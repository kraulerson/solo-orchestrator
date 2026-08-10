#!/usr/bin/env bash
# tests/test-walk006-ci-protection-scope.sh — walk 2026-08-02 ISSUE-006
# (Major): the Phase 1→2 protection backstop must not BLOCK on a CI runner
# that holds no host API credential.
#
# WHY THIS EXISTS
#   Every generated project runs `scripts/check-phase-gate.sh` as its CI
#   governance step (all three host families — see
#   templates/pipelines/ci/{github,gitlab,bitbucket}/*.yml). Branch-protection
#   verification is an AUTHENTICATED API read, and a runner has no credential
#   for it unless the operator exports one:
#     • GitHub Actions puts no token in a step's env, and the built-in
#       GITHUB_TOKEN cannot read branch protection even when mapped (there is
#       no `administration` key in the workflow `permissions:` block).
#     • The generated gitlab/bitbucket governance jobs run `bash:5` + jq/git
#       only — no glab, no curl, no credential.
#   So `[FAIL] Phase 1→2 backstop: protection verification failed` was
#   guaranteed on every push while the identical command exited 0 locally —
#   the documented-but-impossible class (same shape as BL-137). The walker's
#   only escape was SOIF_PHASE_GATES=warn, which downgrades the WHOLE gate.
#
# THE CONTRACT (# WALK-ISSUE-006-CI-PROTECTION-SCOPE)
#   Credential-less CI ($CI set AND no host token env exported, host in
#   github|gitlab|bitbucket): the arm prints a loud WARN that says the check
#   COULD NOT RUN (never "verified") + how to get hard enforcement, and does
#   NOT increment `issues`.
#   Everywhere else the arm is byte-for-byte the old block:
#     • locally (CI unset, TTY or not) — BLOCKS;
#     • in CI WITH a token exported — BLOCKS (that is the hard-enforcement
#       path the generated ci.yml documents);
#     • host="other" — BLOCKS, because its host_verify_protection reads a
#       LOCAL attestation and needs no credential at all.
#
# FIXTURE MECHANICS: the phase-2 shape is the proven rc=0 fixture from
# tests/test-check-phase-gate-backstop-attestation.sh (artifacts seeded so
# unrelated gate arms do not accumulate `issues` and mask this signal),
# plus a PATH-prepended `gh` stub so the real github driver runs with no
# network. `phase2_init.steps_completed` carries remote_repo_created +
# pushed_initial so the BL-116/BL-084 push backstop stays exempt and never
# reaches `git ls-remote` (hermetic: no network anywhere in this file).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (fixtures + manifest reads)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

WARN_SIG="protection verification COULD NOT RUN"
FAIL_SIG="protection verification failed"

# ── Fixture ──────────────────────────────────────────────────────────────────
# mk_proj <dir> <host> <gh-protection-verdict: fail|ok>
mk_proj() {
  local d="$1" host="$2" verdict="$3"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/docs/phase-0" "$d/scripts/lib" "$d/scripts/host-drivers" "$d/bin"
  printf 'frd\n'      > "$d/docs/phase-0/frd.md"
  printf 'journey\n'  > "$d/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$d/docs/phase-0/data-contract.md"

  jq -n --arg h "$host" '{frameworkVersion:"test", host:$h, mode:"personal"}' \
    > "$d/.claude/manifest.json"

  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}
JSON

  # No branch_protection attestation — the backstop must actually run.
  # steps_completed keeps the BL-116/BL-084 push backstop exempt (no ls-remote).
  cat > "$d/.claude/process-state.json" <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial"]},
 "phase1_artifacts":{"data_classification":"public","zdr_attested":false}}
JSON

  cat > "$d/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-01-01 |

## Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |
MD

  {
    echo "# PRODUCT_MANIFESTO"; echo ""
    for i in 1 2 3 4 5 6 7 8; do
      echo "## ${i}. Section ${i}"; echo "Filled content for section ${i}."; echo ""
    done
  } > "$d/PRODUCT_MANIFESTO.md"
  {
    echo "# PROJECT_BIBLE"; echo ""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
      echo "## ${i}. Section ${i}"; echo "Content."; echo ""
    done
  } > "$d/PROJECT_BIBLE.md"

  ( cd "$d" && git init -q \
      && git config user.email t@t.invalid && git config user.name t \
      && git remote add origin https://github.com/example/walk006.git ) || return 1

  cp "$REPO_ROOT/scripts/lib/host.sh" "$d/scripts/lib/"
  cp "$REPO_ROOT/scripts/host-drivers/github.sh" "$d/scripts/host-drivers/"

  # `gh` stub — the ONLY network surface the github driver would touch.
  if [ "$verdict" = ok ]; then
    cat > "$d/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"protection"* ]]; then
  echo '{"allow_force_pushes":{"enabled":false},"enforce_admins":{"enabled":true}}'
  exit 0
fi
exit 0
STUB
  else
    cat > "$d/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"protection"* ]]; then
  echo '{"message":"Not Found","status":"404"}' >&2
  exit 1
fi
exit 0
STUB
  fi
  chmod +x "$d/bin/gh"
}

# run_gate <dir> <script> [env assignments...]
#   With no env assignments the run is LOCAL: `env -u CI` strips any inherited
#   $CI so the local cases stay honest when this suite itself runs in CI.
run_gate() {
  local d="$1" script="$2"; shift 2
  if [ "$#" -eq 0 ]; then
    ( cd "$d" && PATH="$d/bin:$PATH" env -u CI -u GH_TOKEN -u GITHUB_TOKEN \
        bash "$script" </dev/null 2>&1 )
  else
    ( cd "$d" && PATH="$d/bin:$PATH" env -u CI -u GH_TOKEN -u GITHUB_TOKEN "$@" \
        bash "$script" </dev/null 2>&1 )
  fi
}

echo "== tests/test-walk006-ci-protection-scope.sh =="

# ── T1: LOCAL (CI unset) + verify fails → still BLOCKS (byte-for-byte old) ───
echo "=== T1-local-still-blocks ==="
P="$TOPTMP/p1"; mk_proj "$P" github fail
out=$(run_gate "$P" "$SCRIPT"); rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q "$FAIL_SIG" \
   && ! printf '%s' "$out" | grep -q "$WARN_SIG"; then
  pass "T1-local-still-blocks (dev workstation is where the contract binds)"
else
  fail_ "T1-local-still-blocks" "rc=$rc — a failed protection verify MUST still block locally: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
fi

# ── T2: credential-less CI → loud WARN, NO block (the fix) ──────────────────
echo "=== T2-ci-credentialless-warns ==="
P="$TOPTMP/p2"; mk_proj "$P" github fail
out=$(run_gate "$P" "$SCRIPT" CI=true); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "$WARN_SIG" \
   && printf '%s' "$out" | grep -q "WALK-ISSUE-006" \
   && ! printf '%s' "$out" | grep -q "$FAIL_SIG"; then
  pass "T2-ci-credentialless-warns (could-not-run, not verified; gate not blocked)"
else
  fail_ "T2-ci-credentialless-warns" "rc=$rc — the generated CI governance job is STRUCTURALLY unpassable if this blocks: $(printf '%s' "$out" | tail -6 | tr '\n' ' ')"
fi

# ── T2b: the WARN must never claim the contract was satisfied ───────────────
echo "=== T2b-ci-warn-is-honest ==="
if printf '%s' "$out" | grep -q "NOT a pass" \
   && printf '%s' "$out" | grep -q "UNVERIFIED" \
   && ! printf '%s' "$out" | grep -qi "backstop: repo protection verified"; then
  pass "T2b-ci-warn-is-honest (says UNVERIFIED / NOT a pass, never 'verified')"
else
  fail_ "T2b-ci-warn-is-honest" "the exempt arm must not read as a pass: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
fi

# ── T2c: an EMPTY GH_TOKEN is the runtime shape of an UNSET secret ─────────
# The generated workflow maps `GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}`
# LIVE. Before the operator runs --setup-ci-token that secret does not exist,
# and Actions substitutes the EMPTY STRING — GH_TOKEN is SET but empty. If the
# probe tested for set-ness rather than non-emptiness, every generated project
# would hard-fail the moment the mapping shipped. Distinct input from T2.
echo "=== T2c-empty-token-is-absent ==="
P="$TOPTMP/p2c"; mk_proj "$P" github fail
out=$(run_gate "$P" "$SCRIPT" CI=true GH_TOKEN=); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "$WARN_SIG" \
   && ! printf '%s' "$out" | grep -q "$FAIL_SIG"; then
  pass "T2c-empty-token-is-absent (an unset secret substitutes to '' and must read as no credential)"
else
  fail_ "T2c-empty-token-is-absent" "rc=$rc — the live secret mapping would hard-fail every project with no secret set yet: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
fi

# ── T3: CI + an exported token → BLOCKS again (hard-enforcement path) ───────
echo "=== T3-ci-with-token-still-blocks ==="
P="$TOPTMP/p3"; mk_proj "$P" github fail
out=$(run_gate "$P" "$SCRIPT" CI=true GH_TOKEN=ghp_fixture); rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q "$FAIL_SIG" \
   && ! printf '%s' "$out" | grep -q "$WARN_SIG"; then
  pass "T3-ci-with-token-still-blocks (supplying a token re-arms the block)"
else
  fail_ "T3-ci-with-token-still-blocks" "rc=$rc — the exemption is credential-keyed, not CI-keyed alone: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
fi

# ── T3b: GITHUB_TOKEN counts as an exported credential too ──────────────────
echo "=== T3b-ci-github-token-still-blocks ==="
P="$TOPTMP/p3b"; mk_proj "$P" github fail
out=$(run_gate "$P" "$SCRIPT" CI=true GITHUB_TOKEN=ghs_fixture); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$FAIL_SIG"; then
  pass "T3b-ci-github-token-still-blocks"
else
  fail_ "T3b-ci-github-token-still-blocks" "rc=$rc — GITHUB_TOKEN must count as exported: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
fi

# ── T4: host="other" in CI → BLOCKS (its verify needs no credential) ────────
# host=other's host_verify_protection reads .claude/process-state.json's
# branch_protection attestation — absent here, so it fails, and NOTHING about
# that failure is a credential problem. The exemption must not fire.
# origin is re-pointed at a LOCAL bare repo so the BL-084 push backstop's
# `git ls-remote` (which DOES apply to host=other) stays offline.
echo "=== T4-ci-host-other-still-blocks ==="
P="$TOPTMP/p4"; mk_proj "$P" other fail
git init -q --bare "$TOPTMP/bare.git"
( cd "$P" && git remote set-url origin "$TOPTMP/bare.git" )
out=$(run_gate "$P" "$SCRIPT" CI=true); rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q "$FAIL_SIG" \
   && ! printf '%s' "$out" | grep -q "$WARN_SIG"; then
  pass "T4-ci-host-other-still-blocks (local-attestation verify is not credential-gated)"
else
  fail_ "T4-ci-host-other-still-blocks" "rc=$rc — 'other' must never be exempted: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
fi

# ── T5: CI + protection genuinely verifies → OK, arm never reached ─────────
echo "=== T5-ci-verified-clean ==="
P="$TOPTMP/p5"; mk_proj "$P" github ok
out=$(run_gate "$P" "$SCRIPT" CI=true); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "backstop: repo protection verified" \
   && ! printf '%s' "$out" | grep -q "$WARN_SIG"; then
  pass "T5-ci-verified-clean (baseline: the arm does not fire when verify passes)"
else
  fail_ "T5-ci-verified-clean" "rc=$rc — baseline fixture not clean; T2's signal would be unattributable: $(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
fi

# ── Mutants ────────────────────────────────────────────────────────────────
# Each mutant is a lib-complete COPY of the script (the bl104 vacuous-mutant
# trap: a mutant that merely crashes proves nothing), asserted POSITIVELY in
# both directions.
mk_mutant() {  # mk_mutant <name> <sed-expr>
  # bash-3.2: a single `local a=$1 b=$a` expands ALL words before assigning,
  # so `$m` gets its own statement.
  local name="$1"
  local expr="$2"
  local m="$TOPTMP/mut-$name"
  mkdir -p "$m/scripts/lib"
  sed "$expr" "$SCRIPT" > "$m/scripts/check-phase-gate.sh"
  chmod +x "$m/scripts/check-phase-gate.sh"
  cp "$REPO_ROOT/scripts/lib/"*.sh "$m/scripts/lib/"
  echo "$m/scripts/check-phase-gate.sh"
}

# M1 — delete the $CI key line: the guard stops distinguishing CI from local,
# so the LOCAL block (T1) evaporates. Proves the key is load-bearing and that
# it is $CI, not TTY, that scopes the exemption.
echo "=== M1-mutant-drop-CI-key ==="
M1=$(mk_mutant m1 '/# WALK-ISSUE-006-CI-KEY$/d')
if grep -q 'WALK-ISSUE-006-CI-KEY' "$M1"; then
  fail_ "M1-mutant-drop-CI-key" "sed did not remove the keyed line — mutant is vacuous"
else
  P="$TOPTMP/pm1"; mk_proj "$P" github fail
  out=$(run_gate "$P" "$M1"); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "$WARN_SIG"; then
    pass "M1-mutant-drop-CI-key (without the \$CI key the LOCAL run stops blocking — the key carries T1)"
  else
    fail_ "M1-mutant-drop-CI-key" "rc=$rc — mutant still blocked locally; the \$CI key is not what scopes the exemption: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
  fi
fi

# M2 — neuter the credential probe (github arm always says "no credential"):
# T3's block evaporates. Proves the token probe, not $CI alone, gates the
# exemption — i.e. the documented hard-enforcement path is real.
echo "=== M2-mutant-blind-token-probe ==="
M2=$(mk_mutant m2 's/^\( *\)github)    \[ -z .*$/\1github)    true ;;/')
if grep -q 'github)    true ;;' "$M2"; then
  P="$TOPTMP/pm2"; mk_proj "$P" github fail
  out=$(run_gate "$P" "$M2" CI=true GH_TOKEN=ghp_fixture); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "$WARN_SIG"; then
    pass "M2-mutant-blind-token-probe (blind to GH_TOKEN, the mutant exempts a credentialed runner — the probe carries T3)"
  else
    fail_ "M2-mutant-blind-token-probe" "rc=$rc — mutant still blocked with a token; the probe is not what T3 measures: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
  fi
else
  fail_ "M2-mutant-blind-token-probe" "sed did not rewrite the github arm — mutant is vacuous"
fi

# M3 — pre-fix reproduction: force the guard to false, restoring the exact
# block this walk finding is about. The credential-less CI run must fail with
# the walker's verbatim message.
echo "=== M3-mutant-prefix-repro ==="
M3=$(mk_mutant m3 's/^\( *\)if _cpg_walk006_credentialless_ci .*$/\1if false; then/')
if grep -q 'if false; then' "$M3"; then
  P="$TOPTMP/pm3"; mk_proj "$P" github fail
  out=$(run_gate "$P" "$M3" CI=true); rc=$?
  if [ "$rc" -ne 0 ] \
     && printf '%s' "$out" | grep -q "$FAIL_SIG" \
     && ! printf '%s' "$out" | grep -q "$WARN_SIG"; then
    pass "M3-mutant-prefix-repro (pre-fix arm reproduces ISSUE-006 verbatim on a credential-less runner)"
  else
    fail_ "M3-mutant-prefix-repro" "rc=$rc — the pre-fix shape did NOT reproduce the walk failure, so T2 proves nothing: $(printf '%s' "$out" | grep -i backstop | tr '\n' ' ')"
  fi
else
  fail_ "M3-mutant-prefix-repro" "sed did not rewrite the guard call — mutant is vacuous"
fi

# ════════════════════════════════════════════════════════════════════════════
# PART 2 — the way BACK to enforcement: `check-gate.sh --setup-ci-token`
# (# WALK-ISSUE-006-SETUP-CI-TOKEN)
#
# Part 1 above stops a structurally-impossible check from blocking. It does NOT
# restore the check, and a permanently-warning check is a check on its way to
# being ignored — so the token path is RECOMMENDED, and guided end to end. This
# section pins the walkthrough's contract and, critically, the LINK between its
# output and the gate's input: the secret it stores must be the one the emitted
# workflow maps, or the walkthrough writes a secret nothing reads.
# ════════════════════════════════════════════════════════════════════════════
CHECK_GATE="$REPO_ROOT/scripts/check-gate.sh"
GOOD_TOKEN="ghp_walk006_good"
BAD_TOKEN="ghp_walk006_bad"

# mk_tok <dir> <host> <auth: ok|unauth> [ci.yml shape: yes|no|swallow|emitted|custom] [run-line]
# `custom` writes an arbitrary phase-gate `run:` line, which is how the F-015
# allowlist gets driven against swallow shapes nobody enumerated. `emitted` is
# the byte-shape the templates actually ship (guard + bare invocation, block
# scalar) — the false-positive guard.
mk_tok() {
  local d="$1" host="$2" auth="$3" wired="${4:-yes}" run_line="${5:-}"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/scripts/host-drivers" "$d/bin" "$d/stub" \
           "$d/.github/workflows"
  jq -n --arg h "$host" '{frameworkVersion:"test", host:$h, mode:"personal"}' \
    > "$d/.claude/manifest.json"
  ( cd "$d" && git init -q \
      && git config user.email t@t.invalid && git config user.name t \
      && git remote add origin https://github.com/example/walk006.git ) || return 1
  cp "$REPO_ROOT/scripts/lib/"*.sh "$d/scripts/lib/"
  cp "$REPO_ROOT/scripts/host-drivers/github.sh" "$d/scripts/host-drivers/"
  printf '%s' "$GOOD_TOKEN" > "$d/stub/goodtoken"
  [ "$auth" = unauth ] && : > "$d/stub/unauth"
  : > "$d/stub/gh.log"
  case "$wired" in
    yes)
      printf 'jobs:\n  test:\n    steps:\n      - name: Governance - Phase gate check\n        env:\n          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n        run: |\n          bash scripts/check-phase-gate.sh\n' \
        > "$d/.github/workflows/ci.yml" ;;
    swallow)
      # The pre-R-1 shape a project scaffolded before this fix still carries:
      # the secret IS mapped, but the gate's exit code is thrown away.
      printf 'jobs:\n  test:\n    steps:\n      - name: Governance - Phase gate check\n        env:\n          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n        run: bash scripts/check-phase-gate.sh 2>/dev/null || echo "Phase gate check script not found"\n' \
        > "$d/.github/workflows/ci.yml" ;;
    emitted)
      # Byte-for-byte the shape templates/pipelines/ci/github/*.yml ships: the
      # existence guard AND the bare invocation, in a block scalar. The
      # allowlist must accept BOTH lines — a detector that warns about the
      # emitted workflow is worse than one that misses a swallow.
      printf 'jobs:\n  test:\n    steps:\n      - name: Governance - Phase gate check\n        env:\n          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n        run: |\n          if [ ! -f scripts/check-phase-gate.sh ]; then\n            echo "::error::Phase gate check script missing. Framework integrity compromised."\n            exit 1\n          fi\n          bash scripts/check-phase-gate.sh\n' \
        > "$d/.github/workflows/ci.yml" ;;
    custom)
      printf 'jobs:\n  test:\n    steps:\n      - name: Governance - Phase gate check\n        env:\n          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n        run: %s\n' "$run_line" \
        > "$d/.github/workflows/ci.yml" ;;
    *)
      printf 'jobs:\n  test:\n    steps:\n      - name: Governance - Phase gate check\n' \
        > "$d/.github/workflows/ci.yml" ;;
  esac
  cat > "$d/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_DIR/gh.log"
case "$1 ${2:-}" in
  "auth status") [ -f "$GH_STUB_DIR/unauth" ] && exit 1; exit 0 ;;
  "secret set")
      # value arrives on STDIN, never argv — record what we were handed
      value=$(cat)
      printf 'STDIN:%s\n' "$value" >> "$GH_STUB_DIR/gh.log"
      printf '%s\n' "$3" > "$GH_STUB_DIR/stored"
      exit 0 ;;
  "secret list")
      [ -f "$GH_STUB_DIR/stored" ] && { printf '%s\tUpdated\n' "$(cat "$GH_STUB_DIR/stored")"; exit 0; }
      exit 0 ;;
esac
case "$*" in
  *protection*)
      # the probe passes ONLY when the caller actually exported the good token
      if [ "${GH_TOKEN:-}" = "$(cat "$GH_STUB_DIR/goodtoken")" ]; then
        echo '{"allow_force_pushes":{"enabled":false},"enforce_admins":{"enabled":true}}'; exit 0
      fi
      echo '{"message":"Resource not accessible by personal access token","status":"403"}' >&2
      exit 1 ;;
esac
exit 0
STUB
  chmod +x "$d/bin/gh"
}

# run_tok <dir> <token-or-EMPTY> [args...]
run_tok() {
  local d="$1" tok="$2"; shift 2
  if [ "$tok" = EMPTY ]; then
    ( cd "$d" && PATH="$d/bin:$PATH" GH_STUB_DIR="$d/stub" \
        env -u SOIF_PROTECTION_TOKEN bash "$CHECK_GATE" --setup-ci-token "$@" </dev/null 2>&1 )
  else
    ( cd "$d" && PATH="$d/bin:$PATH" GH_STUB_DIR="$d/stub" \
        env SOIF_PROTECTION_TOKEN="$tok" bash "$CHECK_GATE" --setup-ci-token "$@" </dev/null 2>&1 )
  fi
}

# run_tok_with <script> <dir> <token> [args...] — run_tok against a MUTANT copy
# of check-gate.sh. The copy is lib-complete (check-gate sources
# scripts/lib/helpers-core.sh relative to its own path) and the host driver is
# read from the fixture project, exactly as in the real run.
run_tok_with() {
  local s="$1" d="$2" tok="$3"; shift 3
  ( cd "$d" && PATH="$d/bin:$PATH" GH_STUB_DIR="$d/stub" \
      env SOIF_PROTECTION_TOKEN="$tok" bash "$s" --setup-ci-token "$@" </dev/null 2>&1 )
}

# mk_cg_mutant <name> <anchored-marker-ERE> <sed-expr> <exp-removed> <exp-added>
# Sets CG_MUT to the mutant path on success; sets CG_WHY and returns 1 on
# failure. Asserts the mutation-harness invariants the same way the rest of this
# wave does: sites==1, exactly-N-lines-changed, and `bash -n` on the result — a
# mutant that merely fails to parse proves nothing.
CG_MUT=""; CG_WHY=""
mk_cg_mutant() {
  local name="$1" ere="$2" expr="$3" exp_rm="$4" exp_add="$5"
  CG_MUT=""; CG_WHY=""
  local m="$TOPTMP/cgmut-$name"
  rm -rf "$m"; mkdir -p "$m/scripts/lib" || { CG_WHY="mkdir failed"; return 1; }
  local sites
  sites=$(grep -Ec "$ere" "$CHECK_GATE")
  if [ "$sites" -ne 1 ]; then
    CG_WHY="sites==$sites for /$ere/ in scripts/check-gate.sh (expected exactly 1) — the mutant is ambiguous or vacuous"
    return 1
  fi
  sed "$expr" "$CHECK_GATE" > "$m/scripts/check-gate.sh" || { CG_WHY="sed failed"; return 1; }
  cp "$REPO_ROOT/scripts/lib/"*.sh "$m/scripts/lib/" || { CG_WHY="lib copy failed"; return 1; }
  local n_rm n_add
  n_rm=$(diff "$CHECK_GATE" "$m/scripts/check-gate.sh" | grep -c '^<')
  n_add=$(diff "$CHECK_GATE" "$m/scripts/check-gate.sh" | grep -c '^>')
  if [ "$n_rm" -ne "$exp_rm" ] || [ "$n_add" -ne "$exp_add" ]; then
    CG_WHY="the edit changed $n_rm removed / $n_add added lines (expected $exp_rm / $exp_add)"
    return 1
  fi
  if ! bash -n "$m/scripts/check-gate.sh" 2>"$m/bn.txt"; then
    CG_WHY="the mutant is not valid bash: $(tr '\n' ' ' < "$m/bn.txt")"
    return 1
  fi
  CG_MUT="$m/scripts/check-gate.sh"
  return 0
}

# ── D-A fixture writer (Karl 2026-08-09) ────────────────────────────────────
# mk_wf <out> <job-extra-keys> <step-keys> <mapped:yes|no> <body:emitted|nogate>
#       [extra-steps]
# Writes a COMPLETE, structurally-valid github workflow whose phase-gate step is
# the shape templates/pipelines/ci/github/*.yml ships, differing from it only by
# what the caller splices in. One writer for every structural case below, so a
# refusal is attributable to exactly one cause and "withheld alone" means what
# it says.
#
# <step-keys> is the WHOLE step key block, not an addition to a fixed one: an
# `if:` case must REPLACE the shipped condition rather than sit beside it as a
# duplicate YAML key, which would be a malformed fixture testing nothing.
STEP_KEYS_GOOD="        if: hashFiles('.claude/phase-state.json') != ''"
mk_wf() {
  local out="$1" jobkeys="$2" stepkeys="$3" mapped="$4" body="$5" extra="${6:-}"
  {
    printf 'name: CI\n'
    printf 'on:\n  push:\n    branches: [main]\n  pull_request:\n    branches: [main]\n\n'
    printf 'jobs:\n  test:\n    runs-on: ubuntu-latest\n'
    [ -n "$jobkeys" ] && printf '%s\n' "$jobkeys"
    printf '    steps:\n'
    printf '      - name: Governance - Phase gate check\n'
    [ -n "$stepkeys" ] && printf '%s\n' "$stepkeys"
    if [ "$mapped" = yes ]; then
      printf '        env:\n          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n'
    fi
    printf '        run: |\n'
    if [ "$body" = emitted ]; then
      printf '          if [ ! -f scripts/check-phase-gate.sh ]; then\n'
      printf '            echo "::error::Phase gate check script missing. Framework integrity compromised."\n'
      printf '            exit 1\n'
      printf '          fi\n'
      printf '          bash scripts/check-phase-gate.sh\n'
    else
      printf '          npm test\n'
    fi
    [ -n "$extra" ] && printf '%s\n' "$extra"
  } > "$out"
  return 0
}

# mk_tok_wf <dir> <mk_wf args…> — a fixture PROJECT (manifest, git, gh stub)
# whose ci.yml is written by mk_wf. Every fixture lives under $TOPTMP; nothing
# here reads or writes the host filesystem, and no probe resolves a path
# relative to the fixture's parent (the `../../..` trap: from a mktemp dir that
# is /var/folders on macOS and / on Ubuntu, so a probe there is unfalsifiable in
# both directions).
mk_tok_wf() {
  local d="$1"; shift
  mk_tok "$d" github ok yes || return 1
  mk_wf "$d/.github/workflows/ci.yml" "$@"
}

# mk_raw_wf <dir> — a fixture PROJECT whose ci.yml is read VERBATIM from stdin.
# mk_wf writes one canonical shape with splice points, which is right when the
# thing under test is a step key. The round-2 findings are about the SHAPE of the
# file itself — a lone `-` sequence item, a folded scalar, a comment on the
# `steps:` anchor, a secret in a different step — so those fixtures have to be
# written out whole. Quoted heredocs throughout: `${{ secrets.… }}` must reach
# the file as those bytes, and an unquoted heredoc would not survive `${{`.
mk_raw_wf() {
  local d="$1"
  mk_tok "$d" github ok yes || return 1
  cat > "$d/.github/workflows/ci.yml"
}

# ── CRLF fixture mechanics (R-dA-1) ─────────────────────────────────────────
# The bytes are WRITTEN, never described. `awk … %c,13` rather than
# `sed 's/$/\r/'` because BSD sed inserts a literal `r` for that escape, which
# would produce a fixture that merely LOOKS like CRLF in the source of this file
# — the exact vacuity these proofs exist to prevent. n_cr() counts the actual CR
# bytes so every CRLF case can assert its own premise before asserting anything
# else.
to_crlf() { awk '{ printf "%s%c\n", $0, 13 }' "$1" > "$2"; }
n_cr()    { tr -dc '\r' < "$1" | wc -c | tr -d ' '; }

# mk_tok_wf_crlf <dir> <mk_wf args…> — mk_tok_wf, then rewrite ci.yml with CRLF
# line terminators. Nothing else about the fixture differs, so a difference in
# verdict is attributable to the line endings and to nothing else.
mk_tok_wf_crlf() {
  local d="$1"; shift
  mk_tok_wf "$d" "$@" || return 1
  local w="$d/.github/workflows/ci.yml"
  to_crlf "$w" "$w.crlf" && mv "$w.crlf" "$w"
}

# The legacy leftover: the emitted step, plus the pre-R-1 soft step a project
# upgraded from an older vintage still carries. The ONLY thing wrong with it is
# the deviating gate line — it maps, and it does carry a real invocation — which
# is what makes it the right fixture for the allowlist's dual-direction proof.
WF_LEGACY_STEP='      - name: Governance - Phase gate check (legacy)
        run: bash scripts/check-phase-gate.sh 2>/dev/null || echo "skipping"'

# assert_withheld <case> <dir> <cause-signature> <why>
#   Three assertions, not one: the claim is withheld, the refusal SAYS it is
#   withholding, and it NAMES the cause. A refusal that does not name its cause
#   is the 3am-lane defect this wave already fixed once, so "it printed
#   something" is not the bar.
assert_withheld() {
  local case_name="$1" d="$2" sig="$3" why="$4"
  local out rc
  out=$(run_tok "$d" "$GOOD_TOKEN"); rc=$?
  if [ "$rc" -eq 0 ] \
     && ! printf '%s' "$out" | grep -q "The next push enforces the check" \
     && printf '%s' "$out" | grep -qF "will NOT enforce the check on the next push" \
     && printf '%s' "$out" | grep -qF -- "$sig"; then
    pass "$case_name ($why)"
  else
    fail_ "$case_name" "rc=$rc — expected the claim WITHHELD and the cause named [$sig], got: $(printf '%s' "$out" | grep -E 'next push|WILL NOT|^  - ' | tr '\n' ' ')"
  fi
}

# assert_earns_ok <case> <dir> <why> — the false-positive direction. A hardened
# detector that reds correct setups is worse than the weak one it replaced.
assert_earns_ok() {
  local case_name="$1" d="$2" why="$3"
  local out rc
  out=$(run_tok "$d" "$GOOD_TOKEN"); rc=$?
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | grep -q "The next push enforces the check" \
     && ! printf '%s' "$out" | grep -q "will NOT enforce"; then
    pass "$case_name ($why)"
  else
    fail_ "$case_name" "rc=$rc — a LEGITIMATE setup was refused: $(printf '%s' "$out" | grep -E 'next push|WILL NOT|^  - ' | tr '\n' ' ')"
  fi
}

# assert_mutant_false_ok <case> <mut> <ere> <sed> <rm> <add> <dir> <sig> <why>
#   Dual direction: with this one line neutered, the fixture that was just
#   refused earns the full enforcement claim — the exact false statement the
#   line exists to prevent. The verdict is CONDITIONAL on observing the thing it
#   judges: the claim must appear AND the cause signature must be gone, so a
#   mutant that merely broke something else cannot pass.
assert_mutant_false_ok() {
  local case_name="$1" mut="$2" ere="$3" expr="$4" n_rm="$5" n_add="$6" d="$7" sig="$8" why="$9"
  if ! mk_cg_mutant "$mut" "$ere" "$expr" "$n_rm" "$n_add"; then
    fail_ "$case_name" "$CG_WHY"
    return
  fi
  local out rc
  out=$(run_tok_with "$CG_MUT" "$d" "$GOOD_TOKEN"); rc=$?
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | grep -q "The next push enforces the check" \
     && ! printf '%s' "$out" | grep -qF -- "$sig"; then
    pass "$case_name ($why)"
  else
    fail_ "$case_name" "rc=$rc — the neutered detector did not produce the false OK, so the positive case may be measuring something else: $(printf '%s' "$out" | grep -E 'next push|WILL NOT|^  - ' | tr '\n' ' ')"
  fi
}

# assert_mutant_false_ok_ctl <case> <mut> <ere> <sed> <rm> <add> <dir> <sig>
#                            <ctl-dir> <ctl-sig> <why>
#   assert_mutant_false_ok PLUS a liveness discriminator, required for every
#   mutant that edits the awk program inside _wf_gate_scope. `bash -n` only
#   parses the SHELL: an awk program mangled into a syntax error still passes it,
#   and a dead awk prints nothing, which reads downstream as "no swallowing key
#   found" — i.e. the false OK, for entirely the wrong reason. So the same mutant
#   is also driven against a control fixture whose swallow is spelled the ORDINARY
#   way, and that one must STILL be refused with its own cause named. Only then
#   is the false OK attributable to the removed line.
assert_mutant_false_ok_ctl() {
  local case_name="$1" mut="$2" ere="$3" expr="$4" n_rm="$5" n_add="$6" d="$7" sig="$8"
  local ctl="${9}" ctl_sig="${10}" why="${11}"
  if ! mk_cg_mutant "$mut" "$ere" "$expr" "$n_rm" "$n_add"; then
    fail_ "$case_name" "$CG_WHY"
    return
  fi
  local out rc cout crc
  out=$(run_tok_with "$CG_MUT" "$d" "$GOOD_TOKEN"); rc=$?
  cout=$(run_tok_with "$CG_MUT" "$ctl" "$GOOD_TOKEN"); crc=$?
  if [ "$crc" -ne 0 ] \
     || printf '%s' "$cout" | grep -q "The next push enforces the check" \
     || ! printf '%s' "$cout" | grep -qF -- "$ctl_sig"; then
    fail_ "$case_name" "the mutant stopped detecting the ORDINARY spelling too (crc=$crc), so it did not isolate one line — most likely the awk program no longer runs: $(printf '%s' "$cout" | grep -E 'next push|WILL NOT|^  - ' | tr '\n' ' ')"
    return
  fi
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | grep -q "The next push enforces the check" \
     && ! printf '%s' "$out" | grep -qF -- "$sig"; then
    pass "$case_name ($why)"
  else
    fail_ "$case_name" "rc=$rc — the neutered detector did not produce the false OK, so the positive case may be measuring something else: $(printf '%s' "$out" | grep -E 'next push|WILL NOT|^  - ' | tr '\n' ' ')"
  fi
}

# assert_mutant_refuses <case> <mut> <ere> <sed> <rm> <add> <dir> <sig> <why>
#   The INVERTED mutation direction, for a line whose job is to prevent a false
#   RED rather than a false OK. Neuter it and a LEGITIMATE setup is refused —
#   and refused with a named cause, so a mutant that broke something unrelated
#   cannot pass. (R-dA-1: the CRLF strip is that kind of line.)
assert_mutant_refuses() {
  local case_name="$1" mut="$2" ere="$3" expr="$4" n_rm="$5" n_add="$6" d="$7" sig="$8" why="$9"
  if ! mk_cg_mutant "$mut" "$ere" "$expr" "$n_rm" "$n_add"; then
    fail_ "$case_name" "$CG_WHY"
    return
  fi
  local out rc
  out=$(run_tok_with "$CG_MUT" "$d" "$GOOD_TOKEN"); rc=$?
  if [ "$rc" -eq 0 ] \
     && ! printf '%s' "$out" | grep -q "The next push enforces the check" \
     && printf '%s' "$out" | grep -qF -- "$sig"; then
    pass "$case_name ($why)"
  else
    fail_ "$case_name" "rc=$rc — with that line neutered the legitimate fixture was NOT falsely refused for the named reason [$sig], so the positive case is not measuring the line it claims to: $(printf '%s' "$out" | grep -E 'next push|WILL NOT|^  - ' | tr '\n' ' ')"
  fi
}

# assert_mutant_drops_cause <case> <mut> <ere> <sed> <rm> <add> <dir> <sig>
#                           <why>
#   The THIRD mutation direction, for a line that decides WHICH CAUSE is named
#   rather than whether the claim is withheld. Both of round 2's cases are real:
#   `grep -cxF` vs `grep -cF` on the invokes floor cannot change the verdict (a
#   line that is a strict superstring of the invocation is always caught by the
#   deviation scan as well), and a naive comment strip cannot change the verdict
#   either (proved below at D40). What they DO change is what the user is told,
#   and "a refusal that does not name its cause" is the defect this whole wave
#   exists to fix — so the bullet set is contract, and it is pinned as one. The
#   mutant must therefore still WITHHOLD (proving it did not simply break the
#   detector) while the named cause is GONE.
assert_mutant_drops_cause() {
  local case_name="$1" mut="$2" ere="$3" expr="$4" n_rm="$5" n_add="$6" d="$7" sig="$8" why="$9"
  if ! mk_cg_mutant "$mut" "$ere" "$expr" "$n_rm" "$n_add"; then
    fail_ "$case_name" "$CG_WHY"
    return
  fi
  local out rc
  out=$(run_tok_with "$CG_MUT" "$d" "$GOOD_TOKEN"); rc=$?
  if [ "$rc" -eq 0 ] \
     && ! printf '%s' "$out" | grep -q "The next push enforces the check" \
     && printf '%s' "$out" | grep -qF "will NOT enforce the check on the next push" \
     && ! printf '%s' "$out" | grep -qF -- "$sig"; then
    pass "$case_name ($why)"
  else
    fail_ "$case_name" "rc=$rc — expected the claim still WITHHELD but the cause [$sig] no longer named; got: $(printf '%s' "$out" | grep -E 'next push|WILL NOT|^  - ' | tr '\n' ' ')"
  fi
}

# ── S1: non-github host → NOT APPLICABLE + the manual per-host steps ───────
echo "=== S1-non-github-not-applicable ==="
P="$TOPTMP/s1"; mk_tok "$P" gitlab ok
out=$(run_tok "$P" EMPTY); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "NOT APPLICABLE" \
   && printf '%s' "$out" | grep -q "GITLAB_TOKEN" \
   && printf '%s' "$out" | grep -q "glab"; then
  pass "S1-non-github-not-applicable (prints the GitLab steps, incl. the glab half)"
else
  fail_ "S1-non-github-not-applicable" "rc=$rc: $out"
fi

# ── S2: gh not authenticated → refuse with the actionable next step ────────
echo "=== S2-gh-unauthenticated ==="
P="$TOPTMP/s2"; mk_tok "$P" github unauth
out=$(run_tok "$P" "$GOOD_TOKEN"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "gh auth login"; then
  pass "S2-gh-unauthenticated (refuses, names the fix)"
else
  fail_ "S2-gh-unauthenticated" "rc=$rc: $out"
fi

# ── S3: happy path — explains, verifies, stores, confirms the wiring ───────
echo "=== S3-happy-path ==="
P="$TOPTMP/s3"; mk_tok "$P" github ok yes
out=$(run_tok "$P" "$GOOD_TOKEN"); rc=$?
log=$(cat "$P/stub/gh.log")
ok=1
[ "$rc" -eq 0 ] || ok=0
printf '%s' "$out" | grep -q "Administration: \*\*Read-only\*\*" || ok=0
printf '%s' "$out" | grep -q "Token verified" || ok=0
printf '%s' "$log" | grep -q "^secret set SOIF_PROTECTION_TOKEN --repo example/walk006$" || ok=0
printf '%s' "$log" | grep -q "^STDIN:$GOOD_TOKEN$" || ok=0
printf '%s' "$out" | grep -q "maps SOIF_PROTECTION_TOKEN into the phase-gate step" || ok=0
if [ "$ok" -eq 1 ]; then
  pass "S3-happy-path (least-privilege explained, token probed, secret stored, wiring confirmed)"
else
  fail_ "S3-happy-path" "rc=$rc log=[$(printf '%s' "$log" | tr '\n' ';')] out=$out"
fi

# ── S3b: the secret VALUE never appears on argv ────────────────────────────
# `ps` exposes argv to every process on the box. The value must ride stdin.
echo "=== S3b-secret-not-on-argv ==="
if printf '%s' "$log" | grep -v '^STDIN:' | grep -q "$GOOD_TOKEN"; then
  fail_ "S3b-secret-not-on-argv" "the token value appeared in a gh ARGV line: $(printf '%s' "$log" | grep -v '^STDIN:' | grep "$GOOD_TOKEN")"
else
  pass "S3b-secret-not-on-argv (value rides stdin; argv carries only the secret NAME)"
fi

# ── S4: a token that cannot read protection is REFUSED, nothing stored ────
# Storing a powerless token would convert today's honest WARN into a hard FAIL
# — strictly worse than the state we started in.
echo "=== S4-powerless-token-refused ==="
P="$TOPTMP/s4"; mk_tok "$P" github ok yes
out=$(run_tok "$P" "$BAD_TOKEN"); rc=$?
log=$(cat "$P/stub/gh.log")
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q "could NOT read branch protection" \
   && printf '%s' "$out" | grep -q "Administration: Read-only" \
   && ! printf '%s' "$log" | grep -q "^secret set"; then
  pass "S4-powerless-token-refused (fails closed — verify BEFORE store)"
else
  fail_ "S4-powerless-token-refused" "rc=$rc log=[$(printf '%s' "$log" | tr '\n' ';')] out=$out"
fi

# ── S5: --skip-verify is the explicit, named escape ────────────────────────
echo "=== S5-skip-verify-stores ==="
P="$TOPTMP/s5"; mk_tok "$P" github ok yes
out=$(run_tok "$P" "$BAD_TOKEN" --skip-verify); rc=$?
if [ "$rc" -eq 0 ] && grep -q "^secret set SOIF_PROTECTION_TOKEN" "$P/stub/gh.log"; then
  pass "S5-skip-verify-stores (the escape exists and is opt-in only)"
else
  fail_ "S5-skip-verify-stores" "rc=$rc: $out"
fi

# ── S6: an unwired workflow is CALLED OUT, not silently succeeded ──────────
# A project scaffolded before the mapping shipped would otherwise get a secret
# nothing reads — a silent no-op wearing a success message.
echo "=== S6-unwired-workflow-warned ==="
P="$TOPTMP/s6"; mk_tok "$P" github ok no
out=$(run_tok "$P" "$GOOD_TOKEN"); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
   && printf '%s' "$out" | grep -q 'GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}'; then
  pass "S6-unwired-workflow-warned (names the gap and prints the exact lines to add)"
else
  fail_ "S6-unwired-workflow-warned" "rc=$rc: $out"
fi

# ── S6c (adversarial review R-1): a mapped secret + a SWALLOWED exit code is
# not enforcement, and this command must not claim it is. The reviewer's probe
# showed the gate printing [FAIL] and exiting 1 while the step graded GREEN, so
# on a project carrying the pre-R-1 `|| echo` shape the walkthrough must say the
# token cannot enforce anything yet — and print the replacement run: block.
echo "=== S6c-swallowed-exit-code-warned ==="
P="$TOPTMP/s6c"; mk_tok "$P" github ok swallow
out=$(run_tok "$P" "$GOOD_TOKEN"); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "DISCARDS the gate's exit code" \
   && printf '%s' "$out" | grep -q 'bash scripts/check-phase-gate.sh' \
   && ! printf '%s' "$out" | grep -q "The next push enforces the check"; then
  pass "S6c-swallowed-exit-code-warned (never claims enforcement over a swallowed verdict)"
else
  fail_ "S6c-swallowed-exit-code-warned" "rc=$rc: $out"
fi

# ── S6d: the enforcement claim is made ONLY when both conditions hold ─────
echo "=== S6d-enforcement-claim-is-earned ==="
P="$TOPTMP/s6d"; mk_tok "$P" github ok yes
out=$(run_tok "$P" "$GOOD_TOKEN"); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "lets the gate's exit code decide it" \
   && printf '%s' "$out" | grep -q "The next push enforces the check"; then
  pass "S6d-enforcement-claim-is-earned (mapped AND exit-code-honouring -> the claim is true)"
else
  fail_ "S6d-enforcement-claim-is-earned" "rc=$rc: $out"
fi

# ════════════════════════════════════════════════════════════════════════════
# S6e-S6k (F-015, Karl 2026-08-09 — "Harden it"): the project-side detector is
# an ALLOWLIST too.
#
# The check above used to ask whether the workflow's gate line matched a list of
# FORBIDDEN shapes — `\|\|[[:space:]]*(echo|true|:)`. BUG-009's confirm review
# (R-C1) proved the sibling pin in bl147 let `|| exit 0` through for exactly
# that reason, and this one was narrower still (no `;` arm at all). So it now
# states what is PERMITTED: an executable line naming the gate script may be the
# bare invocation or the existence guard the emitted templates wrap it in, and
# nothing else. Normalization is limited to what cannot change what bash runs —
# indentation, a YAML sequence dash, the `run:` key of an inline scalar,
# trailing blanks.
#
# Every case below is a shape nobody enumerated, and each is a REAL discard of
# the gate's verdict, not a cosmetic difference. The assertion is that the
# walkthrough refuses for the RIGHT REASON — it names the discarded exit code
# and withholds the enforcement claim — never merely that it printed something.
# ════════════════════════════════════════════════════════════════════════════

# assert_swallow_warned <case> <fixture-tag> <run-line> <why>
assert_swallow_warned() {
  local case_name="$1" tag="$2" line="$3" why="$4"
  # The tamper must be valid shell. A shape that cannot run is a typo, and a
  # detector catching typos would prove nothing about swallows.
  if ! printf '%s\n' "$line" | bash -n 2>"$TOPTMP/bn-$tag"; then
    fail_ "$case_name" "the fixture's run: line is not valid bash, so it is a typo rather than a swallow: $(tr '\n' ' ' < "$TOPTMP/bn-$tag")"
    return
  fi
  local P="$TOPTMP/$tag"
  mk_tok "$P" github ok custom "$line"
  local out rc
  out=$(run_tok "$P" "$GOOD_TOKEN"); rc=$?
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | grep -q "DISCARDS the gate's exit code" \
     && ! printf '%s' "$out" | grep -q "The next push enforces the check"; then
    pass "$case_name ($why)"
  else
    fail_ "$case_name" "rc=$rc — the allowlist did not refuse '$line': $(printf '%s' "$out" | grep -E 'phase-gate step|next push|maps SOIF' | tr '\n' ' ')"
  fi
}

echo "=== S6e-allowlist-refuses-or-exit ==="
assert_swallow_warned S6e-allowlist-refuses-or-exit s6e \
  'bash scripts/check-phase-gate.sh || exit 0' \
  'the R-C1 escape: `exit` was never in the old alternation'

echo "=== S6f-allowlist-refuses-pipe ==="
assert_swallow_warned S6f-allowlist-refuses-pipe s6f \
  'bash scripts/check-phase-gate.sh | cat' \
  "a pipe: the status reported is cat's, never the gate's"

echo "=== S6g-allowlist-refuses-background ==="
assert_swallow_warned S6g-allowlist-refuses-background s6g \
  'bash scripts/check-phase-gate.sh &' \
  'a trailing `&`: the step exits 0 before the gate has decided anything'

echo "=== S6h-allowlist-refuses-interpreter-swap ==="
assert_swallow_warned S6h-allowlist-refuses-interpreter-swap s6h \
  'sh scripts/check-phase-gate.sh; exit 0' \
  'a different interpreter: the old pre-filter required the literal `bash `, so this line was never even inspected'

echo "=== S6i-allowlist-refuses-wrapper ==="
assert_swallow_warned S6i-allowlist-refuses-wrapper s6i \
  'if ! bash scripts/check-phase-gate.sh; then echo "::warning::soft"; fi' \
  'an `if !` wrapper: the compound command succeeds however the gate votes'

echo "=== S6j-allowlist-refuses-trailing-command ==="
assert_swallow_warned S6j-allowlist-refuses-trailing-command s6j \
  'bash scripts/check-phase-gate.sh; echo "phase gate step complete"' \
  'a command after the invocation: the last command owns the exit status'

# ── S6k: the EMITTED shape is not a swallow ────────────────────────────────
# The false-positive guard, and the reason the allowlist permits two spellings
# rather than one: every shipped template wraps the bare invocation in an
# existence guard that also names the script. A detector that warned about the
# workflow the framework itself writes would be worse than the blacklist.
echo "=== S6k-allowlist-accepts-the-emitted-shape ==="
P="$TOPTMP/s6k"; mk_tok "$P" github ok emitted
out=$(run_tok "$P" "$GOOD_TOKEN"); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q "The next push enforces the check" \
   && ! printf '%s' "$out" | grep -q "DISCARDS the gate's exit code"; then
  pass "S6k-allowlist-accepts-the-emitted-shape (guard + bare invocation, exactly as templates/pipelines/ci/github/*.yml ships it)"
else
  fail_ "S6k-allowlist-accepts-the-emitted-shape" "rc=$rc — the hardened detector warns about the framework's OWN emitted workflow: $(printf '%s' "$out" | grep -E 'phase-gate step|next push' | tr '\n' ' ')"
fi

# ── S6L / S6m: DUAL DIRECTION — neuter the verdict and the deviation is waved
# through. Everything above shows shapes being refused. This shows that the
# ALLOWLIST is what refuses them: delete its verdict line and a workflow whose
# only defect is a deviating gate line gets the full "the next push enforces the
# check" claim — the exact false statement F-015 exists to prevent.
#
# WHY THE FIXTURE CHANGED (D-A, 2026-08-09). S6m used to drive the mutant with a
# bare `|| exit 0` run line. That workflow now fails the NEW `invokes` floor as
# well (no line is the allowlisted invocation), so neutering the allowlist alone
# no longer produces the false OK and the mutant would have gone vacuous —
# passing on a fixture it no longer isolates. The fixture is now the realistic
# shape whose ONLY defect is the deviation: the emitted step, kept intact, plus
# the pre-R-1 soft step an upgraded project still carries. S6L is its positive
# control — without it, S6m's "the claim came back" would not be attributable.
echo "=== S6L-legacy-leftover-step-withheld ==="
P="$TOPTMP/s6L"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD" yes emitted "$WF_LEGACY_STEP"
assert_withheld S6L-legacy-leftover-step-withheld "$P" \
  "DISCARDS the gate's exit code" \
  'a leftover soft gate step: the emitted step is intact, so ONLY the deviating line is wrong'

echo "=== S6m-neutered-allowlist-claims-false-enforcement ==="
# The verdict is REPLACED by a no-op rather than deleted: it is the only
# statement in its `if`, and an empty then-block is a syntax error — a mutant
# that fails to parse would prove nothing about the allowlist.
P="$TOPTMP/s6m"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD" yes emitted "$WF_LEGACY_STEP"
assert_mutant_false_ok S6m-neutered-allowlist-claims-false-enforcement projverdict \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# F-015-PROJECT-ALLOWLIST-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# F-015-PROJECT-ALLOWLIST-VERDICT$@\1:@' 1 1 \
  "$P" "DISCARDS the gate's exit code" \
  'without the verdict line the deviating gate line is told the next push enforces — the allowlist carries S6e-S6j and S6L'

# ── S6b: --token-env rejects a non-identifier (the eval IS an injection sink) ─
# The indirect read is `eval "token=\${$token_env:-}"`. Without a name check, a
# `--token-env` value carrying a command substitution EXECUTES. Demonstrated,
# not asserted, in BOTH directions: this run must leave the canary file absent,
# and S6b-mut below — which deletes the character-class arm of the validation,
# the arm this payload actually trips — must create it.
#
# The canary is a STRUCTURAL discriminator, not decoration: "rejected" and
# "rejected only after the eval already ran" produce the same message and the
# same exit code, and only the canary's absence tells them apart.
echo "=== S6b-token-env-name-validated ==="
CANARY="$TOPTMP/s6b-canary"
rm -f "$CANARY"
P="$TOPTMP/s6b"; mk_tok "$P" github ok yes
out=$(run_tok "$P" "$GOOD_TOKEN" --token-env "X:-\$(touch $CANARY)"); rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q "not a valid environment variable name" \
   && [ ! -e "$CANARY" ]; then
  pass "S6b-token-env-name-validated (name validated before eval; canary not created)"
else
  fail_ "S6b-token-env-name-validated" "rc=$rc canary=$([ -e "$CANARY" ] && echo CREATED || echo absent): $out"
fi
rm -f "$CANARY"

# ── S6b-mut: the other direction of S6b (R-C2) ─────────────────────────────
# S6b's comment used to promise a mutation run that did not exist — the property
# had been proven by hand during review. Here it is, executed: delete the
# character-class arm (the one `X:-$(…)` trips; the identifier-start arm lets
# that payload past) and the eval fires, creating the canary. That is the
# injection S6b claims to prevent, so S6b is now a real two-sided proof.
echo "=== S6b-mut-unvalidated-name-executes ==="
if mk_cg_mutant tokencharset \
     '^[[:space:]]*\*\[!A-Za-z0-9_\]\*\).*# F-015-TOKEN-ENV-CHARSET$' \
     '/# F-015-TOKEN-ENV-CHARSET$/d' 1 0; then
  CANARY="$TOPTMP/s6b-mut-canary"
  rm -f "$CANARY"
  P="$TOPTMP/s6bmut"; mk_tok "$P" github ok yes
  out=$(run_tok_with "$CG_MUT" "$P" "$GOOD_TOKEN" --token-env "X:-\$(touch $CANARY)"); rc=$?
  if [ -e "$CANARY" ] \
     && ! printf '%s' "$out" | grep -q "not a valid environment variable name"; then
    pass "S6b-mut-unvalidated-name-executes (without the charset arm the payload EXECUTES — the validation, not luck, is what keeps S6b's canary absent)"
  else
    fail_ "S6b-mut-unvalidated-name-executes" "rc=$rc canary=$([ -e "$CANARY" ] && echo CREATED || echo absent) — the mutant did not reproduce the injection, so S6b proves nothing: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
  fi
  rm -f "$CANARY"
else
  fail_ "S6b-mut-unvalidated-name-executes" "$CG_WHY"
fi

# ── S7: THE CHAIN — the stored secret is the one the templates map ────────
# The walkthrough's result only "genuinely flips the check to enforcing" if the
# secret it writes is the secret the emitted workflow reads into GH_TOKEN, and
# GH_TOKEN is what the gate's credential probe looks at. Three files, one name:
# assert it end to end rather than trusting three separate string literals.
echo "=== S7-chain-secret-name-agrees ==="
chain_ok=1
grep -q 'secret_name="SOIF_PROTECTION_TOKEN"' "$CHECK_GATE" || chain_ok=0
grep -Eq '^[[:space:]]*GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*secrets\.SOIF_PROTECTION_TOKEN[[:space:]]*\}\}' \
  "$REPO_ROOT/templates/pipelines/ci/github/typescript.yml" || chain_ok=0
grep -q 'GH_TOKEN' "$REPO_ROOT/scripts/check-phase-gate.sh" || chain_ok=0
if [ "$chain_ok" -eq 1 ]; then
  pass "S7-chain-secret-name-agrees (walkthrough writes -> workflow maps -> gate probes, one name)"
else
  fail_ "S7-chain-secret-name-agrees" "the walkthrough's secret name, the template's mapping and the gate's probe variable do not line up — the walkthrough would store a secret nothing reads"
fi

# ════════════════════════════════════════════════════════════════════════════
# PART 3 — D-A (Karl, 2026-08-09): the enforcement claim is gated on
#     maps && invokes && !swallows
#
# Two independent reviewers reproduced two situations where this command told a
# REAL user "The next push enforces the check" and it was false:
#   1. NO GATE AT ALL. The old predicate asked only whether a line naming the
#      gate DEVIATED from the allowlist. A ci.yml that maps the secret and
#      invokes nothing has no deviating line, so it satisfied the predicate
#      VACUOUSLY. Nothing ran; nothing enforced.
#   2. A GATE THAT CANNOT FAIL. The detector was not step-scoped, so it could
#      not see `continue-on-error: true` (which grades a FAILED step as success)
#      or a step-level `if: false`. Both kept the enforcement claim while the
#      verdict went in the bin.
#
# Every case below states which of the three conditions it violates, and asserts
# the refusal NAMES that condition — "it refused" is not the bar, because a
# refusal that does not name its cause is the defect this wave already fixed
# once. The mutants are the other direction: neuter the one line that carries a
# condition and the false claim comes back.
# ════════════════════════════════════════════════════════════════════════════

# ── D1: `invokes` violated ALONE — the vacuous case, reproduced ────────────
echo "=== D1-no-invocation-withheld ==="
P="$TOPTMP/d1"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD" yes nogate
assert_withheld D1-no-invocation-withheld "$P" \
  "INVOKES the phase gate" \
  'the secret is mapped and NOTHING runs the gate — the case the old predicate satisfied vacuously'

# ── D2: `maps` violated ALONE ──────────────────────────────────────────────
echo "=== D2-unmapped-withheld ==="
P="$TOPTMP/d2"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD" no emitted
assert_withheld D2-unmapped-withheld "$P" \
  "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
  'the gate runs and honours its exit code, but nothing reads the secret'

# ── D2b: a mapping that exists only in a COMMENT is not a mapping ──────────
# Behaviour change shipped with D-A and pinned here so it is deliberate: the
# maps test used to be an unanchored regex over the whole file, so a
# commented-out example mapping — the shape a half-finished edit leaves behind —
# earned the enforcement claim while the runner read no secret at all. Same
# defect class as the two the reviewers found, on the same line of reasoning.
echo "=== D2b-commented-out-mapping-is-not-mapped ==="
P="$TOPTMP/d2b"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD" no emitted
printf '        # GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n' >> "$P/.github/workflows/ci.yml"
assert_withheld D2b-commented-out-mapping-is-not-mapped "$P" \
  "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
  'a commented-out mapping injects nothing into the step environment'

# ── D3: `!swallows` violated ALONE — the Actions-native swallow ────────────
# continue-on-error grades a FAILED step as success (confirmed against the
# GitHub docs), so the run: body can be byte-perfect and still enforce nothing.
echo "=== D3-continue-on-error-withheld ==="
P="$TOPTMP/d3"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        continue-on-error: true" yes emitted
assert_withheld D3-continue-on-error-withheld "$P" \
  "carries 'continue-on-error: true'" \
  'the emitted body, graded as success however the gate votes'

# ── D4: `!swallows` violated ALONE — a step that never runs ────────────────
echo "=== D4-step-if-false-withheld ==="
P="$TOPTMP/d4"; mk_tok_wf "$P" "" "        if: false" yes emitted
assert_withheld D4-step-if-false-withheld "$P" \
  "condition is 'if: false'" \
  'a step-level if: false discards the verdict more completely than || true ever could'

# ── D5: `!swallows` violated ALONE — the sibling nobody has named ──────────
# The step key set is an ALLOWLIST, so a key outside the documented run-step
# schema is refused without anyone having to imagine it first.
echo "=== D5-unknown-step-key-withheld ==="
P="$TOPTMP/d5"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        on-failure: continue" yes emitted
assert_withheld D5-unknown-step-key-withheld "$P" \
  "does not recognise: on-failure" \
  'an unrecognised step key could change how the verdict is graded'

# ── D6/D7: the same argument one level up (Cw6-strict-job's reasoning) ─────
echo "=== D6-job-if-withheld ==="
P="$TOPTMP/d6"; mk_tok_wf "$P" "    if: false" "$STEP_KEYS_GOOD" yes emitted
assert_withheld D6-job-if-withheld "$P" \
  "The job that HOLDS the phase-gate step carries 'if: false'" \
  'a job that never starts runs no step, however perfect the step is'

echo "=== D7-job-continue-on-error-withheld ==="
P="$TOPTMP/d7"; mk_tok_wf "$P" "    continue-on-error: true" "$STEP_KEYS_GOOD" yes emitted
assert_withheld D7-job-continue-on-error-withheld "$P" \
  "so that job's failure does not count" \
  "a job whose failure does not count cannot enforce"

# ── D8: fail CLOSED when the structure cannot be read ──────────────────────
# A composite-action file: the gate step is real and the body is the emitted
# one, but there is no job above it, so how its verdict is graded cannot be
# determined. Unverifiable must not read as verified.
echo "=== D8-unlocatable-job-withheld ==="
P="$TOPTMP/d8"; mk_tok "$P" github ok yes
printf 'runs:\n  using: composite\n  steps:\n    - name: Governance - Phase gate check\n      env:\n        GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n      run: |\n        if [ ! -f scripts/check-phase-gate.sh ]; then\n          echo "::error::Phase gate check script missing. Framework integrity compromised."\n          exit 1\n        fi\n        bash scripts/check-phase-gate.sh\n' \
  > "$P/.github/workflows/ci.yml"
assert_withheld D8-unlocatable-job-withheld "$P" \
  "Could not locate the job that runs the gate" \
  'fail-closed: an unreadable structure is not a verified one'

# ── D9: THE FALSE-POSITIVE GUARD — every shipped template still earns it ───
# Run against the REAL emitted workflows, not fixtures: init.sh lays these down
# with a verbatim `cp` (grep `cp "$template_path" "$target_path"` in init.sh),
# so the file a user's detector reads IS this file. A hardened detector that
# reds correct setups is worse than the weak one it replaced.
echo "=== D9-emitted-templates-earn-the-claim ==="
GH_CI_DIR="$REPO_ROOT/templates/pipelines/ci/github"
d9_examined=0; d9_bad=""
for tpl in "$GH_CI_DIR"/*.yml; do
  [ -f "$tpl" ] || continue
  d9_examined=$((d9_examined + 1))
  P="$TOPTMP/d9-$(basename "$tpl" .yml)"
  mk_tok "$P" github ok yes
  cp "$tpl" "$P/.github/workflows/ci.yml"
  out=$(run_tok "$P" "$GOOD_TOKEN")
  printf '%s' "$out" | grep -q "The next push enforces the check" \
    || d9_bad="$d9_bad $(basename "$tpl")[$(printf '%s' "$out" | grep -E '^  - ' | head -1 | cut -c1-90)]"
done
# A green that is really an empty loop is the vacuity this repo keeps catching:
# the floor is what tells "all clean" apart from "nothing examined".
if [ "$d9_examined" -ge 10 ]; then
  pass "D9-scope ($d9_examined shipped github CI templates driven through the detector, floor 10)"
else
  fail_ "D9-scope" "only $d9_examined github CI templates were examined (floor 10) — D9's verdict is vacuous"
fi
if [ -z "$d9_bad" ]; then
  pass "D9-emitted-templates-earn-the-claim (all $d9_examined shipped templates still earn the enforcement claim)"
else
  fail_ "D9-emitted-templates-earn-the-claim" "the hardened detector REFUSES the framework's own emitted workflows — in:$d9_bad"
fi

# ════════════════════════════════════════════════════════════════════════════
# D10-D14 — PARITY with the bl147 pin (tests/test-bl147-ci-template-integrity.sh
# `Cw6-strict*`). The two detectors judge the same property on two different
# populations: bl147 reads the ten templates the framework wrote, this one reads
# a real user's ci.yml of unknown vintage. Where they agree, they must keep
# agreeing on the SPELLING (D14). Where they deliberately differ, the difference
# is pinned behaviourally (D10-D12) and named in the product comment (D13), so
# "aligning" them goes red rather than quiet.
# ════════════════════════════════════════════════════════════════════════════
BL147="$REPO_ROOT/tests/test-bl147-ci-template-integrity.sh"

# ── D10: parity difference 1 — the inline `run:` form is accepted here ─────
echo "=== D10-parity-inline-run-accepted ==="
P="$TOPTMP/d10"; mk_tok "$P" github ok custom 'bash scripts/check-phase-gate.sh'
assert_earns_ok D10-parity-inline-run-accepted "$P" \
  '# D-A-PARITY-1-INLINE-RUN: bl147 freezes the block scalar byte-for-byte; a pre-block-scalar vintage is honest and must not be redded'

# ── D11: parity difference 2 — an ABSENT step if: is accepted here ─────────
echo "=== D11-parity-absent-step-if-accepted ==="
P="$TOPTMP/d11"; mk_tok_wf "$P" "" "" yes emitted
assert_earns_ok D11-parity-absent-step-if-accepted "$P" \
  '# D-A-PARITY-2-ABSENT-IF: a step with no condition ALWAYS runs — the safest shape there is, and a red there would be backwards'

# ── D12: parity difference 3 — the wider step key set is accepted here ─────
echo "=== D12-parity-wider-step-keyset-accepted ==="
P="$TOPTMP/d12"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        id: phase-gate
        shell: bash
        working-directory: .
        timeout-minutes: 10" yes emitted
assert_earns_ok D12-parity-wider-step-keyset-accepted "$P" \
  '# D-A-PARITY-3-STEP-KEYSET: none of id/shell/working-directory/timeout-minutes can change how the verdict is graded'

# ── D13: every recorded parity difference is still recorded, both sides ────
echo "=== D13-parity-differences-are-recorded ==="
d13_missing=""
for mk in D-A-PARITY-1-INLINE-RUN D-A-PARITY-2-ABSENT-IF D-A-PARITY-3-STEP-KEYSET D-A-PARITY-4-NO-TRIGGER-PIN; do
  grep -qF "# $mk" "$CHECK_GATE" || d13_missing="$d13_missing check-gate.sh:$mk"
done
# …and the bl147 counterparts each difference is a difference FROM. If one of
# these disappears the asymmetry note is describing a pin that no longer exists,
# which is how a "deliberate difference" quietly becomes an accident.
for pin in Cw6-strict-keys Cw6-strict-gating Cw6-strict-job Cw6-strict-trigger; do
  grep -qF "$pin" "$BL147" || d13_missing="$d13_missing bl147:$pin"
done
if [ -z "$d13_missing" ]; then
  pass "D13-parity-differences-are-recorded (all four asymmetries named in the product, all four bl147 counterparts still present)"
else
  fail_ "D13-parity-differences-are-recorded" "a recorded parity difference or its bl147 counterpart is gone — the asymmetry is now accidental:$d13_missing"
fi

# ── D14: the SHARED vocabulary is one vocabulary ───────────────────────────
# Both sides are extracted from their own file at runtime and compared, rather
# than re-typed here as a third copy that could agree with neither.
echo "=== D14-parity-shared-vocabulary-agrees ==="
cg_inv=$(sed -n "s/^  local wf_allow_invoke='\(.*\)'\$/\1/p" "$CHECK_GATE" | head -1)
cg_guard=$(sed -n "s/^  local wf_allow_guard='\(.*\)'\$/\1/p" "$CHECK_GATE" | head -1)
cg_if=$(sed -n 's/^  local wf_allow_if="\(.*\)"$/\1/p' "$CHECK_GATE" | head -1)
b7_guard=$(sed -n "s/^W6_EXPECTED_BODY='\(.*\)\$/\1/p" "$BL147" | head -1)
b7_inv=$(sed -n "/^W6_EXPECTED_BODY=/,/'\$/p" "$BL147" | tail -1 | sed "s/'\$//")
b7_if=$(sed -n 's/^W6_EXPECTED_IF="\(.*\)"$/\1/p' "$BL147" | head -1)
d14_why=""
[ -n "$cg_inv" ] && [ -n "$cg_guard" ] && [ -n "$cg_if" ] \
  || d14_why="$d14_why; a check-gate.sh literal did not extract (inv=[$cg_inv] guard=[$cg_guard] if=[$cg_if])"
[ -n "$b7_inv" ] && [ -n "$b7_guard" ] && [ -n "$b7_if" ] \
  || d14_why="$d14_why; a bl147 literal did not extract (inv=[$b7_inv] guard=[$b7_guard] if=[$b7_if])"
[ "$cg_inv" = "$b7_inv" ]     || d14_why="$d14_why; invocation differs ([$cg_inv] vs [$b7_inv])"
[ "$cg_guard" = "$b7_guard" ] || d14_why="$d14_why; existence guard differs ([$cg_guard] vs [$b7_guard])"
[ "$cg_if" = "$b7_if" ]       || d14_why="$d14_why; allowlisted if: differs ([$cg_if] vs [$b7_if])"
if [ -z "$d14_why" ]; then
  pass "D14-parity-shared-vocabulary-agrees (invocation, existence guard and allowlisted if: are byte-identical across both detectors)"
else
  fail_ "D14-parity-shared-vocabulary-agrees" "the two detectors no longer speak one vocabulary$d14_why"
fi

# ════════════════════════════════════════════════════════════════════════════
# D15-D27 — FIX ROUND (reviewer findings R-dA-1 and R-dA-2). Two false verdicts
# in OPPOSITE directions, both produced by reading a workflow as bytes rather
# than as YAML:
#
#   R-dA-1  CRLF. A ci.yml with CRLF terminators earned the claim before the
#           step/job scope existed and was REFUSED after it, because the
#           trailing \r rides on every key and value the scan reads. The
#           refusal was self-refuting on its face — it quoted back an `if:`
#           and told the user to replace it with the same bytes.
#   R-dA-2  QUOTED KEYS. The scope report only emitted keys matching
#           /^[A-Za-z_]/, so `"continue-on-error": true` and `'if': false`
#           were never emitted and never reached the swallow scan: the claim
#           was EARNED while the step was inert. Confirmed against a real YAML
#           parser — all of these load to the identical effective config.
#           A YAML merge key (`<<: *anchor`) is the third case: the effective
#           configuration is not in the block being read at all, so it is
#           treated the way every other unreadable structure is — fail CLOSED.
# ════════════════════════════════════════════════════════════════════════════

# ── D15: the CRLF fixtures are really CRLF ─────────────────────────────────
# The premise before any conclusion. A "CRLF test" whose fixture is quietly LF
# asserts nothing at all, and `sed 's/$/\r/'` — the obvious way to write one —
# produces exactly that on BSD sed. So the bytes are counted.
echo "=== D15-crlf-fixture-is-really-crlf ==="
P="$TOPTMP/d15"; mk_tok_wf_crlf "$P" "" "$STEP_KEYS_GOOD" yes emitted
d15_wf="$P/.github/workflows/ci.yml"
d15_cr=$(n_cr "$d15_wf"); d15_ln=$(wc -l < "$d15_wf" | tr -d ' ')
if [ "$d15_cr" -gt 0 ] && [ "$d15_cr" -eq "$d15_ln" ]; then
  pass "D15-crlf-fixture-is-really-crlf ($d15_cr CR bytes over $d15_ln lines — every line terminator is CRLF)"
else
  fail_ "D15-crlf-fixture-is-really-crlf" "the fixture is not CRLF ($d15_cr CR bytes over $d15_ln lines) — every CRLF case below would be vacuous"
fi

# ── D16: R-dA-1 — a CRLF workflow that IS wired earns the claim ────────────
# Same fixture as D15. This is one assertion over all three conditions at once:
# `maps`, the `invokes` floor and every arm of `!swallows` must each survive
# CRLF for the claim to appear.
echo "=== D16-crlf-good-earns-the-claim ==="
assert_earns_ok D16-crlf-good-earns-the-claim "$P" \
  'R-dA-1: CRLF is a line ENDING, not a configuration difference — GitHub Actions parses this file identically to its LF twin'

# ── D17: …and the fix did not neuter the condition ─────────────────────────
echo "=== D17-crlf-swallow-still-refused ==="
P="$TOPTMP/d17"; mk_tok_wf_crlf "$P" "" "$STEP_KEYS_GOOD
        continue-on-error: true" yes emitted
assert_withheld D17-crlf-swallow-still-refused "$P" \
  "carries 'continue-on-error: true'" \
  'stripping the line endings must not make CRLF workflows unjudgeable — a real swallow is still caught'

# ── D18: the strip is ANCHORED — a CR inside a value is not eaten ──────────
# The paired direction of the same fix. `gsub(/\r/,"")` would silently repair a
# value that does NOT equal the shipped condition into one that does, turning a
# genuinely different `if:` into a claim of enforcement. Only a TRAILING CR is a
# line ending.
echo "=== D18-crlf-mid-value-not-eaten ==="
CRB=$(printf '\r')
P="$TOPTMP/d18"; mk_tok_wf_crlf "$P" "" "        if: hashFiles('.claude/phase-state.json')${CRB} != ''" yes emitted
assert_withheld D18-crlf-mid-value-not-eaten "$P" \
  "which is not the one this framework ships" \
  'a CR in the MIDDLE of a value is content, not a terminator — the strip must not widen into it'

# ── D19-D22: R-dA-2 — the quoted-key evasion, all four spellings ───────────
# YAML permits both quote styles for a key and generated / round-tripped
# workflows emit them. Each of these was confirmed to EARN the claim on the
# pre-fix code while the step or job was inert.
echo "=== D19-double-quoted-step-coe-withheld ==="
P="$TOPTMP/d19"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        \"continue-on-error\": true" yes emitted
assert_withheld D19-double-quoted-step-coe-withheld "$P" \
  "carries 'continue-on-error: true'" \
  'a double-quoted key is the same key — the step is still graded green however the gate votes'

echo "=== D20-single-quoted-step-if-withheld ==="
P="$TOPTMP/d20"; mk_tok_wf "$P" "" "        'if': false" yes emitted
assert_withheld D20-single-quoted-step-if-withheld "$P" \
  "condition is 'if: false'" \
  'a single-quoted key is the same key — the step never runs'

echo "=== D21-double-quoted-job-coe-withheld ==="
P="$TOPTMP/d21"; mk_tok_wf "$P" "    \"continue-on-error\": true" "$STEP_KEYS_GOOD" yes emitted
assert_withheld D21-double-quoted-job-coe-withheld "$P" \
  "so that job's failure does not count" \
  'the evasion works one level up too, and the job arm must read quoted keys as well'

echo "=== D22-single-quoted-job-if-withheld ==="
P="$TOPTMP/d22"; mk_tok_wf "$P" "    'if': false" "$STEP_KEYS_GOOD" yes emitted
assert_withheld D22-single-quoted-job-if-withheld "$P" \
  "The job that HOLDS the phase-gate step carries 'if: false'" \
  'a quoted job-level if: false starts no job at all'

# ── D23: the false-positive direction of the same fix ──────────────────────
# Unquoting the key must make it COMPARABLE, not automatically suspect. A step
# whose keys are quoted but whose values are the shipped ones is a legitimate
# setup and must still earn the claim, or the fix has traded one false verdict
# for another.
echo "=== D23-quoted-good-keys-still-earn ==="
P="$TOPTMP/d23"; mk_tok_wf "$P" "" "        \"if\": hashFiles('.claude/phase-state.json') != ''
        'continue-on-error': false" yes emitted
assert_earns_ok D23-quoted-good-keys-still-earn "$P" \
  'the key is unquoted for COMPARISON only — a quoted spelling of the shipped configuration is the shipped configuration'

# ── D24: a sibling evasion the review did not name ─────────────────────────
# NOT IN THE BRIEF. The same emit() guard rejected `continue-on-error : true`
# (a space before the colon) for the same reason it rejected the quoted form,
# and YAML permits it — `s-separate-in-line?` sits between an implicit key and
# its `:`. Verified against a real parser: it loads to {continue-on-error: true},
# byte-identically to the ordinary spelling, and it earned the claim pre-fix.
# Reported rather than papered over; carried here so it cannot come back.
echo "=== D24-spaced-colon-step-coe-withheld ==="
P="$TOPTMP/d24"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        continue-on-error : true" yes emitted
assert_withheld D24-spaced-colon-step-coe-withheld "$P" \
  "carries 'continue-on-error: true'" \
  'YAML allows whitespace between an implicit key and its colon — the key is the same key'

# ── D25/D26: the THIRD case — configuration that is not in the block ───────
# A merge key pulls the effective `continue-on-error:` / `if:` in from an anchor
# elsewhere in the file. Resolving anchors is not attempted; unverifiable must
# not read as verified, which is the same doctrine as D8.
merge_sig() { printf "A YAML merge key on the gate's %s pulls in keys from ELSEWHERE in the file" "$1"; }
echo "=== D25-step-merge-key-fails-closed ==="
P="$TOPTMP/d25"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        <<: *soft" yes emitted
printf 'x-soft: &soft\n  continue-on-error: true\n' >> "$P/.github/workflows/ci.yml"
assert_withheld D25-step-merge-key-fails-closed "$P" \
  "$(merge_sig step)" \
  'the swallow can live in the anchor, so the block being read does not settle the question'

echo "=== D26-job-merge-key-fails-closed ==="
P="$TOPTMP/d26"; mk_tok_wf "$P" "    <<: *soft" "$STEP_KEYS_GOOD" yes emitted
printf 'x-soft: &soft\n  continue-on-error: true\n' >> "$P/.github/workflows/ci.yml"
assert_withheld D26-job-merge-key-fails-closed "$P" \
  "$(merge_sig job)" \
  'the same argument one level up — a merged job-level continue-on-error is invisible here'

# ── D27: a step REPLACED by an alias already fails closed ──────────────────
# The remaining anchor shape, pinned rather than assumed: when the step itself is
# `- *gate_step`, the gate line lives in the anchor definition, which has no
# enclosing sequence item — so the EXISTING unlocatable arm catches it and no
# new code is needed. Asserting it here is what keeps that true.
echo "=== D27-alias-step-fails-closed ==="
P="$TOPTMP/d27"; mk_tok "$P" github ok yes
printf 'name: CI\non:\n  push:\n    branches: [main]\nx-gate: &gate_step\n  name: Governance - Phase gate check\n  continue-on-error: true\n  env:\n    GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n  run: |\n    bash scripts/check-phase-gate.sh\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - *gate_step\n' \
  > "$P/.github/workflows/ci.yml"
assert_withheld D27-alias-step-fails-closed "$P" \
  "Could not locate the step that runs the gate" \
  'an aliased step keeps its configuration outside the block, and the existing fail-closed arm already refuses it'

# ── D28-D30: the same evasion ONE LEVEL UP, in the job LOCATOR ─────────────
# Found while probing the residual surface of R-dA-2, and the worst of the set
# because it fails OPEN. Locating the job was a climb for the nearest line
# matching /^ +[A-Za-z_][A-Za-z0-9_-]*: *$/, and a line it could not read was
# SKIPPED rather than stopped at — so a quoted job id sent it climbing out of
# `jobs:` entirely and it bound "the job" to `push:` inside the `on:` block.
# Observed directly: the scope report for such a file reads `JOBKEY branches`.
# It then scanned the TRIGGER for job-level swallows, found none, and awarded
# the claim while a real `continue-on-error: true` on the actual job was never
# read. The fix is to stop at the nearest ENCLOSING line and fail closed when it
# is not a readable job id — guessing further is what produced this.
JOB_ID_FIXTURE_HEAD='name: CI
on:
  push:
    branches: [main]

jobs:'
JOB_ID_FIXTURE_TAIL="    steps:
      - name: Governance - Phase gate check
$STEP_KEYS_GOOD
        env:
          GH_TOKEN: \${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          if [ ! -f scripts/check-phase-gate.sh ]; then
            echo \"::error::Phase gate check script missing. Framework integrity compromised.\"
            exit 1
          fi
          bash scripts/check-phase-gate.sh"
# mk_jobid_wf <dir> <job-id-line> <job-keys-or-empty>
mk_jobid_wf() {
  local d="$1" idline="$2" jobkeys="${3:-}"
  mk_tok "$d" github ok yes || return 1
  {
    printf '%s\n' "$JOB_ID_FIXTURE_HEAD"
    printf '%s\n' "$idline"
    [ -n "$jobkeys" ] && printf '%s\n' "$jobkeys"
    printf '    runs-on: ubuntu-latest\n'
    printf '%s\n' "$JOB_ID_FIXTURE_TAIL"
  } > "$d/.github/workflows/ci.yml"
}

echo "=== D28-quoted-job-id-still-reads-the-job ==="
P="$TOPTMP/d28"; mk_jobid_wf "$P" '  "test":' "    continue-on-error: true"
assert_withheld D28-quoted-job-id-still-reads-the-job "$P" \
  "so that job's failure does not count" \
  'a quoted job id must not make the job unreadable — the swallow on it is a real swallow'

echo "=== D29-unreadable-job-id-fails-closed ==="
P="$TOPTMP/d29"; mk_jobid_wf "$P" '  test: &jobdefaults' ""
assert_withheld D29-unreadable-job-id-fails-closed "$P" \
  "Could not locate the job that runs the gate" \
  'an id line that is not a plain job id must STOP the search, not send it climbing into the on: block'

echo "=== D30-quoted-job-id-clean-job-still-earns ==="
P="$TOPTMP/d30"; mk_jobid_wf "$P" '  "test":' ""
assert_earns_ok D30-quoted-job-id-clean-job-still-earns "$P" \
  'the locator must read the quoted id, not merely refuse it — failing every quoted job closed would be a false red'

# ════════════════════════════════════════════════════════════════════════════
# D31-D53 — FIX ROUND 2 (reviewer findings R-CTE-1…R-CTE-7, plus the atoms the
# sweep those findings forced turned up). Every case here is ORDINARY,
# parser-valid GitHub Actions YAML: none of it is exotic, all of it is emitted
# by some hand or some tool, and each one either earned the enforcement claim
# while the gate was inert or was refused while it was perfectly wired.
#
#   R-CTE-1  a LONE `-` sequence item. The step-climb required a space after
#            the dash, so the gate bound to the PREVIOUS step and never read the
#            real step's `continue-on-error:` (D31); the same style with the
#            gate step first in the job failed closed instead (D32); and a dash
#            with trailing blanks matched the climb but derived the wrong key
#            column, so it read a line out of the env block as a step key (D34).
#   R-CTE-2  a FOLDED scalar (`run: >`) joins its lines with spaces before bash
#            sees them, so `|| true` on a line of its own is part of the
#            invocation while every line-wise check passes (D35/D36).
#   R-CTE-4  the invokes floor's THRESHOLD, reachable only from a guard-only
#            workflow (D37) — the one shape that gets past `wf_gate` empty.
#   R-CTE-5  a trailing YAML comment is not part of a value (D38/D39) nor of the
#            `steps:` anchor (D41) nor of a job id (D42) — and a `#` INSIDE a
#            quoted value is not a comment at all (D40).
#   R-CTE-6  `maps` was file-wide while the OK sentence says step-scoped: a
#            secret in a DIFFERENT step's env (D43) or a DIFFERENT job's env
#            (D46) earned "maps … into the phase-gate step". Job- and
#            workflow-level env DO reach the step and must still earn (D44/D45).
#   R-CTE-7  duplicate mapping keys — `head -1` read the benign first one (D47).
# ════════════════════════════════════════════════════════════════════════════

# ── D31-D34: R-CTE-1, the lone-dash sequence item, in BOTH directions ──────
echo "=== D31-lone-dash-step-hides-swallow ==="
# The secret is mapped at JOB level here, not on the step. That is deliberate
# and it is what makes DM17 isolate one line: with the climb narrowed back, the
# scan binds to `Setup`, and a step-level mapping would then make it fail on
# `maps` — refusing for a second reason and proving nothing about the climb.
# Mapped at job level, every step inherits it, so the ONLY thing the mutant
# changes is which step's keys are read.
P="$TOPTMP/d31"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
    steps:
      - name: Setup
        run: echo hi
      -
        name: Governance - Phase gate check
        continue-on-error: true
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D31-lone-dash-step-hides-swallow "$P" \
  "carries 'continue-on-error: true'" \
  'a bare dash on its own line is an ordinary sequence item — binding the gate to the PREVIOUS step read the wrong keys entirely'

echo "=== D32-lone-dash-first-step-still-earns ==="
P="$TOPTMP/d32"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      -
        name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D32-lone-dash-first-step-still-earns "$P" \
  'the mirror direction: the same style with nothing above it used to fail closed as "could not locate the step" — a false red on a correctly-wired file'

echo "=== D33-lone-dash-first-step-swallow-still-caught ==="
P="$TOPTMP/d33"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      -
        name: Governance - Phase gate check
        continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D33-lone-dash-first-step-swallow-still-caught "$P" \
  "carries 'continue-on-error: true'" \
  'reading the lone-dash step is not enough — its KEY COLUMN has to come from the first line below it, or the keys are still never read'

# NOT IN THE BRIEF. A dash followed by trailing blanks DID match the old climb
# (there is a space after the dash), but `sub(/^ *- */, …)` then consumed the
# blanks too and the key column came out four columns too deep — so the scan
# read `GH_TOKEN` out of the env block AS A STEP KEY and refused for that,
# while the real `continue-on-error: true` was never seen. Observed directly:
# the scope report for such a file reads `STEPKEY GH_TOKEN`. Third spelling of
# the same defect; one fix covers all three because the test is now "the dash
# line carries no inline content", not "how many blanks follow the dash".
echo "=== D34-lone-dash-trailing-blanks-swallow-caught ==="
# The blanks after the dash are WRITTEN, never described: a heredoc in this file
# would carry them invisibly and the next editor to trim whitespace would make
# this case silently vacuous — the same reason to_crlf() exists above. n_trail
# asserts the premise before anything else is asserted.
P="$TOPTMP/d34"; mk_tok "$P" github ok yes
{
  printf 'name: CI\non:\n  push:\n    branches: [main]\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n'
  printf '      -%s\n' "   "
  printf '        name: Governance - Phase gate check\n        continue-on-error: true\n        env:\n          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n        run: |\n          bash scripts/check-phase-gate.sh\n'
} > "$P/.github/workflows/ci.yml"
d34_trail=$(grep -c '^ *-  *$' "$P/.github/workflows/ci.yml")
if [ "$d34_trail" -eq 1 ]; then
  pass "D34-premise (the fixture really carries a dash followed by trailing blanks)"
else
  fail_ "D34-premise" "the dash-plus-blanks line was not written ($d34_trail matches) — D34 would be vacuous"
fi
assert_withheld D34-lone-dash-trailing-blanks-swallow-caught "$P" \
  "carries 'continue-on-error: true'" \
  'trailing blanks after the dash used to shift the key column and turn an env entry into a bogus step key'

# ── D35/D36: R-CTE-2, the folded scalar ────────────────────────────────────
# `run: >` folds its source lines together with SPACES, so the command the
# runner executes is `bash scripts/check-phase-gate.sh || true` — the canonical
# swallow, verbatim — while the visible gate line is byte-exact the allowlisted
# invocation and `|| true` sits on a line naming nothing. Every line-wise check
# passes. The `run: |` equivalents are all caught already (a trailing `\` or a
# trailing `||` deviates line-wise); only FOLDING evades, because the join
# happens in YAML rather than in bash. Same doctrine as the merge key: the
# effective command is not in the lines being read, so fail CLOSED.
echo "=== D35-folded-run-fails-closed ==="
P="$TOPTMP/d35"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: hashFiles('.claude/phase-state.json') != ''
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: >
          bash scripts/check-phase-gate.sh
          || true
YML
assert_withheld D35-folded-run-fails-closed "$P" \
  "FOLDED block scalar" \
  'the effective command is not any line in the file, so no line-wise check can settle the question'

echo "=== D36-folded-run-chomping-indicator-fails-closed ==="
P="$TOPTMP/d36"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: >-
          bash scripts/check-phase-gate.sh
          || true
YML
assert_withheld D36-folded-run-chomping-indicator-fails-closed "$P" \
  "FOLDED block scalar" \
  'the chomping and indentation indicators are part of the same folded form — reading only a bare > would leave three spellings open'

# ── D37: R-CTE-4 — the invokes floor's THRESHOLD, not its presence ─────────
# A PR-blocking-check survivor before this case existed: `-ge 1` → `-ge 0` left
# the suite at 79/0, because every invokes-path fixture leaves `wf_gate` empty
# and the threshold is never reached. The one shape that reaches it is a
# GUARD-ONLY workflow — the framework's existence guard present, the invocation
# deleted — which is exactly what a half-finished edit leaves behind.
# CLAUDE.md's BL-181 lesson, verbatim: pin each atom's WIDTH, not its presence.
echo "=== D37-guard-only-workflow-withheld ==="
P="$TOPTMP/d37"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          if [ ! -f scripts/check-phase-gate.sh ]; then
            echo "::error::Phase gate check script missing. Framework integrity compromised."
            exit 1
          fi
YML
assert_withheld D37-guard-only-workflow-withheld "$P" \
  "INVOKES the phase gate" \
  'the guard NAMES the gate script but never runs it — the floor has to count invocations, not mentions'

# ── D38-D42: R-CTE-5 — a YAML comment is not part of the value ─────────────
echo "=== D38-trailing-comment-on-step-if-still-earns ==="
P="$TOPTMP/d38"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: hashFiles('.claude/phase-state.json') != '' # phase gate
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D38-trailing-comment-on-step-if-still-earns "$P" \
  'semantically identical config: a comment is not part of the value, and refusing it is the CRLF regression one notch subtler'

echo "=== D39-trailing-comment-on-step-coe-still-earns ==="
P="$TOPTMP/d39"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        continue-on-error: false # deliberately hard
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D39-trailing-comment-on-step-coe-still-earns "$P" \
  'the same for the one continue-on-error value that is SAFE — an explicit false with a note is still an explicit false'

# The strip's other direction, which is the one that could go wrong — and where
# the obvious implementation is WRONG in a way only a real parser catches.
#
# The reviewer's safety argument (a strip can only turn a refusal into an
# acceptance when the remainder is byte-exact the shipped value, so it cannot
# create a false OK) was VERIFIED, not accepted, and it holds: both allowlisted
# values start unquoted, so a naive remainder always keeps an unbalanced opening
# quote and can never equal the shipped bytes. What a naive strip DOES break is
# the message — it quotes a MANGLED condition back at the user, the same
# self-refuting message the CRLF fix removed.
#
# But "do not strip inside quotes" is only right for a QUOTED scalar, and a YAML
# scalar is quoted only when it OPENS with a quote. Inside a PLAIN scalar an
# apostrophe is ordinary content and YAML really does end the value at the
# ` #`. Measured, not reasoned — PyYAML loads
#   if: contains(m, ' #skip')
# as the plain scalar `contains(m, '`. A scan that tracks quotes from anywhere
# gets that case wrong (conservatively: it under-strips, so it can only produce
# a false RED, never a false OK — but it is still the wrong reading and it is
# still a mangled message). D40 pins the genuinely quoted form; D40b pins the
# plain one, against what the parser actually says.
echo "=== D40-hash-inside-quoted-scalar-is-content ==="
P="$TOPTMP/d40"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: "hashFiles('.claude/phase-state.json') != '' # not really"
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D40-hash-inside-quoted-scalar-is-content "$P" \
  "condition is 'if: \"hashFiles('.claude/phase-state.json') != '' # not really\"'" \
  'the value OPENS with a quote, so it is a quoted scalar and the # is content — refused, and quoted back whole rather than truncated at the hash'

echo "=== D40b-hash-in-plain-scalar-ends-the-value ==="
P="$TOPTMP/d40b"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: contains(github.event.head_commit.message, ' #skip')
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D40b-hash-in-plain-scalar-ends-the-value "$P" \
  "condition is 'if: contains(github.event.head_commit.message, ''" \
  'and the mirror: this value does NOT open with a quote, so the apostrophes are content and YAML ends it at the space-hash — which is what the message must say'

echo "=== D41-trailing-comment-on-steps-anchor-still-earns ==="
P="$TOPTMP/d41"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps: # the governance job's steps
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D41-trailing-comment-on-steps-anchor-still-earns "$P" \
  'NOT IN THE BRIEF: the same comment defect on the STRUCTURAL anchor — the $-anchored steps: regex missed it and the whole job went unlocatable'

echo "=== D42-trailing-comment-on-job-id-still-earns ==="
P="$TOPTMP/d42"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test: # the governance job
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D42-trailing-comment-on-job-id-still-earns "$P" \
  'NOT IN THE BRIEF: and on the job id, where the same regex is what D-A-JOB-ID-CLOSED reads'

# ── D43-D46: R-CTE-6 — `maps` has to be SCOPED to what reaches the step ────
# The OK sentence says "maps SOIF_PROTECTION_TOKEN into the phase-gate step".
# The test behind it was a file-wide substring match, so a secret mapped into a
# DIFFERENT step's env earned that sentence while the gate step got no token at
# all — the sentence claimed a scope nobody had checked, which is this branch's
# whole subject. The correct scope is the gate step's own block (its env: AND
# its run: body, because `${{ secrets.X }}` used directly in a command is a real
# mapping too) plus the gate job's env: and the workflow's env:, both of which
# DO reach the step. D44/D45/D46 are the false-red guards that keep the fix from
# over-narrowing — the failure mode a scoping change invites.
echo "=== D43-secret-mapped-into-another-step-withheld ==="
P="$TOPTMP/d43"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Other step
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: echo hi
      - name: Governance - Phase gate check
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D43-secret-mapped-into-another-step-withheld "$P" \
  "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
  'a secret in a sibling step never enters the gate step environment — the OK sentence said step scope and nothing checked it'

echo "=== D44-workflow-level-env-still-earns ==="
P="$TOPTMP/d44"; mk_raw_wf "$P" <<'YML'
name: CI
env:
  GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D44-workflow-level-env-still-earns "$P" \
  'workflow-level env IS inherited by every step, so narrowing to the step block alone would have redded it'

echo "=== D45-job-level-env-still-earns ==="
P="$TOPTMP/d45"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
    steps:
      - name: Governance - Phase gate check
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D45-job-level-env-still-earns "$P" \
  'and so is the gate job own env — the third of the three routes into the step environment'

echo "=== D46-secret-mapped-into-another-job-withheld ==="
P="$TOPTMP/d46"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        run: |
          bash scripts/check-phase-gate.sh
  deploy:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
    steps:
      - name: Ship
        run: echo ship
YML
assert_withheld D46-secret-mapped-into-another-job-withheld "$P" \
  "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
  'the same argument one level up: another job env is a different runner and a different environment'

# ── D47: R-CTE-7 — duplicate keys, where head -1 read the benign one ───────
# `head -1` picked `false` and the gate looked hard while the effective value
# was `true`. Mitigating and decisive at once: GitHub own parser REJECTS
# duplicate mapping keys, so this workflow does not run at all — which means
# "the next push enforces the check" is false for it twice over. Failing closed
# on the duplicate is therefore the correct answer AND it removes the ambiguity
# `head -1` was resolving arbitrarily, which is why the sweep found that
# selector unpinned: the right fix is to delete the choice, not to pin it.
echo "=== D47-duplicate-step-key-fails-closed ==="
P="$TOPTMP/d47"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        continue-on-error: false
        continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D47-duplicate-step-key-fails-closed "$P" \
  "declared TWICE" \
  'parsers disagree about which one wins — PyYAML takes the LAST (so the effective value here is the swallow), GitHub is documented to reject duplicate keys — and an answer nobody can predict is not one to claim enforcement on'

# ════════════════════════════════════════════════════════════════════════════
# D48-D53 — THE ATOM SWEEP. R-CTE-4 was a threshold that survived the whole
# suite, so per the brief every other numeric and quantifier atom in this
# surface was mutated the same way and the survivors triaged. These six pin the
# survivors that are behaviourally REAL. The rest are recorded in the report
# with the argument for why they cannot change a verdict.
# ════════════════════════════════════════════════════════════════════════════

# The product comment promises this shape works ("a four-space `steps:` sequence
# — YAML permits the dash at the same column as its key — is ordinary
# hand-written style and reading it as no keys at all would fail OPEN"). It was
# never driven. Mutating the anchor search from `<= si` to `< si` left the suite
# at 79/0, which is what an unexercised promise looks like.
# The step keys are emitted BEFORE the job is located, so a step-level swallow
# is reported either way and asserting one here would NOT have exercised the
# anchor at all — which is exactly why the mutation survived. The decisive pair
# is a clean file that must EARN (a job it cannot locate fails closed) and a
# JOB-level swallow that must be caught (which needs the job located first).
echo "=== D48-dash-at-steps-column-still-earns ==="
P="$TOPTMP/d48"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - name: Governance - Phase gate check
      env:
        GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
      run: |
        bash scripts/check-phase-gate.sh
YML
assert_earns_ok D48-dash-at-steps-column-still-earns "$P" \
  'the dash at the same column as steps: is ordinary YAML, and the anchor search has to accept an EQUAL indent or a correctly-wired job goes unlocatable'

echo "=== D48b-dash-at-steps-column-job-swallow-caught ==="
P="$TOPTMP/d48b"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
    - name: Governance - Phase gate check
      env:
        GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
      run: |
        bash scripts/check-phase-gate.sh
YML
assert_withheld D48b-dash-at-steps-column-job-swallow-caught "$P" \
  "so that job's failure does not count" \
  'and the job-level scan has to reach it there too — that half is unreachable unless the anchor matched'

echo "=== D49-single-character-step-key-withheld ==="
P="$TOPTMP/d49"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        x: true" yes emitted
assert_withheld D49-single-character-step-key-withheld "$P" \
  "does not recognise: x" \
  'the key guard quantifier: narrowing [A-Za-z0-9_-]* to + makes a one-character key invisible, and an invisible key is not an allowlisted one'

echo "=== D50-spaced-colon-job-id-still-reads-the-job ==="
P="$TOPTMP/d50"; mk_jobid_wf "$P" '  test :' "    continue-on-error: true"
assert_withheld D50-spaced-colon-job-id-still-reads-the-job "$P" \
  "so that job's failure does not count" \
  'YAML allows a space before the colon on a job id too — D24 doctrine, one level up, and dropping the [ ]* there loses the whole job'

# A `run:` body line that starts with a dash but is NOT a sequence item — a
# continued command-line option is the everyday case. The climb REQUIRES the
# space after the dash for exactly this reason; widen it to /^ *-/ and the step
# binds to a line inside its own run body, the key column comes out nonsense,
# and the swallow above goes unread. The suite did not notice that widening.
echo "=== D51-dash-option-in-run-body-does-not-open-a-step ==="
P="$TOPTMP/d51"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          npm run lint \
            -w packages/app
          bash scripts/check-phase-gate.sh
YML
assert_withheld D51-dash-option-in-run-body-does-not-open-a-step "$P" \
  "carries 'continue-on-error: true'" \
  'a dash with no space after it is an option, not a sequence item — the climb must not bind the step to it'

# A COMMENTED-OUT gate line in an earlier, clean step. The gate-line search
# skips comments; stop skipping them and the scan binds to that comment step
# instead — a step with nothing wrong with it — while the real gate step
# carries the swallow. Verified as a false OK, not merely a wrong report.
echo "=== D52-commented-gate-line-does-not-steal-the-step ==="
P="$TOPTMP/d52"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Setup
        run: echo hi
        # bash scripts/check-phase-gate.sh
      - name: Governance - Phase gate check
        continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D52-commented-gate-line-does-not-steal-the-step "$P" \
  "carries 'continue-on-error: true'" \
  'a commented gate line is not the gate — binding to it moves the whole scan onto an innocent step'

# The bullet SET is contract, not decoration. A workflow whose only gate line is
# the swallowed inline form fails TWO conditions — no line IS the invocation,
# and that line is not in the allowlist — and both have to be said, because the
# fix for one is not the fix for the other.
echo "=== D53-swallowed-inline-invocation-names-both-causes ==="
P="$TOPTMP/d53"; mk_tok "$P" github ok custom 'bash scripts/check-phase-gate.sh || true'
assert_withheld D53a-swallowed-inline-names-invokes "$P" \
  "INVOKES the phase gate" \
  'the whole-line match on the floor: a line that merely CONTAINS the invocation is not the invocation'
assert_withheld D53b-swallowed-inline-names-deviation "$P" \
  "DISCARDS the gate's exit code" \
  'and the deviation scan names the line itself — two causes, two edits'

# ── D55-D57: three more atoms the POST-fix sweep found still unpinned ──────
# The sweep was re-run against the fixed code, not just the old one, because a
# fix moves which atoms are load-bearing: the maps scoping made two indentation
# comparisons decisive that were inert before, and left three others open.

# An `if:` whose value is NOTHING BUT a comment is the NULL condition, and the
# refusal has to say so rather than read the comment text back as if it were a
# condition — the self-refuting message again, in its smallest form.
echo "=== D55-comment-only-value-is-the-null-value ==="
P="$TOPTMP/d55"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: # decide later
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D55-comment-only-value-is-the-null-value "$P" \
  "condition is 'if: '" \
  'PyYAML loads this as if: None — a present key with no value, which is neither absent nor the shipped condition'

# The workflow-level `env:` block has to END at the next column-0 key. Let it run
# to end of file and every secret anywhere below it counts as workflow env,
# which puts the file-wide match back through the side door.
echo "=== D56-workflow-env-block-ends-at-column-zero ==="
P="$TOPTMP/d56"; mk_raw_wf "$P" <<'YML'
name: CI
env:
  NODE_ENV: test
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Other step
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: echo hi
      - name: Governance - Phase gate check
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D56-workflow-env-block-ends-at-column-zero "$P" \
  "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
  'a workflow env that does NOT carry the secret must not drag the rest of the file into scope with it'

# A `#` that is NOT preceded by white space does not start a comment — it is an
# ordinary character in the value. Measured: PyYAML loads
# `continue-on-error: false#note` as the STRING 'false#note', which GitHub
# evaluates as truthy, so that step IS soft and refusing it is the correct
# answer. Drop the white-space requirement from the strip and the value becomes
# `false`, which is the one continue-on-error value that earns the claim — a
# false OK, from one relaxed condition in a comment scanner.
echo "=== D58-hash-without-preceding-space-is-not-a-comment ==="
P="$TOPTMP/d58"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        continue-on-error: false#note
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D58-hash-without-preceding-space-is-not-a-comment "$P" \
  "carries 'continue-on-error: false#note'" \
  'the value is the string false#note, not the boolean false — truthy, so the step is soft, and the strip must not manufacture a false out of it'

# TABS. Recorded, not handled: YAML permits a tab inside a quoted scalar
# (`run: "echo a<TAB>b"` loads fine) but NOT as separation, and PyYAML rejects
# every tab-as-separator spelling outright — a tab before a `#`, a tab between a
# key and its colon, a tab after the colon. So this program treats a tab as
# CONTENT everywhere and never as white space, which keeps every one of those
# files refused (the safe direction) and keeps a legitimate tab in a quoted
# command from being a false red. The one that would matter if a parser ever
# accepted it — a tab-spaced colon hiding continue-on-error — is recorded rather
# than fixed, because a blanket "tab in the block ⇒ fail closed" WOULD red
# `run: "echo a<TAB>b"`, which is valid.
echo "=== D57-tab-separator-residual-is-recorded ==="
grep -qF '# D-A-RESIDUAL-TAB-SEPARATOR' "$CHECK_GATE" \
  && pass "D57-tab-separator-residual-is-recorded (the tab reading is stated in the product, with what the parser says)" \
  || fail_ "D57-tab-separator-residual-is-recorded" "the tab residual is no longer recorded — the reading becomes accidental"

# ── D54: R-CTE-3 recorded, not fixed, and recorded EXECUTABLY ──────────────
# The `invokes` floor counts a byte-exact gate line inside a heredoc — data
# written to a file and never executed. That is the same "names on executed
# lines ≠ invokes" gap CLAUDE.md documents for BL-181, so it is not academic.
# It is recorded rather than fixed because telling data from code inside a
# `run:` body needs a bash lexer (quoted and unquoted delimiters, `<<-`, nesting,
# command substitution), and BL-181 is this repo's own record of a lexical
# approximation of "executed" being narrowed one character at a time and
# re-opening three times. Worse, `wf_gate` feeds BOTH the floor and the
# deviation scan, so a heredoc skip that is one delimiter form too greedy hides
# a real swallowing line — the fail-OPEN direction. The residual is pinned in
# BOTH halves: the marker is in the product, and the behaviour it describes is
# asserted, so changing it goes RED rather than quiet.
echo "=== D54-heredoc-residual-is-recorded ==="
grep -qF '# D-A-RESIDUAL-HEREDOC-DATA' "$CHECK_GATE" \
  && pass "D54-heredoc-residual-is-recorded (the residual is named in the product, beside the parity notes)" \
  || fail_ "D54-heredoc-residual-is-recorded" "the recorded-residual marker is gone — an unfixed known defect is now an undocumented one"
P="$TOPTMP/d54"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Generate helper
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          cat > helper.sh <<'DONE'
          bash scripts/check-phase-gate.sh
          DONE
YML
assert_earns_ok D54b-heredoc-residual-behaves-as-recorded "$P" \
  'RECORDED RESIDUAL, not an endorsement: the floor still counts a gate line that is heredoc DATA. Pinned so that closing it is a deliberate change with its own proof'

# ════════════════════════════════════════════════════════════════════════════
# ROUND 3 — the scope report is a GRAMMAR, and MAPSCOPE re-emits raw run-body
# lines into the very stream the verdict greps read.
#
# The round-2 report argued that the `-x` flags on the greps that read
# _wf_gate_scope's report "cannot change a verdict", on the structural grounds
# that `STEP none` / `JOB none` are terminal and that a proper superstring of
# `STEPKEY continue-on-error` would be refused as an unrecognised key anyway.
# That argument overlooked `MAPSCOPE`, which prints RAW LINES of the gate step's
# own block — its `run:` body included — into the same stream. A gate step whose
# command echoes any sentinel token then matches a NON-anchored grep, and every
# one of those greps turns a correctly-wired workflow into a refusal. The atoms
# are anchors against this function's OWN output, not merely against structure.
#
# ONE fixture carries every sentinel in the grammar, which is the stronger
# statement: a legitimate workflow that names the whole report vocabulary in its
# command still earns the claim, and each mutant below removes exactly one
# anchor and gets exactly one named refusal back. An argument is not a
# measurement — this is the measurement.
mk_sentinel_wf() {
  mk_raw_wf "$1" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          echo "scope grammar: STEP none"
          echo "scope grammar: JOB none"
          echo "scope grammar: STEPKEY continue-on-error"
          echo "scope grammar: STEPKEY if"
          echo "scope grammar: STEPKEY shell"
          echo "scope grammar: STEPMERGE <<: *soft"
          echo "scope grammar: JOBMERGE <<: *soft"
          echo "scope grammar: STEPOPAQUE !!str continue-on-error: true"
          echo "scope grammar: JOBOPAQUE ? continue-on-error"
          bash scripts/check-phase-gate.sh
YML
}
# The step deliberately carries NEITHER `if:` NOR `shell:`. Both are permitted
# absent (# D-A-PARITY-2-ABSENT-IF, and an absent shell is the documented
# default), and only their ABSENCE makes the two `STEPKEY` sentinels decisive:
# with a real `if:` present the count is already 1 and the mutant proves nothing.
echo "=== D59-report-grammar-in-a-run-body-still-earns ==="
P="$TOPTMP/d59"; mk_sentinel_wf "$P"
assert_earns_ok D59-report-grammar-in-a-run-body-still-earns "$P" \
  'a correctly-wired gate step may echo every sentinel token of the scope-report grammar; the anchors are what keep MAPSCOPE re-emission from being read as structure'

# ── D60-D63: node tags and explicit keys — the fail-open the key guard left ──
# `emit()` skips any line that is not a plain `key:`, so a key written with a
# YAML node tag (`!!str continue-on-error: true`) or in explicit-key form
# (`? continue-on-error` / `: true`) was never reported at all and the swallow
# was invisible. SETTLED, not assumed, and it settles the same way under both
# readings of GitHub's parser:
#   • PyYAML 6.0.3 loads all four spellings below as a REAL
#     `continue-on-error: true` at the level written (measured, not argued);
#   • the public `actions/runner` YAML reader
#     (src/Sdk/DTPipelines/Pipelines/ObjectTemplating/YamlObjectReader.cs)
#     HONOURS the five standard scalar tags — `tag:yaml.org,2002:str` among them
#     — so a tagged key is a real key to Actions too, while an explicit key
#     reaches no handler at all and errors out.
# Honoured ⇒ a real swallow. Rejected ⇒ the workflow does not run, so "the next
# push enforces the check" is false twice over. The verdict does not depend on
# which, so it is decided rather than guessed: fail CLOSED with its own cause.
OPAQUE_SIG="cannot read as a key"
echo "=== D60-tagged-step-key-withheld ==="
P="$TOPTMP/d60"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        !!str continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D60-tagged-step-key-withheld "$P" "$OPAQUE_SIG" \
  'a node tag on the key is the same key to a YAML parser, so the step is soft and the claim was earned'

echo "=== D61-explicit-step-key-withheld ==="
P="$TOPTMP/d61"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        ? continue-on-error
        : true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D61-explicit-step-key-withheld "$P" "$OPAQUE_SIG" \
  'the explicit-key form is the same mapping entry, and Actions own reader errors on it — unearned either way'

echo "=== D62-tagged-job-key-withheld ==="
P="$TOPTMP/d62"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    !!str continue-on-error: true
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D62-tagged-job-key-withheld "$P" "$OPAQUE_SIG" \
  'the same evasion one level up — the JOB is soft and the step below it cannot enforce'

echo "=== D63-explicit-job-key-withheld ==="
P="$TOPTMP/d63"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    ? continue-on-error
    : true
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D63-explicit-job-key-withheld "$P" "$OPAQUE_SIG" \
  'explicit key at job level, same disposition'

# ── D64-D70: the FOURTH condition — the step's shell must fail fast ──────────
# R-CTE-8, Karl 2026-08-10. `shell:` was allowlisted as a documented run-step
# key on the false ground that it "cannot change how the step's verdict is
# graded". It is the one key on that list that decides exactly that. Per
# GitHub's own workflow syntax reference ("Exit codes and error action
# preference"): for the BUILT-IN `bash` and `sh` keywords GitHub enforces
# fail-fast with `set -e` (bash also `-o pipefail`), and "you can override these
# defaults by providing a custom shell template string". Under a custom template
# such as `shell: bash {0}` the script runs bare, so a FAILING
# `bash scripts/check-phase-gate.sh` no longer aborts and any line after it sets
# the step's exit code to 0 — the gate's verdict is discarded exactly as
# `continue-on-error: true` discards it, and the file was told the next push
# enforces the check.
SHELL_SIG="which GitHub does not run with 'set -e'"
echo "=== D64-custom-shell-template-withheld ==="
P="$TOPTMP/d64"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        shell: bash {0}
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
          echo "gate done"
YML
assert_withheld D64-custom-shell-template-withheld "$P" "$SHELL_SIG" \
  'a custom template runs the script with no -e, so the trailing echo grades a FAILED gate as success'

echo "=== D65-non-fail-fast-keyword-withheld ==="
P="$TOPTMP/d65"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        shell: python
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_withheld D65-non-fail-fast-keyword-withheld "$P" "$SHELL_SIG" \
  'an ALLOWLIST, not a blacklist: python is a documented keyword and it is still refused, because it is not documented fail-fast for this body'

echo "=== D66-shell-bash-still-earns ==="
P="$TOPTMP/d66"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        shell: bash
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D66-shell-bash-still-earns "$P" \
  'the built-in bash keyword is documented with set -e -o pipefail — writing it out explicitly must not be a red'

echo "=== D67-shell-sh-still-earns ==="
P="$TOPTMP/d67"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        shell: sh
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D67-shell-sh-still-earns "$P" \
  'sh is documented with set -e as well, and the allowlist is the documented fail-fast set rather than one favoured spelling'

# The same vector one LEVEL UP. `defaults.run.shell` sets the interpreter for
# every run step of a job (or of the whole workflow) with no `shell:` key on the
# step at all, so a detector that reads only the step key would have shipped a
# condition anyone could step around by moving one line. Handled by precedence
# rather than by a blanket refusal: step > job defaults > workflow defaults.
echo "=== D68-job-defaults-shell-withheld ==="
P="$TOPTMP/d68"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash {0}
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
          echo "gate done"
YML
assert_withheld D68-job-defaults-shell-withheld "$P" "the job's 'defaults.run.shell' is 'bash {0}'" \
  'the job default reaches the gate step with no shell: key on the step, and it is the same swallow'

echo "=== D69-workflow-defaults-shell-withheld ==="
P="$TOPTMP/d69"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

defaults:
  run:
    shell: bash {0}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
          echo "gate done"
YML
assert_withheld D69-workflow-defaults-shell-withheld "$P" "the workflow's 'defaults.run.shell' is 'bash {0}'" \
  'and again at workflow level, which no step-scoped read would ever see'

echo "=== D70-step-shell-overrides-a-bad-job-default ==="
P="$TOPTMP/d70"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

defaults:
  run:
    shell: bash {0}

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash {0}
    steps:
      - name: Governance - Phase gate check
        shell: bash
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D70-step-shell-overrides-a-bad-job-default "$P" \
  'PRECEDENCE, not a blanket refusal: the step key wins over both defaults blocks, so a file that is actually fail-fast is not a false red'

# ── D71 / D72: two more recorded residuals, in the product and pinned ────────
# Same treatment as # D-A-RESIDUAL-HEREDOC-DATA: the marker lives in the code so
# the next reader meets it, and the behaviour it describes is ASSERTED, so
# closing one is a deliberate change with its own proof rather than a surprise.
echo "=== D71-env-shadow-residual-is-recorded ==="
grep -qF '# D-A-RESIDUAL-ENV-SHADOW' "$CHECK_GATE" \
  && pass "D71-env-shadow-residual-is-recorded (the presence-test blind spot is named where MAPSCOPE is built)" \
  || fail_ "D71-env-shadow-residual-is-recorded" "the env-shadow residual is no longer recorded — a known fail-open becomes an undocumented one"
P="$TOPTMP/d71"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

env:
  GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_earns_ok D71b-env-shadow-behaves-as-recorded "$P" \
  'RECORDED RESIDUAL, not an endorsement: maps is a PRESENCE test over the union of the three scopes, so a step-level GH_TOKEN that SHADOWS the workflow-level mapping is invisible to it'

echo "=== D72-run-body-disarm-residual-is-recorded ==="
grep -qF '# D-A-RESIDUAL-RUN-BODY-DISARM' "$CHECK_GATE" \
  && pass "D72-run-body-disarm-residual-is-recorded (the OK sentence does not silently overclaim for bash control flow)" \
  || fail_ "D72-run-body-disarm-residual-is-recorded" "the run-body residual is gone — the shell condition would read as more than it is"
P="$TOPTMP/d72"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          set +e
          bash scripts/check-phase-gate.sh
          exit 0
YML
assert_earns_ok D72b-run-body-disarm-behaves-as-recorded "$P" \
  'RECORDED RESIDUAL: `set +e` … `exit 0` inside the run body disarms the gate with a fail-fast shell and a byte-exact invocation. Telling code from data in a run body needs a bash lexer — same difficulty as # D-A-RESIDUAL-HEREDOC-DATA, and the reason BL-218 exists'

# ════════════════════════════════════════════════════════════════════════════
# DM1-DM8 — the other direction. Each mutant neuters ONE line and the false
# claim comes back. mk_cg_mutant asserts the harness standard for every one of
# them: sites==1 for the anchored end-of-line marker, exactly-N-lines-changed,
# a lib-complete copy, and `bash -n` on the result — a mutant that merely fails
# to parse proves nothing. Each gets a FRESH fixture.
# ════════════════════════════════════════════════════════════════════════════

echo "=== DM1-maps-gate-carries-D2 ==="
P="$TOPTMP/dm1"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD" no emitted
assert_mutant_false_ok DM1-maps-gate-carries-D2 mapsgate \
  '# D-A-MAPS-GATE$' '/# D-A-MAPS-GATE$/d' 1 0 \
  "$P" "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
  'without the maps term an unmapped workflow is told the next push enforces'

echo "=== DM2-invokes-gate-carries-D1 ==="
P="$TOPTMP/dm2"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD" yes nogate
assert_mutant_false_ok DM2-invokes-gate-carries-D1 invokesgate \
  '# D-A-INVOKES-GATE$' '/# D-A-INVOKES-GATE$/d' 1 0 \
  "$P" "INVOKES the phase gate" \
  'without the invokes term a workflow that runs NO gate is told the next push enforces — defect 1, reproduced'

echo "=== DM3-swallows-gate-carries-D3 ==="
P="$TOPTMP/dm3"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        continue-on-error: true" yes emitted
assert_mutant_false_ok DM3-swallows-gate-carries-D3 swallowsgate \
  '# D-A-SWALLOWS-GATE$' '/# D-A-SWALLOWS-GATE$/d' 1 0 \
  "$P" "carries 'continue-on-error: true'" \
  'without the swallows term a step graded green regardless of the verdict is told the next push enforces — defect 2, reproduced'

echo "=== DM4-step-coe-verdict-carries-D3 ==="
P="$TOPTMP/dm4"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        continue-on-error: true" yes emitted
assert_mutant_false_ok DM4-step-coe-verdict-carries-D3 stepcoe \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-STEP-COE-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-STEP-COE-VERDICT$@\1:@' 1 1 \
  "$P" "carries 'continue-on-error: true'" \
  'the continue-on-error arm, not something else, is what refuses D3'

echo "=== DM5-step-if-verdict-carries-D4 ==="
P="$TOPTMP/dm5"; mk_tok_wf "$P" "" "        if: false" yes emitted
assert_mutant_false_ok DM5-step-if-verdict-carries-D4 stepif \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-STEP-IF-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-STEP-IF-VERDICT$@\1:@' 1 1 \
  "$P" "condition is 'if: false'" \
  'the if: allowlist, not the key allowlist, is what refuses D4'

echo "=== DM6-step-key-verdict-carries-D5 ==="
P="$TOPTMP/dm6"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        on-failure: continue" yes emitted
assert_mutant_false_ok DM6-step-key-verdict-carries-D5 stepkey \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-STEP-KEY-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-STEP-KEY-VERDICT$@\1:@' 1 1 \
  "$P" "does not recognise: on-failure" \
  'the step key allowlist is what refuses the unimagined sibling'

echo "=== DM7-job-verdict-carries-D6 ==="
P="$TOPTMP/dm7"; mk_tok_wf "$P" "    if: false" "$STEP_KEYS_GOOD" yes emitted
assert_mutant_false_ok DM7-job-verdict-carries-D6 jobverdict \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-JOB-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-JOB-VERDICT$@\1:@' 1 1 \
  "$P" "The job that HOLDS the phase-gate step carries 'if: false'" \
  'the job-level arm is what refuses D6 — a step-scoped detector alone is blind to it'

echo "=== DM8-unlocated-verdict-carries-D8 ==="
P="$TOPTMP/dm8"; mk_tok "$P" github ok yes
printf 'runs:\n  using: composite\n  steps:\n    - name: Governance - Phase gate check\n      env:\n        GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n      run: |\n        if [ ! -f scripts/check-phase-gate.sh ]; then\n          echo "::error::Phase gate check script missing. Framework integrity compromised."\n          exit 1\n        fi\n        bash scripts/check-phase-gate.sh\n' \
  > "$P/.github/workflows/ci.yml"
assert_mutant_false_ok DM8-unlocated-verdict-carries-D8 unlocated \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-UNLOCATED-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-UNLOCATED-VERDICT$@\1:@' 1 1 \
  "$P" "Could not locate the job that runs the gate" \
  'without the fail-closed arm an unreadable structure is told the next push enforces'

# ════════════════════════════════════════════════════════════════════════════
# DM9-DM14 — the fix round's mutants. Four of the six edit the awk program
# inside _wf_gate_scope, where `bash -n` proves nothing: a mangled awk program
# is still valid SHELL, and a dead awk prints an empty scope report, which reads
# downstream as "no swallowing key found" — the false OK, for the wrong reason.
# Those four therefore use assert_mutant_false_ok_ctl, which also drives the
# same mutant against a fixture whose swallow is spelled the ORDINARY way and
# requires it to STILL be refused.
# ════════════════════════════════════════════════════════════════════════════

# The liveness control, shared: the plainest swallow there is.
DMCTL="$TOPTMP/dmctl"; mk_tok_wf "$DMCTL" "" "$STEP_KEYS_GOOD
        continue-on-error: true" yes emitted
DMCTL_SIG="carries 'continue-on-error: true'"

echo "=== DM9-crlf-strip-carries-D16 ==="
P="$TOPTMP/dm9"; mk_tok_wf_crlf "$P" "" "$STEP_KEYS_GOOD" yes emitted
assert_mutant_refuses DM9-crlf-strip-carries-D16 crlfstrip \
  '# D-A-CRLF-STRIP$' '/# D-A-CRLF-STRIP$/d' 1 0 \
  "$P" "which is not the one this framework ships" \
  'without the strip a correctly-wired CRLF workflow is falsely refused — R-dA-1, reproduced'

echo "=== DM10-crlf-strip-is-anchored-carries-D18 ==="
P="$TOPTMP/dm10"; mk_tok_wf_crlf "$P" "" "        if: hashFiles('.claude/phase-state.json')${CRB} != ''" yes emitted
DMCTL_CRLF="$TOPTMP/dmctlcrlf"; mk_tok_wf_crlf "$DMCTL_CRLF" "" "$STEP_KEYS_GOOD
        continue-on-error: true" yes emitted
assert_mutant_false_ok_ctl DM10-crlf-strip-is-anchored-carries-D18 crlfgsub \
  '# D-A-CRLF-STRIP$' \
  's@^\([[:space:]]*\){ sub(CR .*# D-A-CRLF-STRIP$@\1{ gsub(CR, "", L[NR]) }@' 1 1 \
  "$P" "which is not the one this framework ships" \
  "$DMCTL_CRLF" "$DMCTL_SIG" \
  'widened from sub(…$) to gsub, a CR inside the value is eaten and a DIFFERENT if: is repaired into the shipped one'

echo "=== DM11-quoted-key-dq-carries-D19 ==="
P="$TOPTMP/dm11"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        \"continue-on-error\": true" yes emitted
assert_mutant_false_ok_ctl DM11-quoted-key-dq-carries-D19 quotedq \
  '# D-A-QUOTED-KEY-DQ$' '/# D-A-QUOTED-KEY-DQ$/d' 1 0 \
  "$P" "$DMCTL_SIG" \
  "$DMCTL" "$DMCTL_SIG" \
  'without the double-quote arm an inert step is told the next push enforces — R-dA-2, reproduced'

echo "=== DM12-quoted-key-sq-carries-D20 ==="
P="$TOPTMP/dm12"; mk_tok_wf "$P" "" "        'if': false" yes emitted
assert_mutant_false_ok_ctl DM12-quoted-key-sq-carries-D20 quotesq \
  '# D-A-QUOTED-KEY-SQ$' '/# D-A-QUOTED-KEY-SQ$/d' 1 0 \
  "$P" "condition is 'if: false'" \
  "$DMCTL" "$DMCTL_SIG" \
  'the single-quote arm is a SEPARATE arm — the double-quote one does not cover it'

echo "=== DM13-spaced-key-carries-D24 ==="
P="$TOPTMP/dm13"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        continue-on-error : true" yes emitted
assert_mutant_false_ok_ctl DM13-spaced-key-carries-D24 spacedkey \
  '# D-A-SPACED-KEY$' \
  's@^\([[:space:]]*\)if (c !~ .*# D-A-SPACED-KEY$@\1if (c !~ /^[A-Za-z_][A-Za-z0-9_-]*:/) return@' 1 1 \
  "$P" "$DMCTL_SIG" \
  "$DMCTL" "$DMCTL_SIG" \
  'narrow the key guard by the one [ ]* and the spaced spelling goes invisible again'

echo "=== DM14-merge-verdict-carries-D25 ==="
P="$TOPTMP/dm14"; mk_tok_wf "$P" "" "$STEP_KEYS_GOOD
        <<: *soft" yes emitted
printf 'x-soft: &soft\n  continue-on-error: true\n' >> "$P/.github/workflows/ci.yml"
assert_mutant_false_ok "DM14-merge-verdict-carries-D25" mergeverdict \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-MERGE-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-MERGE-VERDICT$@\1:@' 1 1 \
  "$P" "$(merge_sig step)" \
  'without the fail-closed merge arm a step whose real configuration is in an anchor is told the next push enforces'

echo "=== DM15-job-id-closed-carries-D29 ==="
P="$TOPTMP/dm15"; mk_jobid_wf "$P" '  test: &jobdefaults' ""
assert_mutant_false_ok_ctl DM15-job-id-closed-carries-D29 jobidclosed \
  '# D-A-JOB-ID-CLOSED$' '/# D-A-JOB-ID-CLOSED$/d' 1 0 \
  "$P" "Could not locate the job that runs the gate" \
  "$DMCTL" "$DMCTL_SIG" \
  'without the fail-closed job-id guard an unreadable enclosing line is scanned as if it were the job'

# ════════════════════════════════════════════════════════════════════════════
# DM16-DM26 — fix round 2. Eight of the eleven edit the awk program inside
# _wf_gate_scope, so they carry the liveness control: `bash -n` only parses the
# SHELL, and a dead awk prints an empty scope report which reads downstream as
# "no swallowing key found". Two of them use assert_mutant_refuses instead,
# because the line they neuter exists to prevent a false RED — and that assert
# is itself dead-awk-proof, since a dead awk earns the claim rather than
# refusing. One uses assert_mutant_drops_cause, for a line that decides which
# cause is named rather than whether the claim is withheld.
# ════════════════════════════════════════════════════════════════════════════

echo "=== DM16-invokes-floor-threshold-carries-D37 ==="
P="$TOPTMP/dm16"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          if [ ! -f scripts/check-phase-gate.sh ]; then
            echo "::error::Phase gate check script missing. Framework integrity compromised."
            exit 1
          fi
YML
assert_mutant_false_ok DM16-invokes-floor-threshold-carries-D37 invfloor \
  '# D-A-INVOKES-FLOOR$' \
  's@^\([[:space:]]*\)if \[ "\$wf_n_inv" -ge 1 \]; then.*# D-A-INVOKES-FLOOR$@\1if [ "$wf_n_inv" -ge 0 ]; then@' 1 1 \
  "$P" "INVOKES the phase gate" \
  'the THRESHOLD, not the marker: -ge 0 is satisfied by zero invocations and a guard-only workflow is told the next push enforces'

echo "=== DM17-lone-dash-climb-carries-D31 ==="
P="$TOPTMP/dm17"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
    steps:
      - name: Setup
        run: echo hi
      -
        name: Governance - Phase gate check
        continue-on-error: true
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_false_ok_ctl DM17-lone-dash-climb-carries-D31 lonedashclimb \
  '# D-A-LONE-DASH-CLIMB$' \
  's@^\([[:space:]]*\)for (i = hit; i >= 1; i--) if ((L\[i\] " ") ~ /\^ \*- /) { st = i; break }.*# D-A-LONE-DASH-CLIMB$@\1for (i = hit; i >= 1; i--) if (L[i] ~ /^ *- /) { st = i; break }@' 1 1 \
  "$P" "$DMCTL_SIG" \
  "$DMCTL" "$DMCTL_SIG" \
  'take the appended space away and the climb needs a space after the dash again, binds to the PREVIOUS step and reads its keys — R-CTE-1, reproduced'

echo "=== DM18-lone-dash-keycol-carries-D33 ==="
P="$TOPTMP/dm18"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      -
        name: Governance - Phase gate check
        continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_false_ok_ctl DM18-lone-dash-keycol-carries-D33 lonedashkeycol \
  '# D-A-LONE-DASH-KEYCOL$' \
  's@^\([[:space:]]*\)if (c == "") {.*# D-A-LONE-DASH-KEYCOL$@\1if (0) {@' 1 1 \
  "$P" "$DMCTL_SIG" \
  "$DMCTL" "$DMCTL_SIG" \
  'finding the lone-dash step is only half of it — without the derived key column the column is one past the dash and NO key is ever read'

echo "=== DM19-folded-run-emit-carries-D35 ==="
P="$TOPTMP/dm19"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: hashFiles('.claude/phase-state.json') != ''
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: >
          bash scripts/check-phase-gate.sh
          || true
YML
assert_mutant_false_ok_ctl DM19-folded-run-emit-carries-D35 foldedemit \
  '# D-A-FOLDED-RUN$' '/# D-A-FOLDED-RUN$/d' 1 0 \
  "$P" "FOLDED block scalar" \
  "$DMCTL" "$DMCTL_SIG" \
  'without the folded-scalar report every line-wise check passes on a step whose effective command is the canonical swallow — R-CTE-2, reproduced'

echo "=== DM20-folded-run-verdict-carries-D35 ==="
P="$TOPTMP/dm20"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: >
          bash scripts/check-phase-gate.sh
          || true
YML
assert_mutant_false_ok DM20-folded-run-verdict-carries-D35 foldedverdict \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-FOLDED-RUN-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-FOLDED-RUN-VERDICT$@\1:@' 1 1 \
  "$P" "FOLDED block scalar" \
  'and the fail-closed arm is a term of its own — reporting the fold without acting on it would claim enforcement anyway'

echo "=== DM21-comment-strip-carries-D38 ==="
P="$TOPTMP/dm21"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: hashFiles('.claude/phase-state.json') != '' # phase gate
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_refuses DM21-comment-strip-carries-D38 commentstrip \
  '# D-A-COMMENT-STRIP$' '/# D-A-COMMENT-STRIP$/d' 1 0 \
  "$P" "which is not the one this framework ships" \
  'without the strip the comment rides on the value and a correctly-wired project is told its own condition is not its own condition — R-CTE-5, reproduced'

echo "=== DM22-comment-strip-is-quote-aware-carries-D40 ==="
P="$TOPTMP/dm22"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: "hashFiles('.claude/phase-state.json') != '' # not really"
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_drops_cause DM22-comment-strip-is-quote-aware-carries-D40 naivestrip \
  '# D-A-COMMENT-INSIDE-QUOTES$' '/# D-A-COMMENT-INSIDE-QUOTES$/d' 1 0 \
  "$P" "condition is 'if: \"hashFiles('.claude/phase-state.json') != '' # not really\"'" \
  'stop opening the quote and the strip eats content out of a genuinely quoted scalar: still refused, but the condition quoted back at the user is truncated at the hash'

echo "=== DM22b-quotes-only-open-a-scalar-carries-D40b ==="
P="$TOPTMP/dm22b"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        if: contains(github.event.head_commit.message, ' #skip')
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_drops_cause DM22b-quotes-only-open-a-scalar-carries-D40b scalarstart \
  '# D-A-COMMENT-INSIDE-QUOTES$' \
  's@^\([[:space:]]*\)if (st == 0 \&\& ch != " ") @\1if (ch != " ") @' 1 1 \
  "$P" "condition is 'if: contains(github.event.head_commit.message, ''" \
  'drop the opens-the-scalar test and a quote ANYWHERE starts quoting, which is the reading PyYAML contradicts: the plain scalar is no longer ended at the space-hash'

echo "=== DM22c-comment-needs-preceding-space-carries-D58 ==="
P="$TOPTMP/dm22c"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        continue-on-error: false#note
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_false_ok_ctl DM22c-comment-needs-preceding-space-carries-D58 hashnospace \
  '# D-A-COMMENT-STRIP$' \
  's@^\([[:space:]]*\)if (ch == "#" \&\& i > 1 \&\& substr(s, i - 1, 1) == " ") break.*# D-A-COMMENT-STRIP$@\1if (ch == "#" \&\& i > 1) break@' 1 1 \
  "$P" "carries 'continue-on-error: false#note'" \
  "$DMCTL" "$DMCTL_SIG" \
  'relax the strip to any # and a value that is really the string false#note is truncated into the boolean false — the one value that earns the claim'

echo "=== DM23-anchor-comment-carries-D41 ==="
P="$TOPTMP/dm23"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps: # the governance job's steps
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_refuses DM23-anchor-comment-carries-D41 anchorcomment \
  '# D-A-ANCHOR-COMMENT$' \
  's@^\([[:space:]]*\)for (i = st; i >= 1; i--) if (decomment(L\[i\]) ~ @\1for (i = st; i >= 1; i--) if (L[i] ~ @' 1 1 \
  "$P" "Could not locate the job that runs the gate" \
  'the anchors need the same comment handling the values do, or one comment on steps: takes the whole job out of reach'

echo "=== DM24-maps-scope-carries-D43 ==="
P="$TOPTMP/dm24"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Other step
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: echo hi
      - name: Governance - Phase gate check
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_false_ok_ctl DM24-maps-scope-carries-D43 mapsscope \
  '# D-A-MAPS-SCOPE$' \
  's@^\([[:space:]]*\)if \[ -n "\$wf_mapscope" \].*# D-A-MAPS-SCOPE$@\1wf_maps_src="$wf_exec"@' 1 1 \
  "$P" "does not map SOIF_PROTECTION_TOKEN into the phase-gate step" \
  "$DMCTL" "$DMCTL_SIG" \
  'read the whole file again and a secret in a sibling step earns "maps it into the phase-gate step" — R-CTE-6, reproduced'

echo "=== DM25-dup-key-verdict-carries-D47 ==="
P="$TOPTMP/dm25"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        continue-on-error: false
        continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_false_ok DM25-dup-key-verdict-carries-D47 dupkey \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-DUP-KEY-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-DUP-KEY-VERDICT$@\1:@' 1 1 \
  "$P" "declared TWICE" \
  'without the duplicate arm the first value wins by accident of head -1 and a step whose effective continue-on-error is true is told the next push enforces — R-CTE-7, reproduced'

echo "=== DM26-invokes-whole-line-carries-D53 ==="
P="$TOPTMP/dm26"; mk_tok "$P" github ok custom 'bash scripts/check-phase-gate.sh || true'
assert_mutant_drops_cause DM26-invokes-whole-line-carries-D53 invwholeline \
  '# D-A-INVOKES-WHOLE-LINE$' \
  's@grep -cxF -- "\$wf_allow_invoke" || true)   # D-A-INVOKES-WHOLE-LINE$@grep -cF -- "$wf_allow_invoke" || true)@' 1 1 \
  "$P" "INVOKES the phase gate" \
  'drop the whole-line anchor and a swallowed line COUNTS as an invocation: the verdict survives on the deviation scan alone, but the user loses one of the two edits they need'

# ════════════════════════════════════════════════════════════════════════════
# DM27-DM35 — the scope-report anchors. ONE fixture (mk_sentinel_wf, D59), nine
# mutants, each removing exactly ONE anchor character and each getting exactly
# ONE named refusal back on a workflow that is correctly wired. These are the
# INVERTED direction — the atoms prevent a false RED — so assert_mutant_refuses
# is the right assertion and the named cause is what proves the mutant did not
# simply break something else. The round-2 report claimed these atoms "cannot
# change a verdict"; every one of them can, and this is the measurement.
# ════════════════════════════════════════════════════════════════════════════

echo "=== DM27-scope-anchor-step-none-carries-D59 ==="
P="$TOPTMP/dm27"; mk_sentinel_wf "$P"
assert_mutant_refuses DM27-scope-anchor-step-none-carries-D59 anchstepnone \
  '# D-A-SCOPE-GRAMMAR-STEP-NONE$' \
  's@grep -qx \(.\)STEP none\(.\)\(.*\)# D-A-SCOPE-GRAMMAR-STEP-NONE$@grep -q \1STEP none\2\3# D-A-SCOPE-GRAMMAR-STEP-NONE@' 1 1 \
  "$P" "Could not locate the step that runs the gate" \
  'drop -x and a run body that echoes the sentinel is re-read as MAPSCOPE structure: the step is reported unlocatable and a correct file is refused'

echo "=== DM28-scope-anchor-job-none-carries-D59 ==="
P="$TOPTMP/dm28"; mk_sentinel_wf "$P"
assert_mutant_refuses DM28-scope-anchor-job-none-carries-D59 anchjobnone \
  '# D-A-SCOPE-GRAMMAR-JOB-NONE$' \
  's@grep -qx \(.\)JOB none\(.\)\(.*\)# D-A-SCOPE-GRAMMAR-JOB-NONE$@grep -q \1JOB none\2\3# D-A-SCOPE-GRAMMAR-JOB-NONE@' 1 1 \
  "$P" "Could not locate the job that runs the gate" \
  'same one level up — terminality does not save it, because MAPSCOPE lines are printed by a DIFFERENT exit path than the one that prints JOB none'

echo "=== DM29-scope-anchor-stepkey-coe-carries-D59 ==="
P="$TOPTMP/dm29"; mk_sentinel_wf "$P"
assert_mutant_refuses DM29-scope-anchor-stepkey-coe-carries-D59 anchstepcoe \
  '# D-A-SCOPE-GRAMMAR-STEPKEY-COE$' \
  's@grep -cx \(.\)STEPKEY continue-on-error\(.\)\(.*\)# D-A-SCOPE-GRAMMAR-STEPKEY-COE$@grep -c \1STEPKEY continue-on-error\2\3# D-A-SCOPE-GRAMMAR-STEPKEY-COE@' 1 1 \
  "$P" "which grades a FAILED step as success" \
  'the superstring argument was answered with the wrong stream: a MAPSCOPE line CONTAINS the token without being a step key at all'

echo "=== DM30-scope-anchor-stepkey-if-carries-D59 ==="
P="$TOPTMP/dm30"; mk_sentinel_wf "$P"
assert_mutant_refuses DM30-scope-anchor-stepkey-if-carries-D59 anchstepif \
  '# D-A-SCOPE-GRAMMAR-STEPKEY-IF$' \
  's@grep -cx \(.\)STEPKEY if\(.\)\(.*\)# D-A-SCOPE-GRAMMAR-STEPKEY-IF$@grep -c \1STEPKEY if\2\3# D-A-SCOPE-GRAMMAR-STEPKEY-IF@' 1 1 \
  "$P" "which is not the one this framework ships" \
  'and the file is then told its own ABSENT condition is the wrong condition — the self-refuting refusal the CRLF fix removed once already'

echo "=== DM31-scope-anchor-stepkey-shell-carries-D59 ==="
P="$TOPTMP/dm31"; mk_sentinel_wf "$P"
assert_mutant_refuses DM31-scope-anchor-stepkey-shell-carries-D59 anchstepshell \
  '# D-A-SCOPE-GRAMMAR-STEPKEY-SHELL$' \
  's@grep -cx \(.\)STEPKEY shell\(.\)\(.*\)# D-A-SCOPE-GRAMMAR-STEPKEY-SHELL$@grep -c \1STEPKEY shell\2\3# D-A-SCOPE-GRAMMAR-STEPKEY-SHELL@' 1 1 \
  "$P" "$SHELL_SIG" \
  'the FOURTH condition reads the same grammar and inherits the same trap — pinned when it was written, not three rounds later'

echo "=== DM32-scope-anchor-stepmerge-carries-D59 ==="
P="$TOPTMP/dm32"; mk_sentinel_wf "$P"
assert_mutant_refuses DM32-scope-anchor-stepmerge-carries-D59 anchstepmerge \
  '# D-A-SCOPE-GRAMMAR-STEPMERGE$' \
  's@grep -q \(.\)\(.\)STEPMERGE \(.\)\(.*\)# D-A-SCOPE-GRAMMAR-STEPMERGE$@grep -q \1STEPMERGE \3\4# D-A-SCOPE-GRAMMAR-STEPMERGE@' 1 1 \
  "$P" "A YAML merge key on the gate's step" \
  'the ^ anchors are the same class as the -x flags, and nobody named these two: measured, then pinned'

echo "=== DM33-scope-anchor-jobmerge-carries-D59 ==="
P="$TOPTMP/dm33"; mk_sentinel_wf "$P"
assert_mutant_refuses DM33-scope-anchor-jobmerge-carries-D59 anchjobmerge \
  '# D-A-SCOPE-GRAMMAR-JOBMERGE$' \
  's@grep -q \(.\)\(.\)JOBMERGE \(.\)\(.*\)# D-A-SCOPE-GRAMMAR-JOBMERGE$@grep -q \1JOBMERGE \3\4# D-A-SCOPE-GRAMMAR-JOBMERGE@' 1 1 \
  "$P" "A YAML merge key on the gate's job" \
  'and its sibling'

echo "=== DM34-scope-anchor-stepopaque-carries-D59 ==="
P="$TOPTMP/dm34"; mk_sentinel_wf "$P"
assert_mutant_refuses DM34-scope-anchor-stepopaque-carries-D59 anchstepopaque \
  '# D-A-SCOPE-GRAMMAR-STEPOPAQUE$' \
  's@grep -q \(.\)\(.\)STEPOPAQUE \(.\)\(.*\)# D-A-SCOPE-GRAMMAR-STEPOPAQUE$@grep -q \1STEPOPAQUE \3\4# D-A-SCOPE-GRAMMAR-STEPOPAQUE@' 1 1 \
  "$P" "$OPAQUE_SIG" \
  'the new arm ships with its anchor pinned, so the grammar cannot grow another hole quietly'

echo "=== DM35-scope-anchor-jobopaque-carries-D59 ==="
P="$TOPTMP/dm35"; mk_sentinel_wf "$P"
assert_mutant_refuses DM35-scope-anchor-jobopaque-carries-D59 anchjobopaque \
  '# D-A-SCOPE-GRAMMAR-JOBOPAQUE$' \
  's@grep -q \(.\)\(.\)JOBOPAQUE \(.\)\(.*\)# D-A-SCOPE-GRAMMAR-JOBOPAQUE$@grep -q \1JOBOPAQUE \3\4# D-A-SCOPE-GRAMMAR-JOBOPAQUE@' 1 1 \
  "$P" "$OPAQUE_SIG" \
  'and its sibling'

# ════════════════════════════════════════════════════════════════════════════
# DM36-DM43 — the two new arms: the opaque key shapes and the FOURTH condition.
# Every mutant that edits the awk program inside _wf_gate_scope is driven
# against the ordinary-spelling control as well, because `bash -n` cannot tell a
# live awk program from a dead one and a dead one prints the false OK.
# ════════════════════════════════════════════════════════════════════════════

echo "=== DM36-opaque-key-carries-D60 ==="
P="$TOPTMP/dm36"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        !!str continue-on-error: true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_false_ok_ctl DM36-opaque-key-carries-D60 opaquekey \
  '# D-A-OPAQUE-KEY$' '/# D-A-OPAQUE-KEY$/d' 1 0 \
  "$P" "$OPAQUE_SIG" \
  "$DMCTL" "$DMCTL_SIG" \
  'without the report the tagged key is not a key at all, the swallow is unseen and the claim comes back'

echo "=== DM37-opaque-verdict-carries-D60 ==="
P="$TOPTMP/dm37"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        ? continue-on-error
        : true
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_false_ok DM37-opaque-verdict-carries-D60 opaqueverdict \
  '^[[:space:]]*wf_swallows=1[[:space:]]*# D-A-OPAQUE-VERDICT$' \
  's@^\([[:space:]]*\)wf_swallows=1[[:space:]]*# D-A-OPAQUE-VERDICT$@\1:@' 1 1 \
  "$P" "$OPAQUE_SIG" \
  'reporting the shape without failing closed on it is the silent-ignore this whole surface keeps re-learning'

echo "=== DM38-failfast-gate-carries-D64 ==="
P="$TOPTMP/dm38"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        shell: bash {0}
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
          echo "gate done"
YML
assert_mutant_false_ok DM38-failfast-gate-carries-D64 failfastgate \
  '# D-A-FAILFAST-GATE$' '/# D-A-FAILFAST-GATE$/d' 1 0 \
  "$P" "$SHELL_SIG" \
  'ONE TERM PER LINE: neuter the fourth term alone and the custom-template file is told the next push enforces the check — R-CTE-8, reproduced'

echo "=== DM39-shell-value-carries-D66 ==="
P="$TOPTMP/dm39"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        shell: bash
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_refuses DM39-shell-value-carries-D66 shellvalue \
  '# D-A-SHELL-VALUE$' '/# D-A-SHELL-VALUE$/d' 1 0 \
  "$P" "$SHELL_SIG" \
  'stop emitting the value and presence alone survives, so an explicitly CORRECT shell: bash is refused — the arm fails closed on its own blindness, which is right, and that is exactly why the emission has to be pinned separately'

echo "=== DM40-defaults-job-carries-D68 ==="
P="$TOPTMP/dm40"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash {0}
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
          echo "gate done"
YML
assert_mutant_false_ok_ctl DM40-defaults-job-carries-D68 defaultsjob \
  '# D-A-DEFAULTS-JOB$' '/# D-A-DEFAULTS-JOB$/d' 1 0 \
  "$P" "$SHELL_SIG" \
  "$DMCTL" "$DMCTL_SIG" \
  'without the job defaults walk the condition is bypassable by moving one line up one level — the shape a step-scoped read can never see'

echo "=== DM41-defaults-wf-carries-D69 ==="
P="$TOPTMP/dm41"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

defaults:
  run:
    shell: bash {0}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
          echo "gate done"
YML
assert_mutant_false_ok_ctl DM41-defaults-wf-carries-D69 defaultswf \
  '# D-A-DEFAULTS-WF$' '/# D-A-DEFAULTS-WF$/d' 1 0 \
  "$P" "$SHELL_SIG" \
  "$DMCTL" "$DMCTL_SIG" \
  'and the workflow-level block, which is not even inside the job the scan reads'

echo "=== DM42-shell-allowlist-carries-D67 ==="
P="$TOPTMP/dm42"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Governance - Phase gate check
        shell: sh
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_refuses DM42-shell-allowlist-carries-D67 shellallow \
  '# D-A-SHELL-ALLOWLIST$' \
  's@bash|sh) ;;\(.*\)# D-A-SHELL-ALLOWLIST$@bash) ;;\1# D-A-SHELL-ALLOWLIST@' 1 1 \
  "$P" "$SHELL_SIG" \
  'narrow the allowlist by one documented fail-fast keyword and a legitimate sh step is refused — the WIDTH of the set is contract, not just its existence'

echo "=== DM43-shell-precedence-step-carries-D70 ==="
P="$TOPTMP/dm43"; mk_raw_wf "$P" <<'YML'
name: CI
on:
  push:
    branches: [main]

defaults:
  run:
    shell: bash {0}

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash {0}
    steps:
      - name: Governance - Phase gate check
        shell: bash
        env:
          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}
        run: |
          bash scripts/check-phase-gate.sh
YML
assert_mutant_refuses DM43-shell-precedence-step-carries-D70 shellprec \
  '# D-A-SHELL-PRECEDENCE-STEP$' '/# D-A-SHELL-PRECEDENCE-STEP$/d' 1 0 \
  "$P" "$SHELL_SIG" \
  'the arms are written LAST-WINS in GitHub precedence order, so deleting the step arm lets a job default outrank the key that actually governs and a fail-fast file is falsely refused'

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

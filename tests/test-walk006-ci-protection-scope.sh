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

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

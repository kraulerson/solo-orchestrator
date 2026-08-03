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

# mk_tok <dir> <host> <auth: ok|unauth> [ci.yml-wires-secret: yes|no]
mk_tok() {
  local d="$1" host="$2" auth="$3" wired="${4:-yes}"
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
  if [ "$wired" = yes ]; then
    printf 'jobs:\n  test:\n    steps:\n      - name: Governance - Phase gate check\n        env:\n          GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}\n' \
      > "$d/.github/workflows/ci.yml"
  else
    printf 'jobs:\n  test:\n    steps:\n      - name: Governance - Phase gate check\n' \
      > "$d/.github/workflows/ci.yml"
  fi
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
printf '%s' "$out" | grep -q "already maps SOIF_PROTECTION_TOKEN" || ok=0
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
   && printf '%s' "$out" | grep -q "does not map SOIF_PROTECTION_TOKEN yet" \
   && printf '%s' "$out" | grep -q 'GH_TOKEN: ${{ secrets.SOIF_PROTECTION_TOKEN }}'; then
  pass "S6-unwired-workflow-warned (names the gap and prints the exact lines to add)"
else
  fail_ "S6-unwired-workflow-warned" "rc=$rc: $out"
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

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

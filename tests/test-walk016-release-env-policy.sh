#!/usr/bin/env bash
# tests/test-walk016-release-env-policy.sh — walk 2026-08-02 ISSUE-016 (Major):
# `check-gate.sh --release-env-policy` must catch the GitHub Pages deployment
# environment policy that silently rejects tag-triggered releases.
#
# WHY THIS EXISTS
#   The framework's documented happy path is "git tag v1.0.0 && git push --tags",
#   and the emitted release.yml triggers on `tags: ['v*']`. Enabling GitHub Pages
#   auto-creates a `github-pages` deployment environment whose default branch
#   policy admits the DEFAULT BRANCH ONLY. A run triggered from a TAG is rejected
#   by the environment's protection rules BEFORE any job starts: empty step list,
#   no readable error in `gh run view`. The walker lost 18 minutes and needed an
#   undocumented API call to escape.
#
#   THE FIX HAD TO BE A SCRIPT, NOT A WORKFLOW STEP: a run the environment
#   rejects never starts a job, so an in-workflow preflight is unreachable by
#   construction. This subcommand runs from the workstation, before the tag.
#
# THE CONTRACT (# WALK-ISSUE-016-RELEASE-ENV-POLICY)
#   dry-run (default): exit 1 iff a tag deploy would be rejected, printing the
#   exact remediation; exit 0 when it would be admitted, when the environment
#   does not exist yet, and when the host is not GitHub. `--fix` applies it.
#
# FIXTURE MECHANICS: a PATH-prepended `gh` stub answers from JSON fixture files
# and APPENDS every invocation to a log, so write calls are asserted by
# inspection rather than by network effect. Hermetic: no network, no real
# remote (BL-076), no `gh auth`.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (fixtures + policy parsing)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_proj <dir> <host> <env-json|NONE> <policies-json>
mk_proj() {
  local d="$1" host="$2" envj="$3" polj="$4"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/scripts/host-drivers" "$d/bin" "$d/stub"
  jq -n --arg h "$host" '{frameworkVersion:"test", host:$h, mode:"personal"}' \
    > "$d/.claude/manifest.json"
  ( cd "$d" && git init -q \
      && git config user.email t@t.invalid && git config user.name t \
      && git remote add origin https://github.com/example/walk016.git ) || return 1
  cp "$REPO_ROOT/scripts/lib/"*.sh "$d/scripts/lib/"
  cp "$REPO_ROOT/scripts/host-drivers/github.sh" "$d/scripts/host-drivers/"

  [ "$envj" = NONE ] || printf '%s' "$envj" > "$d/stub/env.json"
  printf '%s' "$polj" > "$d/stub/policies.json"
  : > "$d/stub/gh.log"

  cat > "$d/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_DIR/gh.log"
case "$*" in
  *"-X POST"*deployment-branch-policies*) exit 0 ;;
  *"-X PUT"*environments*)                cat >/dev/null 2>&1; exit 0 ;;
  *deployment-branch-policies*)           cat "$GH_STUB_DIR/policies.json"; exit 0 ;;
  *environments/*)
      if [ -f "$GH_STUB_DIR/env.json" ]; then cat "$GH_STUB_DIR/env.json"; exit 0; fi
      echo '{"message":"Not Found","status":"404"}' >&2; exit 1 ;;
esac
exit 0
STUB
  chmod +x "$d/bin/gh"
}

# run_cmd <dir> <script> [args...]
run_cmd() {
  local d="$1" script="$2"; shift 2
  ( cd "$d" && PATH="$d/bin:$PATH" GH_STUB_DIR="$d/stub" \
      bash "$script" --release-env-policy "$@" </dev/null 2>&1 )
}

ENV_NO_POLICY='{"name":"github-pages","deployment_branch_policy":null}'
ENV_CUSTOM='{"name":"github-pages","deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
ENV_PROTECTED='{"name":"github-pages","deployment_branch_policy":{"protected_branches":true,"custom_branch_policies":false}}'
POL_MAIN_ONLY='{"total_count":1,"branch_policies":[{"id":1,"name":"main","type":"branch"}]}'
POL_WITH_TAG='{"total_count":2,"branch_policies":[{"id":1,"name":"main","type":"branch"},{"id":2,"name":"v*","type":"tag"}]}'

echo "== tests/test-walk016-release-env-policy.sh =="

# ── T1: non-github host → NOT APPLICABLE, never a failure ───────────────────
echo "=== T1-non-github-not-applicable ==="
P="$TOPTMP/p1"; mk_proj "$P" gitlab NONE "$POL_MAIN_ONLY"
out=$(run_cmd "$P" "$SCRIPT"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "NOT APPLICABLE"; then
  pass "T1-non-github-not-applicable"
else
  fail_ "T1-non-github-not-applicable" "rc=$rc — a gitlab/bitbucket project must not be failed by a GitHub environments check: $out"
fi

# ── T2: environment not created yet → nothing can reject, exit 0 ────────────
echo "=== T2-env-absent-clean ==="
P="$TOPTMP/p2"; mk_proj "$P" github NONE "$POL_MAIN_ONLY"
out=$(run_cmd "$P" "$SCRIPT"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "does not exist yet"; then
  pass "T2-env-absent-clean (Pages not enabled — re-run after enabling)"
else
  fail_ "T2-env-absent-clean" "rc=$rc — a 404 environment is 'nothing to reject', not a failure: $out"
fi

# ── T3: no deployment branch policy at all → every ref may deploy ───────────
echo "=== T3-no-policy-clean ==="
P="$TOPTMP/p3"; mk_proj "$P" github "$ENV_NO_POLICY" "$POL_MAIN_ONLY"
out=$(run_cmd "$P" "$SCRIPT"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "no deployment branch policy"; then
  pass "T3-no-policy-clean"
else
  fail_ "T3-no-policy-clean" "rc=$rc: $out"
fi

# ── T4: custom policies, branch-only → BLOCKS + prints the exact remediation ─
echo "=== T4-tag-rejected-reported ==="
P="$TOPTMP/p4"; mk_proj "$P" github "$ENV_CUSTOM" "$POL_MAIN_ONLY"
out=$(run_cmd "$P" "$SCRIPT"); rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q "NO tag deployment policy" \
   && printf '%s' "$out" | grep -q "deployment-branch-policies -f name='v\*' -f type='tag'"; then
  pass "T4-tag-rejected-reported (names the empty-step-list failure + the one-line fix)"
else
  fail_ "T4-tag-rejected-reported" "rc=$rc — this is the walk's exact repo state and it must report, with the runnable command: $out"
fi
# and it must NOT have written anything without --fix
if grep -q -- '-X POST' "$P/stub/gh.log"; then
  fail_ "T4b-dry-run-is-read-only" "the dry run issued a write call: $(cat "$P/stub/gh.log")"
else
  pass "T4b-dry-run-is-read-only (no -X POST without --fix)"
fi

# ── T5: --fix applies the tag policy ────────────────────────────────────────
echo "=== T5-fix-applies-policy ==="
P="$TOPTMP/p5"; mk_proj "$P" github "$ENV_CUSTOM" "$POL_MAIN_ONLY"
out=$(run_cmd "$P" "$SCRIPT" --fix); rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q -- '-X POST' "$P/stub/gh.log" \
   && grep -q 'deployment-branch-policies' "$P/stub/gh.log" \
   && grep -q 'type=tag' "$P/stub/gh.log"; then
  pass "T5-fix-applies-policy (POST .../deployment-branch-policies type=tag)"
else
  fail_ "T5-fix-applies-policy" "rc=$rc log=[$(cat "$P/stub/gh.log")] out=$out"
fi

# ── T6: a v* tag policy already present → clean ────────────────────────────
echo "=== T6-tag-policy-present-clean ==="
P="$TOPTMP/p6"; mk_proj "$P" github "$ENV_CUSTOM" "$POL_WITH_TAG"
out=$(run_cmd "$P" "$SCRIPT"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "admits tag deployments"; then
  pass "T6-tag-policy-present-clean (the walker's fixed state reads clean)"
else
  fail_ "T6-tag-policy-present-clean" "rc=$rc — an already-fixed repo must not be re-reported: $out"
fi

# ── T7: protected-branches-only → BLOCKS + names the switch to custom ───────
echo "=== T7-protected-branches-only ==="
P="$TOPTMP/p7"; mk_proj "$P" github "$ENV_PROTECTED" "$POL_MAIN_ONLY"
out=$(run_cmd "$P" "$SCRIPT"); rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q "PROTECTED BRANCHES only" \
   && printf '%s' "$out" | grep -q "custom_branch_policies"; then
  pass "T7-protected-branches-only (a tag can never deploy until the env is switched)"
else
  fail_ "T7-protected-branches-only" "rc=$rc: $out"
fi

# ── T8: --tag-pattern is honored end to end ────────────────────────────────
echo "=== T8-tag-pattern-override ==="
P="$TOPTMP/p8"; mk_proj "$P" github "$ENV_CUSTOM" "$POL_WITH_TAG"
out=$(run_cmd "$P" "$SCRIPT" --tag-pattern 'release-*'); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "name='release-\*'"; then
  pass "T8-tag-pattern-override (a v* policy does not satisfy a release-* project)"
else
  fail_ "T8-tag-pattern-override" "rc=$rc — the pattern must flow into both the match and the remediation: $out"
fi

# ── M1: mutant — blind the tag-policy detection ────────────────────────────
# If the `.type=="tag"` select never matches, T6 (an already-correct repo) is
# re-reported as broken. Asserted POSITIVELY on a lib-complete copy.
echo "=== M1-mutant-blind-tag-detection ==="
MUT="$TOPTMP/mut/scripts"
mkdir -p "$MUT/lib"
sed 's/select(\.type=="tag" and/select(false and/' "$SCRIPT" > "$MUT/check-gate.sh"
chmod +x "$MUT/check-gate.sh"
cp "$REPO_ROOT/scripts/lib/"*.sh "$MUT/lib/"
if grep -q 'select(false and' "$MUT/check-gate.sh"; then
  P="$TOPTMP/pm1"; mk_proj "$P" github "$ENV_CUSTOM" "$POL_WITH_TAG"
  out=$(run_cmd "$P" "$MUT/check-gate.sh"); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "NO tag deployment policy"; then
    pass "M1-mutant-blind-tag-detection (blinded, the mutant re-reports an already-fixed repo — the select carries T6)"
  else
    fail_ "M1-mutant-blind-tag-detection" "rc=$rc — the mutant behaved like the real thing; T6 proves nothing: $out"
  fi
else
  fail_ "M1-mutant-blind-tag-detection" "sed did not rewrite the select — mutant is vacuous"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

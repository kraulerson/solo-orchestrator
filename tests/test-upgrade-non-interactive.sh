#!/usr/bin/env bash
# tests/test-upgrade-non-interactive.sh — BL-018 regression test.
#
# scripts/upgrade-project.sh non-interactive mode adds:
#   - explicit --non-interactive flag (overrides [-t 0] auto-detection)
#   - --validate-only mode (parse + validate flags, print resolved JSON, exit 0)
#   - tightened flag validation:
#       * --track value must be light/standard/full
#       * --deployment value must be personal/organizational
#       * --to-production / --to-sponsored-poc / --to-private-poc are mutex
#       * unified BL-016-style error format with expected/observed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_personal_project() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git remote add origin https://example.com/fake.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"other"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"light","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"light","deployment":"personal"}
JSON
  )
}
teardown_project() { rm -rf "$TMPDIR_T"; }

# --- --validate-only tests (no side effects on project state) ---

t1_validate_only_to_production_exits_zero() {
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --validate-only --to-production </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "expected exit 0; rc=$rc; tail:\n$(echo "$out" | tail -3)"
    teardown_project; return
  fi
  if [[ "$out" != *'"_validated": true'* ]]; then
    fail_ "T1" "stdout missing _validated:true; got tail:\n$(echo "$out" | tail -10)"
    teardown_project; return
  fi
  if [[ "$out" != *'"to_production": true'* ]]; then
    fail_ "T1" "stdout missing to_production:true; got tail:\n$(echo "$out" | tail -10)"
    teardown_project; return
  fi
  # No state mutation: phase-state should still show poc_mode=null (unchanged).
  local poc; poc=$(jq -r '.poc_mode // "null"' "$TMPDIR_T/.claude/phase-state.json")
  if [ "$poc" != "null" ]; then
    fail_ "T1" "validate-only mutated state — poc_mode=$poc"
    teardown_project; return
  fi
  pass "T1: --validate-only --to-production prints resolved JSON, no state mutation"
  teardown_project
}

t2_validate_only_invalid_track() {
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --validate-only --track foo </dev/null 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T2" "expected non-zero exit for invalid --track; got rc=0"
    teardown_project; return
  fi
  if [[ "$out" != *"--track"* ]] || [[ "$out" != *"foo"* ]]; then
    fail_ "T2" "expected error mentioning --track and 'foo'; got tail:\n$(echo "$out" | tail -5)"
    teardown_project; return
  fi
  pass "T2: --validate-only --track foo → exit 1 with --track + value in error"
  teardown_project
}

t3_validate_only_invalid_deployment() {
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --validate-only --deployment cloudy </dev/null 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T3" "expected non-zero exit for invalid --deployment; got rc=0"
    teardown_project; return
  fi
  if [[ "$out" != *"--deployment"* ]] || [[ "$out" != *"cloudy"* ]]; then
    fail_ "T3" "expected error mentioning --deployment and 'cloudy'; got tail:\n$(echo "$out" | tail -5)"
    teardown_project; return
  fi
  pass "T3: --validate-only --deployment cloudy → exit 1 with --deployment + value"
  teardown_project
}

t4_mutex_two_to_flags() {
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --validate-only --to-production --to-private-poc </dev/null 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T4" "expected non-zero exit for mutex --to-* flags; got rc=0"
    teardown_project; return
  fi
  if [[ "$out" != *"mutually exclusive"* ]] && [[ "$out" != *"only one"* ]] && [[ "$out" != *"cannot combine"* ]]; then
    fail_ "T4" "expected mutex error message; got tail:\n$(echo "$out" | tail -5)"
    teardown_project; return
  fi
  pass "T4: --to-production + --to-private-poc → exit 1 with mutex error"
  teardown_project
}

t5_non_interactive_flag_accepted() {
  # The --non-interactive flag should be accepted as a no-op semantic marker.
  # With a real upgrade target, the flag should not fail validation.
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --validate-only --non-interactive --to-private-poc </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T5" "expected exit 0 with --non-interactive flag; got rc=$rc tail:\n$(echo "$out" | tail -3)"
    teardown_project; return
  fi
  pass "T5: --non-interactive accepted alongside upgrade target"
  teardown_project
}

t6_no_target_flag_is_error() {
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --validate-only </dev/null 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T6" "expected exit 1 when no upgrade target specified; got rc=0"
    teardown_project; return
  fi
  pass "T6: --validate-only with no target flag → exit 1 (must specify --track/--deployment/--to-*)"
  teardown_project
}

t7_real_upgrade_still_works() {
  # Regression: ensure the existing non-validate path still runs end-to-end.
  # Per audit code-upgrade-project-1 + tier-crosscheck-3 (2026-06) the
  # --to-private-poc path resolves to the personal deployment tier — Private
  # POC is always personal per baseline §2.5. (Pre-audit behavior coerced it
  # to organizational; the audit fix corrected that. T7 used to assert the
  # old, incorrect shape — updated here.)
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-private-poc </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T7" "regression: --to-private-poc real upgrade failed; rc=$rc tail:\n$(echo "$out" | tail -5)"
    teardown_project; return
  fi
  local deploy poc; deploy=$(jq -r '.deployment' "$TMPDIR_T/.claude/phase-state.json"); poc=$(jq -r '.poc_mode' "$TMPDIR_T/.claude/phase-state.json")
  if [ "$deploy" != "personal" ] || [ "$poc" != "private_poc" ]; then
    fail_ "T7" "regression: post-upgrade state wrong (deploy=$deploy poc=$poc; expected personal/private_poc per audit-1)"
    teardown_project; return
  fi
  pass "T7: real --to-private-poc upgrade still works (regression check; personal/private_poc per audit-1)"
  teardown_project
}

echo "== tests/test-upgrade-non-interactive.sh =="
t1_validate_only_to_production_exits_zero
t2_validate_only_invalid_track
t3_validate_only_invalid_deployment
t4_mutex_two_to_flags
t5_non_interactive_flag_accepted
t6_no_target_flag_is_error
t7_real_upgrade_still_works

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

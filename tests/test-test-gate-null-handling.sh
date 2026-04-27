#!/usr/bin/env bash
# tests/test-test-gate-null-handling.sh — U-K regression test.
#
# scripts/test-gate.sh integer comparisons at lines 88/122/210 errored with
# "integer expression expected" when jq returned null/empty for numeric
# fields (build-progress.json missing keys or partially populated).
# Fix: jq -r '... // 0' (or '// 2' for test_interval) default for every
# numeric read site, so partial state files no longer crash the gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/test-gate.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_with_state() {
  local state_json="$1"
  TMPDIR_T=$(mktemp -d)
  mkdir -p "$TMPDIR_T/.claude"
  printf '%s' "$state_json" > "$TMPDIR_T/.claude/build-progress.json"
}
teardown_project() { rm -rf "$TMPDIR_T"; }

t1_empty_json_check_batch_no_crash() {
  setup_with_state '{}'
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --check-batch 2>&1) || rc=$?
  if echo "$out" | grep -q "integer expression expected\|unbound variable"; then
    fail_ "T1" "shell crash on empty JSON; out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "expected exit 0 (0 features < default interval); rc=$rc out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  pass "T1: --check-batch on empty JSON exits 0 with no shell errors"
  teardown_project
}

t2_missing_test_interval_uses_default() {
  setup_with_state '{"features_since_last_test": 5, "features_completed": []}'
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --check-batch 2>&1) || rc=$?
  if echo "$out" | grep -q "integer expression expected"; then
    fail_ "T2" "shell crash; out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  # 5 features >= default interval 2 → testing required → exit 1
  if [ "$rc" -eq 0 ]; then
    fail_ "T2" "expected non-zero (5 >= default 2); rc=$rc out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  if ! echo "$out" | grep -q "Testing session required"; then
    fail_ "T2" "expected 'Testing session required'; out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  pass "T2: missing test_interval defaults to 2 (5 >= 2 → required)"
  teardown_project
}

t3_missing_features_since_last_test_uses_default() {
  setup_with_state '{"test_interval": 3, "features_completed": []}'
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --check-batch 2>&1) || rc=$?
  if echo "$out" | grep -q "integer expression expected"; then
    fail_ "T3" "shell crash; out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  if [ "$rc" -ne 0 ]; then
    fail_ "T3" "expected exit 0 (0 < 3); rc=$rc out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  pass "T3: missing features_since_last_test defaults to 0 (0 < 3 → clear)"
  teardown_project
}

t4_record_feature_no_crash_on_partial_state() {
  setup_with_state '{"features_completed": []}'
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --record-feature "feat-1" 2>&1) || rc=$?
  if echo "$out" | grep -q "integer expression expected\|unbound variable"; then
    fail_ "T4" "shell crash on --record-feature; out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  pass "T4: --record-feature on partial state runs without shell errors"
  teardown_project
}

t5_populated_state_still_works() {
  # Regression: ensure normal happy-path state still works.
  setup_with_state '{"features_completed": [], "features_since_last_test": 0, "test_interval": 2, "testing_required": false, "tester_count": 1, "bug_tracker": "github_issues", "sessions_completed": 0, "last_test_session": null}'
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --check-batch 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T5" "regression: populated state should pass; rc=$rc out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  if ! echo "$out" | grep -q "Clear to continue"; then
    fail_ "T5" "expected 'Clear to continue'; out:\n$(echo "$out" | head -3)"
    teardown_project; return
  fi
  pass "T5: populated state — 'Clear to continue' (regression)"
  teardown_project
}

echo "== tests/test-test-gate-null-handling.sh =="
t1_empty_json_check_batch_no_crash
t2_missing_test_interval_uses_default
t3_missing_features_since_last_test_uses_default
t4_record_feature_no_crash_on_partial_state
t5_populated_state_still_works

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

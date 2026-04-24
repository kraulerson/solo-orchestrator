#!/usr/bin/env bash
# tests/test-check-commit-message.sh — unit tests for
# `scripts/process-checklist.sh --check-commit-message "MSG"` (BL-006).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# --- Helpers: seed a tempdir .claude/ state ---

seed_phase() {
  # $1 = phase number
  mkdir -p "$TMPDIR_T/.claude"
  cat > "$TMPDIR_T/.claude/phase-state.json" <<JSON
{"current_phase": $1, "project": "unit-test"}
JSON
}

seed_process_state() {
  # $1 = feature value (e.g., null or "myfeat")
  # $2 = space-separated list of completed steps (may be empty)
  local feature="$1"
  local completed="$2"
  local completed_json="[]"
  if [ -n "$completed" ]; then
    completed_json=$(printf '%s\n' $completed | jq -R . | jq -sc .)
  fi
  local feature_json
  if [ "$feature" = "null" ]; then
    feature_json="null"
  else
    feature_json="\"$feature\""
  fi
  cat > "$TMPDIR_T/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {
    "feature": $feature_json,
    "step": 0,
    "steps_completed": $completed_json,
    "started_at": null
  },
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
}

run_check() {
  # $1 = MSG to pass. Echoes "EXIT|STDERR" (one line joined).
  local msg="$1"
  local rc=0
  local err
  err=$( cd "$TMPDIR_T" && "$SCRIPT" --check-commit-message "$msg" 2>&1 >/dev/null ) || rc=$?
  err=$(printf '%s' "$err" | tr '\n' ' ')
  echo "$rc|$err"
}

setup() {
  TMPDIR_T=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_T"
}

# --- Tests ---

u1_phase_0_feat() {
  setup; seed_phase 0; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U1" "expected exit 0 in phase 0, got: $out"; teardown; return; }
  pass "U1: Phase 0 — feat: exits 0 (phase gate)"
  teardown
}

u2_phase_1_feat() {
  setup; seed_phase 1; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U2" "expected exit 0 in phase 1, got: $out"; teardown; return; }
  pass "U2: Phase 1 — feat: exits 0 (phase gate)"
  teardown
}

u3_phase_2_no_feature_feat() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U3" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"start-feature"* ]] || { fail_ "U3" "stderr missing --start-feature guidance: $out"; teardown; return; }
  pass "U3: Phase 2, no feature — feat: exit 1 + start-feature remediation"
  teardown
}

u4_non_feat_fix() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "fix(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U4" "expected exit 0 for fix:, got: $out"; teardown; return; }
  pass "U4: fix: — exit 0 (non-feat)"
  teardown
}

u5_non_feat_chore() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "chore: bump")
  [ "${out%%|*}" = "0" ] || { fail_ "U5" "expected exit 0 for chore:, got: $out"; teardown; return; }
  pass "U5: chore: — exit 0"
  teardown
}

u6_non_feat_docs() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "docs: typo")
  [ "${out%%|*}" = "0" ] || { fail_ "U6" "expected exit 0 for docs:, got: $out"; teardown; return; }
  pass "U6: docs: — exit 0"
  teardown
}

u7_feat_no_scope() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat: foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U7" "expected exit 1 for 'feat: ', got: $out"; teardown; return; }
  pass "U7: feat: (no scope) — exit 1"
  teardown
}

u8_feat_bang_no_scope() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat!: breaking")
  [ "${out%%|*}" = "1" ] || { fail_ "U8" "expected exit 1 for 'feat!:', got: $out"; teardown; return; }
  pass "U8: feat!: — exit 1"
  teardown
}

u9_feat_scope_bang() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat(x)!: breaking")
  [ "${out%%|*}" = "1" ] || { fail_ "U9" "expected exit 1 for 'feat(x)!:', got: $out"; teardown; return; }
  pass "U9: feat(x)!: — exit 1"
  teardown
}

u10_feature_word() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feature: foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U10" "expected exit 0 for 'feature:', got: $out"; teardown; return; }
  pass "U10: feature: (wrong word) — exit 0"
  teardown
}

u11_featbar_prefix() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "featbar: foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U11" "expected exit 0 for 'featbar:', got: $out"; teardown; return; }
  pass "U11: featbar: (not feat) — exit 0"
  teardown
}

u12_feature_started_zero_steps() {
  setup; seed_phase 2; seed_process_state "myfeat" ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U12" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"tests_written"* ]] || { fail_ "U12" "stderr missing 'tests_written' step name: $out"; teardown; return; }
  pass "U12: feature started, 0 steps — exit 1 + names tests_written"
  teardown
}

u13_feature_started_partial() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit"
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U13" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"documentation_updated"* ]] || { fail_ "U13" "stderr missing 'documentation_updated' step name: $out"; teardown; return; }
  pass "U13: steps 0-3 done — exit 1 + names step 4 (documentation_updated)"
  teardown
}

u14_feature_started_all_done() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit documentation_updated"
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U14" "expected exit 0, got: $out"; teardown; return; }
  pass "U14: feat with all 5 steps complete — exit 0"
  teardown
}

u15_non_feat_all_done() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit documentation_updated"
  local out; out=$(run_check "fix(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U15" "expected exit 0 for fix with all steps done, got: $out"; teardown; return; }
  pass "U15: fix: with all steps done — exit 0"
  teardown
}

u16_empty_msg() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "")
  [ "${out%%|*}" = "0" ] || { fail_ "U16" "expected exit 0 for empty MSG, got: $out"; teardown; return; }
  pass "U16: empty message — exit 0"
  teardown
}

u17_revert_quotes_feat() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check 'Revert "feat(x): foo"')
  [ "${out%%|*}" = "0" ] || { fail_ "U17" "expected exit 0 for Revert-prefix, got: $out"; teardown; return; }
  pass "U17: Revert \"feat(x): ...\" — exit 0 (regex anchored to start)"
  teardown
}

# --- Run all ---
echo "== tests/test-check-commit-message.sh =="
u1_phase_0_feat
u2_phase_1_feat
u3_phase_2_no_feature_feat
u4_non_feat_fix
u5_non_feat_chore
u6_non_feat_docs
u7_feat_no_scope
u8_feat_bang_no_scope
u9_feat_scope_bang
u10_feature_word
u11_featbar_prefix
u12_feature_started_zero_steps
u13_feature_started_partial
u14_feature_started_all_done
u15_non_feat_all_done
u16_empty_msg
u17_revert_quotes_feat

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

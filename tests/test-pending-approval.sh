#!/usr/bin/env bash
# tests/test-pending-approval.sh — unit tests for scripts/pending-approval.sh (BL-015).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/pending-approval.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# --- Helpers: per-test tempdir with .claude/ ---

setup_project() {
  TMPDIR_T=$(mktemp -d)
  mkdir -p "$TMPDIR_T/.claude"
}

teardown_project() {
  rm -rf "$TMPDIR_T"
}

run_in_project() {
  # Run the helper from the tempdir. Echoes "EXIT|STDOUT_AND_STDERR" (joined as one line).
  # Both streams are merged because bash quoting interactions with stdout/stderr split + colors get hairy.
  local out rc=0
  out=$( cd "$TMPDIR_T" && "$SCRIPT" "$@" 2>&1 ) || rc=$?
  out=$(printf '%s' "$out" | tr '\n' ' ')
  echo "$rc|$out"
}

write_sentinel_raw() {
  # $1 = JSON content
  printf '%s' "$1" > "$TMPDIR_T/.claude/pending-approval.json"
}

# --- Tests ---

p1_offer_fresh_project() {
  setup_project
  local out; out=$(run_in_project --offer "commit structure" --options "A1: single" "A2: two" "A3: three" --recommendation "A1")
  local rc=${out%%|*}
  [ "$rc" = "0" ] || { fail_ "P1" "expected exit 0, got: $out"; teardown_project; return; }
  [ -f "$TMPDIR_T/.claude/pending-approval.json" ] || { fail_ "P1" "sentinel not created"; teardown_project; return; }
  local q opts rec at
  q=$(jq -r '.question' "$TMPDIR_T/.claude/pending-approval.json")
  opts=$(jq -r '.options | length' "$TMPDIR_T/.claude/pending-approval.json")
  rec=$(jq -r '.recommendation' "$TMPDIR_T/.claude/pending-approval.json")
  at=$(jq -r '.offered_at' "$TMPDIR_T/.claude/pending-approval.json")
  [ "$q" = "commit structure" ] && [ "$opts" = "3" ] && [ "$rec" = "A1" ] && [ -n "$at" ] || { fail_ "P1" "schema mismatch: q='$q' opts=$opts rec='$rec' at='$at'"; teardown_project; return; }
  ls "$TMPDIR_T/.claude/"*.tmp 2>/dev/null && { fail_ "P1" "tempfile not cleaned up"; teardown_project; return; }
  pass "P1: --offer in fresh project — sentinel created with valid schema, atomic"
  teardown_project
}

p2_double_offer_refused() {
  setup_project
  run_in_project --offer "first" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --offer "second" --options "B1: x" "B2: y" --recommendation "B1")
  local rc=${out%%|*}
  [ "$rc" = "1" ] || { fail_ "P2" "expected exit 1, got: $out"; teardown_project; return; }
  [[ "$out" == *"first"* ]] || { fail_ "P2" "stderr should mention existing question 'first', got: $out"; teardown_project; return; }
  local q; q=$(jq -r '.question' "$TMPDIR_T/.claude/pending-approval.json")
  [ "$q" = "first" ] || { fail_ "P2" "sentinel was overwritten: q='$q'"; teardown_project; return; }
  pass "P2: double --offer refused, original sentinel preserved"
  teardown_project
}

p3_offer_empty_question() {
  setup_project
  local out; out=$(run_in_project --offer "" --options "A1: foo" "A2: bar" --recommendation "A1")
  [ "${out%%|*}" = "1" ] || { fail_ "P3" "expected exit 1 for empty question, got: $out"; teardown_project; return; }
  pass "P3: --offer with empty --question — exit 1"
  teardown_project
}

p4_offer_single_option() {
  setup_project
  local out; out=$(run_in_project --offer "Q" --options "A1: only" --recommendation "A1")
  [ "${out%%|*}" = "1" ] || { fail_ "P4" "expected exit 1 for single option, got: $out"; teardown_project; return; }
  [[ "$out" == *"2 options"* ]] || { fail_ "P4" "stderr should mention 'minimum 2 options', got: $out"; teardown_project; return; }
  pass "P4: --offer with single option — exit 1 + 'minimum 2 options' message"
  teardown_project
}

p5_offer_recommendation_mismatch() {
  setup_project
  local out; out=$(run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "Z9")
  [ "${out%%|*}" = "1" ] || { fail_ "P5" "expected exit 1 for unknown recommendation, got: $out"; teardown_project; return; }
  pass "P5: --offer with --recommendation not matching any option — exit 1"
  teardown_project
}

p6_offer_outside_project() {
  TMPDIR_T=$(mktemp -d)  # no .claude/
  local out rc=0
  out=$( cd "$TMPDIR_T" && "$SCRIPT" --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || { fail_ "P6" "expected exit 1 outside project, got rc=$rc out=$out"; teardown_project; return; }
  [[ "$out" == *"Solo project"* || "$out" == *"no .claude"* || "$out" == *"no_claude"* ]] || { fail_ "P6" "stderr should mention 'not in a Solo project', got: $out"; teardown_project; return; }
  pass "P6: --offer outside a project — exit 1 + 'not in a Solo project' message"
  teardown_project
}

p7_resolve_present() {
  setup_project
  run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --resolve)
  [ "${out%%|*}" = "0" ] || { fail_ "P7" "expected exit 0, got: $out"; teardown_project; return; }
  [ ! -f "$TMPDIR_T/.claude/pending-approval.json" ] || { fail_ "P7" "sentinel not deleted"; teardown_project; return; }
  [[ "$out" == *"resolved"* ]] || { fail_ "P7" "stdout should mention 'resolved', got: $out"; teardown_project; return; }
  pass "P7: --resolve when sentinel present — exit 0, deleted, OK message"
  teardown_project
}

p8_resolve_absent_idempotent() {
  setup_project
  local out; out=$(run_in_project --resolve)
  [ "${out%%|*}" = "0" ] || { fail_ "P8" "expected exit 0, got: $out"; teardown_project; return; }
  [[ "$out" == *"No pending approval"* ]] || { fail_ "P8" "stdout should mention 'No pending approval', got: $out"; teardown_project; return; }
  pass "P8: --resolve when sentinel absent — exit 0, idempotent"
  teardown_project
}

p9_clear_present() {
  setup_project
  run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --clear)
  [ "${out%%|*}" = "0" ] || { fail_ "P9" "expected exit 0, got: $out"; teardown_project; return; }
  [ ! -f "$TMPDIR_T/.claude/pending-approval.json" ] || { fail_ "P9" "sentinel not deleted by --clear"; teardown_project; return; }
  [[ "$out" == *"cleared"* ]] || { fail_ "P9" "stdout should mention 'cleared (abort)', got: $out"; teardown_project; return; }
  pass "P9: --clear when sentinel present — exit 0, deleted, abort message"
  teardown_project
}

p10_status_present_valid() {
  setup_project
  run_in_project --offer "commit structure" --options "A1: single" "A2: two" "A3: three" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --status)
  [ "${out%%|*}" = "0" ] || { fail_ "P10" "expected exit 0, got: $out"; teardown_project; return; }
  [[ "$out" == *"commit structure"* ]] || { fail_ "P10" "stdout should reflect question, got: $out"; teardown_project; return; }
  [[ "$out" == *"A1: single"* ]] || { fail_ "P10" "stdout should reflect options, got: $out"; teardown_project; return; }
  [[ "$out" == *"A1"* ]] || { fail_ "P10" "stdout should reflect recommendation, got: $out"; teardown_project; return; }
  pass "P10: --status with valid sentinel — exit 0 + formatted summary"
  teardown_project
}

p11_status_absent() {
  setup_project
  local out; out=$(run_in_project --status)
  [ "${out%%|*}" = "0" ] || { fail_ "P11" "expected exit 0, got: $out"; teardown_project; return; }
  [[ "$out" == *"No pending approval"* ]] || { fail_ "P11" "stdout should mention 'No pending approval', got: $out"; teardown_project; return; }
  pass "P11: --status when sentinel absent — exit 0, no-pending message"
  teardown_project
}

p12_status_malformed() {
  setup_project
  write_sentinel_raw '{"question": "incomplete"'
  local out; out=$(run_in_project --status)
  [ "${out%%|*}" = "0" ] || { fail_ "P12" "expected exit 0 even on malformed, got: $out"; teardown_project; return; }
  [[ "$out" == *"alformed"* ]] || { fail_ "P12" "stdout should mention 'alformed', got: $out"; teardown_project; return; }
  pass "P12: --status with malformed sentinel — exit 0 + 'malformed' message"
  teardown_project
}

p13_validate_absent() {
  setup_project
  local out; out=$(run_in_project --validate)
  [ "${out%%|*}" = "0" ] || { fail_ "P13" "expected exit 0 for absent file, got: $out"; teardown_project; return; }
  [[ "$out" == *"No sentinel to validate"* ]] || { fail_ "P13" "stdout should mention 'No sentinel to validate', got: $out"; teardown_project; return; }
  pass "P13: --validate on absent file — exit 0"
  teardown_project
}

p14_validate_valid() {
  setup_project
  run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --validate)
  [ "${out%%|*}" = "0" ] || { fail_ "P14" "expected exit 0 for valid sentinel, got: $out"; teardown_project; return; }
  [[ "$out" == *"Valid sentinel"* ]] || { fail_ "P14" "stdout should mention 'Valid sentinel', got: $out"; teardown_project; return; }
  pass "P14: --validate on valid sentinel — exit 0"
  teardown_project
}

p15_validate_malformed() {
  setup_project
  write_sentinel_raw '{"question": "incomplete"'
  local out; out=$(run_in_project --validate)
  [ "${out%%|*}" = "1" ] || { fail_ "P15" "expected exit 1 for malformed sentinel, got: $out"; teardown_project; return; }
  pass "P15: --validate on malformed sentinel — exit 1"
  teardown_project
}

p16_help() {
  setup_project
  local out; out=$(run_in_project --help)
  [ "${out%%|*}" = "0" ] || { fail_ "P16" "expected exit 0 for --help, got: $out"; teardown_project; return; }
  [[ "$out" == *"--offer"* ]] && [[ "$out" == *"--resolve"* ]] && [[ "$out" == *"--status"* ]] || { fail_ "P16" "help should list subcommands, got: $out"; teardown_project; return; }
  pass "P16: --help — exit 0 + subcommand listing"
  teardown_project
}

p17_atomic_write_code_shape() {
  # Atomic write means: write to a tempfile (mktemp) and then mv it to the
  # final sentinel path. The mv may reference variables ($tmpfile, $sentinel)
  # rather than literals, so accept both shapes.
  local has_mktemp has_mv has_direct_write
  has_mktemp=$(grep -cE 'mktemp.*pending-approval\.[A-Z0-9]+\.tmp' "$SCRIPT" || true)
  has_mv=$(grep -cE '^[[:space:]]*mv[[:space:]]+["$]' "$SCRIPT" || true)
  # Direct write: any non-comment line that does `> $sentinel` or `> ".../.claude/pending-approval.json"`.
  has_direct_write=$(grep -cE '^[[:space:]]*[^#]*>[[:space:]]+("?\$?\{?[A-Za-z_]*\}?/?\.claude/pending-approval\.json"?|"\$sentinel")' "$SCRIPT" || true)

  if [ "$has_mktemp" -ge 1 ] && [ "$has_mv" -ge 1 ] && [ "$has_direct_write" = "0" ]; then
    pass "P17: helper uses atomic write (mktemp + mv); no direct '> sentinel' patterns"
  else
    fail_ "P17" "atomic-write check failed: mktemp=$has_mktemp mv=$has_mv direct_write=$has_direct_write"
  fi
}

# --- Run all ---
echo "== tests/test-pending-approval.sh =="
p1_offer_fresh_project
p2_double_offer_refused
p3_offer_empty_question
p4_offer_single_option
p5_offer_recommendation_mismatch
p6_offer_outside_project
p7_resolve_present
p8_resolve_absent_idempotent
p9_clear_present
p10_status_present_valid
p11_status_absent
p12_status_malformed
p13_validate_absent
p14_validate_valid
p15_validate_malformed
p16_help
p17_atomic_write_code_shape

# ---- BL-029.1 S4 (2026-05-04): --resolve --decision closes audit rows ----

p18_resolve_decision_accept_closes_audit_rows() {
  echo "[TEST] --resolve --decision accept updates PENDING bypass rows to accepted/bypassed"
  setup_project
  # Seed an audit log with a PENDING row + a sentinel.
  echo '[{"timestamp":"x","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{"pattern":"no_verify"},"user_response":"PENDING","final_outcome":"recorded_only"}]' > "$TMPDIR_T/.claude/bypass-audit.json"
  echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A2","offered_at":"x"}' > "$TMPDIR_T/.claude/pending-approval.json"

  run_in_project --resolve --decision accept >/dev/null

  user_resp=$(jq -r '.[0].user_response' "$TMPDIR_T/.claude/bypass-audit.json")
  final_out=$(jq -r '.[0].final_outcome' "$TMPDIR_T/.claude/bypass-audit.json")
  if [ "$user_resp" = "accepted" ] && [ "$final_out" = "bypassed" ]; then
    pass "p18 accept closes row"
  else
    fail_ "p18 accept closes row" "user_response=$user_resp final_outcome=$final_out"
  fi
  teardown_project
}
p18_resolve_decision_accept_closes_audit_rows

p19_resolve_decision_decline_closes_audit_rows() {
  echo "[TEST] --resolve --decision decline updates PENDING bypass rows to declined/abandoned"
  setup_project
  echo '[{"timestamp":"x","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{"pattern":"fake_loop"},"user_response":"PENDING","final_outcome":"recorded_only"}]' > "$TMPDIR_T/.claude/bypass-audit.json"
  echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A2","offered_at":"x"}' > "$TMPDIR_T/.claude/pending-approval.json"

  run_in_project --resolve --decision decline >/dev/null

  user_resp=$(jq -r '.[0].user_response' "$TMPDIR_T/.claude/bypass-audit.json")
  final_out=$(jq -r '.[0].final_outcome' "$TMPDIR_T/.claude/bypass-audit.json")
  if [ "$user_resp" = "declined" ] && [ "$final_out" = "abandoned" ]; then
    pass "p19 decline closes row"
  else
    fail_ "p19 decline closes row" "user_response=$user_resp final_outcome=$final_out"
  fi
  teardown_project
}
p19_resolve_decision_decline_closes_audit_rows

p20_resolve_without_decision_leaves_audit_alone() {
  echo "[TEST] --resolve (no --decision) deletes sentinel but does NOT modify audit rows"
  setup_project
  echo '[{"timestamp":"x","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{},"user_response":"PENDING","final_outcome":"recorded_only"}]' > "$TMPDIR_T/.claude/bypass-audit.json"
  echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A2","offered_at":"x"}' > "$TMPDIR_T/.claude/pending-approval.json"

  run_in_project --resolve >/dev/null

  user_resp=$(jq -r '.[0].user_response' "$TMPDIR_T/.claude/bypass-audit.json")
  if [ "$user_resp" = "PENDING" ] && [ ! -f "$TMPDIR_T/.claude/pending-approval.json" ]; then
    pass "p20 backward compat (no --decision)"
  else
    fail_ "p20 backward compat" "user_response=$user_resp sentinel_still_present=$([ -f "$TMPDIR_T/.claude/pending-approval.json" ] && echo yes || echo no)"
  fi
  teardown_project
}
p20_resolve_without_decision_leaves_audit_alone

p21_resolve_decision_unknown_fails() {
  echo "[TEST] --resolve --decision <unknown> fails"
  setup_project
  echo '[]' > "$TMPDIR_T/.claude/bypass-audit.json"
  echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A2","offered_at":"x"}' > "$TMPDIR_T/.claude/pending-approval.json"

  out=$(run_in_project --resolve --decision maybe 2>&1 || true)
  case "$out" in
    *FAIL*|*"unknown decision"*) pass "p21 unknown decision fails" ;;
    *) fail_ "p21 unknown decision fails" "got '$out'" ;;
  esac
  teardown_project
}
p21_resolve_decision_unknown_fails

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

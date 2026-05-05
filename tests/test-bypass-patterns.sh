#!/usr/bin/env bash
# tests/test-bypass-patterns.sh — BL-029 pattern table tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-patterns.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if [ ! -f "$LIB" ]; then
  fail_ "missing-lib" "RED expected"
else
  # shellcheck disable=SC1090
  source "$LIB"

  # T1: --no-verify is detected.
  if scan_bypass_patterns "you can run git commit --no-verify" >/dev/null; then pass "T1: --no-verify"; else fail_ "T1" "no match"; fi

  # T2: SOIF_FORCE_STEP= is detected.
  if scan_bypass_patterns "set SOIF_FORCE_STEP=build_loop:tests_written" >/dev/null; then pass "T2: SOIF_FORCE_STEP="; else fail_ "T2" "no match"; fi

  # T3: 'run this in your terminal' phrase is detected.
  if scan_bypass_patterns "alternatively, run this in your own terminal" >/dev/null; then pass "T3: terminal phrase"; else fail_ "T3" "no match"; fi

  # T4: synthetic Build Loop step proposal without prior tests_verified_failing is detected.
  if scan_bypass_patterns "I'll mark step build_loop:tests_verified_failing complete and move on" >/dev/null; then pass "T4: fake-loop"; else fail_ "T4" "no match"; fi

  # T5: git push --force-with-lease is detected.
  if scan_bypass_patterns "we can git push --force-with-lease to fix it" >/dev/null; then pass "T5: force-push"; else fail_ "T5" "no match"; fi

  # T6: ordinary text does NOT trigger.
  if scan_bypass_patterns "let's commit and push to origin" >/dev/null; then fail_ "T6" "false positive"; else pass "T6: clean text"; fi

  # T7: scan_bypass_patterns echoes the matched pattern name on hit.
  out=$(scan_bypass_patterns "I'll use --no-verify here")
  if [ "$out" = "no_verify" ]; then pass "T7: pattern name"; else fail_ "T7" "got '$out'"; fi

  # T8 (per BL-029 plan amendment): pattern_regex_for returns the regex for a known name.
  # The 2026-04-29 calibration relaxation expanded no_verify; check substring rather than literal equality.
  rgx=$(pattern_regex_for "no_verify")
  if echo "$rgx" | grep -q -- '--no-verify'; then pass "T8: regex lookup includes --no-verify"; else fail_ "T8" "got '$rgx'"; fi

  # T9: pattern_regex_for returns non-zero for unknown name.
  if pattern_regex_for "totally-not-a-pattern" >/dev/null 2>&1; then fail_ "T9" "expected non-zero"; else pass "T9: unknown returns nonzero"; fi

  # ---- Calibration-found phrasings (S2 fixes) ----

  # T10: terminal_workaround matches "run that command in your terminal" (no literal "this").
  if scan_bypass_patterns "you can run that command in your terminal directly" >/dev/null; then pass "T10: terminal_workaround relaxed"; else fail_ "T10" "regex still requires 'this'"; fi

  # T11: terminal_workaround matches "run it in your shell".
  if scan_bypass_patterns "alternatively, run it in your shell" >/dev/null; then pass "T11: terminal_workaround matches 'shell'"; else fail_ "T11" "no match"; fi

  # T12: fake_loop matches the canonical agent-3 phrasing — verbatim from the calibration replay.
  # Strips the "we can" prefix that would let manual_step_complete match first; isolates fake_loop coverage.
  out=$(scan_bypass_patterns "mark tests_written, tests_verified_failing, etc. as complete via process-checklist.sh --complete-step")
  if [ "$out" = "fake_loop" ]; then pass "T12: fake_loop list-form"; else fail_ "T12" "expected fake_loop, got '$out'"; fi

  # T13: manual_step_complete broadens to "we could just mark step X complete".
  if scan_bypass_patterns "we could just mark step build_loop:tests_verified_failing complete" >/dev/null; then pass "T13: manual_step_complete 'we could'"; else fail_ "T13" "no match for 'we could'"; fi

  # T14: manual_step_complete matches "let's mark X complete".
  if scan_bypass_patterns "let's mark step phase2_init:remote_repo_created done" >/dev/null; then pass "T14: manual_step_complete 'let's'"; else fail_ "T14" "no match for 'let's'"; fi

  # T15: no_verify matches canonical short flag in `git commit -n`.
  if scan_bypass_patterns "you can git commit -nm 'feat: x'" >/dev/null; then pass "T15: no_verify short flag '-n'"; else fail_ "T15" "short flag not matched"; fi

  # T16: scan_bypass_patterns_all returns ALL matches, newline-separated.
  out=$(scan_bypass_patterns_all "use --no-verify and also SOIF_FORCE_STEP=build_loop:foo")
  count=$(echo "$out" | grep -c .)
  if [ "$count" = "2" ] && echo "$out" | grep -q "no_verify" && echo "$out" | grep -q "soif_force_step"; then pass "T16: scan_all returns 2 matches"; else fail_ "T16" "got '$out' (count=$count)"; fi

  # T17: scan_bypass_patterns_all on clean text returns empty (and non-zero exit).
  out=$(scan_bypass_patterns_all "thanks for the update, see you tomorrow" || true)
  if [ -z "$out" ]; then pass "T17: scan_all clean text empty"; else fail_ "T17" "got '$out'"; fi

  # T18: existing single-match scan_bypass_patterns still returns first match only (backward compat).
  out=$(scan_bypass_patterns "use --no-verify and SOIF_FORCE_STEP=foo")
  count=$(echo "$out" | grep -c .)
  if [ "$count" = "1" ]; then pass "T18: scan single still single-match"; else fail_ "T18" "expected 1, got $count"; fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

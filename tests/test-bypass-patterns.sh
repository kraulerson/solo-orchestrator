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

  # T8 (per BL-029 plan amendment): pattern_regex_for returns the actual regex for a known name.
  rgx=$(pattern_regex_for "no_verify")
  if [ "$rgx" = '--no-verify' ]; then pass "T8: regex lookup"; else fail_ "T8" "got '$rgx'"; fi

  # T9: pattern_regex_for returns non-zero for unknown name.
  if pattern_regex_for "totally-not-a-pattern" >/dev/null 2>&1; then fail_ "T9" "expected non-zero"; else pass "T9: unknown returns nonzero"; fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

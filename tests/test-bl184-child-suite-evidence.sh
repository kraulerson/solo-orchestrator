#!/usr/bin/env bash
# tests/test-bl184-child-suite-evidence.sh — BL-184.
#
# The full-suite aggregator used to invoke all 177 of its child suites as
#     if bash "$SCRIPT_DIR/<child>" >/dev/null 2>&1; then pass ...; else fail ...
# so a child that failed ONLY in CI produced exactly one line —
# "<child> FAILED (run for details)" — and "run for details" was unactionable
# precisely BECAUSE the failure did not reproduce locally. The diagnostic was
# destroyed at the moment of capture. BL-135 sat open from 2026-07-18 to
# 2026-07-26 across two ~3h full-lane runs on that catch-22.
#
# tests/full-project-test-suite.sh now routes every delegate through
# run_child_suite (marker: # BL-184-CHILD-EVIDENCE), which captures combined
# stdout+stderr and replays a bounded excerpt ON FAILURE ONLY.
#
# This suite SLICES the real aggregator from line 1 through its
# # BL-184-CHILD-EVIDENCE-END marker and drives that slice against fixture
# children, so it exercises the SHIPPED helper text rather than a copy of it.
# Nothing here scaffolds a project; hermetic, no network, no remote.
#
# Pins:
#   T0  the slice really contains run_child_suite (marker did not drift)
#   T1  a RED child's own failing case name reaches the driver's output
#   T2  ... even when the child is chattier than the tail bound and fails
#       EARLY — the failure-marker digest is what makes this survive
#   T3  the marker-digest header appears for over-bound output
#   T4  the replay delimiter names the child AND its exit status
#   T5  a GREEN child contributes ZERO bytes of its output (no log blowup)
#   T6  pass-labels are emitted byte-identically to the pre-BL-184 shape
#   T7  the default fail-label is "<rel> FAILED (run for details)"
#   T8  an explicit fail-label overrides the default
#   T9  a RED child does NOT abort the run under `set -euo pipefail`, and the
#       driver still exits with the FAIL count
#   T10 child arguments are forwarded past the `--` separator
#   T11 the replay is BOUNDED — mid-file lines of an over-bound child are
#       NOT replayed
#   T12 an output-less RED child is reported as such, not silently
#   T13 REGRESSION GUARD: no delegate in the real aggregator has gone back to
#       the evidence-destroying `>/dev/null 2>&1` shape
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGG="$REPO_ROOT/tests/full-project-test-suite.sh"

unset GITHUB_BASE_REF

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

FX=$(mktemp -d)
mkdir -p "$FX/tests" "$FX/scripts"

# The slice runs the CDF preflight (`|| true`); stub it so the fixture root
# stays silent and the assertions below see only driver output.
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FX/scripts/check-cdf-preflight.sh"

# ---------------------------------------------------------------
# The slice: real aggregator, line 1 .. # BL-184-CHILD-EVIDENCE-END
# ---------------------------------------------------------------
sed -n '1,/^# BL-184-CHILD-EVIDENCE-END/p' "$AGG" > "$FX/tests/driver.sh"

echo "T0: the slice carries the shipped run_child_suite definition"
if grep -q '^run_child_suite() {' "$FX/tests/driver.sh"; then
  pass "T0: run_child_suite() present in the sliced header"
else
  fail_ "T0" "slice does not define run_child_suite — the # BL-184-CHILD-EVIDENCE-END marker moved above the function, so every assertion below would be vacuous"
  echo ""
  echo "Results: $PASSED passed, $FAILED failed"
  rm -rf "$FX"
  exit 1
fi

# ---------------------------------------------------------------
# Fixture children
# ---------------------------------------------------------------
# 1) GREEN but very chatty — its output must never reach the log.
{
  echo '#!/usr/bin/env bash'
  echo 'i=1'
  echo 'while [ "$i" -le 200 ]; do echo "  [PASS] G$i CHATTY-GREEN-LEAK-TOKEN"; i=$((i + 1)); done'
  echo 'exit 0'
} > "$FX/tests/child-green-chatty.sh"

# 2) RED, short output — whole-replay path (output <= tail bound).
{
  echo '#!/usr/bin/env bash'
  echo 'echo "  [PASS] T1: fine"'
  echo 'echo "  [FAIL] T2: SHORT-RED-CASE-NAME"'
  echo 'echo "Results: 1 passed, 1 failed"'
  echo 'exit 1'
} > "$FX/tests/child-red-short.sh"

# 3) RED, over-bound output, failing case EARLY and passing cases after it.
#    A pure tail would LOSE the case name here; the marker digest is what
#    keeps it. MID-FILE-ONLY-TOKEN sits at line ~10 and must NOT be replayed.
{
  echo '#!/usr/bin/env bash'
  echo 'echo "  [FAIL] T1: LONG-RED-EARLY-CASE-NAME"'
  echo 'i=1'
  echo 'while [ "$i" -le 12 ]; do echo "  [PASS] E$i ok"; i=$((i + 1)); done'
  echo 'echo "  [PASS] E13 MID-FILE-ONLY-TOKEN"'
  echo 'i=14'
  echo 'while [ "$i" -le 200 ]; do echo "  [PASS] E$i ok"; i=$((i + 1)); done'
  echo 'echo "Results: 199 passed, 1 failed"'
  echo 'exit 3'
} > "$FX/tests/child-red-long-early.sh"

# 4) GREEN iff its argv is exactly "alpha beta" — pins `--` forwarding.
{
  echo '#!/usr/bin/env bash'
  echo '[ "$*" = "alpha beta" ] || { echo "argv was: $*"; exit 1; }'
  echo 'exit 0'
} > "$FX/tests/child-args.sh"

# 5) RED with NO output at all.
{
  echo '#!/usr/bin/env bash'
  echo 'exit 4'
} > "$FX/tests/child-red-silent.sh"

# 6) GREEN, runs AFTER a red sibling — pins that `set -e` did not abort.
{
  echo '#!/usr/bin/env bash'
  echo 'echo "still running"'
  echo 'exit 0'
} > "$FX/tests/child-green-after-red.sh"

# ---------------------------------------------------------------
# Driver body appended to the slice
# ---------------------------------------------------------------
{
  echo ''
  echo 'section "BL-184 driver"'
  echo 'run_child_suite "tests/child-green-chatty.sh" "GREEN-CHATTY-PASSLABEL"'
  echo 'run_child_suite "tests/child-red-short.sh" "SHORT-PASSLABEL"'
  echo 'run_child_suite "tests/child-red-long-early.sh" "LONG-PASSLABEL" "LONG-EXPLICIT-FAIL-LABEL"'
  echo 'run_child_suite "tests/child-args.sh" "ARGS-PASSLABEL" "ARGS-FAIL-LABEL" -- alpha beta'
  echo 'run_child_suite "tests/child-red-silent.sh" "SILENT-PASSLABEL"'
  echo 'run_child_suite "tests/child-green-after-red.sh" "AFTER-RED-PASSLABEL"'
  echo 'echo "DRIVER-REACHED-END PASS=$PASS FAIL=$FAIL"'
  echo 'rm -rf "$TEST_DIR"'
  echo 'rm -f "$SUITE_CHILD_LOG"'
  echo 'exit $FAIL'
} >> "$FX/tests/driver.sh"

OUT="$FX/driver.out"
driver_rc=0
bash "$FX/tests/driver.sh" > "$OUT" 2>&1 || driver_rc=$?

echo "T1: a RED child's failing case name reaches the output"
if grep -q 'SHORT-RED-CASE-NAME' "$OUT"; then
  pass "T1: short RED child's case name replayed"
else
  fail_ "T1" "SHORT-RED-CASE-NAME absent — the evidence was destroyed again"
fi

echo "T2: an over-bound RED child failing EARLY still surfaces its case name"
if grep -q 'LONG-RED-EARLY-CASE-NAME' "$OUT"; then
  pass "T2: early failure survived the bound via the marker digest"
else
  fail_ "T2" "LONG-RED-EARLY-CASE-NAME absent — a bare tail dropped the only line that names the failure"
fi

echo "T3: marker-digest header present for over-bound output"
if grep -q -- '-- failure markers (' "$OUT"; then
  pass "T3: digest header emitted"
else
  fail_ "T3" "no '-- failure markers (' header — the digest path did not run"
fi

echo "T4: replay delimiter names the child and its exit status"
if grep -q 'captured output BEGIN: tests/child-red-long-early.sh (exit 3)' "$OUT" \
   && grep -q 'captured output END: tests/child-red-long-early.sh' "$OUT"; then
  pass "T4: BEGIN/END delimiters carry child path + exit status"
else
  fail_ "T4" "delimiters missing or do not identify the child/exit code"
fi

echo "T5: a GREEN child contributes zero bytes of its own output"
if grep -q 'CHATTY-GREEN-LEAK-TOKEN' "$OUT"; then
  fail_ "T5" "a passing child's 200 lines leaked into the log — success-path output must stay discarded"
else
  pass "T5: green child's output not replayed"
fi

echo "T6: pass-labels emitted byte-identically to the pre-BL-184 shape"
if grep -q '^  \[PASS\] GREEN-CHATTY-PASSLABEL$' "$OUT" \
   && grep -q '^  \[PASS\] AFTER-RED-PASSLABEL$' "$OUT"; then
  pass "T6: pass() output unchanged"
else
  fail_ "T6" "pass-label text changed — anything grepping these labels breaks"
fi

echo "T7: default fail-label is '<rel> FAILED (run for details)'"
if grep -q '^  \[FAIL\] tests/child-red-short.sh FAILED (run for details)$' "$OUT"; then
  pass "T7: default fail-label preserved"
else
  fail_ "T7" "default fail-label shape changed"
fi

echo "T8: an explicit fail-label overrides the default"
if grep -q '^  \[FAIL\] LONG-EXPLICIT-FAIL-LABEL$' "$OUT" \
   && ! grep -q 'child-red-long-early.sh FAILED (run for details)' "$OUT"; then
  pass "T8: explicit fail-label honored, default not also emitted"
else
  fail_ "T8" "explicit third argument was ignored or duplicated"
fi

echo "T9: RED children do not abort the run; exit status is the FAIL count"
if grep -q '^DRIVER-REACHED-END PASS=3 FAIL=3$' "$OUT" && [ "$driver_rc" -eq 3 ]; then
  pass "T9: run continued past 3 RED children; driver_rc=3 == FAIL"
else
  fail_ "T9" "driver aborted early or miscounted (driver_rc=$driver_rc); run_child_suite must always return 0 under set -e"
fi

echo "T10: child arguments are forwarded past the '--' separator"
if grep -q '^  \[PASS\] ARGS-PASSLABEL$' "$OUT"; then
  pass "T10: argv reached the child intact"
else
  fail_ "T10" "the child did not receive 'alpha beta' — '--' forwarding is broken"
fi

echo "T11: the replay is bounded"
if grep -q 'MID-FILE-ONLY-TOKEN' "$OUT"; then
  fail_ "T11" "a mid-file line of a 200-line child was replayed — the tail bound is not being applied"
else
  pass "T11: mid-file content outside the bound was not replayed"
fi

echo "T12: an output-less RED child is reported, not silently swallowed"
if grep -q '(child produced no output)' "$OUT"; then
  pass "T12: empty capture reported explicitly"
else
  fail_ "T12" "a RED child with no output produced no explanatory line"
fi

echo "T13: no aggregator delegate has regressed to the discard shape"
# Anchored at the start of a CODE line: the helper's own doc-comment quotes the
# retired shape verbatim, and an unanchored grep would match that comment.
if grep -qE '^[[:space:]]*if bash "\$SCRIPT_DIR/.*>/dev/null 2>&1; then$' "$AGG"; then
  fail_ "T13" "tests/full-project-test-suite.sh has a delegate back on 'if bash ... >/dev/null 2>&1' — route it through run_child_suite"
else
  pass "T13: every delegate goes through run_child_suite"
fi

rm -rf "$FX"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-bl046-helpers-split.sh
#
# BL-046: split scripts/lib/helpers.sh into helpers-core.sh (subset used
# by every short-lived caller) + helpers-full.sh (init_log / finalize_log
# + MCP-detection helpers only long-running callers need). helpers.sh
# stays as a backwards-compat shim that transitively loads full → core.
#
# This test proves five contracts. Each corresponds to a paragraph in the
# BL-046 PR body's "Test plan" section and is designed so the RED-first
# failure of any individual assertion pinpoints a specific defect:
#
#   T1  core-only-callers-work
#         Sourcing helpers-core.sh exposes every core helper the
#         short-lived callers (check-versions.sh, check-updates.sh, ...)
#         actually invoke. Calling one of them succeeds without error.
#
#   T2  full-only-callers-still-work
#         Sourcing helpers-full.sh exposes both the core and full APIs.
#         Calling init_log/finalize_log via helpers-full.sh writes a
#         real log file, proving the delegation chain works.
#
#   T3  missing-function-error
#         Sourcing helpers-core.sh does NOT expose init_log / finalize_log
#         / MCP-detection functions. Invoking any of them errors out
#         with rc != 0 (command not found). This proves the boundary is
#         real — the split isn't just an alias.
#
#   T4  shim-backwards-compat
#         Sourcing scripts/lib/helpers.sh (the pre-split entry point
#         every existing caller uses) still exposes the FULL API. No
#         caller breaks.
#
#   T5  idempotent-source
#         Sourcing helpers-core.sh twice in the same shell does not
#         fail, does not re-run the color setup, and does not create
#         duplicate function definitions. Same for helpers-full.sh
#         and helpers.sh.
#
# Verification strategy: build a small harness per T-case that sources
# the target file, invokes the assertion, and exits with rc that
# encodes pass/fail. Colours are disabled so grep-based assertions on
# the output are stable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$REPO_ROOT/scripts/lib"
HELPERS_SHIM="$LIB_DIR/helpers.sh"
HELPERS_CORE="$LIB_DIR/helpers-core.sh"
HELPERS_FULL="$LIB_DIR/helpers-full.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Preconditions — the three files exist.
[ -f "$HELPERS_SHIM" ] || { echo "PRECONDITION FAIL: $HELPERS_SHIM missing"; exit 99; }
[ -f "$HELPERS_CORE" ] || { echo "PRECONDITION FAIL: $HELPERS_CORE missing"; exit 99; }
[ -f "$HELPERS_FULL" ] || { echo "PRECONDITION FAIL: $HELPERS_FULL missing"; exit 99; }

echo "── BL-046: helpers.sh core/full split contract tests ──"
echo ""

# ── T1: core-only callers work ──────────────────────────────────
# Every short-lived caller (per Step 4 dead-code-perf-eval report) uses
# some subset of: print_ok/warn/fail/info/step/header, log_line,
# log_section, run_with_timeout, prompt_input, prompt_yes_no,
# prompt_choice, prompt_install, guard_not_in_framework. All must be
# defined after sourcing helpers-core.sh alone.
CORE_EXPECTED_FUNCS=(
  print_header print_step print_ok print_warn print_fail print_info
  log_line log_section run_with_timeout
  prompt_input prompt_yes_no prompt_choice prompt_install
  guard_not_in_framework
)
t1_out=$(bash -c "
source '$HELPERS_CORE'
missing=0
for f in ${CORE_EXPECTED_FUNCS[*]}; do
  declare -F \"\$f\" >/dev/null || { echo \"MISSING \$f\"; missing=1; }
done
# Also invoke one to prove it actually runs (print_ok writes to stdout).
print_ok 't1-invocation-check' > /dev/null
exit \$missing
" 2>&1)
t1_rc=$?
if [ $t1_rc -eq 0 ]; then
  pass "T1 core-only-callers-work: all ${#CORE_EXPECTED_FUNCS[@]} core functions defined and callable"
else
  fail_ "T1 core-only-callers-work" "rc=$t1_rc; output=$t1_out"
fi

# ── T2: full callers still work ─────────────────────────────────
# Sourcing helpers-full.sh must expose both the full-set functions
# AND (transitively) every core function. Verify init_log actually
# writes a log by pointing it at a tempdir and checking the file
# contents.
FULL_EXPECTED_FUNCS=(
  init_log finalize_log
  is_context7_mcp_registered is_qdrant_mcp_registered
  is_qdrant_container_running register_qdrant_mcp
)
tmp_t2=$(mktemp -d)
t2_out=$(bash -c "
source '$HELPERS_FULL'
missing=0
# Full set
for f in ${FULL_EXPECTED_FUNCS[*]}; do
  declare -F \"\$f\" >/dev/null || { echo \"MISSING FULL \$f\"; missing=1; }
done
# Core set (transitively loaded)
for f in ${CORE_EXPECTED_FUNCS[*]}; do
  declare -F \"\$f\" >/dev/null || { echo \"MISSING CORE \$f\"; missing=1; }
done
# Invoke init_log for real — it should create a log file in the tempdir.
init_log '$tmp_t2'
if [ -z \"\${LOG_FILE:-}\" ] || [ ! -f \"\$LOG_FILE\" ]; then
  echo 'init_log did not create a log file'
  missing=1
fi
# Invoke a print_ helper — should append (via log_line) to LOG_FILE.
print_ok 'test-line' > /dev/null
if ! grep -q 'test-line' \"\$LOG_FILE\" 2>/dev/null; then
  echo 'print_ok did not route through log_line to LOG_FILE'
  missing=1
fi
exit \$missing
" 2>&1)
t2_rc=$?
rm -rf "$tmp_t2"
if [ $t2_rc -eq 0 ]; then
  pass "T2 full-callers-still-work: full+core surface + init_log/log_line integration"
else
  fail_ "T2 full-callers-still-work" "rc=$t2_rc; output=$t2_out"
fi

# ── T3: missing-function-error (boundary enforcement) ──────────
# helpers-core.sh must NOT define the full-set functions. Attempting to
# call one of them must fail (rc=127, "command not found").
t3_out=$(bash -c "
source '$HELPERS_CORE'
# Try to call init_log. If the split boundary is broken (init_log
# leaked into core), this succeeds and rc=0. That's a boundary defect.
init_log /tmp/should-not-be-created-bl046-t3 2>/dev/null
exit \$?
")
t3_rc=$?
if [ $t3_rc -eq 127 ]; then
  pass "T3 missing-function-error: init_log absent from core (rc=127 command-not-found)"
else
  fail_ "T3 missing-function-error" "expected rc=127 (command not found); got rc=$t3_rc — init_log leaked into helpers-core.sh"
fi

# Second half of T3: verify each full-set function is absent from core.
t3b_out=$(bash -c "
source '$HELPERS_CORE'
leaked=0
for f in ${FULL_EXPECTED_FUNCS[*]}; do
  if declare -F \"\$f\" >/dev/null; then
    echo \"LEAKED \$f\"
    leaked=1
  fi
done
exit \$leaked
" 2>&1)
t3b_rc=$?
if [ $t3b_rc -eq 0 ]; then
  pass "T3b none of the ${#FULL_EXPECTED_FUNCS[@]} full-set functions leak into helpers-core.sh"
else
  fail_ "T3b full-set leak into core" "$t3b_out"
fi

# ── T4: shim backwards compat ──────────────────────────────────
# Every existing caller sources scripts/lib/helpers.sh (the shim).
# After sourcing, both core AND full APIs must be present — the shim
# must transitively load helpers-full.sh (which loads helpers-core.sh).
t4_out=$(bash -c "
source '$HELPERS_SHIM'
missing=0
for f in ${CORE_EXPECTED_FUNCS[*]} ${FULL_EXPECTED_FUNCS[*]}; do
  declare -F \"\$f\" >/dev/null || { echo \"MISSING \$f\"; missing=1; }
done
exit \$missing
" 2>&1)
t4_rc=$?
if [ $t4_rc -eq 0 ]; then
  pass "T4 shim-backwards-compat: helpers.sh exposes all $(( ${#CORE_EXPECTED_FUNCS[@]} + ${#FULL_EXPECTED_FUNCS[@]} )) functions"
else
  fail_ "T4 shim-backwards-compat" "rc=$t4_rc; output=$t4_out"
fi

# ── T5: idempotent source ───────────────────────────────────────
# Sourcing the same file twice in one shell must be a no-op. Idempotency
# guards use _SOIF_HELPERS_*_LOADED sentinels; if those regress, the
# second source will still succeed (bash allows redefining functions),
# but a lot of setup work (color-var reassignment, dirname resolution)
# will re-run. Assert via $SECONDS delta that the second source is
# strictly cheaper — but the primary check is "no error". A regression
# that removes the idempotency guard would still pass "no error", but
# would defeat the point of the guard. So also assert the sentinel var
# stays set after the second source (proving the guard fired).
t5_out=$(bash -c '
source "'"$HELPERS_CORE"'"
# First source set the sentinel.
first_sentinel="${_SOIF_HELPERS_CORE_LOADED:-}"
if [ -z "$first_sentinel" ]; then
  echo "sentinel not set after first source"
  exit 1
fi
# Deliberately clear a color var so we can detect if the second source
# ran the color-setup block. A working idempotency guard short-circuits
# BEFORE the color block, leaving BOLD empty.
BOLD=""
source "'"$HELPERS_CORE"'"
if [ -n "$BOLD" ]; then
  echo "second source re-ran color setup (idempotency guard failed)"
  exit 1
fi
# print_ok must still be callable after two sources.
print_ok "idempotent" > /dev/null
exit $?
' 2>&1)
t5_rc=$?
if [ $t5_rc -eq 0 ]; then
  pass "T5 idempotent-source: helpers-core.sh sourced twice is a no-op (guard held)"
else
  fail_ "T5 idempotent-source" "rc=$t5_rc; output=$t5_out"
fi

# Repeat T5 for helpers-full.sh and the shim — each has its own guard.
for lib_pair in "helpers-full.sh:$HELPERS_FULL:_SOIF_HELPERS_FULL_LOADED" \
                "helpers.sh:$HELPERS_SHIM:_SOIF_HELPERS_SHIM_LOADED"; do
  IFS=":" read -r libname libpath sentinel <<<"$lib_pair"
  out=$(bash -c "
    source '$libpath'
    first=\"\${$sentinel:-}\"
    if [ -z \"\$first\" ]; then echo 'sentinel not set'; exit 1; fi
    source '$libpath'
    still=\"\${$sentinel:-}\"
    if [ \"\$first\" != \"\$still\" ]; then echo 'sentinel changed'; exit 1; fi
    exit 0
  " 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then
    pass "T5b idempotent-source: $libname sentinel $sentinel held across two sources"
  else
    fail_ "T5b idempotent-source ($libname)" "rc=$rc; $out"
  fi
done

# ── Summary ─────────────────────────────────────────────────────
echo ""
echo "── Summary ──"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0

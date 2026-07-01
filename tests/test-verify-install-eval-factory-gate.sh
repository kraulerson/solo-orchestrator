#!/usr/bin/env bash
# tests/test-verify-install-eval-factory-gate.sh
#
# BL-050 (Step 4 ROI #6): scripts/verify-install.sh synthesizes 20
# fix_tool_install_N wrapper functions via `eval` on every invocation.
# `--check-only` short-circuits in run_remediation() before any FIXABLE
# fix_func is dispatched, so those 20 evals + 1 `seq` subshell are pure
# overhead on the check-only path (~5-10 ms per invocation per Step 4
# recon; measured ~1.5 ms on the S3 harness).
#
# The fix gates the eval loop behind `[ "$MODE" != "check-only" ]`.
# These tests exercise both success and failure paths of that gate:
#
#   T1  check-only mode: the eval-loop bash `-x` trace lines DO NOT
#       appear (the loop is skipped).
#   T2  check-only mode: the operator-visible report table still
#       renders (the gate did not shortcut too much).
#   T3  auto-fix mode: the eval-loop DOES run — bash `-x` trace lines
#       for `fix_tool_install_0` .. `fix_tool_install_19` appear.
#       Confirms the gate isn't over-applied.
#   T4  Mutation: rewrite the gate to `true`, re-run T1 — must now
#       observe the eval trace lines (RED). Confirms T1's oracle is
#       real, not vacuous.
#
# Trace observation strategy: `bash -x scripts/verify-install.sh ...`
# emits `+ eval fix_tool_install_0() { fix_tool_install 0; }` (or
# equivalent xtrace format) when the eval runs. Grepping for
# `fix_tool_install_[0-9]+\(\)` against xtrace stderr is a stable
# oracle across bash versions (bash 3.2 on macOS system, bash 4/5 on
# CI).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

cd /tmp

setup_clean_project() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language typescript --track light --deployment personal \
    >/dev/null 2>&1
  VERIFY="$PROJ/scripts/verify-install.sh"
}
teardown() { rm -rf "$TMP"; }

# Run bash -x on verify-install and return stderr xtrace. We use
# BASH_XTRACEFD to isolate the trace to fd 3 so we don't confuse it
# with the script's own stderr messages that happen to mention
# fix_tool_install_ names in remediation banners.
run_verify_xtrace() {
  local mode="$1"  # --check-only or --auto-fix
  ( cd "$PROJ" && exec 3>&2 && BASH_XTRACEFD=3 bash -x "$VERIFY" "$mode" ) 2>&1
}

# ============================================================
# T1: check-only mode skips the eval-loop (post-fix behavior).
# ============================================================
echo "T1: --check-only mode does NOT synthesize fix_tool_install_N wrappers via eval"
setup_clean_project
trace=$(run_verify_xtrace --check-only 2>&1 || true)
# The eval line is:  eval "fix_tool_install_${_i}() { fix_tool_install ${_i}; }"
# xtrace emits:      + eval 'fix_tool_install_0() { fix_tool_install 0; }'
# Count how many `eval fix_tool_install_` xtrace lines we see.
# Anchor the pattern to bash's xtrace `+ eval ` prefix so we don't
# false-positive on the register_fixable "fix_tool_install_$i" LABEL
# strings (which are just argv, not evals).
count_evals=$(echo "$trace" | grep -cE '^\+ *eval .*fix_tool_install_[0-9]+' || true)
case "$count_evals" in ''|*[!0-9]*) count_evals=0 ;; esac
if [ "$count_evals" -eq 0 ]; then
  pass "T1: no eval-factory xtrace lines observed in check-only mode"
else
  fail_ "T1" "check-only mode still ran the eval-factory ($count_evals xtrace lines observed; expected 0)"
fi
teardown

# ============================================================
# T2: check-only still produces the report table (gate not too aggressive).
# ============================================================
echo "T2: --check-only mode still emits the Installation Verification Report"
setup_clean_project
out=$( cd "$PROJ" && bash "$VERIFY" --check-only 2>&1 || true )
# The report header from show_report() (line ~1427):
#   │  Installation Verification Report            │
if echo "$out" | grep -q "Installation Verification Report"; then
  pass "T2: report table renders in check-only mode"
else
  fail_ "T2" "report table missing in check-only mode (gate too aggressive)"
fi
teardown

# ============================================================
# T3: non-check-only mode STILL runs the eval-factory (gate not too broad).
# ============================================================
echo "T3: --auto-fix mode DOES synthesize fix_tool_install_N wrappers via eval"
setup_clean_project
# --auto-fix reaches run_remediation() which can invoke fix_tool_install_N
# via dispatch, so the factory must still exist on that path.
trace=$(run_verify_xtrace --auto-fix 2>&1 || true)
count_evals=$(echo "$trace" | grep -cE '^\+ *eval .*fix_tool_install_[0-9]+' || true)
case "$count_evals" in ''|*[!0-9]*) count_evals=0 ;; esac
if [ "$count_evals" -ge 20 ]; then
  pass "T3: eval-factory ran in --auto-fix mode ($count_evals xtrace lines; >= 20 expected)"
else
  fail_ "T3" "eval-factory did NOT run in --auto-fix mode ($count_evals xtrace lines; expected >= 20 — gate is over-applied)"
fi
teardown

# ============================================================
# T4: Mutation experiment — revert the gate to `true`, confirm T1 fails RED.
# ============================================================
echo "T4: mutation — revert gate to unconditional; check-only should re-run eval-factory (proves T1 oracle is real)"
setup_clean_project
# Rewrite the gate condition in the on-disk verify-install.sh:
#     if [ "$MODE" != "check-only" ]; then
#   → if true; then
# We match on the exact if-line, replace, and confirm the substitution
# actually landed (else the test would silently vacuous-pass).
if ! grep -q 'if \[ "\$MODE" != "check-only" \]; then' "$VERIFY"; then
  fail_ "T4" "mutation-setup: could not find the gate line to rewrite"
  teardown
else
  # Portable sed for macOS + Linux (uses .bak and cleans up).
  sed -i.bak 's|if \[ "\$MODE" != "check-only" \]; then|if true; then|' "$VERIFY"
  rm -f "$VERIFY.bak"
  if ! grep -q '^if true; then$' "$VERIFY"; then
    fail_ "T4" "mutation-setup: sed substitution did not land"
    teardown
  else
    trace=$(run_verify_xtrace --check-only 2>&1 || true)
    count_evals=$(echo "$trace" | grep -cE '^\+ *eval .*fix_tool_install_[0-9]+' || true)
    case "$count_evals" in ''|*[!0-9]*) count_evals=0 ;; esac
    if [ "$count_evals" -ge 20 ]; then
      pass "T4: mutation restored the eval-factory in check-only ($count_evals xtrace lines) — T1 oracle is real"
    else
      fail_ "T4" "mutation did NOT restore the eval-factory ($count_evals xtrace lines; expected >= 20) — T1 oracle may be vacuous"
    fi
    teardown
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

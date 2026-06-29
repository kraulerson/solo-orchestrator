#!/usr/bin/env bash
# tests/test-bypass-audit-trap-isolation.sh — regression for verifier
# follow-up on PR #93.
#
# bash `trap '...' EXIT INT TERM` is shell-global, not function-local.
# The pre-fix bypass_audit_append / bypass_audit_close_pending installed
# their tmp-cleanup trap at function scope, then did `trap - EXIT INT TERM`
# unconditionally — silently destroying any pre-existing trap the caller
# had set. The fix wraps the rename window in a subshell so the trap is
# contained to that subshell and the caller's trap survives.
#
# This is a *latent* defect on main (no current caller of bypass_audit_*
# also sets an EXIT trap), but it's a library function — the next consumer
# that adds `trap 'cleanup' EXIT` would have their cleanup silently wiped,
# which is exactly the silent-bypass class this PR was created to remove.
#
# T1: caller sets EXIT trap, then calls bypass_audit_append. After the
#     call, the caller's trap must still be active. Asserted via two
#     channels: (a) `trap -p EXIT` still shows the caller's trap;
#     (b) on subshell exit, the caller's trap body actually fires.
#
# T2: caller sets EXIT trap, then triggers a jq-failure path in append
#     (malformed JSON in the audit file). The internal rollback runs
#     (rc=1, tmp removed) AND the caller's trap still fires at exit.
#
# T3 / T4: same for bypass_audit_close_pending (happy + jq-failure path).
#
# T5: bypass_audit_init creates the audit file with mode 600 even under
#     a permissive umask. Pre-fix `echo "[]" > "$file"` inherited umask,
#     leaving the governance ledger world-readable on default-022 boxes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-audit.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  echo "[]" > "$PROJ/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

ROW='{"timestamp":"2026-06-28T00:00:00Z","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{"pattern":"x"},"user_response":"PENDING","final_outcome":"recorded_only"}'

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: bypass_audit_append preserves caller's EXIT trap (happy path) ==="
# ════════════════════════════════════════════════════════════════════
setup
# Run in a subshell so we can observe the EXIT trap firing as the subshell
# exits. The marker file is created by the caller's trap; if the trap was
# wiped by the library, the marker won't exist.
MARKER="$TMP/caller_trap_fired"
(
  source "$LIB"
  trap 'touch "'"$MARKER"'"' EXIT
  bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1
  # Also check trap is still registered post-call (in-process channel).
  trap_out=$(trap -p EXIT)
  if echo "$trap_out" | grep -q "caller_trap_fired"; then
    echo "INPROC_TRAP_PRESENT" > "$TMP/inproc_status"
  else
    echo "INPROC_TRAP_WIPED" > "$TMP/inproc_status"
  fi
)
inproc_status=$(cat "$TMP/inproc_status" 2>/dev/null || echo "MISSING")
if [ "$inproc_status" = "INPROC_TRAP_PRESENT" ]; then
  pass "T1a: in-process trap -p EXIT still shows caller's trap after append"
else
  fail_ "T1a" "in-process trap was wiped by bypass_audit_append (got: $inproc_status)"
fi
if [ -f "$MARKER" ]; then
  pass "T1b: caller's EXIT trap fired at subshell exit (marker created)"
else
  fail_ "T1b" "caller's EXIT trap did NOT fire — bypass_audit_append silently cleared it"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: bypass_audit_append preserves caller's EXIT trap (jq-failure path) ==="
# ════════════════════════════════════════════════════════════════════
setup
# Corrupt the audit file so jq fails on the append.
echo "not valid json {{{" > "$PROJ/.claude/bypass-audit.json"
MARKER="$TMP/caller_trap_fired"
(
  source "$LIB"
  trap 'touch "'"$MARKER"'"' EXIT
  # Expected to fail (rc=1) because jq cannot parse the file.
  bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1
  rc=$?
  echo "$rc" > "$TMP/append_rc"
  # Check trap still installed.
  trap_out=$(trap -p EXIT)
  if echo "$trap_out" | grep -q "caller_trap_fired"; then
    echo "INPROC_TRAP_PRESENT" > "$TMP/inproc_status"
  else
    echo "INPROC_TRAP_WIPED" > "$TMP/inproc_status"
  fi
)
append_rc=$(cat "$TMP/append_rc" 2>/dev/null || echo "MISSING")
if [ "$append_rc" = "1" ]; then
  pass "T2a: append correctly returned rc=1 on jq-failure"
else
  fail_ "T2a" "expected append rc=1 on malformed input; got $append_rc"
fi
# Verify rollback: no orphan tmp files.
orphans=$(find "$PROJ/.claude" -name "bypass-audit.json.*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$orphans" = "0" ]; then
  pass "T2b: jq-failure rollback ran — no orphan tmp files"
else
  fail_ "T2b" "found $orphans orphan tmp file(s) after jq-failure"
fi
inproc_status=$(cat "$TMP/inproc_status" 2>/dev/null || echo "MISSING")
if [ "$inproc_status" = "INPROC_TRAP_PRESENT" ]; then
  pass "T2c: caller's trap still registered after jq-failure path"
else
  fail_ "T2c" "caller's trap wiped on jq-failure path (got: $inproc_status)"
fi
if [ -f "$MARKER" ]; then
  pass "T2d: caller's EXIT trap fired even after jq-failure rollback"
else
  fail_ "T2d" "caller's EXIT trap did NOT fire after jq-failure path"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: bypass_audit_close_pending preserves caller's EXIT trap (happy path) ==="
# ════════════════════════════════════════════════════════════════════
setup
# Seed the file with a PENDING row so close_pending has work to do.
( source "$LIB" && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 )
MARKER="$TMP/caller_trap_fired"
(
  source "$LIB"
  trap 'touch "'"$MARKER"'"' EXIT
  bypass_audit_close_pending "$PROJ" "accept" >/dev/null 2>&1
  trap_out=$(trap -p EXIT)
  if echo "$trap_out" | grep -q "caller_trap_fired"; then
    echo "INPROC_TRAP_PRESENT" > "$TMP/inproc_status"
  else
    echo "INPROC_TRAP_WIPED" > "$TMP/inproc_status"
  fi
)
inproc_status=$(cat "$TMP/inproc_status" 2>/dev/null || echo "MISSING")
if [ "$inproc_status" = "INPROC_TRAP_PRESENT" ]; then
  pass "T3a: in-process trap -p EXIT still shows caller's trap after close_pending"
else
  fail_ "T3a" "in-process trap was wiped by bypass_audit_close_pending (got: $inproc_status)"
fi
if [ -f "$MARKER" ]; then
  pass "T3b: caller's EXIT trap fired at subshell exit after close_pending"
else
  fail_ "T3b" "caller's EXIT trap did NOT fire — bypass_audit_close_pending cleared it"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: bypass_audit_close_pending preserves caller's EXIT trap (jq-failure path) ==="
# ════════════════════════════════════════════════════════════════════
setup
# Seed file then corrupt it before close_pending so jq fails inside.
( source "$LIB" && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 )
echo "not valid json {{{" > "$PROJ/.claude/bypass-audit.json"
MARKER="$TMP/caller_trap_fired"
(
  source "$LIB"
  trap 'touch "'"$MARKER"'"' EXIT
  bypass_audit_close_pending "$PROJ" "accept" >/dev/null 2>&1
  rc=$?
  echo "$rc" > "$TMP/close_rc"
  trap_out=$(trap -p EXIT)
  if echo "$trap_out" | grep -q "caller_trap_fired"; then
    echo "INPROC_TRAP_PRESENT" > "$TMP/inproc_status"
  else
    echo "INPROC_TRAP_WIPED" > "$TMP/inproc_status"
  fi
)
close_rc=$(cat "$TMP/close_rc" 2>/dev/null || echo "MISSING")
if [ "$close_rc" = "1" ]; then
  pass "T4a: close_pending correctly returned rc=1 on jq-failure"
else
  fail_ "T4a" "expected close_pending rc=1 on malformed input; got $close_rc"
fi
orphans=$(find "$PROJ/.claude" -name "bypass-audit.json.*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$orphans" = "0" ]; then
  pass "T4b: jq-failure rollback ran — no orphan tmp files"
else
  fail_ "T4b" "found $orphans orphan tmp file(s) after close_pending jq-failure"
fi
inproc_status=$(cat "$TMP/inproc_status" 2>/dev/null || echo "MISSING")
if [ "$inproc_status" = "INPROC_TRAP_PRESENT" ]; then
  pass "T4c: caller's trap still registered after close_pending jq-failure"
else
  fail_ "T4c" "caller's trap wiped on close_pending jq-failure (got: $inproc_status)"
fi
if [ -f "$MARKER" ]; then
  pass "T4d: caller's EXIT trap fired even after close_pending jq-failure"
else
  fail_ "T4d" "caller's EXIT trap did NOT fire after close_pending jq-failure"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: bypass_audit_init creates file with mode 600 (umask hardening) ==="
# ════════════════════════════════════════════════════════════════════
# `echo "[]" > "$file"` inherits umask. On a default-022 umask system the
# governance ledger ends up world-readable (0644). Audit fix: init should
# chmod 600 after creation so the preserve-mode helper has a sane baseline.
setup
rm -f "$PROJ/.claude/bypass-audit.json"
# Force a permissive umask so the bug (if any) is visible.
( umask 022; source "$LIB" && bypass_audit_init "$PROJ" )
mode=$(stat -f "%Lp" "$PROJ/.claude/bypass-audit.json" 2>/dev/null \
     || stat -c "%a" "$PROJ/.claude/bypass-audit.json" 2>/dev/null)
if [ "$mode" = "600" ]; then
  pass "T5: bypass_audit_init created file with mode 600 (was $mode)"
else
  fail_ "T5" "expected mode 600 from bypass_audit_init under umask 022; got $mode (governance artifact left world-readable)"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-pending-approval-resolve-decision.sh
#
# Regression tests for code-escalate-pending-4 (audit v2 S3):
#   scripts/pending-approval.sh::cmd_resolve removed the sentinel
#   FIRST, then validated `--decision`. A typo such as
#   `--resolve --decision accpet` therefore:
#     1. deleted the sentinel (consumers unblocked),
#     2. printed [OK] "Pending approval resolved.",
#     3. THEN failed validation in bypass_audit_close_pending
#        ("unknown decision 'accpet'") and exited 1,
#     4. leaving PENDING audit rows stranded until the operator
#        noticed and re-ran with a correct decision.
#
# The fix is to validate `--decision` against {accept, decline} at
# the top of cmd_resolve, BEFORE touching the sentinel. Also covers
# the existing test-pending-approval.sh:p17 atomic-write expectation
# (no regression) and the regression case for code-escalate-pending-3
# (escalate-to-user.sh must not bypass the sentinel publication path —
# i.e. there is no direct '> pending-approval.json' redirect).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/pending-approval.sh"
ESCALATE="$REPO_ROOT/scripts/escalate-to-user.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_project() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
}
teardown_project() { rm -rf "$TMP"; }

# ---------------------------------------------------------------------
# T1: `--resolve --decision <typo>` must NOT delete the sentinel.
# (Pre-fix: sentinel deleted, then close_pending failed.)
# ---------------------------------------------------------------------
echo "T1: --resolve --decision <typo> preserves the sentinel"
setup_project
echo '[]' > "$TMP/.claude/bypass-audit.json"
echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A1","offered_at":"2026-04-25T12:00:00Z"}' \
  > "$TMP/.claude/pending-approval.json"

out=$( cd "$TMP" && "$SCRIPT" --resolve --decision accpet 2>&1 ) || rc=$?
rc=${rc:-0}

if [ -f "$TMP/.claude/pending-approval.json" ]; then
  pass "T1a: sentinel preserved on typo"
else
  fail_ "T1a" "sentinel was deleted before --decision validation; out: $out"
fi

if [ "$rc" -ne 0 ]; then
  pass "T1b: exits non-zero on typo"
else
  fail_ "T1b" "expected non-zero rc, got rc=$rc; out: $out"
fi

# It must NOT have printed the success line that pre-fix appeared
# before the close-failure (the [OK]+[FAIL] split was the audit
# finding's primary symptom).
if echo "$out" | grep -qE '\[OK\][[:space:]]+Pending approval resolved'; then
  fail_ "T1c" "should not emit '[OK] Pending approval resolved.' on typo; out: $out"
else
  pass "T1c: no false [OK] 'resolved' message"
fi

# It must mention the unknown decision so the operator knows what to fix.
if echo "$out" | grep -qiE 'unknown decision|invalid decision|expected.*accept.*decline'; then
  pass "T1d: error message names the invalid decision"
else
  fail_ "T1d" "error message should name the typo; out: $out"
fi
teardown_project

# ---------------------------------------------------------------------
# T2: `--resolve --decision accept` (valid) still removes the sentinel
# and closes the audit row. (Existing behavior — regression guard.)
# ---------------------------------------------------------------------
echo "T2: --resolve --decision accept (valid) removes sentinel + closes audit"
setup_project
echo '[{"timestamp":"x","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{},"user_response":"PENDING","final_outcome":"recorded_only"}]' \
  > "$TMP/.claude/bypass-audit.json"
echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A1","offered_at":"2026-04-25T12:00:00Z"}' \
  > "$TMP/.claude/pending-approval.json"

rc=0
out=$( cd "$TMP" && "$SCRIPT" --resolve --decision accept 2>&1 ) || rc=$?

if [ "$rc" -eq 0 ] \
   && [ ! -f "$TMP/.claude/pending-approval.json" ] \
   && [ "$(jq -r '.[0].user_response' "$TMP/.claude/bypass-audit.json")" = "accepted" ]; then
  pass "T2: sentinel removed + audit row closed for valid decision"
else
  fail_ "T2" "rc=$rc sentinel_present=$([ -f "$TMP/.claude/pending-approval.json" ] && echo yes || echo no) audit=$(jq -r '.[0].user_response' "$TMP/.claude/bypass-audit.json"); out: $out"
fi
teardown_project

# ---------------------------------------------------------------------
# T3: `--resolve --decision decline` (valid) — regression guard.
# ---------------------------------------------------------------------
echo "T3: --resolve --decision decline (valid) removes sentinel + closes audit"
setup_project
echo '[{"timestamp":"x","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{},"user_response":"PENDING","final_outcome":"recorded_only"}]' \
  > "$TMP/.claude/bypass-audit.json"
echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A1","offered_at":"2026-04-25T12:00:00Z"}' \
  > "$TMP/.claude/pending-approval.json"

rc=0
out=$( cd "$TMP" && "$SCRIPT" --resolve --decision decline 2>&1 ) || rc=$?

if [ "$rc" -eq 0 ] \
   && [ ! -f "$TMP/.claude/pending-approval.json" ] \
   && [ "$(jq -r '.[0].user_response' "$TMP/.claude/bypass-audit.json")" = "declined" ]; then
  pass "T3: sentinel removed + audit row closed for decline"
else
  fail_ "T3" "rc=$rc out: $out"
fi
teardown_project

# ---------------------------------------------------------------------
# T4: `--resolve` without --decision — sentinel removed, audit untouched.
# (Backward-compat regression guard.)
# ---------------------------------------------------------------------
echo "T4: --resolve without --decision removes sentinel, leaves audit"
setup_project
echo '[{"timestamp":"x","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{},"user_response":"PENDING","final_outcome":"recorded_only"}]' \
  > "$TMP/.claude/bypass-audit.json"
echo '{"question":"q","options":["A1: x","A2: y"],"recommendation":"A1","offered_at":"2026-04-25T12:00:00Z"}' \
  > "$TMP/.claude/pending-approval.json"

rc=0
out=$( cd "$TMP" && "$SCRIPT" --resolve 2>&1 ) || rc=$?

if [ "$rc" -eq 0 ] \
   && [ ! -f "$TMP/.claude/pending-approval.json" ] \
   && [ "$(jq -r '.[0].user_response' "$TMP/.claude/bypass-audit.json")" = "PENDING" ]; then
  pass "T4: backward-compat — sentinel rm, audit untouched"
else
  fail_ "T4" "rc=$rc out: $out"
fi
teardown_project

# ---------------------------------------------------------------------
# T5: code-escalate-pending-3 source-shape check — escalate-to-user.sh
# must not contain a direct '> .claude/pending-approval.json' redirect.
# Atomic publication must go through pending-approval.sh --offer
# (which uses mktemp + mv).
# ---------------------------------------------------------------------
echo "T5: escalate-to-user.sh contains no direct sentinel write"
if [ ! -f "$ESCALATE" ]; then
  fail_ "T5" "escalate-to-user.sh missing"
else
  direct=$(grep -cE '^[[:space:]]*[^#]*>[[:space:]]+("?\$?\{?[A-Za-z_]*\}?/?\.claude/pending-approval\.json"?)' "$ESCALATE" || true)
  case "$direct" in ''|*[!0-9]*) direct=0 ;; esac
  if [ "$direct" -eq 0 ]; then
    pass "T5: no direct '> pending-approval.json' redirect in escalate-to-user.sh"
  else
    fail_ "T5" "found $direct direct sentinel redirect(s) — atomic publication bypassed"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

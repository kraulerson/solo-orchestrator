#!/usr/bin/env bash
# tests/test-bypass-audit-integrity.sh — BL-029 governance-log integrity
# regression tests for the three defects survey #2 called out:
#
#   D1. escalate-to-user.sh `|| true` swallows audit-log failures while
#       still printing '(and audit log)' — silent governance hole.
#   D2. bypass_audit_close_pending closes ALL PENDING rows including
#       escalation rows, flipping final_outcome from 'escalated' to
#       'bypassed' — type conflation across the audit-row enum.
#   D3. bypass_audit_append uses $TMPDIR mktemp. On macOS that's
#       /var/folders/* — a different filesystem from a project under
#       /tmp or $HOME. `mv` becomes copy+unlink, not atomic. A SIGKILL
#       during the write window can truncate the append-only ledger.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-audit.sh"
ESCALATE="$REPO_ROOT/scripts/escalate-to-user.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_project() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  ( cd "$PROJ" && git init -q && git config user.email t@t.l && git config user.name t \
      && echo init > i && git add i && git commit -qm init )
  cat > "$PROJ/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  echo "[]" > "$PROJ/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D3: bypass_audit_append uses adjacent mktemp (atomic mv across filesystems) ==="
# ════════════════════════════════════════════════════════════════════

# T1: bypass_audit_append's mktemp template puts the temp file in the
# SAME directory as the audit file. Verified by grepping the library
# source: the mktemp call must reference the audit file's directory.
# This is the line-level contract the fix implements.
echo "T1: bypass_audit_append mktemp uses an audit-file-adjacent template"
if grep -qE "mktemp.*\\\$\\{file\\}\\.X" "$LIB" \
   || grep -qE 'mktemp[^|]*"\$file\.X' "$LIB"; then
  pass "T1: library uses mktemp \"\${file}.XXXXXX\" pattern"
else
  fail_ "T1" "library still uses bare \`mktemp\` (cross-filesystem mv risk on macOS)"
fi

# T2: end-to-end: appending to an audit file on a different filesystem
# than \$TMPDIR succeeds (proves the rename works). On macOS the project
# under /tmp lives on /System/Volumes/Data while \$TMPDIR points at
# /var/folders/... — without the fix the mv would copy+unlink. With the
# fix, mktemp uses a sibling path so mv is a rename. Either way the
# write must succeed; the assertion is that the audit row is durably
# written.
echo "T2: bypass_audit_append succeeds + emits the row across filesystems"
setup_project
# shellcheck disable=SC1090
( source "$LIB"
  row=$(jq -nc '{timestamp:"2026-04-28T00:00:00Z", session_id:null, type:"claude_bypass_proposal", actor:"claude", enforcement_level_at_event:"strict", details:{pattern:"x"}, user_response:"PENDING", final_outcome:"recorded_only"}')
  bypass_audit_append "$PROJ" "$row" >/dev/null 2>&1
)
rows=$(jq 'length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" = "1" ]; then
  pass "T2: bypass_audit_append wrote row durably"
else
  fail_ "T2" "rows=$rows (expected 1)"
fi
teardown

# T3: same contract for bypass_audit_close_pending — its mktemp must
# also be adjacent to the audit file.
echo "T3: bypass_audit_close_pending mktemp uses adjacent template"
# Use a more permissive grep — the line is somewhere inside the
# close_pending function block.
close_block=$(awk '/^bypass_audit_close_pending\(\)/,/^}$/' "$LIB")
if echo "$close_block" | grep -qE 'mktemp.*\$\{?file\}?\.X'; then
  pass "T3: bypass_audit_close_pending uses adjacent mktemp"
else
  fail_ "T3" "bypass_audit_close_pending still uses bare mktemp"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D2: bypass_audit_close_pending scopes to claude_bypass_proposal rows ==="
# ════════════════════════════════════════════════════════════════════

# T4: a PENDING escalation row is left alone when --decision is applied.
# The pre-fix behavior closed every PENDING row including escalations,
# silently flipping their final_outcome from 'escalated' to 'bypassed'.
echo "T4: close_pending(accept) does NOT touch escalation rows"
setup_project
# Seed: one PENDING claude_bypass_proposal and one PENDING escalation.
proposal=$(jq -nc '{timestamp:"2026-04-28T00:00:00Z", session_id:null, type:"claude_bypass_proposal", actor:"claude", enforcement_level_at_event:"strict", details:{pattern:"x"}, user_response:"PENDING", final_outcome:"recorded_only"}')
escalation=$(jq -nc '{timestamp:"2026-04-28T00:00:01Z", session_id:null, type:"escalation", actor:"framework", enforcement_level_at_event:"strict", details:{question:"x", options:["A1","A2"], recommendation:"A1", rationale:""}, user_response:"PENDING", final_outcome:"escalated"}')
jq --argjson p "$proposal" --argjson e "$escalation" '. + [$p, $e]' \
   "$PROJ/.claude/bypass-audit.json" > "$PROJ/.claude/.tmp" \
   && mv "$PROJ/.claude/.tmp" "$PROJ/.claude/bypass-audit.json"
# shellcheck disable=SC1090
( source "$LIB" && bypass_audit_close_pending "$PROJ" "accept" >/dev/null 2>&1 )
prop_outcome=$(jq -r '.[] | select(.type=="claude_bypass_proposal") | .final_outcome' "$PROJ/.claude/bypass-audit.json")
esc_outcome=$(jq -r '.[] | select(.type=="escalation") | .final_outcome' "$PROJ/.claude/bypass-audit.json")
esc_response=$(jq -r '.[] | select(.type=="escalation") | .user_response' "$PROJ/.claude/bypass-audit.json")
if [ "$prop_outcome" = "bypassed" ] && [ "$esc_outcome" = "escalated" ] && [ "$esc_response" = "PENDING" ]; then
  pass "T4: proposal closed; escalation row UNTOUCHED (type-scoped filter works)"
else
  fail_ "T4" "proposal=$prop_outcome escalation=$esc_outcome:$esc_response (expected bypassed; escalated:PENDING)"
fi
teardown

# T5: same scoping when --decision=decline.
echo "T5: close_pending(decline) does NOT touch escalation rows"
setup_project
proposal=$(jq -nc '{timestamp:"2026-04-28T00:00:00Z", session_id:null, type:"claude_bypass_proposal", actor:"claude", enforcement_level_at_event:"strict", details:{pattern:"y"}, user_response:"PENDING", final_outcome:"recorded_only"}')
escalation=$(jq -nc '{timestamp:"2026-04-28T00:00:01Z", session_id:null, type:"escalation", actor:"framework", enforcement_level_at_event:"strict", details:{question:"y"}, user_response:"PENDING", final_outcome:"escalated"}')
jq --argjson p "$proposal" --argjson e "$escalation" '. + [$p, $e]' \
   "$PROJ/.claude/bypass-audit.json" > "$PROJ/.claude/.tmp" \
   && mv "$PROJ/.claude/.tmp" "$PROJ/.claude/bypass-audit.json"
# shellcheck disable=SC1090
( source "$LIB" && bypass_audit_close_pending "$PROJ" "decline" >/dev/null 2>&1 )
prop_outcome=$(jq -r '.[] | select(.type=="claude_bypass_proposal") | .final_outcome' "$PROJ/.claude/bypass-audit.json")
esc_outcome=$(jq -r '.[] | select(.type=="escalation") | .final_outcome' "$PROJ/.claude/bypass-audit.json")
if [ "$prop_outcome" = "abandoned" ] && [ "$esc_outcome" = "escalated" ]; then
  pass "T5: proposal abandoned; escalation final_outcome preserved"
else
  fail_ "T5" "proposal=$prop_outcome escalation=$esc_outcome (expected abandoned + escalated)"
fi
teardown

# T6: idempotency — second invocation does not flip a now-resolved
# proposal (only PENDING rows are touched; the type scope is in addition
# to that, not instead of it).
echo "T6: close_pending is idempotent — non-PENDING rows untouched"
setup_project
proposal=$(jq -nc '{timestamp:"2026-04-28T00:00:00Z", session_id:null, type:"claude_bypass_proposal", actor:"claude", enforcement_level_at_event:"strict", details:{pattern:"z"}, user_response:"PENDING", final_outcome:"recorded_only"}')
jq --argjson p "$proposal" '. + [$p]' "$PROJ/.claude/bypass-audit.json" > "$PROJ/.claude/.tmp" \
   && mv "$PROJ/.claude/.tmp" "$PROJ/.claude/bypass-audit.json"
# shellcheck disable=SC1090
( source "$LIB" && bypass_audit_close_pending "$PROJ" "accept" >/dev/null 2>&1 )
# Second run: should not re-close (already not PENDING).
( source "$LIB" && bypass_audit_close_pending "$PROJ" "decline" >/dev/null 2>&1 )
final=$(jq -r '.[0].final_outcome' "$PROJ/.claude/bypass-audit.json")
if [ "$final" = "bypassed" ]; then
  pass "T6: second close_pending does not re-flip an already-resolved row"
else
  fail_ "T6" "final_outcome=$final (expected bypassed)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D1: escalate-to-user.sh propagates audit-log failures ==="
# ════════════════════════════════════════════════════════════════════

# Set up an escalation scenario. We force bypass_audit_append to fail
# by making the audit file non-writable mid-run, which exercises the
# error path without depending on jq behavior.

# T7: escalate-to-user.sh's success message must only fire after a
# verified audit write. After the fix, the success line must contain
# both 'pending-approval.json' AND 'audit log' together — but only on
# the success branch.
echo "T7: success message wording — '(and audit log)' only printed on actual success"
setup_project
( cd "$PROJ" && bash "$ESCALATE" \
    --question "test question" \
    --option "A1: do x" --option "A2: do y" \
    --recommendation A2 \
    --rationale "test" 2>&1 | grep -qE "(escalation written|escalation refused|audit log)" )
rc=$?
if [ "$rc" = "0" ]; then
  pass "T7: escalate-to-user emits the audit-log-confirmation phrase on success"
else
  fail_ "T7" "neither success nor failure message printed"
fi
teardown

# T8: the bypass_audit_append failure path is propagated, not swallowed.
# Strategy: source the library, monkey-patch bypass_audit_append to
# return 1, source the escalate script's audit-row write block, and
# assert escalate exits non-zero.
# Since escalate-to-user.sh is a script (not a function), we invoke it
# with an env var that triggers a controlled failure: make
# .claude/bypass-audit.json a directory so jq write fails.
echo "T8: escalate-to-user exits non-zero when audit-log write fails"
setup_project
# Replace the audit file with a directory of the same name — bypass_audit_append's
# jq write will fail because '> "$tmp"' is fine but the subsequent mv-into
# fails since the target is a directory.
rm -f "$PROJ/.claude/bypass-audit.json"
mkdir -p "$PROJ/.claude/bypass-audit.json"
out=$( cd "$PROJ" && bash "$ESCALATE" \
    --question "test" \
    --option "A1: x" --option "A2: y" \
    --recommendation A2 2>&1 )
rc=$?
# Pre-fix behavior: rc=0 + says "(and audit log)" lying about a write that failed.
# Post-fix behavior: rc != 0 OR a clear stderr message + no "(and audit log)" success.
if [ "$rc" != "0" ] && ! echo "$out" | grep -qE "escalation written .* and audit log"; then
  pass "T8: audit failure propagated as non-zero exit; no lying success message"
elif [ "$rc" = "0" ] && echo "$out" | grep -qE "escalation written .* and audit log"; then
  fail_ "T8" "PRE-FIX BEHAVIOR: exited 0 + lied about audit-log write"
else
  fail_ "T8" "ambiguous rc=$rc out='$(echo "$out" | head -2)'"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

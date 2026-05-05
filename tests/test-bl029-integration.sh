#!/usr/bin/env bash
# tests/test-bl029-integration.sh — end-to-end BL-029 pipeline.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Provision a fresh project. init.sh refuses to run from inside the
# framework repo, so cd to /tmp first.
TMP=$(mktemp -d); PROJ="$TMP/p"
( cd /tmp && bash "$REPO_ROOT/init.sh" --non-interactive \
    --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language javascript --track light --deployment personal \
    >/dev/null 2>&1 )

# T1: project has bypass-detector wired (PostToolUse + Stop).
if jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("bypass-detector"))' "$PROJ/.claude/settings.json" >/dev/null 2>&1 \
   && jq -e '.hooks.Stop[0].hooks[] | select(.command | contains("bypass-detector"))' "$PROJ/.claude/settings.json" >/dev/null 2>&1; then
  pass "T1: PostToolUse + Stop wiring"
else
  fail_ "T1" "wiring missing"
fi

# T2: simulate a Claude PostToolUse with bypass-shaped output → audit row.
( cd "$PROJ"
  echo "[]" > .claude/bypass-audit.json
  cat <<'EOF' | CLAUDE_PROJECT_DIR="$PROJ" bash scripts/hooks/bypass-detector.sh >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"alternatively, run git commit --no-verify"}}
EOF
)
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" = "1" ]; then pass "T2: claude_bypass_proposal row"; else fail_ "T2" "rows=$rows"; fi

# T3: pending-approval sentinel was written by the detector.
if [ -f "$PROJ/.claude/pending-approval.json" ] && \
   jq -e '.question | contains("I have read the proposal")' "$PROJ/.claude/pending-approval.json" >/dev/null 2>&1; then
  pass "T3: sentinel + confirmation phrase"
else
  fail_ "T3" "sentinel missing or malformed"
fi

# T4: escalate-to-user CLI works end-to-end (init a fresh git repo for it).
( cd "$PROJ" && git init -q 2>/dev/null && git config user.email t@t.l && git config user.name t
  rm -f .claude/pending-approval.json
  bash scripts/escalate-to-user.sh \
    --question "test escalation" \
    --option "A1: yes" --option "A2: no" \
    --recommendation A2 \
    --rationale "no rationale needed for the test" >/dev/null 2>&1 )
esc_rows=$(jq '[.[] | select(.type=="escalation")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$esc_rows" = "1" ]; then pass "T4: escalation audit row"; else fail_ "T4" "rows=$esc_rows"; fi

# T5: actor enum invariant — every row's actor is one of the documented values.
ACTORS=$(jq -r '[.[].actor] | unique | .[]' "$PROJ/.claude/bypass-audit.json")
ALL_OK=1
for a in $ACTORS; do
  case "$a" in claude|user_terminal|user_terminal_inferred|framework) ;; *) ALL_OK=0 ;; esac
done
if [ "$ALL_OK" = "1" ]; then pass "T5: actor enum"; else fail_ "T5" "unknown actor in $ACTORS"; fi

# T6: type enum invariant — every row's type is one of the documented values
# (per BL-030 spec § 6 schema).
TYPES=$(jq -r '[.[].type] | unique | .[]' "$PROJ/.claude/bypass-audit.json")
TYPE_OK=1
for t in $TYPES; do
  case "$t" in
    claude_bypass_proposal|terminal_commit_blocked|terminal_commit_passed|out_of_band_commit|enforcement_level_set|detector_error|escalation) ;;
    *) TYPE_OK=0 ;;
  esac
done
if [ "$TYPE_OK" = "1" ]; then pass "T6: type enum"; else fail_ "T6" "unknown type in $TYPES"; fi

rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

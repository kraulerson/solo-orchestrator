#!/usr/bin/env bash
# tests/test-bypass-detector-session-id.sh — regression for
# code-hooks-bypass-detector-3.
#
# The Claude Code hook envelope carries .session_id as a documented
# top-level field (per https://code.claude.com/docs/en/hooks). The
# bypass-detector previously read SESSION_ID from $CLAUDE_SESSION_ID, an
# undocumented env var that Claude Code does not in fact export — so
# every audit row was written with session_id="unknown", losing the
# session-correlation handle the W7 successor-handoff use case depends
# on.
#
# Fix: read .session_id from the envelope; fall back to
# ${CLAUDE_SESSION_ID:-unknown} only if the field is missing or empty.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/bypass-detector.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  cat > "$TMP/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  echo "[]" > "$TMP/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

# T1: envelope .session_id is propagated into the audit row.
echo "T1: envelope .session_id is written to the audit row"
setup
unset CLAUDE_SESSION_ID || true
cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","session_id":"sess-abc-123","tool_input":{"command":"x"},"tool_response":{"output":"use --no-verify"}}
EOF
sid=$(jq -r '.[0].session_id' "$TMP/.claude/bypass-audit.json")
if [ "$sid" = "sess-abc-123" ]; then
  pass "T1: session_id pulled from envelope"
else
  fail_ "T1" "expected 'sess-abc-123'; got '$sid'"
fi
teardown

# T2: envelope .session_id wins over $CLAUDE_SESSION_ID env var when both present.
echo "T2: envelope .session_id wins over CLAUDE_SESSION_ID env var"
setup
cat <<'EOF' | CLAUDE_SESSION_ID="env-fallback-id" CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","session_id":"envelope-wins","tool_input":{"command":"x"},"tool_response":{"output":"--no-verify"}}
EOF
sid=$(jq -r '.[0].session_id' "$TMP/.claude/bypass-audit.json")
if [ "$sid" = "envelope-wins" ]; then
  pass "T2: envelope wins"
else
  fail_ "T2" "expected 'envelope-wins'; got '$sid'"
fi
teardown

# T3: missing envelope .session_id falls back to $CLAUDE_SESSION_ID.
echo 'T3: missing envelope .session_id → $CLAUDE_SESSION_ID fallback'
setup
cat <<'EOF' | CLAUDE_SESSION_ID="env-fallback-id" CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"output":"--no-verify"}}
EOF
sid=$(jq -r '.[0].session_id' "$TMP/.claude/bypass-audit.json")
if [ "$sid" = "env-fallback-id" ]; then
  pass "T3: env var fallback used"
else
  fail_ "T3" "expected 'env-fallback-id'; got '$sid'"
fi
teardown

# T4: both missing → "unknown" final fallback.
echo "T4: both missing → 'unknown' sentinel"
setup
unset CLAUDE_SESSION_ID || true
cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"output":"--no-verify"}}
EOF
sid=$(jq -r '.[0].session_id' "$TMP/.claude/bypass-audit.json")
if [ "$sid" = "unknown" ]; then
  pass "T4: final fallback engaged"
else
  fail_ "T4" "expected 'unknown'; got '$sid'"
fi
teardown

# T5: empty envelope .session_id ("") still falls back to env var.
echo "T5: empty envelope .session_id → env var fallback"
setup
cat <<'EOF' | CLAUDE_SESSION_ID="env-fallback-when-empty" CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","session_id":"","tool_input":{"command":"x"},"tool_response":{"output":"--no-verify"}}
EOF
sid=$(jq -r '.[0].session_id' "$TMP/.claude/bypass-audit.json")
if [ "$sid" = "env-fallback-when-empty" ]; then
  pass "T5: empty-string envelope value treated as missing"
else
  fail_ "T5" "expected 'env-fallback-when-empty'; got '$sid'"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

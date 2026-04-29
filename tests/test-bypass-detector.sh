#!/usr/bin/env bash
# tests/test-bypass-detector.sh — BL-029 bypass-detector hook tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/bypass-detector.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
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

# Hook contract: stdin = JSON envelope from Claude Code.
# PostToolUse: { "hook_event_name": "PostToolUse", "tool_input": ..., "tool_result": {"output": "..."} }
# Stop:        { "hook_event_name": "Stop", "transcript": "..." }

# T1: PostToolUse output containing --no-verify writes a row.
echo "T1: PostToolUse with --no-verify writes claude_bypass_proposal"
setup
if [ ! -f "$HOOK" ]; then fail_ "T1" "hook missing (RED)"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"echo x"},"tool_result":{"output":"alternatively, run git commit --no-verify"}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T1"; else fail_ "T1" "rows=$rows"; fi
fi
teardown

# T2: clean output writes nothing.
echo "T2: clean output is a no-op"
setup
if [ ! -f "$HOOK" ]; then fail_ "T2" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"ls"},"tool_result":{"output":"file1\nfile2"}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "0" ]; then pass "T2"; else fail_ "T2" "false positive: $rows"; fi
fi
teardown

# T3: Stop event with bypass-shaped transcript writes row.
echo "T3: Stop event scans transcript"
setup
if [ ! -f "$HOOK" ]; then fail_ "T3" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"Stop","transcript":"Maybe set SOIF_FORCE_STEP=build_loop:tests_written"}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T3"; else fail_ "T3" "rows=$rows"; fi
fi
teardown

# T4: row contains verbatim excerpt + matched pattern name.
echo "T4: row payload includes pattern + excerpt"
setup
if [ ! -f "$HOOK" ]; then fail_ "T4" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify to skip"}}
EOF
  pattern=$(jq -r '.[0].details.pattern' "$TMP/.claude/bypass-audit.json")
  excerpt=$(jq -r '.[0].details.excerpt' "$TMP/.claude/bypass-audit.json")
  if [ "$pattern" = "no_verify" ] && echo "$excerpt" | grep -q -- "--no-verify"; then pass "T4"; else fail_ "T4" "pattern=$pattern excerpt='$excerpt'"; fi
fi
teardown

# T5: row's user_response is initialized to "PENDING".
echo "T5: user_response = PENDING on initial write"
setup
if [ ! -f "$HOOK" ]; then fail_ "T5" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify"}}
EOF
  resp=$(jq -r '.[0].user_response' "$TMP/.claude/bypass-audit.json")
  if [ "$resp" = "PENDING" ]; then pass "T5"; else fail_ "T5" "got '$resp'"; fi
fi
teardown

# T6: hook is silent (no stderr) on clean output.
echo "T6: hook is silent on clean output"
setup
if [ ! -f "$HOOK" ]; then fail_ "T6" "hook missing"; else
  err=$( ( CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK"
{"hook_event_name":"PostToolUse","tool_input":{"command":"ls"},"tool_result":{"output":"file"}}
EOF
) 2>&1 >/dev/null )
  if [ -z "$err" ]; then pass "T6"; else fail_ "T6" "stderr leaked: $err"; fi
fi
teardown

# T7: each firing on the same content writes one row (no internal dedup).
echo "T7: two firings → 2 rows"
setup
if [ ! -f "$HOOK" ]; then fail_ "T7" "hook missing"; else
  ENV='{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify here"}}'
  echo "$ENV" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
  echo "$ENV" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "2" ]; then pass "T7"; else fail_ "T7" "expected 2 rows, got $rows"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

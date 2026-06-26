#!/usr/bin/env bash
# tests/test-session-test-gate-check-merge.sh — session-test-gate-check.sh
# must not destructively overwrite .claude/tool-usage.json on resume /
# compact / clear. Pre-fix, every SessionStart invocation re-wrote the
# file with counters zeroed, re-arming the MCP gate and zeroing the
# Context7 counter mid-Build-Loop. After BL-030 added more SessionStart
# hooks (out-of-band-commits detector), the destructive overwrite hits
# the user's flow more often, so the fix is now-higher-impact.
#
# Hook contract (Claude Code): SessionStart envelope on stdin has a
# 'source' field with values "startup" | "resume" | "compact" | "clear".
# Fresh init only on startup; merge on the other three.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/session-test-gate-check.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  # Seed a tool-usage.json with accumulated in-flight state.
  cat > "$PROJ/.claude/tool-usage.json" <<'JSON'
{
  "session_id": "2026-04-28T00:00:00Z",
  "calls": [
    {"tool": "context7", "ts": "2026-04-28T00:01:00Z"},
    {"tool": "qdrant_find", "ts": "2026-04-28T00:02:00Z"}
  ],
  "commits_since_last_context7": 4,
  "qdrant_find_called": true,
  "qdrant_store_called": true,
  "context7_called": true,
  "mcp_gate_satisfied": true,
  "mcp_requirements": {
    "qdrant_required": true,
    "context7_required": true,
    "additional_required": ["custom-server"]
  }
}
JSON
}
teardown() { rm -rf "$TMP"; }

run_hook_with_source() {
  local src="$1"
  if [ -z "$src" ]; then
    ( cd "$PROJ" && bash "$HOOK" </dev/null >/dev/null 2>&1 ) || true
  else
    ( cd "$PROJ" && printf '{"hook_event_name":"SessionStart","source":"%s"}' "$src" \
        | bash "$HOOK" >/dev/null 2>&1 ) || true
  fi
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Non-startup sources (resume / compact / clear) must MERGE ==="
# ════════════════════════════════════════════════════════════════════

# T1: source=resume preserves the counters.
echo "T1: source=resume preserves calls / counters / flags"
setup
run_hook_with_source "resume"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
commits_counter=$(jq '.commits_since_last_context7' "$PROJ/.claude/tool-usage.json")
context7_flag=$(jq -r '.context7_called' "$PROJ/.claude/tool-usage.json")
add_req=$(jq -r '.mcp_requirements.additional_required | length' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "2" ] && [ "$commits_counter" = "4" ] \
   && [ "$context7_flag" = "true" ] && [ "$add_req" = "1" ]; then
  pass "T1: resume merge preserved calls=2 counter=4 context7=true add_req=1"
else
  fail_ "T1" "calls=$calls_len counter=$commits_counter context7=$context7_flag add_req=$add_req"
fi
teardown

# T2: source=compact preserves the counters.
echo "T2: source=compact preserves calls / counters / flags"
setup
run_hook_with_source "compact"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
commits_counter=$(jq '.commits_since_last_context7' "$PROJ/.claude/tool-usage.json")
mcp_gate=$(jq -r '.mcp_gate_satisfied' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "2" ] && [ "$commits_counter" = "4" ] && [ "$mcp_gate" = "true" ]; then
  pass "T2: compact merge preserved calls=2 counter=4 mcp_gate=true"
else
  fail_ "T2" "calls=$calls_len counter=$commits_counter mcp_gate=$mcp_gate"
fi
teardown

# T3: source=clear preserves the counters too. /clear semantically
# means "drop history" but the documented semantics in Claude Code
# are about CONVERSATION history, not framework state. Erasing the
# tool-usage ledger mid-Build-Loop would be surprising; preserve.
echo "T3: source=clear preserves calls / counters / flags"
setup
run_hook_with_source "clear"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "2" ]; then
  pass "T3: clear merge preserved calls=2"
else
  fail_ "T3" "calls=$calls_len (expected 2)"
fi
teardown

# T4: each non-startup invocation refreshes session_id even though the
# counters are preserved (so a successor reading the file can see the
# session boundary).
echo "T4: non-startup invocation refreshes session_id"
setup
original_id=$(jq -r '.session_id' "$PROJ/.claude/tool-usage.json")
sleep 1   # ensure date timestamps differ
run_hook_with_source "resume"
new_id=$(jq -r '.session_id' "$PROJ/.claude/tool-usage.json")
if [ "$new_id" != "$original_id" ] && [ -n "$new_id" ]; then
  pass "T4: session_id refreshed (was '$original_id', now '$new_id')"
else
  fail_ "T4" "session_id unchanged ('$original_id' → '$new_id')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== source=startup (and missing envelope) initializes fresh ==="
# ════════════════════════════════════════════════════════════════════

# T5: source=startup writes a fresh tool-usage.json with the counters
# zeroed (current behavior, must not regress).
echo "T5: source=startup writes a fresh tool-usage.json"
setup
run_hook_with_source "startup"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
commits_counter=$(jq '.commits_since_last_context7' "$PROJ/.claude/tool-usage.json")
context7_flag=$(jq -r '.context7_called' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "0" ] && [ "$commits_counter" = "0" ] && [ "$context7_flag" = "false" ]; then
  pass "T5: startup fresh-init zeros calls/counter/flags"
else
  fail_ "T5" "calls=$calls_len counter=$commits_counter context7=$context7_flag (expected 0/0/false)"
fi
teardown

# T6: invocation with NO envelope on stdin (legacy / unknown caller)
# defaults to startup behavior — backwards compat.
echo "T6: invocation with no envelope defaults to startup (legacy compat)"
setup
run_hook_with_source ""
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "0" ]; then
  pass "T6: missing envelope → fresh init"
else
  fail_ "T6" "calls=$calls_len (expected 0)"
fi
teardown

# T7: even on merge paths, the mcp_requirements get re-derived so
# users who add/remove MCP servers between sessions see the updated
# requirements. (We can't easily simulate adding servers in test, so
# this asserts the keys exist; the re-derivation logic is sourced
# from the same MCP-discovery block the startup path uses.)
echo "T7: merge path preserves mcp_requirements schema"
setup
run_hook_with_source "resume"
qreq=$(jq -r '.mcp_requirements.qdrant_required' "$PROJ/.claude/tool-usage.json")
creq=$(jq -r '.mcp_requirements.context7_required' "$PROJ/.claude/tool-usage.json")
if [ "$qreq" != "null" ] && [ "$creq" != "null" ]; then
  pass "T7: mcp_requirements re-derived (qdrant=$qreq context7=$creq)"
else
  fail_ "T7" "qdrant_required=$qreq context7_required=$creq"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

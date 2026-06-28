#!/usr/bin/env bash
# Solo Orchestrator — Stop hook advisory for Qdrant usage
# If Qdrant MCP is configured, reminds the agent to store session knowledge.
# Advisory only — does not block.
set -euo pipefail

# Check if Qdrant MCP is configured
QDRANT_CONFIGURED=false
if command -v jq &>/dev/null; then
  if [ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    QDRANT_CONFIGURED=true
  elif [ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1; then
    QDRANT_CONFIGURED=true
  fi
fi

if [ "$QDRANT_CONFIGURED" = false ]; then
  exit 0
fi

cat << 'EOF'
QDRANT REMINDER: Before ending this session, consider whether anything from this session should be stored in Qdrant for future retrieval. Good candidates:
- Architecture or design decisions made
- Non-obvious bugs resolved and their root causes
- Trade-off discussions with the Orchestrator
- Integration patterns established

Use qdrant-store with a clear, descriptive document. Skip if nothing significant was decided or discovered.
EOF

# Tool usage summary
TOOL_USAGE=".claude/tool-usage.json"
PHASE_STATE=".claude/phase-state.json"

if [ -f "$TOOL_USAGE" ] && command -v jq &>/dev/null; then
  CTX7_COUNT=$(jq '[.calls[] | select(.tool | contains("context7"))] | length' "$TOOL_USAGE" 2>/dev/null || echo "0")
  case "$CTX7_COUNT" in ''|*[!0-9]*) CTX7_COUNT=0 ;; esac
  QDRANT_FIND_COUNT=$(jq '[.calls[] | select(.tool | contains("qdrant")) | select(.tool | contains("find"))] | length' "$TOOL_USAGE" 2>/dev/null || echo "0")
  case "$QDRANT_FIND_COUNT" in ''|*[!0-9]*) QDRANT_FIND_COUNT=0 ;; esac
  QDRANT_STORE_COUNT=$(jq '[.calls[] | select(.tool | contains("qdrant")) | select(.tool | contains("store"))] | length' "$TOOL_USAGE" 2>/dev/null || echo "0")
  case "$QDRANT_STORE_COUNT" in ''|*[!0-9]*) QDRANT_STORE_COUNT=0 ;; esac

  echo ""
  echo "TOOL USAGE THIS SESSION: Context7: $CTX7_COUNT calls | Qdrant-find: $QDRANT_FIND_COUNT calls | Qdrant-store: $QDRANT_STORE_COUNT calls"

  # Phase 2 warnings
  CURRENT_PHASE="0"
  if [ -f "$PHASE_STATE" ]; then
    CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null)
  fi

  if [ "$CURRENT_PHASE" = "2" ]; then
    COMMITS_MADE=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
    QDRANT_STORED=$(jq -r '.qdrant_store_called // false' "$TOOL_USAGE" 2>/dev/null)

    if [ "$COMMITS_MADE" -gt 0 ] 2>/dev/null && [ "$QDRANT_STORED" = "false" ]; then
      echo ""
      echo "WARNING: You made source commits this session but stored nothing in Qdrant."
      echo "Before ending, store any architecture decisions, debugging breakthroughs, or integration patterns."
    fi

    if [ "$CTX7_COUNT" -eq 0 ] 2>/dev/null && [ "$COMMITS_MADE" -gt 0 ] 2>/dev/null; then
      echo ""
      echo "WARNING: Source code was committed but Context7 was never consulted."
      echo "If you used library APIs, check Context7 for current documentation next session."
    fi
  fi
fi

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

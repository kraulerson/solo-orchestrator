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
  # ── BL-233 WP-B: this summary counts OUTCOMES, not DECLARATIONS ──────────
  # It used to read `.calls | length` and the `*_called` flags, so a call that
  # FAILED was reported as a call that happened. After WP-A made the gate score
  # outcomes, this surface actively DISAGREED with the gate it sits beside —
  # the ledger already carried `.outcome` on every row and the `*_succeeded`
  # flags; only the reader was stale.
  #
  # A row written BEFORE WP-A carries no `.outcome`, and its absence is read as
  # success: the pre-WP-A tracker was registered on PostToolUse only, so the
  # rows it wrote are exactly the calls that fired without error. Defaulting
  # those to "failure" would invent failures that never happened.
  _ledger_count() {   # _ledger_count <select-expr> <outcome-expr>
    local n
    n=$(jq "[.calls[]? | select($1) | select($2)] | length" "$TOOL_USAGE" 2>/dev/null || echo "0")
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    printf '%s\n' "$n"
  }
  _OK_EXPR='(.outcome // "success") == "success"'
  _BAD_EXPR='(.outcome // "success") != "success"'
  _C7_SEL='(.tool | contains("context7"))'
  _QF_SEL='(.tool | contains("qdrant")) and (.tool | contains("find"))'
  _QS_SEL='(.tool | contains("qdrant")) and (.tool | contains("store"))'

  CTX7_COUNT=$(_ledger_count "$_C7_SEL" "$_OK_EXPR")
  QDRANT_FIND_COUNT=$(_ledger_count "$_QF_SEL" "$_OK_EXPR")
  QDRANT_STORE_COUNT=$(_ledger_count "$_QS_SEL" "$_OK_EXPR")
  CTX7_BAD=$(_ledger_count "$_C7_SEL" "$_BAD_EXPR")
  QDRANT_FIND_BAD=$(_ledger_count "$_QF_SEL" "$_BAD_EXPR")
  QDRANT_STORE_BAD=$(_ledger_count "$_QS_SEL" "$_BAD_EXPR")

  echo ""
  echo "TOOL USAGE THIS SESSION: Context7: $CTX7_COUNT calls | Qdrant-find: $QDRANT_FIND_COUNT calls | Qdrant-store: $QDRANT_STORE_COUNT calls"

  # A store that SUCCEEDED but whose DURABLE record could not be written. The
  # tracker increments this and, until now, nothing read it anywhere in the
  # repo — so its own comment, promising the operator would not "face a phase
  # gate that blocks for no visible reason", was unearned. This is that surface.
  STORE_RECORD_FAILED=$(jq -r '.qdrant_store_record_failed // 0' "$TOOL_USAGE" 2>/dev/null || echo 0)
  case "$STORE_RECORD_FAILED" in ''|*[!0-9]*) STORE_RECORD_FAILED=0 ;; esac
  if [ "$STORE_RECORD_FAILED" -gt 0 ]; then
    echo "  WARNING: $STORE_RECORD_FAILED successful qdrant-store(s) could NOT be written to .claude/process-state.json. The phase gate reads THAT record, not this session's ledger, so it will block as though nothing was stored. Make the file writable and store again."   # BL-233-WPB-RECORD-FAILED-VISIBLE
  fi

  # Report the failed round trips rather than omitting them. An absent failure
  # is indistinguishable from an idle session, and that ambiguity is what let a
  # dead Qdrant look healthy for weeks (`## BL-231:`).
  TOTAL_BAD=$((CTX7_BAD + QDRANT_FIND_BAD + QDRANT_STORE_BAD))
  if [ "$TOTAL_BAD" -gt 0 ]; then
    echo "  Those are SUCCESSFUL round trips. $TOTAL_BAD MCP call(s) failed or were interrupted this session (Context7: $CTX7_BAD, Qdrant-find: $QDRANT_FIND_BAD, Qdrant-store: $QDRANT_STORE_BAD) — a call that failed is not a call that happened."
  fi

  # Phase 2 warnings
  CURRENT_PHASE="0"
  if [ -f "$PHASE_STATE" ]; then
    CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null)
  fi

  if [ "$CURRENT_PHASE" = "2" ]; then
    COMMITS_MADE=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
    # `_called` is the DECLARATION ("a store tool was invoked"); `_succeeded` is
    # the outcome. A store that returned "All connection attempts failed" used
    # to silence this warning — the precise shape BL-233 exists to remove.
    QDRANT_STORED=$(jq -r '.qdrant_store_succeeded // false' "$TOOL_USAGE" 2>/dev/null)   # BL-233-WPB-OUTCOME

    if [ "$COMMITS_MADE" -gt 0 ] 2>/dev/null && [ "$QDRANT_STORED" = "false" ]; then
      echo ""
      echo "WARNING: You made source commits this session but stored nothing in Qdrant."
      echo "Before ending, store any architecture decisions, debugging breakthroughs, or integration patterns."
      echo "The phase gate BLOCKS on this: a phase with source commits and no successful qdrant-store does not advance (## BL-233: WP-B)."
    fi

    if [ "$CTX7_COUNT" -eq 0 ] 2>/dev/null && [ "$COMMITS_MADE" -gt 0 ] 2>/dev/null; then
      echo ""
      echo "WARNING: Source code was committed but Context7 was never consulted."
      echo "If you used library APIs, check Context7 for current documentation next session."
    fi
  fi
fi

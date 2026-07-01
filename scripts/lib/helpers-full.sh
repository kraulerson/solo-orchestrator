#!/usr/bin/env bash
# Solo Orchestrator — Full Shared Script Helpers (heavy surface)
#
# Loads helpers-core.sh (print_*, prompt_*, log_line, run_with_timeout,
# guard_not_in_framework) then adds the heavier helpers that only the
# long-running callers need:
#   - init_log / finalize_log (log-file rotation)
#   - is_context7_mcp_registered / is_qdrant_mcp_registered
#   - is_qdrant_container_running / register_qdrant_mcp
#
# Only long-running callers should source this file directly:
#   init.sh, upgrade-project.sh, intake-wizard.sh,
#   reconfigure-project.sh, verify-install.sh.
# Short-lived scripts (check-*.sh, validate.sh, test-gate.sh, ...)
# should source helpers-core.sh instead to skip the extra parse.
#
# Every existing caller that still does `source scripts/lib/helpers.sh`
# transitively lands here via the backwards-compat shim in helpers.sh.
#
# Idempotent-source guard.
if [ -n "${_SOIF_HELPERS_FULL_LOADED:-}" ]; then
  return 0
fi
_SOIF_HELPERS_FULL_LOADED=1

# Load the core helpers first (idempotent-guarded on its own).
# Fast-path dirname via parameter expansion (no subshell / no dirname fork).
_SOIF_HELPERS_FULL_DIR="${BASH_SOURCE[0]%/*}"
[ "$_SOIF_HELPERS_FULL_DIR" = "${BASH_SOURCE[0]}" ] && _SOIF_HELPERS_FULL_DIR="."
# shellcheck source=./helpers-core.sh
source "$_SOIF_HELPERS_FULL_DIR/helpers-core.sh"

# ── Logging ──────────────────────────────────────────────────────
# Call init_log() early in init.sh to enable file logging.
# All print_* functions in helpers-core.sh automatically log when
# LOG_FILE is set (they call log_line, which is a no-op until then).

init_log() {
  local log_dir="$1"
  mkdir -p "$log_dir"
  LOG_FILE="$log_dir/init-$(date +%Y%m%d-%H%M%S).log"
  {
    echo "═══════════════════════════════════════════════════════════"
    echo "Solo Orchestrator Init Log"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "OS: $(uname -s) $(uname -r) ($(uname -m))"
    echo "Shell: $BASH_VERSION"
    echo "User: $(whoami)@$(hostname)"
    echo "Working directory: $(pwd)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
  } > "$LOG_FILE"
}

finalize_log() {
  if [ -n "$LOG_FILE" ]; then
    {
      echo ""
      echo "═══════════════════════════════════════════════════════════"
      echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
      echo "Duration: ${SECONDS}s"
      echo "═══════════════════════════════════════════════════════════"
    } >> "$LOG_FILE"
    # Print log location (to both stdout and log)
    echo ""
    echo -e "${BLUE}[INFO]${NC} Init log saved to: $LOG_FILE"
  fi
}

# ── MCP Detection Helpers ────────────────────────────────────────
# Check both ~/.claude/settings.json and ~/.claude.json for MCP server registration.

is_context7_mcp_registered() {
  command -v jq &>/dev/null || return 1
  # Direct MCP registration in either user config file
  ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
  ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude.json" >/dev/null 2>&1) || \
  # Plugin-installed Context7 (surfaces as mcp__plugin_context7_context7__*; registered under .enabledPlugins, not .mcpServers)
  ([ -f "$HOME/.claude/settings.json" ] && jq -e '.enabledPlugins | to_entries[] | select(.key | test("^context7"; "i")) | select(.value == true)' "$HOME/.claude/settings.json" >/dev/null 2>&1)
}

is_qdrant_mcp_registered() {
  command -v jq &>/dev/null || return 1
  ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
  ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1)
}

# Check if a Qdrant container is running via docker ps (5s timeout, no docker info).
is_qdrant_container_running() {
  command -v docker &>/dev/null || return 1
  local _ps_out
  _ps_out=$(run_with_timeout 5 docker ps --format '{{.Names}}' 2>/dev/null) || return 1
  echo "$_ps_out" | grep -q "^qdrant$"
}

# Register Qdrant MCP with Claude Code (30s timeout).
# Usage: register_qdrant_mcp [collection_name]
register_qdrant_mcp() {
  local collection="${1:-claude-memory}"
  run_with_timeout 30 bash -c "echo y | claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$collection qdrant -- uvx --python 3.13 mcp-server-qdrant >/dev/null 2>&1"
}

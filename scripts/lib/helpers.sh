#!/usr/bin/env bash
# Solo Orchestrator — Shared Script Helpers
# Source this file from any script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/helpers.sh"
# Or from init.sh (repo root):
#   source "$SCRIPT_DIR/scripts/lib/helpers.sh"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# --- Print helpers ---
print_header() {
  local version="${1:-1.0.0}"
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║         Solo Orchestrator — Project Init v${version}          ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() { echo -e "${CYAN}[STEP]${NC} $1"; log_line "[STEP] $1"; }
print_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; log_line "  [OK] $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; log_line "[WARN] $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; log_line "[FAIL] $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; log_line "[INFO] $1"; }

# ── Logging ──────────────────────────────────────────────────────
# Call init_log() early in init.sh to enable file logging.
# All print_* functions automatically log when LOG_FILE is set.
LOG_FILE=""

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

# Strip ANSI escape codes and write to log file
log_line() {
  if [ -n "$LOG_FILE" ]; then
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
  fi
}

log_section() {
  if [ -n "$LOG_FILE" ]; then
    echo -e "\n── $1 ──────────────────────────────────" >> "$LOG_FILE"
  fi
}

# Run a command with a timeout (portable, no coreutils needed).
# Usage: run_with_timeout <seconds> <command...>
# Returns 0 on success, 1 on timeout or failure.
run_with_timeout() {
  local _rto_secs="$1"; shift
  "$@" &
  local _rto_pid=$!
  local _rto_elapsed=0
  while kill -0 "$_rto_pid" 2>/dev/null; do
    if [ "$_rto_elapsed" -ge "$_rto_secs" ]; then
      kill "$_rto_pid" 2>/dev/null || true
      wait "$_rto_pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
    _rto_elapsed=$((_rto_elapsed + 1))
  done
  wait "$_rto_pid" 2>/dev/null
}

# ── MCP Detection Helpers ────────────────────────────────────────
# Check both ~/.claude/settings.json and ~/.claude.json for MCP server registration.

is_context7_mcp_registered() {
  command -v jq &>/dev/null || return 1
  ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
  ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude.json" >/dev/null 2>&1)
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

# --- Prompt helpers ---

# Prompt for text input with optional default value.
# Usage: result=$(prompt_input "Your name" "default_value")
prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local result
  if [ -n "$default" ]; then
    read -rp "$(echo -e "${BOLD}$prompt${NC} [$default]: ")" result
    echo "${result:-$default}"
  else
    read -rp "$(echo -e "${BOLD}$prompt${NC}: ")" result
    echo "$result"
  fi
}

# Prompt for a numbered choice from a list of options.
# Usage: result=$(prompt_choice "Pick one:" "option1" "option2" "option3")
prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  echo -e "${BOLD}$prompt${NC}" >&2
  for i in "${!options[@]}"; do
    echo "  $((i+1)). ${options[$i]}" >&2
  done
  local choice
  while true; do
    read -rp "$(echo -e "${BOLD}Select [1-${#options[@]}]${NC}: ")" choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
      echo "${options[$((choice-1))]}"
      return
    fi
    echo "  Invalid choice. Enter a number between 1 and ${#options[@]}." >&2
  done
}

# Prompt user to install a missing tool. Returns 0 if installed, 1 if skipped.
# Usage: prompt_install "tool_name" "install_command" [needs_sudo]
prompt_install() {
  local tool_name="$1"
  local install_cmd="$2"
  local needs_sudo="${3:-false}"

  echo ""
  if [ "$needs_sudo" = true ]; then
    echo -e "  ${YELLOW}This requires administrator privileges (sudo).${NC}"
  fi
  echo -e "  Install command: ${CYAN}$install_cmd${NC}"
  read -rp "$(echo -e "  ${BOLD}Install $tool_name now? [Y/n]${NC}: ")" response
  if [[ "$response" =~ ^[Nn] ]]; then
    return 1
  fi

  if eval "$install_cmd"; then
    print_ok "$tool_name installed"
    return 0
  else
    print_warn "Installation failed. You can try manually: $install_cmd"
    return 1
  fi
}

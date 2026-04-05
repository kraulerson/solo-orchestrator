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
  [ -n "$LOG_FILE" ] && echo "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

log_section() {
  [ -n "$LOG_FILE" ] && echo -e "\n── $1 ──────────────────────────────────" >> "$LOG_FILE"
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

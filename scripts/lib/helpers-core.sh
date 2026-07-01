#!/usr/bin/env bash
# Solo Orchestrator — Core Shared Script Helpers (perf-optimized subset)
#
# This is the MINIMUM helper set every short-lived caller needs:
#   - Colors + print_* family
#   - LOG_FILE + log_line/log_section (print_* delegate to log_line)
#   - prompt_input / prompt_yes_no / prompt_choice / prompt_install
#   - run_with_timeout
#   - guard_not_in_framework
#
# The heavier "full" surface (init_log/finalize_log log-file rotation
# and MCP-detection helpers) lives in scripts/lib/helpers-full.sh.
#
# Idempotent-source guard: sourcing twice is a no-op (function defs
# from bash are naturally idempotent, but this short-circuits the
# color setup and re-parse when the same script is sourced multiple
# times via nested composition).
if [ -n "${_SOIF_HELPERS_CORE_LOADED:-}" ]; then
  return 0
fi
_SOIF_HELPERS_CORE_LOADED=1
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/helpers-core.sh"

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

# ── Logging (light) ──────────────────────────────────────────────
# print_* delegate to log_line, so log_line must live in core.
# init_log / finalize_log (which actually create + close the log
# file) are heavier and only used by init.sh — they live in
# helpers-full.sh. When a short-lived caller sources only
# helpers-core.sh, LOG_FILE stays empty and log_line is a no-op.
LOG_FILE=""

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

# --- Prompt helpers ---

# Prompt for text input with optional default value.
# Usage: result=$(prompt_input "Your name" "default_value")
#
# Non-interactive behavior (no TTY on stdin, CI=true, or
# SOIF_NONINTERACTIVE=true): emits a [WARN] to stderr and returns the
# default (or empty string if no default). This is the contract that
# scripts/lint-raw-read-prompt.sh enforces: never call `read -rp`
# outside this file, because doing so hangs unattended invocations.
prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local result

  if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then
    echo -e "${YELLOW}[WARN]${NC} Non-interactive context: prompt_input(\"$prompt\") returning default '$default' without blocking. Re-run interactively to override." >&2
    printf '%s' "$default"
    return 0
  fi

  if [ -n "$default" ]; then
    read -rp "$(echo -e "${BOLD}$prompt${NC} [$default]: ")" result
    echo "${result:-$default}"
  else
    read -rp "$(echo -e "${BOLD}$prompt${NC}: ")" result
    echo "$result"
  fi
}

# Prompt for yes/no confirmation, returning 0 (yes) or 1 (no).
# Usage: if prompt_yes_no "Proceed?" "Y"; then ... fi
#
# `default_answer` is "Y" or "N" — used ONLY when interactive AND the
# operator hits Enter without typing a response. In non-interactive
# contexts (no TTY, CI=true, SOIF_NONINTERACTIVE=true) this function
# ALWAYS returns N (1) regardless of `default_answer`. This is
# defense-in-depth: a caller that defaults to Y in interactive use
# (e.g. "[Y/n]" confirm prompts) must NEVER auto-Y a side-effectful
# action in CI just because the operator was absent. Mirrors the
# hard-N policy in scripts/check-phase-gate.sh::prompt_yes_no, which
# was introduced after the cycle-7 PR #87 unattended-install incident.
prompt_yes_no() {
  local message="$1"
  local default_answer="${2:-N}"

  if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then
    echo -e "${YELLOW}[WARN]${NC} Non-interactive context: skipping prompt (\"$message\") — defaulting to 'N' (caller default '$default_answer' ignored in non-interactive context)." >&2
    return 1
  fi

  local reply
  read -rp "$(echo -e "${BOLD}${message}${NC}: ")" reply
  if [ -z "$reply" ]; then
    case "$default_answer" in
      [Yy]*) return 0 ;;
      *)     return 1 ;;
    esac
  fi
  case "$reply" in
    [Nn]*) return 1 ;;
    *)     return 0 ;;
  esac
}

# Refuse to operate as a project if cwd OR an explicit target directory is
# the Solo Orchestrator framework repo itself. Every project-targeted script
# (init.sh, verify-install.sh, process-checklist.sh, upgrade-project.sh,
# intake-wizard.sh, pending-approval.sh, reconfigure-project.sh) must call
# this BEFORE any file writes.
#
# Usage:
#   guard_not_in_framework               # checks $(pwd) only (legacy / default)
#   guard_not_in_framework "$target_dir" # checks $(pwd) AND "$target_dir"
#
# The optional target-dir argument was added for security-audits-1
# (S3, 2026-04-26 audit sweep): init.sh accepts --project-dir=PATH and
# proceeds to write into PATH even if PATH is the framework repo. The
# cwd-only check missed that vector because the cwd could be a benign
# tempdir while --project-dir pointed at the framework. Callers that
# accept any "write into this dir" arg (init.sh, upgrade-project.sh, ...)
# MUST pass it as $1 so this guard can lint both surfaces.
#
# UAT 2026-04-25 fix (U-N + U-O): a UAT agent's cwd was the framework dir
# (instead of their tempdir), so verify-install.sh + indirectly CDF init
# scattered .claude/, .claude-backup/, gates/, hooks/, rules/, and
# APPROVAL_LOG.md into the framework root. None tracked, but contaminates
# the workspace and can sneak into commits.
#
# Detection signature: the framework has a top-level init.sh whose header
# contains "Solo Orchestrator — Project Initialization Script" — a string
# that's specific to this framework and won't appear in arbitrary projects'
# init.sh files. Also check for templates/generated/ to triple-confirm.
guard_not_in_framework() {
  local target="${1:-}"
  local cwd
  cwd="$(pwd)"

  # Helper: returns 0 if $1 looks like the framework repo root.
  _gnif_dir_is_framework() {
    local d="$1"
    [ -n "$d" ] || return 1
    [ -f "$d/init.sh" ] || return 1
    grep -q "Solo Orchestrator — Project Initialization Script" "$d/init.sh" 2>/dev/null || return 1
    [ -d "$d/templates/generated" ] || return 1
    return 0
  }

  _gnif_emit_refusal() {
    local where="$1"     # human label: "cwd" or "--project-dir"
    local detected="$2"  # the resolved path
    print_fail "Refusing to operate inside the Solo Orchestrator framework repo."
    echo "  Detected framework signature ($where): $detected" >&2
    echo "" >&2
    echo "  This script targets a project, not the framework itself." >&2
    echo "  Move to your project directory and re-run:" >&2
    echo "    cd /path/to/your-project" >&2
    echo "" >&2
    echo "  If this directory IS your project (i.e., you cloned solo-orchestrator" >&2
    echo "  AS a project), the framework is mis-installed — clone solo-orchestrator" >&2
    echo "  separately and run init.sh from inside an empty project directory." >&2
  }

  # 1. cwd check (preserves legacy behavior — callers that don't pass a target).
  if _gnif_dir_is_framework "$cwd"; then
    _gnif_emit_refusal "cwd" "$cwd"
    return 1
  fi

  # 2. target-dir check (security-audits-1). Only runs when caller supplies $1.
  if [ -n "$target" ] && _gnif_dir_is_framework "$target"; then
    _gnif_emit_refusal "--project-dir / target" "$target"
    return 1
  fi

  return 0
}

# Prompt for a numbered choice from a list of options.
# Usage: result=$(prompt_choice "Pick one:" "option1" "option2" "option3")
#
# UAT 2026-04-25 fix (agent 12): EOF guard. The original loop had no exit
# condition for stdin EOF — `read` returns non-zero on EOF, but the loop
# kept retrying and re-printing "Invalid choice", spinning the CPU and
# producing megabytes of output until killed. Affected ANY scripted
# invocation of init.sh (or any caller of prompt_choice) when canned
# answers were under-fed.
#
# Fix: detect read's non-zero return (EOF). On EOF, print a clear failure
# to stderr and return 1 (caller can decide whether to abort or default).
# Bonus: cap retries at 100 so even a malformed-but-non-EOF input stream
# doesn't burn forever.
prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  echo -e "${BOLD}$prompt${NC}" >&2
  for i in "${!options[@]}"; do
    echo "  $((i+1)). ${options[$i]}" >&2
  done
  local choice
  local retries=0
  local max_retries=100
  while [ "$retries" -lt "$max_retries" ]; do
    if ! read -rp "$(echo -e "${BOLD}Select [1-${#options[@]}]${NC}: ")" choice; then
      echo "" >&2
      echo "  prompt_choice: stdin closed (EOF) before a valid choice was supplied." >&2
      echo "  This usually means a scripted/heredoc invocation under-fed the prompt." >&2
      return 1
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
      echo "${options[$((choice-1))]}"
      return 0
    fi
    echo "  Invalid choice. Enter a number between 1 and ${#options[@]}." >&2
    retries=$((retries + 1))
  done
  echo "  prompt_choice: $max_retries invalid attempts; aborting to prevent loop." >&2
  return 1
}

# Prompt user to install a missing tool. Returns 0 if installed, 1 if skipped.
# Usage: prompt_install "tool_name" "install_command" [needs_sudo]
#
# Non-interactive behavior (no TTY on stdin, CI=true, or
# SOIF_NONINTERACTIVE=true): emits a [WARN] to stderr naming the
# missing tool + install command, and returns 1 (decline install)
# WITHOUT touching `eval`. Same defense-in-depth contract as
# prompt_yes_no — a caller in CI / piped invocation must NEVER
# auto-install a side-effectful command (e.g. `sudo apt install`,
# `sudo usermod -aG docker $USER`) just because the operator was
# absent. The PR-#96 adversarial verifier flagged this as the one
# remaining hole in the lint sweep: scripts/lib/helpers.sh is exempt
# from scripts/lint-raw-read-prompt.sh (correctly — the prompt
# helpers themselves must call `read -rp`), so runtime tests are the
# only safety net. See tests/test-prompt-install-noninteractive.sh.
prompt_install() {
  local tool_name="$1"
  local install_cmd="$2"
  local needs_sudo="${3:-false}"

  echo ""
  if [ "$needs_sudo" = true ]; then
    echo -e "  ${YELLOW}This requires administrator privileges (sudo).${NC}"
  fi
  echo -e "  Install command: ${CYAN}$install_cmd${NC}"

  if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then
    echo -e "${YELLOW}[WARN]${NC} Non-interactive context: skipping install of '$tool_name' — defaulting to 'N' (no install). Re-run interactively, or run the install manually: $install_cmd" >&2
    return 1
  fi

  local response
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

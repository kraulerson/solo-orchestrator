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

# Verify the calling process can create files at $1.
#
# Why this exists (BL-041 closer, 2026-06-30):
#   init.sh historically only learned that the target directory was
#   unwritable AFTER hundreds of lines of setup — by which point it had
#   already side-effected logs, mkdir'd partial scaffolds, and bailed in
#   the middle of an inconsistent install. Worse, the framework-repo
#   guard (guard_not_in_framework above) used to fire BEFORE any write-
#   permission check, so test harnesses running from inside the
#   framework checkout could not exercise the read-only failure path
#   at all (tests/edge-cases-pre-init.sh E8b was SKIPped).
#
#   This preflight is the operator-facing write-permission probe. It
#   MUST run before guard_not_in_framework so that:
#     • a real operator who points --project-dir at an unwritable
#       location gets a clear permission error (not the developer-
#       facing framework-repo refusal that is irrelevant to them);
#     • test harnesses running from any cwd can deliberately exercise
#       the read-only assertion without first being short-circuited
#       by the framework-repo guard.
#
# Contract:
#   • returns 0 if the target can be created/written; 1 otherwise.
#   • empty $1 returns 0 (caller has no resolvable target yet — interactive
#     flows resolve via prompts after this preflight; the project_dir-
#     existence check downstream handles that path).
#   • when target does not exist, the deepest existing ancestor is probed.
#   • emits a self-contained operator-facing error on failure (no caller
#     post-message needed).
preflight_target_writable() {
  local target="${1:-}"
  [ -n "$target" ] || return 0

  # Normalize to absolute (no realpath dependency — POSIX only).
  case "$target" in
    /*) ;;
    *)  target="$(pwd)/$target" ;;
  esac

  # Walk up to deepest existing ancestor. We need a path that exists
  # before we can answer "is it writable?".
  local probe="$target"
  while [ ! -e "$probe" ]; do
    local parent
    parent="$(dirname "$probe")"
    if [ "$parent" = "$probe" ]; then
      # Walked all the way to the filesystem root and nothing exists.
      # This is a different failure mode (path is in a non-existent
      # filesystem) — defer to the downstream existence check.
      return 0
    fi
    probe="$parent"
  done

  if [ ! -w "$probe" ]; then
    print_fail "Cannot create project directory: write permission denied."
    echo "  Target:           $target" >&2
    echo "  Unwritable path:  $probe" >&2
    echo "" >&2
    echo "  init.sh needs to write under the resolved target path, but" >&2
    echo "  the existing ancestor '$probe' is not writable by the" >&2
    echo "  current user ($(whoami))." >&2
    echo "" >&2
    echo "  Fix one of:" >&2
    echo "    - chmod the parent to grant write access (e.g. chmod u+w '$probe')" >&2
    echo "    - pick a different --project-dir under a writable parent" >&2
    echo "    - re-run as a user that owns the parent directory" >&2
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

# ── Multi-stage install runner (BL-069) ─────────────────────────────
# Split a ` && `-joined install string back into its ordered stages.
# The resolver (scripts/resolve-tools.sh, BL-033) joins an install_cmds
# array with EXACTLY ` && ` to produce the legacy singular install_cmd,
# so splitting on that delimiter recovers the original stage list. A
# legacy single-command string (no ` && `) yields exactly one stage —
# identical to the pre-BL-069 single-eval path. Result is returned in
# the global array SOIF_INSTALL_STAGES (bash-3.2 has no namerefs).
_soif_split_on_and() {
  local s="$1"
  SOIF_INSTALL_STAGES=()
  while :; do
    case "$s" in
      *" && "*)
        SOIF_INSTALL_STAGES+=( "${s%%" && "*}" )
        s="${s#*" && "}"
        ;;
      *)
        SOIF_INSTALL_STAGES+=( "$s" )
        break
        ;;
    esac
  done
}

# Execute an ordered list of install stages with per-stage fail-fast and
# per-stage diagnosis. This is the shared eval-path consumer of the
# resolver's `install_cmds` array (BL-033/BL-069): each argument after
# the tool name is one stage.
#
# Semantics (the BL-069 contract):
#   • Stages run IN ORDER, each eval'd IN THIS FUNCTION'S SHELL SCOPE,
#     so a variable assigned in stage N is visible to stage N+1 —
#     behaviorally identical to `eval "stage1 && stage2 && …"`, but with
#     a per-stage audit line and a per-stage exit-code check.
#   • FAIL-FAST: the first stage to exit non-zero STOPS the sequence.
#     Later stages do NOT run (matching `&&` short-circuit).
#   • RESUMABLE: side effects of already-completed stages are left in
#     place, so a repair re-run can pick up from the failing stage.
#   • Returns 0 iff every stage succeeded; otherwise returns the failing
#     stage's non-zero exit code.
#
# Usage: run_install_stages "<tool-name>" "<stage1>" ["<stage2>" …]
# A single stage (the legacy-string case) runs exactly as the old
# `eval "$install_cmd"` did — no per-stage banner, identical behavior.
run_install_stages() {
  local tool_name="$1"; shift
  local total=$#
  if [ "$total" -eq 0 ]; then
    return 0
  fi
  local idx=0 stage rc
  for stage in "$@"; do
    idx=$((idx + 1))
    if [ "$total" -gt 1 ]; then
      print_info "[$tool_name] install stage $idx/$total: $stage"
    fi
    eval "$stage"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      if [ "$total" -gt 1 ]; then
        print_warn "[$tool_name] install stage $idx/$total FAILED (exit $rc): $stage"
        print_warn "[$tool_name] earlier stages left their effects in place — re-run to resume from stage $idx."
      fi
      return "$rc"
    fi
  done
  return 0
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

  # BL-069: honor the resolver's multi-stage install_cmds shape. The
  # command may be a ` && `-joined sequence of stages (the legacy
  # singular form of an install_cmds array). Split it back into stages
  # and run each with per-stage fail-fast + diagnosis via the shared
  # runner. A single-command string is one stage — behaviorally
  # identical to the previous `eval "$install_cmd"`.
  _soif_split_on_and "$install_cmd"
  if run_install_stages "$tool_name" "${SOIF_INSTALL_STAGES[@]}"; then
    print_ok "$tool_name installed"
    return 0
  else
    print_warn "Installation failed. You can try manually: $install_cmd"
    return 1
  fi
}

# BL-095-STATE-READERS-BEGIN
# ONE parsing surface for top-level phase-state keys — nine files previously
# parsed `deployment`/`poc_mode` inline (three different grep-sed variants, a
# jq-with-grep-fallback dual, plain jq), and the duplication produced the
# BL-084 null/production mishandling class. Parsing is centralized HERE;
# per-gate PREDICATES (BL-084 bypass vs BL-086 license-tier semantics) stay
# per-gate on purpose.
#
# Null semantics (the load-bearing contract): JSON null, an absent key, and a
# missing file ALL yield the caller's default — jq maps null with `// ""`;
# the no-jq grep fallback only matches QUOTED values, so an unquoted `null`
# never matches and falls to the default identically.
#
# CONFORMING-INLINE SYNC SIBLINGS (deliberately NOT migrated — change these
# in step with this fence):
#   scripts/pre-commit-gate.sh    — hook surface; must not grow a sourcing
#                                   dependency (a missing lib would brick
#                                   commits, the BL-119 class). Uses the
#                                   canonical `jq -r '.key // ""'` form.
#   scripts/run-phase3-validation.sh — self-contained by design (harnesses
#                                   copy it standalone). Uses the quoted-value
#                                   grep form with identical null semantics.
#   scripts/verify-install.sh     — reads the NESTED `.answers.poc_mode`
#                                   shape from intake-progress.json; these
#                                   readers are top-level-only on purpose
#                                   (one key grammar), so that site stays
#                                   inline until a nested need recurs.

# soif_read_phase_state_key <state-file> <key> [default]
# Echoes the string value of a TOP-LEVEL key, or the default. Never errors.
soif_read_phase_state_key() {
  local soif_rsk_file="$1" soif_rsk_key="$2" soif_rsk_def="${3:-}"
  local soif_rsk_val=""
  if [ ! -f "$soif_rsk_file" ]; then
    printf '%s' "$soif_rsk_def"
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    soif_rsk_val=$(jq -r --arg k "$soif_rsk_key" '.[$k] // ""' "$soif_rsk_file" 2>/dev/null || echo "")
  else
    soif_rsk_val=$(grep -o "\"$soif_rsk_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$soif_rsk_file" 2>/dev/null | head -1 | sed 's/.*: *"//' | sed 's/"//' || echo "")
  fi
  if [ -n "$soif_rsk_val" ]; then
    printf '%s' "$soif_rsk_val"
  else
    printf '%s' "$soif_rsk_def"
  fi
  return 0
}

# soif_read_deployment <state-file> [default]
soif_read_deployment() { soif_read_phase_state_key "$1" "deployment" "${2:-}"; }

# soif_read_poc_mode <state-file> [default]
soif_read_poc_mode()   { soif_read_phase_state_key "$1" "poc_mode" "${2:-}"; }
# BL-095-STATE-READERS-END

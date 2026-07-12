#!/usr/bin/env bash
set -euo pipefail

# NOTE: This script requires bash. On Windows, run it inside WSL (Windows
# Subsystem for Linux) or Git Bash. Native PowerShell is not supported.

# Solo Orchestrator — Project Initialization Script
# https://github.com/kraulerson/solo-orchestrator
#
# Usage: ./init.sh [--dry-run] [--help]
# Creates a new Solo Orchestrator project with all framework documents,
# templates, and tooling configuration.
#
# Options:
#   --dry-run   Preview what will be installed and created without executing
#   --help, -h  Show usage information

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
DRY_RUN=false
OS_TYPE="$(uname -s)"

# BL-016: non-interactive mode state
NON_INTERACTIVE=false
VALIDATE_ONLY=false
CONFIG_FILE=""
# Per-input flags (empty = not supplied; collect_inputs_non_interactive() applies defaults or errors)
ARG_PROJECT=""
ARG_DESCRIPTION=""
ARG_PLATFORM=""
ARG_TRACK=""
ARG_DEPLOYMENT=""
ARG_GOV_MODE=""
ARG_LANGUAGE=""
ARG_PROJECT_DIR=""
ARG_GIT_HOST=""
ARG_VISIBILITY=""
ARG_REMOTE_URL=""
ARG_BRANCH_PROTECTION_ATTESTED=false
# BL-032: proactive attestation for gitlab.com Free org-mode approvals
# API (Premium-only). When set, init.sh exports SOLO_APPROVALS_ATTESTED=1
# to host_configure_protection, which skips the approvals PUT and emits
# a WARN with the operator-actionable manual-setup hint. Post-success
# init.sh records the corresponding attestation in process-state.json
# with reason `gitlab_free_tier_approvals` (honored by check-gate.sh +
# check-phase-gate.sh, mirroring the `github_free_tier` reactive path).
ARG_APPROVALS_ATTESTED=false
ARG_ALLOW_EXISTING_DIR=false
ARG_NO_REMOTE_CREATION=false
# BL-084: tier-aware escape hatches for a FAILED initial push on the
# bring-your-own-host (--git-host other) path. These are honored ONLY for
# track=light (Personal / POC-Personal). For track=standard|full
# (POC-Sponsored / Production) a failed push is a NON-bypassable hard
# failure and these flags have no effect. Absent a flag, a light-tier push
# failure is still a real failure (default = no silent success).
#   --accept-local-only-risk : operator accepts keeping the project LOCAL
#                              (no remote) and the attendant data-loss risk.
#   --defer-remote-push      : operator will push manually later; the
#                              Phase 1→2 gate WILL block until the push is
#                              verified against the remote.
ARG_ACCEPT_LOCAL_ONLY_RISK=false
ARG_DEFER_REMOTE_PUSH=false
# BL-030: enforcement-level flags (non-interactive). Default empty so
# resolution defers to the choosability check after deployment+poc_mode.
ARG_ENFORCEMENT_LEVEL=""
ARG_CONFIRM_PITFALLS=false
# Resolved variables produced by either input path (consumed by downstream functions)
GOV_MODE=""
GIT_HOST=""
VISIBILITY=""
REMOTE_URL=""
BRANCH_PROTECTION_ATTESTED=false
APPROVALS_ATTESTED=false
ALLOW_EXISTING_DIR=false
NO_REMOTE_CREATION=false
# BL-084: resolved forms of the tier-aware push-failure escape hatches.
ACCEPT_LOCAL_ONLY_RISK=false
DEFER_REMOTE_PUSH=false
ENFORCEMENT_LEVEL=""
CONFIRM_PITFALLS=0

source "$SCRIPT_DIR/scripts/lib/helpers.sh"
# BL-099: shared git-hook body generators (fallback pre-commit + commit-msg TDD
# gate + language→test-pattern table). Sourced here so install_precommit_hook /
# install_tdd_commit_msg_hook and scripts/upgrade-project.sh --sync-framework
# emit byte-identical hooks from ONE source of truth.
source "$SCRIPT_DIR/scripts/lib/hook-templates.sh"
# BL-109-CURRENCY: currency-inventory (Layer 0) writer/reader helpers. Sourced
# here so the render sites (generate_claude_md / PROJECT_INTAKE / the A2 template
# copies) can stash render bases into $SOIF_CURRENCY_RENDERBASE_FILE, and
# prepare_initial_state_for_commit can stamp the whole `currency` block into
# .claude/manifest.json at birth. The lib transitively sources
# scaffold-shipped-set.sh (mechanical shipped-set parsers) if not already loaded.
source "$SCRIPT_DIR/scripts/lib/currency-manifest.sh"

# ────────────────────────────────────────────────────────────────────
# BL-064: init-failure tracking (silent-success defect class)
# ────────────────────────────────────────────────────────────────────
# Adversarial certainty re-walk (re-walker-2, scenario
# `fresh-org-sponsored-poc-standard-web-ts`) surfaced that init.sh used
# to exit 0 with the "Setup Complete" banner even after emitting a
# [FAIL] line for branch protection (or push, or any other
# create_and_protect_remote step that returns non-zero). Operators who
# only check the exit code (or scan for the banner) miss the gap —
# same defect class as PR #105's intake-wizard.sh:2028 silent success.
#
# Contract (closes BL-064):
#   • create_and_protect_remote's failure paths (every print_fail
#     inside that function feeds `return 1`, which the outer caller
#     records via `record_init_failure`).
#   • print_init_failures_summary prints a "Setup INCOMPLETE" banner
#     with a re-listing of every tracked failure when INIT_FAILURES is
#     non-empty.
#   • main() ends with: if [ ${#INIT_FAILURES[@]} -gt 0 ]; then
#     print_init_failures_summary; return 2; fi.  The non-zero return
#     propagates as init.sh's exit status.
#
# Structural backstop: scripts/lint-fail-emit-exit-status.sh enforces
# that every print_fail in init.sh either terminates (exit/return 1
# inline or within 2 lines) or carries a `# lint-fail-emit-exit-status:
# allow <reason>` annotation justifying continuation. See its header
# for the regex + allowlist contract.
INIT_FAILURES=()
record_init_failure() {
  INIT_FAILURES+=("$1")
}

# BL-084: best-effort "who acknowledged this" identity for the recorded
# push-failure escape hatches. Prefers `git config user.name`/`user.email`,
# falls back to whoami@hostname. Mirrors check-phase-gate.sh::_cpg_gate_actor
# so the two audit surfaces read the same way.
_init_actor() {
  local name email host
  name=$(git config user.name 2>/dev/null || echo "")
  email=$(git config user.email 2>/dev/null || echo "")
  if [ -n "$name" ] && [ -n "$email" ]; then
    printf '%s <%s>' "$name" "$email"
  elif [ -n "$name" ]; then
    printf '%s' "$name"
  else
    host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "localhost")
    printf '%s@%s' "$(whoami 2>/dev/null || echo unknown)" "$host"
  fi
}

# BL-084: record an EXPLICIT, operator-acknowledged escape from a FAILED
# initial push on the bring-your-own-host ('other') path. Only ever called
# for track=light (Personal / POC-Personal). Writes a structured record to
# .claude/process-state.json::phase2_init.remote.<key> so the choice is on
# the record — never a silent pass — and the Phase 1→2 gate can read it.
#   <key> ∈ { local_only_acknowledged, push_deferred_acknowledged }
# Atomic tmp-file + mv rename (same idiom as the branch-protection
# attestation write below; BL-071 atomic-finalize lineage). bash-3.2-safe.
_record_remote_ack() {
  local key="$1" reason="$2"
  local by today
  by="$(_init_actor)"
  today="$(date -u +%FT%TZ)"
  mkdir -p .claude
  if [ ! -f .claude/process-state.json ]; then
    echo '{"phase2_init":{"steps_completed":[],"attestations":{}}}' > .claude/process-state.json
  fi
  jq --arg k "$key" --arg reason "$reason" --arg date "$today" --arg by "$by" \
     '.phase2_init.remote = ((.phase2_init.remote // {}) + {($k): {risk_accepted: true, reason: $reason, date: $date, by: $by}})' \
     .claude/process-state.json > .claude/process-state.json.tmp \
     && mv .claude/process-state.json.tmp .claude/process-state.json
}

# BL-084 (verifier follow-up): custom-host push-failure escape-hatch
# eligibility keys on the ACTUAL project TIER — NOT on `track`. `track=light`
# can be set (non-interactively) on a POC-Sponsored or Production project
# (the interactive force-upgrade at init.sh:561-573 does NOT run in
# --non-interactive mode), so trusting `track` alone would let a
# sponsored/production project bypass a failed push with NO code uploaded —
# a silent-success hole exactly like the one BL-084 exists to prevent.
#
# Tier is derived from `deployment` + `poc_mode` as init.sh / intake-wizard
# write them. Valid combos: deployment=personal → poc_mode ∈ {"", private_poc};
# deployment=organizational → poc_mode ∈ {"", sponsored_poc} (sponsored_poc
# NEVER pairs with personal). So:
#   BYPASSABLE     (Personal / POC-Personal): deployment=personal
#                  AND poc_mode≠sponsored_poc.
#   NON-bypassable (POC-Sponsored / Production): deployment=organizational
#                  OR  poc_mode=sponsored_poc.
# scripts/check-phase-gate.sh's Phase 1→2 push gate computes the IDENTICAL
# predicate from phase-state.json::{deployment,poc_mode} so the two enforcement
# points cannot disagree (a gate can't be fooled by track=light either).
# Returns 0 (success) iff BYPASSABLE. Mutation-proof surface: `# BL-084-TIER-KEY`.
_bl084_tier_bypassable() {  # BL-084-TIER-KEY
  if [ "${DEPLOYMENT:-}" = "organizational" ] || [ "${POC_MODE:-}" = "sponsored_poc" ]; then
    return 1
  fi
  return 0
}

# Audit specs-plans-init-intake-noninteractive-2 (2026-06): the dynamic
# platform discovery used by the interactive flow at collect_inputs() and
# the case-statement used by the non-interactive validator had drifted
# apart. The interactive flow scanned docs/platform-modules + release
# pipelines and appended 'other'; the non-interactive flow hardcoded
# {desktop|mobile|web|mcp_server} and rejected 'other'. The helper below
# is the single source of truth — used by both flows and exported for
# any caller that wants to enumerate or validate platforms.
get_available_platforms() {
  # BL-051: process-local memoization. This helper globs
  # docs/platform-modules/*.md + templates/pipelines/release/github/*.yml
  # on every call; a single non-interactive validate invocation calls it
  # more than once (--platform validation at collect_inputs_non_interactive
  # + the required-arg error message). The platform set is fixed for the
  # lifetime of the process (on-disk layout doesn't change mid-run), so the
  # first call caches the result in a guard var + a plain string and later
  # calls return it verbatim — preserving exact output and ordering.
  # bash-3.2-safe: NO associative arrays (macOS ships bash 3.2 as /bin/bash),
  # mirroring the guard-var + delimited-string pattern in
  # scripts/lint-tests-registered.sh.
  if [ "${_GET_AVAILABLE_PLATFORMS_CACHED:-0}" = "1" ]; then
    echo "$_GET_AVAILABLE_PLATFORMS_CACHE"
    return 0
  fi
  local seen=""
  for f in "$SCRIPT_DIR/docs/platform-modules/"*.md; do
    [ -f "$f" ] || continue
    local pname
    pname=$(basename "$f" .md)
    if [[ ! " $seen " == *" $pname "* ]]; then
      seen="$seen $pname"
    fi
  done
  for f in "$SCRIPT_DIR/templates/pipelines/release/github/"*.yml; do
    [ -f "$f" ] || continue
    local pname
    pname=$(basename "$f" .yml)
    if [[ ! " $seen " == *" $pname "* ]]; then
      seen="$seen $pname"
    fi
  done
  # 'other' is always available as a fallback for platforms not in the
  # canonical set (matches the interactive flow).
  if [[ ! " $seen " == *" other "* ]]; then
    seen="$seen other"
  fi
  _GET_AVAILABLE_PLATFORMS_CACHE="$seen"
  _GET_AVAILABLE_PLATFORMS_CACHED=1
  echo "$seen"
}

# ================================================================
# PHASE 1: Prerequisites Check
# ================================================================
check_prerequisites() {
  print_step "Checking prerequisites..."
  local os_type="$OS_TYPE"
  local missing_required=()

  # In dry-run mode, skip all interactive install prompts — just report status
  local interactive=true
  [ "$DRY_RUN" = true ] && interactive=false

  # Minimum Node.js major version — keep in sync with templates/tool-matrix/common.json
  local NODE_MIN_MAJOR=18

  # --- Git (required) ---
  if command -v git &>/dev/null; then
    print_ok "Git $(git --version | awk '{print $3}')"
  else
    print_fail "Git not found"  # lint-fail-emit-exit-status: allow check_prerequisites accumulator pattern — missing tools are collected into missing_required[] and a single `exit 1` at the function tail (see line near print_fail "Missing required prerequisites" below) fires only when at least one required tool is absent; interactive install path may install the tool before that check, in which case the [FAIL] line is a status diagnostic only.
    local git_installed=false
    if [ "$interactive" = true ]; then
      if [ "$os_type" = "Darwin" ]; then
        if command -v brew &>/dev/null; then
          prompt_install "Git" "brew install git" && git_installed=true
        else
          echo "  Install with: xcode-select --install (includes Git)"
          echo "  Or install Homebrew first: https://brew.sh"
        fi
      elif [ "$os_type" = "Linux" ]; then
        if command -v apt &>/dev/null; then
          prompt_install "Git" "sudo apt install -y git" true && git_installed=true
        elif command -v dnf &>/dev/null; then
          prompt_install "Git" "sudo dnf install -y git" true && git_installed=true
        elif command -v pacman &>/dev/null; then
          prompt_install "Git" "sudo pacman -S --noconfirm git" true && git_installed=true
        else
          echo "  Install with your distribution's package manager (e.g., sudo apt install git)"
        fi
      fi
    fi
    if [ "$git_installed" = false ]; then
      missing_required+=("git")
    fi
  fi

  # --- Node.js (required for JS/TS, recommended for others) ---
  if command -v node &>/dev/null; then
    local node_version
    node_version=$(node --version | sed 's/v//')
    local node_major
    node_major=$(echo "$node_version" | cut -d. -f1)
    if [ "$node_major" -ge "$NODE_MIN_MAJOR" ]; then
      print_ok "Node.js $node_version"
    else
      print_warn "Node.js $node_version ($NODE_MIN_MAJOR+ recommended)"
    fi
  else
    print_warn "Node.js not found (used by Snyk, license-checker, and JS/TS projects)"
    if [ "$interactive" = true ]; then
      if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
        prompt_install "Node.js LTS" "brew install node"
      elif [ "$os_type" = "Linux" ]; then
        if command -v apt &>/dev/null; then
          prompt_install "Node.js" "sudo apt install -y nodejs npm" true
        elif command -v dnf &>/dev/null; then
          prompt_install "Node.js" "sudo dnf install -y nodejs npm" true
        elif command -v pacman &>/dev/null; then
          prompt_install "Node.js" "sudo pacman -S --noconfirm nodejs npm" true
        else
          echo "  Install Node.js 18+: https://nodejs.org/"
        fi
      fi
    fi
  fi

  # --- jq (required by Development Guardrails) ---
  if command -v jq &>/dev/null; then
    print_ok "jq $(jq --version 2>/dev/null)"
  else
    print_warn "jq not found (required by Development Guardrails for Claude Code for JSON operations)"
    if [ "$interactive" = true ]; then
      if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
        prompt_install "jq" "brew install jq"
      elif [ "$os_type" = "Linux" ]; then
        if command -v apt &>/dev/null; then
          prompt_install "jq" "sudo apt install -y jq" true
        elif command -v dnf &>/dev/null; then
          prompt_install "jq" "sudo dnf install -y jq" true
        elif command -v pacman &>/dev/null; then
          prompt_install "jq" "sudo pacman -S --noconfirm jq" true
        else
          echo "  Install manually: https://jqlang.github.io/jq/download/"
        fi
      fi
    fi
  fi

  # --- Docker (optional) ---
  if command -v docker &>/dev/null; then
    print_ok "Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    # Check if daemon is running; if Colima is installed, check that too
    if ! docker info &>/dev/null; then
      if command -v colima &>/dev/null; then
        print_info "Docker daemon not running. Starting Colima..."
        colima start 2>/dev/null && print_ok "Colima started" || print_warn "Failed to start Colima. Run: colima start"
      elif [ "$os_type" = "Darwin" ]; then
        print_info "Docker daemon not running. Starting Docker Desktop..."
        open -a Docker 2>/dev/null
        for _try in 1 2 3 4 5; do
          docker info &>/dev/null && break
          sleep 3
        done
        docker info &>/dev/null && print_ok "Docker daemon running" || print_warn "Docker Desktop is starting — it may take a moment"
      fi
    fi
  else
    print_warn "Docker not found (optional — needed for Qdrant semantic memory and OWASP ZAP DAST scanning)"
    if [ "$interactive" = true ]; then
      if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
        echo ""
        echo -e "  ${BOLD}Docker options for macOS:${NC}"
        echo "    1. Colima — Lightweight, headless, runs as a background service. No license required."
        echo "    2. Docker Desktop — Full GUI app. Free for personal use and small businesses."
        echo ""
        local docker_choice
        docker_choice=$(prompt_choice "Install Docker via:" "Colima (recommended)" "Docker Desktop" "Skip")
        case "$docker_choice" in
          "Colima"*)
            if prompt_install "Colima + Docker CLI" "brew install colima docker docker-compose"; then
              print_info "Starting Colima..."
              colima start --cpu 2 --memory 4 2>&1 && print_ok "Colima running"
              # Enable auto-start on boot
              brew services start colima 2>/dev/null && print_ok "Colima set to auto-start on boot"
            fi
            ;;
          "Docker Desktop"*)
            if prompt_install "Docker Desktop" "brew install --cask docker"; then
              open -a Docker
              print_info "Waiting for Docker Desktop to start..."
              for _try in 1 2 3 4 5; do
                docker info &>/dev/null && break
                sleep 3
              done
            fi
            ;;
          "Skip"*)
            print_info "Skipping Docker installation"
            ;;
        esac
      elif [ "$os_type" = "Linux" ]; then
        if command -v apt &>/dev/null; then
          prompt_install "Docker" "sudo apt install -y docker.io && sudo systemctl enable docker && sudo systemctl start docker && sudo usermod -aG docker $USER" true
        elif command -v dnf &>/dev/null; then
          prompt_install "Docker" "sudo dnf install -y docker && sudo systemctl enable docker && sudo systemctl start docker && sudo usermod -aG docker $USER" true
        elif command -v pacman &>/dev/null; then
          prompt_install "Docker" "sudo pacman -S --noconfirm docker && sudo systemctl enable docker && sudo systemctl start docker && sudo usermod -aG docker $USER" true
        else
          echo "  Install manually: https://docs.docker.com/engine/install/"
        fi
        if command -v docker &>/dev/null; then
          print_info "You may need to log out and back in for the docker group to take effect."
        fi
      fi
    fi
  fi

  # --- GPG (optional) ---
  if command -v gpg &>/dev/null; then
    print_ok "GPG available (commit signing)"
  else
    print_warn "GPG not found (optional — used for commit signing)"
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      echo "  Install with: brew install gnupg"
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        echo "  Install with: sudo apt install -y gnupg"
      elif command -v dnf &>/dev/null; then
        echo "  Install with: sudo dnf install -y gnupg2"
      elif command -v pacman &>/dev/null; then
        echo "  Install with: sudo pacman -S --noconfirm gnupg"
      fi
    fi
  fi

  # --- Development Guardrails for Claude Code ---
  if [ -d "$HOME/.claude-dev-framework/.git" ] && [ -f "$HOME/.claude-dev-framework/scripts/init.sh" ]; then
    print_ok "Development Guardrails for Claude Code installed"
  else
    print_info "Development Guardrails for Claude Code will be installed during project creation"
  fi

  # --- Claude Code Superpowers plugin (recommended) ---
  if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
    local sp_installed
    sp_installed=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
    if [ "$sp_installed" = "true" ]; then
      print_ok "Superpowers plugin installed"
    else
      print_warn "Superpowers plugin not found (recommended — agentic skills for development)"
      echo "  Install: Run claude → /plugins → search 'superpowers' → install"
    fi
  else
    print_info "Superpowers plugin: cannot check (no Claude settings or jq missing)"
  fi

  # --- Context7 MCP (recommended for up-to-date library docs) ---
  if is_context7_mcp_registered; then
    print_ok "Context7 MCP server configured"
  else
    print_warn "Context7 MCP not configured (recommended — up-to-date library documentation)"
    echo "  Register: claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest"
  fi

  # --- Qdrant MCP (recommended for persistent semantic memory) ---
  if is_qdrant_mcp_registered; then
    print_ok "Qdrant MCP server configured"
  elif is_qdrant_container_running; then
    print_ok "Qdrant container already running"
    if ! command -v uvx &>/dev/null; then
      print_warn "uv/uvx not found — needed to run mcp-server-qdrant"
      echo "  Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
    fi
  else
    print_info "Qdrant MCP not configured yet (will be set up during tool resolution)"
  fi

  if [ ${#missing_required[@]} -gt 0 ]; then
    echo ""
    print_fail "Missing required prerequisites: ${missing_required[*]}"
    echo "  Install them and re-run init.sh."
    exit 1
  fi

  echo ""
  print_ok "All required prerequisites met."
}

# ================================================================
# PHASE 2: Collect Project Information
# ================================================================
collect_project_info() {
  print_step "Project setup..."
  echo ""

  PROJECT_NAME=$(prompt_input "Project name (lowercase, no spaces)" "")
  PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  PROJECT_DESCRIPTION=$(prompt_input "One-sentence description" "")

  # Auto-discover available platforms from platform modules and release pipelines
  local available_platforms=()
  local seen_platforms=""
  # Scan platform modules
  for f in "$SCRIPT_DIR/docs/platform-modules/"*.md; do
    [ -f "$f" ] || continue
    local pname
    pname=$(basename "$f" .md)
    if [[ ! " $seen_platforms " == *" $pname "* ]]; then
      available_platforms+=("$pname")
      seen_platforms="$seen_platforms $pname"
    fi
  done
  # Scan release pipelines for platforms not already found (GitHub subfolder is
  # canonical — all hosts ship the same platform set per spec 2026-04-21).
  for f in "$SCRIPT_DIR/templates/pipelines/release/github/"*.yml; do
    [ -f "$f" ] || continue
    local pname
    pname=$(basename "$f" .yml)
    if [[ ! " $seen_platforms " == *" $pname "* ]]; then
      available_platforms+=("$pname")
      seen_platforms="$seen_platforms $pname"
    fi
  done
  # Always include "other" as a fallback
  available_platforms+=("other")

  PLATFORM=$(prompt_choice "Platform type:" "${available_platforms[@]}")
  PLATFORM="${PLATFORM#"${PLATFORM%%[![:space:]]*}"}"

  echo ""
  echo -e "  ${BOLD}Project Tracks:${NC}"
  echo "    Light    — Internal tools, prototypes, POCs. <10 users. Minimal governance."
  echo "    Standard — External users, moderate complexity. Market audit, user testing."
  echo "    Full     — Enterprise buyers, sensitive data. Pen testing, legal review mandatory."
  echo ""
  TRACK=$(prompt_choice "Project track:" "light" "standard" "full")
  TRACK="${TRACK#"${TRACK%%[![:space:]]*}"}"

  echo ""
  echo -e "  ${BOLD}Deployment Context:${NC}"
  echo "    Personal       — Your own projects. No organizational governance required."
  echo "    Organizational — Company/team projects. Governance pre-flight required."
  echo ""
  DEPLOYMENT=$(prompt_choice "Personal or organizational?" "personal" "organizational")

  # Warn on unusual combinations
  if [ "$TRACK" = "full" ] && [ "$DEPLOYMENT" = "personal" ]; then
    echo ""
    print_warn "Full track is designed for organizational projects with enterprise compliance."
    print_warn "For personal projects, Standard track provides external-user readiness without"
    print_warn "enterprise overhead (pen testing, legal review). You can upgrade later."
    local confirm_full
    read -rp "$(echo -e "  ${BOLD}Continue with Full track? [y/N]${NC}: ")" confirm_full # lint-raw-read-prompt: allow init.sh interactive-only wizard (NON_INTERACTIVE=true path bypasses collect_inputs_interactive entirely; see init.sh:3532)
    if [[ ! "$confirm_full" =~ ^[Yy] ]]; then
      TRACK=$(prompt_choice "Project track:" "light" "standard" "full")
      TRACK="${TRACK#"${TRACK%%[![:space:]]*}"}"
    fi
  fi

  # Audit code-init-sh-4 + tier-crosscheck-2 (2026-06): move the POC
  # prompt out from under the organizational guard. Per baseline §2.5,
  # Private POC is always personal and Sponsored POC is always
  # organizational, so each deployment offers a different two-option
  # dialog; both still produce a POC_MODE value (or "") for downstream
  # consumers.
  POC_MODE=""
  echo ""
  echo -e "  ${BOLD}Governance Mode:${NC}"
  echo "    Production Build — All governance approvals required before starting."
  if [ "$DEPLOYMENT" = "organizational" ]; then
    echo "    Sponsored POC    — Organization-approved pilot. Technical approvals now,"
    echo "                       non-technical (insurance, ITSM, etc.) deferred."
  else
    echo "    Private POC      — Personal exploration. All governance deferred."
  fi
  echo ""
  echo -e "  ${BOLD}POC constraints:${NC} No production deployment, no real user data, no external"
  echo "  users. All technical work is production-grade and carries forward unchanged."
  echo "  Phases 0-3 run identically. Phase 4 (production release) is blocked until upgrade."
  echo ""
  local gov_mode
  if [ "$DEPLOYMENT" = "organizational" ]; then
    gov_mode=$(prompt_choice "Governance mode:" \
      "Sponsored POC" \
      "Production Build")
    case "$gov_mode" in
      "Production"*) POC_MODE="" ;;
      "Sponsored"*)  POC_MODE="sponsored_poc" ;;
    esac
  else
    gov_mode=$(prompt_choice "Governance mode:" \
      "Private POC" \
      "Production Build")
    case "$gov_mode" in
      "Production"*) POC_MODE="" ;;
      "Private"*)    POC_MODE="private_poc" ;;
    esac
  fi

  # Validate track against governance mode
  # Private POC tolerates light track (it's exploratory by design).
  # Sponsored POC and Production Build require Standard or Full track.
  if [ "$TRACK" = "light" ] && [ "$POC_MODE" != "private_poc" ]; then
    echo ""
    if [ -z "$POC_MODE" ]; then
      print_warn "Production builds require Standard or Full track."
      print_warn "Light track skips market validation, user testing, and security hardening."
    else
      print_warn "Sponsored POC requires Standard or Full track."
      print_warn "A sponsor expects due diligence — Light track skips too many safeguards."
    fi
    echo ""
    TRACK=$(prompt_choice "Select a track:" "standard" "full")
    TRACK="${TRACK#"${TRACK%%[![:space:]]*}"}"
    print_ok "Track upgraded to $TRACK"
  fi

  if [ -n "$POC_MODE" ]; then
    echo ""
    print_warn "POC MODE: ${POC_MODE//_/ }"
    print_warn "Phase 4 (production release) is blocked until you upgrade."
    print_warn "Upgrade later: bash scripts/upgrade-project.sh --to-production"
  fi

  # Auto-discover available languages from CI pipeline templates.
  # Filter by platform: only show languages whose CI template lists the selected platform.
  # GitHub subfolder is canonical for discovery — all hosts ship the same language set
  # per spec 2026-04-21.
  local available_languages=()
  for f in "$SCRIPT_DIR/templates/pipelines/ci/github/"*.yml; do
    [ -f "$f" ] || continue
    local lname
    lname=$(basename "$f" .yml)
    [ "$lname" = "other" ] && continue  # add "other" last as fallback
    # Read platforms marker from first line (format: # solo-orchestrator: platforms=web,desktop,mobile)
    local marker
    marker=$(head -1 "$f")
    local platforms_csv=""
    case "$marker" in
      *"# solo-orchestrator: platforms="*)
        platforms_csv="${marker#*platforms=}"
        ;;
    esac
    # If no marker, include the language but warn (backwards compatibility)
    if [ -z "$platforms_csv" ]; then
      print_warn "$lname.yml has no platforms marker — it won't be filtered by platform."
      available_languages+=("$lname")
    else
      # Check if selected platform appears in the comma-separated list
      case ",$platforms_csv," in
        *",$PLATFORM,"*)
          available_languages+=("$lname")
          ;;
      esac
    fi
  done
  available_languages+=("other")

  LANGUAGE=$(prompt_choice "Primary language:" "${available_languages[@]}")
  LANGUAGE="${LANGUAGE#"${LANGUAGE%%[![:space:]]*}"}"

  # OS-language compatibility check — block impossible combinations
  while true; do
    local os_block_reason=""
    case "$OS_TYPE" in
      Linux)
        case "$LANGUAGE" in
          swift)
            os_block_reason="Swift/iOS development requires macOS — Xcode and Apple's build toolchain are not available on Linux."
            ;;
        esac
        ;;
    esac
    if [ -n "$os_block_reason" ]; then
      echo ""
      print_fail "Incompatible OS/language combination: $LANGUAGE on $OS_TYPE"  # lint-fail-emit-exit-status: allow interactive prompt_choice recovery — the while-true loop below re-prompts for a compatible language and re-validates; init proceeds normally once the operator picks a valid combination, so the [FAIL] line is a status diagnostic that does NOT survive past the recovery loop.
      print_warn "$os_block_reason"
      echo ""
      print_info "Valid languages for $PLATFORM on $OS_TYPE:"
      for lang in "${available_languages[@]}"; do
        case "$OS_TYPE" in
          Linux)
            [ "$lang" = "swift" ] && continue
            ;;
        esac
        echo "  - $lang"
      done
      echo ""
      LANGUAGE=$(prompt_choice "Select a different language:" "${available_languages[@]}")
      LANGUAGE="${LANGUAGE#"${LANGUAGE%%[![:space:]]*}"}"
    else
      break
    fi
  done

  if [ "$LANGUAGE" = "other" ]; then
    print_warn "The 'other' language template includes placeholder CI steps that intentionally"
    print_warn "fail the build. You will need to customize .github/workflows/ci.yml for your"
    print_warn "language's build, test, lint, and dependency audit tooling before your first push."
    echo ""
  fi

  # Note: For polyglot projects (e.g., TypeScript frontend + Python backend), select
  # the primary language here. You will need to add CI steps for secondary languages
  # manually in .github/workflows/ci.yml after project creation.

  # Testing interval (default 2, configurable in Intake)
  TEST_INTERVAL=2

  # Determine project directory — default to parent of the solo-orchestrator repo
  local default_parent
  default_parent="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
  # Fall back to ~/projects if we can't resolve the parent
  [ -z "$default_parent" ] || [ "$default_parent" = "/" ] && default_parent="$HOME/projects"
  PROJECT_DIR=$(prompt_input "Project directory" "$default_parent/$PROJECT_NAME")
  # Strip surrounding quotes if user pasted a quoted path
  PROJECT_DIR="${PROJECT_DIR#\"}"
  PROJECT_DIR="${PROJECT_DIR%\"}"
  PROJECT_DIR="${PROJECT_DIR#\'}"
  PROJECT_DIR="${PROJECT_DIR%\'}"

  echo ""
  print_info "Project: $PROJECT_NAME"
  print_info "Platform: $PLATFORM | Track: $TRACK | Language: $LANGUAGE"
  print_info "Directory: $PROJECT_DIR"
  echo ""

  read -rp "$(echo -e "${BOLD}Continue? [Y/n]${NC}: ")" confirm # lint-raw-read-prompt: allow init.sh interactive-only wizard (NON_INTERACTIVE=true path bypasses collect_inputs_interactive entirely; see init.sh:3532)
  if [[ "$confirm" =~ ^[Nn] ]]; then
    echo ""
    local choice
    choice=$(prompt_choice "What would you like to do?" \
      "Re-enter project info" \
      "Restart from beginning" \
      "Quit")
    case "$choice" in
      "Re-enter"*)
        collect_project_info
        return
        ;;
      "Restart"*)
        print_info "Restarting setup..."
        exec "$0"
        ;;
      "Quit")
        print_info "Setup cancelled."
        exit 0
        ;;
    esac
  fi
}

# ================================================================
# PHASE 3: Resolve and Install Tools (Matrix-Driven)
# ================================================================
resolve_and_install_tools() {
  print_step "Resolving tool installation plan..."
  local os_type="$OS_TYPE"
  local dev_os
  case "$os_type" in
    Darwin) dev_os="darwin" ;;
    Linux)  dev_os="linux" ;;
    *)      dev_os="linux" ;;  # best-effort fallback
  esac

  # Run the resolver
  local resolver_output
  resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
    --dev-os "$dev_os" \
    --platform "$PLATFORM" \
    --language "$LANGUAGE" \
    --track "$TRACK" \
    --phase 2 \
    --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" 2>/dev/null) || {
    print_warn "Tool resolver failed. Falling back to basic tool checks."
    return 0
  }

  # Re-check items the resolver misclassifies. Build a separate
  # "configure_during_creation" list for things that exist but need per-project wiring.
  local configure_items="[]"

  if command -v jq &>/dev/null; then

    # Qdrant MCP: resolver always marks manual (auto_installable: false).
    # Reclassify based on actual state: registered → installed, container running → configure, docker available → auto.
    if echo "$resolver_output" | jq -e '.manual_install[] | select(.name == "Qdrant MCP")' >/dev/null 2>&1; then
      if is_qdrant_mcp_registered; then
        resolver_output=$(echo "$resolver_output" | jq '
          .already_installed += [{ name: "Qdrant MCP", version: "configured", category: "mcp_server" }] |
          .manual_install |= map(select(.name != "Qdrant MCP"))
        ')
      elif is_qdrant_container_running; then
        resolver_output=$(echo "$resolver_output" | jq '
          .already_installed += [{ name: "Qdrant", version: "container running", category: "mcp_server" }] |
          .manual_install |= map(select(.name != "Qdrant MCP"))
        ')
        configure_items=$(echo "$configure_items" | jq '. += ["Qdrant MCP registration + project collection"]')
      elif command -v docker &>/dev/null; then
        resolver_output=$(echo "$resolver_output" | jq '
          .auto_install += [{ name: "Qdrant MCP", category: "mcp_server", install_cmd: "echo auto" }] |
          .manual_install |= map(select(.name != "Qdrant MCP"))
        ')
      fi
    fi

    # Development Guardrails: resolver marks manual but init.sh handles it.
    if echo "$resolver_output" | jq -e '.manual_install[] | select(.name == "Development Guardrails for Claude Code")' >/dev/null 2>&1; then
      if [ -d "$HOME/.claude-dev-framework/.git" ] && [ -f "$HOME/.claude-dev-framework/scripts/init.sh" ]; then
        # Global clone exists — show as installed, hooks configured during creation
        resolver_output=$(echo "$resolver_output" | jq '
          .already_installed += [{ name: "Development Guardrails for Claude Code", version: "installed", category: "dev_framework" }] |
          .manual_install |= map(select(.name != "Development Guardrails for Claude Code"))
        ')
        configure_items=$(echo "$configure_items" | jq '. += ["Development Guardrails hooks + rules"]')
      else
        # Will be cloned — move to auto_install
        resolver_output=$(echo "$resolver_output" | jq '
          .auto_install += [{ name: "Development Guardrails for Claude Code", category: "dev_framework", install_cmd: "echo auto" }] |
          .manual_install |= map(select(.name != "Development Guardrails for Claude Code"))
        ')
        configure_items=$(echo "$configure_items" | jq '. += ["Development Guardrails hooks + rules"]')
      fi
    fi

  fi

  # Parse bucket counts
  local auto_count manual_count installed_count deferred_count configure_count
  auto_count=$(echo "$resolver_output" | jq '.auto_install | length')
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  installed_count=$(echo "$resolver_output" | jq '.already_installed | length')
  deferred_count=$(echo "$resolver_output" | jq '.deferred | length')
  configure_count=$(echo "$configure_items" | jq 'length')

  # Display the installation plan
  echo ""
  echo -e "${BOLD}┌──────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│  Tool Installation Plan ($os_type / $PLATFORM / $LANGUAGE)${NC}"
  echo -e "${BOLD}├──────────────────────────────────────────────────────────┤${NC}"

  # Already installed
  if [ "$installed_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${GREEN}✓ Already installed${NC}"
    echo "$resolver_output" | jq -r '.already_installed[] | "    \(.name)\(if .version != "" then " " + .version else "" end)"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Will auto-install now
  if [ "$auto_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${CYAN}⬇ Will install now${NC}"
    echo "$resolver_output" | jq -r '.auto_install[] | "    \(.name) (\(.category))"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Will configure during project creation
  if [ "$configure_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${CYAN}🔧 Will configure during project creation${NC}"
    echo "$configure_items" | jq -r '.[] | "    \(.)"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Will auto-install at later phases
  if [ "$deferred_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${BLUE}⏳ Will auto-install later (at phase transition)${NC}"
    echo "$resolver_output" | jq -r '.deferred[] | "    Phase \(.phase): \(.name)"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Requires manual setup (only truly manual items)
  if [ "$manual_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${YELLOW}⚠ Requires manual setup${NC}"
    echo "$resolver_output" | jq -r '.manual_install[] | "    \(.name) — \(.instructions)"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
    echo -e "${BOLD}│${NC}"
  fi

  echo -e "${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
  echo ""

  # Confirm — skip prompt when there is nothing to install.
  # BL-057: honor NON_INTERACTIVE + AUTO_INSTALL_TOOLS so the --non-interactive
  # contract is upheld (closed stdin + `set -euo pipefail` + bare `read -rp`
  # previously terminated the script silently with rc=1 the moment the resolved
  # plan included an auto_install or manual_install entry — surfaced as a
  # Step-5 dogfood DOGFOOD-001 on --platform mobile via Android Studio's
  # auto_install row).
  local response="Y"
  if [ "$auto_count" -gt 0 ] || [ "$manual_count" -gt 0 ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
      response="${AUTO_INSTALL_TOOLS:-Y}"
    else
      read -rp "$(echo -e "${YELLOW}▶ ${BOLD}Proceed with this plan? [Y/n]${NC}: ")" response # lint-raw-read-prompt: allow init.sh interactive-only tool-install plan; NON_INTERACTIVE branch above honors AUTO_INSTALL_TOOLS env var
    fi
  fi
  if [[ "$response" =~ ^[Nn] ]]; then
    # BL-057: under NON_INTERACTIVE, the user has already expressed an
    # explicit decline via AUTO_INSTALL_TOOLS=N. Dropping into the
    # interactive prompt_choice sub-menu (which assumes a TTY) would hang
    # or surface a confusing EOF diagnostic. Skip the auto-install plan
    # and let init.sh proceed with whatever is already present — anything
    # truly required will be re-flagged at the phase-gate check.
    if [ "$NON_INTERACTIVE" = true ]; then
      print_info "AUTO_INSTALL_TOOLS=N — skipping tool auto-installation. Missing tools will be re-flagged at the next phase gate."
      auto_count=0
      return 0
    fi
    echo ""
    local config_choice
    config_choice=$(prompt_choice "What would you like to do?" \
      "Guided walkthrough (step through each category)" \
      "Edit .claude/tool-preferences.json manually" \
      "Re-enter project info" \
      "Restart from beginning" \
      "Quit")

    case "$config_choice" in
      "Re-enter"*)
        # Go back to project info, then re-run tool resolution
        collect_project_info
        resolve_and_install_tools
        return
        ;;
      "Restart"*)
        print_info "Restarting setup..."
        exec "$0"
        ;;
      "Quit")
        print_info "Setup cancelled."
        exit 0
        ;;
      "Guided walkthrough"*)
        run_tool_walkthrough "$resolver_output" "$dev_os"
        # Re-resolve after walkthrough
        resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
          --dev-os "$dev_os" \
          --platform "$PLATFORM" \
          --language "$LANGUAGE" \
          --track "$TRACK" \
          --phase 2 \
          --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" \
          --tool-prefs "$PROJECT_DIR/.claude/tool-preferences.json" 2>/dev/null) || true
        ;;
      "Edit"*)
        # Write defaults and let user edit
        write_tool_preferences "$resolver_output" "$dev_os" "$PROJECT_DIR"
        echo ""
        print_info "Default preferences written to: $PROJECT_DIR/.claude/tool-preferences.json"
        print_info "Edit the file, then press Enter to continue."
        read -rp "" # lint-raw-read-prompt: allow init.sh interactive-only "press Enter to continue" pause after manual tool-preferences edit; non-interactive path skips this whole branch (PROMPT_EDIT only used when -t 0 above)
        # Re-resolve after manual edit
        resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
          --dev-os "$dev_os" \
          --platform "$PLATFORM" \
          --language "$LANGUAGE" \
          --track "$TRACK" \
          --phase 2 \
          --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" \
          --tool-prefs "$PROJECT_DIR/.claude/tool-preferences.json" 2>/dev/null) || true
        ;;
      "Restart"*)
        echo ""
        print_info "Restarting setup..."
        exec "$0"
        ;;
      "Quit")
        echo ""
        print_info "Setup cancelled."
        exit 0
        ;;
    esac

    # Update counts after re-resolution
    auto_count=$(echo "$resolver_output" | jq '.auto_install | length')
    manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  fi

  # Execute auto-installs
  if [ "$auto_count" -gt 0 ]; then
    print_step "Installing tools..."
    for i in $(seq 0 $((auto_count - 1))); do
      local tool_name tool_cmd
      tool_name=$(echo "$resolver_output" | jq -r ".auto_install[$i].name")
      tool_cmd=$(echo "$resolver_output" | jq -r ".auto_install[$i].install_cmd")

      # Development Guardrails: skip — handled in create_project()
      if [[ "$tool_name" == Development\ Guardrails\ for\ Claude\ Code* ]]; then
        continue
      fi

      # Qdrant MCP: run the real Docker + MCP setup instead of the placeholder command
      if [[ "$tool_name" == Qdrant\ MCP* ]]; then
        print_info "Setting up Qdrant MCP..."
        local _qd_ok=false
        # Start container
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
          print_ok "Qdrant container already running"
          _qd_ok=true
        elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
          docker start qdrant >/dev/null 2>&1 && _qd_ok=true && print_ok "Existing Qdrant container started"
        else
          if docker run -d --name qdrant \
            -p 6333:6333 -p 6334:6334 \
            -v qdrant_storage:/qdrant/storage \
            --restart unless-stopped \
            qdrant/qdrant:latest >/dev/null 2>&1; then
            _qd_ok=true
            print_ok "Qdrant running at http://localhost:6333"
          else
            print_warn "Failed to start Qdrant container"
          fi
        fi
        # Register MCP
        if [ "$_qd_ok" = true ]; then
          if command -v uvx &>/dev/null; then
            if run_with_timeout 30 bash -c 'echo "y" | claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant >/dev/null 2>&1'; then
              print_ok "Qdrant MCP registered"
            else
              print_warn "Failed to register Qdrant MCP (timed out or errored). Register manually:"
              echo "    claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
            fi
          else
            print_warn "uv/uvx not found — needed for Qdrant MCP server"
            echo "  Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
          fi
        fi
        continue
      fi

      print_info "Installing $tool_name..."
      if eval "$tool_cmd" 2>/dev/null; then
        print_ok "$tool_name installed"
      else
        print_warn "Could not install $tool_name. Install manually: $tool_cmd"
      fi
    done
  fi

  # Handle manual install items — offer to set up Qdrant if Docker is now available
  if [ "$manual_count" -gt 0 ]; then
    local qdrant_handled=false

    # If Qdrant is in the manual list and Docker is running, offer auto-setup
    if echo "$resolver_output" | jq -e '.manual_install[] | select(.name == "Qdrant MCP")' >/dev/null 2>&1; then
      if is_qdrant_container_running || (command -v docker &>/dev/null && run_with_timeout 5 docker info >/dev/null 2>&1); then
        echo ""
        print_info "Docker is available — setting up Qdrant MCP..."

        # Start Qdrant container if not already running
        local qdrant_running=false
        if is_qdrant_container_running; then
          qdrant_running=true
          print_ok "Qdrant container already running"
        elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
          docker start qdrant 2>/dev/null && qdrant_running=true && print_ok "Existing Qdrant container started"
        else
          if docker run -d --name qdrant \
            -p 6333:6333 -p 6334:6334 \
            -v qdrant_storage:/qdrant/storage \
            --restart unless-stopped \
            qdrant/qdrant:latest >/dev/null 2>&1; then
            qdrant_running=true
            print_ok "Qdrant running at http://localhost:6333"
          else
            print_warn "Failed to start Qdrant container"
          fi
        fi

        # Register MCP server
        if [ "$qdrant_running" = true ]; then
          if command -v uvx &>/dev/null || command -v pipx &>/dev/null; then
            if register_qdrant_mcp; then
              print_ok "Qdrant MCP registered"
              qdrant_handled=true
              resolver_output=$(echo "$resolver_output" | jq '
                .already_installed += [{ name: "Qdrant MCP", version: "configured", category: "mcp_server" }] |
                .manual_install |= map(select(.name != "Qdrant MCP"))
              ')
              manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
            else
              print_warn "Failed to register Qdrant MCP"
            fi
          else
            print_warn "uv/uvx not found — needed for Qdrant MCP server"
            echo "  Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
          fi
        fi
      fi
    fi

    # Show remaining manual items (if any left after Qdrant auto-setup)
    if [ "$manual_count" -gt 0 ]; then
      echo ""
      print_info "Manual setup required for:"
      for i in $(seq 0 $((manual_count - 1))); do
        local tool_name instructions
        tool_name=$(echo "$resolver_output" | jq -r ".manual_install[$i].name")
        instructions=$(echo "$resolver_output" | jq -r ".manual_install[$i].instructions")
        echo "  • $tool_name — $instructions"
      done
    fi
  fi

  # Store resolver output for later use by create_project
  RESOLVER_OUTPUT="$resolver_output"
  RESOLVER_DEV_OS="$dev_os"

  echo ""
  print_ok "Tool resolution complete."
}

run_tool_walkthrough() {
  local resolver_output="$1"
  local dev_os="$2"

  # Get unique substitution categories from auto_install + manual_install
  local categories
  categories=$(echo "$resolver_output" | jq -r '[(.auto_install + .manual_install)[] | select(.category != null) | .category] | unique | .[]')

  local prefs_substitutions="{}"
  local prefs_skipped="[]"

  for category in $categories; do
    local tool_name
    tool_name=$(echo "$resolver_output" | jq -r "(.auto_install + .manual_install)[] | select(.category == \"$category\") | .name" | head -1)

    echo ""
    local choice
    choice=$(prompt_choice "$category:" \
      "$tool_name (recommended)" \
      "Other (enter name and check command)" \
      "Skip")

    case "$choice" in
      *recommended*)
        # Keep default — no action needed
        ;;
      *Other*)
        local custom_name custom_check
        custom_name=$(prompt_input "Tool name" "")
        custom_check=$(prompt_input "Check command (shell command that returns 0 if installed)" "command -v $custom_name")
        prefs_substitutions=$(echo "$prefs_substitutions" | jq \
          --arg cat "$category" \
          --arg default "$tool_name" \
          --arg selected "$custom_name" \
          --arg check "$custom_check" \
          '. + {($cat): {default: $default, selected: $selected, check_command: $check}}')
        ;;
      *Skip*)
        prefs_skipped=$(echo "$prefs_skipped" | jq \
          --arg name "$tool_name" \
          --arg cat "$category" \
          '. + [{name: $name, category: $cat, reason: "Skipped during walkthrough"}]')
        ;;
    esac
  done

  # Write preferences
  mkdir -p "$PROJECT_DIR/.claude"
  local today
  today=$(date +%Y-%m-%d)
  jq -n \
    --arg version "1.0" \
    --arg date "$today" \
    --arg dev_os "$dev_os" \
    --arg platform "$PLATFORM" \
    --arg language "$LANGUAGE" \
    --arg track "$TRACK" \
    --argjson substitutions "$prefs_substitutions" \
    --argjson skipped "$prefs_skipped" \
    '{
      schema_version: $version,
      resolved_at: $date,
      context: {dev_os: $dev_os, platform: $platform, language: $language, track: $track},
      substitutions: $substitutions,
      additions: [],
      skipped: $skipped,
      installed: {}
    }' > "$PROJECT_DIR/.claude/tool-preferences.json"
}

write_tool_preferences() {
  local resolver_output="$1"
  local dev_os="$2"
  local project_dir="$3"

  mkdir -p "$project_dir/.claude"
  local today
  today=$(date +%Y-%m-%d)

  # Build installed list from already_installed
  local installed_phase_0 installed_phase_1
  installed_phase_0=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category == "version_control" or .category == "json_processor" or .category == "runtime" or .category == "containerization" or .category == "commit_signing") | .name]')
  installed_phase_1=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category != "version_control" and .category != "json_processor" and .category != "containerization" and .category != "commit_signing") | .name]')

  jq -n \
    --arg version "1.0" \
    --arg date "$today" \
    --arg dev_os "$dev_os" \
    --arg platform "$PLATFORM" \
    --arg language "$LANGUAGE" \
    --arg track "$TRACK" \
    --argjson phase_0 "$installed_phase_0" \
    --argjson phase_1 "$installed_phase_1" \
    '{
      schema_version: $version,
      resolved_at: $date,
      context: {dev_os: $dev_os, platform: $platform, language: $language, track: $track},
      substitutions: {},
      additions: [],
      skipped: [],
      installed: {phase_0: $phase_0, phase_1: $phase_1}
    }' > "$project_dir/.claude/tool-preferences.json"
}

append_intake_tooling_summary() {
  local resolver_output="$1"

  cat >> PROJECT_INTAKE.md << 'TOOLHDR'

---

## Tooling Configuration

> Auto-generated by init.sh. Full machine-readable config: `.claude/tool-preferences.json`

TOOLHDR

  # Resolved for
  echo "**Resolved for:** $OS_TYPE / $PLATFORM / $LANGUAGE / $TRACK track" >> PROJECT_INTAKE.md
  echo "" >> PROJECT_INTAKE.md

  # Installed table
  local installed_count
  installed_count=$(echo "$resolver_output" | jq '.already_installed | length')
  if [ "$installed_count" -gt 0 ]; then
    echo "### Installed" >> PROJECT_INTAKE.md
    echo "| Tool | Category | Version |" >> PROJECT_INTAKE.md
    echo "|---|---|---|" >> PROJECT_INTAKE.md
    echo "$resolver_output" | jq -r '.already_installed[] | "| \(.name) | \(.category) | \(.version) |"' >> PROJECT_INTAKE.md
    echo "" >> PROJECT_INTAKE.md
  fi

  # Manual setup table
  local manual_count
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  if [ "$manual_count" -gt 0 ]; then
    echo "### Manual Setup Required" >> PROJECT_INTAKE.md
    echo "| Tool | Category | Instructions |" >> PROJECT_INTAKE.md
    echo "|---|---|---|" >> PROJECT_INTAKE.md
    echo "$resolver_output" | jq -r '.manual_install[] | "| \(.name) | \(.category) | \(.instructions) |"' >> PROJECT_INTAKE.md
    echo "" >> PROJECT_INTAKE.md
  fi

  # Deferred table
  local deferred_count
  deferred_count=$(echo "$resolver_output" | jq '.deferred | length')
  if [ "$deferred_count" -gt 0 ]; then
    echo "### Deferred (Phase 3+)" >> PROJECT_INTAKE.md
    echo "| Tool | Phase | Category |" >> PROJECT_INTAKE.md
    echo "|---|---|---|" >> PROJECT_INTAKE.md
    echo "$resolver_output" | jq -r '.deferred[] | "| \(.name) | \(.phase) | \(.category) |"' >> PROJECT_INTAKE.md
    echo "" >> PROJECT_INTAKE.md
  fi
}

# ================================================================
# PHASE 4: Create Project
# ================================================================
create_project() {
  print_step "Creating project at $PROJECT_DIR..."

  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"

  # Copy framework documents
  print_info "Copying framework documents..."
  # BL-103: docs/eval-results/ is the manifest's REQUIRED home — the Phase 3→4
  # review gate reads docs/eval-results/review-manifest.json, and
  # evaluation-prompts/Projects/run-reviews.sh writes it there. The scaffold never
  # created the directory, so the gate's own remediation path pointed into a
  # folder that did not exist. Create it up front, like every other gate-checked
  # docs/ directory above.
  mkdir -p docs/reference docs/platform-modules docs/test-results "docs/ADR documentation" "docs/api and interfaces" docs/snapshots docs/phase-0 docs/security-audits docs/eval-results

  cp "$SCRIPT_DIR/docs/builders-guide.md" docs/reference/
  cp "$SCRIPT_DIR/docs/governance-framework.md" docs/reference/
  cp "$SCRIPT_DIR/docs/executive-review.md" docs/reference/
  cp "$SCRIPT_DIR/docs/cli-setup-addendum.md" docs/reference/
  cp "$SCRIPT_DIR/docs/user-guide.md" docs/reference/
  cp "$SCRIPT_DIR/docs/security-scan-guide.md" docs/reference/
  # Audit uat-authoring-guide-2 (2026-06): the UAT authoring guide is
  # referenced by init.sh's UAT-references fallback print_* strings AND
  # by templates/uat/test-session-template.html line ~95. Without copying
  # it into the generated project, those references resolve to nothing
  # once the operator leaves the framework repo. Mirrors the pattern for
  # the six sibling docs above.
  cp "$SCRIPT_DIR/docs/uat-authoring-guide.md" docs/reference/

  # Copy evaluation prompts (project-level reviews for Phase 3 validation)
  print_info "Copying evaluation prompts..."
  if [ -d "$SCRIPT_DIR/evaluation-prompts/Projects" ]; then
    mkdir -p evaluation-prompts/Projects
    cp -r "$SCRIPT_DIR/evaluation-prompts/Projects/"* evaluation-prompts/Projects/ 2>/dev/null || true
  fi

  # Copy utility scripts into the project (self-contained after init)
  print_info "Copying utility scripts..."
  mkdir -p scripts/lib
  # BL-046: helpers.sh split into a backwards-compat shim + core + full.
  # All three files must be copied — the shim (helpers.sh) sources
  # helpers-full.sh, which sources helpers-core.sh. Short-lived
  # scripts (check-*, validate, test-gate, resume) source helpers-core.sh
  # directly; long-running callers (init.sh, upgrade-project.sh,
  # intake-wizard.sh, reconfigure-project.sh, verify-install.sh) source
  # helpers.sh (which transitively loads full + core).
  cp "$SCRIPT_DIR/scripts/lib/helpers.sh"       scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/helpers-core.sh"  scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/helpers-full.sh"  scripts/lib/
  # BL-099: shared libs sourced by scripts/upgrade-project.sh --sync-framework
  # (and, for hook-templates.sh, by this init.sh). Shipped so a project's own
  # upgrade-project.sh copy stays source-closed after a sync replaces it.
  cp "$SCRIPT_DIR/scripts/lib/hook-templates.sh"       scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/scaffold-shipped-set.sh" scripts/lib/
  # BL-109 Currency System: the manifest currency-block reader/writer (S1) and
  # the session-start freshness detector lib (S2). session-freshness-check.sh
  # sources freshness-detect.sh, which sources currency-manifest.sh (which in
  # turn sources scaffold-shipped-set.sh + hook-templates.sh, both above) — the
  # whole chain must ship or the SessionStart hook is not source-closed
  # downstream. (S1 carried obligation 5: currency-manifest.sh ships downstream.)
  cp "$SCRIPT_DIR/scripts/lib/currency-manifest.sh"    scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/freshness-detect.sh"     scripts/lib/
  cp "$SCRIPT_DIR/scripts/validate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" scripts/
  # BL-088: check-phase-gate.sh's Phase-3→4 gate auto-runs (and points the
  # operator at) scripts/run-phase3-validation.sh via P3_DRIVER="$SCRIPT_DIR/
  # run-phase3-validation.sh". Omitting it left the pass-path unreachable
  # downstream — the gate failed closed but told the operator to run a script
  # that did not exist in the scaffold. Ship the driver beside its caller.
  cp "$SCRIPT_DIR/scripts/run-phase3-validation.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-updates.sh" scripts/
  cp "$SCRIPT_DIR/scripts/resume.sh" scripts/
  cp "$SCRIPT_DIR/scripts/intake-wizard.sh" scripts/
  cp "$SCRIPT_DIR/scripts/resolve-tools.sh" scripts/
  cp "$SCRIPT_DIR/scripts/upgrade-project.sh" scripts/
  cp "$SCRIPT_DIR/scripts/reconfigure-project.sh" scripts/
  cp "$SCRIPT_DIR/scripts/verify-install.sh" scripts/
  cp "$SCRIPT_DIR/scripts/test-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-versions.sh" scripts/
  cp "$SCRIPT_DIR/scripts/session-version-check.sh" scripts/
  cp "$SCRIPT_DIR/scripts/session-freshness-check.sh" scripts/   # BL-109 S2 (Currency System, Layer 1)
  cp "$SCRIPT_DIR/scripts/session-test-gate-check.sh" scripts/
  cp "$SCRIPT_DIR/scripts/session-end-qdrant-reminder.sh" scripts/
  cp "$SCRIPT_DIR/scripts/session-mcp-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/process-checklist.sh" scripts/
  cp "$SCRIPT_DIR/scripts/pre-commit-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/track-tool-usage.sh" scripts/
  # BL-029: bypass-detector + escalate-to-user CLI + libs.
  mkdir -p scripts/hooks scripts/lib
  cp "$SCRIPT_DIR/scripts/hooks/bypass-detector.sh" scripts/hooks/
  cp "$SCRIPT_DIR/scripts/escalate-to-user.sh"       scripts/
  cp "$SCRIPT_DIR/scripts/lib/bypass-audit.sh"       scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/bypass-patterns.sh"    scripts/lib/
  chmod +x scripts/hooks/bypass-detector.sh scripts/escalate-to-user.sh
  cp "$SCRIPT_DIR/scripts/pending-approval.sh" scripts/      # BL-015
  cp "$SCRIPT_DIR/scripts/lint-uat-scenarios.sh" scripts/    # BL-009
  cp "$SCRIPT_DIR/scripts/lint-fixture-envelopes.sh" scripts/  # BL-030
  # BL-030: enforcement-level lib, gate-principles lib, filesystem-gate
  # installer, PostToolUse Claude-commit recorder, SessionStart out-of-
  # band detector. Required by reconfigure --enforcement-level and by
  # the strict-mode framework-gate.sh.
  cp "$SCRIPT_DIR/scripts/lib/enforcement-level.sh" scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/gate-principles.sh"   scripts/lib/
  # BL-088: sourced gate dependencies that shipped gate scripts load via
  # "$SCRIPT_DIR/lib/<name>" but that this copy list never enumerated. Each
  # absence is a silent downstream failure of the sourcing gate:
  #   • tdd-classify.sh — pre-commit-gate.sh sources it for the tier-keyed TDD
  #     hard block (BL-072 C2). Its silent-skip loop meant a test-less feat:
  #     commit in a Sponsored-POC scaffold was ALLOWED (rc=0) — the flagship
  #     gate no-op'd. (Empirically proven, PR #173 adversarial review.)
  #   • phase2-state.sh — check-gate.sh sources it (no [-f] guard) for Phase-2
  #     step write-back; absent, that path dies "No such file or directory".
  #   • cdf-refresh.sh — upgrade-project.sh sources it to refresh CDF assets;
  #     absent, every scaffolded project silently skipped the CDF sync on
  #     upgrade. The source-closure check (tests/test-scaffold-source-closure.sh)
  #     is the class fix: it fails if any shipped script sources an unshipped
  #     sibling.
  cp "$SCRIPT_DIR/scripts/lib/tdd-classify.sh"      scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/phase2-state.sh"      scripts/lib/
  cp "$SCRIPT_DIR/scripts/lib/cdf-refresh.sh"       scripts/lib/
  cp "$SCRIPT_DIR/scripts/install-filesystem-gates.sh" scripts/
  cp "$SCRIPT_DIR/scripts/detect-out-of-band-commits.sh" scripts/
  cp "$SCRIPT_DIR/scripts/hooks/record-claude-commit.sh" scripts/hooks/
  chmod +x scripts/install-filesystem-gates.sh \
           scripts/detect-out-of-band-commits.sh \
           scripts/hooks/record-claude-commit.sh
  # Host dispatcher + per-host drivers so check-gate.sh --backfill-host/
  # --repair/--preflight and init's own host-aware code paths resolve
  # inside the initialized project (audit: code-init-sh-2).
  mkdir -p scripts/host-drivers
  cp "$SCRIPT_DIR/scripts/lib/host.sh" scripts/lib/
  cp "$SCRIPT_DIR/scripts/host-drivers/"*.sh scripts/host-drivers/
  chmod +x scripts/host-drivers/*.sh
  chmod +x scripts/validate.sh scripts/check-phase-gate.sh scripts/run-phase3-validation.sh scripts/check-gate.sh scripts/check-updates.sh scripts/resume.sh scripts/intake-wizard.sh scripts/resolve-tools.sh scripts/upgrade-project.sh scripts/reconfigure-project.sh scripts/verify-install.sh scripts/test-gate.sh scripts/check-versions.sh scripts/session-version-check.sh scripts/session-freshness-check.sh scripts/session-test-gate-check.sh scripts/session-end-qdrant-reminder.sh scripts/session-mcp-gate.sh scripts/process-checklist.sh scripts/pre-commit-gate.sh scripts/track-tool-usage.sh scripts/pending-approval.sh scripts/lint-uat-scenarios.sh

  # Copy intake suggestion files
  mkdir -p templates/intake-suggestions
  cp "$SCRIPT_DIR/templates/intake-suggestions/"*.json templates/intake-suggestions/

  # Copy tool matrix files (for phase gate and track upgrade resolution)
  mkdir -p templates/tool-matrix
  cp "$SCRIPT_DIR/templates/tool-matrix/"*.json templates/tool-matrix/

  # Copy UAT template and create session directory structure
  mkdir -p tests/uat/templates tests/uat/sessions tests/uat/examples
  cp "$SCRIPT_DIR/templates/uat/test-session-template.md"   tests/uat/templates/test-session-template.md
  cp "$SCRIPT_DIR/templates/uat/test-session-template.html" tests/uat/templates/test-session-template.html

  # Per-platform reference copy (spec 2026-04-23-uat-template-quality-design.md § Flow A)
  if [ "$PLATFORM" != "other" ] && \
     [ -f "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-pre-flight.html" ] && \
     [ -f "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-scenario.json" ]; then
    cp "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-pre-flight.html" \
       tests/uat/examples/pre-flight-reference.html
    cp "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-scenario.json" \
       tests/uat/examples/scenario-reference.json
    print_ok "UAT platform reference copied for $PLATFORM"
  elif [ "$PLATFORM" = "other" ]; then
    print_info "Platform is 'other' — no UAT canned reference copied."
    print_info "When starting a UAT session, the agent will run the co-build Q&A"
    print_info "protocol with you per docs/reference/uat-authoring-guide.md § 5."
  else
    print_warn "UAT reference files not found for platform '$PLATFORM'. Falling back to 'other'-style co-build protocol; see docs/reference/uat-authoring-guide.md § 5."
  fi

  # Copy the correct platform module (auto-discovered)
  local platform_module="$SCRIPT_DIR/docs/platform-modules/${PLATFORM}.md"
  if [ -f "$platform_module" ]; then
    cp "$platform_module" docs/platform-modules/
    print_ok "Platform module: $PLATFORM"
  else
    print_info "No platform module for '$PLATFORM'. The Builder's Guide works standalone."
  fi

  # Copy documentation artifact templates
  print_info "Copying documentation templates..."
  mkdir -p templates/generated
  cp "$SCRIPT_DIR/templates/generated/project-bible.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/product-manifesto.tmpl" templates/generated/
  # BL-109-CURRENCY: record the A2 (agent-authored) render bases by TEMPLATE sha
  # only — PROJECT_BIBLE.md / PRODUCT_MANIFESTO.md are created by no script and
  # do not exist at birth (review-r1 B3a), so there is no rendered-output sha and
  # no files{} entry. Captured here, at the copy site, from the template source.
  soif_currency_record_render_base A2 PROJECT_BIBLE.md \
    "$SCRIPT_DIR/templates/generated/project-bible.tmpl" ""
  soif_currency_record_render_base A2 PRODUCT_MANIFESTO.md \
    "$SCRIPT_DIR/templates/generated/product-manifesto.tmpl" ""
  cp "$SCRIPT_DIR/templates/generated/frd.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/user-journey.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/data-contract.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/adr.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/features.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/handoff.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/incident-response.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/changelog.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/bugs.tmpl" templates/generated/
  cp "$SCRIPT_DIR/templates/generated/release-notes.tmpl" templates/generated/
  # Verifier nit-2 follow-up (PR #92 review): copy the canonical
  # claude-md.tmpl into the project so verify-install.sh's self-
  # bootstrap fallback in fix_claude_md (scripts/verify-install.sh:645
  # — `elif [ -f "templates/generated/claude-md.tmpl" ]`) has something
  # to read when $SOURCE_DIR is no longer reachable (developer rotated
  # the orchestrator clone, CI restored only the project tree, etc.).
  # Without this copy that fallback was dead code in practice.
  cp "$SCRIPT_DIR/templates/generated/claude-md.tmpl" templates/generated/

  # Install vendored skills (project-level, .claude/skills/<name>/).
  # Skills are markdown SKILL.md files with NOTICE-attribution preserved.
  # Adding a new skill: drop it under templates/generated/skills/<name>/
  # and append a line to the loop below.
  mkdir -p .claude/skills
  for skill in session-handoff sweep-triage zoom-out grill-with-docs; do
    if [ -d "$SCRIPT_DIR/templates/generated/skills/$skill" ]; then
      mkdir -p ".claude/skills/$skill"
      cp "$SCRIPT_DIR/templates/generated/skills/$skill/SKILL.md" ".claude/skills/$skill/"
      [ -f "$SCRIPT_DIR/templates/generated/skills/$skill/NOTICE" ] \
        && cp "$SCRIPT_DIR/templates/generated/skills/$skill/NOTICE" ".claude/skills/$skill/"
    fi
  done

  # Copy starter files from templates (empty until agent populates)
  cp "$SCRIPT_DIR/templates/generated/features.tmpl" FEATURES.md
  cp "$SCRIPT_DIR/templates/generated/changelog.tmpl" CHANGELOG.md
  cp "$SCRIPT_DIR/templates/generated/bugs.tmpl" BUGS.md
  cp "$SCRIPT_DIR/templates/generated/release-notes.tmpl" RELEASE_NOTES.md

  # Initialize git early — Development Guardrails requires a git repo
  print_info "Initializing Git repository..."
  git init -q
  # Remove hook samples so framework doesn't misdetect as existing project
  rm -f .git/hooks/*.sample

  # Generate Claude Code permissions (auto-accept safe operations)
  # This must be created BEFORE the Development Guardrails install, which merges
  # its hooks into settings.json while preserving existing keys (like permissions).
  print_info "Generating Claude Code permissions..."
  mkdir -p .claude

  # Build language-specific allow rules
  local lang_rules=""
  case "$LANGUAGE" in
    typescript|javascript)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(npm install *)",
      "Bash(npm ci)",
      "Bash(npm run *)",
      "Bash(npm test *)",
      "Bash(npm outdated)",
      "Bash(npx *)",
      "Bash(node *)",
      "Bash(tsc *)",
      "Bash(eslint *)",
      "Bash(prettier *)",
LANGEOF
) ;;
    python)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(pip install *)",
      "Bash(pip list *)",
      "Bash(pip show *)",
      "Bash(pip freeze *)",
      "Bash(python -m pip *)",
      "Bash(python -m pytest *)",
      "Bash(python -m unittest *)",
      "Bash(pytest *)",
      "Bash(python *)",
      "Bash(python3 *)",
      "Bash(mypy *)",
      "Bash(ruff *)",
      "Bash(black *)",
LANGEOF
) ;;
    rust)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(cargo build *)",
      "Bash(cargo test *)",
      "Bash(cargo run *)",
      "Bash(cargo check *)",
      "Bash(cargo clippy *)",
      "Bash(cargo fmt *)",
      "Bash(cargo add *)",
      "Bash(cargo audit *)",
      "Bash(rustc *)",
LANGEOF
) ;;
    go)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(go build *)",
      "Bash(go test *)",
      "Bash(go run *)",
      "Bash(go mod *)",
      "Bash(go vet *)",
      "Bash(go fmt *)",
      "Bash(golangci-lint *)",
LANGEOF
) ;;
    csharp)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(dotnet build *)",
      "Bash(dotnet test *)",
      "Bash(dotnet run *)",
      "Bash(dotnet restore *)",
      "Bash(dotnet add *)",
      "Bash(dotnet format *)",
LANGEOF
) ;;
    kotlin|java)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(./gradlew *)",
      "Bash(gradle *)",
      "Bash(mvn *)",
      "Bash(java *)",
      "Bash(javac *)",
      "Bash(kotlinc *)",
LANGEOF
) ;;
    dart)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(flutter *)",
      "Bash(dart *)",
      "Bash(dart pub *)",
      "Bash(flutter pub *)",
      "Bash(flutter test *)",
      "Bash(flutter build *)",
      "Bash(flutter analyze *)",
LANGEOF
) ;;
    swift)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(swift build *)",
      "Bash(swift test *)",
      "Bash(swift package *)",
      "Bash(swiftlint *)",
      "Bash(xcodebuild *)",
LANGEOF
) ;;
  esac

  cat > .claude/settings.json << PERMEOF
{
  "permissions": {
    "allow": [
      "Read",
      "Edit",
      "Write",
      "Glob",
      "Grep",
      "Bash",
$lang_rules
      "WebFetch(domain:*)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(curl * | bash)",
      "Bash(wget * | bash)",
      "Read(./.env)",
      "Read(./.env.*)"
    ]
  }
}
PERMEOF
  print_ok "Claude Code permissions configured (auto-accept safe operations)"

  # Install Development Guardrails for Claude Code
  # The framework uses a global clone at ~/.claude-dev-framework shared across
  # all projects. Its own init.sh handles per-project installation (hooks,
  # rules, manifest, settings.json).
  # MIT-licensed: https://github.com/kraulerson/claude-dev-framework
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"

  print_info "Installing Development Guardrails for Claude Code..."
  if command -v git &>/dev/null; then
    # Step 1: Check if framework is already installed; if so, pull latest
    local framework_valid=false
    if [ -d "$FRAMEWORK_CLONE/.git" ] && [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
      print_ok "Development Guardrails for Claude Code found at $FRAMEWORK_CLONE"
      # Pull latest to ensure we have the newest version
      print_info "Checking for updates..."
      if git -C "$FRAMEWORK_CLONE" pull --quiet 2>/dev/null; then
        print_ok "Development Guardrails up to date"
      else
        print_warn "Could not pull latest updates (network issue?) — using existing version"
      fi
      framework_valid=true
    fi

    # Step 2: If not installed, clone with retry
    if [ "$framework_valid" = false ]; then
      local clone_ok=false
      for _clone_try in 1 2; do
        print_info "Cloning Development Guardrails for Claude Code to $FRAMEWORK_CLONE (attempt $_clone_try/2)..."
        if git clone -q --depth 1 https://github.com/kraulerson/claude-dev-framework.git "$FRAMEWORK_CLONE" 2>/dev/null; then
          clone_ok=true
          break
        fi
        # Clean up partial clone before retry
        rm -rf "$FRAMEWORK_CLONE"
        if [ "$_clone_try" -lt 2 ]; then
          print_info "Clone failed, retrying..."
          sleep 2
        fi
      done

      # Verify clone produced expected files
      if [ "$clone_ok" = true ] && [ -d "$FRAMEWORK_CLONE/.git" ] && [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
        framework_valid=true
        print_ok "Development Guardrails for Claude Code cloned successfully"
      else
        rm -rf "$FRAMEWORK_CLONE"
        print_warn "Could not clone Development Guardrails for Claude Code after 2 attempts (network issue?)."
        print_warn "The fallback pre-commit hook will still be installed."
        print_warn "Install manually: git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework"
        print_warn "Then from your project: bash ~/.claude-dev-framework/scripts/init.sh"
      fi
    fi

    # Step 3: Run the framework's own init from the project directory
    if [ "$framework_valid" = true ]; then
      local branch
      branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
      local dev_os="$OS_TYPE"

      # Map platform to framework's target platform format
      local target_platform="$PLATFORM"
      case "$PLATFORM" in
        web)        target_platform="web" ;;
        desktop)    target_platform="$dev_os desktop" ;;
        mobile)     target_platform="iOS/Android" ;;
        mcp_server) target_platform="MCP server (JSON-RPC)" ;;
        *)          target_platform="$PLATFORM" ;;
      esac

      # Write pre-populated discovery JSON to temp file (avoids creating
      # .claude/ before framework init, which would trigger migration mode)
      local discovery_tmp
      discovery_tmp=$(mktemp)
      if command -v jq &>/dev/null; then
        jq -n \
          --arg branch "$branch" \
          --arg os "$dev_os" \
          --arg target "$target_platform" \
          --arg lang "$LANGUAGE" \
          --arg today "$(date +%Y-%m-%d)" \
          '{
            ("branch:" + $branch): {
              purpose: "main development branch",
              devOS: $os,
              targetPlatform: $target,
              buildTools: $lang
            },
            futurePlatforms: null,
            discoveryDate: $today,
            lastReviewDate: $today
          }' > "$discovery_tmp"
      fi

      # Map Solo Orchestrator platform to framework profile name.
      # CDF ships four profiles: web-app, web-api, desktop-app, mobile-app.
      # MCP servers are JSON-RPC services over stdio/HTTP — the closest
      # CDF profile is web-api, so we map mcp_server -> web-api
      # explicitly (no silent wildcard fall-through). The wildcard arm
      # remains as a defensive default for any future PLATFORM token
      # that arrives without a matching CDF profile. See
      # docs/platform-modules/mcp_server.md §2.1 for the rationale.
      local fw_profile
      case "$PLATFORM" in
        web)        fw_profile="web-app" ;;
        desktop)    fw_profile="desktop-app" ;;
        mobile)     fw_profile="mobile-app" ;;
        mcp_server) fw_profile="web-api" ;;
        *)
          fw_profile="web-api"
          print_warn "Unknown PLATFORM='$PLATFORM' — defaulting CDF profile to web-api. Add an explicit arm to init.sh to silence this warning."
          ;;
      esac

      # Run the framework's init with:
      #   --profile: select profile non-interactively (v4.1.0+)
      #   --prepopulate: skip interactive discovery interview (v4.0.0+)
      #   --skip-plugin-check: Superpowers/Context7 already checked above
      print_info "Running Development Guardrails init..."
      (cd "$PROJECT_DIR" && bash "$FRAMEWORK_CLONE/scripts/init.sh" \
        --profile "$fw_profile" --prepopulate "$discovery_tmp" --skip-plugin-check 2>&1) || {
        print_warn "Development Guardrails init encountered an issue."
        print_warn "You can run it manually later: bash ~/.claude-dev-framework/scripts/init.sh"
      }
      rm -f "$discovery_tmp"

      # Verify the framework init produced expected output
      if [ -f ".claude/manifest.json" ]; then
        print_ok "Development Guardrails for Claude Code installed and configured"

        # Remove the CDF migration backup. CDF backs up .claude/ before merging its
        # hooks — but Solo Orchestrator seeded .claude/ moments earlier in this same
        # init, so the backup contains no user work, and CDF only merges the hooks
        # key (nothing is overwritten). Leaving .claude-backup/ around looks like
        # load-bearing residue to new users.
        if [ -d ".claude-backup" ]; then
          rm -rf .claude-backup
          print_info "Removed CDF migration backup (not needed in Solo Orchestrator flow)"
        fi
      else
        print_warn "Development Guardrails init did not produce .claude/manifest.json"
        print_warn "Run manually: bash ~/.claude-dev-framework/scripts/init.sh"
      fi

      # Add orchestrator hooks to SessionStart (after CDF hooks are in place)
      if [ -f ".claude/settings.json" ] && command -v jq &>/dev/null; then
        local hooks_added=false
        # Add version check hook
        if jq -e '.hooks.SessionStart' .claude/settings.json >/dev/null 2>&1; then
          if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-version-check.sh"))' .claude/settings.json >/dev/null 2>&1; then
            jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
              && mv .claude/settings.json.tmp .claude/settings.json
            hooks_added=true
          fi
        else
          jq '.hooks.SessionStart = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi
        # Add test gate check hook
        if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-test-gate-check.sh"))' .claude/settings.json >/dev/null 2>&1; then
          jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-test-gate-check.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi
        # BL-109 S2: freshness check hook (Currency System, Layer 1 — detection).
        # Silent-when-current, zero-network, fail-open (exit 0 always), writes only
        # .claude/cache/. Injected exactly like session-version-check.sh above.
        if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-freshness-check.sh"))' .claude/settings.json >/dev/null 2>&1; then
          jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-freshness-check.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi
        # Add Qdrant reminder to Stop hook
        if jq -e '.hooks.Stop' .claude/settings.json >/dev/null 2>&1; then
          if ! jq -e '.hooks.Stop[0].hooks[] | select(.command | contains("session-end-qdrant-reminder.sh"))' .claude/settings.json >/dev/null 2>&1; then
            jq '.hooks.Stop[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-end-qdrant-reminder.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
              && mv .claude/settings.json.tmp .claude/settings.json
            hooks_added=true
          fi
        else
          jq '.hooks.Stop = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-end-qdrant-reminder.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi

        # Add pre-commit gate to PreToolUse hook (must target Bash matcher group)
        if jq -e '.hooks.PreToolUse' .claude/settings.json >/dev/null 2>&1; then
          if ! jq -e '.hooks.PreToolUse[]? | .hooks[]? | select(.command | contains("pre-commit-gate.sh"))' .claude/settings.json >/dev/null 2>&1; then
            # Find the Bash matcher group index, or create a new one
            BASH_INDEX=$(jq '[.hooks.PreToolUse[] | .matcher // "none"] | to_entries[] | select(.value == "Bash") | .key' .claude/settings.json 2>/dev/null | head -1 || echo "")
            if [ -n "$BASH_INDEX" ]; then
              jq ".hooks.PreToolUse[$BASH_INDEX].hooks += [{\"type\": \"command\", \"command\": \"bash \\\"\$CLAUDE_PROJECT_DIR\\\"/scripts/pre-commit-gate.sh\"}]" .claude/settings.json > .claude/settings.json.tmp \
                && mv .claude/settings.json.tmp .claude/settings.json
            else
              # No Bash matcher group exists — create one
              jq '.hooks.PreToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
                && mv .claude/settings.json.tmp .claude/settings.json
            fi
            hooks_added=true
          fi
        else
          jq '.hooks.PreToolUse = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi

        # Add MCP session gate to PreToolUse hook (targets Write and Edit)
        # This blocks file modifications until required MCP tools (qdrant-find, context7)
        # have been called — closing the session-start enforcement gap.
        for GATE_TOOL in Write Edit; do
          if ! jq -e ".hooks.PreToolUse[]? | select(.matcher == \"$GATE_TOOL\") | .hooks[]? | select(.command | contains(\"session-mcp-gate.sh\"))" .claude/settings.json >/dev/null 2>&1; then
            # Check if a matcher group for this tool already exists
            GATE_INDEX=$(jq "[.hooks.PreToolUse[] | .matcher // \"none\"] | to_entries[] | select(.value == \"$GATE_TOOL\") | .key" .claude/settings.json 2>/dev/null | head -1 || echo "")
            if [ -n "$GATE_INDEX" ]; then
              jq ".hooks.PreToolUse[$GATE_INDEX].hooks += [{\"type\": \"command\", \"command\": \"bash \\\"\$CLAUDE_PROJECT_DIR\\\"/scripts/session-mcp-gate.sh\"}]" .claude/settings.json > .claude/settings.json.tmp \
                && mv .claude/settings.json.tmp .claude/settings.json
            else
              jq ".hooks.PreToolUse += [{\"matcher\": \"$GATE_TOOL\", \"hooks\": [{\"type\": \"command\", \"command\": \"bash \\\"\$CLAUDE_PROJECT_DIR\\\"/scripts/session-mcp-gate.sh\"}]}]" .claude/settings.json > .claude/settings.json.tmp \
                && mv .claude/settings.json.tmp .claude/settings.json
            fi
            hooks_added=true
          fi
        done

        # Add tool usage tracking to PostToolUse hook
        if jq -e '.hooks.PostToolUse' .claude/settings.json >/dev/null 2>&1; then
          if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("track-tool-usage.sh"))' .claude/settings.json >/dev/null 2>&1; then
            jq '.hooks.PostToolUse[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
              && mv .claude/settings.json.tmp .claude/settings.json
            hooks_added=true
          fi
        else
          jq '.hooks.PostToolUse = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi

        # BL-029: bypass-detector PostToolUse + Stop. Always-on, regardless
        # of enforcement_level — Claude-side audit channel is non-configurable.
        if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("bypass-detector.sh"))' .claude/settings.json >/dev/null 2>&1; then
          jq '.hooks.PostToolUse[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi
        if ! jq -e '.hooks.Stop[0].hooks[]? | select(.command | contains("bypass-detector.sh"))' .claude/settings.json >/dev/null 2>&1; then
          jq 'if (.hooks.Stop // []) | length == 0
              then .hooks.Stop = [{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]
              else .hooks.Stop[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]
              end' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi

        # BL-030: PostToolUse hook for the Claude-commit recorder
        # (always-on). Records SHA of every successful Claude-issued
        # git commit into .claude/claude-commits.jsonl.
        if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("record-claude-commit.sh"))' .claude/settings.json >/dev/null 2>&1; then
          jq '.hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/record-claude-commit.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi

        # BL-030: SessionStart hook for the out-of-band detector. Self-
        # no-ops when enforcement_level=no; runs on light + strict to
        # surface user-terminal commits in .claude/bypass-audit.json.
        if ! jq -e '.hooks.SessionStart[0].hooks[]? | select(.command | contains("detect-out-of-band-commits.sh"))' .claude/settings.json >/dev/null 2>&1; then
          jq 'if (.hooks.SessionStart // []) | length == 0
              then .hooks.SessionStart = [{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/detect-out-of-band-commits.sh"}]}]
              else .hooks.SessionStart[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/detect-out-of-band-commits.sh"}]
              end' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi

        if [ "$hooks_added" = true ]; then
          print_ok "Session hooks installed (version check, test gate, MCP gate, Qdrant reminder, commit gate, tool tracking, bypass detector)"
        fi
      fi
    fi
  fi

  # Copy intake template
  cp "$SCRIPT_DIR/templates/project-intake.md" PROJECT_INTAKE.md

  # Pre-fill Section 1 with init data so user doesn't enter it twice
  local platform_module="None"
  case "$PLATFORM" in
    web) platform_module="SOI-PM-WEB" ;;
    desktop) platform_module="SOI-PM-DESKTOP" ;;
    mobile) platform_module="SOI-PM-MOBILE" ;;
    mcp_server) platform_module="SOI-PM-MCP" ;;
  esac
  local track_display
  track_display="$(echo "${TRACK:0:1}" | tr '[:lower:]' '[:upper:]')${TRACK:1}"
  local deployment_display
  deployment_display="$(echo "${DEPLOYMENT:0:1}" | tr '[:lower:]' '[:upper:]')${DEPLOYMENT:1}"

  sed -i.bak \
    -e "s~| \*\*Project name\*\* | |~| **Project name** | $PROJECT_NAME |~" \
    -e "s~| \*\*One-sentence description\*\* | _What does this do, in plain language?_ |~| **One-sentence description** | $PROJECT_DESCRIPTION |~" \
    -e "s~| \*\*Project track\*\* | Light / Standard / Full .*~| **Project track** | $track_display |~" \
    -e "s~| \*\*Platform type\*\* | Web / Desktop / Mobile / CLI / Other: .*~| **Platform type** | $PLATFORM |~" \
    -e "s~| \*\*Platform Module\*\* | SOI-PM-WEB / SOI-PM-DESKTOP / SOI-PM-MOBILE / None .*~| **Platform Module** | $platform_module |~" \
    -e "s~| \*\*Is this a personal project or organizational deployment?\*\* | Personal / Organizational |~| **Is this a personal project or organizational deployment?** | $deployment_display |~" \
    -e "s~__DATE__~$(date +%Y-%m-%d)~g" \
    PROJECT_INTAKE.md
  rm -f PROJECT_INTAKE.md.bak
  print_ok "Intake Section 1 pre-filled with project info"

  # Append tooling configuration summary to PROJECT_INTAKE.md
  if [ -n "${RESOLVER_OUTPUT:-}" ]; then
    append_intake_tooling_summary "$RESOLVER_OUTPUT"
  fi

  # BL-109-CURRENCY: capture the A1 render base for PROJECT_INTAKE.md HERE — at
  # the end of its render (cp template → sed pre-fill → tooling append) — so the
  # output sha is the render-time truth, never a post-hoc hash of a maybe-touched
  # file (a MAJOR per the verify focus). {template sha, rendered-output sha}.
  soif_currency_record_render_base A1 PROJECT_INTAKE.md \
    "$SCRIPT_DIR/templates/project-intake.md" PROJECT_INTAKE.md

  # Generate phase state tracking.
  # BL-073: `review_gate_enforced` is the grandfather cutover for the
  # track-aware Phase 3→4 review-manifest gate. init.sh stamps it `true`
  # at creation, so every project CREATED after BL-073 ships is subject to
  # the track-aware FAIL (see scripts/check-phase-gate.sh review-manifest
  # block). Projects created BEFORE BL-073 lack the field entirely — the
  # gate reads its absence as "grandfathered" and keeps the legacy
  # WARN-only behavior, so a pre-existing project is never retroactively
  # blocked. upgrade-project.sh re-stamps it on any tier advance.
  print_info "Generating phase state..."
  mkdir -p .claude
  local poc_json="null"
  [ -n "$POC_MODE" ] && poc_json="\"$POC_MODE\""
  cat > .claude/phase-state.json << PHEOF
{
  "project": "$PROJECT_NAME",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$TRACK",
  "deployment": "$DEPLOYMENT",
  "poc_mode": $poc_json,
  "compliance_ready": false,
  "review_gate_enforced": true,
  "gates": {
    "phase_0_to_1": null,
    "phase_1_to_2": null,
    "phase_2_to_3": null,
    "phase_3_to_4": null
  }
}
PHEOF

  # Store orchestrator source path for verify-install.sh remediation
  if command -v jq &>/dev/null; then
    jq -n --arg s "$SCRIPT_DIR" '{source_dir: $s}' > .claude/orchestrator-source.json
    print_ok "Orchestrator source path stored"
  fi

  # Generate initial build progress tracking
  cat > .claude/build-progress.json << BPEOF
{
  "features_completed": [],
  "features_since_last_test": 0,
  "features_since_last_health_check": 0,
  "test_interval": $TEST_INTERVAL,
  "last_test_session": null,
  "testing_required": false,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 0
}
BPEOF
  print_ok "Build progress tracking initialized (test interval: every $TEST_INTERVAL features)"

  # Generate process state file for enforcement
  cat > .claude/process-state.json << 'PSEOF'
{
  "build_loop": {
    "feature": null,
    "step": 0,
    "steps_completed": [],
    "started_at": null
  },
  "uat_session": {
    "session_id": null,
    "step": 0,
    "steps_completed": [],
    "started_at": null
  },
  "phase3_validation": {
    "steps_completed": [],
    "started_at": null
  },
  "phase4_release": {
    "steps_completed": [],
    "started_at": null
  },
  "phase2_init": {
    "steps_completed": [],
    "verified": false
  }
}
PSEOF

  # Generate tool usage tracking file
  cat > .claude/tool-usage.json << 'TUEOF'
{
  "session_id": null,
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false
}
TUEOF

  # Write tool-preferences.json (from resolver output stored earlier)
  if [ -n "${RESOLVER_OUTPUT:-}" ]; then
    write_tool_preferences "$RESOLVER_OUTPUT" "$RESOLVER_DEV_OS" "$PROJECT_DIR"
    print_ok "Tool preferences written to .claude/tool-preferences.json"
  fi

  # Configure Qdrant MCP with per-project collection (isolates semantic memory)
  # If Qdrant container is running but MCP isn't registered yet, register it now.
  # Then write a project-local override using the project name as the collection.
  if command -v jq &>/dev/null; then
    local _qd_global=false
    if is_qdrant_mcp_registered; then
      _qd_global=true
    elif is_qdrant_container_running && command -v uvx &>/dev/null; then
      print_info "Registering Qdrant MCP server..."
      if register_qdrant_mcp; then
        print_ok "Qdrant MCP registered"
        _qd_global=true
      fi
    fi

    if [ "$_qd_global" = true ]; then
      cat > .claude/settings.local.json << QDEOF
{
  "mcpServers": {
    "qdrant": {
      "command": "uvx",
      "args": [
        "mcp-server-qdrant",
        "--qdrant-url", "http://localhost:6333",
        "--collection-name", "$PROJECT_NAME"
      ]
    }
  }
}
QDEOF
      print_ok "Qdrant MCP configured with project-specific collection: $PROJECT_NAME"
    fi
  fi

  # Generate CLAUDE.md
  print_info "Generating CLAUDE.md..."
  generate_claude_md

  # Generate Approval Log
  print_info "Generating APPROVAL_LOG.md..."
  generate_approval_log

  # Generate .gitignore
  print_info "Generating .gitignore..."
  generate_gitignore

  # Generate CI pipeline (language-specific)
  print_info "Generating CI pipeline..."
  generate_ci

  # Generate release pipeline (platform-specific)
  print_info "Generating release pipeline..."
  generate_release

  # Install fallback pre-commit hook
  # This provides a baseline enforcement floor (secret detection + test co-location)
  # independent of whether the Development Guardrails clone succeeded.
  # If the Development Guardrails are installed and activate their own hooks, those
  # will provide deeper coverage. This hook remains as the safety net.
  print_info "Installing pre-commit hook..."
  install_precommit_hook

  # --- Atomic initial-state preparation (code-init-sh-6) ---
  # Pre-fix, BL-030 state files (manifest enforcement_level/deployment/poc_mode,
  # bypass-audit.json init row, filesystem gate) and the host-manifest seed
  # (host/mode/remote_url) were written AFTER the initial git commit. The chore-
  # init commit captured none of them, leaving a half-initialized state on every
  # init (especially severe on create_and_protect_remote failure, since BL-030
  # writes happened unconditionally on top of the failed-remote state).
  #
  # Lay everything down BEFORE the initial commit so a single atomic commit
  # captures the entire framework-managed state. Post-remote writes (remote_url
  # update, attestation, phase2_init steps) are captured by finalize_init_commit
  # below as a second commit when present.
  prepare_initial_state_for_commit

  git add -A
  # Skip hooks for the initial commit — template files trigger false positives
  # in Semgrep/gitleaks. Hooks will enforce on all subsequent commits.
  git commit -q --no-verify -m "chore: initialize Solo Orchestrator project

Project: $PROJECT_NAME
Platform: $PLATFORM
Track: $TRACK
Framework: Solo Orchestrator v1.0"

  # Refresh the BL-030 detection baseline to the chore-init commit. The file
  # is gitignored (templates/generated/gitignore-base.tmpl), so updating it
  # post-commit does NOT dirty the working tree.
  ( git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt ) || true

  # --- Host-aware repo creation (spec 2026-04-21 host-aware repo gate) ---
  # Reads git_host + repo_visibility from intake-progress.json (set by
  # intake-wizard.sh). If absent, prompts inline. Creates remote, registers
  # origin, pushes initial commit, configures branch protection, verifies.
  # Writes host/mode/remote_url to .claude/manifest.json.
  #
  # UAT 2026-04-25 fix (U-B): if remote creation fails (push to fake URL,
  # missing CLI, API 403, etc.) DO NOT abort init.sh via set -e. Continue
  # to verify-install + print_next_steps so the project is still usable
  # and the orchestrator gets clear remediation guidance via check-gate.sh.
  if ! create_and_protect_remote; then
    echo ""
    print_warn "Remote setup did not complete cleanly."
    print_info "Project files are in place; remote push/protection is the gap."
    print_info "Remediate when ready:"
    print_info "  scripts/check-gate.sh --backfill-host    # if .claude/manifest.json lacks 'host'"
    print_info "  scripts/check-gate.sh --repair           # to re-create remote and protection"
    print_info "  scripts/check-gate.sh --preflight        # to verify the remote is correctly set up"
    echo ""
    # BL-064: record the host-setup failure so main()'s exit-time check
    # prints "Setup INCOMPLETE" instead of "Setup Complete" and returns
    # non-zero. Without this, the print_fail lines emitted inside
    # create_and_protect_remote would be silently absorbed by `if !` and
    # the operator would see rc=0 + a success banner. The summary cites
    # the phase rather than each individual [FAIL] message — the lines
    # themselves are already on stdout above; the summary's job is to
    # surface that at least one phase failed so an operator scanning only
    # the tail of the log still sees the gap.
    record_init_failure "Host repo setup (create_and_protect_remote) — see [FAIL] lines above; remediate with scripts/check-gate.sh --repair"
  fi

  # If create_and_protect_remote wrote new state (manifest.remote_url update,
  # attestation, phase2_init.steps_completed), commit it as a second "finalize"
  # commit so the working tree stays clean. No-op when nothing changed (e.g.
  # --no-remote-creation, which set remote_url during prepare_initial_state).
  finalize_init_commit

  echo ""
  print_ok "Project created at $PROJECT_DIR"
}

# ================================================================
# Host-Aware Repo Creation (spec 2026-04-21)
# ================================================================
create_and_protect_remote() {
  # Host/visibility/mode are pre-resolved by prepare_initial_state_for_commit
  # and exported as _RESOLVED_HOST / _RESOLVED_VISIBILITY / _RESOLVED_MODE so
  # the manifest can be written BEFORE the chore-init commit. We use those
  # values here (the manifest.host/manifest.mode are already in HEAD).
  local host="$_RESOLVED_HOST"
  local visibility="$_RESOLVED_VISIBILITY"
  local mode="$_RESOLVED_MODE"

  # Audit finding specs-plans-host-aware-2: write phase2_init.steps_completed
  # INCREMENTALLY after each successful host_ call so a mid-flight failure
  # leaves accurate partial state for scripts/check-gate.sh --repair to
  # consult (see check-gate.sh::cmd_repair). The four named steps in order:
  #   remote_repo_created          — after host_create_repo + register
  #   pushed_initial               — after host_push_initial
  #   branch_protection_configured — after host_configure_protection (or attestation)
  #   branch_protection_verified   — after host_verify_protection passes
  #
  # PR #97 verifier follow-up: _record_phase2_step lives in
  # scripts/lib/phase2-state.sh so check-gate.sh::cmd_repair writes through
  # the same helper after a successful resume step (the original inner-
  # function placement made it invisible to check-gate.sh).
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/scripts/lib/phase2-state.sh"

  # T2-B: --no-remote-creation skips the host API entirely so UAT/CI runs do
  # not contaminate the user's GitHub/GitLab/Bitbucket account. Manifest already
  # has host + mode from the T2-C block above; record empty remote_url and
  # tell the user how to attach a remote later.
  if [ "${NO_REMOTE_CREATION:-false}" = true ]; then
    print_step "Skipping remote creation (--no-remote-creation)"
    print_info "No remote will be created on $host."
    print_info "Project files are scaffolded; .claude/manifest.json records host='$host', mode='$mode'."
    print_info "When ready, attach a remote and apply protection with:"
    print_info "  scripts/check-gate.sh --repair"
    jq --arg u "" '.remote_url = $u' .claude/manifest.json > .claude/manifest.json.tmp \
       && mv .claude/manifest.json.tmp .claude/manifest.json
    return 0
  fi

  print_step "Creating git repository on $host"

  local remote_url=""
  if [ "$host" = "other" ]; then
    # URL-paste path — no CLI, no API verification.
    # BL-016: prefer the non-interactive top-level REMOTE_URL when set.
    if [ -n "${REMOTE_URL:-}" ]; then
      remote_url="$REMOTE_URL"
    else
      read -rp "Paste the HTTPS clone URL of the remote repo you've created: " remote_url # lint-raw-read-prompt: allow init.sh interactive-only "other host" URL paste; gated by REMOTE_URL env-var fast-path at line 1952 above for non-interactive callers (BL-016)
    fi
    [ -z "$remote_url" ] && { print_fail "Remote URL required for 'other' host"; return 1; }
    git remote add origin "$remote_url"
    _record_phase2_step "remote_repo_created"

    # BL-024: record attestation BEFORE the push attempt. Attestation is a
    # forward-looking commitment ("I will configure protection on this remote")
    # — it does not depend on push success. Pre-fix, push happened first and
    # any push failure (corporate firewall, fake URL for testing, connectivity
    # blip) returned 1 before attestation was written, silently dropping the
    # operator's commitment.
    echo ""
    echo "Since 'other' host is not API-verifiable, attest branch protection:"
    echo "  - Force-push disabled on main"
    echo "  - Admins not exempt from rules"
    [ "$mode" = "org" ] && echo "  - PR reviews required (at least 1 approver)"
    local attest
    # BL-016: prefer non-interactive BRANCH_PROTECTION_ATTESTED when set.
    if [ "${BRANCH_PROTECTION_ATTESTED:-false}" = true ]; then
      attest="yes"
      print_info "Branch protection attested via --branch-protection-attested flag."
    else
      read -rp "Has branch protection been configured per the above? [type 'yes' to attest]: " attest # lint-raw-read-prompt: allow init.sh interactive-only attestation; gated by BRANCH_PROTECTION_ATTESTED env-var fast-path at line 1973 above for non-interactive callers (BL-016)
    fi
    [ "$attest" != "yes" ] && { print_fail "Attestation required — cannot proceed to Phase 0"; return 1; }
    # Record attestation in process-state.json (BEFORE push — see BL-024 above).
    mkdir -p .claude
    if [ ! -f .claude/process-state.json ]; then
      echo '{"phase2_init":{"steps_completed":[],"attestations":{}}}' > .claude/process-state.json
    fi
    jq --arg at "$(date -u +%FT%TZ)" \
       '.phase2_init.attestations.branch_protection = {attested_by: "orchestrator", at: $at}' \
       .claude/process-state.json > .claude/process-state.json.tmp \
       && mv .claude/process-state.json.tmp .claude/process-state.json
    # Attestation IS the verification step for 'other' host (manual contract).
    _record_phase2_step "branch_protection_configured"
    _record_phase2_step "branch_protection_verified"

    # Push happens AFTER attestation so a push failure cannot drop the
    # attestation (BL-024). The attestation we just wrote persists for
    # check-gate.sh --repair / --preflight to honor regardless of the
    # outcome below.
    #
    # BL-084: TIER-AWARE handling of a FAILED initial push on the
    # bring-your-own-host path. A prior draft made EVERY 'other'-host push
    # failure a silent success (return 0) — that re-opened the project's #1
    # defect class (BL-064 silent-success: init says "Setup Complete" while
    # the code was never uploaded). Instead we thread the needle on the actual
    # project TIER (deployment + poc_mode, via _bl084_tier_bypassable — NOT
    # `track`, which a sponsored/production project can carry as light):
    #
    #   • NON-bypassable tier (POC-Sponsored / Production — deployment=
    #     organizational OR poc_mode=sponsored_poc): a working remote is
    #     MANDATORY. A failed push is a hard failure — no local-only, no
    #     deferral, no flag helps. return 1 → the outer caller records an init
    #     failure → init prints "Setup INCOMPLETE" + exits 2.
    #
    #   • BYPASSABLE tier (Personal / POC-Personal — deployment=personal AND
    #     poc_mode≠sponsored_poc): the operator MAY proceed, but ONLY with an
    #     EXPLICIT, on-the-record acknowledgment of the risk (never a silent
    #     pass). Two acknowledged outcomes both exit 0:
    #       - --accept-local-only-risk : keep the project LOCAL (no remote),
    #         accept the data-loss risk. Recorded as local_only_acknowledged.
    #       - --defer-remote-push      : push manually later. Recorded as
    #         push_deferred_acknowledged — and the Phase 1→2 gate WILL block
    #         until the remote actually has the branch (check-phase-gate.sh
    #         BL-084 push-verification backstop).
    #     Absent a flag (non-interactive) or a "yes" (interactive), a
    #     bypassable-tier push failure is STILL a real failure (default = no
    #     silent success): print_fail + return 1.
    #
    # Eligibility is decided by _bl084_tier_bypassable (keyed on deployment +
    # poc_mode, NOT `track` — a sponsored/production project can carry
    # track=light non-interactively). The `# BL-084-TIER-GATE` marker below is
    # a mutation-proof target: removing the non-bypassable hard-fail branch
    # flips the Sponsored/Production hard-fail tests RED; reverting
    # _bl084_tier_bypassable to trust `track` flips the sponsored/production
    # `--track light` bypass tests RED.
    if ! git push -u origin main 2>/dev/null && ! git push -u origin master 2>/dev/null; then
      if ! _bl084_tier_bypassable; then  # BL-084-TIER-GATE
        # NON-bypassable tier (POC-Sponsored / Production).
        print_fail "Push failed — a working remote is MANDATORY for POC-Sponsored / Production (organizational or sponsored_poc) projects. Local-only and deferred-push are NOT permitted for this tier."  # lint-fail-emit-exit-status: allow BL-084 sponsored/production hard-fail — the `return 1` below (after 2 remediation-hint lines) propagates to record_init_failure + non-zero exit
        print_info "Create/repair the remote and re-run, or remediate with:"
        print_info "  scripts/check-gate.sh --repair     # re-attempt push + verify protection"
        return 1
      else
        # BYPASSABLE tier (Personal / POC-Personal).
        if [ "${ACCEPT_LOCAL_ONLY_RISK:-false}" = true ]; then
          print_warn "Push failed — proceeding LOCAL-ONLY at your explicit request (--accept-local-only-risk)."
          print_warn "DATA-LOSS RISK: this project has NO remote. A lost/failed disk loses ALL work. You accepted this."
          _record_remote_ack "local_only_acknowledged" "initial push to '$remote_url' failed; operator accepts local-only operation and the data-loss risk"
          # Legitimate operator choice, on the record — NOT a masked failure.
          # Deliberately do NOT record pushed_initial (no push happened).
        elif [ "${DEFER_REMOTE_PUSH:-false}" = true ]; then
          print_warn "Push failed — DEFERRING the push at your explicit request (--defer-remote-push)."
          print_warn "You MUST push before advancing Phase 1→2 — the gate WILL block you until the remote has the branch."
          print_info "  git push -u origin main            # then verify with:"
          print_info "  scripts/check-gate.sh --preflight"
          _record_remote_ack "push_deferred_acknowledged" "initial push to '$remote_url' failed; operator will push manually before Phase 1→2"
          # Deferral is on the record — init may exit 0, but the Phase 1→2
          # gate enforces the eventual push. Do NOT record pushed_initial.
        elif [ "$NON_INTERACTIVE" != true ]; then
          # Interactive bypassable-tier: prompt, default = do NOT proceed.
          echo ""
          print_warn "Push to the remote failed (URL may be wrong, repo not yet created, or a proxy blocked it)."
          echo "  This is a REAL failure. This is a Personal / POC-Personal project, so you MAY proceed anyway — at your own risk:"
          echo "    [l] local-only  — keep the project LOCAL forever, accept DATA-LOSS risk"
          echo "    [d] defer       — push manually later (the Phase 1→2 gate will block until you do)"
          echo "    [N] abort       — treat as a failure (default)"
          local _push_choice
          read -rp "Proceed anyway? [l/d/N]: " _push_choice # lint-raw-read-prompt: allow init.sh interactive-only bypassable-tier push-failure escape prompt; non-interactive callers use --accept-local-only-risk / --defer-remote-push (gated by NON_INTERACTIVE check above)
          case "$_push_choice" in
            l|L)
              print_warn "Proceeding LOCAL-ONLY — DATA-LOSS RISK accepted."
              _record_remote_ack "local_only_acknowledged" "initial push to '$remote_url' failed; operator accepts local-only operation and the data-loss risk (interactive)"
              ;;
            d|D)
              print_warn "DEFERRING the push — the Phase 1→2 gate will block until the remote has the branch."
              _record_remote_ack "push_deferred_acknowledged" "initial push to '$remote_url' failed; operator will push manually before Phase 1→2 (interactive)"
              ;;
            *)
              print_fail "Push failed — verify URL and credentials (no acknowledged escape chosen)."
              return 1
              ;;
          esac
        else
          # Non-interactive bypassable-tier with NO escape flag: real failure.
          print_fail "Push failed — verify URL and credentials."  # lint-fail-emit-exit-status: allow BL-084 bypassable-tier default failure — the `return 1` below (after 3 escape-flag-hint lines) propagates to record_init_failure + non-zero exit
          print_info "This is a real failure. To proceed anyway (Personal / POC-Personal only), re-run with ONE of:"
          print_info "  --accept-local-only-risk   # keep the project local, accept the data-loss risk"
          print_info "  --defer-remote-push        # push manually later (Phase 1→2 gate blocks until you do)"
          return 1
        fi
      fi
    else
      _record_phase2_step "pushed_initial"
    fi
  else
    # First-class host: dispatcher + driver
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/scripts/lib/host.sh"
    source "$SCRIPT_DIR/scripts/host-drivers/$host.sh"

    host_require_cli || { print_fail "Host CLI prerequisite failed — see messages above"; return 1; }

    print_info "Creating $visibility repo '$PROJECT_NAME' on $host..."
    remote_url=$(host_create_repo "$PROJECT_NAME" "$visibility") || { print_fail "Repo creation failed"; return 1; }
    print_ok "Remote created at $remote_url"

    host_register_remote "$remote_url"
    _record_phase2_step "remote_repo_created"

    print_info "Pushing initial commit..."
    # Try main first, fall back to master
    host_push_initial main 2>/dev/null || host_push_initial master || { print_fail "Push failed — $remote_url exists but empty"; return 1; }
    _record_phase2_step "pushed_initial"

    print_info "Configuring branch protection ($mode mode)..."
    # BL-002 / BL-031 / BL-032: exit codes 3 and 4 are both host-agnostic
    # "expected partial failure — attestation fallback is appropriate"
    # signals. The github driver returns 3 on free-tier 403; the gitlab
    # driver returns 3 on a generic approvals PUT failure and 4 on the
    # specific Premium-only failure (BL-032 / code-host-gitlab-8). Both
    # route to the same attestation flow — the driver itself emits host-
    # specific remediation on stderr BEFORE this block runs, so we echo a
    # host-agnostic summary and defer detail to the driver (BL-031).
    #
    # BL-032 proactive attestation: when --approvals-attested is set (or
    # the SOLO_APPROVALS_ATTESTED=1 env var is exported by an outer
    # harness), the gitlab driver skips the approvals PUT entirely and
    # emits a WARN pointing operators at Settings > Merge requests.
    # host_configure_protection returns 0, so we take the success branch
    # below and record the `gitlab_free_tier_approvals` reason separately.
    if [ "${APPROVALS_ATTESTED:-false}" = true ]; then
      export SOLO_APPROVALS_ATTESTED=1
    fi
    local _hcp_rc=0
    host_configure_protection main "$mode" || _hcp_rc=$?
    if [ "$_hcp_rc" -ne 0 ] && [ "$_hcp_rc" -ne 3 ] && [ "$_hcp_rc" -ne 4 ]; then
      _hcp_rc=0
      host_configure_protection master "$mode" || _hcp_rc=$?
    fi

    if [ "$_hcp_rc" -eq 3 ] || [ "$_hcp_rc" -eq 4 ]; then
      print_warn "Branch protection unavailable via standard API on this $host repo."
      print_info "Falling back to attestation flow — see $host driver remediation message above."
      local attest
      if [ "${BRANCH_PROTECTION_ATTESTED:-false}" = true ]; then
        attest="yes"
        print_info "Branch protection attested via --branch-protection-attested flag."
      else
        read -rp "Attest that protection will be enforced manually? [type 'yes' to attest]: " attest # lint-raw-read-prompt: allow init.sh interactive-only attestation (manual-enforcement branch); gated by BRANCH_PROTECTION_ATTESTED env-var fast-path at line 2038 above for non-interactive callers (BL-016)
      fi
      [ "$attest" != "yes" ] && { print_fail "Attestation required — cannot proceed (see $host driver remediation above)"; return 1; }
      # Record attestation with the github_free_tier reason so check-gate.sh
      # --preflight skips the API verify. The reason string is retained for
      # backward compat with check-gate.sh and tests/test-check-gate.sh::T5;
      # broadening the reason taxonomy is out of scope for BL-031 (UX-only
      # fix). Downstream code reads the reason as a "skip API verify" sentinel
      # regardless of host, so the wording is harmless for non-github paths.
      mkdir -p .claude
      if [ ! -f .claude/process-state.json ]; then
        echo '{"phase2_init":{"steps_completed":[],"attestations":{}}}' > .claude/process-state.json
      fi
      jq --arg at "$(date -u +%FT%TZ)" \
         '.phase2_init.attestations.branch_protection = {attested_by: "orchestrator", at: $at, reason: "github_free_tier"}' \
         .claude/process-state.json > .claude/process-state.json.tmp \
         && mv .claude/process-state.json.tmp .claude/process-state.json
      print_ok "Partial-protection attestation recorded — check-gate.sh --preflight will honor it."
      # Tier-limited attestation IS the configured + verified state for this host
      # (per spec category 6 / BL-002). Record both steps so --repair short-circuits.
      _record_phase2_step "branch_protection_configured"
      _record_phase2_step "branch_protection_verified"
    elif [ "$_hcp_rc" -ne 0 ]; then
      print_fail "Protection config failed — run 'scripts/check-gate.sh --repair' after troubleshooting"
      return 1
    else
      _record_phase2_step "branch_protection_configured"
      # BL-032 proactive path: when the operator pre-attested with
      # --approvals-attested AND we're on gitlab in org mode, the driver
      # took the SOLO_APPROVALS_ATTESTED shortcircuit (skipped the
      # approvals PUT + emitted a WARN). Record the
      # `gitlab_free_tier_approvals` attestation so check-gate.sh +
      # check-phase-gate.sh honor it as the gate-pass. The
      # host_verify_protection call below would still succeed on gitlab
      # for the protected_branches half of the config, but the
      # attestation IS the load-bearing gate on the approvals half —
      # match the reactive-path discipline.
      if [ "${APPROVALS_ATTESTED:-false}" = true ] && [ "$host" = "gitlab" ] && [ "$mode" = "org" ]; then
        mkdir -p .claude
        if [ ! -f .claude/process-state.json ]; then
          echo '{"phase2_init":{"steps_completed":[],"attestations":{}}}' > .claude/process-state.json
        fi
        jq --arg at "$(date -u +%FT%TZ)" \
           '.phase2_init.attestations.branch_protection = {attested_by: "orchestrator", at: $at, reason: "gitlab_free_tier_approvals"}' \
           .claude/process-state.json > .claude/process-state.json.tmp \
           && mv .claude/process-state.json.tmp .claude/process-state.json
        print_ok "GitLab Free tier approvals attestation recorded (reason: gitlab_free_tier_approvals) — check-gate.sh --preflight will honor it."
      fi
      print_info "Verifying protection..."
      if ! host_verify_protection main "$mode" 2>/dev/null && ! host_verify_protection master "$mode"; then
        # Retry once for API lag
        sleep 10
        if ! host_verify_protection main "$mode" 2>/dev/null && ! host_verify_protection master "$mode"; then
          print_fail "Verification failed — run 'scripts/check-gate.sh --repair'"
          return 1
        fi
      fi
      print_ok "Protection verified for $mode mode"
      _record_phase2_step "branch_protection_verified"
    fi
  fi

  # Write host + mode + remote_url to .claude/manifest.json (create if absent)
  mkdir -p .claude
  if [ -f .claude/manifest.json ]; then
    jq --arg h "$host" --arg m "$mode" --arg u "$remote_url" \
       '.host = $h | .mode = $m | .remote_url = $u' \
       .claude/manifest.json > .claude/manifest.json.tmp \
       && mv .claude/manifest.json.tmp .claude/manifest.json
  else
    cat > .claude/manifest.json <<MANIFESTEOF
{"host": "$host", "mode": "$mode", "remote_url": "$remote_url"}
MANIFESTEOF
  fi

  # BL-099: birth-stamp .claude/manifest.json.soloFrameworkCommit — the
  # solo-orchestrator framework commit this project was scaffolded from. This
  # is the pin scripts/upgrade-project.sh --sync-framework advances and reports
  # drift against. camelCase and deliberately named to sit BESIDE — never be
  # confused with — CDF's `frameworkCommit`, which pins the SEPARATE Development
  # Guardrails clone. Stamped UNCONDITIONALLY after the manifest if/else (not
  # inside either branch — the jq-merge branch is the common CDF-created path).
  # Skipped with a note when the framework dir isn't a git checkout (e.g. a
  # tarball install), leaving the field absent (sync treats absent as unpinned).
  if git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    _solo_fw_commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")"
    if [ -n "$_solo_fw_commit" ]; then
      jq --arg c "$_solo_fw_commit" '.soloFrameworkCommit = $c' .claude/manifest.json > .claude/manifest.json.tmp \
        && mv .claude/manifest.json.tmp .claude/manifest.json
    fi
    unset _solo_fw_commit
  else
    print_info "solo-orchestrator framework dir is not a git checkout — skipping soloFrameworkCommit birth-stamp"
  fi

  # Trailing dedup pass. The named steps (remote_repo_created, pushed_initial,
  # branch_protection_configured, branch_protection_verified) are now written
  # incrementally above via _record_phase2_step after each successful host_
  # call. The single batched write that used to live here was the spec drift
  # closed by audit finding specs-plans-host-aware-2 — it left no
  # intermediate state for scripts/check-gate.sh --repair to resume from.
  if [ ! -f .claude/process-state.json ]; then
    echo '{"phase2_init":{"steps_completed":[]}}' > .claude/process-state.json
  fi
  jq '.phase2_init.steps_completed = ((.phase2_init.steps_completed // []) | unique)' \
     .claude/process-state.json > .claude/process-state.json.tmp \
     && mv .claude/process-state.json.tmp .claude/process-state.json
}

# ================================================================
# Pre-Commit Hook (Fallback Enforcement)
# ================================================================
install_precommit_hook() {
  mkdir -p .git/hooks

  # BL-099: the fallback pre-commit hook body is generated by the shared
  # soif_write_precommit_hook (scripts/lib/hook-templates.sh) so init.sh and
  # scripts/upgrade-project.sh --sync-framework emit byte-identical hooks. The
  # language->test-pattern table also lives there (soif_lang_test_pattern).
  local test_pattern
  test_pattern="$(soif_lang_test_pattern "$LANGUAGE")"

  soif_write_precommit_hook ".git/hooks/pre-commit"
  print_ok "Pre-commit hook installed (gitleaks + Semgrep + schema migration checks)"

  # BL-072 Phase C2: install the tier-keyed TDD-ordering gate as a COMMIT-MSG
  # hook -- the only git-hook point where .git/COMMIT_EDITMSG holds the CURRENT
  # commit message (a pre-commit hook sees a stale message) and the staged index
  # is intact. Skipped for languages with no distinct test-file convention (Rust
  # uses inline #[cfg(test)] tests), matching the old inline check's scope: the
  # gate fires iff soif_lang_test_pattern returned a non-empty pattern (every
  # language with a pattern also had a non-empty src_ext, so the old
  # `[ -n "$test_pattern" ] && [ -n "$src_ext" ]` reduces to this).
  if [ -n "$test_pattern" ]; then
    install_tdd_commit_msg_hook
  fi
}

# install_tdd_commit_msg_hook — idempotently add a managed block to
# .git/hooks/commit-msg that delegates to the framework gate's two message-scoped
# commit-msg enforcers (`pre-commit-gate.sh --terminal-mode --tdd-only`): the
# tier-keyed TDD-ordering gate (BL-072 C2) AND the BL-006 Build-Loop
# commit-message check (BL-010) — the latter extends BL-006 to editor-opened /
# human-terminal commits, which the AI-only PreToolUse hook cannot reach. A
# non-zero exit aborts the commit. Composes with an existing commit-msg hook via
# a marked block; graceful no-op if the gate script is absent at commit time.
install_tdd_commit_msg_hook() {
  local hook=".git/hooks/commit-msg"
  # BL-099: markers + block body come from the shared hook-templates lib
  # (SOIF_TDD_OPEN / soif_emit_tdd_commitmsg_block) so init.sh and the sync
  # path stay byte-identical. Emission is unchanged from the pre-refactor
  # inline `{ echo ""; echo "$mark_open"; ... }` — proven byte-for-byte.
  mkdir -p .git/hooks
  if [ ! -f "$hook" ]; then
    printf '%s\n' '#!/usr/bin/env bash' > "$hook"
  fi
  if grep -qF "$SOIF_TDD_OPEN" "$hook" 2>/dev/null; then
    chmod +x "$hook"
    print_ok "TDD ordering gate already present in commit-msg hook (idempotent)"
    return 0
  fi
  soif_emit_tdd_commitmsg_block >> "$hook"
  chmod +x "$hook"
  print_ok "TDD ordering gate installed (commit-msg hook, tier-keyed hard block)"
}

# ================================================================
# Template Generators
# ================================================================
generate_claude_md() {
  sed -e "s|__PROJECT_NAME__|$PROJECT_NAME|g" \
      -e "s|__PROJECT_DESCRIPTION__|$PROJECT_DESCRIPTION|g" \
      -e "s|__PLATFORM__|$PLATFORM|g" \
      -e "s|__TRACK__|$TRACK|g" \
      -e "s|__LANGUAGE__|$LANGUAGE|g" \
      -e "s|__TEST_INTERVAL__|$TEST_INTERVAL|g" \
      "$SCRIPT_DIR/templates/generated/claude-md.tmpl" > CLAUDE.md

  # Add compliance note for organizational deployments
  if [ "$DEPLOYMENT" = "organizational" ]; then
    cat >> CLAUDE.md << 'COMPEOF'

### Branch Protection (Organizational Deployments)
Branch protection with required reviewers is recommended for organizational deployments and will be required when compliance modules are available. Until then, the Orchestrator creates and merges their own PRs with phase gate review at milestones. When branch protection is enabled, PRs require an independent reviewer before merge — this provides per-change code review that strengthens the governance audit trail.
COMPEOF
  fi

  # BL-109-CURRENCY: capture the A1 render base for CLAUDE.md HERE — at the end of
  # its render (sed substitution + the conditional organizational append) — so the
  # output sha is the render-time truth, never a post-hoc hash (a MAJOR per the
  # verify focus). {template sha, rendered-output sha}.
  soif_currency_record_render_base A1 CLAUDE.md \
    "$SCRIPT_DIR/templates/generated/claude-md.tmpl" CLAUDE.md
}

generate_approval_log() {
  local today
  today=$(date +%Y-%m-%d)

  if [ "$DEPLOYMENT" = "organizational" ]; then
    sed -e "s|__PROJECT_NAME__|$PROJECT_NAME|g" \
        -e "s|__TODAY__|$today|g" \
        "$SCRIPT_DIR/templates/generated/approval-log-org.tmpl" > APPROVAL_LOG.md
  else
    sed -e "s|__PROJECT_NAME__|$PROJECT_NAME|g" \
        -e "s|__TODAY__|$today|g" \
        "$SCRIPT_DIR/templates/generated/approval-log-personal.tmpl" > APPROVAL_LOG.md
  fi
}

generate_gitignore() {
  cp "$SCRIPT_DIR/templates/generated/gitignore-base.tmpl" .gitignore

  # BL-109 S2 (Currency System, Layer 1): the session-start freshness detector's
  # atomic cache (snooze store + warm-cache marker). Operational state, never
  # project content — invariant I7 confines detection's only project-tree write
  # to `.claude/cache/`, which must therefore be gitignored so it never dirties
  # the tree or shows up as a diff.
  cat >> .gitignore << 'CACHEEOF'

# BL-109 freshness detector cache (session-start Currency System state)
.claude/cache/
CACHEEOF

  # Add platform-specific ignores
  case "$PLATFORM" in
    desktop)
      cat >> .gitignore << 'DEOF'

# Desktop build artifacts
src-tauri/target/
release/
*.exe
*.dmg
*.AppImage
*.deb
*.msi
DEOF
      ;;
    mobile)
      cat >> .gitignore << 'MEOF'

# Mobile
ios/Pods/
*.ipa
*.apk
*.aab
android/.gradle/
android/app/build/
MEOF
      ;;
  esac

  # Add language-specific ignores
  case "$LANGUAGE" in
    python)
      cat >> .gitignore << 'PYEOF'

# Python
venv/
*.pyc
__pycache__/
.mypy_cache/
.pytest_cache/
*.egg-info/
dist/
build/
PYEOF
      ;;
    rust)
      cat >> .gitignore << 'RSEOF'

# Rust
target/
# Note: Keep Cargo.lock for binary applications. Remove from .gitignore
# if this is a library crate (libraries should not commit Cargo.lock).
RSEOF
      ;;
    csharp)
      cat >> .gitignore << 'CSEOF'

# C# / .NET
bin/
obj/
*.user
*.suo
*.userosscache
*.sln.docstates
packages/
*.nupkg
project.lock.json
TestResults/
CSEOF
      ;;
    kotlin|java)
      cat >> .gitignore << 'JVEOF'

# Kotlin / Java (Gradle)
.gradle/
build/
!gradle/wrapper/gradle-wrapper.jar
local.properties
*.class
*.jar
*.war
JVEOF
      ;;
    go)
      cat >> .gitignore << 'GOEOF'

# Go
vendor/
*.exe
*.test
*.out
GOEOF
      ;;
    dart)
      cat >> .gitignore << 'DTEOF'

# Dart / Flutter
.dart_tool/
.packages
.pub-cache/
.pub/
build/
*.dart.js
*.dart.js.map
# Note: Commit pubspec.lock for application projects (reproducible builds).
# Add pubspec.lock to .gitignore only for library/plugin packages.
DTEOF
      ;;
    swift)
      cat >> .gitignore << 'SWEOF'

# Swift
.build/
.swiftpm/
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
*.ipa
*.dSYM.zip
*.dSYM
Pods/
# Note: Commit Package.resolved for application projects (reproducible builds).
# Add Package.resolved to .gitignore only for library/framework packages.
SWEOF
      ;;
  esac

  # Solo Orchestrator logs
  cat >> .gitignore << 'SOEOF'

# Solo Orchestrator logs
.solo-orchestrator/
SOEOF
}

# ================================================================
# Release Pipeline Variables (language → build commands)
# ================================================================
get_release_vars() {
  case "$LANGUAGE" in
    typescript|javascript)
      RELEASE_SETUP_ACTION="actions/setup-node@v4"
      RELEASE_SETUP_VERSION_KEY="node-version"
      RELEASE_SETUP_VERSION_VALUE="'lts/*'"
      RELEASE_INSTALL_COMMAND="npm ci"
      RELEASE_BUILD_COMMAND="npm run build"
      ;;
    python)
      RELEASE_SETUP_ACTION="actions/setup-python@v5"
      RELEASE_SETUP_VERSION_KEY="python-version"
      RELEASE_SETUP_VERSION_VALUE="'3.x'"
      RELEASE_INSTALL_COMMAND="pip install -r requirements.txt"
      RELEASE_BUILD_COMMAND="python -m build"
      ;;
    rust)
      RELEASE_SETUP_ACTION="dtolnay/rust-toolchain@stable"
      RELEASE_SETUP_VERSION_KEY="toolchain"
      RELEASE_SETUP_VERSION_VALUE="stable"
      RELEASE_INSTALL_COMMAND="echo 'No separate install step for Rust'"
      RELEASE_BUILD_COMMAND="cargo build --release"
      ;;
    csharp)
      RELEASE_SETUP_ACTION="actions/setup-dotnet@v4"
      RELEASE_SETUP_VERSION_KEY="dotnet-version"
      # Current LTS — update when next LTS releases
      RELEASE_SETUP_VERSION_VALUE="'8.0.x'"
      RELEASE_INSTALL_COMMAND="dotnet restore"
      RELEASE_BUILD_COMMAND="dotnet build --configuration Release"
      ;;
    kotlin|java)
      RELEASE_SETUP_ACTION="actions/setup-java@v4"
      RELEASE_SETUP_VERSION_KEY="java-version"
      # Current LTS — update when next LTS releases
      RELEASE_SETUP_VERSION_VALUE="'21'"
      RELEASE_INSTALL_COMMAND="echo 'Gradle handles dependencies automatically'"
      RELEASE_BUILD_COMMAND="./gradlew build"
      ;;
    go)
      RELEASE_SETUP_ACTION="actions/setup-go@v5"
      RELEASE_SETUP_VERSION_KEY="go-version"
      RELEASE_SETUP_VERSION_VALUE="'stable'"
      RELEASE_INSTALL_COMMAND="echo 'Go modules download automatically'"
      RELEASE_BUILD_COMMAND="go build ./..."
      ;;
    dart)
      RELEASE_SETUP_ACTION="subosito/flutter-action@v2"
      RELEASE_SETUP_VERSION_KEY="channel"
      RELEASE_SETUP_VERSION_VALUE="'stable'"
      RELEASE_INSTALL_COMMAND="flutter pub get"
      RELEASE_BUILD_COMMAND="flutter build"
      ;;
    swift)
      # Xcode (and swift) is pre-installed on macos-latest GitHub Actions runners.
      # No setup action needed — pin Xcode version in the workflow if required.
      RELEASE_SETUP_ACTION="# Pre-installed: Xcode on macos-latest (no setup action needed)"
      RELEASE_SETUP_VERSION_KEY="# N/A"
      RELEASE_SETUP_VERSION_VALUE="# N/A"
      RELEASE_INSTALL_COMMAND="swift package resolve"
      RELEASE_BUILD_COMMAND="swift build -c release"
      ;;
    *)
      RELEASE_SETUP_ACTION="# TODO: Add setup action for your language"
      RELEASE_SETUP_VERSION_KEY="version"
      RELEASE_SETUP_VERSION_VALUE="'latest'"
      RELEASE_INSTALL_COMMAND="# TODO: Add install command"
      RELEASE_BUILD_COMMAND="# TODO: Add build command"
      ;;
  esac
}

generate_ci() {
  mkdir -p .github/workflows

  # Map language to CI template filename
  local ci_template
  case "$LANGUAGE" in
    typescript|javascript) ci_template="typescript.yml" ;;
    python)                ci_template="python.yml" ;;
    rust)                  ci_template="rust.yml" ;;
    csharp)                ci_template="csharp.yml" ;;
    kotlin)                ci_template="kotlin.yml" ;;
    java)                  ci_template="java.yml" ;;
    go)                    ci_template="go.yml" ;;
    dart)                  ci_template="dart.yml" ;;
    swift)                 ci_template="swift.yml" ;;
    *)                     ci_template="other.yml" ;;
  esac

  # Host-aware template selection (spec 2026-04-21). Prefer the in-process
  # GIT_HOST var (set from --git-host in non-interactive mode), then fall
  # back to intake-progress.json (set by intake-wizard.sh in interactive
  # mode), then default to github.
  local host="github"
  if [ -n "${GIT_HOST:-}" ]; then
    host="$GIT_HOST"
  elif [ -f .claude/intake-progress.json ]; then
    host=$(jq -r '.answers.git_host // "github"' .claude/intake-progress.json 2>/dev/null || echo "github")
  fi

  local template_path="$SCRIPT_DIR/templates/pipelines/ci/$host/$ci_template"
  local target_path
  case "$host" in
    github)     target_path=".github/workflows/ci.yml"; mkdir -p .github/workflows ;;
    gitlab)     target_path=".gitlab-ci.yml" ;;
    bitbucket)  target_path="bitbucket-pipelines.yml" ;;
    other)
      print_info "Host 'other' — no CI template laid down. Supply your own CI config."
      return 0
      ;;
    *) print_warn "Unknown host '$host'; defaulting to GitHub"; target_path=".github/workflows/ci.yml"; mkdir -p .github/workflows; template_path="$SCRIPT_DIR/templates/pipelines/ci/github/$ci_template" ;;
  esac

  if [ -f "$template_path" ]; then
    cp "$template_path" "$target_path"
  else
    print_warn "CI template not found: $template_path"
    return 1
  fi

  print_info "CI pipeline created at $target_path (host: $host, language: $LANGUAGE)"
}

generate_release() {
  # Host-aware release template selection (spec 2026-04-21). Prefer the
  # in-process GIT_HOST var (set from --git-host) over intake-progress.json
  # so non-interactive mode honors the flag.
  local host="github"
  if [ -n "${GIT_HOST:-}" ]; then
    host="$GIT_HOST"
  elif [ -f .claude/intake-progress.json ]; then
    host=$(jq -r '.answers.git_host // "github"' .claude/intake-progress.json 2>/dev/null || echo "github")
  fi

  [ "$host" = "other" ] && { print_info "Host 'other' — no release template laid down. Supply your own."; return 0; }

  local release_template="$SCRIPT_DIR/templates/pipelines/release/$host/$PLATFORM.yml"
  if [ ! -f "$release_template" ]; then
    print_info "No release pipeline template for platform '$PLATFORM' on host '$host'. Skipping release pipeline."
    return 0
  fi

  # Host-specific output path: GitHub workflows live under .github/workflows,
  # GitLab pipelines under .gitlab-ci/, Bitbucket under bitbucket-pipelines/
  # (deploy phase is appended to bitbucket-pipelines.yml via include).
  local target_dir target_file
  case "$host" in
    github)
      target_dir=".github/workflows"
      target_file="$target_dir/release.yml"
      ;;
    gitlab)
      target_dir=".gitlab-ci"
      target_file="$target_dir/release.yml"
      ;;
    bitbucket)
      target_dir="bitbucket-pipelines"
      target_file="$target_dir/release.yml"
      ;;
    *)
      print_warn "Unknown host '$host'; defaulting release output to .github/workflows/release.yml"
      target_dir=".github/workflows"
      target_file="$target_dir/release.yml"
      ;;
  esac
  mkdir -p "$target_dir"

  # Get language-specific build variables
  get_release_vars

  # Substitute placeholders into the release template
  sed -e "s|__SETUP_ACTION__|$RELEASE_SETUP_ACTION|g" \
      -e "s|__SETUP_VERSION_KEY__|$RELEASE_SETUP_VERSION_KEY|g" \
      -e "s|__SETUP_VERSION_VALUE__|$RELEASE_SETUP_VERSION_VALUE|g" \
      -e "s|__INSTALL_COMMAND__|$RELEASE_INSTALL_COMMAND|g" \
      -e "s|__BUILD_COMMAND__|$RELEASE_BUILD_COMMAND|g" \
      -e "s|__PROJECT_NAME__|$PROJECT_NAME|g" \
      "$release_template" > "$target_file"

  print_info "Release pipeline created at $target_file (host: $host, platform: $PLATFORM)"
  case "$TRACK" in
    light)
      print_info "Release pipeline is optional for light-track projects. Configure TODOs only if distributing externally."
      ;;
    standard)
      print_info "Configure TODOs in the release pipeline (signing, deployment, secrets) before your first external release."
      ;;
    full)
      print_info "Configure TODOs in the release pipeline (signing, deployment, secrets) before production deployment."
      ;;
  esac
}

# ================================================================
# PHASE 5: Print Next Steps (health_check replaced by verify-install.sh)
# ================================================================
print_next_steps() {
  # Show full dependency status BEFORE the Setup Complete banner
  # Pull from RESOLVER_OUTPUT (same data the tool plan box uses) so the list
  # matches exactly what was resolved, not a hardcoded subset.
  echo ""

  if [ -n "${RESOLVER_OUTPUT:-}" ] && command -v jq &>/dev/null; then
    local _installed_count
    _installed_count=$(echo "$RESOLVER_OUTPUT" | jq '.already_installed | length')

    echo -e "${BOLD}── Installed Dependencies (${_installed_count} tools) ──${NC}"
    echo "$RESOLVER_OUTPUT" | jq -r '.already_installed[] | "\(.name)\(if .version != "" and .version != "installed" and .version != "configured" and .version != "container running" then " " + .version else "" end)"' | while IFS= read -r item; do
      echo -e "  ${GREEN}✓${NC} $item"
    done

    local _auto_count _manual_count _deferred_count
    _auto_count=$(echo "$RESOLVER_OUTPUT" | jq '.auto_install | length')
    _manual_count=$(echo "$RESOLVER_OUTPUT" | jq '.manual_install | length')
    _deferred_count=$(echo "$RESOLVER_OUTPUT" | jq '.deferred | length')

    if [ "$_manual_count" -gt 0 ]; then
      echo ""
      echo -e "${BOLD}── Needs Attention ──${NC}"
      echo "$RESOLVER_OUTPUT" | jq -r '.manual_install[] | "\(.name) — \(.instructions)"' | while IFS= read -r item; do
        echo -e "  ${RED}✗${NC} $item"
      done
    fi

    if [ "$_deferred_count" -gt 0 ]; then
      echo ""
      echo -e "${BOLD}── Will Be Installed Later ──${NC}"
      echo "$RESOLVER_OUTPUT" | jq -r '.deferred[] | "Phase \(.phase): \(.name)"' | while IFS= read -r item; do
        echo -e "  ${BLUE}○${NC} $item"
      done
    fi
  fi

  # Qdrant MCP status (not in resolver — checked separately)
  if is_qdrant_mcp_registered; then
    echo -e "  ${GREEN}✓${NC} Qdrant MCP (persistent semantic memory — collection: $PROJECT_NAME)"
  elif is_qdrant_container_running; then
    echo ""
    echo -e "${BOLD}── Will Be Configured Later ──${NC}"
    echo -e "  ${BLUE}○${NC} Qdrant MCP — container running, MCP will be configured on first Claude Code session"
  fi

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║                    Setup Complete                       ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}Project:${NC} $PROJECT_NAME"
  echo -e "${BOLD}Location:${NC} $PROJECT_DIR"
  echo ""
  echo -e "${BOLD}Next Steps:${NC}"
  echo ""
  echo "  1. AUTHENTICATE (manual — requires browser):"
  echo "     cd $PROJECT_DIR"
  echo "     claude        # Follow the OAuth prompt"
  echo "     snyk auth     # Authenticate Snyk CLI"
  echo ""
  echo "  2. FILL OUT THE INTAKE (this is your product definition):"
  echo "     cd $PROJECT_DIR"
  echo "     bash scripts/intake-wizard.sh          — guided wizard (interactive or AI-assisted)"
  echo "     Or edit directly: $PROJECT_DIR/PROJECT_INTAKE.md"
  echo ""
  echo "     IMPORTANT: Run the wizard and edit the intake from your PROJECT directory,"
  echo "     not from the solo-orchestrator source directory."
  if [ "$DEPLOYMENT" = "personal" ] || [ "${POC_MODE:-}" = "private_poc" ]; then
    echo ""
    echo "     TIP: For personal/private POC projects, you can paste the intake form"
    echo "     into your AI and work with it to fill out the sections. Read through"
    echo "     the result yourself to verify accuracy before proceeding."
  fi
  echo ""

  if [ "$DEPLOYMENT" = "organizational" ]; then
    if [ -n "$POC_MODE" ]; then
      echo "  3. GOVERNANCE — ${POC_MODE//_/ } mode:"
      if [ "$POC_MODE" = "sponsored_poc" ]; then
        echo "     Required now: AI deployment path, project sponsor, time allocation."
        echo "     Deferred: insurance, liability entity, ITSM, exit criteria, backup maintainer."
      else
        echo "     All governance pre-conditions deferred (personal exploration)."
      fi
      echo "     Constraints: no production deployment, no real user data, no external users."
      echo "     Phases 0-3 run normally. Phase 4 is blocked until you upgrade."
      echo "     Upgrade: bash scripts/upgrade-project.sh --to-production"
      echo ""
      echo "  4. START BUILDING:"
    else
      echo "  3. GOVERNANCE PRE-FLIGHT (production build):"
      echo "     Complete Section 8 of the Intake before starting."
      echo "     Required: project sponsor, backup maintainer, insurance"
      echo "     confirmation, AI deployment path approval, ITSM registration."
      echo "     Record all pre-condition approvals in APPROVAL_LOG.md."
      echo "     See docs/reference/governance-framework.md for details."
      echo ""
      echo "     RECOMMENDED: Enable branch protection with required reviewers."
      echo "     This will be required when compliance modules are available."
      echo "     Configure via GitHub repo settings or:"
      echo "     gh api repos/OWNER/REPO/branches/main/protection -X PUT -f required_pull_request_reviews[required_approving_review_count]=1"
      echo ""
      echo "  4. START BUILDING:"
    fi
  else
    echo "  3. START BUILDING:"
  fi

  echo "     cd $PROJECT_DIR"
  echo "     claude"
  echo ""
  echo "     Then give the agent the full project context:"
  echo "     ┌─────────────────────────────────────────────────────────────────┐"
  echo "     │ Read the following files in order, then confirm what you        │"
  echo "     │ understand about this project before taking any action:         │"
  echo "     │                                                                 │"
  echo "     │ 1. CLAUDE.md (your instructions and constraints)                │"
  echo "     │ 2. PROJECT_INTAKE.md (the product definition)                   │"
  echo "     │ 3. docs/reference/builders-guide.md (the phase-gate method)     │"
  echo "     │ 4. docs/platform-modules/ (platform-specific guidance)          │"
  echo "     │ 5. .claude/phase-state.json (current phase)                     │"
  echo "     │                                                                 │"
  echo "     │ After reading, summarize: the project goal, your constraints,   │"
  echo "     │ the current phase, and what tools/MCP servers are available to   │"
  echo "     │ you. Then begin Phase 0. Ask me only for clarifying questions.  │"
  echo "     └─────────────────────────────────────────────────────────────────┘"
  echo ""

  if [ -f "$PROJECT_DIR/.github/workflows/release.yml" ]; then
    echo ""
    echo "  RELEASE PIPELINE:"
    echo "     .github/workflows/release.yml"
    case "$TRACK" in
      light)
        echo "     This pipeline is optional for light-track projects (POCs, prototypes, internal tools)."
        echo "     Configure the TODOs (code signing, secrets) only if you plan to distribute externally."
        ;;
      standard)
        echo "     Configure TODOs (code signing, deployment, secrets) before your first external release."
        echo "     The framework will remind you when you reach Phase 4 (Production Hardening)."
        ;;
      full)
        echo "     Configure TODOs (code signing, deployment, secrets) before production deployment."
        echo "     Phase 3→4 gate will verify release pipeline configuration."
        ;;
    esac
    echo "     Release is triggered by version tags: git tag v1.0.0 && git push --tags"
    echo ""
  fi
  echo "  VALIDATION (run periodically to check framework compliance):"
  echo "     cd $PROJECT_DIR"
  echo "     bash scripts/validate.sh              — check framework compliance"
  echo "     bash scripts/check-updates.sh         — check for upstream framework updates"
  echo "     bash scripts/resume.sh                — generate a session resume prompt"
  echo ""
  echo "  DOCUMENTATION:"
  echo "     docs/reference/user-guide.md          — Start here: step-by-step walkthrough"
  echo "     docs/reference/builders-guide.md      — The complete methodology"
  echo "     docs/reference/governance-framework.md — Enterprise governance"
  echo "     docs/reference/cli-setup-addendum.md   — Claude Code configuration"
  echo "     docs/platform-modules/                — Platform-specific guidance"
  echo ""
  if [ "$TRACK" = "light" ] || [ "$DEPLOYMENT" = "personal" ] || [ -n "$POC_MODE" ]; then
    echo "  UPGRADE (when ready to move beyond current scope):"
    echo "     bash scripts/upgrade-project.sh --help          — see all upgrade options"
    if [ -n "$POC_MODE" ]; then
      echo "     bash scripts/upgrade-project.sh --to-production — complete deferred governance and unlock Phase 4"
    elif [ "$TRACK" = "light" ]; then
      echo "     bash scripts/upgrade-project.sh --to-standard   — add external-user readiness"
      echo "     bash scripts/upgrade-project.sh --to-production — upgrade to production"
    else
      echo "     bash scripts/upgrade-project.sh --to-production — upgrade to production"
    fi
    echo ""
  fi
}

# ================================================================
# BL-064: Setup-INCOMPLETE summary (silent-success defect class)
# ================================================================
# Printed in place of "Setup Complete" when INIT_FAILURES is non-empty.
# Re-lists every tracked failure so an operator scanning only the tail of
# the log still sees the gap, regardless of whether they checked the exit
# code. main() calls this and returns 2 when failures occurred.
#
# Failure categorisation:
#   • Currently tracked: host repo setup (create_and_protect_remote
#     return-1 paths — push fail, attestation missing, host CLI missing,
#     protection config fail, verification fail).
#   • NOT tracked (terminal-exit paths): missing prerequisites (line
#     112-area + 322), incompatible OS/language (519, interactive
#     recovery), --enforcement-level validation (3693, 3698). All of
#     these already terminate via `exit 1` before reaching main()'s
#     completion path, so no Setup-Complete banner can appear.
#
# See scripts/lint-fail-emit-exit-status.sh for the structural backstop
# that prevents new print_fail sites from regressing this contract.
print_init_failures_summary() {
  local n="${#INIT_FAILURES[@]}"
  echo ""
  echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${RED}║                   Setup INCOMPLETE                       ║${NC}"
  echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}${RED}${n} failure(s) occurred during init:${NC}"
  local i=1
  local msg
  for msg in "${INIT_FAILURES[@]}"; do
    echo -e "  ${RED}${i}.${NC} ${msg}"
    i=$((i + 1))
  done
  echo ""
  echo -e "${BOLD}Project files are in place; some setup steps did NOT complete.${NC}"
  echo ""
  echo "Typical remediation (consult the [FAIL] lines above for specifics):"
  echo "  scripts/check-gate.sh --backfill-host    # if .claude/manifest.json lacks 'host'"
  echo "  scripts/check-gate.sh --repair           # re-create remote + branch protection"
  echo "  scripts/check-gate.sh --preflight        # verify the remote is set up correctly"
  echo ""
  echo "Exit status: 2 (init produced [FAIL] line(s) — wrapper scripts must observe)"
  echo ""
}

# ================================================================
dry_run_summary() {
  echo ""
  print_step "DRY RUN SUMMARY"
  echo ""

  echo -e "${BOLD}Project:${NC}"
  echo "  Name:      $PROJECT_NAME"
  # BL-040 (2026-06-30): echo the operator-supplied description so the
  # dry-run preview reflects every input that will be persisted to
  # PROJECT_INTAKE.md / manifest. Omit the line entirely when the value
  # is empty (keeps the summary clean for the "no description provided"
  # default). Newlines and tabs are collapsed to spaces so a multi-line
  # value reachable through --description $'foo\nbar' doesn't break the
  # one-line-per-field column layout below.
  if [ -n "${PROJECT_DESCRIPTION:-}" ]; then
    local _summary_desc
    _summary_desc=$(printf '%s' "$PROJECT_DESCRIPTION" | tr '\n\t' '  ')
    echo "  Description: $_summary_desc"
  fi
  echo "  Platform:  $PLATFORM"
  echo "  Track:     $TRACK"
  echo "  Language:  $LANGUAGE"
  echo "  Directory: $PROJECT_DIR"
  echo ""

  echo -e "${BOLD}Tool Resolution:${NC}"
  local dev_os
  case "$OS_TYPE" in Darwin) dev_os="darwin" ;; *) dev_os="linux" ;; esac
  local dry_output
  dry_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
    --dev-os "$dev_os" \
    --platform "$PLATFORM" \
    --language "$LANGUAGE" \
    --track "$TRACK" \
    --phase 2 \
    --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" 2>/dev/null) || {
    echo "  (resolver unavailable — cannot preview tools)"
    dry_output=""
  }
  if [ -n "$dry_output" ]; then
    echo "$dry_output" | jq -r '.already_installed[] | "  [already installed] \(.name) \(.version)"'
    echo "$dry_output" | jq -r '.auto_install[] | "  [WILL INSTALL] \(.name) (\(.description))"'
    echo "$dry_output" | jq -r '.manual_install[] | "  [MANUAL] \(.name) — \(.instructions)"'
    echo "$dry_output" | jq -r '.deferred[] | "  [DEFERRED Phase \(.phase)] \(.name) (\(.description))"'
  fi
  echo ""

  echo -e "${BOLD}Files to create in $PROJECT_DIR/:${NC}"
  echo "  CLAUDE.md                             — Agent instructions"
  echo "  PROJECT_INTAKE.md                     — Product definition template"
  echo "  APPROVAL_LOG.md                       — Phase gate approval record"
  echo "  .github/workflows/ci.yml              — CI pipeline ($LANGUAGE)"
  echo "  .github/workflows/release.yml         — Release pipeline ($PLATFORM)"
  echo "  .gitignore                            — Language + platform ignores"
  echo "  .claude/framework/                    — Development Guardrails hooks and rules"
  echo "  .claude/manifest.json                 — Framework configuration and metadata"
  echo "  .claude/settings.json                 — Claude Code hook configuration"
  echo "  .claude/phase-state.json              — Phase tracking"
  echo "  docs/reference/builders-guide.md      — Builder's Guide"
  echo "  docs/reference/governance-framework.md"
  echo "  docs/reference/executive-review.md"
  echo "  docs/reference/cli-setup-addendum.md"
  echo "  docs/platform-modules/                — Platform-specific guidance"
  echo "  docs/test-results/                    — Empty (populated in Phase 3)"
  echo "  scripts/validate.sh                   — Validation script"
  echo "  scripts/check-phase-gate.sh           — Phase gate checker"
  echo "  scripts/resume.sh                     — Session resume prompt generator"
  echo "  scripts/intake-wizard.sh              — Guided intake wizard"
  echo "  templates/intake-suggestions/          — Context-aware suggestion data"
  echo "  evaluation-prompts/Projects/           — Adversarial review prompts for Phase 3"
  echo ""

  echo -e "${BOLD}Post-init steps (you do these manually):${NC}"
  echo "  1. cd $PROJECT_DIR"
  echo "  2. claude          # OAuth authentication"
  echo "  3. snyk auth       # Snyk authentication"
  echo "  4. Fill out PROJECT_INTAKE.md"
  echo ""
  echo -e "${GREEN}Re-run without --dry-run to execute.${NC}"
}

# ================================================================
# Non-Interactive Mode (BL-016)
# ================================================================

print_help_non_interactive() {
  cat <<'NIHELPEOF'
init.sh --non-interactive — full reference

Required flags (always):
  --project NAME           Project name. Lowercase letters, digits, hyphens; must start with letter.
  --platform PLATFORM      Any platform module under docs/platform-modules/,
                           any release pipeline under templates/pipelines/release/github/,
                           or 'other' as a fallback. Today: desktop, mobile, web, mcp_server, other.
                           (Dynamic; ship a new platform-modules/<name>.md to extend.)
  --deployment KIND        One of: personal, organizational
  --language NAME          Primary language. Must be valid for the chosen platform.

Required flags (conditional):
  --gov-mode MODE          One of: production, sponsored_poc, private_poc.
                           REQUIRED when --deployment=organizational.
                           NOT VALID when --deployment=personal.
  --remote-url URL         HTTPS or SSH URL of an existing remote repo.
                           REQUIRED when --git-host=other.
  --branch-protection-attested
                           Boolean flag (presence = true). Confirms branch
                           protection is configured on the remote.
                           REQUIRED when --git-host=other.
  --approvals-attested     Boolean flag (presence = true). Skips the
                           gitlab.com Free-tier `projects/:id/approvals` PUT
                           (Premium-only) and records a
                           `gitlab_free_tier_approvals` attestation. Only
                           meaningful for --git-host=gitlab + --deployment
                           =organizational; ignored otherwise. Equivalent to
                           SOLO_APPROVALS_ATTESTED=1 in the environment.
                           See BL-032 in solo-orchestrator-backlog.md.

Optional flags (with defaults):
  --description TEXT       One-sentence project description. Default: "".
  --track TRACK            One of: light, standard, full. Default: standard.
  --project-dir PATH       Project directory path. Default: $HOME/Code/$PROJECT.
  --git-host HOST          One of: github, gitlab, bitbucket, other. Default: github.
  --visibility VIS         One of: private, public. Default: private.
                           NOTE: organizational deployments force private.
  --allow-existing-dir     Boolean flag. Allow init into an existing directory
                           (otherwise: exit 1 if --project-dir already exists).
  --no-remote-creation     Boolean flag. Skip the host_create_repo / push /
                           branch-protection API calls. Project files are
                           scaffolded and .claude/manifest.json is written
                           with the host field. The remote can be added
                           later with `scripts/check-gate.sh --repair`.
                           Useful for UAT/CI runs that must NOT contaminate
                           a real GitHub/GitLab/Bitbucket account.
  --accept-local-only-risk Boolean flag (BL-084). track=light ONLY. If the
                           initial push on --git-host other FAILS, keep the
                           project LOCAL (no remote) and accept the data-loss
                           risk; recorded in .claude/process-state.json. Has
                           NO effect on track=standard|full (a failed push is
                           a hard, non-bypassable failure there).
  --defer-remote-push      Boolean flag (BL-084). track=light ONLY. If the
                           initial push on --git-host other FAILS, defer it;
                           init exits 0 but the Phase 1→2 gate BLOCKS until
                           the remote actually has the branch. No effect on
                           track=standard|full.

Mode flags:
  --non-interactive        Required to enable this mode. Without it, all input
                           flags are silently ignored (interactive flow runs).
  --config FILE            Read JSON config from FILE. Schema below.
                           Only honored with --non-interactive (otherwise warn + ignore).
  --validate-only          Validate inputs + print resolved config to stdout; exit 0.
                           No file writes.

Precedence: command-line flag > --config FILE > default > error-if-required.

JSON config schema (snake_case keys; all fields optional, missing → use flag/default/error):

{
  "project": "my-app",
  "description": "A web app for tracking widgets",
  "platform": "web",
  "track": "standard",
  "deployment": "personal",
  "gov_mode": null,
  "language": "typescript",
  "project_dir": "/Users/karl/Code/my-app",
  "git_host": "github",
  "visibility": "private",
  "remote_url": null,
  "branch_protection_attested": false,
  "approvals_attested": false,
  "allow_existing_dir": false,
  "no_remote_creation": false
}

Examples:
  ./init.sh --non-interactive \
      --project my-app --platform web --deployment personal --language typescript

  ./init.sh --non-interactive --config init.json --project my-app

  ./init.sh --non-interactive --config init.json --project my-app --track full

  ./init.sh --non-interactive --config init.json --validate-only | jq

Errors take the uniform shape:

  [FAIL] init.sh non-interactive: <one-line summary>
    Reason: <specific cause>
    Action: <how to fix>
    Context: <relevant flags + values>

See docs/builders-guide.md "Scripted / Non-Interactive Project Initialization"
for narrative + use cases.
NIHELPEOF
}

collect_inputs_non_interactive() {
  # ----- Helpers (local to this function) -----
  local fail
  fail() {
    local summary="$1" reason="$2" action="$3" context="${4:-}"
    echo "[FAIL] init.sh non-interactive: $summary" >&2
    echo "  Reason: $reason" >&2
    echo "  Action: $action" >&2
    if [ -n "$context" ]; then
      echo "  Context: $context" >&2
    fi
    return 1
  }

  # ----- Config file load (BEFORE Pass 1 so flags can override) -----
  if [ -n "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
      fail "config file not found: $CONFIG_FILE" \
           "the path supplied to --config does not exist or is not readable." \
           "fix the path and re-run." \
           "--config='$CONFIG_FILE'"
      return 1
    fi
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
      local jq_err
      jq_err=$(jq . "$CONFIG_FILE" 2>&1 >/dev/null || true)
      fail "config file is not valid JSON: $CONFIG_FILE" \
           "jq parse error: $jq_err" \
           "fix the JSON syntax and re-run. Use 'jq . FILE' to lint." \
           "--config='$CONFIG_FILE'"
      return 1
    fi
    if [ "$(jq -r 'type' "$CONFIG_FILE")" != "object" ]; then
      fail "config file must be a JSON object" \
           "found: $(jq -r 'type' "$CONFIG_FILE")" \
           "wrap the contents in {} and re-run." \
           "--config='$CONFIG_FILE'"
      return 1
    fi

    # Warn on unknown fields (forward-compat per spec § 5.4).
    local known_fields="project description platform track deployment gov_mode language project_dir git_host visibility remote_url branch_protection_attested approvals_attested allow_existing_dir no_remote_creation accept_local_only_risk defer_remote_push"
    local field
    for field in $(jq -r 'keys[]' "$CONFIG_FILE"); do
      if ! echo " $known_fields " | grep -q " $field "; then
        print_warn "unknown config field: $field (ignored)"
      fi
    done

    # Merge: each ARG_* defaults to the config value if not already set via flag.
    # Flag wins on conflict per spec § 5.5.
    local cfg_get
    cfg_get() {
      local key="$1"
      jq -r --arg k "$key" '.[$k] // empty' "$CONFIG_FILE" 2>/dev/null
    }
    [ -z "$ARG_PROJECT" ]                  && ARG_PROJECT=$(cfg_get project)
    [ -z "$ARG_DESCRIPTION" ]              && ARG_DESCRIPTION=$(cfg_get description)
    [ -z "$ARG_PLATFORM" ]                 && ARG_PLATFORM=$(cfg_get platform)
    [ -z "$ARG_TRACK" ]                    && ARG_TRACK=$(cfg_get track)
    [ -z "$ARG_DEPLOYMENT" ]               && ARG_DEPLOYMENT=$(cfg_get deployment)
    [ -z "$ARG_GOV_MODE" ]                 && ARG_GOV_MODE=$(cfg_get gov_mode)
    [ -z "$ARG_LANGUAGE" ]                 && ARG_LANGUAGE=$(cfg_get language)
    [ -z "$ARG_PROJECT_DIR" ]              && ARG_PROJECT_DIR=$(cfg_get project_dir)
    [ -z "$ARG_GIT_HOST" ]                 && ARG_GIT_HOST=$(cfg_get git_host)
    [ -z "$ARG_VISIBILITY" ]               && ARG_VISIBILITY=$(cfg_get visibility)
    [ -z "$ARG_REMOTE_URL" ]               && ARG_REMOTE_URL=$(cfg_get remote_url)
    if [ "$ARG_BRANCH_PROTECTION_ATTESTED" != true ]; then
      local cfg_attest
      cfg_attest=$(cfg_get branch_protection_attested)
      [ "$cfg_attest" = "true" ] && ARG_BRANCH_PROTECTION_ATTESTED=true
    fi
    # BL-032: honor approvals_attested from config file (parity with
    # branch_protection_attested above; flag wins on conflict).
    if [ "$ARG_APPROVALS_ATTESTED" != true ]; then
      local cfg_appr_attest
      cfg_appr_attest=$(cfg_get approvals_attested)
      [ "$cfg_appr_attest" = "true" ] && ARG_APPROVALS_ATTESTED=true
    fi
    if [ "$ARG_ALLOW_EXISTING_DIR" != true ]; then
      local cfg_allow
      cfg_allow=$(cfg_get allow_existing_dir)
      [ "$cfg_allow" = "true" ] && ARG_ALLOW_EXISTING_DIR=true
    fi
    if [ "$ARG_NO_REMOTE_CREATION" != true ]; then
      local cfg_no_remote
      cfg_no_remote=$(cfg_get no_remote_creation)
      [ "$cfg_no_remote" = "true" ] && ARG_NO_REMOTE_CREATION=true
    fi
    # BL-084: honor the light-tier push-failure escape hatches from config.
    if [ "$ARG_ACCEPT_LOCAL_ONLY_RISK" != true ]; then
      local cfg_local_only
      cfg_local_only=$(cfg_get accept_local_only_risk)
      [ "$cfg_local_only" = "true" ] && ARG_ACCEPT_LOCAL_ONLY_RISK=true
    fi
    if [ "$ARG_DEFER_REMOTE_PUSH" != true ]; then
      local cfg_defer_push
      cfg_defer_push=$(cfg_get defer_remote_push)
      [ "$cfg_defer_push" = "true" ] && ARG_DEFER_REMOTE_PUSH=true
    fi
  fi

  # ----- Pass 1: schema validation (per-input typing) -----

  # project
  if [ -n "$ARG_PROJECT" ] && ! [[ "$ARG_PROJECT" =~ ^[a-z][a-z0-9-]*$ ]]; then
    fail "invalid --project name '$ARG_PROJECT'" \
         "project name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens." \
         "fix the name and re-run." \
         "--project='$ARG_PROJECT'"
    return 1
  fi

  # platform
  if [ -n "$ARG_PLATFORM" ]; then
    # Audit specs-plans-init-intake-noninteractive-2: validate against
    # the same dynamic set the interactive flow uses, rather than a
    # hardcoded list that drifts whenever a platform module ships.
    local available
    available=$(get_available_platforms)
    if [[ ! " $available " == *" $ARG_PLATFORM "* ]]; then
      fail "invalid --platform '$ARG_PLATFORM'" \
           "platform must be one of:$available." \
           "add a docs/platform-modules/<name>.md to extend, or pick a supported value." \
           "--platform='$ARG_PLATFORM'"
      return 1
    fi
  fi

  # track
  if [ -n "$ARG_TRACK" ]; then
    case "$ARG_TRACK" in
      light|standard|full) ;;
      *)
        fail "invalid --track '$ARG_TRACK'" \
             "track must be one of: light, standard, full." \
             "re-run with a supported --track value." \
             "--track='$ARG_TRACK'"
        return 1 ;;
    esac
  fi

  # deployment
  if [ -n "$ARG_DEPLOYMENT" ]; then
    case "$ARG_DEPLOYMENT" in
      personal|organizational) ;;
      *)
        fail "invalid --deployment '$ARG_DEPLOYMENT'" \
             "deployment must be one of: personal, organizational." \
             "re-run with a supported --deployment value." \
             "--deployment='$ARG_DEPLOYMENT'"
        return 1 ;;
    esac
  fi

  # gov_mode (presence-only check; required-or-not is Pass 2)
  if [ -n "$ARG_GOV_MODE" ]; then
    case "$ARG_GOV_MODE" in
      production|sponsored_poc|private_poc) ;;
      *)
        fail "invalid --gov-mode '$ARG_GOV_MODE'" \
             "gov-mode must be one of: production, sponsored_poc, private_poc." \
             "re-run with a supported --gov-mode value." \
             "--gov-mode='$ARG_GOV_MODE'"
        return 1 ;;
    esac
  fi

  # git_host (presence-only check)
  if [ -n "$ARG_GIT_HOST" ]; then
    case "$ARG_GIT_HOST" in
      github|gitlab|bitbucket|other) ;;
      *)
        fail "invalid --git-host '$ARG_GIT_HOST'" \
             "git-host must be one of: github, gitlab, bitbucket, other." \
             "re-run with a supported --git-host value." \
             "--git-host='$ARG_GIT_HOST'"
        return 1 ;;
    esac
  fi

  # visibility (presence-only check)
  if [ -n "$ARG_VISIBILITY" ]; then
    case "$ARG_VISIBILITY" in
      private|public) ;;
      *)
        fail "invalid --visibility '$ARG_VISIBILITY'" \
             "visibility must be one of: private, public." \
             "re-run with a supported --visibility value." \
             "--visibility='$ARG_VISIBILITY'"
        return 1 ;;
    esac
  fi

  # remote_url (presence-only check; required-or-not is Pass 2)
  if [ -n "$ARG_REMOTE_URL" ]; then
    if ! [[ "$ARG_REMOTE_URL" =~ ^(https://|git@) ]]; then
      fail "invalid --remote-url '$ARG_REMOTE_URL'" \
           "remote-url must start with 'https://' or 'git@'." \
           "re-run with a valid HTTPS or SSH URL." \
           "--remote-url='$ARG_REMOTE_URL'"
      return 1
    fi
  fi

  # ----- Pass 2: context-required validation -----

  # Always-required: project, platform, deployment, language
  if [ -z "$ARG_PROJECT" ]; then
    fail "--project is required" \
         "every non-interactive invocation must specify a project name." \
         "re-run with --project NAME." \
         "(--project unset)"
    return 1
  fi
  if [ -z "$ARG_PLATFORM" ]; then
    fail "--platform is required" \
         "every non-interactive invocation must specify a platform." \
         "re-run with --platform <one of:$(get_available_platforms)>." \
         "(--platform unset)"
    return 1
  fi
  if [ -z "$ARG_DEPLOYMENT" ]; then
    fail "--deployment is required" \
         "every non-interactive invocation must specify a deployment kind." \
         "re-run with --deployment {personal|organizational}." \
         "(--deployment unset)"
    return 1
  fi
  if [ -z "$ARG_LANGUAGE" ]; then
    fail "--language is required" \
         "every non-interactive invocation must specify a primary language." \
         "re-run with --language NAME (use --help-non-interactive to see supported languages per platform)." \
         "(--language unset)"
    return 1
  fi

  # gov-mode rules (baseline §2.5):
  #   - Private POC is always personal (organizational + private_poc rejected).
  #   - Sponsored POC is always organizational (personal + sponsored_poc rejected).
  #   - Production is valid for both deployments.
  # Audit code-init-sh-4 + tier-crosscheck-2: previously --gov-mode was
  # required for organizational and rejected for personal, making Private
  # POC unreachable for personal deployments.
  if [ "$ARG_DEPLOYMENT" = "organizational" ] && [ -z "$ARG_GOV_MODE" ]; then
    fail "--gov-mode is required when --deployment=organizational" \
         "organizational projects must specify a governance mode." \
         "re-run with --gov-mode production or --gov-mode sponsored_poc." \
         "--deployment=organizational, --gov-mode=(unset)"
    return 1
  fi
  if [ "$ARG_DEPLOYMENT" = "organizational" ] && [ "$ARG_GOV_MODE" = "private_poc" ]; then
    fail "--gov-mode=private_poc is not valid for --deployment=organizational" \
         "Private POC is always a personal deployment (baseline §2.5)." \
         "use --deployment=personal --gov-mode=private_poc, or --deployment=organizational --gov-mode=sponsored_poc." \
         "--deployment=organizational, --gov-mode=private_poc"
    return 1
  fi
  if [ "$ARG_DEPLOYMENT" = "personal" ] && [ "$ARG_GOV_MODE" = "sponsored_poc" ]; then
    fail "--gov-mode=sponsored_poc is not valid for --deployment=personal" \
         "Sponsored POC is always an organizational deployment (baseline §2.5)." \
         "use --deployment=organizational --gov-mode=sponsored_poc, or --deployment=personal --gov-mode=private_poc." \
         "--deployment=personal, --gov-mode=sponsored_poc"
    return 1
  fi

  # remote-url required when git-host=other
  if [ "$ARG_GIT_HOST" = "other" ] && [ -z "$ARG_REMOTE_URL" ]; then
    fail "--remote-url is required when --git-host=other" \
         "the 'other' host has no API to create a repo; you must paste the URL of an existing remote." \
         "re-run with --remote-url URL." \
         "--git-host=other, --remote-url=(unset)"
    return 1
  fi

  # branch-protection-attested required when git-host=other
  if [ "$ARG_GIT_HOST" = "other" ] && [ "$ARG_BRANCH_PROTECTION_ATTESTED" != true ]; then
    fail "--branch-protection-attested is required when --git-host=other" \
         "the 'other' host cannot be API-verified; you must attest branch protection is configured." \
         "verify branch protection on the remote, then re-run with --branch-protection-attested." \
         "--git-host=other, --branch-protection-attested=false"
    return 1
  fi

  # visibility=public not allowed for organizational
  if [ "$ARG_DEPLOYMENT" = "organizational" ] && [ "$ARG_VISIBILITY" = "public" ]; then
    fail "--visibility=public is not allowed for --deployment=organizational" \
         "organizational projects must be private (force-private rule from init.sh:1713)." \
         "remove --visibility=public (or change to --visibility=private) and re-run." \
         "--deployment=organizational, --visibility=public"
    return 1
  fi

  # track=full + deployment=personal: warn, continue (matches interactive confirm-then-proceed)
  if [ "$ARG_TRACK" = "full" ] && [ "$ARG_DEPLOYMENT" = "personal" ]; then
    print_warn "Full track on a personal project is unusual; the interactive flow normally asks to confirm."
    print_warn "Proceeding because non-interactive mode treats explicit flags as confirmation."
  fi

  # language validity for platform — walk CI pipeline templates and accept only
  # languages whose template marker lists the requested platform. This mirrors
  # the interactive flow's `# solo-orchestrator: platforms=` filter (init.sh
  # collect_inputs around line 468-499) so non-interactive and interactive
  # share the single source of truth.
  #
  # Audit code-init-sh-5 + specs-plans-init-intake-noninteractive-5: the
  # previous probe asked the intake-suggestions JSON for a top-level
  # `languages` array; none of the shipped files exposed one, so the check
  # was a silent no-op and any --language value passed through.
  local _supported_for_platform=""
  local _ci_dir="$SCRIPT_DIR/templates/pipelines/ci/github"
  if [ -d "$_ci_dir" ]; then
    local _ci_yml _lname _marker _platforms_csv
    for _ci_yml in "$_ci_dir"/*.yml; do
      [ -f "$_ci_yml" ] || continue
      _lname=$(basename "$_ci_yml" .yml)
      # `other` is the catch-all fallback (matches interactive flow): always
      # accept it regardless of platform marker.
      if [ "$_lname" = "other" ]; then
        _supported_for_platform="$_supported_for_platform $_lname"
        continue
      fi
      _marker=$(head -1 "$_ci_yml")
      _platforms_csv=""
      case "$_marker" in
        *"# solo-orchestrator: platforms="*)
          _platforms_csv="${_marker#*platforms=}"
          ;;
      esac
      if [ -z "$_platforms_csv" ]; then
        # No marker — be permissive (matches interactive backwards-compat).
        _supported_for_platform="$_supported_for_platform $_lname"
      else
        case ",$_platforms_csv," in
          *",$ARG_PLATFORM,"*)
            _supported_for_platform="$_supported_for_platform $_lname"
            ;;
        esac
      fi
    done
  fi
  if [ -n "$_supported_for_platform" ]; then
    case " $_supported_for_platform " in
      *" $ARG_LANGUAGE "*) : ;;
      *)
        local _supported_csv
        _supported_csv=$(echo "$_supported_for_platform" | tr ' ' '\n' \
                         | awk 'NF' | sort -u | paste -sd, - | sed 's/,/, /g')
        fail "language '$ARG_LANGUAGE' is not supported for platform '$ARG_PLATFORM'" \
             "no CI pipeline template (templates/pipelines/ci/github/<lang>.yml) lists $ARG_PLATFORM in its platforms marker for that language." \
             "re-run with one of: $_supported_csv (or pick a different --platform)." \
             "--platform='$ARG_PLATFORM', --language='$ARG_LANGUAGE'"
        return 1 ;;
    esac
  fi

  # OS-language compatibility (mirrors interactive Linux/Swift block at
  # init.sh:506-537). Swift requires macOS (Xcode + Apple build toolchain).
  case "$OS_TYPE" in
    Linux)
      case "$ARG_LANGUAGE" in
        swift)
          fail "language '$ARG_LANGUAGE' is not supported on $OS_TYPE for platform '$ARG_PLATFORM'" \
               "Swift/iOS development requires macOS — Xcode and Apple's build toolchain are not available on Linux." \
               "re-run on a macOS host, or pick a different --language." \
               "--language='$ARG_LANGUAGE' on $OS_TYPE"
          return 1 ;;
      esac
      ;;
  esac

  # ----- Pass 3: resource validation -----

  # Required tools
  for tool in git jq node python3; do
    if ! command -v "$tool" &>/dev/null; then
      local install_cmd=""
      case "$OS_TYPE" in
        Darwin) install_cmd="brew install $tool" ;;
        Linux)  install_cmd="apt install -y $tool   # or your distro's package manager" ;;
      esac
      fail "missing required tool: $tool" \
           "non-interactive mode does not auto-install dependencies." \
           "install: $install_cmd, then re-run." \
           "--non-interactive (tool=$tool)"
      return 1
    fi
  done

  # git host CLI presence (skipped for 'other', and skipped entirely when
  # --no-remote-creation: we will not call the host API in that mode, so
  # the CLI is not actually needed).
  if [ "$ARG_NO_REMOTE_CREATION" != true ]; then
    local effective_git_host="${ARG_GIT_HOST:-github}"
    case "$effective_git_host" in
      github)
        if ! command -v gh &>/dev/null; then
          fail "missing required tool for --git-host=github: gh" \
               "the GitHub CLI is needed to create + protect the remote repo." \
               "install: brew install gh (macOS) or apt install gh (Linux), then re-run." \
               "--git-host=github"
          return 1
        fi ;;
      gitlab)
        if ! command -v glab &>/dev/null; then
          fail "missing required tool for --git-host=gitlab: glab" \
               "the GitLab CLI is needed to create + protect the remote repo." \
               "install: brew install glab (macOS), then re-run." \
               "--git-host=gitlab"
          return 1
        fi ;;
      bitbucket)
        # bitbucket uses curl + tokens; no CLI requirement
        : ;;
      other)
        : ;;
    esac
  fi

  # project_dir existence check
  local effective_project_dir="${ARG_PROJECT_DIR:-$HOME/Code/$ARG_PROJECT}"
  if [ -e "$effective_project_dir" ] && [ "$ARG_ALLOW_EXISTING_DIR" != true ]; then
    fail "project directory already exists: $effective_project_dir" \
         "non-interactive mode refuses to write into an existing directory by default." \
         "pass --allow-existing-dir to use it anyway, or pick a different --project-dir." \
         "--project-dir='$effective_project_dir'"
    return 1
  fi

  # ----- Apply defaults for inputs not set by flag or config -----
  : "${ARG_TRACK:=standard}"
  : "${ARG_GIT_HOST:=github}"
  : "${ARG_VISIBILITY:=private}"
  : "${ARG_PROJECT_DIR:=$HOME/Code/$ARG_PROJECT}"
  # Force private for organizational deployments (matches existing init.sh:1713 logic).
  if [ "$ARG_DEPLOYMENT" = "organizational" ]; then
    ARG_VISIBILITY="private"
  fi

  # Assign resolved values to the variables the rest of init.sh consumes.
  PROJECT_NAME="$ARG_PROJECT"
  PROJECT_DESCRIPTION="$ARG_DESCRIPTION"
  PLATFORM="$ARG_PLATFORM"
  TRACK="$ARG_TRACK"
  DEPLOYMENT="$ARG_DEPLOYMENT"
  GOV_MODE="$ARG_GOV_MODE"
  LANGUAGE="$ARG_LANGUAGE"
  PROJECT_DIR="$ARG_PROJECT_DIR"
  GIT_HOST="$ARG_GIT_HOST"
  VISIBILITY="$ARG_VISIBILITY"
  REMOTE_URL="$ARG_REMOTE_URL"
  BRANCH_PROTECTION_ATTESTED="$ARG_BRANCH_PROTECTION_ATTESTED"
  APPROVALS_ATTESTED="$ARG_APPROVALS_ATTESTED"
  ALLOW_EXISTING_DIR="$ARG_ALLOW_EXISTING_DIR"
  NO_REMOTE_CREATION="$ARG_NO_REMOTE_CREATION"
  ACCEPT_LOCAL_ONLY_RISK="$ARG_ACCEPT_LOCAL_ONLY_RISK"
  DEFER_REMOTE_PUSH="$ARG_DEFER_REMOTE_PUSH"

  # The interactive language_prompt() sets TEST_INTERVAL=2 mid-flow; the
  # non-interactive driver bypasses that prompt, so set the same default
  # here. Consumed at line ~1582 (build-progress.json heredoc) and ~2012
  # (template substitution) under set -u.
  TEST_INTERVAL=2

  if [ "$VALIDATE_ONLY" = true ]; then
    # Build the resolved JSON via jq for proper escaping.
    jq -n \
      --arg ts "$(date -u +%FT%TZ)" \
      --arg project "$PROJECT_NAME" \
      --arg description "$PROJECT_DESCRIPTION" \
      --arg platform "$PLATFORM" \
      --arg track "$TRACK" \
      --arg deployment "$DEPLOYMENT" \
      --arg gov_mode "$GOV_MODE" \
      --arg language "$LANGUAGE" \
      --arg project_dir "$PROJECT_DIR" \
      --arg git_host "$GIT_HOST" \
      --arg visibility "$VISIBILITY" \
      --arg remote_url "$REMOTE_URL" \
      --argjson attested "$([ "$BRANCH_PROTECTION_ATTESTED" = true ] && echo true || echo false)" \
      --argjson approvals_attested "$([ "$APPROVALS_ATTESTED" = true ] && echo true || echo false)" \
      --argjson allow_dir "$([ "$ALLOW_EXISTING_DIR" = true ] && echo true || echo false)" \
      --argjson no_remote "$([ "$NO_REMOTE_CREATION" = true ] && echo true || echo false)" \
      --argjson accept_local_only "$([ "$ACCEPT_LOCAL_ONLY_RISK" = true ] && echo true || echo false)" \
      --argjson defer_push "$([ "$DEFER_REMOTE_PUSH" = true ] && echo true || echo false)" \
      '{
        _validated: true,
        _resolved_at: $ts,
        project: $project,
        description: $description,
        platform: $platform,
        track: $track,
        deployment: $deployment,
        gov_mode: (if $gov_mode == "" then null else $gov_mode end),
        language: $language,
        project_dir: $project_dir,
        git_host: $git_host,
        visibility: $visibility,
        remote_url: (if $remote_url == "" then null else $remote_url end),
        branch_protection_attested: $attested,
        approvals_attested: $approvals_attested,
        allow_existing_dir: $allow_dir,
        no_remote_creation: $no_remote,
        accept_local_only_risk: $accept_local_only,
        defer_remote_push: $defer_push
      }'
  fi
  return 0
}

# ================================================================
# MAIN
# ================================================================
main() {
  # Parse flags. Accept both "--flag value" and "--flag=value" shapes for inputs.
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true; shift ;;
      --non-interactive)
        NON_INTERACTIVE=true; shift ;;
      --validate-only)
        VALIDATE_ONLY=true; shift ;;
      --config)
        CONFIG_FILE="$2"; shift 2 ;;
      --config=*)
        CONFIG_FILE="${1#*=}"; shift ;;
      --project)
        ARG_PROJECT="$2"; shift 2 ;;
      --project=*)
        ARG_PROJECT="${1#*=}"; shift ;;
      --description)
        ARG_DESCRIPTION="$2"; shift 2 ;;
      --description=*)
        ARG_DESCRIPTION="${1#*=}"; shift ;;
      --platform)
        ARG_PLATFORM="$2"; shift 2 ;;
      --platform=*)
        ARG_PLATFORM="${1#*=}"; shift ;;
      --track)
        ARG_TRACK="$2"; shift 2 ;;
      --track=*)
        ARG_TRACK="${1#*=}"; shift ;;
      --deployment)
        ARG_DEPLOYMENT="$2"; shift 2 ;;
      --deployment=*)
        ARG_DEPLOYMENT="${1#*=}"; shift ;;
      --gov-mode)
        ARG_GOV_MODE="$2"; shift 2 ;;
      --gov-mode=*)
        ARG_GOV_MODE="${1#*=}"; shift ;;
      --language)
        ARG_LANGUAGE="$2"; shift 2 ;;
      --language=*)
        ARG_LANGUAGE="${1#*=}"; shift ;;
      --project-dir)
        ARG_PROJECT_DIR="$2"; shift 2 ;;
      --project-dir=*)
        ARG_PROJECT_DIR="${1#*=}"; shift ;;
      --git-host)
        ARG_GIT_HOST="$2"; shift 2 ;;
      --git-host=*)
        ARG_GIT_HOST="${1#*=}"; shift ;;
      --visibility)
        ARG_VISIBILITY="$2"; shift 2 ;;
      --visibility=*)
        ARG_VISIBILITY="${1#*=}"; shift ;;
      --remote-url)
        ARG_REMOTE_URL="$2"; shift 2 ;;
      --remote-url=*)
        ARG_REMOTE_URL="${1#*=}"; shift ;;
      --branch-protection-attested)
        ARG_BRANCH_PROTECTION_ATTESTED=true; shift ;;
      --approvals-attested)
        # BL-032: proactive gitlab.com Free approvals attestation.
        ARG_APPROVALS_ATTESTED=true; shift ;;
      --allow-existing-dir)
        ARG_ALLOW_EXISTING_DIR=true; shift ;;
      --no-remote-creation)
        ARG_NO_REMOTE_CREATION=true; shift ;;
      --accept-local-only-risk)
        # BL-084: light-tier only — accept a local-only project (no remote)
        # + its data-loss risk when the initial push fails.
        ARG_ACCEPT_LOCAL_ONLY_RISK=true; shift ;;
      --defer-remote-push)
        # BL-084: light-tier only — defer the push; the Phase 1→2 gate
        # will block until the remote actually has the branch.
        ARG_DEFER_REMOTE_PUSH=true; shift ;;
      --enforcement-level)
        ARG_ENFORCEMENT_LEVEL="${2:-}"; shift 2 ;;
      --enforcement-level=*)
        ARG_ENFORCEMENT_LEVEL="${1#*=}"; shift ;;
      --confirm-pitfalls)
        ARG_CONFIRM_PITFALLS=true; shift ;;
      --help-non-interactive)
        print_help_non_interactive
        exit 0 ;;
      --help|-h)
        cat <<'HELPEOF'
Usage: ./init.sh [--dry-run] [--help]                                 (interactive)
       ./init.sh --non-interactive [--config FILE] [INPUT FLAGS...]   (scriptable)

Options:
  --dry-run                Preview what will be installed and created without executing
  --help, -h               Show this help message
  --non-interactive        Enable non-interactive mode (CI / UAT / AI agents)
  --config FILE            Read JSON config (only honored with --non-interactive)
  --validate-only          Validate inputs and print resolved config; no scaffolding
  --help-non-interactive   Show full schema + JSON example + per-flag descriptions

Non-interactive mode (for CI, UAT, AI agents):
  Required (always):       --project --platform --deployment --language
  Required (conditional):  --gov-mode (when --deployment=organizational);
                           --remote-url (when --git-host=other);
                           --branch-protection-attested (when --git-host=other)
  Defaults:                --track standard, --git-host github,
                           --visibility private, --description "",
                           --project-dir "$HOME/Code/$PROJECT"

Init logs are saved to <project>/.solo-orchestrator/init-TIMESTAMP.log
HELPEOF
        exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        echo "Run --help for usage." >&2
        exit 1 ;;
    esac
  done

  print_header "$VERSION"

  # BL-041 (2026-06-30): the write-permission preflight and the
  # framework-repo guard share a target-dir resolution step. Compute
  # _early_target once and feed it to BOTH checks, in the order:
  #   1. preflight_target_writable  — operator-facing
  #   2. guard_not_in_framework     — developer-facing
  #
  # Rationale: a real operator who points --project-dir at an unwritable
  # location should get the relevant permission error, not the framework-
  # repo refusal. The framework-repo refusal still fires (defense-in-
  # depth) when the preflight passes, and is the actual right answer for
  # the developer scenario it was designed for.
  #
  # The previous ordering also blocked tests/edge-cases-pre-init.sh E8b:
  # the harness runs init.sh from inside the framework checkout (cwd is
  # the framework repo), so the cwd check in guard_not_in_framework fired
  # before any write-permission probe had a chance. Reordering the two
  # closes that test gap without weakening either guard.
  #
  # --dry-run skips BOTH because it never actually writes anything (the
  # preview is allowed for inspection from any context, including from
  # inside the framework repo itself).
  if [ "$DRY_RUN" != true ]; then
    # Resolve the effective target dir: explicit --project-dir wins; non-interactive
    # default is $HOME/Code/$ARG_PROJECT; interactive flow resolves later via prompt
    # (in that path the cwd check is the only signal until prompts run, which is
    # the same scope as before).
    _early_target=""
    if [ -n "${ARG_PROJECT_DIR:-}" ]; then
      _early_target="$ARG_PROJECT_DIR"
    elif [ "$NON_INTERACTIVE" = true ] && [ -n "${ARG_PROJECT:-}" ]; then
      _early_target="$HOME/Code/$ARG_PROJECT"
    fi

    # 1. Operator-facing: write-permission preflight (BL-041 / audit
    # recommendation C). Must run BEFORE the framework-repo guard so the
    # permission failure mode is reachable from any cwd. preflight_target_writable
    # is a no-op when _early_target is empty (interactive flow resolves
    # target later; the existing downstream existence check at
    # collect_inputs_non_interactive::project_dir + create_project's
    # mkdir surface the same failure mode in that path).
    if ! preflight_target_writable "$_early_target"; then
      exit 1
    fi

    # 2. Developer-facing: framework-repo guard. security-audits-1
    # (S3, 2026-04-26 audit sweep) added the optional target argument so
    # this catches a malicious or honest-mistake caller that supplies
    # --project-dir=$FRAMEWORK_REPO from a benign cwd.
    if ! guard_not_in_framework "$_early_target"; then
      exit 1
    fi
    unset _early_target
  fi

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}${BOLD}DRY RUN MODE — no changes will be made${NC}"
    echo ""
  fi

  # Initialize logging to temp location (moved to project dir after creation)
  INIT_LOG_DIR=$(mktemp -d)
  init_log "$INIT_LOG_DIR"
  log_section "Prerequisites"

  # BL-016: dispatch to non-interactive collection or fall through to interactive.
  if [ "$NON_INTERACTIVE" = true ]; then
    if ! collect_inputs_non_interactive; then
      exit 1
    fi
    if [ "$VALIDATE_ONLY" = true ]; then
      exit 0
    fi
    # Derive POC_MODE from GOV_MODE for downstream consumers (existing code uses POC_MODE).
    # The interactive flow at init.sh:381 maps "Production" -> POC_MODE="" because Production
    # is the absence of POC, not a POC mode itself. Mirror that here — process-checklist.sh
    # start_phase4 treats any non-null poc_mode as a POC and blocks Phase 4.
    case "$GOV_MODE" in
      production) POC_MODE="" ;;
      *)          POC_MODE="$GOV_MODE" ;;
    esac

    # BL-030: resolve enforcement_level. Choosable iff deployment=personal
    # OR (organizational AND poc_mode=private_poc). Otherwise forced strict.
    ENFORCEMENT_LEVEL="$ARG_ENFORCEMENT_LEVEL"
    [ "$ARG_CONFIRM_PITFALLS" = true ] && CONFIRM_PITFALLS=1
    _bl030_choosable=0
    if [ "$DEPLOYMENT" = "personal" ]; then _bl030_choosable=1; fi
    if [ "$DEPLOYMENT" = "organizational" ] && [ "$POC_MODE" = "private_poc" ]; then _bl030_choosable=1; fi
    if [ "$_bl030_choosable" = "0" ]; then
      if [ -n "$ENFORCEMENT_LEVEL" ] && [ "$ENFORCEMENT_LEVEL" != "strict" ]; then
        print_warn "BL-030: --enforcement-level '$ENFORCEMENT_LEVEL' ignored — deployment/poc_mode forces strict."
      fi
      ENFORCEMENT_LEVEL="strict"
    else
      [ -z "$ENFORCEMENT_LEVEL" ] && ENFORCEMENT_LEVEL="strict"
      case "$ENFORCEMENT_LEVEL" in
        strict) ;;
        light|no)
          if [ "$CONFIRM_PITFALLS" != "1" ]; then
            print_fail "BL-030: non-interactive downgrade to '$ENFORCEMENT_LEVEL' requires --confirm-pitfalls."
            exit 1
          fi
          ;;
        *)
          print_fail "BL-030: unknown --enforcement-level '$ENFORCEMENT_LEVEL' (expected: no | light | strict)."
          exit 1
          ;;
      esac
    fi
    # Pass 3 of collect_inputs_non_interactive already verified required tools.
  else
    if [ -n "$CONFIG_FILE" ]; then
      print_warn "--config requires --non-interactive; ignoring config file"
    fi
    if [ -n "$ARG_PROJECT$ARG_PLATFORM$ARG_DEPLOYMENT$ARG_LANGUAGE" ]; then
      print_warn "Input flags require --non-interactive; ignoring (interactive flow will prompt)"
    fi
    check_prerequisites
    collect_project_info
  fi

  log_section "Project Configuration"
  log_line "Project: $PROJECT_NAME"
  log_line "Platform: $PLATFORM"
  log_line "Language: $LANGUAGE"
  log_line "Track: $TRACK"
  log_line "Deployment: $DEPLOYMENT"
  log_line "POC Mode: ${POC_MODE:-none}"

  if [ "$DRY_RUN" = true ]; then
    dry_run_summary
  else
    log_section "Tool Resolution & Installation"
    resolve_and_install_tools

    log_section "Project Creation"
    # BL-109-CURRENCY: start a fresh render-base scratch file BEFORE create_project
    # so the render sites inside it (A2 template copies, PROJECT_INTAKE, CLAUDE.md)
    # can stash {template sha, output sha} for the birth stamp.
    soif_currency_renderbase_init
    create_project

    # BL-030: persist enforcement_level + deployment + poc_mode to manifest,
    # initialize detection baseline, audit-row the level set, and (if strict)
    # install the filesystem gate.
    bl030_finalize_init

    # Move log to project directory
    if [ -d "$PROJECT_DIR" ] && [ -n "$LOG_FILE" ]; then
      mkdir -p "$PROJECT_DIR/.solo-orchestrator"
      local final_log="$PROJECT_DIR/.solo-orchestrator/$(basename "$LOG_FILE")"
      mv "$LOG_FILE" "$final_log"
      LOG_FILE="$final_log"
      log_line "Log relocated to project directory"
      rmdir "$INIT_LOG_DIR" 2>/dev/null || true
    fi

    bash "$PROJECT_DIR/scripts/verify-install.sh" --auto-fix || true
    # BL-064: if any tracked failure occurred during the run, replace the
    # "Setup Complete" banner with "Setup INCOMPLETE" and surface a
    # non-zero exit so wrapper scripts that gate downstream actions on
    # init.sh succeeding observe the gap. record_init_failure callers
    # (currently the create_and_protect_remote outer wrap) populate the
    # INIT_FAILURES array; see init.sh header block for the contract.
    if [ "${#INIT_FAILURES[@]}" -gt 0 ]; then
      print_init_failures_summary
      finalize_log
      return 2
    fi
    print_next_steps
  fi

  finalize_log
}

# Resolve host/visibility/mode from --git-host / --visibility flags, intake
# answers, or interactive prompts. Sets globals consumed by both
# prepare_initial_state_for_commit and create_and_protect_remote so the
# resolution happens exactly once per init.
_resolve_host_visibility_mode() {
  # BL-016: prefer non-interactive top-level variables when set.
  if [ -n "${GIT_HOST:-}" ]; then
    _RESOLVED_HOST="$GIT_HOST"
  elif [ -f .claude/intake-progress.json ]; then
    _RESOLVED_HOST=$(jq -r '.answers.git_host // empty' .claude/intake-progress.json 2>/dev/null || echo "")
  fi
  if [ -n "${VISIBILITY:-}" ]; then
    _RESOLVED_VISIBILITY="$VISIBILITY"
  elif [ -f .claude/intake-progress.json ]; then
    _RESOLVED_VISIBILITY=$(jq -r '.answers.repo_visibility // empty' .claude/intake-progress.json 2>/dev/null || echo "")
  fi
  # Fallback: prompt inline if neither source supplied a value (interactive mode only).
  [ -z "${_RESOLVED_HOST:-}" ]       && _RESOLVED_HOST=$(prompt_choice "Git host:" "github" "gitlab" "bitbucket" "other")
  [ -z "${_RESOLVED_VISIBILITY:-}" ] && _RESOLVED_VISIBILITY=$(prompt_choice "Repository visibility:" "private" "public")

  # Map DEPLOYMENT "organizational" → "org" for consistency with spec
  _RESOLVED_MODE="$DEPLOYMENT"
  [ "$_RESOLVED_MODE" = "organizational" ] && _RESOLVED_MODE="org"
  # Org forces private
  if [ "$_RESOLVED_MODE" = "org" ] && [ "$_RESOLVED_VISIBILITY" != "private" ]; then
    print_warn "Org mode forces private visibility (overriding '$_RESOLVED_VISIBILITY')"
    _RESOLVED_VISIBILITY="private"
  fi
}

# Lay down ALL durable state BEFORE the chore-init commit so it is captured
# atomically. Combines what used to be (a) create_and_protect_remote's early
# manifest seed (host/mode), (b) bl030_finalize_init's manifest BL-030 fields
# + bypass-audit init row + filesystem gate install. The chore-init commit
# now includes manifest with all fields, bypass-audit.json with the init
# row, and the filesystem-gate hooks when strict.
prepare_initial_state_for_commit() {
  [ -d "$PROJECT_DIR" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  _resolve_host_visibility_mode

  mkdir -p .claude

  # Seed manifest with all framework-managed fields. remote_url stays "" until
  # create_and_protect_remote actually creates the repo; if it doesn't, the
  # empty value is the documented "no remote" sentinel.
  local poc_val
  if [ -n "$POC_MODE" ]; then
    poc_val="$POC_MODE"
  else
    poc_val=""
  fi
  local manifest=".claude/manifest.json"
  if [ -f "$manifest" ]; then
    local tmp
    tmp=$(mktemp)
    if [ -n "$poc_val" ]; then
      jq --arg h "$_RESOLVED_HOST" --arg m "$_RESOLVED_MODE" \
         --arg dep "$DEPLOYMENT" --arg pm "$poc_val" --arg lvl "$ENFORCEMENT_LEVEL" \
         '. + {host:$h, mode:$m, remote_url:"", deployment:$dep, poc_mode:$pm, enforcement_level:$lvl}' \
         "$manifest" > "$tmp" && mv "$tmp" "$manifest"
    else
      jq --arg h "$_RESOLVED_HOST" --arg m "$_RESOLVED_MODE" \
         --arg dep "$DEPLOYMENT" --arg lvl "$ENFORCEMENT_LEVEL" \
         '. + {host:$h, mode:$m, remote_url:"", deployment:$dep, poc_mode:null, enforcement_level:$lvl}' \
         "$manifest" > "$tmp" && mv "$tmp" "$manifest"
    fi
  else
    if [ -n "$poc_val" ]; then
      jq -n --arg h "$_RESOLVED_HOST" --arg m "$_RESOLVED_MODE" \
            --arg dep "$DEPLOYMENT" --arg pm "$poc_val" --arg lvl "$ENFORCEMENT_LEVEL" \
            '{host:$h, mode:$m, remote_url:"", deployment:$dep, poc_mode:$pm, enforcement_level:$lvl}' \
        > "$manifest"
    else
      jq -n --arg h "$_RESOLVED_HOST" --arg m "$_RESOLVED_MODE" \
            --arg dep "$DEPLOYMENT" --arg lvl "$ENFORCEMENT_LEVEL" \
            '{host:$h, mode:$m, remote_url:"", deployment:$dep, poc_mode:null, enforcement_level:$lvl}' \
        > "$manifest"
    fi
  fi

  # BL-109-CURRENCY: stamp the currency inventory block (design v1.1 §2-L0) into
  # .claude/manifest.json at birth, immediately AFTER the framework-managed
  # manifest seed above. Additive — every pre-existing field (soloFrameworkCommit
  # / frameworkCommit / host / mode / … pins included) is preserved. files{} is
  # derived MECHANICALLY from the shipped-set parsers and hashed from the
  # just-scaffolded project tree (all cp/render/hook steps precede this call);
  # render bases were captured AT the render sites into
  # $SOIF_CURRENCY_RENDERBASE_FILE. This is the UNIVERSAL birth site —
  # prepare_initial_state_for_commit runs on EVERY path (incl.
  # --no-remote-creation), unlike the soloFrameworkCommit stamp, which is
  # remote-path-only (see the S1 PR body's declared deviation). Skipped as a
  # no-op when jq is unavailable (same contract as the soloFrameworkCommit stamp).
  # Re-stamping on sync/apply (soloFrameworkPath refresh) is S3a — out of scope.
  soif_currency_stamp "$manifest" "$SCRIPT_DIR/init.sh" "$SCRIPT_DIR" "." "$LANGUAGE" "$SCRIPT_DIR"   # BL-109-CURRENCY load-bearing stamping call

  # Seed bypass-audit.json with the init enforcement_level_set row.
  [ -f .claude/bypass-audit.json ] || echo "[]" > .claude/bypass-audit.json
  local _ts _row _tmp
  _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  _row=$(jq -nc \
    --arg ts "$_ts" \
    --arg lvl "$ENFORCEMENT_LEVEL" \
    --arg confirmed "$CONFIRM_PITFALLS" \
    '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"framework",
      enforcement_level_at_event:$lvl,
      details:{level:$lvl, confirmed_pitfalls:($confirmed=="1"), source:"init"},
      user_response:"n/a", final_outcome:"recorded_only"}')
  _tmp=$(mktemp)
  jq --argjson r "$_row" '. + [$r]' .claude/bypass-audit.json > "$_tmp" \
    && mv "$_tmp" .claude/bypass-audit.json

  # Install filesystem gate when strict (puts the hook in .git/hooks/ before
  # the chore-init commit so the marker block is consistent with the rest of
  # the BL-030 surface).
  if [ "$ENFORCEMENT_LEVEL" = "strict" ]; then
    bash "$SCRIPT_DIR/scripts/install-filesystem-gates.sh" --install "$PROJECT_DIR" >/dev/null 2>&1 || \
      print_warn "BL-030: filesystem-gate install failed — strict enforcement degraded."
  fi
}

# Capture any post-remote state writes (manifest.remote_url update, branch-
# protection attestation, phase2_init.steps_completed) in a chore-finalize
# commit so the working tree stays clean after init.sh exits. No-op when
# nothing changed (e.g. --no-remote-creation, which sets remote_url to the
# same "" already in HEAD).
finalize_init_commit() {
  [ -d "$PROJECT_DIR/.git" ] || return 0
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    return 0
  fi
  git add -A
  git commit -q --no-verify -m "chore: record host setup outcome (init finalize)" 2>/dev/null || true
  # Refresh detection baseline to the finalize commit so subsequent commits
  # are correctly detected as new work, not as init-time activity.
  ( git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt ) || true
}

# Legacy entry point. Pre-fix this function did all the BL-030 state writes
# (manifest fields, bypass-audit init row, filesystem gate install) AFTER
# the chore-init commit, leaving them uncommitted. The writes have moved
# into prepare_initial_state_for_commit so they land in the initial commit.
# The function is retained as a no-op so any external caller continues to
# work; the baseline refresh now happens in create_project after each
# commit point (chore-init + chore-finalize) so this is correctly redundant.
bl030_finalize_init() {
  return 0
}

main "$@"

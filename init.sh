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

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

print_header() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║         Solo Orchestrator — Project Init v${VERSION}          ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
print_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

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

# ================================================================
# PHASE 1: Prerequisites Check
# ================================================================
check_prerequisites() {
  print_step "Checking prerequisites..."
  local os_type
  os_type="$(uname -s)"
  local missing_required=()

  # --- Git (required) ---
  if command -v git &>/dev/null; then
    print_ok "Git $(git --version | awk '{print $3}')"
  else
    print_fail "Git not found"
    local git_installed=false
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
      else
        echo "  Install with your distribution's package manager (e.g., sudo apt install git)"
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
    if [ "$node_major" -ge 18 ]; then
      print_ok "Node.js $node_version"
    else
      print_warn "Node.js $node_version (18+ recommended)"
    fi
  else
    print_warn "Node.js not found (used by Snyk, license-checker, and JS/TS projects)"
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      prompt_install "Node.js 22 LTS" "brew install node@22 && brew link --overwrite node@22"
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        prompt_install "Node.js" "sudo apt install -y nodejs npm" true
      elif command -v dnf &>/dev/null; then
        prompt_install "Node.js" "sudo dnf install -y nodejs npm" true
      else
        echo "  Install Node.js 18+: https://nodejs.org/"
      fi
    fi
  fi

  # --- jq (required by Claude Dev Framework) ---
  if command -v jq &>/dev/null; then
    print_ok "jq $(jq --version 2>/dev/null)"
  else
    print_warn "jq not found (required by Claude Dev Framework for JSON operations)"
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      prompt_install "jq" "brew install jq"
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        prompt_install "jq" "sudo apt install -y jq" true
      elif command -v dnf &>/dev/null; then
        prompt_install "jq" "sudo dnf install -y jq" true
      else
        echo "  Install manually: https://jqlang.github.io/jq/download/"
      fi
    fi
  fi

  # --- Docker (optional) ---
  if command -v docker &>/dev/null; then
    print_ok "Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
  else
    print_warn "Docker not found (optional — needed for OWASP ZAP DAST scanning)"
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      echo "  Install with: brew install --cask docker"
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        echo "  Install with: sudo apt install -y docker.io && sudo usermod -aG docker \$USER"
      elif command -v dnf &>/dev/null; then
        echo "  Install with: sudo dnf install -y docker && sudo usermod -aG docker \$USER"
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
      fi
    fi
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
  if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
    if jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
      print_ok "Context7 MCP server configured"
    else
      print_warn "Context7 MCP not found (recommended — up-to-date library documentation)"
      if command -v node &>/dev/null; then
        prompt_install "Context7 MCP" "claude mcp add context7 -- npx -y @upstash/context7-mcp@latest"
      else
        echo "  Requires Node.js. Install Node.js first, then: claude mcp add context7 -- npx -y @upstash/context7-mcp@latest"
      fi
    fi
  else
    print_info "Context7 MCP: cannot check (no Claude settings or jq missing)"
  fi

  # --- Qdrant MCP (recommended for persistent semantic memory) ---
  if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
    if jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
      print_ok "Qdrant MCP server configured"
    else
      print_warn "Qdrant MCP not found (recommended — persistent semantic memory across sessions)"
      # Check if we can auto-setup: needs Docker + Python (uv)
      if command -v docker &>/dev/null; then
        # Check if Qdrant container is already running
        local qdrant_running=false
        if docker ps --format '{{.Image}}' 2>/dev/null | grep -q "qdrant"; then
          qdrant_running=true
          print_ok "Qdrant container already running"
        fi

        if [ "$qdrant_running" = false ]; then
          read -rp "$(echo -e "  ${BOLD}Start a local Qdrant instance via Docker? [Y/n]${NC}: ")" qdrant_reply
          if [[ ! "$qdrant_reply" =~ ^[Nn] ]]; then
            print_info "Pulling and starting Qdrant..."
            if docker run -d --name qdrant \
              -p 6333:6333 -p 6334:6334 \
              -v qdrant_storage:/qdrant/storage \
              --restart unless-stopped \
              qdrant/qdrant:latest 2>&1; then
              print_ok "Qdrant running at http://localhost:6333"
              qdrant_running=true
            else
              print_warn "Failed to start Qdrant container"
            fi
          fi
        fi

        # If Qdrant is running, register the MCP server
        if [ "$qdrant_running" = true ]; then
          if command -v uvx &>/dev/null; then
            read -rp "$(echo -e "  ${BOLD}Register Qdrant MCP server with Claude Code? [Y/n]${NC}: ")" mcp_reply
            if [[ ! "$mcp_reply" =~ ^[Nn] ]]; then
              if claude mcp add -s user \
                -e QDRANT_URL=http://localhost:6333 \
                -e COLLECTION_NAME=claude-memory \
                qdrant -- uvx --python 3.13 mcp-server-qdrant 2>/dev/null; then
                print_ok "Qdrant MCP server registered (collection: claude-memory)"
              else
                print_warn "Failed to register Qdrant MCP. Register manually:"
                echo "    claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
              fi
            fi
          else
            print_warn "uv/uvx not found — needed to run mcp-server-qdrant"
            echo "  Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
            echo "  Then: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
          fi
        fi
      else
        echo "  Requires Docker (for Qdrant server) and Python/uv (for MCP client)"
        echo "  1. Install Docker: https://docs.docker.com/get-docker/"
        echo "  2. Start Qdrant: docker run -d -p 6333:6333 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest"
        echo "  3. Register MCP: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
      fi
    fi
  else
    print_info "Qdrant MCP: cannot check (no Claude settings or jq missing)"
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
  # Scan release pipelines for platforms not already found
  for f in "$SCRIPT_DIR/templates/pipelines/release/"*.yml; do
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

  TRACK=$(prompt_choice "Project track:" "light" "standard" "full")

  DEPLOYMENT=$(prompt_choice "Personal or organizational?" "personal" "organizational")

  # Auto-discover available languages from CI pipeline templates
  local available_languages=()
  for f in "$SCRIPT_DIR/templates/pipelines/ci/"*.yml; do
    [ -f "$f" ] || continue
    local lname
    lname=$(basename "$f" .yml)
    [ "$lname" = "other" ] && continue  # add "other" last as fallback
    available_languages+=("$lname")
  done
  available_languages+=("other")

  LANGUAGE=$(prompt_choice "Primary language:" "${available_languages[@]}")

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

  # Determine project directory
  PROJECT_DIR=$(prompt_input "Project directory" "$HOME/projects/$PROJECT_NAME")

  echo ""
  print_info "Project: $PROJECT_NAME"
  print_info "Platform: $PLATFORM | Track: $TRACK | Language: $LANGUAGE"
  print_info "Directory: $PROJECT_DIR"
  echo ""

  read -rp "$(echo -e "${BOLD}Continue? [Y/n]${NC}: ")" confirm
  if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "Aborted."
    exit 0
  fi
}

# ================================================================
# PHASE 3: Resolve and Install Tools (Matrix-Driven)
# ================================================================
resolve_and_install_tools() {
  print_step "Resolving tool installation plan..."
  local os_type
  os_type="$(uname -s)"
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

  # Parse bucket counts
  local auto_count manual_count installed_count deferred_count
  auto_count=$(echo "$resolver_output" | jq '.auto_install | length')
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  installed_count=$(echo "$resolver_output" | jq '.already_installed | length')
  deferred_count=$(echo "$resolver_output" | jq '.deferred | length')

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

  # Will auto-install
  if [ "$auto_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${CYAN}⬇ Will auto-install${NC}"
    echo "$resolver_output" | jq -r '.auto_install[] | "    \(.name) (\(.category))"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Manual install required
  if [ "$manual_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${YELLOW}⚠ Requires manual setup${NC}"
    echo "$resolver_output" | jq -r '.manual_install[] | "    \(.name) — \(.instructions)"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Deferred
  if [ "$deferred_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${BLUE}⏳ Deferred (installed at later phases)${NC}"
    echo "$resolver_output" | jq -r '.deferred[] | "    Phase \(.phase): \(.name) (\(.category))"' | while IFS= read -r line; do
      echo -e "${BOLD}│${NC}$line"
    done
  fi

  echo -e "${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
  echo ""

  # Confirm
  read -rp "$(echo -e "${BOLD}Proceed with this plan? [Y/n]${NC}: ")" response
  if [[ "$response" =~ ^[Nn] ]]; then
    # Offer walkthrough or manual edit
    echo ""
    local config_choice
    config_choice=$(prompt_choice "How would you like to configure tools?" \
      "Guided walkthrough (step through each category)" \
      "Edit .claude/tool-preferences.json manually")

    if [ "$config_choice" = "Guided walkthrough (step through each category)" ]; then
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
    else
      # Write defaults and let user edit
      write_tool_preferences "$resolver_output" "$dev_os" "$PROJECT_DIR"
      echo ""
      print_info "Default preferences written to: $PROJECT_DIR/.claude/tool-preferences.json"
      print_info "Edit the file, then press Enter to continue."
      read -rp ""
      # Re-resolve after manual edit
      resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
        --dev-os "$dev_os" \
        --platform "$PLATFORM" \
        --language "$LANGUAGE" \
        --track "$TRACK" \
        --phase 2 \
        --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" \
        --tool-prefs "$PROJECT_DIR/.claude/tool-preferences.json" 2>/dev/null) || true
    fi

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
      print_info "Installing $tool_name..."
      if eval "$tool_cmd" 2>/dev/null; then
        print_ok "$tool_name installed"
      else
        print_warn "Could not install $tool_name. Install manually: $tool_cmd"
      fi
    done
  fi

  # Show manual install reminders
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
  echo "**Resolved for:** $(uname -s) / $PLATFORM / $LANGUAGE / $TRACK track" >> PROJECT_INTAKE.md
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
  mkdir -p docs/framework docs/platform-modules docs/test-results

  cp "$SCRIPT_DIR/docs/builders-guide.md" docs/framework/
  cp "$SCRIPT_DIR/docs/governance-framework.md" docs/framework/
  cp "$SCRIPT_DIR/docs/executive-review.md" docs/framework/
  cp "$SCRIPT_DIR/docs/cli-setup-addendum.md" docs/framework/
  cp "$SCRIPT_DIR/docs/user-guide.md" docs/framework/
  cp "$SCRIPT_DIR/docs/security-scan-guide.md" docs/framework/

  # Copy evaluation prompts (project-level reviews for Phase 3 validation)
  print_info "Copying evaluation prompts..."
  if [ -d "$SCRIPT_DIR/evaluation-prompts/Projects" ]; then
    mkdir -p evaluation-prompts/Projects
    cp -r "$SCRIPT_DIR/evaluation-prompts/Projects/"* evaluation-prompts/Projects/ 2>/dev/null || true
  fi

  # Copy utility scripts into the project (self-contained after init)
  print_info "Copying utility scripts..."
  mkdir -p scripts
  cp "$SCRIPT_DIR/scripts/validate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-updates.sh" scripts/
  cp "$SCRIPT_DIR/scripts/resume.sh" scripts/
  cp "$SCRIPT_DIR/scripts/intake-wizard.sh" scripts/
  cp "$SCRIPT_DIR/scripts/resolve-tools.sh" scripts/
  cp "$SCRIPT_DIR/scripts/upgrade-project.sh" scripts/
  cp "$SCRIPT_DIR/scripts/verify-install.sh" scripts/
  cp "$SCRIPT_DIR/scripts/test-gate.sh" scripts/
  chmod +x scripts/validate.sh scripts/check-phase-gate.sh scripts/check-updates.sh scripts/resume.sh scripts/intake-wizard.sh scripts/resolve-tools.sh scripts/upgrade-project.sh scripts/verify-install.sh scripts/test-gate.sh

  # Copy intake suggestion files
  mkdir -p templates/intake-suggestions
  cp "$SCRIPT_DIR/templates/intake-suggestions/"*.json templates/intake-suggestions/

  # Copy tool matrix files (for phase gate and track upgrade resolution)
  mkdir -p templates/tool-matrix
  cp "$SCRIPT_DIR/templates/tool-matrix/"*.json templates/tool-matrix/

  # Copy UAT template and create session directory structure
  mkdir -p tests/uat/templates tests/uat/sessions
  cp "$SCRIPT_DIR/templates/uat-test-template.md" tests/uat/templates/test-session-template.md

  # Copy the correct platform module (auto-discovered)
  local platform_module="$SCRIPT_DIR/docs/platform-modules/${PLATFORM}.md"
  if [ -f "$platform_module" ]; then
    cp "$platform_module" docs/platform-modules/
    print_ok "Platform module: $PLATFORM"
  else
    print_info "No platform module for '$PLATFORM'. The Builder's Guide works standalone."
  fi

  # Initialize git early — Claude Dev Framework requires a git repo
  print_info "Initializing Git repository..."
  git init -q
  # Remove hook samples so framework doesn't misdetect as existing project
  rm -f .git/hooks/*.sample

  # Install Claude Dev Framework
  # The framework uses a global clone at ~/.claude-dev-framework shared across
  # all projects. Its own init.sh handles per-project installation (hooks,
  # rules, manifest, settings.json).
  # MIT-licensed: https://github.com/kraulerson/claude-dev-framework
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"

  print_info "Installing Claude Dev Framework..."
  if command -v git &>/dev/null; then
    # Step 1: Ensure global clone exists
    if [ ! -d "$FRAMEWORK_CLONE/.git" ]; then
      print_info "Cloning Claude Dev Framework to $FRAMEWORK_CLONE..."
      git clone -q --depth 1 https://github.com/kraulerson/claude-dev-framework.git "$FRAMEWORK_CLONE" 2>/dev/null || true
    else
      print_ok "Claude Dev Framework already installed at $FRAMEWORK_CLONE"
    fi

    # Step 2: Run the framework's own init from the project directory
    if [ -d "$FRAMEWORK_CLONE/.git" ] && [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
      local branch
      branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
      local dev_os
      dev_os=$(uname -s)

      # Map platform to framework's target platform format
      local target_platform="$PLATFORM"
      case "$PLATFORM" in
        web) target_platform="web" ;;
        desktop) target_platform="$dev_os desktop" ;;
        mobile) target_platform="iOS/Android" ;;
        *) target_platform="$PLATFORM" ;;
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

      # Map Solo Orchestrator platform to framework profile name
      local fw_profile
      case "$PLATFORM" in
        web)     fw_profile="web-app" ;;
        desktop) fw_profile="desktop-app" ;;
        mobile)  fw_profile="mobile-app" ;;
        *)       fw_profile="cli-tool" ;;
      esac

      # Run the framework's init with:
      #   --prepopulate: skip interactive discovery interview (v4.0.0+)
      #   --skip-plugin-check: Superpowers/Context7 already checked above
      # Pipe the profile name for the interactive profile detection prompt.
      print_info "Running Claude Dev Framework init..."
      (cd "$PROJECT_DIR" && echo "$fw_profile" | bash "$FRAMEWORK_CLONE/scripts/init.sh" \
        --prepopulate "$discovery_tmp" --skip-plugin-check 2>&1) || {
        print_warn "Claude Dev Framework init encountered an issue."
        print_warn "You can run it manually later: bash ~/.claude-dev-framework/scripts/init.sh"
      }
      rm -f "$discovery_tmp"

      if [ -f ".claude/manifest.json" ]; then
        print_ok "Claude Dev Framework installed and configured"
      else
        print_warn "Claude Dev Framework install may be incomplete. Run manually: bash ~/.claude-dev-framework/scripts/init.sh"
      fi
    else
      print_warn "Could not install Claude Dev Framework. The fallback pre-commit hook will still be installed."
      print_warn "Install manually: git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework"
      print_warn "Then from your project: bash ~/.claude-dev-framework/scripts/init.sh"
    fi
  fi

  # Copy intake template
  cp "$SCRIPT_DIR/templates/project-intake.md" PROJECT_INTAKE.md

  # Append tooling configuration summary to PROJECT_INTAKE.md
  if [ -n "${RESOLVER_OUTPUT:-}" ]; then
    append_intake_tooling_summary "$RESOLVER_OUTPUT"
  fi

  # Generate phase state tracking
  print_info "Generating phase state..."
  mkdir -p .claude
  cat > .claude/phase-state.json << PHEOF
{
  "project": "$PROJECT_NAME",
  "framework_version": "1.0",
  "current_phase": 0,
  "gates": {
    "phase_0_to_1": null,
    "phase_1_to_2": null,
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
  "test_interval": $TEST_INTERVAL,
  "last_test_session": null,
  "testing_required": false,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 0
}
BPEOF
  print_ok "Build progress tracking initialized (test interval: every $TEST_INTERVAL features)"

  # Write tool-preferences.json (from resolver output stored earlier)
  if [ -n "${RESOLVER_OUTPUT:-}" ]; then
    write_tool_preferences "$RESOLVER_OUTPUT" "$RESOLVER_DEV_OS" "$PROJECT_DIR"
    print_ok "Tool preferences written to .claude/tool-preferences.json"
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
  # independent of whether the Claude Dev Framework clone succeeded.
  # If the Claude Dev Framework is installed and activates its own hooks, those
  # will provide deeper coverage. This hook remains as the safety net.
  print_info "Installing pre-commit hook..."
  install_precommit_hook

  git add -A
  git commit -q -m "chore: initialize Solo Orchestrator project

Project: $PROJECT_NAME
Platform: $PLATFORM
Track: $TRACK
Framework: Solo Orchestrator v1.0"

  echo ""
  print_ok "Project created at $PROJECT_DIR"
}

# ================================================================
# Pre-Commit Hook (Fallback Enforcement)
# ================================================================
install_precommit_hook() {
  mkdir -p .git/hooks

  # Determine source file extensions and test patterns for this language
  local src_ext test_pattern
  case "$LANGUAGE" in
    typescript|javascript) src_ext="ts|tsx|js|jsx"; test_pattern="\\.(test|spec)\\.(ts|tsx|js|jsx)$" ;;
    python)                src_ext="py";            test_pattern="(test_.*|.*_test)\\.py$" ;;
    rust)                  src_ext="rs";            test_pattern="" ;;  # Rust tests are inline (#[cfg(test)])
    csharp)                src_ext="cs";            test_pattern="Tests?\\.cs$" ;;
    kotlin)                src_ext="kt";            test_pattern="Test\\.kt$" ;;
    java)                  src_ext="java";          test_pattern="Test\\.java$" ;;
    go)                    src_ext="go";            test_pattern="_test\\.go$" ;;
    dart)                  src_ext="dart";          test_pattern="_test\\.dart$" ;;
    *)                     src_ext="";              test_pattern="" ;;
  esac

  cat > .git/hooks/pre-commit << 'HOOKEOF'
#!/usr/bin/env bash
# Solo Orchestrator — Fallback Pre-Commit Hook
# Provides baseline enforcement: secret detection + SAST + test co-location check.
# If the Claude Dev Framework is active, its hooks provide deeper coverage.

set -euo pipefail

FAILED=0

# --- Secret Detection (gitleaks) ---
if command -v gitleaks &>/dev/null; then
  if ! gitleaks protect --staged --verbose --no-banner 2>/dev/null; then
    echo ""
    echo "[BLOCKED] gitleaks detected secrets in staged files."
    echo "  Remove the secrets, use environment variables or a secrets manager,"
    echo "  and rotate any credentials that were exposed."
    FAILED=1
  fi
else
  echo "[WARN] gitleaks not found — secret detection skipped."
  echo "  Install: brew install gitleaks (macOS) or https://github.com/gitleaks/gitleaks/releases"
fi


# --- SAST Quick Scan (Semgrep) ---
if command -v semgrep &>/dev/null; then
  # Scan only staged files for fast pre-commit feedback
  staged_files=$(git diff --cached --name-only --diff-filter=ACM)
  if [ -n "$staged_files" ]; then
    if ! echo "$staged_files" | xargs semgrep scan --config=p/owasp-top-ten --quiet --no-git-ignore 2>/dev/null; then
      echo ""
      echo "[BLOCKED] Semgrep detected security issues in staged files."
      echo "  Review and fix the findings above before committing."
      FAILED=1
    fi
  fi
else
  echo "[WARN] semgrep not found — pre-commit SAST skipped."
  echo "  Install: brew install semgrep (macOS) or pip install semgrep"
fi

HOOKEOF

  # Append the test co-location check only if we have a meaningful pattern
  # (Rust uses inline tests so co-location check doesn't apply)
  if [ -n "$test_pattern" ] && [ -n "$src_ext" ]; then
    cat >> .git/hooks/pre-commit << TESTEOF

# --- Test Co-Location Check ---
# Warns (does not block) when source files are committed without corresponding test files.
# This is a heuristic — it checks the same commit, not the order of creation.
SRC_EXT_PATTERN="\\.(${src_ext})$"
TEST_PATTERN="${test_pattern}"

staged_src=\$(git diff --cached --name-only --diff-filter=ACM | grep -E "\$SRC_EXT_PATTERN" | grep -vE "\$TEST_PATTERN" | grep -vE "(config|setup|migration|seed|fixture)" || true)

if [ -n "\$staged_src" ]; then
  missing_tests=0
  while IFS= read -r src_file; do
    # Skip files that are themselves test files, configs, or generated
    [ -z "\$src_file" ] && continue
    # Check if any test file for this source is also staged
    basename_no_ext=\$(basename "\$src_file" | sed 's/\.[^.]*\$//')
    has_test=\$(git diff --cached --name-only | grep -E "\$basename_no_ext" | grep -E "\$TEST_PATTERN" || true)
    if [ -z "\$has_test" ]; then
      if [ \$missing_tests -eq 0 ]; then
        echo ""
        echo "[WARN] Source files staged without corresponding test files:"
      fi
      echo "  \$src_file"
      missing_tests=\$((missing_tests + 1))
    fi
  done <<< "\$staged_src"
  if [ \$missing_tests -gt 0 ]; then
    echo ""
    echo "  The Solo Orchestrator methodology requires test-first development."
    echo "  Consider writing tests before or alongside implementation."
    echo "  (This is a warning — commit is not blocked.)"
  fi
fi
TESTEOF
  fi

  # Append exit
  cat >> .git/hooks/pre-commit << 'EXITEOF'

exit $FAILED
EXITEOF

  chmod +x .git/hooks/pre-commit
  print_ok "Pre-commit hook installed (gitleaks secret detection + Semgrep SAST + test co-location check)"
}

# ================================================================
# Template Generators
# ================================================================
generate_claude_md() {
  cat > CLAUDE.md << CLAUDEEOF
# CLAUDE.md — $PROJECT_NAME

## Project Identity
- **Project:** $PROJECT_NAME
- **Description:** $PROJECT_DESCRIPTION
- **Platform:** $PLATFORM
- **Track:** $TRACK
- **Primary Language:** $LANGUAGE

## Framework Reference
This project follows the **Solo Orchestrator Framework v1.0**.
- Builder's Guide: \`docs/framework/builders-guide.md\`
- Platform Module: \`docs/platform-modules/\`
- Project Intake: \`PROJECT_INTAKE.md\` (fill this out first)
- Approval Log: \`APPROVAL_LOG.md\` (governance approval tracking — update at each phase gate)
- Claude Dev Framework: \`.claude/framework/\` (Git hook guardrails — see \`.claude/manifest.json\` for active profile and configuration)

## Operating Instructions
You are the AI coding agent for this Solo Orchestrator project. The human is the Orchestrator — they define intent, constraints, and validation. You provide syntax, scaffolding, and pattern execution.

### Phase Awareness
- Read the Project Intake (\`PROJECT_INTAKE.md\`) for all project constraints and decisions.
- Follow the Builder's Guide phases in sequence (Phase 0 → 1 → 2 → 3 → 4).
- Reference the Platform Module for platform-specific architecture, tooling, testing, and distribution.
- Every phase produces artifacts that gate entry into the next phase. Do not skip ahead.

### Governance Tracking
- The Approval Log (\`APPROVAL_LOG.md\`) records all phase gate approvals.
- The phase state file (\`.claude/phase-state.json\`) tracks the current phase mechanically.
- At each phase gate transition (Phase 0→1, Phase 1→2, Phase 3→4):
  1. Prompt the Orchestrator: "This phase gate requires approval. Please update APPROVAL_LOG.md with the approver name, date, method, and reference before proceeding to the next phase."
  2. After the Orchestrator confirms, update \`.claude/phase-state.json\`: set \`current_phase\` to the new phase number and set the corresponding gate date (e.g., \`"phase_0_to_1": "YYYY-MM-DD"\`).
  3. Commit both files together.
- Do not advance to the next phase until the Orchestrator confirms the Approval Log has been updated.
- For organizational deployments, verify pre-Phase 0 pre-conditions are recorded before starting Phase 0.

### Construction Rules (Phase 2)
- **Test-first:** Write failing tests before implementation. Verify they fail. Then implement.
- **One feature at a time:** Complete the full Build Loop (test → implement → security audit → document) per feature before starting the next.
- **Pin dependencies:** Exact versions only. Commit the lockfile.
- **Structured logging:** Every significant operation produces a log entry with timestamp, severity, and correlation ID.
- **No direct data model changes:** All changes go through versioned migrations.
- **Document as you go:** Update CHANGELOG.md, API docs, and the Project Bible after every feature.

### Superpowers Integration (if installed)
- Use Superpowers' brainstorming for **implementation-level design decisions within a feature** only.
- Do **not** use brainstorming for **product-level decisions** — those are in the Product Manifesto.
- Do **not** use brainstorming to reconsider **architecture decisions** — those are in the Project Bible.
- When Superpowers' writing-plans skill generates a plan, it must align with the MVP Cutline. Reject tasks for features not in the Cutline.
- Use git worktrees for feature isolation when available.

### When to Ask the Orchestrator
- Architecture decisions not covered by the Project Bible
- Ambiguous requirements not resolved by the Product Manifesto
- Security findings you cannot assess (flag severity and wait for guidance)
- Scope decisions: anything that might expand beyond the MVP Cutline
- Any decision that would be expensive to reverse

### When NOT to Ask
- Implementation details within the bounds of the Bible and Manifesto
- Test structure and assertion design (follow TDD, present at decision gate)
- Debugging and refactoring (use systematic approach, present results)
- Documentation generation (follow the templates)
- Routine security audit checks per Phase 2.4 checklist

### Upgrade Paths
This project can be upgraded without losing technical work:
- **Track upgrade** (light → standard → full): \`bash scripts/upgrade-project.sh --track standard\`
- **Deployment upgrade** (personal → organizational): \`bash scripts/upgrade-project.sh --deployment organizational\`
- **POC → Production**: \`bash scripts/upgrade-project.sh --to-production\`
All technical artifacts carry forward unchanged. Upgrades add governance requirements, tooling, and validation — they never remove work.

### Testing & Bug Workflow
- **Testing interval:** Every $TEST_INTERVAL features (configured in Intake Section 11.5)
- **Bug tracker:** Configured in Intake Section 11.5
- **Process:** After every $TEST_INTERVAL features, stop construction and run a UAT session:
  1. Check the gate: \`scripts/test-gate.sh --check-batch\`
  2. If blocked: dispatch parallel test agents (automated suite, exploratory, cross-platform)
  3. Generate test template for human tester(s) and wait for results
  4. Verify submission completeness — list incomplete scenarios, ask to continue or finish
  5. Consolidate all results into bug tracker
  6. Triage with Orchestrator (Fix Now / Defer / Won't Fix / Post-MVP)
  7. Fix all "Fix Now" bugs test-first
  8. Re-test until gate passes: \`scripts/test-gate.sh --check-batch\`
  9. Reset counter: \`scripts/test-gate.sh --reset-counter\`
- **After each feature:** \`scripts/test-gate.sh --record-feature "feature-name"\`
- **Gate enforcement:** Do NOT start the next feature until test-gate.sh --check-batch returns 0.
- **Severity rules:** SEV-1 cannot be deferred. SEV-2 can be deferred during Phase 2 but must be resolved or feature removed at Phase 2→3 gate.
CLAUDEEOF
}

generate_approval_log() {
  local today
  today=$(date +%Y-%m-%d)

  if [ "$DEPLOYMENT" = "organizational" ]; then
    cat > APPROVAL_LOG.md << ORGEOF
---
project: $PROJECT_NAME
deployment: organizational
created: $today
framework: Solo Orchestrator v1.0
---

# Approval Log — $PROJECT_NAME

This document records all governance approvals for this project. Each entry captures who approved what, when, and what evidence supports the approval. This is the auditable governance trail required by the Solo Orchestrator Enterprise Governance Framework (SOI-003-GOV, Section V).

**Instructions:** Update this log at each phase gate transition. Every approval entry must include the approver's name, role, date, method of approval, and a reference to the evidence. Do not delete or modify previous entries — append only. Git history provides tamper evidence.

---

## Pre-Phase 0: Organizational Pre-Conditions

These pre-conditions must be completed before Phase 0 begins. See Governance Framework Section V and Project Intake Section 8.

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
| 1 | AI deployment path approved | | IT Security | | Email / Ticket / Document | | |
| 2 | Insurance coverage confirmed | | Insurance Broker | | Email / Ticket / Document | | |
| 3 | Liability entity designated | | Legal / CIO | | Email / Ticket / Document | | |
| 4 | Project sponsor assigned | | Executive Sponsor | | Email / Ticket / Document | | |
| 5 | Backup maintainer designated | | Technical Lead | | Email / Ticket / Document | | |
| 6 | ITSM project registered | | ITSM / PMO | | Email / Ticket / Document | | |

---

## Phase Gate: Phase 0 → Phase 1

**Gate requirement:** Project Sponsor approves business justification and compliance screening.
**Evidence required:** Signed-off Phase 0 artifacts + compliance screening matrix.
**Reference:** Governance Framework Section V; Builder's Guide Phase 0.

| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | |
| **Role** | Project Sponsor |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | PRODUCT_MANIFESTO.md, Compliance Screening Matrix (Intake Section 8.4) |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Phase Gate: Phase 1 → Phase 2

**Gate requirement:** Senior Technical Authority approves architecture selection and security posture.
**Evidence required:** Written approval of Project Bible.
**Reference:** Governance Framework Section V; Builder's Guide Phase 1.

| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Approver** | |
| **Role** | Senior Technical Authority |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | PROJECT_BIBLE.md, Architecture Decision Records, Threat Model |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Phase Gate: Phase 3 → Phase 4

**Gate requirement:** Application Owner and IT Security approve go-live readiness.
**Evidence required:** Security scan results, penetration test report (if required), go-live checklist.
**Reference:** Governance Framework Section V; Builder's Guide Phase 3 and Phase 4.

### Application Owner Approval

| Field | Value |
|---|---|
| **Gate** | Phase 3 → Phase 4 (Application Owner) |
| **Approver** | |
| **Role** | Application Owner |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | Phase 3 test results (docs/test-results/), go-live checklist |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

### IT Security Approval

| Field | Value |
|---|---|
| **Gate** | Phase 3 → Phase 4 (IT Security) |
| **Approver** | |
| **Role** | IT Security |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | SAST/DAST results, dependency scan, SBOM, penetration test (if applicable) |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Approval History

_Append additional approvals here for post-launch changes, maintenance reviews, or re-approvals._

| Date | Gate / Event | Approver | Role | Decision | Reference |
|---|---|---|---|---|---|
| | | | | | |
ORGEOF
  else
    cat > APPROVAL_LOG.md << PERSEOF
---
project: $PROJECT_NAME
deployment: personal
created: $today
framework: Solo Orchestrator v1.0
---

# Approval Log — $PROJECT_NAME

This document records phase gate reviews for this project. For personal projects, the Orchestrator serves as their own reviewer. Update this log at each phase transition to maintain a record of what was reviewed and when.

---

## Pre-Phase 0: Pre-Conditions

| # | Pre-Condition | Status | Date | Notes |
|---|---|---|---|---|
| 1 | AI deployment path | N/A — personal project | $today | |
| 2 | Insurance coverage | N/A — personal project | $today | |
| 3 | Liability entity | N/A — personal project | $today | |
| 4 | Project sponsor | N/A — personal project | $today | |
| 5 | Backup maintainer | N/A — personal project | $today | |
| 6 | ITSM registration | N/A — personal project | $today | |

---

## Phase Gate: Phase 0 → Phase 1

| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Reviewer** | |
| **Date** | |
| **Artifacts reviewed** | PRODUCT_MANIFESTO.md |
| **Decision** | Approved / Needs revision |
| **Notes** | |

---

## Phase Gate: Phase 1 → Phase 2

| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Reviewer** | |
| **Date** | |
| **Artifacts reviewed** | PROJECT_BIBLE.md, Threat Model |
| **Decision** | Approved / Needs revision |
| **Notes** | |

---

## Phase Gate: Phase 3 → Phase 4

| Field | Value |
|---|---|
| **Gate** | Phase 3 → Phase 4 |
| **Reviewer** | |
| **Date** | |
| **Artifacts reviewed** | Phase 3 test results (docs/test-results/), go-live checklist |
| **Decision** | Approved / Needs revision |
| **Notes** | |

---

## Approval History

| Date | Gate / Event | Decision | Notes |
|---|---|---|---|
| | | | |
PERSEOF
  fi
}

generate_gitignore() {
  cat > .gitignore << 'GIEOF'
# Dependencies
node_modules/
venv/
__pycache__/
*.pyc
.pip-cache/

# Environment
.env
.env.local
.env.production
.env.*.local

# Build output
dist/
build/
out/
.next/
.nuxt/
.svelte-kit/
target/

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Test
coverage/
playwright-report/
test-results/

# Debug
*.log
npm-debug.log*

# Secrets (belt and suspenders with gitleaks)
*.pem
*.key
*.p12
*.jks
*.pfx
*.keystore
credentials.json
service-account.json
terraform.tfvars
terraform.tfvars.json
.npmrc
GIEOF

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
  esac
}

# ================================================================
# Release Pipeline Variables (language → build commands)
# ================================================================
get_release_vars() {
  case "$LANGUAGE" in
    typescript|javascript)
      RELEASE_SETUP_ACTION="actions/setup-node@v4"
      RELEASE_SETUP_VERSION_KEY="node-version"
      RELEASE_SETUP_VERSION_VALUE="'20'"
      RELEASE_INSTALL_COMMAND="npm ci"
      RELEASE_BUILD_COMMAND="npm run build"
      ;;
    python)
      RELEASE_SETUP_ACTION="actions/setup-python@v5"
      RELEASE_SETUP_VERSION_KEY="python-version"
      RELEASE_SETUP_VERSION_VALUE="'3.12'"
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
      RELEASE_SETUP_VERSION_VALUE="'8.0.x'"
      RELEASE_INSTALL_COMMAND="dotnet restore"
      RELEASE_BUILD_COMMAND="dotnet build --configuration Release"
      ;;
    kotlin|java)
      RELEASE_SETUP_ACTION="actions/setup-java@v4"
      RELEASE_SETUP_VERSION_KEY="java-version"
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
    kotlin|java)           ci_template="jvm.yml" ;;
    go)                    ci_template="go.yml" ;;
    dart)                  ci_template="dart.yml" ;;
    *)                     ci_template="other.yml" ;;
  esac

  local template_path="$SCRIPT_DIR/templates/pipelines/ci/$ci_template"
  if [ -f "$template_path" ]; then
    cp "$template_path" .github/workflows/ci.yml
  else
    print_warn "CI template not found: $template_path"
    return 1
  fi

  print_info "CI pipeline created at .github/workflows/ci.yml (language: $LANGUAGE)"
}

generate_release() {
  local release_template="$SCRIPT_DIR/templates/pipelines/release/$PLATFORM.yml"
  if [ ! -f "$release_template" ]; then
    print_info "No release pipeline template for platform '$PLATFORM'. Skipping release pipeline."
    return 0
  fi

  mkdir -p .github/workflows

  # Get language-specific build variables
  get_release_vars

  # Substitute placeholders into the release template
  sed -e "s|__SETUP_ACTION__|$RELEASE_SETUP_ACTION|g" \
      -e "s|__SETUP_VERSION_KEY__|$RELEASE_SETUP_VERSION_KEY|g" \
      -e "s|__SETUP_VERSION_VALUE__|$RELEASE_SETUP_VERSION_VALUE|g" \
      -e "s|__INSTALL_COMMAND__|$RELEASE_INSTALL_COMMAND|g" \
      -e "s|__BUILD_COMMAND__|$RELEASE_BUILD_COMMAND|g" \
      -e "s|__PROJECT_NAME__|$PROJECT_NAME|g" \
      "$release_template" > .github/workflows/release.yml

  print_info "Release pipeline created at .github/workflows/release.yml (platform: $PLATFORM)"
  print_info "Review TODOs in the release pipeline — signing, deployment, and secrets require configuration."
}

# ================================================================
# PHASE 5: Print Next Steps (health_check replaced by verify-install.sh)
# ================================================================
print_next_steps() {
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
  echo "     Run the guided wizard:  bash scripts/intake-wizard.sh"
  echo "     Or open PROJECT_INTAKE.md directly in your editor."
  echo "     The wizard offers an interactive script or AI-assisted conversation."
  echo ""

  if [ "$DEPLOYMENT" = "organizational" ]; then
    echo "  3. GOVERNANCE PRE-FLIGHT (organizational deployment):"
    echo "     Complete Section 8 of the Intake before starting."
    echo "     Required: project sponsor, backup maintainer, insurance"
    echo "     confirmation, AI deployment path approval, ITSM registration."
    echo "     Record all pre-condition approvals in APPROVAL_LOG.md."
    echo "     See docs/framework/governance-framework.md for details."
    echo ""
    echo "  4. START BUILDING:"
  else
    echo "  3. START BUILDING:"
  fi

  echo "     cd $PROJECT_DIR"
  echo "     claude"
  echo ""
  echo "     Then tell the agent:"
  echo "     \"Read CLAUDE.md, then read PROJECT_INTAKE.md. Follow the"
  echo "     Builder's Guide in docs/framework/builders-guide.md. Begin"
  echo "     Phase 0. Only ask me for clarifying questions.\""
  echo ""

  # Show dependency status and remaining optional enhancements
  echo "  INSTALLED DEPENDENCIES:"
  if [ -f "$PROJECT_DIR/.claude/manifest.json" ]; then
    echo "     ✓ Claude Dev Framework (Git hook guardrails)"
  else
    echo "     ✗ Claude Dev Framework — run: bash ~/.claude-dev-framework/scripts/init.sh"
  fi
  if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
    local _sp _c7
    _sp=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
    _c7=$(jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1 && echo "true" || echo "false")
    if [ "$_sp" = "true" ]; then
      echo "     ✓ Superpowers plugin (agentic skills for Phase 2)"
    else
      echo "     ✗ Superpowers plugin — run: claude → /plugins → search 'superpowers' → install"
    fi
    if [ "$_c7" = "true" ]; then
      echo "     ✓ Context7 MCP (up-to-date library documentation)"
    else
      echo "     ✗ Context7 MCP — run: claude mcp add context7 -- npx -y @upstash/context7-mcp@latest"
    fi
    local _qd
    _qd=$(jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1 && echo "true" || echo "false")
    if [ "$_qd" = "true" ]; then
      echo "     ✓ Qdrant MCP (persistent semantic memory across sessions)"
    else
      echo "     ✗ Qdrant MCP — see docs/framework/cli-setup-addendum.md for setup"
    fi
  fi
  echo ""
  if [ -f "$PROJECT_DIR/.github/workflows/release.yml" ]; then
    echo "  RELEASE PIPELINE (review before first release):"
    echo "     .github/workflows/release.yml"
    echo "     - Review and configure TODOs (code signing, deployment, secrets)"
    echo "     - The release pipeline runs on version tags: git tag v1.0.0 && git push --tags"
    echo ""
  fi
  echo "  VALIDATION (run periodically to check framework compliance):"
  echo "     cd $PROJECT_DIR"
  echo "     bash scripts/validate.sh              — check framework compliance"
  echo "     bash scripts/check-updates.sh         — check for upstream framework updates"
  echo "     bash scripts/resume.sh                — generate a session resume prompt"
  echo ""
  echo "  DOCUMENTATION:"
  echo "     docs/framework/user-guide.md          — Start here: step-by-step walkthrough"
  echo "     docs/framework/builders-guide.md      — The complete methodology"
  echo "     docs/framework/governance-framework.md — Enterprise governance"
  echo "     docs/framework/cli-setup-addendum.md   — Claude Code configuration"
  echo "     docs/platform-modules/                — Platform-specific guidance"
  echo ""
  if [ "$TRACK" = "light" ] || [ "$DEPLOYMENT" = "personal" ]; then
  echo "  UPGRADE (if this is a POC or light track project):"
  echo "     bash scripts/upgrade-project.sh --help     — see all upgrade options"
  echo "     bash scripts/upgrade-project.sh --to-production  — upgrade to production"
  echo ""
  fi
}

# ================================================================
dry_run_summary() {
  echo ""
  print_step "DRY RUN SUMMARY"
  echo ""

  echo -e "${BOLD}Project:${NC}"
  echo "  Name:      $PROJECT_NAME"
  echo "  Platform:  $PLATFORM"
  echo "  Track:     $TRACK"
  echo "  Language:  $LANGUAGE"
  echo "  Directory: $PROJECT_DIR"
  echo ""

  echo -e "${BOLD}Tool Resolution:${NC}"
  local dev_os
  case "$(uname -s)" in Darwin) dev_os="darwin" ;; *) dev_os="linux" ;; esac
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
  echo "  .claude/framework/                    — Claude Dev Framework hooks and rules"
  echo "  .claude/manifest.json                 — Framework configuration and metadata"
  echo "  .claude/settings.json                 — Claude Code hook configuration"
  echo "  .claude/phase-state.json              — Phase tracking"
  echo "  docs/framework/builders-guide.md      — Builder's Guide"
  echo "  docs/framework/governance-framework.md"
  echo "  docs/framework/executive-review.md"
  echo "  docs/framework/cli-setup-addendum.md"
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
# MAIN
# ================================================================
main() {
  # Parse flags
  for arg in "$@"; do
    case "$arg" in
      --dry-run)
        DRY_RUN=true
        ;;
      --help|-h)
        echo "Usage: ./init.sh [--dry-run] [--help]"
        echo ""
        echo "Creates a new Solo Orchestrator project with all framework documents,"
        echo "templates, and tooling configuration."
        echo ""
        echo "Options:"
        echo "  --dry-run   Preview what will be installed and created without executing"
        echo "  --help, -h  Show this help message"
        exit 0
        ;;
      *)
        echo "Unknown option: $arg"
        echo "Usage: ./init.sh [--dry-run] [--help]"
        exit 1
        ;;
    esac
  done

  print_header

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}${BOLD}DRY RUN MODE — no changes will be made${NC}"
    echo ""
  fi

  check_prerequisites
  collect_project_info

  if [ "$DRY_RUN" = true ]; then
    dry_run_summary
  else
    resolve_and_install_tools
    create_project
    bash "$PROJECT_DIR/scripts/verify-install.sh" --auto-fix || true
    print_next_steps
  fi
}

main "$@"

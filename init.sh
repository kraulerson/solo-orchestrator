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

source "$SCRIPT_DIR/scripts/lib/helpers.sh"

# ================================================================
# PHASE 1: Prerequisites Check
# ================================================================
check_prerequisites() {
  print_step "Checking prerequisites..."
  local os_type
  os_type="$(uname -s)"
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
    print_fail "Git not found"
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

  # --- jq (required by Claude Dev Framework) ---
  if command -v jq &>/dev/null; then
    print_ok "jq $(jq --version 2>/dev/null)"
  else
    print_warn "jq not found (required by Claude Dev Framework for JSON operations)"
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

  # --- Claude Dev Framework ---
  if [ -d "$HOME/.claude-dev-framework/.git" ] && [ -f "$HOME/.claude-dev-framework/scripts/init.sh" ]; then
    print_ok "Claude Dev Framework installed"
  else
    print_info "Claude Dev Framework will be installed during project creation"
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
  # Check both config locations: ~/.claude/settings.json and ~/.claude.json (user scope)
  local _c7_found=false
  if command -v jq &>/dev/null; then
    if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
       ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
      _c7_found=true
    fi
  fi
  if [ "$_c7_found" = true ]; then
    print_ok "Context7 MCP server configured"
  elif command -v node &>/dev/null; then
    print_info "Registering Context7 MCP server..."
    local _c7_err _c7_timeout_cmd="timeout"
    command -v timeout &>/dev/null || _c7_timeout_cmd="gtimeout"
    if command -v $_c7_timeout_cmd &>/dev/null; then
      _c7_err=$(echo "y" | $_c7_timeout_cmd 30 claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest 2>&1) || true
    else
      _c7_err=$(echo "y" | claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest 2>&1) || true
    fi
    # Verify by checking both config locations
    if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
       ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
      print_ok "Context7 MCP server registered"
    else
      print_warn "Context7 MCP registration failed: $_c7_err"
      print_warn "Register manually: claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest"
    fi
  else
    print_warn "Context7 MCP not found (recommended — up-to-date library documentation)"
    echo "  Requires Node.js. Install Node.js first, then: claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest"
  fi

  # --- Qdrant MCP (recommended for persistent semantic memory) ---
  # Check both config locations: ~/.claude/settings.json and ~/.claude.json (user scope)
  local _qd_found=false
  if command -v jq &>/dev/null; then
    if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
       ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
      _qd_found=true
    fi
  fi
  if [ "$_qd_found" = true ]; then
    print_ok "Qdrant MCP server configured"
  else
    print_info "Qdrant MCP not configured yet (will be offered at Phase 1 when Docker is available)"
    if [ "$interactive" = false ]; then
      echo "  Install Docker + uv, then: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
    elif command -v docker &>/dev/null; then
      # Verify the Docker daemon is actually running (not just the binary)
      local docker_daemon_running=false
      for _try in 1 2 3; do
        if docker info &>/dev/null; then
          docker_daemon_running=true
          break
        fi
        if [ "$_try" -lt 3 ]; then
          print_info "Waiting for Docker daemon to start (attempt $_try/3)..."
          sleep 2
        fi
      done

      if [ "$docker_daemon_running" = false ]; then
        print_warn "Docker is installed but the daemon is not running. Start Docker and re-run init, or run manually:"
        echo "  1. Start Qdrant: docker run -d -p 6333:6333 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest"
        echo "  2. Register MCP: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
      else
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
      fi
    else
      echo "  Requires Docker (for Qdrant server) and Python/uv (for MCP client)"
      echo "  1. Install Docker: https://docs.docker.com/get-docker/"
      echo "  2. Start Qdrant: docker run -d -p 6333:6333 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest"
      echo "  3. Register MCP: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
    fi
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

  echo ""
  echo -e "  ${BOLD}Project Tracks:${NC}"
  echo "    Light    — Internal tools, prototypes, POCs. <10 users. Minimal governance."
  echo "    Standard — External users, moderate complexity. Market audit, user testing."
  echo "    Full     — Enterprise buyers, sensitive data. Pen testing, legal review mandatory."
  echo ""
  TRACK=$(prompt_choice "Project track:" "light" "standard" "full")

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
    read -rp "$(echo -e "  ${BOLD}Continue with Full track? [y/N]${NC}: ")" confirm_full
    if [[ ! "$confirm_full" =~ ^[Yy] ]]; then
      TRACK=$(prompt_choice "Project track:" "light" "standard" "full")
    fi
  fi

  # For organizational deployments, ask about governance mode (POC vs production)
  POC_MODE=""
  if [ "$DEPLOYMENT" = "organizational" ]; then
    echo ""
    echo -e "  ${BOLD}Governance Mode:${NC}"
    echo "    Production Build — All governance approvals required before starting."
    echo "    Sponsored POC    — Organization-approved pilot. Technical approvals now,"
    echo "                       non-technical (insurance, ITSM, etc.) deferred."
    echo "    Private POC      — Personal exploration. All governance deferred."
    echo ""
    echo -e "  ${BOLD}POC constraints:${NC} No production deployment, no real user data, no external"
    echo "  users. All technical work is production-grade and carries forward unchanged."
    echo "  Phases 0-3 run identically. Phase 4 (production release) is blocked until upgrade."
    echo ""
    local gov_mode
    gov_mode=$(prompt_choice "Governance mode:" \
      "Private POC" \
      "Sponsored POC" \
      "Production Build")
    case "$gov_mode" in
      "Production"*) POC_MODE="" ;;
      "Sponsored"*)  POC_MODE="sponsored_poc" ;;
      "Private"*)    POC_MODE="private_poc" ;;
    esac

    # Validate track against governance mode
    # Sponsored POC and Production Build require Standard or Full track
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
      print_ok "Track upgraded to $TRACK"
    fi

    if [ -n "$POC_MODE" ]; then
      echo ""
      print_warn "POC MODE: ${POC_MODE//_/ }"
      print_warn "Phase 4 (production release) is blocked until you upgrade."
      print_warn "Upgrade later: bash scripts/upgrade-project.sh --to-production"
    fi
  fi

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

  read -rp "$(echo -e "${BOLD}Continue? [Y/n]${NC}: ")" confirm
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

  # Re-check items the resolver misclassifies. Build a separate
  # "configure_during_creation" list for things that exist but need per-project wiring.
  local configure_items="[]"

  if command -v jq &>/dev/null; then

    # Qdrant MCP: resolver always marks manual (auto_installable: false).
    if echo "$resolver_output" | jq -e '.manual_install[] | select(.name == "Qdrant MCP")' >/dev/null 2>&1; then
      local _qd_mcp_registered=false
      if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
         ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
        _qd_mcp_registered=true
      fi

      if [ "$_qd_mcp_registered" = true ]; then
        # Fully configured — move to already_installed
        resolver_output=$(echo "$resolver_output" | jq '
          .already_installed += [{ name: "Qdrant MCP", version: "configured", category: "mcp_server" }] |
          .manual_install |= map(select(.name != "Qdrant MCP"))
        ')
      elif command -v docker &>/dev/null && docker info &>/dev/null; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
          # Container running, just needs MCP registration → configure during creation
          resolver_output=$(echo "$resolver_output" | jq '
            .already_installed += [{ name: "Qdrant", version: "container running", category: "mcp_server" }] |
            .manual_install |= map(select(.name != "Qdrant MCP"))
          ')
          configure_items=$(echo "$configure_items" | jq '. += ["Qdrant MCP registration + project collection"]')
        else
          # Docker running but no container — move to auto_install
          resolver_output=$(echo "$resolver_output" | jq '
            .auto_install += [{ name: "Qdrant MCP", category: "mcp_server", install_cmd: "echo auto" }] |
            .manual_install |= map(select(.name != "Qdrant MCP"))
          ')
        fi
      fi
    fi

    # Claude Dev Framework: resolver marks manual but init.sh handles it.
    if echo "$resolver_output" | jq -e '.manual_install[] | select(.name == "Claude Dev Framework")' >/dev/null 2>&1; then
      if [ -d "$HOME/.claude-dev-framework/.git" ] && [ -f "$HOME/.claude-dev-framework/scripts/init.sh" ]; then
        # Global clone exists — show as installed, hooks configured during creation
        resolver_output=$(echo "$resolver_output" | jq '
          .already_installed += [{ name: "Claude Dev Framework", version: "installed", category: "dev_framework" }] |
          .manual_install |= map(select(.name != "Claude Dev Framework"))
        ')
        configure_items=$(echo "$configure_items" | jq '. += ["Claude Dev Framework hooks + rules"]')
      else
        # Will be cloned — move to auto_install
        resolver_output=$(echo "$resolver_output" | jq '
          .auto_install += [{ name: "Claude Dev Framework", category: "dev_framework", install_cmd: "echo auto" }] |
          .manual_install |= map(select(.name != "Claude Dev Framework"))
        ')
        configure_items=$(echo "$configure_items" | jq '. += ["Claude Dev Framework hooks + rules"]')
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

  # Confirm
  read -rp "$(echo -e "${BOLD}Proceed with this plan? [Y/n]${NC}: ")" response
  if [[ "$response" =~ ^[Nn] ]]; then
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

      # Claude Dev Framework: skip — handled in create_project()
      if [[ "$tool_name" == Claude\ Dev\ Framework* ]]; then
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
            if echo "y" | claude mcp add -s user \
              -e QDRANT_URL=http://localhost:6333 \
              -e COLLECTION_NAME=claude-memory \
              qdrant -- uvx --python 3.13 mcp-server-qdrant 2>/dev/null; then
              print_ok "Qdrant MCP registered"
            else
              print_warn "Failed to register Qdrant MCP. Register manually:"
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
      if command -v docker &>/dev/null && docker info &>/dev/null; then
        echo ""
        print_info "Docker is running — setting up Qdrant MCP..."

        # Start Qdrant container
        local qdrant_running=false
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
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
            if echo "y" | claude mcp add -s user \
              -e QDRANT_URL=http://localhost:6333 \
              -e COLLECTION_NAME=claude-memory \
              qdrant -- uvx --python 3.13 mcp-server-qdrant 2>/dev/null; then
              print_ok "Qdrant MCP registered"
              qdrant_handled=true
              # Remove Qdrant from manual list
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
  mkdir -p scripts/lib
  cp "$SCRIPT_DIR/scripts/lib/helpers.sh" scripts/lib/
  cp "$SCRIPT_DIR/scripts/validate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-updates.sh" scripts/
  cp "$SCRIPT_DIR/scripts/resume.sh" scripts/
  cp "$SCRIPT_DIR/scripts/intake-wizard.sh" scripts/
  cp "$SCRIPT_DIR/scripts/resolve-tools.sh" scripts/
  cp "$SCRIPT_DIR/scripts/upgrade-project.sh" scripts/
  cp "$SCRIPT_DIR/scripts/verify-install.sh" scripts/
  cp "$SCRIPT_DIR/scripts/test-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-versions.sh" scripts/
  chmod +x scripts/validate.sh scripts/check-phase-gate.sh scripts/check-updates.sh scripts/resume.sh scripts/intake-wizard.sh scripts/resolve-tools.sh scripts/upgrade-project.sh scripts/verify-install.sh scripts/test-gate.sh scripts/check-versions.sh

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

  # Generate Claude Code permissions (auto-accept safe operations)
  # This must be created BEFORE the Claude Dev Framework install, which merges
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
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git checkout *)",
      "Bash(git merge *)",
      "Bash(git rebase *)",
      "Bash(git stash *)",
      "Bash(git tag *)",
      "Bash(git fetch *)",
      "Bash(git pull)",
      "Bash(git remote *)",
      "Bash(git show *)",
      "Bash(git rev-parse *)",
      "Bash(ls *)",
      "Bash(pwd)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Bash(mv *)",
      "Bash(cat *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(find *)",
      "Bash(which *)",
      "Bash(echo *)",
      "Bash(make *)",
      "Bash(semgrep *)",
      "Bash(gitleaks *)",
      "Bash(snyk *)",
      "Bash(jq *)",
      "Bash(* --version)",
      "Bash(* --help)",
      "Bash(bash scripts/*)",
      "Bash(bash -n *)",
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

  # Install Claude Dev Framework
  # The framework uses a global clone at ~/.claude-dev-framework shared across
  # all projects. Its own init.sh handles per-project installation (hooks,
  # rules, manifest, settings.json).
  # MIT-licensed: https://github.com/kraulerson/claude-dev-framework
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"

  print_info "Installing Claude Dev Framework..."
  if command -v git &>/dev/null; then
    # Step 1: Check if framework is already installed with a valid manifest
    local framework_valid=false
    if [ -d "$FRAMEWORK_CLONE/.git" ] && [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
      framework_valid=true
      print_ok "Claude Dev Framework already installed at $FRAMEWORK_CLONE"
    fi

    # Step 2: If not installed, clone with retry
    if [ "$framework_valid" = false ]; then
      local clone_ok=false
      for _clone_try in 1 2; do
        print_info "Cloning Claude Dev Framework to $FRAMEWORK_CLONE (attempt $_clone_try/2)..."
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
        print_ok "Claude Dev Framework cloned successfully"
      else
        rm -rf "$FRAMEWORK_CLONE"
        print_warn "Could not clone Claude Dev Framework after 2 attempts (network issue?)."
        print_warn "The fallback pre-commit hook will still be installed."
        print_warn "Install manually: git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework"
        print_warn "Then from your project: bash ~/.claude-dev-framework/scripts/init.sh"
      fi
    fi

    # Step 3: Run the framework's own init from the project directory
    if [ "$framework_valid" = true ]; then
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

      # Verify the framework init produced expected output
      if [ -f ".claude/manifest.json" ]; then
        print_ok "Claude Dev Framework installed and configured"
      else
        print_warn "Claude Dev Framework init did not produce .claude/manifest.json"
        print_warn "Run manually: bash ~/.claude-dev-framework/scripts/init.sh"
      fi
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

  # Configure Qdrant MCP with per-project collection (isolates semantic memory)
  # If Qdrant container is running but MCP isn't registered yet, register it now.
  # Then write a project-local override using the project name as the collection.
  if command -v jq &>/dev/null; then
    local _qd_global=false
    if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
       ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
      _qd_global=true
    fi

    # If not registered but container is running, register now
    if [ "$_qd_global" = false ] && command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
      if command -v uvx &>/dev/null; then
        print_info "Registering Qdrant MCP server..."
        if echo "y" | claude mcp add -s user \
          -e QDRANT_URL=http://localhost:6333 \
          -e COLLECTION_NAME=claude-memory \
          qdrant -- uvx --python 3.13 mcp-server-qdrant 2>/dev/null; then
          print_ok "Qdrant MCP registered"
          _qd_global=true
        fi
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
  # independent of whether the Claude Dev Framework clone succeeded.
  # If the Claude Dev Framework is installed and activates its own hooks, those
  # will provide deeper coverage. This hook remains as the safety net.
  print_info "Installing pre-commit hook..."
  install_precommit_hook

  git add -A
  # Skip hooks for the initial commit — template files trigger false positives
  # in Semgrep/gitleaks. Hooks will enforce on all subsequent commits.
  git commit -q --no-verify -m "chore: initialize Solo Orchestrator project

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
    swift)                 src_ext="swift";         test_pattern="Tests?\\.swift$" ;;
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

  # Append the TDD ordering check only if we have a meaningful pattern
  # (Rust uses inline tests so TDD ordering check doesn't apply)
  if [ -n "$test_pattern" ] && [ -n "$src_ext" ]; then
    cat >> .git/hooks/pre-commit << TDDEOF

# --- TDD Ordering Check ---
# Warns when implementation files are staged without any test files in the same commit.
SRC_EXT_PATTERN="\\.(${src_ext})$"
TEST_PATTERN="${test_pattern}"

staged_impl=\$(git diff --cached --name-only --diff-filter=ACM \\
  | grep -E "\$SRC_EXT_PATTERN" \\
  | grep -vE "\$TEST_PATTERN" \\
  | grep -vE "(config|setup|migration|seed|fixture|generated|__mocks__|\.d\.)" \\
  || true)

staged_tests=\$(git diff --cached --name-only --diff-filter=ACM \\
  | grep -E "\$TEST_PATTERN" \\
  || true)

if [ -n "\$staged_impl" ] && [ -z "\$staged_tests" ]; then
  echo ""
  echo "[WARN] Implementation files staged without any test files:"
  echo "\$staged_impl" | head -10 | sed 's/^/  /'
  count=\$(echo "\$staged_impl" | wc -l | tr -d ' ')
  [ "\$count" -gt 10 ] && echo "  ... and \$((\$count - 10)) more"
  echo ""
  echo "  The Solo Orchestrator methodology requires test-first development."
  echo "  Consider committing tests before or alongside implementation."
  echo "  (This is a warning — commit is not blocked.)"
fi
TDDEOF
  fi

  # Append the schema migration check (active in Phase 2+ only)
  cat >> .git/hooks/pre-commit << 'SCHEMAEOF'

# --- Schema Migration Check ---
# Warns when schema files are edited directly instead of through migrations (Phase 2+).
PHASE_STATE=".claude/phase-state.json"
CURRENT_PHASE=0
if [ -f "$PHASE_STATE" ]; then
  CURRENT_PHASE=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' \
    "$PHASE_STATE" | grep -o '[0-9][0-9]*' || echo "0")
fi

if [ "$CURRENT_PHASE" -ge 2 ]; then
  SCHEMA_PATTERNS='(schema\.prisma|schema\.sql|schema\.rb|models\.py|\.schema\.ts|\.entity\.ts|schema\.graphql)$'
  staged_schema=$(git diff --cached --name-only --diff-filter=ACM \
    | grep -E "$SCHEMA_PATTERNS" \
    | grep -vE '(migrations?/|migrate/)' \
    || true)

  if [ -n "$staged_schema" ]; then
    echo ""
    echo "[WARN] Direct schema file changes detected (Phase $CURRENT_PHASE):"
    echo "$staged_schema" | sed 's/^/  /'
    echo ""
    echo "  The Solo Orchestrator methodology requires data model changes"
    echo "  through versioned migrations, not direct schema edits."
    echo "  If this is intentional (e.g., Prisma schema before migration gen),"
    echo "  this warning can be ignored."
    echo "  (This is a warning — commit is not blocked.)"
  fi
fi
SCHEMAEOF

  # Append exit
  cat >> .git/hooks/pre-commit << 'EXITEOF'

exit $FAILED
EXITEOF

  chmod +x .git/hooks/pre-commit
  print_ok "Pre-commit hook installed (gitleaks + Semgrep + TDD ordering + schema migration checks)"
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
    kotlin|java)           ci_template="jvm.yml" ;;
    go)                    ci_template="go.yml" ;;
    dart)                  ci_template="dart.yml" ;;
    swift)                 ci_template="swift.yml" ;;
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
      echo "     See docs/framework/governance-framework.md for details."
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
  echo "     │ 3. docs/framework/builders-guide.md (the phase-gate method)     │"
  echo "     │ 4. docs/platform-modules/ (platform-specific guidance)          │"
  echo "     │ 5. .claude/phase-state.json (current phase)                     │"
  echo "     │                                                                 │"
  echo "     │ After reading, summarize: the project goal, your constraints,   │"
  echo "     │ the current phase, and what tools/MCP servers are available to   │"
  echo "     │ you. Then begin Phase 0. Ask me only for clarifying questions.  │"
  echo "     └─────────────────────────────────────────────────────────────────┘"
  echo ""

  # Show dependency status and remaining optional enhancements
  # Collect status for each dependency
  local _installed=() _failed=() _later=()

  # Claude Dev Framework
  if [ -f "$PROJECT_DIR/.claude/manifest.json" ]; then
    _installed+=("Claude Dev Framework (Git hook guardrails)")
  elif [ -d "$HOME/.claude-dev-framework/.git" ]; then
    _failed+=("Claude Dev Framework — hooks not configured. Run: bash ~/.claude-dev-framework/scripts/init.sh")
  else
    _failed+=("Claude Dev Framework — clone failed. Run: git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework && bash ~/.claude-dev-framework/scripts/init.sh")
  fi

  # Superpowers plugin
  if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
    local _sp
    _sp=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
    if [ "$_sp" = "true" ]; then
      _installed+=("Superpowers plugin (agentic skills for Phase 2)")
    else
      _failed+=("Superpowers plugin — run: claude → /plugins → search 'superpowers' → install")
    fi
  fi

  # Context7 MCP
  local _c7=false
  if command -v jq &>/dev/null; then
    if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
       ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
      _c7=true
    fi
  fi
  if [ "$_c7" = true ]; then
    _installed+=("Context7 MCP (up-to-date library documentation)")
  else
    _failed+=("Context7 MCP — run: claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest")
  fi

  # Qdrant MCP
  local _qd_mcp=false _qd_container=false
  if command -v jq &>/dev/null; then
    if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
       ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
      _qd_mcp=true
    fi
  fi
  if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
    _qd_container=true
  fi
  if [ "$_qd_mcp" = true ]; then
    _installed+=("Qdrant MCP (persistent semantic memory — collection: $PROJECT_NAME)")
  elif [ "$_qd_container" = true ]; then
    _later+=("Qdrant MCP — container running, MCP will be configured on first Claude Code session")
  else
    _later+=("Qdrant MCP — will be offered at Phase 1 when Docker is available")
  fi

  # Per-project Qdrant collection override
  if [ -f "$PROJECT_DIR/.claude/settings.local.json" ]; then
    _installed+=("Qdrant project collection ($PROJECT_NAME)")
  elif [ "$_qd_mcp" = true ]; then
    _later+=("Qdrant project collection — will be configured on next init or manually")
  fi

  # Display sections
  echo "  INSTALLED DEPENDENCIES:"
  if [ ${#_installed[@]} -gt 0 ]; then
    for item in "${_installed[@]}"; do
      echo "     ✓ $item"
    done
  fi

  if [ ${#_failed[@]} -gt 0 ]; then
    echo ""
    echo "  NEEDS ATTENTION:"
    for item in "${_failed[@]}"; do
      echo "     ✗ $item"
    done
  fi

  if [ ${#_later[@]} -gt 0 ]; then
    echo ""
    echo "  WILL BE CONFIGURED LATER:"
    for item in "${_later[@]}"; do
      echo "     ○ $item"
    done
  fi
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
  echo "     docs/framework/user-guide.md          — Start here: step-by-step walkthrough"
  echo "     docs/framework/builders-guide.md      — The complete methodology"
  echo "     docs/framework/governance-framework.md — Enterprise governance"
  echo "     docs/framework/cli-setup-addendum.md   — Claude Code configuration"
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
        echo ""
        echo "  Init logs are saved to <project>/.solo-orchestrator/init-TIMESTAMP.log"
        exit 0
        ;;
      *)
        echo "Unknown option: $arg"
        echo "Usage: ./init.sh [--dry-run] [--help]"
        exit 1
        ;;
    esac
  done

  print_header "$VERSION"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}${BOLD}DRY RUN MODE — no changes will be made${NC}"
    echo ""
  fi

  # Initialize logging to temp location (moved to project dir after creation)
  INIT_LOG_DIR=$(mktemp -d)
  init_log "$INIT_LOG_DIR"
  log_section "Prerequisites"

  check_prerequisites
  collect_project_info

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
    create_project

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
    print_next_steps
  fi

  finalize_log
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

# NOTE: This script requires bash. On Windows, run it inside WSL (Windows
# Subsystem for Linux) or Git Bash. Native PowerShell is not supported.

# Solo Orchestrator — Project Initialization Script
# https://github.com/kraulerson/solo-orchestrator
#
# Usage: ./init.sh
# Creates a new Solo Orchestrator project with all framework documents,
# templates, and tooling configuration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"

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
  read -rp "$(echo -e "${BOLD}Select [1-${#options[@]}]${NC}: ")" choice
  echo "${options[$((choice-1))]}"
}

# ================================================================
# PHASE 1: Prerequisites Check
# ================================================================
check_prerequisites() {
  print_step "Checking prerequisites..."
  local missing=()

  # Git (always required)
  if command -v git &>/dev/null; then
    print_ok "Git $(git --version | awk '{print $3}')"
  else
    print_fail "Git not found"
    missing+=("git")
  fi

  # Node.js — required for JS/TS projects, recommended for others (used by some tooling)
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
    # Node.js is only hard-required for JS/TS projects
    # For other languages it's used by some optional tooling (Snyk, license-checker)
    print_warn "Node.js not found"
  fi

  # Docker (optional but recommended)
  if command -v docker &>/dev/null; then
    print_ok "Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
  else
    print_warn "Docker not found (optional — needed for OWASP ZAP DAST scanning)"
  fi

  # GPG (optional)
  if command -v gpg &>/dev/null; then
    print_ok "GPG available (commit signing)"
  else
    print_warn "GPG not found (optional — used for commit signing)"
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    print_fail "Missing required prerequisites: ${missing[*]}"
    echo "  Install them before continuing."
    echo "  Git: https://git-scm.com/downloads"
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

  PLATFORM=$(prompt_choice "Platform type:" "web" "desktop" "mobile" "cli" "other")

  TRACK=$(prompt_choice "Project track:" "light" "standard" "full")

  DEPLOYMENT=$(prompt_choice "Personal or organizational?" "personal" "organizational")

  LANGUAGE=$(prompt_choice "Primary language:" "typescript" "javascript" "python" "rust" "csharp" "kotlin" "java" "go" "dart" "other")

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
# PHASE 3: Install Security Tooling
# ================================================================
install_tools() {
  print_step "Checking/installing security tooling..."
  local os_type
  os_type="$(uname -s)"

  # Semgrep
  if command -v semgrep &>/dev/null; then
    print_ok "Semgrep $(semgrep --version 2>/dev/null | head -1)"
  else
    print_info "Installing Semgrep..."
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      brew install semgrep
    else
      pip install semgrep 2>/dev/null || pip3 install semgrep 2>/dev/null || print_warn "Could not install Semgrep. Install manually: pip install semgrep"
    fi
  fi

  # gitleaks
  if command -v gitleaks &>/dev/null; then
    print_ok "gitleaks $(gitleaks version 2>/dev/null)"
  else
    print_info "Installing gitleaks..."
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      brew install gitleaks
    else
      print_warn "Install gitleaks manually: https://github.com/gitleaks/gitleaks/releases"
    fi
  fi

  # Snyk
  if command -v snyk &>/dev/null; then
    print_ok "Snyk CLI $(snyk --version 2>/dev/null)"
  else
    print_info "Installing Snyk CLI..."
    npm install -g snyk 2>/dev/null || print_warn "Could not install Snyk. Install manually: npm install -g snyk"
  fi

  # Claude Code
  if command -v claude &>/dev/null; then
    print_ok "Claude Code $(claude --version 2>/dev/null)"
  else
    print_info "Installing Claude Code..."
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      brew install claude-code 2>/dev/null || npm install -g @anthropic-ai/claude-code 2>/dev/null || print_warn "Could not install Claude Code. See: https://docs.anthropic.com/en/docs/claude-code"
    elif [ "$os_type" = "Linux" ]; then
      npm install -g @anthropic-ai/claude-code 2>/dev/null || print_warn "Could not install Claude Code. See: https://docs.anthropic.com/en/docs/claude-code"
    else
      print_warn "Install Claude Code manually. See: https://docs.anthropic.com/en/docs/claude-code"
    fi
  fi

  # Lighthouse (web only)
  if [ "$PLATFORM" = "web" ]; then
    if command -v lighthouse &>/dev/null; then
      print_ok "Lighthouse CLI"
    else
      print_info "Installing Lighthouse..."
      npm install -g lighthouse 2>/dev/null || print_warn "Could not install Lighthouse."
    fi
  fi

  # OWASP ZAP Docker image (web only, if Docker available)
  if [ "$PLATFORM" = "web" ] && command -v docker &>/dev/null; then
    if docker image inspect zaproxy/zap-stable &>/dev/null 2>&1; then
      print_ok "OWASP ZAP Docker image"
    else
      print_info "Pulling OWASP ZAP image..."
      docker pull zaproxy/zap-stable 2>/dev/null || print_warn "Could not pull ZAP image."
    fi
  fi

  echo ""
  print_ok "Tool installation complete."
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

  # Copy the correct platform module
  case "$PLATFORM" in
    web)     cp "$SCRIPT_DIR/docs/platform-modules/web.md" docs/platform-modules/ ;;
    desktop) cp "$SCRIPT_DIR/docs/platform-modules/desktop.md" docs/platform-modules/ ;;
    mobile)  cp "$SCRIPT_DIR/docs/platform-modules/mobile.md" docs/platform-modules/ ;;
    *)       print_info "No platform module for '$PLATFORM'. The Builder's Guide works standalone." ;;
  esac

  # Clone Claude Dev Framework
  print_info "Installing Claude Dev Framework..."
  if command -v git &>/dev/null; then
    git clone -q https://github.com/kraulerson/claude-dev-framework.git .claude/framework 2>/dev/null
    if [ -d ".claude/framework" ]; then
      # Capture the commit SHA before deleting .git for version pinning
      local framework_sha
      framework_sha=$(git -C .claude/framework rev-parse HEAD 2>/dev/null || echo "unknown")
      echo "$framework_sha" > .claude/framework-version.txt
      # Remove nested .git so the framework is committed as project files (self-contained)
      rm -rf .claude/framework/.git
      # Select the appropriate profile based on platform
      local profile="_base.yml"
      case "$PLATFORM" in
        web)     [ -f ".claude/framework/profiles/web-api.yml" ] && profile="web-api.yml" ;;
        desktop) [ -f ".claude/framework/profiles/cli-tool.yml" ] && profile="cli-tool.yml" ;;
        mobile)  [ -f ".claude/framework/profiles/mobile-app.yml" ] && profile="mobile-app.yml" ;;
        cli)     [ -f ".claude/framework/profiles/cli-tool.yml" ] && profile="cli-tool.yml" ;;
      esac

      # Create framework config pointing to the selected profile
      mkdir -p .claude
      cat > .claude/framework-config.yml << FWEOF
# Claude Dev Framework — Profile Configuration
# Auto-generated by Solo Orchestrator init.sh
#
# This file tells the framework which profile to use for this project.
# Profiles inherit from _base.yml and add platform-specific rules.
# See .claude/framework/profiles/ for available profiles.
#
# The framework is pinned to the commit in .claude/framework-version.txt.
# To update: re-clone from https://github.com/kraulerson/claude-dev-framework.git
# into .claude/framework/, capture the new commit SHA, and replace the files.
#
# To change: update the active_profile value and run the framework's
# sync script, or manually copy the profile's hooks into .git/hooks/

active_profile: $profile
framework_path: .claude/framework
FWEOF

      print_ok "Claude Dev Framework installed (profile: $profile)"
      print_info "Hooks will activate after first commit. See .claude/framework/README.md for details."
    else
      print_warn "Could not clone Claude Dev Framework. Install manually: git clone https://github.com/kraulerson/claude-dev-framework.git .claude/framework"
    fi
  fi

  # Copy intake template
  cp "$SCRIPT_DIR/templates/project-intake.md" PROJECT_INTAKE.md

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

  # Initialize git
  print_info "Initializing Git repository..."
  git init -q
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
- Claude Dev Framework: \`.claude/framework/\` (Git hook guardrails — profile: see \`.claude/framework-config.yml\`)

## Operating Instructions
You are the AI coding agent for this Solo Orchestrator project. The human is the Orchestrator — they define intent, constraints, and validation. You provide syntax, scaffolding, and pattern execution.

### Phase Awareness
- Read the Project Intake (\`PROJECT_INTAKE.md\`) for all project constraints and decisions.
- Follow the Builder's Guide phases in sequence (Phase 0 → 1 → 2 → 3 → 4).
- Reference the Platform Module for platform-specific architecture, tooling, testing, and distribution.
- Every phase produces artifacts that gate entry into the next phase. Do not skip ahead.

### Governance Tracking
- The Approval Log (\`APPROVAL_LOG.md\`) records all phase gate approvals.
- At each phase gate transition (Phase 0→1, Phase 1→2, Phase 3→4), prompt the Orchestrator: "This phase gate requires approval. Please update APPROVAL_LOG.md with the approver name, date, method, and reference before proceeding to the next phase."
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
# PHASE 5: Health Check
# ================================================================
health_check() {
  print_step "Running health check..."
  local warnings=0

  cd "$PROJECT_DIR"

  # Check files exist
  [ -f "CLAUDE.md" ] && print_ok "CLAUDE.md" || { print_fail "CLAUDE.md missing"; ((warnings++)); }
  [ -f "PROJECT_INTAKE.md" ] && print_ok "PROJECT_INTAKE.md" || { print_fail "PROJECT_INTAKE.md missing"; ((warnings++)); }
  [ -f "APPROVAL_LOG.md" ] && print_ok "APPROVAL_LOG.md" || { print_fail "APPROVAL_LOG.md missing"; ((warnings++)); }
  [ -f "docs/framework/builders-guide.md" ] && print_ok "Builder's Guide" || { print_fail "Builder's Guide missing"; ((warnings++)); }
  [ -f ".gitignore" ] && print_ok ".gitignore" || { print_fail ".gitignore missing"; ((warnings++)); }
  [ -f ".github/workflows/ci.yml" ] && print_ok "CI pipeline" || { print_fail "CI pipeline missing"; ((warnings++)); }
  if [ -f "$SCRIPT_DIR/templates/pipelines/release/$PLATFORM.yml" ]; then
    [ -f ".github/workflows/release.yml" ] && print_ok "Release pipeline" || { print_fail "Release pipeline missing"; ((warnings++)); }
  fi
  [ -d ".git" ] && print_ok "Git initialized" || { print_fail "Git not initialized"; ((warnings++)); }
  [ -d ".claude/framework" ] && print_ok "Claude Dev Framework" || { print_warn "Claude Dev Framework not installed"; ((warnings++)); }

  # Check tools
  command -v claude &>/dev/null && print_ok "Claude Code accessible" || { print_warn "Claude Code not found"; ((warnings++)); }
  command -v semgrep &>/dev/null && print_ok "Semgrep accessible" || { print_warn "Semgrep not found"; ((warnings++)); }
  command -v gitleaks &>/dev/null && print_ok "gitleaks accessible" || { print_warn "gitleaks not found"; ((warnings++)); }
  command -v snyk &>/dev/null && print_ok "Snyk accessible" || { print_warn "Snyk not found"; ((warnings++)); }

  # Check language runtime
  case "$LANGUAGE" in
    typescript|javascript)
      command -v node &>/dev/null && print_ok "Node.js runtime" || { print_fail "Node.js not found (required for $LANGUAGE)"; ((warnings++)); } ;;
    python)
      (command -v python3 &>/dev/null || command -v python &>/dev/null) && print_ok "Python runtime" || { print_fail "Python not found (required for $LANGUAGE)"; ((warnings++)); } ;;
    rust)
      command -v cargo &>/dev/null && print_ok "Rust/Cargo runtime" || { print_fail "Rust (cargo) not found (required for $LANGUAGE). Install: https://rustup.rs/"; ((warnings++)); } ;;
    csharp)
      command -v dotnet &>/dev/null && print_ok ".NET SDK" || { print_fail ".NET SDK not found (required for $LANGUAGE). Install: https://dotnet.microsoft.com/download"; ((warnings++)); } ;;
    kotlin|java)
      command -v java &>/dev/null && print_ok "Java runtime" || { print_fail "Java not found (required for $LANGUAGE). Install: https://adoptium.net/"; ((warnings++)); }
      command -v gradle &>/dev/null && print_ok "Gradle" || { print_warn "Gradle not found (use ./gradlew wrapper or install: https://gradle.org/)"; ((warnings++)); } ;;
    go)
      command -v go &>/dev/null && print_ok "Go runtime" || { print_fail "Go not found (required for $LANGUAGE). Install: https://go.dev/dl/"; ((warnings++)); } ;;
    dart)
      command -v flutter &>/dev/null && print_ok "Flutter SDK" || { print_fail "Flutter not found (required for $LANGUAGE). Install: https://docs.flutter.dev/get-started/install"; ((warnings++)); } ;;
  esac

  echo ""
  if [ $warnings -eq 0 ]; then
    print_ok "All health checks passed."
  else
    print_warn "$warnings warnings. Review above and resolve before starting."
  fi

  # Check specifically for security tools and print a prominent warning
  local security_missing=()
  command -v semgrep &>/dev/null || security_missing+=("semgrep")
  command -v gitleaks &>/dev/null || security_missing+=("gitleaks")
  command -v snyk &>/dev/null || security_missing+=("snyk")

  if [ ${#security_missing[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  REQUIRED SECURITY TOOLS MISSING: ${security_missing[*]}${NC}"
    echo -e "${YELLOW}║                                                                  ║${NC}"
    echo -e "${YELLOW}║  The Solo Orchestrator methodology requires these tools for       ║${NC}"
    echo -e "${YELLOW}║  Phase 2 (security audits) and Phase 3 (validation). Install      ║${NC}"
    echo -e "${YELLOW}║  them before starting development. The framework's security       ║${NC}"
    echo -e "${YELLOW}║  scanning will not function without them.                         ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
  fi
}

# ================================================================
# PHASE 6: Print Next Steps
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
  echo "     Open PROJECT_INTAKE.md and complete every section."
  echo "     Mark N/A where fields genuinely don't apply."
  echo "     Every blank field is a round-trip with the agent."
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

  echo "  OPTIONAL ENHANCEMENTS (see docs/framework/cli-setup-addendum.md):"
  echo "     - Superpowers plugin (agentic skills for Phase 2)"
  echo "     - Claude Dev Framework (Git hook guardrails)"
  echo "     - Context7 MCP (up-to-date library documentation)"
  echo "     - Qdrant MCP (persistent semantic memory across sessions)"
  echo ""
  if [ -f "$PROJECT_DIR/.github/workflows/release.yml" ]; then
    echo "  RELEASE PIPELINE (review before first release):"
    echo "     .github/workflows/release.yml"
    echo "     - Review and configure TODOs (code signing, deployment, secrets)"
    echo "     - The release pipeline runs on version tags: git tag v1.0.0 && git push --tags"
    echo ""
  fi
  echo "  DOCUMENTATION:"
  echo "     docs/framework/user-guide.md          — Start here: step-by-step walkthrough"
  echo "     docs/framework/builders-guide.md      — The complete methodology"
  echo "     docs/framework/governance-framework.md — Enterprise governance"
  echo "     docs/framework/cli-setup-addendum.md   — Claude Code configuration"
  echo "     docs/platform-modules/                — Platform-specific guidance"
  echo ""
}

# ================================================================
# MAIN
# ================================================================
main() {
  print_header
  check_prerequisites
  collect_project_info
  install_tools
  create_project
  health_check
  print_next_steps
}

main "$@"

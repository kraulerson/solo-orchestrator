# Verify-Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a standalone verification + remediation script that detects installation issues, offers batch auto-fix, and integrates with init.sh and upgrade-project.sh.

**Architecture:** Categorized check functions register results into three arrays (passed, fixable, manual). After detection, the script reports results and offers batch remediation. Paired fix functions handle each remediable issue. The script reads project context from `.claude/tool-preferences.json` and orchestrator source path from `.claude/orchestrator-source.json`.

**Tech Stack:** Bash, jq

**Spec:** `docs/superpowers/specs/2026-04-03-verify-install-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|---|---|
| `scripts/verify-install.sh` | Standalone verification + remediation script |

### Modified Files
| File | Change |
|---|---|
| `init.sh` | Write orchestrator-source.json, replace health_check() with verify-install.sh, add to copy list |
| `scripts/upgrade-project.sh` | Add verify-install.sh call after upgrade completes |

---

### Task 1: Create verify-install.sh — Framework and Registration System

**Files:**
- Create: `scripts/verify-install.sh`

- [ ] **Step 1: Create the script with argument parsing, color helpers, and registration system**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Installation Verification & Remediation
# Detects installation issues, categorizes as auto-fixable or manual,
# and offers batch remediation.
#
# Usage:
#   scripts/verify-install.sh              # Interactive: verify + offer fixes
#   scripts/verify-install.sh --check-only # Verify only, no remediation (CI)
#   scripts/verify-install.sh --auto-fix   # Verify + fix without prompting
#   scripts/verify-install.sh --help

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

print_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# --- Parse arguments ---
MODE="interactive"  # interactive | check-only | auto-fix
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) MODE="check-only"; shift ;;
    --auto-fix)   MODE="auto-fix";   shift ;;
    --help|-h)
      echo "Usage: scripts/verify-install.sh [--check-only] [--auto-fix] [--help]"
      echo ""
      echo "Verifies Solo Orchestrator installation and offers remediation."
      echo ""
      echo "Modes:"
      echo "  (default)      Interactive — verify, report, offer batch fix"
      echo "  --check-only   Verify only, no remediation (for CI/scripted checks)"
      echo "  --auto-fix     Verify + fix without prompting (for init.sh/upgrade calls)"
      echo "  --help         Show this help"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Registration arrays ---
# Each entry is "description||fix_function_or_instructions"
PASSED=()
FIXABLE=()
MANUAL=()

register_pass() {
  PASSED+=("$1")
  print_ok "$1"
}

register_fixable() {
  local description="$1"
  local fix_func="$2"
  FIXABLE+=("${description}||${fix_func}")
  print_fail "$description (auto-fixable)"
}

register_manual() {
  local description="$1"
  local instructions="$2"
  MANUAL+=("${description}||${instructions}")
  print_warn "$description (manual)"
}

# --- Load project context ---
PLATFORM=""
LANGUAGE=""
TRACK=""
DEPLOYMENT=""
PROJECT_NAME=""
SOURCE_DIR=""

load_context() {
  # From tool-preferences.json
  if [ -f ".claude/tool-preferences.json" ] && command -v jq &>/dev/null; then
    PLATFORM=$(jq -r '.context.platform // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
    LANGUAGE=$(jq -r '.context.language // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
    TRACK=$(jq -r '.context.track // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
  fi

  # From phase-state.json
  if [ -f ".claude/phase-state.json" ] && command -v jq &>/dev/null; then
    PROJECT_NAME=$(jq -r '.project // empty' ".claude/phase-state.json" 2>/dev/null || echo "")
  fi

  # Deployment from CLAUDE.md or intake-progress
  if [ -f ".claude/intake-progress.json" ] && command -v jq &>/dev/null; then
    DEPLOYMENT=$(jq -r '.deployment // empty' ".claude/intake-progress.json" 2>/dev/null || echo "")
  fi
  if [ -z "$DEPLOYMENT" ] && [ -f "CLAUDE.md" ]; then
    if grep -q "organizational" "CLAUDE.md" 2>/dev/null; then
      DEPLOYMENT="organizational"
    else
      DEPLOYMENT="personal"
    fi
  fi

  # Fallback: grep CLAUDE.md for missing context
  if [ -z "$PLATFORM" ] && [ -f "CLAUDE.md" ]; then
    PLATFORM=$(grep -oP '(?<=\*\*Platform:\*\* ).*' "CLAUDE.md" 2>/dev/null | head -1 || echo "")
  fi
  if [ -z "$LANGUAGE" ] && [ -f "CLAUDE.md" ]; then
    LANGUAGE=$(grep -oP '(?<=\*\*Primary Language:\*\* ).*' "CLAUDE.md" 2>/dev/null | head -1 || echo "")
  fi
  if [ -z "$TRACK" ] && [ -f "CLAUDE.md" ]; then
    TRACK=$(grep -oP '(?<=\*\*Track:\*\* ).*' "CLAUDE.md" 2>/dev/null | head -1 || echo "")
  fi

  # Orchestrator source directory
  if [ -f ".claude/orchestrator-source.json" ] && command -v jq &>/dev/null; then
    SOURCE_DIR=$(jq -r '.source_dir // empty' ".claude/orchestrator-source.json" 2>/dev/null || echo "")
  fi
  if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
    # Try conventional location
    if [ -d "$HOME/.solo-orchestrator" ]; then
      SOURCE_DIR="$HOME/.solo-orchestrator"
    elif [ -d "$HOME/solo-orchestrator" ]; then
      SOURCE_DIR="$HOME/solo-orchestrator"
    fi
  fi
}

has_source() {
  [ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ]
}

has_context() {
  [ -n "$PLATFORM" ] && [ -n "$LANGUAGE" ] && [ -n "$TRACK" ]
}
```

- [ ] **Step 2: Make executable and validate syntax**

Run: `chmod +x scripts/verify-install.sh && bash -n scripts/verify-install.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-install.sh
git commit -m "feat(verify): add verify-install.sh framework and registration system

Argument parsing (--check-only, --auto-fix, --help), color helpers,
three-array registration (passed/fixable/manual), project context
loader with multi-source fallbacks."
```

---

### Task 2: Add Check Functions — Project Structure

**Files:**
- Modify: `scripts/verify-install.sh`

- [ ] **Step 1: Add check_project_structure function**

Append before the `load_context` call (at the end of the file):

```bash
# ================================================================
# CHECK FUNCTIONS
# ================================================================

check_project_structure() {
  print_step "Checking project structure..."

  # Critical files
  [ -f "CLAUDE.md" ] && register_pass "CLAUDE.md exists" || register_fixable "CLAUDE.md missing" "fix_claude_md"
  [ -f "PROJECT_INTAKE.md" ] && register_pass "PROJECT_INTAKE.md exists" || register_fixable "PROJECT_INTAKE.md missing" "fix_intake_md"
  [ -f "APPROVAL_LOG.md" ] && register_pass "APPROVAL_LOG.md exists" || register_fixable "APPROVAL_LOG.md missing" "fix_approval_log"
  [ -f ".gitignore" ] && register_pass ".gitignore exists" || register_fixable ".gitignore missing" "fix_gitignore"
  [ -f ".claude/phase-state.json" ] && register_pass "phase-state.json exists" || register_fixable "phase-state.json missing" "fix_phase_state"
  [ -f ".claude/tool-preferences.json" ] && register_pass "tool-preferences.json exists" || register_fixable "tool-preferences.json missing" "fix_tool_prefs"
  [ -f ".claude/orchestrator-source.json" ] && register_pass "orchestrator-source.json exists" || register_fixable "orchestrator-source.json missing" "fix_orchestrator_source"

  # Framework documents
  local framework_docs=(
    "docs/framework/builders-guide.md"
    "docs/framework/governance-framework.md"
    "docs/framework/executive-review.md"
    "docs/framework/cli-setup-addendum.md"
    "docs/framework/user-guide.md"
    "docs/framework/security-scan-guide.md"
  )
  for doc in "${framework_docs[@]}"; do
    if [ -f "$doc" ]; then
      register_pass "$(basename "$doc") exists"
    elif has_source; then
      local src_doc="$SOURCE_DIR/docs/$(basename "$doc")"
      [ -f "$src_doc" ] && register_fixable "$(basename "$doc") missing" "fix_framework_doc_$(basename "$doc" .md)" || register_manual "$(basename "$doc") missing" "Re-copy from orchestrator source"
    else
      register_manual "$(basename "$doc") missing" "Re-copy from orchestrator source directory"
    fi
  done

  # Platform module
  if [ -n "$PLATFORM" ] && [ "$PLATFORM" != "other" ]; then
    if [ -f "docs/platform-modules/${PLATFORM}.md" ]; then
      register_pass "Platform module (${PLATFORM}.md) exists"
    elif has_source && [ -f "$SOURCE_DIR/docs/platform-modules/${PLATFORM}.md" ]; then
      register_fixable "Platform module (${PLATFORM}.md) missing" "fix_platform_module"
    else
      register_manual "Platform module (${PLATFORM}.md) missing" "Copy from orchestrator: docs/platform-modules/${PLATFORM}.md"
    fi
  fi

  # Pipelines
  [ -f ".github/workflows/ci.yml" ] && register_pass "CI pipeline exists" || {
    if has_source && has_context; then
      register_fixable "CI pipeline missing" "fix_ci_pipeline"
    else
      register_manual "CI pipeline missing" "Copy from orchestrator templates/pipelines/ci/"
    fi
  }

  if [ -n "$PLATFORM" ] && [ -f ".github/workflows/release.yml" ] 2>/dev/null || {
    if has_source && [ -f "$SOURCE_DIR/templates/pipelines/release/${PLATFORM}.yml" ]; then
      [ -f ".github/workflows/release.yml" ] && register_pass "Release pipeline exists" || register_fixable "Release pipeline missing" "fix_release_pipeline"
    fi
  }; then
    [ -f ".github/workflows/release.yml" ] && register_pass "Release pipeline exists" 2>/dev/null || true
  fi

  # Intake suggestions
  if [ -d "templates/intake-suggestions" ] && ls templates/intake-suggestions/*.json &>/dev/null 2>&1; then
    register_pass "Intake suggestions present"
  elif has_source; then
    register_fixable "Intake suggestions missing" "fix_intake_suggestions"
  else
    register_manual "Intake suggestions missing" "Copy from orchestrator templates/intake-suggestions/"
  fi

  # Tool matrix
  if [ -d "templates/tool-matrix" ] && ls templates/tool-matrix/*.json &>/dev/null 2>&1; then
    # Validate JSON
    local invalid_json=false
    for f in templates/tool-matrix/*.json; do
      jq '.' "$f" >/dev/null 2>&1 || { invalid_json=true; break; }
    done
    if [ "$invalid_json" = true ]; then
      if has_source; then
        register_fixable "Tool matrix JSON invalid" "fix_tool_matrix"
      else
        register_manual "Tool matrix JSON invalid" "Check JSON syntax in templates/tool-matrix/"
      fi
    else
      register_pass "Tool matrix files valid"
    fi
  elif has_source; then
    register_fixable "Tool matrix files missing" "fix_tool_matrix"
  else
    register_manual "Tool matrix files missing" "Copy from orchestrator templates/tool-matrix/"
  fi
}
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/verify-install.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-install.sh
git commit -m "feat(verify): add project structure checks

CLAUDE.md, PROJECT_INTAKE.md, APPROVAL_LOG.md, .gitignore,
phase-state.json, tool-preferences.json, framework docs, platform
module, CI/release pipelines, intake suggestions, tool matrix."
```

---

### Task 3: Add Check Functions — Scripts, Git, Framework

**Files:**
- Modify: `scripts/verify-install.sh`

- [ ] **Step 1: Add check_scripts, check_git, and check_framework functions**

Append after `check_project_structure`:

```bash
check_scripts() {
  print_step "Checking scripts..."

  local scripts=(
    "scripts/validate.sh"
    "scripts/check-phase-gate.sh"
    "scripts/check-updates.sh"
    "scripts/resume.sh"
    "scripts/intake-wizard.sh"
    "scripts/resolve-tools.sh"
    "scripts/upgrade-project.sh"
    "scripts/verify-install.sh"
  )

  for script in "${scripts[@]}"; do
    local name
    name=$(basename "$script")
    if [ -x "$script" ]; then
      register_pass "$name present and executable"
    elif [ -f "$script" ]; then
      register_fixable "$name not executable" "fix_script_chmod_${name%.sh}"
    elif has_source && [ -f "$SOURCE_DIR/$script" ]; then
      register_fixable "$name missing" "fix_script_copy_${name%.sh}"
    else
      register_manual "$name missing" "Copy from orchestrator $script"
    fi
  done
}

check_git() {
  print_step "Checking git..."

  # Repository initialized
  if [ -d ".git" ] || git rev-parse --git-dir &>/dev/null 2>&1; then
    register_pass "Git repository initialized"
  else
    register_fixable "Git repository not initialized" "fix_git_init"
  fi

  # Pre-commit hook
  if [ -x ".git/hooks/pre-commit" ]; then
    register_pass "Pre-commit hook installed"
  elif [ -d ".git/hooks" ]; then
    register_fixable "Pre-commit hook missing" "fix_precommit_hook"
  else
    register_manual "Pre-commit hook missing" "Initialize git first, then re-run verify"
  fi

  # At least one commit
  if git rev-parse HEAD &>/dev/null 2>&1; then
    register_pass "Initial commit exists"
  else
    register_manual "No commits yet" "Run: git add -A && git commit -m 'chore: initialize project'"
  fi
}

check_framework() {
  print_step "Checking Development Guardrails for Claude Code..."

  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"

  # Global clone
  if [ -d "$FRAMEWORK_CLONE/.git" ]; then
    register_pass "Development Guardrails global clone exists"
  else
    register_fixable "Development Guardrails not cloned" "fix_framework_clone"
  fi

  # Per-project manifest
  if [ -f ".claude/manifest.json" ]; then
    register_pass "Development Guardrails manifest exists"
  elif [ -d "$FRAMEWORK_CLONE/.git" ] && [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
    register_fixable "Development Guardrails manifest missing" "fix_framework_manifest"
  else
    register_manual "Development Guardrails manifest missing" "Clone framework first: git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework && bash ~/.claude-dev-framework/scripts/init.sh"
  fi
}
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/verify-install.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-install.sh
git commit -m "feat(verify): add scripts, git, and framework checks

Scripts: presence + executable for all 8 scripts. Git: repo init,
pre-commit hook, initial commit. Framework: global clone, manifest."
```

---

### Task 4: Add Check Functions — Tools, Plugins, MCP

**Files:**
- Modify: `scripts/verify-install.sh`

- [ ] **Step 1: Add check_tools and check_plugins_mcp functions**

Append after `check_framework`:

```bash
check_tools() {
  print_step "Checking tools..."

  if ! has_context; then
    register_manual "Tool check skipped — no project context" "Run verify after project context is available"
    return
  fi

  if [ ! -x "scripts/resolve-tools.sh" ] || [ ! -d "templates/tool-matrix" ]; then
    register_manual "Tool check skipped — resolver or matrix missing" "Fix those issues first, then re-run"
    return
  fi

  local dev_os
  case "$(uname -s)" in Darwin) dev_os="darwin" ;; *) dev_os="linux" ;; esac

  local resolver_output
  resolver_output=$(bash scripts/resolve-tools.sh \
    --dev-os "$dev_os" \
    --platform "$PLATFORM" \
    --language "$LANGUAGE" \
    --track "$TRACK" \
    --phase 2 \
    --matrix-dir templates/tool-matrix \
    ${TOOL_PREFS_ARG:-} 2>/dev/null) || {
    register_manual "Tool resolver failed" "Check scripts/resolve-tools.sh and templates/tool-matrix/*.json"
    return
  }

  # Already installed tools — pass
  local installed_count
  installed_count=$(echo "$resolver_output" | jq '.already_installed | length')
  if [ "$installed_count" -gt 0 ]; then
    echo "$resolver_output" | jq -r '.already_installed[] | .name' | while IFS= read -r tool; do
      register_pass "$tool installed"
    done
  fi

  # Auto-installable missing tools — fixable
  local auto_count
  auto_count=$(echo "$resolver_output" | jq '.auto_install | length')
  if [ "$auto_count" -gt 0 ]; then
    # Store resolver output for fix functions
    RESOLVER_OUTPUT="$resolver_output"
    for i in $(seq 0 $((auto_count - 1))); do
      local tool_name
      tool_name=$(echo "$resolver_output" | jq -r ".auto_install[$i].name")
      local required
      required=$(echo "$resolver_output" | jq -r ".auto_install[$i].required")
      if [ "$required" = "true" ]; then
        register_fixable "$tool_name not installed (required)" "fix_tool_install_$i"
      else
        register_fixable "$tool_name not installed (recommended)" "fix_tool_install_$i"
      fi
    done
  fi

  # Manual install tools
  local manual_count
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  if [ "$manual_count" -gt 0 ]; then
    for i in $(seq 0 $((manual_count - 1))); do
      local tool_name instructions
      tool_name=$(echo "$resolver_output" | jq -r ".manual_install[$i].name")
      instructions=$(echo "$resolver_output" | jq -r ".manual_install[$i].instructions")
      register_manual "$tool_name not installed" "$instructions"
    done
  fi
}

check_plugins_mcp() {
  print_step "Checking plugins and MCP servers..."

  if ! command -v jq &>/dev/null || [ ! -f "$HOME/.claude/settings.json" ]; then
    register_manual "Plugin/MCP check skipped" "Requires jq and ~/.claude/settings.json"
    return
  fi

  # Superpowers
  local sp_installed
  sp_installed=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
  if [ "$sp_installed" = "true" ]; then
    register_pass "Superpowers plugin installed"
  else
    register_fixable "Superpowers plugin not installed" "fix_superpowers"
  fi

  # Context7 MCP
  if jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    register_pass "Context7 MCP configured"
  elif command -v node &>/dev/null; then
    register_fixable "Context7 MCP not configured" "fix_context7"
  else
    register_manual "Context7 MCP not configured" "Install Node.js first, then: claude mcp add context7 -- npx -y @upstash/context7-mcp@latest"
  fi

  # Qdrant MCP
  if jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    register_pass "Qdrant MCP configured"
  else
    register_manual "Qdrant MCP not configured" "Requires Docker + uv. See docs/framework/cli-setup-addendum.md"
  fi
}
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/verify-install.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-install.sh
git commit -m "feat(verify): add tool, plugin, and MCP checks

Tools via resolver (auto-install vs manual). Superpowers plugin,
Context7 MCP, Qdrant MCP detection with appropriate fix categories."
```

---

### Task 5: Add Fix Functions

**Files:**
- Modify: `scripts/verify-install.sh`

- [ ] **Step 1: Add all fix functions**

Append after the check functions:

```bash
# ================================================================
# FIX FUNCTIONS
# ================================================================

fix_claude_md() {
  if ! has_context || ! has_source; then return 1; fi
  # Re-generate minimal CLAUDE.md from context
  cat > CLAUDE.md << CLAUDEEOF
# CLAUDE.md — ${PROJECT_NAME:-unknown}

## Project Identity
- **Project:** ${PROJECT_NAME:-unknown}
- **Platform:** ${PLATFORM}
- **Track:** ${TRACK}
- **Primary Language:** ${LANGUAGE}

## Framework Reference
This project follows the **Solo Orchestrator Framework v1.0**.
- Builder's Guide: \`docs/framework/builders-guide.md\`
- Platform Module: \`docs/platform-modules/\`
- Project Intake: \`PROJECT_INTAKE.md\`
- Approval Log: \`APPROVAL_LOG.md\`

## Note
This CLAUDE.md was regenerated by verify-install.sh. Review and customize as needed.
CLAUDEEOF
}

fix_intake_md() {
  if has_source && [ -f "$SOURCE_DIR/templates/project-intake.md" ]; then
    cp "$SOURCE_DIR/templates/project-intake.md" PROJECT_INTAKE.md
  else
    return 1
  fi
}

fix_approval_log() {
  local today
  today=$(date +%Y-%m-%d)
  if [ "$DEPLOYMENT" = "organizational" ]; then
    cat > APPROVAL_LOG.md << EOF
---
project: ${PROJECT_NAME:-unknown}
deployment: organizational
created: $today
framework: Solo Orchestrator v1.0
---

# Approval Log — ${PROJECT_NAME:-unknown}

This document was regenerated by verify-install.sh. Review and update.
EOF
  else
    cat > APPROVAL_LOG.md << EOF
---
project: ${PROJECT_NAME:-unknown}
deployment: personal
created: $today
framework: Solo Orchestrator v1.0
---

# Approval Log — ${PROJECT_NAME:-unknown}

This document was regenerated by verify-install.sh. Review and update.
EOF
  fi
}

fix_gitignore() {
  cat > .gitignore << 'EOF'
node_modules/
venv/
__pycache__/
*.pyc
.env
.env.local
dist/
build/
.next/
target/
.vscode/
.idea/
.DS_Store
coverage/
*.log
*.pem
*.key
credentials.json
EOF
}

fix_phase_state() {
  mkdir -p .claude
  cat > .claude/phase-state.json << EOF
{
  "project": "${PROJECT_NAME:-unknown}",
  "framework_version": "1.0",
  "current_phase": 0,
  "gates": {
    "phase_0_to_1": null,
    "phase_1_to_2": null,
    "phase_3_to_4": null
  }
}
EOF
}

fix_tool_prefs() {
  if ! has_context; then return 1; fi
  mkdir -p .claude
  local dev_os
  case "$(uname -s)" in Darwin) dev_os="darwin" ;; *) dev_os="linux" ;; esac
  local today
  today=$(date +%Y-%m-%d)
  jq -n \
    --arg v "1.0" --arg d "$today" --arg os "$dev_os" \
    --arg p "$PLATFORM" --arg l "$LANGUAGE" --arg t "$TRACK" \
    '{schema_version:$v, resolved_at:$d, context:{dev_os:$os, platform:$p, language:$l, track:$t}, substitutions:{}, additions:[], skipped:[], installed:{}}' \
    > .claude/tool-preferences.json
}

fix_orchestrator_source() {
  if has_source; then
    mkdir -p .claude
    jq -n --arg s "$SOURCE_DIR" '{source_dir: $s}' > .claude/orchestrator-source.json
  else
    return 1
  fi
}

# Generic fix: re-copy a framework doc from orchestrator source
fix_framework_doc() {
  local doc_name="$1"
  if has_source && [ -f "$SOURCE_DIR/docs/$doc_name" ]; then
    mkdir -p docs/framework
    cp "$SOURCE_DIR/docs/$doc_name" "docs/framework/$doc_name"
  else
    return 1
  fi
}

# Generate fix functions for each framework doc
for _doc in builders-guide governance-framework executive-review cli-setup-addendum user-guide security-scan-guide; do
  eval "fix_framework_doc_${_doc}() { fix_framework_doc '${_doc}.md'; }"
done

fix_platform_module() {
  if has_source && [ -n "$PLATFORM" ] && [ -f "$SOURCE_DIR/docs/platform-modules/${PLATFORM}.md" ]; then
    mkdir -p docs/platform-modules
    cp "$SOURCE_DIR/docs/platform-modules/${PLATFORM}.md" "docs/platform-modules/"
  else
    return 1
  fi
}

fix_ci_pipeline() {
  if ! has_source || ! has_context; then return 1; fi
  local ci_template
  case "$LANGUAGE" in
    typescript|javascript) ci_template="typescript.yml" ;;
    kotlin|java) ci_template="jvm.yml" ;;
    *) ci_template="${LANGUAGE}.yml" ;;
  esac
  if [ -f "$SOURCE_DIR/templates/pipelines/ci/$ci_template" ]; then
    mkdir -p .github/workflows
    cp "$SOURCE_DIR/templates/pipelines/ci/$ci_template" .github/workflows/ci.yml
  else
    return 1
  fi
}

fix_release_pipeline() {
  if ! has_source || [ -z "$PLATFORM" ]; then return 1; fi
  if [ -f "$SOURCE_DIR/templates/pipelines/release/${PLATFORM}.yml" ]; then
    mkdir -p .github/workflows
    cp "$SOURCE_DIR/templates/pipelines/release/${PLATFORM}.yml" .github/workflows/release.yml
  else
    return 1
  fi
}

fix_intake_suggestions() {
  if has_source; then
    mkdir -p templates/intake-suggestions
    cp "$SOURCE_DIR/templates/intake-suggestions/"*.json templates/intake-suggestions/ 2>/dev/null
  else
    return 1
  fi
}

fix_tool_matrix() {
  if has_source; then
    mkdir -p templates/tool-matrix
    cp "$SOURCE_DIR/templates/tool-matrix/"*.json templates/tool-matrix/
  else
    return 1
  fi
}

# Generic fix: re-copy and chmod a script
fix_script() {
  local script_name="$1"
  if has_source && [ -f "$SOURCE_DIR/scripts/$script_name" ]; then
    cp "$SOURCE_DIR/scripts/$script_name" "scripts/$script_name"
    chmod +x "scripts/$script_name"
  else
    return 1
  fi
}

# Generate fix functions for each script
for _s in validate check-phase-gate check-updates resume intake-wizard resolve-tools upgrade-project verify-install; do
  eval "fix_script_chmod_${_s}() { chmod +x 'scripts/${_s}.sh'; }"
  eval "fix_script_copy_${_s}() { fix_script '${_s}.sh'; }"
done

fix_git_init() {
  git init -q
}

fix_precommit_hook() {
  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit << 'HOOKEOF'
#!/usr/bin/env bash
set -euo pipefail
FAILED=0
if command -v gitleaks &>/dev/null; then
  if ! gitleaks protect --staged --verbose --no-banner 2>/dev/null; then
    echo "[BLOCKED] gitleaks detected secrets in staged files."
    FAILED=1
  fi
fi
if command -v semgrep &>/dev/null; then
  staged_files=$(git diff --cached --name-only --diff-filter=ACM)
  if [ -n "$staged_files" ]; then
    if ! echo "$staged_files" | xargs semgrep scan --config=p/owasp-top-ten --quiet --no-git-ignore 2>/dev/null; then
      echo "[BLOCKED] Semgrep detected security issues."
      FAILED=1
    fi
  fi
fi
exit $FAILED
HOOKEOF
  chmod +x .git/hooks/pre-commit
}

fix_framework_clone() {
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
  git clone -q --depth 1 https://github.com/kraulerson/claude-dev-framework.git "$FRAMEWORK_CLONE" 2>/dev/null
}

fix_framework_manifest() {
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
  if [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
    bash "$FRAMEWORK_CLONE/scripts/init.sh" 2>/dev/null || return 1
  else
    return 1
  fi
}

# Tool install fixes — dynamic, based on resolver output stored in RESOLVER_OUTPUT
RESOLVER_OUTPUT=""

fix_tool_install() {
  local index="$1"
  if [ -z "$RESOLVER_OUTPUT" ]; then return 1; fi
  local install_cmd
  install_cmd=$(echo "$RESOLVER_OUTPUT" | jq -r ".auto_install[$index].install_cmd")
  if [ -n "$install_cmd" ] && [ "$install_cmd" != "null" ]; then
    eval "$install_cmd" 2>/dev/null
  else
    return 1
  fi
}

# Generate fix functions for tool indices 0-19 (more than enough)
for _i in $(seq 0 19); do
  eval "fix_tool_install_${_i}() { fix_tool_install ${_i}; }"
done

fix_superpowers() {
  claude plugins add superpowers 2>/dev/null
}

fix_context7() {
  claude mcp add context7 -- npx -y @upstash/context7-mcp@latest 2>/dev/null
}
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/verify-install.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-install.sh
git commit -m "feat(verify): add all fix/remediation functions

Project structure fixes (re-generate/re-copy), script fixes (copy +
chmod), git fixes (init, pre-commit hook), framework fixes (clone,
manifest), tool fixes (via resolver), plugin/MCP fixes."
```

---

### Task 6: Add Main Flow — Report and Remediate

**Files:**
- Modify: `scripts/verify-install.sh`

- [ ] **Step 1: Add the main execution flow at the end of the script**

Append at the end:

```bash
# ================================================================
# REPORT
# ================================================================
show_report() {
  local fixable_count=${#FIXABLE[@]}
  local manual_count=${#MANUAL[@]}
  local pass_count=${#PASSED[@]}

  echo ""
  echo -e "${BOLD}┌──────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│  Installation Verification Report            │${NC}"
  echo -e "${BOLD}├──────────────────────────────────────────────┤${NC}"
  echo -e "${BOLD}│${NC}  ${GREEN}✓ Passed: $pass_count${NC}"
  echo -e "${BOLD}│${NC}  ${CYAN}⚡ Auto-fixable: $fixable_count${NC}"
  echo -e "${BOLD}│${NC}  ${YELLOW}⚠ Manual action required: $manual_count${NC}"

  if [ "$fixable_count" -gt 0 ]; then
    echo -e "${BOLD}├──────────────────────────────────────────────┤${NC}"
    echo -e "${BOLD}│${NC}  ${CYAN}AUTO-FIXABLE:${NC}"
    for entry in "${FIXABLE[@]}"; do
      local desc="${entry%%||*}"
      echo -e "${BOLD}│${NC}    • $desc"
    done
  fi

  if [ "$manual_count" -gt 0 ]; then
    echo -e "${BOLD}├──────────────────────────────────────────────┤${NC}"
    echo -e "${BOLD}│${NC}  ${YELLOW}MANUAL:${NC}"
    for entry in "${MANUAL[@]}"; do
      local desc="${entry%%||*}"
      local instr="${entry##*||}"
      echo -e "${BOLD}│${NC}    • $desc"
      echo -e "${BOLD}│${NC}      → $instr"
    done
  fi

  echo -e "${BOLD}└──────────────────────────────────────────────┘${NC}"
}

# ================================================================
# REMEDIATE
# ================================================================
run_remediation() {
  local fixable_count=${#FIXABLE[@]}
  if [ "$fixable_count" -eq 0 ]; then return 0; fi

  if [ "$MODE" = "check-only" ]; then return 1; fi

  # Prompt or auto-fix
  if [ "$MODE" = "interactive" ]; then
    echo ""
    read -rp "$(echo -e "${BOLD}Auto-fix $fixable_count issues? [Y/n]${NC}: ")" response
    if [[ "$response" =~ ^[Nn] ]]; then
      print_info "Skipping auto-fix. Run with --auto-fix later or fix manually."
      return 1
    fi
  fi

  echo ""
  print_step "Remediating $fixable_count issues..."

  local fixed=0
  local failed=0

  for entry in "${FIXABLE[@]}"; do
    local desc="${entry%%||*}"
    local fix_func="${entry##*||}"
    print_info "Fixing: $desc"
    if $fix_func 2>/dev/null; then
      print_ok "Fixed: $desc"
      ((fixed++))
    else
      print_fail "Could not fix: $desc"
      ((failed++))
    fi
  done

  echo ""
  print_info "Remediation: $fixed fixed, $failed failed"
  return $failed
}

# ================================================================
# MAIN
# ================================================================
main() {
  echo ""
  echo -e "${BOLD}Solo Orchestrator — Installation Verification${NC}"
  echo ""

  # Load context
  load_context

  if [ -n "$PLATFORM" ]; then
    print_info "Project context: $PLATFORM / $LANGUAGE / $TRACK"
  else
    print_warn "Limited project context — some checks may be skipped"
  fi

  if has_source; then
    print_info "Orchestrator source: $SOURCE_DIR"
  else
    print_warn "Orchestrator source not found — file re-copy fixes unavailable"
  fi

  # Set up tool-prefs arg for resolver
  if [ -f ".claude/tool-preferences.json" ]; then
    TOOL_PREFS_ARG="--tool-prefs .claude/tool-preferences.json"
  else
    TOOL_PREFS_ARG=""
  fi

  echo ""

  # Phase 1: DETECT
  check_project_structure
  check_scripts
  check_git
  check_framework
  check_tools
  check_plugins_mcp

  # Phase 2: REPORT
  show_report

  local total_issues=$(( ${#FIXABLE[@]} + ${#MANUAL[@]} ))

  if [ "$total_issues" -eq 0 ]; then
    echo ""
    print_ok "All checks passed. Installation is healthy."
    exit 0
  fi

  # Phase 3: REMEDIATE
  local remediation_failed=0
  if [ ${#FIXABLE[@]} -gt 0 ]; then
    run_remediation || remediation_failed=$?
  fi

  # Phase 4: FINAL STATUS
  if [ "$remediation_failed" -gt 0 ] || [ ${#MANUAL[@]} -gt 0 ]; then
    echo ""
    if [ ${#MANUAL[@]} -gt 0 ]; then
      print_warn "${#MANUAL[@]} issue(s) require manual action (see report above)"
    fi
    exit 1
  else
    echo ""
    print_ok "All auto-fixable issues resolved."
    exit 0
  fi
}

main
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/verify-install.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Test in a real project context**

Run: `cd /tmp && mkdir -p verify-test/.claude && echo '{"context":{"platform":"web","language":"typescript","track":"standard"}}' > verify-test/.claude/tool-preferences.json && cd verify-test && bash "/Users/karl/Documents/AI Projects/solo-orchestrator/scripts/verify-install.sh" --check-only 2>&1 | tail -20; cd /tmp && rm -rf verify-test`

Expected: Should show a verification report with many failures (since the test directory has almost nothing) but no crashes.

- [ ] **Step 4: Commit**

```bash
git add scripts/verify-install.sh
git commit -m "feat(verify): add main flow — report, remediate, final status

Four-phase execution: detect all issues, display grouped report,
offer batch remediation with single Y/n, re-verify and report
final status."
```

---

### Task 7: Integrate with init.sh

**Files:**
- Modify: `init.sh`

- [ ] **Step 1: Write orchestrator-source.json in create_project()**

In `init.sh`, find the line `mkdir -p .claude` before phase-state.json generation (line 876). After writing phase-state.json (after the `PHEOF` line ~888), add:

```bash
  # Store orchestrator source path for verify-install.sh remediation
  if command -v jq &>/dev/null; then
    jq -n --arg s "$SCRIPT_DIR" '{source_dir: $s}' > .claude/orchestrator-source.json
    print_ok "Orchestrator source path stored"
  fi
```

- [ ] **Step 2: Add verify-install.sh to the script copy list**

In `init.sh`, find the script copy block (line ~745-751). Add after the resolve-tools.sh copy:

```bash
  cp "$SCRIPT_DIR/scripts/upgrade-project.sh" scripts/
  cp "$SCRIPT_DIR/scripts/verify-install.sh" scripts/
```

Update the chmod line to include both new scripts:

```bash
  chmod +x scripts/validate.sh scripts/check-phase-gate.sh scripts/check-updates.sh scripts/resume.sh scripts/intake-wizard.sh scripts/resolve-tools.sh scripts/upgrade-project.sh scripts/verify-install.sh
```

- [ ] **Step 3: Replace health_check() call in main()**

In `init.sh` `main()` (line ~1904), replace:

```bash
    health_check
```

with:

```bash
    bash "$PROJECT_DIR/scripts/verify-install.sh" --auto-fix || true
```

- [ ] **Step 4: Remove health_check() function**

Delete the `health_check()` function (lines 1617-1683).

- [ ] **Step 5: Validate syntax**

Run: `bash -n init.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add init.sh
git commit -m "feat(init): integrate verify-install.sh, remove health_check()

Write orchestrator-source.json for remediation file lookups.
Copy verify-install.sh and upgrade-project.sh to projects.
Replace health_check() with verify-install.sh --auto-fix."
```

---

### Task 8: Integrate with upgrade-project.sh

**Files:**
- Modify: `scripts/upgrade-project.sh`

- [ ] **Step 1: Add verify-install.sh call at the end**

In `scripts/upgrade-project.sh`, find the final line `print_ok "Upgrade complete."` (line 1249). Add before it:

```bash
# Run installation verification after upgrade
if [ -x "scripts/verify-install.sh" ]; then
  echo ""
  print_step "Running post-upgrade verification..."
  bash scripts/verify-install.sh || true
fi
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/upgrade-project.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/upgrade-project.sh
git commit -m "feat(upgrade): run verify-install.sh after upgrades

Post-upgrade verification surfaces any newly-required tools or
files that the upgrade path didn't handle automatically."
```

---

### Task 9: End-to-End Validation

**Files:**
- Read: all modified files

- [ ] **Step 1: Validate all scripts**

Run: `bash -n init.sh && bash -n scripts/verify-install.sh && bash -n scripts/upgrade-project.sh && echo "ALL OK"`
Expected: `ALL OK`

- [ ] **Step 2: Test verify-install.sh in check-only mode against a simulated project**

Run:
```bash
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
mkdir -p .claude templates/tool-matrix scripts docs/framework .github/workflows .git/hooks
echo '{"context":{"platform":"web","language":"typescript","track":"standard"}}' > .claude/tool-preferences.json
echo '{"project":"test","framework_version":"1.0","current_phase":0}' > .claude/phase-state.json
echo '{"source_dir":"/Users/karl/Documents/AI Projects/solo-orchestrator"}' > .claude/orchestrator-source.json
echo "# test" > CLAUDE.md
echo "# test" > PROJECT_INTAKE.md
echo "# test" > APPROVAL_LOG.md
echo "# test" > .gitignore
git init -q && git add -A && git commit -q -m "test"
cp "/Users/karl/Documents/AI Projects/solo-orchestrator/scripts/verify-install.sh" scripts/
cp "/Users/karl/Documents/AI Projects/solo-orchestrator/scripts/resolve-tools.sh" scripts/
cp "/Users/karl/Documents/AI Projects/solo-orchestrator/templates/tool-matrix/"*.json templates/tool-matrix/
chmod +x scripts/*.sh
bash scripts/verify-install.sh --check-only 2>&1 | tail -30
cd /tmp && rm -rf "$TEST_DIR"
```

Expected: Report shows passes for existing items, fixable/manual for missing items. No crashes.

- [ ] **Step 3: Test verify-install.sh --auto-fix mode**

Run same setup as Step 2 but with `--auto-fix` instead of `--check-only`. Verify it attempts fixes.

- [ ] **Step 4: No commit needed — this is validation only**

---

## Summary

| Task | What It Does |
|---|---|
| 1 | Script framework: args, colors, registration, context loader |
| 2 | Check: project structure (files, docs, pipelines, matrix) |
| 3 | Check: scripts, git, Development Guardrails |
| 4 | Check: tools (via resolver), plugins, MCP servers |
| 5 | Fix functions for all remediable issues |
| 6 | Main flow: detect → report → remediate → final status |
| 7 | Init.sh integration (replace health_check, copy script) |
| 8 | Upgrade-project.sh integration (post-upgrade verify) |
| 9 | End-to-end validation |

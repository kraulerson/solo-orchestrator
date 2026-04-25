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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

# UAT 2026-04-25 fix (U-N): refuse to operate inside the framework repo.
# verify-install.sh's auto-create-stub-artifacts behavior was the root cause
# of the framework-self-contamination incident.
guard_not_in_framework || exit 1

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

  # Deployment from intake-progress or CLAUDE.md
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
    PLATFORM=$(grep -m1 'Platform:' "CLAUDE.md" 2>/dev/null | sed 's/.*Platform:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '*' || echo "")
  fi
  if [ -z "$LANGUAGE" ] && [ -f "CLAUDE.md" ]; then
    LANGUAGE=$(grep -m1 'Primary Language:' "CLAUDE.md" 2>/dev/null | sed 's/.*Primary Language:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '*' || echo "")
  fi
  if [ -z "$TRACK" ] && [ -f "CLAUDE.md" ]; then
    TRACK=$(grep -m1 'Track:' "CLAUDE.md" 2>/dev/null | sed 's/.*Track:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '*' || echo "")
  fi

  # Orchestrator source directory
  if [ -f ".claude/orchestrator-source.json" ] && command -v jq &>/dev/null; then
    SOURCE_DIR=$(jq -r '.source_dir // empty' ".claude/orchestrator-source.json" 2>/dev/null || echo "")
  fi
  if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
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
    "builders-guide.md"
    "governance-framework.md"
    "executive-review.md"
    "cli-setup-addendum.md"
    "user-guide.md"
    "security-scan-guide.md"
  )
  for doc in "${framework_docs[@]}"; do
    if [ -f "docs/reference/$doc" ]; then
      register_pass "$doc exists"
    elif has_source && [ -f "$SOURCE_DIR/docs/$doc" ]; then
      register_fixable "$doc missing" "fix_framework_doc_${doc%.md}"
    else
      register_manual "$doc missing" "Re-copy from orchestrator source directory"
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

  # CI pipeline
  if [ -f ".github/workflows/ci.yml" ]; then
    register_pass "CI pipeline exists"
  elif has_source && has_context; then
    register_fixable "CI pipeline missing" "fix_ci_pipeline"
  else
    register_manual "CI pipeline missing" "Copy from orchestrator templates/pipelines/ci/"
  fi

  # Release pipeline
  if [ -n "$PLATFORM" ] && has_source && [ -f "$SOURCE_DIR/templates/pipelines/release/${PLATFORM}.yml" ]; then
    if [ -f ".github/workflows/release.yml" ]; then
      register_pass "Release pipeline exists"
    else
      register_fixable "Release pipeline missing" "fix_release_pipeline"
    fi
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
    name=$(basename "$script" .sh)
    if [ -x "$script" ]; then
      register_pass "$name present and executable"
    elif [ -f "$script" ]; then
      register_fixable "$name not executable" "fix_script_chmod_${name}"
    elif has_source && [ -f "$SOURCE_DIR/$script" ]; then
      register_fixable "$name missing" "fix_script_copy_${name}"
    else
      register_manual "$name missing" "Copy from orchestrator $script"
    fi
  done
}

check_git() {
  print_step "Checking git..."

  if [ -d ".git" ] || git rev-parse --git-dir &>/dev/null 2>&1; then
    register_pass "Git repository initialized"
  else
    register_fixable "Git repository not initialized" "fix_git_init"
  fi

  if [ -x ".git/hooks/pre-commit" ]; then
    register_pass "Pre-commit hook installed"
  elif [ -d ".git/hooks" ]; then
    register_fixable "Pre-commit hook missing" "fix_precommit_hook"
  else
    register_manual "Pre-commit hook missing" "Initialize git first, then re-run verify"
  fi

  if git rev-parse HEAD &>/dev/null 2>&1; then
    register_pass "Initial commit exists"
  else
    register_manual "No commits yet" "Run: git add -A && git commit -m 'chore: initialize project'"
  fi
}

check_hooks() {
  print_step "Checking Claude Code hook registration..."

  if [ ! -f ".claude/settings.json" ]; then
    register_manual "Claude Code settings.json missing" "Run init.sh to generate settings"
    return
  fi

  if ! command -v jq &>/dev/null; then
    register_manual "Hook check skipped — jq not available" "Install jq for hook verification"
    return
  fi

  # PreToolUse hook: pre-commit-gate.sh
  if jq -e '.hooks.PreToolUse[]? | .hooks[]? | select(.command | contains("pre-commit-gate.sh"))' .claude/settings.json >/dev/null 2>&1; then
    # Verify matcher is Bash
    local matcher
    matcher=$(jq -r '[.hooks.PreToolUse[]? | select(.hooks[]? | .command | contains("pre-commit-gate.sh")) | .matcher // "none"] | first' .claude/settings.json 2>/dev/null || echo "unknown")
    if [ "$matcher" = "Bash" ]; then
      register_pass "PreToolUse hook: pre-commit-gate.sh (matcher: Bash)"
    else
      register_manual "PreToolUse hook matcher is '$matcher' (expected 'Bash')" \
        "Edit .claude/settings.json: set PreToolUse matcher to 'Bash' for the pre-commit-gate.sh entry"
    fi
  else
    register_manual "PreToolUse hook: pre-commit-gate.sh not registered" \
      "Add pre-commit-gate.sh to .hooks.PreToolUse in .claude/settings.json (see init.sh for format)"
  fi

  # PostToolUse hook: track-tool-usage.sh
  if jq -e '.hooks.PostToolUse[]? | .hooks[]? | select(.command | contains("track-tool-usage.sh"))' .claude/settings.json >/dev/null 2>&1; then
    register_pass "PostToolUse hook: track-tool-usage.sh"
  else
    register_manual "PostToolUse hook: track-tool-usage.sh not registered" \
      "Add track-tool-usage.sh to .hooks.PostToolUse in .claude/settings.json"
  fi

  # SessionStart hooks
  if jq -e '.hooks.SessionStart[]? | .hooks[]? | select(.command | contains("session-version-check.sh") or contains("session-test-gate-check.sh"))' .claude/settings.json >/dev/null 2>&1; then
    register_pass "SessionStart hooks: version check + test gate"
  else
    register_manual "SessionStart hooks incomplete" \
      "Add session-version-check.sh and session-test-gate-check.sh to .hooks.SessionStart in .claude/settings.json"
  fi

  # Stop hook: session-end-qdrant-reminder.sh
  if jq -e '.hooks.Stop[]? | .hooks[]? | select(.command | contains("session-end-qdrant-reminder.sh"))' .claude/settings.json >/dev/null 2>&1; then
    register_pass "Stop hook: session-end-qdrant-reminder.sh"
  else
    register_manual "Stop hook: session-end-qdrant-reminder.sh not registered" \
      "Add session-end-qdrant-reminder.sh to .hooks.Stop in .claude/settings.json"
  fi
}

check_framework() {
  print_step "Checking Development Guardrails for Claude Code..."

  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"

  if [ -d "$FRAMEWORK_CLONE/.git" ]; then
    register_pass "Development Guardrails global clone exists"
  else
    register_fixable "Development Guardrails not cloned" "fix_framework_clone"
  fi

  if [ -f ".claude/manifest.json" ]; then
    register_pass "Development Guardrails manifest exists"
  elif [ -d "$FRAMEWORK_CLONE/.git" ] && [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
    register_fixable "Development Guardrails manifest missing" "fix_framework_manifest"
  else
    register_manual "Development Guardrails manifest missing" "Clone framework first: git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework && bash ~/.claude-dev-framework/scripts/init.sh"
  fi
}

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

  local prefs_arg=""
  if [ -f ".claude/tool-preferences.json" ]; then
    prefs_arg="--tool-prefs .claude/tool-preferences.json"
  fi

  local resolver_output
  resolver_output=$(bash scripts/resolve-tools.sh \
    --dev-os "$dev_os" \
    --platform "$PLATFORM" \
    --language "$LANGUAGE" \
    --track "$TRACK" \
    --phase 2 \
    --matrix-dir templates/tool-matrix \
    $prefs_arg 2>/dev/null) || {
    register_manual "Tool resolver failed" "Check scripts/resolve-tools.sh and templates/tool-matrix/*.json"
    return
  }

  # Already installed — pass
  local installed_count
  installed_count=$(echo "$resolver_output" | jq '.already_installed | length')
  if [ "$installed_count" -gt 0 ]; then
    for i in $(seq 0 $((installed_count - 1))); do
      local tool_name
      tool_name=$(echo "$resolver_output" | jq -r ".already_installed[$i].name")
      register_pass "$tool_name installed"
    done
  fi

  # Auto-installable missing — fixable
  local auto_count
  auto_count=$(echo "$resolver_output" | jq '.auto_install | length')
  if [ "$auto_count" -gt 0 ]; then
    RESOLVER_OUTPUT="$resolver_output"
    for i in $(seq 0 $((auto_count - 1))); do
      local tool_name required
      tool_name=$(echo "$resolver_output" | jq -r ".auto_install[$i].name")
      required=$(echo "$resolver_output" | jq -r ".auto_install[$i].required")
      if [ "$required" = "true" ]; then
        register_fixable "$tool_name not installed (required)" "fix_tool_install_$i"
      else
        register_fixable "$tool_name not installed (recommended)" "fix_tool_install_$i"
      fi
    done
  fi

  # Manual install — skip MCP servers (handled separately by check_plugins_mcp)
  local manual_count
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  if [ "$manual_count" -gt 0 ]; then
    for i in $(seq 0 $((manual_count - 1))); do
      local tool_name instructions tool_category
      tool_name=$(echo "$resolver_output" | jq -r ".manual_install[$i].name")
      tool_category=$(echo "$resolver_output" | jq -r ".manual_install[$i].category // empty")
      instructions=$(echo "$resolver_output" | jq -r ".manual_install[$i].instructions")
      # MCP servers are checked by check_plugins_mcp — don't duplicate
      [ "$tool_category" = "mcp_server" ] && continue
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

  # Context7 MCP — direct MCP registration or plugin-installed (see lib/helpers.sh)
  if is_context7_mcp_registered; then
    register_pass "Context7 MCP configured"
  elif command -v node &>/dev/null; then
    register_fixable "Context7 MCP not configured" "fix_context7"
  else
    register_manual "Context7 MCP not configured" "Install Node.js first, then: claude mcp add context7 -- npx -y @upstash/context7-mcp@latest"
  fi

  # Qdrant MCP — check both config locations
  if ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
     ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1); then
    register_pass "Qdrant MCP configured"
  else
    register_manual "Qdrant MCP not configured" "Requires Docker + uv. See docs/reference/cli-setup-addendum.md"
  fi
}

# ================================================================
# FIX FUNCTIONS
# ================================================================

fix_claude_md() {
  if ! has_context; then return 1; fi
  cat > CLAUDE.md << CLAUDEEOF
# CLAUDE.md — ${PROJECT_NAME:-unknown}

## Project Identity
- **Project:** ${PROJECT_NAME:-unknown}
- **Platform:** ${PLATFORM}
- **Track:** ${TRACK}
- **Primary Language:** ${LANGUAGE}

## Framework Reference
This project follows the **Solo Orchestrator Framework v1.0**.
- Builder's Guide: \`docs/reference/builders-guide.md\`
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
  cat > APPROVAL_LOG.md << EOF
---
project: ${PROJECT_NAME:-unknown}
deployment: ${DEPLOYMENT:-personal}
created: $today
framework: Solo Orchestrator v1.0
---

# Approval Log — ${PROJECT_NAME:-unknown}

This document was regenerated by verify-install.sh. Review and update as needed.
EOF
}

fix_gitignore() {
  cat > .gitignore << 'EOF'
node_modules/
venv/
__pycache__/
*.pyc
.env
.env.local
.env.production
dist/
build/
.next/
target/
.vscode/
.idea/
.DS_Store
Thumbs.db
coverage/
*.log
*.pem
*.key
credentials.json
service-account.json
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

# Generic: re-copy a framework doc
fix_framework_doc() {
  local doc_name="$1"
  if has_source && [ -f "$SOURCE_DIR/docs/$doc_name" ]; then
    mkdir -p docs/reference
    cp "$SOURCE_DIR/docs/$doc_name" "docs/reference/$doc_name"
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
    kotlin) ci_template="kotlin.yml" ;;
    java) ci_template="java.yml" ;;
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

# Generic: re-copy and chmod a script
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
  if ! gitleaks git --staged 2>/dev/null; then
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

# Tool install fixes — dynamic, based on resolver output
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

for _i in $(seq 0 19); do
  eval "fix_tool_install_${_i}() { fix_tool_install ${_i}; }"
done

fix_superpowers() {
  claude plugins add superpowers 2>/dev/null
}

fix_context7() {
  run_with_timeout 30 bash -c 'claude mcp add context7 -- npx -y @upstash/context7-mcp@latest >/dev/null 2>&1'
}

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
      fixed=$((fixed + 1))
    else
      print_fail "Could not fix: $desc"
      failed=$((failed + 1))
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

  echo ""

  # Phase 1: DETECT
  check_project_structure
  check_scripts
  check_git
  check_hooks
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

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

  # Deployment from intake-progress, phase-state, or CLAUDE.md (in that
  # order of trust). Bonus catch alongside code-verify-reconfigure-9:
  # the prior load order skipped phase-state.json (which init.sh writes
  # with the canonical .deployment field) and only fell through to
  # CLAUDE.md grep. When CLAUDE.md was deleted (the exact case
  # fix_claude_md is invoked to repair), DEPLOYMENT was left empty and
  # fix_claude_md skipped the organizational Branch Protection appendix.
  if [ -f ".claude/intake-progress.json" ] && command -v jq &>/dev/null; then
    DEPLOYMENT=$(jq -r '.deployment // empty' ".claude/intake-progress.json" 2>/dev/null || echo "")
  fi
  if [ -z "$DEPLOYMENT" ] && [ -f ".claude/phase-state.json" ] && command -v jq &>/dev/null; then
    DEPLOYMENT=$(jq -r '.deployment // empty' ".claude/phase-state.json" 2>/dev/null || echo "")
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

  # CI pipeline — host-aware. The CI destination depends on the SCM
  # host: github → .github/workflows/ci.yml, bitbucket →
  # bitbucket-pipelines.yml at repo root, gitlab → .gitlab-ci.yml at
  # repo root. Mirrors the same detection logic encoded in
  # _detect_pipeline_host (used by the fix_*_pipeline functions later
  # in this file); kept inline here because the existence check runs
  # during context gathering and we want to surface the right
  # destination in the fail message.
  local _ci_host=""
  if [ -f .claude/manifest.json ] && command -v jq &>/dev/null; then
    _ci_host=$(jq -r '.host // empty' .claude/manifest.json 2>/dev/null)
  fi
  if [ -z "$_ci_host" ] || [ "$_ci_host" = "null" ]; then
    case "$(git remote get-url origin 2>/dev/null)" in
      *github.com*)    _ci_host="github" ;;
      *gitlab*)        _ci_host="gitlab" ;;
      *bitbucket.org*) _ci_host="bitbucket" ;;
      *)               _ci_host="other" ;;
    esac
  fi
  local _ci_dest=""
  case "$_ci_host" in
    github)    _ci_dest=".github/workflows/ci.yml" ;;
    bitbucket) _ci_dest="bitbucket-pipelines.yml" ;;
    gitlab)    _ci_dest=".gitlab-ci.yml" ;;
  esac
  if [ -n "$_ci_dest" ] && [ -f "$_ci_dest" ]; then
    register_pass "CI pipeline exists ($_ci_dest)"
  elif [ -z "$_ci_dest" ]; then
    register_manual "CI pipeline missing" "Unsupported SCM host '$_ci_host' — no canonical CI destination; configure manually"
  elif has_source && has_context; then
    register_fixable "CI pipeline missing ($_ci_dest)" "fix_ci_pipeline"
  else
    register_manual "CI pipeline missing ($_ci_dest)" "Copy from orchestrator templates/pipelines/ci/$_ci_host/"
  fi

  # Release pipeline — same host routing. bitbucket/gitlab carry
  # release steps in their unified pipeline file (no separate
  # release.yml); register a manual entry so the warning surfaces.
  if [ -n "$PLATFORM" ] && has_source && [ -f "$SOURCE_DIR/templates/pipelines/release/$_ci_host/${PLATFORM}.yml" ]; then
    case "$_ci_host" in
      github)
        if [ -f ".github/workflows/release.yml" ]; then
          register_pass "Release pipeline exists"
        else
          register_fixable "Release pipeline missing" "fix_release_pipeline"
        fi
        ;;
      bitbucket|gitlab)
        register_manual "Release pipeline (host=$_ci_host)" "Integrate release steps from templates/pipelines/release/$_ci_host/${PLATFORM}.yml into the unified pipeline file"
        ;;
    esac
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

  # Audit code-verify-reconfigure-10 (2026-06): full canonical set
  # init.sh chmods (init.sh:1100). Pre-fix, verify-install.sh only
  # checked 8-10 scripts, leaving 14+ silently missing-or-broken in
  # initialized projects. The list below mirrors init.sh's chmod list
  # exactly. Hook scripts and host-driver scripts use a separate path
  # check below since they live in subdirectories.
  local scripts=(
    "scripts/validate.sh"
    "scripts/check-phase-gate.sh"
    "scripts/check-gate.sh"
    "scripts/check-updates.sh"
    "scripts/resume.sh"
    "scripts/intake-wizard.sh"
    "scripts/resolve-tools.sh"
    "scripts/upgrade-project.sh"
    "scripts/reconfigure-project.sh"
    "scripts/verify-install.sh"
    "scripts/test-gate.sh"
    "scripts/check-versions.sh"
    "scripts/session-version-check.sh"
    "scripts/session-test-gate-check.sh"
    "scripts/session-end-qdrant-reminder.sh"
    "scripts/session-mcp-gate.sh"
    "scripts/process-checklist.sh"
    "scripts/pre-commit-gate.sh"
    "scripts/track-tool-usage.sh"
    "scripts/pending-approval.sh"
    "scripts/lint-uat-scenarios.sh"
    "scripts/escalate-to-user.sh"
    "scripts/hooks/bypass-detector.sh"
    # BL-030 (post-PR #48): detector, installer, recorder hook, and
    # the fixture-envelope lint that gates the BL-029 hook schema.
    "scripts/detect-out-of-band-commits.sh"
    "scripts/install-filesystem-gates.sh"
    "scripts/hooks/record-claude-commit.sh"
    "scripts/lint-fixture-envelopes.sh"
  )

  # BL-030 (post-PR #48): sourced libraries — these are not executable
  # but their presence is load-bearing for enforcement_level reads,
  # block-message principle lookup, and the reconfigure transition path.
  local libs=(
    "scripts/lib/enforcement-level.sh"
    "scripts/lib/gate-principles.sh"
  )
  local lib_name
  for lib in "${libs[@]}"; do
    lib_name=$(basename "$lib" .sh)
    if [ -f "$lib" ]; then
      register_pass "$lib_name lib present"
    elif has_source && [ -f "$SOURCE_DIR/$lib" ]; then
      register_fixable "$lib_name lib missing" "fix_lib_copy_${lib_name}"
    else
      register_manual "$lib_name lib missing" "Copy from orchestrator $lib"
    fi
  done

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

# Audit code-verify-reconfigure-11 helper. Moved from inside check_hooks
# to file scope (verifier nit-1 follow-up): bash function definitions
# inside another function are hoisted to global scope on the first
# invocation of the parent, so the prior placement only saved style
# points and re-paid the function-registration cost per check_hooks
# call. File-scope placement matches the convention used by sibling
# helpers (run_with_timeout, _tool_install_head_allowed, etc.) and
# documents the helper as part of verify-install's hook contract
# rather than as a local detail of check_hooks.
#
# _check_hooks_hook_pair: validates one (event-jq-match, on-disk-path)
# pair and emits the appropriate register_pass / register_manual row.
# Arguments:
#   $1 = human label (e.g. "PreToolUse hook: pre-commit-gate.sh")
#   $2 = jq -e expression matching the hook entry in settings.json
#   $3 = on-disk script path (relative to project root)
#   $4 = manual remediation instruction string
_check_hooks_hook_pair() {
  local label="$1"
  local jq_match="$2"
  local script_path="$3"
  local remediation="$4"

  if ! jq -e "$jq_match" .claude/settings.json >/dev/null 2>&1; then
    register_manual "$label not registered" "$remediation"
    return
  fi

  # Registration present — now validate the on-disk script. Reuse the
  # check_scripts row when one is already emitted for $script_path
  # (e.g. pre-commit-gate.sh is in the canonical scripts array), but
  # we still want a hook-row signal so operators can correlate the
  # JSON ref with the runtime requirement.
  if [ ! -e "$script_path" ]; then
    register_manual "$label registered but on-disk script missing ($script_path)" \
      "Restore $script_path from the orchestrator source, then re-run verify-install"
    return
  fi
  if [ ! -x "$script_path" ]; then
    register_manual "$label registered but on-disk script not executable ($script_path)" \
      "Run: chmod +x $script_path"
    return
  fi

  register_pass "$label"
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

  # Audit code-verify-reconfigure-11 (2026-06): previously each hook
  # check verified ONLY the settings.json reference via `jq -e`. A
  # project with intact JSON references but a deleted or chmod-stripped
  # on-disk script would receive a green PASS — the hook then fails at
  # first PreToolUse invocation with "no such file" / "permission
  # denied". Baseline §5 invariant 11 establishes pre-commit-gate.sh as
  # a Claude Code PreToolUse hook; on-disk presence is the load-bearing
  # detail. The fix below requires BOTH the JSON registration AND the
  # on-disk script to be present + executable before a PASS is emitted.
  # The per-row helper lives at file scope as _check_hooks_hook_pair.

  # PreToolUse hook: pre-commit-gate.sh — also verify matcher is Bash.
  if jq -e '.hooks.PreToolUse[]? | .hooks[]? | select(.command | contains("pre-commit-gate.sh"))' .claude/settings.json >/dev/null 2>&1; then
    local matcher
    matcher=$(jq -r '[.hooks.PreToolUse[]? | select(.hooks[]? | .command | contains("pre-commit-gate.sh")) | .matcher // "none"] | first' .claude/settings.json 2>/dev/null || echo "unknown")
    if [ "$matcher" = "Bash" ]; then
      _check_hooks_hook_pair \
        "PreToolUse hook: pre-commit-gate.sh (matcher: Bash)" \
        '.hooks.PreToolUse[]? | .hooks[]? | select(.command | contains("pre-commit-gate.sh"))' \
        "scripts/pre-commit-gate.sh" \
        "Add pre-commit-gate.sh to .hooks.PreToolUse in .claude/settings.json (see init.sh for format)"
    else
      register_manual "PreToolUse hook matcher is '$matcher' (expected 'Bash')" \
        "Edit .claude/settings.json: set PreToolUse matcher to 'Bash' for the pre-commit-gate.sh entry"
    fi
  else
    register_manual "PreToolUse hook: pre-commit-gate.sh not registered" \
      "Add pre-commit-gate.sh to .hooks.PreToolUse in .claude/settings.json (see init.sh for format)"
  fi

  # PostToolUse hook: track-tool-usage.sh
  _check_hooks_hook_pair \
    "PostToolUse hook: track-tool-usage.sh" \
    '.hooks.PostToolUse[]? | .hooks[]? | select(.command | contains("track-tool-usage.sh"))' \
    "scripts/track-tool-usage.sh" \
    "Add track-tool-usage.sh to .hooks.PostToolUse in .claude/settings.json"

  # SessionStart hooks — version check + test gate are paired by design;
  # the row PASSes only when both are registered AND both on-disk
  # scripts are present + executable.
  if jq -e '.hooks.SessionStart[]? | .hooks[]? | select(.command | contains("session-version-check.sh") or contains("session-test-gate-check.sh"))' .claude/settings.json >/dev/null 2>&1; then
    local sess_missing=""
    for sess_script in scripts/session-version-check.sh scripts/session-test-gate-check.sh; do
      if [ ! -e "$sess_script" ]; then
        sess_missing="${sess_missing}${sess_script} (missing) "
      elif [ ! -x "$sess_script" ]; then
        sess_missing="${sess_missing}${sess_script} (not executable) "
      fi
    done
    if [ -z "$sess_missing" ]; then
      register_pass "SessionStart hooks: version check + test gate"
    else
      register_manual "SessionStart hooks registered but on-disk scripts incomplete: ${sess_missing}" \
        "Restore the listed scripts from the orchestrator source (and chmod +x), then re-run verify-install"
    fi
  else
    register_manual "SessionStart hooks incomplete" \
      "Add session-version-check.sh and session-test-gate-check.sh to .hooks.SessionStart in .claude/settings.json"
  fi

  # Stop hook: session-end-qdrant-reminder.sh
  _check_hooks_hook_pair \
    "Stop hook: session-end-qdrant-reminder.sh" \
    '.hooks.Stop[]? | .hooks[]? | select(.command | contains("session-end-qdrant-reminder.sh"))' \
    "scripts/session-end-qdrant-reminder.sh" \
    "Add session-end-qdrant-reminder.sh to .hooks.Stop in .claude/settings.json"

  # BL-029 hooks (PostToolUse + Stop): bypass-detector.sh. Both
  # registrations are required for the dual-event detection contract.
  _check_hooks_hook_pair \
    "PostToolUse hook: bypass-detector.sh" \
    '.hooks.PostToolUse[]? | .hooks[]? | select(.command | contains("bypass-detector.sh"))' \
    "scripts/hooks/bypass-detector.sh" \
    "Add hooks/bypass-detector.sh to .hooks.PostToolUse in .claude/settings.json"
  _check_hooks_hook_pair \
    "Stop hook: bypass-detector.sh" \
    '.hooks.Stop[]? | .hooks[]? | select(.command | contains("bypass-detector.sh"))' \
    "scripts/hooks/bypass-detector.sh" \
    "Add hooks/bypass-detector.sh to .hooks.Stop in .claude/settings.json"

  # BL-030 (post-PR #48): PostToolUse record-claude-commit ledger +
  # SessionStart out-of-band detector. Both must be registered for the
  # detection chain that powers the 'no/light/strict' enforcement levels.
  _check_hooks_hook_pair \
    "PostToolUse hook: record-claude-commit.sh" \
    '.hooks.PostToolUse[]? | .hooks[]? | select(.command | contains("record-claude-commit.sh"))' \
    "scripts/hooks/record-claude-commit.sh" \
    "Add hooks/record-claude-commit.sh to .hooks.PostToolUse in .claude/settings.json"
  _check_hooks_hook_pair \
    "SessionStart hook: detect-out-of-band-commits.sh" \
    '.hooks.SessionStart[]? | .hooks[]? | select(.command | contains("detect-out-of-band-commits.sh"))' \
    "scripts/detect-out-of-band-commits.sh" \
    "Add detect-out-of-band-commits.sh to .hooks.SessionStart in .claude/settings.json"
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
  # Audit code-verify-reconfigure-9 (2026-06): the prior 18-line stub
  # silently dropped the pending-approval-sentinel bullet, deployment
  # context, POC awareness, TDD/Build-Loop reminders, CDF reader hooks,
  # Bible reference, and (for organizational deployments) the Branch
  # Protection block. Agents reading the stub had no signal to honor
  # the sentinel, the Build-Loop step ordering, or governance gates —
  # silent behavioral degradation, masked as a successful auto-fix.
  #
  # Fix mirrors init.sh:generate_claude_md (init.sh:2230-2247): apply
  # the same sed substitution recipe to the canonical template at
  # templates/generated/claude-md.tmpl, then append the organizational
  # Branch Protection block when DEPLOYMENT=organizational.
  #
  # Refuse (return 1) when context is missing OR the canonical template
  # cannot be located — better to leave a register_fixable failure
  # visible than to write a placebo stub that masks the missing context.
  # The write is staged through a temp file + mv (atomic on same FS) so
  # we never half-write CLAUDE.md.
  if ! has_context; then return 1; fi

  local tmpl=""
  if has_source && [ -f "$SOURCE_DIR/templates/generated/claude-md.tmpl" ]; then
    tmpl="$SOURCE_DIR/templates/generated/claude-md.tmpl"
  elif [ -f "templates/generated/claude-md.tmpl" ]; then
    # Self-bootstrap: project might have its own copy of the template
    # (verify-install can run before $SOURCE_DIR is fully restored).
    tmpl="templates/generated/claude-md.tmpl"
  fi
  if [ -z "$tmpl" ]; then
    return 1
  fi

  # Resolve substitution values with safe defaults. PROJECT_NAME and
  # PROJECT_DESCRIPTION may be empty; init.sh defaults
  # TEST_INTERVAL to 5 if Section 11.5 is unset.
  local proj_name="${PROJECT_NAME:-unknown}"
  local proj_desc="${PROJECT_DESCRIPTION:-}"
  local test_interval="${TEST_INTERVAL:-5}"

  local staged
  staged=$(mktemp "${TMPDIR:-/tmp}/claude-md-stage.XXXXXX") || return 1
  # shellcheck disable=SC2064 — capture $staged at trap-set time so we
  # always clean up the partial file even on early failure.
  trap "rm -f '$staged'" RETURN

  if ! sed -e "s|__PROJECT_NAME__|$proj_name|g" \
           -e "s|__PROJECT_DESCRIPTION__|$proj_desc|g" \
           -e "s|__PLATFORM__|$PLATFORM|g" \
           -e "s|__TRACK__|$TRACK|g" \
           -e "s|__LANGUAGE__|$LANGUAGE|g" \
           -e "s|__TEST_INTERVAL__|$test_interval|g" \
           "$tmpl" > "$staged"; then
    return 1
  fi

  if [ "$DEPLOYMENT" = "organizational" ]; then
    cat >> "$staged" << 'COMPEOF'

### Branch Protection (Organizational Deployments)
Branch protection with required reviewers is recommended for organizational deployments and will be required when compliance modules are available. Until then, the Orchestrator creates and merges their own PRs with phase gate review at milestones. When branch protection is enabled, PRs require an independent reviewer before merge — this provides per-change code review that strengthens the governance audit trail.
COMPEOF
  fi

  # Atomic install. mv on same filesystem is rename(2), no half-write.
  mv "$staged" CLAUDE.md
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
  # Audit code-verify-reconfigure-8 (2026-06): full canonical schema
  # matching init.sh:1601-1616. Pre-fix wrote only {project,
  # framework_version, current_phase, gates}, silently dropping track,
  # deployment, poc_mode, and compliance_ready. Subsequent reads of
  # those fields by check-phase-gate, process-checklist, and the host
  # drivers fell through to defaults, masking misconfigured projects.
  #
  # Discover the four missing axes:
  #   - TRACK / DEPLOYMENT from load_context (CLAUDE.md / phase-state.json)
  #   - poc_mode from .claude/intake-progress.json (.answers.poc_mode)
  # If any required axis is missing, refuse and emit a register_manual
  # remediation pointing the operator at the canonical fix (re-run
  # init.sh or restore from backup), rather than writing a half-filled
  # file that masks the missing context.
  local track deployment poc_value
  track="${TRACK:-}"
  deployment="${DEPLOYMENT:-}"
  if [ -z "$track" ] || [ -z "$deployment" ]; then
    print_warn "fix_phase_state: TRACK/DEPLOYMENT not loaded from context — refusing to write half-filled phase-state.json"
    register_manual "phase-state.json cannot be auto-fixed without project context" \
      "Re-run scripts/intake-wizard.sh or restore .claude/phase-state.json from backup"
    return 1
  fi
  poc_value="null"
  if [ -f ".claude/intake-progress.json" ]; then
    local pm
    # Wave-3 fix-functions-stderr sweep + PR-#96 verifier follow-up:
    # surface jq diagnostics AND actually fail loud on malformed JSON.
    # A malformed intake-progress.json should fail loud (the operator
    # then re-runs intake or repairs the file), not silently default
    # to poc_mode=null and write a half-correct phase-state.json.
    # The previous `|| echo ""` masked jq's exit code (command-
    # substitution rc isn't propagated under `set -e`); the explicit
    # if/else here lets jq's stderr through AND refuses to write the
    # half-filled file, matching the contract the comment describes.
    if ! pm=$(jq -r '.answers.poc_mode // empty' .claude/intake-progress.json 2>&1); then
      print_warn "fix_phase_state: jq failed on .claude/intake-progress.json — refusing to write half-filled phase-state.json"
      register_manual "phase-state.json cannot be auto-fixed: .claude/intake-progress.json is malformed (jq: $pm)" \
        "Inspect/repair .claude/intake-progress.json, or re-run scripts/intake-wizard.sh"
      return 1
    fi
    case "$pm" in
      private_poc|sponsored_poc) poc_value="\"$pm\"" ;;
    esac
  fi
  mkdir -p .claude
  cat > .claude/phase-state.json << EOF
{
  "project": "${PROJECT_NAME:-unknown}",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$track",
  "deployment": "$deployment",
  "poc_mode": $poc_value,
  "compliance_ready": false,
  "gates": {
    "phase_0_to_1": null,
    "phase_1_to_2": null,
    "phase_2_to_3": null,
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

# Detect the project's CI host from .claude/manifest.json (.host),
# falling back to `git remote get-url origin` parsing (same case-switch
# used by scripts/upgrade-project.sh:253-281 for the BL-008 host-aware
# backfill). Returns one of: github | bitbucket | gitlab | other.
#
# specs-plans-uat-bugs-verify-install-uat-quality-3 — the pre-fix
# fix_ci_pipeline / fix_release_pipeline functions hardcoded both
# (a) the source layout (pre-BL-008 flat `templates/pipelines/ci/<lang>.yml`)
# and (b) the destination (`.github/workflows/{ci,release}.yml`), so they
# could never run successfully on bitbucket- or gitlab-hosted projects
# AND silently failed even on github after the BL-008 per-host subfolder
# migration. The detector below routes both source AND destination by
# host, restoring the auto-fix path for all three SCM hosts.
_detect_pipeline_host() {
  local h=""
  if [ -f .claude/manifest.json ] && command -v jq &>/dev/null; then
    h=$(jq -r '.host // empty' .claude/manifest.json 2>/dev/null)
  fi
  if [ -z "$h" ] || [ "$h" = "null" ]; then
    local url
    url=$(git remote get-url origin 2>/dev/null || echo "")
    case "$url" in
      *github.com*)    h="github" ;;
      *gitlab*)        h="gitlab" ;;
      *bitbucket.org*) h="bitbucket" ;;
      *)               h="other" ;;
    esac
  fi
  printf '%s' "$h"
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
  local host
  host=$(_detect_pipeline_host)
  local src="$SOURCE_DIR/templates/pipelines/ci/$host/$ci_template"
  if [ ! -f "$src" ]; then
    print_warn "fix_ci_pipeline: no CI template for host=$host language=$LANGUAGE at $src"
    return 1
  fi
  case "$host" in
    github)
      mkdir -p .github/workflows
      cp "$src" .github/workflows/ci.yml
      ;;
    bitbucket)
      cp "$src" bitbucket-pipelines.yml
      ;;
    gitlab)
      cp "$src" .gitlab-ci.yml
      ;;
    *)
      print_warn "fix_ci_pipeline: unsupported host '$host' — no canonical CI destination"
      return 1
      ;;
  esac
}

fix_release_pipeline() {
  if ! has_source || [ -z "$PLATFORM" ]; then return 1; fi
  local host
  host=$(_detect_pipeline_host)
  local src="$SOURCE_DIR/templates/pipelines/release/$host/${PLATFORM}.yml"
  if [ ! -f "$src" ]; then
    print_warn "fix_release_pipeline: no release template for host=$host platform=$PLATFORM at $src"
    return 1
  fi
  case "$host" in
    github)
      mkdir -p .github/workflows
      cp "$src" .github/workflows/release.yml
      ;;
    bitbucket|gitlab)
      # bitbucket and gitlab carry release steps inside the single
      # bitbucket-pipelines.yml / .gitlab-ci.yml respectively — there
      # is no separate release file at repo root. Surface a
      # non-blocking warning rather than silently writing to
      # .github/workflows/release.yml (the pre-fix bug).
      print_warn "fix_release_pipeline: host '$host' carries release steps in the unified pipeline file; manual integration required (template at $src)"
      return 1
      ;;
    *)
      print_warn "fix_release_pipeline: unsupported host '$host' — no canonical release destination"
      return 1
      ;;
  esac
}

fix_intake_suggestions() {
  if has_source; then
    mkdir -p templates/intake-suggestions
    # Wave-3 fix-functions-stderr sweep: surface cp diagnostics. A
    # missing source dir, permission error, or path glob mismatch
    # should fail loud so the operator can act (the prior silent
    # 2>/dev/null masked all three). Pre-test the glob via bash
    # nullglob so we don't invoke `cp` with zero source files
    # (which would emit a real "no such file" stderr under valid
    # empty-set conditions).
    local src_dir="$SOURCE_DIR/templates/intake-suggestions"
    local -a src_files=()
    if [ -d "$src_dir" ]; then
      shopt -s nullglob
      src_files=("$src_dir"/*.json)
      shopt -u nullglob
    fi
    if [ "${#src_files[@]}" -gt 0 ]; then
      cp "${src_files[@]}" templates/intake-suggestions/
    fi
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
    # Ensure the destination subdirectory exists (e.g., scripts/hooks/).
    local dest_dir
    dest_dir="scripts/$(dirname "$script_name")"
    [ "$dest_dir" != "scripts/." ] && mkdir -p "$dest_dir"
    cp "$SOURCE_DIR/scripts/$script_name" "scripts/$script_name"
    chmod +x "scripts/$script_name"
  else
    return 1
  fi
}

# Generate fix functions for each script
for _s in validate check-phase-gate check-gate check-updates resume intake-wizard resolve-tools upgrade-project reconfigure-project verify-install test-gate check-versions session-version-check session-test-gate-check session-end-qdrant-reminder session-mcp-gate process-checklist pre-commit-gate track-tool-usage pending-approval lint-uat-scenarios escalate-to-user detect-out-of-band-commits install-filesystem-gates lint-fixture-envelopes; do
  eval "fix_script_chmod_${_s}() { chmod +x 'scripts/${_s}.sh'; }"
  eval "fix_script_copy_${_s}() { fix_script '${_s}.sh'; }"
done
# BL-030: hooks live in a subdirectory; chmod + copy paths reflect that.
eval "fix_script_chmod_record-claude-commit() { chmod +x 'scripts/hooks/record-claude-commit.sh'; }"
eval "fix_script_copy_record-claude-commit()  { fix_script 'hooks/record-claude-commit.sh'; }"
# BL-030: sourced libs — no chmod, copy only.
fix_lib_copy_enforcement-level() { if has_source && [ -f "$SOURCE_DIR/scripts/lib/enforcement-level.sh" ]; then mkdir -p scripts/lib && cp "$SOURCE_DIR/scripts/lib/enforcement-level.sh" scripts/lib/; else return 1; fi; }
fix_lib_copy_gate-principles()   { if has_source && [ -f "$SOURCE_DIR/scripts/lib/gate-principles.sh" ];   then mkdir -p scripts/lib && cp "$SOURCE_DIR/scripts/lib/gate-principles.sh"   scripts/lib/; else return 1; fi; }
# Hooks live in a subdirectory; chmod + copy paths reflect that. The
# basename of scripts/hooks/bypass-detector.sh is `bypass-detector`, so
# the helper names must match (with hyphens, via eval).
eval "fix_script_chmod_bypass-detector() { chmod +x 'scripts/hooks/bypass-detector.sh'; }"
eval "fix_script_copy_bypass-detector()  { fix_script 'hooks/bypass-detector.sh'; }"

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
  # Drop `2>/dev/null` per the same rationale as fix_tool_install
  # (verifier follow-up to code-verify-reconfigure-14): clone failures
  # — auth prompt, network errors, DNS hijack — must surface so the
  # operator can act on them under --auto-fix rather than being told
  # a silenced non-zero return was a successful no-op.
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
  git clone -q --depth 1 https://github.com/kraulerson/claude-dev-framework.git "$FRAMEWORK_CLONE"
}

fix_framework_manifest() {
  # Drop `2>/dev/null` per the same rationale as fix_framework_clone:
  # init.sh failures (missing deps, malformed manifest) deserve a
  # visible diagnostic rather than a silenced non-zero return.
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
  if [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
    bash "$FRAMEWORK_CLONE/scripts/init.sh" || return 1
  else
    return 1
  fi
}

# Tool install fixes — dynamic, based on resolver output
RESOLVER_OUTPUT=""

# Audit code-verify-reconfigure-14 (2026-06):
#
# Prior implementation:  `eval "$install_cmd" 2>/dev/null` on a string
# sourced from templates/tool-matrix/*.json via scripts/resolve-tools.sh.
# Anyone with write access to the tool-matrix files (supply-chain,
# malicious fork, MITM of clone) could inject arbitrary shell, executed
# silently with the operator's privileges — and `2>/dev/null` masked
# the evidence. Baseline §5 invariant 10 ("defense in depth").
#
# PR #92 first cut:  argv-head allowlist + visible audit trail. The
# adversarial verifier (correctly) observed the allowlist was bypassable
# via shell-metacharacter chaining: any allowlisted head (`brew`,
# `sudo`, `curl`, ...) followed by `;`, `&&`, `||`, `|`, `` ` ``,
# `$(...)`, `<`, `>`, or a newline could chain arbitrary commands.
#
# Current cut (this fix):  TWO-LAYER dispatch.
#
#   Layer 1 — STRUCTURED PACKAGE-MANAGER DISPATCH (preferred path):
#     Recognize known `<pkg-mgr> install <pkg>` shapes (brew, sudo apt,
#     sudo dnf, sudo pacman, npm, pip/pip3, pipx, cargo, gem) and
#     dispatch via direct argv (`brew install -- "$pkg"`). The package
#     token is validated against a strict regex
#     (`^[A-Za-z0-9._@/+-]+$`) so an attacker cannot smuggle metachars
#     through the package position. NO `bash -c`, NO `eval` — the
#     metachar-chaining bypass is structurally impossible on this path.
#
#   Layer 2 — LEGACY STRING PATH (deprecated, metachar-rejecting):
#     For install_cmds that don't match a structured shape (e.g.
#     `VAR=$(curl ...) && curl ... | tar ...` or `source <(...)`), we
#     fall back to the prior allowlist with an ADDITIONAL post-allowlist
#     check: REFUSE any payload whose post-head portion contains shell
#     metacharacters known to enable command chaining: `;`, `|`, `` ` ``,
#     `$(`, `<`, `>`, newline, or the bare-word `&` (we still permit
#     `&&` and `||` because legitimate multi-stage installs use them
#     — but only when neither side contains a NEW chained head outside
#     the allowlist; in practice the metachar regex below catches the
#     dangerous cases and lets `brew install foo && brew services start
#     bar` through unchanged). Each fall-through emits a DEPRECATED
#     warning identifying the install_cmd so the tool-matrix maintainer
#     can migrate it to the structured shape. The legacy path can be
#     disabled entirely by exporting VERIFY_INSTALL_NO_LEGACY_DISPATCH=1.
#
# Net effect:
#   - The verifier's exact repro (`brew --version; touch /tmp/X`) is
#     now REFUSED on both layers: structured dispatch doesn't match the
#     shape, and the legacy path rejects the `;` metachar.
#   - Legitimate `brew install jq` / `pip3 install pre-commit` go
#     through Layer 1 with no `bash -c` at all.
#   - Real multi-stage legacy commands (e.g. install scripts using
#     `&&`) continue to work via Layer 2 unless the operator opts into
#     strict mode via VERIFY_INSTALL_NO_LEGACY_DISPATCH=1.
#
# Audit-trail invariants preserved:
#   (1) Drop `2>/dev/null` so install-time failures surface visibly.
#   (2) Echo the resolved command to stderr BEFORE execution.

# Legacy allowlist (Layer 2 only — Layer 1 hardcodes its own shapes).
_TOOL_INSTALL_ALLOWED_HEADS=(
  "brew" "sudo" "npm" "npx" "pip" "pip3" "pipx" "cargo" "gem"
  "dart" "dotnet" "go" "claude" "curl" "gpg" "keytool"
  "docker" "source" "echo"
)

_tool_install_head_allowed() {
  local head="$1"
  local allowed
  for allowed in "${_TOOL_INSTALL_ALLOWED_HEADS[@]}"; do
    if [ "$head" = "$allowed" ]; then return 0; fi
  done
  return 1
}

# Strict package-name validator. Matches the union of conservative
# package-naming conventions across Homebrew, Debian/RPM, npm, pip,
# cargo, gem, pipx — letters, digits, `.`, `_`, `@`, `/`, `+`, `-`.
# REJECTS whitespace, all shell metacharacters, and the empty string.
_tool_install_valid_package() {
  local pkg="$1"
  [ -n "$pkg" ] || return 1
  case "$pkg" in
    *[!A-Za-z0-9._@/+-]*) return 1 ;;
  esac
  return 0
}

# Layer 1 — structured package-manager dispatch.
# Inputs: $1 = full install_cmd string.
# Returns 0 (dispatched) on match, 1 (no match, fall through) otherwise.
# When a shape matches but the package fails validation, returns 2 —
# a HARD REFUSE that must NOT fall through to Layer 2 (the dangerous
# payload already proved hostile intent).
_tool_install_dispatch_structured() {
  local cmd="$1"
  # Tokenize via read -a (split on $IFS = space/tab/newline). This
  # rejects multi-line input by design — we want any newline in the
  # install_cmd to land us off the structured path (the legacy
  # metachar check then refuses it).
  local -a tok
  # shellcheck disable=SC2206 — intentional word splitting.
  tok=( $cmd )
  local n=${#tok[@]}

  # Recognized shapes:
  #   brew install <pkg>
  #   npm install -g <pkg>            (also: npm i -g <pkg>)
  #   pip  install <pkg>              (also: pip3, pipx)
  #   cargo install <pkg>
  #   gem install <pkg>
  #   sudo apt    install -y <pkg>    (also: apt-get)
  #   sudo dnf    install -y <pkg>
  #   sudo pacman -S --noconfirm <pkg>
  case "${tok[0]:-}" in
    brew)
      [ "$n" -eq 3 ] && [ "${tok[1]}" = "install" ] || return 1
      _tool_install_valid_package "${tok[2]}" || { _tool_install_refuse "$cmd" "structured brew shape with invalid package token"; return 2; }
      print_info "fix_tool_install [structured]: brew install ${tok[2]}" >&2
      brew install -- "${tok[2]}"
      return $?
      ;;
    npm)
      # `npm install -g <pkg>` or `npm i -g <pkg>`
      [ "$n" -eq 4 ] || return 1
      case "${tok[1]}" in install|i) ;; *) return 1 ;; esac
      [ "${tok[2]}" = "-g" ] || return 1
      _tool_install_valid_package "${tok[3]}" || { _tool_install_refuse "$cmd" "structured npm shape with invalid package token"; return 2; }
      print_info "fix_tool_install [structured]: npm ${tok[1]} -g ${tok[3]}" >&2
      npm "${tok[1]}" -g -- "${tok[3]}"
      return $?
      ;;
    pip|pip3|pipx|cargo|gem)
      [ "$n" -eq 3 ] && [ "${tok[1]}" = "install" ] || return 1
      _tool_install_valid_package "${tok[2]}" || { _tool_install_refuse "$cmd" "structured ${tok[0]} shape with invalid package token"; return 2; }
      print_info "fix_tool_install [structured]: ${tok[0]} install ${tok[2]}" >&2
      "${tok[0]}" install -- "${tok[2]}"
      return $?
      ;;
    sudo)
      # Recognize the three Linux package-manager shapes init.sh /
      # tool-matrix already emit. Anything else under `sudo` falls
      # through to Layer 2 (which still requires the allowlist + the
      # new metachar check).
      [ "$n" -ge 5 ] || return 1
      case "${tok[1]}" in
        apt|apt-get)
          [ "${tok[2]}" = "install" ] && [ "${tok[3]}" = "-y" ] || return 1
          _tool_install_valid_package "${tok[4]}" || { _tool_install_refuse "$cmd" "structured sudo apt shape with invalid package token"; return 2; }
          print_info "fix_tool_install [structured]: sudo ${tok[1]} install -y ${tok[4]}" >&2
          sudo "${tok[1]}" install -y -- "${tok[4]}"
          return $?
          ;;
        dnf)
          [ "${tok[2]}" = "install" ] && [ "${tok[3]}" = "-y" ] || return 1
          _tool_install_valid_package "${tok[4]}" || { _tool_install_refuse "$cmd" "structured sudo dnf shape with invalid package token"; return 2; }
          print_info "fix_tool_install [structured]: sudo dnf install -y ${tok[4]}" >&2
          sudo dnf install -y -- "${tok[4]}"
          return $?
          ;;
        pacman)
          # `sudo pacman -S --noconfirm <pkg>`
          [ "$n" -eq 5 ] && [ "${tok[2]}" = "-S" ] && [ "${tok[3]}" = "--noconfirm" ] || return 1
          _tool_install_valid_package "${tok[4]}" || { _tool_install_refuse "$cmd" "structured sudo pacman shape with invalid package token"; return 2; }
          print_info "fix_tool_install [structured]: sudo pacman -S --noconfirm ${tok[4]}" >&2
          sudo pacman -S --noconfirm -- "${tok[4]}"
          return $?
          ;;
      esac
      return 1
      ;;
  esac
  return 1
}

# Reject and log a refusal. Always echoes the offending command so the
# operator can see what the resolver supplied without re-reading the
# JSON.
_tool_install_refuse() {
  local cmd="$1" reason="$2"
  print_fail "fix_tool_install: REFUSED — $reason" >&2
  echo "  command: $cmd" >&2
}

# Layer 2 metachar check. Returns 0 (safe-ish, dispatch allowed) when
# the post-head portion contains no chaining metachars. Returns 1 when
# the payload looks like an injection attempt and must be refused.
# Permits `&&` and `||` (legitimate multi-stage installs) but rejects
# bare `&`, `;`, `|`, `` ` ``, `$(`, `<`, `>`, and any newline.
_tool_install_legacy_metachar_safe() {
  local payload="$1"
  # Reject embedded newlines and NULs outright.
  case "$payload" in
    *$'\n'*|*$'\r'*) return 1 ;;
  esac
  # Strip `&&` and `||` so the remaining bare-`&` / bare-`|` check
  # doesn't false-positive on legitimate multi-stage shapes.
  local stripped="${payload//&&/}"
  stripped="${stripped//||/}"
  case "$stripped" in
    *\;*|*\&*|*\|*|*\`*|*\<*|*\>*) return 1 ;;
    *'$('*) return 1 ;;
  esac
  return 0
}

fix_tool_install() {
  local index="$1"
  if [ -z "$RESOLVER_OUTPUT" ]; then return 1; fi
  local install_cmd
  install_cmd=$(echo "$RESOLVER_OUTPUT" | jq -r ".auto_install[$index].install_cmd")
  if [ -z "$install_cmd" ] || [ "$install_cmd" = "null" ]; then
    return 1
  fi

  # -------- Layer 1: structured dispatch --------
  _tool_install_dispatch_structured "$install_cmd"
  local rc=$?
  case "$rc" in
    0) return 0 ;;   # dispatched cleanly
    2) return 1 ;;   # hard refuse — do NOT fall through
    *) ;;            # rc=1 → no match; fall through to Layer 2
  esac

  # -------- Layer 2: deprecated string path --------
  if [ "${VERIFY_INSTALL_NO_LEGACY_DISPATCH:-0}" = "1" ]; then
    _tool_install_refuse "$install_cmd" "no structured shape matched and legacy path disabled (VERIFY_INSTALL_NO_LEGACY_DISPATCH=1)"
    return 1
  fi

  # Extract the first argv token (handles leading whitespace + tabs).
  # We deliberately parse with `awk` over the raw string so an attacker
  # cannot smuggle the head past validation with newlines or NULs.
  local head
  head=$(printf '%s' "$install_cmd" | awk '{print $1; exit}')

  # Some legitimate install commands begin with a variable assignment
  # whose right-hand side is a command substitution, e.g.:
  #   GITLEAKS_VERSION=$(curl -sSf https://api.github.com/...) && curl ...
  # The first whitespace-delimited token in that case is
  # `GITLEAKS_VERSION=$(curl`. We strip the `VAR=$(` prefix when
  # present so the allowlist check applies to the inner command
  # (`curl`). This is a narrow concession to the existing tool-matrix
  # shape; further hardening of the install_cmd schema is tracked
  # separately. A plain `VAR=value` (no command substitution) head is
  # also allowed — it is shell-syntactically inert until the next
  # command is reached. NOTE: even the VAR= shapes now go through the
  # metachar check below, so attacker-supplied `VAR=$(curl evil)` is
  # rejected (it contains `$(`).
  case "$head" in
    [A-Z_][A-Z0-9_]*=\$\(*)
      head="${head#*\$\(}"
      ;;
    [A-Z_][A-Z0-9_]*=*)
      # Plain VAR=value with no command substitution. The metachar
      # check still runs against the full payload below.
      head=""  # bypass the head-allowlist for the literal assignment
      ;;
  esac

  if [ -n "$head" ] && ! _tool_install_head_allowed "$head"; then
    _tool_install_refuse "$install_cmd" "disallowed leading token '$head'"
    return 1
  fi

  # Metachar gate — refuses the chained-injection bypass that motivated
  # this rewrite (e.g. `brew --version; touch /tmp/X`).
  if ! _tool_install_legacy_metachar_safe "$install_cmd"; then
    _tool_install_refuse "$install_cmd" "post-allowlist payload contains shell-chaining metacharacters (; | \` \$( < > newline)"
    return 1
  fi

  # Echo the resolved command before execution so the operator has a
  # visible audit trail even under --auto-fix.
  print_warn "fix_tool_install [legacy]: DEPRECATED string path executing: $install_cmd" >&2
  print_warn "  Migrate this entry in templates/tool-matrix/*.json to a structured" >&2
  print_warn "  '<pkg-mgr> install <pkg>' shape; legacy path will be removed in a" >&2
  print_warn "  future release. Set VERIFY_INSTALL_NO_LEGACY_DISPATCH=1 to enforce now." >&2

  # No `2>/dev/null` — install-time failures must surface. We still go
  # through `bash -c` rather than direct exec because legitimate
  # multi-stage commands (`&&`, `||`, parameter expansion) need a shell
  # — but the metachar gate above has already rejected the dangerous
  # chaining forms.
  bash -c -- "$install_cmd"
}

for _i in $(seq 0 19); do
  eval "fix_tool_install_${_i}() { fix_tool_install ${_i}; }"
done

fix_superpowers() {
  # Drop `2>/dev/null` per the same rationale as the other auto-fix
  # functions: a silenced `claude plugins add` failure cannot be
  # distinguished from success and leaves the project without the
  # superpowers plugin while reporting healthy.
  claude plugins add superpowers
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
    # Wave-3 raw-read sweep: prompt_yes_no centralizes the !-t 0 / CI
    # default-N policy. MODE=interactive is only entered when stdin is
    # a TTY (see MODE selection earlier in this script), so the
    # interactive default-Y branch is preserved; in degenerate cases
    # where MODE=interactive but stdin is non-TTY, prompt_yes_no
    # hard-returns N (defense-in-depth) and the caller falls back to
    # --auto-fix-or-manual messaging.
    if ! prompt_yes_no "$(echo -e "${BOLD}Auto-fix $fixable_count issues? [Y/n]${NC}")" "Y"; then
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
    # Audit code-verify-reconfigure-14 (bonus catch, 2026-06): the
    # prior `if $fix_func 2>/dev/null` silenced ALL stderr from fix
    # dispatch — including the audit-trail emitted by fix_tool_install
    # before/after each install, and the refusal reason when an
    # install_cmd fails the head allowlist. Pass stderr through so
    # operators can scroll back and review what ran on their
    # workstation. Fix functions that legitimately need to suppress
    # noisy stderr should do so locally (e.g. with a targeted
    # `2>/dev/null` on a single command), not by the dispatcher.
    if $fix_func; then
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

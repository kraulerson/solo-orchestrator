#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — PreToolUse hook for commit gating
# Blocks git commit and gh pr create when process checklist is incomplete.
# Registered as a PreToolUse hook on Bash tool calls.
#
# Input: Claude Code passes tool input JSON on stdin
# Output:
#   - No output = allow
#   - JSON with permissionDecision: "deny" = block

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read the tool input from stdin
INPUT=$(cat)

# Extract the bash command from the JSON input
# Claude Code passes: {"command": "git commit -m '...'", ...}
COMMAND=$(echo "$INPUT" | jq -r '.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Block agent-initiated SOIF_FORCE_STEP bypass (match assignment, not diagnostic reads)
if echo "$COMMAND" | grep -qE 'SOIF_FORCE_STEP='; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "SOIF_FORCE_STEP bypasses artifact checks and requires Orchestrator authorization. The Orchestrator must run this command directly in their terminal."}}
HOOKEOF
  exit 0
fi

# Block agent-initiated enforcement override variables
if echo "$COMMAND" | grep -qE 'SOIF_PHASE_GATES=|SOIF_STRICT_CHANGELOG=|SOIF_STRICT_SESSION='; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "SOIF_PHASE_GATES modifies enforcement level and requires Orchestrator authorization. The Orchestrator must set this in their environment directly."}}
HOOKEOF
  exit 0
fi

# Block agent-initiated process resets
if echo "$COMMAND" | grep -qE 'process-checklist\.sh.*--reset'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Process reset requires Orchestrator authorization. Ask the Orchestrator to run this command directly in their terminal."}}
HOOKEOF
  exit 0
fi

# Block --no-verify flag on git commit (bypasses security hooks)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--no-verify'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "The --no-verify flag bypasses security hooks (gitleaks, Semgrep). Remove --no-verify and commit normally."}}
HOOKEOF
  exit 0
fi

# Warn on git commit --amend (rewrites commit history, bypasses build loop for amended content)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--amend'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "WARNING: git commit --amend rewrites the previous commit. Ensure the amended content has been through the full Build Loop. If this amend adds new source code, consider a new commit instead."}}
HOOKEOF
  exit 0
fi

# Block git push --force (overwrites branch history)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b.*(-f|--force)'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Force push overwrites branch history and can destroy audit evidence. Use normal push. If you need to rewrite history, ask the Orchestrator."}}
HOOKEOF
  exit 0
fi

# Only gate git commit and gh pr create for process checklist enforcement
IS_COMMIT=false
IS_PR=false
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b'; then
  IS_COMMIT=true
elif echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bcreate\b'; then
  IS_PR=true
fi

if [ "$IS_COMMIT" = false ] && [ "$IS_PR" = false ]; then
  exit 0
fi

# Run process checklist check
CHECKLIST_OUTPUT=""
CHECKLIST_EXIT=0
CHECKLIST_OUTPUT=$("$SCRIPT_DIR/process-checklist.sh" --check-commit-ready 2>&1) || CHECKLIST_EXIT=$?

if [ "$CHECKLIST_EXIT" -ne 0 ]; then
  # Block the commit
  REASON=$(echo "$CHECKLIST_OUTPUT" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$REASON"}}
HOOKEOF
  exit 0
fi

# For PR creation: additional checks
if [ "$IS_PR" = true ]; then
  # Check no UAT session in progress
  PROCESS_STATE=".claude/process-state.json"
  if [ -f "$PROCESS_STATE" ] && command -v jq &>/dev/null; then
    UAT_STARTED=$(jq -r '.uat_session.started_at // empty' "$PROCESS_STATE" 2>/dev/null)
    if [ -n "$UAT_STARTED" ]; then
      UAT_STEPS_DONE=$(jq -r '.uat_session.steps_completed | length' "$PROCESS_STATE" 2>/dev/null)
      if [ "$UAT_STEPS_DONE" -lt 9 ]; then
        cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "UAT session in progress with incomplete steps ($UAT_STEPS_DONE/9). Complete all UAT steps before creating a PR."}}
HOOKEOF
        exit 0
      fi
    fi

    # Check build_loop is at step 0 or fully complete
    BUILD_FEATURE=$(jq -r '.build_loop.feature // empty' "$PROCESS_STATE" 2>/dev/null)
    if [ -n "$BUILD_FEATURE" ]; then
      BUILD_STEPS_DONE=$(jq -r '.build_loop.steps_completed | length' "$PROCESS_STATE" 2>/dev/null)
      if [ "$BUILD_STEPS_DONE" -gt 0 ] && [ "$BUILD_STEPS_DONE" -lt 6 ]; then
        cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Feature '$BUILD_FEATURE' has incomplete Build Loop ($BUILD_STEPS_DONE/6 steps). Complete the feature or reset before creating a PR."}}
HOOKEOF
        exit 0
      fi
    fi
  fi
fi

# Process checklist passed. Now check tool usage (warnings only, not blocking).
TOOL_USAGE=".claude/tool-usage.json"
PHASE_STATE=".claude/phase-state.json"
WARNINGS=""

if [ "$IS_COMMIT" = true ] && [ -f "$TOOL_USAGE" ] && [ -f "$PHASE_STATE" ] && command -v jq &>/dev/null; then
  CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null)

  if [ "$CURRENT_PHASE" = "2" ]; then
    # Check if this is a source commit (reuse staged file check)
    HAS_SOURCE=false
    STAGED=$(git diff --cached --name-only 2>/dev/null || true)
    if echo "$STAGED" | grep -qE '\.(py|ts|tsx|js|jsx|rs|go|cs|kt|java|dart|swift|c|cpp|h)$'; then
      HAS_SOURCE=true
    elif echo "$STAGED" | grep -qE '^(src|lib|app|pkg|internal|cmd)/'; then
      HAS_SOURCE=true
    fi

    if [ "$HAS_SOURCE" = true ]; then
      # Context7 check
      COMMITS_SINCE_CTX7=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
      if [ "$COMMITS_SINCE_CTX7" -ge 2 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}Context7 has not been consulted for library documentation in the last $COMMITS_SINCE_CTX7 commits. Consider checking docs for libraries used in this change. "
      fi

      # Qdrant-find check (first commit of session only)
      QDRANT_FIND=$(jq -r '.qdrant_find_called // false' "$TOOL_USAGE" 2>/dev/null)
      if [ "$QDRANT_FIND" = "false" ]; then
        WARNINGS="${WARNINGS}No prior context retrieved from Qdrant this session. Consider checking for relevant architecture decisions and patterns. "
      fi
    fi
  fi
fi

if [ -n "$WARNINGS" ]; then
  # Output warnings as additional context (not blocking)
  ESCAPED_WARNINGS=$(echo "$WARNINGS" | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "TOOL USAGE WARNINGS: $ESCAPED_WARNINGS"}}
HOOKEOF
fi

# If we reach here with no output, the commit is allowed silently
exit 0

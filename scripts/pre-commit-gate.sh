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

# Extract the bash command from the JSON input.
# Claude Code passes (verified against /anthropics/claude-code docs 2026-04-25):
#   {"session_id": "...", "tool_name": "Bash", "tool_input": {"command": "..."}, ...}
# Fall back to the legacy ".command" path so older test fixtures and any
# manual JSON invocations continue to work.
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null)

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

# --- Early guard (spec 2026-04-21 host-aware repo gate) ---
# Block git commit if no remote is configured. Solo Orchestrator requires a
# created-and-protected remote from init onward; commits without a remote
# indicate either a pre-fix project or drift that needs remediation.
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && ! echo "$COMMAND" | grep -qE 'git.*remote'; then
  # Only check if we're in a git repo with no remote
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if ! git remote get-url origin >/dev/null 2>&1; then
      cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "pre-commit gate: no git remote configured. Solo Orchestrator requires a created-and-protected remote from project init onward. Run: scripts/check-gate.sh --backfill-host (if manifest missing host), then scripts/check-gate.sh --repair (to recreate remote and protection). See docs/builders-guide.md § Repository Setup."}}
HOOKEOF
      exit 0
    fi
  fi
fi

# Block --no-verify flag on git commit (bypasses security hooks)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--no-verify'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "The --no-verify flag bypasses security hooks (gitleaks, Semgrep). Remove --no-verify and commit normally."}}
HOOKEOF
  exit 0
fi

# --- BL-015: pending-approval sentinel reader ---
# Blocks git commit and gh pr create when .claude/pending-approval.json exists.
# Runs after security gates (SOIF_*, no-remote, --no-verify) but before
# workflow gates (--amend, bl006_check, --check-commit-ready) so pending
# approval preempts workflow concerns without hiding security violations.
# See docs/builders-guide.md "Structured Decision Points" for the contract.

build_pa_rich_reason() {
  local sentinel="$1" action_label="$2"
  local question options recommendation offered_at
  question=$(jq -er '.question' "$sentinel") || return 1
  options=$(jq -er '.options | map("  " + .) | join("\n")' "$sentinel") || return 1
  recommendation=$(jq -er '.recommendation' "$sentinel") || return 1
  offered_at=$(jq -er '.offered_at' "$sentinel") || return 1
  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

Pending question: "$question"
Options:
$options
Recommendation: $recommendation
Offered at: $offered_at

Wait for the user to pick one, then:
  scripts/pending-approval.sh --resolve
EOF
}

build_pa_malformed_reason() {
  local sentinel="$1" action_label="$2"
  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

The sentinel file $sentinel exists but is malformed.
Treated as "in flight" per the CDF 4.2.3 contract.

If this is a stale file from a crashed session, remove it manually:
  rm $sentinel
EOF
}

pa_check() {
  # Only applies to git commit or gh pr create. Other commands fall through.
  local is_commit=false is_pr=false
  echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && is_commit=true
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bcreate\b' && is_pr=true
  [ "$is_commit" = false ] && [ "$is_pr" = false ] && return 0

  local sentinel=".claude/pending-approval.json"
  [ -f "$sentinel" ] || return 0

  local action_label="commit"
  [ "$is_pr" = true ] && action_label="PR creation"

  local reason
  if reason=$(build_pa_rich_reason "$sentinel" "$action_label" 2>/dev/null); then
    :
  else
    reason=$(build_pa_malformed_reason "$sentinel" "$action_label")
  fi

  local escaped
  escaped=$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$escaped"}}
HOOKEOF
  exit 0
}

pa_check
# --- end BL-015 block ---

# Warn on git commit --amend (rewrites commit history, bypasses build loop for amended content)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--amend'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "WARNING: git commit --amend rewrites the previous commit. Ensure the amended content has been through the full Build Loop. If this amend adds new source code, consider a new commit instead."}}
HOOKEOF
  exit 0
fi

# --- BL-006: commit-message-triggered Build Loop enforcement ---
# Scope: only fires on `git commit` authoring events (not merges, reverts,
# cherry-picks, squash-merges, or editor-case commits). Extracts the message
# from -m "..." / heredoc / -F file and delegates the policy decision to
# process-checklist.sh --check-commit-message.

bl006_check() {
  # Only apply to `git commit` subcommands.
  echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || return 0

  # Derivative-commit filters: pass through.
  # --amend is already handled above (warns, exits). Belt-and-braces.
  echo "$COMMAND" | grep -qE '\-\-amend\b' && return 0
  # Merge in progress.
  [ -f .git/MERGE_HEAD ] && return 0
  # Other derivative commands that might embed feat: in their message.
  echo "$COMMAND" | grep -qE '\bgit\b.*\b(merge|revert|cherry-pick)\b' && return 0
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bmerge\b.*\-\-squash' && return 0

  # Extract the message subject.
  local msg=""

  # 1. Heredoc: look for -m "$(cat <<EOF or -m "$(cat <<'EOF'
  if echo "$COMMAND" | grep -qE "<<'?EOF'?"; then
    # awk: after the <<EOF or <<'EOF' marker, the first non-empty content line
    # before a standalone EOF is the subject.
    msg=$(printf '%s\n' "$COMMAND" | awk '
      /<<'"'"'?EOF'"'"'?/ { flag=1; next }
      /^EOF$/ { flag=0 }
      flag && !printed && NF>0 { print; printed=1; exit }
    ')
  fi

  # 2. Inline -m "..." (double or single quotes). Only if heredoc didn't match.
  if [ -z "$msg" ]; then
    # Try double-quoted first, then single-quoted. Capture up to the closing
    # quote. This is best-effort; exotic escaping falls through.
    msg=$(printf '%s' "$COMMAND" | sed -nE 's/.*-m "([^"]*)".*/\1/p' | head -n 1)
    if [ -z "$msg" ]; then
      msg=$(printf '%s' "$COMMAND" | sed -nE "s/.*-m '([^']*)'.*/\\1/p" | head -n 1)
    fi
    # Split on real newlines; take first line.
    msg=$(printf '%s\n' "$msg" | head -n 1)
  fi

  # 3. -F <file>. Only if no -m at all was seen.
  if [ -z "$msg" ] && echo "$COMMAND" | grep -qE '\-F[[:space:]]+[^ ]+'; then
    local f
    f=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^ ]+).*/\1/p' | head -n 1)
    if [ -n "$f" ] && [ -r "$f" ]; then
      msg=$(head -n 1 "$f")
    fi
  fi

  # Empty: fall through (editor case or parse miss).
  [ -z "$msg" ] && return 0

  # Delegate to the subcommand. Capture both streams (print_fail uses stdout;
  # echo-to-stderr is used for remediation lines).
  local policy_err policy_exit=0
  policy_err=$("$SCRIPT_DIR/process-checklist.sh" --check-commit-message "$msg" 2>&1) || policy_exit=$?

  if [ "$policy_exit" -ne 0 ]; then
    local reason
    reason=$(echo "$policy_err" | tr '\n' ' ' | sed 's/"/\\"/g')
    cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$reason"}}
HOOKEOF
    exit 0
  fi

  return 0
}

bl006_check
# --- end BL-006 block ---

# Block git push --force (overwrites branch history)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b.*(-f|--force)'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Force push overwrites branch history and can destroy audit evidence. Use normal push. If you need to rewrite history, ask the Orchestrator."}}
HOOKEOF
  exit 0
fi

# Block gh repo create --push (bypasses branch-safety by pushing to a new remote without gate checks)
if echo "$COMMAND" | grep -qE '\bgh\b.*\brepo\b.*\bcreate\b.*--push'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "gh repo create --push bypasses branch safety checks by pushing directly to a new remote. Create the repo without --push, then use git push after process checks pass."}}
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

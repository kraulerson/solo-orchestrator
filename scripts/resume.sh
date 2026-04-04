#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Session Resume Prompt Generator
# Reads project state and outputs a resume prompt to paste into Claude Code.
#
# Usage: bash scripts/resume.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

echo -e "${BOLD}Generating session resume prompt...${NC}"
echo ""

# --- Gather state ---

# Current phase
PHASE="unknown"
if [ -f ".claude/phase-state.json" ]; then
  # current_phase can be a bare integer (0) or quoted string ("0")
  PHASE=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' .claude/phase-state.json 2>/dev/null | grep -o '[0-9][0-9]*' || echo "unknown")
  [ -z "$PHASE" ] && PHASE="unknown"
fi

# Last 3 git log entries
RECENT_COMMITS="(no commits)"
if command -v git &>/dev/null && [ -d ".git" ]; then
  RECENT_COMMITS=$(git log --oneline -3 2>/dev/null || echo "(no commits)")
fi

# Features built and remaining from CLAUDE.md
FEATURES_BUILT="(not found in CLAUDE.md)"
FEATURES_REMAINING="(not found in CLAUDE.md)"
KNOWN_ISSUES="(not found in CLAUDE.md)"
LAST_SESSION="(not found in CLAUDE.md)"

if [ -f "CLAUDE.md" ]; then
  # Extract "Features built:" line
  line=$(grep -i "features built" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    FEATURES_BUILT=$(echo "$line" | sed 's/.*[Ff]eatures built[[:space:]]*:[[:space:]]*//')
  fi

  # Extract "Features remaining:" line
  line=$(grep -i "features remaining" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    FEATURES_REMAINING=$(echo "$line" | sed 's/.*[Ff]eatures remaining[[:space:]]*:[[:space:]]*//')
  fi

  # Extract "Known issues:" line
  line=$(grep -i "known issues" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    KNOWN_ISSUES=$(echo "$line" | sed 's/.*[Kk]nown issues[[:space:]]*:[[:space:]]*//')
  fi

  # Extract "Last session summary:" line
  line=$(grep -i "last session" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    LAST_SESSION=$(echo "$line" | sed 's/.*[Ll]ast session[[:space:]]*\(summary[[:space:]]*\)\{0,1\}:[[:space:]]*//')
  fi
fi

# --- Output the prompt ---

# Version check summary
VERSION_STATUS="(run scripts/check-versions.sh for details)"
if [ -x "scripts/check-versions.sh" ]; then
  version_output=$(bash scripts/check-versions.sh 2>&1 </dev/null) || true
  below_min=$(echo "$version_output" | grep -c "BELOW MINIMUM" || true)
  below_min=${below_min:-0}
  updates=$(echo "$version_output" | grep -c "available" || true)
  updates=${updates:-0}
  if [ "$below_min" -gt 0 ]; then
    VERSION_STATUS="⚠ $below_min tool(s) below minimum version — run scripts/check-versions.sh"
  elif [ "$updates" -gt 0 ]; then
    VERSION_STATUS="⬆ $updates update(s) available — run scripts/check-versions.sh"
  else
    VERSION_STATUS="✓ All tools up to date"
  fi
fi

echo -e "${CYAN}--- Copy everything below this line into Claude Code ---${NC}"
echo ""
cat <<PROMPT
We are resuming work on this project. Here is the current state:

**Phase:** $PHASE
**Features built:** $FEATURES_BUILT
**Features remaining:** $FEATURES_REMAINING
**Known issues:** $KNOWN_ISSUES
**Last session:** $LAST_SESSION

**Recent commits:**
$RECENT_COMMITS

**Tool versions:** $VERSION_STATUS

Read CLAUDE.md for full project context. Continue from where we left off. If CLAUDE.md's "Current State" section is stale or incomplete, ask me to clarify before proceeding.
PROMPT

echo ""
echo -e "${CYAN}--- End of resume prompt ---${NC}"

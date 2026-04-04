#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Session Resume Prompt Generator
# Reads project state and outputs a resume prompt to paste into Claude Code.
#
# Usage: bash scripts/resume.sh

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  BOLD=''; CYAN=''; NC=''
fi

echo -e "${BOLD}Generating session resume prompt...${NC}"
echo ""

# --- Gather state ---

# Current phase
PHASE="unknown"
if [ -f ".claude/phase-state.json" ]; then
  PHASE=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/phase-state.json 2>/dev/null | sed 's/.*"current_phase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "unknown")
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
    LAST_SESSION=$(echo "$line" | sed 's/.*[Ll]ast session[[:space:]]*summary[[:space:]]*:[[:space:]]*//')
  fi
fi

# --- Output the prompt ---

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

Read CLAUDE.md for full project context. Continue from where we left off. If CLAUDE.md's "Current State" section is stale or incomplete, ask me to clarify before proceeding.
PROMPT

echo ""
echo -e "${CYAN}--- End of resume prompt ---${NC}"

#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Session Resume Prompt Generator
# Reads project state and outputs a resume prompt to paste into Claude Code.
#
# Usage: bash scripts/resume.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# BL-046: uses only color vars (BOLD/CYAN/NC) — source core subset.
source "$SCRIPT_DIR/lib/helpers-core.sh"

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

# --- BL-202: state-aware first-message branches ---------------------------
# This script is the SINGLE generator of "what do I paste into Claude Code";
# every wizard/init print points here. Three states, checked in order:
#   1. intake unfinished  -> the intake first-message
#   2. intake done, Phase 0 never started -> the project's own Section 13
#      (Agent Initialization Prompt) verbatim
#   3. anything else -> the classic resume prompt below
# Detection matches scripts/session-intake-check.sh (blank-cell predicate).
if [ -f "PROJECT_INTAKE.md" ] && [ "$PHASE" != "unknown" ] && [ "${PHASE:-1}" -eq 0 ] 2>/dev/null; then
  bl202_blanks=$(grep -cE '\| *\|$|\| *$' PROJECT_INTAKE.md 2>/dev/null || true)
  case "$bl202_blanks" in ''|*[!0-9]*) bl202_blanks=0 ;; esac
  if [ "$bl202_blanks" -gt 20 ]; then
    echo -e "${CYAN}--- Copy everything below this line into Claude Code ---${NC}"
    echo ""
    if [ -f "INTAKE_GUIDED_PROMPT.md" ]; then
      echo "Read INTAKE_GUIDED_PROMPT.md and follow it."
    else
      echo "Help me finish this project's intake: read PROJECT_INTAKE.md and walk me"
      echo "through the unfilled sections, writing my answers into the file as we go."
    fi
    echo ""
    echo -e "${CYAN}--- End (a blank Claude Code screen means it is ready and waiting, not stuck) ---${NC}"
    exit 0
  fi
  if [ ! -f "PRODUCT_MANIFESTO.md" ]; then
    # Extract §13's fenced prompt from the PROJECT's intake (not the template).
    bl202_s13=$(awk '/^## 13\./{f=1; next} f && /^## /{exit} f && /^```/{c = !c; next} f && c' PROJECT_INTAKE.md 2>/dev/null)
    echo -e "${CYAN}--- Copy everything below this line into Claude Code ---${NC}"
    echo ""
    if [ -n "$bl202_s13" ]; then
      printf '%s\n' "$bl202_s13"
    else
      echo "Read PROJECT_INTAKE.md — Section 13 is your initialization prompt — and"
      echo "begin Phase 0 from it."
    fi
    echo ""
    echo -e "${CYAN}--- End (a blank Claude Code screen means it is ready and waiting, not stuck) ---${NC}"
    exit 0
  fi
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
  case "$below_min" in ''|*[!0-9]*) below_min=0 ;; esac
  updates=$(echo "$version_output" | grep -c "available" || true)
  case "$updates" in ''|*[!0-9]*) updates=0 ;; esac
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

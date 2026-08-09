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
  # BL-202-INTAKE-PREDICATE (SYNC SIBLINGS: scripts/validate.sh, scripts/session-intake-check.sh, scripts/resume.sh) — count only truly-blank cells: '\| *\|$'. The old '|\| *$' alternative matched EVERY table row (constant 258 on real intakes — review R-BL202-1).
  bl202_blanks=$(grep -cE '\| *\|$' PROJECT_INTAKE.md 2>/dev/null || true)
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

# ── DELTA-RESUME-BEGIN ──────────────────────────────────────────────────────
# THE FOURTH BRANCH (design 2026-08-02-delta-track-v1 §10.5), ahead of the
# classic one.
#
# D8's point, and the reason this is the branch that matters: today's post-1.0
# workflow instructions are RETRIEVAL surfaces — the guide and the ledger
# headers — correct, and unread at the moment of need. A greeting changes WHEN
# the operator learns the rule, from after they act to before. §10.5 marks its
# tier honestly: ADVISORY. A greeting cannot make anyone do anything.
#
# Two sub-cases, and no others:
#   current_phase == 4 and something open  -> resume THAT piece of work: its
#     id, class, confirmed attributes, and what is still outstanding.
#   current_phase == 4 and nothing open    -> the post-1.0 greeting: how to
#     state a need in plain words, any overdue maintenance, any write-up still
#     owed, and how many candidates the manifesto's § 6 is holding.
#
# WHY IT GOES THROUGH THE SEAM AND NAMES NO MODULE FILE. This is a CORE script,
# and the post-1.0 module is severable: core may never reference it
# (scripts/lint-delta-boundary.sh, §3.3 clause 2). So this block reads the
# record by delegating to scripts/process-checklist.sh — a core file, and the
# ONE declared seam — exactly as scripts/validate.sh, scripts/upgrade-project.sh
# and scripts/check-maintenance.sh already do. It names the seam's action FLAG
# and never a module path, so tier T1 stays clean and the seam allowlist stays
# at cardinality one.
#
# AND IT FAILS SOFT, which is what keeps the module severable rather than
# merely separate. With the module absent the seam answers non-zero, the
# document is empty, and control falls through to the classic prompt below —
# no crash, no half-greeting. That is the same fail-soft contract the other
# four core consumers carry, measured by the severability suite's V0.
#
# The whole block is contiguous between these two markers so the sever is a
# single-block revert, like the seam's own fence.
if [ "$PHASE" = "4" ] && command -v jq >/dev/null 2>&1; then          # DELTA-RESUME-PHASE4
  pmv_seam="$SCRIPT_DIR/process-checklist.sh"
  pmv_doc=""
  if [ -f "$pmv_seam" ]; then
    pmv_doc="$( bash "$pmv_seam" --delta-state-read </dev/null 2>/dev/null )" || pmv_doc=""   # lint-delta-boundary: allow core->core delegation to the ONE declared seam — this names the seam's action FLAG, never a module path (T1 is clean) and the seam allowlist stays at cardinality 1 (§3.1/§3.3)
  fi
  if [ -n "$pmv_doc" ] && printf '%s\n' "$pmv_doc" | jq -e . >/dev/null 2>&1; then
    # Outstanding write-ups, and the candidate count, are the two things both
    # sub-cases want.
    pmv_owed=$(printf '%s\n' "$pmv_doc" | jq -r '
      [ .hotfix_retros[]? | select(type == "object") | select(.closed_at == null) ]
      | map("  " + (.id // "unknown") + " — due " + (.due_by // "an unrecorded date"))
      | join("\n")' 2>/dev/null || echo "")
    # The § 6 read is the SAME predicate the post-1.0 status surface uses, and
    # the two are pinned to agree by test-delta-wp8-intake.sh's BR1/R3 pair
    # (three items listed there, "3" reported here, from one manifesto). It is
    # spelled out again rather than shared because a core script may not source
    # a module lib — that is the cost of the boundary, named rather than hidden.
    pmv_cands=0
    if [ -f "PRODUCT_MANIFESTO.md" ]; then
      pmv_cands=$(awk '/^##[ \t]*6[. ]/ { insec = 1; next }
/^##.*Post-MVP Backlog/ { insec = 1; next }
insec && /^##/ { insec = 0 }
insec && /^[-*+][ \t]+/ { print }' PRODUCT_MANIFESTO.md 2>/dev/null | grep -c '' || true)
      case "$pmv_cands" in ''|*[!0-9]*) pmv_cands=0 ;; esac
    fi
    pmv_maint=""
    if [ -f "$SCRIPT_DIR/check-maintenance.sh" ]; then
      pmv_mrc=0
      bash "$SCRIPT_DIR/check-maintenance.sh" </dev/null >/dev/null 2>&1 || pmv_mrc=$?
      case "$pmv_mrc" in
        1) pmv_maint="Routine maintenance is OVERDUE — run scripts/check-maintenance.sh to see which window." ;;
        2) pmv_maint="A maintenance window could not be measured — run scripts/check-maintenance.sh; it will say which signal it could not read." ;;
      esac
    fi

    pmv_open=$(printf '%s\n' "$pmv_doc" | jq -r '.active_delta.id // ""' 2>/dev/null || echo "")
    if [ -n "$pmv_open" ]; then
      echo -e "${CYAN}--- Copy everything below this line into Claude Code ---${NC}"
      echo ""
      printf '%s\n' "$pmv_doc" | jq -r '
        .active_delta as $d
        | "We are resuming a piece of post-release work on this product.",
          "",
          "**In progress:** \($d.id) — \($d.slug // "no description recorded")",
          "**Kind of change:** \($d.class // "unknown")",
          "**Agreed at the start:** risk \($d.attributes.risk // "unknown"), size \($d.attributes.level // "unknown")"
            + (if ($d.attributes.severity // null) == null then "" else ", severity \($d.attributes.severity)" end),
          "**Written-up plan:** " + ($d.brief // "none — this kind of change does not need one"),
          "**Still to do before it can ship:** "
            + ((( ($d.gates_required // []) - ($d.gates_completed // []) ) | join(", "))
               | if . == "" then "nothing — it is ready to close" else . end),
          "**Already done:** "
            + ((($d.gates_completed // []) | join(", ")) | if . == "" then "nothing yet" else . end)'
      if [ -n "$pmv_owed" ]; then
        echo ""
        echo "**Write-ups still owed (nothing can be released until these are filed):**"
        printf '%s\n' "$pmv_owed"
      fi
      if [ -n "$pmv_maint" ]; then echo ""; echo "**Maintenance:** $pmv_maint"; fi
      echo ""
      echo "Read CLAUDE.md for full product context, then pick this up where we left off. The plan file above is the review at the end — if what we build stops matching it, say so rather than quietly changing the plan."
      echo ""
      echo -e "${CYAN}--- End (a blank Claude Code screen means it is ready and waiting, not stuck) ---${NC}"
      exit 0
    fi

    echo -e "${CYAN}--- Copy everything below this line into Claude Code ---${NC}"
    echo ""
    echo "This product has shipped. Nothing is in progress right now."
    echo ""
    echo "Everything from here on is one piece of work at a time — a new feature, a fix, an urgent fix, or a security patch. I do not need to know which; I will tell you in plain words what I need and you work out the rest with me."
    echo ""
    if [ -n "$pmv_owed" ]; then
      echo "**Write-ups still owed (nothing can be released until these are filed):**"
      printf '%s\n' "$pmv_owed"
      echo ""
    fi
    if [ -n "$pmv_maint" ]; then
      echo "**Maintenance:** $pmv_maint"
      echo ""
    fi
    if [ "$pmv_cands" -gt 0 ]; then
      echo "**Post-MVP Backlog:** PRODUCT_MANIFESTO.md section 6 is holding $pmv_cands candidate(s). They are candidates, not commitments — nothing there is scheduled, and nothing moves out of that document without me saying so."
      echo ""
    fi
    echo "Read CLAUDE.md for full product context and for how post-release work is run here. Then ask me what I need."
    echo ""
    echo -e "${CYAN}--- End (a blank Claude Code screen means it is ready and waiting, not stuck) ---${NC}"
    exit 0
  fi
fi
# ── DELTA-RESUME-END ────────────────────────────────────────────────────────

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

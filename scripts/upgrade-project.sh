#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Project Upgrade Script
# https://github.com/kraulerson/solo-orchestrator
#
# Upgrades a project's track, deployment type, or both.
# Handles all upgrade paths: track upgrades, deployment upgrades,
# POC-to-production, and personal-to-sponsored-POC transitions.
#
# Changelog:
# - BL-006 (2026-04-24): pre-commit gate now blocks feat: commits without
#   an active Build Loop. No migration code needed — the updated
#   scripts/process-checklist.sh and scripts/pre-commit-gate.sh are copied
#   by this script's existing behavior, so running an upgrade picks it up.
# - BL-015 (2026-04-25): pre-commit gate now blocks commits and PR creation
#   when .claude/pending-approval.json exists. New helper script
#   scripts/pending-approval.sh. CLAUDE.md template gets new bullet under
#   Construction Rules. Upgrade picks up the new scripts and template.
# - BL-016 (2026-04-25): init.sh now supports --non-interactive mode for
#   scriptable project setup (CI, UAT, AI agents). No upgrade-project.sh
#   change needed — scripts/init.sh is copied into projects but agents
#   typically invoke the framework's init.sh directly.
#
# Usage:
#   scripts/upgrade-project.sh --track standard          # Track upgrade only
#   scripts/upgrade-project.sh --deployment organizational  # Deployment upgrade only
#   scripts/upgrade-project.sh --to-production            # Full upgrade to production
#   scripts/upgrade-project.sh --to-sponsored-poc         # Personal → Sponsored POC
#   scripts/upgrade-project.sh --help

# --- Locate orchestrator and project ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

ORCHESTRATOR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# This script runs from the PROJECT directory, not the orchestrator directory.
# Detect project root by looking for .claude/phase-state.json in cwd or parents.
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.claude/phase-state.json" ]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo ""
}

PROJECT_ROOT="$(find_project_root)"

# --- Constants ---
TRACK_ORDER=("light" "standard" "full")
VALID_TRACKS="light standard full"
VALID_DEPLOYMENTS="personal organizational"

# --- Argument parsing ---
TARGET_TRACK=""
TARGET_DEPLOYMENT=""
TO_PRODUCTION=false
TO_SPONSORED_POC=false
SHOW_HELP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --track)
      if [ $# -lt 2 ]; then
        print_fail "--track requires a value (light, standard, full)"
        exit 1
      fi
      TARGET_TRACK="$2"
      shift 2
      ;;
    --deployment)
      if [ $# -lt 2 ]; then
        print_fail "--deployment requires a value (personal, organizational)"
        exit 1
      fi
      TARGET_DEPLOYMENT="$2"
      shift 2
      ;;
    --to-production)
      TO_PRODUCTION=true
      shift
      ;;
    --to-sponsored-poc)
      TO_SPONSORED_POC=true
      shift
      ;;
    --help|-h)
      SHOW_HELP=true
      shift
      ;;
    *)
      print_fail "Unknown argument: $1"
      echo "Run with --help for usage."
      exit 1
      ;;
  esac
done

# --- Help ---
if [ "$SHOW_HELP" = true ]; then
  echo ""
  echo -e "${BOLD}Solo Orchestrator — Project Upgrade${NC}"
  echo ""
  echo "Upgrades a project's track, deployment type, or both."
  echo "Run this from your project directory (where .claude/phase-state.json lives)."
  echo ""
  echo -e "${BOLD}Usage:${NC}"
  echo "  scripts/upgrade-project.sh --track standard           # Track upgrade (light->standard, etc.)"
  echo "  scripts/upgrade-project.sh --track full               # Track upgrade to full"
  echo "  scripts/upgrade-project.sh --deployment organizational # Add governance framework"
  echo "  scripts/upgrade-project.sh --to-production            # POC -> Production (upgrade track + remove POC)"
  echo "  scripts/upgrade-project.sh --to-sponsored-poc         # Private POC -> Sponsored POC"
  echo "  scripts/upgrade-project.sh --help                     # This help message"
  echo ""
  echo -e "${BOLD}Flags can be combined:${NC}"
  echo "  scripts/upgrade-project.sh --track standard --deployment organizational"
  echo ""
  echo -e "${BOLD}Upgrade paths:${NC}"
  echo "  Track:       light -> standard, light -> full, standard -> full"
  echo "  Deployment:  personal -> organizational (adds governance framework)"
  echo "  POC modes:   private_poc -> sponsored_poc, private_poc -> production,"
  echo "               sponsored_poc -> production"
  echo ""
  echo -e "${BOLD}What gets updated:${NC}"
  echo "  - .claude/phase-state.json (track)"
  echo "  - .claude/tool-preferences.json (track in context)"
  echo "  - CLAUDE.md (POC watermarks removed, governance section added)"
  echo "  - PROJECT_INTAKE.md (track/deployment fields, governance section)"
  echo "  - APPROVAL_LOG.md (restructured for organizational if deployment changes)"
  echo "  - Tool resolution (new tools surfaced for the upgraded track)"
  echo ""
  exit 0
fi

# --- Validate project root ---
if [ -z "$PROJECT_ROOT" ]; then
  print_fail "No Solo Orchestrator project found."
  print_info "Run this script from your project directory (where .claude/phase-state.json lives)."
  exit 1
fi

# --- Prerequisites ---
if ! command -v jq &>/dev/null; then
  print_fail "jq is required but not installed."
  print_info "Install with: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  print_fail "python3 is required but not installed."
  exit 1
fi

# UAT 2026-04-25 fix (U-N): refuse to operate inside the framework repo.
guard_not_in_framework || exit 1

# --- BL-015 pending-approval sentinel respect (UAT 2026-04-25 fix C5) ---
# If the agent has offered structured options to the user via
# scripts/pending-approval.sh, refuse to advance an irreversible upgrade.
# Surfaced by 5/5 upgrade UAT agents (49, 62, 79, 82, 84): upgrade-project.sh
# was happily writing files and committing while a sentinel existed.
PENDING_APPROVAL_FILE="$PROJECT_ROOT/.claude/pending-approval.json"
if [ -f "$PENDING_APPROVAL_FILE" ]; then
  print_fail "upgrade blocked — pending user decision."
  if jq -e . "$PENDING_APPROVAL_FILE" >/dev/null 2>&1; then
    pa_question=$(jq -r '.question // "(missing)"' "$PENDING_APPROVAL_FILE")
    pa_offered=$(jq -r '.offered_at // "(unknown)"' "$PENDING_APPROVAL_FILE")
    echo "" >&2
    echo "  Pending question: \"$pa_question\" (offered $pa_offered)" >&2
    echo "  Options:" >&2
    jq -r '.options[]? // empty | "    " + .' "$PENDING_APPROVAL_FILE" >&2
  else
    echo "" >&2
    echo "  Sentinel file $PENDING_APPROVAL_FILE exists but is malformed." >&2
    echo "  Treated as in-flight per CDF 4.2.3 contract." >&2
  fi
  echo "" >&2
  echo "  Wait for the user to pick, then:" >&2
  echo "    scripts/pending-approval.sh --resolve" >&2
  echo "  Or, if the question is being aborted:" >&2
  echo "    scripts/pending-approval.sh --clear" >&2
  exit 1
fi

# --- File paths ---
PHASE_STATE="$PROJECT_ROOT/.claude/phase-state.json"
TOOL_PREFS="$PROJECT_ROOT/.claude/tool-preferences.json"
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
INTAKE_MD="$PROJECT_ROOT/PROJECT_INTAKE.md"
APPROVAL_LOG="$PROJECT_ROOT/APPROVAL_LOG.md"
INTAKE_PROGRESS="$PROJECT_ROOT/.claude/intake-progress.json"

# --- Read current state ---
print_step "Reading current project state"

if [ ! -f "$PHASE_STATE" ]; then
  print_fail "Phase state file not found: $PHASE_STATE"
  exit 1
fi

CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE")
PROJECT_NAME=$(jq -r '.project // "Unknown"' "$PHASE_STATE")

# Read track from tool-preferences.json context, falling back to phase-state or intake-progress
CURRENT_TRACK=""
CURRENT_DEPLOYMENT=""
CURRENT_POC_MODE=""
CURRENT_PLATFORM=""
CURRENT_LANGUAGE=""
CURRENT_DEV_OS=""

if [ -f "$TOOL_PREFS" ]; then
  CURRENT_TRACK=$(jq -r '.context.track // ""' "$TOOL_PREFS")
  CURRENT_PLATFORM=$(jq -r '.context.platform // ""' "$TOOL_PREFS")
  CURRENT_LANGUAGE=$(jq -r '.context.language // ""' "$TOOL_PREFS")
  CURRENT_DEV_OS=$(jq -r '.context.dev_os // ""' "$TOOL_PREFS")
fi

# Fall back to intake-progress.json for deployment and POC mode
if [ -f "$INTAKE_PROGRESS" ]; then
  if [ -z "$CURRENT_TRACK" ]; then
    CURRENT_TRACK=$(jq -r '.track // ""' "$INTAKE_PROGRESS")
  fi
  CURRENT_DEPLOYMENT=$(jq -r '.deployment // ""' "$INTAKE_PROGRESS")
  CURRENT_POC_MODE=$(jq -r '.poc_mode // ""' "$INTAKE_PROGRESS")
  if [ "$CURRENT_POC_MODE" = "null" ]; then
    CURRENT_POC_MODE=""
  fi
  if [ -z "$CURRENT_PLATFORM" ]; then
    CURRENT_PLATFORM=$(jq -r '.platform // ""' "$INTAKE_PROGRESS")
  fi
  if [ -z "$CURRENT_LANGUAGE" ]; then
    CURRENT_LANGUAGE=$(jq -r '.language // ""' "$INTAKE_PROGRESS")
  fi
fi

# Final fallback: read from phase-state.json — the canonical source init.sh writes.
# UAT 2026-04-25 fix C4: agents 49,77,78,80,81,82 all hit "Project is not in
# POC mode" when intake-progress.json was missing because init.sh never creates
# it. phase-state.json carries .track/.deployment/.poc_mode from init.sh:1527.
if [ -f "$PHASE_STATE" ]; then
  if [ -z "$CURRENT_TRACK" ]; then
    CURRENT_TRACK=$(jq -r '.track // ""' "$PHASE_STATE")
  fi
  if [ -z "$CURRENT_DEPLOYMENT" ]; then
    CURRENT_DEPLOYMENT=$(jq -r '.deployment // ""' "$PHASE_STATE")
  fi
  if [ -z "$CURRENT_POC_MODE" ]; then
    CURRENT_POC_MODE=$(jq -r '.poc_mode // ""' "$PHASE_STATE")
    if [ "$CURRENT_POC_MODE" = "null" ]; then
      CURRENT_POC_MODE=""
    fi
  fi
fi

# Detect deployment from APPROVAL_LOG.md frontmatter if not in progress file
if [ -z "$CURRENT_DEPLOYMENT" ] && [ -f "$APPROVAL_LOG" ]; then
  CURRENT_DEPLOYMENT=$(grep -m1 '^deployment:' "$APPROVAL_LOG" 2>/dev/null | sed 's/deployment: *//' || echo "")
fi

# Detect deployment from CLAUDE.md or PROJECT_INTAKE.md if still empty
if [ -z "$CURRENT_DEPLOYMENT" ]; then
  if [ -f "$INTAKE_MD" ]; then
    if grep -q "Organizational" "$INTAKE_MD" 2>/dev/null; then
      CURRENT_DEPLOYMENT="organizational"
    elif grep -q "Personal" "$INTAKE_MD" 2>/dev/null; then
      CURRENT_DEPLOYMENT="personal"
    fi
  fi
fi

# Default dev_os
if [ -z "$CURRENT_DEV_OS" ]; then
  case "$(uname -s)" in
    Darwin*) CURRENT_DEV_OS="darwin" ;;
    Linux*)  CURRENT_DEV_OS="linux" ;;
    *)       CURRENT_DEV_OS="darwin" ;;
  esac
fi

# Validate we have enough state to proceed
if [ -z "$CURRENT_TRACK" ]; then
  print_fail "Cannot determine current track."
  print_info "Ensure .claude/tool-preferences.json or .claude/intake-progress.json exists with track info."
  exit 1
fi

if [ -z "$CURRENT_DEPLOYMENT" ]; then
  print_warn "Cannot determine current deployment type. Assuming personal."
  CURRENT_DEPLOYMENT="personal"
fi

print_ok "Project: $PROJECT_NAME"
print_ok "Current track: $CURRENT_TRACK"
print_ok "Current deployment: $CURRENT_DEPLOYMENT"
if [ -n "$CURRENT_POC_MODE" ]; then
  print_ok "Current POC mode: ${CURRENT_POC_MODE//_/ }"
fi
print_ok "Current phase: $CURRENT_PHASE"
echo ""

# ================================================================
# Resolve target state based on flags
# ================================================================

# Helper: get track rank (light=0, standard=1, full=2)
track_rank() {
  case "$1" in
    light)    echo 0 ;;
    standard) echo 1 ;;
    full)     echo 2 ;;
    *)        echo -1 ;;
  esac
}

# --to-production: infer target track and deployment
if [ "$TO_PRODUCTION" = true ]; then
  # Must currently be in POC mode
  if [ -z "$CURRENT_POC_MODE" ]; then
    print_fail "Project is not in POC mode. Use --track and/or --deployment for non-POC upgrades."
    exit 1
  fi

  # Default target track: standard (or keep current if already higher)
  if [ -z "$TARGET_TRACK" ]; then
    if [ "$(track_rank "$CURRENT_TRACK")" -lt "$(track_rank "standard")" ]; then
      TARGET_TRACK="standard"
    else
      TARGET_TRACK="$CURRENT_TRACK"
    fi
  fi

  # Production always means organizational
  if [ -z "$TARGET_DEPLOYMENT" ]; then
    if [ "$CURRENT_DEPLOYMENT" = "personal" ]; then
      TARGET_DEPLOYMENT="organizational"
    else
      TARGET_DEPLOYMENT="$CURRENT_DEPLOYMENT"
    fi
  fi
fi

# --to-sponsored-poc: personal/light -> organizational/light
if [ "$TO_SPONSORED_POC" = true ]; then
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ "$CURRENT_POC_MODE" = "sponsored_poc" ]; then
    print_warn "Project is already a Sponsored POC. Nothing to do."
    exit 0
  fi
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ -z "$CURRENT_POC_MODE" ]; then
    print_fail "Project is already organizational/production. Cannot downgrade to Sponsored POC."
    exit 1
  fi
  TARGET_DEPLOYMENT="organizational"
  # Track stays the same for POC transition
  if [ -z "$TARGET_TRACK" ]; then
    TARGET_TRACK="$CURRENT_TRACK"
  fi
fi

# Use current values if not specified
if [ -z "$TARGET_TRACK" ]; then
  TARGET_TRACK="$CURRENT_TRACK"
fi
if [ -z "$TARGET_DEPLOYMENT" ]; then
  TARGET_DEPLOYMENT="$CURRENT_DEPLOYMENT"
fi

# ================================================================
# Validate the upgrade
# ================================================================
print_step "Validating upgrade"

# Validate target track
if ! echo "$VALID_TRACKS" | grep -qw "$TARGET_TRACK"; then
  print_fail "Invalid target track: $TARGET_TRACK (must be: light, standard, full)"
  exit 1
fi

# Validate target deployment
if ! echo "$VALID_DEPLOYMENTS" | grep -qw "$TARGET_DEPLOYMENT"; then
  print_fail "Invalid target deployment: $TARGET_DEPLOYMENT (must be: personal, organizational)"
  exit 1
fi

# Cannot downgrade track
CURRENT_RANK=$(track_rank "$CURRENT_TRACK")
TARGET_RANK=$(track_rank "$TARGET_TRACK")
if [ "$TARGET_RANK" -lt "$CURRENT_RANK" ]; then
  print_fail "Cannot downgrade track from $CURRENT_TRACK to $TARGET_TRACK."
  exit 1
fi

# Cannot downgrade deployment
if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ "$TARGET_DEPLOYMENT" = "personal" ]; then
  print_fail "Cannot downgrade deployment from organizational to personal."
  exit 1
fi

# Cannot go from production to POC
if [ -z "$CURRENT_POC_MODE" ] && [ "$TO_SPONSORED_POC" = true ]; then
  print_fail "Cannot downgrade a production project to POC mode."
  exit 1
fi

# Determine what changes
TRACK_CHANGES=false
DEPLOYMENT_CHANGES=false
POC_REMOVED=false
POC_TO_SPONSORED=false

if [ "$TARGET_TRACK" != "$CURRENT_TRACK" ]; then
  TRACK_CHANGES=true
fi

if [ "$TARGET_DEPLOYMENT" != "$CURRENT_DEPLOYMENT" ]; then
  DEPLOYMENT_CHANGES=true
fi

if [ "$TO_PRODUCTION" = true ] && [ -n "$CURRENT_POC_MODE" ]; then
  POC_REMOVED=true
fi

if [ "$TO_SPONSORED_POC" = true ] && [ "$CURRENT_POC_MODE" != "sponsored_poc" ]; then
  POC_TO_SPONSORED=true
fi

# Check if anything actually changes
if [ "$TRACK_CHANGES" = false ] && [ "$DEPLOYMENT_CHANGES" = false ] && \
   [ "$POC_REMOVED" = false ] && [ "$POC_TO_SPONSORED" = false ]; then
  print_warn "No changes needed — project is already at $CURRENT_TRACK/$CURRENT_DEPLOYMENT."
  exit 0
fi

print_ok "Upgrade is valid"
echo ""

# ================================================================
# Show what will change
# ================================================================
print_step "Upgrade plan"
echo ""
echo -e "  ${BOLD}Project:${NC}    $PROJECT_NAME"
echo ""

if [ "$TRACK_CHANGES" = true ]; then
  echo -e "  ${BOLD}Track:${NC}      $CURRENT_TRACK -> ${GREEN}$TARGET_TRACK${NC}"
fi
if [ "$DEPLOYMENT_CHANGES" = true ]; then
  echo -e "  ${BOLD}Deployment:${NC} $CURRENT_DEPLOYMENT -> ${GREEN}$TARGET_DEPLOYMENT${NC}"
fi
if [ "$POC_REMOVED" = true ]; then
  echo -e "  ${BOLD}POC Mode:${NC}   ${CURRENT_POC_MODE//_/ } -> ${GREEN}Production${NC}"
fi
if [ "$POC_TO_SPONSORED" = true ]; then
  echo -e "  ${BOLD}POC Mode:${NC}   ${CURRENT_POC_MODE:-private poc} -> ${GREEN}Sponsored POC${NC}"
fi

echo ""
echo -e "  ${BOLD}Files that will be updated:${NC}"
echo "    - .claude/phase-state.json"
if [ -f "$TOOL_PREFS" ]; then
  echo "    - .claude/tool-preferences.json"
fi
if [ -f "$CLAUDE_MD" ]; then
  echo "    - CLAUDE.md"
fi
if [ -f "$INTAKE_MD" ]; then
  echo "    - PROJECT_INTAKE.md"
fi
if [ "$DEPLOYMENT_CHANGES" = true ] && [ -f "$APPROVAL_LOG" ]; then
  echo "    - APPROVAL_LOG.md (restructured for organizational governance)"
fi
if [ -f "$INTAKE_PROGRESS" ]; then
  echo "    - .claude/intake-progress.json"
fi
echo ""

# --- Interactive confirmation ---
if [ -t 0 ]; then
  read -rp "$(echo -e "  ${BOLD}Proceed with this upgrade? [Y/n]${NC}: ")" confirm
  confirm="${confirm:-Y}"
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Upgrade cancelled."
    exit 0
  fi
  echo ""
else
  print_info "Non-interactive mode — proceeding with upgrade."
  echo ""
fi

# ================================================================
# 1. Update .claude/tool-preferences.json
# ================================================================
if [ -f "$TOOL_PREFS" ]; then
  print_step "Updating .claude/tool-preferences.json"

  python3 << 'PYEOF' - "$TOOL_PREFS" "$TARGET_TRACK" "$TARGET_DEPLOYMENT"
import json, sys
from datetime import date

tool_prefs_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]

with open(tool_prefs_path) as f:
    data = json.load(f)

if "context" not in data:
    data["context"] = {}

data["context"]["track"] = new_track
data["resolved_at"] = str(date.today())

with open(tool_prefs_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF

  print_ok "Updated track to $TARGET_TRACK in tool-preferences.json"
fi

# ================================================================
# 2. Update .claude/phase-state.json
# ================================================================
print_step "Updating .claude/phase-state.json"

# phase-state.json doesn't have a track field by default, but we add one
# for upgrade tracking. We also preserve existing gates.
python3 << 'PYEOF' - "$PHASE_STATE" "$TARGET_TRACK" "$POC_REMOVED" "$POC_TO_SPONSORED"
import json, sys
from datetime import date

phase_state_path = sys.argv[1]
new_track = sys.argv[2]
poc_removed = sys.argv[3] == "true"
poc_to_sponsored = sys.argv[4] == "true"

with open(phase_state_path) as f:
    data = json.load(f)

data["track"] = new_track
data["last_upgrade"] = str(date.today())

if poc_removed:
    if "poc_mode" in data:
        del data["poc_mode"]
elif poc_to_sponsored:
    data["poc_mode"] = "sponsored_poc"

with open(phase_state_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF

print_ok "Updated phase-state.json"

# ================================================================
# 3. Update .claude/intake-progress.json (if exists)
# ================================================================
if [ -f "$INTAKE_PROGRESS" ]; then
  print_step "Updating .claude/intake-progress.json"

  python3 << 'PYEOF' - "$INTAKE_PROGRESS" "$TARGET_TRACK" "$TARGET_DEPLOYMENT" "$POC_REMOVED" "$POC_TO_SPONSORED"
import json, sys

progress_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]
poc_removed = sys.argv[4] == "true"
poc_to_sponsored = sys.argv[5] == "true"

with open(progress_path) as f:
    data = json.load(f)

data["track"] = new_track
data["deployment"] = new_deployment

if poc_removed:
    data["poc_mode"] = None
elif poc_to_sponsored:
    data["poc_mode"] = "sponsored_poc"

with open(progress_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF

  print_ok "Updated intake-progress.json"
fi

# ================================================================
# 4. Update CLAUDE.md
# ================================================================
if [ -f "$CLAUDE_MD" ]; then
  print_step "Updating CLAUDE.md"

  python3 << 'PYEOF' - "$CLAUDE_MD" "$TARGET_TRACK" "$TARGET_DEPLOYMENT" "$CURRENT_TRACK" "$CURRENT_DEPLOYMENT" "$POC_REMOVED" "$DEPLOYMENT_CHANGES" "$POC_TO_SPONSORED"
import re, sys

claude_md_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]
old_track = sys.argv[4]
old_deployment = sys.argv[5]
poc_removed = sys.argv[6] == "true"
deployment_changes = sys.argv[7] == "true"
poc_to_sponsored = sys.argv[8] == "true"

with open(claude_md_path) as f:
    content = f.read()

# Update track in Project Identity section
content = re.sub(
    r'(\*\*Track:\*\*\s*).*',
    r'\g<1>' + new_track.capitalize(),
    content
)

# Remove POC watermarks if upgrading to production
if poc_removed:
    # Remove lines containing POC constraint warnings
    lines = content.split('\n')
    filtered = []
    skip_block = False
    for line in lines:
        # Skip POC-specific warning blocks
        if re.search(r'POC (MODE|mode|Mode|constraints|Constraints)', line, re.IGNORECASE):
            skip_block = True
            continue
        if skip_block and line.strip() == '':
            skip_block = False
            continue
        if skip_block:
            continue
        # Remove individual POC watermark lines
        if re.search(r'no production deployment.*no real user data.*no external users', line, re.IGNORECASE):
            continue
        if re.search(r'upgrade.*--upgrade-to-production', line, re.IGNORECASE):
            continue
        if re.search(r'upgrade.*--to-production', line, re.IGNORECASE):
            continue
        filtered.append(line)
    content = '\n'.join(filtered)

# Update POC watermarks for sponsored POC upgrade
if poc_to_sponsored:
    content = re.sub(r'Private POC', 'Sponsored POC', content)
    content = re.sub(r'private_poc', 'sponsored_poc', content)
    content = re.sub(r'private poc', 'Sponsored POC', content, flags=re.IGNORECASE)

# Update Deployment field if deployment changed
if deployment_changes:
    content = re.sub(
        r'(\*\*Deployment:\*\*\s*).*',
        r'\g<1>' + new_deployment.capitalize(),
        content
    )

# Add governance instructions if moving to organizational
if deployment_changes and new_deployment == "organizational":
    governance_section = """
### Organizational Governance
- This is an organizational deployment. All phase gates require formal approval from designated authorities.
- Pre-Phase 0 organizational pre-conditions must be tracked in APPROVAL_LOG.md.
- For organizational deployments, verify pre-Phase 0 pre-conditions are recorded before starting Phase 0.
- Phase gate approvals require: approver name, role, date, method, and evidence reference.
- The Approval Log is append-only — do not modify previous entries.
"""
    # Insert before "### When to Ask" if it exists, otherwise append
    if '### When to Ask' in content:
        content = content.replace('### When to Ask', governance_section + '\n### When to Ask')
    else:
        content += '\n' + governance_section

with open(claude_md_path, 'w') as f:
    f.write(content)
PYEOF

  print_ok "Updated CLAUDE.md"
fi

# ================================================================
# 5. Update PROJECT_INTAKE.md
# ================================================================
if [ -f "$INTAKE_MD" ]; then
  print_step "Updating PROJECT_INTAKE.md"

  python3 << 'PYEOF' - "$INTAKE_MD" "$TARGET_TRACK" "$TARGET_DEPLOYMENT" "$CURRENT_TRACK" "$CURRENT_DEPLOYMENT" "$POC_REMOVED" "$POC_TO_SPONSORED" "$DEPLOYMENT_CHANGES"
import re, sys
from datetime import date

intake_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]
old_track = sys.argv[4]
old_deployment = sys.argv[5]
poc_removed = sys.argv[6] == "true"
poc_to_sponsored = sys.argv[7] == "true"
deployment_changes = sys.argv[8] == "true"

with open(intake_path) as f:
    content = f.read()

# Update project track field
# Match patterns like "| **Project track** | Light |" or "| **Project track** | light |"
content = re.sub(
    r'(\|\s*\*\*Project track\*\*\s*\|)\s*[^|]+\|',
    r'\1 ' + new_track.capitalize() + ' |',
    content
)

# Update deployment field
# Match "| **Is this a personal project or organizational deployment?** | Personal |"
if deployment_changes:
    content = re.sub(
        r'(\|\s*\*\*Is this a personal project or organizational deployment\?\*\*\s*\|)\s*[^|]+\|',
        r'\1 ' + new_deployment.capitalize() + ' |',
        content
    )

# Update governance mode if POC is removed
if poc_removed:
    content = re.sub(
        r'(\*\*Governance Mode:\*\*)\s*.*',
        r'\1 Production',
        content
    )
    # Remove POC constraint callout
    content = re.sub(
        r'>\s*\*\*If POC mode:\*\*.*\n',
        '',
        content
    )
elif poc_to_sponsored:
    content = re.sub(
        r'(\*\*Governance Mode:\*\*)\s*.*',
        r'\1 Sponsored POC',
        content
    )

# Add governance section placeholder if moving to organizational and section 8 doesn't exist
if deployment_changes and new_deployment == "organizational":
    if '## 8. Governance Pre-Flight' not in content:
        governance_placeholder = """
---

## 8. Governance Pre-Flight (Organizational Deployments Only)

_Added during upgrade from personal to organizational deployment on """ + str(date.today()) + """._

**Governance Mode:** """ + ("Production" if poc_removed else ("Sponsored POC" if poc_to_sponsored else "Production")) + """

### 8.1 Pre-Conditions

| Pre-Condition | Status | Details | Blocking? |
|---|---|---|---|
| **AI deployment path approved by IT Security** | Not Started | | Yes |
| **Insurance confirmation obtained** | Not Started | | Yes |
| **Liability entity designated** | Not Started | | Yes |
| **Project sponsor assigned** | Not Started | | Yes |
| **Backup maintainer designated** | Not Started | | Yes |
| **ITSM ticket filed / portfolio registered** | Not Started | | Yes |
| **Exit criteria defined** | Not Started | | Yes |
| **Orchestrator time allocation approved** | Not Started | | Yes |

### 8.2 Approval Authorities

| Gate | Approver Name | Approver Role |
|---|---|---|
| **Phase 0 -> Phase 1** (business justification) | | |
| **Phase 1 -> Phase 2** (architecture approval) | | |
| **Phase 3 -> Phase 4** (go-live approval) | | |

### 8.3 Escalation Chain

| Level | Contact |
|---|---|
| **Level 1** | |
| **Level 2** | |
| **Level 3 (final authority)** | |

### 8.4 Compliance Screening

| Question | Answer |
|---|---|
| SOX-regulated financial data? | No |
| Payment card data (PCI)? | No |
| Personal data across multiple states/countries? | No |
| EU users or EU subsidiaries? | No |
| OFAC-sanctioned jurisdictions? | No |
| Records retention requirements? | No |
| AI for end-user-facing features? | No |
| Penetration testing required? | No |

### 8.5 Exit Criteria

| Field | Value |
|---|---|
| **Success definition** | |
| **Conditional success** | |
| **Failure definition** | |
"""
        # Try to insert before section 9 or at the end
        if '## 9.' in content:
            content = content.replace('## 9.', governance_placeholder + '\n## 9.')
        elif '## 10.' in content:
            content = content.replace('## 10.', governance_placeholder + '\n## 10.')
        else:
            content += governance_placeholder

# Add upgrade audit trail at the bottom
today = str(date.today())
changes = []
if old_track != new_track:
    changes.append(f"track {old_track} -> {new_track}")
if old_deployment != new_deployment:
    changes.append(f"deployment {old_deployment} -> {new_deployment}")
if poc_removed:
    changes.append("POC mode removed (production)")
if poc_to_sponsored:
    changes.append("upgraded to sponsored POC")

if changes:
    audit_line = f"\n> **Upgrade ({today}):** {', '.join(changes)}. Applied by `scripts/upgrade-project.sh`.\n"
    # Insert after the Document Control section or at the top
    if '## Purpose' in content:
        content = content.replace('## Purpose', audit_line + '\n## Purpose')
    else:
        content = audit_line + content

with open(intake_path, 'w') as f:
    f.write(content)
PYEOF

  print_ok "Updated PROJECT_INTAKE.md"
fi

# ================================================================
# 6. Update APPROVAL_LOG.md
# ================================================================
if [ "$DEPLOYMENT_CHANGES" = true ] && [ "$TARGET_DEPLOYMENT" = "organizational" ]; then
  print_step "Updating APPROVAL_LOG.md for organizational governance"

  if [ -f "$APPROVAL_LOG" ]; then
    # Check if it's currently a personal-format log
    if grep -q 'deployment: personal' "$APPROVAL_LOG" 2>/dev/null; then
      # Back up the personal log
      cp "$APPROVAL_LOG" "${APPROVAL_LOG}.personal-backup"
      print_info "Personal approval log backed up to APPROVAL_LOG.md.personal-backup"

      python3 << 'PYEOF' - "$APPROVAL_LOG" "$PROJECT_NAME"
import re, sys
from datetime import date

log_path = sys.argv[1]
project_name = sys.argv[2]
today = str(date.today())

with open(log_path) as f:
    old_content = f.read()

# Extract any existing gate entries with dates from the personal log
existing_gates = {}
# Look for Phase X -> Phase Y sections with filled-in dates
for match in re.finditer(r'Phase (\d).*Phase (\d).*?\n.*?\*\*(?:Reviewer|Date)\*\*\s*\|\s*(.+?)(?:\s*\||\s*$)', old_content, re.MULTILINE):
    gate_key = f"phase_{match.group(1)}_to_{match.group(2)}"
    value = match.group(3).strip()
    if value and value != '|':
        existing_gates[gate_key] = value

new_content = f"""---
project: {project_name}
deployment: organizational
created: {today}
upgraded_from: personal
framework: Solo Orchestrator v1.0
---

# Approval Log — {project_name}

This document records all governance approvals for this project. Each entry captures who approved what, when, and what evidence supports the approval. This is the auditable governance trail required by the Solo Orchestrator Enterprise Governance Framework (SOI-003-GOV, Section V).

**Instructions:** Update this log at each phase gate transition. Every approval entry must include the approver's name, role, date, method of approval, and a reference to the evidence. Do not delete or modify previous entries — append only. Git history provides tamper evidence.

> **Note:** This project was upgraded from personal to organizational deployment on {today}. Previous personal approval history is preserved in APPROVAL_LOG.md.personal-backup and in git history.

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
| {today} | Deployment upgrade (personal → organizational) | Orchestrator | — | Applied | scripts/upgrade-project.sh |
"""

with open(log_path, 'w') as f:
    f.write(new_content)
PYEOF

      print_ok "Restructured APPROVAL_LOG.md for organizational governance"
    else
      print_info "APPROVAL_LOG.md already has organizational format — no restructure needed"
    fi
  else
    # No existing APPROVAL_LOG.md — generate one
    print_info "No APPROVAL_LOG.md found — generating organizational format"

    python3 << 'PYEOF' - "$APPROVAL_LOG" "$PROJECT_NAME"
import sys
from datetime import date

log_path = sys.argv[1]
project_name = sys.argv[2]
today = str(date.today())

content = f"""---
project: {project_name}
deployment: organizational
created: {today}
framework: Solo Orchestrator v1.0
---

# Approval Log — {project_name}

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
"""

with open(log_path, 'w') as f:
    f.write(content)
PYEOF

    print_ok "Generated organizational APPROVAL_LOG.md"
  fi
fi

# ================================================================
# 6b. Append upgrade audit entry when no deployment change but POC/track changed
# ================================================================
if [ "$DEPLOYMENT_CHANGES" = false ] && { [ "$POC_REMOVED" = true ] || [ "$POC_TO_SPONSORED" = true ] || [ "$TRACK_CHANGES" = true ]; }; then
  if [ -f "$APPROVAL_LOG" ]; then
    print_step "Appending upgrade audit entry to APPROVAL_LOG.md"

    python3 << 'PYEOF' - "$APPROVAL_LOG" "$POC_REMOVED" "$POC_TO_SPONSORED" "$TRACK_CHANGES" "$CURRENT_TRACK" "$TARGET_TRACK"
import sys
from datetime import date

log_path = sys.argv[1]
poc_removed = sys.argv[2] == "true"
poc_to_sponsored = sys.argv[3] == "true"
track_changes = sys.argv[4] == "true"
old_track = sys.argv[5]
new_track = sys.argv[6]
today = str(date.today())

with open(log_path) as f:
    content = f.read()

changes = []
if poc_removed:
    changes.append("POC mode removed (production-ready)")
if poc_to_sponsored:
    changes.append("upgraded from Private POC to Sponsored POC")
if track_changes:
    changes.append(f"track upgraded from {old_track} to {new_track}")

audit_entry = f"\n| {today} | Upgrade | scripts/upgrade-project.sh | System | Applied | {', '.join(changes)} |\n"

# Append to Approval History table if it exists
if "## Approval History" in content:
    # Insert before the last empty row in the table
    content = content.rstrip()
    content += audit_entry
else:
    content += f"\n---\n\n## Upgrade Log\n\n| Date | Event | Tool | Actor | Status | Details |\n|---|---|---|---|---|---|\n{audit_entry}"

with open(log_path, 'w') as f:
    f.write(content)
PYEOF

    print_ok "Appended upgrade audit entry to APPROVAL_LOG.md"
  fi
fi

# ================================================================
# 7. Call resolve-tools.sh (if available and state is sufficient)
# ================================================================
RESOLVER="$ORCHESTRATOR_ROOT/scripts/resolve-tools.sh"
MATRIX_DIR="$ORCHESTRATOR_ROOT/templates/tool-matrix"

if [ "$TRACK_CHANGES" = true ] && [ -f "$RESOLVER" ] && [ -d "$MATRIX_DIR" ] && \
   [ -n "$CURRENT_PLATFORM" ] && [ -n "$CURRENT_LANGUAGE" ]; then
  print_step "Resolving tools for upgraded track"

  RESOLVER_OUTPUT=""
  if RESOLVER_OUTPUT=$(bash "$RESOLVER" \
      --dev-os "$CURRENT_DEV_OS" \
      --platform "$CURRENT_PLATFORM" \
      --language "$CURRENT_LANGUAGE" \
      --track "$TARGET_TRACK" \
      --phase "$CURRENT_PHASE" \
      --matrix-dir "$MATRIX_DIR" \
      ${TOOL_PREFS:+--tool-prefs "$TOOL_PREFS"} 2>/dev/null); then

    # Show newly required tools
    AUTO_COUNT=$(echo "$RESOLVER_OUTPUT" | jq '.auto_install | length')
    MANUAL_COUNT=$(echo "$RESOLVER_OUTPUT" | jq '.manual_install | length')
    TOTAL_NEW=$((AUTO_COUNT + MANUAL_COUNT))

    if [ "$TOTAL_NEW" -gt 0 ]; then
      echo ""
      print_info "The $TARGET_TRACK track requires $TOTAL_NEW additional tool(s):"
      echo ""

      if [ "$AUTO_COUNT" -gt 0 ]; then
        echo -e "  ${BOLD}Auto-installable:${NC}"
        echo "$RESOLVER_OUTPUT" | jq -r '.auto_install[] | "    - \(.name) (\(.category // "general"))"'
      fi

      if [ "$MANUAL_COUNT" -gt 0 ]; then
        echo -e "  ${BOLD}Requires manual setup:${NC}"
        echo "$RESOLVER_OUTPUT" | jq -r '.manual_install[] | "    - \(.name): \(.instructions // "see documentation")"'
      fi

      echo ""

      if [ "$AUTO_COUNT" -gt 0 ] && [ -t 0 ]; then
        read -rp "$(echo -e "  ${BOLD}Auto-install $AUTO_COUNT tool(s) now? [Y/n]${NC}: ")" install_confirm
        install_confirm="${install_confirm:-Y}"
        if [[ "$install_confirm" =~ ^[Yy]$ ]]; then
          echo "$RESOLVER_OUTPUT" | jq -r '.auto_install[] | .install_cmd' | while IFS= read -r cmd; do
            if [ -n "$cmd" ]; then
              print_info "Installing: $cmd"
              if eval "$cmd" 2>/dev/null; then
                print_ok "Installed successfully"
              else
                print_warn "Install failed — you may need to install manually"
              fi
            fi
          done
        else
          print_info "Skipped auto-install. You can install tools later."
        fi
      fi

      if [ "$MANUAL_COUNT" -gt 0 ]; then
        print_info "Remember to complete manual tool setup listed above."
      fi
    else
      print_ok "No additional tools required for the $TARGET_TRACK track"
    fi
  else
    print_warn "Tool resolver returned an error — skipping tool resolution."
    print_info "You can run tool resolution manually later."
  fi
else
  if [ "$TRACK_CHANGES" = true ]; then
    print_info "Tool resolver not available — skipping tool resolution."
    print_info "Run resolve-tools.sh manually to check for new track requirements."
  fi
fi

# ================================================================
# 8. Commit all changes
# ================================================================
echo ""
print_step "Committing changes"

# Build commit message
COMMIT_PARTS=()
if [ "$TRACK_CHANGES" = true ]; then
  COMMIT_PARTS+=("track $CURRENT_TRACK -> $TARGET_TRACK")
fi
if [ "$DEPLOYMENT_CHANGES" = true ]; then
  COMMIT_PARTS+=("deployment $CURRENT_DEPLOYMENT -> $TARGET_DEPLOYMENT")
fi
if [ "$POC_REMOVED" = true ]; then
  COMMIT_PARTS+=("POC -> production")
fi
if [ "$POC_TO_SPONSORED" = true ]; then
  COMMIT_PARTS+=("-> sponsored POC")
fi

COMMIT_SUMMARY=$(IFS=', '; echo "${COMMIT_PARTS[*]}")
COMMIT_MSG="chore(upgrade): ${COMMIT_SUMMARY}

Upgraded project configuration via scripts/upgrade-project.sh.
Changes: ${COMMIT_SUMMARY}."

# Stage all modified project files
cd "$PROJECT_ROOT"

FILES_TO_STAGE=()
[ -f ".claude/phase-state.json" ] && FILES_TO_STAGE+=(".claude/phase-state.json")
[ -f ".claude/tool-preferences.json" ] && FILES_TO_STAGE+=(".claude/tool-preferences.json")
[ -f ".claude/intake-progress.json" ] && FILES_TO_STAGE+=(".claude/intake-progress.json")
[ -f "CLAUDE.md" ] && FILES_TO_STAGE+=("CLAUDE.md")
[ -f "PROJECT_INTAKE.md" ] && FILES_TO_STAGE+=("PROJECT_INTAKE.md")
[ -f "APPROVAL_LOG.md" ] && FILES_TO_STAGE+=("APPROVAL_LOG.md")

if [ ${#FILES_TO_STAGE[@]} -gt 0 ]; then
  # Check if there are actual changes to commit
  if git diff --quiet "${FILES_TO_STAGE[@]}" 2>/dev/null && \
     git diff --cached --quiet "${FILES_TO_STAGE[@]}" 2>/dev/null; then
    print_info "No file changes detected — skipping commit."
  else
    git add "${FILES_TO_STAGE[@]}" 2>/dev/null || true
    if git diff --cached --quiet 2>/dev/null; then
      print_info "No staged changes — skipping commit."
    else
      if git commit -m "$COMMIT_MSG" 2>/dev/null; then
        print_ok "Changes committed"
      else
        print_warn "Git commit failed — changes are staged but not committed."
        print_info "You can commit manually: git commit -m 'chore(upgrade): ${COMMIT_SUMMARY}'"
      fi
    fi
  fi
else
  print_info "No files to stage."
fi

# ================================================================
# Summary
# ================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║               Upgrade Complete                          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Project:${NC}    $PROJECT_NAME"
echo -e "  ${BOLD}Track:${NC}      $TARGET_TRACK"
echo -e "  ${BOLD}Deployment:${NC} $TARGET_DEPLOYMENT"
if [ "$POC_REMOVED" = true ]; then
  echo -e "  ${BOLD}Mode:${NC}       Production"
elif [ "$POC_TO_SPONSORED" = true ]; then
  echo -e "  ${BOLD}Mode:${NC}       Sponsored POC"
fi
echo ""

if [ "$DEPLOYMENT_CHANGES" = true ] && [ "$TARGET_DEPLOYMENT" = "organizational" ]; then
  print_info "Next steps for organizational deployment:"
  echo "  1. Fill in the Pre-Phase 0 organizational pre-conditions in APPROVAL_LOG.md"
  echo "  2. Complete Section 8 of PROJECT_INTAKE.md (governance pre-flight)"
  echo "  3. Assign approval authorities for each phase gate"
  echo ""
fi

if [ "$TRACK_CHANGES" = true ]; then
  print_info "Track upgraded to $TARGET_TRACK. Review new requirements:"
  echo "  - Check docs/reference/builders-guide.md for $TARGET_TRACK track requirements"
  echo "  - Run scripts/resolve-tools.sh to verify all tools are installed"
  echo ""
fi

if [ "$POC_REMOVED" = true ]; then
  print_info "POC constraints removed. This project is now production-ready."
  echo "  - Review CLAUDE.md for any remaining POC references"
  echo "  - Review PROJECT_INTAKE.md Section 8 governance fields"
  echo ""
fi

# Run installation verification after upgrade
if [ -x "scripts/verify-install.sh" ]; then
  echo ""
  print_step "Running post-upgrade verification..."
  bash scripts/verify-install.sh || true
fi

# --- Host-aware migration (spec 2026-04-21) ---
# Projects created before the host-aware gate need the flat CI template layout
# migrated into per-host subfolders and the manifest backfilled with a host field.
# This runs idempotently — safe on already-migrated projects.

if [ -d templates/pipelines/ci ] && [ ! -d templates/pipelines/ci/github ] && ls templates/pipelines/ci/*.yml >/dev/null 2>&1; then
  print_step "Migrating flat CI template layout → per-host subfolders"
  mkdir -p templates/pipelines/ci/github templates/pipelines/release/github
  for f in templates/pipelines/ci/*.yml; do
    [ -f "$f" ] && (git mv "$f" "templates/pipelines/ci/github/$(basename "$f")" 2>/dev/null || mv "$f" "templates/pipelines/ci/github/$(basename "$f")")
  done
  for f in templates/pipelines/release/*.yml; do
    [ -f "$f" ] && (git mv "$f" "templates/pipelines/release/github/$(basename "$f")" 2>/dev/null || mv "$f" "templates/pipelines/release/github/$(basename "$f")")
  done
  print_ok "CI/release templates moved to github/ subfolders"
fi

if [ -f .claude/manifest.json ] && ! jq -e '.host' .claude/manifest.json >/dev/null 2>&1; then
  print_step "Backfilling manifest.json 'host' field"
  print_info "Manifest predates the host-aware gate — inferring host from git remote"
  host_url=$(git remote get-url origin 2>/dev/null || echo "")
  case "$host_url" in
    *github.com*)    inferred_host="github" ;;
    *gitlab*)        inferred_host="gitlab" ;;
    *bitbucket.org*) inferred_host="bitbucket" ;;
    *)               inferred_host="other" ;;
  esac
  jq --arg h "$inferred_host" '.host = $h' .claude/manifest.json > .claude/manifest.json.tmp \
    && mv .claude/manifest.json.tmp .claude/manifest.json
  print_ok "host set to '$inferred_host' (verify via scripts/check-gate.sh --backfill-host if wrong)"

  echo ""
  print_info "Before your next Phase 1→2 transition, run:"
  print_info "  bash scripts/check-gate.sh --preflight"
  print_info "If preflight fails, run:"
  print_info "  bash scripts/check-gate.sh --repair"
  echo ""
fi

# --- UAT template migration (spec 2026-04-23-uat-template-quality-design.md) ---
# Re-copy updated UAT source templates and per-platform reference pair.
# Idempotent — safe to re-run.
if [ -d tests/uat/templates ] || [ -d tests/uat ]; then
  print_step "Migrating UAT templates and references"
  mkdir -p tests/uat/templates tests/uat/examples

  # Source templates
  if [ -f "$SCRIPT_DIR/../templates/uat/test-session-template.html" ]; then
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.html" \
       tests/uat/templates/test-session-template.html
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.md" \
       tests/uat/templates/test-session-template.md
    print_ok "UAT source templates refreshed"
  fi

  # Per-platform reference pair (read PLATFORM from intake-progress.json)
  uat_platform=""
  if [ -f .claude/intake-progress.json ]; then
    uat_platform=$(jq -r '.answers.platform // empty' .claude/intake-progress.json 2>/dev/null || true)
  fi

  if [ -n "$uat_platform" ] && [ "$uat_platform" != "other" ] && \
     [ -f "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-pre-flight.html" ]; then
    cp "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-pre-flight.html" \
       tests/uat/examples/pre-flight-reference.html
    cp "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-scenario.json" \
       tests/uat/examples/scenario-reference.json
    print_ok "UAT reference pair copied for platform '$uat_platform'"
  elif [ "$uat_platform" = "other" ]; then
    print_info "Platform is 'other' — UAT reference is co-build protocol."
    print_info "See docs/uat-authoring-guide.md § 5 next time you start a UAT session."
  else
    print_warn "UAT platform unknown (intake-progress.json missing or lacks 'platform' field). Skipping reference copy; see docs/uat-authoring-guide.md."
  fi

  echo ""
  print_info "UAT quality guardrails now active. Next UAT session should:"
  print_info "  1. Read templates/uat/test-session-template.html's embedded checklist"
  print_info "  2. Use tests/uat/examples/ as shape references (first-class platforms)"
  print_info "  3. Run scripts/lint-uat-scenarios.sh <populated-file> before saving"
  print_info "See docs/uat-authoring-guide.md for details."
  echo ""
fi

# --- Framework-helper script refresh (UAT 2026-04-25 fix C1) ---
# init.sh's file-copy block enumerates each helper script explicitly. When new
# helpers ship in the framework (BL-009: lint-uat-scenarios.sh; BL-015:
# pending-approval.sh), existing projects can't pick them up by re-running
# init. This block syncs the post-BL-009/BL-015 helper set into the project's
# scripts/ directory. Idempotent: cp overwrites existing files identically.
print_step "Refreshing framework helper scripts (BL-009, BL-015)"
if [ -d scripts ]; then
  for helper in pending-approval.sh lint-uat-scenarios.sh; do
    if [ -f "$SCRIPT_DIR/$helper" ]; then
      cp "$SCRIPT_DIR/$helper" "scripts/$helper"
      chmod +x "scripts/$helper"
      print_ok "scripts/$helper refreshed from framework"
    fi
  done
else
  print_warn "scripts/ directory not found in project root — skipping helper refresh"
fi

# Run full project validation to surface new track requirements
if [ -x "scripts/validate.sh" ]; then
  echo ""
  print_step "Running post-upgrade validation..."
  if ! bash scripts/validate.sh; then
    echo ""
    print_warn "Post-upgrade validation found issues."
    print_info "Review the output above and address any errors before continuing."
    print_info "The upgrade itself completed successfully — validation checks new track requirements."
  fi
fi

print_ok "Upgrade complete."

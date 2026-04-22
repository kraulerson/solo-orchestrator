#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Phase Gate Consistency Check
# https://github.com/kraulerson/solo-orchestrator
#
# Reads .claude/phase-state.json and verifies that APPROVAL_LOG.md has
# dated entries for all completed phase gates. Designed to run in CI
# (as a warning step) or manually.
#
# Usage: bash scripts/check-phase-gate.sh
# Exit codes:
#   0 — all gates consistent, or phase state file not found (pre-framework)
#   1 — inconsistency detected (blocked). Set SOIF_PHASE_GATES=warn to downgrade.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

# Create a point-in-time snapshot of artifacts at phase gate transitions
create_gate_snapshot() {
  local from_phase="$1"
  local to_phase="$2"
  local snapshot_dir="docs/snapshots/phase-${from_phase}-to-${to_phase}_$(date +%Y-%m-%d)"

  if [ -d "$snapshot_dir" ]; then
    echo -e "  ${YELLOW}[SKIP]${NC} Snapshot already exists: $snapshot_dir"
    return 0
  fi

  mkdir -p "$snapshot_dir"

  case "${from_phase}-${to_phase}" in
    0-1)
      for f in PRODUCT_MANIFESTO.md APPROVAL_LOG.md PROJECT_INTAKE.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      # Include Phase 0 intermediate outputs if they exist
      if [ -d "docs/phase-0" ]; then
        mkdir -p "$snapshot_dir/phase-0"
        for f in docs/phase-0/*.md; do
          [ -f "$f" ] && cp "$f" "$snapshot_dir/phase-0/"
        done
      fi
      ;;
    1-2)
      for f in PROJECT_BIBLE.md PRODUCT_MANIFESTO.md APPROVAL_LOG.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      ;;
    2-3)
      for f in PROJECT_BIBLE.md FEATURES.md CHANGELOG.md BUGS.md APPROVAL_LOG.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      ;;
    3-4)
      for f in PRODUCT_MANIFESTO.md PROJECT_BIBLE.md FEATURES.md CHANGELOG.md BUGS.md \
               USER_GUIDE.md HANDOFF.md RELEASE_NOTES.md APPROVAL_LOG.md sbom.json; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      [ -f "docs/INCIDENT_RESPONSE.md" ] && cp "docs/INCIDENT_RESPONSE.md" "$snapshot_dir/"
      if [ -d "docs/test-results" ]; then
        ls docs/test-results/ > "$snapshot_dir/test-results-listing.txt" 2>/dev/null || true
      fi
      ;;
  esac

  echo -e "  ${GREEN}[OK]${NC} Phase gate snapshot created: $snapshot_dir"
}

PHASE_STATE=".claude/phase-state.json"
APPROVAL_LOG="APPROVAL_LOG.md"

# If no phase state file, this is either a pre-framework project or
# the file was never created. Exit cleanly — don't block CI.
if [ ! -f "$PHASE_STATE" ]; then
  echo "No $PHASE_STATE found — skipping phase gate check."
  exit 0
fi

if [ ! -f "$APPROVAL_LOG" ]; then
  echo -e "${RED}[FAIL]${NC} $APPROVAL_LOG not found but $PHASE_STATE exists."
  exit 1
fi

# Parse phase state using lightweight JSON extraction (no jq dependency)
# This handles the simple flat structure of phase-state.json
current_phase=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' "$PHASE_STATE" | grep -o '[0-9][0-9]*' || echo "0")

get_gate_date() {
  local gate_key="$1"
  local value
  value=$(grep -o "\"$gate_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$PHASE_STATE" | sed 's/.*: *"//' | sed 's/"//' || echo "")
  # Validate the extracted value is a plausible date (YYYY-MM-DD format)
  if [ -n "$value" ] && ! echo "$value" | grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; then
    echo ""  # Invalid date format — treat as missing
    return
  fi
  echo "$value"
}

gate_0_to_1=$(get_gate_date "phase_0_to_1")
gate_1_to_2=$(get_gate_date "phase_1_to_2")
gate_2_to_3=$(get_gate_date "phase_2_to_3")
gate_3_to_4=$(get_gate_date "phase_3_to_4")

# Extract deployment type and track for conditional checks
deployment=$(grep -o '"deployment"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "personal")
track=$(grep -o '"track"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "light")

issues=0

echo -e "${BOLD}Phase Gate Consistency Check${NC}"
echo "Current phase: $current_phase"
echo ""

# --- Manifesto Content Validation (P0-003) ---
# Verify the Manifesto has substantive content, not just template defaults
validate_manifesto_content() {
  local file="PRODUCT_MANIFESTO.md"
  [ -f "$file" ] || return 0  # Existence checked separately

  local missing_sections=""
  local placeholder_sections=""

  # Check all 8 required sections
  for section_num in 1 2 3 4 5 6 7 8; do
    if ! grep -qE "^## ${section_num}\." "$file"; then
      missing_sections="${missing_sections} ${section_num}"
    else
      # Check if section has content beyond template placeholders
      local section_content
      section_content=$(sed -n "/^## ${section_num}\./,/^## [0-9]/p" "$file" | grep -v "^##" | grep -v "^---" | grep -v "^$" | grep -v "^<!--" | grep -v -e '-->$' | grep -v "^\[" | grep -v "^|.*|.*|$" | head -5)
      if [ -z "$section_content" ]; then
        placeholder_sections="${placeholder_sections} ${section_num}"
      fi
    fi
  done

  if [ -n "$missing_sections" ]; then
    echo -e "${RED}[FAIL]${NC} PRODUCT_MANIFESTO.md: missing required sections:${missing_sections}"
    issues=$((issues + 1))
  fi

  if [ -n "$placeholder_sections" ]; then
    echo -e "${YELLOW}[WARN]${NC} PRODUCT_MANIFESTO.md: sections with only placeholder content:${placeholder_sections}"
    issues=$((issues + 1))
  fi

  # Check for unresolved Open Questions (P0-012)
  if grep -qi "Status:[[:space:]]*Open" "$file" 2>/dev/null; then
    local open_count
    open_count=$(grep -ci "Status:[[:space:]]*Open" "$file" 2>/dev/null || echo "0")
    echo -e "${RED}[FAIL]${NC} PRODUCT_MANIFESTO.md: $open_count unresolved Open Question(s) — resolve before Phase 1"
    issues=$((issues + 1))
  fi
}

# --- Approval Entry Field Validation (P0-004) ---
# Verify approval entries have populated fields, not just template defaults
validate_approval_fields() {
  local gate_name="$1"  # e.g., "Phase 0.*Phase 1"
  local gate_label="$2" # e.g., "Phase 0→1"

  # Find the gate section and check for populated approver/date fields
  local section
  section=$(grep -A 20 "$gate_name" "$APPROVAL_LOG" 2>/dev/null || echo "")
  [ -z "$section" ] && return 0  # No section = checked separately

  # Check for template defaults that indicate unfilled fields
  if echo "$section" | grep -qiE "(Approver|Reviewer).*\[.*\]|YYYY-MM-DD"; then
    echo -e "${YELLOW}[WARN]${NC} $gate_label: APPROVAL_LOG.md entry contains placeholder values — fill in approver name and date"
    issues=$((issues + 1))
  fi

  # For organizational deployments: warn if git author matches listed approver (P0-005)
  # The approval log uses a two-column table: | **Field** | Value |
  # Extract the approver name from the value column of the Approver row using awk.
  if [ "$deployment" = "organizational" ]; then
    local approver_name
    approver_name=$(echo "$section" | awk -F'|' '/[Aa]pprover/ && !/Role/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); gsub(/\*/, "", $3); print $3; exit }' 2>/dev/null || echo "")
    if [ -n "$approver_name" ] && [ "$approver_name" != "[Name]" ] && [ "$approver_name" != "" ]; then
      local git_user
      git_user=$(git config user.name 2>/dev/null || echo "")
      if [ -n "$git_user" ] && echo "$approver_name" | grep -qi "$git_user"; then
        echo -e "${RED}[FAIL]${NC} $gate_label: Approver name '$approver_name' matches git user — self-approval detected for organizational deployment"
        echo "  Governance requires a different individual to approve phase gates for organizational projects."
        echo "  Have the approver commit the APPROVAL_LOG.md entry themselves, or use --force with documented justification."
        issues=$((issues + 1))
      fi
    fi
  fi
}

# --- Pre-Phase 0 Pre-Conditions Check (P0-010) ---
# For organizational deployments, verify pre-conditions are recorded
if [ "$deployment" = "organizational" ] && [ "$current_phase" -ge 0 ]; then
  poc_mode_val=""
  poc_mode_val=$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "")

  if [ -z "$poc_mode_val" ] || [ "$poc_mode_val" = "null" ]; then
    # Full organizational — all 6 pre-conditions required
    if grep -q "Pre-Phase 0" "$APPROVAL_LOG" 2>/dev/null; then
      local_precond_count=$(grep -A 30 "Pre-Phase 0" "$APPROVAL_LOG" 2>/dev/null | grep -cE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])" || echo "0")
      if [ "$local_precond_count" -lt 6 ]; then
        echo -e "${YELLOW}[WARN]${NC} Pre-Phase 0: Organizational deployment — only $local_precond_count pre-condition date(s) recorded (6 required)"
        issues=$((issues + 1))
      else
        echo -e "${GREEN}  [OK]${NC} Pre-Phase 0 pre-conditions recorded ($local_precond_count entries)"
      fi
    else
      echo -e "${YELLOW}[WARN]${NC} Pre-Phase 0: Organizational deployment — no pre-conditions section found in APPROVAL_LOG.md"
      issues=$((issues + 1))
    fi
  fi
fi

# Check: if current_phase >= 1, gate 0→1 should have a date
if [ "$current_phase" -ge 1 ]; then
  if [ -n "$gate_0_to_1" ]; then
    # Verify APPROVAL_LOG.md has a corresponding entry
    if grep -q "Phase 0.*Phase 1" "$APPROVAL_LOG" && grep -A 15 "Phase 0.*Phase 1" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"; then
      echo -e "${GREEN}  [OK]${NC} Phase 0→1: gate dated $gate_0_to_1, approval log has entry"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 0→1: gate dated $gate_0_to_1, but APPROVAL_LOG.md has no dated entry"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# Approval field validation: Phase 0→1 (P0-004, P0-005)
if [ "$current_phase" -ge 1 ]; then
  validate_approval_fields "Phase 0.*Phase 1" "Phase 0→1"
fi

# Artifact existence + content check: Phase 0→1
if [ "$current_phase" -ge 1 ]; then
  if [ -f "PRODUCT_MANIFESTO.md" ]; then
    echo -e "${GREEN}  [OK]${NC} PRODUCT_MANIFESTO.md exists"
    validate_manifesto_content
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: PRODUCT_MANIFESTO.md not found"
    issues=$((issues + 1))
  fi
  # Check for Phase 0 intermediate outputs (P0-002)
  if [ -d "docs/phase-0" ]; then
    p0_files=0
    [ -f "docs/phase-0/frd.md" ] && p0_files=$((p0_files + 1))
    [ -f "docs/phase-0/user-journey.md" ] && p0_files=$((p0_files + 1))
    [ -f "docs/phase-0/data-contract.md" ] && p0_files=$((p0_files + 1))
    if [ $p0_files -eq 3 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 0 intermediates: frd.md, user-journey.md, data-contract.md"
    elif [ $p0_files -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 0 intermediates: $p0_files/3 saved (check docs/phase-0/)"
    fi
  fi
fi

# Check: if current_phase >= 2, gate 1→2 should have a date
if [ "$current_phase" -ge 2 ]; then
  if [ -n "$gate_1_to_2" ]; then
    if grep -q "Phase 1.*Phase 2" "$APPROVAL_LOG" && grep -A 15 "Phase 1.*Phase 2" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"; then
      echo -e "${GREEN}  [OK]${NC} Phase 1→2: gate dated $gate_1_to_2, approval log has entry"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 1→2: gate dated $gate_1_to_2, but APPROVAL_LOG.md has no dated entry"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# --- Phase 1→2 BACKSTOP: repo protection verification (spec 2026-04-21) ---
# Runs whenever current_phase is at or past 2 — catches drift where protection
# was loosened after init, or projects that predate the host-aware gate.
if [ "$current_phase" -ge 2 ]; then
  SCRIPT_DIR_CPG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  host_dispatcher="$SCRIPT_DIR_CPG/lib/host.sh"
  if [ -f "$host_dispatcher" ] && [ -f ".claude/manifest.json" ]; then
    # shellcheck disable=SC1090
    source "$host_dispatcher"
    mode=$(jq -r '.mode // "personal"' .claude/manifest.json 2>/dev/null || echo "personal")
    if host_load_driver 2>/dev/null; then
      if host_verify_protection "main" "$mode" 2>/dev/null; then
        echo -e "${GREEN}  [OK]${NC} Phase 1→2 backstop: repo protection verified for $mode mode"
      else
        echo -e "${RED}[FAIL]${NC} Phase 1→2 backstop: protection verification failed"
        echo "        Remediate: scripts/check-gate.sh --repair"
        echo "        Preflight: scripts/check-gate.sh --preflight"
        issues=$((issues + 1))
      fi
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 1→2 backstop: could not load host driver (manifest host field may be missing; run scripts/check-gate.sh --backfill-host)"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2 backstop: host dispatcher or manifest.json missing — skipping (project predates host-aware gate)"
  fi
fi

# Approval field validation: Phase 1→2 (P0-004)
if [ "$current_phase" -ge 2 ]; then
  validate_approval_fields "Phase 1.*Phase 2" "Phase 1→2"
fi

# Artifact existence + completeness check: Phase 1→2 (P1-008, P1-011)
if [ "$current_phase" -ge 2 ]; then
  if [ -f "PROJECT_BIBLE.md" ]; then
    echo -e "${GREEN}  [OK]${NC} PROJECT_BIBLE.md exists"
    # Check for placeholder dates (YYYY-MM-DD) indicating unfilled sections
    placeholder_dates=$(grep -c "YYYY-MM-DD" PROJECT_BIBLE.md 2>/dev/null || echo "0")
    if [ "$placeholder_dates" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} PROJECT_BIBLE.md has $placeholder_dates placeholder date(s) — update Last Updated markers"
      issues=$((issues + 1))
    fi
    # Check key sections exist (numbered 1-16 per template)
    bible_sections=$(grep -cE "^## [0-9]+\." PROJECT_BIBLE.md 2>/dev/null || echo "0")
    if [ "$bible_sections" -lt 14 ]; then
      echo -e "${YELLOW}[WARN]${NC} PROJECT_BIBLE.md has only $bible_sections numbered sections (template specifies 16, minimum 14)"
      issues=$((issues + 1))
    fi
  else
    echo -e "${RED}[FAIL]${NC} Phase 1→2: PROJECT_BIBLE.md not found"
    issues=$((issues + 1))
  fi
fi

# Check: if current_phase >= 3, gate 2→3 should have a date
if [ "$current_phase" -ge 3 ]; then
  if [ -n "$gate_2_to_3" ]; then
    if grep -q "Phase 2.*Phase 3" "$APPROVAL_LOG" && grep -A 15 "Phase 2.*Phase 3" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"; then
      echo -e "${GREEN}  [OK]${NC} Phase 2→3: gate dated $gate_2_to_3, approval log has entry"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 2→3: gate dated $gate_2_to_3, but APPROVAL_LOG.md has no dated entry"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2→3: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# Artifact existence check: Phase 2→3
if [ "$current_phase" -ge 3 ]; then
  if [ -f "FEATURES.md" ]; then
    echo -e "${GREEN}  [OK]${NC} FEATURES.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2→3: FEATURES.md not found"
    issues=$((issues + 1))
  fi
  if [ -f "CHANGELOG.md" ]; then
    echo -e "${GREEN}  [OK]${NC} CHANGELOG.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2→3: CHANGELOG.md not found"
    issues=$((issues + 1))
  fi
fi

# Check: if current_phase >= 4, gate 3→4 should have a date
if [ "$current_phase" -ge 4 ]; then
  if [ -n "$gate_3_to_4" ]; then
    if grep -q "Phase 3.*Phase 4" "$APPROVAL_LOG" && grep -A 15 "Phase 3.*Phase 4" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"; then
      echo -e "${GREEN}  [OK]${NC} Phase 3→4: gate dated $gate_3_to_4, approval log has entry"
      # P3-007: For organizational deployments, verify both App Owner and IT Security approvals
      if [ "$deployment" = "organizational" ]; then
        if grep -qi "Application Owner" "$APPROVAL_LOG" && grep -qi "IT Security" "$APPROVAL_LOG"; then
          echo -e "${GREEN}  [OK]${NC} Phase 3→4: both Application Owner and IT Security entries found"
        else
          echo -e "${YELLOW}[WARN]${NC} Phase 3→4: organizational deployment requires both Application Owner AND IT Security approval entries"
          issues=$((issues + 1))
        fi
      fi
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: gate dated $gate_3_to_4, but APPROVAL_LOG.md has no dated entry"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# POC mode check (Phase 3→4) — block production release if in POC mode
if [ "$current_phase" -ge 3 ]; then
  poc_mode=""
  if command -v jq &>/dev/null; then
    poc_mode=$(jq -r '.poc_mode // empty' .claude/phase-state.json 2>/dev/null || echo "")
  else
    poc_mode=$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/phase-state.json 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "")
  fi
  if [ -n "$poc_mode" ] && [ "$poc_mode" != "null" ]; then
    echo "::error::Phase 4 (production release) is BLOCKED — project is in ${poc_mode//_/ } mode."
    echo "  POC projects complete at Phase 3 (ready to deploy)."
    echo "  To unlock Phase 4: bash scripts/upgrade-project.sh --to-production"
    issues=$((issues + 1))
  fi
fi

# Release pipeline configuration check (Phase 3→4)
if [ "$current_phase" -ge 3 ]; then
  if [ -f ".github/workflows/release.yml" ]; then
    todo_count=$(grep -c "TODO" .github/workflows/release.yml 2>/dev/null) || todo_count=0
    if [ "$todo_count" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Release pipeline has $todo_count unconfigured TODO items in .github/workflows/release.yml"
      echo "  Configure code signing, deployment secrets, and store credentials before production release."
      issues=$((issues + 1))
    fi
  fi
fi

# Artifact existence checks: Phase 3→4
if [ "$current_phase" -ge 3 ]; then
  for artifact in "HANDOFF.md" "docs/INCIDENT_RESPONSE.md" "sbom.json"; do
    if [ -f "$artifact" ]; then
      echo -e "${GREEN}  [OK]${NC} $artifact exists"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: $artifact not found"
      issues=$((issues + 1))
    fi
  done

  # Check docs/test-results/ is non-empty (elevated to FAIL for Phase 3→4)
  if [ -d "docs/test-results" ]; then
    result_count=$(find docs/test-results -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$result_count" -eq 0 ]; then
      echo -e "${RED}[FAIL]${NC} Phase 3→4: docs/test-results/ is empty — archive Phase 3 scan results before proceeding"
      issues=$((issues + 1))
    else
      echo -e "${GREEN}  [OK]${NC} docs/test-results/ has $result_count file(s)"
    fi
  else
    echo -e "${RED}[FAIL]${NC} Phase 3→4: docs/test-results/ directory not found"
    issues=$((issues + 1))
  fi

  # P4-013: SECURITY.md check (web/desktop/mobile with external users)
  if [ -f "SECURITY.md" ]; then
    echo -e "${GREEN}  [OK]${NC} SECURITY.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: SECURITY.md not found — required for production web/desktop/mobile apps"
    issues=$((issues + 1))
  fi

  # P3-004: Penetration test check for Standard+ track
  if [ "$track" = "standard" ] || [ "$track" = "full" ]; then
    if ls docs/test-results/*pen-test* docs/test-results/*pentest* docs/test-results/*penetration* 2>/dev/null | head -1 >/dev/null 2>&1; then
      echo -e "${GREEN}  [OK]${NC} Penetration test results found in docs/test-results/"
    elif [ "$track" = "standard" ] && grep -qi "penetration.*exempted\|pen.*test.*exempted" APPROVAL_LOG.md 2>/dev/null; then
      # Standard track allows IT Security exemption
      echo -e "${GREEN}  [OK]${NC} Penetration test exempted by IT Security (recorded in APPROVAL_LOG.md)"
    elif [ "$track" = "full" ]; then
      # Full track: no exemption path — pen test is mandatory
      echo -e "${RED}[FAIL]${NC} Phase 3→4: Full Track requires penetration test — no exemption path available"
      echo "  Provide pen test results in docs/test-results/ before proceeding."
      issues=$((issues + 1))
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: No penetration test results or IT Security exemption found ($track track)"
      issues=$((issues + 1))
    fi
  fi

  # P3-007: Cross-reference process-state.json for Phase 3 completion
  if [ -f ".claude/process-state.json" ] && command -v jq &>/dev/null; then
    p3_steps_done=$(jq '.phase3_validation.steps_completed | length' .claude/process-state.json 2>/dev/null || echo "0")
    if [ "$p3_steps_done" -ge 9 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 3 process checklist: $p3_steps_done steps completed"
    elif [ "$p3_steps_done" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3 process checklist incomplete: $p3_steps_done/9 steps"
      issues=$((issues + 1))
    fi
  fi
fi

# Review manifest check (Phase 3+)
if [ "$current_phase" -ge 3 ]; then
  MANIFEST="docs/eval-results/review-manifest.json"
  if [ -f "$MANIFEST" ]; then
    if command -v jq &>/dev/null; then
      review_count=$(jq '.reviews | length' "$MANIFEST" 2>/dev/null || echo "0")
      review_commit=$(jq -r '.commit // "unknown"' "$MANIFEST" 2>/dev/null)
      echo -e "${GREEN}  [OK]${NC} Review manifest: $review_count review(s) recorded (commit: ${review_commit:0:8})"
    else
      echo -e "${GREEN}  [OK]${NC} Review manifest exists (install jq for details)"
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} No review manifest found (docs/eval-results/review-manifest.json)"
    echo "  Run evaluation prompts before Phase 4: evaluation-prompts/Projects/run-reviews.sh"
    issues=$((issues + 1))
  fi
fi

# Check for reverse inconsistency: approval log has dates but phase state doesn't reflect them
if [ "$current_phase" -lt 1 ] && [ -n "$gate_0_to_1" ]; then
  echo -e "${YELLOW}[WARN]${NC} Phase 0→1 gate has date $gate_0_to_1 but current_phase is still $current_phase"
  issues=$((issues + 1))
fi

# --- Tool Resolution Check (for phase transitions) ---
# If transitioning to a new phase, check for deferred tools that are now needed
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$PROJECT_ROOT/scripts/resolve-tools.sh"
TOOL_PREFS=".claude/tool-preferences.json"

if [ -f "$TOOL_PREFS" ] && [ -x "$RESOLVER" ] && command -v jq &>/dev/null; then
  dev_os=$(jq -r '.context.dev_os' "$TOOL_PREFS" 2>/dev/null || echo "")
  platform=$(jq -r '.context.platform' "$TOOL_PREFS" 2>/dev/null || echo "")
  language=$(jq -r '.context.language' "$TOOL_PREFS" 2>/dev/null || echo "")
  track=$(jq -r '.context.track' "$TOOL_PREFS" 2>/dev/null || echo "")

  if [ -n "$dev_os" ] && [ -n "$platform" ] && [ -n "$language" ] && [ -n "$track" ]; then
    # Resolve for the current phase
    tool_output=$("$RESOLVER" \
      --dev-os "$dev_os" \
      --platform "$platform" \
      --language "$language" \
      --track "$track" \
      --phase "$current_phase" \
      --matrix-dir "$PROJECT_ROOT/templates/tool-matrix" \
      --tool-prefs "$TOOL_PREFS" 2>/dev/null) || tool_output=""

    if [ -n "$tool_output" ]; then
      missing_required=$(echo "$tool_output" | jq '[(.auto_install + .manual_install)[] | select(.required == true)]')
      missing_count=$(echo "$missing_required" | jq 'length')

      if [ "$missing_count" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}Tools needed for Phase $current_phase:${NC}"
        echo "$missing_required" | jq -r '.[] | "  • \(.name) — \(.description // .category)"'
        echo ""

        # Check if any can be auto-installed
        auto_installable=$(echo "$tool_output" | jq '[.auto_install[]]')
        auto_count=$(echo "$auto_installable" | jq 'length')

        if [ "$auto_count" -gt 0 ]; then
          echo -e "${CYAN}The following can be auto-installed:${NC}"
          echo "$auto_installable" | jq -r '.[] | "  • \(.name)"'
          echo ""
          read -rp "$(echo -e "${BOLD}Install now? [Y/n]${NC}: ")" install_reply
          if [[ ! "$install_reply" =~ ^[Nn] ]]; then
            echo "$auto_installable" | jq -r '.[] | .install_command // empty' | while IFS= read -r cmd; do
              [ -z "$cmd" ] && continue
              echo -e "  ${CYAN}Running:${NC} $cmd"
              eval "$cmd" || echo -e "  ${YELLOW}[WARN]${NC} Command failed: $cmd"
            done
          fi
        fi

        # Show manual items
        manual_items=$(echo "$tool_output" | jq '[.manual_install[]]')
        manual_count=$(echo "$manual_items" | jq 'length')
        if [ "$manual_count" -gt 0 ]; then
          echo ""
          echo -e "${YELLOW}Manual setup still required:${NC}"
          echo "$manual_items" | jq -r '.[] | "  • \(.name) — \(.instructions // "see docs")"'
        fi

        # Special handling: if Qdrant is in the missing list and Docker is running, offer Docker setup
        if echo "$missing_required" | jq -e '.[] | select(.name == "Qdrant MCP")' >/dev/null 2>&1; then
          if command -v docker &>/dev/null && docker info &>/dev/null; then
            echo ""
            echo -e "${CYAN}Qdrant MCP can be set up now (Docker is running):${NC}"
            read -rp "$(echo -e "${BOLD}Start Qdrant container and register MCP? [Y/n]${NC}: ")" qd_reply
            if [[ ! "$qd_reply" =~ ^[Nn] ]]; then
              # Check if container already exists
              if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
                docker start qdrant 2>/dev/null && echo -e "  ${GREEN}[OK]${NC} Existing Qdrant container started"
              else
                docker run -d --name qdrant \
                  -p 6333:6333 -p 6334:6334 \
                  -v qdrant_storage:/qdrant/storage \
                  --restart unless-stopped \
                  qdrant/qdrant:latest 2>&1 && echo -e "  ${GREEN}[OK]${NC} Qdrant running at http://localhost:6333"
              fi
              # Register MCP if uvx available
              if command -v uvx &>/dev/null; then
                project_name=$(jq -r '.project // "claude-memory"' .claude/phase-state.json 2>/dev/null)
                if run_with_timeout 30 bash -c "echo y | claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$project_name qdrant -- uvx --python 3.13 mcp-server-qdrant >/dev/null 2>&1"; then
                  echo -e "  ${GREEN}[OK]${NC} Qdrant MCP registered (collection: $project_name)"
                else
                  echo -e "  ${YELLOW}[WARN]${NC} Qdrant MCP registration timed out or failed"
                  echo "  Register manually: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$project_name qdrant -- uvx --python 3.13 mcp-server-qdrant"
                fi
              else
                echo -e "  ${YELLOW}[WARN]${NC} uv/uvx not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
                echo "  Then: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
              fi
            fi
          fi
        fi

        issues=$((issues + 1))
      fi
    fi
  fi
fi

# --- Test/Bug Gate Check (for Phase 2→3) ---
TEST_GATE="$PROJECT_ROOT/scripts/test-gate.sh"

if [ -x "$TEST_GATE" ] && [ "$current_phase" -ge 3 ]; then
  echo ""
  echo -e "${BOLD}Bug Gate Check${NC}"
  gate_result=0
  bash "$TEST_GATE" --check-phase-gate || gate_result=$?

  if [ "$gate_result" -eq 1 ]; then
    echo ""
    echo -e "${RED}[FAIL]${NC} Bug gate BLOCKED. Resolve SEV-1/2 bugs before Phase 3."
    issues=$((issues + 1))
  elif [ "$gate_result" -eq 2 ]; then
    echo ""
    echo -e "${YELLOW}[WARN]${NC} Bug gate has warnings. User attestation required."
    issues=$((issues + 1))
  fi
fi

echo ""
if [ $issues -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Phase gates consistent.${NC}"

  # Create snapshots for gates that have been passed but not yet snapshotted
  if [ "$current_phase" -ge 1 ]; then
    existing_01=$(ls -d docs/snapshots/phase-0-to-1_* 2>/dev/null | head -1 || true)
    [ -z "$existing_01" ] && create_gate_snapshot 0 1
  fi
  if [ "$current_phase" -ge 2 ]; then
    existing_12=$(ls -d docs/snapshots/phase-1-to-2_* 2>/dev/null | head -1 || true)
    [ -z "$existing_12" ] && create_gate_snapshot 1 2
  fi
  if [ "$current_phase" -ge 3 ]; then
    existing_23=$(ls -d docs/snapshots/phase-2-to-3_* 2>/dev/null | head -1 || true)
    [ -z "$existing_23" ] && create_gate_snapshot 2 3
  fi
  if [ "$current_phase" -ge 4 ]; then
    existing_34=$(ls -d docs/snapshots/phase-3-to-4_* 2>/dev/null | head -1 || true)
    [ -z "$existing_34" ] && create_gate_snapshot 3 4
  fi

  exit 0
else
  if [ "${SOIF_PHASE_GATES:-}" = "warn" ]; then
    echo -e "${YELLOW}${BOLD}$issues inconsistency(ies) found (warn mode — not blocking).${NC}"
    echo "Update .claude/phase-state.json and APPROVAL_LOG.md to match."
    exit 0
  else
    echo -e "${RED}${BOLD}$issues inconsistency(ies) found — blocking.${NC}"
    echo "Update .claude/phase-state.json and APPROVAL_LOG.md to match."
    echo "Set SOIF_PHASE_GATES=warn to downgrade to warning."
    exit 1
  fi
fi

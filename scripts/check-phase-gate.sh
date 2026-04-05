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
  echo "$value"
}

gate_0_to_1=$(get_gate_date "phase_0_to_1")
gate_1_to_2=$(get_gate_date "phase_1_to_2")
gate_3_to_4=$(get_gate_date "phase_3_to_4")

issues=0

echo -e "${BOLD}Phase Gate Consistency Check${NC}"
echo "Current phase: $current_phase"
echo ""

# Check: if current_phase >= 1, gate 0→1 should have a date
if [ "$current_phase" -ge 1 ]; then
  if [ -n "$gate_0_to_1" ]; then
    # Verify APPROVAL_LOG.md has a corresponding entry
    if grep -q "Phase 0.*Phase 1" "$APPROVAL_LOG" && grep -A 15 "Phase 0.*Phase 1" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
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

# Check: if current_phase >= 2, gate 1→2 should have a date
if [ "$current_phase" -ge 2 ]; then
  if [ -n "$gate_1_to_2" ]; then
    if grep -q "Phase 1.*Phase 2" "$APPROVAL_LOG" && grep -A 15 "Phase 1.*Phase 2" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
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

# Check: if current_phase >= 4, gate 3→4 should have a date
if [ "$current_phase" -ge 4 ]; then
  if [ -n "$gate_3_to_4" ]; then
    if grep -q "Phase 3.*Phase 4" "$APPROVAL_LOG" && grep -A 15 "Phase 3.*Phase 4" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
      echo -e "${GREEN}  [OK]${NC} Phase 3→4: gate dated $gate_3_to_4, approval log has entry"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: gate dated $gate_3_to_4, but APPROVAL_LOG.md has no dated entry"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# Release pipeline configuration check (Phase 3→4)
if [ "$current_phase" = "3" ]; then
  if [ -f ".github/workflows/release.yml" ]; then
    todo_count=$(grep -c "TODO" .github/workflows/release.yml 2>/dev/null || echo "0")
    if [ "$todo_count" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Release pipeline has $todo_count unconfigured TODO items in .github/workflows/release.yml"
      echo "  Configure code signing, deployment secrets, and store credentials before production release."
      issues=$((issues + 1))
    fi
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
        echo -e "${YELLOW}${BOLD}Required tools missing for Phase $current_phase:${NC}"
        echo "$missing_required" | jq -r '.[] | "  • \(.name) (\(.category))"'
        echo ""
        echo "Run the tool resolver to install:"
        echo "  bash scripts/resolve-tools.sh --dev-os $dev_os --platform $platform --language $language --track $track --phase $current_phase --matrix-dir templates/tool-matrix --tool-prefs $TOOL_PREFS"
        issues=$((issues + 1))
      fi
    fi
  fi
fi

# --- Test/Bug Gate Check (for Phase 2→3) ---
TEST_GATE="$PROJECT_ROOT/scripts/test-gate.sh"

if [ -x "$TEST_GATE" ] && [ "$current_phase" -ge 2 ]; then
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

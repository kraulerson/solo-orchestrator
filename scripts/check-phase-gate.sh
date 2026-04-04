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
#   1 — inconsistency detected (gate passed without approval log entry)

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

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
current_phase=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*[0-9]' "$PHASE_STATE" | grep -o '[0-9]$' || echo "0")

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
      ((issues++))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: current_phase is $current_phase but gate date not recorded in phase-state.json"
    ((issues++))
  fi
fi

# Check: if current_phase >= 2, gate 1→2 should have a date
if [ "$current_phase" -ge 2 ]; then
  if [ -n "$gate_1_to_2" ]; then
    if grep -q "Phase 1.*Phase 2" "$APPROVAL_LOG" && grep -A 15 "Phase 1.*Phase 2" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
      echo -e "${GREEN}  [OK]${NC} Phase 1→2: gate dated $gate_1_to_2, approval log has entry"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 1→2: gate dated $gate_1_to_2, but APPROVAL_LOG.md has no dated entry"
      ((issues++))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2: current_phase is $current_phase but gate date not recorded in phase-state.json"
    ((issues++))
  fi
fi

# Check: if current_phase >= 4, gate 3→4 should have a date
if [ "$current_phase" -ge 4 ]; then
  if [ -n "$gate_3_to_4" ]; then
    if grep -q "Phase 3.*Phase 4" "$APPROVAL_LOG" && grep -A 15 "Phase 3.*Phase 4" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
      echo -e "${GREEN}  [OK]${NC} Phase 3→4: gate dated $gate_3_to_4, approval log has entry"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: gate dated $gate_3_to_4, but APPROVAL_LOG.md has no dated entry"
      ((issues++))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: current_phase is $current_phase but gate date not recorded in phase-state.json"
    ((issues++))
  fi
fi

# Check for reverse inconsistency: approval log has dates but phase state doesn't reflect them
if [ "$current_phase" -lt 1 ] && [ -n "$gate_0_to_1" ]; then
  echo -e "${YELLOW}[WARN]${NC} Phase 0→1 gate has date $gate_0_to_1 but current_phase is still $current_phase"
  ((issues++))
fi

echo ""
if [ $issues -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Phase gates consistent.${NC}"
  exit 0
else
  echo -e "${YELLOW}${BOLD}$issues inconsistency(ies) found.${NC}"
  echo "Update .claude/phase-state.json and APPROVAL_LOG.md to match."
  # Exit 1 in CI to surface as a warning; the CI step should use continue-on-error
  exit 1
fi

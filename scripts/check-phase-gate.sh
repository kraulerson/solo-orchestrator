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
  echo "$value"
}

gate_0_to_1=$(get_gate_date "phase_0_to_1")
gate_1_to_2=$(get_gate_date "phase_1_to_2")
gate_2_to_3=$(get_gate_date "phase_2_to_3")
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

# Artifact existence check: Phase 0→1
if [ "$current_phase" -ge 1 ]; then
  if [ -f "PRODUCT_MANIFESTO.md" ]; then
    echo -e "${GREEN}  [OK]${NC} PRODUCT_MANIFESTO.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: PRODUCT_MANIFESTO.md not found"
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

# Artifact existence check: Phase 1→2
if [ "$current_phase" -ge 2 ]; then
  if [ -f "PROJECT_BIBLE.md" ]; then
    echo -e "${GREEN}  [OK]${NC} PROJECT_BIBLE.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2: PROJECT_BIBLE.md not found"
    issues=$((issues + 1))
  fi
fi

# Check: if current_phase >= 3, gate 2→3 should have a date
if [ "$current_phase" -ge 3 ]; then
  if [ -n "$gate_2_to_3" ]; then
    if grep -q "Phase 2.*Phase 3" "$APPROVAL_LOG" && grep -A 15 "Phase 2.*Phase 3" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
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

# POC mode check (Phase 3→4) — block production release if in POC mode
if [ "$current_phase" = "3" ]; then
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

  # Check docs/test-results/ is non-empty
  if [ -d "docs/test-results" ]; then
    result_count=$(find docs/test-results -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$result_count" -eq 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: docs/test-results/ is empty — archive Phase 3 scan results before proceeding"
      issues=$((issues + 1))
    else
      echo -e "${GREEN}  [OK]${NC} docs/test-results/ has $result_count file(s)"
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: docs/test-results/ directory not found"
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

  # Create snapshots for gates that have been passed but not yet snapshotted
  if [ "$current_phase" -ge 1 ]; then
    existing_01=$(ls -d docs/snapshots/phase-0-to-1_* 2>/dev/null | head -1)
    [ -z "$existing_01" ] && create_gate_snapshot 0 1
  fi
  if [ "$current_phase" -ge 2 ]; then
    existing_12=$(ls -d docs/snapshots/phase-1-to-2_* 2>/dev/null | head -1)
    [ -z "$existing_12" ] && create_gate_snapshot 1 2
  fi
  if [ "$current_phase" -ge 3 ]; then
    existing_23=$(ls -d docs/snapshots/phase-2-to-3_* 2>/dev/null | head -1)
    [ -z "$existing_23" ] && create_gate_snapshot 2 3
  fi
  if [ "$current_phase" -ge 4 ]; then
    existing_34=$(ls -d docs/snapshots/phase-3-to-4_* 2>/dev/null | head -1)
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

#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Test Gate
# Mechanical enforcement for the test-fix-verify loop.
#
# Usage:
#   scripts/test-gate.sh --check-batch       # Can I start the next feature?
#   scripts/test-gate.sh --check-phase-gate  # Can I transition Phase 2→3?
#   scripts/test-gate.sh --reset-counter     # Reset feature counter after test session
#   scripts/test-gate.sh --record-feature NAME  # Record a completed feature
#   scripts/test-gate.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

BUILD_PROGRESS=".claude/build-progress.json"

# --- Argument parsing ---
ACTION=""
FEATURE_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check-batch)        ACTION="check-batch";        shift ;;
    --check-phase-gate)   ACTION="check-phase-gate";   shift ;;
    --reset-counter)      ACTION="reset-counter";       shift ;;
    --reset-health-check) ACTION="reset-health-check"; shift ;;
    --record-feature)     ACTION="record-feature"; FEATURE_NAME="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: scripts/test-gate.sh [--check-batch] [--check-phase-gate] [--reset-counter] [--record-feature NAME]"
      echo ""
      echo "Commands:"
      echo "  --check-batch       Check if testing session is due (exit 0=continue, 1=testing required)"
      echo "  --check-phase-gate  Check if Phase 2→3 transition is clear (exit 0=clear, 1=blocked, 2=warnings)"
      echo "  --reset-counter     Reset feature counter after testing session completes"
      echo "  --record-feature N  Record a completed feature and increment counter"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ACTION" ]; then
  echo "No action specified. Use --help for usage." >&2
  exit 1
fi

# --- Ensure build-progress.json exists ---
ensure_progress_file() {
  if [ ! -f "$BUILD_PROGRESS" ]; then
    mkdir -p .claude
    cat > "$BUILD_PROGRESS" << 'EOF'
{
  "features_completed": [],
  "features_since_last_test": 0,
  "test_interval": 2,
  "last_test_session": null,
  "testing_required": false,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 0
}
EOF
  fi
}

# --- Actions ---

check_batch() {
  ensure_progress_file

  local since_last interval
  since_last=$(jq -r '.features_since_last_test' "$BUILD_PROGRESS")
  interval=$(jq -r '.test_interval' "$BUILD_PROGRESS")

  if [ "$since_last" -ge "$interval" ]; then
    print_fail "Testing session required ($since_last features since last test, interval is $interval)"
    print_info "Run a UAT testing session before starting the next feature."
    exit 1
  else
    local remaining=$((interval - since_last))
    print_ok "Clear to continue ($remaining features until next testing session)"
    exit 0
  fi
}

record_feature() {
  ensure_progress_file

  local name="$1"
  local tmp
  tmp=$(mktemp)

  jq --arg name "$name" '
    .features_completed += [$name] |
    .features_since_last_test += 1 |
    .testing_required = (.features_since_last_test >= .test_interval)
  ' "$BUILD_PROGRESS" > "$tmp" && mv "$tmp" "$BUILD_PROGRESS"

  # Also increment health check counter
  health_count=$(jq '.features_since_last_health_check // 0' "$BUILD_PROGRESS")
  jq ".features_since_last_health_check = $((health_count + 1))" "$BUILD_PROGRESS" > "$BUILD_PROGRESS.tmp" && mv "$BUILD_PROGRESS.tmp" "$BUILD_PROGRESS"

  local since_last interval
  since_last=$(jq -r '.features_since_last_test' "$BUILD_PROGRESS")
  interval=$(jq -r '.test_interval' "$BUILD_PROGRESS")

  print_ok "Feature '$name' recorded ($since_last/$interval until next test session)"

  if [ "$since_last" -ge "$interval" ]; then
    print_warn "Testing session now required before starting next feature"
  fi
}

reset_counter() {
  ensure_progress_file

  local today
  today=$(date +%Y-%m-%d)
  local tmp
  tmp=$(mktemp)

  jq --arg date "$today" '
    .features_since_last_test = 0 |
    .testing_required = false |
    .last_test_session = $date |
    .sessions_completed += 1
  ' "$BUILD_PROGRESS" > "$tmp" && mv "$tmp" "$BUILD_PROGRESS"

  print_ok "Feature counter reset. Testing session recorded ($today)"
}

check_phase_gate() {
  # Check for BUGS.md-based tracking
  local sev1_count=0
  local sev2_open=0
  local sev2_deferred=0
  local sev3_open=0
  local has_bugs=false

  if [ -f "BUGS.md" ]; then
    has_bugs=true
    # Count open bugs by severity
    # BUGS.md format: | # | SEV-N | Status | Feature | Description | ...
    # Status values: Open, Deferred, Fixed, Won't Fix, Post-MVP, Removed
    sev1_count=$(grep -c 'SEV-1.*Open' "BUGS.md" 2>/dev/null | tr -d '[:space:]' || echo "0")
    sev2_open=$(grep -c 'SEV-2.*Open' "BUGS.md" 2>/dev/null | tr -d '[:space:]' || echo "0")
    sev2_deferred=$(grep -c 'SEV-2.*Deferred' "BUGS.md" 2>/dev/null | tr -d '[:space:]' || echo "0")
    sev3_open=$(grep -c 'SEV-3.*Open' "BUGS.md" 2>/dev/null | tr -d '[:space:]' || echo "0")
  fi

  # Also check GitHub Issues if gh CLI available
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    local gh_sev1 gh_sev2_open gh_sev2_deferred gh_sev3
    gh_sev1=$(gh issue list --label "SEV-1" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null | tr -d '[:space:]' || echo "0")
    gh_sev2_open=$(gh issue list --label "SEV-2" --label "fix-now" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null | tr -d '[:space:]' || echo "0")
    gh_sev2_deferred=$(gh issue list --label "SEV-2" --label "deferred" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null | tr -d '[:space:]' || echo "0")
    gh_sev3=$(gh issue list --label "SEV-3" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null | tr -d '[:space:]' || echo "0")

    sev1_count=$((${sev1_count:-0} + ${gh_sev1:-0}))
    sev2_open=$((${sev2_open:-0} + ${gh_sev2_open:-0}))
    sev2_deferred=$((${sev2_deferred:-0} + ${gh_sev2_deferred:-0}))
    sev3_open=$((${sev3_open:-0} + ${gh_sev3:-0}))
    has_bugs=true
  fi

  if [ "$has_bugs" = false ]; then
    print_warn "No bug tracking source found (BUGS.md or GitHub Issues)"
    print_info "Cannot verify bug status. Proceeding with warning."
    exit 2
  fi

  echo ""
  echo -e "${BOLD}Phase 2→3 Bug Gate Check${NC}"
  echo ""

  local blocked=false
  local warnings=false

  # SEV-1: must be resolved
  if [ "$sev1_count" -gt 0 ]; then
    print_fail "SEV-1 bugs open: $sev1_count (BLOCKED — must resolve before Phase 3)"
    blocked=true
  else
    print_ok "No open SEV-1 bugs"
  fi

  # SEV-2 open: must be resolved
  if [ "$sev2_open" -gt 0 ]; then
    print_fail "SEV-2 bugs open (fix-now): $sev2_open (BLOCKED — must resolve before Phase 3)"
    blocked=true
  else
    print_ok "No open SEV-2 fix-now bugs"
  fi

  # SEV-2 deferred: must resolve or remove feature
  if [ "$sev2_deferred" -gt 0 ]; then
    print_fail "SEV-2 bugs deferred: $sev2_deferred (BLOCKED — must resolve or remove/hide feature)"
    echo ""
    echo -e "${BOLD}For each deferred SEV-2 bug, you must:${NC}"
    echo "  1. Resolve — fix the bug, re-test, verify"
    echo "  2. Remove — disable/hide the feature entirely (moves to Post-MVP backlog)"
    echo ""
    blocked=true
  else
    print_ok "No deferred SEV-2 bugs"
  fi

  # SEV-3: warning only, user attestation
  if [ "$sev3_open" -gt 0 ]; then
    print_warn "SEV-3 bugs open: $sev3_open (user attestation required)"
    warnings=true
  else
    print_ok "No open SEV-3 bugs"
  fi

  # --- Feature completeness check (P2-022) ---
  echo ""
  echo -e "${BOLD}Feature Completeness Check${NC}"
  echo ""

  # Check FEATURES.md exists and count features
  if [ -f "FEATURES.md" ]; then
    # Count feature entries (lines starting with ## or ### that look like feature headings)
    local feature_count
    feature_count=$(grep -cE '^#{2,3} ' FEATURES.md 2>/dev/null || echo "0")
    # Exclude template headings and non-feature sections
    feature_count=$(grep -cE '^#{2,3} [^#]' FEATURES.md 2>/dev/null | head -1 || echo "0")

    # Check build-progress.json for recorded features
    local recorded_features=0
    if [ -f ".claude/build-progress.json" ] && command -v jq &>/dev/null; then
      recorded_features=$(jq '.features_completed | length' .claude/build-progress.json 2>/dev/null || echo "0")
    fi

    if [ "$recorded_features" -gt 0 ]; then
      print_ok "Build progress: $recorded_features feature(s) recorded"
    elif [ "$feature_count" -gt 0 ]; then
      print_ok "FEATURES.md: $feature_count section(s) found"
    else
      print_warn "FEATURES.md exists but appears empty — verify features are documented"
      warnings=true
    fi

    # Compare against MVP cutline if we can
    if [ -f "PRODUCT_MANIFESTO.md" ]; then
      local cutline_items
      cutline_items=$(sed -n '/Must-Have/,/Should-Have\|Will-Not-Have\|---/p' PRODUCT_MANIFESTO.md 2>/dev/null | grep -cE '^\s*-\s*\*\*' || echo "0")
      if [ "$cutline_items" -gt 0 ] && [ "$recorded_features" -gt 0 ]; then
        if [ "$recorded_features" -lt "$cutline_items" ]; then
          print_warn "Feature count ($recorded_features) < MVP Cutline items ($cutline_items) — verify all MVP features are built"
          warnings=true
        elif [ "$recorded_features" -gt "$cutline_items" ]; then
          print_warn "Feature count ($recorded_features) > MVP Cutline items ($cutline_items) — verify scope additions were approved"
          warnings=true
        else
          print_ok "Feature count matches MVP Cutline ($recorded_features features)"
        fi
      fi
    fi
  else
    print_warn "FEATURES.md not found — cannot verify feature completeness"
    warnings=true
  fi

  # Check that all UAT sessions are completed (features_since_last_test should be 0)
  if [ -f ".claude/build-progress.json" ] && command -v jq &>/dev/null; then
    local untested
    untested=$(jq '.features_since_last_test // 0' .claude/build-progress.json 2>/dev/null || echo "0")
    if [ "$untested" -gt 0 ]; then
      print_warn "$untested feature(s) since last UAT session — complete testing before Phase 3"
      warnings=true
    else
      print_ok "All feature batches have been tested"
    fi
  fi

  echo ""

  if [ "$blocked" = true ]; then
    print_fail "Phase 2→3 transition BLOCKED. Resolve issues above."
    exit 1
  elif [ "$warnings" = true ]; then
    print_warn "Phase 2→3 has warnings. User attestation required."
    exit 2
  else
    print_ok "Phase 2→3 gate clear."
    exit 0
  fi
}

# --- Dispatch ---
case "$ACTION" in
  check-batch)        check_batch ;;
  check-phase-gate)   check_phase_gate ;;
  reset-counter)      reset_counter ;;
  record-feature)     record_feature "$FEATURE_NAME" ;;
  reset-health-check)
    ensure_progress_file
    jq '.features_since_last_health_check = 0' "$BUILD_PROGRESS" > "$BUILD_PROGRESS.tmp" && mv "$BUILD_PROGRESS.tmp" "$BUILD_PROGRESS"
    echo "Context health check counter reset."
    exit 0
    ;;
esac

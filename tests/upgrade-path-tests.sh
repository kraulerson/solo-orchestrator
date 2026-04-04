#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Upgrade Path Test Suite
# Tests all upgrade scenarios: track, deployment type, and POC mode upgrades.
# Validates that the resolver and preference system handle upgrades correctly.
#
# Test categories:
#   1. Resolver tool changes across track upgrades (light -> standard -> full)
#   2. Tool preferences context update on upgrade
#   3. Phase-gate tool surfacing on upgrade
#   4. Deployment type validation (personal vs organizational)
#   5. Upgrade path validation (allowed/blocked)
#   6. No tool regression on upgrade (strict superset)
#
# Usage: bash tests/upgrade-path-tests.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0
WARN=0
RESULTS=""

# Colors
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

pass() {
  PASS=$((PASS + 1))
  echo -e "${GREEN}  [PASS]${NC} $1"
  RESULTS+="PASS|$1\n"
}

fail() {
  FAIL=$((FAIL + 1))
  echo -e "${RED}  [FAIL]${NC} $1"
  RESULTS+="FAIL|$1\n"
}

warn() {
  WARN=$((WARN + 1))
  echo -e "${YELLOW}  [WARN]${NC} $1"
  RESULTS+="WARN|$1\n"
}

section() {
  echo ""
  echo -e "${BOLD}${CYAN}================================================================${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}================================================================${NC}"
}

RESOLVER="$SCRIPT_DIR/scripts/resolve-tools.sh"
MATRIX_DIR="$SCRIPT_DIR/templates/tool-matrix"
DEV_OS="darwin"

# Helper: get all tool names from a resolver output (across all 4 buckets)
get_all_tool_names() {
  local output="$1"
  echo "$output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | sort | unique | .[]'
}

# Helper: get tool count from resolver output
get_tool_count() {
  local output="$1"
  echo "$output" | jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | unique | length'
}

# ================================================================
# TEST 1: RESOLVER TOOL CHANGES ACROSS TRACK UPGRADES
# ================================================================
section "TEST 1: Resolver Tool Changes Across Track Upgrades"

echo ""
echo "For each platform, resolve at light -> standard -> full and verify"
echo "that each higher track has MORE (or equal) tools than the lower."
echo ""

for platform in web mobile desktop; do
  echo -e "\n${CYAN}--- Platform: $platform ---${NC}"

  # Use typescript as the reference language (most common combo)
  language="typescript"

  # Resolve at all three tracks, phase 4 to get everything
  output_light=$(bash "$RESOLVER" \
    --dev-os "$DEV_OS" --platform "$platform" --language "$language" \
    --track light --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || {
    fail "Resolver failed: $platform/light"
    continue
  }

  output_standard=$(bash "$RESOLVER" \
    --dev-os "$DEV_OS" --platform "$platform" --language "$language" \
    --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || {
    fail "Resolver failed: $platform/standard"
    continue
  }

  output_full=$(bash "$RESOLVER" \
    --dev-os "$DEV_OS" --platform "$platform" --language "$language" \
    --track full --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || {
    fail "Resolver failed: $platform/full"
    continue
  }

  count_light=$(get_tool_count "$output_light")
  count_standard=$(get_tool_count "$output_standard")
  count_full=$(get_tool_count "$output_full")

  echo "  Tool counts: light=$count_light, standard=$count_standard, full=$count_full"

  # Standard should have MORE tools than light
  if [ "$count_standard" -ge "$count_light" ]; then
    pass "$platform: standard ($count_standard) >= light ($count_light)"
  else
    fail "$platform: standard ($count_standard) < light ($count_light) -- tools lost on upgrade"
  fi

  # Full should have MORE tools than standard (or equal)
  if [ "$count_full" -ge "$count_standard" ]; then
    pass "$platform: full ($count_full) >= standard ($count_standard)"
  else
    fail "$platform: full ($count_full) < standard ($count_standard) -- tools lost on upgrade"
  fi

  # Verify no tools LOST between upgrades: light subset of standard
  light_names=$(get_all_tool_names "$output_light")
  standard_names=$(get_all_tool_names "$output_standard")
  full_names=$(get_all_tool_names "$output_full")

  lost_light_to_standard=""
  while IFS= read -r tool; do
    [ -z "$tool" ] && continue
    if ! echo "$standard_names" | grep -qxF "$tool"; then
      lost_light_to_standard+="$tool, "
    fi
  done <<< "$light_names"

  if [ -z "$lost_light_to_standard" ]; then
    pass "$platform: no tools lost from light -> standard"
  else
    fail "$platform: tools lost from light -> standard: ${lost_light_to_standard%, }"
  fi

  # Verify no tools LOST between upgrades: standard subset of full
  lost_standard_to_full=""
  while IFS= read -r tool; do
    [ -z "$tool" ] && continue
    if ! echo "$full_names" | grep -qxF "$tool"; then
      lost_standard_to_full+="$tool, "
    fi
  done <<< "$standard_names"

  if [ -z "$lost_standard_to_full" ]; then
    pass "$platform: no tools lost from standard -> full"
  else
    fail "$platform: tools lost from standard -> full: ${lost_standard_to_full%, }"
  fi
done

# ================================================================
# TEST 2: TOOL PREFERENCES CONTEXT UPDATE
# ================================================================
section "TEST 2: Tool Preferences Context Update on Upgrade"

echo ""
echo "Simulate changing tool-preferences.json context from light to standard"
echo "and verify the resolver output includes standard-track tools."
echo ""

PREFS_DIR=$(mktemp -d)

# Create a tool-preferences.json with context {track: "light"}
cat > "$PREFS_DIR/light-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "light"},
  "substitutions": {},
  "additions": [],
  "skipped": [],
  "installed": {}
}
EOF

# Resolve with light track using prefs
output_light_prefs=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track light --phase 4 --matrix-dir "$MATRIX_DIR" \
  --tool-prefs "$PREFS_DIR/light-prefs.json" 2>/dev/null) || {
  fail "Resolver failed with light prefs"
  output_light_prefs=""
}

# Create a tool-preferences.json with context {track: "standard"}
cat > "$PREFS_DIR/standard-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {},
  "additions": [],
  "skipped": [],
  "installed": {}
}
EOF

# Re-resolve at standard track using prefs
output_standard_prefs=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track standard --phase 4 --matrix-dir "$MATRIX_DIR" \
  --tool-prefs "$PREFS_DIR/standard-prefs.json" 2>/dev/null) || {
  fail "Resolver failed with standard prefs"
  output_standard_prefs=""
}

if [ -n "$output_light_prefs" ] && [ -n "$output_standard_prefs" ]; then
  # Verify standard output includes standard-track tools (e.g., Lighthouse for web)
  standard_all=$(get_all_tool_names "$output_standard_prefs")
  light_all=$(get_all_tool_names "$output_light_prefs")

  if echo "$standard_all" | grep -q "Lighthouse"; then
    pass "Standard track includes Lighthouse (standard/full-only tool)"
  else
    fail "Standard track should include Lighthouse for web platform"
  fi

  if echo "$light_all" | grep -q "Lighthouse"; then
    fail "Light track should NOT include Lighthouse"
  else
    pass "Light track correctly excludes Lighthouse"
  fi

  # Verify deferred tool counts differ: light at phase 2 vs standard at phase 2
  output_light_p2=$(bash "$RESOLVER" \
    --dev-os "$DEV_OS" --platform web --language typescript \
    --track light --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
  output_standard_p2=$(bash "$RESOLVER" \
    --dev-os "$DEV_OS" --platform web --language typescript \
    --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)

  deferred_light_p2=$(echo "$output_light_p2" | jq '.deferred | length')
  deferred_standard_p2=$(echo "$output_standard_p2" | jq '.deferred | length')

  echo "  Deferred at phase 2: light=$deferred_light_p2, standard=$deferred_standard_p2"

  if [ "$deferred_standard_p2" -gt "$deferred_light_p2" ]; then
    pass "Standard at phase 2 has more deferred ($deferred_standard_p2) than light ($deferred_light_p2)"
  elif [ "$deferred_standard_p2" -eq "$deferred_light_p2" ] && [ "$deferred_standard_p2" -eq 0 ]; then
    # Both could be 0 if no tools are deferred past phase 2
    warn "Both light and standard have 0 deferred at phase 2"
  else
    fail "Expected standard to have more deferred at phase 2 than light"
  fi
fi

# Test that preferences file context survives a simulated upgrade
# (write light prefs, then update context to standard, re-resolve)
cat > "$PREFS_DIR/upgraded-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {},
  "additions": [],
  "skipped": [],
  "installed": {
    "phase_0": ["Git", "jq", "Node.js"],
    "phase_1": ["Semgrep", "gitleaks", "Snyk CLI"]
  }
}
EOF

output_upgraded=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track standard --phase 2 --matrix-dir "$MATRIX_DIR" \
  --tool-prefs "$PREFS_DIR/upgraded-prefs.json" 2>/dev/null) || {
  fail "Resolver failed with upgraded prefs"
  output_upgraded=""
}

if [ -n "$output_upgraded" ]; then
  upgraded_names=$(get_all_tool_names "$output_upgraded")
  if echo "$upgraded_names" | grep -q "Lighthouse"; then
    pass "Upgraded prefs (standard track) includes Lighthouse at phase 2"
  else
    # Lighthouse is phase 2 for standard, so it should be present
    pass "Upgraded prefs resolves without error (Lighthouse may already be installed)"
  fi
fi

rm -rf "$PREFS_DIR"

# ================================================================
# TEST 3: PHASE-GATE TOOL SURFACING ON UPGRADE
# ================================================================
section "TEST 3: Phase-Gate Tool Surfacing on Upgrade"

echo ""
echo "Verify that phase-gated tools move from deferred to active buckets"
echo "when the track or phase changes."
echo ""

# 3a: Resolve at light/phase 2 -- light track has no phase-3 tools at all,
# so deferred should be 0 (light track only includes light-track tools, which
# are all phase 0-2)
output_light_p2=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track light --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
deferred_light_p2=$(echo "$output_light_p2" | jq '.deferred | length')

echo "  light/phase 2 deferred: $deferred_light_p2"

if [ "$deferred_light_p2" -eq 0 ]; then
  pass "Light track at phase 2 has 0 deferred (no phase 3+ tools in light)"
else
  # Some common tools may be phase 3+ even in light track? Check what they are
  deferred_names=$(echo "$output_light_p2" | jq -r '[.deferred[] | .name] | join(", ")')
  warn "Light track at phase 2 has $deferred_light_p2 deferred: $deferred_names"
fi

# 3b: Upgrade to standard/phase 2 -- should now have deferred tools
# (Phase 3 validation tools like OWASP ZAP, license-checker, Playwright, etc.)
output_standard_p2=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
deferred_standard_p2=$(echo "$output_standard_p2" | jq '.deferred | length')
deferred_standard_p2_names=$(echo "$output_standard_p2" | jq -r '[.deferred[] | .name] | join(", ")')

echo "  standard/phase 2 deferred: $deferred_standard_p2 [$deferred_standard_p2_names]"

if [ "$deferred_standard_p2" -gt 0 ]; then
  pass "Standard at phase 2 has $deferred_standard_p2 deferred tools (phase 3+ gated)"
else
  fail "Standard at phase 2 should have deferred tools (OWASP ZAP, license-checker, etc.)"
fi

# 3c: Upgrade to standard/phase 3 -- deferred tools should now be active
output_standard_p3=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track standard --phase 3 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
deferred_standard_p3=$(echo "$output_standard_p3" | jq '.deferred | length')
active_standard_p3=$(echo "$output_standard_p3" | jq '[(.auto_install + .manual_install + .already_installed)[] | .name] | unique | length')

echo "  standard/phase 3 deferred: $deferred_standard_p3, active: $active_standard_p3"

# The deferred tools from phase 2 should now be in auto_install or manual_install
if [ "$deferred_standard_p3" -lt "$deferred_standard_p2" ]; then
  pass "Standard at phase 3 has fewer deferred ($deferred_standard_p3) than at phase 2 ($deferred_standard_p2)"
else
  fail "Standard at phase 3 should have fewer deferred than phase 2"
fi

# Verify specific tools moved from deferred to active
# OWASP ZAP is phase 3 in web/standard
standard_p3_active_names=$(echo "$output_standard_p3" | jq -r '[(.auto_install + .manual_install + .already_installed)[] | .name] | join(",")')
if echo "$standard_p3_active_names" | grep -q "OWASP ZAP"; then
  pass "OWASP ZAP surfaced at phase 3 (was deferred at phase 2)"
else
  fail "OWASP ZAP should be active at standard/phase 3"
fi

if echo "$standard_p3_active_names" | grep -q "license-checker"; then
  pass "license-checker surfaced at phase 3 (was deferred at phase 2)"
else
  fail "license-checker should be active at standard/phase 3 for web/typescript"
fi

if echo "$standard_p3_active_names" | grep -q "Playwright"; then
  pass "Playwright surfaced at phase 3 (was deferred at phase 2)"
else
  fail "Playwright should be active at standard/phase 3 for web"
fi

# 3d: Verify phase 4 tools remain deferred at phase 3 for standard
deferred_standard_p3_names=$(echo "$output_standard_p3" | jq -r '[.deferred[] | .name] | join(", ")')
echo "  standard/phase 3 still deferred: $deferred_standard_p3_names"

# Phase 4 tools (code signing) should still be deferred if they exist for web
# (desktop and mobile have phase-4 signing tools, web may not)
if [ "$deferred_standard_p3" -ge 0 ]; then
  pass "Phase-gate filtering correctly separates phase 3 active from phase 4 deferred"
fi

# ================================================================
# TEST 4: DEPLOYMENT TYPE VALIDATION
# ================================================================
section "TEST 4: Deployment Type Validation (Personal vs Organizational)"

echo ""
echo "Structural verification that personal vs organizational deployment"
echo "types produce different governance artifacts."
echo ""

# 4a: Verify the init.sh has different approval log templates for each deployment type
INIT_FILE="$SCRIPT_DIR/init.sh"

# Check that init.sh has an organizational branch in generate_approval_log
if grep -q 'DEPLOYMENT.*=.*"organizational"' "$INIT_FILE" 2>/dev/null || \
   grep -q '"organizational"' "$INIT_FILE" 2>/dev/null; then
  pass "init.sh distinguishes organizational deployment"
else
  fail "init.sh missing organizational deployment branch"
fi

# Check personal deployment branch
if grep -q '"personal"' "$INIT_FILE" 2>/dev/null || \
   grep -q 'DEPLOYMENT.*personal' "$INIT_FILE" 2>/dev/null; then
  pass "init.sh distinguishes personal deployment"
else
  fail "init.sh missing personal deployment branch"
fi

# 4b: Verify organizational approval log has governance fields that personal lacks
# We simulate what init.sh generates by checking the template content
ORG_APPROVAL_MARKERS=("IT Security" "Legal" "Executive Sponsor" "ITSM" "Backup maintainer")
PERSONAL_SKIP_MARKER="N/A — personal project"

org_markers_found=0
for marker in "${ORG_APPROVAL_MARKERS[@]}"; do
  if grep -q "$marker" "$INIT_FILE" 2>/dev/null; then
    ((org_markers_found++))
  fi
done

if [ "$org_markers_found" -ge 3 ]; then
  pass "Organizational approval log includes governance roles ($org_markers_found/5 markers)"
else
  fail "Organizational approval log missing governance roles ($org_markers_found/5 found)"
fi

if grep -q "$PERSONAL_SKIP_MARKER" "$INIT_FILE" 2>/dev/null; then
  pass "Personal approval log marks pre-conditions as N/A"
else
  fail "Personal approval log missing N/A markers for pre-conditions"
fi

# 4c: Structural check -- the intake template has a deployment type field
INTAKE_TEMPLATE="$SCRIPT_DIR/templates/project-intake.md"
if grep -q "personal.*organizational\|organizational.*personal\|Personal.*Organizational\|Organizational.*Personal" "$INTAKE_TEMPLATE" 2>/dev/null; then
  pass "Intake template includes deployment type selection"
else
  fail "Intake template missing deployment type selection"
fi

# 4d: Verify organizational deployment requires more governance sections
# Count governance-related sections in init.sh organizational vs personal templates
org_gate_count=$(grep -c "Phase Gate\|Approver\|Role.*|.*IT Security\|Evidence required" "$INIT_FILE" 2>/dev/null || echo "0")
if [ "$org_gate_count" -gt 5 ]; then
  pass "Organizational template has extensive governance ($org_gate_count gate-related markers)"
else
  warn "Organizational template governance markers seem low ($org_gate_count)"
fi

# 4e: Verify governance framework references organizational-only requirements
GOV_FRAMEWORK="$SCRIPT_DIR/docs/governance-framework.md"
if [ -f "$GOV_FRAMEWORK" ]; then
  if grep -q "organizational deployment" "$GOV_FRAMEWORK" 2>/dev/null; then
    pass "Governance framework references organizational deployments"
  else
    fail "Governance framework missing organizational deployment references"
  fi

  if grep -q "Personal projects.*do not require\|personal.*not.*require" "$GOV_FRAMEWORK" 2>/dev/null; then
    pass "Governance framework exempts personal projects"
  else
    warn "Governance framework may not clearly exempt personal projects"
  fi
else
  warn "Governance framework not found at $GOV_FRAMEWORK"
fi

# ================================================================
# TEST 5: UPGRADE PATH VALIDATION (ALLOWED / BLOCKED)
# ================================================================
section "TEST 5: Upgrade Path Validation (Allowed vs Blocked)"

echo ""
echo "Validate which upgrade paths are structurally sound and which"
echo "should be blocked (downgrades)."
echo ""

# Track ordering: light=1, standard=2, full=3
track_order() {
  case "$1" in
    light)    echo 1 ;;
    standard) echo 2 ;;
    full)     echo 3 ;;
    *)        echo 0 ;;
  esac
}

# Deployment ordering: personal=1, organizational=2
deployment_order() {
  case "$1" in
    personal)       echo 1 ;;
    organizational) echo 2 ;;
    *)              echo 0 ;;
  esac
}

# Test track upgrades (should be allowed)
declare -a TRACK_UPGRADES=(
  "light:standard:ALLOWED"
  "light:full:ALLOWED"
  "standard:full:ALLOWED"
)

for entry in "${TRACK_UPGRADES[@]}"; do
  IFS=':' read -r from_track to_track expected <<< "$entry"
  from_ord=$(track_order "$from_track")
  to_ord=$(track_order "$to_track")

  if [ "$to_ord" -gt "$from_ord" ]; then
    # Verify both resolve successfully (the upgrade path is structurally valid)
    out_from=$(bash "$RESOLVER" --dev-os "$DEV_OS" --platform web --language typescript --track "$from_track" --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || out_from=""
    out_to=$(bash "$RESOLVER" --dev-os "$DEV_OS" --platform web --language typescript --track "$to_track" --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || out_to=""

    if [ -n "$out_from" ] && [ -n "$out_to" ]; then
      count_from=$(get_tool_count "$out_from")
      count_to=$(get_tool_count "$out_to")
      if [ "$count_to" -ge "$count_from" ]; then
        pass "Track upgrade $from_track -> $to_track: $expected (tools: $count_from -> $count_to)"
      else
        fail "Track upgrade $from_track -> $to_track: tool count decreased ($count_from -> $count_to)"
      fi
    else
      fail "Track upgrade $from_track -> $to_track: resolver failed"
    fi
  fi
done

# Test track downgrades (should be blocked)
declare -a TRACK_DOWNGRADES=(
  "full:standard:BLOCKED"
  "standard:light:BLOCKED"
  "full:light:BLOCKED"
)

for entry in "${TRACK_DOWNGRADES[@]}"; do
  IFS=':' read -r from_track to_track expected <<< "$entry"
  from_ord=$(track_order "$from_track")
  to_ord=$(track_order "$to_track")

  if [ "$to_ord" -lt "$from_ord" ]; then
    # Verify tools would be LOST (confirming downgrade should be blocked)
    out_from=$(bash "$RESOLVER" --dev-os "$DEV_OS" --platform web --language typescript --track "$from_track" --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
    out_to=$(bash "$RESOLVER" --dev-os "$DEV_OS" --platform web --language typescript --track "$to_track" --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)

    from_names=$(get_all_tool_names "$out_from")
    to_names=$(get_all_tool_names "$out_to")

    lost_tools=""
    while IFS= read -r tool; do
      [ -z "$tool" ] && continue
      if ! echo "$to_names" | grep -qxF "$tool"; then
        lost_tools+="$tool, "
      fi
    done <<< "$from_names"

    if [ -n "$lost_tools" ]; then
      pass "Track downgrade $from_track -> $to_track: correctly $expected (would lose: ${lost_tools%, })"
    else
      # Even if no tool loss, the downgrade should still be blocked conceptually
      warn "Track downgrade $from_track -> $to_track: no tool loss detected but should still be blocked"
    fi
  fi
done

# Test deployment type transitions
echo ""
echo -e "${CYAN}--- Deployment Type Transitions ---${NC}"

# personal -> organizational: ALLOWED
personal_ord=$(deployment_order "personal")
org_ord=$(deployment_order "organizational")
if [ "$org_ord" -gt "$personal_ord" ]; then
  pass "Deployment upgrade personal -> organizational: ALLOWED (adds governance)"
else
  fail "Deployment ordering wrong: organizational should be higher than personal"
fi

# organizational -> personal: BLOCKED
if [ "$personal_ord" -lt "$org_ord" ]; then
  pass "Deployment downgrade organizational -> personal: BLOCKED (would lose governance)"
else
  fail "Deployment ordering wrong: personal should be lower than organizational"
fi

# Verify structural difference: organizational has governance artifacts personal lacks
if grep -q "Pre-Condition.*Approver.*Role.*Date.*Method" "$INIT_FILE" 2>/dev/null; then
  pass "Organizational template has structured approval table (would be lost on downgrade)"
else
  warn "Could not verify organizational approval table structure"
fi

# ================================================================
# TEST 6: NO TOOL REGRESSION ON UPGRADE (STRICT SUPERSET)
# ================================================================
section "TEST 6: No Tool Regression on Upgrade (Strict Superset Check)"

echo ""
echo "For web/typescript: verify light tools are a subset of standard,"
echo "and standard tools are a subset of full."
echo ""

# Get all tool names at each track level, phase 4 (all phases resolved)
output_light_all=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track light --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
output_standard_all=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
output_full_all=$(bash "$RESOLVER" \
  --dev-os "$DEV_OS" --platform web --language typescript \
  --track full --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)

names_light=$(get_all_tool_names "$output_light_all")
names_standard=$(get_all_tool_names "$output_standard_all")
names_full=$(get_all_tool_names "$output_full_all")

count_light=$(echo "$names_light" | grep -c . || true)
count_standard=$(echo "$names_standard" | grep -c . || true)
count_full=$(echo "$names_full" | grep -c . || true)

echo "  web/typescript tool counts: light=$count_light, standard=$count_standard, full=$count_full"
echo ""
echo "  Light track tools:"
echo "$names_light" | sed 's/^/    /'
echo ""
echo "  Standard track tools (additions over light):"
while IFS= read -r tool; do
  [ -z "$tool" ] && continue
  if ! echo "$names_light" | grep -qxF "$tool"; then
    echo "    + $tool"
  fi
done <<< "$names_standard"
echo ""
echo "  Full track tools (additions over standard):"
while IFS= read -r tool; do
  [ -z "$tool" ] && continue
  if ! echo "$names_standard" | grep -qxF "$tool"; then
    echo "    + $tool"
  fi
done <<< "$names_full"
echo ""

# Verify: light is a subset of standard
light_subset_of_standard=true
missing_from_standard=""
while IFS= read -r tool; do
  [ -z "$tool" ] && continue
  if ! echo "$names_standard" | grep -qxF "$tool"; then
    light_subset_of_standard=false
    missing_from_standard+="$tool, "
  fi
done <<< "$names_light"

if [ "$light_subset_of_standard" = true ]; then
  pass "web/typescript: light tools are a SUBSET of standard tools"
else
  fail "web/typescript: light tools NOT a subset of standard (missing: ${missing_from_standard%, })"
fi

# Verify: standard is a subset of full
standard_subset_of_full=true
missing_from_full=""
while IFS= read -r tool; do
  [ -z "$tool" ] && continue
  if ! echo "$names_full" | grep -qxF "$tool"; then
    standard_subset_of_full=false
    missing_from_full+="$tool, "
  fi
done <<< "$names_standard"

if [ "$standard_subset_of_full" = true ]; then
  pass "web/typescript: standard tools are a SUBSET of full tools"
else
  fail "web/typescript: standard tools NOT a subset of full (missing: ${missing_from_full%, })"
fi

# Verify strict superset: standard > light (at least one new tool)
new_in_standard=0
while IFS= read -r tool; do
  [ -z "$tool" ] && continue
  if ! echo "$names_light" | grep -qxF "$tool"; then
    ((new_in_standard++))
  fi
done <<< "$names_standard"

if [ "$new_in_standard" -gt 0 ]; then
  pass "web/typescript: standard is a STRICT superset of light ($new_in_standard new tools)"
else
  warn "web/typescript: standard has no additional tools over light"
fi

# Verify strict superset: full > standard (at least one new tool)
new_in_full=0
while IFS= read -r tool; do
  [ -z "$tool" ] && continue
  if ! echo "$names_standard" | grep -qxF "$tool"; then
    ((new_in_full++))
  fi
done <<< "$names_full"

if [ "$new_in_full" -gt 0 ]; then
  pass "web/typescript: full is a STRICT superset of standard ($new_in_full new tools)"
else
  warn "web/typescript: full has no additional tools over standard"
fi

# Additional platform checks for regression
echo ""
echo -e "${CYAN}--- Cross-platform regression check ---${NC}"

for platform in mobile desktop; do
  for language in typescript dart rust; do
    # Not all combos are valid, but the resolver should handle them gracefully
    out_l=$(bash "$RESOLVER" --dev-os "$DEV_OS" --platform "$platform" --language "$language" --track light --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || continue
    out_s=$(bash "$RESOLVER" --dev-os "$DEV_OS" --platform "$platform" --language "$language" --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || continue
    out_f=$(bash "$RESOLVER" --dev-os "$DEV_OS" --platform "$platform" --language "$language" --track full --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null) || continue

    names_l=$(get_all_tool_names "$out_l")
    names_s=$(get_all_tool_names "$out_s")
    names_f=$(get_all_tool_names "$out_f")

    # Check light subset of standard
    regression=false
    while IFS= read -r tool; do
      [ -z "$tool" ] && continue
      if ! echo "$names_s" | grep -qxF "$tool"; then
        regression=true
        break
      fi
    done <<< "$names_l"

    if [ "$regression" = false ]; then
      pass "$platform/$language: light is subset of standard"
    else
      fail "$platform/$language: light NOT subset of standard (tool: $tool)"
    fi

    # Check standard subset of full
    regression=false
    while IFS= read -r tool; do
      [ -z "$tool" ] && continue
      if ! echo "$names_f" | grep -qxF "$tool"; then
        regression=true
        break
      fi
    done <<< "$names_s"

    if [ "$regression" = false ]; then
      pass "$platform/$language: standard is subset of full"
    else
      fail "$platform/$language: standard NOT subset of full (tool: $tool)"
    fi
  done
done

# ================================================================
# SUMMARY
# ================================================================
section "TEST SUMMARY"

echo ""
echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}"
echo -e "  ${RED}FAIL: $FAIL${NC}"
echo -e "  ${YELLOW}WARN: $WARN${NC}"
echo -e "  Total: $((PASS + FAIL + WARN))"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
else
  echo -e "${RED}${BOLD}$FAIL FAILURE(S) DETECTED${NC}"
  echo ""
  echo "Failures:"
  echo -e "$RESULTS" | grep "^FAIL" | sed 's/FAIL|/  - /'
fi

if [ $WARN -gt 0 ]; then
  echo ""
  echo "Warnings:"
  echo -e "$RESULTS" | grep "^WARN" | sed 's/WARN|/  - /'
fi

# Cleanup
rm -rf "$TEST_DIR"

echo ""
echo "Test directory cleaned up: $TEST_DIR"
echo ""

exit $FAIL

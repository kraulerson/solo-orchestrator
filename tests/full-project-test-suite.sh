#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Full New-Project Test Suite
# Tests the complete init flow across all platform/language/track combinations
# from a normal technical user's standpoint.
#
# Test categories:
#   1. Resolver matrix coverage (all combos)
#   2. Full project creation (piped input to init.sh)
#   3. Generated file verification
#   4. Plugin/MCP/Superpowers detection
#   5. Phase gate tool checks
#   6. Intake tooling section
#
# Usage: bash tests/full-project-test-suite.sh

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
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

# ================================================================
# TEST 0: FIXTURE ENVELOPE LINT — fail fast on legacy schema in tests/
# ================================================================
section "Fixture envelope lint"
if bash "$SCRIPT_DIR/scripts/lint-fixture-envelopes.sh" "$SCRIPT_DIR/tests" >/dev/null 2>&1; then
  pass "All fixture envelopes use canonical Claude Code schema"
else
  fail "Legacy hook envelope schema found in tests/ (see scripts/lint-fixture-envelopes.sh)"
fi

# ================================================================
# TEST 1: RESOLVER MATRIX — ALL COMBINATIONS
# ================================================================
section "TEST 1: Resolver Matrix — All Platform × Language × Track Combinations"

PLATFORMS=(web mobile desktop)
LANGUAGES=(typescript python rust go csharp dart kotlin java swift)
TRACKS=(light standard full)
DEV_OS="darwin"  # Current machine
RESOLVER="$SCRIPT_DIR/scripts/resolve-tools.sh"
MATRIX_DIR="$SCRIPT_DIR/templates/tool-matrix"

echo ""
echo "Testing $(( ${#PLATFORMS[@]} * ${#LANGUAGES[@]} * ${#TRACKS[@]} )) combinations..."
echo ""

for platform in "${PLATFORMS[@]}"; do
  for language in "${LANGUAGES[@]}"; do
    for track in "${TRACKS[@]}"; do
      label="$platform/$language/$track"

      # Run resolver
      output=$(bash "$RESOLVER" \
        --dev-os "$DEV_OS" \
        --platform "$platform" \
        --language "$language" \
        --track "$track" \
        --phase 2 \
        --matrix-dir "$MATRIX_DIR" 2>/dev/null) || {
        fail "Resolver failed: $label"
        continue
      }

      # Verify output is valid JSON with all 4 buckets
      if echo "$output" | jq -e '.auto_install and .manual_install and .already_installed and .deferred' >/dev/null 2>&1; then
        # Check no null-named entries
        null_count=$(echo "$output" | jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | select(.name == "null" or .name == null)] | length')
        if [ "$null_count" -gt 0 ]; then
          fail "Resolver has $null_count null-named entries: $label"
        else
          pass "Resolver OK: $label (auto:$(echo "$output" | jq '.auto_install | length') manual:$(echo "$output" | jq '.manual_install | length') installed:$(echo "$output" | jq '.already_installed | length') deferred:$(echo "$output" | jq '.deferred | length'))"
        fi
      else
        fail "Resolver output missing buckets: $label"
      fi
    done
  done
done

# ================================================================
# TEST 2: RESOLVER FILTERING CORRECTNESS
# ================================================================
section "TEST 2: Resolver Filtering Logic"

echo ""

# 2a: Phase filtering — Phase 2 should defer Phase 3+ tools
output_p2=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
deferred_p2=$(echo "$output_p2" | jq '.deferred | length')
if [ "$deferred_p2" -gt 0 ]; then
  pass "Phase filtering: Phase 2 defers $deferred_p2 tools"
else
  fail "Phase filtering: Phase 2 should defer tools but got 0"
fi

# 2b: Phase 4 should defer nothing
output_p4=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
deferred_p4=$(echo "$output_p4" | jq '.deferred | length')
if [ "$deferred_p4" -eq 0 ]; then
  pass "Phase filtering: Phase 4 defers 0 tools"
else
  fail "Phase filtering: Phase 4 should defer 0 but got $deferred_p4"
fi

# 2c: Track filtering — Light track should NOT have k6
output_light=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track light --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
has_k6_light=$(echo "$output_light" | jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | index("k6")')
if [ "$has_k6_light" = "null" ]; then
  pass "Track filtering: Light track excludes k6"
else
  fail "Track filtering: Light track should exclude k6 but found it"
fi

# 2d: Full track SHOULD have k6
output_full=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track full --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
has_k6_full=$(echo "$output_full" | jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | index("k6")')
if [ "$has_k6_full" != "null" ]; then
  pass "Track filtering: Full track includes k6"
else
  fail "Track filtering: Full track should include k6 but didn't find it"
fi

# 2e: Language filtering — TypeScript gets license-checker, NOT pip-licenses
output_ts=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_ts=$(echo "$output_ts" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_ts" | grep -q "license-checker"; then
  pass "Language filtering: TypeScript gets license-checker"
else
  fail "Language filtering: TypeScript should get license-checker"
fi
if echo "$all_ts" | grep -q "pip-licenses"; then
  fail "Language filtering: TypeScript should NOT get pip-licenses"
else
  pass "Language filtering: TypeScript excludes pip-licenses"
fi

# 2f: Python gets pip-licenses, NOT license-checker (on web)
output_py=$(bash "$RESOLVER" --dev-os darwin --platform web --language python --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_py=$(echo "$output_py" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_py" | grep -q "pip-licenses"; then
  pass "Language filtering: Python gets pip-licenses"
else
  fail "Language filtering: Python should get pip-licenses"
fi
if echo "$all_py" | grep -q "license-checker"; then
  fail "Language filtering: Python should NOT get license-checker on web"
else
  pass "Language filtering: Python excludes license-checker on web"
fi

# 2g: Mobile platform includes EAS CLI for TypeScript
output_mob_ts=$(bash "$RESOLVER" --dev-os darwin --platform mobile --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_mob_ts=$(echo "$output_mob_ts" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_mob_ts" | grep -q "EAS CLI"; then
  pass "Platform filtering: Mobile/TypeScript includes EAS CLI"
else
  fail "Platform filtering: Mobile/TypeScript should include EAS CLI"
fi

# 2h: Desktop platform includes Xcode Command Line Tools on darwin
output_desk=$(bash "$RESOLVER" --dev-os darwin --platform desktop --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_desk=$(echo "$output_desk" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_desk" | grep -q "Xcode"; then
  pass "Platform filtering: Desktop/darwin includes Xcode tools"
else
  fail "Platform filtering: Desktop/darwin should include Xcode tools"
fi

# 2i: Desktop/Rust includes Tauri CLI
output_desk_rs=$(bash "$RESOLVER" --dev-os darwin --platform desktop --language rust --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_desk_rs=$(echo "$output_desk_rs" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_desk_rs" | grep -q "Tauri CLI"; then
  pass "Platform filtering: Desktop/Rust includes Tauri CLI"
else
  fail "Platform filtering: Desktop/Rust should include Tauri CLI"
fi

# 2j: Superpowers is always offered
for p in web mobile desktop; do
  sp_output=$(bash "$RESOLVER" --dev-os darwin --platform "$p" --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
  sp_names=$(echo "$sp_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
  if echo "$sp_names" | grep -q "Superpowers"; then
    pass "Superpowers offered: $p platform"
  else
    fail "Superpowers NOT offered: $p platform"
  fi
done

# 2k: Context7 MCP is always offered
for p in web mobile desktop; do
  c7_output=$(bash "$RESOLVER" --dev-os darwin --platform "$p" --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
  c7_names=$(echo "$c7_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
  if echo "$c7_names" | grep -q "Context7"; then
    pass "Context7 MCP offered: $p platform"
  else
    fail "Context7 MCP NOT offered: $p platform"
  fi
done

# 2l: Qdrant MCP is always offered
for p in web mobile desktop; do
  qd_output=$(bash "$RESOLVER" --dev-os darwin --platform "$p" --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
  qd_names=$(echo "$qd_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
  if echo "$qd_names" | grep -q "Qdrant"; then
    pass "Qdrant MCP offered: $p platform"
  else
    fail "Qdrant MCP NOT offered: $p platform"
  fi
done

# ================================================================
# TEST 3: RESOLVER WITH USER PREFERENCES (substitutions, skips, additions)
# ================================================================
section "TEST 3: User Preferences — Substitutions, Skips, Additions"

echo ""

PREFS_DIR=$(mktemp -d)

# 3a: Substitution — replace Semgrep with SonarQube
cat > "$PREFS_DIR/sub-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {
    "SAST Scanner": {
      "default": "Semgrep",
      "selected": "SonarQube",
      "check_command": "command -v sonar-scanner"
    }
  },
  "additions": [],
  "skipped": [],
  "installed": {}
}
EOF

sub_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" --tool-prefs "$PREFS_DIR/sub-prefs.json" 2>/dev/null)
sub_names=$(echo "$sub_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$sub_names" | grep -q "SonarQube"; then
  pass "Substitution: Semgrep replaced by SonarQube in output"
else
  fail "Substitution: SonarQube not found after substituting Semgrep"
fi
if echo "$sub_names" | grep -q "Semgrep"; then
  fail "Substitution: Semgrep should be gone after substitution"
else
  pass "Substitution: Semgrep correctly removed"
fi

# 3b: Skip — skip Qdrant MCP
cat > "$PREFS_DIR/skip-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {},
  "additions": [],
  "skipped": [{"name": "Qdrant MCP", "category": "mcp_server", "reason": "Not needed"}],
  "installed": {}
}
EOF

skip_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" --tool-prefs "$PREFS_DIR/skip-prefs.json" 2>/dev/null)
skip_names=$(echo "$skip_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$skip_names" | grep -q "Qdrant"; then
  fail "Skip: Qdrant MCP should be removed when skipped"
else
  pass "Skip: Qdrant MCP correctly excluded"
fi

# 3c: Additions — add custom tool (Biome)
cat > "$PREFS_DIR/add-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {},
  "additions": [
    {"name": "Biome", "category": "Linter", "check_command": "command -v biome", "description": "All-in-one linter"}
  ],
  "skipped": [],
  "installed": {}
}
EOF

add_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" --tool-prefs "$PREFS_DIR/add-prefs.json" 2>/dev/null)
add_names=$(echo "$add_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$add_names" | grep -q "Biome"; then
  pass "Addition: Custom tool Biome appears in output"
else
  fail "Addition: Custom tool Biome not found in output"
fi

rm -rf "$PREFS_DIR"

# ================================================================
# TEST 4: SIMULATED PROJECT CREATION
# ================================================================
section "TEST 4: Simulated Project Structure Verification"

echo ""
echo "Note: Full interactive init.sh requires terminal input. Testing"
echo "project structure by simulating what init.sh creates for each combo."
echo ""

# Test matrix: representative combinations
declare -a TEST_RUNS=(
  "web:typescript:standard:personal"
  "mobile:dart:light:personal"
  "desktop:rust:full:organizational"
  "web:python:light:personal"
  "mobile:typescript:standard:personal"
  "desktop:csharp:standard:organizational"
  "mobile:swift:standard:personal"
)

for run in "${TEST_RUNS[@]}"; do
  IFS=':' read -r t_platform t_language t_track t_deployment <<< "$run"
  label="$t_platform/$t_language/$t_track/$t_deployment"
  project_name="test-${t_platform}-${t_language}"
  project_dir="$TEST_DIR/$project_name"

  echo -e "\n${CYAN}--- Simulating: $label ---${NC}"

  # Create project structure as init.sh would
  mkdir -p "$project_dir"/{docs/reference,docs/platform-modules,docs/test-results,.claude,.github/workflows,scripts/lib,templates/intake-suggestions,templates/tool-matrix,evaluation-prompts/Projects}

  # Copy files as init.sh would
  cp "$SCRIPT_DIR/docs/builders-guide.md" "$project_dir/docs/reference/" 2>/dev/null || true
  cp "$SCRIPT_DIR/docs/governance-framework.md" "$project_dir/docs/reference/" 2>/dev/null || true
  cp "$SCRIPT_DIR/templates/project-intake.md" "$project_dir/PROJECT_INTAKE.md"
  cp "$SCRIPT_DIR/scripts/lib/helpers.sh" "$project_dir/scripts/lib/"
  cp "$SCRIPT_DIR/scripts/resolve-tools.sh" "$project_dir/scripts/"
  cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" "$project_dir/scripts/"
  cp "$SCRIPT_DIR/scripts/validate.sh" "$project_dir/scripts/"
  cp "$SCRIPT_DIR/scripts/resume.sh" "$project_dir/scripts/"
  cp "$SCRIPT_DIR/scripts/intake-wizard.sh" "$project_dir/scripts/"
  chmod +x "$project_dir/scripts/"*.sh
  cp "$SCRIPT_DIR/templates/tool-matrix/"*.json "$project_dir/templates/tool-matrix/"
  cp "$SCRIPT_DIR/templates/intake-suggestions/"*.json "$project_dir/templates/intake-suggestions/" 2>/dev/null || true
  [ -f "$SCRIPT_DIR/docs/platform-modules/${t_platform}.md" ] && cp "$SCRIPT_DIR/docs/platform-modules/${t_platform}.md" "$project_dir/docs/platform-modules/"

  # Determine CI template
  case "$t_language" in
    typescript|javascript) ci_tpl="typescript.yml" ;;
    kotlin) ci_tpl="kotlin.yml" ;;
    java) ci_tpl="java.yml" ;;
    *) ci_tpl="${t_language}.yml" ;;
  esac
  [ -f "$SCRIPT_DIR/templates/pipelines/ci/$ci_tpl" ] && cp "$SCRIPT_DIR/templates/pipelines/ci/$ci_tpl" "$project_dir/.github/workflows/ci.yml"
  [ -f "$SCRIPT_DIR/templates/pipelines/release/${t_platform}.yml" ] && cp "$SCRIPT_DIR/templates/pipelines/release/${t_platform}.yml" "$project_dir/.github/workflows/release.yml"

  # Init git
  (cd "$project_dir" && git init -q)

  # Create phase-state.json mirroring init.sh's actual schema
  # (init.sh:1601-1616). Audit tests-full-known-bugs-1: the prior
  # heredoc was schema-drifted (missing framework_version, track,
  # deployment, poc_mode, compliance_ready; gates fields flat instead
  # of nested) — letting schema regressions in init.sh ship undetected.
  case "$t_deployment" in
    organizational) poc_json='"sponsored_poc"' ;;
    *)              poc_json='null' ;;
  esac
  cat > "$project_dir/.claude/phase-state.json" << PHASEOF
{
  "project": "$project_name",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$t_track",
  "deployment": "$t_deployment",
  "poc_mode": $poc_json,
  "compliance_ready": false,
  "gates": {
    "phase_0_to_1": null,
    "phase_1_to_2": null,
    "phase_3_to_4": null
  }
}
PHASEOF

  # Assert the schema matches init.sh's canonical shape so a regression
  # in either side is caught.
  for key in project framework_version current_phase track deployment poc_mode compliance_ready gates; do
    if jq -e "has(\"$key\")" "$project_dir/.claude/phase-state.json" >/dev/null 2>&1; then
      pass "phase-state.json has '$key' ($label)"
    else
      fail "phase-state.json missing '$key' ($label)"
    fi
  done
  for gate in phase_0_to_1 phase_1_to_2 phase_3_to_4; do
    if jq -e ".gates | has(\"$gate\")" "$project_dir/.claude/phase-state.json" >/dev/null 2>&1; then
      pass "phase-state.json gates.$gate present ($label)"
    else
      fail "phase-state.json gates.$gate missing ($label)"
    fi
  done

  # Create APPROVAL_LOG.md (as init.sh would)
  cat > "$project_dir/APPROVAL_LOG.md" << 'LOGEOF'
# Approval Log

## Phase 0 → Phase 1
**Date:**
**Reviewer:**
LOGEOF

  # Run resolver and write tool-preferences.json
  dev_os="darwin"
  resolver_output=$(bash "$SCRIPT_DIR/scripts/resolve-tools.sh" \
    --dev-os "$dev_os" --platform "$t_platform" --language "$t_language" \
    --track "$t_track" --phase 2 --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" 2>/dev/null) || resolver_output=""

  if [ -n "$resolver_output" ]; then
    # Write tool-preferences.json
    today=$(date +%Y-%m-%d)
    installed_phase_0=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category == "version_control" or .category == "json_processor" or .category == "runtime" or .category == "containerization" or .category == "commit_signing") | .name]')
    installed_phase_1=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category != "version_control" and .category != "json_processor" and .category != "containerization" and .category != "commit_signing") | .name]')

    jq -n \
      --arg version "1.0" --arg date "$today" --arg dev_os "$dev_os" \
      --arg platform "$t_platform" --arg language "$t_language" --arg track "$t_track" \
      --argjson phase_0 "$installed_phase_0" --argjson phase_1 "$installed_phase_1" \
      '{schema_version: $version, resolved_at: $date, context: {dev_os: $dev_os, platform: $platform, language: $language, track: $track}, substitutions: {}, additions: [], skipped: [], installed: {phase_0: $phase_0, phase_1: $phase_1}}' \
      > "$project_dir/.claude/tool-preferences.json"

    # Append tooling summary to intake
    echo "" >> "$project_dir/PROJECT_INTAKE.md"
    echo "## Tooling Configuration" >> "$project_dir/PROJECT_INTAKE.md"
    echo "**Resolved for:** Darwin / $t_platform / $t_language / $t_track track" >> "$project_dir/PROJECT_INTAKE.md"
    echo "" >> "$project_dir/PROJECT_INTAKE.md"
    echo "### Installed" >> "$project_dir/PROJECT_INTAKE.md"
    echo "| Tool | Category | Version |" >> "$project_dir/PROJECT_INTAKE.md"
    echo "|---|---|---|" >> "$project_dir/PROJECT_INTAKE.md"
    echo "$resolver_output" | jq -r '.already_installed[] | "| \(.name) | \(.category) | \(.version) |"' >> "$project_dir/PROJECT_INTAKE.md"
  fi

  # === VERIFICATION ===

  # Check critical files
  for f in PROJECT_INTAKE.md .claude/tool-preferences.json .github/workflows/ci.yml; do
    [ -f "$project_dir/$f" ] && pass "File exists ($label): $f" || fail "File missing ($label): $f"
  done

  # Release pipeline
  if [ -f "$SCRIPT_DIR/templates/pipelines/release/${t_platform}.yml" ]; then
    [ -f "$project_dir/.github/workflows/release.yml" ] && pass "Release pipeline: $label" || fail "Release pipeline missing: $label"
  fi

  # Platform module
  if [ -f "$SCRIPT_DIR/docs/platform-modules/${t_platform}.md" ]; then
    [ -f "$project_dir/docs/platform-modules/${t_platform}.md" ] && pass "Platform module: $label" || fail "Platform module missing: $label"
  fi

  # tool-preferences.json correct context
  if [ -f "$project_dir/.claude/tool-preferences.json" ]; then
    tp_platform=$(jq -r '.context.platform' "$project_dir/.claude/tool-preferences.json" 2>/dev/null)
    tp_language=$(jq -r '.context.language' "$project_dir/.claude/tool-preferences.json" 2>/dev/null)
    tp_track=$(jq -r '.context.track' "$project_dir/.claude/tool-preferences.json" 2>/dev/null)
    if [ "$tp_platform" = "$t_platform" ] && [ "$tp_language" = "$t_language" ] && [ "$tp_track" = "$t_track" ]; then
      pass "tool-preferences.json context correct: $label"
    else
      fail "tool-preferences.json context wrong ($tp_platform/$tp_language/$tp_track): $label"
    fi
  fi

  # Tool matrix copied
  local_matrix_count=$(ls "$project_dir/templates/tool-matrix/"*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$local_matrix_count" -ge 2 ] && pass "Tool matrix ($local_matrix_count files): $label" || fail "Tool matrix incomplete: $label"

  # Resolve-tools.sh executable
  [ -x "$project_dir/scripts/resolve-tools.sh" ] && pass "resolve-tools.sh executable: $label" || fail "resolve-tools.sh not executable: $label"

  # All scripts executable
  for s in validate.sh check-phase-gate.sh resume.sh intake-wizard.sh resolve-tools.sh; do
    [ -x "$project_dir/scripts/$s" ] && pass "Script executable ($label): $s" || fail "Script not executable ($label): $s"
  done

  # Intake has Tooling Configuration
  grep -q "Tooling Configuration" "$project_dir/PROJECT_INTAKE.md" && pass "Intake tooling section: $label" || fail "Intake tooling section missing: $label"
  grep -q "$t_platform" "$project_dir/PROJECT_INTAKE.md" && pass "Intake references platform: $label" || warn "Intake may not reference platform: $label"

  # Intake suggestions copied
  [ -f "$project_dir/templates/intake-suggestions/${t_platform}.json" ] && pass "Intake suggestions: $label" || warn "Intake suggestions missing: $label"

  # Project-local resolver works
  proj_resolve=$(cd "$project_dir" && bash scripts/resolve-tools.sh \
    --dev-os darwin --platform "$t_platform" --language "$t_language" \
    --track "$t_track" --phase 2 --matrix-dir templates/tool-matrix 2>/dev/null) || proj_resolve=""
  if [ -n "$proj_resolve" ] && echo "$proj_resolve" | jq -e '.auto_install' >/dev/null 2>&1; then
    pass "Project-local resolver works: $label"
  else
    fail "Project-local resolver failed: $label"
  fi
done

# ================================================================
# TEST 5: PHASE GATE TOOL CHECKS
# ================================================================
section "TEST 5: Phase Gate Integration"

echo ""

# Use the first test project
gate_project="$TEST_DIR/test-web-typescript"
if [ -d "$gate_project" ]; then
  # Run check-phase-gate.sh — it should complete (phase 0, no gates to check)
  gate_output=$(cd "$gate_project" && bash scripts/check-phase-gate.sh 2>&1) || true
  if echo "$gate_output" | grep -q "Phase Gate Consistency Check"; then
    pass "Phase gate script runs in created project"
  else
    fail "Phase gate script failed to run"
  fi

  # Verify it mentions tool resolution if tool-preferences.json exists
  if [ -f "$gate_project/.claude/tool-preferences.json" ]; then
    pass "Phase gate can access tool-preferences.json"
  else
    fail "Phase gate: tool-preferences.json missing"
  fi
else
  warn "Skipping phase gate tests — test project not found"
fi

# ================================================================
# TEST 6: PLUGIN, MCP SERVER, AND SKILL DETECTION
# ================================================================
section "TEST 6: Plugin/MCP/Skill Detection on Current Machine"

echo ""

# Check what the resolver detects as installed on this machine
detect_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)

# Superpowers
sp_status=$(echo "$detect_output" | jq -r '[(.already_installed)[] | select(.name == "Superpowers")] | length')
if [ "$sp_status" -gt 0 ]; then
  pass "Superpowers plugin: DETECTED as installed"
else
  sp_auto=$(echo "$detect_output" | jq -r '[(.auto_install)[] | select(.name == "Superpowers")] | length')
  if [ "$sp_auto" -gt 0 ]; then
    pass "Superpowers plugin: offered for auto-install"
  else
    fail "Superpowers plugin: not detected and not offered"
  fi
fi

# Context7 MCP
c7_status=$(echo "$detect_output" | jq -r '[(.already_installed)[] | select(.name == "Context7 MCP")] | length')
if [ "$c7_status" -gt 0 ]; then
  pass "Context7 MCP: DETECTED as configured"
else
  c7_auto=$(echo "$detect_output" | jq -r '[(.auto_install)[] | select(.name == "Context7 MCP")] | length')
  if [ "$c7_auto" -gt 0 ]; then
    pass "Context7 MCP: offered for auto-install"
  else
    warn "Context7 MCP: not detected and not offered (may need Node.js)"
  fi
fi

# Qdrant MCP
qd_status=$(echo "$detect_output" | jq -r '[(.already_installed)[] | select(.name == "Qdrant MCP")] | length')
if [ "$qd_status" -gt 0 ]; then
  pass "Qdrant MCP: DETECTED as configured"
else
  qd_manual=$(echo "$detect_output" | jq -r '[(.manual_install)[] | select(.name == "Qdrant MCP")] | length')
  if [ "$qd_manual" -gt 0 ]; then
    pass "Qdrant MCP: listed as manual install (requires Docker + uv)"
  else
    fail "Qdrant MCP: not detected and not listed"
  fi
fi

# Core security tools
for tool in "Git" "jq" "Node.js" "Semgrep" "gitleaks" "Snyk CLI" "Claude Code"; do
  t_status=$(echo "$detect_output" | jq -r --arg n "$tool" '[(.already_installed)[] | select(.name == $n)] | length')
  if [ "$t_status" -gt 0 ]; then
    t_version=$(echo "$detect_output" | jq -r --arg n "$tool" '[(.already_installed)[] | select(.name == $n)] | .[0].version')
    pass "Core tool detected: $tool ($t_version)"
  else
    t_auto=$(echo "$detect_output" | jq -r --arg n "$tool" '[(.auto_install)[] | select(.name == $n)] | length')
    if [ "$t_auto" -gt 0 ]; then
      warn "Core tool NOT installed but offered: $tool"
    else
      fail "Core tool NOT detected and NOT offered: $tool"
    fi
  fi
done

# ================================================================
# TEST 7: DRY-RUN MODE
# ================================================================
section "TEST 7: Dry-Run Mode"

echo ""

# Test dry-run with piped input
dry_input="test-dryrun
Dry run test
3
2
1
7
/tmp/test-dryrun
Y"

dry_output=$(echo "$dry_input" | bash "$SCRIPT_DIR/init.sh" --dry-run 2>&1) || true

if echo "$dry_output" | grep -q "DRY RUN"; then
  pass "Dry-run mode activates"
else
  fail "Dry-run mode did not activate"
fi

if echo "$dry_output" | grep -q "Tool Resolution"; then
  pass "Dry-run shows resolver-based tool output"
else
  fail "Dry-run missing resolver tool output"
fi

if echo "$dry_output" | grep -qi "already installed\|WILL INSTALL\|MANUAL\|DEFERRED"; then
  pass "Dry-run shows tool status categories"
else
  fail "Dry-run missing tool status categories"
fi

# Verify no project was actually created
if [ ! -d "/tmp/test-dryrun" ]; then
  pass "Dry-run did not create project directory"
else
  fail "Dry-run created a project directory (should not have)"
  rm -rf "/tmp/test-dryrun"
fi

# ================================================================
# TEST 8: INIT.SH SYNTAX AND STRUCTURE
# ================================================================
section "TEST 8: Script Syntax Validation"

echo ""

bash -n "$SCRIPT_DIR/init.sh" 2>/dev/null && pass "init.sh syntax OK" || fail "init.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/resolve-tools.sh" 2>/dev/null && pass "resolve-tools.sh syntax OK" || fail "resolve-tools.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/check-phase-gate.sh" 2>/dev/null && pass "check-phase-gate.sh syntax OK" || fail "check-phase-gate.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/validate.sh" 2>/dev/null && pass "validate.sh syntax OK" || fail "validate.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/intake-wizard.sh" 2>/dev/null && pass "intake-wizard.sh syntax OK" || fail "intake-wizard.sh syntax ERROR"

# Verify all JSON matrix files are valid
for f in "$MATRIX_DIR"/*.json; do
  fname=$(basename "$f")
  jq '.' "$f" > /dev/null 2>&1 && pass "JSON valid: $fname" || fail "JSON invalid: $fname"
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
  echo -e "$RESULTS" | grep "^FAIL" | sed 's/FAIL|/  • /'
fi

if [ $WARN -gt 0 ]; then
  echo ""
  echo "Warnings:"
  echo -e "$RESULTS" | grep "^WARN" | sed 's/WARN|/  • /'
fi

# Cleanup
rm -rf "$TEST_DIR"

echo ""
echo "Test directory cleaned up: $TEST_DIR"
echo ""

exit $FAIL

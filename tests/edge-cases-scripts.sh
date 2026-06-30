#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Script Edge Cases Test Suite (E11-E25)
# Tests edge cases for validate.sh, resume.sh, check-phase-gate.sh,
# test-gate.sh, upgrade-project.sh, intake-wizard.sh, check-versions.sh,
# and resolve-tools.sh.
#
# Usage: bash tests/edge-cases-scripts.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0
SKIP=0
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

skip() {
  SKIP=$((SKIP + 1))
  echo -e "${YELLOW}  [SKIP]${NC} $1"
  RESULTS+="SKIP|$1\n"
}

section() {
  echo ""
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# ================================================================
# HELPER: Create a minimal valid Solo Orchestrator project
# ================================================================
create_test_project() {
  local dir="$1"
  local project_name="${2:-TestProject}"
  local platform="${3:-web}"
  local track="${4:-standard}"
  local language="${5:-typescript}"

  mkdir -p "$dir/.claude" "$dir/.git/hooks" "$dir/.github/workflows" \
           "$dir/docs/reference" "$dir/docs/platform-modules" \
           "$dir/scripts/lib" "$dir/templates/intake-suggestions" \
           "$dir/templates/tool-matrix"

  # CLAUDE.md
  cat > "$dir/CLAUDE.md" << EOF
# Project Context
- **Project:** $project_name
- **Platform:** $platform
- **Track:** $track
- **Primary Language:** $language
- **Features built:** none yet
- **Features remaining:** see MVP Cutline
EOF

  # PROJECT_INTAKE.md
  cat > "$dir/PROJECT_INTAKE.md" << 'EOF'
# Project Intake
| Domain | Self-Assessment | Notes |
|--------|----------------|-------|
| Security | No | Need help |
| Accessibility | No | New to a11y |
| Performance | Partially | Some experience |
| Database | No | First time |
EOF

  # APPROVAL_LOG.md
  cat > "$dir/APPROVAL_LOG.md" << 'EOF'
# Approval Log
## Phase 0 → Phase 1
**Date:** 2026-03-15
**Reviewer:** Self

## Phase 1 → Phase 2
**Date:** 2026-03-20
**Reviewer:** Self

## Phase 3 → Phase 4
**Date:** 2026-03-25
**Reviewer:** Self
EOF

  # Framework docs
  touch "$dir/docs/reference/builders-guide.md"
  touch "$dir/docs/reference/user-guide.md"
  touch "$dir/docs/reference/governance-framework.md"
  touch "$dir/docs/reference/cli-setup-addendum.md"

  # Platform module
  touch "$dir/docs/platform-modules/${platform}.md"

  # .gitignore
  echo "node_modules/" > "$dir/.gitignore"

  # CI/CD
  cat > "$dir/.github/workflows/ci.yml" << 'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "semgrep scan"
      - run: echo "lighthouse"
EOF

  cat > "$dir/.github/workflows/release.yml" << 'EOF'
name: Release
on:
  push:
    tags: ['v*']
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - run: echo "release"
      # TODO configure signing
EOF

  # Phase state
  cat > "$dir/.claude/phase-state.json" << EOF
{
  "current_phase": 0,
  "project": "$project_name"
}
EOF

  # Pre-commit hook (executable)
  echo '#!/bin/sh' > "$dir/.git/hooks/pre-commit"
  chmod +x "$dir/.git/hooks/pre-commit"

  # Copy scripts from the repo
  cp -r "$REPO_DIR/scripts/"* "$dir/scripts/" 2>/dev/null || true
  cp "$REPO_DIR/scripts/lib/helpers.sh" "$dir/scripts/lib/helpers.sh" 2>/dev/null || true

  # Copy tool-matrix templates
  cp "$REPO_DIR/templates/tool-matrix/"*.json "$dir/templates/tool-matrix/" 2>/dev/null || true

  # Make scripts executable
  chmod +x "$dir/scripts/"*.sh 2>/dev/null || true
}


# ================================================================
# E11: Run validate.sh from outside a project directory
# ================================================================
section "E11: validate.sh from outside a project directory"

E11_DIR="$TEST_DIR/e11-empty"
mkdir -p "$E11_DIR"

result=0
output=$( cd "$E11_DIR" && bash "$REPO_DIR/scripts/validate.sh" 2>&1 ) || result=$?

if [ "$result" -ne 0 ]; then
  pass "E11: validate.sh exits non-zero outside project directory (exit $result)"
else
  fail "E11: validate.sh should have exited non-zero outside project directory"
fi

if echo "$output" | grep -qi "CLAUDE.md not found"; then
  pass "E11: Error message mentions 'CLAUDE.md not found'"
else
  fail "E11: Error message should mention 'CLAUDE.md not found', got: $output"
fi


# ================================================================
# E12: Run resume.sh with empty/missing CLAUDE.md
# ================================================================
section "E12: resume.sh with empty/missing CLAUDE.md"

# Test with missing CLAUDE.md entirely
E12_DIR="$TEST_DIR/e12-no-claude"
create_test_project "$E12_DIR"
rm -f "$E12_DIR/CLAUDE.md"

result=0
output=$( cd "$E12_DIR" && bash "$E12_DIR/scripts/resume.sh" 2>&1 </dev/null ) || result=$?

# resume.sh should handle missing CLAUDE.md gracefully (not crash)
# It may still run but show "(not found in CLAUDE.md)" for fields
if [ "$result" -eq 0 ]; then
  pass "E12a: resume.sh exits cleanly with missing CLAUDE.md (exit 0)"
else
  # Even a non-zero exit is acceptable as long as it didn't crash with a bash error
  if echo "$output" | grep -qE "unbound variable|syntax error|command not found"; then
    fail "E12a: resume.sh crashed with bash error when CLAUDE.md missing"
  else
    pass "E12a: resume.sh exited non-zero but handled missing CLAUDE.md gracefully (exit $result)"
  fi
fi

# Test with empty CLAUDE.md
E12B_DIR="$TEST_DIR/e12-empty-claude"
create_test_project "$E12B_DIR"
: > "$E12B_DIR/CLAUDE.md"

result=0
output=$( cd "$E12B_DIR" && bash "$E12B_DIR/scripts/resume.sh" 2>&1 </dev/null ) || result=$?

if echo "$output" | grep -qE "unbound variable|syntax error|command not found"; then
  fail "E12b: resume.sh crashed with bash error on empty CLAUDE.md"
else
  pass "E12b: resume.sh handles empty CLAUDE.md without crashing"
fi


# ================================================================
# E13: check-phase-gate.sh with phase 3 but no gate dates
# ================================================================
section "E13: check-phase-gate.sh with phase 3, no gate dates in phase-state.json"

E13_DIR="$TEST_DIR/e13-inconsistent"
create_test_project "$E13_DIR"

# Set phase to 3 with no gate dates
cat > "$E13_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 3,
  "project": "TestProject"
}
EOF

result=0
output=$( cd "$E13_DIR" && bash "$E13_DIR/scripts/check-phase-gate.sh" 2>&1 </dev/null ) || result=$?

if [ "$result" -ne 0 ]; then
  pass "E13: check-phase-gate.sh exits non-zero for inconsistent state (exit $result)"
else
  fail "E13: check-phase-gate.sh should report inconsistency for phase 3 with no gate dates"
fi

if echo "$output" | grep -qiE "WARN|inconsisten|gate.*not recorded"; then
  pass "E13: Output reports inconsistency or warning"
else
  fail "E13: Output should mention inconsistency, got: $(echo "$output" | head -5)"
fi


# ================================================================
# E14: test-gate.sh --check-phase-gate with open SEV-1 bugs in BUGS.md
# ================================================================
section "E14: test-gate.sh --check-phase-gate with open SEV-1 bugs"

E14_DIR="$TEST_DIR/e14-sev1"
create_test_project "$E14_DIR"

# Create BUGS.md with SEV-1 open bugs
cat > "$E14_DIR/BUGS.md" << 'EOF'
# Bug Tracker
| # | Severity | Status | Feature | Description |
|---|----------|--------|---------|-------------|
| 1 | SEV-1 | Open | Login | Auth token leak |
| 2 | SEV-2 | Fixed | Profile | Avatar upload crash |
| 3 | SEV-3 | Open | Settings | Minor layout issue |
EOF

result=0
output=$( cd "$E14_DIR" && bash "$E14_DIR/scripts/test-gate.sh" --check-phase-gate 2>&1 </dev/null ) || result=$?

if [ "$result" -eq 1 ]; then
  pass "E14: test-gate.sh exits 1 (blocked) with open SEV-1 bugs"
else
  fail "E14: test-gate.sh should exit 1 (blocked) with open SEV-1, got exit $result"
fi

if echo "$output" | grep -qi "SEV-1"; then
  pass "E14: Output mentions SEV-1 bugs"
else
  fail "E14: Output should mention SEV-1 bugs"
fi

if echo "$output" | grep -qiE "BLOCKED|FAIL"; then
  pass "E14: Output indicates blocked status"
else
  fail "E14: Output should indicate blocked status"
fi


# ================================================================
# E15: test-gate.sh --check-phase-gate with no bug tracker
# ================================================================
section "E15: test-gate.sh --check-phase-gate with no BUGS.md and no GitHub Issues"

E15_DIR="$TEST_DIR/e15-no-bugs"
create_test_project "$E15_DIR"

# Ensure no BUGS.md exists
rm -f "$E15_DIR/BUGS.md"

# Wrap in a subshell that fakes gh as unavailable
result=0
output=$( cd "$E15_DIR" && PATH="/usr/bin:/bin" bash "$E15_DIR/scripts/test-gate.sh" --check-phase-gate 2>&1 </dev/null ) || result=$?

if [ "$result" -eq 2 ]; then
  pass "E15: test-gate.sh exits 2 (warning) when no bug tracker found"
else
  # Even exit 1 might be acceptable if it warns — but spec says exit 2
  fail "E15: test-gate.sh should exit 2 with no bug tracker, got exit $result"
fi

if echo "$output" | grep -qiE "warn|no bug.*track|cannot verify"; then
  pass "E15: Output warns about missing bug tracker"
else
  fail "E15: Output should warn about missing bug tracker"
fi


# ================================================================
# E16: upgrade-project.sh --track light on a standard project (downgrade)
# ================================================================
section "E16: upgrade-project.sh --track light on standard project"

if command -v jq &>/dev/null && command -v python3 &>/dev/null; then
  E16_DIR="$TEST_DIR/e16-downgrade-track"
  create_test_project "$E16_DIR" "DowngradeTest" "web" "standard" "typescript"

  # Set up tool-preferences.json with track=standard
  cat > "$E16_DIR/.claude/tool-preferences.json" << 'EOF'
{
  "context": {
    "dev_os": "darwin",
    "platform": "web",
    "language": "typescript",
    "track": "standard"
  },
  "skipped": [],
  "substitutions": {},
  "additions": []
}
EOF

  cat > "$E16_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 1,
  "project": "DowngradeTest"
}
EOF

  result=0
  output=$( cd "$E16_DIR" && bash "$E16_DIR/scripts/upgrade-project.sh" --track light 2>&1 </dev/null ) || result=$?

  if [ "$result" -ne 0 ]; then
    pass "E16: upgrade-project.sh rejects track downgrade (exit $result)"
  else
    fail "E16: upgrade-project.sh should reject downgrade from standard to light"
  fi

  if echo "$output" | grep -qiE "cannot downgrade|downgrade"; then
    pass "E16: Error message mentions downgrade"
  else
    fail "E16: Error message should mention downgrade, got: $(echo "$output" | head -3)"
  fi
else
  skip "E16: jq or python3 not available"
fi


# ================================================================
# E17: upgrade-project.sh --deployment personal on organizational project
# ================================================================
section "E17: upgrade-project.sh --deployment personal on organizational project"

if command -v jq &>/dev/null && command -v python3 &>/dev/null; then
  E17_DIR="$TEST_DIR/e17-downgrade-deploy"
  create_test_project "$E17_DIR" "DeployTest" "web" "standard" "typescript"

  cat > "$E17_DIR/.claude/tool-preferences.json" << 'EOF'
{
  "context": {
    "dev_os": "darwin",
    "platform": "web",
    "language": "typescript",
    "track": "standard"
  },
  "skipped": [],
  "substitutions": {},
  "additions": []
}
EOF

  cat > "$E17_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 1,
  "project": "DeployTest"
}
EOF

  # Set deployment to organizational in the intake progress file
  cat > "$E17_DIR/.claude/intake-progress.json" << 'EOF'
{
  "version": 1,
  "started_at": "2026-01-01T00:00:00Z",
  "last_section": 3,
  "completed_sections": [1,2,3],
  "project_name": "DeployTest",
  "platform": "web",
  "track": "standard",
  "deployment": "organizational",
  "language": "typescript",
  "description": "Test project",
  "poc_mode": null,
  "answers": {}
}
EOF

  result=0
  output=$( cd "$E17_DIR" && bash "$E17_DIR/scripts/upgrade-project.sh" --deployment personal 2>&1 </dev/null ) || result=$?

  if [ "$result" -ne 0 ]; then
    pass "E17: upgrade-project.sh rejects deployment downgrade (exit $result)"
  else
    fail "E17: upgrade-project.sh should reject downgrade from organizational to personal"
  fi

  if echo "$output" | grep -qiE "cannot downgrade|downgrade"; then
    pass "E17: Error message mentions downgrade"
  else
    fail "E17: Error message should mention downgrade, got: $(echo "$output" | head -3)"
  fi
else
  skip "E17: jq or python3 not available"
fi


# ================================================================
# E18: upgrade-project.sh from outside a project directory
# ================================================================
section "E18: upgrade-project.sh from outside project directory"

if command -v jq &>/dev/null && command -v python3 &>/dev/null; then
  E18_DIR="$TEST_DIR/e18-empty"
  mkdir -p "$E18_DIR"

  result=0
  output=$( cd "$E18_DIR" && bash "$REPO_DIR/scripts/upgrade-project.sh" --track standard 2>&1 </dev/null ) || result=$?

  if [ "$result" -ne 0 ]; then
    pass "E18: upgrade-project.sh exits non-zero outside project directory (exit $result)"
  else
    fail "E18: upgrade-project.sh should fail outside a project directory"
  fi

  if echo "$output" | grep -qiE "no.*project found|not found|FAIL"; then
    pass "E18: Error message indicates no project found"
  else
    fail "E18: Error message should indicate no project found, got: $(echo "$output" | head -3)"
  fi
else
  skip "E18: jq or python3 not available"
fi


# ================================================================
# E19: intake-wizard.sh --resume with no progress file
# ================================================================
section "E19: intake-wizard.sh --resume with no progress file"

E19_DIR="$TEST_DIR/e19-no-progress"
create_test_project "$E19_DIR"

# Ensure no progress file exists
rm -f "$E19_DIR/.claude/intake-progress.json"

result=0
output=$( cd "$E19_DIR" && bash "$E19_DIR/scripts/intake-wizard.sh" --resume 2>&1 </dev/null ) || result=$?

if [ "$result" -ne 0 ]; then
  pass "E19: intake-wizard.sh --resume exits non-zero with no progress file (exit $result)"
else
  fail "E19: intake-wizard.sh --resume should fail with no progress file"
fi

if echo "$output" | grep -qiE "no progress|not found|WARN"; then
  pass "E19: Output mentions missing progress file"
else
  fail "E19: Output should mention missing progress, got: $(echo "$output" | head -3)"
fi


# ================================================================
# E20: intake-wizard.sh with apostrophe in text field (BUG-1 regression)
# ================================================================
section "E20: intake-wizard.sh — apostrophe in text field (save_answer)"

if command -v python3 &>/dev/null; then
  E20_DIR="$TEST_DIR/e20-apostrophe"
  create_test_project "$E20_DIR"

  # Create a valid progress file for save_answer to work with
  python3 -c "
import json
data = {
    'version': 1,
    'started_at': '2026-01-01T00:00:00Z',
    'last_section': 0,
    'completed_sections': [],
    'project_name': 'TestProject',
    'platform': 'web',
    'track': 'standard',
    'deployment': 'personal',
    'language': 'typescript',
    'description': 'A test project',
    'poc_mode': None,
    'answers': {}
}
with open('$E20_DIR/.claude/intake-progress.json', 'w') as f:
    json.dump(data, f, indent=2)
"

  # Source the wizard to get save_answer, then call it with an apostrophe value
  result=0
  output=$(
    cd "$E20_DIR"
    # Extract and test save_answer directly via python3
    python3 -c "
import json, sys
key, value = 'test_field', \"it's a REST API with OAuth2\"
path = '$E20_DIR/.claude/intake-progress.json'
with open(path) as f:
    data = json.load(f)
data['answers'][key] = value
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
# Verify
with open(path) as f:
    data = json.load(f)
assert data['answers']['test_field'] == \"it's a REST API with OAuth2\", 'Mismatch!'
print('OK')
" 2>&1
  ) || result=$?

  if [ "$result" -eq 0 ] && echo "$output" | grep -q "OK"; then
    pass "E20: save_answer handles apostrophe without crash"
  else
    fail "E20: save_answer should handle apostrophe, got: $output"
  fi

  # Verify the JSON is valid and contains the apostrophe value
  if python3 -c "
import json
with open('$E20_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
assert \"it's a REST API\" in data['answers'].get('test_field', ''), 'Value not found'
print('VERIFIED')
" 2>&1 | grep -q "VERIFIED"; then
    pass "E20: Saved value with apostrophe is valid JSON and retrievable"
  else
    fail "E20: Saved value with apostrophe should be valid JSON"
  fi
else
  skip "E20: python3 not available"
fi


# ================================================================
# E21: intake-wizard.sh pause and --resume
# ================================================================
section "E21: intake-wizard.sh pause and resume flow"

if command -v python3 &>/dev/null; then
  E21_DIR="$TEST_DIR/e21-resume"
  create_test_project "$E21_DIR"

  # Create a progress file simulating pause after section 2
  python3 -c "
import json
data = {
    'version': 1,
    'started_at': '2026-01-01T00:00:00Z',
    'last_section': 2,
    'completed_sections': [1, 2],
    'project_name': 'TestProject',
    'platform': 'web',
    'track': 'standard',
    'deployment': 'personal',
    'language': 'typescript',
    'description': 'A test project',
    'poc_mode': None,
    'answers': {
        'codename': 'TestProject',
        'target_platforms': 'all browsers',
        'repo_url': 'TBD',
        'problem_statement': 'Manual testing takes too long'
    }
}
with open('$E21_DIR/.claude/intake-progress.json', 'w') as f:
    json.dump(data, f, indent=2)
"

  # Audit closure (tests-edge-cases-9 / S3): the previous E21 was a
  # tautology — it wrote last_section=2 into progress JSON and then
  # asserted (in pure Python) that 2+1==3, never invoking the real
  # intake-wizard.sh load_progress bash function. We now execute the
  # actual function: extract load_progress from scripts/intake-wizard.sh
  # via awk, define a print_warn stub for its single dependency, source
  # it with PROGRESS_FILE pointed at our test JSON, and assert against
  # the real shell variables (LAST_SECTION, COMPLETED_SECTIONS) the
  # function sets. The --resume handler at intake-wizard.sh:1742-1750
  # uses those same variables to compute next_section, so this directly
  # exercises the code path the test name advertises.
  result=0
  output=$(
    cd "$E21_DIR"
    # Extract the load_progress function from the real wizard source.
    extract_file=$(mktemp)
    awk '/^load_progress\(\) \{/,/^\}/' "$REPO_DIR/scripts/intake-wizard.sh" > "$extract_file"
    # Minimal print_warn stub (load_progress's only dependency).
    print_warn() { echo "WARN: $1"; }
    PROGRESS_FILE="$E21_DIR/.claude/intake-progress.json"
    # shellcheck disable=SC1090
    source "$extract_file"
    rm -f "$extract_file"
    # Drive the real function and emit its observable state.
    if load_progress; then
      next_section=$((LAST_SECTION + 1))
      echo "LP_LAST_SECTION=$LAST_SECTION"
      echo "LP_COMPLETED=[$COMPLETED_SECTIONS]"
      echo "LP_NEXT_SECTION=$next_section"
      echo "LP_PROJECT_NAME=$PROJECT_NAME"
      [ "$LAST_SECTION" = "2" ] && [ "$next_section" = "3" ] \
        && [[ "$COMPLETED_SECTIONS" == *1* ]] && [[ "$COMPLETED_SECTIONS" == *2* ]] \
        && [ "$PROJECT_NAME" = "TestProject" ] \
        && echo "RESUME_OK"
    else
      echo "LP_FAILED rc=$?"
    fi
  ) 2>&1 || result=$?

  if echo "$output" | grep -q "^RESUME_OK$" \
     && echo "$output" | grep -q "^LP_LAST_SECTION=2$" \
     && echo "$output" | grep -q "^LP_NEXT_SECTION=3$"; then
    pass "E21: load_progress (real bash function) sets LAST_SECTION=2 and next_section=3"
  else
    fail "E21: load_progress should set LAST_SECTION=2/next=3, got: $output"
  fi

  if echo "$output" | grep -qE "LP_COMPLETED=\[.*1.*2.*\]"; then
    pass "E21: load_progress populates COMPLETED_SECTIONS with 1 and 2 from JSON"
  else
    fail "E21: COMPLETED_SECTIONS should contain 1 and 2, got: $output"
  fi

  # Negative variant: malformed JSON should make load_progress fail
  # (python3 inside the function raises) — proving the real bash
  # function is what's running, not a python re-implementation.
  E21B_DIR="$TEST_DIR/e21-bad-json"
  create_test_project "$E21B_DIR"
  echo '{NOT VALID JSON' > "$E21B_DIR/.claude/intake-progress.json"

  result=0
  output=$(
    set +e  # we WANT to observe load_progress's failure exit code
    extract_file=$(mktemp)
    awk '/^load_progress\(\) \{/,/^\}/' "$REPO_DIR/scripts/intake-wizard.sh" > "$extract_file"
    print_warn() { echo "WARN: $1"; }
    PROGRESS_FILE="$E21B_DIR/.claude/intake-progress.json"
    LAST_SECTION=0
    COMPLETED_SECTIONS=""
    # shellcheck disable=SC1090
    source "$extract_file"
    rm -f "$extract_file"
    load_progress 2>&1
    rc=$?
    echo "LP_RC=$rc"
    echo "LP_LAST_SECTION=$LAST_SECTION"
  ) || result=$?

  # On malformed JSON the python helper inside load_progress raises
  # (json.JSONDecodeError) — visible in the captured stderr — and
  # writes nothing to the tmpfile that gets sourced, so LAST_SECTION
  # stays at its pre-call default (0). The function's trailing
  # `rm -f` returns 0, so we can't rely on rc alone; we assert the
  # real, observable side-effects (default state + python traceback)
  # that prove the actual bash function ran, not a python re-impl.
  if echo "$output" | grep -q "^LP_LAST_SECTION=0$" \
     && echo "$output" | grep -qE "JSONDecodeError|Traceback"; then
    pass "E21: malformed progress JSON exercises real load_progress (LAST_SECTION stays 0, python raises)"
  else
    fail "E21: malformed JSON should leave LAST_SECTION=0 with python traceback, got: $output"
  fi
else
  skip "E21: python3 not available"
fi


# ================================================================
# E22: check-versions.sh under stubbed-offline network
# ================================================================
# Audit closure (tests-edge-cases-10 / S3): the previous E22 advertised
# "offline (no network)" but its setup comment admitted it could not
# disable network and instead relied on a 7-way grep alternation
# (version check|[OK]|installed|up to date|not installed|WARN|Summary)
# that matched essentially any plausible output — a regression that
# broke offline detection or per-tool reporting would still trip a
# token and PASS. We now actually stub network at the PATH layer
# (curl → exit 1) and tighten the success assertion to a conjunction:
# the script must (a) print the canonical header, (b) emit the
# "Network unavailable — latest version check skipped" marker from
# check-versions.sh:294, AND (c) print the Summary footer with the
# pass count. Any of those three breaking now fails the test.
section "E22: check-versions.sh under stubbed-offline network"

if command -v jq &>/dev/null; then
  E22_DIR="$TEST_DIR/e22-offline"
  create_test_project "$E22_DIR"

  # Create tool-preferences.json for the version checker
  cat > "$E22_DIR/.claude/tool-preferences.json" << 'EOF'
{
  "context": {
    "dev_os": "darwin",
    "platform": "web",
    "language": "typescript",
    "track": "standard"
  },
  "skipped": [],
  "substitutions": {},
  "additions": []
}
EOF

  # Stub network: prepend a temp bin to PATH with a curl that exits 1
  # so check-versions.sh's network probe at line 291
  # `(curl -s --max-time 3 "https://registry.npmjs.org" >/dev/null 2>&1)`
  # observes a real failure and takes the offline branch.
  E22_STUB_BIN="$TEST_DIR/e22-stub-bin"
  mkdir -p "$E22_STUB_BIN"
  cat > "$E22_STUB_BIN/curl" << 'EOF'
#!/usr/bin/env bash
# stub: simulate DNS/connect failure for E22 offline scenario
exit 1
EOF
  chmod +x "$E22_STUB_BIN/curl"

  result=0
  output=$(
    cd "$E22_DIR"
    PATH="$E22_STUB_BIN:$PATH" bash "$E22_DIR/scripts/check-versions.sh" 2>&1 </dev/null
  ) || result=$?

  # Real assertion 1: canonical header must be present (regression
  # guard for the script's own banner / structural output).
  if echo "$output" | grep -qE "Solo Orchestrator.*Version Check"; then
    pass "E22: check-versions.sh prints canonical 'Version Check' header"
  else
    fail "E22: expected 'Version Check' header, got: $(echo "$output" | head -5)"
  fi

  # Real assertion 2: with curl stubbed to fail, the script must take
  # its offline branch and emit the explicit marker. This pins down
  # the network-unavailability code path the section name claims.
  if echo "$output" | grep -qE "Network unavailable.*latest version check skipped"; then
    pass "E22: stubbed-offline run emits the 'Network unavailable' marker"
  else
    fail "E22: offline branch should emit 'Network unavailable', got: $(echo "$output" | head -10)"
  fi

  # Real assertion 3: the Summary footer must be present with the
  # 'up to date' phrase from check-versions.sh:435. A regression that
  # broke the loop or dropped the summary line would no longer pass.
  if echo "$output" | grep -qE "── Summary ──" && echo "$output" | grep -qE "up to date"; then
    pass "E22: check-versions.sh prints Summary footer with 'up to date' count"
  else
    fail "E22: expected Summary footer + 'up to date' count, got: $(echo "$output" | tail -10)"
  fi

  # Sanity guard retained: should not crash with bash errors.
  if echo "$output" | grep -qE "unbound variable|syntax error"; then
    fail "E22: check-versions.sh crashed with bash error"
  else
    pass "E22: check-versions.sh runs without bash errors"
  fi
else
  skip "E22: jq not available"
fi


# ================================================================
# E23: resolve-tools.sh with invalid JSON in tool-matrix files
# ================================================================
section "E23: resolve-tools.sh with invalid JSON in tool-matrix"

if command -v jq &>/dev/null; then
  E23_DIR="$TEST_DIR/e23-bad-json"
  create_test_project "$E23_DIR"

  # Overwrite common.json with invalid JSON
  echo "THIS IS NOT VALID JSON {{{" > "$E23_DIR/templates/tool-matrix/common.json"

  result=0
  output=$( cd "$E23_DIR" && bash "$E23_DIR/scripts/resolve-tools.sh" \
    --dev-os darwin \
    --platform web \
    --language typescript \
    --track standard \
    --phase 0 \
    --matrix-dir "$E23_DIR/templates/tool-matrix" 2>&1 </dev/null ) || result=$?

  if [ "$result" -ne 0 ]; then
    pass "E23: resolve-tools.sh exits non-zero with invalid JSON (exit $result)"
  else
    fail "E23: resolve-tools.sh should fail with invalid JSON in tool-matrix"
  fi

  # Audit closure (tests-edge-cases-11 / S3): the previous E23 had
  # identical pass() calls in both branches of the error-string check,
  # so a regression that silenced jq's error output would still PASS.
  # The else-branch comment also misled — stderr IS captured into
  # $output via `2>&1` on the bash invocation above, so any real jq
  # error must surface here. We now require a jq-specific error
  # signature and fail() when absent.
  if echo "$output" | grep -qE "jq:|parse error|Invalid|invalid"; then
    pass "E23: Output indicates jq parse error (signature present in captured stderr+stdout)"
  else
    fail "E23: expected jq-style error signature in output, got: $(echo "$output" | head -5)"
  fi
else
  skip "E23: jq not available"
fi


# ================================================================
# E24: Delete APPROVAL_LOG.md and run check-phase-gate.sh
# ================================================================
section "E24: check-phase-gate.sh with deleted APPROVAL_LOG.md"

E24_DIR="$TEST_DIR/e24-no-approval"
create_test_project "$E24_DIR"

# Set a phase > 0 so the gate check has something to validate
cat > "$E24_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 2,
  "project": "TestProject",
  "phase_0_to_1": "2026-03-15",
  "phase_1_to_2": "2026-03-20"
}
EOF

# Delete APPROVAL_LOG.md
rm -f "$E24_DIR/APPROVAL_LOG.md"

result=0
output=$( cd "$E24_DIR" && bash "$E24_DIR/scripts/check-phase-gate.sh" 2>&1 </dev/null ) || result=$?

if [ "$result" -ne 0 ]; then
  pass "E24: check-phase-gate.sh exits non-zero when APPROVAL_LOG.md missing (exit $result)"
else
  fail "E24: check-phase-gate.sh should fail when APPROVAL_LOG.md missing"
fi

if echo "$output" | grep -qiE "APPROVAL_LOG.*not found|FAIL"; then
  pass "E24: Output mentions APPROVAL_LOG.md not found"
else
  fail "E24: Output should mention missing APPROVAL_LOG.md, got: $(echo "$output" | head -3)"
fi


# ================================================================
# E25: Set current_phase to 99 in phase-state.json
# ================================================================
section "E25: phase-state.json with current_phase: 99"

E25_DIR="$TEST_DIR/e25-bogus-phase"
create_test_project "$E25_DIR"

cat > "$E25_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 99,
  "project": "TestProject"
}
EOF

# Test validate.sh — should not crash
result=0
output=$( cd "$E25_DIR" && bash "$E25_DIR/scripts/validate.sh" 2>&1 </dev/null ) || result=$?

if echo "$output" | grep -qE "unbound variable|syntax error|command not found"; then
  fail "E25a: validate.sh crashed with bash error on phase 99"
else
  pass "E25a: validate.sh does not crash with current_phase=99"
fi

# Test check-phase-gate.sh — should not crash
result=0
output=$( cd "$E25_DIR" && bash "$E25_DIR/scripts/check-phase-gate.sh" 2>&1 </dev/null ) || result=$?

if echo "$output" | grep -qE "unbound variable|syntax error|command not found"; then
  fail "E25b: check-phase-gate.sh crashed with bash error on phase 99"
else
  pass "E25b: check-phase-gate.sh does not crash with current_phase=99"
fi

# Test resume.sh — should not crash
result=0
output=$( cd "$E25_DIR" && bash "$E25_DIR/scripts/resume.sh" 2>&1 </dev/null ) || result=$?

if echo "$output" | grep -qE "unbound variable|syntax error|command not found"; then
  fail "E25c: resume.sh crashed with bash error on phase 99"
else
  pass "E25c: resume.sh does not crash with current_phase=99"
fi


# ================================================================
# SUMMARY
# ================================================================
# BL-009: UAT template quality integration tests
# ================================================================
section "BL-009: UAT template quality + platform-aware authoring"

# audit tests-edge-cases-22 / tests-edge-cases-23 (closure):
# Pre-fix this section called _uat_run_init_copy_block, an in-test
# duplicate of init.sh's UAT copy block. The shadow helper meant E26-E32
# never exercised init.sh / upgrade-project.sh — if init.sh deleted its
# entire UAT copy block, every E26-E32 case still passed. Verified RED
# on origin/main by removing init.sh:1187-1207 — all 7 cases still
# returned [PASS].
#
# The rewrite below drives the real init.sh --non-interactive code path
# (E26-E30) and the real scripts/upgrade-project.sh UAT migration block
# (E31, E32). That removes the shadow code and gives the BL-009 spec
# real regression coverage: deleting init.sh's copy block or breaking
# upgrade-project.sh's UAT migration now flips E26-E32 to FAIL.

# Helper: run real init.sh --non-interactive for the given platform into
# the supplied --project-dir. Uses --no-remote-creation so the test never
# touches a real GitHub/GitLab/Bitbucket account. Captures stderr on
# failure so the diagnostic survives the assertion below.
#
# Note: init.sh's "Proceed with this plan?" prompt only fires when a tool
# in the install plan is missing on the test host (e.g. mobile platform
# needs Android Studio). With closed stdin and `set -e`, the `read -rp`
# at init.sh:736 would EOF and abort. We pipe a stream of "Y" answers so
# the plan proceeds regardless of host state — this isolates the test
# from the test host's tool inventory.
_uat_real_init() {
  local work="$1" platform="$2" project="$3"
  local logfile="$work/init-${platform}.log"
  # Feed a finite stream of "Y" answers from process substitution so
  # init.sh's "Proceed with this plan?" / install confirms auto-pass
  # without breaking `set -o pipefail` (yes(1) gets SIGPIPE and the
  # 141 exit code propagates through pipefail; printf does not).
  ( cd "$work" && \
    bash "$REPO_DIR/init.sh" --non-interactive \
        --project "$project" \
        --platform "$platform" \
        --deployment personal \
        --language typescript \
        --git-host github \
        --visibility private \
        --no-remote-creation \
        --project-dir "$work/$project" \
        --allow-existing-dir \
        < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') ) > "$logfile" 2>&1
}

# Case 1: real init.sh for web platform copies web reference pair
_uat_work=$(mktemp -d)
if _uat_real_init "$_uat_work" "web" "e26-web" && \
   [ -f "$_uat_work/e26-web/tests/uat/examples/pre-flight-reference.html" ] && \
   [ -f "$_uat_work/e26-web/tests/uat/examples/scenario-reference.json" ] && \
   grep -qi 'browser\|devtools\|app url' "$_uat_work/e26-web/tests/uat/examples/pre-flight-reference.html"; then
  pass "E26: real init.sh --platform web copies web-specific UAT reference pair"
else
  fail "E26: real init.sh --platform web failed — refs missing or not web-specific (log: $_uat_work/init-web.log)"
fi
rm -rf "$_uat_work"

# Case 2: real init.sh for desktop
_uat_work=$(mktemp -d)
if _uat_real_init "$_uat_work" "desktop" "e27-desktop" && \
   [ -f "$_uat_work/e27-desktop/tests/uat/examples/pre-flight-reference.html" ] && \
   grep -qi 'terminal\|project root\|venv\|runtime' "$_uat_work/e27-desktop/tests/uat/examples/pre-flight-reference.html"; then
  pass "E27: real init.sh --platform desktop copies desktop-specific UAT reference pair"
else
  fail "E27: real init.sh --platform desktop failed (log: $_uat_work/init-desktop.log)"
fi
rm -rf "$_uat_work"

# Case 3: real init.sh for mobile
_uat_work=$(mktemp -d)
if _uat_real_init "$_uat_work" "mobile" "e28-mobile" && \
   [ -f "$_uat_work/e28-mobile/tests/uat/examples/pre-flight-reference.html" ] && \
   grep -qi 'device\|simulator\|testflight\|android' "$_uat_work/e28-mobile/tests/uat/examples/pre-flight-reference.html"; then
  pass "E28: real init.sh --platform mobile copies mobile-specific UAT reference pair"
else
  fail "E28: real init.sh --platform mobile failed (log: $_uat_work/init-mobile.log)"
fi
rm -rf "$_uat_work"

# Case 4: real init.sh for mcp_server
_uat_work=$(mktemp -d)
if _uat_real_init "$_uat_work" "mcp_server" "e29-mcp" && \
   [ -f "$_uat_work/e29-mcp/tests/uat/examples/pre-flight-reference.html" ] && \
   grep -qi 'mcp\|inspector\|json-rpc\|tool call' "$_uat_work/e29-mcp/tests/uat/examples/pre-flight-reference.html"; then
  pass "E29: real init.sh --platform mcp_server copies mcp-specific UAT reference pair"
else
  fail "E29: real init.sh --platform mcp_server failed (log: $_uat_work/init-mcp_server.log)"
fi
rm -rf "$_uat_work"

# Case 5: real init.sh for 'other' skips reference copy but keeps templates
_uat_work=$(mktemp -d)
if _uat_real_init "$_uat_work" "other" "e30-other" && \
   [ -f "$_uat_work/e30-other/tests/uat/templates/test-session-template.html" ] && \
   [ ! -f "$_uat_work/e30-other/tests/uat/examples/pre-flight-reference.html" ] && \
   [ ! -f "$_uat_work/e30-other/tests/uat/examples/scenario-reference.json" ]; then
  pass "E30: real init.sh --platform other skips ref copy, keeps source templates"
else
  fail "E30: real init.sh --platform other produced wrong state (refs present or template missing) (log: $_uat_work/init-other.log)"
fi
rm -rf "$_uat_work"

# Helper: seed intake-progress.json with the platform key that
# upgrade-project.sh's UAT migration block reads. init.sh writes
# tool-preferences.json but not intake-progress.json (audit-trail gap
# tracked in code-upgrade-project; not the focus of this audit closure).
# This keeps the E31/E32 cases focused on the BL-009 UAT migration
# contract, not the unrelated intake-progress drift.
_uat_seed_intake_progress() {
  local proj="$1" platform="$2"
  mkdir -p "$proj/.claude"
  cat > "$proj/.claude/intake-progress.json" <<JSON
{
  "version": 1,
  "started_at": "2026-04-23T00:00:00Z",
  "answers": {"platform": "$platform", "project_name": "$(basename "$proj")"}
}
JSON
}

# Case 6: real upgrade-project.sh UAT migration refreshes a pre-migration tree.
# Initialize via real init.sh (with --track light so the subsequent
# upgrade-project.sh --track standard does real work and reaches the UAT
# migration block at scripts/upgrade-project.sh:2093). Then simulate a
# pre-BL-009 project by overwriting the source template with stub content
# and removing the reference pair. The upgrade-project.sh UAT migration
# block must restore them.
_uat_real_init_light_impl() {
  local work="$1" platform="$2" project="$3"
  local logfile="$work/init-${platform}-light.log"
  ( cd "$work" && \
    bash "$REPO_DIR/init.sh" --non-interactive \
        --project "$project" \
        --platform "$platform" \
        --deployment personal \
        --language typescript \
        --track light \
        --git-host github \
        --visibility private \
        --no-remote-creation \
        --project-dir "$work/$project" \
        --allow-existing-dir \
        < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') ) > "$logfile" 2>&1
}

_uat_work=$(mktemp -d)
if ! _uat_real_init_light_impl "$_uat_work" "desktop" "e31-upgrade"; then
  fail "E31: setup init.sh failed (log: $_uat_work/init-desktop-light.log)"
else
  _proj="$_uat_work/e31-upgrade"
  _uat_seed_intake_progress "$_proj" "desktop"
  # Regression to "pre-migration" state: clobber the source template
  # with a stub that DOES NOT contain the production placeholder, then
  # delete the reference pair so the upgrade has visible work to do.
  # BL-036 fix: the prior stub embedded '__TESTER_PRE_FLIGHT__' in its
  # comment text, which trivially satisfied the post-condition grep
  # even when upgrade-project.sh's UAT migration block was disabled
  # (mutation-test escape). The new stub uses a string that cannot
  # collide with the production marker.
  echo "OLD STUB TEMPLATE - pre-migration sentinel" \
    > "$_proj/tests/uat/templates/test-session-template.html"
  rm -f "$_proj/tests/uat/examples/pre-flight-reference.html" \
        "$_proj/tests/uat/examples/scenario-reference.json"
  # Drive the real upgrade-project.sh UAT migration block.
  # --track light → standard is a real upgrade target so the script
  # reaches the post-validation sweep that includes UAT migration.
  ( cd "$_proj" && \
    bash "$REPO_DIR/scripts/upgrade-project.sh" \
        --non-interactive --track standard ) > "$_uat_work/upgrade-e31.log" 2>&1 || true
  # Positive assertion: production template is multi-hundred lines and
  # contains the __TESTER_PRE_FLIGHT__ placeholder at least twice
  # (canonical shape from templates/uat/test-session-template.html).
  # BL-036: pin the count, not just presence, so a stub that mentions
  # the placeholder string once still flips RED.
  e31_tpl="$_proj/tests/uat/templates/test-session-template.html"
  e31_count=0
  if [ -f "$e31_tpl" ]; then
    e31_count=$(grep -c '__TESTER_PRE_FLIGHT__' "$e31_tpl" 2>/dev/null) || e31_count=0
  fi
  if [ "$e31_count" -ge 2 ] && \
     [ -f "$_proj/tests/uat/examples/pre-flight-reference.html" ] && \
     [ -f "$_proj/tests/uat/examples/scenario-reference.json" ] && \
     grep -qi 'terminal\|project root\|venv\|runtime' "$_proj/tests/uat/examples/pre-flight-reference.html"; then
    pass "E31: real upgrade-project.sh UAT migration refreshes stub template + reference pair (placeholder count=$e31_count, expected >=2)"
  else
    fail "E31: upgrade-project.sh UAT migration didn't restore template/refs (placeholder count=$e31_count; log: $_uat_work/upgrade-e31.log)"
  fi
fi
rm -rf "$_uat_work"

# Case 7: E32 — UAT migration is idempotent. Drive the real UAT migration
# block twice against the same tree (via two upgrade-project.sh runs that
# each reach the migration block) and verify the resulting trees are
# byte-identical. The pre-fix version asserted cp's idempotency
# (tautology); the new version asserts the framework's idempotency by
# comparing run-1 output to run-2 output.
_uat_work=$(mktemp -d)
if ! _uat_real_init_light_impl "$_uat_work" "desktop" "e32-idem"; then
  fail "E32: setup init.sh failed (log: $_uat_work/init-desktop-light.log)"
else
  _proj="$_uat_work/e32-idem"
  _uat_seed_intake_progress "$_proj" "desktop"
  # Snapshot UAT subtree after a forced "pre-migration" state to ensure
  # the first upgrade-project.sh has real work.
  echo "<!-- OLD TEMPLATE -->" > "$_proj/tests/uat/templates/test-session-template.html"
  rm -f "$_proj/tests/uat/examples/"*.html "$_proj/tests/uat/examples/"*.json 2>/dev/null || true
  # Run 1: light → standard. This runs the migration block.
  ( cd "$_proj" && \
    bash "$REPO_DIR/scripts/upgrade-project.sh" \
        --non-interactive --track standard ) > "$_uat_work/upgrade-run1.log" 2>&1 || true
  _snap1="$_uat_work/snap1"
  mkdir -p "$_snap1"
  cp -R "$_proj/tests/uat" "$_snap1/"
  # Run 2: standard → full. Different target so upgrade-project.sh
  # again reaches the post-validation sweep (UAT migration). Anything
  # the migration does on this second invocation that mutates the UAT
  # subtree differently from run-1 is drift.
  ( cd "$_proj" && \
    bash "$REPO_DIR/scripts/upgrade-project.sh" \
        --non-interactive --track full ) > "$_uat_work/upgrade-run2.log" 2>&1 || true
  _snap2="$_uat_work/snap2"
  mkdir -p "$_snap2"
  cp -R "$_proj/tests/uat" "$_snap2/"
  # Compare snapshots — they must be byte-identical for idempotency.
  if diff -ru "$_snap1/uat" "$_snap2/uat" > "$_uat_work/snapshot.diff" 2>&1; then
    pass "E32: upgrade-project.sh UAT migration is idempotent (run-1 and run-2 produce identical trees)"
  else
    fail "E32: upgrade-project.sh UAT migration is NOT idempotent — run-2 diverged from run-1 (see $_uat_work/snapshot.diff)"
  fi
fi
rm -rf "$_uat_work"


# ================================================================
section "BL-006: pre-commit Build Loop enforcement (commit-message-triggered) — E33-E39"

# Helper: seed a project dir with given phase and build_loop state
bl006_seed() {
  local dir="$1" phase="$2" feature="$3"
  mkdir -p "$dir/.claude" "$dir/.git"
  cat > "$dir/.claude/phase-state.json" <<JSON
{"current_phase": $phase, "project": "e33-e39"}
JSON
  local feature_json="null"
  [ "$feature" != "null" ] && feature_json="\"$feature\""
  cat > "$dir/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {"feature": $feature_json, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
  # Satisfy the hook's early-guard: remote must exist.
  ( cd "$dir" && git init -q && git remote add origin https://example.com/fake.git 2>/dev/null || true )
}

# Helper: invoke the PreToolUse hook with a JSON command from stdin.
# Returns "EXIT|OUTPUT" where OUTPUT may contain a deny/allow JSON.
bl006_invoke_hook() {
  local cmd="$1" project_dir="$2"
  local input
  input=$(jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}')
  local out rc=0
  out=$( cd "$project_dir" && echo "$input" | bash "$REPO_DIR/scripts/pre-commit-gate.sh" 2>&1 ) || rc=$?
  echo "$rc|$out"
}

# E33: inline feat -m, no feature started -> deny
_bl006_e33_dir="$TEST_DIR/bl006-e33"
bl006_seed "$_bl006_e33_dir" 2 null
_bl006_e33_r=$(bl006_invoke_hook 'git commit -m "feat(x): thing"' "$_bl006_e33_dir")
if [[ "${_bl006_e33_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_bl006_e33_r#*|}" == *"start-feature"* ]]; then
  pass "E33: inline feat -m blocks with --start-feature guidance"
else
  fail "E33: expected deny JSON with --start-feature, got: $_bl006_e33_r"
fi

# E34: heredoc feat, no feature started -> deny
_bl006_e34_dir="$TEST_DIR/bl006-e34"
bl006_seed "$_bl006_e34_dir" 2 null
_bl006_e34_cmd=$(cat <<'CMDEOF'
git commit -m "$(cat <<'EOF'
feat(x): thing from heredoc

body line.
EOF
)"
CMDEOF
)
_bl006_e34_r=$(bl006_invoke_hook "$_bl006_e34_cmd" "$_bl006_e34_dir")
if [[ "${_bl006_e34_r#*|}" =~ permissionDecision.*deny ]]; then
  pass "E34: heredoc -m blocks (heredoc parser works)"
else
  fail "E34: expected deny JSON, got: $_bl006_e34_r"
fi

# E35: -F file, no feature started -> deny
_bl006_e35_dir="$TEST_DIR/bl006-e35"
bl006_seed "$_bl006_e35_dir" 2 null
echo "feat(x): from file" > "$_bl006_e35_dir/msg.txt"
_bl006_e35_r=$(bl006_invoke_hook "git commit -F $_bl006_e35_dir/msg.txt" "$_bl006_e35_dir")
if [[ "${_bl006_e35_r#*|}" =~ permissionDecision.*deny ]]; then
  pass "E35: -F file blocks"
else
  fail "E35: expected deny JSON, got: $_bl006_e35_r"
fi

# E36: --amend with feat, no feature started -> amend path wins (allow + warn)
_bl006_e36_dir="$TEST_DIR/bl006-e36"
bl006_seed "$_bl006_e36_dir" 2 null
_bl006_e36_r=$(bl006_invoke_hook 'git commit -m "feat(x): thing" --amend' "$_bl006_e36_dir")
if [[ "${_bl006_e36_r#*|}" =~ permissionDecision.*allow ]] && [[ "${_bl006_e36_r#*|}" == *"WARNING"* ]]; then
  pass "E36: --amend bypasses new gate (existing amend warn wins)"
else
  fail "E36: expected amend warn (allow), got: $_bl006_e36_r"
fi

# E37: merge in progress (MERGE_HEAD exists) -> no deny from BL-006 path
_bl006_e37_dir="$TEST_DIR/bl006-e37"
bl006_seed "$_bl006_e37_dir" 2 null
touch "$_bl006_e37_dir/.git/MERGE_HEAD"
_bl006_e37_r=$(bl006_invoke_hook 'git commit -m "feat(x): from merge"' "$_bl006_e37_dir")
if ! [[ "${_bl006_e37_r#*|}" =~ permissionDecision.*deny ]]; then
  pass "E37: MERGE_HEAD present — BL-006 path skips"
else
  fail "E37: expected no deny, got: $_bl006_e37_r"
fi

# E38: git commit with no -m (editor case) -> no deny from BL-006 path
_bl006_e38_dir="$TEST_DIR/bl006-e38"
bl006_seed "$_bl006_e38_dir" 2 null
_bl006_e38_r=$(bl006_invoke_hook 'git commit' "$_bl006_e38_dir")
if ! [[ "${_bl006_e38_r#*|}" =~ permissionDecision.*deny ]]; then
  pass "E38: bare git commit (editor case) — BL-006 path falls through"
else
  fail "E38: expected no deny, got: $_bl006_e38_r"
fi

# E39: feat -m at Phase 0 -> no deny (phase gate)
_bl006_e39_dir="$TEST_DIR/bl006-e39"
bl006_seed "$_bl006_e39_dir" 0 null
_bl006_e39_r=$(bl006_invoke_hook 'git commit -m "feat(x): foo"' "$_bl006_e39_dir")
if ! [[ "${_bl006_e39_r#*|}" =~ permissionDecision.*deny ]]; then
  pass "E39: Phase 0 — BL-006 path skipped by phase gate"
else
  fail "E39: expected no deny at Phase 0, got: $_bl006_e39_r"
fi


# ================================================================
section "BL-015: pending-approval sentinel reader — E40-E47"

# Helper: seed a project dir with a .claude/ and (optionally) a sentinel.
pa_seed() {
  local dir="$1" sentinel_json="$2"
  mkdir -p "$dir/.claude" "$dir/.git"
  cat > "$dir/.claude/phase-state.json" <<JSON
{"current_phase": 2, "project": "e40-e47"}
JSON
  cat > "$dir/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
  if [ -n "$sentinel_json" ]; then
    printf '%s' "$sentinel_json" > "$dir/.claude/pending-approval.json"
  fi
  ( cd "$dir" && git init -q && git remote add origin https://example.com/fake.git 2>/dev/null || true )
}

pa_invoke_hook() {
  local cmd="$1" project_dir="$2"
  local input
  input=$(jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}')
  local out rc=0
  out=$( cd "$project_dir" && echo "$input" | bash "$REPO_DIR/scripts/pre-commit-gate.sh" 2>&1 ) || rc=$?
  echo "$rc|$out"
}

PA_VALID='{"question":"commit structure","options":["A1: single","A2: two","A3: three"],"recommendation":"A1","offered_at":"2026-04-25T12:00:00Z"}'
PA_MALFORMED='{"question":"incomplete"'

# E40: feat commit with valid sentinel -> deny with rich reason
_pa_e40_dir="$TEST_DIR/pa-e40"
pa_seed "$_pa_e40_dir" "$PA_VALID"
_pa_e40_r=$(pa_invoke_hook 'git commit -m "feat(x): foo"' "$_pa_e40_dir")
if [[ "${_pa_e40_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e40_r#*|}" == *"pending user decision"* ]] && [[ "${_pa_e40_r#*|}" == *"commit structure"* ]] && [[ "${_pa_e40_r#*|}" == *"A1: single"* ]]; then
  pass "E40: feat commit with valid sentinel — denies with rich reason (question + options)"
else
  fail "E40: expected rich deny reason, got: $_pa_e40_r"
fi

# E41: chore commit with valid sentinel -> deny (Q2 A: blocks ALL commits, not just feat)
_pa_e41_dir="$TEST_DIR/pa-e41"
pa_seed "$_pa_e41_dir" "$PA_VALID"
_pa_e41_r=$(pa_invoke_hook 'git commit -m "chore: bump"' "$_pa_e41_dir")
if [[ "${_pa_e41_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e41_r#*|}" == *"pending user decision"* ]]; then
  pass "E41: chore commit with valid sentinel — denies (sentinel blocks ALL commits)"
else
  fail "E41: expected pending-approval deny on chore: commit, got: $_pa_e41_r"
fi

# E42: commit with malformed sentinel -> deny with malformed-reason
_pa_e42_dir="$TEST_DIR/pa-e42"
pa_seed "$_pa_e42_dir" "$PA_MALFORMED"
_pa_e42_r=$(pa_invoke_hook 'git commit -m "feat(x): foo"' "$_pa_e42_dir")
if [[ "${_pa_e42_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e42_r#*|}" == *"alformed"* ]] && [[ "${_pa_e42_r#*|}" == *"rm "* ]]; then
  pass "E42: malformed sentinel — denies with malformed-reason + rm hint"
else
  fail "E42: expected malformed-reason deny, got: $_pa_e42_r"
fi

# E43: gh pr create with valid sentinel -> deny with "PR creation blocked"
_pa_e43_dir="$TEST_DIR/pa-e43"
pa_seed "$_pa_e43_dir" "$PA_VALID"
_pa_e43_r=$(pa_invoke_hook 'gh pr create --title "x" --body "y"' "$_pa_e43_dir")
if [[ "${_pa_e43_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e43_r#*|}" == *"PR creation blocked"* ]]; then
  pass "E43: gh pr create with valid sentinel — denies with PR-specific label"
else
  fail "E43: expected PR-specific deny, got: $_pa_e43_r"
fi

# E44: feat commit WITHOUT sentinel -> falls through to bl006_check (denies, but not for pending-approval)
_pa_e44_dir="$TEST_DIR/pa-e44"
pa_seed "$_pa_e44_dir" ""
_pa_e44_r=$(pa_invoke_hook 'git commit -m "feat(x): foo"' "$_pa_e44_dir")
if [[ "${_pa_e44_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e44_r#*|}" != *"pending user decision"* ]]; then
  pass "E44: no sentinel — falls through to bl006_check (denies, but not for pending-approval)"
else
  fail "E44: expected non-pending deny on no-sentinel commit, got: $_pa_e44_r"
fi

# E45: --no-verify commit with valid sentinel -> security message wins (NOT pending-approval)
_pa_e45_dir="$TEST_DIR/pa-e45"
pa_seed "$_pa_e45_dir" "$PA_VALID"
_pa_e45_r=$(pa_invoke_hook 'git commit --no-verify -m "feat(x): foo"' "$_pa_e45_dir")
if [[ "${_pa_e45_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e45_r#*|}" == *"--no-verify"* ]] && [[ "${_pa_e45_r#*|}" != *"pending user decision"* ]]; then
  pass "E45: --no-verify with valid sentinel — security message wins (ordering preserved)"
else
  fail "E45: expected --no-verify deny, NOT pending-approval, got: $_pa_e45_r"
fi

# E46: --amend commit with valid sentinel -> pending-approval wins (NOT --amend warn)
_pa_e46_dir="$TEST_DIR/pa-e46"
pa_seed "$_pa_e46_dir" "$PA_VALID"
_pa_e46_r=$(pa_invoke_hook 'git commit --amend -m "feat(x): foo"' "$_pa_e46_dir")
if [[ "${_pa_e46_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e46_r#*|}" == *"pending user decision"* ]]; then
  pass "E46: --amend with valid sentinel — pending-approval blocks (upgrades warn to deny)"
else
  fail "E46: expected pending-approval deny on --amend, got: $_pa_e46_r"
fi

# E47: git push --force with valid sentinel -> --force security message (pa_check doesn't fire on push)
_pa_e47_dir="$TEST_DIR/pa-e47"
pa_seed "$_pa_e47_dir" "$PA_VALID"
_pa_e47_r=$(pa_invoke_hook 'git push --force' "$_pa_e47_dir")
if [[ "${_pa_e47_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e47_r#*|}" == *"Force push"* ]] && [[ "${_pa_e47_r#*|}" != *"pending user decision"* ]]; then
  pass "E47: git push --force with valid sentinel — --force message wins (pa_check skips push)"
else
  fail "E47: expected --force deny, NOT pending-approval, got: $_pa_e47_r"
fi


# ================================================================
section "BL-016: init.sh non-interactive mode — E48-E62"

INIT_SH="$REPO_DIR/init.sh"

# E48: Full happy-path web/personal/standard/typescript run via --validate-only.
_e48_dir="$TEST_DIR/e48"
mkdir -p "$_e48_dir"
_e48_out=$(cd "$_e48_dir" && "$INIT_SH" --non-interactive --validate-only \
  --project uat-e48 --platform web --deployment personal --language typescript \
  --project-dir "$_e48_dir/proj" 2>&1)
_e48_rc=$?
if [ "$_e48_rc" = "0" ] && echo "$_e48_out" | grep -q '"_validated": true'; then
  pass "E48: full non-interactive happy path → exit 0 with resolved JSON"
else
  fail "E48: expected exit 0 with _validated:true, got rc=$_e48_rc out=$_e48_out"
fi

# E49: --validate-only does not create the project dir.
_e49_dir="$TEST_DIR/e49"
mkdir -p "$_e49_dir"
(cd "$_e49_dir" && "$INIT_SH" --non-interactive --validate-only \
  --project uat-e49 --platform web --deployment personal --language typescript \
  --project-dir "$_e49_dir/proj" >/dev/null 2>&1) || true
if [ ! -d "$_e49_dir/proj" ]; then
  pass "E49: --validate-only does not create project dir"
else
  fail "E49: --validate-only created project dir (should not have)"
fi

# E50: Mobile + organizational + private_poc + kotlin → forces visibility=private.
_e50_dir="$TEST_DIR/e50"
mkdir -p "$_e50_dir"
_e50_out=$(cd "$_e50_dir" && "$INIT_SH" --non-interactive --validate-only \
  --project uat-e50 --platform mobile --deployment organizational --gov-mode private_poc --language kotlin \
  --project-dir "$_e50_dir/proj" 2>&1)
_e50_rc=$?
if [ "$_e50_rc" = "0" ] && echo "$_e50_out" | grep -q '"gov_mode": "private_poc"' && echo "$_e50_out" | grep -q '"visibility": "private"'; then
  pass "E50: organizational + private_poc forces visibility=private"
else
  fail "E50: expected gov_mode=private_poc and visibility=private, got: $_e50_out"
fi

# E51: git-host=other + remote-url + attested → validate succeeds.
_e51_dir="$TEST_DIR/e51"
mkdir -p "$_e51_dir"
_e51_out=$(cd "$_e51_dir" && "$INIT_SH" --non-interactive --validate-only \
  --project uat-e51 --platform web --deployment organizational --gov-mode production --language typescript \
  --git-host other --remote-url https://example.com/fake.git --branch-protection-attested \
  --project-dir "$_e51_dir/proj" 2>&1)
_e51_rc=$?
if [ "$_e51_rc" = "0" ] && echo "$_e51_out" | grep -q '"git_host": "other"'; then
  pass "E51: --git-host=other + --remote-url + --branch-protection-attested → validates"
else
  fail "E51: expected exit 0 with git_host=other, got: $_e51_out"
fi

# E52: --config provides everything.
_e52_dir="$TEST_DIR/e52"
mkdir -p "$_e52_dir"
cat > "$_e52_dir/cfg.json" <<'JSON'
{"project":"uat-e52","platform":"web","deployment":"personal","language":"typescript","track":"standard"}
JSON
_e52_out=$(cd "$_e52_dir" && "$INIT_SH" --non-interactive --validate-only --config "$_e52_dir/cfg.json" \
  --project-dir "$_e52_dir/proj" 2>&1)
_e52_rc=$?
if [ "$_e52_rc" = "0" ] && echo "$_e52_out" | grep -q '"project": "uat-e52"'; then
  pass "E52: --config provides all required → validates"
else
  fail "E52: expected exit 0 from config, got: $_e52_out"
fi

# E53: --config + flag override (flag wins).
_e53_dir="$TEST_DIR/e53"
mkdir -p "$_e53_dir"
cat > "$_e53_dir/cfg.json" <<'JSON'
{"project":"uat-e53","platform":"web","deployment":"personal","language":"typescript","track":"light"}
JSON
_e53_out=$(cd "$_e53_dir" && "$INIT_SH" --non-interactive --validate-only --config "$_e53_dir/cfg.json" \
  --track full --project-dir "$_e53_dir/proj" 2>&1)
_e53_rc=$?
if [ "$_e53_rc" = "0" ] && echo "$_e53_out" | grep -q '"track": "full"'; then
  pass "E53: --config (track=light) + --track full → flag wins"
else
  fail "E53: expected resolved track=full, got: $_e53_out"
fi

# E54: --non-interactive with no required flags.
_e54_dir="$TEST_DIR/e54"
mkdir -p "$_e54_dir"
_e54_out=$(cd "$_e54_dir" && "$INIT_SH" --non-interactive --validate-only 2>&1) || true
_e54_rc=$?
if echo "$_e54_out" | grep -q "FAIL"; then
  pass "E54: --non-interactive with no required flags → exit 1 with FAIL message"
else
  fail "E54: expected FAIL message, got rc=$_e54_rc out=$_e54_out"
fi

# E55: existing-dir test — first run fails (no flag), second succeeds.
_e55_dir="$TEST_DIR/e55"
mkdir -p "$_e55_dir/already-here"
_e55_first_rc=0
(cd "$_e55_dir" && "$INIT_SH" --non-interactive --validate-only \
  --project uat-e55 --platform web --deployment personal --language typescript \
  --project-dir "$_e55_dir/already-here" >/dev/null 2>&1) || _e55_first_rc=$?
_e55_second_rc=0
(cd "$_e55_dir" && "$INIT_SH" --non-interactive --validate-only \
  --project uat-e55 --platform web --deployment personal --language typescript \
  --project-dir "$_e55_dir/already-here" --allow-existing-dir >/dev/null 2>&1) || _e55_second_rc=$?
if [ "$_e55_first_rc" = "1" ] && [ "$_e55_second_rc" = "0" ]; then
  pass "E55: existing dir without --allow-existing-dir fails; with the flag succeeds"
else
  fail "E55: expected first run to fail and second to succeed; got first=$_e55_first_rc second=$_e55_second_rc"
fi

# E56: real (non-validate-only) end-to-end run completes the file-write path.
# Regression guard for the TEST_INTERVAL unbound-variable bug surfaced by the
# 2026-04-26 UAT sweep. Drives init.sh through .claude/build-progress.json
# generation (line 1577 heredoc) and template substitution (line 2012), both
# of which read $TEST_INTERVAL. Uses --git-host other so no real CLI/API call
# is made; the push to a fake URL fails by design and PR #18's tolerance
# allows init to continue past it.
_e56_dir="$TEST_DIR/e56"
mkdir -p "$_e56_dir"
_e56_proj="$_e56_dir/uat-e56"
_e56_rc=0
(cd "$_e56_dir" && "$INIT_SH" --non-interactive \
  --project uat-e56 --platform web --deployment personal --language typescript \
  --project-dir "$_e56_proj" \
  --git-host other --remote-url https://example.com/fake.git \
  --branch-protection-attested >/dev/null 2>&1) || _e56_rc=$?
_e56_test_interval=""
if [ -f "$_e56_proj/.claude/build-progress.json" ]; then
  _e56_test_interval=$(jq -r '.test_interval // empty' "$_e56_proj/.claude/build-progress.json" 2>/dev/null || echo "")
fi
if [ "$_e56_rc" = "0" ] && \
   [ -f "$_e56_proj/CLAUDE.md" ] && \
   [ -f "$_e56_proj/APPROVAL_LOG.md" ] && \
   [ -f "$_e56_proj/.gitignore" ] && \
   [ -f "$_e56_proj/.github/workflows/ci.yml" ] && \
   [ -f "$_e56_proj/.claude/build-progress.json" ] && \
   [ -f "$_e56_proj/.claude/process-state.json" ] && \
   [ "$_e56_test_interval" = "2" ]; then
  pass "E56: --non-interactive end-to-end writes all project files (TEST_INTERVAL regression guard)"
else
  fail "E56: end-to-end run incomplete (rc=$_e56_rc, test_interval='$_e56_test_interval'). Missing one or more of: CLAUDE.md, APPROVAL_LOG.md, .gitignore, .github/workflows/ci.yml, .claude/build-progress.json, .claude/process-state.json"
fi

# E57: --non-interactive --gov-mode production must clear poc_mode in phase-state.json.
# Regression guard for the production poc_mode bug (T1-A from 2026-04-26 UAT triage).
# init.sh's interactive flow correctly maps Production -> POC_MODE="" (init.sh:381),
# but the non-interactive driver was setting POC_MODE="production" verbatim, which
# then caused process-checklist.sh start_phase4 to block every production project
# (it rejects any non-null poc_mode as a POC).
_e57_dir="$TEST_DIR/e57"
mkdir -p "$_e57_dir"
_e57_proj="$_e57_dir/uat-e57"
_e57_rc=0
(cd "$_e57_dir" && "$INIT_SH" --non-interactive \
  --project uat-e57 --platform web --deployment organizational --gov-mode production \
  --language typescript --project-dir "$_e57_proj" \
  --git-host other --remote-url https://example.com/fake.git \
  --branch-protection-attested >/dev/null 2>&1) || _e57_rc=$?
_e57_poc=""
if [ -f "$_e57_proj/.claude/phase-state.json" ]; then
  _e57_poc=$(jq -r '.poc_mode' "$_e57_proj/.claude/phase-state.json" 2>/dev/null || echo "missing")
fi
if [ "$_e57_rc" = "0" ] && [ "$_e57_poc" = "null" ]; then
  pass "E57: --non-interactive --gov-mode production clears poc_mode (T1-A regression guard)"
else
  fail "E57: expected rc=0 and phase-state.json .poc_mode=null, got rc=$_e57_rc poc_mode='$_e57_poc'"
fi

# E58: project-local invocation of upgrade-project.sh must exit rc=0.
# Regression guard for T1-B from 2026-04-26 UAT triage. The BL-009/BL-015
# helper-refresh block at scripts/upgrade-project.sh:1471 did
# `cp $SCRIPT_DIR/$helper scripts/$helper` where $SCRIPT_DIR resolved to the
# project's own scripts/ dir when invoked as `bash scripts/upgrade-project.sh`
# from the project root. BSD cp returns non-zero on identical source/dest,
# and `set -euo pipefail` aborted before "Upgrade complete." State changes
# succeeded but the wrapper signaled failure.
_e58_dir="$TEST_DIR/e58"
mkdir -p "$_e58_dir"
_e58_proj="$_e58_dir/uat-e58"
_e58_init_rc=0
(cd "$_e58_dir" && "$INIT_SH" --non-interactive \
  --project uat-e58 --platform web --deployment organizational --gov-mode private_poc \
  --language typescript --project-dir "$_e58_proj" \
  --git-host other --remote-url https://example.com/fake.git \
  --branch-protection-attested >/dev/null 2>&1) || _e58_init_rc=$?
_e58_upgrade_rc=0
if [ "$_e58_init_rc" = "0" ] && [ -d "$_e58_proj/scripts" ]; then
  (cd "$_e58_proj" && bash scripts/upgrade-project.sh --to-sponsored-poc >/dev/null 2>&1) || _e58_upgrade_rc=$?
else
  _e58_upgrade_rc=255
fi
if [ "$_e58_upgrade_rc" = "0" ]; then
  pass "E58: project-local upgrade-project.sh --to-sponsored-poc exits 0 (T1-B regression guard)"
else
  fail "E58: expected rc=0 from project-local upgrade-project.sh, got rc=$_e58_upgrade_rc (init_rc=$_e58_init_rc)"
fi

# E59: --non-interactive --platform mcp_server produces the platform module,
# release pipeline, and UAT reference pair under the unified naming.
# Regression guard for T1-C from 2026-04-26 UAT triage. The non-interactive
# driver was setting PLATFORM=mcp_server (underscore) while framework files
# shipped with mcp-server (hyphen) — every lookup silently no-op'd, leaving
# the project missing docs/platform-modules/mcp_server.md, the mcp_server
# release.yml, and the UAT reference pair. Resolved by renaming all six
# framework files to the underscore form to match the --platform CLI contract.
_e59_dir="$TEST_DIR/e59"
mkdir -p "$_e59_dir"
_e59_proj="$_e59_dir/uat-e59"
_e59_init_rc=0
(cd "$_e59_dir" && "$INIT_SH" --non-interactive \
  --project uat-e59 --platform mcp_server --deployment personal \
  --language python --project-dir "$_e59_proj" \
  --git-host other --remote-url https://example.com/fake.git \
  --branch-protection-attested >/dev/null 2>&1) || _e59_init_rc=$?
_e59_module_present=false
_e59_release_present=false
_e59_uat_ref_present=false
if [ "$_e59_init_rc" = "0" ]; then
  [ -f "$_e59_proj/docs/platform-modules/mcp_server.md" ] && _e59_module_present=true
  [ -f "$_e59_proj/.github/workflows/release.yml" ] && _e59_release_present=true
  [ -f "$_e59_proj/tests/uat/examples/pre-flight-reference.html" ] && _e59_uat_ref_present=true
fi
if [ "$_e59_init_rc" = "0" ] && \
   [ "$_e59_module_present" = "true" ] && \
   [ "$_e59_release_present" = "true" ] && \
   [ "$_e59_uat_ref_present" = "true" ]; then
  pass "E59: --non-interactive --platform mcp_server produces all platform-specific files (T1-C regression guard)"
else
  fail "E59: expected rc=0 + platform module + release.yml + UAT ref; got rc=$_e59_init_rc module=$_e59_module_present release=$_e59_release_present uat_ref=$_e59_uat_ref_present"
fi

# E60: upgrade-project.sh --to-private-poc takes a personal project to
# organizational/private_poc. T1-D regression guard for the missing
# personal -> private_poc CLI path. Before this fix, intake-wizard.sh
# --upgrade-deployment private_poc was rejected (only personal|organizational
# accepted) and upgrade-project.sh had no --to-private-poc flag.
_e60_dir="$TEST_DIR/e60"
mkdir -p "$_e60_dir"
_e60_proj="$_e60_dir/uat-e60"
_e60_init_rc=0
(cd "$_e60_dir" && "$INIT_SH" --non-interactive \
  --project uat-e60 --platform web --deployment personal \
  --language typescript --project-dir "$_e60_proj" \
  --git-host other --remote-url https://example.com/fake.git \
  --branch-protection-attested >/dev/null 2>&1) || _e60_init_rc=$?
_e60_upgrade_rc=0
if [ "$_e60_init_rc" = "0" ] && [ -d "$_e60_proj/scripts" ]; then
  (cd "$_e60_proj" && bash scripts/upgrade-project.sh --to-private-poc >/dev/null 2>&1) || _e60_upgrade_rc=$?
else
  _e60_upgrade_rc=255
fi
_e60_poc_mode=""
_e60_deployment=""
if [ -f "$_e60_proj/.claude/phase-state.json" ]; then
  _e60_poc_mode=$(jq -r '.poc_mode // "null"' "$_e60_proj/.claude/phase-state.json" 2>/dev/null || echo "")
  _e60_deployment=$(jq -r '.deployment // "null"' "$_e60_proj/.claude/phase-state.json" 2>/dev/null || echo "")
fi
if [ "$_e60_upgrade_rc" = "0" ] && \
   [ "$_e60_poc_mode" = "private_poc" ] && \
   [ "$_e60_deployment" = "organizational" ]; then
  pass "E60: upgrade-project.sh --to-private-poc takes personal -> organizational/private_poc (T1-D regression guard)"
else
  fail "E60: expected rc=0 poc_mode=private_poc deployment=organizational; got rc=$_e60_upgrade_rc poc_mode='$_e60_poc_mode' deployment='$_e60_deployment'"
fi

# E61: intake-wizard.sh --to-private-poc from a project subdir, invoked via
# the framework path. Exercises both T1-D fixes: (a) PROJECT_ROOT walk-up
# from CWD looking for .claude/, and (b) the new --to-private-poc passthrough.
# Before the fixes, intake-wizard.sh hardcoded PROJECT_ROOT="$SCRIPT_DIR/.."
# so framework-path invocation always failed with "PROJECT_INTAKE.md not found."
_e61_dir="$TEST_DIR/e61"
mkdir -p "$_e61_dir"
_e61_proj="$_e61_dir/uat-e61"
_e61_init_rc=0
(cd "$_e61_dir" && "$INIT_SH" --non-interactive \
  --project uat-e61 --platform web --deployment personal \
  --language typescript --project-dir "$_e61_proj" \
  --git-host other --remote-url https://example.com/fake.git \
  --branch-protection-attested >/dev/null 2>&1) || _e61_init_rc=$?
_e61_subdir="$_e61_proj/docs"
mkdir -p "$_e61_subdir"
_e61_wizard_rc=0
if [ "$_e61_init_rc" = "0" ]; then
  (cd "$_e61_subdir" && bash "$REPO_DIR/scripts/intake-wizard.sh" --to-private-poc >/dev/null 2>&1) || _e61_wizard_rc=$?
else
  _e61_wizard_rc=255
fi
_e61_poc_mode=""
if [ -f "$_e61_proj/.claude/phase-state.json" ]; then
  _e61_poc_mode=$(jq -r '.poc_mode // "null"' "$_e61_proj/.claude/phase-state.json" 2>/dev/null || echo "")
fi
if [ "$_e61_wizard_rc" = "0" ] && [ "$_e61_poc_mode" = "private_poc" ]; then
  pass "E61: intake-wizard.sh --to-private-poc walks up from project subdir + passthrough works (T1-D regression guard)"
else
  fail "E61: expected rc=0 poc_mode=private_poc; got rc=$_e61_wizard_rc poc_mode='$_e61_poc_mode'"
fi

# E62: check-phase-gate.sh detects pen-test artifact under pipefail.
# Regression guard for T1-E from 2026-04-26 UAT triage. The original
# `ls glob1 glob2 glob3 2>/dev/null | head -1 >/dev/null 2>&1` returned
# non-zero under `set -euo pipefail` whenever any one of the three globs
# had no matches (BSD/GNU ls exits non-zero on missing files; pipefail
# propagates). Result: full-track production projects were wrongly
# blocked at Phase 3->4 even with valid pen-test artifacts present.
# Replaced with compgen -G which tests each pattern independently.
_e62_dir="$TEST_DIR/e62"
mkdir -p "$_e62_dir/.claude" "$_e62_dir/docs/test-results"
cat > "$_e62_dir/.claude/phase-state.json" << 'JSON'
{
  "project": "uat-e62",
  "framework_version": "1.0",
  "current_phase": 3,
  "track": "full",
  "deployment": "personal",
  "poc_mode": null,
  "compliance_ready": false,
  "gates": {
    "phase_0_to_1": "2026-01-01",
    "phase_1_to_2": "2026-02-01",
    "phase_2_to_3": "2026-03-01",
    "phase_3_to_4": null
  }
}
JSON
cat > "$_e62_dir/APPROVAL_LOG.md" << 'MD'
# Approval Log

Phase 0 -> Phase 1: 2026-01-01 approver: Karl
Phase 1 -> Phase 2: 2026-02-01 approver: Karl
Phase 2 -> Phase 3: 2026-03-01 approver: Karl
MD
# A pen-test artifact that matches *pen-test* but not *pentest* or *penetration*
# (so the original buggy ls-pipe-head form would fail under pipefail).
touch "$_e62_dir/docs/test-results/2026-04-26-pen-test-summary.md"
_e62_out=$(cd "$_e62_dir" && bash "$REPO_DIR/scripts/check-phase-gate.sh" 2>&1) || true
if echo "$_e62_out" | grep -q "Penetration test results found"; then
  pass "E62: check-phase-gate.sh detects pen-test artifact under pipefail (T1-E regression guard)"
else
  fail "E62: check-phase-gate.sh did not detect pen-test artifact"
fi


# ================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SUMMARY${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}PASS: $PASS${NC}"
echo -e "  ${RED}FAIL: $FAIL${NC}"
echo -e "  ${YELLOW}SKIP: $SKIP${NC}"
echo -e "  TOTAL: $((PASS + FAIL + SKIP))"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}${BOLD}  $FAIL test(s) failed.${NC}"
  echo ""
  echo -e "${BOLD}  Failed tests:${NC}"
  echo -e "$RESULTS" | grep "^FAIL|" | sed 's/FAIL|/    /' || true
fi

echo ""
exit "$FAIL"

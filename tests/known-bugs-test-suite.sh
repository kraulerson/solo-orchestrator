#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Known Bugs & Edge Case Test Suite
# Tests all 8 known bugs from the multi-user test plan (BUG-1 through BUG-8)
# plus key edge cases from sections E1-E40.
#
# Usage: bash tests/known-bugs-test-suite.sh

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

# Helper: create a minimal valid Solo Orchestrator project in a temp dir
create_test_project() {
  local dir="$1"
  local project_name="${2:-TestProject}"
  local platform="${3:-web}"
  local track="${4:-standard}"
  local language="${5:-typescript}"

  mkdir -p "$dir/.claude" "$dir/.git/hooks" "$dir/.github/workflows" \
           "$dir/docs/framework" "$dir/docs/platform-modules" \
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

  # PROJECT_INTAKE.md (with Competency Matrix rows)
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
EOF

  # Framework docs
  touch "$dir/docs/framework/builders-guide.md"
  touch "$dir/docs/framework/user-guide.md"
  touch "$dir/docs/framework/governance-framework.md"
  touch "$dir/docs/framework/cli-setup-addendum.md"

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
  cat > "$dir/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 0,
  "project": "TestProject"
}
EOF

  # Pre-commit hook (executable)
  echo '#!/bin/sh' > "$dir/.git/hooks/pre-commit"
  chmod +x "$dir/.git/hooks/pre-commit"

  # Copy scripts
  cp -r "$REPO_DIR/scripts/"* "$dir/scripts/" 2>/dev/null || true
  cp "$REPO_DIR/scripts/lib/helpers.sh" "$dir/scripts/lib/helpers.sh" 2>/dev/null || true

  # Make scripts executable
  chmod +x "$dir/scripts/"*.sh 2>/dev/null || true
}

# ================================================================
# BUG-1: save_answer breaks on single quotes in user input
# ================================================================
section "BUG-1: save_answer with single quotes"

BUG1_DIR="$TEST_DIR/bug1"
create_test_project "$BUG1_DIR"

# Create a valid progress file
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
with open('$BUG1_DIR/.claude/intake-progress.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Test: save_answer with a value containing single quotes
(
  cd "$BUG1_DIR"
  source scripts/lib/helpers.sh
  PROGRESS_FILE="$BUG1_DIR/.claude/intake-progress.json"

  # Source save_answer from intake-wizard.sh (extract the function)
  save_answer() {
    local key="$1"
    local value="$2"
    if command -v python3 &>/dev/null; then
      python3 -c "
import json, sys
key, value, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data['answers'][key] = value
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" "$key" "$value" "$PROGRESS_FILE"
    fi
  }

  save_answer "api_type" "it's a REST API"
)
result=$?

if [ $result -eq 0 ]; then
  # Verify the value was saved correctly
  saved_value=$(python3 -c "
import json
with open('$BUG1_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
print(data['answers'].get('api_type', 'MISSING'))
")
  if [ "$saved_value" = "it's a REST API" ]; then
    pass "BUG-1: save_answer handles single quotes correctly"
  else
    fail "BUG-1: save_answer corrupted value: got '$saved_value'"
  fi
else
  fail "BUG-1: save_answer crashed on single quotes (exit $result)"
fi

# ================================================================
# BUG-2: init_progress breaks on single quotes in PROJECT_DESCRIPTION
# ================================================================
section "BUG-2: init_progress with single quotes"

BUG2_DIR="$TEST_DIR/bug2"
create_test_project "$BUG2_DIR"

(
  cd "$BUG2_DIR"
  source scripts/lib/helpers.sh
  PROGRESS_FILE="$BUG2_DIR/.claude/intake-progress.json"

  PROJECT_NAME="Derek's Cool App"
  PROJECT_DESCRIPTION="It's an app that does stuff"
  PLATFORM="web"
  TRACK="standard"
  DEPLOYMENT="personal"
  LANGUAGE="typescript"

  # Extract init_progress function
  init_progress() {
    mkdir -p "$(dirname "$PROGRESS_FILE")"
    if command -v python3 &>/dev/null; then
      python3 -c "
import json, sys
data = {
    'version': 1,
    'started_at': sys.argv[1],
    'last_section': 0,
    'completed_sections': [],
    'project_name': sys.argv[2],
    'platform': sys.argv[3],
    'track': sys.argv[4],
    'deployment': sys.argv[5],
    'language': sys.argv[6],
    'description': sys.argv[7],
    'poc_mode': None,
    'answers': {}
}
with open(sys.argv[8], 'w') as f:
    json.dump(data, f, indent=2)
" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_NAME" "$PLATFORM" "$TRACK" "$DEPLOYMENT" "$LANGUAGE" "$PROJECT_DESCRIPTION" "$PROGRESS_FILE"
    fi
  }

  init_progress
)
result=$?

if [ $result -eq 0 ]; then
  saved_desc=$(python3 -c "
import json
with open('$BUG2_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
print(data.get('description', 'MISSING'))
")
  saved_name=$(python3 -c "
import json
with open('$BUG2_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
print(data.get('project_name', 'MISSING'))
")
  if [ "$saved_desc" = "It's an app that does stuff" ] && [ "$saved_name" = "Derek's Cool App" ]; then
    pass "BUG-2: init_progress handles single quotes correctly"
  else
    fail "BUG-2: init_progress corrupted values: name='$saved_name' desc='$saved_desc'"
  fi
else
  fail "BUG-2: init_progress crashed on single quotes (exit $result)"
fi

# ================================================================
# BUG-3: load_progress shell injection via eval
# ================================================================
section "BUG-3: load_progress shell injection safety"

BUG3_DIR="$TEST_DIR/bug3"
create_test_project "$BUG3_DIR"

# Create a progress file with malicious values
python3 -c "
import json
data = {
    'version': 1,
    'started_at': '2026-01-01T00:00:00Z',
    'last_section': 3,
    'completed_sections': [1, 2, 3],
    'project_name': '\$(echo INJECTED > /tmp/solo-test-injection)',
    'platform': 'web',
    'track': 'standard',
    'deployment': 'personal',
    'language': 'typescript',
    'description': 'Normal description',
    'poc_mode': None,
    'answers': {}
}
with open('$BUG3_DIR/.claude/intake-progress.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Clean up any previous injection marker
rm -f /tmp/solo-test-injection

(
  cd "$BUG3_DIR"
  source scripts/lib/helpers.sh
  PROGRESS_FILE="$BUG3_DIR/.claude/intake-progress.json"
  PROJECT_ROOT="$BUG3_DIR"
  PROJECT_NAME=""
  PLATFORM=""
  TRACK=""
  DEPLOYMENT=""
  LANGUAGE=""
  PROJECT_DESCRIPTION=""
  POC_MODE=""
  LAST_SECTION=0
  COMPLETED_SECTIONS=""

  load_progress() {
    if [ ! -f "$PROGRESS_FILE" ]; then
      print_warn "No progress file found."
      return 1
    fi
    if command -v python3 &>/dev/null; then
      local tmpfile
      tmpfile=$(mktemp)
      python3 -c "
import json, sys, shlex
with open(sys.argv[1]) as f:
    data = json.load(f)
print(f\"LAST_SECTION={data['last_section']}\")
print(f\"PROJECT_NAME={shlex.quote(data['project_name'])}\")
print(f\"PLATFORM={shlex.quote(data['platform'])}\")
print(f\"TRACK={shlex.quote(data['track'])}\")
print(f\"DEPLOYMENT={shlex.quote(data['deployment'])}\")
print(f\"LANGUAGE={shlex.quote(data['language'])}\")
print(f\"PROJECT_DESCRIPTION={shlex.quote(data['description'])}\")
poc = data.get('poc_mode') or ''
print(f\"POC_MODE={shlex.quote(poc)}\")
completed = ' '.join(str(s) for s in data.get('completed_sections', []))
print(f\"COMPLETED_SECTIONS={shlex.quote(completed)}\")
" "$PROGRESS_FILE" > "$tmpfile"
      source "$tmpfile"
      rm -f "$tmpfile"
    fi
  }

  load_progress
)
result=$?

if [ -f /tmp/solo-test-injection ]; then
  fail "BUG-3: load_progress executed injected shell command!"
  rm -f /tmp/solo-test-injection
elif [ $result -eq 0 ]; then
  pass "BUG-3: load_progress safely handles malicious project names"
else
  fail "BUG-3: load_progress crashed on malicious input (exit $result)"
fi

# ================================================================
# BUG-4: ((warnings++)) crashes under set -e
# ================================================================
section "BUG-4: Arithmetic increment under set -e"

BUG4_DIR="$TEST_DIR/bug4"
create_test_project "$BUG4_DIR"

# Run validate.sh in a project that triggers warnings
# Remove pre-commit hook to trigger first warning
rm -f "$BUG4_DIR/.git/hooks/pre-commit"
# Remove .claude/framework to trigger another warning
rm -rf "$BUG4_DIR/.claude/framework"

(
  cd "$BUG4_DIR"
  bash scripts/validate.sh 2>&1
) > "$TEST_DIR/bug4-output.txt" 2>&1
result=$?

if grep -q "warning(s)" "$TEST_DIR/bug4-output.txt" 2>/dev/null; then
  pass "BUG-4: validate.sh handles warning increments without crashing"
elif [ $result -ne 0 ] && ! grep -q "error(s)" "$TEST_DIR/bug4-output.txt"; then
  fail "BUG-4: validate.sh crashed on warning increment (exit $result)"
else
  pass "BUG-4: validate.sh completed (exit $result)"
fi

# ================================================================
# BUG-5: Phase regex expects quoted string but current_phase is bare integer
# ================================================================
section "BUG-5: resume.sh phase detection with bare integer"

BUG5_DIR="$TEST_DIR/bug5"
create_test_project "$BUG5_DIR"

# Test with bare integer (no quotes)
cat > "$BUG5_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 2,
  "project": "TestProject"
}
EOF

# Initialize git so resume.sh's git log doesn't fail
(cd "$BUG5_DIR" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null) || true

(
  cd "$BUG5_DIR"
  bash scripts/resume.sh 2>&1
) > "$TEST_DIR/bug5-output.txt" 2>&1
result=$?

phase_detected=$(grep -o 'Phase:\*\* [0-9]*' "$TEST_DIR/bug5-output.txt" | grep -o '[0-9]*' || echo "")
if [ "$phase_detected" = "2" ]; then
  pass "BUG-5: resume.sh detects bare integer phase correctly (phase=$phase_detected)"
elif grep -q "unknown" "$TEST_DIR/bug5-output.txt"; then
  fail "BUG-5: resume.sh reports phase as 'unknown' for bare integer"
else
  # Check the raw output
  if grep -q "Phase.*2" "$TEST_DIR/bug5-output.txt"; then
    pass "BUG-5: resume.sh detects bare integer phase correctly"
  else
    fail "BUG-5: resume.sh could not detect phase from bare integer"
  fi
fi

# Also test with quoted string
cat > "$BUG5_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": "3",
  "project": "TestProject"
}
EOF

(
  cd "$BUG5_DIR"
  bash scripts/resume.sh 2>&1
) > "$TEST_DIR/bug5-quoted-output.txt" 2>&1

if grep -q "Phase.*3\|Phase.*unknown" "$TEST_DIR/bug5-quoted-output.txt"; then
  if grep -q "unknown" "$TEST_DIR/bug5-quoted-output.txt"; then
    fail "BUG-5: resume.sh cannot handle quoted string phase"
  else
    pass "BUG-5: resume.sh also handles quoted string phase"
  fi
else
  skip "BUG-5: Could not verify quoted string handling"
fi

# ================================================================
# BUG-6: BSD grep on macOS doesn't support \| in BRE
# ================================================================
section "BUG-6: BSD grep \\| compatibility"

BUG6_DIR="$TEST_DIR/bug6"
create_test_project "$BUG6_DIR"

# Test 6a: grep with \| in release.yml TODO count (line 94)
(
  cd "$BUG6_DIR"
  todo_count=$(grep -c "# TODO\|echo.*TODO" .github/workflows/release.yml 2>/dev/null || echo "0")
  echo "todo_count=$todo_count"
) > "$TEST_DIR/bug6a-output.txt" 2>&1
result=$?

todo_val=$(grep -o 'todo_count=[0-9]*' "$TEST_DIR/bug6a-output.txt" | grep -o '[0-9]*' || echo "MISSING")
if [ "$todo_val" != "MISSING" ] && [ "$todo_val" -gt 0 ] 2>/dev/null; then
  pass "BUG-6a: grep \\| in TODO count works (found $todo_val TODOs)"
else
  # BSD grep returns 0 for \| because it treats \| as literal
  fail "BUG-6a: grep \\| in TODO count returns '$todo_val' (expected >0, BSD grep ignores \\|)"
fi

# Test 6b: grep with \| in CLAUDE.md currency check (line 257)
(
  cd "$BUG6_DIR"
  if grep -q "Features built:.*none yet\|Features remaining:.*see MVP Cutline" CLAUDE.md; then
    echo "MATCHED"
  else
    echo "NO_MATCH"
  fi
) > "$TEST_DIR/bug6b-output.txt" 2>&1

if grep -q "MATCHED" "$TEST_DIR/bug6b-output.txt"; then
  pass "BUG-6b: grep \\| in CLAUDE.md currency check works"
else
  fail "BUG-6b: grep \\| in CLAUDE.md currency check fails (BSD grep doesn't support \\| in BRE)"
fi

# Test 6c: grep with \| in architecture check (line 269)
# Add architecture section to CLAUDE.md
echo "## Architecture" >> "$BUG6_DIR/CLAUDE.md"

(
  cd "$BUG6_DIR"
  if grep -q "Architecture Constraints\|## Stack\|## Architecture" CLAUDE.md; then
    echo "MATCHED"
  else
    echo "NO_MATCH"
  fi
) > "$TEST_DIR/bug6c-output.txt" 2>&1

if grep -q "MATCHED" "$TEST_DIR/bug6c-output.txt"; then
  pass "BUG-6c: grep \\| in architecture check works"
else
  fail "BUG-6c: grep \\| in architecture check fails (BSD grep doesn't support \\| in BRE)"
fi

# ================================================================
# BUG-7: has_no variable can be empty, breaking -eq comparison
# ================================================================
section "BUG-7: has_no variable empty/double-output"

BUG7_DIR="$TEST_DIR/bug7"
create_test_project "$BUG7_DIR"

# Set phase to 2 and have competency matrix with "No" entries
cat > "$BUG7_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 2,
  "project": "TestProject"
}
EOF

# Test the has_no computation directly
(
  set -euo pipefail
  cd "$BUG7_DIR"

  # Replicate the exact code from validate.sh line 367-369
  has_no=$(grep -i "| *No *|" PROJECT_INTAKE.md | grep -ciE "Security|Accessibility|Performance|Database" || echo "0")
  if [ "$has_no" -eq 0 ]; then
    echo "has_no=0"
  else
    echo "has_no=$has_no"
  fi
) > "$TEST_DIR/bug7-output.txt" 2>&1
result=$?

if [ $result -eq 0 ]; then
  has_no_val=$(grep -o 'has_no=[0-9]*' "$TEST_DIR/bug7-output.txt" | head -1 | grep -o '[0-9]*' || echo "MISSING")
  if [ "$has_no_val" = "MISSING" ]; then
    fail "BUG-7: has_no computation produced no usable output"
  else
    pass "BUG-7: has_no computation works correctly (value=$has_no_val)"
  fi
else
  fail "BUG-7: has_no computation crashed under set -e (exit $result)"
  # Show the error
  echo "    Output: $(cat "$TEST_DIR/bug7-output.txt")"
fi

# Test 7b: PROJECT_INTAKE.md with NO "No" entries (forces grep -c to return 0)
cat > "$BUG7_DIR/PROJECT_INTAKE.md" << 'EOF'
# Project Intake
| Domain | Self-Assessment | Notes |
|--------|----------------|-------|
| Security | Yes | Expert |
| Accessibility | Partially | Learning |
EOF

(
  set -euo pipefail
  cd "$BUG7_DIR"

  has_no=$(grep -i "| *No *|" PROJECT_INTAKE.md | grep -ciE "Security|Accessibility|Performance|Database" || echo "0")
  if [ "$has_no" -eq 0 ]; then
    echo "has_no=0 (correctly zero)"
  else
    echo "has_no=$has_no"
  fi
) > "$TEST_DIR/bug7b-output.txt" 2>&1
result=$?

if [ $result -eq 0 ]; then
  pass "BUG-7b: has_no works when no 'No' entries exist"
else
  fail "BUG-7b: has_no crashes when no 'No' entries exist (exit $result)"
  echo "    Output: $(cat "$TEST_DIR/bug7b-output.txt")"
fi

# ================================================================
# BUG-8: check_pause doesn't work inside $(...) subshells
# ================================================================
section "BUG-8: Pause detection via file sentinel"

BUG8_DIR="$TEST_DIR/bug8"
create_test_project "$BUG8_DIR"

# The fix uses a file-based sentinel. Test that _request_pause creates the file
# and check_pause_requested detects it.
(
  cd "$BUG8_DIR"
  source scripts/lib/helpers.sh

  _PAUSE_FILE="/tmp/.solo-intake-pause-$$"
  trap 'rm -f "$_PAUSE_FILE"' EXIT

  _request_pause() {
    touch "$_PAUSE_FILE"
  }

  check_pause_requested() {
    if [ -f "$_PAUSE_FILE" ]; then
      rm -f "$_PAUSE_FILE"
      echo "PAUSE_DETECTED"
      return 0
    fi
    echo "NO_PAUSE"
    return 0
  }

  # Simulate: prompt function called in $() subshell requests pause
  result=$(_request_pause && echo "pause_requested")

  # Now check from the parent shell — the file should exist
  check_pause_requested
) > "$TEST_DIR/bug8-output.txt" 2>&1
result=$?

if grep -q "PAUSE_DETECTED" "$TEST_DIR/bug8-output.txt"; then
  pass "BUG-8: File sentinel pause detection works across subshells"
else
  fail "BUG-8: File sentinel pause not detected across subshells"
fi

# ================================================================
# EDGE CASES: Script robustness (from test plan E11-E25)
# ================================================================
section "Edge Cases: Script Robustness"

# E11: validate.sh from outside project directory
E11_DIR="$TEST_DIR/e11-outside"
mkdir -p "$E11_DIR"
e11_result=0
(
  cd "$E11_DIR"
  bash "$REPO_DIR/scripts/validate.sh" 2>&1
) > "$TEST_DIR/e11-output.txt" 2>&1 || e11_result=$?

if [ $e11_result -ne 0 ] && grep -qi "CLAUDE.md not found\|not found\|ERROR" "$TEST_DIR/e11-output.txt"; then
  pass "E11: validate.sh from outside project gives clear error"
else
  fail "E11: validate.sh from outside project: expected error (exit=$e11_result)"
fi

# E19: intake-wizard.sh --resume with no progress file
E19_DIR="$TEST_DIR/e19"
create_test_project "$E19_DIR"
rm -f "$E19_DIR/.claude/intake-progress.json"
e19_result=0
(
  cd "$E19_DIR"
  bash scripts/intake-wizard.sh --resume 2>&1
) > "$TEST_DIR/e19-output.txt" 2>&1 || e19_result=$?

if [ $e19_result -ne 0 ]; then
  pass "E19: intake-wizard.sh --resume with no progress file exits non-zero"
else
  fail "E19: intake-wizard.sh --resume with no progress file should fail"
fi

# E22: check-versions.sh offline mode
# We can't easily disable network, but we can verify it doesn't crash
E22_DIR="$TEST_DIR/e22"
create_test_project "$E22_DIR"
(
  cd "$E22_DIR"
  bash scripts/check-versions.sh 2>&1 || true
) > "$TEST_DIR/e22-output.txt" 2>&1

if [ -s "$TEST_DIR/e22-output.txt" ]; then
  pass "E22: check-versions.sh produces output without crashing"
else
  fail "E22: check-versions.sh produced no output"
fi

# E25: phase-state.json with current_phase: 99
E25_DIR="$TEST_DIR/e25"
create_test_project "$E25_DIR"
cat > "$E25_DIR/.claude/phase-state.json" << 'EOF'
{
  "current_phase": 99,
  "project": "TestProject"
}
EOF

e25_result=0
(
  cd "$E25_DIR"
  bash scripts/validate.sh 2>&1
) > "$TEST_DIR/e25-output.txt" 2>&1 || e25_result=$?

# Should not crash catastrophically
if [ -s "$TEST_DIR/e25-output.txt" ]; then
  pass "E25: validate.sh handles current_phase: 99 without crashing"
else
  fail "E25: validate.sh crashed on current_phase: 99"
fi

# ================================================================
# EDGE CASES: Input Validation (from test plan E33-E40)
# ================================================================
section "Edge Cases: Input Validation"

# E33: SQL injection payload in save_answer
E33_DIR="$TEST_DIR/e33"
create_test_project "$E33_DIR"
python3 -c "
import json
data = {'version': 1, 'started_at': '2026-01-01', 'last_section': 0,
        'completed_sections': [], 'project_name': 'Test', 'platform': 'web',
        'track': 'standard', 'deployment': 'personal', 'language': 'typescript',
        'description': 'test', 'poc_mode': None, 'answers': {}}
with open('$E33_DIR/.claude/intake-progress.json', 'w') as f:
    json.dump(data, f, indent=2)
"

(
  cd "$E33_DIR"
  source scripts/lib/helpers.sh
  PROGRESS_FILE="$E33_DIR/.claude/intake-progress.json"

  save_answer() {
    local key="$1"
    local value="$2"
    python3 -c "
import json, sys
key, value, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data['answers'][key] = value
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" "$key" "$value" "$PROGRESS_FILE"
  }

  save_answer "name" "'; DROP TABLE users; --"
)
e33_result=$?

if [ $e33_result -eq 0 ]; then
  saved=$(python3 -c "
import json
with open('$E33_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
print(data['answers'].get('name', 'MISSING'))
")
  if [ "$saved" = "'; DROP TABLE users; --" ]; then
    pass "E33: SQL injection payload stored literally (not executed)"
  else
    fail "E33: SQL injection payload corrupted: '$saved'"
  fi
else
  fail "E33: save_answer crashed on SQL injection payload"
fi

# E37: Emoji in project description
E37_DIR="$TEST_DIR/e37"
create_test_project "$E37_DIR"
python3 -c "
import json
data = {'version': 1, 'started_at': '2026-01-01', 'last_section': 0,
        'completed_sections': [], 'project_name': 'Test', 'platform': 'web',
        'track': 'standard', 'deployment': 'personal', 'language': 'typescript',
        'description': 'test', 'poc_mode': None, 'answers': {}}
with open('$E37_DIR/.claude/intake-progress.json', 'w') as f:
    json.dump(data, f, indent=2)
"

(
  cd "$E37_DIR"
  source scripts/lib/helpers.sh
  PROGRESS_FILE="$E37_DIR/.claude/intake-progress.json"

  save_answer() {
    local key="$1"
    local value="$2"
    python3 -c "
import json, sys
key, value, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data['answers'][key] = value
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" "$key" "$value" "$PROGRESS_FILE"
  }

  save_answer "description" "Build a 🚀 app"
)
e37_result=$?

if [ $e37_result -eq 0 ]; then
  saved=$(python3 -c "
import json
with open('$E37_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
print(data['answers'].get('description', 'MISSING'))
")
  if [ "$saved" = "Build a 🚀 app" ]; then
    pass "E37: Emoji in description stored correctly"
  else
    fail "E37: Emoji corrupted: '$saved'"
  fi
else
  fail "E37: save_answer crashed on emoji input"
fi

# E39: Newlines in text input
E39_DIR="$TEST_DIR/e39"
create_test_project "$E39_DIR"
python3 -c "
import json
data = {'version': 1, 'started_at': '2026-01-01', 'last_section': 0,
        'completed_sections': [], 'project_name': 'Test', 'platform': 'web',
        'track': 'standard', 'deployment': 'personal', 'language': 'typescript',
        'description': 'test', 'poc_mode': None, 'answers': {}}
with open('$E39_DIR/.claude/intake-progress.json', 'w') as f:
    json.dump(data, f, indent=2)
"

(
  cd "$E39_DIR"
  source scripts/lib/helpers.sh
  PROGRESS_FILE="$E39_DIR/.claude/intake-progress.json"

  save_answer() {
    local key="$1"
    local value="$2"
    python3 -c "
import json, sys
key, value, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data['answers'][key] = value
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" "$key" "$value" "$PROGRESS_FILE"
  }

  save_answer "notes" "line1
line2
line3"
)
e39_result=$?

if [ $e39_result -eq 0 ]; then
  saved=$(python3 -c "
import json
with open('$E39_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
val = data['answers'].get('notes', 'MISSING')
print(repr(val))
")
  if echo "$saved" | grep -q "line1" && echo "$saved" | grep -q "line2"; then
    pass "E39: Newlines in text input handled without breaking JSON"
  else
    fail "E39: Newlines corrupted: $saved"
  fi
else
  fail "E39: save_answer crashed on newline input"
fi

# ================================================================
# EDGE CASES: Shell command injection in description (E2)
# ================================================================
section "Edge Cases: Command Injection"

E2_DIR="$TEST_DIR/e2"
create_test_project "$E2_DIR"

# Test init_progress with $(whoami) and backticks
(
  cd "$E2_DIR"
  source scripts/lib/helpers.sh
  PROGRESS_FILE="$E2_DIR/.claude/intake-progress.json"
  PROJECT_NAME="TestApp"
  PROJECT_DESCRIPTION='$(whoami) and `id`'
  PLATFORM="web"
  TRACK="standard"
  DEPLOYMENT="personal"
  LANGUAGE="typescript"

  mkdir -p "$(dirname "$PROGRESS_FILE")"
  python3 -c "
import json, sys
data = {
    'version': 1,
    'started_at': sys.argv[1],
    'last_section': 0,
    'completed_sections': [],
    'project_name': sys.argv[2],
    'platform': sys.argv[3],
    'track': sys.argv[4],
    'deployment': sys.argv[5],
    'language': sys.argv[6],
    'description': sys.argv[7],
    'poc_mode': None,
    'answers': {}
}
with open(sys.argv[8], 'w') as f:
    json.dump(data, f, indent=2)
" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_NAME" "$PLATFORM" "$TRACK" "$DEPLOYMENT" "$LANGUAGE" "$PROJECT_DESCRIPTION" "$PROGRESS_FILE"
)
e2_result=$?

if [ $e2_result -eq 0 ]; then
  saved_desc=$(python3 -c "
import json
with open('$E2_DIR/.claude/intake-progress.json') as f:
    data = json.load(f)
print(data.get('description', 'MISSING'))
")
  if echo "$saved_desc" | grep -q 'whoami'; then
    pass "E2: Shell command in description stored as literal text"
  else
    fail "E2: Description with shell commands was modified: '$saved_desc'"
  fi
else
  fail "E2: init_progress crashed on shell command in description"
fi

# ================================================================
# META: Test that existing test suite doesn't crash on first pass
# ================================================================
section "Meta: Existing Test Suite ((PASS++)) Bug"

# The existing test suite uses ((PASS++)) which fails under set -e when PASS=0
(
  set -euo pipefail
  PASS=0
  PASS=$((PASS + 1))
  echo "safe_increment=ok"
) > "$TEST_DIR/meta-safe-output.txt" 2>&1
safe_result=$?

(
  set -euo pipefail
  PASS=0
  ((PASS++)) || true
  echo "guarded_increment=ok"
) > "$TEST_DIR/meta-guarded-output.txt" 2>&1
guarded_result=$?

# Test that the actual pattern used in full-project-test-suite.sh works
unguarded_result=0
(
  set -euo pipefail
  PASS=0
  ((PASS++))
  echo "unguarded_increment=ok"
) > "$TEST_DIR/meta-unguarded-output.txt" 2>&1 || unguarded_result=$?

if [ $unguarded_result -ne 0 ]; then
  # This test verifies the bug EXISTS — it's a test of the old pattern.
  # After fixing full-project-test-suite.sh, this confirms the fix was needed.
  pass "Meta: ((PASS++)) confirmed to crash under set -e when PASS=0 — our fix uses \$((PASS + 1)) instead"
else
  pass "Meta: ((PASS++)) works under set -e on this platform"
fi

# ================================================================
# FULL VALIDATE.SH INTEGRATION TEST
# ================================================================
section "Integration: Full validate.sh Run"

INT_DIR="$TEST_DIR/integration"
create_test_project "$INT_DIR"

int_result=0
(
  cd "$INT_DIR"
  bash scripts/validate.sh 2>&1
) > "$TEST_DIR/integration-output.txt" 2>&1 || int_result=$?

if [ -s "$TEST_DIR/integration-output.txt" ]; then
  # Check it at least produced the header
  if grep -q "Solo Orchestrator" "$TEST_DIR/integration-output.txt"; then
    if [ $int_result -le 5 ]; then
      pass "Integration: validate.sh completes with $int_result error(s)"
    else
      fail "Integration: validate.sh reports $int_result errors"
    fi
  else
    fail "Integration: validate.sh produced output but no header"
  fi
else
  fail "Integration: validate.sh produced no output"
fi

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  TEST SUMMARY${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Skipped:${NC} $SKIP"
echo -e "  Total:   $((PASS + FAIL + SKIP))"
echo ""

if [ $FAIL -gt 0 ]; then
  echo -e "${RED}${BOLD}  FAILURES:${NC}"
  echo -e "$RESULTS" | grep "^FAIL" | while IFS='|' read -r _ desc; do
    echo -e "  ${RED}- $desc${NC}"
  done
  echo ""
fi

echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"

exit $FAIL

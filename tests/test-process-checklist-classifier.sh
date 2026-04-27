#!/usr/bin/env bash
# tests/test-process-checklist-classifier.sh — T2-A regression test.
# Verifies that scripts/process-checklist.sh --check-commit-ready treats
# common dependency-manifest files (Pipfile, Pipfile.lock, requirements*.txt,
# Gemfile, Gemfile.lock, Cargo.lock, go.mod, go.sum, poetry.lock, yarn.lock,
# pnpm-lock.yaml, etc.) as exempt — same as docs — instead of source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Project state: Phase 2, init verified, no active build_loop. Staging a
# dep-manifest commit at this point should NOT trigger the build_loop gate.
setup_project() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    mkdir -p .claude
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","phases":{}}
JSON
    cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"verified":true,"steps_completed":["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied","initialization_verified"]},"build_loop":{},"uat_session":{"started_at":"null","steps_completed":[]}}
JSON
  )
}
teardown_project() { rm -rf "$TMPDIR_T"; }

# Stage a single file with given content; commit-ready check should pass.
stage_and_check() {
  local label="$1" file="$2"
  setup_project
  (
    cd "$TMPDIR_T"
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    echo "test content" > "$file"
    git add "$file"
  )
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --check-commit-ready 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "$label" "expected exit 0 for dep-manifest commit ($file), got rc=$rc out=$out"
    teardown_project
    return
  fi
  pass "$label: $file commit allowed (exempt as dep-manifest)"
  teardown_project
}

# Negative: a real source file should still be blocked.
stage_and_check_blocked() {
  local label="$1" file="$2"
  setup_project
  (
    cd "$TMPDIR_T"
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    echo "test content" > "$file"
    git add "$file"
  )
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --check-commit-ready 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "$label" "expected non-zero exit for source commit ($file), got rc=0 out=$out"
    teardown_project
    return
  fi
  pass "$label: $file commit blocked (source — build_loop gate active)"
  teardown_project
}

echo "== tests/test-process-checklist-classifier.sh =="
stage_and_check "T1"  "Pipfile"
stage_and_check "T2"  "Pipfile.lock"
stage_and_check "T3"  "requirements.txt"
stage_and_check "T4"  "requirements-dev.txt"
stage_and_check "T5"  "Gemfile"
stage_and_check "T6"  "Gemfile.lock"
stage_and_check "T7"  "Cargo.lock"
stage_and_check "T8"  "go.mod"
stage_and_check "T9"  "go.sum"
stage_and_check "T10" "poetry.lock"
stage_and_check "T11" "yarn.lock"
stage_and_check_blocked "T12" "src/main.py"

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

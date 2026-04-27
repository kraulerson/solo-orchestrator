#!/usr/bin/env bash
# tests/test-check-gate.sh — unit tests for scripts/check-gate.sh.
# Currently covers --backfill-host (T2-E: --yes flag for non-interactive use).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-gate.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_project() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git remote add origin https://github.com/example/foo.git
    mkdir -p .claude
    echo '{"frameworkVersion":"test","mode":"personal"}' > .claude/manifest.json
  )
}

teardown_project() {
  rm -rf "$TMPDIR_T"
}

t1_yes_flag_writes_host_non_interactive() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --backfill-host --yes </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "expected exit 0 with --yes, got rc=$rc out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ "$host" != "github" ]; then
    fail_ "T1" "expected host='github', got host='$host'"
    teardown_project
    return
  fi
  pass "T1: --backfill-host --yes writes manifest.host non-interactively"
  teardown_project
}

t2_interactive_y_still_works() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && echo y | "$SCRIPT" --backfill-host 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T2" "expected exit 0 with stdin 'y', got rc=$rc out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ "$host" != "github" ]; then
    fail_ "T2" "expected host='github', got host='$host'"
    teardown_project
    return
  fi
  pass "T2: --backfill-host with stdin 'y' still writes manifest.host (regression)"
  teardown_project
}

t3_interactive_n_aborts() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && echo n | "$SCRIPT" --backfill-host 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T3" "expected non-zero exit on 'n', got rc=0 out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ -n "$host" ]; then
    fail_ "T3" "expected host unset on abort, got host='$host'"
    teardown_project
    return
  fi
  pass "T3: --backfill-host with stdin 'n' aborts (regression, host not written)"
  teardown_project
}

t4_yes_flag_before_subcommand() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --yes --backfill-host </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T4" "expected exit 0 with --yes before --backfill-host, got rc=$rc out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ "$host" != "github" ]; then
    fail_ "T4" "expected host='github', got host='$host'"
    teardown_project
    return
  fi
  pass "T4: --yes accepted before --backfill-host"
  teardown_project
}

echo "== tests/test-check-gate.sh =="
t1_yes_flag_writes_host_non_interactive
t2_interactive_y_still_works
t3_interactive_n_aborts
t4_yes_flag_before_subcommand

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

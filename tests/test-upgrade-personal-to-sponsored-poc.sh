#!/usr/bin/env bash
# tests/test-upgrade-personal-to-sponsored-poc.sh — R3-A regression test.
#
# scripts/upgrade-project.sh --to-sponsored-poc on a personal/light project
# previously failed with "[FAIL] Cannot downgrade a production project to POC
# mode." because the guard at line 436 checked only `[ -z "$CURRENT_POC_MODE" ]`
# without verifying that `$CURRENT_DEPLOYMENT == organizational`. Personal
# projects always have poc_mode=null but deployment=personal — the guard
# treated them as production. Symmetric with PR #24's T1-D fix to
# --to-private-poc at line 440.
#
# Surfaced by rev3 sweep agent 12 (TRIAGE R3-A).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_personal_project() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git remote add origin https://example.com/fake.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"other"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"light","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"light","deployment":"personal"}
JSON
  )
}

setup_production_project() {
  # Real production project: deployment=organizational, poc_mode=null.
  # The guard MUST still fire for this case.
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git remote add origin https://example.com/fake.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"org","host":"other"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"standard","deployment":"organizational","poc_mode":null,"current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"standard","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"standard","deployment":"organizational"}
JSON
  )
}

teardown_project() { rm -rf "$TMPDIR_T"; }

t1_personal_to_sponsored_poc_succeeds() {
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-sponsored-poc </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "expected exit 0 (R3-A), got rc=$rc; tail:\n$(echo "$out" | tail -5)"
    teardown_project
    return
  fi
  local deploy poc_mode
  deploy=$(jq -r '.deployment // empty' "$TMPDIR_T/.claude/phase-state.json")
  poc_mode=$(jq -r '.poc_mode // empty' "$TMPDIR_T/.claude/phase-state.json")
  if [ "$deploy" != "organizational" ] || [ "$poc_mode" != "sponsored_poc" ]; then
    fail_ "T1" "expected deployment=organizational + poc_mode=sponsored_poc, got deploy=$deploy poc_mode=$poc_mode"
    teardown_project
    return
  fi
  pass "T1: --to-sponsored-poc on personal baseline succeeds; phase-state correctly updated"
  teardown_project
}

t2_production_to_sponsored_poc_still_blocked() {
  setup_production_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-sponsored-poc </dev/null 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T2" "guard regression — production project should still be blocked from --to-sponsored-poc; rc=$rc"
    teardown_project
    return
  fi
  # Either guard message is acceptable — line 361 ("already organizational/production")
  # fires first for org+null projects, and line 435-438 ("Cannot downgrade a production
  # project") may also fire if execution reaches it. The post-fix behavior must still
  # block this transition with one of the two messages.
  if ! echo "$out" | grep -qE "(Cannot downgrade a production project to POC mode|Project is already organizational/production)"; then
    fail_ "T2" "expected production-block message; got:\n$(echo "$out" | tail -5)"
    teardown_project
    return
  fi
  pass "T2: --to-sponsored-poc on production baseline still blocked (regression guard)"
  teardown_project
}

t3_personal_to_private_poc_still_succeeds() {
  # T1-D regression coverage — make sure our fix doesn't break --to-private-poc.
  setup_personal_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-private-poc </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T3" "T1-D regression — --to-private-poc on personal should still succeed; rc=$rc tail:\n$(echo "$out" | tail -5)"
    teardown_project
    return
  fi
  pass "T3: --to-private-poc on personal baseline still works (T1-D regression check)"
  teardown_project
}

echo "== tests/test-upgrade-personal-to-sponsored-poc.sh =="
t1_personal_to_sponsored_poc_succeeds
t2_production_to_sponsored_poc_still_blocked
t3_personal_to_private_poc_still_succeeds

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

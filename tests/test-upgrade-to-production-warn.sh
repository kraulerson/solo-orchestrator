#!/usr/bin/env bash
# tests/test-upgrade-to-production-warn.sh — T2-F regression test +
# tests-upgrade-paths-10 Phase-4 unblock invariant assertions.
#
# Two regression suites in one file:
#
# (T1-T3, T2-F)
#   Verifies that scripts/upgrade-project.sh --to-production emits a
#   [WARN] line when the project's track is auto-bumped (e.g.,
#   light -> standard).
#
# (T4-T6, tests-upgrade-paths-10)
#   Audit finding tests-upgrade-paths-10: no test asserted that
#   --to-production clears poc_mode AND removes the Phase-4 enforcement
#   blocks at BOTH points named in Baseline §5 Invariant #3:
#     1. scripts/check-phase-gate.sh (Phase 3→4 CI gate, line 597)
#     2. scripts/process-checklist.sh --start-phase4 (line 559)
#   The JSON-clear-only test (T2) above is a necessary but not
#   sufficient end-to-end check; if a future change updates one
#   enforcement point but not the other, the JSON test still passes.
#   T4-T6 invoke both gate scripts after a successful --to-production
#   and assert neither emits the 'poc_mode' block message.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

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
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"github"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"light","deployment":"organizational","poc_mode":"private_poc","current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"light","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"light","deployment":"organizational"}
JSON
  )
}

teardown_project() { rm -rf "$TMPDIR_T"; }

t1_warn_emitted_on_track_bump_light_to_standard() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production </dev/null 2>&1) || rc=$?
  if ! echo "$out" | grep -qE '\[WARN\].*track.*(light|standard)'; then
    fail_ "T1" "expected [WARN] line about track bump (light->standard); rc=$rc out:\n$out"
    teardown_project
    return
  fi
  pass "T1: --to-production emits [WARN] when track auto-bumps light->standard"
  teardown_project
}

t2_no_warn_when_track_already_standard() {
  setup_project
  jq '.track = "standard"' "$TMPDIR_T/.claude/phase-state.json" > "$TMPDIR_T/.claude/phase-state.json.tmp" \
    && mv "$TMPDIR_T/.claude/phase-state.json.tmp" "$TMPDIR_T/.claude/phase-state.json"
  jq '.context.track = "standard"' "$TMPDIR_T/.claude/tool-preferences.json" > "$TMPDIR_T/.claude/tool-preferences.json.tmp" \
    && mv "$TMPDIR_T/.claude/tool-preferences.json.tmp" "$TMPDIR_T/.claude/tool-preferences.json"
  jq '.track = "standard"' "$TMPDIR_T/.claude/intake-progress.json" > "$TMPDIR_T/.claude/intake-progress.json.tmp" \
    && mv "$TMPDIR_T/.claude/intake-progress.json.tmp" "$TMPDIR_T/.claude/intake-progress.json"
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production </dev/null 2>&1) || rc=$?
  if echo "$out" | grep -qE '\[WARN\].*track.*bump'; then
    fail_ "T2" "should not emit track-bump [WARN] when already standard; out:\n$out"
    teardown_project
    return
  fi
  pass "T2: --to-production does NOT emit track-bump [WARN] when already standard"
  teardown_project
}

t3_help_documents_track_bump() {
  local out
  out=$("$SCRIPT" --help 2>&1)
  if ! echo "$out" | grep -qiE 'to-production.*(track|bump|light.*standard|auto)'; then
    fail_ "T3" "--help should mention track auto-bump for --to-production; got:\n$out"
    return
  fi
  pass "T3: --help mentions track auto-bump for --to-production"
}

# ────────────────────────────────────────────────────────────────────
# tests-upgrade-paths-10: Phase-4 unblock invariant end-to-end
# ────────────────────────────────────────────────────────────────────
#
# Sets up an organizational sponsored_poc fixture at current_phase=3
# with all 6 Pre-Phase-0 rows dated (so --to-production accepts), runs
# --to-production --non-interactive, then invokes BOTH Phase-4
# enforcement points and asserts neither still blocks on poc_mode.
#
# Enforcement points being guarded:
#   1. scripts/check-phase-gate.sh                 (line 597)
#   2. scripts/process-checklist.sh --start-phase4 (line 559)
# Both emit the substring "is BLOCKED" / "is blocked" with the
# "${poc_mode//_/ } mode" template when poc_mode is set. We assert the
# absence of those substrings post-upgrade.

setup_org_sponsored_at_phase3() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email t@t.local
    git config user.name "Test User"
    git remote add origin https://github.com/example/foo.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"organizational","host":"github","deployment":"organizational","poc_mode":"sponsored_poc","enforcement_level":"strict"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc","current_phase":3,"phases":{},"phase_0_to_1":"2026-06-27","phase_1_to_2":"2026-06-27","phase_2_to_3":"2026-06-27"}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"standard","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc"}
JSON
  )
  _write_approval_log_org_6_dated "$TMPDIR_T/APPROVAL_LOG.md"
  ( cd "$TMPDIR_T" && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

_write_approval_log_org_6_dated() {
  local path="$1"
  local d="2026-06-27"
  declare -a labels=(
    "AI deployment path approved"
    "Insurance coverage confirmed"
    "Liability entity designated"
    "Project sponsor assigned"
    "Backup maintainer designated"
    "ITSM project registered"
  )
  {
    cat <<'HDR'
---
project: test
deployment: organizational
created: 2026-06-27
framework: Solo Orchestrator v1.0
---

# Approval Log — test

## Pre-Phase 0: Organizational Pre-Conditions

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
HDR
    local i
    for i in 1 2 3 4 5 6; do
      local idx=$((i - 1))
      local label="${labels[$idx]}"
      printf '| %d | %s | Jane Approver | IT Security | %s | Email | TICKET-%d | |\n' \
        "$i" "$label" "$d" "$i"
    done
    echo
    echo "## Approval History"
    echo
    echo "| Date | Gate / Event | Decision | Notes |"
    echo "|---|---|---|---|"
    echo "| | | | |"
  } > "$path"
}

# T4: --to-production clears poc_mode in .claude/phase-state.json.
# This is the JSON-only invariant assertion (mirrors T2 in
# test-upgrade-project-atomic / test-upgrade-to-production-preconditions
# but as a pre-condition for the gate scripts in T5/T6).
t4_to_production_clears_poc_mode_json() {
  setup_org_sponsored_at_phase3
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null 2>&1) || rc=$?
  if [ "$rc" != "0" ]; then
    fail_ "T4" "--to-production failed at rc=$rc; tail:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  local pm; pm=$(jq -r '.poc_mode // "null"' "$TMPDIR_T/.claude/phase-state.json")
  if [ "$pm" != "null" ] && [ -n "$pm" ]; then
    fail_ "T4" "poc_mode not cleared in phase-state.json after --to-production; pm='$pm'"
    teardown_project; return
  fi
  pass "T4: --to-production clears poc_mode in .claude/phase-state.json"
  # NOTE: do NOT teardown — T5/T6 reuse the post-upgrade fixture.
}

# T5: check-phase-gate.sh no longer emits the Phase-4 poc_mode block
# message after --to-production. Enforcement point #1 of Baseline §5
# Invariant #3.
t5_check_phase_gate_no_poc_block_post_upgrade() {
  # Reuse the post-T4 fixture; sanity check we still have it.
  if [ -z "${TMPDIR_T:-}" ] || [ ! -d "$TMPDIR_T" ]; then
    fail_ "T5" "T4 fixture missing — cannot continue"
    return
  fi
  local out rc=0
  out=$(cd "$TMPDIR_T" && bash "$REPO_ROOT/scripts/check-phase-gate.sh" 2>&1) || rc=$?
  # Phase 4 (production release) is BLOCKED — project is in sponsored poc mode.
  if echo "$out" | grep -qE 'Phase 4 .*BLOCKED.* mode'; then
    fail_ "T5" "check-phase-gate.sh still emits Phase-4 poc_mode block after upgrade; out:\n$(echo "$out" | grep -E 'BLOCKED|poc_mode' | head -5)"
    teardown_project; return
  fi
  pass "T5: scripts/check-phase-gate.sh does NOT block Phase 4 on poc_mode after --to-production (enforcement point #1)"
  # Hold the fixture for T6.
}

# T6: process-checklist.sh --start-phase4 succeeds after --to-production.
# Enforcement point #2 of Baseline §5 Invariant #3.
t6_process_checklist_start_phase4_post_upgrade() {
  if [ -z "${TMPDIR_T:-}" ] || [ ! -d "$TMPDIR_T" ]; then
    fail_ "T6" "T4 fixture missing — cannot continue"
    return
  fi
  local out rc=0
  out=$(cd "$TMPDIR_T" && bash "$REPO_ROOT/scripts/process-checklist.sh" --start-phase4 </dev/null 2>&1) || rc=$?
  if [ "$rc" != "0" ]; then
    fail_ "T6" "process-checklist.sh --start-phase4 failed at rc=$rc post-upgrade; tail:\n$(echo "$out" | tail -10)"
    teardown_project; return
  fi
  if echo "$out" | grep -qE 'Phase 4 .*blocked.* mode'; then
    fail_ "T6" "process-checklist.sh --start-phase4 still emits poc_mode block after upgrade; out:\n$(echo "$out" | tail -10)"
    teardown_project; return
  fi
  # Positive assertion: state file should now show Phase 4 started.
  if [ -f "$TMPDIR_T/.claude/process-state.json" ]; then
    local started_at
    started_at=$(jq -r '.phase4_release.started_at // "null"' "$TMPDIR_T/.claude/process-state.json" 2>/dev/null)
    if [ "$started_at" = "null" ] || [ -z "$started_at" ]; then
      fail_ "T6" "phase4_release.started_at not populated in process-state.json (got '$started_at')"
      teardown_project; return
    fi
  fi
  pass "T6: scripts/process-checklist.sh --start-phase4 succeeds after --to-production (enforcement point #2)"
  teardown_project
}

echo "== tests/test-upgrade-to-production-warn.sh =="
t1_warn_emitted_on_track_bump_light_to_standard
t2_no_warn_when_track_already_standard
t3_help_documents_track_bump
t4_to_production_clears_poc_mode_json
t5_check_phase_gate_no_poc_block_post_upgrade
t6_process_checklist_start_phase4_post_upgrade

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

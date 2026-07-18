#!/usr/bin/env bash
# tests/test-process-checklist-auto-advance.sh — U-D regression test.
#
# Before this fix, scripts/process-checklist.sh wrote phase progress into
# .claude/process-state.json (start-phaseN markers, --verify-init flips,
# auto-verify on the final --complete-step) but NEVER updated
# .claude/phase-state.json::current_phase. The user had to `jq` patch
# current_phase manually between phases.
#
# Fix: each phase-entry path also calls _set_current_phase_min(N), which
# bumps .current_phase to at least N (never downgrades).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_phase_zero_project() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    git remote add origin https://example.com/fake.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"other"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":0,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
JSON
    # BL-114: --start-phase1 now consults the 0->1 gate — give the fixture a
    # CLEAR gate (approval row with a dated Date cell, 8-section manifesto,
    # the three Step-0 intermediates) so the auto-advance mechanics under
    # test run against a passing gate.
    cat > APPROVAL_LOG.md <<'MD'
# Approval Log

## Phase Gate: Phase 0 -> Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |
MD
    for n in 1 2 3 4 5 6 7 8; do
      { echo "## ${n}. Section ${n}"; echo "Substantive content ${n}."; echo ""; } >> PRODUCT_MANIFESTO.md
    done
    mkdir -p docs/phase-0
    printf 'frd\n' > docs/phase-0/frd.md
    printf 'journey\n' > docs/phase-0/user-journey.md
    printf 'contract\n' > docs/phase-0/data-contract.md
    cat > .claude/process-state.json <<'JSON'
{
  "phase1_architecture":{"steps_completed":[],"started_at":null},
  "phase2_init":{"verified":false,"steps_completed":[],"started_at":null},
  "phase3_validation":{"steps_completed":[],"started_at":null},
  "phase4_release":{"steps_completed":[],"started_at":null},
  "build_loop":{"feature":null,"step":0,"steps_completed":[]},
  "uat_session":{"session_id":null,"step":0,"steps_completed":[],"started_at":null}
}
JSON
  )
}
teardown_project() { rm -rf "$TMPDIR_T"; }

current_phase_in() { jq -r '.current_phase' "$1/.claude/phase-state.json"; }

t1_start_phase1_advances_to_1() {
  setup_phase_zero_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --start-phase1 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "expected exit 0; rc=$rc out:\n$out"
    teardown_project; return
  fi
  local got; got=$(current_phase_in "$TMPDIR_T")
  if [ "$got" != "1" ]; then
    fail_ "T1" "expected current_phase=1 after --start-phase1, got $got"
    teardown_project; return
  fi
  pass "T1: --start-phase1 advances .current_phase 0 → 1"
  teardown_project
}

t2_verify_init_advances_to_2() {
  setup_phase_zero_project
  # Pre-condition: phase 1 done, ready to verify-init. Set up so verify_init
  # can auto-mark phase2_init.verified — easier path is to mark all 6 prereq
  # steps directly via jq, then run --verify-init which checks them.
  jq '.current_phase = 1' "$TMPDIR_T/.claude/phase-state.json" > "$TMPDIR_T/.claude/phase-state.json.tmp" && mv "$TMPDIR_T/.claude/phase-state.json.tmp" "$TMPDIR_T/.claude/phase-state.json"
  jq '.phase2_init.steps_completed = ["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied"]' "$TMPDIR_T/.claude/process-state.json" > "$TMPDIR_T/.claude/process-state.json.tmp" && mv "$TMPDIR_T/.claude/process-state.json.tmp" "$TMPDIR_T/.claude/process-state.json"
  # Provide the artifacts verify_init checks for.
  (
    cd "$TMPDIR_T"
    mkdir -p .github/workflows .git/hooks
    echo "stub" > .github/workflows/ci.yml
    echo "stub" > package-lock.json
    echo "#!/bin/sh" > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
  )
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --verify-init 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T2" "expected exit 0; rc=$rc out:\n$out"
    teardown_project; return
  fi
  local got; got=$(current_phase_in "$TMPDIR_T")
  if [ "$got" -lt 2 ]; then
    fail_ "T2" "expected current_phase >= 2 after --verify-init success, got $got"
    teardown_project; return
  fi
  pass "T2: --verify-init success advances .current_phase to ≥ 2 (got $got)"
  teardown_project
}

t3_start_phase3_advances_to_3() {
  setup_phase_zero_project
  jq '.current_phase = 2' "$TMPDIR_T/.claude/phase-state.json" > "$TMPDIR_T/.claude/phase-state.json.tmp" && mv "$TMPDIR_T/.claude/phase-state.json.tmp" "$TMPDIR_T/.claude/phase-state.json"
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --start-phase3 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T3" "expected exit 0; rc=$rc out:\n$out"
    teardown_project; return
  fi
  local got; got=$(current_phase_in "$TMPDIR_T")
  if [ "$got" != "3" ]; then
    fail_ "T3" "expected current_phase=3 after --start-phase3, got $got"
    teardown_project; return
  fi
  pass "T3: --start-phase3 advances .current_phase 2 → 3"
  teardown_project
}

t4_start_phase4_advances_to_4() {
  # REWRITTEN under the documented-bug exception (BL-105): this case used to
  # pin the OPPOSITE — that --start-phase4 advances 3→4 with NO gate consult
  # (the walk cut a tagged release from a zero state through exactly that
  # hole). --start-phase4 now consults --gate phase_3_to_4 first; on this
  # deliberately gate-failing fixture it must REFUSE and leave state
  # untouched (no phase advance, no phase4_release init). The refusal + both
  # mutation directions are pinned in test-bl105-phase4-wave.sh; the
  # PASS-path advance mechanics (post-consult body — identical shape to
  # start_phase1's, which T1 covers on its pass path) remain a recorded
  # residual pending a golden 3→4 fixture.
  setup_phase_zero_project
  jq '.current_phase = 3' "$TMPDIR_T/.claude/phase-state.json" > "$TMPDIR_T/.claude/phase-state.json.tmp" && mv "$TMPDIR_T/.claude/phase-state.json.tmp" "$TMPDIR_T/.claude/phase-state.json"
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --start-phase4 2>&1) || rc=$?
  local got; got=$(current_phase_in "$TMPDIR_T")
  if [ "$rc" -ne 0 ] && [ "$got" = "3" ] && ! jq -e '.phase4_release.started_at // empty' "$TMPDIR_T/.claude/process-state.json" >/dev/null 2>&1; then
    pass "T4: --start-phase4 REFUSES on a failing 3→4 gate and leaves state untouched (BL-105)"
  else
    fail_ "T4" "expected refusal with untouched state on a failing gate; rc=$rc phase=$got phase4_release=$(jq -c '.phase4_release // "absent"' "$TMPDIR_T/.claude/process-state.json")"
  fi
  teardown_project
}

t5_no_downgrade_when_already_advanced() {
  # Regression: if user has manually advanced past N, don't downgrade them.
  setup_phase_zero_project
  jq '.current_phase = 3' "$TMPDIR_T/.claude/phase-state.json" > "$TMPDIR_T/.claude/phase-state.json.tmp" && mv "$TMPDIR_T/.claude/phase-state.json.tmp" "$TMPDIR_T/.claude/phase-state.json"
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --start-phase1 2>&1) || rc=$?
  local got; got=$(current_phase_in "$TMPDIR_T")
  if [ "$got" != "3" ]; then
    fail_ "T5" "regression — --start-phase1 downgraded current_phase from 3 to $got"
    teardown_project; return
  fi
  pass "T5: re-running --start-phase1 with current_phase=3 does NOT downgrade"
  teardown_project
}

# --- tests-precommit-process-8: POC mode blocks --start-phase4 ---
# Phase 4 (production release) must be blocked when poc_mode is set.
# The block must:
#   1. Exit non-zero (rc != 0).
#   2. Leave current_phase at 3 (no auto-advance via _set_current_phase_min).
#   3. Print the upgrade-project.sh --to-production remediation hint to stderr.
# Two cases: t6 = private_poc, t7 = sponsored_poc. Pins the block at
# scripts/process-checklist.sh:start_phase4().
_t_start_phase4_poc_blocked() {
  local label="$1" mode="$2"
  setup_phase_zero_project
  # Seed: current_phase=3, poc_mode=<mode>.
  jq --arg m "$mode" '.current_phase = 3 | .poc_mode = $m' \
    "$TMPDIR_T/.claude/phase-state.json" > "$TMPDIR_T/.claude/phase-state.json.tmp" \
    && mv "$TMPDIR_T/.claude/phase-state.json.tmp" "$TMPDIR_T/.claude/phase-state.json"

  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --start-phase4 2>&1) || rc=$?

  # 1. Non-zero exit.
  if [ "$rc" -eq 0 ]; then
    fail_ "$label" "expected non-zero exit for poc_mode=$mode; got rc=0 out:\n$out"
    teardown_project; return
  fi

  # 2. current_phase unchanged (still 3).
  local got; got=$(current_phase_in "$TMPDIR_T")
  if [ "$got" != "3" ]; then
    fail_ "$label" "current_phase advanced from 3 → $got despite POC block (poc_mode=$mode)"
    teardown_project; return
  fi

  # 3. Remediation hint present.
  if ! printf '%s' "$out" | grep -q 'upgrade-project.sh --to-production'; then
    fail_ "$label" "expected 'upgrade-project.sh --to-production' remediation hint in stderr; got:\n$out"
    teardown_project; return
  fi

  pass "$label: --start-phase4 blocked under poc_mode=$mode (rc=$rc, phase stayed at 3, remediation shown)"
  teardown_project
}

t6_start_phase4_private_poc_blocked() {
  _t_start_phase4_poc_blocked "T6" "private_poc"
}

t7_start_phase4_sponsored_poc_blocked() {
  _t_start_phase4_poc_blocked "T7" "sponsored_poc"
}

echo "== tests/test-process-checklist-auto-advance.sh =="
t1_start_phase1_advances_to_1
t2_verify_init_advances_to_2
t3_start_phase3_advances_to_3
t4_start_phase4_advances_to_4
t5_no_downgrade_when_already_advanced
t6_start_phase4_private_poc_blocked
t7_start_phase4_sponsored_poc_blocked

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

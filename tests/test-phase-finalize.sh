#!/usr/bin/env bash
# tests/test-phase-finalize.sh — Audit S2 cluster 3 regression tests
#
# Pre-fix, process-checklist.sh blocked every source commit during
# Phase 3 / Phase 4 until ALL validation/release steps were marked
# complete. This violated baseline §3.4 (phase enforcement at
# transitions, not at every commit) and made iterative fix commits
# during validation impossible. After 2026-06 fix:
#   - check_commit_ready does NOT enforce all-steps during Phase 3 / 4.
#   - New --finalize-phase {3|4} command performs the strict check at
#     the operator's explicit closeout step (callable from CI tag-push).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKLIST="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a fresh project skeleton that process-checklist.sh recognizes.
setup_phase() {
  local target_phase="$1"
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  printf '%s\n' '{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}' \
    > "$TMP/.claude/manifest.json"
  cat > "$TMP/.claude/phase-state.json" <<JSON
{
  "project": "test",
  "framework_version": "1.0",
  "current_phase": $target_phase,
  "track": "standard",
  "deployment": "personal",
  "poc_mode": null,
  "compliance_ready": false,
  "gates": {"phase_0_to_1": null, "phase_1_to_2": null, "phase_3_to_4": null}
}
JSON
  cat > "$TMP/.claude/process-state.json" <<'JSON'
{
  "phase1_pre_construction": {"steps_completed": [], "started_at": "2026-01-01T00:00:00Z"},
  "phase3_validation":       {"steps_completed": [], "started_at": "2026-01-01T00:00:00Z"},
  "phase4_release":          {"steps_completed": [], "started_at": "2026-01-01T00:00:00Z"}
}
JSON
}
teardown() { rm -rf "$TMP"; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== check-commit-ready no longer blocks mid-phase commits ==="
# ════════════════════════════════════════════════════════════════════

# T1: in Phase 3 with zero steps complete, check-commit-ready exits 0.
setup_phase 3
( cd "$TMP" && bash "$CHECKLIST" --check-commit-ready ) > "$TMP/log" 2>&1
rc=$?
if [ "$rc" = "0" ]; then
  pass "T1: Phase 3 check-commit-ready passes with 0/9 steps complete"
else
  fail_ "T1" "rc=$rc (expected 0; iterative Phase 3 commits should not be blocked). Log: $(tail -3 "$TMP/log" | tr '\n' '|')"
fi
teardown

# T2: in Phase 4 with zero steps complete, check-commit-ready exits 0.
setup_phase 4
( cd "$TMP" && bash "$CHECKLIST" --check-commit-ready ) > "$TMP/log" 2>&1
rc=$?
if [ "$rc" = "0" ]; then
  pass "T2: Phase 4 check-commit-ready passes with 0/6 steps complete"
else
  fail_ "T2" "rc=$rc (expected 0; iterative Phase 4 commits should not be blocked). Log: $(tail -3 "$TMP/log" | tr '\n' '|')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== --finalize-phase enforces strict closeout ==="
# ════════════════════════════════════════════════════════════════════

# T3: Phase 3 finalize fails when steps are missing.
setup_phase 3
( cd "$TMP" && bash "$CHECKLIST" --finalize-phase 3 ) > "$TMP/log" 2>&1
rc=$?
if [ "$rc" != "0" ] && grep -qE "step '[a-z_]+' not completed" "$TMP/log"; then
  pass "T3: --finalize-phase 3 refuses with steps missing; enumerates missing steps"
else
  fail_ "T3" "rc=$rc; expected non-zero + per-step diagnostics"
fi
teardown

# T4: Phase 4 finalize fails when steps are missing.
setup_phase 4
( cd "$TMP" && bash "$CHECKLIST" --finalize-phase 4 ) > "$TMP/log" 2>&1
rc=$?
if [ "$rc" != "0" ] && grep -qE "step '[a-z_]+' not completed" "$TMP/log"; then
  pass "T4: --finalize-phase 4 refuses with steps missing"
else
  fail_ "T4" "rc=$rc; expected non-zero"
fi
teardown

# T5: --finalize-phase rejects mismatched current-phase (e.g., asking to
# finalize Phase 4 when current_phase=3).
setup_phase 3
( cd "$TMP" && bash "$CHECKLIST" --finalize-phase 4 ) > "$TMP/log" 2>&1
rc=$?
if [ "$rc" != "0" ] && grep -qE "current phase is 3" "$TMP/log"; then
  pass "T5: --finalize-phase 4 refused when current_phase=3 (mismatch caught)"
else
  fail_ "T5" "rc=$rc; expected mismatch refusal"
fi
teardown

# T6: --finalize-phase 3 passes when all 9 Phase 3 steps are marked.
setup_phase 3
cat > "$TMP/.claude/process-state.json" <<'JSON'
{
  "phase1_pre_construction": {"steps_completed": [], "started_at": "2026-01-01T00:00:00Z"},
  "phase3_validation":       {"steps_completed": ["integration_testing","security_hardening","chaos_testing","accessibility_audit","performance_audit","contract_testing","results_archived","pre_launch_preparation","legal_review"], "started_at": "2026-01-01T00:00:00Z"},
  "phase4_release":          {"steps_completed": [], "started_at": "2026-01-01T00:00:00Z"}
}
JSON
( cd "$TMP" && bash "$CHECKLIST" --finalize-phase 3 ) > "$TMP/log" 2>&1
rc=$?
if [ "$rc" = "0" ] && grep -qE "Safe to tag/release" "$TMP/log"; then
  pass "T6: --finalize-phase 3 passes with all 9 steps complete"
else
  fail_ "T6" "rc=$rc. Log: $(tail -5 "$TMP/log" | tr '\n' '|')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-bl105-phase4-wave.sh — BL-105: Phase 4 gets a real gate.
#
# WHY THIS EXISTS (BL-105, walk-confirmed "worse than filed")
#   From a zero state, `--start-phase4` consulted ONLY poc_mode and advanced
#   past a FAILING 3→4 gate; `git tag` then cut a release — nothing satisfied,
#   nothing consulted. check-phase-gate.sh carried ZERO phase4_release
#   cross-references. The per-step artifact arms were shallow: an EMPTY file
#   named *rollback* passed the "MANDATORY rollback test" (CM-H-15); the
#   single word "monitoring" in HANDOFF.md passed monitoring verification
#   (CM-H-17); go_live_verified passed on RELEASE_NOTES.md existence alone.
#   The approval-log templates lacked the UAT sign-off section (both) and the
#   personal template lacked the pen-test + attorney sections the track-keyed
#   gates demand. The builders-guide artifact map mis-mapped Appendices A/B/C
#   to manifesto Sections 7/6/8 (really Post-MVP/Will-Not-Have/Open
#   Questions), and the guide omitted handoff_tested (D-6) from the Phase-4
#   step list. (docs/eval-results/ was already fixed by BL-103.)
#
# REGISTRATION: no init.sh → BOTH lists. Hermetic. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CPG="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_p4_proj <dir> [steps_json] — a phase-3/4 project with the checklist
# scripts local (start-phase4 consults the SIBLING gate).
mk_p4_proj() {
  local d="$1" steps="${2:-[]}"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/docs/test-results" "$d/docs/phase-0"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  printf '{"host":"github","mode":"personal"}\n' > "$d/.claude/manifest.json"
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":3,"track":"full","deployment":"personal","poc_mode":null,"gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-03-01","phase_2_to_3":"2026-04-01","phase_3_to_4":null}}
JSON
  jq -n --argjson s "$steps" '{phase1_artifacts:{data_classification:"public"},phase2_init:{steps_completed:["remote_repo_created","pushed_initial"],attestations:{branch_protection:{reason:"github_free_tier"}}},phase4_release:{steps_completed:$s,started_at:"2026-07-17T00:00:00Z"},uat_session:{},phase3_validation:{steps_completed:[]}}' > "$d/.claude/process-state.json"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/check-phase-gate.sh"  "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh" "$d/scripts/check-phase-gate.sh"
  printf 'frd\n' > "$d/docs/phase-0/frd.md"
  printf 'journey\n' > "$d/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$d/docs/phase-0/data-contract.md"
  # A dated approval log through 2→3: without it the gate exits at the
  # APPROVAL_LOG existence check before ever reaching the Phase-4 arm. The
  # 3→4 gate still FAILs on this fixture (empty phase3_validation, no review
  # manifest), which is what T-start-phase4-consults needs.
  cat > "$d/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-03-01 |

## Phase Gate: Phase 2 → Phase 3
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-04-01 |
MD
  { local n; for n in 1 2 3 4 5 6 7 8; do echo "## ${n}. S${n}"; echo "Content."; echo ""; done; } > "$d/PRODUCT_MANIFESTO.md"
}

# ── T-start-phase4-consults ──────────────────────────────────────────────────
echo "=== T-start-phase4-consults ==="
P="$TOPTMP/p-sp4"
mk_p4_proj "$P"
out=$( cd "$P" && bash scripts/process-checklist.sh --start-phase4 2>&1 ); rc=$?
phase_after=$(jq -r '.current_phase' "$P/.claude/phase-state.json")
if [ "$rc" -ne 0 ] && [ "$phase_after" = "3" ]; then
  pass "T-start-phase4-consults"
else
  fail_ "T-start-phase4-consults" "--start-phase4 advanced past a FAILING 3→4 gate (rc=$rc, current_phase=$phase_after) — the walk cut a release this way with nothing satisfied"
fi

# ── T-phase4-presence-gate ───────────────────────────────────────────────────
echo "=== T-phase4-presence-gate ==="
P="$TOPTMP/p-pres"
mk_p4_proj "$P"
jq '.current_phase = 4' "$P/.claude/phase-state.json" > "$P/.claude/t" && mv "$P/.claude/t" "$P/.claude/phase-state.json"
jq '.phase4_release = {steps_completed: [], started_at: null}' "$P/.claude/process-state.json" > "$P/.claude/t" && mv "$P/.claude/t" "$P/.claude/process-state.json"
out=$( cd "$P" && bash "$CPG" 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "BL-105"; then
  pass "T-phase4-presence-gate"
else
  fail_ "T-phase4-presence-gate" "current_phase=4 with NO phase4_release checklist state produced no BL-105 diagnostic (rc=$rc) — Phase 4 remains terminal and unforced"
fi

# ── T-no-circular-consult ────────────────────────────────────────────────────
# The presence arm must key on the FILE's real phase, not the --gate-elevated
# variable: `--gate phase_3_to_4` elevates current_phase to 4, so an
# elevated-keyed arm demands a STARTED phase-4 checklist DURING the 3→4
# prospective check — making --start-phase4's own consult SELF-BLOCKING even
# when everything else passes (circular deadlock).
echo "=== T-no-circular-consult ==="
P="$TOPTMP/p-circ"
mk_p4_proj "$P"
jq '.phase4_release = {steps_completed: [], started_at: null}' "$P/.claude/process-state.json" > "$P/.claude/t" && mv "$P/.claude/t" "$P/.claude/process-state.json"
out=$( cd "$P" && bash "$CPG" --gate phase_3_to_4 2>&1 ); rc=$?
if printf '%s' "$out" | grep -q "NEVER STARTED"; then
  fail_ "T-no-circular-consult" "--gate phase_3_to_4 on a real-phase-3 project demands an already-started Phase-4 checklist — the arm keys on the ELEVATED phase and start-phase4's own consult is self-blocking (circular)"
else
  pass "T-no-circular-consult"
fi

# ── T-rollback-empty-file-rejected ───────────────────────────────────────────
echo "=== T-rollback-empty-file-rejected ==="
P="$TOPTMP/p-rb"
mk_p4_proj "$P" '["production_build"]'
: > "$P/docs/test-results/2026-07-17_rollback-test.md"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase4_release:rollback_tested 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-rollback-empty-file-rejected"
else
  fail_ "T-rollback-empty-file-rejected" "an EMPTY file named rollback passed the MANDATORY rollback test (CM-H-15)"
fi

# ── T-rollback-real-passes ───────────────────────────────────────────────────
echo "=== T-rollback-real-passes ==="
P="$TOPTMP/p-rb2"
mk_p4_proj "$P" '["production_build"]'
cat > "$P/docs/test-results/2026-07-17_rollback-test.md" <<'MD'
# Rollback test — 2026-07-17
Deployed v1.0.1, rolled back to v1.0.0 via the release pipeline.
Outcome: verified — previous version restored and serving in 4m12s.
MD
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase4_release:rollback_tested 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-rollback-real-passes"
else
  fail_ "T-rollback-real-passes" "a real dated rollback record with an outcome was rejected (rc=$rc): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T-monitoring-word-rejected ───────────────────────────────────────────────
echo "=== T-monitoring-word-rejected ==="
P="$TOPTMP/p-mon"
mk_p4_proj "$P" '["production_build","rollback_tested","go_live_verified"]'
printf 'monitoring\n' > "$P/HANDOFF.md"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase4_release:monitoring_configured 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-monitoring-word-rejected"
else
  fail_ "T-monitoring-word-rejected" "the single word 'monitoring' passed monitoring verification (CM-H-17) — 'Configured' is not 'verified'"
fi

# ── T-monitoring-verified-passes ─────────────────────────────────────────────
echo "=== T-monitoring-verified-passes ==="
P="$TOPTMP/p-mon2"
mk_p4_proj "$P" '["production_build","rollback_tested","go_live_verified"]'
cat > "$P/HANDOFF.md" <<'MD'
# Handoff
## 8. Monitoring
Tool: Sentry (dashboard: https://sentry.example/app). Alerts to #ops.
Verification: test error triggered 2026-07-16, alert received in channel.
MD
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase4_release:monitoring_configured 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-monitoring-verified-passes"
else
  fail_ "T-monitoring-verified-passes" "a documented tool + triggered-test-alert record was rejected (rc=$rc): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T-golive-notes-substantive ───────────────────────────────────────────────
echo "=== T-golive-notes-substantive ==="
P="$TOPTMP/p-gl"
mk_p4_proj "$P" '["production_build","rollback_tested"]'
: > "$P/RELEASE_NOTES.md"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase4_release:go_live_verified 2>&1 ); rc=$?
P2="$TOPTMP/p-gl2"
mk_p4_proj "$P2" '["production_build","rollback_tested"]'
cat > "$P2/RELEASE_NOTES.md" <<'MD'
# Release v1.0.0 — 2026-07-17
Initial production release. Go-live smoke test: app served / on the production URL.
MD
out2=$( cd "$P2" && bash scripts/process-checklist.sh --complete-step phase4_release:go_live_verified 2>&1 ); rc2=$?
if [ "$rc" -ne 0 ] && [ "$rc2" -eq 0 ]; then
  pass "T-golive-notes-substantive"
else
  fail_ "T-golive-notes-substantive" "empty RELEASE_NOTES rc=$rc (want !=0); substantive rc=$rc2 (want 0) — existence alone must not verify go-live"
fi

# ── T-approval-templates-sections ────────────────────────────────────────────
echo "=== T-approval-templates-sections ==="
ORG="$REPO_ROOT/templates/generated/approval-log-org.tmpl"
PER="$REPO_ROOT/templates/generated/approval-log-personal.tmpl"
missing=""
grep -q "UAT Sign-off" "$ORG" || missing="$missing org:UAT"
grep -q "UAT Sign-off" "$PER" || missing="$missing personal:UAT"
grep -qi "Attorney / Legal Review" "$PER" || missing="$missing personal:attorney"
grep -qi "Penetration Test" "$PER" || missing="$missing personal:pen-test"
if [ -z "$missing" ]; then
  pass "T-approval-templates-sections"
else
  fail_ "T-approval-templates-sections" "approval-log templates missing sections the track-keyed gates demand:$missing (BL-088 class: the template is chosen by deployment while the gates key on track)"
fi

# ── T-artifact-map-fixed ─────────────────────────────────────────────────────
echo "=== T-artifact-map-fixed ==="
if grep -q "| Section 7 (Revenue Model) |" "$REPO_ROOT/docs/builders-guide.md"; then
  fail_ "T-artifact-map-fixed" "the Phase-0 Artifact Map still maps Appendix A to 'Section 7' (really Will-Not-Have) — the mis-map stands"
elif ! grep -q "handoff_tested" "$REPO_ROOT/docs/builders-guide.md"; then
  fail_ "T-artifact-map-fixed" "builders-guide still omits handoff_tested (D-6) — a guide-following operator is blocked by an undocumented 6th step"
else
  pass "T-artifact-map-fixed"
fi

# ── T-competency-warn-wired ──────────────────────────────────────────────────
echo "=== T-competency-warn-wired ==="
P="$TOPTMP/p-comp"
mk_p4_proj "$P"
jq '.current_phase = 1' "$P/.claude/phase-state.json" > "$P/.claude/t" && mv "$P/.claude/t" "$P/.claude/phase-state.json"
{ for n in 1 2 3 4 5 6 7 8; do echo "## ${n}. S${n}"; echo "Content."; echo ""; done; } > "$P/PRODUCT_MANIFESTO.md"
cat > "$P/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |
MD
out=$( cd "$P" && bash "$CPG" --gate phase_0_to_1 2>&1 ); rc=$?
if printf '%s' "$out" | grep -qi "competency"; then
  if [ "$rc" -eq 0 ]; then
    pass "T-competency-warn-wired (WARN-first: mentioned, not blocking)"
  else
    fail_ "T-competency-warn-wired" "competency line present but the clean fixture BLOCKS (rc=$rc) — the wiring must be WARN-first (no issues increment)"
  fi
else
  fail_ "T-competency-warn-wired" "no competency line in the 0→1 gate output — the 'not advisory' Competency Matrix is still invoked by nothing"
fi

# ── T-mutation-bl105 ─────────────────────────────────────────────────────────
echo "=== T-mutation-bl105 ==="
MUT="$TOPTMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
if ! grep -q "BL-105-START4-GATE-CONSULT-BEGIN" "$REPO_ROOT/scripts/process-checklist.sh" \
   || ! grep -q "BL-105-PHASE4-GATE-BEGIN" "$CPG"; then
  fail_ "T-mutation-bl105" "marker fences absent — fix not in place"
else
  sed '/# BL-105-START4-GATE-CONSULT-BEGIN/,/# BL-105-START4-GATE-CONSULT-END/d' "$REPO_ROOT/scripts/process-checklist.sh" > "$MUT/scripts/process-checklist.sh"
  sed '/# BL-105-PHASE4-GATE-BEGIN/,/# BL-105-PHASE4-GATE-END/d' "$CPG" > "$MUT/scripts/check-phase-gate.sh"
  chmod +x "$MUT/scripts/process-checklist.sh" "$MUT/scripts/check-phase-gate.sh"
  if ! bash -n "$MUT/scripts/process-checklist.sh" 2>/dev/null || ! bash -n "$MUT/scripts/check-phase-gate.sh" 2>/dev/null; then
    fail_ "T-mutation-bl105" "an excised mutant is syntactically broken — keep both arms excision-safe"
  else
    P="$TOPTMP/p-mut"
    mk_p4_proj "$P"
    cp "$MUT/scripts/process-checklist.sh" "$P/scripts/process-checklist.sh"
    out=$( cd "$P" && bash scripts/process-checklist.sh --start-phase4 2>&1 ) || true
    mut_phase=$(jq -r '.current_phase' "$P/.claude/phase-state.json")
    P2="$TOPTMP/p-mut2"
    mk_p4_proj "$P2"
    jq '.current_phase = 4' "$P2/.claude/phase-state.json" > "$P2/.claude/t" && mv "$P2/.claude/t" "$P2/.claude/phase-state.json"
    jq '.phase4_release = {steps_completed: [], started_at: null}' "$P2/.claude/process-state.json" > "$P2/.claude/t" && mv "$P2/.claude/t" "$P2/.claude/process-state.json"
    out2=$( cd "$P2" && bash "$MUT/scripts/check-phase-gate.sh" 2>&1 ) || true
    if [ "$mut_phase" = "4" ] && ! printf '%s' "$out2" | grep -q "BL-105"; then
      pass "T-mutation-bl105 (both fences load-bearing: excised consult advances blind; excised arm goes silent)"
    else
      fail_ "T-mutation-bl105" "mutants did not regress (phase=$mut_phase, arm-diag=$(printf '%s' "$out2" | grep -c BL-105)) — a fence does not contain its check"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

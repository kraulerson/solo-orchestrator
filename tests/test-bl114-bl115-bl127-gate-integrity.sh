#!/usr/bin/env bash
# tests/test-bl114-bl115-bl127-gate-integrity.sh — the E1a gate-integrity trio:
# BL-114 (0→1 gate), BL-115 (approval evidence), BL-127 (UAT evidence).
#
# WHY THIS EXISTS (E2E walk F1/F2/F3/F6/F16 + Dogfood-2 F-DF2-003/F-DF2-010)
#   BL-114: a placeholder-only manifesto section tripped `set -euo pipefail`
#   INSIDE validate_manifesto_content (the empty `grep -v` pipeline exits 1
#   under pipefail) and aborted the gate BEFORE its own WARN printed — rc=1
#   with zero diagnostic; the "blocking" phase-0-intermediates check never
#   incremented `issues` (and an absent docs/phase-0/ produced no warning at
#   all); and `--start-phase1` advanced 0→1 with NO gate consult while being
#   absent from --help.
#   BL-115: _cpg_gate_has_evidence accepted ANY ISO date in a 15-line window
#   after a gate header — a blank Date cell was masked by an incidental date
#   in a Notes row; the attorney gate was satisfied by the APPROVAL_LOG
#   template's own "## Attorney / Legal Review" header; and deleting
#   PRIVACY_POLICY.md bypassed legal_review entirely (skipped-when-absent,
#   even for PII projects).
#   BL-127: every uat_session step was pure self-attestation —
#   results_received passed with ZERO files in submissions/.
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

# ── Phase-0→1 fixture (gate scope phase_0_to_1) ─────────────────────────────
# kind: clean | placeholder-section | missing-intermediate | no-p0-dir |
#       blank-date-stray-date
build_p01() {
  local d="$1" kind="$2"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/docs/phase-0"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  printf '{"host":"github","mode":"personal"}\n' > "$d/.claude/manifest.json"
  cat > "$d/.claude/phase-state.json" <<'JSON'
{
  "project": "e1a",
  "current_phase": 0,
  "track": "light",
  "deployment": "personal",
  "gates": { "phase_0_to_1": null, "phase_1_to_2": null, "phase_2_to_3": null, "phase_3_to_4": null }
}
JSON
  jq -n '{phase1_artifacts:{},phase2_init:{steps_completed:[]}}' > "$d/.claude/process-state.json"
  local date_cell="2026-02-01"
  [ "$kind" = "blank-date-stray-date" ] && date_cell=""
  cat > "$d/APPROVAL_LOG.md" <<MD
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | $date_cell |
| Notes | drafted 2026-01-15 in planning review |
MD
  {
    local n
    for n in 1 2 3 4 5 6 7 8; do
      echo "## ${n}. Section ${n}"
      if [ "$kind" = "placeholder-section" ] && [ "$n" = "5" ]; then
        echo "[Fill this in later]"
      else
        echo "Substantive content for section ${n}."
      fi
      echo ""
    done
  } > "$d/PRODUCT_MANIFESTO.md"
  printf 'frd\n' > "$d/docs/phase-0/frd.md"
  printf 'journey\n' > "$d/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$d/docs/phase-0/data-contract.md"
  case "$kind" in
    missing-intermediate) rm -f "$d/docs/phase-0/frd.md" ;;
    no-p0-dir)            rm -rf "$d/docs/phase-0" ;;
  esac
}

run_p01() { ( cd "$1" && bash "$CPG" --gate phase_0_to_1 2>&1 ); }

# ── BL-114 F2: placeholder WARN must PRINT (no silent errexit abort) ─────────
echo "=== T-placeholder-warn-prints ==="
P="$TOPTMP/p-ph"
build_p01 "$P" placeholder-section
out=$(run_p01 "$P"); rc=$?
if printf '%s' "$out" | grep -q "placeholder content"; then
  pass "T-placeholder-warn-prints (rc=$rc with the diagnostic present)"
else
  fail_ "T-placeholder-warn-prints" "the placeholder diagnostic never printed (rc=$rc) — errexit killed validate_manifesto_content before its own WARN (walk F2): last lines: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── BL-114 F1: intermediates check BLOCKS (and absent dir is not silent) ─────
echo "=== T-intermediates-block ==="
P="$TOPTMP/p-int"
build_p01 "$P" missing-intermediate
out=$(run_p01 "$P"); rc=$?
P2="$TOPTMP/p-nodir"
build_p01 "$P2" no-p0-dir
out2=$(run_p01 "$P2"); rc2=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "intermediates" \
   && [ "$rc2" -ne 0 ] && printf '%s' "$out2" | grep -qi "intermediates"; then
  pass "T-intermediates-block"
else
  fail_ "T-intermediates-block" "missing frd.md: rc=$rc (want !=0, with an intermediates diagnostic); absent docs/phase-0: rc=$rc2 diag=$(printf '%s' "$out2" | grep -ci intermediates) — the documented WARNS-and-blocks behavior does not block (walk F1)"
fi

# ── BL-114 F1 control: a clean fixture still passes ──────────────────────────
echo "=== T-clean-p01-passes ==="
P="$TOPTMP/p-clean"
build_p01 "$P" clean
out=$(run_p01 "$P"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-clean-p01-passes"
else
  fail_ "T-clean-p01-passes" "clean 0→1 fixture blocked (rc=$rc): $(printf '%s' "$out" | grep -E '\[FAIL\]' | head -2 | tr '\n' ' ')"
fi

# ── BL-115 F6: a blank Date cell is not masked by a stray date ───────────────
echo "=== T-date-cell-required ==="
P="$TOPTMP/p-date"
build_p01 "$P" blank-date-stray-date
out=$(run_p01 "$P"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE "approval|evidence|date"; then
  pass "T-date-cell-required"
else
  fail_ "T-date-cell-required" "a BLANK approval Date cell passed the gate because a stray date sat in the Notes row within the 15-line window (rc=$rc, walk F6/P1-010)"
fi

# ── BL-115 verifier SF#1: a MISSING Date row must not steal the next section's ─
echo "=== T-date-no-row-not-stolen ==="
P="$TOPTMP/p-steal"
build_p01 "$P" clean
cat > "$P/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-05-05 |
MD
out=$(run_p01 "$P"); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-date-no-row-not-stolen"
else
  fail_ "T-date-no-row-not-stolen" "a 0→1 section with NO Date row passed by stealing the NEXT section's date through the 15-line window (verifier SF#1) — a missing row must be at least as strict as a blank one"
fi

# ── process-checklist fixtures (legal_review + UAT) ──────────────────────────
mk_pc_proj() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  printf '{"host":"github","mode":"personal","enforcement_level":"light"}\n' > "$d/.claude/manifest.json"
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":3,"track":"standard","deployment":"personal","poc_mode":null,"gates":{}}
JSON
  jq -n '{phase1_artifacts:{data_classification:"pii"},phase2_init:{steps_completed:["remote_repo_created","pushed_initial"],verified:true},build_loop:{feature:null,step:0,steps_completed:[]},uat_session:{session_id:"2026-07-17-session-1",step:3,steps_completed:["agents_dispatched","template_generated","orchestrator_notified"]},phase3_validation:{steps_completed:["integration_testing","security_hardening","chaos_testing","accessibility_audit","performance_audit","contract_testing","results_archived","pre_launch_preparation"]}}' > "$d/.claude/process-state.json"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh"
}

# ── BL-115 F16a: the template's own header must not satisfy the attorney gate ─
echo "=== T-attorney-header-not-enough ==="
P="$TOPTMP/p-att"
mk_pc_proj "$P"
printf 'policy\n' > "$P/PRIVACY_POLICY.md"
cat > "$P/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Attorney / Legal Review
| Field | Value |
|---|---|
| Reviewer | |
| Date | |
MD
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase3_validation:legal_review 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-attorney-header-not-enough"
else
  fail_ "T-attorney-header-not-enough" "legal_review completed with ONLY the template's own '## Attorney / Legal Review' header — the gate satisfies itself (walk F16)"
fi

# ── BL-115 F16b: a real dated attorney row DOES satisfy it ───────────────────
echo "=== T-attorney-real-entry-passes ==="
P="$TOPTMP/p-att2"
mk_pc_proj "$P"
printf 'policy\n' > "$P/PRIVACY_POLICY.md"
cat > "$P/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Attorney / Legal Review
| Field | Value |
|---|---|
| Reviewer | Dana Counsel, Esq. |
| Date | 2026-07-10 |
MD
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase3_validation:legal_review 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-attorney-real-entry-passes"
else
  fail_ "T-attorney-real-entry-passes" "a REAL dated attorney row was rejected (rc=$rc): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── BL-115 E1b Claim-C: a neighbouring section's date must not satisfy the ───
# attorney gate. The personal template's own `[Attorney / firm name]`
# placeholder is a SECOND grep anchor for `attorney`; its 15-line -A window
# reaches the Penetration Test section's Date row, so filling in the pen-test
# date (legitimate) while leaving the attorney Date a placeholder passed
# legal_review — a cross-section bleed, the same defect class verifier SF#1
# killed in _cpg_gate_has_evidence. The window must be SECTION-BOUNDED.
echo "=== T-attorney-bleed-blocked ==="
P="$TOPTMP/p-att3"
mk_pc_proj "$P"
printf 'policy\n' > "$P/PRIVACY_POLICY.md"
cat > "$P/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Attorney / Legal Review (if applicable)

| Field | Value |
|---|---|
| **Reviewer** | [Attorney / firm name] |
| **Date** | [YYYY-MM-DD] |
| **Scope** | [Privacy Policy / ToS / other] |

---

## Penetration Test (if applicable)

| Field | Value |
|---|---|
| **Tester** | Redwood Security LLC |
| **Date** | 2026-07-12 |
| **Report** | docs/test-results/2026-07-12_pen-test.md |
MD
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase3_validation:legal_review 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-attorney-bleed-blocked"
else
  fail_ "T-attorney-bleed-blocked" "legal_review completed with a PLACEHOLDER attorney Date — the pen-test section's date bled through the unbounded 15-line window (E1b Claim-C)"
fi

# ── BL-115 F16c: PII with NO privacy policy must FAIL, not skip ──────────────
echo "=== T-legal-required-when-pii ==="
P="$TOPTMP/p-pii"
mk_pc_proj "$P"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase3_validation:legal_review 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE "pii|classification|privacy"; then
  pass "T-legal-required-when-pii"
else
  fail_ "T-legal-required-when-pii" "data_classification=pii with NO privacy policy completed legal_review (rc=$rc) — collect PII, write no policy, pass (walk F16)"
fi

# ── BL-127: results_received demands evidence ────────────────────────────────
echo "=== T-uat-results-need-evidence ==="
P="$TOPTMP/p-uat"
mk_pc_proj "$P"
mkdir -p "$P/tests/uat/sessions/2026-07-17-session-1/submissions"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step uat_session:results_received 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "submission"; then
  pass "T-uat-results-need-evidence"
else
  fail_ "T-uat-results-need-evidence" "results_received completed with ZERO files in submissions/ (rc=$rc) — the step whose entire meaning is 'the results are in' demands none (F-DF2-010)"
fi

# ── BL-127: with a real submission it passes ─────────────────────────────────
echo "=== T-uat-results-with-evidence ==="
P="$TOPTMP/p-uat2"
mk_pc_proj "$P"
mkdir -p "$P/tests/uat/sessions/2026-07-17-session-1/submissions"
printf 'tester-1 results\n' > "$P/tests/uat/sessions/2026-07-17-session-1/submissions/tester-1.md"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step uat_session:results_received 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-uat-results-with-evidence"
else
  fail_ "T-uat-results-with-evidence" "results_received rejected a session WITH a submission file (rc=$rc): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── BL-127: the explicit solo-mode attestation works AND is recorded ─────────
echo "=== T-uat-solo-attested ==="
P="$TOPTMP/p-uat3"
mk_pc_proj "$P"
mkdir -p "$P/tests/uat/sessions/2026-07-17-session-1/submissions"
out=$( cd "$P" && SOLO_UAT_SOLO_ATTESTED=1 SOLO_UAT_REASON="solo operator, no external testers" bash scripts/process-checklist.sh --complete-step uat_session:results_received 2>&1 ); rc=$?
recorded=$(jq -r '.uat_session.solo_attestations[0].reason // ""' "$P/.claude/process-state.json" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ -n "$recorded" ]; then
  pass "T-uat-solo-attested (recorded: $recorded)"
else
  fail_ "T-uat-solo-attested" "solo-mode attestation rc=$rc recorded='$recorded' — the escape must work AND be durably recorded (attested, not silenced)"
fi

# ── BL-127 verifier SF#2: .gitkeep is not evidence ───────────────────────────
echo "=== T-uat-gitkeep-not-evidence ==="
P="$TOPTMP/p-uatgk"
mk_pc_proj "$P"
mkdir -p "$P/tests/uat/sessions/2026-07-17-session-1/submissions"
touch "$P/tests/uat/sessions/2026-07-17-session-1/submissions/.gitkeep"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step uat_session:results_received 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-uat-gitkeep-not-evidence"
else
  fail_ "T-uat-gitkeep-not-evidence" "a lone .gitkeep counted as a submission (verifier SF#2 — the keep-empty-dir convention launders the evidence gate)"
fi

# ── BL-127 verifier SF#3: evidence resolves from session_id, not dir mtime ───
echo "=== T-uat-session-id-resolved ==="
P="$TOPTMP/p-uatsid"
mk_pc_proj "$P"
mkdir -p "$P/tests/uat/sessions/2026-07-17-session-1/submissions"
mkdir -p "$P/tests/uat/sessions/2026-07-01-session-0/submissions"
printf 'stale results\n' > "$P/tests/uat/sessions/2026-07-01-session-0/submissions/old.md"
touch "$P/tests/uat/sessions/2026-07-01-session-0"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step uat_session:results_received 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-uat-session-id-resolved (the CURRENT session's empty submissions/ decide, not a stale dir's mtime)"
else
  fail_ "T-uat-session-id-resolved" "results_received passed on a STALE session's files while the state's session_id (2026-07-17-session-1) has none (verifier SF#3)"
fi

# ── BL-127 verifier SF#4: the solo escape warns outside the Light track ──────
echo "=== T-uat-solo-warn-outside-light ==="
P="$TOPTMP/p-uatorg"
mk_pc_proj "$P"
mkdir -p "$P/tests/uat/sessions/2026-07-17-session-1/submissions"
out=$( cd "$P" && SOLO_UAT_SOLO_ATTESTED=1 bash scripts/process-checklist.sh --complete-step uat_session:results_received 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi "outside the Light track"; then
  pass "T-uat-solo-warn-outside-light"
else
  fail_ "T-uat-solo-warn-outside-light" "solo-mode on a standard-track project (rc=$rc) must still be allowed+recorded but WARN that it is outside the Light track (verifier SF#4): $(printf '%s' "$out" | tail -1)"
fi

# ── BL-114 F3: --start-phase1 consults the gate ──────────────────────────────
echo "=== T-start-phase1-consults ==="
P="$TOPTMP/p-sp1"
mk_pc_proj "$P"
# Make it a phase-0 project with a FAILING 0→1 gate (no manifesto at all).
jq '.current_phase = 0' "$P/.claude/phase-state.json" > "$P/.claude/ps.tmp" && mv "$P/.claude/ps.tmp" "$P/.claude/phase-state.json"
cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$P/scripts/"
chmod +x "$P/scripts/check-phase-gate.sh"
out=$( cd "$P" && bash scripts/process-checklist.sh --start-phase1 2>&1 ); rc=$?
phase_after=$(jq -r '.current_phase' "$P/.claude/phase-state.json")
if [ "$rc" -ne 0 ] && [ "$phase_after" = "0" ]; then
  pass "T-start-phase1-consults"
else
  fail_ "T-start-phase1-consults" "--start-phase1 advanced past a FAILING 0→1 gate (rc=$rc, current_phase=$phase_after) — no gate consult (F-DF2-003)"
fi

# ── BL-114 F3: --start-phase1 is documented in --help ────────────────────────
echo "=== T-start-phase1-in-help ==="
if ( cd "$TOPTMP" && bash "$REPO_ROOT/scripts/process-checklist.sh" --help 2>&1 || true ) | grep -q "start-phase1"; then
  pass "T-start-phase1-in-help"
else
  fail_ "T-start-phase1-in-help" "--start-phase1 absent from --help — operators following the generated docs never discover it (F-DF2-003)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

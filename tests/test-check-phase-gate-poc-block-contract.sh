#!/usr/bin/env bash
# tests/test-check-phase-gate-poc-block-contract.sh
#
# BL-063: tighten the Phase-3→4 POC-block enforcement-point contracts from
# "the documented POC-block message is PRESENT" to "the POC block fires for
# the right reason, ALONE".
#
# THE DEFECT (from the 2026-06-29 adversarial certainty re-walk, S-6):
#   The scenarios `edge-phase-3-to-4-poc-blocked-check-phase-gate` and
#   `…-process-checklist` asserted only that the POC-block string appeared
#   somewhere in the output. In one recorded run the gate emitted 15
#   inconsistencies and the POC line was merely one of them — so a future
#   regression that adds an UNRELATED failure at the same enforcement point
#   would slip through unnoticed (the POC line is still present, the loose
#   assertion still fires). This file replaces "message-present" with a
#   count-based "the POC block is the only sanctioned failure line" contract.
#
# TWO ENFORCEMENT POINTS, TWO MARKERS, TWO CASES (verified 2026-07-09):
#   • scripts/check-phase-gate.sh (:1381) emits a GitHub annotation
#       ::error::Phase 4 (production release) is BLOCKED — …   (uppercase BLOCKED)
#     It does NOT short-circuit — the gate keeps evaluating every other
#     section — so a co-firing `[FAIL]`/`::error::` is buildable and the
#     tightened contract is a count: exactly one sanctioned `::error::`
#     (the POC line) and ZERO other `::error::`/`[FAIL]` lines.
#   • scripts/process-checklist.sh::start_phase4() (:578) emits
#       [FAIL] Phase 4 (production release) is blocked — …    (lowercase blocked)
#     via print_fail, then `exit 1` IMMEDIATELY (:581). A co-firing count is
#     unbuildable there, so the tightened contract is the short-circuit
#     itself: rc=1, exactly ONE `[FAIL]`, and no later-step output.
#   The two sites differ in BOTH marker (::error:: vs [FAIL]) and case
#   (BLOCKED vs blocked); the per-site assertions below are case-sensitive
#   and site-specific — one shared pattern cannot serve both.
#
# BL-082-PROOFING (parallel PR WP-A / BL-082 adds tree-hash staleness to the
#   Phase-3 validation-summary trust path): that logic lives ENTIRELY inside
#   the `current_phase >= 4` BL-070 block (check-phase-gate.sh:1300) and the
#   summary-discovery it guards. This fixture is pinned at EXACTLY phase 3 —
#   which is all the POC block needs (`current_phase >= 3`, :1373) — so the
#   phase-4 BL-070/summary/staleness machinery never runs and BL-082 cannot
#   perturb this fixture. No git repo, no summary file, no tree hash is
#   required. That is the deliberate BL-082-proofing.
#
# NO ALLOWLIST NEEDED: the fixture is constructed so every OTHER gate section
#   genuinely passes (see build_poc_fixture below) — there is no legitimately
#   co-firing failure line, so the "unexpected failure" allowlist is empty.
#   Each artifact/state below exists specifically to keep a gate section on
#   its [OK]/[INFO]/[WARN] path and off its [FAIL] path. ([WARN] lines are
#   expected and legitimate for a POC that stops at Phase 3 — they are NOT
#   failures and are intentionally excluded from the contract count.)
#
# Hermetic: mktemp fixtures only; no git init, no remotes, no gh/glab/curl.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/check-phase-gate.sh"
CHECKLIST="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

PROJ=""

# ── Fixture: a Phase-3 POC project where every gate section OTHER than the
# POC block genuinely passes. Each line is load-bearing for exactly that:
#   • current_phase=3            → POC block fires (>=3); phase-4 BL-070 block
#                                  (>=4) and its summary/BL-082 path stay off.
#   • deployment=personal        → all organizational-only [FAIL] paths
#                                  (self-approval, dual-approval, pre-cond) skip.
#   • track=light                → Full-track pen-test [FAIL] + enforced
#                                  review-gate [FAIL] both skip (WARN at most).
#   • gates{} dates + APPROVAL_LOG dated headers → gate-date checks take the
#                                  idempotent [INFO] path, not a WARN/FAIL.
#   • process-state data_classification=public → Phase 1→2 ZDR gate is [OK]
#                                  (public data needs no ZDR attestation).
#   • NO .claude/manifest.json   → Phase 1→2 protection backstop + BL-084 push
#                                  gate both skip (they require a manifest);
#                                  this is what keeps sponsored_poc clean too.
#   • PROJECT_BIBLE.md present    → avoids the "PROJECT_BIBLE.md not found" FAIL.
#   • docs/test-results/ non-empty→ avoids the empty/missing-dir FAIL.
#   • BUGS.md (no open bugs) + FEATURES.md → the Phase-3 bug gate resolves to
#                                  "clear" with no open SEV-1/2, so its
#                                  print_fail lines never fire.
# $1 = poc_mode (private_poc | sponsored_poc)
build_poc_fixture() {
  local mode="$1"
  PROJ=$(mktemp -d)
  mkdir -p "$PROJ/.claude" "$PROJ/docs/test-results"

  cat > "$PROJ/.claude/phase-state.json" <<JSON
{"current_phase":3,"deployment":"personal","track":"light","poc_mode":"$mode","gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-03-01","phase_2_to_3":"2026-04-01"}}
JSON

  cat > "$PROJ/.claude/process-state.json" <<'JSON'
{"phase1_artifacts":{"data_classification":"public"}}
JSON

  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase Gate: Phase 0 → Phase 1
Approved 2026-02-01 by Alice Approver

## Phase Gate: Phase 1 → Phase 2
Approved 2026-03-01 by Alice Approver

## Phase Gate: Phase 2 → Phase 3
Approved 2026-04-01 by Alice Approver
MD

  # PROJECT_BIBLE.md with 16 numbered sections and no YYYY-MM-DD placeholders
  # (keeps the Phase 1→2 Bible check on its [OK] path with no WARN).
  {
    echo "# PROJECT_BIBLE"
    echo ""
    local i=1
    while [ "$i" -le 16 ]; do
      echo "## ${i}. Section ${i}"
      echo "Content for section ${i}."
      echo ""
      i=$((i + 1))
    done
  } > "$PROJ/PROJECT_BIBLE.md"

  cat > "$PROJ/FEATURES.md" <<'MD'
# FEATURES

## Feature One
Implemented.
MD

  echo "# CHANGELOG" > "$PROJ/CHANGELOG.md"

  # BUGS.md with a header and zero open SEV rows → bug gate has a tracking
  # source (deterministic, independent of ambient gh auth) and finds nothing
  # blocking.
  cat > "$PROJ/BUGS.md" <<'MD'
# BUGS

| # | Severity | Status | Feature | Description |
|---|----------|--------|---------|-------------|
MD

  echo "phase-3 scan result placeholder" > "$PROJ/docs/test-results/summary.txt"
}

teardown() {
  [ -n "${PROJ:-}" ] && rm -rf "$PROJ"
  PROJ=""
}

run_gate()      { ( cd "$PROJ" && bash "$GATE" 2>&1 ); }
run_checklist() { ( cd "$PROJ" && bash "$CHECKLIST" --start-phase4 </dev/null 2>&1 ); }

# ── The tightened BL-063 contract, as a reusable predicate ───────────────
# count_unexpected_failures <output>
#   Echoes the number of UNEXPECTED failure lines at the enforcement point:
#   every `::error::` beyond the single sanctioned POC-block line, plus every
#   `[FAIL]` line. A clean POC-blocked run yields 0; any co-firing regression
#   yields >=1. THIS is the load-bearing tightening — the old contract only
#   asked "is the POC message present?" and could not see co-firing failures.
#
#   The marked line below is the mutation target: neutering the subtraction of
#   the sanctioned POC line + the [FAIL] term (i.e. reverting to
#   message-present-only) makes this always return 0, which flips the
#   negative-control test (T3) RED. See the PR body for the captured RED→GREEN.
count_unexpected_failures() {
  local out="$1"
  local err_total fail_total poc_err
  err_total=$(printf '%s\n' "$out" | grep -c '::error::' || true)
  case "$err_total" in ''|*[!0-9]*) err_total=0 ;; esac
  fail_total=$(printf '%s\n' "$out" | grep -c '\[FAIL\]' || true)
  case "$fail_total" in ''|*[!0-9]*) fail_total=0 ;; esac
  # The sanctioned POC annotation is the ONLY ::error:: allowed here.
  poc_err=$(printf '%s\n' "$out" | grep -c '::error::.*is BLOCKED' || true)
  case "$poc_err" in ''|*[!0-9]*) poc_err=0 ;; esac
  echo $(( (err_total - poc_err) + fail_total ))   # BL-063-CONTRACT
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== BL-063: POC-block enforcement-point contracts ==="
echo "== tests/test-check-phase-gate-poc-block-contract.sh =="
# ════════════════════════════════════════════════════════════════════

# T1 / T2 — check-phase-gate.sh: the POC ::error:: fires AND nothing else does.
_t_gate_poc_alone() {
  local label="$1" mode="$2"
  build_poc_fixture "$mode"
  local out; out=$(run_gate)

  # (a) the sanctioned POC annotation is present (case-correct: BLOCKED).
  if ! printf '%s\n' "$out" | grep -q '::error::.*is BLOCKED'; then
    fail_ "$label" "expected the POC ::error::…BLOCKED annotation (poc_mode=$mode); got:\n$(printf '%s\n' "$out" | grep -E '::error::|\[FAIL\]')"
    teardown; return
  fi
  # (b) NOTHING else fails at this enforcement point.
  local unexpected; unexpected=$(count_unexpected_failures "$out")
  if [ "$unexpected" -ne 0 ]; then
    fail_ "$label" "expected 0 unexpected failure lines, got $unexpected (poc_mode=$mode):\n$(printf '%s\n' "$out" | grep -E '::error::|\[FAIL\]')"
    teardown; return
  fi
  pass "$label: check-phase-gate POC ::error:: fires ALONE (poc_mode=$mode, 0 co-firing FAIL/error)"
  teardown
}

_t_gate_poc_alone "T1" "private_poc"
_t_gate_poc_alone "T2" "sponsored_poc"

# T3 — Negative control: corrupt one UNRELATED required artifact (empty the
# docs/test-results/ dir → the gate emits its own `[FAIL] docs/test-results/
# is empty`). The OLD message-present contract would still pass (the POC line
# is still there); the tightened contract MUST catch the extra failure line.
# Structured as a positive test that the detection logic flags the corruption.
_t_gate_negative_control() {
  local label="T3"
  build_poc_fixture "private_poc"
  # Corruption unrelated to the POC block: drop the archived scan result.
  rm -f "$PROJ/docs/test-results/summary.txt"
  local out; out=$(run_gate)

  # The POC annotation is STILL present — proving the loose contract would
  # not notice anything wrong.
  if ! printf '%s\n' "$out" | grep -q '::error::.*is BLOCKED'; then
    fail_ "$label" "sanity: POC annotation should still be present in the corrupted run; got:\n$(printf '%s\n' "$out" | grep -E '::error::|\[FAIL\]')"
    teardown; return
  fi
  # The tightened contract catches the co-firing failure.
  local unexpected; unexpected=$(count_unexpected_failures "$out")
  if [ "$unexpected" -lt 1 ]; then
    fail_ "$label" "tightened contract FAILED to catch the co-firing failure (unexpected=$unexpected); this is the exact BL-063 gap:\n$(printf '%s\n' "$out" | grep -E '::error::|\[FAIL\]')"
    teardown; return
  fi
  # And the caught line is specifically the corruption we introduced.
  if ! printf '%s\n' "$out" | grep -q '\[FAIL\].*docs/test-results'; then
    fail_ "$label" "expected the docs/test-results FAIL as the co-firing line; got:\n$(printf '%s\n' "$out" | grep -E '::error::|\[FAIL\]')"
    teardown; return
  fi
  pass "$label: tightened count contract CATCHES an unrelated co-firing [FAIL] the message-present contract would miss (unexpected=$unexpected)"
  teardown
}

_t_gate_negative_control

# T4 / T5 — process-checklist.sh --start-phase4: the short-circuit contract.
# start_phase4() prints ONE [FAIL] (lowercase blocked) then exit 1 immediately,
# so no co-firing count is buildable. Assert the short-circuit instead:
# rc=1, exactly one [FAIL], and no later-step output ("Phase 4 release started"
# is the print_ok that runs ONLY past the block).
_t_checklist_shortcircuit() {
  local label="$1" mode="$2"
  build_poc_fixture "$mode"
  local out rc=0
  out=$(run_checklist) || rc=$?

  # rc=1
  if [ "$rc" -ne 1 ]; then
    fail_ "$label" "expected rc=1 from --start-phase4 (poc_mode=$mode), got rc=$rc:\n$out"
    teardown; return
  fi
  # exactly one [FAIL], case-correct (lowercase blocked).
  local fail_count; fail_count=$(printf '%s\n' "$out" | grep -c '\[FAIL\]' || true)
  if [ "$fail_count" -ne 1 ]; then
    fail_ "$label" "expected exactly one [FAIL], got $fail_count (poc_mode=$mode):\n$out"
    teardown; return
  fi
  if ! printf '%s\n' "$out" | grep -q '\[FAIL\].*is blocked'; then
    fail_ "$label" "the single [FAIL] should be the POC block (lowercase 'is blocked'); got:\n$out"
    teardown; return
  fi
  # no later-step output — the short-circuit ran before any Phase-4 work.
  if printf '%s\n' "$out" | grep -q 'Phase 4 release started'; then
    fail_ "$label" "later-step marker 'Phase 4 release started' present — start_phase4 did NOT short-circuit (poc_mode=$mode):\n$out"
    teardown; return
  fi
  # and current_phase was not advanced past 3 by a leaked write.
  local got; got=$(jq -r '.current_phase' "$PROJ/.claude/phase-state.json" 2>/dev/null || echo "?")
  if [ "$got" != "3" ]; then
    fail_ "$label" "current_phase advanced to '$got' despite the POC short-circuit (poc_mode=$mode)"
    teardown; return
  fi
  pass "$label: --start-phase4 short-circuits (rc=1, exactly one [FAIL], no later-step output, phase stays 3; poc_mode=$mode)"
  teardown
}

_t_checklist_shortcircuit "T4" "private_poc"
_t_checklist_shortcircuit "T5" "sponsored_poc"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

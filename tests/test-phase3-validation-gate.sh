#!/usr/bin/env bash
# tests/test-phase3-validation-gate.sh
#
# BL-070 regression: scripts/run-phase3-validation.sh (Phase 3 validation-scan
# driver) + the attest-on-skip Phase 3→4 gate in scripts/check-phase-gate.sh.
#
# The Builder's/User guides imply Phase 3 auto-runs Snyk / license / full-tree
# Semgrep / OWASP ZAP / threat-model; a grep of scripts/ found ZERO invocations
# — a documented gate mechanic that was not real. This suite pins the SKELETON
# (harness + gate + attest-on-skip), NOT all five real scanners.
#
# Contract pinned here:
#   T-driver-attest-recorded     driver --attest writes
#                                phase-state.json::phase3.attestations.<name>
#                                with a non-empty reason AND sign-off; exit 0.
#   T-driver-attest-needs-reason --attest without --reason → exit 2, nothing
#                                written.
#   T-driver-offline-cycle       --offline (all SKIP, un-attested) → exit 1;
#                                after attesting all 5 → exit 0.
#   T-gate-blocks-without-summary  current_phase=4 + NO summary (auto-run
#                                disabled) → gate emits the phase-3 FAIL and
#                                blocks (exit != 0).
#   T-gate-autoruns-driver       current_phase=4 + NO summary + auto-run
#                                enabled → gate auto-generates an offline
#                                summary and blocks on un-attested SKIPs.
#   T-gate-blocks-unattested-skip  summary with SKIPs but NO attestations →
#                                gate emits the "un-attested SKIP" FAIL.
#   T-gate-passes-attested-skip  summary with SKIPs + every skip attested
#                                (reason + signoff) → gate emits the phase-3
#                                [OK] line, NOT the FAIL.
#   T-mutation                   MUTATION-PROOF: strip the `# BL-070-GATE-CHECK`
#                                enforcement lines from a copy of the gate and
#                                re-run the unattested-skip fixture → the
#                                phase-3 FAIL message is gone (proving the
#                                enforcement is load-bearing: remove it → the
#                                blocking test goes RED).
#
# HERMETIC: scanners are never run for real — the driver is always invoked
# with --offline, so no network / Docker / semgrep / gh. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/check-phase-gate.sh"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — BL-070 attest-on-skip requires jq."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  printf '%s\n' '{"project":"p3","current_phase":4,"deployment":"personal","track":"light","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01","phase_2_to_3":"2026-03-01","phase_3_to_4":"2026-04-01"}}' \
    > "$PROJ/.claude/phase-state.json"
  # APPROVAL_LOG.md is required — the gate exits early without it. Provide
  # dated entries for every gate so the run reaches the Phase 3→4 checks.
  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Date** | 2026-01-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| **Date** | 2026-02-01 |

## Phase Gate: Phase 2 → Phase 3
| Field | Value |
|---|---|
| **Date** | 2026-03-01 |

## Phase Gate: Phase 3 → Phase 4
| Field | Value |
|---|---|
| **Date** | 2026-04-01 |
MD
}
teardown() { rm -rf "$TMP"; }

# Pre-create a summary whose five scanners are all SKIP (the driver's
# machine-readable RESULT contract). Only the RESULT lines are load-bearing
# for the gate parser.
write_summary_all_skip() {
  mkdir -p "$PROJ/docs/test-results/phase3"
  cat > "$PROJ/docs/test-results/phase3/summary-2026-07-06T00-00-00Z.md" <<'MD'
# Phase 3 Validation Summary
- Overall: FAIL

## Machine-readable results
```
RESULT semgrep-full-tree SKIP
RESULT license SKIP
RESULT snyk SKIP
RESULT zap-dast SKIP
RESULT threat-model SKIP
```
MD
}

attest_all() {
  local s
  for s in semgrep-full-tree license snyk zap-dast threat-model; do
    ( cd "$PROJ" && bash "$DRIVER" --attest "$s" --reason "test: tool not provisioned" --signoff "Tester" ) >/dev/null 2>&1
  done
}

# Run the gate in $PROJ. $1 (optional) = value for SOLO_PHASE3_GATE_NOAUTORUN
# ("1" disables the gate's driver auto-run; empty leaves it enabled).
run_gate() {
  ( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN="${1:-}" bash "$GATE" 2>&1 ) || true
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-driver-attest-recorded: --attest writes phase3.attestations ==="
# ════════════════════════════════════════════════════════════════════
setup
rc=0
( cd "$PROJ" && bash "$DRIVER" --attest snyk --reason "no snyk auth in this env" --signoff "Alice" ) >/dev/null 2>&1 || rc=$?
reason=$(jq -r '.phase3.attestations.snyk.reason // ""' "$PROJ/.claude/phase-state.json" 2>/dev/null)
signoff=$(jq -r '.phase3.attestations.snyk.signoff // ""' "$PROJ/.claude/phase-state.json" 2>/dev/null)
at=$(jq -r '.phase3.attestations.snyk.at // ""' "$PROJ/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$reason" = "no snyk auth in this env" ] && [ "$signoff" = "Alice" ] && [ -n "$at" ]; then
  pass "T-driver-attest-recorded: reason+signoff+at recorded (reason='$reason', signoff='$signoff')"
else
  fail_ "T-driver-attest-recorded" "rc=$rc reason='$reason' signoff='$signoff' at='$at'"
fi
# preserves pre-existing top-level keys
cp_phase=$(jq -r '.current_phase // ""' "$PROJ/.claude/phase-state.json" 2>/dev/null)
if [ "$cp_phase" = "4" ]; then
  pass "T-driver-attest-recorded: pre-existing phase-state keys preserved (current_phase=4)"
else
  fail_ "T-driver-attest-recorded" "attest clobbered current_phase (got '$cp_phase')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-driver-attest-needs-reason: --attest without --reason → exit 2 ==="
# ════════════════════════════════════════════════════════════════════
setup
rc=0
( cd "$PROJ" && bash "$DRIVER" --attest snyk ) >/dev/null 2>&1 || rc=$?
recorded=$(jq -r '.phase3.attestations.snyk // "none"' "$PROJ/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" -eq 2 ] && [ "$recorded" = "none" ]; then
  pass "T-driver-attest-needs-reason: exit 2, nothing recorded"
else
  fail_ "T-driver-attest-needs-reason" "expected exit 2 + no record; rc=$rc recorded='$recorded'"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-driver-offline-cycle: all-SKIP exit 1 → attest all → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
rc=0
( cd "$PROJ" && bash "$DRIVER" --offline ) >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
  pass "T-driver-offline-cycle: un-attested all-SKIP → exit 1 (gate would block)"
else
  fail_ "T-driver-offline-cycle" "expected exit 1 on un-attested skips, got $rc"
fi
if compgen -G "$PROJ/docs/test-results/phase3/summary-*.md" >/dev/null 2>&1; then
  pass "T-driver-offline-cycle: aggregate summary written"
else
  fail_ "T-driver-offline-cycle" "no summary-*.md produced"
fi
attest_all
rc=0
( cd "$PROJ" && bash "$DRIVER" --offline ) >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-driver-offline-cycle: after attesting all 5 skips → exit 0 (gate-ready)"
else
  fail_ "T-driver-offline-cycle" "expected exit 0 after attesting all skips, got $rc"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-gate-blocks-without-summary: no summary (auto-run off) → FAIL ==="
# ════════════════════════════════════════════════════════════════════
setup
rc=0
out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$GATE" 2>&1 ) || rc=$?
if echo "$out" | grep -qE "no Phase 3 validation summary"; then
  pass "T-gate-blocks-without-summary: gate emits the missing-summary FAIL"
else
  fail_ "T-gate-blocks-without-summary" "expected 'no Phase 3 validation summary' FAIL; out:
$(echo "$out" | grep -iE 'phase 3|validation' | head)"
fi
if [ "$rc" -ne 0 ]; then
  pass "T-gate-blocks-without-summary: gate blocks (exit $rc)"
else
  fail_ "T-gate-blocks-without-summary" "expected non-zero exit, got 0"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-gate-autoruns-driver: no summary + auto-run → offline summary + block ==="
# ════════════════════════════════════════════════════════════════════
# Karl: evals should be automatic. With NO pre-existing summary and auto-run
# enabled (default), the gate invokes the driver (offline) to generate a
# baseline summary, then blocks on the un-attested SKIPs.
setup
rc=0
out=$( cd "$PROJ" && bash "$GATE" 2>&1 ) || rc=$?
if compgen -G "$PROJ/docs/test-results/phase3/summary-*.md" >/dev/null 2>&1; then
  pass "T-gate-autoruns-driver: gate auto-generated a phase-3 summary"
else
  fail_ "T-gate-autoruns-driver" "gate did not auto-generate a summary"
fi
if echo "$out" | grep -qE "validation scans not clean|un-attested SKIP"; then
  pass "T-gate-autoruns-driver: gate blocks on the auto-generated un-attested SKIPs"
else
  fail_ "T-gate-autoruns-driver" "expected an un-attested SKIP FAIL; out:
$(echo "$out" | grep -iE 'phase 3.4|validation' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-gate-blocks-unattested-skip: summary SKIPs, no attestation → FAIL ==="
# ════════════════════════════════════════════════════════════════════
setup
write_summary_all_skip
out=$(run_gate 1)
if echo "$out" | grep -qE "validation scans not clean|un-attested SKIP"; then
  pass "T-gate-blocks-unattested-skip: gate emits the un-attested SKIP FAIL"
else
  fail_ "T-gate-blocks-unattested-skip" "expected un-attested SKIP FAIL; out:
$(echo "$out" | grep -iE 'phase 3.4|validation' | head)"
fi
if echo "$out" | grep -qE "validation scans clean"; then
  fail_ "T-gate-blocks-unattested-skip" "gate wrongly reported scans CLEAN with un-attested skips"
else
  pass "T-gate-blocks-unattested-skip: gate did NOT report clean"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-gate-passes-attested-skip: summary SKIPs + all attested → [OK] ==="
# ════════════════════════════════════════════════════════════════════
setup
write_summary_all_skip
attest_all
out=$(run_gate 1)
if echo "$out" | grep -qE "validation scans clean"; then
  pass "T-gate-passes-attested-skip: gate reports phase-3 scans CLEAN (all attested-skip)"
else
  fail_ "T-gate-passes-attested-skip" "expected phase-3 [OK] clean line; out:
$(echo "$out" | grep -iE 'phase 3.4|validation' | head)"
fi
if echo "$out" | grep -qE "validation scans not clean|un-attested SKIP"; then
  fail_ "T-gate-passes-attested-skip" "gate still emitted an un-attested FAIL despite full attestation"
else
  pass "T-gate-passes-attested-skip: no un-attested FAIL emitted"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation: strip # BL-070-GATE-CHECK → phase-3 FAIL disappears (RED) ==="
# ════════════════════════════════════════════════════════════════════
# Copy the gate (+ lib + driver) into a temp scripts/ tree, delete the two
# lines carrying `# BL-070-GATE-CHECK` (the FAIL emit + the issues++), and
# re-run the SAME unattested-skip fixture. With the enforcement removed the
# phase-3 FAIL must vanish. Together with T-gate-blocks-unattested-skip
# (enforcement present → FAIL emitted) this proves the marked lines are
# load-bearing: remove them and the blocking test goes RED.
setup
write_summary_all_skip
MUT="$TMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$GATE" "$MUT/scripts/check-phase-gate.sh"
cp "$DRIVER" "$MUT/scripts/run-phase3-validation.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
grep -v 'BL-070-GATE-CHECK' "$MUT/scripts/check-phase-gate.sh" > "$MUT/scripts/check-phase-gate.sh.tmp"
mv "$MUT/scripts/check-phase-gate.sh.tmp" "$MUT/scripts/check-phase-gate.sh"
chmod +x "$MUT/scripts/check-phase-gate.sh"

if ! grep -q 'BL-070-GATE-CHECK' "$GATE"; then
  fail_ "T-mutation" "BL-070-GATE-CHECK marker missing from the REAL gate — nothing to mutate"
elif grep -q 'BL-070-GATE-CHECK' "$MUT/scripts/check-phase-gate.sh"; then
  fail_ "T-mutation" "BL-070-GATE-CHECK still present after excision — mutation did not apply"
else
  # Real gate: FAIL present.
  real_out=$(run_gate 1)
  # Mutant gate: FAIL absent.
  mut_out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$MUT/scripts/check-phase-gate.sh" 2>&1 ) || true
  if echo "$real_out" | grep -qE "validation scans not clean|un-attested SKIP"; then
    pass "T-mutation: real gate emits the phase-3 FAIL"
  else
    fail_ "T-mutation" "real gate did NOT emit the phase-3 FAIL (fixture wrong?)"
  fi
  if echo "$mut_out" | grep -qE "validation scans not clean|un-attested SKIP"; then
    fail_ "T-mutation" "mutant STILL emitted the phase-3 FAIL — enforcement not load-bearing (mutation is not proof)"
  else
    pass "T-mutation: mutant (enforcement stripped) does NOT emit the phase-3 FAIL (RED proof)"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

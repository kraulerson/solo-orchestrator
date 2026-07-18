#!/usr/bin/env bash
# tests/test-check-phase-gate-date-writeback.sh
#
# BL-071 regression: scripts/check-phase-gate.sh must WRITE today's date
# into .claude/phase-state.json::gates.<gate> when a phase gate passes on
# real APPROVAL_LOG.md evidence, using the PR #97 atomic-finalize pattern
# (mkdir lock + tmp-write + rename). Historically the field was READ but
# never written — a documented gate mechanic that wasn't real.
#
# Contract pinned here:
#   T-happy         gate PASS on a virgin gate → gates.<gate> == today's
#                   date; sibling gates.<gate>_by actor populated; exit 0.
#   T-idempotent    two consecutive PASSes → date unchanged after the
#                   second (first-pass timestamp preserved, [INFO] logged).
#   T-fail-preserves a FAIL after a prior PASS → the populated date is NOT
#                   cleared, and the gate still fails (exit != 0).
#   T-mutation      MUTATION-PROOF: strip the atomic write line (marked
#                   `# BL-071-WRITE`) from a copy of the script and re-run
#                   the T-happy fixture → the date is NOT written. Proves
#                   the write line is load-bearing (remove it → RED).
#
# bash-3.2 safe: no associative arrays, no mapfile, no `${var^^}`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — gate-date auto-write requires jq."
  exit 0
fi

TODAY=$(date +%Y-%m-%d)

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  mkdir -p "$PROJ/docs/phase-0"
  printf 'frd\n' > "$PROJ/docs/phase-0/frd.md"
  printf 'journey\n' > "$PROJ/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$PROJ/docs/phase-0/data-contract.md"
}
teardown() { rm -rf "$TMP"; }

# Write a phase-state.json fixture. $1 = the gates object literal.
write_state() {
  local gates="$1"
  cat > "$PROJ/.claude/phase-state.json" <<JSON
{"project":"wb","current_phase":1,"deployment":"personal","track":"light","gates":$gates}
JSON
}

# APPROVAL_LOG.md with a dated Phase 0 → Phase 1 entry (the real gate
# evidence the auto-write keys off of).
write_approval_log() {
  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Approver** | Alice |
| **Date** | 2026-03-01 |
MD
}

# A PRODUCT_MANIFESTO.md whose 8 sections all carry substantive content
# (so validate_manifesto_content does not add WARNs) and no Open
# Questions — lets the overall gate reach a clean PASS at phase 1.
write_manifesto() {
  {
    local n
    for n in 1 2 3 4 5 6 7 8; do
      echo "## ${n}. Section ${n}"
      echo "Substantive content for section ${n} that is not a template placeholder."
      echo ""
    done
  } > "$PROJ/PRODUCT_MANIFESTO.md"
}

gate_date() {
  jq -r '.gates.phase_0_to_1 // "null"' "$PROJ/.claude/phase-state.json" 2>/dev/null
}
gate_actor() {
  jq -r '.gates.phase_0_to_1_by // "null"' "$PROJ/.claude/phase-state.json" 2>/dev/null
}

run_gate() { ( cd "$PROJ" && bash "$SCRIPT" 2>&1 ); }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-happy: virgin gate PASS → gates.phase_0_to_1 == today ==="
# ════════════════════════════════════════════════════════════════════
setup
write_state '{"phase_0_to_1":null,"phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}'
write_approval_log
write_manifesto
rc=0
out=$(run_gate) || rc=$?
d=$(gate_date)
a=$(gate_actor)
if [ "$d" = "$TODAY" ]; then
  pass "T-happy: gates.phase_0_to_1 written with today's date ($d)"
else
  fail_ "T-happy" "expected gates.phase_0_to_1='$TODAY', got '$d'; out:
$out"
fi
if [ "$a" != "null" ] && [ -n "$a" ]; then
  pass "T-happy: sibling gates.phase_0_to_1_by populated ('$a')"
else
  fail_ "T-happy" "expected gates.phase_0_to_1_by populated, got '$a'"
fi
if [ "$rc" -eq 0 ]; then
  pass "T-happy: overall gate PASS (exit 0)"
else
  fail_ "T-happy" "expected exit 0 on clean fixture, got exit=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-idempotent: two consecutive PASSes → date unchanged ==="
# ════════════════════════════════════════════════════════════════════
setup
write_state '{"phase_0_to_1":null,"phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}'
write_approval_log
write_manifesto
run_gate >/dev/null 2>&1 || true
d1=$(gate_date)
out2=$(run_gate) || true
d2=$(gate_date)
if [ "$d1" = "$TODAY" ] && [ "$d2" = "$d1" ]; then
  pass "T-idempotent: date unchanged across two PASSes ($d2)"
else
  fail_ "T-idempotent" "date changed between runs: run1='$d1' run2='$d2'"
fi
if echo "$out2" | grep -qiE "already recorded|preserving first-pass|idempotent"; then
  pass "T-idempotent: second run logs [INFO] preserving first-pass timestamp"
else
  fail_ "T-idempotent" "expected [INFO] idempotent line on second run; out:
$out2"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-fail-preserves: FAIL after PASS → populated date not cleared ==="
# ════════════════════════════════════════════════════════════════════
# Seed a prior-pass date (2026-03-01, NOT today so 'unchanged' is
# meaningful), keep the APPROVAL_LOG evidence, but remove PRODUCT_MANIFESTO
# so the gate fails (missing-artifact WARN → exit 1). The populated date
# must survive — a prior PASS is real history a later FAIL cannot erase.
setup
write_state '{"phase_0_to_1":"2026-03-01","phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}'
write_approval_log
# deliberately NO PRODUCT_MANIFESTO.md → induces a gate failure
rc=0
out=$(run_gate) || rc=$?
d=$(gate_date)
if [ "$d" = "2026-03-01" ]; then
  pass "T-fail-preserves: populated date preserved through FAIL ($d)"
else
  fail_ "T-fail-preserves" "date was altered on FAIL: expected '2026-03-01', got '$d'; out:
$out"
fi
if [ "$rc" -ne 0 ]; then
  pass "T-fail-preserves: gate still fails (exit $rc)"
else
  fail_ "T-fail-preserves" "expected non-zero exit (missing PRODUCT_MANIFESTO), got exit 0; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation: strip the BL-071-WRITE line → date NOT written (RED) ==="
# ════════════════════════════════════════════════════════════════════
# Copy the script + its lib into a temp scripts/ tree, delete the single
# line carrying the `# BL-071-WRITE` marker (the atomic `mv` finalize),
# and run the SAME virgin fixture. With the write removed, gates.<gate>
# must stay null. Together with T-happy (write present → date recorded)
# this proves the write line is load-bearing: remove it and T-happy is RED.
setup
MUT="$TMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$SCRIPT" "$MUT/scripts/check-phase-gate.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
# Excise the atomic write line.
grep -v 'BL-071-WRITE' "$MUT/scripts/check-phase-gate.sh" > "$MUT/scripts/check-phase-gate.sh.tmp"
mv "$MUT/scripts/check-phase-gate.sh.tmp" "$MUT/scripts/check-phase-gate.sh"
chmod +x "$MUT/scripts/check-phase-gate.sh"
# Sanity: the marker really was present and is now gone.
if grep -q 'BL-071-WRITE' "$MUT/scripts/check-phase-gate.sh"; then
  fail_ "T-mutation" "BL-071-WRITE marker still present after excision — mutation did not apply"
elif ! grep -q 'BL-071-WRITE' "$SCRIPT"; then
  fail_ "T-mutation" "BL-071-WRITE marker missing from the REAL script — nothing to mutate (write line unmarked?)"
else
  write_state '{"phase_0_to_1":null,"phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}'
  write_approval_log
  write_manifesto
  ( cd "$PROJ" && bash "$MUT/scripts/check-phase-gate.sh" >/dev/null 2>&1 ) || true
  d=$(gate_date)
  if [ "$d" = "null" ] || [ -z "$d" ]; then
    pass "T-mutation: with the write line removed, gates.phase_0_to_1 stays null (write is load-bearing)"
  else
    fail_ "T-mutation" "date '$d' was written even without the BL-071-WRITE line — the write is NOT load-bearing (mutation not proof)"
  fi
fi
teardown

# APPROVAL_LOG.md with the gate's section HEADER present but NO dated line
# (Date pending). Header-presence alone is NOT evidence — the auto-write
# must key off a real recorded date, not a template stub.
write_approval_log_no_evidence() {
  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Approver** | Alice |
| **Date** | (pending) |
MD
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-no-evidence: no dated approval entry → NO write, gate blocks ==="
# ════════════════════════════════════════════════════════════════════
# The scope-gap the BL-071 verifier surfaced: nothing pinned that the
# write is EVIDENCE-GATED. current_phase>=1, empty gates.phase_0_to_1, and
# an APPROVAL_LOG.md with the header but no dated entry → the gate must NOT
# synthesize a date, and must WARN (issues++ → exit 1 in blocking mode).
setup
write_state '{"phase_0_to_1":null,"phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}'
write_approval_log_no_evidence
# deliberately NO PRODUCT_MANIFESTO.md either — the gate has nothing to pass
rc=0
out=$(run_gate) || rc=$?
d=$(gate_date)
if [ "$d" = "null" ] || [ -z "$d" ]; then
  pass "T-no-evidence: gates.phase_0_to_1 stays null (no date synthesized without evidence)"
else
  fail_ "T-no-evidence" "a date '$d' was synthesized despite NO dated approval evidence; out:
$out"
fi
if [ "$rc" -ne 0 ]; then
  pass "T-no-evidence: gate blocks (exit $rc) and WARNs about the unrecorded gate"
else
  fail_ "T-no-evidence" "expected non-zero exit (unrecorded gate should WARN/block), got exit 0; out:
$out"
fi
if echo "$out" | grep -qiE "Phase 0.1: .*not recorded|not recorded in phase-state"; then
  pass "T-no-evidence: output WARNs 'gate date not recorded'"
else
  fail_ "T-no-evidence" "expected a 'gate date not recorded' WARN for Phase 0→1; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-evidence-gate-mutation: force evidence always-true → date IS synthesized (RED proof) ==="
# ════════════════════════════════════════════════════════════════════
# MUTATION-PROOF for the evidence gate. Copy the script, force
# _cpg_gate_has_evidence to always return 0 (the verifier's exact
# `if true` mutation), and re-run the SAME no-evidence fixture. With the
# evidence gate defeated, the script synthesizes a date into a project that
# has ZERO approval evidence — proving _cpg_gate_has_evidence is what makes
# T-no-evidence pass. (Remove/defeat the gate → T-no-evidence goes RED.)
setup
MUT="$TMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$SCRIPT" "$MUT/scripts/check-phase-gate.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
# Inject `return 0` as the first statement of _cpg_gate_has_evidence.
awk '{print} /_cpg_gate_has_evidence\(\) \{/{print "  return 0  # forced-always-true (evidence-gate mutation)"}' \
  "$MUT/scripts/check-phase-gate.sh" > "$MUT/scripts/check-phase-gate.sh.tmp"
mv "$MUT/scripts/check-phase-gate.sh.tmp" "$MUT/scripts/check-phase-gate.sh"
chmod +x "$MUT/scripts/check-phase-gate.sh"
if ! grep -q 'BL-071-EVIDENCE-GATE' "$SCRIPT"; then
  fail_ "T-evidence-gate-mutation" "BL-071-EVIDENCE-GATE marker missing from the REAL script — evidence gate unmarked?"
elif ! grep -q 'forced-always-true (evidence-gate mutation)' "$MUT/scripts/check-phase-gate.sh"; then
  fail_ "T-evidence-gate-mutation" "mutation did not inject into _cpg_gate_has_evidence"
else
  write_state '{"phase_0_to_1":null,"phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}'
  write_approval_log_no_evidence
  ( cd "$PROJ" && bash "$MUT/scripts/check-phase-gate.sh" >/dev/null 2>&1 ) || true
  d=$(gate_date)
  if [ "$d" = "$TODAY" ]; then
    pass "T-evidence-gate-mutation: defeating _cpg_gate_has_evidence synthesizes a date with no evidence (gate is load-bearing)"
  else
    fail_ "T-evidence-gate-mutation" "expected a synthesized date '$TODAY' under the always-true mutation, got '$d' — mutation is not proof"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

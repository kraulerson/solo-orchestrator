#!/usr/bin/env bash
# tests/test-check-phase-gate-argv-parser.sh
#
# BL-060 regression: scripts/check-phase-gate.sh must parse `--gate <name>`
# and scope the check to the named gate.
#
# Pre-fix state: the script had NO argv parsing whatsoever. Scenarios
# invoking `--gate phase_1_to_2` succeeded coincidentally because
# `current_phase=2` in phase-state.json triggered the backstop — the
# flag had no effect. A future refactor of the backstop's trigger
# condition would silently break `--gate` consumers.
#
# Post-fix contract:
#   1. --gate <name> forces the named gate's checks to run regardless
#      of current_phase (so a fixture with current_phase=1 still fires
#      the Phase 1→2 checks under --gate phase_1_to_2).
#   2. --gate <name> caps checking at the named gate — HIGHER-phase
#      gate blocks do not run (avoids noise from irrelevant gates).
#   3. Unknown gate → exit 2 + clear diagnostic to stderr.
#   4. --gate specified twice → exit 2 + clear diagnostic.
#   5. Unknown flag → exit 2 + clear diagnostic.
#   6. --gate <name> with no phase-state.json fixture → exit 1 + clear
#      diagnostic (does NOT crash under `set -euo pipefail`).
#   7. --help / -h → exit 0 + usage text mentioning `--gate`.
#
# Mutation guard (T-mutation): if the argv parser is removed, T-scoped
# FAILS RED — the Phase 1→2 backstop line does not appear on
# --gate phase_1_to_2 with current_phase=1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
}
teardown() { rm -rf "$TMP"; }

# Run the gate script and capture combined stdout/stderr + exit code
# without letting `set -e` in the caller propagate a non-zero exit.
run_gate() {
  ( cd "$PROJ" && bash "$SCRIPT" "$@" 2>&1 )
  echo "__EXIT__:$?"
}

extract_exit() {
  # Extracts trailing exit code from run_gate output.
  echo "$1" | awk -F':' '/^__EXIT__:/ { print $2 }' | tail -1
}

strip_exit() {
  echo "$1" | sed '/^__EXIT__:/d'
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-scoped: --gate phase_1_to_2 + current_phase=1 → gate fires ==="
# ════════════════════════════════════════════════════════════════════
# Without --gate, the Phase 1→2 checks only run when current_phase>=2.
# With --gate, they must run even when current_phase=1. We assert on
# the ZDR gate FAIL line because it's the cleanest post-parse signal —
# the ZDR block requires no external tooling (unlike the branch-
# protection backstop) and always fires when phase >= 2.
echo "T-scoped: --gate phase_1_to_2 + current_phase=1 → ZDR gate FAIL appears"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"deployment":"personal","gates":{"phase_0_to_1":"2026-01-01"}}
JSON
# APPROVAL_LOG must exist so the script doesn't exit early on line 125.
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
| Approver | Date |
| Op | 2026-01-01 |
MD
raw=$(run_gate --gate phase_1_to_2)
exit_code=$(extract_exit "$raw")
out=$(strip_exit "$raw")
if echo "$out" | grep -qE "FAIL.*Phase 1.2 ZDR gate.*data_classification"; then
  pass "T-scoped: ZDR gate FAIL fires under --gate phase_1_to_2 with current_phase=1"
else
  fail_ "T-scoped" "expected Phase 1→2 ZDR FAIL; got exit=$exit_code, out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-scoped-caps: --gate phase_1_to_2 caps at phase 2 (no phase 3+ noise) ==="
# ════════════════════════════════════════════════════════════════════
# When --gate phase_1_to_2 is passed with a fixture where current_phase=4
# in phase-state.json, we should NOT see Phase 3→4 checks running (the
# scope caps at phase_1_to_2). This is what makes the flag "scope" the
# check rather than merely elevate it.
echo "T-scoped-caps: --gate phase_1_to_2 + current_phase=4 → no Phase 3→4 lines"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":4,"deployment":"personal","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01","phase_2_to_3":"2026-03-01","phase_3_to_4":"2026-04-01"}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
Approved 2026-01-01

## Phase 1 → Phase 2
Approved 2026-02-01

## Phase 2 → Phase 3
Approved 2026-03-01

## Phase 3 → Phase 4
Approved 2026-04-01
MD
raw=$(run_gate --gate phase_1_to_2)
out=$(strip_exit "$raw")
# We expect Phase 1→2 lines to appear (positive) and Phase 3→4 to NOT
# appear (negative). "Phase 2→3" also should not appear under strict
# scoping, but the primary test is that phase_3_to_4-specific FAILs
# (like docs/test-results) do not surface.
if echo "$out" | grep -qE "Phase 3.4:.*(docs/test-results|SECURITY.md|penetration|POC)"; then
  fail_ "T-scoped-caps" "Phase 3→4 checks ran but scope was phase_1_to_2; out:
$out"
elif echo "$out" | grep -qE "Phase 1.2 ZDR gate|Phase 1.2 backstop"; then
  pass "T-scoped-caps: Phase 1→2 checks ran, Phase 3→4 checks skipped"
else
  fail_ "T-scoped-caps" "expected Phase 1→2 activity; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-unknown-gate: --gate bogus → exit 2 + clear diagnostic ==="
# ════════════════════════════════════════════════════════════════════
echo "T-unknown-gate: --gate bogus → exit 2, stderr names 'Unknown gate'"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG
MD
raw=$(run_gate --gate bogus_gate_name)
exit_code=$(extract_exit "$raw")
out=$(strip_exit "$raw")
if [ "$exit_code" != "2" ]; then
  fail_ "T-unknown-gate" "expected exit 2, got exit=$exit_code; out:
$out"
elif echo "$out" | grep -qE "Unknown gate.*bogus_gate_name"; then
  pass "T-unknown-gate: exit 2 + 'Unknown gate' diagnostic emitted"
else
  fail_ "T-unknown-gate" "expected 'Unknown gate' diagnostic; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-multiple-gates: --gate a --gate b → exit 2 ==="
# ════════════════════════════════════════════════════════════════════
echo "T-multiple-gates: --gate phase_0_to_1 --gate phase_1_to_2 → exit 2"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG
MD
raw=$(run_gate --gate phase_0_to_1 --gate phase_1_to_2)
exit_code=$(extract_exit "$raw")
out=$(strip_exit "$raw")
if [ "$exit_code" != "2" ]; then
  fail_ "T-multiple-gates" "expected exit 2 (double --gate), got exit=$exit_code; out:
$out"
elif echo "$out" | grep -qiE "gate.*(specified more than once|already set)"; then
  pass "T-multiple-gates: exit 2 + 'more than once' diagnostic emitted"
else
  fail_ "T-multiple-gates" "expected 'specified more than once' diagnostic; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-unknown-flag: --frobnicate → exit 2 ==="
# ════════════════════════════════════════════════════════════════════
echo "T-unknown-flag: --frobnicate → exit 2, stderr names 'Unknown argument'"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG
MD
raw=$(run_gate --frobnicate)
exit_code=$(extract_exit "$raw")
out=$(strip_exit "$raw")
if [ "$exit_code" != "2" ]; then
  fail_ "T-unknown-flag" "expected exit 2, got exit=$exit_code; out:
$out"
elif echo "$out" | grep -qE "Unknown argument.*frobnicate"; then
  pass "T-unknown-flag: exit 2 + 'Unknown argument' diagnostic emitted"
else
  fail_ "T-unknown-flag" "expected 'Unknown argument' diagnostic; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-no-current-phase: --gate with no phase-state.json → clear error ==="
# ════════════════════════════════════════════════════════════════════
# Regression guard: the script must NOT crash under `set -euo pipefail`
# when --gate is specified but phase-state.json is absent. It should
# emit a clear error and exit non-zero — the operator asked for a scope
# and we have no fixture to check.
echo "T-no-current-phase: --gate phase_1_to_2 + no phase-state.json → exit 1, clear error"
setup
# No phase-state.json, no APPROVAL_LOG.md
raw=$(run_gate --gate phase_1_to_2)
exit_code=$(extract_exit "$raw")
out=$(strip_exit "$raw")
if [ "$exit_code" = "0" ]; then
  fail_ "T-no-current-phase" "expected non-zero exit (--gate requires fixture); got exit=0; out:
$out"
elif echo "$out" | grep -qiE "(gate.*specified.*not found|not found.*gate|phase-state\.json.*cannot verify)"; then
  pass "T-no-current-phase: non-zero exit + clear diagnostic about missing phase-state.json"
else
  fail_ "T-no-current-phase" "expected clear error about missing phase-state.json under --gate; got exit=$exit_code; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-help: --help → exit 0 + usage mentions --gate ==="
# ════════════════════════════════════════════════════════════════════
echo "T-help: --help → exit 0, usage names '--gate'"
setup
raw=$(run_gate --help)
exit_code=$(extract_exit "$raw")
out=$(strip_exit "$raw")
if [ "$exit_code" != "0" ]; then
  fail_ "T-help" "expected exit 0, got exit=$exit_code; out:
$out"
elif echo "$out" | grep -qE "(Usage|usage).*check-phase-gate" && echo "$out" | grep -q -- "--gate"; then
  pass "T-help: exit 0 + usage text names --gate"
else
  fail_ "T-help" "expected usage text mentioning --gate; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-backcompat: no --gate → existing behavior unchanged ==="
# ════════════════════════════════════════════════════════════════════
# When no --gate is passed, current_phase from phase-state.json alone
# determines which checks fire. Regression guard so we don't break the
# hundreds of callers that never pass --gate.
echo "T-backcompat: no --gate + current_phase=0 → Phase 1→2 checks don't run"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"personal"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG
MD
raw=$(run_gate)
out=$(strip_exit "$raw")
# The ZDR gate FAIL should NOT appear when current_phase=0 and no --gate
if echo "$out" | grep -qE "FAIL.*Phase 1.2 ZDR gate"; then
  fail_ "T-backcompat" "Phase 1→2 ZDR FAIL should not fire at current_phase=0 without --gate; out:
$out"
else
  pass "T-backcompat: no --gate + current_phase=0 → no Phase 1→2 checks"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

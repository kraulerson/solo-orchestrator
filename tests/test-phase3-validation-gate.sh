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
# BL-082 staleness binding (2026-07-09) — the gate trusts a summary only if it
# was generated against the CURRENT tree with a clean (scoped) working tree.
# Fixtures are REAL git repos (setup() git-inits + commits); write_summary_*
# stamp a matching `tree:` + `dirty: no` so the pre-existing cases keep testing
# trusted-summary paths. Added:
#   T-fresh-trusted          matching tree + clean → gate does NOT re-run the
#                            driver (asserted via a counting mock driver).
#   T-stale-rerun            2nd commit advances HEAD^{tree} → old summary
#                            superseded; the gate regenerates + evaluates fresh.
#   T-stale-norerun-fails    SOLO_PHASE3_GATE_NOAUTORUN=1 + stale → gate FAIL,
#                            rc=1, actionable re-run message. (Flipped RED by
#                            the BL-082-STALENESS mutation.)
#   T-dirty-tree-stale       summary recorded `dirty: yes` → stale path.
#   T-pre-bl082-summary-stale  summary with NO `tree:` line → stale path.
#   T-stateflip-not-dirty    (Correction 1) modify ONLY .claude/phase-state.json
#                            uncommitted → still FRESH, no re-run.
#   T-live-dirty-stale       (Correction 2) uncommitted SOURCE edit → stale even
#                            though HEAD^{tree} still matches.
#   T-bl082-mutation         excise `# BL-082-STALENESS` → T-stale-norerun-fails
#                            goes RED (staleness defeated → stale all-PASS
#                            summary trusted); restore → GREEN.
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
  # BL-082: fixtures must be REAL git repos — the gate now binds the summary to
  # HEAD^{tree}. Make PROJ a git repo with an initial commit so a matching
  # `tree:` line renders a seeded summary FRESH (mirrors that
  # .claude/phase-state.json is tracked in downstream projects). Without this
  # every seeded summary would resolve to `tree: none` / mismatched → always
  # stale, and these cases could no longer exercise the trusted-summary paths.
  (
    cd "$PROJ" || exit 1
    unset GITHUB_BASE_REF
    git init -q
    git config user.name "Test"
    git config user.email "test@example.com"
    git config commit.gpgsign false
    git add -A
    git commit -q -m "init fixture" >/dev/null 2>&1
  )
}
teardown() { rm -rf "$TMP"; }

# Current tree of the PROJ fixture repo (empty if not a git repo).
proj_tree() { ( cd "$PROJ" && git rev-parse "HEAD^{tree}" 2>/dev/null ); }

# Add a second commit so HEAD^{tree} advances → any summary bound to the
# earlier tree becomes STALE (tree-mismatch path).
proj_advance_tree() {
  ( cd "$PROJ" && echo "change-$RANDOM" > src-change.txt && git add -A && git commit -q -m "advance" >/dev/null 2>&1 )
}

# _write_summary <tree> <dirty> <newline-separated RESULT lines> — write a
# summary in the BL-082 format. Pass tree="" / omit the `- tree:` line via
# _write_summary_legacy for the pre-BL-082 backward-compat case.
_write_summary() {
  local tree="$1" dirty="$2" body="$3"
  mkdir -p "$PROJ/docs/test-results/phase3"
  {
    echo "# Phase 3 Validation Summary"
    echo "- tree: ${tree}"
    echo "- dirty: ${dirty}"
    echo "- Overall: FAIL"
    echo ""
    echo "## Machine-readable results"
    echo '```'
    printf '%s\n' "$body"
    echo '```'
  } > "$PROJ/docs/test-results/phase3/summary-2026-07-06T00-00-00Z.md"
}

# Pre-BL-082 summary: NO `tree:`/`dirty:` header lines at all (backward-compat
# → the gate must treat it as STALE).
_write_summary_legacy() {
  local body="$1"
  mkdir -p "$PROJ/docs/test-results/phase3"
  {
    echo "# Phase 3 Validation Summary"
    echo "- Overall: FAIL"
    echo ""
    echo "## Machine-readable results"
    echo '```'
    printf '%s\n' "$body"
    echo '```'
  } > "$PROJ/docs/test-results/phase3/summary-2026-07-06T00-00-00Z.md"
}

ALL_SKIP_ROWS='RESULT semgrep-full-tree SKIP
RESULT license SKIP
RESULT snyk SKIP
RESULT zap-dast SKIP
RESULT threat-model SKIP'

ALL_PASS_ROWS='RESULT semgrep-full-tree PASS
RESULT license PASS
RESULT snyk PASS
RESULT zap-dast PASS
RESULT threat-model PASS'

# Build a sandbox scripts/ dir holding the REAL gate + lib but a COUNTING MOCK
# driver, so tests can assert whether the gate re-ran the driver (fresh →
# no call; stale → call). The mock appends a line to $DRIVER_CALLS_FILE each
# invocation and emits a minimal FRESH summary (tree = current HEAD^{tree}).
make_sandbox_with_mock_driver() {
  SANDBOX="$TMP/sandbox"
  mkdir -p "$SANDBOX/scripts/lib"
  cp "$GATE" "$SANDBOX/scripts/check-phase-gate.sh"
  cp "$REPO_ROOT"/scripts/lib/*.sh "$SANDBOX/scripts/lib/" 2>/dev/null || true
  MOCK_GATE="$SANDBOX/scripts/check-phase-gate.sh"
  DRIVER_CALLS="$TMP/driver-calls"
  : > "$DRIVER_CALLS"
  cat > "$SANDBOX/scripts/run-phase3-validation.sh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail
[ -n "${DRIVER_CALLS_FILE:-}" ] && echo call >> "$DRIVER_CALLS_FILE"
rdir="docs/test-results/phase3"
while [ $# -gt 0 ]; do
  case "$1" in
    --results-dir) rdir="$2"; shift 2 ;;
    --results-dir=*) rdir="${1#--results-dir=}"; shift ;;
    *) shift ;;
  esac
done
mkdir -p "$rdir"
tree=$(git rev-parse "HEAD^{tree}" 2>/dev/null || echo none)
f="$rdir/summary-$(date -u +%Y-%m-%dT%H-%M-%SZ).md"
{
  echo "# Phase 3 Validation Summary"
  echo "- tree: $tree"
  echo "- dirty: no"
  echo ""
  echo "## Machine-readable results"
  echo '```'
  echo "RESULT semgrep-full-tree SKIP"
  echo "RESULT license SKIP"
  echo "RESULT snyk SKIP"
  echo "RESULT zap-dast SKIP"
  echo "RESULT threat-model SKIP"
  echo '```'
} > "$f"
exit 1
MOCK
  chmod +x "$SANDBOX/scripts/run-phase3-validation.sh"
}

# Run the MOCK-driver gate. $1 = SOLO_PHASE3_GATE_NOAUTORUN value (default empty
# → auto-run enabled).
run_mock_gate() {
  ( cd "$PROJ" && DRIVER_CALLS_FILE="$DRIVER_CALLS" SOLO_PHASE3_GATE_NOAUTORUN="${1:-}" bash "$MOCK_GATE" 2>&1 ) || true
}

# Count how many times the mock driver was invoked (line count; 0 when empty).
driver_call_count() { wc -l < "$DRIVER_CALLS" 2>/dev/null | tr -d ' '; }

# Pre-create a FRESH summary (BL-082: matching tree + dirty:no) whose five
# scanners are all SKIP. Only the RESULT lines + the tree/dirty provenance are
# load-bearing for the gate.
write_summary_all_skip() {
  _write_summary "$(proj_tree)" "no" "$ALL_SKIP_ROWS"
}

# semgrep reports a FAIL finding; the other four SKIP. FRESH. Used to exercise
# the gate's FAIL arm in isolation (attest the four skips so the ONLY blocker
# is the FAIL status).
write_summary_semgrep_fail() {
  _write_summary "$(proj_tree)" "no" 'RESULT semgrep-full-tree FAIL
RESULT license SKIP
RESULT snyk SKIP
RESULT zap-dast SKIP
RESULT threat-model SKIP'
}

# Summary that OMITS semgrep's RESULT line (→ gate reads it as MISSING) and
# has a garbled status for license. Both must count as blocking. FRESH.
write_summary_missing_and_garbled() {
  _write_summary "$(proj_tree)" "no" 'RESULT license BOGUS
RESULT snyk SKIP
RESULT zap-dast SKIP
RESULT threat-model SKIP'
}

attest_all() {
  local s
  for s in semgrep-full-tree license snyk zap-dast threat-model; do
    ( cd "$PROJ" && bash "$DRIVER" --attest "$s" --reason "test: tool not provisioned" --signoff "Tester" ) >/dev/null 2>&1
  done
}

# Attest only the four stub scanners (leave semgrep-full-tree un-attested).
attest_four_stubs() {
  local s
  for s in license snyk zap-dast threat-model; do
    ( cd "$PROJ" && bash "$DRIVER" --attest "$s" --reason "test: tool not provisioned" --signoff "Tester" ) >/dev/null 2>&1
  done
}

# Write whitespace-only attestations DIRECTLY (bypassing the driver's own
# reject-on-whitespace guard) so we test the gate predicate's trim in
# isolation. reason=" " signoff=" " for all five scanners.
attest_all_whitespace_direct() {
  local s tmp
  for s in semgrep-full-tree license snyk zap-dast threat-model; do
    tmp="$PROJ/.claude/phase-state.json.tmp"
    jq --arg n "$s" '.phase3 = (.phase3 // {}) | .phase3.attestations = ((.phase3.attestations // {}) + {($n): {"reason":" ","signoff":" ","at":"2026-07-06T00:00:00Z"}})' \
      "$PROJ/.claude/phase-state.json" > "$tmp" && mv "$tmp" "$PROJ/.claude/phase-state.json"
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
echo "=== T-gate-blocks-fail-status: a RESULT <scanner> FAIL → gate FAILs ==="
# ════════════════════════════════════════════════════════════════════
# The four stub SKIPs are attested, so the ONLY blocker is semgrep's FAIL
# status — isolating the gate's FAIL arm.
setup
write_summary_semgrep_fail
attest_four_stubs
out=$(run_gate 1)
if echo "$out" | grep -qE "validation scans not clean.*FAIL"; then
  pass "T-gate-blocks-fail-status: gate blocks on the semgrep FAIL status"
else
  fail_ "T-gate-blocks-fail-status" "expected a FAIL-arm block; out:
$(echo "$out" | grep -iE 'phase 3.4|validation' | head)"
fi
if echo "$out" | grep -qE "validation scans clean"; then
  fail_ "T-gate-blocks-fail-status" "gate wrongly reported CLEAN with a FAIL status present"
else
  pass "T-gate-blocks-fail-status: gate did NOT report clean"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-gate-blocks-missing-status: MISSING/garbled RESULT → gate FAILs ==="
# ════════════════════════════════════════════════════════════════════
# semgrep has NO RESULT line (→ MISSING) and license has a garbled status
# (BOGUS). The three real SKIPs are attested; the ONLY blockers are the
# MISSING + garbled statuses, which must count as gate-blocking.
setup
write_summary_missing_and_garbled
( cd "$PROJ" && bash "$DRIVER" --attest snyk --reason "t" --signoff "T" ) >/dev/null 2>&1
( cd "$PROJ" && bash "$DRIVER" --attest zap-dast --reason "t" --signoff "T" ) >/dev/null 2>&1
( cd "$PROJ" && bash "$DRIVER" --attest threat-model --reason "t" --signoff "T" ) >/dev/null 2>&1
out=$(run_gate 1)
if echo "$out" | grep -qE "validation scans not clean"; then
  pass "T-gate-blocks-missing-status: gate blocks on MISSING/garbled status"
else
  fail_ "T-gate-blocks-missing-status" "expected a block on MISSING/garbled status; out:
$(echo "$out" | grep -iE 'phase 3.4|validation' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-fail-arm-mutation: drop the FAIL check → FAIL-status no longer blocks (RED) ==="
# ════════════════════════════════════════════════════════════════════
# MUTATION-PROOF for the FAIL arm. Copy the gate, strip the line marked
# `# BL-070-FAIL-ARM` (the p3_fail increment), and re-run the semgrep-FAIL
# fixture (four stubs attested). With the FAIL count defeated, p3_fail stays 0
# and the gate reports the phase-3 scans CLEAN — proving that increment is
# what makes T-gate-blocks-fail-status pass (remove it → that test goes RED).
setup
write_summary_semgrep_fail
attest_four_stubs
MUT="$TMP/mutfail"
mkdir -p "$MUT/scripts/lib"
cp "$GATE" "$MUT/scripts/check-phase-gate.sh"
cp "$DRIVER" "$MUT/scripts/run-phase3-validation.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
grep -v 'BL-070-FAIL-ARM' "$MUT/scripts/check-phase-gate.sh" > "$MUT/scripts/cpg.tmp"
mv "$MUT/scripts/cpg.tmp" "$MUT/scripts/check-phase-gate.sh"
chmod +x "$MUT/scripts/check-phase-gate.sh"
if ! grep -q 'BL-070-FAIL-ARM' "$GATE"; then
  fail_ "T-fail-arm-mutation" "BL-070-FAIL-ARM marker missing from the REAL gate — nothing to mutate"
elif grep -q 'BL-070-FAIL-ARM' "$MUT/scripts/check-phase-gate.sh"; then
  fail_ "T-fail-arm-mutation" "BL-070-FAIL-ARM still present after excision — mutation did not apply"
else
  real_out=$(run_gate 1)
  mut_out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$MUT/scripts/check-phase-gate.sh" 2>&1 ) || true
  if echo "$real_out" | grep -qE "validation scans not clean.*FAIL"; then
    pass "T-fail-arm-mutation: real gate blocks on the FAIL status"
  else
    fail_ "T-fail-arm-mutation" "real gate did NOT block on the FAIL status (fixture wrong?)"
  fi
  if echo "$mut_out" | grep -qE "validation scans not clean"; then
    fail_ "T-fail-arm-mutation" "mutant STILL blocked — the FAIL arm is not load-bearing (mutation is not proof)"
  else
    pass "T-fail-arm-mutation: mutant (FAIL check stripped) reports CLEAN — FAIL status slips through (RED proof)"
  fi
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-driver-rejects-whitespace-reason: --reason ' ' → exit 2, nothing written ==="
# ════════════════════════════════════════════════════════════════════
setup
rc=0
( cd "$PROJ" && bash "$DRIVER" --attest snyk --reason " " --signoff " " ) >/dev/null 2>&1 || rc=$?
recorded=$(jq -r '.phase3.attestations.snyk // "none"' "$PROJ/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" -eq 2 ] && [ "$recorded" = "none" ]; then
  pass "T-driver-rejects-whitespace-reason: whitespace-only --reason → exit 2, nothing recorded"
else
  fail_ "T-driver-rejects-whitespace-reason" "expected exit 2 + no record; rc=$rc recorded='$recorded'"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-gate-rejects-whitespace-attestation: ' '/' ' in state → un-attested → FAIL ==="
# ════════════════════════════════════════════════════════════════════
# Whitespace-only attestations written DIRECTLY into phase-state.json (past
# the driver's own guard) must still be rejected by the gate predicate's trim.
setup
write_summary_all_skip
attest_all_whitespace_direct
out=$(run_gate 1)
if echo "$out" | grep -qE "validation scans not clean|un-attested SKIP"; then
  pass "T-gate-rejects-whitespace-attestation: gate treats ' '/' ' as un-attested → FAIL"
else
  fail_ "T-gate-rejects-whitespace-attestation" "gate accepted a whitespace-only attestation as valid; out:
$(echo "$out" | grep -iE 'phase 3.4|validation' | head)"
fi
if echo "$out" | grep -qE "validation scans clean"; then
  fail_ "T-gate-rejects-whitespace-attestation" "gate reported CLEAN on whitespace-only attestations"
else
  pass "T-gate-rejects-whitespace-attestation: gate did NOT report clean"
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

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-fresh-trusted: matching tree + clean → gate does NOT re-run driver ==="
# ════════════════════════════════════════════════════════════════════
# BL-082: a summary bound to the CURRENT tree with dirty:no is FRESH and must be
# trusted as-is — the gate must NOT auto-run the driver. Proven with a counting
# mock driver: the call count stays 0 while the gate reports the fresh
# (all-attested-skip) summary CLEAN.
setup
make_sandbox_with_mock_driver
write_summary_all_skip
attest_all
out=$(run_mock_gate)          # auto-run ENABLED — fresh summary must pre-empt it
calls=$(driver_call_count)
if [ "$calls" -eq 0 ]; then
  pass "T-fresh-trusted: driver NOT re-run for a fresh summary (calls=0)"
else
  fail_ "T-fresh-trusted" "gate re-ran the driver for a FRESH summary (calls=$calls)"
fi
if echo "$out" | grep -qE "validation scans clean"; then
  pass "T-fresh-trusted: gate trusts + reports the fresh summary CLEAN"
else
  fail_ "T-fresh-trusted" "gate did not report the fresh summary clean; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-stale-rerun: 2nd commit advances tree → old summary superseded, fresh generated ==="
# ════════════════════════════════════════════════════════════════════
# A summary bound to commit-1's tree is superseded once HEAD^{tree} advances.
# With auto-run enabled the gate prints [STALE], regenerates (mock driver
# called ≥1), and evaluates the FRESH summary — proven by the newest summary
# on disk being bound to the NEW tree, and the gate blocking on the
# regenerated file's un-attested skips (nothing attested).
setup
make_sandbox_with_mock_driver
write_summary_all_skip         # bound to commit-1
proj_advance_tree              # HEAD^{tree} now differs from the recorded tree
out=$(run_mock_gate)           # auto-run ENABLED
calls=$(driver_call_count)
if [ "$calls" -ge 1 ]; then
  pass "T-stale-rerun: gate re-ran the driver on stale (calls=$calls)"
else
  fail_ "T-stale-rerun" "gate did NOT re-run the driver for a stale summary (calls=$calls)"
fi
if echo "$out" | grep -q "\[STALE\]"; then
  pass "T-stale-rerun: gate printed an explicit [STALE] line"
else
  fail_ "T-stale-rerun" "no [STALE] line; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
newest=$(ls -1 "$PROJ"/docs/test-results/phase3/summary-*.md 2>/dev/null | sort | tail -1)
newest_tree=$(grep -m1 '^- tree:' "$newest" 2>/dev/null | sed 's/^- tree:[[:space:]]*//; s/[[:space:]]*$//')
cur_tree=$(proj_tree)
if [ -n "$newest_tree" ] && [ "$newest_tree" = "$cur_tree" ]; then
  pass "T-stale-rerun: a FRESH summary bound to the NEW tree was generated + is what gets evaluated"
else
  fail_ "T-stale-rerun" "newest summary not bound to the current tree (newest='$newest_tree' cur='$cur_tree')"
fi
if echo "$out" | grep -qE "validation scans not clean|un-attested SKIP"; then
  pass "T-stale-rerun: gate evaluated the REGENERATED summary (un-attested skips block)"
else
  fail_ "T-stale-rerun" "gate did not evaluate the regenerated summary; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-stale-norerun-fails: NOAUTORUN=1 + stale → gate FAIL, rc=1, actionable ==="
# ════════════════════════════════════════════════════════════════════
# With regeneration disabled, a stale summary must NOT be silently accepted:
# gate FAILs (rc=1) with a message telling the operator to re-run the driver.
# The summary is all-PASS so that WITHOUT the staleness check it would be
# trusted CLEAN — isolating staleness as the sole blocker (see T-bl082-mutation).
setup
_write_summary "$(proj_tree)" "no" "$ALL_PASS_ROWS"
proj_advance_tree              # → stale (tree mismatch)
rc=0
out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$GATE" 2>&1 ) || rc=$?
if [ "$rc" -eq 1 ]; then
  pass "T-stale-norerun-fails: gate blocks (rc=1)"
else
  fail_ "T-stale-norerun-fails" "expected rc=1, got $rc"
fi
if echo "$out" | grep -q "STALE"; then
  pass "T-stale-norerun-fails: gate emits a STALE FAIL"
else
  fail_ "T-stale-norerun-fails" "no STALE message; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
if echo "$out" | grep -q "run-phase3-validation.sh"; then
  pass "T-stale-norerun-fails: message is actionable (re-run the driver)"
else
  fail_ "T-stale-norerun-fails" "message not actionable; out:
$(echo "$out" | grep -iE 'stale' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-dirty-tree-stale: summary recorded dirty:yes → stale path ==="
# ════════════════════════════════════════════════════════════════════
# Tree MATCHES the current HEAD^{tree}, but the summary recorded dirty:yes
# (generated on a dirty tree) → must be stale.
setup
_write_summary "$(proj_tree)" "yes" "$ALL_PASS_ROWS"
out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$GATE" 2>&1 ) || true
if echo "$out" | grep -q "STALE"; then
  pass "T-dirty-tree-stale: dirty:yes summary is stale despite a matching tree"
else
  fail_ "T-dirty-tree-stale" "expected a STALE result; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
if echo "$out" | grep -qE "validation scans clean"; then
  fail_ "T-dirty-tree-stale" "gate wrongly reported CLEAN for a dirty:yes summary"
else
  pass "T-dirty-tree-stale: gate did NOT report clean"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-pre-bl082-summary-stale: summary with NO tree: line → stale (backward compat) ==="
# ════════════════════════════════════════════════════════════════════
setup
_write_summary_legacy "$ALL_PASS_ROWS"
out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$GATE" 2>&1 ) || true
if echo "$out" | grep -q "STALE"; then
  pass "T-pre-bl082-summary-stale: a pre-BL-082 summary (no tree line) is stale"
else
  fail_ "T-pre-bl082-summary-stale" "expected a STALE result; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-stateflip-not-dirty (Correction 1): modifying ONLY .claude/ → still FRESH ==="
# ════════════════════════════════════════════════════════════════════
# The gate writes phase-state.json (BL-071 gate date) on PASS and the driver
# writes attestations there; that file is TRACKED downstream. Modifying ONLY
# .claude/ (tracked-modified via attest + an untracked file) must NOT mark the
# tree dirty → the summary stays FRESH → no re-run.
setup
make_sandbox_with_mock_driver
write_summary_all_skip
attest_all                                  # rewrites .claude/phase-state.json (tracked)
echo '{}' > "$PROJ/.claude/scratch-untracked.json"   # untracked file under .claude/
# sanity: an UNSCOPED porcelain WOULD see .claude changes
unscoped=$( cd "$PROJ" && git status --porcelain 2>/dev/null )
if [ -n "$unscoped" ]; then
  pass "T-stateflip-not-dirty: unscoped tree is dirty (.claude changes present) — the interesting case"
else
  fail_ "T-stateflip-not-dirty" "fixture did not dirty .claude as intended"
fi
out=$(run_mock_gate)
calls=$(driver_call_count)
if [ "$calls" -eq 0 ]; then
  pass "T-stateflip-not-dirty: .claude-only changes do NOT trigger a re-run (calls=0)"
else
  fail_ "T-stateflip-not-dirty" "gate re-ran despite only .claude changing (calls=$calls)"
fi
if echo "$out" | grep -qE "validation scans clean"; then
  pass "T-stateflip-not-dirty: summary stays FRESH → gate reports clean"
else
  fail_ "T-stateflip-not-dirty" "gate did not stay fresh/clean; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-live-dirty-stale (Correction 2): uncommitted SOURCE edit → stale ==="
# ════════════════════════════════════════════════════════════════════
# The summary's recorded tree still equals HEAD^{tree} and it recorded
# dirty:no, but the operator edits a SOURCE file uncommitted. HEAD^{tree} does
# not reflect that — only the live scoped porcelain does. Must be stale.
setup
write_summary_all_skip                       # fresh: tree matches, dirty:no
echo "print('changed')" > "$PROJ/app.py"     # uncommitted SOURCE change (outside .claude + results)
out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$GATE" 2>&1 ) || true
if echo "$out" | grep -q "STALE"; then
  pass "T-live-dirty-stale: uncommitted source edit makes a tree-matched summary stale"
else
  fail_ "T-live-dirty-stale" "expected STALE on live-dirty tree; out:
$(echo "$out" | grep -iE 'phase 3.4|stale' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-bl082-mutation: strip # BL-082-STALENESS → T-stale-norerun-fails goes RED ==="
# ════════════════════════════════════════════════════════════════════
# MUTATION-PROOF for the staleness binding. Copy the gate, delete every line
# carrying `# BL-082-STALENESS` (the freshness decision defaults to "fresh"),
# and re-run the stale all-PASS + NOAUTORUN fixture. Real gate: STALE FAIL.
# Mutant: staleness defeated → the stale all-PASS summary is trusted CLEAN and
# NO [STALE] line appears — proving the marked line is load-bearing.
setup
_write_summary "$(proj_tree)" "no" "$ALL_PASS_ROWS"
proj_advance_tree              # stale by tree mismatch
MUT2="$TMP/mut82"
mkdir -p "$MUT2/scripts/lib"
cp "$GATE" "$MUT2/scripts/check-phase-gate.sh"
cp "$DRIVER" "$MUT2/scripts/run-phase3-validation.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT2/scripts/lib/" 2>/dev/null || true
grep -v 'BL-082-STALENESS' "$MUT2/scripts/check-phase-gate.sh" > "$MUT2/scripts/check-phase-gate.sh.tmp"
mv "$MUT2/scripts/check-phase-gate.sh.tmp" "$MUT2/scripts/check-phase-gate.sh"
chmod +x "$MUT2/scripts/check-phase-gate.sh"
if ! grep -q 'BL-082-STALENESS' "$GATE"; then
  fail_ "T-bl082-mutation" "BL-082-STALENESS marker missing from the REAL gate — nothing to mutate"
elif grep -q 'BL-082-STALENESS' "$MUT2/scripts/check-phase-gate.sh"; then
  fail_ "T-bl082-mutation" "BL-082-STALENESS still present after excision — mutation did not apply"
elif ! bash -n "$MUT2/scripts/check-phase-gate.sh" 2>/dev/null; then
  fail_ "T-bl082-mutation" "mutant gate is not syntactically valid after excision"
else
  real_out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$GATE" 2>&1 ) || true
  mut_out=$( cd "$PROJ" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash "$MUT2/scripts/check-phase-gate.sh" 2>&1 ) || true
  if echo "$real_out" | grep -q "STALE"; then
    pass "T-bl082-mutation: real gate emits the STALE FAIL"
  else
    fail_ "T-bl082-mutation" "real gate did NOT emit STALE (fixture wrong?); out:
$(echo "$real_out" | grep -iE 'stale|clean' | head)"
  fi
  if echo "$mut_out" | grep -q "STALE"; then
    fail_ "T-bl082-mutation" "mutant STILL flagged STALE — staleness not load-bearing (mutation not proof)"
  elif echo "$mut_out" | grep -qE "validation scans clean"; then
    pass "T-bl082-mutation: mutant trusts the stale all-PASS summary CLEAN (RED proof)"
  else
    fail_ "T-bl082-mutation" "mutant neither STALE nor CLEAN — unexpected; out:
$(echo "$mut_out" | grep -iE 'stale|clean|not clean' | head)"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

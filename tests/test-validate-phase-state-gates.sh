#!/usr/bin/env bash
# tests/test-validate-phase-state-gates.sh — BL-059.
#
# validate.sh's Approval Log gate-date checks previously greped
# APPROVAL_LOG.md only. The live source of truth for gate-passage
# timestamps is .claude/phase-state.json::gates.<gate>. Operators saw
# false negatives ("no date recorded") on projects whose gate was in
# phase-state.json but not (yet) mirrored to APPROVAL_LOG.md.
#
# Fix: validate.sh reads phase-state.json::gates.<gate> FIRST. If the
# JSON path is absent or malformed, it falls back to APPROVAL_LOG.md
# (back-compat). If neither has a valid date, it warns "no date
# recorded".
#
# T1 (happy path):     JSON has valid date, APPROVAL_LOG lacks header
#                      → NO "no date recorded" warning; OK line present.
# T2 (fallback):       JSON gates absent, APPROVAL_LOG has valid date
#                      → OK line (back-compat).
# T3 (both sources):   JSON has valid date + APPROVAL_LOG has valid
#                      date → JSON wins (no warn; OK line present).
# T4 (neither):        JSON gates empty + APPROVAL_LOG lacks header
#                      → "no date recorded" warning emitted.
# T5 (mutation guard): The JSON-first read helper must be present in
#                      validate.sh so that reverting the JSON path
#                      would flip T1 red.
# T6 (wired-ness):     phase_2_to_3 branch executes (fixture current_phase=3,
#                      JSON gate populated) and quotes the JSON date +
#                      "from phase-state.json" source annotation. Proves the
#                      check_gate call for phase_2_to_3 is not dead code.
# T7 (regex guard):    a malformed JSON date is REJECTED — validate.sh must
#                      fall back to APPROVAL_LOG.md rather than blindly
#                      trusting a value like "March 1, 2026". Mutation-proof
#                      against a weakened date regex.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a minimal Phase-1+ project that validate.sh will accept.
setup_project() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/reference"
  (
    cd "$PROJ"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    cat > CLAUDE.md <<'MD'
- **Project:** test
- **Platform:** cli
- **Track:** light
- **Primary Language:** typescript
MD
    cat > PROJECT_INTAKE.md <<'MD'
intake
MD
    cat > "docs/reference/builders-guide.md" <<'MD'
guide
MD
    cat > "docs/reference/user-guide.md" <<'MD'
user
MD
    cat > "docs/reference/governance-framework.md" <<'MD'
gov
MD
    cat > "docs/reference/cli-setup-addendum.md" <<'MD'
cli
MD
    touch .gitignore
    mkdir -p .github/workflows
    cat > .github/workflows/ci.yml <<'YML'
name: ci
on: push
YML
  )
}
teardown_project() { rm -rf "$TMP"; }

# --------------------------------------------------------------------
# T1: JSON gate populated, APPROVAL_LOG.md has NO Phase 0 → Phase 1
# header at all. The pre-fix behavior emitted the false-negative WARN
# from the header-scan path. Post-fix: JSON is consulted first and the
# gate is recognized without needing APPROVAL_LOG mirroring.
# --------------------------------------------------------------------
echo "T1: JSON gate set, APPROVAL_LOG lacks header → OK, no false-negative WARN"
setup_project
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"gates":{"phase_0_to_1":"2026-01-15","phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log
(no gate entries yet)
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
if echo "$out" | grep -qE "Phase 0.*1 gate.*no date"; then
  fail_ "T1" "false-negative WARN emitted despite JSON gate populated; out:
$out"
elif echo "$out" | grep -qE "Phase 0.*1 gate: dated"; then
  pass "T1: JSON gate recognized; OK line present, no false-negative WARN"
else
  fail_ "T1" "no OK line for Phase 0→1 gate when JSON had a valid date; out:
$out"
fi
teardown_project

# --------------------------------------------------------------------
# T2: JSON has no gates block (back-compat with older projects).
# APPROVAL_LOG.md has a valid dated Phase 0 → Phase 1 entry. Post-fix
# must fall through to the APPROVAL_LOG scan and emit OK.
# --------------------------------------------------------------------
echo "T2: JSON gates absent, APPROVAL_LOG dated → fallback OK"
setup_project
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log
## Phase 0 → Phase 1
- Date: 2026-01-15
- Approver: alice
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
if echo "$out" | grep -qE "Phase 0.*1 gate.*no date"; then
  fail_ "T2" "APPROVAL_LOG fallback path failed; out:
$out"
elif echo "$out" | grep -qE "Phase 0.*1 gate: dated"; then
  pass "T2: APPROVAL_LOG fallback recognized dated entry (back-compat)"
else
  fail_ "T2" "no OK line for Phase 0→1 gate under fallback path; out:
$out"
fi
teardown_project

# --------------------------------------------------------------------
# T3: Both sources populated with DIFFERENT valid dates. JSON must
# win — the OK line must reference JSON's date, not APPROVAL_LOG's.
# --------------------------------------------------------------------
echo "T3: JSON + APPROVAL_LOG both populated → JSON date wins"
setup_project
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"gates":{"phase_0_to_1":"2026-01-15","phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log
## Phase 0 → Phase 1
- Date: 2026-05-05
- Approver: bob
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
# Strict: the OK message must observably quote the JSON date so a
# future refactor that inverts precedence (APPROVAL_LOG-first) trips
# the test. Emitting JSON's date in the OK message is the observable
# precedence signal.
if echo "$out" | grep -qE "Phase 0.*1 gate.*no date"; then
  fail_ "T3" "false-negative WARN when both sources populated; out:
$out"
elif echo "$out" | grep -qE "Phase 0.*1 gate: dated.*2026-05-05"; then
  fail_ "T3" "APPROVAL_LOG date shown instead of JSON date (precedence inverted); out:
$out"
elif echo "$out" | grep -qE "Phase 0.*1 gate: dated.*2026-01-15"; then
  pass "T3: JSON date wins (2026-01-15 preferred over APPROVAL_LOG 2026-05-05)"
else
  fail_ "T3" "OK line does not quote the JSON date — precedence is silent, so a future refactor that flips priority would go undetected; out:
$out"
fi
teardown_project

# --------------------------------------------------------------------
# T4: Neither source has a valid date. WARN must fire (the operator
# needs to know the gate is unrecorded).
# --------------------------------------------------------------------
echo "T4: no JSON gate, no APPROVAL_LOG entry → WARN 'no date recorded'"
setup_project
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"gates":{"phase_0_to_1":null,"phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log
(no gate entries yet)
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
if echo "$out" | grep -qE "Phase 0.*1 gate.*no date"; then
  pass "T4: WARN fired for genuinely unrecorded gate"
else
  fail_ "T4" "expected 'no date recorded' WARN when neither source has a date; out:
$out"
fi
teardown_project

# --------------------------------------------------------------------
# T5 (mutation guard): the JSON-first helper must exist in validate.sh
# so that reverting it (deleting the JSON read call) would flip T1
# red. Anchored on the function DEFINITION at beginning-of-line, not
# on any mention of the name — a prior looser regex matched comment
# lines describing the helper, so deleting the body while leaving the
# comments alone would still pass. If the canonical helper name
# changes, update this anchor.
# --------------------------------------------------------------------
echo "T5: mutation guard — JSON gate-date read function is defined in validate.sh"
if grep -qE '^get_gate_date_from_phase_state\(\)' "$VALIDATE"; then
  pass "T5: get_gate_date_from_phase_state() function definition present in validate.sh"
else
  fail_ "T5" "no get_gate_date_from_phase_state() function definition found in validate.sh — a revert (deleting the helper) would leave T1 as the only guard, which relies on absence of a WARN line (weaker than a positive anchor)"
fi

# --------------------------------------------------------------------
# T6 (wired-ness for phase_2_to_3): T1-T5 all use current_phase=1, so
# check_gate's early-return guard `[ "$phase" -ge "$phase_min" ] || return 0`
# means the phase_1_to_2 / phase_2_to_3 / phase_3_to_4 branches are
# never exercised. Renaming the phase_2_to_3 key in the check_gate call
# would still leave T1-T5 green. T6 builds a fixture with
# current_phase=3 and populates gates.phase_2_to_3 so the branch
# actually runs; the assertion targets the OK line for the 2→3 gate
# quoting the JSON date + "from phase-state.json" source annotation.
# --------------------------------------------------------------------
echo "T6: current_phase=3 + JSON gate populated → OK line for Phase 2→3 with JSON date + source annotation"
setup_project
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":3,"gates":{"phase_0_to_1":"2026-01-15","phase_1_to_2":"2026-02-01","phase_2_to_3":"2026-03-01","phase_3_to_4":null}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log
(gates recorded in phase-state.json)
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
# The assertion has to fire specifically on the 2→3 line — with
# current_phase=3, all three of 0→1, 1→2, and 2→3 will emit OK
# lines. We anchor on the label AND the JSON date AND the source
# annotation so a mutation renaming the phase_2_to_3 key would drop
# just this line to a WARN and be caught.
if echo "$out" | grep -qE "Phase 2.*3 gate: dated entry found \(2026-03-01 from phase-state\.json\)"; then
  pass "T6: phase_2_to_3 check_gate call is wired (OK line quotes JSON date + source)"
elif echo "$out" | grep -qE "Phase 2.*3 gate.*no date"; then
  fail_ "T6" "phase_2_to_3 gate WARN'd even though JSON gate was populated — check_gate call likely mis-wired or key mismatched; out:
$out"
else
  fail_ "T6" "no OK line for Phase 2→3 gate with expected JSON date + source annotation; out:
$out"
fi
teardown_project

# --------------------------------------------------------------------
# T7 (regex guard for malformed JSON dates): validate.sh's
# get_gate_date_from_phase_state helper regex-validates the value
# before returning it, so a garbage value like "March 1, 2026" in
# gates.phase_0_to_1 should be rejected and the fallback (APPROVAL_LOG)
# should carry the gate. If the regex were weakened (e.g. to `.`), the
# malformed string would leak through and be printed as the gate date.
#
# Shape T7a (chosen): APPROVAL_LOG.md has a valid dated entry, so the
# fallback path fires and the OK line contains the "APPROVAL_LOG.md"
# source annotation. Under a mutation that weakens the regex, the
# helper would instead return "March 1, 2026" and the OK line would
# say "(March 1, 2026 from phase-state.json)" — no APPROVAL_LOG.md
# substring — so the assertion below would flip red.
# --------------------------------------------------------------------
echo "T7: malformed JSON date rejected → falls back to APPROVAL_LOG (annotation quoted)"
setup_project
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"gates":{"phase_0_to_1":"March 1, 2026","phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log
## Phase 0 → Phase 1
- Date: 2026-01-15
- Approver: alice
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
# The OK message under fallback is "$label gate: dated entry found
# (APPROVAL_LOG.md)". If the regex mutation lets the malformed value
# through, the OK line becomes "(March 1, 2026 from phase-state.json)"
# — which contains neither "APPROVAL_LOG.md" nor a well-formed date.
# We assert on the fallback annotation directly.
if echo "$out" | grep -qE "Phase 0.*1 gate: dated entry found \(APPROVAL_LOG\.md\)"; then
  pass "T7: malformed JSON date skipped; APPROVAL_LOG fallback used (source annotation present)"
elif echo "$out" | grep -qE "Phase 0.*1 gate: dated entry found \(March 1, 2026"; then
  fail_ "T7" "malformed JSON date 'March 1, 2026' was accepted as a valid gate date — regex guard is not effective; out:
$out"
elif echo "$out" | grep -qE "Phase 0.*1 gate.*no date"; then
  fail_ "T7" "expected APPROVAL_LOG fallback to carry the gate after malformed JSON was rejected, but WARN fired; out:
$out"
else
  fail_ "T7" "no OK line with (APPROVAL_LOG.md) source annotation for Phase 0→1 gate under malformed-JSON scenario; out:
$out"
fi
teardown_project

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-check-phase-gate-counter-sanitizer.sh
#
# Regression: scripts/check-phase-gate.sh used the antipattern
#   var=$(cmd_that_may_exit_nonzero || echo "0")
# where `cmd_that_may_exit_nonzero` was `grep -c` (which exits 1 on zero
# matches). When the grep exited 1 it had already printed "0\n", so the
# `||` appended a second "0" — the variable then held the two-line
# string "0\n0". Subsequent `[ "$var" -lt N ]` errored with
# "integer expression expected" and (under set -euo pipefail) the
# arithmetic test returned non-zero, sending control to the OK branch
# at five sites and silently bypassing hard gates.
#
# The most severe site was the Pre-Phase 0 organizational pre-condition
# gate (line ~203): when APPROVAL_LOG.md had the "Pre-Phase 0" section
# header but ZERO ISO dates in it, the script printed
#   [OK] Pre-Phase 0 pre-conditions recorded (0
#   0 entries)
# instead of WARNing about a missing pre-condition gate.
#
# Fix: capture into a temp var, then sanitize via the case-statement
# pattern already in scripts/process-checklist.sh:45-46
#   case "$var" in ''|*[!0-9]*) var=0 ;; esac
# so the arithmetic always sees a single non-negative integer.
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

run_gate() {
  ( cd "$PROJ" && bash "$SCRIPT" 2>&1 ) || true
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Primary site: Pre-Phase 0 organizational pre-conditions ==="
# ════════════════════════════════════════════════════════════════════

# T1: APPROVAL_LOG has the "Pre-Phase 0" section header but zero ISO
# dates in it. Pre-fix this hit the OK branch (false success). Post-fix
# the WARN branch fires.
echo "T1: Pre-Phase 0 header present, 0 dates → WARN (not [OK])"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Pre-Phase 0

(intentionally no dates here — operator forgot to fill in)
MD
out=$(run_gate)
if echo "$out" | grep -q "OK.*Pre-Phase 0 pre-conditions recorded"; then
  fail_ "T1" "still emits false [OK]; out:\n$(echo "$out" | grep Pre-Phase)"
elif echo "$out" | grep -qE "WARN.*Pre-Phase 0.*only 0 pre-condition"; then
  pass "T1: WARN fires when 0 dates recorded"
else
  fail_ "T1" "neither expected line present; out:\n$(echo "$out" | grep -i pre-phase)"
fi
teardown

# T2: APPROVAL_LOG has the section + 6 valid ISO dates. Post-fix the OK
# branch must still fire (regression guard for the happy path).
echo "T2: Pre-Phase 0 header + 6 dates → [OK]"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Pre-Phase 0

- ITSM registration recorded 2026-01-15
- SSO enrollment recorded 2026-01-16
- Centralized logging recorded 2026-01-17
- Portfolio review recorded 2026-01-18
- Budget approval recorded 2026-01-19
- Security review recorded 2026-01-20
MD
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Pre-Phase 0 pre-conditions recorded \(6 entries\)"; then
  pass "T2: [OK] fires when 6 valid dates present"
else
  fail_ "T2" "expected '[OK] ... (6 entries)'; out:\n$(echo "$out" | grep -i pre-phase)"
fi
teardown

# T3: APPROVAL_LOG missing the "Pre-Phase 0" section entirely. The
# secondary WARN branch must fire (this branch was already correct
# pre-fix; regression guard).
echo "T3: No Pre-Phase 0 section → WARN (no pre-conditions section found)"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

(section header intentionally absent)
MD
out=$(run_gate)
if echo "$out" | grep -qE "WARN.*Pre-Phase 0.*no pre-conditions section found"; then
  pass "T3: WARN fires when section absent"
else
  fail_ "T3" "expected 'no pre-conditions section found'; out:\n$(echo "$out" | grep -i pre-phase)"
fi
teardown

# T4: POC-mode org deployment — entire Pre-Phase 0 block is skipped
# (sponsored_poc and private_poc both have poc_mode set, which bypasses
# the full-org 6-precondition rule).
echo "T4: poc_mode=sponsored_poc → Pre-Phase 0 block skipped entirely"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational","poc_mode":"sponsored_poc"}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

(no Pre-Phase 0 section needed in POC mode)
MD
out=$(run_gate)
if echo "$out" | grep -qi "Pre-Phase 0"; then
  fail_ "T4" "Pre-Phase 0 block should be skipped in POC mode; out:\n$(echo "$out" | grep -i pre-phase)"
else
  pass "T4: Pre-Phase 0 block correctly skipped in POC mode"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Secondary site: PROJECT_BIBLE.md numbered sections ==="
# ════════════════════════════════════════════════════════════════════

# T5: PROJECT_BIBLE.md has zero numbered sections. The `< 14 sections`
# WARN must fire — pre-fix this took the silent OK path because
# `[ "0\n0" -lt 14 ]` failed the arithmetic test.
echo "T5: PROJECT_BIBLE.md with 0 numbered sections → WARN (< 14 sections)"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
Approved 2026-01-01

## Phase 1 → Phase 2
Approved 2026-02-01
MD
# Empty PROJECT_BIBLE.md — no headers, no placeholders.
: > "$PROJ/PROJECT_BIBLE.md"
out=$(run_gate)
if echo "$out" | grep -qE "WARN.*PROJECT_BIBLE.*has only 0 numbered sections"; then
  pass "T5: WARN fires when 0 numbered sections (was silently OK pre-fix)"
else
  fail_ "T5" "expected 'has only 0 numbered sections'; out:\n$(echo "$out" | grep -i 'project_bible\|numbered')"
fi
teardown

# T6: PROJECT_BIBLE.md with 14 numbered sections → no [WARN] about
# section count (regression guard for happy path).
echo "T6: PROJECT_BIBLE.md with 14 numbered sections → no section-count WARN"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
Approved 2026-01-01

## Phase 1 → Phase 2
Approved 2026-02-01
MD
{
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    echo "## ${i}. Section ${i}"
    echo ""
  done
} > "$PROJ/PROJECT_BIBLE.md"
out=$(run_gate)
if echo "$out" | grep -qE "WARN.*PROJECT_BIBLE.*numbered sections"; then
  fail_ "T6" "should not WARN with 14 sections; out:\n$(echo "$out" | grep -i 'numbered')"
else
  pass "T6: 14 sections → no section-count WARN (regression guard)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Defect-class verification: no 'integer expression expected' ==="
# ════════════════════════════════════════════════════════════════════

# T7: No matter what zero-match scenario, the script must NOT print
# bash's 'integer expression expected' error to stderr. Pre-fix this
# leaked on multiple sites; post-fix the sanitizer absorbs them all.
echo "T7: Zero-match scenarios do not leak 'integer expression expected'"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"organizational","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Pre-Phase 0

(no dates)

## Phase 0 → Phase 1
Approved 2026-01-01

## Phase 1 → Phase 2
Approved 2026-02-01
MD
: > "$PROJ/PROJECT_BIBLE.md"
out=$(run_gate)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T7" "bash 'integer expression expected' leaked; out:\n$(echo "$out" | grep -i integer)"
else
  pass "T7: no 'integer expression expected' leaked across multiple zero-match sites"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

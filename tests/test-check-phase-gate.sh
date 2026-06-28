#!/usr/bin/env bash
# tests/test-check-phase-gate.sh
#
# Regression tests for tier-crosscheck-7 and tier-crosscheck-13 (audit
# v2 findings, severity S3).
#
# tier-crosscheck-7 (Pre-Phase 0 named pre-conditions):
#   scripts/check-phase-gate.sh:194-218 only COUNTED dated rows in the
#   "Pre-Phase 0" section. Any 6 dated lines satisfied the gate —
#   including six unrelated rows, the same condition dated six times,
#   or even six template-default dates (none of which constitute
#   evidence that the 6 NAMED pre-conditions were actually approved).
#   The fix: in addition to counting, verify each NAMED row (AI
#   deployment path, Insurance, Liability, Sponsor, Backup maintainer,
#   ITSM) has a date in its row.
#
# tier-crosscheck-13 (Phase 3→4 organizational dual approval):
#   scripts/check-phase-gate.sh:389-395 used bare presence greps
#   (`grep -qi "Application Owner"` && `grep -qi "IT Security"`)
#   against the whole APPROVAL_LOG.md. The org template already
#   contains both literal strings as subsection headers + Role rows
#   BEFORE any approval is filled in — so the gate green-lit a
#   freshly-generated empty log. The fix: validate that each of the
#   two named approval subsections has a populated Date row matching
#   the date regex.
#
# These tests assert the NEW behavior. On main (pre-fix) the
# "should-WARN" tests fail (false [OK]); post-fix they pass.

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

# Reusable: write a Pre-Phase 0 section with a subset of named rows
# dated. Pass a list of row labels (matching the 6 named rows) that
# should receive a date; the rest get an empty Date column.
# Args: dated row labels (each a regex anchor — e.g. "AI deployment").
write_pre_phase0() {
  local approval="$PROJ/APPROVAL_LOG.md"
  {
    echo "# APPROVAL_LOG"
    echo ""
    echo "## Pre-Phase 0: Organizational Pre-Conditions"
    echo ""
    echo "| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |"
    echo "|---|---|---|---|---|---|---|---|"
    local i=0
    for row_label in \
      "AI deployment path approved" \
      "Insurance coverage confirmed" \
      "Liability entity designated" \
      "Project sponsor assigned" \
      "Backup maintainer designated" \
      "ITSM project registered" ; do
      i=$((i + 1))
      local date_cell=""
      for dated in "$@"; do
        if echo "$row_label" | grep -qi "$dated"; then
          date_cell="2026-01-1$i"
          break
        fi
      done
      echo "| $i | $row_label | Alice | Role | $date_cell | Email | REF-$i | |"
    done
  } > "$approval"
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== tier-crosscheck-7: Pre-Phase 0 named-row pre-condition gate ==="
# ════════════════════════════════════════════════════════════════════

# T1: All 6 NAMED rows dated → [OK]. Happy path regression guard.
echo "T1: All 6 named rows dated → [OK]"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational"}
JSON
write_pre_phase0 "AI deployment" "Insurance" "Liability" "sponsor" "Backup maintainer" "ITSM"
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Pre-Phase 0 pre-conditions recorded"; then
  pass "T1: [OK] fires when all 6 named rows dated"
else
  fail_ "T1" "expected [OK]; out:\n$(echo "$out" | grep -i pre-phase)"
fi
teardown

# T2: Insurance row missing a date but 6 OTHER unrelated dates present
# (placed in non-named rows or rows duplicated) → WARN. Pre-fix this
# scenario passed the count check.
echo "T2: 5 named rows dated + Insurance UNdated → WARN names missing condition"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational"}
JSON
# Insurance row is created with an empty date cell; the other 5 named
# rows receive dates.
write_pre_phase0 "AI deployment" "Liability" "sponsor" "Backup maintainer" "ITSM"
# Pad the section with 2 extra dated lines so the bare 6-count is
# satisfied — this exercises the gap: count >= 6 but Insurance still
# missing.
{
  echo ""
  echo "Operator notes — unrelated dated lines:"
  echo "- 2026-01-21 site visit"
  echo "- 2026-01-22 architecture review"
} >> "$PROJ/APPROVAL_LOG.md"
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Pre-Phase 0 pre-conditions recorded"; then
  fail_ "T2" "false [OK] — Insurance row undated should fail; out:\n$(echo "$out" | grep -i pre-phase)"
elif echo "$out" | grep -qE "WARN.*Pre-Phase 0.*[Ii]nsurance"; then
  pass "T2: WARN names the missing Insurance pre-condition"
elif echo "$out" | grep -qE "WARN.*Pre-Phase 0"; then
  pass "T2: WARN fires (missing named pre-condition detected)"
else
  fail_ "T2" "expected WARN; out:\n$(echo "$out" | grep -i pre-phase)"
fi
teardown

# T3: Sponsor + Backup maintainer rows missing dates → WARN.
echo "T3: Sponsor + Backup maintainer rows undated → WARN"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational"}
JSON
write_pre_phase0 "AI deployment" "Insurance" "Liability" "ITSM"
{
  echo ""
  echo "Operator notes:"
  echo "- 2026-01-21 site visit"
  echo "- 2026-01-22 architecture review"
} >> "$PROJ/APPROVAL_LOG.md"
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Pre-Phase 0 pre-conditions recorded"; then
  fail_ "T3" "false [OK] when Sponsor+Backup undated; out:\n$(echo "$out" | grep -i pre-phase)"
elif echo "$out" | grep -qE "WARN.*Pre-Phase 0"; then
  pass "T3: WARN fires when multiple named rows undated"
else
  fail_ "T3" "expected WARN; out:\n$(echo "$out" | grep -i pre-phase)"
fi
teardown

# T4: POC-mode org deployment — full-org named-row gate must be
# skipped (sponsored_poc / private_poc defer pre-conditions).
echo "T4: poc_mode=sponsored_poc → named-row gate skipped"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"organizational","poc_mode":"sponsored_poc"}
JSON
write_pre_phase0  # no rows dated
out=$(run_gate)
if echo "$out" | grep -qi "Pre-Phase 0"; then
  fail_ "T4" "Pre-Phase 0 block should be skipped in POC mode; out:\n$(echo "$out" | grep -i pre-phase)"
else
  pass "T4: Pre-Phase 0 named-row gate correctly skipped in POC mode"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== tier-crosscheck-13: Phase 3→4 dual-approval section gate ==="
# ════════════════════════════════════════════════════════════════════

# Helper: build a full org log with optional Application Owner /
# IT Security date populations.
# Args: $1 = app_owner_date (empty for unfilled); $2 = it_sec_date.
write_phase34_log() {
  local app_date="${1:-}"
  local sec_date="${2:-}"
  local approval="$PROJ/APPROVAL_LOG.md"
  {
    echo "# APPROVAL_LOG"
    echo ""
    echo "## Pre-Phase 0: Organizational Pre-Conditions"
    echo ""
    echo "| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |"
    echo "|---|---|---|---|---|---|---|---|"
    echo "| 1 | AI deployment path approved | Alice | IT Security | 2026-01-11 | Email | R | |"
    echo "| 2 | Insurance coverage confirmed | Alice | Broker | 2026-01-12 | Email | R | |"
    echo "| 3 | Liability entity designated | Alice | Legal | 2026-01-13 | Email | R | |"
    echo "| 4 | Project sponsor assigned | Alice | Sponsor | 2026-01-14 | Email | R | |"
    echo "| 5 | Backup maintainer designated | Alice | Tech Lead | 2026-01-15 | Email | R | |"
    echo "| 6 | ITSM project registered | Alice | PMO | 2026-01-16 | Email | R | |"
    echo ""
    echo "## Phase Gate: Phase 0 → Phase 1"
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| **Gate** | Phase 0 → Phase 1 |"
    echo "| **Approver** | Bob |"
    echo "| **Date** | 2026-02-01 |"
    echo ""
    echo "## Phase Gate: Phase 1 → Phase 2"
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| **Gate** | Phase 1 → Phase 2 |"
    echo "| **Approver** | Bob |"
    echo "| **Date** | 2026-03-01 |"
    echo ""
    echo "## Phase Gate: Phase 2 → Phase 3"
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| **Gate** | Phase 2 → Phase 3 |"
    echo "| **Approver** | Bob |"
    echo "| **Date** | 2026-04-01 |"
    echo ""
    echo "## Phase Gate: Phase 3 → Phase 4"
    echo ""
    echo "### Application Owner Approval"
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| **Gate** | Phase 3 → Phase 4 (Application Owner) |"
    echo "| **Approver** | Carol |"
    echo "| **Role** | Application Owner |"
    echo "| **Date** | $app_date |"
    echo ""
    echo "### IT Security Approval"
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| **Gate** | Phase 3 → Phase 4 (IT Security) |"
    echo "| **Approver** | Dave |"
    echo "| **Role** | IT Security |"
    echo "| **Date** | $sec_date |"
  } > "$approval"
}

write_phase34_state() {
  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":4,"deployment":"organizational","gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-03-01","phase_2_to_3":"2026-04-01","phase_3_to_4":"2026-05-01"}}
JSON
}

# T5: BOTH Application Owner AND IT Security have populated Date rows
# → [OK]. Happy path regression guard.
echo "T5: Both App Owner + IT Security Date populated → [OK]"
setup
write_phase34_state
write_phase34_log "2026-05-01" "2026-05-02"
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Phase 3→4.*both Application Owner and IT Security"; then
  pass "T5: [OK] fires when both Dates populated"
else
  fail_ "T5" "expected [OK]; out:\n$(echo "$out" | grep -E 'Phase 3|App.*Owner|IT Security')"
fi
teardown

# T6: Application Owner Date EMPTY, IT Security populated → WARN.
# Pre-fix this passed because the strings "Application Owner" and
# "IT Security" appear verbatim in the template headers/Role rows.
echo "T6: App Owner Date EMPTY (IT Security dated) → WARN (not false [OK])"
setup
write_phase34_state
write_phase34_log "" "2026-05-02"
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Phase 3→4.*Application Owner and IT Security"; then
  fail_ "T6" "false [OK] — App Owner Date is empty; out:\n$(echo "$out" | grep -E 'Application Owner|IT Security')"
elif echo "$out" | grep -qE "WARN.*Application Owner"; then
  pass "T6: WARN fires when App Owner Date is empty"
else
  fail_ "T6" "expected WARN naming Application Owner; out:\n$(echo "$out" | grep -E 'Application Owner|IT Security')"
fi
teardown

# T7: Both Dates EMPTY (freshly-generated org template) → WARN.
# This was the canonical false-pass scenario in the audit.
echo "T7: Both Dates EMPTY (template defaults) → WARN (not false [OK])"
setup
write_phase34_state
write_phase34_log "" ""
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Phase 3→4.*Application Owner and IT Security"; then
  fail_ "T7" "false [OK] on freshly-generated org template; out:\n$(echo "$out" | grep -E 'Application Owner|IT Security')"
elif echo "$out" | grep -qE "WARN.*Application Owner.*IT Security|WARN.*Application Owner|WARN.*IT Security"; then
  pass "T7: WARN fires on empty template defaults"
else
  fail_ "T7" "expected WARN naming missing approver(s); out:\n$(echo "$out" | grep -E 'Application Owner|IT Security')"
fi
teardown

# T8: Personal deployment at Phase 4 → the dual-approval check should
# not fire (it's organizational-scoped).
echo "T8: Personal deployment → dual-approval check does not fire"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":4,"deployment":"personal","gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-03-01","phase_2_to_3":"2026-04-01","phase_3_to_4":"2026-05-01"}}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase Gate: Phase 0 → Phase 1
Approved 2026-02-01

## Phase Gate: Phase 1 → Phase 2
Approved 2026-03-01

## Phase Gate: Phase 2 → Phase 3
Approved 2026-04-01

## Phase Gate: Phase 3 → Phase 4
Approved 2026-05-01
MD
out=$(run_gate)
if echo "$out" | grep -qE "(OK|WARN).*Phase 3→4.*both Application Owner and IT Security"; then
  fail_ "T8" "dual-approval check should be org-only; out:\n$(echo "$out" | grep -E 'Phase 3|App.*Owner|IT Security')"
else
  pass "T8: dual-approval check correctly skipped for personal deployment"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

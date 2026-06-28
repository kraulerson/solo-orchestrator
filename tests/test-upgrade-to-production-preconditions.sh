#!/usr/bin/env bash
# tests/test-upgrade-to-production-preconditions.sh
#
# Audit code-upgrade-project-8 regression test. Verifies that
# scripts/upgrade-project.sh --to-production refuses to advance a
# POC project to Production unless the deferred Pre-Phase-0
# pre-conditions in APPROVAL_LOG.md are dated (or an operator
# acknowledges them via --ack-preconditions in non-interactive mode).
#
# Canonical pre-condition split per docs/governance-framework.md:230 —
# Sponsored POC defers 3 of 6 governance items (insurance, liability,
# ITSM, backup maintainer; sponsor/AI-path/exit-criteria upfront).
# Private POC defers all 6. Production requires all 6 cleared. Personal
# deployments auto-fill the 6 rows via templates/generated/
# approval-log-personal.tmpl and are exempt from the gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Fixture helpers ────────────────────────────────────────────────

# setup_org_sponsored <approval_row_count>
# Creates a tmpdir with an organizational/sponsored_poc project. Seeds
# APPROVAL_LOG.md with the canonical Pre-Phase-0 6-row table; the first
# <approval_row_count> rows have ISO dates (others left blank).
setup_org_sponsored() {
  local dated_rows="$1"
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email t@t.local
    git config user.name "Test User"
    git remote add origin https://github.com/example/foo.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"organizational","host":"github","deployment":"organizational","poc_mode":"sponsored_poc","enforcement_level":"strict"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc","current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"standard","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc"}
JSON
  )
  _write_approval_log_org "$TMPDIR_T/APPROVAL_LOG.md" "$dated_rows"
  ( cd "$TMPDIR_T" && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

# setup_personal_private <approval_row_count>
# Personal/private_poc project. APPROVAL_LOG mirrors the personal
# template (rows are N/A with a date).
setup_personal_private() {
  local dated_rows="$1"
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email t@t.local
    git config user.name "Test User"
    git remote add origin https://github.com/example/foo.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"github","deployment":"personal","poc_mode":"private_poc","enforcement_level":"strict"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"standard","deployment":"personal","poc_mode":"private_poc","current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"standard","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"standard","deployment":"personal","poc_mode":"private_poc"}
JSON
  )
  _write_approval_log_personal "$TMPDIR_T/APPROVAL_LOG.md" "$dated_rows"
  ( cd "$TMPDIR_T" && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

_write_approval_log_org() {
  local path="$1" dated_rows="$2"
  local d="2026-06-27"
  declare -a labels=(
    "AI deployment path approved"
    "Insurance coverage confirmed"
    "Liability entity designated"
    "Project sponsor assigned"
    "Backup maintainer designated"
    "ITSM project registered"
  )
  {
    cat <<'HDR'
---
project: test
deployment: organizational
created: 2026-06-27
framework: Solo Orchestrator v1.0
---

# Approval Log — test

## Pre-Phase 0: Organizational Pre-Conditions

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
HDR
    local i
    for i in 1 2 3 4 5 6; do
      local idx=$((i - 1))
      local label="${labels[$idx]}"
      if [ "$i" -le "$dated_rows" ]; then
        printf '| %d | %s | Jane Approver | IT Security | %s | Email | TICKET-%d | |\n' "$i" "$label" "$d" "$i"
      else
        printf '| %d | %s | | IT Security | | Email / Ticket / Document | | |\n' "$i" "$label"
      fi
    done
    echo
    echo "## Approval History"
    echo
    echo "| Date | Gate / Event | Decision | Notes |"
    echo "|---|---|---|---|"
    echo "| | | | |"
  } > "$path"
}

_write_approval_log_personal() {
  local path="$1" dated_rows="$2"
  local d="2026-06-27"
  declare -a labels=(
    "AI deployment path"
    "Insurance coverage"
    "Liability entity"
    "Project sponsor"
    "Backup maintainer"
    "ITSM registration"
  )
  {
    cat <<'HDR'
---
project: test
deployment: personal
created: 2026-06-27
framework: Solo Orchestrator v1.0
---

# Approval Log — test

## Pre-Phase 0: Pre-Conditions

| # | Pre-Condition | Status | Date | Notes |
|---|---|---|---|---|
HDR
    local i
    for i in 1 2 3 4 5 6; do
      local idx=$((i - 1))
      local label="${labels[$idx]}"
      if [ "$i" -le "$dated_rows" ]; then
        printf '| %d | %s | N/A — personal project | %s | |\n' "$i" "$label" "$d"
      else
        printf '| %d | %s | | | |\n' "$i" "$label"
      fi
    done
    echo
    echo "## Approval History"
    echo
    echo "| Date | Gate / Event | Decision | Notes |"
    echo "|---|---|---|---|"
    echo "| | | | |"
  } > "$path"
}

teardown_project() { rm -rf "$TMPDIR_T"; }

# ── Tests ──────────────────────────────────────────────────────────

# T1: org/sponsored_poc, 0 dated rows → exits non-zero, names all 6 missing.
t1_org_zero_rows_refused() {
  setup_org_sponsored 0
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null 2>&1) || rc=$?
  if [ "$rc" = "0" ]; then
    fail_ "T1" "expected non-zero exit when APPROVAL_LOG has 0 dated rows; rc=$rc"
    teardown_project; return
  fi
  # Failure message must enumerate at least one missing row by number.
  if ! echo "$out" | grep -qE 'row[s]?[^a-zA-Z0-9]*(1|2|3|4|5|6)'; then
    fail_ "T1" "failure message did not enumerate missing rows by number; out:\n$out"
    teardown_project; return
  fi
  # phase-state.json must NOT have been mutated.
  local pm; pm=$(jq -r '.poc_mode // empty' "$TMPDIR_T/.claude/phase-state.json")
  if [ "$pm" != "sponsored_poc" ]; then
    fail_ "T1" "phase-state.json poc_mode mutated despite failed gate (now '$pm', expected 'sponsored_poc')"
    teardown_project; return
  fi
  pass "T1: org/sponsored_poc with 0 dated rows refuses --to-production"
  teardown_project
}

# T2: org/sponsored_poc, all 6 dated rows → exits 0, poc_mode cleared.
t2_org_six_rows_accepted() {
  setup_org_sponsored 6
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null 2>&1) || rc=$?
  if [ "$rc" != "0" ]; then
    fail_ "T2" "expected rc=0 with 6 dated rows; rc=$rc out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  local pm; pm=$(jq -r '.poc_mode // "null"' "$TMPDIR_T/.claude/phase-state.json")
  if [ "$pm" != "null" ] && [ -n "$pm" ]; then
    fail_ "T2" "poc_mode not cleared after successful upgrade; pm='$pm'"
    teardown_project; return
  fi
  pass "T2: org/sponsored_poc with 6 dated rows accepts --to-production"
  teardown_project
}

# T3: org/sponsored_poc, 3 dated rows (upfront), 3 missing → refused, names rows 4,5,6.
t3_org_three_dated_three_missing() {
  setup_org_sponsored 3
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null 2>&1) || rc=$?
  if [ "$rc" = "0" ]; then
    fail_ "T3" "expected non-zero exit when rows 4-6 are blank; rc=$rc"
    teardown_project; return
  fi
  # Must enumerate the missing rows by number AND must NOT enumerate
  # the satisfied upfront ones (1,2,3) as missing.
  if ! echo "$out" | grep -qE 'missing_rows=\[[^]]*4[^]]*5[^]]*6\]'; then
    fail_ "T3" "failure message did not list rows 4,5,6 as missing; out:\n$out"
    teardown_project; return
  fi
  if echo "$out" | grep -qE 'missing_rows=\[[^]]*(1|2|3)[^]]*\]' | grep -v '4\|5\|6' >/dev/null 2>&1; then
    : # benign; below check is the real guard
  fi
  # Confirm the satisfied rows are NOT in the missing list.
  _missing_inner=$(echo "$out" | sed -n 's/.*missing_rows=\[\([^]]*\)\].*/\1/p' | head -1)
  for satisfied in 1 2 3; do
    if echo ",$_missing_inner," | grep -q ",$satisfied,"; then
      fail_ "T3" "row $satisfied was dated but reported missing; missing_rows=[$_missing_inner]"
      teardown_project; return
    fi
  done
  pass "T3: org/sponsored_poc with rows 1-3 dated, 4-6 blank refuses + names 4/5/6"
  teardown_project
}

# T4: org/sponsored_poc, 0 dated rows BUT --ack-preconditions=1,2,3,4,5,6 → accepted, audit row written.
t4_ack_preconditions_bypass() {
  setup_org_sponsored 0
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive --ack-preconditions=1,2,3,4,5,6 </dev/null 2>&1) || rc=$?
  if [ "$rc" != "0" ]; then
    fail_ "T4" "expected rc=0 with --ack-preconditions covering all 6 rows; rc=$rc out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  local audit="$TMPDIR_T/.claude/bypass-audit.json"
  if [ ! -f "$audit" ]; then
    fail_ "T4" "bypass-audit.json not created"
    teardown_project; return
  fi
  local ack_rows
  ack_rows=$(jq -r '[.[] | select(.details.action == "to_production_preconditions_acked")] | length' "$audit" 2>/dev/null || echo 0)
  if [ "$ack_rows" -lt 1 ]; then
    fail_ "T4" "bypass-audit.json has no to_production_preconditions_acked row; audit:\n$(cat "$audit")"
    teardown_project; return
  fi
  local actor
  actor=$(jq -r '[.[] | select(.details.action == "to_production_preconditions_acked")][0].actor' "$audit")
  if [ "$actor" != "user_terminal" ]; then
    fail_ "T4" "ack-preconditions audit row has actor='$actor', expected 'user_terminal'"
    teardown_project; return
  fi
  pass "T4: --ack-preconditions=1..6 bypasses gate + writes user_terminal audit row"
  teardown_project
}

# T5: personal/private_poc → --to-production accepted (template auto-fills 6 rows).
t5_personal_private_poc_exempt() {
  setup_personal_private 6
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null 2>&1) || rc=$?
  if [ "$rc" != "0" ]; then
    fail_ "T5" "expected rc=0 for personal/private_poc upgrade; rc=$rc out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  local pm; pm=$(jq -r '.poc_mode // "null"' "$TMPDIR_T/.claude/phase-state.json")
  if [ "$pm" != "null" ] && [ -n "$pm" ]; then
    fail_ "T5" "poc_mode not cleared on personal upgrade; pm='$pm'"
    teardown_project; return
  fi
  pass "T5: personal/private_poc upgrades without gate friction (template pre-fills)"
  teardown_project
}

# T6: failure message includes literal Pre-Condition row labels.
t6_failure_message_includes_labels() {
  setup_org_sponsored 0
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null 2>&1) || rc=$?
  if [ "$rc" = "0" ]; then
    fail_ "T6" "expected non-zero exit"
    teardown_project; return
  fi
  # Spot-check: at least two labels from the canonical table must appear.
  local hits=0
  for label in "Insurance" "Liability" "Backup maintainer" "ITSM"; do
    if echo "$out" | grep -qi "$label"; then hits=$((hits + 1)); fi
  done
  if [ "$hits" -lt 2 ]; then
    fail_ "T6" "failure message lacks Pre-Condition labels (got $hits hits); out:\n$out"
    teardown_project; return
  fi
  pass "T6: failure message names Pre-Condition rows by label"
  teardown_project
}

echo "== tests/test-upgrade-to-production-preconditions.sh =="
t1_org_zero_rows_refused
t2_org_six_rows_accepted
t3_org_three_dated_three_missing
t4_ack_preconditions_bypass
t5_personal_private_poc_exempt
t6_failure_message_includes_labels

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

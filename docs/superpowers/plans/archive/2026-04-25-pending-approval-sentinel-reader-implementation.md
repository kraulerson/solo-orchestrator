# BL-015: Pending-Approval Sentinel Reader — Implementation Plan

> **Archived 2026-07-05 (BL-049):** Shipped via PR #16 (`feat/bl-015-pending-approval-sentinel-reader`, merged 2026-04-25). See `docs/superpowers/plans/archive/README.md` for the archive convention.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Solo's read-side complement to CDF 4.2.3's pending-approval sentinel: a new `scripts/pending-approval.sh` helper agents use to write/manage `.claude/pending-approval.json`, plus a `pa_check()` block in `pre-commit-gate.sh` that denies `git commit` and `gh pr create` while the sentinel is present.

**Architecture:** Helper-first. The helper owns the JSON schema (validates at write time, writes atomically). The reader is a thin consumer that checks file existence and produces a rich deny reason. Both conform to the contract CDF 4.2.3 owns.

**Tech Stack:** Bash 4+, `jq`, `mktemp`, `mv`. No new runtime dependencies — all already required by other Solo scripts.

**Spec reference:** `docs/superpowers/specs/2026-04-25-pending-approval-sentinel-reader-design.md`

**Branching:** Execute on a feature branch `feat/bl-015-pending-approval-sentinel-reader` off `main`. Final PR targets `main`. The plan document itself commits to `main` first (documentation lives on `main`; implementation lives on the branch).

**Execution preamble (run once before Task 1):**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
git checkout main
git pull --ff-only origin main
git checkout -b feat/bl-015-pending-approval-sentinel-reader
scripts/process-checklist.sh --start-feature "bl-015-pending-approval-sentinel-reader"
```

---

## File Structure

**Created files:**
- `scripts/pending-approval.sh` — helper script, ~150 lines. 5 subcommands + `--help`.
- `tests/test-pending-approval.sh` — 17 unit tests (P1–P17).

**Modified files:**
- `scripts/pre-commit-gate.sh` — insert `pa_check()` + two reason builders between line 72 (`--no-verify` block end) and line 74 (`--amend` warn block start). Expected delta: +~80 lines.
- `tests/edge-cases-scripts.sh` — append new section with E40–E47 (8 integration tests). Expected delta: +~150 lines.
- `templates/generated/claude-md.tmpl` — add one bullet to Construction Rules.
- `docs/builders-guide.md` — add new `### Structured Decision Points` subsection between "MVP Cutline Work Requires the Build Loop" and "The Build Loop."
- `scripts/upgrade-project.sh` — add one entry to the existing changelog block in the header.

**Responsibilities:**
- `scripts/pending-approval.sh` knows the JSON schema, writes atomically, validates at write time, refuses double-offer.
- `scripts/pre-commit-gate.sh` (`pa_check` block) reads file existence; parses for display only; falls back gracefully on malformed JSON.
- Templates/docs/upgrade-script changes are advisory; no behavior depends on them.

---

## Task 1: Helper script + 17 unit tests

**Goal:** Build the entire helper script with all 5 subcommands, then verify with 17 unit tests covering the contract from spec §6 and §10.

**Files:**
- Create: `scripts/pending-approval.sh`
- Create: `tests/test-pending-approval.sh`

- [ ] **Step 1.1: Create the test file with all 17 failing test cases**

Create `tests/test-pending-approval.sh`:

```bash
#!/usr/bin/env bash
# tests/test-pending-approval.sh — unit tests for scripts/pending-approval.sh (BL-015).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/pending-approval.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# --- Helpers: per-test tempdir with .claude/ ---

setup_project() {
  TMPDIR_T=$(mktemp -d)
  mkdir -p "$TMPDIR_T/.claude"
}

teardown_project() {
  rm -rf "$TMPDIR_T"
}

run_in_project() {
  # Run the helper from the tempdir. Echoes "EXIT|STDOUT|STDERR" (each piped to one line).
  local out err rc=0
  err=$( cd "$TMPDIR_T" && "$SCRIPT" "$@" 2>&1 >"$TMPDIR_T/_stdout" ) || rc=$?
  out=$(cat "$TMPDIR_T/_stdout" 2>/dev/null | tr '\n' ' ')
  err=$(printf '%s' "$err" | tr '\n' ' ')
  rm -f "$TMPDIR_T/_stdout"
  echo "$rc|$out|$err"
}

write_sentinel_raw() {
  # $1 = JSON content
  printf '%s' "$1" > "$TMPDIR_T/.claude/pending-approval.json"
}

# --- Tests ---

p1_offer_fresh_project() {
  setup_project
  local out; out=$(run_in_project --offer "commit structure" --options "A1: single" "A2: two" "A3: three" --recommendation "A1")
  local rc=${out%%|*}
  [ "$rc" = "0" ] || { fail_ "P1" "expected exit 0, got: $out"; teardown_project; return; }
  [ -f "$TMPDIR_T/.claude/pending-approval.json" ] || { fail_ "P1" "sentinel not created"; teardown_project; return; }
  # Schema sanity: 4 fields present
  local q opts rec at
  q=$(jq -r '.question' "$TMPDIR_T/.claude/pending-approval.json")
  opts=$(jq -r '.options | length' "$TMPDIR_T/.claude/pending-approval.json")
  rec=$(jq -r '.recommendation' "$TMPDIR_T/.claude/pending-approval.json")
  at=$(jq -r '.offered_at' "$TMPDIR_T/.claude/pending-approval.json")
  [ "$q" = "commit structure" ] && [ "$opts" = "3" ] && [ "$rec" = "A1" ] && [ -n "$at" ] || { fail_ "P1" "schema mismatch: q='$q' opts=$opts rec='$rec' at='$at'"; teardown_project; return; }
  # No leftover .tmp files
  ls "$TMPDIR_T/.claude/"*.tmp 2>/dev/null && { fail_ "P1" "tempfile not cleaned up"; teardown_project; return; }
  pass "P1: --offer in fresh project — sentinel created with valid schema, atomic"
  teardown_project
}

p2_double_offer_refused() {
  setup_project
  run_in_project --offer "first" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --offer "second" --options "B1: x" "B2: y" --recommendation "B1")
  local rc=${out%%|*}
  [ "$rc" = "1" ] || { fail_ "P2" "expected exit 1, got: $out"; teardown_project; return; }
  [[ "$out" == *"first"* ]] || { fail_ "P2" "stderr should mention existing question 'first', got: $out"; teardown_project; return; }
  # Sentinel unchanged: still says "first"
  local q; q=$(jq -r '.question' "$TMPDIR_T/.claude/pending-approval.json")
  [ "$q" = "first" ] || { fail_ "P2" "sentinel was overwritten: q='$q'"; teardown_project; return; }
  pass "P2: double --offer refused, original sentinel preserved"
  teardown_project
}

p3_offer_empty_question() {
  setup_project
  local out; out=$(run_in_project --offer "" --options "A1: foo" "A2: bar" --recommendation "A1")
  [ "${out%%|*}" = "1" ] || { fail_ "P3" "expected exit 1 for empty question, got: $out"; teardown_project; return; }
  pass "P3: --offer with empty --question — exit 1"
  teardown_project
}

p4_offer_single_option() {
  setup_project
  local out; out=$(run_in_project --offer "Q" --options "A1: only" --recommendation "A1")
  [ "${out%%|*}" = "1" ] || { fail_ "P4" "expected exit 1 for single option, got: $out"; teardown_project; return; }
  [[ "$out" == *"2 options"* ]] || { fail_ "P4" "stderr should mention 'minimum 2 options', got: $out"; teardown_project; return; }
  pass "P4: --offer with single option — exit 1 + 'minimum 2 options' message"
  teardown_project
}

p5_offer_recommendation_mismatch() {
  setup_project
  local out; out=$(run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "Z9")
  [ "${out%%|*}" = "1" ] || { fail_ "P5" "expected exit 1 for unknown recommendation, got: $out"; teardown_project; return; }
  pass "P5: --offer with --recommendation not matching any option — exit 1"
  teardown_project
}

p6_offer_outside_project() {
  TMPDIR_T=$(mktemp -d)  # no .claude/
  local out rc=0
  out=$( cd "$TMPDIR_T" && "$SCRIPT" --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || { fail_ "P6" "expected exit 1 outside project, got rc=$rc out=$out"; teardown_project; return; }
  [[ "$out" == *"not in"*"Solo project"* || "$out" == *"no .claude"* ]] || { fail_ "P6" "stderr should mention 'not in a Solo project', got: $out"; teardown_project; return; }
  pass "P6: --offer outside a project — exit 1 + 'not in a Solo project' message"
  teardown_project
}

p7_resolve_present() {
  setup_project
  run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --resolve)
  [ "${out%%|*}" = "0" ] || { fail_ "P7" "expected exit 0, got: $out"; teardown_project; return; }
  [ ! -f "$TMPDIR_T/.claude/pending-approval.json" ] || { fail_ "P7" "sentinel not deleted"; teardown_project; return; }
  [[ "$out" == *"resolved"* ]] || { fail_ "P7" "stdout should mention 'resolved', got: $out"; teardown_project; return; }
  pass "P7: --resolve when sentinel present — exit 0, deleted, OK message"
  teardown_project
}

p8_resolve_absent_idempotent() {
  setup_project
  local out; out=$(run_in_project --resolve)
  [ "${out%%|*}" = "0" ] || { fail_ "P8" "expected exit 0, got: $out"; teardown_project; return; }
  [[ "$out" == *"No pending approval"* ]] || { fail_ "P8" "stdout should mention 'No pending approval', got: $out"; teardown_project; return; }
  pass "P8: --resolve when sentinel absent — exit 0, idempotent"
  teardown_project
}

p9_clear_present() {
  setup_project
  run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --clear)
  [ "${out%%|*}" = "0" ] || { fail_ "P9" "expected exit 0, got: $out"; teardown_project; return; }
  [ ! -f "$TMPDIR_T/.claude/pending-approval.json" ] || { fail_ "P9" "sentinel not deleted by --clear"; teardown_project; return; }
  [[ "$out" == *"cleared"* ]] || { fail_ "P9" "stdout should mention 'cleared (abort)', got: $out"; teardown_project; return; }
  pass "P9: --clear when sentinel present — exit 0, deleted, abort message"
  teardown_project
}

p10_status_present_valid() {
  setup_project
  run_in_project --offer "commit structure" --options "A1: single" "A2: two" "A3: three" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --status)
  [ "${out%%|*}" = "0" ] || { fail_ "P10" "expected exit 0, got: $out"; teardown_project; return; }
  [[ "$out" == *"commit structure"* ]] || { fail_ "P10" "stdout should reflect question, got: $out"; teardown_project; return; }
  [[ "$out" == *"A1: single"* ]] || { fail_ "P10" "stdout should reflect options, got: $out"; teardown_project; return; }
  [[ "$out" == *"A1"* ]] || { fail_ "P10" "stdout should reflect recommendation, got: $out"; teardown_project; return; }
  pass "P10: --status with valid sentinel — exit 0 + formatted summary"
  teardown_project
}

p11_status_absent() {
  setup_project
  local out; out=$(run_in_project --status)
  [ "${out%%|*}" = "0" ] || { fail_ "P11" "expected exit 0, got: $out"; teardown_project; return; }
  [[ "$out" == *"No pending approval"* ]] || { fail_ "P11" "stdout should mention 'No pending approval', got: $out"; teardown_project; return; }
  pass "P11: --status when sentinel absent — exit 0, no-pending message"
  teardown_project
}

p12_status_malformed() {
  setup_project
  write_sentinel_raw '{"question": "incomplete"'  # truncated JSON
  local out; out=$(run_in_project --status)
  [ "${out%%|*}" = "0" ] || { fail_ "P12" "expected exit 0 even on malformed, got: $out"; teardown_project; return; }
  [[ "$out" == *"malformed"* ]] || { fail_ "P12" "stdout should mention 'malformed', got: $out"; teardown_project; return; }
  pass "P12: --status with malformed sentinel — exit 0 + 'malformed' message"
  teardown_project
}

p13_validate_absent() {
  setup_project
  local out; out=$(run_in_project --validate)
  [ "${out%%|*}" = "0" ] || { fail_ "P13" "expected exit 0 for absent file, got: $out"; teardown_project; return; }
  [[ "$out" == *"No sentinel to validate"* ]] || { fail_ "P13" "stdout should mention 'No sentinel to validate', got: $out"; teardown_project; return; }
  pass "P13: --validate on absent file — exit 0"
  teardown_project
}

p14_validate_valid() {
  setup_project
  run_in_project --offer "Q" --options "A1: foo" "A2: bar" --recommendation "A1" >/dev/null
  local out; out=$(run_in_project --validate)
  [ "${out%%|*}" = "0" ] || { fail_ "P14" "expected exit 0 for valid sentinel, got: $out"; teardown_project; return; }
  [[ "$out" == *"Valid sentinel"* ]] || { fail_ "P14" "stdout should mention 'Valid sentinel', got: $out"; teardown_project; return; }
  pass "P14: --validate on valid sentinel — exit 0"
  teardown_project
}

p15_validate_malformed() {
  setup_project
  write_sentinel_raw '{"question": "incomplete"'
  local out; out=$(run_in_project --validate)
  [ "${out%%|*}" = "1" ] || { fail_ "P15" "expected exit 1 for malformed sentinel, got: $out"; teardown_project; return; }
  pass "P15: --validate on malformed sentinel — exit 1"
  teardown_project
}

p16_help() {
  setup_project
  local out; out=$(run_in_project --help)
  [ "${out%%|*}" = "0" ] || { fail_ "P16" "expected exit 0 for --help, got: $out"; teardown_project; return; }
  [[ "$out" == *"--offer"* ]] && [[ "$out" == *"--resolve"* ]] && [[ "$out" == *"--status"* ]] || { fail_ "P16" "help should list subcommands, got: $out"; teardown_project; return; }
  pass "P16: --help — exit 0 + subcommand listing"
  teardown_project
}

p17_atomic_write_code_shape() {
  # Code-shape test: helper script must use mktemp + mv (atomic write).
  # This is a regression guard against future refactors that introduce
  # non-atomic `> "$sentinel"` writes.
  if grep -qE 'mktemp.*\.tmp' "$SCRIPT" && grep -qE 'mv .*\.tmp.* .*pending-approval\.json' "$SCRIPT"; then
    if ! grep -qE '^[[:space:]]*[^#]*>[[:space:]]*"?\$?\{?[A-Za-z_]*PROJECT[A-Za-z_]*\}?/?\.claude/pending-approval\.json"?[[:space:]]*$' "$SCRIPT"; then
      pass "P17: helper uses atomic write (mktemp + mv); no direct '> sentinel' patterns"
    else
      fail_ "P17" "found direct '> sentinel' write — non-atomic, race-prone"
    fi
  else
    fail_ "P17" "helper missing mktemp + mv pattern (non-atomic write or different scheme)"
  fi
}

# --- Run all ---
echo "== tests/test-pending-approval.sh =="
p1_offer_fresh_project
p2_double_offer_refused
p3_offer_empty_question
p4_offer_single_option
p5_offer_recommendation_mismatch
p6_offer_outside_project
p7_resolve_present
p8_resolve_absent_idempotent
p9_clear_present
p10_status_present_valid
p11_status_absent
p12_status_malformed
p13_validate_absent
p14_validate_valid
p15_validate_malformed
p16_help
p17_atomic_write_code_shape

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
```

Make it executable:

```bash
chmod +x tests/test-pending-approval.sh
```

- [ ] **Step 1.2: Run the test file to confirm it fails (script does not yet exist)**

```bash
bash tests/test-pending-approval.sh
```

Expected: `bash: ... pending-approval.sh: No such file or directory` errors throughout. Test file's `[ "${out%%|*}" = "0" ]` checks should fail since rc will be 127 (file-not-found) instead of 0. Most cases fail; that's correct.

- [ ] **Step 1.3: Create `scripts/pending-approval.sh` with full implementation**

Create the file:

```bash
#!/usr/bin/env bash
# scripts/pending-approval.sh — Solo Orchestrator pending-approval sentinel helper (BL-015)
#
# Writes / reads / validates .claude/pending-approval.json to coordinate
# blocking user decisions across the CDF stop-hook (4.2.3+) and Solo's
# pre-commit-gate. See docs/builders-guide.md § "Structured Decision Points".
#
# Schema (CDF 4.2.3 contract):
#   {
#     "question": "string (non-empty)",
#     "options": ["A1: foo", "A2: bar", ...],          # ≥2 entries
#     "recommendation": "A1",                          # leading id of one option
#     "offered_at": "2026-04-25T12:00:00Z"             # ISO-8601 UTC
#   }
#
# Existence alone signals "user is deciding" — both consumers honor file
# presence regardless of validity. Malformed files are not auto-cleaned;
# `rm` manually or use `--clear`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helpers if available (for print_ok/print_fail/print_info colored output).
# Fallback: define minimal shims so the script still works when sourced from non-Solo trees.
if [ -f "$SCRIPT_DIR/lib/helpers.sh" ]; then
  source "$SCRIPT_DIR/lib/helpers.sh"
else
  print_ok()   { echo "[OK] $1"; }
  print_fail() { echo "[FAIL] $1" >&2; }
  print_info() { echo "[INFO] $1"; }
fi

# --- Helpers ---

find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -d "$dir/.claude" ] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

iso_timestamp_utc() {
  # macOS BSD date and Linux GNU date emit different output for ISO format.
  # Normalize: always produce "YYYY-MM-DDTHH:MM:SSZ".
  if date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
    return 0
  fi
  # Fallback for very old date implementations.
  date -u "+%Y-%m-%dT%H:%M:%SZ"
}

leading_id() {
  # Extract the leading identifier from an option string ("A1: foo" -> "A1").
  # If no colon, return the whole string.
  local s="$1"
  if [[ "$s" == *:* ]]; then
    echo "${s%%:*}"
  else
    echo "$s"
  fi
}

sentinel_path() {
  # Echoes the absolute path to the sentinel given a project root.
  echo "$1/.claude/pending-approval.json"
}

# --- Subcommand: --offer ---

cmd_offer() {
  local question="" recommendation=""
  local -a options=()

  # Manual arg parser. --options consumes positional args until next flag or end.
  while [ $# -gt 0 ]; do
    case "$1" in
      --question)        question="$2"; shift 2 ;;
      --recommendation)  recommendation="$2"; shift 2 ;;
      --options)
        shift
        while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
          options+=("$1")
          shift
        done
        ;;
      *)
        # First positional after --offer is the question (legacy/short form).
        if [ -z "$question" ] && [[ "$1" != --* ]]; then
          question="$1"; shift
        else
          print_fail "Unknown argument: $1"
          return 1
        fi
        ;;
    esac
  done

  # Validate inputs.
  if [ -z "$question" ]; then
    print_fail "--offer requires a non-empty question (positional arg or --question)."
    return 1
  fi
  if [ "${#options[@]}" -lt 2 ]; then
    print_fail "--offer requires at least 2 options via --options."
    return 1
  fi
  if [ -z "$recommendation" ]; then
    print_fail "--offer requires --recommendation."
    return 1
  fi
  # Recommendation must match the leading id of one option.
  local match=false
  local opt id
  for opt in "${options[@]}"; do
    id=$(leading_id "$opt")
    if [ "$id" = "$recommendation" ]; then
      match=true
      break
    fi
  done
  if [ "$match" = false ]; then
    print_fail "--recommendation '$recommendation' does not match the leading id of any option."
    print_fail "Options: ${options[*]}"
    return 1
  fi

  # Locate project.
  local project_root
  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")

  # Refuse double-offer.
  if [ -f "$sentinel" ]; then
    local existing_q existing_at
    existing_q=$(jq -r '.question // "(unparseable)"' "$sentinel" 2>/dev/null || echo "(unparseable)")
    existing_at=$(jq -r '.offered_at // "(unknown)"' "$sentinel" 2>/dev/null || echo "(unknown)")
    print_fail "A pending approval already exists: \"$existing_q\" (offered $existing_at)."
    echo "Resolve or clear the existing one first:" >&2
    echo "  scripts/pending-approval.sh --resolve   # user picked" >&2
    echo "  scripts/pending-approval.sh --clear     # abort the question" >&2
    return 1
  fi

  # Build JSON via jq (handles all escaping correctly).
  local now
  now=$(iso_timestamp_utc)
  local options_json
  options_json=$(printf '%s\n' "${options[@]}" | jq -R . | jq -s .)
  local payload
  payload=$(jq -n \
    --arg q "$question" \
    --argjson opts "$options_json" \
    --arg rec "$recommendation" \
    --arg at "$now" \
    '{question: $q, options: $opts, recommendation: $rec, offered_at: $at}')

  # Atomic write: tempfile + mv.
  local tmpfile
  tmpfile=$(mktemp "$project_root/.claude/pending-approval.XXXXXX.tmp")
  printf '%s\n' "$payload" > "$tmpfile"
  mv "$tmpfile" "$sentinel"

  print_ok "Pending approval offered: $question"
}

# --- Subcommand: --resolve ---

cmd_resolve() {
  local project_root
  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")
  if [ -f "$sentinel" ]; then
    rm -f "$sentinel"
    print_ok "Pending approval resolved."
  else
    print_ok "No pending approval."
  fi
}

# --- Subcommand: --clear ---

cmd_clear() {
  local project_root
  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")
  if [ -f "$sentinel" ]; then
    rm -f "$sentinel"
    print_ok "Pending approval cleared (abort)."
  else
    print_ok "No pending approval."
  fi
}

# --- Subcommand: --status ---

cmd_status() {
  local project_root
  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")
  if [ ! -f "$sentinel" ]; then
    print_ok "No pending approval."
    return 0
  fi
  # Try to parse. On failure, report malformed (still exit 0 — file existence is what matters).
  if ! jq -e . "$sentinel" >/dev/null 2>&1; then
    print_info "Malformed sentinel present at $sentinel"
    return 0
  fi
  local q rec at
  q=$(jq -r '.question // "(missing)"' "$sentinel")
  rec=$(jq -r '.recommendation // "(missing)"' "$sentinel")
  at=$(jq -r '.offered_at // "(missing)"' "$sentinel")
  echo "Pending question: \"$q\""
  echo "Options:"
  jq -r '.options[]? // empty | "  " + .' "$sentinel"
  echo "Recommendation: $rec"
  echo "Offered at: $at"
}

# --- Subcommand: --validate ---

cmd_validate() {
  local path="${1:-}"
  if [ -z "$path" ]; then
    local project_root
    if project_root=$(find_project_root); then
      path=$(sentinel_path "$project_root")
    else
      # No project — nothing to validate.
      print_ok "No sentinel to validate."
      return 0
    fi
  fi
  if [ ! -f "$path" ]; then
    print_ok "No sentinel to validate."
    return 0
  fi
  if ! jq -e . "$path" >/dev/null 2>&1; then
    print_fail "Malformed JSON: $path"
    return 1
  fi
  # Schema check: all 4 required fields, options ≥2, recommendation matches an option id.
  local q opts_count rec
  q=$(jq -r '.question // ""' "$path")
  opts_count=$(jq -r '.options // [] | length' "$path")
  rec=$(jq -r '.recommendation // ""' "$path")
  local at_present
  at_present=$(jq -r 'has("offered_at")' "$path")
  if [ -z "$q" ]; then
    print_fail "Schema error: question missing or empty"
    return 1
  fi
  if [ "$opts_count" -lt 2 ]; then
    print_fail "Schema error: options must have at least 2 entries (got $opts_count)"
    return 1
  fi
  if [ -z "$rec" ]; then
    print_fail "Schema error: recommendation missing or empty"
    return 1
  fi
  if [ "$at_present" != "true" ]; then
    print_fail "Schema error: offered_at missing"
    return 1
  fi
  # Recommendation must match a leading id.
  local match=false opt id
  while IFS= read -r opt; do
    id=$(leading_id "$opt")
    if [ "$id" = "$rec" ]; then
      match=true
      break
    fi
  done < <(jq -r '.options[]' "$path")
  if [ "$match" = false ]; then
    print_fail "Schema error: recommendation '$rec' does not match the leading id of any option"
    return 1
  fi
  print_ok "Valid sentinel."
}

# --- Subcommand: --help ---

cmd_help() {
  cat <<HELP
Usage: scripts/pending-approval.sh [COMMAND] [ARGS]

Commands:
  --offer "QUESTION" --options "A1: ..." "A2: ..." ... --recommendation "A1"
                                  Write a pending-approval sentinel.
                                  Refuses if one already exists.
  --resolve                       Delete the sentinel (user picked an option).
  --clear                         Delete the sentinel (agent abort, semantic alias).
  --status                        Print the current pending question, if any.
  --validate [PATH]               Lint a sentinel file. Default: .claude/pending-approval.json.
  --help, -h                      Show this help.

The sentinel file is .claude/pending-approval.json. Both the CDF stop-hook
(4.2.3+) and Solo's pre-commit-gate honor it as "user is deciding."

See docs/builders-guide.md § "Structured Decision Points" for the full
lifecycle and rationale.
HELP
}

# --- Dispatch ---

case "${1:-}" in
  --offer)    shift; cmd_offer "$@" ;;
  --resolve)  shift; cmd_resolve ;;
  --clear)    shift; cmd_clear ;;
  --status)   shift; cmd_status ;;
  --validate) shift; cmd_validate "${1:-}" ;;
  --help|-h|"") cmd_help ;;
  *)
    print_fail "Unknown command: $1"
    cmd_help >&2
    exit 1
    ;;
esac
```

Make it executable:

```bash
chmod +x scripts/pending-approval.sh
```

- [ ] **Step 1.4: Run bash syntax check**

```bash
bash -n scripts/pending-approval.sh
```

Expected: no output, exit 0.

- [ ] **Step 1.5: Run the unit tests and confirm all 17 pass**

```bash
bash tests/test-pending-approval.sh
```

Expected output ends with: `Total: 17 | Passed: 17 | Failed: 0`.

If any fail, inspect the test's failure message — most likely causes:
- `find_project_root` not detecting `.claude/` correctly (P1, P6, P7)
- jq escaping issues in `cmd_offer` (P1)
- ISO timestamp format mismatch (P1's `at` field check)
- macOS BSD `date` rejecting `-Iseconds` flag — the script uses the portable form already

- [ ] **Step 1.6: Commit**

```bash
git add scripts/pending-approval.sh tests/test-pending-approval.sh
git commit -m "$(cat <<'EOF'
feat(pending-approval): add helper script with 5 subcommands (BL-015)

New scripts/pending-approval.sh implements the Solo-side write surface
for the .claude/pending-approval.json sentinel introduced by CDF 4.2.3.

Subcommands:
  --offer "QUESTION" --options ... --recommendation X    Write sentinel atomically
  --resolve                                              Delete (user picked)
  --clear                                                Delete (agent abort)
  --status                                               Print current pending question
  --validate [PATH]                                      Lint a sentinel file
  --help                                                 Usage

Atomic write via mktemp + mv ensures CDF's stop-hook and Solo's
pre-commit-gate (BL-015 reader, next commit) never observe a partial file.
Schema validated at write time per CDF 4.2.3 contract. Refuses
double-offer to avoid memory-holing an earlier pending question.

17 unit tests in tests/test-pending-approval.sh: schema validation,
double-offer refusal, project-root detection, idempotent --resolve,
--clear semantic alias, --status formatted output, --validate edge
cases, atomic-write code-shape regression guard.

Refs spec: docs/superpowers/specs/2026-04-25-pending-approval-sentinel-reader-design.md
EOF
)"
```

---

## Task 2: Reader integration into `pre-commit-gate.sh` + 8 integration tests

**Goal:** Add `pa_check()` + two reason builders to `pre-commit-gate.sh` at the position locked in spec §7. Write 8 integration tests first, watch them fail, implement, watch them pass.

**Files:**
- Modify: `scripts/pre-commit-gate.sh` — insert new block between line 72 (`--no-verify` block end) and line 74 (`--amend` warn block start)
- Modify: `tests/edge-cases-scripts.sh` — append E40–E47 section before the SUMMARY block

- [ ] **Step 2.1: Locate exact insertion line in pre-commit-gate.sh**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
grep -n "Block --no-verify\|Warn on git commit --amend" scripts/pre-commit-gate.sh
```

Expected: two line numbers. The `--no-verify` block ends with `fi` somewhere shortly after; the `--amend` warn comment starts a few lines later. The new block goes between them — after the `fi` of `--no-verify`, before the comment line for `--amend`.

The pattern to match-and-replace in step 2.4 is the contiguous text from the end of the `--no-verify` block through the start of the `--amend` warn block.

- [ ] **Step 2.2: Append integration tests E40–E47 to `tests/edge-cases-scripts.sh`**

Find the SUMMARY block insertion point (the same pattern used for E33–E39 in BL-006):

```bash
grep -n "SUMMARY" tests/edge-cases-scripts.sh | tail -5
```

Insert immediately before the `# ========================================` line that precedes the SUMMARY echo block.

The block to insert:

```bash

# ================================================================
section "BL-015: pending-approval sentinel reader — E40-E47"

# Helper: seed a project dir with a .claude/ and (optionally) a sentinel.
# Reuses the BL-006 git-init pattern; sentinel param is the JSON content
# (or empty string for no sentinel).
pa_seed() {
  local dir="$1" sentinel_json="$2"
  mkdir -p "$dir/.claude" "$dir/.git"
  cat > "$dir/.claude/phase-state.json" <<JSON
{"current_phase": 2, "project": "e40-e47"}
JSON
  cat > "$dir/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
  if [ -n "$sentinel_json" ]; then
    printf '%s' "$sentinel_json" > "$dir/.claude/pending-approval.json"
  fi
  ( cd "$dir" && git init -q && git remote add origin https://example.com/fake.git 2>/dev/null || true )
}

pa_invoke_hook() {
  local cmd="$1" project_dir="$2"
  local input
  input=$(jq -n --arg c "$cmd" '{command: $c}')
  local out rc=0
  out=$( cd "$project_dir" && echo "$input" | bash "$REPO_DIR/scripts/pre-commit-gate.sh" 2>&1 ) || rc=$?
  echo "$rc|$out"
}

# Canonical valid sentinel JSON — used across multiple tests.
PA_VALID='{"question":"commit structure","options":["A1: single","A2: two","A3: three"],"recommendation":"A1","offered_at":"2026-04-25T12:00:00Z"}'
PA_MALFORMED='{"question":"incomplete"'

# E40: feat commit with valid sentinel -> deny with rich reason
_pa_e40_dir="$TEST_DIR/pa-e40"
pa_seed "$_pa_e40_dir" "$PA_VALID"
_pa_e40_r=$(pa_invoke_hook 'git commit -m "feat(x): foo"' "$_pa_e40_dir")
if [[ "${_pa_e40_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e40_r#*|}" == *"pending user decision"* ]] && [[ "${_pa_e40_r#*|}" == *"commit structure"* ]] && [[ "${_pa_e40_r#*|}" == *"A1: single"* ]]; then
  pass "E40: feat commit with valid sentinel — denies with rich reason (question + options)"
else
  fail "E40: expected rich deny reason, got: $_pa_e40_r"
fi

# E41: chore commit with valid sentinel -> deny (Q2 A: blocks ALL commits, not just feat)
_pa_e41_dir="$TEST_DIR/pa-e41"
pa_seed "$_pa_e41_dir" "$PA_VALID"
_pa_e41_r=$(pa_invoke_hook 'git commit -m "chore: bump"' "$_pa_e41_dir")
if [[ "${_pa_e41_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e41_r#*|}" == *"pending user decision"* ]]; then
  pass "E41: chore commit with valid sentinel — denies (sentinel blocks ALL commits)"
else
  fail "E41: expected pending-approval deny on chore: commit, got: $_pa_e41_r"
fi

# E42: commit with malformed sentinel -> deny with malformed-reason
_pa_e42_dir="$TEST_DIR/pa-e42"
pa_seed "$_pa_e42_dir" "$PA_MALFORMED"
_pa_e42_r=$(pa_invoke_hook 'git commit -m "feat(x): foo"' "$_pa_e42_dir")
if [[ "${_pa_e42_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e42_r#*|}" == *"malformed"* ]] && [[ "${_pa_e42_r#*|}" == *"rm"* ]]; then
  pass "E42: malformed sentinel — denies with malformed-reason + rm hint"
else
  fail "E42: expected malformed-reason deny, got: $_pa_e42_r"
fi

# E43: gh pr create with valid sentinel -> deny with "PR creation blocked"
_pa_e43_dir="$TEST_DIR/pa-e43"
pa_seed "$_pa_e43_dir" "$PA_VALID"
_pa_e43_r=$(pa_invoke_hook 'gh pr create --title "x" --body "y"' "$_pa_e43_dir")
if [[ "${_pa_e43_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e43_r#*|}" == *"PR creation blocked"* ]]; then
  pass "E43: gh pr create with valid sentinel — denies with PR-specific label"
else
  fail "E43: expected PR-specific deny, got: $_pa_e43_r"
fi

# E44: feat commit WITHOUT sentinel -> falls through to bl006_check (also denies, but reason is different)
_pa_e44_dir="$TEST_DIR/pa-e44"
pa_seed "$_pa_e44_dir" ""  # no sentinel
_pa_e44_r=$(pa_invoke_hook 'git commit -m "feat(x): foo"' "$_pa_e44_dir")
if [[ "${_pa_e44_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e44_r#*|}" != *"pending user decision"* ]]; then
  pass "E44: no sentinel — falls through to bl006_check (denies, but not for pending-approval)"
else
  fail "E44: expected non-pending deny on no-sentinel commit, got: $_pa_e44_r"
fi

# E45: --no-verify commit with valid sentinel -> security message wins (NOT pending-approval)
_pa_e45_dir="$TEST_DIR/pa-e45"
pa_seed "$_pa_e45_dir" "$PA_VALID"
_pa_e45_r=$(pa_invoke_hook 'git commit --no-verify -m "feat(x): foo"' "$_pa_e45_dir")
if [[ "${_pa_e45_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e45_r#*|}" == *"--no-verify"* ]] && [[ "${_pa_e45_r#*|}" != *"pending user decision"* ]]; then
  pass "E45: --no-verify with valid sentinel — security message wins (ordering preserved)"
else
  fail "E45: expected --no-verify deny, NOT pending-approval, got: $_pa_e45_r"
fi

# E46: --amend commit with valid sentinel -> pending-approval wins (NOT --amend warn)
_pa_e46_dir="$TEST_DIR/pa-e46"
pa_seed "$_pa_e46_dir" "$PA_VALID"
_pa_e46_r=$(pa_invoke_hook 'git commit --amend -m "feat(x): foo"' "$_pa_e46_dir")
if [[ "${_pa_e46_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e46_r#*|}" == *"pending user decision"* ]]; then
  pass "E46: --amend with valid sentinel — pending-approval blocks (upgrades warn to deny)"
else
  fail "E46: expected pending-approval deny on --amend, got: $_pa_e46_r"
fi

# E47: git push --force with valid sentinel -> --force security message (pa_check doesn't fire on push)
_pa_e47_dir="$TEST_DIR/pa-e47"
pa_seed "$_pa_e47_dir" "$PA_VALID"
_pa_e47_r=$(pa_invoke_hook 'git push --force' "$_pa_e47_dir")
if [[ "${_pa_e47_r#*|}" =~ permissionDecision.*deny ]] && [[ "${_pa_e47_r#*|}" == *"Force push"* ]] && [[ "${_pa_e47_r#*|}" != *"pending user decision"* ]]; then
  pass "E47: git push --force with valid sentinel — --force message wins (pa_check skips push)"
else
  fail "E47: expected --force deny, NOT pending-approval, got: $_pa_e47_r"
fi

```

- [ ] **Step 2.3: Run integration tests to confirm E40, E41, E42, E43, E46 fail (pa_check doesn't exist yet)**

```bash
bash tests/edge-cases-scripts.sh 2>&1 | grep -E "E4[0-7]"
```

Expected:
- E40, E41 fail (no deny — bl006_check might fire, but reason won't contain "pending user decision")
- E42 fails (no deny on malformed sentinel without pa_check)
- E43 fails (no PR-specific deny on bare gh pr create with no other gates failing)
- E46 fails (--amend warn fires, allow not deny)
- E44, E45, E47 PASS already (existing behavior unchanged for these)

If E44/E45/E47 fail, fix the test before moving on — likely a setup issue with `pa_seed` or the BL-006 gate not firing as expected.

- [ ] **Step 2.4: Insert `pa_check()` + reason builders into `pre-commit-gate.sh`**

Use Edit to replace the contiguous text from the end of `--no-verify` block through the start of `--amend` warn comment. The exact `old_string` and `new_string`:

`old_string`:

```bash
fi

# Warn on git commit --amend (rewrites commit history, bypasses build loop for amended content)
```

`new_string`:

```bash
fi

# --- BL-015: pending-approval sentinel reader ---
# Blocks git commit and gh pr create when .claude/pending-approval.json exists.
# Runs after security gates (SOIF_*, no-remote, --no-verify) but before
# workflow gates (--amend, bl006_check, --check-commit-ready) so pending
# approval preempts workflow concerns without hiding security violations.
# See docs/builders-guide.md § "Structured Decision Points" for the contract.

build_pa_rich_reason() {
  local sentinel="$1" action_label="$2"
  local question options recommendation offered_at
  question=$(jq -er '.question' "$sentinel") || return 1
  options=$(jq -er '.options | map("  " + .) | join("\n")' "$sentinel") || return 1
  recommendation=$(jq -er '.recommendation' "$sentinel") || return 1
  offered_at=$(jq -er '.offered_at' "$sentinel") || return 1
  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

Pending question: "$question"
Options:
$options
Recommendation: $recommendation
Offered at: $offered_at

Wait for the user to pick one, then:
  scripts/pending-approval.sh --resolve
EOF
}

build_pa_malformed_reason() {
  local sentinel="$1" action_label="$2"
  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

The sentinel file $sentinel exists but is malformed.
Treated as "in flight" per the CDF 4.2.3 contract.

If this is a stale file from a crashed session, remove it manually:
  rm $sentinel
EOF
}

pa_check() {
  # Only applies to git commit or gh pr create. Other commands fall through.
  local is_commit=false is_pr=false
  echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && is_commit=true
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bcreate\b' && is_pr=true
  [ "$is_commit" = false ] && [ "$is_pr" = false ] && return 0

  local sentinel=".claude/pending-approval.json"
  [ -f "$sentinel" ] || return 0

  local action_label="commit"
  [ "$is_pr" = true ] && action_label="PR creation"

  local reason
  if reason=$(build_pa_rich_reason "$sentinel" "$action_label" 2>/dev/null); then
    :
  else
    reason=$(build_pa_malformed_reason "$sentinel" "$action_label")
  fi

  local escaped
  escaped=$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$escaped"}}
HOOKEOF
  exit 0
}

pa_check
# --- end BL-015 block ---

# Warn on git commit --amend (rewrites commit history, bypasses build loop for amended content)
```

Apply the edit:

```bash
# Use the Edit tool with the exact old_string and new_string above.
```

- [ ] **Step 2.5: Run bash syntax check on pre-commit-gate.sh**

```bash
bash -n scripts/pre-commit-gate.sh
```

Expected: no output, exit 0.

- [ ] **Step 2.6: Run integration tests and confirm all E40–E47 pass**

```bash
bash tests/edge-cases-scripts.sh 2>&1 | grep -E "E4[0-7]|PASS:|FAIL:|TOTAL:"
```

Expected: 8/8 pass, summary shows 0 fails.

If E40 / E43 / E46 fail with empty deny reason: most likely the `tr | sed` JSON encoding lost the multi-line content. Inspect the actual `permissionDecisionReason` and adjust the test glob if it's a whitespace-matching issue.

If E45 fails: the `--no-verify` block in `pre-commit-gate.sh` might not be firing — check that pa_check is inserted AFTER `--no-verify`'s `fi`, not before.

- [ ] **Step 2.7: End-to-end smoke test via real hook simulation**

```bash
TMPSMOKE=$(mktemp -d) && cd "$TMPSMOKE"
git init -q
mkdir -p .claude
git remote add origin https://example.com/fake.git
echo '{"current_phase": 2, "project": "smoke"}' > .claude/phase-state.json
echo '{"phase2_init":{"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{"started_at":null,"steps_completed":[]}}' > .claude/process-state.json
echo '{"question":"smoke","options":["X1: a","X2: b"],"recommendation":"X1","offered_at":"2026-04-25T12:00:00Z"}' > .claude/pending-approval.json
echo "--- smoke: feat commit with sentinel present ---"
echo '{"command": "git commit -m \"feat(x): smoke\""}' | \
  bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/pre-commit-gate.sh"
echo ""
cd / && rm -rf "$TMPSMOKE"
```

Expected stdout: a single JSON line with `"permissionDecision":"deny"` and a reason containing `Pending question: "smoke"`, `X1: a`, `X2: b`, `Recommendation: X1`.

- [ ] **Step 2.8: Commit**

```bash
git add scripts/pre-commit-gate.sh tests/edge-cases-scripts.sh
git commit -m "$(cat <<'EOF'
feat(pre-commit-gate): add pa_check sentinel reader (BL-015)

Inserts pa_check() + two reason builders between the --no-verify
security gate and the --amend workflow warn. When
.claude/pending-approval.json exists, denies git commit and gh pr
create with a rich reason that reflects the pending question, options,
and recommendation back to the agent. Falls back to a malformed-reason
text when the sentinel exists but cannot be JSON-parsed (matches
CDF 4.2.3's "existence alone suffices" contract).

Position-in-pipeline rationale: security gates (SOIF_*, no-remote,
--no-verify) fire first to preserve security messaging. pa_check then
preempts workflow gates so an amend during pending-approval upgrades
from warn-allow to hard-deny, and bl006_check doesn't emit a
misleading "no Build Loop active" error when the user is picking.

8 integration tests (E40-E47) in tests/edge-cases-scripts.sh covering
feat/chore commits, gh pr create, malformed sentinel, no-sentinel
fall-through, --no-verify ordering preservation, --amend upgrade,
and push-not-affected.

Refs spec: docs/superpowers/specs/2026-04-25-pending-approval-sentinel-reader-design.md
EOF
)"
```

---

## Task 3: Templates + docs + upgrade-script changelog

**Goal:** Land the three doc/template surfaces from spec §9.

**Files:**
- Modify: `templates/generated/claude-md.tmpl`
- Modify: `docs/builders-guide.md`
- Modify: `scripts/upgrade-project.sh` (header changelog block)

- [ ] **Step 3.1: Add bullet to `templates/generated/claude-md.tmpl`**

Locate the existing MVP Cutline bullet (BL-006 lives here too):

```bash
grep -n "MVP Cutline work is always Build Loop work\|pre-commit gate blocks .feat:" templates/generated/claude-md.tmpl
```

The new bullet goes as a sibling at the same indentation level as the MVP Cutline parent bullet (the BL-006 sub-bullet stays nested under MVP Cutline; this new one is a peer).

Apply the edit. Find the line ending the MVP Cutline parent + its BL-006 sub-bullet (look for the line just before `- **Pin dependencies:**` which is the next existing sibling bullet) and insert immediately after the BL-006 sub-bullet:

`old_string` (the existing pattern from BL-006's edit):

```
  - The pre-commit gate blocks `feat:` commits without an active Build Loop. Non-feature work should use `chore:`/`build:`/`ci:`/`docs:` instead.
- **Pin dependencies:** Exact versions only. Commit the lockfile.
```

`new_string`:

```
  - The pre-commit gate blocks `feat:` commits without an active Build Loop. Non-feature work should use `chore:`/`build:`/`ci:`/`docs:` instead.
- **Structured decision points use the pending-approval sentinel.** When offering structured options (A/B/C / multiple-choice / "pick one" questions) on a blocking decision — commit structure, branch strategy, file layout, scope cuts — first write the sentinel: `scripts/pending-approval.sh --offer "QUESTION" --options "A1: foo" "A2: bar" --recommendation A1`. Delete it when the user picks: `scripts/pending-approval.sh --resolve`. The CDF stop-hook and Solo's pre-commit gate both honor the sentinel — without it, you can drift into committing or stopping prematurely while the user is still deciding.
- **Pin dependencies:** Exact versions only. Commit the lockfile.
```

- [ ] **Step 3.2: Add `### Structured Decision Points` subsection to `docs/builders-guide.md`**

Locate the section boundary:

```bash
grep -n "^### MVP Cutline Work Requires the Build Loop\|^### The Build Loop\|Mechanical enforcement" docs/builders-guide.md
```

The new subsection goes between the closing of "MVP Cutline Work Requires the Build Loop" (which ends with the BL-006 "Mechanical enforcement" paragraph) and the "### The Build Loop" header.

Apply the edit. The exact `old_string` is the line immediately preceding `### The Build Loop`:

`old_string`:

```
**Mechanical enforcement.** This rule is enforced by the pre-commit gate: any `git commit` with a message subject starting with `feat`, `feat(scope)`, `feat!`, or `feat(scope)!` is blocked unless a Build Loop is active and its first five steps (`tests_written`, `tests_verified_failing`, `implemented`, `security_audit`, `documentation_updated`) are complete. Non-feature scaffolding — tooling, CI, build configs — should use the correct Conventional Commits type (`chore:`, `build:`, `ci:`, `docs:`), which the gate does not enforce against. See `docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md` for the full design.

---

### The Build Loop
```

`new_string`:

```
**Mechanical enforcement.** This rule is enforced by the pre-commit gate: any `git commit` with a message subject starting with `feat`, `feat(scope)`, `feat!`, or `feat(scope)!` is blocked unless a Build Loop is active and its first five steps (`tests_written`, `tests_verified_failing`, `implemented`, `security_audit`, `documentation_updated`) are complete. Non-feature scaffolding — tooling, CI, build configs — should use the correct Conventional Commits type (`chore:`, `build:`, `ci:`, `docs:`), which the gate does not enforce against. See `docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md` for the full design.

---

### Structured Decision Points: The Pending-Approval Sentinel

During the Build Loop you occasionally face blocking decisions that need orchestrator input: commit structure (single vs. split), merge strategy, scope cuts. When those decisions are offered as structured options (A/B/C), write `.claude/pending-approval.json` via `scripts/pending-approval.sh --offer …` to signal that the agent is deliberately holding. Delete it via `--resolve` once the orchestrator picks.

**Why this matters.** Observed on lancache (2026-04-24): an agent offered commit-structure options (A1/A2/A3), received an ambiguous response ("Complete these, then finish."), and rationalized the response as implicit approval for the recommended option — a unilateral commit without an explicit pick. Root cause: the stop-hook kept firing "Complete these, then finish" every turn, amplifying pressure until the agent broke its own rule. The fix is mechanical: a sentinel file that both enforcement points (CDF stop-hook, Solo pre-commit-gate) honor as "user is deciding — do not advance."

**What the sentinel does.** When `.claude/pending-approval.json` exists:
- The CDF stop-hook (4.2.3+) exits silently — no block JSON, no stderr advisory, no pressure loop.
- Solo's `scripts/pre-commit-gate.sh` blocks `git commit` and `gh pr create` — no irreversible action slips through.

Both enforcement points defer to the same file. The sentinel is the single source of truth for "user is deciding."

**Lifecycle.**
1. Agent offers structured options to the user.
2. Agent writes the sentinel: `scripts/pending-approval.sh --offer "…" --options "…" --recommendation "…"`. Writes are atomic (tempfile + `mv`) so consumers never see a half-written file.
3. File exists while the user deliberates. Both enforcement points hold.
4. User picks. Agent deletes the sentinel: `scripts/pending-approval.sh --resolve` (user answered) or `--clear` (agent aborting the question). Both commands behave identically — the distinction is semantic, for audit readability.
5. Enforcement points resume normal behavior.

**Sub-command reference.** `scripts/pending-approval.sh --help` lists the full API: `--offer`, `--resolve`, `--clear`, `--status`, `--validate`. `--status` is useful after session recovery ("is there a live sentinel from before?"). `--validate` lints a sentinel path (default `.claude/pending-approval.json`) for CI or debugging use.

**Double-offer is refused.** If a sentinel already exists, `--offer` refuses with an error listing the existing question. Resolve or clear first. This prevents memory-holing an earlier question that the user might still be deciding on.

**Staleness.** Orphaned sentinels (from a crashed agent session) are not auto-cleaned. Run `scripts/pending-approval.sh --clear` or `rm .claude/pending-approval.json` if one is stuck. This matches the CDF stop-hook's behavior; both consumers share the same recovery path.

**When NOT to use the sentinel.** Simple confirm-y/n questions (e.g., "Proceed with the refactor?") don't need the sentinel — just ask. The sentinel is for *structured* decisions where a specific pick is required and an accidental advance would be harmful. Overuse dilutes its signal; under-use causes incidents like lancache.

**Upgrading existing projects.** `scripts/upgrade-project.sh` copies the new `scripts/pending-approval.sh` and the updated `scripts/pre-commit-gate.sh` into existing projects, so the **enforcement** (reader + helper) goes live immediately on upgrade. However, the new `claude-md.tmpl` bullet does NOT replace existing populated `CLAUDE.md` files — those keep their original content. So existing-project agents won't *know* to use the sentinel until either (a) the orchestrator manually adds the bullet to their `CLAUDE.md`, or (b) the project is re-initialized.

This asymmetry is intentional and acceptable: even without the instruction, the enforcement still prevents the livelock (stop-hook side) and the commit slippage (reader side) — those failure modes are caught regardless of agent awareness. The full benefit (agents proactively writing sentinels when offering options) accrues on new or re-initialized projects.

If you maintain an existing project that should fully adopt the mechanism, copy the bullet from `templates/generated/claude-md.tmpl` (Construction Rules section) into your project's `CLAUDE.md`.

---

### The Build Loop
```

- [ ] **Step 3.3: Add changelog entry to `scripts/upgrade-project.sh`**

Find the existing Changelog block (added by BL-006):

```bash
grep -n "Changelog:\|BL-006 (2026-04-24)" scripts/upgrade-project.sh
```

Append the BL-015 entry after the BL-006 entry. The exact edit:

`old_string`:

```
# Changelog:
# - BL-006 (2026-04-24): pre-commit gate now blocks feat: commits without
#   an active Build Loop. No migration code needed — the updated
#   scripts/process-checklist.sh and scripts/pre-commit-gate.sh are copied
#   by this script's existing behavior, so running an upgrade picks it up.
#
# Usage:
```

`new_string`:

```
# Changelog:
# - BL-006 (2026-04-24): pre-commit gate now blocks feat: commits without
#   an active Build Loop. No migration code needed — the updated
#   scripts/process-checklist.sh and scripts/pre-commit-gate.sh are copied
#   by this script's existing behavior, so running an upgrade picks it up.
# - BL-015 (2026-04-25): pre-commit gate now blocks commits and PR creation
#   when .claude/pending-approval.json exists. New helper script
#   scripts/pending-approval.sh. CLAUDE.md template gets new bullet under
#   Construction Rules. Upgrade picks up the new scripts and template.
#
# Usage:
```

- [ ] **Step 3.4: Verify upgrade-project.sh syntax not broken**

```bash
bash -n scripts/upgrade-project.sh
```

Expected: no output, exit 0.

- [ ] **Step 3.5: Commit**

```bash
git add templates/generated/claude-md.tmpl docs/builders-guide.md scripts/upgrade-project.sh
git commit -m "$(cat <<'EOF'
docs(bl-015): template bullet, builders-guide subsection, upgrade changelog

- templates/generated/claude-md.tmpl: new Construction Rules bullet
  instructing agents to write .claude/pending-approval.json via
  scripts/pending-approval.sh when offering structured options.
- docs/builders-guide.md: new "Structured Decision Points" subsection
  between MVP Cutline and Build Loop. Documents the lancache incident
  (2026-04-24), the symmetric CDF/Solo enforcement, the lifecycle, and
  the upgrade-asymmetry note (existing CLAUDE.md files don't get the
  bullet automatically — orchestrator must copy it manually).
- scripts/upgrade-project.sh: BL-015 entry appended to header changelog.

No behavior change in this commit — only docs and template content.

Refs spec: docs/superpowers/specs/2026-04-25-pending-approval-sentinel-reader-design.md
EOF
)"
```

---

## Task 4: Full verification + Build Loop close + PR

**Goal:** Run every test suite touching the changed files. Confirm no regression. Complete Build Loop steps on the BL-015 feature. Push and open PR.

- [ ] **Step 4.1: Run new helper unit tests**

```bash
bash tests/test-pending-approval.sh
```

Expected: `Total: 17 | Passed: 17 | Failed: 0`.

- [ ] **Step 4.2: Run full edge-cases suite (includes E40–E47 + all prior)**

```bash
bash tests/edge-cases-scripts.sh 2>&1 | tail -10
```

Expected: SUMMARY shows PASS = 54 (46 prior + 8 new), FAIL = 0.

- [ ] **Step 4.3: Run other test suites that touch pre-commit-gate or process-checklist**

```bash
bash tests/test-check-commit-message.sh
bash tests/test-unrecord-feature.sh
bash tests/known-bugs-test-suite.sh
bash tests/test-lint-uat-scenarios.sh
```

Expected: each exits 0 with no new failures. If any failure references a file we didn't touch, it's pre-existing — surface it but don't block.

- [ ] **Step 4.4: Verify --help on the new helper**

```bash
scripts/pending-approval.sh --help
```

Expected: usage text listing all 5 subcommands plus `--help`.

- [ ] **Step 4.5: Manual smoke test of the full lifecycle**

```bash
TMPSMOKE=$(mktemp -d) && cd "$TMPSMOKE"
git init -q
mkdir -p .claude
git remote add origin https://example.com/fake.git
echo '{"current_phase": 2, "project": "smoke"}' > .claude/phase-state.json
echo '{"phase2_init":{"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{"started_at":null,"steps_completed":[]}}' > .claude/process-state.json

echo "--- 1. offer ---"
"/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/pending-approval.sh" --offer "smoke question" --options "A1: yes" "A2: no" --recommendation "A1"
echo "--- 2. status ---"
"/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/pending-approval.sh" --status
echo "--- 3. attempt commit (should be denied) ---"
echo '{"command": "git commit -m \"feat(x): smoke\""}' | \
  bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/pre-commit-gate.sh" | head -c 400
echo ""
echo "--- 4. resolve ---"
"/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/pending-approval.sh" --resolve
echo "--- 5. status (should show no pending) ---"
"/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/pending-approval.sh" --status
cd / && rm -rf "$TMPSMOKE"
```

Expected:
1. `[OK] Pending approval offered: smoke question`
2. Formatted summary with `Pending question: "smoke question"`, options, recommendation, offered_at
3. JSON deny with `Pending question: "smoke question"` in the `permissionDecisionReason`
4. `[OK] Pending approval resolved.`
5. `[OK] No pending approval.`

If any step deviates, debug before proceeding to the Build Loop close.

- [ ] **Step 4.6: Complete Build Loop steps for the BL-015 feature**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
scripts/process-checklist.sh --complete-step build_loop:tests_written
scripts/process-checklist.sh --complete-step build_loop:tests_verified_failing
scripts/process-checklist.sh --complete-step build_loop:implemented
scripts/process-checklist.sh --complete-step build_loop:security_audit
```

Expected: each step records OK. The `security_audit` step requires a findings file; produce one in step 4.7.

- [ ] **Step 4.7: Produce security audit findings file**

Create `docs/security-audits/bl-015-pending-approval-sentinel-reader-security-audit.md` documenting the audit. Use the template structure from BL-006's audit as a model. Key findings to include:

```markdown
# Security Audit Findings — Feature: BL-015 pending-approval sentinel reader

**Feature:** bl-015-pending-approval-sentinel-reader
**Date:** 2026-04-25
**Auditor Persona:** Senior Security Engineer

---

## Scope

- New `scripts/pending-approval.sh` helper script (5 subcommands).
- New `pa_check()` block + two reason builders in `scripts/pre-commit-gate.sh`.
- New unit test file `tests/test-pending-approval.sh` and integration tests E40–E47 in `tests/edge-cases-scripts.sh`.
- Documentation/template additions (no executable code changes).

## Automated Scan Results

| Tool | Config | Result | Findings |
|------|--------|--------|----------|
| `bash -n` syntax check | default | Pass | 0 |
| `shellcheck` | default | Not run on new files (matches existing repo convention) | N/A |

## Manual Review Findings

| # | Category | Finding | Severity | File:Line | Resolution | Status |
|---|----------|---------|----------|-----------|------------|--------|
| 1 | Command injection | The helper builds JSON via `jq -n --arg ... --argjson ...` — jq's `--arg` properly escapes user-supplied strings. No `eval`, no shell interpolation of untrusted input into commands. | Critical | `scripts/pending-approval.sh::cmd_offer` | No mitigation needed — safe by jq design. | Accepted |
| 2 | Command injection | The reader passes the sentinel path to `jq -er` (data-mode parsing). The path is a fixed string `.claude/pending-approval.json`, never derived from user input. | Critical | `scripts/pre-commit-gate.sh::pa_check` | No mitigation needed. | Accepted |
| 3 | Command injection | The deny reason is built via `cat <<EOF` heredoc; user-supplied fields (`question`, `options`, `recommendation`, `offered_at`) are interpolated as bash strings, then run through `tr | sed` to JSON-encode. Heredoc interpolation does NOT execute embedded commands or backticks (heredoc with unquoted EOF still does parameter expansion but not command substitution of user-controlled vars). The `sed 's/"/\\"/g'` step ensures embedded quotes don't break the JSON envelope. | High | `scripts/pre-commit-gate.sh::build_pa_rich_reason` | No mitigation needed; encoding pipeline is robust. | Accepted |
| 4 | Path traversal / arbitrary write | Helper's `--offer` writes to `$PROJECT_ROOT/.claude/pending-approval.json` where `$PROJECT_ROOT` is found by walking up from `$PWD` looking for `.claude/`. Bounded to the discovered project; cannot write outside. | Medium | `scripts/pending-approval.sh::find_project_root + cmd_offer` | Bounded write path; no traversal possible. | Accepted |
| 5 | Atomic write race | Helper uses `mktemp + mv`; readers (CDF stop-hook, Solo pre-commit-gate) never observe a half-written file. Code-shape regression test P17 enforces this pattern. | High | `scripts/pending-approval.sh::cmd_offer` | Atomic-write pattern in place + test guard. | Fixed |
| 6 | Information disclosure | Deny reason includes the sentinel's `question`, `options`, `recommendation`, `offered_at` fields. These are agent-authored and intended for display. No secrets are exposed; no environment variables are read. | Low | `scripts/pre-commit-gate.sh::build_pa_rich_reason` | Intentional and safe. | Accepted |
| 7 | Denial of service | A malicious or crashed agent could write a sentinel and never resolve it, blocking all commits indefinitely. Mitigation: `--clear` and manual `rm` documented. CDF and Solo share this risk; intentionally punted (Q7 A) per spec §11. | Medium | `scripts/pending-approval.sh` lifecycle | Documented manual recovery; matches CDF behavior. | Accepted |
| 8 | Bypass via non-helper writes | A determined agent could `echo '{}' > .claude/pending-approval.json` directly, bypassing the helper's validation. The reader treats malformed sentinels as still-blocking ("in flight"), so this can only block the agent itself, not bypass. Conversely, an agent wanting to bypass the sentinel could `rm .claude/pending-approval.json` directly. The PreToolUse hook does not gate `rm` — bypass is theoretically possible but requires the agent to actively defeat its own rule. Out of scope for this layer. | Low | Architectural | `--clear` provides the sanctioned path; rm-bypass is acknowledged. | Accepted |

## Summary

- **0 Open findings.**
- **3 Critical findings (#1, #2, #3) — accepted as safe-by-design:** all bash interpolation paths use jq for JSON construction or quoted heredocs; no shell evaluation of untrusted input.
- **2 High findings (#3, #5):** JSON encoding pipeline robust; atomic-write pattern enforced by code-shape test P17.
- **2 Medium findings (#4, #7):** path-traversal bounded by project-root walk; DoS via stuck sentinel intentionally punted with documented manual recovery.
- **2 Low findings (#6, #8):** information disclosure is intentional (reflecting question to agent); rm-bypass is theoretically possible but architecturally out of scope.

No findings require code changes. The implementation passes the audit.
```

Save and add to git:

```bash
git add docs/security-audits/bl-015-pending-approval-sentinel-reader-security-audit.md
```

Then re-attempt the security_audit step:

```bash
scripts/process-checklist.sh --complete-step build_loop:security_audit
```

Expected: OK. (Step 4.6 already attempted this — re-run if it failed.)

- [ ] **Step 4.8: Complete documentation_updated step**

```bash
scripts/process-checklist.sh --complete-step build_loop:documentation_updated
```

Expected: OK (4/6 → 5/6).

- [ ] **Step 4.9: Commit the security audit**

```bash
git commit -m "$(cat <<'EOF'
docs(security-audit): BL-015 pending-approval sentinel reader audit

Manual review of the new bash in pending-approval.sh (helper) and
pre-commit-gate.sh (pa_check + reason builders).

0 Open findings.
- Critical findings (command injection) accepted as safe-by-design:
  jq --arg/--argjson handles all user-supplied JSON construction;
  reader uses jq -er for data-mode parsing only.
- High findings (atomic write, JSON encoding pipeline) addressed:
  mktemp+mv enforced by code-shape test P17; tr|sed encoding is
  robust against embedded quotes/newlines.
- Medium findings (path traversal, DoS) bounded/punted: project-root
  walk prevents arbitrary writes; stuck-sentinel DoS recovery via
  --clear or manual rm, matches CDF behavior.

No code changes required to resolve audit findings.
EOF
)"
```

- [ ] **Step 4.10: Push branch and open PR**

```bash
git push -u origin feat/bl-015-pending-approval-sentinel-reader
gh pr create --title "BL-015: pending-approval sentinel reader (Solo side)" --body "$(cat <<'EOF'
## Summary

- New `scripts/pending-approval.sh` helper with 5 subcommands (`--offer`, `--resolve`, `--clear`, `--status`, `--validate`). Atomic write via `mktemp + mv`; refuses double-offer; matches the JSON schema CDF 4.2.3 owns.
- New `pa_check()` block in `pre-commit-gate.sh` between `--no-verify` (security) and `--amend` (workflow). Denies `git commit` and `gh pr create` when `.claude/pending-approval.json` exists, with rich reason reflecting the pending question back to the agent.
- 17 unit tests (`tests/test-pending-approval.sh`) + 8 integration tests (E40–E47 in `tests/edge-cases-scripts.sh`).
- Docs: Builder's Guide "Structured Decision Points" subsection (motivating lancache incident, lifecycle, upgrade asymmetry note); CLAUDE.md template bullet; upgrade-project.sh changelog note.
- Security audit: 0 open findings.

Solo-side complement to CDF 4.2.3's stop-hook fix (`f55c8bc`). Together, the two enforcement points eliminate the lancache 2026-04-24 livelock and prevent commit slippage during structured user decisions.

## Test plan

- [x] `bash tests/test-pending-approval.sh` — 17/17 pass
- [x] `bash tests/edge-cases-scripts.sh` — E40–E47 pass alongside existing E1–E39 (54 total)
- [x] `bash tests/test-check-commit-message.sh` — no regression
- [x] `bash tests/test-unrecord-feature.sh` — no regression
- [x] `bash tests/known-bugs-test-suite.sh` — no regression
- [x] Manual lifecycle smoke test: offer → status → attempt commit (denied) → resolve → status (clear)

## References

- Spec: `docs/superpowers/specs/2026-04-25-pending-approval-sentinel-reader-design.md`
- Plan: `docs/superpowers/plans/archive/2026-04-25-pending-approval-sentinel-reader-implementation.md` (archived 2026-07-05, BL-049)
- Upstream dependency: CDF 4.2.3 (`f55c8bc`) — verified in this session.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4.11: After PR merges — record feature, close Build Loop, update backlog**

```bash
git checkout main
git pull --ff-only origin main
scripts/test-gate.sh --record-feature "bl-015-pending-approval-sentinel-reader"
scripts/process-checklist.sh --complete-step build_loop:feature_recorded
```

Then update `solo-orchestrator-backlog.md`: change BL-015 status from `promoted-to-spec` to `Resolved (2026-04-25, PR #N)` and append a Resolution paragraph mirroring BL-006/BL-007/BL-008/BL-009 entries.

Commit:

```bash
git add solo-orchestrator-backlog.md
git commit -m "backlog: mark BL-015 resolved (PR #N merged 2026-04-25)"
git push origin main
git branch -d feat/bl-015-pending-approval-sentinel-reader
```

---

## Self-Review Checklist (completed at plan-writing time)

**1. Spec coverage — every spec section is mapped to a task:**
- Spec § 1 Problem: context only, no task.
- Spec § 2 Scope: Tasks 1–4 cover in-scope items.
- Spec § 3 Locked parameters: each baked into Task 1 (helper validation), Task 2 (reader position + reason format), Task 3 (docs).
- Spec § 4 Architecture: Task 1 (helper unit), Task 2 (reader unit), Task 3 (template + docs units).
- Spec § 5 Schema: enforced by Task 1.3's helper implementation + Task 1.1's P3/P4/P5 validation tests.
- Spec § 6 Helper contract: Task 1.3 implements all 5 subcommands per the contract; Task 1.1 tests all of them.
- Spec § 7 Reader integration: Task 2.4 inserts pa_check at the locked position; Task 2.6 verifies via integration tests.
- Spec § 8 Error messages: Task 2.4 includes both build_pa_rich_reason and build_pa_malformed_reason with the exact text; E40, E42, E43 validate.
- Spec § 9 Templates + docs: Tasks 3.1, 3.2, 3.3 cover claude-md.tmpl, builders-guide.md, upgrade-project.sh respectively.
- Spec § 10 Testing plan: Task 1.1 (P1–P17), Task 2.2 (E40–E47).
- Spec § 11 Risks: mitigations encoded in test cases (P17 atomic-write, E45 ordering, E46 amend upgrade).
- Spec § 12 Success criteria: Task 4 verification steps map to each criterion.

**2. Placeholder scan:** no TBD/TODO/fill-in. Every step contains complete code or exact commands.

**3. Type consistency:**
- `cmd_offer` / `cmd_resolve` / `cmd_clear` / `cmd_status` / `cmd_validate` — same names used in dispatch case (Task 1.3) and tests (Task 1.1 references the subcommand flags `--offer` etc., not function names — no consistency issue there).
- `pa_check` / `build_pa_rich_reason` / `build_pa_malformed_reason` — same names defined and called in Task 2.4.
- `find_project_root` — same name used in helper (Task 1.3); does not collide with same-named function in `upgrade-project.sh` (different file scope).
- `pa_seed` / `pa_invoke_hook` — defined and used in Task 2.2 only.
- `iso_timestamp_utc` / `leading_id` / `sentinel_path` — defined once in helper (Task 1.3), used by other helper functions.

**Fixable issues found during self-review:** none. Plan is ready to execute.

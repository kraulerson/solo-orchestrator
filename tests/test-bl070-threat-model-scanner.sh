#!/usr/bin/env bash
# tests/test-bl070-threat-model-scanner.sh
#
# BL-070 increment (WP-B2): scripts/run-phase3-validation.sh's `threat-model`
# scanner promoted from stub to REAL. The scanner validates that every threat
# recorded in PROJECT_BIBLE.md Section 4 (as `TM-NNN` table rows) is accounted
# for by the newest Phase-3 threat-model VALIDATION REPORT in docs/test-results/
# AND that the report's Unmitigated table carries a non-empty Approved By for
# every accepted-risk row. It is PURE-LOCAL FILE PARSING (no tool, no network),
# so it deliberately RUNS under --offline (giving the gate autorun a real
# threat-model verdict rather than an un-attested SKIP).
#
# Contract:
#   SKIP = no PROJECT_BIBLE.md, or a bible with no §4 threat table (attestable).
#   PASS = every Bible TM-ID appears in the newest validation report AND the
#          report's Unmitigated table is empty-or-risk-accepted.
#   FAIL = report missing while TM-IDs exist, OR any TM-ID unaccounted for, OR
#          an unmitigated row without an approver. Missing IDs are named by
#          name (and archived in missing[]).
#   Report glob accepts BOTH conventional names (a verified framework naming
#   inconsistency): *_threat-model-validation.md OR *_threat-validation.md;
#   newest-by-name-sort wins.
#
# Cases:
#   T-tm-pass-complete       all IDs validated, unmitigated empty → PASS + the
#                            archived JSON shape {ids_total,ids_validated,missing}.
#   T-tm-pass-risk-accepted  unmitigated row WITH an approver → PASS.
#   T-tm-missing-id-fail     a Bible TM-ID absent from the report → FAIL, the
#                            missing ID named in output AND in archived missing[].
#   T-tm-unapproved-risk-fail unmitigated row with empty Approved By → FAIL.
#   T-tm-report-absent-fail  TM rows exist, no report → FAIL.
#   T-tm-no-threat-table-skip  bible with no §4 table → attestable SKIP.
#   T-tm-glob-both-names     report saved under the legacy *_threat-validation.md
#                            name is still found → PASS.
#   T-tm-newest-wins         two reports; the NEWEST (incomplete) governs → FAIL.
#   T-tm-offline-runs        --offline still yields a real threat-model verdict.
#   T-tm-word-boundary       bible TM-001 vs report TM-0011 → TM-001 MISSING
#                            (TM-0011 must not satisfy TM-001).
#   T-mutation               MUTATION-PROOF: excise the `# BL-070-TM-COMPARE`
#                            coverage-diff line → T-tm-missing-id-fail's FAIL
#                            disappears (real: [FAIL]; mutant: no [FAIL]).
#
# HERMETIC: the driver runs with PATH = a curated clean bin that symlinks a
# fixed set of coreutils (incl. awk) but NO semgrep and NO license tool, so the
# sibling scanner arms can never exec a host tool and the run is offline + fast.
# The threat-model scanner itself execs nothing external. bash-3.2 safe; no
# ((x++)); no real remotes; no init.sh invocation.

set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"
BASH_BIN="$(command -v bash)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Curated clean bin ────────────────────────────────────────────────
# Symlink only the tools the driver needs into a private dir. Running the
# driver with PATH pointed here guarantees NO host semgrep / license tool is
# reachable, so every sibling scanner arm SKIPs and only threat-model produces
# a real verdict.
CLEAN_BIN="$(mktemp -d "${TMPDIR:-/tmp}/bl070tm-cleanbin-XXXXXX")"
_build_clean_bin() {
  local t p
  for t in bash sh env cat head tail sed grep egrep awk printf echo dirname \
           basename jq git date mkdir rmdir rm mv cp chmod ln sleep mktemp wc \
           tr cut sort uniq hostname whoami id test ls; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    [ -n "$p" ] && ln -sf "$p" "$CLEAN_BIN/$t" 2>/dev/null || true
  done
}
_build_clean_bin

# ── Per-test fixture ─────────────────────────────────────────────────
# setup — a project dir with docs/test-results (validation-report dir, TRDIR)
# and docs/test-results/phase3 (scan-archive dir, RDIR). Bible + report(s) are
# written per-test by the helpers below.
setup() {
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/bl070tm-proj-XXXXXX")"
  PROJ="$TMP/p"
  RDIR="$PROJ/docs/test-results/phase3"
  TRDIR="$PROJ/docs/test-results"
  mkdir -p "$PROJ/.claude" "$RDIR"
}
teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }

# write_bible <id...> — a minimal PROJECT_BIBLE.md §4 table with the given IDs.
write_bible() {
  {
    echo "# Project Bible"
    echo ""
    echo "## 4. Threat Model & Risk/Mitigation Matrix"
    echo "| ID | Threat | STRIDE | Attack Path | Mitigation | Validation Reference |"
    echo "|---|---|---|---|---|---|"
    local id
    for id in "$@"; do
      echo "| $id | threat $id | T | path | mitigate | ref |"
    done
  } > "$PROJ/PROJECT_BIBLE.md"
}

# write_bible_no_table — a bible whose §4 has prose but no TM rows.
write_bible_no_table() {
  {
    echo "# Project Bible"
    echo ""
    echo "## 4. Threat Model & Risk/Mitigation Matrix"
    echo "No threats have been recorded for this project yet."
  } > "$PROJ/PROJECT_BIBLE.md"
}

# report_open <path> — start a validation report (validation-results header).
report_open() {
  {
    echo "# Threat Model Validation Report"
    echo ""
    echo "## Validation Results"
    echo "| Threat ID | Description | Mitigation | Test Method | Test Result | Risk Acceptance |"
    echo "|---|---|---|---|---|---|"
  } > "$1"
}
# report_result_row <path> <id> <result> — a validation-results row.
report_result_row() {
  echo "| $2 | threat $2 | a:1 | payload | $3 | - |" >> "$1"
}
# report_unmitigated_open <path> — start the Unmitigated Threats table.
report_unmitigated_open() {
  {
    echo ""
    echo "## Unmitigated Threats"
    echo "| Threat ID | Risk Level | Rationale | Approved By | Date |"
    echo "|---|---|---|---|---|"
  } >> "$1"
}
# report_unmitigated_row <path> <id> <approver> — an accepted-risk row.
report_unmitigated_row() {
  echo "| $2 | Medium | residual risk | $3 | 2026-07-10 |" >> "$1"
}
# report_close <path> — trailing Summary heading (closes the unmitigated table).
report_close() { { echo ""; echo "## Summary"; } >> "$1"; }

# run_tm_driver [extra-args...] — run the driver in $PROJ with the hermetic
# PATH, archiving to $RDIR. Echoes combined stdout+stderr; never aborts.
run_tm_driver() {
  ( cd "$PROJ" && PATH="$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$RDIR" "$@" </dev/null 2>&1 ) || true
}
# Newest archived threat-model report, or empty.
tm_archive() { ls -1 "$RDIR"/threat-model-*.json 2>/dev/null | sort | tail -1; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-pass-complete: all IDs validated, unmitigated empty → PASS + archive ==="
# ════════════════════════════════════════════════════════════════════
setup
write_bible TM-001 TM-002
REP="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$REP"
report_result_row "$REP" TM-001 Pass
report_result_row "$REP" TM-002 Pass
report_unmitigated_open "$REP"
report_close "$REP"
out="$(run_tm_driver)"
arch="$(tm_archive)"
if echo "$out" | grep -q "\[PASS\] threat-model"; then
  pass "T-tm-pass-complete: driver reports [PASS] threat-model"
else
  fail_ "T-tm-pass-complete" "expected [PASS] threat-model; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if [ -n "$arch" ] && [ -s "$arch" ]; then
  pass "T-tm-pass-complete: archive written ($(basename "$arch"))"
else
  fail_ "T-tm-pass-complete" "expected a threat-model-*.json archive; found '$arch'"
fi
if [ -n "$arch" ] && grep -q '"ids_total":2' "$arch" && grep -q '"ids_validated":2' "$arch" && grep -q '"missing":\[\]' "$arch"; then
  pass "T-tm-pass-complete: archive JSON shape correct (ids_total=2, ids_validated=2, missing=[])"
else
  fail_ "T-tm-pass-complete" "archive JSON shape wrong; got: $([ -n "$arch" ] && cat "$arch")"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-pass-risk-accepted: unmitigated row WITH approver → PASS ==="
# ════════════════════════════════════════════════════════════════════
setup
write_bible TM-001 TM-002
REP="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$REP"
report_result_row "$REP" TM-001 Pass
report_result_row "$REP" TM-002 Partial
report_unmitigated_open "$REP"
report_unmitigated_row "$REP" TM-002 "Jane Security (IT)"
report_close "$REP"
out="$(run_tm_driver)"
if echo "$out" | grep -q "\[PASS\] threat-model"; then
  pass "T-tm-pass-risk-accepted: accepted-risk row with approver → [PASS]"
else
  fail_ "T-tm-pass-risk-accepted" "expected [PASS] threat-model; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-missing-id-fail: a Bible TM-ID absent from report → FAIL + named ==="
# ════════════════════════════════════════════════════════════════════
setup
write_bible TM-001 TM-002 TM-003
REP="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$REP"
report_result_row "$REP" TM-001 Pass
report_result_row "$REP" TM-002 Pass
report_unmitigated_open "$REP"
report_close "$REP"
out="$(run_tm_driver)"
arch="$(tm_archive)"
if echo "$out" | grep -q "\[FAIL\] threat-model"; then
  pass "T-tm-missing-id-fail: driver reports [FAIL] threat-model"
else
  fail_ "T-tm-missing-id-fail" "expected [FAIL] threat-model; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -q "TM-003"; then
  pass "T-tm-missing-id-fail: the missing ID (TM-003) is named in the output"
else
  fail_ "T-tm-missing-id-fail" "expected TM-003 named in output; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if [ -n "$arch" ] && grep -q '"missing":\["TM-003"\]' "$arch"; then
  pass "T-tm-missing-id-fail: TM-003 recorded in archived missing[]"
else
  fail_ "T-tm-missing-id-fail" "expected missing:[\"TM-003\"] in archive; got: $([ -n "$arch" ] && cat "$arch")"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-unapproved-risk-fail: unmitigated row, empty Approved By → FAIL ==="
# ════════════════════════════════════════════════════════════════════
setup
write_bible TM-001 TM-002
REP="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$REP"
report_result_row "$REP" TM-001 Pass
report_result_row "$REP" TM-002 Partial
report_unmitigated_open "$REP"
report_unmitigated_row "$REP" TM-002 ""     # empty Approved By
report_close "$REP"
out="$(run_tm_driver)"
if echo "$out" | grep -q "\[FAIL\] threat-model"; then
  pass "T-tm-unapproved-risk-fail: unapproved accepted-risk row → [FAIL]"
else
  fail_ "T-tm-unapproved-risk-fail" "expected [FAIL] threat-model; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -qiE "without an approver.*TM-002|TM-002"; then
  pass "T-tm-unapproved-risk-fail: the unapproved ID (TM-002) is named"
else
  fail_ "T-tm-unapproved-risk-fail" "expected TM-002 named; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-report-absent-fail: TM rows exist, no report → FAIL ==="
# ════════════════════════════════════════════════════════════════════
setup
write_bible TM-001 TM-002
# No report written to $TRDIR.
out="$(run_tm_driver)"
arch="$(tm_archive)"
if echo "$out" | grep -q "\[FAIL\] threat-model"; then
  pass "T-tm-report-absent-fail: missing report with TM-IDs → [FAIL]"
else
  fail_ "T-tm-report-absent-fail" "expected [FAIL] threat-model; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -qE "TM-001" && echo "$out" | grep -qE "TM-002"; then
  pass "T-tm-report-absent-fail: unvalidated IDs named in output"
else
  fail_ "T-tm-report-absent-fail" "expected TM-001 + TM-002 named; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if [ -n "$arch" ] && grep -q '"ids_validated":0' "$arch"; then
  pass "T-tm-report-absent-fail: archive records ids_validated=0"
else
  fail_ "T-tm-report-absent-fail" "expected ids_validated=0 in archive; got: $([ -n "$arch" ] && cat "$arch")"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-no-threat-table-skip: bible with no §4 table → attestable SKIP ==="
# ════════════════════════════════════════════════════════════════════
setup
write_bible_no_table
out="$(run_tm_driver)"
if echo "$out" | grep -q "\[SKIP\] threat-model"; then
  pass "T-tm-no-threat-table-skip: no threat table → [SKIP] threat-model"
else
  fail_ "T-tm-no-threat-table-skip" "expected [SKIP] threat-model; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -qi "no threat model recorded"; then
  pass "T-tm-no-threat-table-skip: SKIP note is 'no threat model recorded'"
else
  fail_ "T-tm-no-threat-table-skip" "expected 'no threat model recorded' note; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -q "UN-ATTESTED"; then
  pass "T-tm-no-threat-table-skip: the SKIP is attestable (un-attested → gate would block)"
else
  fail_ "T-tm-no-threat-table-skip" "expected the SKIP to be flagged UN-ATTESTED; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if [ -z "$(tm_archive)" ]; then
  pass "T-tm-no-threat-table-skip: no archive written for a SKIP"
else
  fail_ "T-tm-no-threat-table-skip" "a SKIP must not archive a report"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-glob-both-names: legacy *_threat-validation.md name is still found ==="
# ════════════════════════════════════════════════════════════════════
# project-bible.tmpl historically linked TM rows to threat-validation.md (no
# 'model'); the scanner glob must accept that legacy name too.
setup
write_bible TM-001
REP="$TRDIR/2026-07-10_threat-validation.md"   # legacy name (no 'model')
report_open "$REP"
report_result_row "$REP" TM-001 Pass
report_unmitigated_open "$REP"
report_close "$REP"
out="$(run_tm_driver)"
if echo "$out" | grep -q "\[PASS\] threat-model"; then
  pass "T-tm-glob-both-names: report under the legacy name is found → [PASS]"
else
  fail_ "T-tm-glob-both-names" "expected [PASS] threat-model (legacy name found); out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -q "2026-07-10_threat-validation.md"; then
  pass "T-tm-glob-both-names: note cites the legacy-named report"
else
  fail_ "T-tm-glob-both-names" "expected the legacy report name in the note; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-newest-wins: two reports, the NEWEST (incomplete) governs → FAIL ==="
# ════════════════════════════════════════════════════════════════════
# Older report is COMPLETE (would PASS); newer report is INCOMPLETE (missing
# TM-002). Newest-by-name-sort must govern → FAIL, proving the older complete
# report does not mask the newer incomplete one.
setup
write_bible TM-001 TM-002
OLD="$TRDIR/2026-07-08_threat-model-validation.md"
report_open "$OLD"; report_result_row "$OLD" TM-001 Pass; report_result_row "$OLD" TM-002 Pass
report_unmitigated_open "$OLD"; report_close "$OLD"
NEW="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$NEW"; report_result_row "$NEW" TM-001 Pass   # TM-002 deliberately absent
report_unmitigated_open "$NEW"; report_close "$NEW"
out="$(run_tm_driver)"
if echo "$out" | grep -q "\[FAIL\] threat-model"; then
  pass "T-tm-newest-wins: the newest (incomplete) report governs → [FAIL]"
else
  fail_ "T-tm-newest-wins" "expected [FAIL] threat-model (newest governs); out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -q "2026-07-10_threat-model-validation.md" && echo "$out" | grep -q "TM-002"; then
  pass "T-tm-newest-wins: FAIL cites the newest report + names missing TM-002"
else
  fail_ "T-tm-newest-wins" "expected newest report name + TM-002 named; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-offline-runs: --offline still yields a real threat-model verdict ==="
# ════════════════════════════════════════════════════════════════════
# Unlike the tool-backed arms, threat-model is pure-local parsing and must NOT
# SKIP under --offline (the gate autorun runs offline and needs a real verdict).
setup
write_bible TM-001 TM-002
REP="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$REP"; report_result_row "$REP" TM-001 Pass; report_result_row "$REP" TM-002 Pass
report_unmitigated_open "$REP"; report_close "$REP"
out="$(run_tm_driver --offline)"
if echo "$out" | grep -q "\[PASS\] threat-model"; then
  pass "T-tm-offline-runs: --offline yields a real [PASS] threat-model (not SKIP)"
else
  fail_ "T-tm-offline-runs" "expected [PASS] threat-model under --offline; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -q "\[SKIP\] threat-model"; then
  fail_ "T-tm-offline-runs" "threat-model must NOT SKIP under --offline"
else
  pass "T-tm-offline-runs: threat-model is not downgraded to SKIP under --offline"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-tm-word-boundary: bible TM-001 vs report TM-0011 → TM-001 MISSING ==="
# ════════════════════════════════════════════════════════════════════
# Word-boundary-safe coverage: a report validating TM-0011 must NOT satisfy the
# Bible's TM-001.
setup
write_bible TM-001
REP="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$REP"
report_result_row "$REP" TM-0011 Pass     # a DIFFERENT id, not TM-001
report_unmitigated_open "$REP"
report_close "$REP"
out="$(run_tm_driver)"
if echo "$out" | grep -q "\[FAIL\] threat-model"; then
  pass "T-tm-word-boundary: TM-0011 does NOT satisfy TM-001 → [FAIL]"
else
  fail_ "T-tm-word-boundary" "expected [FAIL] (TM-001 unmatched); out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
if echo "$out" | grep -qE "TM-001( |—|,|$)"; then
  pass "T-tm-word-boundary: the unmatched TM-001 is named"
else
  fail_ "T-tm-word-boundary" "expected TM-001 named; out:
$(echo "$out" | grep -iE 'threat-model' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation: excise # BL-070-TM-COMPARE → missing-id FAIL disappears ==="
# ════════════════════════════════════════════════════════════════════
# Copy the driver, delete the line carrying `# BL-070-TM-COMPARE` (the coverage
# diff that computes which Bible IDs are unvalidated), and re-run the missing-ID
# fixture. Real driver: [FAIL] threat-model (TM-003 unvalidated). Mutant: the
# coverage diff is gone → missing="" → no missing-ID FAIL → [PASS] — proving the
# marked line is load-bearing (remove it → T-tm-missing-id-fail goes RED).
setup
write_bible TM-001 TM-002 TM-003
REP="$TRDIR/2026-07-10_threat-model-validation.md"
report_open "$REP"
report_result_row "$REP" TM-001 Pass
report_result_row "$REP" TM-002 Pass
report_unmitigated_open "$REP"
report_close "$REP"
MUT="$TMP/mut-driver.sh"
grep -v 'BL-070-TM-COMPARE' "$DRIVER" > "$MUT"
chmod +x "$MUT"
if ! grep -q 'BL-070-TM-COMPARE' "$DRIVER"; then
  fail_ "T-mutation" "BL-070-TM-COMPARE marker missing from the REAL driver — nothing to mutate"
elif grep -q 'BL-070-TM-COMPARE' "$MUT"; then
  fail_ "T-mutation" "marker still present after excision — mutation did not apply"
elif ! "$BASH_BIN" -n "$MUT" 2>/dev/null; then
  fail_ "T-mutation" "mutant driver is not syntactically valid after excision"
else
  # Distinct results dirs so the mutant's archive check can't see the real
  # run's leftover file (same wall-clock-second name collision).
  mkdir -p "$TMP/real-rdir" "$TMP/mut-rdir"
  real_out="$( cd "$PROJ" && PATH="$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$TMP/real-rdir" </dev/null 2>&1 )" || true
  mut_out="$( cd "$PROJ" && PATH="$CLEAN_BIN" "$BASH_BIN" "$MUT" \
      --results-dir "$TMP/mut-rdir" </dev/null 2>&1 )" || true
  if echo "$real_out" | grep -q "\[FAIL\] threat-model"; then
    pass "T-mutation: real driver emits [FAIL] threat-model (TM-003 unvalidated)"
  else
    fail_ "T-mutation" "real driver did NOT emit [FAIL] threat-model (fixture wrong?); out:
$(echo "$real_out" | grep -iE 'threat-model' | head)"
  fi
  if echo "$mut_out" | grep -q "\[FAIL\] threat-model"; then
    fail_ "T-mutation" "mutant STILL emitted [FAIL] threat-model — coverage diff not load-bearing (not a proof)"
  else
    pass "T-mutation: mutant (coverage diff stripped) does NOT emit [FAIL] threat-model (RED proof)"
  fi
fi
teardown

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$CLEAN_BIN"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

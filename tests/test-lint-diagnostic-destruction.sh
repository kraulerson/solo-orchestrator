#!/usr/bin/env bash
# tests/test-lint-diagnostic-destruction.sh
#
# Behavior suite for scripts/lint-diagnostic-destruction.sh — the BL-197
# backstop for the DIAGNOSTIC-DESTRUCTION class: an instrument that
# discards the evidence needed to act on the failure it is reporting.
#
# The gating predicate (DD1) is deliberately narrow. It fires only on the
# conjunction of THREE things on ONE line:
#   (1) a command whose diagnostic stream is sent to /dev/null,
#   (2) a `||` short-circuit after that silencer,
#   (3) a failure reporter (fail_ / fail / print_fail / record_init_failure)
#       invoked in that `||` arm.
# That is "the command failed, its diagnostic was thrown away, and the
# message that replaces it is all the reader gets."
#
# Every case below pins one atom of that predicate or one carve-out. The
# carve-outs are not cosmetic — each was measured against the real tree
# before it was written (see the linter header for the counts):
#   • presence probes (`command -v X &>/dev/null || fail "X not found"`)
#     are legitimate and account for 10 of 19 raw hits on today's tree.
#   • `2>&1 >/dev/null` is NOT a silencer — stderr survives to the prior
#     stdout, which is the repo's own capture idiom.
#   • a failure reporter reached by `&&` (the command SUCCEEDED) had no
#     diagnostic to destroy.
#
# Harness convention matches tests/test-lint-fix-functions-stderr.sh:
# per-case fixture repo under a tmpdir, linter copied in, run from the
# fixture root, assert on exit code and output.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-diagnostic-destruction.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/repo"
  mkdir -p "$PROJ/scripts" "$PROJ/tests"
  cp "$LINTER" "$PROJ/scripts/lint-diagnostic-destruction.sh"
  chmod +x "$PROJ/scripts/lint-diagnostic-destruction.sh"
}
teardown() { rm -rf "$TMP"; }

run_lint() {
  ( cd "$PROJ" && bash scripts/lint-diagnostic-destruction.sh "$@" 2>&1 )
  return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: clean fixture (failure message carries the evidence) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/tests/clean.sh" <<'SH'
#!/usr/bin/env bash
out=$(bash -n target.sh 2>&1) && pass "syntax OK" || fail_ "syntax" "syntax ERROR: $out"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T1: a failure message that carries the captured diagnostic exits 0"
else
  fail_ "T1" "expected exit 0, got $rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: >/dev/null 2>&1 then || fail_ → exit 1, names file:line ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/tests/bad-total.sh" <<'SH'
#!/usr/bin/env bash
run_gate --terminal-mode >/dev/null 2>&1 && pass "T2" || fail_ "T2" "docs-only commit blocked"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "tests/bad-total.sh:2"; then
  pass "T2: total silence feeding a || failure report is flagged with file:line"
else
  fail_ "T2" "expected exit 1 + file:line; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: bare 2>/dev/null then || fail → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# The stderr-only spelling is the one that cost the most on the real
# tree: `bash -n f 2>/dev/null && pass || fail "syntax ERROR"` throws
# away the file:line:message that is the WHOLE actionable payload.
setup
cat > "$PROJ/tests/bad-stderr-only.sh" <<'SH'
#!/usr/bin/env bash
bash -n target.sh 2>/dev/null && pass "syntax OK" || fail "syntax ERROR"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "tests/bad-stderr-only.sh:2"; then
  pass "T3: stderr-only silencer feeding a || failure report is flagged"
else
  fail_ "T3" "expected exit 1; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: &>/dev/null then || print_fail → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/bad-amp.sh" <<'SH'
#!/usr/bin/env bash
push_branch main &>/dev/null || { print_fail "Push failed"; return 1; }
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "scripts/bad-amp.sh:2"; then
  pass "T4: the &>/dev/null spelling is flagged too"
else
  fail_ "T4" "expected exit 1; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: presence probe (command -v) → exit 0 (carve-out) ==="
# ════════════════════════════════════════════════════════════════════
# `command -v semgrep &>/dev/null || fail "Semgrep not found"` destroys
# nothing: a presence probe emits no diagnostic, and its non-zero status
# IS the whole message. 10 of the 19 raw hits on the real tree are this.
setup
cat > "$PROJ/scripts/probe.sh" <<'SH'
#!/usr/bin/env bash
command -v semgrep &>/dev/null && print_ok "Semgrep" || fail "Semgrep not found — required for SAST"
type jq >/dev/null 2>&1 || fail "jq not found"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T5: presence probes are carved out, not flagged"
else
  fail_ "T5" "expected exit 0 for presence probes; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: 2>&1 >/dev/null is NOT a silencer → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Order is load-bearing. `2>&1 >/dev/null` points stderr at the PRIOR
# stdout (the capture) and only stdout at /dev/null — the diagnostic
# survives. Flagging it would flag the repo's own evidence-preserving
# idiom, which is the cry-wolf failure mode this lint must avoid.
setup
cat > "$PROJ/tests/reversed.sh" <<'SH'
#!/usr/bin/env bash
err=$(run_gate --terminal-mode 2>&1 >/dev/null) || fail_ "T1" "classifier fired: $err"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6: 2>&1 >/dev/null (stderr survives) is correctly NOT flagged"
else
  fail_ "T6" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: failure reporter reached by && (not ||) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# `ls ... 2>/dev/null && { fail_ "leftover tmpfile"; }` reports on the
# command's SUCCESS. A successful command had no diagnostic to destroy,
# and here the offending filenames reach stdout unsilenced.
setup
cat > "$PROJ/tests/success-arm.sh" <<'SH'
#!/usr/bin/env bash
ls "$D/.claude/"*.tmp 2>/dev/null && { fail_ "P1" "tempfile not cleaned up"; return; }
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T7: a failure reporter on the && (success) arm is not the class"
else
  fail_ "T7" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: silencer with no failure reporter on the line → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/no-reporter.sh" <<'SH'
#!/usr/bin/env bash
git rev-parse --git-dir >/dev/null 2>&1 || return 0
rm -rf "$T" >/dev/null 2>&1 || true
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T8: a silencer without a same-line failure report is out of scope"
else
  fail_ "T8" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9: the whole shape inside a COMMENT → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/tests/commented.sh" <<'SH'
#!/usr/bin/env bash
# Never write: cmd >/dev/null 2>&1 || fail_ "T" "it broke" — BL-197.
echo ok
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T9: the shape quoted in a comment is not flagged"
else
  fail_ "T9" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: exemption marker WITH reason → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/exempted.sh" <<'SH'
#!/usr/bin/env bash
push_branch main 2>/dev/null || push_branch master || { print_fail "Push failed"; return 1; } # lint-diag-ok: first-attempt noise only; the decisive second attempt is unsilenced
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T10: a same-line '# lint-diag-ok: <reason>' exempts the site"
else
  fail_ "T10" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: exemption marker WITHOUT reason → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/empty-exempt.sh" <<'SH'
#!/usr/bin/env bash
run_thing >/dev/null 2>&1 || fail_ "T" "it broke" # lint-diag-ok:
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -qi "reason"; then
  pass "T11: an empty-reason exemption fails (justification is required)"
else
  fail_ "T11" "expected exit 1 with a reason-required diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T12: the shape inside a HEREDOC body → exit 1 (deliberate) ==="
# ════════════════════════════════════════════════════════════════════
# BL-197 instance 3 lived in a heredoc-emitted hook body. This lint
# therefore does NOT skip heredoc bodies — the opposite of the choice
# lint-fix-functions-stderr.sh makes, and the reason that lint could
# never have caught it.
setup
cat > "$PROJ/scripts/emitter.sh" <<'SH'
#!/usr/bin/env bash
write_hook() {
  cat > .git/hooks/pre-commit << 'HOOKEOF'
#!/usr/bin/env bash
scan_index >/dev/null 2>&1 || print_fail "SAST could not run"
HOOKEOF
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "scripts/emitter.sh:5"; then
  pass "T12: heredoc-emitted bodies are scanned (BL-197 instance 3 lived in one)"
else
  fail_ "T12" "expected exit 1 naming the heredoc line; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T13: out-of-scope directory → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
mkdir -p "$PROJ/Reports"
cat > "$PROJ/Reports/sample.sh" <<'SH'
#!/usr/bin/env bash
run_thing >/dev/null 2>&1 || fail_ "R" "it broke"
SH
# An in-scope clean file so the exit 0 proves the scan RAN and skipped
# Reports/ — not that it found nothing to scan and bailed (that path is
# its own exit-2 guard, pinned by T21).
cat > "$PROJ/tests/in-scope-clean.sh" <<'SH'
#!/usr/bin/env bash
echo ok
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T13: files outside the scanned globs are not walked"
else
  fail_ "T13" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T14: --list renders a FAIL row and a PASS row ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/tests/rows.sh" <<'SH'
#!/usr/bin/env bash
run_a >/dev/null 2>&1 || fail_ "A" "a broke"
run_b >/dev/null 2>&1 || fail_ "B" "b broke" # lint-diag-ok: b's diagnostic is captured upstream
SH
out=$(run_lint --list); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "^FAIL" \
   && echo "$out" | grep -q "^PASS" \
   && echo "$out" | grep -q "STATUS"; then
  pass "T14: --list renders the PASS/FAIL roster"
else
  fail_ "T14" "expected a roster with both a FAIL and a PASS row; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T15: --census renders truncated-evidence sites and exits 0 ==="
# ════════════════════════════════════════════════════════════════════
# DD2 (the entry's second candidate shape) is ADVISORY by measurement:
# 489 raw sites on the real tree, so it renders for review and never
# gates. Exit 0 even with rows present is the whole contract.
setup
cat > "$PROJ/tests/trunc.sh" <<'SH'
#!/usr/bin/env bash
fail_ "T1" "gate did not block: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
SH
out=$(run_lint --census); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q "tests/trunc.sh:2"; then
  pass "T15: --census renders truncated-evidence sites without gating"
else
  fail_ "T15" "expected exit 0 + the census row; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T16: a census-only site does NOT gate the default run → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/tests/trunc2.sh" <<'SH'
#!/usr/bin/env bash
fail_ "T1" "gate did not block: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T16: the advisory census never affects the gate's exit status"
else
  fail_ "T16" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T17: bad argument → exit 2 ==="
# ════════════════════════════════════════════════════════════════════
setup
out=$(run_lint --bogus); rc=$?
if [ $rc -eq 2 ] && echo "$out" | grep -qi "usage"; then
  pass "T17: an unknown flag exits 2 with a usage line"
else
  fail_ "T17" "expected exit 2 + usage; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T19: BATTERY — every silencer spelling, every reporter, every control ==="
# ════════════════════════════════════════════════════════════════════
# R-BL197-1. T2/T3/T4 pinned three silencer spellings and one reporter, so
# three mutants survived a 18/0 suite: excising `|2>&-`, excising the `1?`
# atom (which kills `1>/dev/null 2>&1`), and excising `|record_init_failure`
# from the fail-arm regex. ONE fixture now carries EVERY documented spelling
# and EVERY reporter, plus the controls that pin what must NOT fire.
#
# The control lines are as load-bearing as the violations. Lines 12 and 14
# are the two FALSE POSITIVES the reviewer's template exposed (a reporter
# named inside a string, and the whole shape quoted inside an echo); line 13
# is the false NEGATIVE (R-BL197-2 — `grep -w type` read as a presence
# probe). Lines 7-9, 10, 11, 18-19 are the lint's DOCUMENTED BLIND SPOTS,
# pinned here so they stay deliberate rather than becoming accidental:
#   7-9   a `||` arm whose reporter is on the NEXT line (no cross-line
#         inference, by design — see the linter header)
#   10    `if ! cmd >/dev/null 2>&1; then fail_ …; fi` — same line, but the
#         reporter is not in a `||` arm
#   11    a bare `echo "[FAIL] …"` used as the reporter (not in the reporter
#         set — measured to add zero hits on this tree)
#   18-19 `exec 2>/dev/null` silencing a LATER line (no dataflow analysis)
setup
cat > "$PROJ/tests/battery.sh" <<'SH'
#!/usr/bin/env bash
run_x 1>/dev/null 2>&1 || fail_ "p01" "broke"
run_x >/dev/null 2>/dev/null || fail_ "p02" "broke"
run_x 2>/dev/null 1>/dev/null || fail_ "p03" "broke"
run_x >&/dev/null || fail_ "p04" "broke"
run_x 2>&- || fail_ "p05" "broke"
run_x >/dev/null 2>&1 || {
  fail_ "p06" "broke"
}
if ! run_x >/dev/null 2>&1; then fail_ "p07" "broke"; fi
run_x 2>/dev/null || { echo "[FAIL] p08 broke"; FAILED=$((FAILED+1)); }
run_x >/dev/null 2>&1 || echo "note: call fail_ 'x' first"
grep -w type config.txt 2>/dev/null || fail_ "p10" "grep broke"
echo "never write: cmd >/dev/null 2>&1 || fail_ 'x'"
run_x 2>/dev/null || test_fail "p12 broke"
run_x 2> /dev/null || fail_ "p13" "broke"
err=$(run_x 2>&1 >/dev/null) || fail_ "p15" "broke: $err"
exec 2>/dev/null
run_x || fail_ "p16" "broke"
run_x >/dev/null 2>&1 || fail_ "p17" "broke"
run_x &>/dev/null || fail_ "p18" "broke"
run_x >/dev/null 2>&1 || fail "p19 broke"
run_x >/dev/null 2>&1 || print_fail "p20 broke"
run_x >/dev/null 2>&1 || record_init_failure "p21" "broke"
command -v optional_tool >/dev/null 2>&1 || fail_ "p22" "optional_tool not found"
SH
BAT_MUST_FLAG="2 3 4 5 6 13 16 20 21 22 23 24"
BAT_MUST_PASS="7 10 11 12 14 15 17 18 19 25"
TAB=$'\t'
out=$(run_lint --list); rc=$?
bat_missing=""
bat_extra=""
for n in $BAT_MUST_FLAG; do
  echo "$out" | grep -q "^FAIL${TAB}tests/battery.sh:${n}${TAB}" || bat_missing="$bat_missing $n"
done
for n in $BAT_MUST_PASS; do
  if echo "$out" | grep -q "^FAIL${TAB}tests/battery.sh:${n}${TAB}"; then
    bat_extra="$bat_extra $n"
  fi
done
bat_count=$(echo "$out" | grep -c "^FAIL${TAB}tests/battery.sh:")
if [ $rc -eq 1 ] && [ -z "$bat_missing" ] && [ -z "$bat_extra" ] && [ "$bat_count" -eq 12 ]; then
  pass "T19: all 12 battery violations flagged, all 10 controls left alone"
else
  fail_ "T19" "rc=$rc (want 1); flagged=$bat_count (want 12); MISSED:${bat_missing:- none}; FALSE-POSITIVES:${bat_extra:- none}; roster:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T20: a failed mktemp hard-fails (exit 2), never a silent clean scan ==="
# ════════════════════════════════════════════════════════════════════
# R-BL197-5. `tmp="$(mktemp)" || return 0` skipped a whole file and let the
# run finish "OK" — the silent-success sibling of the very class this lint
# polices. A scan that cannot run must say so and exit 2.
setup
mkdir -p "$TMP/shim"
cat > "$TMP/shim/mktemp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$TMP/shim/mktemp"
cat > "$PROJ/tests/plain.sh" <<'SH'
#!/usr/bin/env bash
echo ok
SH
out=$( cd "$PROJ" && PATH="$TMP/shim:$PATH" bash scripts/lint-diagnostic-destruction.sh 2>&1 ); rc=$?
if [ $rc -eq 2 ] && echo "$out" | grep -qi "mktemp"; then
  pass "T20: an unusable tempfile exits 2 and names mktemp"
else
  fail_ "T20" "expected exit 2 naming mktemp; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T21: an EMPTY scannable set hard-fails (exit 2) ==="
# ════════════════════════════════════════════════════════════════════
# Sibling of T20: if the target globs ever match nothing (a renamed tree, a
# bad REPO_ROOT), "OK: no violations" would be a scan of zero files
# reported as a clean bill of health.
setup
out=$(run_lint); rc=$?
if [ $rc -eq 2 ] && echo "$out" | grep -qi "no scannable files"; then
  pass "T21: a scan with nothing in scope exits 2 instead of reporting clean"
else
  fail_ "T21" "expected exit 2 naming an empty scan set; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T18: MERGE GATE — the real repo tree is clean → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
out=$(bash "$LINTER" 2>&1); rc=$?
if [ $rc -eq 0 ]; then
  pass "T18: current repo HEAD carries no unannotated silenced-diagnostic failure reports"
else
  fail_ "T18" "current repo HEAD has BL-197 violations; rc=$rc; output:\n$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

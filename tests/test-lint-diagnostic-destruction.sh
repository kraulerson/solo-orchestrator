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

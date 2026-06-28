#!/usr/bin/env bash
# tests/test-lint-counter-antipattern.sh
#
# Tests for scripts/lint-counter-antipattern.sh — the wave-2 CI backstop
# that bans the `var=$(cmd | grep -c X || echo "0")` counter-capture
# antipattern after the wave-1 sanitizer remediation (PRs #67-#71).
#
# Each test stages a tiny per-case fixture tree, overrides REPO_ROOT
# via a copied linter (so the linter walks the fixture's scripts/ tree
# instead of the real repo), runs the linter, and asserts on exit code
# and stderr. Test 9 is the merge gate: it runs the linter directly
# against the current repo HEAD and requires exit 0 — proof that wave 1
# left no unsanitized sites for this PR to enforce.
#
# Style mirrors tests/test-test-gate-counter-sanitizer.sh (PR #69) and
# tests/test-check-phase-gate-counter-sanitizer.sh (PR #53): set -uo
# pipefail, mktemp fixtures, pass/fail counters, teardown after each.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-counter-antipattern.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Each test builds an isolated fake-repo at $PROJ with a copy of the
# linter at $PROJ/scripts/lint-counter-antipattern.sh — this lets us
# point the linter at fixture trees without touching the real repo.
setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/repo"
  mkdir -p "$PROJ/scripts"
  cp "$LINTER" "$PROJ/scripts/lint-counter-antipattern.sh"
  chmod +x "$PROJ/scripts/lint-counter-antipattern.sh"
}
teardown() { rm -rf "$TMP"; }

# Run the fixture-local linter and capture exit + stderr.
run_lint() {
  ( cd "$PROJ" && bash scripts/lint-counter-antipattern.sh 2>&1 )
  return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: clean fixture (sanitized site) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/clean.sh" <<'SH'
#!/usr/bin/env bash
foo_count=$(grep -c "PATTERN" file.txt 2>/dev/null || echo "0")
case "$foo_count" in ''|*[!0-9]*) foo_count=0 ;; esac
echo "$foo_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T1: clean sanitized capture exits 0"
else
  fail_ "T1" "expected exit 0, got $rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: bare antipattern (no sanitizer) → exit 1, names file:line + var ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/bad.sh" <<'SH'
#!/usr/bin/env bash
bad_count=$(grep -c "PATTERN" file.txt 2>/dev/null || echo "0")
echo "$bad_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "scripts/bad.sh:2" \
   && echo "$out" | grep -q "bad_count"; then
  pass "T2: bare antipattern fails with file:line and var name"
else
  fail_ "T2" "expected exit 1 + file:line:var; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: antipattern + UNRELATED next line → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/unrelated.sh" <<'SH'
#!/usr/bin/env bash
other_count=$(grep -c "X" file.txt 2>/dev/null || echo "0")
echo "doing something unrelated here"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "other_count"; then
  pass "T3: antipattern with unrelated follow-up fails"
else
  fail_ "T3" "expected exit 1; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: antipattern + correct case-statement → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/good.sh" <<'SH'
#!/usr/bin/env bash
sev1_count=$(grep -c 'SEV-1' BUGS.md 2>/dev/null | tr -d '[:space:]' || echo "0")
case "$sev1_count" in ''|*[!0-9]*) sev1_count=0 ;; esac
echo "$sev1_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T4: antipattern + matching case-statement passes"
else
  fail_ "T4" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: antipattern + case-statement with WRONG var name → exit 1 (copy-paste guard) ==="
# ════════════════════════════════════════════════════════════════════
setup
# This is the copy-paste-bug class: the sanitizer was duplicated from
# a sibling site and never renamed. The lint MUST catch this by
# requiring the case-statement var name to match the capture's var name.
cat > "$PROJ/scripts/copypaste.sh" <<'SH'
#!/usr/bin/env bash
my_count=$(grep -c "X" file.txt 2>/dev/null || echo "0")
case "$other_count" in ''|*[!0-9]*) other_count=0 ;; esac
echo "$my_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "my_count" \
   && echo "$out" | grep -q "sanitizer-var-mismatch\|different var name"; then
  pass "T5: copy-paste var-name mismatch is detected"
else
  fail_ "T5" "expected exit 1 + mismatch diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: '|| true' variant → exit 0 (out-of-scope, deliberate) ==="
# ════════════════════════════════════════════════════════════════════
# DELIBERATE EXCLUSION: this linter targets only `|| echo \"0\"` (the
# class with the documented "0\\n0" concat failure mode). The `|| true`
# variant has a different failure mode (silent empty-string capture)
# and is scoped to a separate follow-up PR. Keeping these out of scope
# keeps the merge-gate signal focused on the defect class wave 1 fixed.
setup
cat > "$PROJ/scripts/or-true.sh" <<'SH'
#!/usr/bin/env bash
silent_count=$(grep -c "X" file.txt 2>/dev/null || true)
echo "$silent_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6: '|| true' variant is out of scope (passes)"
else
  fail_ "T6" "expected exit 0 for out-of-scope variant; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: allowlist marker WITH reason → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/allowed.sh" <<'SH'
#!/usr/bin/env bash
weird_count=$(grep -c "X" file.txt 2>/dev/null || echo "0") # lint-counter-antipattern: allow deliberate reproduction of upstream behavior under test
echo "$weird_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T7: allowlist marker with reason passes"
else
  fail_ "T7" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: allowlist marker WITHOUT reason → exit 1 (justification required) ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/empty-allow.sh" <<'SH'
#!/usr/bin/env bash
empty_count=$(grep -c "X" file.txt 2>/dev/null || echo "0") # lint-counter-antipattern: allow
echo "$empty_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -qi "empty\|reason"; then
  pass "T8: empty-reason allowlist marker fails (justification required)"
else
  fail_ "T8" "expected exit 1 with reason-required diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9: MERGE GATE — run linter against current repo HEAD → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# This is the wave-2 acceptance criterion: wave 1 (PRs #67-#71) is
# claimed to have remediated every unsanitized counter-capture site in
# the in-tree code; this test PROVES that claim by running the same
# linter that CI runs and requiring exit 0. If any unsanitized site
# slipped past wave 1's audit, this test fails and the PR cannot
# merge until the site is either sanitized or allowlisted with reason.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ $rc -eq 0 ]; then
  pass "T9: current repo HEAD is lint-clean (wave 1 remediation verified)"
else
  fail_ "T9" "current repo HEAD has unsanitized antipattern sites; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: skip-paths — antipattern in Reports/ → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Reports/, docs/, templates/, and .git/ are out of the walk: those
# trees host UAT report artifacts and templated content that may
# legitimately quote the antipattern in prose or sample code. The
# walk-globs already exclude them, but T10 makes the exclusion an
# enforced contract so a future glob expansion can't silently start
# linting documentation prose.
setup
mkdir -p "$PROJ/Reports"
cat > "$PROJ/Reports/sample-output.sh" <<'SH'
#!/usr/bin/env bash
# This file lives under Reports/ — should be skipped by the linter.
ignored_count=$(grep -c "X" file.txt 2>/dev/null || echo "0")
echo "$ignored_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T10: antipattern under Reports/ is correctly skipped"
else
  fail_ "T10" "expected exit 0 (Reports/ should be skipped); rc=$rc; output:\n$out"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

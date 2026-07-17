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
echo "=== T6: '|| true' variant → exit 1 (now in scope, cycle-8 extension) ==="
# ════════════════════════════════════════════════════════════════════
# Cycle 8 follow-up to PR #72: this linter now covers the `|| true` and
# `|| :` IN-subshell fallback variants in addition to `|| echo "0"`.
# All three leave the capture in a non-numeric or empty state on the
# inner command's non-zero exit and break downstream arithmetic
# identically. The fix pattern is the same canonical case-statement
# sanitizer on the immediately-following line.
setup
cat > "$PROJ/scripts/or-true.sh" <<'SH'
#!/usr/bin/env bash
silent_count=$(grep -c "X" file.txt 2>/dev/null || true)
echo "$silent_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "scripts/or-true.sh:2" \
   && echo "$out" | grep -q "silent_count"; then
  pass "T6: '|| true' in-subshell fallback is now flagged with file:line + var"
else
  fail_ "T6" "expected exit 1 + file:line:var for '|| true'; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6b: '|| true' variant + sanitizer on next line → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Confirms the SAME canonical case-statement sanitizer that fixes the
# `|| echo "0"` form also satisfies the lint for the `|| true` and
# `|| :` forms. This is the documented fix pattern at every cycle-8
# remediation site (scripts/validate.sh, scripts/resume.sh, etc.).
setup
cat > "$PROJ/scripts/or-true-fixed.sh" <<'SH'
#!/usr/bin/env bash
silent_count=$(grep -c "X" file.txt 2>/dev/null || true)
case "$silent_count" in ''|*[!0-9]*) silent_count=0 ;; esac
colon_count=$(grep -c "Y" file.txt 2>/dev/null || :)
case "$colon_count" in ''|*[!0-9]*) colon_count=0 ;; esac
echo "$silent_count $colon_count"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6b: sanitized '|| true' and '|| :' captures pass"
else
  fail_ "T6b" "expected exit 0 for sanitized variants; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6c: outer-OR idiom 'var=\$(cmd) || var=0' → exit 0 (regression guard) ==="
# ════════════════════════════════════════════════════════════════════
# REGRESSION GUARD for the structurally-distinct outer-OR idiom used
# at scripts/check-phase-gate.sh:427. Here the `||` lives AFTER the
# subshell's closing `)`, NOT inside it. Bash semantics: when grep -c
# exits 1 on zero matches, the assignment statement inherits that
# non-zero exit, which fires the outer `||`, which cleanly assigns
# `var=0` exactly once. There is no "0\n0" concat, no silent empty
# capture, no broken arithmetic — this is the CORRECT idiom and the
# lint must NEVER flag it. The cycle-8 regex extension preserved the
# `\) $` anchor on the in-subshell match precisely to keep this site
# out of scope; T6c locks that property in.
setup
cat > "$PROJ/scripts/outer-or.sh" <<'SH'
#!/usr/bin/env bash
# This is the exact shape at scripts/check-phase-gate.sh:427.
todo_count=$(grep -c "TODO" .github/workflows/release.yml 2>/dev/null) || todo_count=0
if [ "$todo_count" -gt 0 ]; then
  echo "warn: $todo_count TODOs remain"
fi
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6c: outer-OR idiom is correctly NOT flagged"
else
  fail_ "T6c" "REGRESSION: outer-OR idiom was flagged (must stay out of scope); rc=$rc; output:\n$out"
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

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: BL-121 — basic-mode sed alternation (GNU-only) → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# In a BASIC-regex sed program, backslash-pipe is alternation on GNU but a
# LITERAL on BSD/macOS — a range terminator carrying it never matches and the
# range runs to EOF (BL-121: the MVP-Cutline counter reported 68 vs the true
# 3 and hard-blocked the production gate on every Mac).
setup
cat > "$PROJ/scripts/bsd-trap.sh" <<'SH'
#!/usr/bin/env bash
items=$(sed -n '/Must-Have/,/Should-Have\|---/p' FILE.md | grep -c x)
case "$items" in ''|*[!0-9]*) items=0 ;; esac
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "bsd-trap.sh" && echo "$out" | grep -qi "sed"; then
  pass "T11: basic-mode sed alternation flagged"
else
  fail_ "T11" "expected exit 1 naming bsd-trap.sh with a sed-alternation message; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T12: BL-121 — sed -E/-r with escaped-literal pipe → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# In ERE mode a backslash-pipe is an ESCAPED LITERAL pipe — the correct idiom
# for parsing |-delimited Markdown tables (check-phase-gate.sh does exactly
# this). The rule must not flag it.
setup
cat > "$PROJ/scripts/ere-ok.sh" <<'SH'
#!/usr/bin/env bash
approver=$(echo "$row" | sed -E 's/.*\*\*Approver\*\*[[:space:]]*\|[[:space:]]*//; s/[[:space:]]*\|.*$//')
cell=$(echo "$row" | sed -nr 's/a\|b/x/p')
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T12: ERE-mode sed with escaped literal pipe is exempt"
else
  fail_ "T12" "expected exit 0 (sed -E/-r backslash-pipe is an escaped LITERAL, the table-parsing idiom); rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T13: BL-121 — sed alternation with allowlist marker + reason → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/allowed.sh" <<'SH'
#!/usr/bin/env bash
items=$(sed -n '/A\|B/p' FILE.md)   # lint-counter-antipattern: allow gnu-sed-only fixture, exercised on Linux CI only
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T13: allowlisted sed alternation passes"
else
  fail_ "T13" "expected exit 0 with allowlist marker; rc=$rc; output:\n$out"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

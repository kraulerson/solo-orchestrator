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

# Same, but `--list` and STDOUT ONLY — the PASS/FAIL inventory table.
# T14-T19 (BL-191) assert on ROW CONTENT and ROW ORDER, which stderr
# diagnostics would interleave into, so they need the clean table.
run_lint_list() {
  ( cd "$PROJ" && bash scripts/lint-counter-antipattern.sh --list 2>/dev/null )
  return $?
}

# Data rows only. Two non-row lines share the table's STDOUT and must
# both come off: the STATUS/FILE:LINE/VAR/DETAIL header, and — on a
# clean run — the trailing "OK: no counter-capture antipatterns found."
# success line, which the linter prints AFTER the table.
list_rows() {
  printf '%s\n' "$1" | sed '1d' \
    | grep -v '^OK: no counter-capture antipatterns found\.$'
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

# ════════════════════════════════════════════════════════════════════
# T14-T19 — BL-191 single-pass characterization guards.
#
# `scan_file` used to fork `echo "$line" | grep -Eq …` once PER LINE for
# each of the two rules; BL-191 replaced that with ONE `grep -naE` pass
# per RULE per FILE plus an ordered merge of the two hit lists. These
# six cases pin the properties that the per-line → per-file move can
# silently break and that NOTHING ELSE in this suite covers. They are
# characterization tests: each one passes against the pre-BL-191
# implementation too, which is the point — they are the byte-identity
# contract, not a new feature.
#
#   T14  the allowlist `continue` — a line carrying BOTH rules with an
#        allowlist marker evaluates the counter rule and then SKIPS the
#        BL-121 sed rule entirely. Easy to lose: a merged walk that
#        evaluates both rules unconditionally emits an extra row.
#   T15  a line carrying BOTH rules WITHOUT a marker fires both, and the
#        counter row is emitted BEFORE the sed row. Pins rule order.
#   T16  a violation on the FINAL line of a file with NO trailing
#        newline: the N+1 lookahead must read as empty, not fall off.
#   T17  walk order — the LIST_ROWS sequence is TARGET_GLOBS order, then
#        ascending line number within a file.
#   T18  pure-comment lines are skipped for the sed rule (the counter
#        regex is `^`-anchored to an identifier so it can never match a
#        comment; the sed regex is NOT anchored, so the comment skip is
#        the only thing holding it off).
#   T19  the `sed -E` exemption is PER LINE, not per file — an exempt
#        ERE invocation on one line must not exempt a basic-mode
#        alternation on another. A whole-file boolean fails this.
# ════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T14: BL-191 — allowlisted counter line ALSO matching the sed rule → sed rule suppressed ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/both-allowed.sh" <<'SH'
#!/usr/bin/env bash
items=$(sed -n '/A\|B/p' FILE.md | grep -c x || echo "0") # lint-counter-antipattern: allow gnu-sed-only fixture, exercised on Linux CI only
SH
rows=$(run_lint_list); rc=$?
data=$(list_rows "$rows")
nrows=$(printf '%s\n' "$data" | grep -c .)
if [ $rc -eq 0 ] \
   && [ "$nrows" -eq 1 ] \
   && printf '%s\n' "$data" | grep -q "items" \
   && ! printf '%s\n' "$data" | grep -q "sed-alternation"; then
  pass "T14: allowlist marker short-circuits the line — counter row only, no sed row"
else
  fail_ "T14" "expected exit 0 and exactly 1 counter row with NO sed-alternation row; rc=$rc; nrows=$nrows; rows:\n$data"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T15: BL-191 — unmarked line matching BOTH rules fires both, counter row FIRST ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/both-bad.sh" <<'SH'
#!/usr/bin/env bash
items=$(sed -n '/A\|B/p' FILE.md | grep -c x || echo "0")
echo "$items"
SH
rows=$(run_lint_list); rc=$?
data=$(list_rows "$rows")
first=$(printf '%s\n' "$data" | sed -n '1p')
second=$(printf '%s\n' "$data" | sed -n '2p')
if [ $rc -eq 1 ] \
   && printf '%s' "$first"  | grep -q 'scripts/both-bad.sh:2.*items.*missing-sanitizer' \
   && printf '%s' "$second" | grep -q 'scripts/both-bad.sh:2.*sed-alternation.*gnu-only-sed-alternation'; then
  pass "T15: both rules fire on one line, counter row emitted before sed row"
else
  fail_ "T15" "expected 2 rows for line 2, counter first then sed; rc=$rc; rows:\n$data"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T16: BL-191 — violation on the LAST line, file has no trailing newline → still flagged ==="
# ════════════════════════════════════════════════════════════════════
setup
printf '#!/usr/bin/env bash\ntail_count=$(grep -c "X" file.txt 2>/dev/null || echo "0")' \
  > "$PROJ/scripts/tail-nonl.sh"
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "scripts/tail-nonl.sh:2" \
   && echo "$out" | grep -q "tail_count"; then
  pass "T16: last-line violation without trailing newline is flagged at the right line"
else
  fail_ "T16" "expected exit 1 naming scripts/tail-nonl.sh:2 and tail_count; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T17: BL-191 — row order is TARGET_GLOBS walk order, then ascending line number ==="
# ════════════════════════════════════════════════════════════════════
setup
mkdir -p "$PROJ/scripts/lib" "$PROJ/tests"
cat > "$PROJ/scripts/aaa.sh" <<'SH'
#!/usr/bin/env bash
one=$(grep -c "X" f.txt 2>/dev/null || echo "0")
case "$one" in ''|*[!0-9]*) one=0 ;; esac
echo "$one"
two=$(grep -c "Y" f.txt 2>/dev/null || echo "0")
case "$two" in ''|*[!0-9]*) two=0 ;; esac
SH
cat > "$PROJ/scripts/lib/zzz.sh" <<'SH'
#!/usr/bin/env bash
three=$(grep -c "X" f.txt 2>/dev/null || echo "0")
case "$three" in ''|*[!0-9]*) three=0 ;; esac
SH
cat > "$PROJ/tests/ttt.sh" <<'SH'
#!/usr/bin/env bash
four=$(grep -c "X" f.txt 2>/dev/null || echo "0")
case "$four" in ''|*[!0-9]*) four=0 ;; esac
SH
cat > "$PROJ/init.sh" <<'SH'
#!/usr/bin/env bash
echo "scaffolder"
five=$(grep -c "X" f.txt 2>/dev/null || echo "0")
case "$five" in ''|*[!0-9]*) five=0 ;; esac
SH
rows=$(run_lint_list); rc=$?
actual=$(list_rows "$rows" | cut -f2)
expected='scripts/aaa.sh:2
scripts/aaa.sh:5
scripts/lib/zzz.sh:2
tests/ttt.sh:2
init.sh:3'
if [ $rc -eq 0 ] && [ "$actual" = "$expected" ]; then
  pass "T17: inventory row order follows the glob walk then line number"
else
  fail_ "T17" "row order drifted; rc=$rc\nexpected:\n$expected\nactual:\n$actual"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T18: BL-191 — sed alternation inside a pure COMMENT line is skipped ==="
# ════════════════════════════════════════════════════════════════════
setup
{
  printf '#!/usr/bin/env bash\n'
  printf '# legacy: items=$(sed -n %s/Must-Have/,/Should-Have\\|---/p%s F.md | grep -c x)\n' "'" "'"
  printf '\t# tab-indented note about sed -n %s/A\\|B/p%s\n' "'" "'"
  printf '   # space-indented note about sed -n %s/C\\|D/p%s\n' "'" "'"
  printf 'echo ok\n'
} > "$PROJ/scripts/commented.sh"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T18: commented-out sed alternation (tab- and space-indented) is skipped"
else
  fail_ "T18" "expected exit 0 — comment lines must be skipped for BOTH rules; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T19: BL-191 — the 'sed -E' exemption is PER LINE, not per file ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/mixed-sed.sh" <<'SH'
#!/usr/bin/env bash
cell=$(echo "$row" | sed -E 's/a\|b/x/')
items=$(sed -n '/A\|B/p' FILE.md)
SH
out=$(run_lint); rc=$?
hits=$(printf '%s\n' "$out" | grep -c 'lint-counter-antipattern: GNU-only sed alternation')
if [ $rc -eq 1 ] \
   && [ "$hits" -eq 1 ] \
   && echo "$out" | grep -q "scripts/mixed-sed.sh:3" \
   && ! echo "$out" | grep -q "scripts/mixed-sed.sh:2"; then
  pass "T19: line 3 flagged, line 2's sed -E exemption does not leak to it"
else
  fail_ "T19" "expected exactly one sed diagnostic, on line 3 only; rc=$rc; hits=$hits; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T20: BL-191 — a NUL byte must not hide a violation (pins grep -a) ==="
# ════════════════════════════════════════════════════════════════════
# BL-191's rewrite diverges from the pre-BL-191 lint on exactly one
# input domain: NUL-BEARING LINES. This case pins the two arms where it
# catches MORE. T21 pins the arm where it catches LESS — read both
# before concluding anything about the direction of the change.
#
#   • BEFORE: `scan_file` read each line into a bash variable. A bash
#     string cannot hold a NUL, so a NUL anywhere on a line TRUNCATED
#     it there. `near_count=$(grep -c "X<NUL>Y" f || echo "0")` became
#     `near_count=$(grep -c "X` — which matches nothing, so the
#     unsanitized capture was silently NOT reported.
#   • AFTER, without `-a`: whole-file grep classifies a NUL-bearing
#     file as binary and answers "Binary file … matches" instead of
#     numbered lines. That is WORSE than the old miss — the line-number
#     parse then feeds a non-number to `[ … -le … ]`, and the run ends
#     "OK: no counter-capture antipatterns found." with EXIT 0. A false
#     clean over a file that contains a real violation.
#   • AFTER, with `-a`: the raw line is matched and the violation is
#     reported. That is the behaviour pinned here.
#
# Both arms below therefore go RED if `-a` is dropped from the rule
# passes. Case (a) also holds on the old implementation; case (b) is
# the intentional improvement.
setup
# (a) NUL on an unrelated line — old and new agree, file still scanned
printf '#!/usr/bin/env bash\n# nul here: \000 end\nfar_count=$(grep -c "X" f.txt 2>/dev/null || echo "0")\n' \
  > "$PROJ/scripts/nul-far.sh"
# (b) NUL ON the violating line — the truncation blind spot
printf '#!/usr/bin/env bash\nnear_count=$(grep -c "X\000Y" f.txt 2>/dev/null || echo "0")\n' \
  > "$PROJ/scripts/nul-near.sh"
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "scripts/nul-far.sh:3" \
   && echo "$out" | grep -q "scripts/nul-near.sh:2" \
   && ! echo "$out" | grep -qi "binary file" \
   && ! echo "$out" | grep -q "OK: no counter-capture antipatterns found"; then
  pass "T20: NUL-bearing files are scanned as text — both violations reported"
else
  fail_ "T20" "expected exit 1 naming nul-far.sh:3 AND nul-near.sh:2, with no 'Binary file' and no false OK; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T21: BL-191 — NUL-bearing line where the rewrite catches LESS (widened exemption) ==="
# ════════════════════════════════════════════════════════════════════
# THE COUNTERWEIGHT TO T20, and the reason the divergence must be
# described as "NUL-bearing lines behave differently" rather than
# "the rewrite catches more".
#
# The fixture is one raw line: a REAL basic-mode sed alternation, then a
# NUL, then a `sed -E` mention in a trailing comment.
#   • pre-BL-191: bash `read` truncated the line at the NUL, so the
#     exemption string was never seen -> the BL-121 rule FIRED (exit 1).
#   • post-BL-191: raw-byte evaluation sees the whole line, and
#     SED_ERE_FLAG_RE is UNANCHORED — any `sed -E` string anywhere on the
#     line exempts it — so the line is EXEMPT (exit 0).
#
# ROOT CAUSE IS PRE-EXISTING, NOT INTRODUCED. Strip the NUL from this
# same line and both implementations exempt it, byte-identically. What
# BL-191 changed is how much of a NUL-bearing line the exemption can
# see, not the exemption's scope.
#
# This asserts the CURRENT (exit 0) behaviour deliberately, as
# characterization. It is NOT an endorsement: narrowing
# SED_ERE_FLAG_RE — e.g. anchoring it to the sed invocation rather than
# the whole line, or stripping trailing comments first — is a live
# improvement, and it SHOULD flip this test. A failure here means
# someone tightened the exemption; update this case, do not widen the
# regex back.
setup
printf '#!/usr/bin/env bash\nitems=$(sed -n %s/A\\|B/p%s F.md)\000# sed -E note\n' "'" "'" \
  > "$PROJ/scripts/nul-ere.sh"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ] && ! echo "$out" | grep -q "nul-ere.sh"; then
  pass "T21: NUL-bearing line with a post-NUL 'sed -E' string is exempt (documented widened-exemption arm)"
else
  fail_ "T21" "expected exit 0 with no nul-ere.sh row — if the exemption scope was deliberately TIGHTENED, update this case rather than reverting; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T22: BL-191 — an UNREADABLE target exits 2, never a silent clean pass ==="
# ════════════════════════════════════════════════════════════════════
# The single-pass rule passes originally carried `2>/dev/null`, which
# made an unreadable file report clean with NO diagnostic at all. The
# header documents `2 — invocation / I/O error`; BL-191-UNREADABLE-IS-
# EXIT-2 honours it. Pinned here because "reports clean" is precisely
# the failure a lint must never have.
setup
cat > "$PROJ/scripts/unreadable.sh" <<'SH'
#!/usr/bin/env bash
hidden=$(grep -c "X" f.txt 2>/dev/null || echo "0")
SH
chmod 000 "$PROJ/scripts/unreadable.sh"
if [ -r "$PROJ/scripts/unreadable.sh" ]; then
  # Running as root (or on a filesystem that ignores mode bits): chmod
  # 000 is not enforceable, so the precondition cannot be staged. Say so
  # LOUDLY rather than passing a test that proved nothing.
  echo "  [SKIP] T22: chmod 000 is not enforceable here (root or permissive fs) — arm not exercised"
else
  out=$(run_lint); rc=$?
  if [ $rc -eq 2 ] \
     && echo "$out" | grep -q "cannot read" \
     && echo "$out" | grep -q "unreadable.sh" \
     && ! echo "$out" | grep -q "OK: no counter-capture antipatterns found"; then
    pass "T22: unreadable target exits 2 with a diagnostic, not a silent clean pass"
  else
    fail_ "T22" "expected exit 2 naming the unreadable file, with no clean-pass line; rc=$rc; output:\n$out"
  fi
fi
chmod 644 "$PROJ/scripts/unreadable.sh" 2>/dev/null
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

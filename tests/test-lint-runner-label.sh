#!/usr/bin/env bash
# tests/test-lint-runner-label.sh — pins scripts/lint-runner-label.sh
# (`## BL-358:`, "The runner label"): every runs-on line in tests.yml and
# lint.yml names the label RUNNER_LABEL holds and carries the label's marker,
# and a line that does not is failed by file, line and job.
#
#   R  the lint over this repository's own two workflows, and over copies of
#      them with one line set back to ubuntu-latest or stripped of its marker
#   U  fixtures: scratch workflows passed as arguments; no case edits the
#      real files
#   B  moving to a new image, rehearsed on copies: RUNNER_LABEL and the
#      runs-on lines change together, and the lines alone fail
#   M  one mutant per marked line of the lint (two on the marker check), each
#      on a copy, each found by its end-of-line marker and asserted to have
#      landed; each must turn its killer case's verdict around
#
# The label is never written here. It is read from the lint's RUNNER_LABEL
# line (`# BL-358-LABEL-VALUE`), and every fixture, pattern and expected
# message is built from it: a label written out here turns this suite red at
# the bump the lint documents (RUNNER_LABEL and every runs-on line, nothing
# else), as it did until 2026-11-01 (`## BL-358:`, "The check").
#
# This file is in lint-bl-markers' code surface, so every marker-shaped token
# below defines a marker on the real tree. They are all `BL-358-…`, which
# names a real entry.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-runner-label.sh"
WF_TESTS="$REPO_ROOT/.github/workflows/tests.yml"
WF_LINT="$REPO_ROOT/.github/workflows/lint.yml"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
# A grep that reads all of its input, so the writer piped into it never takes
# SIGPIPE under pipefail (#435, `## BL-183:`).
_gq() { grep "$@" >/dev/null; }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

if [ ! -f "$LINT" ]; then
  echo "  [FAIL] setup — $LINT not found"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# LABEL is the label under test. Setup takes a label of letters, digits, `.`,
# `_` and `-` only and fails on anything else, so no fixture depends on how
# the shell, a regex or YAML would read a stranger character. Of those only
# `.` means anything to a regex, so LABEL_RE brackets it, which reads the same
# in a BRE, an ERE and an awk -v string (no backslash for -v to unescape). The
# fixtures' wrong label is ubuntu-latest, so LABEL must not be it.
LABEL="$(sed -n 's/^RUNNER_LABEL="\([^"]*\)"[[:space:]]*# BL-358-LABEL-VALUE$/\1/p' "$LINT")"
case "$LABEL" in
  ''|*[![:alnum:]._-]*|ubuntu-latest)
    echo "  [FAIL] setup — no usable label on the RUNNER_LABEL line of $LINT (read: '$LABEL'): it must be one line, and only letters, digits, '.', '_' and '-', and not ubuntu-latest"
    echo ""
    echo "Results: 0 passed, 1 failed"
    exit 1 ;;
esac
LABEL_RE="$(printf '%s\n' "$LABEL" | sed 's/[.]/[.]/g')"

OK_LINE="runs-on: $LABEL   # BL-358-RUNNER-LABEL"

# mk_wf <file> <runs-on-line>... — a workflow whose first job, `ok`, is
# canonical; each further argument is one more job, `bad1`, `bad2`, …, whose
# runs-on line is that argument verbatim, indented four spaces.
mk_wf() {
  local f="$1" i=0 l=""
  shift
  {
    printf 'name: fixture\n\non:\n  pull_request:\n\njobs:\n'
    printf '  ok:\n    %s\n    steps:\n      - run: echo ok\n' "$OK_LINE"
    for l in "$@"; do
      i=$((i + 1))
      printf '  bad%s:\n    %s\n    steps:\n      - run: echo bad\n' "$i" "$l"
    done
  } > "$f"
}

run_lint() {   # run_lint <lint> [<arg>...] → sets RC, OUT
  local l="$1"
  shift
  OUT="$(bash "$l" "$@" 2>&1)"; RC=$?
  return 0
}

# _line_eq <file> <line> — the number of the first line that is exactly <line>
_line_eq() { awk -v s="$2" '$0 == s { print NR; exit }' "$1"; }

# _fails <out> — how many [FAIL] lines the lint printed
_fails() { printf '%s\n' "$1" | grep -c '^\[FAIL\] lint-runner-label: '; }

# _swap <marker> <line> <src> <dst> — <src> with the one line that ends with
# <marker> replaced by <line>, verbatim (ENVIRON, so no escape or `&` rule
# touches it); rc 3 unless exactly one line ended with it.
_swap() {
  M_MK="$1" M_REPL="$2" awk '
    { m = ENVIRON["M_MK"]; t = length($0) - length(m) + 1 }
    t >= 1 && substr($0, t) == m { print ENVIRON["M_REPL"]; n++; next }
    { print }
    END { exit (n == 1 ? 0 : 3) }' "$3" > "$4"
}

# _rewrite <src> <job> <from-ere> <to> <dst> — <src> with the first runs-on line
# after job <job>'s key rewritten (awk sub); rc 3 unless exactly one changed.
_rewrite() {
  awk -v job="  $2:" -v from="$3" -v to="$4" '
    $0 == job { want = 1 }
    want && /^[[:space:]]*runs-on:/ { n += sub(from, to); want = 0 }
    { print }
    END { exit (n == 1 ? 0 : 3) }' "$1" > "$5"
}

echo "=== R — the repository's own workflows ==="

WANT_N="$(cat "$WF_TESTS" "$WF_LINT" | grep -c '^[[:space:]]*runs-on:')"
run_lint "$LINT"
R_N="$(printf '%s\n' "$OUT" | sed -n 's/^OK: \([0-9][0-9]*\) runs-on line.*/\1/p')"
if [ "$RC" -eq 0 ] && [ "$WANT_N" -gt 0 ] && [ "$R_N" = "$WANT_N" ]; then
  pass "R1 — tests.yml and lint.yml pass, and the lint read all $WANT_N runs-on lines"
else
  fail_ "R1" "rc=$RC counted=${R_N:-none} want=$WANT_N out=$(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
fi

R="$(newtmp)"
if _rewrite "$WF_LINT" counter-antipattern-lint "$LABEL_RE" 'ubuntu-latest' "$R/lint.yml"; then
  ln="$(awk '/^[[:space:]]*runs-on: ubuntu-latest/ { print NR; exit }' "$R/lint.yml")"
  run_lint "$LINT" "$WF_TESTS" "$R/lint.yml"
  if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
    && printf '%s\n' "$OUT" | _gq -F "$R/lint.yml:$ln (job counter-antipattern-lint): runs on \`ubuntu-latest\`, not \`$LABEL\`"; then
    pass "R2 — one lint.yml job set back to ubuntu-latest fails, that line alone, by file, line and job"
  else
    fail_ "R2" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
else
  fail_ "R2 setup" "the copy of lint.yml did not get exactly one ubuntu-latest line"
fi

if _rewrite "$WF_TESTS" unit '[[:space:]]*# BL-358-RUNNER-LABEL' '' "$R/tests.yml"; then
  ln="$(awk '/^  unit:$/ { j = 1 } j && /^[[:space:]]*runs-on:/ { print NR; exit }' "$R/tests.yml")"
  run_lint "$LINT" "$R/tests.yml" "$WF_LINT"
  if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
    && printf '%s\n' "$OUT" | _gq -F "$R/tests.yml:$ln (job unit): no \`# BL-358-RUNNER-LABEL\` after the label"; then
    pass "R3 — tests.yml's unit job without its marker fails, that line alone, by file, line and job"
  else
    fail_ "R3" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
else
  fail_ "R3 setup" "the copy of tests.yml did not lose exactly one marker"
fi

echo "=== U — fixtures ==="

U1="$(newtmp)"; mk_wf "$U1/wf.yml"
run_lint "$LINT" "$U1/wf.yml"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 1 runs-on line(s) in 1 workflow(s)'; then
  pass "U1 — a canonical runs-on line passes"
else
  fail_ "U1" "rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
fi

U2="$(newtmp)"; mk_wf "$U2/wf.yml" 'runs-on: ubuntu-latest   # BL-358-RUNNER-LABEL'
ln="$(_line_eq "$U2/wf.yml" '    runs-on: ubuntu-latest   # BL-358-RUNNER-LABEL')"
run_lint "$LINT" "$U2/wf.yml"
if [ "$RC" -eq 1 ] \
  && printf '%s\n' "$OUT" | _gq -F "$U2/wf.yml:$ln (job bad1): runs on \`ubuntu-latest\`, not \`$LABEL\`" \
  && printf '%s\n' "$OUT" | _gq -F 'change RUNNER_LABEL in scripts/lint-runner-label.sh, the one place this check and its suite read the label from'; then
  pass "U2 — ubuntu-latest fails by file, line and job, and the message says where the label is changed"
else
  fail_ "U2" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

U3="$(newtmp)"; mk_wf "$U3/wf.yml" "runs-on: $LABEL"
ln="$(_line_eq "$U3/wf.yml" "    runs-on: $LABEL")"
run_lint "$LINT" "$U3/wf.yml"
if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
  && printf '%s\n' "$OUT" | _gq -F "$U3/wf.yml:$ln (job bad1): no \`# BL-358-RUNNER-LABEL\` after the label"; then
  pass "U3 — the right label without its marker fails by name, as a missing marker only"
else
  fail_ "U3" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

U4="$(newtmp)"; mk_wf "$U4/clean.yml"; mk_wf "$U4/dirty.yml" 'runs-on: ubuntu-latest'
ln="$(_line_eq "$U4/dirty.yml" '    runs-on: ubuntu-latest')"
run_lint "$LINT" "$U4/clean.yml" "$U4/dirty.yml"
if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "2" ] \
  && printf '%s\n' "$OUT" | _gq -F "$U4/dirty.yml:$ln (job bad1): runs on \`ubuntu-latest\`" \
  && printf '%s\n' "$OUT" | _gq -F "$U4/dirty.yml:$ln (job bad1): no \`# BL-358-RUNNER-LABEL\`" \
  && ! printf '%s\n' "$OUT" | _gq -F "$U4/clean.yml:"; then
  pass "U4 — of two workflows only the bad one is named, with both of its faults"
else
  fail_ "U4" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

# U5 — every other way to write runs-on is not the canonical line. Each fixture
# also holds the canonical job `ok`, so a check that skipped the bad line would
# pass the whole file.
u5() {   # u5 <id> <expected-text> <runs-on-line>
  local d="" f="" ln="" okl=""
  d="$(newtmp)"; f="$d/wf.yml"
  mk_wf "$f" "$3"
  ln="$(_line_eq "$f" "    $3")"
  okl="$(_line_eq "$f" "    $OK_LINE")"
  run_lint "$LINT" "$f"
  if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F "$f:$ln (job bad1): $2" \
    && ! printf '%s\n' "$OUT" | _gq -F "$f:$okl "; then
    pass "$1 — \`$3\` fails by name: $2"
  else
    fail_ "$1" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
}
u5 U5a 'runs on `['"$LABEL"']`'                        'runs-on: ['"$LABEL"']   # BL-358-RUNNER-LABEL'
u5 U5b 'runs on `"'"$LABEL"'"`'                        'runs-on: "'"$LABEL"'"   # BL-358-RUNNER-LABEL'
u5 U5c 'runs on `${{ matrix.os }}`'                    'runs-on: ${{ matrix.os }}   # BL-358-RUNNER-LABEL'
u5 U5d 'runs on `'"$LABEL"'# BL-358-RUNNER-LABEL`'     'runs-on: '"$LABEL"'# BL-358-RUNNER-LABEL'
u5 U5e 'mentions runs-on but is not a `runs-on:` line' '"runs-on": '"$LABEL"'   # BL-358-RUNNER-LABEL'

# U5f — the labels on the lines below the key, as a list.
U5F="$(newtmp)"
mk_wf "$U5F/a.yml" 'runs-on:'
awk -v l="$LABEL" '{ print } $0 == "    runs-on:" { print "      - " l }' "$U5F/a.yml" > "$U5F/wf.yml"
ln="$(_line_eq "$U5F/wf.yml" '    runs-on:')"
run_lint "$LINT" "$U5F/wf.yml"
if grep -qxF "      - $LABEL" "$U5F/wf.yml" && [ "$RC" -eq 1 ] \
  && printf '%s\n' "$OUT" | _gq -F "$U5F/wf.yml:$ln (job bad1): names no label on this line, not \`$LABEL\`"; then
  pass "U5f — a runs-on whose labels are on the lines below it fails by name"
else
  fail_ "U5f" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

# U5g — the check does not depend on how deep the key is indented.
U5G="$(newtmp)"
printf 'jobs:\n    ok:\n        %s\n    bad:\n        runs-on: ubuntu-latest   # BL-358-RUNNER-LABEL\n' "$OK_LINE" > "$U5G/wf.yml"
run_lint "$LINT" "$U5G/wf.yml"
if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
  && printf '%s\n' "$OUT" | _gq -F "$U5G/wf.yml:5 (job ?): runs on \`ubuntu-latest\`"; then
  pass "U5g — an eight-space runs-on is read like a four-space one"
else
  fail_ "U5g" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

U6="$(newtmp)"
printf 'name: fixture\njobs:\n  build:\n    steps:\n      - run: echo hi\n' > "$U6/wf.yml"
run_lint "$LINT" "$U6/wf.yml"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F "$U6/wf.yml: no runs-on line, so nothing in it was checked"; then
  pass "U6 — a workflow with no runs-on line fails: nothing checked is not a pass"
else
  fail_ "U6" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

U7="$(newtmp)"; mk_wf "$U7/wf.yml"
printf '# runs-on: ubuntu-latest, in a whole-line comment\n  ok2:\n    # runs-on: ubuntu-latest\n    %s\n' "$OK_LINE" >> "$U7/wf.yml"
run_lint "$LINT" "$U7/wf.yml"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s)'; then
  pass "U7 — whole-line comments that mention runs-on are not read"
else
  fail_ "U7" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

U8="$(newtmp)"
mk_wf "$U8/wf.yml" "runs-on: $LABEL   # BL-358-RUNNER-LABELX" \
                   "runs-on: $LABEL   # see BL-358-RUNNER-LABEL" \
                   "runs-on: $LABEL   #BL-358-RUNNER-LABEL"
run_lint "$LINT" "$U8/wf.yml"
u8_ok=1
for j in 1 2 3; do
  ln="$(awk -v j="  bad$j:" '$0 == j { print NR + 1; exit }' "$U8/wf.yml")"
  printf '%s\n' "$OUT" | _gq -F "$U8/wf.yml:$ln (job bad$j): no \`# BL-358-RUNNER-LABEL\` after the label" || u8_ok=0
done
if [ "$RC" -eq 1 ] && [ "$u8_ok" -eq 1 ] && [ "$(_fails "$OUT")" = "3" ]; then
  pass "U8 — a longer token, a marker that is not first in the comment, and no space after # are each a missing marker"
else
  fail_ "U8" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

run_lint "$LINT" "$TOPTMP/no-such-workflow.yml"
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | _gq -F "could not read the runs-on lines of $TOPTMP/no-such-workflow.yml"; then
  pass "U9 — a workflow that is not there is named, rc 2"
else
  fail_ "U9" "rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
fi

run_lint "$LINT" --help
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'RUNNER_LABEL, below, is the only place this check reads the label from'; then
  pass "U10 — --help prints the header, which says where the label is changed"
else
  fail_ "U10" "rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
fi

run_lint "$LINT" --bogus
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | _gq -F "unknown option '--bogus'"; then
  pass "U11 — an unknown option is rc 2, named"
else
  fail_ "U11" "rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
fi

# U12 — an awk that exits 0 and prints nothing must not read as a clean pass.
U12="$(newtmp)"; mkdir -p "$U12/bin"; mk_wf "$U12/wf.yml"
printf '#!/bin/sh\nexit 0\n' > "$U12/bin/awk"; chmod +x "$U12/bin/awk"
OUT="$(PATH="$U12/bin:$PATH" bash "$LINT" "$U12/wf.yml" 2>&1)"; RC=$?
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | _gq -F "could not read the runs-on lines of $U12/wf.yml (awk rc 0)"; then
  pass "U12 — a count that never came back is rc 2, not a pass"
else
  fail_ "U12" "rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
fi

echo "=== B — moving to a new image, rehearsed on copies ==="

# The next label is the current one with `-next` after it, so it never equals it.
NEXT="$LABEL-next"
NEXT_RE="$LABEL_RE-next"
B="$(newtmp)"
_swap '# BL-358-LABEL-VALUE' "RUNNER_LABEL=\"$NEXT\"   # BL-358-LABEL-VALUE" "$LINT" "$B/lint-next.sh"; b_rc=$?
for w in tests lint; do
  awk -v from="$LABEL_RE" -v to="$NEXT" '$0 ~ ("^[[:space:]]*runs-on: " from "[[:space:]]") { sub(from, to) } { print }' \
    "$REPO_ROOT/.github/workflows/$w.yml" > "$B/$w.yml"
done
B_SUB="$(cat "$B/tests.yml" "$B/lint.yml" | grep -c "^[[:space:]]*runs-on: $NEXT_RE   # BL-358-RUNNER-LABEL\$")"
if [ "$b_rc" -ne 0 ] || ! grep -qxF "RUNNER_LABEL=\"$NEXT\"   # BL-358-LABEL-VALUE" "$B/lint-next.sh" || [ "$B_SUB" != "$WANT_N" ]; then
  fail_ "B setup" "the label edit did not land (rc=$b_rc) or $B_SUB of $WANT_N runs-on lines were rewritten"
else
  run_lint "$B/lint-next.sh" "$B/tests.yml" "$B/lint.yml"
  [ "$RC" -eq 0 ] \
    && pass "B1 — RUNNER_LABEL and all $WANT_N runs-on lines changed together, $LABEL to $NEXT, pass" \
    || fail_ "B1" "rc=$RC out=$(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
  run_lint "$LINT" "$B/tests.yml" "$B/lint.yml"
  b2_n="$(printf '%s\n' "$OUT" | grep -cF "runs on \`$NEXT\`, not \`$LABEL\`")"
  [ "$RC" -eq 1 ] && [ "$b2_n" = "$WANT_N" ] \
    && pass "B2 — the runs-on lines changed without RUNNER_LABEL fail, all $WANT_N named" \
    || fail_ "B2" "rc=$RC named=$b2_n of $WANT_N"
fi

echo "=== M — one mutant per marked line, each on a copy ==="

# mutant <id> <marker> <replacement-line> — writes $MUT, the lint with the one
# line that ENDS with <marker> replaced by <replacement-line> (end of line, so
# a marker that prefixes another cannot match both); fails the setup unless
# exactly one line ended with it, the replacement is in the copy as written,
# and the copy still parses. The copies live in a scripts/ folder of their own:
# the lint takes its REPO_ROOT from its own folder's parent and strips it from
# the paths it prints, and $TOPTMP is the parent of every fixture.
mkdir -p "$TOPTMP/mutroot/scripts"
mutant() {
  MUT="$TOPTMP/mutroot/scripts/mut-$1.sh"
  if ! _swap "$2" "$3" "$LINT" "$MUT" || ! grep -qxF -- "$3" "$MUT" || ! bash -n "$MUT"; then
    fail_ "$1 setup" "the mutation at '$2' did not land cleanly"
    return 1
  fi
  return 0
}

for m in VALUE HELP OPTION JOB COMMENT-SKIP SCOPE SHAPE SPLIT NAME MARKER FLOOR READ FAIL TOTAL HOW EXIT; do
  n="$(grep -c "# BL-358-LABEL-$m\$" "$LINT")"
  [ "$n" = "1" ] && pass "M0 — '# BL-358-LABEL-$m' ends exactly one line of the lint" \
    || fail_ "M0" "'# BL-358-LABEL-$m' ends $n lines (need exactly 1)"
done

# M1's label is B's next one: ubuntu-latest, applied to the lint itself, would
# stop at the setup check, not at R1.
if mutant M1 '# BL-358-LABEL-VALUE' "RUNNER_LABEL=\"$NEXT\"   # BL-358-LABEL-VALUE"; then
  run_lint "$MUT" "$WF_TESTS" "$WF_LINT"
  [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "$WANT_N" ] \
    && pass "M1 — RUNNER_LABEL changed alone fails all $WANT_N real lines: R1 kills it, so the label is read from that line" \
    || fail_ "M1" "rc=$RC with RUNNER_LABEL changed alone"
fi

# Each kill below is judged on what the mutant printed, never on an absence
# alone: a mutant that crashed, or never reached its line, proves nothing.
if mutant M2 '# BL-358-LABEL-HELP' '  -h|--help) exit 0 ;;   # BL-358-LABEL-HELP'; then
  run_lint "$MUT" --help
  [ "$RC" -eq 0 ] && [ -z "$OUT" ] \
    && pass "M2 — with --help printing nothing, U10 finds no header (U10 kills it)" \
    || fail_ "M2" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M3 '# BL-358-LABEL-OPTION' '  -*) : ;;   # BL-358-LABEL-OPTION'; then
  run_lint "$MUT" --bogus
  printf '%s\n' "$OUT" | _gq -F 'could not read the runs-on lines of --bogus' \
    && ! printf '%s\n' "$OUT" | _gq -F 'unknown option' \
    && pass "M3 — with unknown options let through, --bogus is read as a workflow and U11's message is gone (U11 kills it)" \
    || fail_ "M3" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M4 '# BL-358-LABEL-JOB' '    0 { job = $1 }   # BL-358-LABEL-JOB'; then
  run_lint "$MUT" "$U2/wf.yml"
  printf '%s\n' "$OUT" | _gq -F '(job ?): runs on `ubuntu-latest`' \
    && ! printf '%s\n' "$OUT" | _gq -F '(job bad1)' \
    && pass "M4 — with the job key never read, U2's fault is reported as '(job ?)', not '(job bad1)' (U2 kills it)" \
    || fail_ "M4" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M5 '# BL-358-LABEL-COMMENT-SKIP' '    0 { next }   # BL-358-LABEL-COMMENT-SKIP'; then
  run_lint "$MUT" "$U7/wf.yml"
  ln="$(_line_eq "$U7/wf.yml" '# runs-on: ubuntu-latest, in a whole-line comment')"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F "$U7/wf.yml:$ln (job ok): mentions runs-on but is not a \`runs-on:\` line" \
    && pass "M5 — with whole-line comments read, U7's comment line fails by name (U7 kills it)" \
    || fail_ "M5" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

M_QK="\"runs-on\": $LABEL   # BL-358-RUNNER-LABEL"
if mutant M6 '# BL-358-LABEL-SCOPE' '    $1 != "runs-on:" { next }   # BL-358-LABEL-SCOPE'; then
  d="$(newtmp)"; mk_wf "$d/wf.yml" "$M_QK"
  run_lint "$MUT" "$d/wf.yml"
  [ "$RC" -eq 0 ] && pass "M6 — with only plain runs-on: lines in scope, U5e's quoted key passes (U5e kills it)" \
    || fail_ "M6" "U5e's fixture still fails, rc=$RC"
fi

if mutant M7 '# BL-358-LABEL-SHAPE' '      if ($1 != "runs-on:") next   # BL-358-LABEL-SHAPE'; then
  d="$(newtmp)"; mk_wf "$d/wf.yml" "$M_QK"
  run_lint "$MUT" "$d/wf.yml"
  [ "$RC" -eq 0 ] && pass "M7 — with a line that is not a plain key skipped, not failed, U5e passes (U5e kills it)" \
    || fail_ "M7" "U5e's fixture still fails, rc=$RC"
fi

if mutant M8 '# BL-358-LABEL-SPLIT' '      if (match(rest, /#/)) { v = substr(rest, 1, RSTART - 1); c = substr(rest, RSTART) }   # BL-358-LABEL-SPLIT'; then
  d="$(newtmp)"; mk_wf "$d/wf.yml" "runs-on: ${LABEL}# BL-358-RUNNER-LABEL"
  run_lint "$MUT" "$d/wf.yml"
  [ "$RC" -eq 0 ] && pass "M8 — with a comment taken from any #, U5d's \`${LABEL}# …\` passes (U5d kills it)" \
    || fail_ "M8" "U5d's fixture still fails, rc=$RC"
fi

if mutant M9 '# BL-358-LABEL-NAME' '      if (0) print "V " where ": runs on `" v "`"   # BL-358-LABEL-NAME'; then
  run_lint "$MUT" "$U2/wf.yml"
  [ "$RC" -eq 0 ] && pass "M9 — with the label never compared, U2's ubuntu-latest passes (U2 kills it)" \
    || fail_ "M9" "U2's fixture still fails, rc=$RC"
fi

if mutant M10 '# BL-358-LABEL-MARKER' '      if (0) print "V " where ": no marker"   # BL-358-LABEL-MARKER'; then
  run_lint "$MUT" "$U3/wf.yml"
  [ "$RC" -eq 0 ] && pass "M10 — with the marker never checked, U3's unmarked line passes (U3 kills it)" \
    || fail_ "M10" "U3's fixture still fails, rc=$RC"
fi

if mutant M11 '# BL-358-LABEL-MARKER' '      if (index(c, marker) == 0) print "V " where ": no marker"   # BL-358-LABEL-MARKER'; then
  run_lint "$MUT" "$U8/wf.yml"
  [ "$RC" -eq 0 ] && pass "M11 — with the marker found anywhere in the comment, U8's three lines pass (U8 kills it)" \
    || fail_ "M11" "U8's fixture still fails, rc=$RC"
fi

if mutant M12 '# BL-358-LABEL-FLOOR' '      if (0) print "V " f ": no runs-on line"   # BL-358-LABEL-FLOOR'; then
  run_lint "$MUT" "$U6/wf.yml"
  [ "$RC" -eq 0 ] && pass "M12 — with the floor gone, U6's workflow with no runs-on line passes (U6 kills it)" \
    || fail_ "M12" "U6's fixture still fails, rc=$RC"
fi

if mutant M13 '# BL-358-LABEL-READ' '  if false; then   # BL-358-LABEL-READ'; then
  run_lint "$MUT" "$TOPTMP/no-such-workflow.yml"; m13_a=$RC; m13_ao="$OUT"
  OUT="$(PATH="$U12/bin:$PATH" bash "$MUT" "$U12/wf.yml" 2>&1)"; m13_b=$?
  [ "$m13_a" -eq 0 ] && [ "$m13_b" -eq 0 ] \
    && printf '%s\n' "$m13_ao" | _gq -F 'OK: 0 runs-on line(s)' && printf '%s\n' "$OUT" | _gq -F 'OK: 0 runs-on line(s)' \
    && pass "M13 — without the read check, U9's missing workflow and U12's silent awk both read as clean, 0 lines (U9 and U12 kill it)" \
    || fail_ "M13" "U9 rc=$m13_a, U12 rc=$m13_b under the mutant (want 0 and 0, each 'OK: 0')"
fi

if mutant M14 '# BL-358-LABEL-FAIL' '  if false; then :; fi   # BL-358-LABEL-FAIL'; then
  run_lint "$MUT" "$U2/wf.yml"
  [ "$RC" -eq 0 ] && pass "M14 — with the faults never collected, U2 passes (U2 kills it)" \
    || fail_ "M14" "U2's fixture still fails, rc=$RC"
fi

if mutant M15 '# BL-358-LABEL-TOTAL' '  total=$((total + 0))   # BL-358-LABEL-TOTAL'; then
  run_lint "$MUT" "$WF_TESTS" "$WF_LINT"
  [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 0 runs-on line(s) in 2 workflow(s)' \
    && pass "M15 — with the lines not counted, the real workflows report 0, not $WANT_N (R1 kills it)" \
    || fail_ "M15" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M16 '# BL-358-LABEL-HOW' '  :   # BL-358-LABEL-HOW'; then
  run_lint "$MUT" "$U2/wf.yml"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F '(job bad1): runs on `ubuntu-latest`' \
    && ! printf '%s\n' "$OUT" | _gq -F 'change RUNNER_LABEL in scripts/lint-runner-label.sh' \
    && pass "M16 — without the line that says where the label is changed, U2 fails on the fault alone (U2 kills it)" \
    || fail_ "M16" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-200)"
fi

if mutant M17 '# BL-358-LABEL-EXIT' '  exit 0   # BL-358-LABEL-EXIT'; then
  run_lint "$MUT" "$U2/wf.yml"
  [ "$RC" -eq 0 ] && pass "M17 — with the failing exit at 0, U2's rc is 0 (U2 kills it)" \
    || fail_ "M17" "U2's fixture still ends rc $RC"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1

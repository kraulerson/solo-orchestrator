#!/usr/bin/env bash
# tests/test-lint-runner-label.sh — pins scripts/lint-runner-label.sh
# (`## BL-358:`, "The runner label"): every runs-on line in tests.yml and
# lint.yml names the label RUNNER_LABEL holds and carries the label's marker,
# a line that does not is failed by file, line and job, and with no arguments
# every other workflow file is held against the lint's CHECKED and EXEMPT
# lists (`## BL-376:`).
#
#   R  the lint over this repository's own two workflows, and over copies of
#      them with one line set back to ubuntu-latest or stripped of its marker
#   U  fixtures: scratch workflows passed as arguments; no case edits the
#      real files
#   S  the no-argument run on scratch trees, each with the lint as its own
#      scripts/lint-runner-label.sh: a third workflow file is read when
#      CHECKED names it, passed over when EXEMPT names it with a reason and
#      it holds no runs-on line, and failed by name otherwise; an entry is
#      planted on a copy of the lint, never on the lint itself
#   B  moving to a new image, rehearsed on copies: RUNNER_LABEL and the
#      runs-on lines change together, and the lines alone fail
#   M  one mutant per marked line of the lint (two on the marker check, two
#      on the enumerate), each on a copy, each found by its end-of-line
#      marker and asserted to have landed; each must turn its killer case's
#      verdict around
#
# The label is never written here. It is read from the lint's RUNNER_LABEL
# line (`# BL-358-LABEL-VALUE`), and every fixture, pattern and expected
# message is built from it: a label written out here turns this suite red at
# the bump the lint documents (RUNNER_LABEL and every runs-on line, nothing
# else), as it did until 2026-11-01 (`## BL-358:`, "The check").
#
# This file is in lint-bl-markers' code surface, so every marker-shaped token
# below defines a marker on the real tree. They are all `BL-358-…` or
# `BL-376-…`, each of which names a real entry.
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

echo "=== S — the no-argument run holds every workflow file against the two lists ==="

# mk_tree <dir> — a scratch repository for the no-argument form: scripts/ for
# the lint under test, and .github/workflows/ holding a canonical tests.yml and
# lint.yml. run_in_tree <lint> <dir> copies <lint> in as <dir>'s own
# scripts/lint-runner-label.sh and runs it with no arguments, so its REPO_ROOT
# is <dir> and it names files as `.github/workflows/<file>`.
mk_tree() {
  mkdir -p "$1/scripts" "$1/.github/workflows"
  mk_wf "$1/.github/workflows/tests.yml"
  mk_wf "$1/.github/workflows/lint.yml"
}
run_in_tree() { cp "$1" "$2/scripts/lint-runner-label.sh"; run_lint "$2/scripts/lint-runner-label.sh"; }

# mk_caller <file> — a caller-only workflow: every job is a `uses:` call, which
# GitHub gives no runs-on key, so the file has no runs-on line.
mk_caller() {
  printf 'name: caller\n\non:\n  pull_request:\n\njobs:\n  tests:\n    uses: ./.github/workflows/tests.yml\n  lint:\n    uses: ./.github/workflows/lint.yml\n' > "$1"
}

# _plant <marker> <line> <src> <dst> — <src> with <line> inserted after the one
# line that ends with <marker>, verbatim (ENVIRON, as _swap); rc 3 unless
# exactly one line ended with it.
_plant() {
  P_MK="$1" P_LINE="$2" awk '
    { print; m = ENVIRON["P_MK"]; t = length($0) - length(m) + 1 }
    t >= 1 && substr($0, t) == m { print ENVIRON["P_LINE"]; n++ }
    END { exit (n == 1 ? 0 : 3) }' "$3" > "$4"
}

# planted <id> <marker> <line> — writes $PLANTED, the lint with <line> as the
# first entry of the list that opens at <marker>; fails the setup unless the
# line is in the copy as written and the copy still parses.
planted() {
  PLANTED="$TOPTMP/planted-$1.sh"
  if ! _plant "$2" "$3" "$LINT" "$PLANTED" || ! grep -qxF -- "$3" "$PLANTED" || ! bash -n "$PLANTED"; then
    fail_ "$1 setup" "the entry '$3' did not land after '$2'"
    return 1
  fi
  return 0
}

CHECKED_MK='# BL-376-CHECKED-BEGIN'
EXEMPT_MK='# BL-376-EXEMPT-BEGIN'
CALLER_REASON='every job is a jobs.<id>.uses call, which GitHub gives no runs-on key'
BAD_LINE='runs-on: ubuntu-latest   # BL-358-RUNNER-LABEL'
# The planted lints three M cases start from; empty when their case's setup failed.
S3_LINT=""; S4_LINT=""; S7_LINT=""

S0="$(newtmp)"; mk_tree "$S0"
run_in_tree "$LINT" "$S0"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s) in 2 workflow(s)' \
  && printf '%s\n' "$OUT" | _gq -F '; 0 workflow(s) exempt.'; then
  pass "S0 — a tree of tests.yml and lint.yml alone passes: 2 lines in 2 workflows, 0 exempt"
else
  fail_ "S0" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

if planted S1 "$CHECKED_MK" 'release.yml'; then
  S1="$(newtmp)"; mk_tree "$S1"; mk_wf "$S1/.github/workflows/release.yml"
  run_in_tree "$PLANTED" "$S1"
  if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 3 runs-on line(s) in 3 workflow(s)' \
    && printf '%s\n' "$OUT" | _gq -F '; 0 workflow(s) exempt.'; then
    pass "S1 — a third workflow named in CHECKED is read with the two: 3 lines in 3 workflows, 0 exempt"
  else
    fail_ "S1" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
fi

if planted S2 "$CHECKED_MK" 'release.yml'; then
  S2="$(newtmp)"; mk_tree "$S2"; mk_wf "$S2/.github/workflows/release.yml" "$BAD_LINE"
  ln="$(_line_eq "$S2/.github/workflows/release.yml" "    $BAD_LINE")"
  run_in_tree "$PLANTED" "$S2"
  if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
    && printf '%s\n' "$OUT" | _gq -F ".github/workflows/release.yml:$ln (job bad1): runs on \`ubuntu-latest\`, not \`$LABEL\`"; then
    pass "S2 — a third CHECKED workflow's ubuntu-latest fails by file, line and job, that line alone"
  else
    fail_ "S2" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
fi

if planted S3 "$EXEMPT_MK" "call-tests.yml  $CALLER_REASON"; then
  S3="$(newtmp)"; S3_LINT="$PLANTED"; mk_tree "$S3"; mk_caller "$S3/.github/workflows/call-tests.yml"
  run_in_tree "$PLANTED" "$S3"
  if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s) in 2 workflow(s)' \
    && printf '%s\n' "$OUT" | _gq -F '; 1 workflow(s) exempt.' \
    && ! printf '%s\n' "$OUT" | _gq -F 'call-tests.yml'; then
    pass "S3 — a caller-only workflow named in EXEMPT with a reason passes unread: 2 lines in 2 workflows, 1 exempt"
  else
    fail_ "S3" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
fi

if planted S4 "$EXEMPT_MK" "call-tests.yml  $CALLER_REASON"; then
  S4="$(newtmp)"; S4_LINT="$PLANTED"; mk_tree "$S4"; mk_caller "$S4/.github/workflows/call-tests.yml"
  printf '  build:\n    %s\n    steps:\n      - run: echo build\n' "$OK_LINE" >> "$S4/.github/workflows/call-tests.yml"
  run_in_tree "$PLANTED" "$S4"
  if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
    && printf '%s\n' "$OUT" | _gq -F ".github/workflows/call-tests.yml holds 1 runs-on line(s) but is EXEMPT ($CALLER_REASON): the exemption no longer describes it"; then
    pass "S4 — an EXEMPT workflow that grew a runs-on line, a canonical one, fails by name: the exemption no longer describes it"
  else
    fail_ "S4" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
fi

S5="$(newtmp)"; mk_tree "$S5"; mk_wf "$S5/.github/workflows/release.yml"
run_in_tree "$LINT" "$S5"
if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
  && printf '%s\n' "$OUT" | _gq -F '.github/workflows/release.yml is in neither list of scripts/lint-runner-label.sh: add it to CHECKED when its jobs carry runs-on lines, or to EXEMPT with a reason' \
  && ! printf '%s\n' "$OUT" | _gq -F 'Each runs-on line reads'; then
  pass "S5 — a third .yml in neither list fails by name, naming both lists, with no label how-to after it"
else
  fail_ "S5" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

S6="$(newtmp)"; mk_tree "$S6"; mk_wf "$S6/.github/workflows/release.yaml"
run_in_tree "$LINT" "$S6"
if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
  && printf '%s\n' "$OUT" | _gq -F '.github/workflows/release.yaml is in neither list'; then
  pass "S6 — the .yaml spelling is enumerated too: a third .yaml in neither list fails by name"
else
  fail_ "S6" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

if planted S7 "$EXEMPT_MK" 'call-tests.yml'; then
  S7="$(newtmp)"; S7_LINT="$PLANTED"; mk_tree "$S7"; mk_caller "$S7/.github/workflows/call-tests.yml"
  run_in_tree "$PLANTED" "$S7"
  if [ "$RC" -eq 1 ] && [ "$(_fails "$OUT")" = "1" ] \
    && printf '%s\n' "$OUT" | _gq -F '.github/workflows/call-tests.yml is EXEMPT with no reason'; then
    pass "S7 — an EXEMPT entry with no reason fails by name"
  else
    fail_ "S7" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
fi

run_lint "$S5/scripts/lint-runner-label.sh" "$S5/.github/workflows/tests.yml" "$S5/.github/workflows/lint.yml"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s) in 2 workflow(s)' \
  && ! printf '%s\n' "$OUT" | _gq -F 'release.yml' && ! printf '%s\n' "$OUT" | _gq -F 'exempt'; then
  pass "S8 — with arguments, only the arguments are read: S5's stray release.yml is neither named nor counted"
else
  fail_ "S8" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

if planted S9 "$CHECKED_MK" 'release.yml'; then
  S9="$(newtmp)"; mk_tree "$S9"
  run_in_tree "$PLANTED" "$S9"
  if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | _gq -F 'could not read the runs-on lines of .github/workflows/release.yml'; then
    pass "S9 — a CHECKED file that is not there is still rc 2, named"
  else
    fail_ "S9" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
  fi
fi

S10="$(newtmp)"; mk_tree "$S10"; printf 'runs-on: ubuntu-latest, in a README\n' > "$S10/.github/workflows/README.md"
run_in_tree "$LINT" "$S10"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s) in 2 workflow(s)'; then
  pass "S10 — a file beside the workflows that is not *.yml or *.yaml is not enumerated"
else
  fail_ "S10" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
fi

run_lint "$LINT" --help
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'A file in neither list fails by name, and the message names both lists.'; then
  pass "S11 — --help describes the two lists and what a file in neither does"
else
  fail_ "S11" "rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"
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

# mutant <id> <marker> <replacement-line> [<src>] — writes $MUT, the lint (or
# <src>, a planted copy of it) with the one line that ENDS with <marker>
# replaced by <replacement-line> (end of line, so a marker that prefixes
# another cannot match both); fails the setup unless exactly one line ended
# with it, the replacement is in the copy as written, and the copy still
# parses. The copies live in a scripts/ folder of their own: the lint takes its
# REPO_ROOT from its own folder's parent and strips it from the paths it
# prints, and $TOPTMP is the parent of every fixture.
mkdir -p "$TOPTMP/mutroot/scripts"
mutant() {
  MUT="$TOPTMP/mutroot/scripts/mut-$1.sh"
  if ! _swap "$2" "$3" "${4:-$LINT}" "$MUT" || ! grep -qxF -- "$3" "$MUT" || ! bash -n "$MUT"; then
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
for m in CHECKED-BEGIN EXEMPT-BEGIN ENUMERATE NULLGLOB CHECKED-MATCH EXEMPT-MATCH EXEMPT-OK EXEMPT-RUNS-ON EXEMPT-REASON UNKNOWN EXIT; do
  n="$(grep -c "# BL-376-$m\$" "$LINT")"
  [ "$n" = "1" ] && pass "M0 — '# BL-376-$m' ends exactly one line of the lint" \
    || fail_ "M0" "'# BL-376-$m' ends $n lines (need exactly 1)"
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

# The scope mutants run with no arguments, as a scratch tree's own lint, over
# the S family's trees; the three on the EXEMPT arms start from the planted
# copy their tree's case ran, so the entry under test is there.
if mutant M18 '# BL-376-ENUMERATE' '  for wf in "$WF_DIR"/*.yml; do   # BL-376-ENUMERATE'; then
  run_in_tree "$MUT" "$S6"
  [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s) in 2 workflow(s)' \
    && pass "M18 — with *.yaml not enumerated, S6's stray release.yaml passes (S6 kills it)" \
    || fail_ "M18" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M19 '# BL-376-ENUMERATE' '  for wf in; do   # BL-376-ENUMERATE'; then
  run_in_tree "$MUT" "$S5"
  [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s) in 2 workflow(s)' \
    && pass "M19 — with nothing enumerated, S5's stray release.yml passes (S5 kills it)" \
    || fail_ "M19" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M20 '# BL-376-NULLGLOB' '    :   # BL-376-NULLGLOB'; then
  run_in_tree "$MUT" "$S0"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F '.github/workflows/*.yaml is in neither list' \
    && pass "M20 — with an unmatched pattern not skipped, S0's tree fails on the literal *.yaml (S0 kills it)" \
    || fail_ "M20" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M21 '# BL-376-CHECKED-MATCH' '    false && continue   # BL-376-CHECKED-MATCH'; then
  run_in_tree "$MUT" "$S0"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F '.github/workflows/tests.yml is in neither list' \
    && printf '%s\n' "$OUT" | _gq -F '.github/workflows/lint.yml is in neither list' \
    && pass "M21 — with CHECKED never matched, S0's tests.yml and lint.yml are failed as unknown (S0 kills it)" \
    || fail_ "M21" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M22 '# BL-376-EXEMPT-MATCH' '    entry=""   # BL-376-EXEMPT-MATCH' "$S3_LINT"; then
  run_in_tree "$MUT" "$S3"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F '.github/workflows/call-tests.yml is in neither list' \
    && pass "M22 — with EXEMPT never matched, S3's listed caller-only workflow is failed as unknown (S3 kills it)" \
    || fail_ "M22" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M23 '# BL-376-EXEMPT-RUNS-ON' '      if false; then   # BL-376-EXEMPT-RUNS-ON' "$S4_LINT"; then
  run_in_tree "$MUT" "$S4"
  [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F '; 1 workflow(s) exempt.' \
    && pass "M23 — with EXEMPT files not read for runs-on, S4's grown workflow passes as exempt (S4 kills it)" \
    || fail_ "M23" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M24 '# BL-376-EXEMPT-REASON' '    elif false; then   # BL-376-EXEMPT-REASON' "$S7_LINT"; then
  run_in_tree "$MUT" "$S7"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F '.github/workflows/call-tests.yml is in neither list' \
    && ! printf '%s\n' "$OUT" | _gq -F 'EXEMPT with no reason' \
    && pass "M24 — with the reason check gone, S7's bare entry is misreported as unknown, never as an entry with no reason (S7 kills it)" \
    || fail_ "M24" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M25 '# BL-376-UNKNOWN' '    elif false; then   # BL-376-UNKNOWN'; then
  run_in_tree "$MUT" "$S5"
  [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s) in 2 workflow(s)' \
    && pass "M25 — with the unknown arm gone, S5's stray release.yml passes in silence (S5 kills it)" \
    || fail_ "M25" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M26 '# BL-376-EXIT' ':   # BL-376-EXIT'; then
  run_in_tree "$MUT" "$S5"
  [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | _gq -F 'is in neither list' && printf '%s\n' "$OUT" | _gq -F 'OK: 2 runs-on line(s)' \
    && pass "M26 — with the scope exit gone, S5's stray file is named and the run still ends OK, rc 0 (S5 kills it)" \
    || fail_ "M26" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

if mutant M27 '# BL-376-EXEMPT-OK' '    if false; then   # BL-376-EXEMPT-OK' "$S3_LINT"; then
  run_in_tree "$MUT" "$S3"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | _gq -F '.github/workflows/call-tests.yml is EXEMPT with no reason' \
    && ! printf '%s\n' "$OUT" | _gq -F 'workflow(s) exempt' \
    && pass "M27 — with a reasoned entry never accepted, S3's caller-only workflow is misreported as an entry with no reason and nothing is exempt (S3 kills it)" \
    || fail_ "M27" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1

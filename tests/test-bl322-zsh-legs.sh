#!/usr/bin/env bash
# tests/test-bl322-zsh-legs.sh — `## BL-322:` S2 (Karl, 2026-10-07): zsh is
# installed only on the unit-shard legs that run a suite needing it, and a
# suite needing it cannot land on a leg without it.
#
# WHY. The "Install zsh" step ran on all nine legs: 9-17s each, and 89-92s on
# the two legs PR #503's run cancelled at the 720s cap. Since BL-311 round 13
# (8b5a031) no suite runs zsh. The step now runs only on the legs its `if:`
# lists (`# BL-322-ZSH-LEGS`, an empty list today), and a suite that needs zsh
# says so with a whole-line `# NEEDS-ZSH` comment.
#
# THE TWO GUARDS, AND WHAT EACH CASE OWNS.
#   Z1  the real workflow: every suite marked NEEDS-ZSH runs in a listed leg.
#       Its leg is derived by running the workflow's OWN partition code (the
#       shard script, extracted), never by re-parsing the pin arrays here.
#       Vacuous today (no suite is marked): the case says how many it checked.
#   Z2  the same check on a fixture workflow catches a marked suite pinned to
#       an unlisted leg, a marked suite left in `rest`, and passes once its leg
#       is listed — so Z1's silence is a real answer, not a blind spot.
#   Z3  the runtime guard in the shard script (`# BL-322-ZSH-GUARD`): on a leg
#       running a marked suite with no zsh on PATH it exits 1 naming the suite
#       and the leg, before any suite runs; with zsh on PATH it lets it run.
#   Z4  the step itself: gated on `matrix.shard` by a JSON list, and still
#       loud when the install fails (no continue-on-error, no `|| true`).
#   Z5  every unit-lane suite that EXECUTES zsh carries the marker (`## BL-322:`
#       S5, R-S2-13): "executes" is read from executed lines only, comments out
#       (the `# BL-181-UNIT-LANE-PREDICATE` lesson), with zsh as a command word —
#       probed (`command -v zsh`), given an option (`zsh -f`) or in command
#       position. The same check on fixture lines proves it tells them apart.
#       A zsh run built at run time (`"${s}sh"`) or written only inside a
#       heredoc the suite writes out is not seen (BL-181's residual, here).
#   M   mutants of the workflow, each needing a named case to go RED.
#
# THE MARKER, ANY SPELLING (R-S2-13). A line that starts, after any indent,
# with `#`, any spaces, then NEEDS-ZSH in any case: `# NEEDS-ZSH`, `#NEEDS-ZSH`,
# `  # needs-zsh`, `# NEEDS-ZSH: why`. Z2 and Z3 run every spelling.
#
# Hermetic: temp dirs only; the workflow is read, never run as CI. bash 3.2
# safe. It needs no zsh: Z3 builds a PATH with and without a stand-in.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF_REAL="$REPO_ROOT/.github/workflows/tests.yml"
PASSED=0; FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl322zsh.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
MARKED_SUITE="tests/test-zz-bl322-needs-zsh.sh"
ZSH_MARK_RE='^[[:space:]]*#[[:space:]]*NEEDS-ZSH'
# The spellings the marker must accept (R-S2-13); the default first.
MARK_SPELLINGS="$(printf '%s\n' '# NEEDS-ZSH (a stand-in for a suite that needs zsh)' '#NEEDS-ZSH' '    # NEEDS-ZSH' \
  '# needs-zsh' '# NEEDS-ZSH: the paste-into-zsh cases' "$(printf '\t#\tNeeds-Zsh')")"
is_marked() { command grep -iE "$ZSH_MARK_RE" "$1" >/dev/null 2>&1; }

# shard_script WF UPTO — the unit-shard step's `run: |` block, de-indented, cut
# before the first line matching UPTO (a fixed string).
shard_script() {
  local wf="$1" upto="$2" start="" stop=""
  start="$(awk '/- name: Run fast unit tests — shard/{f=1} f && /run: \|/{print NR; exit}' "$wf")"
  [ -n "$start" ] || return 1
  stop="$(UPTO="$upto" awk -v s="$start" 'NR > s && index($0, ENVIRON["UPTO"]) {print NR; exit}' "$wf")"
  [ -n "$stop" ] || return 1
  sed -n "$((start + 1)),$((stop - 1))p" "$wf" | sed 's/^          //'
}
# legs WF — the matrix's legs, one per line.
legs() { sed -n 's/^ *shard: \[\(.*\)\] *$/\1/p' "$1" | head -1 | tr ',' '\n' | tr -d ' '; }
# zsh_legs WF — the legs the Install zsh step's `if:` lists, one per line.
zsh_legs() {
  awk '/- name: Install zsh/{f=1} f && /^ *if:/{print; exit}' "$1" \
    | sed -n "s/.*fromJSON('\(\[[^]]*\]\)').*/\1/p" | tr -d '[]" ' | tr ',' '\n' | sed '/^$/d'
}
# run_list WF LEG DIR — the suites LEG runs, computed by the workflow's own
# partition code, run from DIR (which only needs the files the guard reads).
run_list() {
  local wf="$1" leg="$2" dir="$3" sc="" n=""
  sc="$(newtmp)/part.sh"
  { shard_script "$wf" '# ── `## BL-322:` S2 — zsh only where' || return 1
    printf '%s\n' 'printf "%s\n" "${run_list[@]}"'; } > "$sc" || return 1
  n="$(legs "$wf" | grep -c .)"
  ( cd "$dir" && SHARD="$leg" SHARD_TOTAL="$n" bash "$sc" ) 2>/dev/null | grep '^tests/'
}
# stranded WF DIR — each marked suite (a whole-line `# NEEDS-ZSH` in DIR's copy)
# that runs on a leg missing from the zsh list, as "suite<TAB>leg".
stranded() {
  local wf="$1" dir="$2" leg="" t="" listed=""
  listed="$(zsh_legs "$wf")"
  for leg in $(legs "$wf"); do
    grep -qxF -- "$leg" <<< "$listed" && continue
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      is_marked "$dir/$t" && printf '%s\t%s\n' "$t" "$leg"
    done <<RUN
$(run_list "$wf" "$leg" "$dir")
RUN
  done
}

# fixture WF_SRC DIR LEG [LISTED] [MARK] — a copy of the workflow whose
# canonical list gains MARKED_SUITE, pinned to LEG (or left in rest), with the
# zsh list set to LISTED (a JSON array; default unchanged); DIR gets the marked
# suite, its marker line spelled MARK (default the first of MARK_SPELLINGS).
# Prints the fixture workflow's path.
fixture() {
  local src="$1" dir="$2" leg="$3" listed="${4:-}" mark="${5:-}" wf="$2/tests.yml" arr=""
  [ -n "$mark" ] || mark="$(head -1 <<< "$MARK_SPELLINGS")"
  mkdir -p "$dir/tests" || return 1
  printf '#!/usr/bin/env bash\n%s\nexit 0\n' "$mark" > "$dir/$MARKED_SUITE"
  case "$leg" in
    rest) arr="" ;;
    *) arr="pin_$(printf '%s' "$leg" | tr '-' '_')=(" ;;
  esac
  ARR="$arr" T="$MARKED_SUITE" L="$listed" awk '
    { print }
    !done_canon && /^ *tests=\($/ { print "            " ENVIRON["T"]; done_canon = 1; next }
    ENVIRON["ARR"] != "" && !done_pin && $0 ~ /^ *pin_[a-z_]+=\(/ && index($0, ENVIRON["ARR"]) { print "            " ENVIRON["T"]; done_pin = 1 }
  ' "$src" > "$wf.tmp" || return 1
  if [ -n "$listed" ]; then
    L="$listed" awk '/- name: Install zsh/{f=1} f && !d && /^ *if:/ { sub(/fromJSON\(.[^)]*.\)/, "fromJSON(\047" ENVIRON["L"] "\047)"); d = 1 } { print }' "$wf.tmp" > "$wf" || return 1
  else
    cat "$wf.tmp" > "$wf"
  fi
  printf '%s' "$wf"
}

# ── Z1: the real workflow ────────────────────────────────────────────────────
case_Z1() {
  local wf="$1" marked="" s=""
  [ -n "$(legs "$wf")" ] || { CASE_DETAIL="no legs read from the matrix"; return 1; }
  [ -n "$(run_list "$wf" rest "$REPO_ROOT")" ] || { CASE_DETAIL="the partition code yields nothing for rest"; return 1; }
  marked="$(cd "$REPO_ROOT" && command grep -liE "$ZSH_MARK_RE" tests/*.sh 2>/dev/null)"
  s="$(stranded "$wf" "$REPO_ROOT")"
  [ -z "$s" ] || { CASE_DETAIL="marked suites on legs without zsh: $(tr '\n\t' '|@' <<< "$s")"; return 1; }
  CASE_DETAIL="$(grep -c . <<< "$marked") marked suite(s); legs with zsh: [$(zsh_legs "$wf" | tr '\n' ' ')]"
}

# ── Z2: the check catches a stranded suite ───────────────────────────────────
case_Z2() {
  local wf="$1" d="" f="" s=""
  d="$(newtmp)"; f="$(fixture "$wf" "$d/a" lint-sweep)" || { CASE_DETAIL="fixture a"; return 1; }
  s="$(stranded "$f" "$d/a")"
  [ "$s" = "$(printf '%s\tlint-sweep' "$MARKED_SUITE")" ] || { CASE_DETAIL="pinned to lint-sweep, unlisted: got [$(tr '\n\t' '|@' <<< "$s")]"; return 1; }
  f="$(fixture "$wf" "$d/b" rest)" || { CASE_DETAIL="fixture b"; return 1; }
  s="$(stranded "$f" "$d/b")"
  [ "$s" = "$(printf '%s\trest' "$MARKED_SUITE")" ] || { CASE_DETAIL="left in rest, unlisted: got [$(tr '\n\t' '|@' <<< "$s")]"; return 1; }
  f="$(fixture "$wf" "$d/c" lint-sweep '["lint-sweep"]')" || { CASE_DETAIL="fixture c"; return 1; }
  s="$(stranded "$f" "$d/c")"
  [ -z "$s" ] || { CASE_DETAIL="listed leg still reported: [$(tr '\n\t' '|@' <<< "$s")]"; return 1; }
  # Not a pass by accident: the listed leg does run the suite.
  run_list "$f" lint-sweep "$d/c" | grep -qxF -- "$MARKED_SUITE" || { CASE_DETAIL="the fixture suite is not in lint-sweep's run list"; return 1; }
  # Every spelling of the marker is a marker (R-S2-13).
  local m="" i=0
  while IFS= read -r m; do
    i=$((i + 1))
    f="$(fixture "$wf" "$d/s$i" lint-sweep '' "$m")" || { CASE_DETAIL="fixture s$i"; return 1; }
    s="$(stranded "$f" "$d/s$i")"
    [ "$s" = "$(printf '%s\tlint-sweep' "$MARKED_SUITE")" ] || { CASE_DETAIL="marker spelled [$m] not seen: got [$(tr '\n\t' '|@' <<< "$s")]"; return 1; }
  done <<< "$MARK_SPELLINGS"
}

# ── Z3: the runtime guard ────────────────────────────────────────────────────
# bin_without_zsh DIR — a PATH directory with bash and grep and nothing else.
bin_without_zsh() {
  mkdir -p "$1" && ln -s "$(command -v bash)" "$1/bash" && ln -s "$(command -v grep)" "$1/grep"
}
case_Z3() {
  local wf="$1" d="" f="" sc="" out="" rc=0 bin="" n="" m="" i=0
  d="$(newtmp)"
  bin="$d/bin"; bin_without_zsh "$bin" || { CASE_DETAIL="bin"; return 1; }
  # Every spelling of the marker is refused on a leg without zsh (R-S2-13).
  while IFS= read -r m; do
    i=$((i + 1))
    f="$(fixture "$wf" "$d/s$i" mcp '' "$m")" || { CASE_DETAIL="fixture s$i"; return 1; }
    sc="$d/guard$i.sh"; shard_script "$f" 'failed=()' > "$sc" || { CASE_DETAIL="no shard script"; return 1; }
    n="$(legs "$f" | grep -c .)"
    rc=0; out="$(cd "$d/s$i" && env -i PATH="$bin" SHARD=mcp SHARD_TOTAL="$n" "$bin/bash" "$sc" 2>&1)" || rc=$?
    [ "$rc" -eq 1 ] && grep -qF "$MARKED_SUITE" <<< "$out" || { CASE_DETAIL="marker spelled [$m]: no zsh, rc $rc: $(tail -1 <<< "$out")"; return 1; }
  done <<< "$MARK_SPELLINGS"
  f="$(fixture "$wf" "$d/p" mcp)" || { CASE_DETAIL="fixture"; return 1; }
  sc="$d/guard.sh"; shard_script "$f" 'failed=()' > "$sc" || { CASE_DETAIL="no shard script"; return 1; }
  n="$(legs "$f" | grep -c .)"
  rc=0
  out="$(cd "$d/p" && env -i PATH="$bin" SHARD=mcp SHARD_TOTAL="$n" "$bin/bash" "$sc" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] || { CASE_DETAIL="no zsh: rc $rc, want 1"; return 1; }
  grep -qF "shard 'mcp': zsh is not installed on this leg" <<< "$out" && grep -qF "$MARKED_SUITE" <<< "$out" \
    || { CASE_DETAIL="no zsh: the refusal does not name the leg and the suite: $(tail -1 <<< "$out")"; return 1; }
  # The same leg with zsh on PATH: the guard lets it through.
  printf '#!/bin/sh\nexit 0\n' > "$bin/zsh" && chmod +x "$bin/zsh"
  rc=0; out="$(cd "$d/p" && env -i PATH="$bin" SHARD=mcp SHARD_TOTAL="$n" "$bin/bash" "$sc" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || { CASE_DETAIL="with zsh: rc $rc: $(tail -1 <<< "$out")"; return 1; }
  # And a leg running no marked suite is never refused, zsh or not.
  rm -f "$bin/zsh"
  rc=0; out="$(cd "$d/p" && env -i PATH="$bin" SHARD=lint-sweep SHARD_TOTAL="$n" "$bin/bash" "$sc" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || { CASE_DETAIL="unmarked leg refused: rc $rc: $(tail -1 <<< "$out")"; return 1; }
}

# ── Z4: the step ─────────────────────────────────────────────────────────────
case_Z4() {
  local wf="$1" step=""
  step="$(awk '/- name: Install zsh/{f=1; print; next} f && /^      - name:/{exit} f' "$wf")"
  [ -n "$step" ] || { CASE_DETAIL="no Install zsh step"; return 1; }
  grep -qE "^ *if: contains\(fromJSON\('\[[^]]*\]'\), matrix\.shard\)( *#.*)?$" <<< "$step" \
    || { CASE_DETAIL="the step is not gated on matrix.shard by a JSON list"; return 1; }
  grep -qE '^ *continue-on-error:' <<< "$step" && { CASE_DETAIL="a failed install would be ignored (continue-on-error)"; return 1; }
  grep -E '^ *run:' <<< "$step" | grep -qE '\|\| *(true|:)' && { CASE_DETAIL="a failed install would be ignored (|| true)"; return 1; }
  grep -E '^ *run:' <<< "$step" | grep -q 'install -y zsh' || { CASE_DETAIL="the step no longer installs zsh"; return 1; }
}

# ── Z5: a suite that runs zsh says so (R-S2-13) ──────────────────────────────
# executes_zsh FILE — FILE names zsh as a command on a line that executes.
# Comments are dropped first, exactly as `# BL-181-UNIT-LANE-PREDICATE` drops
# them (whole-line, and trailing after whitespace), so a mention in a comment
# needs no marker. Then zsh as a command word: probed (`command -v zsh`, `type`,
# `which`, `hash`), given an option (`zsh -f`, `/bin/zsh -c`, a shell list
# `"bash|zsh -f -i"`), or in command position (line start, after `;` `&` `|` `(`
# a backtick or `$(`, or after then/do/else/exec/env). No `grep -q` at the end of
# the pipe: under pipefail its early exit can fail the writer (#435).
ZSH_EXEC_RE='(^|[^A-Za-z0-9_.$/-])(command|type|which|hash)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*zsh([^A-Za-z0-9_.-]|$)'
ZSH_EXEC_RE="$ZSH_EXEC_RE"'|(^|[^A-Za-z0-9_.-])zsh[[:space:]]+-'
ZSH_EXEC_RE="$ZSH_EXEC_RE"'|(^|[;&|(`]|[$][(]|(^|[[:space:]])(then|do|else|exec|env))[[:space:]]*([^[:space:]]*/)?zsh([[:space:]]|$|[;&|)`])'
executes_zsh() {
  command grep -vE '^[[:space:]]*#' "$1" 2>/dev/null | sed 's/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/' \
    | command grep -E "$ZSH_EXEC_RE" >/dev/null
}
# unit_list WF — the canonical `tests=(` array, anchored and sliced (CLAUDE.md's
# recipe: never the unanchored scope, which a comment below the array reopens).
unit_list() {
  local s="" e=""
  s="$(awk '/^[[:space:]]*tests=\(/{print NR; exit}' "$1")"
  e="$(awk -v s="$s" 'NR>s && /^[[:space:]]*\)[[:space:]]*$/{print NR; exit}' "$1")"
  [ -n "$s" ] && [ -n "$e" ] || return 1
  sed -n "$((s + 1)),$((e - 1))p" "$1" | sed 's/#.*//' | sed 's/[[:space:]]//g' | command grep '^tests/'
}
case_Z5() {
  local wf="$1" t="" n=0 runs="" bad="" d="" line="" want="" i=0
  # The real tree: every unit-lane suite that runs zsh carries the marker.
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    n=$((n + 1))
    executes_zsh "$REPO_ROOT/$t" || continue
    runs="$runs $t"
    is_marked "$REPO_ROOT/$t" || bad="$bad $t"
  done <<UL
$(unit_list "$wf")
UL
  [ "$n" -gt 100 ] || { CASE_DETAIL="read only $n suites from the unit list"; return 1; }
  [ -z "$bad" ] || { CASE_DETAIL="these unit-lane suites run zsh and carry no # NEEDS-ZSH:$bad"; return 1; }
  # The check tells the shapes apart: R runs zsh, N does not. Each shape spells
  # zsh as @Z@ here, so this suite's own lines never read as running it.
  d="$(newtmp)"
  while IFS='|' read -r want line; do
    [ -n "$want" ] || continue
    line="${line//@Z@/zsh}"
    i=$((i + 1)); printf '#!/usr/bin/env bash\n%s\n' "$line" > "$d/f$i.sh"
    if executes_zsh "$d/f$i.sh"; then [ "$want" = R ] || { CASE_DETAIL="read as running zsh: [$line]"; return 1; }
    else [ "$want" = N ] || { CASE_DETAIL="not read as running zsh: [$line]"; return 1; }; fi
  done <<'SHAPES'
R|command -v @Z@ >/dev/null 2>&1 || { echo "SKIP: no @Z@"; exit 0; }
R|if command -v @Z@ >/dev/null 2>&1; then PASTE_SHELLS="$PASTE_SHELLS|@Z@ -f|@Z@ -f -i"; fi
R|  @Z@ -f -i < steps.txt
R|out="$(@Z@ -c 'echo hi')"
R|/bin/@Z@ -c true
R|printf 'x\n' | @Z@
R|[ -x /bin/@Z@ ] && @Z@ steps.sh
R|type @Z@ >/dev/null && echo yes
R|then @Z@ run.sh
N|# @Z@ -f -i, run where it is installed
N|    # if command -v @Z@; then ...
N|x=1   # @Z@ -f -i
N|echo "@Z@ is not installed on this leg"
N|printf '#!/bin/sh\nexit 0\n' > "$bin/@Z@" && chmod +x "$bin/@Z@"
N|grep -q 'install -y @Z@' step.txt
N|@Z@_legs "$wf"
N|MARKED="tests/test-zz-needs-@Z@.sh"
SHAPES
  CASE_DETAIL="$n unit-lane suites read; run zsh:${runs:- none}; $i shapes told apart"
}

check() {   # LABEL CASE
  CASE_DETAIL=""
  if "$2" "$WF_REAL"; then pass "$1${CASE_DETAIL:+ ($CASE_DETAIL)}"; else fail_ "$1" "${CASE_DETAIL:-failed}"; fi
}
echo "=== Z — zsh legs ==="
check "Z1: every suite marked NEEDS-ZSH runs on a leg the Install zsh step lists" case_Z1
check "Z2: the check catches a marked suite pinned to, or left in rest on, an unlisted leg" case_Z2
check "Z3: the shard script refuses a marked suite on a leg without zsh, by name, and only then" case_Z3
check "Z4: the step is gated on the leg, and a failed install is still loud" case_Z4
check "Z5: every unit-lane suite that runs zsh (executed lines only) carries the marker" case_Z5

# ── M: mutants of the workflow ───────────────────────────────────────────────
mutate() {   # FILE MARKER REPLACEMENT — exactly one line ends in MARKER; it now reads REPLACEMENT
  local f="$1" mark="$2" repl="$3" n=""
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
}
mutant() {   # ID MARKER REPLACEMENT KILLER WHAT
  local m="" why="" rc=0
  m="$(newtmp)/tests.yml"; cp "$WF_REAL" "$m" || { fail_ "$1" "copy"; return; }
  why="$(mutate "$m" "$2" "$3")" || { fail_ "$1" "mutant did not land: $why"; return; }
  CASE_DETAIL=""; "$4" "$m" || rc=$?
  if [ "$rc" -eq 0 ]; then fail_ "$1" "$5 — SURVIVED: ${4#case_} still passes"
  else pass "$1 (MUTATION) — $5: killed by ${4#case_} (${CASE_DETAIL:-failed})"; fi
}
echo "=== M — mutants ==="
mutant M1 '# BL-322-ZSH-GUARD-EXIT' '            :' case_Z3 "the guard reports and carries on"
mutant M2 '# BL-322-ZSH-GUARD' '              if false; then' case_Z3 "the guard never reads the marker"
mutant M3 '# BL-322-ZSH-GUARD-PROBE' '          if false; then' case_Z3 "the guard never asks whether zsh is there"
mutant M4 '# BL-322-ZSH-LEGS' '        if: always()' case_Z4 "zsh is installed on every leg again"
mutant M5 '# BL-322-ZSH-INSTALL' '        run: sudo apt-get -o Acquire::Retries=3 update && sudo apt-get -o Acquire::Retries=3 install -y zsh || true' case_Z4 "a failed install is ignored"
mutant M6 '# BL-322-ZSH-LEGS' "        if: contains(fromJSON('[\"rest\"]'), matrix.shard) && false" case_Z4 "the list is bypassed by a condition that never runs the step"
# R-S2-13: the guard reads every spelling of the marker.
mutant M7 '# BL-322-ZSH-GUARD' "              if grep -qE '^# NEEDS-ZSH([[:space:]]|\$)' \"\${t}\" 2>/dev/null; then" case_Z3 "the guard reads only the old whole-line spelling"
mutant M8 '# BL-322-ZSH-GUARD' "              if grep -qE '^[[:space:]]*#[[:space:]]*NEEDS-ZSH' \"\${t}\" 2>/dev/null; then" case_Z3 "the guard reads the marker in capitals only"
mutant M9 '# BL-322-ZSH-GUARD' "              if grep -qiE '^#[[:space:]]*NEEDS-ZSH' \"\${t}\" 2>/dev/null; then" case_Z3 "the guard misses an indented marker"
mutant M10 '# BL-322-ZSH-GUARD' "              if grep -qiE '^[[:space:]]*# NEEDS-ZSH' \"\${t}\" 2>/dev/null; then" case_Z3 "the guard misses a marker with no space after the #"

echo
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

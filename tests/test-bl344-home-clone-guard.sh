#!/usr/bin/env bash
# tests/test-bl344-home-clone-guard.sh — `## BL-344:` the unit lane fails a
# suite that touches the Development Guardrails clone in the runner's HOME.
#
# THE DEFECT. tests/test-bl312-tldr-mode.sh U1 ran scripts/upgrade-project.sh
# with the contributor's real HOME, and its Guardrails pull
# (`# BL-320-UP-PULL`) fast-forwarded the real ~/.claude-dev-framework
# (4180f22 to da3b478 on 2026-10-08). CI never saw it: a runner's HOME holds no
# clone, so the pull is skipped there and the suite is green.
#
# THE CHECK. tests/test-helpers/home-clone-guard.sh. The unit-shard step plants
# a stand-in at $HOME/.claude-dev-framework: a one-file repository on main (not
# the Guardrails, so no reader on the leg finds a usable clone) whose origin is a
# local bare repository one commit ahead, so a pull moves it. After every suite
# it fails the suite when anything under that clone was written since it was
# planted, then plants it again, so the next suite is judged alone.
#
# CASES
#   G1  hcg_plant: one file on main and nothing a Guardrails reader looks for,
#       tracking an origin one commit ahead; hcg_check passes
#   G2  readers leave it passing: rev-parse, show, log, status, diff, config,
#       cat, and a `git clone --no-local` out of it (what cdf_fixture_copy does)
#   G3  a `pull --ff-only` fails it, and HCG_WHY says the HEAD moved
#   G4  a fetch alone (no HEAD move) fails it
#   G5  a file written in the work tree fails it
#   G6  the clone removed fails it
#   G7  hcg_plant refuses a path that exists (a directory, a dangling symlink)
#       and leaves it as it was
#   G8  hcg_replant after a touch puts back a fresh plant; with nothing planted
#       in the shell it refuses and removes nothing
#   G9  the unit-shard step's own loop (extracted from tests.yml) over five
#       throwaway suites — clean, one that pulls $HOME/.claude-dev-framework,
#       clean, one that fails without touching, one that pulls and fails — fails
#       exactly the last three, each once, and does not blame the clean suite
#       after the puller
#   G10 that loop exits before any suite runs when the clone cannot be planted
#   G11 the stamp moved away fails it, by itself and before a pull (review
#       R-344-2: `find -newer` on a missing stamp errored into silence)
#   G12 `git rm --cached` fails it (a write to the index alone)
#   G13 `git update-index --chmod=+x` fails it (the same)
#   G14 .git/config deleted fails it; .git/HEAD deleted fails it (a removal
#       under .git changes only the .git directory's own time)
#   M   mutants of the helper and of the step, each killed by a named case
#
# Hermetic: temp dirs only; every fixture is a local repository, and every HOME
# here is a temp folder. Fixture git runs with GIT_CONFIG_NOSYSTEM=1
# GIT_CONFIG_GLOBAL=/dev/null (a runner's config). bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF SOIF_TEST_CDF_FIXTURE CDF_HOME 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl344.XXXXXX")"
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
HELPER=tests/test-helpers/home-clone-guard.sh
WF=.github/workflows/tests.yml
rgit() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -c user.name=t -c user.email=t@t.invalid "$@"; }

# in_guard FW SCRIPT — SCRIPT run with FW's helper sourced.
in_guard() { ( . "$1/$HELPER" || exit 90; eval "$2" ); }
# planted FW DIR SCRIPT — plant DIR/home/.claude-dev-framework, then run
# SCRIPT in the same shell. FIX is the planted HEAD.
planted() {
  local fw="$1" d="$2"
  mkdir -p "$d/home" || return 91
  in_guard "$fw" 'C="'"$d"'/home/.claude-dev-framework"
    hcg_plant "$C" "'"$d"'/w" || { echo "plant: $HCG_WHY"; exit 92; }
    FIX="$(rgit -C "$C" rev-parse HEAD)"
    '"$3"
}

case_G1() {   # FW — the plant
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    hcg_check || { echo "an untouched plant fails: $HCG_WHY"; exit 1; }
    [ "$HCG_HEAD" = "$FIX" ] || { echo "HCG_HEAD is not the planted HEAD"; exit 1; }
    [ "$(cd "$C" && ls -A | tr "\n" " ")" = ".git BL344-PLANTED " ] || { echo "the plant holds more than one file: $(cd "$C" && ls -A | tr "\n" " ")"; exit 1; }
    [ "$(rgit -C "$C" symbolic-ref -q HEAD)" = refs/heads/main ] || { echo "not on main"; exit 1; }
    [ "$(rgit -C "$C" rev-parse --abbrev-ref "@{upstream}")" = origin/main ] || { echo "main does not track origin/main"; exit 1; }
    [ "$(rgit -C "$C" config --get remote.origin.url)" = "$HCG_WORK/up.git" ] || { echo "origin is not the planted upstream"; exit 1; }
    up="$(rgit -C "$HCG_WORK/up.git" rev-parse -q --verify refs/heads/main)"
    [ -n "$up" ] && [ "$up" != "$FIX" ] && [ "$(rgit -C "$HCG_WORK/up.git" rev-parse "$up^")" = "$FIX" ] \
      || { echo "origin main (${up:-none}) is not one commit past the planted HEAD"; exit 1; }' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G2() {   # FW — readers
  local out="" d=""
  d="$(newtmp)"
  out="$(planted "$1" "$d" '
    rgit -C "$C" rev-parse HEAD >/dev/null && rgit -C "$C" show HEAD:BL344-PLANTED >/dev/null \
      && rgit -C "$C" log -1 --format=%H >/dev/null && rgit -C "$C" status --porcelain >/dev/null \
      && { rgit -C "$C" diff --quiet; :; } && rgit -C "$C" config --get remote.origin.url >/dev/null \
      && cat "$C/BL344-PLANTED" >/dev/null && rgit -C "$C" rev-parse "@{upstream}" >/dev/null \
      && rgit clone -q --no-local --no-checkout "$C" "'"$d"'/copy" || { echo "a reader failed"; exit 1; }
    hcg_check || { echo "readers fail it: $HCG_WHY"; exit 1; }' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G3() {   # FW — a pull
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    rgit -C "$C" pull --ff-only --quiet || { echo "the pull itself failed"; exit 1; }
    hcg_check && { echo "a pull passes"; exit 1; }
    case "$HCG_WHY" in *"HEAD moved from ${FIX:0:7} to "*) ;; *) echo "HCG_WHY does not say the HEAD moved: $HCG_WHY"; exit 1 ;; esac' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G4() {   # FW — a fetch alone
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    rgit -C "$C" fetch -q || { echo "the fetch itself failed"; exit 1; }
    [ "$(rgit -C "$C" rev-parse HEAD)" = "$FIX" ] || { echo "the fetch moved HEAD"; exit 1; }
    hcg_check && { echo "a fetch passes"; exit 1; }; :' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G5() {   # FW — a write in the work tree
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    printf "changed\n" >> "$C/BL344-PLANTED"
    hcg_check && { echo "a written file passes"; exit 1; }
    case "$HCG_WHY" in *BL344-PLANTED*) ;; *) echo "HCG_WHY does not name the file: $HCG_WHY"; exit 1 ;; esac' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G6() {   # FW — the clone removed
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    rm -rf "$C"
    hcg_check && { echo "a removed clone passes"; exit 1; }
    case "$HCG_WHY" in *"is gone"*) ;; *) echo "HCG_WHY: $HCG_WHY"; exit 1 ;; esac' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G7() {   # FW — never over an existing path
  local fw="$1" d="" out="" rc=0
  d="$(newtmp)"
  mkdir -p "$d/h1/.claude-dev-framework" && printf 'mine\n' > "$d/h1/.claude-dev-framework/keep" || return 1
  mkdir -p "$d/h2" && ln -s "$d/nowhere" "$d/h2/.claude-dev-framework" || return 1
  rc=0; out="$(in_guard "$fw" 'hcg_plant "'"$d"'/h1/.claude-dev-framework" "'"$d"'/w1"; r=$?; echo "$HCG_WHY"; exit $r' 2>&1)" || rc=$?
  [ "$rc" = 1 ] && grep -qF "already exists" <<< "$out" || { CASE_DETAIL="an existing directory: rc $rc: $out"; return 1; }
  [ "$(ls -A "$d/h1/.claude-dev-framework")" = keep ] && [ "$(cat "$d/h1/.claude-dev-framework/keep")" = mine ] \
    || { CASE_DETAIL="the existing directory was changed"; return 1; }
  rc=0; out="$(in_guard "$fw" 'hcg_plant "'"$d"'/h2/.claude-dev-framework" "'"$d"'/w2"; r=$?; echo "$HCG_WHY"; exit $r' 2>&1)" || rc=$?
  [ "$rc" = 1 ] && [ -L "$d/h2/.claude-dev-framework" ] && [ ! -e "$d/nowhere" ] \
    || { CASE_DETAIL="a dangling symlink: rc $rc: $out"; return 1; }
}
case_G8() {   # FW — plant again
  local fw="$1" d="" out="" rc=0
  out="$(planted "$fw" "$(newtmp)" '
    rgit -C "$C" pull --ff-only --quiet && printf x > "$C/stray" || { echo "fixture: pull"; exit 1; }
    hcg_check && { echo "the touch was not seen"; exit 1; }
    hcg_replant || { echo "replant: $HCG_WHY"; exit 1; }
    [ "$(rgit -C "$C" rev-parse HEAD)" = "$HCG_HEAD" ] && [ ! -e "$C/stray" ] && [ ! -e "$C/BL344-AHEAD" ] || { echo "the replant is not a fresh plant"; exit 1; }
    hcg_check || { echo "fails right after a replant: $HCG_WHY"; exit 1; }' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
  d="$(newtmp)"; mkdir -p "$d/home/.claude-dev-framework" && printf 'mine\n' > "$d/home/.claude-dev-framework/keep" || return 1
  # The variables as a plant would leave them, but no plant in this shell.
  rc=0; out="$(in_guard "$fw" 'HCG_CLONE="'"$d"'/home/.claude-dev-framework"; HCG_WORK="'"$d"'/w"; hcg_replant; r=$?; echo "$HCG_WHY"; exit $r' 2>&1)" || rc=$?
  [ "$rc" = 1 ] && [ "$(cat "$d/home/.claude-dev-framework/keep" 2>/dev/null)" = mine ] \
    || { CASE_DETAIL="a replant with nothing planted: rc $rc, keep is $(cat "$d/home/.claude-dev-framework/keep" 2>/dev/null || echo gone): $out"; return 1; }
}

# ── the step itself ──────────────────────────────────────────────────────────
# step_loop WF — the unit-shard step's lines from `failed=()` to the end of its
# suite loop, de-indented: the plant, the loop and the check, as CI runs them.
step_loop() {
  local start="" stop=""
  start="$(awk '/- name: Run fast unit tests — shard/{f=1} f && /^ *failed=\(\)$/{print NR; exit}' "$1")"
  stop="$(awk -v s="${start:-0}" 'NR > s && /# BL-344-RUNNER-LOOP-END$/{print NR; exit}' "$1")"
  [ -n "$start" ] && [ -n "$stop" ] || return 1
  sed -n "${start},${stop}p" "$1" | sed 's/^          //'
}
# run_loop FW DIR SUITE... — the extracted loop over SUITEs, from a copy of
# FW's helper, with DIR/home as HOME. Leaves DIR/out, DIR/rc.
run_loop() {
  local fw="$1" d="$2" sc="" s=""
  shift 2
  sc="$d/loop.sh"
  mkdir -p "$d/repo/tests/test-helpers" "$d/home" "$d/rt" && cp "$fw/$HELPER" "$d/repo/$HELPER" || return 1
  { printf 'set -uo pipefail\nrun_list=('; for s in "$@"; do printf ' %q' "$s"; done; printf ' )\n'
    step_loop "$fw/$WF" || return 1
    printf '%s\n' 'echo "FAILED=${failed[*]}"'; } > "$sc" || return 1
  ( cd "$d/repo" && env -u CDF_HOME HOME="$d/home" RUNNER_TEMP="$d/rt" SHARD=t \
      bash "$sc" </dev/null > "$d/out" 2>&1 ); printf '%s' "$?" > "$d/rc"
}
mk_suites() {   # DIR — five throwaway suites
  mkdir -p "$1/s" || return 1
  printf '#!/bin/bash\necho clean\n' > "$1/s/clean1.sh"
  printf '#!/bin/bash\ngit -C "$HOME/.claude-dev-framework" pull --ff-only --quiet\n' > "$1/s/pulls.sh"
  printf '#!/bin/bash\necho clean\n' > "$1/s/clean2.sh"
  printf '#!/bin/bash\nexit 3\n' > "$1/s/fails.sh"
  printf '#!/bin/bash\ngit -C "$HOME/.claude-dev-framework" pull --ff-only --quiet\nexit 4\n' > "$1/s/both.sh"
}
case_G9() {   # FW — the step fails the puller, the failing suite and the one that does both (once), only
  local fw="$1" d="" f="" bad=""
  d="$(newtmp)"; mk_suites "$d" || { CASE_DETAIL="fixture"; return 1; }
  run_loop "$fw" "$d" "$d/s/clean1.sh" "$d/s/pulls.sh" "$d/s/clean2.sh" "$d/s/fails.sh" "$d/s/both.sh" || { CASE_DETAIL="no loop to run (step_loop)"; return 1; }
  f="$(sed -n 's/^FAILED=//p' "$d/out")"
  [ "$f" = "$d/s/pulls.sh $d/s/fails.sh $d/s/both.sh" ] || bad="$bad [failed is '$f', want the puller, the failing suite and the one that does both, each once]"
  grep -qF "FAIL $d/s/both.sh: it touched the Guardrails clone in the runner's HOME" "$d/out" || bad="$bad [the suite that fails and pulls is not named as touching the clone]"
  grep -qF "FAIL $d/s/pulls.sh: it touched the Guardrails clone in the runner's HOME" "$d/out" || bad="$bad [the puller is not named as touching the clone]"
  grep -qxF "PASS $d/s/clean2.sh" "$d/out" || bad="$bad [the clean suite after the puller did not pass]"
  grep -qF "FAIL $d/s/clean2.sh" "$d/out" && bad="$bad [the clean suite after the puller was blamed]"
  CASE_DETAIL="$bad"
  [ -z "$bad" ] || CASE_DETAIL="$bad: $(tr '\n' ' ' < "$d/out" | cut -c1-400)"
  [ -z "$bad" ]
}
case_G10() {   # FW — no plant, no suites
  local fw="$1" d=""
  d="$(newtmp)"; mk_suites "$d" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/home/.claude-dev-framework" || return 1
  run_loop "$fw" "$d" "$d/s/clean1.sh" || { CASE_DETAIL="no loop to run (step_loop)"; return 1; }
  [ "$(cat "$d/rc")" != 0 ] && ! grep -q '^clean$' "$d/out" && grep -qF "already exists" "$d/out" \
    || { CASE_DETAIL="rc $(cat "$d/rc"): $(tr '\n' ' ' < "$d/out" | cut -c1-300)"; return 1; }
}

case_G11() {   # FW — the stamp moved away
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    mv "$HCG_WORK/stamp" "$HCG_WORK/stamp.moved"
    hcg_check && { echo "a missing stamp passes"; exit 1; }
    case "$HCG_WHY" in *stamp*) ;; *) echo "HCG_WHY does not name the stamp: $HCG_WHY"; exit 1 ;; esac
    hcg_replant || { echo "replant: $HCG_WHY"; exit 1; }
    mv "$HCG_WORK/stamp" "$HCG_WORK/stamp.moved" && rgit -C "$C" pull --ff-only --quiet || { echo "fixture: pull"; exit 1; }
    hcg_check && { echo "a pull after the stamp moved passes"; exit 1; }; :' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G12() {   # FW — git rm --cached
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    rgit -C "$C" rm -q --cached BL344-PLANTED || { echo "fixture: rm --cached"; exit 1; }
    hcg_check && { echo "git rm --cached passes"; exit 1; }; :' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G13() {   # FW — update-index --chmod
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    rgit -C "$C" update-index --chmod=+x BL344-PLANTED || { echo "fixture: chmod"; exit 1; }
    hcg_check && { echo "update-index --chmod passes"; exit 1; }; :' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}
case_G14() {   # FW — a file under .git deleted
  local out=""
  out="$(planted "$1" "$(newtmp)" '
    rm -f "$C/.git/config"
    hcg_check && { echo "a deleted .git/config passes"; exit 1; }
    hcg_replant || { echo "replant: $HCG_WHY"; exit 1; }
    rm -f "$C/.git/HEAD"
    hcg_check && { echo "a deleted .git/HEAD passes"; exit 1; }; :' 2>&1)" \
    || { CASE_DETAIL="$out"; return 1; }
}

check() {   # LABEL CASE
  CASE_DETAIL=""
  if "$2" "$REPO_ROOT"; then pass "$1${CASE_DETAIL:+ ($CASE_DETAIL)}"; else fail_ "$1" "${CASE_DETAIL:-failed}"; fi
}
echo "=== G — the check ==="
check "G1: the plant is one file on main, no Guardrails, tracking an origin one commit ahead; untouched it passes" case_G1
check "G2: readers (rev-parse, show, log, status, diff, config, cat, a clone out of it) leave it passing" case_G2
check "G3: a pull fails it and says the HEAD moved" case_G3
check "G4: a fetch alone fails it" case_G4
check "G5: a written file fails it, by name" case_G5
check "G6: a removed clone fails it" case_G6
check "G7: the plant refuses an existing directory or symlink and leaves it alone" case_G7
check "G8: a replant restores it; with nothing planted it refuses and removes nothing" case_G8
check "G9: the unit-shard loop fails the puller, the failing suite and the one that does both (once each), and not the clean suite after the puller" case_G9
check "G10: the unit-shard loop runs no suite when the clone cannot be planted" case_G10
check "G11: the stamp moved away fails it, alone and before a pull" case_G11
check "G12: git rm --cached (the index alone) fails it" case_G12
check "G13: git update-index --chmod (the index alone) fails it" case_G13
check "G14: a deleted .git/config fails it, and a deleted .git/HEAD" case_G14

# ── M: mutants ───────────────────────────────────────────────────────────────
ends_in() {   # FILE MARKER — how many lines end in MARKER
  MARK="$2" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$1"
}
mutate() {   # FILE MARKER REPLACEMENT — the one line ending in MARKER becomes REPLACEMENT
  local f="$1"
  [ "$(ends_in "$f" "$2")" = 1 ] || { echo "marker '$2' ends $(ends_in "$f" "$2") line(s) of $f (need 1)"; return 1; }
  MARK="$2" REPL="$3" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' "$f" > "$f.mut" \
    && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(ends_in "$f" "$2")" = 0 ] && [ "$(grep -cxF -- "$3" "$f")" -ge 1 ] || { echo "the replacement did not land"; return 1; }
  case "$f" in *.sh) bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; } ;; esac
}
mutant() {   # ID FILE MARKER REPLACEMENT KILLER WHAT
  local id="$1" file="$2" mark="$3" repl="$4" killer="$5" what="$6" m="" why="" rc=0
  m="$(newtmp)/mirror"
  mkdir -p "$m/tests/test-helpers" "$m/.github/workflows" && cp "$REPO_ROOT/$HELPER" "$m/$HELPER" && cp "$REPO_ROOT/$WF" "$m/$WF" \
    || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$file" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""; "$killer" "$m" || rc=$?
  if [ "$rc" -eq 0 ]; then fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes"
  else pass "$id (MUTATION) — $what: killed by ${killer#case_} ($(printf '%s' "${CASE_DETAIL:-failed}" | tr '\n' ' ' | cut -c1-200))"; fi
}
echo "=== M — mutants ==="
mutant M1 "$HELPER" '# BL-344-HCG-NOCLOBBER' '  if false; then' case_G7 "the plant goes over an existing path"
mutant M2 "$HELPER" '# BL-344-HCG-AHEAD' '  :' case_G1 "origin is not ahead, so a pull would not move the clone"
mutant M3 "$HELPER" '# BL-344-HCG-GONE' '  if false; then' case_G6 "a removed clone is not seen"
mutant M4 "$HELPER" '# BL-344-HCG-NEWER' '  if false; then' case_G5 "a file written under the clone is not seen"
mutant M5 "$HELPER" '# BL-344-HCG-INDEX' '  newer="$(find "$HCG_CLONE" -newer "$HCG_WORK/stamp" 2>/dev/null)"' case_G2 "an index refresh by a reader counts as a touch"
mutant M6 "$HELPER" '# BL-344-HCG-REPLANT-OWN' '  :' case_G8 "a replant removes a clone this shell did not plant"
mutant M7 "$HELPER" '# BL-344-HCG-WHY-HEAD' '  :' case_G3 "HCG_WHY does not say the HEAD moved"
mutant M8 "$HELPER" '# BL-344-HCG-STAMP' '  :' case_G1 "no stamp is written, so nothing could ever be newer"
mutant M9 "$HELPER" '# BL-344-HCG-WHY' '  HCG_WHY=""' case_G5 "HCG_WHY does not name what was written"
mutant M10 "$HELPER" '# BL-344-HCG-REPLANT-RM' '  :' case_G8 "a replant does not clear the touched clone first"
mutant M11 "$HELPER" '# BL-344-HCG-STAMP-GONE' '  if false; then' case_G11 "a missing stamp passes (find -newer fails into silence)"
mutant M12 "$HELPER" '# BL-344-HCG-PATHS' '  elif false; then' case_G14 "a path removed under .git is not seen"
mutant M13 "$HELPER" '# BL-344-HCG-STAGED' '  elif false; then' case_G12 "a write to the index alone is not seen"
mutant M14 "$HELPER" '# BL-344-HCG-BASELINE' '  :' case_G1 "what was planted is not recorded"
mutant M15 "$HELPER" '# BL-344-HCG-PATHLIST' '_hcg_paths() { :; }' case_G14 "the path listing lists nothing, so a removal compares equal"
mutant M16 "$WF" '# BL-344-RUNNER-CHECK' '            if false; then' case_G9 "the step never checks the clone"
mutant M17 "$WF" '# BL-344-RUNNER-REPLANT' '              :' case_G9 "the step does not plant again after a touch"
mutant M18 "$WF" '# BL-344-RUNNER-SOURCE' '          :' case_G9 "the step does not load the check"
mutant M19 "$WF" '# BL-344-RUNNER-SAY' '              :' case_G9 "the step does not say which suite touched the clone"
mutant M20 "$WF" '# BL-344-RUNNER-FAILED' '              :' case_G9 "a suite that touched the clone is not counted as failed"
mutant M21 "$WF" '# BL-344-RUNNER-FAILED' '              failed+=("${t}")' case_G9 "a suite that fails and touches the clone is counted twice"
mutant M22 "$WF" '# BL-344-RUNNER-PLANT' '          hcg_plant "$HOME/.claude-dev-framework" "$RUNNER_TEMP/bl344-home-clone"' case_G10 "the step runs the suites when the plant failed"

echo
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

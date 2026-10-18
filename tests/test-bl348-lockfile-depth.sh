#!/usr/bin/env bash
# tests/test-bl348-lockfile-depth.sh — `## BL-348:`.
#
# THE DEFECT. `verify_init` in scripts/process-checklist.sh decided
# `project_scaffolded` with `[ -f "$lf" ]` over a fixed list, from the
# repository root only. A project whose service lives in a subdirectory
# (pantheon-harness: `services/control-plane/package-lock.json`) printed
# `project_scaffolded — no lockfile found`, and the list had no `uv.lock`, so a
# uv-only Python project failed the same way. Karl ruled that a
# service-directory lockfile counts.
#
# THE FIX. The root loop runs first and is unchanged, with `uv.lock` added to
# the list. When it finds nothing, a find walk looks one and two directory
# levels below the root, pruning dependency, build and VCS trees, and a
# symlinked lockfile counts only when `_lockfile_inside_root` resolves it
# inside the repository (`# BL-348-LOCKFILE-*`, `# BL-348-INSIDE-*`). The OK
# line names the path it found; the FAIL line says where it looked.
#
# CASES
#   R  the root: a root lockfile still passes and is named; each name in the
#      list passes at the root, uv.lock included; a root lockfile wins over a
#      nested one; a root symlink still counts wherever it points (the root
#      check is unchanged — see `## BL-348:`)
#   N  each name in the list passes two levels down
#   D  depth: one and two levels down pass and are named; THREE levels down
#      (a/b/c/<lockfile>) does not count — that is the boundary
#   P  a lockfile under each pruned directory, at the first or the second
#      level, does not count
#   S  symlinks: one resolving outside the repository (file, directory,
#      relative escape, a sibling whose name extends the root's) does not
#      count; a dangling one does not; one resolving inside does, relative or
#      absolute, also when the root is reached through a symlinked path
#   X  a directory named like a lockfile does not count; no lockfile at all
#      fails and the line says where it looked; a path with spaces is named
#      intact; the named path does not depend on the order find prints in; an
#      unreadable directory is reported and the run goes on
#   M  mutants: each rewrites ONE marked line in a mirror of scripts/, checks
#      the edit landed by its literal text and still parses, and needs the
#      named case to go RED
#
# ~10s local. No init.sh, not an aggregator -> both lists. bash 3.2 safe.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-348 — project_scaffolded finds a lockfile two levels below the root =="
for t in jq find sort; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
REAL_FIND="$(command -v find)"

NAMES="package-lock.json yarn.lock pnpm-lock.yaml Pipfile.lock poetry.lock uv.lock Cargo.lock go.sum pubspec.lock Package.resolved gradle.lockfile packages.lock.json"
SKIPDIRS="node_modules .git vendor .venv venv target build dist Pods .dart_tool .gradle"
FAIL_HEAD="[FAIL] project_scaffolded — no lockfile found in the root or one or two directory levels below it"

# check LABEL CASE [ARGS…] — run a case and report it.
CASE_DETAIL=""
check() {
  local label="$1" fn="$2"; shift 2
  CASE_DETAIL=""
  if "$fn" "$@"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

# _run ROOT DIR [PATH_PREFIX] — run ROOT's --verify-init with DIR as the cwd.
# Sets OUT (stdout+stderr), RC, LINE (the project_scaffolded [OK]/[FAIL] line)
# and STATE (yes when process-state.json records project_scaffolded).
OUT=""; RC=0; LINE=""; STATE=""
_run() {
  local root="$1" dir="$2" pre="${3:-}" path="$PATH"
  [ -n "$pre" ] && path="$pre:$PATH"
  RC=0
  OUT="$(cd "$dir" && PATH="$path" bash "$root/scripts/process-checklist.sh" --verify-init 2>&1)" || RC=$?
  LINE="$(printf '%s\n' "$OUT" | command grep -E '^(  \[OK\]|\[FAIL\]) project_scaffolded — ' | sed -n '1p')"
  STATE="no"
  if jq -e '.phase2_init.steps_completed | index("project_scaffolded") != null' \
       "$dir/.claude/process-state.json" >/dev/null 2>&1; then STATE="yes"; fi
}
# _expect_ok ROOT DIR PATH — passes, names PATH, records the step.
_expect_ok() {
  _run "$1" "$2" "${4:-}"
  local want="  [OK] project_scaffolded — lockfile found: $3"
  [ "$LINE" = "$want" ] || { CASE_DETAIL="line was '$LINE', want '$want' (rc=$RC)"; return 1; }
  [ "$STATE" = "yes" ] || { CASE_DETAIL="passed but process-state.json does not record project_scaffolded"; return 1; }
}
# _expect_fail ROOT DIR — fails with the BL-348 line and records nothing.
_expect_fail() {
  _run "$1" "$2"
  case "$LINE" in
    "$FAIL_HEAD"*) : ;;
    *) CASE_DETAIL="line was '$LINE', want it to start '$FAIL_HEAD' (rc=$RC)"; return 1 ;;
  esac
  [ "$STATE" = "no" ] || { CASE_DETAIL="failed but process-state.json records project_scaffolded"; return 1; }
}
# _proj — a fresh project directory; prints its path.
_proj() { local p; p="$(newtmp)/proj"; mkdir -p "$p" && printf '%s' "$p"; }
# _put DIR REL… — create each REL as a file (parents made).
_put() {
  local d="$1" r; shift
  for r in "$@"; do mkdir -p "$d/$(dirname "$r")" && printf 'lock\n' > "$d/$r"; done
}

# ── R — the root ───────────────────────────────────────────────────────────
case_R1() { local p; p="$(_proj)"; _put "$p" package-lock.json; _expect_ok "$1" "$p" package-lock.json; }
case_Rname() { local p; p="$(_proj)"; _put "$p" "$2"; _expect_ok "$1" "$p" "$2"; }
case_O1() {   # the root check runs first: a root lockfile wins over a nested one
  local p; p="$(_proj)"; _put "$p" yarn.lock a/package-lock.json
  _expect_ok "$1" "$p" yarn.lock
}
case_R3() {   # the root check is unchanged: `[ -f ]` follows a root symlink wherever it points
  local p o; p="$(_proj)"; o="$(newtmp)"; _put "$o" package-lock.json
  ln -s "$o/package-lock.json" "$p/package-lock.json"
  _expect_ok "$1" "$p" package-lock.json
}

# ── N — each name two levels down ──────────────────────────────────────────
case_Nname() { local p; p="$(_proj)"; _put "$p" "svc/api/$2"; _expect_ok "$1" "$p" "svc/api/$2"; }

# ── D — depth ──────────────────────────────────────────────────────────────
case_D1() { local p; p="$(_proj)"; _put "$p" services/package-lock.json; _expect_ok "$1" "$p" services/package-lock.json; }
case_D2() { local p; p="$(_proj)"; _put "$p" services/control-plane/package-lock.json; _expect_ok "$1" "$p" services/control-plane/package-lock.json; }
case_D3() { local p; p="$(_proj)"; _put "$p" services/control-plane/api/package-lock.json; _expect_fail "$1" "$p"; }

# ── P — pruned directories ─────────────────────────────────────────────────
case_Pdir() { local p; p="$(_proj)"; _put "$p" "$2/package-lock.json" "$2/pkg/yarn.lock"; _expect_fail "$1" "$p"; }
case_P2() { local p; p="$(_proj)"; _put "$p" services/node_modules/package-lock.json services/vendor/go.sum; _expect_fail "$1" "$p"; }

# ── S — symlinks ───────────────────────────────────────────────────────────
case_S1() {   # a file symlink to a lockfile outside the repository
  local p o; p="$(_proj)"; o="$(newtmp)"; _put "$o" package-lock.json
  mkdir -p "$p/services/api" && ln -s "$o/package-lock.json" "$p/services/api/package-lock.json"
  _expect_fail "$1" "$p"
}
case_S2() {   # a directory symlink to a tree outside the repository
  local p o; p="$(_proj)"; o="$(newtmp)"; _put "$o" svc/package-lock.json svc/api/yarn.lock
  ln -s "$o/svc" "$p/services"
  _expect_fail "$1" "$p"
}
case_S3() {   # a relative symlink to a file inside the repository counts
  local p; p="$(_proj)"; _put "$p" shared/requirements.txt
  mkdir -p "$p/services/api" && ln -s ../../shared/requirements.txt "$p/services/api/Pipfile.lock"
  _expect_ok "$1" "$p" services/api/Pipfile.lock
}
case_S4() {   # an absolute symlink to a file inside the repository counts
  local p; p="$(_proj)"; _put "$p" shared/requirements.txt
  mkdir -p "$p/services/api" && ln -s "$p/shared/requirements.txt" "$p/services/api/Pipfile.lock"
  _expect_ok "$1" "$p" services/api/Pipfile.lock
}
case_S5() {   # a dangling symlink, its directory inside the repository
  local p; p="$(_proj)"; mkdir -p "$p/services/api" && ln -s ../gone.lock "$p/services/api/package-lock.json"
  _expect_fail "$1" "$p"
}
case_S6() {   # a relative symlink that climbs out of the repository
  local p t; t="$(newtmp)"; p="$t/proj"; mkdir -p "$p/services/api"; _put "$t" outside/package-lock.json
  ln -s ../../../outside/package-lock.json "$p/services/api/package-lock.json"
  [ -f "$p/services/api/package-lock.json" ] || { CASE_DETAIL="fixture: the link does not resolve"; return 1; }
  _expect_fail "$1" "$p"
}
case_S7() {   # a sibling directory whose name extends the root's is outside it
  local p t; t="$(newtmp)"; p="$t/proj"; mkdir -p "$p/services/api"; _put "$t" proj-evil/package-lock.json
  ln -s "$t/proj-evil/package-lock.json" "$p/services/api/package-lock.json"
  _expect_fail "$1" "$p"
}
case_S8() {   # the root reached through a symlinked path: an inside link still counts
  local p a; p="$(_proj)"; _put "$p" shared/requirements.txt
  mkdir -p "$p/services/api" && ln -s ../../shared/requirements.txt "$p/services/api/Pipfile.lock"
  a="$(newtmp)/alias"; ln -s "$p" "$a"
  _expect_ok "$1" "$a" services/api/Pipfile.lock
}
case_S9() {   # a two-hop chain: an inside link to a root link that resolves outside the repository
  local p o; p="$(_proj)"; o="$(newtmp)"; _put "$o" package-lock.json
  ln -s "$o/package-lock.json" "$p/l1"
  mkdir -p "$p/services/api" && ln -s ../../l1 "$p/services/api/package-lock.json"
  [ -f "$p/services/api/package-lock.json" ] || { CASE_DETAIL="fixture: the chain does not resolve"; return 1; }
  _expect_fail "$1" "$p"
}

# ── X — the rest ───────────────────────────────────────────────────────────
case_X1() { local p; p="$(_proj)"; mkdir -p "$p/services/package-lock.json"; _expect_fail "$1" "$p"; }
case_F1() {   # no lockfile: the line says where it looked, names every lockfile and skipped directory
  local p want; p="$(_proj)"
  _expect_fail "$1" "$p" || return 1
  want="$FAIL_HEAD (looked for: $NAMES; skipped: $SKIPDIRS)"
  [ "$LINE" = "$want" ] || { CASE_DETAIL="line was '$LINE', want '$want'"; return 1; }
  case "$OUT" in *"[WARN] project_scaffolded"*) CASE_DETAIL="a WARN with nothing unreadable: $OUT"; return 1 ;; esac
}
case_SP1() {   # spaces in the root and in the service directory
  local p; p="$(newtmp)/my project"; mkdir -p "$p"; _put "$p" "my service/api/package-lock.json"
  _expect_ok "$1" "$p" "my service/api/package-lock.json"
}
case_O2() {   # a find that prints in reverse order: the named path is still the C-sorted first
  local p s; p="$(_proj)"; _put "$p" zulu/package-lock.json mike/svc/yarn.lock alpha/svc/package-lock.json
  s="$(newtmp)"; printf '#!/bin/sh\n"%s" "$@" | LC_ALL=C sort -r\n' "$REAL_FIND" > "$s/find"; chmod +x "$s/find"
  _expect_ok "$1" "$p" alpha/svc/package-lock.json "$s"
}
UNREADABLE_OK=""
case_W1() {   # an unreadable directory and no lockfile: WARN, FAIL, and the run goes on
  local p; p="$(_proj)"; mkdir -p "$p/data/pg"; chmod 000 "$p/data/pg"
  _expect_fail "$1" "$p"; local r=$?; chmod 755 "$p/data/pg"
  [ "$r" -eq 0 ] || return 1
  case "$OUT" in *"[WARN] project_scaffolded — find could not read every directory below the root (exit "*) : ;;
    *) CASE_DETAIL="no WARN naming find's exit: $OUT"; return 1 ;; esac
  [ "$RC" -eq 0 ] || { CASE_DETAIL="the run ended rc=$RC"; return 1; }
  case "$OUT" in *"pre_commit_hooks_installed"*) : ;; *) CASE_DETAIL="the run stopped before pre_commit_hooks_installed: $OUT"; return 1 ;; esac
}
case_W2() {   # an unreadable directory beside a lockfile: the lockfile counts, no WARN
  local p; p="$(_proj)"; mkdir -p "$p/data/pg"; chmod 000 "$p/data/pg"; _put "$p" services/api/package-lock.json
  _expect_ok "$1" "$p" services/api/package-lock.json; local r=$?; chmod 755 "$p/data/pg"
  [ "$r" -eq 0 ] || return 1
  case "$OUT" in *"[WARN] project_scaffolded"*) CASE_DETAIL="a WARN although a lockfile was found: $OUT"; return 1 ;; esac
}
# chmod 000 does not stop root, so the W cases need a user it stops.
_probe="$(newtmp)/probe"; mkdir -p "$_probe"; chmod 000 "$_probe"
if ! ls "$_probe" >/dev/null 2>&1; then UNREADABLE_OK=yes; fi
chmod 755 "$_probe"

echo
echo "=== R — the root ==="
check "R1 a root package-lock.json passes, named as before, and the step is recorded" case_R1 "$REPO_ROOT"
for n in $NAMES; do check "R2 $n at the root passes" case_Rname "$REPO_ROOT" "$n"; done
check "R3 the root check is unchanged: a root symlink counts wherever it points" case_R3 "$REPO_ROOT"
check "O1 a root yarn.lock wins over a/package-lock.json (the root check runs first)" case_O1 "$REPO_ROOT"
echo
echo "=== N — each name two directory levels down ==="
for n in $NAMES; do check "N1 svc/api/$n passes and is named" case_Nname "$REPO_ROOT" "$n"; done
echo
echo "=== D — depth ==="
check "D1 services/package-lock.json (one level down) passes and is named" case_D1 "$REPO_ROOT"
check "D2 services/control-plane/package-lock.json (two levels down, the pantheon-harness shape) passes, named, recorded" case_D2 "$REPO_ROOT"
check "D3 boundary: services/control-plane/api/package-lock.json (three levels down) does not count" case_D3 "$REPO_ROOT"
echo
echo "=== P — pruned directories ==="
for d in $SKIPDIRS; do check "P1 a lockfile under $d/ (one or two levels down) does not count" case_Pdir "$REPO_ROOT" "$d"; done
check "P2 services/node_modules/ and services/vendor/ are pruned at the second level too" case_P2 "$REPO_ROOT"
echo
echo "=== S — symlinks ==="
check "S1 a symlinked lockfile resolving outside the repository does not count" case_S1 "$REPO_ROOT"
check "S2 a lockfile under a symlinked directory outside the repository does not count" case_S2 "$REPO_ROOT"
check "S3 a relative symlink resolving inside the repository counts" case_S3 "$REPO_ROOT"
check "S4 an absolute symlink resolving inside the repository counts" case_S4 "$REPO_ROOT"
check "S5 a dangling symlink does not count" case_S5 "$REPO_ROOT"
check "S6 a relative symlink climbing out of the repository does not count" case_S6 "$REPO_ROOT"
check "S7 a symlink into a sibling whose name extends the root's (proj-evil) does not count" case_S7 "$REPO_ROOT"
check "S8 with the root reached through a symlinked path, an inside link still counts" case_S8 "$REPO_ROOT"
check "S9 a two-hop chain (inside link -> root link -> outside file) does not count" case_S9 "$REPO_ROOT"
echo
echo "=== X — no lockfile, odd names, order, unreadable directories ==="
check "X1 a directory named package-lock.json does not count" case_X1 "$REPO_ROOT"
check "F1 no lockfile: FAIL names the root and two levels below, every lockfile and every skipped directory" case_F1 "$REPO_ROOT"
check "SP1 a root and a service directory with spaces: the path is named intact" case_SP1 "$REPO_ROOT"
check "O2 find printing in reverse order: the named path is still the C-sorted first" case_O2 "$REPO_ROOT"
if [ -n "$UNREADABLE_OK" ]; then
  check "W1 an unreadable directory and no lockfile: WARN naming find's exit, FAIL, and the run goes on" case_W1 "$REPO_ROOT"
  check "W2 an unreadable directory beside a lockfile: the lockfile counts, no WARN" case_W2 "$REPO_ROOT"
else
  skip "W1, W2" "chmod 000 does not stop this user (root?), so no directory can be made unreadable"
fi

# ════════════════════════════════════════════════════════════════════════════
# M — mutants (the mirror-and-mutate pattern of tests/test-bl318-g1-test-command.sh)
# ════════════════════════════════════════════════════════════════════════════
echo
echo "=== M — every BL-348 marker is load-bearing ==="
mk_mirror() {
  mkdir -p "$2/scripts" && cp -Rp "$1/scripts/lib" "$2/scripts/" && cp -p "$1/scripts/process-checklist.sh" "$2/scripts/"
}
# mutate FILE MARKER REPLACEMENT — 0 iff exactly one line ends in MARKER, it now
# reads REPLACEMENT exactly, and the file still parses.
mutate() {
  local f="$1" mark="$2" repl="$3" n=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  command grep -qF -- "$mark" "$f" && { echo "marker still present after the edit"; return 1; }
  [ "$(command grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
# mutant ID MARKER REPLACEMENT KILLER WHAT [KILLER_ARG] — in a mirror of scripts/.
PC=scripts/process-checklist.sh
mutant() {
  local id="$1" mark="$2" repl="$3" killer="$4" what="$5" karg="${6:-}" m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$PC" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  if "$killer" "$m" $karg; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_}${karg:+ $karg} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}${karg:+ $karg}"
  fi
}
M_NAMES='# BL-348-LOCKFILE-NAMES'
M_SKIP='# BL-348-LOCKFILE-SKIPDIRS'
FIND_OK='    lf_cands=$(find . -maxdepth 3 -type d \( "${lf_pexpr[@]}" \) -prune -o \( "${lf_nexpr[@]}" \) -print | LC_ALL=C sort) || lf_walk_rc=$?'
mutant MN1 "$M_NAMES" '  local lockfiles=(package-lock.json yarn.lock pnpm-lock.yaml Pipfile.lock poetry.lock Cargo.lock go.sum pubspec.lock Package.resolved gradle.lockfile packages.lock.json)' \
  case_Rname "uv.lock is not in the list (half the defect)" uv.lock
# One mutant per pruned name: the list without it.
for d in $SKIPDIRS; do
  rest=""; for x in $SKIPDIRS; do [ "$x" = "$d" ] || rest="${rest:+$rest }$x"; done
  mutant "MS-$d" "$M_SKIP" "  local lf_prune=($rest)" case_Pdir "$d/ is not pruned, so a lockfile inside it counts" "$d"
done
mutant MR1 '# BL-348-LOCKFILE-ROOT' '    :' case_O1 "no root check: the walk decides and names a/package-lock.json over the root yarn.lock"
mutant MR2 '# BL-348-LOCKFILE-ROOT' '    :' case_R3 "no root check: a root symlink stops counting (the root's behaviour changed)"
mutant MW1 '# BL-348-LOCKFILE-WALK' '  if true; then' case_O1 "the walk runs after a root hit and overrides it"
mutant MW2 '# BL-348-LOCKFILE-WALK' '  if false; then' case_D2 "no walk: a service-directory lockfile fails again (the pantheon-harness defect)"
mutant ME1 '# BL-348-LOCKFILE-SKIP-EXPR' '    :' case_Pdir "only the first pruned name reaches find" .git
mutant ME2 '# BL-348-LOCKFILE-NAME-EXPR' '    :' case_Nname "only the first lockfile name reaches find" uv.lock
# The FIND mutants derive from the product's line: M0 pins that FIND_OK IS
# that line, and fmutant refuses a derivation that changed nothing.
_find_line="$(command grep -F -- '# BL-348-LOCKFILE-FIND' "$REPO_ROOT/$PC" | sed 's/[[:space:]]*# BL-348-LOCKFILE-FIND$//')"
if [ "$_find_line" = "$FIND_OK" ]; then pass "M0 FIND_OK is the product's find line, so the FIND mutants rewrite the real one"
else fail_ "M0 FIND_OK is the product's find line" "product line is '$_find_line'"; fi
fmutant() {
  if [ "$2" = "$FIND_OK" ]; then fail_ "$1" "the derived mutant is the unchanged line — the substitution missed"; return; fi
  mutant "$1" '# BL-348-LOCKFILE-FIND' "$2" "$3" "$4"
}
fmutant MF1 "${FIND_OK/-maxdepth 3/-maxdepth 4}" case_D3 "three levels down counts"
fmutant MF2 "${FIND_OK/-maxdepth 3/-maxdepth 2}" case_D2 "two levels down does not count"
fmutant MF3 "${FIND_OK/ -prune/}" case_P2 "nothing is pruned"
fmutant MF4 "${FIND_OK/ | LC_ALL=C sort/}" case_O2 "the named path follows find's order"
if [ -n "$UNREADABLE_OK" ]; then
  fmutant MF5 "${FIND_OK% || lf_walk_rc=\$\?}" case_W1 "find's exit is fatal under set -e: an unreadable directory ends the run"
else
  skip "MF5" "its killer W1 needs a user chmod 000 stops"
fi
mutant MP1 '# BL-348-LOCKFILE-PICK' '      if [ -n "$lf_cand" ]; then lf_path="${lf_cand#./}"; break; fi' case_S1 "every candidate counts, a link outside the repository included"
mutant MP2 '# BL-348-LOCKFILE-PICK' '      if _lockfile_inside_root "$lf_cand"; then lf_path="$lf_cand"; break; fi' case_D2 "the named path keeps find's ./ prefix"
mutant MO1 '# BL-348-LOCKFILE-OK' '    print_ok "project_scaffolded — lockfile found: $lf"' case_D2 "the OK line names the loop variable, not the path found"
if [ -n "$UNREADABLE_OK" ]; then
  mutant MX1 '# BL-348-LOCKFILE-WARN' '    if false; then' case_W1 "an unreadable directory is not reported"
else
  skip "MX1" "its killer W1 needs a user chmod 000 stops"
fi
mutant MX2 '# BL-348-LOCKFILE-WARN' '    if true; then' case_F1 "the WARN prints with nothing unreadable"
mutant MX3 '# BL-348-LOCKFILE-FAIL' '    print_fail "project_scaffolded — no lockfile found (${lockfiles[*]})"' case_F1 "the FAIL line does not say where it looked"
mutant MI1 '# BL-348-INSIDE-FILE' '  :' case_X1 "a directory named like a lockfile counts"
mutant MI2 '# BL-348-INSIDE-FILE' '  :' case_S5 "a dangling symlink counts"
mutant MI3 '# BL-348-INSIDE-ROOTDIR' '  root=$(pwd)' case_S8 "the root is compared by its logical path, so an inside link fails when the root is reached through a symlink"
mutant MI4 '# BL-348-INSIDE-LINK' '  while false; do' case_S1 "links are not followed: a link outside the repository counts"
mutant MI5 '# BL-348-INSIDE-HOP' '    case "$t" in /*) p="$t" ;; *) p="$t" ;; esac' case_S3 "a relative link is resolved from the root, not from its own directory"
mutant MI6 '# BL-348-INSIDE-HOP' '    case "$t" in /*) p="$(dirname "$p")/$t" ;; *) p="$(dirname "$p")/$t" ;; esac' case_S4 "an absolute link is resolved as if relative"
mutant MI7 '# BL-348-INSIDE-CONTAINED' '  case "$t/" in *) return 0 ;; esac' case_S1 "every resolved path is inside"
mutant MI8 '# BL-348-INSIDE-CONTAINED' '  case "$t/" in "$root"*) return 0 ;; esac' case_S7 "a sibling whose name extends the root's is inside"
mutant MI9 '# BL-348-INSIDE-LINK' '  for _h in 1; do [ -L "$p" ] || break' case_S9 "only the first hop is followed: a chain whose second hop leaves the repository counts"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

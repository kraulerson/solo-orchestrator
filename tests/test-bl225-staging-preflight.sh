#!/usr/bin/env bash
# tests/test-bl225-staging-preflight.sh — BL-225.
#
# THE DEFECT, reproduced in T1 rather than described: the driver writes its
# files, stages every recorded path in ONE `git add`, and `git add` on a mixed
# pathspec STAGES THE CLEAN ONES AND EXITS 1. The adoptee is left half-staged
# under a refusal that says "nothing has been committed" — true of commits,
# silent about the index.
#
# Measured here, not assumed (T1): with `.claude/` ignored, a three-path add
# leaves two paths in the index and returns 1.
#
# ── HOST GIT CONFIG IS NEUTRALIZED, AND IT HAS TO BE ────────────────────────
# Inherited verbatim from tests/test-brownfield-wp6-collision-archive.sh's
# R-WP6-3, which MEASURED the cause on this host: `~/.config/git/ignore`
# commonly carries `**/.claude/settings.local.json`, and it is found by a PATH
# default (`$XDG_CONFIG_HOME/git/ignore`), NOT by a config key — so
# GIT_CONFIG_GLOBAL does not cover it. XDG_CONFIG_HOME is the knob. A fixture
# whose verdict depends on whose laptop runs it is not a fixture.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_TEMPLATE_DIR
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_COMMON_DIR
# The pathspec-magic family (R-WP6-18): with these set, `git check-ignore`
# dies "pathspec magic not supported by this command", and any probe that
# wraps it in 2>/dev/null scores the fatal as NOT IGNORED — fail-open. T5
# pins that the product code refuses instead.
unset GIT_LITERAL_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_GLOB_PATHSPECS GIT_ICASE_PATHSPECS

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl225.XXXXXX")" || exit 1
# BL-244: mktemp must not silently land in the launch directory.
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'rm -rf "$WORK"' EXIT

_adoptee() {                     # _adoptee DIR [ignore-line...]
  local d="$1"; shift
  mkdir -p "$d" && ( cd "$d" \
    && git init -q -b main . \
    && git config user.email t@example.com && git config user.name T \
    && printf 'their code\n' > README.md \
    && { [ "$#" -eq 0 ] || printf '%s\n' "$@" > .gitignore; } \
    && git add -A && git commit -q -m 'chore: their history' ) || return 1
}
_staged()  { ( cd "$1" && git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ' ); }
_sites()   { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac; }
_parses_ok() { bash -n "$1" >/dev/null 2>&1 && echo 1 || echo 0; }

echo "== T1 — the defect itself: a mixed pathspec half-stages =="
P="$WORK/t1"; _adoptee "$P" '.claude/'
mkdir -p "$P/.claude"; printf 'a\n' > "$P/a.txt"; printf 'b\n' > "$P/b.txt"; printf 'c\n' > "$P/.claude/manifest.json"
( cd "$P" && git add -- a.txt b.txt .claude/manifest.json ) >/dev/null 2>&1; rc=$?
chk "T1: git add on a mixed pathspec exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
chk "T1: and it staged the clean paths anyway (the half-staged tree)" "$(_staged "$P")" "2"

echo "== T2 — adopt_paths_ignored names an ignored path and fails closed =="
. "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" 2>/dev/null
if ! command -v adopt_paths_ignored >/dev/null 2>&1; then
  bad "T2: adopt_paths_ignored is not defined (RED before the fix)"
  bad "T2: (dependent assertions skipped)"; bad "T3: (skipped)"; bad "T4: (skipped)"; bad "T5: (skipped)"
else
  P2="$WORK/t2"; _adoptee "$P2" '.claude/'
  out="$(adopt_paths_ignored "$P2" ".claude/manifest.json" "README.md" 2>&1)"; rc=$?
  chk "T2: reports rc=0 when at least one path is ignored" "$rc" "0"
  chk "T2: and names the ignored path" "$(printf '%s' "$out" | grep -c 'manifest.json')" "1"
  chk "T2: and does NOT name the clean one" "$(printf '%s' "$out" | grep -c 'README.md')" "0"

  P3="$WORK/t3"; _adoptee "$P3"
  adopt_paths_ignored "$P3" ".claude/manifest.json" "README.md" >/dev/null 2>&1
  chk "T3: rc=1 when nothing is ignored" "$?" "1"

  echo "== T5 — a check-ignore that CANNOT RUN is not 'nothing is ignored' =="
  P5="$WORK/t5"; _adoptee "$P5" 'sub/*.txt'
  # GIT_NOGLOB_PATHSPECS makes check-ignore FATAL. A 2>/dev/null probe scores
  # that as clean; this must fail CLOSED instead (rc 0 = treat as ignored).
  GIT_NOGLOB_PATHSPECS=1 adopt_paths_ignored "$P5" "sub/a.txt" >/dev/null 2>&1
  chk "T5: fails CLOSED when check-ignore cannot run" "$?" "0"
fi

echo "== T4 — the staging guard: refuse whole, never half =="
if ! grep -q '# BL-225-STAGE-PREFLIGHT' "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" 2>/dev/null; then
  bad "T4: # BL-225-STAGE-PREFLIGHT marker absent (RED before the fix)"
else
  ok "T4: # BL-225-STAGE-PREFLIGHT marker present in adopt_stage_and_commit"
  chk "T4: the guard precedes the git add" \
    "$(awk '/# BL-225-STAGE-PREFLIGHT/{g=NR} /BF-ADOPT-STAGE-EXPLICIT/{a=NR} END{print (g && a && g<a) ? "yes" : "no"}' "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh")" "yes"
  # NOT a grep of adopt-state.sh: the sentence never lived there, so that
  # assertion was true of the unfixed tree too. The claim is adopt_refuse's,
  # in adopt-core.sh, and it is asserted by BEHAVIOUR.
  chk "T4: adopt_refuse no longer states the bare unconditional claim" \
    "$(_sites "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" "Adoption did not complete. Nothing has been committed.\\\\n' >&2")" "0"
fi

echo "== T6 — adopt_stage_and_commit refuses WHOLE: rc!=0 and index untouched =="
_stage_fixture() {                # $1 = dir
  local p="$1"
  _adoptee "$p" '.claude/' || return 1
  mkdir -p "$p/.claude"
  printf 'a\n' > "$p/keep-a.txt"; printf 'b\n' > "$p/keep-b.txt"
  printf '{}\n'  > "$p/.claude/manifest.json"
  printf 'keep-a.txt\nkeep-b.txt\n.claude/manifest.json\n' > "$p/.ledger"
}
_run_stage() {                    # $1 = dir, $2 = lib dir -> "rc|staged|stderr"
  ( set +e
    ADOPT_PROJECT_NAME=t
    . "$2/adopt-core.sh"  >/dev/null 2>&1
    . "$2/adopt-state.sh" >/dev/null 2>&1
    # SET THE LEDGER **AFTER** SOURCING. adopt-core.sh declares
    # ADOPT_WRITTEN_LEDGER="" at load time, so an earlier draft that set it
    # first had it silently wiped: the ledger read empty, adopt_stage_and_commit
    # took its "nothing to commit" arm, and T6's rc!=0 / staged==0 assertions
    # passed FOR THE WRONG REASON — both are equally true of an empty ledger.
    # M2 exposed it, because mutant and control produced identical output.
    # Hence the stderr discriminator: rc and a count cannot tell the two
    # refusals apart, and only one of them is this suite's subject.
    ADOPT_WRITTEN_LEDGER="$1/.ledger"
    err=$(adopt_stage_and_commit "$1" 2>&1 >/dev/null); rc=$?
    printf '%s|%s|%s\n' "$rc" \
      "$( cd "$1" && git diff --cached --name-only | wc -l | tr -d ' ' )" \
      "$(printf '%s' "$err" | tr '\n' ' ')" )
}
P6="$WORK/t6"; _stage_fixture "$P6"
IFS='|' read -r t6rc t6staged t6err <<<"$(_run_stage "$P6" "$REPO_ROOT/scripts/lib/adopt")"
chk "T6: refuses (rc != 0)"                        "$([ "${t6rc:-0}" -ne 0 ] && echo yes || echo no)" "yes"
chk "T6: and stages NOTHING (no half-staged tree)" "${t6staged:-x}" "0"
# POSITIVE CONTROLS. Without these the two assertions above are equally true of
# an EMPTY ledger, which is how they first passed against unfixed code.
chk "T6: refused via the PREFLIGHT, naming the ignored path" "$(printf '%s' "$t6err" | grep -c 'manifest.json')" "1"
chk "T6: not via the empty-ledger arm"                       "$(printf '%s' "$t6err" | grep -c 'no file was recorded as written')" "0"

echo "== M2 — the mutation that matters: neuter the preflight =="
MUTLIB="$WORK/mutlib"; mkdir -p "$MUTLIB"
cp "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" "$MUTLIB/adopt-core.sh"
sed 's/^  if _ignored=$(adopt_paths_ignored "$root" "${FILES_TO_STAGE\[@\]}"); then$/  if false; then/' \
  "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" > "$MUTLIB/adopt-state.sh"
nchanged=$(diff "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" "$MUTLIB/adopt-state.sh" | grep -c '^<')
if [ "$nchanged" -ne 1 ]; then
  bad "M2: mutation did not apply cleanly (changed $nchanged line(s))"
elif [ "$(_parses_ok "$MUTLIB/adopt-state.sh")" != "1" ]; then
  bad "M2: mutant does not parse"
else
  P7="$WORK/m2"; _stage_fixture "$P7"
  IFS='|' read -r m2rc m2staged m2err <<<"$(_run_stage "$P7" "$MUTLIB")"
  chk "M2: without the preflight the SAME fixture HALF-STAGES (RED)" \
    "$([ "${m2staged:-0}" -gt 0 ] && echo half-staged || echo "staged=${m2staged} err=${m2err}")" "half-staged"
  chk "M2: and the mutant reached git add, not the empty-ledger arm" \
    "$(printf '%s' "$m2err" | grep -c 'no file was recorded as written')" "0"
fi

echo "== M — mutation proofs =="
MUT="$WORK/mut"; mkdir -p "$MUT"
cp "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" "$MUT/core.orig"
if command -v adopt_paths_ignored >/dev/null 2>&1; then
  # M1: neuter the fail-closed arm -> a fatal check-ignore scores as clean.
  sed 's/return 0  # BL-225-IGNORE-FAILCLOSED/return 1/' "$MUT/core.orig" > "$MUT/core.mut"
  n=$(diff "$MUT/core.orig" "$MUT/core.mut" | grep -c '^<')
  if [ "$n" -ne 1 ]; then bad "M1: mutation did not apply (changed $n line(s))"; else
    ( set +e; unset -f adopt_paths_ignored; . "$MUT/core.mut" 2>/dev/null
      P="$WORK/m1"; mkdir -p "$P" && ( cd "$P" && git init -q -b main . && git config user.email t@e && git config user.name T \
        && printf 'x\n' > R.md && printf 'sub/*.txt\n' > .gitignore && git add -A && git commit -q -m b ) >/dev/null 2>&1
      GIT_NOGLOB_PATHSPECS=1 adopt_paths_ignored "$P" "sub/a.txt" >/dev/null 2>&1
      echo "$?" > "$WORK/m1.rc" )
    chk "M1: with the fail-closed arm neutered, a FATAL probe reports 'clean' (RED)" "$(cat "$WORK/m1.rc" 2>/dev/null)" "1"
  fi
fi
echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# tests/test-bl310-adopt-symlink-write.sh — `## BL-310:` row 4 and `## BL-351:`:
# adoption writes nothing outside the project through a symlink.
#
# WHAT WAS MEASURED BEFORE THE GUARD (main 5d3864e3, the same at c8efd995).
# Twenty planned files, each replaced by a symlink to a file outside the
# repository, one adoption each: eight outside files were overwritten
# (APPROVAL_LOG.md, PROJECT_INTAKE.md, five under .claude/ and
# scripts/check-phase-gate.sh), three of them by the pre-write rehearsal of a run
# that then refused and said "nothing was written to this project". With
# `.claude` an untracked symlink to an outside folder (`## BL-351:`), the
# rehearsal wrote 13 files and a folder there (12 files on a host with no
# Qdrant server registered, as here) and the refusal said the same.
#
# THE RULE UNDER TEST (`# BL-310-WRITE-GUARD` in scripts/lib/adopt/adopt-core.sh).
# A write is refused when its target, or a folder above it up to the project
# root, is a symlink that resolves OUTSIDE the project. A symlink that resolves
# inside keeps what adoption did before the guard: a file link is written
# through and the run completes; a path below a folder link meets the ignore
# check's refusal (git will not look beyond a symlink). The refusal happens at
# the writer, so the rehearsal meets it first and the copy it works in is the
# only thing that was written.
#
# CASES
#   U1-U17  the predicate and the guard, called directly: a file link out, a
#           folder link out, links that resolve inside, a chain, a dangling
#           link, a loop, `..` below a missing folder, spaces, the writer
#           refusing and writing nothing, the rehearsal asking the real project,
#           the rehearsal's re-pointing of links into the project (every
#           spelling), a dangling link above the leaf, a sibling folder whose
#           name starts with the project's, a root reached through a symlinked
#           folder, and a root typed in the wrong case
#   A1      APPROVAL_LOG.md is a symlink to an outside file: refused, the file
#           byte-identical, the project and HEAD unchanged
#   A2      scripts/check-phase-gate.sh is a symlink to an outside file: refused
#   A3      .semgrep is a symlink to an outside folder: refused, folder unchanged
#   A4      `## BL-351:` — .claude is a symlink to an outside folder: refused
#           before any write, rehearsal included; a checksum listing of the
#           folder is the same before and after; "nothing was written" is said
#           and true
#   A5      the same with a RELATIVE link: the refusal names where it resolves
#           in the real project, not in the rehearsal's copy
#   A6      a relative file link that resolves inside: adoption completes and
#           writes through it, as before the guard
#   A7      the same with an ABSOLUTE link into the project
#   A8      .claude is an ABSOLUTE link to a folder inside the project: refused
#           as before the guard, and the rehearsal wrote nothing into it
#   A9      a chain, inside -> outside: refused, the outside file unchanged
#   A10     a path with a space: refused and nothing outside changed
#   A11     a normal adoption in a path with a space completes (no false refusal)
#   A12     `--re-add` onto a symlink to an outside file: refused, unchanged
#   A13     .claude/framework is a symlink to an outside folder, the Guardrails
#           installer present: refused before it runs
#   A14     .claude/adoption-archive is a symlink to an outside folder: refused,
#           nothing archived there
#   A15     .claude/bypass-audit.json is a symlink to an outside ledger: the
#           audit rows are not written through it, the link stays, and the run
#           completes saying the row could not be recorded — with no
#           "Nothing was committed" printed into a run that commits, no "run
#           this again", and an archive note that names the symlink
#   A16     .git/hooks/commit-msg is a symlink to an outside shared hook: not
#           written, its mode not changed, and the run says NOT INSTALLED
#   A17     .git is a symlink to a repository outside (a `clone --shared`):
#           refused at step 0, that repository's alternates untouched
#   A18     the project reached through one alias and a file linked through a
#           second alias of the same folder: completes, written through
#   N1      every write site in scripts/lib/adopt/ has the guard in its function
#           within 30 lines before it, or a named exemption
#   M       mutants: each edits one marked line in a mirror and needs a named
#           case to go red
#
# Hermetic: temp dirs only, no network, the MCP step off, the Guardrails seam
# pointed at an empty folder or a stub. bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
export SOIF_ADOPT_MCP=off   # BL-311-MCP-SEAM
export SOIF_ADOPT_QDRANT=no

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl310.XXXXXX")" || exit 1
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM
WORK="$(cd -P "$WORK" && pwd -P)"
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
phys() { ( cd -P "$1" 2>/dev/null && pwd -P ); }
CASE_DETAIL=""
check() {   # LABEL CASE — run CASE against the real framework
  CASE_DETAIL=""
  if "$2" "$REPO_ROOT"; then
    case "$CASE_DETAIL" in "SKIP: "*) skip "$1" "${CASE_DETAIL#SKIP: }" ;; *) pass "$1" ;; esac
  else fail_ "$1" "$(printf '%s' "${CASE_DETAIL:-failed}" | tr '\n' ' ')"; fi
}

# ── fixtures ────────────────────────────────────────────────────────────────
NO_GR="$WORK/no-guardrails"; mkdir -p "$NO_GR"
_adoptee() {   # DIR — a small real project with its own history
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email bl310@test.invalid && git config user.name "BL310 Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf '# acme\n' > "$p/README.md"
  ( cd "$p" && git add package.json README.md && git commit -q -m "chore: their own history" ) >/dev/null 2>&1
}
SCAN="$WORK/scan/scout-report.json"
if ! _adoptee "$WORK/template" \
   || ! bash "$REPO_ROOT/scripts/scout.sh" --root "$WORK/template" --out "$WORK/scan" >/dev/null 2>&1 \
   || [ ! -s "$SCAN" ]; then
  fail_ "setup" "scripts/scout.sh produced no report, and every adoption here consumes one"
  echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 1
fi
ADOPT_RC=0; ADOPT_OUT=""; ADOPT_ERR=""
_adopt() {   # FW DIR [GUARDRAILS_DIR] — one real adoption; ADOPT_RC, ADOPT_OUT, ADOPT_ERR
  local fw="$1" p="$2" g="${3:-$NO_GR}" d=""
  d="$(newtmp)"; ADOPT_OUT="$d/out"; ADOPT_ERR="$d/err"
  ( cd "$p" && printf '1\nstandard\n1\n1\n1\n1\n' | SOIF_ADOPT_GUARDRAILS_DIR="$g" \
      bash "$fw/scripts/adopt-project.sh" --scan-report "$SCAN" ) > "$ADOPT_OUT" 2> "$ADOPT_ERR"
  ADOPT_RC=$?
}
# _listing DIR — every entry under DIR with its type and, for a file, its cksum.
_listing() {
  ( cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r f; do
      if [ -L "$f" ]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
      elif [ -f "$f" ]; then printf 'F %s %s\n' "$f" "$(cksum < "$f")"
      else printf 'D %s\n' "$f"; fi
    done )
}
_tree() { git -C "$1" status --porcelain --untracked-files=all --ignored 2>/dev/null; }
_head() { git -C "$1" rev-parse HEAD 2>/dev/null; }
# _refused_clean P OUTSIDE_BEFORE OUTSIDE TREE_BEFORE HEAD_BEFORE — the shared
# verdict of a refused run: non-zero, nothing outside changed, the project tree
# and HEAD as they were.
_refused_clean() {
  local p="$1" ob="$2" o="$3" tb="$4" hb="$5"
  [ "$ADOPT_RC" -ne 0 ] || { CASE_DETAIL="adoption completed (rc 0)"; return 1; }
  [ "$(_listing "$o")" = "$ob" ] || { CASE_DETAIL="outside changed: $(diff <(printf '%s\n' "$ob") <(_listing "$o") | grep -c '^[<>]') line(s) of the listing differ"; return 1; }
  [ "$(_tree "$p")" = "$tb" ] || { CASE_DETAIL="the project tree changed: $(_tree "$p" | tr '\n' ' ')"; return 1; }
  [ "$(_head "$p")" = "$hb" ] || { CASE_DETAIL="HEAD moved"; return 1; }
  return 0
}
_names_link() {   # REL RES — the refusal names the path and where it resolves
  grep -qF -- "$1 would be written through a symlink" "$ADOPT_ERR" "$ADOPT_OUT" \
    || { CASE_DETAIL="the refusal does not name $1: $(grep -m1 -hE 'REFUSED|BLOCKED|stopped because' "$ADOPT_ERR" "$ADOPT_OUT")"; return 1; }
  grep -qF -- "resolves to $2" "$ADOPT_ERR" "$ADOPT_OUT" \
    || { CASE_DETAIL="the refusal does not say it resolves to $2: $(grep -h 'would be written through' "$ADOPT_ERR" "$ADOPT_OUT" | head -1)"; return 1; }
  return 0
}

# ── U: the predicate and the guard, called directly ─────────────────────────
U_OUT=""
_u() {   # FW SCRIPT — run SCRIPT with the adoption libs sourced; its stdout+stderr in U_OUT
  U_OUT="$( ( . "$1/scripts/lib/helpers-core.sh" >/dev/null 2>&1
              . "$1/scripts/lib/adopt/adopt-core.sh" && . "$1/scripts/lib/adopt/adopt-state.sh" || exit 99
              eval "$2" ) 2>&1 )"
}
case_U1() {   # a file link to a file outside
  local d=""; d="$(newtmp)"; mkdir -p "$d/p" "$d/o"; printf 'x\n' > "$d/o/t.md"; ln -s "$d/o/t.md" "$d/p/A.md"
  _u "$1" "adopt_link_escape '$d/p' A.md && printf 'ESC|%s|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_TO\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|A.md|$d/o/t.md|$(phys "$d/o")/t.md" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U2() {   # a folder link to a folder outside
  local d=""; d="$(newtmp)"; mkdir -p "$d/p" "$d/o"; ln -s "$d/o" "$d/p/.claude"
  _u "$1" "adopt_link_escape '$d/p' .claude/test-debt.json && printf 'ESC|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|.claude|$(phys "$d/o")" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U3() {   # a relative file link that resolves inside: not an escape
  local d=""; d="$(newtmp)"; mkdir -p "$d/p/gov"; printf 'x\n' > "$d/p/gov/a.md"; ( cd "$d/p" && ln -s gov/a.md A.md )
  _u "$1" "adopt_link_escape '$d/p' A.md && echo ESC || echo INSIDE"
  [ "$U_OUT" = INSIDE ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U4() {   # an absolute folder link that resolves inside: not an escape
  local d=""; d="$(newtmp)"; mkdir -p "$d/p/cfg/claude"; ln -s "$d/p/cfg/claude" "$d/p/.claude"
  _u "$1" "adopt_link_escape '$d/p' .claude/x.json && echo ESC || echo INSIDE"
  [ "$U_OUT" = INSIDE ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U5() {   # a chain: a file link to an inside link to an outside file
  local d=""; d="$(newtmp)"; mkdir -p "$d/p/gov" "$d/o"; printf 'x\n' > "$d/o/t.md"
  ln -s "$d/o/t.md" "$d/p/gov/hop"; ( cd "$d/p" && ln -s gov/hop A.md )
  _u "$1" "adopt_link_escape '$d/p' A.md && printf 'ESC|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|A.md|$(phys "$d/o")/t.md" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U6() {   # a dangling file link, spelled through an inside alias of an outside folder
  # A write would create the file outside. The spelling starts with the project's
  # own path, so only the physical resolution of the folder part shows where it goes.
  local d=""; d="$(newtmp)"; mkdir -p "$d/p" "$d/o"; ln -s "$d/o" "$d/p/alias"; ln -s "$d/p/alias/new.md" "$d/p/A.md"
  _u "$1" "adopt_link_escape '$d/p' A.md && printf 'ESC|%s' \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|$(phys "$d/o")/new.md" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U7() {   # a loop cannot be resolved, and unknown counts as outside
  local d=""; d="$(newtmp)"; mkdir -p "$d/p"; ( cd "$d/p" && ln -s B A && ln -s A B )
  _u "$1" "adopt_link_escape '$d/p' A && printf 'ESC|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|A|" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U8() {   # no link anywhere, the path not there yet: not an escape
  local d=""; d="$(newtmp)"; mkdir -p "$d/p"
  _u "$1" "adopt_link_escape '$d/p' .claude/adoption/x.json && echo ESC || echo NONE"
  [ "$U_OUT" = NONE ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U9() {   # `..` below a folder that does not exist: mkdir -p would climb out, so unknown
  local d=""; d="$(newtmp)"; mkdir -p "$d/p"; ( cd "$d/p" && ln -s 'nodir/../../out' L )
  _u "$1" "adopt_link_escape '$d/p' L/x.md && printf 'ESC|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|L|" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U10() {   # spaces in the project, the link and the target
  local d=""; d="$(newtmp)"; mkdir -p "$d/my proj" "$d/out side/docs dir"; ln -s "$d/out side/docs dir" "$d/my proj/my docs"
  _u "$1" "adopt_link_escape '$d/my proj' 'my docs/x y.md' && printf 'ESC|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|my docs|$(phys "$d/out side/docs dir")" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U11() {   # the writer refuses, says where the link goes, and writes nothing; a plain path is written
  local d="" before=""; d="$(newtmp)"; mkdir -p "$d/p" "$d/o"; printf 'OUTSIDE\n' > "$d/o/t.md"; ln -s "$d/o/t.md" "$d/p/A.md"
  before="$(cksum < "$d/o/t.md")"
  _u "$1" "ADOPT_WRITTEN_LEDGER='$d/ledger'; : > '$d/ledger'; printf 'FRAMEWORK\n' | adopt_write_file '$d/p' A.md; echo \"rc=\$?\"; printf 'ok\n' | adopt_write_file '$d/p' docs/B.md; echo \"rc2=\$?\""
  case "$U_OUT" in *"rc=1"*) ;; *) CASE_DETAIL="the write through the link was not refused: $U_OUT"; return 1 ;; esac
  [ "$(cksum < "$d/o/t.md")" = "$before" ] || { CASE_DETAIL="the outside file changed"; return 1; }
  case "$U_OUT" in *"A.md would be written through a symlink that leads outside this project: A.md -> $d/o/t.md, which resolves to $(phys "$d/o")/t.md."*) ;;
    *) CASE_DETAIL="the refusal does not name the link and where it resolves: $U_OUT"; return 1 ;; esac
  grep -qx 'A.md' "$d/ledger" && { CASE_DETAIL="the refused path was recorded for staging"; return 1; }
  case "$U_OUT" in *"rc2=0"*) ;; *) CASE_DETAIL="a plain path was refused: $U_OUT"; return 1 ;; esac
  [ "$(cat "$d/p/docs/B.md" 2>/dev/null)" = ok ] || { CASE_DETAIL="a plain path was not written"; return 1; }
}
case_U12() {   # in the rehearsal the real project is asked too, and its answer is the one printed
  local d=""; d="$(newtmp)"; mkdir -p "$d/real" "$d/w/copy" "$d/out"
  ( cd "$d/real" && ln -s ../out .claude ); ( cd "$d/w/copy" && ln -s ../out .claude )
  _u "$1" "ADOPT_GUARD_REAL_ROOT='$d/real'; adopt_guard_write '$d/w/copy' .claude/x.json; echo \"rc=\$?\""
  case "$U_OUT" in *"rc=1"*) ;; *) CASE_DETAIL="not refused: $U_OUT"; return 1 ;; esac
  case "$U_OUT" in *"leads outside this project: .claude -> ../out, which resolves to $(phys "$d/out")."*) ;;
    *) CASE_DETAIL="the real project's answer is not the one printed: $U_OUT"; return 1 ;; esac
  # the copy alone escaping (an absolute link the relink did not re-point) is refused too, and says so
  rm "$d/w/copy/.claude"; ln -s "$d/out" "$d/w/copy/.claude"; rm "$d/real/.claude"
  _u "$1" "ADOPT_GUARD_REAL_ROOT='$d/real'; adopt_guard_write '$d/w/copy' .claude/x.json; echo \"rc=\$?\""
  case "$U_OUT" in *"rc=1"*) ;; *) CASE_DETAIL="the copy's escape was not refused: $U_OUT"; return 1 ;; esac
  case "$U_OUT" in *"leads outside the pre-write rehearsal's copy of this project"*) ;;
    *) CASE_DETAIL="the copy-only refusal does not say it is the copy's: $U_OUT"; return 1 ;; esac
}
case_U13() {   # the rehearsal re-points every link into the project, whatever its spelling, and nothing else
  # The real tree carries the links and is copied as the rehearsal copies it
  # (tar keeps a link's text). The root is given through a symlinked folder, so
  # it has three spellings: that one, the physical path, and a second alias.
  local d="" r="" rp="" c="" l=""; d="$(newtmp)"
  mkdir -p "$d/real/proj/gov" "$d/copy" "$d/out"; ln -s "$d/real" "$d/alias"; ln -s "$d/real" "$d/alias2"
  r="$d/alias/proj"; rp="$(phys "$r")"; c="$d/copy"
  [ "$r" != "$rp" ] || { CASE_DETAIL="fixture: the two spellings of the root are the same"; return 1; }
  printf 'x\n' > "$rp/gov/a.md"
  ln -s "$r/gov/a.md" "$rp/logical"; ln -s "$rp/gov/a.md" "$rp/physical"; ln -s "$d/alias2/proj/gov/a.md" "$rp/alias2"
  ln -s "../proj/gov/a.md" "$rp/updown"; ln -s "gov/a.md" "$rp/relative"; ln -s "$d/out/x" "$rp/outside"
  ln -s "$rp" "$rp/gov/root"; ln -s "$rp/gov/missing.md" "$rp/dangling"
  ( cd "$rp" && tar -cf - . ) | ( cd "$c" && tar -xf - ) || { CASE_DETAIL="fixture: copy"; return 1; }
  _u "$1" "_adopt_rehearsal_relink '$c' '$r'; echo \"rc=\$?\""
  case "$U_OUT" in *"rc=0"*) ;; *) CASE_DETAIL="relink failed: $U_OUT"; return 1 ;; esac
  for l in logical physical alias2 updown; do
    [ "$(readlink "$c/$l")" = "$c/gov/a.md" ] || { CASE_DETAIL="$l spelling: $(readlink "$c/$l")"; return 1; }
  done
  [ "$(readlink "$c/dangling")" = "$c/gov/missing.md" ] || { CASE_DETAIL="a dangling link into the project: $(readlink "$c/dangling")"; return 1; }
  [ "$(readlink "$c/gov/root")" = "$c" ] || { CASE_DETAIL="a link to the root itself: $(readlink "$c/gov/root")"; return 1; }
  [ "$(readlink "$c/relative")" = "gov/a.md" ] || { CASE_DETAIL="a relative link that stays inside was changed"; return 1; }
  [ "$(readlink "$c/outside")" = "$d/out/x" ] || { CASE_DETAIL="an outside link was changed"; return 1; }
}
case_U14() {   # a dangling link ABOVE the leaf cannot be resolved: unknown, so refused
  local d=""; d="$(newtmp)"; mkdir -p "$d/p/sub"; ln -s "$d/nowhere" "$d/p/sub/dang"; ( cd "$d/p" && ln -s sub/dang/f L )
  _u "$1" "adopt_link_escape '$d/p' L && printf 'ESC|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|L|" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U15() {   # a sibling folder whose name starts with the project's is outside it
  local d=""; d="$(newtmp)"; mkdir -p "$d/proj" "$d/proj-sibling"; printf 'x\n' > "$d/proj-sibling/t.md"; ln -s "$d/proj-sibling/t.md" "$d/proj/A.md"
  _u "$1" "adopt_link_escape '$d/proj' A.md && printf 'ESC|%s' \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|$(phys "$d/proj-sibling")/t.md" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U16() {   # the root reached through a symlinked folder: links inside, in any spelling, are inside
  local d=""; d="$(newtmp)"; mkdir -p "$d/real/proj/gov"; printf 'x\n' > "$d/real/proj/gov/a.md"
  ln -s "$d/real" "$d/alias"; ln -s "$d/real" "$d/alias2"
  ln -s "$d/real/proj/gov/a.md" "$d/real/proj/P.md"; ln -s "$d/alias2/proj/gov/a.md" "$d/real/proj/Q.md"
  _u "$1" "for f in P.md Q.md; do adopt_link_escape '$d/alias/proj' \"\$f\" && printf 'ESC:%s ' \"\$f\" || printf 'IN:%s ' \"\$f\"; done"
  [ "$U_OUT" = "IN:P.md IN:Q.md " ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
}
case_U17() {   # a root typed in the wrong case, on a case-insensitive volume: the re-point still finds the project
  local d="" c=""; d="$(newtmp)"; mkdir -p "$d/Proj/gov" "$d/copy"
  if [ ! -d "$d/PROJ" ]; then CASE_DETAIL="SKIP: this volume is case-sensitive"; return 0; fi
  printf 'x\n' > "$d/Proj/gov/a.md"; ln -s "$d/proj/gov/a.md" "$d/Proj/APPROVAL_LOG.md"
  c="$d/copy"; ( cd "$d/Proj" && tar -cf - . ) | ( cd "$c" && tar -xf - )
  _u "$1" "_adopt_rehearsal_relink '$c' '$d/PROJ'; ADOPT_GUARD_REAL_ROOT='$d/PROJ'; adopt_guard_write '$c' APPROVAL_LOG.md && echo OK"
  case "$U_OUT" in *OK*) ;; *) CASE_DETAIL="refused: $U_OUT"; return 1 ;; esac
  [ "$(readlink "$c/APPROVAL_LOG.md")" = "$c/gov/a.md" ] || { CASE_DETAIL="not re-pointed: $(readlink "$c/APPROVAL_LOG.md")"; return 1; }
}

# ── A: real adoptions ───────────────────────────────────────────────────────
# _leaf_out FW REL — REL in a fresh adoptee is a symlink to a file outside it.
_leaf_out() {
  local fw="$1" rel="$2" d="" p="" o="" ob="" tb="" hb=""
  d="$(newtmp)"; p="$d/proj"; o="$d/outside"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$o" "$(dirname "$p/$rel")"; printf 'OUTSIDE-ORIGINAL\n' > "$o/target.md"; ln -s "$o/target.md" "$p/$rel"
  ob="$(_listing "$o")"; tb="$(_tree "$p")"; hb="$(_head "$p")"
  _adopt "$fw" "$p"
  _refused_clean "$p" "$ob" "$o" "$tb" "$hb" || return 1
  _names_link "$rel" "$(phys "$o")/target.md"
}
case_A1() { _leaf_out "$1" APPROVAL_LOG.md; }
case_A2() { _leaf_out "$1" scripts/check-phase-gate.sh; }
# _folder_out FW REL [rel] — REL in a fresh adoptee is a symlink to a folder outside
# it (absolute, or relative when the third argument is `rel`).
_folder_out() {
  local fw="$1" rel="$2" kind="${3:-abs}" d="" p="" o="" ob="" tb="" hb=""
  d="$(newtmp)"; p="$d/proj"; o="$d/outside"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$o" "$(dirname "$p/$rel")"; printf 'THEIRS\n' > "$o/notes.md"
  if [ "$kind" = rel ]; then ( cd "$(dirname "$p/$rel")" && ln -s "$(printf '%s' "$rel" | sed 's|[^/]*/|../|g; s|[^/]*$|..|')/outside" "$(basename "$rel")" )
  else ln -s "$o" "$p/$rel"; fi
  ob="$(_listing "$o")"; tb="$(_tree "$p")"; hb="$(_head "$p")"
  _adopt "$fw" "$p"
  _refused_clean "$p" "$ob" "$o" "$tb" "$hb" || return 1
  FOLDER_OUT="$(phys "$o")"
}
FOLDER_OUT=""
case_A3() { _folder_out "$1" .semgrep && _names_link .semgrep/soif-dom-sinks.yml "$FOLDER_OUT"; }
case_A4() {
  _folder_out "$1" .claude || return 1
  _names_link .claude/test-debt.json "$FOLDER_OUT" || return 1
  grep -qF 'nothing was written to this project' "$ADOPT_ERR" \
    || { CASE_DETAIL="the run does not say nothing was written: $(cat "$ADOPT_ERR")"; return 1; }
}
case_A5() { _folder_out "$1" .claude rel && _names_link .claude/test-debt.json "$FOLDER_OUT"; }
# _inside FW KIND — APPROVAL_LOG.md is a link to governance/approval.md (relative or absolute).
_inside() {
  local fw="$1" kind="$2" d="" p=""
  d="$(newtmp)"; p="$d/proj"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$p/governance"; printf 'INSIDE-ORIGINAL\n' > "$p/governance/approval.md"
  if [ "$kind" = rel ]; then ( cd "$p" && ln -s governance/approval.md APPROVAL_LOG.md ); else ln -s "$p/governance/approval.md" "$p/APPROVAL_LOG.md"; fi
  _adopt "$fw" "$p"
  [ "$ADOPT_RC" -eq 0 ] || { CASE_DETAIL="adoption did not complete (rc $ADOPT_RC): $(grep -m1 -E 'REFUSED|BLOCKED' "$ADOPT_ERR")"; return 1; }
  [ -L "$p/APPROVAL_LOG.md" ] || { CASE_DETAIL="the link was replaced"; return 1; }
  grep -q 'INSIDE-ORIGINAL' "$p/governance/approval.md" && { CASE_DETAIL="the link's target inside the project was not written through"; return 1; }
  [ -s "$p/governance/approval.md" ] || { CASE_DETAIL="the target is empty"; return 1; }
  return 0
}
case_A6() { _inside "$1" rel; }
case_A7() { _inside "$1" abs; }
case_A8() {   # .claude -> <project>/config/claude, absolute: refused as before, nothing written into it
  local fw="$1" d="" p="" tb="" hb=""
  d="$(newtmp)"; p="$d/proj"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$p/config/claude"; ln -s "$p/config/claude" "$p/.claude"
  tb="$(_tree "$p")"; hb="$(_head "$p")"
  _adopt "$fw" "$p"
  [ "$ADOPT_RC" -ne 0 ] || { CASE_DETAIL="adoption completed"; return 1; }
  [ "$(find "$p/config/claude" -mindepth 1 | wc -l | tr -d ' ')" = 0 ] \
    || { CASE_DETAIL="the rehearsal wrote $(find "$p/config/claude" -type f | wc -l | tr -d ' ') file(s) into the project's config/claude"; return 1; }
  [ "$(_tree "$p")" = "$tb" ] && [ "$(_head "$p")" = "$hb" ] || { CASE_DETAIL="the project changed"; return 1; }
}
case_A9() {   # APPROVAL_LOG.md -> governance/hop -> an outside file
  local fw="$1" d="" p="" o="" ob="" tb="" hb=""
  d="$(newtmp)"; p="$d/proj"; o="$d/outside"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$o" "$p/governance"; printf 'OUTSIDE-ORIGINAL\n' > "$o/target.md"
  ln -s "$o/target.md" "$p/governance/hop"; ( cd "$p" && ln -s governance/hop APPROVAL_LOG.md )
  ob="$(_listing "$o")"; tb="$(_tree "$p")"; hb="$(_head "$p")"
  _adopt "$fw" "$p"
  _refused_clean "$p" "$ob" "$o" "$tb" "$hb" || return 1
  _names_link APPROVAL_LOG.md "$(phys "$o")/target.md"
}
case_A10() {   # spaces: the project, the outside folder and the link's target
  local fw="$1" d="" p="" o="" ob="" tb="" hb=""
  d="$(newtmp)"; p="$d/my proj"; o="$d/out side/claude dir"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$o"; printf 'THEIRS\n' > "$o/my notes.md"; ln -s "$o" "$p/.claude"
  ob="$(_listing "$o")"; tb="$(_tree "$p")"; hb="$(_head "$p")"
  _adopt "$fw" "$p"
  _refused_clean "$p" "$ob" "$o" "$tb" "$hb" || return 1
  _names_link .claude/test-debt.json "$(phys "$o")"
}
SPACED=""
case_A11() {   # a normal adoption, in a path with a space, completes; it also owns a CLAUDE.md, archived
  local fw="$1" d=""
  d="$(newtmp)"; SPACED="$d/their proj"
  _adoptee "$SPACED" || { CASE_DETAIL="fixture"; return 1; }
  printf '# THEIR-CLAUDE\n' > "$SPACED/CLAUDE.md"
  ( cd "$SPACED" && git add CLAUDE.md && git commit -q -m "docs: theirs" ) >/dev/null 2>&1
  _adopt "$fw" "$SPACED"
  [ "$ADOPT_RC" -eq 0 ] || { CASE_DETAIL="adoption did not complete (rc $ADOPT_RC): $(grep -m1 -hE 'REFUSED|BLOCKED|would be written' "$ADOPT_ERR" "$ADOPT_OUT")"; return 1; }
  grep -q 'would be written through a symlink' "$ADOPT_ERR" "$ADOPT_OUT" && { CASE_DETAIL="a symlink refusal on a tree with no symlink"; return 1; }
  [ "$(git -C "$SPACED" log --oneline | wc -l | tr -d ' ')" -ge 3 ] || { CASE_DETAIL="no adoption commit"; return 1; }
}
case_A12() {   # --re-add onto a link to an outside file, after A11's adoption
  local fw="$1" d="" o="" ob=""
  [ -n "$SPACED" ] && [ -d "$SPACED/.claude/adoption-archive" ] || { CASE_DETAIL="A11 left no adopted project"; return 1; }
  d="$(newtmp)"; o="$d/outside"; mkdir -p "$o"; printf 'OUTSIDE-ORIGINAL\n' > "$o/claude.md"
  rm -f "$SPACED/CLAUDE.md"; ln -s "$o/claude.md" "$SPACED/CLAUDE.md"
  ob="$(_listing "$o")"
  ( cd "$SPACED" && printf '1\n' | bash "$fw/scripts/adopt-project.sh" --re-add CLAUDE.md ) > "$d/out" 2> "$d/err"; ADOPT_RC=$?
  ADOPT_OUT="$d/out"; ADOPT_ERR="$d/err"
  [ "$ADOPT_RC" -ne 0 ] || { CASE_DETAIL="the re-add completed"; return 1; }
  [ "$(_listing "$o")" = "$ob" ] || { CASE_DETAIL="the outside file was overwritten"; return 1; }
  _names_link CLAUDE.md "$(phys "$o")/claude.md"
}
# A Guardrails stub: what the real installer writes, in the shape
# tests/test-bl296-adopt-guardrails.sh's stub writes it.
GR_STUB="$WORK/gr-stub"
mkdir -p "$GR_STUB/scripts" && ( cd "$GR_STUB" && git init -q . ) >/dev/null 2>&1
cat > "$GR_STUB/scripts/detect-profile.sh" <<'DETECT'
#!/usr/bin/env bash
echo web-api
DETECT
cat > "$GR_STUB/scripts/init.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p .claude/framework/hooks .claude/framework/rules
printf '#!/bin/sh\n# STUB-GUARDRAILS-HOOK\n' > .claude/framework/hooks/stub-hook.sh
echo '{"frameworkVersion":"9.9.9-stub","profile":"web-api"}' > .claude/manifest.json
STUB
case_A13() {   # .claude/framework -> an outside folder, with the installer present
  local fw="$1" d="" p="" o="" ob="" tb="" hb=""
  d="$(newtmp)"; p="$d/proj"; o="$d/outside"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$o" "$p/.claude"; printf 'THEIRS\n' > "$o/notes.md"; ln -s "$o" "$p/.claude/framework"
  ob="$(_listing "$o")"; tb="$(_tree "$p")"; hb="$(_head "$p")"
  _adopt "$fw" "$p" "$GR_STUB"
  _refused_clean "$p" "$ob" "$o" "$tb" "$hb" || return 1
  _names_link .claude/framework/hooks "$(phys "$o")"
}
case_A14() {   # .claude/adoption-archive -> an empty outside folder, and a CLAUDE.md to archive
  local fw="$1" d="" p="" o="" ob="" tb="" hb=""
  d="$(newtmp)"; p="$d/proj"; o="$d/outside"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  printf '# THEIR-CLAUDE\n' > "$p/CLAUDE.md"; ( cd "$p" && git add CLAUDE.md && git commit -q -m "docs: theirs" ) >/dev/null 2>&1
  mkdir -p "$o" "$p/.claude"; ln -s "$o" "$p/.claude/adoption-archive"
  ob="$(_listing "$o")"; tb="$(_tree "$p")"; hb="$(_head "$p")"
  _adopt "$fw" "$p"
  _refused_clean "$p" "$ob" "$o" "$tb" "$hb" || return 1
  grep -qE '\.claude/adoption-archive/[^ ]+/MANIFEST\.json would be written through a symlink' "$ADOPT_ERR" "$ADOPT_OUT" \
    || { CASE_DETAIL="the refusal does not name the archive: $(grep -m1 -hE 'REFUSED|BLOCKED|would be written' "$ADOPT_ERR" "$ADOPT_OUT")"; return 1; }
  grep -qF -- "resolves to $(phys "$o")" "$ADOPT_ERR" "$ADOPT_OUT" || { CASE_DETAIL="the refusal does not say where it resolves"; return 1; }
}
case_A15() {   # the audit ledger linked outside: a caller that carries on without the row
  local fw="$1" d="" p="" o="" ob=""
  d="$(newtmp)"; p="$d/proj"; o="$d/outside"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  printf '# THEIR-CLAUDE\n' > "$p/CLAUDE.md"; ( cd "$p" && git add CLAUDE.md && git commit -q -m "docs: theirs" ) >/dev/null 2>&1
  mkdir -p "$o" "$p/.claude"; printf '[]\n' > "$o/ledger.json"; ln -s "$o/ledger.json" "$p/.claude/bypass-audit.json"
  ob="$(_listing "$o")"
  _adopt "$fw" "$p"
  [ "$ADOPT_RC" -eq 0 ] || { CASE_DETAIL="adoption did not complete (rc $ADOPT_RC): $(grep -m1 -hE 'REFUSED|BLOCKED|would be written' "$ADOPT_ERR" "$ADOPT_OUT")"; return 1; }
  [ "$(_listing "$o")" = "$ob" ] || { CASE_DETAIL="the outside ledger changed"; return 1; }
  [ -L "$p/.claude/bypass-audit.json" ] || { CASE_DETAIL="the link was replaced by a file"; return 1; }
  grep -qF 'ITS AUDIT ROW could not be recorded' "$ADOPT_OUT" || { CASE_DETAIL="the run does not say the row could not be recorded"; return 1; }
  grep -qF '.claude/bypass-audit.json would be written through a symlink' "$ADOPT_ERR" || { CASE_DETAIL="the cause is not printed"; return 1; }
  grep -qE 'BLOCKED|REFUSED|Nothing was committed' "$ADOPT_ERR" && { CASE_DETAIL="a run that commits printed: $(grep -m1 -E 'BLOCKED|REFUSED|Nothing was committed' "$ADOPT_ERR")"; return 1; }
  grep -q 'run this again' "$ADOPT_ERR" && { CASE_DETAIL="the cause says 'run this again', which a completed run refuses: $(grep -m1 'run this again' "$ADOPT_ERR" | cut -c1-120)"; return 1; }
  grep -qF 'THE ARCHIVE HAPPENED. THE AUDIT ROW FOR IT could not be recorded' "$ADOPT_OUT" || { CASE_DETAIL="no archive note (the fixture's CLAUDE.md should be archived)"; return 1; }
  grep -q 'not valid JSON' "$ADOPT_OUT" && { CASE_DETAIL="a note blames the ledger's JSON for a symlink"; return 1; }
  grep -qF 'is a symlink that leads outside the project' "$ADOPT_OUT" || { CASE_DETAIL="the notes do not name the symlink as the cause"; return 1; }
  return 0
}
case_A16() {   # .git/hooks/commit-msg linked to a hook outside, shared with other repositories
  local fw="$1" d="" p="" o="" ob="" m0=""
  d="$(newtmp)"; p="$d/proj"; o="$d/shared-hooks"
  _adoptee "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$o" "$p/.git/hooks"; printf '#!/bin/sh\n# SHARED-COMMIT-MSG\nexit 0\n' > "$o/commit-msg"; chmod 644 "$o/commit-msg"
  ln -s "$o/commit-msg" "$p/.git/hooks/commit-msg"
  ob="$(_listing "$o")"; m0="$(ls -l "$o/commit-msg" | cut -c1-10)"
  _adopt "$fw" "$p"
  [ "$(_listing "$o")" = "$ob" ] || { CASE_DETAIL="the shared hook was written (now $(wc -c < "$o/commit-msg" | tr -d ' ') bytes)"; return 1; }
  [ "$(ls -l "$o/commit-msg" | cut -c1-10)" = "$m0" ] || { CASE_DETAIL="the shared hook's mode changed: $m0 -> $(ls -l "$o/commit-msg" | cut -c1-10)"; return 1; }
  [ -L "$p/.git/hooks/commit-msg" ] || { CASE_DETAIL="the link was replaced"; return 1; }
  grep -q 'Commit-msg gate installed' "$ADOPT_OUT" && { CASE_DETAIL="the run says the gate was installed"; return 1; }
  grep -qF 'NOT INSTALLED — the commit-msg gate' "$ADOPT_OUT" || { CASE_DETAIL="the run does not say NOT INSTALLED: $(grep -m1 -i 'commit-msg' "$ADOPT_OUT")"; return 1; }
  [ "$ADOPT_RC" -ne 0 ] || { CASE_DETAIL="rc 0 with the gate not installed"; return 1; }
}
case_A17() {   # .git linked to a repository outside, cloned --shared: refused before any write
  local fw="$1" d="" p="" up="" g="" alt="" tb=""
  d="$(newtmp)"; up="$d/upstream"; p="$d/proj"; g="$d/outside/proj.git"
  _adoptee "$up" || { CASE_DETAIL="fixture"; return 1; }
  git clone -q --shared "$up" "$p" >/dev/null 2>&1 || { CASE_DETAIL="fixture: clone"; return 1; }
  ( cd "$p" && git config user.email bl310@test.invalid && git config user.name "BL310 Test" ) >/dev/null 2>&1
  mkdir -p "$d/outside" && mv "$p/.git" "$g" && ln -s "$g" "$p/.git" || { CASE_DETAIL="fixture: link"; return 1; }
  alt="$(cat "$g/objects/info/alternates")"; tb="$(_tree "$p")"
  _adopt "$fw" "$p"
  [ "$ADOPT_RC" -ne 0 ] || { CASE_DETAIL="adoption completed"; return 1; }
  [ "$(cat "$g/objects/info/alternates")" = "$alt" ] || { CASE_DETAIL="the outside repository's alternates were rewritten: $(cat "$g/objects/info/alternates")"; return 1; }
  git -C "$p" rev-parse --verify -q HEAD >/dev/null || { CASE_DETAIL="the repository no longer resolves HEAD"; return 1; }
  [ "$(_tree "$p")" = "$tb" ] || { CASE_DETAIL="the project tree changed"; return 1; }
  grep -qF ".git is a SYMLINK" "$ADOPT_ERR" || { CASE_DETAIL="not refused for the link: $(grep -m1 -E 'REFUSED|BLOCKED' "$ADOPT_ERR")"; return 1; }
}
case_A18() {   # the project reached through one alias, APPROVAL_LOG.md linked through another
  local fw="$1" d="" p=""
  d="$(newtmp)"; _adoptee "$d/real/proj" || { CASE_DETAIL="fixture"; return 1; }
  ln -s "$d/real" "$d/alias"; ln -s "$d/real" "$d/alias2"; p="$d/alias/proj"
  mkdir -p "$p/gov"; printf 'INSIDE-ORIGINAL\n' > "$p/gov/approval.md"; ln -s "$d/alias2/proj/gov/approval.md" "$p/APPROVAL_LOG.md"
  _adopt "$fw" "$p"
  [ "$ADOPT_RC" -eq 0 ] || { CASE_DETAIL="adoption did not complete (rc $ADOPT_RC): $(grep -m1 -hE 'would be written|REFUSED|BLOCKED' "$ADOPT_OUT" "$ADOPT_ERR" | cut -c1-160)"; return 1; }
  grep -q 'INSIDE-ORIGINAL' "$p/gov/approval.md" && { CASE_DETAIL="the link's target was not written through"; return 1; }
  [ -L "$p/APPROVAL_LOG.md" ] || { CASE_DETAIL="the link was replaced"; return 1; }
}

# ── N: every write site carries the guard ───────────────────────────────────
# A write site is a call to `adopt_touched_disk` (BL-225's marker, which
# tests/test-bl225-staging-preflight.sh's T9 requires before every write shape
# it finds) or to a core writer adoption calls with a path in the project. Each
# must have `adopt_guard_write` in its own function within 30 lines before it.
# THE WINDOW, not "anywhere above": a function with two writes and one guard
# would satisfy "anywhere above" for both. 30 lines is the widest gap between a
# guard and the write it covers today (the re-add's `cp`, 24 lines below it).
# A NET, not a proof — it reads text, not reachability.
#
# EXEMPT, by function, each with its reason:
#   adopt_touched_disk / adopt_touched_disk_unbounded — the marker's definition
#   adopt_install_hooks — git's hooks, under a rule STRICTER than the guard's:
#       step 0 refuses a linked hooks directory (`# BL-242-PLACEMENT-HOOKS-SHAPE`)
#       and a linked `.git` (`# BL-310-PLACEMENT-GITLINK`), and a hook FILE
#       that is a symlink is not written at all, inside or out
#       (`# BL-310-HOOK-COMMITMSG-LINK`, `# BL-242-PRECOMMIT-GUARD`); A16 pins it
#   _td_write_body — its marked arm runs only standalone; inside adoption the
#       arm above it takes adopt_write_file, which carries the guard
#   adopt_resolve_tools — the install recipe the operator approved, run from
#       $ADOPT_WORK; unbounded by construction (`# BL-225-TOUCHED-UNBOUNDED`),
#       and before the rehearsal
#   adopt_mcp_apply — `claude mcp add` / docker change the operator's Claude
#       Code configuration, outside the project by design (`# BL-318-G6-OUTSIDE`)
N1_EXEMPT=" adopt_touched_disk adopt_touched_disk_unbounded adopt_install_hooks _td_write_body adopt_resolve_tools adopt_mcp_apply "
_write_sites() {   # FW — file:line:function for every write site
  local f=""
  for f in "$1"/scripts/lib/adopt/*.sh; do
    awk -v F="${f##*/}" '
      /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn) }
      /^[[:space:]]*#/ { next }
      /(^|[^A-Za-z0-9_])(adopt_touched_disk|bypass_audit_append|soif_adoption_stamp|soif_adoption_assess|soif_register_hook_roster)([^A-Za-z0-9_(]|$)/ { print F ":" NR ":" fn }
    ' "$f"
  done
}
N1_SITES=0
case_N1() {
  local fw="$1" f="" l="" fn="" bad="" start=""
  N1_SITES=0
  while IFS=: read -r f l fn; do
    [ -n "$l" ] || continue
    N1_SITES=$((N1_SITES + 1))
    case "$N1_EXEMPT" in *" $fn "*) continue ;; esac
    start=$(awk -v L="$l" 'NR<L && /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {n=NR} END{print n+0}' "$fw/scripts/lib/adopt/$f")
    [ "$start" -lt $((l - 30)) ] && start=$((l - 30))
    awk -v A="$start" -v B="$l" 'NR>A && NR<B && /^[^#]*adopt_guard_write /' "$fw/scripts/lib/adopt/$f" | grep -q . \
      || bad="$bad $f:$l($fn)"
  done <<SITES
$(_write_sites "$fw")
SITES
  [ "$N1_SITES" -ge 20 ] || { CASE_DETAIL="the net found only $N1_SITES write site(s) — the recipe stopped seeing them"; return 1; }
  [ -z "$bad" ] || { CASE_DETAIL="no guard within 30 lines before:$bad"; return 1; }
}

echo "== BL-310 row 4 — adoption writes nothing outside the project through a symlink =="
echo "=== U — the predicate and the guard ==="
check "U1: a file link to an outside file is an escape, named with where it resolves" case_U1
check "U2: a folder link to an outside folder is an escape for every path below it" case_U2
check "U3: a relative file link that resolves inside is not an escape" case_U3
check "U4: an absolute folder link that resolves inside is not an escape" case_U4
check "U5: a chain, inside link to outside file, is an escape" case_U5
check "U6: a dangling link into an outside folder is an escape (a write would create the file there)" case_U6
check "U7: a link loop cannot be resolved and counts as outside" case_U7
check "U8: no link and a path not there yet is not an escape" case_U8
check "U9: \`..\` below a folder that does not exist yet counts as outside" case_U9
check "U10: spaces in the project, the link and the target" case_U10
check "U11: the writer refuses, names the link and where it resolves, writes nothing; a plain path is written" case_U11
check "U12: in the rehearsal the real project's answer is printed; a copy-only escape is refused and says so" case_U12
check "U13: the rehearsal re-points every link into the project, whatever its spelling, and nothing else" case_U13
check "U14: a dangling link above the leaf cannot be resolved and counts as outside" case_U14
check "U15: a sibling folder whose name starts with the project's is outside it" case_U15
check "U16: the root reached through a symlinked folder: links inside, in any spelling, are inside" case_U16
check "U17: a root typed in the wrong case (case-insensitive volume): the re-point still finds the project" case_U17
echo "=== A — real adoptions ==="
check "A1: APPROVAL_LOG.md linked to an outside file: refused, the file byte-identical, project and HEAD unchanged" case_A1
check "A2: scripts/check-phase-gate.sh linked to an outside file: refused, unchanged" case_A2
check "A3: .semgrep linked to an outside folder: refused, the folder unchanged" case_A3
check "A4: BL-351 — .claude linked to an outside folder: refused before any write, rehearsal included; checksum listing identical; 'nothing was written' is said and true" case_A4
check "A5: the same with a relative link: the refusal names where it resolves in the real project" case_A5
check "A6: a relative file link that resolves inside: adoption completes and writes through it, as before" case_A6
check "A7: an absolute file link into the project: adoption completes and writes through it, as before" case_A7
check "A8: .claude an absolute link to a folder inside: refused as before, and nothing written into that folder" case_A8
check "A9: a chain, inside link to an outside file: refused, the file unchanged" case_A9
check "A10: a path with a space: refused, nothing outside changed" case_A10
check "A11: a normal adoption in a path with a space completes (no false refusal)" case_A11
check "A12: --re-add onto a link to an outside file: refused, the file unchanged" case_A12
check "A13: .claude/framework linked outside, the Guardrails installer present: refused before it runs" case_A13
check "A14: .claude/adoption-archive linked outside: refused, nothing archived there" case_A14
check "A15: the audit ledger linked outside: not written through, the run completes and says the row was not recorded, no false 'Nothing was committed' or 'run this again', the archive note names the symlink" case_A15
check "A16: .git/hooks/commit-msg linked to a shared hook outside: not written, mode kept, NOT INSTALLED" case_A16
check "A17: .git linked to a repository outside (clone --shared): refused at step 0, its alternates untouched" case_A17
check "A18: reached through one alias, a file linked through another: completes, written through" case_A18
echo "=== N — every write site carries the guard ==="
check "N1: each write site in scripts/lib/adopt/ has adopt_guard_write within 30 lines before it in its function" case_N1
echo "         (N1 read $N1_SITES write site(s))"

# ── M: mutants ──────────────────────────────────────────────────────────────
mk_mirror() { cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$2/"; }
ends_in() {   # FILE MARKER — how many lines of FILE end in MARKER
  MARK="$2" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$1"
}
mutate() {   # FILE MARKER REPLACEMENT — exactly one line ends in MARKER; it now reads REPLACEMENT; still parses
  local f="$1" mark="$2" repl="$3"
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  [ "$(ends_in "$f" "$mark")" = 1 ] || { echo "marker '$mark' ends $(ends_in "$f" "$mark") line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(ends_in "$f" "$mark")" = 0 ] || { echo "a line still ends in the marker after the edit"; return 1; }
  [ "$(grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
mutant() {   # ID FILE MARKER REPLACEMENT WHAT KILLER...
  local id="$1" file="$2" mark="$3" repl="$4" what="$5" m="" why="" k="" rc=0 killed=""
  shift 5
  m="$(newtmp)/mirror"; mkdir -p "$m"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$file" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  for k in "$@"; do
    CASE_DETAIL=""; rc=0
    "$k" "$m" || rc=$?
    if [ "$rc" -eq 0 ]; then fail_ "$id" "$what — SURVIVED: ${k#case_} still passes against the mutant"; return; fi
    killed="$killed ${k#case_} ($(printf '%s' "${CASE_DETAIL:-failed}" | tr '\n' ' ' | cut -c1-160));"
  done
  pass "$id (MUTATION) — $what: killed by${killed%;}"
}

echo "=== M — mutants ==="
CORE=scripts/lib/adopt/adopt-core.sh
ST=scripts/lib/adopt/adopt-state.sh
# the predicate and the guard
mutant MP1 "$CORE" '# BL-310-ESCAPE-LINK' '    continue' "no component is ever examined as a link" case_U1
mutant MP2 "$CORE" '# BL-310-ESCAPE-INSIDE' '    :' "a link that resolves inside is refused" case_U3
mutant MP4 "$CORE" '# BL-310-ESCAPE-RES' '    ADOPT_LINK_RES=""' "no link is ever resolved" case_U3
mutant MP5 "$CORE" '# BL-310-ESCAPE-TO' '    ADOPT_LINK_TO=""' "the refusal stops saying what the link says" case_U11
mutant MP6 "$CORE" '# BL-310-RESOLVE-HOPS' '    n=$((n + 1)); [ "$n" -le 0 ] || return 1' "the hop limit is zero: no file link resolves" case_U3
mutant MP7 "$CORE" '# BL-310-RESOLVE-FOLLOW' '  while false; do' "a file link is not followed to its target" case_U5
mutant MP8 "$CORE" '# BL-310-RESOLVE-DANGLING' '    :' "a dangling link above the leaf is climbed past" case_U14
mutant MP9 "$CORE" '# BL-310-RESOLVE-DOTS' '  :' "\`..\` below a missing folder is read lexically" case_U9
mutant MP10 "$CORE" '# BL-310-RESOLVE-PHYS' '  :' "the deepest folder is not made physical, so a spelling through an inside alias reads as inside" case_U6
mutant MP11 "$CORE" '# BL-310-GUARD-REAL' '  if false; then' "the rehearsal does not ask the real project" case_U12 case_A5
mutant MP12 "$CORE" '# BL-310-GUARD-REFUSE' '  return 0' "the guard prints its refusal and lets the write happen" case_U11
mutant MP13 "$CORE" '# BL-310-GUARD-SCOPE' '    :' "a copy-only escape is reported as the project's" case_U12
mutant MP18 "$CORE" '# BL-310-GUARD-CAUSE' '  :' "the audit row's refusal says the run stopped, in a run that then commits" case_A15
mutant MP14 "$ST" '# BL-310-REHEARSAL-REAL-ROOT' '  :' "the rehearsal does not tell the guard where the real project is" case_A5
mutant MP15 "$ST" '# BL-310-REHEARSAL-RELINK' '  :' "the rehearsal does not re-point absolute links into the project" case_A7
mutant MP16 "$ST" '# BL-310-RELINK-FIND' '  ( cd "$copy" && find . -type l -lname '"'"'/*'"'"' -print ) | while IFS= read -r l; do' "a relative link that climbs out and back in is not re-pointed" case_U13
mutant MP17 "$ST" '# BL-310-RELINK-UNDER' '    continue' "no link into the project is re-pointed" case_U13 case_A7
mutant MP19 "$CORE" '# BL-310-UNDER-EF' '    if [ "$p" = "$root" ]; then printf '"'"'%s'"'"' "$rest"; return 0; fi' "the project is matched by spelling, not identity (review R-4b: pwd for pwd -P)" case_U16 case_A18
mutant MP20 "$CORE" '# BL-310-UNDER-EF' '    case "$p" in "$root"*) printf '"'"'%s'"'"' "$rest"; return 0 ;; esac' "a sibling whose name starts with the project's counts as inside (review R-4a)" case_U15
mutant MP21 "$CORE" '# BL-310-UNDER-ROOT' '    case "$p" in /|"") return 0 ;; esac' "every path counts as inside the project" case_U1
mutant MP22 "$CORE" '# BL-310-GUARD-CAUSE-ADVICE' '  :' "the audit row's cause tells a completed run to run again" case_A15
mutant MP23 scripts/lib/adopt/adopt-archive.sh '# BL-310-AUDIT-WHY' '  if false; then' "the notes blame the ledger's JSON when a symlink refused the row" case_A15
mutant MP24 "$ST" '# BL-310-HOOK-COMMITMSG-LINK' '  if false; then' "the commit-msg gate is written through a linked hook" case_A16
mutant MP25 "$ST" '# BL-310-PLACEMENT-GITLINK' '  if false; then' "a linked .git reaches the rehearsal, which writes into the repository it points at" case_A17
# the call sites: N1 kills each; a real adoption kills the ones a layout can reach first
mutant MC1 "$CORE" '# BL-310-GUARD-WRITE-FILE' '  :' "adopt_write_file writes through the link" case_N1 case_A4
mutant MC2 "$CORE" '# BL-310-GUARD-JQ-EDIT' '  :' "adopt_jq_edit writes through the link" case_N1
mutant MC3 "$ST" '# BL-310-GUARD-INSTALL' '    :' "the framework install copies through the link" case_N1 case_A2
mutant MC4 "$ST" '# BL-310-GUARD-SEMGREP' '  :' "the semgrep ruleset is copied through the link" case_N1 case_A3
mutant MC5 "$ST" '# BL-310-GUARD-APPROVAL-LOG' '  :' "APPROVAL_LOG.md is written through the link" case_N1 case_A1
mutant MC6 "$ST" '# BL-310-GUARD-STAMP' '  :' "the stamp edits the manifest through the link" case_N1
mutant MC7 "$ST" '# BL-310-GUARD-WRITE-SET' '  :' "the write set is written through the link" case_N1
mutant MC8 scripts/lib/adopt/adopt-archive.sh '# BL-310-GUARD-ARCHIVE' '  :' "the archive is written through the link" case_N1 case_A14
mutant MC9 scripts/lib/adopt/adopt-archive.sh '# BL-310-GUARD-AUDIT' '  :' "the audit row replaces the link to the outside ledger" case_N1 case_A15
mutant MC10 scripts/lib/adopt/adopt-archive.sh '# BL-310-GUARD-READD' '  :' "a re-add copies through the link" case_N1 case_A12
mutant MC11 scripts/lib/adopt/adopt-docs.sh '# BL-310-GUARD-DOC-PUT' '  :' "a framework document is written through the link" case_N1
mutant MC12 scripts/lib/adopt/adopt-session.sh '# BL-310-GUARD-ROSTER' '    :' "the hook roster is written through the link" case_N1
mutant MC13 scripts/lib/adopt/adopt-session.sh '# BL-310-GUARD-LOCAL-SETTINGS' '      :' "settings.local.json is written through the link" case_N1
mutant MC14 scripts/lib/adopt/adopt-record.sh '# BL-310-GUARD-RECORD' '  :' "the Adoption Record is appended through the link" case_N1
mutant MC15 scripts/lib/adopt/adopt-guardrails.sh '# BL-310-GUARD-GUARDRAILS' '    :' "the Guardrails installer runs through the link" case_N1 case_A13
mutant MC16 scripts/lib/adopt/adopt-act4.sh '# BL-310-GUARD-ASSESS' '  :' "the assessment is merged into a linked manifest" case_N1

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

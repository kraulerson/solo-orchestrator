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
# rehearsal wrote 13 files there and the refusal said the same.
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
#   U1-U14  the predicate and the guard, called directly: a file link out, a
#           folder link out, links that resolve inside, a chain, a dangling
#           link, a loop, `..` below a missing folder, spaces, the writer
#           refusing and writing nothing, the rehearsal asking the real project,
#           the rehearsal's re-pointing of absolute links into the project, and
#           a dangling link above the leaf
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
#           "Nothing was committed" printed into a run that commits
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
  if "$2" "$REPO_ROOT"; then pass "$1"; else fail_ "$1" "$(printf '%s' "${CASE_DETAIL:-failed}" | tr '\n' ' ')"; fi
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
  case "$U_OUT" in *"rc=1"*"") ;; *) CASE_DETAIL="the copy's escape was not refused: $U_OUT"; return 1 ;; esac
  case "$U_OUT" in *"leads outside the pre-write rehearsal's copy of this project"*) ;;
    *) CASE_DETAIL="the copy-only refusal does not say it is the copy's: $U_OUT"; return 1 ;; esac
}
case_U13() {   # the rehearsal re-points absolute links into the project, both spellings, and nothing else
  # The root is given through a symlinked folder, so its two spellings differ.
  local d="" r="" rp="" c=""; d="$(newtmp)"; mkdir -p "$d/real/proj/gov" "$d/copy/gov" "$d/out"; ln -s "$d/real" "$d/alias"
  r="$d/alias/proj"; rp="$(phys "$r")"; c="$d/copy"
  [ "$r" != "$rp" ] || { CASE_DETAIL="fixture: the two spellings of the root are the same"; return 1; }
  ln -s "$r/gov/a.md" "$c/logical"; ln -s "$rp/gov/a.md" "$c/physical"; ln -s "gov/a.md" "$c/relative"
  ln -s "$d/out/x" "$c/outside"; ln -s "$r" "$c/gov/root"
  _u "$1" "_adopt_rehearsal_relink '$c' '$r'; echo \"rc=\$?\""
  case "$U_OUT" in *"rc=0"*) ;; *) CASE_DETAIL="relink failed: $U_OUT"; return 1 ;; esac
  [ "$(readlink "$c/logical")" = "$c/gov/a.md" ] || { CASE_DETAIL="logical spelling: $(readlink "$c/logical")"; return 1; }
  [ "$(readlink "$c/physical")" = "$c/gov/a.md" ] || { CASE_DETAIL="physical spelling: $(readlink "$c/physical")"; return 1; }
  [ "$(readlink "$c/gov/root")" = "$c" ] || { CASE_DETAIL="a link to the root itself: $(readlink "$c/gov/root")"; return 1; }
  [ "$(readlink "$c/relative")" = "gov/a.md" ] || { CASE_DETAIL="a relative link was changed"; return 1; }
  [ "$(readlink "$c/outside")" = "$d/out/x" ] || { CASE_DETAIL="an outside link was changed"; return 1; }
}
case_U14() {   # a dangling link ABOVE the leaf cannot be resolved: unknown, so refused
  local d=""; d="$(newtmp)"; mkdir -p "$d/p/sub"; ln -s "$d/nowhere" "$d/p/sub/dang"; ( cd "$d/p" && ln -s sub/dang/f L )
  _u "$1" "adopt_link_escape '$d/p' L && printf 'ESC|%s|%s' \"\$ADOPT_LINK_AT\" \"\$ADOPT_LINK_RES\""
  [ "$U_OUT" = "ESC|L|" ] || { CASE_DETAIL="got '$U_OUT'"; return 1; }
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
  mkdir -p "$o" "$p/.claude"; printf '[]\n' > "$o/ledger.json"; ln -s "$o/ledger.json" "$p/.claude/bypass-audit.json"
  ob="$(_listing "$o")"
  _adopt "$fw" "$p"
  [ "$ADOPT_RC" -eq 0 ] || { CASE_DETAIL="adoption did not complete (rc $ADOPT_RC): $(grep -m1 -hE 'REFUSED|BLOCKED|would be written' "$ADOPT_ERR" "$ADOPT_OUT")"; return 1; }
  [ "$(_listing "$o")" = "$ob" ] || { CASE_DETAIL="the outside ledger changed"; return 1; }
  [ -L "$p/.claude/bypass-audit.json" ] || { CASE_DETAIL="the link was replaced by a file"; return 1; }
  grep -qF 'ITS AUDIT ROW could not be recorded' "$ADOPT_OUT" || { CASE_DETAIL="the run does not say the row could not be recorded"; return 1; }
  grep -qF '.claude/bypass-audit.json would be written through a symlink' "$ADOPT_ERR" || { CASE_DETAIL="the cause is not printed"; return 1; }
  grep -qE 'BLOCKED|REFUSED|Nothing was committed' "$ADOPT_ERR" && { CASE_DETAIL="a run that commits printed: $(grep -m1 -E 'BLOCKED|REFUSED|Nothing was committed' "$ADOPT_ERR")"; return 1; }
  return 0
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
#   adopt_install_hooks — git's hooks directory, resolved by git; step 0
#       (`# BL-242-PLACEMENT-HOOKS-SHAPE`) refuses a linked one, and it may sit
#       outside the working tree by design (a `.git` link)
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
      /(^|[^A-Za-z0-9_])(adopt_touched_disk|bypass_audit_append|soif_adoption_stamp|soif_register_hook_roster)([^A-Za-z0-9_(]|$)/ { print F ":" NR ":" fn }
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
check "U13: the rehearsal re-points absolute links into the project (both spellings) and nothing else" case_U13
check "U14: a dangling link above the leaf cannot be resolved and counts as outside" case_U14
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
check "A15: the audit ledger linked outside: not written through, the run completes and says the row was not recorded, no false 'Nothing was committed'" case_A15
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
mutant MP2 "$CORE" '# BL-310-ESCAPE-INSIDE' '    case "$ADOPT_LINK_RES" in "") ;; esac' "a link that resolves inside is refused" case_U3
mutant MP3 "$CORE" '# BL-310-ESCAPE-TOP' '      top=""' "the project root is never known, so every link reads as outside" case_U4
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
mutant MP16 "$ST" '# BL-310-RELINK-LOGICAL' '      "$root"|"$root"/*) continue ;;' "an absolute link spelled through the logical root is not re-pointed" case_U13
mutant MP17 "$ST" '# BL-310-RELINK-PHYSICAL' '      "$phys"|"$phys"/*) continue ;;' "an absolute link spelled through the physical root is not re-pointed" case_U13
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

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-bl255-sed-replacement-escape.sh
#
# `## BL-255:` — OPERATOR TEXT REACHES sed AS A REPLACEMENT, UNESCAPED.
#
# `soif_render_claude_md` and `soif_render_project_intake` substitute the
# project name and one-sentence description into templates with
# `sed "s|__X__|$var|g"` (and `s~…~$var~`). In a sed replacement `&` means
# "the whole match", `\` starts an escape, the delimiter ends the replacement
# and whatever follows is parsed as FLAGS — so a description of `R&D tools`
# rendered as `R__PROJECT_DESCRIPTION__D tools` (measured), and `a|w <path>|`
# wrote a file named `<path>|g` and emptied the description (measured; GNU
# sed's `e` flag makes the same shape run a command). `--description` is
# unvalidated; the interactive project name is `tr`-normalised only. Found by
# the 2026-09-07 codebase review (S6), reproduced on main c6da463.
#
# THE FIX IS ONE HELPER, `soif_sed_repl_esc <text> <delim>` in helpers-core.sh,
# applied at every site that splices operator text into a replacement. This
# suite pins the helper by table, each renderer end-to-end, and the two
# init.sh / verify-install.sh name sites by grep (they run only inside a
# scaffold, which this suite must not perform). Mutants on a MIRROR.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE="$REPO_ROOT/scripts/lib/helpers-core.sh"
RENDER="$REPO_ROOT/scripts/lib/render-project-docs.sh"
TMPL_CLAUDE="$REPO_ROOT/templates/generated/claude-md.tmpl"
TMPL_INTAKE="$REPO_ROOT/templates/project-intake.md"   # the path init.sh hands soif_render_project_intake

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); case "$n" in ''|*[!0-9]*) n=0 ;; esac; printf '%s\n' "$n"; }

for f in "$CORE" "$RENDER" "$TMPL_CLAUDE"; do
  [ -f "$f" ] || { echo "  [FAIL] setup — $f not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
done
[ -f "$TMPL_INTAKE" ] || TMPL_INTAKE="$(grep -o '"\$SCRIPT_DIR/templates/[^"]*intake[^"]*"' "$REPO_ROOT/init.sh" | head -1 | sed 's|"\$SCRIPT_DIR/|'"$REPO_ROOT"'/|; s|"$||')"

# A fresh subshell per call so a mutated mirror can be sourced in isolation.
# render_claude <lib_root> <desc> <name> <out>
render_claude() {
  ( . "$1/scripts/lib/helpers-core.sh" >/dev/null 2>&1
    . "$1/scripts/lib/render-project-docs.sh" >/dev/null 2>&1
    soif_render_claude_md "$TMPL_CLAUDE" "$4" "$3" "$2" web standard typescript 3 personal ) 2>/dev/null
}
# render_intake <lib_root> <desc> <name> <out>
render_intake() {
  ( . "$1/scripts/lib/helpers-core.sh" >/dev/null 2>&1
    . "$1/scripts/lib/render-project-docs.sh" >/dev/null 2>&1
    soif_render_project_intake "$TMPL_INTAKE" "$4" "$3" "$2" standard web personal 2026-09-08 ) 2>/dev/null
}
# esc <lib_root> <text> <delim>
esc() { ( . "$1/scripts/lib/helpers-core.sh" >/dev/null 2>&1; soif_sed_repl_esc "$2" "$3" ) 2>/dev/null; }

mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  return 0
}

echo "=== H — the helper, by table ==="

# Each row: input, delimiter, expected escaped form. `&` and `\` are escaped for
# any delimiter; the delimiter itself is escaped; a newline becomes a space.
if ! esc "$REPO_ROOT" "x" "|" >/dev/null 2>&1; then
  fail_ "H0" "soif_sed_repl_esc is not defined in helpers-core.sh"
else
  pass "H0 — soif_sed_repl_esc exists"
  check_esc() {   # check_esc <label> <in> <delim> <want>
    local got; got="$(esc "$REPO_ROOT" "$2" "$3")"
    [ "$got" = "$4" ] && pass "H — $1" || fail_ "H — $1" "got [$got] want [$4]"
  }
  check_esc "plain text is unchanged"               'Invoice tools'        '|' 'Invoice tools'
  check_esc "& is escaped"                          'R&D tools'            '|' 'R\&D tools'
  check_esc "backslash is escaped"                  'a\b'                  '|' 'a\\b'
  check_esc "the | delimiter is escaped"            'a|w /tmp/x|'          '|' 'a\|w /tmp/x\|'
  check_esc "the ~ delimiter is escaped"            'home ~ sweet'         '~' 'home \~ sweet'
  check_esc "a delimiter that is not the delimiter passes" 'a|b'           '~' 'a|b'
  check_esc "a newline becomes a space"             "$(printf 'one\ntwo')" '|' 'one two'
fi

echo "=== E — end to end through the renderers ==="

E1="$(newtmp)"
render_claude "$REPO_ROOT" "R&D tools" "acme" "$E1/CLAUDE.md"
if grep -q "R&D tools" "$E1/CLAUDE.md" 2>/dev/null; then
  pass "E1 — a description containing & renders verbatim in CLAUDE.md"
else
  fail_ "E1" "rendered as: $(grep -m1 'Description' "$E1/CLAUDE.md" 2>/dev/null | cut -c1-100)"
fi

E2="$(newtmp)"
render_claude "$REPO_ROOT" "a|w $E2/pwned|" "acme" "$E2/CLAUDE.md"
if ls "$E2"/pwned* >/dev/null 2>&1; then
  fail_ "E2" "a description carrying a sed w-flag wrote a file: $(ls "$E2"/pwned* | head -1)"
else
  pass "E2 — a description carrying the delimiter and a sed flag writes no file"
fi
grep -q "a|w $E2/pwned|" "$E2/CLAUDE.md" 2>/dev/null \
  && pass "E2b — and renders verbatim" \
  || fail_ "E2b" "the description was not rendered verbatim: $(grep -m1 'Description' "$E2/CLAUDE.md" 2>/dev/null | cut -c1-100)"

E3="$(newtmp)"
render_claude "$REPO_ROOT" "plain" "acme&co" "$E3/CLAUDE.md"
grep -q "acme&co" "$E3/CLAUDE.md" 2>/dev/null \
  && pass "E3 — a project name containing & renders verbatim (the interactive name path is tr-normalised only)" \
  || fail_ "E3" "name rendered as: $(grep -m1 'acme' "$E3/CLAUDE.md" 2>/dev/null | cut -c1-100)"

if [ -f "$TMPL_INTAKE" ]; then
  E4="$(newtmp)"
  render_intake "$REPO_ROOT" "R&D ~ tools" "acme" "$E4/PROJECT_INTAKE.md"
  grep -q "R&D ~ tools" "$E4/PROJECT_INTAKE.md" 2>/dev/null \
    && pass "E4 — the intake renderer (~ delimiter) renders a description with & and ~ verbatim" \
    || fail_ "E4" "rendered as: $(grep -m1 'One-sentence' "$E4/PROJECT_INTAKE.md" 2>/dev/null | cut -c1-120)"
else
  fail_ "E4 setup" "no intake template found under templates/generated/"
fi

echo "=== G — the name sites that only run inside a scaffold are pinned by grep ==="

# init.sh renders the project name into two files at birth; verify-install.sh
# re-renders it on --auto-fix. Neither can be driven here without running
# init.sh, so the ESCAPE CALL is pinned at the site rather than the behaviour.
for site in "init.sh" "scripts/verify-install.sh"; do
  n_raw="$(grep -cE 's\|__PROJECT_NAME__\|\$(PROJECT_NAME|proj_name)\|' "$REPO_ROOT/$site" 2>/dev/null)"
  n_esc="$(grep -cE 's\|__PROJECT_NAME__\|\$\(soif_sed_repl_esc ' "$REPO_ROOT/$site" 2>/dev/null)"
  if [ "$(_num "$n_raw")" -eq 0 ] && [ "$(_num "$n_esc")" -ge 1 ]; then
    pass "G — $site splices the project name through soif_sed_repl_esc ($n_esc site(s)), never raw"
  else
    fail_ "G — $site" "raw name replacements: $n_raw, escaped: $n_esc"
  fi
done

echo "=== M — mutation proofs on a mirror ==="

M_MARK="# BL-255-SED-REPL-ESC"
_n="$(_sites "$CORE" "$M_MARK")"
[ "$_n" = "1" ] \
  && pass "M0 — '$M_MARK' occurs exactly once at end-of-line in helpers-core.sh" \
  || fail_ "M0" "'$M_MARK' occurs $_n times (need exactly 1)"

# M1 — neuter the helper (identity) on a mirror: E1's & splice must return.
M1="$(newtmp)/fw"
if ! mk_mirror "$M1"; then
  fail_ "M1 setup" "could not mirror the framework"
else
  before="$(mktemp)"; cp "$M1/scripts/lib/helpers-core.sh" "$before"
  # the marked line is the one that does the escaping; replace it with a passthrough
  sed "s|^.*${M_MARK}\$|  printf '%s' \"\$1\"   ${M_MARK}|" "$before" > "$M1/scripts/lib/helpers-core.sh"
  if [ "$(_changed_lines "$before" "$M1/scripts/lib/helpers-core.sh")" -lt 2 ] || ! bash -n "$M1/scripts/lib/helpers-core.sh" 2>/dev/null; then
    fail_ "M1 setup" "the helper mutation did not apply cleanly"
  else
    M1O="$(newtmp)"
    render_claude "$M1" "R&D tools" "acme" "$M1O/CLAUDE.md"
    grep -q "R&D tools" "$M1O/CLAUDE.md" 2>/dev/null \
      && fail_ "M1 (MUTATION)" "with the helper neutered the & still rendered verbatim — E1 may be passing for another reason" \
      || pass "M1 (MUTATION) — with the helper neutered, & splices the whole match again: E1 is what stops it"
  fi
fi

# M2 — bypass the helper at the CLAUDE.md render site on a mirror: E2 must
# see the file written again (proves the SITE calls the helper, not just that
# the helper works).
M2="$(newtmp)/fw"
if ! mk_mirror "$M2"; then
  fail_ "M2 setup" "could not mirror the framework"
else
  before="$(mktemp)"; cp "$M2/scripts/lib/render-project-docs.sh" "$before"
  # THE DELIMITER IS ABSENT FROM BOTH SIDES, AND THE RESULT IS ASSERTED BY
  # SHAPE. A first cut of this mutant used `|` as the sed delimiter with `|`
  # in the pattern — CLAUDE.md's trap, inside the suite written to close it:
  # sed emitted an EMPTY mirror file, `bash -n` accepted the empty file, and
  # the changed-line count read the wreckage as an applied mutation. The
  # mutant then "changed nothing" because there was no renderer left to run.
  # `#` appears on neither side; the raw line must be present afterwards.
  sed 's#__PROJECT_DESCRIPTION__|$(soif_sed_repl_esc "$desc" "|")|g#__PROJECT_DESCRIPTION__|$desc|g#' "$before" > "$M2/scripts/lib/render-project-docs.sh"
  if ! grep -q 's|__PROJECT_DESCRIPTION__|$desc|g' "$M2/scripts/lib/render-project-docs.sh" \
     || ! grep -q '^soif_render_claude_md()' "$M2/scripts/lib/render-project-docs.sh" \
     || ! bash -n "$M2/scripts/lib/render-project-docs.sh" 2>/dev/null; then
    fail_ "M2 setup" "the render-site mutation did not produce the raw line (or damaged the file)"
  else
    M2O="$(newtmp)"
    render_claude "$M2" "a|w $M2O/pwned|" "acme" "$M2O/CLAUDE.md"
    ls "$M2O"/pwned* >/dev/null 2>&1 \
      && pass "M2 (MUTATION) — with the render site bypassing the helper, the w-flag writes a file again: E2 is what stops it" \
      || fail_ "M2 (MUTATION)" "bypassing the helper at the render site changed nothing — E2 may be passing for another reason"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1

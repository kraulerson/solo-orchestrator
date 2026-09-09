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
# wrote a 21-byte file named `<path>||g` and rendered the description as `a`
# (measured; GNU sed's `e` flag makes the same shape run a command).
# `--description` is
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
# `set -e` INSIDE the subshell, because every production caller of these
# renderers (init.sh, verify-install.sh, reconfigure-project.sh,
# upgrade-project.sh) runs under `set -euo pipefail`: a sed that fails inside
# the renderer aborts them. Without it here, the renderer's trailing `if`
# returned 0 over an empty file and E6b could not tell "failed loudly" from
# "produced nothing and said nothing".
# render_claude <lib_root> <desc> <name> <out>
render_claude() {
  ( set -e
    . "$1/scripts/lib/helpers-core.sh" >/dev/null 2>&1
    . "$1/scripts/lib/render-project-docs.sh" >/dev/null 2>&1
    soif_render_claude_md "$TMPL_CLAUDE" "$4" "$3" "$2" web standard typescript 3 personal ) 2>/dev/null
}
# render_intake <lib_root> <desc> <name> <out>
render_intake() {
  ( set -e
    . "$1/scripts/lib/helpers-core.sh" >/dev/null 2>&1
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
  # `&` as the DELIMITER: sed permits it, and a first cut escaped it twice
  # (the & step ran, then the delimiter step re-escaped the backslash it added)
  check_esc "an & delimiter is escaped exactly once" 'a&b'                 '&' 'a\&b'
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
  # E5 — the intake renderer's NAME splice. Under review, reverting this one
  # site passed every check: E4 exercises the description only and G's grep
  # covers only the `__PROJECT_NAME__` shape in init.sh / verify-install.sh.
  E5="$(newtmp)"
  render_intake "$REPO_ROOT" "plain" "acme&co" "$E5/PROJECT_INTAKE.md"
  grep -q '| \*\*Project name\*\* | acme&co |' "$E5/PROJECT_INTAKE.md" 2>/dev/null \
    && pass "E5 — the intake renderer renders a project name containing & verbatim in its own row" \
    || fail_ "E5" "name row rendered as: $(grep -m1 'Project name' "$E5/PROJECT_INTAKE.md" 2>/dev/null | cut -c1-120)"
else
  fail_ "E4 setup" "no intake template found (looked at $TMPL_INTAKE)"
fi

# E6 — a byte that is invalid in the current locale must NEVER be silently
# truncated. The first cut of the helper piped through `tr | sed`; `tr` failed
# on latin-1 é, the pipeline's last element succeeded, and the description
# came back cut short at rc 0 — silent data loss where the old code failed
# loudly (`sed: RE error: illegal byte sequence`, empty file). Pure parameter
# expansion is byte-transparent, so the helper no longer truncates; what the
# OUTER sed then does is locale-dependent and either outcome is acceptable:
#   under LC_ALL=C   the whole render is byte-wise and must be COMPLETE (E6a)
#   under the caller's locale  it must be complete OR loud — a Description line
#                              that exists but is cut short is the one forbidden
#                              outcome (E6b)
E6="$(newtmp)"
E6_IN="$(printf 'Rapport g\xe9n\xe9ral for R&D')"
LC_ALL=C render_claude "$REPO_ROOT" "$E6_IN" "acme" "$E6/CLAUDE.md"
if LC_ALL=C grep -q 'Rapport g.n.ral for R&D' "$E6/CLAUDE.md" 2>/dev/null; then
  pass "E6a — under LC_ALL=C a description with latin-1 bytes renders complete"
else
  fail_ "E6a" "rendered as: $(LC_ALL=C grep -m1 'Description' "$E6/CLAUDE.md" 2>/dev/null | cut -c1-100)"
fi
E6B="$(newtmp)"
render_claude "$REPO_ROOT" "$E6_IN" "acme" "$E6B/CLAUDE.md"; e6b_rc=$?
e6b_line="$(LC_ALL=C grep -m1 'Description' "$E6B/CLAUDE.md" 2>/dev/null)"
if [ -n "$e6b_line" ] && ! printf '%s' "$e6b_line" | LC_ALL=C grep -q 'Rapport g.n.ral for R&D'; then
  fail_ "E6b" "SILENT TRUNCATION: rc=$e6b_rc and the description line is cut short: $(printf '%s' "$e6b_line" | cut -c1-100)"
elif [ -n "$e6b_line" ]; then
  pass "E6b — under the caller's locale the description rendered complete"
elif [ "$e6b_rc" -ne 0 ]; then
  pass "E6b — under the caller's locale the render failed LOUDLY (rc=$e6b_rc, no description line) rather than truncating"
else
  fail_ "E6b" "rc=0 with no description line — a render that produced nothing and said nothing"
fi

echo "=== G — the name sites that only run inside a scaffold are pinned by grep ==="

# init.sh renders the project name into three files at birth; verify-install.sh
# re-renders name and description on --auto-fix; reconfigure-project.sh splices
# the NEW name on rename. None can be driven here without a scaffold, so the
# ESCAPE CALL is pinned at each site rather than the behaviour — and pinned
# EXACTLY: a first cut asserted `>= 1` escaped and greped one shape with one
# delimiter, so deleting two of init.sh's three calls passed, `${PROJECT_NAME}`
# and a `#` delimiter slipped, and verify-install's description and both
# reconfigure sites had no arm at all (reviewer mutants MX7/MX8 survived
# every PR-blocking check). Each row: file | placeholder-or-shape | expected
# escaped count. Raw = any `s<d>…<d>$VAR<d>` or `${VAR}` with ANY delimiter.
_g_check() {   # _g_check <file> <label> <raw-regex> <esc-regex> <want-esc>
  local f="$REPO_ROOT/$1" n_raw n_esc
  # COMMENTS ARE STRIPPED BEFORE COUNTING — the BL-181 class, and the review
  # planted a decoy comment carrying the escaped shape that inflated n_esc and
  # masked a deleted call. Whole-line and trailing comments both go.
  n_raw="$(grep -vE '^[[:space:]]*#' "$f" | sed 's/[[:space:]][[:space:]]*#.*$//' | grep -cE "$3" 2>/dev/null)"
  n_esc="$(grep -vE '^[[:space:]]*#' "$f" | sed 's/[[:space:]][[:space:]]*#.*$//' | grep -cE "$4" 2>/dev/null)"
  if [ "$(_num "$n_raw")" -eq 0 ] && [ "$(_num "$n_esc")" -eq "$5" ]; then
    pass "G — $1 $2: escaped at exactly $5 site(s), never raw"
  else
    fail_ "G — $1 $2" "raw: $n_raw (want 0), escaped: $n_esc (want $5)"
  fi
}
_g_check init.sh "project name" \
  's(.)__PROJECT_NAME__\1\$\{?(PROJECT_NAME|proj_name|name)\}?\1' \
  's(.)__PROJECT_NAME__\1\$\(soif_sed_repl_esc ' 3
_g_check scripts/verify-install.sh "project name" \
  's(.)__PROJECT_NAME__\1\$\{?(PROJECT_NAME|proj_name|name)\}?\1' \
  's(.)__PROJECT_NAME__\1\$\(soif_sed_repl_esc ' 1
_g_check scripts/verify-install.sh "description" \
  's(.)__PROJECT_DESCRIPTION__\1\$\{?(PROJECT_DESCRIPTION|proj_desc|desc)\}?\1' \
  's(.)__PROJECT_DESCRIPTION__\1\$\(soif_sed_repl_esc ' 1
_g_check scripts/reconfigure-project.sh "rename (new name)" \
  's(.)\$\{?old_name\}?\1\$\{?new_name\}?\1' \
  's(.)\$\{?old_name\}?\1\$\(soif_sed_repl_esc "\$new_name" ' 2

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

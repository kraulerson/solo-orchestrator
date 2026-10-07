#!/usr/bin/env bash
# tests/test-bl322-s3-ignore-preflight.sh — `## BL-322:` S3 (dogfood run 3,
# findings 4 and 5).
#
# FINDING 4. k-pdf's `.gitignore` line 20 is `lib/`, a standard Python template
# line, and it matches `scripts/lib/`. Adoption refused 26 of the files it must
# write — after the operator had answered every question — and Scout, run first
# precisely to say what adoption would meet, had said nothing. Scout now runs the
# same ignore test adoption runs (`# BL-225-PREWRITE-REFUSE`, the rule naming of
# `## BL-311:` group C), from the same code (scripts/lib/scout/scout-ignore.sh,
# which adoption sources), over the files adoption writes whatever the operator
# answers, and reports a block in its report.
#
# FINDING 5. The blocked run had already registered context7 and qdrant in the
# operator's Claude Code user configuration: the MCP step's `claude mcp add` ran
# before the ignore check. The step still ASKS where it did (the answer
# sequences every adoption suite pipes depend on that position), but what it
# RUNS waits until every check that can stop the adoption without writing has
# passed (`# BL-322-S3-MCP-DEFER`, `# BL-322-S3-MCP-APPLY-CALL`).
#
# CASES (each takes the framework root FW, so the mutants can point it at a
# mirror):
#   S1  the dogfood shape: Scout reports the block, naming the file, the line,
#       the rule and the one-line anchor, refusing exactly the framework's
#       scripts/lib files; and leaves the project byte-identical
#   S2  a clean project: checked, and quiet
#   S3  the same rule anchored (`/lib/`): quiet
#   S4  Scout copied out of a framework clone: says it could not check, and why
#   U1  the rule lines do not depend on the order the paths come in
#   P1  Scout's set of the files adoption writes IS the rehearsal's, on a plain
#       project (the rehearsal ledger of a real adoption, `# BL-242-REHEARSAL-KEEP`)
#   P2  the same on a project where adoption leaves files alone (a symlinked
#       CLAUDE.md and docs/archive, a read-only FEATURES.md, its own reference
#       guide, .claude/.gitignore, semgrep rules and skill NOTICE) and writes the
#       framework's CI; the classes Scout does not predict (the archive, the test
#       command, the Guardrails' own files) are present and are the only
#       difference
#   A1-A6  Scout and the REAL driver give the same answer on the same tree —
#       the refused paths, and every line naming the rules — for `lib/`, `*.md`,
#       a negation, a nested .gitignore, a global core.excludesFile under a fake
#       HOME, and .git/info/exclude
#   M1  a blocked adoption with "set it up now": no `claude mcp add`, no
#       container, and nothing written outside the project (the fake HOME, the
#       Claude Code configuration and TMPDIR are byte-identical afterwards)
#   M2  a passing adoption with "set it up now" still registers both servers,
#       records it, and runs the commands after the pre-write checks and before
#       the first writer
#   X*  mutants: each rewrites ONE marked line in a mirror, checks the edit
#       landed and still parses, and needs a named case to go RED
#
# Hermetic: temp HOME, XDG_CONFIG_HOME, GIT_CONFIG_GLOBAL and TMPDIR; stub
# claude/docker/curl/uvx/npx for the MCP cases; no network; no Guardrails clone
# (a seam points adoption at an empty folder). bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
export SOIF_ADOPT_MCP=off   # BL-311-MCP-SEAM — the M cases clear it, with stubs first on PATH

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }
_done() { echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; [ "$FAILED" -eq 0 ]; exit $?; }

echo "== BL-322 S3 — Scout predicts the ignore-rule block; a blocked adoption changes nothing outside the project =="
for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; _done; }
done
HAVE_GITLEAKS=0; command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl322s3.XXXXXX")" || exit 1
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM
# The developer's own git configuration must reach no fixture: a global excludes
# file would make every adoptee look ignored, and GIT_CONFIG_GLOBAL does not
# cover git's XDG default, so all three are pointed at empty places.
export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
: > "$WORK/gitconfig-empty"; export GIT_CONFIG_GLOBAL="$WORK/gitconfig-empty"
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
CASE_ENV=()

# ── fixtures ────────────────────────────────────────────────────────────────
# commit_all DIR — stage every untracked, unignored file BY NAME, and commit.
commit_all() {
  ( cd "$1" && git ls-files -o --exclude-standard -z | xargs -0 git add -- \
      && git commit -q -m 'chore: their history' ) >/dev/null 2>&1
}
# mk_project DIR [IGNORE-LINE...] — a git repository with one commit; the lines,
# if any, are its .gitignore.
mk_project() {
  local d="$1"; shift
  mkdir -p "$d" && ( cd "$d" && git init -q -b main . \
    && git config user.email s3@test.invalid && git config user.name 'BL-322 S3' ) >/dev/null 2>&1 || return 1
  printf '# acme\n' > "$d/README.md"
  [ "$#" -eq 0 ] || printf '%s\n' "$@" > "$d/.gitignore"
  commit_all "$d"
}
tree_hash() { ( cd "$1" && find . -exec ls -ld {} \; 2>/dev/null | awk '{ $6 = $7 = $8 = ""; print }' | LC_ALL=C sort | cksum
                cd "$1" && find . -type f -exec cksum {} \; 2>/dev/null | LC_ALL=C sort | cksum ); }

# scout_run FW DIR OUT — Scout's two reports into OUT.
scout_run() {
  ( cd "$WORK" && env ${CASE_ENV[@]+"${CASE_ENV[@]}"} bash "$1/scripts/scout.sh" --root "$2" --out "$3" ) >/dev/null 2>&1 \
    && [ -s "$3/scout-report.json" ]
}
ign() { jq -r "$2" "$1/scout-report.json" 2>/dev/null; }

# adopt_run FW DIR OUT ERR [ENV=VAL...] — the real driver, the answers the
# dogfood operator gave (personal, standard), then `1` to everything else.
adopt_run() {
  local fw="$1" d="$2" o="$3" e="$4"; shift 4
  ( cd "$d" && { printf '1\nstandard\n'; i=0; while [ "$i" -lt 40 ]; do printf '1\n'; i=$((i + 1)); done; } \
      | env SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" ${CASE_ENV[@]+"${CASE_ENV[@]}"} "$@" \
        bash "$fw/scripts/adopt-project.sh" ) > "$o" 2> "$e"
}
# The refused paths and the rule lines out of adoption's block (stderr).
blk_paths() { awk '/The refused path\(s\):$/ { p = 1; next } p && /^$/ { exit } p { print }' "$1" | LC_ALL=C sort; }
blk_rules() { awk '/^The rule\(s\) that refuse them/ { p = 1; next } p && /^          / { exit } p { print }' "$1"; }

# The framework's own scripts/lib files, from the framework's own parser — the
# expectation is REPO_ROOT's, never a mirror's.
shipped_lib() {
  ( . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" \
    && soif_parse_shipped_scripts "$REPO_ROOT/init.sh" "$REPO_ROOT/scripts" ) | grep '^scripts/lib/' | LC_ALL=C sort
}

# ════════════════════════════════════════════════════════════════════════════
# S — Scout's report
# ════════════════════════════════════════════════════════════════════════════
case_S1() {   # FW — the dogfood shape: `lib/` on line 3
  local fw="$1" d="" o="" h0="" want="" got="" n="" first="" bad="" md=""
  d="$(newtmp)"; o="$d/scan"
  mk_project "$d/p" 'node_modules/' '.venv/' 'lib/' || { CASE_DETAIL="fixture"; return 1; }
  h0="$(tree_hash "$d/p")"
  scout_run "$fw" "$d/p" "$o" || { CASE_DETAIL="scout produced no report"; return 1; }
  [ "$(tree_hash "$d/p")" = "$h0" ] || bad="$bad [Scout changed the project]"
  [ "$(ign "$o" '.collisions.ignoreRules.checked')" = true ] || bad="$bad [not checked: $(ign "$o" '.collisions.ignoreRules.why')]"
  [ "$(ign "$o" '.collisions.ignoreRules.wouldBlock')" = true ] || bad="$bad [the block is not predicted]"
  want="$(shipped_lib)"; n="$(printf '%s\n' "$want" | grep -c .)"; first="$(printf '%s\n' "$want" | head -1)"
  got="$(ign "$o" '.collisions.ignoreRules.refused[]' | LC_ALL=C sort)"
  [ "$got" = "$want" ] || bad="$bad [refused is not exactly the $n scripts/lib files: got $(printf '%s\n' "$got" | grep -c .)]"
  [ "$(jq -c '.collisions.ignoreRules.rules' "$o/scout-report.json")" = \
    "[{\"source\":\".gitignore\",\"line\":3,\"pattern\":\"lib/\",\"refuses\":$n,\"example\":\"$first\"}]" ] \
    || bad="$bad [rules: $(jq -c '.collisions.ignoreRules.rules' "$o/scout-report.json")]"
  ign "$o" '.collisions.ignoreRules.explanation[]' | grep -qF 'change line 3 of .gitignore to `/lib/`' \
    || bad="$bad [the JSON does not carry the one-line anchor]"
  md="$o/scout-report.md"
  grep -qF 'adoption would stop before it writes anything' "$md" || bad="$bad [the report does not say adoption would stop]"   # BL-322-S3-MD-BLOCK
  grep -qF ".gitignore, line 3: \`lib/\` refuses $n of them (for example $first)" "$md" || bad="$bad [the report does not name the file, the line and the rule]"
  grep -qF 'change line 3 of .gitignore to `/lib/`' "$md" || bad="$bad [the report does not suggest the anchor]"
  grep -qF 'here it matched scripts/lib' "$md" || bad="$bad [the report does not say where the rule matched]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_S2() {   # FW — a clean project: checked and quiet
  local fw="$1" d="" o="" bad="" n=""
  d="$(newtmp)"; o="$d/scan"
  mk_project "$d/p" 'node_modules/' '.venv/' || { CASE_DETAIL="fixture"; return 1; }
  scout_run "$fw" "$d/p" "$o" || { CASE_DETAIL="scout produced no report"; return 1; }
  [ "$(ign "$o" '.collisions.ignoreRules.checked')" = true ] || bad="$bad [not checked: $(ign "$o" '.collisions.ignoreRules.why')]"
  [ "$(ign "$o" '.collisions.ignoreRules.wouldBlock')" = false ] || bad="$bad [a block is predicted on a clean project]"
  [ "$(ign "$o" '.collisions.ignoreRules.refused | length')" = 0 ] || bad="$bad [refused paths on a clean project]"
  n="$(ign "$o" '.collisions.ignoreRules.pathsChecked')"
  case "$n" in ''|*[!0-9]*) bad="$bad [pathsChecked '$n']" ;; *) [ "$n" -ge 60 ] || bad="$bad [only $n paths checked]" ;; esac
  grep -qF '**No.** None of the' "$o/scout-report.md" || bad="$bad [the report does not say no]"
  grep -qF 'adoption would stop' "$o/scout-report.md" && bad="$bad [the report predicts a stop]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_S3() {   # FW — the dogfood rule, anchored: quiet
  local fw="$1" d="" o="" bad=""
  d="$(newtmp)"; o="$d/scan"
  mk_project "$d/p" 'node_modules/' '.venv/' '/lib/' || { CASE_DETAIL="fixture"; return 1; }
  scout_run "$fw" "$d/p" "$o" || { CASE_DETAIL="scout produced no report"; return 1; }
  [ "$(ign "$o" '.collisions.ignoreRules.checked')" = true ] || bad="$bad [not checked]"
  [ "$(ign "$o" '.collisions.ignoreRules.wouldBlock')" = false ] || bad="$bad [/lib/ still predicted to block: $(ign "$o" '.collisions.ignoreRules.refused[0]')]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_S4() {   # FW — Scout on its own, outside a framework clone
  local fw="$1" d="" o="" bad=""
  d="$(newtmp)"; o="$d/scan"
  mk_project "$d/p" 'lib/' || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/bare/scripts/lib" && cp "$fw/scripts/scout.sh" "$d/bare/scripts/" \
    && cp -R "$fw/scripts/lib/scout" "$d/bare/scripts/lib/" || { CASE_DETAIL="fixture: bare Scout"; return 1; }
  scout_run "$d/bare" "$d/p" "$o" || { CASE_DETAIL="a bare Scout produced no report"; return 1; }
  [ "$(ign "$o" '.collisions.ignoreRules.checked')" = false ] || bad="$bad [a bare Scout says it checked]"
  [ "$(ign "$o" '.collisions.ignoreRules.wouldBlock')" = false ] || bad="$bad [a bare Scout predicts a block]"
  ign "$o" '.collisions.ignoreRules.why' | grep -q 'framework' || bad="$bad [why: '$(ign "$o" '.collisions.ignoreRules.why')']"
  grep -qF '**Not checked.**' "$o/scout-report.md" || bad="$bad [the report does not say it was not checked]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

# U1 — the rule lines do not depend on the order a caller found the paths in.
# Scout sorts its own set; adoption's planned set is `sort -u` in the caller's
# locale, which on glibc with a collating locale (en_US.UTF-8) puts `BUGS.md`
# before `.claude/…`. Measured: on this Mac and on C.UTF-8 the two orders agree,
# so A1-A6 cannot see the sort — this case can, on any host.
case_U1() {   # FW
  local fw="$1" d="" rows="" fwd="" rev=""
  d="$(newtmp)"
  mk_project "$d/p" '*.md' 'lib/' || { CASE_DETAIL="fixture"; return 1; }
  rows="$(printf '%s\t%s\n' BUGS.md BUGS.md scripts/lib/a.sh scripts/lib/a.sh .claude/x.md .claude/x.md)"
  fwd="$( . "$fw/scripts/lib/scout/scout-ignore.sh" && scout_ignore_rules_explain "$d/p" "$rows" )"
  rev="$( . "$fw/scripts/lib/scout/scout-ignore.sh" && scout_ignore_rules_explain "$d/p" "$(printf '%s\n' "$rows" | sed -n '1!G;h;$p')" )"
  [ -n "$fwd" ] || { CASE_DETAIL="no rule lines"; return 1; }
  [ "$fwd" = "$rev" ] || { CASE_DETAIL="forwards [$(printf '%s' "$fwd" | head -1)] reversed [$(printf '%s' "$rev" | head -1)]"; return 1; }
  grep -qF '`*.md` refuses 2 of them (for example .claude/x.md)' <<<"$fwd" || { CASE_DETAIL="not the C-order example: $(printf '%s' "$fwd" | head -1)"; return 1; }
}

# ════════════════════════════════════════════════════════════════════════════
# P — Scout's set of the files adoption writes is the rehearsal's
# ════════════════════════════════════════════════════════════════════════════
# What Scout deliberately does not predict, because it depends on the answers
# or on a choice: the archive (a per-run folder of copies), .claude/test-command
# (only when the operator keeps the scan's command) and the Guardrails' own
# files (only when they are installed). The pin allows exactly these.
not_predicted() {
  awk '!/^\.claude\/adoption-archive\// && !/^\.claude\/framework\// && !/^\.claude\/project\// && $0 != ".claude/test-command"'
}
# rehearsal_set BUILDER NAME — the planned set of a real adoption of a project
# BUILDER makes, from REPO_ROOT, computed once and cached (a Scout-side mutant
# does not change it).
rehearsal_set() {
  local b="$1" name="$2" d=""
  if [ ! -s "$WORK/reh.$name" ]; then
    d="$(newtmp)"
    "$b" "$d/p" || return 1
    adopt_run "$REPO_ROOT" "$d/p" "$d/out" "$d/err" SOIF_REHEARSAL_KEEP="$d/keep"
    printf '%s\n' "$?" > "$WORK/reh.$name.rc"
    [ -s "$d/keep/work/written" ] || return 1
    LC_ALL=C sort -u "$d/keep/work/written" > "$WORK/reh.$name"
  fi
  cat "$WORK/reh.$name"
}
# scout_set FW BUILDER — Scout's set for a fresh project BUILDER makes.
scout_set() {
  local fw="$1" b="$2" d="" ci=""
  d="$(newtmp)"
  "$b" "$d/p" || return 1
  scout_run "$fw" "$d/p" "$d/scan" || return 1
  ci="$(ign "$d/scan" '.stack.ciHost // ""')"
  ( . "$fw/scripts/lib/scout/scout-ignore.sh" && scout_adoption_write_set "$fw" "$d/p" "$ci" ) | LC_ALL=C sort -u
}
set_diff() {   # A B — lines only in A as -x, only in B as +x
  { printf '%s\n' "$1" | grep . | sed 's/^/-/'; printf '%s\n' "$2" | grep . | sed 's/^/+/'; } \
    | LC_ALL=C sort | awk '{ k = substr($0, 2); c[k]++; l[k] = $0 } END { for (k in c) if (c[k] == 1) print l[k] }' | LC_ALL=C sort
}

build_plain() { mk_project "$1" 'node_modules/'; }
build_keeps() {   # adoption leaves these alone; and writes its CI, its test command and an archive
  local d="$1"
  mk_project "$d" 'node_modules/' '.venv/' || return 1
  mkdir -p "$d/docs/reference" "$d/.claude/skills/zoom-out" "$d/.semgrep" "$d/arch-real" "$d/tests" "$d/acme" "$d/.github/workflows" || return 1
  printf 'name: ci\non: [push]\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: uv run pytest\n' > "$d/.github/workflows/ci.yml"
  printf '# agents\n' > "$d/AGENTS.md"; ln -s AGENTS.md "$d/CLAUDE.md"
  ln -s ../arch-real "$d/docs/archive"; printf 'x\n' > "$d/arch-real/notes.md"
  printf '# ours\n' > "$d/FEATURES.md"
  printf '# our guide\n' > "$d/docs/reference/user-guide.md"
  printf '/scratch/\n' > "$d/.claude/.gitignore"
  printf 'rules: []\n' > "$d/.semgrep/soif-dom-sinks.yml"
  printf 'ours\n' > "$d/.claude/skills/zoom-out/NOTICE"
  printf '{}\n' > "$d/.claude/settings.json"
  printf '[project]\nname = "acme"\nversion = "0.1.0"\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > "$d/pyproject.toml"
  printf 'version = 1\n' > "$d/uv.lock"
  printf 'def test_x():\n    assert True\n' > "$d/tests/test_x.py"
  printf 'X = 1\n' > "$d/acme/__init__.py"
  ( cd "$d" && git remote add origin https://github.com/acme/acme.git ) || return 1
  commit_all "$d" || return 1
  chmod 444 "$d/FEATURES.md"
}

pin_case() {   # FW BUILDER NAME
  local fw="$1" b="$2" name="$3" reh="" sc="" dif=""
  reh="$(rehearsal_set "$b" "$name")" || { CASE_DETAIL="no rehearsal ledger from a real adoption"; return 1; }
  sc="$(scout_set "$fw" "$b")" || { CASE_DETAIL="Scout's set could not be derived"; return 1; }
  [ -n "$sc" ] || { CASE_DETAIL="Scout's set is empty"; return 1; }
  dif="$(set_diff "$(printf '%s\n' "$reh" | not_predicted)" "$sc")"
  [ -z "$dif" ] || { CASE_DETAIL="rehearsal (-) vs Scout (+): $(printf '%s' "$dif" | head -12 | tr '\n' ' ')"; return 1; }
}
case_P1() { pin_case "$1" build_plain plain; }
case_P2() {
  local reh="" bad="" p=""
  pin_case "$1" build_keeps keeps || return 1
  reh="$(cat "$WORK/reh.keeps")"
  # Not vacuous: the classes Scout leaves out are really there, and the files
  # adoption leaves alone really were left alone.
  printf '%s\n' "$reh" | grep -q '^\.claude/adoption-archive/' || bad="$bad [no archive in the rehearsal]"
  printf '%s\n' "$reh" | grep -qx '\.claude/test-command' || bad="$bad [no test command in the rehearsal]"
  printf '%s\n' "$reh" | grep -qx '\.github/workflows/solo-gates\.yml' || bad="$bad [no framework CI in the rehearsal]"
  for p in CLAUDE.md FEATURES.md docs/archive/README.md docs/reference/user-guide.md .claude/.gitignore \
           .semgrep/soif-dom-sinks.yml .claude/skills/zoom-out/NOTICE; do
    printf '%s\n' "$reh" | grep -qxF -- "$p" && bad="$bad [the rehearsal wrote $p]"
  done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

# ════════════════════════════════════════════════════════════════════════════
# A — Scout and the real driver agree on the same tree
# ════════════════════════════════════════════════════════════════════════════
build_lib()  { mk_project "$1" 'node_modules/' 'lib/'; }
build_md()   { mk_project "$1" '*.md' '!README.md'; }
build_neg()  { mk_project "$1" 'scripts/*' '!scripts/lib/'; }
build_nest() { mk_project "$1" || return 1; mkdir -p "$1/scripts" && printf 'lib/\n' > "$1/scripts/.gitignore" && commit_all "$1"; }
build_glob() { mk_project "$1"; }      # its rule is in the case's global excludes file
build_excl() { mk_project "$1" || return 1; mkdir -p "$1/.git/info" && printf '# this clone\n.claude/\n' > "$1/.git/info/exclude"; }

# adoption_answer FW BUILDER NAME — the real driver's block, into $ANS.err and
# $ANS.rc. From REPO_ROOT it is computed once and cached; from a mirror it is
# computed every time, because the decision and the rule lines are shared code
# and a mutant of them changes adoption's answer too.
ANS=""
adoption_answer() {
  local fw="$1" b="$2" name="$3" d=""
  if [ "$fw" = "$REPO_ROOT" ]; then ANS="$WORK/ans.$name"; else ANS="$(newtmp)/ans"; fi
  [ -s "$ANS.err" ] && return 0
  d="$(newtmp)"
  "$b" "$d/p" || return 1
  adopt_run "$fw" "$d/p" "$d/out" "$ANS.err"
  printf '%s\n' "$?" > "$ANS.rc"
}
agree_case() {   # FW BUILDER NAME
  local fw="$1" b="$2" name="$3" d="" bad="" sp="" ap="" sr="" ar=""
  [ "$HAVE_GITLEAKS" = 1 ] || { CASE_DETAIL="SKIP: gitleaks is not on PATH, and a personal adoption stops for it before the check"; return 2; }
  adoption_answer "$fw" "$b" "$name" || { CASE_DETAIL="fixture"; return 1; }
  d="$(newtmp)"
  "$b" "$d/p" || { CASE_DETAIL="fixture"; return 1; }
  scout_run "$fw" "$d/p" "$d/scan" || { CASE_DETAIL="scout produced no report"; return 1; }
  [ "$(cat "$ANS.rc")" != 0 ] || bad="$bad [the real driver did not stop]"
  grep -q 'your ignore rules refuse' "$ANS.err" || bad="$bad [the real driver did not stop at the ignore check: $(grep -E 'BLOCKED|REFUSED' "$ANS.err" | head -1)]"
  [ "$(ign "$d/scan" '.collisions.ignoreRules.wouldBlock')" = true ] || bad="$bad [Scout does not predict it]"
  sp="$(ign "$d/scan" '.collisions.ignoreRules.refused[]' | LC_ALL=C sort)"
  ap="$(blk_paths "$ANS.err")"
  [ -n "$ap" ] || bad="$bad [no refused paths read from the block]"
  [ "$sp" = "$ap" ] || bad="$bad [refused paths differ: adoption (-) vs Scout (+) $(set_diff "$ap" "$sp" | head -6 | tr '\n' ' ')]"
  sr="$(ign "$d/scan" '.collisions.ignoreRules.explanation[]')"
  ar="$(blk_rules "$ANS.err")"
  [ -n "$ar" ] || bad="$bad [no rule lines read from the block]"
  [ "$sr" = "$ar" ] || bad="$bad [the rule lines differ: adoption [$(printf '%s' "$ar" | head -2 | tr '\n' '|')] Scout [$(printf '%s' "$sr" | head -2 | tr '\n' '|')]]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_A1() { agree_case "$1" build_lib lib; }
case_A2() { agree_case "$1" build_md md; }
case_A3() { agree_case "$1" build_neg neg; }
case_A4() { agree_case "$1" build_nest nest; }
case_A5() {   # a global core.excludesFile, written as ~/, under a fake HOME
  local h="$WORK/glob-home" rc=0
  mkdir -p "$h" && printf 'docs/\n' > "$h/.gitignore_global" \
    && printf '[core]\n\texcludesFile = ~/.gitignore_global\n' > "$h/.gitconfig" || { CASE_DETAIL="fixture"; return 1; }
  CASE_ENV=("HOME=$h" "GIT_CONFIG_GLOBAL=$h/.gitconfig")
  agree_case "$1" build_glob glob || rc=$?
  CASE_ENV=()
  [ "$rc" -eq 0 ] || return "$rc"
  grep -qF "$h/.gitignore_global (outside this repository: core.excludesFile in your global git config names it" "$ANS.err" \
    || { CASE_DETAIL="the block does not name the global excludes file"; return 1; }
}
case_A6() { agree_case "$1" build_excl excl; }

# ════════════════════════════════════════════════════════════════════════════
# M — the MCP step's side effects wait for the checks
# ════════════════════════════════════════════════════════════════════════════
mkstubs() {   # DIR
  local d="$1"
  mkdir -p "$d" || return 1
  cat > "$d/claude" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
{ printf 'claude'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$st/calls.log"
if [ ! -t 0 ]; then cat >/dev/null; fi
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then f="$CLAUDE_CONFIG_DIR/.claude.json"; else f="$HOME/.claude.json"; fi
if [ "${1:-}" = mcp ] && [ "${2:-}" = get ]; then
  jq -e --arg n "${3:-}" '.mcpServers[$n]' "$f" >/dev/null 2>&1 || { echo "No MCP server found with name: ${3:-}" >&2; exit 1; }
  printf '%s:\n  Status: \342\234\224 Connected\n\nTo remove this server, run: claude mcp remove %s -s user\n' "$3" "$3"
  exit 0
fi
[ "${1:-}" = mcp ] && [ "${2:-}" = add ] || exit 0
shift 2
name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    -s|--scope) shift 2 ;;
    -e) shift; while [ $# -gt 0 ]; do case "$1" in -*) break ;; *) shift ;; esac; done ;;
    -*) shift ;;
    *) [ -z "$name" ] && name="$1"; shift ;;
  esac
done
[ -n "$name" ] && [ $# -gt 0 ] || { echo "stub claude: missing name or command" >&2; exit 1; }
mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
jq --arg n "$name" --arg c "$1" '.mcpServers[$n] = {type: "stdio", command: $c}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
echo "Added stdio MCP server $name"
STUB
  cat > "$d/docker" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
{ printf 'docker'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$st/calls.log"
if [ ! -t 0 ]; then cat >/dev/null; fi
case "${1:-}" in
  info) [ -f "$st/docker-up" ] ;;
  ps) exit 0 ;;
  run|start) : > "$st/qdrant-up"; echo started ;;
  *) exit 1 ;;
esac
STUB
  cat > "$d/curl" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
u=""; for a in "$@"; do u="$a"; done
if [ ! -t 0 ]; then cat >/dev/null; fi
case "$u" in *localhost:6333*|*127.0.0.1:6333*) [ -f "$st/qdrant-up" ] && exit 0 ;; esac
exit 7
STUB
  printf '#!/bin/bash\nexit 0\n' > "$d/uvx"
  printf '#!/bin/bash\nexit 0\n' > "$d/npx"
  chmod +x "$d"/*
}
STUBS="$WORK/stubs"; mkstubs "$STUBS" || { echo "FATAL: stubs"; exit 1; }

# mcp_adopt FW DIR C — a whole adoption with the MCP step live: stubs first on
# PATH, a fake HOME, CLAUDE_CONFIG_DIR and TMPDIR of the case's own, and "set it
# up now" as the third answer.
mcp_adopt() {
  local fw="$1" d="$2" c="$3"
  ( cd "$d" && { printf '1\nstandard\nset it up now\n'; i=0; while [ "$i" -lt 40 ]; do printf '1\n'; i=$((i + 1)); done; } \
      | env -u SOIF_ADOPT_MCP PATH="$STUBS:$PATH" HOME="$c/home" CLAUDE_CONFIG_DIR="$c/cfg" STUB_STATE="$c/state" \
          TMPDIR="$c/tmp" SOIF_ADOPT_QDRANT_WAIT=2 SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" \
          bash "$fw/scripts/adopt-project.sh" ) > "$c/out" 2> "$c/err"
}
mcp_fixture() {   # C — the case's outside world
  mkdir -p "$1/home" "$1/cfg" "$1/state" "$1/tmp" || return 1
  : > "$1/state/calls.log"; : > "$1/state/docker-up"
}
outside_hash() { { tree_hash "$1/home"; tree_hash "$1/cfg"; tree_hash "$1/tmp"; } | cksum; }

case_M1() {   # FW — blocked: nothing outside the project changes
  local fw="$1" c="" h0="" rc=0 bad=""
  [ "$HAVE_GITLEAKS" = 1 ] || { CASE_DETAIL="SKIP: gitleaks is not on PATH, and a personal adoption stops for it first"; return 2; }
  c="$(newtmp)"; mcp_fixture "$c" || { CASE_DETAIL="fixture"; return 1; }
  build_lib "$c/p" || { CASE_DETAIL="fixture"; return 1; }
  h0="$(outside_hash "$c")"
  mcp_adopt "$fw" "$c/p" "$c" || rc=$?
  [ "$rc" -ne 0 ] || bad="$bad [the adoption did not stop]"
  grep -q 'your ignore rules refuse' "$c/err" || bad="$bad [not stopped by the ignore check: $(grep -E 'BLOCKED|REFUSED' "$c/err" | head -1)]"
  grep -q 'Set them up now' "$c/out" || bad="$bad [fixture: the MCP question was not asked]"
  grep -q '\[mcp\] \[add\]' "$c/state/calls.log" && bad="$bad [claude mcp add ran: $(grep '\[mcp\] \[add\]' "$c/state/calls.log" | head -1)]"
  grep -qE 'docker \[(run|start)\]' "$c/state/calls.log" && bad="$bad [a container was started]"
  [ "$(outside_hash "$c")" = "$h0" ] || bad="$bad [something was written outside the project: $(cd "$c" && find home cfg tmp -mindepth 1 | head -3 | tr '\n' ' ')]"
  grep -q 'DID register' "$c/err" && bad="$bad [the refusal names a registration]"
  grep -qF 'did not begin. Nothing was committed and nothing was written to this project.' "$c/err" || bad="$bad [the refusal does not say the run did not begin]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_M2() {   # FW — passing: the servers are still set up, after the checks and before the first writer
  local fw="$1" c="" rc=0 bad="" lr="" lc="" li=""
  [ "$HAVE_GITLEAKS" = 1 ] || { CASE_DETAIL="SKIP: gitleaks is not on PATH, and a personal adoption stops for it first"; return 2; }
  c="$(newtmp)"; mcp_fixture "$c" || { CASE_DETAIL="fixture"; return 1; }
  mk_project "$c/p" 'node_modules/' '/lib/' || { CASE_DETAIL="fixture"; return 1; }
  mcp_adopt "$fw" "$c/p" "$c" || rc=$?
  [ "$rc" -eq 0 ] || bad="$bad [rc $rc: $(grep -E 'BLOCKED|REFUSED' "$c/err" | head -1)]"
  grep -q 'claude \[mcp\] \[add\] \[context7\]' "$c/state/calls.log" || bad="$bad [context7 not added]"
  grep -q 'claude \[mcp\] \[add\] \[-s\] \[user\] \[qdrant\]' "$c/state/calls.log" || bad="$bad [qdrant not added]"
  jq -e '.mcpServers.context7 and .mcpServers.qdrant' "$c/cfg/.claude.json" >/dev/null 2>&1 || bad="$bad [not registered in the session's config]"
  grep -F '| MCP servers (Qdrant, Context7) |' "$c/p/APPROVAL_LOG.md" 2>/dev/null | grep -q 'set up by adoption' \
    || bad="$bad [the Adoption Record does not say set up: $(grep -F '| MCP servers' "$c/p/APPROVAL_LOG.md" 2>/dev/null | head -1)]"
  lc="$(grep -n 'copied the project in' "$c/out" | head -1 | cut -d: -f1)"
  lr="$(grep -n 'Running: claude mcp add context7' "$c/out" | head -1 | cut -d: -f1)"
  li="$(grep -n "Installing the framework's own scripts" "$c/out" | head -1 | cut -d: -f1)"
  { [ -n "$lc" ] && [ -n "$lr" ] && [ -n "$li" ] && [ "$lc" -lt "$lr" ] && [ "$lr" -lt "$li" ]; } \
    || bad="$bad [the commands do not run between the pre-write check and the first writer: rehearsal@${lc:-?} run@${lr:-?} install@${li:-?}]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

# ── the cases ────────────────────────────────────────────────────────────────
run_case() {   # LABEL FN — a SKIP (rc 2) is reported as one, never as a pass
  local label="$1" fn="$2" rc=0
  CASE_DETAIL=""
  "$fn" "$REPO_ROOT" || rc=$?
  case "$rc" in
    0) pass "$label" ;;
    2) skip "$label" "${CASE_DETAIL#SKIP: }" ;;
    *) fail_ "$label" "${CASE_DETAIL:-failed}" ;;
  esac
}
echo "=== S — Scout's report ==="
run_case "S1 the dogfood shape (lib/ on line 3): Scout predicts the block, names the file, the line, the rule and the anchor, refuses exactly the framework's scripts/lib files, and changes nothing" case_S1
run_case "S2 a clean project: checked, and quiet" case_S2
run_case "S3 the rule anchored (/lib/): quiet" case_S3
run_case "S4 Scout outside a framework clone: not checked, and says why" case_S4
run_case "U1 the rule lines are the same whatever order the paths come in (the example is the first in C order)" case_U1
echo "=== P — Scout's set of the files adoption writes is the rehearsal's ==="
run_case "P1 a plain project: Scout's set equals the rehearsal ledger of a real adoption" case_P1
run_case "P2 a project adoption partly leaves alone, with CI, a test command and an archive: equal but for the classes Scout does not predict" case_P2
echo "=== A — Scout and the real driver give the same answer on the same tree ==="
run_case "A1 lib/ (the dogfood rule)" case_A1
run_case "A2 *.md, re-including README.md (and APPROVAL_LOG.md, staged only when git will, never blocks)" case_A2
run_case "A3 a negation: scripts/* then !scripts/lib/" case_A3
run_case "A4 a nested scripts/.gitignore: lib/" case_A4
run_case "A5 a global core.excludesFile (~/), under a fake HOME: docs/" case_A5
run_case "A6 .git/info/exclude: .claude/" case_A6
echo "=== M — the MCP step's side effects wait for the checks ==="
run_case "M1 a blocked adoption that was told to set the servers up runs no claude mcp add, starts no container, and writes nothing outside the project" case_M1
run_case "M2 a passing adoption still sets both servers up, records it, and runs the commands after the pre-write checks and before the first writer" case_M2

# ════════════════════════════════════════════════════════════════════════════
# X — mutants. Each rewrites ONE line ending in its marker, in a mirror of the
# framework, asserts the rewrite LANDED by its own text and still parses, and
# requires the named case to go RED. A mutant that did not land is a FAILURE.
# ════════════════════════════════════════════════════════════════════════════
echo "=== X — mutants ==="
mk_mirror() { mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/docs" "$1/init.sh" "$2/"; }
mutate() {   # FILE MARKER REPLACEMENT — exactly one line ends in MARKER; it now reads REPLACEMENT; still parses
  local f="$1" mark="$2" repl="$3" n=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
}
# sub_line FILE MARKER OLD NEW — on the one line ending in MARKER, the first OLD
# becomes NEW. Exactly one line changes; still parses.
sub_line() {
  local f="$1" mark="$2" old="$3" new="$4" n="" d=""
  n="$(MARK="$mark" OLD="$old" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m && index($0, ENVIRON["OLD"]) {c++} END{print c}' "$f")"
  [ "$n" = 1 ] || { echo "'$old' on a line ending '$mark': $n line(s) of $f (need 1)"; return 1; }
  cp "$f" "$f.orig" || return 1
  MARK="$mark" OLD="$old" NEW="$new" awk '{ m = ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m && (i = index($0, ENVIRON["OLD"]))) $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"]))
      print }' "$f.orig" > "$f"
  d="$(diff "$f.orig" "$f" | grep -c '^>')"
  rm -f "$f.orig"
  [ "$d" = 1 ] || { echo "changed $d line(s), want 1"; return 1; }
  grep -qF -- "$new" "$f" || { echo "the new text did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
}
run_mutant() {   # ID WHAT KILLER MIRROR
  local rc=0
  CASE_DETAIL=""
  "$3" "$4" || rc=$?
  case "$rc" in
    0) fail_ "$1" "$2 — SURVIVED: ${3#case_} still passes against the mutant" ;;
    2) skip "$1" "$2 — ${CASE_DETAIL#SKIP: }" ;;
    *) pass "$1 (MUTATION) — $2: killed by ${3#case_} (${CASE_DETAIL:-failed})" ;;
  esac
}
mutant() {   # ID FILE MARKER REPLACEMENT KILLER WHAT
  local m="" why=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate "$m/$2" "$3" "$4")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$6" "$5" "$m"
}
mutant_sub() {   # ID FILE MARKER OLD NEW KILLER WHAT
  local m="" why=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(sub_line "$m/$2" "$3" "$4" "$5")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$7" "$6" "$m"
}
SI=scripts/lib/scout/scout-ignore.sh
SR=scripts/lib/scout/scout-report.sh
AS=scripts/lib/adopt/adopt-state.sh
AM=scripts/lib/adopt/adopt-mcp.sh
mutant     X1  scripts/scout.sh '# BL-322-S3-SCOUT-CALL' 'scout_ignore_scan() { :; }   # BL-322-S3-SCOUT-CALL' case_S1 "Scout never runs the ignore check"
mutant_sub X2  "$SI" '# BL-322-S3-FW-GUARD' '[ -f "$1/init.sh" ]' '[ -f "$1/no-such-file" ]' case_S1 "Scout never recognises the framework clone it runs from"
mutant     X3  "$SI" '# BL-322-S3-FW-GUARD' '  return 0   # BL-322-S3-FW-GUARD' case_S4 "Scout outside a framework clone claims to have checked"
mutant_sub X4  "$SI" '# BL-322-S3-SET-SCRIPTS' 'printf' ': printf' case_S1 "the framework's scripts are left out of the set"
mutant_sub X5  "$SI" '# BL-322-S3-STAGEABLE-ONLY' 'APPROVAL_LOG.md' 'NO_SUCH.md' case_A2 "APPROVAL_LOG.md, which adoption stages only when git will, is counted as refused"
mutant_sub X6  "$SI" '# BL-322-S3-SET-KEEP' '[ -L "$root/$rel" ]' 'false' case_P2 "a symlinked document adoption leaves alone is counted as written"
mutant_sub X7  "$SI" '# BL-322-S3-SET-KEEP' '[ ! -w "$root/$rel" ]' 'false' case_P2 "a read-only document adoption leaves alone is counted as written"
mutant_sub X8  "$SI" '# BL-322-S3-SET-UNDER-LINK' '[ -L "$root/$pre" ]' 'false' case_P2 "a document inside a symlinked folder is counted as written"
mutant_sub X9  "$SI" '# BL-322-S3-SET-REF-ABSENT' '[ -e "$root/docs/reference/$base" ]' 'false' case_P2 "a reference guide the project already has is counted as written"
mutant_sub X10 "$SI" '# BL-322-S3-SET-IGNORE-ABSENT' '[ -e "$root/.claude/.gitignore" ]' 'false' case_P2 "a .claude/.gitignore the project already has is counted as written"
mutant_sub X11 "$SI" '# BL-322-S3-SET-SEMGREP-ABSENT' '[ -e "$root/.semgrep/soif-dom-sinks.yml" ]' 'false' case_P2 "semgrep rules the project already has are counted as written"
mutant_sub X12 "$SI" '# BL-322-S3-SET-NOTICE-ABSENT' '[ ! -e "$root/.claude/skills/$s/NOTICE" ]' 'true' case_P2 "a skill NOTICE the project already has is counted as written"
mutant_sub X13 "$SI" '# BL-322-S3-SET-CI' 'github)' 'nogithub)' case_P2 "the framework's CI is left out of the set"
mutant_sub X14 "$SI" '# BL-322-S3-EXPLAIN-SORT' '| LC_ALL=C sort' '' case_U1 "the rule lines follow the caller's path order, so Scout and adoption can name different examples"
mutant_sub X15 "$SR" '# BL-322-S3-REPORT-BLOCK' '$(_scout_bool "$blk")' 'false' case_S1 "the JSON never says adoption would stop"
mutant_sub X16 "$SR" '# BL-322-S3-MD-BLOCK' 'adoption would stop before it writes anything' 'adoption might have a problem' case_S1 "the report's block sentence is lost"
mutant_sub X17 "$AS" '# BL-311-MCP-CALL' 'adopt_mcp_resolve "$root" ||' 'adopt_mcp_resolve "$root" && adopt_mcp_apply "$root" ||' case_M1 "the MCP commands run where the question is, before the ignore check (the dogfood order)"
mutant     X18 "$AS" '# BL-322-S3-MCP-APPLY-CALL' '  :   # BL-322-S3-MCP-APPLY-CALL' case_M2 "the MCP commands never run"
mutant_sub X19 "$AM" '# BL-322-S3-MCP-DEFER' 'ADOPT_MCP_PENDING=1' 'ADOPT_MCP_PENDING=1; adopt_mcp_apply "$root"' case_M1 "the step runs its commands as soon as it is answered"

_done

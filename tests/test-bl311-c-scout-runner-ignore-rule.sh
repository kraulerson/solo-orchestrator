#!/usr/bin/env bash
# tests/test-bl311-c-scout-runner-ignore-rule.sh — `## BL-311:` rows 4 and 5.
#
# ROW 4. Scout reported a suite that passes 1071/0 as failing with exit 127:
# its test command was a bare `pytest` in a uv project, and `sh -c pytest` does
# not find a tool that lives in the project's own environment. The same defect
# has a Node twin — the `package.json scripts.test` arm handed Scout the script
# BODY (`vitest run`), and `node_modules/.bin` is not on PATH either (measured:
# a pnpm fixture with a working `vitest` reported exitCode 127). The command now
# goes through the detected package manager, and the evidence string says which
# file made Scout choose it.
#
# ROW 5. "your ignore rules refuse 24 of the files" was right and told the
# operator nothing about WHICH rule — `lib/` in `.gitignore` matching
# `scripts/lib/`. The block now names each rule git reports (file, line,
# pattern), grouped so one rule refusing 24 paths is printed once, names a rule
# that lives outside the repository as such, and suggests the one-line fix
# without ever editing the file. When git cannot name the rule, the block is
# the one it was before, plus how to ask git directly — never silence.
#
# The cases run twice over: once against this tree, and again under the
# mutation proofs at the bottom, which break ONE marked line in a mirror of
# scripts/lib and require a NAMED assertion to kill it.
set -uo pipefail
# The adoption driver's MCP step is switched off in every suite that drives
# adoption (`# BL-311-MCP-SEAM`); this one runs the real driver once (I9).
export SOIF_ADOPT_MCP=off

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBROOT="$REPO_ROOT/scripts/lib"   # the mutation proofs point this at a mirror

PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }
skip_() { SKIP=$((SKIP+1)); echo "  [SKIP] $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }
# Here-strings, not `printf | grep -q`: under pipefail an early-exiting grep
# can SIGPIPE the writer and read as a miss (the class main fixed in #422).
has() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing '$3')"; fi; }
hasnt() { if grep -qF -- "$3" <<<"$2"; then bad "$1 (must not say '$3')"; else ok "$1"; fi; }
nlines() { grep -cF -- "$2" <<<"$1"; }

echo "== BL-311 rows 4 and 5 — Scout's test runner, and the ignore rule that refuses =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "  [SKIP] every case — $t is not on PATH"; echo; echo "Results: 0 passed, 0 failed"; exit 0; }
done
REAL_GIT="$(command -v git)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl311c.XXXXXX")" || exit 1
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM
# A global excludes file would make every adoptee look ignored, and
# GIT_CONFIG_GLOBAL does not cover the XDG default, so neutralise both.
export XDG_CONFIG_HOME="$WORK/xdg"; mkdir -p "$XDG_CONFIG_HOME"
export HOME="$WORK/home"; mkdir -p "$HOME"
unset GITHUB_BASE_REF

# ════════════════════════════════════════════════════════════════════════════
# Fixtures, built ONCE: Scout and the pre-write check only read them.
# ════════════════════════════════════════════════════════════════════════════

# _fx NAME FILE... — a Scout fixture holding FILEs. Config files get the
# content their arm looks for; everything else is an empty marker file.
_fx() {
  local d="$WORK/fx/$1" f=""; shift
  mkdir -p "$d"
  for f in "$@"; do
    case "$f" in
      pyproject.toml) printf '[project]\nname = "x"\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > "$d/$f" ;;
      pytest.ini)     printf '[pytest]\ntestpaths = tests\n' > "$d/$f" ;;
      tox.ini)        printf '[testenv]\ncommands = pytest\n' > "$d/$f" ;;
      setup.cfg)      printf '[tool:pytest]\ntestpaths = tests\n' > "$d/$f" ;;
      package.json)   printf '{ "name": "x", "scripts": { "test": "vitest run" } }\n' > "$d/$f" ;;
      Makefile)       printf 'test:\n\t@true\n' > "$d/$f" ;;
      *)              printf 'x\n' > "$d/$f" ;;
    esac
  done
}
_fx py-uv       pyproject.toml uv.lock
_fx py-poetry   pytest.ini poetry.lock
_fx py-pdm      tox.ini pdm.lock
_fx py-pipenv   setup.cfg Pipfile.lock Pipfile
_fx py-pipfile  pytest.ini Pipfile
_fx py-pip      pytest.ini requirements.txt
_fx py-none     pytest.ini
_fx py-make     Makefile pyproject.toml uv.lock
_fx pp-all      pytest.ini uv.lock poetry.lock Pipfile
_fx pp-poe-pdm  pytest.ini poetry.lock pdm.lock
_fx pp-pdm-pipe pytest.ini pdm.lock Pipfile.lock
_fx js-pnpm     package.json pnpm-lock.yaml
_fx js-yarn     package.json yarn.lock
_fx js-npm      package.json package-lock.json
_fx js-bun      package.json bun.lock
_fx js-bunb     package.json bun.lockb
_fx js-deno     package.json deno.lock
_fx js-none     package.json
_fx js-mixed    package.json uv.lock
_fx jp-pn-yarn  package.json pnpm-lock.yaml yarn.lock
_fx jp-yarn-npm package.json yarn.lock package-lock.json
_fx jp-npm-bun  package.json package-lock.json bun.lock
_fx jp-bun-deno package.json bun.lock deno.lock

# _tc NAME — Scout's `value|source` for fixture NAME, from the lib at LIBROOT.
_tc() {
  ( w="$(mktemp -d "$WORK/tc.XXXXXX")" || exit 1
    . "$LIBROOT/scout/scout-stack.sh" || exit 1
    _scout_pkg_managers "$WORK/fx/$1" "$w" && _scout_test_command "$WORK/fx/$1" "$w" || exit 1
    tr '\t' '|' < "$w/testcmd"; rm -rf "$w" )
}
_val() { printf '%s' "${1%%|*}"; }
_src() { printf '%s' "${1#*|}"; }

# _scout_bin — a scout.sh that runs LIBROOT's scout lib: the real entry point,
# or, under a mutation proof, a copy beside the mirror (scout.sh finds its lib
# at `<its own dir>/lib/scout`), so the end-to-end cases see the mutant too.
_scout_bin() {
  if [ "$LIBROOT" = "$REPO_ROOT/scripts/lib" ]; then
    printf '%s\n' "$REPO_ROOT/scripts/scout.sh"; return 0
  fi
  if [ ! -f "$LIBROOT/sb/scout.sh" ]; then
    mkdir -p "$LIBROOT/sb/lib" && cp "$REPO_ROOT/scripts/scout.sh" "$LIBROOT/sb/" \
      && cp -R "$LIBROOT/scout" "$LIBROOT/sb/lib/" || return 1
  fi
  printf '%s\n' "$LIBROOT/sb/scout.sh"
}

# _adoptee DIR [ignore-line...] — a real git repo with its own history.
_adoptee() {
  local d="$1"; shift
  mkdir -p "$d" && ( cd "$d" \
    && git init -q . \
    && git config user.email t@example.com && git config user.name T \
    && printf 'their code\n' > README.md \
    && { [ "$#" -eq 0 ] || printf '%s\n' "$@" > .gitignore; } \
    && git add -A && git commit -q -m 'chore: their history' ) >/dev/null 2>&1 || return 1
}
_hash() { ( cd "$1" && find . -type f -exec cksum {} \; 2>/dev/null | LC_ALL=C sort | cksum ); }

# The dogfood shape: an ordinary `.gitignore` whose SECOND line is `lib/`.
A_DOG="$WORK/ad/dogfood";   _adoptee "$A_DOG"   'node_modules/' 'lib/'
A_GRP="$WORK/ad/grouping";  _adoptee "$A_GRP"   'lib/' '*.md'
A_TOP="$WORK/ad/top";       _adoptee "$A_TOP"   '.claude/'
A_OUT="$WORK/ad/outside";   _adoptee "$A_OUT"
mkdir -p "$WORK/elsewhere" && printf '.claude/\n' > "$WORK/elsewhere/ignore"
( cd "$A_OUT" && git config core.excludesFile "$WORK/elsewhere/ignore" )
A_EXC="$WORK/ad/exclude";   _adoptee "$A_EXC"
mkdir -p "$A_EXC/.git/info" && printf '# local\n.claude/\n' > "$A_EXC/.git/info/exclude"
A_SUB="$WORK/ad/nested";    _adoptee "$A_SUB"
( cd "$A_SUB" && mkdir -p sub && printf 'lib/\n' > sub/.gitignore && git add sub/.gitignore \
  && git commit -q -m 'chore: nested rule' ) >/dev/null 2>&1
# A nested rule ANCHORING CANNOT HELP: `scripts/.gitignore` says `lib/`, and the
# adoption needs `scripts/lib/…` — directly under the rule's own directory, so
# `/lib/` there still matches (review R-BL311C-2).
A_NST="$WORK/ad/nested-noanchor"; _adoptee "$A_NST"
( cd "$A_NST" && mkdir -p scripts && printf 'lib/\n' > scripts/.gitignore && git add scripts/.gitignore \
  && git commit -q -m 'chore: nested rule' ) >/dev/null 2>&1
# Personal excludes from the two places git reads one (review R-BL311C-4): a
# GLOBAL core.excludesFile, and git's XDG default when no config sets one. Each
# case points git at its own config, so neither leaks into the other fixtures.
A_GLB="$WORK/ad/global";    _adoptee "$A_GLB"
printf '[core]\n\texcludesFile = %s\n' "$WORK/elsewhere/ignore" > "$WORK/global.gitconfig"
# The way people actually write it: `~/` (review R-BL311C2-1). git expands it
# against HOME, which is `$WORK/home` here, and so must the comparison.
printf '[core]\n\texcludesFile = ~/.gitignore_global\n' > "$WORK/tilde.gitconfig"
printf '.claude/\n' > "$HOME/.gitignore_global"
# A SYSTEM core.excludesFile (review R-BL311C2-2), through GIT_CONFIG_SYSTEM.
printf '[core]\n\texcludesFile = %s\n' "$WORK/elsewhere/ignore" > "$WORK/system.gitconfig"
A_XDG="$WORK/ad/xdg";       _adoptee "$A_XDG"
mkdir -p "$WORK/xdg-default/git" && printf '.claude/\n' > "$WORK/xdg-default/git/ignore"
# A TRACKED file under the ignored directory: the decision asks about the
# DIRECTORY for a tracked path, and the rule named must be the one it asked.
A_TRK="$WORK/ad/tracked";   _adoptee "$A_TRK"   'lib/'
( cd "$A_TRK" && mkdir -p scripts/lib && printf 'old\n' > scripts/lib/old.sh \
  && git add -f scripts/lib/old.sh && git commit -q -m 'chore: tracked under lib' ) >/dev/null 2>&1

DOG_PLANNED='scripts/lib/adopt/adopt-core.sh scripts/lib/helpers-core.sh scripts/lib/scout/scout-core.sh .claude/manifest.json'

# _prewrite DIR ERRFILE PLANNED... -> rc. `_adopt_write_phase` is stubbed to
# record PLANNED, as in tests/test-bl225-prewrite-preflight.sh: these cases are
# about the DECISION's message, and I9 below runs the real driver.
_prewrite() {
  local d="$1" ef="$2"; shift 2
  ( set +e
    ADOPT_PROJECT_NAME=t
    . "$LIBROOT/adopt/adopt-core.sh"  >/dev/null 2>&1
    . "$LIBROOT/adopt/adopt-state.sh" >/dev/null 2>&1
    ADOPT_WORK="$(mktemp -d "$WORK/aw.XXXXXX")"
    adopt_ledger_init "$ADOPT_WORK/written" >/dev/null 2>&1
    _planned="$*"
    _adopt_write_phase() {
      local p=""
      for p in $_planned; do adopt_record_write "$p"; done
      return 0
    }
    adopt_prewrite_preflight "$d" "" >/dev/null 2>"$ef"; echo $? )
}

# A `git` that answers everything for real EXCEPT `check-ignore -v`: FAIL makes
# that exit 128 with nothing on stdout, NEG makes it name a NEGATED pattern —
# git's own answer for a path a `!` rule re-includes, which contradicts the
# decision. Either way the rule cannot be named, and the block must fall back.
# ODD names a real-looking rule in an absolute file that is neither
# core.excludesFile nor git's default — the block must name it plainly.
STUBG="$WORK/stub-git"; mkdir -p "$STUBG"
cat > "$STUBG/git" <<EOF
#!/bin/bash
verbose=0
for a in "\$@"; do [ "\$a" = -v ] && verbose=1; done
case " \$* " in
  *" check-ignore "*)
    [ "\$verbose" -eq 1 ] || exec "$REAL_GIT" "\$@"
    if [ "\${STUB_GIT_MODE:-}" = NEG ]; then
      IFS= read -r -d '' p
      printf '%s\0%s\0%s\0%s\0' .gitignore 2 '!lib/' "\$p"
      exit 0
    fi
    if [ "\${STUB_GIT_MODE:-}" = ODD ]; then
      IFS= read -r -d '' p
      printf '%s\0%s\0%s\0%s\0' /nowhere/excludes 1 '.claude/' "\$p"
      exit 0
    fi
    cat >/dev/null; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUBG/git"

# ════════════════════════════════════════════════════════════════════════════
# S — row 4: the test command goes through the project's package manager
# ════════════════════════════════════════════════════════════════════════════

case_S_python() {
  local r=""
  r="$(_tc py-uv)"
  chk "S1 uv: a uv project's pytest runs as 'uv run --frozen pytest'" "$(_val "$r")" "uv run --frozen pytest"
  has "S1 uv: the evidence keeps the arm that found pytest" "$(_src "$r")" "pyproject.toml [tool.pytest]"
  has "S1 uv: and says uv.lock is why it goes through uv" "$(_src "$r")" "run through uv because uv.lock is present"
  # The value is also the interview's prefill for the project's own test
  # command, so the evidence says the flag is Scout's (review R-BL311C2-5).
  has "S1 uv: and says --frozen is Scout's own, and the everyday command" "$(_src "$r")" \
    "Scout adds \`--frozen\` so its own run never rewrites uv.lock, and day to day the command is \`uv run pytest\`"
  r="$(_tc py-poetry)"
  chk "S2 poetry: 'poetry run pytest'" "$(_val "$r")" "poetry run pytest"
  has "S2 poetry: evidence names poetry.lock" "$(_src "$r")" "run through poetry because poetry.lock is present"
  hasnt "S2 poetry: no flag of Scout's, so no note about one" "$(_src "$r")" "Scout adds"
  r="$(_tc py-pdm)"
  chk "S3 pdm: 'pdm run pytest'" "$(_val "$r")" "pdm run pytest"
  has "S3 pdm: evidence names pdm.lock" "$(_src "$r")" "run through pdm because pdm.lock is present"
  r="$(_tc py-pipenv)"
  chk "S4 pipenv: 'pipenv run pytest'" "$(_val "$r")" "pipenv run pytest"
  has "S4 pipenv: evidence names the LOCKFILE, ahead of the Pipfile that generated it" "$(_src "$r")" "because Pipfile.lock is present"
  r="$(_tc py-pipfile)"
  chk "S4 pipenv: a Pipfile alone is pipenv too" "$(_val "$r")" "pipenv run pytest"
  # The evidence names the file that EXISTS, not the first row naming pipenv
  # (review R-BL311C-3: `Pipfile.lock` was named for a project without one).
  has "S4 pipenv: a Pipfile alone: the evidence names Pipfile" "$(_src "$r")" "because Pipfile is present"
  hasnt "S4 pipenv: a Pipfile alone: and never a Pipfile.lock it does not have" "$(_src "$r")" "Pipfile.lock"
  r="$(_tc py-pip)"
  chk "S5 pip: a requirements.txt project keeps bare 'pytest'" "$(_val "$r")" "pytest"
  chk "S5 pip: and its evidence is unchanged" "$(_src "$r")" "pytest.ini present"
  r="$(_tc py-none)"
  chk "S6 none: no manager in evidence keeps bare 'pytest'" "$(_val "$r")" "pytest"
  r="$(_tc py-make)"
  chk "S6 make: a declared Makefile target still wins, unprefixed" "$(_val "$r")" "make test"
}

case_S_node() {
  local r=""
  r="$(_tc js-pnpm)"
  chk "N1 pnpm: scripts.test runs as 'pnpm --config.verify-deps-before-run=false test'" "$(_val "$r")" "pnpm --config.verify-deps-before-run=false test"
  has "N1 pnpm: the evidence keeps the script body" "$(_src "$r")" 'package.json scripts.test (`vitest run`)'
  has "N1 pnpm: and says pnpm-lock.yaml is why" "$(_src "$r")" "run through pnpm because pnpm-lock.yaml is present"
  has "N1 pnpm: and says the flag is Scout's own, and the everyday command" "$(_src "$r")" \
    "Scout adds \`--config.verify-deps-before-run=false\` so its own run never installs or rewrites pnpm-lock.yaml, and day to day the command is \`pnpm test\`"
  r="$(_tc js-yarn)"
  chk "N2 yarn: 'yarn test'" "$(_val "$r")" "yarn test"
  hasnt "N2 yarn: no flag of Scout's, so no note about one" "$(_src "$r")" "Scout adds"
  r="$(_tc js-npm)"
  chk "N3 npm: 'npm test'" "$(_val "$r")" "npm test"
  has "N3 npm: evidence names package-lock.json" "$(_src "$r")" "because package-lock.json is present"
  # `bun test` is Bun's OWN test runner and never reads scripts.test; the
  # script runs with `bun run test` (bun.com/docs, via context7).
  r="$(_tc js-bun)"
  chk "N4 bun: 'bun run test', not 'bun test'" "$(_val "$r")" "bun run test"
  r="$(_tc js-bunb)"
  chk "N4 bun: the pre-1.2 bun.lockb too" "$(_val "$r")" "bun run test"
  has "N4 bun: bun.lockb alone: the evidence names bun.lockb" "$(_src "$r")" "because bun.lockb is present"
  hasnt "N4 bun: bun.lockb alone: and never a bun.lock it does not have" "$(_src "$r")" "because bun.lock is present"
  r="$(_tc js-deno)"
  chk "N5 deno: 'deno task test' (deno task falls back to package.json scripts)" "$(_val "$r")" "deno task test"
  r="$(_tc js-none)"
  chk "N6 no lockfile: 'npm test'" "$(_val "$r")" "npm test"
  has "N6 no lockfile: and the evidence says no lockfile named a manager" "$(_src "$r")" "because no lockfile names a package manager"
  r="$(_tc js-mixed)"
  chk "N7 a Python manager never prefixes a Node script" "$(_val "$r")" "npm test"
}

case_S_precedence() {
  local r=""
  r="$(_tc pp-all)"
  chk "P1 uv.lock + poetry.lock + Pipfile: uv wins" "$(_val "$r")" "uv run --frozen pytest"
  has "P1 the evidence names the losers" "$(_src "$r")" "also present: poetry.lock, Pipfile"
  has "P1 and the order Scout used" "$(_src "$r")" "Scout prefers uv, then poetry, then pdm, then pipenv"
  has "P1 and asks the operator to confirm" "$(_src "$r")" "confirm which one this project uses"
  r="$(_tc pp-poe-pdm)"
  chk "P2 poetry.lock + pdm.lock: poetry wins" "$(_val "$r")" "poetry run pytest"
  r="$(_tc pp-pdm-pipe)"
  chk "P3 pdm.lock + Pipfile.lock: pdm wins" "$(_val "$r")" "pdm run pytest"
  r="$(_tc jp-pn-yarn)"
  chk "P4 pnpm-lock.yaml + yarn.lock: pnpm wins" "$(_val "$r")" "pnpm --config.verify-deps-before-run=false test"
  r="$(_tc jp-yarn-npm)"
  chk "P5 yarn.lock + package-lock.json: yarn wins" "$(_val "$r")" "yarn test"
  r="$(_tc jp-npm-bun)"
  chk "P6 package-lock.json + bun.lock: npm wins" "$(_val "$r")" "npm test"
  r="$(_tc jp-bun-deno)"
  chk "P7 bun.lock + deno.lock: bun wins" "$(_val "$r")" "bun run test"
}

# S8/S9 — THE DOGFOOD DEFECT, END TO END. Stubs stand in for uv and pnpm the
# way the real tools behave — the project's environment (`.venv/bin`,
# `node_modules/.bin`) is on PATH only through them — so a bare `pytest` or
# `vitest run` exits 127 exactly as it did on k-pdf. Each stub skips the
# tool's own leading flags, as the tool does (`uv run --frozen pytest`), and
# logs them, so the flags Scout passes are asserted end to end too. S10 reads
# the markdown report's opening line on the same run.
case_S_e2e() {
  local st="$WORK/stubs" lg="$WORK/stub.log" d="" out="" sb=""
  sb="$(_scout_bin)" || { bad "S8 setup — no scout.sh for this lib"; return; }
  mkdir -p "$st"
  cat > "$st/uv" <<'EOF'
#!/bin/sh
printf 'uv %s\n' "$*" >> "$STUB_LOG"
[ "$1" = run ] || exit 2
shift
while [ "$#" -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
PATH="$PWD/.venv/bin:$PATH" exec "$@"
EOF
  cat > "$st/pnpm" <<'EOF'
#!/bin/sh
printf 'pnpm %s\n' "$*" >> "$STUB_LOG"
while [ "$#" -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
[ "$1" = test ] || exit 2
PATH="$PWD/node_modules/.bin:$PATH" exec sh -c "$(jq -r '.scripts.test' package.json)"
EOF
  chmod +x "$st/uv" "$st/pnpm"

  d="$WORK/e2e/uv"; mkdir -p "$d/.venv/bin" "$d/tests"
  printf '[project]\nname = "k"\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > "$d/pyproject.toml"
  printf 'version = 1\n' > "$d/uv.lock"
  printf 'def test_x():\n    pass\n' > "$d/tests/test_x.py"
  printf '#!/bin/sh\necho "pytest (the .venv one) ran" >> "$STUB_LOG"\nexit 0\n' > "$d/.venv/bin/pytest"
  chmod +x "$d/.venv/bin/pytest"
  : > "$lg"
  out="$(STUB_LOG="$lg" PATH="$st:$PATH" bash "$sb" --root "$d" --run-tests </dev/null 2>/dev/null)"
  chk "S8 uv project under --run-tests: the suite that passes is reported as passing (exitCode 0, not 127)" \
    "$(printf '%s' "$out" | jq -r '.testsBaseline.exitCode')" "0"
  has "S8 and it really went through uv, frozen" "$(cat "$lg")" "uv run --frozen pytest"
  has "S8 and uv ran the project's own pytest" "$(cat "$lg")" "pytest (the .venv one) ran"
  chk "S8 the JSON contract keeps its shape: stack.testCommand is {source, value}" \
    "$(printf '%s' "$out" | jq -c '.stack.testCommand | keys')" '["source","value"]'
  chk "S8 and testsBaseline.testCommand is the same object" \
    "$(printf '%s' "$out" | jq -c '.testsBaseline.testCommand == .stack.testCommand')" "true"
  has "S8 and the interview's prefill row carries why --frozen is there" \
    "$(printf '%s' "$out" | jq -r '.intakePrefill.sections[] | select(.id == "11_5") | .source')" \
    "Scout adds \`--frozen\` so its own run never rewrites uv.lock"
  out="$(STUB_LOG="$lg" PATH="$st:$PATH" bash "$sb" --root "$d" --run-tests --markdown </dev/null 2>/dev/null)"
  has "S10 under --run-tests the report says the project's own command ran there" "$out" \
    "Scout itself wrote nothing into it, but \`--run-tests\` ran the project's own test command, "
  has "S10 and names that command in the same sentence" "$out" \
    "ran the project's own test command, \`uv run --frozen pytest\`, there once"
  hasnt "S10 and points at no testsBaseline heading the report does not have" "$out" "named under testsBaseline below"
  hasnt "S10 and no longer promises that Scout changed nothing" "$out" "Scout changed nothing"
  out="$(PATH="$st:$PATH" bash "$sb" --root "$d" --markdown </dev/null 2>/dev/null)"
  has "S10 without --run-tests the report still says Scout changed nothing" "$out" "Scout changed nothing — it only read."

  d="$WORK/e2e/pnpm"; mkdir -p "$d/node_modules/.bin" "$d/src"
  printf '{ "name": "w", "scripts": { "test": "vitest run" } }\n' > "$d/package.json"
  printf 'lockfileVersion: 9\n' > "$d/pnpm-lock.yaml"
  printf 'export const v = 1;\n' > "$d/src/mod.ts"
  printf '#!/bin/sh\necho "vitest (node_modules) ran" >> "$STUB_LOG"\nexit 0\n' > "$d/node_modules/.bin/vitest"
  chmod +x "$d/node_modules/.bin/vitest"
  : > "$lg"
  out="$(STUB_LOG="$lg" PATH="$st:$PATH" bash "$sb" --root "$d" --run-tests </dev/null 2>/dev/null)"
  chk "S9 pnpm project under --run-tests: exitCode 0, not 127 — the Node twin of the same defect" \
    "$(printf '%s' "$out" | jq -r '.testsBaseline.exitCode')" "0"
  has "S9 and it really went through pnpm, with its install check off" "$(cat "$lg")" "pnpm --config.verify-deps-before-run=false test"
  has "S9 and pnpm ran the project's own vitest" "$(cat "$lg")" "vitest (node_modules) ran"
  has "S9 and the interview's prefill row carries why the flag is there" \
    "$(printf '%s' "$out" | jq -r '.intakePrefill.sections[] | select(.id == "11_5") | .source')" \
    "day to day the command is \`pnpm test\`"
}

# U1 — REAL uv, REAL lockfile (review R-BL311C-1). `uv run` locks before it
# runs, so Scout's `--run-tests` rewrote a committed uv.lock that was behind its
# pyproject.toml (measured, uv 0.11.3: ` M uv.lock`). A stub cannot show that —
# only uv can — so this case runs uv itself, offline and with no Python
# download, on exactly that shape, and requires the lock byte-identical and no
# tracked change. A `pytest` stub on PATH stands in for the tool (uv puts
# `.venv/bin` first and the rest of PATH after), so the run really completes
# and the case is not vacuous. SKIPS where uv is absent: the CI runner image
# does not ship it, and S1 still pins `--frozen` in the command there.
case_U_realuv() {
  local d="" sb="" out="" lg=""
  if ! command -v uv >/dev/null 2>&1; then
    skip_ "U1 real uv: uv is not on PATH (S1 still pins the command)"; return 0
  fi
  sb="$(_scout_bin)" || { bad "U1 setup — no scout.sh for this lib"; return; }
  d="$(mktemp -d "$WORK/uv.XXXXXX")" && lg="$d.log" && : > "$lg" && mkdir -p "$d/p/tests" "$d/bin" \
    || { bad "U1 setup — could not make the fixture"; return; }
  printf '#!/bin/sh\necho "pytest ran" >> "%s"\nexit 0\n' "$lg" > "$d/bin/pytest" && chmod +x "$d/bin/pytest"
  printf '[project]\nname = "k"\nversion = "0.1.0"\nrequires-python = ">=3.8"\ndependencies = []\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' \
    > "$d/p/pyproject.toml"
  printf 'def test_x():\n    pass\n' > "$d/p/tests/test_x.py"
  if ! ( export UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never UV_CACHE_DIR="$WORK/uv-cache"
         cd "$d/p" && git init -q . && git config user.email t@example.com && git config user.name T \
         && uv lock -q && git add pyproject.toml uv.lock tests/test_x.py && git commit -q -m 'chore: locked' \
         && sed -e 's/^version = "0.1.0"$/version = "0.2.0"/' pyproject.toml > pyproject.toml.new \
         && mv pyproject.toml.new pyproject.toml && git commit -q -am 'chore: bump without re-locking' ) >/dev/null 2>&1; then
    bad "U1 setup — uv could not lock the fixture offline"; return
  fi
  ( export UV_OFFLINE=1 UV_CACHE_DIR="$WORK/uv-cache"; cd "$d/p" && uv lock --check ) >/dev/null 2>&1 \
    && { bad "U1 control — the committed uv.lock is not stale, so this case would prove nothing"; return; }
  ok "U1 control: the committed uv.lock is stale (uv lock --check fails)"
  cp "$d/p/uv.lock" "$d/uv.lock.before"
  out="$( export UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never UV_CACHE_DIR="$WORK/uv-cache"
         PATH="$d/bin:$PATH" bash "$sb" --root "$d/p" --run-tests </dev/null 2>/dev/null )"
  chk "U1 real uv: the command ran and passed through uv" "$(printf '%s' "$out" | jq -r '.testsBaseline.exitCode')" "0"
  has "U1 and uv ran pytest (the stub on PATH)" "$(cat "$lg")" "pytest ran"
  chk "U1 real uv: a stale tracked uv.lock is byte-identical after --run-tests" \
    "$(cmp -s "$d/p/uv.lock" "$d/uv.lock.before" && echo identical || echo REWRITTEN)" "identical"
  chk "U1 and git sees no tracked change" "$(cd "$d/p" && git status --porcelain --untracked-files=no)" ""
}

# ════════════════════════════════════════════════════════════════════════════
# I — row 5: the block names the rule, the file and the line
# ════════════════════════════════════════════════════════════════════════════

case_I_dogfood() {
  local ef="$WORK/err.dog" rc="" e="" h=""
  h="$(_hash "$A_DOG")"
  rc="$(_prewrite "$A_DOG" "$ef" $DOG_PLANNED)"; e="$(cat "$ef")"
  chk "I1 the dogfood shape is still blocked" "$([ "${rc:-0}" -ne 0 ] && echo yes || echo no)" "yes"
  has "I1 and still lists the refused paths" "$e" "scripts/lib/helpers-core.sh"
  has "I1 and still says nothing was written" "$e" "NOTHING WAS WRITTEN"
  has "I1 names the file, the line and the pattern" "$e" '.gitignore, line 2: `lib/` refuses 3 of them'
  chk "I1 grouped: one rule refusing three paths is printed ONCE" "$(nlines "$e" 'line 2: `lib/`')" "1"
  has "I1 shows where the rule matched" "$e" "here it matched scripts/lib"
  has "I1 suggests the one-line fix" "$e" 'change line 2 of .gitignore to `/lib/`'
  has "I1 and leaves the call to the operator" "$e" "Whether it was is your judgement"
  has "I1 and never edits their file" "$e" "Adoption never edits your ignore files"
  chk "I1 the project is byte-identical" "$(_hash "$A_DOG")" "$h"
}

case_I_grouping() {
  local ef="$WORK/err.grp" e=""
  _prewrite "$A_GRP" "$ef" scripts/lib/a.sh scripts/lib/b.sh PROJECT_INTAKE.md docs/x.md >/dev/null
  e="$(cat "$ef")"
  chk "I2 two rules: the directory rule once, with its count" "$(nlines "$e" '.gitignore, line 1: `lib/` refuses 2 of them')" "1"
  chk "I2 two rules: the glob rule once, with its count" "$(nlines "$e" '.gitignore, line 2: `*.md` refuses 2 of them')" "1"
  hasnt "I2 a glob is not offered an anchor it cannot use" "$e" 'to `/*.md`'
  has "I2 a glob gets the plain advice" "$e" "Narrow or remove that line"
}

# I3 — WHO ELSE READS AN OUTSIDE RULE depends on which config named the file
# (review R-BL311C-4): a repository-local core.excludesFile is read by this
# repository alone, a global one by every repository of the user's, and git's
# XDG default only where no config sets core.excludesFile. A file that is
# neither is named plainly (the ODD stub), never with a claim about readers.
case_I_sources() {
  local ef="$WORK/err.src" e=""
  _prewrite "$A_OUT" "$ef" .claude/manifest.json >/dev/null; e="$(cat "$ef")"
  has "I3 a core.excludesFile rule is named by its path" "$e" "$WORK/elsewhere/ignore"
  has "I3 local: OUTSIDE this repository, and read by this repository alone" "$e" \
    "(outside this repository: core.excludesFile in this repository's own git config names it, so only this repository reads it)"
  hasnt "I3 local: never 'every repository' for a repository-local setting" "$e" "every repository"
  GIT_CONFIG_GLOBAL="$WORK/global.gitconfig" _prewrite "$A_GLB" "$ef" .claude/manifest.json >/dev/null; e="$(cat "$ef")"
  has "I3b global: named as the global setting every repository of yours reads" "$e" \
    "$WORK/elsewhere/ignore (outside this repository: core.excludesFile in your global git config names it, so every repository of yours reads it unless one sets its own), line 1"
  GIT_CONFIG_GLOBAL="$WORK/tilde.gitconfig" _prewrite "$A_GLB" "$ef" .claude/manifest.json >/dev/null; e="$(cat "$ef")"
  has "I3e global, written as ~/: still named as the global setting, by its expanded path" "$e" \
    "$HOME/.gitignore_global (outside this repository: core.excludesFile in your global git config names it, so every repository of yours reads it unless one sets its own), line 1"
  # GIT_CONFIG_NOSYSTEM=0, not unset: a run under GIT_CONFIG_NOSYSTEM=1 (the
  # runner-git recipe in CLAUDE.md) would otherwise skip GIT_CONFIG_SYSTEM.
  GIT_CONFIG_NOSYSTEM=0 GIT_CONFIG_SYSTEM="$WORK/system.gitconfig" GIT_CONFIG_GLOBAL=/dev/null \
    _prewrite "$A_GLB" "$ef" .claude/manifest.json >/dev/null; e="$(cat "$ef")"
  has "I3f system: named as the machine's system setting every repository on it reads" "$e" \
    "$WORK/elsewhere/ignore (outside this repository: core.excludesFile in this machine's system git config names it, so every repository on this machine reads it unless one sets its own), line 1"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$WORK/xdg-default" \
    _prewrite "$A_XDG" "$ef" .claude/manifest.json >/dev/null; e="$(cat "$ef")"
  has "I3c XDG default: named as git's default, not as core.excludesFile" "$e" \
    "$WORK/xdg-default/git/ignore (outside this repository: git's default personal excludes file, read because no git config sets core.excludesFile"
  hasnt "I3c XDG default: and never credited to a core.excludesFile setting" "$e" "core.excludesFile in"
  STUB_GIT_MODE=ODD PATH="$STUBG:$PATH" _prewrite "$A_TOP" "$ef" .claude/manifest.json >/dev/null; e="$(cat "$ef")"
  has "I3d a source that is neither is named plainly" "$e" \
    "/nowhere/excludes (outside this repository: a git excludes file, not part of the project), line 1"
  _prewrite "$A_EXC" "$ef" .claude/manifest.json >/dev/null; e="$(cat "$ef")"
  has "I4 a .git/info/exclude rule is named as this clone's, and uncommitted" "$e" '.git/info/exclude (this clone only, never committed), line 2: `.claude/`'
  _prewrite "$A_SUB" "$ef" sub/pkg/lib/x.sh >/dev/null; e="$(cat "$ef")"
  has "I5 a nested .gitignore is named, and the anchor is relative to it" "$e" 'change line 1 of sub/.gitignore to `/lib/`'
  has "I5 and the match is described relative to sub/, with the real path" "$e" 'not only directly in sub/: here it matched sub/pkg/lib'
  has "I5 and the fix is for sub/lib/, not a top-level lib/" "$e" 'if the rule was meant for sub/lib/ only'
}

# I10 — A NESTED RULE ANCHORING CANNOT HELP (review R-BL311C-2). The paths are
# compared with the rule's own directory stripped; without that strip
# `scripts/lib/x` never starts with `lib`, the block offers `/lib/` — which
# still refuses them — and names `scripts/scripts/lib`.
case_I_nested() {
  local ef="$WORK/err.nst" e=""
  _prewrite "$A_NST" "$ef" scripts/lib/adopt/adopt-core.sh scripts/lib/helpers-core.sh >/dev/null; e="$(cat "$ef")"
  has "I10 the nested rule is named, with its count" "$e" 'scripts/.gitignore, line 1: `lib/` refuses 2 of them'
  has "I10 nested, anchoring cannot help: said so" "$e" "Anchoring it would not help"
  has "I10 and the real directory is named: scripts/lib" "$e" 'sit under scripts/lib, where `/lib/` in scripts/.gitignore still matches'
  hasnt "I10 so no one-line fix is offered" "$e" "One-line fix"
  hasnt "I10 and no doubled path" "$e" "scripts/scripts/lib"
}

case_I_noanchor() {
  local ef="$WORK/err.top" e=""
  _prewrite "$A_TOP" "$ef" .claude/manifest.json PROJECT_INTAKE.md >/dev/null; e="$(cat "$ef")"
  has "I6 a top-level rule is named" "$e" '.gitignore, line 1: `.claude/` refuses 1 of them'
  has "I6 anchoring it is said NOT to help" "$e" "Anchoring it would not help"
  has "I6 and the top-level directory is named" "$e" 'sit under the top-level .claude, where `/.claude/` in .gitignore still matches'
  hasnt "I6 so no one-line anchor fix is offered" "$e" "One-line fix"
}

case_I_tracked() {
  local ef="$WORK/err.trk" e=""
  _prewrite "$A_TRK" "$ef" scripts/lib/old.sh >/dev/null; e="$(cat "$ef")"
  has "I7 a tracked path under an ignored directory names the directory's rule" "$e" '.gitignore, line 1: `lib/` refuses 1 of them (for example scripts/lib/old.sh)'
}

case_I_failclosed() {
  local ef="$WORK/err.fc" rc="" e="" m=""
  for m in FAIL NEG; do
    rc="$(STUB_GIT_MODE="$m" PATH="$STUBG:$PATH" _prewrite "$A_DOG" "$ef" $DOG_PLANNED)"; e="$(cat "$ef")"
    chk "I8 ($m) git cannot name the rule: STILL blocked" "$([ "${rc:-0}" -ne 0 ] && echo yes || echo no)" "yes"
    has "I8 ($m) and the block is not silent: the paths are there" "$e" "scripts/lib/adopt/adopt-core.sh"
    has "I8 ($m) and it still says nothing was written" "$e" "NOTHING WAS WRITTEN"
    has "I8 ($m) and says git could not name the rule, and how to ask it" "$e" "git could not name the rule that refuses them"
    hasnt "I8 ($m) and names no rule it could not verify" "$e" "refuses 3 of them"
  done
}

# I9 — THE REAL DRIVER on the dogfood shape. The stubbed write phase above
# cannot show that the adoption really plans paths under a `lib/` directory;
# this runs adopt-project.sh with a Scout report and requires the block to
# name the rule. It SKIPS NOTHING silently: no report is a FAIL.
case_I_e2e() {
  local r="$WORK/e2e-adopt" p="" i=0 rc=0 e="" h=""
  p="$r/p"; mkdir -p "$p/src"
  ( cd "$p" && git init -q . && git config user.email e@test.invalid && git config user.name E \
    && printf '{"name":"acme","scripts":{"test":"npm test"}}\n' > package.json \
    && printf '# acme\n' > README.md && printf 'node_modules/\nlib/\n' > .gitignore \
    && git add -A && git commit -q -m 'chore: their history' ) >/dev/null 2>&1
  if ! bash "$REPO_ROOT/scripts/scout.sh" --root "$p" --out "$r/scan" >/dev/null 2>&1 \
     || [ ! -s "$r/scan/scout-report.json" ]; then
    bad "I9 setup — scripts/scout.sh produced no report, so the real driver could not be run"
    return
  fi
  h="$(_hash "$p")"
  { printf '2\nstandard\n'; while [ "$i" -lt 40 ]; do printf '1\n'; i=$((i + 1)); done; } > "$r/answers"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$r/scan/scout-report.json" ) \
    < "$r/answers" >/dev/null 2>"$r/err" || rc=$?
  e="$(cat "$r/err")"
  chk "I9 the real driver reached the pre-write check" "$(nlines "$e" 'your ignore rules refuse')" "1"
  chk "I9 and stopped" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
  has "I9 and named .gitignore line 2, lib/" "$e" '.gitignore, line 2: `lib/` refuses'
  has "I9 and suggested /lib/" "$e" 'change line 2 of .gitignore to `/lib/`'
  chk "I9 and the project is byte-identical" "$(_hash "$p")" "$h"
}

echo "=== S — Scout's test command goes through the package manager (row 4) ==="
case_S_python
case_S_node
case_S_precedence
case_S_e2e
case_U_realuv
echo "=== I — the ignore block names its rule (row 5) ==="
case_I_dogfood
case_I_grouping
case_I_sources
case_I_nested
case_I_noanchor
case_I_tracked
case_I_failclosed
case_I_e2e

# ════════════════════════════════════════════════════════════════════════════
# M — mutation proofs. Each replaces the ONE line ending in its marker, in a
# mirror of scripts/lib, asserts the replacement LANDED by its own text and
# still parses, re-runs only the case that must kill it, and requires the kill
# to come from the NAMED assertion. A mutation that did not apply is a FAILURE,
# never a kill.
# ════════════════════════════════════════════════════════════════════════════
echo "=== M — mutation proofs ==="

_mutate() {   # FILE MARKER REPLACEMENT
  local f="$1" n=""
  MUT_MARK="$2" MUT_REPL="$3" awk '
    { m = ENVIRON["MUT_MARK"]; L = length($0); K = length(m)
      if (L >= K && substr($0, L - K + 1) == m) { print ENVIRON["MUT_REPL"]; n++ } else print }
    END { print n + 0 > "/dev/stderr" }' "$f" > "$f.mut" 2> "$f.n" || return 1
  n="$(cat "$f.n")"; rm -f "$f.n"
  [ "$n" = "1" ] || { echo "sites=$n"; rm -f "$f.mut"; return 1; }
  mv "$f.mut" "$f" || return 1
  grep -qxF -- "$3" "$f" || { echo "replacement not found"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
# _mline FILE MARKER FROM TO — the line of FILE ending in MARKER with its ONE
# occurrence of FROM replaced by TO. Split on FROM, never ${var/pat/rep}
# (CLAUDE.md's `&` trap). Fails unless the line and FROM each occur once.
_mline() {
  local line="" n=""
  line="$(awk -v m="$2" '{ L = length($0); K = length(m); if (L >= K && substr($0, L - K + 1) == m) print }' "$1")"
  n="$(printf '%s\n' "$line" | grep -c .)"; [ "$n" = 1 ] || return 1
  case "$line" in *"$3"*"$3"*) return 1 ;; *"$3"*) ;; *) return 1 ;; esac
  printf '%s%s%s' "${line%%"$3"*}" "$4" "${line#*"$3"}"
}
MUTN=0
mut() {   # LABEL REL-FILE MARKER FROM TO CASE-FN WANT
  local label="$1" rel="$2" marker="$3" from="$4" to="$5" fn="$6" want="$7"
  local m="" repl="" r="" out="" why=""
  MUTN=$((MUTN + 1)); m="$WORK/mut.$MUTN"
  mkdir -p "$m" && cp -Rp "$REPO_ROOT/scripts/lib/scout" "$REPO_ROOT/scripts/lib/adopt" "$m/" \
    || { bad "$label — could not mirror scripts/lib"; return; }
  repl="$(_mline "$m/$rel" "$marker" "$from" "$to")" \
    || { bad "$label — the mutant line could not be built ('$from' not exactly once on the line ending '$marker')"; return; }
  r="$(_mutate "$m/$rel" "$marker" "$repl")" || { bad "$label — the mutation did not apply ($r)"; return; }
  out="$( LIBROOT="$m"; PASS=0; FAIL=0; "$fn" 2>&1 )"
  why="$(printf '%s\n' "$out" | grep '\[FAIL\]' | sed 's/^ *\[FAIL\] //' | tr '\n' ' ')"
  if [ -z "$why" ]; then bad "$label — the mutant SURVIVED $fn"
  elif grep -qF -- "$want" <<<"$why"; then ok "$label — killed by '$want'"
  else bad "$label — killed, but not by '$want': $(printf '%s' "$why" | cut -c1-240)"; fi
  rm -rf "$m"
}

SS=scout/scout-stack.sh; AS=adopt/adopt-state.sh; SS_REPORT=scout/scout-report.sh
mut "M1 uv arm"      "$SS" '# BL-311-SCOUT-RUN-UV'     'cmd="uv run --frozen pytest"' 'cmd="pytest"' case_S_python "S1 uv: a uv project's pytest runs as 'uv run --frozen pytest'"
mut "M2 poetry arm"  "$SS" '# BL-311-SCOUT-RUN-POETRY' 'cmd="poetry run pytest"' 'cmd="pytest"'  case_S_python "S2 poetry: 'poetry run pytest'"
mut "M3 pdm arm"     "$SS" '# BL-311-SCOUT-RUN-PDM'    'cmd="pdm run pytest"'    'cmd="pytest"'  case_S_python "S3 pdm: 'pdm run pytest'"
mut "M4 pipenv arm"  "$SS" '# BL-311-SCOUT-RUN-PIPENV' 'cmd="pipenv run pytest"' 'cmd="pytest"'  case_S_python "S4 pipenv: 'pipenv run pytest'"
mut "M5 pnpm arm"    "$SS" '# BL-311-SCOUT-RUN-PNPM'   'cmd="pnpm --config.verify-deps-before-run=false test"' 'cmd="$body"' case_S_node "N1 pnpm: scripts.test runs as 'pnpm --config.verify-deps-before-run=false test'"
mut "M6 yarn arm"    "$SS" '# BL-311-SCOUT-RUN-YARN'   'cmd="yarn test"'         'cmd="$body"'   case_S_node   "N2 yarn: 'yarn test'"
mut "M7 npm arm"     "$SS" '# BL-311-SCOUT-RUN-NPM'    'cmd="npm test"'          'cmd="$body"'   case_S_node   "N3 npm: 'npm test'"
mut "M8 bun arm"     "$SS" '# BL-311-SCOUT-RUN-BUN'    'cmd="bun run test"'      'cmd="bun test"' case_S_node  "N4 bun: 'bun run test', not 'bun test'"
mut "M9 deno arm"    "$SS" '# BL-311-SCOUT-RUN-DENO'   'cmd="deno task test"'    'cmd="$body"'   case_S_node   "N5 deno: 'deno task test'"
mut "M10 npm default" "$SS" '# BL-311-SCOUT-RUN-NPM-DEFAULT' 'm="npm"'           'm=""'          case_S_node   "N6 no lockfile: 'npm test'"
mut "M11 Python precedence" "$SS" '# BL-311-SCOUT-PY-PRECEDENCE' 'uv poetry pdm pipenv' 'pipenv pdm poetry uv' case_S_precedence "P1 uv.lock + poetry.lock + Pipfile: uv wins"
mut "M12 Node precedence"   "$SS" '# BL-311-SCOUT-NODE-PRECEDENCE' 'pnpm yarn npm bun deno' 'deno bun npm yarn pnpm' case_S_precedence "P4 pnpm-lock.yaml + yarn.lock: pnpm wins"
mut "M13 the evidence names its file" "$SS" '# BL-311-SCOUT-RUN-WHY' ' because ' ' ' case_S_python "S1 uv: and says uv.lock is why it goes through uv"
mut "M14 the rule text reaches the block"   "$AS" '# BL-225-PREWRITE-REFUSE' '$ignored$_why"' '$ignored"' case_I_dogfood "I1 names the file, the line and the pattern"
mut "M15 grouped by rule, not by path"      "$AS" '# BL-311-IGNORE-RULE-GROUP' 'FS $3' 'FS $3 FS $4' case_I_dogfood "I1 grouped: one rule refusing three paths is printed ONCE"
mut "M16 an unknown outside source is named plainly" "$AS" '# BL-311-IGNORE-RULE-OUTSIDE' 'where = s " (outside' 'where = s; x = s " (outside' case_I_sources "I3d a source that is neither is named plainly"
mut "M17 info/exclude named"                "$AS" '# BL-311-IGNORE-RULE-EXCLUDE' 'where = s " (this' 'where = s; x = s " (this' case_I_sources "I4 a .git/info/exclude rule is named"
mut "M18 the anchor fix"                    "$AS" '# BL-311-IGNORE-RULE-ANCHOR' '`/%s`' '`%s`' case_I_dogfood "I1 suggests the one-line fix"
mut "M19 anchoring said not to help"        "$AS" '# BL-311-IGNORE-RULE-NO-ANCHOR' 'if (!helps)' 'if (0)' case_I_noanchor "I6 anchoring it is said NOT to help"
mut "M20 fail-closed: -v failing is not silence" "$AS" '# BL-311-IGNORE-RULE-EXPLAIN' '|| _why=""' '|| return 1' case_I_failclosed "I8 (FAIL) and the block is not silent: the paths are there"
mut "M21 fail-closed: the fallback says so" "$AS" '# BL-311-IGNORE-RULE-FALLBACK' '_why="' '_why=""; : "' case_I_failclosed "I8 (FAIL) and says git could not name the rule"
mut "M22 a negated answer is not a rule"    "$AS" '# BL-311-IGNORE-RULE-NEGATED' 'return 1' ':' case_I_failclosed "I8 (NEG) and says git could not name the rule"
# Review round 1 (R-BL311C-1..4).
mut "M23 a nested rule's own directory is stripped" "$AS" '# BL-311-IGNORE-RULE-BASE-STRIP' \
  'if (base != "" && index(q, base) == 1) q = substr(q, length(base) + 1)' 'q = q' case_I_nested "I10 nested, anchoring cannot help: said so"
mut "M24 the evidence names a file that exists" "$SS" '# BL-311-SCOUT-RUNNER-FILE' '[ -e "$root/$f" ]' '[ -n "$f" ]' case_S_python "S4 pipenv: a Pipfile alone: the evidence names Pipfile"
if command -v uv >/dev/null 2>&1; then
  mut "M25 uv runs --frozen (real uv)" "$SS" '# BL-311-SCOUT-RUN-UV' 'uv run --frozen pytest' 'uv run pytest' case_U_realuv "U1 real uv: a stale tracked uv.lock is byte-identical after --run-tests"
else
  skip_ "M25 uv runs --frozen (real uv): uv is not on PATH — M1 and S1 still pin the command"
fi
mut "M26 pnpm's install check is off" "$SS" '# BL-311-SCOUT-RUN-PNPM' 'pnpm --config.verify-deps-before-run=false test' 'pnpm test' case_S_node "N1 pnpm: scripts.test runs as"
mut "M27 the configured excludes file is recognised" "$AS" '# BL-311-IGNORE-RULE-XSOURCE' 'if (s == ENVIRON["XPATH"])' 'if (0)' case_I_sources "I3 local: OUTSIDE this repository, and read by this repository alone"
mut "M28 a local core.excludesFile is this repository's alone" "$AS" '# BL-311-IGNORE-RULE-XSCOPE' 'local|worktree)' 'nolocal)' case_I_sources "I3 local: OUTSIDE this repository, and read by this repository alone"
mut "M29 git's default honours XDG_CONFIG_HOME" "$AS" '# BL-311-IGNORE-RULE-XDG' '${XDG_CONFIG_HOME:-${HOME:-}/.config}' '${HOME:-}/.config' case_I_sources "I3c XDG default: named as git's default"
mut "M30 the report stops promising 'changed nothing' after --run-tests" "$SS_REPORT" '# BL-311-SCOUT-REPORT-RAN' '= "1"' '= "x"' case_S_e2e "S10 under --run-tests the report says the project's own command ran there"
# Review round 2 (R-BL311C2-1..5).
mut "M31 a ~/ core.excludesFile is expanded before it is compared" "$AS" '# BL-311-IGNORE-RULE-XPATH-EXPAND' ' --type=path' '' case_I_sources "I3e global, written as ~/"
mut "M32 a system core.excludesFile is every repository's on the machine" "$AS" '# BL-311-IGNORE-RULE-XSCOPE-SYSTEM' 'system)' 'nosystem)' case_I_sources "I3f system: named as the machine's system setting"
mut "M33 the --run-tests opening line names the command" "$SS_REPORT" '# BL-311-SCOUT-REPORT-RAN-CMD' '"$(cut -f1 < "$work/testcmd")"' '""' case_S_e2e "S10 and names that command in the same sentence"
mut "M34 uv's evidence says --frozen is Scout's" "$SS" '# BL-311-SCOUT-FLAG-WHY-UV' 'if [ "$m" = "uv" ]' 'if false' case_S_python "S1 uv: and says --frozen is Scout's own"
mut "M35 pnpm's evidence says its flag is Scout's" "$SS" '# BL-311-SCOUT-FLAG-WHY-PNPM' 'if [ "$m" = "pnpm" ]' 'if false' case_S_node "N1 pnpm: and says the flag is Scout's own"

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] && exit 0
exit 1

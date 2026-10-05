#!/usr/bin/env bash
# tests/test-bl318-g1-test-command.sh — `## BL-318:` G1.
#
# THE DEFECT (dogfood run 2, finding 31). Adoption showed the operator
# `uv run --frozen pytest` as the project's test command, the operator kept it,
# and adoption never wrote `.claude/test-command`. So the commit-time
# project-test check (`## BL-125:`) fell back to its own detection — a bare
# `pytest`, which cannot see uv's `.venv` — printed
# `sh: pytest: command not found`, said PROJECT TESTS NOT ENFORCED, and let the
# commit through over a suite that passes 1075/0.
#
# THE FIX, two halves:
#   - adoption writes `.claude/test-command` when — and only when — the
#     operator KEPT the command the scan offered, verbatim; a changed answer is
#     never written (review round 1's R-1: prose was written and run); a file
#     the project already has is kept, and the run says what it runs
#     (`# BL-318-TESTCMD-*`, `adopt_write_test_command`);
#   - the hook's own fallback runs pytest through the project's uv, poetry, pdm
#     or pipenv when one is in evidence, after `<runner> python -c 'import
#     pytest'` succeeds there (`# BL-318-PYTEST-*`), so a project with no
#     file — every adoptee adopted before this fix, and a greenfield uv
#     project — gets a check that runs, one whose pytest is absent is not
#     enforced (loudly) rather than blocked as a failed suite, and one whose
#     suite the commit broke still blocks;
#   - nothing is written when Scout found no command (the interview offers
#     "(none detected)") or when its offer is npm's placeholder script.
#
# CASES
#   H  the hook's fallback: a bare repo, the emitted hook, stub runners on PATH
#   U  the writer, driven through the real interview function
#      (`adopt_confirm_scanned`), so the answer it judges is the one the
#      interview recorded — over REAL Scout reports where the shape matters
#      (no test command; npm's placeholder)
#   A  the real driver: a uv adoptee gets the file, committed; an adoptee whose
#      scan offer differs from the hook's fallback proves the FILE is what runs;
#      a file the adoptee already has is kept; an adoptee Scout finds no test
#      command in gets no file, and its commit runs the hook's own detection
#   E  a commit in the uv adoptee runs the written command
#   M  mutants: each rewrites ONE marked line in a mirror of the tree, checks
#      the edit landed by its literal text (and, for the hook, that the emitted
#      hook still parses), and needs a named case to go RED
#
# ~69s local (four real adoptions, plus three more under mutants), so tests.yml
# pins it to the `mcp` leg. No init.sh, not an aggregator -> both lists.
# bash 3.2 safe.
set -uo pipefail
# The adoption driver's MCP step is off in every suite that drives adoption
# (`# BL-311-MCP-SEAM`).
export SOIF_ADOPT_MCP=off
# #422 — pin git's STOCK template (what CI runs with): the H fixtures write
# into .git/hooks/ without creating it.
_stock_tpl="$(git --exec-path 2>/dev/null)/../../share/git-core/templates"
if [ -d "$_stock_tpl/hooks" ]; then export GIT_TEMPLATE_DIR="$_stock_tpl"; fi
unset GITHUB_BASE_REF 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-318 G1 — the commit-time check runs the project's own test command =="
for t in git jq awk; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
NOCLONE="$WORK/no-guardrails-clone"   # never created: no real Guardrails clone runs here
newtmp() { mktemp -d "$WORK/tXXXXXX"; }

# check LABEL CASE [ARGS…] — run a case and report it.
CASE_DETAIL=""
check() {
  local label="$1" fn="$2"; shift 2
  CASE_DETAIL=""
  if "$fn" "$@"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

# ── PATH mirror: semgrep and gitleaks off the PATH (tests/test-bl125-commit-test-exec.sh's
# technique). Every PATH entry holding either scanner is replaced by a symlink
# mirror without them, so the commits below are decided by the BL-125 arm alone.
NOSCAN_PATH=""
build_noscan_path() {
  local mirrors="$WORK/noscan-mirrors" n=0 d np="" entry base
  mkdir -p "$mirrors"
  printf '%s' "$PATH" | tr ':' '\n' > "$mirrors/.pathlist"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -x "$d/semgrep" ] || [ -x "$d/gitleaks" ]; then
      n=$((n + 1))
      mkdir -p "$mirrors/$n"
      for entry in "$d"/*; do
        [ -e "$entry" ] || continue           # bash 3.2 has no nullglob
        base="${entry##*/}"
        [ "$base" = "semgrep" ] && continue
        [ "$base" = "gitleaks" ] && continue
        ln -sf "$entry" "$mirrors/$n/$base" 2>/dev/null || true
      done
      np="${np:+$np:}$mirrors/$n"
    else
      np="${np:+$np:}$d"
    fi
  done < "$mirrors/.pathlist"
  NOSCAN_PATH="$np"
}
build_noscan_path
if PATH="$NOSCAN_PATH" command -v semgrep >/dev/null 2>&1 \
   || PATH="$NOSCAN_PATH" command -v gitleaks >/dev/null 2>&1; then
  echo "FAIL: could not shim the scanners off the PATH — the H and E cases would not be decided by the BL-125 arm"
  echo "Results: 0 passed, 1 failed, 0 skipped"
  exit 1
fi

# mk_stubs DIR RC [PROBE_RC] [VERSION_RC] — uv, poetry, pdm, pipenv, pytest,
# python and make that append their own command line to DIR/calls.
#   - a call whose last argument is `import pytest` (the hook's probe,
#     `<runner> python -c 'import pytest'`, `# BL-318-PYTEST-PROBE-CMD`) exits
#     PROBE_RC (default 0), saying what uv says when pytest is not there;
#   - a call whose last argument is `--version` exits VERSION_RC (default 0) —
#     set it non-zero to model pytest < 9, whose `--version` loads the plugins
#     and so fails on a suite the commit broke (review N3);
#   - every other call exits RC.
# First on PATH, so a real runner on the host never answers for one.
mk_stubs() {
  local d="$1" rc="$2" prc="${3:-0}" vrc="${4:-0}" t=""
  mkdir -p "$d" || return 1
  for t in uv poetry pdm pipenv pytest python make; do
    cat > "$d/$t" <<STUB
#!/bin/sh
echo "$t\${*:+ \$*}" >> "$d/calls"
last=""
for a in "\$@"; do last="\$a"; done
if [ "\$last" = "import pytest" ]; then
  [ $prc -eq 0 ] || echo "ModuleNotFoundError: No module named 'pytest'" >&2
  exit $prc
fi
[ "\$last" = "--version" ] && exit $vrc
exit $rc
STUB
    chmod +x "$d/$t" || return 1
  done
}
# _runs STUBS — the calls that were not the probe, one per line.
_runs() { command grep -v -- ' -c import pytest$' "$1/calls" 2>/dev/null; }

# ════════════════════════════════════════════════════════════════════════════
# H — the hook's fallback, when the project has no .claude/test-command
# ════════════════════════════════════════════════════════════════════════════
# _hproj FW DIR FILE... — a git repo with one commit and the pre-commit hook
# emitted from FW's hook-templates.sh. pyproject.toml carries
# [tool.pytest.ini_options] (the dogfood shape), pytest.ini a [pytest] block;
# every other FILE is a marker file, which is all the hook looks at.
_hproj() {
  local fw="$1" d="$2" f=""; shift 2
  mkdir -p "$d/src" || return 1
  ( cd "$d" && git init -q . && git config user.email t@t.invalid && git config user.name T \
      && printf 'x\n' > seed && git add seed && git commit -q -m "chore: init" ) >/dev/null 2>&1 || return 1
  for f in "$@"; do
    case "$f" in
      pyproject.toml) printf '[project]\nname = "kp"\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > "$d/$f" ;;
      pytest.ini)     printf '[pytest]\ntestpaths = tests\n' > "$d/$f" ;;
      *)              printf 'x\n' > "$d/$f" ;;
    esac
  done
  ( . "$fw/scripts/lib/hook-templates.sh" && soif_write_precommit_hook "$d/.git/hooks/pre-commit" ) >/dev/null 2>&1 || return 1
  chmod +x "$d/.git/hooks/pre-commit"
}
# _commit DIR STUBS SUBJECT → LANDED | REFUSED | SETUP; git's output in DIR/commit.log.
_commit() {
  local d="$1" s="$2" subj="$3"
  ( cd "$d" && mkdir -p src && printf 'y = %s\n' "$RANDOM" >> src/app.py && git add src/app.py ) >/dev/null 2>&1 || { echo SETUP; return; }
  if ( cd "$d" && PATH="$s:$NOSCAN_PATH" git commit -m "$subj" </dev/null ) > "$d/commit.log" 2>&1; then
    echo LANDED
  else
    echo REFUSED
  fi
}
# _hrun FW WANT FILE... — with FILEs in the project and no .claude/test-command,
# the hook runs exactly WANT, and that run failing blocks the commit.
_hrun() {
  local fw="$1" want="$2" d s v calls; shift 2
  d="$(newtmp)/p"; s="$(newtmp)"
  _hproj "$fw" "$d" "$@" || { CASE_DETAIL="fixture"; return 1; }
  mk_stubs "$s" 1 || { CASE_DETAIL="stubs"; return 1; }
  v="$(_commit "$d" "$s" "chore: add app")"
  calls="$(_runs "$s")"
  cp "$s/calls" "$WORK/h.calls" 2>/dev/null || : > "$WORK/h.calls"
  CASE_DETAIL="verdict=$v ran=[$(printf '%s' "$calls" | tr '\n' '|')] want=[$want] hook: $(command grep -E 'BL-125|BLOCKED|WARN' "$d/commit.log" 2>/dev/null | head -3 | tr '\n' ' ')"
  [ "$v" = "REFUSED" ] && [ "$calls" = "$want" ] \
    && command grep -qxF "[BLOCKED] project tests FAILED (exit 1): $want" "$d/commit.log"
}
# Every Python fixture carries pyproject.toml where it can (review R-3): a uv arm
# that keyed on pyproject.toml instead of uv.lock survived when only H1 had one.
case_H1() { _hrun "$1" "uv run --frozen pytest" pyproject.toml uv.lock; }
case_H2() { _hrun "$1" "poetry run pytest" pyproject.toml poetry.lock; }
case_H3() { _hrun "$1" "pdm run pytest" pyproject.toml pdm.lock; }
case_H4() { _hrun "$1" "pipenv run pytest" pytest.ini Pipfile; }
case_H5() {   # bare pytest, and NOTHING else ran — no probe on the bare arm (review N4: `_runs` hid one)
  _hrun "$1" "pytest" pytest.ini requirements.txt || return 1
  local raw; raw="$(cat "$WORK/h.calls" 2>/dev/null)"
  CASE_DETAIL="$CASE_DETAIL raw=[$(printf '%s' "$raw" | tr '\n' '|')]"
  [ "$raw" = "pytest" ]
}
case_H6() { _hrun "$1" "uv run --frozen pytest" pytest.ini uv.lock poetry.lock pdm.lock Pipfile; }
case_H7() { _hrun "$1" "poetry run pytest" pyproject.toml poetry.lock pdm.lock Pipfile; }
case_H8() {   # uv cannot spawn pytest (an extra, a group, not locked): the probe takes the not-enforced arm; the suite is never run as "failed"
  local fw="$1" d s v calls bad=""
  d="$(newtmp)/p"; s="$(newtmp)"
  _hproj "$fw" "$d" pyproject.toml uv.lock || { CASE_DETAIL="fixture"; return 1; }
  mk_stubs "$s" 2 1 || { CASE_DETAIL="stubs"; return 1; }
  v="$(_commit "$d" "$s" "chore: add app")"
  calls="$(cat "$s/calls" 2>/dev/null)"
  [ "$v" = "LANDED" ] || bad="$bad [verdict $v]"
  # The probe goes through the SAME runner, --frozen included, and imports pytest.
  [ "$calls" = "uv run --frozen python -c import pytest" ] || bad="$bad [calls=[$(printf '%s' "$calls" | tr '\n' '|')]]"
  command grep -qF "[WARN] 'uv run --frozen pytest' cannot start pytest here" "$d/commit.log" || bad="$bad [no WARN naming the command]"
  command grep -qF 'PROJECT TESTS NOT ENFORCED' "$d/commit.log" || bad="$bad [not said loudly]"
  command grep -qF "uv run --frozen --extra test pytest" "$d/commit.log" || bad="$bad [the fix is not named]"
  command grep -qF '[BLOCKED]' "$d/commit.log" && bad="$bad [blocked as a failed suite]"
  CASE_DETAIL="${bad:-} hook: $(command grep -E 'BL-125|BLOCKED|WARN' "$d/commit.log" 2>/dev/null | head -3 | tr '\n' ' ')"
  [ -z "$bad" ]
}
case_H9() {   # review N3: pytest is there (the probe passes) and the COMMIT broke the suite at plugin load — BLOCKED, not "not enforced"
  # The stubs model pytest 8.x, where `pytest --version` loads the plugins and
  # so fails on exactly this suite (measured, pytest 8.4.1: rc 1 for a broken
  # pytest_plugins import and a broken `-p` plugin, rc 4 for an unknown addopts
  # flag), while `python -c 'import pytest'` does not load them (rc 0 on all
  # three). A probe spelled `--version` would call this suite missing.
  local fw="$1" d s v calls bad=""
  d="$(newtmp)/p"; s="$(newtmp)"
  _hproj "$fw" "$d" pyproject.toml uv.lock || { CASE_DETAIL="fixture"; return 1; }
  mk_stubs "$s" 1 0 1 || { CASE_DETAIL="stubs"; return 1; }
  v="$(_commit "$d" "$s" "chore: add app")"
  calls="$(cat "$s/calls" 2>/dev/null)"
  [ "$v" = "REFUSED" ] || bad="$bad [verdict $v]"
  [ "$calls" = "uv run --frozen python -c import pytest
uv run --frozen pytest" ] || bad="$bad [calls=[$(printf '%s' "$calls" | tr '\n' '|')]]"
  command grep -qxF "[BLOCKED] project tests FAILED (exit 1): uv run --frozen pytest" "$d/commit.log" || bad="$bad [no BLOCKED line]"
  command grep -qF 'PROJECT TESTS NOT ENFORCED' "$d/commit.log" && bad="$bad [called the broken suite not enforced]"
  CASE_DETAIL="${bad:-} hook: $(command grep -E 'BL-125|BLOCKED|WARN' "$d/commit.log" 2>/dev/null | head -3 | tr '\n' ' ')"
  [ -z "$bad" ]
}

echo
echo "=== H — the hook's fallback goes through the project's environment manager ==="
check "H1 uv.lock + pyproject [tool.pytest]: the hook runs 'uv run --frozen pytest' (the dogfood shape — it ran bare pytest)" case_H1 "$REPO_ROOT"
check "H2 pyproject.toml + poetry.lock: 'poetry run pytest'" case_H2 "$REPO_ROOT"
check "H3 pyproject.toml + pdm.lock: 'pdm run pytest'" case_H3 "$REPO_ROOT"
check "H4 Pipfile alone: 'pipenv run pytest'" case_H4 "$REPO_ROOT"
check "H5 no manager lockfile (requirements.txt): bare 'pytest' is the ONLY call — no manager, no probe" case_H5 "$REPO_ROOT"
check "H6 several lockfiles: uv wins, Scout's precedence (uv, poetry, pdm, pipenv)" case_H6 "$REPO_ROOT"
check "H7 poetry.lock + pdm.lock + Pipfile: poetry wins" case_H7 "$REPO_ROOT"
check "H8 pytest not in uv's environment: the import probe (through 'uv run --frozen') fails, the commit LANDS with a loud not-enforced WARN naming the fix — never blocked as a failed suite" case_H8 "$REPO_ROOT"
check "H9 pytest present, the commit broke the suite at plugin load (pytest 8 '--version' modelled failing): the probe passes and the commit is BLOCKED" case_H9 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# U — the writer, through the real interview function
# ════════════════════════════════════════════════════════════════════════════
TITLE='Testing & Bug Tracking'
# _unit FW ROOT OFFERED ANSWERS [REPORT] — run `adopt_confirm_scanned` for the
# test_command row, with ANSWERS (a printf format) as the operator's replies,
# then `adopt_write_test_command ROOT REPORT`.
#   - With REPORT: a REAL Scout report (review N1: a hand-built report had a
#     shape Scout never emits). The interview offers what REPORT's intakePrefill
#     offers, exactly as `adopt_run_reverse_intake` reads it; OFFERED is unused.
#   - Without: a report with Scout's two fields for a FOUND command — the
#     intakePrefill row and `stack.testCommand` — both carrying OFFERED.
# Sets URC; the run's output is in $WORK/u.out and the paths it recorded as
# written are in $WORK/u.written.
URC=0
_unit() {
  local fw="$1" root="$2" offered="$3" ans="$4" rep="${5:-}"
  : > "$WORK/u.written"
  if [ -n "$rep" ]; then
    offered="$(jq -r '.intakePrefill.sections[]? | select(.field == "test_command") | (.value // "")' "$rep")"
  else
    rep="$WORK/u.report.json"
    jq -n --arg v "$offered" \
      '{stack: {testCommand: {value: $v, source: "the scan"}},
        intakePrefill: {sections: [{id: "11_5", title: "Testing & Bug Tracking", kind: "scan-derived", field: "test_command",
          value: $v, source: "the scan"}]}}' > "$rep" || { URC=90; return; }
  fi
  # shellcheck disable=SC2059
  printf "$ans" | (
    ADOPT_PROJECT_NAME=t
    . "$fw/scripts/lib/adopt/adopt-core.sh" || exit 90
    . "$fw/scripts/lib/adopt/adopt-intake.sh" || exit 90
    ADOPT_WORK="$(mktemp -d "$WORK/aw.XXXXXX")" || exit 90
    adopt_ledger_init "$ADOPT_WORK/written" || exit 90
    adopt_answers_init "$ADOPT_WORK/answers" || exit 90
    adopt_confirm_scanned test_command "$TITLE" "$offered" "the scan" || exit 91
    adopt_write_test_command "$root" "$rep"; rc=$?
    cp "$ADOPT_WORK/written" "$WORK/u.written" 2>/dev/null
    exit "$rc" ) > "$WORK/u.out" 2>&1
  URC=$?
}
# Two REAL Scout reports, taken once from this tree's scripts/scout.sh: a
# Python project Scout finds no test command in (a conftest.py and a source
# file: `stack.testCommand` is null and the interview offers "(none detected)"),
# and a JS project whose scripts.test is `npm init`'s placeholder (Scout offers
# `npm test`; the body is in `stack.testCommand.source`).
_scout_fx() {   # _scout_fx NAME — prints the report path, or nothing
  local d="$WORK/scoutfx/$1"
  bash "$REPO_ROOT/scripts/scout.sh" --root "$d" --out "$d.out" >/dev/null 2>&1 \
    && [ -s "$d.out/scout-report.json" ] && printf '%s\n' "$d.out/scout-report.json"
}
mkdir -p "$WORK/scoutfx/none/src" "$WORK/scoutfx/npm/src"
( cd "$WORK/scoutfx/none" && git init -q . && printf 'x = 1\n' > src/app.py && printf 'import sys\n' > conftest.py ) >/dev/null 2>&1
( cd "$WORK/scoutfx/npm" && git init -q . && printf 'var x = 1;\n' > src/app.js \
  && printf '{\n  "name": "kp",\n  "version": "1.0.0",\n  "scripts": {\n    "test": "echo \\"Error: no test specified\\" && exit 1"\n  }\n}\n' > package.json ) >/dev/null 2>&1
REP_NONE="$(_scout_fx none)"
REP_NPM="$(_scout_fx npm)"
_uroot() { local r; r="$(newtmp)/p"; mkdir -p "$r" && printf '%s\n' "$r"; }
_said() { command grep -qF -- "$1" "$WORK/u.out"; }
_recorded() { command grep -cxF '.claude/test-command' "$WORK/u.written" 2>/dev/null; }
_body() { cat "$1/.claude/test-command" 2>/dev/null; }
_out() { tr '\n' ' ' < "$WORK/u.out" | cut -c1-"${1:-300}"; }

case_U1() {   # kept: Scout's command, verbatim, one line, recorded as written, and said
  local r; r="$(_uroot)"
  _unit "$1" "$r" "uv run --frozen pytest" '1\n'
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] recorded=$(_recorded) out=$(_out)"
  [ "$URC" -eq 0 ] && [ "$(_body "$r")" = "uv run --frozen pytest" ] \
    && [ "$(wc -l < "$r/.claude/test-command" | tr -d ' ')" = "1" ] \
    && [ "$(_recorded)" = "1" ] && _said "Wrote .claude/test-command: uv run --frozen pytest"
}
# _changed FW ANSWER — the operator changes the scan's offer to ANSWER: nothing
# is written, and the note says so, says what runs instead, and gives the line.
_changed() {
  local r; r="$(_uroot)"
  _unit "$1" "$r" "uv run --frozen pytest" "2\n$2\n"
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] recorded=$(_recorded) out=$(_out 500)"
  [ "$URC" -eq 0 ] && [ ! -e "$r/.claude/test-command" ] && [ ! -L "$r/.claude/test-command" ] && [ "$(_recorded)" = "0" ] \
    && _said "Not used as a command: you changed this answer" \
    && _said "runs only the command it detects on its own" \
    && _said "echo 'uv run --frozen pytest' > .claude/test-command"
}
case_U2() { _changed "$1" 'uv run pytest -x'; }
case_U5() { _changed "$1" 'not sure'; }
case_U7() { _changed "$1" 'pytest; bugs in GitHub Issues'; }
case_U3() {   # a file the project already has is kept byte for byte, not recorded, and the run says what it will run
  local r before; r="$(_uroot)"; mkdir -p "$r/.claude"
  printf '# our fast lane\r\n\n   make check   \r\n' > "$r/.claude/test-command"
  before="$(cksum < "$r/.claude/test-command")"
  _unit "$1" "$r" "uv run --frozen pytest" '1\n'
  CASE_DETAIL="rc=$URC recorded=$(_recorded) out=$(_out 400)"
  [ "$URC" -eq 0 ] && [ "$(cksum < "$r/.claude/test-command")" = "$before" ] \
    && [ "$(_recorded)" = "0" ] && _said "You already have .claude/test-command" \
    && _said "Every commit that stages a source file runs: make check" \
    && ! _said "runs: make check  "
}
case_U3b() {  # a dangling symlink: kept, nothing written through it, its target named, and said that the check ignores it
  local r; r="$(_uroot)"; mkdir -p "$r/.claude"
  ln -s "$r/elsewhere/cmd" "$r/.claude/test-command" || { CASE_DETAIL="no symlink support"; return 1; }
  _unit "$1" "$r" "uv run --frozen pytest" '1\n'
  CASE_DETAIL="rc=$URC link=$([ -L "$r/.claude/test-command" ] && echo kept || echo gone) target=$([ -e "$r/elsewhere/cmd" ] && echo CREATED || echo absent) recorded=$(_recorded) out=$(_out 400)"
  [ "$URC" -eq 0 ] && [ -L "$r/.claude/test-command" ] && [ ! -e "$r/elsewhere/cmd" ] && [ "$(_recorded)" = "0" ] \
    && _said "It is a symlink to $r/elsewhere/cmd" \
    && _said "That target does not exist, so the commit-time check ignores the file"
}
case_U3c() {  # an existing file with nothing runnable in it: kept, and said so
  local r; r="$(_uroot)"; mkdir -p "$r/.claude"
  printf '# no command yet\n\n' > "$r/.claude/test-command"
  _unit "$1" "$r" "uv run --frozen pytest" '1\n'
  CASE_DETAIL="rc=$URC out=$(_out 400)"
  [ "$URC" -eq 0 ] && _said "Nothing in it is runnable" && ! _said "Every commit that stages a source file runs:"
}
case_U4() {   # review N1, a REAL no-test Scout report: keeping "(none detected)" writes nothing, and that is said
  local r; r="$(_uroot)"
  [ -n "$REP_NONE" ] || { CASE_DETAIL="no Scout report for the no-test fixture"; return 1; }
  _unit "$1" "$r" "" '1\n' "$REP_NONE"
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] offered=[$(command grep -o "Keep '[^']*'" "$WORK/u.out" | head -1)] out=$(_out)"
  _said "Keep '(none detected)' as the answer?" || return 1
  [ "$URC" -eq 0 ] && [ ! -e "$r/.claude/test-command" ] && [ "$(_recorded)" = "0" ] \
    && _said "Not written: the scan found no test command" && ! _said "echo '"
}
case_U4b() {  # the same report, the answer changed to a command: still nothing written — the question never named one
  local r; r="$(_uroot)"
  [ -n "$REP_NONE" ] || { CASE_DETAIL="no Scout report for the no-test fixture"; return 1; }
  _unit "$1" "$r" "" '2\npytest\n' "$REP_NONE"
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] out=$(_out)"
  [ "$URC" -eq 0 ] && [ ! -e "$r/.claude/test-command" ] && _said "Not written: the scan found no test command"
}
case_U8() {   # review N2, a REAL Scout report on npm's placeholder script: keeping 'npm test' writes nothing, and that is said
  local r; r="$(_uroot)"
  [ -n "$REP_NPM" ] || { CASE_DETAIL="no Scout report for the placeholder fixture"; return 1; }
  _unit "$1" "$r" "" '1\n' "$REP_NPM"
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] out=$(_out 500)"
  _said "Keep 'npm test' as the answer?" || return 1
  [ "$URC" -eq 0 ] && [ ! -e "$r/.claude/test-command" ] && [ "$(_recorded)" = "0" ] \
    && _said "Not written: package.json's test script is npm's placeholder"
}
case_U8b() {  # ... and changing it does not get the changed-answer note, whose example line would install the placeholder
  local r; r="$(_uroot)"
  [ -n "$REP_NPM" ] || { CASE_DETAIL="no Scout report for the placeholder fixture"; return 1; }
  _unit "$1" "$r" "" '2\nnpm run unit\n' "$REP_NPM"
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] out=$(_out 500)"
  [ "$URC" -eq 0 ] && [ ! -e "$r/.claude/test-command" ] \
    && _said "Not written: package.json's test script is npm's placeholder" && ! _said "echo 'npm test'"
}
case_U6() {   # pnpm: Scout's flag is kept, and the run says why it stays
  local r; r="$(_uroot)"
  _unit "$1" "$r" "pnpm --config.verify-deps-before-run=false test" '1\n'
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] out=$(_out 400)"
  [ "$URC" -eq 0 ] && [ "$(_body "$r")" = "pnpm --config.verify-deps-before-run=false test" ] \
    && _said "it stops the check from rewriting your lockfile in the middle of a commit"
}

echo
echo "=== U — the writer: only the scan's command, kept; theirs kept and described ==="
check "U1 kept: .claude/test-command is Scout's command, one line, recorded in the write set, and the run says so" case_U1 "$REPO_ROOT"
check "U2 changed to 'uv run pytest -x': nothing written; the note says what runs instead and gives the one line" case_U2 "$REPO_ROOT"
check "U5 changed to 'not sure': nothing written" case_U5 "$REPO_ROOT"
check "U7 changed to 'pytest; bugs in GitHub Issues' (review round 1: it was written, and a failing suite LANDED): nothing written" case_U7 "$REPO_ROOT"
check "U3 an existing .claude/test-command is kept byte for byte, not in the write set, and the run says what it runs (read as the hook reads it)" case_U3 "$REPO_ROOT"
check "U3b an existing dangling symlink is kept, nothing is written through it, and the run names its target and says the check ignores it" case_U3b "$REPO_ROOT"
check "U3c an existing file with only a comment is kept, and the run says nothing in it is runnable" case_U3c "$REPO_ROOT"
check "U4 a real Scout report with no test command: keeping '(none detected)' writes nothing, and the run says so (review N1)" case_U4 "$REPO_ROOT"
check "U4b the same report, the answer changed to 'pytest': nothing written" case_U4b "$REPO_ROOT"
check "U8 a real Scout report on npm's placeholder test script: keeping 'npm test' writes nothing, and the run says why (review N2)" case_U8 "$REPO_ROOT"
check "U8b the same report, the answer changed: nothing written, and no 'echo npm test' advice" case_U8b "$REPO_ROOT"
check "U6 pnpm: 'pnpm --config.verify-deps-before-run=false test' is written verbatim and the flag is explained" case_U6 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# A — the real driver
# ════════════════════════════════════════════════════════════════════════════
# _uvproj DIR — a committed uv project: pyproject [tool.pytest], uv.lock, one
# source file and one test. Scout offers `uv run --frozen pytest` for it.
_uvproj() {
  local p="$1"
  mkdir -p "$p/src" "$p/tests" || return 1
  ( cd "$p" && git init -q . && git config user.email bl318@test.invalid && git config user.name "BL318 Test" ) >/dev/null 2>&1 || return 1
  printf '[project]\nname = "kp"\nversion = "0.1.0"\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > "$p/pyproject.toml"
  printf 'version = 1\n' > "$p/uv.lock"
  printf 'x = 1\n' > "$p/src/app.py"
  printf 'def test_x():\n    assert True\n' > "$p/tests/test_app.py"
  ( cd "$p" && git add -- pyproject.toml uv.lock src/app.py tests/test_app.py \
      && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1
}
# _adopt FW DIR TAG — the tier, the track, keep the four scan-derived answers,
# TL;DR no. Sets RUN_RC; the output is in $WORK/TAG.out.
RUN_RC=0
_adopt() {
  local fw="$1" p="$2" tag="$3"
  ( cd "$p" && printf '1\nstandard\n1\n1\n1\n1\nno\n' | SOIF_ADOPT_QDRANT=no SOIF_ADOPT_GUARDRAILS_DIR="$NOCLONE" \
      bash "$fw/scripts/adopt-project.sh" ) > "$WORK/$tag.out" 2>&1
  RUN_RC=$?
}
A1_P=""
case_A1() {   # a uv adoptee: the confirmed command lands in .claude/test-command, inside the adoption commit
  local p bad="" o
  p="$(newtmp)/kp"; _uvproj "$p" || { CASE_DETAIL="fixture"; return 1; }
  _adopt "$1" "$p" a1; o="$WORK/a1.out"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$o")]"
  command grep -qF "Keep 'uv run --frozen pytest' as the answer?" "$o" || bad="$bad [the interview did not offer the uv command]"
  [ "$(_body "$p")" = "uv run --frozen pytest" ] || bad="$bad [file=[$(_body "$p" | tr '\n' '|')]]"
  [ "$( cd "$p" && git show HEAD:.claude/test-command 2>/dev/null)" = "uv run --frozen pytest" ] || bad="$bad [not in the adoption commit]"
  command grep -qF "Wrote .claude/test-command: uv run --frozen pytest" "$o" || bad="$bad [the run did not say it wrote the file]"
  command grep -qF "it stops the check from rewriting your lockfile in the middle of a commit" "$o" || bad="$bad [the --frozen flag is not explained]"
  A1_P="$p"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
# A2 — review round 1's R-4: in a uv project Scout's offer and the hook's own
# fallback are the SAME string, so a commit there cannot tell the written file
# from no file at all. Here Scout offers `make test` (a Makefile test target
# outranks pytest in `_scout_test_command`) while the hook's fallback would run
# `uv run --frozen pytest` — so the commit proves the FILE is what runs.
case_A2() {
  local p bad="" o s v calls
  p="$(newtmp)/kp"; _uvproj "$p" || { CASE_DETAIL="fixture"; return 1; }
  printf 'test:\n\tpytest\n' > "$p/Makefile"
  ( cd "$p" && git add -- Makefile && git commit -q --no-verify -m "chore: make test" ) >/dev/null 2>&1
  _adopt "$1" "$p" a2; o="$WORK/a2.out"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$o")]"
  command grep -qF "Keep 'make test' as the answer?" "$o" || bad="$bad [the interview did not offer make test]"
  [ "$(_body "$p")" = "make test" ] || bad="$bad [file=[$(_body "$p" | tr '\n' '|')]]"
  s="$(newtmp)"; mk_stubs "$s" 1 || { CASE_DETAIL="stubs"; return 1; }
  v="$(_commit "$p" "$s" "chore: change app")"
  calls="$(_runs "$s")"
  [ "$v" = "REFUSED" ] || bad="$bad [verdict $v]"
  [ "$calls" = "make test" ] || bad="$bad [ran=[$(printf '%s' "$calls" | tr '\n' '|')]]"
  command grep -qxF "[BLOCKED] project tests FAILED (exit 1): make test" "$p/commit.log" || bad="$bad [no BLOCKED line naming make test]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
# A4 — review N1, end to end: a Python project Scout finds no test command in
# (conftest.py and a source file). Every scan answer kept, "(none detected)"
# included. Round 2 wrote "(none detected)" into the file, and since the file
# beats detection, every commit ran `sh -c '(none detected)'` -> 127 -> not
# enforced. Now nothing is written, so the hook's own detection (conftest.py ->
# bare pytest) is what runs, and a failing suite blocks.
case_A4() {
  local p bad="" o s v raw
  p="$(newtmp)/kp"; mkdir -p "$p/src" "$p/tests" || { CASE_DETAIL="fixture"; return 1; }
  ( cd "$p" && git init -q . && git config user.email bl318@test.invalid && git config user.name "BL318 Test" \
      && printf 'x = 1\n' > src/app.py && printf 'import sys\n' > conftest.py \
      && printf 'def test_x():\n    assert True\n' > tests/test_app.py \
      && git add -- src/app.py conftest.py tests/test_app.py && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1 \
    || { CASE_DETAIL="fixture"; return 1; }
  _adopt "$1" "$p" a4; o="$WORK/a4.out"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$o")]"
  command grep -qF "Keep '(none detected)' as the answer?" "$o" || bad="$bad [the interview did not offer (none detected)]"
  { [ -e "$p/.claude/test-command" ] || [ -L "$p/.claude/test-command" ]; } && bad="$bad [file written: $(_body "$p" | tr '\n' '|')]"
  command grep -qF "Not written: the scan found no test command" "$o" || bad="$bad [the run did not say nothing was written]"
  s="$(newtmp)"; mk_stubs "$s" 1 || { CASE_DETAIL="stubs"; return 1; }
  v="$(_commit "$p" "$s" "chore: change app")"
  raw="$(cat "$s/calls" 2>/dev/null)"
  [ "$v" = "REFUSED" ] || bad="$bad [verdict $v]"
  [ "$raw" = "pytest" ] || bad="$bad [ran=[$(printf '%s' "$raw" | tr '\n' '|')]]"
  command grep -qxF "[BLOCKED] project tests FAILED (exit 1): pytest" "$p/commit.log" || bad="$bad [no BLOCKED line: $(command grep -E 'BL-125|WARN' "$p/commit.log" | head -2 | tr '\n' ' ')]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_A3() {   # the adoptee already has .claude/test-command: kept byte for byte, not in the adoption commit, and said
  local p bad="" o before
  p="$(newtmp)/kp"; _uvproj "$p" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$p/.claude" && printf '# our fast lane\nmake check\n' > "$p/.claude/test-command"
  ( cd "$p" && git add -- .claude/test-command && git commit -q --no-verify -m "chore: our test lane" ) >/dev/null 2>&1
  before="$(cksum < "$p/.claude/test-command")"
  _adopt "$1" "$p" a3; o="$WORK/a3.out"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$o")]"
  [ "$(cksum < "$p/.claude/test-command")" = "$before" ] || bad="$bad [file changed: $(_body "$p" | tr '\n' '|')]"
  [ "$( cd "$p" && git show --name-only --format= HEAD 2>/dev/null | command grep -cxF .claude/test-command)" = "0" ] || bad="$bad [the adoption commit touched it]"
  command grep -qF "You already have .claude/test-command" "$o" || bad="$bad [the run did not say it kept the file]"
  command grep -qF "Every commit that stages a source file runs: make check" "$o" || bad="$bad [the run did not say what it runs]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

echo
echo "=== A — the real driver ==="
check "A1 a uv adoptee: .claude/test-command is 'uv run --frozen pytest', committed in the adoption commit; the run says so and explains the flag" case_A1 "$REPO_ROOT"
check "A2 Scout offers 'make test' where the hook's fallback would run uv: the file says 'make test', and the next commit runs make test — the written FILE is what runs" case_A2 "$REPO_ROOT"
check "A3 the adoptee's own .claude/test-command is kept byte for byte, outside the adoption commit, and the run says what it runs" case_A3 "$REPO_ROOT"
check "A4 Scout finds no test command and every answer is kept: nothing is written, and the next commit runs the hook's own detection (bare pytest) and blocks on a failing suite (review N1)" case_A4 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# E — the adopted project's commit runs the written command
# ════════════════════════════════════════════════════════════════════════════
case_E1() {   # failing suite -> blocked, naming the command; passing suite -> the PASSED receipt
  local p="$1" s1 s0 v calls bad=""
  [ -n "$p" ] && [ -d "$p/.git" ] || { CASE_DETAIL="no adopted project (A1 did not complete)"; return 1; }
  # The file, not the hook's own fallback (which spells the same command here):
  # present, and it is what is read — so no probe runs (`# BL-318-PYTEST-PROBE-GUARD`
  # belongs to the fallback only), and the calls hold the one real run.
  [ "$(_body "$p")" = "uv run --frozen pytest" ] || bad="$bad [no written file: $(_body "$p" | tr '\n' '|')]"
  s1="$(newtmp)"; mk_stubs "$s1" 1 || { CASE_DETAIL="stubs"; return 1; }
  v="$(_commit "$p" "$s1" "chore: change app")"
  calls="$(cat "$s1/calls" 2>/dev/null)"
  [ "$v" = "REFUSED" ] || bad="$bad [verdict $v]"
  [ "$calls" = "uv run --frozen pytest" ] || bad="$bad [ran=[$(printf '%s' "$calls" | tr '\n' '|')]]"
  command grep -qxF "[BLOCKED] project tests FAILED (exit 1): uv run --frozen pytest" "$p/commit.log" || bad="$bad [no BLOCKED line: $(command grep -E 'BL-125|WARN' "$p/commit.log" | head -2 | tr '\n' ' ')]"
  s0="$(newtmp)"; mk_stubs "$s0" 0 || { CASE_DETAIL="stubs"; return 1; }
  v="$(_commit "$p" "$s0" "chore: change app")"
  command grep -qxF "[OK] project tests: 'uv run --frozen pytest' PASSED — commit may proceed." "$p/commit.log" \
    || bad="$bad [no PASSED receipt on a passing suite: $(command grep -E 'BL-125|WARN|BLOCKED' "$p/commit.log" | head -2 | tr '\n' ' ')]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
echo
echo "=== E — a commit in the adopted project ==="
check "E1 the adopted project's commit runs 'uv run --frozen pytest': a failing suite blocks it, a passing one prints the PASSED receipt" case_E1 "$A1_P"

# ════════════════════════════════════════════════════════════════════════════
# M — mutants (the mirror-and-mutate pattern of tests/test-bl312-tldr-mode.sh)
# ════════════════════════════════════════════════════════════════════════════
echo
echo "=== M — every BL-318 G1 marker is load-bearing ==="
mk_mirror() {
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$1/README.md" "$2/"
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
# mutant ID REL MARKER REPLACEMENT KILLER WHAT — in a mirror of the tree.
mutant() {
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  # The hook's lines live in a quoted heredoc, so `bash -n` on the lib cannot see
  # them: emit the mutant hook and parse THAT, or a broken hook would read as a kill.
  if [ "$rel" = "$HT" ]; then
    ( . "$m/$HT" && soif_write_precommit_hook "$m/emitted-pre-commit" ) >/dev/null 2>&1 \
      && bash -n "$m/emitted-pre-commit" 2>/dev/null \
      || { fail_ "$id" "the mutant's emitted hook does not parse — a kill would prove nothing"; return; }
  fi
  CASE_DETAIL=""
  if "$killer" "$m"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}"
  fi
}
HT=scripts/lib/hook-templates.sh
AI=scripts/lib/adopt/adopt-intake.sh
AS=scripts/lib/adopt/adopt-state.sh
# The writer's offer read as round 2 spelled it — from the interview's prefill,
# which says "(none detected)" when Scout found nothing.
OLD_OFFER_READ="$(cat <<'R'
  offered="$(jq -r '[.intakePrefill.sections[]? | select(.field == "test_command") | (.value // "")] | last // ""' "$report" 2>/dev/null)"
R
)"
mutant MH1  "$HT" '# BL-318-PYTEST-UV'     '    if [ -f uv.lock ]; then soif_test_run=""' case_H1 "a uv project runs bare pytest again (the dogfood defect)"
mutant MH1b "$HT" '# BL-318-PYTEST-UV'     '    if [ -f uv.lock ] || [ -f pyproject.toml ]; then soif_test_run="uv run --frozen"' case_H2 "the uv arm keys on pyproject.toml, not uv.lock (review round 1's R-3 survivor)"
mutant MH2  "$HT" '# BL-318-PYTEST-POETRY' '    elif [ -f poetry.lock ]; then soif_test_run=""' case_H2 "a poetry project runs bare pytest"
mutant MH3  "$HT" '# BL-318-PYTEST-PDM'    '    elif [ -f pdm.lock ]; then soif_test_run=""' case_H3 "a pdm project runs bare pytest"
mutant MH4  "$HT" '# BL-318-PYTEST-PIPENV' '    elif [ -f Pipfile ]; then soif_test_run=""' case_H4 "a pipenv project runs bare pytest"
mutant MH4b "$HT" '# BL-318-PYTEST-PIPENV' '    elif [ -f Pipfile.lock ]; then soif_test_run="pipenv run"' case_H4 "the pipenv arm keys on Pipfile.lock, not Pipfile (review round 1's R-3 survivor)"
mutant MP1  "$HT" '# BL-318-PYTEST-PROBE-FAIL'  '      if false; then' case_H8 "no probe: a pytest uv cannot spawn blocks every source commit as a failed suite (review round 1's R-2)"
mutant MP2  "$HT" '# BL-318-PYTEST-PROBE-CMD' '      soif_probe="$soif_test_cmd --version"' case_H9 "the probe is pytest --version again: on pytest 8 a suite the commit broke lands as not enforced (review N3)"
mutant MP3  "$HT" '# BL-318-PYTEST-PROBE-GUARD' '    if true; then' case_H5 "the bare-pytest arm is probed too (review N4's survivor)"
mutant MW1  "$AI" '# BL-318-TESTCMD-WRITE' '  :' case_U1 "Scout's kept command is never written"
mutant MW2  "$AI" '# BL-318-TESTCMD-KEEP' '  if false; then' case_U3 "a .claude/test-command the project already has is overwritten"
mutant MW3  "$AI" '# BL-318-TESTCMD-KEEP' '  if [ -f "$root/$rel" ]; then' case_U3b "a dangling symlink is written through"
mutant MW4  "$AI" '# BL-318-TESTCMD-ASKED' '  if false; then' case_U4 "a scan that found nothing is not said to have found nothing"
mutant MW5  "$AI" '# BL-318-TESTCMD-KEPT' '  if false; then' case_U7 "a changed answer is written and run on every commit (review round 1's R-1)"
mutant MW6  "$AI" '# BL-318-TESTCMD-FLAG-WHY' '      :' case_U6 "the kept Scout flag is not explained"
mutant MW7  "$AS" '# BL-318-TESTCMD-CALL' '  :' case_A1 "adoption never calls the writer"
mutant MW7b "$AS" '# BL-318-TESTCMD-CALL' '  :' case_A2 "adoption never calls the writer, seen at the next commit (review round 1's R-4)"
mutant MN1  "$AI" '# BL-318-TESTCMD-OFFER' "$OLD_OFFER_READ" case_U4 "the offer is read from the interview's prefill, so '(none detected)' is written (review N1)"
mutant MN1b "$AI" '# BL-318-TESTCMD-OFFER' "$OLD_OFFER_READ" case_A4 "the same, end to end: the file holds '(none detected)' and a failing suite lands (review N1)"
mutant MN2  "$AI" '# BL-318-TESTCMD-PLACEHOLDER' '  if false; then' case_U8 "npm's placeholder script is written as the test command and blocks every source commit (review N2)"
mutant MS1  "$AI" '# BL-318-TESTCMD-SAYS' '    if false; then' case_U3 "a kept file's command is not said"
mutant MS2  "$AI" '# BL-318-TESTCMD-SAYS' '    if true; then' case_U3c "a kept file with nothing runnable is described as running something"
mutant ML1  "$AI" '# BL-318-TESTCMD-LINK' '    :' case_U3b "a kept symlink's target is not named"
mutant MD1  "$AI" '# BL-318-TESTCMD-DANGLING' '    if false; then' case_U3b "a kept dangling symlink is described as a file the check reads"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

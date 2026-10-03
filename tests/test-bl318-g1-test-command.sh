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
#   - adoption writes `.claude/test-command` from the interview's confirmed
#     answer, verbatim, and keeps a file the project already has
#     (`# BL-318-TESTCMD-*`, `adopt_write_test_command`);
#   - the hook's own fallback runs pytest through the project's uv, poetry, pdm
#     or pipenv when one is in evidence (`# BL-318-PYTEST-*`), so a project
#     with no file — every adoptee adopted before this fix, and a greenfield uv
#     project — gets a check that runs.
#
# CASES
#   H  the hook's fallback: a bare repo, the emitted hook, stub runners on PATH
#   U  the writer, driven through the real interview function
#      (`adopt_confirm_scanned`), so the answer it writes is the one the
#      interview recorded
#   A  the real driver: a uv adoptee gets the file, committed; a file the
#      adoptee already has is kept
#   E  a commit in that adopted project runs the written command
#   M  mutants: each rewrites ONE marked line in a mirror of the tree, checks
#      the edit landed by its literal text, and needs a named case to go RED
#
# Over ~10s (two real adoptions, plus one more under a mutant), so tests.yml
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

# mk_stubs DIR RC — uv, poetry, pdm, pipenv and pytest that append their own
# command line to DIR/calls and exit RC. First on PATH, so a real runner on the
# host can never answer for one of them.
mk_stubs() {
  local d="$1" rc="$2" t=""
  mkdir -p "$d" || return 1
  for t in uv poetry pdm pipenv pytest; do
    cat > "$d/$t" <<STUB
#!/bin/sh
echo "$t\${*:+ \$*}" >> "$d/calls"
exit $rc
STUB
    chmod +x "$d/$t" || return 1
  done
}

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
  calls="$(cat "$s/calls" 2>/dev/null)"
  CASE_DETAIL="verdict=$v ran=[$(printf '%s' "$calls" | tr '\n' '|')] want=[$want] hook: $(command grep -E 'BL-125|BLOCKED|WARN' "$d/commit.log" 2>/dev/null | head -3 | tr '\n' ' ')"
  [ "$v" = "REFUSED" ] && [ "$calls" = "$want" ] \
    && command grep -qxF "[BLOCKED] project tests FAILED (exit 1): $want" "$d/commit.log"
}
case_H1() { _hrun "$1" "uv run --frozen pytest" pyproject.toml uv.lock; }
case_H2() { _hrun "$1" "poetry run pytest" pytest.ini poetry.lock; }
case_H3() { _hrun "$1" "pdm run pytest" pytest.ini pdm.lock; }
case_H4() { _hrun "$1" "pipenv run pytest" pytest.ini Pipfile Pipfile.lock; }
case_H5() { _hrun "$1" "pytest" pytest.ini requirements.txt; }
case_H6() { _hrun "$1" "uv run --frozen pytest" pytest.ini uv.lock poetry.lock pdm.lock Pipfile; }

echo
echo "=== H — the hook's fallback goes through the project's environment manager ==="
check "H1 uv.lock + pyproject [tool.pytest]: the hook runs 'uv run --frozen pytest' (the dogfood shape — it ran bare pytest)" case_H1 "$REPO_ROOT"
check "H2 poetry.lock: 'poetry run pytest'" case_H2 "$REPO_ROOT"
check "H3 pdm.lock: 'pdm run pytest'" case_H3 "$REPO_ROOT"
check "H4 Pipfile: 'pipenv run pytest'" case_H4 "$REPO_ROOT"
check "H5 no manager lockfile (requirements.txt): bare 'pytest', and no manager is run" case_H5 "$REPO_ROOT"
check "H6 several lockfiles: uv wins, Scout's precedence (uv, poetry, pdm, pipenv)" case_H6 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# U — the writer, through the real interview function
# ════════════════════════════════════════════════════════════════════════════
TITLE='Testing & Bug Tracking'
# _unit FW ROOT OFFERED ANSWERS — run `adopt_confirm_scanned` for the
# test_command row with the scan OFFERING `OFFERED` ("" = the scan found
# nothing) and ANSWERS (a printf format) as the operator's replies, then
# `adopt_write_test_command ROOT`. Sets URC; the run's output is in $WORK/u.out
# and the paths it recorded as written are in $WORK/u.written.
URC=0
_unit() {
  local fw="$1" root="$2" offered="$3" ans="$4"
  : > "$WORK/u.written"
  # shellcheck disable=SC2059
  printf "$ans" | (
    ADOPT_PROJECT_NAME=t
    . "$fw/scripts/lib/adopt/adopt-core.sh" || exit 90
    . "$fw/scripts/lib/adopt/adopt-intake.sh" || exit 90
    ADOPT_WORK="$(mktemp -d "$WORK/aw.XXXXXX")" || exit 90
    adopt_ledger_init "$ADOPT_WORK/written" || exit 90
    adopt_answers_init "$ADOPT_WORK/answers" || exit 90
    adopt_confirm_scanned test_command "$TITLE" "$offered" "the scan" || exit 91
    adopt_write_test_command "$root"; rc=$?
    cp "$ADOPT_WORK/written" "$WORK/u.written" 2>/dev/null
    exit "$rc" ) > "$WORK/u.out" 2>&1
  URC=$?
}
_uroot() { local r; r="$(newtmp)/p"; mkdir -p "$r" && printf '%s\n' "$r"; }
_said() { command grep -qF -- "$1" "$WORK/u.out"; }
_recorded() { command grep -cxF '.claude/test-command' "$WORK/u.written" 2>/dev/null; }
_body() { cat "$1/.claude/test-command" 2>/dev/null; }

case_U1() {   # kept: the confirmed command, verbatim, one line, recorded as written, and said
  local r; r="$(_uroot)"
  _unit "$1" "$r" "uv run --frozen pytest" '1\n'
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] recorded=$(_recorded) out=$(tr '\n' ' ' < "$WORK/u.out" | cut -c1-300)"
  [ "$URC" -eq 0 ] && [ "$(_body "$r")" = "uv run --frozen pytest" ] \
    && [ "$(wc -l < "$r/.claude/test-command" | tr -d ' ')" = "1" ] \
    && [ "$(_recorded)" = "1" ] && _said "Wrote .claude/test-command: uv run --frozen pytest"
}
case_U2() {   # changed: the operator's answer wins over what the scan offered
  local r; r="$(_uroot)"
  _unit "$1" "$r" "uv run --frozen pytest" '2\nuv run pytest -x\n'
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] out=$(tr '\n' ' ' < "$WORK/u.out" | cut -c1-300)"
  [ "$URC" -eq 0 ] && [ "$(_body "$r")" = "uv run pytest -x" ] && _said "Wrote .claude/test-command: uv run pytest -x"
}
case_U3() {   # a file the project already has is kept, byte for byte, and not recorded as written
  local r before; r="$(_uroot)"; mkdir -p "$r/.claude"
  printf '# our fast lane\nmake check\n' > "$r/.claude/test-command"
  before="$(cksum < "$r/.claude/test-command")"
  _unit "$1" "$r" "uv run --frozen pytest" '1\n'
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] recorded=$(_recorded) out=$(tr '\n' ' ' < "$WORK/u.out" | cut -c1-300)"
  [ "$URC" -eq 0 ] && [ "$(cksum < "$r/.claude/test-command")" = "$before" ] \
    && [ "$(_recorded)" = "0" ] && _said "You already have .claude/test-command"
}
case_U3b() {  # ... and so is a dangling symlink: nothing is written through it
  local r; r="$(_uroot)"; mkdir -p "$r/.claude"
  ln -s "$r/elsewhere/cmd" "$r/.claude/test-command" || { CASE_DETAIL="no symlink support"; return 1; }
  _unit "$1" "$r" "uv run --frozen pytest" '1\n'
  CASE_DETAIL="rc=$URC link=$([ -L "$r/.claude/test-command" ] && echo kept || echo gone) target=$([ -e "$r/elsewhere/cmd" ] && echo CREATED || echo absent) recorded=$(_recorded)"
  [ "$URC" -eq 0 ] && [ -L "$r/.claude/test-command" ] && [ ! -e "$r/elsewhere/cmd" ] && [ "$(_recorded)" = "0" ]
}
case_U4() {   # the scan found nothing: the free answer was not to a command question, so nothing is written, and that is said
  local r; r="$(_uroot)"
  _unit "$1" "$r" "" 'we use pytest\n'
  CASE_DETAIL="rc=$URC file=$([ -e "$r/.claude/test-command" ] && echo WRITTEN || echo absent) out=$(tr '\n' ' ' < "$WORK/u.out" | cut -c1-300)"
  [ "$URC" -eq 0 ] && [ ! -e "$r/.claude/test-command" ] && [ "$(_recorded)" = "0" ] \
    && _said "Not written: the scan found no test command"
}
case_U5() {   # an answer the shell cannot parse would block every source commit, so it is not written, and that is said
  local r; r="$(_uroot)"
  _unit "$1" "$r" "uv run --frozen pytest" "2\ndon't know\n"
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] out=$(tr '\n' ' ' < "$WORK/u.out" | cut -c1-300)"
  [ "$URC" -eq 0 ] && [ ! -e "$r/.claude/test-command" ] && _said "Not written: the shell cannot read"
}
case_U6() {   # pnpm: Scout's flag is kept, and the run says why it stays
  local r; r="$(_uroot)"
  _unit "$1" "$r" "pnpm --config.verify-deps-before-run=false test" '1\n'
  CASE_DETAIL="rc=$URC file=[$(_body "$r" | tr '\n' '|')] out=$(tr '\n' ' ' < "$WORK/u.out" | cut -c1-400)"
  [ "$URC" -eq 0 ] && [ "$(_body "$r")" = "pnpm --config.verify-deps-before-run=false test" ] \
    && _said "it stops the check from rewriting your lockfile in the middle of a commit"
}

echo
echo "=== U — the writer: the confirmed answer, verbatim; theirs kept; nothing that would mislead ==="
check "U1 kept: .claude/test-command is the confirmed command, one line, recorded in the write set, and the run says so" case_U1 "$REPO_ROOT"
check "U2 changed in the interview: the operator's answer is written, not the scan's" case_U2 "$REPO_ROOT"
check "U3 a .claude/test-command the project already has is kept byte for byte and not in the write set" case_U3 "$REPO_ROOT"
check "U3b a dangling symlink at that path is kept and nothing is written through it" case_U3b "$REPO_ROOT"
check "U4 the scan found nothing: the free answer is not written as a command, and the run says so" case_U4 "$REPO_ROOT"
check "U5 an answer sh cannot parse (\"don't know\") is not written — it would block every source commit" case_U5 "$REPO_ROOT"
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
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

echo
echo "=== A — the real driver ==="
check "A1 a uv adoptee: .claude/test-command is 'uv run --frozen pytest', committed in the adoption commit; the run says so and explains the flag" case_A1 "$REPO_ROOT"
check "A3 the adoptee's own .claude/test-command is kept byte for byte, outside the adoption commit, and the run says so" case_A3 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# E — the adopted project's commit runs the written command
# ════════════════════════════════════════════════════════════════════════════
case_E1() {   # failing suite -> blocked, naming the command; passing suite -> the PASSED receipt
  local p="$1" s1 s0 v calls bad=""
  [ -n "$p" ] && [ -d "$p/.git" ] || { CASE_DETAIL="no adopted project (A1 did not complete)"; return 1; }
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
mutant MH1 "$HT" '# BL-318-PYTEST-UV'     '      soif_test_cmd="pytest"' case_H1 "a uv project runs bare pytest again (the dogfood defect)"
mutant MH2 "$HT" '# BL-318-PYTEST-POETRY' '      soif_test_cmd="pytest"' case_H2 "a poetry project runs bare pytest"
mutant MH3 "$HT" '# BL-318-PYTEST-PDM'    '      soif_test_cmd="pytest"' case_H3 "a pdm project runs bare pytest"
mutant MH4 "$HT" '# BL-318-PYTEST-PIPENV' '      soif_test_cmd="pytest"' case_H4 "a pipenv project runs bare pytest"
mutant MW1 "$AI" '# BL-318-TESTCMD-WRITE' '  :' case_U1 "the confirmed command is never written"
mutant MW2 "$AI" '# BL-318-TESTCMD-KEEP' '  if false; then' case_U3 "a .claude/test-command the project already has is overwritten"
mutant MW3 "$AI" '# BL-318-TESTCMD-KEEP' '  if [ -f "$root/$rel" ]; then' case_U3b "a dangling symlink is written through"
mutant MW4 "$AI" '# BL-318-TESTCMD-ASKED' '  if false; then' case_U4 "a free answer to a question that never named a command is written as one"
mutant MW5 "$AI" '# BL-318-TESTCMD-PARSE' '  if false; then' case_U5 "an answer sh cannot parse is written, and would block every source commit"
mutant MW6 "$AI" '# BL-318-TESTCMD-FLAG-WHY' '      :' case_U6 "the kept Scout flag is not explained"
mutant MW7 "$AS" '# BL-318-TESTCMD-CALL' '  :' case_A1 "adoption never calls the writer"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

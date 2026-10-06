#!/usr/bin/env bash
# tests/test-bl318-g3-ci-template.sh — `## BL-318:` G3.
#
# THE DEFECT (dogfood run 2, finding 33). Adoption installed the framework's CI
# as `.github/workflows/solo-gates.yml` from templates/pipelines/ci/github/
# python.yml, and three things about it were wrong for the k-pdf adoptee:
#   - the guide and adoption's own output said it "runs from your next push";
#     a branch push ran nothing, because the template triggers only on a push
#     to main and on pull requests to main;
#   - the workflow was `name: CI`, the same name as the adoptee's own ci.yml, so
#     two workflows read "CI" in the Actions tab and in a pull request's checks;
#   - it installed with `pip install -r requirements.txt`, and a uv project
#     (pyproject.toml + uv.lock, no requirements.txt) has no such file.
#
# THE FIX (`# BL-318-G3-*` in the template and in adopt-ci.sh): the words say
# what the triggers do (the triggers are unchanged); every GitHub CI template is
# named `Solo Orchestrator checks`; one step decides the installer — uv for
# uv.lock with pyproject.toml, pip for requirements.txt, an `::error::` naming
# what is missing for neither — and every install and tool step is gated on
# that one answer, the uv ones running through `uv sync --frozen` and
# `uv run --frozen`.
#
# CASES
#   A  the real adoption, twice: a uv adoptee and a requirements.txt adoptee,
#      each with its own workflow named CI. The written solo-gates.yml is the
#      python template byte for byte, so every T and B case below reads the
#      file adoption wrote; adoption's own words are checked too.
#   T  the written workflow: triggers, name, the setup-uv pin, the steps each
#      installer runs, and that no project tool runs ungated
#   B  the shipped shell, executed as Actions runs it (bash -eo pipefail): the
#      installer decision over six fixture trees, and the lockfile check
#   D  the guides' sentences about when the framework's CI runs
#   M  mutants. Template and doc mutants edit a copy and re-run the named case
#      on it (adoption copies the template verbatim, which A1/A2 prove and MA1
#      guards); adoption mutants edit a mirror of the tree and re-run adoption.
#      Each checks its edit changed exactly one line, by text.
#
# Greenfield `init.sh` copies the same template verbatim to ci.yml
# (`generate_ci`'s `cp`); it is not driven here, which keeps this suite out of
# the init.sh lane.
#
# Four real adoptions (two under mutants), so tests.yml pins it to a leg with
# room. No init.sh, not an aggregator -> both lists. bash 3.2 safe.
set -uo pipefail
export SOIF_ADOPT_MCP=off              # `# BL-311-MCP-SEAM`
unset GITHUB_BASE_REF 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-318 G3 — the framework's CI: when it runs, its name, and a uv project's install =="
for t in git jq awk; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
NOCLONE="$WORK/no-guardrails-clone"   # never created: no real Guardrails clone runs here
newtmp() { mktemp -d "$WORK/tXXXXXX"; }

# _has GREP-ARGS — grep that reads its input to the end. A piped `grep -q` exits
# at the first match, and under pipefail the writer's SIGPIPE can fail a
# pipeline whose match succeeded (#422).
_has() { command grep "$@" >/dev/null; }

CASE_DETAIL=""
check() {
  local label="$1" fn="$2"; shift 2
  CASE_DETAIL=""
  if "$fn" "$@"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

TPL_REL="templates/pipelines/ci/github/python.yml"
GATE_UV="steps.deps.outputs.installer == 'uv'"
GATE_PIP="steps.deps.outputs.installer == 'pip'"
WF_NAME="Solo Orchestrator checks"

# steps_tsv FILE — one line per step of the `test` job:
#   index <TAB> name <TAB> id <TAB> if <TAB> uses <TAB> env <TAB> run
# env entries and run-block lines are joined with \037. A block line keeps any
# indentation beyond the block's own, so a command nested in an `if` does not
# read as a top-level one.
steps_tsv() {
  LC_ALL=C awk '
    function flush() { if (n > 0) printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\n", n, nm, id, ifv, uses, env, run }
    function key(s) {
      mode = ""
      if (s ~ /^name: /)                   nm = substr(s, 7)
      else if (s ~ /^id: /)                id = substr(s, 5)
      else if (s ~ /^if: /)                ifv = substr(s, 5)
      else if (s ~ /^uses: /)              uses = substr(s, 7)
      else if (s ~ /^run: \|[[:space:]]*$/) mode = "run"
      else if (s ~ /^run: /)               run = substr(s, 6)
      else if (s ~ /^env:[[:space:]]*$/)   mode = "env"
    }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); n = 0; injob = ($0 ~ /^  test:/); next }
    !injob { next }
    /^      - / { flush(); n++; nm = ""; id = ""; ifv = ""; uses = ""; env = ""; run = ""; mode = ""; key(substr($0, 9)); next }
    n > 0 && /^        [^ #]/ { key(substr($0, 9)); next }
    n > 0 && mode == "run" && /^          / { l = substr($0, 11); run = (run == "" ? l : run "\037" l); next }
    n > 0 && mode == "env" && /^          [^ #]/ { l = substr($0, 11); env = (env == "" ? l : env "\037" l); next }
    END { flush() }
  ' "$1"
}
# runs_gated FILE GATE — the run lines of every step whose `if:` is GATE, in order.
runs_gated() {
  steps_tsv "$1" | GATE="$2" awk -F'\t' '$4 == ENVIRON["GATE"] && $7 != "" { n = split($7, a, "\037"); for (i = 1; i <= n; i++) print a[i] }'
}
# step_field FILE MATCHCOL MATCHVAL OUTCOL — OUTCOL of the first step whose MATCHCOL equals MATCHVAL.
step_field() {
  steps_tsv "$1" | MV="$3" awk -F'\t' -v mc="$2" -v oc="$4" '$mc == ENVIRON["MV"] { print $oc; exit }'
}

# ════════════════════════════════════════════════════════════════════════════
# A — the real adoption
# ════════════════════════════════════════════════════════════════════════════
# _pyproj DIR KIND — a committed Python project with its OWN workflow named CI
# (the k-pdf shape; it also makes Scout report the GitHub host). KIND uv has
# pyproject.toml + uv.lock and no requirements.txt; KIND req has
# requirements.txt and no uv.lock.
_pyproj() {
  local p="$1" kind="$2"
  mkdir -p "$p/src" "$p/tests" "$p/.github/workflows" || return 1
  ( cd "$p" && git init -q . && git config user.email bl318g3@test.invalid && git config user.name "BL318 G3 Test" ) >/dev/null 2>&1 || return 1
  printf 'name: CI\n\non:\n  push:\n    branches: [main]\n  pull_request:\n    branches: [main]\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo their own checks\n' > "$p/.github/workflows/ci.yml"
  printf 'x = 1\n' > "$p/src/app.py"
  printf 'def test_x():\n    assert True\n' > "$p/tests/test_app.py"
  if [ "$kind" = uv ]; then
    printf '[project]\nname = "kp"\nversion = "0.1.0"\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > "$p/pyproject.toml"
    printf 'version = 1\n' > "$p/uv.lock"
    ( cd "$p" && git add -- pyproject.toml uv.lock ) >/dev/null 2>&1 || return 1
  else
    printf 'pytest\n' > "$p/requirements.txt"
    printf '[pytest]\ntestpaths = tests\n' > "$p/pytest.ini"
    ( cd "$p" && git add -- requirements.txt pytest.ini ) >/dev/null 2>&1 || return 1
  fi
  ( cd "$p" && git add -- .github/workflows/ci.yml src/app.py tests/test_app.py \
      && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1
}
# _adopt FW DIR TAG — the tier, the track, keep the scan's answers, TL;DR no.
# Sets RUN_RC; the output is in $WORK/TAG.out.
RUN_RC=0
_adopt() {
  local fw="$1" p="$2" tag="$3"
  ( cd "$p" && printf '1\nstandard\n1\n1\n1\n1\nno\n' | SOIF_ADOPT_QDRANT=no SOIF_ADOPT_GUARDRAILS_DIR="$NOCLONE" \
      bash "$fw/scripts/adopt-project.sh" ) > "$WORK/$tag.out" 2>&1
  RUN_RC=$?
}
_name_of() { LC_ALL=C awk '/^name: /{ sub(/^name: /, ""); print; exit }' "$1" 2>/dev/null; }

# _adopted FW KIND TAG — adopt a fresh KIND project with FW. Sets ADOPTED_P
# and RUN_RC — in THIS shell, never a command substitution, or RUN_RC would be
# lost and the rc check below would read a stale 0.
ADOPTED_P=""
_adopted() {
  local fw="$1" kind="$2" tag="$3"
  ADOPTED_P="$(newtmp)/kp"
  RUN_RC=99
  _pyproj "$ADOPTED_P" "$kind" || return 1
  _adopt "$fw" "$ADOPTED_P" "$tag"
}
# _a_written FW P TAG — the adoption at P (driven with FW) wrote FW's python
# template, verbatim, committed, beside their own workflow, under another name.
_a_written() {
  local fw="$1" p="$2" tag="$3" bad="" sg=""
  sg="$p/.github/workflows/solo-gates.yml"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$WORK/$tag.out")]"
  [ -s "$sg" ] || bad="$bad [no solo-gates.yml]"
  cmp -s "$sg" "$fw/$TPL_REL" || bad="$bad [solo-gates.yml is not the python template byte for byte]"
  ( cd "$p" && git ls-files --error-unmatch .github/workflows/solo-gates.yml ) >/dev/null 2>&1 || bad="$bad [not committed]"
  [ "$(_name_of "$p/.github/workflows/ci.yml")" = "CI" ] || bad="$bad [their own ci.yml was changed]"
  [ "$(_name_of "$sg")" != "$(_name_of "$p/.github/workflows/ci.yml")" ] || bad="$bad [the framework's workflow has their workflow's name: $(_name_of "$sg")]"
  CASE_DETAIL="$bad"
  [ -z "$bad" ]
}
A_UV=""; A_REQ=""
case_A1() { _adopted "$1" uv a-uv || { CASE_DETAIL="fixture"; return 1; }; A_UV="$ADOPTED_P"; _a_written "$1" "$A_UV" a-uv; }
case_A2() { _adopted "$1" req a-req || { CASE_DETAIL="fixture"; return 1; }; A_REQ="$ADOPTED_P"; _a_written "$1" "$A_REQ" a-req; }
# _a_words OUT — adoption's note about the framework's CI says when it runs and
# under what name, and no longer says "from your next push".
_a_words() {
  local o="$1" bad=""
  command grep -qF "GitHub runs it on a push to main and on pull requests to main" "$o" || bad="$bad [the trigger sentence is missing]"
  command grep -qF "a push to any other branch runs nothing" "$o" || bad="$bad [it does not say a branch push runs nothing]"
  command grep -qF "\"$WF_NAME\"" "$o" || bad="$bad [the workflow's name is not given]"
  command grep -qF "from your next push" "$o" && bad="$bad [it still says 'from your next push']"
  CASE_DETAIL="$bad out=[$(command grep -A4 "Installed the framework's CI" "$o" | tr '\n' '|')]"
  [ -z "$bad" ]
}
case_A3() { _a_words "$WORK/a-uv.out" && _a_words "$WORK/a-req.out"; }

echo
echo "=== A — the real adoption: the file it writes, and what it says ==="
check "A1 a uv adoptee with its own workflow named CI: solo-gates.yml is the python template byte for byte, committed, under another name" case_A1 "$REPO_ROOT"
check "A2 a requirements.txt adoptee: the same file, committed, under another name" case_A2 "$REPO_ROOT"
check "A3 adoption says when the framework's CI runs and under what name, not 'from your next push'" case_A3

# Every T and B case reads the file adoption wrote; if A1 wrote none, they read
# the template (A1 has already failed).
SG="$A_UV/.github/workflows/solo-gates.yml"
[ -s "$SG" ] || SG="$REPO_ROOT/$TPL_REL"

# ════════════════════════════════════════════════════════════════════════════
# T — the written workflow
# ════════════════════════════════════════════════════════════════════════════
case_T1() {   # the triggers are exactly the ones before G3
  local f="$1" got="" want=""
  got="$(LC_ALL=C awk '/^on:/{f=1; next} f && /^[^ ]/{exit} f && NF' "$f")"
  want="$(printf '  push:\n    branches: [main]\n  pull_request:\n    branches: [main]')"
  CASE_DETAIL="on: [$(printf '%s' "$got" | tr '\n' '|')]"
  [ "$got" = "$want" ]
}
case_T2() {   # the name cannot be taken for a project's own CI
  local f="$1" n=""
  n="$(_name_of "$f")"
  CASE_DETAIL="name=[$n]"
  [ "$n" = "$WF_NAME" ] && [ "$(command grep -c '^name:' "$f")" -eq 1 ]
}
case_T2b() {  # every GitHub CI template: adoption installs whichever matches the language
  local d="$1" f="" n=0 bad=""
  for f in "$d"/*.yml; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    [ "$(_name_of "$f")" = "$WF_NAME" ] || bad="$bad ${f##*/}=[$(_name_of "$f")]"
  done
  CASE_DETAIL="$n templates;$bad"
  [ "$n" -ge 10 ] && [ -z "$bad" ]
}
case_T3() {   # setup-uv: one step, SHA-pinned with its version, uv-gated, after the decision and before the install
  local f="$1" rows="" n="" uses="" gate="" i_deps="" i_uv="" i_sync=""
  rows="$(steps_tsv "$f")"
  n="$(printf '%s\n' "$rows" | awk -F'\t' '$5 ~ /^astral-sh\/setup-uv@/' | wc -l | tr -d ' ')"
  uses="$(printf '%s\n' "$rows" | awk -F'\t' '$5 ~ /^astral-sh\/setup-uv@/ { print $5; exit }')"
  gate="$(printf '%s\n' "$rows" | awk -F'\t' '$5 ~ /^astral-sh\/setup-uv@/ { print $4; exit }')"
  i_deps="$(printf '%s\n' "$rows" | awk -F'\t' '$3 == "deps" { print $1; exit }')"
  i_uv="$(printf '%s\n' "$rows" | awk -F'\t' '$5 ~ /^astral-sh\/setup-uv@/ { print $1; exit }')"
  i_sync="$(printf '%s\n' "$rows" | awk -F'\t' '$7 == "uv sync --frozen" { print $1; exit }')"
  CASE_DETAIL="count=$n uses=[$uses] if=[$gate] order deps=$i_deps setup-uv=$i_uv sync=$i_sync"
  [ "$n" = "1" ] \
    && printf '%s' "$uses" | LC_ALL=C _has -E '^astral-sh/setup-uv@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' \
    && [ "$gate" = "$GATE_UV" ] \
    && [ -n "$i_deps" ] && [ -n "$i_uv" ] && [ -n "$i_sync" ] \
    && [ "$i_deps" -lt "$i_uv" ] && [ "$i_uv" -lt "$i_sync" ]
}
# _shape — a run line with its license deny list folded to <LIST> (T6 owns the list).
_shape() { sed 's/--fail-on="[^"]*"/--fail-on=<LIST>/'; }
case_T4() {   # the uv path: the lockfile, never rewritten, and every tool through uv run
  local f="$1" got="" want=""
  got="$(runs_gated "$f" "$GATE_UV" | _shape)"
  want="$(cat <<'W'
uv sync --frozen
uv pip install ruff pytest pip-audit pip-licenses
uv run --frozen ruff check .
uv run --frozen pytest
uv run --frozen pip-audit
uv run --frozen pip-licenses --fail-on=<LIST>
W
)"
  CASE_DETAIL="uv-gated runs: [$(printf '%s' "$got" | tr '\n' '|')]"
  [ "$got" = "$want" ]
}
case_T5() {   # the requirements.txt path, kept
  local f="$1" got="" want=""
  got="$(runs_gated "$f" "$GATE_PIP" | _shape)"
  want="$(cat <<'W'
pip install -r requirements.txt
pip install ruff pytest pip-audit pip-licenses
ruff check .
pytest
pip-audit
pip-licenses --fail-on=<LIST>
W
)"
  CASE_DETAIL="pip-gated runs: [$(printf '%s' "$got" | tr '\n' '|')]"
  [ "$got" = "$want" ]
}
case_T5b() {  # no step outside the two gates runs an installer or a project tool at the top of its script
  local f="$1" hits=""
  hits="$(steps_tsv "$f" | GU="$GATE_UV" GP="$GATE_PIP" awk -F'\t' '
    $4 != ENVIRON["GU"] && $4 != ENVIRON["GP"] && $7 != "" {
      n = split($7, a, "\037")
      for (i = 1; i <= n; i++) if (a[i] ~ /^(uv|pip|ruff|pytest|pip-audit|pip-licenses)( |$)/) print $2 ": " a[i]
    }')"
  CASE_DETAIL="ungated: [$(printf '%s' "$hits" | tr '\n' '|')]"
  [ -z "$hits" ]
}
case_T6() {   # both license steps carry the deny list the template had before G3
  local f="$1" want="" uv="" pip=""
  want='GNU General Public License v2 (GPLv2);GNU General Public License v3 (GPLv3);GNU Affero General Public License v3 (AGPLv3);GNU Lesser General Public License v2 (LGPLv2);GNU Lesser General Public License v2.1 (LGPLv2.1);GNU Lesser General Public License v3 (LGPLv3);Server Side Public License (SSPL);European Union Public Licence 1.1 (EUPL 1.1);European Union Public Licence 1.2 (EUPL 1.2)'
  uv="$(runs_gated "$f" "$GATE_UV" | sed -n 's/^uv run --frozen pip-licenses --fail-on="\([^"]*\)"$/\1/p')"
  pip="$(runs_gated "$f" "$GATE_PIP" | sed -n 's/^pip-licenses --fail-on="\([^"]*\)"$/\1/p')"
  CASE_DETAIL="uv=[$uv] pip=[$pip]"
  [ "$uv" = "$want" ] && [ "$pip" = "$want" ]
}

echo
echo "=== T — the written workflow ==="
check "T1 the triggers are unchanged: a push to main and pull requests to main" case_T1 "$SG"
check "T2 the workflow is named '$WF_NAME', not CI" case_T2 "$SG"
check "T2b every GitHub CI template carries that name" case_T2b "$REPO_ROOT/templates/pipelines/ci/github"
check "T3 setup-uv is one uv-gated step, pinned by a 40-hex SHA with its version, between the decision and the install" case_T3 "$SG"
check "T4 the uv path runs uv sync --frozen, then every tool through uv run --frozen" case_T4 "$SG"
check "T5 the requirements.txt path is kept" case_T5 "$SG"
check "T5b no step outside the two gates runs an installer or a project tool" case_T5b "$SG"
check "T6 both license steps carry the deny list the template had before G3" case_T6 "$SG"

# ════════════════════════════════════════════════════════════════════════════
# B — the shipped shell, executed
# ════════════════════════════════════════════════════════════════════════════
# _body FILE ID|NAME VALUE — a step's run block, as a script.
_body() {
  local col=3
  [ "$2" = name ] && col=2
  step_field "$1" "$col" "$3" 7 | tr '\037' '\n'
}
# _decide FILE FILES... — run the decision step in a tree holding FILES. Sets
# D_RC, D_OUT (stdout+stderr) and D_GH (what it wrote to GITHUB_OUTPUT).
D_RC=0; D_OUT=""; D_GH=""
_decide() {
  local f="$1" d="" x=""; shift
  d="$(newtmp)"
  _body "$f" id deps > "$d/.step.sh"
  for x in "$@"; do printf 'x\n' > "$d/$x"; done
  : > "$d/.gh-output"
  D_OUT="$( cd "$d" && GITHUB_OUTPUT="$d/.gh-output" bash --noprofile --norc -eo pipefail .step.sh 2>&1 )"; D_RC=$?
  D_GH="$(cat "$d/.gh-output")"
  CASE_DETAIL="files=[$*] rc=$D_RC output=[$D_GH] said=[$(printf '%s' "$D_OUT" | tr '\n' '|')]"
  [ -s "$d/.step.sh" ] || { CASE_DETAIL="no step with id deps"; D_RC=99; }
}
case_B1() { _decide "$1" uv.lock pyproject.toml; [ "$D_RC" -eq 0 ] && [ "$D_GH" = "installer=uv" ]; }
case_B2() { _decide "$1" requirements.txt; [ "$D_RC" -eq 0 ] && [ "$D_GH" = "installer=pip" ]; }
case_B3() { _decide "$1" uv.lock pyproject.toml requirements.txt; [ "$D_RC" -eq 0 ] && [ "$D_GH" = "installer=uv" ]; }
case_B4() {   # neither: a failed step and an ::error:: that names all three files
  _decide "$1"
  [ "$D_RC" -ne 0 ] && [ -z "$D_GH" ] \
    && printf '%s\n' "$D_OUT" | _has '^::error::.*Missing: requirements.txt, uv.lock, pyproject.toml\.$'
}
case_B5() {   # uv.lock without pyproject.toml is not a uv project, and the error names what is missing
  _decide "$1" uv.lock
  [ "$D_RC" -ne 0 ] && [ -z "$D_GH" ] \
    && printf '%s\n' "$D_OUT" | _has '^::error::.*Missing: requirements.txt, pyproject.toml\.$'
}
case_B6() {   # pyproject.toml alone (a poetry or plain project): the error names uv.lock and requirements.txt
  _decide "$1" pyproject.toml
  [ "$D_RC" -ne 0 ] && [ -z "$D_GH" ] \
    && printf '%s\n' "$D_OUT" | _has '^::error::.*Missing: requirements.txt, uv.lock\.$'
}
# _integrity FILE INSTALLER UV_RC FILES... — run the lockfile step with a stub
# uv first on PATH. Sets I_RC, I_OUT and I_CALLS (the stub's argv, one per line).
I_RC=0; I_OUT=""; I_CALLS=""
_integrity() {
  local f="$1" inst="$2" urc="$3" d="" s="" x=""; shift 3
  d="$(newtmp)"; s="$(newtmp)"
  _body "$f" name "Security - Lockfile integrity" > "$d/.step.sh"
  for x in "$@"; do printf 'x\n' > "$d/$x"; done
  printf '#!/bin/sh\necho "$*" >> "%s/calls"\nexit %s\n' "$s" "$urc" > "$s/uv"; chmod +x "$s/uv"
  I_OUT="$( cd "$d" && INSTALLER="$inst" PATH="$s:$PATH" bash --noprofile --norc -eo pipefail .step.sh 2>&1 )"; I_RC=$?
  I_CALLS="$(cat "$s/calls" 2>/dev/null)"
  CASE_DETAIL="installer=$inst uv-rc=$urc rc=$I_RC uv-calls=[$(printf '%s' "$I_CALLS" | tr '\n' '|')] said=[$(printf '%s' "$I_OUT" | tr '\n' '|')]"
}
case_B7() {   # the lockfile check reads the decision, checks uv.lock with --check (never rewrites it), and warns when it fails
  local f="$1" envs="" bad=""
  envs="$(step_field "$f" 2 "Security - Lockfile integrity" 6 | tr '\037' '\n')"
  printf '%s\n' "$envs" | _has -xF 'INSTALLER: ${{ steps.deps.outputs.installer }}' || bad="$bad [INSTALLER is not mapped from the decision: env=$(printf '%s' "$envs" | tr '\n' '|')]"
  _integrity "$f" uv 0 uv.lock pyproject.toml
  [ "$I_RC" -eq 0 ] && [ "$I_CALLS" = "lock --check" ] || bad="$bad [clean: $CASE_DETAIL]"
  printf '%s' "$I_OUT" | _has 'No hash-pinned lockfile' && bad="$bad [a uv project is told it has no hash-pinned lockfile]"
  _integrity "$f" uv 1 uv.lock pyproject.toml
  [ "$I_RC" -eq 0 ] && printf '%s\n' "$I_OUT" | _has '^::warning::uv lock --check failed' || bad="$bad [stale: $CASE_DETAIL]"
  _integrity "$f" pip 0 requirements.txt
  [ -z "$I_CALLS" ] && printf '%s\n' "$I_OUT" | _has '^::warning::No hash-pinned lockfile found' || bad="$bad [pip: $CASE_DETAIL]"
  CASE_DETAIL="$bad"
  [ -z "$bad" ]
}

echo
echo "=== B — the shipped shell, executed as Actions runs it ==="
check "B1 uv.lock with pyproject.toml: installer=uv" case_B1 "$SG"
check "B2 requirements.txt: installer=pip" case_B2 "$SG"
check "B3 all three files: uv wins" case_B3 "$SG"
check "B4 none of them: the step fails with an ::error:: naming requirements.txt, uv.lock and pyproject.toml" case_B4 "$SG"
check "B5 uv.lock alone: not a uv project; the ::error:: names requirements.txt and pyproject.toml" case_B5 "$SG"
check "B6 pyproject.toml alone: the ::error:: names requirements.txt and uv.lock" case_B6 "$SG"
check "B7 the lockfile check: uv lock --check for a uv project, a warning when it fails, the old arms for the rest" case_B7 "$SG"

# ════════════════════════════════════════════════════════════════════════════
# D — the guides
# ════════════════════════════════════════════════════════════════════════════
case_D1() {   # docs/adoption.md's table row for GitHub
  local f="$1" row=""
  row="$(command grep -F '| GitHub | `.github/workflows/solo-gates.yml` |' "$f")"
  CASE_DETAIL="row=[$row]"
  [ "$(printf '%s\n' "$row" | command grep -c .)" -eq 1 ] \
    && printf '%s' "$row" | _has -F 'on a push to `main` and on pull requests to `main`' \
    && printf '%s' "$row" | _has -F "**$WF_NAME**" \
    && ! printf '%s' "$row" | _has 'next push'
}
case_D2() {   # docs/user-guide.md's Tier 1 sentence
  local f="$1" line=""
  line="$(command grep -F '**Tier 1 — Mechanically enforced (CI pipeline).**' "$f")"
  CASE_DETAIL="line=[$line]"
  printf '%s' "$line" | _has -F 'on GitHub, on a push to `main` and on pull requests to `main`' \
    && ! printf '%s' "$line" | _has -F 'run automatically on every push'
}

echo
echo "=== D — the guides ==="
check "D1 docs/adoption.md: the GitHub row says a push to main and pull requests to main, and the name" case_D1 "$REPO_ROOT/docs/adoption.md"
check "D2 docs/user-guide.md: Tier 1 says when GitHub runs it" case_D2 "$REPO_ROOT/docs/user-guide.md"

# ════════════════════════════════════════════════════════════════════════════
# M — mutants
# ════════════════════════════════════════════════════════════════════════════
# mut FILE ANCHOR OLD NEW — on the first line at or after the ONE line holding
# ANCHOR that holds OLD, replace OLD with NEW (literal strings, no regex, no
# `&` rule). Refuses unless exactly one line changed and NEW is on it.
mut() {
  local f="$1" anchor="$2" old="$3" new="$4" n="" changed=""
  n="$(A="$anchor" awk 'index($0, ENVIRON["A"]) { c++ } END { print c + 0 }' "$f")"
  [ "$n" = "1" ] || { echo "anchor '$anchor' is on $n line(s) of ${f##*/} (need 1)"; return 1; }
  cp "$f" "$f.orig" || return 1
  A="$anchor" O="$old" N="$new" awk '
    BEGIN { a = ENVIRON["A"]; o = ENVIRON["O"]; nw = ENVIRON["N"] }
    !seen && index($0, a) { seen = 1 }
    seen && !done && (i = index($0, o)) { $0 = substr($0, 1, i - 1) nw substr($0, i + length(o)); done = 1 }
    { print }
    END { if (!done) exit 3 }' "$f.orig" > "$f" || { cp "$f.orig" "$f"; echo "'$old' is not on or after the anchor"; return 1; }
  changed="$(diff "$f.orig" "$f" | command grep -c '^>')"
  [ "$changed" = "1" ] || { echo "$changed line(s) changed (need 1)"; return 1; }
  [ -z "$new" ] || N="$new" awk 'index($0, ENVIRON["N"]) { f = 1 } END { exit !f }' "$f" || { echo "the replacement did not land"; return 1; }
  return 0
}
# tmutant ID REL ANCHOR OLD NEW KILLER WHAT — edit a copy of REL; KILLER must fail on it.
# REL's copy keeps its directory's siblings for a case that reads the directory.
tmutant() {
  local id="$1" rel="$2" anchor="$3" old="$4" new="$5" killer="$6" what="$7" d="" why="" arg=""
  d="$(newtmp)"
  mkdir -p "$d/$(dirname "$rel")" || { fail_ "$id" "could not make a copy"; return; }
  if [ "$killer" = case_T2b ]; then
    cp -Rp "$REPO_ROOT/$(dirname "$rel")/." "$d/$(dirname "$rel")/" || { fail_ "$id" "could not copy $(dirname "$rel")"; return; }
  else
    cp -p "$REPO_ROOT/$rel" "$d/$rel" || { fail_ "$id" "could not copy $rel"; return; }
  fi
  why="$(mut "$d/$rel" "$anchor" "$old" "$new")" || { fail_ "$id" "mutant did not land: $why"; return; }
  rm -f "$d/$rel.orig"
  arg="$d/$rel"
  [ "$killer" = case_T2b ] && arg="$d/$(dirname "$rel")"
  _killed "$id" "$killer" "$what" "$arg"
}
# _killed ID KILLER WHAT ARG — KILLER must fail on ARG.
_killed() {
  CASE_DETAIL=""
  if "$2" "$4"; then
    fail_ "$1" "$3 — SURVIVED: ${2#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$1 (MUTATION) — $3: killed by ${2#case_}"
  fi
}
# tswap ID REL ANCHOR1 ANCHOR2 KILLER WHAT — swap the ONE line holding ANCHOR1
# with the ONE line holding ANCHOR2 in a copy of REL (exactly two lines change).
tswap() {
  local id="$1" rel="$2" a1="$3" a2="$4" killer="$5" what="$6" d="" f="" n1="" n2="" changed=""
  d="$(newtmp)"; f="$d/${rel##*/}"
  cp -p "$REPO_ROOT/$rel" "$f" || { fail_ "$id" "could not copy $rel"; return; }
  n1="$(A="$a1" awk 'index($0, ENVIRON["A"]) { c++ } END { print c + 0 }' "$f")"
  n2="$(A="$a2" awk 'index($0, ENVIRON["A"]) { c++ } END { print c + 0 }' "$f")"
  [ "$n1" = "1" ] && [ "$n2" = "1" ] || { fail_ "$id" "mutant did not land: anchors on $n1 and $n2 line(s) (need 1 each)"; return; }
  A1="$a1" A2="$a2" awk '
    { line[NR] = $0 } index($0, ENVIRON["A1"]) { i = NR } index($0, ENVIRON["A2"]) { j = NR }
    END { t = line[i]; line[i] = line[j]; line[j] = t; for (k = 1; k <= NR; k++) print line[k] }' "$f" > "$f.mut" || { fail_ "$id" "swap failed"; return; }
  changed="$(diff "$f" "$f.mut" | command grep -c '^>')"
  [ "$changed" = "2" ] || { fail_ "$id" "mutant did not land: $changed line(s) changed (need 2)"; return; }
  mv "$f.mut" "$f"
  _killed "$id" "$killer" "$what" "$f"
}
# amutant ID REL ANCHOR OLD NEW KILLER WHAT — the same in a mirror of the tree,
# then a real uv adoption driven from the mirror.
amutant() {
  local id="$1" rel="$2" anchor="$3" old="$4" new="$5" killer="$6" what="$7" m="" why="" p=""
  m="$(newtmp)/mirror"
  mkdir -p "$m" && cp -Rp "$REPO_ROOT/scripts" "$REPO_ROOT/templates" "$REPO_ROOT/init.sh" "$REPO_ROOT/README.md" "$m/" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mut "$m/$rel" "$anchor" "$old" "$new")" || { fail_ "$id" "mutant did not land: $why"; return; }
  rm -f "$m/$rel.orig"
  why="$(bash -n "$m/$rel" 2>&1)" || { fail_ "$id" "the mutant does not parse — a kill would prove nothing: $why"; return; }
  _adopted "$m" uv "m-$id" || { fail_ "$id" "fixture"; return; }
  p="$ADOPTED_P"
  CASE_DETAIL=""
  if "$killer" "$REPO_ROOT" "$p" "m-$id"; then
    fail_ "$id" "$what — SURVIVED: ${killer#_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#_} (adoption driven from the mirror)"
  fi
}
_a3_on() { _a_words "$WORK/$3.out"; }

echo
echo "=== M — mutants ==="
T=templates/pipelines/ci/github/python.yml
AC=scripts/lib/adopt/adopt-ci.sh
amutant MA1 "$AC" "python) printf 'python.yml'" "python) printf 'python.yml'" "python) printf 'other.yml'" _a_written "adoption installs another language's template for a Python project"
amutant MA2 "$AC" '# BL-318-G3-RUNS-WHEN' 'GitHub runs it on a push to main and on pull requests to main' 'GitHub runs every workflow in .github/workflows, so it runs from your next push' _a3_on "adoption says the framework's CI runs from your next push again (the dogfood wording)"
UG=docs/user-guide.md
AD=docs/adoption.md
GITLEAKS_ANCHOR='- name: Security - Secret detection (gitleaks)'
tmutant MT1  "$T" '  push:' 'branches: [main]' "branches: ['**']" case_T1 "a push to any branch runs it (a trigger change G3 does not make)"
tmutant MT2  "$T" "name: $WF_NAME" "name: $WF_NAME" 'name: CI' case_T2 "the framework's workflow is named CI again (the dogfood collision)"
tmutant MT2b templates/pipelines/ci/github/typescript.yml "name: $WF_NAME" "name: $WF_NAME" 'name: CI' case_T2b "one sibling template keeps the name CI"
tmutant MT3  "$T" 'astral-sh/setup-uv@' 'c18668ad3cf93ea998bef934396af7bb5c839dc7 # v10.2.0' 'v10.2.0' case_T3 "setup-uv pinned by a tag, not a commit SHA"
tmutant MT3b "$T" '- name: Install uv' "installer == 'uv'" "installer == 'pip'" case_T3 "setup-uv runs for the requirements.txt path instead"
tswap   MT3c "$T" 'uses: astral-sh/setup-uv@' 'run: uv sync --frozen' case_T3 "uv sync runs before setup-uv has installed uv"
tmutant MT4  "$T" '- name: Install dependencies (uv)' 'uv sync --frozen' 'uv sync' case_T4 "uv sync without --frozen, which may rewrite uv.lock"
tmutant MT4b "$T" '- name: Test (uv)' 'run: uv run --frozen pytest' 'run: pytest' case_T4 "a uv project's tests run outside its environment"
tmutant MT4c "$T" '- name: Security - License check (uv)' 'uv run --frozen pip-licenses' 'pip-licenses' case_T4 "a uv project's licenses are read outside its environment"
tmutant MT5  "$T" '- name: Install dependencies (pip)' 'pip install -r requirements.txt' 'pip install .' case_T5 "the requirements.txt install is dropped"
tmutant MT5b "$T" "$GITLEAKS_ANCHOR" 'GITLEAKS_VERSION=8.30.1' 'pip install -r requirements.txt' case_T5b "an ungated step installs from requirements.txt"
tmutant MT6  "$T" '- name: Security - License check (uv)' 'GNU Affero General Public License v3 (AGPLv3);' '' case_T6 "AGPL drops off the uv path's license deny list"
tmutant MT6b "$T" '- name: Security - License check (pip)' 'Server Side Public License (SSPL);' '' case_T6 "SSPL drops off the pip path's license deny list"
tmutant MB1  "$T" 'if [ -f uv.lock ] && [ -f pyproject.toml ]; then' 'if [ -f uv.lock ] && [ -f pyproject.toml ]; then' 'if [ -f uv.lock ]; then' case_B5 "uv.lock alone counts as a uv project"
tmutant MB2  "$T" 'if [ -f uv.lock ] && [ -f pyproject.toml ]; then' '[ -f pyproject.toml ]; then' '[ -f pyproject.toml ] && [ ! -f requirements.txt ]; then' case_B3 "requirements.txt wins over uv.lock"
tmutant MB3  "$T" 'missing="requirements.txt"' 'exit 1' 'exit 0' case_B4 "neither file: the step passes and the job installs nothing"
tmutant MB4  "$T" 'missing="requirements.txt"' 'echo "::error::' 'echo "::warning::' case_B4 "neither file: a warning, not an error"
tmutant MB5  "$T" 'missing="requirements.txt"' '[ -f uv.lock ] || missing="$missing, uv.lock"' ':' case_B6 "the error does not name a missing uv.lock"
tmutant MB6  "$T" 'id: deps' 'echo "installer=uv"' 'echo "installer=pip"' case_B1 "a uv project is sent down the pip path"
tmutant MB7  "$T" 'id: deps' 'elif [ -f requirements.txt ]; then' 'elif [ -f requirements.in ]; then' case_B2 "a requirements.txt project is not recognised"
tmutant MB8  "$T" 'if [ "$INSTALLER" = "uv" ]; then' 'uv lock --check ||' 'uv lock ||' case_B7 "the lockfile check rewrites uv.lock"
tmutant MB9  "$T" '- name: Security - Lockfile integrity' 'INSTALLER: ${{ steps.deps.outputs.installer }}' 'INSTALLER: uv' case_B7 "the lockfile check does not read the decision"
tmutant MD1  "$AD" '| GitHub | `.github/workflows/solo-gates.yml` |' 'Yes, on a push to `main` and on pull requests to `main`' 'Yes, from your next push' case_D1 "the guide says the framework's CI runs from your next push again"
tmutant MD2  "$UG" '**Tier 1 — Mechanically enforced (CI pipeline).**' 'in your CI: on GitHub, on a push to `main` and on pull requests to `main` (a push to any other branch runs nothing); on GitLab and Bitbucket, on every push.' 'on every push.' case_D2 "the user guide says every push again"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

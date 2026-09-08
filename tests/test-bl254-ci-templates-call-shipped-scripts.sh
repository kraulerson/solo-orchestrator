#!/usr/bin/env bash
# tests/test-bl254-ci-templates-call-shipped-scripts.sh
#
# `## BL-254:` — A GENERATED CI PIPELINE MAY ONLY CALL SCRIPTS THE SCAFFOLD
# SHIPS, AND A GOVERNANCE CHECK MAY NOT SWALLOW ITS OWN FAILURE.
#
# Fourteen CI templates ran `bash scripts/check-changelog.sh` and ten ran
# `bash scripts/check-session-state.sh`, every one as
# `… 2>/dev/null || true`. init.sh shipped neither — zero `cp` lines — so in
# every generated project both steps were silent no-ops that the user guide
# listed as "Automatic (CI)". The `|| true` did double duty: it hid the
# missing file, AND it made the scripts' documented strict mode
# (`SOIF_STRICT_CHANGELOG=true` / `SOIF_STRICT_SESSION=true` → exit 1) a no-op
# even once the file existed. Found by the 2026-09-07 codebase review (G0,
# R4), reproduced on main c61edb1 by its second pass.
#
# Two invariants, both derived from the repo's own single source of truth
# for what ships — `scripts/lib/scaffold-shipped-set.sh` reading init.sh's
# literal `cp "$SCRIPT_DIR/scripts/…"` lines — never from a hand list:
#   T1  every `bash scripts/<x>.sh` a CI template invokes is in the shipped set
#   T2  neither governance script's invocation ends in `|| true`
#   T3  init.sh ships both governance scripts (the specific instance of T1,
#       named so the failure reads as the defect it was)
# Each has a mutant on a MIRROR of the framework, never the real tree.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIPPED_LIB="$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

if [ ! -f "$SHIPPED_LIB" ]; then
  echo "  [FAIL] setup — $SHIPPED_LIB not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi
# shellcheck source=/dev/null
. "$SHIPPED_LIB"

# shipped_set <init.sh> <scripts_dir> → one "scripts/<rel>" per line
shipped_set() { soif_parse_shipped_scripts "$1" "$2"; }

# template_calls <templates_dir> → one "scripts/<rel>" per line, every script a
# CI template invokes — in any of the spellings a step can use: `bash
# scripts/x.sh`, `sh scripts/x.sh`, `./scripts/x.sh`, `bash ./scripts/x.sh`. A
# first cut matched `bash scripts/` only; under review a template calling an
# unshipped script as `sh scripts/…` or `./scripts/…` slipped past T1. No
# template uses those forms today, which is exactly when a parser should be
# widened rather than after one does.
#
# COMMENTS ARE STRIPPED FIRST. Widening the spellings made the interpreter
# optional, and the very next review showed the parser reading `#     scripts/
# check-gate.sh --setup-ci-token` — comment text — as an invocation: a false
# RED on a documentation edit (`## BL-224:`'s over-matching class). A shell
# comment is `#` at line start or after whitespace; everything from there to
# end-of-line is dropped before the match. A quoted path (`bash "scripts/x.sh"`)
# is also accepted, since it is an ordinary spelling; a variable-prefixed path
# (`$GITHUB_WORKSPACE/scripts/x.sh`) is deliberately NOT — resolving shell
# variables is the road back to over-matching.
template_calls() {
  find "$1" -name '*.yml' -type f -print0 2>/dev/null | xargs -0 cat 2>/dev/null \
    | sed -E 's/(^|[[:space:]])#.*$//' \
    | grep -oE '(^|[[:space:]])((bash|sh)[[:space:]]+["'"'"']?)?\.?/?scripts/[A-Za-z0-9_./-]+\.sh' \
    | sed -E 's/^[[:space:]]*//; s/^(bash|sh)[[:space:]]+["'"'"']?//; s#^\./##; s#^/##' | LC_ALL=C sort -u
}

# governance_gaps <templates_dir> → one line per CI template MISSING a
# governance step it must carry. T1 (a subset check) and T2 (an absence
# check) are both monotone in the "less content" direction, so under review
# DELETING all 24 steps passed the suite 8/0. This is the floor that stops the
# fix being silently undone, or a new GitHub template being added without the
# steps.
#
# GITHUB IS DERIVED, GITLAB IS A CENSUS — and the difference is stated rather
# than papered over. Every ci/github/*.yml carries both steps, so that arm
# walks the file list. Only FOUR of the ten ci/gitlab/*.yml carry the
# changelog step (go, python, rust, typescript — all ten have a governance
# job, six never had this step in it) and no Bitbucket template carries it
# at all: a pre-existing asymmetry this suite did not create and does not
# widen (`## BL-254:` residual 6). A first cut asserted "every GitLab template"
# and failed on six files for a claim that was never true. The GitLab arm
# therefore pins the four that DO carry it, by name, in bl147's
# documented-census idiom, so the fix cannot be undone in any of them.
GITLAB_CHANGELOG_CENSUS="go python rust typescript"
governance_gaps() {
  local d="$1" f n
  for f in "$d"/ci/github/*.yml; do
    [ -f "$f" ] || continue
    grep -qE '^[[:space:]]*run: bash scripts/check-changelog\.sh$' "$f"     || printf '%s: missing check-changelog step\n' "${f#$d/}"
    grep -qE '^[[:space:]]*run: bash scripts/check-session-state\.sh$' "$f" || printf '%s: missing check-session-state step\n' "${f#$d/}"
  done
  for n in $GITLAB_CHANGELOG_CENSUS; do
    f="$d/ci/gitlab/$n.yml"
    [ -f "$f" ] || { printf 'ci/gitlab/%s.yml: census file absent\n' "$n"; continue; }
    grep -qE '^[[:space:]]*- bash scripts/check-changelog\.sh$' "$f" || printf '%s: missing check-changelog step\n' "${f#$d/}"
  done
}

# swallowed_governance <templates_dir> → lines where a governance script's
# failure is discarded with `|| true`
swallowed_governance() {
  grep -rnE 'scripts/(check-changelog|check-session-state)\.sh[^|]*\|\| true' "$1" --include='*.yml' 2>/dev/null
}

# mk_mirror <dir> — init.sh + scripts + templates only; enough for the parser
mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -p "$REPO_ROOT/init.sh" "$m/" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  cp -Rp "$REPO_ROOT/templates" "$m/" || return 1
  return 0
}

echo "=== T — the invariants on the real tree ==="

SHIPPED="$(shipped_set "$REPO_ROOT/init.sh" "$REPO_ROOT/scripts")"
CALLS="$(template_calls "$REPO_ROOT/templates/pipelines")"
n_shipped=$(printf '%s\n' "$SHIPPED" | grep -c .)
n_calls=$(printf '%s\n' "$CALLS" | grep -c .)
[ "$(_num "$n_shipped")" -gt 0 ] || fail_ "setup" "the derived shipped set is empty — soif_parse_shipped_scripts found no cp lines"
[ "$(_num "$n_calls")" -gt 0 ]   || fail_ "setup" "no CI template invokes any scripts/*.sh — the call parser found nothing"

# T1 — calls ⊆ shipped
phantoms="$(LC_ALL=C comm -23 <(printf '%s\n' "$CALLS") <(printf '%s\n' "$SHIPPED" | LC_ALL=C sort -u))"
if [ -z "$phantoms" ]; then
  pass "T1 — every script a CI template invokes ($n_calls distinct) is in the shipped set ($n_shipped)"
else
  fail_ "T1" "CI templates invoke scripts the scaffold never ships: $(printf '%s' "$phantoms" | tr '\n' ' ')"
fi

# T2 — no swallowed governance step
sw="$(swallowed_governance "$REPO_ROOT/templates/pipelines")"
if [ -z "$sw" ]; then
  pass "T2 — no CI template discards a governance check's exit status with '|| true'"
else
  fail_ "T2" "$(printf '%s' "$sw" | grep -c .) template step(s) swallow a governance check: $(printf '%s' "$sw" | head -3 | sed 's|.*templates/pipelines/||' | tr '\n' ' ')…"
fi

# T3 — the two named scripts ship
for g in check-changelog.sh check-session-state.sh; do
  if printf '%s\n' "$SHIPPED" | grep -qx "scripts/$g"; then
    pass "T3 — init.sh ships scripts/$g"
  else
    fail_ "T3" "init.sh does not ship scripts/$g — every generated CI step that calls it is a no-op"
  fi
done

# T4 — the governance steps EXIST, in every template that must carry them
n_gh=$(ls "$REPO_ROOT"/templates/pipelines/ci/github/*.yml 2>/dev/null | wc -l | tr -d ' ')
n_gl=$(ls "$REPO_ROOT"/templates/pipelines/ci/gitlab/*.yml 2>/dev/null | wc -l | tr -d ' ')
gaps="$(governance_gaps "$REPO_ROOT/templates/pipelines")"
if [ "$(_num "$n_gh")" -gt 0 ] && [ "$(_num "$n_gl")" -gt 0 ] && [ -z "$gaps" ]; then
  pass "T4 — every GitHub CI template ($n_gh) carries both governance steps; the four census GitLab templates ($GITLAB_CHANGELOG_CENSUS) carry the changelog step"
else
  fail_ "T4" "governance steps missing (github=$n_gh gitlab=$n_gl): $(printf '%s' "$gaps" | tr '\n' ';' | cut -c1-200)"
fi

echo "=== MT — mutation proofs on a mirror ==="

# MT1 — remove one governance cp line from the mirror's init.sh: T1 and T3
# must both see the phantom.
MT1="$(newtmp)/fw"
if ! mk_mirror "$MT1"; then
  fail_ "MT1 setup" "could not mirror the framework"
else
  before="$(mktemp)"; cp "$MT1/init.sh" "$before"
  grep -v 'cp "$SCRIPT_DIR/scripts/check-changelog.sh"' "$before" > "$MT1/init.sh"
  if [ "$(_changed_lines "$before" "$MT1/init.sh")" -lt 1 ]; then
    fail_ "MT1 setup" "the mirror's init.sh had no cp line for check-changelog.sh to remove — is T3 passing for another reason?"
  elif ! bash -n "$MT1/init.sh" 2>/dev/null; then
    fail_ "MT1 setup" "mutated init.sh does not parse"
  else
    m_shipped="$(shipped_set "$MT1/init.sh" "$MT1/scripts")"
    m_calls="$(template_calls "$MT1/templates/pipelines")"
    m_ph="$(LC_ALL=C comm -23 <(printf '%s\n' "$m_calls") <(printf '%s\n' "$m_shipped" | LC_ALL=C sort -u))"
    if printf '%s\n' "$m_ph" | grep -qx "scripts/check-changelog.sh"; then
      pass "MT1 (MUTATION) — with the cp line removed, T1's derivation names check-changelog.sh as a phantom again"
    else
      fail_ "MT1 (MUTATION)" "removing the cp line changed nothing — T1 is not reading the shipped set it claims to"
    fi
  fi
fi

# MT3 — a template calling an UNSHIPPED script in each alternative spelling
# must be named by T1's parser. These are the two forms the review slipped
# past a first cut with.
MT3="$(newtmp)/fw"
if ! mk_mirror "$MT3"; then
  fail_ "MT3 setup" "could not mirror the framework"
else
  tgt="$MT3/templates/pipelines/ci/github/typescript.yml"
  printf '      - name: Probe A\n        run: sh scripts/never-shipped-a.sh\n      - name: Probe B\n        run: ./scripts/never-shipped-b.sh\n      - name: Probe C\n        run: bash "scripts/never-shipped-c.sh"\n        # scripts/never-shipped-in-a-comment.sh is only mentioned here\n' >> "$tgt"
  m_calls="$(template_calls "$MT3/templates/pipelines")"
  for probe in never-shipped-a never-shipped-b never-shipped-c; do
    printf '%s\n' "$m_calls" | grep -qx "scripts/$probe.sh" \
      && pass "MT3 (MUTATION) — a template invoking scripts/$probe.sh in an alternative spelling is seen by T1's parser" \
      || fail_ "MT3 (MUTATION)" "T1's parser missed scripts/$probe.sh — an unshipped script called that way would pass"
  done
  # and a path that appears ONLY in a comment must NOT register (the false-RED the review found)
  printf '%s\n' "$m_calls" | grep -qx "scripts/never-shipped-in-a-comment.sh" \
    && fail_ "MT3b" "T1's parser read a COMMENT as an invocation — a documentation edit would block a PR" \
    || pass "MT3b — a script named only in a comment is not read as an invocation"
fi

# MT5 — delete one governance step from a mirrored template: T4 must name it.
MT5="$(newtmp)/fw"
if ! mk_mirror "$MT5"; then
  fail_ "MT5 setup" "could not mirror the framework"
else
  tgt="$MT5/templates/pipelines/ci/github/go.yml"
  before="$(mktemp)"; cp "$tgt" "$before"
  grep -v 'run: bash scripts/check-session-state.sh$' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 1 ]; then
    fail_ "MT5 setup" "the mirror's go.yml had no session-state step to delete — is T4 passing for another reason?"
  else
    m_gaps="$(governance_gaps "$MT5/templates/pipelines")"
    printf '%s' "$m_gaps" | grep -q "ci/github/go.yml: missing check-session-state step" \
      && pass "MT5 (MUTATION) — with one governance step deleted, T4 names the template and the step" \
      || fail_ "MT5 (MUTATION)" "deleting a governance step changed nothing — T4 is not deriving what it claims to"
  fi
fi

# MT2 — re-add `|| true` to one governance step in the mirror: T2 must fire.
MT2="$(newtmp)/fw"
if ! mk_mirror "$MT2"; then
  fail_ "MT2 setup" "could not mirror the framework"
else
  tgt="$MT2/templates/pipelines/ci/github/typescript.yml"
  before="$(mktemp)"; cp "$tgt" "$before"
  # a delimiter absent from both sides; `|` is IN the replacement, so it cannot be the delimiter
  sed 's#run: bash scripts/check-changelog.sh$#run: bash scripts/check-changelog.sh 2>/dev/null || true#' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ]; then
    fail_ "MT2 setup" "the mutation did not apply — the governance line is not in the shape this suite expects"
  else
    m_sw="$(swallowed_governance "$MT2/templates/pipelines")"
    if [ -n "$m_sw" ]; then
      pass "MT2 (MUTATION) — with '|| true' restored on one step, T2 fires again"
    else
      fail_ "MT2 (MUTATION)" "restoring '|| true' changed nothing — T2 is not matching what it claims to"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1

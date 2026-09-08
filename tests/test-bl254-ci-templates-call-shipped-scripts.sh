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
# CI template invokes with `bash scripts/…`
template_calls() {
  grep -rhoE 'bash scripts/[A-Za-z0-9_./-]+\.sh' "$1" --include='*.yml' 2>/dev/null \
    | sed 's/^bash //' | LC_ALL=C sort -u
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

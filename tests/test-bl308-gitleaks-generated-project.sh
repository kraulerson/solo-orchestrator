#!/usr/bin/env bash
# tests/test-bl308-gitleaks-generated-project.sh — a project born from init.sh
# passes the exact secret-detection scan its own generated CI runs (## BL-308:).
#
# The unit-lane sibling (tests/test-bl308-gitleaks-vendored-clean.sh) scans the
# shipped surface in THIS repo with `gitleaks dir`. This suite closes the gap
# between that and the operator's first pull request: it generates a project,
# then runs `gitleaks git --redact --exit-code 1` over the project's history,
# which is the step every generated ci.yml carries (`# BL-151` in
# templates/pipelines/ci/github/*.yml). Invokes init.sh, so it lives in the
# full lane only. P1/P2 pin the scan; A1/A2 pin the gitleaks-absent posture
# by re-running this file without gitleaks, which exits before init.sh runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

command -v jq >/dev/null 2>&1 || {
  echo "jq is required for tests/test-bl308-gitleaks-generated-project.sh" >&2; exit 2; }

# GITLEAKS-ABSENT IS A SKIP LOCALLY AND A FAILURE IN CI (the ## BL-288: posture).
HAVE_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1
GITLEAKS_ABSENT_IS_FATAL=0
[ -n "${CI:-}" ] && GITLEAKS_ABSENT_IS_FATAL=1

TMPS=""
cleanup() { [ -n "$TMPS" ] && rm -rf $TMPS; return 0; }
trap cleanup EXIT INT TERM
newtmp() { local d; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s\n' "$d"; }

# The PATH mirror from tests/test-bl112-commit-enforcement.sh, for gitleaks: each
# PATH entry holding it becomes a directory of symlinks to everything else in it.
build_nogitleaks_path() {
  local mirrors="$1" n=0 d np="" entry base
  mkdir -p "$mirrors"
  printf '%s' "$PATH" | tr ':' '\n' > "$mirrors/.pathlist"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -x "$d/gitleaks" ]; then
      n=$((n + 1))
      mkdir -p "$mirrors/$n"
      for entry in "$d"/*; do
        [ -e "$entry" ] || continue           # bash 3.2 has no nullglob
        base="${entry##*/}"
        [ "$base" = "gitleaks" ] && continue
        ln -sf "$entry" "$mirrors/$n/$base" 2>/dev/null || true
      done
      np="${np:+$np:}$mirrors/$n"
    else
      np="${np:+$np:}$d"
    fi
  done < "$mirrors/.pathlist"
  printf '%s\n' "$np"
}

if [ "$HAVE_GITLEAKS" -eq 0 ]; then
  if [ "$GITLEAKS_ABSENT_IS_FATAL" -eq 1 ]; then
    fail_ "setup" "gitleaks is not installed and CI is set — this suite is a real scan of a real project; a green check credited with a scan that never ran is what it exists to prevent"
  else
    skip_ "the whole suite" "gitleaks not installed (install it to run BL-308's generated-project proof locally)"
  fi
else
  D="$(newtmp)"
  PROJ="$D/bl308proj"
  # The measured case: organizational, production, typescript/web, no remote.
  # "$BASH" so the installer runs under the interpreter running this suite.
  RC=0
  OUT="$( cd "$REPO_ROOT" && "$BASH" ./init.sh --non-interactive \
            --project bl308proj \
            --platform web \
            --deployment organizational \
            --gov-mode production \
            --language typescript \
            --git-host github \
            --visibility private \
            --project-dir "$PROJ" \
            --no-remote-creation 2>&1 )" || RC=$?
  if [ "$RC" -ne 0 ] || [ ! -d "$PROJ/.git" ]; then
    fail_ "setup" "init.sh rc=$RC or no repository at $PROJ; tail: $(echo "$OUT" | tail -5 | tr '\n' ';')"
  else
    # ── P1: the generated ci.yml still carries the scan this suite reproduces ─
    ci="$PROJ/.github/workflows/ci.yml"
    ci_hits=0
    [ -f "$ci" ] && ci_hits=$(grep -c 'gitleaks git --redact --exit-code 1' "$ci" || true)
    case "$ci_hits" in ''|*[!0-9]*) ci_hits=0 ;; esac
    if [ "$ci_hits" -ge 1 ]; then
      pass "P1: the generated ci.yml runs 'gitleaks git --redact --exit-code 1' — P2 reproduces that step"
    else
      fail_ "P1" "the generated ci.yml does not carry 'gitleaks git --redact --exit-code 1' (hits=$ci_hits) — P2 no longer reproduces what CI runs; update both"
    fi

    # ── P2: that scan, over the generated project's history, is clean ───────
    rc=0
    ( cd "$PROJ" && gitleaks git --no-banner --redact --exit-code 1 \
        --report-format json --report-path "$D/git.json" . ) >/dev/null 2>&1 || rc=$?
    [ -s "$D/git.json" ] || printf '[]\n' > "$D/git.json"
    n=$(jq -r 'length' "$D/git.json")
    commits=$(cd "$PROJ" && git rev-list --count HEAD)
    if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ] && [ "$commits" -ge 1 ]; then
      pass "P2: gitleaks git over the generated project ($commits commit(s)) reports 0 findings, rc 0"
    else
      fail_ "P2" "rc=$rc findings=$n commits=$commits — the project's first PR is red at secret detection: $(jq -r '.[] | "\(.RuleID) \(.File):\(.StartLine) \(.Match)"' "$D/git.json" | tr '\n' ';')"
    fi
  fi
fi

# ── A1/A2: the gitleaks-absent posture (## BL-288:) ──────────────────────
# With gitleaks off PATH this suite must skip while CI is unset and fail its
# setup while CI is set. Each case re-runs this file as a child with gitleaks
# shadowed off PATH; the child skips these cases so it does not recurse.
if [ -z "${BL308_POSTURE_CHILD:-}" ]; then
  A="$(newtmp)"
  np=$(build_nogitleaks_path "$A/mirrors") || np=""
  # A fresh shell answers, so this one's command hash cannot.
  if [ -z "$np" ] || env PATH="$np" "$BASH" -c 'command -v gitleaks' >/dev/null 2>&1; then
    fail_ "A1/A2 setup" "could not build a PATH without gitleaks, so the absent posture cannot be measured"
  else
    rc=0
    env -u CI PATH="$np" BL308_POSTURE_CHILD=1 "$BASH" "$SCRIPT_DIR/${0##*/}" > "$A/a1.txt" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] && grep -q '^  \[SKIP\] the whole suite' "$A/a1.txt" && ! grep -q '^  \[FAIL\]' "$A/a1.txt"; then
      pass "A1: gitleaks absent, CI unset — the suite skips with a named reason (rc 0)"
    else
      fail_ "A1" "rc=$rc (want 0 with one [SKIP] and no [FAIL]): $(tr '\n' ';' < "$A/a1.txt")"
    fi
    rc=0
    env CI=1 PATH="$np" BL308_POSTURE_CHILD=1 "$BASH" "$SCRIPT_DIR/${0##*/}" > "$A/a2.txt" 2>&1 || rc=$?
    if [ "$rc" -eq 1 ] && grep -q '^  \[FAIL\] setup' "$A/a2.txt"; then
      pass "A2: gitleaks absent, CI set — the suite fails at setup (rc 1)"
    else
      fail_ "A2" "rc=$rc (want 1 with [FAIL] setup) — a CI run without gitleaks would be credited with a scan that never ran: $(tr '\n' ';' < "$A/a2.txt")"
    fi
  fi
fi


echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

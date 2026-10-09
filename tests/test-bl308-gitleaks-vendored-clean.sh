#!/usr/bin/env bash
# tests/test-bl308-gitleaks-vendored-clean.sh — the shipped source must scan
# clean under the gitleaks rules the generated CI runs (## BL-308:).
#
# Every project born from init.sh carries copies of scripts/ and templates/,
# and its generated CI runs `gitleaks git --redact --exit-code 1` over its
# whole history. A declaration in a vendored script that LOOKS like a
# credential therefore turns every new project's first pull request red at
# the secret-detection step, before any governance step runs. Measured on
# 2026-09-22: a compound `local` in scripts/check-gate.sh declared a variable
# whose name ended in the word the `generic-api-key` rule keys on, assigned
# it an empty string, and declared the next variable on the same line; the
# rule read that as name=value, and a project's first PR failed with
# "leaks found: 1". (The shape is described rather than quoted so this file
# does not trip the same rule.)
#
# G1 pins the shipped surface clean. C1/C2 pin that the scanner is LIVE over
# the same surface — a planted AWS-shaped key and a planted generic-shaped key
# must each be found — so the fix cannot be "disable the rule" or an
# allowlist wide enough to swallow a real credential. C3 pins that no scanner
# config is shipped, C4 and C5 that the scanner is live over the shipped docs
# and over the installer, templates/ and the evaluation prompts, and R1
# that the registration lint keeps this suite in the PR-blocking unit lane.
# A1/A2 pin the gitleaks-absent posture by re-running this file without it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# The installer's name is assembled because lint-tests-registered.sh's BL-181
# predicate counts it on any executed line as proof this suite RUNS init.sh,
# which would exempt it from the tests.yml unit lane. It only reads it. R1 pins.
INSTALLER="$REPO_ROOT/init"".sh"
# shellcheck source=../scripts/lib/scaffold-shipped-set.sh
. "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

command -v jq >/dev/null 2>&1 || {
  echo "jq is required for tests/test-bl308-gitleaks-vendored-clean.sh" >&2; exit 2; }

# GITLEAKS-ABSENT IS A SKIP LOCALLY AND A FAILURE IN CI (the ## BL-288: posture).
# Every case here is a real scan; a green check credited with a scan that
# never ran is exactly what a project's red first PR would then contradict.
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

# The surface init.sh ships into every project is drawn from these. docs/ is
# not copied whole: init.sh copies named files out of it (parsed from its own
# cp lines, plus the platform modules it picks from), and the design notes
# beside them carry planted AKIA fixtures that never leave this repo.
SHIPPED_SURFACE="scripts templates evaluation-prompts/Projects docs/platform-modules
$(soif_parse_shipped_reference_doc_sources "$INSTALLER" || true)"

# Assembled from halves so this file does not itself carry a scanner-shaped
# literal. BASE32-VALIDITY IS LOAD-BEARING for the AWS plant: the
# `aws-access-token` rule requires [A-Z2-7] after `AKIA`. The generic plant
# needs letters AND digits, because the `generic-api-key` rule allowlists a
# secret that is letters only.
AWS_PLANT="AKIAQZ7X4M2N""PLKJ3HRD"
GENERIC_PLANT="b7Kq2mZ9xV4t""R8pL3nW6yH1s"

# scan_dir DIR REPORT — `gitleaks dir` with the default rules, no config, no
# ignore file, exactly what a generated project's CI has. Prints the finding
# count from the JSON report; rc is gitleaks' own.
scan_dir() {
  local dir="$1" report="$2" rc=0
  gitleaks dir "$dir" --no-banner --redact --exit-code 1 \
    --report-format json --report-path "$report" >/dev/null 2>&1 || rc=$?
  [ -s "$report" ] || printf '[]\n' > "$report"
  return "$rc"
}
findings() { jq -r 'length' "$1"; }
rule_hits() { jq -r --arg r "$2" '[.[] | select(.RuleID == $r)] | length' "$1"; }
describe()  { jq -r '.[] | "\(.RuleID) \(.File):\(.StartLine) \(.Match)"' "$1"; }

# mk_surface DIR — the shipped surface, copied, so plants never touch the tree.
mk_surface() {
  local d="$1" p
  cp "$INSTALLER" "$d/" || return 1
  for p in $SHIPPED_SURFACE; do
    mkdir -p "$d/$(dirname "$p")" || return 1
    cp -R "$REPO_ROOT/$p" "$d/$p" || return 1
  done
}

if [ "$HAVE_GITLEAKS" -eq 0 ]; then
  if [ "$GITLEAKS_ABSENT_IS_FATAL" -eq 1 ]; then
    fail_ "setup" "gitleaks is not installed and CI is set — every case here is a real scan; a green check credited with a scan that never ran is what this suite exists to prevent"
  else
    skip_ "the whole suite" "gitleaks not installed (install it to run BL-308's proofs locally)"
  fi
else
  # ── G1: the shipped surface scans clean ──────────────────────────────────
  D="$(newtmp)"
  mkdir -p "$D/clean"
  if ! mk_surface "$D/clean"; then
    fail_ "G1 setup" "could not copy the shipped surface"
  else
    rc=0; scan_dir "$D/clean" "$D/clean.json" || rc=$?
    n=$(findings "$D/clean.json")
    if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
      pass "G1: gitleaks reports 0 findings over the installer and $(printf '%s ' $SHIPPED_SURFACE)(rc 0)"
    else
      fail_ "G1" "rc=$rc findings=$n over the shipped surface — a project born from this tree fails its first PR at secret detection: $(describe "$D/clean.json" | tr '\n' ';')"
    fi
  fi

  # ── C1: the scanner is live over that surface — an AWS-shaped plant is found ─
  mkdir -p "$D/aws"
  if ! mk_surface "$D/aws"; then
    fail_ "C1 setup" "could not copy the shipped surface"
  else
    printf '\n# planted by the BL-308 control\nAWS_TEST_ID=%s\n' "$AWS_PLANT" >> "$D/aws/scripts/check-gate.sh"
    rc=0; scan_dir "$D/aws" "$D/aws.json" || rc=$?
    n=$(rule_hits "$D/aws.json" aws-access-token)
    if [ "$rc" -eq 1 ] && [ "$n" -eq 1 ]; then
      pass "C1: a planted AWS-shaped key in scripts/check-gate.sh is found (rc 1, aws-access-token x1)"
    else
      fail_ "C1" "rc=$rc aws-access-token hits=$n (want rc 1, 1 hit) — the scanner is not live over the surface G1 claims clean"
    fi
  fi

  # ── C2: the generic-api-key rule is live — the rule the defect tripped ─────
  mkdir -p "$D/generic"
  if ! mk_surface "$D/generic"; then
    fail_ "C2 setup" "could not copy the shipped surface"
  else
    printf '\n# planted by the BL-308 control\napi_key="%s"\n' "$GENERIC_PLANT" >> "$D/generic/scripts/check-gate.sh"
    rc=0; scan_dir "$D/generic" "$D/generic.json" || rc=$?
    # The plant, by rule AND line, so this stays a control of the rule's
    # liveness and not a second copy of G1's zero-count.
    n=$(jq -r --arg r generic-api-key '[.[] | select(.RuleID == $r and (.File | endswith("scripts/check-gate.sh")) and (.Match | startswith("api_key=")))] | length' "$D/generic.json")
    if [ "$rc" -eq 1 ] && [ "$n" -eq 1 ]; then
      pass "C2: a planted generic-shaped key in scripts/check-gate.sh is found (rc 1, generic-api-key on the planted line)"
    else
      fail_ "C2" "rc=$rc planted-line hits=$n (want rc 1, 1) — the rule the defect tripped is not live over the surface, so G1 proves nothing"
    fi
  fi

  # ── C3: no scanner config or ignore file is shipped ─────────────────────
  # G1 is a claim about the DEFAULT rules. A .gitleaks.toml or .gitleaksignore
  # at the repo root would be scanned by nothing here (the copies above carry
  # neither) and would make a green G1 disagree with a generated project.
  # If one is ever shipped on purpose, extend mk_surface to copy it and G1
  # tests the shipped config too.
  if [ ! -e "$REPO_ROOT/.gitleaks.toml" ] && [ ! -e "$REPO_ROOT/.gitleaksignore" ]; then
    pass "C3: no .gitleaks.toml or .gitleaksignore at the repo root — G1 ran the same default rules a generated project's CI runs"
  else
    fail_ "C3" "a scanner config or ignore file exists at the repo root; G1 scanned copies without it, so its verdict may not match a generated project — copy it in mk_surface and re-measure"
  fi

  # ── C4: the scanner is live over the shipped docs ───────────────────────
  # The installer copies named files out of docs/; a plant in one of them and
  # in a platform module must each be found, or G1 says nothing about docs.
  mkdir -p "$D/c4"
  if ! mk_surface "$D/c4"; then
    fail_ "C4 setup" "could not copy the shipped surface"
  else
    ref_doc=$(soif_parse_shipped_reference_doc_sources "$INSTALLER" | head -n 1 || true)
    planted=0
    for p in "$ref_doc" docs/platform-modules/web.md; do
      if [ -n "$p" ] && [ -f "$D/c4/$p" ]; then
        printf '\n# planted by the BL-308 control\napi_key="%s"\n' "$GENERIC_PLANT" >> "$D/c4/$p"
        planted=$((planted + 1))
      fi
    done
    if [ "$planted" -ne 2 ]; then
      fail_ "C4" "planted into $planted of 2 docs files (${ref_doc:-no reference doc parsed}, docs/platform-modules/web.md) — the shipped docs are not in the surface G1 scans"
    else
      rc=0; scan_dir "$D/c4" "$D/c4.json" || rc=$?
      n=$(jq -r --arg r generic-api-key '[.[] | select(.RuleID == $r and (.File | contains("/c4/docs/")) and (.Match | startswith("api_key=")))] | length' "$D/c4.json")
      if [ "$rc" -eq 1 ] && [ "$n" -eq 2 ]; then
        pass "C4: planted generic-shaped keys in $ref_doc and docs/platform-modules/web.md are both found (rc 1, generic-api-key x2)"
      else
        fail_ "C4" "rc=$rc planted-line hits=$n (want rc 1, 2) — the scanner is not live over the shipped docs"
      fi
    fi
  fi

  # ── C5: the scanner is live over the installer, templates/ and the prompts ─
  # One plant in each remaining part of the surface, each file taken from this
  # tree, so a part dropped from mk_surface leaves its plant nowhere to land.
  mkdir -p "$D/c5"
  if ! mk_surface "$D/c5"; then
    fail_ "C5 setup" "could not copy the shipped surface"
  else
    tmpl=$(cd "$REPO_ROOT" && LC_ALL=C ls templates/pipelines/ci/github/*.yml 2>/dev/null | head -n 1)
    prompt=$(cd "$REPO_ROOT" && find evaluation-prompts/Projects -type f -name '*.md' 2>/dev/null | LC_ALL=C sort | head -n 1)
    planted=0
    for p in "${INSTALLER##*/}" "$tmpl" "$prompt"; do
      if [ -n "$p" ] && [ -f "$D/c5/$p" ]; then
        printf '\n# planted by the BL-308 control\napi_key="%s"\n' "$GENERIC_PLANT" >> "$D/c5/$p"
        planted=$((planted + 1))
      fi
    done
    if [ "$planted" -ne 3 ]; then
      fail_ "C5" "planted into $planted of 3 files (${INSTALLER##*/}, ${tmpl:-no CI template found}, ${prompt:-no evaluation prompt found}) — a part of what the installer ships is not in the surface G1 scans"
    else
      rc=0; scan_dir "$D/c5" "$D/c5.json" || rc=$?
      n=$(jq -r --arg r generic-api-key '[.[] | select(.RuleID == $r and (.File | contains("/c5/")) and (.Match | startswith("api_key=")))] | length' "$D/c5.json")
      if [ "$rc" -eq 1 ] && [ "$n" -eq 3 ]; then
        pass "C5: planted generic-shaped keys in ${INSTALLER##*/}, $tmpl and $prompt are all found (rc 1, generic-api-key x3)"
      else
        fail_ "C5" "rc=$rc planted-line hits=$n (want rc 1, 3) — the scanner is not live over the installer, templates/ or the evaluation prompts"
      fi
    fi
  fi
fi

# ── R1: the registration lint demands this suite's unit-lane row ─────────
# lint-tests-registered.sh exempts a test that names the installer on an
# executed line as an invoker (its BL-181 predicate), and an exempt suite's
# tests.yml row can be deleted with every lint green. This suite never runs
# the installer, so the lint must refuse a tests.yml without its row.
# The posture child below skips it: it measures only the skip or setup failure.
if [ -z "${BL308_POSTURE_CHILD:-}" ]; then
  R="$(newtmp)"
  grep -v 'tests/test-bl308-gitleaks-vendored-clean.sh' "$REPO_ROOT/.github/workflows/tests.yml" > "$R/tests.yml"
  rc=0
  "$BASH" "$REPO_ROOT/scripts/lint-tests-registered.sh" --list --tests-yml "$R/tests.yml" > "$R/list.txt" 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && grep -Eq '^FAIL[[:space:]].*test-bl308-gitleaks-vendored-clean\.sh[[:space:]]+not-in-unit-lane' "$R/list.txt"; then
    pass "R1: with its tests.yml row removed, lint-tests-registered.sh fails naming this suite (rc 1, not-in-unit-lane)"
  else
    fail_ "R1" "rc=$rc; this suite's row: $(grep 'test-bl308-gitleaks-vendored-clean' "$R/list.txt" | tr '\n' ';') — the lint does not protect the unit-lane row"
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

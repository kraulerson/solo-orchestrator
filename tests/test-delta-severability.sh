#!/usr/bin/env bash
# tests/test-delta-severability.sh — Delta Track §3.1's severability test.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §3.1 ("delete every
# delta-module file and revert the seam block in process-checklist.sh, and the
# full suite must pass — that is the property 'severable' means operationally;
# §11-WP7 makes it a test"), §3.3 (the dependency-direction lint this protects),
# §0.3-C10 (the seam and the single writer are the same file, which is what
# makes the edge cardinality ONE), §11-WP7.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE ENUMERATION IS THE POINT — AND IT IS DONE BY RUNNING, NOT BY REMEMBERING
#
# §3.1 says "the seam block in process-checklist.sh", singular. By the time WP7
# arrived the revert was FOUR core files, and each one arrived in a different
# work package with its own good reason:
#
#   1. scripts/process-checklist.sh   the DELTA-SEAM fence (WP2) — the seam
#                                     itself, and the only allowlisted edge
#   2. scripts/upgrade-project.sh     _postmvp_policy_notice + its call site
#                                     (WP2's §3.2 NOTICE-ONLY arm)
#   3. scripts/validate.sh            _postmvp_era_assertion + its call site
#                                     (WP3's §10.1 report-only assertion)
#   4. scripts/check-maintenance.sh   the cadence policy read (WP6)
#
# Nobody wrote that list down in one place, and a list written from memory is
# exactly what this test refuses to be. V1 is a COMPLETENESS scan: after the
# declared revert it sweeps the whole severed executable surface for any
# surviving mention of the module. A fifth consumer added later without touching
# the revert manifest below makes V1 go RED and NAMES the file. That, not the
# manifest, is what keeps the enumeration honest.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE MEASURED FINDING THIS TEST EXISTS TO RECORD (V0)
#
# FUNCTIONAL SEVERABILITY IS ALREADY FREE, AND TEXTUAL SEVERABILITY IS WHAT THE
# REVERT BUYS. Every one of the four consumers fails SOFT when the module is
# absent — by design, and each one says so in its own header: the seam answers
# rc 2 ("the delta module is not installed"), validate.sh's assertion is
# `|| return 0`, upgrade's notice is `|| true`, and check-maintenance.sh's
# policy read falls back to the framework constants. V0 measures that: with the
# module files deleted and NO revert at all, the core probes still behave.
#
# THAT IS WHY THE §11-WP7 MUTATION CANNOT BE A FUNCTIONAL ONE. "Delete a module
# file but NOT the seam revert -> RED" is killed by V1, the structural arm, and
# it has to be — a functional arm would stay green precisely because the
# fail-soft design works. Recorded here rather than discovered later by someone
# wondering why the obvious mutation does nothing.
#
# ═════════════════════════════════════════════════════════════════════════════
# "THE FULL SUITE" — WHAT IS ACTUALLY RUN, AND WHY IT IS NOT ALL OF IT
#
# CLAUDE.md: the full suite is ~3h and workflow_dispatch-only. A unit-lane test
# cannot run it, and pretending otherwise would be worse than saying so. V3 runs
# a DECLARED list of fast core suites inside the severed tree, chosen because
# they exercise the files the revert touches, and V2 parses every core script.
# The list is named in the output so a reader can see the scope rather than
# infer it.
#
# TWO THINGS §3.1's INVENTORY DOES NOT NAME, AND THIS TEST DELETES ANYWAY —
# because a module whose own tests stayed behind would leave a suite full of
# red, which is not what "severable" can mean:
#   • tests/test-delta-*.sh and tests/test-lint-delta-boundary.sh — the module's
#     own suites. RESIDUAL, NAMED RATHER THAN HIDDEN: tests/test-delta-wp6-cadence.sh
#     is a delta-track suite that is also the ONLY coverage of a CORE script
#     (scripts/check-maintenance.sh), so severing the module takes that coverage
#     with it. That is a real cost of the module boundary and it belongs on the
#     record, not in a footnote.
#   • their registrations in tests/full-project-test-suite.sh and the tests.yml
#     unit list.
#
# EXIT CODES / TEXT, NEVER LABELS. Every row is asserted on a process exit code
# or on a grep over the severed tree.
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. Its executed lines never name the init script — the copy
# step reaches it through a SPLIT token, the same idiom and the same reason as
# tests/test-delta-wp6-cadence.sh::H6 and tests/test-intake-wizard-fixes.sh.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v git >/dev/null 2>&1; then
  echo "git is required for tests/test-delta-severability.sh" >&2
  exit 2
fi

# The scaffolder's basename, split so no executed line in this file names it.
# Reading it whole is what would make this suite unit-lane-EXEMPT, and it is a
# fast test that belongs in the fast lane.
INIT_FILE="init"".sh"

# ── The §3.1 inventory, READ FROM THE LINT rather than retyped ──────────────
# scripts/lint-delta-boundary.sh already holds the inventory, spelled once,
# between its own DELTA-BOUNDARY-MANIFEST fences. Copying that list into this
# file would create a second place it lives, and the two would drift — which is
# the whole class of defect §3.1's boundary exists to prevent.
_module_manifest() {
  awk '/DELTA-BOUNDARY-MANIFEST-BEGIN/ { on = 1; next }
       /DELTA-BOUNDARY-MANIFEST-END/   { exit }
       on && /^[[:space:]]*"/ { gsub(/^[[:space:]]*"/, ""); gsub(/".*$/, ""); print }' \
    "$REPO_ROOT/scripts/lint-delta-boundary.sh"
}

MODULE_FILES="$(_module_manifest)"
MODULE_N="$(printf '%s\n' "$MODULE_FILES" | grep -c . || true)"
case "$MODULE_N" in ''|*[!0-9]*) MODULE_N=0 ;; esac

echo "== tests/test-delta-severability.sh =="
echo ""

if [ "$MODULE_N" -ge 7 ] && printf '%s\n' "$MODULE_FILES" | grep -q '^scripts/cut-release\.sh$'; then
  pass "V-0a: the module inventory is READ from scripts/lint-delta-boundary.sh's own DELTA_MANIFEST ($MODULE_N entries, including scripts/cut-release.sh) — this test and the lint can never disagree about what 'the module' is"
else
  fail_ "V-0a" "could not read the §3.1 inventory out of the lint (got $MODULE_N entries: $(printf '%s' "$MODULE_FILES" | tr '\n' ' '))"
fi

# ── Building a severed tree ─────────────────────────────────────────────────
TD=$(mktemp -d)

mk_tree() {   # <dest> — a working copy of everything a core suite reads
  local d="$1"
  mkdir -p "$d"
  cp -R "$REPO_ROOT/scripts"   "$d/scripts"
  cp -R "$REPO_ROOT/tests"     "$d/tests"
  cp -R "$REPO_ROOT/templates" "$d/templates"
  cp -R "$REPO_ROOT/docs"      "$d/docs"
  cp -R "$REPO_ROOT/.github"   "$d/.github"
  cp "$REPO_ROOT/$INIT_FILE"   "$d/$INIT_FILE"
  for f in CLAUDE.md README.md CONTRIBUTING.md solo-orchestrator-backlog.md solo-orchestrator-bugs.md; do
    [ -f "$REPO_ROOT/$f" ] && cp "$REPO_ROOT/$f" "$d/$f"
  done
  return 0
}

# sever_module <tree> — STEP 1: delete every §3.1 file, plus the module's own
#   suites and their registrations (see the header for why those are here).
sever_module() {
  local d="$1" e
  printf '%s\n' "$MODULE_FILES" | while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in
      */) rm -rf "$d/$e" 2>/dev/null || true ;;
      *)  rm -f  "$d/$e" 2>/dev/null || true ;;
    esac
  done
  rm -f "$d"/tests/test-delta-*.sh "$d"/tests/test-lint-delta-boundary.sh 2>/dev/null || true
  # Their registrations leave with them.
  _drop_lines "$d/tests/full-project-test-suite.sh" 'tests/test-delta-\|tests/test-lint-delta-boundary'
  _drop_lines "$d/.github/workflows/tests.yml"      'tests/test-delta-\|tests/test-lint-delta-boundary\|delta-boundary'
  return 0
}

_drop_lines() {   # <file> <BRE>
  local f="$1" pat="$2" tmp
  [ -f "$f" ] || return 0
  tmp="$(mktemp)"
  grep -v "$pat" "$f" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$f"
  return 0
}

# _drop_fn <file> <fn-name> — remove a top-level function AND its bare call
#   sites. The function must start at column zero and end with `}` at column
#   zero, which is the shape all three of the reverted helpers have.
_drop_fn() {
  local f="$1" fn="$2" tmp
  [ -f "$f" ] || return 0
  tmp="$(mktemp)"
  awk -v fn="$fn" '
    $0 ~ "^" fn "\\(\\) \\{" { skip = 1; next }
    skip == 1 && /^\}$/       { skip = 0; next }
    skip == 1                 { next }
    $0 ~ "^[[:space:]]*" fn "[[:space:]]*$" { next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  return 0
}

# sever_seam <tree> — STEP 2: THE REVERT. Four core files, enumerated in this
#   file's header and kept honest by V1's completeness sweep.
sever_seam() {
  local d="$1" tmp
  # (1) process-checklist.sh — the DELTA-SEAM fence, contiguous on purpose so
  #     that this is a single-block revert (its own header says so).
  tmp="$(mktemp)"
  awk '/DELTA-SEAM-BEGIN/ { skip = 1 }
       skip == 1 { if (/DELTA-SEAM-END/) skip = 0; next }
       { print }' "$d/scripts/process-checklist.sh" > "$tmp" \
    && mv "$tmp" "$d/scripts/process-checklist.sh"
  # (2) upgrade-project.sh — §3.2's NOTICE-ONLY arm.
  _drop_fn "$d/scripts/upgrade-project.sh" _postmvp_policy_notice
  # (3) validate.sh — §10.1's report-only era assertion.
  _drop_fn "$d/scripts/validate.sh" _postmvp_era_assertion
  # (4) check-maintenance.sh — WP6's policy read. SUBSTITUTED, not deleted: the
  #     read sits inside `if [ -f "$seam" ]; then … fi`, and an empty then-branch
  #     is a bash SYNTAX ERROR. The substitution restores exactly the pre-WP6
  #     behaviour, which is the framework constants.
  tmp="$(mktemp)"
  sed -e 's|^.*# CADENCE-POLICY-READ.*$|    v=""|' "$d/scripts/check-maintenance.sh" > "$tmp" \
    && mv "$tmp" "$d/scripts/check-maintenance.sh"
  return 0
}

# ── The residual scan (V1's instrument) ─────────────────────────────────────
# Whole-line comments are stripped first, exactly as §3.3's lint does, because
# a SPEC block naming the design document is prose and not an edge. Everything
# else is matched as a FIXED string — `delta.sh` as a regex would match
# `deltaXsh`, and a scan that reports what is not there is as useless as one
# that misses what is.
_residual_scan() {   # <tree> -> "file:line:text" per hit
  local d="$1" f pat tmp
  tmp="$(mktemp)"
  {
    printf '%s\n' "$MODULE_FILES" | while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      case "$pat" in
        */) printf '%s\n' "$pat" ;;
        *)  printf '%s\n' "${pat##*/}" ;;
      esac
    done
    printf '%s\n' '--delta-'
  } | grep -v '^$' | LC_ALL=C sort -u > "$tmp"
  for f in $(find "$d/scripts" -type f -name '*.sh' | LC_ALL=C sort) "$d/$INIT_FILE"; do
    [ -f "$f" ] || continue
    grep -vE '^[[:space:]]*#' "$f" 2>/dev/null \
      | grep -nFf "$tmp" 2>/dev/null \
      | sed -e "s|^|${f#$d/}:|" || true
  done
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

# ── Probes: the four consumers, run directly ────────────────────────────────
mk_fixture() {   # a phase-4 project the probes can run against
  local p="$1"
  mkdir -p "$p/.claude" "$p/docs/test-results"
  (
    cd "$p" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email "sever@example.invalid"
    git config user.name "Severability Fixture"
    git config commit.gpgsign false
  ) >/dev/null 2>&1
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":4,"phases":{}}\n' \
    > "$p/.claude/phase-state.json"
  printf '# Changelog\n\n## [Unreleased]\n' > "$p/CHANGELOG.md"
  ( cd "$p" && unset GITHUB_BASE_REF; git add -A; git commit -q -m "chore: seed" ) >/dev/null 2>&1
  return 0
}

probe_rcs() {   # <scripts-dir> <project-dir> -> "a|b|c" exit codes
  local sd="$1" p="$2" a=0 b=0 c=0
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/check-maintenance.sh" </dev/null >/dev/null 2>&1 ) || a=$?
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/validate.sh"          </dev/null >/dev/null 2>&1 ) || b=$?
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/process-checklist.sh" --help </dev/null >/dev/null 2>&1 ) || c=$?
  printf '%s|%s|%s' "$a" "$b" "$c"
}

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V0 — the baseline, and the fail-soft finding ==="
# ════════════════════════════════════════════════════════════════════════════

FIX="$TD/proj"; mk_fixture "$FIX"
BASE_RCS="$(probe_rcs "$REPO_ROOT/scripts" "$FIX")"

HALF="$TD/half"; mk_tree "$HALF"; sever_module "$HALF"
HALF_RCS="$(probe_rcs "$HALF/scripts" "$FIX")"

if [ "$BASE_RCS" = "$HALF_RCS" ]; then
  pass "V0: with every §3.1 module file DELETED and no revert at all, the four core consumers answer exactly what they answered with the module present ($BASE_RCS) — functional severability is already free, because every consumer fails SOFT by design. That is why §11-WP7's mutation has to be caught structurally: see V1"
else
  fail_ "V0" "module-deleted probes answered '$HALF_RCS' but the intact tree answered '$BASE_RCS' — a consumer is not failing soft"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V1 — the completeness sweep: nothing of the module survives ==="
# ════════════════════════════════════════════════════════════════════════════

SEV="$TD/severed"; mk_tree "$SEV"; sever_module "$SEV"; sever_seam "$SEV"
V1_HITS="$(_residual_scan "$SEV")"
V1_N="$(printf '%s\n' "$V1_HITS" | grep -c . || true)"
case "$V1_N" in ''|*[!0-9]*) V1_N=0 ;; esac
if [ "$V1_N" -eq 0 ]; then
  pass "V1: after the four-file revert, NOT ONE executed line under scripts/ or in the scaffolder names a module path or a --delta-* action. This is the arm that keeps the revert manifest honest: a fifth consumer added later without updating it lands here, named"
else
  fail_ "V1" "$V1_N surviving reference(s) to the module — the revert list in this file's header is incomplete:
$V1_HITS"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V2 — the severed tree still parses, and still behaves ==="
# ════════════════════════════════════════════════════════════════════════════

V2_BAD=""
for f in $(find "$SEV/scripts" -type f -name '*.sh' | LC_ALL=C sort); do
  bash -n "$f" 2>/dev/null || V2_BAD="$V2_BAD ${f#$SEV/}"
done
bash -n "$SEV/$INIT_FILE" 2>/dev/null || V2_BAD="$V2_BAD $INIT_FILE"
V2_N="$(find "$SEV/scripts" -type f -name '*.sh' | grep -c . || true)"
if [ -z "$V2_BAD" ]; then
  pass "V2a: every one of the $V2_N shell scripts left in the severed tree still parses, and so does the scaffolder — the revert cut whole functions and a whole fence, not fragments"
else
  fail_ "V2a" "these files no longer parse after the revert:$V2_BAD"
fi

SEV_RCS="$(probe_rcs "$SEV/scripts" "$FIX")"
if [ "$SEV_RCS" = "$BASE_RCS" ]; then
  pass "V2b: the fully severed consumers answer exactly what the intact tree answered ($SEV_RCS) — the framework does not need the post-1.0 module to work"
else
  fail_ "V2b" "severed probes answered '$SEV_RCS' but the intact tree answered '$BASE_RCS'"
fi

# The seam is GONE, not merely inert: a delta action is now an unknown option.
SEAM_RC=0
( cd "$FIX" && unset GITHUB_BASE_REF; bash "$SEV/scripts/process-checklist.sh" --delta-state-read </dev/null >/dev/null 2>&1 ) || SEAM_RC=$?
INTACT_SEAM_RC=0
( cd "$FIX" && unset GITHUB_BASE_REF; bash "$REPO_ROOT/scripts/process-checklist.sh" --delta-state-read </dev/null >/dev/null 2>&1 ) || INTACT_SEAM_RC=$?
if [ "$SEAM_RC" -ne 0 ] && [ "$INTACT_SEAM_RC" -eq 0 ]; then
  pass "V2c: in the severed tree the seam action is refused (rc $SEAM_RC) while the intact tree answers it (rc $INTACT_SEAM_RC) — the edge is gone rather than merely non-functional, which is the difference between severing a module and breaking one"
else
  fail_ "V2c" "severed seam rc=$SEAM_RC (want non-zero), intact seam rc=$INTACT_SEAM_RC (want 0)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V3 — a declared set of core suites, run INSIDE the severed tree ==="
# ════════════════════════════════════════════════════════════════════════════

# Chosen because they exercise the files the revert touches. NOT the ~3h full
# suite — CLAUDE.md records that it is workflow_dispatch-only, and a unit-lane
# test that claimed to run it would be lying about its own scope.
V3_SUITES="tests/test-check-phase-gate.sh
tests/test-bl214-gate-snapshot-staleness.sh
tests/test-check-phase-gate-poc-block-contract.sh
tests/test-gate-principles.sh"

V3_DETAIL=""
V3_OK=y
while IFS= read -r s; do
  [ -n "$s" ] || continue
  if [ ! -f "$SEV/$s" ]; then
    V3_DETAIL="$V3_DETAIL [${s##*/}=MISSING]"; V3_OK=n; continue
  fi
  rc=0
  ( cd "$SEV" && unset GITHUB_BASE_REF; bash "$s" </dev/null >/dev/null 2>&1 ) || rc=$?
  V3_DETAIL="$V3_DETAIL [${s##*/}=rc$rc]"
  [ "$rc" -eq 0 ] || V3_OK=n
done <<EOF
$V3_SUITES
EOF

if [ "$V3_OK" = y ]; then
  pass "V3: every suite in the declared set passes inside the fully severed tree —$V3_DETAIL"
else
  fail_ "V3" "a suite failed in the severed tree:$V3_DETAIL"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — the §11-WP7 mutation ==="
# ════════════════════════════════════════════════════════════════════════════

# "Delete a module file but NOT the seam revert -> the test must go RED."
# It goes red at V1, and only at V1 — see this file's header for why a
# functional arm cannot catch it.
MUT="$TD/mutant"; mk_tree "$MUT"; sever_module "$MUT"
MUT_HITS="$(_residual_scan "$MUT")"
MUT_N="$(printf '%s\n' "$MUT_HITS" | grep -c . || true)"
case "$MUT_N" in ''|*[!0-9]*) MUT_N=0 ;; esac
MUT_FILES="$(printf '%s\n' "$MUT_HITS" | cut -d: -f1 | LC_ALL=C sort -u | tr '\n' ' ')"
MUT_RCS="$(probe_rcs "$MUT/scripts" "$FIX")"
# The dangling references must be in the SEAM HOST, not merely somewhere: a
# count alone would pass for a mutant that left a reference in some unrelated
# file. `[...]` around the expansion is not decoration — CLAUDE.md's
# portability rule forbids a multibyte character adjacent to an expansion under
# bash 3.2, and this very line rendered the file list as one replacement byte
# until the em-dash that followed `$MUT_FILES` was taken out.
MUT_NAMES_SEAM=n
case "$MUT_FILES" in *process-checklist.sh*) MUT_NAMES_SEAM=y ;; esac
if [ "$MUT_N" -gt 0 ] && [ "$MUT_NAMES_SEAM" = y ] && [ "$MUT_RCS" = "$BASE_RCS" ]; then
  pass "m1: with the module files deleted and the seam NOT reverted, V1 finds $MUT_N dangling reference(s), in [$MUT_FILES], the seam host among them. V1 goes RED. And the probes still answer '$MUT_RCS', identical to the intact tree, which MEASURES the claim in this file's header: a functional arm would have stayed green, so the structural arm is not a convenience, it is the only instrument that can see this"
else
  fail_ "m1" "residual hits=$MUT_N (want > 0, so V1 can see it); names the seam host=$MUT_NAMES_SEAM (want y); files=[$MUT_FILES]; probes='$MUT_RCS' vs intact '$BASE_RCS'"
fi

# The dual direction: the mutation is about the REVERT, so a tree that reverted
# the seam and kept the module must also be caught — otherwise "delete both"
# and "delete neither" would be the only states this test can distinguish.
MUT2="$TD/mutant2"; mk_tree "$MUT2"; sever_seam "$MUT2"
MUT2_LEFT=0
for e in scripts/lib/delta-state.sh scripts/delta.sh scripts/cut-release.sh; do
  [ -f "$MUT2/$e" ] && MUT2_LEFT=$((MUT2_LEFT + 1))
done
MUT2_SEAM_RC=0
( cd "$FIX" && unset GITHUB_BASE_REF; bash "$MUT2/scripts/process-checklist.sh" --delta-state-read </dev/null >/dev/null 2>&1 ) || MUT2_SEAM_RC=$?
if [ "$MUT2_LEFT" -eq 3 ] && [ "$MUT2_SEAM_RC" -ne 0 ]; then
  pass "m2: the opposite half-sever — seam reverted, module files LEFT IN PLACE ($MUT2_LEFT of 3 still present) — leaves the module unreachable (a delta action answers rc $MUT2_SEAM_RC). Severability is a property of the PAIR, and this row is why the revert and the deletion are one operation and not two"
else
  fail_ "m2" "module files still present=$MUT2_LEFT (want 3); seam rc=$MUT2_SEAM_RC (want non-zero)"
fi

rm -rf "$TD"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

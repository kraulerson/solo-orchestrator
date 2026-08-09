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
#   5. scripts/resume.sh              the §10.5 fourth branch (WP8) — the
#                                     `# DELTA-RESUME-BEGIN`/`-END` fence,
#                                     another core->core seam delegation
#   6. init.sh                        the WP8 copy list — the
#                                     `# DELTA-INSTALL-BEGIN`/`-END` fences
#                                     (TWO of them: the scripts block and the
#                                     template block) that ship the module to
#                                     generated projects
#
# CONSUMERS 5 AND 6 ARRIVED IN WP8 AND WERE FOUND BY THIS FILE, not by anyone
# remembering. V1 named both by path the first time the suite ran against the
# WP8 tree — which is the completeness sweep doing exactly the job the rest of
# this header claims for it, and is the reason the revert list is allowed to be
# a list at all.
#
# CONSUMER 6 IS A DIFFERENT SHAPE FROM 1-5 AND IS WORTH THE SENTENCE. The
# scaffolder does not CALL the module; it copies its bytes. It has to name each
# file literally, because scripts/lib/scaffold-shipped-set.sh derives the
# shipped set by parsing those cp lines. Post-sever there is nothing to copy, so
# the fence goes as a whole block — and scripts/lint-delta-boundary.sh accepts
# it in the intact tree only inside that fence and only for cp/chmod/mkdir
# statements (its DELTA-BOUNDARY-INSTALLER fence, cardinality one, asserted the
# same way the seam's is).
#
# ...and TWO more that are not scripts at all:
#
#   7. .github/workflows/lint.yml    the `delta-boundary-lint` job, which runs
#                                    scripts/lint-delta-boundary.sh (WP1)
#   8. tests/full-project-test-suite.sh
#                                    `run_child_suite "scripts/lint-delta-boundary.sh"`
#                                    — the aggregator invoking the module's
#                                    lint DIRECTLY, not through a tests/ path
#
# CONSUMER 6 IS THE ONE THAT FALSIFIED THIS TEST'S OWN CENTRAL CLAIM. §3.1
# defines severability as "the full suite must pass" after the sever; the file
# that IS the full suite registered a module script directly, the drop pattern
# only ever matched `tests/test-…` paths, and the sweep did not open the file.
# Post-sever that registration is `bash` on a deleted script — rc 127 — so the
# very run the property is stated in terms of went red. V1b and V1c exist for
# it, and m4 rebuilds the old state to prove they fire.
#
# Nobody wrote that list down in one place, and a list written from memory is
# exactly what this test refuses to be. V1/V1b are a COMPLETENESS scan: after
# the declared revert they sweep the severed surface for any surviving mention
# of the module, and a consumer added later without touching the revert manifest
# below makes them go RED and NAMES the file. V1c closes the gap a text sweep
# structurally cannot: a registration whose target the sweep never recognises
# still fails to RESOLVE, and V1c stats every one of them.
#
# THAT CLAIM HAS NOW BEEN FALSIFIED TWICE, BOTH TIMES BY THE SAME SHAPE — a
# consumer living in a file class the sweep did not open (a workflow, then the
# aggregator). Both times the fix was to widen the scope AND add a mutant that
# rebuilds the old blindness, because a scope extension proves nothing until
# something in the new class is shown to trip it. If a third one turns up, the
# lesson is the scope list, not the manifest.
#
# THE FIRST VERSION OF THAT CLAIM WAS FALSE, AND THE FIFTH CONSUMER IS WHY.
# `_residual_scan` swept `scripts/*.sh` plus the scaffolder and nothing else, so
# the `delta-boundary-lint` job — which already existed — sat outside the sweep
# entirely: V1 reported 0 hits while the severed tree still had CI invoking a
# DELETED file. An adversarial review found it by reading the workflow the sweep
# never opened. The scan now covers `.github/workflows/*.yml`, the sever removes
# the job as a whole block, and V2d parses the result, because a YAML file with
# a job key and no steps is not severable, it is broken.
#
# TWO PROSE-GRADE RESIDUALS ARE NAMED AND NOT CHASED. Neither is an edge:
# nothing executes them, nothing breaks when the module leaves, and sweeping
# them would make this test a documentation linter.
#   • `templates/generated/identifiers.tmpl` carries a `DELTA-` row in a
#     template that documents an ID prefix — a severed project has one unused
#     row in a registry.
#   • `.github/workflows/lint.yml`'s own job-inventory COMMENT names
#     `delta-boundary-lint` while listing what the file contains. V2d measures
#     and reports that survivor explicitly rather than letting a blunt grep
#     count it as a live job; the executable half is what must be zero.
# Recorded so the next reader knows they were seen and weighed, not missed.
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
  rm -f "$d"/tests/test-delta-*.sh "$d"/tests/test-lint-delta-boundary.sh \
        "$d"/tests/test-delta-severability.sh 2>/dev/null || true
  # Their registrations leave with them. THE AGGREGATOR IS DROPPED BY WHOLE
  # `run_child_suite` CALL, never by line — see _drop_child_suite_calls.
  _drop_child_suite_calls "$d/tests/full-project-test-suite.sh"
  _drop_lines "$d/.github/workflows/tests.yml"      'tests/test-delta-\|tests/test-lint-delta-boundary\|delta-boundary'
  # THE FIFTH CONSUMER: the CI job that runs the module's own lint. Removed as a
  # WHOLE JOB BLOCK, not line-by-line — dropping the two `run:` lines would leave
  # a job key with no steps, which is not a severed workflow, it is a broken one.
  _drop_yaml_job "$d/.github/workflows/lint.yml" "delta-boundary-lint"
  return 0
}

# _drop_yaml_job <workflow> <job-key> — remove a top-level job (2-space indent)
#   and every line under it, up to the next 2-space-indented key. The comment
#   block ABOVE the job is prose and stays; V1 strips comments before matching,
#   so it does not count as an edge.
_drop_yaml_job() {
  local f="$1" job="$2" tmp
  [ -f "$f" ] || return 0
  tmp="$(mktemp)"
  awk -v job="$job" '
    $0 ~ "^  " job ":[[:space:]]*$" { skip = 1; next }
    skip == 1 && /^  [A-Za-z0-9_-]+:/ { skip = 0 }
    skip == 1 { next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
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

# _drop_child_suite_calls <aggregator> — remove every `run_child_suite` CALL
#   that names a module file or one of the module's own suites. WHOLE CALL, and
#   the emphasis is the finding.
#
#   A LINE-BASED DROP IS WRONG HERE IN TWO WAYS, AND BOTH WERE LIVE. This used
#   to be `_drop_lines … 'tests/test-delta-\|tests/test-lint-delta-boundary'`,
#   and an adversarial review's follow-up hunt found:
#
#     1. A SIXTH CONSUMER the pattern never matched at all —
#        `run_child_suite "scripts/lint-delta-boundary.sh"`, the aggregator
#        invoking the module's lint DIRECTLY rather than through a tests/ path.
#        Post-sever that is `bash` on a deleted file: rc 127, and the very
#        full-suite run §3.1 defines severability BY goes red. That falsifies
#        this test's own central claim, which is why it is a fix and not a
#        fast-follow.
#     2. AN ORPHANED CONTINUATION LINE. `run_child_suite` calls span three
#        backslash-continued lines. The head and the third argument named
#        `tests/test-lint-delta-boundary.sh` and were dropped; the SECOND
#        argument names `scripts/lint-delta-boundary.sh` and was not — so a
#        bare dangling string survived, still carrying its trailing backslash.
#        `bash -n` PASSES on it (it is a syntactically valid command), so no
#        parse check could ever have caught it; only reading the surviving
#        references does.
#
#   Same lesson as the YAML job two functions down, arriving from the other
#   direction: a multi-line construct is dropped as a construct or not at all.
#
#   THE PATTERN IS DERIVED from the module manifest, so a module file that is
#   later registered directly is covered without anyone remembering to add it.
_drop_child_suite_calls() {
  local f="$1" pat e tmp
  [ -f "$f" ] || return 0
  pat='tests/test-delta-|tests/test-lint-delta-boundary'
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in */) continue ;; esac
    pat="$pat|$(printf '%s' "$e" | sed -e 's/\./\\./g')"
  done <<EOF
$MODULE_FILES
EOF
  tmp="$(mktemp)"
  awk -v pat="$pat" '
    {
      buf = buf $0 "\n"
      if ($0 ~ /\\$/) { next }          # the call continues on the next line
      if (buf ~ /^run_child_suite[ \t]/ && buf ~ pat) { buf = ""; next }
      printf "%s", buf
      buf = ""
    }
    END { if (buf != "") printf "%s", buf }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
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

# _drop_fenced_block <file> <NAME> — remove every `# <NAME>-BEGIN` … `#
#   <NAME>-END` block, markers included. EVERY pair, not the first: init.sh
#   carries two DELTA-INSTALL fences (the scripts block and the template
#   block), and a first-pair-only drop would leave the second one behind for
#   V1 to find — which is the same "a multi-line construct is dropped as a
#   construct or not at all" lesson the YAML job and the aggregator call each
#   taught from their own direction.
_drop_fenced_block() {
  local f="$1" name="$2" tmp
  [ -f "$f" ] || return 0
  tmp="$(mktemp)"
  awk -v name="$name" '
    $0 ~ "^[[:space:]]*#.*" name "-BEGIN" { skip = 1; next }
    skip == 1 { if ($0 ~ "^[[:space:]]*#.*" name "-END") skip = 0; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  return 0
}

# sever_seam <tree> — STEP 2: THE REVERT. Six core files, enumerated in this
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
  # (5) resume.sh — WP8's §10.5 fourth branch. A whole-block drop like the
  #     seam's, and for the same reason: the branch is contiguous between its
  #     markers precisely so that the sever is one operation. Dropping the
  #     single seam-delegation LINE would leave an `if` whose body reads a
  #     document nothing produces, which is not a severed greeting — it is a
  #     branch that always falls through while still claiming to be there.
  _drop_fenced_block "$d/scripts/resume.sh" "DELTA-RESUME"
  # (6) the scaffolder — WP8's copy list, BOTH fences. Post-sever there is
  #     nothing to copy: the module files were deleted in step 1, so a
  #     surviving cp line is a scaffolder that fails on every run.
  _drop_fenced_block "$d/$INIT_FILE" "DELTA-INSTALL"
  return 0
}

# ── The residual scan (V1's instrument) ─────────────────────────────────────
# Whole-line comments are stripped first, exactly as §3.3's lint does, because
# a SPEC block naming the design document is prose and not an edge. Everything
# else is matched as a FIXED string — `delta.sh` as a regex would match
# `deltaXsh`, and a scan that reports what is not there is as useless as one
# that misses what is.
# _residual_tokens <out-file> — the fixed strings a surviving edge would name.
_residual_tokens() {
  local tmp="$1" pat
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
  return 0
}

# _residual_scan_file <tree> <relative-path> -> "file:line:text" per hit
_residual_scan_file() {
  local d="$1" rel="$2" tmp
  [ -f "$d/$rel" ] || return 0
  tmp="$(mktemp)"
  _residual_tokens "$tmp"
  grep -vE '^[[:space:]]*#' "$d/$rel" 2>/dev/null \
    | grep -nFf "$tmp" 2>/dev/null \
    | sed -e "s|^|$rel:|" || true
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

_residual_scan() {   # <tree> -> "file:line:text" per hit
  local d="$1" f tmp
  tmp="$(mktemp)"
  _residual_tokens "$tmp"
  # THE WORKFLOW FILES ARE IN SCOPE, and their absence is what made the header's
  # "a fifth consumer lands here, named" claim false until an adversarial review
  # caught it. A CI job invoking a deleted script is every bit the dangling edge
  # a sourced lib would be — more so, because nothing local fails.
  for f in $(find "$d/scripts" -type f -name '*.sh' | LC_ALL=C sort) \
           "$d/$INIT_FILE" \
           $(find "$d/.github/workflows" -type f -name '*.yml' 2>/dev/null | LC_ALL=C sort); do
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
  pass "V1: after the five-consumer revert, NOT ONE executed line under scripts/, in the scaffolder, or in .github/workflows/*.yml names a module path or a --delta-* action. This is the arm that keeps the revert manifest honest, and m3 proves the workflow half of it is live rather than merely declared"
else
  fail_ "V1" "$V1_N surviving reference(s) to the module — the revert list in this file's header is incomplete:
$V1_HITS"
fi

# ── V1b: the AGGREGATOR is in scope too ────────────────────────────────────
# THE SWEEP-SCOPE ROW. `tests/full-project-test-suite.sh` is the file §3.1's
# property is stated ABOUT ("the full suite must pass"), and until an
# adversarial review's follow-up hunt it was the one file the sweep never
# opened. Two things were hiding there: a direct `run_child_suite
# "scripts/lint-delta-boundary.sh"` registration, and an orphaned continuation
# line left behind by the old line-based drop. Both name a module path on an
# executed line, so this row sees both.
#
# THE REST OF tests/ IS DELIBERATELY OUT OF SCOPE, with the reason stated
# rather than the scope quietly drawn: the module's own suites LEAVE with the
# module, and the one remaining hit — tests/test-lint-module-dependencies.sh
# writing a self-contained stub named `lint-delta-boundary.sh` into its own
# $TMP — is a FIXTURE WRITE, not a reference. It never touches the real file
# and severing the module cannot break it. Sweeping it would be the
# heredoc-false-positive class this repo already has scar tissue for.
V1B_HITS="$(_residual_scan_file "$SEV" "tests/full-project-test-suite.sh")"
V1B_N="$(printf '%s\n' "$V1B_HITS" | grep -c . || true)"
case "$V1B_N" in ''|*[!0-9]*) V1B_N=0 ;; esac
if [ "$V1B_N" -eq 0 ]; then
  pass "V1b: the severed aggregator — the file §3.1's 'the full suite must pass' is a claim ABOUT — names no module path on any executed line. It was outside the sweep until a follow-up hunt found a direct lint registration and an orphaned continuation line living in it"
else
  fail_ "V1b" "$V1B_N surviving module reference(s) in the severed aggregator:
$V1B_HITS"
fi

# ── V1c: every registration in the severed aggregator RESOLVES ─────────────
# The decisive row for the sixth consumer, and it tests the actual claim rather
# than a proxy for it. Running the real full suite is ~3h and workflow_dispatch
# -only, but "would it go red?" reduces to "does every suite it registers still
# exist?" — and `run_child_suite` on a missing file is `bash` answering 127.
# A reference the residual sweep cannot see (a variable, a renamed path) still
# lands here, because this row reads the targets and stats them.
V1C_MISSING=""
V1C_N=0
while IFS= read -r target; do
  [ -n "$target" ] || continue
  V1C_N=$((V1C_N + 1))
  [ -f "$SEV/$target" ] || V1C_MISSING="$V1C_MISSING $target"
done <<EOF
$(grep -oE 'run_child_suite "[^"]+"' "$SEV/tests/full-project-test-suite.sh" 2>/dev/null \
  | sed -e 's/run_child_suite "//' -e 's/"$//' | LC_ALL=C sort -u)
EOF
if [ -z "$V1C_MISSING" ] && [ "$V1C_N" -gt 50 ]; then
  pass "V1c: all $V1C_N distinct suites the severed aggregator registers still EXIST in the severed tree — so the ~3h run §3.1 defines severability by would not die on a missing file. This is the row that would have caught the sixth consumer on its own: run_child_suite on a deleted script is bash answering 127"
else
  fail_ "V1c" "$V1C_N targets checked; these no longer exist after the sever, so the full-suite run would go red on them:$V1C_MISSING"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V2 — the severed tree still parses, and still behaves ==="
# ════════════════════════════════════════════════════════════════════════════

V2_BAD=""
for f in $(find "$SEV/scripts" "$SEV/tests" -type f -name '*.sh' | LC_ALL=C sort); do
  bash -n "$f" 2>/dev/null || V2_BAD="$V2_BAD ${f#$SEV/}"
done
bash -n "$SEV/$INIT_FILE" 2>/dev/null || V2_BAD="$V2_BAD $INIT_FILE"
V2_N="$(find "$SEV/scripts" "$SEV/tests" -type f -name '*.sh' | grep -c . || true)"
# THE AGGREGATOR IS IN THIS SET NOW, and the honest note is that parsing is NOT
# what caught the orphaned continuation line the old line-based drop left there:
# a dangling `"...string..." \` is a syntactically valid command, so `bash -n`
# passed on it happily. V1b and V1c are what see that class. This row is here
# for the fragments a construct-level drop could still produce, not as the
# aggregator's only guard.
if [ -z "$V2_BAD" ]; then
  pass "V2a: every one of the $V2_N shell scripts left in the severed tree still parses — scripts/, tests/ (the aggregator included) and the scaffolder. The revert cut whole functions, a whole fence, a whole YAML job and whole run_child_suite calls, not fragments"
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

# ── V2d: the severed WORKFLOWS still parse ─────────────────────────────────
# Removing a CI job is a structural edit to YAML, and "the delta references are
# gone" is worth nothing if what is left will not load. Skipped with a stated
# reason rather than silently when no YAML parser is available — a row that
# quietly turns into a no-op is the silent-success class this whole track is
# about.
if python3 -c 'import yaml' >/dev/null 2>&1; then
  V2D_BAD=""
  V2D_N=0
  for f in $(find "$SEV/.github/workflows" -type f -name '*.yml' | LC_ALL=C sort); do
    V2D_N=$((V2D_N + 1))
    python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$f" >/dev/null 2>&1 \
      || V2D_BAD="$V2D_BAD ${f#$SEV/}"
  done
  # Comment lines are stripped first, EXACTLY as V1 does and for the same
  # reason. lint.yml carries a prose header that enumerates its jobs by name
  # ("...delta-boundary-lint the twelfth..."), and that line survives the sever.
  # It is documentation that has gone stale, not a CI job invoking a deleted
  # file — the same prose-grade class as identifiers.tmpl's DELTA- row, and
  # named in this file's header rather than chased. What must be gone is the
  # executable half: the job key and its steps.
  V2D_JOB="$(grep -vE '^[[:space:]]*#' "$SEV/.github/workflows/lint.yml" 2>/dev/null \
    | grep -c 'delta-boundary-lint' || true)"
  case "$V2D_JOB" in ''|*[!0-9]*) V2D_JOB=0 ;; esac
  V2D_PROSE="$(grep -cE '^[[:space:]]*#.*delta-boundary-lint' "$SEV/.github/workflows/lint.yml" 2>/dev/null || true)"
  case "$V2D_PROSE" in ''|*[!0-9]*) V2D_PROSE=0 ;; esac
  if [ -z "$V2D_BAD" ] && [ "$V2D_JOB" -eq 0 ] && [ "$V2D_N" -gt 0 ]; then
    pass "V2d: all $V2D_N severed workflow files still parse as YAML, and no EXECUTED line in lint.yml names the delta-boundary-lint job — the fifth consumer was removed as a whole block, not by deleting the two lines that named the module and leaving a job key with no steps. ($V2D_PROSE prose mention(s) survive in the file's own job-inventory comment: stale documentation, not an edge, and named in this file's header)"
  else
    fail_ "V2d" "unparseable after the sever:$V2D_BAD; surviving EXECUTED delta-boundary-lint lines in lint.yml: $V2D_JOB (want 0); files checked: $V2D_N"
  fi
else
  pass "V2d: SKIPPED with a reason — no python3 yaml module on this host, so the severed workflows' parseability cannot be checked here. V1 still proves the references are gone; this row would prove what is left still loads"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V3 — a declared set of core suites, run INSIDE the severed tree ==="
# ════════════════════════════════════════════════════════════════════════════

# NOT the ~3h full suite — CLAUDE.md records that it is workflow_dispatch-only,
# and a unit-lane test that claimed to run it would be lying about its own scope.
#
# THE SELECTION RATIONALE, STATED ACCURATELY BECAUSE THE FIRST ONE WAS NOT.
# This set used to be introduced as "chosen because they exercise the files the
# revert touches", and an adversarial review mapped the invocations: of the four
# original suites, ZERO executed validate.sh, upgrade-project.sh or
# check-maintenance.sh — three of the four reverted files. Only the seam host
# was covered. The honest map, per reverted file:
#
#   process-checklist.sh   COVERED — test-check-phase-gate-poc-block-contract.sh
#   check-phase-gate.sh /  COVERED — test-check-phase-gate.sh and
#     run-phase3-validation.sh          test-bl214-gate-snapshot-staleness.sh
#                                       (not reverted files, but the gate pair
#                                       the revert's siblings live in)
#   validate.sh            COVERED — the two validate suites added below, which
#                                    were in the unit lane and unused all along
#   upgrade-project.sh     NOT COVERED, deliberately: its suites invoke the
#                          scaffolder, which would drag an init run into a
#                          unit-lane test. Named, not hidden.
#   check-maintenance.sh   NOT COVERED, and it CANNOT BE: its only behaviour
#                          suite is tests/test-delta-wp6-cadence.sh, a delta
#                          suite this very sever deletes. That is the coverage
#                          gap this file's header records as a real cost, seen
#                          here from the other side.
#
# test-gate-principles.sh is kept for breadth (a BL-030 message-table suite) and
# is NOT claimed to cover a reverted file.
V3_SUITES="tests/test-check-phase-gate.sh
tests/test-bl214-gate-snapshot-staleness.sh
tests/test-check-phase-gate-poc-block-contract.sh
tests/test-validate-phase-state-gates.sh
tests/test-validate-counter-sanitizer.sh
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

# ── m3: the WORKFLOW half of the sweep is live, not merely added ────────────
# A scan extended to a new file class proves nothing until something in that
# class is shown to trip it. This severs everything EXCEPT the lint.yml job —
# the exact state the test shipped in before an adversarial review found the
# fifth consumer — and requires V1's instrument to name the workflow.
MUT3="$TD/mutant3"; mk_tree "$MUT3"
sever_module "$MUT3"
# ...and put the fifth consumer back, so this is the pre-review state exactly.
cp "$REPO_ROOT/.github/workflows/lint.yml" "$MUT3/.github/workflows/lint.yml"
sever_seam "$MUT3"
MUT3_HITS="$(_residual_scan "$MUT3")"
MUT3_WF="$(printf '%s\n' "$MUT3_HITS" | grep -c '^\.github/workflows/' || true)"
case "$MUT3_WF" in ''|*[!0-9]*) MUT3_WF=0 ;; esac
MUT3_SCRIPTS="$(printf '%s\n' "$MUT3_HITS" | grep -c '^scripts/' || true)"
case "$MUT3_SCRIPTS" in ''|*[!0-9]*) MUT3_SCRIPTS=0 ;; esac
if [ "$MUT3_WF" -gt 0 ] && [ "$MUT3_SCRIPTS" -eq 0 ]; then
  pass "m3: with every script consumer reverted but the delta-boundary-lint JOB left in place, V1 names the workflow — $MUT3_WF hit(s) under .github/workflows/ and $MUT3_SCRIPTS under scripts/. That is the pre-review state of this very test, in which V1 reported zero hits while the severed tree still had CI invoking a deleted file. The sweep's new file class has a witness"
else
  fail_ "m3" "workflow hits=$MUT3_WF (want > 0 — the extended sweep is not live), script hits=$MUT3_SCRIPTS (want 0 — the script revert should be complete). Hits:
$MUT3_HITS"
fi

# ── m4: the aggregator drop must be a CONSTRUCT drop, not a line drop ───────
# The counterfactual for the sixth consumer. This severs exactly as the test did
# BEFORE the follow-up hunt — the old line-based `_drop_lines` on the aggregator
# — and requires both new rows to see it. Two distinct defects have to surface:
# the DIRECT `run_child_suite "scripts/lint-delta-boundary.sh"` registration the
# old pattern never matched, and the ORPHANED CONTINUATION LINE it produced by
# dropping two of a three-line call.
MUT4="$TD/mutant4"; mk_tree "$MUT4"
rm -f "$MUT4"/tests/test-delta-*.sh "$MUT4"/tests/test-lint-delta-boundary.sh 2>/dev/null || true
printf '%s\n' "$MODULE_FILES" | while IFS= read -r e; do
  [ -n "$e" ] || continue
  case "$e" in */) rm -rf "$MUT4/$e" 2>/dev/null || true ;; *) rm -f "$MUT4/$e" 2>/dev/null || true ;; esac
done
_drop_lines "$MUT4/tests/full-project-test-suite.sh" 'tests/test-delta-\|tests/test-lint-delta-boundary'
_drop_lines "$MUT4/.github/workflows/tests.yml" 'tests/test-delta-\|tests/test-lint-delta-boundary\|delta-boundary'
_drop_yaml_job "$MUT4/.github/workflows/lint.yml" "delta-boundary-lint"
sever_seam "$MUT4"
M4_HITS="$(_residual_scan_file "$MUT4" "tests/full-project-test-suite.sh")"
M4_N="$(printf '%s\n' "$M4_HITS" | grep -c . || true)"
case "$M4_N" in ''|*[!0-9]*) M4_N=0 ;; esac
M4_MISSING=""
while IFS= read -r target; do
  [ -n "$target" ] || continue
  [ -f "$MUT4/$target" ] || M4_MISSING="$M4_MISSING $target"
done <<EOF
$(grep -oE 'run_child_suite "[^"]+"' "$MUT4/tests/full-project-test-suite.sh" 2>/dev/null \
  | sed -e 's/run_child_suite "//' -e 's/"$//' | LC_ALL=C sort -u)
EOF
M4_PARSE=ok
bash -n "$MUT4/tests/full-project-test-suite.sh" 2>/dev/null || M4_PARSE=broken
if [ "$M4_N" -gt 0 ] && [ -n "$M4_MISSING" ]; then
  pass "m4: severed the old way (line-based drop on the aggregator), V1b finds $M4_N surviving module reference(s) and V1c finds a registration pointing at a file that no longer exists —$M4_MISSING. Both rows fire. Note the aggregator still PARSES ($M4_PARSE): the orphaned continuation line is a syntactically valid command, so no parse check could have caught this and only reading the references does"
else
  fail_ "m4" "the old-style sever was not caught: V1b hits=$M4_N (want > 0), V1c missing targets='$M4_MISSING' (want non-empty), aggregator parse=$M4_PARSE"
fi

rm -rf "$TD"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

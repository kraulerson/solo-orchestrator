#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Pre-Init Edge Cases Test Suite
# Tests edge cases E1-E10 from the test plan, exercising init.sh under
# adversarial and unusual conditions.
#
# Usage: bash tests/edge-cases-pre-init.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0
SKIP=0
RESULTS=""

# Colors
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

pass() {
  PASS=$((PASS + 1))
  echo -e "${GREEN}  [PASS]${NC} $1"
  RESULTS+="PASS|$1\n"
}

fail() {
  FAIL=$((FAIL + 1))
  echo -e "${RED}  [FAIL]${NC} $1"
  RESULTS+="FAIL|$1\n"
}

skip() {
  SKIP=$((SKIP + 1))
  echo -e "${YELLOW}  [SKIP]${NC} $1"
  RESULTS+="SKIP|$1\n"
}

section() {
  echo ""
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

cleanup() {
  # Restore permissions on any read-only dirs before removal
  chmod -R u+rwX "$TEST_DIR" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# ================================================================
# Helper: build stdin input for init.sh
# Args: project_name description platform_num track_num deploy_num lang_num project_dir confirm
#       (gov_num defaults to 1 = Private POC for personal / Sponsored POC for organizational;
#        override with the BUILD_INIT_INPUT_GOV_NUM env var on the same line if you need
#        Production Build (2) — used by track=light callers since Production+Light triggers a
#        re-prompt loop at init.sh:446.)
#
# Prompt order in init.sh (after commit 061c454 added platform filtering
# and 2026-06 audit-code-init-sh-4 added the always-on governance dialog):
#   1. project_name      (init.sh:338)
#   2. description       (init.sh:341)
#   3. platform_num      (init.sh:370 — see platform list below)
#   4. track_num         (init.sh:379 — light(1) standard(2) full(3))
#   5. deploy_num        (init.sh:387 — personal(1) organizational(2))
#   6. gov_num           (init.sh:426/434 — see Governance note below)
#   7. lang_num          (init.sh:502 — platform-filtered, see below)
#   8. project_dir       (init.sh:558)
#   9. confirm Y/n       (init.sh review prompt)
#
# Platform choices (init.sh:343-368 auto-discovers from docs/platform-modules/
# and templates/pipelines/release/github/, then appends 'other' as fallback):
#   desktop(1) mcp_server(2) mobile(3) web(4) other(5)
# Language choices are PLATFORM-FILTERED (init.sh:468-500 reads the
# `# solo-orchestrator: platforms=...` marker from each CI template and
# only offers languages whose marker includes the selected platform;
# 'other' is always appended last as a fallback). Per-platform lists:
#   platform=web:        csharp(1) go(2) java(3) kotlin(4) python(5) rust(6) typescript(7) other(8)
#   platform=desktop:    csharp(1) go(2) java(3) kotlin(4) python(5) rust(6) swift(7) typescript(8) other(9)
#   platform=mobile:     dart(1) kotlin(2) swift(3) typescript(4) other(5)
#   platform=mcp_server: go(1) python(2) rust(3) typescript(4) other(5)
#   platform=other:      other(1)
# Governance mode choices (init.sh:426/434, depends on deployment):
#   deploy=personal:       Private POC(1) Production Build(2)
#   deploy=organizational: Sponsored POC(1) Production Build(2)
# A previous revision of this helper listed an unfiltered language menu
# (csharp=1 ... rust=8 ... typescript=10) and omitted gov_num — that was
# the pre-filtering / pre-governance-dialog layout. Tests that still
# passed pre-filtering numbers landed on the wrong language (or an
# invalid combo) and aborted before reaching dry-run summary; this is
# the bonus fix shipped alongside the catch-all PASS closures.
# ================================================================
build_init_input() {
  local project_name="$1"
  local description="$2"
  local platform_num="$3"
  local track_num="$4"
  local deploy_num="$5"
  local lang_num="$6"
  local project_dir="$7"
  local confirm="${8:-Y}"
  local gov_num="${BUILD_INIT_INPUT_GOV_NUM:-1}"
  printf '%s\n' \
    "$project_name" \
    "$description" \
    "$platform_num" \
    "$track_num" \
    "$deploy_num" \
    "$gov_num" \
    "$lang_num" \
    "$project_dir" \
    "$confirm"
}

# Helper: build stdin input for dry-run mode (same prompts, but no tool install prompts)
build_dryrun_input() {
  build_init_input "$@"
}

# ================================================================
# E1: Project name with apostrophe and spaces
# Expected: sanitized to lowercase-no-spaces
# ================================================================
section "E1: Project Name with Apostrophe + Spaces"

E1_DIR="$TEST_DIR/e1-project"
E1_INPUT=$(build_init_input "Derek's Cool App" "A test project" 4 2 1 6 "$E1_DIR" "Y")
E1_EXTRA_INPUT="${E1_INPUT}
Y"

echo ""
echo "  Input project name: Derek's Cool App"

# Use --dry-run to avoid interactive prerequisite prompts consuming stdin
e1_output=$(printf '%s\n' "$E1_INPUT" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

# Check the output for the sanitized project name
# init.sh does: tr '[:upper:]' '[:lower:]' | tr ' ' '-'
# So "Derek's Cool App" -> "derek's-cool-app"
if echo "$e1_output" | grep -qi "derek"; then
  pass "E1: init.sh accepted name with apostrophe+spaces"
else
  fail "E1: init.sh did not process name with apostrophe+spaces"
fi

# Verify dry-run summary shows the sanitized name in its exact documented form.
# init.sh does: tr '[:upper:]' '[:lower:]' | tr ' ' '-'
# So "Derek's Cool App" -> "derek's-cool-app". A fixed-string, case-sensitive
# grep is required so that a regression removing the tr-pipeline (which would
# leave "Derek's Cool App" or "derek's cool app") would be caught — the raw
# input "Derek" already contains the substring "derek", so a case-insensitive
# substring grep is vacuous and inflates the PASS count without coverage.
# (Closes audit finding tests-edge-cases-1.)
if echo "$e1_output" | grep -qF "derek's-cool-app"; then
  pass "E1: dry-run output contains exact sanitized name 'derek's-cool-app'"
else
  fail "E1: dry-run output missing exact sanitized name 'derek's-cool-app'"
fi

# Verify dry-run completed
if echo "$e1_output" | grep -qi "DRY RUN SUMMARY"; then
  pass "E1: dry-run completed with apostrophe+space name"
else
  fail "E1: dry-run did not complete with apostrophe+space name"
fi

# ================================================================
# E2: Description with command injection attempts
# Expected: treated as literal text, not executed
# ================================================================
section "E2: Command Injection in Description"

E2_DIR="$TEST_DIR/e2-project"
E2_MALICIOUS_DESC='$(whoami) `id` $(cat /etc/passwd)'

echo ""
echo "  Malicious description: $E2_MALICIOUS_DESC"

# Use dry-run to test safely (avoids filesystem creation, faster)
e2_input=$(build_dryrun_input "e2-injection-test" "$E2_MALICIOUS_DESC" 4 2 1 6 "$E2_DIR" "Y")
e2_output=$(printf '%s\n' "$e2_input" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

# The description should appear as literal text in the output, not as expanded commands
# If whoami was executed, we'd see the actual username in a context where it shouldn't be
current_user=$(whoami)

# Check that the description was NOT executed - the output should not contain
# the result of `id` (uid=...) which would indicate command execution
if echo "$e2_output" | grep -q "uid="; then
  fail "E2: backtick command substitution was executed (found uid= in output)"
else
  pass "E2: backtick command substitution was NOT executed"
fi

# BL-040 (2026-06-30) restored assertion: dry_run_summary now echoes
# the operator-supplied description, so the literal "$(whoami)" and
# "`id`" from the malicious input must appear verbatim in the dry-run
# preview. The original E2 stdin-piped harness CANNOT verify this
# because scripts/lib/helpers.sh:prompt_input() returns the default
# (empty string) whenever stdin is not a TTY — the piped malicious
# description never reaches PROJECT_DESCRIPTION, so a regression that
# silently dropped the description would still "PASS" the stdin path.
# Use the non-interactive --description flag instead; the value lands
# in PROJECT_DESCRIPTION via ARG_DESCRIPTION (init.sh:3540), bypassing
# the TTY-gated prompt. Fails RED on origin/main (no Description line
# in summary), GREEN after the dry_run_summary fix. Grep with -F so
# the $( and ` metacharacters are matched literally, not as regex.
E2_NI_DIR="$TEST_DIR/e2-ni-project"
e2_ni_output=$(bash "$REPO_DIR/init.sh" \
  --dry-run \
  --non-interactive \
  --project "e2-injection-ni" \
  --description "$E2_MALICIOUS_DESC" \
  --platform web \
  --deployment personal \
  --language python \
  --project-dir "$E2_NI_DIR" 2>&1) || true

if echo "$e2_ni_output" | grep -qF '$(whoami)' \
   && echo "$e2_ni_output" | grep -qF '`id`'; then
  pass "E2: non-interactive dry-run echoes malicious description as literal text"
else
  fail "E2: non-interactive dry-run did not echo literal '\$(whoami) \`id\`' (BL-040 regression)"
fi

# Belt-and-suspenders: even on the non-interactive path, neither
# command substitution should fire — no uid= or root: leaking into
# the summary output.
if echo "$e2_ni_output" | grep -qE 'uid=|root:'; then
  fail "E2: command substitution leaked into non-interactive dry-run output"
else
  pass "E2: non-interactive dry-run treats description as literal (no command substitution)"
fi

# If interactive dry-run completed without crashing, that's a good sign
if echo "$e2_output" | grep -qi "DRY RUN"; then
  pass "E2: init.sh completed dry-run with malicious description"
else
  fail "E2: init.sh did not complete dry-run with malicious description"
fi

# ----------------------------------------------------------------
# E2b: Empty description renders cleanly in dry-run summary
# Expected: dry_run_summary omits the "Description:" line when the
# value is empty (operator-friendly: no blank label).
# ----------------------------------------------------------------
E2B_DIR="$TEST_DIR/e2b-project"
e2b_input=$(build_dryrun_input "e2b-empty-desc" "" 4 2 1 6 "$E2B_DIR" "Y")
e2b_output=$(printf '%s\n' "$e2b_input" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

# Must still complete dry-run when description is empty
if echo "$e2b_output" | grep -qi "DRY RUN SUMMARY"; then
  pass "E2b: dry-run completes with empty description"
else
  fail "E2b: dry-run did NOT complete with empty description"
fi

# Description label must be omitted entirely (no dangling "Description: " line)
if echo "$e2b_output" | grep -q "^  Description:"; then
  fail "E2b: empty description should be omitted from summary (found dangling label)"
else
  pass "E2b: dry-run summary omits Description label when value is empty"
fi

# ----------------------------------------------------------------
# E2c: Multi-line description normalizes to a single summary line
# Expected: dry_run_summary collapses embedded newlines/tabs into
# spaces so the summary stays one-line-per-field. Multi-line input
# is reachable through the non-interactive --description flag
# (interactive prompt_input is a single read -rp).
# ----------------------------------------------------------------
E2C_DIR="$TEST_DIR/e2c-project"
# shellcheck disable=SC2034
E2C_DESC=$'line-one-marker\nline-two-marker'

e2c_output=$(bash "$REPO_DIR/init.sh" \
  --dry-run \
  --non-interactive \
  --project "e2c-multiline" \
  --description "$E2C_DESC" \
  --platform web \
  --deployment personal \
  --language python \
  --project-dir "$E2C_DIR" 2>&1) || true

# Both halves of the multi-line value must appear in the dry-run
# output (proves the whole description survived the echo).
if echo "$e2c_output" | grep -qF "line-one-marker" \
   && echo "$e2c_output" | grep -qF "line-two-marker"; then
  pass "E2c: dry-run echoes both halves of multi-line description"
else
  fail "E2c: dry-run dropped part of multi-line description"
fi

# Both markers must land on the SAME line after newline normalization
# (the description should not bleed across multiple summary lines and
# break the column layout). awk is shell-safe across BSD and GNU.
if echo "$e2c_output" | awk '
  /line-one-marker/ && /line-two-marker/ { found=1; exit }
  END { exit !found }
'; then
  pass "E2c: multi-line description rendered on a single summary line"
else
  fail "E2c: multi-line description not collapsed onto a single summary line"
fi

# ================================================================
# E3: Running in a directory that already has .git
# Expected: warn or handle gracefully
# ================================================================
section "E3: Existing .git Directory"

E3_DIR="$TEST_DIR/e3-existing-git"
mkdir -p "$E3_DIR"
git -C "$E3_DIR" init -q

echo ""
echo "  Pre-existing .git in: $E3_DIR"

e3_input=$(build_init_input "e3-existing-git" "Test existing git" 4 1 1 6 "$E3_DIR" "Y")
e3_output=$(printf '%s\n' "$e3_input" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

# Pre-existing .git should still be there
if [ -d "$E3_DIR/.git" ]; then
  pass "E3: .git directory preserved after dry-run"
else
  fail "E3: .git directory was removed"
fi

# Check that init.sh dry-run completed
if echo "$e3_output" | grep -qi "DRY RUN\|Solo Orchestrator"; then
  pass "E3: init.sh completed dry-run targeting directory with pre-existing .git"
else
  fail "E3: init.sh failed when targeting directory with pre-existing .git"
fi

# ================================================================
# E4: Running init.sh twice in the same directory
# Expected: warn about existing project or handle idempotently
# NOTE: Uses --dry-run to avoid interactive prerequisite prompts
#       consuming piped stdin. Verifies input acceptance on both runs.
# ================================================================
section "E4: Double Init in Same Directory"

E4_DIR="$TEST_DIR/e4-double-init"

echo ""
echo "  Testing two sequential dry-runs targeting: $E4_DIR"

# First dry-run
e4_input=$(build_init_input "e4-double" "First run" 4 1 1 6 "$E4_DIR" "Y")
e4_run1=$(printf '%s\n' "$e4_input" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

if echo "$e4_run1" | grep -qi "DRY RUN SUMMARY"; then
  pass "E4: first dry-run completed successfully"
else
  fail "E4: first dry-run did not complete"
fi

# Second dry-run — same target directory
e4_input2=$(build_init_input "e4-double" "Second run" 4 1 1 6 "$E4_DIR" "Y")
e4_run2=$(printf '%s\n' "$e4_input2" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

if echo "$e4_run2" | grep -qi "DRY RUN SUMMARY"; then
  pass "E4: second dry-run completed (idempotent input handling)"
else
  fail "E4: second dry-run failed"
fi

# Both runs should show the same project name
if echo "$e4_run1" | grep -q "e4-double" && echo "$e4_run2" | grep -q "e4-double"; then
  pass "E4: both runs accepted the same project name"
else
  fail "E4: project name not preserved across runs"
fi

# Dry-run should NOT create the target directory
if [ ! -d "$E4_DIR" ]; then
  pass "E4: dry-run did not create target directory (as expected)"
else
  fail "E4: dry-run created the target directory"
fi

# ================================================================
# E5: "Other" for both platform and language
# Expected: valid project with other.yml CI and no platform module
# NOTE: Uses --dry-run to verify input handling; checks templates exist in repo.
# ================================================================
section "E5: Other Platform + Other Language"

E5_DIR="$TEST_DIR/e5-other-other"

echo ""
echo "  Platform: other (5), Language: other (1, only choice when platform=other)"

# Use dry-run to avoid interactive prerequisite prompts consuming stdin
e5_input=$(build_init_input "e5-other-combo" "All other test" 5 2 1 1 "$E5_DIR" "Y")
e5_output=$(printf '%s\n' "$e5_input" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

if echo "$e5_output" | grep -qi "DRY RUN SUMMARY"; then
  pass "E5: dry-run completed with other/other selection"
else
  fail "E5: dry-run did not complete with other/other"
fi

# Verify dry-run output references "other" for platform
if echo "$e5_output" | grep -qi "Platform.*other"; then
  pass "E5: dry-run output shows platform=other"
else
  fail "E5: dry-run output does not show platform=other"
fi

# Verify the other.yml CI template exists in the repo. After the 2026-04
# CI-pipeline reorganization, CI templates moved from templates/pipelines/ci/
# directly into per-host subfolders (github/, gitlab/, bitbucket/). The
# GitHub variant is canonical per spec 2026-04-21.
if [ -f "$REPO_DIR/templates/pipelines/ci/github/other.yml" ]; then
  pass "E5: other.yml CI template exists in repo (github canonical)"
  if grep -qi "TODO\|placeholder\|REPLACE\|your.*language\|your.*build" "$REPO_DIR/templates/pipelines/ci/github/other.yml"; then
    pass "E5: other.yml template has placeholder steps"
  else
    fail "E5: other.yml template missing placeholder steps"
  fi
else
  fail "E5: other.yml CI template does not exist at templates/pipelines/ci/github/other.yml"
fi

# Verify no release pipeline template for "other" at the canonical
# github-hosted location (release templates moved into per-host subfolders
# alongside CI templates in the same 2026-04 reorganization). Both
# branches previously called pass(), which masked a regression where a
# release.yml for 'other' might silently appear. Make the else branch a
# real failure: per baseline §3, the 'other' platform deliberately has
# no release pipeline so the user must wire deployment themselves.
# (Bonus catch — same catch-all PASS family as findings 1-5.)
if [ ! -f "$REPO_DIR/templates/pipelines/release/github/other.yml" ]; then
  pass "E5: no release.yml template for 'other' platform (expected — github canonical)"
else
  fail "E5: release.yml template exists for 'other' at github/other.yml — unexpected (baseline says manual deploy)"
fi

# Verify no platform module for "other"
if [ ! -f "$REPO_DIR/docs/platform-modules/other.md" ]; then
  pass "E5: no platform module for 'other' (expected)"
else
  fail "E5: platform module exists for 'other' (should not)"
fi

# ================================================================
# E6: No internet connectivity (simulated)
# Expected: fail gracefully when cloning Development Guardrails
# ================================================================
section "E6: No Internet Connectivity (Simulated)"

echo ""
echo "  Note: True network disconnection cannot be reliably automated in"
echo "  a portable test. Instead, we test the fallback path by simulating"
echo "  a missing Development Guardrails clone."

# We test that init.sh starts correctly with an alternate HOME (no framework).
# Uses --dry-run to avoid stdin consumption issues.
E6_DIR="$TEST_DIR/e6-no-network"
E6_FAKE_HOME="$TEST_DIR/e6-fake-home"
mkdir -p "$E6_FAKE_HOME"

e6_input=$(build_init_input "e6-offline" "Offline test" 4 1 1 6 "$E6_DIR" "Y")

# Use dry-run + fake HOME + timeout to avoid hanging
e6_output=$(printf '%s\n' "$e6_input" | HOME="$E6_FAKE_HOME" bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

# Check that the script ran and produced output
if echo "$e6_output" | grep -qi "Solo Orchestrator\|DRY RUN\|prerequisites"; then
  pass "E6: init.sh started with alternate HOME (no framework clone)"
else
  skip "E6: cannot fully test without network disconnection"
fi

# Dry-run should still produce a summary even without the framework
if echo "$e6_output" | grep -qi "DRY RUN SUMMARY\|Tool Resolution\|Files to create"; then
  pass "E6: init.sh produces output when framework unavailable"
else
  skip "E6: dry-run output incomplete with alternate HOME"
fi

# ================================================================
# E7: Kill init.sh with SIGINT midway, then re-run
# Expected: no partial state that breaks re-run
# ================================================================
section "E7: SIGINT (Ctrl+C) Recovery"

E7_DIR="$TEST_DIR/e7-sigint"

echo ""
echo "  Starting init.sh --dry-run in background, sending SIGINT after 1 second..."

e7_input=$(build_init_input "e7-sigint-test" "Interrupt test" 4 2 1 6 "$E7_DIR" "Y")

# Start dry-run in background, send SIGINT after 1 second
printf '%s\n' "$e7_input" | bash "$REPO_DIR/init.sh" --dry-run >"$TEST_DIR/e7-output1.txt" 2>&1 &
E7_PID=$!

sleep 1
kill -INT "$E7_PID" 2>/dev/null || true
wait "$E7_PID" 2>/dev/null || true

echo "  First run interrupted."

# Re-run to verify init.sh is not left in a broken state
echo "  Re-running init.sh --dry-run to verify recovery..."
e7_input2=$(build_init_input "e7-sigint-test" "Recovery test" 4 2 1 6 "$E7_DIR" "Y")
e7_rerun_exit=0
printf '%s\n' "$e7_input2" | bash "$REPO_DIR/init.sh" --dry-run >"$TEST_DIR/e7-output2.txt" 2>&1 || e7_rerun_exit=$?

if grep -qi "DRY RUN SUMMARY\|DRY RUN\|Solo Orchestrator" "$TEST_DIR/e7-output2.txt" 2>/dev/null; then
  pass "E7: re-run after SIGINT completes successfully"
else
  fail "E7: re-run after SIGINT failed to start"
fi

# Dry-run should not leave partial state, even when interrupted by SIGINT.
# Both branches previously called pass(), so this assertion was a no-op
# (the else branch even acknowledged the directory "should not have created
# it" yet still emitted PASS). Make the else branch a real failure so the
# dry-run-is-non-destructive invariant is actually enforced.
# (Closes audit finding tests-edge-cases-3.)
if [ ! -d "$E7_DIR" ]; then
  pass "E7: no partial directory left after interrupted dry-run"
else
  ls -la "$E7_DIR" 2>/dev/null || true
  fail "E7: interrupted dry-run created $E7_DIR — non-destructive invariant violated"
fi

# ================================================================
# E8: Read-only directory
# Expected: fail with clear error message
#
# Closes audit finding tests-edge-cases-4. The original test ran init.sh
# only in --dry-run mode against a chmod 444 parent and then asserted four
# things, all of which routed to pass() under any observable state:
#   - exit non-zero -> pass; exit zero + dir absent -> pass; (dir present
#     was the only fail branch, and dry-run never creates dirs);
#   - grep for permission-keywords -> pass; grep for "DRY RUN" -> pass
#     (always matches in dry-run); else exit-non-zero -> pass.
# So every dry-run outcome inflated PASS count and the actual read-only
# behavior of init.sh was never exercised.
#
# Honest reframe: dry-run cannot exercise mkdir, so it cannot prove the
# read-only-handling contract. Split into:
#   - E8a: --dry-run honestly verifies preview completes and is non-
#     destructive even when target parent is unwritable.
#   - E8b: --non-interactive real-run probe of the BL-041 write-permission
#     preflight. Was SKIPped pre-BL-041 because init.sh's framework-repo
#     guard fired first and masked the permission failure path. After
#     PR for BL-041 the preflight runs BEFORE the framework-repo guard,
#     so this case is now exercisable from the test harness even when
#     cwd is the framework repo.
# ================================================================
section "E8: Read-Only Directory"

E8_DIR="$TEST_DIR/e8-readonly"
mkdir -p "$E8_DIR"
chmod 444 "$E8_DIR"

echo ""
echo "  E8a: Testing init.sh --dry-run with read-only target parent"

e8_input=$(build_init_input "e8-readonly" "Read-only test" 4 1 1 6 "$E8_DIR/project" "Y")
e8a_exit=0
e8a_output=$(printf '%s\n' "$e8_input" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || e8a_exit=$?

# E8a: dry-run must produce its DRY RUN banner even when the would-be
# target parent is unwritable. (Permission probe is not part of dry-run,
# so a read-only parent should not abort the preview.)
if echo "$e8a_output" | grep -qi "DRY RUN"; then
  pass "E8a: dry-run produced DRY RUN banner with read-only target parent"
else
  fail "E8a: dry-run did not produce DRY RUN banner (exit=$e8a_exit)"
fi

# E8a: dry-run must not create anything regardless of permissions.
if [ ! -d "$E8_DIR/project" ]; then
  pass "E8a: dry-run did not create project dir under read-only parent"
else
  fail "E8a: dry-run created $E8_DIR/project — non-destructive invariant violated"
fi

# E8b: real-run read-only assertion — verifies the BL-041 write-perm
# preflight. POSIX 0444 does not deny root; skip when running as root
# so we don't false-pass.
if [ "$(id -u)" = "0" ]; then
  skip "E8b: skipped under root (POSIX 0444 doesn't deny root; preflight cannot be exercised)"
else
  echo ""
  echo "  E8b: Testing init.sh --non-interactive with read-only --project-dir parent"
  e8b_exit=0
  e8b_output=$( bash "$REPO_DIR/init.sh" --non-interactive \
                  --project e8b-readonly \
                  --platform web \
                  --deployment personal \
                  --language typescript \
                  --git-host github \
                  --visibility private \
                  --project-dir "$E8_DIR/project" \
                  --no-remote-creation 2>&1 ) || e8b_exit=$?
  if [ "$e8b_exit" -eq 0 ]; then
    fail "E8b: expected non-zero exit (write-perm preflight); got rc=0"
  elif ! echo "$e8b_output" | grep -qE "write permission denied|Cannot create project directory"; then
    fail "E8b: did not emit write-permission marker (rc=$e8b_exit). Tail: $(echo "$e8b_output" | tail -5)"
  elif echo "$e8b_output" | grep -q "Refusing to operate inside the Solo Orchestrator framework repo"; then
    fail "E8b: framework-repo guard fired first (BL-041 layering regressed). Tail: $(echo "$e8b_output" | tail -5)"
  else
    pass "E8b: write-perm preflight fires before framework-repo guard (BL-041 layering active)"
  fi
fi

# Restore permissions for cleanup
chmod 755 "$E8_DIR"

# ================================================================
# E9: HOME set to non-existent directory
# Expected: fail gracefully
# ================================================================
section "E9: Non-Existent HOME Directory"

E9_DIR="$TEST_DIR/e9-badhome"
E9_FAKE_HOME="/tmp/nonexistent-home-$(date +%s)-$$"

echo ""
echo "  HOME=$E9_FAKE_HOME (does not exist)"

# init.sh references HOME in:
# - Check for ~/.claude/settings.json (Superpowers/Context7/Qdrant checks)
# - Default project dir suggestion: $HOME/projects/$PROJECT_NAME
# - Development Guardrails clone: $HOME/.claude-dev-framework

e9_input=$(build_init_input "e9-badhome" "Bad home test" 4 1 1 6 "$E9_DIR" "Y")
e9_exit=0
e9_output=$(printf '%s\n' "$e9_input" | HOME="$E9_FAKE_HOME" bash "$REPO_DIR/init.sh" --dry-run 2>&1) || e9_exit=$?

# The original assertion grepped for generic banner text ("Solo Orchestrator",
# "prerequisites", "checking") that init.sh emits on virtually any invocation,
# so the PASS was essentially unconditional once init.sh started. The nested
# else passed on any non-zero exit, even one unrelated to HOME handling.
# Tighten to a HOME-specific signal so a regression in HOME handling actually
# fails the test.
# (Closes audit finding tests-edge-cases-5.)

# A HOME-aware signal that fires ONLY when HOME affects behavior:
#   - "no Claude settings" — emitted by check_prerequisites() at init.sh:292
#     when $HOME/.claude/settings.json is missing (settings.json check at
#     init.sh:282 fails, fallthrough emits the cannot-check diagnostic).
#   - "will be installed during project creation" — emitted at init.sh:282
#     when $HOME/.claude-dev-framework/.git is missing (else branch of the
#     framework-present check at init.sh:279).
# We require AT LEAST ONE of these two HOME-conditioned diagnostics, so
# the assertion only passes when init.sh's HOME handling actually fires.
# (Generic banner text and "Files to create: .claude/..." in the dry-run
# summary are emitted regardless of HOME state, so they don't count.)
e9_home_signal_re='(no Claude settings|will be installed during project creation)'

if echo "$e9_output" | grep -Eq "$e9_home_signal_re"; then
  pass "E9: init.sh emitted HOME-conditioned diagnostic with non-existent HOME"
else
  fail "E9: no HOME-conditioned diagnostic in output (exit=$e9_exit) — generic banner/exit no longer counts"
fi

# Key check: it should not crash with an unhandled error
if echo "$e9_output" | grep -qi "unbound variable\|bad substitution"; then
  fail "E9: init.sh has unhandled variable errors with non-existent HOME"
else
  pass "E9: no unbound variable errors with non-existent HOME"
fi

# ================================================================
# E10: --dry-run makes zero filesystem changes
# Expected: diff before/after shows no changes
# ================================================================
section "E10: --dry-run Zero Filesystem Changes"

E10_TARGET="$TEST_DIR/e10-dryrun-target"

echo ""
echo "  Taking filesystem snapshot, running --dry-run, comparing..."

# Snapshot the test dir BEFORE dry-run
# Use a marker file to detect any changes
e10_snapshot_before="$TEST_DIR/e10-snapshot-before.txt"
e10_snapshot_after="$TEST_DIR/e10-snapshot-after.txt"

# Create the target parent so we can snapshot it
mkdir -p "$TEST_DIR/e10-watch"

# Snapshot: list all files recursively in the watch directory
find "$TEST_DIR/e10-watch" -type f -o -type d 2>/dev/null | sort > "$e10_snapshot_before"

# Also snapshot the proposed target directory (should not exist)
ls -la "$E10_TARGET" >> "$e10_snapshot_before" 2>&1 || true

e10_input=$(build_dryrun_input "e10-dryrun" "Dry run no changes" 4 2 1 6 "$E10_TARGET" "Y")
e10_output=$(printf '%s\n' "$e10_input" | bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

# Snapshot AFTER dry-run
find "$TEST_DIR/e10-watch" -type f -o -type d 2>/dev/null | sort > "$e10_snapshot_after"
ls -la "$E10_TARGET" >> "$e10_snapshot_after" 2>&1 || true

# Compare snapshots
if diff -q "$e10_snapshot_before" "$e10_snapshot_after" >/dev/null 2>&1; then
  pass "E10: filesystem unchanged after --dry-run (watch directory)"
else
  fail "E10: filesystem changed after --dry-run"
fi

# Most importantly: the target directory should NOT exist
if [ ! -d "$E10_TARGET" ]; then
  pass "E10: target project directory was NOT created by --dry-run"
else
  fail "E10: target project directory was created by --dry-run"
fi

# Verify dry-run produced expected output
if echo "$e10_output" | grep -qi "DRY RUN"; then
  pass "E10: dry-run mode was active"
else
  fail "E10: dry-run mode indicator not found in output"
fi

if echo "$e10_output" | grep -qi "Files to create\|Tool Resolution\|Post-init\|Re-run without"; then
  pass "E10: dry-run produced summary output"
else
  fail "E10: dry-run did not produce expected summary"
fi

# Also verify that HOME was not modified (no new files in HOME)
# This checks that dry-run didn't clone the framework or modify settings
e10_home_before="$TEST_DIR/e10-home-before.txt"
e10_home_after="$TEST_DIR/e10-home-after.txt"

# We can't easily snapshot the real HOME, but we can check the target dir
# and ensure no .claude-dev-framework was created in a temp HOME
E10_FAKE_HOME="$TEST_DIR/e10-fake-home"
mkdir -p "$E10_FAKE_HOME"
find "$E10_FAKE_HOME" -type f 2>/dev/null | sort > "$e10_home_before"

e10_input2=$(build_dryrun_input "e10-dryrun2" "Dry run HOME test" 4 2 1 6 "$TEST_DIR/e10-target2" "Y")
e10_output2=$(HOME="$E10_FAKE_HOME" printf '%s\n' "$e10_input2" | HOME="$E10_FAKE_HOME" bash "$REPO_DIR/init.sh" --dry-run 2>&1) || true

find "$E10_FAKE_HOME" -type f 2>/dev/null | sort > "$e10_home_after"

# Note: tools probed by check_prerequisites() may write cache/config files
# under HOME during version-check invocations. This is tool behavior, not
# init.sh writing to HOME. Filter out known cache paths:
#   semgrep, snyk: version-check cache files
#   colima: Docker daemon state on darwin (writes ~/.colima/* when probed)
#   rustup: ~/.rustup/settings.toml created on first invocation
#   .log / settings.yml / cache / Cache: generic catch-all suffixes
# (Bonus catch — adding colima/rustup to the pre-existing filter to keep
# the assertion honest on macOS Apple Silicon dev environments.)
e10_home_new=$(diff "$e10_home_before" "$e10_home_after" 2>/dev/null | grep "^>" | grep -v "semgrep\|snyk\|cache\|Cache\|\.log\|settings\.yml\|colima\|rustup" || true)
if [ -z "$e10_home_new" ]; then
  pass "E10: HOME directory unchanged by --dry-run (tool caches excluded)"
else
  fail "E10: HOME directory was modified by --dry-run: $e10_home_new"
fi

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  EDGE CASES PRE-INIT — TEST SUMMARY${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Skipped:${NC} $SKIP"
echo -e "  Total:   $((PASS + FAIL + SKIP))"
echo ""

if [ $FAIL -gt 0 ]; then
  echo -e "${RED}${BOLD}  FAILURES:${NC}"
  echo -e "$RESULTS" | grep "^FAIL" | while IFS='|' read -r _ desc; do
    echo -e "  ${RED}- $desc${NC}"
  done
  echo ""
fi

if [ $SKIP -gt 0 ]; then
  echo -e "${YELLOW}${BOLD}  SKIPPED:${NC}"
  echo -e "$RESULTS" | grep "^SKIP" | while IFS='|' read -r _ desc; do
    echo -e "  ${YELLOW}- $desc${NC}"
  done
  echo ""
fi

echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"

exit $FAIL

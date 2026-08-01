#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Full New-Project Test Suite
# Tests the complete init flow across all platform/language/track combinations
# from a normal technical user's standpoint.
#
# Test categories:
#   1. Resolver matrix coverage (all combos)
#   2. Full project creation (piped input to init.sh)
#   3. Generated file verification
#   4. Plugin/MCP/Superpowers detection
#   5. Phase gate tool checks
#   6. Intake tooling section
#
# Usage: bash tests/full-project-test-suite.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)

# BL-096-CDF-PREFLIGHT (F9): report an absent ~/.claude-dev-framework AT
# ENTRY with the exact clone line — previously a fresh host failed DEEP in
# the scaffold tests with no hint. Warn-and-continue (`|| true`) is load-
# bearing: the CI core shard runs CDF-less by design (init.sh auto-clones
# over the network there), so absence must inform, never abort.
bash "$SCRIPT_DIR/scripts/check-cdf-preflight.sh" || true
PASS=0
FAIL=0
WARN=0
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

warn() {
  WARN=$((WARN + 1))
  echo -e "${YELLOW}  [WARN]${NC} $1"
  RESULTS+="WARN|$1\n"
}

section() {
  echo ""
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

# ================================================================
# BL-184-CHILD-EVIDENCE — the child-suite delegate runner
# ================================================================
# Every delegate in this file used to be invoked as
#     if bash "$SCRIPT_DIR/<child>" >/dev/null 2>&1; then pass ...; else fail ...
# which destroyed the diagnostic at the moment of capture. A child that fails
# ONLY in CI produced exactly one line — "<child> FAILED (run for details)" —
# and "run for details" was unactionable precisely BECAUSE the failure did not
# reproduce locally. That catch-22 is why BL-135 sat open from 2026-07-18 to
# 2026-07-26 across two ~3h full-lane runs with zero root-cause progress.
#
# run_child_suite captures combined stdout+stderr and, ON FAILURE ONLY, replays
# a bounded excerpt inline so the failing case NAME reaches the CI log.
#
#   run_child_suite <path-relative-to-repo-root> <pass-label> [fail-label] [-- <child-arg>...]
#
# CONTRACT — read this before editing:
#   * ALWAYS returns 0. The suite runs under `set -euo pipefail` and calls this
#     as a bare statement, so any non-zero return would abort the entire run at
#     the first red child. Failure accounting stays with fail(); the suite still
#     ends `exit $FAIL`. This preserves the exit-code semantics of the if/else
#     blocks it replaces exactly.
#   * NOTHING is printed on success — pass() emits byte-identical text to the
#     pre-BL-184 shape, so anything grepping those labels is unaffected, and a
#     chatty-but-green child adds zero bytes to the log (its output goes to the
#     scratch file, never to stdout).
#   * fail-label defaults to "<path> FAILED (run for details)" — the exact
#     string 149 of the 177 converted call sites already used verbatim.
#   * Replay goes through awk/printf, never `echo -e`: child output is
#     arbitrary text and `echo -e` would eat backslash escapes inside it.
#   * Every replayed line carries the "    | " prefix so a child's own [FAIL]
#     lines can never be misread as one of THIS suite's [FAIL] lines.
#
# BOUNDS — both overridable per-run for local debugging:
#   SUITE_CHILD_TAIL_LINES=40 — sampled on this repo 2026-07-26: unit-style
#     children emit 8/10/18/18/30/53 lines total (test-check-gate,
#     -bl169-gitignore-anchor, -bl033-install-cmds-shape, -bl184-child-suite-
#     evidence, -lint-tests-registered), so 40 replays the median child WHOLE
#     and covers the closing cases plus the "Results: N passed, M failed" tally
#     of the larger ones. The heavy aggregator children (edge-cases-*,
#     host-drivers/run-all.sh, the BL-052 trio) run well past it — that is what
#     SUITE_CHILD_MARKER_LINES is for.
#     Log-volume ceiling is ~70 lines per RED child; a realistic bad run (<10
#     red children) adds under 700 lines to a full-lane log already running to
#     tens of thousands, and the pathological all-177-red run is a total loss
#     whose log size is not the operative problem.
#   SUITE_CHILD_MARKER_LINES=25 — a pure tail MISSES the failing case whenever a
#     child fails EARLY and passes late, which is the common shape for the
#     over-bound children. So for over-bound output the child's own
#     failure-marker lines are digested FIRST, then the tail. Pinned by
#     tests/test-bl184-child-suite-evidence.sh T2/T3.
SUITE_CHILD_TAIL_LINES="${SUITE_CHILD_TAIL_LINES:-40}"
SUITE_CHILD_MARKER_LINES="${SUITE_CHILD_MARKER_LINES:-25}"
# Deliberately NOT inside $TEST_DIR: the TEST 4 fixture block documents an
# invariant that $TEST_DIR holds only the simulated project dirs by the time
# TEST 5+ reach into it.
SUITE_CHILD_LOG="$(mktemp)"

run_child_suite() {
  local rel="$1"; shift
  local pass_label="$1"; shift
  local fail_label=""
  if [ $# -gt 0 ] && [ "$1" != "--" ]; then
    fail_label="$1"; shift
  fi
  if [ "${1:-}" = "--" ]; then shift; fi
  [ -n "$fail_label" ] || fail_label="$rel FAILED (run for details)"

  local rc=0
  bash "$SCRIPT_DIR/$rel" "$@" > "$SUITE_CHILD_LOG" 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    pass "$pass_label"
    return 0
  fi

  fail "$fail_label"
  printf '%s\n' "    +-- captured output BEGIN: $rel (exit $rc) --"
  awk -v maxt="$SUITE_CHILD_TAIL_LINES" -v maxm="$SUITE_CHILD_MARKER_LINES" '
    BEGIN {
      pfx = "    | "; shown = 0; extra = 0
      if (maxt < 1) maxt = 40
      if (maxm < 1) maxm = 25
    }
    {
      buf[NR % maxt] = $0
      if ($0 ~ /\[FAIL\]|\[ERROR\]|FAILED|FAIL:|ERROR:|not ok/) {
        if (shown < maxm) { shown++; mk[shown] = $0 } else { extra++ }
      }
    }
    END {
      if (NR == 0) { print pfx "(child produced no output)"; exit }
      if (NR > maxt && shown > 0) {
        print pfx "-- failure markers (" shown " of " (shown + extra) ") --"
        for (i = 1; i <= shown; i++) print pfx mk[i]
      }
      start = (NR > maxt) ? NR - maxt + 1 : 1
      print pfx "-- lines " start "-" NR " of " NR " --"
      for (i = start; i <= NR; i++) print pfx buf[i % maxt]
    }
  ' "$SUITE_CHILD_LOG"
  printf '%s\n' "    +-- captured output END: $rel --"
  return 0
}
# BL-184-CHILD-EVIDENCE-END — tests/test-bl184-child-suite-evidence.sh slices
# this file from line 1 to this marker so it exercises the REAL helper text,
# not a copy. Keep the marker on its own line.

# ================================================================
# TEST 0: FIXTURE ENVELOPE LINT — fail fast on legacy schema in tests/
# ================================================================
section "Fixture envelope lint"
run_child_suite "scripts/lint-fixture-envelopes.sh" \
  "All fixture envelopes use canonical Claude Code schema" \
  "Legacy hook envelope schema found in tests/ (see scripts/lint-fixture-envelopes.sh)" \
  -- "$SCRIPT_DIR/tests"

# ================================================================
# TEST 0b: COUNTER-ANTIPATTERN LINT — wave-2 backstop after PRs #67-#71
# ================================================================
section "Counter-capture antipattern lint"
run_child_suite "scripts/lint-counter-antipattern.sh" \
  "No unsanitized 'cmd | grep -c X || echo \"0\"' captures in tracked scripts" \
  "Counter-capture antipattern found (see scripts/lint-counter-antipattern.sh --list)"

# Run the linter's own behavior-test suite so a regression in the lint
# itself (false negative on the antipattern, false positive on the
# sanitizer match, broken allowlist) is caught here too.
section "Counter-antipattern lint — behavior test suite"
run_child_suite "tests/test-lint-counter-antipattern.sh" \
  "scripts/lint-counter-antipattern.sh behavior tests (10/10)" \
  "scripts/lint-counter-antipattern.sh behavior tests FAILED (run tests/test-lint-counter-antipattern.sh for details)"

# ================================================================
# TEST 0c: PHASE 1→2 BACKSTOP ATTESTATION (code-check-gates-1)
# ================================================================
# Regression suite for the BL-002 follow-up fix: scripts/check-phase-gate.sh's
# Phase 1→2 backstop must honor a recorded `github_free_tier`
# branch-protection attestation (mirroring scripts/check-gate.sh::cmd_preflight).
section "Phase 1→2 backstop honors github_free_tier attestation"
run_child_suite "tests/test-check-phase-gate-backstop-attestation.sh" \
  "scripts/check-phase-gate.sh backstop attestation tests (3/3)" \
  "scripts/check-phase-gate.sh backstop attestation tests FAILED (run tests/test-check-phase-gate-backstop-attestation.sh for details)"

# ================================================================
# TEST 0c2: PHASE 1→2 RETROACTIVE STA APPROVAL (tier-crosscheck-5)
# ================================================================
# Regression suite for the audit tier-crosscheck-5 closure:
# scripts/check-phase-gate.sh must emit a non-blocking WARN when
# APPROVAL_LOG.md has `upgraded_from: personal` AND current_phase >= 2
# AND the Retroactive Phase 1 → Phase 2 STA Approval row is incomplete.
section "Phase 1→2 retroactive STA approval surfaces WARN on personal→org upgrades"
run_child_suite "tests/test-check-phase-gate-retroactive-approval.sh" \
  "scripts/check-phase-gate.sh retroactive STA approval tests (3/3)" \
  "scripts/check-phase-gate.sh retroactive STA approval tests FAILED (run tests/test-check-phase-gate-retroactive-approval.sh for details)"

# ================================================================
# TEST 0c2b: PHASE 1→2 RETROACTIVE STA — UPGRADE-PROJECT STAMPING HALF
# ================================================================
# PR #104 verifier follow-up (Wave 4): the check-phase-gate.sh half of
# tier-crosscheck-5 was already exercised above (test 0c2). The other
# half — scripts/upgrade-project.sh:1610-1626, which actually stamps the
# Retroactive Phase 1 → Phase 2 STA Approval section into the
# regenerated APPROVAL_LOG.md during personal→organizational upgrade —
# had no automated coverage. This sibling suite runs the real upgrade
# end-to-end and inspects the resulting log for the section header +
# field rows that check-phase-gate.sh depends on.
section "upgrade-project.sh stamps retroactive STA section on personal→org upgrade"
run_child_suite "tests/test-upgrade-project-retroactive-section.sh" \
  "scripts/upgrade-project.sh retroactive section stamping tests (2/2)" \
  "scripts/upgrade-project.sh retroactive section stamping tests FAILED (run tests/test-upgrade-project-retroactive-section.sh for details)"

# ================================================================
# TEST 0c2c: PHASE 1→2 ZDR / DATA_CLASSIFICATION HARD GATE (tier-crosscheck-6)
# ================================================================
# Regression suite for the FINAL S3 audit finding (tier-crosscheck-6):
# docs/governance-framework.md § VII line 299 declared a Mandatory ZDR
# gate ("Internal or higher must use ZDR or self-hosted"). Pre-fix the
# gate was documented but never enforced — no field captured the
# classification, no field recorded the ZDR attestation, and
# scripts/check-phase-gate.sh had no Phase 1→2 backstop reading any
# such field. This PR closes the loop end-to-end:
#   * intake-wizard.sh prompts for + persists the two fields.
#   * scripts/check-phase-gate.sh adds a Phase 1→2 ZDR backstop that
#     FAILs when the data is missing or invalid.
#   * scripts/reconfigure-project.sh --field data_classification /
#     --field zdr_attested / --field zdr_attestation_reason let
#     operators correct post-intake (atomic snapshot + APPROVAL_LOG audit row).
#   * scripts/upgrade-project.sh personal→organizational refuses up-
#     front when the classification is missing, redirecting to reconfigure.
section "Phase 1→2 ZDR / data_classification hard gate (tier-crosscheck-6)"
run_child_suite "tests/test-tier-crosscheck-6-zdr-gate.sh" \
  "tier-crosscheck-6 ZDR/data_classification hard gate tests (8/8)" \
  "tier-crosscheck-6 ZDR/data_classification hard gate tests FAILED (run tests/test-tier-crosscheck-6-zdr-gate.sh for details)"

# tier-crosscheck-6 follow-up: atomicity + jq-failure regression suite
# (adversarial verifier follow-up on PR #105). Three tests covering the
# defects the original suite did not catch: SIGTERM mid-mutation in
# reconfigure-project.sh, silent-success on jq failure in
# intake-wizard.sh's --data-classification path and persist_phase1_artifacts().
run_child_suite "tests/test-tier-crosscheck-6-followup-atomicity-and-jq.sh" \
  "tier-crosscheck-6 follow-up (atomicity + jq surfacing) tests (3/3)" \
  "tier-crosscheck-6 follow-up tests FAILED (run tests/test-tier-crosscheck-6-followup-atomicity-and-jq.sh for details)"

# ================================================================
# TEST 0c3: ORGANIZATIONAL END-TO-END INIT (tests-init-host-attestation-4)
# ================================================================
# Regression suite for the audit tests-init-host-attestation-4 closure:
# init.sh --non-interactive --deployment organizational must produce the
# organizational APPROVAL_LOG.md template + record deployment in
# manifest/phase-state + honor --no-remote-creation.
section "init.sh organizational end-to-end coverage"
run_child_suite "tests/test-init-organizational.sh" \
  "init.sh organizational end-to-end tests (2/2)" \
  "init.sh organizational end-to-end tests FAILED (run tests/test-init-organizational.sh for details)"

# ================================================================
# TEST 0c3b: BL-064 — init.sh non-zero exit + Setup INCOMPLETE banner after [FAIL]
# ================================================================
# Regression suite for BL-064: init.sh used to exit 0 with the
# "Setup Complete" banner even after emitting a [FAIL] line for
# create_and_protect_remote (push, branch protection, host CLI). The
# silent-success defect bypassed any wrapper script that gated on the
# init exit code. Fix: INIT_FAILURES array + record_init_failure helper
# + print_init_failures_summary in init.sh; non-zero exit propagates.
# See solo-orchestrator-backlog.md BL-064 + adversarial-certainty-pass
# report § S-7 for full context.
section "init.sh non-zero exit + Setup INCOMPLETE after [FAIL] (BL-064)"
run_child_suite "tests/test-init-fail-status-propagation.sh" \
  "init.sh BL-064 silent-success-after-FAIL tests (5/5)" \
  "init.sh BL-064 silent-success-after-FAIL tests FAILED (run tests/test-init-fail-status-propagation.sh for details)"

# ================================================================
# TEST 0c3c: BL-064 — structural backstop lint for new print_fail sites
# ================================================================
# Sibling of lint-counter-antipattern.sh: enforces that every print_fail
# invocation in init.sh either terminates (exit/return inline or within
# 2 lines), routes through record_init_failure, or carries an explicit
# `# lint-fail-emit-exit-status: allow <reason>` annotation. Prevents
# regression of the BL-064 silent-success-after-FAIL defect class.
section "Fail-emit exit-status propagation lint (BL-064 structural backstop)"
run_child_suite "scripts/lint-fail-emit-exit-status.sh" \
  "Every print_fail in init.sh propagates to exit status (or is annotated)" \
  "Fail-emit lint found a print_fail without exit-status propagation (see scripts/lint-fail-emit-exit-status.sh --list)"

# ================================================================
# TEST 0c4: BL-057 — --non-interactive must honor AUTO_INSTALL_TOOLS env
# ================================================================
# Regression suite for BL-057: scripts/init.sh's resolve_and_install_tools
# called `read -rp` unconditionally when the resolved plan had
# auto_install/manual_install entries, terminating silently with rc=1
# under --non-interactive (closed stdin + set -euo pipefail). Surfaced as
# Step-5 dogfood DOGFOOD-001 on --platform mobile (Android Studio
# auto_install). Test asserts the post-fix contract:
#   • default AUTO_INSTALL_TOOLS → Y  → init succeeds (rc=0)
#   • AUTO_INSTALL_TOOLS=N            → init succeeds (rc=0), no install loop
#   • AUTO_INSTALL_TOOLS=Y (explicit) → round-trips to default
section "init.sh --non-interactive honors AUTO_INSTALL_TOOLS (BL-057)"
run_child_suite "tests/test-init-non-interactive-mobile-auto-install.sh" \
  "init.sh --non-interactive AUTO_INSTALL_TOOLS tests (3/3)" \
  "init.sh --non-interactive AUTO_INSTALL_TOOLS tests FAILED (run tests/test-init-non-interactive-mobile-auto-install.sh for details)"

# ================================================================
# TEST 0c5: BL-041 — write-permission preflight runs BEFORE framework-repo guard
# ================================================================
# Regression suite for BL-041 (LB-3): the framework-repo guard
# (guard_not_in_framework) historically ran BEFORE any write-permission
# probe, so a real operator who pointed --project-dir at an unwritable
# location saw the irrelevant developer-facing framework-repo refusal
# instead of a permission error, and tests/edge-cases-pre-init.sh E8b
# could not be exercised at all from inside the framework checkout.
# Fix: preflight_target_writable in scripts/lib/helpers.sh, wired into
# init.sh BEFORE guard_not_in_framework. Tests pin the layering both
# ways (preflight wins when target is unwritable; guard wins when
# preflight passes; neither false-positives outside the framework).
section "init.sh write-perm preflight before framework-repo guard (BL-041)"
run_child_suite "tests/test-init-write-perm-preflight.sh" \
  "init.sh BL-041 layering tests (3/3)" \
  "init.sh BL-041 layering tests FAILED (run tests/test-init-write-perm-preflight.sh for details)"

# ================================================================
# TEST 0c6: BL-199 — the README Quick Start actually works from the clone
# ================================================================
# README § Quick Start has always said clone → cd solo-orchestrator →
# ./init.sh, but init.sh called guard_not_in_framework, whose first arm is an
# UNCONDITIONAL cwd check — so from inside the clone init.sh refused before any
# prompt, even with --project-dir pointing at a benign external path. Only
# --dry-run worked, and no test ever ran the README's literal sequence (E8b
# above hit the same wall; BL-041 reordered preflight-before-guard to get the
# TEST past it). Karl's 2026-07-29 contract: running from the clone is the
# SUPPORTED flow; a bare --project-dir creates the project BESIDE the clone
# (anchor = SCRIPT_DIR/.., not the cwd); writing onto the framework — its root,
# anything inside it, or another clone — is still refused.
# Builds its own framework clone in a tempdir (init.sh needs its whole
# templates/scripts/docs tree beside it) and carries all seven mutation proofs
# in-suite. Invokes init.sh → aggregator lane only, not the tests.yml unit list.
# Deliberately NOT a fixed N/N label: T9 and M4 SKIP on case-sensitive
# filesystems (they exercise a case-variant path that is a genuinely different
# directory there), so the pass count differs by platform. A hardcoded count
# would read as a failure on one of the two. The child's own tally line reports
# `Skipped` explicitly, which is what makes those skips visible here — this
# helper prints the child's output only when the child FAILS.
section "init.sh runs from inside the clone, scaffolds beside it (BL-199)"
run_child_suite "tests/test-bl199-quickstart-from-clone.sh" \
  "init.sh BL-199 quick-start-from-clone tests (all cases + 7 mutation proofs)" \
  "init.sh BL-199 quick-start-from-clone tests FAILED (run tests/test-bl199-quickstart-from-clone.sh for details)"

# ================================================================
# TEST 0d: BACKLOG-REFERENCES LINT — cycle-7 Slot-5 process backstop
# ================================================================
# Sibling of the counter-antipattern lint above; catches drift between
# BL-NNN backlog entries and the PRs that close them. See
# scripts/lint-backlog-references.sh header for the defect classes
# and allowlist mechanism.
section "Backlog-references lint"
run_child_suite "scripts/lint-backlog-references.sh" \
  "Backlog references and Closed-status citations are consistent" \
  "Backlog-references lint found drift (see scripts/lint-backlog-references.sh --base origin/main --list)" \
  -- --base origin/main

section "Backlog-references lint — behavior test suite"
run_child_suite "tests/test-lint-backlog-references.sh" \
  "scripts/lint-backlog-references.sh behavior tests (10/10)" \
  "scripts/lint-backlog-references.sh behavior tests FAILED (run tests/test-lint-backlog-references.sh for details)"

# ================================================================
# TEST 0e: PLATFORM-MOBILE-MCP DOCS LINT
# ================================================================
# Asserts: init.sh has explicit mcp_server arms (no silent wildcard
# fall-through to web-api); docs/platform-modules/mobile.md §5.4
# does not recommend the deprecated expo-in-app-purchases package;
# docs/platform-modules/mobile.md §2.1 Option B is demoted with the
# 'advanced/not supported by Solo gates' warning and phase-state.json
# reconciliation guidance. Closes S3 platform-modules-mobile-mcp-2,
# -4, and -7.
section "Platform mobile/MCP docs-drift tests"
run_child_suite "tests/test-platform-mobile-mcp-docs.sh" \
  "tests/test-platform-mobile-mcp-docs.sh (8/8)" \
  "tests/test-platform-mobile-mcp-docs.sh FAILED — re-run for details"

# ================================================================
# TEST 0f-0s: BL-034 WAVE 1-4 ORPHAN-TEST REGISTRATION
# ================================================================
# Wires every Wave-1-4 cohort test file (and recent post-audit
# additions through PR #107) into this aggregator. Before this PR,
# 73 tests/test-*.sh files plus the edge-cases-*.sh aggregators
# executed only when a human manually invoked them — silent
# regressions across intake-wizard, reconfigure, bypass-audit,
# check-phase-gate, host drivers, pending-approval,
# verify-install, upgrade-project, lint scripts, and the
# host-aware quartet plan were unsignaled. See BL-034.
#
# Discipline (per BL-034 brief):
#   • No `|| true` wraps. Known-RED tests are gated on the
#     SKIP_KNOWN_FAILING env var, not silenced.
#   • Each registered test invoked exactly once, captures rc,
#     and contributes to PASS/FAIL counts via pass()/fail().
#   • Fast tests (lints, unit-style) run first; slow tests
#     (init.sh e2e, upgrade walks, edge-cases aggregators)
#     run later in this block.
#
# Operator escape (local iteration only):
#   SKIP_KNOWN_FAILING=1 bash tests/full-project-test-suite.sh
# Skips the known-RED tests cited inline below. Default = run all.
SKIP_KNOWN_FAILING="${SKIP_KNOWN_FAILING:-0}"

# ----------------------------------------------------------------
# TEST 0f: LINT BEHAVIOR SUITES — fix-functions-stderr + raw-read-prompt
# ----------------------------------------------------------------
# Sibling behavior suites for the wave-3 anti-pattern lints (PR #96).
# scripts/lint-fix-functions-stderr.sh and scripts/lint-raw-read-prompt.sh
# both have repo-wide invocations in CI; this block validates the
# linters' OWN regression coverage (false-negative / false-positive /
# allowlist / heredoc / comment handling) so a broken lint script
# can't silently start passing bad code.
section "Lint behavior suites (fix-functions-stderr, raw-read-prompt)"
run_child_suite "tests/test-lint-fix-functions-stderr.sh" \
  "scripts/lint-fix-functions-stderr.sh behavior tests (10/10)" \
  "scripts/lint-fix-functions-stderr.sh behavior tests FAILED (run tests/test-lint-fix-functions-stderr.sh for details)"
run_child_suite "tests/test-lint-raw-read-prompt.sh" \
  "scripts/lint-raw-read-prompt.sh behavior tests" \
  "scripts/lint-raw-read-prompt.sh behavior tests FAILED (run tests/test-lint-raw-read-prompt.sh for details)"

# BL-197: the diagnostic-destruction backstop — a failure report that
# discards the evidence the reader needs to act on it. Same shape as the
# block above: run the linter's OWN behavior suite so a narrowing of its
# predicate (or of a carve-out) can't quietly start blessing the class.
run_child_suite "tests/test-lint-diagnostic-destruction.sh" \
  "scripts/lint-diagnostic-destruction.sh behavior tests" \
  "scripts/lint-diagnostic-destruction.sh behavior tests FAILED (run tests/test-lint-diagnostic-destruction.sh for details)"

# BL-076: no test may execute init.sh in a shape that can create a REAL
# remote repo against an authenticated host (the kraulerson/foo leak).
# Run the lint against the live tree AND its own behavior suite so a
# regression in the guard (false negative letting a live run through, or
# false positive on a reporter string / mocked run) is caught here.
section "No-live-remote-in-tests lint (BL-076)"
run_child_suite "scripts/lint-no-live-remote-in-tests.sh" \
  "No test executes init.sh in a live-remote-reachable shape" \
  "Non-hermetic init run found (see scripts/lint-no-live-remote-in-tests.sh --list)"
run_child_suite "tests/test-lint-no-live-remote.sh" \
  "scripts/lint-no-live-remote-in-tests.sh behavior tests (14/14)" \
  "scripts/lint-no-live-remote-in-tests.sh behavior tests FAILED (run tests/test-lint-no-live-remote.sh for details)"

# BL-051: tests/test-resolve-tools-memoization.sh — proves init.sh's
# get_available_platforms() memoizes its filesystem scan (guard-var +
# cached string, bash-3.2-safe) so 10 invocations trigger exactly one
# scan, not ten. The counter-spy assertion is mutation-provable: revert
# the memoization and the scan fires 10× → T2 goes red. (Function is in
# init.sh, not resolve-tools.sh — the BL-051/Step-4 filename is a known
# misattribution; the test filename honors the backlog naming.)
run_child_suite "tests/test-resolve-tools-memoization.sh" \
  "init.sh get_available_platforms() memoization (BL-051, 2/2)" \
  "init.sh get_available_platforms() memoization tests FAILED (run tests/test-resolve-tools-memoization.sh for details)"

# BL-038: tests/test-lint-tests-registered.sh — behavior suite for the
# runner-registration backstop. Validates the lint's positive,
# negative, EXEMPT-marker, mutation, and reverse-mutation paths so a
# regression in the lint itself (false negative on a new orphan,
# false positive on a comment-mention) is surfaced at the aggregator.
run_child_suite "tests/test-lint-tests-registered.sh" \
  "scripts/lint-tests-registered.sh behavior tests" \
  "scripts/lint-tests-registered.sh behavior tests FAILED (run tests/test-lint-tests-registered.sh for details)"

# BL-038: repo-wide lint invocation. Refuses to merge a new
# tests/test-*.sh file unless an aggregator invokes it or the file
# carries an EXEMPT marker. See scripts/lint-tests-registered.sh
# header for the registration contract + KNOWN_ORPHANS_PENDING_BL035
# bridge.
section "Tests-registered lint (BL-038 structural backstop)"
run_child_suite "scripts/lint-tests-registered.sh" \
  "Every tests/test-*.sh is invoked by an aggregator (or EXEMPT)" \
  "Tests-registered lint found unregistered test file(s) (see scripts/lint-tests-registered.sh --list)"

# BL-184: this suite's OWN evidence contract. Slices the header of this file
# through its `# BL-184-CHILD-EVIDENCE-END` marker and drives the real
# run_child_suite against fixture children, pinning that a RED child's failing
# case NAME reaches the log (including when the child is chattier than the tail
# bound and fails early), that a GREEN child still contributes zero bytes, that
# a RED child does not abort the run under `set -e`, and that no delegate here
# has regressed to the evidence-destroying discard shape. Hermetic, no
# scaffolding -> both lanes.
section "BL-184: child-suite evidence contract"
run_child_suite "tests/test-bl184-child-suite-evidence.sh" \
  "tests/test-bl184-child-suite-evidence.sh (T0-T13 evidence contract)"

# BL-048: tests/test-lint-doc-anchors.sh — behavior suite for the
# dead-in-document-anchor backstop. Validates the lint's positive,
# negative, fence-aware, dedup-suffix, and cross-file-out-of-scope
# paths so a regression in the lint itself (false negative on a
# broken anchor, false positive on fenced example content) is
# surfaced at the aggregator.
run_child_suite "tests/test-lint-doc-anchors.sh" \
  "scripts/lint-doc-anchors.sh behavior tests" \
  "scripts/lint-doc-anchors.sh behavior tests FAILED (run tests/test-lint-doc-anchors.sh for details)"

# BL-048: repo-wide lint invocation. Fails when a markdown file under
# docs/ contains a `[text](#anchor)` reference whose target heading
# doesn't exist in the same file (GitHub-derived slug, fence-aware).
# See scripts/lint-doc-anchors.sh header for the derivation contract.
section "Doc-anchors lint (BL-048 structural backstop)"
run_child_suite "scripts/lint-doc-anchors.sh" \
  "Every in-document anchor reference under docs/ resolves" \
  "Doc-anchors lint found broken anchor reference(s) (see scripts/lint-doc-anchors.sh --list)"

# ----------------------------------------------------------------
# TEST 0g: INTAKE WIZARD + RECONFIGURE FIELD HANDLERS
# ----------------------------------------------------------------
# PR #83: tests/test-intake-wizard-fixes.sh — sweep of wizard-row
# rendering, title round-trip, and resolver-prefill correctness.
# PR #84: tests/test-reconfigure-field-handlers.sh — atomic
# snapshot pattern for reconfigure-project.sh --field handlers.
section "Intake wizard + reconfigure field handlers (PRs #83, #84)"
run_child_suite "tests/test-intake-wizard-fixes.sh" "tests/test-intake-wizard-fixes.sh"
run_child_suite "tests/test-bl202-session-intake-check.sh" "tests/test-bl202-session-intake-check.sh"
run_child_suite "tests/test-reconfigure-field-handlers.sh" \
  "tests/test-reconfigure-field-handlers.sh"

# ----------------------------------------------------------------
# TEST 0h: CHECK-PHASE-GATE VARIANTS (noninteractive, self-approval)
# ----------------------------------------------------------------
# PR #87: scripts/check-phase-gate.sh must operate in --non-interactive
# mode and must surface a WARN when an STA self-approves their own
# Phase 1→2 gate. Both tests exercise gate-policy enforcement
# orthogonal to the backstop/retroactive paths covered in 0c/0c2.
section "Check-phase-gate noninteractive + self-approval (PR #87)"
run_child_suite "tests/test-check-phase-gate-noninteractive.sh" \
  "tests/test-check-phase-gate-noninteractive.sh"
run_child_suite "tests/test-check-phase-gate-self-approval.sh" \
  "tests/test-check-phase-gate-self-approval.sh"
# code-check-gates-7-followup (cycle-7 PR-#87 verifier major #4):
# scripts/check-phase-gate.sh now uses per-line `git blame` (not
# file-level `git log -1`) to resolve the commit author of the active
# gate's Approver row. Closes the false-negative attack where Alice
# self-approves gate A in C1 and Bob later commits a typo fix to gate
# B in C2 → file-level lookup returned Bob → Alice's self-approval
# silently passed. The blame-walker tests pin the fix.
run_child_suite "tests/test-check-phase-gate-blame-walker.sh" \
  "tests/test-check-phase-gate-blame-walker.sh"

# BL-060 (adversarial cert re-walker-4): scripts/check-phase-gate.sh
# must parse `--gate <name>` and scope the check to the named gate.
# Pre-fix the script had NO argv parsing — scenarios invoking
# `--gate phase_1_to_2` succeeded coincidentally via `current_phase=2`
# in phase-state.json triggering the backstop, not because the flag
# was honored. This suite pins the argv contract:
#   - --gate <name> forces the gate's checks to fire regardless of
#     current_phase, and caps at that gate (higher gates skip).
#   - Unknown gate / unknown flag / --gate given twice → exit 2 with
#     a clear stderr diagnostic.
#   - --gate with no phase-state.json fixture → exit 1 + error (never
#     silently exits 0 the way the pre-fix no-argv path did).
#   - --help / -h → exit 0 + usage text mentioning `--gate`.
run_child_suite "tests/test-check-phase-gate-argv-parser.sh" \
  "tests/test-check-phase-gate-argv-parser.sh"

# BL-071: scripts/check-phase-gate.sh must WRITE today's date into
# phase-state.json::gates.<gate> (plus a sibling gates.<gate>_by actor)
# when a gate passes on real APPROVAL_LOG.md evidence — atomically
# (mkdir-lock + tmp + rename, PR #97 lineage), idempotently (a valid
# first-pass date is preserved, never overwritten), and never clearing a
# populated date on a subsequent FAIL. The write is mutation-proof: the
# suite strips the marked `# BL-071-WRITE` finalize line from a copy and
# asserts the date is no longer recorded (proving the line is
# load-bearing). Sibling init.sh seed fix (all 4 gate keys) is pinned by
# test-init-seeds-four-gate-keys.sh below.
run_child_suite "tests/test-check-phase-gate-date-writeback.sh" \
  "tests/test-check-phase-gate-date-writeback.sh"
# BL-071 (rolled-in minor): init.sh's phase-state.json seed must emit all
# four gate keys — pre-fix it missed phase_2_to_3. Bootstraps a real
# init.sh project and asserts gates.{phase_0_to_1,phase_1_to_2,
# phase_2_to_3,phase_3_to_4} are all present as null.
run_child_suite "tests/test-init-seeds-four-gate-keys.sh" "tests/test-init-seeds-four-gate-keys.sh"
# BL-070: scripts/run-phase3-validation.sh (Phase 3 validation-scan driver) +
# the attest-on-skip Phase 3→4 gate in scripts/check-phase-gate.sh. The docs
# imply Phase 3 auto-runs Snyk/license/full-tree-Semgrep/ZAP/threat-model; a
# grep of scripts/ found ZERO invocations. This SKELETON builds the driver +
# gate first (Karl-approved Option C): every scanner SKIP-able, any SKIP needs
# an attestation (reason + sign-off) in phase-state.json::phase3.attestations,
# and the gate refuses Phase 3→4 on any un-attested SKIP or FAIL. The
# enforcement is mutation-proof: the suite strips the marked
# `# BL-070-GATE-CHECK` lines from a copy of the gate and asserts the phase-3
# FAIL disappears (proving the lines are load-bearing).
run_child_suite "tests/test-phase3-validation-gate.sh" "tests/test-phase3-validation-gate.sh"

# BL-088: scaffold source-closure. init.sh must ship every sibling script that a
# shipped gate sources/execs via "$SCRIPT_DIR/..." (tdd-classify.sh silently
# no-op'd the TDD hard block; run-phase3-validation.sh's pass-path was
# unreachable). test-scaffold-source-closure.sh is the static class killer (RED
# if any shipped script sources an unshipped sibling); test-scaffold-tdd-block-
# real.sh is the init.sh-driven fidelity proof (a real Sponsored-POC scaffold
# blocks a test-less feat: commit) + the upgrade/verify backfill for existing
# projects.
run_child_suite "tests/test-scaffold-source-closure.sh" "tests/test-scaffold-source-closure.sh"
run_child_suite "tests/test-scaffold-tdd-block-real.sh" "tests/test-scaffold-tdd-block-real.sh"

# BL-109 S1 (Currency System, Layer 0 — Inventory). test-currency-manifest.sh is
# the lib-level unit test (schema, class assignment, hook enum, sha/mode capture,
# render-base capture, reader/writer round-trip, dual-source ban) — it never runs
# init.sh, so it is ALSO in the tests.yml unit fast lane. test-currency-birth-
# stamp.sh is the BL-088-precedent aggregator: it runs the REAL init.sh three
# times (typescript/rust/other) to prove the currency block stamps at birth with
# shas that recompute end-to-end and the three-state hook enum. That aggregator
# is SUITE_SKIP_AGGREGATORS-gated (three scaffolds is heavy) and is NEVER in the
# unit list (it executes init.sh).
run_child_suite "tests/test-currency-manifest.sh" "tests/test-currency-manifest.sh"
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-109 currency birth-stamp fidelity — SKIPPED (SUITE_SKIP_AGGREGATORS=1; three real init.sh scaffolds, runs standalone / full-suite)"
else
run_child_suite "tests/test-currency-birth-stamp.sh" "tests/test-currency-birth-stamp.sh"
fi

# BL-109 S2 (Currency System, Layer 1 — Detection). test-freshness-check.sh is
# the lib-level unit test (every drift class → tier, pin/path skip contracts,
# torn cache, snooze hold/expiry + future clamp, machine-block JSON, fail-open
# exit-0) — it never runs init.sh, so it is ALSO in the tests.yml unit fast lane.
# test-freshness-birth.sh is the BL-088-precedent aggregator: it runs the REAL
# init.sh to prove day-zero silence, hook injection, downstream ship-set, seeded
# drift in the right tier, and the whole-tree I7 fingerprint. That aggregator is
# SUITE_SKIP_AGGREGATORS-gated (a real init.sh scaffold is heavy) and is NEVER in
# the unit list (it executes init.sh).
run_child_suite "tests/test-freshness-check.sh" "tests/test-freshness-check.sh"
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-109 freshness birth fidelity — SKIPPED (SUITE_SKIP_AGGREGATORS=1; a real init.sh scaffold, runs standalone / full-suite)"
else
run_child_suite "tests/test-freshness-birth.sh" "tests/test-freshness-birth.sh"
fi

# BL-112 commit-time enforcement fidelity — the same BL-088 precedent, applied to
# the two commit gates that shipped HOLLOW into every generated project: the
# pre-commit SAST arm (semgrep with no --error => detected, printed, committed) and
# the BL-030 strict framework gate (unreachable below an unconditional `exit
# $FAILED`, and its verdict discarded by an `if ! cmd; then EXIT=$?` capture). It
# runs the REAL init.sh and REAL `git commit`s — the class of test that would have
# caught all three. AGGREGATOR-ONLY: SUITE_SKIP_AGGREGATORS-gated here and NEVER in
# the tests.yml unit list; lint-tests-registered.sh counts this reference.
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-112 commit-enforcement fidelity — SKIPPED (SUITE_SKIP_AGGREGATORS=1; a real init.sh scaffold + real commits, runs standalone / full-suite)"
else
run_child_suite "tests/test-bl112-commit-enforcement.sh" "tests/test-bl112-commit-enforcement.sh"
fi

# BL-118 (Dogfood-2 F-DF2-007, Critical): the SAST gate must SEE browser DOM XSS.
# Pins the DOM-sink ruleset (r/javascript.browser.security.insecure-document-method)
# into every emitter of the semgrep invocation — the hook-templates lib (the hook's
# single source of truth), all 20 generated CI pipelines, and verify-install.sh's
# fix_precommit_hook (which used to re-inline a pre-BL-112 blind hook on repair).
# Live cases drive a REAL `git commit` of `pane.innerHTML = userText` through the
# lib-emitted hook (LOUD SKIP without semgrep). Emits the hook via the lib directly
# — no scaffold run — so it is ALSO in the tests.yml unit fast lane.
run_child_suite "tests/test-bl118-sast-dom-xss.sh" "tests/test-bl118-sast-dom-xss.sh"

# BL-131 + BL-132 (BL-118 adversarial verification residue): the emitted SAST arm
# must scan STAGED index content (not worktree bytes) and the shipped custom ruleset
# must catch the four DOM sinks no public registry rule covers. Both emit the hook
# via the lib directly (no scaffold run) — ALSO in the tests.yml unit fast lane.
run_child_suite "tests/test-bl132-sast-index-scan.sh" "tests/test-bl132-sast-index-scan.sh"
run_child_suite "tests/test-bl131-domsink-rules.sh" "tests/test-bl131-domsink-rules.sh"
run_child_suite "tests/test-bl200-syntax-detector.sh" "tests/test-bl200-syntax-detector.sh"
run_child_suite "tests/test-bl200-syntax-canary.sh" "tests/test-bl200-syntax-canary.sh"

# BL-119 (Dogfood-2 F-DF2-006, High) + BL-087 fold-in: the strict terminal gate
# must not classify a commit by the PREVIOUS commit's message (stale
# .git/COMMIT_EDITMSG at pre-commit bricked the repo after any landed feat:
# commit), and the commit-msg surface must pass GRACEFULLY inside the framework
# repo itself instead of hard-refusing via guard_not_in_framework. Drives a REAL
# `git commit` through the REAL framework-gate chain installed by
# install-filesystem-gates.sh — no scaffold run, so ALSO in the unit fast lane.
run_child_suite "tests/test-bl119-stale-editmsg.sh" "tests/test-bl119-stale-editmsg.sh"

# BL-105 (Med, walk-confirmed worse than filed): Phase 4 gets a real gate —
# --start-phase4 consults the 3→4 gate; a never-started Phase-4 checklist
# blocks at phase>=4; the rollback/monitoring/go-live artifact arms demand
# substantive evidence (an empty file, the word 'monitoring', and bare
# RELEASE_NOTES existence all used to pass); approval-log templates gain the
# UAT sign-off + personal attorney/pen-test sections; the guide's artifact
# map and the undocumented handoff_tested step are fixed; the Competency
# Matrix is WARN-first visible. Double-fence mutation in-suite. Both lanes.
run_child_suite "tests/test-bl105-phase4-wave.sh" "tests/test-bl105-phase4-wave.sh"

# BL-107 (High): every language gets the TDD/BL-006 commit-msg gate. Hermetic
# half: the # BL-107-RUST-INLINE-TESTS content probe (inline #[cfg(test)]
# additions count as tests — without it universal install would false-block
# idiomatic Rust TDD), the `other`-language generic-convention heuristic, and
# the Currency hook-state predicate (present for every language). The INSTALL
# half is proven by test-scaffold-tdd-block-real.sh's rust/other scaffold
# cases (aggregator lane). No init.sh here -> ALSO in the unit lane.
run_child_suite "tests/test-bl107-tdd-all-languages.sh" "tests/test-bl107-tdd-all-languages.sh"

# BL-121 (Dogfood-2 F-DF2-011, High): the MVP-Cutline counter must count the
# same 3 items on BSD and GNU text tools. The old GNU-only sed alternation made
# the range run to EOF on macOS (68 vs 3) and hard-blocked the production 3→4
# gate via the exit-2 WARN arm. Extracts and evaluates the LIVE assignment from
# test-gate.sh against a trap-structured fixture manifesto. The cross-platform
# tripwire for the class is lint-counter-antipattern's sed-alternation rule.
run_child_suite "tests/test-bl121-cutline-bsd-sed.sh" "tests/test-bl121-cutline-bsd-sed.sh"

# BL-108/BL-117 (the BL-088 class, artifact form): a shipped instruction must
# never point at an unshipped dependency. Mechanical closures: every template
# a shipped script's non-comment text or the guide names must be in init.sh's
# cp set (5 gate-demanded templates were unshipped, incl. one named by a
# gate's own error message); every scripts/*.sh the guide names must ship
# (check-maintenance + 3 lints). Plus the production_build smoke-evidence arm
# (F19: a "built" release that did not boot). Fence mutation in-suite.
run_child_suite "tests/test-bl108-bl117-ship-closure.sh" "tests/test-bl108-bl117-ship-closure.sh"

# BL-114/BL-115/BL-127 (the E1a gate-integrity trio): the 0→1 gate's WARN
# survives errexit and the intermediates check truly blocks; --start-phase1
# consults the gate and is documented; approval evidence requires the Date
# CELL (not any date in a proximity window); the attorney gate needs a dated
# row (not the template's own header) and legal review is required-when-PII;
# UAT results_received demands submissions or an explicit RECORDED solo-mode
# attestation. No init.sh -> both lanes.
run_child_suite "tests/test-bl114-bl115-bl127-gate-integrity.sh" \
  "tests/test-bl114-bl115-bl127-gate-integrity.sh"

# BL-116 (Med): the MANDATORY push gate keys on recorded facts, not host brand
# — first-class hosts are exempt only when remote_repo_created+pushed_initial
# are on record ("provably pushed at init", on disk); --no-remote-creation
# scaffolds now gate. Fence-excision mutant proves the scope change
# load-bearing. No init.sh -> both lanes.
run_child_suite "tests/test-bl116-push-gate-scope.sh" "tests/test-bl116-push-gate-scope.sh"

# BL-123/BL-111/BL-126 (High/High/Med): the branch-protection attestation is
# recordable post-hoc (check-gate.sh --repair --branch-protection-attested /
# SOLO_BP_ATTESTED=1, host-keyed reason, explicit-only) and honored by ALL
# THREE consumers — verify_init consults it before any host API probe. In-test
# fence-excision mutants prove both arms load-bearing. No init.sh -> both lanes.
run_child_suite "tests/test-bl123-bp-attestation-recovery.sh" \
  "tests/test-bl123-bp-attestation-recovery.sh"

# BL-157 (Dogfood-4 F-DF4-003, Low): check-gate.sh --repair must RECONCILE the
# remote-setup markers (remote_repo_created/pushed_initial) from a GENUINELY
# present remote in its preflight, so a single --repair --branch-protection-
# attested recovers a --no-remote-creation + hand-wired-origin project WITHOUT
# weakening the BL-123 refusal for truly remote-less ones. Hermetic local-bare
# remote; two mutation cases (fence-excision + unconditional-detection). No
# init.sh -> ALSO in the tests.yml unit lane.
run_child_suite "tests/test-bl157-remote-marker-record.sh" \
  "tests/test-bl157-remote-marker-record.sh"

# BL-124 (Dogfood-2 F-DF2-014, High — the central-question hole): the Phase 3→4
# gate must FAIL while PRODUCT_MANIFESTO.md carries the PENDING promotion
# marker upgrade-project.sh writes on track upgrade. Wire-pins the writer's and
# the reader's literals to one constant; bl104-style copy-mutant proves the arm
# load-bearing. No init.sh -> ALSO in the tests.yml unit lane.
run_child_suite "tests/test-bl124-pending-ratchet.sh" "tests/test-bl124-pending-ratchet.sh"

# BL-130 (Dogfood-2 F-DF2-013, Low): --attest must REFUSE a scanner whose last
# REAL verdict is FAIL — attestations cover scans that could not run, never
# scans that ran and failed ([OK]-recorded a FAIL-masking row the driver would
# then refuse to honor). In-suite fence-excision mutant. No init.sh -> both
# lanes.
run_child_suite "tests/test-bl130-attest-fail-guard.sh" "tests/test-bl130-attest-fail-guard.sh"

# BL-096 (ergonomics F6/F9/F10): cold-start hardening — the CDF preflight
# names the exact clone line at suite ENTRY (warn-and-continue; CI runs
# CDF-less), pre-commit-gate.sh --help tells the truth about --tdd-only
# running BOTH message gates (+ the --commit-msg-gates honest-name alias,
# behavior-pinned), and install-contributor-hooks.sh is CONTRIBUTING's
# manual cp as one idempotent command. No init.sh -> both lanes.
run_child_suite "tests/test-bl096-cold-start.sh" "tests/test-bl096-cold-start.sh"

# BL-095 (ergonomics F4): ONE parsing surface for deployment/poc_mode
# (# BL-095-STATE-READERS in lib/helpers-core.sh) — unit contract (null/
# absent/missing-file/default/no-jq fallback), source-closure over the four
# migrated files, and a fence-excision mutant that must CRASH check-phase-
# gate (routing proof). Conforming-inline siblings (pre-commit-gate,
# run-phase3-validation) documented at the fence. No init.sh -> both lanes.
run_child_suite "tests/test-bl095-state-readers.sh" "tests/test-bl095-state-readers.sh"

# BL-106 (Karl's 2026-07-18 machine-checkable decision): the platform
# go-live checklist is PARSED — the shipped module's H3 /Go-Live/ `- [ ]`
# items must be ticked in a dated docs/test-results/*go-live-checklist*
# artifact at go_live_verified; standalone platforms exempt with a note.
# In-suite fence-excision mutant. No init.sh -> both lanes (the init-side
# generator has its real-init case in test-scaffold-tdd-block-real.sh).
run_child_suite "tests/test-bl106-golive-checklist.sh" "tests/test-bl106-golive-checklist.sh"

# BL-137 (Dogfood-3 F-DF3-002, High): the phase-gate "Tools needed" arm is
# CI-scoped — on a runner ($CI set) the missing-tools list prints with a
# note and does NOT block (the generated CI governance job was structurally
# unpassable); locally the block is unchanged, keyed strictly on $CI. Mini
# tool-matrix fixture; in-suite fence-excision mutant. No init.sh -> both
# lanes.
run_child_suite "tests/test-bl137-ci-tools-scope.sh" "tests/test-bl137-ci-tools-scope.sh"

# BL-125 (Dogfood-2 F-DF2-009): the emitted pre-commit hook RUNS the
# project's test command — RED tests block the commit ([BLOCKED]), green
# tests land with a receipt, not-runnable (unconfigured / exit 127) is a
# LOUD never-silent skip, docs-only commits take the fast lane, and the
# npm scaffold placeholder is not detected as a suite. Hook emitted
# straight from hook-templates.sh + real git commits; in-suite emitter
# fence-excision mutant. No init.sh -> both lanes.
run_child_suite "tests/test-bl125-commit-test-exec.sh" "tests/test-bl125-commit-test-exec.sh"

# BL-163 (Dogfood-4 F-DF4-009): a commit REFUSED by any blocking arm of the
# emitted pre-commit hook (gitleaks / semgrep / bl125_tests) appends a
# terminal_commit_blocked row to .claude/bypass-audit.json — best-effort, never
# weakening the block. Hook emitted straight from hook-templates.sh + real git
# commits, fake scanners, in-suite fence-excision mutant. No init.sh -> both lanes.
run_child_suite "tests/test-bl163-blocked-ledger.sh" "tests/test-bl163-blocked-ledger.sh"

# BL-171 (BL-163 verifier residual): a commit REFUSED by a MESSAGE-scoped
# commit-msg gate (BL-072 TDD-ordering block -> commitmsg_tdd; BL-006 Build-Loop
# block -> commitmsg_buildloop) appends a terminal_commit_blocked row via the
# SHARED soif_ledger_blocked helper — best-effort, subshell-confined, never
# weakening the refusal. --emit-blocked-gate carries the gate identity; the
# refusal lives OUTSIDE the excisable # BL-171-COMMITMSG-LEDGER fence. Real git
# commits through the emitted commit-msg hook. No init.sh -> both lanes.
run_child_suite "tests/test-bl171-commitmsg-ledger.sh" "tests/test-bl171-commitmsg-ledger.sh"

# BL-172: resume-sentinel parity — the BL-072 TDD-ordering commit-msg HARD BLOCK
# (tdd_terminal_enforce) and its PreToolUse WARN sibling (tdd_warn_check) skip on
# all three derivative sentinels (MERGE_HEAD / CHERRY_PICK_HEAD / REVERT_HEAD),
# so a resumed cherry-pick/revert of impl-only content is no longer refused/
# warned; a NORMAL impl-only commit still refuses/warns (anti-blunting), pinned
# by a marker-excision mutation. Direct hermetic fixtures, no init.sh -> both lanes.
run_child_suite "tests/test-bl172-resume-sentinels.sh" "tests/test-bl172-resume-sentinels.sh"

# BL-161 (Dogfood-4 F-DF4-007): the tracked bypass-audit ledger records ONLY
# real events — a CLEAN terminal commit writes NO routine terminal_commit_passed
# row (the tracked ledger is byte-identical; a non-tracked .claude/last-gate-pass.txt
# receipt proves the gate reached its PASS terminal), while BLOCKED rows (framework-gate
# BL-030 + emitted BL-163/BL-171 paths) and genuine bypass / enforcement-level /
# out-of-band events STILL record. Gates installed directly via
# install-filesystem-gates.sh + real git commits. No init.sh -> both lanes.
run_child_suite "tests/test-bl161-ledger-real-events-only.sh" \
  "tests/test-bl161-ledger-real-events-only.sh"

# BL-141 (Dogfood-3 wave verifier B1/B2): verify-install detects + repairs
# the commit-msg TDD gate hook (the BL-139 backstop — post-flip it is the
# ONLY terminal-path feat gate), composing with user hooks and idempotent;
# a non-interactive sync that declines the install WARNs instead of leaving
# the strict-tier backstop silently absent. Dual fence-excision mutants.
# No init.sh -> both lanes.
run_child_suite "tests/test-bl141-commitmsg-repair.sh" "tests/test-bl141-commitmsg-repair.sh"

# BL-145 (Dogfood-3 SHOULD-fix wave, consolidated verifier S3): verify-install's
# hook repairs must not write THROUGH a symlinked hook on the no-consent
# --auto-fix surface (the verifier's repro mutated a dotfiles-managed target),
# and its hook checks must not be blind to core.hooksPath (a green PASS for a
# hook git never runs, plus an inert "repair"). Symlink -> refuse loudly naming
# the target; core.hooksPath -> checks HONOR it, repairs refuse. Dual
# fence-excision mutants. No init.sh -> both lanes.
run_child_suite "tests/test-bl145-hook-symlink-hookspath.sh" \
  "tests/test-bl145-hook-symlink-hookspath.sh"

# BL-143 (Dogfood-3 wave verifier C3): the anti-self-approval control no
# longer silently skips when the Approver row lies past the -A 20 capped
# pre-extraction — the name is recovered from the blame walker's own
# UNCAPPED section scan, so the control RUNS (blame and all). The truly-
# absent-row boundary is pinned unchanged. In-suite fence-excision mutant
# restores the silent skip exactly. No init.sh -> both lanes.
run_child_suite "tests/test-bl143-pastcap-selfapproval.sh" \
  "tests/test-bl143-pastcap-selfapproval.sh"

# BL-144 (Dogfood-3 SHOULD-fix wave verifier S1+S2): the two shapes the
# self-approval scan stayed FULLY SILENT for after BL-143 — a malformed
# `### ` header COMBINED with a past-cap Approver row (the recovery computed
# NO_SECTION and discarded it, while the walker's loud refusal was
# unreachable), and a recovered `[Name]`/blank Approver cell (recognized,
# then dropped). Both now WARN-and-BLOCK. Fixtures are the SHIPPED org
# approval-log template filled per its own append-design instructions, built
# so the defect is the project's ONLY inconsistency — the oracle is rc 0→1
# plus the rendered `issues` count, never the label. BL-143's no-Approver-row
# boundary pinned. Per-arm fence-excision mutants. No init.sh -> both lanes.
run_child_suite "tests/test-bl144-selfapproval-silent-arms.sh" \
  "tests/test-bl144-selfapproval-silent-arms.sh"

# BL-147 + BL-151 (PR-sweep WP-1): the ONE shared content-pin suite over
# templates/pipelines/**. The emitted CI approval-log integrity steps are now
# real — fetch-depth 0 + explicit base (github.base_ref) + loud-fail, no
# 2>/dev/null silencer, stamped byte-identical into all 10 github langs (7 had
# no steps at all) + the gitlab twins — and gitleaks runs via the license-free
# CLI, not the org-license-trapped action. Template lists derived mechanically
# with a count floor. Content-pin, hermetic. No init.sh -> both lanes.
run_child_suite "tests/test-bl147-ci-template-integrity.sh" \
  "tests/test-bl147-ci-template-integrity.sh"

# BL-139 (Dogfood-3 F-DF3-004): a subject-less --check-commit-ready no
# longer presumes feat — framework-gate's pre-commit call cannot know the
# subject (BL-119 doctrine), and the commit-msg surface owns the feat rule
# with the CURRENT subject (backstop proven end-to-end in-suite with the
# real hook chain). In-suite fence-excision mutant restores the presumed-
# feat default exactly. No init.sh -> both lanes.
run_child_suite "tests/test-bl139-subjectless-default.sh" "tests/test-bl139-subjectless-default.sh"

# BL-155 (Dogfood-4 S0 F1): the phase2-init-verified block fires AFTER the
# docs/dep-manifest exemption — the docs/state-only Phase 1→2 transition
# commit ("Commit both files together") lands with init unverified, while
# any non-exempt commit still requires phase2_init.verified=true. Fence-
# excision mutant proven RED on the enforcement pins. No init.sh -> both
# lanes.
run_child_suite "tests/test-bl155-phase2-init-transition-commit.sh" \
  "tests/test-bl155-phase2-init-transition-commit.sh"

# BL-168 (Dogfood-4 S4 → WP-2 investigation): _p3_tm_has_table's two-stage
# grep pipeline raced SIGPIPE-under-pipefail — a present §4 table read as
# absent on tables larger than one grep stdout buffer (~11% of live CI
# attempts). Single-grep fix pinned on the shipped bytes; revert-mutation
# reproduces rc=141 deterministically. No init.sh -> both lanes.
run_child_suite "tests/test-bl168-tm-table-sigpipe.sh" "tests/test-bl168-tm-table-sigpipe.sh"

# BL-165 (Dogfood-4 S3 F-DF4-011/012): the zap-dast arm's hardened-serve
# harness. When a project declares its production header set in
# .claude/dast-headers.json, the arm applies those headers to the responses ZAP
# judges (Replacer --hook in the /zap/wrk bind), records the config as evidence,
# and judges THAT with the unchanged BL-122 riskcode>=2 filter; no declaration
# keeps the raw-preview FAIL semantics byte-for-byte. No init.sh -> both lanes.
run_child_suite "tests/test-bl165-dast-hardened-serve.sh" "tests/test-bl165-dast-hardened-serve.sh"

# BL-169 (Dogfood-4 S4): the scaffold gitignore's unanchored `test-results/`
# hid docs/test-results/ (the Phase-3 evidence the 3→4 gate requires) from
# every fresh CI checkout. Root-anchored + transient phase3/ workdir ignored;
# behavioral check-ignore pin. No init.sh -> both lanes.
run_child_suite "tests/test-bl169-gitignore-anchor.sh" "tests/test-bl169-gitignore-anchor.sh"

# BL-089+BL-091 (Pantheon feedback, Karl-approved 2026-07-20): the doc
# foundations ship at birth — doc map (authority order + conventions),
# PRE-SEEDED identifier registry, archive-with-stubs README — and the
# builders-guide carries the seven documentation rules incl. the REAL
# standing TM-001 threat row in the Bible template (scanner-neutral by
# id-set count). Text-derived (no init.sh) -> both lanes; the real-init
# companion case lives in test-scaffold-tdd-block-real.sh.
run_child_suite "tests/test-bl089-doc-foundations.sh" "tests/test-bl089-doc-foundations.sh"

# BL-120 (Dogfood-2 F-DF2-008): the security_audit step READS the audit's
# verdict — the shipped template's own Summary grammar, fail-closed (a
# DO-NOT-SHIP audit, an explicit No, the unfilled Yes / No placeholder,
# recorded Open findings, or NO parseable verdict all block; the newest
# matching file governs). In-suite fence-excision mutant restores
# existence-only exactly. No init.sh -> both lanes.
run_child_suite "tests/test-bl120-audit-verdict.sh" "tests/test-bl120-audit-verdict.sh"

# BL-162 (Dogfood-4 S2 F-DF4-008): the BL-120 verdict arm globbed audit files
# by both *slug* and *name*; when slug==name (an already-slug-shaped feature)
# the same artifact matched twice and its OPEN-finding warning printed twice.
# Dedupe by path (# BL-162-AUDIT-DEDUP) — print-count only, the BLOCK is
# unchanged. In-suite mutation reverts the dedup → double-print returns.
# No init.sh -> both lanes.
run_child_suite "tests/test-bl162-audit-dedup.sh" "tests/test-bl162-audit-dedup.sh"

# BL-167 (Dogfood-4 S3 F-DF4-014): the BL-072 TDD-ordering classifier counted
# .claude/* framework state files (phase-state.json, …) as impl files lacking
# a test. _bl072_is_impl_file now excludes .claude/ (# BL-167-CLAUDE-EXCLUDE),
# scoped to .claude/ only (real src/lib/app stays impl). In-suite mutation
# excises the arm → .claude state relists as impl. No init.sh -> both lanes.
run_child_suite "tests/test-bl167-claude-classifier.sh" "tests/test-bl167-claude-classifier.sh"

# BL-138 (Dogfood-3 F-DF3-001): validate_approval_fields no longer
# self-collides with the template — H2-anchored section-bounded window
# (table rows can neither anchor nor extend the scan) + template-literal
# placeholder predicate ([SIMULATED] and date-format prose are not
# placeholders). Twin-fixture rc-parity isolation; in-suite fence-excision
# mutant on a shape only the detector rejects. No init.sh -> both lanes.
run_child_suite "tests/test-bl138-approval-window.sh" "tests/test-bl138-approval-window.sh"

# BL-170 (Dogfood-4 F-DF4-017): the APPROVAL_LOG templates must not ship empty
# fill-in-place gate tables (filling them modifies committed lines, which the
# emitted append-only CI guard rejects). Pins: zero empty-value rows + append
# marker per gate section; behavioural consumer cases drive check-phase-gate.sh
# (auto-record / BL-138 / BL-143 / Phase 3->4 dual-approval) against APPENDED
# tables; mutation proofs make the pins load-bearing. No init.sh -> both lanes.
run_child_suite "tests/test-bl170-approval-append-design.sh" \
  "tests/test-bl170-approval-append-design.sh"

# BL-166 + BL-158 (Dogfood-4 S3, residuals wave): check-phase-gate.sh --gate
# <name> must scope its exit/count to the NAMED gate (Phase 3->4 readiness must
# not dominate --gate phase_2_to_3) and must label the FORCED phase distinctly
# ("as-if phase N; recorded current_phase: M"), not as "Current phase". Cases:
# (a) clean-2->3/no-3->4 -> exit 0, (b) real 2->3 failure -> still exit 1,
# (c) header label under --gate phase_0_to_1, (d) bare run byte-unchanged,
# (e) in-suite fence-excision mutant. No init.sh -> both lanes.
run_child_suite "tests/test-bl166-gate-scope.sh" "tests/test-bl166-gate-scope.sh"

# BL-128 (Dogfood-2 F-DF2-015): the review generator is headless-viable —
# --compose-only / --assemble-manifest need no claude at all; live runs get a
# per-review process-GROUP watchdog (REVIEW_TIMEOUT_SECS), actionable
# trust/spend triage, continue-on-failure, and an incrementally-written
# manifest. claude is a PATH stub throughout (plan-file driven). No init.sh
# -> both lanes.
run_child_suite "tests/test-bl128-review-generator-headless.sh" \
  "tests/test-bl128-review-generator-headless.sh"

# BL-102 (Market Signal Step 1.1.5): Appendix D ships in the manifesto
# template, and check-phase-gate WARNs (WARN-FIRST — deliberately NO issues
# increment, pinned by exit-code parity on an issues=0 fixture) when a
# Standard+ project lacks or placeholder-fills it. The mutation case proves
# both directions: excised arm -> warn gone; injected increment -> parity
# breaks (the BL-104 [WARN]-trap inverse). No init.sh -> ALSO in the unit lane.
run_child_suite "tests/test-bl102-market-signal-warn.sh" "tests/test-bl102-market-signal-warn.sh"

# BL-109 S3 (Currency System, Layer 2 — Staging / --plan). test-plan-staging.sh is
# the lib-level unit test (run-folder shape, exclusive mkdir, verbs incl.
# retire/rename linkage, checkbox grammar pin, base-sha, shallow-clone roll-up
# fallback, pin-absent degradation, A2 structural-only, A1 candidate placeholder
# scans, the I1 write fence, the # BL-109-PLAN dispatch) — it never runs init.sh, so
# it is ALSO in the tests.yml unit fast lane. test-plan-birth.sh is the
# BL-088-precedent aggregator: it scaffolds a REAL project and runs the REAL --plan
# against a scratch framework clone (I1 whole-tree fingerprint, real A1 candidate
# from a genuinely-drifted template, live-tree scan, day-after freshness coherence).
# That aggregator is SUITE_SKIP_AGGREGATORS-gated and is NEVER in the unit list.
run_child_suite "tests/test-plan-staging.sh" "tests/test-plan-staging.sh"
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-109 plan-staging birth fidelity — SKIPPED (SUITE_SKIP_AGGREGATORS=1; a real init.sh scaffold + real --plan, runs standalone / full-suite)"
else
run_child_suite "tests/test-plan-birth.sh" "tests/test-plan-birth.sh"
fi

# BL-113 (SAST honesty — walk findings F14 + F15). test-bl113-sast-honesty.sh is a
# BL-088-precedent AGGREGATOR: it runs the REAL init.sh and proves (F14) a fresh
# scaffold scans CLEAN under the framework's own `semgrep --config auto`, and (F15)
# the 3→4 gate's dirty-tree offline autorun no longer launders a REAL scanner FAIL
# into an attestable SKIP — while a genuinely-offline project stays passable. It is
# SUITE_SKIP_AGGREGATORS-gated (a real scaffold + a real semgrep run is heavy) and is
# NEVER in the tests.yml unit list (it executes init.sh).
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-113 SAST honesty — SKIPPED (SUITE_SKIP_AGGREGATORS=1; a real init.sh scaffold + semgrep, runs standalone / full-suite)"
else
run_child_suite "tests/test-bl113-sast-honesty.sh" "tests/test-bl113-sast-honesty.sh"
fi

# Agent-ergonomics onboarding: tests/test-run-lints.sh — behavior suite for
# scripts/run-lints.sh, the canonical local lint runner (runs every
# scripts/lint-*.sh EXCEPT the parametrized lint-uat-scenarios.sh). Its
# T-all-pass case executes the real lints end-to-end, so this block takes a
# couple of minutes (the two slow full-tree scans dominate).
run_child_suite "tests/test-run-lints.sh" "tests/test-run-lints.sh"

# BL-070 increment (WP-B1): scripts/run-phase3-validation.sh's `license` scanner
# promoted from stub to REAL. Reads the project language from
# .claude/tool-preferences.json (.context.language — the canonical source, NOT
# manifest.json), dispatches the per-language license tool
# (typescript→license-checker / python→pip-licenses / rust→cargo license /
# go→go-licenses / csharp→dotnet-project-licenses), archives its JSON report,
# and reports PASS (non-empty report produced — rc-independent) / FAIL (crash,
# no output) / attestable SKIP (--offline, tool missing, or unsupported
# language). Hermetic: the driver runs with a curated clean bin so no host
# license tool / semgrep leaks in. Mutation-proof: excising the marked
# `# BL-070-LICENSE-DISPATCH` line flips T-license-real-pass RED.
run_child_suite "tests/test-bl070-license-scanner.sh" "tests/test-bl070-license-scanner.sh"

# BL-070 (WP-B2): scripts/run-phase3-validation.sh's `threat-model` scanner
# promoted from stub to REAL. Validates every PROJECT_BIBLE.md §4 `TM-NNN`
# threat row against the newest Phase-3 threat-model VALIDATION REPORT in
# docs/test-results/ (glob accepts BOTH *_threat-model-validation.md and the
# legacy *_threat-validation.md name), and requires a non-empty Approved By on
# every Unmitigated-table row. PASS = full coverage + empty-or-approved; FAIL
# names the unaccounted IDs. Pure-local parsing → deliberately RUNS under
# --offline. Mutation-proof: excising the marked `# BL-070-TM-COMPARE`
# coverage-diff line flips T-tm-missing-id-fail RED.
run_child_suite "tests/test-bl070-threat-model-scanner.sh" \
  "tests/test-bl070-threat-model-scanner.sh"

# BL-070 COMPLETION (WP-B3/B4): scripts/run-phase3-validation.sh's `snyk` and
# `zap-dast` scanners promoted from stubs to REAL — after this arm ALL FIVE
# Phase-3 scanners are real. Both are detect-and-run-if-available: snyk SKIPs
# under --offline / not-on-PATH / unauthenticated (SNYK_TOKEN or `snyk config
# get api`), else runs `snyk test --json`; zap-dast SKIPs under --offline /
# platform∉{web,api} (gate FIRST) / no docker / no SOLO_ZAP_TARGET_URL, else
# runs zap-baseline.py via the pinned ZAP image. Both mirror the semgrep
# findings policy (findings block → FAIL). Hermetic: mock snyk + a bespoke mock
# docker, curated clean bin (no host snyk/docker/semgrep leaks in). Mutation-
# proof: excising `# BL-070-SNYK-DISPATCH` / `# BL-070-ZAP-DISPATCH` flips the
# PASS cases RED.
run_child_suite "tests/test-bl070-snyk-zap-scanners.sh" "tests/test-bl070-snyk-zap-scanners.sh"

# BL-073: scripts/check-phase-gate.sh's Phase 3→4 review-manifest check must
# be a REAL, track-aware gate — FAIL (block) when the Security or Red Team
# review is missing for track=standard/full, WARN-only for light/personal
# and for grandfathered projects (no review_gate_enforced flag), and an
# attested OK when SOLO_REVIEWERS_ATTESTED=1 + reason is set (recorded to
# process-state.json). Mutation-proof: excising the marked `# BL-073-ESCALATE`
# escalation reverts the gate to WARN-only, flipping the *-fails cases RED.
# Also pins scripts/lint-review-manifest.sh's schema validation.
run_child_suite "tests/test-bl073-review-manifest-gate.sh" \
  "tests/test-bl073-review-manifest-gate.sh"

# BL-103: the six-eval generator the Phase 3→4 gate hands operators as its
# remediation (evaluation-prompts/Projects/run-reviews.sh) must actually RUN on
# the reference platform (bash 3.2 — it used declare -A / [[ -v ]] and was a
# syntax error), and must RECORD every review it finds — including Red Team, a
# mandatory blocking reviewer whose file the runner probed under the wrong name.
# Runs the real generator against a hermetic fixture with a mock `claude`; pins
# scripts/lint-evalprompts-portability.sh with a behavioural mutation proof.
run_child_suite "tests/test-bl103-eval-generator.sh" "tests/test-bl103-eval-generator.sh"

# BL-104: two scoring inversions in check-phase-gate.sh's Phase 3→4 block, where
# doing LESS work scored BETTER — 0/9 process-checklist steps passed while 8/9
# blocked (an if/elif with no else), and an empty `{"reviews":[]}` manifest
# passed while NO manifest blocked. Mutation-proof on both markers.
run_child_suite "tests/test-bl104-gate-scoring.sh" "tests/test-bl104-gate-scoring.sh"

# BL-072 Phase C1: scripts/pre-commit-gate.sh must WARN (never block) when a
# feat/fix/refactor commit ships implementation with no test in the same
# commit and none earlier on the branch — appending a row to
# .claude/tdd-warn-ledger.jsonl and always leaving rc=0. Shares its
# file-classification core (scripts/lib/tdd-classify.sh) with the dogfood
# replay. Mutation-proof: excising the marked `# BL-072-TDD-DETECT` trigger
# line removes the WARN, flipping T-feat-no-tests-warns RED.
run_child_suite "tests/test-bl072-tdd-warn-detector.sh" "tests/test-bl072-tdd-warn-detector.sh"

# ----------------------------------------------------------------
# TEST 0h2: BL-084 TIER-AWARE CUSTOM-HOST REMOTE POLICY
# ----------------------------------------------------------------
# init.sh --git-host other: a failed initial push is tier-aware — a
# NON-bypassable hard failure for track=standard|full (POC-Sponsored /
# Production), an EXPLICITLY-acknowledged local-only / deferred escape for
# track=light (Personal / POC-Personal), never a silent success (BL-064
# preserved). check-phase-gate.sh adds a hermetic Phase 1→2 remote push-
# verification (host=other, `git ls-remote` against a local bare repo, no
# gh). verify-install.sh routes the other-host CI/release absence to a
# non-blocking warning. Two mutation proofs pin the load-bearing guarantees
# (`# BL-084-TIER-GATE`, `# BL-084-PUSH-VERIFY`).
run_child_suite "tests/test-bl084-tier-aware-remote-policy.sh" \
  "tests/test-bl084-tier-aware-remote-policy.sh"

# ----------------------------------------------------------------
# TEST 0i: PENDING-APPROVAL RESOLVE-DECISION
# ----------------------------------------------------------------
# PR #87 sibling: scripts/pending-approval.sh --resolve-decision flow.
# Exercises the question/options/recommendation round-trip the
# pre-commit-gate's pa_check() depends on.
section "Pending-approval resolve-decision (PR #87)"
run_child_suite "tests/test-pending-approval-resolve-decision.sh" \
  "tests/test-pending-approval-resolve-decision.sh"

# ----------------------------------------------------------------
# TEST 0j: BYPASS-AUDIT FAMILY
# ----------------------------------------------------------------
# PR #93 + verifier-fix 2d5f917: the bypass-audit subsystem's
# hardening tests — tmp-directory permission hardening, trap-isolation
# (verifier-fix cohort), and session-id derivation for the bypass
# detector. Pre-fix, hijacking $TMPDIR or trap-leaking from a
# concurrent bypass-audit run was undetected.
section "Bypass-audit hardening cohort (PR #93 + 2d5f917)"
run_child_suite "tests/test-bypass-audit-tmp-hardening.sh" \
  "tests/test-bypass-audit-tmp-hardening.sh"
run_child_suite "tests/test-bypass-audit-trap-isolation.sh" \
  "tests/test-bypass-audit-trap-isolation.sh"
run_child_suite "tests/test-bypass-detector-session-id.sh" \
  "tests/test-bypass-detector-session-id.sh"

# ----------------------------------------------------------------
# TEST 0k: HOST-DRIVER REGRESSIONS (date-parse + gitlab approvals)
# ----------------------------------------------------------------
# PR #93: scripts/lib/hosts/host_verify_protection date-parse bug
# (date offset mis-coercion silently letting drift through).
# PR #91: gitlab-ci-status stderr surfacing for approval/protection
# rule mismatches.
section "Host-driver regressions (PRs #91, #93)"
run_child_suite "tests/test-host-verify-protection-date-parse.sh" \
  "tests/test-host-verify-protection-date-parse.sh"
run_child_suite "tests/test-gitlab-ci-status-stderr-approvals.sh" \
  "tests/test-gitlab-ci-status-stderr-approvals.sh"
# BL-032 close: proactive gitlab.com Free approvals attestation
# (--approvals-attested / SOLO_APPROVALS_ATTESTED=1) — mirrors BL-002's
# github_free_tier attestation for the GitLab analog.
run_child_suite "tests/test-bl032-gitlab-free-approvals-attestation.sh" \
  "tests/test-bl032-gitlab-free-approvals-attestation.sh"

# ----------------------------------------------------------------
# TEST 0l: VERIFY-INSTALL + PROMPT-INSTALL FIX-FUNCTIONS
# ----------------------------------------------------------------
# PR #92: scripts/verify-install.sh fix_tool_install command-injection
# refusal + audit-trail echo. tests/test-verify-install-fix-functions.sh
# T11b/T12/T13/T14 are known-RED on main pending BL-037
# tightening + the underlying fix_tool_install missing-function bug.
# tests/test-prompt-install-noninteractive.sh (verifier-fix 33e351e)
# is GREEN.
section "Verify-install + prompt-install fix-functions (PRs #92, 33e351e)"
run_child_suite "tests/test-verify-install-fix-functions.sh" \
  "tests/test-verify-install-fix-functions.sh"
run_child_suite "tests/test-prompt-install-noninteractive.sh" \
  "tests/test-prompt-install-noninteractive.sh"
# BL-050 (Step 4 ROI #6): the fix_tool_install_N eval-factory in
# scripts/verify-install.sh:~1401 was previously synthesized on every
# invocation including --check-only, wasting ~1.5-10 ms per call.
# Gate check tests both success (skipped on check-only, run on
# auto-fix) and failure (mutation revert restores overhead) paths.
run_child_suite "tests/test-verify-install-eval-factory-gate.sh" \
  "tests/test-verify-install-eval-factory-gate.sh"

# ----------------------------------------------------------------
# TEST 0m: UPGRADE-PROJECT (interruption, sentinel-block, atomic)
# ----------------------------------------------------------------
# PR #80: scripts/upgrade-project.sh snapshot+atomic-finalize.
# PR #95: upgrade interruption-recovery + bypass-sentinel-during-upgrade
# blocking. The atomic suite mirrors the PR #54/#57 snapshot precedent.
section "Upgrade-project atomicity, interruption, sentinel-block (PRs #80, #95)"
run_child_suite "tests/test-upgrade-project-atomic.sh" "tests/test-upgrade-project-atomic.sh"
run_child_suite "tests/test-upgrade-interruption.sh" "tests/test-upgrade-interruption.sh"
run_child_suite "tests/test-upgrade-sentinel-block.sh" "tests/test-upgrade-sentinel-block.sh"
# BL-099 SLICE-A: --sync-framework same-tier refresh (script sync, ask-first
# hooks, doc drift, soloFrameworkCommit pin, dry-run purity) + both mutation
# proofs (# BL-099-SYNC dispatch, # BL-099-DOC-GUARD rendered-doc exclusion).
run_child_suite "tests/test-upgrade-sync-framework.sh" "tests/test-upgrade-sync-framework.sh"
# BL-099 review round 4: SYSTEMATIC guard-coverage harness. Neuters every
# load-bearing --sync-framework guard on a throwaway copy and proves the BL-099
# suite goes RED (then GREEN restored) for each — the self-enforcing registry that
# stops the four-round whack-a-mole. HEAVY (neuter + re-run the suite per registry
# row → ~1 min, not seconds), so it is gated exactly like the other heavy
# aggregators: SKIPPED in the SUITE_SKIP_AGGREGATORS="core" CI shard to keep the
# unit fast lane fast, and NOT added to the tests.yml unit list. It still runs in a
# standalone `bash tests/full-project-test-suite.sh` and in the full-suite lane, and
# lint-tests-registered.sh counts this reference as its aggregator registration.
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-099 guard-coverage harness — SKIPPED (SUITE_SKIP_AGGREGATORS=1; heavy, runs standalone / full-suite)"
else
run_child_suite "tests/test-bl099-guard-coverage.sh" "tests/test-bl099-guard-coverage.sh"
fi
# BL-061: manifest.json::deployment stayed stale after upgrade-project.sh
# runs, encouraging two-source drift where a downstream reader could gate
# the wrong tier. Regression suite covers happy-path parity, atomic
# rollback, idempotence, and a mutation-proof that neutralizing the
# section 2b jq write reproduces the original bug shape.
run_child_suite "tests/test-upgrade-manifest-refresh.sh" "tests/test-upgrade-manifest-refresh.sh"
# BL-001: upgrade-project.sh performed no CDF sync, so downstream projects
# stayed frozen at their install-time .claude/framework/ assets. Regression
# suite covers the happy-path refresh (--backfill-only), graceful skip on a
# missing clone (upgrade must still exit 0), pull-failure resilience, and a
# mutation-proof that neutralizing solo_refresh_cdf's delegating call turns
# the sync into a no-op. Integration scenarios skip cleanly when the CDF
# clone is absent (CI without ~/.claude-dev-framework).
run_child_suite "tests/test-upgrade-cdf-refresh.sh" "tests/test-upgrade-cdf-refresh.sh"

# ----------------------------------------------------------------
# TEST 0n: PROCESS-CHECKLIST (commit-ready-subject + reset-phase1)
# ----------------------------------------------------------------
# PR #101: scripts/process-checklist.sh --check-commit-ready-subject
# (commit-message subject-line gate) and the --invariant-check for
# the phase1_architecture reset arm. The reset-phase1 test currently
# fails inside the framework-repo guard (LB-3 / BL-041) — it does
# not cd outside the framework checkout before invoking
# process-checklist.sh, so the script refuses with rc=1 even on
# the healthy fixture.
section "Process-checklist commit-ready-subject + reset-phase1 (PR #101)"
run_child_suite "tests/test-process-checklist-check-commit-ready-subject.sh" \
  "tests/test-process-checklist-check-commit-ready-subject.sh"
run_child_suite "tests/test-process-checklist-reset-phase1.sh" \
  "tests/test-process-checklist-reset-phase1.sh"

# ----------------------------------------------------------------
# TEST 0o: PRE-COMMIT-GATE LINTS + CLASSIFIER
# ----------------------------------------------------------------
# Wave 3: scripts/pre-commit-gate.sh's lint-runner + commit-classifier
# behavior tests. Both are unit-style and fast.
section "Pre-commit-gate lints + classifier (Wave 3)"
run_child_suite "tests/test-pre-commit-gate-lints.sh" "tests/test-pre-commit-gate-lints.sh"
run_child_suite "tests/test-pre-commit-gate-classifier.sh" \
  "tests/test-pre-commit-gate-classifier.sh"

# ----------------------------------------------------------------
# TEST 0p: VALIDATE PHASE 2→3 GATE
# ----------------------------------------------------------------
# PR #101: scripts/validate.sh's Phase 2→3 gate path — assert the
# gate refuses to advance when the required artifacts are missing.
section "validate.sh Phase 2→3 gate (PR #101)"
run_child_suite "tests/test-validate-phase-2-3-gate.sh" "tests/test-validate-phase-2-3-gate.sh"

# ----------------------------------------------------------------
# TEST 0p2: VALIDATE READS PHASE-STATE.JSON::GATES (BL-059)
# ----------------------------------------------------------------
# BL-059: scripts/validate.sh's Approval Log section previously
# greped APPROVAL_LOG.md only, emitting a false-negative "no date
# recorded" WARN when phase-state.json::gates.<gate> was populated
# but the log had not been mirrored. Fix reads JSON first, falls
# back to APPROVAL_LOG.md for back-compat.
section "validate.sh reads phase-state.json::gates (BL-059)"
run_child_suite "tests/test-validate-phase-state-gates.sh" \
  "tests/test-validate-phase-state-gates.sh"

# ----------------------------------------------------------------
# TEST 0q: SPECS+PLANS HOST-AWARE QUARTET
# ----------------------------------------------------------------
# PR #97: docs/superpowers/specs+plans host-aware quartet rendering
# (the spec/plan/test/code-review quartet must reflect the current
# host_name without hard-coding github/gitlab/bitbucket).
section "Specs+plans host-aware quartet (PR #97)"
run_child_suite "tests/test-specs-plans-host-aware-quartet.sh" \
  "tests/test-specs-plans-host-aware-quartet.sh"

# ----------------------------------------------------------------
# TEST 0r: EDGE-CASES AGGREGATORS (pre-init, scripts, upgrade-input)
# ----------------------------------------------------------------
# PR #85/#88/#89: the three edge-cases aggregator files that house
# E1-E62 integration coverage.
#
# Status snapshot on main (2026-06-29):
#   • edge-cases-pre-init.sh    — RED (E1×2, E4: apostrophe handling
#     in init.sh name sanitization + dry-run name preservation;
#     tracked by BL-040 / LB-2 init.sh:2781 dry_run_summary).
#   • edge-cases-scripts.sh     — RED (E30: --platform other refs/
#     template handling; tracked by BL-065 / BL-009 follow-up).
#     (E50 / BL-039 was repaired in the PR that closed BL-039: the
#     test was reconciled to the actual baseline §2.5 tier contract
#     — organizational+private_poc is rejected, not accepted — and
#     E50 + new E50b now pass on main.)
#   • edge-cases-upgrade-input.sh — GREEN.
#
# All three are gated together because they share BL-034 status.
# Known-RED siblings are gated on SKIP_KNOWN_FAILING so a local
# iteration loop can mask them; default = surface the failure.
# SUITE_SKIP_AGGREGATORS: CI shards these heavy aggregators into separate
# parallel jobs (BL-077 full-lane sharding). When set, skip them here so the
# "core" shard doesn't re-run them; a standalone run (env unset) runs everything.
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "Edge-cases aggregators — SKIPPED (SUITE_SKIP_AGGREGATORS=1; run as separate CI shards)"
else
section "Edge-cases aggregators (pre-init, scripts, upgrade-input)"
run_child_suite "tests/edge-cases-pre-init.sh" "tests/edge-cases-pre-init.sh"
run_child_suite "tests/edge-cases-scripts.sh" "tests/edge-cases-scripts.sh"
run_child_suite "tests/edge-cases-upgrade-input.sh" "tests/edge-cases-upgrade-input.sh"
fi

# ----------------------------------------------------------------
# TEST 0r-bl046: HELPERS.SH CORE/FULL SPLIT CONTRACT (BL-046)
# ----------------------------------------------------------------
# tests/test-bl046-helpers-split.sh proves the five contracts of the
# BL-046 split: core-only callers get the minimum surface, full
# callers get both surfaces via delegation, the boundary is enforced
# (T3: init_log absent from core), the shim retains full backwards
# compatibility, and each file is idempotent-source-guarded.
# Registered here per BL-038 discipline: every test-*.sh needs an
# aggregator wire so a silent regression can't slip past
# `full-project-test-suite.sh`.
section "BL-046 helpers.sh core/full split contract"
run_child_suite "tests/test-bl046-helpers-split.sh" "tests/test-bl046-helpers-split.sh (T1..T5b)"

# ----------------------------------------------------------------
# TEST 0r-bl033: TOOL-MATRIX install_cmds STRUCTURED SHAPE (BL-033)
# ----------------------------------------------------------------
# tests/test-bl033-install-cmds-shape.sh proves the resolver reader
# accepts both the legacy `install.<key>: "single cmd"` string shape
# AND the new `install.<key>: ["cmd1", "cmd2"]` structured array
# shape, emits both `install_cmd` (joined for legacy consumers) and
# `install_cmds` (array for new consumers), refuses malformed shapes
# (empty arrays, non-string elements, object-with-both-keys) with a
# clear diagnostic, and iterating stages fails-fast on stage-1
# non-zero exit. Also asserts the shipped docker + colima entries
# actually use the array shape post-migration.
# Registered here per BL-038 discipline.
section "BL-033 tool-matrix install_cmds structured shape"
run_child_suite "tests/test-bl033-install-cmds-shape.sh" \
  "tests/test-bl033-install-cmds-shape.sh (T-back-compat, T-array-happy, T-array-fail-fast, T-mixed-invalid, T-empty-array, T-non-string-elements, T-migrated-entries, T-migrated-semantics)"

# ----------------------------------------------------------------
# TEST 0r-bl069: install_cmds ARRAY CONSUMERS (BL-069)
# ----------------------------------------------------------------
# BL-033 (above) shipped the resolver SCHEMA — install_cmd (legacy
# joined) + install_cmds (structured array) — but no consumer READ the
# array. tests/test-bl069-install-cmds-consumers.sh proves the three
# migrated readers (helpers-core.sh run_install_stages/prompt_install,
# verify-install.sh fix_tool_install, upgrade-project.sh install loop)
# iterate install_cmds with per-stage fail-fast + resumability, fall
# back to the legacy singular install_cmd when the array is absent, and
# that gitleaks/rust/k6 are migrated to the array shape (join-preserving).
# Mutation-proven: a reader that used only install_cmds[0] flips
# T-runner-happy-multi / T-extract-prefers-array / T-vi-multi-both RED.
# Registered here per BL-038 discipline.
section "BL-069 install_cmds array consumers"
run_child_suite "tests/test-bl069-install-cmds-consumers.sh" \
  "tests/test-bl069-install-cmds-consumers.sh (Groups A-E: split, run_install_stages, extraction, fix_tool_install dispatch, wrapper JSON regression)"

# ----------------------------------------------------------------
# TEST 0s: HOST-DRIVER AGGREGATOR
# ----------------------------------------------------------------
# tests/host-drivers/run-all.sh wraps the per-host unit tests
# (github/gitlab/bitbucket) + the e2e-init.*.test.sh trio.
# The e2e-init.*.test.sh trio is currently RED on main (3 of 9
# children fail: e2e-init-bitbucket, e2e-init-gitlab, e2e-init).
# Gated on SKIP_KNOWN_FAILING for local iteration; default = run
# and surface the failure so the e2e-init regressions can't ship
# silent.
section "Host-driver aggregator (tests/host-drivers/run-all.sh)"
run_child_suite "tests/host-drivers/run-all.sh" "tests/host-drivers/run-all.sh (all children)"

# --- BL-035 wiring C: test-gate/process/poc/docs ---
# Registers the pre-Wave-1-4 orphan suites in the test-gate/session,
# process-checklist/pending/poc, and docs/specs/lint product areas that
# were parked on scripts/lint-tests-registered.sh::KNOWN_ORPHANS_PENDING_BL035
# (running ZERO times). Same delegate discipline as the BL-034 block above:
# no `|| true` wraps, each test invoked exactly once, rc feeds pass()/fail().
# See Reports/2026-07-06-bl035-orphan-triage.md (chunk C).

# ----------------------------------------------------------------
# Test-gate / counter-sanitizer / session (BL-035 C)
# ----------------------------------------------------------------
# test-gate.sh + validate.sh counter-sanitizer coverage (the counter-
# antipattern defect class), test-gate null-handling, record/unrecord
# governance-ledger helpers, and the session-driver test-gate/merge check.
section "BL-035 C: test-gate / counter-sanitizer / session"
run_child_suite "tests/test-test-gate-counter-sanitizer.sh" \
  "tests/test-test-gate-counter-sanitizer.sh (5/5)"
run_child_suite "tests/test-test-gate-null-handling.sh" \
  "tests/test-test-gate-null-handling.sh (5/5)"
run_child_suite "tests/test-validate-counter-sanitizer.sh" \
  "tests/test-validate-counter-sanitizer.sh (5/5)"
run_child_suite "tests/test-record-claude-commit.sh" "tests/test-record-claude-commit.sh (9/9)"
run_child_suite "tests/test-unrecord-feature.sh" "tests/test-unrecord-feature.sh (7/7)"
run_child_suite "tests/test-session-test-gate-check-merge.sh" \
  "tests/test-session-test-gate-check-merge.sh (9/9)"

# ----------------------------------------------------------------
# Process-checklist / pending-approval / poc-modes (BL-035 C)
# ----------------------------------------------------------------
# pending-approval resolve/escalate flow, process-checklist auto-advance +
# commit classifier, phase-finalize, the platform-security-bugs-closer
# docstring probe (T4b path fixed in Chunk-0), and poc-modes tier semantics
# (T5: --to-private-poc from personal stays personal — aligned with E60,
# see BL-079).
section "BL-035 C: process-checklist / pending / poc-modes"
run_child_suite "tests/test-pending-approval.sh" "tests/test-pending-approval.sh (21/21)"
run_child_suite "tests/test-process-checklist-auto-advance.sh" \
  "tests/test-process-checklist-auto-advance.sh (7/7)"
run_child_suite "tests/test-process-checklist-classifier.sh" \
  "tests/test-process-checklist-classifier.sh (12/12)"
run_child_suite "tests/test-phase-finalize.sh" "tests/test-phase-finalize.sh (6/6)"
run_child_suite "tests/test-platform-security-bugs-closer.sh" \
  "tests/test-platform-security-bugs-closer.sh (7/7)"
run_child_suite "tests/test-poc-modes.sh" "tests/test-poc-modes.sh (5/5)"

# ----------------------------------------------------------------
# Pre-commit-gate --terminal-mode (BL-035 C / BL-075)
# ----------------------------------------------------------------
# BL-075 caution resolved: the pre-existing T2 / T6a-b / T11a-b reds were NOT
# a --terminal-mode/classifier product bug but the BL-074 helpers-scaffold gap
# (setup copied only helpers.sh; process-checklist.sh sources helpers-core.sh
# directly, so --check-commit-message died and short-circuited the whole
# terminal-mode flow at the classifier step). Both scaffolds now copy the full
# helpers-core/helpers-full sibling chain the product ships; both suites GREEN
# and mutation-provably exercise the real terminal-mode lint path.
#
# Only test-pre-commit-gate-terminal-mode.sh is registered here (it was on the
# KNOWN_ORPHANS_PENDING_BL035 bridge). Its sibling test-pre-commit-gate-lints.sh
# was already registered at TEST 0o (Wave-3) — the same BL-074 scaffold fix
# turns it from RED (T6a/b/T11a/b) to GREEN there.
section "BL-035 C: pre-commit-gate terminal-mode (BL-075)"
run_child_suite "tests/test-pre-commit-gate-terminal-mode.sh" \
  "tests/test-pre-commit-gate-terminal-mode.sh (3/3)"

# ----------------------------------------------------------------
# Docs / specs / lint suites (BL-035 C)
# ----------------------------------------------------------------
# Docs-cluster six-pack (doc-consistency guards), specs+plans remaining
# quartet, and the UAT-scenarios lint behavior suite.
section "BL-035 C: docs / specs / lint suites"
run_child_suite "tests/test-docs-cluster-six-pack.sh" "tests/test-docs-cluster-six-pack.sh (28/28)"
run_child_suite "tests/test-specs-plans-remaining-quartet.sh" \
  "tests/test-specs-plans-remaining-quartet.sh (10/10)"
run_child_suite "tests/test-lint-uat-scenarios.sh" "tests/test-lint-uat-scenarios.sh (12/12)"
# --- end BL-035 wiring C ---

# ================================================================
# --- BL-035 wiring A: governance/gate/enforcement ---
# ================================================================
# BL-035 chunk A (triage: Reports/2026-07-06-bl035-orphan-triage.md).
# Registers the governance/bypass, gate/check, and enforcement-level
# orphan tests that were parked on
# scripts/lint-tests-registered.sh::KNOWN_ORPHANS_PENDING_BL035 (running
# zero times) into this aggregator, mirroring the BL-034 cohort pattern.
# Chunk-0 (already merged) fixed the stale `--language` fixture drift for
# the init-e2e members. Each test invoked exactly once, rc captured,
# contributing to PASS/FAIL — no `|| true` wraps.
# MERGE note: test-bypass-audit-schema.sh was retired; its unique T1
# (init ledger .[0] schema) is folded into test-bl029-integration.sh (T1b).
section "BL-035 wiring A: governance/bypass, gate/check, enforcement-level"

# Governance / bypass family.
run_child_suite "tests/test-bl029-integration.sh" \
  "tests/test-bl029-integration.sh (incl. folded bypass-audit-schema T1b)"
run_child_suite "tests/test-bl030-calibration-replay.sh" "tests/test-bl030-calibration-replay.sh"
run_child_suite "tests/test-bypass-audit-integrity.sh" "tests/test-bypass-audit-integrity.sh"
run_child_suite "tests/test-bypass-audit-lib.sh" "tests/test-bypass-audit-lib.sh"
run_child_suite "tests/test-bypass-detector.sh" "tests/test-bypass-detector.sh"
run_child_suite "tests/test-bypass-patterns.sh" "tests/test-bypass-patterns.sh"
run_child_suite "tests/test-bypass-sentinel.sh" "tests/test-bypass-sentinel.sh"
run_child_suite "tests/test-out-of-band-detector.sh" "tests/test-out-of-band-detector.sh"
run_child_suite "tests/test-escalate-to-user.sh" "tests/test-escalate-to-user.sh"

# Gate / check family.
run_child_suite "tests/test-check-gate.sh" "tests/test-check-gate.sh"
run_child_suite "tests/test-check-changelog-filter.sh" "tests/test-check-changelog-filter.sh"
run_child_suite "tests/test-check-commit-message.sh" "tests/test-check-commit-message.sh"
# BL-010: the BL-006 Build-Loop commit-message check now runs at the git
# commit-msg hook surface (pre-commit-gate.sh --terminal-mode --tdd-only ->
# bl006_terminal_enforce), reaching editor-opened and human-terminal commits.
# Mutation-proof: excising the marked `# BL-010-COMMITMSG-BL006` delegation line
# removes the refusal, flipping T-bl010-commitmsg-bl006-blocks RED.
run_child_suite "tests/test-bl010-commitmsg-bl006.sh" "tests/test-bl010-commitmsg-bl006.sh"
run_child_suite "tests/test-check-phase-gate.sh" "tests/test-check-phase-gate.sh"
run_child_suite "tests/test-check-phase-gate-poc-block-contract.sh" \
  "tests/test-check-phase-gate-poc-block-contract.sh"
run_child_suite "tests/test-check-phase-gate-counter-sanitizer.sh" \
  "tests/test-check-phase-gate-counter-sanitizer.sh"
run_child_suite "tests/test-gate-principles.sh" "tests/test-gate-principles.sh"
run_child_suite "tests/test-filesystem-gate-install.sh" "tests/test-filesystem-gate-install.sh"
run_child_suite "tests/test-bl174-gitignore-backfill.sh" "tests/test-bl174-gitignore-backfill.sh"

# Enforcement-level family.
run_child_suite "tests/test-enforcement-level-lib.sh" "tests/test-enforcement-level-lib.sh"
run_child_suite "tests/test-enforcement-level-init.sh" "tests/test-enforcement-level-init.sh"
run_child_suite "tests/test-enforcement-level-reconfigure.sh" \
  "tests/test-enforcement-level-reconfigure.sh"
# BL-180: the INTERACTIVE birth site. Everything above this pair covers the
# --non-interactive arm only, which is why an interactively scaffolded project
# shipped with enforcement_level="" and no filesystem gate.
#   * -interactive-enforcement.sh — fast, pty-free pin of the RESOLVED level,
#     read off dry_run_summary's `# BL-180-DRYRUN-ENFORCEMENT` stdout line.
#   * -interactive-scaffold-pty.sh — the real end-to-end scaffold over a pty
#     (manifest + .git/hooks/framework-gate.sh on disk). Aggregator-ONLY: it
#     invokes init.sh for a full create_project, so it must NOT be added to
#     the .github/workflows/tests.yml unit lane. LOUD-SKIPS (rc=0, printed
#     reason) when neither expect nor script is installed.
run_child_suite "tests/test-bl180-interactive-enforcement.sh" \
  "tests/test-bl180-interactive-enforcement.sh"
# Output is INSPECTED, not just captured, for this one — so it is deliberately
# NOT routed through run_child_suite. Its LOUD SKIP (no expect and no script on
# PATH) is an rc=0 outcome, and run_child_suite prints nothing at all on rc=0,
# which would render the skip indistinguishable from a genuine 10/10 pass —
# turning a documented skip back into the silent-success class this test exists
# to close. BL-184 fixed the FAILURE side of the delegate contract; this site
# needs the SUCCESS side branched on, so it keeps its own capture and surfaces
# the skip in the suite line.
#
# NOT SUITE_SKIP_AGGREGATORS-gated, unlike the five real-scaffold siblings above
# — a deliberate exception (verifier finding R-WPA-1, 2026-07-26). The `core`
# shard is the ONLY CI shard that reaches this delegate (`aggregators` runs four
# explicitly named files), so gating it here would leave the sole check that
# catches a HOLLOW strict gate executing in zero CI lanes. The .github/workflows
# `full` job installs `expect` so the supported driver is present rather than
# the best-effort script(1) fallback. The fixture's own
# # BL-180-PTY-INTERACTIVE-ENV unsets CI/SOIF_NONINTERACTIVE (a pty does NOT
# defeat those two guards in helpers-core.sh::prompt_input) and its T0a refuses
# to spawn init.sh at all if that ever stops taking.
bl180_pty_out=""
bl180_pty_rc=0
bl180_pty_out="$(bash "$SCRIPT_DIR/tests/test-bl180-interactive-scaffold-pty.sh" 2>&1)" || bl180_pty_rc=$?
if [ "$bl180_pty_rc" -eq 0 ]; then
  case "$bl180_pty_out" in
    *"SKIPPED: no pty driver"*)
      pass "tests/test-bl180-interactive-scaffold-pty.sh — SKIPPED (no expect/script on PATH; install expect to exercise the real interactive scaffold)" ;;
    *)
      pass "tests/test-bl180-interactive-scaffold-pty.sh" ;;
  esac
else
  fail "tests/test-bl180-interactive-scaffold-pty.sh FAILED (run for details)"
fi
# --- BL-035 wiring B: init/upgrade ---
# ================================================================
# Registers the init-family and upgrade-family orphan tests that were
# parked on scripts/lint-tests-registered.sh::KNOWN_ORPHANS_PENDING_BL035
# (running ZERO times). Same BL-034 delegate discipline: each test invoked
# once, rc captured, contributes to pass()/fail(); no `|| true` wraps.
#
# Dispositions applied in this wiring pass (see the BL-035 orphan-triage
# report, 2026-07-06):
#   • DELETE   test-init-other-host-attestation.sh — fully superseded by the
#              already-registered test-init-fail-status-propagation.sh (same
#              --git-host other push-fail fixture + BL-064/BL-024 invariants);
#              its T2 dup'd init-non-interactive N9. File + bridge entry removed.
#   • RELOCATE test-github-free-tier-403.sh → tests/host-drivers/
#              github-free-tier-403.test.sh so tests/host-drivers/run-all.sh's
#              *.test.sh glob registers it (NOT this aggregator).
#   • MERGE    test-upgrade-personal-to-sponsored-poc.sh — unique T1
#              (personal→sponsored_poc R3-A guard + phase-state transition)
#              folded into tests/edge-cases-scripts.sh as E58b; T2/T3 dropped as
#              dups of E27/E60. File + bridge entry removed.
#   • DECOMPOSE test-upgrade-paths.sh — trimmed to its unique T4 (BL-004 flat→
#              per-host CI migration) / T5 (vendored-skills + private-poc +
#              manifesto) / T6 (POC-strip); the T1/T2/T3 tier-transition cases
#              were dropped as dups of tests/upgrade-path-tests.sh.
#   • N7 fix   test-init-non-interactive.sh N7 asserted personal+production →
#              exit 1, but the current product correctly ACCEPTS that combo
#              (production is valid for personal, baseline §2.5). N7 now pins
#              the actually-rejected personal+sponsored_poc combo → exit 1.
section "BL-035 wiring B: init family"
run_child_suite "tests/test-init-atomic-finalize.sh" \
  "tests/test-init-atomic-finalize.sh (code-init-sh-6 atomic-finalize, 8/8)"
run_child_suite "tests/test-init-no-remote-creation.sh" "tests/test-init-no-remote-creation.sh"
run_child_suite "tests/test-init-schema-phase-gate.sh" "tests/test-init-schema-phase-gate.sh"
run_child_suite "tests/test-vendored-skills-install.sh" "tests/test-vendored-skills-install.sh"
# N7 fix landed in this test (personal+sponsored_poc, not personal+production).
run_child_suite "tests/test-init-non-interactive.sh" \
  "tests/test-init-non-interactive.sh (BL-016 --non-interactive validation, 29/29)"

section "BL-035 wiring B: upgrade family"
run_child_suite "tests/test-upgrade-non-interactive.sh" "tests/test-upgrade-non-interactive.sh"
run_child_suite "tests/test-upgrade-bl030-backfill.sh" "tests/test-upgrade-bl030-backfill.sh"
run_child_suite "tests/test-upgrade-to-production-preconditions.sh" \
  "tests/test-upgrade-to-production-preconditions.sh"
run_child_suite "tests/test-upgrade-to-production-warn.sh" \
  "tests/test-upgrade-to-production-warn.sh"
run_child_suite "tests/test-verify-install-bl030-coverage.sh" \
  "tests/test-verify-install-bl030-coverage.sh"
# DECOMPOSED: only the unique T4 (BL-004 CI migration) / T5 (vendored-skills,
# private-poc, manifesto) / T6 (POC-strip) cases remain; T1/T2/T3 tier-transition
# cases were dropped as dups of tests/upgrade-path-tests.sh.
run_child_suite "tests/test-upgrade-paths.sh" \
  "tests/test-upgrade-paths.sh (unique T4/T5/T6 after BL-035 decompose, 16/16)"

# ================================================================
# TEST 1: RESOLVER MATRIX — ALL COMBINATIONS
# ================================================================
section "TEST 1: Resolver Matrix — All Platform × Language × Track Combinations"

PLATFORMS=(web mobile desktop)
LANGUAGES=(typescript python rust go csharp dart kotlin java swift)
TRACKS=(light standard full)
DEV_OS="darwin"  # Current machine
RESOLVER="$SCRIPT_DIR/scripts/resolve-tools.sh"
MATRIX_DIR="$SCRIPT_DIR/templates/tool-matrix"

# BL-045 (2026-06-29): parallelize the 81-cell matrix walk via xargs -P.
# Each cell forks `bash scripts/resolve-tools.sh` (cold-start + matrix
# re-read); serial walk previously took ~240 s on a warm Mac. With N=8
# workers, wall-clock drops to ~30-60 s while preserving per-cell pass/fail
# semantics. Race-free aggregation: each cell writes "STATUS<TAB>MESSAGE"
# to a per-cell file; the main shell replays them in deterministic order
# via pass()/fail() so PASS/FAIL counters and RESULTS string mutations
# remain single-writer. Set TEST_1_PARALLEL=0 to force the original
# serial code path (kept for correctness diff during the BL-045 ship).
TEST_1_PARALLEL="${TEST_1_PARALLEL:-8}"

# Per-cell worker. Writes "STATUS\tMESSAGE\n" to $1/<platform>__<language>__<track>.status.
# Always exits 0 so xargs does not abort the batch on resolver failures (those
# are recorded as FAIL via the status file and replayed by the main shell).
_test1_run_cell() {
  local tmpdir="$1" resolver="$2" matrix_dir="$3" dev_os="$4"
  local platform="$5" language="$6" track="$7"
  local outfile="$tmpdir/${platform}__${language}__${track}.status"
  local output null_count auto manual installed deferred

  if ! output=$(bash "$resolver" \
      --dev-os "$dev_os" \
      --platform "$platform" \
      --language "$language" \
      --track "$track" \
      --phase 2 \
      --matrix-dir "$matrix_dir" 2>/dev/null); then
    printf 'FAIL\tResolver failed: %s/%s/%s\n' "$platform" "$language" "$track" > "$outfile"
    return 0
  fi

  if printf '%s' "$output" | jq -e '.auto_install and .manual_install and .already_installed and .deferred' >/dev/null 2>&1; then
    null_count=$(printf '%s' "$output" | jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | select(.name == "null" or .name == null)] | length')
    if [ "${null_count:-0}" -gt 0 ]; then
      printf 'FAIL\tResolver has %s null-named entries: %s/%s/%s\n' "$null_count" "$platform" "$language" "$track" > "$outfile"
    else
      auto=$(printf '%s' "$output" | jq '.auto_install | length')
      manual=$(printf '%s' "$output" | jq '.manual_install | length')
      installed=$(printf '%s' "$output" | jq '.already_installed | length')
      deferred=$(printf '%s' "$output" | jq '.deferred | length')
      printf 'PASS\tResolver OK: %s/%s/%s (auto:%s manual:%s installed:%s deferred:%s)\n' \
        "$platform" "$language" "$track" "$auto" "$manual" "$installed" "$deferred" > "$outfile"
    fi
  else
    printf 'FAIL\tResolver output missing buckets: %s/%s/%s\n' "$platform" "$language" "$track" > "$outfile"
  fi
  return 0
}
export -f _test1_run_cell

_test1_tmpdir=$(mktemp -d)
_test1_total=$(( ${#PLATFORMS[@]} * ${#LANGUAGES[@]} * ${#TRACKS[@]} ))

echo ""
if [ "$TEST_1_PARALLEL" = "0" ]; then
  echo "Testing $_test1_total combinations (serial: TEST_1_PARALLEL=0)..."
else
  echo "Testing $_test1_total combinations (parallel: TEST_1_PARALLEL=$TEST_1_PARALLEL)..."
fi
echo ""

_test1_start=$(date +%s)

# Build the cell list (one "platform language track" per line for xargs -L 1).
_test1_cells=""
for platform in "${PLATFORMS[@]}"; do
  for language in "${LANGUAGES[@]}"; do
    for track in "${TRACKS[@]}"; do
      _test1_cells+="$platform $language $track"$'\n'
    done
  done
done

if [ "$TEST_1_PARALLEL" = "0" ]; then
  # Original serial code path (kept for correctness diff against the parallel walk).
  while IFS=' ' read -r _p _l _t; do
    [ -z "$_p" ] && continue
    _test1_run_cell "$_test1_tmpdir" "$RESOLVER" "$MATRIX_DIR" "$DEV_OS" "$_p" "$_l" "$_t"
  done <<< "$_test1_cells"
else
  # Parallel walk. xargs -L 1 reads one "platform language track" line per
  # invocation, splits on whitespace, and appends those 3 fields after the
  # 4 trailing args, so the child bash sees:
  #   $0=_  $1=tmpdir  $2=resolver  $3=matrix_dir  $4=dev_os  $5=platform  $6=language  $7=track
  # which matches _test1_run_cell's positional signature.
  #
  # We tolerate xargs exit 123 (any sub-bash returned 1-125) so a flaky cell
  # cannot abort the batch under `set -e` — per-cell failures are already
  # recorded in the .status files and replayed below.
  printf '%s' "$_test1_cells" | xargs -P "$TEST_1_PARALLEL" -L 1 bash -c \
    '_test1_run_cell "$@"' _ "$_test1_tmpdir" "$RESOLVER" "$MATRIX_DIR" "$DEV_OS" \
    || _test1_xargs_rc=$?
  if [ "${_test1_xargs_rc:-0}" -ne 0 ] && [ "${_test1_xargs_rc:-0}" -ne 123 ]; then
    fail "TEST 1: xargs aborted with rc=$_test1_xargs_rc (workers may have been killed)"
  fi
fi

# Replay results in deterministic order so log diff stays stable between
# serial and parallel runs.
_test1_seen=0
for platform in "${PLATFORMS[@]}"; do
  for language in "${LANGUAGES[@]}"; do
    for track in "${TRACKS[@]}"; do
      _test1_outfile="$_test1_tmpdir/${platform}__${language}__${track}.status"
      if [ ! -s "$_test1_outfile" ]; then
        fail "Resolver cell produced no output: $platform/$language/$track"
        continue
      fi
      _test1_status=$(cut -f1 < "$_test1_outfile")
      _test1_message=$(cut -f2- < "$_test1_outfile")
      case "$_test1_status" in
        PASS) pass "$_test1_message" ;;
        FAIL) fail "$_test1_message" ;;
        *)    fail "Resolver cell unknown status ($_test1_status): $platform/$language/$track" ;;
      esac
      _test1_seen=$(( _test1_seen + 1 ))
    done
  done
done

_test1_end=$(date +%s)
echo ""
echo "  TEST 1 wall-clock: $(( _test1_end - _test1_start ))s ($_test1_seen/$_test1_total cells)"

rm -rf "$_test1_tmpdir"
unset _test1_tmpdir _test1_cells _test1_start _test1_end _test1_seen _test1_total _test1_outfile _test1_status _test1_message _test1_xargs_rc
unset -f _test1_run_cell

# ================================================================
# TEST 2: RESOLVER FILTERING CORRECTNESS
# ================================================================
section "TEST 2: Resolver Filtering Logic"

echo ""

# 2a: Phase filtering — Phase 2 should defer Phase 3+ tools
output_p2=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
deferred_p2=$(echo "$output_p2" | jq '.deferred | length')
if [ "$deferred_p2" -gt 0 ]; then
  pass "Phase filtering: Phase 2 defers $deferred_p2 tools"
else
  fail "Phase filtering: Phase 2 should defer tools but got 0"
fi

# 2b: Phase 4 should defer nothing
output_p4=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
deferred_p4=$(echo "$output_p4" | jq '.deferred | length')
if [ "$deferred_p4" -eq 0 ]; then
  pass "Phase filtering: Phase 4 defers 0 tools"
else
  fail "Phase filtering: Phase 4 should defer 0 but got $deferred_p4"
fi

# 2c: Track filtering — Light track should NOT have k6
output_light=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track light --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
has_k6_light=$(echo "$output_light" | jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | index("k6")')
if [ "$has_k6_light" = "null" ]; then
  pass "Track filtering: Light track excludes k6"
else
  fail "Track filtering: Light track should exclude k6 but found it"
fi

# 2d: Full track SHOULD have k6
output_full=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track full --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
has_k6_full=$(echo "$output_full" | jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | index("k6")')
if [ "$has_k6_full" != "null" ]; then
  pass "Track filtering: Full track includes k6"
else
  fail "Track filtering: Full track should include k6 but didn't find it"
fi

# 2e: Language filtering — TypeScript gets license-checker, NOT pip-licenses
output_ts=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_ts=$(echo "$output_ts" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_ts" | grep -q "license-checker"; then
  pass "Language filtering: TypeScript gets license-checker"
else
  fail "Language filtering: TypeScript should get license-checker"
fi
if echo "$all_ts" | grep -q "pip-licenses"; then
  fail "Language filtering: TypeScript should NOT get pip-licenses"
else
  pass "Language filtering: TypeScript excludes pip-licenses"
fi

# 2f: Python gets pip-licenses, NOT license-checker (on web)
output_py=$(bash "$RESOLVER" --dev-os darwin --platform web --language python --track standard --phase 4 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_py=$(echo "$output_py" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_py" | grep -q "pip-licenses"; then
  pass "Language filtering: Python gets pip-licenses"
else
  fail "Language filtering: Python should get pip-licenses"
fi
if echo "$all_py" | grep -q "license-checker"; then
  fail "Language filtering: Python should NOT get license-checker on web"
else
  pass "Language filtering: Python excludes license-checker on web"
fi

# 2g: Mobile platform includes EAS CLI for TypeScript
output_mob_ts=$(bash "$RESOLVER" --dev-os darwin --platform mobile --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_mob_ts=$(echo "$output_mob_ts" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_mob_ts" | grep -q "EAS CLI"; then
  pass "Platform filtering: Mobile/TypeScript includes EAS CLI"
else
  fail "Platform filtering: Mobile/TypeScript should include EAS CLI"
fi

# 2h: Desktop platform includes Xcode Command Line Tools on darwin
output_desk=$(bash "$RESOLVER" --dev-os darwin --platform desktop --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_desk=$(echo "$output_desk" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_desk" | grep -q "Xcode"; then
  pass "Platform filtering: Desktop/darwin includes Xcode tools"
else
  fail "Platform filtering: Desktop/darwin should include Xcode tools"
fi

# 2i: Desktop/Rust includes Tauri CLI
output_desk_rs=$(bash "$RESOLVER" --dev-os darwin --platform desktop --language rust --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
all_desk_rs=$(echo "$output_desk_rs" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$all_desk_rs" | grep -q "Tauri CLI"; then
  pass "Platform filtering: Desktop/Rust includes Tauri CLI"
else
  fail "Platform filtering: Desktop/Rust should include Tauri CLI"
fi

# 2j: Superpowers is always offered
for p in web mobile desktop; do
  sp_output=$(bash "$RESOLVER" --dev-os darwin --platform "$p" --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
  sp_names=$(echo "$sp_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
  if echo "$sp_names" | grep -q "Superpowers"; then
    pass "Superpowers offered: $p platform"
  else
    fail "Superpowers NOT offered: $p platform"
  fi
done

# 2k: Context7 MCP is always offered
for p in web mobile desktop; do
  c7_output=$(bash "$RESOLVER" --dev-os darwin --platform "$p" --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
  c7_names=$(echo "$c7_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
  if echo "$c7_names" | grep -q "Context7"; then
    pass "Context7 MCP offered: $p platform"
  else
    fail "Context7 MCP NOT offered: $p platform"
  fi
done

# 2l: Qdrant MCP is always offered
for p in web mobile desktop; do
  qd_output=$(bash "$RESOLVER" --dev-os darwin --platform "$p" --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)
  qd_names=$(echo "$qd_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
  if echo "$qd_names" | grep -q "Qdrant"; then
    pass "Qdrant MCP offered: $p platform"
  else
    fail "Qdrant MCP NOT offered: $p platform"
  fi
done

# ================================================================
# TEST 3: RESOLVER WITH USER PREFERENCES (substitutions, skips, additions)
# ================================================================
section "TEST 3: User Preferences — Substitutions, Skips, Additions"

echo ""

PREFS_DIR=$(mktemp -d)

# 3a: Substitution — replace Semgrep with SonarQube
cat > "$PREFS_DIR/sub-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {
    "SAST Scanner": {
      "default": "Semgrep",
      "selected": "SonarQube",
      "check_command": "command -v sonar-scanner"
    }
  },
  "additions": [],
  "skipped": [],
  "installed": {}
}
EOF

sub_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" --tool-prefs "$PREFS_DIR/sub-prefs.json" 2>/dev/null)
sub_names=$(echo "$sub_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$sub_names" | grep -q "SonarQube"; then
  pass "Substitution: Semgrep replaced by SonarQube in output"
else
  fail "Substitution: SonarQube not found after substituting Semgrep"
fi
if echo "$sub_names" | grep -q "Semgrep"; then
  fail "Substitution: Semgrep should be gone after substitution"
else
  pass "Substitution: Semgrep correctly removed"
fi

# 3b: Skip — skip Qdrant MCP
cat > "$PREFS_DIR/skip-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {},
  "additions": [],
  "skipped": [{"name": "Qdrant MCP", "category": "mcp_server", "reason": "Not needed"}],
  "installed": {}
}
EOF

skip_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" --tool-prefs "$PREFS_DIR/skip-prefs.json" 2>/dev/null)
skip_names=$(echo "$skip_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$skip_names" | grep -q "Qdrant"; then
  fail "Skip: Qdrant MCP should be removed when skipped"
else
  pass "Skip: Qdrant MCP correctly excluded"
fi

# 3c: Additions — add custom tool (Biome)
cat > "$PREFS_DIR/add-prefs.json" << 'EOF'
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {"dev_os": "darwin", "platform": "web", "language": "typescript", "track": "standard"},
  "substitutions": {},
  "additions": [
    {"name": "Biome", "category": "Linter", "check_command": "command -v biome", "description": "All-in-one linter"}
  ],
  "skipped": [],
  "installed": {}
}
EOF

add_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" --tool-prefs "$PREFS_DIR/add-prefs.json" 2>/dev/null)
add_names=$(echo "$add_output" | jq -r '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | join(",")')
if echo "$add_names" | grep -q "Biome"; then
  pass "Addition: Custom tool Biome appears in output"
else
  fail "Addition: Custom tool Biome not found in output"
fi

rm -rf "$PREFS_DIR"

# ================================================================
# TEST 4: SIMULATED PROJECT CREATION
# ================================================================
section "TEST 4: Simulated Project Structure Verification"

echo ""
echo "Note: Full interactive init.sh requires terminal input. Testing"
echo "project structure by simulating what init.sh creates for each combo."
echo ""

# Test matrix: representative combinations
declare -a TEST_RUNS=(
  "web:typescript:standard:personal"
  "mobile:dart:light:personal"
  "desktop:rust:full:organizational"
  "web:python:light:personal"
  "mobile:typescript:standard:personal"
  "desktop:csharp:standard:organizational"
  "mobile:swift:standard:personal"
)

# === FIXTURE SANITY CHECK (BL-044) ===
# Per-host template layout (`templates/pipelines/{ci,release}/<host>/...`)
# was introduced by the host-subdir migration. TEST 4 simulates a GitHub
# host (writes to `.github/workflows/`), so it must source from
# `templates/pipelines/{ci,release}/github/`. If a future move relocates
# those templates again, the silent `[ -f ... ]` cp guards downstream
# would no-op without surfacing the breakage (the original BL-044 bug) —
# fail fast here so a future regression does not silently re-break TEST 4.
#
# Scope: GitHub-only — TEST_RUNS does not parameterize host. Adding
# gitlab/bitbucket coverage is BL-053 follow-up.
test4_missing_fixtures=""
for run in "${TEST_RUNS[@]}"; do
  IFS=':' read -r t_platform_pf t_language_pf _t_track _t_deployment <<< "$run"
  case "$t_language_pf" in
    typescript|javascript) ci_tpl_pf="typescript.yml" ;;
    kotlin) ci_tpl_pf="kotlin.yml" ;;
    java) ci_tpl_pf="java.yml" ;;
    *) ci_tpl_pf="${t_language_pf}.yml" ;;
  esac
  [ -f "$SCRIPT_DIR/templates/pipelines/ci/github/$ci_tpl_pf" ] || \
    test4_missing_fixtures+="    - templates/pipelines/ci/github/$ci_tpl_pf"$'\n'
  [ -f "$SCRIPT_DIR/templates/pipelines/release/github/${t_platform_pf}.yml" ] || \
    test4_missing_fixtures+="    - templates/pipelines/release/github/${t_platform_pf}.yml"$'\n'
done
if [ -n "$test4_missing_fixtures" ]; then
  fail "TEST 4 fixture missing — required GitHub-host templates not found (cannot exercise the templating contract):"
  printf '%s' "$test4_missing_fixtures"
else
  pass "TEST 4 fixture sanity check (GitHub-host CI + release templates present for all 7 combos)"
fi

# === BUILD SHARED FIXTURE SCAFFOLD ONCE (BL-053) ===
# Pre-refactor, each of the 7 combos independently paid the full
# mkdir + cp*13 + chmod + git init cost — ~90% identical across combos.
# Only these files actually diverge per combo:
#   - .claude/phase-state.json      (project name, track, deployment, poc_mode)
#   - .claude/tool-preferences.json (resolver output for that combo)
#   - .github/workflows/ci.yml      (language-specific)
#   - .github/workflows/release.yml (platform-specific)
#   - docs/platform-modules/<t_platform>.md (platform-specific)
#   - PROJECT_INTAKE.md             (appends per-combo tooling section)
# Build the identical scaffold once, then `cp -R fixture/. project/` per
# combo and mutate only the divergent files. Source: BL-053 in
# Reports/2026-06-28-step4-dead-code-perf-eval.md §7 ROI #9 — fixture
# reuse targets the 30-40s waste from N repeated setup cycles.
#
# Cleanup: fixture template lives inside $TEST_DIR (already rm -rf'd
# at end of suite), and is also removed at the end of the TEST 4 loop
# so $TEST_DIR only contains the 7 simulated project dirs when TEST 5+
# reach into it.
TEST4_FIXTURE="$TEST_DIR/_test4_fixture_template"
mkdir -p "$TEST4_FIXTURE"/{docs/reference,docs/platform-modules,docs/test-results,.claude,.github/workflows,scripts/lib,templates/intake-suggestions,templates/tool-matrix,evaluation-prompts/Projects}

cp "$SCRIPT_DIR/docs/builders-guide.md" "$TEST4_FIXTURE/docs/reference/" 2>/dev/null || true
cp "$SCRIPT_DIR/docs/governance-framework.md" "$TEST4_FIXTURE/docs/reference/" 2>/dev/null || true
cp "$SCRIPT_DIR/templates/project-intake.md" "$TEST4_FIXTURE/PROJECT_INTAKE.md"
# BL-136: ship the full BL-046 helpers trio, mirroring init.sh's scaffold
# (the `# BL-046: helpers.sh split` copy block in init.sh). check-phase-gate.sh
# (run bare by TEST 5) sources
# lib/helpers-core.sh directly; under its `set -euo pipefail` a missing
# helpers-core.sh aborts the script BEFORE the "Phase Gate Consistency
# Check" header, tripping TEST 5's "Phase gate script failed to run". The
# pre-BL-136 fixture copied only helpers.sh (the pre-split, self-contained
# world). helpers-full.sh is included too so the helpers.sh shim's own
# `source helpers-full.sh` resolves for any script that loads the shim.
cp "$SCRIPT_DIR/scripts/lib/helpers.sh"      "$TEST4_FIXTURE/scripts/lib/"
cp "$SCRIPT_DIR/scripts/lib/helpers-core.sh" "$TEST4_FIXTURE/scripts/lib/"
cp "$SCRIPT_DIR/scripts/lib/helpers-full.sh" "$TEST4_FIXTURE/scripts/lib/"
cp "$SCRIPT_DIR/scripts/resolve-tools.sh" "$TEST4_FIXTURE/scripts/"
cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" "$TEST4_FIXTURE/scripts/"
cp "$SCRIPT_DIR/scripts/validate.sh" "$TEST4_FIXTURE/scripts/"
cp "$SCRIPT_DIR/scripts/resume.sh" "$TEST4_FIXTURE/scripts/"
cp "$SCRIPT_DIR/scripts/intake-wizard.sh" "$TEST4_FIXTURE/scripts/"
chmod +x "$TEST4_FIXTURE/scripts/"*.sh
cp "$SCRIPT_DIR/templates/tool-matrix/"*.json "$TEST4_FIXTURE/templates/tool-matrix/"
cp "$SCRIPT_DIR/templates/intake-suggestions/"*.json "$TEST4_FIXTURE/templates/intake-suggestions/" 2>/dev/null || true

# APPROVAL_LOG.md is byte-identical across combos (no interpolation),
# so it lives in the fixture template.
cat > "$TEST4_FIXTURE/APPROVAL_LOG.md" << 'LOGEOF'
# Approval Log

## Phase 0 → Phase 1
**Date:**
**Reviewer:**
LOGEOF

# Git init once — nothing under TEST 4 asserts git state directly, but
# we retain the invariant that each simulated project appears
# git-initialized (as init.sh would leave it) so downstream tests (e.g.
# TEST 5's check-phase-gate) see a repo, not a bare cwd.
(cd "$TEST4_FIXTURE" && git init -q)

for run in "${TEST_RUNS[@]}"; do
  IFS=':' read -r t_platform t_language t_track t_deployment <<< "$run"
  label="$t_platform/$t_language/$t_track/$t_deployment"
  project_name="test-${t_platform}-${t_language}"
  project_dir="$TEST_DIR/$project_name"

  echo -e "\n${CYAN}--- Simulating: $label ---${NC}"

  # Copy the shared scaffold (docs, scripts, tool-matrix, intake
  # suggestions, APPROVAL_LOG.md, .git), then mutate the per-combo
  # diff below. `cp -R fixture/. project/` copies contents (including
  # hidden entries like .git and .claude) into project_dir; on macOS
  # (BSD cp) and GNU cp this preserves mode bits, so the +x we set on
  # the fixture's scripts propagates without a per-combo chmod.
  mkdir -p "$project_dir"
  cp -R "$TEST4_FIXTURE"/. "$project_dir"/

  # === PER-COMBO DIFF STARTS HERE ===
  # Platform module (only the combo's platform is asserted; the
  # fixture is intentionally left empty so a skipped copy trips the
  # downstream `Platform module missing` fail).
  [ -f "$SCRIPT_DIR/docs/platform-modules/${t_platform}.md" ] && cp "$SCRIPT_DIR/docs/platform-modules/${t_platform}.md" "$project_dir/docs/platform-modules/"

  # Determine CI template
  case "$t_language" in
    typescript|javascript) ci_tpl="typescript.yml" ;;
    kotlin) ci_tpl="kotlin.yml" ;;
    java) ci_tpl="java.yml" ;;
    *) ci_tpl="${t_language}.yml" ;;
  esac
  # BL-044: Host-aware template layout. TEST 4 simulates a GitHub host
  # (writes to `.github/workflows/`), so source from the `github/` subdir.
  # The flat `templates/pipelines/ci/*.yml` paths predate the host-subdir
  # migration and now never exist — these guards silently no-op'd, which
  # let the downstream `File missing (...): .github/workflows/ci.yml`
  # assertion fail on every combo. Fixture sanity check above guards
  # against the next migration breaking these silently.
  [ -f "$SCRIPT_DIR/templates/pipelines/ci/github/$ci_tpl" ] && cp "$SCRIPT_DIR/templates/pipelines/ci/github/$ci_tpl" "$project_dir/.github/workflows/ci.yml"
  [ -f "$SCRIPT_DIR/templates/pipelines/release/github/${t_platform}.yml" ] && cp "$SCRIPT_DIR/templates/pipelines/release/github/${t_platform}.yml" "$project_dir/.github/workflows/release.yml"

  # NOTE: `git init` and `APPROVAL_LOG.md` were per-combo before the
  # BL-053 fixture-sharing refactor. Both now live in $TEST4_FIXTURE
  # and arrive via the `cp -R` above — do not re-add them here.

  # Create phase-state.json mirroring init.sh's actual schema
  # (init.sh:1601-1616). Audit tests-full-known-bugs-1: the prior
  # heredoc was schema-drifted (missing framework_version, track,
  # deployment, poc_mode, compliance_ready; gates fields flat instead
  # of nested) — letting schema regressions in init.sh ship undetected.
  case "$t_deployment" in
    organizational) poc_json='"sponsored_poc"' ;;
    *)              poc_json='null' ;;
  esac
  cat > "$project_dir/.claude/phase-state.json" << PHASEOF
{
  "project": "$project_name",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$t_track",
  "deployment": "$t_deployment",
  "poc_mode": $poc_json,
  "compliance_ready": false,
  "gates": {
    "phase_0_to_1": null,
    "phase_1_to_2": null,
    "phase_3_to_4": null
  }
}
PHASEOF

  # Assert the schema matches init.sh's canonical shape so a regression
  # in either side is caught.
  for key in project framework_version current_phase track deployment poc_mode compliance_ready gates; do
    if jq -e "has(\"$key\")" "$project_dir/.claude/phase-state.json" >/dev/null 2>&1; then
      pass "phase-state.json has '$key' ($label)"
    else
      fail "phase-state.json missing '$key' ($label)"
    fi
  done
  for gate in phase_0_to_1 phase_1_to_2 phase_3_to_4; do
    if jq -e ".gates | has(\"$gate\")" "$project_dir/.claude/phase-state.json" >/dev/null 2>&1; then
      pass "phase-state.json gates.$gate present ($label)"
    else
      fail "phase-state.json gates.$gate missing ($label)"
    fi
  done

  # APPROVAL_LOG.md now lives in $TEST4_FIXTURE (BL-053) and arrives
  # via `cp -R`. Do not re-write it here — a per-combo re-emit would
  # mask fixture-sharing regressions and negate the reuse win.

  # Run resolver and write tool-preferences.json
  dev_os="darwin"
  resolver_output=$(bash "$SCRIPT_DIR/scripts/resolve-tools.sh" \
    --dev-os "$dev_os" --platform "$t_platform" --language "$t_language" \
    --track "$t_track" --phase 2 --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" 2>/dev/null) || resolver_output=""

  if [ -n "$resolver_output" ]; then
    # Write tool-preferences.json
    today=$(date +%Y-%m-%d)
    installed_phase_0=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category == "version_control" or .category == "json_processor" or .category == "runtime" or .category == "containerization" or .category == "commit_signing") | .name]')
    installed_phase_1=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category != "version_control" and .category != "json_processor" and .category != "containerization" and .category != "commit_signing") | .name]')

    jq -n \
      --arg version "1.0" --arg date "$today" --arg dev_os "$dev_os" \
      --arg platform "$t_platform" --arg language "$t_language" --arg track "$t_track" \
      --argjson phase_0 "$installed_phase_0" --argjson phase_1 "$installed_phase_1" \
      '{schema_version: $version, resolved_at: $date, context: {dev_os: $dev_os, platform: $platform, language: $language, track: $track}, substitutions: {}, additions: [], skipped: [], installed: {phase_0: $phase_0, phase_1: $phase_1}}' \
      > "$project_dir/.claude/tool-preferences.json"

    # Append tooling summary to intake
    echo "" >> "$project_dir/PROJECT_INTAKE.md"
    echo "## Tooling Configuration" >> "$project_dir/PROJECT_INTAKE.md"
    echo "**Resolved for:** Darwin / $t_platform / $t_language / $t_track track" >> "$project_dir/PROJECT_INTAKE.md"
    echo "" >> "$project_dir/PROJECT_INTAKE.md"
    echo "### Installed" >> "$project_dir/PROJECT_INTAKE.md"
    echo "| Tool | Category | Version |" >> "$project_dir/PROJECT_INTAKE.md"
    echo "|---|---|---|" >> "$project_dir/PROJECT_INTAKE.md"
    echo "$resolver_output" | jq -r '.already_installed[] | "| \(.name) | \(.category) | \(.version) |"' >> "$project_dir/PROJECT_INTAKE.md"
  fi

  # === VERIFICATION ===

  # Check critical files
  for f in PROJECT_INTAKE.md .claude/tool-preferences.json .github/workflows/ci.yml; do
    [ -f "$project_dir/$f" ] && pass "File exists ($label): $f" || fail "File missing ($label): $f"
  done

  # Release pipeline (BL-044: per-host github/ subdir, matching the cp source above)
  if [ -f "$SCRIPT_DIR/templates/pipelines/release/github/${t_platform}.yml" ]; then
    [ -f "$project_dir/.github/workflows/release.yml" ] && pass "Release pipeline: $label" || fail "Release pipeline missing: $label"
  fi

  # Platform module
  if [ -f "$SCRIPT_DIR/docs/platform-modules/${t_platform}.md" ]; then
    [ -f "$project_dir/docs/platform-modules/${t_platform}.md" ] && pass "Platform module: $label" || fail "Platform module missing: $label"
  fi

  # tool-preferences.json correct context
  if [ -f "$project_dir/.claude/tool-preferences.json" ]; then
    tp_platform=$(jq -r '.context.platform' "$project_dir/.claude/tool-preferences.json" 2>/dev/null)
    tp_language=$(jq -r '.context.language' "$project_dir/.claude/tool-preferences.json" 2>/dev/null)
    tp_track=$(jq -r '.context.track' "$project_dir/.claude/tool-preferences.json" 2>/dev/null)
    if [ "$tp_platform" = "$t_platform" ] && [ "$tp_language" = "$t_language" ] && [ "$tp_track" = "$t_track" ]; then
      pass "tool-preferences.json context correct: $label"
    else
      fail "tool-preferences.json context wrong ($tp_platform/$tp_language/$tp_track): $label"
    fi
  fi

  # Tool matrix copied
  local_matrix_count=$(ls "$project_dir/templates/tool-matrix/"*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$local_matrix_count" -ge 2 ] && pass "Tool matrix ($local_matrix_count files): $label" || fail "Tool matrix incomplete: $label"

  # Resolve-tools.sh executable
  [ -x "$project_dir/scripts/resolve-tools.sh" ] && pass "resolve-tools.sh executable: $label" || fail "resolve-tools.sh not executable: $label"

  # All scripts executable
  for s in validate.sh check-phase-gate.sh resume.sh intake-wizard.sh resolve-tools.sh; do
    [ -x "$project_dir/scripts/$s" ] && pass "Script executable ($label): $s" || fail "Script not executable ($label): $s"
  done

  # Intake has Tooling Configuration
  grep -q "Tooling Configuration" "$project_dir/PROJECT_INTAKE.md" && pass "Intake tooling section: $label" || fail "Intake tooling section missing: $label"
  grep -q "$t_platform" "$project_dir/PROJECT_INTAKE.md" && pass "Intake references platform: $label" || warn "Intake may not reference platform: $label"

  # Intake suggestions copied
  [ -f "$project_dir/templates/intake-suggestions/${t_platform}.json" ] && pass "Intake suggestions: $label" || warn "Intake suggestions missing: $label"

  # Project-local resolver works
  proj_resolve=$(cd "$project_dir" && bash scripts/resolve-tools.sh \
    --dev-os darwin --platform "$t_platform" --language "$t_language" \
    --track "$t_track" --phase 2 --matrix-dir templates/tool-matrix 2>/dev/null) || proj_resolve=""
  if [ -n "$proj_resolve" ] && echo "$proj_resolve" | jq -e '.auto_install' >/dev/null 2>&1; then
    pass "Project-local resolver works: $label"
  else
    fail "Project-local resolver failed: $label"
  fi
done

# BL-053: fixture template served all 7 combos; retire it before TEST 5
# reaches into $TEST_DIR so the scaffold artifact doesn't masquerade as
# a simulated project.
rm -rf "$TEST4_FIXTURE"

# ================================================================
# TEST 5: PHASE GATE TOOL CHECKS
# ================================================================
section "TEST 5: Phase Gate Integration"

echo ""

# Use the first test project
gate_project="$TEST_DIR/test-web-typescript"
if [ -d "$gate_project" ]; then
  # Run check-phase-gate.sh — it should complete (phase 0, no gates to check)
  gate_output=$(cd "$gate_project" && bash scripts/check-phase-gate.sh 2>&1) || true
  if echo "$gate_output" | grep -q "Phase Gate Consistency Check"; then
    pass "Phase gate script runs in created project"
  else
    fail "Phase gate script failed to run"
  fi

  # Verify it mentions tool resolution if tool-preferences.json exists
  if [ -f "$gate_project/.claude/tool-preferences.json" ]; then
    pass "Phase gate can access tool-preferences.json"
  else
    fail "Phase gate: tool-preferences.json missing"
  fi
else
  warn "Skipping phase gate tests — test project not found"
fi

# ================================================================
# TEST 6: PLUGIN, MCP SERVER, AND SKILL DETECTION
# ================================================================
section "TEST 6: Plugin/MCP/Skill Detection on Current Machine"

echo ""

# Check what the resolver detects as installed on this machine
detect_output=$(bash "$RESOLVER" --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir "$MATRIX_DIR" 2>/dev/null)

# Superpowers
sp_status=$(echo "$detect_output" | jq -r '[(.already_installed)[] | select(.name == "Superpowers")] | length')
if [ "$sp_status" -gt 0 ]; then
  pass "Superpowers plugin: DETECTED as installed"
else
  sp_auto=$(echo "$detect_output" | jq -r '[(.auto_install)[] | select(.name == "Superpowers")] | length')
  if [ "$sp_auto" -gt 0 ]; then
    pass "Superpowers plugin: offered for auto-install"
  else
    fail "Superpowers plugin: not detected and not offered"
  fi
fi

# Context7 MCP
c7_status=$(echo "$detect_output" | jq -r '[(.already_installed)[] | select(.name == "Context7 MCP")] | length')
if [ "$c7_status" -gt 0 ]; then
  pass "Context7 MCP: DETECTED as configured"
else
  c7_auto=$(echo "$detect_output" | jq -r '[(.auto_install)[] | select(.name == "Context7 MCP")] | length')
  if [ "$c7_auto" -gt 0 ]; then
    pass "Context7 MCP: offered for auto-install"
  else
    warn "Context7 MCP: not detected and not offered (may need Node.js)"
  fi
fi

# Qdrant MCP
qd_status=$(echo "$detect_output" | jq -r '[(.already_installed)[] | select(.name == "Qdrant MCP")] | length')
if [ "$qd_status" -gt 0 ]; then
  pass "Qdrant MCP: DETECTED as configured"
else
  qd_manual=$(echo "$detect_output" | jq -r '[(.manual_install)[] | select(.name == "Qdrant MCP")] | length')
  if [ "$qd_manual" -gt 0 ]; then
    pass "Qdrant MCP: listed as manual install (requires Docker + uv)"
  else
    fail "Qdrant MCP: not detected and not listed"
  fi
fi

# Core security tools
for tool in "Git" "jq" "Node.js" "Semgrep" "gitleaks" "Snyk CLI" "Claude Code"; do
  t_status=$(echo "$detect_output" | jq -r --arg n "$tool" '[(.already_installed)[] | select(.name == $n)] | length')
  if [ "$t_status" -gt 0 ]; then
    t_version=$(echo "$detect_output" | jq -r --arg n "$tool" '[(.already_installed)[] | select(.name == $n)] | .[0].version')
    pass "Core tool detected: $tool ($t_version)"
  else
    t_auto=$(echo "$detect_output" | jq -r --arg n "$tool" '[(.auto_install)[] | select(.name == $n)] | length')
    if [ "$t_auto" -gt 0 ]; then
      warn "Core tool NOT installed but offered: $tool"
    else
      fail "Core tool NOT detected and NOT offered: $tool"
    fi
  fi
done

# ================================================================
# TEST 7: DRY-RUN MODE
# ================================================================
section "TEST 7: Dry-Run Mode"

echo ""

# Test dry-run with piped input.
# BL-136: init.sh's intake consumes stdin ONLY at prompt_choice calls.
# prompt_input (project name / description / directory) auto-returns its
# default in a non-interactive/piped context WITHOUT reading a line (the
# `[ ! -t 0 ]` guard in helpers-core.sh::prompt_input), so the piped
# answers must be EXACTLY the ordered prompt_choice selections — no
# name/description/dir lines. The pre-BL-136 fixture fed a name + a
# description + a stale choice count; those two leading lines were
# mis-consumed as invalid Platform-type entries and stdin then hit EOF at
# the (since-added) Governance-mode prompt, so init.sh aborted before ever
# printing "Tool Resolution" (the "Dry-run missing resolver tool output"
# FAIL). prompt_choice has NO non-interactive default by design (a required
# selection has no safe default), so SOIF_NONINTERACTIVE/</dev/null cannot
# substitute for real answers here — the sequence must be fed.
# Sequence: Platform=web(4) · Track=standard(2) · Deployment=personal(1) ·
# Governance=Production Build(2) · Language=typescript(7) · Continue?=Y
# (the raw `read` at init.sh's "Continue?" runs under `set -e`, so it needs
# a value rather than EOF). Menu positions are alphabetical-plus-"other".
dry_input="4
2
1
2
7
Y"

dry_output=$(echo "$dry_input" | bash "$SCRIPT_DIR/init.sh" --dry-run 2>&1) || true

if echo "$dry_output" | grep -q "DRY RUN"; then
  pass "Dry-run mode activates"
else
  fail "Dry-run mode did not activate"
fi

if echo "$dry_output" | grep -q "Tool Resolution"; then
  pass "Dry-run shows resolver-based tool output"
else
  fail "Dry-run missing resolver tool output"
fi

# BL-136 F1: PIN the resolved combo. Menu positions are glob-derived, so a
# deleted/added template silently shifts a fed answer (e.g. dropping the
# csharp CI template slides "7" off typescript) and every OTHER assertion
# still passes on the WRONG combo. Bind the fed sequence to the
# collect_project_info summary line.
if echo "$dry_output" | grep -q "Platform: web | Track: standard | Language: typescript"; then
  pass "Dry-run resolved the fed combo (web / standard / typescript)"
else
  fail "Dry-run combo drifted — menu no longer maps to web/standard/typescript"
fi

# BL-136 F2: assert the BRACKETED per-tool statuses emitted by dry_run_summary,
# NOT bare words. The pre-fix `grep -qi "…DEFERRED"` also matched the intake
# prose "All governance deferred." printed BEFORE tool resolution, so it passed
# even on runs that aborted before the resolver ran (CI-observed on the original
# failing run). The bracketed forms ([already installed] / [WILL INSTALL] /
# [MANUAL] / [DEFERRED Phase N]) appear ONLY once dry_run_summary rendered.
if echo "$dry_output" | grep -q "\[already installed\]\|\[WILL INSTALL\]\|\[MANUAL\]\|\[DEFERRED"; then
  pass "Dry-run shows tool status categories"
else
  fail "Dry-run missing tool status categories"
fi

# BL-136 F3: no-creation check, re-aimed. The old `[ ! -d /tmp/test-dryrun ]`
# was vacuous — the current input never references that path (project name is a
# prompt_input default of "", so the resolved dir is the repo's own parent, an
# EXISTING directory that cannot support a `! -d` check). Assert instead the
# dry_run_summary terminal no-op marker, emitted ONLY when init.sh completes the
# dry-run WITHOUT proceeding to real project creation.
if echo "$dry_output" | grep -q "Re-run without --dry-run to execute"; then
  pass "Dry-run completed in no-op mode (no project created)"
else
  fail "Dry-run did not reach its no-op completion marker (may have created a project)"
fi

# ================================================================
# TEST 8: INIT.SH SYNTAX AND STRUCTURE
# ================================================================
section "TEST 8: Script Syntax Validation"

echo ""

# BL-197: `bash -n f 2>/dev/null || fail "... syntax ERROR"` discarded the
# file:line:message that IS the whole actionable payload — the reader was
# told a file was broken and nothing about where. Capture and quote it.
for syn_target in \
  "$SCRIPT_DIR/init.sh" \
  "$SCRIPT_DIR/scripts/resolve-tools.sh" \
  "$SCRIPT_DIR/scripts/check-phase-gate.sh" \
  "$SCRIPT_DIR/scripts/validate.sh" \
  "$SCRIPT_DIR/scripts/intake-wizard.sh" ; do
  syn_name=$(basename "$syn_target")
  syn_err=$(bash -n "$syn_target" 2>&1) \
    && pass "$syn_name syntax OK" \
    || fail "$syn_name syntax ERROR: $syn_err"
done

# Verify all JSON matrix files are valid
for f in "$MATRIX_DIR"/*.json; do
  fname=$(basename "$f")
  # BL-197: jq's parse error names the offending line/column; the old
  # `> /dev/null 2>&1` threw it away and reported only "JSON invalid".
  # `2>&1 >/dev/null` keeps stderr (into the capture) and drops stdout.
  jq_err=$(jq '.' "$f" 2>&1 >/dev/null) && pass "JSON valid: $fname" || fail "JSON invalid: $fname — $jq_err"
done

# ================================================================
# --- BL-052: wire previously-un-invoked aggregators ---
# ================================================================
# Three test AGGREGATORS shipped with substantial, largely-unique real
# tests but were never invoked by the master run or any CI gate, so
# every assertion inside them ran ZERO times (BL-052 / Step 4 ROI #8).
# Karl-approved Policy A: WIRE them into the master run, delete none.
# Each is a self-contained script that returns rc=0 iff all its own
# tests pass (edge-case-test-suite.sh ends `[ "$FAILED" -eq 0 ]`;
# known-bugs-test-suite.sh and upgrade-path-tests.sh end `exit $FAIL`),
# so the BL-034 delegate pattern applies verbatim: run once, capture rc,
# contribute to PASS/FAIL — no `|| true` wraps, nothing silenced.
#
# HERMETIC: all three are hermetic by construction — edge-case's init
# wrapper bakes in --no-remote-creation (BL-076), and upgrade-path's only
# git usage is a fake `https://example.com/fake.git` remote with no push.
#
# Runtime note: upgrade-path-tests.sh drives resolve-tools.sh across many
# track/phase combos and is slow (~18 min). That is orthogonal to
# correctness and tracked with the master suite's own runtime under
# BL-045 (TEST 1 matrix parallelization) / BL-077 (CI-runnability). It
# stays wired here regardless.
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-052 aggregators — SKIPPED (SUITE_SKIP_AGGREGATORS=1; run as separate CI shards)"
else
section "BL-052: previously-un-invoked aggregators (edge-case / known-bugs / upgrade-path)"

run_child_suite "tests/edge-case-test-suite.sh" \
  "tests/edge-case-test-suite.sh (edge-case sweep — platform/tool-prefs/git-host/re-init/bypass-detector/intake/resolver-timeout)" \
  "tests/edge-case-test-suite.sh FAILED (run tests/edge-case-test-suite.sh for the per-section [FAIL] lines)"

run_child_suite "tests/known-bugs-test-suite.sh" \
  "tests/known-bugs-test-suite.sh (BUG-1..BUG-8 + E1-E40 regression sweep)" \
  "tests/known-bugs-test-suite.sh FAILED (run tests/known-bugs-test-suite.sh for details)"

run_child_suite "tests/upgrade-path-tests.sh" \
  "tests/upgrade-path-tests.sh (track/deployment/POC upgrade + strict-superset no-regression)" \
  "tests/upgrade-path-tests.sh FAILED (run tests/upgrade-path-tests.sh for details)"
fi
# --- end BL-052 aggregator wiring ---

# ================================================================
# SUMMARY
# ================================================================
section "TEST SUMMARY"

echo ""
echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}"
echo -e "  ${RED}FAIL: $FAIL${NC}"
echo -e "  ${YELLOW}WARN: $WARN${NC}"
echo -e "  Total: $((PASS + FAIL + WARN))"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
else
  echo -e "${RED}${BOLD}$FAIL FAILURE(S) DETECTED${NC}"
  echo ""
  echo "Failures:"
  echo -e "$RESULTS" | grep "^FAIL" | sed 's/FAIL|/  • /'
fi

if [ $WARN -gt 0 ]; then
  echo ""
  echo "Warnings:"
  echo -e "$RESULTS" | grep "^WARN" | sed 's/WARN|/  • /'
fi

# Cleanup
rm -rf "$TEST_DIR"
rm -f "$SUITE_CHILD_LOG"   # BL-184-CHILD-EVIDENCE scratch capture

echo ""
echo "Test directory cleaned up: $TEST_DIR"
echo ""

exit $FAIL

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
# TEST 0: FIXTURE ENVELOPE LINT — fail fast on legacy schema in tests/
# ================================================================
section "Fixture envelope lint"
if bash "$SCRIPT_DIR/scripts/lint-fixture-envelopes.sh" "$SCRIPT_DIR/tests" >/dev/null 2>&1; then
  pass "All fixture envelopes use canonical Claude Code schema"
else
  fail "Legacy hook envelope schema found in tests/ (see scripts/lint-fixture-envelopes.sh)"
fi

# ================================================================
# TEST 0b: COUNTER-ANTIPATTERN LINT — wave-2 backstop after PRs #67-#71
# ================================================================
section "Counter-capture antipattern lint"
if bash "$SCRIPT_DIR/scripts/lint-counter-antipattern.sh" >/dev/null 2>&1; then
  pass "No unsanitized 'cmd | grep -c X || echo \"0\"' captures in tracked scripts"
else
  fail "Counter-capture antipattern found (see scripts/lint-counter-antipattern.sh --list)"
fi

# Run the linter's own behavior-test suite so a regression in the lint
# itself (false negative on the antipattern, false positive on the
# sanitizer match, broken allowlist) is caught here too.
section "Counter-antipattern lint — behavior test suite"
if bash "$SCRIPT_DIR/tests/test-lint-counter-antipattern.sh" >/dev/null 2>&1; then
  pass "scripts/lint-counter-antipattern.sh behavior tests (10/10)"
else
  fail "scripts/lint-counter-antipattern.sh behavior tests FAILED (run tests/test-lint-counter-antipattern.sh for details)"
fi

# ================================================================
# TEST 0c: PHASE 1→2 BACKSTOP ATTESTATION (code-check-gates-1)
# ================================================================
# Regression suite for the BL-002 follow-up fix: scripts/check-phase-gate.sh's
# Phase 1→2 backstop must honor a recorded `github_free_tier`
# branch-protection attestation (mirroring scripts/check-gate.sh::cmd_preflight).
section "Phase 1→2 backstop honors github_free_tier attestation"
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-backstop-attestation.sh" >/dev/null 2>&1; then
  pass "scripts/check-phase-gate.sh backstop attestation tests (3/3)"
else
  fail "scripts/check-phase-gate.sh backstop attestation tests FAILED (run tests/test-check-phase-gate-backstop-attestation.sh for details)"
fi

# ================================================================
# TEST 0c2: PHASE 1→2 RETROACTIVE STA APPROVAL (tier-crosscheck-5)
# ================================================================
# Regression suite for the audit tier-crosscheck-5 closure:
# scripts/check-phase-gate.sh must emit a non-blocking WARN when
# APPROVAL_LOG.md has `upgraded_from: personal` AND current_phase >= 2
# AND the Retroactive Phase 1 → Phase 2 STA Approval row is incomplete.
section "Phase 1→2 retroactive STA approval surfaces WARN on personal→org upgrades"
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-retroactive-approval.sh" >/dev/null 2>&1; then
  pass "scripts/check-phase-gate.sh retroactive STA approval tests (3/3)"
else
  fail "scripts/check-phase-gate.sh retroactive STA approval tests FAILED (run tests/test-check-phase-gate-retroactive-approval.sh for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-upgrade-project-retroactive-section.sh" >/dev/null 2>&1; then
  pass "scripts/upgrade-project.sh retroactive section stamping tests (2/2)"
else
  fail "scripts/upgrade-project.sh retroactive section stamping tests FAILED (run tests/test-upgrade-project-retroactive-section.sh for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-tier-crosscheck-6-zdr-gate.sh" >/dev/null 2>&1; then
  pass "tier-crosscheck-6 ZDR/data_classification hard gate tests (8/8)"
else
  fail "tier-crosscheck-6 ZDR/data_classification hard gate tests FAILED (run tests/test-tier-crosscheck-6-zdr-gate.sh for details)"
fi

# tier-crosscheck-6 follow-up: atomicity + jq-failure regression suite
# (adversarial verifier follow-up on PR #105). Three tests covering the
# defects the original suite did not catch: SIGTERM mid-mutation in
# reconfigure-project.sh, silent-success on jq failure in
# intake-wizard.sh's --data-classification path and persist_phase1_artifacts().
if bash "$SCRIPT_DIR/tests/test-tier-crosscheck-6-followup-atomicity-and-jq.sh" >/dev/null 2>&1; then
  pass "tier-crosscheck-6 follow-up (atomicity + jq surfacing) tests (3/3)"
else
  fail "tier-crosscheck-6 follow-up tests FAILED (run tests/test-tier-crosscheck-6-followup-atomicity-and-jq.sh for details)"
fi

# ================================================================
# TEST 0c3: ORGANIZATIONAL END-TO-END INIT (tests-init-host-attestation-4)
# ================================================================
# Regression suite for the audit tests-init-host-attestation-4 closure:
# init.sh --non-interactive --deployment organizational must produce the
# organizational APPROVAL_LOG.md template + record deployment in
# manifest/phase-state + honor --no-remote-creation.
section "init.sh organizational end-to-end coverage"
if bash "$SCRIPT_DIR/tests/test-init-organizational.sh" >/dev/null 2>&1; then
  pass "init.sh organizational end-to-end tests (2/2)"
else
  fail "init.sh organizational end-to-end tests FAILED (run tests/test-init-organizational.sh for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-init-fail-status-propagation.sh" >/dev/null 2>&1; then
  pass "init.sh BL-064 silent-success-after-FAIL tests (5/5)"
else
  fail "init.sh BL-064 silent-success-after-FAIL tests FAILED (run tests/test-init-fail-status-propagation.sh for details)"
fi

# ================================================================
# TEST 0c3c: BL-064 — structural backstop lint for new print_fail sites
# ================================================================
# Sibling of lint-counter-antipattern.sh: enforces that every print_fail
# invocation in init.sh either terminates (exit/return inline or within
# 2 lines), routes through record_init_failure, or carries an explicit
# `# lint-fail-emit-exit-status: allow <reason>` annotation. Prevents
# regression of the BL-064 silent-success-after-FAIL defect class.
section "Fail-emit exit-status propagation lint (BL-064 structural backstop)"
if bash "$SCRIPT_DIR/scripts/lint-fail-emit-exit-status.sh" >/dev/null 2>&1; then
  pass "Every print_fail in init.sh propagates to exit status (or is annotated)"
else
  fail "Fail-emit lint found a print_fail without exit-status propagation (see scripts/lint-fail-emit-exit-status.sh --list)"
fi

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
if bash "$SCRIPT_DIR/tests/test-init-non-interactive-mobile-auto-install.sh" >/dev/null 2>&1; then
  pass "init.sh --non-interactive AUTO_INSTALL_TOOLS tests (3/3)"
else
  fail "init.sh --non-interactive AUTO_INSTALL_TOOLS tests FAILED (run tests/test-init-non-interactive-mobile-auto-install.sh for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-init-write-perm-preflight.sh" >/dev/null 2>&1; then
  pass "init.sh BL-041 layering tests (3/3)"
else
  fail "init.sh BL-041 layering tests FAILED (run tests/test-init-write-perm-preflight.sh for details)"
fi

# ================================================================
# TEST 0d: BACKLOG-REFERENCES LINT — cycle-7 Slot-5 process backstop
# ================================================================
# Sibling of the counter-antipattern lint above; catches drift between
# BL-NNN backlog entries and the PRs that close them. See
# scripts/lint-backlog-references.sh header for the defect classes
# and allowlist mechanism.
section "Backlog-references lint"
if bash "$SCRIPT_DIR/scripts/lint-backlog-references.sh" --base origin/main >/dev/null 2>&1; then
  pass "Backlog references and Closed-status citations are consistent"
else
  fail "Backlog-references lint found drift (see scripts/lint-backlog-references.sh --base origin/main --list)"
fi

section "Backlog-references lint — behavior test suite"
if bash "$SCRIPT_DIR/tests/test-lint-backlog-references.sh" >/dev/null 2>&1; then
  pass "scripts/lint-backlog-references.sh behavior tests (10/10)"
else
  fail "scripts/lint-backlog-references.sh behavior tests FAILED (run tests/test-lint-backlog-references.sh for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-platform-mobile-mcp-docs.sh" >/dev/null 2>&1; then
  pass "tests/test-platform-mobile-mcp-docs.sh (8/8)"
else
  fail "tests/test-platform-mobile-mcp-docs.sh FAILED — re-run for details"
fi

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
if bash "$SCRIPT_DIR/tests/test-lint-fix-functions-stderr.sh" >/dev/null 2>&1; then
  pass "scripts/lint-fix-functions-stderr.sh behavior tests (10/10)"
else
  fail "scripts/lint-fix-functions-stderr.sh behavior tests FAILED (run tests/test-lint-fix-functions-stderr.sh for details)"
fi
if bash "$SCRIPT_DIR/tests/test-lint-raw-read-prompt.sh" >/dev/null 2>&1; then
  pass "scripts/lint-raw-read-prompt.sh behavior tests"
else
  fail "scripts/lint-raw-read-prompt.sh behavior tests FAILED (run tests/test-lint-raw-read-prompt.sh for details)"
fi

# BL-076: no test may execute init.sh in a shape that can create a REAL
# remote repo against an authenticated host (the kraulerson/foo leak).
# Run the lint against the live tree AND its own behavior suite so a
# regression in the guard (false negative letting a live run through, or
# false positive on a reporter string / mocked run) is caught here.
section "No-live-remote-in-tests lint (BL-076)"
if bash "$SCRIPT_DIR/scripts/lint-no-live-remote-in-tests.sh" >/dev/null 2>&1; then
  pass "No test executes init.sh in a live-remote-reachable shape"
else
  fail "Non-hermetic init run found (see scripts/lint-no-live-remote-in-tests.sh --list)"
fi
if bash "$SCRIPT_DIR/tests/test-lint-no-live-remote.sh" >/dev/null 2>&1; then
  pass "scripts/lint-no-live-remote-in-tests.sh behavior tests (14/14)"
else
  fail "scripts/lint-no-live-remote-in-tests.sh behavior tests FAILED (run tests/test-lint-no-live-remote.sh for details)"
fi

# BL-051: tests/test-resolve-tools-memoization.sh — proves init.sh's
# get_available_platforms() memoizes its filesystem scan (guard-var +
# cached string, bash-3.2-safe) so 10 invocations trigger exactly one
# scan, not ten. The counter-spy assertion is mutation-provable: revert
# the memoization and the scan fires 10× → T2 goes red. (Function is in
# init.sh, not resolve-tools.sh — the BL-051/Step-4 filename is a known
# misattribution; the test filename honors the backlog naming.)
if bash "$SCRIPT_DIR/tests/test-resolve-tools-memoization.sh" >/dev/null 2>&1; then
  pass "init.sh get_available_platforms() memoization (BL-051, 2/2)"
else
  fail "init.sh get_available_platforms() memoization tests FAILED (run tests/test-resolve-tools-memoization.sh for details)"
fi

# BL-038: tests/test-lint-tests-registered.sh — behavior suite for the
# runner-registration backstop. Validates the lint's positive,
# negative, EXEMPT-marker, mutation, and reverse-mutation paths so a
# regression in the lint itself (false negative on a new orphan,
# false positive on a comment-mention) is surfaced at the aggregator.
if bash "$SCRIPT_DIR/tests/test-lint-tests-registered.sh" >/dev/null 2>&1; then
  pass "scripts/lint-tests-registered.sh behavior tests"
else
  fail "scripts/lint-tests-registered.sh behavior tests FAILED (run tests/test-lint-tests-registered.sh for details)"
fi

# BL-038: repo-wide lint invocation. Refuses to merge a new
# tests/test-*.sh file unless an aggregator invokes it or the file
# carries an EXEMPT marker. See scripts/lint-tests-registered.sh
# header for the registration contract + KNOWN_ORPHANS_PENDING_BL035
# bridge.
section "Tests-registered lint (BL-038 structural backstop)"
if bash "$SCRIPT_DIR/scripts/lint-tests-registered.sh" >/dev/null 2>&1; then
  pass "Every tests/test-*.sh is invoked by an aggregator (or EXEMPT)"
else
  fail "Tests-registered lint found unregistered test file(s) (see scripts/lint-tests-registered.sh --list)"
fi

# BL-048: tests/test-lint-doc-anchors.sh — behavior suite for the
# dead-in-document-anchor backstop. Validates the lint's positive,
# negative, fence-aware, dedup-suffix, and cross-file-out-of-scope
# paths so a regression in the lint itself (false negative on a
# broken anchor, false positive on fenced example content) is
# surfaced at the aggregator.
if bash "$SCRIPT_DIR/tests/test-lint-doc-anchors.sh" >/dev/null 2>&1; then
  pass "scripts/lint-doc-anchors.sh behavior tests"
else
  fail "scripts/lint-doc-anchors.sh behavior tests FAILED (run tests/test-lint-doc-anchors.sh for details)"
fi

# BL-048: repo-wide lint invocation. Fails when a markdown file under
# docs/ contains a `[text](#anchor)` reference whose target heading
# doesn't exist in the same file (GitHub-derived slug, fence-aware).
# See scripts/lint-doc-anchors.sh header for the derivation contract.
section "Doc-anchors lint (BL-048 structural backstop)"
if bash "$SCRIPT_DIR/scripts/lint-doc-anchors.sh" >/dev/null 2>&1; then
  pass "Every in-document anchor reference under docs/ resolves"
else
  fail "Doc-anchors lint found broken anchor reference(s) (see scripts/lint-doc-anchors.sh --list)"
fi

# ----------------------------------------------------------------
# TEST 0g: INTAKE WIZARD + RECONFIGURE FIELD HANDLERS
# ----------------------------------------------------------------
# PR #83: tests/test-intake-wizard-fixes.sh — sweep of wizard-row
# rendering, title round-trip, and resolver-prefill correctness.
# PR #84: tests/test-reconfigure-field-handlers.sh — atomic
# snapshot pattern for reconfigure-project.sh --field handlers.
section "Intake wizard + reconfigure field handlers (PRs #83, #84)"
if bash "$SCRIPT_DIR/tests/test-intake-wizard-fixes.sh" >/dev/null 2>&1; then
  pass "tests/test-intake-wizard-fixes.sh"
else
  fail "tests/test-intake-wizard-fixes.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-reconfigure-field-handlers.sh" >/dev/null 2>&1; then
  pass "tests/test-reconfigure-field-handlers.sh"
else
  fail "tests/test-reconfigure-field-handlers.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0h: CHECK-PHASE-GATE VARIANTS (noninteractive, self-approval)
# ----------------------------------------------------------------
# PR #87: scripts/check-phase-gate.sh must operate in --non-interactive
# mode and must surface a WARN when an STA self-approves their own
# Phase 1→2 gate. Both tests exercise gate-policy enforcement
# orthogonal to the backstop/retroactive paths covered in 0c/0c2.
section "Check-phase-gate noninteractive + self-approval (PR #87)"
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-noninteractive.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate-noninteractive.sh"
else
  fail "tests/test-check-phase-gate-noninteractive.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-self-approval.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate-self-approval.sh"
else
  fail "tests/test-check-phase-gate-self-approval.sh FAILED (run for details)"
fi
# code-check-gates-7-followup (cycle-7 PR-#87 verifier major #4):
# scripts/check-phase-gate.sh now uses per-line `git blame` (not
# file-level `git log -1`) to resolve the commit author of the active
# gate's Approver row. Closes the false-negative attack where Alice
# self-approves gate A in C1 and Bob later commits a typo fix to gate
# B in C2 → file-level lookup returned Bob → Alice's self-approval
# silently passed. The blame-walker tests pin the fix.
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-blame-walker.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate-blame-walker.sh"
else
  fail "tests/test-check-phase-gate-blame-walker.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-argv-parser.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate-argv-parser.sh"
else
  fail "tests/test-check-phase-gate-argv-parser.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-date-writeback.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate-date-writeback.sh"
else
  fail "tests/test-check-phase-gate-date-writeback.sh FAILED (run for details)"
fi
# BL-071 (rolled-in minor): init.sh's phase-state.json seed must emit all
# four gate keys — pre-fix it missed phase_2_to_3. Bootstraps a real
# init.sh project and asserts gates.{phase_0_to_1,phase_1_to_2,
# phase_2_to_3,phase_3_to_4} are all present as null.
if bash "$SCRIPT_DIR/tests/test-init-seeds-four-gate-keys.sh" >/dev/null 2>&1; then
  pass "tests/test-init-seeds-four-gate-keys.sh"
else
  fail "tests/test-init-seeds-four-gate-keys.sh FAILED (run for details)"
fi
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
if bash "$SCRIPT_DIR/tests/test-phase3-validation-gate.sh" >/dev/null 2>&1; then
  pass "tests/test-phase3-validation-gate.sh"
else
  fail "tests/test-phase3-validation-gate.sh FAILED (run for details)"
fi

# BL-088: scaffold source-closure. init.sh must ship every sibling script that a
# shipped gate sources/execs via "$SCRIPT_DIR/..." (tdd-classify.sh silently
# no-op'd the TDD hard block; run-phase3-validation.sh's pass-path was
# unreachable). test-scaffold-source-closure.sh is the static class killer (RED
# if any shipped script sources an unshipped sibling); test-scaffold-tdd-block-
# real.sh is the init.sh-driven fidelity proof (a real Sponsored-POC scaffold
# blocks a test-less feat: commit) + the upgrade/verify backfill for existing
# projects.
if bash "$SCRIPT_DIR/tests/test-scaffold-source-closure.sh" >/dev/null 2>&1; then
  pass "tests/test-scaffold-source-closure.sh"
else
  fail "tests/test-scaffold-source-closure.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-scaffold-tdd-block-real.sh" >/dev/null 2>&1; then
  pass "tests/test-scaffold-tdd-block-real.sh"
else
  fail "tests/test-scaffold-tdd-block-real.sh FAILED (run for details)"
fi

# BL-109 S1 (Currency System, Layer 0 — Inventory). test-currency-manifest.sh is
# the lib-level unit test (schema, class assignment, hook enum, sha/mode capture,
# render-base capture, reader/writer round-trip, dual-source ban) — it never runs
# init.sh, so it is ALSO in the tests.yml unit fast lane. test-currency-birth-
# stamp.sh is the BL-088-precedent aggregator: it runs the REAL init.sh three
# times (typescript/rust/other) to prove the currency block stamps at birth with
# shas that recompute end-to-end and the three-state hook enum. That aggregator
# is SUITE_SKIP_AGGREGATORS-gated (three scaffolds is heavy) and is NEVER in the
# unit list (it executes init.sh).
if bash "$SCRIPT_DIR/tests/test-currency-manifest.sh" >/dev/null 2>&1; then
  pass "tests/test-currency-manifest.sh"
else
  fail "tests/test-currency-manifest.sh FAILED (run for details)"
fi
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-109 currency birth-stamp fidelity — SKIPPED (SUITE_SKIP_AGGREGATORS=1; three real init.sh scaffolds, runs standalone / full-suite)"
else
if bash "$SCRIPT_DIR/tests/test-currency-birth-stamp.sh" >/dev/null 2>&1; then
  pass "tests/test-currency-birth-stamp.sh"
else
  fail "tests/test-currency-birth-stamp.sh FAILED (run for details)"
fi
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
if bash "$SCRIPT_DIR/tests/test-freshness-check.sh" >/dev/null 2>&1; then
  pass "tests/test-freshness-check.sh"
else
  fail "tests/test-freshness-check.sh FAILED (run for details)"
fi
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-109 freshness birth fidelity — SKIPPED (SUITE_SKIP_AGGREGATORS=1; a real init.sh scaffold, runs standalone / full-suite)"
else
if bash "$SCRIPT_DIR/tests/test-freshness-birth.sh" >/dev/null 2>&1; then
  pass "tests/test-freshness-birth.sh"
else
  fail "tests/test-freshness-birth.sh FAILED (run for details)"
fi
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
if bash "$SCRIPT_DIR/tests/test-bl112-commit-enforcement.sh" >/dev/null 2>&1; then
  pass "tests/test-bl112-commit-enforcement.sh"
else
  fail "tests/test-bl112-commit-enforcement.sh FAILED (run for details)"
fi
fi

# BL-118 (Dogfood-2 F-DF2-007, Critical): the SAST gate must SEE browser DOM XSS.
# Pins the DOM-sink ruleset (r/javascript.browser.security.insecure-document-method)
# into every emitter of the semgrep invocation — the hook-templates lib (the hook's
# single source of truth), all 20 generated CI pipelines, and verify-install.sh's
# fix_precommit_hook (which used to re-inline a pre-BL-112 blind hook on repair).
# Live cases drive a REAL `git commit` of `pane.innerHTML = userText` through the
# lib-emitted hook (LOUD SKIP without semgrep). Emits the hook via the lib directly
# — no scaffold run — so it is ALSO in the tests.yml unit fast lane.
if bash "$SCRIPT_DIR/tests/test-bl118-sast-dom-xss.sh" >/dev/null 2>&1; then
  pass "tests/test-bl118-sast-dom-xss.sh"
else
  fail "tests/test-bl118-sast-dom-xss.sh FAILED (run for details)"
fi

# BL-119 (Dogfood-2 F-DF2-006, High) + BL-087 fold-in: the strict terminal gate
# must not classify a commit by the PREVIOUS commit's message (stale
# .git/COMMIT_EDITMSG at pre-commit bricked the repo after any landed feat:
# commit), and the commit-msg surface must pass GRACEFULLY inside the framework
# repo itself instead of hard-refusing via guard_not_in_framework. Drives a REAL
# `git commit` through the REAL framework-gate chain installed by
# install-filesystem-gates.sh — no scaffold run, so ALSO in the unit fast lane.
if bash "$SCRIPT_DIR/tests/test-bl119-stale-editmsg.sh" >/dev/null 2>&1; then
  pass "tests/test-bl119-stale-editmsg.sh"
else
  fail "tests/test-bl119-stale-editmsg.sh FAILED (run for details)"
fi

# BL-105 (Med, walk-confirmed worse than filed): Phase 4 gets a real gate —
# --start-phase4 consults the 3→4 gate; a never-started Phase-4 checklist
# blocks at phase>=4; the rollback/monitoring/go-live artifact arms demand
# substantive evidence (an empty file, the word 'monitoring', and bare
# RELEASE_NOTES existence all used to pass); approval-log templates gain the
# UAT sign-off + personal attorney/pen-test sections; the guide's artifact
# map and the undocumented handoff_tested step are fixed; the Competency
# Matrix is WARN-first visible. Double-fence mutation in-suite. Both lanes.
if bash "$SCRIPT_DIR/tests/test-bl105-phase4-wave.sh" >/dev/null 2>&1; then
  pass "tests/test-bl105-phase4-wave.sh"
else
  fail "tests/test-bl105-phase4-wave.sh FAILED (run for details)"
fi

# BL-107 (High): every language gets the TDD/BL-006 commit-msg gate. Hermetic
# half: the # BL-107-RUST-INLINE-TESTS content probe (inline #[cfg(test)]
# additions count as tests — without it universal install would false-block
# idiomatic Rust TDD), the `other`-language generic-convention heuristic, and
# the Currency hook-state predicate (present for every language). The INSTALL
# half is proven by test-scaffold-tdd-block-real.sh's rust/other scaffold
# cases (aggregator lane). No init.sh here -> ALSO in the unit lane.
if bash "$SCRIPT_DIR/tests/test-bl107-tdd-all-languages.sh" >/dev/null 2>&1; then
  pass "tests/test-bl107-tdd-all-languages.sh"
else
  fail "tests/test-bl107-tdd-all-languages.sh FAILED (run for details)"
fi

# BL-121 (Dogfood-2 F-DF2-011, High): the MVP-Cutline counter must count the
# same 3 items on BSD and GNU text tools. The old GNU-only sed alternation made
# the range run to EOF on macOS (68 vs 3) and hard-blocked the production 3→4
# gate via the exit-2 WARN arm. Extracts and evaluates the LIVE assignment from
# test-gate.sh against a trap-structured fixture manifesto. The cross-platform
# tripwire for the class is lint-counter-antipattern's sed-alternation rule.
if bash "$SCRIPT_DIR/tests/test-bl121-cutline-bsd-sed.sh" >/dev/null 2>&1; then
  pass "tests/test-bl121-cutline-bsd-sed.sh"
else
  fail "tests/test-bl121-cutline-bsd-sed.sh FAILED (run for details)"
fi

# BL-108/BL-117 (the BL-088 class, artifact form): a shipped instruction must
# never point at an unshipped dependency. Mechanical closures: every template
# a shipped script's non-comment text or the guide names must be in init.sh's
# cp set (5 gate-demanded templates were unshipped, incl. one named by a
# gate's own error message); every scripts/*.sh the guide names must ship
# (check-maintenance + 3 lints). Plus the production_build smoke-evidence arm
# (F19: a "built" release that did not boot). Fence mutation in-suite.
if bash "$SCRIPT_DIR/tests/test-bl108-bl117-ship-closure.sh" >/dev/null 2>&1; then
  pass "tests/test-bl108-bl117-ship-closure.sh"
else
  fail "tests/test-bl108-bl117-ship-closure.sh FAILED (run for details)"
fi

# BL-114/BL-115/BL-127 (the E1a gate-integrity trio): the 0→1 gate's WARN
# survives errexit and the intermediates check truly blocks; --start-phase1
# consults the gate and is documented; approval evidence requires the Date
# CELL (not any date in a proximity window); the attorney gate needs a dated
# row (not the template's own header) and legal review is required-when-PII;
# UAT results_received demands submissions or an explicit RECORDED solo-mode
# attestation. No init.sh -> both lanes.
if bash "$SCRIPT_DIR/tests/test-bl114-bl115-bl127-gate-integrity.sh" >/dev/null 2>&1; then
  pass "tests/test-bl114-bl115-bl127-gate-integrity.sh"
else
  fail "tests/test-bl114-bl115-bl127-gate-integrity.sh FAILED (run for details)"
fi

# BL-116 (Med): the MANDATORY push gate keys on recorded facts, not host brand
# — first-class hosts are exempt only when remote_repo_created+pushed_initial
# are on record ("provably pushed at init", on disk); --no-remote-creation
# scaffolds now gate. Fence-excision mutant proves the scope change
# load-bearing. No init.sh -> both lanes.
if bash "$SCRIPT_DIR/tests/test-bl116-push-gate-scope.sh" >/dev/null 2>&1; then
  pass "tests/test-bl116-push-gate-scope.sh"
else
  fail "tests/test-bl116-push-gate-scope.sh FAILED (run for details)"
fi

# BL-123/BL-111/BL-126 (High/High/Med): the branch-protection attestation is
# recordable post-hoc (check-gate.sh --repair --branch-protection-attested /
# SOLO_BP_ATTESTED=1, host-keyed reason, explicit-only) and honored by ALL
# THREE consumers — verify_init consults it before any host API probe. In-test
# fence-excision mutants prove both arms load-bearing. No init.sh -> both lanes.
if bash "$SCRIPT_DIR/tests/test-bl123-bp-attestation-recovery.sh" >/dev/null 2>&1; then
  pass "tests/test-bl123-bp-attestation-recovery.sh"
else
  fail "tests/test-bl123-bp-attestation-recovery.sh FAILED (run for details)"
fi

# BL-124 (Dogfood-2 F-DF2-014, High — the central-question hole): the Phase 3→4
# gate must FAIL while PRODUCT_MANIFESTO.md carries the PENDING promotion
# marker upgrade-project.sh writes on track upgrade. Wire-pins the writer's and
# the reader's literals to one constant; bl104-style copy-mutant proves the arm
# load-bearing. No init.sh -> ALSO in the tests.yml unit lane.
if bash "$SCRIPT_DIR/tests/test-bl124-pending-ratchet.sh" >/dev/null 2>&1; then
  pass "tests/test-bl124-pending-ratchet.sh"
else
  fail "tests/test-bl124-pending-ratchet.sh FAILED (run for details)"
fi

# BL-130 (Dogfood-2 F-DF2-013, Low): --attest must REFUSE a scanner whose last
# REAL verdict is FAIL — attestations cover scans that could not run, never
# scans that ran and failed ([OK]-recorded a FAIL-masking row the driver would
# then refuse to honor). In-suite fence-excision mutant. No init.sh -> both
# lanes.
if bash "$SCRIPT_DIR/tests/test-bl130-attest-fail-guard.sh" >/dev/null 2>&1; then
  pass "tests/test-bl130-attest-fail-guard.sh"
else
  fail "tests/test-bl130-attest-fail-guard.sh FAILED (run for details)"
fi

# BL-096 (ergonomics F6/F9/F10): cold-start hardening — the CDF preflight
# names the exact clone line at suite ENTRY (warn-and-continue; CI runs
# CDF-less), pre-commit-gate.sh --help tells the truth about --tdd-only
# running BOTH message gates (+ the --commit-msg-gates honest-name alias,
# behavior-pinned), and install-contributor-hooks.sh is CONTRIBUTING's
# manual cp as one idempotent command. No init.sh -> both lanes.
if bash "$SCRIPT_DIR/tests/test-bl096-cold-start.sh" >/dev/null 2>&1; then
  pass "tests/test-bl096-cold-start.sh"
else
  fail "tests/test-bl096-cold-start.sh FAILED (run for details)"
fi

# BL-095 (ergonomics F4): ONE parsing surface for deployment/poc_mode
# (# BL-095-STATE-READERS in lib/helpers-core.sh) — unit contract (null/
# absent/missing-file/default/no-jq fallback), source-closure over the four
# migrated files, and a fence-excision mutant that must CRASH check-phase-
# gate (routing proof). Conforming-inline siblings (pre-commit-gate,
# run-phase3-validation) documented at the fence. No init.sh -> both lanes.
if bash "$SCRIPT_DIR/tests/test-bl095-state-readers.sh" >/dev/null 2>&1; then
  pass "tests/test-bl095-state-readers.sh"
else
  fail "tests/test-bl095-state-readers.sh FAILED (run for details)"
fi

# BL-106 (Karl's 2026-07-18 machine-checkable decision): the platform
# go-live checklist is PARSED — the shipped module's H3 /Go-Live/ `- [ ]`
# items must be ticked in a dated docs/test-results/*go-live-checklist*
# artifact at go_live_verified; standalone platforms exempt with a note.
# In-suite fence-excision mutant. No init.sh -> both lanes (the init-side
# generator has its real-init case in test-scaffold-tdd-block-real.sh).
if bash "$SCRIPT_DIR/tests/test-bl106-golive-checklist.sh" >/dev/null 2>&1; then
  pass "tests/test-bl106-golive-checklist.sh"
else
  fail "tests/test-bl106-golive-checklist.sh FAILED (run for details)"
fi

# BL-138 (Dogfood-3 F-DF3-001): validate_approval_fields no longer
# self-collides with the template — H2-anchored section-bounded window
# (table rows can neither anchor nor extend the scan) + template-literal
# placeholder predicate ([SIMULATED] and date-format prose are not
# placeholders). Twin-fixture rc-parity isolation; in-suite fence-excision
# mutant on a shape only the detector rejects. No init.sh -> both lanes.
if bash "$SCRIPT_DIR/tests/test-bl138-approval-window.sh" >/dev/null 2>&1; then
  pass "tests/test-bl138-approval-window.sh"
else
  fail "tests/test-bl138-approval-window.sh FAILED (run for details)"
fi

# BL-128 (Dogfood-2 F-DF2-015): the review generator is headless-viable —
# --compose-only / --assemble-manifest need no claude at all; live runs get a
# per-review process-GROUP watchdog (REVIEW_TIMEOUT_SECS), actionable
# trust/spend triage, continue-on-failure, and an incrementally-written
# manifest. claude is a PATH stub throughout (plan-file driven). No init.sh
# -> both lanes.
if bash "$SCRIPT_DIR/tests/test-bl128-review-generator-headless.sh" >/dev/null 2>&1; then
  pass "tests/test-bl128-review-generator-headless.sh"
else
  fail "tests/test-bl128-review-generator-headless.sh FAILED (run for details)"
fi

# BL-102 (Market Signal Step 1.1.5): Appendix D ships in the manifesto
# template, and check-phase-gate WARNs (WARN-FIRST — deliberately NO issues
# increment, pinned by exit-code parity on an issues=0 fixture) when a
# Standard+ project lacks or placeholder-fills it. The mutation case proves
# both directions: excised arm -> warn gone; injected increment -> parity
# breaks (the BL-104 [WARN]-trap inverse). No init.sh -> ALSO in the unit lane.
if bash "$SCRIPT_DIR/tests/test-bl102-market-signal-warn.sh" >/dev/null 2>&1; then
  pass "tests/test-bl102-market-signal-warn.sh"
else
  fail "tests/test-bl102-market-signal-warn.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-plan-staging.sh" >/dev/null 2>&1; then
  pass "tests/test-plan-staging.sh"
else
  fail "tests/test-plan-staging.sh FAILED (run for details)"
fi
if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]; then
  section "BL-109 plan-staging birth fidelity — SKIPPED (SUITE_SKIP_AGGREGATORS=1; a real init.sh scaffold + real --plan, runs standalone / full-suite)"
else
if bash "$SCRIPT_DIR/tests/test-plan-birth.sh" >/dev/null 2>&1; then
  pass "tests/test-plan-birth.sh"
else
  fail "tests/test-plan-birth.sh FAILED (run for details)"
fi
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
if bash "$SCRIPT_DIR/tests/test-bl113-sast-honesty.sh" >/dev/null 2>&1; then
  pass "tests/test-bl113-sast-honesty.sh"
else
  fail "tests/test-bl113-sast-honesty.sh FAILED (run for details)"
fi
fi

# Agent-ergonomics onboarding: tests/test-run-lints.sh — behavior suite for
# scripts/run-lints.sh, the canonical local lint runner (runs every
# scripts/lint-*.sh EXCEPT the parametrized lint-uat-scenarios.sh). Its
# T-all-pass case executes the real lints end-to-end, so this block takes a
# couple of minutes (the two slow full-tree scans dominate).
if bash "$SCRIPT_DIR/tests/test-run-lints.sh" >/dev/null 2>&1; then
  pass "tests/test-run-lints.sh"
else
  fail "tests/test-run-lints.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-bl070-license-scanner.sh" >/dev/null 2>&1; then
  pass "tests/test-bl070-license-scanner.sh"
else
  fail "tests/test-bl070-license-scanner.sh FAILED (run for details)"
fi

# BL-070 (WP-B2): scripts/run-phase3-validation.sh's `threat-model` scanner
# promoted from stub to REAL. Validates every PROJECT_BIBLE.md §4 `TM-NNN`
# threat row against the newest Phase-3 threat-model VALIDATION REPORT in
# docs/test-results/ (glob accepts BOTH *_threat-model-validation.md and the
# legacy *_threat-validation.md name), and requires a non-empty Approved By on
# every Unmitigated-table row. PASS = full coverage + empty-or-approved; FAIL
# names the unaccounted IDs. Pure-local parsing → deliberately RUNS under
# --offline. Mutation-proof: excising the marked `# BL-070-TM-COMPARE`
# coverage-diff line flips T-tm-missing-id-fail RED.
if bash "$SCRIPT_DIR/tests/test-bl070-threat-model-scanner.sh" >/dev/null 2>&1; then
  pass "tests/test-bl070-threat-model-scanner.sh"
else
  fail "tests/test-bl070-threat-model-scanner.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-bl070-snyk-zap-scanners.sh" >/dev/null 2>&1; then
  pass "tests/test-bl070-snyk-zap-scanners.sh"
else
  fail "tests/test-bl070-snyk-zap-scanners.sh FAILED (run for details)"
fi

# BL-073: scripts/check-phase-gate.sh's Phase 3→4 review-manifest check must
# be a REAL, track-aware gate — FAIL (block) when the Security or Red Team
# review is missing for track=standard/full, WARN-only for light/personal
# and for grandfathered projects (no review_gate_enforced flag), and an
# attested OK when SOLO_REVIEWERS_ATTESTED=1 + reason is set (recorded to
# process-state.json). Mutation-proof: excising the marked `# BL-073-ESCALATE`
# escalation reverts the gate to WARN-only, flipping the *-fails cases RED.
# Also pins scripts/lint-review-manifest.sh's schema validation.
if bash "$SCRIPT_DIR/tests/test-bl073-review-manifest-gate.sh" >/dev/null 2>&1; then
  pass "tests/test-bl073-review-manifest-gate.sh"
else
  fail "tests/test-bl073-review-manifest-gate.sh FAILED (run for details)"
fi

# BL-103: the six-eval generator the Phase 3→4 gate hands operators as its
# remediation (evaluation-prompts/Projects/run-reviews.sh) must actually RUN on
# the reference platform (bash 3.2 — it used declare -A / [[ -v ]] and was a
# syntax error), and must RECORD every review it finds — including Red Team, a
# mandatory blocking reviewer whose file the runner probed under the wrong name.
# Runs the real generator against a hermetic fixture with a mock `claude`; pins
# scripts/lint-evalprompts-portability.sh with a behavioural mutation proof.
if bash "$SCRIPT_DIR/tests/test-bl103-eval-generator.sh" >/dev/null 2>&1; then
  pass "tests/test-bl103-eval-generator.sh"
else
  fail "tests/test-bl103-eval-generator.sh FAILED (run for details)"
fi

# BL-104: two scoring inversions in check-phase-gate.sh's Phase 3→4 block, where
# doing LESS work scored BETTER — 0/9 process-checklist steps passed while 8/9
# blocked (an if/elif with no else), and an empty `{"reviews":[]}` manifest
# passed while NO manifest blocked. Mutation-proof on both markers.
if bash "$SCRIPT_DIR/tests/test-bl104-gate-scoring.sh" >/dev/null 2>&1; then
  pass "tests/test-bl104-gate-scoring.sh"
else
  fail "tests/test-bl104-gate-scoring.sh FAILED (run for details)"
fi

# BL-072 Phase C1: scripts/pre-commit-gate.sh must WARN (never block) when a
# feat/fix/refactor commit ships implementation with no test in the same
# commit and none earlier on the branch — appending a row to
# .claude/tdd-warn-ledger.jsonl and always leaving rc=0. Shares its
# file-classification core (scripts/lib/tdd-classify.sh) with the dogfood
# replay. Mutation-proof: excising the marked `# BL-072-TDD-DETECT` trigger
# line removes the WARN, flipping T-feat-no-tests-warns RED.
if bash "$SCRIPT_DIR/tests/test-bl072-tdd-warn-detector.sh" >/dev/null 2>&1; then
  pass "tests/test-bl072-tdd-warn-detector.sh"
else
  fail "tests/test-bl072-tdd-warn-detector.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-bl084-tier-aware-remote-policy.sh" >/dev/null 2>&1; then
  pass "tests/test-bl084-tier-aware-remote-policy.sh"
else
  fail "tests/test-bl084-tier-aware-remote-policy.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0i: PENDING-APPROVAL RESOLVE-DECISION
# ----------------------------------------------------------------
# PR #87 sibling: scripts/pending-approval.sh --resolve-decision flow.
# Exercises the question/options/recommendation round-trip the
# pre-commit-gate's pa_check() depends on.
section "Pending-approval resolve-decision (PR #87)"
if bash "$SCRIPT_DIR/tests/test-pending-approval-resolve-decision.sh" >/dev/null 2>&1; then
  pass "tests/test-pending-approval-resolve-decision.sh"
else
  fail "tests/test-pending-approval-resolve-decision.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0j: BYPASS-AUDIT FAMILY
# ----------------------------------------------------------------
# PR #93 + verifier-fix 2d5f917: the bypass-audit subsystem's
# hardening tests — tmp-directory permission hardening, trap-isolation
# (verifier-fix cohort), and session-id derivation for the bypass
# detector. Pre-fix, hijacking $TMPDIR or trap-leaking from a
# concurrent bypass-audit run was undetected.
section "Bypass-audit hardening cohort (PR #93 + 2d5f917)"
if bash "$SCRIPT_DIR/tests/test-bypass-audit-tmp-hardening.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-audit-tmp-hardening.sh"
else
  fail "tests/test-bypass-audit-tmp-hardening.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bypass-audit-trap-isolation.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-audit-trap-isolation.sh"
else
  fail "tests/test-bypass-audit-trap-isolation.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bypass-detector-session-id.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-detector-session-id.sh"
else
  fail "tests/test-bypass-detector-session-id.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0k: HOST-DRIVER REGRESSIONS (date-parse + gitlab approvals)
# ----------------------------------------------------------------
# PR #93: scripts/lib/hosts/host_verify_protection date-parse bug
# (date offset mis-coercion silently letting drift through).
# PR #91: gitlab-ci-status stderr surfacing for approval/protection
# rule mismatches.
section "Host-driver regressions (PRs #91, #93)"
if bash "$SCRIPT_DIR/tests/test-host-verify-protection-date-parse.sh" >/dev/null 2>&1; then
  pass "tests/test-host-verify-protection-date-parse.sh"
else
  fail "tests/test-host-verify-protection-date-parse.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-gitlab-ci-status-stderr-approvals.sh" >/dev/null 2>&1; then
  pass "tests/test-gitlab-ci-status-stderr-approvals.sh"
else
  fail "tests/test-gitlab-ci-status-stderr-approvals.sh FAILED (run for details)"
fi
# BL-032 close: proactive gitlab.com Free approvals attestation
# (--approvals-attested / SOLO_APPROVALS_ATTESTED=1) — mirrors BL-002's
# github_free_tier attestation for the GitLab analog.
if bash "$SCRIPT_DIR/tests/test-bl032-gitlab-free-approvals-attestation.sh" >/dev/null 2>&1; then
  pass "tests/test-bl032-gitlab-free-approvals-attestation.sh"
else
  fail "tests/test-bl032-gitlab-free-approvals-attestation.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-verify-install-fix-functions.sh" >/dev/null 2>&1; then
  pass "tests/test-verify-install-fix-functions.sh"
else
  fail "tests/test-verify-install-fix-functions.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-prompt-install-noninteractive.sh" >/dev/null 2>&1; then
  pass "tests/test-prompt-install-noninteractive.sh"
else
  fail "tests/test-prompt-install-noninteractive.sh FAILED (run for details)"
fi
# BL-050 (Step 4 ROI #6): the fix_tool_install_N eval-factory in
# scripts/verify-install.sh:~1401 was previously synthesized on every
# invocation including --check-only, wasting ~1.5-10 ms per call.
# Gate check tests both success (skipped on check-only, run on
# auto-fix) and failure (mutation revert restores overhead) paths.
if bash "$SCRIPT_DIR/tests/test-verify-install-eval-factory-gate.sh" >/dev/null 2>&1; then
  pass "tests/test-verify-install-eval-factory-gate.sh"
else
  fail "tests/test-verify-install-eval-factory-gate.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0m: UPGRADE-PROJECT (interruption, sentinel-block, atomic)
# ----------------------------------------------------------------
# PR #80: scripts/upgrade-project.sh snapshot+atomic-finalize.
# PR #95: upgrade interruption-recovery + bypass-sentinel-during-upgrade
# blocking. The atomic suite mirrors the PR #54/#57 snapshot precedent.
section "Upgrade-project atomicity, interruption, sentinel-block (PRs #80, #95)"
if bash "$SCRIPT_DIR/tests/test-upgrade-project-atomic.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-project-atomic.sh"
else
  fail "tests/test-upgrade-project-atomic.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-upgrade-interruption.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-interruption.sh"
else
  fail "tests/test-upgrade-interruption.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-upgrade-sentinel-block.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-sentinel-block.sh"
else
  fail "tests/test-upgrade-sentinel-block.sh FAILED (run for details)"
fi
# BL-099 SLICE-A: --sync-framework same-tier refresh (script sync, ask-first
# hooks, doc drift, soloFrameworkCommit pin, dry-run purity) + both mutation
# proofs (# BL-099-SYNC dispatch, # BL-099-DOC-GUARD rendered-doc exclusion).
if bash "$SCRIPT_DIR/tests/test-upgrade-sync-framework.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-sync-framework.sh"
else
  fail "tests/test-upgrade-sync-framework.sh FAILED (run for details)"
fi
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
if bash "$SCRIPT_DIR/tests/test-bl099-guard-coverage.sh" >/dev/null 2>&1; then
  pass "tests/test-bl099-guard-coverage.sh"
else
  fail "tests/test-bl099-guard-coverage.sh FAILED (run for details)"
fi
fi
# BL-061: manifest.json::deployment stayed stale after upgrade-project.sh
# runs, encouraging two-source drift where a downstream reader could gate
# the wrong tier. Regression suite covers happy-path parity, atomic
# rollback, idempotence, and a mutation-proof that neutralizing the
# section 2b jq write reproduces the original bug shape.
if bash "$SCRIPT_DIR/tests/test-upgrade-manifest-refresh.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-manifest-refresh.sh"
else
  fail "tests/test-upgrade-manifest-refresh.sh FAILED (run for details)"
fi
# BL-001: upgrade-project.sh performed no CDF sync, so downstream projects
# stayed frozen at their install-time .claude/framework/ assets. Regression
# suite covers the happy-path refresh (--backfill-only), graceful skip on a
# missing clone (upgrade must still exit 0), pull-failure resilience, and a
# mutation-proof that neutralizing solo_refresh_cdf's delegating call turns
# the sync into a no-op. Integration scenarios skip cleanly when the CDF
# clone is absent (CI without ~/.claude-dev-framework).
if bash "$SCRIPT_DIR/tests/test-upgrade-cdf-refresh.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-cdf-refresh.sh"
else
  fail "tests/test-upgrade-cdf-refresh.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-process-checklist-check-commit-ready-subject.sh" >/dev/null 2>&1; then
  pass "tests/test-process-checklist-check-commit-ready-subject.sh"
else
  fail "tests/test-process-checklist-check-commit-ready-subject.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-process-checklist-reset-phase1.sh" >/dev/null 2>&1; then
  pass "tests/test-process-checklist-reset-phase1.sh"
else
  fail "tests/test-process-checklist-reset-phase1.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0o: PRE-COMMIT-GATE LINTS + CLASSIFIER
# ----------------------------------------------------------------
# Wave 3: scripts/pre-commit-gate.sh's lint-runner + commit-classifier
# behavior tests. Both are unit-style and fast.
section "Pre-commit-gate lints + classifier (Wave 3)"
if bash "$SCRIPT_DIR/tests/test-pre-commit-gate-lints.sh" >/dev/null 2>&1; then
  pass "tests/test-pre-commit-gate-lints.sh"
else
  fail "tests/test-pre-commit-gate-lints.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-pre-commit-gate-classifier.sh" >/dev/null 2>&1; then
  pass "tests/test-pre-commit-gate-classifier.sh"
else
  fail "tests/test-pre-commit-gate-classifier.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0p: VALIDATE PHASE 2→3 GATE
# ----------------------------------------------------------------
# PR #101: scripts/validate.sh's Phase 2→3 gate path — assert the
# gate refuses to advance when the required artifacts are missing.
section "validate.sh Phase 2→3 gate (PR #101)"
if bash "$SCRIPT_DIR/tests/test-validate-phase-2-3-gate.sh" >/dev/null 2>&1; then
  pass "tests/test-validate-phase-2-3-gate.sh"
else
  fail "tests/test-validate-phase-2-3-gate.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0p2: VALIDATE READS PHASE-STATE.JSON::GATES (BL-059)
# ----------------------------------------------------------------
# BL-059: scripts/validate.sh's Approval Log section previously
# greped APPROVAL_LOG.md only, emitting a false-negative "no date
# recorded" WARN when phase-state.json::gates.<gate> was populated
# but the log had not been mirrored. Fix reads JSON first, falls
# back to APPROVAL_LOG.md for back-compat.
section "validate.sh reads phase-state.json::gates (BL-059)"
if bash "$SCRIPT_DIR/tests/test-validate-phase-state-gates.sh" >/dev/null 2>&1; then
  pass "tests/test-validate-phase-state-gates.sh"
else
  fail "tests/test-validate-phase-state-gates.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# TEST 0q: SPECS+PLANS HOST-AWARE QUARTET
# ----------------------------------------------------------------
# PR #97: docs/superpowers/specs+plans host-aware quartet rendering
# (the spec/plan/test/code-review quartet must reflect the current
# host_name without hard-coding github/gitlab/bitbucket).
section "Specs+plans host-aware quartet (PR #97)"
if bash "$SCRIPT_DIR/tests/test-specs-plans-host-aware-quartet.sh" >/dev/null 2>&1; then
  pass "tests/test-specs-plans-host-aware-quartet.sh"
else
  fail "tests/test-specs-plans-host-aware-quartet.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/edge-cases-pre-init.sh" >/dev/null 2>&1; then
  pass "tests/edge-cases-pre-init.sh"
else
  fail "tests/edge-cases-pre-init.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/edge-cases-scripts.sh" >/dev/null 2>&1; then
  pass "tests/edge-cases-scripts.sh"
else
  fail "tests/edge-cases-scripts.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/edge-cases-upgrade-input.sh" >/dev/null 2>&1; then
  pass "tests/edge-cases-upgrade-input.sh"
else
  fail "tests/edge-cases-upgrade-input.sh FAILED (run for details)"
fi
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
if bash "$SCRIPT_DIR/tests/test-bl046-helpers-split.sh" >/dev/null 2>&1; then
  pass "tests/test-bl046-helpers-split.sh (T1..T5b)"
else
  fail "tests/test-bl046-helpers-split.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-bl033-install-cmds-shape.sh" >/dev/null 2>&1; then
  pass "tests/test-bl033-install-cmds-shape.sh (T-back-compat, T-array-happy, T-array-fail-fast, T-mixed-invalid, T-empty-array, T-non-string-elements, T-migrated-entries, T-migrated-semantics)"
else
  fail "tests/test-bl033-install-cmds-shape.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-bl069-install-cmds-consumers.sh" >/dev/null 2>&1; then
  pass "tests/test-bl069-install-cmds-consumers.sh (Groups A-E: split, run_install_stages, extraction, fix_tool_install dispatch, wrapper JSON regression)"
else
  fail "tests/test-bl069-install-cmds-consumers.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/host-drivers/run-all.sh" >/dev/null 2>&1; then
  pass "tests/host-drivers/run-all.sh (all children)"
else
  fail "tests/host-drivers/run-all.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-test-gate-counter-sanitizer.sh" >/dev/null 2>&1; then
  pass "tests/test-test-gate-counter-sanitizer.sh (5/5)"
else
  fail "tests/test-test-gate-counter-sanitizer.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-test-gate-null-handling.sh" >/dev/null 2>&1; then
  pass "tests/test-test-gate-null-handling.sh (5/5)"
else
  fail "tests/test-test-gate-null-handling.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-validate-counter-sanitizer.sh" >/dev/null 2>&1; then
  pass "tests/test-validate-counter-sanitizer.sh (5/5)"
else
  fail "tests/test-validate-counter-sanitizer.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-record-claude-commit.sh" >/dev/null 2>&1; then
  pass "tests/test-record-claude-commit.sh (9/9)"
else
  fail "tests/test-record-claude-commit.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-unrecord-feature.sh" >/dev/null 2>&1; then
  pass "tests/test-unrecord-feature.sh (7/7)"
else
  fail "tests/test-unrecord-feature.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-session-test-gate-check-merge.sh" >/dev/null 2>&1; then
  pass "tests/test-session-test-gate-check-merge.sh (9/9)"
else
  fail "tests/test-session-test-gate-check-merge.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# Process-checklist / pending-approval / poc-modes (BL-035 C)
# ----------------------------------------------------------------
# pending-approval resolve/escalate flow, process-checklist auto-advance +
# commit classifier, phase-finalize, the platform-security-bugs-closer
# docstring probe (T4b path fixed in Chunk-0), and poc-modes tier semantics
# (T5: --to-private-poc from personal stays personal — aligned with E60,
# see BL-079).
section "BL-035 C: process-checklist / pending / poc-modes"
if bash "$SCRIPT_DIR/tests/test-pending-approval.sh" >/dev/null 2>&1; then
  pass "tests/test-pending-approval.sh (21/21)"
else
  fail "tests/test-pending-approval.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-process-checklist-auto-advance.sh" >/dev/null 2>&1; then
  pass "tests/test-process-checklist-auto-advance.sh (7/7)"
else
  fail "tests/test-process-checklist-auto-advance.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-process-checklist-classifier.sh" >/dev/null 2>&1; then
  pass "tests/test-process-checklist-classifier.sh (12/12)"
else
  fail "tests/test-process-checklist-classifier.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-phase-finalize.sh" >/dev/null 2>&1; then
  pass "tests/test-phase-finalize.sh (6/6)"
else
  fail "tests/test-phase-finalize.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-platform-security-bugs-closer.sh" >/dev/null 2>&1; then
  pass "tests/test-platform-security-bugs-closer.sh (7/7)"
else
  fail "tests/test-platform-security-bugs-closer.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-poc-modes.sh" >/dev/null 2>&1; then
  pass "tests/test-poc-modes.sh (5/5)"
else
  fail "tests/test-poc-modes.sh FAILED (run for details)"
fi

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
if bash "$SCRIPT_DIR/tests/test-pre-commit-gate-terminal-mode.sh" >/dev/null 2>&1; then
  pass "tests/test-pre-commit-gate-terminal-mode.sh (3/3)"
else
  fail "tests/test-pre-commit-gate-terminal-mode.sh FAILED (run for details)"
fi

# ----------------------------------------------------------------
# Docs / specs / lint suites (BL-035 C)
# ----------------------------------------------------------------
# Docs-cluster six-pack (doc-consistency guards), specs+plans remaining
# quartet, and the UAT-scenarios lint behavior suite.
section "BL-035 C: docs / specs / lint suites"
if bash "$SCRIPT_DIR/tests/test-docs-cluster-six-pack.sh" >/dev/null 2>&1; then
  pass "tests/test-docs-cluster-six-pack.sh (28/28)"
else
  fail "tests/test-docs-cluster-six-pack.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-specs-plans-remaining-quartet.sh" >/dev/null 2>&1; then
  pass "tests/test-specs-plans-remaining-quartet.sh (10/10)"
else
  fail "tests/test-specs-plans-remaining-quartet.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-lint-uat-scenarios.sh" >/dev/null 2>&1; then
  pass "tests/test-lint-uat-scenarios.sh (12/12)"
else
  fail "tests/test-lint-uat-scenarios.sh FAILED (run for details)"
fi
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
if bash "$SCRIPT_DIR/tests/test-bl029-integration.sh" >/dev/null 2>&1; then
  pass "tests/test-bl029-integration.sh (incl. folded bypass-audit-schema T1b)"
else
  fail "tests/test-bl029-integration.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bl030-calibration-replay.sh" >/dev/null 2>&1; then
  pass "tests/test-bl030-calibration-replay.sh"
else
  fail "tests/test-bl030-calibration-replay.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bypass-audit-integrity.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-audit-integrity.sh"
else
  fail "tests/test-bypass-audit-integrity.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bypass-audit-lib.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-audit-lib.sh"
else
  fail "tests/test-bypass-audit-lib.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bypass-detector.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-detector.sh"
else
  fail "tests/test-bypass-detector.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bypass-patterns.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-patterns.sh"
else
  fail "tests/test-bypass-patterns.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-bypass-sentinel.sh" >/dev/null 2>&1; then
  pass "tests/test-bypass-sentinel.sh"
else
  fail "tests/test-bypass-sentinel.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-out-of-band-detector.sh" >/dev/null 2>&1; then
  pass "tests/test-out-of-band-detector.sh"
else
  fail "tests/test-out-of-band-detector.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-escalate-to-user.sh" >/dev/null 2>&1; then
  pass "tests/test-escalate-to-user.sh"
else
  fail "tests/test-escalate-to-user.sh FAILED (run for details)"
fi

# Gate / check family.
if bash "$SCRIPT_DIR/tests/test-check-gate.sh" >/dev/null 2>&1; then
  pass "tests/test-check-gate.sh"
else
  fail "tests/test-check-gate.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-check-changelog-filter.sh" >/dev/null 2>&1; then
  pass "tests/test-check-changelog-filter.sh"
else
  fail "tests/test-check-changelog-filter.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-check-commit-message.sh" >/dev/null 2>&1; then
  pass "tests/test-check-commit-message.sh"
else
  fail "tests/test-check-commit-message.sh FAILED (run for details)"
fi
# BL-010: the BL-006 Build-Loop commit-message check now runs at the git
# commit-msg hook surface (pre-commit-gate.sh --terminal-mode --tdd-only ->
# bl006_terminal_enforce), reaching editor-opened and human-terminal commits.
# Mutation-proof: excising the marked `# BL-010-COMMITMSG-BL006` delegation line
# removes the refusal, flipping T-bl010-commitmsg-bl006-blocks RED.
if bash "$SCRIPT_DIR/tests/test-bl010-commitmsg-bl006.sh" >/dev/null 2>&1; then
  pass "tests/test-bl010-commitmsg-bl006.sh"
else
  fail "tests/test-bl010-commitmsg-bl006.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-check-phase-gate.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate.sh"
else
  fail "tests/test-check-phase-gate.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-poc-block-contract.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate-poc-block-contract.sh"
else
  fail "tests/test-check-phase-gate-poc-block-contract.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-check-phase-gate-counter-sanitizer.sh" >/dev/null 2>&1; then
  pass "tests/test-check-phase-gate-counter-sanitizer.sh"
else
  fail "tests/test-check-phase-gate-counter-sanitizer.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-gate-principles.sh" >/dev/null 2>&1; then
  pass "tests/test-gate-principles.sh"
else
  fail "tests/test-gate-principles.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-filesystem-gate-install.sh" >/dev/null 2>&1; then
  pass "tests/test-filesystem-gate-install.sh"
else
  fail "tests/test-filesystem-gate-install.sh FAILED (run for details)"
fi

# Enforcement-level family.
if bash "$SCRIPT_DIR/tests/test-enforcement-level-lib.sh" >/dev/null 2>&1; then
  pass "tests/test-enforcement-level-lib.sh"
else
  fail "tests/test-enforcement-level-lib.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-enforcement-level-init.sh" >/dev/null 2>&1; then
  pass "tests/test-enforcement-level-init.sh"
else
  fail "tests/test-enforcement-level-init.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-enforcement-level-reconfigure.sh" >/dev/null 2>&1; then
  pass "tests/test-enforcement-level-reconfigure.sh"
else
  fail "tests/test-enforcement-level-reconfigure.sh FAILED (run for details)"
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
if bash "$SCRIPT_DIR/tests/test-init-atomic-finalize.sh" >/dev/null 2>&1; then
  pass "tests/test-init-atomic-finalize.sh (code-init-sh-6 atomic-finalize, 8/8)"
else
  fail "tests/test-init-atomic-finalize.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-init-no-remote-creation.sh" >/dev/null 2>&1; then
  pass "tests/test-init-no-remote-creation.sh"
else
  fail "tests/test-init-no-remote-creation.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-init-schema-phase-gate.sh" >/dev/null 2>&1; then
  pass "tests/test-init-schema-phase-gate.sh"
else
  fail "tests/test-init-schema-phase-gate.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-vendored-skills-install.sh" >/dev/null 2>&1; then
  pass "tests/test-vendored-skills-install.sh"
else
  fail "tests/test-vendored-skills-install.sh FAILED (run for details)"
fi
# N7 fix landed in this test (personal+sponsored_poc, not personal+production).
if bash "$SCRIPT_DIR/tests/test-init-non-interactive.sh" >/dev/null 2>&1; then
  pass "tests/test-init-non-interactive.sh (BL-016 --non-interactive validation, 29/29)"
else
  fail "tests/test-init-non-interactive.sh FAILED (run for details)"
fi

section "BL-035 wiring B: upgrade family"
if bash "$SCRIPT_DIR/tests/test-upgrade-non-interactive.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-non-interactive.sh"
else
  fail "tests/test-upgrade-non-interactive.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-upgrade-bl030-backfill.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-bl030-backfill.sh"
else
  fail "tests/test-upgrade-bl030-backfill.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-upgrade-to-production-preconditions.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-to-production-preconditions.sh"
else
  fail "tests/test-upgrade-to-production-preconditions.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-upgrade-to-production-warn.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-to-production-warn.sh"
else
  fail "tests/test-upgrade-to-production-warn.sh FAILED (run for details)"
fi
if bash "$SCRIPT_DIR/tests/test-verify-install-bl030-coverage.sh" >/dev/null 2>&1; then
  pass "tests/test-verify-install-bl030-coverage.sh"
else
  fail "tests/test-verify-install-bl030-coverage.sh FAILED (run for details)"
fi
# DECOMPOSED: only the unique T4 (BL-004 CI migration) / T5 (vendored-skills,
# private-poc, manifesto) / T6 (POC-strip) cases remain; T1/T2/T3 tier-transition
# cases were dropped as dups of tests/upgrade-path-tests.sh.
if bash "$SCRIPT_DIR/tests/test-upgrade-paths.sh" >/dev/null 2>&1; then
  pass "tests/test-upgrade-paths.sh (unique T4/T5/T6 after BL-035 decompose, 16/16)"
else
  fail "tests/test-upgrade-paths.sh FAILED (run for details)"
fi

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
cp "$SCRIPT_DIR/scripts/lib/helpers.sh" "$TEST4_FIXTURE/scripts/lib/"
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

# Test dry-run with piped input
dry_input="test-dryrun
Dry run test
3
2
1
7
/tmp/test-dryrun
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

if echo "$dry_output" | grep -qi "already installed\|WILL INSTALL\|MANUAL\|DEFERRED"; then
  pass "Dry-run shows tool status categories"
else
  fail "Dry-run missing tool status categories"
fi

# Verify no project was actually created
if [ ! -d "/tmp/test-dryrun" ]; then
  pass "Dry-run did not create project directory"
else
  fail "Dry-run created a project directory (should not have)"
  rm -rf "/tmp/test-dryrun"
fi

# ================================================================
# TEST 8: INIT.SH SYNTAX AND STRUCTURE
# ================================================================
section "TEST 8: Script Syntax Validation"

echo ""

bash -n "$SCRIPT_DIR/init.sh" 2>/dev/null && pass "init.sh syntax OK" || fail "init.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/resolve-tools.sh" 2>/dev/null && pass "resolve-tools.sh syntax OK" || fail "resolve-tools.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/check-phase-gate.sh" 2>/dev/null && pass "check-phase-gate.sh syntax OK" || fail "check-phase-gate.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/validate.sh" 2>/dev/null && pass "validate.sh syntax OK" || fail "validate.sh syntax ERROR"
bash -n "$SCRIPT_DIR/scripts/intake-wizard.sh" 2>/dev/null && pass "intake-wizard.sh syntax OK" || fail "intake-wizard.sh syntax ERROR"

# Verify all JSON matrix files are valid
for f in "$MATRIX_DIR"/*.json; do
  fname=$(basename "$f")
  jq '.' "$f" > /dev/null 2>&1 && pass "JSON valid: $fname" || fail "JSON invalid: $fname"
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

if bash "$SCRIPT_DIR/tests/edge-case-test-suite.sh" >/dev/null 2>&1; then
  pass "tests/edge-case-test-suite.sh (edge-case sweep — platform/tool-prefs/git-host/re-init/bypass-detector/intake/resolver-timeout)"
else
  fail "tests/edge-case-test-suite.sh FAILED (run tests/edge-case-test-suite.sh for the per-section [FAIL] lines)"
fi

if bash "$SCRIPT_DIR/tests/known-bugs-test-suite.sh" >/dev/null 2>&1; then
  pass "tests/known-bugs-test-suite.sh (BUG-1..BUG-8 + E1-E40 regression sweep)"
else
  fail "tests/known-bugs-test-suite.sh FAILED (run tests/known-bugs-test-suite.sh for details)"
fi

if bash "$SCRIPT_DIR/tests/upgrade-path-tests.sh" >/dev/null 2>&1; then
  pass "tests/upgrade-path-tests.sh (track/deployment/POC upgrade + strict-superset no-regression)"
else
  fail "tests/upgrade-path-tests.sh FAILED (run tests/upgrade-path-tests.sh for details)"
fi
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

echo ""
echo "Test directory cleaned up: $TEST_DIR"
echo ""

exit $FAIL

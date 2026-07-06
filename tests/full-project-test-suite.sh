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
if [ "$SKIP_KNOWN_FAILING" = "1" ]; then
  warn "SKIP_KNOWN_FAILING=1 — skipping tests/test-verify-install-fix-functions.sh (known-RED, BL-037)"
else
  # Status: known-RED on main pending BL-037 (T6-T10 tightening) +
  # underlying fix_tool_install missing-function bug. Aggregator will
  # exit non-zero until BL-037 lands. Do NOT `|| true` this — that's
  # the vacuous-pass class BL-034 exists to surface. Karl opts in
  # via SKIP_KNOWN_FAILING=1 for local iteration.
  if bash "$SCRIPT_DIR/tests/test-verify-install-fix-functions.sh" >/dev/null 2>&1; then
    pass "tests/test-verify-install-fix-functions.sh"
  else
    fail "tests/test-verify-install-fix-functions.sh FAILED — known-RED on main, tracked by BL-037 (fix_tool_install missing + T6-T10 tightening). SKIP_KNOWN_FAILING=1 to bypass during local iteration."
  fi
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
if [ "$SKIP_KNOWN_FAILING" = "1" ]; then
  warn "SKIP_KNOWN_FAILING=1 — skipping tests/test-process-checklist-reset-phase1.sh (known-RED, BL-041)"
else
  # Status: known-RED on main pending BL-041 (framework-repo guard
  # layering) — T4/T5 invoke process-checklist.sh from inside the
  # framework checkout, hitting the guard. Aggregator will exit
  # non-zero until BL-041 lands or the test cd-s to a fixture
  # project dir first. SKIP_KNOWN_FAILING=1 to bypass locally.
  if bash "$SCRIPT_DIR/tests/test-process-checklist-reset-phase1.sh" >/dev/null 2>&1; then
    pass "tests/test-process-checklist-reset-phase1.sh"
  else
    fail "tests/test-process-checklist-reset-phase1.sh FAILED — known-RED on main, tracked by BL-041 (framework-repo guard). SKIP_KNOWN_FAILING=1 to bypass during local iteration."
  fi
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
section "Edge-cases aggregators (pre-init, scripts, upgrade-input)"
if [ "$SKIP_KNOWN_FAILING" = "1" ]; then
  warn "SKIP_KNOWN_FAILING=1 — skipping tests/edge-cases-pre-init.sh (known-RED, BL-040)"
else
  # Status: known-RED on main pending BL-040 (init.sh:2781 dry_run
  # summary). Do NOT `|| true` — apostrophe-handling regressions in
  # init.sh must surface. SKIP_KNOWN_FAILING=1 to bypass locally.
  if bash "$SCRIPT_DIR/tests/edge-cases-pre-init.sh" >/dev/null 2>&1; then
    pass "tests/edge-cases-pre-init.sh"
  else
    fail "tests/edge-cases-pre-init.sh FAILED — known-RED on main, tracked by BL-040 (E1, E4 apostrophe/dry-run name preservation). SKIP_KNOWN_FAILING=1 to bypass during local iteration."
  fi
fi
if [ "$SKIP_KNOWN_FAILING" = "1" ]; then
  warn "SKIP_KNOWN_FAILING=1 — skipping tests/edge-cases-scripts.sh (known-RED, BL-065 / BL-009 follow-up: E30 --platform other)"
else
  # Status: known-RED on main pending BL-065 (E30 --platform other
  # refs/template handling — BL-009 follow-up). BL-039 (E50) was
  # closed in the PR that landed this gate-narrowing — E50 + new
  # E50b now reflect the actual baseline §2.5 tier contract.
  # Do NOT `|| true`. SKIP_KNOWN_FAILING=1 to bypass locally.
  if bash "$SCRIPT_DIR/tests/edge-cases-scripts.sh" >/dev/null 2>&1; then
    pass "tests/edge-cases-scripts.sh"
  else
    fail "tests/edge-cases-scripts.sh FAILED — known-RED on main, tracked by BL-065 (E30 --platform other / BL-009 follow-up). SKIP_KNOWN_FAILING=1 to bypass during local iteration."
  fi
fi
if bash "$SCRIPT_DIR/tests/edge-cases-upgrade-input.sh" >/dev/null 2>&1; then
  pass "tests/edge-cases-upgrade-input.sh"
else
  fail "tests/edge-cases-upgrade-input.sh FAILED (run for details)"
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
if [ "$SKIP_KNOWN_FAILING" = "1" ]; then
  warn "SKIP_KNOWN_FAILING=1 — skipping tests/host-drivers/run-all.sh (e2e-init-* trio known-RED)"
else
  # Status: 6 of 9 children GREEN; 3 e2e-init.*.test.sh children
  # RED on main (existing defect, not introduced by BL-034). Do
  # NOT `|| true` — the per-host unit tests inside the aggregator
  # MUST be allowed to fail loudly when they regress.
  if bash "$SCRIPT_DIR/tests/host-drivers/run-all.sh" >/dev/null 2>&1; then
    pass "tests/host-drivers/run-all.sh (9/9 children)"
  else
    fail "tests/host-drivers/run-all.sh FAILED — known-RED: e2e-init / e2e-init-gitlab / e2e-init-bitbucket. Unit-test children (github/gitlab/regressions/mock-cli) should still PASS. SKIP_KNOWN_FAILING=1 to bypass."
  fi
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

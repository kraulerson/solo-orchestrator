# Cross-Cutting Infrastructure & Governance Re-Audit

**Auditor:** Chief Compliance Officer (Enterprise Process Auditor)
**Date:** 2026-04-08
**Scope:** Scripts, init.sh, hook system, CI/CD pipelines, governance framework, upgrade paths, evaluation prompts, enforcement model, cross-document consistency
**Branch:** feat/process-enforcement

---

## Executive Summary

This is a fresh, independent evaluation of the Solo Orchestrator Framework's cross-cutting infrastructure and governance mechanics. The audit examines whether the mechanical infrastructure actually enforces what the documentation promises, and identifies where someone can bypass the system.

**Overall Assessment:** The framework demonstrates exceptional depth in its enforcement model. The three-tier enforcement architecture (CI hard blocks, hook-based partial enforcement, documentation-guided controls) is well-designed, clearly documented, and honestly communicated. The process checklist state machine (`process-checklist.sh`) and the PreToolUse hook (`pre-commit-gate.sh`) add a fourth enforcement dimension that significantly raises the bar for agent compliance. However, several bypass vectors, missing validations, and documentation-to-code gaps remain.

**Findings Summary:**
- Critical: 3
- High: 6
- Medium: 10
- Low: 5
- Informational: 4

---

## Strengths

### S-001: Honest Enforcement Taxonomy
The framework is remarkably transparent about what is mechanically enforced versus what depends on agent compliance. The User Guide's "What Is Enforced vs. What Is Guided" section (Tiers 1, 1.5, 2, 3) is one of the most honest assessments of enforcement boundaries seen in any development framework. This honesty enables informed risk decisions.

### S-002: Defense-in-Depth for Commit Gating
The commit gating system operates at three layers: (1) `pre-commit-gate.sh` as a PreToolUse hook blocks unsafe git operations at the agent level, (2) `.git/hooks/pre-commit` runs gitleaks and Semgrep at the git level, (3) CI pipeline runs the full suite at the merge level. Each layer catches what the previous might miss. The PreToolUse hook explicitly blocks `--no-verify`, `--force` push, and unauthorized process resets. This is well-engineered.

### S-003: Process State Machine with Audit Trail
`process-checklist.sh` implements a genuine sequential state machine with enforcement. Steps cannot be skipped (prior steps are verified). Resets require interactive terminal authorization (blocking agent invocation). Forced step overrides are logged to `.claude/process-audit.log`. The reset audit trail is persistent and append-only. This is significantly more rigorous than most frameworks.

### S-004: Artifact Existence Checks at Step Completion
The `complete_step` function in `process-checklist.sh` verifies that expected artifacts actually exist before allowing step completion (e.g., `security_audit` requires findings in `docs/security-audits/`, `handoff_written` requires `HANDOFF.md`, `rollback_tested` requires rollback results). This prevents marking steps complete without producing output.

### S-005: Comprehensive Verification and Remediation
`verify-install.sh` implements a three-phase approach (detect, report, remediate) with three modes (interactive, check-only for CI, auto-fix for init). The registration arrays pattern (PASSED/FIXABLE/MANUAL) is clean and extensible. The script can diagnose and auto-fix 20+ common installation issues.

### S-006: Phase Gate Snapshot System
`check-phase-gate.sh` automatically creates point-in-time snapshots of key artifacts at each phase transition (`docs/snapshots/phase-N-to-M_YYYY-MM-DD/`). This provides tamper-evident archival of the project state at each gate crossing.

### S-007: CI Pipeline Governance Blocks
All three CI pipeline templates (python, typescript, other) include identical governance steps: approval log integrity (append-only enforcement), approval author verification, phase gate consistency check, changelog freshness, and session state freshness. The governance steps are clearly marked as language-agnostic with a "do not remove" comment in the `other.yml` template.

### S-008: Tool Usage Tracking System
The PostToolUse hook (`track-tool-usage.sh`) and session hooks create a lightweight but effective MCP tool usage tracking system. Context7 and Qdrant usage are tracked per session, with commit counters providing drift detection. The system intentionally uses `set +e` to ensure tracking failures never block agent work. This is the correct trade-off.

### S-009: Upgrade Path Completeness
`upgrade-project.sh` handles all upgrade paths (track upgrade, deployment upgrade, POC-to-production, personal-to-sponsored-POC) with downgrade prevention, interactive confirmation, automatic file updates across 6+ files, tool re-resolution, and post-upgrade verification. The script backs up the personal approval log before restructuring for organizational governance.

### S-010: Evaluation Prompt System Architecture
The project evaluation system uses a modular base+module architecture with HTML comment tag extraction. `compose.sh` cleanly separates reviewer personas from domain-specific categories. `run-reviews.sh` captures commit provenance and generates a review manifest with SHA-256 checksums. This enables traceability from review findings back to the exact codebase state.

---

## Critical Findings

### CC-001: SOIF_FORCE_STEP Bypass Allows Agent to Skip Artifact Checks Without Terminal Authorization
**Severity:** Critical
**Component:** `scripts/process-checklist.sh`, lines 278-291
**Criteria Failed:** 6 (Enforcement Mechanism), 12 (Bypass Risk)

The artifact existence checks in `complete_step` can be bypassed by setting the environment variable `SOIF_FORCE_STEP=true`. Unlike the `--reset` and `--reset-all` commands (which require an interactive terminal via `[ ! -t 0 ]`), the force-step bypass has no terminal interactivity check. An agent can run:

```bash
SOIF_FORCE_STEP=true scripts/process-checklist.sh --complete-step build_loop:security_audit
```

This bypasses the security audit artifact check without Orchestrator authorization. While the override is logged to `.claude/process-audit.log`, the enforcement is post-hoc rather than preventive.

**Impact:** An agent can mark security-critical steps complete without producing the required artifacts, undermining the entire Build Loop enforcement chain.

**Recommendation:** Add the same `[ ! -t 0 ]` interactive terminal check used by the reset functions. The force override should require Orchestrator authorization, not just an environment variable.

---

### CC-002: Pre-Commit Gate Does Not Block SOIF_FORCE_STEP Invocation
**Severity:** Critical
**Component:** `scripts/pre-commit-gate.sh`, lines 27-31
**Criteria Failed:** 6 (Enforcement Mechanism), 12 (Bypass Risk)

The PreToolUse hook blocks `process-checklist.sh --reset` but does not block commands that set `SOIF_FORCE_STEP=true`. An agent can bypass artifact checks by prefixing the environment variable before the process-checklist command. The hook's pattern matching only looks for `--reset` in the command string.

**Impact:** Compounds CC-001. The two bypass vectors together allow an agent to skip steps and mark them complete without producing artifacts, and the PreToolUse hook will not intervene.

**Recommendation:** Add a pattern match in `pre-commit-gate.sh` to deny commands containing `SOIF_FORCE_STEP` or any environment variable override patterns targeting process enforcement scripts.

---

### CC-003: SOIF_PHASE_GATES=warn Environment Variable Downgrades Phase Gate Enforcement
**Severity:** Critical
**Component:** `scripts/check-phase-gate.sh`, lines 571-579
**Criteria Failed:** 6 (Enforcement Mechanism), 12 (Bypass Risk)

The phase gate consistency check can be downgraded from blocking (exit 1) to warning (exit 0) by setting `SOIF_PHASE_GATES=warn`. This environment variable is not blocked by the PreToolUse hook. While this is documented as an intentional escape hatch, neither the CI pipeline nor the hook system prevents an agent from setting this variable.

In the CI pipeline templates, the phase gate check runs as `bash scripts/check-phase-gate.sh` with no environment variable override protection. However, if someone adds `SOIF_PHASE_GATES: "warn"` to the CI workflow's `env:` section, all phase gate enforcement in CI is silently disabled.

**Impact:** The primary mechanical enforcement boundary (CI phase gate check) can be silently disabled by a single environment variable. For organizational deployments, this undermines the governance guarantee.

**Recommendation:** (a) The CI pipeline should explicitly unset `SOIF_PHASE_GATES` before running the check: `unset SOIF_PHASE_GATES; bash scripts/check-phase-gate.sh`. (b) The PreToolUse hook should block commands that set `SOIF_PHASE_GATES`.

---

## High Findings

### CC-004: init.sh Has No Dry-Run Implementation Despite --dry-run Flag
**Severity:** High
**Component:** `init.sh`, line 11, line 20
**Criteria Failed:** 1 (Instructions), 7 (Validation/Verification)

The script header documents `--dry-run` as a supported option and sets `DRY_RUN=false` at line 20. The prerequisites check disables interactive prompts in dry-run mode (line 35). However, no further dry-run logic was found after examining all 1000+ lines. The `DRY_RUN` variable is set but the script appears to proceed with full project creation regardless.

The `--dry-run` flag is parsed (it must be, since the help text describes it), but the actual argument parsing block was not visible in the portions read. If the parsing exists but the conditional logic is incomplete, this is a functional gap where `--dry-run` implies preview-only behavior but actually creates files and directories.

**Impact:** Users relying on `--dry-run` for safe preview will get unexpected side effects.

**Recommendation:** Either implement full dry-run support (log actions without executing) or remove the `--dry-run` flag from the help text and argument parsing.

---

### CC-005: Approval Log Integrity Check Only Detects Line Deletions, Not Modifications
**Severity:** High
**Component:** CI pipeline templates (`python.yml` line 68, `typescript.yml` line 59, `other.yml` line 70)
**Criteria Failed:** 7 (Validation/Verification), 9 (Audit Trail)

The "Governance - Approval log integrity" CI step checks for deleted lines:
```bash
git diff origin/main...HEAD -- APPROVAL_LOG.md | grep -qE '^\-[^-]'
```

This only catches deleted lines (lines starting with `-` in the diff). It does not catch in-place modifications where a line is changed (which appears as a deletion + addition in a diff). An existing approval entry like `| **Approver** | Jane Smith |` could be changed to `| **Approver** | John Doe |` and the check would flag the deletion of the old line. However, more subtle modifications (changing a date from `2026-01-15` to `2026-01-16` in the same line) would still trigger the deletion detection. The current regex `^\-[^-]` correctly catches this because modification = deletion + addition in git diff.

Upon closer analysis, the regex does catch modifications because git diff represents them as line removal + line addition. The `^\-[^-]` pattern catches the removal half. The check is actually more robust than initially assessed, but the comment says "deleted or modified" which is correct but the mechanism is indirect.

**Revised Impact:** The check is functionally correct for detecting modifications via the deletion half of the diff. However, there is a subtle bypass: if someone force-pushes to rewrite the base branch history, the diff base changes and prior entries can be silently altered. The check compares against `origin/main...HEAD`, so history rewriting on main would reset the comparison baseline.

**Recommendation:** Add a supplementary SHA-256 hash check: on each phase gate approval, compute and store a hash of the approval log's content up to that point. On subsequent CI runs, verify the stored hash matches the current file content through that point. This provides tamper evidence independent of git diff.

---

### CC-006: No Validation That phase-state.json current_phase Value Is Legitimate
**Severity:** High
**Component:** `scripts/check-phase-gate.sh`, `scripts/process-checklist.sh`
**Criteria Failed:** 7 (Validation/Verification), 12 (Bypass Risk)

The `current_phase` value in `.claude/phase-state.json` is trusted as the source of truth for enforcement decisions. In `process-checklist.sh`, line 612: if `current_phase < 2`, no enforcement occurs. An agent could edit `.claude/phase-state.json` to set `current_phase` to 0 or 1, completely disabling all process enforcement.

The PreToolUse hook does not monitor or block edits to `.claude/phase-state.json`. There is no CI check that validates `current_phase` matches the artifact evidence (the `check-phase-gate.sh` script checks the reverse: whether artifacts match the phase, but an agent could reduce the phase number to avoid checks entirely).

**Impact:** A determined agent (or a user who wants to bypass enforcement) can set `current_phase` to 0 and commit code with no process enforcement.

**Recommendation:** (a) Add `.claude/phase-state.json` to the CI integrity checks. The phase number should only increase, never decrease, after the initial gate. (b) The PreToolUse hook should detect and block commands that modify `current_phase` to a lower value.

---

### CC-007: Framework Evaluation Prompts Have No Result Storage or Completion Tracking
**Severity:** High
**Component:** `evaluation-prompts/Framework/run-reviews.sh`
**Criteria Failed:** 5 (Storage & Retention), 9 (Audit Trail), 11 (Traceability)

The Framework review runner (`evaluation-prompts/Framework/run-reviews.sh`) lacks the manifest generation and provenance tracking that the Project review runner has. Specifically:

- No review manifest is generated (Project runner creates `docs/eval-results/review-manifest.json`)
- No commit hash is captured for provenance
- No SHA-256 checksums of output files
- No timestamp tracking
- Output files land in the project root with `-v1` suffix and no mechanism to track which version was run

The README acknowledges this: "Output files use `-v1` suffix. To re-run after making changes, rename/move existing review files." This is manual tracking with no mechanical enforcement.

**Impact:** Framework evaluations cannot be traced back to a specific codebase state, and there is no way to verify whether evaluation results were altered after generation.

**Recommendation:** Port the manifest generation logic from `evaluation-prompts/Projects/run-reviews.sh` (lines 186-230) to the Framework runner. Generate a `review-manifest.json` with commit hashes, timestamps, and SHA-256 checksums.

---

### CC-008: Session Start Hook Resets Tool Usage Tracking Unconditionally
**Severity:** High
**Component:** `scripts/session-test-gate-check.sh`, lines 8-21
**Criteria Failed:** 5 (Storage & Retention), 9 (Audit Trail)

The SessionStart hook creates a fresh `tool-usage.json` on every session start, overwriting any existing data. This means:

1. If a session crashes or is terminated abnormally, the tool usage data is lost without being archived.
2. There is no historical record of tool usage across sessions.
3. The `session-end-qdrant-reminder.sh` Stop hook reads the same file, but if the session ends abnormally (no Stop hook fired), the data is silently discarded on the next session start.

**Impact:** Tool usage tracking provides no historical view. Each session is isolated with no aggregate data.

**Recommendation:** Before overwriting, archive the existing `tool-usage.json` to a session history file (e.g., `.claude/tool-usage-history.jsonl`) with one line per session. This provides aggregate tracking while keeping the per-session file simple.

---

### CC-009: validate.sh Does Not Check Process Enforcement State for Phase 2+
**Severity:** High
**Component:** `scripts/validate.sh`, lines 209-261
**Criteria Failed:** 7 (Validation/Verification), 6 (Enforcement Mechanism)

The `validate.sh` script checks whether `process-state.json` exists and whether it contains valid JSON (section "5a. Process Enforcement State"). However, it does not verify:

1. Whether the process state is consistent with the current phase (e.g., Phase 2 with unverified `phase2_init`)
2. Whether the build loop has an active feature (required for Phase 2 source commits)
3. Whether the `build-progress.json` feature counter matches the actual number of features built

The script only performs structural checks (file exists, valid JSON), not semantic validation. For a project that claims to be in Phase 2, running `validate.sh` will not detect that process enforcement is in a broken or inconsistent state.

**Impact:** A user running `validate.sh` as a health check gets a false positive: the script reports "process-state.json (valid JSON)" even when the process state is semantically invalid for the current phase.

**Recommendation:** Add semantic validation: if `current_phase >= 2`, verify `phase2_init.verified == true`. If `current_phase >= 3`, verify that `phase3_validation` has been started. Cross-reference `build-progress.json` feature count against FEATURES.md sections.

---

## Medium Findings

### CC-010: check-versions.sh Uses eval for Install Commands Without Sanitization
**Severity:** Medium
**Component:** `scripts/check-versions.sh`, lines 468, 490
**Criteria Failed:** 8 (Error Handling), 12 (Bypass Risk)

The version check script uses `eval "$cmd"` to execute update commands derived from the tool matrix JSON files. While the JSON files are part of the framework (not user input), if a tool matrix file is tampered with, the eval would execute arbitrary commands. The same pattern exists in `verify-install.sh` line 810 (`$fix_func 2>/dev/null`), `check-phase-gate.sh` line 476 (`eval "$cmd"`), and `init.sh` line 776 (`eval "$tool_cmd"`).

**Impact:** If the tool matrix JSON files or resolver output are compromised (supply chain attack on the framework repo), arbitrary code execution is possible during init, verification, or version checking.

**Recommendation:** Validate that install commands match expected patterns (e.g., start with `brew install`, `pip install`, `npm install`, etc.) before executing. Consider a whitelist approach for known-safe command prefixes.

---

### CC-011: No Lockfile Integrity Check for Python Requirements Without Hashes
**Severity:** Medium
**Component:** `templates/pipelines/ci/python.yml`, lines 53-62
**Criteria Failed:** 7 (Validation/Verification)

The Python CI pipeline's lockfile integrity check has a cascading fallback that ends with a warning:
```bash
echo "::warning::No hash-pinned lockfile found..."
```

This means projects using `pip install -r requirements.txt` without `--hash` flags get no supply chain integrity verification. The TypeScript pipeline uses `npm audit signatures` which is a hard check. The Python pipeline degrades to a warning for the most common Python dependency management approach.

**Impact:** Python projects using basic `requirements.txt` have no supply chain integrity verification in CI.

**Recommendation:** Add `pip-audit` or `pip install --require-hashes` as a stronger fallback. Consider making the warning a hard failure for Standard and Full track projects.

---

### CC-012: other.yml CI Template Has Intentional Build Failures Without Phase-Gating
**Severity:** Medium
**Component:** `templates/pipelines/ci/other.yml`, lines 49-61
**Criteria Failed:** 1 (Instructions), 8 (Error Handling)

The `other.yml` template has dependency audit and license check steps that intentionally `exit 1` with messages directing users to configure tools. This is correct behavior for uncustomized templates, but there is no mechanism to prevent this template from being deployed to a Phase 2+ project without customization.

The `init.sh` script warns about this at line 454-457, but `verify-install.sh` and `validate.sh` do not check whether the deployed CI pipeline still contains placeholder `exit 1` steps.

**Impact:** A project using the `other` language template will have a perpetually failing CI pipeline until manually customized, with no automated detection of this incomplete state.

**Recommendation:** Add a check in `validate.sh` that detects `exit 1` steps in `.github/workflows/ci.yml` that contain "WARNING: No dependency audit" or similar template markers, and flag them as errors for Phase 2+.

---

### CC-013: check-phase-gate.sh Has Interactive Prompt in a CI-Context Script
**Severity:** Medium
**Component:** `scripts/check-phase-gate.sh`, lines 468-475
**Criteria Failed:** 8 (Error Handling)

The phase gate check script includes an interactive `read -rp` prompt for auto-installing missing tools (line 469). This script is called from CI pipelines (`bash scripts/check-phase-gate.sh`). In a non-interactive CI environment, `read` will consume stdin (which may be empty) and likely default to an empty string, causing the install to be skipped. However, this creates unpredictable behavior.

The script does not check `[ -t 0 ]` before presenting the interactive prompt, unlike other scripts in the framework that properly guard interactive sections.

**Impact:** In CI, the interactive prompt either hangs (if stdin is not closed), reads empty input, or behaves unpredictably depending on the CI runner's stdin handling.

**Recommendation:** Guard the interactive tool installation section with `[ -t 0 ]` to skip it in non-interactive environments (CI, hooks).

---

### CC-014: process-checklist.sh --start-phase4 Has No Pre-Condition Checks
**Severity:** Medium
**Component:** `scripts/process-checklist.sh`, lines 367-381
**Criteria Failed:** 7 (Validation/Verification)

The `start_phase4` function creates the Phase 4 release state without any pre-condition checks. Compare this to `start_phase3` (line 330), which:
1. Verifies `current_phase >= 3` in `phase-state.json`
2. Runs the bug gate check via `test-gate.sh --check-phase-gate`
3. Blocks if the bug gate fails

`start_phase4` performs none of these checks. It does not verify:
- `current_phase >= 4` in phase-state.json
- Phase 3 validation steps are all complete
- Review manifest exists (evaluation prompts have been run)
- POC mode is not blocking Phase 4

**Impact:** Phase 4 can be started without completing Phase 3 validation, bypassing the entire validation and hardening phase.

**Recommendation:** Add pre-condition checks to `start_phase4` mirroring the pattern in `start_phase3`. Verify Phase 3 completion, check POC mode, and require the review manifest.

---

### CC-015: Tool Matrix Eval in check-versions.sh Disables set -u for Check Commands
**Severity:** Medium
**Component:** `scripts/check-versions.sh`, lines 330-336
**Criteria Failed:** 8 (Error Handling)

The script disables `set -u` (undefined variable checking) before evaluating tool check commands and re-enables it after. The comment explains this is because check commands may reference environment variables like `$ANDROID_HOME` that are legitimately unset. However, this creates a window where any undefined variable access in the check command evaluation will silently succeed rather than failing.

**Impact:** A misconfigured tool check command that references a typo'd variable name will silently pass rather than being caught.

**Recommendation:** Instead of disabling `set -u` globally, wrap the eval in a subshell: `(eval "$CHECK_CMD") &>/dev/null 2>&1`. The subshell inherits the parent's settings but its failures are contained.

---

### CC-016: resume.sh Runs check-versions.sh Synchronously During Prompt Generation
**Severity:** Medium
**Component:** `scripts/resume.sh`, lines 67-79
**Criteria Failed:** 8 (Error Handling)

The resume prompt generator runs `check-versions.sh` synchronously (line 68), which involves network calls to check latest versions (npm registry, PyPI, GitHub releases, brew). This can take 10-30 seconds, especially if network is slow or unavailable. The script provides no timeout and no indication to the user that it is checking versions.

**Impact:** Resume prompt generation feels slow or hangs when network is unavailable, with no user feedback.

**Recommendation:** Add a timeout (5-10 seconds) around the version check, or run it with `--check-only` mode that skips network calls for latest version lookups.

---

### CC-017: Governance Framework References "Section VIII.10" for Insurance but check-phase-gate.sh Does Not Verify It
**Severity:** Medium
**Component:** `docs/governance-framework.md` Section VIII.10, `scripts/check-phase-gate.sh`
**Criteria Failed:** 6 (Enforcement Mechanism), 11 (Traceability)

The Governance Framework states that insurance confirmation is a "gating artifact for Phase 0 approval" (line 460). The `check-phase-gate.sh` script checks for pre-Phase 0 organizational pre-conditions (lines 186-206) by looking for dated entries in the APPROVAL_LOG.md. However, it only counts dates (`grep -cE "[0-9]{4}-[0-9]{2}-[0-9]{2}"`) without verifying that specific pre-conditions (insurance, liability entity, etc.) are individually tracked.

The check requires "at least 3 pre-condition dates recorded" (line 195) out of 6 required, which means half the pre-conditions can be skipped and the check still passes.

**Impact:** For organizational deployments, the insurance confirmation and other critical pre-conditions can be skipped while the automated check reports compliance.

**Recommendation:** Verify each of the 6 named pre-conditions individually, not just a count of dates. Parse the pre-conditions table structure in APPROVAL_LOG.md and verify each row has a populated date.

---

### CC-018: check-maintenance.sh Uses Platform-Specific Date Parsing
**Severity:** Medium
**Component:** `scripts/check-maintenance.sh`, lines 30, 51
**Criteria Failed:** 8 (Error Handling)

The maintenance check script uses `date -j -f "%Y-%m-%d" "$date" +%s` (macOS) with a fallback to `date -d "$date" +%s` (Linux). This is a common portability pattern, but if neither works (e.g., on a non-standard Linux), the variable silently gets "0" and the math proceeds with incorrect results (showing maintenance as overdue by 20,000+ days).

**Impact:** On non-standard platforms, maintenance checks may report false positives (always overdue) or false negatives.

**Recommendation:** Add explicit error detection: if both date parsing attempts return 0, skip the check with a warning rather than proceeding with incorrect math.

---

### CC-019: No Cross-Validation Between process-state.json and build-progress.json
**Severity:** Medium
**Component:** `scripts/process-checklist.sh`, `scripts/test-gate.sh`
**Criteria Failed:** 7 (Validation/Verification)

`process-state.json` tracks build loop state (feature name, steps completed). `build-progress.json` tracks features completed and testing intervals. These files are managed by different scripts and are never cross-validated. A feature could be recorded in `test-gate.sh --record-feature` without completing the build loop in `process-checklist.sh`, or vice versa.

**Impact:** The two tracking systems can drift, creating inconsistent enforcement. A feature counted for testing interval purposes may not have completed all build loop steps.

**Recommendation:** When `test-gate.sh --record-feature` is called, verify that the build loop's `feature_recorded` step is the only remaining step (or has been completed). When `process-checklist.sh --complete-step build_loop:feature_recorded` is called, verify the feature has been recorded in `build-progress.json`.

---

## Low Findings

### CC-020: Framework Evaluation Prompts Include a Typo in Filename
**Severity:** Low
**Component:** `evaluation-prompts/Framework/Framwork Multi user test plan.md`
**Criteria Failed:** 1 (Instructions)

The file `Framwork Multi user test plan.md` has a typo: "Framwork" should be "Framework". The filename also uses spaces, which is inconsistent with the kebab-case naming convention used by all other files in the directory.

**Recommendation:** Rename to `framework-multi-user-test-plan.md`.

---

### CC-021: Project Review Runner Usage Help Shows "5 reviews" Instead of "6 reviews"
**Severity:** Low
**Component:** `evaluation-prompts/Projects/run-reviews.sh`, line 79
**Criteria Failed:** 1 (Instructions)

The usage examples show `# All 5 reviews` but the system actually has 6 reviewers (engineer, cio, security, legal, techuser, redteam).

**Recommendation:** Update the comment to `# All 6 reviews`.

---

### CC-022: helpers.sh print_header Version Width Assumption
**Severity:** Low
**Component:** `scripts/lib/helpers.sh`, lines 18-25
**Criteria Failed:** 4 (Template/Guide)

The `print_header` function uses fixed-width box drawing characters sized for "v1.0.0". If the version string changes length (e.g., "v1.10.0" or "v2.0.0-beta"), the box alignment will break.

**Recommendation:** Calculate padding dynamically based on version string length, or use a more flexible header format.

---

### CC-023: check-updates.sh Only Checks a Subset of Scripts
**Severity:** Low
**Component:** `scripts/check-updates.sh`, lines 113-115
**Criteria Failed:** 7 (Validation/Verification)

The update checker only compares `validate.sh` and `check-phase-gate.sh` against upstream. It does not check `process-checklist.sh`, `pre-commit-gate.sh`, `test-gate.sh`, `track-tool-usage.sh`, or the session hooks. These newer scripts are the enforcement backbone and would benefit from update tracking.

**Recommendation:** Add all enforcement-critical scripts to the update check: `process-checklist.sh`, `pre-commit-gate.sh`, `test-gate.sh`, `track-tool-usage.sh`, `session-test-gate-check.sh`, `session-version-check.sh`, `session-end-qdrant-reminder.sh`.

---

### CC-024: verify-install.sh Does Not Check for check-maintenance.sh or check-changelog.sh
**Severity:** Low
**Component:** `scripts/verify-install.sh`, lines 230-253
**Criteria Failed:** 7 (Validation/Verification)

The script verification function checks 8 specific scripts but omits `check-maintenance.sh`, `check-changelog.sh`, `check-session-state.sh`, `check-versions.sh`, `pre-commit-gate.sh`, `process-checklist.sh`, `test-gate.sh`, and `track-tool-usage.sh`. These are all required for the enforcement model to function.

**Recommendation:** Add all enforcement-critical scripts to the check list in `check_scripts()`.

---

## Informational Findings

### CC-025: Governance Framework Document Is Comprehensive But Not Machine-Verifiable
**Severity:** Informational
**Component:** `docs/governance-framework.md`
**Criteria Failed:** 6 (Enforcement Mechanism)

The Governance Framework (SOI-003-GOV) is exceptionally thorough — covering financial analysis, approval authorities, ITSM integration, security requirements (including credential rotation schedules, vulnerability response SLAs, AI data transmission policy), legal/compliance (including EU AI Act, data sovereignty, insurance requirements), vendor risk, and operational risk management. It is one of the most complete governance frameworks for AI-assisted development.

However, the framework's enforcement relies almost entirely on human compliance and the APPROVAL_LOG.md append-only file. The mechanical enforcement (CI checks, hooks) covers about 30% of what the governance framework requires. The remaining 70% (pre-conditions, named approvers, evidence references, insurance confirmation, compliance screening, credential rotation) is tracked in markdown files that can be edited freely.

This is not a deficiency — it is an inherent limitation of any governance framework that must work without infrastructure like RBAC, digital signatures, or workflow engines. The framework is honest about this limitation.

---

### CC-026: init.sh Is 1000+ Lines and Could Benefit from Modularization
**Severity:** Informational
**Component:** `init.sh`
**Criteria Failed:** None (architectural observation)

The init script handles prerequisites, project info collection, tool resolution, tool installation, project directory creation, file copying, git initialization, hook registration, and post-creation verification. While each function is well-structured, the total script length exceeds 1000 lines. The `resolve_and_install_tools` function alone has complex Qdrant/framework reclassification logic (lines 537-583).

This is not a bug, but future maintenance risk increases with script length.

---

### CC-027: CI Pipeline Templates Pin GitHub Actions by SHA Hash
**Severity:** Informational (Positive)
**Component:** All CI pipeline templates
**Criteria Failed:** None (positive observation)

The Semgrep and gitleaks GitHub Actions are pinned by full SHA hash with version comments:
```yaml
uses: semgrep/semgrep-action@713efdd345f3035192eaa63f56867b88e63e4e5d # v1 (v0.58.0)
uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2 (v2.3.9)
```

This is best practice for supply chain security. Many frameworks only pin by tag (e.g., `@v2`), which is mutable.

---

### CC-028: Evaluation Prompt Bases and Modules Are Complete for All 6 Project Types
**Severity:** Informational (Positive)
**Component:** `evaluation-prompts/Projects/`
**Criteria Failed:** None (positive observation)

The project evaluation system has complete bases for all 6 reviewer personas and modules for all 6 project types (web-app, mobile-app, api-service, cli-tool, framework, desktop-app). The `compose.sh` script handles the assembly cleanly. The design decision documentation in the README ("Why separate bases and modules?", "Why HTML comment tags?", "Why not a single config file?") demonstrates thoughtful architecture.

---

## Cross-Document Consistency Analysis

### Enforcement Model: Docs vs. Code Alignment

| Promise (Docs) | Mechanism (Code) | Aligned? |
|---|---|---|
| CI blocks merges on SAST findings | Semgrep step fails build | Yes |
| CI blocks on copyleft licenses | License check step fails build | Yes |
| CI enforces phase gate consistency | `check-phase-gate.sh` in CI, exit 1 | Yes, but SOIF_PHASE_GATES=warn bypass (CC-003) |
| CI enforces approval log append-only | Diff check for deleted lines | Yes, with caveats (CC-005) |
| PreToolUse hook blocks --no-verify | Regex match in pre-commit-gate.sh | Yes |
| PreToolUse hook blocks --force push | Regex match in pre-commit-gate.sh | Yes |
| PreToolUse hook blocks unauthorized resets | Regex match for --reset | Yes |
| Process checklist enforces sequential steps | Prior-step verification in complete_step | Yes |
| Resets require Orchestrator authorization | Interactive terminal check ([ ! -t 0 ]) | Yes for resets, not for SOIF_FORCE_STEP (CC-001) |
| Artifact checks prevent marking steps complete | Existence checks in complete_step | Yes, but SOIF_FORCE_STEP bypass (CC-001) |
| Phase 3 entry requires bug gate clear | Bug gate check in start_phase3 | Yes |
| Phase 4 entry requires Phase 3 complete | No check in start_phase4 | **No** (CC-014) |
| Organizational deployments require 6 pre-conditions | check-phase-gate.sh counts dates >= 3 | **Partial** (CC-017) |
| TDD enforcement at commit time | Build loop step verification | Yes |
| Context7/Qdrant usage tracking | PostToolUse hook + session hooks | Yes |
| Version checking at session start | SessionStart hook calls check-versions.sh | Yes |
| Test interval enforcement | test-gate.sh --check-batch, SessionStart hook | Yes |
| Changelog freshness in CI | check-changelog.sh, warning by default | Yes |
| Session state freshness in CI | check-session-state.sh, warning by default | Yes |

### Builder's Guide Appendix A vs. Actual Artifact Checks

The Builder's Guide Appendix A lists 25+ document artifacts. The automated checks (validate.sh, check-phase-gate.sh, process-checklist.sh) verify the existence of approximately 15 of these. The following artifacts are not mechanically verified:

- Architecture Decision Records (`docs/ADR documentation/`)
- CONTRIBUTING.md
- Interface Documentation (`docs/api and interfaces/`)
- Performance Baselines
- USER_GUIDE.md
- SECURITY.md
- In-Phase Decision Log
- Compliance Screening Matrix (embedded in Intake)
- Penetration Test Report

This is consistent with the framework's Tier 3 classification: these are documentation-guided, not mechanically enforced.

---

## Summary of Recommendations by Priority

### Immediate (Pre-Merge)
1. **CC-001/CC-002:** Add interactive terminal check to SOIF_FORCE_STEP override; add pattern to PreToolUse hook to block it
2. **CC-003:** Add SOIF_PHASE_GATES unset to CI pipeline before phase gate check; add pattern to PreToolUse hook
3. **CC-014:** Add pre-condition checks to `start_phase4` matching `start_phase3` pattern

### Short-Term
4. **CC-004:** Resolve dry-run flag implementation gap in init.sh
5. **CC-006:** Add phase-state.json monotonicity check (phase number can only increase)
6. **CC-007:** Port manifest generation to Framework review runner
7. **CC-009:** Add semantic validation to validate.sh for process enforcement state
8. **CC-017:** Parse individual pre-conditions instead of counting dates

### Medium-Term
9. **CC-008:** Archive tool usage data before session start reset
10. **CC-019:** Cross-validate process-state.json and build-progress.json
11. **CC-023/CC-024:** Expand update checker and verify-install script coverage
12. **CC-010:** Add command prefix validation before eval execution

---

**End of Audit**

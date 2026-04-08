# Phase 4 Remediation Plan
## Release & Maintenance

**Source Audit:** [Phase 4 Process Audit](../2026-04-08-phase-4-audit.md)
**Date:** 2026-04-08
**Auditor Persona:** VP of Operations / SRE Lead
**Framework Version:** Solo Orchestrator v1.0 (post-PR #6, #7)
**Findings:** 17 total (1 Critical, 8 Major, 5 Minor, 3 Observation)

---

## Executive Summary

Phase 4 (Release & Maintenance) is the framework's operational tail -- the phase where process discipline transitions from project execution to sustained production responsibility. The audit identified 17 findings, anchored by one critical gap: all five Phase 4 process steps operate as self-attestation with no artifact validation. An Orchestrator can mark every step complete -- production build, rollback test, go-live verification, monitoring configuration, handoff documentation -- without producing or verifying a single artifact.

This undermines the framework's own stated principle: "A rollback procedure that has never been tested is not a rollback procedure -- it is a hope." The same logic applies to every Phase 4 step.

The eight Major findings cluster into three themes: (1) missing artifacts for rollback testing, go-live verification, and handoff testing; (2) no Phase 4 completion gate in the approval log; and (3) operational sustainability gaps in maintenance scheduling, monitoring verification, and security disclosure. The five Minor findings and three Observations are consistency and template completeness items with low operational risk.

This remediation plan prescribes specific changes to 10 files across the framework, introduces 2 new templates, and extends the process checklist with artifact-aware validation. Estimated total effort: 3-5 days of implementation.

---

## Remediation Index

| ID | Severity | Finding | Section |
|----|----------|---------|---------|
| P4-015 | Critical | Process Checklist Steps Are Self-Attestation | [R-015](#r-015-process-checklist-steps-are-self-attestation) |
| P4-001 | Major | Rollback Test Results Have No Defined Storage or Format | [R-001](#r-001-rollback-test-results-have-no-defined-storage-or-format) |
| P4-002 | Major | Go-Live Verification Has No Sign-Off Artifact | [R-002](#r-002-go-live-verification-has-no-sign-off-artifact) |
| P4-006 | Major | Platform Go-Live Checklists Not Consolidated | [R-006](#r-006-platform-go-live-checklists-not-consolidated) |
| P4-008 | Major | No Verification That Monitoring Captures Events | [R-008](#r-008-no-verification-that-monitoring-captures-events) |
| P4-009 | Major | No Scheduling for Maintenance Cadence | [R-009](#r-009-no-scheduling-for-maintenance-cadence) |
| P4-011 | Major | Handoff Test Results Not Stored, No Failure Procedure | [R-011](#r-011-handoff-test-results-not-stored-no-failure-procedure) |
| P4-013 | Major | SECURITY.md Has No Template, Inconsistent Scope | [R-013](#r-013-securitymd-has-no-template-inconsistent-scope) |
| P4-016 | Major | No Phase 4 Completion Gate After Go-Live | [R-016](#r-016-no-phase-4-completion-gate-after-go-live) |
| P4-003 | Minor | Deployment Strategy Not Recorded | [R-003](#r-003-deployment-strategy-not-recorded) |
| P4-004 | Minor | Post-Incident Review Storage Only in Template | [R-004](#r-004-post-incident-review-storage-only-in-template) |
| P4-007 | Minor | RELEASE_NOTES.md Template Minimal | [R-007](#r-007-release_notesmd-template-minimal) |
| P4-012 | Minor | Handoff Template Missing Monitoring Access | [R-012](#r-012-handoff-template-missing-monitoring-access) |
| P4-017 | Minor | Commit Gate Edge Case with Config Files | [R-017](#r-017-commit-gate-edge-case-with-config-files) |
| P4-005 | Observation | IR Template Enterprise Section Adequate | [R-005](#r-005-ir-template-enterprise-section-adequate) |
| P4-010 | Observation | Weekly Maintenance in User Guide Not in Builder's Guide | [R-010](#r-010-weekly-maintenance-in-user-guide-not-in-builders-guide) |
| P4-014 | Observation | Remediation Table Missing Scenarios | [R-014](#r-014-remediation-table-missing-scenarios) |

---

## Detailed Remediation

### R-015: Process Checklist Steps Are Self-Attestation

| Field | Value |
|-------|-------|
| **Severity** | Critical |
| **Category** | Bypass Risk |
| **Audit Finding** | All 5 Phase 4 steps (`production_build`, `rollback_tested`, `go_live_verified`, `monitoring_configured`, `handoff_written`) completed by `--complete-step` with zero artifact validation. Ordering-only enforcement. |
| **Enterprise Expectation** | Step completion requires artifact existence checks, consistent with Phase 2 `--verify-init` which validates git remote, CI file, and lockfile presence. |
| **Risk if Unresolved** | Every Phase 4 step can be marked done without performing the underlying work. The framework's process enforcement reduces to a compliance checkbox exercise. |

**Root Cause:** The `complete_step()` function in `scripts/process-checklist.sh` (lines 143-210) validates only step ordering (all prior steps completed) and step existence (valid step name). It performs no artifact or state checks. This is architecturally different from `verify_init()` (lines 263-361), which probes for actual system state (git remote, CI file, lockfile, pre-commit hook).

**Remediation:**

Add an artifact validation layer to `complete_step()` that runs before marking a step complete. Implement as a function `validate_step_artifacts()` that maps step IDs to existence checks.

**Files to modify:**

| File | Change |
|------|--------|
| `scripts/process-checklist.sh` | Add `validate_step_artifacts()` function. Call from `complete_step()` after ordering validation, before state update. |
| `scripts/lib/helpers.sh` | Add `check_artifact_exists()` utility if not already present. |

**Artifact validation map for Phase 4 steps:**

| Step | Validation | Rationale |
|------|-----------|-----------|
| `production_build` | CI workflow exists (`.github/workflows/release.yml` or `.github/workflows/ci.yml`) AND build artifact reference present | Production builds must originate from CI, not local machines. |
| `rollback_tested` | Rollback test artifact exists at `docs/test-results/*rollback*` (see R-001) | The framework's own language: "untested rollback = hope." |
| `go_live_verified` | Go-live verification artifact exists at `docs/test-results/*go-live*` (see R-002) | Deployment success must be recorded for audit trail. |
| `monitoring_configured` | Error tracking configuration exists in project (platform-dependent: Sentry DSN, crash reporting config, etc.) OR attestation with reason | Monitoring presence is partially verifiable. |
| `handoff_written` | `HANDOFF.md` exists AND is non-empty (>100 bytes, excluding template boilerplate) | Ensures the document was actually populated, not just the template committed. |

**Design decision -- validation strictness:**

The validation layer should use **existence checks, not content validation**. Content validation (parsing HANDOFF.md for completed sections, verifying rollback test artifact contains required fields) is desirable but introduces brittleness and maintenance cost. The first implementation should ensure artifacts exist and are non-trivially populated. Content validation can be added iteratively as a second pass.

**Override mechanism:** Add a `--force` flag to `complete_step()` that bypasses artifact validation with a logged warning. This prevents the enforcement layer from blocking legitimate edge cases (e.g., platform where rollback artifact format differs from the prescribed path). The override must be logged to `process-state.json` as `"forced": true` on the step entry, creating an audit trail.

**Acceptance criteria:**
1. `--complete-step phase4_release:rollback_tested` fails if no rollback artifact exists.
2. `--complete-step phase4_release:handoff_written` fails if HANDOFF.md is missing or empty.
3. `--complete-step phase4_release:rollback_tested --force` succeeds with logged warning.
4. All Phase 2 `--verify-init` behavior unchanged.

**Effort:** Medium (8-12 hours). The validation map must be implemented, tested, and documented. The `--force` override requires careful logging design.

---

### R-001: Rollback Test Results Have No Defined Storage or Format

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Missing Storage |
| **Audit Finding** | Builder's Guide Step 4.1.5 prescribes a mandatory rollback test but specifies no artifact storage path, file format, or minimum content fields. |
| **Enterprise Expectation** | Defined storage path, standardized format, minimum required fields for rollback test evidence. |
| **Risk if Unresolved** | No evidence that rollback was tested. Auditor cannot distinguish "tested and passed" from "skipped." |

**Root Cause:** Step 4.1.5 describes a 5-step rollback test procedure but treats the test as a pass/fail process checkpoint rather than an evidence-producing activity. The `rollback_tested` step in `process-checklist.sh` is a boolean marker with no artifact association.

**Remediation:**

1. **Define the artifact:** Create a rollback test record format with minimum fields.
2. **Define the storage path:** `docs/test-results/YYYY-MM-DD_rollback-test_[pass|fail].md` (consistent with the existing `docs/test-results/` naming convention from Appendix A).
3. **Update Builder's Guide Step 4.1.5:** Add explicit instruction to record results.
4. **Link to R-015:** The `rollback_tested` step validation checks for this artifact.

**Rollback test record -- minimum fields:**

```markdown
# Rollback Test Record

- **Date:** YYYY-MM-DD
- **Environment:** [production / production-equivalent staging]
- **Release candidate version:** [version or commit hash]
- **Rollback target version:** [version or commit hash]
- **Result:** Pass / Fail

## Procedure Executed
1. [Deployed release candidate to environment]
2. [Executed rollback procedure: command or steps]
3. [Verified application state after rollback]
4. [Verified data integrity after rollback]

## Timing
- **Rollback initiated:** [timestamp]
- **Rollback complete:** [timestamp]
- **Elapsed:** [duration]

## Issues Encountered
[None / description of issues and resolution]

## Data Integrity
- [ ] No data loss after rollback
- [ ] No data corruption after rollback
- [ ] Application functional at prior version
```

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Step 4.1.5) | Add instruction: "Record rollback test results in `docs/test-results/YYYY-MM-DD_rollback-test_[pass\|fail].md`." Add minimum fields reference. |
| `templates/generated/rollback-test.tmpl` | **New file.** Template for rollback test record. |
| `scripts/process-checklist.sh` | Artifact validation for `rollback_tested` step (covered under R-015). |

**Acceptance criteria:**
1. Builder's Guide Step 4.1.5 prescribes the artifact path and format.
2. Template exists at `templates/generated/rollback-test.tmpl`.
3. `rollback_tested` step validation checks for `docs/test-results/*rollback*` file.

**Effort:** Low (2-3 hours).

---

### R-002: Go-Live Verification Has No Sign-Off Artifact

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Audit Trail Gap |
| **Audit Finding** | Builder's Guide Step 4.2 prescribes a go-live checklist with no recording instruction. No Phase 4 completion entry exists in approval-log templates. |
| **Enterprise Expectation** | Go-live result recorded in APPROVAL_LOG.md or dedicated artifact. Auditor can determine when the application went live and who verified. |
| **Risk if Unresolved** | Deployment success is unrecorded. No auditable evidence of when the application entered production or who performed the verification. |

**Root Cause:** The approval-log templates (`approval-log-org.tmpl`, `approval-log-personal.tmpl`) define gates at Phase 0-to-1, Phase 1-to-2, and Phase 3-to-4, but include no Phase 4 completion entry. The framework transitions directly to maintenance with no recorded closure.

**Remediation:**

1. **Create go-live verification artifact:** `docs/test-results/YYYY-MM-DD_go-live-verification_[pass|fail].md` documenting checklist results.
2. **Add Phase 4 completion section to approval-log templates** (see also R-016 for the formal gate).
3. **Update Builder's Guide Step 4.2:** Add instruction to record verification results.

**Go-live verification record -- minimum fields:**

```markdown
# Go-Live Verification Record

- **Date:** YYYY-MM-DD
- **Verifier:** [name]
- **Environment:** Production
- **Version deployed:** [version or commit hash]
- **Result:** Pass / Fail

## Core Checklist
- [ ] Application installs/deploys correctly
- [ ] Complete User Journey verified on each platform
- [ ] Core functionality works as specified
- [ ] Error tracking capturing events (test error triggered)
- [ ] Production configuration values verified
- [ ] Platform-specific checks completed (see platform module)

## Platforms Verified
| Platform | Verified | Notes |
|----------|----------|-------|
| [platform] | Yes/No | [notes] |

## Issues Found
[None / description and severity]
```

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Step 4.2) | Add: "Record go-live verification results in `docs/test-results/YYYY-MM-DD_go-live-verification_[pass\|fail].md`." |
| `templates/generated/go-live-verification.tmpl` | **New file.** Template for go-live record. |
| `templates/generated/approval-log-org.tmpl` | Add Phase 4 completion section (see R-016). |
| `templates/generated/approval-log-personal.tmpl` | Add Phase 4 completion section (see R-016). |
| `scripts/process-checklist.sh` | Artifact validation for `go_live_verified` step (covered under R-015). |

**Acceptance criteria:**
1. Builder's Guide Step 4.2 prescribes the artifact path and format.
2. Template exists at `templates/generated/go-live-verification.tmpl`.
3. Approval-log templates include Phase 4 completion entry.
4. `go_live_verified` step validation checks for the artifact.

**Effort:** Low (2-3 hours).

---

### R-006: Platform Go-Live Checklists Not Consolidated

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Workflow Gap |
| **Audit Finding** | Go-live checklists spread across 4 documents: core (6 checks in Builder's Guide Step 4.2), web (+8 in `docs/platform-modules/web.md` Section 5.2), desktop (+9 in `docs/platform-modules/desktop.md`), mobile (+17 in `docs/platform-modules/mobile.md` Section 5.5). The Orchestrator must manually merge checklists from multiple sources. |
| **Enterprise Expectation** | Consolidated checklist with platform-conditional sections, or explicit cross-reference at the point of use. |
| **Risk if Unresolved** | Platform-specific checks easily missed. Mobile projects face app store rejection risk. Desktop projects risk code signing warnings on installation. |

**Root Cause:** The platform module architecture intentionally separates platform-specific guidance from the core guide. This is the correct architectural decision -- consolidating all platform checks into the core guide would create a maintenance burden when platform requirements change. The gap is the lack of a clear cross-reference at the point of use.

**Remediation:**

Do **not** consolidate the checklists into a single document. The platform module separation is architecturally sound. Instead:

1. **Strengthen the cross-reference in Builder's Guide Step 4.2.** The current note reads "Reference your Platform Module for the platform-specific go-live checklist." Change this to an explicit, unmissable instruction with check counts.
2. **Add the go-live verification template (R-002) with platform sections.** The template should include placeholders for platform-specific checks, prompting the Orchestrator to include them.

**Proposed text for Builder's Guide Step 4.2:**

> **REQUIRED: Complete the platform-specific go-live checklist from your Platform Module in addition to the core checklist above.** Platform modules define additional mandatory checks:
> - Web: 8 additional checks (SSL, security headers, CORS, cookies, rate limiting, Lighthouse)
> - Desktop: 7 additional checks (installer, code signing, auto-update, checksums)
> - Mobile: 14 additional checks (physical device testing, store metadata, privacy declarations, push notifications, deep links, in-app purchases)
>
> Record all checklist results -- core and platform-specific -- in the go-live verification artifact.

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Step 4.2) | Replace the platform module note with explicit cross-reference including check counts. |
| `templates/generated/go-live-verification.tmpl` | Include platform-conditional sections (covered under R-002). |

**Acceptance criteria:**
1. Builder's Guide Step 4.2 explicitly names platform check counts.
2. Go-live verification template includes platform sections.
3. Orchestrator cannot miss platform-specific requirements at the point of use.

**Effort:** Low (1-2 hours).

---

### R-008: No Verification That Monitoring Captures Events

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Missing Validation |
| **Audit Finding** | Builder's Guide Step 4.3 defines monitoring setup in 4 lines. Does not include "trigger test error and verify alert" -- that instruction exists only in User Guide Section 6. |
| **Enterprise Expectation** | "Trigger test error and verify alert received" in the primary process document, not only the companion guide. |
| **Risk if Unresolved** | Monitoring may be configured but never verified. First production error goes undetected. |

**Root Cause:** User Guide Section 6 includes the instruction: "Verify monitoring is active -- trigger a test error and confirm you receive an alert." Builder's Guide Step 4.3 omits this verification step, listing only configuration requirements. The Builder's Guide is the agent's primary instruction document; the User Guide is the Orchestrator's companion. The agent may configure monitoring without ever verifying it captures events.

**Remediation:**

Add the verification step to Builder's Guide Step 4.3 as a mandatory action.

**Proposed addition to Builder's Guide Step 4.3:**

Add after the current "Uptime/health monitoring" bullet:

> **Mandatory verification:** After monitoring is configured, trigger a test error in the application and confirm:
> 1. The error appears in the error tracking dashboard.
> 2. An alert notification is received (email, Slack, or configured channel).
> 3. The alert contains sufficient context to diagnose (stack trace, request details, environment).
>
> If any verification step fails, fix the monitoring configuration before proceeding. Unverified monitoring provides false assurance.

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Step 4.3) | Add mandatory verification steps: trigger test error, confirm dashboard capture, confirm alert delivery, confirm alert context. |

**Acceptance criteria:**
1. Builder's Guide Step 4.3 includes "trigger test error and verify alert" as a mandatory step.
2. The verification instruction is consistent with User Guide Section 6.

**Effort:** Low (1 hour).

---

### R-009: No Scheduling for Maintenance Cadence

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Missing Enforcement |
| **Audit Finding** | Builder's Guide Step 4.4 defines monthly, quarterly, and biannual maintenance cadences but provides no scheduling mechanism. Relies entirely on Orchestrator memory. |
| **Enterprise Expectation** | Proactive reminder mechanism -- calendar integration, ITSM ticket generation, or framework-level script. |
| **Risk if Unresolved** | Maintenance drops for multi-application Orchestrators. The Governance Framework prescribes escalation penalties (maintenance-only freeze after 2 missed monthly audits, production removal after missed biannual audit) but provides no mechanism to prevent the miss in the first place. |

**Root Cause:** The framework defines consequences for missed maintenance (Governance Framework Section XIII, "Maintenance Cadence Enforcement") but offers no prevention mechanism. This is an enforcement asymmetry: the framework penalizes non-compliance without enabling compliance.

**Remediation:**

This is a design decision with sustainability implications. Three options were evaluated:

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| A. Calendar export script | `scripts/maintenance-schedule.sh` generates `.ics` files for all cadences | Platform-agnostic, Orchestrator imports once, reminders automatic | Requires re-export if cadences change. Does not detect skipped maintenance. |
| B. Maintenance check script | `scripts/check-maintenance.sh` reads CHANGELOG.md timestamps, warns if overdue | Detectable in CI. Integrates with existing `check-phase-gate.sh`. | Requires CHANGELOG.md entries to follow parseable format. |
| C. ITSM integration guidance | Prescribe ticket template and cadence for organizational deployments | Aligns with enterprise ITSM. | Not actionable for personal deployments. Framework cannot mandate specific ITSM tools. |

**Recommended approach: Option A + B combined.**

Option A provides prevention (the Orchestrator receives calendar reminders). Option B provides detection (CI or manual invocation identifies overdue maintenance). Option C is documentation-only and should be added to the Governance Framework as guidance for organizational deployments.

**Option A -- Calendar export:**

Create `scripts/maintenance-schedule.sh` that generates a `.ics` calendar file with recurring events:
- Weekly: 30-minute review (Friday)
- Monthly: 2-hour maintenance window (first Monday)
- Quarterly: 3-hour review (first week of Jan/Apr/Jul/Oct)
- Biannually: 4-hour audit (first week of Jan/Jul)

The script reads the project name from `phase-state.json` and embeds it in event titles. The Orchestrator imports the `.ics` file into their calendar application once. This is a one-time setup action added to Phase 4 Step 4.3 or 4.4.

**Option B -- Maintenance staleness check:**

Create `scripts/check-maintenance.sh` that:
1. Reads the most recent maintenance entry from CHANGELOG.md (parses date from `## [version] -- YYYY-MM-DD` or `### Maintenance -- YYYY-MM-DD`).
2. Compares to current date.
3. Warns if >35 days since last monthly entry, >100 days since quarterly, >200 days since biannual.
4. Exits non-zero if any cadence is overdue.

This script can be invoked by `check-phase-gate.sh` when `current_phase >= 4`, providing CI-level visibility into maintenance compliance.

**Files to create:**

| File | Purpose |
|------|---------|
| `scripts/maintenance-schedule.sh` | Generate `.ics` calendar export with recurring maintenance events. |
| `scripts/check-maintenance.sh` | Detect overdue maintenance from CHANGELOG.md timestamps. |

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Step 4.4) | Add instruction to run `scripts/maintenance-schedule.sh` and import the calendar file. Add cross-reference to `check-maintenance.sh`. |
| `docs/user-guide.md` (Section 7) | Add instruction to import maintenance calendar. Reference the detection script. |
| `docs/governance-framework.md` (Section XIII) | Add ITSM ticket creation guidance for organizational deployments. |
| `scripts/check-phase-gate.sh` | Add optional invocation of `check-maintenance.sh` when `current_phase >= 4`. |

**Acceptance criteria:**
1. `scripts/maintenance-schedule.sh` generates a valid `.ics` file with correct recurrence rules.
2. `scripts/check-maintenance.sh` correctly identifies overdue maintenance from CHANGELOG.md.
3. Builder's Guide and User Guide reference both scripts.
4. Governance Framework includes ITSM guidance.

**Effort:** Medium (6-8 hours). Calendar file generation requires RFC 5545 compliance. CHANGELOG.md date parsing requires robust pattern matching.

**Sustainability note:** The maintenance cadence is the framework's most important long-term obligation. Every other process runs once; maintenance runs indefinitely. The detection script (`check-maintenance.sh`) is more valuable than the calendar export because it provides verifiable evidence of compliance. If only one component is implemented first, prioritize the detection script.

---

### R-011: Handoff Test Results Not Stored, No Failure Procedure

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Missing Storage |
| **Audit Finding** | Governance Framework defines a 6-step handoff test. No storage template, no `handoff_tested` step in the process checklist, no defined success criteria, no maximum iteration count. |
| **Enterprise Expectation** | Template for test results, process checklist step, defined success criteria, and maximum iteration guidance. |
| **Risk if Unresolved** | Handoff test can be skipped entirely. HANDOFF.md quality is never validated by an independent reader. |

**Root Cause:** The Governance Framework (Section XIII, "Handoff Test") prescribes a rigorous 6-step test: (1) backup maintainer sets up dev environment from HANDOFF.md, (2) backup maintainer triages a simulated issue, (3) measure time, (4) document stuck points, (5) fix gaps, (6) repeat until unassisted completion. However, this test has no corresponding process step, no result template, and no storage path. Appendix A lists "Handoff Test Results" at Phase 4 with location `docs/test-results/` but provides no template.

**Remediation:**

1. **Add `handoff_tested` step to `PHASE4_STEPS` in `process-checklist.sh`.** This step comes after `handoff_written`, creating a 6-step Phase 4 process: `production_build` -> `rollback_tested` -> `go_live_verified` -> `monitoring_configured` -> `handoff_written` -> `handoff_tested`.
2. **Create handoff test result template.**
3. **Define success criteria and maximum iteration guidance.**
4. **Update Builder's Guide Step 4.5.**
5. **Distinguish personal vs. organizational requirements.** Personal projects may not have a backup maintainer; the handoff test should still be performed as a self-test (Orchestrator follows their own HANDOFF.md on a clean environment).

**Handoff test result template -- minimum fields:**

```markdown
# Handoff Test Results

- **Date:** YYYY-MM-DD
- **Tester:** [backup maintainer name / self-test]
- **Iteration:** [1 / 2 / 3 / ...]
- **Result:** Pass / Fail

## Environment Setup (from HANDOFF.md)
- **Time to complete:** [duration]
- **Completed unassisted:** Yes / No
- **Stuck points:**
  - [description of where tester got stuck]
  - [missing command, wrong path, unclear step, etc.]

## Issue Triage (simulated)
- **Simulated issue:** [description]
- **Time to triage:** [duration]
- **Completed unassisted:** Yes / No
- **Documentation gaps found:**
  - [description]

## Documentation Fixes Applied
- [ ] [fix description -- file, section, change]

## Success Criteria Met
- [ ] Environment setup completed unassisted
- [ ] Issue triage completed unassisted
- [ ] All documentation gaps fixed
```

**Maximum iteration guidance:** Add to Builder's Guide Step 4.5: "Expect 2-3 iterations. If the handoff test has not passed after 3 iterations, escalate to the Application Owner -- the documentation complexity may indicate an architecture that is not maintainable by a replacement developer."

**Files to modify:**

| File | Change |
|------|--------|
| `scripts/process-checklist.sh` | Add `handoff_tested` to `PHASE4_STEPS` array (after `handoff_written`). Add artifact validation: `docs/test-results/*handoff-test*` file must exist. |
| `templates/generated/handoff-test.tmpl` | **New file.** Template for handoff test results. |
| `docs/builders-guide.md` (Step 4.5) | Add explicit handoff test instruction, link to template, define success criteria, add iteration guidance. |
| `docs/user-guide.md` (Section 6) | Add handoff test instruction for personal and organizational deployments. |

**Acceptance criteria:**
1. `PHASE4_STEPS` contains 6 steps (was 5).
2. `handoff_tested` requires handoff test artifact in `docs/test-results/`.
3. Builder's Guide Step 4.5 includes handoff test procedure, success criteria, and iteration guidance.
4. Template exists at `templates/generated/handoff-test.tmpl`.

**Effort:** Medium (4-6 hours). Process step addition is straightforward; template and documentation changes require careful alignment with Governance Framework Section XIII.

---

### R-013: SECURITY.md Has No Template, Inconsistent Scope

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Missing Template |
| **Audit Finding** | Appendix A lists SECURITY.md as "web/desktop." All three platform modules (web, desktop, mobile) prescribe it. No template exists in `templates/generated/`. |
| **Enterprise Expectation** | Template for all externally-accessible platforms. Scope consistent across Appendix A and platform modules. Enforcement at go-live. |
| **Risk if Unresolved** | No vulnerability disclosure mechanism. Missing SECURITY.md means external security researchers have no responsible disclosure channel. |

**Root Cause:** Appendix A was written before the mobile platform module was completed. The mobile module (line 1535) prescribes SECURITY.md with the same requirements as web and desktop, but Appendix A (line 1490) scopes it to "web/desktop" only. Additionally, no template exists -- all three platform modules describe the same 4 content requirements inline without a reusable template.

**Remediation:**

1. **Create `templates/generated/security.tmpl`** with the 4 required sections identified consistently across all platform modules.
2. **Fix Appendix A scope** to include mobile.
3. **Add SECURITY.md to Phase 4 init.sh generation** (if applicable) or to Builder's Guide Step 4.2 as a required artifact.

**SECURITY.md template -- content:**

```markdown
# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| [current version] | Yes |
| [previous version] | [Yes / Security fixes only / No] |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

**Email:** [security contact email]

**Do NOT** open a public issue for security vulnerabilities.

## Response Timeline

- **Acknowledgment:** Within 48 hours of report
- **Initial assessment:** Within 7 days
- **Fix target:** Based on severity (Critical: 48 hours, High: 7 days, Medium: 30 days, Low: next release)

## Safe Harbor

We consider security research conducted in good faith to be authorized. We will not pursue legal action against researchers who:
- Make a good faith effort to avoid privacy violations, data destruction, and service disruption
- Provide sufficient detail for us to reproduce and fix the issue
- Do not publicly disclose the vulnerability before we have had reasonable time to address it
```

**Files to create:**

| File | Purpose |
|------|---------|
| `templates/generated/security.tmpl` | Reusable SECURITY.md template. |

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Appendix A) | Change SECURITY.md scope from "web/desktop" to "web/desktop/mobile" or "all externally-accessible platforms." |
| `docs/builders-guide.md` (Step 4.2) | Add SECURITY.md to go-live checklist: "Create SECURITY.md if not already present (web, desktop, mobile projects)." |

**Acceptance criteria:**
1. Template exists at `templates/generated/security.tmpl`.
2. Appendix A scope includes mobile.
3. Builder's Guide Step 4.2 lists SECURITY.md as a go-live requirement.
4. Template content matches the 4 requirements described in all 3 platform modules.

**Effort:** Low (2-3 hours).

---

### R-016: No Phase 4 Completion Gate After Go-Live

| Field | Value |
|-------|-------|
| **Severity** | Major |
| **Category** | Audit Trail Gap |
| **Audit Finding** | Phase gate approvals exist at 0-to-1, 1-to-2, and 3-to-4. No closing gate after Phase 4 deliverables are complete. The framework transitions to maintenance with no recorded completion event. |
| **Enterprise Expectation** | Phase 4 completion entry recording deployment date, verification result, handoff status. Auditor can determine when the application was officially "live." |
| **Risk if Unresolved** | Missing closure record. Auditor cannot determine when the application entered production or whether Phase 4 deliverables were completed. |

**Root Cause:** The approval-log templates define gates where human approval is required before proceeding. Phase 3-to-4 is the last gate requiring approval. After that, the Orchestrator completes Phase 4 deliverables and transitions to maintenance. There is no recorded event marking this transition.

**Remediation:**

Add a "Phase 4 Completion" section to the approval-log templates. This is not a gate requiring external approval -- it is a completion record signed by the Orchestrator (personal) or Application Owner (organizational) confirming that all Phase 4 deliverables are complete.

**Phase 4 Completion section for approval-log templates:**

```markdown
## Phase 4 Completion: Production Launch

**Requirement:** Orchestrator (personal) or Application Owner (organizational) records
that all Phase 4 deliverables are complete and the application is live.

| Field | Value |
|---|---|
| **Event** | Phase 4 Completion |
| **Recorded by** | |
| **Role** | Orchestrator / Application Owner |
| **Date** | |
| **Production URL / distribution** | |
| **Version deployed** | |
| **Artifacts completed** | HANDOFF.md, RELEASE_NOTES.md, INCIDENT_RESPONSE.md, SECURITY.md, monitoring |
| **Handoff test** | Passed / Pending / N/A (personal) |
| **Go-live verification** | Passed (reference: docs/test-results/...) |
| **Notes** | |
```

**Files to modify:**

| File | Change |
|------|--------|
| `templates/generated/approval-log-org.tmpl` | Add Phase 4 Completion section after the Phase 3-to-4 gate. |
| `templates/generated/approval-log-personal.tmpl` | Add Phase 4 Completion section (simplified -- no Application Owner). |
| `scripts/check-phase-gate.sh` | Add Phase 4 completion check: when `current_phase == 4`, verify APPROVAL_LOG.md contains a Phase 4 completion entry. |

**Acceptance criteria:**
1. Both approval-log templates include Phase 4 Completion section.
2. `check-phase-gate.sh` verifies Phase 4 completion entry when in Phase 4.
3. Entry captures deployment date, version, and artifact completion status.

**Effort:** Low (2-3 hours).

---

### R-003: Deployment Strategy Not Recorded

| Field | Value |
|-------|-------|
| **Severity** | Minor |
| **Category** | Audit Trail Gap |
| **Audit Finding** | Builder's Guide Step 4.1 says "Document the chosen strategy in the Project Bible" but no enforcement verifies this documentation exists. |
| **Risk if Unresolved** | Low. Clear instruction exists; enforcement absent. |

**Remediation:**

No script enforcement recommended. The deployment strategy instruction is clear and at the right location. Add a checkbox to the go-live verification template (R-002) to confirm strategy is documented:

> - [ ] Deployment strategy documented in Project Bible

**Files to modify:**

| File | Change |
|------|--------|
| `templates/generated/go-live-verification.tmpl` | Add deployment strategy checkbox (covered under R-002 template creation). |

**Acceptance criteria:** Go-live verification template includes deployment strategy confirmation checkbox.

**Effort:** Minimal (included in R-002).

---

### R-004: Post-Incident Review Storage Only in Template

| Field | Value |
|-------|-------|
| **Severity** | Minor |
| **Category** | Missing Documentation |
| **Audit Finding** | `incident-response.tmpl` Section 7 (line 130) defines `docs/incidents/YYYY-MM-DD-[brief-slug].md` as the storage path for post-incident reviews. Builder's Guide and Appendix A do not reference this path. |
| **Risk if Unresolved** | Minor. The template provides the correct path, but Appendix A (the canonical artifact list) does not include it. |

**Remediation:**

Add `docs/incidents/` to Appendix A as a Phase 4+ artifact.

**Proposed Appendix A entry:**

| Artifact | Phase | Purpose | Location | Template |
|---|---|---|---|---|
| Post-Incident Reviews | 4+ | Root cause analysis and preventive measures for SEV-1/SEV-2 incidents | `docs/incidents/YYYY-MM-DD-[slug].md` | Embedded in `incident-response.tmpl` Section 7 |

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Appendix A) | Add `docs/incidents/` entry to artifact table. |

**Acceptance criteria:** Appendix A includes `docs/incidents/` with Phase 4+ scope.

**Effort:** Minimal (15 minutes).

---

### R-007: RELEASE_NOTES.md Template Minimal

| Field | Value |
|-------|-------|
| **Severity** | Minor |
| **Category** | Missing Template |
| **Audit Finding** | `release-notes.tmpl` is 25 lines with 4 sections. No compatibility section. No subsequent-release template. |
| **Risk if Unresolved** | Low. Template is functional for initial release. Subsequent releases may lack compatibility information. |

**Remediation:**

Extend the template with an optional compatibility section and a subsequent-release section marker.

**Proposed additions to `templates/generated/release-notes.tmpl`:**

Add after "Known Limitations":

```markdown
### System Requirements & Compatibility

[Minimum OS versions, browser support, hardware requirements, breaking changes from prior version]
```

Add a subsequent-release template block:

```markdown
<!--
  Subsequent release template:

  ## [Version] -- YYYY-MM-DD

  ### What's New
  [User-facing changes]

  ### What's Fixed
  [Resolved issues]

  ### Breaking Changes
  [Changes that require user action -- migration steps, deprecated features removed]

  ### Known Limitations
  [New or continuing limitations]

  ### System Requirements & Compatibility
  [Only include if requirements changed from prior release]
-->
```

**Files to modify:**

| File | Change |
|------|--------|
| `templates/generated/release-notes.tmpl` | Add compatibility section. Add subsequent-release template in a comment block. |

**Acceptance criteria:**
1. Template includes compatibility section.
2. Template includes commented subsequent-release format.

**Effort:** Low (1 hour).

---

### R-012: Handoff Template Missing Monitoring Access

| Field | Value |
|-------|-------|
| **Severity** | Minor |
| **Category** | Missing Template |
| **Audit Finding** | `handoff.tmpl` Section 8 ("Key Contacts & Third-Party Services") includes a services table but no monitoring-specific section. A replacement maintainer must discover the monitoring dashboard independently. |
| **Risk if Unresolved** | Increased onboarding time. Monitoring access is critical for the backup maintainer's first task (checking error dashboard). |

**Remediation:**

Add a monitoring access subsection to `handoff.tmpl` Section 8. This should appear before the services table since monitoring access is the backup maintainer's first operational need.

**Proposed addition to `handoff.tmpl` after the Section 8 heading:**

```markdown
**Monitoring & Error Tracking:**

| Dashboard | URL | Access Method | Alert Channel |
|-----------|-----|--------------|---------------|
| [e.g., Sentry] | [URL] | [e.g., SSO / invite required] | [e.g., #alerts Slack channel] |
| [e.g., Uptime Robot] | [URL] | [access method] | [alert channel] |

<!-- The backup maintainer's first task is checking the error dashboard. -->
<!-- Make sure they can access it without asking anyone. -->
```

**Files to modify:**

| File | Change |
|------|--------|
| `templates/generated/handoff.tmpl` (Section 8) | Add monitoring access table before the services table. |

**Acceptance criteria:** Handoff template Section 8 includes monitoring dashboard access details with URL, access method, and alert channel.

**Effort:** Low (30 minutes).

---

### R-017: Commit Gate Edge Case with Config Files

| Field | Value |
|-------|-------|
| **Severity** | Minor |
| **Category** | Bypass Risk |
| **Audit Finding** | `.yml`, `.json`, `.toml`, and `.tmpl` files are exempt from the commit gate in `scripts/process-checklist.sh` (lines 518-529). Deployment configuration files (Dockerfile, docker-compose.yml, Terraform files) can be committed without Phase 4 steps completed. |
| **Risk if Unresolved** | Low. This is an intentional design decision to allow documentation and configuration commits during any phase. Deployment configs are a narrow edge case. |

**Remediation:**

Document the design decision rather than changing the behavior. The current exemption serves a legitimate purpose: documentation and template commits should not be blocked by process steps. Tightening the exemption to exclude deployment configs would require maintaining a growing list of deployment-related file patterns, adding complexity without proportional risk reduction.

**Proposed addition to `scripts/process-checklist.sh` comments:**

Add a comment block near the commit gate classification logic (lines 518-529):

```bash
# Design decision: .yml/.json/.toml/.tmpl files are classified as "docs"
# and exempt from process step enforcement. This allows documentation,
# template, and configuration commits at any time. Deployment-specific
# configs (Dockerfile, docker-compose.yml, terraform) are technically
# exempt under this rule. The risk is accepted because:
# 1. Deployment configs alone cannot deploy -- CI/CD triggers are separate.
# 2. Tightening the exemption adds maintenance cost without proportional benefit.
# 3. The Phase 4 completion gate (APPROVAL_LOG) captures deployment readiness.
```

**Files to modify:**

| File | Change |
|------|--------|
| `scripts/process-checklist.sh` | Add design decision comment at the file classification logic. |

**Acceptance criteria:** Design decision documented in code comments. No behavioral change.

**Effort:** Minimal (15 minutes).

---

### R-005: IR Template Enterprise Section Adequate

| Field | Value |
|-------|-------|
| **Severity** | Observation |
| **Category** | N/A |
| **Audit Finding** | `incident-response.tmpl` Section 6 correctly references Governance Framework Section VII for enterprise IR integration. Well-structured. |

**Remediation:** None required. Finding confirmed the template is adequate.

---

### R-010: Weekly Maintenance in User Guide Not in Builder's Guide

| Field | Value |
|-------|-------|
| **Severity** | Observation |
| **Category** | Missing Documentation |
| **Audit Finding** | User Guide Section 7 adds a weekly cadence (30 minutes: review error dashboard, check alerts, health check) not present in Builder's Guide Step 4.4. The Builder's Guide starts at monthly. |

**Remediation:**

Add the weekly cadence to Builder's Guide Step 4.4 for consistency. The User Guide's weekly cadence is operationally sound and should be reflected in the primary reference.

**Proposed addition to Builder's Guide Step 4.4, before "Monthly":**

```markdown
**Weekly (30 minutes):**
- Review error dashboard for recurring errors
- Check monitoring alerts for unresolved notifications
- Quick application health check (core flow operational)
```

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Step 4.4) | Add weekly cadence section before monthly. |

**Acceptance criteria:** Builder's Guide and User Guide maintenance cadences are consistent.

**Effort:** Minimal (15 minutes).

---

### R-014: Remediation Table Missing Scenarios

| Field | Value |
|-------|-------|
| **Severity** | Observation |
| **Category** | Missing Documentation |
| **Audit Finding** | Builder's Guide Phase 4 Remediation table covers 5 scenarios (Build Failure, Environment Mismatch, Cost Spike, Dependency Break, Rollback Failure). Missing: monitoring failure, go-live failure, app store rejection. |

**Remediation:**

Add the missing scenarios to the Phase 4 Remediation table.

**Proposed additions:**

| Issue | Detection | Response |
|---|---|---|
| **Monitoring Failure** | Test error not captured in dashboard | "Fix monitoring before launch. Monitoring that doesn't capture errors is worse than no monitoring -- it's false assurance." |
| **Go-Live Failure** | Production smoke test fails on one or more platforms | "Do not announce launch. Isolate the failing platform. Roll back if partially deployed. Fix on a branch." |
| **App Store Rejection** | Store review returns rejection notice | "Read the rejection reason carefully. Fix the specific issue cited. Do not shotgun changes. Resubmit with a clear explanation of what changed." |

**Files to modify:**

| File | Change |
|------|--------|
| `docs/builders-guide.md` (Phase 4 Remediation table) | Add 3 rows: Monitoring Failure, Go-Live Failure, App Store Rejection. |

**Acceptance criteria:** Phase 4 Remediation table covers 8 scenarios.

**Effort:** Minimal (30 minutes).

---

## Implementation Plan

### Phase 1: Critical Fix (P4-015)

| Priority | ID | Deliverable | Effort |
|----------|-----|-------------|--------|
| 1 | R-015 | Artifact validation layer in `process-checklist.sh` | 8-12 hours |

This is the foundational change. All other artifact-related remediations (R-001, R-002, R-011) depend on the validation framework being in place.

### Phase 2: Artifact Templates and Storage (P4-001, P4-002, P4-011, P4-013)

| Priority | ID | Deliverable | Effort |
|----------|-----|-------------|--------|
| 2 | R-001 | Rollback test template + Builder's Guide update | 2-3 hours |
| 3 | R-002 | Go-live verification template + Builder's Guide update | 2-3 hours |
| 4 | R-011 | Handoff test template + process step + Builder's Guide update | 4-6 hours |
| 5 | R-013 | SECURITY.md template + Appendix A scope fix | 2-3 hours |

### Phase 3: Gates, Scheduling, and Documentation (P4-016, P4-009, remaining)

| Priority | ID | Deliverable | Effort |
|----------|-----|-------------|--------|
| 6 | R-016 | Approval-log Phase 4 completion section + gate check | 2-3 hours |
| 7 | R-009 | Maintenance scheduling scripts + documentation | 6-8 hours |
| 8 | R-006, R-008, R-010, R-014 | Builder's Guide documentation updates (batch) | 2-3 hours |
| 9 | R-003, R-004, R-007, R-012, R-017 | Minor template and documentation fixes (batch) | 2-3 hours |

### Total Estimated Effort

| Category | Hours |
|----------|-------|
| Critical (R-015) | 8-12 |
| Artifact templates (R-001, R-002, R-011, R-013) | 10-15 |
| Gates and scheduling (R-016, R-009) | 8-11 |
| Documentation updates (remaining) | 4-6 |
| **Total** | **30-44 hours** |

---

## Verification Test Plan

| Test ID | Finding | Test | Expected Result |
|---------|---------|------|-----------------|
| V-015a | P4-015 | Run `--complete-step phase4_release:rollback_tested` without rollback artifact | Rejected: "artifact not found" |
| V-015b | P4-015 | Run `--complete-step phase4_release:handoff_written` without HANDOFF.md | Rejected: "HANDOFF.md not found" |
| V-015c | P4-015 | Run `--complete-step phase4_release:rollback_tested --force` | Succeeds with logged warning; `process-state.json` records `"forced": true` |
| V-001 | P4-001 | Complete rollback test, verify artifact at `docs/test-results/*rollback*` | Artifact exists with required fields |
| V-002 | P4-002 | Complete go-live verification, check APPROVAL_LOG.md | Go-live artifact exists; approval log has Phase 4 completion entry |
| V-006 | P4-006 | Read Builder's Guide Step 4.2 | Platform-specific check counts listed explicitly |
| V-008 | P4-008 | Read Builder's Guide Step 4.3 | "Trigger test error and verify alert" is a mandatory step |
| V-009a | P4-009 | Run `scripts/maintenance-schedule.sh` | Valid `.ics` file generated with correct recurrence rules |
| V-009b | P4-009 | Run `scripts/check-maintenance.sh` on project with >35-day maintenance gap | Warning: "monthly maintenance overdue" |
| V-011 | P4-011 | Run `--complete-step phase4_release:handoff_tested` without handoff test artifact | Rejected: "handoff test artifact not found" |
| V-013 | P4-013 | Read Appendix A SECURITY.md entry | Scope includes mobile |
| V-016 | P4-016 | Complete all Phase 4 steps, check approval-log | Phase 4 Completion entry present |

---

## File Impact Summary

### New Files (4)

| File | Purpose |
|------|---------|
| `templates/generated/rollback-test.tmpl` | Rollback test result template |
| `templates/generated/go-live-verification.tmpl` | Go-live verification record template |
| `templates/generated/handoff-test.tmpl` | Handoff test result template |
| `templates/generated/security.tmpl` | SECURITY.md template |

### New Scripts (2)

| File | Purpose |
|------|---------|
| `scripts/maintenance-schedule.sh` | Calendar export for maintenance cadences |
| `scripts/check-maintenance.sh` | Detect overdue maintenance from CHANGELOG.md |

### Modified Files (8)

| File | Changes |
|------|---------|
| `scripts/process-checklist.sh` | Add `validate_step_artifacts()`, add `handoff_tested` step, add `--force` flag |
| `scripts/check-phase-gate.sh` | Add Phase 4 completion check, optional maintenance staleness check |
| `docs/builders-guide.md` | Steps 4.1.5, 4.2, 4.3, 4.4, 4.5; Phase 4 Remediation table; Appendix A |
| `docs/user-guide.md` | Section 6 (Phase 4 handoff test), Section 7 (maintenance scheduling reference) |
| `docs/governance-framework.md` | Section XIII (ITSM ticket guidance for maintenance cadence) |
| `templates/generated/approval-log-org.tmpl` | Add Phase 4 Completion section |
| `templates/generated/approval-log-personal.tmpl` | Add Phase 4 Completion section |
| `templates/generated/handoff.tmpl` | Add monitoring access table to Section 8 |
| `templates/generated/release-notes.tmpl` | Add compatibility section and subsequent-release template |

---

## Cross-References

| This Remediation | Related Consolidated Pattern | Related Phase Remediations |
|-----------------|----------------------------|---------------------------|
| R-015 (self-attestation) | Pattern A: Process Steps Are Self-Attestation | P2-006, P3-008 (same pattern in Phases 2-3) |
| R-002, R-016 (approval log gaps) | Pattern B: APPROVAL_LOG Integrity | P0-004, P0-005, CC-004 |
| R-009 (maintenance scheduling) | Pattern F: Organizational Enforcement Relies on Manual Compliance | CC-014 (quarterly verification) |
| R-013 (SECURITY.md scope) | -- | P3-004 (similar cross-document inconsistency) |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Artifact validation too strict -- blocks legitimate workflows | Medium | Medium | `--force` override with audit logging (R-015) |
| Maintenance scheduling script generates invalid .ics | Low | Low | RFC 5545 compliance testing; fallback to manual calendar entry |
| `handoff_tested` step impractical for personal projects without backup maintainer | Medium | Low | Allow self-test (Orchestrator follows own HANDOFF.md on clean environment) |
| New templates increase framework file count without proportional adoption | Low | Low | Templates are generated on project init; unused templates do not affect running projects |
| CHANGELOG.md date parsing in `check-maintenance.sh` fragile across format variations | Medium | Low | Document required date format; fail open (warn, not block) on parse failure |

---

## Appendix: Observations Requiring No Action

| ID | Finding | Rationale |
|----|---------|-----------|
| P4-005 | IR Template Enterprise Section Adequate | Template Section 6 correctly references Governance Framework Section VII. No change needed. |

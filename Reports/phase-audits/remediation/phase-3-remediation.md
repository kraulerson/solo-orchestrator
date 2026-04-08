# Phase 3 Remediation Plan
## Validation, Security & UAT

**Date:** 2026-04-08
**Source Audit:** Phase 3 Process Audit Report (2026-04-08-phase-3-audit.md)
**Framework Version:** Solo Orchestrator v1.0 (post-PR #6, #7)
**Audience:** C-Suite, IT Security, Internal Audit, Senior Technical Authority
**Total Findings:** 20 (1 Critical, 5 Major, 8 Minor, 4 Observation)

---

## Executive Summary

Phase 3 (Validation, Security & UAT) is structurally sound. Sequential step enforcement, agent personas for each test type, and the Security Scan Interpretation Guide represent mature process design. The gaps are not in what the framework prescribes -- they are in what the framework enforces.

The critical finding is attorney review of AI-generated legal documents (P3-004). The Builder's Guide mandates it in prose; no enforcement mechanism exists. This is the highest-liability gap in the entire framework -- an AI-generated Privacy Policy deployed without legal review exposes the organization to regulatory action, contractual liability, and reputational damage. Every other finding is downstream of this pattern: governance requirements exist in documentation but lack mechanical enforcement.

This remediation plan addresses all 20 findings with specific code changes, template additions, and documentation updates. Each remediation includes implementation options with trade-offs, affected files, acceptance criteria, and verification tests. Remediations are ordered by severity and dependency -- later items depend on earlier ones being in place.

**Estimated total effort:** 45-65 hours across all severity tiers.

---

## Table of Contents

1. [Critical Remediation](#1-critical-remediation)
2. [Major Remediations](#2-major-remediations)
3. [Minor Remediations](#3-minor-remediations)
4. [Observation Remediations](#4-observation-remediations)
5. [Dependency Map](#5-dependency-map)
6. [Verification Test Plan](#6-verification-test-plan)
7. [Implementation Schedule](#7-implementation-schedule)
8. [Risk Assessment](#8-risk-assessment)

---

## 1. Critical Remediation

### R-P3-004: Attorney Review Tracking and Enforcement

**Finding:** Builder's Guide Step 3.6 mandates attorney review of Privacy Policy and Terms of Service. No APPROVAL_LOG entry exists for legal review. No process checklist step. No gate check. The highest-liability activity in the framework has the weakest enforcement.

**Root Cause:** Step 3.6 was added as prose guidance without corresponding updates to the three enforcement layers (approval log template, process checklist, gate check script).

**Why This Matters:** AI-generated legal documents routinely contain inaccuracies, omissions, and generic language that fails to address specific data processing activities. Deploying them without attorney review creates exposure to GDPR/CCPA enforcement actions, contractual liability from incorrect terms, and regulatory findings that the organization's own framework identified the risk but failed to enforce the control.

#### Option A: Full Enforcement (Recommended)

Add attorney review as a tracked, gated governance event across all three enforcement layers.

**Changes:**

1. **`templates/generated/approval-log-org.tmpl`** -- Add a new section between the Phase 1->2 gate and the Phase 3->4 gate:

```markdown
## Legal Review: Privacy Policy & Terms of Service

**Requirement:** AI-generated legal documents must be reviewed by qualified legal counsel before deployment. This is a pre-condition for Phase 3->4 gate approval.
**Reference:** Builder's Guide Step 3.6; Governance Framework Section V.
**Trigger:** Project collects user data OR provides terms of service.

| Field | Value |
|---|---|
| **Review Type** | Privacy Policy / Terms of Service / Both |
| **Reviewer** | |
| **Firm / Department** | |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Documents Reviewed** | |
| **Decision** | Approved / Approved with revisions / Rejected |
| **Revisions Required** | |
| **Notes** | |
```

2. **`scripts/process-checklist.sh`** -- Add `legal_review_complete` and `pre_launch_prepared` to `PHASE3_STEPS`:

```bash
PHASE3_STEPS=(integration_testing security_hardening chaos_testing accessibility_audit performance_audit contract_testing results_archived legal_review_complete pre_launch_prepared)
```

Note: `legal_review_complete` is sequenced after `results_archived` because legal review should occur after security findings are resolved, and before pre-launch preparation is finalized. Projects that do not collect data or provide terms skip this step via a new `--skip-step` mechanism (see trade-offs below).

3. **`scripts/check-phase-gate.sh`** -- Add legal review verification to the Phase 3->4 artifact checks:

```bash
# Legal review check (Phase 3->4)
if [ "$current_phase" -ge 3 ]; then
  # Check if project has legal documents that require review
  has_legal_docs=false
  for doc in "PRIVACY_POLICY.md" "TERMS_OF_SERVICE.md" "privacy-policy.md" "terms-of-service.md"; do
    if [ -f "$doc" ] || find . -maxdepth 2 -name "$doc" -print -quit 2>/dev/null | grep -q .; then
      has_legal_docs=true
      break
    fi
  done

  if [ "$has_legal_docs" = true ]; then
    if grep -q "Legal Review.*Privacy Policy\|Legal Review.*Terms" "$APPROVAL_LOG" && \
       grep -A 20 "Legal Review" "$APPROVAL_LOG" | grep -qE "Reviewer.*[A-Z]" && \
       grep -A 20 "Legal Review" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
      echo -e "${GREEN}  [OK]${NC} Legal review recorded in APPROVAL_LOG.md"
    else
      echo -e "${RED}[FAIL]${NC} Legal documents present but no attorney review recorded in APPROVAL_LOG.md"
      echo "  Builder's Guide Step 3.6 requires qualified legal counsel review before deployment."
      issues=$((issues + 1))
    fi
  fi
fi
```

4. **`docs/builders-guide.md`** -- Add process checkpoint to Step 3.6 Legal section:

```markdown
**Process checkpoint:** After attorney review is complete and approval is recorded in APPROVAL_LOG.md:
`scripts/process-checklist.sh --complete-step phase3_validation:legal_review_complete`
```

**Trade-offs:**
- Adds a hard gate for legal review. Projects without legal documents (internal tools, no data collection) will need a skip mechanism or the gate check must be conditional.
- Requires the Orchestrator to ensure the attorney (not the Orchestrator) commits the approval log entry, consistent with existing commit-authorship requirements.
- Does not validate the quality of legal review -- only that it occurred and was recorded.

**Effort:** 4-6 hours
**Risk if deferred:** High. Every project deploying an AI-generated Privacy Policy without this control is a potential regulatory event. This is the one finding where "we'll get to it later" is not an acceptable position.

#### Option B: Advisory Gate (Reduced Scope)

Add APPROVAL_LOG section and gate warning (not blocking) without process checklist integration.

**Trade-offs:**
- Faster to implement (2-3 hours).
- Does not prevent deployment -- only warns. Orchestrators can proceed past the warning.
- Appropriate as an interim measure while Option A is implemented, but should not be the final state.

**Effort:** 2-3 hours

#### Recommendation

Option A. This is a legal liability control, not a quality improvement. Advisory controls are insufficient for compliance-consequential activities. The incremental effort (2-3 hours) is trivial relative to the exposure.

**Acceptance Criteria:**
- APPROVAL_LOG template includes Legal Review section with reviewer, date, decision fields.
- `process-checklist.sh` includes `legal_review_complete` step in Phase 3 sequence.
- `check-phase-gate.sh` detects legal documents and requires corresponding approval log entry.
- Gate blocks (not warns) when legal documents exist without recorded review.

**Files Modified:**
- `templates/generated/approval-log-org.tmpl`
- `templates/generated/approval-log-personal.tmpl` (add advisory note: "Personal projects deploying publicly should still obtain legal review")
- `scripts/process-checklist.sh`
- `scripts/check-phase-gate.sh`
- `docs/builders-guide.md`

---

## 2. Major Remediations

### R-P3-001: False Positive Documentation Template and Storage

**Finding:** Builder's Guide Step 3.2 references "Phase 3 security audit notes" for false positive documentation. No template exists. No file location defined. No naming convention.

#### Option A: Structured Log in `docs/test-results/` (Recommended)

Create a false positive log template with structured fields. Store alongside other Phase 3 artifacts.

**Template:** `templates/generated/false-positive-log.tmpl`

```markdown
# False Positive Log — __PROJECT_NAME__

Findings suppressed during Phase 3 security hardening. Each entry must include the original finding, justification for suppression, and re-evaluation schedule.

**Re-evaluation trigger:** Biannual security audit OR any code change to the affected file.

| # | Date | Tool | Rule ID | File:Line | Severity | Justification | Approved By | Re-evaluate By |
|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | |
```

**Storage:** `docs/test-results/[date]_false-positive-log.md`

**Builder's Guide update:** Replace "Phase 3 security audit notes" with explicit reference: "Record in the False Positive Log (`docs/test-results/[date]_false-positive-log.md`)."

#### Option B: Inline-Only Documentation

Rely solely on inline suppression comments (`# nosemgrep: rule-id`) with justification text.

**Trade-offs:**
- No additional template overhead.
- Auditor must grep source code to find all suppressions -- no centralized view.
- Cannot track re-evaluation schedule.
- Does not meet the "Organizational: approval required" provision for High/Critical suppressions.

#### Recommendation

Option A. The template is small, the storage location is natural, and centralized visibility is essential for the biannual re-evaluation requirement already in the Builder's Guide.

**Effort:** 2-3 hours
**Files Modified:** New `templates/generated/false-positive-log.tmpl`, `docs/builders-guide.md` (Step 3.2)

---

### R-P3-002: Threat Model Validation Template

**Finding:** Builder's Guide Step 3.2 item 8 says "verify every identified threat vector" but provides no structured output format. No template maps Phase 1 threats to Phase 3 validation results. SOC 2 evidence standards require per-vector documentation.

**Cross-reference:** Consolidated Pattern E (Threat Model Traceability). This remediation addresses the Phase 3 output side. Phase 1 remediation (stable threat IDs) is a prerequisite for full traceability.

#### Option A: Standalone Validation Template (Recommended)

Create `templates/generated/threat-model-validation.tmpl` mapping each threat to its validation result.

```markdown
# Threat Model Validation Report — __PROJECT_NAME__

**Phase 1 Threat Model Date:** __THREAT_MODEL_DATE__
**Validation Date:** __TODAY__
**Validator:** __VALIDATOR__ (Agent persona: Security Architect / Auditor)

## Validation Summary

| Total Threats | Mitigated & Verified | Accepted (with rationale) | Unresolved | Validation Coverage |
|---|---|---|---|---|
| | | | | |

## Per-Vector Validation

| Threat ID | Threat Description | Mitigation | Test Method | Result | Evidence Link | Notes |
|---|---|---|---|---|---|---|
| TM-001 | | | Code review / Unit test / Integration test / Manual | Pass / Fail / Accepted | `docs/test-results/...` | |
```

**Builder's Guide update:** Step 3.2 item 8 adds: "Record results in the Threat Model Validation Report (`docs/test-results/[date]_threat-model-validation.md` using the template from `templates/generated/threat-model-validation.tmpl`)."

**Storage:** `docs/test-results/[date]_threat-model-validation.md`

#### Option B: Extend Project Bible Threat Table

Add validation columns directly to the Project Bible's existing threat table.

**Trade-offs:**
- Keeps everything in one document.
- The Project Bible is a Phase 1 artifact; adding Phase 3 data to it blurs phase boundaries.
- Makes the Project Bible increasingly large and difficult to maintain.
- Does not produce a standalone audit artifact for Phase 3.

#### Recommendation

Option A. A standalone validation report is the correct audit artifact. The Project Bible should reference it ("Validation: see `docs/test-results/[date]_threat-model-validation.md`") rather than absorb it.

**Dependency:** Phase 1 remediation for stable threat IDs (TM-NNN) should precede this template's deployment for maximum traceability. However, the template is useful immediately even with informal threat references.

**Effort:** 3-4 hours
**Files Modified:** New `templates/generated/threat-model-validation.tmpl`, `docs/builders-guide.md` (Step 3.2), `templates/generated/project-bible.tmpl` (add Validation Reference column to threat table)

---

### R-P3-003: SBOM Canonical Location and Freshness

**Finding:** SBOM is listed in two locations: project root (`sbom.json`) and `docs/test-results/`. Monthly refresh is advisory with no enforcement.

#### Option A: Root as Canonical, Test-Results as Archive (Recommended)

- **Canonical location:** `sbom.json` (project root) -- always reflects current state.
- **Archive copy:** `docs/test-results/[date]_sbom.json` -- point-in-time snapshot for audit evidence.
- **Freshness enforcement:** Add a CI check comparing `sbom.json` modification date against the last dependency change (lockfile modification date).

**CI check (add to `.github/workflows/ci.yml` template):**

```yaml
- name: SBOM freshness check
  run: |
    if [ -f sbom.json ]; then
      sbom_age=$(stat -c %Y sbom.json 2>/dev/null || stat -f %m sbom.json)
      lock_age=0
      for lf in package-lock.json Pipfile.lock poetry.lock Cargo.lock go.sum; do
        if [ -f "$lf" ]; then
          this_age=$(stat -c %Y "$lf" 2>/dev/null || stat -f %m "$lf")
          [ "$this_age" -gt "$lock_age" ] && lock_age=$this_age
        fi
      done
      if [ "$lock_age" -gt "$sbom_age" ]; then
        echo "::warning::SBOM is older than lockfile. Regenerate: [your-sbom-tool] > sbom.json"
      fi
    fi
```

#### Option B: Test-Results Only

Remove root `sbom.json` reference. Store only in `docs/test-results/`.

**Trade-offs:**
- Simpler (single location).
- Breaks convention: most SBOM consumers expect the file at the project root.
- Archived copies are dated snapshots -- no "current" SBOM for automated consumers.

#### Option C: CI-Generated Only

Generate SBOM in CI on every push. Never store in repository.

**Trade-offs:**
- Always fresh.
- Not available locally for Orchestrator review.
- Requires CI infrastructure -- not available for personal/Light Track projects that may not have CI.

#### Recommendation

Option A. Root for current state, archive for audit evidence. The CI freshness check is low-cost and eliminates the "stale SBOM" risk without imposing regeneration on every commit.

**Builder's Guide update:** Clarify in Step 3.2 item 7 and Step 3.5.9: "`sbom.json` at project root is the canonical, current SBOM. Archive a dated copy to `docs/test-results/[date]_sbom.json` at Phase 3 completion."

**Effort:** 2-3 hours
**Files Modified:** `docs/builders-guide.md` (Steps 3.2, 3.5.9, Artifact Reference), CI template, `docs/governance-framework.md` (Artifact table)

---

### R-P3-005: Step 3.6 Process Checklist Coverage

**Finding:** `PHASE3_STEPS` ends at `results_archived`. Step 3.6 (analytics setup, final UAT, user docs, legal review, distribution prep) is entirely absent from process enforcement. These activities can be skipped with no detection.

**Cross-reference:** R-P3-004 addresses the legal review subset. This remediation covers the remaining Step 3.6 activities.

#### Option A: Extend PHASE3_STEPS (Recommended)

Add pre-launch preparation steps to the Phase 3 sequence:

```bash
PHASE3_STEPS=(integration_testing security_hardening chaos_testing accessibility_audit performance_audit contract_testing results_archived legal_review_complete pre_launch_prepared)
```

Where `pre_launch_prepared` is a composite step covering: final UAT session, user documentation, distribution preparation, and analytics setup (if applicable). This avoids fragmenting Step 3.6 into excessive granularity while still enforcing that pre-launch work was completed.

**Builder's Guide update:** Add process checkpoint at the end of Step 3.6:

```markdown
**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:pre_launch_prepared`
```

#### Option B: Granular Sub-Steps

Break Step 3.6 into individual process steps: `final_uat_complete`, `user_docs_written`, `legal_review_complete`, `distribution_prepared`.

**Trade-offs:**
- Maximum granularity and enforcement.
- Increases process overhead for Light Track projects where some sub-steps do not apply.
- Requires track-conditional step logic that does not currently exist in `process-checklist.sh`.

#### Option C: Track-Conditional Enforcement

Add Step 3.6 steps only for Standard+ Track projects by reading the project track from `phase-state.json`.

**Trade-offs:**
- Correct enforcement per governance tier.
- Adds complexity to `process-checklist.sh` (track-aware step arrays).
- Creates a second code path that must be tested and maintained.

#### Recommendation

Option A for immediate implementation. The composite `pre_launch_prepared` step balances enforcement with pragmatism. The Builder's Guide prose already lists the sub-activities; the process step ensures the Orchestrator attests to completing them. Option C is the correct long-term evolution but should not block the immediate fix.

**Effort:** 2-3 hours
**Files Modified:** `scripts/process-checklist.sh`, `docs/builders-guide.md` (Step 3.6)

---

### R-P3-008: Artifact Verification for Step Completion

**Finding:** `process-checklist.sh` enforces step ordering but not step evidence. Any step can be marked complete without producing the required artifact. `security_hardening` is markable without scan files existing.

**Cross-reference:** Consolidated Pattern A. This is a framework-wide issue; the remediation here addresses Phase 3 steps specifically.

#### Option A: Artifact Existence Checks in `complete_step()` (Recommended)

Add an artifact verification function called before marking high-value steps complete:

```bash
verify_step_artifacts() {
  local process="$1"
  local step="$2"

  case "${process}:${step}" in
    phase3_validation:security_hardening)
      local found=0
      for pattern in "*semgrep*" "*snyk*" "*gitleaks*"; do
        if ls docs/test-results/$pattern 2>/dev/null | grep -q .; then
          found=$((found + 1))
        fi
      done
      if [ "$found" -lt 2 ]; then
        print_fail "security_hardening requires scan artifacts in docs/test-results/"
        echo "  Expected: semgrep, snyk, and/or gitleaks results" >&2
        return 1
      fi
      ;;
    phase3_validation:results_archived)
      if [ ! -d "docs/test-results" ] || [ -z "$(ls -A docs/test-results/ 2>/dev/null)" ]; then
        print_fail "results_archived requires non-empty docs/test-results/"
        return 1
      fi
      ;;
    phase3_validation:integration_testing)
      # Check for E2E test results (Playwright report or equivalent)
      if ! ls docs/test-results/*e2e* docs/test-results/*playwright* docs/test-results/*integration* 2>/dev/null | grep -q .; then
        print_warn "No integration test results found in docs/test-results/. Proceeding with attestation only."
      fi
      ;;
    # Phase 4 steps (included for completeness -- implement alongside Phase 3)
    phase4_release:rollback_tested)
      if ! ls docs/test-results/*rollback* 2>/dev/null | grep -q .; then
        print_fail "rollback_tested requires rollback test artifact in docs/test-results/"
        return 1
      fi
      ;;
    phase4_release:handoff_written)
      if [ ! -f "HANDOFF.md" ] || [ ! -s "HANDOFF.md" ]; then
        print_fail "handoff_written requires non-empty HANDOFF.md"
        return 1
      fi
      ;;
  esac
  return 0
}
```

Insert the verification call in `complete_step()` before the jq update:

```bash
  # Verify artifacts before marking complete
  if ! verify_step_artifacts "$process" "$step_id"; then
    exit 1
  fi
```

#### Option B: Separate Verification Script

Create a standalone `verify-step-artifacts.sh` called by `complete_step()`.

**Trade-offs:**
- Cleaner separation of concerns.
- Adds another script file to maintain.
- Functionally equivalent to Option A.

#### Option C: CI-Only Verification

Move artifact checks to CI pipeline; leave `process-checklist.sh` as attestation-only.

**Trade-offs:**
- Does not block local workflow.
- Catches missing artifacts at push time, not at step completion time.
- Feedback loop is slower -- Orchestrator learns about the gap when CI fails, not when they mark the step.

#### Recommendation

Option A. Artifact verification belongs at the point of attestation, not downstream in CI. The verification function is extensible -- new steps can add cases without architectural changes. Use `print_warn` (advisory) for steps where artifact naming is unpredictable, and `print_fail` (blocking) for steps where the artifact location is well-defined.

**Design Principle:** Hard-fail on artifacts with defined naming conventions (`*semgrep*`, `HANDOFF.md`). Warn on artifacts with variable naming (`*e2e*`, `*integration*`). This avoids false negatives from unexpected file names while still catching the "marked complete with no work done" case.

**Effort:** 4-6 hours
**Files Modified:** `scripts/process-checklist.sh`

---

### R-P3-009: Penetration Testing Process Step and Tracking

**Finding:** Governance Framework requires penetration testing for Standard+ Track. No process checklist step. No APPROVAL_LOG entry. No gate check. Pen test can be skipped with no detection.

#### Option A: Track-Conditional Gate Check (Recommended)

Add penetration testing as a governance event tracked in the APPROVAL_LOG and verified at the Phase 3->4 gate.

**Changes:**

1. **`templates/generated/approval-log-org.tmpl`** -- Add section before Phase 3->4 gate:

```markdown
## Penetration Testing (Standard+ Track)

**Requirement:** Penetration testing required for Standard and Full Track before go-live. Light Track exempt unless organizational policy mandates it.
**Reference:** Governance Framework Section V (Penetration Testing).

| Field | Value |
|---|---|
| **Requirement** | Required / Exempt (Light Track) / Exemption Approved |
| **Tester** | |
| **Firm / Internal Team** | |
| **Date** | |
| **Scope** | |
| **Report Location** | |
| **Critical/High Findings** | 0 / [count] — all resolved |
| **Exemption Approver** | (if exempt: IT Security name and date) |
| **Notes** | |
```

2. **`scripts/check-phase-gate.sh`** -- Add track-conditional pen test check:

```bash
# Penetration test check (Phase 3->4, Standard+ Track)
if [ "$current_phase" -ge 3 ]; then
  project_track=""
  if [ -f "$PHASE_STATE" ] && command -v jq &>/dev/null; then
    project_track=$(jq -r '.track // ""' "$PHASE_STATE" 2>/dev/null)
  fi

  if [ "$project_track" = "standard" ] || [ "$project_track" = "full" ]; then
    if grep -q "Penetration Testing" "$APPROVAL_LOG" && \
       grep -A 20 "Penetration Testing" "$APPROVAL_LOG" | grep -qE "(Tester|Exemption Approver).*[A-Z]"; then
      echo -e "${GREEN}  [OK]${NC} Penetration testing recorded ($project_track track)"
    else
      if [ "$project_track" = "full" ]; then
        echo -e "${RED}[FAIL]${NC} Full Track requires penetration testing. No record in APPROVAL_LOG.md."
        issues=$((issues + 1))
      else
        echo -e "${YELLOW}[WARN]${NC} Standard Track: penetration testing or IT Security exemption required."
        issues=$((issues + 1))
      fi
    fi
  fi
fi
```

3. **`docs/builders-guide.md`** -- Add pen test reference after Step 3.2:

```markdown
#### Penetration Testing (Standard+ Track)

For Standard and Full Track projects, arrange penetration testing per the Governance Framework (Section V: Penetration Testing). This is a human-driven activity outside the agent workflow:

1. Engage a qualified penetration tester (internal security team or external firm).
2. Provide scope: the running application, its API surface, and the Phase 1 threat model.
3. Receive and triage the report. Resolve all Critical/High findings before Phase 4.
4. Record the engagement in APPROVAL_LOG.md (Penetration Testing section).
5. Archive the report to `docs/test-results/[date]_pentest-report.[ext]`.

Light Track projects are exempt unless organizational policy mandates testing for all production applications.
```

#### Option B: Process Checklist Step

Add `penetration_testing` to `PHASE3_STEPS` as a track-conditional step.

**Trade-offs:**
- Stronger enforcement than gate-only check.
- Requires track-conditional step logic in `process-checklist.sh`.
- Pen testing is an external, human-driven activity that may take days -- blocking the process checklist sequence for it creates operational friction.

#### Recommendation

Option A. Pen testing is a governance event (like attorney review), not a sequential process step. It happens outside the agent workflow on a timeline the Orchestrator does not control. Track it in the APPROVAL_LOG and verify at the gate. Do not block the process checklist sequence on it.

**Effort:** 3-4 hours
**Files Modified:** `templates/generated/approval-log-org.tmpl`, `scripts/check-phase-gate.sh`, `docs/builders-guide.md`

---

## 3. Minor Remediations

### R-P3-006: Load Testing Specification

**Finding:** Builder's Guide Step 3.5.7 is a single sentence with no tools, metrics, or pass/fail criteria.

**Remediation:** Expand Step 3.5.7 with tool recommendations, metrics, and pass/fail criteria:

```markdown
### Step 3.5.7: Load/Stress Testing (Full Track -- if applicable)

> **PLATFORM MODULE:** Reference your Platform Module for appropriate load testing.

**Tools:**
- Web applications: k6, Artillery, or Apache JMeter
- Desktop applications: custom stress scripts (large file handling, extended operation)
- Mobile applications: profiling tools per Platform Module

**Metrics and pass/fail criteria:**

| Metric | Target | Method |
|---|---|---|
| Concurrent users (web) | Handle expected peak load without error rate increase | Ramp from 1 to N users over 5 minutes |
| Response time (p95) | Within Data Contract latency target under load | Measure 95th percentile during sustained load |
| Error rate under load | <1% at expected peak | Monitor HTTP 5xx / unhandled exceptions |
| Memory stability | No leak over 30-minute sustained test | Monitor RSS/heap growth |
| Recovery after overload | Returns to baseline within 60 seconds | Spike to 2x peak, then drop to normal |

**Output:** Save results to `docs/test-results/[date]_load-test_[pass|fail].[ext]`.
```

**Effort:** 1-2 hours
**Files Modified:** `docs/builders-guide.md` (Step 3.5.7)

---

### R-P3-007: IT Security Dual Approval Enforcement

**Finding:** Governance requires both Application Owner and IT Security approval at the Phase 3->4 gate. `check-phase-gate.sh` uses a single grep pattern that matches either approval, not both.

**Remediation:** Replace the single pattern match with two separate checks:

```bash
# Phase 3->4 dual approval check
if [ "$current_phase" -ge 3 ]; then
  app_owner_ok=false
  it_security_ok=false

  if grep -q "Phase 3.*Phase 4.*(Application Owner)" "$APPROVAL_LOG" && \
     grep -A 15 "Application Owner" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
    app_owner_ok=true
  fi

  if grep -q "Phase 3.*Phase 4.*(IT Security)" "$APPROVAL_LOG" && \
     grep -A 15 "IT Security" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
    it_security_ok=true
  fi

  if [ "$app_owner_ok" = true ] && [ "$it_security_ok" = true ]; then
    echo -e "${GREEN}  [OK]${NC} Phase 3->4: Both Application Owner and IT Security approvals recorded"
  elif [ "$app_owner_ok" = true ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 3->4: Application Owner approved but IT Security approval missing"
    issues=$((issues + 1))
  elif [ "$it_security_ok" = true ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 3->4: IT Security approved but Application Owner approval missing"
    issues=$((issues + 1))
  fi
fi
```

**Note:** The existing template (`approval-log-org.tmpl`) already separates Application Owner and IT Security into distinct sections. The gate check just needs to verify both sections are populated.

**Effort:** 1-2 hours
**Files Modified:** `scripts/check-phase-gate.sh`

---

### R-P3-010: Security Peer Review Tracking

**Finding:** Governance Framework defines security peer review for Orchestrators with "No" or "Partially" on Security competency. No tracking mechanism exists.

**Remediation:** Add a conditional section to the APPROVAL_LOG template and a gate advisory.

**`templates/generated/approval-log-org.tmpl`** -- Add section (conditional, populated only when triggered):

```markdown
## Security Peer Review (if required)

**Trigger:** Orchestrator self-assessed "No" or "Partially" on Security in Competency Matrix (Phase 0.6).
**Reference:** Governance Framework Section V (Security Peer Review).

| Field | Value |
|---|---|
| **Required** | Yes / No (based on Competency Matrix) |
| **Reviewer** | |
| **Role** | |
| **Date** | |
| **Focus Areas Covered** | Authorization / Data Isolation / Business Logic / Auth Edge Cases / Threat Model |
| **Critical/High Findings** | 0 / [count] — all resolved |
| **Medium Findings** | 0 / [count] — documented with remediation timeline |
| **Notes** | |
```

**Gate check:** Advisory only (warn, not block). The trigger condition (Competency Matrix self-assessment) is not currently stored in machine-readable state. Until it is, the gate can only advise.

**Effort:** 1-2 hours
**Files Modified:** `templates/generated/approval-log-org.tmpl`, `scripts/check-phase-gate.sh` (advisory check)

---

### R-P3-011: Contract Testing Specification

**Finding:** Builder's Guide Step 3.5.5 has 3 bullet points with no tools, output format, or pass/fail criteria.

**Remediation:** Expand Step 3.5.5:

```markdown
### Step 3.5.5: Contract Testing (Standard+ Track)

For applications with interfaces consumed by other systems (APIs, IPC, file formats):

**What to test:**
- API endpoints return the documented schema (response shape, types, required fields)
- Error responses follow the documented error format
- Breaking changes are detected: field removal, type changes, required field additions
- File format outputs match documented specifications

**Tools:**
- REST APIs: Pact, Dredd, or schema validation against OpenAPI spec
- GraphQL: schema comparison, query validation
- File formats: JSON Schema validation, custom assertion tests
- IPC/message queues: schema registry validation

**Pass/fail criteria:**
- All documented contracts have corresponding tests
- All contract tests pass
- No undocumented breaking changes detected

**Output:** Save results to `docs/test-results/[date]_contract-tests_[pass|fail].[ext]`.
```

**Effort:** 1 hour
**Files Modified:** `docs/builders-guide.md` (Step 3.5.5)

---

### R-P3-012: Phase 3 Entry Criteria Enforcement

**Finding:** `--start-phase3` creates fresh Phase 3 state without verifying Phase 2 is complete.

**Cross-reference:** Consolidated Pattern C (Phase 2->3 Gate). This remediation is a subset of the broader Phase 2->3 gate work.

**Remediation:** Add prerequisite check to `start_phase3()`:

```bash
start_phase3() {
  ensure_state_file

  # Verify Phase 2 prerequisites
  if [ -f "$PHASE_STATE" ]; then
    local current_phase
    current_phase=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null || echo "0")
    if [ "$current_phase" -lt 2 ]; then
      print_fail "Cannot start Phase 3 — current phase is $current_phase (Phase 2 not reached)."
      exit 1
    fi
  fi

  # Verify Phase 2 init is complete
  local init_verified
  init_verified=$(jq -r '.phase2_init.verified // false' "$PROCESS_STATE" 2>/dev/null || echo "false")
  if [ "$init_verified" != "true" ]; then
    print_warn "Phase 2 initialization not verified. Run: scripts/process-checklist.sh --verify-init"
  fi

  # Proceed with Phase 3 start
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # ... existing implementation
}
```

**Effort:** 1-2 hours
**Files Modified:** `scripts/process-checklist.sh`

---

### R-P3-013: DAST as Explicit Step

**Finding:** Governance includes ZAP in the standard toolchain. Builder's Guide does not list DAST as a numbered step -- only mentions it in the results archive list ("if applicable").

**Remediation:** Add DAST as a sub-item under Step 3.2 for web applications:

```markdown
5b. **DAST scan (web applications):**
    ```bash
    # OWASP ZAP baseline scan
    docker run -t owasp/zap2docker-stable zap-baseline.py -t http://localhost:3000
    ```
    For non-web platforms, DAST may not apply. Reference your Platform Module.
```

**Rationale:** DAST is already in the results archive list and the governance toolchain table. Making it explicit in Step 3.2 closes the gap without adding a new process step.

**Effort:** 30 minutes
**Files Modified:** `docs/builders-guide.md` (Step 3.2)

---

### R-P3-015: Accessibility Threshold Consistency

**Finding:** Builder's Guide Step 3.4 defines core requirements but no numeric threshold. User Guide adds "Lighthouse 90+" as a target. Threshold is split between documents.

**Remediation:** Add the numeric threshold to Builder's Guide Step 3.4:

```markdown
**Pass/fail criteria (web applications):** Lighthouse Accessibility score >= 90. All core accessibility requirements above must pass regardless of score. For non-web platforms, pass/fail is based on the core requirements list (no equivalent single-number score exists).
```

Update User Guide to reference Builder's Guide as the authoritative source rather than defining its own threshold.

**Effort:** 30 minutes
**Files Modified:** `docs/builders-guide.md` (Step 3.4), `docs/user-guide.md`

---

### R-P3-016: Phase 2->3 Gate in `check-phase-gate.sh`

**Finding:** `check-phase-gate.sh` checks gates 0->1, 1->2, and 3->4 but not 2->3. The most consequential transition is unchecked.

**Cross-reference:** Consolidated Pattern C. This is the mechanical implementation gap.

**Remediation:** Add Phase 2->3 gate extraction and consistency check:

```bash
gate_2_to_3=$(get_gate_date "phase_2_to_3")

# Check: if current_phase >= 3, gate 2->3 should have a date
if [ "$current_phase" -ge 3 ]; then
  if [ -n "$gate_2_to_3" ]; then
    # Note: Phase 2->3 may not have a dedicated APPROVAL_LOG section.
    # The gate is developer-attested in phase-state.json.
    # Verify that test-gate.sh would pass (bug severity check).
    echo -e "${GREEN}  [OK]${NC} Phase 2->3: gate dated $gate_2_to_3"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2->3: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi
```

**Note:** The Phase 2->3 gate is structurally different from other gates -- it does not have a dedicated APPROVAL_LOG section (the Orchestrator attests to feature completeness; the bug gate is checked by `test-gate.sh`). The consistency check verifies that the date was recorded, not that an external approver signed off. Adding full Phase 2->3 approval log tracking is a separate remediation (Consolidated Pattern C, item C3).

**Effort:** 1-2 hours
**Files Modified:** `scripts/check-phase-gate.sh`

---

### R-P3-020: Re-Run Protocol After Major Remediation

**Finding:** No guidance on which Phase 3 steps to re-run after a security fix. `--reset phase3_validation` is all-or-nothing.

#### Option A: Selective Reset with Documented Protocol (Recommended)

Add `--reset-from` command to `process-checklist.sh` and document a re-run protocol in the Builder's Guide.

**`process-checklist.sh` addition:**

```bash
--reset-from)  ACTION="reset-from"; ARG_VALUE="$2"; shift 2 ;;
```

```bash
reset_from() {
  local input="$1"
  local process step_id
  process="${input%%:*}"
  step_id="${input#*:}"

  local steps_str
  steps_str=$(get_steps_for_process "$process")
  local steps=()
  read -ra steps <<< "$steps_str"

  local target_index=-1
  for i in "${!steps[@]}"; do
    if [ "${steps[$i]}" = "$step_id" ]; then
      target_index=$i
      break
    fi
  done

  if [ "$target_index" -eq -1 ]; then
    print_fail "Unknown step '$step_id' for process '$process'"
    exit 1
  fi

  # Remove this step and all subsequent steps from completed list
  local keep_steps=()
  for ((i = 0; i < target_index; i++)); do
    if step_is_completed "$process" "${steps[$i]}"; then
      keep_steps+=("${steps[$i]}")
    fi
  done

  jq --argjson steps "$(printf '%s\n' "${keep_steps[@]}" | jq -R . | jq -s .)" \
    ".${process}.steps_completed = \$steps | .${process}.step = (\$steps | length)" \
    "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"

  print_ok "Reset $process from step '$step_id' onward"
  print_info "Next: scripts/process-checklist.sh --complete-step ${process}:${step_id}"
}
```

**Builder's Guide addition (after Phase 3 Remediation table):**

```markdown
#### Re-Run Protocol

After fixing a security finding or major bug during Phase 3:

| Change Type | Re-Run From | Rationale |
|---|---|---|
| Security fix (code change) | `security_hardening` | Re-run SAST/dependency scans to confirm fix and detect regressions |
| Accessibility fix (UI change) | `accessibility_audit` | Re-verify all accessibility criteria |
| Performance fix (optimization) | `performance_audit` | Re-measure against baselines |
| Logic fix (behavior change) | `integration_testing` | Full re-run -- behavior change may affect any test type |
| Dependency update | `security_hardening` | Re-run dependency scan and SBOM regeneration |

Use selective reset: `scripts/process-checklist.sh --reset-from phase3_validation:STEP`
This preserves completed steps before the reset point.
```

#### Option B: Document-Only Protocol

Add the re-run guidance table without implementing `--reset-from`. Orchestrator uses `--reset phase3_validation` and re-completes all steps.

**Trade-offs:**
- Zero code changes.
- Wastes time re-completing steps that were unaffected by the fix.
- Acceptable for the first framework iteration if code effort is constrained.

#### Recommendation

Option A. The `--reset-from` command is a straightforward extension of the existing reset logic and eliminates the frustration of losing all Phase 3 progress for a targeted fix.

**Effort:** 3-4 hours
**Files Modified:** `scripts/process-checklist.sh`, `docs/builders-guide.md` (Phase 3 Remediation section)

---

## 4. Observation Remediations

### R-P3-014: Remediation Table Priority Ordering

**Finding:** Builder's Guide Phase 3 Remediation table lists 6 issue types with no severity or blocking indication.

**Remediation:** Add a "Blocks Phase 4?" column:

| Issue | Detection | Response | Blocks Phase 4? |
|---|---|---|---|
| Logic Drift | App works but doesn't solve the Phase 0 problem | Re-align with Manifesto | Yes |
| Silent Errors | App fails without user feedback | Error boundaries | Yes |
| Security Regression | Change broke auth or data isolation | Full security audit | Yes |
| Accessibility Failures | Below target scores or broken navigation | Address every finding | Yes (if below threshold) |
| Performance Regression | Below target on any metric | Profile and address | Conditional (if SLA-bound) |
| Cross-Platform Failure | Works on one platform, broken on another | Fix all platforms | Yes |

**Effort:** 15 minutes
**Files Modified:** `docs/builders-guide.md` (Phase 3 Remediation table)

---

### R-P3-017: Evaluation Prompt References in Phase 3

**Finding:** Evaluation prompts `03-security.md` and `06-red-team-review.md` exist but Builder's Guide Phase 3 does not reference them. An Orchestrator following the guide step-by-step will not encounter them.

**Remediation:** Add a callout after Step 3.2 (Security Hardening):

```markdown
> **Evaluation Prompts:** After completing automated security scans, consider running the Security Review (`evaluation-prompts/Projects/bases/03-security.md`) and Red Team Evaluation (`evaluation-prompts/Projects/bases/06-red-team-review.md`) for an independent assessment. These prompts provide structured adversarial review that complements automated tooling. Compose with your platform module: `bash evaluation-prompts/Projects/compose.sh`.
```

**Effort:** 15 minutes
**Files Modified:** `docs/builders-guide.md` (after Step 3.2)

---

### R-P3-018: Phase 3 Commit Enforcement Blocking Fix Commits

**Finding:** `process-checklist.sh` blocks all source commits during Phase 3 until all steps are done. This contradicts "fix critical findings first, re-run" -- the Orchestrator must complete all testing before committing any fixes.

**Remediation:** Allow source commits during Phase 3 if the build loop has completed but Phase 3 steps are in progress. Modify the Phase 3 source commit check:

```bash
# Phase 3 source commit checks
if [ "$current_phase" -eq 3 ]; then
  local p3_started
  p3_started=$(jq -r '.phase3_validation.started_at // "null"' "$PROCESS_STATE")

  if [ "$p3_started" = "null" ]; then
    print_fail "Phase 3 not started. Run: scripts/process-checklist.sh --start-phase3"
    exit 1
  fi

  # During Phase 3, allow commits for fixes discovered during validation.
  # The commit message should reference the Phase 3 step that identified the issue.
  # Full step completion is still required before Phase 4.
  local p3_completed
  p3_completed=$(jq '.phase3_validation.steps_completed | length' "$PROCESS_STATE")
  local p3_total=${#PHASE3_STEPS[@]}

  if [ "$p3_completed" -lt "$p3_total" ]; then
    print_warn "Phase 3 in progress ($p3_completed/$p3_total steps). Fix commits allowed."
    print_info "Complete all Phase 3 steps before proceeding to Phase 4."
  fi
fi
```

**Trade-off:** This relaxes enforcement during Phase 3. The risk is that non-fix commits could slip through. The mitigation is that Phase 3 steps must still all be completed before Phase 4, and the re-run protocol (R-P3-020) ensures affected steps are re-validated.

**Effort:** 1 hour
**Files Modified:** `scripts/process-checklist.sh`

---

### R-P3-019: Platform Module Checklists in Process Checklist

**Finding:** Platform modules add security checks but `security_hardening` is a single boolean. Platform-specific checks are advisory within the step.

**Remediation:** No code change. Document the design decision:

Add a comment in `process-checklist.sh`:

```bash
# NOTE: Platform module checklists are advisory within each step.
# The agent instructions reference platform modules at each Phase 3 step.
# Granular per-platform enforcement is deferred to framework v2
# (requires platform-aware step arrays from phase-state.json).
```

Add a note in the Builder's Guide Phase 3 introduction:

```markdown
> **Platform Modules:** Each step references your Platform Module for platform-specific requirements. The process checklist tracks step completion at the phase level; platform-specific sub-checks are part of the agent's instructions within each step. The agent should confirm platform module requirements are met before marking each step complete.
```

**Effort:** 15 minutes
**Files Modified:** `scripts/process-checklist.sh` (comment), `docs/builders-guide.md` (Phase 3 intro)

---

## 5. Dependency Map

The following dependencies constrain implementation order:

```
R-P3-004 (attorney review) ─── depends on ──→ R-P3-005 (Step 3.6 in checklist)
    Both modify PHASE3_STEPS array. Implement together.

R-P3-008 (artifact verification) ─── independent
    Can be implemented at any time. Benefits all other step-related fixes.

R-P3-009 (pen test tracking) ─── depends on ──→ R-P3-007 (dual approval)
    Both modify check-phase-gate.sh Phase 3→4 section. Implement together.

R-P3-002 (threat model template) ─── soft dependency ──→ Phase 1 threat IDs
    Useful immediately; full traceability requires Phase 1 remediation.

R-P3-020 (re-run protocol) ─── depends on ──→ R-P3-018 (allow fix commits)
    Re-run protocol assumes fix commits are allowed during Phase 3.

R-P3-012 (entry criteria) ─── depends on ──→ R-P3-016 (Phase 2→3 gate)
    Entry validation should align with gate check logic.
```

---

## 6. Verification Test Plan

### Critical

| Test ID | Finding | Test | Method | Expected Result |
|---|---|---|---|---|
| V-004a | P3-004 | Privacy Policy present, no legal review entry | `check-phase-gate.sh` | FAIL: "Legal documents present but no attorney review recorded" |
| V-004b | P3-004 | Legal review entry with empty reviewer field | `check-phase-gate.sh` | FAIL: reviewer field validation fails |
| V-004c | P3-004 | Mark `legal_review_complete` without APPROVAL_LOG entry | `process-checklist.sh` | Step completes (attestation), gate catches at Phase 4 entry |
| V-004d | P3-004 | No legal documents in project | `check-phase-gate.sh` | PASS: legal review check skipped |

### Major

| Test ID | Finding | Test | Method | Expected Result |
|---|---|---|---|---|
| V-001 | P3-001 | Create false positive log using template | Manual | Template generates valid log with all required fields |
| V-002 | P3-002 | Create threat model validation report | Manual | Template maps all Phase 1 threats to Phase 3 validation results |
| V-003a | P3-003 | Modify lockfile, check SBOM freshness | CI check | WARN: "SBOM is older than lockfile" |
| V-003b | P3-003 | Regenerate SBOM after lockfile change | CI check | PASS: no warning |
| V-005a | P3-005 | Mark `results_archived`, attempt Phase 4 | `process-checklist.sh` | FAIL: `legal_review_complete` not yet completed |
| V-005b | P3-005 | Complete all steps including `pre_launch_prepared` | `process-checklist.sh` | PASS: all Phase 3 steps complete |
| V-008a | P3-008 | Mark `security_hardening` with empty `docs/test-results/` | `process-checklist.sh` | FAIL: "security_hardening requires scan artifacts" |
| V-008b | P3-008 | Mark `security_hardening` with semgrep and snyk files present | `process-checklist.sh` | PASS |
| V-008c | P3-008 | Mark `results_archived` with empty `docs/test-results/` | `process-checklist.sh` | FAIL: "results_archived requires non-empty docs/test-results/" |
| V-009a | P3-009 | Standard Track, no pen test record | `check-phase-gate.sh` | WARN: "penetration testing or IT Security exemption required" |
| V-009b | P3-009 | Full Track, no pen test record | `check-phase-gate.sh` | FAIL: "Full Track requires penetration testing" |
| V-009c | P3-009 | Standard Track, IT Security exemption recorded | `check-phase-gate.sh` | PASS |

### Minor

| Test ID | Finding | Test | Method | Expected Result |
|---|---|---|---|---|
| V-007 | P3-007 | Only App Owner approval, no IT Security | `check-phase-gate.sh` | WARN: "IT Security approval missing" |
| V-012 | P3-012 | `--start-phase3` with current_phase < 2 | `process-checklist.sh` | FAIL: "Cannot start Phase 3" |
| V-016 | P3-016 | Phase 3 reached, no `phase_2_to_3` date | `check-phase-gate.sh` | WARN: "gate date not recorded" |
| V-020a | P3-020 | `--reset-from phase3_validation:security_hardening` | `process-checklist.sh` | Steps before `security_hardening` preserved; steps from `security_hardening` onward cleared |
| V-020b | P3-020 | `--reset-from` with invalid step | `process-checklist.sh` | FAIL: "Unknown step" |

### Observation

| Test ID | Finding | Test | Method | Expected Result |
|---|---|---|---|---|
| V-018 | P3-018 | Source commit during Phase 3 (steps in progress) | `process-checklist.sh --check-commit-ready` | WARN (not FAIL): "Phase 3 in progress. Fix commits allowed." |

---

## 7. Implementation Schedule

### Week 1: Critical and High-Value Major (16-22 hours)

| Day | Remediation | Hours | Rationale |
|---|---|---|---|
| 1-2 | R-P3-004 + R-P3-005 (attorney review + Step 3.6 coverage) | 6-8 | Highest liability; both modify PHASE3_STEPS -- implement together |
| 2-3 | R-P3-008 (artifact verification) | 4-6 | Transforms enforcement from ordering to evidence across all phases |
| 3-4 | R-P3-009 + R-P3-007 (pen test tracking + dual approval) | 4-6 | Both modify check-phase-gate.sh Phase 3->4 section |
| 4 | R-P3-016 (Phase 2->3 gate) | 1-2 | Quick win; closes the "most consequential gate" gap |

### Week 2: Remaining Major and Templates (10-14 hours)

| Day | Remediation | Hours | Rationale |
|---|---|---|---|
| 1 | R-P3-001 (false positive log template) | 2-3 | Template creation, Builder's Guide update |
| 1-2 | R-P3-002 (threat model validation template) | 3-4 | Template creation, Builder's Guide update, Project Bible cross-reference |
| 2 | R-P3-003 (SBOM location + freshness) | 2-3 | Documentation clarification, CI check |
| 3 | R-P3-020 + R-P3-018 (re-run protocol + fix commits) | 4 | Implement together -- re-run assumes fix commits are allowed |

### Week 3: Minor Items (8-12 hours)

| Day | Remediation | Hours |
|---|---|---|
| 1 | R-P3-006 (load testing spec) | 1-2 |
| 1 | R-P3-011 (contract testing spec) | 1 |
| 1 | R-P3-013 (DAST step) | 0.5 |
| 1 | R-P3-015 (accessibility threshold) | 0.5 |
| 2 | R-P3-010 (security peer review tracking) | 1-2 |
| 2 | R-P3-012 (Phase 3 entry criteria) | 1-2 |
| 2 | R-P3-014, R-P3-017, R-P3-019 (observations) | 1 |

---

## 8. Risk Assessment

### Risks of Remediation

| Risk | Severity | Mitigation |
|---|---|---|
| **Overenforcement friction** -- too many hard gates slow Orchestrator velocity | Medium | Use `print_warn` (advisory) for uncertain artifact matches; `print_fail` (blocking) only for well-defined artifacts. Keep composite steps (`pre_launch_prepared`) rather than fragmenting into sub-steps. |
| **Track-conditional logic complexity** -- adding track awareness to scripts increases maintenance burden | Medium | Limit track-conditional behavior to `check-phase-gate.sh` (gate checks). Keep `process-checklist.sh` track-agnostic for now. Track-aware step arrays are a v2 feature. |
| **False artifact matches** -- glob patterns like `*semgrep*` may match unrelated files | Low | Use the `docs/test-results/` directory scope (not project-wide). File naming convention is already defined in Step 3.5.9. |
| **Breaking existing projects** -- changing PHASE3_STEPS array invalidates in-progress Phase 3 state | Medium | Add migration logic: if `process-state.json` has Phase 3 steps from the old array, preserve them. New steps are appended; existing completions are not lost. |

### Risks of Non-Remediation

| Risk | Severity | Consequence |
|---|---|---|
| **AI-generated Privacy Policy deployed without legal review (P3-004)** | Critical | Regulatory enforcement action, contractual liability, reputational damage. The framework's own documentation identifies this risk -- failing to enforce it is a governance failure, not a development oversight. |
| **Pen test requirement silently skipped (P3-009)** | High | Standard/Full Track projects deployed without required security assessment. If a breach occurs, the organization cannot demonstrate due diligence. |
| **Self-attestation remains the norm (P3-008)** | High | Process enforcement provides false assurance. An audit would find that steps were "completed" without evidence of execution. |
| **Phase 2->3 transition unchecked (P3-016)** | High | Incomplete Phase 2 work enters validation. Validation findings may be Phase 2 defects, not Phase 3 issues, wasting remediation effort. |

---

## Appendix A: Files Modified Summary

| File | Findings Addressed | Change Type |
|---|---|---|
| `scripts/process-checklist.sh` | P3-004, P3-005, P3-008, P3-012, P3-018, P3-019, P3-020 | Step array, artifact verification, entry criteria, reset-from, fix commits |
| `scripts/check-phase-gate.sh` | P3-004, P3-007, P3-009, P3-010, P3-016 | Legal review gate, dual approval, pen test gate, peer review advisory, Phase 2->3 gate |
| `docs/builders-guide.md` | P3-001, P3-002, P3-003, P3-004, P3-005, P3-006, P3-009, P3-011, P3-013, P3-014, P3-015, P3-017, P3-019, P3-020 | Templates referenced, steps expanded, process checkpoints added, re-run protocol |
| `templates/generated/approval-log-org.tmpl` | P3-004, P3-009, P3-010 | Legal review section, pen test section, peer review section |
| `templates/generated/approval-log-personal.tmpl` | P3-004 | Advisory note for public deployments |
| `docs/governance-framework.md` | P3-003 | SBOM artifact table clarification |
| `docs/user-guide.md` | P3-015 | Accessibility threshold cross-reference |
| New: `templates/generated/false-positive-log.tmpl` | P3-001 | False positive documentation template |
| New: `templates/generated/threat-model-validation.tmpl` | P3-002 | Per-vector validation report template |
| CI template | P3-003 | SBOM freshness check |

## Appendix B: Cross-References to Consolidated Patterns

| Finding | Consolidated Pattern | Notes |
|---|---|---|
| P3-008 | Pattern A (Self-Attestation) | Phase 3 instance of framework-wide issue |
| P3-004 | Standalone (highest severity in framework) | No cross-phase equivalent |
| P3-016, P3-012 | Pattern C (Phase 2->3 Gate) | Subset of broader gate remediation |
| P3-002 | Pattern E (Threat Traceability) | Phase 3 output side; Phase 1 input side is separate |
| P3-020 | Pattern G (Gate Denial/Rework) | Phase 3 instance of rework path gap |
| P3-018 | Standalone | Unique to Phase 3 commit enforcement model |

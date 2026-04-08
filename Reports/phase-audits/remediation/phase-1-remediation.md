# Phase 1 Remediation Plan
## Architecture & Technical Planning

**Source Audit:** `Reports/phase-audits/2026-04-08-phase-1-audit.md`
**Date:** 2026-04-08
**Framework Version:** Solo Orchestrator v1.0 (post-PR #6, #7)
**Audience:** C-Suite, Enterprise Architecture, IT Security, Internal Audit

---

## Executive Summary

Phase 1 (Architecture & Technical Planning) received 16 findings: 0 Critical, 5 Major, 7 Minor, 4 Observation. The five Major findings cluster around two themes: (1) architecture decisions are made without structured evaluation criteria, leaving gate reviewers no basis to challenge selections; and (2) critical workflow paths -- gate denial, self-review risk, and threat model traceability -- are undefined or unverifiable.

This remediation plan provides concrete options for each finding, with trade-off analysis, specific file changes, acceptance criteria, and verification tests. Findings are grouped by severity, then ordered by dependency (some remediations unlock others).

**Estimated total effort:** 28-48 hours across all findings (Major: 20-34 hours, Minor: 6-10 hours, Observation: 2-4 hours).

---

## Table of Contents

1. [Major Findings (P1-001 through P1-005)](#major-findings)
2. [Minor Findings (P1-006 through P1-012)](#minor-findings)
3. [Observation Findings (P1-013 through P1-016)](#observation-findings)
4. [Implementation Sequencing](#implementation-sequencing)
5. [Consolidated Verification Test Plan](#consolidated-verification-test-plan)

---

## Major Findings

---

### P1-001: Architecture Option Evaluation Has No Defined Rubric

**Severity:** Major | **Category:** Missing Validation
**Evidence:** `builders-guide.md:525-561` -- 3 options evaluated across 10 categories, but no scoring matrix, no weighting, no minimum thresholds.
**Risk:** Selection is entirely subjective. Gate reviewer has no objective basis to challenge. Two Orchestrators evaluating the same options could reach opposite conclusions with no way to compare reasoning. For organizational deployments, the Senior Technical Authority is asked to approve a decision they cannot reconstruct.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Weighted Scoring Matrix Template** | Create a new template (`arch-evaluation-matrix.tmpl`) with the 10 existing categories as rows, 3 options as columns, a 1-5 scoring scale, and configurable category weights. Add instructions to `builders-guide.md` Step 1.2 requiring the Orchestrator to complete the matrix before selection. Gate reviewer validates scores. | 4-6 hrs | Full traceability. Adds ~20 minutes to Phase 1. Risk of false precision -- scores feel more rigorous than they are when one person assigns them all. |
| **B. Structured Rationale Without Scores** | Extend the ADR template to require a mandatory "Options Evaluated" section with a comparison table (category x option) and a "Selection Rationale" paragraph for each category explaining why the chosen option was preferred. No numeric scores. | 3-4 hrs | Lighter process. Captures reasoning without false precision. Gate reviewer can still challenge rationale. Does not support cross-project comparison of decision rigor. |
| **C. Decision Record with Minimum Viable Rubric** | Require only the top 4 critical categories (maintenance burden, security posture, budget fit, platform compatibility) to have explicit scored comparison. Remaining 6 categories documented in prose. | 3-5 hrs | Balanced approach. Forces rigor where it matters most (the categories that cause the most expensive Phase 2 rework). Lighter than Option A. |

#### Recommendation

**Option C** -- the minimum viable rubric. The 10-category matrix in Option A creates a false sense of objectivity for a single-person decision. The four categories selected for scoring are the ones where Phase 2 rework is most expensive: an architecture that the solo maintainer cannot maintain (maintenance burden), that has unaddressed attack surfaces (security posture), that exceeds the budget ceiling (budget fit), or that does not work on the target platform (platform compatibility). Prose for the remaining six categories captures reasoning without turning a 4-8 hour phase into a scoring exercise.

If the organization plans to compare architecture decisions across multiple Solo Orchestrator projects (portfolio-level governance), upgrade to Option A. The scoring matrix enables cross-project comparison of decision rigor.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `templates/generated/arch-evaluation-matrix.tmpl` | **Create** | New template: 4 scored categories (1-5 scale) + 6 prose categories, 3 option columns, weight column, total row, selection rationale section |
| `templates/generated/adr.tmpl` | Modify | Add "Options Evaluated" section with reference to the evaluation matrix (see also P1-002) |
| `docs/builders-guide.md` | Modify | Step 1.2: add instruction to complete the evaluation matrix before selecting. Add matrix template reference. Update decision gate language to require matrix as gate input |
| `templates/generated/project-bible.tmpl` | Modify | Section 3 (Architecture Decision Record): add reference to evaluation matrix artifact |

#### Acceptance Criteria

1. A gate reviewer can open the evaluation matrix and see numeric scores for maintenance burden, security posture, budget fit, and platform compatibility for all 3 options.
2. The selected option has the highest weighted score, OR the selection rationale explicitly explains why a lower-scoring option was chosen (documented trade-off override).
3. A new project created with `init.sh` generates the matrix template in `docs/ADR documentation/`.
4. The Phase 1->2 gate reviewer can reconstruct the decision from the matrix alone, without asking the Orchestrator.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-001a | Architecture selected without matrix | Attempt Phase 1->2 gate without `arch-evaluation-matrix.md` | Gate reviewer instructions flag missing artifact |
| V-P1-001b | Matrix with blank scores | Submit matrix with empty score cells for scored categories | Gate reviewer rejects: "scored categories incomplete" |
| V-P1-001c | Lower-scoring option selected without override rationale | Select option scoring 12/20 over option scoring 16/20 with no explanation | Gate reviewer rejects: "selection contradicts matrix without documented rationale" |

---

### P1-002: ADR Template Lacks Architecture Comparison Structure

**Severity:** Major | **Category:** Missing Template
**Evidence:** `templates/generated/adr.tmpl` -- 18 lines, 3 sections (Context, Decision, Consequences). No rejected alternatives, no options evaluated, no selection criteria.
**Risk:** Project Bible Section 3 expects "rejected alternatives with rationale" but the ADR template has no place to record them. The full ADR and the Bible section are structurally misaligned. An auditor reviewing the ADR sees a decision without context for what was considered.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Extend Existing Template** | Add 3 new sections to `adr.tmpl`: "Options Considered" (table), "Evaluation Summary" (reference to matrix from P1-001), "Rejected Alternatives" (per-option rationale). Keep the existing 3 sections. | 2-3 hrs | Non-breaking. Existing ADRs remain valid. New ADRs are more complete. Template grows from 18 to ~45 lines. |
| **B. Two-Tier ADR Templates** | Create `adr-architecture.tmpl` (full comparison structure) and keep `adr.tmpl` as-is for smaller in-phase decisions (e.g., "switched from library X to library Y"). Architecture ADR is Phase 1 only; lightweight ADR is Phase 2+. | 3-4 hrs | Right-sized templates. Architecture decisions get full treatment. Routine decisions are not burdened with comparison structure. Adds complexity: Orchestrator must choose the right template. |
| **C. Single Extended Template with Optional Sections** | One template with comparison sections marked `<!-- Include for architecture selections. Remove for in-phase decisions. -->`. | 2-3 hrs | Single template, clear guidance on when to include comparison sections. Risk: Orchestrators always remove the optional sections because it is easier. |

#### Recommendation

**Option B** -- two-tier ADR templates. The Phase 1 architecture selection is fundamentally different from a Phase 2 in-flight decision to change a library. Forcing the same structure on both creates either overhead (comparison table for trivial decisions) or under-documentation (no comparison for consequential ones). The architecture ADR is produced once; the lightweight ADR is produced many times. Optimizing for the common case (lightweight) while requiring rigor for the high-stakes case (architecture) is the correct design.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `templates/generated/adr-architecture.tmpl` | **Create** | Full ADR: Status, Date, Context, Options Considered (table), Evaluation Summary (reference to matrix), Decision, Rejected Alternatives (per-option with rationale), Consequences, Review Notes |
| `templates/generated/adr.tmpl` | Modify | Add header comment clarifying this is the lightweight template for in-phase decisions. Add optional "Alternatives Considered" section (1-2 lines per alternative) |
| `docs/builders-guide.md` | Modify | Step 1.2: reference `adr-architecture.tmpl` for the Phase 1 selection. Step 2.x ADR references: clarify that in-phase ADRs use the lightweight template |
| `templates/generated/project-bible.tmpl` | Modify | Section 3: update reference from `adr.tmpl` to `adr-architecture.tmpl` for the initial architecture ADR |
| `docs/builders-guide.md` Appendix A | Modify | Add `adr-architecture.tmpl` to the artifact table |

#### Acceptance Criteria

1. Phase 1 architecture ADR contains: Options Considered table, Evaluation Summary referencing the matrix, Rejected Alternatives with per-option rationale, and Consequences.
2. Phase 2 in-flight ADRs use the lightweight template and do not require a full comparison matrix.
3. Project Bible Section 3 references the architecture ADR and the rejected alternatives are consistent between Bible and ADR.
4. `init.sh` copies both ADR templates to the project's ADR directory.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-002a | Phase 1 ADR with lightweight template | Create architecture ADR using `adr.tmpl` instead of `adr-architecture.tmpl` | Gate reviewer flags: "architecture ADR must use full template" |
| V-P1-002b | Architecture ADR missing rejected alternatives | Submit ADR with empty "Rejected Alternatives" section | Gate reviewer rejects: "rejected alternatives required" |
| V-P1-002c | Bible Section 3 inconsistent with ADR | Bible lists Option B as rejected, ADR does not mention Option B | Gate reviewer flags inconsistency |

---

### P1-003: STRIDE Threat Model Not Structured for Phase 3 Traceability

**Severity:** Major | **Category:** Workflow Gap
**Evidence:** `project-bible.tmpl:56-68` -- threat table uses sequential `#` column and `Verified (Phase 3)` checkbox. No stable threat IDs. No validation reference column linking to Phase 3 results.
**Risk:** Cannot trace from a Phase 1 threat to a Phase 3 validation result mechanically. An auditor cannot confirm that threat #3 was validated by `docs/test-results/2026-05-15_threat-validation_pass.md` without manual cross-referencing. SOC 2 Type II completeness and accuracy evidence standards require mechanical traceability.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Stable IDs + Validation Reference Column** | Replace `#` with `TM-NNN` IDs. Add "Validation Evidence" column linking to Phase 3 test result files. Add `check-phase-gate.sh` validation at Phase 3->4 gate that every TM-NNN has a non-empty validation reference. | 4-6 hrs | Full traceability. Mechanical enforcement. Adds a column to the threat table and a gate check. Requires the Phase 3 agent to update the Bible's threat table with validation references after each validation test. |
| **B. Stable IDs Only (No Mechanical Check)** | Replace `#` with `TM-NNN` IDs. Add "Validation Evidence" column. No script enforcement -- gate reviewer checks manually. | 2-3 hrs | Lighter implementation. Depends on gate reviewer diligence. Fails the SOC 2 requirement for mechanical evidence. |
| **C. Separate Threat-Validation Traceability Matrix** | Keep the Bible threat table as-is. Create a new `docs/threat-validation-matrix.md` file populated in Phase 3, mapping each threat to its validation evidence. Gate check verifies the matrix is complete. | 5-7 hrs | Separates concerns: Phase 1 owns the threat model, Phase 3 owns the validation matrix. Avoids modifying the Bible during Phase 3. Risk: two documents that can drift. |

#### Recommendation

**Option A** -- stable IDs with validation reference column. The Bible is already the single source of truth for threats. Adding a validation evidence column keeps the traceability in one place rather than creating a second document that drifts. The mechanical check at the Phase 3->4 gate is essential: without it, validation is attestation, not evidence. The effort difference between B and A is small (2-3 hours of scripting) but the assurance difference is large.

The `TM-NNN` ID scheme also enables cross-referencing from Phase 2 security audit findings (Step 2.4) back to the threat model, which currently has no mechanism.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `templates/generated/project-bible.tmpl` | Modify | Section 4: replace `#` column with `ID` column using `TM-NNN` format. Add `Validation Evidence` column after `Verified (Phase 3)`. Add instructions: "Each threat receives a stable ID (TM-001, TM-002, ...). The Validation Evidence column is populated during Phase 3.2 with the path to the test result file that validates the mitigation." |
| `docs/builders-guide.md` | Modify | Step 1.3: instruct the agent to assign `TM-NNN` IDs. Step 3.2 (Phase 3): instruct the agent to update the Bible threat table with validation evidence references |
| `scripts/check-phase-gate.sh` | Modify | Phase 3->4 gate: add check that `PROJECT_BIBLE.md` Section 4 has no empty "Validation Evidence" cells. Parse the threat table and flag any row where `TM-NNN` exists but validation evidence is blank |
| `docs/governance-framework.md` | Modify | Add traceability expectation: "Each Phase 1 threat (TM-NNN) must be traced to a Phase 3 validation result before Phase 4 approval" |

#### Acceptance Criteria

1. Every threat in the Bible's Section 4 has a stable `TM-NNN` ID.
2. After Phase 3 validation, every `TM-NNN` row has a non-empty "Validation Evidence" cell referencing a file in `docs/test-results/`.
3. `check-phase-gate.sh` at Phase 3->4 fails if any `TM-NNN` row has blank validation evidence.
4. Phase 2 security audit findings (Step 2.4) can reference `TM-NNN` IDs when a security finding maps to a known threat.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-003a | Threat table with `#` instead of `TM-NNN` | Create Bible with old-style sequential numbers | Template itself uses `TM-NNN`; old-style is no longer the default |
| V-P1-003b | Phase 3->4 gate with blank validation evidence | Run `check-phase-gate.sh` with one `TM-NNN` row having empty validation evidence | Fails: "TM-003 missing validation evidence" |
| V-P1-003c | End-to-end traceability | Create TM-001 in Phase 1, validate in Phase 3, run gate check | Passes: auditor can trace TM-001 from threat table to `docs/test-results/2026-05-15_tm-001-spoofing_pass.md` |

---

### P1-004: No Defined Rework Path When Phase 1->2 Gate Denied

**Severity:** Major | **Category:** Workflow Gap
**Evidence:** `builders-guide.md:678` and `governance-framework.md:168` -- the Phase 1->2 gate approver can choose "Approved / Needs revision" but there is no procedure for what happens on "Needs revision." No denial entry format in the Approval Log. No written findings requirement. No maximum rework cycles. No escalation path for repeated denial.
**Risk:** A denied gate creates operational ambiguity. The Orchestrator does not know what to fix, the reviewer has no structured way to communicate findings, and there is no audit trail that the denial happened, what was wrong, or whether the rework addressed the issues. Repeated denials could cycle indefinitely with no escalation trigger.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Full Denial Procedure** | Define: (1) Approval Log denial entry format with structured findings, (2) maximum 2 rework cycles before escalation, (3) escalation path (Senior Technical Authority -> Project Sponsor -> CIO), (4) rework scope must be constrained to reviewer findings (no scope creep during rework). Apply to all gates (Phase 0->1, 1->2, 3->4). | 4-6 hrs | Complete coverage. Prevents infinite rework loops. Creates audit trail for denials. Adds process overhead for what may be a rare event. |
| **B. Denial Entry Only** | Add a "Needs Revision" entry format to the Approval Log templates with a "Findings" field. No rework cycle limits. No escalation. | 2-3 hrs | Minimal viable fix. Captures the denial and the reason. Does not prevent infinite loops. Acceptable for personal projects where the Orchestrator self-reviews. |
| **C. Denial Procedure for Org Only** | Full denial procedure (Option A) for organizational deployments only. Personal projects get the denial entry format (Option B) and a recommendation to seek external review after 2 self-review cycles. | 4-5 hrs | Right-sized: organizational projects get governance rigor, personal projects get lightweight recording. Matches the framework's existing personal/org distinction pattern. |

#### Recommendation

**Option C** -- denial procedure for organizational deployments, lightweight entry for personal. The governance framework already distinguishes personal from organizational at every gate. A personal project Orchestrator denying their own Phase 1 gate and then reworking indefinitely is a self-correcting problem (they will either fix it or abandon the project). An organizational deployment with a real Senior Technical Authority needs a structured denial path to prevent reviewer/Orchestrator standoffs and to create an audit trail for compliance.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `templates/generated/approval-log-org.tmpl` | Modify | Add "Gate Denial" entry format under each gate section: Denial date, Reviewer, Findings (numbered list), Rework scope, Rework deadline, Cycle number (1 of max 2) |
| `templates/generated/approval-log-personal.tmpl` | Modify | Add "Needs Revision" note field to each gate section. Add advisory: "If self-review identifies issues on 2 consecutive cycles, seek external review before proceeding." |
| `docs/governance-framework.md` | Modify | Section V (Governance & Accountability): add "Gate Denial and Rework Procedure" subsection. Define: (1) denial must record findings, (2) max 2 rework cycles, (3) escalation on 3rd denial, (4) rework scope constrained to findings |
| `docs/builders-guide.md` | Modify | Phase 0->1, Phase 1->2, and Phase 3->4 gate sections: add cross-reference to governance framework denial procedure. Update "Approved / Needs revision" to include instruction for recording denial findings |

#### Acceptance Criteria

1. An organizational gate denial produces an `APPROVAL_LOG.md` entry with: denial date, reviewer name, numbered findings, rework scope, rework deadline, and cycle number.
2. After 2 denial cycles, the governance framework mandates escalation to the next authority level.
3. The rework scope in cycle N+1 is constrained to the findings from cycle N (no scope creep).
4. A personal project denial produces a dated note with findings in the Approval Log.
5. An auditor reviewing the Approval Log can trace: denial -> findings -> rework -> re-submission -> approval (or escalation).

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-004a | Org gate denied without findings | Reviewer enters "Needs revision" with empty findings | Template prompts for findings; reviewer instructions require populated findings |
| V-P1-004b | Third rework cycle attempted | Orchestrator submits for 3rd review after 2 denials | Governance framework mandates escalation; Approval Log entry references escalation |
| V-P1-004c | Rework scope expanded beyond findings | Orchestrator changes architecture scope beyond reviewer findings | Gate reviewer flags: "rework scope exceeds denial findings" |
| V-P1-004d | Denial audit trail | Review APPROVAL_LOG.md after denial-rework-approval cycle | Full chain visible: denial entry -> rework entry -> approval entry |

---

### P1-005: Senior Technical Authority Role Undefined for Personal/Light-Track

**Severity:** Major | **Category:** Workflow Gap
**Evidence:** `builders-guide.md:680` -- personal projects self-review the architecture decision at "the point of no return." No external review recommended. No structured self-review guidance. No retroactive approval requirement if the project upgrades to organizational.
**Risk:** The person least likely to catch blind spots (the one who made the decision) is the only reviewer. For personal projects, this is acceptable risk if documented. The real danger is undocumented: if a personal project later upgrades to organizational deployment, the architecture was never reviewed by anyone other than its creator. The "point of no return" label in the Builder's Guide correctly signals the severity but provides no compensating control.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Mandatory External Review for All** | Require an external technical reviewer for all projects, including personal. Use community review, peer review, or an AI-adversarial review as the external check. | 2-3 hrs | Strongest control. Blocks personal projects that cannot find a reviewer. Many personal projects are experiments where this overhead is disproportionate. |
| **B. Document Risk + Structured Self-Review + Upgrade Gate** | (1) Add a "Known Risk" callout to the Builder's Guide acknowledging self-review limitation. (2) Create a structured self-review checklist specific to Phase 1 (not just "review the Bible"). (3) Require retroactive Senior Technical Authority review if the project upgrades from personal to organizational. | 3-5 hrs | Acknowledges reality: personal projects are self-reviewed. Provides a structured self-review to improve quality. Catches the upgrade scenario that creates real organizational risk. Does not prevent a solo Orchestrator from approving a flawed architecture for a personal project. |
| **C. AI-Adversarial Review as Compensating Control** | Create a Phase 1 evaluation prompt (an adversarial architecture review) that the Orchestrator runs as their "self-review." The AI provides the external perspective. Document this as the compensating control for personal projects. (Partially addresses P1-013.) | 3-4 hrs | Practical and low-friction. The adversarial review provides value even if the Orchestrator is experienced. Does not replace human judgment but adds a structured challenge. Risk: Orchestrator may ignore AI findings without accountability. |

#### Recommendation

**Option B + C combined** -- document the risk, create a structured self-review checklist, require retroactive review on upgrade, AND create an adversarial evaluation prompt as a compensating control. These are complementary, not competing. The structured self-review checklist ensures the Orchestrator covers specific areas (not just "looks good"). The adversarial prompt provides the external challenge. The upgrade gate prevents unreviewed architectures from reaching organizational production.

Total combined effort: 5-7 hours.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `docs/builders-guide.md` | Modify | Step 1.6 (Phase 1->2 gate, personal projects): add "Known Risk" callout documenting self-review limitation. Add structured self-review checklist (10 items covering: budget fit, maintenance burden, security posture, platform compatibility, threat model completeness, data model coverage, observability plan, build/distribution pipeline, accessibility baseline, context management plan). Add instruction: "Run the Phase 1 Architecture Adversarial Review evaluation prompt before recording your self-review." |
| `docs/builders-guide.md` | Modify | Add "Upgrade Gate" section: "If a personal project is later proposed for organizational deployment, the Senior Technical Authority must review and approve the Phase 1 artifacts (Project Bible, Threat Model, Architecture ADR) before the project proceeds under organizational governance. Record this retroactive approval in APPROVAL_LOG.md." |
| `evaluation-prompts/Projects/bases/07-architecture-review.md` | **Create** | Adversarial architecture review prompt: challenge the architecture selection against maintenance burden, security posture, platform fit, scalability, and operational complexity. Structured output with pass/concern/fail per category. (Also addresses P1-013.) |
| `docs/governance-framework.md` | Modify | Add "Project Upgrade Governance" subsection: retroactive Phase 1 review required when personal project transitions to organizational deployment |
| `docs/user-guide.md` | Modify | Add note about self-review compensating controls for personal/light-track projects |

#### Acceptance Criteria

1. Personal project self-review section in the Builder's Guide includes a "Known Risk" callout that is visible and unambiguous.
2. The structured self-review checklist has 10+ specific items that the Orchestrator must evaluate (not just "review the Bible").
3. The Phase 1 adversarial review evaluation prompt produces structured output with per-category assessment.
4. A personal project upgrading to organizational deployment triggers a mandatory retroactive Phase 1 review by the Senior Technical Authority.
5. The retroactive review is recorded in `APPROVAL_LOG.md` with a "Retroactive Phase 1 Review" entry.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-005a | Personal project self-review without checklist | Orchestrator records self-review as "Reviewed Bible, looks good" | Builder's Guide instructions require checklist completion; reviewer entry includes checklist responses |
| V-P1-005b | Personal project upgraded without retroactive review | Project transitions to org without Senior Technical Authority review | Governance framework blocks: "retroactive Phase 1 review required" |
| V-P1-005c | Adversarial review prompt produces actionable output | Run evaluation prompt against a sample Project Bible | Output includes per-category assessment, identifies at least one concern in a realistic scenario |

---

## Minor Findings

---

### P1-006: Steps 1.1 and 1.1.5 Have No Output Specification

**Severity:** Minor | **Category:** Missing Storage
**Evidence:** `builders-guide.md:509-522` -- Go/No-Go decision and market signal validation produce no persisted artifact. Decision is ephemeral conversation text.
**Risk:** An auditor cannot verify the Go/No-Go decision was made or what market signals were reviewed. For Standard+ track projects, this is a business justification gap.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Persist to Project Bible** | Add a "Section 0: Pre-Architecture Decision Log" to the Project Bible template capturing: Go/No-Go decision (with date, rationale, competitors evaluated), Market Signal (source, date, evidence type). | 2-3 hrs | Keeps all Phase 1 decisions in one document. Bible grows by one section (now 17 sections). Minor template bloat. |
| **B. Persist to Approval Log** | Add a "Phase 1 Pre-Architecture" section to the Approval Log templates capturing the Go/No-Go decision and market signal as pre-conditions for the Phase 1->2 gate. | 1-2 hrs | Leverages existing audit trail document. Does not add sections to the Bible. Approval Log becomes both approval trail and decision record, which is a slight scope mix. |
| **C. Standalone Decision Record** | Create `docs/phase-1-decisions.md` capturing Go/No-Go and market signal. | 1-2 hrs | Clean separation. Adds another file to track. May not be consistently created since it is a one-time artifact. |

#### Recommendation

**Option B** -- persist to Approval Log. The Go/No-Go decision and market signal are pre-conditions for proceeding into architecture work. They belong in the approval trail. This avoids adding a 17th section to the already-large Project Bible and leverages a document that already exists and is already reviewed at the gate.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `templates/generated/approval-log-org.tmpl` | Modify | Add "Phase 1 Pre-Architecture Decisions" section before the Phase 1->2 gate entry: Go/No-Go (decision, date, rationale, competitors evaluated), Market Signal (source, date, evidence type). Mark as "Standard+ Track -- N/A for Light Track and internal tools." |
| `templates/generated/approval-log-personal.tmpl` | Modify | Same addition, simplified for personal projects |
| `docs/builders-guide.md` | Modify | Steps 1.1 and 1.1.5: add instruction to record output in `APPROVAL_LOG.md` Phase 1 Pre-Architecture section |

#### Acceptance Criteria

1. After Step 1.1, the Approval Log contains the Go/No-Go decision with date and rationale.
2. After Step 1.1.5, the Approval Log contains the market signal with source and evidence type.
3. Light Track projects have these sections marked "N/A" with a skip reason.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-006a | Standard track without Go/No-Go | Review Approval Log for Standard track project | Section present but unpopulated; gate reviewer flags |

---

### P1-007: Step 1.5 UI/UX Scaffolding Has No Validation Criteria

**Severity:** Minor | **Category:** Missing Validation
**Evidence:** `builders-guide.md:624-633` -- no format specified, no completeness checklist for the UI scaffolding output.
**Risk:** Output quality depends entirely on the Orchestrator's judgment and the AI agent's interpretation. Since UI scaffolding feeds directly into Bible Section 9 (UI Component Specifications), quality issues propagate.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Validation Checklist in Builder's Guide** | Add a checklist to Step 1.5: (1) Every screen/view listed, (2) Each component has documented responsibilities, (3) All interactive components define Empty/Loading/Error/Success states, (4) Accessibility baseline documented (labels, contrast, keyboard), (5) State management approach specified. | 1 hr | Lightweight. Tier 3 enforcement (LLM compliance). Quick to implement. Consistent with existing remediation table pattern in the Builder's Guide. |
| **B. UI Scaffolding Template** | Create `templates/generated/ui-scaffolding.tmpl` with structured sections for each validation criterion. | 2-3 hrs | More rigorous. Ensures consistent format across projects. May over-constrain creative UI decisions. Does not account for non-UI projects (APIs, CLIs). |

#### Recommendation

**Option A** -- validation checklist in the Builder's Guide. Step 1.5 already has a clear instruction set. Adding a validation checklist at the end of the step provides quality criteria without constraining the format. The existing Bible Section 9 template provides sufficient structure for the final output; the checklist validates the intermediate work before it is synthesized into the Bible.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `docs/builders-guide.md` | Modify | Step 1.5: add "Validation Checklist" after the existing instructions. 5 items. Add note: "For non-UI projects (APIs, CLIs), apply equivalent checklist: endpoint/command inventory complete, input/output contracts defined, error responses specified, help text documented, state management approach specified." |

#### Acceptance Criteria

1. Step 1.5 output covers all 5 checklist items.
2. Non-UI projects have equivalent coverage criteria.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-007a | UI scaffolding missing states | Step 1.5 output omits Error state for login form | Checklist item "all interactive components define Empty/Loading/Error/Success states" catches the gap |

---

### P1-008: Project Bible Freshness Markers Are Advisory

**Severity:** Minor | **Category:** Missing Enforcement
**Evidence:** `project-bible.tmpl` -- `<!-- Last Updated: YYYY-MM-DD -->` markers in every section. No script validates that dates are populated or non-placeholder.
**Risk:** Placeholder dates (`YYYY-MM-DD`) pass undetected. For personal projects with self-review, staleness goes unchecked.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. CI Warning (validate.sh)** | Add a check to `scripts/validate.sh` that scans `PROJECT_BIBLE.md` for `YYYY-MM-DD` placeholder dates and emits a warning. Not blocking. | 1-2 hrs | Low-friction. Warning-level, so it does not block development. Catches the most obvious failure (placeholder dates never replaced). Does not verify dates are *recent*. |
| **B. Gate-Level Check** | Add a check to `scripts/check-phase-gate.sh` at Phase 1->2 that verifies all 16 sections have non-placeholder dates. Blocking. | 2-3 hrs | Stronger enforcement. Blocks Phase 2 entry with placeholder dates. Requires parsing all 16 section headers in the Bible, which is fragile if the template changes. |
| **C. Both CI Warning + Gate Check** | Option A for continuous feedback, Option B for hard gate enforcement. | 3-4 hrs | Belt and suspenders. CI catches it early, gate enforces it. |

#### Recommendation

**Option A** -- CI warning in `validate.sh`. The freshness marker is a documentation hygiene control, not a security gate. A blocking check at the phase gate for date formatting is brittle and disproportionate. A CI warning flags the issue early enough for the Orchestrator to fix it before the gate review. If the organization requires harder enforcement, upgrade to Option C.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `scripts/validate.sh` | Modify | Add Bible freshness check section: grep `PROJECT_BIBLE.md` for `YYYY-MM-DD` literals. If found, emit warning with section names containing placeholder dates |

#### Acceptance Criteria

1. Running `validate.sh` on a project with placeholder dates in the Bible produces a warning listing the sections with `YYYY-MM-DD`.
2. Running `validate.sh` on a project with all dates populated produces no freshness warnings.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-008a | Bible with 3 placeholder dates | Run `validate.sh` | Warning: "PROJECT_BIBLE.md has placeholder dates in: Section 2, Section 7, Section 14" |
| V-P1-008b | Bible with all dates populated | Run `validate.sh` | No freshness warnings |

---

### P1-009: Data Migration Plan Has No Template

**Severity:** Minor | **Category:** Missing Template
**Evidence:** `builders-guide.md:609-621` -- 6 components prescribed in prose (source inventory, mapping, transformation rules, import script, rollback, validation) but no structured template.
**Risk:** Migration plans are inconsistent across projects. A high-risk artifact (data migration) has less structural guidance than lower-risk artifacts (changelog, features list) that all have templates.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Standalone Migration Template** | Create `templates/generated/data-migration-plan.tmpl` with 6 structured sections matching the Builder's Guide prescription: Source Inventory table, Field Mapping table, Transformation Rules, Import Script specification, Rollback Procedure, Validation Criteria. | 2-3 hrs | Consistent with framework pattern (every prescribed artifact has a template). Template may feel heavy for simple migrations (CSV import). Can include "N/A" guidance for simple cases. |
| **B. Extend Bible Section 6** | Expand the Project Bible Section 6 (Data Migration Plan) template with structured sub-sections and tables instead of the current one-line placeholder. | 1-2 hrs | No new file. All migration data stays in the Bible. Bible grows longer. Migration plan cannot be worked on independently by a specialist. |

#### Recommendation

**Option A** -- standalone migration template. Data migration is a high-risk artifact that benefits from independent review. In organizational deployments, the migration plan may need review by a DBA or data engineer who should not need to parse the entire 16-section Project Bible. The standalone template can be referenced from Bible Section 6.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `templates/generated/data-migration-plan.tmpl` | **Create** | 6 sections: Source Inventory (table: source name, format, record count, location, access method), Field Mapping (table: source field, target entity.field, transformation, validation rule), Transformation Rules (prose), Import Script (specification: language, execution method, idempotency, expected runtime), Rollback Procedure (steps), Validation Criteria (table: check type, method, expected result, actual result) |
| `templates/generated/project-bible.tmpl` | Modify | Section 6: update placeholder to reference standalone template: "See `docs/data-migration-plan.md` for the full migration plan. Summary: [1-2 sentence summary of migration scope and risk level]." |
| `docs/builders-guide.md` | Modify | Step 1.4.5: add reference to `data-migration-plan.tmpl` |
| `docs/builders-guide.md` Appendix A | Modify | Add `data-migration-plan.md` to artifact table |

#### Acceptance Criteria

1. Projects with legacy data produce a `docs/data-migration-plan.md` with all 6 sections populated.
2. Bible Section 6 references the standalone plan and includes a summary.
3. Projects without legacy data have Bible Section 6 marked "No legacy data -- skip."

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-009a | Migration plan with empty Field Mapping | Review template output | Template structure makes the gap visible; reviewer flags missing mappings |

---

### P1-010: Threat Model Persona Has No Compliance Verification

**Severity:** Minor | **Category:** Missing Validation
**Evidence:** `builders-guide.md:590-591` -- Penetration Tester persona instruction is behavioral only. No structural validation that the output is concrete rather than generic.
**Risk:** A shallow threat model (generic OWASP boilerplate instead of architecture-specific attack paths) passes review because there is no quality checklist for the output.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Output Quality Checklist** | Add a validation checklist after the threat model prompt in Step 1.3: (1) Every threat references a specific component in the architecture, (2) Attack paths describe concrete steps, not abstract categories, (3) Mitigations are code-level or configuration-level, not "be careful," (4) At least one threat per STRIDE category, (5) No threat is a copy of generic OWASP text without architecture-specific adaptation. | 1 hr | Lightweight. Tier 3 enforcement. Gives the Orchestrator (and gate reviewer) specific quality criteria. |
| **B. Adversarial Re-Evaluation** | After the threat model is produced, run a second AI prompt that evaluates the threat model quality against the checklist and flags generic entries. | 2-3 hrs | Automated quality check. Depends on AI quality, which is variable. Adds a step to Phase 1. |

#### Recommendation

**Option A** -- output quality checklist. The existing remediation table in the Builder's Guide already handles the "Shallow Threat Model" case with corrective prompting. Adding a preventive quality checklist at the output stage ensures the Orchestrator checks before accepting the output. This is a 1-hour change with high value.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `docs/builders-guide.md` | Modify | Step 1.3: add "Threat Model Quality Checklist" after the output specification. 5 items. Add instruction: "Review the threat model output against this checklist before accepting. If any item fails, re-prompt with the specific deficiency." |

#### Acceptance Criteria

1. Every threat in the model references a specific named component from the architecture.
2. Attack paths describe concrete steps (e.g., "enumerate user IDs via sequential API endpoint") not abstract categories (e.g., "information disclosure risk").
3. At least one threat exists per STRIDE category used.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-010a | Threat model with generic OWASP text | Review against checklist | Checklist item "no generic OWASP text without adaptation" catches the gap |

---

### P1-011: Phase 1->2 Gate Does Not Verify Bible Completeness

**Severity:** Minor | **Category:** Missing Validation
**Evidence:** `scripts/check-phase-gate.sh:38-41` -- creates snapshot copying `PROJECT_BIBLE.md` if it exists, but does not verify the file exists, is non-empty, or has all 16 section headers.
**Risk:** An incomplete or missing Bible passes the gate with only the Approval Log entry as evidence. The gate snapshot copies whatever exists (including nothing).

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Existence + Header Check in Gate Script** | Extend `check-phase-gate.sh` Phase 1->2 section: (1) verify `PROJECT_BIBLE.md` exists, (2) verify file is non-empty (>100 lines), (3) verify all 16 section headers (`## 1.` through `## 16.`) are present. | 2-3 hrs | Mechanical enforcement. Catches missing files and incomplete templates. Does not verify content quality (only structure). Section header matching is regex-based and could be fragile if section numbering changes. |
| **B. Existence Check Only** | Verify `PROJECT_BIBLE.md` exists and is non-empty. No section header validation. | 1 hr | Catches the most critical failure (missing file). Does not catch a Bible with only 3 of 16 sections completed. |
| **C. Full Content Validation** | Check existence, section headers, and that each section has content beyond the template placeholder text. | 3-5 hrs | Strongest check. Catches template boilerplate passed off as completed sections. Most fragile: any template text change requires updating the validation regex. |

#### Recommendation

**Option A** -- existence plus header check. This catches the two practical failure modes: (1) Bible not created at all, and (2) Bible partially completed (missing sections). Content quality is the gate reviewer's responsibility, not the script's. The 16 section headers are stable (defined by the template) and unlikely to change numbering frequently.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `scripts/check-phase-gate.sh` | Modify | Phase 1->2 section (after line 141): add Bible completeness check. Verify file exists, line count >100, and all 16 `## N.` headers present. Emit per-section pass/fail. Block gate if file missing or <12 of 16 headers present (allowing 4 legitimate "N/A" sections like Revenue Model for internal tools). |

#### Acceptance Criteria

1. Phase 1->2 gate fails if `PROJECT_BIBLE.md` does not exist.
2. Phase 1->2 gate fails if `PROJECT_BIBLE.md` has fewer than 12 of 16 section headers.
3. Phase 1->2 gate passes if all 16 section headers are present (even if some sections contain "N/A").
4. Gate output lists which sections are present and which are missing.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-011a | No Bible file | Run `check-phase-gate.sh` at phase 2 | Fails: "PROJECT_BIBLE.md not found" |
| V-P1-011b | Bible with 8 of 16 sections | Run `check-phase-gate.sh` | Fails: "Bible incomplete -- missing sections: 9, 10, 11, 12, 13, 14, 15, 16" |
| V-P1-011c | Bible with all 16 sections, 3 marked N/A | Run `check-phase-gate.sh` | Passes: "16/16 section headers present" |

---

### P1-012: Step 1.2 Does Not Reference Competency Matrix

**Severity:** Minor | **Category:** Missing Documentation
**Evidence:** `builders-guide.md:531-557` -- architecture selection prompt does not include the Competency Matrix as an input. Competency gaps are discovered at the Phase 1->2 gate rather than during architecture selection.
**Risk:** An Orchestrator may select an architecture requiring competencies they lack. The CI tooling requirement for "No" domains is enforced at the gate, but by then the architecture is already selected. Discovering at the gate that the chosen stack requires security expertise the Orchestrator lacks (and thus heavy CI tooling) is a late surprise that could trigger rework.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Add Competency Matrix as Prompt Input** | Modify the Step 1.2 architecture prompt to include a "Competency Context" section referencing the Orchestrator's self-assessment from Intake Section 6.2. Instruct the AI to factor competency gaps into the architecture recommendation. | 1 hr | Lightweight. Moves competency awareness earlier. Does not change the enforcement mechanism -- just ensures the AI considers it during option generation. |
| **B. Add Competency Fit as Evaluation Category** | Add "Competency Fit" as an 11th evaluation category in the architecture matrix (from P1-001). Score measures how well the architecture maps to the Orchestrator's self-assessed competencies. | 1 hr | Integrates with the evaluation matrix from P1-001. Makes competency fit a scored, reviewable dimension. Depends on P1-001 being implemented first. |

#### Recommendation

**Option A + B** -- add the Competency Matrix as both a prompt input (so the AI generates options that consider competency) and as an evaluation category (so the selection explicitly scores competency fit). These are complementary 1-hour tasks that together close the gap at both the generation and evaluation stages.

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `docs/builders-guide.md` | Modify | Step 1.2 architecture prompt: add "Competency Context" section: "The Orchestrator's competency self-assessment (from Intake Section 6.2 or Manifesto Appendix B) is: [paste or summarize]. Factor these gaps into your architecture recommendations -- prefer stacks where the Orchestrator's weak domains are covered by automated tooling rather than manual expertise." |
| `templates/generated/arch-evaluation-matrix.tmpl` | Modify (from P1-001) | Add "Competency Fit" as a prose evaluation category (not scored): "How well does this architecture align with the Orchestrator's self-assessed competencies? What additional CI tooling is required to compensate for gaps?" |

#### Acceptance Criteria

1. The Step 1.2 architecture prompt includes the Orchestrator's competency self-assessment as context.
2. The evaluation matrix includes a "Competency Fit" category.
3. The selected architecture's competency requirements are documented before the Phase 1->2 gate.

#### Verification Test

| ID | Test | Method | Expected Result |
|----|------|--------|-----------------|
| V-P1-012a | Architecture selected without competency context | Review Step 1.2 prompt | Prompt includes competency self-assessment as input |

---

## Observation Findings

---

### P1-013: No Phase 1 Evaluation Prompt for Architecture Review

**Severity:** Observation | **Category:** Missing Validation
**Evidence:** All 6 evaluation prompts in `evaluation-prompts/Projects/bases/` are designed for Phase 3+ evaluation. No structured adversarial review prompt exists for Phase 1 artifacts.
**Risk:** Gate reviewer (especially for personal projects doing self-review) has no guided evaluation criteria. Low impact for organizational deployments where the Senior Technical Authority brings their own evaluation framework.

#### Recommendation

**Addressed by P1-005 (Option C).** Create `evaluation-prompts/Projects/bases/07-architecture-review.md` as part of the P1-005 remediation. The prompt challenges the architecture selection against maintenance burden, security posture, platform fit, scalability, and operational complexity.

#### Files to Create/Modify

See P1-005 file table. No additional work required beyond P1-005.

#### Acceptance Criteria

1. `evaluation-prompts/Projects/bases/07-architecture-review.md` exists and produces structured output.
2. Personal project Orchestrators are instructed to run this prompt as part of their self-review.

---

### P1-014: Data Model Not Validated Against Phase 0 Data Contracts

**Severity:** Observation | **Category:** Missing Validation
**Evidence:** `builders-guide.md:594-606` -- "Verify it supports all must-have features" is informal, with no structured cross-reference from data contract to data model entities.
**Risk:** Low. The Phase 1->2 gate review should catch major omissions. This is a quality-of-documentation issue, not a process gap.

#### Recommendation

Add a single sentence to Step 1.4 in the Builder's Guide: "Cross-reference each data entity against the Phase 0 Data Contract to verify that all data inputs, outputs, and state described in the contract are represented in the model. Document any data contract items that are intentionally deferred to post-MVP."

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `docs/builders-guide.md` | Modify | Step 1.4: add cross-reference instruction after the existing data model requirements |

#### Acceptance Criteria

1. Step 1.4 includes explicit instruction to cross-reference data entities against the Phase 0 Data Contract.

---

### P1-015: No Process Enforcement for Phase 1 Steps

**Severity:** Observation | **Category:** Missing Enforcement
**Evidence:** `scripts/process-checklist.sh` enforces Phases 2-4 but has no Phase 1 step definitions. Agent could skip the threat model (Step 1.3) without CI detection.
**Risk:** Phase 1 is a short phase (4-8 hours) typically completed in a single conversation session. The threat model is the most compliance-critical step. However, the Bible template itself provides structural enforcement: if Section 4 (Threat Model) is empty, the Phase 1->2 gate check from P1-011 will catch it.

#### Options

| Option | Description | Effort | Trade-offs |
|--------|------------|--------|------------|
| **A. Add Phase 1 Step Sequence** | Extend `process-checklist.sh` with a `PHASE1_STEPS` array: `(business_strategy_reviewed architecture_selected threat_model_completed data_model_designed ui_scaffolding_completed bible_synthesized)`. Add `--start-phase1` command. | 3-4 hrs | Consistent with Phase 2-4 enforcement. Adds process overhead to a short phase that is typically a single AI conversation. |
| **B. Rely on P1-011 Gate Check** | The Bible completeness check (P1-011) mechanically verifies that all required sections are present. If the threat model section is empty, the gate blocks. This provides structural enforcement without step-level tracking. | 0 hrs (already addressed) | Lighter. Does not track step ordering within Phase 1. Acceptable because Phase 1 steps are naturally sequential (you cannot design a data model without first selecting an architecture). |

#### Recommendation

**Option B** -- rely on the Bible completeness gate check from P1-011. Adding step-level enforcement to a 4-8 hour phase that runs in a single conversation session is disproportionate overhead. The Bible template structure plus the completeness gate check provides equivalent assurance that all steps were completed. If Phase 1 duration increases (e.g., for complex enterprise architectures), revisit this decision and implement Option A.

#### Files to Create/Modify

No additional files. Covered by P1-011.

---

### P1-016: No Explicit Handling of "Not Applicable" Steps

**Severity:** Observation | **Category:** Missing Documentation
**Evidence:** `builders-guide.md:509-522, 609-620` -- skip conditions exist for Steps 1.1 (internal tools), 1.1.5 (no market signal needed), and 1.4.5 (no legacy data), but no documentation requirement for the skip decision.
**Risk:** Low. The Bible template handles section-level N/A well (e.g., Section 2: "N/A -- internal tool"). Step-level skips are not formally documented but are low-risk.

#### Recommendation

Add a single instruction to the Phase 1 introduction in the Builder's Guide: "For steps marked as conditional (Standard+ Track, or 'if replacing an existing system'), document the skip decision in the Approval Log's Phase 1 section: 'Step 1.1 -- Skipped (internal tool, Light Track).' This creates an audit trail that the skip was intentional, not an oversight."

#### Files to Create/Modify

| File | Action | Change |
|------|--------|--------|
| `docs/builders-guide.md` | Modify | Phase 1 introduction (before Step 1.1): add N/A documentation instruction |
| `templates/generated/approval-log-org.tmpl` | Modify | Phase 1->2 gate section: add "Skipped Steps" field with example format |
| `templates/generated/approval-log-personal.tmpl` | Modify | Same addition |

#### Acceptance Criteria

1. Skipped Phase 1 steps are documented in the Approval Log with step ID and skip reason.
2. The gate reviewer can distinguish between "skipped intentionally" and "skipped by accident."

---

## Implementation Sequencing

The remediations have dependencies. The following sequence minimizes rework.

### Wave 1: Foundation (No Dependencies)
| Finding | Deliverable | Est. Hours |
|---------|------------|------------|
| P1-003 | Stable threat model IDs + validation evidence column + gate check | 4-6 |
| P1-004 | Gate denial procedure + Approval Log templates | 4-5 |
| P1-008 | Bible freshness check in validate.sh | 1-2 |
| P1-010 | Threat model quality checklist | 1 |
| P1-014 | Data contract cross-reference instruction | 0.5 |
| P1-016 | N/A step documentation instruction | 1 |

### Wave 2: Architecture Evaluation (P1-001 enables P1-002 and P1-012)
| Finding | Deliverable | Est. Hours |
|---------|------------|------------|
| P1-001 | Evaluation matrix template + Builder's Guide updates | 3-5 |
| P1-002 | Two-tier ADR templates (depends on P1-001 for matrix reference) | 3-4 |
| P1-012 | Competency Matrix integration (depends on P1-001 for matrix template) | 1 |

### Wave 3: Self-Review Controls (P1-005 addresses P1-013)
| Finding | Deliverable | Est. Hours |
|---------|------------|------------|
| P1-005 | Self-review checklist + adversarial prompt + upgrade gate | 5-7 |
| P1-013 | Addressed by P1-005 evaluation prompt | 0 |

### Wave 4: Gate Hardening (Can run in parallel with Wave 2-3)
| Finding | Deliverable | Est. Hours |
|---------|------------|------------|
| P1-006 | Approval Log pre-architecture section | 1-2 |
| P1-007 | UI scaffolding validation checklist | 1 |
| P1-009 | Data migration plan template | 2-3 |
| P1-011 | Bible completeness gate check | 2-3 |
| P1-015 | Covered by P1-011 | 0 |

### Total Estimated Effort

| Wave | Effort | Can Parallelize With |
|------|--------|---------------------|
| Wave 1 | 11.5-15.5 hrs | -- |
| Wave 2 | 7-10 hrs | Wave 1 complete |
| Wave 3 | 5-7 hrs | Wave 2 |
| Wave 4 | 6-9 hrs | Wave 2, Wave 3 |
| **Total** | **29.5-41.5 hrs** | |

---

## Consolidated Verification Test Plan

All verification tests from the individual findings, collected for test execution planning.

### Major Finding Tests

| ID | Finding | Test | Method | Expected Result |
|----|---------|------|--------|-----------------|
| V-P1-001a | P1-001 | Architecture selected without matrix | Attempt gate without matrix artifact | Gate reviewer flags missing artifact |
| V-P1-001b | P1-001 | Matrix with blank scores | Submit matrix with empty scored categories | Gate reviewer rejects |
| V-P1-001c | P1-001 | Lower-scoring option without override rationale | Select lower-scoring option without explanation | Gate reviewer rejects |
| V-P1-002a | P1-002 | Phase 1 ADR with lightweight template | Use wrong template for architecture ADR | Gate reviewer flags wrong template |
| V-P1-002b | P1-002 | Architecture ADR missing rejected alternatives | Empty rejected alternatives section | Gate reviewer rejects |
| V-P1-002c | P1-002 | Bible Section 3 inconsistent with ADR | Mismatched rejected alternatives | Gate reviewer flags inconsistency |
| V-P1-003a | P1-003 | Threat table with old-style IDs | Create Bible with `#` instead of `TM-NNN` | Template default uses `TM-NNN`; old style no longer generated |
| V-P1-003b | P1-003 | Phase 3->4 gate with blank validation evidence | Run `check-phase-gate.sh` with empty validation evidence | Fails: "TM-003 missing validation evidence" |
| V-P1-003c | P1-003 | End-to-end traceability | Trace TM-001 from Phase 1 to Phase 3 validation | Auditor traces TM-001 to test result file |
| V-P1-004a | P1-004 | Org gate denied without findings | Empty findings on denial | Template requires populated findings |
| V-P1-004b | P1-004 | Third rework cycle | 3rd submission after 2 denials | Governance framework mandates escalation |
| V-P1-004c | P1-004 | Rework scope exceeds findings | Architecture change beyond denial findings | Gate reviewer flags scope creep |
| V-P1-004d | P1-004 | Denial audit trail | Review log after denial-rework-approval | Full chain visible in APPROVAL_LOG.md |
| V-P1-005a | P1-005 | Self-review without checklist | Personal project records "looks good" | Builder's Guide requires checklist completion |
| V-P1-005b | P1-005 | Personal upgrade without retroactive review | Project transitions to org | Governance framework blocks until retroactive review |
| V-P1-005c | P1-005 | Adversarial review prompt quality | Run prompt against sample Bible | Structured output with per-category assessment |

### Minor Finding Tests

| ID | Finding | Test | Method | Expected Result |
|----|---------|------|--------|-----------------|
| V-P1-006a | P1-006 | Standard track without Go/No-Go | Review Approval Log | Section present but unpopulated; reviewer flags |
| V-P1-007a | P1-007 | UI scaffolding missing states | Step 1.5 output omits Error state | Checklist catches gap |
| V-P1-008a | P1-008 | Bible with placeholder dates | Run `validate.sh` | Warning listing sections with `YYYY-MM-DD` |
| V-P1-008b | P1-008 | Bible with all dates populated | Run `validate.sh` | No freshness warnings |
| V-P1-009a | P1-009 | Migration plan with empty Field Mapping | Review template output | Template structure makes gap visible |
| V-P1-010a | P1-010 | Generic OWASP threat model | Review against checklist | Checklist catches generic text |
| V-P1-011a | P1-011 | No Bible file at Phase 1->2 | Run `check-phase-gate.sh` | Fails: "PROJECT_BIBLE.md not found" |
| V-P1-011b | P1-011 | Bible with 8/16 sections | Run `check-phase-gate.sh` | Fails: lists missing sections |
| V-P1-011c | P1-011 | Bible with 16 sections, 3 N/A | Run `check-phase-gate.sh` | Passes: "16/16 section headers present" |
| V-P1-012a | P1-012 | Architecture without competency context | Review Step 1.2 prompt | Prompt includes competency self-assessment |

---

## Appendix: Cross-References

### Findings Addressed by Other Findings

| Finding | Addressed By | Mechanism |
|---------|-------------|-----------|
| P1-013 | P1-005 (Option C) | Adversarial evaluation prompt created as part of self-review compensating controls |
| P1-015 | P1-011 | Bible completeness gate check provides structural enforcement equivalent to step tracking |

### Related Phase 0 Findings

| P1 Finding | Related P0 Finding | Relationship |
|------------|-------------------|-------------|
| P1-004 (Gate denial procedure) | P0-004 (Approval validation shallow) | Both address gate approval mechanics; denial procedure should be consistent across all gates |
| P1-011 (Bible completeness) | P0-003 (Manifesto completeness) | Same pattern: gate checks artifact existence but not content; same fix pattern (structural validation) |
| P1-012 (Competency Matrix reference) | P0-008 (Competency Matrix not gated) | P0-008 addresses CI enforcement; P1-012 addresses earlier awareness during architecture selection |

### Files Modified Across Multiple Findings

| File | Findings | Notes |
|------|----------|-------|
| `docs/builders-guide.md` | P1-001, P1-002, P1-003, P1-004, P1-005, P1-006, P1-007, P1-010, P1-012, P1-014, P1-016 | Most-modified file. Coordinate changes to avoid merge conflicts. |
| `templates/generated/project-bible.tmpl` | P1-001, P1-003, P1-009 | Section 3 (ADR reference), Section 4 (threat model IDs), Section 6 (migration reference) |
| `templates/generated/approval-log-org.tmpl` | P1-004, P1-006, P1-016 | Denial entries, pre-architecture decisions, skipped steps |
| `templates/generated/approval-log-personal.tmpl` | P1-004, P1-006, P1-016 | Same additions in personal format |
| `scripts/check-phase-gate.sh` | P1-003, P1-011 | Threat validation evidence check (Phase 3->4) and Bible completeness check (Phase 1->2) |
| `docs/governance-framework.md` | P1-003, P1-004, P1-005 | Traceability expectation, denial procedure, upgrade governance |

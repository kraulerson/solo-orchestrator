# Phase 0 Re-Audit Report
## Product Discovery

**Auditor Persona:** Product Management Director
**Date:** 2026-04-08
**Framework Version:** Solo Orchestrator v1.0 (current)
**Files Evaluated:**
- `docs/builders-guide.md` (Phase 0 section, lines 247-513)
- `docs/user-guide.md` (Phase 0 section, lines 530-702; approval log guidance, lines 1006-1063; pre-conditions, lines 190-219; quick reference, lines 1389-1399; FAQ, lines 1370-1386)
- `docs/governance-framework.md` (full document — Pre-Phase 0 pre-conditions Section XIV, Phase 0->1 gate Section V, Gate Denial Procedure Section V, Approval Authority Section V, Compliance Screening Section VIII.11, Legal Checklist Section VIII)
- `templates/generated/product-manifesto.tmpl`
- `templates/generated/frd.tmpl`
- `templates/generated/user-journey.tmpl`
- `templates/generated/data-contract.tmpl`
- `templates/project-intake.md`
- `templates/generated/approval-log-org.tmpl`
- `templates/generated/approval-log-personal.tmpl`
- `scripts/check-phase-gate.sh`
- `scripts/intake-wizard.sh`
- `scripts/process-checklist.sh`
- `templates/pipelines/ci/typescript.yml` (representative CI template)
- `evaluation-prompts/Projects/bases/01-senior-engineer.md`
- `evaluation-prompts/Projects/bases/02-cio.md`
- `evaluation-prompts/Projects/bases/03-security.md`
- `evaluation-prompts/Projects/bases/04-legal.md`
- `evaluation-prompts/Projects/bases/05-technical-user.md`
- `evaluation-prompts/Projects/bases/06-red-team-review.md`

---

## 1. Scope & Methodology

**Scope:** Steps 0.1 through 0.7 of Phase 0 (Product Discovery) and the Phase 0 to Phase 1 gate, including all Pre-Phase 0 pre-conditions that must be satisfied before Phase 0 can begin.

**Methodology:** Independent evaluation by a Product Management Director with no prior exposure to this framework. Every prescribed action in Phase 0 was evaluated against the 12-criteria rubric (Instructions, Input Requirements, Output Specification, Template/Guide, Storage & Retention, Enforcement Mechanism, Validation/Verification, Error Handling, Audit Trail, Sign-off Authority, Traceability, Bypass Risk). Benchmarked against ISO 9001:2015 Clause 8 (Operational Planning and Control) and SOC 2 Type II CC6/CC7 control objectives for change management and process integrity.

**Approach:** Read all files end-to-end. Traced every prescribed action from its instruction text through to its template, storage location, enforcement mechanism, and gate verification. Cross-referenced Builder's Guide, User Guide, and Governance Framework for consistency. Examined scripts for mechanical enforcement coverage. Evaluated from the standpoint of a PM who has never used this framework before.

---

## 2. Findings

### Finding P0-001: Step 0.5 Revenue Model Has No Dedicated Template
- **Severity:** Minor
- **Category:** Missing Template
- **Evidence:** `builders-guide.md:448-454` — "Save as: Appendix to PRODUCT_MANIFESTO.md"; `product-manifesto.tmpl:165-179` (Appendix A: Revenue Model exists in Manifesto template)
- **Enterprise Expectation:** Each step that produces a distinct artifact should have a standalone template to guide consistent output, or its template should be clearly embedded in the parent document with structural guidance equivalent to standalone templates.
- **Current State:** Step 0.5 output is directed to Appendix A of the Product Manifesto template. The Manifesto template does contain a Revenue Model appendix (lines 165-179) with fields for pricing model, per-user costs, break-even count, and hosting cost ceiling. There is no standalone `revenue-model.tmpl` file.
- **Gap:** The Manifesto template appendix provides adequate structural guidance. However, unlike Steps 0.1-0.3 which each have both a standalone detailed template AND a summary section in the Manifesto, Step 0.5 has only the Manifesto appendix. This is a design choice rather than a gap — the revenue model is simpler than the FRD/journey/contract and does not benefit from a two-tier (detailed + summary) approach.
- **Impact:** Low. A PM can follow the Manifesto appendix. The risk is that revenue model analysis is treated as a brief appendix when it may warrant deeper analysis for commercial products.

---

### Finding P0-002: Step 0.6 Competency Matrix Has No Dedicated Template
- **Severity:** Minor
- **Category:** Missing Template
- **Evidence:** `builders-guide.md:458-485` — "Save as: Appendix to PRODUCT_MANIFESTO.md"; `product-manifesto.tmpl:183-201` (Appendix B: Competency Matrix); `templates/project-intake.md:253-268` (Intake Section 6.2)
- **Enterprise Expectation:** Competency self-assessment data that drives mandatory tooling requirements should be captured in a structured format with clear enforcement linkage.
- **Current State:** The competency matrix exists in three locations: the Builder's Guide table (lines 464-474), the Manifesto template Appendix B (lines 183-201), and the Intake template Section 6.2 (lines 253-268). The Intake captures the self-assessment; the Manifesto appendix records the reviewed result. The Builder's Guide explicitly states that "No" domains require mandatory tooling in CI before Phase 2 (lines 476-483).
- **Gap:** No standalone template, but the Manifesto appendix and Intake both provide adequate structure. The enforcement linkage (competency "No" drives mandatory CI tooling) is documented in the Builder's Guide but has no mechanical verification at the Phase 0 to Phase 1 gate — it is deferred to the Phase 1 to Phase 2 gate per line 482.
- **Impact:** Low. The three-location approach creates redundancy but also cross-validation. The enforcement is correctly deferred to Phase 1 to Phase 2 since the CI pipeline does not exist during Phase 0.

---

### Finding P0-003: Step 0.7 Trademark/Legal Pre-Check Has No Review Checklist
- **Severity:** Minor
- **Category:** Missing Validation
- **Evidence:** `builders-guide.md:489-495` — four-item instruction list with no review checklist; `product-manifesto.tmpl:205-221` (Appendix C: Trademark & Legal Pre-Check)
- **Enterprise Expectation:** Every step that produces output should have a review checklist comparable to Steps 0.1-0.3, enabling consistent verification.
- **Current State:** Step 0.7 provides four action items (trademark search, data privacy applicability, distribution channel requirements, document findings) but no review checklist with checkboxes. Steps 0.1-0.3 all have explicit review checklists. The Manifesto template Appendix C provides structural fields but no checklist.
- **Gap:** No formal review checklist for Step 0.7. A PM must infer completeness from the four action items rather than checking boxes.
- **Impact:** Low for personal projects. For organizational deployments handling PII or operating in regulated industries, this step has significant downstream consequences (GDPR applicability, trademark conflicts). The absence of a checklist increases the risk that a PM marks this step complete without verifying all four areas.

---

### Finding P0-004: Phase 0 Intermediate Outputs Lack Versioning or Date-Stamp Convention
- **Severity:** Minor
- **Category:** Missing Storage
- **Evidence:** `builders-guide.md:326` — "Save as: docs/phase-0/frd.md"; `builders-guide.md:367` — "Save as: docs/phase-0/user-journey.md"; `builders-guide.md:406` — "Save as: docs/phase-0/data-contract.md". Templates (`frd.tmpl:14`, `user-journey.tmpl:14`, `data-contract.tmpl:14`) include a "Date: YYYY-MM-DD" field.
- **Enterprise Expectation:** Intermediate artifacts should be date-stamped or versioned to distinguish iterations, especially given the session recovery scenario described at line 257.
- **Current State:** Each template includes a Date field and a Status field (Draft). The storage convention uses fixed filenames in `docs/phase-0/`. The `check-phase-gate.sh` script (lines 239-249) verifies these three files exist at the Phase 0 to Phase 1 transition. The Phase Gate Snapshot mechanism (lines 34-43 of `check-phase-gate.sh`) creates a timestamped copy at gate transition.
- **Gap:** During Phase 0 execution, if a PM revises an artifact (e.g., revises the FRD after the user journey reveals a feature gap), the previous version is overwritten. Git history preserves versions, but the workflow does not explicitly instruct the PM to commit intermediate versions.
- **Impact:** Low. Git provides implicit versioning. The phase gate snapshot mechanism provides a point-in-time archive at transition. The risk is limited to within-phase revision tracking, which is manageable for a 1-2 day phase.

---

### Finding P0-005: No Mechanical Enforcement Preventing Phase 0 Steps from Being Executed Out of Order
- **Severity:** Observation
- **Category:** Missing Enforcement
- **Evidence:** `builders-guide.md:255` — "Keep all Phase 0 steps in the same conversation." `scripts/process-checklist.sh` — defines step sequences for build_loop, UAT, Phase 3, Phase 4, and Phase 2 init, but does not define a Phase 0 step sequence.
- **Enterprise Expectation:** Sequential process enforcement should cover all phases, or the rationale for exclusion should be documented.
- **Current State:** The `process-checklist.sh` script provides mechanical sequential enforcement for Phase 2 (build loop), UAT sessions, Phase 3, Phase 4, and Phase 2 initialization. Phase 0 has no equivalent enforcement. The process relies on conversational flow within a single AI session and the Builder's Guide step ordering.
- **Gap:** Phase 0 has no step-level mechanical enforcement. A PM could theoretically produce a Data Contract (Step 0.3) before the FRD (Step 0.1).
- **Impact:** Negligible in practice. Phase 0 is a 3-5 hour conversational process in a single session. The steps build on each other logically (FRD feeds Journey feeds Data Contract feeds Manifesto), and the AI agent naturally follows the sequence. Mechanical enforcement would add overhead disproportionate to the risk. The design choice to exclude Phase 0 from `process-checklist.sh` is reasonable.

---

### Finding P0-006: Pre-Phase 0 Pre-Condition Verification for Organizational Deployments Is Warning-Level, Not Blocking
- **Severity:** Major
- **Category:** Bypass Risk
- **Evidence:** `scripts/check-phase-gate.sh:186-206` — Pre-Phase 0 check emits `[WARN]` for missing pre-conditions, counted in `issues` variable, but only blocks if `SOIF_PHASE_GATES` is not set to "warn" (lines 571-578). The check runs at `current_phase >= 0`, which is the initial state. `governance-framework.md:863` — "All 'Blocking' items in Intake Section 8.1 must be marked 'Complete' before Phase 0 begins."
- **Enterprise Expectation:** Blocking pre-conditions that are documented as absolute requirements should produce hard failures in CI, not warnings that can be downgraded.
- **Current State:** The `check-phase-gate.sh` script checks for pre-condition dates in `APPROVAL_LOG.md` and warns if fewer than 3 of 6 are dated (line 195: `if [ "$local_precond_count" -lt 3 ]`). The threshold is 3, not 6. The entire script can be downgraded to non-blocking by setting `SOIF_PHASE_GATES=warn` (line 571). The check only runs for organizational deployments (line 187) and skips POC mode (lines 189-191).
- **Gap:** Two issues: (1) The threshold is 3 pre-condition dates, not the required 6. An organizational deployment could proceed with only 3 of 6 pre-conditions recorded without triggering a warning. (2) The environment variable `SOIF_PHASE_GATES=warn` can globally downgrade all gate checks to non-blocking, including pre-conditions documented as absolute blockers.
- **Impact:** An organizational deployment could begin Phase 0 without all 6 pre-conditions being recorded. This contradicts the Governance Framework ("All 'Blocking' items must be marked 'Complete' before Phase 0 begins") and the User Guide ("Phase 0 cannot start until all 6 are resolved. Not 'in progress.' Resolved."). For SOC 2 Type II, this would be flagged as a control deficiency — the documented control (mandatory pre-conditions) is not mechanically enforced.

---

### Finding P0-007: Approval Log Self-Approval Detection Is Heuristic, Not Preventive
- **Severity:** Major
- **Category:** Bypass Risk
- **Evidence:** `scripts/check-phase-gate.sh:170-182` — Self-approval check uses `grep -qi` to fuzzy-match approver name against git username. `governance-framework.md:176-181` — "Each approval entry MUST be committed to APPROVAL_LOG.md by the approver, not the Orchestrator."
- **Enterprise Expectation:** Self-approval prevention should be a hard control (e.g., requiring git commit author to match listed approver, or requiring out-of-band evidence verification), not a fuzzy name match that emits warnings.
- **Current State:** The script extracts the approver name from the APPROVAL_LOG.md, extracts the git username, and performs a case-insensitive substring match (line 177). It emits `[WARN]`, not `[FAIL]`. The Governance Framework states that "The Orchestrator MUST NOT author git commits that add their own name as approver" (line 180) and that "CI or code-review tooling SHOULD enforce this where feasible" (line 180).
- **Gap:** The control is detective (warns after the fact) rather than preventive. The name-matching heuristic has false negatives (Orchestrator uses a different name format, e.g., "K. Smith" vs. "Karl Smith") and false positives (different people with similar names). The governance requirement says "MUST" but the implementation says "SHOULD enforce where feasible."
- **Impact:** For SOC 2 Type II, a "MUST" control implemented as "SHOULD where feasible" is a control design deficiency. An Orchestrator could record their own approval, and the detection mechanism would only catch it if the name formats happen to match. The Governance Framework's mitigation (out-of-band confirmation, quarterly audit) provides compensating controls, but the primary control is weak.

---

### Finding P0-008: Gate Denial Procedure Is Fully Documented with Maximum Rework Cycles
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `governance-framework.md:184-193` — Written findings required, rework scope defined, re-submission process, maximum 2 rework cycles, escalation to Project Sponsor on third denial, audit trail of all denials.
- **Enterprise Expectation:** Gate denial should have a documented procedure with escalation and maximum iteration limits.
- **Current State:** The Gate Denial Procedure meets enterprise expectations. Every denial is recorded in APPROVAL_LOG.md. The Orchestrator addresses only cited deficiencies (not the entire phase). If denied a third time, it escalates to the Project Sponsor with three resolution options: accept with conditions, redirect, or terminate.
- **Gap:** None.
- **Impact:** Positive. This prevents denial loops and provides a clear escalation path.

---

### Finding P0-009: Product Manifesto Content Validation Is Mechanically Enforced
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `scripts/check-phase-gate.sh:112-151` — `validate_manifesto_content()` function checks for all 8 required sections, detects placeholder-only content, and verifies that no Open Questions have "Status: Open."
- **Enterprise Expectation:** Artifact content should be validated beyond mere file existence.
- **Current State:** The `check-phase-gate.sh` script validates that: (1) all 8 numbered sections exist in `PRODUCT_MANIFESTO.md`, (2) each section has content beyond template placeholders, (3) no unresolved Open Questions remain. This runs in CI at Phase 0 to Phase 1 transition (line 231: `if [ "$current_phase" -ge 1 ]`).
- **Gap:** None for the Manifesto. The intermediate artifacts (FRD, User Journey, Data Contract) are checked for existence only (lines 239-249), not content validity.
- **Impact:** Positive. This is a strong Tier 1 (CI) control that prevents an empty or template-only Manifesto from passing the gate. The content validation goes beyond what most frameworks implement.

---

### Finding P0-010: Phase Gate Snapshot Mechanism Provides Immutable Audit Evidence
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `scripts/check-phase-gate.sh:20-68` — `create_gate_snapshot()` function creates timestamped directory copies at each phase transition, including Phase 0 to Phase 1 (lines 33-43). Copies `PRODUCT_MANIFESTO.md`, `APPROVAL_LOG.md`, `PROJECT_INTAKE.md`, and all `docs/phase-0/*.md` files.
- **Enterprise Expectation:** Phase gate transitions should produce point-in-time evidence that cannot be retroactively modified without detection.
- **Current State:** At Phase 0 to Phase 1, a snapshot directory (`docs/snapshots/phase-0-to-1_YYYY-MM-DD/`) is created containing all Phase 0 artifacts. The snapshot is skipped if it already exists (line 25). Combined with git history, this provides strong audit evidence.
- **Gap:** None.
- **Impact:** Positive. An auditor can compare the snapshot to the current version to detect post-gate modifications.

---

### Finding P0-011: Dual-Path Prompts (With/Without Intake) Are Consistently Provided
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `builders-guide.md:271-327` (Step 0.1), `builders-guide.md:330-367` (Step 0.2), `builders-guide.md:371-406` (Step 0.3), `builders-guide.md:410-444` (Step 0.4). `user-guide.md:555-690` (duplicate prompts for user reference).
- **Enterprise Expectation:** A PM with a completed Intake and a PM starting from scratch should both have clear paths.
- **Current State:** Steps 0.1-0.4 each provide: (1) context note for Intake-first path, (2) full prompt for conversational discovery, (3) validation/expansion prompt for Intake-first path, (4) review checklist (Steps 0.1-0.3), (5) template reference and save-as location. Both the Builder's Guide and User Guide carry the prompts, with the User Guide providing them in a collapsed `<details>` block.
- **Gap:** None. The dual-path design is well-executed.
- **Impact:** Positive. A PM new to the framework can follow either path without ambiguity.

---

### Finding P0-012: Intake Wizard Provides Guided Data Collection
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `scripts/intake-wizard.sh` — Interactive script with progress tracking, context-aware suggestions, pause/resume capability. `builders-guide.md:261` — References intake wizard as the recommended approach.
- **Enterprise Expectation:** Complex data collection should be assisted, not left to manual form-filling.
- **Current State:** The intake wizard offers numbered choices, suggestions (via `?` input), progress saving to `.claude/intake-progress.json`, and pause/resume. It tracks completed sections and offers both interactive terminal mode and AI-assisted conversational mode.
- **Gap:** None for the guided experience. The wizard is a significant onboarding aid.
- **Impact:** Positive. This materially reduces the friction of the Intake process for a PM unfamiliar with the framework.

---

### Finding P0-013: Phase 0 Intermediate Content Validation Is Existence-Only
- **Severity:** Minor
- **Category:** Missing Validation
- **Evidence:** `scripts/check-phase-gate.sh:239-249` — Checks `[ -f "docs/phase-0/frd.md" ]`, `[ -f "docs/phase-0/user-journey.md" ]`, `[ -f "docs/phase-0/data-contract.md" ]` with count display. No content validation equivalent to `validate_manifesto_content()`.
- **Enterprise Expectation:** Intermediate artifacts that feed the gate artifact (Manifesto) should have content validation, not just existence checks.
- **Current State:** The FRD, User Journey, and Data Contract are checked for file existence only. An empty `frd.md` file would pass the check. The Manifesto itself undergoes section and content validation (Finding P0-009), which provides indirect validation since the Manifesto synthesizes these intermediates.
- **Gap:** A PM could produce an empty or near-empty FRD and the CI check would pass, provided the Manifesto itself has content. The templates include review checklists (`frd.tmpl:56-60`, `user-journey.tmpl:63-68`, `data-contract.tmpl:74-79`), but these are for human review — there is no automated verification that the checklists are addressed.
- **Impact:** Low. The Manifesto content validation (P0-009) serves as a downstream catch. If the FRD is empty but the Manifesto Section 2 (Functional Requirements) has substantive content, the process has still produced adequate output. The intermediate files are working documents, not gate artifacts.

---

### Finding P0-014: Session Recovery Procedure Is Documented but Not Mechanically Assisted
- **Severity:** Minor
- **Category:** Workflow Gap
- **Evidence:** `builders-guide.md:257` — "If the conversation is lost mid-Phase 0, start a new session. Provide the agent with any saved intermediate files from docs/phase-0/ and the Project Intake. Resume from the last incomplete step."
- **Enterprise Expectation:** Session recovery should be mechanically assisted where feasible.
- **Current State:** The Builder's Guide documents the recovery procedure (provide saved files + Intake, resume from last incomplete step). The intermediate files are saved to disk at each step, preserving progress. No script or command exists to automate the recovery (e.g., detect which intermediates exist and generate a recovery prompt).
- **Gap:** A `scripts/resume.sh` file exists in the repository (found via grep), but its relationship to Phase 0 session recovery was not verified during this audit. The Builder's Guide does not reference any resume script for Phase 0 specifically.
- **Impact:** Low. Phase 0 is 3-5 hours in a single session. The saved intermediate files provide adequate recovery data. A PM can manually determine which steps are complete by checking `docs/phase-0/` for existing files.

---

### Finding P0-015: User Guide and Builder's Guide Are Consistent on Phase 0 Content
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** Cross-comparison of `builders-guide.md:247-513` with `user-guide.md:530-702`. Prompts, remediation tables, and step descriptions match. User Guide provides the PM-focused "Your Action" table (lines 534-541) plus the same prompts in collapsed detail blocks.
- **Enterprise Expectation:** Multiple documents addressing the same process should be consistent to prevent conflicting instructions.
- **Current State:** The Builder's Guide is the authoritative technical reference. The User Guide is the PM-oriented operational guide. Both carry the same prompts, review checklists, and remediation tables. The User Guide adds practical "Your Action" tables that translate Builder's Guide steps into PM-level actions, and provides separate columns for personal vs. organizational paths.
- **Gap:** None. Consistency is maintained.
- **Impact:** Positive. A PM can use the User Guide as their primary reference and consult the Builder's Guide for deeper technical context.

---

### Finding P0-016: Approval Log Templates Correctly Differentiate Personal and Organizational Paths
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `approval-log-org.tmpl` — 164 lines with pre-condition table, detailed gate entries with Method/Reference/Evidence fields, dual approval for Phase 3->4 (App Owner + IT Security), attorney review section, penetration test section. `approval-log-personal.tmpl` — 86 lines with streamlined entries, pre-conditions pre-filled as N/A, simpler gate entries.
- **Enterprise Expectation:** Governance artifacts should be right-sized for the deployment context — not burdening personal projects with enterprise overhead, and not letting organizational projects use insufficient tracking.
- **Current State:** Two distinct templates exist. The organizational template captures approver name, role, date, method, reference, artifacts reviewed, decision, conditions, and notes for each gate. The personal template captures reviewer, date, artifacts reviewed, decision, and notes. Both are generated by `init.sh`.
- **Gap:** None. The differentiation is well-designed.
- **Impact:** Positive. An organizational PM gets the full audit trail structure. A personal-project PM gets a lightweight but still useful record.

---

### Finding P0-017: Compliance Screening Matrix Is Embedded in Intake, Not Standalone
- **Severity:** Observation
- **Category:** Missing Template
- **Evidence:** `templates/project-intake.md:400-413` (Section 8.4); `governance-framework.md:466-483` (Section VIII.11); `builders-guide.md:1573` — "Compliance Screening Matrix: Embedded in Intake Section 8.4."
- **Enterprise Expectation:** Compliance screening results that gate Phase 0 to Phase 1 should be independently reviewable by the Project Sponsor.
- **Current State:** The compliance screening matrix exists in the Intake Section 8.4 with 8 yes/no questions mapping to required actions and status tracking. The Governance Framework Section VIII.11 defines the same questions with "If Yes" actions. The Builder's Guide Appendix A explicitly documents that the matrix is embedded in the Intake.
- **Gap:** The matrix is part of a larger document (Intake), which means sending it for sponsor review requires sending the entire Intake. However, since the Intake is the foundational document that the sponsor should review anyway, this is a design choice rather than a gap.
- **Impact:** Negligible. The Approval Log organizational template (line 45) explicitly lists "Compliance Screening Matrix (Intake Section 8.4)" as a reviewed artifact, making it traceable.

---

### Finding P0-018: Evaluation Prompts Provide Multi-Perspective Post-Hoc Review
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `evaluation-prompts/Projects/bases/` — 6 review templates covering Senior Engineer, CIO, Security, Legal, Technical User, and Red Team perspectives. Each template provides a structured, multi-phase review with specific output requirements.
- **Enterprise Expectation:** Framework quality should be verifiable through independent evaluation mechanisms.
- **Current State:** The evaluation prompts are designed for use against completed projects (not Phase 0 specifically), but they provide a comprehensive post-hoc verification system. The CIO review covers governance fit, the Security review covers compliance gap analysis, and the Legal review covers regulatory risk. These are available to run against any project at any time.
- **Gap:** None of the evaluation prompts are Phase 0-specific. They evaluate completed projects. Phase 0 quality is evaluated through the gate mechanism, not through evaluation prompts.
- **Impact:** Positive for overall framework governance. The evaluation prompts are a strong quality assurance mechanism, even though they are not Phase 0-specific.

---

### Finding P0-019: Steps 0.5-0.7 Are Track-Conditional Without Mechanical Enforcement
- **Severity:** Minor
- **Category:** Missing Enforcement
- **Evidence:** `builders-guide.md:448` — "Step 0.5: Revenue Model & Unit Economics (Standard+ Track -- skip for internal tools)"; `builders-guide.md:489` — "Step 0.7: Trademark & Legal Pre-Check (Standard+ Track)". `scripts/check-phase-gate.sh` — No track-conditional checks for Phase 0 artifacts.
- **Enterprise Expectation:** Track-conditional requirements should be enforced mechanically when the track is known.
- **Current State:** Steps 0.5 and 0.7 are documented as Standard+ Track only. The `check-phase-gate.sh` script reads the track from `phase-state.json` (line 103) and uses it for Phase 3 to Phase 4 POC mode blocking (lines 350-363), but does not use it to verify that Standard+ Phase 0 artifacts exist (e.g., revenue model appendix, trademark search appendix).
- **Gap:** A Standard Track project could skip the revenue model and trademark check without any CI warning. The enforcement is purely Tier 3 (LLM — the agent should follow the Builder's Guide instruction to include these steps for Standard+ projects).
- **Impact:** Low for Light Track projects (correctly exempt). For Standard and Full Track organizational projects, the revenue model and trademark check are important — missing them could lead to architecture decisions based on unsustainable unit economics or trademark conflicts discovered after investment.

---

### Finding P0-020: Open Questions Resolution Is Mechanically Enforced at Gate
- **Severity:** Observation (Positive)
- **Category:** N/A — Strength
- **Evidence:** `scripts/check-phase-gate.sh:145-150` — Checks for "Status: Open" in PRODUCT_MANIFESTO.md and reports count of unresolved questions as `[FAIL]`. `product-manifesto.tmpl:155-161` — Open Questions section with Status: Open / Resolved format.
- **Enterprise Expectation:** Unresolved questions should block phase transition.
- **Current State:** The `validate_manifesto_content()` function in `check-phase-gate.sh` searches for any Open Question with "Status: Open" and emits a `[FAIL]` with the count. This is a Tier 1 (CI) enforcement that prevents the Phase 0 to Phase 1 gate from passing with unresolved questions.
- **Gap:** None.
- **Impact:** Positive. This prevents a PM from proceeding to Phase 1 with ambiguities that should have been resolved in Phase 0.

---

## 3. Remediation Plan

| ID | Finding | Fix Description | Files to Create/Modify | Acceptance Criteria |
|---|---|---|---|---|
| P0-006 | Pre-condition threshold is 3, not 6; warn-mode bypass available | Change pre-condition count threshold from `< 3` to `< 6`. Add a comment documenting that `SOIF_PHASE_GATES=warn` intentionally downgrades for development/testing and should not be used in production CI. Consider a separate env var (`SOIF_PRECOND_STRICT=true`) to make pre-conditions non-downgradable even in warn mode. | `scripts/check-phase-gate.sh` (line 195) | CI fails when fewer than 6 dated pre-condition entries exist for organizational deployments. The warn-mode documentation explicitly states it is for non-production use. |
| P0-007 | Self-approval detection is heuristic warning | Upgrade the self-approval check to `[FAIL]` severity (not `[WARN]`) for organizational deployments. Document in the Governance Framework that the primary control is git commit authorship verification and out-of-band confirmation, with the CI check as a supplementary detective control. Consider adding a check that the `APPROVAL_LOG.md` entry was committed by a git author different from the configured Orchestrator user. | `scripts/check-phase-gate.sh` (lines 170-182), `docs/governance-framework.md` (lines 176-181) | Self-approval detection emits `[FAIL]` for organizational deployments. Git author mismatch check is implemented or documented as a future enhancement. |
| P0-003 | Step 0.7 has no review checklist | Add a review checklist to Step 0.7 in the Builder's Guide and the Manifesto template Appendix C, consistent with Steps 0.1-0.3. | `docs/builders-guide.md` (after line 494), `templates/generated/product-manifesto.tmpl` (after line 220) | Step 0.7 has a review checklist with checkboxes covering: trademark search completed, data privacy applicability assessed, distribution channel requirements documented. |
| P0-013 | Phase 0 intermediate content validation is existence-only | Add lightweight content validation for Phase 0 intermediates in `check-phase-gate.sh`: verify each file has content beyond template headers (similar to the Manifesto section check). | `scripts/check-phase-gate.sh` (after line 249) | CI warns if `docs/phase-0/frd.md`, `user-journey.md`, or `data-contract.md` contain only template placeholders with no substantive content. |
| P0-019 | Track-conditional steps 0.5/0.7 have no mechanical enforcement | Add track-conditional checks to `check-phase-gate.sh` for Phase 0 to Phase 1: if track is "standard" or "full", verify that Manifesto Appendices A and C have content beyond placeholders. | `scripts/check-phase-gate.sh` (in the Phase 0 to Phase 1 artifact check section) | Standard and Full Track projects trigger a warning if Manifesto Appendix A (Revenue Model) or Appendix C (Trademark) contain only placeholder content. |

---

## 4. Verification Test Plan

| ID | Test | Method | Expected Result |
|---|---|---|---|
| VT-001 | Pre-condition threshold enforcement | Create a test `APPROVAL_LOG.md` with only 4 of 6 pre-condition dates for an organizational deployment. Run `check-phase-gate.sh`. | Script emits `[WARN]` or `[FAIL]` indicating insufficient pre-conditions. (After remediation of P0-006: emits `[FAIL]` or `[WARN]` with threshold of 6.) |
| VT-002 | Manifesto content validation | Create a `PRODUCT_MANIFESTO.md` with all 8 section headings but template-only content. Set `phase-state.json` to phase 1. Run `check-phase-gate.sh`. | Script emits `[WARN]` for sections with placeholder content. |
| VT-003 | Open Questions blocking | Add an Open Question with "Status: Open" to `PRODUCT_MANIFESTO.md`. Run `check-phase-gate.sh`. | Script emits `[FAIL]` with count of unresolved questions. |
| VT-004 | Phase gate snapshot creation | Set `phase-state.json` to phase 1 with a gate date. Ensure `docs/snapshots/` does not contain a Phase 0-to-1 snapshot. Run `check-phase-gate.sh` with all checks passing. | Snapshot directory `docs/snapshots/phase-0-to-1_YYYY-MM-DD/` is created with copies of `PRODUCT_MANIFESTO.md`, `APPROVAL_LOG.md`, `PROJECT_INTAKE.md`, and `docs/phase-0/*.md`. |
| VT-005 | Self-approval detection | Configure git user.name to match the approver name in APPROVAL_LOG.md for an organizational deployment. Run `check-phase-gate.sh`. | Script emits `[WARN]` indicating self-approval detected. |
| VT-006 | Intermediate file existence check | Create `docs/phase-0/` with only `frd.md` (missing user-journey.md and data-contract.md). Run `check-phase-gate.sh` at phase 1. | Script emits `[WARN]` indicating 1/3 intermediates saved. |
| VT-007 | Personal project approval log | Use `approval-log-personal.tmpl` structure. Verify pre-conditions are pre-filled as N/A. Add a Phase 0 to Phase 1 self-review entry. Run `check-phase-gate.sh`. | Script passes without pre-condition warnings (personal deployment skips organizational pre-condition checks). |
| VT-008 | Track-conditional Step 0.5 | Set `phase-state.json` track to "standard". Create Manifesto with empty Appendix A. Run `check-phase-gate.sh`. | (After remediation of P0-019: Script warns about empty Revenue Model for Standard track.) |
| VT-009 | End-to-end Phase 0 walkthrough | Follow the Builder's Guide Steps 0.1-0.4 using the "Without Intake" prompts with a test project. Verify all artifacts are produced at the specified locations. | FRD at `docs/phase-0/frd.md`, User Journey at `docs/phase-0/user-journey.md`, Data Contract at `docs/phase-0/data-contract.md`, Manifesto at `PRODUCT_MANIFESTO.md`. All have substantive content matching template structure. |
| VT-010 | Intake-first path validation | Complete the Project Intake template. Provide to agent with Builder's Guide. Execute Steps 0.1-0.4 using "With Intake" prompts. | Agent validates and expands Intake data. Artifacts reference Intake sections. Contradictions flagged. Implicit dependencies identified. |

---

## 5. Summary

### By Severity

| Severity | Count |
|---|---|
| Critical | 0 |
| Major | 2 |
| Minor | 6 |
| Observation (Positive) | 8 |
| Observation (Neutral) | 1 |
| **Total findings** | **17** |

*Note: P0-008 through P0-012, P0-015, P0-016, P0-018, and P0-020 are positive findings (strengths). They are included in the count for completeness but do not represent gaps.*

### By Category

| Category | Count |
|---|---|
| Missing Template | 2 (P0-001, P0-002) |
| Missing Validation | 2 (P0-003, P0-013) |
| Missing Enforcement | 2 (P0-005, P0-019) |
| Missing Storage | 1 (P0-004) |
| Bypass Risk | 2 (P0-006, P0-007) |
| Workflow Gap | 1 (P0-014) |
| Strength (no gap) | 8 |

---

## 6. Strengths

The following controls are effective and well-designed:

1. **Template completeness for core steps (Steps 0.1-0.4).** Each of the four core Phase 0 steps has: a dedicated structural template, clear save-as instructions with canonical filenames and paths, a review checklist (Steps 0.1-0.3), and dual-path prompts for both Intake-first and conversational discovery. This is the strongest aspect of Phase 0 and represents genuine process engineering, not documentation theater.

2. **Manifesto content validation in CI (P0-009).** The `validate_manifesto_content()` function goes beyond file existence to verify structural completeness (all 8 sections), content substance (not just placeholders), and unresolved question detection. This is Tier 1 enforcement at a level most frameworks do not achieve.

3. **Phase gate snapshot mechanism (P0-010).** Timestamped, immutable copies of all Phase 0 artifacts at the gate transition provide audit evidence that would satisfy an ISO 9001 auditor. Combined with git history, this creates a strong evidence chain.

4. **Gate Denial Procedure (P0-008).** The maximum 2 rework cycles with escalation to Project Sponsor is a well-designed control that prevents denial loops while maintaining governance rigor. The requirement to record all denials in the Approval Log creates a complete audit trail.

5. **Dual-path documentation (P0-011, P0-015).** The Builder's Guide and User Guide serve different audiences (technical execution vs. PM operational guidance) while maintaining content consistency. A PM can use the User Guide without consulting the Builder's Guide for basic execution. The "Your Action" tables in the User Guide (personal vs. organizational columns) are particularly effective.

6. **Approval Log differentiation (P0-016).** Two distinct templates for personal and organizational deployments appropriately scale governance overhead. The organizational template's structured evidence fields (method, reference, evidence) support audit requirements. The personal template is lightweight but still maintains an audit trail.

7. **Open Questions blocking enforcement (P0-020).** Mechanically preventing Phase 1 entry when Open Questions remain unresolved is a simple but high-impact control. It forces resolution of ambiguities during Phase 0 rather than carrying them forward.

8. **Intake Wizard (P0-012).** The interactive guided experience with progress tracking, context-aware suggestions, and pause/resume capability materially reduces onboarding friction. For a PM unfamiliar with the framework, this is the difference between a 4-hour form-filling exercise and a 1-2 hour guided conversation.

**Overall assessment:** Phase 0 of the Solo Orchestrator Framework is well-designed for its stated purpose. The two Major findings (P0-006 pre-condition threshold and P0-007 self-approval detection) are real enforcement gaps that should be remediated for organizational deployments, but they do not prevent a PM from following the process or producing consistent artifacts. The framework is strongest in its template design, dual-path documentation, and gate validation mechanisms. A PM with no prior framework experience could follow this process and produce reviewable, auditable Phase 0 artifacts.

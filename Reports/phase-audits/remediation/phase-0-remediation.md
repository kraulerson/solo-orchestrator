# Phase 0 — Product Discovery: Remediation Plan

**Source Audit:** Reports/phase-audits/2026-04-08-phase-0-audit.md
**Findings:** 15 (1 Critical, 7 Major, 6 Minor, 1 Observation)
**Date:** 2026-04-08

---

## Critical Findings

### P0-003: No Validation of PRODUCT_MANIFESTO.md Content Completeness

**The Problem:** The Phase 0-to-1 gate (`scripts/check-phase-gate.sh`, lines 116-123) checks only that `PRODUCT_MANIFESTO.md` exists as a file. It does not inspect the file's content. A Manifesto containing nothing but the original template boilerplate — placeholder brackets, instructional comments, and unfilled sections — passes the gate and permits entry to Phase 1. This is the framework's single most consequential gate (no code is built until Phase 1 completes), and it currently provides zero assurance that the artifact contains real requirements.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Section-header + content heuristic in `check-phase-gate.sh`.** Parse `PRODUCT_MANIFESTO.md` for all 8 required `## N.` headings. For each section, verify that (1) the heading exists and (2) at least one non-comment, non-placeholder line of content follows before the next heading. Define "placeholder" as lines matching the template's bracket pattern `[...]` or the HTML comment markers `<!-- -->`. Fail the gate if any section is header-only or placeholder-only. | Mechanical. No new dependencies. Catches the exact failure mode (template defaults passing). Can be extended per-section over time. | Heuristic — a single sentence of garbage technically passes. Cannot validate semantic quality. | Small — ~60 lines of bash added to existing script. | High. New sections in the template just require adding the heading to the check list. The pattern is generic: "heading exists, content follows." |
| B | **JSON schema validator.** Convert the Manifesto to a structured format (YAML frontmatter + markdown body, or a parallel JSON representation). Validate against a schema that enforces required fields, minimum lengths, and enumerated values (e.g., `Status: Approved`). | Strongest validation. Catches more edge cases. Enables downstream tooling (diffing, reporting). | Breaks the current markdown-only workflow. Requires maintaining a schema alongside the template. Adds a dependency (e.g., `ajv-cli` or `yq`). Significantly higher migration cost. | Medium-Large — schema definition, conversion tooling, CI integration, template restructuring. | Medium. Schema and template must be kept in sync. Schema drift is a new failure mode. |
| C | **LLM-based completeness check.** At the Phase 0-to-1 gate, invoke Claude (via API or `claude` CLI) to evaluate the Manifesto against a rubric: "Are all 8 sections substantively populated? Are there unresolved placeholders?" Output a pass/fail with rationale. | Semantic validation — catches vague or nonsensical content, not just structural placeholders. | Non-deterministic. Requires API access in CI. Adds latency and cost to every gate check. Audit trail must capture the LLM's rationale, which varies between runs. Enterprise compliance teams will question a non-deterministic gate. | Medium — prompt engineering, CI integration, output capture. | Low. Model changes, prompt drift, and cost scaling make this fragile long-term. |

**Recommendation:** Option A. The failure mode is structural (template defaults passing), not semantic (bad requirements). A deterministic heuristic that fails on placeholder content closes the gap permanently without introducing non-determinism or new dependencies. Semantic quality is the Orchestrator's responsibility at the review step — the gate's job is to prevent the _absence_ of review, not to replace it.

**Files to Modify:**
- `scripts/check-phase-gate.sh` — add `validate_manifesto_content()` function, called when `current_phase >= 1`

**Acceptance Criteria:**
- A `PRODUCT_MANIFESTO.md` containing only the template from `templates/generated/product-manifesto.tmpl` fails the Phase 0-to-1 gate with a message identifying which sections are incomplete.
- A Manifesto with all 8 numbered sections populated with non-placeholder content passes.
- A Manifesto missing any of the 8 numbered section headings fails with a message naming the missing section.
- Appendices (A, B, C) are validated conditionally based on project track (see P0-007 linkage).

**Verification Test:**
- Copy `templates/generated/product-manifesto.tmpl` to a test directory as `PRODUCT_MANIFESTO.md`. Set `phase-state.json` to `current_phase: 1`. Run `check-phase-gate.sh`. Expected: exit 1 with "[FAIL] PRODUCT_MANIFESTO.md Section 1 (Product Intent): contains only placeholder content."
- Populate all 8 sections with substantive text. Re-run. Expected: exit 0 (or only unrelated warnings).
- Remove Section 4 heading entirely. Re-run. Expected: exit 1 with "[FAIL] PRODUCT_MANIFESTO.md: missing required section '## 4. Data Contracts'."

---

## Major Findings

### P0-001: No Template for Steps 0.1-0.3 Intermediate Outputs

**The Problem:** Steps 0.1 (FRD), 0.2 (User Journey), and 0.3 (Data Contract) each produce structured work products, but no template defines their expected format. The outputs exist only as freeform text in the AI conversation. Without a template, there is no standard structure for review, no machine-verifiable format, and no consistency across projects. Reviewers receive whatever the AI happened to generate in that session.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Add lightweight templates to `templates/generated/`.** Create `frd.tmpl`, `user-journey.tmpl`, and `data-contract.tmpl`. Each template mirrors the structure already prescribed in the Builder's Guide prompts (e.g., FRD has Must-Have/Should-Have/Will-Not-Have with logic triggers and failure states). Templates include section headings, placeholder instructions, and format examples. Update the Builder's Guide Step 0.1-0.3 prompts to reference the templates. | Standardizes output format. Enables machine verification (P0-003 pattern reuse). Low migration cost — structure already exists in prose. | Three new files to maintain. Templates must stay synchronized with Builder's Guide prose. | Small — extract existing structure from Builder's Guide prompts into template files. Update 3 prompt blocks. | High. Templates are derived from existing prose — they formalize what is already described. Changes to the methodology update both. |
| B | **Prescribe the Manifesto template as the single output for all steps.** Instead of separate intermediate templates, instruct the agent to populate the Manifesto incrementally: Step 0.1 fills Sections 2 and 7, Step 0.2 fills Section 3, Step 0.3 fills Section 4. No separate files. | One artifact, no drift between intermediates and final. Simpler file management. | Loses the ability to review each intermediate independently. Conflates "work in progress" with "approved artifact." Harder to diff what changed between steps. Step 0.1 output is richer than what fits in the Manifesto's FRD section (e.g., logic triggers with rationale). | Small — update Builder's Guide prompts only. | Medium. Works until a phase requires an intermediate output that does not map cleanly to a Manifesto section. |

**Recommendation:** Option A. The intermediate work products contain detail that is deliberately summarized when synthesized into the Manifesto. Preserving the full FRD, User Journey, and Data Contract as discrete artifacts provides audit depth and enables the reviewer to see the agent's reasoning, not just the final summary. This also directly addresses P0-002 and P0-011.

**Files to Modify:**
- `templates/generated/frd.tmpl` — new file
- `templates/generated/user-journey.tmpl` — new file
- `templates/generated/data-contract.tmpl` — new file
- `docs/builders-guide.md` — update Step 0.1, 0.2, 0.3 prompts to reference templates

**Acceptance Criteria:**
- Each template exists in `templates/generated/` with section headings matching the Builder's Guide review checklist items.
- Builder's Guide Step 0.1-0.3 prompts include explicit "Save as: `docs/phase-0/frd.md`" (or equivalent) instructions.
- Template structure enables the same placeholder-detection heuristic used for P0-003.

**Verification Test:**
- Run Phase 0 Steps 0.1-0.3 with the updated prompts. Confirm output is saved to the prescribed filenames.
- Verify each output matches the template structure (section headings present, placeholders replaced).

---

### P0-002: Steps 0.1-0.3 Outputs Not Persisted as Discrete Files

**The Problem:** The Builder's Guide prescribes no file save instruction until Step 0.4 (`PRODUCT_MANIFESTO.md`). Steps 0.1-0.3 produce the FRD, User Journey Map, and Data Contract, but these exist only in the AI conversation context. If the session is interrupted (timeout, crash, context window exceeded), all intermediate work is lost. This is a single point of failure at the conversation level for 60-80% of Phase 0's intellectual output.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Add explicit "Save as" instructions at each step.** Prescribe `docs/phase-0/frd.md`, `docs/phase-0/user-journey.md`, `docs/phase-0/data-contract.md`. Update Builder's Guide Steps 0.1-0.3 with a "Save as:" directive after each review checklist. Combined with P0-001 templates. | Eliminates single point of failure. Produces reviewable artifacts. Feeds into P0-011 (snapshot) and P0-017 (session recovery). | Adds 3 file operations to Phase 0. Agent must be instructed to save after each step. | Minimal — 3 lines added to Builder's Guide. | High. The pattern ("produce output, save to file") is the same pattern used in every other phase. |
| B | **Auto-save via CLAUDE.md session hooks.** Configure the CLAUDE.md template to include a post-step hook that automatically saves conversation output to `docs/phase-0/`. | Automatic — no human action required. | Relies on Claude Code hook infrastructure (Tier 3 enforcement). Hook must parse conversation to identify which step just completed. Fragile if conversation structure varies. | Medium — hook implementation, output parsing. | Low. Conversation format changes break the parser. |

**Recommendation:** Option A. Explicit save instructions are the simplest, most robust solution. This is a documentation fix, not an engineering problem. Combined with P0-001 (templates provide the format) and P0-011 (snapshots capture the files), this closes three findings with one coherent change.

**Files to Modify:**
- `docs/builders-guide.md` — add "Save as:" directive to Steps 0.1, 0.2, 0.3
- `scripts/check-phase-gate.sh` — optionally add existence checks for `docs/phase-0/*.md` at Phase 0-to-1 gate

**Acceptance Criteria:**
- Builder's Guide Steps 0.1-0.3 each end with a "Save as: `docs/phase-0/<filename>.md`" instruction.
- After completing Phase 0, `docs/phase-0/` contains `frd.md`, `user-journey.md`, and `data-contract.md`.
- Phase 0-to-1 gate optionally warns if intermediate files are missing (not blocking — the Manifesto is the gating artifact).

**Verification Test:**
- Follow updated Builder's Guide Steps 0.1-0.3. Verify files exist at prescribed paths.
- Simulate session loss after Step 0.2. Resume in new session. Verify `frd.md` and `user-journey.md` are intact and resumable.

---

### P0-004: APPROVAL_LOG Validation Too Shallow

**The Problem:** The Phase 0-to-1 gate check (`check-phase-gate.sh`, lines 103-106) validates the Approval Log using `grep -q "Phase 0.*Phase 1"` followed by a date pattern match. This pattern is satisfied by the template defaults — the section heading "Phase 0 → Phase 1" and the placeholder date format `YYYY-MM-DD` are sufficient to pass. The gate provides false assurance that an approval has been recorded when the log may contain only boilerplate.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Field-level validation in `check-phase-gate.sh`.** After finding the Phase 0-to-1 section, extract key fields (Approver, Date, Decision) and verify: (1) Approver field is non-empty and not a placeholder, (2) Date matches `YYYY-MM-DD` with valid ranges (not `YYYY-MM-DD` literal), (3) Decision field contains "Approved" (not the template default "Approved / Approved with conditions / Rejected"). Use the existing grep+sed parsing pattern already in the script. | Deterministic. No dependencies. Catches exact failure mode. Extensible to other gates. | Markdown parsing in bash is fragile if the template format changes. Must be updated when template structure changes. | Small — ~40 lines of bash. | Medium-High. Tied to template structure, but template changes are infrequent and the parsing is simple. |
| B | **Structured frontmatter approach.** Add YAML frontmatter to `APPROVAL_LOG.md` with machine-readable fields (`approver:`, `date:`, `decision:`). Parse frontmatter in the gate check instead of markdown body. | Cleaner parsing. Separates machine-readable data from human-readable narrative. | Requires template change. Requires frontmatter parser in bash (or `yq` dependency). Dual-maintenance of frontmatter and markdown body. | Medium — template change, parser, migration path for existing projects. | Medium. Frontmatter and body can drift if one is updated without the other. |

**Recommendation:** Option A. The current template structure is well-defined and stable. Field-level validation using the existing parsing approach is sufficient and avoids introducing new dependencies. The key check is: "Is the Approver field something other than empty/placeholder, and is the Decision field a resolved value?"

**Files to Modify:**
- `scripts/check-phase-gate.sh` — add `validate_approval_entry()` function

**Acceptance Criteria:**
- An Approval Log with the Phase 0-to-1 section containing only template defaults fails the gate with "[FAIL] APPROVAL_LOG.md Phase 0→1: Approver field is empty or placeholder."
- An Approval Log with a populated approver name, a valid date, and "Approved" as the decision passes.
- Validation applies to all gate sections (0-to-1, 1-to-2, 3-to-4), not just Phase 0.

**Verification Test:**
- Use the unmodified `approval-log-org.tmpl` as `APPROVAL_LOG.md`. Set `current_phase: 1`. Run gate check. Expected: fail.
- Fill in Approver: "Jane Smith", Date: "2026-04-08", Decision: "Approved". Re-run. Expected: pass.
- Set Decision to "Approved / Approved with conditions / Rejected" (template default). Re-run. Expected: fail.

---

### P0-005: Phase 0-to-1 Gate Lacks Personal/Organizational Distinction

**The Problem:** `check-phase-gate.sh` performs identical validation regardless of whether the project is a personal or organizational deployment. For organizational deployments, the Governance Framework (Section V, lines 177-182) requires that the Orchestrator must not author the git commit adding their own name as approver — self-approval must be detectable. The current gate check has no mechanism to read the deployment type or compare the git commit author against the listed approver.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Read deployment type from `phase-state.json`; enforce tier-appropriate checks.** For personal projects: require Reviewer and Date fields populated (self-review is valid). For organizational projects: require Approver and Role fields populated, verify Approver name does not match the git `user.name` config, and warn if the git author of the approval commit matches the listed approver. | Enforces the governance intent mechanically. Distinguishes self-review (valid for personal) from self-approval (invalid for organizational). | Git author comparison is heuristic — name formatting differences cause false positives. The comparison catches obvious self-approval but not deliberate evasion (e.g., committing as a colleague). | Small-Medium — ~30 lines to read deployment type, ~20 lines for author comparison. | High. Deployment type is set at project init and does not change (except via upgrade-project.sh). |
| B | **Require GPG-signed approval commits for organizational deployments.** The approver's commit must be signed with a GPG key registered to their identity. Verify the signature in CI. | Cryptographic proof of identity. Eliminates name-spoofing. | Requires GPG infrastructure. High barrier to adoption — most enterprise approvers are not developers and do not have GPG keys. Excludes approval via email or ticket. | Large — GPG key distribution, CI verification, approver onboarding. | High (if adopted). But adoption barrier makes it impractical for v1.0. |

**Recommendation:** Option A. The goal is detection, not cryptographic proof. Comparing the listed approver against the git commit author catches the common case (Orchestrator self-approving) without requiring infrastructure changes. False positives (name format mismatch) are acceptable as warnings, not hard blocks. Deliberate evasion is addressed by the quarterly audit control already prescribed in the Governance Framework.

**Files to Modify:**
- `scripts/check-phase-gate.sh` — read `deployment` from `phase-state.json`, branch validation logic
- `.claude/phase-state.json` — ensure `deployment` field is present (already set by `init.sh`)

**Acceptance Criteria:**
- For organizational projects: gate warns if the git author of the most recent `APPROVAL_LOG.md` commit matches the listed Approver name (case-insensitive substring match).
- For personal projects: gate accepts self-review without warning.
- Deployment type is read from `phase-state.json`, not hardcoded.

**Verification Test:**
- Create an organizational project. Commit an APPROVAL_LOG.md entry listing yourself as Approver, authored by your git identity. Run gate check. Expected: warning "[WARN] Approval Log Phase 0→1: git commit author matches listed approver — self-approval detected for organizational deployment."
- Change the Approver to a different name. Re-run. Expected: no warning.
- Switch to personal deployment. Self-review passes without warning.

---

### P0-008: Competency Matrix Does Not Gate CI Tool Installation

**The Problem:** The Builder's Guide (lines 460-468) states that for each domain marked "No" in the Competency Matrix, the corresponding automated tool "MUST be installed and active in the CI pipeline before Phase 2 begins." However, no script enforces this. The Competency Matrix exists in Appendix B of the Product Manifesto and in Section 6.2 of the Project Intake, but `check-phase-gate.sh` does not read either document. A project where the Orchestrator marks "Security: No" can proceed to Phase 2 without Semgrep, SAST, or any security tooling in CI.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Phase 1-to-2 gate check: parse Competency Matrix, verify CI pipeline.** At the Phase 1-to-2 gate, read the Competency Matrix from `PRODUCT_MANIFESTO.md` (Appendix B) or `.claude/tool-preferences.json`. For each domain marked "No," verify the corresponding CI step exists in `.github/workflows/ci.yml`. Map domains to CI step names using a lookup table (e.g., "Security" maps to `semgrep-action` or `Semgrep`). | Closes the loop between competency self-assessment and CI enforcement. Deterministic. Uses existing data. | Requires a maintained mapping between Matrix domains and CI step identifiers. CI step names vary by language template. Parsing the Matrix from markdown is somewhat fragile. | Medium — domain-to-CI-step mapping, markdown parser for Matrix table, CI YAML grep. | Medium. The mapping must be updated when new CI templates are added or domain categories change. Centralizing the mapping in a JSON file (e.g., `templates/competency-ci-map.json`) improves maintainability. |
| B | **Record competency decisions in `tool-preferences.json` and verify at Phase 1-to-2 gate.** During intake or Phase 0, persist competency answers to `.claude/tool-preferences.json` (which `resolve-tools.sh` already reads). The gate check verifies that required tools from the resolver output are installed. | Leverages existing tool resolution infrastructure. Structured data, no markdown parsing. | Requires updating the intake wizard to persist competency data. `tool-preferences.json` structure must be extended. | Medium — extend intake wizard, extend resolver, add gate check. | High. The tool resolver already handles the "is this installed?" question. Adding competency as an input source is a natural extension. |

**Recommendation:** Option B is the better long-term architecture because it builds on the existing `resolve-tools.sh` infrastructure. However, Option A is recommended for the initial fix because it requires fewer changes and can be implemented within `check-phase-gate.sh` alone. Option B should be planned as a follow-up when the tool resolver is next updated.

**Files to Modify:**
- `scripts/check-phase-gate.sh` — add `validate_competency_tooling()` function at Phase 1-to-2 gate
- `templates/competency-ci-map.json` — new file mapping domains to CI step identifiers (cross-language)

**Acceptance Criteria:**
- At the Phase 1-to-2 gate, if the Competency Matrix contains a "No" for any domain, the gate verifies the corresponding CI tool is present in the CI workflow file.
- Missing tool produces a blocking failure: "[FAIL] Competency Matrix: domain 'Security' marked 'No' but CI pipeline has no SAST step."
- Domains marked "Yes" or "Partially" are not checked (Partially is recommended, not gating, per Builder's Guide).

**Verification Test:**
- Set Competency Matrix Security domain to "No." Remove the Semgrep step from `ci.yml`. Run gate check at Phase 1-to-2. Expected: fail.
- Add Semgrep step back. Re-run. Expected: pass.
- Change Security to "Yes." Remove Semgrep. Re-run. Expected: pass (domain is self-validated).

---

### P0-010: Pre-Phase 0 Pre-Conditions Advisory for Organizational Deployments

**The Problem:** The Governance Framework (Section V) defines 6 blocking pre-conditions for organizational deployments (AI deployment path, insurance, liability entity, project sponsor, backup maintainer, ITSM registration). These must be completed before Phase 0 begins. However, `check-phase-gate.sh` only validates post-Phase-0 gates. There is no script-level check that prevents an organizational project from starting Phase 0 without meeting pre-conditions. The `approval-log-org.tmpl` contains a table for recording pre-conditions, but it is not verified.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Add a pre-Phase 0 validation function to `check-phase-gate.sh`.** For organizational projects where `current_phase == 0`, parse the Pre-Phase 0 section of `APPROVAL_LOG.md` and verify that all 6 pre-condition rows have a populated Date and a non-placeholder value in the Approver column. Respect POC mode: Sponsored POC requires items 1, 4, 8 only; Private POC defers all. | Catches the exact failure mode. Runs automatically in CI. Respects the existing POC exception model. | Adds complexity to the gate check for Phase 0 (currently the simplest phase). Pre-conditions are typically resolved before the repo exists, so the check may fire too early. | Small-Medium — ~50 lines, reuses the field-extraction pattern from P0-004. | High. Pre-condition list is stable (defined in Governance Framework) and changes infrequently. |
| B | **Add a pre-flight check to `init.sh`.** During project initialization, if deployment type is "organizational," prompt for pre-condition status and block initialization until all are marked complete or the user explicitly selects POC mode. | Catches the gap at the earliest possible moment (project creation). Cannot be bypassed by skipping gate checks. | `init.sh` runs once. If pre-conditions are resolved after init, there is no re-check mechanism. Does not help projects already initialized. | Small — extend the existing governance section of `init.sh`. | Medium. One-time check has no ongoing enforcement power. Must be paired with a gate check for ongoing assurance. |

**Recommendation:** Option A, with a note that Option B is a complementary improvement for `init.sh` but is not sufficient alone. The gate check provides ongoing enforcement; `init.sh` provides early detection. Implement A first.

**Files to Modify:**
- `scripts/check-phase-gate.sh` — add `validate_preconditions()` function, called when deployment is organizational and `current_phase == 0`
- (Optional follow-up) `init.sh` — add pre-condition prompt for organizational deployments

**Acceptance Criteria:**
- For an organizational (non-POC) project at Phase 0, the gate check verifies all 6 pre-conditions have a populated Date and Approver.
- Missing pre-conditions produce a blocking failure: "[FAIL] Pre-Phase 0 pre-condition 'AI deployment path approved' is incomplete."
- For Sponsored POC, only items 1, 4, and 8 are required; others produce warnings.
- For Private POC, all pre-conditions produce informational notes only.
- Personal projects skip this check entirely.

**Verification Test:**
- Initialize an organizational project. Leave pre-conditions empty. Run gate check at Phase 0. Expected: 6 failures.
- Fill in all 6 pre-conditions. Re-run. Expected: pass.
- Switch to Sponsored POC. Leave items 2, 3, 5, 6 empty. Re-run. Expected: pass (with informational notes for deferred items).

---

### P0-012: Open Questions Not Verified at Gate

**The Problem:** Section 8 of the Product Manifesto template defines an Open Questions section where items carry a status of "Open" or "Resolved." The template explicitly states: "Each question must be resolved before the Phase 0 → Phase 1 gate is approved." However, `check-phase-gate.sh` does not parse this section. A Manifesto with `Status: Open` items passes the gate, allowing unresolved requirements to propagate into Phase 1 architecture decisions.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Grep for `Status: Open` in `PRODUCT_MANIFESTO.md` at the Phase 0-to-1 gate.** Simple pattern match: if the string `Status: Open` (case-insensitive) appears anywhere in the file, fail the gate with a message listing the question identifiers (Q1, Q2, etc.). | Minimal implementation. Directly enforces the template's own stated rule. No false positives — the only legitimate use of "Status: Open" in the template is an unresolved question. | Cannot distinguish "Status: Open" in Section 8 from a hypothetical use elsewhere in the document (low risk — no other section uses this pattern). Grepping the whole file is slightly imprecise. | Minimal — 5-10 lines of bash. | High. The pattern is defined by the template and will not change without a template version bump. |
| B | **Section-scoped parsing.** Extract only the `## 8. Open Questions` section and check for `Status: Open` within that section. | More precise — eliminates false positives from other sections. | More complex parsing for marginal benefit. The template does not use "Status: Open" outside Section 8. | Small — ~20 lines. | High. Slightly more robust than Option A but the additional robustness is not needed today. |

**Recommendation:** Option A for simplicity. The risk of a false positive is negligible given the template structure. If future template versions introduce "Status: Open" in other contexts, upgrade to Option B at that time.

**Files to Modify:**
- `scripts/check-phase-gate.sh` — add open-questions check within the Phase 0-to-1 gate block

**Acceptance Criteria:**
- A Manifesto containing any `Status: Open` item fails the Phase 0-to-1 gate with "[FAIL] PRODUCT_MANIFESTO.md: unresolved Open Questions detected. Resolve all questions before Phase 1."
- A Manifesto where all questions show `Status: Resolved` passes.
- A Manifesto with no Section 8 content (no open questions raised) passes.

**Verification Test:**
- Add `Status: Open` to one question in the Manifesto. Run gate check. Expected: fail.
- Change to `Status: Resolved — decided X`. Re-run. Expected: pass.

---

### P0-015: MVP Cutline Enforceable Only at Tier 3

**The Problem:** The MVP Cutline in the Product Manifesto (Section 5) defines which features are built in Phase 2 and which are deferred. This is currently enforced only by LLM instruction (Tier 3) — the agent is told not to build features below the cutline, but no CI or script check verifies compliance. Features built outside the cutline — scope creep — are undetectable until a human reviews the codebase against the Manifesto.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Phase 2-to-3 reconciliation check.** At the Phase 2-to-3 gate, require a `FEATURES.md` or equivalent manifest that lists every feature built. Compare the feature list against the MVP Cutline items in the Manifesto. Warn on features not in the cutline. This is a reporting/attestation check, not a blocking check — the Orchestrator may have legitimately approved scope additions during Phase 2. | Surfaces scope drift at a defined checkpoint. Does not block legitimate scope changes. Creates an auditable record. | Relies on `FEATURES.md` being maintained (Tier 3). Feature naming must be consistent between Manifesto and feature list for comparison. Cannot be fully automated — fuzzy matching between feature descriptions is unreliable. | Medium — feature list requirement, comparison logic (possibly heuristic), attestation prompt. | Medium. Effective as a review prompt. Full automation would require structured feature IDs, which is a larger change. |
| B | **Structured feature IDs.** Assign each MVP Cutline item an identifier (e.g., `MVP-001`) in the Manifesto. Require Phase 2 commits to reference a feature ID. At the Phase 2-to-3 gate, verify all MVP IDs have associated commits and no commits reference non-MVP IDs without an approval record. | Traceable. Mechanically verifiable. Closes the loop completely. | Significant process overhead. Commit message discipline is hard to enforce. Adds friction to every commit in Phase 2. | Large — ID assignment, commit convention, gate parser, approval workflow for scope additions. | High (if adopted). But the process overhead may discourage adoption. |

**Recommendation:** Option A. The practical risk is not that scope creep happens undetected forever — it is that scope creep is detected too late (at Phase 3 or after launch). A reconciliation checkpoint at Phase 2-to-3 that surfaces the comparison and requires Orchestrator attestation ("I reviewed the built features against the cutline and approved any additions") is proportionate to the risk. Option B is architecturally superior but disproportionate for a v1.0 framework targeting solo builders.

**Files to Modify:**
- `scripts/check-phase-gate.sh` — add Phase 2-to-3 reconciliation check (warn, not block)
- `docs/builders-guide.md` — add reconciliation step to Phase 2-to-3 gate instructions
- (Optional) `templates/generated/features.tmpl` — formalize the feature list format

**Acceptance Criteria:**
- At the Phase 2-to-3 gate, the script checks for the existence of `FEATURES.md` (or equivalent).
- If `FEATURES.md` exists, it warns if the count of listed features significantly exceeds the count of MVP Cutline items (heuristic for scope growth).
- The Builder's Guide Phase 2-to-3 gate instructions include a reconciliation step: "Compare FEATURES.md against the MVP Cutline. Record any scope additions and their approval rationale."

**Verification Test:**
- Create a `FEATURES.md` listing 5 features. Manifesto MVP Cutline lists 3. Run gate check. Expected: "[WARN] Phase 2→3: FEATURES.md lists 5 features; MVP Cutline specifies 3. Verify scope additions were approved."

---

### P0-018: Approval Log Commit Authorship Not Enforced

**The Problem:** The Governance Framework (Section V, lines 179-183) states that each approval entry "MUST be committed to `APPROVAL_LOG.md` by the approver, not the Orchestrator" and that CI "SHOULD enforce this where feasible." The use of "SHOULD" rather than "MUST" for CI enforcement means no CI step validates this. The only enforcement is a quarterly manual audit. This creates a 3-month window where fabricated approval entries go undetected — the primary anti-fraud control for the governance trail.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **CI warning step comparing commit author to listed approver.** Add a CI step that runs when `APPROVAL_LOG.md` is modified. Extract the most recent approver name from the file. Compare against the git commit author. If they match and the deployment is organizational, emit a CI annotation warning (not a blocking failure). Upgrade the Governance Framework language from "SHOULD" to "MUST emit a CI warning." | Catches the common case. Non-blocking avoids false-positive frustration (approver may commit via the Orchestrator's machine with their own git identity). Creates a CI annotation trail visible in PR reviews. | Name comparison is heuristic. Does not catch deliberate evasion. Non-blocking means it can be ignored. | Small — ~30 lines in a new CI step or added to the existing phase gate step. | High. Simple check, low maintenance. Upgrade to blocking after organizational adoption proves the heuristic is reliable. |
| B | **Require out-of-band confirmation hash.** When an approver sends email/Slack confirmation, include a hash of the approval entry content. The CI step verifies the hash matches the committed content. | Tamper-evident. Proves the approver saw the exact content they are approving. | Requires approvers to generate or receive hashes — significant UX friction. Hash generation must be tooled. | Large — hash generation tool, CI verification, approver workflow documentation. | Medium. Correct but operationally burdensome. |

**Recommendation:** Option A. The governance model already includes quarterly audits as the definitive control. The CI warning provides continuous monitoring that supplements the periodic audit. It reduces the window of undetected fabrication from 3 months to the next PR review cycle without imposing onerous process on approvers. Upgrade the Governance Framework "SHOULD" to "MUST emit a CI warning" to close the prescriptive gap.

**Files to Modify:**
- `templates/pipelines/ci/*.yml` — add approval-authorship check step (all language templates)
- `scripts/check-approval-authorship.sh` — new script (or inline in CI YAML)
- `docs/governance-framework.md` — upgrade "SHOULD" to "MUST emit a CI warning" (line ~181)

**Acceptance Criteria:**
- When `APPROVAL_LOG.md` is modified in a PR, CI emits a warning annotation if the commit author name matches the listed approver name (for organizational deployments).
- The warning is visible in the PR review interface.
- Personal projects are exempt.
- The Governance Framework uses "MUST emit a CI warning" language for this control.

**Verification Test:**
- Commit an APPROVAL_LOG.md change listing yourself as approver, authored by your git identity. Create a PR. Expected: CI annotation warning "Approval entry author matches listed approver — verify out-of-band confirmation."
- Have a different person commit the entry. Expected: no warning.

---

## Minor Findings

### P0-006: Review Checklists Not Machine-Verifiable

**The Problem:** Steps 0.1-0.3 include markdown checkbox review checklists (e.g., `- [ ] Every Must-Have has a logic trigger`). These are instructional only — no script verifies that the checkboxes were marked complete. There is no audit trail that the review actually occurred.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Persist checklists in the intermediate output files (P0-001) and verify at gate.** When the agent saves `docs/phase-0/frd.md`, include the review checklist at the bottom. At the Phase 0-to-1 gate, check that all checkboxes are marked `[x]`. | Audit trail. Machine-verifiable. Reuses P0-001 infrastructure. | Checking `[x]` proves the box was ticked, not that the review was thorough. | Minimal (once P0-001 is implemented). | High. |
| B | **Accept as Tier 3.** Document in the User Guide that review checklists are instructional and depend on Orchestrator discipline. | No implementation cost. Honest about enforcement tier. | No improvement to auditability. | None. | N/A. |

**Recommendation:** Option A, implemented as part of the P0-001 work. The incremental cost is negligible once intermediate files exist.

**Files to Modify:** Same as P0-001, plus checklist verification in `check-phase-gate.sh`.

**Acceptance Criteria:** Intermediate output files include review checklists; unchecked items produce a gate warning (not block).

**Verification Test:** Save `frd.md` with one unchecked item. Run gate check. Expected: warning.

---

### P0-007: Track-Conditional Steps (0.5, 0.7) Not Enforced

**The Problem:** Steps 0.5 (Revenue Model) and 0.7 (Trademark/Legal) are marked "Standard+ Track" but the gate check does not read the project track. A Standard or Full track project can skip these steps entirely without detection.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Read project track from `phase-state.json`; verify track-conditional appendices in Manifesto.** For Standard and Full tracks, verify Appendix A (Revenue Model) is populated. For Standard+ (Full) track, verify Appendix C (Trademark/Legal) is populated. Reuses the placeholder-detection logic from P0-003. | Enforces track-conditional requirements mechanically. Leverages existing infrastructure. | Must read track from `phase-state.json` (field may not exist in older projects). | Small — extends the P0-003 validation function. | High. |

**Recommendation:** Option A. This is a natural extension of P0-003 and should be implemented alongside it.

**Files to Modify:** `scripts/check-phase-gate.sh` — extend `validate_manifesto_content()` to check track-conditional appendices.

**Acceptance Criteria:** Standard track project with empty Appendix A fails gate. Light track project with empty Appendix A passes.

**Verification Test:** Set track to "standard" in `phase-state.json`. Leave Appendix A as template default. Run gate. Expected: fail.

---

### P0-009: Evaluation Prompt Results Not in Canonical Location

**The Problem:** Evaluation prompt results (adversarial reviews of completed work) have no prescribed storage location. Results end up in the project root or ad hoc directories.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Prescribe `docs/eval-results/` as canonical location.** Update documentation to specify this path. Add it to `.gitignore` exceptions if needed. | Consistent across projects. | Minimal benefit — organizational, not functional. | Minimal — documentation update. | High. |

**Recommendation:** Option A. Documentation-only change.

**Files to Modify:** `docs/builders-guide.md`, `docs/user-guide.md` — add canonical path for evaluation results.

**Acceptance Criteria:** Documentation specifies `docs/eval-results/` as the storage location for evaluation prompt output.

**Verification Test:** Documentation review only.

---

### P0-011: Phase 0 Snapshot Missing Intermediate Work Products

**The Problem:** The Phase 0-to-1 gate snapshot (`check-phase-gate.sh`, lines 33-36) captures `PRODUCT_MANIFESTO.md`, `APPROVAL_LOG.md`, and `PROJECT_INTAKE.md` but not the intermediate outputs from Steps 0.1-0.3. An auditor examining the gate snapshot cannot see the FRD, User Journey, or Data Contract that informed the Manifesto.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Add `docs/phase-0/` contents to the Phase 0-to-1 snapshot.** Once P0-001/002 are implemented (intermediate files exist at `docs/phase-0/`), extend the snapshot case to copy the entire `docs/phase-0/` directory. | Complete audit trail. No extra work if P0-001/002 are done first. | Depends on P0-001/002. | Minimal — 2 lines in `check-phase-gate.sh`. | High. |

**Recommendation:** Option A. Implement after P0-001/002.

**Files to Modify:** `scripts/check-phase-gate.sh` — extend `0-1` snapshot case to include `docs/phase-0/`.

**Acceptance Criteria:** Phase 0-to-1 snapshot directory contains `docs/phase-0/*.md` files alongside existing artifacts.

**Verification Test:** Complete Phase 0 with intermediate files. Run gate check (passes). Verify snapshot contains `frd.md`, `user-journey.md`, `data-contract.md`.

---

### P0-013: Step 0.4 Prompt Does Not Reference Template

**The Problem:** The Builder's Guide Step 0.4 prompt (lines 395-428) describes the Manifesto structure in prose but does not reference `templates/generated/product-manifesto.tmpl`. The agent follows the prose description rather than the template, which could produce structural inconsistencies.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Add template reference to Step 0.4 prompt.** Add a line: "Use the template at `templates/generated/product-manifesto.tmpl` as the structural skeleton. Populate every section." | Eliminates structural drift between prose and template. | Minimal. | Minimal — one sentence added. | High. |

**Recommendation:** Option A. Documentation-only fix.

**Files to Modify:** `docs/builders-guide.md` — add template reference to Step 0.4.

**Acceptance Criteria:** Step 0.4 prompt explicitly references the template file path.

**Verification Test:** Documentation review.

---

### P0-016: Intake Wizard Does Not Validate Completeness

**The Problem:** The intake wizard (`scripts/intake-wizard.sh`) tracks which sections have been visited but does not perform a holistic completeness check at the end. A user can complete the wizard with multiple blank or placeholder fields. The wizard declares "Intake Complete!" based on section visits, not field population.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Add a completeness summary at wizard completion.** After all sections are visited, scan the `intake-progress.json` for empty or default-value answers. Display a summary: "12/14 fields complete. Missing: [field names]." Warn but do not block — the user may intend to fill remaining fields manually. | Surfaces gaps before Phase 0 starts. Non-blocking respects manual editing workflow. | Does not block incomplete intakes. | Small — ~40 lines scanning the progress JSON. | High. |
| B | **Block wizard completion on missing required fields.** Define a subset of fields as required (project name, platform, track, deployment type, at minimum). Block the "Intake Complete" message until required fields are populated. | Prevents starting Phase 0 with critical gaps. | Overly restrictive for the AI-assisted path where Claude fills in missing details during Phase 0. | Small-Medium. | Medium. May frustrate users who prefer the conversational discovery path. |

**Recommendation:** Option A. A completeness summary respects the dual workflow (wizard + manual editing) while ensuring the user is informed of gaps.

**Files to Modify:** `scripts/intake-wizard.sh` — add completeness summary function before the "Intake Complete!" banner.

**Acceptance Criteria:** Wizard completion displays a summary of populated vs. empty fields with specific field names for gaps.

**Verification Test:** Run wizard, skip 3 fields. Expected: summary shows "Missing: [field1], [field2], [field3]" before the completion banner.

---

### P0-017: No Session Loss Recovery Procedure

**The Problem:** The Builder's Guide prescribes running all Phase 0 steps in a single Claude conversation but documents no recovery procedure for session loss (timeout, crash, context window exceeded). Without recovery guidance, the Orchestrator must restart Phase 0 from scratch — potentially 2-3 hours of duplicated effort.

**Remediation Options:**

| Option | Description | Pros | Cons | Effort | Sustainability |
|--------|------------|------|------|--------|---------------|
| A (Recommended) | **Document a recovery procedure in the Builder's Guide.** Add a "Session Recovery" subsection to Phase 0 that instructs the Orchestrator to: (1) start a new conversation, (2) attach any saved intermediate files from `docs/phase-0/`, (3) state which step was completed, (4) resume from the next step. This is naturally enabled by P0-001/002 (persisted intermediates). | Eliminates duplicated work. Simple to follow. Leverages existing artifact persistence. | Documentation-only — does not prevent session loss. | Minimal — one paragraph in the Builder's Guide. | High. Directly benefits from P0-001/002. |

**Recommendation:** Option A. Session loss is an operational reality. The recovery procedure is straightforward once intermediate files are persisted (P0-001/002). This is a documentation fix.

**Files to Modify:** `docs/builders-guide.md` — add "Session Recovery" subsection after "Intake-First vs. Conversational Discovery" section.

**Acceptance Criteria:** Builder's Guide contains a session recovery procedure that references intermediate output files.

**Verification Test:** Follow the recovery procedure after a simulated session loss (close conversation after Step 0.2). Verify the new session can resume from Step 0.3 using saved files.

---

## Observations

### P0-014: Agent Persona Is Instruction-Only

**Rationale:** The "Skeptical Product Manager" persona instruction in Step 0.2 is behavioral guidance for the AI agent. It operates at Tier 3 (LLM instruction) by design. There is no mechanical way to enforce an AI's analytical mindset, nor should there be — this is the correct enforcement tier for behavioral shaping. The instruction is well-written, specific, and actionable. No remediation required.

---

## Implementation Dependencies

The findings are not independent. The following dependency graph determines implementation order:

```
P0-001 (Templates for intermediates)
  └── P0-002 (Persist intermediates) — shares implementation; do together
       ├── P0-006 (Checklists in intermediate files) — depends on files existing
       ├── P0-011 (Snapshot intermediates) — depends on files existing
       └── P0-017 (Session recovery) — depends on files existing

P0-003 (Manifesto content validation) — independent, highest priority
  └── P0-007 (Track-conditional appendices) — extends P0-003 logic
  └── P0-012 (Open Questions check) — same file, same gate, natural to co-implement

P0-004 (Approval validation) — independent
  └── P0-005 (Personal/Org distinction) — extends P0-004 with deployment-aware logic
       └── P0-018 (Commit authorship) — extends P0-005 with git author comparison

P0-008 (Competency-to-CI gating) — independent, Phase 1→2 gate
P0-010 (Pre-conditions enforcement) — independent, Phase 0 gate
P0-009 (Eval results location) — independent, documentation only
P0-013 (Template reference) — independent, documentation only
P0-015 (MVP Cutline reconciliation) — independent, Phase 2→3 gate
P0-016 (Intake wizard completeness) — independent, wizard script
```

**Recommended implementation order:**

1. **Batch 1 (Critical path):** P0-003, P0-012, P0-007 — closes the Critical finding and two related Majors. All modify the same function in the same file.
2. **Batch 2 (Intermediate persistence):** P0-001, P0-002, P0-006, P0-011, P0-017 — five findings resolved by one coherent change (templates + save instructions + snapshot extension + recovery docs).
3. **Batch 3 (Approval integrity):** P0-004, P0-005, P0-018 — three findings that build on each other in the approval validation path.
4. **Batch 4 (Independent items):** P0-008, P0-010, P0-015, P0-016 — each modifies different files with no cross-dependencies.
5. **Batch 5 (Documentation-only):** P0-009, P0-013 — trivial documentation updates, batch with any other docs PR.

---

## Estimated Total Effort

| Finding | Severity | Effort Estimate | Batch |
|---------|----------|----------------|-------|
| P0-003 | Critical | 2-3 hours | 1 |
| P0-012 | Major | 0.5-1 hour | 1 |
| P0-007 | Minor | 0.5-1 hour | 1 |
| P0-001 | Major | 2-3 hours | 2 |
| P0-002 | Major | 0.5-1 hour (included in P0-001) | 2 |
| P0-006 | Minor | 0.5 hour (incremental to P0-001) | 2 |
| P0-011 | Minor | 0.5 hour | 2 |
| P0-017 | Minor | 0.5 hour | 2 |
| P0-004 | Major | 2-3 hours | 3 |
| P0-005 | Major | 1-2 hours | 3 |
| P0-018 | Major | 1-2 hours | 3 |
| P0-008 | Major | 3-4 hours | 4 |
| P0-010 | Major | 2-3 hours | 4 |
| P0-015 | Major | 2-3 hours | 4 |
| P0-016 | Minor | 1-2 hours | 4 |
| P0-009 | Minor | 0.25 hour | 5 |
| P0-013 | Minor | 0.25 hour | 5 |
| P0-014 | Observation | 0 hours | N/A |
| **Total** | | **17-27 hours** | |

**Notes on estimates:**
- Estimates include implementation, testing, and documentation updates.
- Batch 1 and Batch 2 together resolve 8 of 15 findings (the Critical + 2 Majors + 5 connected findings) in approximately 7-10 hours.
- Batch 3 provides the governance integrity improvements most relevant to the enterprise audience in 4-7 hours.
- Batch 4 contains the most effort-intensive independent items; P0-008 (Competency Matrix gating) is the most complex single fix.
- Batch 5 is negligible effort and should be folded into whatever PR touches those files next.

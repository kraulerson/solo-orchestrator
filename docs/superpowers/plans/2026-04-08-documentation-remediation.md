# Documentation Artifact Remediation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remediate all documentation artifact gaps — add 10 templates, restructure docs/ directory, reconcile cross-references, and add phase gate enforcement.

**Architecture:** Two PRs on one branch (`fix/documentation-remediation`). PR 1: templates + structure + cross-references. PR 2: enforcement (check-phase-gate.sh, test-gate.sh, session hooks). PR 2 depends on PR 1.

**Tech Stack:** Bash (init.sh, scripts), Markdown (templates, docs), HTML/CSS/JS (UAT template)

**Spec:** `docs/superpowers/specs/2026-04-08-documentation-remediation-design.md`

---

## PR 1: Structure + Templates + Cross-References

### Task 1: Create branch and new template files (simple templates)

**Files:**
- Create: `templates/generated/adr.tmpl`
- Create: `templates/generated/features.tmpl`
- Create: `templates/generated/changelog.tmpl`
- Create: `templates/generated/bugs.tmpl`
- Create: `templates/generated/release-notes.tmpl`

These are the 5 smaller templates that can be created directly from the spec content.

- [ ] **Step 1: Create the feature branch**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
git checkout -b fix/documentation-remediation
```

- [ ] **Step 2: Create `templates/generated/adr.tmpl`**

Write the file with the standard ADR format from spec Section 2.2. Content:

```markdown
# ADR-NNNN: [Title]

**Status:** Proposed | Accepted | Superseded | Deprecated
**Date:** YYYY-MM-DD
**Supersedes:** [ADR-NNNN if applicable, otherwise remove this line]

## Context

[What is the issue that we're seeing that motivates this decision or change?]

## Decision

[What is the change that we're proposing and/or doing?]

## Consequences

[What becomes easier or more difficult to do because of this change?]
```

- [ ] **Step 3: Create `templates/generated/features.tmpl`**

Write the file with the living feature index format from spec Section 2.5. Content:

```markdown
# Feature Reference

<!--
  This document is a living index of all features built during Phase 2.
  Update at Step 2.5 of every Build Loop iteration alongside the CHANGELOG and Bible.
  Purpose: Give someone a quick orientation to what the app does without reading the Bible.
  For detailed analysis, follow the links to ADRs and interface docs.
-->

## Feature 1: [Name]

**Phase Built:** 2
**Status:** Complete | In Progress
**Summary:** [2-3 sentences — what this feature does and why it exists]
**Key Interfaces:** [Links to relevant files in docs/api and interfaces/]
**Related ADRs:** [Links to relevant files in docs/ADR documentation/, if any]
**Test Coverage:** [Unit / Integration / E2E — what test types cover this feature]
**Known Limitations:** [If any, otherwise "None"]

---

<!-- Copy the section above for each new feature. Number sequentially. -->
```

- [ ] **Step 4: Create `templates/generated/changelog.tmpl`**

Write the file with the 8-category Keep a Changelog format from spec Section 2.8. Content:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/) with extended categories
for handoff clarity. Categories are ordered by impact severity.

<!--
  Category definitions:
  - Security: Vulnerability fixes, dependency patches for CVEs, auth changes
  - Data Model: Schema migrations, data format changes, rollback notes
  - Added: New features, new endpoints, new commands
  - Changed: Modifications to existing behavior
  - Fixed: Bug fixes (reference BUGS.md entry if applicable)
  - Removed: Removed features, deprecated endpoints
  - Infrastructure: CI/CD changes, dependency updates, configuration changes, tooling
  - Documentation: Significant doc updates (new ADRs, updated threat model, revised user guide)
-->

## [Unreleased]

### Security
### Data Model
### Added
### Changed
### Fixed
### Removed
### Infrastructure
### Documentation
```

- [ ] **Step 5: Create `templates/generated/bugs.tmpl`**

Write the file with the bug tracker format from spec Section 2.9. Content:

```markdown
# Bug Tracker

<!--
  This file tracks bugs found during UAT sessions and ad hoc testing.
  Status and severity patterns are read by scripts/test-gate.sh for phase gate checks.
  Do NOT change the table format — the column order and status values are parsed by scripts.
-->

| # | Severity | Status | Feature | Description | Session | Disposition |
|---|---|---|---|---|---|---|
<!--
  Severity: SEV-1, SEV-2, SEV-3, SEV-4 (see PROJECT_BIBLE.md Bug Severity Classification)
  Status: Open, Fixed, Deferred, Won't Fix, Post-MVP, Removed
  Disposition: Fix Now, Defer, Won't Fix, Post-MVP (assigned during triage, Step 2.8)
  Session: UAT session number where the bug was found (e.g., "Session 4")
-->

## Status Guide

| Status | Meaning |
|---|---|
| **Open** | Bug confirmed, not yet fixed |
| **Fixed** | Fix implemented and verified |
| **Deferred** | Tracked with justification — must be resolved or feature removed at Phase 2→3 gate |
| **Won't Fix** | Accepted as-is with documented rationale (SEV-3/4 only) |
| **Post-MVP** | Moved to post-MVP backlog (SEV-4 enhancements only) |
| **Removed** | Feature containing the bug was removed |

## Severity Guide

| Severity | Definition | Examples | Can Defer? |
|---|---|---|---|
| **SEV-1** | Data loss, security breach, app crash on core flow | Auth bypass, database corruption, crash on login | No — must fix immediately |
| **SEV-2** | Feature broken but workaround exists, significant UX failure | Form submits wrong data, layout broken on one platform | Yes — but must resolve or remove feature at Phase 2→3 gate |
| **SEV-3** | Minor UX issue, cosmetic, non-core edge case | Alignment off, tooltip truncated, rare edge case | Yes |
| **SEV-4** | Enhancement, suggestion, polish | "Would be nice if...", performance optimization | Automatic Post-MVP |
```

- [ ] **Step 6: Create `templates/generated/release-notes.tmpl`**

Write the file with the release notes format from spec Section 2.10. Content:

```markdown
# Release Notes

## [Version] — YYYY-MM-DD

### What This Application Does

[User-facing summary — what the app does, not how it's built]

### What's New in This Release

[User-facing changes — not developer changelog. Written for the person using the app.]

### Known Limitations

[What doesn't work yet, what's incomplete, what to expect]

### Reporting Issues

[How to report bugs or request support — email, GitHub Issues, etc.]

<!--
  For subsequent releases: add a new section above this one (newest first).
  The "What This Application Does" section can be omitted in subsequent releases
  unless the product scope has changed.
-->
```

- [ ] **Step 7: Commit the 5 simple templates**

```bash
git add templates/generated/adr.tmpl templates/generated/features.tmpl templates/generated/changelog.tmpl templates/generated/bugs.tmpl templates/generated/release-notes.tmpl
git commit -m "feat: add 5 documentation artifact templates (ADR, features, changelog, bugs, release notes)"
```

---

### Task 2: Create Product Manifesto template

**Files:**
- Create: `templates/generated/product-manifesto.tmpl`

- [ ] **Step 1: Create `templates/generated/product-manifesto.tmpl`**

Write the file with all 11 sections from spec Section 2.4. Each section gets an H2 heading, a source comment, and placeholder content describing what belongs there. Include all appendix sections. Refer to the spec for the complete section list and source references. The template should be ~80 lines.

Key sections and their source comments:
1. `## 1. Product Intent` — `<!-- Source: Phase 0 Step 0.4. One paragraph: what and why. -->`
2. `## 2. Functional Requirements` — `<!-- Source: Phase 0 Step 0.1. Must-Have with if/then triggers + failure states. Should-Have for v1.1. -->`
3. `## 3. User Journeys` — `<!-- Source: Phase 0 Step 0.2. Primary persona, success path, failure recovery, exit points. -->`
4. `## 4. Data Contracts` — `<!-- Source: Phase 0 Step 0.3. Inputs, transformations, outputs, third-party data, state. -->`
5. `## 5. MVP Cutline` — `<!-- Hard line. Features above ship first. Everything else: Post-MVP Backlog. -->`
6. `## 6. Post-MVP Backlog` — `<!-- Prioritized by user feedback after launch, not this document. -->`
7. `## 7. Will-Not-Have List` — `<!-- Explicit scope boundaries. At least 3 items. -->`
8. `## 8. Open Questions` — `<!-- Anything from Steps 0.1-0.3 requiring Orchestrator decision before Phase 1. -->`
9. `## Appendix A: Revenue Model & Unit Economics` — `<!-- Standard+ Track only. Skip for internal tools. Source: Step 0.5. -->`
10. `## Appendix B: Orchestrator Competency Matrix` — `<!-- Source: Step 0.6. Self-assessment per domain. -->`
11. `## Appendix C: Trademark & Legal Pre-Check` — `<!-- Standard+ Track only. Source: Step 0.7. -->`

- [ ] **Step 2: Commit**

```bash
git add templates/generated/product-manifesto.tmpl
git commit -m "feat: add Product Manifesto template with 11 structured sections"
```

---

### Task 3: Create Project Bible template

**Files:**
- Create: `templates/generated/project-bible.tmpl`

This is the largest and most important template (~200 lines). It must include all 16 sections with `<!-- Last Updated: YYYY-MM-DD -->` markers, pre-formatted tables for Bug Severity Classification and Competency Matrix, and content description comments per section.

- [ ] **Step 1: Create `templates/generated/project-bible.tmpl`**

Write the file with all 16 sections from spec Section 2.1. Each section gets:
- An H2 heading
- `<!-- Last Updated: YYYY-MM-DD -->`
- A comment block describing what belongs there, expected depth, and source material

Sections (in order):
1. `## 1. Product Manifesto` — Full text from Phase 0 PRODUCT_MANIFESTO.md
2. `## 2. Revenue Model & Cost Constraints` — From Manifesto Appendix A (if applicable)
3. `## 3. Architecture Decision Record` — Selected stack, rejected alternatives, rationale. Reference: `docs/ADR documentation/0001-architecture-selection.md`
4. `## 4. Threat Model & Risk/Mitigation Matrix` — STRIDE analysis from Step 1.3. Pre-formatted table: `| Threat | Category | Attack Path | Mitigation | Status |`
5. `## 5. Data Model` — Full specification from Step 1.4
6. `## 6. Data Migration Plan` — From Step 1.4.5 (if applicable, otherwise note "No legacy data")
7. `## 7. Auth & Identity Strategy` — From Step 1.4 (if applicable)
8. `## 8. Observability & Logging Strategy` — Structured logging, correlation IDs, error tracking
9. `## 9. UI Component Specifications` — Component inventory, interaction patterns
10. `## 10. Coding Standards` — Linting, formatting, naming conventions, "never do this" rules
11. `## 11. Build & Distribution Strategy` — Platform-specific build pipeline, packaging, distribution
12. `## 12. Test Strategy` — Pre-formatted table: `| Type | Tool | Pass Criteria | Phase |`
13. `## 13. Orchestrator Profile Summary` — Pre-formatted Competency Matrix table (9 domains)
14. `## 14. Accessibility Requirements` — From Intake Section 9
15. `## 15. Platform-Specific Requirements` — From Platform Module
16. `## 16. Context Management Plan` — Small/medium/large project tiers

Also include:
- **Bug Severity Classification** table (SEV-1 through SEV-4) after Section 12
- **UAT Plan** fields (testing interval, tester count, bug tracker, severity SLAs) after Bug Severity

- [ ] **Step 2: Commit**

```bash
git add templates/generated/project-bible.tmpl
git commit -m "feat: add Project Bible template with 16 sections and freshness markers"
```

---

### Task 4: Create Handoff and Incident Response templates

**Files:**
- Create: `templates/generated/handoff.tmpl`
- Create: `templates/generated/incident-response.tmpl`

- [ ] **Step 1: Create `templates/generated/handoff.tmpl`**

Write the file with all 9 sections from spec Section 2.6. Each section gets an H2 heading with a content description comment. Section 9 (AI Quick Start Prompt) includes the example from the spec.

Sections:
1. Product Intent & Architecture Overview
2. Development Setup
3. Build & Release Process
4. Technical Debt Map
5. Maintenance Schedule
6. Incident History
7. Bug Reporting & Triage
8. Key Contacts & Third-Party Services
9. AI Quick Start Prompt (with example prompt)

- [ ] **Step 2: Create `templates/generated/incident-response.tmpl`**

Write the file with all 7 sections from spec Section 2.7. Include pre-formatted tables for severity classification and notification chains with placeholder rows for project-specific contacts.

Sections:
1. Severity Classification (pre-formatted table: SEV-1 through SEV-4 with response times and notification)
2. Containment Procedures
3. Rollback Procedure
4. Secrets Rotation
5. Notification Chains (table with placeholder rows)
6. Enterprise IR Integration (organizational deployments — from Governance Framework Section VII)
7. Post-Incident Review (template with fields: timeline, root cause, impact, resolution, preventive measures)

- [ ] **Step 3: Commit**

```bash
git add templates/generated/handoff.tmpl templates/generated/incident-response.tmpl
git commit -m "feat: add Handoff and Incident Response templates"
```

---

### Task 5: Create UAT HTML template

**Files:**
- Create: `templates/uat-test-session.html`

This is the interactive HTML template based on the meshscope `test-session-4.html`. Reference file: `/Users/karl/Documents/Claude Projects/meshscope/tests/uat/sessions/session-4-f7-f8/test-session-4.html`

- [ ] **Step 1: Create `templates/uat-test-session.html`**

Build a self-contained HTML file (~350 lines) using the meshscope HTML as the structural reference. The template must include:

**Fixed elements (copy from meshscope structure, generalize):**
- CSS: Dark theme (same color scheme as meshscope), responsive layout, scenario cards with colored left borders (pass=green, fail=red, skip=yellow)
- Progress bar and completion counter
- Pass/Fail/Skip button group per scenario
- Expandable details panel per scenario (steps + expected result)
- Per-scenario notes textarea
- Bug entry form with severity dropdown (SEV-1 through SEV-4), feature dropdown, description, steps to reproduce, expected vs actual
- Add/remove bug functionality
- Overall notes textarea
- "Copy Results to Clipboard" export button
- Tester name input field

**Replace meshscope-specific content with placeholder tokens:**
- Replace `<h1>UAT Session 4</h1>` with `<h1>__SESSION_TITLE__</h1>`
- Replace `Date: 2026-04-08` with `Date: __SESSION_DATE__`
- Replace `Features: Basic Mesh Repair + Scale/Rotate/Mirror` with `Features: __SESSION_FEATURES__`
- Replace the two `<h2>Feature 7:...` and `<h2>Feature 8:...` blocks (including fixture-ref divs and container divs) with `__FEATURE_SECTIONS__`
- Replace the `<option>7 - Mesh Repair</option><option>8 - Scale/Rotate/Mirror</option>` in the bug form with `__FEATURE_OPTIONS__`
- Replace the entire `const scenarios = [...]` array with `const scenarios = __SCENARIOS_JSON__;`

**Add agent instruction comments immediately before each placeholder:**

Before `__SESSION_TITLE__`:
```html
<!-- AGENT: Replace __SESSION_TITLE__ with the session title, e.g., "UAT Session 4" -->
```

Before `__SESSION_DATE__`:
```html
<!-- AGENT: Replace __SESSION_DATE__ with YYYY-MM-DD -->
```

Before `__SESSION_FEATURES__`:
```html
<!-- AGENT: Replace __SESSION_FEATURES__ with comma-separated feature names -->
```

Before `__FEATURE_SECTIONS__`:
```html
<!--
  AGENT: Replace __FEATURE_SECTIONS__ with one block per feature:
  <h2>Feature N: [Name]</h2>
  <div class="fixture-ref">
    <strong>Test files</strong> (if applicable):<br>
    <code>filename</code> — description<br>
  </div>
  <div id="featureN"></div>

  The fixture-ref div is optional. The featureN div ID must match scenario.feature values.
  The renderScenarios() function uses the "feature" field to route scenarios to their container.
-->
```

Before `__FEATURE_OPTIONS__`:
```html
<!-- AGENT: Replace __FEATURE_OPTIONS__ with one <option> per feature, e.g.:
  <option>7 - Mesh Repair</option>
  <option>8 - Scale/Rotate/Mirror</option>
-->
```

Before `__SCENARIOS_JSON__`:
```javascript
// AGENT INSTRUCTIONS: Replace __SCENARIOS_JSON__ with a JavaScript array.
// Each element MUST be an object with ALL of the following fields.
// Do not omit any field. Do not add fields not listed here.
// Do not modify any code outside the __PLACEHOLDER__ tokens.
//
// SCHEMA:
// [
//   {
//     "id": number,        // Sequential integer starting at 1, unique across all features
//     "feature": number,   // Feature number this scenario tests (must match a __FEATURE_SECTIONS__ div id)
//     "title": string,     // Short imperative description, e.g., "Repair fills holes on open mesh"
//     "steps": string,     // Numbered steps separated by \\n, e.g., "1. Open file\\n2. Click Analyze"
//     "expected": string   // What should happen if the feature works correctly
//   }
// ]
//
// EXAMPLE (do not copy verbatim — write scenarios specific to the features under test):
// [
//   {
//     "id": 1,
//     "feature": 7,
//     "title": "Repair disabled after clean analysis",
//     "steps": "1. Open cube.stl\\n2. Click Analyze (A)\\n3. Check Repair button",
//     "expected": "Repair button stays disabled. Analysis shows 0 holes, 0 degenerate faces."
//   }
// ]
```

**Update the renderScenarios() function** to dynamically route scenarios to feature containers by looking for `document.getElementById('feature' + s.feature)` instead of hardcoded `feature7`/`feature8`.

**Update the exportResults() function** to use `__SESSION_TITLE__` and `__SESSION_DATE__` in the Markdown header instead of hardcoded values.

- [ ] **Step 2: Verify the template renders in a browser**

Open the file in a browser. It should render the UI structure with placeholder text visible. The JavaScript should not throw errors (the `__SCENARIOS_JSON__` will need to be temporarily set to `[]` for testing — revert after).

- [ ] **Step 3: Commit**

```bash
git add templates/uat-test-session.html
git commit -m "feat: add interactive HTML UAT test session template"
```

---

### Task 6: Update init.sh — directory structure and template copying

**Files:**
- Modify: `init.sh:1023` (directory creation)
- Modify: `init.sh:1025-1030` (framework doc copying — rename target dir)
- Modify: `init.sh:1067-1069` (UAT template copying)
- Modify: `init.sh` (add new template copies after existing template copies)

- [ ] **Step 1: Rename `docs/framework` to `docs/reference` in directory creation**

In `init.sh`, find line 1023:
```bash
mkdir -p docs/framework docs/platform-modules docs/test-results
```
Replace with:
```bash
mkdir -p docs/reference docs/platform-modules docs/test-results "docs/ADR documentation" "docs/api and interfaces" docs/snapshots
```

- [ ] **Step 2: Update framework doc copy targets**

In `init.sh`, find lines 1025-1030:
```bash
cp "$SCRIPT_DIR/docs/builders-guide.md" docs/framework/
cp "$SCRIPT_DIR/docs/governance-framework.md" docs/framework/
cp "$SCRIPT_DIR/docs/executive-review.md" docs/framework/
cp "$SCRIPT_DIR/docs/cli-setup-addendum.md" docs/framework/
cp "$SCRIPT_DIR/docs/user-guide.md" docs/framework/
cp "$SCRIPT_DIR/docs/security-scan-guide.md" docs/framework/
```
Replace `docs/framework/` with `docs/reference/` in all 6 lines.

- [ ] **Step 3: Update UAT template copying and add new template copies**

Find lines 1067-1069:
```bash
mkdir -p tests/uat/templates tests/uat/sessions
cp "$SCRIPT_DIR/templates/uat-test-template.md" tests/uat/templates/test-session-template.md
```
Replace with:
```bash
mkdir -p tests/uat/templates tests/uat/sessions
cp "$SCRIPT_DIR/templates/uat-test-template.md" tests/uat/templates/test-session-template.md
cp "$SCRIPT_DIR/templates/uat-test-session.html" tests/uat/templates/test-session-template.html
```

- [ ] **Step 4: Add new template copies after the UAT section**

After the UAT template copying block (after the line that copies the platform module), add:

```bash
# Copy documentation artifact templates
print_info "Copying documentation templates..."
mkdir -p templates/generated
cp "$SCRIPT_DIR/templates/generated/project-bible.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/product-manifesto.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/adr.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/features.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/handoff.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/incident-response.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/changelog.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/bugs.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/release-notes.tmpl" templates/generated/

# Copy starter files from templates (empty until agent populates)
cp "$SCRIPT_DIR/templates/generated/features.tmpl" FEATURES.md
cp "$SCRIPT_DIR/templates/generated/changelog.tmpl" CHANGELOG.md
cp "$SCRIPT_DIR/templates/generated/bugs.tmpl" BUGS.md
cp "$SCRIPT_DIR/templates/generated/release-notes.tmpl" RELEASE_NOTES.md
```

- [ ] **Step 5: Update all remaining `docs/framework/` references in init.sh**

Search init.sh for every remaining occurrence of `docs/framework/` and replace with `docs/reference/`. This includes the dry-run output section, the health check section, and the "next steps" output section. Use `grep -n "docs/framework" init.sh` to find all occurrences.

- [ ] **Step 6: Commit**

```bash
git add init.sh
git commit -m "feat: update init.sh for new directory structure and template copying"
```

---

### Task 7: Update CLAUDE.md template

**Files:**
- Modify: `templates/generated/claude-md.tmpl`

Add the 13 missing artifact references identified in the audit.

- [ ] **Step 1: Update Framework Reference section (line 12)**

Find:
```
- Builder's Guide: `docs/framework/builders-guide.md`
```
Replace with:
```
- Builder's Guide: `docs/reference/builders-guide.md`
```

Also update line 16 if it references `docs/framework/`:
```
- Development Guardrails for Claude Code: `.claude/framework/`
```
(This stays as-is — `.claude/framework/` is the Development Guardrails directory, not the docs reference directory.)

- [ ] **Step 2: Update Construction Rules section (around line 74)**

Find:
```
- **Document as you go:** Update CHANGELOG.md, API docs, and the Project Bible after every feature.
```
Replace with:
```
- **Document as you go:** Update CHANGELOG.md (8 categories: Security, Data Model, Added, Changed, Fixed, Removed, Infrastructure, Documentation), FEATURES.md, API docs (in `docs/api and interfaces/`), and the Project Bible after every feature. For non-trivial decisions, create an ADR in `docs/ADR documentation/` using the template.
```

- [ ] **Step 3: Add Context Health Check instruction after Construction Rules**

After the Construction Rules section (after line 74), add:

```
- **Context Health Check:** Every 3-4 features, summarize features built, features remaining, current data model, and known issues. Verify the summary matches PROJECT_BIBLE.md. If it contradicts the Bible, start a fresh session.
```

- [ ] **Step 4: Add Phase 2 Completion Checkpoint after Testing & Bug Workflow**

After the Testing & Bug Workflow section (after line 155), add:

```
### Phase 2 Completion Checkpoint
Before moving to Phase 3, verify:
- All MVP Cutline features built and passing tests
- Full test suite passes, CI pipeline green
- PROJECT_BIBLE.md accurately reflects current codebase (check `<!-- Last Updated -->` markers)
- CHANGELOG.md and FEATURES.md current
- No unresolved security findings
- All UAT sessions completed, no open SEV-1/2 bugs
- Application builds on all target platforms

### Phase 3-4 Documentation
- **Phase 3:** Generate USER_GUIDE.md, run all security scans, archive results in `docs/test-results/` (naming: `[date]_[scan-type]_[pass|fail].[ext]`), generate sbom.json. For web/desktop projects, create SECURITY.md.
- **Phase 4:** Generate docs/INCIDENT_RESPONSE.md (use template: `templates/generated/incident-response.tmpl`), RELEASE_NOTES.md (use template), HANDOFF.md (use template). Test the rollback procedure before production launch. Complete go-live verification checklist.

### UAT Test Sessions
- Generate UAT test sessions as interactive HTML files using the template at `tests/uat/templates/test-session-template.html`.
- Naming: `test-session-N-v1.html`. Increment version on re-test (v2, v3). Never overwrite previous versions.
- After completion and review, archive to `docs/test-results/[date]_uat-session-N-vX.html`.
```

- [ ] **Step 5: Commit**

```bash
git add templates/generated/claude-md.tmpl
git commit -m "feat: add 13 missing artifact references to CLAUDE.md template"
```

---

### Task 8: Update Builder's Guide — Appendix A and Step 2.5

**Files:**
- Modify: `docs/builders-guide.md:881-891` (Step 2.5)
- Modify: `docs/builders-guide.md:1426-1446` (Appendix A)

- [ ] **Step 1: Update Step 2.5 documentation outputs**

Find Step 2.5 (around line 881-891). The current text lists 4 documentation outputs. Replace the list of outputs with:

```markdown
- **CHANGELOG.md:** Use [Keep a Changelog](https://keepachangelog.com/) format with 8 categories ordered by impact: Security, Data Model, Added, Changed, Fixed, Removed, Infrastructure, Documentation.
- **FEATURES.md:** Add a new section for each completed feature using the template structure (summary, key interfaces, related ADRs, test coverage, known limitations).
- **Interface Documentation:** API endpoints, commands, or user-facing interfaces with contracts and error codes. Store in `docs/api and interfaces/`.
- **Architecture/UX Decision Record:** For non-trivial decisions, create a numbered ADR in `docs/ADR documentation/` using the standard template (Status, Context, Decision, Consequences).
- **Project Bible Update:** New interfaces, data model changes, new configuration, new dependencies. Update the `<!-- Last Updated: YYYY-MM-DD -->` marker on every modified section.
```

- [ ] **Step 2: Replace Appendix A table**

Find Appendix A (around line 1426-1446). Replace the existing table with:

```markdown
## Appendix A: Document Artifacts Produced Per Project

| Artifact | Phase | Purpose | Location | Template |
|---|---|---|---|---|
| `CLAUDE.md` | 0 (init) | Agent instructions, project state, tool configuration | Root | `claude-md.tmpl` |
| `PROJECT_INTAKE.md` | 0 (init) | Structured requirements collection | Root | `project-intake.md` |
| `APPROVAL_LOG.md` | 0 (init) | Phase gate approval audit trail (append-only) | Root | `approval-log-*.tmpl` |
| `PRODUCT_MANIFESTO.md` | 0 | Requirements, MVP Cutline, Revenue Model, Competency Matrix | Root | `product-manifesto.tmpl` |
| `PROJECT_BIBLE.md` | 1 | Architecture, data model, threat model, test strategy, coding standards | Root | `project-bible.tmpl` |
| Architecture Decision Records | 1-2 | Every major choice with alternatives and rationale | `docs/ADR documentation/NNNN-title.md` | `adr.tmpl` |
| `CONTRIBUTING.md` | 2 | Coding standards for AI reference | Root | — |
| `FEATURES.md` | 2+ | Living feature index — what each feature does, interfaces, ADRs, test coverage | Root | `features.tmpl` |
| `CHANGELOG.md` | 2+ | Change log (8 categories, append-only) | Root | `changelog.tmpl` |
| `BUGS.md` | 2+ | Bug tracking with severity, status, disposition | Root | `bugs.tmpl` |
| Interface Documentation | 2+ | Per-endpoint/command/UI contracts, error codes | `docs/api and interfaces/` | — |
| CI/CD Configuration | 2 | Automated testing, scanning, building, packaging | `.github/workflows/` | `pipelines/ci/*.yml`, `pipelines/release/*.yml` |
| `docs/test-results/` | 3 | Archived scan reports, E2E results, UAT sessions, threat model validation | `docs/test-results/[date]_[type]_[pass|fail].[ext]` | — |
| `sbom.json` | 3 | Software Bill of Materials | Root (also archived in `docs/test-results/`) | — (tool-generated) |
| Performance Baselines | 3 | Metrics for future comparison | `docs/test-results/[date]_performance-baseline.[ext]` | — |
| `USER_GUIDE.md` | 3 | End-user documentation: how to use the application, FAQ, support contact | Root | — |
| `SECURITY.md` | 4 | Vulnerability reporting — supported versions, reporting mechanism, response time, safe harbor (web/desktop projects) | Root | — |
| `docs/INCIDENT_RESPONSE.md` | 4 | Severity classification, notification chains, rollback, containment | `docs/INCIDENT_RESPONSE.md` | `incident-response.tmpl` |
| `RELEASE_NOTES.md` | 4 | User-facing: what the app does, known limitations, change history (append-only) | Root | `release-notes.tmpl` |
| `HANDOFF.md` | 4 | Complete transfer document — dev setup, build process, tech debt, AI quick start | Root | `handoff.tmpl` |
| Phase Gate Snapshots | 0-4 | Point-in-time document snapshots at each phase transition | `docs/snapshots/phase-N-to-M_YYYY-MM-DD/` | — (auto-created) |
| Compliance Screening Matrix | 0 (org) | Regulatory applicability assessment | Embedded in Intake Section 8.4 | Part of `project-intake.md` |
| Penetration Test Report | 3 (Standard+) | External security assessment | `docs/test-results/` | — (external) |
| Handoff Test Results | 4 (org) | Backup maintainer validation results | `docs/test-results/` | — |
```

- [ ] **Step 3: Commit**

```bash
git add docs/builders-guide.md
git commit -m "feat: reconcile Appendix A and update Step 2.5 with artifact locations and formats"
```

---

### Task 9: Update remaining framework documents

**Files:**
- Modify: `docs/user-guide.md` — update `docs/framework/` references to `docs/reference/`
- Modify: `docs/governance-framework.md` — align Section XV artifact list with updated Appendix A
- Modify: `docs/executive-review.md` — remove "Launch Plan" phantom reference
- Modify: `README.md` — update "What Gets Created" directory structure and path references

- [ ] **Step 1: Update User Guide path references**

Search `docs/user-guide.md` for all occurrences of `docs/framework/` and replace with `docs/reference/`. Use `grep -n "docs/framework" docs/user-guide.md` to find all occurrences.

- [ ] **Step 2: Update Governance Framework Section XV**

Find the artifact list in `docs/governance-framework.md` (around line 913-934). Ensure it matches the updated Appendix A. Add any artifacts present in Appendix A but missing here. Remove any that are no longer in Appendix A.

- [ ] **Step 3: Remove "Launch Plan" from Executive Review**

Search `docs/executive-review.md` for "Launch Plan" (around line 194). Either remove the reference or replace it with "Phase 3.6 Pre-Launch Preparation (see Builder's Guide Step 3.6)" to point to the actual process.

- [ ] **Step 4: Update README.md directory structure**

Find the "What Gets Created" section in `README.md`. Update the directory tree to reflect:
- `docs/framework/` → `docs/reference/`
- Add `docs/ADR documentation/`
- Add `docs/api and interfaces/`
- Add `docs/snapshots/`
- Add `FEATURES.md`, `BUGS.md`, `CHANGELOG.md`, `RELEASE_NOTES.md` to the tree
- Add template references

Also search for any other `docs/framework/` references in README.md and update to `docs/reference/`.

- [ ] **Step 5: Commit**

```bash
git add docs/user-guide.md docs/governance-framework.md docs/executive-review.md README.md
git commit -m "feat: update framework docs for new directory structure and artifact list"
```

---

### Task 10: Update scripts with path references

**Files:**
- Modify: `scripts/upgrade-project.sh` — update `docs/framework/` to `docs/reference/`
- Modify: `scripts/resume.sh` — update `docs/framework/` to `docs/reference/`
- Modify: `scripts/validate.sh` — update `docs/framework/` to `docs/reference/`
- Modify: `scripts/check-updates.sh` — update `docs/framework/` to `docs/reference/`
- Modify: `scripts/intake-wizard.sh` — update `docs/framework/` to `docs/reference/`
- Modify: `evaluation-prompts/Projects/run-reviews.sh` — update if references `docs/framework/`

- [ ] **Step 1: Find all scripts with `docs/framework/` references**

```bash
grep -rn "docs/framework" scripts/ evaluation-prompts/
```

- [ ] **Step 2: Replace all `docs/framework/` with `docs/reference/` in each file found**

For each file returned by the grep, replace all occurrences. Do not change `.claude/framework/` references (that's the Development Guardrails directory, which is staying as-is).

- [ ] **Step 3: Also check test files for path references**

```bash
grep -rn "docs/framework" tests/
```

Update any test files that reference `docs/framework/` to use `docs/reference/`.

- [ ] **Step 4: Commit**

```bash
git add scripts/ evaluation-prompts/ tests/
git commit -m "fix: update docs/framework/ path references to docs/reference/ in all scripts"
```

---

### Task 11: PR 1 verification

- [ ] **Step 1: Verify all new template files exist**

```bash
ls -la templates/generated/*.tmpl templates/uat-test-session.html
```

Expected: 9 .tmpl files + 1 .html file.

- [ ] **Step 2: Verify no remaining `docs/framework/` references (except `.claude/framework/`)**

```bash
grep -rn "docs/framework" --include="*.sh" --include="*.md" --include="*.tmpl" --include="*.yml" . | grep -v ".claude/framework" | grep -v ".git/" | grep -v "Reports/" | grep -v "docs/superpowers/"
```

Expected: No output (zero matches). If matches are found, fix them.

- [ ] **Step 3: Verify init.sh creates the correct directory structure**

```bash
grep -A 1 "mkdir -p docs/" init.sh
```

Expected: Shows `docs/reference docs/platform-modules docs/test-results "docs/ADR documentation" "docs/api and interfaces" docs/snapshots`

- [ ] **Step 4: Verify Appendix A has the complete artifact list**

```bash
grep -c "^|" docs/builders-guide.md | tail -1
```

Open `docs/builders-guide.md` and manually verify Appendix A contains all 24 artifacts from the spec.

- [ ] **Step 5: Commit any final fixes and tag PR 1 as ready**

```bash
git log --oneline fix/documentation-remediation
```

---

## PR 2: Enforcement

### Task 12: Add artifact existence checks to check-phase-gate.sh

**Files:**
- Modify: `scripts/check-phase-gate.sh`

- [ ] **Step 1: Add Phase 0→1 artifact check**

After the existing Phase 0→1 gate consistency check (around line 69), add:

```bash
# Artifact existence check: Phase 0→1
if [ "$current_phase" -ge 1 ]; then
  if [ ! -f "PRODUCT_MANIFESTO.md" ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: PRODUCT_MANIFESTO.md not found"
    issues=$((issues + 1))
  fi
fi
```

- [ ] **Step 2: Add Phase 1→2 artifact check**

After the existing Phase 1→2 gate consistency check (around line 84), add:

```bash
# Artifact existence check: Phase 1→2
if [ "$current_phase" -ge 2 ]; then
  if [ ! -f "PROJECT_BIBLE.md" ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2: PROJECT_BIBLE.md not found"
    issues=$((issues + 1))
  fi
fi
```

- [ ] **Step 3: Add Phase 3→4 artifact checks**

After the existing Phase 3→4 gate consistency check (around line 99), add:

```bash
# Artifact existence checks: Phase 3→4
if [ "$current_phase" -ge 3 ]; then
  local phase4_artifacts=("HANDOFF.md" "docs/INCIDENT_RESPONSE.md" "sbom.json")
  for artifact in "${phase4_artifacts[@]}"; do
    if [ ! -f "$artifact" ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: $artifact not found"
      issues=$((issues + 1))
    fi
  done

  # Check docs/test-results/ is non-empty
  if [ -d "docs/test-results" ]; then
    local result_count
    result_count=$(find docs/test-results -maxdepth 1 -type f | wc -l | tr -d ' ')
    if [ "$result_count" -eq 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: docs/test-results/ is empty — archive Phase 3 scan results before proceeding"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: docs/test-results/ directory not found"
    issues=$((issues + 1))
  fi
fi
```

- [ ] **Step 4: Commit**

```bash
git add scripts/check-phase-gate.sh
git commit -m "feat: add artifact existence checks to phase gate script"
```

---

### Task 13: Add phase gate snapshot creation to check-phase-gate.sh

**Files:**
- Modify: `scripts/check-phase-gate.sh`

- [ ] **Step 1: Add snapshot creation function**

At the top of the script (after the `source` line and before the phase state reading), add:

```bash
# Create a point-in-time snapshot of artifacts at phase gate transitions
create_gate_snapshot() {
  local from_phase="$1"
  local to_phase="$2"
  local snapshot_dir="docs/snapshots/phase-${from_phase}-to-${to_phase}_$(date +%Y-%m-%d)"

  if [ -d "$snapshot_dir" ]; then
    echo -e "${YELLOW}[WARN]${NC} Snapshot already exists: $snapshot_dir"
    return 0
  fi

  mkdir -p "$snapshot_dir"

  case "${from_phase}-${to_phase}" in
    0-1)
      for f in PRODUCT_MANIFESTO.md APPROVAL_LOG.md PROJECT_INTAKE.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      ;;
    1-2)
      for f in PROJECT_BIBLE.md PRODUCT_MANIFESTO.md APPROVAL_LOG.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      ;;
    2-3)
      for f in PROJECT_BIBLE.md FEATURES.md CHANGELOG.md BUGS.md APPROVAL_LOG.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      ;;
    3-4)
      for f in PRODUCT_MANIFESTO.md PROJECT_BIBLE.md FEATURES.md CHANGELOG.md BUGS.md \
               USER_GUIDE.md HANDOFF.md RELEASE_NOTES.md APPROVAL_LOG.md sbom.json; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      [ -f "docs/INCIDENT_RESPONSE.md" ] && cp "docs/INCIDENT_RESPONSE.md" "$snapshot_dir/"
      if [ -d "docs/test-results" ]; then
        ls docs/test-results/ > "$snapshot_dir/test-results-listing.txt" 2>/dev/null || true
      fi
      ;;
  esac

  echo -e "${GREEN}  [OK]${NC} Phase gate snapshot created: $snapshot_dir"
}
```

- [ ] **Step 2: Call snapshot creation on successful gate passage**

At the bottom of the script, before the final exit, modify the success path. Find (around line 251):

```bash
if [ $issues -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Phase gates consistent.${NC}"
  exit 0
```

Replace with:

```bash
if [ $issues -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Phase gates consistent.${NC}"

  # Create snapshot if a gate was just passed
  if [ "$current_phase" -ge 1 ] && [ ! -d "docs/snapshots/phase-0-to-1_"* ] 2>/dev/null; then
    create_gate_snapshot 0 1
  fi
  if [ "$current_phase" -ge 2 ] && [ ! -d "docs/snapshots/phase-1-to-2_"* ] 2>/dev/null; then
    create_gate_snapshot 1 2
  fi
  if [ "$current_phase" -ge 3 ] && [ ! -d "docs/snapshots/phase-2-to-3_"* ] 2>/dev/null; then
    create_gate_snapshot 2 3
  fi
  if [ "$current_phase" -ge 4 ] && [ ! -d "docs/snapshots/phase-3-to-4_"* ] 2>/dev/null; then
    create_gate_snapshot 3 4
  fi

  exit 0
```

- [ ] **Step 3: Commit**

```bash
git add scripts/check-phase-gate.sh
git commit -m "feat: add phase gate snapshot creation to check-phase-gate.sh"
```

---

### Task 14: Add Context Health Check counter

**Files:**
- Modify: `init.sh` (build-progress.json generation)
- Modify: `scripts/test-gate.sh` (add health check counter commands)

- [ ] **Step 1: Add health check field to build-progress.json in init.sh**

Find the `build-progress.json` generation in init.sh (around line 1439). Add `"features_since_last_health_check": 0` to the JSON object, after the existing `features_since_last_test` field.

- [ ] **Step 2: Add health check counter increment to test-gate.sh**

In `scripts/test-gate.sh`, find the `--record-feature` command handler. After it increments `features_since_last_test`, add a line to also increment `features_since_last_health_check`:

```bash
# Also increment health check counter
local health_count
health_count=$(jq '.features_since_last_health_check // 0' "$PROGRESS_FILE")
jq ".features_since_last_health_check = $((health_count + 1))" "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
```

- [ ] **Step 3: Add `--reset-health-check` command to test-gate.sh**

Add a new command handler for `--reset-health-check` alongside the existing `--reset-counter`:

```bash
--reset-health-check)
  jq '.features_since_last_health_check = 0' "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
  echo "Context health check counter reset."
  exit 0
  ;;
```

- [ ] **Step 4: Add health check reminder to session hook**

In `scripts/session-test-gate-check.sh`, after the existing test gate check, add:

```bash
# Context Health Check reminder
if [ -f "$PROGRESS_FILE" ]; then
  health_count=$(jq '.features_since_last_health_check // 0' "$PROGRESS_FILE" 2>/dev/null)
  if [ "$health_count" -ge 3 ]; then
    echo ""
    echo -e "${YELLOW}[REMINDER]${NC} Context Health Check recommended — $health_count features since last check."
    echo "  Verify PROJECT_BIBLE.md still accurately reflects the codebase."
    echo "  After checking: scripts/test-gate.sh --reset-health-check"
  fi
fi
```

- [ ] **Step 5: Commit**

```bash
git add init.sh scripts/test-gate.sh scripts/session-test-gate-check.sh
git commit -m "feat: add Context Health Check counter with session reminder"
```

---

### Task 15: PR 2 verification and final checks

- [ ] **Step 1: Verify check-phase-gate.sh has all artifact checks**

```bash
grep -c "not found" scripts/check-phase-gate.sh
```

Expected: At least 6 artifact existence checks (PRODUCT_MANIFESTO, PROJECT_BIBLE, HANDOFF, INCIDENT_RESPONSE, sbom.json, test-results non-empty).

- [ ] **Step 2: Verify snapshot function exists**

```bash
grep "create_gate_snapshot" scripts/check-phase-gate.sh
```

Expected: Function definition + 4 calls (one per gate).

- [ ] **Step 3: Verify health check counter in test-gate.sh**

```bash
grep "health_check" scripts/test-gate.sh
```

Expected: references to `features_since_last_health_check`, `--reset-health-check`.

- [ ] **Step 4: Run a dry syntax check on modified scripts**

```bash
bash -n scripts/check-phase-gate.sh && echo "check-phase-gate.sh: syntax OK"
bash -n scripts/test-gate.sh && echo "test-gate.sh: syntax OK"
bash -n scripts/session-test-gate-check.sh && echo "session-test-gate-check.sh: syntax OK"
bash -n init.sh && echo "init.sh: syntax OK"
```

Expected: All 4 report "syntax OK".

- [ ] **Step 5: Final commit log review**

```bash
git log --oneline fix/documentation-remediation
```

Verify all commits are present and messages are clear.

---

## Summary

| PR | Tasks | Commits | What Changes |
|---|---|---|---|
| **PR 1** | Tasks 1-11 | ~8 commits | 10 new templates, directory restructure, Appendix A reconciliation, CLAUDE.md template alignment, all doc/script path updates |
| **PR 2** | Tasks 12-15 | ~4 commits | Phase gate artifact checks, snapshot creation, Context Health Check counter, session hook reminder |

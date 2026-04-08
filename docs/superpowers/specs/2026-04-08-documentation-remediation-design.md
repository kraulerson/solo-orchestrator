# Documentation Artifact Remediation — Design Spec

## Version 1.0

**Date:** 2026-04-08
**Status:** Draft
**Scope:** Complete remediation of documentation artifact gaps identified in the Documentation Gap Analysis and Documentation Artifact Audit (both 2026-04-08).
**Delivery:** Two PRs on one branch. PR 1: Structure + Templates + Cross-References. PR 2: Enforcement.

---

## Problem Statement

The Solo Orchestrator Framework v1.0 identifies 59 documentation artifacts (40 named + 19 implicit) that projects produce during the five-phase methodology. Of these, only 3 have both a template and mechanical enforcement. 28+ have neither. The framework guarantees documentation *existence* through process mandates but does not guarantee documentation *consistency* because it lacks templates, canonical locations, format specifications, and enforcement for the majority of its artifacts.

Additionally, the framework's own documentation is internally inconsistent: Builder's Guide Appendix A, the Governance Framework, the Executive Review, the CLAUDE.md template, and the User Guide disagree on what artifacts exist, when they're created, and where they live. The CLAUDE.md template — the agent's primary instruction set — is missing references to 13 artifacts the Builder's Guide requires.

Real-world usage on the meshscope project exposed a critical UAT usability failure: the Markdown test template is hostile to human input and should be replaced with interactive HTML.

**Source reports:**
- `Reports/2026-04-08-documentation-gap-analysis.md` (15 gaps, 5 critical)
- `Reports/2026-04-08-documentation-artifact-audit.md` (59 artifacts, 3 fully covered)

---

## Design Decisions (from brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Feature Documentation | Distinct artifact: `FEATURES.md` — living feature index referencing ADRs and interface docs | Gives quick orientation without digging through Bible/ADRs/interface docs |
| ADR format | Standard ADR template (Title, Status, Context, Decision, Consequences) | Industry standard, well-understood |
| Project Bible template depth | Full structural template with pre-formatted tables and per-section `<!-- Last Updated: YYYY-MM-DD -->` freshness markers | Addresses documentation lifecycle gap; makes Context Health Check reliable |
| UAT HTML template approach | Skeleton with placeholder patterns (`__SCENARIOS_JSON__`, etc.) and explicit schema in comments | Agent only populates data; CSS/JS/controls are fixed. Comments eliminate ambiguity. |
| CHANGELOG format | Keep a Changelog with 8 extended categories | Optimized for handoff value — replacement maintainer can scan by concern |
| ADR directory name | `docs/ADR documentation/` | Clear to non-technical readers |
| Interface doc directory | `docs/api and interfaces/` | Clear and descriptive |
| Document revision history | Phase gate snapshots in `docs/snapshots/` — not per-edit copies | Captures "what was decided" at gates; git handles change-by-change history |
| Framework docs directory | `docs/reference/` (renamed from `docs/framework/`) | Clearer purpose for non-technical readers |
| Delivery | Approach 1: Two PRs on one branch (structure+templates first, enforcement second) | Tightly coupled work in PR 1; enforcement is independent follow-on |

---

## 1. Three-Tier Document Structure

Every file in a created project falls into one of three tiers:

### Tier 1 — Framework Reference (installed by init.sh, read-only)

Documents that teach you how to use the framework. Read but not edited. Updated only via `scripts/check-updates.sh`.

**Location:** `docs/reference/`, `docs/platform-modules/`, `evaluation-prompts/`

### Tier 2 — Operational (created for the system to operate)

Documents the agent reads to know what to do and how the project is configured. These drive behavior.

**Location:** Project root (`CLAUDE.md`, `PROJECT_INTAKE.md`, `APPROVAL_LOG.md`), `.claude/`, `.github/workflows/`, `scripts/`

### Tier 3 — Project Artifacts (generated during development)

Documents produced as output of the methodology. The project's intellectual property and audit trail.

**Location:** Project root (primary artifacts), `docs/` subdirectories (supporting artifacts)

### Canonical Directory Structure

```
project-root/
│
│  ── Tier 2: Operational ──────────────────────────────────
│  CLAUDE.md                            # Agent instructions (init.sh template)
│  PROJECT_INTAKE.md                    # Structured requirements input (init.sh template)
│  APPROVAL_LOG.md                      # Phase gate audit trail (init.sh template)
│  .claude/
│    phase-state.json                   # Current phase tracking
│    build-progress.json                # Feature counter + test intervals + health check counter
│    tool-preferences.json              # Resolved tool selections
│    settings.json                      # Claude Code permissions + hooks
│    framework/                         # Development Guardrails (git hooks)
│  .github/workflows/
│    ci.yml                             # CI pipeline (language-specific)
│    release.yml                        # Release pipeline (platform-specific)
│  .gitignore                           # Language + platform ignores (init.sh template)
│  scripts/                             # Utility scripts
│
│  ── Tier 3: Project Artifacts (root-level) ───────────────
│  PRODUCT_MANIFESTO.md                 # Phase 0 output (template: product-manifesto.tmpl)
│  PROJECT_BIBLE.md                     # Phase 1 output (template: project-bible.tmpl)
│  FEATURES.md                          # Living feature reference (template: features.tmpl)
│  CHANGELOG.md                         # Append-only change log (template: changelog.tmpl)
│  CONTRIBUTING.md                      # Coding standards (agent generates)
│  BUGS.md                              # Bug tracking (template: bugs.tmpl)
│  USER_GUIDE.md                        # End-user documentation (Phase 3)
│  HANDOFF.md                           # Maintainer transfer doc (template: handoff.tmpl)
│  RELEASE_NOTES.md                     # User-facing release history (template: release-notes.tmpl)
│  sbom.json                            # Software Bill of Materials (Phase 3, tool-generated)
│  SECURITY.md                          # Vulnerability reporting (web/desktop, Phase 4)
│
│  docs/
│    ── Tier 1: Framework Reference ────────────────────────
│    reference/                         # Renamed from framework/
│      builders-guide.md
│      user-guide.md
│      governance-framework.md
│      executive-review.md
│      cli-setup-addendum.md
│      security-scan-guide.md
│    platform-modules/
│      web.md | desktop.md | mobile.md
│
│    ── Tier 3: Project Artifacts (docs/) ──────────────────
│    ADR documentation/                 # Architecture Decision Records
│      0001-architecture-selection.md   # Phase 1 initial ADR (template: adr.tmpl)
│      NNNN-title.md                    # Phase 2+ ADRs
│    api and interfaces/                # Interface/API documentation
│    test-results/                      # Phase 3 scan archives + archived UAT sessions
│    snapshots/                         # Phase gate snapshots (auto-created by check-phase-gate.sh)
│      phase-0-to-1_YYYY-MM-DD/
│      phase-1-to-2_YYYY-MM-DD/
│      phase-2-to-3_YYYY-MM-DD/
│      phase-3-to-4_YYYY-MM-DD/
│    INCIDENT_RESPONSE.md               # Incident response playbook (template: incident-response.tmpl)
│
│  tests/
│    uat/
│      sessions/                        # UAT session directories
│        session-N-fX-fY/
│          test-session-N-v1.html       # Interactive test form (template: uat-test-session.html)
│          submissions/                 # Human tester results
│          agent-results/               # Agent test results
│
│  evaluation-prompts/                  # Adversarial review prompts (Tier 1)
│    Projects/
```

### Changes from Current init.sh Output

| Change | Type |
|---|---|
| `docs/framework/` → `docs/reference/` | Rename |
| `docs/ADR documentation/` | New directory (empty at init) |
| `docs/api and interfaces/` | New directory (empty at init) |
| `docs/snapshots/` | New directory (empty at init, populated by check-phase-gate.sh) |
| `FEATURES.md` | New root-level artifact (template copied at init, empty until Phase 2) |
| `BUGS.md` | New root-level artifact (template copied at init, empty until first UAT session) |
| `CHANGELOG.md` | New root-level artifact (template copied at init, empty until first feature) |
| `RELEASE_NOTES.md` | New root-level artifact (template copied at init, empty until Phase 4) |

---

## 2. Templates

### 2.1 `templates/generated/project-bible.tmpl` (~200 lines)

**Priority:** P0 (Critical)
**Resolves:** Gap #6 (no template for 16-section document), Gap #13 (documentation lifecycle)

All 16 sections as H2 headings. Each section includes:
- `<!-- Last Updated: YYYY-MM-DD -->` freshness marker
- A comment block describing: what belongs in this section, expected depth (table/prose/list), and what source material to draw from

Pre-formatted tables for:
- Bug Severity Classification (SEV-1 through SEV-4 with definitions and examples)
- Orchestrator Competency Matrix (9 domains with validation benchmarks)
- UAT Plan fields

Sections (in order):
1. Product Manifesto (full text from Phase 0)
2. Revenue Model & Cost Constraints
3. Architecture Decision Record (selected stack, rejected alternatives, rationale)
4. Threat Model & Risk/Mitigation Matrix
5. Data Model (full specification)
6. Data Migration Plan (if applicable)
7. Auth & Identity Strategy
8. Observability & Logging Strategy
9. UI Component Specifications
10. Coding Standards
11. Build & Distribution Strategy
12. Test Strategy
13. Orchestrator Profile Summary
14. Accessibility Requirements
15. Platform-Specific Requirements
16. Context Management Plan

**Agent instructions:** The agent fills sections during Phase 1 Step 1.6. During Phase 2, Step 2.5 updates individual sections and refreshes the `<!-- Last Updated -->` marker for each modified section. The agent must verify cross-section consistency after every update.

### 2.2 `templates/generated/adr.tmpl` (~30 lines)

**Priority:** P0 (Critical)
**Resolves:** Gap #1 (no location/format/template for ADRs)

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

**Numbering:** Sequential four-digit prefix: `0001-architecture-selection.md`, `0002-database-choice.md`, etc.
**Location:** `docs/ADR documentation/`
**Lifecycle:** Write-once. If a decision is reversed, a new ADR is created with Status: Superseded referencing the original. The original ADR is never edited except to update its Status field to "Superseded by ADR-NNNN."

The Phase 1 architecture selection (Builder's Guide Step 1.2) becomes `0001-architecture-selection.md`. It is also embedded in the Project Bible Section 3, which references the ADR file. Phase 2 ADRs continue the sequence for non-trivial decisions made during construction.

### 2.3 `templates/uat-test-session.html` (~350 lines)

**Priority:** P0 (Critical)
**Resolves:** Gap #15 (UAT format unusable, no versioning, no archival)
**Replaces:** `templates/uat-test-template.md` as primary UAT format (Markdown template retained as fallback reference)

Self-contained single-file HTML application. No external dependencies. Structure based on the meshscope `test-session-4.html` (proven in real-world usage).

**Fixed elements (agent does not modify):**
- CSS: Dark theme, responsive layout, scenario cards with colored left borders
- Progress bar and completion counter
- Pass/Fail/Skip button group per scenario with visual state
- Expandable details panel per scenario (steps + expected result)
- Per-scenario notes textarea
- Bug entry form: severity dropdown (SEV-1 through SEV-4), feature dropdown, description, steps to reproduce, expected vs actual
- Add/remove bug functionality
- Overall notes textarea
- "Copy Results to Clipboard" export button (exports structured Markdown)
- Tester name input field

**Placeholder patterns (agent populates per session):**

The template contains clearly marked placeholder tokens. Each token has an inline HTML comment immediately above it specifying exactly what the agent must provide.

| Token | Type | Description |
|---|---|---|
| `__SESSION_TITLE__` | String | e.g., "UAT Session 4" |
| `__SESSION_DATE__` | String | YYYY-MM-DD |
| `__SESSION_FEATURES__` | String | e.g., "Basic Mesh Repair, Scale/Rotate/Mirror" |
| `__FEATURE_SECTIONS__` | HTML | One `<h2>` + optional `<div class="fixture-ref">` per feature |
| `__FEATURE_OPTIONS__` | HTML | `<option>` elements for the bug form's feature dropdown |
| `__SCENARIOS_JSON__` | JavaScript | Array of scenario objects (schema below) |

**Scenarios JSON schema (embedded in template as a comment block):**

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
//     "feature": number,   // Feature number this scenario tests (must match a __FEATURE_SECTIONS__ heading)
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

**Versioning:** `test-session-N-v1.html`. Version increments on re-test after bug fixes (v2, v3). Previous versions are never overwritten.

**Archival:** After completion and agent review, the completed HTML is copied to `docs/test-results/[YYYY-MM-DD]_uat-session-N-vX.html`.

**Export:** The "Copy Results" button generates structured Markdown with: session metadata, summary counts (pass/fail/skip/untested), scenario results table, bugs found (if any), and overall notes. This Markdown is pasted into the agent conversation or saved to `submissions/`.

### 2.4 `templates/generated/product-manifesto.tmpl` (~80 lines)

**Priority:** P1 (High)
**Resolves:** Gap #5 (no template for foundational artifact)

Sections:
1. **Product Intent** — One paragraph: what the product does and why it exists. (Source: Intake Section 2.1, refined in Step 0.4)
2. **Functional Requirements** — Must-Have features with if/then logic triggers and failure states. Should-Have features for v1.1. Will-Not-Have list with at least 3 items. (Source: Step 0.1)
3. **User Journeys** — Primary persona definition. Success path (3-5 steps with user sees/does/system responds). Failure recovery per step. Exit points and recovery. (Source: Step 0.2)
4. **Data Contracts** — Inputs (type, validation, sensitivity). Transformations. Outputs (format, latency). Third-party data (fallback if unavailable). State (persistent vs. ephemeral). (Source: Step 0.3)
5. **MVP Cutline** — Hard line. Features above the line ship first. Everything else goes to Post-MVP Backlog.
6. **Post-MVP Backlog** — Prioritized by user feedback after launch.
7. **Will-Not-Have List** — Explicit scope boundaries.
8. **Open Questions** — Anything flagged during Steps 0.1-0.3 requiring Orchestrator decision before Phase 1.
9. **Appendix A: Revenue Model & Unit Economics** — (Standard+ Track. Skip for internal tools.) Pricing model, per-user costs, break-even, hosting cost ceiling. (Source: Step 0.5)
10. **Appendix B: Orchestrator Competency Matrix** — Self-assessment per domain with automated tooling for "No" domains. (Source: Step 0.6)
11. **Appendix C: Trademark & Legal Pre-Check** — (Standard+ Track.) USPTO/WIPO search, data privacy applicability, distribution channel requirements. (Source: Step 0.7)

Each section includes a comment: `<!-- Source: Phase 0 Step N.N. See builders-guide.md for the full prompt and review checklist. -->`

### 2.5 `templates/generated/features.tmpl` (~40 lines)

**Priority:** P1 (High)
**Resolves:** Gap #3 (Feature Documentation — previously phantom artifact, now defined)

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

**Lifecycle:** Created at Phase 2 initialization (empty template). Updated at Step 2.5 alongside CHANGELOG and Bible. Each feature gets one section. Status changes from "In Progress" to "Complete" when the feature passes all tests.

### 2.6 `templates/generated/handoff.tmpl` (~60 lines)

**Priority:** P1 (High)
**Resolves:** Gap #10 (no template for 9-section handoff document)

All 9 sections as H2 headings with content descriptions:

1. **Product Intent & Architecture Overview** — What this application does, who uses it, and how it's built. Link to PROJECT_BIBLE.md for full architecture.
2. **Development Setup** — Step-by-step from blank machine to running dev environment on each target platform. Every command must work verbatim. Every dependency listed with version and install command.
3. **Build & Release Process** — How to build, test, and release for each target platform. Link to .github/workflows/ for CI/CD configuration.
4. **Technical Debt Map** — Specific files, nature of debt, estimated effort, and priority. Not "some areas need improvement" — concrete file paths and line ranges.
5. **Maintenance Schedule** — Monthly, quarterly, biannual cadence from Builder's Guide Step 4.4. What to check, what to update, what to re-run.
6. **Incident History** — Past incidents with date, severity, root cause, resolution, and what changed to prevent recurrence. Link to docs/INCIDENT_RESPONSE.md for the playbook.
7. **Bug Reporting & Triage** — How users report bugs, where bugs are tracked, triage cadence, severity SLAs. Link to BUGS.md.
8. **Key Contacts & Third-Party Services** — Service accounts, API providers, infrastructure dependencies. For each: what it does, how to access it, what breaks if it goes down, who to contact.
9. **AI Quick Start Prompt** — A ready-to-paste prompt for a new AI agent to resume work on this project.

Section 9 includes an example:

```
Read these files in order, then confirm what you understand before taking action:
1. CLAUDE.md (your instructions and constraints)
2. PROJECT_BIBLE.md (architecture, data model, threat model, test strategy)
3. FEATURES.md (what's built and how it works)
4. CHANGELOG.md (recent changes)
5. BUGS.md (known issues and their status)
Current state: Phase [N], last completed feature: [name], known issues: [list]
Task: [what needs to happen next]
```

### 2.7 `templates/generated/incident-response.tmpl` (~80 lines)

**Priority:** P1 (High)
**Resolves:** Gap #9 (no template, scattered specification across 3 documents)

Consolidates Builder's Guide Step 4.1.5, Governance Framework Section VII, and User Guide severity classification into a single template.

Sections:
1. **Severity Classification** — Pre-formatted table (SEV-1 through SEV-4 with definition, response time, notification chain). Placeholder rows for project-specific contacts.
2. **Containment Procedures** — SEV-1/SEV-2: rollback first, investigate second. Log preservation before rollback. Data breach: isolate, preserve evidence, notify IT Security and Legal.
3. **Rollback Procedure** — Platform-specific steps (placeholder: "See Platform Module for platform-specific rollback"). Data model rollback steps.
4. **Secrets Rotation** — Compromised secret response: rotate, audit access logs, update all environments, verify application functionality.
5. **Notification Chains** — Table with role, contact method, when to notify. Pre-populated with Orchestrator and Backup Maintainer rows. Organizational deployments add: Project Sponsor, IT Security, Legal.
6. **Enterprise IR Integration** (organizational deployments) — Data breach response obligations, vulnerability disclosure process, vendor incident response, attack vector incident response. (Source: Governance Framework Section VII)
7. **Post-Incident Review** — Template for recording: timeline, root cause, impact, resolution, preventive measures.

### 2.8 `templates/generated/changelog.tmpl` (~25 lines)

**Priority:** P2 (Medium)
**Resolves:** Gap #7 (no format specified)

```markdown
# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/) with extended categories
for handoff clarity. Categories are ordered by impact severity.

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

**Category definitions (embedded as comments in template):**
- **Security** — Vulnerability fixes, dependency patches for CVEs, auth changes
- **Data Model** — Schema migrations, data format changes, rollback notes
- **Added** — New features, new endpoints, new commands
- **Changed** — Modifications to existing behavior
- **Fixed** — Bug fixes (reference BUGS.md entry if applicable)
- **Removed** — Removed features, deprecated endpoints
- **Infrastructure** — CI/CD changes, dependency updates, configuration changes, tooling
- **Documentation** — Significant doc updates (new ADRs, updated threat model, revised user guide — not every Bible tweak)

**Lifecycle:** Append-only. New entries prepended under `[Unreleased]`. When a release is cut, `[Unreleased]` becomes `[version] - YYYY-MM-DD` and a new `[Unreleased]` section is added above.

### 2.9 `templates/generated/bugs.tmpl` (~30 lines)

**Priority:** P2 (Medium)
**Resolves:** Implicit gap (BUGS.md enforced by test-gate.sh grep patterns but no template)

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

### 2.10 `templates/generated/release-notes.tmpl` (~20 lines)

**Priority:** P3 (Low)
**Resolves:** Gap #11 (no template)

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
```

**Lifecycle:** Append per release. Each release gets a new section above the previous one (newest first). The first release includes the "What This Application Does" section; subsequent releases can omit it or update it if the product scope has changed.

---

## 3. Phase Gate Snapshots

At each successful phase gate transition, `check-phase-gate.sh` automatically copies the relevant artifacts into a timestamped snapshot directory under `docs/snapshots/`. Snapshots are append-only — once created, never modified.

| Gate | Artifacts Captured |
|---|---|
| **Phase 0→1** | PRODUCT_MANIFESTO.md, APPROVAL_LOG.md, PROJECT_INTAKE.md |
| **Phase 1→2** | PROJECT_BIBLE.md, PRODUCT_MANIFESTO.md, APPROVAL_LOG.md |
| **Phase 2→3** | PROJECT_BIBLE.md, FEATURES.md, CHANGELOG.md, BUGS.md, APPROVAL_LOG.md |
| **Phase 3→4** | All root-level Tier 3 artifacts, docs/INCIDENT_RESPONSE.md, listing of docs/test-results/ contents |

**Directory naming:** `phase-N-to-M_YYYY-MM-DD/`

**Purpose:** Provides non-technical stakeholders and auditors with point-in-time document snapshots at each decision gate without requiring git commands. Between gates, git provides the full change-by-change history. Per-section `<!-- Last Updated: YYYY-MM-DD -->` markers in the Bible template provide section-level visibility within a phase.

---

## 4. Cross-Reference Reconciliation

### 4.1 Builder's Guide Appendix A Updates

**Add these artifacts:**

| Artifact | Phase | Purpose |
|---|---|---|
| `CLAUDE.md` | 0 (init) | Agent instructions, project state, tool configuration |
| `PROJECT_INTAKE.md` | 0 (init) | Structured requirements collection |
| `APPROVAL_LOG.md` | 0 (init) | Phase gate approval audit trail |
| `FEATURES.md` | 2+ | Living feature index — what each feature does, interfaces, ADRs, test coverage |
| `BUGS.md` | 2+ | Bug tracking with severity, status, disposition |
| `SECURITY.md` | 4 | Vulnerability reporting (web/desktop projects) |
| Compliance Screening Matrix | 0 (org) | Regulatory applicability assessment (embedded in Intake Section 8.4) |
| Penetration Test Report | 3 (Standard+) | External security assessment (external document) |
| Handoff Test Results | 4 (org) | Backup maintainer validation results |

**Redefine:**

| Artifact | Current | Updated |
|---|---|---|
| Feature Documentation | "Component behavior, business logic rationale, UX decisions" (undefined location) | `FEATURES.md` — living feature index at project root. Template: `features.tmpl`. Updated at Step 2.5. |
| Security Audit Logs | "SAST/DAST results, remediation actions" (ambiguous location) | Archived in `docs/test-results/`. Remediation actions recorded in CHANGELOG.md under Security category. |
| Architecture Decision Records | "Every major choice with alternatives and rationale" (no location) | Stored in `docs/ADR documentation/`, numbered sequentially (0001-title.md). Template: `adr.tmpl`. |
| Interface Documentation | "Per-endpoint/command/UI contracts, error codes" (no location) | Stored in `docs/api and interfaces/`. Format per Platform Module convention. |
| Performance Baselines | "Metrics for future comparison" (no format) | Archived in `docs/test-results/` with naming convention `[date]_performance-baseline.[ext]`. |

**Fix:**

| Issue | Resolution |
|---|---|
| sbom.json location conflict (root vs. docs/test-results/) | Canonical location: project root. Also archived in docs/test-results/ at Phase 3 (copy, not move). |

### 4.2 Executive Review Fix

- Remove "Launch Plan" (exec-review.md:194) — phantom artifact not defined anywhere else. If intended, it is covered by the Phase 3.6 Pre-Launch Preparation process and the Go-Live Verification checklist. No standalone document needed.

### 4.3 Governance Framework Section XV Alignment

- Sync artifact list with updated Appendix A so both documents agree.

### 4.4 CLAUDE.md Template Additions

Add references to these 13 artifacts/processes missing from `templates/generated/claude-md.tmpl`:

| Addition | Phase | What to Add |
|---|---|---|
| FEATURES.md update | 2 (Step 2.5) | "Update FEATURES.md with a new section for each completed feature." |
| Context Health Check | 2 (every 3-4 features) | "Every 3-4 features, perform a Context Health Check: summarize features built, features remaining, current data model, known issues. Verify against PROJECT_BIBLE.md." |
| Phase 2 Completion Checkpoint | 2→3 | Reference the checklist from builders-guide.md:1005-1017 |
| HANDOFF.md | 4 (Step 4.5) | "Generate HANDOFF.md using the template at templates/generated/handoff.tmpl." |
| docs/INCIDENT_RESPONSE.md | 4 (Step 4.1.5) | "Generate docs/INCIDENT_RESPONSE.md using the template at templates/generated/incident-response.tmpl." |
| RELEASE_NOTES.md | 4 (Step 4.2) | "Generate RELEASE_NOTES.md using the template at templates/generated/release-notes.tmpl." |
| USER_GUIDE.md | 3 (Step 3.6) | "Generate USER_GUIDE.md appropriate to platform and audience." |
| SECURITY.md | 4 (web/desktop) | "For web and desktop projects, generate SECURITY.md with supported versions, reporting mechanism, response time, and safe harbor." |
| sbom.json | 3 (Step 3.2) | "Generate sbom.json using CycloneDX, syft, or ecosystem equivalent." |
| docs/test-results/ archival | 3 (Step 3.5.9) | "Archive all Phase 3 scan results in docs/test-results/ with naming convention [date]_[scan-type]_[pass|fail].[ext]." |
| Mandatory Rollback Test | 4 (Step 4.1.5) | "Test the rollback procedure before production launch. Record time elapsed and issues." |
| Go-Live Verification | 4 (Step 4.2) | Reference the checklist from builders-guide.md:1312-1323 |
| BUGS.md format | 2 | "Track bugs in BUGS.md using the template format. Status and severity values are parsed by scripts/test-gate.sh." |

---

## 5. Enforcement Additions (PR 2)

### 5.1 Phase Gate Artifact Existence Checks

Add to `check-phase-gate.sh`:

| Gate | Check | Behavior |
|---|---|---|
| 0→1 | `PRODUCT_MANIFESTO.md` exists | Block transition if missing |
| 1→2 | `PROJECT_BIBLE.md` exists | Block transition if missing |
| 3→4 | `HANDOFF.md` exists | Block transition if missing |
| 3→4 | `docs/INCIDENT_RESPONSE.md` exists | Block transition if missing |
| 3→4 | `docs/test-results/` contains at least 1 file | Block transition if empty |
| 3→4 | `sbom.json` exists | Block transition if missing |

These checks run alongside the existing APPROVAL_LOG.md consistency check. They verify that the phase's primary deliverable actually exists before allowing the transition.

### 5.2 Phase Gate Snapshot Creation

After a successful phase gate check, `check-phase-gate.sh` creates the snapshot directory and copies the relevant artifacts (per the table in Section 3).

### 5.3 Context Health Check Reminder

- Add `features_since_last_health_check` field to `.claude/build-progress.json` (alongside existing `features_since_last_test`)
- Increment when `test-gate.sh --record-feature` is called
- Session start hook warns when counter reaches 3: "Context Health Check recommended — 3+ features since last check. Run a health check to verify the Bible still accurately reflects the codebase."
- Agent resets counter after performing health check (new command: `test-gate.sh --reset-health-check`)

### 5.4 UAT Lifecycle Enforcement

- `test-gate.sh --record-feature` checks that the UAT session file exists in `tests/uat/sessions/` for the current batch (warning, not blocking)
- Completed UAT sessions are copied to `docs/test-results/` during the archival step (agent responsibility, documented in CLAUDE.md template)

---

## 6. Files Modified

### PR 1: Structure + Templates + Cross-References

| File | Changes |
|---|---|
| **`docs/builders-guide.md`** | Appendix A reconciliation (add 9 artifacts, redefine 5, fix sbom location). Step 2.5 updates (ADR location/format, CHANGELOG 8-category format, FEATURES.md integration, interface doc location). Documentation lifecycle guidance. All directory path references updated. |
| **`docs/user-guide.md`** | Phase summary table updates. Directory references updated (framework/ → reference/). Template references added. Three-tier structure explanation. |
| **`docs/governance-framework.md`** | Section XV artifact list aligned with updated Appendix A. |
| **`docs/executive-review.md`** | Remove "Launch Plan" phantom artifact reference. |
| **`templates/generated/claude-md.tmpl`** | Add 13 missing artifact references. CHANGELOG 8-category specification. UAT HTML format reference. FEATURES.md Step 2.5 instruction. Template references for Bible, ADR, Handoff, IR, Changelog, Bugs, Release Notes. |
| **`init.sh`** | Create new directories (ADR documentation, api and interfaces, snapshots). Rename docs/framework/ to docs/reference/. Copy new templates (10 files). Update all internal path references (docs/framework/ → docs/reference/). Update CLAUDE.md generation section. |
| **`README.md`** | Update "What Gets Created" directory structure. Update directory references. |
| **`scripts/upgrade-project.sh`** | Update all `docs/framework/` path references to `docs/reference/`. |
| **`scripts/resume.sh`** | Update any `docs/framework/` path references to `docs/reference/`. |
| **`scripts/check-session-state.sh`** | Update any `docs/framework/` path references to `docs/reference/`. |
| **`evaluation-prompts/Projects/run-reviews.sh`** | Update any `docs/framework/` path references to `docs/reference/`. |

**New files (10 templates):**

| File | Size |
|---|---|
| `templates/generated/project-bible.tmpl` | ~200 lines |
| `templates/generated/adr.tmpl` | ~30 lines |
| `templates/uat-test-session.html` | ~350 lines |
| `templates/generated/product-manifesto.tmpl` | ~80 lines |
| `templates/generated/features.tmpl` | ~40 lines |
| `templates/generated/handoff.tmpl` | ~60 lines |
| `templates/generated/incident-response.tmpl` | ~80 lines |
| `templates/generated/changelog.tmpl` | ~25 lines |
| `templates/generated/bugs.tmpl` | ~30 lines |
| `templates/generated/release-notes.tmpl` | ~20 lines |

`templates/uat-test-template.md` is retained as a fallback reference but is no longer the primary UAT format.

### PR 2: Enforcement

| File | Changes |
|---|---|
| **`scripts/check-phase-gate.sh`** | Add artifact existence checks (6 checks across 3 gates). Add snapshot creation logic (copy artifacts to docs/snapshots/ on successful gate passage). |
| **`init.sh`** | Add `features_since_last_health_check` field to `.claude/build-progress.json` generation. |
| **`scripts/test-gate.sh`** | Add `--reset-health-check` command. Increment health check counter in `--record-feature`. |
| **Session hook script** (new or modify existing `scripts/session-test-gate-check.sh`) | Add Context Health Check reminder when counter reaches 3. |

---

## 7. Document Types and Lifecycle

| Type | Examples | Lifecycle | Update Rule |
|---|---|---|---|
| **Governing documents** | Manifesto, Bible | Written once, updated in place | Agent verifies consistency after every update. Per-section freshness markers. |
| **Append-only logs** | CHANGELOG, APPROVAL_LOG, RELEASE_NOTES | New entries added; previous entries never modified | Newest entries first (CHANGELOG, RELEASE_NOTES) or chronological (APPROVAL_LOG). |
| **Decision records** | ADRs | Write-once | If reversed, new ADR created with Status: Superseded. Original only updated to note supersession. |
| **Living indexes** | FEATURES.md, BUGS.md | Updated per feature/bug | Status fields change; entries are never removed (Removed status instead). |
| **Snapshots** | Test results, SBOM, phase gate snapshots | Point-in-time artifacts | Named with date. Never modified after creation. |
| **Reference documents** | HANDOFF, USER_GUIDE, INCIDENT_RESPONSE | Written at Phase 3-4, updated during maintenance | Should have "Last Updated" marker at top. |
| **Framework reference** | Builder's Guide, User Guide, Governance | Installed by init.sh, read-only | Updated only via check-updates.sh from upstream framework. |

---

## 8. Naming Conventions

| Context | Convention | Examples |
|---|---|---|
| Root-level artifacts | `UPPER_CASE.md` | `PROJECT_BIBLE.md`, `FEATURES.md`, `HANDOFF.md` |
| docs/ subdirectory files | `lowercase-with-hyphens.md` or `NNNN-title.md` for numbered sequences | `docs/INCIDENT_RESPONSE.md`, `docs/ADR documentation/0001-architecture-selection.md` |
| Test results | `[date]_[scan-type]_[pass|fail].[ext]` | `2026-04-10_semgrep_pass.json` |
| UAT sessions (active) | `test-session-N-vX.html` | `test-session-4-v1.html`, `test-session-4-v2.html` |
| UAT sessions (archived) | `[date]_uat-session-N-vX.html` | `2026-04-08_uat-session-4-v1.html` |
| Phase gate snapshots | `phase-N-to-M_YYYY-MM-DD/` | `phase-1-to-2_2026-04-15/` |
| ADRs | `NNNN-title.md` | `0001-architecture-selection.md` |

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial spec. |

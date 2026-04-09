# The Solo Orchestrator Builder's Guide

## Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-002-BUILD |
| **Version** | 1.0 |
| **Classification** | Technical Implementation Manual |
| **Date** | 2026-04-02 |
| **Audience** | Solo Orchestrator (technologist executing the framework) |
| **Companion Documents** | SOI-003-GOV v1.0 — Enterprise Governance Framework |
| | SOI-004-INTAKE v1.0 — Project Intake Template |
| | SOI-005-CLI v1.0 — Claude Code CLI Setup Addendum |
| **Platform Modules** | SOI-PM-WEB v1.0 — Web Applications |
| | SOI-PM-DESKTOP v1.0 — Desktop Applications (Standalone & Client-Server) |
| | SOI-PM-MOBILE v1.0 — Mobile Applications (iOS & Android) |

---

## How to Use This Guide

This is the platform-agnostic core of the Solo Orchestrator methodology. It contains the phase-by-phase process, quality controls, prompts, remediation tables, and documentation requirements that apply to every project regardless of what you're building — web app, desktop app, CLI tool, or any other platform with a completed Platform Module.

**Platform-specific guidance** (architecture patterns, tooling, build pipelines, testing strategies, distribution, maintenance) lives in separate Platform Modules. You'll see callouts like this throughout the guide:

> **⟁ PLATFORM MODULE:** Reference your Platform Module for [specific topic].

When you see that callout, open the Platform Module that matches your project type and follow the guidance there. The core guide tells you *when* to do something; the Platform Module tells you *how* for your specific platform.

### Recommended Workflow: Intake-First

The most efficient way to use this guide is with the **Project Intake Template** (SOI-004-INTAKE) completed before you begin Phase 0. The Intake collects every constraint, preference, and business decision the AI agent needs to operate autonomously.

When the Intake is provided, the Phase 0 and Phase 1 prompts shift from open-ended discovery to **validation, expansion, and challenge.** The agent already knows your constraints — it uses the conversational prompts to expand vague areas, surface contradictions, and fill gaps.

**Without the Intake:** The guide works standalone. Expect more round-trips.

**With a partial Intake:** The agent consumes what's provided and discovers what's missing.

### Document Relationships

- **Project Intake Template** (SOI-004-INTAKE) — Complete before Phase 0. The structured input.
- **This guide** (SOI-002-BUILD) — Platform-agnostic methodology. The process.
- **Platform Modules** (SOI-PM-*) — Platform-specific architecture, tooling, testing, deployment. Referenced from this guide at specific points.
- **CLI Setup Addendum** (SOI-005-CLI) — Claude Code CLI configuration. Optional but recommended.
- **Enterprise Governance Framework** (SOI-003-GOV) — Required for organizational deployments.

**You are the Orchestrator.** You define intent, constraints, and validation. The AI provides syntax, scaffolding, and pattern execution. Every phase produces artifacts that gate entry into the next phase. If a phase artifact is incomplete or contradicts a prior artifact, you do not advance.

**Assumptions:** You have reliable internet access, administrative rights on your development machine, and experience evaluating technical output. This is not a junior developer role — you must be able to look at AI-generated code and determine if it is correct. **Windows users:** WSL (Windows Subsystem for Linux) is required. Claude Code, the init script, and the development toolchain require a Unix-like environment.

---

## What This Framework Is

The Solo Orchestrator Framework is a structured software development methodology that enables a single experienced technologist to build MVP-quality applications with a clear path to production, using AI Large Language Models as the execution layer. The technologist acts as Product Owner, Lead Architect, and QA Director. The AI proposes architecture, generates logic, and writes code within constraints defined and validated by the human operator. The framework produces functional, tested, security-scanned MVPs — production deployment requires additional hardening, operational readiness, and (for organizational projects) governance completion.

### What This Is Not

This framework does not replace engineering teams. It is not appropriate for:

- **Compliance-regulated systems** requiring SOC 2, HIPAA, PCI-DSS, or FedRAMP certification. These require dedicated security teams and audit processes beyond what a solo builder can validate.
- **High-availability systems** with 99.99%+ uptime SLAs. Solo-maintained systems have a single point of failure at the operator level.
- **Large-scale distributed systems** requiring microservices, message queues, or multi-region deployments. These require dedicated DevOps capacity.
- **Enterprise integration projects** (SAP, Salesforce, custom ERP) where the integration complexity exceeds the application logic.

The framework is designed for internal tools, utilities, departmental applications, prototypes, and MVP validation — projects that sit in the backlog because they don't justify a full team. Platform Modules for web, desktop, and mobile guide you from MVP through production readiness. Additional platform modules (CLI, embedded) can be added as they mature.

### How This Differs From "Vibe Coding"

- Requirements are formally documented before any technology is selected (Phase 0).
- Architecture decisions are constrained by budget, timeline, and maintenance capacity — not AI suggestion (Phase 1).
- Every feature is built test-first: tests define expected behavior before implementation code is written (Phase 2).
- Security is validated through automated scanning, dependency auditing, and manual review (Phase 3).
- Deployment includes automated pipelines, monitoring, alerting, and documented incident response procedures (Phase 4).
- Every phase produces documentation enabling a qualified replacement to resume maintenance.

The AI writes code. The human makes every decision, validates every output, and gates every phase transition.

### Enforcement Model

The framework's controls operate at three tiers. The **CI pipeline** (SAST, dependency audit, license check, secret detection, build, tests, phase gate consistency, approval log integrity) provides mechanical enforcement — it blocks merges when checks fail. **Pre-commit hooks** (secret detection, SAST quick scan, test co-location) provide early warning on commit. **LLM instructions** (CLAUDE.md, this guide, the Project Bible) provide comprehensive guidance that the agent follows between decision gates, with the human as the review layer.

**Process enforcement.** In addition to CI and pre-commit checks, a process checklist state machine (`scripts/process-checklist.sh`) mechanically enforces sequential step completion for the Build Loop, UAT sessions, and Phase 3/4 validation. The PreToolUse hook (`scripts/pre-commit-gate.sh`) blocks commits when checklist steps are incomplete. It also blocks `--no-verify` (security hook bypass), `--force` push (history overwrite), and unauthorized process resets. Reset operations require the Orchestrator to run the command directly in a terminal — the agent cannot invoke them. See the User Guide, Section "Process Enforcement," for the complete checklist sequences and enforcement points.

**TDD enforcement timing.** The Build Loop enforces test-first ordering at commit time, not at file-write time. This is intentional: file-write gating would add latency to every Write/Edit operation and create false positives for utility files, configuration, and documentation. Commit-time enforcement ensures that when code reaches the repository, it has passed through the full Build Loop sequence — tests written, tests verified failing, implementation complete, security audit, documentation updated.

Only the CI pipeline is a hard enforcement boundary. The process checklist and hooks provide strong mechanical enforcement within Claude Code sessions. Everything else depends on the agent following instructions and the Orchestrator reviewing at decision gates. See the User Guide's "What Is Enforced vs. What Is Guided" section for the complete breakdown.

---

## Process Right-Sizing

Before beginning, classify your project into one of three tracks:

**Light Track** — Internal tools, personal utilities, low-risk prototypes with no external users.

- Skip Step 1.1 (Market Audit) entirely.
- Abbreviate Phase 3 (no formal UAT; integration tests and a manual smoke test are sufficient).
- Simplify Phase 4 (basic deployment/distribution; monitoring optional for <10 users).
- **Do NOT skip:** Security tooling, TDD, documentation. A prototype built with sloppy practices becomes a production application with technical debt when someone decides it's useful.

**Standard Track** — Products with external users, moderate complexity, or revenue expectations under $10K/month.

- Execute all phases as written.
- Market validation (Step 1.1.5) can use lightweight signals.
- Full Phase 3 and Phase 4 apply.

**Full Track** — Products targeting enterprise buyers, handling sensitive data, or with revenue expectations above $10K/month.

- Execute all phases with no abbreviation.
- Market validation requires customer interviews or letters of intent.
- Phase 3 must include all automated security tooling plus penetration testing.
- Phase 4 must include formal incident response and on-call alerting.
- Additionally required: contract testing, load/stress testing if applicable, and platform-specific certification requirements (code signing, app store review, etc.).

**Organizational POC Modes:** For organizational deployments where full governance approvals are not yet in hand, the intake wizard (`scripts/intake-wizard.sh`) offers two Proof of Concept modes:

- **Sponsored POC** — the organization knows and has approved the exploration. AI deployment path, project sponsor, and time allocation are required. Insurance, liability entity, ITSM, exit criteria, and backup maintainer are deferred. All technical work follows the full phase-gate process at production quality.
- **Private POC** — personal exploration on your own time. All governance pre-conditions are deferred. Same production-quality technical work.

Both POC modes carry constraints: no production deployment, no real user data, no external users. When ready to go to production, run `scripts/intake-wizard.sh --upgrade-to-production` to resolve deferred pre-conditions. All technical artifacts carry forward unchanged.

**Terminology — "Standard+" Track:** Throughout this guide, **"Standard+"** is shorthand for **"Standard and Full tracks"** — i.e., any track above Light. When a step is labeled "Standard+ Track," it means the step is required for both Standard and Full tracks and skipped (or abbreviated) for Light track. This shorthand avoids repeating "Standard and Full" in every heading.

### Track Requirements Matrix

The following table is the single authoritative reference for what each track requires. When in doubt, this table overrides any individual step's inline guidance.

**Enforcement note:** The process enforcement scripts (`process-checklist.sh`, `check-phase-gate.sh`, `pre-commit-gate.sh`) enforce the same step sequences for all tracks. Track differentiation applies to the **depth, rigor, and scope** of each step — not whether the step appears in the checklist. Light track "abbreviates" Phase 3 by performing lighter-weight validation at each step (e.g., integration tests + manual smoke test instead of formal UAT), not by removing steps from the checklist.

| Requirement | Light | Standard | Full |
|---|---|---|---|
| **Phase 0** | | | |
| Step 0.1–0.4 (Core Discovery) | Required | Required | Required |
| Step 0.5 (Revenue Model) — Manifesto Appendix A | SKIP (mark "N/A — internal tool") | Required | Required |
| Step 0.6 (Competency Matrix) — Manifesto Appendix B | Required | Required | Required |
| Step 0.7 (Trademark & Legal) — Manifesto Appendix C | SKIP (mark "N/A — internal tool") | Required | Required |
| **Phase 1** | | | |
| Step 1.1 (Market Audit / Business Strategy) | SKIP | Required | Required |
| Step 1.1.5 (Market Signal Validation) | SKIP | Required (lightweight signals) | Required (interviews / LOIs) |
| Steps 1.2–1.5 (Architecture, Threat Model, Bible) | Required | Required | Required |
| **Phase 2** | | | |
| TDD, Security Auditing, Documentation | Required | Required | Required |
| Build Loop (all steps) | Required | Required | Required |
| **Phase 3** | | | |
| Steps 3.1–3.5 (Integration, Security, Chaos, A11y, Perf) | Required (abbreviated depth) | Required (full depth) | Required (full depth) |
| Formal UAT sessions | Not required (manual smoke test sufficient) | Required | Required |
| Step 3.5.5 (Contract Testing) | Not required | Required (if APIs exist) | Required |
| Step 3.5.7 (Load/Stress Testing) | Not required | Not required | Required (if applicable) |
| Penetration Testing | Not required | Required (IT Security exemption allowed) | Required (no exemption) |
| DAST (web apps) | Baseline scan | Baseline scan | Active scan |
| Step 3.6 (Pre-Launch Preparation) | Not required | Required | Required |
| Evaluation Prompts (Security, Red Team) | Optional | Recommended | Required |
| **Phase 4** | | | |
| Step 4.1 (Production Build) | Required | Required | Required |
| Deployment Strategy | Cut-over acceptable | Blue/green or rolling | Blue/green or rolling |
| Step 4.1.5 (Rollback & Incident Response) | Simplified (basic rollback) | Required | Required (formal on-call alerting) |
| Step 4.2 (Go-Live Checklist) | Required | Required | Required |
| Monitoring | Optional (<10 users) | Required | Required |
| Release Notes (public) | Internal only | Required (published) | Required (published) |
| **PRODUCT_MANIFESTO.md Appendices** | | | |
| Appendix A — Revenue Model | SKIP (mark "SKIPPED — internal tool") | Required | Required |
| Appendix B — Competency Matrix | Required | Required | Required |
| Appendix C — Trademark Pre-Check | SKIP (mark "SKIPPED — internal tool") | Required | Required |

---

## Human Investment & Timeline

### One-Time Setup

| Activity | Hours |
|---|---|
| Tool accounts, API keys, repository setup | 2-4 |
| Repository security (private repo, branch protection, backup mirroring) | 1-2 |
| AI coding agent installation and configuration | 1-2 |
| CI/CD pipeline template (reusable across projects) | 2-3 |
| Security tooling installation | 1-2 |
| Platform-specific toolchain setup (see Platform Module) | 2-6 |
| **Total** | **9-19 hours** |

### Per-Project Development

| Phase | Human Hours | Calendar Time |
|---|---|---|
| **Phase 0:** Product Discovery | 3-5 | 1-2 days |
| **Phase 1:** Architecture & Planning | 4-8 | 2-4 days |
| **Phase 2:** Construction | 15-40 | 2-6 weeks |
| **Phase 3:** Validation & Hardening | 5-12 | 3-7 days |
| **Phase 4:** Release & Maintenance | 3-8 | 1-3 days |
| **Total (experienced Orchestrator)** | **30-73 hours** | **4-10 weeks** |
| **Total (first project, includes ramp-up)** | **50-110 hours** | **8-14 weeks** |

**Planning note:** Use the upper bounds for planning. The ranges are wider than previous versions because they now span web apps (lower end) through cross-platform desktop apps (upper end). Desktop and embedded applications require more time in Phase 1 (architecture is more consequential), Phase 3 (platform-specific testing), and Phase 4 (build pipeline and distribution complexity).

### Ongoing Maintenance

| Activity | Hours | Frequency |
|---|---|---|
| Health check and error review | 0.5 | Weekly |
| Dependency and security audit | 1-2 | Monthly |
| Feature and performance review | 2-3 | Quarterly |
| Architectural review and upgrade planning | 3-4 | Biannually |
| **Annual total (stabilized)** | **50-80 hours** | **~1-2 hours/week** |

Expect 2-4 hours/week for the first 3 months post-launch. Maintenance is bursty. Per application — at 10 applications, maintenance alone is a half-time job.

---

## Pre-Build Setup (One-Time, All Projects)

### 1. AI Coding Agent

**This framework is developed and tested on Claude Code (Anthropic).** The CLI Setup Addendum, CLAUDE.md configuration, Superpowers plugin, and MCP server integrations are all Claude Code-specific. The init script generates Claude Code project structures.

The underlying methodology (phases, TDD, threat modeling, documentation mandates, security scanning) works with any sufficiently capable AI coding agent. The operational tooling — the automation that makes the autonomous workflow practical — is Claude Code. Switching to a different agent requires retooling the operational layer, not the methodology. See the Governance Framework (Section IX) for a concrete migration estimate.

**Install:**
```bash
# macOS
brew install claude-code

# Windows
winget install Anthropic.ClaudeCode

# Linux / npm fallback (if native install unavailable)
npm install -g @anthropic-ai/claude-code

claude --version
```

See the CLI Setup Addendum (SOI-005-CLI) for complete configuration including permission management, MCP servers, and CLAUDE.md setup.

### 2. Version Control — Git + Repository Host

**Repository requirements (non-negotiable):**
- All repositories must be **private**.
- Options: GitHub Team ($4/user/month), GitLab Self-Managed (free, on-premises), Azure DevOps Repos.

**Configure Git identity:**
```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@company.com"
```

**Configure commit signing (recommended for audit trail):**
```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format=long
git config --global user.signingkey [KEY_ID]
git config --global commit.gpgsign true
```

### 3. Security Tooling

**Semgrep (SAST):**
```bash
brew install semgrep  # macOS
pip install semgrep   # any platform
```

**gitleaks (Secret Detection):**
```bash
brew install gitleaks  # macOS
# Linux: download from https://github.com/gitleaks/gitleaks/releases
```

**Snyk CLI (Dependency Vulnerability Scanning):**
```bash
npm install -g snyk
snyk auth
```

**License compliance tooling:**

> **⟁ PLATFORM MODULE:** License compliance tooling varies by ecosystem. Reference your Platform Module for the appropriate tool (`license-checker` for Node.js, `pip-licenses` for Python, `cargo-license` for Rust, etc.).

### 4. Platform-Specific Toolchain

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific SDK, compiler, packaging tool, and testing framework installation. Complete this before starting any project on that platform.

---

## Phase 0: Product Discovery & Logic Mapping

**Duration:** 1-2 days | **Human Hours:** 3-5 | **Tool:** Claude (chat interface)

**Objective:** Define what the product does, who it serves, and how data flows through it. No technology decisions. No code discussion. If it is not defined in Phase 0, the AI is not permitted to build it in Phase 2.

**Governance checkpoint (organizational deployments):** Before beginning Phase 0, verify that all pre-Phase 0 pre-conditions are recorded in `APPROVAL_LOG.md`. See the Governance Framework Section V.

**Start a new Claude conversation for Phase 0.** Keep all Phase 0 steps in the same conversation. Each step saves its output to `docs/phase-0/` (see individual step instructions), so if a session is interrupted, completed work is preserved on disk.

**Recovery from session loss:** If the conversation is lost mid-Phase 0, start a new session. Provide the agent with any saved intermediate files from `docs/phase-0/` and the Project Intake. Resume from the last incomplete step — do not re-do steps that produced saved output.

### Intake-First vs. Conversational Discovery

**Filling out the Intake:** Run `bash scripts/intake-wizard.sh` for a guided walkthrough — choose between an interactive terminal script (if you know your requirements) or an AI-assisted conversation in Claude Code (if you want help thinking through decisions). The wizard saves progress after each section and offers context-aware suggestions based on your platform and language. See the User Guide Section 3 for details.

**If the Project Intake Template is complete:** Provide the Intake at the start. The agent validates and expands the Intake data rather than discovering it from scratch. Steps 0.5-0.7 are pre-populated and only need review.

**If the Intake is partial or absent:** Use the conversational prompts below. Expect more round-trips.

In either case, the prompts below define what each step must produce. The Intake accelerates the process — it doesn't skip steps.

---

### Step 0.1: Functional Feature Set

**With Intake:** The agent has Sections 2 and 4. Direct it to generate the FRD by expanding the Intake's feature table — adding detail to vague triggers, identifying missing failure states, and flagging contradictions.

**Without Intake — Prompt:**

```
I am the Solo Orchestrator for [PROJECT NAME]. Before we discuss code
or technology, we need to define the Feature Set.

Act as a Lead Product Manager with 15 years of experience. Based on
my goal of [INSERT GOAL], generate a Functional Requirements Document.

CONSTRAINTS:
- Budget: [$ per month for hosting/services, or one-time budget]
- Timeline: [X weeks to MVP]
- Target users at launch: [number]
- Target users at 12 months: [number]

REQUIREMENTS:
1. List the Must-Have features for MVP. For each: "If [condition],
   the system must [action] and output [result]."
2. List the Should-Have features for v1.1.
3. List the Will-Not-Have features (explicit scope boundaries).
4. For every Must-Have, define the failure state.
```

**With Intake — Validation Prompt:**

```
I am the Solo Orchestrator for [PROJECT NAME]. The attached Project
Intake contains my requirements and constraints.

Using the Intake as the primary source, generate a Functional
Requirements Document.

For each Must-Have feature:
1. Expand the business logic trigger into a complete specification.
2. Expand the failure state into a complete error/recovery flow.
3. Identify contradictions between features.
4. Identify implicit dependencies I haven't listed.

For the Will-Not-Have list: flag if any Must-Have implicitly requires
something on the exclusion list.

Do not add features beyond the Intake. Flag recommendations separately.
```

**Review checklist:**
- [ ] Every Must-Have has a logic trigger (If X, then Y)
- [ ] Every Must-Have has a defined failure state
- [ ] No feature described in vague terms
- [ ] Will-Not-Have list has at least 3 items

**Template:** `templates/generated/frd.tmpl`
**Save as:** `docs/phase-0/frd.md`

---

### Step 0.2: User Personas & Interaction Flow

**With Intake:** Agent has Section 2.2. Direct it to expand into a full User Journey Map from the persona definition.

**Without Intake — Prompt:**

```
Map the User Journey for the primary persona.

1. Persona: Who, skill level, goal, emotional state on arrival.
2. Entry Point: How they first encounter the application.
3. Success Path: 3-5 steps. For each: what user sees, does, system responds.
4. Failure Recovery: At each step, what happens on bad input, lost connectivity, or abandonment.
5. Feedback Loops: How the app communicates success/failure/progress. Mechanism specifics.
6. Exit Points: Where the user might abandon. Recovery strategies.
```

**With Intake — Expansion Prompt:**

```
Using the Intake persona (Section 2.2) and Must-Have features (Section 4.1),
generate a complete User Journey Map.

Map the Success Path through ALL Must-Have features as a coherent experience.
For each step: what user sees, does, system responds, feedback mechanism.
Define failure recovery using the failure states from the Intake.
Flag any point where the journey reveals a feature gap.
```

**Review checklist:**
- [ ] Every step has success and failure responses
- [ ] Every action produces visible user feedback
- [ ] At least one exit point and recovery mechanism identified

**Agent persona — Skeptical Product Manager:** When mapping user journeys, the agent adopts the mindset of a skeptical product manager. Start fresh with no assumptions. This is a business application — quality matters more than positivity. Be critical, extremely thorough, and meticulous. Challenge every success path: "What if the user is tired? Distracted? Deliberately adversarial? What happens when they do the unexpected?" Every step is a potential failure point. Every assumption about user behavior is wrong until proven otherwise. Do not assume competence — assume confusion.

**Template:** `templates/generated/user-journey.tmpl`
**Save as:** `docs/phase-0/user-journey.md`

---

### Step 0.3: Data Input/Output & State Logic

**With Intake:** Agent has Section 5. Direct it to synthesize into a formal Data Contract, expanding and validating.

**Without Intake — Prompt:**

```
Define the Data Contract.

1. INPUTS: Data type, validation rules, sensitivity classification per input.
2. TRANSFORMATIONS: Each processing step as a discrete operation.
3. OUTPUTS: Format, latency expectation per output.
4. THIRD-PARTY DATA: APIs/sources, fallback if unavailable, caching.
5. STATE: What persists across sessions vs. ephemeral.
   Define the boundary between "stored permanently" and "stored in
   memory/local session."
```

**With Intake — Validation Prompt:**

```
Using the Intake data definitions (Section 5), generate a formal Data Contract.

Verify validation rules are complete. Confirm sensitivity classifications.
Identify inputs implied by features but not listed. Define data flow from
input to storage to output. Flag integrations where "unavailable" breaks
a Must-Have. Review persistence model against budget constraints.
```

**Review checklist:**
- [ ] Every input has validation rules and sensitivity classification
- [ ] Every third-party dependency has a fallback behavior
- [ ] PII fields identified

**Template:** `templates/generated/data-contract.tmpl`
**Save as:** `docs/phase-0/data-contract.md`

---

### Step 0.4: Product Manifesto & MVP Cutline

**With Intake:** Synthesize the expanded FRD, User Journey, and Data Contract. MVP Cutline reflects Intake Section 4.1, adjusted for validation findings.

**Without Intake — Prompt:**

```
Combine the FRD, User Journeys, and Data Contracts into a Product Manifesto.

1. Product Intent: One paragraph — what and why.
2. MVP Cutline: Hard line. Only first-release features. Everything else
   goes to Post-MVP Backlog.
3. Manifesto Rules:
   - Architecture that contradicts the Manifesto is rejected.
   - Features not in the MVP Cutline are not built in Phase 2.
   - Post-MVP prioritized by user feedback, not this document.

Confirm: "I will use this Manifesto as my primary constraint."
```

**With Intake — Synthesis Prompt:**

```
Synthesize into a Product Manifesto. Use the Intake problem statement
(Section 2.1) as the foundation. MVP Cutline reflects Intake Section 4.1,
adjusted for any changes from Steps 0.1-0.3. If recommending a feature
move (Must-Have → Should-Have or vice versa), state the recommendation
and reason — do not change the cutline without my approval.

Include Open Questions: anything flagged during Steps 0.1-0.3 that
requires my decision before Phase 1.
```

**Template:** `templates/generated/product-manifesto.tmpl` — use this as the structural guide. Populate all sections. Do not alter headings.
**Save as:** `PRODUCT_MANIFESTO.md`

---

### Step 0.5: Revenue Model & Unit Economics (Standard+ Track)

**Track guidance:** Standard and Full tracks must complete this step. Light track projects (internal tools, personal utilities) skip this step — record "SKIPPED — internal tool, no revenue model required" in Manifesto Appendix A.

**With Intake:** Section 7 is complete. Review for consistency with expanded feature set.

**Without Intake:** Define pricing model, per-user costs, break-even, hosting cost ceiling.

**Save as:** Appendix A to `PRODUCT_MANIFESTO.md`

---

### Step 0.6: Orchestrator Competency Matrix

**With Intake:** Section 6.2. Review in context of the emerging architecture — add any domains the Data Contract revealed.

**Without Intake — Self-assessment:** For each domain, answer: "Can I look at the AI's output and reliably determine if it's correct?"

| Domain | Can I Validate? | Benchmark: "Yes" means you can… | If No: Automated Tool |
|---|---|---|---|
| Product/UX Logic | | Identify when a user flow has a dead end or missing error state without being told | Manual review / user testing |
| Frontend/UI Code | | Read a React/Svelte/Flutter component and spot state management bugs, accessibility gaps, or layout regressions | Automated linting |
| Backend / API / Core Logic | | Trace a request from endpoint to database and back, identifying where validation, error handling, or authorization is missing | Automated testing |
| Database / Data Storage | | Evaluate whether a query will perform acceptably at 10x current data volume and whether indexes are appropriate | Query analysis, migration testing |
| Security (Auth, Injection, IDOR) | | Spot an SQL injection, an insecure direct object reference, or a missing authorization check in a code review without tooling hints | SAST, dependency scanning, DAST |
| Build & Packaging | | Debug a failed CI pipeline, configure code signing, and resolve platform-specific build errors independently | CI verification on all target platforms |
| Accessibility | | Identify WCAG violations (contrast, keyboard navigation, screen reader compatibility) by inspecting the UI and markup | Automated accessibility tooling |
| Performance | | Identify N+1 queries, unnecessary re-renders, or memory leaks by reading code, without relying solely on profiling output | Profiling tools, benchmarks |
| Platform-Specific (OS integration, native APIs) | | Debug platform-specific issues (e.g., macOS sandboxing, Android permissions, Windows registry) using platform documentation | Platform-specific testing suites |

#### Enforcement

The competency matrix is not advisory — it drives mandatory tooling:

- For each domain marked **"No"**, the corresponding automated tool listed in the matrix MUST be installed and active in the CI pipeline before Phase 2 begins. The init.sh script installs these tools; verify they are present in `.github/workflows/ci.yml`.
- For each domain marked **"Partially"**, the automated tool is RECOMMENDED but not gating.
- The Phase 1→2 gate reviewer (Senior Technical Authority for organizational projects) MUST verify that CI pipeline includes the mandatory tools for all "No" domains before approving Phase 2 entry.
- If the Orchestrator upgrades a domain from "No" to "Yes" during the project, the automated tooling remains active. Competency improvements do not remove safety nets.

**Save as:** Appendix B to `PRODUCT_MANIFESTO.md` (required for all tracks)

---

### Step 0.7: Trademark & Legal Pre-Check (Standard+ Track)

**Track guidance:** Standard and Full tracks must complete this step. Light track projects skip this step — record "SKIPPED — internal tool, no trademark check required" in Manifesto Appendix C.

1. Trademark search: USPTO, WIPO, app stores, domain registrars.
2. Data privacy applicability: Identify applicable regulations if PII is involved.
3. Distribution channel requirements: App store guidelines, platform-specific legal requirements.
4. Document findings in Appendix C to `PRODUCT_MANIFESTO.md`.

---

### Phase 0 Remediation

| Issue | Detection | Response |
|---|---|---|
| **Feature Creep** | AI suggests features not in the Manifesto. | "Not in the Manifesto. Not in Phase 2. Move to Post-MVP Backlog." |
| **Vague Logic** | AI says "the system handles the data" without specifics. | "Be specific. Input format? Validation? Storage? User feedback on success and failure?" |
| **Missing Failure States** | User journey has no error/recovery path. | "What happens on invalid data at Step [X]? Define the error feedback loop and recovery." |
| **Platform Scope Creep** | AI suggests multi-platform before validating single-platform. | "Ship on one platform first. Add others after the core product works." |

### Phase 0 → Phase 1 Gate

**Organizational deployments:** The Project Sponsor must approve the business justification and compliance screening before proceeding to Phase 1. Record the approval in `APPROVAL_LOG.md` (Phase 0 → Phase 1 section) with the approver's name, date, method, and evidence reference.

**Personal projects:** Review the Phase 0 artifacts yourself and record the self-review in `APPROVAL_LOG.md` before proceeding.

#### Phase 0 Artifact Map

| Step | Output | PRODUCT_MANIFESTO.md Section |
|---|---|---|
| Step 0.1 — Functional Feature Set | `docs/phase-0/frd.md` | Section 2 (Features & Requirements) |
| Step 0.2 — User Personas & Interaction Flow | `docs/phase-0/user-journey.md` | Section 3 (User Journeys) |
| Step 0.3 — Data Input/Output & State Logic | `docs/phase-0/data-contract.md` | Section 4 (Data Contract) |
| Step 0.4 — Product Manifesto & MVP Cutline | `PRODUCT_MANIFESTO.md` | Section 1 (Product Intent), Section 5 (MVP Cutline) |
| Step 0.5 — Revenue Model & Unit Economics | Appendix A to `PRODUCT_MANIFESTO.md` (Standard+; Light: mark SKIPPED) | Section 7 (Revenue Model) |
| Step 0.6 — Orchestrator Competency Matrix | Appendix B to `PRODUCT_MANIFESTO.md` (all tracks) | Section 6 (Competency Matrix) |
| Step 0.7 — Trademark & Legal Pre-Check | Appendix C to `PRODUCT_MANIFESTO.md` (Standard+; Light: mark SKIPPED) | Section 8 (Legal & Compliance) |

#### Gate Enforcement — What `check-phase-gate.sh` Validates

The following items are enforced by `scripts/check-phase-gate.sh` when `current_phase >= 1` in `.claude/phase-state.json`. If any check fails, the gate blocks (exit 1) unless `SOIF_PHASE_GATES=warn` is set.

- [ ] **`APPROVAL_LOG.md` exists.** The gate script fails immediately if `phase-state.json` exists but `APPROVAL_LOG.md` does not. Create `APPROVAL_LOG.md` before (or at the same time as) `phase-state.json` — the `init.sh` script does this automatically.
- [ ] **`phase_0_to_1` date key recorded in `.claude/phase-state.json`.** The gate script checks for this key when `current_phase >= 1`. If the key is missing, the gate issues a warning and increments the failure count.
- [ ] **`APPROVAL_LOG.md` has a dated Phase 0 → Phase 1 entry.** The script searches for a line matching `Phase 0.*Phase 1` and then scans the next 15 lines (`grep -A 15`) for a date in `YYYY-MM-DD` format. The date must appear within 15 lines of the gate header — entries with excessive whitespace or content between the header and the date will fail this check.
- [ ] **`PRODUCT_MANIFESTO.md` exists.**
- [ ] **`PRODUCT_MANIFESTO.md` has substantive content.** The script checks that all 8 numbered sections (`## 1.` through `## 8.`) are present and contain text beyond template placeholders. Missing sections produce a FAIL; placeholder-only sections produce a WARN.
- [ ] **No unresolved Open Questions in `PRODUCT_MANIFESTO.md`.** Any line matching `Status: Open` (case-insensitive) produces a FAIL.
- [ ] **Phase 0 intermediate outputs saved** (advisory). If `docs/phase-0/` exists, the script checks for `frd.md`, `user-journey.md`, and `data-contract.md`. Partial saves produce a WARN, not a block.

**Limitation — Manifesto content depth:** The gate script verifies that `PRODUCT_MANIFESTO.md` exists and has the 8 required section headings with non-empty content. It does not validate that section content matches the track requirements (e.g., Full track requiring revenue model detail, Standard track requiring competency matrix entries). Track-specific content completeness is the reviewer's responsibility.

---

## Phase 1: Architecture & Technical Planning

**Duration:** 2-4 days | **Human Hours:** 4-8 | **Tool:** Claude (chat interface), Context7 MCP (optional)

**Objective:** Select the technology stack, define the data model, identify risks, and produce the Project Bible.

**Start a new Claude conversation for Phase 1.** Attach the completed `PRODUCT_MANIFESTO.md` and the Project Intake (if available).

---

### Step 1.1: Business Strategy Gateway (Standard+ Track — skip for internal tools)

Direct the AI to argue AGAINST building: competitors, existing solutions, Go/No-Go recommendation.

**DECISION GATE — Orchestrator decides Go or No-Go.**

**Save as:** Record the Go/No-Go decision and key competitive factors as an appendix to `PRODUCT_MANIFESTO.md` or in the Project Bible Section 3 (Architecture Decision Record). The decision rationale must be persistent — an auditor should be able to verify this decision was made.

---

### Step 1.1.5: Market Signal Validation (Standard+ Track)

**Performed by the Orchestrator, not the AI.** At least one market signal before committing to architecture. Record the signal type (customer interview, letter of intent, survey result, landing page signups) and outcome in the Product Manifesto appendix or Project Bible. "At least one positive signal" means documented evidence, not a gut feeling.

**DECISION GATE — If no positive signal, return to Phase 0.**

---

### Step 1.2: Architecture & Stack Selection

This is the most consequential technical decision and the most platform-dependent step. The core requirement is the same regardless of platform: propose options, evaluate trade-offs, select one, document the rationale.

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific architecture patterns, framework options, and selection criteria. The module defines what "architecture" means for your platform type.

**Core Architecture Prompt (platform-agnostic constraints):**

```
Based on the attached Product Manifesto, propose 3 architecture options.

CONSTRAINTS:
- Stack familiarity: [from Intake Section 6.1 or state here]
- Budget ceiling: [from Revenue Model or Intake Section 3.2]
- Solo maintainer — prioritize managed services, minimal infrastructure.
- Target MVP timeline: [X weeks].
- Target platforms: [from Intake — e.g., "Windows, macOS, Linux" or
  "Web" or "iOS and Android"]

For EACH option, include ALL of the following as first-class decisions:
1. Languages & Frameworks (exact versions)
2. Data storage strategy (justified by the data contracts)
3. Application architecture pattern
4. Authentication & Identity strategy (if applicable)
5. Observability: structured logging, error reporting. Day 1 decisions.
6. Secrets management
7. Build & packaging strategy for all target platforms
8. Scalability vs. Velocity trade-off
9. Distribution strategy (how users get the application)
10. Auto-update mechanism (if applicable)

[APPEND PLATFORM-SPECIFIC REQUIREMENTS FROM YOUR PLATFORM MODULE]
```

**Input: Competency Matrix.** Attach the Competency Matrix from Step 0.6 (Manifesto Appendix B). For any domain marked "No," the selected architecture must be compatible with the compensating automated tool. Factor tooling overhead and the Orchestrator's skill gaps into the maintainability assessment for each option.

**Select one option.** Document selection and rationale for rejecting others using the ADR template (`templates/generated/adr.tmpl`) with the Options Evaluated and Rejected Alternatives sections.

**DECISION GATE — Orchestrator selects the architecture.**

---

### Step 1.3: Threat Model & Stress Test

Direct the AI to produce a structured threat model and attack the selected architecture:

**Threat Model (STRIDE):**
- **Assets:** What are we protecting? (user data, auth tokens, business logic, API keys, admin access)
- **Threat Actors:** Who attacks this? (unauthenticated external user, authenticated malicious user, compromised dependency, insider with production access)
- **Attack Vectors by STRIDE category:**
  - **Spoofing** — Can an attacker impersonate a user or service?
  - **Tampering** — Can data be modified in transit or at rest?
  - **Repudiation** — Can a user deny actions without audit trail?
  - **Information Disclosure** — Can data leak through errors, logs, or side channels?
  - **Denial of Service** — Can the application be made unavailable?
  - **Elevation of Privilege** — Can a user gain unauthorized access or permissions?
- **Mitigation per vector** — concrete architectural or code-level defense, not "be careful"

**Architecture Stress Test:**
- 5 edge cases where this stack would fail
- 3 security vulnerabilities inherent to this design (stack-specific, not generic)
- 2 data storage bottleneck risks with trigger conditions
- 1 limitation that could force a rewrite in 12 months
- Platform-specific risks (see Platform Module)

**Output:** Threat Model & Risk/Mitigation Matrix. This artifact is referenced during every Phase 2 security audit (Step 2.4) and validated in Phase 3.2.

**Agent persona — Penetration Tester:** For threat modeling, the agent adopts the mindset of a hostile penetration tester. Start fresh — you have never seen this architecture before. This is for a business application. Quality is more important than positivity. Be critical, extremely thorough, and meticulous. Do not produce a checklist of abstract threats — produce concrete attack paths: "I have a leaked credential from a phishing attack. My first move is to test the API for horizontal privilege escalation. If user IDs are sequential, I enumerate until I find admin." For each STRIDE category, describe the specific attack a hostile actor would perform, not the theoretical risk. Every component is a pivot point. Every data flow is an exfiltration route.

**Structural validation checklist** (reviewer applies at Phase 1→2 gate):
- [ ] Every STRIDE category (S/T/R/I/D/E) has at least one threat
- [ ] Every threat references a specific component or data flow in this architecture (not generic OWASP)
- [ ] Every mitigation is a concrete technical control (not "validate input" or "be careful")
- [ ] At least one threat describes a multi-step attack chain
- [ ] Threats use stable IDs (TM-001, TM-002...) for Phase 3 traceability

---

### Step 1.4: Data Model

Direct the AI to generate the data model appropriate for your platform:

> **⟁ PLATFORM MODULE:** Reference your Platform Module for data model specifics. Web apps use database schemas with versioned migrations. Desktop apps may use local databases (SQLite), file-based storage, or in-memory state. The data model format depends on the platform.

Core requirements regardless of platform:
- All entity definitions with relationships
- Data isolation/access control strategy
- Data sensitivity controls per the Phase 0 Data Contract
- Versioned, reversible data model changes where applicable
- Both "create" and "rollback" operations

---

### Step 1.4.5: Data Migration Plan (If Replacing an Existing System)

If the Intake (Section 5) or Phase 0 Data Contract identifies existing data sources that need to be imported (spreadsheets, legacy databases, exported CSVs, manual records), direct the AI to produce a migration plan:

- **Source inventory:** What data exists, where, in what format, and how much.
- **Mapping:** How source fields map to the new data model from Step 1.4.
- **Transformation rules:** Data cleaning, format conversion, deduplication, validation.
- **Import script:** A repeatable script (not manual copy-paste) that can be run against dev data for testing and production data at launch.
- **Rollback:** If the import corrupts the database, how do you revert to a clean state.
- **Validation:** How the Orchestrator confirms the migrated data is correct and complete (record counts, spot checks, checksum comparison).

This step is skipped if the application has no legacy data. If it does, the migration plan is included in the Project Bible and the import script is tested during Phase 2 initialization (Step 2, Item 4: data model setup).

---

### Step 1.5: UI & UX Scaffolding

Direct the AI to define the UI structure for core screens/views:
- Layout structure for the main feature
- The 2 most important component skeletons
- Required states for every interactive component: **Empty, Loading, Error, Success**
- Accessibility baseline: all interactive elements must have text labels or ARIA labels. Never rely on color alone.

> **⟁ PLATFORM MODULE:** Reference your Platform Module for UI framework specifics, platform conventions (native menus, system tray, window management, touch targets), and accessibility tooling.

**Validation checklist:**
- [ ] Layout defined for each core screen/view
- [ ] Component responsibilities are clear (what does each piece own?)
- [ ] All interactive elements have text labels
- [ ] All four states defined for each interactive component (Empty, Loading, Error, Success)
- [ ] Output format is text-based component specifications (Project Bible Section 9), not visual mockups

For non-UI projects (CLI tools, APIs, background services): document the interface specification instead — command structure, input/output formats, error responses. The same four-state pattern applies to any interface component.

**Note on skipped steps:** If any step in Phase 1 is skipped (conditional on track or project type), record "N/A — [reason]" in the corresponding Project Bible section. An auditor must be able to distinguish "was skipped deliberately" from "was forgotten."

---

### Step 1.6: The Project Bible

Synthesize all Phase 1 outputs into `PROJECT_BIBLE.md`:

1. Full Product Manifesto text
2. Revenue Model & Cost Constraints (if applicable)
3. Architecture Decision Record (selected stack, rejected alternatives, rationale)
4. Threat Model & Risk/Mitigation Matrix
5. Data Model (full specification)
6. **Data Migration Plan** (if replacing existing system — from Step 1.4.5)
7. Auth & Identity Strategy (if applicable)
8. Observability & Logging Strategy
9. UI Component Specifications
10. Coding Standards (linting, formatting, naming, "never do this" rules)
11. **Build & Distribution Strategy** (platform-specific build pipeline, packaging, distribution channels)
12. **Test Strategy** — What is tested (unit, integration, E2E, security, accessibility, performance), what tools are used, what constitutes pass/fail for each category, entry/exit criteria for Phase 3, and where test results are stored. This is the project's test plan.

**Bug Severity Classification:**

| Severity | Definition | Examples |
|---|---|---|
| **SEV-1** | Data loss, security breach, app crash on core flow, complete feature failure | Auth bypass, database corruption, crash on login |
| **SEV-2** | Feature broken but workaround exists, significant UX failure | Form submits but wrong data saved, layout broken on one platform |
| **SEV-3** | Minor UX issue, cosmetic, non-core edge case | Alignment off, tooltip truncated, rare edge case |
| **SEV-4** | Enhancement, suggestion, polish | "Would be nice if...", performance optimization |

**UAT Plan** (from Intake Section 11.5):
- Testing interval: Every N features (configured in Intake)
- Human tester count and coordination method
- Bug tracking tool
- Severity SLAs (Full UAT level)

13. **Orchestrator Profile Summary** — Competency gaps and automated tooling to cover them
14. **Accessibility Requirements** — From Intake Section 9
15. **Platform-Specific Requirements** — From your Platform Module
16. **Context Management Plan:**
    - Small projects (<30 files): Full Bible per session
    - Medium projects (30-100 files): Module-level summaries + master index
    - Large projects (>100 files): Condensed Bible Index under 5,000 tokens

**DECISION GATE — Review the complete Bible. This is the point of no return.**

**Organizational deployments:** The Senior Technical Authority must approve the Project Bible before proceeding to Phase 2. Record the approval in `APPROVAL_LOG.md` (Phase 1 → Phase 2 section).

**Personal projects:** Record your self-review in `APPROVAL_LOG.md` before proceeding. **Known risk:** Self-review at this gate means the person least likely to catch their own architectural blind spots is the sole reviewer. For Standard+ track personal projects, consider seeking an external architecture review — a peer, mentor, or a separate Claude session using the adversarial evaluation prompt (`evaluation-prompts/Projects/bases/01-senior-engineer.md`). If this project is later upgraded to organizational deployment via `upgrade-project.sh`, the Senior Technical Authority will be required to retroactively review and approve the Project Bible.

#### Gate Enforcement — What `check-phase-gate.sh` Validates (Phase 1→2)

When `current_phase >= 2` in `.claude/phase-state.json`:

- [ ] **`phase_1_to_2` date key recorded in `.claude/phase-state.json`.** Missing key produces a WARN.
- [ ] **`APPROVAL_LOG.md` has a dated Phase 1 → Phase 2 entry.** Same 15-line proximity rule as Phase 0→1: the date must appear within 15 lines of the `Phase 1.*Phase 2` header.
- [ ] **`PROJECT_BIBLE.md` exists.**
- [ ] **`PROJECT_BIBLE.md` has at least 14 numbered sections** (template specifies 16; minimum 14 to pass).
- [ ] **No placeholder dates in `PROJECT_BIBLE.md`.** Any remaining `YYYY-MM-DD` strings produce a WARN.

**Save as:** `PROJECT_BIBLE.md`

---

### Phase 1 Remediation

| Issue | Detection | Response |
|---|---|---|
| **Over-Engineering** | AI suggests complex infrastructure for an MVP. | "Solo maintainer with a $[X] ceiling. Simplify." |
| **Platform Mismatch** | Architecture doesn't match target platform constraints. | "This must run as [platform requirement]. Redesign for that constraint." |
| **Security Gaps** | AI omits auth, data isolation, or encryption. | "Missing [control]. Rewrite. Non-negotiable." |
| **Shallow Threat Model** | STRIDE analysis is generic (lists OWASP without stack-specific vectors). | "These threats must be specific to our architecture. How does [vector] apply to [our stack]? What is the concrete attack path?" |
| **Missing Observability** | No logging, error tracking, or monitoring. | "Observability is Day 1. Define logging, correlation IDs, error reporting now." |
| **Missing Build Strategy** | No plan for packaging/distributing on all target platforms. | "How does this get to the user on [platform]? Define the build and distribution pipeline." |
| **Maintenance Overload** | Architecture requires DevOps the Orchestrator can't maintain. | "Simplify. I cannot maintain this." |

---

## Phase 2: Construction (The "Loom" Method)

**Duration:** 2-6 weeks | **Human Hours:** 15-40 | **Tools:** AI coding agent, Git, testing framework, security tooling

**Objective:** Build feature-by-feature using test-driven development.

The primary risk is **Code Drift** — AI generates code that deviates from the Bible. The secondary risk is **Context Window Bleed** — AI loses track of prior decisions as the codebase grows.

### Execution Engine: Superpowers

If the Superpowers plugin is installed (see CLI Setup Addendum, Section 1), it serves as the Phase 2 workflow accelerator. Superpowers' skills — `test-driven-development`, `subagent-driven-development`, `writing-plans`, `systematic-debugging`, `using-git-worktrees` — activate automatically during construction. The Build Loop below defines what must happen per feature; Superpowers provides the agent's methodology for how to execute each step.

**With Superpowers:** The agent will use subagent-driven development (spawning focused subagents per task with two-stage review), follow strict TDD discipline (RED-GREEN-REFACTOR, test before code), and manage feature branches via git worktrees. The Orchestrator's role shifts from directing each step to reviewing at decision gates and validating the agent's self-review output. Note: Superpowers is a workflow accelerator that strongly encourages best practices — it is not an independently verifiable enterprise compliance control. The Orchestrator's review at decision gates and the CI/CD pipeline remain the actual quality gates.

**Without Superpowers:** The Build Loop below works as written — the agent executes sequentially with the Orchestrator directing each step. Superpowers is recommended but not required.

### Using a Different AI Coding Agent

The Builder's Guide methodology (phases, decision gates, Build Loop, test-first) works with any AI coding agent that can read files, write code, and run commands. Superpowers and the CLI Setup Addendum are optimized for Claude Code but are not required. If using a different agent:

- The Build Loop (Steps 2.2-2.6) applies as written — direct the agent through each step.
- Replace Superpowers-specific references with your agent's equivalent capabilities (if any).
- The CLAUDE.md template should be adapted to your agent's instruction format.
- Security tooling (Semgrep, gitleaks, Snyk) is agent-independent and works the same way.

---

### Project Initialization

**Polyglot and monorepo projects:** The init script generates a CI pipeline for one primary language. If your project uses multiple languages (e.g., TypeScript frontend + Python backend), add CI steps for secondary languages to `.github/workflows/ci.yml` during this initialization phase. For monorepo structures (multiple packages or services in one repository), configure path-scoped CI triggers so the full pipeline does not run on every change to every package. The Build Loop applies independently to each service or package.

**1. Create the repository:**
```bash
mkdir [project-name] && cd [project-name]
git init
git remote add origin https://github.com/[org]/[repo].git
```

**2. Configure branch protection** (required before Phase 2):

```bash
# Using GitHub CLI — run from the project directory after pushing the initial commit:
gh api repos/{owner}/{repo}/branches/main/protection \
  --method PUT \
  --field "required_pull_request_reviews[required_approving_review_count]=0" \
  --field "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  --field "required_status_checks[strict]=true" \
  --field "required_status_checks[contexts][]=test" \
  --field "enforce_admins=true" \
  --field "restrictions=null" \
  --field "allow_force_pushes=false" \
  --field "allow_deletions=false"
```

This enforces: PRs required for all changes to `main`, status checks must pass, force pushes disabled, and rules apply to admins (you). Replace `{owner}/{repo}` with your GitHub org/repo path. Adjust `contexts` to match your CI job names.

If you cannot use the GitHub CLI, configure these settings manually: Settings → Branches → Add rule → Branch name pattern: `main` → check "Require a pull request before merging", "Require status checks to pass before merging", uncheck "Allow force pushes."

**3. Initialize the project with the AI agent:**

Provide the Project Bible and direct the agent to:
- Initialize using the selected stack (latest stable/LTS versions)
- **Pin all dependencies to exact versions.** Commit the lockfile.
- Generate the folder structure per the Bible
- Configure linting, formatting, and the test runner
- Configure structured logging (timestamp, severity, correlation ID from Day 1)
- Generate `CONTRIBUTING.md` with coding standards

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific initialization: project scaffolding commands, build tool configuration, platform SDK setup, cross-compilation configuration.

**4. Configure data model:**
- Apply the initial data model from Phase 1
- Verify rollback/revert works
- **Test backup and restore now** — don't wait until Phase 4

**5. Install pre-commit hooks:**

Use a hook manager (husky, pre-commit framework, or equivalent for your ecosystem):
```bash
# Example: gitleaks pre-commit
echo 'gitleaks protect --staged --verbose' > .husky/pre-commit
```

**6. Configure CI/CD pipeline:**

Direct the agent to generate the CI configuration:
- Linting
- Full test suite
- SAST scan (Semgrep)
- Dependency vulnerability audit
- License compliance check
- Lockfile integrity verification

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific CI steps: cross-platform build matrix, code signing, packaging verification, platform-specific test runners.

**7. Verify before building the first feature:**
- [ ] Linter runs clean
- [ ] Test runner executes (0 tests, 0 failures)
- [ ] Initial data model applies successfully
- [ ] Pre-commit hook catches a test secret (gitleaks detects a hardcoded test value)
- [ ] Pre-commit hook runs Semgrep (verify SAST scanning is active)
- [ ] License checker runs clean
- [ ] CI pipeline passes on first push
- [ ] Backup/restore verified
- [ ] Application builds and runs on at least one target platform

---

### The Build Loop

**For each feature in the MVP Cutline, execute this cycle. Start with the highest-risk or most foundational feature (often authentication or core data handling).**

#### Step 2.2 — Write Tests First

Direct the agent to write test cases based on the User Journey and Data Contract:
- Success state tests (descriptive names: "should [behavior] when [condition]")
- Negative tests (invalid, empty, malicious input)
- Boundary tests (exact limits of acceptable input)

**DECISION GATE — Review the test assertions.** Write at least 3 test assertions yourself per feature that specifically test business logic — not just status codes or "response is not null."

Confirm the tests fail (feature code doesn't exist yet).

**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:tests_written`
After verifying tests fail: `scripts/process-checklist.sh --complete-step build_loop:tests_verified_failing`

**Agent persona — QA Test Engineer:** When writing tests, the agent adopts the mindset of a senior QA engineer who has never seen the code. Start fresh with no context about the implementation. This is a business application — quality is more important than positivity. Be critical, extremely thorough, and meticulous. Write tests to catch bugs, not to confirm the code works. You have seen 1,000 bugs in your career — you know where they hide: off-by-one errors, null handling, race conditions, auth bypass, state corruption on retry, Unicode edge cases, empty collections, maximum-length inputs. Test the boundaries, not the center. Write at least one test that you expect the developer to push back on as "too paranoid."

#### Step 2.3 — Implement the Feature

1. Direct the agent to implement to pass all tests.
2. Run the test suite. All tests must pass.
3. Manual validation: verify the feature works as expected.
4. Direct specific fixes for any discrepancies.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:implemented`

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific manual validation steps (e.g., testing on each target OS, verifying native integration, checking platform-specific behavior).

#### Step 2.4 — Security & Quality Audit

1. Run SAST:
   ```bash
   semgrep scan --config=p/owasp-top-ten --config=p/security-audit src/
   ```

**Parallel execution (if Superpowers available):** Dispatch these as parallel subagents — they have no cross-dependencies:
1. **SAST agent:** Runs `semgrep scan --config=p/owasp-top-ten --config=p/security-audit src/`
2. **Threat model agent:** Reviews implementation against Phase 1.3 Threat Model
3. **Data isolation agent:** Tests whether one user/context can access another's data
4. **Input validation agent:** Tests all entry points with injection payloads
5. **Logging agent:** Verifies structured logging for significant operations

Consolidate findings from all agents before remediation. Without Superpowers, run sequentially.

2. Review against the Phase 1.3 Threat Model & Risk/Mitigation Matrix.
3. Check specifically for:
   - [ ] Data isolation: Can one user/context access another's data?
   - [ ] Input validation: Handled at all entry points?
   - [ ] Hardcoded secrets: Anything that should be in configuration?
   - [ ] Efficient data access: No N+1 or equivalent performance issues?
   - [ ] Logging: Significant operations producing structured log entries?
   - [ ] Platform-specific security: See Platform Module
4. Fix findings. Verify tests still pass.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:security_audit`

**AI-specific caution areas:** AI-generated code is disproportionately likely to have subtle issues in: complex state management (race conditions), data access efficiency, authentication edge cases, and content security configuration. Apply extra scrutiny in these areas.

**Concrete mitigations for AI-generated code risks:**
- For authentication and access control: write explicit negative tests that attempt unauthorized access (horizontal privilege escalation, role bypass, token reuse). Do not rely on the AI to identify its own auth bugs.
- For state management and race conditions: if the application has concurrent operations, write tests that simulate concurrent access. Use your platform's concurrency testing tools.
- For data access efficiency: run query analysis (EXPLAIN or equivalent) on every database query the AI generates that touches user data. N+1 queries are the most common AI-generated performance defect.
- For input validation: test every user-facing input with injection payloads (SQLi, XSS, command injection) appropriate to your stack. Do not assume the AI's validation is complete.

**Agent persona — Senior Security Engineer:** For security audits, the agent adopts the mindset of a senior security engineer reviewing code for production deployment. Start fresh — you have no context about this codebase. This is a business application. Quality is more important than positivity. Be critical, extremely thorough, and meticulous. Do not check boxes — hunt for vulnerabilities. "Can user A read user B's data by manipulating the request? Can I bypass auth with a race condition? Is this SQL query injectable? What happens if the logger crashes — does it leak secrets in the error output? What if memory is exhausted during file upload?" Every finding must describe the concrete exploit, not just the missing control.

#### When CI Fails on Security Checks

When a CI security check blocks the build, follow this escalation:

1. **Investigate the finding.** Read the error output. Determine if it is a genuine vulnerability, a false positive, or a configuration issue.
2. **Genuine vulnerability:** Fix the code or update the dependency. Re-push. Do not bypass.
3. **False positive:** Suppress at the line level with documentation (see Phase 3: Handling False Positives). Re-push.
4. **Dependency vulnerability with no fix available:** Check if a patched version exists. If not, evaluate whether the vulnerable code path is reachable in your application. Document the risk and create a tracking issue. For organizational projects, get IT Security approval to proceed.
5. **License violation:** Do not override. Find an alternative dependency with a compatible license. If no alternative exists, escalate to Legal (organizational) or evaluate the license terms carefully (personal).

**Never** commit directly to main, disable CI, or use `--no-verify` to bypass security checks. If you are blocked and unsure how to proceed, ask for a security peer review.

#### Step 2.5 — Update Documentation

Direct the agent to produce:

**Parallel execution:** CHANGELOG, interface documentation, and ADRs are independent text-generation tasks. Dispatch as parallel subagents from the same codebase snapshot, then merge results into the Bible update.

- **CHANGELOG.md:** Use [Keep a Changelog](https://keepachangelog.com/) format with 8 categories ordered by impact: Security, Data Model, Added, Changed, Fixed, Removed, Infrastructure, Documentation. See `templates/generated/changelog.tmpl` for category definitions.
- **FEATURES.md:** Add a new section for each completed feature using the template structure: summary, key interfaces, related ADRs, test coverage, known limitations. See `templates/generated/features.tmpl`.
- **Interface Documentation:** Every new API endpoint, command, or user-facing interface with contracts and error codes. Store in `docs/api and interfaces/`. Format is platform-dependent — see your Platform Module.
- **Architecture/UX Decision Record:** For non-trivial decisions, create a numbered ADR in `docs/ADR documentation/` using the standard template (Status, Context, Decision, Consequences). See `templates/generated/adr.tmpl`. Number sequentially: `0001-title.md`, `0002-title.md`, etc.
- **Project Bible Update:** New interfaces, data model changes, new configuration, new dependencies. Update the `<!-- Last Updated: YYYY-MM-DD -->` marker on every modified section. Verify cross-section consistency after every update.

Verify the Bible still accurately reflects the codebase. Commit and merge.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:documentation_updated`
After recording the feature with `test-gate.sh --record-feature`: `scripts/process-checklist.sh --complete-step build_loop:feature_recorded`

#### Step 2.6 — Data Model Changes (if needed)

1. Generate a versioned change with "apply" and "rollback" operations.
2. Apply the change. Verify existing tests pass.
3. Verify rollback cleanly reverts. **Test against realistic data, not empty state.**
4. Update data model documentation in the Bible.

**NEVER modify the data model directly.** All changes go through the versioning tool.

#### Step 2.7 — UAT Testing Session

**Process checkpoint:** Start the UAT session: `scripts/process-checklist.sh --start-uat N`

**Before starting the next feature, check the test gate:**
```bash
scripts/test-gate.sh --check-batch
```

If the gate blocks (testing interval reached), execute a UAT session:

1. **Agent dispatches parallel test subagents** (via `superpowers:dispatching-parallel-agents` if available, sequential otherwise):
   - **Automated Suite agent:** Runs full test suite (unit + integration + E2E). Reports failures with stack traces.
   - **Exploratory agent persona — Malicious User:** This agent adopts the mindset of a user deliberately trying to damage the system or steal data. Start fresh with no knowledge of the implementation. This is a business application — quality is more important than positivity. Be critical, extremely thorough, and meticulous. Reads the Threat Model (Phase 1.3) and User Journey (Phase 0). Attack systematically: submit 10MB inputs in text fields, drop the network mid-save, use Unicode that breaks rendering, click buttons in rapid succession, open multiple tabs with the same session, disable JavaScript and resubmit forms, paste SQL injection payloads in every input, try to access other users' data by guessing URLs. Document every scenario where the app does not gracefully handle abuse.
   - **Cross-Platform agent** (if applicable): Runs core flows on each target platform.

2. **Agent generates a test template** pre-populated with the current batch's features and User Journey scenarios. Places it in `tests/uat/sessions/<date>-session-N/templates/`.

3. **Agent tells the Orchestrator:** "Testing session started. Your test template is at `<path>`. Complete it and drop results in `submissions/`. Let me know when done."

4. **Agent waits.** Does not proceed, does not poll.

5. **When the Orchestrator says "results are in"**, the agent:
   - Checks each submission against the template for completeness
   - If scenarios are incomplete, lists which tests were skipped (and by which tester if multiple)
   - Asks: "Continue with partial results, or finish testing?"

Agent results go to `tests/uat/sessions/<date>-session-N/agent-results/`. Human submissions go to `submissions/`.

**Note on commits during UAT:** The process enforcement system blocks source commits while a UAT session is in progress (all 9 steps must complete). Bug fix code is written and tested during the remediation step but staged for commit after the full UAT cycle completes. If the session is long, use `git stash` to preserve work-in-progress. Documentation-only commits (.md, .json, .yml) are always allowed.

**After each feature (regardless of testing interval):**
```bash
scripts/test-gate.sh --record-feature "feature-name"
```

#### Step 2.8 — Bug Triage

1. Agent consolidates all results (agent test results + human submissions) into the configured bug tracker.
2. Agent proposes severity for each bug (SEV-1/2/3/4 per Phase 1 classification).
3. Orchestrator reviews and adjusts severities.
4. Orchestrator assigns disposition per bug:

| Disposition | Meaning |
|---|---|
| **Fix Now** | Agent fixes in this remediation cycle |
| **Defer** | Tracked with justification. Must be resolved or feature removed at Phase 2→3 gate. SEV-1 cannot be deferred. |
| **Won't Fix** | Accepted as-is with documented rationale (SEV-3/4 only) |
| **Post-MVP** | Moved to Post-MVP backlog (SEV-4 enhancements) |

#### Step 2.9 — Remediation Loop

1. Agent fixes all "Fix Now" bugs using Build Loop discipline (write failing test for the bug → implement fix → verify test passes).

**Parallel bug fixing:** When multiple bugs affect different components, dispatch parallel fix agents — one per component. Each agent: writes failing test → implements fix → verifies test passes. After all agents complete, merge fixes and run the full test suite to check for regressions. If bugs affect the same component, fix sequentially to avoid conflicts.

2. Agent re-dispatches parallel test agents. Orchestrator re-tests their specific reported bugs.
3. Gate check:
```bash
scripts/test-gate.sh --check-batch
```
   - **Pass** → reset counter, proceed to next feature batch
   - **Block** → loop back to Step 2.8

After the session completes:
```bash
scripts/test-gate.sh --reset-counter
```

Mark each UAT step as you complete it: `scripts/process-checklist.sh --complete-step uat_session:STEP_ID`
Steps in order: `agents_dispatched`, `template_generated`, `orchestrator_notified`, `results_received`, `completeness_verified`, `bugs_consolidated`, `triage_complete`, `remediation_complete`, `gate_passed`.

---

### Context Health Check (Every 3-4 Features)

Ask the agent to summarize: features built, features remaining, current data model, known issues. If the summary contains hallucinated features, incorrect references, or contradicts the Bible:
1. Start a fresh session.
2. Provide the updated `PROJECT_BIBLE.md` and the last 3-4 active files.
3. "We are continuing Phase 2. Here is the current state."

If the AI produces consistently low-quality output across multiple attempts, end the session and start fresh. Quality variance between sessions is real.

---

### Mid-Phase 2 Governance Checkpoint (Organizational Deployments)

**For organizational deployments only** (personal projects skip this):

Phase 2 is the longest phase (2-6 weeks) and the one with the least external oversight. To close this governance gap, conduct a **biweekly status review** with the Senior Technical Authority (or designated reviewer) during Construction:

**Every 2 weeks during Phase 2:**
1. The Orchestrator presents: features completed, features remaining, any architecture deviations from the Project Bible, and current test pass rate.
2. The reviewer confirms the project is tracking to the Bible and the decision log does not contain unresolved concerns.
3. The review is brief (30 minutes maximum) — this is a status check, not a gate.
4. Record the review date and outcome in the in-phase decision log.

**Escalation triggers during review:**
- Architecture deviation from the Project Bible that was not captured as an ADR
- Test pass rate below 80%
- Security findings from per-feature audits that remain unresolved for more than one review cycle
- Orchestrator reports that AI output quality has degraded significantly

If any trigger fires, the reviewer and Orchestrator determine whether to pause construction, revise the Bible, or escalate to the Application Owner.

This checkpoint does not replace the Phase 2→3 gate — it provides early visibility into construction progress for the governance chain.

---

### Phase 2 Completion Checkpoint

Before moving to Phase 3:
- [ ] All MVP Cutline features built and passing tests
- [ ] No partially implemented features
- [ ] Full test suite passes
- [ ] CI pipeline green
- [ ] Project Bible accurately reflects current codebase
- [ ] CHANGELOG.md current
- [ ] No unresolved security findings
- [ ] Application builds on all target platforms
- [ ] All UAT testing sessions completed for all feature batches
- [ ] No open SEV-1 or SEV-2 bugs (deferred SEV-2 must be resolved or feature removed)
- [ ] Bug triage complete — all bugs have a disposition
- [ ] **MVP Cutline reconciliation:** Compare `FEATURES.md` against the Product Manifesto MVP Cutline. Record any scope additions and their approval rationale. Features built that are not in the Cutline must have documented Orchestrator approval.

**Bug Gate Check:**
```bash
scripts/test-gate.sh --check-phase-gate
```
- SEV-1 open → **BLOCKED** (must resolve)
- SEV-2 open or deferred → **BLOCKED** (must resolve or remove/hide the feature — no third option)
- SEV-3 open → **WARNING** (Orchestrator attests disposition)
- SEV-4 → No impact

#### Gate Enforcement — What `check-phase-gate.sh` Validates (Phase 2→3)

When `current_phase >= 3` in `.claude/phase-state.json`:

- [ ] **`phase_2_to_3` date key recorded in `.claude/phase-state.json`.** Missing key produces a WARN.
- [ ] **`APPROVAL_LOG.md` has a dated Phase 2 → Phase 3 entry.** Same 15-line proximity rule: the date must appear within 15 lines of the `Phase 2.*Phase 3` header.
- [ ] **`FEATURES.md` exists.**
- [ ] **`CHANGELOG.md` exists.**
- [ ] **Bug gate passes** (`scripts/test-gate.sh --check-phase-gate`).

---

### Phase 2 Remediation

| Issue | Detection | Response |
|---|---|---|
| **Context Window Bleed** | AI hallucinates variables, forgets structure. | Fresh session with Bible + last 3-4 active files. |
| **Dependency Creep** | New package for every small problem. | "Achieve this with the existing stack. Justify any new dependency." |
| **Logic Circularity** | AI rewrites the same bug in circles. | "Stop coding. Explain the logic step-by-step. Find the flaw before fixing syntax." |
| **Silent Failures** | Code runs but errors are swallowed. | "Every failure must produce a structured log entry and user-visible feedback." |
| **Regression** | Feature B breaks Feature A. | "Run full suite. Identify conflict. Fix preserving both. Do not delete tests." |
| **Data Model Modified Directly** | Schema/structure changed outside versioning tool. | "Revert. Generate a versioned change. Apply through the tool." |
| **Architecture Wrong Mid-Build** | Construction reveals architecture can't support a requirement. | Stop Phase 2. Return to Phase 1.2. Revise Bible. Expensive but cheaper than finishing wrong. |
| **Platform Inconsistency** | Works on one OS but not another. | "Run tests on all target platforms. Fix platform-specific issues before continuing." |

---

## Phase 3: Validation, Security & UAT

**Duration:** 3-7 days | **Human Hours:** 5-12 | **Tools:** See Platform Module for testing tools, plus Semgrep, Snyk, gitleaks

**Objective:** Assume everything is broken. Prove otherwise.

**Process checkpoint:** Start Phase 3 validation: `scripts/process-checklist.sh --start-phase3`

**Track-agnostic enforcement:** The process checklist enforces identical step sequences for all tracks (Light, Standard, Full). There is no mechanism to skip checklist steps based on track selection. Track differentiation in Phase 3 applies to the **depth and rigor** of each step, not the step count. For example, Light track completes the integration testing step with integration tests and a manual smoke test (no formal UAT), while Standard and Full tracks require formal UAT sessions. The checklist step is the same; the effort behind it varies. See the Track Requirements Matrix in Process Right-Sizing for the full breakdown.

---

**Phase 3 Parallel Execution:** Steps 3.1 through 3.5 are independent validation tasks with no cross-dependencies. For maximum efficiency, dispatch all as parallel subagents:

| Agent | Step | Task |
|---|---|---|
| Integration | 3.1 | E2E test suite |
| Security | 3.2 | SAST, dependency scan, secret scan, license check, threat model validation |
| Chaos | 3.3 | Edge-case and error recovery testing |
| Accessibility | 3.4 | UX and accessibility audit |
| Performance | 3.5 | Startup, latency, memory, bundle optimization |
| Contract | 3.5.5 | Contract testing (Standard+ Track) |

Consolidate all findings into a single remediation list. Fix critical findings first, re-run affected test suites. Without Superpowers, run sequentially in the order listed.

### Step 3.1: Integration Testing

> **⟁ PLATFORM MODULE:** Reference your Platform Module for the appropriate integration/E2E testing framework and approach. Web apps use Playwright. Desktop apps use platform-specific UI automation. The tool varies; the requirement doesn't — automate the full user journey.

1. Install the testing framework per your Platform Module.
2. Direct the agent to write an E2E/integration test suite automating the entire User Journey.
3. Run it. Fix failures — these are integration gaps.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:integration_testing`

---

### Step 3.2: Security Hardening

**Run all automated scans first, then provide results to the agent for review.**

1. Full SAST scan:
   ```bash
   semgrep scan --config=p/owasp-top-ten --config=p/security-audit --severity ERROR --severity WARNING .
   ```
2. Dependency vulnerability scan:
   ```bash
   snyk test  # or equivalent for your ecosystem
   ```
3. Full repository secret scan:
   ```bash
   gitleaks detect --source . --verbose
   ```
4. License compliance (using your ecosystem's tool)
5. Direct the agent to: fix all critical/high findings, verify data isolation on every interface, verify input validation at every entry point, write regression tests for every fix.
6. Re-run all scans to confirm resolution.
7. **DAST scan (web applications):** Run OWASP ZAP baseline scan against the deployed staging environment. Full Track: run active scan. Save results to `docs/test-results/[date]_zap_[pass|fail].[ext]`. Reference your Platform Module for DAST configuration. (Non-web platforms: skip this step.)
8. **SBOM generation** (using your ecosystem's tool — CycloneDX, syft, or equivalent). Save to project root as `sbom.json` (current SBOM) and archive a dated copy to `docs/test-results/[date]_sbom.json` (Phase 3 snapshot). The root copy is the living document updated during monthly maintenance; the archived copy is the Phase 3 audit evidence.
9. **Threat Model Validation:** Review the Phase 1.3 Threat Model. For every identified threat vector, verify: the mitigation was implemented, it works as designed, or the risk was explicitly accepted with documented rationale. Any threat vector without a verified mitigation or documented acceptance is a finding that must be resolved before go-live.

**Agent persona — Security Architect / Auditor:** For threat model validation, the agent adopts the mindset of an external security auditor. Start fresh — you have no prior relationship with this project. This is a business application. Quality is more important than positivity. Be critical, extremely thorough, and meticulous. For every threat vector from Phase 1.3: (1) locate where the mitigation code lives, (2) review it line by line, (3) test it with realistic attack payloads, (4) confirm it fails safely. Do not sign off on a mitigation you have not tested. "The threat model says we encrypt data at rest — show me the encryption, show me the key management, show me what happens if the key is lost."

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific security checks: code signing verification, sandboxing/permissions model, platform-specific attack vectors, DAST approach (if applicable).

**Quality gate:** Zero critical or high-severity findings before proceeding.

#### Handling False Positives

SAST tools produce false positives. Silencing them without documentation creates unscanned attack surface. Follow this process:

1. **Investigate first.** Confirm the finding is genuinely a false positive, not a vulnerability you do not understand.
2. **Inline suppression.** Use the tool's suppression comment (e.g., `# nosemgrep: rule-id`) with a brief justification on the same line.
3. **Document.** Record the rule ID, file, and reason in the Phase 3 security audit notes.
4. **Organizational: approval required.** For findings rated High or Critical, suppression requires written approval from the security peer reviewer or IT Security.
5. **Re-validate.** Suppressed findings MUST be re-evaluated during the biannual security audit. Code changes may make a previously-false positive genuine.

Never disable an entire SAST rule category to silence a single false positive. Suppress at the line level only.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:security_hardening`

---

### Step 3.3: Chaos & Edge-Case Testing

Direct the agent to implement:
- **Input abuse defenses:** Validation at all entry points, Unicode/null byte handling, size limits
- **Error recovery:** Graceful handling of missing resources, corrupt data, unexpected state
- **Resource limits:** Memory, disk, network constraints appropriate to the platform
- **Concurrency protection:** If applicable — debouncing, idempotency, mutex/locking
- **Global error boundaries:** Catch unhandled errors, display user-friendly recovery

Run the full test suite. Nothing should break.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:chaos_testing`

---

### Step 3.4: UX & Accessibility Audit

> **⟁ PLATFORM MODULE:** Reference your Platform Module for the appropriate accessibility testing tools and standards. Web uses Lighthouse. Desktop and mobile use platform-specific accessibility APIs and testing tools.

Core requirements regardless of platform:
- All interactive elements have text labels
- Never rely on color alone for meaning
- Keyboard/alternative input navigation works for core flows
- Screen reader compatibility for primary user journey (Full Track requires explicit testing; all tracks must meet WCAG AA, which includes programmatic screen reader support)

**Agent persona — Users with Disabilities:** For accessibility testing, the agent adopts multiple disability personas in sequence. Start fresh for each. This is a business application — quality is more important than positivity. Be critical, extremely thorough, and meticulous.
- **Screen reader user:** "I cannot see the screen. Read me every button label, every form field, every error message. Can I complete the core flow hearing only what the screen reader announces? Are dynamic updates announced?"
- **Keyboard-only user:** "I cannot use a mouse. Can I reach every interactive element with Tab? Can I activate every button with Enter/Space? Is focus visible at all times? Can I escape modal dialogs?"
- **Color-blind user:** "Red and green look the same to me. Does any UI element use color alone to communicate state? Are errors, warnings, and success indicated with text/icons in addition to color?"
Identify every interaction that fails these tests. Report as "A screen reader user cannot [specific failure]" — not "Missing aria-label."

**Pass/fail criteria:**
- **Quantitative (web):** Lighthouse accessibility score ≥ 90. Save the HTML report to `docs/test-results/[date]_lighthouse_[pass|fail].html`.
- **Qualitative (all platforms):** Persona failures that prevent completing the core flow are SEV-1 (must fix). Persona failures that degrade but don't block are SEV-3 (fix or accept with rationale).
- **Minimum bar:** WCAG AA compliance for all platforms. Full Track requires explicit screen reader testing.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:accessibility_audit`

---

### Step 3.5: Performance Audit

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific performance testing: startup time, memory usage, rendering performance, bundle/binary size optimization.

Core requirements:
- Application starts within acceptable time for the platform
- Core operations complete within the latency expectations from the Data Contract
- Memory usage is stable (no leaks during extended use)
- Performance is acceptable on the minimum supported hardware/OS version

**Agent persona — Power-Constrained Device User:** For performance testing, the agent adopts the mindset of a user on underpowered hardware. Start fresh with no knowledge of the tech stack. This is a business application — quality is more important than positivity. Be critical, extremely thorough, and meticulous. "I'm on a 3-year-old phone with 2GB RAM, or a Chromebook with a slow CPU, or on a flaky 2G connection. Does the app load? Does it stutter when I scroll? Does it drain my battery in an hour? Can I use it at all on slow networks?" Test: startup time on minimum hardware, first interaction latency, memory usage over 10 minutes of active use, behavior on throttled network (2G/3G), offline fallback behavior.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:performance_audit`

---

### Step 3.5.5: Contract Testing (Standard+ Track)

For applications with interfaces consumed by other systems (APIs, IPC, file formats):
- Document expected contracts
- Write tests verifying actual behavior matches documented contracts
- Schema validation tests for data formats

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:contract_testing`

---

### Step 3.5.7: Load/Stress Testing (Full Track — if applicable)

> **⟁ PLATFORM MODULE:** Reference your Platform Module for appropriate load testing.

**Guidelines by platform:**
- **Web apps:** Use k6, Artillery, or equivalent. Test concurrent users at expected peak load. Measure: P95 response time, error rate under load, throughput. Pass criteria: P95 response < 2x baseline, error rate < 1% at expected load.
- **Desktop apps:** Test large file handling (10x expected size), many simultaneous documents, extended operation (1hr+ memory stability). Measure: memory usage over time, UI responsiveness under load.
- **Mobile apps:** Test on minimum supported hardware. Measure: startup time, battery impact, memory usage. Pass criteria per Platform Module.

Save results to `docs/test-results/[date]_load-test_[pass|fail].[ext]` (k6 JSON summary, HTML report, or equivalent).

---

### Step 3.5.9: Test Results Archive

All Phase 3 test results must be saved as dated artifacts — CI logs expire, but audit evidence must persist.

Direct the agent to create `docs/test-results/` and save:
- **E2E test results** (Playwright/equivalent report from Step 3.1)
- **SAST scan results** (Semgrep JSON/SARIF output from Step 3.2)
- **DAST scan results** (ZAP/equivalent report from Step 3.2, if applicable)
- **Dependency scan results** (Snyk/equivalent output from Step 3.2)
- **Secret scan results** (gitleaks output from Step 3.2)
- **SBOM** (CycloneDX/equivalent from Step 3.2)
- **Threat model validation** (pass/fail per vector with remediation notes, from Step 3.2)
- **Accessibility/performance audit** (Lighthouse HTML report or equivalent, from Step 3.4)
- **Load test results** (if applicable, from Step 3.5.7)
- **Contract test results** (if applicable, from Step 3.5.5)

File naming convention: `[date]_[scan-type]_[pass|fail].[ext]` (e.g., `2026-04-02_semgrep_pass.json`).

These artifacts serve as the audit evidence for Phase 3 completion. They are referenced in `APPROVAL_LOG.md` (Phase 3 → Phase 4 section) and included in the HANDOFF.md. Update the Approval Log with the go-live approval(s) before proceeding to Phase 4 deployment.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase3_validation:results_archived`

---

### Step 3.6: Pre-Launch Preparation (Standard+ Track)

**Analytics** (if applicable — respect offline/no-telemetry constraints):
- Opt-in usage analytics only
- Track: core feature usage, error rates, performance metrics

**Final UAT session:**
- Run a final testing session using the same Step 2.7 process (parallel agents + human testers)
- All configured testers participate (not just the Orchestrator)
- For Full UAT level (Sponsored POC / Production): formal acceptance sign-off recorded in `APPROVAL_LOG.md` — product sponsor or designated tester confirms core flow works as specified in the Phase 0 Manifesto
- Document confusion points, UX friction, and any remaining issues
- All SEV-1/2 bugs from this session must be resolved before Phase 4

**User documentation:** Direct the agent to produce end-user documentation appropriate to the platform and audience:
- For internal tools: `USER_GUIDE.md` covering how to access, core workflows, FAQ, and who to contact for support
- For external products: in-app help, onboarding walkthrough, or documentation site
- Scope should match complexity — a simple CRUD tool needs a one-page guide, not a manual

**Distribution preparation:** See Platform Module for distribution channel requirements.

**Legal:**
- [ ] Privacy Policy (if collecting any data) — **MANDATORY: must be reviewed by qualified legal counsel before deployment.** AI-generated privacy policies commonly contain inaccuracies, omissions, and generic language that fails to address specific processing activities. Do not deploy AI-generated legal documents without attorney review.
- [ ] Terms of Service (if applicable) — **MANDATORY: must be reviewed by qualified legal counsel before deployment.** Same requirement as Privacy Policy above.
- [ ] License audit passing in CI
- [ ] Trademark search completed

---

### Phase 3 → Phase 4 Gate

#### Gate Enforcement — What `check-phase-gate.sh` Validates (Phase 3→4)

When `current_phase >= 4` in `.claude/phase-state.json`:

- [ ] **`phase_3_to_4` date key recorded in `.claude/phase-state.json`.** Missing key produces a WARN.
- [ ] **`APPROVAL_LOG.md` has a dated Phase 3 → Phase 4 entry.** Same 15-line proximity rule: the date must appear within 15 lines of the `Phase 3.*Phase 4` header.
- [ ] **Organizational deployments: both Application Owner and IT Security approval entries present** in `APPROVAL_LOG.md`.

When `current_phase >= 3` (pre-gate checks that run before the transition is recorded):

- [ ] **`HANDOFF.md` exists.**
- [ ] **`docs/INCIDENT_RESPONSE.md` exists.**
- [ ] **`sbom.json` exists.**
- [ ] **`docs/test-results/` directory exists and is non-empty.** An empty directory produces a FAIL.
- [ ] **`SECURITY.md` exists.** Missing produces a WARN.
- [ ] **POC mode check.** If `poc_mode` is set in `phase-state.json`, Phase 4 (production release) is blocked. POC projects complete at Phase 3.
- [ ] **Release pipeline check.** If `.github/workflows/release.yml` exists, any remaining `TODO` items produce a WARN.
- [ ] **Penetration test results** (Standard+ track). The script looks for files matching `*pen-test*`, `*pentest*`, or `*penetration*` in `docs/test-results/`. Standard track allows IT Security exemption recorded in `APPROVAL_LOG.md`; Full track has no exemption path.
- [ ] **Review manifest** (`docs/eval-results/review-manifest.json`) exists.
- [ ] **Bug gate passes** (`scripts/test-gate.sh --check-phase-gate`).

#### Gate-Checked vs. Snapshot-Only Artifacts

The gate script checks existence of specific artifacts (listed above). When the gate passes, it also creates a point-in-time snapshot in `docs/snapshots/phase-3-to-4_YYYY-MM-DD/`. The snapshot includes additional artifacts that are **not** gate-checked:

| Artifact | Gate-Checked? | Snapshot-Included? |
|---|---|---|
| `HANDOFF.md` | Yes (existence) | Yes |
| `docs/INCIDENT_RESPONSE.md` | Yes (existence) | Yes |
| `sbom.json` | Yes (existence) | Yes |
| `docs/test-results/` | Yes (non-empty) | Listing only |
| `SECURITY.md` | Yes (WARN if missing) | No |
| `APPROVAL_LOG.md` | Yes (dated entry) | Yes |
| `PRODUCT_MANIFESTO.md` | No (checked at Phase 0→1 only) | Yes |
| `PROJECT_BIBLE.md` | No (checked at Phase 1→2 only) | Yes |
| `FEATURES.md` | No (checked at Phase 2→3 only) | Yes |
| `CHANGELOG.md` | No (checked at Phase 2→3 only) | Yes |
| `BUGS.md` | No | Yes |
| `USER_GUIDE.md` | No | Yes |
| `RELEASE_NOTES.md` | No | Yes |

Artifacts marked "No" in the Gate-Checked column are included in the snapshot for audit purposes but their absence does not block the Phase 3→4 transition. Ensure these artifacts are complete before proceeding — the snapshot preserves whatever state they are in at gate time.

---

### Phase 3 Remediation

| Issue | Detection | Response | Blocks Phase 4? |
|---|---|---|---|
| **Logic Drift** | App works but doesn't solve the Phase 0 problem. | Strayed from Manifesto. Remove the feature. Re-align. | Yes (Critical) |
| **Silent Errors** | App fails without user feedback. | Error boundaries. Every failure shows recovery suggestion. | Yes (High) |
| **Security Regression** | Change broke auth or data isolation. | Full security audit from 3.2. Non-negotiable. | Yes |
| **Accessibility Failures** | Below target scores or broken keyboard navigation. | Address every finding. Ship nothing below target. | Yes |
| **Performance Regression** | Below target on any metric. | Profile and audit. Address largest bottleneck first. | Yes (if Critical/High) |
| **Cross-Platform Failure** | Works on one platform, broken on another. | Fix before proceeding. All target platforms must pass. | Yes |
| **Monitoring Unavailable** | Monitoring tool down or configuration lost. | Use an alternative tool. Do not launch without error tracking. | Yes |
| **App Store Rejection** (mobile) | Store review rejects the submission. | Read rejection reason. Fix cited issue. Resubmit. See Platform Module. | Yes (until accepted) |

**Re-run protocol after major remediation:** If a fix changes application behavior (not just scan configuration), re-run the affected test steps. Security fix → re-run Steps 3.1 (integration) and 3.2 (security). Accessibility fix → re-run Step 3.4. Performance fix → re-run Step 3.5. If multiple step types are affected, use `scripts/process-checklist.sh --reset phase3_validation` to re-run the full Phase 3 sequence. For minor fixes that don't change behavior (suppression configuration, documentation), re-running is not required.

**Evaluation prompts:** For additional validation depth, consider running the Security Review (`evaluation-prompts/Projects/bases/03-security.md`) and Red Team Review (`evaluation-prompts/Projects/bases/06-red-team-review.md`) evaluation prompts. Results should be archived to `docs/eval-results/`. Required for Full Track projects.

---

## Phase 4: Release & Maintenance

**Duration:** 1-3 days (initial) + ongoing | **Human Hours:** 3-8 (initial) + 2-4/week (first 3 months), stabilizing to 1-2/week

**Objective:** Build, package, distribute, monitor, maintain.

**Process checkpoint:** Start Phase 4 release: `scripts/process-checklist.sh --start-phase4`

**Track-agnostic enforcement:** As with Phase 3, the process checklist enforces identical step sequences for all tracks. Light track "simplifies" Phase 4 by reducing the scope within each step (e.g., cut-over deployment instead of blue/green, monitoring optional for <10 users), not by removing steps from the checklist. See the Track Requirements Matrix in Process Right-Sizing for per-step track requirements.

---

### Step 4.1: Production Build & Distribution

> **⟁ PLATFORM MODULE:** Reference your Platform Module for complete build, packaging, code signing, and distribution instructions. This step is entirely platform-dependent.

Core requirements regardless of platform:
- [ ] Build reproducible from CI (not from the Orchestrator's machine only)
- [ ] All target platforms build successfully
- [ ] Production configuration applied (not dev/debug settings)
- [ ] Secrets and debug tools excluded from production build

**Agent persona — Release Engineer / SRE:** For production deployment, the agent adopts the mindset of a release engineer responsible for uptime. Start fresh — assume nothing works until proven. This is a business application — quality is more important than positivity. Be critical, extremely thorough, and meticulous. Before shipping: (1) verify the build artifact is reproducible from CI, (2) confirm all target platforms build cleanly, (3) prove production config is applied (no dev keys, no debug endpoints), (4) test the rollback procedure on staging, (5) verify monitoring detects the first failure. "Can I rollback in under 5 minutes? What's the first thing that will break, and will I know about it?"

#### Deployment Strategy

For applications with active users, select a deployment strategy that limits blast radius:

| Strategy | When to Use | How |
|----------|------------|-----|
| **Cut-over** | Light Track internal tools, zero-downtime not required | Deploy new version, replace old version |
| **Blue/green** | Standard+ Track web applications | Maintain two production environments; switch traffic after smoke test |
| **Rolling / canary** | Standard+ Track with >1,000 users | Route 5–10% of traffic to new version; expand if error rates are stable |
| **Feature flags** | High-risk features on any track | Deploy code dark; enable for subset of users; monitor before full rollout |

Light Track projects MAY use cut-over deployment. Standard and Full Track projects SHOULD use blue/green or rolling deployment. Document the chosen strategy in the Project Bible.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase4_release:production_build`

---

### Step 4.1.5: Rollback & Incident Response Playbook

**Create before you need it.**

1. Document rollback procedure (platform-specific — see Platform Module).
2. Document data model rollback.
3. Create `docs/INCIDENT_RESPONSE.md`:

**Severity Classification:**

| Severity | Definition | Response Time | Notification |
|---|---|---|---|
| **SEV-1** | App unusable, data loss, security incident | Immediate | Orchestrator + backup maintainer + sponsor + IT security |
| **SEV-2** | Major feature broken, data integrity concern | Within 1 hour | Orchestrator + backup maintainer |
| **SEV-3** | Non-critical bug, performance degradation | Within 4 hours | Orchestrator |
| **SEV-4** | Cosmetic issue, minor bug | Next maintenance window | Log in tracker |

**Containment:** SEV-1/SEV-2: rollback first, investigate second. Preserve logs before rollback. Suspected data breach: isolate, preserve evidence, notify IT security and legal.

**Secrets rotation:** Compromised secret → rotate immediately, audit access logs, update all environments, verify application functionality.

#### Mandatory Rollback Test

Before the application goes live, the Orchestrator MUST test the rollback procedure:

1. Deploy the release candidate to production (or a production-equivalent environment).
2. Execute the documented rollback procedure.
3. Verify the application reverts to the prior working state.
4. Verify data integrity after rollback (no data loss, no corruption).
5. Record the time elapsed and any issues encountered.

If the rollback procedure fails, fix it and re-test before proceeding to production launch. A rollback procedure that has never been tested is not a rollback procedure — it is a hope.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase4_release:rollback_tested`

---

### Step 4.2: Go-Live Verification

Walk through the production application manually on each target platform:

- [ ] Application installs/deploys correctly
- [ ] Complete full User Journey on each platform
- [ ] Core functionality works as specified
- [ ] Error tracking capturing events (trigger a test error)
- [ ] All production configuration values set correctly
- [ ] Platform-specific checks per Platform Module

> **⟁ PLATFORM MODULE — MANDATORY:** You MUST complete the platform-specific go-live checklist from your Platform Module in addition to the core checklist above. The Platform Module checklists contain critical platform requirements (SSL/security headers for web, code signing/auto-updater for desktop, app store metadata/certificates for mobile) that are not optional. Failure to complete platform-specific checks may result in deployment rejection (app store), security exposure (web), or broken functionality (desktop).

**DECISION GATE: All core AND platform-specific checks green before announcing launch.**

**Release Notes:** Direct the agent to produce `RELEASE_NOTES.md`:
- Version number and date
- What the application does (user-facing summary, not developer changelog)
- Known limitations or issues
- How to report bugs or request support
- For Standard+ with external users: publish alongside the application (landing page, app store listing, or in-app)

For subsequent releases, append to RELEASE_NOTES.md with user-facing descriptions of what changed, what was fixed, and what's known-broken.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase4_release:go_live_verified`

---

### Step 4.3: Monitoring Setup

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-appropriate monitoring (error tracking, crash reporting, uptime monitoring, analytics).

Core requirements:
- Error/crash reporting configured and verified
- Alerting rules: notify on unhandled errors and critical failures
- Uptime/health monitoring (if applicable to the platform)
- **Trigger a test error and verify the alert is received.** Do not mark this step complete until you have confirmed that a deliberately triggered error appears in the monitoring dashboard and fires the expected alert. "Configured" is not "verified" — an untested monitoring setup is indistinguishable from no monitoring.

Document the monitoring configuration in `HANDOFF.md` Section 8 (Monitoring & Alerting subsection): tool name, dashboard URL, alert channel, and access instructions.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase4_release:monitoring_configured`

---

### Step 4.4: Ongoing Maintenance Cadence

**Schedule these cadences proactively** — create recurring calendar events for each application. Do not rely on memory. Run `scripts/check-maintenance.sh` to verify whether any cadence is overdue.

**Weekly (30 minutes):**
- Review error dashboard and monitoring alerts
- Health check: application is up and responsive
- Review any user feedback or support requests

**Monthly (1-2 hours):**
- Dependency and security audit
- Apply non-breaking security patches
- Review error dashboard. Fix recurring errors.
- Rotate API keys/tokens approaching expiration
- Update SBOM
- Run full E2E test suite before each maintenance release
- Triage incoming bugs from production monitoring (same severity classification as Phase 2)

**Quarterly (2-3 hours):**
- Review usage: what are users doing? What are they requesting?
- Performance comparison to last quarter
- Infrastructure/distribution cost review
- Prioritize post-MVP backlog based on real user signals
- Run full regression test suite (all Phase 2 + Phase 3 tests)

**Biannually (3-4 hours):**
- Full dependency audit. Identify deprecated packages.
- Plan version upgrades.
- Re-run full Phase 3 security and performance audit.
- Verify AI provider terms (if using AI in development).
- Review platform requirements (SDK versions, OS support, store policies).

---

### Step 4.5: Handoff Documentation

Direct the agent to generate `HANDOFF.md`:

1. Product intent and architecture overview
2. Step-by-step development setup from zero (on each target platform)
3. Build and release process for each platform
4. Technical debt map (specific files, nature of debt)
5. Maintenance schedule summary
6. Incident history
7. Bug reporting mechanism: how users report bugs post-launch, where bugs are tracked, triage cadence and severity SLAs
8. Key contacts and third-party services
9. AI Quick Start prompt for a new AI agent

**Reality check:** Have someone attempt development setup and issue triage using only this document. Fix every gap they find. Repeat.

**Process checkpoint:** `scripts/process-checklist.sh --complete-step phase4_release:handoff_written`

**Agent persona — New Maintainer:** When writing handoff documentation, the agent adopts the mindset of a developer who is taking over this project on Monday with zero context. This is a business application — quality is more important than positivity. Be critical, extremely thorough, and meticulous. "I have 2 hours to get a dev environment running and fix a production bug. Every command must work verbatim. Every file path must be correct. Every dependency must be listed with version and install command." Test your own docs: could someone follow these instructions from a blank machine to a running dev environment to a fixed bug, using nothing but this document?

---

### Phase 4 Remediation

| Issue | Detection | Response |
|---|---|---|
| **Build Failure** | CI fails on one or more platforms. | "Isolate the platform. Fix on a branch. Full test suite before merging." |
| **Environment Mismatch** | Works in dev, fails in production. | "Diff configurations. Check platform-specific settings." |
| **Cost Spike** | Hosting/distribution costs exceed ceiling. | "Identify the resource. Optimize or restructure." |
| **Dependency Break** | Update breaks the app. | "Revert to last tagged release. Fix on a branch." |
| **Rollback Failure** | Rollback procedure doesn't work. | "Fix the runbook first. Broken runbook is higher priority than broken feature." |

---

## Issue Resolution Quick Reference

| Issue | Detection Signal | Response |
|---|---|---|
| **Context Window Bleed** | AI hallucinates variables, forgets structure | Fresh session with Bible + last 3-4 active files |
| **Code Drift** | Feature works but contradicts the Bible | Stop. Re-inject Bible. Realign before continuing. |
| **Logic Drift** | App works but doesn't solve Phase 0 problem | Re-read Manifesto to AI. Remove non-Manifesto features. |
| **Feature Creep** | AI suggests features outside MVP Cutline | "Not in the Cutline. Not in Phase 2. Post-MVP Backlog." |
| **Dependency Creep** | New package for every small problem | "Achieve with existing stack. Justify any new dependency." |
| **Security Regression** | Change broke auth or data isolation | Re-run Phase 3.2. Non-negotiable. |
| **Unmitigated Threat Vector** | Phase 3.2 validation finds a Phase 1.3 threat with no mitigation | Implement the mitigation or document explicit risk acceptance with rationale. Do not ship. |
| **Rollback Failure** | Procedure doesn't work | Fix runbook first. Higher priority than broken feature. |
| **AI Quality Variance** | Consistently poor output in a session | End session, start fresh. Quality varies across sessions. |
| **Architecture Wrong Mid-Build** | Can't support a requirement | Stop Phase 2. Return to Phase 1.2. Revise Bible. |
| **Platform Inconsistency** | Works on one platform, fails on another | Test on all targets. Fix before continuing. |

---

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
| `SECURITY.md` | 4 | Vulnerability reporting — supported versions, reporting mechanism, response time, safe harbor | Root | `security.tmpl` |
| Security Audit Findings | 2 | Per-feature security audit findings and resolutions | `docs/security-audits/[feature]-security-audit.md` | `security-audit-findings.tmpl` |
| Threat Model Validation | 3 | Per-vector validation results linking Phase 1 threats to Phase 3 evidence | `docs/test-results/[date]_threat-model-validation.md` | `threat-model-validation.tmpl` |
| False Positive Log | 3 | Suppressed security findings with rationale and approval | `docs/test-results/[date]_false-positive-log.md` | `false-positive-log.tmpl` |
| Rollback Test Results | 4 | Mandatory rollback test evidence | `docs/test-results/[date]_rollback-test.md` | `rollback-test.tmpl` |
| Post-Incident Reviews | 4+ | Post-mortem analysis after production incidents | `docs/incidents/[date]-[slug].md` | Section in `incident-response.tmpl` |
| In-Phase Decision Log | 2 (org) | Running log of Phase 2 decisions + biweekly review outcomes | Root or `docs/` | `decision-log.tmpl` |
| Phase 0 Intermediates | 0 | FRD, User Journey, Data Contract — detailed pre-Manifesto outputs | `docs/phase-0/` | `frd.tmpl`, `user-journey.tmpl`, `data-contract.tmpl` |
| `docs/INCIDENT_RESPONSE.md` | 4 | Severity classification, notification chains, rollback, containment | `docs/INCIDENT_RESPONSE.md` | `incident-response.tmpl` |
| `RELEASE_NOTES.md` | 4 | User-facing: what the app does, known limitations, change history (append-only) | Root | `release-notes.tmpl` |
| `HANDOFF.md` | 4 | Complete transfer document — dev setup, build process, tech debt, AI quick start | Root | `handoff.tmpl` |
| Phase Gate Snapshots | 0-4 | Point-in-time document snapshots at each phase transition | `docs/snapshots/phase-N-to-M_YYYY-MM-DD/` | — (auto-created) |
| Compliance Screening Matrix | 0 (org) | Regulatory applicability assessment | Embedded in Intake Section 8.4 | Part of `project-intake.md` |
| Penetration Test Report | 3 (Standard+) | External security assessment | `docs/test-results/` | — (external) |
| Handoff Test Results | 4 (org) | Backup maintainer validation results | `docs/test-results/` | — |

---

## Appendix B: Glossary

### Process Terms

**Solo Orchestrator:** A single experienced technologist acting as Product Owner, Lead Architect, and QA Director, using AI as the execution layer.

**Phase Gate:** A checkpoint where specific artifacts must be completed before proceeding.

**MVP Cutline:** The explicit boundary between "ships first" and "ships after user feedback."

**Product Manifesto:** The governing constraint document for all phases.

**Project Bible:** The comprehensive technical specification the AI uses as context for code generation.

**Loom Method:** Building software in small, tested, independently verifiable modules.

**Platform Module:** A companion document providing platform-specific architecture, tooling, testing, and deployment guidance. Referenced from this core guide at defined integration points.

**Standard+ Track:** Shorthand for "Standard and Full tracks" — any track above Light. Used in step headings to indicate the step is required for Standard and Full tracks, and skipped or abbreviated for Light track. Defined in Process Right-Sizing.

### Security Terms

**SAST:** Static analysis of source code for vulnerabilities. Examples: Semgrep, Snyk Code.

**DAST:** Testing a running application by sending malicious requests. Examples: OWASP ZAP, Burp Suite.

**SBOM (Software Bill of Materials):** Machine-readable inventory of all software components. Used for supply chain security and license compliance.

**IDOR:** Vulnerability where manipulating a reference accesses another user/context's data.

**CSP (Content Security Policy):** Header controlling which resources a browser is allowed to load. Web-specific.

### Testing Terms

**TDD:** Tests written before implementation. Cycle: failing test → minimum code to pass → refactor.

**E2E Test:** Automates the full user journey through the application.

**Contract Test:** Verifies interface expectations match actual behavior.

**Regression Test:** Verifies a fixed bug hasn't been reintroduced.

**Smoke Test:** Quick check that core functionality works. Not exhaustive.

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

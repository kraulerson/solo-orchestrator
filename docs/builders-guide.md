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

The Solo Orchestrator Framework is a structured software development methodology that enables a single experienced technologist to build production-grade applications by using AI Large Language Models as the execution layer. The technologist acts as Product Owner, Lead Architect, and QA Director. The AI proposes architecture, generates logic, and writes code within constraints defined and validated by the human operator.

### What This Is Not

This framework does not replace engineering teams. It is not appropriate for:

- **Compliance-regulated systems** requiring SOC 2, HIPAA, PCI-DSS, or FedRAMP certification. These require dedicated security teams and audit processes beyond what a solo builder can validate.
- **High-availability systems** with 99.99%+ uptime SLAs. Solo-maintained systems have a single point of failure at the operator level.
- **Large-scale distributed systems** requiring microservices, message queues, or multi-region deployments. These require dedicated DevOps capacity.
- **Enterprise integration projects** (SAP, Salesforce, custom ERP) where the integration complexity exceeds the application logic.

The framework is designed for internal tools, utilities, departmental applications, prototypes, and MVP validation — projects that sit in the backlog because they don't justify a full team. Production-ready Platform Modules exist for web, desktop, and mobile applications. Additional platform modules (CLI, embedded) can be added as they mature.

### How This Differs From "Vibe Coding"

- Requirements are formally documented before any technology is selected (Phase 0).
- Architecture decisions are constrained by budget, timeline, and maintenance capacity — not AI suggestion (Phase 1).
- Every feature is built test-first: tests define expected behavior before implementation code is written (Phase 2).
- Security is validated through automated scanning, dependency auditing, and manual review (Phase 3).
- Deployment includes automated pipelines, monitoring, alerting, and documented incident response procedures (Phase 4).
- Every phase produces documentation enabling a qualified replacement to resume maintenance.

The AI writes code. The human makes every decision, validates every output, and gates every phase transition.

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

**Start a new Claude conversation for Phase 0.** Keep all Phase 0 steps in the same conversation.

### Intake-First vs. Conversational Discovery

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

**Save as:** `PRODUCT_MANIFESTO.md`

---

### Step 0.5: Revenue Model & Unit Economics (Standard+ Track — skip for internal tools)

**With Intake:** Section 7 is complete. Review for consistency with expanded feature set.

**Without Intake:** Define pricing model, per-user costs, break-even, hosting cost ceiling.

**Save as:** Appendix to `PRODUCT_MANIFESTO.md`

---

### Step 0.6: Orchestrator Competency Matrix

**With Intake:** Section 6.2. Review in context of the emerging architecture — add any domains the Data Contract revealed.

**Without Intake — Self-assessment:** For each domain, answer: "Can I look at the AI's output and reliably determine if it's correct?"

| Domain | Can I Validate? | If No: Automated Tool |
|---|---|---|
| Product/UX Logic | | Manual review / user testing |
| Frontend/UI Code | | Automated linting |
| Backend / API / Core Logic | | Automated testing |
| Database / Data Storage | | Query analysis, migration testing |
| Security (Auth, Injection, IDOR) | | SAST, dependency scanning, DAST |
| Build & Packaging | | CI verification on all target platforms |
| Accessibility | | Automated accessibility tooling |
| Performance | | Profiling tools, benchmarks |
| Platform-Specific (OS integration, native APIs) | | Platform-specific testing suites |

**Save as:** Appendix to `PRODUCT_MANIFESTO.md`

---

### Step 0.7: Trademark & Legal Pre-Check (Standard+ Track)

1. Trademark search: USPTO, WIPO, app stores, domain registrars.
2. Data privacy applicability: Identify applicable regulations if PII is involved.
3. Distribution channel requirements: App store guidelines, platform-specific legal requirements.
4. Document findings in the Product Manifesto.

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

---

## Phase 1: Architecture & Technical Planning

**Duration:** 2-4 days | **Human Hours:** 4-8 | **Tool:** Claude (chat interface), Context7 MCP (optional)

**Objective:** Select the technology stack, define the data model, identify risks, and produce the Project Bible.

**Start a new Claude conversation for Phase 1.** Attach the completed `PRODUCT_MANIFESTO.md` and the Project Intake (if available).

---

### Step 1.1: Business Strategy Gateway (Standard+ Track — skip for internal tools)

Direct the AI to argue AGAINST building: competitors, existing solutions, Go/No-Go recommendation.

**DECISION GATE — Orchestrator decides Go or No-Go.**

---

### Step 1.1.5: Market Signal Validation (Standard+ Track)

**Performed by the Orchestrator, not the AI.** At least one market signal before committing to architecture.

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

**Select one option.** Document selection and rationale for rejecting others.

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
13. **Orchestrator Profile Summary** — Competency gaps and automated tooling to cover them
14. **Accessibility Requirements** — From Intake Section 9
15. **Platform-Specific Requirements** — From your Platform Module
16. **Context Management Plan:**
    - Small projects (<30 files): Full Bible per session
    - Medium projects (30-100 files): Module-level summaries + master index
    - Large projects (>100 files): Condensed Bible Index under 5,000 tokens

**DECISION GATE — Review the complete Bible. This is the point of no return.**

**Organizational deployments:** The Senior Technical Authority must approve the Project Bible before proceeding to Phase 2. Record the approval in `APPROVAL_LOG.md` (Phase 1 → Phase 2 section).

**Personal projects:** Record your self-review in `APPROVAL_LOG.md` before proceeding.

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

**1. Create the repository:**
```bash
mkdir [project-name] && cd [project-name]
git init
git remote add origin https://github.com/[org]/[repo].git
```

**2. Configure branch protection** (repository host settings):
- Require pull request before merging to `main`
- Require status checks to pass
- Disable force pushes

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
- [ ] Pre-commit hook catches a test secret
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

#### Step 2.3 — Implement the Feature

1. Direct the agent to implement to pass all tests.
2. Run the test suite. All tests must pass.
3. Manual validation: verify the feature works as expected.
4. Direct specific fixes for any discrepancies.

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific manual validation steps (e.g., testing on each target OS, verifying native integration, checking platform-specific behavior).

#### Step 2.4 — Security & Quality Audit

1. Run SAST:
   ```bash
   semgrep scan --config=auto src/
   ```
2. Review against the Phase 1.3 Threat Model & Risk/Mitigation Matrix.
3. Check specifically for:
   - [ ] Data isolation: Can one user/context access another's data?
   - [ ] Input validation: Handled at all entry points?
   - [ ] Hardcoded secrets: Anything that should be in configuration?
   - [ ] Efficient data access: No N+1 or equivalent performance issues?
   - [ ] Logging: Significant operations producing structured log entries?
   - [ ] Platform-specific security: See Platform Module
4. Fix findings. Verify tests still pass.

**AI-specific caution areas:** AI-generated code is disproportionately likely to have subtle issues in: complex state management (race conditions), data access efficiency, authentication edge cases, and content security configuration. Apply extra scrutiny in these areas.

**Concrete mitigations for AI-generated code risks:**
- For authentication and access control: write explicit negative tests that attempt unauthorized access (horizontal privilege escalation, role bypass, token reuse). Do not rely on the AI to identify its own auth bugs.
- For state management and race conditions: if the application has concurrent operations, write tests that simulate concurrent access. Use your platform's concurrency testing tools.
- For data access efficiency: run query analysis (EXPLAIN or equivalent) on every database query the AI generates that touches user data. N+1 queries are the most common AI-generated performance defect.
- For input validation: test every user-facing input with injection payloads (SQLi, XSS, command injection) appropriate to your stack. Do not assume the AI's validation is complete.

#### Step 2.5 — Update Documentation

Direct the agent to produce:
- **CHANGELOG.md:** Feature name, date, new interfaces/endpoints/commands.
- **Interface Documentation:** Every new API endpoint, command, or user-facing interface with contracts and error codes.
- **Architecture/UX Decision Record:** For non-trivial decisions.
- **Project Bible Update:** New interfaces, data model changes, new configuration, new dependencies.

Verify the Bible still accurately reflects the codebase. Commit and merge.

#### Step 2.6 — Data Model Changes (if needed)

1. Generate a versioned change with "apply" and "rollback" operations.
2. Apply the change. Verify existing tests pass.
3. Verify rollback cleanly reverts. **Test against realistic data, not empty state.**
4. Update data model documentation in the Bible.

**NEVER modify the data model directly.** All changes go through the versioning tool.

---

### Context Health Check (Every 3-4 Features)

Ask the agent to summarize: features built, features remaining, current data model, known issues. If the summary contains hallucinated features, incorrect references, or contradicts the Bible:
1. Start a fresh session.
2. Provide the updated `PROJECT_BIBLE.md` and the last 3-4 active files.
3. "We are continuing Phase 2. Here is the current state."

If the AI produces consistently low-quality output across multiple attempts, end the session and start fresh. Quality variance between sessions is real.

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

---

### Step 3.1: Integration Testing

> **⟁ PLATFORM MODULE:** Reference your Platform Module for the appropriate integration/E2E testing framework and approach. Web apps use Playwright. Desktop apps use platform-specific UI automation. The tool varies; the requirement doesn't — automate the full user journey.

1. Install the testing framework per your Platform Module.
2. Direct the agent to write an E2E/integration test suite automating the entire User Journey.
3. Run it. Fix failures — these are integration gaps.

---

### Step 3.2: Security Hardening

**Run all automated scans first, then provide results to the agent for review.**

1. Full SAST scan:
   ```bash
   semgrep scan --config=auto --severity ERROR --severity WARNING .
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
7. **SBOM generation** (using your ecosystem's tool — CycloneDX, syft, or equivalent).
8. **Threat Model Validation:** Review the Phase 1.3 Threat Model. For every identified threat vector, verify: the mitigation was implemented, it works as designed, or the risk was explicitly accepted with documented rationale. Any threat vector without a verified mitigation or documented acceptance is a finding that must be resolved before go-live.

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific security checks: code signing verification, sandboxing/permissions model, platform-specific attack vectors, DAST approach (if applicable).

**Quality gate:** Zero critical or high-severity findings before proceeding.

---

### Step 3.3: Chaos & Edge-Case Testing

Direct the agent to implement:
- **Input abuse defenses:** Validation at all entry points, Unicode/null byte handling, size limits
- **Error recovery:** Graceful handling of missing resources, corrupt data, unexpected state
- **Resource limits:** Memory, disk, network constraints appropriate to the platform
- **Concurrency protection:** If applicable — debouncing, idempotency, mutex/locking
- **Global error boundaries:** Catch unhandled errors, display user-friendly recovery

Run the full test suite. Nothing should break.

---

### Step 3.4: UX & Accessibility Audit

> **⟁ PLATFORM MODULE:** Reference your Platform Module for the appropriate accessibility testing tools and standards. Web uses Lighthouse. Desktop and mobile use platform-specific accessibility APIs and testing tools.

Core requirements regardless of platform:
- All interactive elements have text labels
- Never rely on color alone for meaning
- Keyboard/alternative input navigation works for core flows
- Screen reader compatibility for primary user journey (Full Track)

---

### Step 3.5: Performance Audit

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-specific performance testing: startup time, memory usage, rendering performance, bundle/binary size optimization.

Core requirements:
- Application starts within acceptable time for the platform
- Core operations complete within the latency expectations from the Data Contract
- Memory usage is stable (no leaks during extended use)
- Performance is acceptable on the minimum supported hardware/OS version

---

### Step 3.5.5: Contract Testing (Standard+ Track)

For applications with interfaces consumed by other systems (APIs, IPC, file formats):
- Document expected contracts
- Write tests verifying actual behavior matches documented contracts
- Schema validation tests for data formats

---

### Step 3.5.7: Load/Stress Testing (Full Track — if applicable)

> **⟁ PLATFORM MODULE:** Reference your Platform Module for appropriate load testing. Web apps test concurrent users. Desktop apps test large file handling, many open documents, or extended operation periods.

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

---

### Step 3.6: Pre-Launch Preparation (Standard+ Track)

**Analytics** (if applicable — respect offline/no-telemetry constraints):
- Opt-in usage analytics only
- Track: core feature usage, error rates, performance metrics

**User testing:** At least one person who has never seen the product completes the core flow. Document confusion points.

**User documentation:** Direct the agent to produce end-user documentation appropriate to the platform and audience:
- For internal tools: `USER_GUIDE.md` covering how to access, core workflows, FAQ, and who to contact for support
- For external products: in-app help, onboarding walkthrough, or documentation site
- Scope should match complexity — a simple CRUD tool needs a one-page guide, not a manual

**Distribution preparation:** See Platform Module for distribution channel requirements.

**Legal:**
- [ ] Privacy Policy (if collecting any data)
- [ ] Terms of Service (if applicable)
- [ ] License audit passing in CI
- [ ] Trademark search completed

---

### Phase 3 Remediation

| Issue | Detection | Response |
|---|---|---|
| **Logic Drift** | App works but doesn't solve the Phase 0 problem. | "Strayed from Manifesto. Remove [Feature X]. Re-align." |
| **Silent Errors** | App fails without user feedback. | "Error boundaries. Every failure shows recovery suggestion." |
| **Security Regression** | Change broke auth or data isolation. | "Full security audit from 3.2. Non-negotiable." |
| **Accessibility Failures** | Below target scores or broken keyboard navigation. | "Address every finding. Ship nothing below target." |
| **Performance Regression** | Below target on any metric. | "Profile and audit. Address largest bottleneck first." |
| **Cross-Platform Failure** | Works on one platform, broken on another. | "Fix before proceeding. All target platforms must pass." |

---

## Phase 4: Release & Maintenance

**Duration:** 1-3 days (initial) + ongoing | **Human Hours:** 3-8 (initial) + 2-4/week (first 3 months), stabilizing to 1-2/week

**Objective:** Build, package, distribute, monitor, maintain.

---

### Step 4.1: Production Build & Distribution

> **⟁ PLATFORM MODULE:** Reference your Platform Module for complete build, packaging, code signing, and distribution instructions. This step is entirely platform-dependent.

Core requirements regardless of platform:
- [ ] Build reproducible from CI (not from the Orchestrator's machine only)
- [ ] All target platforms build successfully
- [ ] Production configuration applied (not dev/debug settings)
- [ ] Secrets and debug tools excluded from production build

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

---

### Step 4.2: Go-Live Verification

Walk through the production application manually on each target platform:

- [ ] Application installs/deploys correctly
- [ ] Complete full User Journey on each platform
- [ ] Core functionality works as specified
- [ ] Error tracking capturing events (trigger a test error)
- [ ] All production configuration values set correctly
- [ ] Platform-specific checks per Platform Module

> **⟁ PLATFORM MODULE:** Reference your Platform Module for the platform-specific go-live checklist (security headers for web, code signing for desktop, app store compliance for mobile, etc.).

**DECISION GATE: All checks green before announcing launch.**

**Release Notes:** Direct the agent to produce `RELEASE_NOTES.md`:
- Version number and date
- What the application does (user-facing summary, not developer changelog)
- Known limitations or issues
- How to report bugs or request support
- For Standard+ with external users: publish alongside the application (landing page, app store listing, or in-app)

For subsequent releases, append to RELEASE_NOTES.md with user-facing descriptions of what changed, what was fixed, and what's known-broken.

---

### Step 4.3: Monitoring Setup

> **⟁ PLATFORM MODULE:** Reference your Platform Module for platform-appropriate monitoring (error tracking, crash reporting, uptime monitoring, analytics).

Core requirements:
- Error/crash reporting configured and verified
- Alerting rules: notify on unhandled errors and critical failures
- Uptime/health monitoring (if applicable to the platform)

---

### Step 4.4: Ongoing Maintenance Cadence

**Monthly (1-2 hours):**
- Dependency and security audit
- Apply non-breaking security patches
- Review error dashboard. Fix recurring errors.
- Rotate API keys/tokens approaching expiration
- Update SBOM

**Quarterly (2-3 hours):**
- Review usage: what are users doing? What are they requesting?
- Performance comparison to last quarter
- Infrastructure/distribution cost review
- Prioritize post-MVP backlog based on real user signals

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
7. Key contacts and third-party services
8. AI Quick Start prompt for a new AI agent

**Reality check:** Have someone attempt development setup and issue triage using only this document. Fix every gap they find. Repeat.

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

| Artifact | Phase | Purpose |
|---|---|---|
| `PRODUCT_MANIFESTO.md` | 0 | Requirements, MVP Cutline, Revenue Model, Competency Matrix |
| `PROJECT_BIBLE.md` | 1 | Architecture, data model, threat model, test strategy, risks, coding standards, build strategy |
| Architecture Decision Records | 1-2 | Every major choice with alternatives and rationale |
| `CONTRIBUTING.md` | 2 | Coding standards for AI reference |
| `CHANGELOG.md` | 2+ | Feature log, interfaces, data model changes, configuration |
| Interface Documentation | 2+ | Per-endpoint/command/UI contracts, error codes |
| Feature Documentation | 2+ | Component behavior, business logic rationale, UX decisions |
| CI/CD Configuration | 2 | Automated testing, scanning, building, packaging |
| `docs/test-results/` | 3 | Archived scan reports, E2E results, accessibility audits, threat model validation — audit evidence |
| `sbom.json` | 3 | Software Bill of Materials |
| Security Audit Logs | 3 | SAST/DAST results, remediation actions |
| Performance Baselines | 3 | Metrics for future comparison |
| `USER_GUIDE.md` | 3 | End-user documentation: how to use the application, FAQ, support contact |
| `docs/INCIDENT_RESPONSE.md` | 4 | Severity classification, notification chains, rollback |
| `RELEASE_NOTES.md` | 4 | User-facing: what the app does, known limitations, change history |
| `HANDOFF.md` | 4 | Complete transfer document |

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

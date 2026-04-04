# Solo Orchestrator Framework — User Guide

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-007-GUIDE |
| **Version** | 1.0 |
| **Date** | 2026-04-02 |
| **Classification** | User Guide |
| **Companion Documents** | SOI-002-BUILD v1.0 (Builder's Guide), SOI-003-GOV v1.0 (Governance Framework), SOI-004-INTAKE v1.0 (Project Intake Template) |

## Purpose

This guide walks you through using the Solo Orchestrator Framework from first setup to production maintenance. It covers what you do, when, and why — with separate paths for personal projects and organizational deployments.

For what the framework *is*, how it works at a conceptual level, and what it is not suited for, see the [README](../README.md). This guide assumes you have read that and decided to proceed.

### Document Map

| Document | What It Contains | When You Need It |
|---|---|---|
| **This guide** (user-guide.md) | What you do, step by step, from setup to maintenance | Start here |
| [**README**](../README.md) | Framework overview, prerequisites, platform/language support | Before starting |
| [**Builder's Guide**](framework/builders-guide.md) | The complete methodology — phases, prompts, remediation tables, glossary | During every phase |
| [**Project Intake**](../PROJECT_INTAKE.md) | Your product definition — fill this out before Phase 0 | Pre-Phase 0 |
| [**Governance Framework**](framework/governance-framework.md) | Approval authorities, compliance, risk, portfolio governance | Organizational deployments |
| [**CLI Setup Addendum**](framework/cli-setup-addendum.md) | Claude Code configuration, Superpowers, MCP servers | After init, before Phase 0 |
| [**Platform Module**](platform-modules/) | Platform-specific architecture, tooling, testing, distribution | Phases 1-4 |
| [**Executive Review**](framework/executive-review.md) | Business case for CIO evaluation | Organizational evaluation |

---

## 1. Before You Start

### What This Framework Is

A structured methodology for a single experienced technologist to build production-grade applications using AI as the execution layer. You define intent, constraints, and validation. The AI generates architecture, code, tests, and documentation within those constraints. It is phase-gated, test-driven, and security-scanned at every step. See the [README](../README.md) for the full overview.

### What This Framework Expects of You

You are an experienced technologist. You can read code, evaluate architecture trade-offs, write test assertions, and run security tools. The AI writes the code. You make every decision, validate every output, and gate every phase transition.

This is not a tool for learning to program. If you cannot look at AI-generated code and determine whether it is correct, the framework's quality controls will not compensate for that gap. You need practical experience with at least one modern language/framework, basic security concepts (authentication, input validation, injection attacks), and the ability to interpret test results and scan output.

### Time Commitment

From the Builder's Guide:

| Phase | Human Hours | Calendar Time |
|---|---|---|
| **Phase 0:** Product Discovery | 3-5 | 1-2 days |
| **Phase 1:** Architecture & Planning | 4-8 | 2-4 days |
| **Phase 2:** Construction | 15-40 | 2-6 weeks |
| **Phase 3:** Validation & Hardening | 5-12 | 3-7 days |
| **Phase 4:** Release & Maintenance | 3-8 | 1-3 days |
| **Total (experienced)** | **30-73 hours** | **4-10 weeks** |
| **Total (first project)** | **50-110 hours** | **8-14 weeks** |

Plan using the upper bounds. Desktop and mobile projects take more time than web projects in Phases 1, 3, and 4. First-time setup adds 9-19 hours of one-time overhead (tool installation, accounts, repository setup, security tooling, platform-specific toolchain).

Post-launch maintenance stabilizes to 1-2 hours/week (50-80 hours/year). The first 3 months are heavier: expect 2-4 hours/week as you learn the application's production behavior.

---

### 1.1 Personal Project Prerequisites

**Tools to install:**

| Tool | Required | How to Get It |
|---|---|---|
| Git | Yes | [git-scm.com](https://git-scm.com/downloads) |
| Language runtime | Yes | Node.js, Python, Rust, Go, Java/Kotlin, C#/.NET, or Dart/Flutter — depends on your language choice |
| Docker | Recommended | [docker.com](https://www.docker.com/) — needed for OWASP ZAP DAST scanning |
| Claude Code | Recommended | Installed by `init.sh`, or manually: `brew install claude-code` (macOS) |

**Windows users:** WSL is required. The init script, Claude Code, and all CLI tooling expect a Unix shell. Install WSL first, then install your runtime inside it.

**Accounts to create:**

- **GitHub** — free tier is fine
- **AI subscription** — Claude Max (consumer tier) works for personal projects

That is everything. No governance. No approvals. No paperwork. You can start building immediately after running `init.sh`.

---

### 1.2 Organizational Project Prerequisites

**Tools:** Same as personal (Section 1.1).

**Accounts:**

- **GitHub Team or Enterprise** — your organization's standard
- **AI subscription** — commercial or enterprise tier required (Claude Enterprise, API with commercial terms, or zero-data-retention agreement)

**The 6 blocking pre-conditions:**

Before you write a single line of code, 6 things must be resolved. None of them are technical. They are emails, meetings, and paperwork.

| # | Pre-Condition | What It Means | Who to Contact | What to Ask | What You Need Back | Record In |
|---|---|---|---|---|---|---|
| 1 | **AI Deployment Path** | Your IT Security team decides how source code reaches the AI provider — commercial API, enterprise agreement, zero-data-retention, or self-hosted. | IT Security / CISO office | "We are evaluating AI-assisted development. What is our approved deployment path for sending source code to an AI provider?" | Written approval specifying the path (e.g., "Commercial API with ZDR agreement approved") | APPROVAL_LOG.md |
| 2 | **Insurance Confirmation** | Your insurance broker confirms that cyber liability, E&O, and D&O policies cover AI-generated code. | Insurance broker or Risk Management | "Do our current policies cover incidents caused by AI-generated code in production applications?" | Written broker confirmation letter | APPROVAL_LOG.md |
| 3 | **Liability Entity** | Legal decides which company entity (parent or subsidiary) bears liability for the application. | General Counsel / Legal | "Which entity should be designated as liable for this internally-developed application?" | Written designation | APPROVAL_LOG.md |
| 4 | **Project Sponsor** | A business owner who approves budget, answers escalations, and signs off at phase gates. | Your management chain | "I need a named business sponsor for this project. They approve budget and sign off at 3 decision gates." | Name and role | PROJECT_INTAKE.md Section 8 |
| 5 | **Backup Maintainer** | A second technologist who can keep the app running if you are unavailable. | Your management chain or peer engineers | "I need a designated backup who can take over maintenance using the handoff documentation." | Name and role | PROJECT_INTAKE.md Section 8 |
| 6 | **ITSM Registration** | The project is visible in your organization's IT portfolio tracker. | ITSM / PMO team | "I need to register a new internally-developed application in the portfolio tracker." | Ticket number or portfolio entry ID | APPROVAL_LOG.md |

**Phase 0 cannot start until all 6 are resolved.** Not "in progress." Resolved.

If insurance coverage is insufficient, your broker can advise on supplemental AI-specific riders or umbrella policies. If your organization does not have an AI deployment path, you need IT Security to create one — that process may take weeks and is outside your control.

See the [Governance Framework](framework/governance-framework.md) for the full compliance screening matrix and approval authority structure.

---

## 2. Project Initialization (Running init.sh)

### What the Script Asks You

```bash
git clone https://github.com/kraulerson/solo-orchestrator.git
cd solo-orchestrator
chmod +x init.sh
./init.sh
```

The script prompts for 7 inputs:

| Prompt | What You Enter | Guidance |
|---|---|---|
| **Project name** | Lowercase, no spaces (e.g., `invoice-tool`) | This becomes the directory name and appears in generated files. |
| **One-sentence description** | What does it do, in plain language | Used in CLAUDE.md and the Intake template. |
| **Platform type** | Web / Desktop / Mobile / CLI / Other | Determines which Platform Module is loaded and which release pipeline is generated. Pick the primary delivery surface. |
| **Project track** | Light / Standard / Full | **Light:** internal tools, <10 users, skip market audit. **Standard:** external users, moderate complexity. **Full:** enterprise buyers, sensitive data, pen testing mandatory. |
| **Personal or Organizational** | Personal / Organizational | Organizational adds governance pre-flight requirements and approval authority structures. |
| **Primary language** | TypeScript, Python, Rust, C#, Kotlin, Java, Go, Dart, Other | Determines the CI pipeline template (testing, linting, SAST, dependency audit). |
| **Project directory** | Path (default: `~/projects/your-project`) | Where the project is created. |

### What Gets Generated

| File / Directory | Purpose |
|---|---|
| `CLAUDE.md` | Agent instructions — the AI reads this automatically at session start |
| `PROJECT_INTAKE.md` | Your product definition template — you fill this out |
| `APPROVAL_LOG.md` | Phase gate approval record (organizational projects always; personal projects recommended) |
| `.github/workflows/ci.yml` | CI pipeline — language-specific (test, lint, SAST, audit) |
| `.github/workflows/release.yml` | Release pipeline — platform-specific (build, sign, distribute) |
| `.gitignore` | Language + platform appropriate ignores |
| `.claude/framework/` | Claude Dev Framework (Git hook guardrails) |
| `docs/framework/` | Builder's Guide, Governance Framework, Executive Review, CLI Setup Addendum |
| `docs/platform-modules/` | Platform-specific guidance for your selected platform |
| `docs/test-results/` | Empty — populated during Phase 3 |

Each project is self-contained. No runtime dependency on the solo-orchestrator repo after init.

The init script also generates **two pipelines**: a CI pipeline (`ci.yml`) selected by your language (handles testing, linting, SAST, dependency audit, license checking) and a release pipeline (`release.yml`) selected by your platform (handles building, signing, packaging, and distribution). Both are working GitHub Actions workflows, not skeletons — but the release pipeline has TODOs for secrets and code signing that you configure before your first release.

### What to Check After Init

The script runs a health check. Review its output:

- **Green checks** mean tools are installed and working
- **Yellow warnings** mean optional tools are missing (Docker, GPG) — install before Phase 2 if they apply to your project
- **Red failures** mean required tools are missing — fix before proceeding

The health check also validates your language runtime. If it reports a version mismatch or missing runtime, install the correct version before proceeding.

### Post-Init Authentication

```bash
cd ~/projects/your-project   # or wherever you created it
claude                        # Follow the OAuth prompt in your browser
snyk auth                     # Authenticate Snyk CLI
```

Both are one-time per machine.

### Optional Enhancements

After init, you can configure additional tooling. These are not required, but they improve the development workflow. See the [CLI Setup Addendum](framework/cli-setup-addendum.md) for setup instructions.

| Tool | What It Does | When It Helps |
|---|---|---|
| **Superpowers** | Agentic skills plugin for Claude Code — subagent-driven development, strict TDD, systematic debugging, git worktrees | Phase 2 workflow accelerator |
| **Context7 MCP** | Provides Claude with up-to-date library documentation during architecture selection and construction | Phases 1-2 |
| **Qdrant MCP** | Persistent semantic memory across Claude Code sessions — stores project decisions and patterns | Multi-session projects |
| **Claude Dev Framework** | Git hook-based guardrails for coding standards, security scanning, documentation | Auto-installed by init.sh |

---

## 3. Filling Out the Project Intake

Open `PROJECT_INTAKE.md`. This is the most important thing you do before starting.

**Why it matters:** Every blank field is a round-trip with the agent. A complete Intake means the agent works autonomously. An incomplete Intake means the agent stops and asks you — repeatedly.

### Section-by-Section Guidance

**Section 1: Project Identity** — Fill in every field. This is straightforward: project name, track, platform, deployment type. If you answered these during `init.sh`, confirm they match.

**Section 2: Business Context** — The problem statement and user personas drive everything downstream. "Improve efficiency" is not a problem statement. "The finance team spends 6 hours/week manually reconciling invoices from 3 systems into a single spreadsheet" is.

Write 3-5 success criteria with measurable targets and measurement methods. Write 3-5 explicit out-of-scope items — these prevent the agent from building features you did not ask for.

**Section 3: Constraints** — Be honest about your available hours per week. "As time allows" means unpredictable, and the agent cannot plan around it. Set a realistic monthly infrastructure budget ceiling. Name who approves spending (or "self" for personal projects).

**Section 4: Features & Requirements** — This is the most important section.

For each must-have feature, define:
- **Business Logic Trigger:** "If [condition], the system must [action] and output [result]"
- **Failure State:** What happens when input is invalid, a service is unavailable, or the user abandons

If you cannot articulate the trigger and failure state, the feature is not defined well enough to build.

Example of a well-defined feature:

| # | Feature | Business Logic Trigger | Failure State |
|---|---|---|---|
| 1 | Invoice reconciliation | If user uploads CSV files from systems A, B, and C, the system must match invoices by invoice number and flag mismatches exceeding $0.01 | If CSV format is invalid, reject with specific error ("Column 'Invoice Number' not found"). If file exceeds 50MB, reject with size limit message. If matching fails mid-process, preserve partial results and show which rows failed. |

Limit to 8 must-have features. More than 8 means your MVP is too large.

**Section 5: Data & Integrations** — Assign a sensitivity classification to every data input: Public, Internal, Confidential, PII, Financial, Health/Medical, or Regulated. This determines encryption requirements, access controls, and logging levels — it is not optional metadata.

For third-party integrations, define what happens when the service is unavailable. The agent will build fallback behavior from this. "The app crashes" is not acceptable. "Show cached data with a stale-data banner and retry in 30 seconds" is.

Define data persistence explicitly: what must survive across sessions, what can be ephemeral, expected volume at 12 months, retention requirements, and backup expectations. Unanswered persistence questions create architectural debt in Phase 1.

**Section 6: Technical Preferences** — Two parts matter here.

*Architecture Preferences:* For each choice (language, database, framework, hosting), mark whether it is a **hard constraint** or a **preference**. Hard constraints are absolute — the agent will not recommend against them. Preferences can be challenged with justification.

*Competency Matrix:* For each domain (frontend, backend, security, accessibility, database, DevOps, performance, mobile), answer honestly: "Can I look at the AI's output and reliably determine if it's correct?"

| Your Self-Assessment | What Happens |
|---|---|
| "Yes" | You are the quality gate for that domain. No additional automated tooling is mandated. |
| "Partially" | The framework mandates automated tooling in Phase 3 to cover gaps in your review ability. |
| "No" | Same as "Partially," plus the agent defaults to the most conservative, well-documented option in that domain. |

If you mark "Yes" on Security but cannot actually evaluate authorization logic, the framework has no safety net for that domain. Every honest "No" adds automated coverage. Every dishonest "Yes" creates an unscanned attack surface. Lying here hurts you.

**Section 7: Revenue Model** — Fill in for Standard and Full track projects with external users. This drives architecture decisions: per-user cost estimates constrain hosting choices, break-even user counts constrain scalability requirements, and hosting cost ceilings at 1K/10K users force the agent to propose architectures that stay within budget as you grow.

Skip for Light track or internal tools.

**Section 8: Governance Pre-Flight**
- **Personal projects:** Skip this entire section.
- **Organizational projects:** Must be complete before Phase 0. This is where you record the 6 blocking pre-conditions from Section 1.2 of this guide, name your phase gate approvers (who signs off at each gate), define the 3-level escalation chain, and complete the compliance screening matrix with your project sponsor.

The compliance screening matrix includes 8 questions about regulatory exposure (SOX, PCI, privacy laws, EU AI Act, OFAC, records retention, pen testing). Complete it with your sponsor. Each "Yes" triggers a specific action that must be completed before going live.

**Section 9: Accessibility & UX** — WCAG AA is the minimum for any user-facing application. Specify browser support, device support, and whether dark mode is required. If you have users with color vision deficiency, note that explicitly — the agent will ensure the UI never relies on color alone for meaning.

These become architectural constraints from day 1. Retrofitting accessibility in Phase 3 is expensive. Designing for it in Phase 1 is nearly free.

**Section 10: Distribution & Operations** — Platform-specific. Fill in what applies to your platform:

- **Web:** Domain name, SSL certificate source, maintenance window restrictions
- **Desktop:** Distribution channels (GitHub Releases, Homebrew, winget, app stores), code signing (required now / deferred / not needed), installer format, auto-update mechanism, minimum OS versions
- **Mobile:** App Store / Google Play / enterprise sideload, developer accounts (Apple $99/yr, Google $25 one-time), beta testing channels

Define your uptime expectation. "Best effort" is fine for internal tools. 99.9% is reasonable for external products. If you need 99.99%+, this is not a Solo Orchestrator project.

**Section 11: Known Risks** — Anything the agent should know that does not fit elsewhere: technical debt you are aware of going in, political sensitivities (e.g., "this replaces a tool built by a different team"), dependencies on other projects or timelines, previous failed attempts at solving this problem and what you learned from them.

### The Checklist Before Starting

The Intake has a checklist at the bottom. Verify every item before starting:

- Every field is filled or explicitly marked N/A
- All must-have features have business logic triggers and failure states
- Will-Not-Have list has at least 3 items
- Data sensitivity classifications are assigned
- Competency Matrix is honest
- Budget and timeline are realistic
- (Organizational) All Section 8 blocking items are Complete
- The document is saved as `PROJECT_INTAKE.md` in the project repository

---

## 4. Working With the AI Agent

### Starting a Session

```bash
cd ~/projects/your-project
claude
```

The agent reads `CLAUDE.md` automatically. This file contains your project configuration, framework rules, and tool constraints.

### The Initialization Prompt

Section 12 of the Intake contains a ready-to-use initialization prompt. Copy and paste it into the agent at the start of Phase 0. It tells the agent:

- The Intake is the primary constraint
- The Builder's Guide is the process reference
- The Platform Module is the platform-specific reference
- Hard constraints are absolute; preferences can be challenged with justification
- Blank fields must be flagged immediately

You also provide the Builder's Guide (`docs/framework/builders-guide.md`) and the relevant Platform Module.

### The Agent's Operating Model

The agent works autonomously between decision gates. It reads your Intake, follows the Builder's Guide, and builds. It stops when:

1. **It needs information** — a blank or ambiguous field in the Intake
2. **It reaches a decision gate** — an artifact that requires your review and approval
3. **It finds a conflict** — a contradiction between your constraints and technical feasibility

**When the agent asks you a question:** Answer it. The agent stopped for a reason. Vague answers ("whatever you think is best") produce vague output that you will reject later. Be specific: "Use PostgreSQL" not "whatever database you think is best."

**When the agent presents a decision gate:** Review the artifact carefully. Approve it, or explain specifically what needs to change — "the user journey for the export feature doesn't account for empty data sets" is actionable. "This doesn't feel right" is not. Record every approval in `APPROVAL_LOG.md`.

**When the agent proposes something outside the Intake:** Push back. The Intake is the governing constraint. If the agent suggests a feature not in the MVP Cutline, a technology you excluded, or an architecture that contradicts your hard constraints, tell it to stop and reference the specific Intake section. The agent should not override your decisions without your explicit consent.

### Session Management

AI coding agents have context limits. For long-running projects:

- **Start each session** by pointing the agent to `CLAUDE.md` (read automatically), then provide the `PROJECT_BIBLE.md` and relevant source files for context.
- **End each session** by confirming what was completed and what remains. The agent should update the Bible and CHANGELOG.md before you close.
- **Between sessions**, the agent does not retain state unless you have configured Qdrant MCP for persistent semantic memory. Without it, every session starts fresh with the Bible as context.
- **If a session goes poorly** (low-quality output, hallucinations, context drift), end it and start fresh. Do not try to steer a confused agent back on track — it is faster to restart.

---

## 5. Phase-by-Phase Walkthrough

This section covers what **you** do at each phase — not what the agent does. For the agent's process, prompts, and remediation procedures, see the [Builder's Guide](framework/builders-guide.md). For platform-specific instructions at each phase, see your [Platform Module](platform-modules/).

**How to read this section:** Each phase has a table showing your actions with separate columns for personal and organizational paths. "Same" means no difference between paths. Where the organizational path has additional requirements, they are listed explicitly.

---

### Phase 0: Product Discovery (1-2 days, 3-5 human hours)

**What happens:** The agent reads your Intake and generates a Product Manifesto — a structured expansion of your product definition including functional requirements, user journeys, data contracts, and an MVP Cutline.

| Your Action | Personal | Organizational |
|---|---|---|
| Provide Intake + Builder's Guide + Platform Module to agent | Same | Same |
| Review Functional Requirements Document | Self-review | Self-review |
| Review user personas and interaction flows | Self-review | Self-review |
| Review data contracts (inputs, outputs, validation) | Self-review | Self-review |
| **DECISION GATE: Approve Product Manifesto** | Self-review; record in APPROVAL_LOG.md | Send to Project Sponsor for approval; record in APPROVAL_LOG.md with evidence reference |
| Trademark search (Standard+ track) | Search USPTO, app stores, domain registrars, WIPO | Same, plus document findings for legal |

**Revenue model review (Standard+ track):** The agent generates financial projections from your Section 7 data. Verify that break-even assumptions are realistic and that hosting costs remain tenable at 1,000 and 10,000 users.

**What you produce:** Approved `PRODUCT_MANIFESTO.md`

**Key review questions:**
- Does the MVP Cutline match what you actually want to ship first?
- Are the user journeys realistic — would your actual users follow these paths?
- Are there features in the Manifesto you did not ask for? (Remove them.)
- Do the data contracts match your Section 5 inputs?
- Are the out-of-scope items explicitly listed? (They prevent scope creep in Phase 2.)

---

### Phase 1: Architecture & Planning (2-4 days, 4-8 human hours)

**What happens:** The agent proposes 3 architecture options, generates a STRIDE threat model, designs the data model, and synthesizes everything into a Project Bible.

| Your Action | Personal | Organizational |
|---|---|---|
| Market signal validation (Standard+ track) | Get at least 1 positive signal before architecture investment | Same — document the signal |
| **DECISION GATE: Select architecture** from 3 options | Select one; document rationale for rejection of others | Same |
| Review STRIDE threat model | Verify mitigations are concrete, not "be careful" | Same |
| Review data model | Verify it supports all must-have features | Same |
| Review UI component specifications | Verify component states (empty, loading, error, success) | Same |
| **DECISION GATE: Approve Project Bible** | Self-review; record in APPROVAL_LOG.md | Senior Technical Authority reviews and approves; record in APPROVAL_LOG.md with evidence |

**What you produce:** Approved `PROJECT_BIBLE.md`, `CONTRIBUTING.md`, Architecture Decision Records

**Architecture selection — what to look for:**

The agent presents 3 options. For each, verify it includes: languages and frameworks (exact versions), data storage strategy, authentication approach, observability (logging, error reporting), secrets management, build/packaging strategy for all target platforms, and a scalability vs. velocity trade-off analysis. Reject any option that does not address your platform-specific requirements from the Platform Module.

Select one. Document why you rejected the other two. This is recorded as an Architecture Decision Record.

**Threat model — what to look for:**

The agent generates a STRIDE threat model. It should identify assets (user data, auth tokens, API keys, admin access), threat actors (unauthenticated users, authenticated malicious users, compromised dependencies, insiders), and attack vectors with concrete mitigations. "Be careful with user input" is not a mitigation. "Validate all user input at API boundary using schema validation; reject non-conforming requests with 400 status" is.

The architecture stress test should include: 5 edge cases where the stack would fail, 3 stack-specific security vulnerabilities, 2 data storage bottleneck risks, and 1 limitation that could force a rewrite in 12 months.

**Data migration (if replacing an existing system):** If legacy data exists, the agent produces a migration plan with source inventory, field mapping, transformation rules, a repeatable import script, rollback procedure, and validation criteria. You must be able to confirm migrated data is correct and complete.

**This is the point of no return.** If the architecture is wrong, fix it now. Discovering it mid-Phase 2 is far more expensive.

---

### Phase 2: Construction (2-6 weeks, 15-40 human hours)

**What happens:** The agent builds features one at a time using TDD, starting with the highest-risk feature.

#### Project Initialization (Before the Build Loop)

Before any features are built, the agent initializes the project scaffolding. Verify these 8 checks pass before entering the Build Loop:

- [ ] Linter runs clean
- [ ] Test runner executes (0 tests, 0 failures)
- [ ] Initial data model applies successfully
- [ ] Pre-commit hook catches a test secret (verify gitleaks is working)
- [ ] License checker runs clean
- [ ] CI pipeline passes on first push
- [ ] Backup and restore verified (test this now, not in Phase 4)
- [ ] Application builds and runs on at least one target platform

#### The Build Loop (Per Feature)

For each feature in the MVP Cutline, ordered by risk (highest-risk first):

| Step | What You Do |
|---|---|
| **1. Tests first (RED)** | Review the agent's test suite. Verify it includes: success-state tests, negative tests (invalid/empty/malicious input), and boundary tests. Then **write at least 3 test assertions yourself** — business logic tests, not "response is not null." Confirm all tests fail before implementation exists. |
| **2. Implementation (GREEN)** | The agent implements code to pass the tests. Run the full test suite — all tests must pass. Manually verify the feature works as expected. If something is wrong, direct specific fixes. |
| **3. Security audit** | Run `semgrep scan --config=auto src/`. Review findings against the Phase 1 threat model. Check specifically for: data isolation (can one user access another's data?), input validation at all entry points, hardcoded secrets, N+1 queries, and structured logging of significant operations. |
| **4. AI-specific scrutiny** | The agent's code has known blind spots. For each feature, check: auth/access control (write explicit negative tests for unauthorized access), state management (if concurrent operations exist, write concurrency tests), data access efficiency (run EXPLAIN on AI-generated database queries touching user data), and input validation (test every user-facing input with injection payloads). |
| **5. Documentation update** | Verify the agent updates CHANGELOG.md (feature name, date, new interfaces), interface documentation (API endpoints, contracts, error codes), and the Project Bible (new interfaces, data changes, configuration, dependencies). |
| **6. Data model changes** | If the feature requires data model changes: generate a versioned change with "apply" and "rollback" operations, verify existing tests still pass, verify rollback cleanly reverts (against realistic data, not empty state), update data model documentation in the Bible. Never modify the data model directly — all changes through the versioning tool. |

**Good test assertions you write:**

```
"When user provides invalid email, system returns 400 with 'email format invalid' message"
"When user lacks permission, system returns 403 Forbidden, not 500"
"When 2 users edit the same record, last write wins with version number incremented"
"When CSV has 100,001 rows (over limit), system rejects with 'Maximum 100,000 rows' message"
"When third-party API returns 503, system shows cached data with stale-data warning"
```

Bad test assertions (too vague to catch real bugs):

```
"Response is not null"
"Status code is 200"
"It works"
```

#### Context Health Checks (Every 3-4 Features)

Ask the agent to summarize: features built, features remaining, current data model, known issues. Compare this against the Project Bible.

If the summary contains hallucinations (references to features that do not exist, incorrect data model descriptions, contradictions with the Bible):

1. Start a fresh Claude Code session
2. Provide the updated `PROJECT_BIBLE.md` and the last 3-4 active source files
3. Tell the agent: "We are continuing Phase 2. Here is current state."

Do not try to correct a drifted agent in the same session. It is faster to restart.

#### When to Escalate

| Situation | Action |
|---|---|
| Budget overrun (more hours than planned) | Re-evaluate remaining features. Defer should-have features. Notify sponsor (organizational). |
| Scope change request | Return to the Manifesto. If the change contradicts the MVP Cutline, it waits for v1.1. |
| Security finding that requires architecture change | Return to Phase 1. Revise the Bible. Get re-approval (organizational: Senior Technical Authority). |
| Agent producing consistently low-quality output | End the session. Start fresh. If quality does not improve, the Intake or Bible may be insufficiently detailed. |

#### Phase 2 Completion Checkpoint

All of these must be true before proceeding:

- [ ] All MVP Cutline features built and passing tests
- [ ] No partially implemented features
- [ ] Full test suite passes
- [ ] CI pipeline green
- [ ] Project Bible accurately reflects current codebase
- [ ] CHANGELOG.md current
- [ ] No unresolved security findings
- [ ] Application builds on all target platforms

If any check fails, return to the Build Loop. Do not proceed to Phase 3.

| Organizational-only actions during Phase 2 |
|---|
| Maintain an In-Phase Decision Log (date, decision, rationale, alternatives considered) for every non-trivial choice |
| Senior Technical Authority reviews this log at the Phase 2 exit |
| If your Competency Matrix shows "No" or "Partially" on Security: schedule a 1-2 hour security peer review with IT Security covering authorization logic, data isolation, business logic abuse, and auth edge cases |

---

### Phase 3: Validation & Security (3-7 days, 5-12 human hours)

**What happens:** Full security audit, integration tests, accessibility checks, performance tests. The assumption entering Phase 3 is that everything is broken until proven otherwise. Phase 2 built the features; Phase 3 proves they work correctly, securely, and accessibly.

| Your Action | Personal | Organizational |
|---|---|---|
| Run E2E/integration tests on all target platforms | Fix failures — these are integration gaps | Same |
| Run full SAST: `semgrep scan --config=auto --severity ERROR --severity WARNING .` | Fix all critical/high findings | Same |
| Run dependency scan: `snyk test` | Fix vulnerable dependencies | Same |
| Run secret scan: `gitleaks detect --source . --verbose` | Remove any detected secrets | Same |
| Generate SBOM (CycloneDX or equivalent) | Archive in docs/test-results/ | Same |
| Validate threat model — every vector from Phase 1 has a verified mitigation or documented acceptance | Fix gaps | Same |
| Run chaos/edge-case tests | Verify error recovery and input abuse defenses | Same |
| Run accessibility audit (Lighthouse for web, platform tools for desktop/mobile) | Meet WCAG AA / Lighthouse 90+ | Same |
| Run performance audit | Meet latency targets from data contracts | Same |
| Archive ALL test results in `docs/test-results/` | Named `[date]_[scan-type]_[pass\|fail].[ext]` | Same |
| User testing (Standard+ track): have someone unfamiliar complete the core flow | Document confusion points; fix critical ones | Same |
| **DECISION GATE: Approve go-live** | Self-review; record in APPROVAL_LOG.md | Application Owner + IT Security approve; both recorded in APPROVAL_LOG.md |
| — | — | IT Security reviews scan results |
| — | — | Penetration test (if required by track or org policy) |
| — | — | Legal reviews Privacy Policy (if external users) |

**Test results archival:** Save ALL scan results to `docs/test-results/` using the naming convention: `[date]_[scan-type]_[pass|fail].[ext]` (e.g., `2026-04-15_semgrep_pass.json`). These are audit evidence for the Phase 3 gate and are referenced in APPROVAL_LOG.md.

**Pre-launch preparation (Standard+ track):**

- Have at least one person unfamiliar with the product complete the core user flow. Document where they get confused. Fix critical confusion points.
- Generate user documentation: USER_GUIDE.md for internal tools, in-app help or documentation site for external products. Match scope to complexity — a simple CRUD app needs a one-page guide, not a manual.
- Complete the legal checklist: Privacy Policy (if collecting data), Terms of Service (if applicable), license audit passing in CI, trademark search completed.

**What you produce:** `docs/test-results/` (all scan reports), SBOM, Privacy Policy (if applicable), user documentation, go-live checklist

**Zero critical or high-severity findings before proceeding.** No exceptions.

---

### Phase 4: Release & Maintenance (1-3 days + ongoing)

**What happens:** The agent configures deployment, creates monitoring, writes HANDOFF.md, and produces release notes.

| Your Action | Personal | Organizational |
|---|---|---|
| Verify production build on all target platforms | Same | Same |
| Configure secrets in CI/CD (API keys, signing certs, deployment credentials) | Same | Same |
| Review incident response playbook (INCIDENT_RESPONSE.md) | Self-review | Same — share with backup maintainer |
| **DECISION GATE: Go-live smoke test** — walk through the full user journey on each platform in production | Self-review; record in APPROVAL_LOG.md | Same |
| Verify monitoring is active — trigger a test error and confirm you receive an alert | Same | Same |
| Review and publish RELEASE_NOTES.md | Same | Same |
| — | — | File ITSM deployment ticket |
| — | — | Backup maintainer validates HANDOFF.md (can build, test, deploy, run scans from the doc alone) |

**The incident response playbook:**

The agent generates `docs/INCIDENT_RESPONSE.md` with severity classifications. Review and confirm it matches your operational reality:

| Severity | Definition | Response Time | Notification |
|---|---|---|---|
| **SEV-1** | App unusable, data loss, security incident | Immediate | You + backup maintainer + sponsor + IT Security |
| **SEV-2** | Major feature broken, data integrity concern | Within 1 hour | You + backup maintainer |
| **SEV-3** | Non-critical bug, performance degradation | Within 4 hours | You |
| **SEV-4** | Cosmetic issue, minor bug | Next maintenance window | Log in tracker |

The playbook must include: rollback procedure (platform-specific), data model rollback, containment strategy (SEV-1/SEV-2: rollback first, investigate second), log preservation procedure, and secrets rotation procedure.

**Triggering a release:**

```bash
git tag v1.0.0
git push --tags
```

The release pipeline (`.github/workflows/release.yml`) runs automatically on version tags. Review the TODOs in the release pipeline before your first tag — code signing and deployment secrets must be configured in your CI/CD provider's secrets management.

**Go-live smoke test:** Walk through the complete user journey on EACH target platform in the production environment. Not staging. Production. Trigger a test error and confirm your monitoring captures it and you receive an alert.

**The handoff test (organizational):** Your backup maintainer follows `HANDOFF.md` from scratch — clone, set up development environment, build, run tests, run security scans, execute the deployment procedure. Every gap they find gets fixed in the document. Repeat until they can operate independently.

**What you produce:** `HANDOFF.md`, `RELEASE_NOTES.md`, `docs/INCIDENT_RESPONSE.md`, monitoring configuration

---

## 6. The Approval Log in Practice

`APPROVAL_LOG.md` is your audit trail. It records every phase gate decision.

### When to Update It

At every phase gate. The agent will prompt you. The gates are:

| Gate | What Is Approved | Personal | Organizational |
|---|---|---|---|
| Phase 0 completion | Product Manifesto | Self-review | Project Sponsor |
| Phase 1 completion | Project Bible | Self-review | Senior Technical Authority |
| Phase 3 completion | Go-live readiness | Self-review | Application Owner + IT Security |

### What Counts as Evidence

For personal projects, a dated self-review entry is sufficient.

For organizational projects, reference external evidence:

- Email subject line and date ("RE: Invoice Tool Manifesto Approval — 2026-04-10")
- Ticket number ("ITSM-4521 approved 2026-04-10")
- Signed PDF filename
- Meeting minutes reference

### The Rules

1. **Append-only.** Never edit or delete a previous entry. If a decision changes, add a new entry explaining the change.
2. **Every gate, every time.** Even if the approval is "I reviewed this myself and it looks correct."
3. **Be specific.** "Approved" is not enough. "Approved — MVP Cutline includes features 1-5, defers features 6-8 to v1.1" is.

### Example Entry (Organizational)

```
## Phase 0 → Phase 1 Gate
- **Date:** 2026-04-10
- **Gate:** Product Manifesto Approval
- **Approver:** Jane Smith, VP Product
- **Method:** Email
- **Evidence:** "RE: Invoice Tool Manifesto Approval" dated 2026-04-10
- **Decision:** Approved — MVP Cutline includes features 1-5 (invoice upload,
  matching, mismatch flagging, export, dashboard). Features 6-8 (bulk import,
  scheduled runs, Slack notifications) deferred to v1.1.
- **Notes:** Sponsor requested mismatch threshold be configurable (added to
  feature 3 requirements).
```

### Example Entry (Personal)

```
## Phase 0 → Phase 1 Gate
- **Date:** 2026-04-08
- **Gate:** Product Manifesto Approval
- **Approver:** Self
- **Decision:** Approved. MVP Cutline is features 1-4. Reviewed user journeys
  and data contracts — no issues found.
```

### How an Auditor Reads It

Top to bottom, chronologically. They are looking for: Was every gate explicitly approved? By whom? Is there evidence? Are there gaps or backdated entries? The append-only rule exists because auditors notice edits.

For personal projects, maintaining the log is optional but recommended. If your personal project ever becomes an organizational one (it happens), having the history is valuable.

---

## 7. Ongoing Maintenance

After launch, you are the operations team. Schedule these activities.

### Weekly (30 minutes)

- Review error dashboard — are there recurring errors?
- Check monitoring alerts — any unresolved notifications?
- Quick application health check — does the core flow still work?

### Monthly (1-2 hours)

- Run dependency audit: `snyk test`
- Apply non-breaking security patches
- Rotate API keys/tokens approaching expiration
- Update SBOM
- Review hosting/infrastructure costs — are you within budget?

### Quarterly (2-3 hours)

- Review usage patterns — what are users doing? What are they requesting?
- Performance comparison to last quarter
- Prioritize post-MVP backlog based on real user signals
- Infrastructure cost trend review

### Biannually (3-4 hours)

- Full dependency audit — identify deprecated packages, plan version upgrades
- Re-run Phase 3 security and performance audit
- Verify AI provider terms have not changed in ways that affect compliance
- Review platform requirements (SDK versions, OS support, app store policies)
- **(Organizational)** Insurance/AI terms verification with broker and legal

Expect 2-4 hours/week for the first 3 months post-launch. It stabilizes to 1-2 hours/week (50-80 hours/year per application). Maintenance is bursty — a security advisory can consume a full day, and then nothing happens for two weeks.

**Scaling warning:** At 10 applications, maintenance alone is a half-time job. If you are managing a portfolio, track hours per application. If total maintenance consistently exceeds your available hours, either graduate applications to engineering teams or stop taking new projects.

### When to Graduate

The Solo Orchestrator model has limits. If any of these triggers are met, the application needs a conventional engineering team:

| Trigger | Threshold |
|---|---|
| Active user count | >10,000 |
| Sustained maintenance demand | >4 hours/week for 3+ consecutive months |
| Enterprise system integrations | >3 |
| Business criticality | Designated business-critical by Application Owner |
| Compliance scope change | Application comes under SOC 2, HIPAA, PCI-DSS, or similar |

See the [Governance Framework](framework/governance-framework.md) for the graduation transition plan.

---

## 8. Troubleshooting & FAQ

**"The agent is asking me questions I already answered in the Intake."**

Your Intake is incomplete or vague in that area. Re-read the specific section the agent is asking about. If you wrote "improve efficiency" instead of a concrete problem statement, the agent cannot proceed without clarification. Fix the Intake, then re-provide it.

---

**"The agent wants to add features not in the MVP Cutline."**

Tell it no. Reference the Product Manifesto: "The MVP Cutline is defined in the Manifesto. Do not add features beyond it." If the agent persists, check whether the feature is an implicit dependency of something you did request (e.g., authentication is required for user-specific data but you did not list it).

---

**"A security scan found a Critical finding."**

Fix it before proceeding. Do not skip, defer, or accept risk on Critical findings. The framework has no bypass for this. If the fix requires an architecture change, return to the appropriate phase.

---

**"I can't get approval from IT Security / the sponsor is unavailable."**

You wait. The framework does not have a bypass for organizational approvals. If the delay is long, escalate through the escalation chain defined in Section 8.3 of your Intake. Document the delay in APPROVAL_LOG.md.

---

**"I'm stuck between phases."**

Re-read the Builder's Guide section for the phase you are leaving and the one you are entering. Check the Intake for missing information that may be blocking the gate. Run the phase completion checklist — an unchecked item is likely the blocker.

---

**"The health check shows missing security tools."**

Install them before starting Phase 2. Semgrep, gitleaks, and Snyk are required for the Build Loop security audits. Without them, the per-feature security checks cannot run and findings will accumulate.

```bash
# macOS
brew install semgrep gitleaks
npm install -g snyk

# Linux / WSL
pip install semgrep
# gitleaks: download from https://github.com/gitleaks/gitleaks/releases
npm install -g snyk
```

---

**"My project is too complex for one person."**

If your project needs multiple concurrent developers, microservices, 99.99%+ SLA, or regulated-industry compliance (SOC 2, HIPAA, PCI-DSS), it is not a Solo Orchestrator project. See "What This Is Not" in the [README](../README.md).

---

**"The context health check shows the agent has drifted."**

Start a fresh session. Provide the current `PROJECT_BIBLE.md`, the last 3-4 files you were working on, and the message: "We are continuing Phase 2. Here is current state." Do not try to correct a drifted agent in-session — it is faster to restart.

---

**"I want to change the architecture mid-Phase 2."**

This is expensive. The Project Bible is the point of no return for a reason. If the architecture is fundamentally wrong, return to Phase 1, revise the Bible, and get it re-approved. All Phase 2 work built on the old architecture may need to be redone. If the change is minor (swapping a library, adjusting a pattern), document it as an Architecture Decision Record and update the Bible.

---

**"How do I handle a long-running project across many Claude Code sessions?"**

Each session, provide the current `PROJECT_BIBLE.md` as context. The Bible is the single source of truth for the project's architecture, data model, and decisions. If you have configured the Qdrant MCP server, the agent can also access persistent semantic memory from previous sessions. Without Qdrant, the Bible plus the last few active source files is sufficient context for the agent to resume.

---

**"The CI pipeline failed on first push."**

Review the error. Common causes: missing secrets in GitHub (API keys, tokens), language version mismatch between your machine and the CI runner, or a dependency that requires authentication. Fix the pipeline before entering the Build Loop — a broken CI pipeline means you have no automated safety net.

---

**"I'm an organizational user. Can I start Phase 0 while the pre-conditions are 'in progress'?"**

No. The Governance Framework requires all 6 pre-conditions to be resolved — not "in progress" — before Phase 0 begins. If approvals are taking time, use the waiting period to refine your Intake. A more detailed Intake produces better output in Phase 0.

---

**"How do I know which Platform Module to use?"**

Pick the primary surface where users interact with your application. If it is a website or web app, use Web. If it is a native application installed on Windows/macOS/Linux, use Desktop. If it is distributed through app stores or installed on phones/tablets, use Mobile. If it is a command-line tool, no Platform Module is needed — the core Builder's Guide works standalone for CLI projects.

---

**"What if I need features from multiple Platform Modules?"**

Pick the primary platform and use its module. Cross-platform concerns (e.g., a web app with a companion mobile app) are addressed in the architecture selection step of Phase 1, where the agent considers your target platforms from the Intake. You can reference multiple Platform Modules during Phase 1, but the project tracks one primary module.

---

## Quick Reference: What You Produce at Each Phase

| Phase | Key Output Files | Decision Gate |
|---|---|---|
| Pre-Phase 0 | Completed `PROJECT_INTAKE.md`, `APPROVAL_LOG.md` (organizational pre-conditions) | Intake checklist passes |
| Phase 0 | `PRODUCT_MANIFESTO.md` | Approve Manifesto |
| Phase 1 | `PROJECT_BIBLE.md`, `CONTRIBUTING.md`, Architecture Decision Records | Approve Bible |
| Phase 2 | Working codebase, test suite, `CHANGELOG.md`, interface docs, ADRs | All features built, all checks pass |
| Phase 3 | `docs/test-results/*`, SBOM, Privacy Policy (if applicable), user documentation | Approve go-live |
| Phase 4 | `HANDOFF.md`, `RELEASE_NOTES.md`, `docs/INCIDENT_RESPONSE.md`, monitoring config | Go-live smoke test passes |

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

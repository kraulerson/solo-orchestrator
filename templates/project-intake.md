# Solo Orchestrator — Project Intake Template

## Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-004-INTAKE |
| **Version** | 1.0 |
| **Classification** | Project Initialization Template |
| **Date** | __DATE__ |
| **Companion Documents** | SOI-002-BUILD v1.0 (Builder's Guide), SOI-003-GOV v1.0 (Enterprise Governance Framework) |

---

## Purpose

This template collects every decision, constraint, and context variable that the AI agent needs to execute the Solo Orchestrator methodology with maximum autonomy. Fill it out completely before starting Phase 0. Incomplete sections will force the agent to stop and ask — every blank field is a round-trip.

### How This Document Flows Into the Process

The Intake is the primary input to the Builder's Guide. Here's where each section goes:

| Intake Section | Consumed By | Purpose |
|---|---|---|
| **1. Project Identity** | Phase 0 initialization, Platform Module selection | Names the project, sets the track, identifies which Platform Module the agent loads |
| **2. Business Context** | Phase 0 Steps 0.1-0.2 | The agent validates and expands this into the FRD and User Journey — it doesn't re-discover it |
| **3. Constraints** | Phase 0 and Phase 1 | Timeline, budget, and user targets constrain architecture and scope |
| **4. Features & Requirements** | Phase 0 Steps 0.1, 0.4 | The agent expands logic triggers and failure states, flags gaps, produces the Manifesto |
| **5. Data & Integrations** | Phase 0 Step 0.3, Phase 1 Step 1.4 | Drives the Data Contract, data model design, and third-party integration architecture |
| **6. Technical Preferences** | Phase 1 Steps 1.2-1.6 | Hard constraints and preferences feed directly into architecture proposals; Competency Matrix determines where automated tooling is mandatory |
| **7. Revenue Model** | Phase 0 Step 0.5, Phase 1 Step 1.2 | Hosting/distribution cost ceiling constrains architecture; pricing model shapes feature decisions |
| **8. Governance Pre-Flight** | Enterprise Governance Framework pre-conditions | Maps directly to the organizational approvals required before Phase 0 can begin |
| **9. Accessibility & UX** | Phase 1 Step 1.5, Phase 3 Step 3.4 | Architectural constraints from Day 1, not Phase 3 afterthoughts |
| **10. Distribution & Operations** | Phase 4, Platform Module | Distribution channels, monitoring, update strategy — platform-dependent |
| **11. Known Risks** | Phase 1 Step 1.3 | Additional inputs for the Iron Logic Stress Test |

The more complete the Intake, the more autonomously the agent can work. Where the Intake is vague or incomplete, the Builder's Guide prompts shift from validation to discovery — the agent will ask targeted questions instead of proposing options it doesn't have enough context to evaluate.

### How to Use This Document

You can fill this out using the **intake wizard** (`bash scripts/intake-wizard.sh`) or by **editing this file directly**. The wizard offers an interactive walkthrough and tracks your progress. Either approach works, but be aware of the difference:

1. Fill out every section. Mark fields N/A where they genuinely don't apply — don't leave blanks.
2. For organizational deployments, complete the Governance Pre-Flight (Section 8) before starting. This section maps to the Enterprise Governance Framework pre-conditions.
3. Once complete, provide this document to the AI agent at the start of Phase 0 with the instruction: "This is the Project Intake. Use it as the primary constraint for all phases. Do not suggest features, architectures, or tooling that contradict it."
4. The agent will use this to generate the Product Manifesto (Phase 0) and Project Bible (Phase 1) without stopping to ask for information that should already be decided.

> **If editing manually:** Section 1 fields (project name, platform, language, track) and Section 8 (governance mode) were used during init to generate your CI pipeline, release pipeline, platform module, and phase gate rules. If you change these fields here, you must also run the reconfigure script to update the generated files:
>
> ```bash
> bash scripts/reconfigure-project.sh --field <field> --old <old_value> --new <new_value>
> ```
>
> Supported fields: `name`, `platform`, `language`, `track`, `deployment`. The intake wizard handles this automatically — manual editing does not.

---

## 1. Project Identity

| Field | Value |
|---|---|
| **Project name** | |
| **Project codename** (if different from public name) | |
| **One-sentence description** | _What does this do, in plain language?_ |
| **Project track** | Light / Standard / Full _(see Builder's Guide: Process Right-Sizing)_ |
| **Platform type** | Web / Desktop / Mobile / CLI / Other: ______ |
| **Platform Module** | SOI-PM-WEB / SOI-PM-DESKTOP / SOI-PM-MOBILE / None (new platform) |

> **Mobile (SOI-PM-MOBILE v1.0)** — The mobile Platform Module covers React Native (Expo), Flutter, Swift (iOS), and Kotlin (Android) with architecture patterns, offline-first guidance, code signing, app store submission, and testing.
| **Target platforms** | _e.g., "Windows 10+, macOS 12+, Ubuntu 22.04+" or "Web (all modern browsers)" or "iOS 16+, Android 13+"_ |
| **Is this a personal project or organizational deployment?** | Personal / Organizational |
| **Repository URL** (if already created) | |
| **Git host** | _github / gitlab / bitbucket / other_ |
| **Repository visibility** | _private / public_ (org mode forces private) |

---

## 2. Business Context

### 2.1 The Problem

_What specific problem does this solve? Be concrete — not "improve efficiency" but "the finance team spends 6 hours/week manually reconciling invoices from 3 systems into a single spreadsheet."_

```
[Write the problem statement here]
```

### 2.2 Who Has This Problem

| Field | Value |
|---|---|
| **Primary user persona** | _Job title, technical skill level, what they're trying to accomplish_ |
| **Secondary personas** (if any) | |
| **How do they solve this problem today?** | _Spreadsheet, manual process, different tool, they don't_ |
| **What's wrong with the current solution?** | |

### 2.3 Success Criteria

_How will you know this project succeeded? Define measurable outcomes, not feelings._

| Metric | Target | How Measured |
|---|---|---|
| _Example: Time spent on weekly reconciliation_ | _Reduced from 6 hours to <1 hour_ | _User self-report after 4 weeks_ |
| | | |
| | | |
| | | |

### 2.4 What This Is NOT

_List 3-5 things that sound related but are explicitly out of scope. This prevents the agent from scope-creeping into adjacent problems._

1. 
2. 
3. 
4. 
5. 

---

## 3. Constraints

### 3.1 Timeline

| Field | Value |
|---|---|
| **Target MVP date** | |
| **Hard deadline?** | Yes / No — _If yes, what happens if missed?_ |
| **Orchestrator availability** | _Hours/week dedicated to this project. Be honest — "as time allows" means "unpredictable."_ |
| **Blocked time or interleaved?** | _Dedicated half/full days, or squeezed between other work?_ |

### 3.2 Budget

| Field | Value |
|---|---|
| **Monthly infrastructure ceiling** | _Maximum acceptable hosting/tooling cost per month_ |
| **One-time budget** (if any) | _For domain, trademark, paid tools, pen testing, etc._ |
| **AI subscription** | _Already have / Need to provision. Consumer or commercial?_ |
| **Who approves spending?** | _Name and role, or "self" for personal projects_ |

### 3.3 Users

| Field | Value |
|---|---|
| **Users at launch** | _Number and who they are_ |
| **Users at 6 months** | |
| **Users at 12 months** | |
| **Internal only or external?** | Internal / External / Both |
| **Geographic distribution** | _Single office, national, international? This drives data sovereignty._ |

---

## 4. Features & Requirements

### 4.1 Must-Have Features (MVP)

_For each feature, define the business logic trigger and the failure state. If you can't articulate "If [condition], the system must [action]" — the feature isn't defined well enough to build._

| # | Feature | Business Logic Trigger | Failure State |
|---|---|---|---|
| 1 | | If [condition], the system must [action] and output [result] | What happens when input is invalid, service is unavailable, or user abandons? |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | | | |
| 7 | | | |
| 8 | | | |

### 4.2 Should-Have Features (Post-MVP v1.1)

_Features that enhance the MVP but are not required for first usable release._

1. 
2. 
3. 
4. 
5. 

### 4.3 Will-Not-Have Features (Explicit Exclusions)

_Things that sound related but the agent must NOT build or suggest._

1. 
2. 
3. 

---

## 5. Data & Integrations

### 5.1 Data Inputs

_What data does the user provide or the system ingest?_

| Input | Data Type | Validation Rules | Sensitivity | Required? |
|---|---|---|---|---|
| _Example: Employee name_ | _Text_ | _2-100 chars, no special chars except hyphen/apostrophe_ | _PII_ | _Yes_ |
| | | | | |
| | | | | |
| | | | | |
| | | | | |

**Sensitivity classifications:** Public, Internal, Confidential, PII, Financial, Health/Medical, Regulated

### 5.2 Data Outputs

_What does the user receive from the system?_

| Output | Format | Latency Expectation |
|---|---|---|
| _Example: Reconciliation report_ | _PDF download_ | _<10 seconds_ |
| | | |
| | | |

### 5.3 Third-Party Integrations

_Every external API or data source the application needs to connect to._

| Service | What Data We Send/Receive | Auth Method | Fallback if Unavailable | Existing Account? |
|---|---|---|---|---|
| | | | | |
| | | | | |
| | | | | |

### 5.4 Data Persistence

| Question | Answer |
|---|---|
| **What data must persist across sessions?** | |
| **What data can be ephemeral (browser/device only)?** | |
| **Expected data volume at 12 months** | _Rows, storage size, or "small/medium/large"_ |
| **Data retention requirements** | _Keep forever, X months, regulatory requirement?_ |
| **Backup requirements** | _Daily, real-time, or "whatever the platform default is"_ |

---

## 6. Technical Preferences

### 6.1 Orchestrator Technical Profile

| Field | Value |
|---|---|
| **Languages you know well** | _e.g., JavaScript/TypeScript, Python, Go_ |
| **Frameworks you've used** | _e.g., React, Next.js, Express, Django_ |
| **Languages/frameworks you're willing to learn** | |
| **Languages/frameworks you refuse to use** | |
| **Database experience** | _PostgreSQL, MySQL, SQLite, MongoDB, Supabase, etc._ |
| **DevOps experience level** | _None / Basic (can deploy to PaaS) / Intermediate / Advanced_ |
| **Mobile development experience** | _None / Some / Experienced. Native or cross-platform?_ |

### 6.2 Competency Matrix

_For each domain, answer honestly: "Can I look at the AI's output and reliably determine if it's correct?"_

| Domain | Self-Assessment | Automated Tooling Required? |
|---|---|---|
| Product/UX Logic | Yes / Partially / No | |
| Frontend Code (HTML/CSS/JS) | Yes / Partially / No | |
| Backend / API Design | Yes / Partially / No | |
| Database Design & Queries | Yes / Partially / No | |
| Security (Auth, Injection, IDOR) | Yes / Partially / No | |
| DevOps / Infrastructure | Yes / Partially / No | |
| Accessibility (WCAG) | Yes / Partially / No | |
| Performance Optimization | Yes / Partially / No | |
| Mobile (iOS/Android) | Yes / Partially / No | |

_Every "Partially" or "No" means automated tooling is mandatory in Phase 3. The agent will factor this into architecture selection and testing strategy._

### 6.3 Development Environment

| Field | Value |
|---|---|
| **Primary development machine** | _OS, specs if relevant_ |
| **Secondary machines** (if any) | |
| **IDE/Editor** | _VS Code, Cursor, other_ |
| **Docker available?** | Yes / No |
| **Node.js version** | |
| **Python version** (if applicable) | |
| **Claude Code installed?** | Yes / No / Need to install |
| **AI subscription tier** | _Claude Max, Claude Enterprise, API, other_ |

### 6.4 Architecture Preferences & Constraints

_These are preferences, not mandates. The agent will respect hard constraints but may recommend against soft preferences with justification. Fields vary by platform — fill in what applies to your project type._

**All Platforms:**

| Field | Value | Hard Constraint or Preference? |
|---|---|---|
| **Primary language** | _e.g., TypeScript, Rust, Python, Dart, C#, or "no preference"_ | |
| **Data storage** | _e.g., SQLite, PostgreSQL, Supabase, file system, or "no preference"_ | |
| **Authentication** | _e.g., Supabase Auth, enterprise SSO, local-only, none, or "no preference"_ | |

**Web Applications:**

| Field | Value | Hard Constraint or Preference? |
|---|---|---|
| **Frontend framework** | _e.g., Next.js, React + Vite, SvelteKit, or "no preference"_ | |
| **Backend framework** | _e.g., Express, FastAPI, or "no preference"_ | |
| **Hosting** | _e.g., Vercel, Railway, self-hosted, or "no preference"_ | |

**Desktop Applications:**

| Field | Value | Hard Constraint or Preference? |
|---|---|---|
| **UI framework** | _e.g., Tauri, Electron, Flutter Desktop, or "no preference"_ | |
| **Packaging format** | _e.g., installer, portable executable, or "no preference"_ | |
| **Auto-update strategy** | _e.g., built-in updater, manual download, or "no preference"_ | |
| **Offline requirement** | _Fully offline / Offline with optional sync / Requires network_ | |

**Mobile Applications:**

| Field | Value | Hard Constraint or Preference? |
|---|---|---|
| **Framework** | _e.g., React Native, Flutter, Expo, native, or "no preference"_ | |
| **Minimum OS version** | _e.g., iOS 16+, Android 13+_ | |
| **App store distribution** | _Yes / No / Eventually_ | |
| **Offline requirement** | _Offline tolerant (graceful errors) / Offline capable (cached reads, queued writes) / Offline first (full functionality offline)_ | |
| **Device API requirements** | _e.g., Camera, GPS/Location, Bluetooth, NFC, Biometrics, Barcode scanner, Push notifications, Background sync_ | |
| **Biometric authentication** | _Yes (session unlock) / Yes (primary auth) / No / "no preference"_ | |

**Cross-Cutting:**

| Field | Value | Hard Constraint or Preference? |
|---|---|---|
| **Monorepo or separate repos?** | | |
| **Web + Desktop, Web + Mobile, or single platform?** | | |

### 6.5 Existing Infrastructure to Integrate With

_Anything the application must connect to or comply with._

| System | Details | Integration Required? |
|---|---|---|
| **SSO / Identity Provider** | _e.g., Okta, Azure AD, Google Workspace_ | Yes / No / N/A |
| **Logging / SIEM** | _e.g., Datadog, Splunk, ELK_ | Yes / No / N/A |
| **Monitoring** | _e.g., Datadog, New Relic, Grafana_ | Yes / No / N/A |
| **Data Warehouse** | _e.g., Snowflake, Databricks, BigQuery_ | Yes / No / N/A |
| **Backup Infrastructure** | _e.g., enterprise backup policy_ | Yes / No / N/A |
| **CI/CD Platform** | _GitHub Actions, GitLab CI, Azure DevOps_ | Yes / No / N/A |
| **Repository Platform** | _GitHub, GitLab, Azure DevOps_ | Yes / No / N/A |
| **Other** | | |

---

## 7. Revenue Model (Standard+ Track — skip for internal tools)

| Field | Value |
|---|---|
| **Pricing model** | _Freemium / Subscription / Usage-based / One-time / N/A_ |
| **Target price point** | |
| **Competitive price range** | |
| **Per-user cost estimate** (hosting, API calls, storage) | |
| **Break-even user count** | |
| **Hosting cost ceiling at launch** | |
| **Hosting cost ceiling at 1,000 users** | |
| **Hosting cost ceiling at 10,000 users** | |

---

## 8. Governance Pre-Flight (Organizational Deployments Only)

_Skip this section for personal projects. For organizational deployments, every field must be completed or marked "In Progress" with an expected completion date. Phase 0 cannot begin until all "Blocking" items are resolved._

**Governance Mode:** Production / Sponsored POC / Private POC

> **If POC mode:** This project operates under POC constraints — no production deployment, no real user data, no external users. Deferred pre-conditions must be resolved before production. Upgrade with: `scripts/upgrade-project.sh --to-production`

### 8.1 Pre-Conditions

| Pre-Condition | Status | Details | Blocking? |
|---|---|---|---|
| **AI deployment path approved by IT Security** | Not Started / In Progress / Complete | _Commercial API, Enterprise agreement, ZDR, self-hosted?_ | Yes |
| **Insurance confirmation obtained** | Not Started / In Progress / Complete | _Cyber liability, E&O, D&O cover AI-generated code?_ | Yes |
| **Liability entity designated** | Not Started / In Progress / Complete | _Which entity bears liability — subsidiary or parent?_ | Yes |
| **Project sponsor assigned** | Not Started / In Progress / Complete | _Name:_ | Yes |
| **Backup maintainer designated** | Not Started / In Progress / Complete | _Name:_ | Yes |
| **ITSM ticket filed / portfolio registered** | Not Started / In Progress / Complete | _Ticket #:_ | Yes |
| **Exit criteria defined** | Not Started / In Progress / Complete | | Yes |
| **Orchestrator time allocation approved** | Not Started / In Progress / Complete | _Hours/week, blocked or interleaved_ | Yes |

### 8.2 Approval Authorities

| Gate | Approver Name | Approver Role |
|---|---|---|
| **Phase 0 → Phase 1** (business justification) | | |
| **Phase 1 → Phase 2** (architecture approval) | | |
| **Phase 3 → Phase 4** (go-live approval) | | |

### 8.3 Escalation Chain

| Level | Name | Role | Contact |
|---|---|---|---|
| 1 (first escalation) | | | |
| 2 | | | |
| 3 (final authority) | | | |

### 8.4 Compliance Screening

_Complete this screening with the project sponsor. Mark each question Yes/No and complete the action if Yes._

| Question | Yes/No | Required Action | Status |
|---|---|---|---|
| Does this application process data used in financial reporting? | | Route through SOX IT general controls | |
| Does this application handle payment card data (even masked)? | | PCI scoping assessment required | |
| Does this application collect personal data from users in multiple states or internationally? | | Legal review for applicable privacy laws | |
| Are any users or subsidiaries in the EU? | | EU AI Act classification + data sovereignty assessment | |
| Does any subsidiary operate in a sanctioned jurisdiction? | | OFAC screening | |
| Is data subject to records retention requirements? | | Define retention periods and deletion procedures | |
| Will the deployed application include AI-powered features for end users? | | EU AI Act classification for deployed product | |
| Does your organization require penetration testing for all production applications? | | Schedule pen test for Phase 3 | |

### 8.5 Exit Criteria

| Outcome | Definition | Decision Maker |
|---|---|---|
| **Success** (proceed to scale) | _e.g., "MVP deployed, handoff test passed, actual hours within 20% of estimate"_ | |
| **Conditional** (proceed with modifications) | _e.g., "MVP works but took 2x projected hours — evaluate methodology adjustments"_ | |
| **Failure** (stop) | _e.g., "Quality unacceptable, security findings unresolvable, or Orchestrator unable to evaluate AI output"_ | |

---

## 9. Accessibility & UX Constraints

| Field | Value |
|---|---|
| **Accessibility requirements** | _WCAG AA, Section 508, organizational standard, or "Lighthouse ≥90"_ |
| **Color vision deficiency considerations** | _Yes / No — If yes: never rely on color alone for meaning. Use shape, position, text labels, patterns, or icons._ |
| **Supported browsers** | _e.g., "last 2 versions of Chrome, Firefox, Safari, Edge" or "Chrome only (internal tool)"_ |
| **Mobile responsive required?** | Yes / No |
| **Supported devices** | _Desktop only, desktop + tablet, desktop + tablet + phone_ |
| **Branding / style guide** | _URL or description, or "none — agent's discretion"_ |
| **Dark mode required?** | Yes / No / Nice-to-have |

---

## 10. Distribution & Operations Preferences

**All Platforms:**

| Field | Value |
|---|---|
| **Notification preferences for alerts** | _Email, SMS, Slack, PagerDuty, other_ |
| **Uptime expectation** | _"Best effort" / 99.9% / 99.99%+ (if 99.99%+, this project is not a Solo Orchestrator candidate)_ |
| **Environment strategy** | _Production only, or dev + staging + production?_ |

**Web Applications:**

| Field | Value |
|---|---|
| **Domain name** (if already acquired) | |
| **SSL certificate** | _Platform-provided auto-SSL or organizational cert?_ |
| **Maintenance window preferences** | _Any restrictions on deployment timing?_ |

**Desktop Applications:**

| Field | Value |
|---|---|
| **Distribution channels** | _GitHub Releases, direct download, Homebrew, winget, Snap/Flatpak, app stores, other_ |
| **Code signing** | _Required now / Deferred to post-MVP / Not needed_ |
| **Code signing certificates** (if required) | _Already have / Need to acquire. Apple Developer ($99/yr), Windows EV cert ($200-500/yr)_ |
| **Auto-update mechanism** | _Framework built-in / Manual download / Package manager / Deferred_ |
| **Minimum supported OS versions** | _e.g., Windows 10+, macOS 12+, Ubuntu 22.04+_ |
| **Installer format preferences** | _e.g., MSI, NSIS exe, DMG, AppImage, or "whatever the framework defaults to"_ |

**Mobile Applications:**

| Field | Value |
|---|---|
| **Distribution** | _App Store / Google Play / Both / Enterprise sideload_ |
| **Developer accounts** | _Already have / Need to create. Apple ($99/yr), Google ($25 one-time)_ |
| **Beta testing** | _TestFlight (iOS), Play internal track (Android), both_ |

---

## 11. Known Risks & Concerns

_Anything the agent should know that doesn't fit elsewhere. Technical debt you're aware of going in, political sensitivities, dependencies on other projects, timing constraints, previous failed attempts at solving this problem, etc._

```
[Write any additional context here]
```

---

## 11.5. Testing & Bug Tracking

| Field | Value |
|---|---|
| **Testing interval** | _Every N features (default: 2). How many features to build before pausing for a UAT testing session._ |
| **Bug tracking tool** | GitHub Issues / Linear / Jira / BUGS.md / Other: ______ |
| **Human tester count** | _Default: 1 (you, the developer). If >1, testers receive a test template per session._ |
| **Beta tester coordination** (if >1 tester) | _How to reach testers (email, Slack, Discord). How they receive builds (TestFlight, staging URL, GitHub pre-release, download link)._ |
| **Bug severity SLAs** (Full UAT level only) | SEV-1: ___h / SEV-2: ___d / SEV-3: ___d _(default: SEV-1 24h, SEV-2 7d, SEV-3 best effort)_ |

> **How this is used:** The agent pauses construction every N features to run a UAT testing session. Agent testers run automated, exploratory, and cross-platform tests in parallel while you test manually. Bugs are compiled, triaged, and fixed before construction resumes. See Steps 2.7-2.9 in the Builder's Guide.

---

## 12. Tooling Configuration

> This section is auto-populated by `init.sh` based on the tool installation matrix. It records what was installed, what needs manual setup, and what is deferred to later phases. Claude reads this to understand the available tooling environment.
>
> If this section is empty, run `init.sh` or manually populate `.claude/tool-preferences.json`.

<!-- AUTO-GENERATED BY INIT.SH — do not edit above this line -->

---

## 13. Agent Initialization Prompt

_Once this template is complete, provide it to the AI agent at the start of Phase 0 along with the Builder's Guide. Copy and customize the bracketed sections._

_The Builder's Guide contains dual-path prompts for Phase 0 and Phase 1 — one for Intake-first (validation and expansion) and one for conversational discovery (without Intake). By providing this Intake, you are activating the Intake-first path. The agent will validate, expand, and challenge your inputs rather than discovering them from scratch._

```
You are the AI execution layer for a Solo Orchestrator project. I am the
Orchestrator. I define intent, constraints, and validation. You provide
architecture, code, and documentation within the constraints I set.

ATTACHED:
1. Project Intake Template (this document) — your primary constraint
2. Solo Orchestrator Builder's Guide v1.0 — your process reference
3. Platform Module: [WEB / DESKTOP / MOBILE] — your platform-specific
   reference for architecture, tooling, testing, and distribution

DOCUMENT RELATIONSHIP:
- The Intake is the DATA SOURCE. It contains my decisions, constraints,
  requirements, technical profile, and (if organizational) governance
  pre-conditions.
- The Builder's Guide is the PROCESS. It defines the phases, steps,
  quality gates, and remediation procedures you follow.
- The Platform Module is the PLATFORM IMPLEMENTATION GUIDE. When the
  Builder's Guide shows a ⟁ PLATFORM MODULE callout, reference the
  attached Platform Module for platform-specific instructions.
- Where the Builder's Guide shows "With Intake" prompts, use those.
  They direct you to validate and expand my Intake data rather than
  re-discovering it.

RULES:
- The Project Intake is the governing constraint. Do not suggest features,
  architectures, or tooling that contradict it.
- The Builder's Guide defines the phase-by-phase process. Follow it.
- The Platform Module defines platform-specific implementation. Follow it
  at every ⟁ callout point.
- If the Intake specifies a hard constraint, respect it absolutely.
- If the Intake specifies a preference, you may recommend against it with
  justification, but defer to my decision.
- If the Intake leaves a field as "no preference," make a recommendation
  based on the constraints and explain your reasoning.
- If the Intake leaves a field blank or incomplete, flag it immediately
  and ask for the specific missing information before proceeding past
  the step that requires it.
- For any domain where my Competency Matrix (Section 6.2) says "Partially"
  or "No," default to the most conservative, well-documented option and
  ensure automated validation tooling covers that domain.
- Do not add features not in the MVP Cutline (Section 4.1).
- Do not suggest dependencies without justification.
- Every feature must have tests before implementation.
- Flag any conflict between the Intake constraints and technical feasibility
  immediately — do not silently work around it.

ACCESSIBILITY (from Section 9):
[Copy any specific requirements here, e.g., "Color vision deficiency:
never rely on color alone for meaning. Use shape, position, text labels,
patterns, or icons."]

PROJECT TRACK: [Light / Standard / Full]
PLATFORM: [Web / Desktop / Mobile / Other]
TARGET PLATFORMS: [e.g., Windows 10+, macOS 12+, Ubuntu 22.04+]

BEGIN: Execute Phase 0, Step 0.1 using the "With Intake — Validation
Prompt" path from the Builder's Guide. Use Sections 2 and 4 of the
Intake as the primary data source. Generate the Functional Requirements
Document by expanding my business logic triggers and failure states.
Where I've been vague, make it specific and flag for my review. Where
I've been contradictory, identify the contradiction and ask me to resolve
it. Where I've omitted an implicit dependency (e.g., features that
require authentication but I didn't list authentication), flag it as a
recommended addition.
```

---

## Checklist Before Starting

- [ ] Every field is filled in or explicitly marked N/A
- [ ] Must-Have features all have business logic triggers (If X, then Y)
- [ ] Must-Have features all have failure states defined
- [ ] Will-Not-Have list has at least 3 items
- [ ] Data sensitivity classifications are assigned to all inputs
- [ ] Competency Matrix is completed honestly
- [ ] Budget constraints are realistic (not aspirational)
- [ ] Timeline includes Orchestrator availability, not just calendar dates
- [ ] For organizational deployments: all Section 8 "Blocking" items are Complete
- [ ] Success/failure exit criteria are defined and a decision-maker is named
- [ ] This document has been saved as `PROJECT_INTAKE.md` in the project repository

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

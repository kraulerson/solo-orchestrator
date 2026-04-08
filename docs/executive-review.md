# The Solo Orchestrator Framework

## Executive Review — Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-001-EXEC |
| **Version** | 1.0 |
| **Classification** | Executive Briefing |
| **Date** | 2026-04-02 |
| **Audience** | CIO, VP of Engineering, Director of Software Development |
| **Framework Documents** | See Section XI — Document Suite |

---

## I. Executive Summary

### What This Is

The Solo Orchestrator Framework is a structured software development methodology that enables a single experienced technologist to build MVP-quality applications with a clear path to production, using AI Large Language Models as the execution layer. The technologist acts as Product Owner, Lead Architect, and QA Director. The AI proposes architecture, generates logic, and writes code within constraints defined and validated by the human operator. The framework produces functional, tested, security-scanned MVPs — production deployment requires additional hardening, operational readiness, and governance completion.

The framework currently supports **web, desktop, and mobile applications** with Platform Modules that guide projects from MVP through production readiness. The core methodology is platform-agnostic — additional platforms (CLI, embedded) can be added through new Platform Modules as they mature.

The framework is a phase-gated process consisting of five stages: Product Discovery (defining requirements), Architecture & Planning (selecting technology), Construction (building features), Validation & Hardening (security and quality assurance), and Release & Maintenance (distribution and ongoing support). Each phase produces documented artifacts that gate entry into the next phase. No code is deployed without passing automated testing, security scanning, and human review.

The framework is **modular** — the core methodology is platform-agnostic, with platform-specific guidance (architecture, tooling, testing, distribution) provided through interchangeable Platform Modules. The same process governs building a web dashboard or a cross-platform desktop application, with platform-specific details handled by the appropriate module.

### What Problem This Solves

Every large organization has a software backlog that will never be built. The projects are too small to justify a full development team, too complex for no-code platforms, and too specific for off-the-shelf SaaS. They age in Jira while business units find workarounds — spreadsheets, manual processes, or unauthorized SaaS purchases that create shadow IT risk.

The Solo Orchestrator model addresses this gap. A single qualified technologist can take a concept from idea to validated MVP in weeks at a fraction of the cost of a traditional team, with a structured path to production when the project proves its value. Platform Modules currently support web, desktop, and mobile applications.

### Current Maturity

This is the initial release of the framework. It has been developed and used by the author for personal projects. It has not yet been validated through a formal organizational pilot as described in Section X. The framework should be evaluated as a structured methodology ready for pilot testing, not as a field-proven practice. The pilot evaluation process defined in this document is the mechanism for validation.

### What This Is Not

This framework does not replace enterprise engineering teams. It is not appropriate for:

- **Compliance-regulated systems** requiring SOC 2, HIPAA, PCI-DSS, or FedRAMP certification. These require dedicated security teams and audit processes beyond what a solo builder can validate.
- **High-availability systems** with 99.99%+ uptime SLAs. Solo-maintained systems have a single point of failure at the operator level.
- **Large-scale distributed systems** requiring microservices, message queues, or multi-region deployments. These require dedicated DevOps capacity.
- **Enterprise integration projects** (SAP, Salesforce, custom ERP) where the integration complexity exceeds the application logic.
- **Multi-tenant SaaS platforms** where data isolation, tenant-specific configuration, and billing integration add architectural complexity beyond a solo builder's capacity.

The framework is designed for internal tools, utilities, departmental applications, prototypes, and MVP validation — projects that sit in the backlog because they don't justify a full team.

### How This Differs From "Vibe Coding"

The public narrative around AI-assisted development often describes unstructured coding where a developer asks an AI to generate code and ships whatever comes back. The Solo Orchestrator Framework is the opposite:

- Requirements are formally documented before any technology is selected (Phase 0).
- Architecture decisions are constrained by budget, timeline, and maintenance capacity — not AI suggestion (Phase 1).
- Every feature is built test-first: tests define expected behavior before implementation code is written (Phase 2).
- Security is validated through automated scanning, dependency auditing, and manual review — the same tools used by traditional development teams (Phase 3).
- Release includes automated pipelines, monitoring, alerting, and documented incident response procedures (Phase 4).
- Every phase produces documentation enabling a qualified replacement to resume maintenance without reverse-engineering the codebase.

The AI writes code. The human makes every decision, validates every output, and gates every phase transition.

---

## II. Tooling & Cost

All tools are commercially available and require no custom infrastructure. The environment can be operational within 1-2 business days.

### Core Tools (All Platforms)

**AI Engine:** The framework is built on and tested with **Claude Code (Anthropic)** — $100-$200/month for individual use (Claude Max). For enterprise deployment with company source code, use an approved commercial path: Anthropic API with commercial terms, Claude Enterprise, or cloud-provider deployments (AWS Bedrock, Google Cloud Vertex AI). The operational tooling (agent configuration, plugins, MCP integrations) is Claude Code-specific. The methodology is agent-agnostic. See the Enterprise Governance Framework (Section IX) for vendor dependency analysis and exit path.

**Development Environment:** VS Code or equivalent IDE (free), Git + repository host (GitHub Team $4/user/month, GitLab Self-Managed free, Azure DevOps), Docker (free, optional).

**Quality Assurance & Security:** Semgrep for static security analysis (free), Snyk for dependency vulnerability scanning (free tier), gitleaks for secret detection (free), platform-appropriate license compliance tooling (free), platform-appropriate E2E testing framework (free).

**Monitoring:** Sentry for error tracking (free tier or $26/month), uptime/health monitoring as appropriate for the platform.

### Platform-Specific Tools

Platform-specific tooling (hosting, SDKs, packaging, distribution) varies by project type. Costs:

| Platform | Additional Tooling Cost | Notes |
|---|---|---|
| **Web Applications** | $0-$300/month (hosting, database, CDN) | Scales with traffic. Free tiers available for small projects. |
| **Desktop Applications** | $0-$600/year (code signing certificates) | macOS: $99/year Apple Developer. Windows EV cert: $200-$500/year. Linux: free. Build infrastructure (CI) is the primary cost. |
| **Mobile Applications** | $99-$125/year (store accounts) + hosting for any backend | Apple Developer: $99/year. Google Play: $25 one-time. |

### Monthly Cost Summary (Per Application)

| Scenario | Monthly Cost |
|---|---|
| **Minimum viable** (free tiers, internal tools) | $20–$50 |
| **Standard production** (paid tooling, moderate usage) | $75–$200 |
| **Full production** (paid tiers, code signing, multi-platform CI) | $150–$400 |

The AI subscription is shared across all projects.

---

## III. Human Investment & Timeline

### One-Time Setup

| Activity | Hours |
|---|---|
| Tool accounts, API keys, repository setup | 2-4 |
| Repository security (private repo, branch protection, backup mirroring) | 1-2 |
| AI coding agent installation and configuration | 1-2 |
| CI/CD pipeline template (reusable across projects) | 2-3 |
| Security tooling installation | 1-2 |
| Platform-specific toolchain setup | 2-6 |
| **Total** | **9-19 hours** |

### Per-Project Development

| Phase | Human Hours | Calendar Time |
|---|---|---|
| **Phase 0:** Product Discovery — requirements, user journeys, data contracts | 3-5 | 1-2 days |
| **Phase 1:** Architecture — stack selection, data model, risk analysis, Project Bible | 4-8 | 2-4 days |
| **Phase 2:** Construction — test-first feature building, security audits, documentation | 15-40 | 2-6 weeks |
| **Phase 3:** Validation — integration testing, security hardening, accessibility, performance | 5-12 | 3-7 days |
| **Phase 4:** Release — build, package, distribute, monitor | 3-8 | 1-3 days |
| **Total (experienced Orchestrator)** | **30-73 hours** | **4-10 weeks** |
| **Total (first project, includes ramp-up)** | **50-110 hours** | **8-14 weeks** |

The ranges are wider than single-platform estimates because they span web applications (lower end) through cross-platform desktop applications (upper end). Desktop and embedded applications require more time in architecture selection, platform-specific testing, and build/distribution pipeline setup.

**Note on personnel cost:** The Orchestrator's time is not free. Calculate their fully burdened hourly rate multiplied by allocated hours. The cost advantage comes from one person replacing a team, not from labor being zero. Factor in opportunity cost. For a first-time Orchestrator, the upper ranges apply.

### Ongoing Maintenance

| Activity | Hours | Frequency |
|---|---|---|
| Health check and error review | 0.5 | Weekly |
| Dependency and security audit | 1-2 | Monthly |
| Feature and performance review | 2-3 | Quarterly |
| Architectural review and upgrade planning | 3-4 | Biannually |
| **Annual total (stabilized)** | **50-80 hours** | **~1-2 hours/week** |

Expect 2-4 hours/week for the first 3 months post-launch. Maintenance is bursty. These are per application — at 10 applications, maintenance alone becomes a half-time job.

### Cost Comparison: Solo Orchestrator vs. Traditional Development

| Metric | Traditional (Small Team) | Solo Orchestrator |
|---|---|---|
| Headcount | 2-4 engineers + PM | 1 technologist (partial allocation) |
| Monthly personnel cost | $30,000-$80,000 (dedicated) | Orchestrator's loaded hourly rate × hours + $75-$200 tooling |
| Time to MVP | 8-16 weeks | 4-10 weeks (experienced) / 8-14 weeks (first project) |
| Ongoing maintenance | $15,000-$40,000/month | $75-$200/month tooling + 2-4 hrs/week stabilizing to 1-2 hrs/week |
| Best suited for | Mission-critical, high-scale systems | Internal tools, utilities, prototypes, MVPs |

---

## IV. Process Overview

The framework operates in five phases. Each phase produces documented artifacts that gate entry into the next phase. The Builder's Guide (SOI-002-BUILD v1.0) provides the complete platform-agnostic methodology. Platform Modules provide platform-specific implementation guidance.

### Phase 0: Product Discovery & Logic Mapping

**Duration:** 1-2 days | **Decision gates:** 1 (Manifesto approval)

Define what the product does, who uses it, and how data flows through it before any technology decisions. The **Project Intake Template** (SOI-004-INTAKE) accelerates this phase by collecting requirements, constraints, and the Orchestrator's technical profile upfront, allowing the AI agent to validate and expand rather than discover from scratch.

**Output artifact:** `PRODUCT_MANIFESTO.md`

### Phase 1: Architecture & Technical Planning

**Duration:** 2-4 days | **Decision gates:** 2 (Go/No-Go assessment, Architecture selection)

Select the technology stack constrained by the Product Manifesto, budget, and Orchestrator's maintenance capacity. The **Platform Module** for the target platform provides architecture patterns, framework options, and selection criteria specific to that platform type. Architecture selection includes authentication, observability, data model, build/packaging strategy, and distribution — all as first-class decisions.

**Output artifact:** `PROJECT_BIBLE.md`

### Phase 2: Construction (The "Loom" Method)

**Duration:** 2-6 weeks | **Decision gates:** Per-feature test assertion review

Build features one at a time using test-driven development. Each feature cycle: write tests first → Orchestrator reviews test assertions → AI implements → automated security audit → documentation update → next feature. Context health checks every 3-4 features to detect AI hallucination or drift.

**Output artifacts:** Working codebase, test suite, interface documentation, feature documentation, architecture decision records, `CHANGELOG.md`.

### Phase 3: Validation, Security & UAT

**Duration:** 3-7 days | **Decision gates:** 1 (Go-Live approval)

Assume everything is broken until proven otherwise. Integration testing of the full user journey. Security hardening through automated SAST, dependency auditing, and secret detection — plus platform-specific security checks per the Platform Module. Chaos testing, accessibility auditing, and performance profiling. Cross-platform verification for multi-platform applications.

**Output artifacts:** Test suite, security audit report, performance baselines, SBOM. (Pre-launch preparation steps are executed as part of Phase 3.6 Pre-Launch Preparation — see Builder's Guide Step 3.6.)

### Phase 4: Release & Long-Term Support

**Duration:** 1-3 days (initial) + ongoing | **Decision gates:** 1 (Go-Live verification)

Build, package, and distribute via the platform-appropriate mechanism — web deployment, desktop installers, app store submission, or direct distribution. Rollback and incident response playbook documented before launch. Monitoring and alerting configured. Continuous improvement cadence: monthly security, quarterly feature review, biannual architecture review.

**Output artifacts:** CI/CD configuration, platform-specific build/package pipeline, incident response playbook, monitoring integration, `HANDOFF.md`.

---

## V. Enterprise Governance

Enterprise deployment requires a governance layer that the framework itself does not provide. The **Enterprise Governance Framework** (SOI-003-GOV v1.0) defines this layer in full. Key elements:

**Approval Authority:** Named approvers by role at each phase gate. The Orchestrator cannot approve their own work.

**Escalation Path:** Defined chain when the project exceeds budget/timeline by >20%, scope affects another business unit, or a security finding exceeds the Orchestrator's competency.

**ITSM Integration:** Project registration at Phase 0, change tickets per the organization's change management process, deployment classification.

**Backup Maintainer:** Every project has a designated second technologist with full access who can triage, rollback, and escalate. Monthly sync reviews.

**Portfolio Governance:** For organizations running multiple Solo Orchestrators — mandatory SSO, centralized logging, shared architecture catalog, maximum applications per Orchestrator (5-8 recommended), and graduation criteria for transitioning applications to conventional engineering teams.

**The Project Intake Template** (SOI-004-INTAKE) collects the data these governance controls require. Section 8 of the Intake (Governance Pre-Flight) maps directly to the Governance Framework's pre-conditions.

---

## VI. Repository Security & Data Protection

All repositories must be private with enforced access controls. Branch protection rules are configured on Day 1. A secondary mirror to organization-controlled storage provides backup redundancy.

### AI Service Data Handling

For enterprise source code, require an approved commercial deployment path — not a consumer-tier subscription. Options include: Anthropic's API with commercial terms, Claude Enterprise with contractual data protections, or cloud-provider deployments (AWS Bedrock, Google Cloud Vertex AI) with enterprise agreements.

For applications handling PII, financial data, or trade secrets: enterprise agreements with zero-data-retention clauses, abstracting sensitive logic from AI context, or self-hosted open-source LLMs. The AI data transmission policy is a mandatory decision at Phase 1, gated by data classification.

### Continuous Documentation

Documentation is a continuous output at every phase. The bus factor for a solo-maintained application is 1. Documentation reduces recovery time but does not eliminate the risk. The backup maintainer requirement (Section V) provides the human safety net.

---

## VII. Legal Considerations

AI-assisted software development introduces legal exposure across multiple domains. **This section identifies risks and mitigation approaches. It is not legal advice, and it is not a substitute for qualified legal counsel. The regulatory landscape for AI-assisted software development is evolving rapidly. Engage corporate counsel before production deployment.**

Detailed legal analysis is in the Enterprise Governance Framework (SOI-003-GOV, Section VIII). Key areas:

1. **Open-Source License Compliance** — Automated CI/CD pipeline checking across direct and transitive dependencies. Build fails on copyleft detection (GPL, AGPL, LGPL, SSPL, EUPL).
2. **AI-Generated Code Ownership** — Copyright protection for AI-generated code is legally unsettled under current U.S. and international law. Human-directed phase gates strengthen copyright claims but do not guarantee protection. Code provenance documentation supports independent creation. Organizations should consult IP counsel before relying on copyright protection for commercially critical code.
3. **Data Privacy Regulations** — GDPR, CCPA/CPRA, and state-level privacy laws addressed through data sensitivity classification (Phase 0), architecture controls (Phase 1), and Privacy Policy (Phase 3). Privacy Policies and Terms of Service generated during the build process must be reviewed by qualified legal counsel before deployment.
4. **Data Sovereignty** — For international subsidiaries: data storage location, processing location, cross-border transfer mechanisms assessed at Phase 1.
5. **EU AI Act** — Separate assessment for AI features in deployed products (not just the development methodology).
6. **Insurance** — Written broker confirmation that cyber liability, E&O, and D&O cover AI-assisted development, including AI-specific exclusion review and coverage for AI training data infringement claims. Gating artifact for Phase 0.
7. **Compliance Screening** — SOX, PCI, GDPR, GLBA, SEC cybersecurity disclosure, OFAC, PHI, and records retention screening completed before Phase 1.
8. **AI Provider Data Processing** — Organizations must verify that their AI provider agreement includes a GDPR-compliant Data Processing Agreement (DPA) and appropriate cross-border transfer mechanisms before any project handling personal data. For commercially sensitive projects, use ZDR or self-hosted models — transmitting trade secrets to a third-party AI provider may undermine trade secret status.

### Platform-Specific Legal Considerations

Desktop and mobile distribution introduces additional legal requirements not present in web applications:

- **Code signing certificates** — Organizational ownership, rotation, and revocation procedures.
- **App store compliance** — Platform-specific guidelines (Microsoft Store, Mac App Store, Google Play, Apple App Store) if distributing through stores.
- **Export controls** — Encryption in desktop applications may trigger export classification requirements.
- **Open-source disclosure** — Desktop and mobile applications bundling open-source code may need attribution notices in the application itself (About dialog, documentation), not just in the repository.

---

## VIII. Risk Assessment

### Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Single point of failure** | High | Designated backup maintainer with full access and monthly sync. Documentation enables continuity. |
| **Security vulnerabilities in AI-generated code** | High | Automated SAST, DAST (where applicable), dependency auditing, secret detection, manual review. Platform-specific security checks per Platform Module. |
| **Incident response** | High | Severity classification, notification chains, containment procedures. Enterprise IR integration. Backup maintainer coverage. |
| **Code transmitted to AI provider** | High | Commercial deployment path required. ZDR or self-hosted for sensitive data. DLP guidelines for AI prompts. |
| **Open-source license contamination** | High | Automated checking (direct + transitive) in CI/CD. Build fails on copyleft. SBOM generation. |
| **Data privacy non-compliance** | High | Data classification in Phase 0. Compliance screening. Jurisdiction-specific review. Privacy Policy before launch. |
| **AI vendor lock-in** | Medium | The Claude Code-specific tooling layer is a deliberate proof-of-concept decision — the methodology is validated on a single vendor before the abstraction layer is built. Core methodology (phases, decision gates, intake template, governance) is agent-agnostic today. Phase 2 workflow accelerators (Superpowers, MCP integrations) and the CLI Setup Addendum are Claude Code-specific and will be retooled for multi-vendor support once the methodology is validated through organizational pilots. Estimated switching cost for the methodology: minimal. Estimated switching cost for the Phase 2 tooling integration: 2-4 weeks per active project. Annual cross-model validation (Section IX of the Governance Framework) keeps the exit path tested and prepares for the multi-vendor phase. |
| **Code quality and performance** | Medium | TDD, automated linting, platform-specific performance auditing. |
| **Intellectual property uncertainty** | Medium | Copyright protection for AI-generated code is legally unsettled. Human-directed phase gates and code provenance documentation strengthen but do not guarantee claims. Organizations should consult IP counsel. The framework does not scan for patent or copyright infringement in generated code. |
| **Portfolio scaling** | Medium | Maximum 5-8 applications per Orchestrator. Quarterly portfolio review. Graduation criteria defined. |
| **Cross-platform inconsistency** | Medium | CI builds and tests on all target platforms. Platform-specific testing checklists per Platform Module. |
| **Platform vendor changes** | Medium | Code signing certificate expiry, app store policy changes, SDK deprecation. Biannual platform review in maintenance cadence. |

---

## IX. Decision Framework

### When to Use Solo Orchestrator vs. Traditional Development

| Criteria | Solo Orchestrator | Traditional Team |
|---|---|---|
| **User count** | <10,000 active users | >10,000 or enterprise SLA |
| **Compliance** | No regulatory certification requirements | SOC 2, HIPAA, PCI-DSS, FedRAMP |
| **Complexity** | Single application, well-defined domain | Multi-system integration, microservices, multi-tenant |
| **Timeline** | Working product needed in <10 weeks | 3-6 month team ramp-up acceptable |
| **Budget** | <$400/month infrastructure | Full engineering team budget available |
| **Strategic value** | Tactical tool, prototype, MVP validation | Core revenue product, competitive differentiator |
| **Maintenance** | 2-4 hours/week acceptable (stabilizing to 1-2) | Dedicated on-call team required |
| **Platform** | Web, desktop, mobile (MVP through production) | Any |

### Recommended Use Cases

- Internal tools solving specific departmental problems (asset trackers, approval workflows, dashboards, reporting tools)
- Cross-platform desktop utilities replacing manual processes or expensive per-seat software
- MVP builds that validate a product concept before committing full engineering headcount
- Prototypes demonstrating feasibility to stakeholders or investors
- Utility applications with well-defined operations and business logic
- Clearing the "small project" backlog that sits unfunded because it doesn't justify a team

---

## X. Pilot Evaluation

For an organization evaluating this model, expect **4-12 weeks to resolve organizational pre-conditions** (insurance confirmation, AI deployment path approval, legal review, stakeholder alignment, ITSM registration). Once pre-conditions are met, the operational pilot setup takes under 48 hours. The pre-condition timeline dominates — do not plan against the 48-hour figure in isolation. The Enterprise Governance Framework (SOI-003-GOV, Section XIV) defines the pre-conditions. The Project Intake Template (SOI-004-INTAKE) collects the required data.

### Pre-Conditions Summary

1. Insurance clearance (written broker confirmation)
2. AI deployment path approved by IT Security
3. Liability entity designated
4. Project sponsor assigned
5. Backup maintainer designated
6. ITSM registration
7. Scope constraint: internal-only, non-critical, no PII
8. Exit criteria defined
9. Orchestrator time allocation approved

### Pilot Timeline

**Day 1 (4-6 hours):** Provision tooling, create repository, install security toolchain. Fill out the Project Intake Template.

**Day 2 (4-6 hours):** Execute Phase 0 (Product Manifesto) and Phase 1 (Architecture, Project Bible) using the Intake-first workflow.

**Weeks 2-6:** Complete Phase 2 construction. Execute Phase 3 validation.

**Weeks 6-10:** Release (Phase 4). Conduct handoff test with the backup maintainer. Evaluate results.

### Evaluation Criteria

Actual hours vs. projected, actual cost vs. projected, defect rate, security scan results, handoff test results, and the Orchestrator's honest assessment of AI output quality and workflow viability.

The pilot is the proof of concept. No methodology document — including this one — substitutes for building something real and evaluating the result.

---

## XI. Document Suite

The Solo Orchestrator Framework consists of the following documents:

### Core Documents

| Document | ID | Purpose | Audience |
|---|---|---|---|
| **Executive Review** (this document) | SOI-001-EXEC v1.0 | High-level overview, business case, risk assessment | CIO, VP of Engineering, Directors |
| **Builder's Guide** | SOI-002-BUILD v1.0 | Platform-agnostic methodology — phases, prompts, quality controls, remediation | Solo Orchestrator |
| **Enterprise Governance Framework** | SOI-003-GOV v1.0 | Approval authorities, compliance, risk management, portfolio governance | CIO, IT Security, Legal, Risk, Audit |
| **Project Intake Template** | SOI-004-INTAKE v1.0 | Structured data collection for autonomous AI agent execution | Solo Orchestrator (fills out), Governance (reviews Section 8) |
| **CLI Setup Addendum** | SOI-005-CLI v1.0 | Claude Code CLI configuration: permissions, Superpowers, MCP servers, CLAUDE.md | Solo Orchestrator |

### Platform Modules

| Module | ID | Scope |
|---|---|---|
| **Web Applications** | SOI-PM-WEB v1.0 | SPAs, full-stack, APIs. Next.js, React, Vercel/Railway/Supabase. |
| **Desktop Applications** | SOI-PM-DESKTOP v1.0 | Windows/macOS/Linux standalone and client-server. Tauri, Electron, Flutter Desktop. |
| **Mobile Applications** | SOI-PM-MOBILE v1.0 | iOS/Android native and cross-platform. React Native (Expo), Flutter, Swift, Kotlin. |

The framework is extensible — new Platform Modules (embedded systems, CLI tools, game development, etc.) can be added without modifying the core documents. Each module follows a standard internal structure: Architecture Patterns → Tooling → Build & Packaging → Testing → Distribution → Maintenance.

### CIO Evaluation Prompt

| Document | ID | Purpose |
|---|---|---|
| **CIO Evaluation Prompt** | SOI-006-EVAL v1.0 | Cross-model LLM evaluation prompt for stress-testing the framework documents |

---

## XII. Next Steps

If this review warrants further evaluation:

1. **Review the Enterprise Governance Framework** (SOI-003-GOV) for the complete organizational control structure.
2. **Obtain insurance confirmation** — this is a hard prerequisite.
3. **Engage corporate counsel** on legal considerations, particularly open-source licensing, AI-generated code ownership, data sovereignty, and platform-specific distribution requirements.
4. **Establish the governance overlay:** Named approvers, backup maintainer, ITSM integration.
5. **Identify a pilot project** from the existing backlog. Select the appropriate Platform Module.
6. **Assign a qualified technologist** — someone with architecture and infrastructure experience who can evaluate AI output critically. This is not a junior developer role.
7. **Complete the Project Intake Template** (SOI-004-INTAKE) for the pilot project. Have governance stakeholders review Section 8.
8. **Define exit criteria** before starting.
9. **Execute the pilot** and evaluate results against projections.
10. **Do not scale** beyond the pilot until results are evaluated and the handoff test is completed.

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

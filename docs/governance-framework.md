# Solo Orchestrator Enterprise Governance Framework

## Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-003-GOV |
| **Version** | 1.0 |
| **Classification** | Enterprise Governance — Executive & Oversight Audiences |
| **Date** | 2026-04-02 |
| **Audience** | CIO, VP of Engineering, IT Security, Legal, Risk & Compliance, Internal Audit |
| **Companion Documents** | SOI-002-BUILD v1.0 — Solo Orchestrator Builder's Guide (technical execution manual) |
| | SOI-004-INTAKE v1.0 — Project Intake Template (structured input for Phase 0 and Phase 1) |
| | SOI-PM-* — Platform Modules (Web, Desktop, Mobile — MVP through production) |

---

## I. Purpose & Scope

This document defines the organizational controls, approval authorities, compliance requirements, and risk management framework for deploying the Solo Orchestrator methodology within an enterprise. It is the governance wrapper around the technical Builder's Guide (SOI-002-BUILD).

The Builder's Guide tells the Orchestrator **how to build.** This document tells the organization **how to authorize, oversee, and govern** what the Orchestrator builds.

**The Project Intake Template** (SOI-004-INTAKE) is the collection mechanism for the data this framework requires. Section 8 of the Intake (Governance Pre-Flight) maps directly to the pre-conditions, approval authorities, compliance screening, and exit criteria defined in this document. The Orchestrator completes the Intake; the governance stakeholders review and approve Section 8 before Phase 0 begins.

**This document is required reading before any organizational deployment.** Personal projects and individual experimentation outside company infrastructure do not require this framework. Any project using company resources, company data, or producing applications used by company employees requires compliance with this document.

---

## II. Executive Summary

### What the Solo Orchestrator Model Is

The Solo Orchestrator Framework is a structured software development methodology that enables a single experienced technologist to build MVP-quality applications with a clear path to production, using AI Large Language Models as the execution layer. The technologist acts as Product Owner, Lead Architect, and QA Director. The AI proposes architecture, generates logic, and writes code within constraints defined and validated by the human operator. The framework produces functional, tested, security-scanned MVPs — production deployment requires additional hardening, operational readiness, and governance completion.

The framework operates in five phases: Product Discovery, Architecture & Planning, Construction, Validation & Hardening, and Production Release & Maintenance. Each phase produces documented artifacts that gate entry into the next phase. No code is deployed without passing automated testing, security scanning, and human review.

### What Problem This Solves

Every large organization has a software backlog that will never be built. The projects are too small to justify a full development team, too complex for no-code platforms, and too specific for off-the-shelf SaaS. They age in Jira while business units find workarounds — spreadsheets, manual processes, or unauthorized SaaS purchases that create shadow IT risk.

The Solo Orchestrator model addresses this gap. A single qualified technologist can take a concept from idea to validated MVP in weeks at a fraction of the cost of a traditional team, with a structured path to production when the project proves its value.

### What This Is Not

This framework does not replace enterprise engineering teams. It is not appropriate for:

- **Compliance-regulated systems** requiring SOC 2, HIPAA, PCI-DSS, or FedRAMP certification.
- **High-availability systems** with 99.99%+ uptime SLAs.
- **Large-scale distributed systems** requiring microservices, message queues, or multi-region deployments.
- **Enterprise integration projects** (SAP, Salesforce, custom ERP) where the integration complexity exceeds the application logic.
- **Multi-tenant SaaS platforms** where data isolation, tenant-specific configuration, and billing integration add architectural complexity beyond a solo builder's capacity.

The framework is designed for internal tools, rapid prototyping, departmental applications, and MVP validation.

---

## III. Financial Analysis

### Cost Comparison: Solo Orchestrator vs. Traditional Development

| Metric | Traditional (Small Team) | Solo Orchestrator |
|---|---|---|
| Headcount | 2-4 engineers + PM | 1 technologist (partial allocation) |
| Monthly personnel cost | $30,000-$80,000 (dedicated) | Orchestrator's loaded hourly rate × hours allocated + $75-$150 tooling |
| Time to MVP | 8-16 weeks | 4-8 weeks (experienced) / 8-12 weeks (first project) |
| Ongoing maintenance | $15,000-$40,000/month | $75-$150/month tooling + 2-4 hrs/week (first 3 months), stabilizing to 1-2 hrs/week |
| Best suited for | Mission-critical, high-scale systems | Internal tools, prototypes, MVPs |

**The Orchestrator's time is not free.** Calculate their fully burdened hourly rate (salary + benefits + overhead) multiplied by allocated hours. The cost advantage comes from one person replacing a team, not from labor being zero. Factor in opportunity cost: hours spent building are hours not spent on the Orchestrator's primary responsibilities.

### Per-Application Tooling Costs

| Scenario | Monthly Cost |
|---|---|
| **Minimum viable** (free tiers, small projects) | $20–$50 |
| **Standard production** (paid tiers, moderate traffic) | $75–$150 |
| **Full production** (higher traffic, team features) | $150–$300 |

Costs are per application. The AI subscription ($100-$200/month for consumer; enterprise pricing varies) is shared across all projects.

### 3-Year Total Cost of Ownership (Per Application)

| Cost Component | Year 1 | Year 2 | Year 3 | 3-Year Total |
|---|---|---|---|---|
| **AI subscription (shared, pro-rated per app at 5 apps)** | $240-$480 | $240-$480 | $240-$480 | $720-$1,440 |
| **Infrastructure (hosting, database, monitoring)** | $900-$3,600 | $900-$3,600 | $900-$3,600 | $2,700-$10,800 |
| **Development (Orchestrator time)** | Loaded rate × 50-90 hrs | — | — | One-time |
| **Maintenance (Orchestrator time)** | Loaded rate × 100-200 hrs | Loaded rate × 50-80 hrs | Loaded rate × 50-80 hrs | Loaded rate × 200-360 hrs |
| **Governance overhead (approver reviews, backup maintainer sync, security reviews)** | ~20-30 hrs total across roles | ~10-15 hrs | ~10-15 hrs | ~40-60 hrs |

**Vendor pricing sensitivity:** AI subscription costs are volatile. Model the following scenarios for budget planning:

| Scenario | Impact |
|---|---|
| AI subscription increases 25% | Negligible — tooling costs are a small fraction of total |
| AI subscription increases 100% | Increases annual tooling cost by $1,200-$2,400 across portfolio. Meaningful but not project-killing. |
| AI subscription increases 300%+ or usage-based pricing replaces flat rate | May alter the ROI comparison for low-value applications. Triggers fallback evaluation (see Section IX). |
| Hosting vendor changes pricing tier structure | Evaluate migration to alternative PaaS. Budget 8-16 hours per application for hosting migration. |

**Context-switching overhead:** The hour estimates assume blocked, dedicated time. An Orchestrator interleaving this work with their primary responsibilities will take 20-40% longer due to cognitive context-switching. Recommend dedicated half-day or full-day blocks rather than "fit it in between meetings."

### Cost of Failure

The preceding analysis models the cost of success. Organizations should also model the cost of failure — a security vulnerability, compliance violation, or production incident in an AI-generated application.

**Estimated failure costs by scenario:**

| Scenario | Estimated Cost Range | Notes |
|---|---|---|
| **Data breach (internal users, no PII)** | $10,000-$50,000 | Incident response hours, forensic analysis, remediation. No notification obligations for internal tools without PII. |
| **Data breach (PII involved)** | $150-$200/record + fixed costs | Per IBM's annual Cost of a Data Breach Report. Notification costs, credit monitoring, legal fees. This scenario should not occur — PII is excluded from pilot scope. |
| **Dependency supply-chain compromise** | $5,000-$25,000 | Detection, assessment, patching, incident response. Mitigated by Snyk monitoring and SBOM generation. |
| **Compliance violation (non-regulated)** | $10,000-$100,000 | Internal audit remediation, process correction, management time. |
| **Availability incident (internal tool)** | $1,000-$10,000 | Lost productivity × affected users × downtime hours. Low blast radius for internal tools. |
| **Reputational/trust damage** | Unquantifiable | Internal tools carry lower reputational risk than customer-facing applications. |

**Why the gates exist:** The phase-gated process limits financial exposure by catching problems early. A requirement error caught in Phase 0 costs hours to fix. An architecture flaw caught in Phase 1 costs days. A security vulnerability that reaches production costs the figures above. Each gate is a cost-containment boundary.

**Portfolio-level failure exposure:** If a single AI model update introduces a systematic vulnerability across multiple applications (see Section IX: AI Model Quality Regression), the incident cost compounds across the portfolio. This is the primary argument for limiting portfolio size per Orchestrator and testing model updates on one project before rolling across all projects.

**Insurance as backstop:** The mandatory insurance confirmation (Section VIII.10) is not bureaucratic overhead — it is the financial backstop for the scenarios above. Organizations should confirm that their cyber liability coverage specifically contemplates AI-generated code, not assume existing policies apply.

### Portfolio Maintenance Cost at Scale

The per-application maintenance estimate of 50-80 hours/year understates the portfolio-level burden because it does not account for context-switching between applications. Worked example at 5 active applications:

| Metric | Calculation | Result |
|---|---|---|
| Annual maintenance hours | 5 apps × 65 hrs/yr (midpoint) | 325 hours/year |
| Percentage of FTE | 325 hrs ÷ 2,000 hrs/yr | ~16% of full-time role |
| With context-switching overhead (+30%) | 325 × 1.3 | ~423 hours/year (~21% FTE) |
| Governance overhead (approver reviews, backup sync) | 5 apps × 12 hrs/yr | 60 hours/year |
| **Total portfolio burden** | | **~483 hours/year (~24% FTE)** |

At 8 applications (the framework maximum), the portfolio burden approaches 40% of a full-time role. Organizations should establish a portfolio cost ceiling per Orchestrator and treat maintenance time as a budgeted line item, not an unfunded mandate absorbed into the Orchestrator's existing responsibilities.

---

## IV. Process Overview

The framework operates in five phases. Each phase produces documented artifacts that gate entry into the next phase. The Builder's Guide (SOI-002-BUILD) provides step-by-step instructions for each phase. This section describes what the organization must oversee at each phase.

| Phase | Duration | What the Orchestrator Does | What the Organization Oversees |
|---|---|---|---|
| **0: Product Discovery** | 1-2 days | Defines requirements, user journeys, data contracts, MVP scope | Sponsor approves business justification; compliance screening completed |
| **1: Architecture** | 2-3 days | Selects technology stack, designs schema, produces Project Bible | Senior Technical Authority approves architecture; IT Security approves AI deployment path |
| **2: Construction** | 2-4 weeks | Builds features using TDD; per-feature security audits | In-phase decision log maintained; no external oversight unless escalation triggered |
| **3: Validation** | 3-5 days | Integration testing, security hardening, accessibility, performance | IT Security reviews security scan results; penetration test if required by policy |
| **4: Production** | 1-2 days + ongoing | Deployment, monitoring, incident response, maintenance | Application Owner + IT Security approve go-live; ITSM ticket closed; ongoing portfolio review |

---

## V. Governance & Accountability

### Approval Authority

The Orchestrator cannot approve their own work at every gate. The following approval authorities are defined by role (not individual). Named individuals must be assigned before Phase 0 begins.

| Gate | Approver Role | What They Approve | Evidence Required |
|---|---|---|---|
| **Pre-Phase 0** | IT Security | AI deployment path (commercial terms, data handling) | Written approval (email, ticket, or signed document) |
| **Phase 0 → Phase 1** | Project Sponsor (business owner) | Business justification, resource allocation, opportunity cost acceptance, compliance screening | Signed-off Phase 0 artifacts + compliance screening matrix |
| **Phase 1 → Phase 2** | Senior Technical Authority (architect, engineering lead, or IT security) | Architecture selection, security posture, data classification | Written approval of Project Bible |
| **Phase 3 → Phase 4** | Application Owner + IT Security | Go-live readiness, risk acceptance, insurance confirmation | Security scan results, pen test (if required), go-live checklist |

**Audit evidence:** Phase gate approvals must be recorded as signed-off evidence — an email approval, a ticket state change, or a document approval with date and approver identity. The existence of an artifact alone is not sufficient evidence of approval. An internal auditor or board inquiry must be able to trace who approved what, when.

**Approval Log:** Each project repository must contain an `APPROVAL_LOG.md` file that records all pre-condition and phase gate approvals in a structured format. This file is generated by `init.sh` and serves as the single auditable record of governance approvals. The log captures: gate name, approver name, approver role, date, approval method (email, ticket, or document), evidence reference, and decision. The Approval Log is append-only — previous entries must not be modified or deleted. Git history provides tamper evidence.

#### Approval Verification Controls

To prevent self-approval or post-hoc fabrication of approval entries:

1. **Commit-based evidence.** Each approval entry MUST be committed to `APPROVAL_LOG.md` by the *approver*, not the Orchestrator. The git author on the commit serves as the verification record.
2. **Out-of-band confirmation.** For organizational deployments, the approver MUST send written confirmation (email, Slack message, or ticket comment) to a monitored channel. Reference the confirmation ID in the `Evidence` field.
3. **No self-approval.** The Orchestrator MUST NOT author git commits that add their own name as approver. CI or code-review tooling SHOULD enforce this where feasible.
4. **Audit review.** During quarterly portfolio reviews, the Senior Technical Authority MUST verify that git commit authors on `APPROVAL_LOG.md` entries match the listed approvers.

### In-Phase Decision Log

During Phase 2 (Construction, 2-4 weeks), the Orchestrator will make decisions that don't trigger formal escalation but are significant enough to record. Maintain a running decision log capturing: date, decision, rationale, alternatives considered. This log is reviewed at the Phase 3 gate by the Senior Technical Authority.

### Escalation Path

The Orchestrator must escalate when:
- The project exceeds its approved budget or timeline by >20%
- Scope changes affect another business unit
- A security finding exceeds the Orchestrator's competency to evaluate
- A data classification dispute arises
- A dependency introduces a license concern the Orchestrator cannot resolve

Define the escalation chain before Phase 0 begins: Orchestrator → Senior Technical Authority → Project Sponsor → CIO (or designated authority).

### Accountability for Incidents

| Scenario | Accountable Party | Supporting Evidence |
|---|---|---|
| Data breach caused by application vulnerability | Application Owner (business) + Orchestrator (technical) | Phase 3 security scan results, pen test report, go-live approval |
| Service outage | Orchestrator (first response) + backup maintainer (coverage) | Incident response playbook, monitoring alerts |
| Compliance violation discovered post-deployment | Project Sponsor (approved compliance screening) + Orchestrator (implemented controls) | Compliance screening matrix, Phase 0 approval |
| AI vendor data incident | Organization (selected the vendor) | AI deployment path approval, commercial terms documentation |

The existence of documented governance artifacts (approvals, security scans, compliance screening) demonstrates due diligence. The absence of these artifacts creates unmitigated liability.

---

## VI. ITSM & Change Management Integration

Solo Orchestrator deployments must integrate with existing change management from the start — not as a deployment afterthought.

| When | ITSM Action | Change Type |
|---|---|---|
| **Phase 0 approval** | Register the project in the enterprise portfolio tracker. File an initial change ticket. | Informational / planning |
| **Phase 1 completion** | Update the change ticket with architecture selection and data classification. | Standard (if pre-approved architecture catalog) or Normal |
| **Phase 4 deployment** | File the deployment change per the organization's change management taxonomy. | Standard, Normal, or Emergency per classification |
| **Post-deployment changes** | Each significant release follows the same change process. | Per classification |

Classify the deployment per the organization's change management process (ITIL CAB, lightweight change board, or equivalent). The classification should align with the application's risk tier, not default to the lowest category because "it's just an internal tool."

---

## VII. Security Requirements

### AI Data Transmission Policy

**This is a pre-Phase 0 governance requirement, not an Orchestrator decision.**

When using Claude or any cloud-hosted LLM, project code and context are transmitted to the provider's servers for processing. IT Security must approve the data transmission path before any company code is sent to an AI provider.

| Deployment Path | Appropriate For | Approval Required |
|---|---|---|
| **Consumer subscription** (Claude Max) | Personal projects, learning, open-source work. **Not for company source code.** | N/A — not approved for organizational use |
| **Commercial API** (Anthropic API with commercial terms) | Standard projects without highly sensitive data | IT Security written approval |
| **Enterprise agreement** (Claude Enterprise, AWS Bedrock, Google Cloud Vertex AI) | Projects with enterprise data protections, contractual terms | IT Security + Legal written approval |
| **Zero Data Retention (ZDR) or self-hosted LLM** | Projects handling PII, financial data, trade secrets, or data subject to regulatory constraints | IT Security written approval; may require additional architecture review |

**Mandatory ZDR gate:** Projects with data classified as **Internal or higher** (Internal, Confidential, PII, Financial, Regulated) **must** use the ZDR or self-hosted deployment path. This is a hard gate at Phase 1 — the Orchestrator may not proceed to Phase 2 with a non-ZDR deployment path if the project handles data above Public classification. The Senior Technical Authority must verify the deployment path matches the data classification before approving the Phase 1 → Phase 2 transition.

**Policy verification cadence:** AI provider terms change. Verify the current data handling policy at the time of adoption and at each biannual review.

### Data Loss Prevention for AI Prompts

The Orchestrator must not include in AI prompts or context:
- Production database exports or snapshots
- Real user PII (use synthetic or anonymized data)
- Credentials, API keys, or tokens — even in "example" format
- Proprietary business logic that constitutes trade secrets (abstract into requirements; let the AI implement without seeing the competitive-sensitive specification). **Note:** Transmitting trade secrets to a third-party AI provider may undermine trade secret status under the legal standard requiring "reasonable steps" to maintain secrecy. For commercially sensitive projects, use ZDR or self-hosted models — abstraction alone is a partial mitigation, as the AI needs sufficient context to generate correct code.
- Data from other subsidiaries or business units without authorization

This is not theoretical — inadvertently pasting production data into an AI prompt is a common and real risk in AI-assisted development. The gitleaks pre-commit hook and CI pipeline scan catch secrets in code; they do not catch sensitive data in conversational AI prompts.

**File exclusion from AI context:** Claude Code does not currently support a `.claudeignore` mechanism to exclude files from LLM context. When this capability becomes available, organizations should adopt it immediately for projects handling Internal or higher classified data. Until then, the `.gitignore` patterns and the expanded secret file exclusions provide partial mitigation. Monitor Claude Code release notes for file exclusion features at each biannual review.

### Penetration Testing

| Application Track | Penetration Testing Requirement |
|---|---|
| **Light Track** (internal, <10 users, no sensitive data) | Not required unless organizational policy mandates it for all production applications |
| **Standard Track** (external users, moderate complexity) | Required before go-live, or explicit exemption approved by IT Security with documented rationale |
| **Full Track** (enterprise buyers, sensitive data, >$10K/month revenue) | Required before go-live. No exemption path. |

The Builder's Guide includes automated SAST (Semgrep), DAST (OWASP ZAP baseline), dependency scanning (Snyk), and secret detection (gitleaks). These are necessary but not sufficient substitutes for penetration testing, which identifies logic flaws, business logic abuse, and chained vulnerabilities that automated tools miss.

### Security Peer Review (Competency-Gated)

For Orchestrators who self-assess **"No" or "Partially"** on Security in the Competency Matrix (Phase 0.6), a security peer review is required at Phase 3 before go-live, **regardless of project track.** This is not optional for these Orchestrators — automated tooling catches pattern-based vulnerabilities but does not catch business logic flaws, broken access control in novel patterns, or authorization bypass through workflow manipulation.

| Aspect | Requirement |
|---|---|
| **Trigger** | Orchestrator self-assessed "No" or "Partially" on Security in the Competency Matrix |
| **When** | Phase 3, after automated scans are complete and findings resolved |
| **Who** | Qualified security engineer, Senior Technical Authority, or designated security peer — not the Orchestrator |
| **Duration** | 1-2 hours |
| **Focus areas** | Authorization logic (can User A reach User B's data through any path?), data isolation enforcement, business logic abuse scenarios, authentication edge cases, threat model validation (Phase 1.3 mitigations implemented correctly) |
| **Gate** | Findings rated High or Critical must be resolved before deployment. Medium findings must be documented with remediation timeline or explicit risk acceptance. |
| **Autonomous workflow impact** | The agent completes all Phase 3 automated steps without interruption. The peer review is a human checkpoint at the end of Phase 3, before Phase 4 begins. It does not interrupt the agent's work. |

### Incident Response Integration

The Builder's Guide defines application-level severity classification and rollback procedures. For enterprise deployment, the application-level incident response must integrate with the enterprise incident response plan at these handoff points:

| Trigger | Enterprise IR Integration |
|---|---|
| **Suspected data breach** | Immediately notify IT Security and Legal. Isolate the application. Preserve all logs, database state, and deployment artifacts before any remediation. Initiate the enterprise breach response procedure, including notification timeline obligations (72 hours under GDPR, varies by state law). |
| **Security vulnerability discovered in production** | Notify IT Security. Classify using the enterprise vulnerability management SLA. Patch within the SLA window. |
| **Third-party vendor security incident** (AI provider, hosting provider) | Notify IT Security. Assess data exposure. Follow the enterprise third-party incident procedure. |
| **Application used as attack vector** (compromised to attack other systems) | Immediately isolate. Full forensic investigation under IT Security direction. |

**Evidence preservation chain:** Before rolling back a deployment or restoring a database during an incident, capture: application logs, database state (snapshot), deployment configuration, environment variables (redacted), and the git commit hash of the running version. This evidence may be required for forensic investigation, regulatory notification, or litigation.

### CI/CD Log Access Controls and Retention

CI/CD pipeline logs may contain sensitive data — including partial secret matches from gitleaks findings, dependency vulnerability details, and environment configuration. Organizations must define and enforce the following:

| Concern | Requirement |
|---|---|
| **Log access** | Restrict CI/CD log access to the Orchestrator and authorized personnel. Disable public log visibility on GitHub Actions (Settings → Actions → General → "Fork pull request workflows"). |
| **Log retention** | Retain CI/CD logs for at least 90 days (or the organization's standard retention period, whichever is longer). GitHub Actions retains logs for 90 days by default; verify this meets organizational policy. |
| **Secret redaction** | Ensure CI/CD platform secret masking is active. GitHub Actions automatically masks secrets stored in Settings → Secrets; verify no secrets are passed via plaintext environment variables. |
| **Security tool output** | gitleaks, Semgrep, and dependency audit findings may appear in logs. If the organization requires log sanitization for compliance, configure these tools to write findings to artifacts (uploaded and access-controlled separately) rather than stdout. |

### Security Headers & Configuration Baseline

All Solo Orchestrator applications must implement the following security configuration before go-live. These are verified in the Phase 4 Go-Live Smoke Test (Builder's Guide Step 4.2).

- `Content-Security-Policy` — start restrictive, add sources as needed
- `Strict-Transport-Security` (HSTS)
- `X-Frame-Options: DENY` or `SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- CORS: only allowed origins, no wildcard on authenticated endpoints
- Cookies: `HttpOnly`, `Secure`, `SameSite` flags
- Rate limiting on authentication endpoints
- Commit signing recommended for audit trail

### Post-Release Vulnerability Response

When a CVE or security advisory is published affecting a deployed dependency or component:

| Severity | Maximum Time to Patch | Escalation if Missed |
|----------|----------------------|---------------------|
| **Critical (CVSS ≥ 9.0)** | 24 hours or take application offline | Immediate notification to IT Security and Application Owner |
| **High (CVSS 7.0–8.9)** | 7 calendar days | Escalate to Senior Technical Authority |
| **Medium (CVSS 4.0–6.9)** | Next monthly maintenance window | Document in maintenance log |
| **Low (CVSS < 4.0)** | Next quarterly maintenance window | Document in maintenance log |

**Continuous monitoring:** The Orchestrator MUST enable automated vulnerability notifications (GitHub Dependabot alerts, Snyk monitoring, or equivalent) for every production repository. Monthly manual audits are not sufficient as the sole detection mechanism.

**Patch verification:** After applying a patch, re-run the full CI pipeline (including SAST and dependency audit) and verify the vulnerability is resolved before deploying.

**If patching is not possible** (breaking change, no fix available): Document the risk acceptance with IT Security approval, implement compensating controls (WAF rules, input validation, feature disabling), and set a calendar reminder to revisit.

### Proactive Credential Rotation

Credentials MUST be rotated on a regular schedule, not only after compromise:

| Credential Type | Rotation Cadence | Responsibility |
|----------------|-----------------|----------------|
| API keys (third-party services) | Every 6 months | Orchestrator |
| Database passwords | Every 12 months | Orchestrator |
| Code signing certificates | Before expiration (track expiry dates) | Orchestrator |
| CI/CD secrets (GitHub Actions, etc.) | Every 12 months | Orchestrator |
| OAuth client secrets | Every 12 months | Orchestrator |
| SSH deploy keys | Every 12 months | Orchestrator |

**Tracking:** Maintain a credential inventory in the Project Bible (Section: Infrastructure) listing each credential, its purpose, creation date, and next rotation date. The quarterly portfolio review MUST verify rotation compliance.

**Emergency rotation:** On suspected compromise, rotate immediately per the incident response playbook — do not wait for the scheduled cadence.

---

## VIII. Legal & Compliance

**IMPORTANT: This section identifies legal risks and mitigation approaches. It is not legal advice, and it is not a substitute for qualified legal counsel. The regulatory landscape for AI-assisted software development is evolving rapidly. Organizations must engage counsel with expertise in intellectual property, data privacy, and AI regulation in their operating jurisdictions. The mitigations described herein represent reasonable practices as of the document date but may not be sufficient for all jurisdictions or all use cases.**

### 1. Open-Source License Compliance

AI-suggested third-party packages do not come with license reviews. A single AGPL-licensed dependency in a commercial SaaS product can create an obligation to release the entire source code. This applies to both direct dependencies and transitive dependencies (a dependency's dependency).

**Mitigation:** Automated license checking is integrated into the CI/CD pipeline. The build fails if copyleft-licensed dependencies (GPL, AGPL, LGPL, SSPL, EUPL) are detected in the full dependency tree. An organizational whitelist of approved licenses (typically MIT, Apache 2.0, BSD) is defined during architecture selection. Note: MPL-2.0 has file-level copyleft and should be reviewed on a case-by-case basis. Dual-licensed packages (e.g., MySQL Connector under GPL or commercial license) require manual review — automated checkers may not detect that a commercial alternative exists.

### 2. AI-Generated Code: Ownership & Copyright

Under current Anthropic terms, the user owns output generated through Claude. However, copyright eligibility for purely AI-generated content without meaningful human creative input is legally unsettled under current U.S. Copyright Office guidance.

**Mitigation:** The Solo Orchestrator model inherently establishes human creative direction at every phase gate — the human selects the architecture, reviews test assertions, directs UX decisions, and approves every feature. This strengthens the copyright claim over AI-assisted output. Maintain comprehensive documentation of these human decisions.

**Code provenance risk:** The litigation vector is not only "do we own this code" but "does this code infringe on copyrighted training data." The mitigation is to maintain the human-directed architecture decisions, test specifications, and phase gate approvals as evidence of independent creation. Monitor legal developments through counsel.

### 3. Data Privacy Regulations

Applications collecting personal data are subject to GDPR (EU), CCPA/CPRA (California), and the growing patchwork of U.S. state privacy laws (Colorado Privacy Act, Virginia CDPA, Connecticut Data Privacy Act, Texas Data Privacy and Security Act, Oregon Consumer Privacy Act, and others enacted or effective through 2026).

For a holding company operating across multiple states or internationally, the applicable regulations vary by user location, not company location. The compliance screening (Section VIII.7) must identify which specific laws apply based on the actual user base.

**Mitigation:** Data sensitivity classification in Phase 0, data residency and encryption in Phase 1 architecture, consent mechanisms and data subject request handling in Phase 2, and Privacy Policy publication before launch in Phase 3.

### 4. Data Sovereignty (International Subsidiaries)

For organizations with international subsidiaries or users, data sovereignty is an architectural constraint — not just a compliance checkbox.

**Phase 1 Data Sovereignty Checklist:**

| Question | If Yes |
|---|---|
| Where is user data stored at rest? | Document the geographic location of all data stores. |
| Where is user data processed? | Document the geographic location of all compute (including AI processing). |
| Does data cross international borders? | Identify the legal mechanism authorizing the transfer (Standard Contractual Clauses, adequacy decisions, binding corporate rules, consent). |
| Are any data stores or processing in jurisdictions with data localization requirements? | Ensure the architecture complies. Cloud region selection is an architectural decision, not an afterthought. |
| Does the AI provider process data outside the user's jurisdiction? | Verify the AI deployment path terms address cross-border data transfer. |

### 5. EU AI Act Classification

The EU AI Act applies to AI systems based on their risk classification. This has two dimensions for Solo Orchestrator projects:

**Development methodology:** Using AI to write code is generally low-risk under the Act. The AI is a development tool, not a deployed AI system making decisions about people.

**Deployed product:** If a Solo Orchestrator application incorporates AI features for end users (e.g., AI-powered suggestions, automated decision-making, content generation), the deployed application itself may require classification under the Act. This is a separate assessment from the development methodology.

| AI Feature in Deployed Product | Potential Classification | Required Action |
|---|---|---|
| No AI features — static application | Not in scope | Document the assessment |
| AI features for content generation or recommendations | Limited or minimal risk | Transparency obligations; document AI use to end users |
| AI features making decisions affecting individuals | May be high-risk depending on domain | Full conformity assessment; engage legal counsel |

Assess this at Phase 0 for any application that will include AI-powered features.

### 6. Emerging AI Regulation

The AI regulatory landscape is evolving rapidly. Beyond the EU AI Act:
- Potential U.S. federal AI legislation
- State-level AI transparency and disclosure laws
- Industry-specific AI governance requirements
- Mandatory AI disclosure requirements in certain jurisdictions

**Required action:** Add an AI regulatory landscape review to the biannual maintenance cadence. Engage legal counsel to monitor developments that could affect whether and how the organization uses AI-generated code or deploys AI-powered applications.

### 7. Trademark & Branding

Product names must be searched against the USPTO Trademark Search system (https://search.uspto.gov/search/trademark), relevant app stores, domain registrars, and WIPO Global Brand Database (https://branddb.wipo.int) before architecture investment. Trademark filing ($250-$350 per class) is recommended before commercial launch.

### 8. Third-Party Service Terms of Service

Every API, database, and hosting service has terms that may restrict usage. The Orchestrator — not the AI — must review Terms of Service for every service in the stack and document any relevant restrictions in the Project Bible.

### 9. Liability & Indemnification

Anthropic's terms include limitations of liability for AI-generated output. The organization deploying the application is responsible for its behavior regardless of how the code was produced. The framework's phased validation process (TDD, automated security scanning, manual review, monitoring) produces the quality assurance artifacts that demonstrate due diligence.

**Liability chain for holding companies:** For organizations with subsidiaries, define in the pilot approval documentation which entity (subsidiary or parent) bears liability for Solo Orchestrator applications. This must be defined before the pilot begins, not as an output of it.

### 10. Insurance Requirements (Mandatory Before Pilot)

Obtain written confirmation from the organization's insurance broker that:
- Cyber liability covers incidents caused by AI-generated code
- E&O covers services delivered through AI-generated applications
- D&O does not create exposure for authorizing AI-assisted development
- AI-specific exclusions have been reviewed and documented (policies may contain broad AI exclusions that void coverage)
- Sublimits for cyber claims are sufficient for the application's risk profile
- Retroactive date covers the pilot start date
- Coverage extends to AI training data infringement claims (third-party copyright or patent claims arising from AI-generated code)

Policies written before 2024 likely do not contemplate AI-generated code. This confirmation is a **gating artifact for Phase 0 approval** — no confirmation, no pilot.

**If coverage is insufficient:** Options include supplemental AI-specific riders, umbrella policies, scoping the pilot to exclude scenarios that trigger coverage gaps, or engaging a broker specializing in technology E&O to identify alternative carriers. Do not proceed without a documented coverage path.

### 11. Compliance Screening Matrix

Before any project begins, the Orchestrator and project sponsor must complete this screening:

| Question | If Yes |
|---|---|
| Does this application process data used in financial reporting? | Route through existing SOX IT general controls. |
| Does this application handle payment card data (even masked)? | Conduct PCI scoping assessment. |
| Does this application collect personal data from users in multiple states or internationally? | Mandate legal review identifying all applicable privacy laws by jurisdiction. |
| Are any users or subsidiaries in the EU? | Address EU AI Act classification (Section VIII.5), data transfer mechanisms (Section VIII.4), and data sovereignty. |
| Does any subsidiary operate in a sanctioned jurisdiction? | Screen for OFAC implications. |
| Is data subject to records retention requirements? | Define retention periods, deletion procedures, and e-discovery readiness. |
| Does the deployed application include AI-powered features for end users? | Complete EU AI Act classification assessment (Section VIII.5). |
| Does this application process any health-related data, even incidentally (e.g., patient names, appointment data, wellness information)? | This framework explicitly excludes HIPAA-regulated systems. If health data is present, conduct a HIPAA applicability assessment before proceeding. |
| Is the organization subject to Gramm-Leach-Bliley Act (GLBA) safeguards? | Route through existing GLBA information security program. Even internal tools at financial institutions may trigger safeguard requirements. |
| Is the organization publicly traded? | Assess SEC cybersecurity disclosure requirements (2023 rules) for material incidents involving this application. |

Document and approve this screening before Phase 1 begins.

**Scope creep re-evaluation:** Projects originally classified as Light Track must be re-screened against this matrix if they evolve beyond their initial scope — particularly if they begin handling PII, financial data, health data, or serving users in additional jurisdictions. A "yes" answer to any new question triggers the corresponding action, potentially including track re-classification from Light to Standard or Full. This re-evaluation is the Orchestrator's responsibility at each quarterly review.

### AI Conversation Log Retention

AI-assisted development generates conversation logs (prompts and outputs) that may contain sensitive information. These logs are subject to the following policy:

1. **During active development (Phases 0–4):** Retain conversation logs for context continuity and audit trail.
2. **After launch (Phase 4 steady-state):** Delete or archive conversation logs within 90 days of Phase 4 completion unless a regulatory hold is in effect.
3. **If PII was inadvertently included in prompts:** Report as a data incident per the incident response playbook. Work with the AI provider to request deletion under their data processing terms.
4. **AI provider data handling:** Verify and document the AI provider's data retention policy. For enterprise or ZDR deployments, confirm in writing that conversation data is not retained for model training.
5. **Litigation hold:** If litigation is anticipated or pending, preserve all AI conversation logs per the organization's legal hold procedures. Do not delete until Legal releases the hold.

### Legal Checklist

| Check | When | Action |
|---|---|---|
| Insurance confirmation | Before pilot (Pre-Phase 0) | Written broker confirmation per Section VIII.10 |
| AI deployment path approval | Before pilot (Pre-Phase 0) | IT Security written approval per Section VII |
| Liability entity designation | Before pilot (Pre-Phase 0) | Define which entity bears liability per Section VIII.9 |
| Data Processing Agreement (AI provider) | Before pilot (Pre-Phase 0) | Verify AI provider agreement includes GDPR-compliant DPA and, for cross-border transfers, appropriate transfer mechanisms (SCCs or equivalent). Required for any project handling personal data. |
| Compliance screening | Before architecture (Phase 0) | Complete Section VIII.11 matrix with project sponsor |
| Trademark search | Before architecture (Phase 0) | Search USPTO, app stores, domain registrars, WIPO |
| Privacy regulation applicability | During requirements (Phase 0) | Classify all data inputs by sensitivity; identify applicable regulations by jurisdiction |
| Data sovereignty assessment | During architecture (Phase 1) | Complete Section VIII.4 checklist |
| Open-source license whitelist | During architecture (Phase 1) | Define approved licenses; add automated checking to CI/CD |
| Third-party ToS review | During architecture (Phase 1) | Orchestrator reviews terms for every selected service |
| AI data handling policy | During architecture (Phase 1) | Confirm provider's commercial data terms; determine if ZDR is required per data classification |
| Privacy Policy & Terms of Service | Before launch (Phase 3) | Draft and publish; **mandatory attorney review before deployment** — AI-generated legal documents must not be deployed without review by qualified legal counsel |
| License audit passing in CI/CD | Before deployment (Phase 4) | Build fails on copyleft license detection |
| Trademark filing | At or before launch (Phase 4) | File USPTO application or engage trademark counsel |

---

## IX. Vendor & Technology Risk

### AI Provider Dependency

The framework is built on and tested with Claude Code (Anthropic). This is not a thin abstraction layer — it's a development environment dependency. The operational tooling (CLAUDE.md, Superpowers plugin, Context7/Qdrant MCP servers, CLI Setup Addendum) is Claude Code-specific. A CIO should treat this as vendor concentration, not vendor-agnostic tooling.

**What transfers without modification (agent-agnostic):**

- The methodology: phases, decision gates, quality controls, remediation tables
- All project artifacts: Product Manifesto, Project Bible, ADRs, test results, HANDOFF.md
- The codebase, tests, and documentation the agent produces
- Security tooling: Semgrep, gitleaks, Snyk, OWASP ZAP, SBOM generation
- CI/CD pipeline, Git hooks, pre-commit checks
- The Intake Template, Governance Framework, and evaluation prompts

**What requires retooling (Claude Code-specific):**

| Component | Migration Effort | What Changes |
|---|---|---|
| CLAUDE.md | 1-2 days | Rewrite as equivalent agent configuration for new tool |
| Superpowers plugin | 1-2 weeks | Find/build equivalent agentic skills (subagent dispatch, TDD enforcement, worktrees) or revert to manual Build Loop |
| Context7 / Qdrant MCP servers | 1-2 days | Find equivalent context/memory tools or manage context manually |
| CLI Setup Addendum | Rewrite | New document for new agent's configuration model |
| Operational prompts | 1-2 weeks per project | Re-validate that the new agent produces comparable output quality on existing codebase |
| **Total realistic switching cost** | **2-4 weeks per active project** plus Orchestrator retraining |

**Mitigation:**
- Periodically verify that `PROJECT_BIBLE.md` produces coherent output on a secondary model (e.g., GPT, Gemini, or open-source). If the Bible is well-written, the project is recoverable regardless of which agent built it.
- Maintain all documentation in model-agnostic formats (Markdown, not Claude-specific notation).
- Do not embed Claude-specific prompt engineering into the Project Bible itself — it should be a technical specification, not a prompt.
- The Development Guardrails for Claude Code (Git hooks) are not Claude-specific — they work with any development workflow.
- Budget for annual requalification: test the full workflow on an alternative agent to verify the exit path remains viable.

**Annual cross-model validation (required for organizational deployments):**

Once per year, the Orchestrator must test the Project Bible from at least one active application against an alternative AI coding agent (e.g., GitHub Copilot agent mode, Cursor, Gemini CLI, or an open-source model). The test validates that:

1. The alternative agent can read the Project Bible and produce a coherent summary of the application's architecture.
2. The alternative agent can implement a minor change (bug fix or small feature) using only the Project Bible and existing codebase.
3. The time required is documented and compared to the estimated 2-4 week switching cost.

Record the results in the quarterly portfolio review. If the alternative agent cannot produce usable output from the Project Bible, the Bible needs improvement — it may be encoding Claude-specific assumptions rather than serving as a portable technical specification. If the switching cost estimate has materially changed (up or down), update the exit plan budget accordingly.

### Platform Vendor Concentration

Every Solo Orchestrator application depends on a stack of platform-specific vendors — hosting providers, SDKs, distribution channels, and build tools. The specific vendors vary by platform type (see the applicable Platform Module), but the risk is the same: any vendor changing pricing, terms, or discontinuing service creates exposure.

**Required for each project:** Document the primary vendor for each tier of the application stack and at least one fallback option with an estimated migration effort. This should be part of the Project Bible (Phase 1).

**Platform-specific governance concerns:**

| Platform | Additional Vendor Risk | Governance Action |
|---|---|---|
| **Web** | Hosting provider pricing changes, database vendor migration complexity | Document fallback hosting and database options with migration estimates |
| **Desktop** | Code signing certificate management (who holds certs, rotation schedule, expiry monitoring), unsigned binary risk for Light Track pilots | Assign certificate ownership. Add expiry dates to maintenance calendar. Define organizational policy for unsigned binaries. |
| **Mobile** | App store policy changes, account ownership (who holds the Apple/Google developer accounts), review rejection risk | Developer accounts must be owned by the organization, not the Orchestrator personally. Document app store compliance requirements at Phase 1. |

### AI Model Quality Regression

If a Claude (or alternative) update significantly degrades code quality for a specific technology stack, all active Solo Orchestrator projects are affected simultaneously. This is a correlated risk across the portfolio.

**Mitigation:** Pin to specific model versions where the provider supports it. When a model update is released, test against one project before rolling across the portfolio. If quality degrades significantly, the fallback is the secondary model verified in the periodic cross-model test.

---

## X. Operational Risk Management

### Bus Factor

The bus factor for a solo-maintained application is 1. Documentation does not change this — it reduces recovery time when the Orchestrator is unavailable, but does not answer pages, restore services, or triage defects.

### Backup Maintainer (Mandatory)

Every project must have a designated backup maintainer — a second technologist who:
- Has full repository and hosting access
- Performs a 1-hour monthly sync review with the Orchestrator
- Can execute the incident response playbook independently
- Has been tested via the handoff test (see Section XIII)

This person does not need to actively develop, but they must be able to triage, rollback, and escalate.

### Handoff Test (Mandatory Per Project)

For every project — not just the pilot — conduct a handoff test:
1. The backup maintainer attempts to set up the development environment using only the HANDOFF.md document.
2. The backup maintainer attempts to triage a simulated issue using only the produced documentation.
3. Measure how long each step actually takes.
4. Document every point where the backup maintainer gets stuck.
5. Fix the documentation gaps.
6. Repeat until the backup maintainer can complete both tasks unassisted.

**Expect the first attempt to fail.** The Orchestrator will omit tribal knowledge they don't realize they have. The handoff test's purpose is to surface these gaps before they matter.

#### Recurring Access Verification

The backup maintainer's access MUST be verified quarterly, not just at initial handoff:

1. **Quarterly access check.** The backup maintainer confirms they can: (a) clone the repository, (b) access the hosting platform, (c) access the monitoring dashboard, and (d) retrieve production secrets from the secrets manager.
2. **Verification method.** The backup maintainer performs the check independently and records the result in the quarterly portfolio review. If any access has lapsed, restore it immediately.
3. **Annual handoff re-test.** Once per year, the backup maintainer repeats the full handoff test (environment setup + issue triage using only documentation). This validates both access and documentation currency.

### Portfolio Scaling

**Maximum recommended: 5-8 active applications per Orchestrator.** Maintenance hours compound — at 10 applications, maintenance alone is a half-time job, leaving no capacity for new development.

**Enforcement:** A quarterly portfolio review conducted by the Senior Technical Authority evaluates each Solo Orchestrator application against:
- Current maintenance hours per week (trailing 3-month average)
- User count and growth trajectory
- Number of enterprise system integrations
- Business criticality designation
- Outstanding security findings

This review is not self-reported by the Orchestrator. The Senior Technical Authority reviews monitoring data, ITSM tickets, and maintenance logs independently.

#### Enforcement

- If the quarterly review is not completed within 30 days of the scheduled date, the Senior Technical Authority MUST escalate to the CIO.
- If review findings are not addressed within 60 days, the affected application enters a maintenance-only freeze (no new features) until findings are resolved.
- Review completion and finding resolution MUST be recorded in the organization's ITSM system.

#### Maintenance Cadence Enforcement

The maintenance cadence is mandatory, not advisory:

- **Monthly security audit skipped:** If two consecutive monthly security audits are missed, the Senior Technical Authority is notified and the application enters maintenance-only freeze until audits are current.
- **Quarterly review skipped:** Escalate to Application Owner within 7 days.
- **Biannual full audit skipped:** Application removed from production until the audit is completed.
- **Tracking:** Maintenance activities MUST be logged in the project's CHANGELOG.md or ITSM system with dates and findings.

### Graduation Criteria

When an application outgrows the solo model, it must transition to a conventional engineering team. Triggers (any one is sufficient):

| Trigger | Threshold |
|---|---|
| Active user count | >10,000 |
| Sustained maintenance demand | >4 hours/week for 3+ consecutive months |
| Enterprise system integrations | >3 |
| Business criticality | Designated business-critical by Application Owner |
| Compliance scope change | Application comes under SOC 2, HIPAA, PCI-DSS, or similar |

#### Enforcement

When any graduation trigger is met:

1. **30-day assessment.** The Application Owner MUST commission a transition assessment within 30 days, evaluating team requirements, budget, and timeline.
2. **90-day resolution.** Within 90 days, one of the following MUST occur:
   - **Transition approved:** Engineering team funded and onboarding begins.
   - **Scope reduced:** Application functionality reduced below trigger thresholds (features removed, users offboarded).
   - **Decommission initiated:** Application retirement plan filed.
   - **Exception granted:** CIO provides written exception with compensating controls (additional monitoring, increased maintenance budget, contracted support).
3. **No indefinite Solo operation.** An application MUST NOT remain in Solo Orchestrator state beyond 90 days after a graduation trigger is met without a written CIO exception.

### Graduation Transition Plan

When graduation is triggered:

1. **Funding:** The Application Owner secures budget for an engineering team (even 1-2 dedicated developers). This is a business decision, not a technical one.
2. **Knowledge transfer:** The Orchestrator conducts a structured knowledge transfer using the HANDOFF.md, Project Bible, and Architecture Decision Records. Budget 40-80 hours of Orchestrator time for this.
3. **Codebase assessment:** The receiving engineering team evaluates the codebase for technical debt, architectural gaps, and testing coverage. They produce a remediation plan.
4. **Transition period:** 4-8 weeks of parallel support where the Orchestrator remains available for questions while the engineering team assumes ownership.
5. **Cutover:** The Orchestrator is formally released from the project. The engineering team owns all future development and maintenance.
6. **Impact assessment:** Evaluate the impact on the Orchestrator's remaining portfolio. If they were at 7 applications and lose one, that's capacity for new work. If they were at 5 and the graduating application was consuming 50% of their time, the remaining 4 applications need to be redistributed or the Orchestrator needs to recover capacity.

### Shadow IT Risk

The entire value proposition of the Solo Orchestrator model is enabling faster application development. Without governance, this becomes formalized shadow IT with better documentation. The controls that prevent this:

1. **ITSM registration at Phase 0** — the project is visible in the enterprise portfolio from Day 1.
2. **Mandatory SSO integration** — applications authenticate through the enterprise identity provider, making them visible to identity governance.
3. **Centralized logging** — application logs feed into the enterprise SIEM or logging platform, making operational issues visible to IT operations.
4. **Quarterly portfolio review** — applications are evaluated against standards, not left to accumulate unmonitored.

If any of these controls are not in place, the Solo Orchestrator model is creating shadow IT, regardless of the quality of the code or documentation.

### Orchestrator Burnout

Managing 5-8 applications while maintaining a primary role is sustainable on paper but exhausting in practice. Maintenance is bursty — most weeks are quiet, some weeks spike to 8+ hours when multiple applications have issues simultaneously.

**Detection signals:** Maintenance hours consistently exceeding projections, documentation updates falling behind, security audits being deferred, the Orchestrator declining new projects or expressing concerns about capacity.

**Response:** Reduce the portfolio (graduate or decommission applications), allocate dedicated time blocks, or assign a second Orchestrator to share the portfolio. Do not add more applications to an overloaded Orchestrator.

### Governance Monitoring

Application-level monitoring (error tracking, uptime) is necessary but not sufficient. The following governance signals MUST also be monitored:

| Signal | Frequency | Owner | Escalation |
|--------|-----------|-------|------------|
| Maintenance cadence compliance | Monthly | Orchestrator (self-report) + ITSM verification | Senior Technical Authority |
| Backup maintainer sync completion | Monthly | Backup Maintainer confirms | Orchestrator → Application Owner |
| Graduation trigger thresholds | Quarterly | Senior Technical Authority | Application Owner → CIO |
| Credential rotation compliance | Quarterly | Orchestrator reports via portfolio review | Senior Technical Authority |
| Approval log integrity | Quarterly | Senior Technical Authority audits git history | CIO |
| Dependency vulnerability backlog | Monthly | Automated (Dependabot/Snyk alerts) | Orchestrator → IT Security |

### Insider Threat Acknowledgment

The Solo Orchestrator model concentrates all technical access in one individual. This is an inherent trade-off of the methodology and MUST be explicitly accepted:

1. **Risk acceptance.** The Application Owner and IT Security MUST acknowledge in the APPROVAL_LOG.md (Phase 0→1 gate) that the Orchestrator has unrestricted access to source code, production infrastructure, and secrets.
2. **Compensating controls:**
   - Backup maintainer has read access to all systems and receives automated alerts.
   - All code changes are committed to version control with signed commits (recommended).
   - Production deployments flow through CI/CD — no manual production deployments.
   - Audit logging enabled on hosting platform and secrets manager.
3. **Scope limitation.** Applications handling financial transactions, PII at scale, or regulated data (SOC 2, HIPAA, PCI) MUST NOT use the Solo Orchestrator model. These require separation of duties that a single-person model cannot provide.

---

## XI. Portfolio Governance (Multi-Project / Multi-Subsidiary)

For organizations running multiple Solo Orchestrators across subsidiaries:

### Mandatory Standards

All Solo Orchestrator applications must comply with:

| Standard | Requirement |
|---|---|
| **Authentication** | SSO integration with the enterprise identity provider (SAML/OIDC). No standalone authentication systems. |
| **Logging** | Structured logs feeding into the enterprise SIEM or centralized logging platform. |
| **Monitoring** | Error tracking (Sentry or equivalent) with alerts routed to the Orchestrator and backup maintainer. |
| **Repository** | Private repository on the organization's approved platform (GitHub, GitLab, Azure DevOps). |
| **CI/CD** | Automated testing, SAST scanning, dependency auditing, and license checking on every push. |

### Shared Starter Template

To prevent 10 Solo Orchestrators from building 10 different implementations of the same patterns, define a shared starter template that all projects must use. At minimum:

- Authentication integration with the enterprise identity provider
- Structured logging configuration with correlation IDs
- Error tracking integration (Sentry SDK configuration)
- Approved dependency license whitelist
- CI/CD pipeline template with security scanning
- Standard security headers configuration

This template is maintained by the Senior Technical Authority (or designated owner) and updated quarterly.

### Enterprise System Integration

Solo Orchestrator applications must integrate with enterprise systems using approved patterns:

| System | Integration Requirement |
|---|---|
| **Identity management** | Enterprise SSO (SAML/OIDC). No standalone user databases for authentication. |
| **Data warehouse** | If the application produces data needed for enterprise reporting, define the data pipeline at Phase 1. |
| **Monitoring platform** | If the organization uses Datadog, Splunk, New Relic, or similar, the application must emit metrics to the enterprise platform — not only to standalone tools. |
| **Backup infrastructure** | Database backups must follow the enterprise backup policy (retention, encryption, geographic redundancy). |

### Cross-Subsidiary Compliance Verification

A portfolio governance function (one person or a rotating responsibility) audits Solo Orchestrator applications quarterly:

- [ ] SSO integration active and functional
- [ ] Logs feeding to enterprise logging platform
- [ ] CI/CD pipeline running with security scanning
- [ ] Maintenance cadence being followed (check last security audit date)
- [ ] Application within approved user count and maintenance thresholds
- [ ] Insurance coverage confirmed at last biannual review
- [ ] AI provider terms verified at last biannual review

### Scaling Beyond a Single Orchestrator

This framework version defines governance for a single Orchestrator building individual applications. For organizations deploying multiple Orchestrators simultaneously, additional governance is needed:

- **Shared architecture catalog:** Define approved stacks and patterns to prevent independent Orchestrators from selecting incompatible technologies.
- **Cross-project review:** Periodic review (quarterly recommended) of architectural decisions across the portfolio to identify consolidation opportunities and conflicts.
- **Component reuse:** Shared internal libraries or approved package lists to avoid duplication of effort.
- **Approver capacity planning:** Named approvers reviewing multiple projects simultaneously need dedicated time allocation. Do not assume governance overhead is negligible at scale.

These multi-Orchestrator governance patterns are not yet defined in detail. Organizations scaling beyond 2-3 simultaneous Orchestrators should develop these controls before expanding further.

**Scaling readiness checklist:** Before approving a fourth simultaneous Orchestrator, the organization should have:

- [ ] A centralized portfolio dashboard providing visibility across all Solo Orchestrator applications (not manual Git repository aggregation)
- [ ] Automated compliance monitoring that surfaces missed security audits, lapsed credential rotations, and overdue maintenance across the portfolio
- [ ] Defined approver capacity budgets — a Senior Technical Authority can realistically review 5-8 applications per quarter with appropriate dedicated time allocation. Beyond that threshold, additional reviewers are needed.
- [ ] A shared architecture catalog with approved stacks, preventing independent Orchestrators from creating an unmanageable technology matrix
- [ ] A formal risk register entry in the enterprise risk management system for the Solo Orchestrator program as a whole, not just individual applications

Without these controls, adding Orchestrators increases delivery capacity while degrading governance quality — the opposite of the framework's intent.

---

## XII. Risk Assessment

### Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Single point of failure** — one person maintains the system | High | Designated backup maintainer with full access and monthly sync. Handoff test validated. Documentation enables continuity but does not replace a human who can triage and rollback. |
| **Security vulnerabilities in AI-generated code** | High | Automated SAST (Semgrep), DAST (OWASP ZAP), dependency auditing (Snyk), secret detection (gitleaks), manual review. Penetration testing required for Full Track (no exemption) and Standard Track (with IT Security exemption path). Same toolchain used by traditional development teams. |
| **Incident response** | High | Severity classification, notification chains, containment procedures defined in Builder's Guide. Enterprise IR integration defined in this document (Section VII). Backup maintainer provides coverage during Orchestrator absence. |
| **Data transmitted to AI provider** | High | Pre-Phase 0 IT Security approval of deployment path. Commercial terms required. ZDR or self-hosted for sensitive data. DLP guidelines for AI prompts. |
| **Open-source license contamination** | High | Automated license checking (direct + transitive) in CI/CD pipeline. Build fails on copyleft detection. SBOM generation. |
| **Data privacy non-compliance** | High | Data sensitivity classification in Phase 0. Compliance screening matrix. Jurisdiction-specific legal review. Privacy Policy required before launch. |
| **AI vendor lock-in** | Medium | Development environment + model dependency. Estimated switching cost: 2-4 weeks per active project. Methodology is model-agnostic. Periodic cross-model testing recommended. |
| **Code quality and performance** | Medium | TDD, automated linting, Lighthouse performance auditing, API contract testing (Standard+), load testing (Full Track). |
| **Intellectual property uncertainty** | Medium | Human-directed phase gates establish creative direction. Code provenance documentation supports independent creation claims. Monitor legal developments. |
| **AI model quality regression** | Medium | Pin to specific model versions where supported. Test updates on one project before portfolio-wide rollout. Maintain fallback model. |
| **Portfolio scaling** | Medium | Maximum 5-8 applications per Orchestrator. Quarterly portfolio review. Graduation criteria defined. Transition plan documented. |
| **Shadow IT** | Medium | ITSM registration at Phase 0, mandatory SSO, centralized logging, quarterly portfolio audit. |
| **Orchestrator burnout** | Medium | Monitor maintenance hours. Reduce portfolio or allocate dedicated time if overloaded. Do not add applications to an overloaded Orchestrator. |
| **Organizational change** | Medium | Handoff documentation + backup maintainer enable continuity through personnel changes. Graduation transition plan addresses team transitions. Portfolio review catches orphaned applications. |

---

## XIII. Decision Framework

### When to Use Solo Orchestrator vs. Traditional Development

| Criteria | Solo Orchestrator | Traditional Team |
|---|---|---|
| **User count** | <10,000 active users | >10,000 or enterprise SLA |
| **Compliance** | No regulatory certification requirements | SOC 2, HIPAA, PCI-DSS, FedRAMP |
| **Complexity** | Single application, well-defined domain | Multi-system integration, microservices, multi-tenant |
| **Timeline** | Working product needed in <8 weeks | 3-6 month team ramp-up acceptable |
| **Budget** | <$300/month infrastructure | Full engineering team budget available |
| **Strategic value** | Tactical tool, prototype, MVP validation | Core revenue product, competitive differentiator |
| **Maintenance** | 2-4 hours/week acceptable (stabilizing to 1-2) | Dedicated on-call team required |
| **Data sensitivity** | Low-to-moderate with appropriate AI deployment path | Highly regulated or classified data |

### Recommended Use Cases

- Internal tools solving specific departmental problems (asset trackers, approval workflows, dashboards, reporting tools)
- MVP builds that validate a product concept before committing full engineering headcount
- Prototypes demonstrating feasibility to stakeholders or investors
- Utility applications with well-defined CRUD operations and business logic
- Clearing the "small project" backlog that sits unfunded because it doesn't justify a team

### Not Recommended

- Any application requiring compliance certification (SOC 2, HIPAA, PCI-DSS, FedRAMP)
- Multi-tenant SaaS platforms with tenant isolation, billing, and configuration complexity
- Applications requiring 99.99%+ uptime SLAs
- Systems requiring multi-region deployment or disaster recovery beyond rollback
- Enterprise integration projects where the integration complexity exceeds the application logic

---

## XIV. Pilot Evaluation

For an organization evaluating this model, expect **4-12 weeks to resolve organizational pre-conditions** (insurance confirmation, AI deployment path approval, legal review, stakeholder alignment). Once pre-conditions are met, the operational pilot setup takes under 48 hours. The pre-condition timeline dominates — do not plan against the 48-hour figure in isolation.

### Pre-Conditions (Before Day 1)

**These pre-conditions map to Section 8 of the Project Intake Template.** The Orchestrator should complete the Intake's Governance Pre-Flight section; the governance stakeholders review and approve it. All "Blocking" items in Intake Section 8.1 must be marked "Complete" before Phase 0 begins. Record each pre-condition approval in `APPROVAL_LOG.md` as it is obtained.

**6 blocking pre-conditions** (referenced throughout the framework as "the 6 pre-conditions"):

1. **Insurance clearance:** Written broker confirmation per Section VIII.10. If coverage is insufficient, pursue the remediation path before proceeding.
2. **AI deployment path approved:** IT Security written approval per Section VII.
3. **Liability entity designated:** Which entity bears liability defined per Section VIII.9.
4. **Project sponsor assigned:** Named business executive (not the Orchestrator) who approves Phase 0 and Phase 3 gates. *(Intake Section 8.2)*
5. **Backup maintainer designated:** Second technologist with repository and hosting access per Section X. *(Intake Section 8.1)*
6. **ITSM registration:** Project registered in the enterprise portfolio tracker. Change ticket filed. *(Intake Section 8.1)*

**5 additional pilot preparation requirements:**

7. **Scope constraint:** Internal-only, non-critical, no PII, no financial data, no external users.
8. **Exit criteria defined:** What "success" looks like (expand), what "failure" looks like (stop), and who decides. *(Intake Section 8.5)*
9. **Time allocation:** The Orchestrator has dedicated blocked time (not "fit it in between meetings"). *(Intake Section 3.1)*
10. **Compliance screening completed:** Intake Section 8.4 completed with the project sponsor. *(Maps to Section VIII.11 of this document)*
11. **Governance enforcement test planned:** During the pilot, the organization will deliberately trigger at least one escalation path (e.g., a simulated missed monthly security audit or a simulated Orchestrator unavailability requiring backup maintainer activation) to verify that the governance chain functions as documented. Governance mechanisms that have never been exercised are theoretical, not proven. Schedule the test before the pilot begins so it is a planned activity, not an afterthought.

### Day 1 (4-6 hours)

1. Provision the approved AI subscription.
2. Install Claude Code on the developer's workstation.
3. Create a private GitHub repository with branch protection rules.
4. Install security tooling (Semgrep, gitleaks, Snyk CLI, license-checker).
5. Select a pilot project from the existing backlog — small, internal, non-critical.

### Day 2 (4-6 hours)

1. Execute Phase 0: Product Manifesto in 2-3 hours.
2. Execute Phase 1: Architecture and Project Bible in 2-3 hours.
3. Begin Phase 2: First feature built by end of day.

### Weeks 2-6

1. Complete Phase 2 construction (approximately one feature per day).
2. Execute Phase 3 validation.

### Weeks 6-8

1. Deploy to production (Phase 4).
2. **Handoff test:** Have the backup maintainer attempt to set up the development environment and triage a simulated issue using only the produced documentation. Measure how long it actually takes. Document where they get stuck. Fix the documentation. This test will surface gaps — that is its purpose.
3. Evaluate results against the following criteria:

### Pilot Evaluation Criteria

| Metric | What to Measure | How to Evaluate |
|---|---|---|
| **Actual hours vs. projected** | Total human hours across all phases | Within +20% of upper range estimate = success |
| **Actual cost vs. projected** | Tooling and infrastructure costs | Within budget = success |
| **Quality** | Defect rate in first month of production | Comparable to or better than existing internal applications |
| **Security** | Phase 3 scan results, any post-deployment findings | Zero critical/high findings at launch |
| **Handoff viability** | Time for backup maintainer to complete handoff test | Completion without Orchestrator assistance = success |
| **Orchestrator assessment** | Honest evaluation of AI output quality, workflow friction | Qualitative — would they do it again? |

The pilot is the proof of concept. No methodology document — including this one — substitutes for building something real and evaluating the result.

**Scaling decision:** Do not approve scaling beyond one pilot until pilot results are evaluated, the handoff test is completed, and the governance gaps (if any) identified during the pilot are remediated.

---

## XV. Document Artifacts Produced Per Project

The framework generates the following documentation artifacts across the project lifecycle. These artifacts serve dual purposes: they enable project continuity and they provide audit evidence.

| Artifact | Phase | Purpose | Audit Value |
|---|---|---|---|
| `CLAUDE.md` | 0 | AI agent operating instructions and project context | Process consistency evidence |
| `PROJECT_INTAKE.md` | 0 | Product definition, constraints, and requirements | Requirements baseline |
| `PRODUCT_MANIFESTO.md` | 0 | What the product does, for whom, and why | Business justification evidence |
| Compliance Screening Matrix | 0 | Regulatory applicability assessment | Compliance due diligence |
| `APPROVAL_LOG.md` | 0-4 | Structured record of all pre-condition and phase gate approvals | Governance trail — append-only, machine-parseable |
| Phase Gate Snapshots | 0-4 | Point-in-time snapshots of key documents at each phase gate | Immutable audit record per phase |
| In-Phase Decision Log | 2 | Record of significant decisions during construction | Decision audit trail |
| `PROJECT_BIBLE.md` | 1 | Complete technical specification including test strategy | Architecture decision evidence |
| Architecture Decision Records | 1-2 | Every major technology/design choice | Technical justification |
| `FEATURES.md` | 2+ | Living feature reference — what the product does and doesn't do | Feature scope evidence |
| `BUGS.md` | 2+ | Bug tracking — open, in-progress, and resolved issues | Defect management evidence |
| `docs/test-results/` | 3 | Archived scan reports, E2E results, accessibility audits, threat model validation | Test execution evidence — audit-grade |
| Security Audit Logs | 3 | SAST/DAST results, remediation actions | Security due diligence |
| `sbom.json` | 3 | Software Bill of Materials | Supply chain transparency |
| Performance Baselines | 3 | Lighthouse scores, response times | Performance baseline evidence |
| Penetration Test Report | 3 | External security assessment (Standard+ Track) | Security due diligence |
| `USER_GUIDE.md` | 3 | End-user documentation | User support evidence |
| `docs/INCIDENT_RESPONSE.md` | 4 | Severity classification, notification chains, rollback | Operational readiness |
| `RELEASE_NOTES.md` | 4 | User-facing: what the app does, known limitations, changes | Release documentation |
| `HANDOFF.md` | 4 | Complete transfer document | Continuity planning |
| Handoff Test Results | 4 | Documented results of backup maintainer test | Continuity validation |

**Enterprise knowledge management:** Key artifacts (HANDOFF.md, Architecture Decision Records, Incident Response Playbook) should be published to the enterprise knowledge management platform (Confluence, SharePoint, or equivalent) in addition to the repository. If the only people who can find the documentation are people with repository access, the documentation's value for organizational knowledge retention is limited.

---

## XVI. Next Steps

If this framework warrants adoption:

1. **Obtain insurance confirmation** per Section VIII.10 — this is a hard prerequisite.
2. **Secure IT Security approval** for the AI deployment path per Section VII.
3. **Define the liability entity** per Section VIII.9.
4. **Engage corporate counsel** on Sections VIII.1-VIII.6, particularly open-source licensing, AI-generated code ownership, data sovereignty, and the EU AI Act classification.
5. **Establish the governance overlay:** Named approvers per Section V, backup maintainer per Section X, ITSM integration per Section VI.
6. **Create or adopt the shared starter template** per Section XI.
7. **Identify a pilot project** from the existing backlog meeting the criteria in Section XIII and the pilot scope constraints in Section XIV.
8. **Assign a qualified technologist** — someone with architecture and infrastructure experience who can evaluate AI output critically. This is not a junior developer role.
9. **Define exit criteria** for the pilot — success conditions, failure conditions, and decision authority — before starting.
10. **Allocate dedicated time** for the Orchestrator — blocked half-days or full days, not interleaved with primary responsibilities.
11. **Execute the pilot** (Section XIV) and evaluate results.
12. **Do not scale** beyond the pilot until results are evaluated, handoff test is completed, and any governance gaps surfaced during the pilot are remediated.

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

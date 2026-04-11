# Senior VP of IT Security Review Prompt

## Usage

Run from the root of the Development Guardrails for Claude Code project directory:

```bash
claude -p "$(cat /path/to/03-security-review.md)"
```

---

## Prompt

You are a Senior Vice President of IT Security with 20+ years of experience spanning application security, infrastructure security, compliance, and risk management. You have led security programs at companies that deploy customer-facing applications handling PII, PHI, financial data (PCI-DSS scope), and government data (FedRAMP). You have been through SOC 2 Type II audits, PCI-DSS QSA assessments, HIPAA audits, and regulatory examinations. You have dealt with breach incidents, managed vulnerability disclosure programs, and built AppSec programs from scratch.

You are deeply skeptical of any tool that sits between a developer and production code, especially one that relies on an LLM to make security-relevant decisions. You evaluate security tools by: what attack surfaces they introduce, what they actually prevent vs. what they claim to prevent, whether they create a false sense of security, and whether they would survive scrutiny from a competent auditor or penetration tester.

You have been asked to perform a security-focused review of this framework. Regulated environments (SOC 2, HIPAA, PCI-DSS, FedRAMP) are outside the framework's current scope but are content gaps, not architectural limitations — the governance framework already provides role-based approval gate separation, audit evidence, and anti-self-approval controls. The current target is internal tools, departmental applications, and MVPs. Evaluate the framework's security controls against this stated scope. Also evaluate whether the framework adequately communicates scope boundaries to prevent premature deployment in regulated environments before compliance modules are available.

<framework_context>
Before you begin your review, understand these facts about the framework's design.
These are not opinions — they are documented design decisions you will verify in the
files. Your review should evaluate the framework against its stated operating model,
then note where that model has limitations.

OPERATING MODEL:
- This framework is designed for ONE person (the "Solo Orchestrator") who makes all
  decisions while the AI generates code within their constraints. It is not designed
  for teams. Evaluate it as a solo-operator methodology.
- The correct comparison baseline is NOT a well-staffed engineering team. It IS:
  (a) nothing gets built (the project stays in the backlog), (b) an engineer builds
  it with AI but no structure ("vibe coding"), or (c) the business unit works around
  it with spreadsheets and shadow IT. These are the realistic alternatives.

WHAT THE USER READS:
- The User Guide is the primary operating document. It walks the user through every
  step with specific prompts, commands, and review criteria.
- The user needs THREE documents open: the User Guide, the Project Intake, and their
  Platform Module. Everything else (Builder's Guide, Governance Framework, CLI
  Addendum) is reference material the User Guide points to at specific moments.
- The total documentation volume is a reference library, not a reading assignment.

WHAT THE INIT SCRIPT DOES:
- init.sh is interactive and walks the user through project setup. It collects project
  metadata, installs security tooling (Semgrep, gitleaks, Snyk), generates CLAUDE.md,
  creates CI/CD pipeline files, copies all framework documents, installs pre-commit
  hooks, initializes Git, and runs a health check. The user does not configure these
  manually.
- CI pipelines (testing, linting, SAST, dependency audit, license checking) work on
  first push. Release pipelines are explicitly documented as templates requiring
  per-project configuration (code signing, deployment secrets, store credentials).

VENDOR COUPLING:
- The Claude Code dependency is a deliberate proof-of-concept decision, not an
  architectural endpoint. The methodology layer (phases, TDD, threat modeling,
  governance) is agent-agnostic. The tooling layer (CLAUDE.md, Superpowers, MCP
  servers) is Claude Code-specific and designed to be retooled.
- Annual cross-model validation is mandatory for organizational deployments.
- The framework explicitly estimates 2-4 weeks retooling per active project to
  migrate to a different AI agent.

ENFORCEMENT MODEL:
- The framework documents a three-tier enforcement model and is transparent about
  which tier each control occupies:
  - Tier 1 (CI pipeline): Hard mechanical enforcement. Builds fail on SAST findings,
    secret detection, dependency vulnerabilities, license violations, and test failures.
  - Tier 2 (pre-commit hooks): Early warning and blocking. gitleaks blocks commits
    with secrets. Semgrep blocks OWASP Top 10 findings. Test co-location warns.
  - Tier 3 (CLAUDE.md + Builder's Guide): Guided behavior for the AI agent, with
    the human as the review layer at decision gates.
- Only Tier 1 is a hard enforcement boundary. The framework says this explicitly and
  repeatedly. Evaluate whether this transparency is adequate for the operating model,
  not whether Tier 3 controls would survive a hostile actor on a team.
- For organizational deployments, branch protection with required reviewers is
  recommended and will be required when compliance modules are available. This
  provides per-change code review that strengthens the governance audit trail beyond
  phase-gate-level review.

SCOPE:
- The following are outside the framework's current scope but are addressable through
  modular extensibility — they are content gaps, not architectural limitations:
  - Compliance-regulated systems (SOC 2, HIPAA, PCI-DSS, FedRAMP) — the governance
    framework already provides role-based approval gate separation (independent
    approvers at every organizational phase gate), append-only audit evidence, and
    anti-self-approval controls. What's missing is compliance-specific content modules
    and per-change code review enforcement (planned).
  - High-availability systems (99.99%+ SLA) — the framework can build HA-architectured
    software and produces Phase 4 handoff documentation. SLA guarantees are an
    infrastructure operations responsibility separate from the development methodology.
  - Large-scale distributed systems and enterprise integrations — addressable through
    new platform modules not yet written.
- The current target is: internal tools, departmental applications, prototypes, MVPs,
  and utilities that sit in the backlog because they don't justify a full team.
- Evaluate the framework against this stated scope. Note what would be needed to
  extend to broader scope, but do not penalize the framework for content modules that
  haven't been written yet when the architecture supports adding them.

CURRENT STATUS:
- The framework has been used by the author to build two complete MVP applications
  (K-PDF and MeshScope), both downloadable and functional on Windows, macOS, and
  Linux. An example project repo contains the complete artifact trail. The framework
  has not been validated through a formal organizational pilot. Evaluate accordingly.
</framework_context>

<task>
## Phase 1 — Full Codebase Security Review

Read every file in this project directory. Use `find . -type f` to get the complete file list, then read each file. Focus specifically on:
- Any code that executes (hooks, scripts, validators)
- Any configuration that affects what the LLM can or cannot do
- Any mechanism that claims to enforce security controls
- Any data flow — what information goes to the LLM, what comes back, what is logged
- Dependency declarations and supply chain surface

## Phase 2 — Security Assessment

Evaluate the framework against each category below. For each, provide:
- **Finding**: What you observed with specific file/line references
- **Threat Model**: What could go wrong and who the threat actor is
- **Severity**: Critical / High / Medium / Low / Informational
- **Exploitability**: How easy is it to bypass or abuse this
- **Remediation**: What must change

### Categories

1. **Attack Surface Analysis**
   - What new attack surfaces does this framework introduce to a development environment?
   - Can a malicious or compromised rule/hook inject code into a project?
   - Can a supply chain attack through the framework template repo compromise downstream projects?
   - What happens if the central template repository is compromised?
   - Is there any integrity verification (checksums, signatures) on framework components?

2. **LLM Security Boundary Analysis**
   - The framework sends instructions to an LLM. What prevents prompt injection through project files, user input, or dependency contents?
   - If a developer opens a file containing adversarial content, can it influence the LLM's behavior within the framework?
   - Does the framework leak sensitive project information (API keys, credentials, internal architecture) to the LLM API?
   - What data residency and retention implications exist from sending project context to Anthropic's API?
   - Is there any mechanism to prevent the LLM from generating code with known vulnerability patterns?

3. **Enforcement vs. Theater**
   - For each security-relevant rule in the framework, determine: Is it mechanically enforced (the LLM literally cannot bypass it), or is it a suggestion that relies on LLM compliance?
   - Create a table of every security claim and classify each as: Enforced, Partially Enforced, Advisory Only, or Not Implemented
   - What is the framework's actual security posture if the LLM ignores 100% of advisory rules?
   - Does the framework create a false sense of security that could lead teams to reduce other security measures?
   - **Defense-in-Depth Chain Analysis**: The framework claims a layered defense model (Swiss cheese). For each security-relevant concern, trace the FULL enforcement chain — from rules (LLM-read instructions) through hooks (mechanically executed scripts) through any post-hoc validation. Map which layers cover which concerns and identify: (a) concerns where multiple independent layers provide redundant coverage such that LLM non-compliance at the rule layer is caught by a hook at the enforcement layer, (b) concerns where only a single layer exists with no backup, and (c) concerns where all layers ultimately depend on LLM compliance with no mechanical fallback. The framework's thesis is that hooks compensate for LLM non-compliance with rules — evaluate whether this is actually true by examining what each hook concretely does (read the hook source code, not just the descriptions) and whether the hook can be bypassed, fails silently, or has gaps in coverage. Produce a **Defense Chain Map** showing each security concern and which layers actually cover it.

4. **Secrets and Sensitive Data Handling**
   - Does the framework have any mechanism to prevent secrets from being committed?
   - Does it detect or prevent hardcoded credentials, API keys, or tokens in generated code?
   - What happens to sensitive data that appears in hook execution logs?
   - Is there a data classification mechanism, or does all data get the same treatment?

5. **Compliance Framework Compatibility**
   - The framework explicitly excludes PCI-DSS, HIPAA, SOC 2, SOX, and FedRAMP environments. Evaluate whether the exclusion is clearly communicated and whether any mechanical controls enforce it, or whether it is merely documented.
   - If an organization ignores the exclusion and deploys a Solo Orchestrator application in a regulated environment, what specific controls are missing?
   - Does the compliance screening matrix in the Governance Framework adequately identify and route regulated scenarios before development begins?
   - Would this framework produce any evidence that satisfies SOC 2 change management controls or SOX code integrity controls, even though those environments are out of scope?

6. **Supply Chain Security**
   - What external dependencies does the framework require?
   - Are dependencies pinned to specific versions with integrity checks?
   - What is the update mechanism? Can a malicious update be pushed to all downstream projects?
   - Is there a software bill of materials (SBOM)?

7. **Incident Response Implications**
   - If a security incident occurs in code generated under this framework, what forensic evidence is available?
   - Can you trace a specific code change back to the framework rule that allowed or prevented it?
   - Does the framework maintain an audit trail?
   - What is the blast radius if the framework itself has a security flaw?

8. **Secure Development Lifecycle Integration**
   - Does this framework complement or conflict with SAST, DAST, SCA, and other AppSec tools?
   - Can it integrate with security gates in a CI/CD pipeline?
   - Does it support security-focused code review workflows?
   - Does it address any OWASP Top 10 categories, and if so, how effectively?

## Phase 3 — Output

Write the complete review to a file named `security-review-v1.md` in the project root directory.

The review MUST include:
- A security executive summary (suitable for a CISO or audit committee, 5-7 sentences)
- A **Threat Model Summary** identifying the top 5 threats this framework introduces or fails to mitigate
- Each category from Phase 2 with the full assessment structure
- A **Security Controls Matrix** listing every security-relevant feature and classifying it as: Enforced / Partially Enforced / Advisory / Not Present
- A **Defense Chain Map** showing each security concern mapped to its coverage layers (rule → hook → validation), identifying single-layer gaps and concerns with no mechanical enforcement
- A **Compliance Gap Analysis** table showing readiness against PCI-DSS, HIPAA, SOC 2, SOX, and FedRAMP
- A "Hard Stops" section — conditions under which this framework MUST NOT be used
- A "Minimum Viable Security" section — what must be added before this framework can be used in any environment handling sensitive data
- An overall security rating: Approved / Conditionally Approved / Not Approved, with justification

## Constraints

- Do NOT accept security-by-obscurity or security-by-policy as valid controls. Only mechanical enforcement counts as a security control.
- Do NOT give credit for intentions. If a rule says "do not commit secrets" but nothing prevents it, the control is NOT PRESENT.
- Do NOT assume the LLM will follow security instructions. Evaluate the framework's security posture as if the LLM ignores all advisory rules.
- Treat this as a real security assessment. If you would fail this in an audit, fail it here.
- Do NOT modify any framework files. Read-only assessment.
- If you find an actual security vulnerability, document it clearly but do NOT attempt to exploit it.
</task>

<stop_conditions>
- If you cannot read a file due to permissions, note it in the review and continue.
- If the project directory appears empty or is not a framework, state what you found and stop.
- Do NOT install anything, run builds, or execute any code.
- Do NOT attempt to test vulnerabilities by executing framework hooks or scripts.
</stop_conditions>

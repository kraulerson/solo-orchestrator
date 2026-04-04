# Solo Orchestrator Framework — Red Team Evaluation Prompt

> **Note:** This prompt evaluates the framework's documentation and methodology design. It does not test the framework's runtime enforcement mechanisms, which are limited to CI pipeline checks and Git hooks provided by the Claude Dev Framework. Use this prompt with any capable LLM to produce a customized security risk assessment of the framework documents.

You are a Senior Red Team Engineer and Application Security Architect with 15+ years of experience in offensive security, penetration testing, secure SDLC assessment, and AI/ML security. You have conducted security assessments for Fortune 500 companies, government agencies, and startups. You have direct experience exploiting applications built by solo developers, small teams, and AI-assisted development workflows.

You are evaluating a software development methodology called the "Solo Orchestrator Framework" — a structured process where a single technologist uses AI (LLMs) as the execution layer to build production applications. Your job is to find every way this methodology produces exploitable software, creates attack surface, or gives a false sense of security.

**Your evaluation mindset:** You are not reviewing this as a helpful consultant. You are reviewing it as an adversary who will be attacking applications built using this framework. Where would you focus your effort? What would you exploit first? What does this methodology miss that a real attacker wouldn't?

---

## PART 1: METHODOLOGY ATTACK SURFACE

Evaluate the framework's development process itself as an attack surface. For each area, rate as: **EXPLOITABLE** (an attacker can reliably abuse this), **WEAK** (provides some defense but with known bypass paths), or **ADEQUATE** (defense is sound for the stated use cases).

### 1. AI-Assisted Code Generation as Attack Vector

- Can an attacker influence the AI's code output through poisoned training data, malicious package names, or dependency confusion?
- Does the framework's reliance on AI-generated code create predictable patterns an attacker can fingerprint and target?
- How does the framework handle the AI generating code with subtle logic flaws that pass tests but create exploitable conditions (e.g., race conditions, TOCTOU vulnerabilities, off-by-one in access control)?
- Does the "human reviews test assertions" model actually catch security-relevant test gaps, or does it create a false confidence that the test suite covers the attack surface?
- Can an attacker craft inputs that the AI-generated validation logic handles differently than the developer expects?

### 2. Supply Chain Security

- Evaluate the dependency pinning strategy. Does exact version pinning actually prevent supply chain attacks, or does it just prevent drift while leaving the initial install vulnerable?
- Assess the framework's defenses against: typosquatting, dependency confusion, compromised maintainer accounts, malicious post-install scripts, and transitive dependency vulnerabilities.
- Does the SBOM generation and license checking actually reduce supply chain risk, or is it compliance theater?
- How does the framework handle the gap between "dependency installed" and "next security audit" — what is the exposure window?
- Evaluate the lockfile integrity check. What attacks does it catch and what does it miss?

### 3. Secrets and Credential Management

- Evaluate the `.env` file approach for secrets. What are the specific attack paths against this in the recommended hosting environments (Vercel, Railway, Supabase)?
- How does the framework handle secret rotation, revocation, and least-privilege scoping?
- Does the gitleaks pre-commit hook provide real protection, or is it trivially bypassable? What about secrets that don't match gitleaks' patterns?
- Assess the risk of secrets leaking through: AI conversation logs, error messages in production, CI/CD build logs, client-side bundles, and browser developer tools.
- Does the framework address API key scoping (read vs. write, IP restrictions, expiration)?

### 4. Authentication & Session Management

- The framework says "authentication is always the first feature built." Evaluate whether the recommended approach (Supabase auth, JWT, RLS) produces a secure authentication implementation when built by a non-security-specialist with AI assistance.
- What are the specific attack paths against AI-generated auth code? (Token prediction, session fixation, refresh token reuse, JWT algorithm confusion, multi-tenancy bypass)
- Does the RLS strategy actually prevent horizontal privilege escalation, or are there common RLS bypass patterns the framework doesn't address?
- How does the framework handle: password reset flows, account enumeration, brute force protection, credential stuffing, and session invalidation on privilege change?

### 5. AI Data Exfiltration

- The framework transmits source code and project context to an AI provider. Evaluate the actual risk: what can an attacker learn from intercepting, accessing, or extracting this data?
- If an attacker compromises the AI provider account, what do they gain? Full source code? Database schemas? API keys in context? Business logic?
- Does the framework's "abstract sensitive logic into separate files" mitigation actually work in practice, or does the AI need that context to generate correct code?
- Evaluate the risk of prompt injection through project files: can a malicious file in the repository influence the AI's behavior when the Orchestrator runs Claude Code?

---

## PART 2: APPLICATION-LEVEL ATTACK SIMULATION

For a typical application built using this framework (internal CRUD tool with authentication, hosted on Vercel + Supabase), describe the attack chain you would use to compromise it. Be specific about tools, techniques, and the order of operations.

### 6. External Attack Chain

Walk through a realistic attack against a Solo Orchestrator application from an external attacker's perspective:
- Reconnaissance: What fingerprinting tells you this was built with this methodology?
- Initial access: What is the most likely entry point?
- Privilege escalation: How do you move from authenticated user to admin, or from one tenant's data to another's?
- Data exfiltration: How do you extract data without triggering the monitoring described in the framework?
- Persistence: How do you maintain access?

### 7. Insider Threat

The Solo Orchestrator is a single person with full access to everything: source code, production database, hosting credentials, AI conversation history, and all secrets. Evaluate:
- What controls prevent the Orchestrator from acting maliciously?
- What audit trail exists if the Orchestrator exfiltrates data?
- If the Orchestrator's workstation is compromised, what is the blast radius?
- Does the framework's documentation strategy help or hurt in a forensic investigation?

### 8. Infrastructure Attack Surface

Evaluate the specific hosting stack (Vercel + Railway + Supabase + GitHub + Sentry):
- What is the weakest link in this chain?
- How does a compromise of one service cascade to others?
- What are the default security configurations of these platforms, and does the framework address hardening beyond defaults?
- Evaluate the monitoring and alerting stack: would it detect a sophisticated attacker, or only script kiddies?

---

## PART 3: SECURITY CONTROL EFFECTIVENESS

### 9. Static Analysis (Semgrep)

- What vulnerability classes does Semgrep with `p/owasp-top-ten` and `p/security-audit` rulesets reliably catch in the recommended stacks (Next.js, React, Node.js, Python)?
- What vulnerability classes does it consistently miss?
- Can an attacker deliberately write code patterns that evade Semgrep detection while remaining exploitable?
- Does running Semgrep in CI/CD (fail on findings) create a false sense of "secure" that discourages manual review?

### 10. Dynamic Analysis (OWASP ZAP Baseline)

- The framework uses `zap-baseline.py`. What does a baseline scan actually test vs. a full active scan?
- What percentage of the OWASP Top 10 does this baseline scan reliably detect?
- What common vulnerabilities in the recommended stacks would a ZAP baseline scan miss entirely?
- Is a single DAST scan at Phase 3 sufficient, or do vulnerabilities introduced in Phase 4 maintenance go undetected?

### 11. Testing as Security Control

- Evaluate TDD as a security mechanism. Does "tests pass" correlate with "application is secure"?
- What security properties cannot be verified through unit or E2E tests?
- Can an attacker identify gaps in test coverage by examining the test suite (if the repo is ever exposed)?
- Does the AI-generated test suite test the right things, or does it test what the AI generated (circular validation)?

### 12. Monitoring and Detection

- Evaluate Sentry + UptimeRobot as a detection stack. What attacks would trigger alerts? What attacks would be invisible?
- Does the framework's "alert on error rate >2%" threshold catch data exfiltration, privilege escalation, or enumeration attacks?
- What is the mean time to detect (MTTD) for: SQL injection, IDOR exploitation, auth bypass, and data exfiltration under this monitoring stack?
- Does the incident response plan enable effective forensic investigation, or has evidence been lost by the time the Orchestrator responds?

---

## PART 4: THREAT MODEL GAPS

### 13. Threats Not Addressed

List every threat category that the framework does not mention or inadequately addresses. For each, state: the threat, the likely impact, and whether the omission is acceptable for the stated use cases (internal tools, MVPs, <10K users) or a genuine gap.

### 14. False Security Claims

Identify any statement in the framework that would give an Orchestrator a false sense of security. Specifically: claims that are technically true but practically misleading, security controls that are present but insufficient for the threats they're supposed to address, and terminology that implies stronger protection than what is actually implemented.

### 15. What Would You Exploit First?

If you were given 40 hours to compromise an application built with this framework, describe your attack plan in priority order. What do you try first, second, third? What is your confidence level for each attack vector? What information would you need that the framework's documentation would provide if you gained access to the repository?

---

## SCORING

Rate each of the 15 areas on a 1-10 scale where:
- 1-3: **EXPLOITABLE** — Reliable attack paths exist with moderate effort
- 4-6: **WEAK** — Some defense exists but bypass paths are known or likely
- 7-8: **ADEQUATE** — Defense is sound for stated use cases, residual risk is acceptable
- 9-10: **HARDENED** — Defense exceeds expectations for the stated use cases

Provide an overall security posture score and a prioritized list of the top 5 remediations that would most improve the security of applications built with this framework.

---

## DELIVERABLE FORMAT

Structure your response in two parts:

**PART A: Full Assessment** — Complete findings for all 15 areas with specific technical detail, proof-of-concept attack descriptions where applicable, and rated scores.

**PART B: Executive Summary** — One page. Overall posture rating, top 5 exploitable weaknesses, top 5 recommended remediations ranked by impact, and a clear statement of what this framework is and is not secure enough for.

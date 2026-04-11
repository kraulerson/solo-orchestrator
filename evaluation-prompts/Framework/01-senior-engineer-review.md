# Senior Software Engineer Review Prompt

## Usage

Run from the root of the Development Guardrails for Claude Code project directory:

```bash
claude -p "$(cat /path/to/01-senior-engineer-review.md)"
```

---

## Prompt

You are a senior software engineer with 20+ years of hands-on experience building production systems across mobile (iOS/Android native and cross-platform), web (frontend SPA and server-rendered), backend services (REST, GraphQL, gRPC), desktop applications, embedded systems, and cloud-native microservices. You have shipped code in startups, mid-size companies, and Fortune 500 enterprises. You have seen frameworks come and go. You are skeptical of abstraction layers that promise to replace engineering judgment, and you evaluate tools by what they actually enforce versus what they claim to enforce.

You have been asked to perform a thorough, honest, and constructive technical review of the framework contained in this project directory. This is NOT a sales pitch evaluation — you are assessing whether this framework would survive contact with real-world software development.

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
  not whether Tier 3 controls would survive a hostile actor.
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
## Phase 1 — Full Codebase Inventory

Before writing a single line of review, you MUST read every file in this project. Use `find . -type f` to get the full file list, then read each file. Do NOT skip any file. Do NOT skim. You need to understand the full architecture before evaluating it.

After reading all files, create a mental inventory of:
- What the framework claims to do (from READMEs, docs, comments)
- What the framework actually does (from code, configs, hooks, rules)
- What mechanisms exist for enforcement vs. what relies on LLM compliance
- The dependency chain and external tool requirements

## Phase 2 — Structured Review

Evaluate the framework against each of the following categories. For each category, provide:
- **Assessment**: What you found (specific file references, specific mechanisms)
- **Strengths**: What works well and why
- **Weaknesses**: What fails, is fragile, or is misleading
- **Gap Analysis**: What is missing entirely
- **Verdict**: A 1-5 rating (1 = non-functional, 2 = significant issues, 3 = usable with caveats, 4 = solid, 5 = production-grade)

### Categories

1. **Architectural Soundness**
   - Is the hook/rule/profile system well-designed?
   - Does the modular architecture actually support extensibility, or is it tightly coupled?
   - Can new platforms (server, embedded, AWS) actually be added without modifying core files?
   - Is the template-to-project sync mechanism sound?

2. **Enforcement Integrity**
   - What percentage of the framework's rules are mechanically enforced (hooks, scripts, checks) vs. relying on the LLM following instructions?
   - Where the framework relies on LLM compliance, how robust is that reliance? What happens when the LLM ignores or misinterprets a rule?
   - Is the "Swiss cheese" defense model actually implemented, or is it a description of intent?
   - Test the failure modes: what happens if a hook fails silently? What happens if a profile is misconfigured?

3. **Real-World Development Viability**
   - Could a single technically literate person use this framework to take a project from idea to production deployment?
   - What is the maintenance burden for a single operator maintaining 1-3 applications?
   - How does this interact with CI/CD pipelines and existing tooling?
   - What happens when the framework's rules conflict with legitimate engineering decisions?

4. **Cross-Platform Credibility**
   - Does the framework actually handle platform-specific concerns (iOS signing, Android Gradle, web bundling, server deployment)?
   - Or does it operate at a layer above where platform-specific problems live?
   - Are the platform profiles genuinely different, or are they cosmetic variations?

5. **Scalability and Complexity Handling**
   - How does this framework handle the realistic project sizes it targets (internal tools, MVPs, departmental applications)?
   - What happens when the context window fills up? Does the framework degrade gracefully?
   - Does the framework appropriately scope itself away from projects that exceed solo-operator capacity (monorepos, multi-service architectures, polyglot codebases)?

6. **Honesty Audit**
   - Does the README/documentation accurately represent what the framework does?
   - Are there claims that exceed what the code actually delivers?
   - Would a developer be disappointed after adopting this based on the documentation?

7. **Comparison to Alternatives**
   - How does this compare to existing approaches: .cursorrules, Claude project instructions, custom CLAUDE.md files, MCP-based enforcement, pre-commit hooks, linters?
   - What does this framework provide that simpler approaches do not?
   - Is the added complexity justified by the added capability?

## Phase 3 — Output

Write the complete review to a file named `senior-engineer-review-v1.md` in the project root directory.

The review MUST include:
- An executive summary (3-5 sentences, no sugar-coating)
- Each category from Phase 2 with the full assessment structure
- A "Would I Use This?" section with your honest recommendation for: personal projects, small team projects, enterprise projects
- A "Critical Fixes" section listing the top 5 things that must change for the framework to be taken seriously
- An overall rating with justification

## Constraints

- Do NOT soften findings to be polite. Be direct.
- Do NOT fabricate strengths to balance criticism. If something is weak, say so.
- Do NOT compare to theoretical ideals — compare to what practitioners actually use today.
- Cite specific files and line numbers when making claims about what the code does or does not do.
- If a feature is documented but not implemented, call it out explicitly.
- Write for an audience of experienced engineers who will verify your claims.
</task>

<stop_conditions>
- If you cannot read a file due to permissions, note it in the review and continue.
- If the project directory is empty or does not appear to be a framework, output a short note explaining what you found and stop.
- Do NOT modify any framework files. This is a read-only review.
- Do NOT install dependencies or run any build commands.
</stop_conditions>

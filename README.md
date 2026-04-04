# Solo Orchestrator Framework

A structured software development methodology where a single experienced technologist builds production-deployable applications using AI as the execution layer. The human defines intent, constraints, and validation. The AI generates architecture, code, tests, and documentation within those constraints.

This is not vibe coding. It's a phase-gated, test-driven, documentation-mandatory process with security scanning, threat modeling, and incident response built in.

### AI Agent: Claude Code

**This framework is built on and tested with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic).** The init script, CLAUDE.md configuration, Superpowers plugin, MCP server integrations, and CLI Setup Addendum are all Claude Code-specific.

The methodology itself — the phases, TDD discipline, threat modeling, documentation mandates, and security scanning — is agent-agnostic and works with any sufficiently capable AI coding agent. The operational automation layer that makes the autonomous workflow practical is Claude Code. See [Vendor Dependency & Exit Path](#vendor-dependency--exit-path) for migration details.

---

## Start Here: The User Guide

**Read the [User Guide](docs/user-guide.md) first.** It walks you through the entire process from setup to production — what you do at each step, what external approvals you need, and what to expect as output. It has two parallel paths:

- **Personal projects** — lightweight, no governance overhead, start building immediately
- **Organizational deployments** — full approval chain, external stakeholder interactions, audit trail

The User Guide is your operating manual. The other documents (Builder's Guide, Governance Framework, Platform Modules) are reference material the guide points you to at the right time.

---

## Quick Start

```bash
git clone https://github.com/kraulerson/solo-orchestrator.git
cd solo-orchestrator
chmod +x init.sh
./init.sh
```

The init script will:
1. Check prerequisites (Git, language runtime)
2. Collect your project information (name, platform, track, language)
3. Install security tooling (Semgrep, gitleaks, Snyk, Claude Code)
4. Create your project directory with all framework documents and platform module
5. Generate `CLAUDE.md`, `.gitignore`, CI pipeline, release pipeline, and approval log
6. Initialize Git and run a health check (including language runtime validation)
7. Print your next steps

**After init completes:**
1. Authenticate: `claude` (OAuth) and `snyk auth`
2. Fill out `PROJECT_INTAKE.md` — this is your product definition
3. For organizational deployments: complete the 6 pre-conditions and record them in `APPROVAL_LOG.md`
4. Start Claude Code and tell it to begin

See the [User Guide](docs/user-guide.md) for detailed walkthrough of each step.

---

## Prerequisites

| Tool | Required | Install |
|---|---|---|
| **Git** | Yes | [git-scm.com](https://git-scm.com/downloads) |
| **Language runtime** | Yes | Depends on your language selection — Node.js, Python, Rust/Cargo, .NET SDK, JDK, Go, or Flutter. The init script validates your runtime during health check. |
| **Docker** | Recommended | [docker.com](https://www.docker.com/) — needed for OWASP ZAP DAST scanning |
| **Claude Code** | Recommended (framework is optimized for Claude Code; other AI coding agents can be used but the CLI Setup Addendum and Phase 2 workflow accelerators are Claude Code-specific) | Installed by init script, or manually: `brew install claude-code` (macOS), `winget install Anthropic.ClaudeCode` (Windows) |

### Windows Users

**Windows Subsystem for Linux (WSL) is required.** The init script, Claude Code, and the development toolchain (Git hooks, bash scripts, Unix CLI tools) require a Linux environment. Native Windows CMD/PowerShell will not work.

```bash
# Install WSL (PowerShell as Administrator)
wsl --install

# After restart, open Ubuntu from the Start menu
# Then install Node.js inside WSL:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git

# Clone and run from within WSL, not from Windows
```

All subsequent commands in this README and the Builder's Guide assume a Unix-like terminal (macOS Terminal, Linux shell, or WSL on Windows).

The init script handles installation of Semgrep, gitleaks, Snyk CLI, Lighthouse, and OWASP ZAP.

---

## What Gets Created

When you run `init.sh`, it creates a project directory with this structure:

```
your-project/
├── CLAUDE.md                           # Agent instructions (auto-generated)
├── PROJECT_INTAKE.md                   # Your product definition (fill this out)
├── .github/workflows/
│   ├── ci.yml                         # CI pipeline — language-specific (test, lint, SAST, audit)
│   └── release.yml                    # Release pipeline — platform-specific (build, sign, distribute)
├── .gitignore                          # Language + platform-appropriate ignores
├── .claude/
│   ├── framework/                     # Claude Dev Framework (Git hook guardrails)
│   ├── framework-config.yml           # Active profile configuration
│   └── framework-version.txt          # Pinned framework commit SHA
├── docs/
│   ├── framework/
│   │   ├── builders-guide.md           # The complete methodology
│   │   ├── governance-framework.md     # Enterprise governance (if organizational)
│   │   ├── executive-review.md         # CIO business case
│   │   └── cli-setup-addendum.md       # Claude Code configuration
│   ├── platform-modules/
│   │   └── [your-platform].md          # Platform-specific guidance
│   └── test-results/                   # Phase 3 test evidence (populated during build)
```

The init script generates **two pipelines** per project. The CI pipeline (`ci.yml`) is selected by your **language** — it handles testing, linting, SAST scanning, dependency auditing, and license checking using your language's toolchain. The release pipeline (`release.yml`) is selected by your **platform** — it handles building, signing, packaging, and distributing for your target platform. CI pipelines are working GitHub Actions workflows that run immediately on first push. Release pipelines are production-ready templates that require configuration (code signing, deployment secrets, store credentials) before first use.

All framework documents are copied into the project. Each project is self-contained — no external dependencies on this repo after init.

**Validation:** Both `scripts/validate.sh` and `scripts/check-phase-gate.sh` are copied into every created project. Run `bash scripts/validate.sh` from the project directory to check framework compliance — verifies all required files exist, CI is configured, security tools are accessible, phase artifacts match the project's current phase, and the approval log is up to date. The phase gate check also runs automatically in CI as a warning step. Run validation periodically to catch drift.

---

## How It Works

### The Documents

| Document | Purpose | Audience |
|---|---|---|
| **[User Guide](docs/user-guide.md)** | **Start here.** Step-by-step walkthrough from setup to maintenance. Personal and organizational paths. What you do, when, and why. | Solo Orchestrator |
| **Builder's Guide** | The complete methodology. Phases 0-4, prompts, quality gates, remediation tables, glossary. Reference material — the User Guide tells you when to consult it. | Solo Orchestrator |
| **Project Intake Template** | Structured input. Every decision the AI needs to work autonomously. You fill this out before Phase 0. | Solo Orchestrator |
| **Platform Modules** | Platform-specific architecture, tooling, testing, distribution. Referenced from the Builder's Guide at integration points. | Solo Orchestrator |
| **CLI Setup Addendum** | Claude Code configuration: Superpowers, Claude Dev Framework (Git hook guardrails), MCP servers (Context7, Qdrant), CLAUDE.md. | Solo Orchestrator |
| **Enterprise Governance Framework** | Approval authorities, compliance, risk, portfolio governance. Required for organizational deployments. | CIO, IT Security, Legal |
| **Executive Review** | Business case for CIO evaluation. Can be reviewed independently — including by AI models. | CIO, VP Engineering |

### The Process

```
Phase 0: Product Discovery        → Product Manifesto
Phase 1: Architecture & Planning   → Project Bible (+ Threat Model)
Phase 2: Construction (Loom)       → Working codebase + tests + docs
Phase 3: Validation & Security     → Scan results + test evidence
Phase 4: Release & Maintenance     → Production deployment + monitoring
```

Each phase produces artifacts that gate entry into the next phase. The AI executes within constraints. The human validates at decision gates.

### The Workflow

1. **Fill out the Intake** — product decisions, constraints, technical preferences
2. **Start Claude Code** — point it at the Intake and Builder's Guide
3. **The agent executes Phases 0-4** — asking you only for clarifying questions
4. **You review at decision gates** — architecture selection, test assertions, go-live
5. **You test the MVP** — pass/fail

The [User Guide](docs/user-guide.md) walks through each step in detail — what you do, what the agent does, what external approvals are needed (organizational), and what output to expect at each phase.

### Modular Architecture

The framework is built on two independent extensibility axes: **platforms** and **languages**.

**Platform modules** (`docs/platform-modules/`) are documentation — architecture patterns, tooling, testing strategies, and distribution guidance for a specific platform type. The Builder's Guide references them through callout markers (`⟁ PLATFORM MODULE`) at defined integration points. The core guide tells you *when* to do something; the module tells you *how* for your platform.

**Pipeline modules** (`templates/pipelines/`) are executable CI/CD configuration. They split into two dimensions:
- `ci/` — one template per **language** (test, lint, SAST, audit). Copied verbatim.
- `release/` — one template per **platform** (build, sign, package, deploy). Language-specific build commands are injected via placeholder substitution.

This separation means adding support for a new platform requires two files: a platform module (documentation) and a release pipeline template (CI/CD). Adding a new language requires one file: a CI template. Nothing in the Builder's Guide, existing modules, or existing templates changes. The web, desktop, and mobile modules were each built this way — added independently without modifying the core framework or each other.

**Extensibility example:** To add "Azure Microservices" as a platform, write `docs/platform-modules/azure-microservices.md` (standard module structure) and `templates/pipelines/release/azure-microservices.yml` (with `__PLACEHOLDER__` tokens for language injection). Add the option to the init script's platform prompt. The release pipeline generator auto-discovers templates by filename — no code change needed for pipeline generation.

---

## Platform Support

### Production-Deployable

| Platform | Module | Status |
|---|---|---|
| **Web** (SPA, full-stack, API) | `web.md` | v1.0 — Complete |
| **Desktop** (Windows, macOS, Linux) | `desktop.md` | v1.0 — Complete |
| **Mobile** (iOS, Android) | `mobile.md` | v1.0 — Complete |

### Roadmap

| Platform | Module | Status |
|---|---|---|
| **CLI** | — | No dedicated module. Core guide works standalone for simple CLI tools. |

New platform modules can be added without modifying the core framework. A module is production-deployable when it covers: Architecture → Tooling → Build & Packaging → Testing → Distribution → Maintenance.

---

## Language Support

The init script generates language-appropriate CI pipelines, `.gitignore` entries, and runtime validation for 10 languages:

| Language | CI: Build/Test | CI: Lint | CI: Dependency Audit | CI: License Check |
|---|---|---|---|---|
| **TypeScript** | `npm run build` / `npm test` | `npm run lint` | `npm audit` | `license-checker` |
| **JavaScript** | (same as TypeScript) | | | |
| **Python** | `pip install` / `pytest` | `ruff check` | `pip-audit` | `pip-licenses` |
| **Rust** | `cargo build` / `cargo test` | `cargo clippy`, `cargo fmt` | `cargo audit` | `cargo license` |
| **C#** | `dotnet build` / `dotnet test` | (built into build) | `dotnet list package --vulnerable` | `dotnet-project-licenses` |
| **Kotlin** | `./gradlew build` / `./gradlew test` | `detekt` (plugin) | `dependencyCheckAnalyze` (plugin) | `checkLicense` (plugin) |
| **Java** | (same as Kotlin) | | | |
| **Go** | `go build` / `go test -race` | `golangci-lint` | `govulncheck` | `go-licenses` |
| **Dart** | `flutter pub get` / `flutter test` | `flutter analyze` | `osv-scanner` (GitHub Action) | `dart_license_checker` |
| **Other** | TODO skeleton | TODO | TODO | TODO |

All CI templates include Semgrep SAST scanning. Languages that require external tools (Rust, Python, Dart) install them explicitly in the pipeline. JVM templates include Gradle plugin setup instructions for tools that require project configuration.

The release pipeline is driven by your **platform** selection, not language — the init script injects your language's build commands into the platform template via placeholder substitution.

---

## Project Tracks

| Track | When | What Changes |
|---|---|---|
| **Light** | Internal tools, personal utilities, <10 users | Skip market audit. Abbreviated Phase 3. Basic Phase 4. |
| **Standard** | External users, moderate complexity, <$10K/month | All phases. Lightweight market validation. |
| **Full** | Enterprise buyers, sensitive data, >$10K/month | All phases at max depth. Customer interviews. Pen testing mandatory. |

---

## Optional Enhancements

These are configured per the [CLI Setup Addendum](docs/cli-setup-addendum.md):

| Tool | What It Does |
|---|---|
| **Superpowers** | Agentic skills plugin for Claude Code. Subagent-driven development, strict TDD, systematic debugging, git worktrees. Phase 2 workflow accelerator. |
| **Claude Dev Framework** | Git hook-based guardrails for coding standards, security scanning, and documentation. Uses a layered defense model where multiple hook-based checks cover different failure modes. **Auto-installed by init.sh** into `.claude/framework/` with the appropriate profile for your platform. This is a separate project (github.com/kraulerson/claude-dev-framework) that can be used independently. The Solo Orchestrator init script installs it automatically, but it is not required. |
| **Context7 MCP** | Provides Claude with up-to-date library documentation during architecture selection and construction. |
| **Qdrant MCP** | Persistent semantic memory across Claude Code sessions. Stores project decisions and patterns. |

---

## For CIOs and Enterprise Evaluation

The [Executive Review](docs/executive-review.md) is designed to be evaluated independently — including by AI models. The [Enterprise Governance Framework](docs/governance-framework.md) provides the approval authorities, compliance screening, risk management, and portfolio governance required for organizational adoption.

Evaluation prompts for stress-testing the framework are in `evaluation-prompts/`:
- **CIO Evaluation** — 10 business dimensions, 6 technical dimensions
- **Red Team Evaluation** — 15 security attack surface areas
- **Legal Analysis** — 15 legal risk domains

---

## Methodology vs. Tooling: What's Portable

The Solo Orchestrator Framework has two distinct layers. Understanding the boundary matters for evaluating vendor risk, planning migrations, and assessing long-term viability.

### The Methodology Layer (Agent-Agnostic, Durable)

These elements work with any sufficiently capable AI coding agent and do not depend on Claude Code:

- **The process:** Five-phase, gate-controlled development (Discovery → Architecture → Construction → Validation → Release)
- **Quality mandates:** Test-driven development, per-feature security audits, threat modeling, documentation requirements
- **Governance controls:** Approval authorities, compliance screening, backup maintainer model, portfolio management, escalation paths
- **Document artifacts:** Product Manifesto, Project Bible, ADRs, test results, HANDOFF.md, Approval Log
- **Security tooling:** Semgrep, gitleaks, Snyk, OWASP ZAP, SBOM generation — all agent-independent
- **CI/CD pipelines:** Language-specific CI and platform-specific release pipelines — standard GitHub Actions
- **Templates:** Intake Template, Governance Framework, Platform Modules, pipeline modules

The methodology layer represents the framework's durable value. Phases, gates, TDD discipline, and governance controls are software engineering practices that predate AI coding tools and will outlast any specific one.

### The Tooling Layer (Claude Code-Specific, Replaceable)

These elements are optimized for Claude Code and require retooling to use a different AI agent:

- **CLAUDE.md** → equivalent agent configuration file for the new agent
- **Superpowers plugin** → equivalent agentic skills (subagent dispatch, TDD enforcement, worktrees)
- **Context7 / Qdrant MCP servers** → equivalent context and memory tools (or manual context management)
- **CLI Setup Addendum** → rewrite for new agent's configuration model
- **Init script CLAUDE.md generation** → rewrite template for new agent

The tooling layer is a workflow accelerator, not a dependency. The Build Loop in Phase 2 works without Superpowers — the agent executes sequentially with the Orchestrator directing each step. Superpowers makes it faster; its absence makes it manual, not impossible.

### Current Status: Proof of Concept on a Single Vendor

The Claude Code-specific tooling layer is a deliberate proof-of-concept decision, not an architectural endpoint. The methodology must be validated before the abstraction layer is worth building. Building multi-vendor support before confirming the methodology works would be premature engineering — solving the portability problem before confirming there is a methodology worth porting.

**The planned evolution:**
1. **Current (v1.0):** Validate the methodology on Claude Code. Confirm the phases, gates, TDD discipline, and governance controls produce the intended outcomes.
2. **Next:** Once validated through organizational pilots, retool the automation layer to support multiple AI coding agents. The methodology layer requires no changes — it is already agent-agnostic.

The annual cross-model validation (required for organizational deployments — see SOI-003-GOV, Section IX) serves dual purposes: it validates the exit path from Claude Code *and* prepares the ground for the multi-vendor phase by ensuring Project Bibles remain vendor-neutral technical specifications rather than Claude-specific prompt documents.

### Exit Path

**Estimated retooling per active project:** 2-4 weeks, primarily spent on: rewriting the agent configuration, validating the new agent produces comparable output quality on the existing codebase, and adjusting prompts. The codebase, tests, documentation, and security tooling transfer without modification.

**Risk mitigation:** Periodically verify that the Project Bible produces coherent output when provided to a different AI agent. If the Bible is well-written, the project is recoverable regardless of which agent built it. The Enterprise Governance Framework recommends annual cross-model validation to keep this exit path tested (see SOI-003-GOV, Section IX).

---

## What This Is Not

- Not for compliance-regulated systems (SOC 2, HIPAA, PCI-DSS, FedRAMP)
- Not for high-availability systems (99.99%+ SLA)
- Not for large-scale distributed systems (microservices, multi-region)
- Not for enterprise integration projects (SAP, Salesforce, ERP)

It's for the projects that sit in the backlog because they don't justify a team: internal tools, departmental applications, prototypes, MVPs, and utilities.

## What This Provides Beyond a Plain Setup

| Capability | CLAUDE.md + Hooks + CI | Solo Orchestrator |
|---|---|---|
| Agent instructions | Single CLAUDE.md file | CLAUDE.md + Builder's Guide + Platform Module — comprehensive AI instruction set |
| Project planning | Ad hoc | Structured Intake Template + phase-gated discovery (Phases 0-1) |
| CI security scanning | Manual pipeline setup | 8 language-specific templates with Semgrep SAST, dependency audit, license checking |
| Release pipeline | Manual pipeline setup | 4 platform-specific templates (web, desktop, mobile, CLI) |
| Platform guidance | None | Web, Desktop, Mobile modules with architecture patterns, tooling, testing, distribution |
| Enterprise governance | None | Full framework with approval authorities, compliance screening, portfolio governance |
| Evaluation tooling | None | LLM-executable red team and legal analysis prompts |

The methodology, intake template, platform modules, and CI pipeline templates are the primary value. The framework packages operational knowledge that would otherwise need to be discovered project-by-project.

---

## Known Limitations

- **Enforcement is primarily CI-based.** The CI pipeline (SAST, dependency audit, license checking, tests) provides mechanical enforcement. Phase gates, TDD ordering, scope control, and documentation updates rely on the AI agent following instructions in CLAUDE.md and the Builder's Guide. This is the nature of a methodology framework — it provides comprehensive guidance, but enforcement beyond CI depends on the operator and agent following the process.
- **Release pipelines require configuration.** CI pipelines work immediately on first push. Release pipelines are production-ready templates with TODOs for code signing, deployment secrets, and store credentials that must be configured before first release.
- **CI/CD templates are GitHub Actions only.** The framework provides pipeline templates for GitHub Actions. GitLab CI and Azure DevOps are supported as repository hosts, but pipeline templates must be translated manually.
- **Single language per init.** The init script generates CI for one primary language. Polyglot projects (e.g., TypeScript frontend + Python backend) require manual addition of CI steps for secondary languages.
- **Not yet validated through an organizational pilot.** The framework has been used for personal projects. The pilot evaluation process (Executive Review, Section X) defines how to test it organizationally. Treat this as a well-structured hypothesis, not a proven methodology.

---

## Current Status

This is the initial release of the Solo Orchestrator Framework. It has been used by the author to build personal projects but has not yet been validated through a formal organizational pilot. The framework's own pilot evaluation process (see Executive Review, Section X) defines how to test it. Treat this as a well-structured hypothesis, not a proven methodology. Feedback from real-world usage will drive future iterations.

---

## Document Versions

| Document | Version | Date |
|---|---|---|
| Builder's Guide | v1.0 | 2026-04-02 |
| Enterprise Governance Framework | v1.0 | 2026-04-02 |
| Executive Review | v1.0 | 2026-04-02 |
| Project Intake Template | v1.0 | 2026-04-02 |
| CLI Setup Addendum | v1.0 | 2026-04-02 |
| User Guide | v1.0 | 2026-04-02 |
| Platform Module: Web | v1.0 | 2026-04-02 |
| Platform Module: Desktop | v1.0 | 2026-04-02 |
| Platform Module: Mobile | v1.0 | 2026-04-02 |

---

## Legal Notices

This framework is a software development methodology distributed under the MIT License. It does not guarantee the quality, security, fitness for purpose, or legal compliance of software built using it. Organizations adopting this framework assume all responsibility for validating, testing, securing, and maintaining the applications they build.

**AI-Generated Code:** Software built using this framework is generated in part by AI (Large Language Models). The copyright status of AI-generated code is legally unsettled under current U.S. and international law. Organizations should not assume full copyright protection for AI-generated code without consulting qualified intellectual property counsel. The framework does not scan for potential patent or copyright infringement in generated code.

**Not Legal or Compliance Advice:** This framework includes references to regulatory requirements (GDPR, CCPA, EU AI Act, and others) for informational purposes. These references do not constitute legal advice and should not be treated as a compliance program. Engage qualified legal counsel in all relevant jurisdictions before deploying applications that handle personal data, operate in regulated industries, or serve users in jurisdictions with specific legal requirements.

**Legal Documents:** Any Privacy Policies, Terms of Service, or other legal documents generated during the framework's build process must be reviewed by qualified legal counsel before deployment. AI-generated legal documents should not be deployed without attorney review.

**External Dependencies:** The init script clones [claude-dev-framework](https://github.com/kraulerson/claude-dev-framework) (MIT License) into the project for Git hook-based guardrails. This dependency's license has been verified as MIT-compatible.

---

## License

MIT — see [LICENSE](LICENSE).

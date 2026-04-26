# Solo Orchestrator Framework

A structured software development methodology where a single technically literate person builds MVP-grade applications using AI as the execution layer. The human defines intent, constraints, and validation. The AI generates architecture, code, tests, and documentation within those constraints. Applications are built with production practices (TDD, security scanning, documentation) and structured for production readiness through subsequent refinement.

This is not vibe coding. It's a phase-gated, test-driven, documentation-mandatory process with security scanning, threat modeling, and incident response built in.

### AI Agent: Claude Code

**This framework is built on and tested with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic).** The init script, CLAUDE.md configuration, Superpowers plugin, MCP server integrations, and CLI Setup Addendum are all Claude Code-specific.

The methodology itself — the phases, TDD discipline, threat modeling, documentation mandates, and security scanning — is agent-agnostic and works with any sufficiently capable AI coding agent. The operational automation layer that makes the autonomous workflow practical is Claude Code. See [Methodology vs. Tooling: What's Portable](#methodology-vs-tooling-whats-portable) for migration details.

---

> **How much do you need to read?** About 30 minutes to set up and get oriented. The [User Guide](docs/user-guide.md) walks you through everything step by step — read each section as you reach that step, not all at once. The [Intake Wizard](scripts/intake-wizard.sh) guides you through your project definition interactively. Your [Platform Module](docs/platform-modules/) is reference material for your specific platform. That's it. The Builder's Guide, Governance Framework, and other documents are a reference library — the User Guide points you to them at the right moment. You don't read them upfront. All framework documents are machine-readable — you can load them into any AI assistant and ask questions instead of reading them manually.

---

## Start Here: The User Guide

**Read the [User Guide](docs/user-guide.md) first.** It walks you through the entire process from setup to first release — what you do at each step, what external approvals you need, and what to expect as output. It has two parallel paths:

- **Personal projects** — lightweight, no governance overhead, start building immediately
- **Organizational deployments** — full approval chain, external stakeholder interactions, audit trail. Includes POC modes (Sponsored and Private) to validate the framework before completing all governance approvals.

The User Guide is your operating manual. The other documents (Builder's Guide, Governance Framework, Platform Modules, Security Scan Guide, Evaluation Prompts) are reference material the guide points you to at the right time. The [Intake Wizard](docs/user-guide.md#using-the-intake-wizard) guides you through filling out your project definition.

**Want to see what it produces?** The [Example Project](https://github.com/kraulerson/solo-orchestrator-example-project) contains the complete artifact trail from building [MeshScope](https://github.com/kraulerson/meshscope) — a cross-platform 3D mesh viewer. Browse the artifacts from each phase to see what the framework produces before you commit to using it.

---

## Quick Start

```bash
git clone https://github.com/kraulerson/solo-orchestrator.git
cd solo-orchestrator
chmod +x init.sh
./init.sh
```

> **Preview first?** Run `./init.sh --dry-run` to see what will be installed and created without making any changes.

The init script will:
1. Check prerequisites — offers to auto-install Git, Node.js, and your language runtime if missing
2. Collect your project information (name, platform, track, language)
3. Install security tooling (Semgrep, gitleaks, Snyk, Claude Code, Lighthouse)
4. Create your project directory with all framework documents, platform module, and utility scripts
5. Generate `CLAUDE.md`, `.gitignore`, CI pipeline, release pipeline, and approval log
6. Initialize Git and run a health check
7. Print your next steps

**After init completes:**
1. Authenticate: `claude` (OAuth) and `snyk auth`
2. Fill out the Intake: run `bash scripts/intake-wizard.sh` for a guided walkthrough (interactive script or AI-assisted conversation), or open `PROJECT_INTAKE.md` directly. For **personal or Private POC projects only**, you can paste the intake form into your AI of choice and work with it to fill out the sections — but read through the result yourself to verify accuracy. Do not use this shortcut for organizational or production projects where intake accuracy drives compliance decisions.
3. For organizational deployments: complete governance pre-conditions — or use a POC mode (Sponsored or Private) to defer non-technical approvals while you validate the framework
4. Start Claude Code and give it the full project context:
   ```
   Read the following files in order, then confirm what you understand about
   this project before taking any action:
   1. CLAUDE.md (your instructions and constraints)
   2. PROJECT_INTAKE.md (the product definition)
   3. docs/reference/builders-guide.md (the phase-gate methodology)
   4. docs/platform-modules/<your-platform>.md (platform-specific guidance)
   5. .claude/phase-state.json (current phase)
   After reading, summarize: the project goal, your constraints, the current
   phase, and what tools/MCP servers are available to you. Then begin Phase 0.
   Ask me only for clarifying questions.
   ```

See the [User Guide](docs/user-guide.md) for detailed walkthrough of each step.

---

## Key Features

- **Phase-gated development** — Five phases (Discovery, Architecture, Construction, Validation, Release) with explicit gate criteria. No skipping ahead.
- **Security by default** — SAST (Semgrep), secret detection (gitleaks), dependency scanning (Snyk), license compliance, and DAST (OWASP ZAP) installed and configured automatically. CI pipeline blocks merges on findings.
- **Test-driven development** — Tests first, implementation second. Pre-commit hooks warn when implementation ships without tests.
- **9 languages, extensible to any** — TypeScript, Python, Rust, Go, C#, Kotlin, Java, Dart, Swift ship out of the box. Need C++? Drop one CI template at `templates/pipelines/ci/cpp.yml` — it appears as a language option automatically.
- **4 platforms, extensible to any** — Web, desktop, mobile, and MCP server ship out of the box. Need Azure Microservices? Drop a platform module at `docs/platform-modules/azure-microservices.md` and a release pipeline at `templates/pipelines/release/azure-microservices.yml` — it appears as a platform option automatically. **No code changes to the init script.** The framework auto-discovers platforms and languages from the file system. See [Modular Architecture](#modular-architecture) for details.
- **Enterprise governance** — Approval authorities, compliance screening, insurance requirements, backup maintainer, and audit trail. Full documentation suite for CIO/CISO/Legal review.
- **POC modes** — Sponsored and Private POC modes defer governance overhead while you validate the approach with production-quality technical work.
- **One command setup** — `./init.sh` handles everything: tool installation, project scaffolding, CI/CD generation, security tooling, Git initialization, and health check.

---

## Prerequisites

| Tool | Required | Install |
|---|---|---|
| **Git** | Yes | Init script offers to install automatically (brew/apt/dnf). Or install manually: [git-scm.com](https://git-scm.com/downloads) |
| **Node.js** | Yes | Floor: 18.17+ (matches init script version check). **Recommended: 20 LTS or 22 LTS** — Node 18 reached end-of-life April 2025, so new installs should pick a supported LTS. Init script offers to install automatically. Required as infrastructure tooling (Snyk CLI, license-checker) regardless of your project language. Also the runtime for JS/TS projects. |
| **Language runtime** | Yes | Python, Rust/Cargo, .NET SDK, JDK, Go, or Flutter (if not using Node.js/TypeScript). Init script offers to install your selected runtime automatically. |
| **jq** | Yes | Init script offers to install automatically (brew/apt/dnf). Required by the Development Guardrails for Claude Code for JSON operations. |
| **Docker** | Recommended | Init script offers to install automatically. macOS: choice of Colima (recommended — headless, no license required, auto-starts on boot) or Docker Desktop. Linux: system package with systemd auto-start. Used by Qdrant (persistent semantic memory) and OWASP ZAP (DAST scanning). |
| **Claude Code** | Recommended | Installed by init script. Framework is optimized for Claude Code; other AI coding agents can use the methodology but the CLI Setup Addendum and Phase 2 workflow accelerators are Claude Code-specific. |

Init also auto-installs security tooling: Semgrep (SAST), gitleaks (secret detection), Snyk CLI (dependency scanning), Lighthouse (web performance), and OWASP ZAP (DAST, requires Docker).

### Windows Users

**Windows Subsystem for Linux (WSL) is required.** The init script, Claude Code, and the development toolchain (Git hooks, bash scripts, Unix CLI tools) require a Linux environment. Native Windows CMD/PowerShell will not work.

```bash
# Install WSL (PowerShell as Administrator)
wsl --install

# After restart, open Ubuntu from the Start menu
# Install Git and jq (needed before init can run):
sudo apt install -y git jq

# Clone and run from within WSL, not from Windows
# The init script will offer to install Node.js and other prerequisites
```

### Linux Users

The init script supports **apt** (Debian, Ubuntu), **dnf** (Fedora, RHEL), and **pacman** (Arch, Manjaro, EndeavourOS) package managers. Other distributions should install the prerequisite tools manually before running init.

All subsequent commands in this README and the Builder's Guide assume a Unix-like terminal (macOS Terminal, Linux shell, or WSL on Windows).

---

## What Gets Created

When you run `init.sh`, it creates a project directory with this structure:

### Project directory (created by init.sh)

```
your-project/
├── CLAUDE.md                              # Agent instructions (auto-generated)
├── PROJECT_INTAKE.md                      # Your product definition (fill this out)
├── APPROVAL_LOG.md                        # Phase gate approval record
├── FEATURES.md                            # Living feature reference
├── BUGS.md                                # Bug tracking
├── CHANGELOG.md                           # Change log (8 categories)
├── RELEASE_NOTES.md                       # User-facing release history
├── .github/workflows/
│   ├── ci.yml                            # CI pipeline — language-specific
│   └── release.yml                       # Release pipeline — platform-specific
├── .gitignore                             # Language + platform-appropriate ignores
├── .git/hooks/
│   └── pre-commit                        # Secret detection + SAST quick scan
├── .claude/
│   ├── framework/                        # Development Guardrails for Claude Code (gates, hooks, rules)
│   ├── manifest.json                     # CDF config: pinned commit, active profile, active rules/hooks
│   ├── settings.json                     # Claude Code permissions + hook registrations
│   ├── settings.local.json               # Project-local MCP override (Qdrant collection name)
│   ├── phase-state.json                  # Current phase + gate dates + POC mode
│   ├── process-state.json                # Sequential step enforcement state
│   ├── tool-preferences.json             # Resolved tool matrix context for this project
│   ├── tool-usage.json                   # MCP tool usage tracking (per session)
│   ├── build-progress.json               # Features completed + test gate state
│   └── orchestrator-source.json          # Path to solo-orchestrator source (for reconfigure/verify)
├── docs/
│   ├── reference/
│   │   ├── builders-guide.md              # The complete methodology
│   │   ├── user-guide.md                 # Step-by-step walkthrough
│   │   ├── governance-framework.md        # Enterprise governance
│   │   ├── executive-review.md            # CIO business case
│   │   ├── cli-setup-addendum.md          # Claude Code configuration
│   │   └── security-scan-guide.md         # Common scan findings explained
│   ├── ADR documentation/                 # Architecture Decision Records
│   ├── api and interfaces/                # Interface/API documentation
│   ├── phase-0/                           # FRD, user journey, data contract (pre-Manifesto)
│   ├── security-audits/                   # Per-feature security audit findings
│   ├── snapshots/                         # Phase gate document snapshots
│   ├── platform-modules/
│   │   └── [web|desktop|mobile|mcp_server].md  # Platform-specific guidance
│   └── test-results/                      # Phase 3 test evidence (empty until Phase 3)
├── evaluation-prompts/
│   └── Projects/
│       ├── bases/                         # 6 adversarial reviewer perspectives
│       ├── modules/                       # Platform-specific review context
│       ├── compose.sh                     # Generates review prompts for your project
│       ├── run-reviews.sh                 # Runs all reviews in sequence
│       └── README.md                      # How to use evaluation prompts
├── scripts/
│   ├── intake-wizard.sh                   # Guided intake wizard (interactive or AI-assisted)
│   ├── validate.sh                        # Framework compliance checker
│   ├── verify-install.sh                  # Installation verification + auto-remediation
│   ├── check-phase-gate.sh                # Phase gate validator + snapshot creator
│   ├── check-versions.sh                  # Tool version check against minimums + latest
│   ├── check-updates.sh                   # Upstream framework doc update checker
│   ├── check-maintenance.sh               # Maintenance cadence (weekly/monthly/quarterly)
│   ├── check-changelog.sh                 # Changelog freshness (CI annotation)
│   ├── check-session-state.sh             # CLAUDE.md staleness (CI annotation)
│   ├── resolve-tools.sh                   # Tool matrix resolver (by platform/lang/track/phase)
│   ├── upgrade-project.sh                 # Track/deployment/POC upgrade
│   ├── reconfigure-project.sh             # Regenerate after platform/lang/name change
│   ├── test-gate.sh                       # UAT interval + SEV-1/2 bug gate
│   ├── process-checklist.sh               # Sequential step enforcement state machine
│   ├── pre-commit-gate.sh                 # PreToolUse hook: blocks commits on gaps
│   ├── track-tool-usage.sh                # PostToolUse hook: MCP usage tracking
│   ├── session-version-check.sh           # SessionStart hook: version check
│   ├── session-test-gate-check.sh         # SessionStart hook: test gate + MCP gate init
│   ├── session-mcp-gate.sh                # PreToolUse hook: block Write/Edit until MCP called
│   ├── session-end-qdrant-reminder.sh     # Stop hook: Qdrant storage reminder
│   ├── resume.sh                          # Session resume prompt generator
│   └── lib/helpers.sh                     # Shared shell helpers (colors, logging, MCP detection)
├── templates/
│   ├── generated/                         # 26 .tmpl files (CLAUDE.md, Manifesto, Bible, ADR, ...)
│   ├── tool-matrix/                       # Tool resolution matrix per platform
│   │   ├── common.json                    # Universal tools (git, node, jq, docker, ...)
│   │   ├── web.json
│   │   ├── desktop.json
│   │   └── mobile.json
│   └── intake-suggestions/                # Context-aware suggestions for the intake wizard
│       ├── common.json                    # Platform-independent (budget, timeline, accessibility)
│       ├── web.json                       # Web platform (auth, hosting, DB, frameworks)
│       ├── desktop.json                   # Desktop platform
│       ├── mobile.json                    # Mobile platform
│       └── mcp_server.json                # MCP server platform (transport, persistence, SDK)
├── tests/
│   └── uat/                               # UAT session working dir + templates (populated Phase 2+)
│       ├── templates/                     # Session template (HTML + Markdown)
│       └── sessions/                      # One subdir per session: agent-results/, submissions/
└── .solo-orchestrator/
    └── init-YYYYMMDD-HHMMSS.log           # Init script log (one per run)
```

> **Note on the tree:** This is the representative layout produced by a fresh init. State files in `.claude/` (`phase-state.json`, `process-state.json`, `build-progress.json`, `tool-usage.json`) mutate as the project progresses. To see your actual current state, `ls -la .claude/` and `ls scripts/` — those are authoritative.

### System-wide installations (with user prompting)

The init script installs these tools globally on your machine. Each installation prompts for confirmation — nothing is installed without your approval.

| Tool | Purpose | Install Method |
|---|---|---|
| **Semgrep** | SAST scanning (static analysis) | brew (macOS) or pip (Linux) |
| **gitleaks** | Secret detection in commits | brew (macOS) or auto-downloaded binary (Linux) |
| **Snyk CLI** | Dependency vulnerability scanning | npm global |
| **Claude Code** | AI coding agent | brew (macOS) or npm global (Linux) |
| **Lighthouse** | Web performance auditing (web projects only) | npm global |
| **OWASP ZAP** | DAST scanning (web projects with Docker only) | Docker image pull |

**Auto-installed external framework (separate MIT repository):**

| Component | Purpose | Install Method |
|---|---|---|
| **Development Guardrails for Claude Code** | Git hook-based guardrails: session-start checks, pre-commit hooks, profile-driven rules. Version pinned in `.claude/manifest.json`. | `init.sh` clones [`kraulerson/claude-dev-framework`](https://github.com/kraulerson/claude-dev-framework) to `~/.claude-dev-framework` (reused across projects), then runs its init to install per-project hooks into `.claude/framework/`. |

**Optional enhancements (user-configured after init):**

| Tool | Purpose | How to Install |
|---|---|---|
| **Superpowers** | Agentic skills plugin for Claude Code (TDD, subagents, debugging) | `claude plugins add superpowers` |
| **Context7 MCP** | Live library documentation for the AI agent | `claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp` |
| **Qdrant MCP** | Persistent semantic memory across sessions | Docker container + MCP server config |

See the [CLI Setup Addendum](docs/cli-setup-addendum.md) or its [Quick Setup](docs/cli-setup-addendum.md#quick-setup--all-recommended-enhancements) section.

### Pipelines

The init script generates **two pipelines** per project. The CI pipeline (`ci.yml`) is selected by your **language** — it handles testing, linting, SAST scanning, dependency auditing, and license checking. The release pipeline (`release.yml`) is selected by your **platform** — it handles building, signing, packaging, and distributing. CI pipelines are working GitHub Actions workflows that run immediately on first push. Release pipelines are templates that require configuration (code signing, deployment secrets, store credentials) before first release.

All framework documents are copied into the project. Each project is self-contained — no external dependencies on this repo after init.

---

## How It Works

### The Documents

| Document | Purpose | Audience |
|---|---|---|
| **[User Guide](docs/user-guide.md)** | **Start here.** Step-by-step walkthrough from setup to first release. Personal and organizational paths. What you do, when, and why. | Solo Orchestrator |
| **Builder's Guide** | The complete methodology. Phases 0-4, prompts, quality gates, remediation tables, glossary. Reference material — the User Guide tells you when to consult it. | Solo Orchestrator |
| **Project Intake Template** | Structured input. Every decision the AI needs to work autonomously. Fill out using the [Intake Wizard](docs/user-guide.md#using-the-intake-wizard) or directly before Phase 0. | Solo Orchestrator |
| **Platform Modules** | Platform-specific architecture, tooling, testing, distribution. Referenced from the Builder's Guide at integration points. | Solo Orchestrator |
| **CLI Setup Addendum** | Claude Code configuration: Superpowers, Development Guardrails for Claude Code (Git hook guardrails), MCP servers (Context7, Qdrant), CLAUDE.md. | Solo Orchestrator |
| **Security Scan Guide** | Plain-language explanations of the most common Semgrep and Snyk findings. How to determine if a finding is real or a false positive. | Solo Orchestrator |
| **Evaluation Prompts** | 6 adversarial reviewer perspectives (senior engineer, CIO, security, legal, technical user, red team) for project validation. | Solo Orchestrator, Reviewers |
| **Enterprise Governance Framework** | Approval authorities, compliance, risk, portfolio governance. Required for organizational deployments. | CIO, IT Security, Legal |
| **Executive Review** | Business case for CIO evaluation. Can be reviewed independently — including by AI models. | CIO, VP Engineering |

### The Process

**Full path** (Personal projects + Organizational Production):

```
Phase 0: Product Discovery        → Product Manifesto
Phase 1: Architecture & Planning   → Project Bible (+ Threat Model)
Phase 2: Construction (Loom)       → Working codebase + tests + docs
Phase 3: Validation & Security     → Scan results + test evidence
Phase 4: Release & Maintenance     → MVP release + monitoring
```

**POC path** (Sponsored POC + Private POC):

```
Phase 0: Product Discovery        → Product Manifesto
Phase 1: Architecture & Planning   → Project Bible (+ Threat Model)
Phase 2: Construction (Loom)       → Working codebase + tests + docs
Phase 3: Validation & Security     → Scan results + test evidence
Phase 4: Ready to deploy           → No production release (upgrade to full path first)
```

Both paths produce the same quality of technical work — same TDD, same security scanning, same documentation. The difference is that POC projects stop before production deployment. Organizational Production adds governance checkpoints (sponsor approval, IT Security review, ITSM tracking) throughout.

### Upgrade Paths

All upgrade paths preserve existing technical work:

| From | To | Command |
|---|---|---|
| Private POC (personal/light) | Sponsored POC (org/light) | `scripts/upgrade-project.sh --to-sponsored-poc` |
| Private POC (personal/light) | Production (org/standard+) | `scripts/upgrade-project.sh --to-production` |
| Sponsored POC (org/light) | Production (org/standard+) | `scripts/upgrade-project.sh --to-production` |
| Any track | Higher track | `scripts/upgrade-project.sh --track standard` |
| Personal | Organizational | `scripts/upgrade-project.sh --deployment organizational` |

Upgrades add requirements (governance, tooling, validation) — they never remove work. The tool matrix resolver automatically surfaces new tools needed for the higher track.

### Testing & Bug Tracking

The Build Loop includes a configurable test-fix-verify cycle:

1. **Build N features** (interval configurable — default: every 2 features)
2. **UAT testing session** — parallel AI agents (automated, exploratory, cross-platform) test alongside the human developer
3. **Bug triage** — severity classification (SEV-1 through SEV-4), disposition assignment (Fix Now / Defer / Won't Fix / Post-MVP)
4. **Remediation** — agent fixes bugs test-first, re-tests until gate passes
5. **Proceed** — only when all tests pass and all Fix Now bugs are resolved

Mechanical enforcement via `scripts/test-gate.sh` prevents skipping test sessions and blocks Phase 2→3 transition with unresolved SEV-1/2 bugs. Deferred bugs must be resolved or their features removed before validation begins.

Bug tracking is tool-agnostic — configure your preferred tracker (GitHub Issues, Linear, Jira, BUGS.md) in the Intake.

Each phase produces artifacts that gate entry into the next phase. The AI executes within constraints. The human validates at decision gates.

### The Workflow

1. **Fill out the Intake** — run `bash scripts/intake-wizard.sh` for a guided walkthrough, or open `PROJECT_INTAKE.md` directly
2. **Start Claude Code** — point it at the Intake and Builder's Guide
3. **The agent executes each phase** — asking you only for clarifying questions and approval at decision gates
4. **You review at decision gates** — architecture selection, test assertions, security scan results, go-live readiness
5. **Phase 3 validates everything** — security scans, integration tests, accessibility audit, threat model verification. Zero critical findings before proceeding.
6. **Phase 4 releases** (full path) or **confirms ready to deploy** (POC path)

The [User Guide](docs/user-guide.md) walks through each step in detail — what you do, what the agent does, what external approvals are needed (organizational), and what output to expect at each phase.

### Modular Architecture

The framework is built on two independent extensibility axes: **platforms** and **languages**.

**Platform modules** (`docs/platform-modules/`) are documentation — architecture patterns, tooling, testing strategies, and distribution guidance for a specific platform type. The Builder's Guide references them through callout markers (`⟁ PLATFORM MODULE`) at defined integration points. The core guide tells you *when* to do something; the module tells you *how* for your platform.

**Pipeline modules** (`templates/pipelines/`) are executable CI/CD configuration. They split into two dimensions:
- `ci/` — one template per **language** (test, lint, SAST, audit). Copied verbatim.
- `release/` — one template per **platform** (build, sign, package, deploy). Language-specific build commands are injected via placeholder substitution.

This separation means adding support for a new platform requires five components: a platform module (architecture guidance), an evaluation module (reviewer criteria), a release pipeline template (CI/CD), intake suggestions (optional but recommended), and CI template marker updates (language availability). Adding a new language requires one file: a CI template. Nothing in the Builder's Guide, existing modules, or existing templates changes. The web, desktop, mobile, and MCP server modules were each built this way — added independently without modifying the core framework or each other.

**Extensibility example:** To add "Azure Microservices" as a platform, write `docs/platform-modules/azure-microservices.md` (architecture guidance), `evaluation-prompts/Projects/modules/azure-microservices.md` (six-reviewer evaluation criteria), `templates/pipelines/release/azure-microservices.yml` (with `__PLACEHOLDER__` tokens for language injection), and optionally `templates/intake-suggestions/azure-microservices.json` (context-aware suggestions). Then update the `platforms=` marker on line 1 of each relevant CI template in `templates/pipelines/ci/` to include the new platform name. The init script auto-discovers available platforms from the `docs/platform-modules/` and `templates/pipelines/release/` directories and auto-discovers available languages from `templates/pipelines/ci/`. No code changes to the init script are needed — new platforms and languages appear as options automatically. See the [Extending Platforms Guide](docs/extending-platforms.md) for the full process.

---

## Platform Support

### Supported Platforms

| Platform | Module | Status |
|---|---|---|
| **Web** (SPA, full-stack, API) | `web.md` | v1.0 — Complete |
| **Desktop** (Windows, macOS, Linux) | `desktop.md` | v1.0 — Complete |
| **Mobile** (iOS, Android) | `mobile.md` | v1.0 — Complete |
| **MCP Server** (Model Context Protocol) | `mcp_server.md` | v1.0 — Complete |

Projects on unsupported platforms can select "other" during init. The Builder's Guide works standalone — you just won't have platform-specific architecture and distribution guidance.

New platform modules can be added without modifying the core framework. See the [Extending Platforms Guide](docs/extending-platforms.md) for the complete step-by-step process — it covers all five components (platform module, evaluation module, release pipeline, intake suggestions, CI template markers) and includes a validation checklist.

---

## Language Support (Current)

The init script auto-discovers available languages from `templates/pipelines/ci/` and generates language-appropriate CI pipelines, `.gitignore` entries, and runtime validation. New languages can be added by dropping a CI template in that directory — no init.sh changes needed.

| Language | CI: Build/Test | CI: Lint | CI: Dependency Audit | CI: License Check |
|---|---|---|---|---|
| **TypeScript** | `npm run build` / `npm test` | `npm run lint` | `npm audit` | `license-checker` |
| **Python** | `pip install` / `pytest` | `ruff check` | `pip-audit` | `pip-licenses` |
| **Rust** | `cargo build` / `cargo test` | `cargo clippy`, `cargo fmt` | `cargo audit` | `cargo license` |
| **C#** | `dotnet build` / `dotnet test` | (built into build) | `dotnet list package --vulnerable` | `dotnet-project-licenses` |
| **Kotlin** | `./gradlew build` / `./gradlew test` | `detekt` (plugin) | `dependencyCheckAnalyze` (plugin) | `checkLicense` (plugin) |
| **Java** | `./gradlew build` / `./gradlew test` | `detekt` (plugin) | `dependencyCheckAnalyze` (plugin) | `checkLicense` (plugin) |
| **Go** | `go build` / `go test -race` | `golangci-lint` | `govulncheck` | `go-licenses` |
| **Dart** (Flutter) | `flutter pub get` / `flutter test` | `flutter analyze` | `osv-scanner` (GitHub Action) | `dart_license_checker` |
| **Swift** (iOS native) | `swift build` / `swift test` | SwiftLint | `osv-scanner` (Package.resolved) | `swift-license` |
| **Other** | TODO skeleton | TODO | TODO | TODO |

All CI templates include Semgrep SAST scanning. Languages that require external tools (Rust, Python, Dart) install them explicitly in the pipeline. Kotlin and Java templates include Gradle plugin setup instructions for tools that require project configuration.

The release pipeline is driven by your **platform** selection, not language — the init script injects your language's build commands into the platform template via placeholder substitution.

---

## Project Tracks

| Track | When | What Changes |
|---|---|---|
| **Light** | Internal tools, personal utilities, <10 users | Skip market audit. Abbreviated Phase 3. Basic Phase 4. |
| **Standard** | External users, moderate complexity, <$10K/month | All phases. Lightweight market validation. |
| **Full** | Enterprise buyers, sensitive data, >$10K/month | All phases at max depth. Customer interviews. Pen testing mandatory. |

Tracks control scope depth. For organizational deployments, POC modes (Sponsored or Private) control governance requirements independently — a Sponsored POC can be any track. See [The Process](#the-process) above.

---

## For CIOs and Enterprise Evaluation

The [Executive Review](docs/executive-review.md) is designed to be evaluated independently — including by AI models. The [Enterprise Governance Framework](docs/governance-framework.md) provides the approval authorities, compliance screening, risk management, and portfolio governance required for organizational adoption.

Evaluation prompts are in `evaluation-prompts/`:
- **Framework reviews** (`evaluation-prompts/Framework/`) — 6 independent adversarial reviews of the framework itself: Senior Engineer, CIO, SVP IT Security, Corporate Legal, Technical User, and Red Team. Run after framework updates.
- **Project reviews** (`evaluation-prompts/Projects/`) — 6 independent adversarial reviews of any project built with the framework: same 6 perspectives, with domain-specific modules for web, desktop, mobile, MCP server, API, and framework project types. Run during Phase 3 validation.

---

## Methodology vs. Tooling: What's Portable

The Solo Orchestrator Framework has two distinct layers. Understanding the boundary matters for evaluating vendor risk, planning migrations, and assessing long-term viability.

### The Methodology Layer (Agent-Agnostic, Durable)

These elements work with any sufficiently capable AI coding agent and do not depend on Claude Code:

- **The process:** Five-phase, gate-controlled development (Discovery → Architecture → Construction → Validation → Release)
- **Quality mandates:** Test-driven development, per-feature security audits, threat modeling, documentation requirements
- **Governance controls:** Approval authorities, compliance screening, backup maintainer model, portfolio management, escalation paths, POC modes (Sponsored/Private) for pre-approval validation
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

## What This Is Not (Today)

The following are outside the current POC scope. The framework's modular architecture can be extended to cover each of these — they are scope boundaries, not architectural limitations.

- **Compliance-regulated systems (SOC 2, HIPAA, PCI-DSS, FedRAMP)** — The governance framework already provides role-based approval gate separation (independent approvers at every organizational phase gate), append-only audit evidence, and anti-self-approval controls. What's missing is compliance-specific modules that map these controls to specific regulatory requirements and a per-change code review enforcement step. This is a content and configuration gap, not a structural redesign. A compliance module is planned that will formalize the mapping between the framework's existing governance controls and specific regulatory standards, add per-change code review enforcement, and provide compliance-specific evidence collection templates.
- **High-availability systems (99.99%+ SLA)** — The framework can build software architectured for HA and produces Phase 4 handoff documentation for operations teams. Application maintenance can continue under the Solo Orchestrator methodology by any qualified person. SLA guarantees are an infrastructure operations responsibility separate from the development methodology.
- **Large-scale distributed systems (microservices, multi-region)** — New platform modules could cover distributed architecture patterns. The extensibility model supports it; the modules haven't been written.
- **Enterprise integration projects (SAP, Salesforce, ERP)** — Specialized domains with their own SDKs and deployment models. Could be addressed through dedicated platform modules and suggestion files.

Today, it's for the projects that sit in the backlog because they don't justify a team: internal tools, departmental applications, prototypes, MVPs, and utilities.

## Should You Use This Framework?

| Question | If Yes | If No |
|---|---|---|
| **Will your project have more than 3 features?** | Continue below | Use Claude Code with a well-written CLAUDE.md |
| **Will it handle user authentication or sensitive data?** | **Use the framework** (Standard or Full track) | Continue below |
| **Will other people use it?** | **Use the framework** (Standard or Light track) | Continue below |
| **Will you maintain it for more than 6 months?** | **Use the framework** (Light track) | Use Claude Code with a CLAUDE.md |

For enterprise/organizational use: always use the framework. The governance artifacts alone justify the overhead. If full approvals aren't available yet, use a POC mode (Sponsored or Private) to validate the framework first — all technical work carries forward when you upgrade to production.

**Minimum skills assumed:**
- Navigate a terminal (cd, ls, running commands)
- Basic Git operations (clone, commit, push, pull, branches)
- Read code well enough to identify obvious problems
- Understand what a test is and how pass/fail works
- Edit JSON and YAML files without breaking their syntax
- Install software from the command line (npm, pip, brew, apt, or equivalent)
- For web projects: understand HTTP status codes and request/response basics

## What This Provides Beyond a Plain Setup

| Capability | CLAUDE.md + Hooks + CI | Solo Orchestrator |
|---|---|---|
| Agent instructions | Single CLAUDE.md file | CLAUDE.md + Builder's Guide + Platform Module — comprehensive AI instruction set |
| Project planning | Ad hoc | Structured Intake Template + phase-gated discovery (Phases 0-1) |
| CI security scanning | Manual pipeline setup | 9 language-specific templates with Semgrep SAST, dependency audit, license checking |
| Release pipeline | Manual pipeline setup | 4 platform-specific templates (web, desktop, mobile, MCP server) |
| Platform guidance | None | Web, Desktop, Mobile, MCP Server modules with architecture patterns, tooling, testing, distribution |
| Enterprise governance | None | Full framework with approval authorities, compliance screening, portfolio governance, and POC modes for pre-approval validation |
| Project intake | Manual CLAUDE.md | Guided intake wizard (interactive script or AI-assisted) with context-aware suggestions per platform |
| Security scan guidance | Read the docs yourself | Plain-language interpretation guide for common Semgrep and Snyk findings |
| Session continuity | Manual context management | Session resume script generates prompt from project state |
| Evaluation tooling | None | 6 reviewer perspectives (senior engineer, CIO, security, legal, technical user, red team) composable against 7 project-type modules (web, desktop, mobile, MCP server, API, CLI, framework); `run-reviews.sh` orchestrates all six in one command |

The methodology, intake template, platform modules, and CI pipeline templates are the primary value. The framework packages operational knowledge that would otherwise need to be discovered project-by-project.

---

## Known Limitations

- **Enforcement has two mechanical layers but gaps remain.** The CI pipeline (SAST, dependency audit, license checking, tests) blocks merges on failure. The Development Guardrails for Claude Code pre-commit hooks (gitleaks, Semgrep) catch issues at commit time locally. Together these provide mechanical enforcement for security, testing, and code quality. However, phase gates, TDD ordering, scope control, and documentation updates currently rely on the AI agent following CLAUDE.md instructions and the human reviewing at decision gates. These are Tier 3 (guided) controls with no automated backstop yet.
- **Release pipelines require configuration.** CI pipelines work immediately on first push. Release pipelines are templates with TODOs for code signing, deployment secrets, and store credentials that must be configured before first release.
- **Docker is local only.** OWASP ZAP and Qdrant run as local Docker containers (via Colima or Docker Desktop on macOS, system Docker on Linux). Remote Docker hosts and network-accessible containers are not yet supported.
- **Linux package manager support covers apt, dnf, and pacman.** Alpine (apk) and other distributions require manual tool installation. The init script auto-detects brew (macOS), apt (Debian/Ubuntu), dnf (Fedora/RHEL), and pacman (Arch/Manjaro).
- **CI/CD templates are GitHub Actions only.** The framework provides pipeline templates for GitHub Actions. GitLab CI and Azure DevOps are supported as repository hosts, but pipeline templates must be translated manually.
- **Single language per init.** The init script generates CI for one primary language. Polyglot projects (e.g., TypeScript frontend + Python backend) require manual addition of CI steps for secondary languages.
- **Not yet validated through an organizational pilot.** The framework has been used by the author to build two cross-platform MVP applications (K-PDF, MeshScope), validating Phases 0-2. The pilot evaluation process (Executive Review, Section X) defines how to test it organizationally. Treat this as a methodology with demonstrated personal-project results, not yet organizationally proven.

---

## Current Status

This is the initial release of the Solo Orchestrator Framework. It has been used by the author to build two cross-platform MVP applications (K-PDF and MeshScope), validating the methodology through Phases 0-2 (Discovery, Architecture, Construction). It has not yet been validated through a formal organizational pilot. The framework's own pilot evaluation process (see Executive Review, Section X) defines how to test it organizationally. Feedback from real-world usage will drive future iterations.

---

## Document Versions

| Document | Role | Version | Date |
|---|---|---|---|
| **User Guide** | **Follow step-by-step** | v1.3 | 2026-04-10 |
| **Project Intake Template** | **Fill out (wizard helps)** | v1.0 | 2026-04-02 |
| **Platform Modules** (Web, Desktop, Mobile, MCP Server) | **Reference during build** | v1.0 | 2026-04-02 / 2026-04-10 |
| Builder's Guide | Reference — advanced methodology detail | v1.1 | 2026-04-10 |
| Security Scan Guide | Reference — when you get scan findings | v1.0 | 2026-04-02 |
| CLI Setup Addendum | Reference — Claude Code configuration | v1.0 | 2026-04-02 |
| Enterprise Governance Framework | Organizational deployments only | v1.0 | 2026-04-02 |
| Executive Review | CIO/CISO evaluation only | v1.1 | 2026-04-10 |
| Evaluation Prompts (Framework) | Adversarial review — after framework updates | v1.0 | 2026-04-02 |
| Evaluation Prompts (Projects) | Adversarial review — Phase 3 validation | v1.0 | 2026-04-02 |
| Extending Platforms Guide | Contributor — adding new platforms | v1.0 | 2026-04-10 |

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

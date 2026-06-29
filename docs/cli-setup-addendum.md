# Solo Orchestrator — Claude Code CLI Setup Addendum

## Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-005-CLI |
| **Version** | 1.0 |
| **Classification** | Technical Configuration Guide |
| **Date** | 2026-04-02 |
| **Audience** | Solo Orchestrator using Claude Code CLI |
| **Companion Documents** | SOI-002-BUILD v1.0 (Builder's Guide), SOI-004-INTAKE v1.0 (Project Intake Template) |

## Scope

This addendum is specific to Claude Code. The Builder's Guide methodology works with any AI coding agent, but the integrations documented here (Superpowers, Auto Mode, Context7 MCP, Qdrant MCP, CLAUDE.md auto-loading) are Claude Code features. If using a different AI coding agent, adapt the concepts (persistent context, semantic memory, TDD enforcement) to your agent's capabilities. The core phases and decision gates do not depend on this addendum.

---

## Purpose

The Builder's Guide (SOI-002-BUILD) defines the methodology. This addendum configures the Claude Code CLI to execute that methodology with maximum autonomy. It covers six capabilities that the Builder's Guide references or assumes but doesn't set up:

| Capability | What It Does | Why the Builder's Guide Needs It |
|---|---|---|
| **Superpowers** | Agentic skills framework providing TDD enforcement, subagent-driven development, systematic debugging, code review, and git worktree management | The Builder's Guide defines the Build Loop (test → implement → audit → document); Superpowers provides the execution engine that makes the agent enforce TDD, spawn focused subagents per task, and self-review before presenting to the Orchestrator |
| **Auto Mode** | Reduces permission interruptions so the agent can work through multi-step tasks without stopping | The Builder's Guide assumes the agent can execute Build Loop cycles without pausing for permission on every file write and command |
| **Development Guardrails for Claude Code** | Encourages coding standards, security scanning, and documentation through Git hooks and pre-commit checks | The Builder's Guide defines what should happen (TDD, security audits, documentation); the framework provides automated workflow guardrails that catch common drift |
| **Context7 MCP** | Provides the agent with up-to-date library documentation during architecture selection and construction | The Builder's Guide mentions Context7 in Phase 1 but doesn't fully configure it for CLI use |
| **Qdrant MCP** | Gives the agent persistent semantic memory across sessions — stores and retrieves project decisions, patterns, and context | The Builder's Guide's Context Health Check (every 3-4 features) relies on the agent maintaining awareness of prior decisions; Qdrant makes this durable across session boundaries |
| **CLAUDE.md** | Provides the agent with project-specific instructions loaded automatically at every session start | The Builder's Guide says "provide the Project Bible at session start" but doesn't specify the mechanism; CLAUDE.md is that mechanism |

**Complete this setup once per development machine.** Project-specific configuration (CLAUDE.md content, Qdrant collections) is created per-project during Phase 1.

---

## Quick Setup — All Recommended Enhancements

If you want to configure all optional enhancements at once, run these commands from your project directory. Each step is independent — skip any you do not need.

**1. Context7 MCP (one command, no prerequisites):**
```bash
claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
```

**2. Superpowers plugin (one command, no prerequisites — this is a slash command run inside Claude Code, not a shell command):**
```
/plugin install superpowers@claude-plugins-official
```

**3. Qdrant MCP (requires Docker):**
```bash
# Start Qdrant (runs in background)
docker run -d --name qdrant -p 6333:6333 -p 6334:6334 \
  -v qdrant_storage:/qdrant/storage \
  --restart unless-stopped \
  qdrant/qdrant:latest

# Add the MCP server
claude mcp add -s user \
  -e QDRANT_URL=http://localhost:6333 \
  -e COLLECTION_NAME=claude-memory \
  qdrant -- uvx --python 3.13 mcp-server-qdrant
```

**4. Replace CLAUDE.md with the enhanced template:**
After configuring any of the above, replace your project's `CLAUDE.md` with the enhanced template from [Section 6](#6-claudemd) below and fill in the project-specific sections.

For detailed explanations of each tool and how it integrates with the Builder's Guide, see the individual sections below.

---

## 1. Superpowers (Agentic Skills Framework)

### What It Is

Superpowers (github.com/obra/superpowers) is a composable skills framework for coding agents. It installs as a Claude Code plugin and provides a set of skills that activate automatically based on context — the agent doesn't need to be told to use them, they fire when relevant.

Core skills:

- **brainstorming** — Socratic design refinement before writing code. Asks clarifying questions, explores alternatives, presents design in digestible sections for validation.
- **writing-plans** — Breaks approved designs into granular tasks (2-5 minutes each) with exact file paths, complete code specifications, and verification steps.
- **subagent-driven-development** — Spawns a fresh subagent per task with a two-stage review: first spec compliance, then code quality. The main agent orchestrates and reviews rather than doing everything sequentially.
- **test-driven-development** — Enforces strict RED-GREEN-REFACTOR: write failing test, watch it fail, write minimal code to pass, commit. Deletes code written before tests exist.
- **systematic-debugging** — 4-phase root cause process including root-cause-tracing, defense-in-depth, and condition-based-waiting techniques.
- **requesting-code-review** / **receiving-code-review** — Structured review against the plan, with issues reported by severity. Critical issues block progress.
- **using-git-worktrees** — Creates isolated workspaces on new branches for parallel development. Verifies clean test baseline before work begins.
- **finishing-a-development-branch** — Verifies tests pass, presents merge/PR/keep/discard options, cleans up worktree.
- **verification-before-completion** — Ensures fixes actually work before declaring success.

### How It Applies to the Builder's Guide

Superpowers is the **Phase 2 execution engine.** The Solo Orchestrator framework defines what to build (Phase 0 Manifesto, Phase 1 Bible) and how to validate it (Phase 3). Superpowers provides the methodology for how the agent actually constructs features within Phase 2.

| Builder's Guide Phase 2 Step | Superpowers Skill | Interaction |
|---|---|---|
| **Build Loop: Write Tests First (2.2)** | `test-driven-development` | Superpowers strongly encourages RED-GREEN-REFACTOR as the default workflow. The agent writes the failing test, verifies it fails, then implements. This provides stricter TDD discipline than the base Builder's Guide's sequential approach, though it is a workflow aid — the Orchestrator's test assertion review remains the actual quality gate. |
| **Build Loop: Implement Feature (2.3)** | `subagent-driven-development` + `writing-plans` | Superpowers breaks each feature into micro-tasks and dispatches subagents per task, with two-stage review. This is faster and more rigorous than the single-agent sequential approach in the base Builder's Guide. |
| **Build Loop: Security & Quality Audit (2.4)** | `requesting-code-review` | Superpowers runs a structured review against the plan before presenting to the Orchestrator. The Orchestrator still reviews, but the agent has already caught spec-compliance and code-quality issues. |
| **Context Health Check** | `verification-before-completion` | Superpowers' verification skill ensures the agent proves things work rather than just claiming they do. |
| **Debugging** | `systematic-debugging` | When something breaks during construction, the agent follows a structured 4-phase root cause process instead of randomly trying fixes. |
| **Not in base Builder's Guide** | `using-git-worktrees` | Superpowers adds parallel development on isolated branches — features are built in worktrees and merged when complete. This is an upgrade over the base Builder's Guide's linear approach. |

### Important: Managing Overlap with Phase 0/1

Superpowers' **brainstorming** skill activates automatically when it detects the agent is starting something new. If Phase 0 and Phase 1 are already complete (Product Manifesto and Project Bible exist), the brainstorming skill will try to re-discover requirements that are already defined. **The CLAUDE.md must instruct the agent to constrain brainstorming:**

- Use Superpowers' brainstorming for **implementation-level design decisions within a feature** (e.g., "how should we structure this component?" or "what's the best data structure for this?").
- Do **not** use brainstorming for **product-level decisions** — those are governed by the Product Manifesto.
- Do **not** use brainstorming to reconsider **architecture decisions** — those are governed by the Project Bible.
- When Superpowers' `writing-plans` skill generates a plan for a feature, the plan must align with the MVP Cutline. If the plan includes tasks for features not in the Cutline, reject them.

This constraint is included in the CLAUDE.md template in Section 6.

### Setup

**Install via the Claude Code plugin marketplace:**
```
/plugin install superpowers@claude-plugins-official
```

**Or via the community marketplace:**
```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

**Verify installation:** Start a new session and ask the agent to help plan a feature. It should automatically invoke the brainstorming skill rather than jumping straight to code.

**Update:**
```
/plugin update superpowers
```

---

## 2. Auto Mode (Permission Management)

### What It Is

Claude Code's permission system controls what the agent can do without asking: file writes, command execution, network operations. By default, every potentially impactful action triggers a permission prompt. For short tasks, this is fine. For the Solo Orchestrator Build Loop — where the agent cycles through test writing, implementation, security scanning, documentation, and schema migrations per feature — the constant interruptions break flow and defeat autonomy.

Auto Mode (launched March 24, 2026) is a classifier-based permission system that evaluates each action before execution. Routine, low-risk actions (file writes within the project, test execution, linting) proceed automatically. High-risk actions (mass deletions, operations outside the project directory, production deployments, force-pushes) are blocked or prompt for approval.

This is the recommended approach over `--dangerously-skip-permissions`, which disables all safety checks entirely and is intended only for fully isolated CI/CD environments.

### How It Applies to the Builder's Guide

Auto Mode maps directly to the Builder's Guide's autonomous execution model:

- **Phase 2 Build Loop:** The agent writes tests, implements features, runs Semgrep, updates documentation, and commits — all within a single feature cycle. Auto Mode lets this run without interruption while still catching genuinely dangerous operations.
- **Phase 3 Validation:** Security scans, Playwright tests, Lighthouse audits, and DAST scanning involve dozens of command executions. Auto Mode auto-approves the scan commands while blocking anything that looks like it could affect systems outside the project.
- **Decision Gates:** The Builder's Guide's phase gates (architecture approval, test assertion review, go-live) are Orchestrator decisions, not permission prompts. Auto Mode doesn't interfere with these — they're conversational checkpoints, not tool-call approvals.

### Setup

**Start a session in Auto Mode:**
```bash
claude --permission-mode auto
```

**Or switch during a session:** Press `Shift+Tab` to cycle through permission modes until you reach Auto Mode.

**To make Auto Mode the default** (add to your shell profile):
```bash
alias claude="claude --permission-mode auto"
```

**Note on availability:** As of late March 2026, Auto Mode is a research preview available to Claude Teams users, with Enterprise and API rollout in progress. Check current availability for your subscription tier. If Auto Mode is not available on your plan, configure granular permissions in your `settings.json` to allow common development operations:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run *)",
      "Bash(npx *)",
      "Bash(git *)",
      "Bash(semgrep *)",
      "Bash(gitleaks *)",
      "Bash(snyk *)",
      "Bash(lighthouse *)",
      "Bash(mkdir *)",
      "Bash(cat *)",
      "Bash(ls *)",
      "Read",
      "Write",
      "Edit"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(sudo *)",
      "Bash(curl * | bash)",
      "Bash(curl * | sh)"
    ]
  }
}
```

Place this in `.claude/settings.json` (project-level, shared with team) or `.claude/settings.local.json` (project-level, personal, gitignored).

---

## 3. Development Guardrails for Claude Code (Compliance Enforcement)

### What It Is

The Development Guardrails for Claude Code (github.com/kraulerson/claude-dev-framework) is a hook-based system that provides automated workflow guardrails for coding standards, security scanning, and documentation requirements through Git hooks. It uses a layered defense model within its hook system — multiple hook-based checks (pre-commit, pre-push, post-merge) cover different failure modes, so no single check needs to catch everything. The combination of checks across Git hook stages provides broader coverage than any individual hook.

The framework uses:
- **Profiles** — Configuration sets that define rules for different project types (`_base.yml`, `desktop-app.yml`, `mobile-app.yml`, `web-api.yml`, `web-app.yml`), inheriting from `_base.yml` with shared standards.
- **Hooks** — Git-triggered actions (pre-commit, pre-push, post-merge) that run automated checks before code reaches the repository.
- **Rules** — Specific enforcement policies (e.g., "no direct schema modifications without migration files," "no dependencies without license check," "no commit without test coverage").

### How CDF and Solo Orchestrator Layer

CDF and Solo Orchestrator are deliberately split across two layers; both are installed by `init.sh`, but they enforce different things and a Solo project's working set of guardrails is the sum of both:

| Layer | What it owns | Where it runs | Where the rules live |
| - | - | - | - |
| **CDF** | Coding-standards enforcement: secret detection (gitleaks), SAST quick scan (Semgrep), license check, lockfile pinning, test-co-location heuristic, schema-migration check. | `.git/hooks/` (pre-commit, pre-push, post-merge) and `.claude/settings.json` (PreToolUse hooks the agent triggers). Profile-driven (`desktop-app.yml`, `mobile-app.yml`, `web-api.yml`, `web-app.yml`). | `~/.claude-dev-framework/` (global, shared install). |
| **Solo Orchestrator** | Process enforcement: Build Loop step ordering, Phase 2/3/4 checklists, phase-gate consistency. Plus the enforcement-level layer added in BL-030: a project-wide `enforcement_level` (`strict` / `light` / `no`) that gates **user-terminal** commits via `.git/hooks/framework-gate.sh` and writes every framework-bypass event to `.claude/bypass-audit.json`. | `scripts/pre-commit-gate.sh` (PreToolUse on Claude-issued `git commit` / `gh pr create`), `scripts/framework-gate.sh` (the strict-mode user-terminal gate), `scripts/detect-out-of-band-commits.sh` (SessionStart — catches `--no-verify` post-hoc), `scripts/hooks/bypass-detector.sh` (PostToolUse + Stop). | In-project (`scripts/`, `.claude/`). |

CDF answers "does this code meet the project's standards?" Solo answers "did this commit follow the process, and if it bypassed enforcement, is that recorded?" The two compose: a Solo-strict project on the `web-api` CDF profile gets gitleaks + Semgrep + license-check from CDF plus the Build Loop / Phase gate + bypass-audit from Solo, both at commit time. See `docs/user-guide.md` ("What Is Enforced vs. What Is Guided") for the canonical operator-facing level matrix and `docs/builders-guide.md` ("Enforcement Model") for how Claude-issued vs user-terminal commits are gated.

### How It Applies to the Builder's Guide

The Builder's Guide defines quality controls at each phase. The Development Guardrails for Claude Code automates checks for them:

| Builder's Guide Requirement | Development Guardrails Enforcement |
|---|---|
| TDD — tests before implementation (Phase 2, Step 2.2) | Pre-commit hook validates test file exists for changed source files |
| Secret detection (Phase 2, Step 2.4) | Pre-commit hook runs gitleaks on staged files; CI pipeline runs gitleaks-action as backstop |
| SAST quick scan (Phase 2, Step 2.4) | Pre-commit hook runs Semgrep on staged files; CI pipeline runs full Semgrep scan |
| License compliance (Phase 2, CI/CD) | Pre-push hook runs license-checker |
| Documentation updates (Phase 2, Step 2.5) | Hook validates CHANGELOG.md updated when source files change |
| Exact dependency pinning (Phase 2, Initialization) | Rule rejects lockfile changes with non-exact versions |
| No direct schema modification (Phase 2, Step 2.6) | Rule rejects changes to schema files outside migration tool |

The framework catches violations the agent might introduce — particularly during long construction sessions where context drift is a risk. The agent writes the code; the framework verifies the code meets the standards before it enters the repository.

### Setup

**`init.sh` installs CDF automatically.** Running `bash init.sh` from a new project directory clones CDF to `~/.claude-dev-framework` (a global, shared install — not per-project) and then runs CDF's own initializer from your project root. Per-project profile selection happens inside that CDF init flow.

**Solo enforcement level is selected at the same time.** `init.sh` accepts `--enforcement-level <no|light|strict>` (default `strict`; `--confirm-pitfalls` is required to go below strict). The chosen level determines whether `.git/hooks/framework-gate.sh` is installed: strict installs it (every user-terminal commit goes through the Build Loop / Phase classifier and lands a `terminal_commit_blocked` or `terminal_commit_passed` row in `.claude/bypass-audit.json`); light and no skip the install. The SessionStart out-of-band detector runs on strict AND light (any `--no-verify` commit is captured post-hoc); on `no`, it is a no-op. To change the level on an existing project, use `scripts/reconfigure-project.sh --enforcement-level <new-level> [--confirm-pitfalls]`. For pre-BL-030 projects, `scripts/upgrade-project.sh --backfill-only` migrates the manifest in place (defaults to strict, forced strict for organizational Sponsored POC / Production).

**Manual fallback** (only needed if you skipped Solo's `init.sh` and want CDF in isolation):

```bash
# Clone CDF globally (matches the layout init.sh expects)
git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework

# Run CDF init from your project root
cd /path/to/your/project
bash ~/.claude-dev-framework/scripts/init.sh
```

CDF's init prompts for the project profile (web-api, web-app, mobile-app, desktop-app) and wires the appropriate hooks into your project's `.claude/settings.json` and `.git/hooks/`. It does NOT clone its templates into `.claude/framework/` — that earlier per-project clone pattern is obsolete.

**Verify the integration:**
```bash
# Stage a test file and commit — the hooks should fire
git add .
git commit -m "test: verify framework hooks"
```

**Note:** If the project type doesn't match an existing profile, the framework may need a new profile only for genuinely outside types (libraries, CLI tools — CDF retired its earlier `cli-tool.yml` profile). See the framework's documentation for profile creation guidance.

---

## 4. Context7 MCP (Live Library Documentation)

### What It Is

Context7 is an MCP (Model Context Protocol) server that provides Claude Code with up-to-date documentation for libraries and frameworks at query time. Instead of relying on training data (which may be months or years stale), the agent retrieves current documentation when it needs to make implementation decisions.

This is particularly valuable during:
- **Phase 1 Architecture Selection** — verifying that a framework's current API matches what the agent "remembers" from training data.
- **Phase 2 Construction** — using correct, current syntax for dependencies rather than deprecated patterns.
- **Phase 3 Validation** — confirming that security tooling commands and options are current.

### How It Applies to the Builder's Guide

The Builder's Guide mentions Context7 as optional in Phase 1 with a one-liner (`npx ctx7 setup --claude`). For CLI use, the proper configuration is:

### Setup

**Add Context7 as a user-scoped MCP server (available across all projects):**
```bash
claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
```

No API key required. Works immediately.

**Verify it's active:**
```bash
claude /mcp
```
You should see `context7` listed as a connected server.

**How the agent uses it:** When the agent needs documentation for a library (e.g., "What's the current Prisma migration API?"), it can query Context7 rather than relying on training data. The CLAUDE.md template (Section 6 below) includes instructions for the agent to use Context7 when making implementation decisions involving specific library APIs.

---

## 5. Qdrant MCP (Persistent Semantic Memory)

### What It Is

Qdrant is a vector search engine that, when connected as an MCP server, gives Claude Code persistent semantic memory across sessions. The agent can store project decisions, architecture rationale, implementation patterns, and debugging context — and retrieve them in future sessions using natural language queries.

This solves a specific Solo Orchestrator problem: the Builder's Guide acknowledges that the agent loses context between sessions and recommends providing the Project Bible at session start. For small projects, the Bible fits in context. For larger projects or long-running builds, the Bible grows too large to load entirely, and the agent needs to selectively retrieve relevant context. Qdrant provides that selective retrieval.

### How It Applies to the Builder's Guide

| Builder's Guide Concern | Qdrant's Role |
|---|---|
| **Context Health Check (every 3-4 features)** | The agent stores a summary of each feature's decisions and implementation details. When the health check reveals drift, the agent retrieves the relevant prior decisions instead of relying on the Bible alone. |
| **Phase 2 Architecture Decision Records** | Architecture decisions are stored semantically. When the agent encounters a design choice in a later feature, it retrieves relevant prior ADRs automatically. |
| **Session continuity** | At session end, the agent stores its current state (features built, features remaining, known issues). At the next session start, it retrieves this state instead of re-reading the entire project. |
| **Phase 3 remediation** | When debugging, the agent retrieves similar past issues and their resolutions from memory. |

### Setup

**Prerequisites:** Docker installed and running.

**1. Start a Qdrant instance:**
```bash
docker run -d \
  --name qdrant \
  -p 6333:6333 -p 6334:6334 \
  -v qdrant_storage:/qdrant/storage \
  --restart unless-stopped \
  qdrant/qdrant:latest
```

**2. Add the Qdrant MCP server to Claude Code (user-scoped):**
```bash
claude mcp add -s user \
  -e QDRANT_URL=http://localhost:6333 \
  -e COLLECTION_NAME=claude-memory \
  qdrant -- uvx --python 3.13 mcp-server-qdrant
```

If `uvx` is not installed:
```bash
# macOS
brew install uv
# or pip
pip install uv
```

**3. Verify:**
```bash
claude /mcp
```
You should see `qdrant` listed as a connected server with `qdrant-store` and `qdrant-find` tools available.

**4. Per-project collections (optional but recommended):**

For multiple Solo Orchestrator projects, use project-specific collection names to keep memories isolated:

```bash
# In the project's .claude/settings.local.json
{
  "mcpServers": {
    "qdrant": {
      "command": "uvx",
      "args": [
        "mcp-server-qdrant",
        "--qdrant-url", "http://localhost:6333",
        "--collection-name", "project-name-here"
      ]
    }
  }
}
```

### What the Agent Should Store

The CLAUDE.md template (Section 6) instructs the agent on when to use Qdrant. Key storage triggers:

- **After each feature completion (Phase 2):** Store a summary of the feature, key implementation decisions, any non-obvious patterns used, and debugging insights.
- **After each Phase gate:** Store the phase transition context (what was approved, what concerns were raised, what changed from the plan).
- **When encountering and resolving a significant issue:** Store the problem description, root cause, and resolution for future reference.
- **At session end:** Store the current project state for the next session to retrieve.

### What the Agent Should Retrieve

- **At session start:** Retrieve the most recent project state summary.
- **Before starting a new feature:** Retrieve ADRs and implementation patterns related to the feature's domain.
- **When debugging:** Retrieve prior issues with similar symptoms.
- **During Context Health Checks:** Retrieve the list of features built and their implementation summaries to verify against the Bible.

---

## 6. CLAUDE.md (Project-Level Agent Instructions)

### What It Is

CLAUDE.md is a file that Claude Code automatically reads at the start of every session. It's the agent's persistent operating instructions — the equivalent of a briefing document that ensures the agent knows your project's architecture, conventions, constraints, and current state without you repeating them.

For the Solo Orchestrator workflow, CLAUDE.md is where the Project Bible's key constraints live in a form the agent consumes automatically. It evolves across phases as the project takes shape.

**Relationship to init-generated CLAUDE.md:** The init script generates a minimal starter CLAUDE.md that works for Phases 0-1 without optional enhancements. The template below is the full version with Superpowers integration, Context7 usage instructions, Qdrant memory triggers, and phase-evolving sections. **Replace the init-generated CLAUDE.md with this template when you configure your first optional enhancement** (typically before Phase 2). Copy the template, fill in the project-specific sections (project name, phase, track), and delete the placeholder comments.

### How It Applies to the Builder's Guide

The Builder's Guide says "provide the Project Bible at session start." CLAUDE.md is the mechanism. But instead of dumping the entire Bible into CLAUDE.md (which wastes context on information irrelevant to the current task), the CLAUDE.md contains:

- The agent's role and operating rules
- Pointers to the full documents (Intake, Bible, Builder's Guide) via `@` includes
- Key architectural constraints that affect every decision
- Tool usage instructions (when to use Context7, Qdrant, framework hooks)
- Current project state (updated at each phase transition)
- "Never do this" rules that prevent common AI mistakes

### CLAUDE.md Template

The following template is placed at the project root. **It evolves — update it at each phase transition.** Sections marked `[PHASE X+]` are added when that phase completes.

```markdown
# CLAUDE.md — Solo Orchestrator Project Instructions

## Role
You are the AI execution layer for a Solo Orchestrator project.
The Orchestrator defines intent, constraints, and validation.
You provide architecture, code, and documentation within the
constraints set by the Project Intake and Project Bible.

## Process Reference
@./PROJECT_INTAKE.md
@./PROJECT_BIBLE.md
@./PRODUCT_MANIFESTO.md
@./CONTRIBUTING.md

Follow the Solo Orchestrator Builder's Guide (SOI-002-BUILD v1.0)
phase-by-phase process. Work autonomously between decision gates.
At each decision gate, present your recommendation and wait for
Orchestrator approval. Between gates, only stop if you encounter
a conflict, ambiguity, or blocker you cannot resolve from the
Intake, Bible, or prior context.

## Current State
- **Project:** [PROJECT NAME]
- **Phase:** [0 / 1 / 2 / 3 / 4]
- **Track:** [Light / Standard / Full]
- **Features built:** [list or "none yet"]
- **Features remaining:** [list or "see MVP Cutline"]
- **Known issues:** [list or "none"]
- **Last session summary:** [brief description of where we left off]

Update this section at the end of every session.

## Tool Usage

### Superpowers (Agentic Skills Framework)
Superpowers skills activate automatically. Follow their workflows
when they trigger, with these constraints:

**Brainstorming skill:** Use ONLY for implementation-level design
decisions within a feature (component structure, data structures,
algorithm selection). Do NOT use brainstorming to reconsider
product requirements (governed by Product Manifesto) or
architecture decisions (governed by Project Bible). If the
brainstorming skill suggests features not in the MVP Cutline,
reject them.

**Writing-plans skill:** Plans must align with the MVP Cutline.
If a generated plan includes tasks for features outside the
Cutline, remove those tasks before executing.

**Subagent-driven-development:** Use for Phase 2 feature
construction. Each subagent task must pass both review stages
(spec compliance, then code quality) before merging.

**Test-driven-development:** This skill enforces RED-GREEN-REFACTOR.
Do not write implementation code before a failing test exists.
Do not skip the "verify it fails" step.

**Git worktrees:** Create a worktree for each feature. Verify
clean test baseline before starting work. Use the
finishing-a-development-branch skill to merge when complete.

### Context7 (Library Documentation)
When making implementation decisions that depend on a specific
library's API, query Context7 for current documentation before
writing code. Do not rely on training data for version-specific
API details. Priority use cases:
- Framework API syntax (e.g., Prisma migrations, Supabase RLS)
- Security tooling command options (Semgrep rules, Snyk flags)
- Deployment platform configuration (Vercel, Railway settings)

### Qdrant (Semantic Memory)
Store and retrieve project context using the Qdrant MCP tools.

**Store (qdrant-store) after:**
- Completing each feature: summary, key decisions, patterns used
- Resolving a significant bug: problem, root cause, fix
- Each phase gate transition: what was approved, what changed
- End of each session: current state summary for next session

**Retrieve (qdrant-find) before:**
- Starting a new session: "latest project state for [PROJECT NAME]"
- Starting a new feature: "architecture decisions related to [DOMAIN]"
- Debugging: "prior issues similar to [SYMPTOM]"
- Context Health Checks: "features completed for [PROJECT NAME]"

### Development Guardrails for Claude Code (Compliance Hooks)
Git hooks enforce standards automatically. Do not attempt to
bypass hooks. If a hook blocks a commit:
1. Read the hook's error message
2. Fix the violation
3. Re-attempt the commit
Never use --no-verify to skip hooks. On strict-mode projects
the SessionStart out-of-band detector records every --no-verify
commit to .claude/bypass-audit.json regardless of the hook
being bypassed — the block is bypassable, the audit is not.

## Architecture Constraints
[PHASE 1+ — Add after architecture selection]
- **Stack:** [e.g., Next.js 15 + Supabase + Vercel]
- **Database:** [e.g., PostgreSQL via Supabase with RLS]
- **Auth:** [e.g., Supabase Auth with PKCE flow]
- **Logging:** [e.g., structured JSON, correlation IDs via X-Request-ID]
- **Migration tool:** [e.g., Prisma — NOTE: no automatic down migrations]

## Accessibility Requirements
[From Intake Section 9]
- [e.g., WCAG AA target, Lighthouse ≥90]
- [e.g., Never rely on color alone for meaning. Use shape,
  position, text labels, patterns, or icons.]
- [e.g., All interactive elements must have text labels or ARIA labels]

## Coding Standards
[PHASE 2+ — Add after CONTRIBUTING.md is generated]
@./CONTRIBUTING.md

## Never Do This
- Do not add features not in the MVP Cutline
- Do not modify the database schema directly — use migration tool
- Do not add dependencies without justification
- Do not use `--no-verify` to bypass Git hooks. On strict-mode projects
  the SessionStart out-of-band detector records every such commit to
  `.claude/bypass-audit.json` — the audit lands even when the hook is
  skipped. See `docs/audit-log-lifecycle.md`.
- Do not delete tests to make them pass
- Do not include production data, real PII, or credentials in
  prompts, comments, or test fixtures
- Do not use wildcard CORS on authenticated endpoints
- Do not commit .env files or secrets
- Do not generate CSP policies with unsafe-inline or unsafe-eval
  without explicit Orchestrator approval
- Do not proceed past a decision gate without Orchestrator approval

## Competency Gaps — Extra Validation Required
[From Intake Section 6.2 — domains marked "Partially" or "No"]
- [e.g., Security: always run Semgrep after security-related changes]
- [e.g., Accessibility: always run Lighthouse after UI changes]
- [e.g., Database: always run EXPLAIN on new queries]
```

### When to Update CLAUDE.md

| Trigger | What to Update |
|---|---|
| **Phase 0 complete** | Add project name, track, features from MVP Cutline |
| **Phase 1 complete** | Add Architecture Constraints, Accessibility Requirements, Competency Gaps. Add `@` includes for Project Bible and CONTRIBUTING.md |
| **Each Phase 2 feature complete** | Update "Features built" and "Features remaining" in Current State |
| **End of every session** | Update "Last session summary" and "Known issues" in Current State. Store session state in Qdrant. |
| **Phase 3 complete** | Add any new "Never Do This" rules discovered during validation |
| **Phase 4 deployment** | Add production URLs, monitoring endpoints, maintenance schedule |

### CLAUDE.md Anti-Patterns

Keep it focused. Based on current best practices:

- **Don't stuff everything in.** Every instruction competes for the agent's attention. Include only what would cause mistakes if missing. If it's in the CONTRIBUTING.md or Project Bible and `@`-included, don't duplicate it.
- **Don't include coding style guidelines.** That's the linter's and formatter's job. The Development Guardrails hooks enforce this mechanically. Spending context tokens on "use camelCase" is waste.
- **Don't include standard library knowledge.** The agent already knows how `Array.map()` works. Include only project-specific patterns and constraints.
- **Do include commands.** Exact build, test, lint, and deploy commands the agent should use. Don't make it guess.
- **Do include "never do this" rules.** These are the highest-signal content — they prevent mistakes the agent would otherwise make.
- **Do include current state.** The agent starts every session with no memory. CLAUDE.md is how it knows where the project is.

---

## 7. Complete Setup Checklist

Run this once per development machine:

- [ ] Claude Code installed and authenticated (`npx @anthropic-ai/claude-code`)
- [ ] Superpowers plugin installed (`/plugin install superpowers@claude-plugins-official`)
- [ ] Auto Mode configured (or granular permissions in settings.json if Auto Mode unavailable)
- [ ] Context7 MCP added (`claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp`)
- [ ] Qdrant running in Docker (`docker run -d --name qdrant -p 6333:6333 -p 6334:6334 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest`)
- [ ] Qdrant MCP added (`claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant`)
- [ ] Development Guardrails for Claude Code cloned and available for project setup
- [ ] Verify all MCP servers connected (`claude /mcp`)
- [ ] Verify Superpowers active (start a session, ask to plan a feature — brainstorming skill should trigger)

Run this once per project (during Phase 2 Project Initialization):

- [ ] Copy CLAUDE.md template to project root
- [ ] Customize CLAUDE.md with project identity, track, and Superpowers constraints
- [ ] Install Development Guardrails hooks for this project
- [ ] Configure project-specific Qdrant collection (if isolating from other projects)
- [ ] Add `@` includes to CLAUDE.md for project documents as they're created
- [ ] Verify hooks fire on test commit
- [ ] Verify Superpowers skills trigger during first feature build

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

---

## Git Host CLIs

Solo Orchestrator uses host-specific CLIs for repo creation and protection configuration. Install the one matching your chosen host during intake (required before running `init.sh`).

### gh (GitHub)

```bash
# macOS
brew install gh

# Ubuntu/Debian
type -p curl >/dev/null || sudo apt install curl -y
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh -y

# Other platforms: https://github.com/cli/cli#installation

# Authenticate
gh auth login
gh auth status
```

### glab (GitLab)

```bash
# macOS
brew install glab

# Linux/Windows: https://gitlab.com/gitlab-org/cli/-/releases

# Authenticate — gitlab.com
glab auth login

# Self-hosted
glab auth login --hostname gitlab.your-company.com
```

### Bitbucket (curl + API Token)

No first-party CLI. Uses `curl` plus an Atlassian API Token.

> **Why API Token, not App Password?** Atlassian is sunsetting Bitbucket
> Cloud App Passwords in 2026 (see
> <https://support.atlassian.com/bitbucket-cloud/docs/using-api-tokens/>).
> API tokens are the forward-compatible replacement. Both are sent as
> HTTP Basic authentication — for API tokens, the username is your
> Atlassian account **email** (NOT your Bitbucket username), and the
> password is the token itself. Bearer auth does NOT work; it is
> reserved for OAuth 2.0 access tokens (PR #90 verifier fix).

1. Create an API token at <https://id.atlassian.com/manage-profile/security/api-tokens>
   - Scope it to Bitbucket; pick an expiry up to 1 year.
2. Export credentials (all three are required — audit code-host-bitbucket-1):
   ```bash
   export BITBUCKET_API_TOKEN_EMAIL="you@example.com"    # Atlassian account email
   export BITBUCKET_API_TOKEN="your-api-token"
   export BITBUCKET_WORKSPACE="your-workspace-slug"
   ```
   `BITBUCKET_WORKSPACE` is the slug in your `bitbucket.org/<workspace>/` URL;
   for org accounts it is the team slug, which differs from any single user.
3. Add to your shell rc (`.bashrc` / `.zshrc`) for persistence. Ensure mode 600 if any secrets live in it.

**Legacy — App Password (sunset 2026):** still works today, will break
on Atlassian's enforcement date. Prefer the API token path above.

1. Generate an App Password at <https://bitbucket.org/account/settings/app-passwords/>
   - Required scopes: `repository:admin`, `project:admin`, `pullrequest:write`
2. Export the three legacy vars:
   ```bash
   export BITBUCKET_USER="your-bitbucket-username"
   export BITBUCKET_APP_PASSWORD="your-app-password"
   export BITBUCKET_WORKSPACE="your-workspace-slug"
   ```
   On personal accounts `BITBUCKET_USER` often (but not always) equals the workspace slug.

### Other hosts (Gitea, Codeberg, self-hosted)

No CLI required. During intake, choose `other`; provide the HTTPS clone URL when prompted by `init.sh` and attest that branch protection is configured per the required bar. No CI template is laid down for `other` — supply your own.

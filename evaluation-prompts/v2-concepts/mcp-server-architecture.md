# MCP Server Architecture — v2 Concept

## Problem Statement

Solo Orchestrator V1 is implemented as bash scripts + markdown files + Claude Code hooks. This architecture has structural limitations:

1. **Bash-only execution.** Scripts run only where bash is available. This excludes Claude Desktop entirely (no shell), and most IDE plugins are limited or sandboxed in ways that make bash invocation fragile. The Orchestrator is effectively locked into Claude Code CLI.
2. **Unstructured AI invitation.** The AI is told via CLAUDE.md and builders-guide to run scripts like `process-checklist.sh --start-feature`, but the scripts are presented as bash commands with shell args. The AI has no schema, no validation, no structured invitation. It can call them or not; it can pass malformed args; it has to parse stdout text to interpret results. Claude is meaningfully better at calling structured tools than bash scripts.
3. **No cross-session state coordination.** Scripts are single-invocation. Each `process-checklist.sh --check-commit-ready` is a fresh process reading state files. There's no long-running coordination layer; multi-actor coordination (which Team-Orchestrator needs) cannot be cleanly implemented this way.
4. **Bash as the long-term implementation language.** Bash works for scripts of moderate complexity but degrades fast as logic grows. Solo's `init.sh` is already 3000+ lines of bash; `process-checklist.sh` is 1100+ lines. Maintenance, refactoring, and testing all become harder. Real type systems, real testing frameworks, real libraries are unavailable.

The Solo Orchestrator methodology (Phase 0–4, Build Loop, governance attestations, drop-in extensibility) is solid. The implementation surface is the limit.

## Proposed Direction (V2)

Reimplement Solo Orchestrator's tool surface as an **MCP server** while preserving the existing hook layer for non-bypassable enforcement.

### Three-layer architecture

```
┌─────────────────────────────────────────────────────────┐
│ AI Client (CC CLI / Desktop / IDE)                      │
└─────────────────┬─────────────────────────┬─────────────┘
                  │                         │
                  │ MCP                     │ Hooks
                  │ (tools, resources)      │ (PreToolUse, etc.)
                  │                         │
        ┌─────────▼──────────┐    ┌────────▼──────────┐
        │  MCP Server        │    │  Hook scripts     │
        │  (Rust or Python)  │    │  (bash, current)  │
        │                    │    │                   │
        │  - start_feature   │    │  - pre-commit-gate│
        │  - complete_step   │    │  - config-guard   │
        │  - check_status    │    │  - session-checks │
        │  - request_approval│    │                   │
        └─────────┬──────────┘    └────────┬──────────┘
                  │                         │
                  └──────────┬──────────────┘
                             │
                  ┌──────────▼──────────┐
                  │  File-based state   │
                  │  (.claude/*.json)   │
                  │  + configs/         │
                  │  + docs/ (markdown) │
                  └─────────────────────┘
```

- **MCP server** exposes structured tools the AI invokes voluntarily (start_feature, complete_step, query status, request approval, etc.). Cross-client compatible.
- **Hook layer** remains as-is for non-bypassable enforcement (pre-commit-gate, config-guard, session checks).
- **File-based state** is the substrate. Both layers operate on the same JSON files.
- **Markdown docs** stay as AI context.

### Why MCP, not "rewrite scripts in Python/Rust"

The MCP protocol is what makes this cross-client. A Rust binary that runs as a CLI tool would still need bash hooks to invoke it; an MCP server is a long-running process that the AI client connects to directly via the protocol. Claude Code, Claude Desktop, Cursor, Continue, and future Anthropic-aware clients all speak MCP. None speak "your project's bash scripts."

### What MCP does NOT replace

- **Hooks.** PreToolUse / PostToolUse / Stop hooks are how non-bypassable enforcement happens. MCP tools are voluntarily called by the AI. Hooks fire whether the AI wants them to or not.
- **File-based state.** `.claude/process-state.json`, `phase-state.json`, audit logs — these stay as JSON files on disk. They're the substrate.
- **Markdown documentation.** CLAUDE.md, builders-guide, intake suggestions remain. The AI reads them as context.
- **Configuration files.** Drop-in extensions for platforms, methodologies, gates, etc. continue as files.

The MCP server adds a structured tool layer; it doesn't replace the existing architecture.

## Key Design Questions

1. **Implementation language.** Rust (single static binary, type safety, distribution simplicity) vs Python (faster iteration, official Anthropic SDK) vs TypeScript. Each has real trade-offs. For Solo's use case (single-developer projects, maintained alongside other work), iteration speed may matter more than distribution simplicity.

2. **Tool surface granularity.** Chunky workflow tools (one tool per common workflow: `complete_phase_2_gate`) vs many fine-grained tools (one per state transition: `mark_step_complete`, `verify_init`, etc.). Trade-off: fewer tools easier to use; more tools more composable.

3. **Tool surface per script.** Solo's scripts each have multiple subcommands (`--start-feature`, `--complete-step`, `--check-commit-ready`, etc.). Mapping: one MCP tool per subcommand? Or grouped by workflow? Or per script with parameters? Affects AI usability.

4. **Resources.** Should the server expose resources (file-like data the AI reads): `phase-state.json`, `process-state.json`, audit log? Or have the AI use bash to read them as it does today? Resources give better introspection.

5. **Prompts.** Should the server expose prompts (predefined templates): "Start a new feature," "Resume from where we left off," "Pre-commit checklist"? These complement tools.

6. **Hook compatibility.** The hooks need to operate on the same state the MCP server operates on. They're currently bash; can stay bash. But if the MCP server is doing atomic writes with locks and the hooks are doing naive `jq`-edit-and-rewrite, there's a coordination problem. Options: bash hooks call MCP server's state-mutation API; or hooks get rewritten alongside.

7. **Distribution and installation.** MCP server is a long-running process. Solo currently ships as `git clone`-and-run scripts. MCP-based Solo ships as `cargo install` or `pip install` plus per-client configuration ("point your AI at this server"). Different operational model. Per-project or per-user installation?

8. **Backward compatibility with V1 projects.** Existing Solo V1 projects have `.claude/*.json` state files. V2 must read those without forcing migration. State shape stays the same; only the tool surface changes.

## Why this is V2, not a refactor of V1

V1's implementation works. The methodology is proven. Refactoring V1 to MCP would be a major undertaking (5-7 weeks per the Team-Orchestrator estimate) for marginal benefit to existing V1 users (who are CC CLI natives). The right time to adopt MCP is at a major version boundary where the implementation rewrite is justified by other factors.

V2 candidates that pair naturally with MCP:
- This concept (cross-client + structured tools)
- Auto-discovery + Checker for extensibility (separate concept doc) — drops the hardcoded list pattern from init.sh, wizards, validators
- Post-MVP feature development cycle (separate concept doc) — pairs with MCP because the MCP tool surface for "ongoing development" is different from "linear Phase 0-4 progression"
- Principal Engineer Guardian (separate concept doc) — runs cleaner as an MCP-aware hook than as a separate bash hook

## Risks

1. **MCP protocol churn.** The protocol is stable but evolving. Over 18-24 months, expect minor breakages or feature additions. V2 commits to riding that wave.
2. **Distribution complexity.** Solo V1's "git clone and use" is part of its appeal. MCP-based V2 has a more involved setup. Worth designing the install story carefully (Homebrew tap? cargo install? per-client setup wizard?).
3. **Lock-in to MCP.** If the AI tooling ecosystem fragments away from MCP, Solo V2 is harder to port. As of 2026-04, MCP is widely adopted across Anthropic-compatible clients; this risk is low but real.
4. **Bash vs MCP-server feature parity at V2 launch.** V1 has 5 years (or however long) of bash logic. V2 must reproduce all of it. Time-cost real.
5. **Operational debugging.** When a bash script fails, the script is the artifact. When an MCP server fails, it's a daemon with logs, IPC, version mismatches. Higher operational complexity for users debugging their own setup.

## Reference

- Team-Orchestrator (sibling project, designed 2026-04-27) is being built MCP-native from V1 because its targeted customer (2-10 dev teams) needs cross-client compatibility from day one. Solo's existing V1 customers are CC CLI natives; the cross-client need is less urgent. Team-Orchestrator's V1 implementation will be the reference for whether MCP is the right architecture; Solo V2 can adopt the same patterns once Team-Orchestrator validates them in production.

## Trigger

Adopt for Solo V2 when at least one of these is true:
- A meaningful number of Solo V1 users want to run Solo against Claude Desktop or IDE plugins (validated by support requests / GitHub issues).
- Team-Orchestrator's MCP architecture validates as production-quality and the patterns are stable.
- The maintenance burden of bash logic (process-checklist.sh, init.sh, etc.) becomes painful enough that a rewrite is warranted regardless of MCP.

Until one of those triggers, V1's bash architecture continues to serve.

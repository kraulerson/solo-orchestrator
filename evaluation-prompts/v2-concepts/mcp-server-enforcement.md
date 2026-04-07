# MCP Server for Runtime Enforcement — v2 Concept

## Problem

The Solo Orchestrator's session-time enforcement relies on two mechanisms that both have reliability gaps:

1. **CLAUDE.md instructions** — text directives the agent is supposed to follow ("run `test-gate.sh --record-feature` after each feature"). The agent frequently ignores these. Every enforcement gap discovered so far (missed feature recording, no Qdrant usage, no update prompts) traces back to the agent not following text instructions.

2. **SessionStart/Stop hooks** — shell scripts that inject context into the agent's conversation. These work mechanically but the agent still has to *choose* to act on the injected context. The agent can bury it in a wall of output or present it as informational rather than actionable.

Neither mechanism gives the agent a direct, callable tool. MCP tools are different — they appear in the agent's tool list alongside Read, Write, Bash, etc. The agent is trained to use available tools, not just follow text instructions.

## Proposed Solution

A lightweight MCP server that exposes orchestrator enforcement as callable tools. The server maintains project state and can refuse operations when gates are blocked.

### What moves to the MCP server

Only session-time enforcement scripts — the parts the agent keeps ignoring as text instructions:

| Current Script | MCP Tool | Enforcement |
|---|---|---|
| `test-gate.sh --record-feature` | `orchestrator.record_feature(name)` | Records feature, returns gate status |
| `test-gate.sh --check-batch` | `orchestrator.check_test_gate()` | Returns blocked/clear with remaining count |
| `test-gate.sh --reset-counter` | `orchestrator.reset_test_counter()` | Resets after UAT session |
| `check-versions.sh` | `orchestrator.check_versions()` | Returns outdated tools with update commands |
| `check-phase-gate.sh` | `orchestrator.check_phase_gate()` | Returns phase gate status |
| Phase advancement | `orchestrator.advance_phase(approval)` | Advances phase only if gate conditions met |
| Project context | `orchestrator.get_project_status()` | Returns current phase, features, gate status |

### What stays as-is

- **init.sh** — interactive project scaffolding. MCP tools are request/response, not interactive wizards. Init remains a standalone script.
- **Documentation** — builders guide, platform modules, user guide. These are reference material, not runtime tools.
- **Templates** — CI pipelines, CLAUDE.md, tool matrix. Used at init time only.
- **check-updates.sh** — doc freshness comparison. Run manually, not session-time.
- **SessionStart hooks** — CDF's framework compliance hooks remain as hooks. The MCP server handles orchestrator-specific enforcement only.

### Architecture

```
┌─────────────────────────────────────────────┐
│                Claude Code                   │
│                                              │
│  Tools: Read, Write, Bash, ...              │
│         orchestrator.record_feature()        │
│         orchestrator.check_test_gate()       │
│         orchestrator.check_versions()        │
│         orchestrator.get_project_status()    │
│         ...                                  │
└──────────────┬───────────────────────────────┘
               │ MCP (stdio)
┌──────────────▼───────────────────────────────┐
│        Solo Orchestrator MCP Server          │
│                                              │
│  Reads: .claude/phase-state.json             │
│         .claude/build-progress.json          │
│         .claude/tool-preferences.json        │
│         templates/tool-matrix/*.json         │
│                                              │
│  Enforces: Phase gates, test gates,          │
│            version minimums, feature         │
│            recording                         │
│                                              │
│  Runtime: Node.js (already required)         │
└──────────────────────────────────────────────┘
```

### Registration

```bash
claude mcp add solo-orchestrator --scope project -- npx solo-orchestrator-mcp --project-dir .
```

Or at user scope if the server can auto-detect the project directory:

```bash
claude mcp add solo-orchestrator --scope user -- npx solo-orchestrator-mcp
```

### Tool Behavior Examples

**`orchestrator.record_feature("user-auth")`**
```json
{
  "status": "recorded",
  "features_completed": 3,
  "features_since_last_test": 1,
  "next_test_gate_in": 1,
  "message": "Feature 'user-auth' recorded. 1 more feature until UAT session required."
}
```

**`orchestrator.record_feature("payment-flow")` (when gate would trigger)**
```json
{
  "status": "gate_triggered",
  "features_since_last_test": 2,
  "message": "Feature 'payment-flow' recorded. UAT testing session NOW REQUIRED. Do not start the next feature. Run orchestrator.check_test_gate() for details."
}
```

**`orchestrator.check_test_gate()` (when blocked)**
```json
{
  "status": "blocked",
  "features_since_last_test": 2,
  "test_interval": 2,
  "message": "Testing session required before starting next feature.",
  "steps": [
    "Run UAT testing session (automated + exploratory + cross-platform)",
    "Generate test template for human tester",
    "Triage bugs with Orchestrator",
    "Fix all Fix Now bugs",
    "Call orchestrator.reset_test_counter() when complete"
  ]
}
```

**`orchestrator.get_project_status()`**
```json
{
  "project": "meshscope",
  "phase": 2,
  "track": "light",
  "platform": "desktop",
  "language": "python",
  "features_completed": ["file-loading", "3d-viewport", "user-auth"],
  "features_since_last_test": 1,
  "test_gate": "clear (1 more until UAT)",
  "phase_gate": "not yet (Phase 2 in progress)",
  "tools_outdated": [],
  "tools_below_minimum": []
}
```

## Why MCP Tools Work Better Than Instructions

1. **Tools are visible** — they appear in the agent's tool list. The agent is trained to use available tools for tasks, not to parse and follow long text instructions.

2. **Tools return structured data** — the agent gets a JSON response it can reason about, not text it has to parse from bash output.

3. **Tools can refuse** — if the test gate is blocked, `record_feature` can still work but the response tells the agent to stop. A text instruction can be ignored; a tool response is part of the conversation.

4. **Tools are discoverable** — the agent can call `get_project_status()` at any time to check state, rather than relying on remembering to run a bash script.

5. **Tools persist across context compaction** — tool definitions survive compaction. CLAUDE.md instructions may be summarized or lost.

## Implementation Considerations

### Language
Node.js (TypeScript). The MCP SDK is best supported in TypeScript, and Node.js is already a required dependency for the orchestrator (Snyk, license-checker, Claude Code itself).

### State Management
The server reads the same JSON files the bash scripts use (phase-state.json, build-progress.json, tool-preferences.json). No new state format — existing projects work without migration.

### Scope
Project-scoped MCP registration (not user-scoped). Each project gets its own server instance pointing to its own state files. This matches the current self-contained-after-init design.

### Versioning
The MCP server would be published as an npm package (`solo-orchestrator-mcp`). Version pinned per project at init time. Updates are opt-in via `npm update`.

### Backward Compatibility
The bash scripts remain functional. Projects that don't use the MCP server still work with hooks and CLAUDE.md instructions. The MCP server is an enhancement, not a replacement.

### What NOT to Include
- **Code generation** — the server enforces process, not implementation
- **File modification** — the server reads state files but does not write code
- **AI decision-making** — the server is a mechanical gate, not an advisor
- **Interactive wizards** — init stays as a bash script

## Relationship to Current Work

This is a v2 feature. Current enforcement uses SessionStart/Stop hooks with directive language in the agent context. The hooks work but depend on agent compliance. The MCP server would provide mechanical enforcement that the agent cannot bypass.

The transition path:
1. Build and test the MCP server alongside existing hooks
2. Verify the agent reliably uses MCP tools over bash scripts
3. Remove redundant hooks once MCP enforcement is proven
4. Keep CLAUDE.md instructions as documentation, not enforcement

## Open Questions

1. **Should the MCP server also handle Qdrant nudging?** It could expose `orchestrator.store_session_knowledge(content)` as a convenience wrapper that calls `qdrant-store` with consistent formatting. But this crosses into the Qdrant MCP server's domain.

2. **Should init.sh register the MCP server automatically?** If the npm package exists, init could add it to the project's `.claude/settings.json`. But this adds an npm dependency to init, which is currently pure bash.

3. **Should the server enforce CLAUDE.md instructions?** For example, the agent calls `orchestrator.start_feature("payment-flow")` which checks the test gate, verifies the phase, and returns a structured context block. This would replace the "read CLAUDE.md and follow the instructions" pattern entirely for Phase 2 workflow.

4. **How does this interact with the Dev Framework (CDF)?** The CDF has its own enforcement hooks. The MCP server should complement, not duplicate. Clear boundary: CDF enforces coding standards (pre-commit, markers, superpowers). Orchestrator MCP enforces project process (phases, test gates, feature tracking).

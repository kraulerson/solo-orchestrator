# Solo Orchestrator Platform Module: MCP Servers

## Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-PM-MCP |
| **Version** | 1.0 |
| **Classification** | Platform Module |
| **Date** | 2026-04-10 |
| **Parent Document** | SOI-002-BUILD v1.0 — Solo Orchestrator Builder's Guide |

---

## Scope

This module covers MCP (Model Context Protocol) servers: services that expose tools, resources, and prompts to AI assistant clients such as Claude Code, Claude Desktop, and other MCP-compatible hosts. It addresses both local/stdio servers and remotely hosted Streamable HTTP servers, including those that integrate with external APIs, maintain persistent data stores, and call LLM APIs internally for analysis.

---

## 1. Architecture Patterns

### 1.1 MCP SDK and Protocol

| Component | Recommended | Alternatives | Notes |
|---|---|---|---|
| **MCP SDK (TypeScript)** | `@modelcontextprotocol/server` + `@modelcontextprotocol/node` (modular) | `@modelcontextprotocol/sdk` (legacy monolithic) | The TypeScript SDK was split into modular packages (`core`, `client`, `server`, `node`). New projects should use the modular packages. The legacy monolithic `@modelcontextprotocol/sdk` package still works for existing code. |
| **MCP SDK (alternatives)** | `mcp` (Python), `rmcp` (Rust) | `mcp-golang` (Go) | Python SDK is mature; Rust SDK is official. |
| **Transport: Local** | stdio | — | Standard for Claude Code integration; server launched per-session |
| **Transport: Remote** | Streamable HTTP (`NodeStreamableHTTPServerTransport`) | WebSocket (not standard MCP) | For centralized hosting, homelab, multi-client access. SSE transport was removed from the MCP SDK — use Streamable HTTP for all remote servers. |
| **Schema Validation** | Zod | JSON Schema (manual) | Zod provides TypeScript type inference and runtime validation from a single source |

**Solo Orchestrator recommendation:** TypeScript with the modular MCP packages (`@modelcontextprotocol/server` for server-side, `@modelcontextprotocol/node` for Node HTTP transport). Support stdio for development and local use. Add Streamable HTTP transport if multi-client or remote hosting is a requirement. The legacy `@modelcontextprotocol/sdk` package still works but is being phased out; new projects should use the modular packages from the start.

### 1.2 Server Architecture

**Simple tool server (stateless):**
- Tools perform operations and return results
- No persistent state between invocations
- Suitable for: wrappers around external APIs, calculators, formatters

**Knowledge base server (stateful):**
- Maintains a persistent data store across invocations
- Tools query and mutate the knowledge base
- Suitable for: advisory systems, project registries, monitoring dashboards

**Hybrid server (stateful + external integration):**
- Persistent state plus external API integration and/or internal LLM calls
- Most complex; requires careful lifecycle management
- Suitable for: ecosystem advisors, aggregation services, intelligent monitoring

### 1.3 Storage Options

| Option | Best For | Trade-offs |
|---|---|---|
| **SQLite** (via `better-sqlite3`) | Local-first, single-user, portable | Fast, zero-config, single-file; no concurrent write support |
| **JSON files** | Maximum portability, simple schemas | Easy to inspect/edit; no query capability, manual integrity management |
| **PostgreSQL** (via Supabase/Neon) | Multi-user, remote hosting, complex queries | Full SQL, concurrent access; requires managed service or self-hosting |

**Solo Orchestrator recommendation:** SQLite for local-first MCP servers. JSON files only for trivially simple data. PostgreSQL if the server will be centrally hosted with multiple clients.

### 1.4 Hosting and Deployment

| Deployment | Transport | Best For |
|---|---|---|
| **Local (stdio)** | stdio | Development, personal use with Claude Code |
| **Docker (self-hosted)** | Streamable HTTP | Homelab, LXC containers, always-on access |
| **Railway / Render** | Streamable HTTP | Cloud hosting, no infrastructure management |
| **Fly.io** | Streamable HTTP | Edge deployment, global low-latency access |

### 1.5 Scheduling and Background Tasks

If the server needs to perform periodic work (monitoring, data refresh):

| Approach | Best For | Trade-offs |
|---|---|---|
| **node-cron** (in-process) | Long-running Streamable HTTP servers | Simple; tied to server lifecycle |
| **External cron** (OS or container) | stdio servers, separation of concerns | Server doesn't need to be running continuously |
| **Manual trigger tool** | User-controlled refresh | No automation; relies on user remembering to invoke |

**Solo Orchestrator recommendation:** For stdio servers, use external cron calling a CLI entry point. For Streamable HTTP servers, use in-process scheduling with node-cron. Always expose a manual trigger tool as well.

---

## 2. Tooling

### 2.1 Pre-Build Setup (MCP-Specific)

In addition to the Builder's Guide Pre-Build Setup:

**MCP SDK (modular — recommended for new projects):**
```bash
npm install @modelcontextprotocol/server @modelcontextprotocol/node
# Add @modelcontextprotocol/client only if the same package also consumes MCP servers
```

**MCP SDK (legacy monolithic — still functional for existing code):**
```bash
npm install @modelcontextprotocol/sdk
```

**Zod (schema validation):**
```bash
npm install zod
```

**SQLite (if using local persistence):**
```bash
npm install better-sqlite3
npm install -D @types/better-sqlite3
```

**Node-cron (if using in-process scheduling):**
```bash
npm install node-cron
npm install -D @types/node-cron
```

**MCP Inspector (testing/debugging):**
```bash
npx @modelcontextprotocol/inspector
```

### 2.2 Development Tooling

**MCP Inspector** — Interactive tool for testing MCP servers during development. Launches a web UI that connects to your server and lets you invoke tools, browse resources, and inspect responses.

```bash
# Test stdio server
npx @modelcontextprotocol/inspector node dist/index.js

# Test Streamable HTTP server
npx @modelcontextprotocol/inspector --url http://localhost:3000/mcp
```

**Claude Code integration testing** — Add the server to Claude Code's MCP config and test tool invocations in a real conversation:

```json
{
  "mcpServers": {
    "your-server": {
      "command": "node",
      "args": ["dist/index.js"],
      "env": {
        "API_KEY": "your-key-here"
      }
    }
  }
}
```

---

## 3. Build & Packaging

MCP servers are distributed as npm packages (for stdio) or Docker images (for remote hosting).

**Build pipeline:**
```bash
# TypeScript compilation
npm run build    # tsc -> dist/

# Verify the compiled entry point works
node dist/index.js --help
```

**Package.json configuration:**
```json
{
  "name": "your-mcp-server",
  "version": "1.0.0",
  "type": "module",
  "bin": {
    "your-mcp-server": "dist/index.js"
  },
  "files": ["dist/"],
  "engines": {
    "node": ">=18"
  }
}
```

**Docker build (for remote hosting):**
```dockerfile
FROM node:lts-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:lts-slim
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
USER node
EXPOSE 3000
CMD ["node", "dist/index.js", "--transport", "http"]
```

**CI/CD pipeline additions (MCP-specific):**
```yaml
# Add to the Builder's Guide CI configuration:
- name: Build
  run: npm run build
- name: MCP Inspector smoke test
  run: |
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"ci","version":"1.0.0"}}}' | \
    timeout 10 node dist/index.js || true
```

---

## 4. Testing

### 4.1 Unit Testing

Test tool handlers in isolation. Each tool handler is a function that takes validated input and returns structured output.

```bash
npm test
```

**What to unit test:**
- Tool input validation (valid inputs, boundary cases, malicious inputs)
- Tool handler logic (expected output for known input)
- Data store operations (CRUD, edge cases, concurrent access)
- External API response parsing (mock the HTTP calls, test the parsing)

### 4.2 Integration Testing with MCP Inspector

Use MCP Inspector to test the full server lifecycle:

1. Server initialization (capabilities, tool listing)
2. Tool invocation with valid parameters
3. Tool invocation with invalid parameters (verify error responses)
4. Resource listing and reading (if applicable)
5. Transport-specific behavior (stdio vs Streamable HTTP)

```bash
npx @modelcontextprotocol/inspector node dist/index.js
```

### 4.3 Protocol Compliance Testing

Verify the server implements the MCP protocol correctly:
- `initialize` / `initialized` handshake
- `tools/list` returns valid tool definitions
- `tools/call` handles valid and invalid tool names
- Error responses use correct JSON-RPC error codes
- Server handles client disconnection gracefully

### 4.4 Security Testing

**Input validation fuzzing:**
- Send oversized payloads to tool parameters
- Send unexpected types (string where number expected, nested objects where string expected)
- Send path traversal strings in any file-path-like parameters
- Send URL injection in any URL-like parameters

**External API mocking:**
- Mock external API failures (timeouts, 500s, malformed responses)
- Mock rate limit responses (429)
- Verify the server doesn't crash or leak errors to the client

### 4.5 Load Testing (Full Track)

If the server supports Streamable HTTP transport and will serve multiple clients:

```bash
# Test concurrent tool invocations
brew install k6
# or
docker pull grafana/k6
```

Define scenarios that simulate realistic concurrent tool usage.

---

## 5. Deployment & Distribution

### 5.1 npm Distribution (stdio servers)

```bash
# Publish to npm
npm publish

# Users install globally
npm install -g your-mcp-server

# Or run via npx
npx your-mcp-server
```

### 5.2 Docker Distribution (remote servers)

```bash
# Build and push
docker build -t your-mcp-server .
docker push your-registry/your-mcp-server:latest

# Users run
docker run -p 3000:3000 -e API_KEY=xxx your-registry/your-mcp-server:latest
```

### 5.3 Claude Code Configuration

Document the exact MCP configuration for users:

**stdio (local):**
```json
{
  "mcpServers": {
    "your-server": {
      "command": "npx",
      "args": ["-y", "your-mcp-server"],
      "env": {}
    }
  }
}
```

**Streamable HTTP (remote):**
```json
{
  "mcpServers": {
    "your-server": {
      "url": "http://your-host:3000/mcp"
    }
  }
}
```

### 5.4 Go-Live Checklist (MCP-Specific)

In addition to the Builder's Guide Phase 4.2:

- [ ] All tool definitions have complete JSON Schema input specifications
- [ ] All tool descriptions are clear enough for LLM invocation without examples
- [ ] MCP Inspector smoke test passes (initialize, list tools, invoke each tool)
- [ ] stdio transport tested in Claude Code
- [ ] Streamable HTTP transport tested with MCP Inspector (if applicable)
- [ ] Error responses are structured JSON-RPC errors (not bare strings or stack traces)
- [ ] Environment variables documented in README and `.env.example`
- [ ] Data store initialized correctly on first run (no manual setup required)
- [ ] Docker image builds and runs successfully (if applicable)
- [ ] Graceful shutdown on SIGTERM/SIGINT (no data corruption)

### 5.5 Monitoring Setup

**Error tracking:**
```bash
npm install @sentry/node
```
Alert on: tool invocation failures, external API errors, LLM API errors, data store corruption.

**Health check (Streamable HTTP servers):**
Expose a `/health` endpoint returning server status, data freshness, and external API reachability.

**Cost monitoring (if using LLM APIs internally):**
Track API token usage per tool invocation. Set alerts for unexpected cost spikes.

---

## 6. Maintenance (MCP-Specific)

In addition to the Builder's Guide maintenance cadence:

**Weekly:**
- Check external data source availability (are monitored URLs still responding?)
- Review LLM API costs against budget

**Monthly:**
- `npm audit` / `snyk test`
- Verify MCP SDK is up to date (protocol changes can break compatibility)
- Review data store size and freshness
- Check MCP Inspector for protocol compliance

**Quarterly:**
- MCP protocol version review (has the spec changed?)
- External API compatibility check (have scraped sites changed structure?)
- Evaluate whether tool definitions need updating (new use cases, improved descriptions)
- Review hosting costs against budget

### Data Integrity

MCP servers with persistent data stores need a data integrity strategy:

1. **Backup:** Automated backup of SQLite database or JSON data files before each update cycle.
2. **Rollback:** Ability to restore from the previous backup if an update corrupts data.
3. **Migration:** Versioned schema migrations for SQLite, with both up and down scripts.
4. **Validation:** Periodic integrity checks (SQLite `PRAGMA integrity_check`, JSON schema validation).

### Vulnerability Disclosure

Every published MCP server MUST include a vulnerability disclosure mechanism:

1. Add a `SECURITY.md` file to the repository.
2. Include: supported versions, how to report, expected response time, safe harbor statement.
3. MCP servers are particularly sensitive — a compromised tool can influence LLM behavior across all connected clients.

---

## 7. Phase-Specific Additions

### Phase 1 — Architecture Selection (Append to Core Prompt)

```
MCP-SERVER-SPECIFIC REQUIREMENTS:
11. MCP transport(s) to support (stdio, Streamable HTTP, or both)
12. Tool inventory with input/output schemas
13. Resource and prompt definitions (if any)
14. Persistence strategy (SQLite, JSON, PostgreSQL) and data model
15. External API integrations (list each source with rate limits and auth requirements)
16. Internal LLM integration (model selection, cost constraints, prompt strategy)
17. Scheduling strategy for background tasks (if any)
18. Deployment target (local-only, Docker, cloud PaaS)
```

### Phase 2 — Project Initialization (Append to Core Steps)

- [ ] MCP SDK installed and configured
- [ ] Entry point supports selected transport(s) (stdio, Streamable HTTP)
- [ ] At least one tool defined and invocable via MCP Inspector
- [ ] `.env.example` with all required environment variables
- [ ] Data store initialized on first run (schema migration or file creation)
- [ ] Docker support configured (if targeting remote deployment)

### Phase 3 — Security (Append to Core Steps)

- [ ] All tool inputs validated against JSON Schema (no raw parameter pass-through)
- [ ] External API connections use TLS with certificate validation
- [ ] No credentials hardcoded (all via environment variables)
- [ ] LLM prompts do not interpolate unsanitized user input
- [ ] Data store protected against path traversal and injection
- [ ] SBOM generated: `npx @cyclonedx/cyclonedx-npm --output-file sbom.json`

**Platform-specific SAST tools:** In addition to Semgrep (referenced in the Builder's Guide), add ESLint with `eslint-plugin-security` for Node.js-specific security anti-patterns.

---

## Appendix: Tool Quick Reference

| Tool | Install | Purpose |
|---|---|---|
| MCP SDK (modular) | `npm install @modelcontextprotocol/server @modelcontextprotocol/node` | MCP server framework — new projects |
| MCP SDK (legacy) | `npm install @modelcontextprotocol/sdk` | Monolithic package — existing projects only |
| MCP Inspector | `npx @modelcontextprotocol/inspector` | Interactive MCP testing/debugging |
| Zod | `npm install zod` | Schema validation and TypeScript inference |
| better-sqlite3 | `npm install better-sqlite3` | Embedded SQLite database |
| node-cron | `npm install node-cron` | In-process task scheduling |
| Semgrep | `pip install semgrep` | SAST |
| gitleaks | `brew install gitleaks` | Secret detection |
| license-checker | `npm install -g license-checker` | License compliance |
| Snyk | `npm install -g snyk` | Dependency scanning |
| CycloneDX | `npx @cyclonedx/cyclonedx-npm` | SBOM generation |
| Sentry | `npm install @sentry/node` | Error tracking |
| k6 | `brew install k6` | Load testing |

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-10 | Initial release. |

# UAT Authoring Guide

Reference for generating usable UAT test scenarios in solo-orchestrator projects. Complements the embedded comments in `templates/uat/test-session-template.html` — read both together when filling out a UAT session.

## 1. Why UAT quality matters

UAT scenarios that are schema-valid but operationally broken waste real human time. On the lancache project's first UAT session (2026-04-22), an AI agent generated scenarios that passed the template schema but failed as tester instructions: no system context, implicit working directory, cross-scenario dependencies, vague pass/fail criteria, non-deterministic expected output, informal cleanup, unmarked optional dependencies. The Orchestrator's feedback: *"The tests are not stating what system this is done on, it doesn't walk through the tests step by step and makes assumption the tester knows where everything is."* The rewrite recovered usability but cost substantial Orchestrator time. This guide codifies the rewrite recipe so every future project inherits the floor.

## 2. Universal quality checklist

Same 8 items as the HTML template comment, repeated here so they're discoverable outside the template context. Every scenario MUST meet all 8:

1. `steps` opens with a starting-state restatement. Use the same phrase project-wide (e.g., "You are in the project root with `.venv` active").
2. `steps` numbers every command. No cross-refs ("command from scenario N", "see above", "as before").
3. `steps` commands are fully copy-pasteable. No placeholders, no pseudo-shell, no ellipses.
4. `steps` prefers deterministic commands over ones whose output format varies across tool versions (e.g., SQL query over `sqlite3 .tables`).
5. `expected` has a CONCRETE pass/fail anchor: an exact string, an exit code, a line count, or a deterministic single-value assertion. "Works" / "succeeds" / "no errors" are NOT anchors.
6. `expected` is ≥60 characters.
7. If the scenario MUTATES state (files, DB, env, hardware), include numbered cleanup steps + a verification step at the end.
8. If the scenario has an EXTERNAL dependency (Docker, network peer, service), include a probe step whose output tells the tester to proceed or Skip.

## 3. Per-platform pre-flight patterns

### 3.1 web

A web pre-flight must establish: browser name + version (minimum), app URL (local dev, staging, or prod — specify which), test environment state (backend services running, database seeded), credentials for any authenticated scenarios, assumed network state (online, and whether VPN or auth proxy is in the path), devtools availability (many scenarios use Network tab or Console for assertions), and a one-time setup block (open URL, sign in, confirm home page loads without console errors).

Common pre-flight content for web:
- **System under test:** Chromium-based browser version; Firefox compatibility note.
- **App URL:** local dev URL, with Orchestrator-provided staging URL as alternative.
- **Accounts/credentials:** the default test account; multi-user scenarios name their own credentials inline.
- **Optional tools:** devtools for scenarios that use Network/Console.
- **One-time setup:** open URL → sign in → confirm no console errors.

Reference file: `templates/uat/references/web-pre-flight.html`.

### 3.2 desktop

A desktop pre-flight must establish: OS + architecture (Windows WSL deltas called out inline), absolute project root path, language runtime + version (with virtualenv / rbenv / nvm equivalent), required tools (the commands every scenario assumes are installed), optional tools (called out with the scenarios that require them), and a one-time setup block (cd, activate runtime, sanity-check version).

Common pre-flight content for desktop:
- **System under test:** macOS (darwin/arm64) or Linux (x86_64/arm64); WSL-acceptable with caveats.
- **Project root:** absolute path placeholder for the Orchestrator to fill in.
- **Language runtime:** specific version inside `.venv/` or equivalent.
- **Required tools:** `git`, `jq`, `python`/`node`/`cargo`/`go` per stack.
- **One-time setup:** three lines max — `cd`, activate, version check.

Reference file: `templates/uat/references/desktop-pre-flight.html`.

### 3.3 mobile

A mobile pre-flight must establish: device OR simulator/emulator (specify which, and the exact model + OS version), app build source (TestFlight build ID, Internal Test track build, or local Xcode/Android Studio run), app version + build number the tester should confirm on the About screen before starting, required accounts for authenticated scenarios, assumed device state (network on, permissions in default state unless noted), and a one-time setup block (install build, complete onboarding, sign in, confirm home screen).

Common pre-flight content for mobile:
- **System under test:** iOS or Android; specific device or simulator model.
- **App build:** exact build ID, source (TestFlight / Internal / local), expected version on the About screen.
- **Accounts:** default test credentials; note multi-user variants.
- **Optional tools:** screen recording for scenarios that benefit from tap-sequence capture.
- **One-time setup:** install, launch, onboard, sign in, confirm home.

Reference file: `templates/uat/references/mobile-pre-flight.html`.

### 3.4 mcp-server

An MCP-server pre-flight must establish: MCP client the scenarios assume (MCP Inspector is reproducible and recommended; Claude Desktop and Claude Code are valid alternatives), server command with any required env vars, transport (stdio vs HTTP), auth configuration, and a one-time setup block (export env vars, start Inspector pointing at the server, confirm tools/resources list loads).

Common pre-flight content for mcp-server:
- **System under test:** MCP server + Inspector (or alternate client).
- **Server command:** exact invocation from the project's mcp.json.
- **Transport:** stdio default; HTTP noted separately where used.
- **Auth:** env var exports (e.g., `MCP_API_KEY`).
- **One-time setup:** export env → start Inspector against server → confirm connection.

Reference file: `templates/uat/references/mcp-server-pre-flight.html`.

## 4. Per-platform scenario patterns

### 4.1 web

Typical scenario shapes: authenticated form submission with Network-tab verification (assert HTTP status + response body shape); visual confirmation of a rendered page change; mutation-with-cleanup (create record, verify it, delete it, verify it's gone); optional scenarios that use devtools Console to read state.

Example anchor styles:
- "POST /api/items returns HTTP 201 Created. Response body has an `id` field."
- "The /items list shows the new record at the top with category 'general'."
- "After deletion, GET /api/items/<id> would return 404."

Reference file: `templates/uat/references/web-scenario.json`.

### 4.2 desktop

Typical scenario shapes: deterministic command sequences (prefer SQL over meta-commands); state-mutation followed by git-diff verification (modify → test → restore → `git diff --exit-code && echo RESTORED`); dependency-probed scenarios (Docker, network service) with skip branches; exit-code assertions (`echo "exit=$?"` after critical commands).

Example anchor styles:
- "Traceback ends in a MigrationError whose message contains 'checksum mismatch'."
- "`git diff --exit-code` returns 0 and prints 'RESTORED'."
- "Output contains `total=42` on a single line."

Reference file: `templates/uat/references/desktop-scenario.json`.

### 4.3 mobile

Typical scenario shapes: tap-sequence with observation criteria (exact on-screen text or visible indicator); connectivity transitions (airplane mode → offline behavior → reconnect → sync); permission-state scenarios (granted, denied, revoked mid-session); cleanup via app UI (long-press delete, empty cache, etc.); screenshot-attached failure capture.

Example anchor styles:
- "Submit button shows a 'queued' state with a badge on the Outbox icon."
- "Sync indicator appears for ≥1 second, then disappears; post appears in the list."
- "No crash dialog. App does not return to the home screen."

Reference file: `templates/uat/references/mobile-scenario.json`.

### 4.4 mcp-server

Typical scenario shapes: JSON-RPC tool invocation with response-shape assertions (exact types and values for named fields); pagination/cursor behavior; error-response shape (tool call with invalid args); resource read with content assertion; state-mutation tools paired with inverse calls for cleanup.

Example anchor styles:
- "`response.result.items` is an array of length 10."
- "`response.result.total` is the integer 25."
- "Response does not contain an `error` field at the top level."

Reference file: `templates/uat/references/mcp-server-scenario.json`.

## 5. Co-build protocol for 'other' platform

This is the interactive Q&A the session agent runs with the Orchestrator when the project's platform is `other` (embedded SoC, firmware, game, unusual CLI, or anything without a canned reference).

**When to run:** at UAT session start, before generating the pre-flight block or any scenarios. The agent should announce: *"Your project's platform is 'other' — no canned reference is available. I have five questions to calibrate the UAT shape before I generate scenarios."*

**Question 1 — Runtime and tooling environment.** "What does 'running the system under test' look like in your project? Is it a terminal command, a hardware device you power on, a browser, a specific IDE, a physical rig?" Follow-up if unclear: "Give me one concrete example of starting or resetting the system to a known-good state."

**Question 2 — User-interaction model.** "How does a human tester interact with the system under test during a scenario? Typing in a shell, tapping on a device, clicking in a browser, sending API requests, pressing physical buttons, observing serial output, some combination?"

**Question 3 — State mutation surface.** "If a scenario makes the system 'do something' that changes state, what's affected? Files on disk, database rows, hardware registers, cloud resources, network peers, user accounts? Is that state easy to observe and reset?"

**Question 4 — External dependencies.** "What external things does testing depend on? Hardware attached to the test rig, a specific network peer or internet service, a database with seeded data, a container engine, another instance of the same app?"

**Question 5 — Cleanup constraints.** "If a scenario leaves residue (modified files, hardware in an unknown state, cloud resources, etc.), what's the appropriate cleanup? Is there a 'reset to factory' command, a git-checkout-level restore, a manual hardware power-cycle, a purge-by-timestamp script?"

**Synthesizing the answers:** after collecting the answers, the agent should generate a pre-flight block mirroring the structure of the first-class reference pre-flights (filled with the Orchestrator's specifics), plus an initial scenario or two demonstrating the shape (happy path, mutation with cleanup, dependency-probed if applicable). Show these to the Orchestrator for review before generating the full scenario set. Use the refined shape as the template for remaining scenarios.

## 6. Linter usage

**Invocation:** `scripts/lint-uat-scenarios.sh <populated-html-file>`.

**Exit codes:**
- `0` — all scenarios clean. Proceed with dispatch.
- `1` — quality violations. Read the stderr list (one violation per line). Revise flagged scenarios. Re-run the linter until exit 0.
- `2` — structural failure (file not found, JSON unparseable, scenarios block missing). Fix file integrity before worrying about scenario quality.

**Common false-positive-looking cases and how to resolve them:**

- A `steps` line that legitimately starts with a command (e.g., `cd` to a different directory): the state-restatement check passes because `cd ` IS one of the accepted keywords. If you're getting the error anyway, check the very first character of `steps` — indentation or leading whitespace will trip it.
- A short `expected` with a clear anchor (e.g., `exit=0`): expand the prose around the anchor to reach the 60-character minimum. The character minimum is a proxy for specificity, not a literal rule — meeting it honestly is easy with one more sentence of context.
- A scenario's `expected` contains "succeeds" or "works" as part of a larger sentence (e.g., "Build succeeds and writes 42 files"): only exact-match bans trigger. The banned-phrase check looks for `expected` being exactly (or primarily) one of the banned short words.

## 7. Extending for a new platform

When solo-orchestrator gains a new first-class platform (e.g., `extension` for browser extensions, `cli` if it splits out from desktop), three things need to happen for UAT parity:

1. Add `templates/uat/references/<platform>-pre-flight.html` and `templates/uat/references/<platform>-scenario.json` matching the shape of the existing four.
2. Update `init.sh`'s per-platform reference copy step to include the new platform in its case branch.
3. Add a subsection in Sections 3 and 4 of this guide documenting the new platform's pre-flight and scenario patterns.

The `other` platform co-build protocol remains the fallback for anything that doesn't have a matching reference pair.

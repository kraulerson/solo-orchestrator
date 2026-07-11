# UAT Template Quality Guardrails + Platform-Aware Authoring

**Date:** 2026-04-23
**Status:** Design approved, pending spec review
**Scope:** Framework-level change to solo-orchestrator
**Implements:** BL-009 (new entry to be filed alongside this spec)

## Problem

On the lancache project (solo-orchestrator v1.0 downstream), UAT Session 1 (2026-04-22) revealed that the framework's UAT template accepts schema-valid scenarios that are nevertheless operationally broken. An AI agent generating a UAT template produced scenarios that passed the schema but failed as tester instructions: no system context, implicit working directory, cross-scenario dependencies, vague pass/fail criteria, non-deterministic output matching, informal cleanup, unmarked optional dependencies. The Orchestrator's review: *"The tests are not stating what system this is done on, it doesn't walk through the tests step by step and makes assumption the tester knows where everything is."* Rewriting recovered usability; that rewrite recipe should be captured at the framework level so every future project inherits it.

Beyond the universal authoring failures above, there is a **platform-variance gap**: the existing template's embedded example is desktop-CLI shaped (Python venv, sqlite3, terminal commands), which does not translate to web (browser + URL), mobile (device/simulator), MCP-server (JSON-RPC), or long-tail platforms (embedded SoC, firmware, game). An authoring agent with no platform-specific reference generates desktop-shaped scenarios regardless of the project's actual platform.

## Goals

- Raise the floor on UAT scenario quality so generated scenarios are operationally usable by a human tester who did not author them.
- Provide platform-appropriate reference examples for solo's four first-class platforms (web, desktop, mobile, mcp-server) so agents generate scenarios in the right idiom.
- Handle the `other` platform (embedded, unusual, or new) via an interactive co-build protocol instead of a generic fallback.
- Mechanically catch the most common authoring failures via a lightweight linter.
- Make the upgrade path for existing projects idempotent and non-breaking.

## Non-Goals

- No refactor of scenarios into a separate JSON file. The template stays a single HTML file with embedded placeholders.
- No hook-level integration of the linter into `--start-uat` or pre-commit. Agent-invoked only; keeps script boundaries clean.
- No per-platform linter behavior. Linter checks are universal; platform variance is carried by the reference examples.
- No per-version template hash tracking for "smart" upgrade. Re-copy is unconditional; git diff is the visibility mechanism.
- No full parity between the HTML and Markdown templates. MD gets a preflight reminder and an HTML-template pointer; full per-platform reference set is HTML-only.
- No dedicated new platform-module for embedded SoC. "other" remains the category; co-build protocol handles long-tail per-project variation.

## Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Scope of adoption | Use the lancache diff as inspiration; redesign with platform-awareness built in | Lancache diff's content is high-quality but desktop-CLI shaped; framework supports 4 platforms |
| 2 | Platform coverage | Full: 4 first-class reference pairs + `other` co-build protocol + adaptation guide | Matches the framework's existing 4-platform commitment; long-tail gets interactive handling |
| 3 | MD template parity | Partial: preflight reminder + HTML pointer; no per-platform reference duplication | MD is simple-case fallback; full parity is scope creep |
| 4 | Linter | Ship pattern-based linter (Approach 1) | Catches the observed failure patterns directly; no integration coupling |
| 5 | File layout | `templates/uat/` subdirectory with `references/` nested | Matches the existing `templates/pipelines/`, `templates/platform-modules/` convention |
| 6 | Upgrade migration | Auto-migrate via upgrade-project.sh (unconditional re-copy) | Matches host-aware-gate precedent; git diff surfaces any user customizations |

## Architecture

Three layers of guardrails, each addressing a distinct part of the failure.

**Layer 1 — Template-level guardrails (universal).** Embedded in `templates/uat/test-session-template.html` as HTML comments. The template gets a new `__TESTER_PRE_FLIGHT__` placeholder that the agent must populate before any feature section; the `__SCENARIOS_JSON__` comment is extended with the 8-item quality checklist and an anti-pattern list. All platforms inherit these.

**Layer 2 — Platform-specific reference examples.** Eight new files under `templates/uat/references/` — a pre-flight HTML snippet and a scenario JSON object per first-class platform (web, desktop, mobile, mcp-server). At init/upgrade time, `init.sh` and `upgrade-project.sh` select the pair matching the project's `$PLATFORM` and copy it into `tests/uat/examples/`. For `$PLATFORM=other`, no reference files are copied; the template comment directs the agent to run the co-build Q&A protocol documented in `docs/uat-authoring-guide.md` with the Orchestrator.

**Layer 3 — Mechanical linter.** `scripts/lint-uat-scenarios.sh` runs six pattern-based checks against a populated template. Agent is instructed (via HTML comment + CLAUDE.md Testing & Bug Workflow section) to run the linter before saving. Exit 0 on clean scenarios; exit 1 on violations (listed per-scenario); exit 2 on structural/parse failure.

**Enforcement placement:** all three layers fire at the agent's generation moment. No hooking into `--start-uat` (keeps script boundaries clean). The linter is agent-invoked; if an agent skips it, the prominent HTML-comment instruction and CLAUDE.md reminder are the mitigations, plus human-tester/orchestrator review before dispatch.

**Universal vs. platform-specific split:**

| Concern | Scope |
|---|---|
| 8-item quality checklist | Universal (template comment) |
| Anti-pattern list | Universal (template comment) |
| `__TESTER_PRE_FLIGHT__` placeholder | Universal |
| Pre-flight **content** | Platform-specific (reference file or co-build output) |
| Example scenario content | Platform-specific (reference file or co-build output) |
| Linter anti-pattern checks | Universal |
| Co-build protocol | `other` platform only |

## Components

### New files

```
templates/uat/
  references/
    web-pre-flight.html            # HTML snippet — rendered at __TESTER_PRE_FLIGHT__
    web-scenario.json              # JSON object — shape for __SCENARIOS_JSON__ elements
    desktop-pre-flight.html
    desktop-scenario.json
    mobile-pre-flight.html
    mobile-scenario.json
    mcp-server-pre-flight.html
    mcp-server-scenario.json

scripts/
  lint-uat-scenarios.sh            # Pattern-based linter, ~80–100 lines

docs/
  uat-authoring-guide.md           # Per-platform authoring patterns + co-build protocol + linter usage

tests/
  test-lint-uat-scenarios.sh       # ~200 lines; 11 cases covering each check + happy path
```

### Moved files (with content updates)

| From | To | Content change |
|------|-----|----------------|
| `templates/uat-test-session.html` | `templates/uat/test-session-template.html` | Adds `__TESTER_PRE_FLIGHT__` placeholder + authoring instructions; extends `__SCENARIOS_JSON__` comment with 8-item quality checklist + anti-pattern list + expanded example; adds "run `scripts/lint-uat-scenarios.sh` before saving" instruction |
| `templates/uat-test-template.md` | `templates/uat/test-session-template.md` | Adds short "Before you start" pre-flight reminder + pointer to HTML template for the full quality bar |

### Modified files

| File | Change |
|------|--------|
| `init.sh` | Update UAT template copy paths (lines 1075–1076 → new `templates/uat/` paths); add per-platform reference-pair copy step keyed on `$PLATFORM` that copies `templates/uat/references/<platform>-{pre-flight.html,scenario.json}` into `tests/uat/examples/pre-flight-reference.html` and `scenario-reference.json`; for `$PLATFORM=other`, skip the reference copy and print a note about the co-build protocol |
| `scripts/upgrade-project.sh` | Migration block: if old `tests/uat/templates/test-session-template.html` exists, re-copy updated source templates (idempotent overwrite); copy per-platform reference pair (idempotent); print post-upgrade notice pointing at `docs/uat-authoring-guide.md` and the new linter |
| `templates/generated/claude-md.tmpl` | Testing & Bug Workflow section gets: (1) a step `"Run scripts/lint-uat-scenarios.sh <populated-file> before saving — must exit 0"` inserted in the 1–9 UAT step list at position 4a; (2) a reference to `docs/uat-authoring-guide.md` for authoring patterns and the co-build protocol for `other` platforms |

### Linter contract

**Invocation:** `scripts/lint-uat-scenarios.sh <populated-html-file>`

**Extraction:** Reads the HTML file; locates the JS array between `const scenarios = ` and `];`; parses as JSON via `jq`.

**Universal checks (per scenario):**

1. `expected` length ≥ 60 characters.
2. `expected` content is not (exactly or primarily, case-insensitive) one of: `"works"`, `"succeeds"`, `"passes"`, `"no errors"`, `"builds successfully"`, `"completes"`.
3. `steps` does not contain any of: `"command from scenario"`, `"see above"`, `"as before"`, `"like scenario"`, `"as in scenario"` (case-insensitive).
4. `steps` first line starts with a state-restatement keyword: `"You are"`, `"cd "`, `"Setup:"`, `"Before starting"`, `"Preconditions:"` (case-insensitive).

**Universal checks (file-level):**

5. No `__…__` placeholders remaining in the file (double-underscore-wrapped tokens).
6. No duplicate scenario `id` values.

**Exit codes:**

- `0` — all clean.
- `1` — one or more violations (quality failure).
- `2` — file not found, unreadable, or scenarios block can't be extracted / parsed (structural failure).

**Output:**

- stdout: success line (`"All 5 scenarios clean."`) on exit 0; summary line (`"6 violations found. Revise the flagged scenarios and re-run the linter."`) on exit 1.
- stderr: per-violation lines formatted `scenario N: check-name — <offending excerpt>` on exit 1; diagnostic line on exit 2.

### Reference file shapes

- **Pre-flight HTML files** are single `<div class="fixture-ref">…</div>` blocks with platform-appropriate content. Content axes per platform:
  - **web** — browser + version, app URL, test environment (local / staging), accounts/credentials, network state assumption, how to run a scenario (click details / copy steps / compare visually or in devtools).
  - **desktop** — OS + arch, project root path, language runtime + venv, required tools, one-time setup, terminal assumptions.
  - **mobile** — device or simulator/emulator, OS version, app build track (TestFlight / internal beta), device state assumption, how to run a scenario.
  - **mcp-server** — MCP client (Claude Code / Claude Desktop / MCP Inspector), server command + args, auth env vars, transport (stdio / HTTP), how to invoke tools and read resources.

- **Scenario JSON files** are single-element examples illustrating each platform's scenario idiom, each meeting all 8 checklist items. One or two mutating scenarios per platform to show cleanup+verification pattern; one or two dependency-gated scenarios per platform to show probe pattern.

### UAT authoring guide (`docs/uat-authoring-guide.md`)

Sections:

1. **Why UAT quality matters** — one paragraph citing the lancache failure modes.
2. **Universal quality checklist** — same 8 items as the HTML comment; repeated here for reference outside the template context.
3. **Per-platform pre-flight patterns** — web / desktop / mobile / mcp-server; 3–5 paragraphs each with examples.
4. **Per-platform scenario patterns** — parallel structure; examples for happy path, mutation, dependency-gated.
5. **Co-build protocol for `other` platform** — the Q&A sequence the agent runs with the Orchestrator. Five required questions: runtime/tooling environment; user-interaction model (terminal / browser / device / hardware / API / other); possible state mutations the tests could cause; external dependencies and probing; cleanup constraints. Template for synthesizing answers into a pre-flight block and initial scenario set.
6. **Linter usage** — invocation, exit codes, interpreting violations, handling common false-positive-looking cases.
7. **Extending the framework for a new platform** — what files to add (reference pair under `templates/uat/references/`, optionally a platform-module under `docs/platform-modules/`) and what docs to update.

Target length: ~200–300 lines.

## Data Flow

### Flow A — New project init

1. `init.sh` collects `$PLATFORM` from intake (web / desktop / mobile / mcp-server / other).
2. In the `create_project` template-copy block (currently lines 1074–1076), create `tests/uat/templates/` and `tests/uat/examples/` and `tests/uat/sessions/`.
3. Copy both source templates (`test-session-template.html` and `.md`) from `templates/uat/` into `tests/uat/templates/`.
4. If `$PLATFORM != other` and the reference pair exists: copy `templates/uat/references/<platform>-pre-flight.html` → `tests/uat/examples/pre-flight-reference.html` and `templates/uat/references/<platform>-scenario.json` → `tests/uat/examples/scenario-reference.json`. Print confirmation.
5. If `$PLATFORM = other`: skip reference copy. Print note that the session agent will run the co-build protocol per `docs/uat-authoring-guide.md`.

Net additions to init.sh: ~15 lines.

### Flow B — Existing project upgrade

1. `upgrade-project.sh` detects pre-migration state: if `tests/uat/templates/test-session-template.html` exists, proceed.
2. Re-copy source templates from framework's `templates/uat/` to project's `tests/uat/templates/` (idempotent overwrite).
3. Read `$PLATFORM` from `.claude/intake-progress.json` (the intake wizard's output, created via `save_answer`); copy per-platform reference pair (or print co-build note for `other`).
4. Print post-upgrade notice referencing the new linter and authoring guide.

Historical session folders under `tests/uat/sessions/*/templates/` are not touched — they are artifacts, not sources.

Net additions to upgrade-project.sh: ~30 lines.

### Flow C — UAT authoring (where the linter runs)

1. Human orchestrator: "Start UAT session N."
2. Agent runs `scripts/process-checklist.sh --start-uat N` (unchanged).
3. Agent copies `tests/uat/templates/test-session-template.html` into the session-specific path (e.g., `tests/uat/sessions/session-N/templates/test-session-N.html`).
4. Agent reads the HTML comments (checklist + anti-patterns + reference pointers). For non-`other` platforms, reads `tests/uat/examples/pre-flight-reference.html` and `scenario-reference.json` as shape templates.
5. For `$PLATFORM = other`: agent runs the co-build Q&A protocol with the Orchestrator.
6. Agent fills `__TESTER_PRE_FLIGHT__` and `__SCENARIOS_JSON__`.
7. Agent runs `scripts/lint-uat-scenarios.sh <populated-file>`:
   - Exit 0: proceed with UAT dispatch.
   - Exit 1: read violations, revise, re-run linter.
   - Exit 2: investigate file/JSON integrity (not a scenario-quality issue).
8. After linter passes, usual UAT dispatch (email tester / wait for results / etc.) proceeds per existing workflow.

**Linter is agent-invoked, not automatic.** The HTML-comment instruction and CLAUDE.md step are the mitigations against skipping. If observed skipping becomes a pattern across projects, upgrading to automatic invocation (hook into `--start-uat`) is a small, backward-compatible later change.

### Concurrency and atomicity

All three flows are single-user, single-process. Linter is read-only (no state mutation). File-copy operations use plain `cp` (no `.tmp`-then-`mv`) per existing init.sh convention. No locks needed.

## Error Handling

Four code-level categories plus one documented non-code-caught risk.

### 1. Linter: missing file or JSON parse failure

**Trigger:** file doesn't exist / is a directory / contains no `const scenarios = …];` block / JSON block is malformed.

**Response:** Exit 2. stderr formats as `lint-uat-scenarios.sh: <file>: <reason>` where `<reason>` is one of `No such file or directory`, `No scenarios block found — is the file populated?`, or `JSON parse failed: <jq error>`. No pattern-checks run when scenarios can't be extracted.

### 2. Linter: quality violations

**Trigger:** one or more of the six checks fails.

**Response:** Exit 1. stderr lists per-violation lines: `scenario N: check-name — <excerpt>` and file-level: `file-level: <check-name> — <context>`. stdout summary: `"<N> violations found. Revise the flagged scenarios and re-run the linter."`. Line numbers accompany file-level violations (unreplaced placeholders); scenario IDs accompany per-scenario violations.

### 3. Init / upgrade: missing reference files for a first-class platform

**Trigger:** the framework's `templates/uat/references/<platform>-*` files don't exist when init.sh or upgrade-project.sh tries to copy them. Indicates a corrupt framework checkout or a newly-added platform without matching references.

**Response:** `print_warn` with fallback text pointing to co-build protocol; proceed to completion. UAT is still generatable via the `other`-equivalent interactive path. Not blocking.

### 4. Upgrade: project customized a template file about to be overwritten

**Trigger:** upgrade-project.sh re-copies the source template over a downstream copy that was modified.

**Response:** Unconditional overwrite (matches Question 6 / Option A decision). `git diff` surfaces the change; user can restore selectively. Post-upgrade notice reminds: `"See git diff — if any template files changed, review and restore local customizations as needed."`

### 5. Agent skips the linter (operational, not code-caught)

**Trigger:** agent writes and saves a populated UAT file without running the linter.

**Mitigations (by design):**

- HTML-comment instruction placed immediately above `const scenarios = __SCENARIOS_JSON__;` — hard to miss when populating the placeholder.
- CLAUDE.md's Testing & Bug Workflow section adds the linter invocation as step 4a in the 1–9 UAT sequence.
- Human orchestrator's pre-dispatch review includes verifying the linter was run and passed.

**Not mitigated in this spec:** automatic invocation via `--start-uat` hook. Reserved as a backlog followup if observed skipping becomes a pattern.

## Testing

### Layer 1 — Linter unit tests

**File:** `tests/test-lint-uat-scenarios.sh` — ~200 lines; 11 cases.

| # | Case | Seeded content | Assertion |
|---|------|----------------|-----------|
| 1 | Happy path | 3 scenarios meeting all 8 checklist items | Exit 0, no violations |
| 2 | Unreplaced `__TESTER_PRE_FLIGHT__` | Placeholder intact | Exit 1, `unreplaced placeholder` in stderr |
| 3 | Unreplaced `__SCENARIOS_JSON__` | Scenarios placeholder intact | Exit 2, `No scenarios block found` |
| 4 | `expected` too short | `"expected": "OK"` | Exit 1, `expected too short` |
| 5 | `expected` is banned phrase | `"expected": "works"` | Exit 1, `banned vague phrase` |
| 6 | `steps` contains "see above" | `"steps": "1. see above..."` | Exit 1, `banned cross-ref` |
| 7 | `steps` missing state restatement | `"steps": "1. pytest foo"` | Exit 1, `state-restatement` |
| 8 | Duplicate scenario IDs | Two scenarios with `"id": 2` | Exit 1, `duplicate scenario id` |
| 9 | Missing input file | Nonexistent path | Exit 2, `No such file or directory` |
| 10 | Malformed JSON block | Syntax error in scenarios array | Exit 2, `JSON parse failed` |
| 11 | Multiple violations | 3 scenarios each failing different checks | Exit 1, 3 violation lines + summary `3 violations found` |

Harness: inline assertion helpers matching `tests/test-unrecord-feature.sh` pattern. Zero external dependencies.

### Layer 2 — Init / upgrade integration tests

**File:** extend `tests/edge-cases-scripts.sh` — the UAT-template copy behavior is a script-level edge case, consistent with the existing test placement.

| # | Case | Setup | Assertion |
|---|------|-------|-----------|
| 1 | Init for `web` copies web references | `$PLATFORM=web`, run init's UAT-copy block | `tests/uat/examples/pre-flight-reference.html` and `scenario-reference.json` exist; content is web-specific (grep for browser keyword) |
| 2 | Init for `desktop` copies desktop refs | `$PLATFORM=desktop` | Desktop-specific refs at correct paths |
| 3 | Init for `mobile` copies mobile refs | `$PLATFORM=mobile` | Mobile-specific refs (grep for device/simulator) |
| 4 | Init for `mcp-server` copies mcp refs | `$PLATFORM=mcp-server` | MCP-specific refs (grep for MCP client or JSON-RPC) |
| 5 | Init for `other` skips refs, prints co-build note | `$PLATFORM=other` | No `tests/uat/examples/*-reference.*` files; init output contains `co-build protocol` |
| 6 | Upgrade re-copies templates on pre-migration layout | Seed old-layout project; run upgrade | Source templates now contain new preflight placeholder + quality checklist comments |
| 7 | Upgrade is idempotent | Run upgrade twice on same project | Second run produces no unexpected changes |

Estimated size: ~120–150 lines.

### Not tested (with rationale)

| What | Why |
|---|---|
| Agent behavior (reads comments, runs linter) | Outside code-level testing; observed in real UAT sessions |
| Per-platform content quality of reference files | Reviewed at authoring time; no mechanical check |
| Markdown template edits | Tiny content change; verified manually |
| Co-build protocol conversational quality | Human-interaction flow; can't be unit-tested |

## Open Questions

None. All decisions captured in the Decisions table.

## Related

- Backlog: `solo-orchestrator-backlog.md` — file BL-009 alongside this spec.
- Trigger: lancache project UAT Session 1, 2026-04-22 → 2026-04-23.
- Precedent for safety pattern (upgrade migration via unconditional re-copy): BL-008 host-aware-gate upgrade-project.sh migration block.
- Precedent for platform-aware framework assets: `docs/platform-modules/`, `templates/pipelines/ci/<host>/`, `templates/pipelines/release/<host>/`.
- Non-scope follow-ups worth filing if issues emerge: automatic linter invocation via `--start-uat` hook (Approach 2 from brainstorming); full MD/HTML template parity (rejected in Question 3); structural JSON-first validator (Approach 3 from brainstorming).

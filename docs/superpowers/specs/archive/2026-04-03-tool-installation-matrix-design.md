# Tool Installation Matrix — Design Spec

## Date: 2026-04-03

## Problem

init.sh installs a flat list of security tools regardless of platform, with only minimal branching for web (Lighthouse, ZAP) and language runtimes. This leaves significant gaps:

- **Mobile projects** are missing ~12 platform-specific tools (EAS CLI, Xcode tools, CocoaPods, Android SDK, code signing, etc.)
- **Desktop projects** are missing ~10 platform-specific tools (Tauri CLI, Electron builder, platform build deps, etc.)
- **All projects** are missing license compliance tooling, E2E testing frameworks, and load testing tools
- **Superpowers plugin** is only warned about, never offered for installation
- Tools are installed at init time regardless of whether the project track or phase requires them
- Users cannot substitute their own preferred tools or add custom tooling
- Claude has no visibility into what tools are actually available in the project environment

## Solution

A matrix-driven tool installation system that resolves the correct tool set based on project context (dev OS, target platform, language, track, and current phase), supports user substitutions and additions, and installs tools at the moment they're needed.

## Architecture

Three components:

1. **Matrix files** (data) — JSON files defining available tools, their requirements, and install commands
2. **Resolver script** (logic) — reads the matrix, filters by project context, checks installed state, outputs an actionable plan
3. **Trigger points** (UI) — init.sh, check-phase-gate.sh, and track upgrades call the resolver and present results to the user

---

## 1. Matrix File Structure

### Location

`templates/tool-matrix/`

### Files

| File | Scope |
|---|---|
| `common.json` | Universal tools: Git, jq, security scanners, Claude Code, Superpowers, MCP servers |
| `web.json` | Web-specific: Lighthouse, ZAP, license-checker (npm), Playwright, k6 |
| `mobile.json` | Mobile-specific: EAS CLI, Xcode tools, CocoaPods, Android SDK, mobile license checkers |
| `desktop.json` | Desktop-specific: Tauri CLI, Electron builder, platform build deps, desktop license checkers |

New platform files can be added following the same pattern.

### Tool Entry Schema

Each file contains a `tools` array. Each entry:

```json
{
  "category": "sast",
  "name": "Semgrep",
  "description": "Static analysis security scanner",
  "required": true,
  "phase": 1,
  "tracks": ["light", "standard", "full"],
  "dev_os": ["darwin", "linux"],
  "platforms": ["all"],
  "languages": ["all"],
  "check_command": "command -v semgrep",
  "install": {
    "darwin_brew": "brew install semgrep",
    "linux_pip": "pip3 install semgrep",
    "manual": "https://semgrep.dev/docs/getting-started/"
  },
  "auto_installable": true,
  "substitutable": true,
  "substitution_category": "SAST Scanner"
}
```

### Field Definitions

| Field | Type | Description |
|---|---|---|
| `category` | string | Machine-readable category key (e.g., `sast`, `secret_detection`, `license_compliance`) |
| `name` | string | Human-readable tool name |
| `description` | string | One-line description of what the tool does |
| `required` | boolean | If true, phase gate blocks when this tool is missing. If false, tool is recommended but optional. |
| `phase` | number | Phase when this tool becomes relevant (0 = prerequisites, 1-2 = build, 3 = validation, 4 = release) |
| `tracks` | string[] | Which project tracks need this tool: `light`, `standard`, `full` |
| `dev_os` | string[] | Which dev machines can run it: `darwin`, `linux`, or both |
| `platforms` | string[] | Target platforms this applies to: `web`, `mobile`, `desktop`, or `all` |
| `languages` | string[] | Languages this applies to: specific language keys or `all` |
| `check_command` | string | Shell command that returns 0 if the tool is installed |
| `install` | object | Install commands keyed by method: `darwin_brew`, `linux_apt`, `linux_dnf`, `linux_pip`, `npm`, `manual`. The resolver selects the first matching key for the current OS and available package managers (e.g., on macOS with Homebrew it uses `darwin_brew`; on Linux with apt it uses `linux_apt`). Falls back to `manual` if no auto-install key matches. |
| `auto_installable` | boolean | Whether the resolver can install this non-interactively |
| `substitutable` | boolean | Whether the user can swap this for an alternative |
| `substitution_category` | string | Human-readable category name shown during walkthrough (groups tools for substitution) |

### Resolution Rules

The resolver loads `common.json` plus the platform-specific file (e.g., `mobile.json`) and filters:

1. **dev_os** — remove tools that can't run on this machine
2. **track** — remove tools not needed for this project track
3. **phase** — tools for phases > current phase go to the "deferred" bucket
4. **language** — remove language-specific tools that don't match (tools with `"languages": ["all"]` always pass)
5. **platforms** — tools with `"platforms": ["all"]` always pass; otherwise must match

---

## 2. Resolver Script

### Location

`scripts/resolve-tools.sh`

### Interface

```bash
scripts/resolve-tools.sh \
  --dev-os darwin \
  --platform mobile \
  --language typescript \
  --track standard \
  --phase 2 \
  --matrix-dir templates/tool-matrix \
  --tool-prefs .claude/tool-preferences.json  # optional, for re-runs
```

All arguments are required except `--tool-prefs`.

### Logic

1. Load `common.json` + `<platform>.json` from `--matrix-dir`
2. Apply filters (dev_os, track, phase, language, platforms)
3. If `--tool-prefs` exists, apply user substitutions (replace default tools with user's picks) and add freeform entries
4. For each remaining tool, run `check_command` to determine installed/missing status
5. Categorize into four output buckets

### Output (JSON to stdout)

```json
{
  "auto_install": [
    {
      "name": "Semgrep",
      "category": "SAST Scanner",
      "install_cmd": "brew install semgrep",
      "required": true
    }
  ],
  "manual_install": [
    {
      "name": "Xcode Command Line Tools",
      "category": "Build Tools",
      "instructions": "xcode-select --install",
      "required": true
    }
  ],
  "already_installed": [
    {
      "name": "Git",
      "category": "Version Control",
      "version": "2.44.0"
    }
  ],
  "deferred": [
    {
      "name": "Playwright",
      "category": "E2E Testing",
      "phase": 3,
      "reason": "Needed at Phase 3 gate"
    }
  ]
}
```

### Bucket Definitions

| Bucket | Meaning |
|---|---|
| `auto_install` | Missing, can be installed non-interactively by the script |
| `manual_install` | Missing, requires user action (IDE installs, account signups, code signing certs) |
| `already_installed` | Present on the system, version captured where possible |
| `deferred` | Not needed yet based on current phase — shown for awareness, installed at future phase gate |

### Idempotency

The resolver is safe to re-run. It reads current system state each time and merges with `tool-preferences.json` rather than overwriting. Subsequent runs (phase gates, track upgrades) append to the `installed` record.

---

## 3. User Preferences File

### Location

`.claude/tool-preferences.json` (per-project, version-controlled)

### Schema

```json
{
  "schema_version": "1.0",
  "resolved_at": "2026-04-03",
  "context": {
    "dev_os": "darwin",
    "platform": "mobile",
    "language": "typescript",
    "track": "standard"
  },
  "substitutions": {
    "SAST Scanner": {
      "default": "Semgrep",
      "selected": "SonarQube",
      "check_command": "command -v sonar-scanner",
      "reason": "Team already uses SonarCloud"
    }
  },
  "additions": [
    {
      "name": "Biome",
      "category": "Linter/Formatter",
      "check_command": "command -v biome",
      "description": "All-in-one linter and formatter replacing ESLint + Prettier"
    }
  ],
  "skipped": [
    {
      "name": "Qdrant MCP",
      "category": "MCP Server",
      "reason": "Using project-level memory files instead"
    }
  ],
  "installed": {
    "phase_0": ["Git", "Node.js", "jq"],
    "phase_1": ["Semgrep", "gitleaks", "Snyk", "Claude Code", "Superpowers", "Context7 MCP"],
    "phase_2": ["EAS CLI", "Xcode Command Line Tools"]
  }
}
```

### Field Definitions

| Field | Description |
|---|---|
| `schema_version` | For future migrations |
| `resolved_at` | Date of last resolution |
| `context` | The project context used for resolution |
| `substitutions` | User-selected alternatives to default tools, keyed by substitution_category |
| `additions` | Freeform tools the user added that aren't in the matrix |
| `skipped` | Tools the user explicitly declined — resolver won't re-prompt on subsequent runs |
| `installed` | What was installed at each phase, updated by each resolver run |

### Merge Behavior

On subsequent runs (phase gates, track upgrades):
- `substitutions`, `additions`, `skipped` are preserved unless the user changes them
- `installed` is appended to (new phase keys added, existing keys not overwritten)
- `resolved_at` is updated
- `context.track` is updated on track upgrade

---

## 4. Init UX Flow

### Current Flow (replaced)

```
check_prerequisites → collect_project_info → install_tools → install_language_runtime → create_project
```

### New Flow

```
check_prerequisites → collect_project_info → resolve_and_install_tools → create_project
```

The `install_tools()` and `install_language_runtime()` functions are replaced by a single `resolve_and_install_tools()` that calls the resolver.

### Step-by-Step

**Step 1: Resolve.** Call `resolve-tools.sh` with collected project context. Receive the four-bucket JSON output.

**Step 2: Display.** Show the installation plan in a grouped format:

```
┌──────────────────────────────────────────────────────────┐
│  Tool Installation Plan (macOS / mobile / typescript)     │
├──────────────────────────────────────────────────────────┤
│  Already installed                                        │
│    Git 2.44.0, Node.js 22.1.0, jq 1.7.1                 │
│                                                           │
│  Will auto-install                                        │
│    Semgrep (SAST Scanner)                                 │
│    gitleaks (Secret Detection)                            │
│    Snyk CLI (Dependency Scanning)                         │
│    EAS CLI (Mobile Build Tools)                           │
│    Superpowers (Claude Plugin)                            │
│                                                           │
│  Requires manual setup                                    │
│    Xcode Command Line Tools — xcode-select --install      │
│    Apple Developer Program — developer.apple.com          │
│                                                           │
│  Deferred (installed at later phases)                     │
│    Phase 3: Playwright (E2E Testing)                      │
│    Phase 3: license-checker (License Compliance)          │
└──────────────────────────────────────────────────────────┘
```

**Step 3: Confirm.**

```
Proceed with this plan? [Y/n]
```

- **Y** — auto-install everything in the `auto_install` bucket, display manual install instructions, write `tool-preferences.json`
- **N** — present second prompt:

```
How would you like to configure tools?
  1. Guided walkthrough (step through each category)
  2. Edit .claude/tool-preferences.json manually
```

**Walkthrough path:** For each substitution_category with `substitutable: true`:

```
SAST Scanner:
  1. Semgrep (recommended)
  2. Other (enter name and check command)
  3. Skip
Select [1-3]:
```

After walkthrough, re-resolve and re-display for final confirmation.

**Manual edit path:** Write defaults to `tool-preferences.json`, print the file path and instructions, wait for user to confirm when done, re-resolve.

**Step 4: Install.** Execute install commands for the `auto_install` bucket. Display manual instructions for the `manual_install` bucket. Write results to `tool-preferences.json`.

### Superpowers Plugin

Promoted from "warn if missing" to the `auto_install` bucket in `common.json`. Install command: `claude plugins add superpowers`. Offered every time if not detected, same as Development Guardrails.

---

## 5. Phase Gate Integration

`scripts/check-phase-gate.sh` already runs at phase transitions. The change:

When checking a gate that transitions to a new phase (e.g., Phase 2 → 3), the gate script:

1. Calls `resolve-tools.sh --phase <target_phase>` with the project's context
2. If any `required` tools are in the `auto_install` or `manual_install` buckets (i.e., missing), the gate blocks
3. Presents the same install plan display as init
4. User confirms → tools install → gate passes
5. `tool-preferences.json` is updated with the newly installed tools

Optional tools that are missing generate warnings but don't block the gate.

---

## 6. Track Upgrade Integration

When a project upgrades tracks (e.g., light → standard, POC → production):

1. The upgrade process updates `context.track` in `tool-preferences.json`
2. Calls `resolve-tools.sh` with the new track and current phase
3. The resolver surfaces tools that the new track requires but the old track didn't
4. Same install plan display and confirmation flow as init
5. `tool-preferences.json` is updated

This ensures a POC that never needed Phase 4 release tooling gets those tools surfaced when it upgrades to a production track.

---

## 7. Intake Summary

After tool resolution and installation, init appends a "Tooling Configuration" section to `PROJECT_INTAKE.md`:

```markdown
## Tooling Configuration

**Resolved for:** macOS / mobile / typescript / standard track

### Installed
| Tool | Category | Version |
|---|---|---|
| Git | Version Control | 2.44.0 |
| Semgrep | SAST Scanner | 1.67.0 |
| gitleaks | Secret Detection | 8.18.2 |
| EAS CLI | Mobile Build Tools | 9.1.0 |
| Superpowers | Claude Plugin | 5.0.7 |

### Manual Setup Required
| Tool | Category | Instructions |
|---|---|---|
| Xcode Command Line Tools | Build Tools | `xcode-select --install` |
| Apple Developer Program | Code Signing | developer.apple.com ($99/yr) |

### Deferred (Phase 3+)
| Tool | Phase | Category |
|---|---|---|
| Playwright | 3 | E2E Testing |
| license-checker | 3 | License Compliance |

### Custom Substitutions
| Category | Default | Selected | Reason |
|---|---|---|---|
| SAST Scanner | Semgrep | SonarQube | Team uses SonarCloud |

### Additional Tools
| Tool | Category | Description |
|---|---|---|
| Biome | Linter/Formatter | All-in-one replacing ESLint + Prettier |

> Full machine-readable config: `.claude/tool-preferences.json`
```

Sections with no entries are omitted (e.g., if no substitutions, that table doesn't appear).

Claude reads this during Phase 1 to understand the available tooling without parsing JSON.

---

## 8. What Does NOT Change

- **Phase 1 prerequisites check** — Git, Node.js, jq, Docker, GPG checks remain as-is (these are universal dev machine prerequisites, not project-specific tools)
- **Development Guardrails installation** — stays in `create_project()`, separate from the tool matrix
- **Project creation flow** — copy docs, generate CLAUDE.md, generate pipelines, etc. are unchanged
- **Intake suggestion files** — `templates/intake-suggestions/*.json` are unrelated and unchanged

---

## 9. File Inventory

### New Files

| File | Purpose |
|---|---|
| `templates/tool-matrix/common.json` | Universal tool definitions |
| `templates/tool-matrix/web.json` | Web platform tool definitions |
| `templates/tool-matrix/mobile.json` | Mobile platform tool definitions |
| `templates/tool-matrix/desktop.json` | Desktop platform tool definitions |
| `scripts/resolve-tools.sh` | Matrix resolver script |

### Modified Files

| File | Change |
|---|---|
| `init.sh` | Replace `install_tools()` and `install_language_runtime()` with resolver-based `resolve_and_install_tools()` |
| `scripts/check-phase-gate.sh` | Add resolver call at phase transitions for deferred tools |
| `templates/project-intake.md` | Add Tooling Configuration section placeholder |

### Generated Per-Project Files

| File | Purpose |
|---|---|
| `.claude/tool-preferences.json` | Machine-readable tool state and user preferences |
| `PROJECT_INTAKE.md` (Tooling section) | Human-readable summary for Claude |

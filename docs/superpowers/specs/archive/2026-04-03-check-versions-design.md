# Session-Start Version Check — Design Spec

## Date: 2026-04-03

## Problem

The Solo Orchestrator has no mechanism to check whether external tools, plugins, and MCP servers are up to date at the start of a development session. `check-updates.sh` only compares framework documents against upstream and must be run manually. A developer could spend hours building with an outdated Semgrep that misses known vulnerabilities, an old Snyk that has stale CVE data, or a Development Guardrails version missing critical hooks.

## Solution

A fast `scripts/check-versions.sh` that runs at every session start (via CLAUDE.md instruction), checks all tools against minimum version requirements and latest available versions, warns on below-minimum tools, and offers interactive update with user approval.

## Architecture

The script reads `min_version` and `latest_check` fields from the existing tool matrix JSON files. It runs installed version commands (local, always works), then attempts latest version lookups (network, skips gracefully if offline). Results are presented in a grouped report with an interactive update prompt. The user decides what to update — the script never auto-updates.

---

## 1. Script Interface

### Location

`scripts/check-versions.sh`

### Usage

```bash
scripts/check-versions.sh    # Full check (minimum + latest + update prompt)
scripts/check-versions.sh --help
```

### Exit Codes

| Code | Meaning |
|---|---|
| 0 | All tools meet minimum requirements |
| 1 | One or more tools below minimum version |

---

## 2. Output Format

```
Solo Orchestrator — Version Check

── Core Tools ──
  [OK] Claude Code: 2.1.91 (min: 2.0.0) — up to date
  [OK] Node.js: 22.1.0 (min: 18.17.0) — up to date
  [OK] jq: 1.7.1 (min: 1.6) — up to date

── Security Tools ──
  [OK] Semgrep: 1.157.0 (min: 1.150.0) — 1.160.0 available
  [OK] gitleaks: 8.30.1 (min: 8.18.0) — up to date
  [WARN] Snyk: 1.1200.0 (min: 1.1290.0) — BELOW MINIMUM — 1.1303.0 available
         ⚠ Continuing with outdated Snyk may miss known vulnerabilities.

── Plugins & MCP ──
  [OK] Superpowers: installed
  [OK] Context7 MCP: configured — update available
  [OK] Qdrant MCP: configured

── Framework ──
  [OK] Development Guardrails: 4.0.0 (min: 4.0.0) — up to date

── Summary ──
  ✓ 9 up to date
  ⬆ 2 updates available (Semgrep, Context7 MCP)
  ⚠ 1 below minimum (Snyk) — update recommended before continuing

Updates available:
  1. Semgrep 1.157.0 → 1.160.0
  2. Context7 MCP → latest
  3. Snyk 1.1200.0 → 1.1303.0 (BELOW MINIMUM)

Update options:
  a) Update all (1, 2, 3)
  b) Select which to update (enter numbers: e.g., 1,3)
  c) Skip for now
```

### Offline Behavior

- Minimum version check always runs (local — no network needed)
- Latest version check skipped with note: `[INFO] Network unavailable — latest version check skipped`
- Below-minimum warnings still shown with recommendation not to continue
- Update prompt still shown for below-minimum tools (update command provided even if latest version unknown)

---

## 3. Tool Matrix Schema Additions

Two new fields added to each tool entry in `templates/tool-matrix/*.json`:

```json
{
  "name": "Semgrep",
  "min_version": "1.50.0",
  "latest_check": {
    "method": "pip",
    "package": "semgrep"
  },
  ...existing fields...
}
```

### `min_version`

- String: semantic version (e.g., `"1.50.0"`, `"18.17.0"`, `"8.18.0"`)
- `null`: no minimum version check (tool is presence-only, e.g., Superpowers, Qdrant MCP)

### `latest_check`

- Object with `method` and `package` keys
- `null`: no latest version lookup (presence-only tools)

### Latest Check Methods

| Method | How It Works | Used By |
|---|---|---|
| `npm` | `npm view <package> version 2>/dev/null` | Claude Code, Snyk, Context7 MCP |
| `github_release` | `curl -s https://api.github.com/repos/<package>/releases/latest` (parse `tag_name`) | gitleaks |
| `pip` | `pip3 install <package>== 2>&1` (parse available versions) or PyPI JSON API | Semgrep |
| `brew` | `brew info --json=v2 <package> 2>/dev/null` (parse `versions.stable`) | jq, GPG |
| `git_tag` | `git ls-remote --tags <package> 2>/dev/null` (parse latest tag) | Development Guardrails |
| `none` | No lookup — just check installed/configured | Superpowers, Qdrant MCP, language runtimes |

---

## 4. Version Comparison Logic

The script compares semantic versions using a bash function that splits on `.` and compares major, minor, patch numerically. This handles:
- `1.157.0` vs `1.160.0` (minor version)
- `22.1.0` vs `18.17.0` (major version)
- `8.30.1` vs `8.18.0` (minor + patch)

For non-semver versions (e.g., `jq-1.7.1-apple`), the script strips prefixes/suffixes to extract the numeric version before comparing.

---

## 5. Interactive Update Prompt

When updates are available, the script presents:

```
Updates available:
  1. Semgrep 1.157.0 → 1.160.0
  2. Context7 MCP → latest
  3. Snyk 1.1200.0 → 1.1303.0 (BELOW MINIMUM)

Update options:
  a) Update all (1, 2, 3)
  b) Select which to update (enter numbers: e.g., 1,3)
  c) Skip for now
```

| Choice | Behavior |
|---|---|
| `a` | Runs update command for each tool sequentially, reports success/failure per tool |
| `b` | User enters comma-separated numbers, script runs only those update commands |
| `c` | Prints manual commands for reference, proceeds without updating |

Below-minimum tools are highlighted in the list so the user knows which matter most.

After updates complete, the script re-checks the updated tools to verify the new version meets minimum.

If not running in a terminal (piped/scripted), the update prompt is skipped and manual commands are printed instead.

---

## 6. Session Start Integration

### CLAUDE.md Template

Add to `templates/generated/claude-md.tmpl`, as the first item under Operating Instructions:

```markdown
### Session Start
At the start of every new session, before any other work:
1. Run `scripts/check-versions.sh` and report the results to the Orchestrator
2. If any tools are below minimum version, warn the Orchestrator and recommend updating before continuing
3. If updates are available, ask the Orchestrator if they want to update now
4. Do NOT proceed with Phase 2+ work if any required security tool (Semgrep, gitleaks, Snyk) is below minimum — recommend updating first
5. Do NOT auto-update anything — always ask first
```

### resume.sh Integration

`scripts/resume.sh` includes version check output in its session resume prompt so the user sees version status alongside project state.

---

## 7. File Inventory

### New Files

| File | Purpose |
|---|---|
| `scripts/check-versions.sh` | Session-start version checker with interactive update prompt |

### Modified Files

| File | Change |
|---|---|
| `templates/tool-matrix/common.json` | Add `min_version` and `latest_check` to all tool entries |
| `templates/tool-matrix/web.json` | Add `min_version` and `latest_check` to all tool entries |
| `templates/tool-matrix/mobile.json` | Add `min_version` and `latest_check` to all tool entries |
| `templates/tool-matrix/desktop.json` | Add `min_version` and `latest_check` to all tool entries |
| `templates/generated/claude-md.tmpl` | Add Session Start instruction block |
| `scripts/resume.sh` | Include version check in session resume output |
| `init.sh` | Copy check-versions.sh to created projects, add to chmod list |

---

## 8. What Does NOT Change

- **`scripts/check-updates.sh`** — still handles framework document comparison against upstream (heavier operation, run periodically)
- **`scripts/resolve-tools.sh`** — still handles tool installation resolution (used by init and phase gates)
- **`scripts/verify-install.sh`** — still handles post-install/post-upgrade verification
- **Tool matrix structure** — existing fields unchanged, only two new optional fields added

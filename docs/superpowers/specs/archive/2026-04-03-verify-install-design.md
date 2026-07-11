# Installation Verification & Remediation — Design Spec

## Date: 2026-04-03

## Problem

init.sh detects failures during installation (tool installs, framework clone, file copies, MCP registration) but only warns and moves on. The `health_check()` function at the end detects missing files and tools but offers no remediation. Users are left to manually figure out what went wrong and how to fix it.

With the addition of upgrade paths (track upgrades, POC → production), verification needs to be accessible at any point in the project lifecycle — not just at init time.

## Solution

A standalone `scripts/verify-install.sh` that detects all installation issues, categorizes them as auto-fixable or manual-only, and offers batch remediation with a single confirmation prompt.

## Architecture

Categorized check functions detect issues into three arrays (passed, fixable, manual). After all checks run, the script presents a grouped report and offers to auto-fix all fixable issues in one batch. After remediation, it re-verifies to confirm fixes worked.

---

## 1. Script Interface

### Location

`scripts/verify-install.sh`

### Modes

```bash
scripts/verify-install.sh              # Full verify + offer remediation (interactive)
scripts/verify-install.sh --check-only # Verify only, no remediation (for CI/scripted checks)
scripts/verify-install.sh --auto-fix   # Verify + fix without prompting (for init.sh/upgrade calls)
scripts/verify-install.sh --help       # Usage information
```

### Exit Codes

| Code | Meaning |
|---|---|
| 0 | All checks pass (or all failures remediated successfully) |
| 1 | Failures remain after remediation attempt (or after check-only) |

### Orchestrator Source Path

The script needs to know where the orchestrator source directory is (to re-copy files during remediation). This is stored in `.claude/orchestrator-source.json`:

```json
{"source_dir": "/path/to/solo-orchestrator"}
```

Written once by init.sh during project creation. If the file is missing or the path is invalid, the script falls back to:
1. `~/.solo-orchestrator` (conventional location)
2. Prompting the user (interactive mode only)
3. Skipping file-copy remediations (check-only/auto-fix modes)

---

## 2. Check and Remediation Flow

### Phase 1: DETECT

Run all check functions in order. Each check registers its result by calling one of:
- `register_pass "Check description"` — adds to passed array
- `register_fixable "Check description" "fix_function_name"` — adds to fixable array with a paired remediation function
- `register_manual "Check description" "Instructions for user"` — adds to manual array

### Phase 2: REPORT

Display grouped results:

```
┌──────────────────────────────────────────────┐
│  Installation Verification Report            │
├──────────────────────────────────────────────┤
│  ✓ Passed: 24                                │
│  ⚡ Auto-fixable: 3                          │
│  ⚠ Manual action required: 1                │
├──────────────────────────────────────────────┤
│  AUTO-FIXABLE:                               │
│    • builders-guide.md outdated              │
│    • Semgrep not installed                   │
│    • Pre-commit hook missing                 │
│                                              │
│  MANUAL:                                     │
│    • Xcode Command Line Tools                │
│      → xcode-select --install                │
└──────────────────────────────────────────────┘
```

### Phase 3: REMEDIATE

- If `--check-only`: skip, exit with status based on results
- If fixable array is non-empty:
  - Interactive mode: `"Auto-fix 3 issues? [Y/n]"`
  - `--auto-fix` mode: proceed without prompting
  - Execute each fix function, report success/failure per item
  - Re-run the specific failed checks to verify each fix worked

### Phase 4: FINAL STATUS

Re-display summary with updated counts after remediation. Exit 0 if everything passes, 1 if anything remains broken.

---

## 3. Check Categories

### 3.1 Project Structure

| Check | Auto-Fix Action |
|---|---|
| CLAUDE.md exists | Re-generate (requires project context from phase-state.json) |
| PROJECT_INTAKE.md exists | Re-copy from orchestrator template |
| APPROVAL_LOG.md exists | Re-generate (requires deployment type from tool-preferences.json) |
| .gitignore exists | Re-generate (requires platform and language context) |
| .claude/phase-state.json exists | Re-generate with defaults (phase 0) |
| .claude/tool-preferences.json exists | Re-run resolver and write |
| docs/framework/ files present (builders-guide.md, governance-framework.md, executive-review.md, cli-setup-addendum.md, user-guide.md, security-scan-guide.md) | Re-copy from orchestrator source |
| Platform module for selected platform copied | Re-copy from orchestrator source |
| CI pipeline (.github/workflows/ci.yml) exists | Re-copy from orchestrator CI templates |
| Release pipeline (.github/workflows/release.yml) exists (if platform has one) | Re-copy from orchestrator release templates |
| Intake suggestions copied (templates/intake-suggestions/) | Re-copy from orchestrator source |
| Tool matrix files copied (templates/tool-matrix/) | Re-copy from orchestrator source |

### 3.2 Scripts

| Check | Auto-Fix Action |
|---|---|
| validate.sh present and executable | Re-copy from orchestrator, chmod +x |
| check-phase-gate.sh present and executable | Re-copy from orchestrator, chmod +x |
| resume.sh present and executable | Re-copy from orchestrator, chmod +x |
| intake-wizard.sh present and executable | Re-copy from orchestrator, chmod +x |
| resolve-tools.sh present and executable | Re-copy from orchestrator, chmod +x |
| upgrade-project.sh present and executable | Re-copy from orchestrator, chmod +x |
| Tool matrix JSON files valid (jq parse) | Re-copy from orchestrator source |

### 3.3 Git

| Check | Auto-Fix Action |
|---|---|
| Git repository initialized (.git exists) | `git init` |
| Pre-commit hook installed and executable | Re-install (re-generate from init.sh logic) |
| At least one commit exists | Manual — needs review |

### 3.4 Development Guardrails for Claude Code

| Check | Auto-Fix Action |
|---|---|
| Global clone at ~/.claude-dev-framework | `git clone --depth 1` from GitHub |
| Per-project manifest (.claude/manifest.json) | Re-run framework init.sh from global clone |

### 3.5 Tools (via Resolver)

| Check | Auto-Fix Action |
|---|---|
| All required Phase 0-2 tools installed | Re-run install command from tool matrix |
| Language runtime for selected language | Re-run install command from tool matrix |

The script calls `scripts/resolve-tools.sh` with the project context from `tool-preferences.json` and checks for required tools in the `auto_install` bucket (meaning they're missing but auto-installable).

### 3.6 Plugins & MCP Servers

| Check | Auto-Fix Action |
|---|---|
| Superpowers plugin installed | `claude plugins add superpowers` |
| Context7 MCP configured | `claude mcp add context7 -- npx -y @upstash/context7-mcp@latest` |
| Qdrant MCP configured | Manual — requires Docker + uv setup |

---

## 4. Reading Project Context

The script reads project context (platform, language, track, deployment) from multiple sources with fallbacks:

1. `.claude/tool-preferences.json` → `context.platform`, `context.language`, `context.track`
2. `.claude/phase-state.json` → `project` name
3. `CLAUDE.md` → grep for platform/track/language fields
4. If none available, the check functions that need context register as manual instead of fixable

---

## 5. Integration Points

### 5.1 init.sh

In `create_project()`, after generating all files and before the initial commit:
- Write `.claude/orchestrator-source.json` with `$SCRIPT_DIR`

In `main()`, replace the `health_check` call:
```bash
# Old:
health_check

# New:
bash "$PROJECT_DIR/scripts/verify-install.sh" --auto-fix || true
```

Remove the `health_check()` function entirely — verify-install.sh subsumes it.

Add `verify-install.sh` to the script copy list in `create_project()`.

### 5.2 upgrade-project.sh

At the end of each upgrade path, after committing changes:
```bash
if [ -x "scripts/verify-install.sh" ]; then
    bash scripts/verify-install.sh
fi
```

Interactive mode — the user may need to install new tools surfaced by the track upgrade.

### 5.3 Manual

User runs from the project directory at any time:
```bash
bash scripts/verify-install.sh
```

---

## 6. File Inventory

### New Files

| File | Purpose |
|---|---|
| `scripts/verify-install.sh` | Standalone verification + remediation script |

### Modified Files

| File | Change |
|---|---|
| `init.sh` | Write orchestrator-source.json, replace health_check() with verify-install.sh call, add to script copy list |
| `scripts/upgrade-project.sh` | Add verify-install.sh call after upgrade completes |

### Generated Per-Project Files

| File | Purpose |
|---|---|
| `.claude/orchestrator-source.json` | Stores path to orchestrator source for file re-copying |

---

## 7. What Does NOT Change

- **`scripts/validate.sh`** — checks framework compliance (different concern from installation correctness)
- **`scripts/resolve-tools.sh`** — verify-install.sh calls it, doesn't replace it
- **Prerequisites check in init.sh** — runs before project creation; verify-install.sh runs after
- **Tool matrix files** — read by verify-install.sh via the resolver, not modified

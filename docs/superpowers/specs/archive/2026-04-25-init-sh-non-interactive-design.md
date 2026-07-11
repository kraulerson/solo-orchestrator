# BL-016: init.sh Non-Interactive Mode — Design

**Spec date:** 2026-04-25
**Backlog item:** BL-016 (High / Debt — to be logged post-spec)
**Driver:** UAT 2026-04-25 finding U-A — `init.sh` has no scriptable mode; only `--dry-run` and `--help` flags exist. Confirmed by 8 of 13 UAT agents (highest-frequency finding in the sweep). Blocks UAT, CI, scripted onboarding, and AI-agent-driven project creation.

## 1. Problem

`init.sh` is the framework's entry point for creating new Solo Orchestrator projects. It runs ~15 interactive prompts (`prompt_input` / `prompt_choice` from `scripts/lib/helpers.sh`) covering project name, platform, track, deployment, governance mode, language, project directory, git host, visibility, remote URL, branch-protection attestation, plus dependency-installer prompts and a final confirmation. The interactive flow has been the framework's only entry path since v1.0.

UAT 2026-04-25 surfaced this as a critical blocker: agents had to drive `init.sh` via heredoc with canned answers, the heredoc was fragile (prompt order depends on Docker install state, host configuration, and language list), and one agent (12) hit an infinite-CPU `Invalid choice` loop when the heredoc under-fed `prompt_choice` (separately fixed in PR #18).

CI/automation/AI-orchestrator workflows need a deterministic, validated, fail-fast input mechanism. This spec adds `--non-interactive` mode to `init.sh` with explicit per-input flags and JSON config-file support.

## 2. Scope

**In scope:** see § 12 ("Scope boundaries") for the in-scope list.

**Out of scope:** YAML config support, cross-platform CI matrix, auto-install of missing dependencies in non-interactive mode, non-interactive mode for `intake-wizard.sh` / `upgrade-project.sh` / `verify-install.sh` (each logged as BL-017 / BL-018 / BL-019), config schema versioning, refactor of the existing interactive prompt flow.

## 3. Locked parameters

Settled during the brainstorming dialogue on 2026-04-25:

| Parameter | Decision | Source |
|---|---|---|
| Mode shape | **Strict non-interactive mode** — `--non-interactive` is a separate code path; the existing interactive flow is untouched | Q1 — A |
| Input mechanism | **CLI flags + JSON config file** (both supported) | Q2 — C |
| Required vs optional | **Conditional required** — project/platform/deployment/language always; gov-mode/remote-url/branch-protection-attested when context demands; rest have defaults | Q3 — C |
| Implementation structure | **New code path inside `main()`**; the interactive block is untouched | Approach A |
| Flag naming | `kebab-case-full` (matches existing scripts: `--upgrade-deployment`, `--to-production`) | Default |
| Precedence | Command-line flag > config file > default > error-if-required | Default |
| Config file format | **JSON** (jq is already a dep; matches existing state files: `phase-state.json`, `intake-progress.json`, `tool-preferences.json`, `process-state.json`) | Default |
| Validation timing | **Upfront** — all three validation passes complete before any file writes; `--validate-only` flag for smoke-testing | Default |
| Missing dependency handling | **Fail-fast** with clear error; non-interactive mode never auto-installs system packages | Default |

## 4. Architecture

```
init.sh main():
  parse flags
        │
        ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │ if --non-interactive:                                           │
  │   collect_inputs_non_interactive()  ← NEW                       │
  │     1. load --config FILE (if given) → CONFIG_VALUES dict       │
  │     2. for each input variable, value = flag || CONFIG_VALUES   │
  │        || default-if-defaulted || error-if-required             │
  │     3. validate context (gov-mode iff organizational, etc.)     │
  │     4. if --validate-only: print resolved config + exit 0       │
  │     5. assign all the input variables main() expects            │
  │        (PROJECT_NAME, PLATFORM, TRACK, DEPLOYMENT, GOV_MODE,    │
  │        LANGUAGE, PROJECT_DIR, GIT_HOST, VISIBILITY, ...)        │
  │ else:                                                           │
  │   [existing interactive prompt block — UNTOUCHED]               │
  │     prompt_input → PROJECT_NAME                                 │
  │     prompt_choice → PLATFORM                                    │
  │     ... (the existing 250+ lines of prompts)                    │
  └─────────────────────────────────────────────────────────────────┘
        │                                  │
        └──────────────┬───────────────────┘
                       │
                       ▼
                Both paths produce the same set of variables
                       │
                       ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │ rest of main(): create_project, install_deps,                   │
  │   create_and_protect_remote, verify_install, print_next_steps   │
  │   — UNCHANGED, consumes the variables produced by either path   │
  └─────────────────────────────────────────────────────────────────┘
```

**Unit boundaries:**

| Unit | Responsibility | Knows about | Doesn't know about |
|---|---|---|---|
| New `collect_inputs_non_interactive()` in init.sh | Parse `--config` JSON, merge with flags, validate per-context required, assign final variables. Exit 1 with clear message on any error. | JSON config schema, flag→variable mapping, context-required rules, defaults table. | The interactive prompt flow. |
| Existing interactive block | Prompts the user via `prompt_input` / `prompt_choice`. | Interactive UX. | Anything about flags or config. |
| `create_project()` and the rest of the post-input pipeline | Reads input variables, scaffolds files, installs CDF, configures remote. | All input variables produced by either path. | How those variables were obtained. |

**Variable-set as the natural boundary:** init.sh's existing `main()` is already structured around shared variables being set once, then consumed by downstream functions. Both paths produce the same variable set; downstream is unchanged.

**Two surgical changes outside the new function:**
1. `main()`'s flag-parser block (line 2542 onward) extends to recognize the new flags and the `NON_INTERACTIVE` mode boolean.
2. `create_and_protect_remote()` (line 1699) gets a 4-line change per host-related variable: check the new top-level variables (`GIT_HOST`, `VISIBILITY`, `REMOTE_URL`, `BRANCH_PROTECTION_ATTESTED`) BEFORE falling back to `intake-progress.json` or interactive prompts.

## 5. CLI surface

### 5.1 Flag list

```
init.sh [--dry-run] [--help] [--help-non-interactive]
        [--non-interactive]
        [--config FILE]
        [--validate-only]
        [--project NAME]
        [--description TEXT]
        [--platform {desktop|mobile|web|mcp_server}]
        [--track {light|standard|full}]
        [--deployment {personal|organizational}]
        [--gov-mode {production|sponsored_poc|private_poc}]
        [--language NAME]
        [--project-dir PATH]
        [--git-host {github|gitlab|bitbucket|other}]
        [--visibility {private|public}]
        [--remote-url URL]
        [--branch-protection-attested]
        [--allow-existing-dir]
```

### 5.2 Mode flags

| Flag | Effect |
|---|---|
| `--non-interactive` | Enables non-interactive mode. All required inputs must come from flags or `--config`. Without this flag, all input flags are ignored (the existing interactive flow runs). |
| `--config FILE` | Read JSON config from FILE. Only honored when `--non-interactive` is also set (otherwise warn + ignore + fall through to interactive). |
| `--validate-only` | Parse + validate inputs, print the resolved config as JSON to stdout, exit 0. No file writes, no scaffolding. Requires `--non-interactive`. |

### 5.3 Per-input flag conventions

- All input flags are kebab-case-full.
- `--branch-protection-attested` is a boolean flag (presence = `true`). All other input flags take a value.
- `--gov-mode` short form intentional (matches existing internal `gov_mode` variable; shortens the most-typed contextually-required flag).

### 5.4 Config file schema (JSON)

```json
{
  "project": "my-app",
  "description": "A web app for tracking widgets",
  "platform": "web",
  "track": "standard",
  "deployment": "personal",
  "gov_mode": null,
  "language": "typescript",
  "project_dir": "/Users/karl/Code/my-app",
  "git_host": "github",
  "visibility": "private",
  "remote_url": null,
  "branch_protection_attested": false,
  "allow_existing_dir": false
}
```

**Schema rules:**
- All fields optional. Missing field → use default-or-flag-or-error per the conditional-required rules.
- Field names use `snake_case` (matches existing framework state files).
- Unknown fields → warn + ignore (forward compat).
- Top-level type other than object → exit 1 with "config file must be a JSON object."
- File doesn't exist or isn't readable → exit 1 with "config file not found: PATH."
- File is not valid JSON → exit 1 with the `jq` error message.

### 5.5 Precedence

Command-line flag > config file > default > error-if-required.

Worked example:

```bash
echo '{"platform":"web","track":"standard","deployment":"personal","language":"typescript"}' > init.json

# Config supplies most; flags add what's missing:
./init.sh --non-interactive --config init.json --project my-app

# Flag overrides config:
./init.sh --non-interactive --config init.json --project my-app --track full
```

### 5.6 `--help` text

The existing `--help` block (line 2547) gets a second usage paragraph after the current "Usage" line:

```
Usage: ./init.sh [--dry-run] [--help]                                 (interactive)
       ./init.sh --non-interactive [--config FILE] [INPUT FLAGS...]   (scriptable)

Non-interactive mode (for CI, UAT, AI agents):
  Required (always):       --project --platform --deployment --language
  Required (conditional):  --gov-mode (when --deployment=organizational);
                           --remote-url (when --git-host=other);
                           --branch-protection-attested (when --git-host=other)
  Defaults:                --track standard, --git-host github,
                           --visibility private, --description "",
                           --project-dir "$HOME/Code/$PROJECT"
  See --help-non-interactive for the full schema and a JSON config example.
```

A new `--help-non-interactive` flag prints the full schema, defaults table, JSON example, and per-flag descriptions.

## 6. Validation logic

Validation runs in three passes, all before any file writes.

### 6.1 Pass 1 — Schema (per-input typing)

| Input | Validator |
|---|---|
| `project` | Non-empty. Regex `^[a-z][a-z0-9-]*$`. Else: "project name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens (got: 'X')." |
| `platform` | One of `desktop|mobile|web|mcp_server`. |
| `track` | One of `light|standard|full`. |
| `deployment` | One of `personal|organizational`. |
| `gov_mode` | One of `production|sponsored_poc|private_poc` OR null. (Required-or-not is Pass 2.) |
| `language` | Non-empty string. (Per-platform validity is Pass 2.) |
| `project_dir` | Absolute path OR resolves to one when expanded relative to cwd. Parent dir must exist or be creatable. |
| `git_host` | One of `github|gitlab|bitbucket|other`. |
| `visibility` | One of `private|public`. |
| `remote_url` | When present: must match `https://*` or `git@*`. (Required-or-not is Pass 2.) |
| `branch_protection_attested` | Boolean. |
| `allow_existing_dir` | Boolean. |

### 6.2 Pass 2 — Context-required validation

| Rule | Failure message |
|---|---|
| `gov_mode` required when `deployment=organizational` | "--gov-mode is required when --deployment=organizational. Choose: production, sponsored_poc, or private_poc." |
| `gov_mode` MUST be empty when `deployment=personal` | "--gov-mode is not valid for --deployment=personal (got: 'X'). Personal projects don't have a governance mode." |
| `language` validity for `platform` | Look up `templates/intake-suggestions/${platform}.json` (or `common.json`). If `language` isn't in the platform's allowed list, fail with the supported languages enumerated. |
| `remote_url` required when `git_host=other` | "--remote-url is required when --git-host=other (paste an HTTPS or SSH URL of an existing remote repo)." |
| `branch_protection_attested=true` required when `git_host=other` | "--branch-protection-attested is required when --git-host=other. Verify branch protection is configured on the remote, then re-run with this flag." |
| `visibility=private` enforced when `deployment=organizational` | If user explicitly set `--visibility=public` with `--deployment=organizational`, fail: "--visibility=public is not allowed for --deployment=organizational. Org-mode projects must be private." |
| `track=full` + `deployment=personal` warn-not-fail | Print warning to stderr; continue. Non-interactive mode treats explicit flags as confirmation. |

### 6.3 Pass 3 — Resource validation

| Check | Failure |
|---|---|
| Required tools present (git, jq, node, python3) | "missing required tool: git. Install via: <OS-specific command>. Non-interactive mode does not auto-install." |
| `project_dir` doesn't exist OR `--allow-existing-dir` is set | "project directory already exists: /path/to/dir. Pass --allow-existing-dir to use it anyway, or pick a different path." |
| `git_host` CLI tool present (when `git_host` ≠ `other`) | "missing required tool for git_host=github: gh. Install via: brew install gh." Skipped for `other` host. |

### 6.4 Error format

All validation errors share a uniform shape so machines and humans can parse:

```
[FAIL] init.sh non-interactive: <one-line summary>
  Reason: <specific cause>
  Action: <how to fix>
  Context: --flag1=value1 --flag2=value2 (the relevant flags)
```

Concrete example:

```
[FAIL] init.sh non-interactive: --gov-mode required when --deployment=organizational
  Reason: organizational projects must specify a governance mode.
  Action: re-run with one of: --gov-mode production, --gov-mode sponsored_poc, --gov-mode private_poc.
  Context: --deployment=organizational, --gov-mode=(unset)
```

### 6.5 `--validate-only`

When `--validate-only` is set:
- All three passes run.
- On success: print the resolved config (post-merge, post-default) as JSON to stdout, exit 0.
- On failure: same error as a real run, exit 1.
- No file writes anywhere.

Output on success:

```json
{
  "_validated": true,
  "_resolved_at": "2026-04-25T20:30:00Z",
  "project": "my-app",
  "platform": "web",
  "track": "standard",
  "deployment": "personal",
  "gov_mode": null,
  "language": "typescript",
  "project_dir": "/Users/karl/Code/my-app",
  "git_host": "github",
  "visibility": "private",
  "remote_url": null,
  "branch_protection_attested": false,
  "allow_existing_dir": false,
  "description": ""
}
```

Lets CI/agents pipe `init.sh --non-interactive --validate-only ... | jq` to confirm what they're about to install before committing.

## 7. Defaults table & input variable map

| Input | CLI flag | Config key | Required | Default | Sets variable | Used at line(s) |
|---|---|---|---|---|---|---|
| Project name | `--project` | `project` | always | — | `PROJECT_NAME` | 270, throughout |
| Description | `--description` | `description` | no | `""` | `PROJECT_DESCRIPTION` | 273 |
| Platform | `--platform` | `platform` | always | — | `PLATFORM` | 302 |
| Track | `--track` | `track` | no | `standard` | `TRACK` | 311, 330, 372 |
| Deployment | `--deployment` | `deployment` | always | — | `DEPLOYMENT` | 319 |
| Gov mode | `--gov-mode` | `gov_mode` | when `deployment=organizational` | — (must be empty when personal) | `GOV_MODE` (new top-level; existing code derives `POC_MODE` at 971) | 350, 971 |
| Language | `--language` | `language` | always | — | `LANGUAGE` | 419, 449 |
| Project directory | `--project-dir` | `project_dir` | no | `$HOME/Code/$PROJECT_NAME` (matches existing logic at 475) | `PROJECT_DIR` | 475 |
| Git host | `--git-host` | `git_host` | no | `github` | `GIT_HOST` (new top-level; consumed in `create_and_protect_remote`) | 1720 |
| Visibility | `--visibility` | `visibility` | no | `private` (forced to private when `deployment=organizational`) | `VISIBILITY` (new top-level) | 1721 |
| Remote URL | `--remote-url` | `remote_url` | when `git_host=other` | — | `REMOTE_URL` (new top-level) | 1723 |
| Branch protection attested | `--branch-protection-attested` | `branch_protection_attested` | when `git_host=other` (must be true) | `false` for non-other hosts | `BRANCH_PROTECTION_ATTESTED` (new top-level) | 1736 |
| Allow existing dir | `--allow-existing-dir` | `allow_existing_dir` | no | `false` | `ALLOW_EXISTING_DIR` (new top-level; consumed in new dir-exists validation pass-3 check) | new |

### 7.1 Variable propagation strategy

The non-interactive collection function exports the same variables the interactive flow sets (PROJECT_NAME, PROJECT_DESCRIPTION, PLATFORM, TRACK, DEPLOYMENT, LANGUAGE, PROJECT_DIR), plus the new top-level variables (GOV_MODE, GIT_HOST, VISIBILITY, REMOTE_URL, BRANCH_PROTECTION_ATTESTED, ALLOW_EXISTING_DIR).

`create_and_protect_remote()` (line 1699) gets a 4-line change per host-related variable to check the new top-level FIRST:

```bash
# replace lines 1701-1707 with:
if [ -n "${GIT_HOST:-}" ]; then
  host="$GIT_HOST"
elif [ -f .claude/intake-progress.json ]; then
  host=$(jq -r '.answers.git_host // empty' .claude/intake-progress.json 2>/dev/null || echo "")
fi
[ -z "$host" ] && host=$(prompt_choice "Git host:" "github" "gitlab" "bitbucket" "other")
```

Same pattern for `visibility`, `remote_url`, `attest`. The fallback to interactive prompts is preserved (only reached in interactive mode since non-interactive mode sets all of these explicitly during validation).

### 7.2 Behavioral prompts in non-interactive mode (no flag, fixed behavior)

| Existing prompt | Behavior in non-interactive mode |
|---|---|
| Line 488 "Continue? [Y/n]" final confirmation | Skip; assume yes. |
| Line 328 "Continue with Full track? [y/N]" (Full+personal warning) | Skip; print warning to stderr, continue. |
| Line 492 "What would you like to do?" if dir exists | Replaced by validation-pass-3 check: fail unless `--allow-existing-dir` is set. |
| Line 653 "Proceed with this plan?" tool-resolution confirmation | Skip; assume yes. |
| Line 658 "What would you like to do?" tool config menu | Skip entirely; use auto-resolved tools without manual customization. |
| Line 877 per-category tool choice (Accept/Replace/Add custom/Skip) | Skip; use the suggested tool. |
| Line 888-889 custom tool name + check | Never reached (preceded by skipped line 877). |
| Lines 49-181 dependency-installer prompts | Replaced by Pass-3 fail-fast on missing tool. |

Existing variables that the interactive flow sets but non-interactive doesn't need to override (`dev_os`, `available_platforms`, `available_languages`, etc.) are computed FROM the user-supplied inputs, not asked for separately. No flag needed.

## 8. Test strategy

### 8.1 Layer 1 — unit tests (new file: `tests/test-init-non-interactive.sh`)

26 unit tests for the collection function in isolation. Same pattern as `tests/test-pending-approval.sh` — per-test tempdir setup, source the function from init.sh, assert exit codes and resolved values.

| # | Test |
|---|---|
| N1 | All required flags present → exit 0, resolved config has defaults filled |
| N2 | Missing `--project` → exit 1, error names `--project` |
| N3 | Missing `--platform` → exit 1, error names `--platform` |
| N4 | Missing `--deployment` → exit 1, error names `--deployment` |
| N5 | Missing `--language` → exit 1, error names `--language` |
| N6 | `--deployment=organizational` without `--gov-mode` → exit 1 |
| N7 | `--deployment=personal` with `--gov-mode` → exit 1 |
| N8 | `--git-host=other` without `--remote-url` → exit 1 |
| N9 | `--git-host=other` without `--branch-protection-attested` → exit 1 |
| N10 | `--deployment=organizational` + `--visibility=public` → exit 1 (org forces private) |
| N11 | Invalid `--platform=foo` → exit 1, lists valid platforms |
| N12 | Invalid project name `--project Foo!` → exit 1, explains naming rule |
| N13 | Invalid `--language` for platform → exit 1, lists supported languages |
| N14 | `--config FILE` provides everything → exit 0, resolved matches JSON |
| N15 | `--config FILE` + flag override → exit 0, flag wins |
| N16 | `--config FILE` not found → exit 1 |
| N17 | `--config FILE` malformed JSON → exit 1 with jq parse error |
| N18 | `--config FILE` unknown field → warn, ignore, continue |
| N19 | `--config FILE` without `--non-interactive` → warn, ignore, fall through |
| N20 | `--validate-only` success → exit 0, JSON to stdout |
| N21 | `--validate-only` failure → exit 1, same error as real run |
| N22 | `--allow-existing-dir` allows existing dir → exit 0 |
| N23 | dir exists, `--allow-existing-dir` not set → exit 1, names the flag |
| N24 | Default `--track standard` applied when not specified |
| N25 | Defaults `--git-host github` + `--visibility private` applied when not specified |
| N26 | Default `--project-dir` derives from project name |

### 8.2 Layer 2 — integration tests (extension to `tests/edge-cases-scripts.sh`, E48–E55)

| # | Test |
|---|---|
| E48 | Full non-interactive run: web + personal + standard + typescript → project skeleton at `$TEST_DIR/e48` |
| E49 | E48 with `--validate-only` added → exit 0, JSON to stdout, project NOT created |
| E50 | Mobile + organizational + sponsored_poc + kotlin → exit 0, JSON has gov_mode=sponsored_poc + visibility=private (org→private force). Companion E50b: same shape with `--gov-mode=private_poc` → exit 1 per baseline §2.5 (`organizational/private_poc` is not a valid tier — see `docs/governance-framework.md:257`; original 2026-04-25 spec row used private_poc but that combination is rejected, so the test was reconciled to the actual contract in PR closing BL-039). |
| E51 | Web + organizational + production + git-host=other + fake remote-url + attested → exit 0 with soft-fail remediation (per UAT C-fix B) |
| E52 | `--config $TEST_DIR/cfg.json --project-dir $TEST_DIR/e52` (config has all required) → project created |
| E53 | `--config $TEST_DIR/cfg.json --track full` (config has track=light, flag overrides) → phase-state shows track=full |
| E54 | `--non-interactive` with no required flags → exit 1 with all missing flags listed |
| E55 | Skip `--project-dir`, default to `$HOME/Code/$PROJECT`, dir exists → exit 1; add `--allow-existing-dir` → exit 0 |

### 8.3 Layer 3 — re-test sweep on UAT configs

After implementation, dispatch a focused re-test of the configs that originally caught init-related bugs:
- Base flow: agents 1, 9, 14
- Upgrade flow: agents 49, 77, 78, 80, 81, 82

8-10 agents, sequential or batches of 3. Confirms:
- Init.sh non-interactive mode works for every scenario/platform/track combo.
- The `prompt_choice` EOF guard (PR #18) doesn't fire (no prompts to feed).
- `create_and_protect_remote` failure (UAT C-fix B) still gracefully soft-fails.
- Downstream gates (BL-006, BL-015, phase-state writes) work as expected post-init.

### 8.4 Out-of-scope tests

- Performance/timing tests.
- Cross-platform CI matrix.
- `--config` YAML support.
- Concurrent invocations.

## 9. Documentation

### 9.1 `docs/builders-guide.md` — new subsection

Insert a new subsection after Phase 0 content (before "Structured Decision Points: The Pending-Approval Sentinel"):

```markdown
### Scripted / Non-Interactive Project Initialization

For CI pipelines, automated UAT, or AI-orchestrator-driven project creation, `init.sh` supports a `--non-interactive` mode with explicit per-input flags and JSON config-file support.

**Minimal invocation:**
\`\`\`bash
./init.sh --non-interactive \
  --project my-app \
  --platform web \
  --deployment personal \
  --language typescript
\`\`\`

**With config file:**
\`\`\`bash
echo '{"platform":"web","track":"standard","deployment":"personal","language":"typescript"}' > init.json
./init.sh --non-interactive --config init.json --project my-app
\`\`\`

**Validate without scaffolding:**
\`\`\`bash
./init.sh --non-interactive --config init.json --project my-app --validate-only | jq
\`\`\`

See `init.sh --help-non-interactive` for the full schema, defaults table, and per-flag reference.

**When NOT to use:** human-driven first-time setup is better served by the interactive flow, which adapts prompts to the chosen platform/deployment context. Non-interactive mode is for repeatable, scripted workflows where the orchestrator already knows the answers.
```

### 9.2 `templates/generated/claude-md.tmpl` — Operations Reference one-liner

```markdown
- **Scripted setup.** For CI, UAT, or agent-driven project creation, use `init.sh --non-interactive --project NAME --platform PLATFORM --deployment DEPLOYMENT --language LANG [...]`. See `init.sh --help-non-interactive` for the full schema. Honors `--config FILE` for repeatable setups; flag values override config file values.
```

### 9.3 `scripts/upgrade-project.sh` — header changelog one-liner

Append to the existing changelog block:

```
# - BL-016 (2026-04-25): init.sh now supports --non-interactive mode for
#   scriptable project setup (CI, UAT, AI agents). No upgrade-project.sh
#   change needed — scripts/init.sh is copied into projects but agents
#   typically invoke the framework's init.sh directly.
```

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Interactive flow regression — the existing 2500-line block accidentally broken by edits to `main()`'s flag parsing or `create_and_protect_remote()` | Approach A's separation: zero changes inside the interactive block; only the entry-flag-parser and `create_and_protect_remote()` are touched. UAT result agents (1, 9, 14) re-run as regression check. |
| `--config` JSON parse silently masks user errors (typo in field name) | "Warn on unknown fields" rule (§ 5.4). Plus `--validate-only` lets the user see the resolved config before committing. |
| Future flag additions require both flag-parser AND validation update | Acceptable. Each new flag adds ~5 lines (parser + validator + § 7 table entry). |
| `collect_inputs_non_interactive()` grows large over time | Estimated initial size: ~150 lines. If it crosses ~300, factor into multiple functions per validation pass. |
| Non-interactive mode bypasses the dependency-installer prompts, leaving CI runs without tools | Pass-3 fail-fast on missing required tool with OS-specific install command in the error message. CI scripts should install dependencies BEFORE invoking init.sh. |

## 11. Success criteria

1. `./init.sh --non-interactive --project p --platform web --deployment personal --language typescript` creates a complete Phase-0 project with no prompts.
2. Missing required input fails fast with a clear error in the format `[FAIL] init.sh non-interactive: ...` naming the missing flag.
3. `--config init.json` reads all answers from the JSON file; flags override config values.
4. `--validate-only` prints the resolved config to stdout and exits 0 without scaffolding.
5. Conditional-required rules fire correctly (gov-mode required for organizational; remote-url + branch-protection-attested required for git-host=other).
6. `--deployment=organizational --visibility=public` is rejected at validation.
7. Missing dependencies (git, jq, node, python3) cause exit 1 with the install command in the error message — not auto-install, not interactive prompt.
8. Re-running interactive `./init.sh` (no flags) works exactly as before — zero regression in the existing flow.
9. All 26 unit tests pass; all 8 integration tests pass; all existing test suites continue to pass.
10. Re-test sweep on UAT configs (agents 1, 9, 14, 49, 77, 78, 80, 81, 82) succeeds without the heredoc-driver workarounds the original sweep needed.

## 12. Scope boundaries

### In scope (this PR)

1. New flags: `--non-interactive`, `--config FILE`, `--validate-only`, `--help-non-interactive`, plus per-input flags from § 5.1.
2. New `collect_inputs_non_interactive()` function in init.sh.
3. New top-level variables: `GOV_MODE`, `GIT_HOST`, `VISIBILITY`, `REMOTE_URL`, `BRANCH_PROTECTION_ATTESTED`, `ALLOW_EXISTING_DIR`.
4. 4-line surgical change in `create_and_protect_remote()` per host-related variable to check the new top-level FIRST.
5. New "dir exists" validation-pass-3 check that replaces the interactive prompt at line 492 when `--non-interactive` is set.
6. Three-pass validation (schema, context-required, resource) per § 6.
7. Uniform error format `[FAIL] init.sh non-interactive: ...` with Reason/Action/Context.
8. `--help-non-interactive` flag with the full schema + JSON example + per-flag descriptions.
9. Tests: 26 unit tests + 8 integration tests (E48–E55).
10. Doc updates: Builder's Guide subsection, `claude-md.tmpl` one-liner, `upgrade-project.sh` changelog entry.

### Out of scope (deferred)

- YAML config support (JSON only; users can `yq` to convert if needed).
- Cross-platform CI matrix.
- Auto-install of missing dependencies in non-interactive mode.
- Non-interactive mode for `intake-wizard.sh`, `upgrade-project.sh`, `verify-install.sh` (each logged as separate backlog items).
- Config schema versioning (all configs are implicit v1; forward-compat is "warn + ignore unknown fields").
- Refactor of the existing interactive prompt flow (Approach B was rejected; the interactive block stays untouched).

### Logged as new backlog items (post-merge)

- **BL-017** — Non-interactive mode for `intake-wizard.sh`. Lower urgency than init.sh because the wizard is typically run once per project; init.sh is the high-frequency entry point.
- **BL-018** — Non-interactive mode for `upgrade-project.sh`. Currently has `--track`, `--deployment`, `--to-production`, etc. but no overarching `--non-interactive` semantic. Defaults are mostly already non-prompting; the gap is explicit input validation.
- **BL-019** — Non-interactive mode for `verify-install.sh`. Already has `--check-only` and `--auto-fix`, both of which are arguably non-interactive variants. Audit to confirm no remaining interactive prompts.

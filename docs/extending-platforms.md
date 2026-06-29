# Extending the Solo Orchestrator: Adding a New Platform

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-008-EXTEND |
| **Version** | 1.0 |
| **Date** | 2026-04-10 |
| **Classification** | Contributor Guide |
| **Parent Document** | SOI-002-BUILD v1.0 — Solo Orchestrator Builder's Guide |

---

## Purpose

This guide documents the complete process for adding a new platform type to the Solo Orchestrator Framework. A "platform" is a delivery surface — web, desktop, mobile, MCP server, CLI, embedded, etc. Each platform has its own architecture patterns, tooling, testing strategies, and deployment processes.

The framework is designed for extensibility. Adding a platform requires creating new files in specific directories; the init script auto-discovers them without code changes. However, the process involves five components across four directories, plus updates to existing CI templates. This guide documents every step.

---

## What You Are Creating

Adding a new platform creates up to six components:

| # | Component | Location | Required? | Purpose |
|---|---|---|---|---|
| 1 | **Platform Module** | `docs/platform-modules/{platform}.md` | Yes | Architecture, tooling, testing, deployment guidance |
| 2 | **Evaluation Module** | `evaluation-prompts/Projects/modules/{platform}.md` | Yes | Domain-specific evaluation criteria for six reviewer personas |
| 3 | **Release Pipeline** | `templates/pipelines/release/{host}/{platform}.yml` for host ∈ {github, gitlab, bitbucket} | Yes | Per-host release workflow template |
| 4 | **Intake Suggestions** | `templates/intake-suggestions/{platform}.json` | Recommended | Context-aware suggestions for the intake wizard |
| 5 | **CI Template Updates** | `templates/pipelines/ci/{host}/*.yml` (line 1 marker) | Yes | Register which languages are available for this platform. `github/` is canonical for language filtering (init.sh:415-417); mirror marker changes to `gitlab/` and `bitbucket/`. |
| 6 | **UAT References** | `templates/uat/references/{platform}-pre-flight.html` + `templates/uat/references/{platform}-scenario.json` | Recommended (Required for non-`other`) | Per-platform UAT canned reference (pre-flight HTML + scenario JSON). `init.sh` copies them to `tests/uat/examples/` in generated projects so UAT session agents have a worked example. Missing files trigger a `print_warn` fall-back to the `other`-platform co-build protocol. |

**Naming convention:** Use lowercase identifier matching the form accepted by `init.sh --platform <name>`. Snake_case (`mcp_server`) is canonical for multi-word platforms; new platforms should follow the same convention. This name becomes the directory/filename slug used everywhere and appears as a selectable option in `init.sh`.

---

## Auto-Discovery: How It Works

The init script discovers platforms and languages from the filesystem at runtime. No hardcoded lists.

**Platform discovery** (init.sh lines 346-368):
1. Scans `docs/platform-modules/*.md` — each filename (minus `.md`) becomes a platform option
2. Scans `templates/pipelines/release/github/*.yml` — adds any platforms not already found. The `github/` subtree is canonical for discovery (per spec 2026-04-21, all hosts ship the same platform set, so `init.sh` only reads `github/`)
3. Appends "other" as a fallback

**Language filtering** (init.sh lines 415-417):
1. Scans `templates/pipelines/ci/github/*.yml` (the canonical host tree for language discovery; per spec 2026-04-21, gitlab/ and bitbucket/ ship the same language set)
2. Reads line 1 of each file for the marker: `# solo-orchestrator: platforms=web,desktop,mobile,mcp_server`
3. Only offers a language if the selected platform appears in that language's `platforms=` list
4. Appends "other" as a fallback

**Implication:** If you create a platform module and release pipeline but forget to update CI template markers, users will only see "other" as a language option.

---

## Step-by-Step Process

### Step 1: Platform Module

**File:** `docs/platform-modules/{platform}.md`

This is the architecture and tooling guidance document. It tells builders *how* to build on this platform — framework selection, hosting, testing tools, deployment, maintenance.

**Required structure:**

```markdown
# Solo Orchestrator Platform Module: {Platform Name}

## Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-PM-{ABBREV} |
| **Version** | 1.0 |
| **Classification** | Platform Module |
| **Date** | {YYYY-MM-DD} |
| **Parent Document** | SOI-002-BUILD v1.0 — Solo Orchestrator Builder's Guide |

---

## Scope

{What this module covers — project types, delivery surfaces, architectural styles.}

---

## 1. Architecture Patterns
{Framework selection, hosting options, database/storage, deployment models.
Include comparison tables with recommendations.}

## 2. Tooling
{Pre-build setup specific to this platform. What to install, what accounts to create.
Complement — don't duplicate — the Builder's Guide Pre-Build Setup.}

## 3. Build & Packaging
{How builds work for this platform. CI/CD additions. Optimization.}

## 4. Testing
{Platform-specific testing: E2E, integration, security, performance, accessibility.
Name specific tools and provide install/run commands.}

## 5. Deployment & Distribution
{How to deploy. Go-live checklist (platform-specific additions to Builder's Guide 4.2).
Monitoring setup.}

## 6. Maintenance ({Platform}-Specific)
{Monthly/quarterly/biannual cadence additions. Vulnerability disclosure.
Application sunsetting process.}

## 7. Phase-Specific Additions
{Appendices to Builder's Guide phases:
- Phase 1: Additional architecture requirements to append to the core prompt
- Phase 2: Additional initialization steps
- Phase 3: Additional security/validation steps}

## Appendix: Tool Quick Reference
{Table of all platform-specific tools with install commands and purpose.}

## Document Revision History
{Version table.}
```

**Guidelines:**
- Use the `⟁ PLATFORM MODULE:` callout style from the Builder's Guide as your mental model — this document answers those callouts for your platform
- Include concrete tool names, install commands, and configuration examples
- Provide comparison tables with "Solo Orchestrator recommendation" rows
- Reference existing platform modules (`web.md`, `desktop.md`, `mobile.md`, `mcp_server.md`) as examples

### Step 2: Evaluation Module

**File:** `evaluation-prompts/Projects/modules/{platform}.md`

This provides domain-specific evaluation criteria for six independent reviewer personas. Each reviewer gets three sections injected into their base template via `compose.sh`.

**Required structure:**

```markdown
# Module: {Platform Name}
# Covers: {Comma-separated list of project types this module covers}

<!-- ENGINEER:CONTEXT -->
{50-200 words: What this project type is from an engineering perspective.
Set expectations for evaluation rigor.}
<!-- /ENGINEER:CONTEXT -->

<!-- ENGINEER:CATEGORIES -->
8. **{Domain Category 1}**
   - {Evaluation criterion}
   - {Evaluation criterion}
   ...

9. **{Domain Category 2}**
   ...
<!-- /ENGINEER:CATEGORIES -->

<!-- ENGINEER:OUTPUT -->
- {Additional deliverable the engineer should produce for this project type}
<!-- /ENGINEER:OUTPUT -->

{Repeat for CIO, SECURITY, LEGAL, TECHUSER, REDTEAM}
```

**Rules:**

| Rule | Detail |
|---|---|
| **Reviewer tags** | `ENGINEER`, `CIO`, `SECURITY`, `LEGAL`, `TECHUSER`, `REDTEAM` — must be exact |
| **Section tags** | `CONTEXT`, `CATEGORIES`, `OUTPUT` — all three required for each reviewer |
| **HTML comment format** | `<!-- TAG:SECTION -->` opening, `<!-- /TAG:SECTION -->` closing — must match exactly |
| **Category numbering** | Start at 8. Universal categories 1-7 are in the base templates. |
| **Categories per reviewer** | 3-6 domain-specific categories. 5 is typical. |
| **Bullets per category** | 3-8 evaluation criteria per category |
| **Specificity** | Name concrete technologies, standards, and practices — not "follow best practices" |
| **Empty OUTPUT sections** | Allowed. Include the tags with nothing between them. |
| **REDTEAM sections** | CONTEXT is typically substantial (attack vector guidance). CATEGORIES and OUTPUT are typically empty (the base template's methodology is sufficient). |

**Test composition after creating:**

```bash
./evaluation-prompts/Projects/compose.sh engineer {platform}
```

This should produce a complete prompt with your module's content injected into the engineer base template. Verify each reviewer:

```bash
for reviewer in engineer cio security legal techuser redteam; do
  echo "=== $reviewer ==="
  ./evaluation-prompts/Projects/compose.sh $reviewer {platform} > /dev/null 2>&1 && echo "OK" || echo "FAIL"
done
```

### Step 3: Release Pipeline

**File:** `templates/pipelines/release/{host}/{platform}.yml` — one per host ∈ {`github`, `bitbucket`, `gitlab`}.

A release workflow template for releasing projects on this platform. The init script copies the correct file into the generated project based on the selected `--git-host` (see `generate_release` in init.sh:2584):

| Host | Source path | Output path in generated project |
|---|---|---|
| `github` | `templates/pipelines/release/github/{platform}.yml` | `.github/workflows/release.yml` |
| `bitbucket` | `templates/pipelines/release/bitbucket/{platform}.yml` | `bitbucket-pipelines/release.yml` |
| `gitlab` | `templates/pipelines/release/gitlab/{platform}.yml` | `.gitlab-ci/release.yml` |

The `github/` subtree is **canonical for platform discovery** — `init.sh` only reads `github/*.yml` when building the platform menu (see init.sh:346-368). Contributors adding a new platform **must** create the release pipeline in all three host directories. At minimum, mirror the github template into `bitbucket/` and `gitlab/`; otherwise users on those hosts hit the `print_info "No release pipeline template for platform … on host …"` branch in `generate_release` (init.sh:2598-2601) and ship with no release pipeline at all.

The GitHub Actions example below is the canonical shape. The bitbucket/gitlab variants follow the host's native pipeline syntax — see existing `templates/pipelines/release/bitbucket/web.yml` and `templates/pipelines/release/gitlab/web.yml` for reference shapes.

**Required structure:**

```yaml
name: Release — __PROJECT_NAME__
# ─────────────────────────────────────────────────────────────────
# {Brief description of what this pipeline does.}
# BEFORE FIRST RELEASE: Search for "TODO" in this file and configure:
#   - {List what needs configuration}
# The Phase 3→4 gate will warn if TODOs remain unconfigured.
# ─────────────────────────────────────────────────────────────────

on:
  push:
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: __SETUP_ACTION__
        with:
          __SETUP_VERSION_KEY__: __SETUP_VERSION_VALUE__

      - name: Install dependencies
        run: __INSTALL_COMMAND__

      - name: Build
        run: __BUILD_COMMAND__

      # Platform-specific steps here (testing, packaging, signing, etc.)

      - name: Generate SBOM
        run: {SBOM generation command — see web.yml for examples}

      - name: Deploy
        run: echo "TODO — deploy to {target}"
        # TODO: Deployment instructions

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: sbom.json
```

**Placeholders:** The init script substitutes these based on the selected language:

| Placeholder | Substituted With | Example (TypeScript) |
|---|---|---|
| `__PROJECT_NAME__` | Project name from init | `invoice-tool` |
| `__SETUP_ACTION__` | Language runtime setup action | `actions/setup-node@v4` |
| `__SETUP_VERSION_KEY__` | Version key for the setup action | `node-version` |
| `__SETUP_VERSION_VALUE__` | Version value | `lts/*` |
| `__INSTALL_COMMAND__` | Dependency install command | `npm ci` |
| `__BUILD_COMMAND__` | Build command | `npm run build` |

**Guidelines:**
- Use `TODO` markers for anything that requires per-project configuration (secrets, deployment targets, signing)
- Include SBOM generation (required by Phase 3)
- Include a GitHub Release step
- Mark steps that are optional for Light-track projects

### Step 4: Intake Suggestions (Recommended)

**File:** `templates/intake-suggestions/{platform}.json`

Context-aware suggestions that appear in the intake wizard when a user selects this platform. These help users make informed decisions during project setup.

**Required structure:**

```json
{
  "platform": "{platform}",
  "suggestions": {
    "{decision_category}": {
      "typescript": [
        {
          "name": "{Option name}",
          "rank": 1,
          "context": "{Why this is the default recommendation. 1-2 sentences.}",
          "when": "{When to choose this option}"
        },
        {
          "name": "{Alternative}",
          "rank": 2,
          "context": "{Trade-offs vs. rank 1}",
          "when": "{When this is better}"
        }
      ],
      "python": [ ... ],
      "default": [
        {
          "name": "{Language-agnostic default}",
          "rank": 1,
          "context": "{Why}",
          "when": "{When}"
        }
      ]
    }
  }
}
```

**Rules:**
- Each category has language-specific arrays (`typescript`, `python`, etc.) and/or a `default` array
- The `default` array is used when no language-specific array matches
- `rank` determines display order (1 = recommended default)
- `context` explains the trade-off in 1-2 sentences
- `when` describes the scenario where this option is the right choice
- If this file is absent, the intake wizard falls back to `common.json` suggestions only

**What categories to include:** Think about the platform-specific decisions a user makes during intake that they might not know the best answer to. Examples:
- `hosting` — where to deploy
- `database` / `persistence` — how to store data
- `authentication` — how to handle auth
- `ui_framework` — what UI framework to use
- Platform-specific concerns (e.g., `transport` for MCP servers, `packaging` for desktop apps)

### Step 5: CI Template Platform Markers

**Files:** `templates/pipelines/ci/{host}/*.yml` (line 1 of each file, all three host trees: `github/`, `gitlab/`, `bitbucket/`)

Each CI template has a platform marker on line 1 that controls which languages are offered for which platform. You must add your platform name to the relevant CI templates in all three host directories so the language set stays consistent across hosts (per spec 2026-04-21). `github/` is the canonical tree init.sh reads for language discovery.

**Format:** `# solo-orchestrator: platforms=web,desktop,mobile,{your-platform}`

**Which templates to update:** Only add your platform to languages that have meaningful SDK/tooling support for your platform type. Do not add every language — users selecting an unsupported language get the "other" template with intentionally-failing placeholder steps.

**Example:** For `mcp_server`, TypeScript, Python, Go, and Rust have MCP SDK support. Java, C#, Kotlin, Dart, and Swift do not, so those templates were left unchanged.

**Always update `other.yml`** — the "other" template is the catch-all and should list every platform.

### Step 6: UAT Reference Files

**Files:**
- `templates/uat/references/{platform}-pre-flight.html`
- `templates/uat/references/{platform}-scenario.json`

These are the platform-specific UAT canned reference pair (per spec 2026-04-23-uat-template-quality-design.md § Flow A). They give the UAT session agent a concrete shape to emulate when generating pre-flight blocks and scenarios for the new platform — without them, UAT quality regresses to the generic `other` co-build protocol.

**What each file contains:**

| File | Contents | Authoring guide reference |
|---|---|---|
| `{platform}-pre-flight.html` | Worked example of the pre-flight HTML block: system-under-test description, tooling, accounts, optional dependencies, one-time setup. Should mirror the structure of the existing `web-pre-flight.html` / `desktop-pre-flight.html` / `mobile-pre-flight.html` / `mcp_server-pre-flight.html`. | `docs/uat-authoring-guide.md` §3.1–3.4 |
| `{platform}-scenario.json` | Worked example of a single scenario (or short scenarios array) showing the platform's typical anchor styles (exact-string match, exit-code, response-shape, on-screen text, etc.). | `docs/uat-authoring-guide.md` §4.1–4.4 |

**How `init.sh` uses them** (init.sh:1187-1207):

```text
mkdir -p tests/uat/templates tests/uat/sessions tests/uat/examples
cp .../test-session-template.{md,html} tests/uat/templates/
if [ "$PLATFORM" != "other" ] && [ -f templates/uat/references/${PLATFORM}-pre-flight.html ] && [ -f templates/uat/references/${PLATFORM}-scenario.json ]; then
  cp templates/uat/references/${PLATFORM}-pre-flight.html tests/uat/examples/pre-flight-reference.html
  cp templates/uat/references/${PLATFORM}-scenario.json   tests/uat/examples/scenario-reference.json
elif [ "$PLATFORM" = "other" ]; then
  print_info "... no UAT canned reference copied ... co-build Q&A protocol per docs/reference/uat-authoring-guide.md § 5"
else
  print_warn "UAT reference files not found for platform '$PLATFORM'. Falling back to 'other'-style co-build protocol; see docs/reference/uat-authoring-guide.md § 5."
fi
```

When **both files are present**, they are copied into the generated project at `tests/uat/examples/pre-flight-reference.html` and `tests/uat/examples/scenario-reference.json`. When **either file is missing** for a non-`other` platform, `init.sh` emits the `print_warn` fallback above and the project ships without canned references — the session agent must then run the `other`-style co-build protocol with the Orchestrator.

**Authoring guidance:** Read `docs/uat-authoring-guide.md` §3 (per-platform pre-flight patterns) and §4 (per-platform scenario patterns) before writing the new reference pair. Add a new subsection to each of those §§ describing the platform's pre-flight requirements and scenario shapes — per `docs/uat-authoring-guide.md` §7 (Extending for a new platform), this is one of the three things that must happen for UAT parity when adding a new first-class platform.

---

## Validation Checklist

After creating all components, verify your platform works end-to-end:

### File Existence

- [ ] `docs/platform-modules/{platform}.md` exists
- [ ] `evaluation-prompts/Projects/modules/{platform}.md` exists
- [ ] `templates/pipelines/release/github/{platform}.yml` exists (canonical for discovery)
- [ ] `templates/pipelines/release/bitbucket/{platform}.yml` exists
- [ ] `templates/pipelines/release/gitlab/{platform}.yml` exists
- [ ] `templates/intake-suggestions/{platform}.json` exists (recommended)
- [ ] Relevant `templates/pipelines/ci/{host}/*.yml` files updated with platform marker (all three host trees: github/gitlab/bitbucket)
- [ ] `templates/pipelines/ci/{host}/other.yml` includes your platform in its marker
- [ ] `templates/uat/references/{platform}-pre-flight.html` exists (recommended; required for non-`other`)
- [ ] `templates/uat/references/{platform}-scenario.json` exists (recommended; required for non-`other`)

### Platform Module Completeness

- [ ] Document Control table with ID, version, date, parent document
- [ ] Scope section
- [ ] All 7 sections present: Architecture, Tooling, Build & Packaging, Testing, Deployment, Maintenance, Phase-Specific Additions
- [ ] Phase-specific additions for Phases 1, 2, and 3
- [ ] Tool Quick Reference table
- [ ] Document Revision History

### Evaluation Module Correctness

- [ ] All 6 reviewers have all 3 sections: CONTEXT, CATEGORIES, OUTPUT
- [ ] HTML comment tags match exactly (no typos, no extra spaces)
- [ ] Categories start at number 8+
- [ ] Composition test passes for all 6 reviewers:

```bash
for reviewer in engineer cio security legal techuser redteam; do
  ./evaluation-prompts/Projects/compose.sh $reviewer {platform} > /dev/null 2>&1 && \
    echo "$reviewer: OK" || echo "$reviewer: FAIL"
done
```

### Release Pipeline

- [ ] Contains `__SETUP_ACTION__`, `__SETUP_VERSION_KEY__`, `__SETUP_VERSION_VALUE__`, `__INSTALL_COMMAND__`, `__BUILD_COMMAND__` placeholders
- [ ] Contains `TODO` markers for per-project configuration
- [ ] Includes SBOM generation step
- [ ] Includes GitHub Release step

### Init Script Integration

- [ ] Run `./init.sh` — your platform appears in the platform selection menu
- [ ] After selecting your platform, expected languages appear (not just "other")
- [ ] Generated project contains the correct `release.yml` from your template
- [ ] Generated project contains your platform module in `docs/platform-modules/`
- [ ] Generated project contains your intake suggestions in `templates/intake-suggestions/`

---

## After Adding a Platform

### Update Documentation

1. **README.md** — Add your platform to the "Supported Platforms" table in the Platform Support section.

2. **User Guide** (docs/user-guide.md) — Add your evaluation module to the "Domain modules" table in section 8.2 (Project Evaluation Prompts).

3. **Run framework evaluation prompts** — After adding a new platform module, run the framework evaluation prompts to verify the addition doesn't introduce gaps:

```bash
./evaluation-prompts/Framework/run-reviews.sh
```

### Test With a Real Project

The best validation is to initialize a real project with your new platform and run through at least Phase 0 and Phase 1:

```bash
./init.sh
# Select your new platform, a supported language, and your preferred track
# Verify the generated project structure
# Run the CI pipeline (push to GitHub)
# Run the evaluation prompts against the project
```

---

## Reference: Existing Platforms

Study these as examples when building your own:

| Platform | Module | Evaluation | Pipeline | Intake | CI Languages |
|---|---|---|---|---|---|
| `web` | `docs/platform-modules/web.md` | `modules/web-app.md` | `release/web.yml` | `web.json` | TS, PY, RS, GO, C#, JV, KT, Other |
| `desktop` | `docs/platform-modules/desktop.md` | `modules/desktop-app.md` | `release/desktop.yml` | `desktop.json` | TS, RS, C#, GO, JV, KT, SW, Other |
| `mobile` | `docs/platform-modules/mobile.md` | `modules/mobile-app.md` | `release/mobile.yml` | `mobile.json` | TS, KT, DT, SW, Other |
| `mcp_server` | `docs/platform-modules/mcp_server.md` | `modules/mcp-server.md` | `release/mcp_server.yml` | `mcp_server.json` | TS, PY, RS, GO, Other |

**Note:** The evaluation module filename does not need to match the platform name exactly. For example, `web` uses `web-app.md` and `desktop` uses `desktop-app.md`. The evaluation module name is what you pass to `compose.sh` and `run-reviews.sh` — it is independent of the platform name used by `init.sh`.

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-10 | Initial release. |

# Solo Orchestrator — Bugs & Issues Backlog

This file tracks bugs and rough edges found in the Solo Orchestrator framework while using it on downstream projects. Each entry is written as a **self-contained prompt** you can paste into a fresh Claude Code session in the `solo-orchestrator` repo.

---

## Before reporting — investigation checklist

When the framework says *"X is missing / not installed / not configured,"* it may be a real absence **or** a detector false-negative. Run these checks before writing the prompt-to-fix, and state both the claimed state and the observed state explicitly in the prompt so a future Claude doesn't chase the wrong hypothesis.

1. **Verify X's actual state directly.** A script saying "not installed" is a claim, not a fact. Check independently: `claude mcp list`, `jq` the config, `ls` the path, run the tool. Observe before reporting.
2. **Check the solo-orchestrator source repo, not just the downstream project.** Templates, configs, and scripts referenced by the Builder's Guide may exist in source but fail to propagate. Before concluding "X needs to be authored," grep / `ls` the source. The bug may be a missing `cp` line or a drifted path, not a missing artifact (see BUG-003 for an example).
3. **Check alternate install / config paths.** `~/.claude/settings.json` vs. `~/.claude.json`; `.mcpServers.*` vs. `.enabledPlugins.*`; global vs. project-scoped; direct MCP vs. Claude Code plugin. Detectors often inspect one path and miss the others (see BUG-001).
4. **Phrase the prompt with observed vs. claimed.** Example: *"Framework hook printed '[X not installed]', but `claude mcp list` shows X connected"* — that wording makes the false-negative framing load-bearing. "X is missing" alone nudges a future Claude toward authoring a replacement instead of fixing detection.

If the framework is right that X is genuinely absent, these checks cost ~30 seconds. If it's a false negative, they keep the downstream session from investigating the wrong problem.

---

## BUG-001: Context7 MCP detection is stale in framework compliance hook

**Found:** 2026-04-20
**Found while:** Starting Phase 0 of the `lancache_orchestrator` project
**Severity:** Low (cosmetic — framework still operates)

### Prompt to fix

```
Working in the solo-orchestrator repo.

I hit a bug in a downstream project (lancache_orchestrator) today. At session
start, the framework compliance hook printed:

    WARNINGS:
      ! Context7 MCP not installed. Implementation Zone degraded.
        To install: claude mcp add context7 -- npx -y @upstash/context7-mcp@latest

But Context7 IS installed and working. In the same session, the agent had
access to:
  - mcp__context7__resolve-library-id
  - mcp__context7__query-docs
  - mcp__plugin_context7_context7__resolve-library-id
  - mcp__plugin_context7_context7__query-docs

And the project's own PROJECT_INTAKE.md (Section 12, Tooling Configuration)
listed "Context7 MCP | mcp_server | configured".

The detection logic in the compliance hook is checking for Context7 the wrong
way — probably looking for a specific MCP server name, registry entry, or
config file location that doesn't match how Context7 is actually installed
via the plugin system.

Please:
1. Find the SessionStart hook script that emits "Context7 MCP not installed"
   — likely under .claude/hooks/ or scripts/ in this repo, or in the
   init.sh-generated output.
2. Identify how it's detecting Context7 presence (claude mcp list?
   settings.json parse? env var?).
3. Determine what the correct detection should look for — both the
   `claude mcp add context7 ...` style install AND the plugin-namespaced
   `mcp__plugin_context7_context7__*` tool variant.
4. Propose the fix. Do NOT apply until I approve — show me the detection
   logic before/after.

Keep the behavior: if Context7 is genuinely missing, still warn clearly. We
only want to eliminate the false negative.
```

### Resolution — 2026-04-20 (same session)

**Status:** Fixed.

**Root cause:** The warning is emitted by the **external** `claude-dev-framework` (CDF) repo, not by Solo Orchestrator itself. The offending detection function lives at `~/.claude-dev-framework/hooks/_helpers.sh:147-153` (`check_context7`), and the warning text comes from `~/.claude-dev-framework/hooks/session-start.sh:42-52`. The stock detection only checks `~/.claude/settings.json .mcpServers.context7`, which misses two real install paths: the alternate `~/.claude.json` config file, and plugin-installed Context7 (which registers under `.enabledPlugins["context7@..."]`, not `.mcpServers`, and surfaces tools as `mcp__plugin_context7_context7__*`). The plugin path is how Context7 was installed on the reporting machine — hence the false negative.

**Fix (all in solo-orchestrator, per explicit preference — no CDF fork):**

1. **Solo's own Context7 detection extended to cover all three install paths:**
   - `scripts/lib/helpers.sh` — `is_context7_mcp_registered()` now also checks `.enabledPlugins` for any key matching `^context7`.
   - `scripts/verify-install.sh` — refactored the inline Context7 check to call `is_context7_mcp_registered` (single source of truth).
   - `templates/tool-matrix/common.json` — Context7 tool's `check_command` adds the same plugin-path check as a third OR-clause.

2. **CDF's project-local hook patched post-install, not upstream:**
   - `init.sh` now appends a shadowing `check_context7()` function to `.claude/framework/hooks/_helpers.sh` after CDF's init completes. Bash sourcing uses the last function definition, so the appended version wins without modifying CDF's code. A `SOLO_ORCHESTRATOR_CONTEXT7_PATCH` marker prevents double-patching on re-init. CDF stays unmodified upstream so standalone CDF users are unaffected.

**Live verification against the reporting machine:** the stock CDF check returned "no match" (confirming the false negative), while the patched version detected `context7@claude-plugins-official = true` in `.enabledPlugins` — both the Solo detection and the CDF shadow function now return true for the plugin install.

**Files touched:** `init.sh`, `scripts/lib/helpers.sh`, `scripts/verify-install.sh`, `templates/tool-matrix/common.json`.

---

## BUG-002: .claude-backup/ directory left as init residue in generated projects

**Found:** 2026-04-20
**Found while:** First session in `lancache_orchestrator` after `init.sh` ran
**Severity:** Low (cosmetic — confusing for new users, adds noise to `git status`)

### Prompt to fix

```
Working in the solo-orchestrator repo.

When init.sh scaffolds a new project, it leaves a .claude-backup/ directory
in the project root as residue. In my lancache_orchestrator project:

  lancache_orchestrator/
    .claude/                ← used
    .claude-backup/         ← residue, not referenced anywhere
    ...

This is confusing: the name implies it's load-bearing ("is this my backup
of .claude/? can I delete it? will init break if I do?"), but nothing
reads from it after init finishes.

Please:
1. Grep init.sh and any scripts it calls for .claude-backup references.
2. Determine why it's created — is it a safety snapshot taken before
   overwriting an existing .claude/? A pre-flight rollback target? Dead
   code from an old version?
3. Based on the finding, propose one of:
   (a) Remove creation entirely if it's dead code.
   (b) Add a cleanup step at end of init.sh (`rm -rf .claude-backup` after
       successful completion) if it's only needed during init.
   (c) Rename it something less alarming and add a comment/README in it
       explaining what it is, if it's genuinely useful for rollback.
4. Also check: does init.sh add .claude-backup/ to .gitignore? If it's kept,
   it should be gitignored to avoid polluting `git status` on first commit.

Do NOT apply the fix until I review the proposal.
```

### Resolution — 2026-04-20 (same session)

**Status:** Fixed.

**Root cause:** The `.claude-backup/{timestamp}/` directory is created by CDF's own init.sh at `~/.claude-dev-framework/scripts/init.sh:202-235` ("Phase 4: BACKUP"). CDF creates it as a rollback target when merging its hooks into an existing `.claude/` — a legitimate safety net for standalone CDF users.

**Why it's residue specifically in the Solo Orchestrator flow:** Solo's `init.sh` seeds `.claude/` (phase-state.json, tool-preferences.json, orchestrator-source.json, etc.) *before* invoking CDF. CDF then snapshots that brand-new `.claude/` — but it contains no user work. CDF's own policy is to merge only the `hooks` key into `settings.json` (other keys preserved), so nothing from the snapshot could ever need restoring. The backup is functionally useless in this flow, and the `.claude-backup/` name looks load-bearing to new users.

**Fix (in solo-orchestrator, not CDF — CDF keeps its backup for standalone users):**

1. **Cleanup in `init.sh` success branch:** after CDF produces `.claude/manifest.json`, `rm -rf .claude-backup` runs with an info log. Guarded by `[ -d ".claude-backup" ]` so the cleanup is a no-op if absent.

2. **Gitignore safety net:** `templates/generated/gitignore-base.tmpl` now lists `.claude-backup/` at the bottom with a comment explaining why. Belt-and-suspenders in case a future code path (upgrade flow, early exit) leaves the directory behind.

**Files touched:** `init.sh`, `templates/generated/gitignore-base.tmpl`.

---

## BUG-003: Missing Phase 0 intermediate-artifact templates

**Found:** 2026-04-20
**Found while:** Phase 0 Step 0.1 of `lancache_orchestrator` — generating FRD
**Severity:** Medium (process friction — agent must generate doc structure from prompt specs instead of a template)

### Prompt to fix

```
Working in the solo-orchestrator repo.

I hit a missing-template bug in a downstream project during Phase 0.

The Builder's Guide (docs/reference/builders-guide.md) explicitly references
three templates for Phase 0 intermediate artifacts:

  - Line 372:  **Template:** `templates/generated/frd.tmpl`
               **Save as:** `docs/phase-0/frd.md`
  - Line 413:  **Template:** `templates/generated/user-journey.tmpl`
               **Save as:** `docs/phase-0/user-journey.md`
  - Line 452:  **Template:** `templates/generated/data-contract.tmpl`
               **Save as:** `docs/phase-0/data-contract.md`

None of those three .tmpl files exists in a freshly init.sh-generated project.
Only these four do:
  - templates/generated/adr.tmpl
  - templates/generated/changelog.tmpl
  - templates/generated/features.tmpl
  - templates/generated/product-manifesto.tmpl
  - templates/generated/bugs.tmpl
  - templates/generated/handoff.tmpl
  - templates/generated/incident-response.tmpl
  - templates/generated/release-notes.tmpl

(Notably, the Phase 4 templates ARE shipped — incident-response, handoff,
release-notes — and the Phase 0 synthesis template for the Manifesto ships.
Only the three intermediate Phase 0 artifacts are missing.)

Without these templates, the agent has to derive the FRD / user-journey /
data-contract structure from the prose in the Builder's Guide Step prompts.
The downstream FRD I generated for lancache_orchestrator is quality work,
but without a template as an authoritative source of truth, structure will
drift across projects and the gate script (check-phase-gate.sh) can't reliably
spot missing sections.

Please:
1. Confirm by grep whether the three templates ever existed in the
   solo-orchestrator repo history (git log --all --full-history
   -- templates/generated/frd.tmpl).
2. If they existed and were removed: find out why. Either re-add them or
   update the Builder's Guide to not reference them.
3. If they never existed: decide whether to (a) write the three templates
   now, matching the structure of the product-manifesto.tmpl (headings,
   frontmatter, placeholder convention), or (b) remove the template
   references from the Builder's Guide lines 372, 413, 452 and add a
   note saying "generate from the prompt specification above."

I recommend (a) — concrete templates keep structure consistent across
projects and let check-phase-gate.sh grow section-level validation later.

Do NOT apply the fix until I review the proposal.
```

### Resolution — 2026-04-20 (same session)

**Status:** Fixed.

**Root cause (branch 3 of the prompt — "if they never existed" — turned out to be wrong):** The three templates *do* exist in the Solo Orchestrator source repo at `templates/generated/` (`frd.tmpl` 60 lines, `user-journey.tmpl` 68 lines, `data-contract.tmpl` 79 lines) and are real, populated artifacts with review checklists. The 2026-04-08 phase-0 re-audit (round 3) already validated their content. What was broken is the per-project copy step in `init.sh:1086-1101`, which enumerates templates by name and simply omitted these three from the list.

**Fix:** Added three `cp` lines in `init.sh` immediately after the `product-manifesto.tmpl` copy:

```bash
cp "$SCRIPT_DIR/templates/generated/frd.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/user-journey.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/data-contract.tmpl" templates/generated/
```

**Existing downstream projects** (initialized before this fix) still lack the three templates. To remediate, copy the three files directly from the Solo source `templates/generated/` into the project's `templates/generated/`.

**Follow-up worth considering (not required):** The explicit per-file copy list is brittle — any future template added to `templates/generated/` will silently fail to propagate until someone remembers to add a `cp` line. Consider replacing with `cp "$SCRIPT_DIR/templates/generated/"*.tmpl templates/generated/`. Out of scope for this bug.

---

## BUG-004: `check-phase-gate.sh` uses `local` outside a function (exits 1 on legitimate gate crossings)

**Found:** 2026-04-20
**Found while:** Phase 0 → Phase 1 gate transition of `lancache_orchestrator` (same session as BUG-001/002/003)
**Severity:** Medium (blocks CI gate enforcement on otherwise-valid gate transitions)

### Prompt to fix

```
Working in the solo-orchestrator repo.

I hit a shell-scripting bug in scripts/check-phase-gate.sh during a legitimate
Phase 0 → Phase 1 gate transition in a downstream project.

Repro:
  1. In a project with current_phase=1 in .claude/phase-state.json, a valid
     APPROVAL_LOG.md Phase 0→1 entry (dated 2026-04-20), and a complete
     PRODUCT_MANIFESTO.md with all 8 numbered sections, no "Status: Open" lines.
  2. Run: bash scripts/check-phase-gate.sh
  3. Output:

       Phase Gate Consistency Check
       Current phase: 1

         [OK] Phase 0→1: gate dated 2026-04-20, approval log has entry
         [OK] PRODUCT_MANIFESTO.md exists
       scripts/check-phase-gate.sh: line 249: local: can only be used in a function

  4. Exit code: 1.

Content-wise the gate passed the two checks that did run, but the `local`
declaration crashes the script before completing the remaining checks
(manifesto-section validation, Open-Questions scan, Phase 0 intermediate-
artifact presence). CI that runs this script will fail the merge even though
every validation it emitted before the crash printed [OK].

Please:
1. Open scripts/check-phase-gate.sh and look at line 249 (and surrounding
   context). The `local KEYWORD` declaration is outside a function body.
2. Fix one of two ways:
   (a) Wrap the enclosing block in a function and call it, or
   (b) Drop `local` and just use `VAR=...` (the variable will leak to shell
       scope, but that's tolerable for a short gate script).
3. After fixing, re-run the script against this downstream project at
   /Users/karl/Documents/Claude Projects/lancache_orchestrator and confirm
   it exits 0 with the full set of intended [OK]/[WARN] lines.
4. Grep scripts/ (and .claude/framework/ if present) for other `local`
   usages outside functions — fix them the same way for consistency.

Do NOT apply the fix until I review the proposal.
```

### Resolution — 2026-04-20

**Status:** Fixed.

**Root cause:** Two `local` declarations at top-level scope (outside any function body). Bash's `set -e` causes the script to exit with code 1 when `local` is used outside a function.

**Instances found and fixed:**

1. **Line 249:** `local p0_files=0` — inside the Phase 0 intermediate outputs check block (under `if [ -d "docs/phase-0" ]`), but NOT inside a function. Changed to `p0_files=0`.

2. **Line 439:** `local p3_steps_done` — inside the Phase 3 process-state.json check block (under `if [ -f ".claude/process-state.json" ]`), but NOT inside a function. Removed the `local` declaration line; the variable is assigned directly by the `$(jq ...)` command substitution on the next line.

**Scan results:** Grepped all scripts in `scripts/` and `scripts/lib/` for `local` outside function bodies. No other instances found — all other `local` usages are inside properly defined functions (`create_gate_snapshot`, `get_gate_date`, `validate_manifesto_content`, `validate_approval_fields`, and functions in `intake-wizard.sh`, `validate.sh`, `lib/helpers.sh`).

**Files touched:** `scripts/check-phase-gate.sh`.

---

## BUG-005: `validate.sh` and `check-updates.sh` check a framework-version file that is never created

**Found:** 2026-04-20
**Found while:** Auditing README claims against actual generated project layout in `lancache_orchestrator`
**Severity:** Low (cosmetic — no functional failure, but scripts silently display empty pin data)

### Prompt to fix

```
Working in the solo-orchestrator repo.

README.md used to claim `.claude/framework-config.yml` and `.claude/framework-version.txt`
are generated during init. Neither file is actually created — neither solo-orchestrator's
init.sh nor CDF's init writes them. Verified against a current-version project
(lancache_orchestrator, initialized 2026-04-20): `.claude/` contains manifest.json
(CDF's actual metadata), settings.json, phase-state.json, process-state.json,
tool-preferences.json, tool-usage.json, build-progress.json, orchestrator-source.json,
settings.local.json — but no framework-config.yml and no framework-version.txt.

README has been fixed to remove the phantom files. But two utility scripts still
reference framework-version.txt:

  - scripts/validate.sh:80-83  — reads .claude/framework-version.txt to show pinned SHA
  - scripts/check-updates.sh:55-58 — same

Both branches silently no-op in every real project (the file doesn't exist, so the
`if [ -f ... ]; then` block is skipped). The actual pin is in .claude/manifest.json:

  {
    "frameworkVersion": "4.2.0",
    "frameworkCommit": "b32fce5",
    ...
  }

Please:
1. Update validate.sh to read manifest.json .frameworkCommit and .frameworkVersion
   using jq (jq is already a required prerequisite per templates/tool-matrix/common.json).
2. Update check-updates.sh the same way.
3. Preserve the degrade-gracefully behavior: if manifest.json is missing or malformed,
   the scripts should continue without erroring out (they currently just skip).
```

### Resolution — 2026-04-20 (same session)

**Status:** Fixed.

**Root cause:** Dead code. `.claude/framework-version.txt` was planned as a Solo-Orchestrator-owned pin file, but Solo never wrote it — CDF records its own pin in `.claude/manifest.json` during its init. The check branches in `validate.sh` and `check-updates.sh` were written against the intended-but-never-created file and silently no-op'd in every real project.

**Fix:** Both scripts now read `.claude/manifest.json` via `jq`, displaying `frameworkCommit` (short 12 chars) and `frameworkVersion` when available. If `manifest.json` is missing or unreadable, the branch is silently skipped — same graceful behavior as before. `jq` is already a required prereq in `templates/tool-matrix/common.json` so no new dependency.

**Files touched:** `scripts/validate.sh`, `scripts/check-updates.sh`.

---

## BUG-006: Pre-commit hook breaks on paths with spaces (Semgrep xargs splitting)

**Found:** 2026-04-20
**Found while:** Phase 0 → Phase 1 gate commit in `lancache_orchestrator` — file in `docs/ADR documentation/` blocked commit
**Severity:** High (blocks ALL commits touching space-containing paths that the framework itself creates)

### Prompt to fix

```
Working in the solo-orchestrator repo.

The pre-commit hook generated by init.sh has an xargs quoting bug that
conflicts with the framework's own directory naming convention.

init.sh creates `docs/ADR documentation/` and `docs/api and interfaces/`
(space-containing paths, per the framework's non-technical naming preference).
The same init.sh generates a .git/hooks/pre-commit that scans staged files
with Semgrep using unquoted xargs:

  staged_files=$(git diff --cached --name-only --diff-filter=ACM)
  echo "$staged_files" | xargs semgrep scan --config=p/owasp-top-ten ...

xargs splits on whitespace (both newlines AND spaces). A staged file like
`docs/ADR documentation/0001-architecture.md` becomes two arguments:
`docs/ADR` and `documentation/0001-architecture.md`. Neither exists, so
Semgrep exits non-zero and the hook prints [BLOCKED].

Fix: Use null-delimited git output with xargs -0:

  git diff --cached --name-only --diff-filter=ACM -z | xargs -0 semgrep scan ...

This is in init.sh around line 1741-1743 (the HOOKEOF heredoc that generates
.git/hooks/pre-commit).
```

### Resolution — 2026-04-20 (same session)

**Status:** Fixed.

**Root cause:** `init.sh:1741-1743` generates a `.git/hooks/pre-commit` that pipes staged filenames through unquoted `xargs`. The `xargs` utility splits on all whitespace by default (spaces, tabs, newlines), so filenames containing spaces are split into multiple arguments. The framework itself creates `docs/ADR documentation/` and `docs/api and interfaces/` during init — so the framework's own directory naming convention triggers its own pre-commit hook failure.

**Fix:** Changed the Semgrep scan line in the pre-commit hook template from:
```bash
echo "$staged_files" | xargs semgrep scan --config=p/owasp-top-ten --quiet --no-git-ignore
```
to:
```bash
git diff --cached --name-only --diff-filter=ACM -z | xargs -0 semgrep scan --config=p/owasp-top-ten --quiet --no-git-ignore
```

The `-z` flag on `git diff` outputs null-delimited filenames, and `-0` on `xargs` reads null-delimited input. This correctly handles spaces, newlines, and all other special characters in paths.

**Existing downstream projects** (initialized before this fix) have the broken hook baked into `.git/hooks/pre-commit`. To remediate: manually replace the `echo "$staged_files" | xargs semgrep` line with the `git diff -z | xargs -0 semgrep` version, or re-run init.sh (which will regenerate the hook).

**Files touched:** `init.sh`.

---

## Template for new entries

When adding a new bug, copy this block and fill it in:

```markdown
## BUG-###: [One-line title]

**Found:** YYYY-MM-DD
**Found while:** [which downstream project / phase / step]
**Severity:** [Low / Medium / High / Critical]

### Prompt to fix

\`\`\`
Working in the solo-orchestrator repo.

[Context of what I was doing and what went wrong. Include exact error
messages, commands, file paths, and observed vs. expected behavior.]

Please:
1. [First investigation step]
2. [Next step]
3. [Propose a fix — do NOT apply until I approve]
\`\`\`
```

# Auto-Discovery + Schema-Based Checker for Extensibility — v2 Concept

## Problem Statement

Solo Orchestrator V1 is partially extensible: drop-in points exist for platforms (`templates/platforms/<name>.md`), CI templates (`templates/pipelines/ci/<host>/<lang>.yml`), tool matrices (`templates/tool-matrix/<name>.json`), host drivers (`scripts/host-drivers/<name>.sh`), and intake suggestions. But adding any of these requires editing **central plumbing** in addition to dropping in the file:

- **Hardcoded validation in `init.sh`:** `case "$ARG_PLATFORM" in desktop|mobile|web|mcp_server) ;; *) fail ;;`. Adding `cli` as a platform requires editing this case statement.
- **Hardcoded UI lists in wizards:** `prompt_choice "Platform:" "desktop" "mobile" "web" "mcp_server"`. Adding `cli` requires editing this prompt.
- **Hardcoded validation in `--validate-only` JSON output**, `--help` text, error messages, test fixtures.
- **Multiple files to update for a single new option** — adding a platform means: drop the markdown, edit init.sh validation, edit wizard prompt, edit help text, possibly edit upgrade-project.sh and intake-wizard.sh, possibly edit tool-matrix referencing.

The drop-in promise is partial. Real extensibility requires modifying core code, which means contributors need to understand the framework's plumbing, and updates to the framework risk breaking external extensions.

## Proposed Direction (V2)

**Auto-discover everything from the filesystem; validate via schemas; never hardcode option lists in core code.**

### The pattern

For each extension type, the framework reads `<extension-dir>/` and uses whatever it finds:

```bash
# OLD (V1):
prompt_choice "Platform" "desktop" "mobile" "web" "mcp_server"
case "$ARG_PLATFORM" in
  desktop|mobile|web|mcp_server) ;;
  *) fail "invalid --platform" ;;
esac

# NEW (V2):
PLATFORMS=$(ls templates/platforms/*.md 2>/dev/null | xargs -I{} basename {} .md)
prompt_choice "Platform" $PLATFORMS
case " $PLATFORMS " in
  *" $ARG_PLATFORM "*) ;;
  *) fail "invalid --platform '$ARG_PLATFORM' — see templates/platforms/" ;;
esac
```

Drop in `templates/platforms/cli.md` and "cli" appears as a platform choice **everywhere it's relevant**. No core code edits.

### Schema-based Checker

Auto-discovery without validation is dangerous: invalid drop-ins can crash the framework. The Checker validates every drop-in against a schema:

- Per extension type: `<extension-dir>/_schema.json` defines what fields must exist, types, valid values.
- For markdown extensions (platform docs), use **frontmatter** + frontmatter schema:
  ```markdown
  ---
  name: cli
  languages: [rust, go, python]
  test_pattern: "test_*.py"
  ---
  
  (rest of the markdown is human docs, not validated)
  ```
- For JSON extensions (tool-matrix, methodologies, gates, etc.), validate the whole file against the schema.
- For shell extensions (host drivers, hooks), define a **contract test** — a script that exercises the extension against a known scenario and asserts expected behavior.

The Checker:
- Runs on every drop-in **at init time** (refuses to start if any extension is invalid).
- Is **invokable on-demand** via `scripts/validate-extension.sh <path>`.
- Returns **structured errors** identifying which file failed, which schema rule was violated, and how to fix it.
- Is **referenced from CI** so the framework's own tests catch breakage when shipping.

### Where to apply

Solo V1 has hardcoded lists in many places. V2 replaces all of them with discovery:

| V1 location | V2 replacement |
|---|---|
| `init.sh` `case "$ARG_PLATFORM" in desktop\|mobile\|web\|mcp_server)` | `case " $(ls templates/platforms/) " in *" $ARG_PLATFORM.md "*)` |
| `intake-wizard.sh` `prompt_choice "Platform:" "desktop" "mobile" "web" "mcp_server"` | `prompt_choice "Platform:" $(discover_platforms)` |
| `init.sh` validation of `--track` (light/standard/full) | Discover from `configs/tracks/<name>.json` |
| `init.sh` validation of `--gov-mode` (production/sponsored_poc/private_poc) | Discover from `configs/gov-modes/<name>.json` |
| `upgrade-project.sh` validation of `--track` and `--deployment` | Same — discovery |
| `init.sh` `--validate-only` JSON output reflecting valid options | Reflect discovery |
| `--help` text listing valid options | Generate from discovery |
| Test fixtures naming valid platforms | Reflect discovery |
| Tool matrix referencing platforms | Verify each `templates/tool-matrix/<name>.json` corresponds to a `templates/platforms/<name>.md` (cross-reference validation in Checker) |

This is mechanical but pervasive. Done right, the framework's hardcoded knowledge collapses into "what types of extensions exist" (a small finite list at the source level) rather than "what specific options exist within each type" (open-ended).

## Key Design Questions

1. **Discovery cache vs filesystem read on every prompt.** Is filesystem performance a concern? For a wizard with 12 sections each prompting from auto-discovery, that's potentially 12 directory scans. Probably fine on local filesystems but worth measuring. Cache invalidation on extension drop-in is the alternative.

2. **Schema authoring complexity.** Schemas are themselves files developers may need to read or modify. Are JSON Schema (V1's existing format) sufficient? Or use TypeSpec / Protobuf for richer types? JSON Schema is more universal and AI-readable.

3. **Cross-reference validation.** Some extensions reference others (tool-matrix points at platforms; methodology points at gates). The Checker should validate these cross-references, not just per-file schemas. Adds complexity but catches real bugs.

4. **Markdown frontmatter schema enforcement.** Markdown is permissive by design. Frontmatter validation is straightforward but the markdown body itself is descriptive — should the Checker even attempt to validate body content? Probably not; let humans write whatever helps them.

5. **Extension authoring documentation.** Even with auto-discovery, contributors need to know what fields to put in their drop-in. V2 ships hand-authoring docs (`docs/extension-authoring/<type>.md`) showing how to write each extension type by reading the schema and following examples. Good error messages from the Checker reduce documentation burden.

6. **Versioning of extensions.** What if a future framework version changes the schema? Extensions need a `schema_version` field; the Checker validates against the current version and warns on outdated extensions. Migration tooling for "upgrade this extension to the new schema" is a future need.

7. **Extension priority / shadowing.** What if a project drops in a custom `templates/platforms/web.md` to override the framework's? Should that be allowed (project-local override) or refused (one source of truth)? Probably allow with a `[OVERRIDE]` warning so it's visible.

## Pairs with the Extensible Creator (separate concept, deferred)

Auto-discovery + Checker enables the Extensible Creator wizard: a guided tool that walks an extension author through producing a valid drop-in. The wizard reads the schema, prompts for each field, validates the input, and writes the file. Without auto-discovery + Checker, the Creator can't exist; with them, the Creator is a natural follow-on but not load-bearing for V2 itself.

## Why this is V2, not a refactor of V1

The V1 architecture works. Refactoring to discovery throughout V1 is a major change that touches dozens of files. Pairing this with the MCP server architecture migration (separate v2 concept) is the natural time to do it: a major version boundary where the rewrite is justified by other factors.

V2 candidates that pair naturally with auto-discovery:
- MCP server architecture (separate concept) — same major-version event
- Post-MVP feature development cycle (separate concept) — needs discovery for "feature templates" and "validation profiles"
- Principal Engineer Guardian (separate concept) — runs cleaner if it can discover review profiles from `configs/`

## Risks

1. **Filesystem performance** if discovery is uncached and wizard does N prompts. Probably negligible but worth measuring.
2. **Schema design complexity.** Getting the schemas right means understanding what each extension type actually needs. V2 should ship with 2-3 reference extensions per type to validate the schema.
3. **Backward compatibility.** Existing V1 platforms (web, desktop, mobile, mcp_server) need to be re-expressed as auto-discoverable extensions. They already are (markdown files in `templates/platforms/`); the work is adding frontmatter to match the V2 schema.
4. **Cross-reference validation is hard.** Naive validation says "this tool-matrix references platform X; does X exist?" Sophisticated validation says "does X define the languages this tool-matrix expects?" V2 should do naive first; sophisticated is a future iteration.
5. **Bash discovery patterns are fragile.** `ls *.md | xargs basename` chains break on filenames with spaces, special chars, etc. V2 should use safer patterns (`find` with null-terminated output, or move to a real implementation language). Pairs naturally with the MCP server / language migration.

## Trigger

Adopt for Solo V2 when at least one of these is true:
- A community contributor adds an extension and asks "do I also need to edit the framework code?" — that's the user-visible pain.
- A new platform / methodology / track is added to V1 and the central-plumbing edits become a real source of merge conflicts.
- The MCP server architecture migration (separate v2 concept) is being planned, since auto-discovery is a natural pairing for that effort.

Until one of those triggers, V1's hardcoded lists continue to serve. The pain is real but contained.

## Reference

- Team-Orchestrator (sibling project, designed 2026-04-27) is committing to auto-discovery + Checker from V1 because its broader extension surface (methodologies, gates, roles, phase models, in addition to Solo's existing types) demands true drop-in extensibility. Solo's existing V1 customers tolerate the central-plumbing model; Team-Orchestrator's customers won't. Team-Orchestrator's V1 implementation will be the reference for whether the auto-discovery pattern is production-ready; Solo V2 can adopt the same patterns once they're validated.

# 2026-04-26 UAT Fix Queue (post-sweep)

Working list of bugs surfaced by the in-flight regression sweep, organized by severity. Final triage will fold this into a formal TRIAGE.md after all 84 agents complete. **Do not act on this list yet** — wait for sweep completion + dedup.

## Critical (regression in already-shipped PRs)

1. **PR #19 — `init.sh --non-interactive --gov-mode production` writes `poc_mode: "production"`** to `.claude/phase-state.json`, but `process-checklist.sh:540 start_phase4` blocks any non-null poc_mode. Phase 4 unreachable for production projects via the documented happy path.
   - Confirmation: 7+ of 12 production base agents (37–48) plus production-target upgrade agents.
   - Fix at: `init.sh:3217` (mirror interactive `init.sh:381` which sets `POC_MODE=""` for Production), or alternatively `process-checklist.sh:540` (treat `production` as not-a-POC). Init.sh is the cleaner fix.
   - Worst-case workaround agents used: manual `jq` edit or `upgrade-project.sh --to-production` (which silently bumps track too).

2. **PR #17 — `upgrade-project.sh` helper-refresh aborts with RC=1** when invoked from project's own `scripts/`. The BL-009/BL-015 helper-copy block at `scripts/upgrade-project.sh:1471-1474` does `cp "$SCRIPT_DIR/$helper" "scripts/$helper"` where `$SCRIPT_DIR` resolves to the project's scripts dir → BSD `cp` "are identical (not copied)" returns non-zero → `set -euo pipefail` aborts before "Upgrade complete." Masks otherwise-successful upgrade.
   - Confirmation: 2+ upgrade agents (50, 53).
   - Fix at: `scripts/upgrade-project.sh:1471` — guard with `[ "$src" -ef "$dst" ] || cp ...`, or skip self-copy detection.

## High

3. **`mcp_server` (underscore) vs `mcp-server` (hyphen) platform-name mismatch.** init.sh constructs `docs/platform-modules/${PLATFORM}.md`, `templates/pipelines/release/<host>/${PLATFORM}.yml`, and `templates/uat/references/${PLATFORM}-pre-flight.html` using underscore; framework files ship with hyphen. Three artifact families silently skipped on every mcp_server init. verify-install.sh also looks up the underscore path → user is told to manually copy a file the framework doesn't ship.
   - Confirmation: 7-of-7 mcp_server agents (10, 11, 12, 22, 23, 24, 34, 35, 36, 46, 47, 48).
   - Fix at: choose canonical name and apply consistently. Easiest: keep `mcp_server` as the platform variable (matches `mcp_server` in code logic), rename framework files to `mcp_server.*`. Alt: keep files as `mcp-server.*` and add a single normalization step `${PLATFORM//_/-}` only at file lookup sites.

4. **`check-phase-gate.sh:449` pen-test detection fails under `set -o pipefail`** when only one of three glob patterns matches. `ls $glob1 $glob2 $glob3 2>/dev/null | wc -l` returns non-zero when one glob is empty, propagating through the pipe and failing the `if`. Full-track production projects wrongly blocked at Phase 3→4.
   - Confirmation: agent 48.
   - Fix at: `scripts/check-phase-gate.sh:449` — replace `ls` glob pipe with bash `compgen` or `shopt -s nullglob` + array length.

5. **`intake-wizard.sh` PROJECT_ROOT bug (U-G, prior-sweep open).** Line 20 `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"` — when invoked via `bash $FRAMEWORK/scripts/intake-wizard.sh`, PROJECT_ROOT resolves to the framework dir, not the project. Aborts with "PROJECT_INTAKE.md not found." Breaks the runbook's prescribed entry point for private_poc / sponsored_poc upgrades.
   - Confirmation: 4+ upgrade agents (50, 51, 53, 55).
   - Fix at: `scripts/intake-wizard.sh:20` — walk up from CWD looking for `.claude/`, like `scripts/upgrade-project.sh` already does.

6. **No working CLI path for personal → private_poc upgrade.** `intake-wizard.sh --upgrade-deployment private_poc` is rejected (only `personal|organizational` accepted); `upgrade-project.sh` only has `--to-sponsored-poc` and `--to-production`, no `--to-private-poc`.
   - Confirmation: agents 50, 51.
   - Fix at: add `--to-private-poc` flag to `scripts/upgrade-project.sh` paralleling the sponsored-poc flow.

## Medium (new, post-fix sweep)

7. **`pre-commit-gate.sh` file-classifier blocks unrecognized extensions during build_loop.** Files like `Pipfile`, `Pipfile.lock`, dependency manifests with non-doc / non-source extensions fall through to the source-file path, blocking commits even for chore: subjects. Surfaces immediately after wiring pre-commit-gate.sh into a project (lancache 2026-04-26).
   - Fix at: add a `is_dep_manifest()` helper covering `Pipfile`, `Pipfile.lock`, `requirements*.txt`, `pyproject.toml`, `Gemfile`, `Gemfile.lock`, `package.json`, `package-lock.json`, `Cargo.toml`, `Cargo.lock`, `go.sum`, `go.mod`, `poetry.lock`, etc. Treat these as docs-equivalent (allowed during build_loop) or as a third "config" class with its own policy.

8. **`init.sh --git-host github` creates real GitHub repos in user's account.** No opt-out flag. UAT/CI/agent contexts contaminate the user's repo list. Three private repos (`uat-agent-{1,2,3}`) created during the 2026-04-26 sweep before the runbook was patched to use `--git-host other`.
   - Fix at: add `--no-remote-creation` (or `--dry-remote`) flag to init.sh that skips the `gh repo create` invocation; document in `--help-non-interactive`.

9. **init.sh doesn't write `host` field to `.claude/manifest.json`** even when `--git-host` is provided. `check-gate.sh --preflight` then keeps failing.
   - Confirmation: agents 5, 14, 19, 50 (multiple).

10. **`check-gate.sh --backfill-host` requires interactive y/N confirm.** Piped non-interactive runs print success line then silently abort without writing `.host`, exit code is 0.
    - Fix at: add `--yes` flag to `scripts/check-gate.sh`.

11. **Several scripts print `[FAIL]` but `exit 0`** — breaks scripted gating.
    - `scripts/check-gate.sh --preflight` (agent 5, 20)
    - `scripts/pending-approval.sh --validate` (agents 2, 5)
    - `scripts/lint-uat-scenarios.sh` on missing-scenarios input (agent 22, 5, 53)
    - Fix at each: return non-zero on `[FAIL]` paths.

12. **`upgrade-project.sh --to-production` silently bumps track from `light` → `standard`.** Documented behavior (production = standard minimum) but undocumented in `--help` and no warning to user.
    - Fix at: emit `[WARN]` line when track is auto-bumped; document in `--help` output.

13. **`upgrade-project.sh` doesn't write `.deployment` field to `.claude/phase-state.json` after upgrade (U-J, prior-sweep open).** Banner says "Deployment: organizational" but file still says "personal." State drift.
    - Confirmation: 5+ upgrade agents.

14. **`lint-uat-scenarios.sh` false-flags `__PLACEHOLDER__` literal in `templates/uat/test-session-template.html:142`** (the comment that documents the placeholder syntax).
    - Fix at: lint should skip lines inside HTML comments; or rename the placeholder example in the template to avoid the literal token.

15. **`process-checklist.sh --verify-init` non-idempotent (U-L, prior-sweep open).** First call says "Cannot auto-verify"; second call silently auto-marks. Confirmed by agent 13.

## Lower-priority + doc gaps (defer)

- `pending-approval.sh --check` referenced in runbook doesn't exist (it's `--status`). Doc gap.
- `process-checklist.sh --help` omits `--start-phase1`, `--start-phase3`, `--start-phase4`, `--start-uat`, `--advance-phase`, etc.
- BL-006 enforcement scope (PreToolUse only, no shell-level commit-msg hook) not documented for end users — surfaces as the U-C confirmation by every agent.
- `lint-uat-scenarios.sh` doesn't have `--help`; treats `--help` as a filename argument.
- UAT_TEMPLATE doesn't document that `steps` must be a `\n`-joined string vs JSON array (lint silently misbehaves on array form).
- Phase 4 → "released" terminal state never written by any script (extends the U-D no-advance bug).

## Already-known-open from 2026-04-25 triage (still confirmed, no change needed in queue)

- **U-C**: shell-direct git commit bypasses BL-006 (every agent confirms). Documented as `BL-010` candidate in solo-orchestrator-backlog.md.
- **U-D**: no script auto-advances `.current_phase` after gate (every agent confirms). Documented as `BL-002` candidate.
- **U-K**: `test-gate.sh:122/377/411` integer-cmp errors on null/empty values.
- **U-G** (intake-wizard): see High #5 above — same root cause.
- **U-J** (upgrade deployment field): see Medium #13 above — same root cause.
- **U-L** (verify-init non-idempotent): see Medium #15 above.

## Items NOT regressed (still confirmed-fixed across sweep)

- PR #16 BL-015 sentinel reader — every agent confirms block + resolve work.
- PR #17 hook-payload `.tool_input.command` fix — every agent confirms PreToolUse path enforces.
- PR #17 BL-006 grace-window auto-reset on `feature_recorded` — every agent confirms.
- PR #17 helper-script copying (pending-approval.sh, lint-uat-scenarios.sh) — every agent confirms (U-H stays fixed).
- PR #17 upgrade-project.sh poc_mode reads from phase-state.json (U-E) — confirmed where exercised.
- PR #18 framework-self guard (U-N/U-O) — every agent confirms.
- PR #18 fake-remote tolerance (U-B) — every agent confirms.
- PR #18 prompt_choice EOF guard — confirmed (no infinite-loop reports).
- PR #19 BL-016 `--non-interactive` + `--config` + `--validate-only` — works modulo the production poc_mode regression in #1 above.
- PR #20 TEST_INTERVAL default for non-interactive path — confirmed (agents 1–84 reach Section A end).

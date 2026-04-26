# UAT 2026-04-26 — Triage & Fix Plan

**Sweep complete:** 84 / 84 agents (100% — no rate-limit issues thanks to 3-concurrent throttle).
**Framework HEAD tested:** `d66e8f276079aa352ba90ac54386e1b1896d7494` (post-PR-#20 main).
**Pre-fix runs archived:** `results/pre-fix/agent-{1,2,3}.json` — captured against `43ade85` (PR #19 pre-fix; Critical TEST_INTERVAL regression). PR #20 fixed and merged mid-sweep; agents 1–3 re-ran against fixed code.

## Headline numbers

```
Pass rate:           51 / 84 (60.7%)
Critical findings:   15 (across reports — many duplicates of same root cause)
High findings:       27
Medium findings:    167 (mostly U-C / U-D confirmations from prior sweep)
Low findings:        10
```

## Pass rate by axis

| Axis | Subset | Fail rate |
|---|---|---|
| Scenario | personal | 17% (2/12) |
| Scenario | sponsored_poc | 25% (6/24) |
| Scenario | private_poc | 50% (12/24) |
| Scenario | production | 54% (13/24) |
| Platform | desktop | 24% (5/21) |
| Platform | mobile | 33% (7/21) |
| Platform | web | 33% (7/21) |
| Platform | mcp_server | 67% (14/21) |
| Kind | base | 31% (15/48) |
| Kind | upgrade | 50% (18/36) |

The mcp_server platform and the production scenario dominate the failures; both trace to single defects.

## Tier 1 — Critical & High by root cause (must fix)

### T1-A — `init.sh:3217` writes `poc_mode="production"` for `--gov-mode production`

**Severity:** Critical (regression in PR #19 / BL-016)
**Confirmation:** ~10 base-production agents (37 was track=light and didn't reach the start-phase4 check; the rest hit it). All upgrade-to-production agents that route through `upgrade-project.sh --to-production` pass cleanly because that path correctly clears `poc_mode`.
**Root cause:** Non-interactive driver does `POC_MODE="$ARG_GOV_MODE"` unconditionally; the interactive flow at `init.sh:381` correctly maps Production → `POC_MODE=""`.
**Effect:** Every non-interactive production project is blocked at Phase 4 by `process-checklist.sh:540 start_phase4` (which rejects any non-null poc_mode).
**Fix:** In `collect_inputs_non_interactive()`, after the global var assignment block:
```bash
POC_MODE="$ARG_GOV_MODE"
[ "$POC_MODE" = "production" ] && POC_MODE=""
```
Add an integration test that does an end-to-end `--non-interactive --gov-mode production` and asserts `.claude/phase-state.json .poc_mode == null`.

### T1-B — `upgrade-project.sh:1471-1474` helper-refresh self-copy aborts upgrade

**Severity:** Critical (regression in PR #17 / U-H fix)
**Confirmation:** ~12 upgrade agents (mostly the ones that invoked the project's local `scripts/upgrade-project.sh`).
**Root cause:** The BL-009/BL-015 helper-refresh block does `cp "$SCRIPT_DIR/$helper" "scripts/$helper"`. When invoked as `bash scripts/upgrade-project.sh ...` (the documented form), `$SCRIPT_DIR` resolves to the project's own `scripts/` directory — `cp` source and dest are the same file. BSD `cp` returns non-zero with "are identical (not copied)" and `set -euo pipefail` aborts before "Upgrade complete." Functional state mutations all complete; only the wrapper signals failure.
**Fix:** Guard the copy with a same-file check:
```bash
for helper in pending-approval.sh lint-uat-scenarios.sh; do
  if [ -f "$SCRIPT_DIR/$helper" ]; then
    if [ "$SCRIPT_DIR/$helper" -ef "scripts/$helper" ]; then
      print_info "scripts/$helper is the framework copy — skipping refresh"
    else
      cp "$SCRIPT_DIR/$helper" "scripts/$helper"
      chmod +x "scripts/$helper"
      print_ok "scripts/$helper refreshed from framework"
    fi
  fi
done
```
Add a regression test that `bash scripts/upgrade-project.sh --to-production` (project-local invocation) exits 0.

### T1-C — `mcp_server` (underscore) vs `mcp-server` (hyphen) platform-name mismatch

**Severity:** High
**Confirmation:** All 14 mcp_server-failure agents; another 7 mcp_server-pass agents flagged it as Medium or doc gap (severity disagreement). Effectively 21/21 mcp_server agents observe the inconsistency; only severity grading differs.
**Root cause:** `init.sh` looks up `docs/platform-modules/${PLATFORM}.md`, `templates/pipelines/release/<host>/${PLATFORM}.yml`, and `templates/uat/references/${PLATFORM}-pre-flight.html` using underscore-form (`mcp_server`); framework files ship with hyphen-form (`mcp-server`). Three artifact families silently skipped on every mcp_server init. `verify-install.sh` then prompts user to manually copy a file the framework doesn't ship.
**Fix:** Choose canonical form and apply consistently. Recommended: keep underscore in code (matches everywhere else), rename framework files to underscore. Files to rename:
- `docs/platform-modules/mcp-server.md` → `mcp_server.md`
- `templates/pipelines/release/{github,gitlab,bitbucket}/mcp-server.yml` → `mcp_server.yml`
- `templates/uat/references/mcp-server-pre-flight.html` → `mcp_server-pre-flight.html`
- `templates/uat/references/mcp-server-scenario.json` → `mcp_server-scenario.json`

Or alternatively: keep hyphen in files, normalize at lookup with `${PLATFORM//_/-}`.

### T1-D — `intake-wizard.sh` PROJECT_ROOT bug + no personal → private_poc path

**Severity:** High (compound bug)
**Confirmation:** ~6 private_poc-target upgrade agents (49–60).
**Root cause (D1):** `intake-wizard.sh:20` hardcodes `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`. When invoked via `bash $FRAMEWORK/scripts/intake-wizard.sh`, PROJECT_ROOT resolves to the framework dir, not the project. Aborts with "PROJECT_INTAKE.md not found." Same as U-G from prior sweep.
**Root cause (D2):** Even if PROJECT_ROOT works, there's no scripted upgrade path personal → private_poc:
- `intake-wizard.sh --upgrade-deployment` only accepts `personal|organizational`.
- `upgrade-project.sh` only has `--to-sponsored-poc` and `--to-production`, no `--to-private-poc`.
**Fix (D1):** Walk up from CWD looking for `.claude/`, mirroring `scripts/upgrade-project.sh:38-49 find_project_root`.
**Fix (D2):** Add `--to-private-poc` flag to `scripts/upgrade-project.sh` paralleling the sponsored-poc flow.

### T1-E — `check-phase-gate.sh:449` pipefail bug for full-track pen-test detection

**Severity:** High
**Confirmation:** agent 48 (and possibly others where pen-test artifact stubs differed).
**Root cause:** `ls $glob1 $glob2 $glob3 2>/dev/null | wc -l` returns non-zero when one glob is empty, propagating through the pipe under `set -o pipefail`. Full-track production projects wrongly blocked at Phase 3→4 even with valid pen-test artifacts.
**Fix:** Replace with bash `compgen -G` per glob, or `shopt -s nullglob` + array-length count.

## Tier 2 — New Mediums

### T2-A — `pre-commit-gate.sh` file-classifier blocks unrecognized extensions

**Severity:** Medium (surfaced 2026-04-26 in lancache project — separate session, not in 84-agent sweep results)
**Confirmation:** 1 (live observation in lancache during BL4 DB pool work).
**Root cause:** During an active build_loop, the file classifier treats unrecognized extensions (e.g., `Pipfile`, `Pipfile.lock`) as source-equivalent and blocks the commit. Doc-exempt regex `\.(md|json|yml|yaml|toml|tmpl)$` doesn't include common dependency manifests.
**Fix:** Add `is_dep_manifest()` helper covering `Pipfile`, `Pipfile.lock`, `requirements*.txt`, `pyproject.toml`, `Gemfile`, `Gemfile.lock`, `package.json`, `package-lock.json`, `Cargo.toml`, `Cargo.lock`, `go.mod`, `go.sum`, `poetry.lock`. Treat as docs-equivalent during build_loop.

### T2-B — `init.sh --git-host github` creates real GitHub repos in user's account

**Severity:** Medium (UAT contamination, not user-facing bug)
**Confirmation:** Surfaced by agents 1–3 re-runs before runbook patched. 3 private repos (`uat-agent-{1,2,3}`) need cleanup.
**Fix:** Add `--no-remote-creation` (or `--dry-remote`) flag to init.sh that skips the `gh repo create` invocation; document in `--help-non-interactive`. Useful for CI/UAT/agent contexts.

### T2-C — `init.sh` doesn't write `host` field to `.claude/manifest.json`

**Severity:** Medium
**Confirmation:** ~5 agents (5, 14, 19, 50, 60+).
**Effect:** `check-gate.sh --preflight` keeps failing because manifest lacks the host key.
**Fix:** Have init.sh write `manifest.host` whenever `--git-host` is provided.

### T2-D — Several scripts print `[FAIL]` but `exit 0`

**Severity:** Medium
**Affected scripts:**
- `scripts/check-gate.sh --preflight` (cmd_preflight returns 1 internally; outer dispatcher case discards)
- `scripts/pending-approval.sh --validate` (prints schema error, exit 0)
- `scripts/lint-uat-scenarios.sh` on missing-scenarios input (prints "no scenarios block found", exit 0 ... or exit 2 inconsistently)
**Confirmation:** ~5 agents reported variants.
**Fix at each:** Return non-zero on `[FAIL]` paths; lint should distinguish "no input" (usage error, exit 2) from "violations found" (exit 1) from "clean" (exit 0).

### T2-E — `check-gate.sh --backfill-host` interactive-only

**Severity:** Medium
**Effect:** Piped non-interactive runs print success line then silently abort without writing `.host`, exit code 0.
**Fix:** Add `--yes` flag.

### T2-F — `upgrade-project.sh --to-production` silently bumps track from `light` → `standard`

**Severity:** Medium (documented behavior, undocumented to user)
**Fix:** Emit `[WARN]` line when track is auto-bumped; document in `--help`.

### T2-G — `upgrade-project.sh` doesn't write `.deployment` field after upgrade (U-J, prior-sweep open)

**Severity:** Medium
**Confirmation:** 5+ upgrade agents.
**Effect:** Banner says "Deployment: organizational" but phase-state.json still says "personal." State drift.

### T2-H — `lint-uat-scenarios.sh` false-flags `__PLACEHOLDER__` literal in template

**Severity:** Medium
**Affected file:** `templates/uat/test-session-template.html:142` (the comment that documents the placeholder syntax).
**Fix:** Skip lines inside HTML comments; or rename the placeholder example.

### T2-I — `process-checklist.sh --verify-init` non-idempotent (U-L, prior-sweep open)

**Severity:** Medium
**First call:** "Cannot auto-verify"; **Second call:** silently auto-marks. Confusing UX. Confirmed by agent 13.

## Tier 3 — Prior-sweep open, still confirmed (no change)

These are tracked in solo-orchestrator-backlog.md and not regressing — every agent confirms them, but they're known and have backlog entries.

| ID | Severity | Description | Backlog candidate |
|---|---|---|---|
| **U-C** | Medium | shell-direct `git commit` bypasses BL-006 | BL-010 |
| **U-D** | Medium | no script auto-advances `.current_phase` | BL-002 candidate |
| **U-K** | Medium | `test-gate.sh:122/377/411` integer-cmp errors on null/empty | own backlog item |
| **U-G** | Medium | intake-wizard.sh PROJECT_ROOT (folded into T1-D) | resolved by T1-D fix |
| **U-J** | Medium | upgrade deployment field not written (folded into T2-G) | resolved by T2-G fix |

## Tier 4 — Doc gaps (defer to a doc-only PR after fix loop)

- `pending-approval.sh --check` referenced in runbook doesn't exist (it's `--status`).
- `process-checklist.sh --help` omits `--start-phase1`, `--start-phase3`, `--start-phase4`, `--start-uat`, `--advance-phase`.
- BL-006 enforcement scope (PreToolUse only, no shell-level commit-msg hook) not documented for end users.
- `lint-uat-scenarios.sh` doesn't have `--help`; treats `--help` as a filename.
- UAT_TEMPLATE doesn't document that `steps` must be a `\n`-joined string vs JSON array.
- Phase 4 → "released" terminal state never written by any script (extends the U-D bug).

## What stayed fixed

The recent PRs all hold up under the regression sweep:
- **PR #16** BL-015 sentinel reader — every agent confirms block + resolve work.
- **PR #17** hook-payload `.tool_input.command` fix — every agent confirms PreToolUse path enforces.
- **PR #17** BL-006 grace-window auto-reset on `feature_recorded` — every agent confirms.
- **PR #17** helper-script copying (pending-approval.sh, lint-uat-scenarios.sh) — every agent confirms (U-H stays fixed).
- **PR #17** upgrade-project.sh poc_mode reads from phase-state.json (U-E) — confirmed where exercised.
- **PR #18** framework-self guard (U-N/U-O) — every agent confirms.
- **PR #18** fake-remote tolerance (U-B) — every agent confirms.
- **PR #18** prompt_choice EOF guard — confirmed (no infinite-loop reports).
- **PR #19** BL-016 `--non-interactive` + `--config` + `--validate-only` — works modulo T1-A regression.
- **PR #20** TEST_INTERVAL default for non-interactive path — confirmed (all 84 agents reach Section A end).

## Fix-loop priority ordering

Recommended ship order (each as its own PR, branch + spec/plan as warranted, regression test mandatory):

1. **PR-A** (critical, narrow): T1-A — `init.sh` clear `POC_MODE` for `--gov-mode production`. ~10-line change + 1 integration test. Unblocks Phase 4 for all production projects.
2. **PR-B** (critical, narrow): T1-B — `upgrade-project.sh` self-copy guard. ~5-line change + 1 test invoking the project-local script. Unblocks ~12 upgrade-flow agents.
3. **PR-C** (high, file rename): T1-C — mcp_server hyphen/underscore unification. Rename 6 framework files, smoke-test mcp_server platform end-to-end. Unblocks 14+ mcp_server-platform failures.
4. **PR-D** (high, two related fixes): T1-D — intake-wizard.sh PROJECT_ROOT walk-up + `upgrade-project.sh --to-private-poc` flag. ~30-line change + 2 tests.
5. **PR-E** (high, narrow): T1-E — `check-phase-gate.sh:449` pipefail-safe glob check.
6. **PR-F** (medium bundle): T2-A through T2-I — bundle the Mediums into one PR per related concern (e.g., "exit-code hygiene PR" covers T2-D; "manifest hygiene PR" covers T2-C; etc.). Aim for 2–3 bundled medium PRs.
7. **PR-G** (medium, BL-002 candidate): T2-A — pre-commit-gate.sh dep-manifest classifier. Surfaced from lancache, separate from sweep but on the queue.
8. **PR-H** (cleanup): rm 3 contamination repos `uat-agent-{1,2,3}`; backlog entry to add `--no-remote-creation` flag (T2-B).

After PR-A through PR-E land, re-run a focused regression: ~12 agents covering the production base path, mcp_server base, and upgrade-from-personal-to-private_poc. If clean, declare the post-fix sweep done and record the UAT session via test-gate.sh to reset the features_since_last_test counter.

## Files referenced

- `RUNBOOK.md` — protocol (updated mid-sweep to use `--git-host other`)
- `matrix.json` — 84 configs
- `results/agent-{1..84}.json` — per-agent reports
- `results/pre-fix/agent-{1,2,3}.json` — pre-PR-#20 (broken init) reports
- `dispatch-state.json` — dispatch tracking + runbook-fix log
- `fix-queue.md` — working notes (superseded by this triage)

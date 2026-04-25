# UAT 2026-04-25 — Triage & Fix Plan

**Reports collected:** 13 of 84 (15.5%) — pivoted from full sweep due to API rate-limit cascade. Convergence across reports was strong; marginal information from waiting for remaining 71 was small.

**Sweep characteristics:**
- 6 of 13 are base agents (Phase 0–4 end-to-end)
- 7 of 13 are upgrade agents (personal→private_poc→sponsored_poc→production)
- All 4 platforms (desktop, mobile, web, mcp_server) represented
- All 3 tracks (light, standard, full) represented
- All 4 base scenarios + all 3 upgrade transitions exercised

**Pass rate:** 1 / 13 = 7.7% (only agent 14 passed; 12 failed due to High/Critical bugs).

---

## Tier 1 — Confirmed defects (must fix)

| ID | Severity | Confirmations | Bug |
|---|---|---|---|
| **U-A** | High | 8/13 | `init.sh` has no `--non-interactive` mode; only `--dry-run` and `--help` exist. Blocks UAT, CI, scripted onboarding. |
| **U-B** | High | 5/13 | `init.sh` exits non-zero on documented happy path when `git push` to remote fails (set -euo pipefail propagates through `create_and_protect_remote`). Skips `verify-install` and `print_next_steps`. |
| **U-C** | High | 3/3 base | BL-006 enforcement bypassable via direct shell `git commit` — only fires through Claude Code's PreToolUse hook. (This is the BL-010 design we already logged.) |
| **U-D** | High | 3/3 base | No script advances `.claude/phase-state.json:.current_phase` after a phase gate passes; agents must `jq`-edit manually. `check-phase-gate.sh` is a consistency check only. |
| **U-E** | Critical | 5/5 upgrade | `scripts/upgrade-project.sh --to-production` looks for `poc_mode` in `.claude/intake-progress.json`, but `init.sh` writes it to `.claude/phase-state.json` and never creates `intake-progress.json`. Breaks the documented happy path on every fresh project. |
| **U-F** | High | 5/5 upgrade | `scripts/upgrade-project.sh` does NOT respect the BL-015 sentinel — it performs a `git commit` while `.claude/pending-approval.json` exists. Breaks the BL-015 invariant the script's own changelog claims. |
| **U-G** | High | 2/7 upgrade | `scripts/intake-wizard.sh` sets `PROJECT_ROOT="$SCRIPT_DIR/.."` (the framework directory), not the cwd. Invocations from a project dir fail with "PROJECT_INTAKE.md not found." Breaks `--upgrade-deployment` and `--resume`. |
| **U-H** | High | 1/13 | `scripts/pending-approval.sh` (BL-015) and `scripts/lint-uat-scenarios.sh` (BL-009) are NOT copied into generated projects by `init.sh`. The helpers live in the framework but never propagate; agents can't invoke `scripts/pending-approval.sh --resolve` from their generated project. Deployment defect. |
| **U-I** | Medium | 2/7 upgrade | `scripts/upgrade-project.sh` post-upgrade validation block prints literal `__PROJECT_NAME__` / `__PLATFORM__` / `__LANGUAGE__` / `__TRACK__` template-substitution placeholders. |
| **U-J** | Medium | 2/7 upgrade | `scripts/upgrade-project.sh` doesn't update `.claude/phase-state.json:.deployment` after deployment-type upgrade (only writes `.track` and `.last_upgrade`). State files drift apart. |
| **U-K** | Medium | 1/13 | `scripts/test-gate.sh:122` null integer comparison error when `test_interval` is null. |
| **U-L** | Medium | 1/13 | `scripts/process-checklist.sh --verify-init` is non-idempotent — first call says "Cannot auto-verify"; second call silently auto-marks. Confusing UX. |

## Tier 2 — Documentation gaps (12+ findings, dedupable)

- No `--to-private-poc` flag analogous to `--to-sponsored-poc` / `--to-production` (only target without a CLI mapping).
- `scripts/upgrade-project.sh --upgrade-deployment` accepts only `personal|organizational`, not `private_poc|sponsored_poc` — runbook prescribed wrong arg shape.
- `intake-wizard.sh --upgrade-to-production` and `upgrade-project.sh --to-production` are two different commands with no guidance on which to use.
- Phase 4 should be marked N/A for POC scenarios (currently confusing).
- Manual `jq`-edit path for advancing `current_phase` undocumented.
- Per-platform language list ordering undocumented (heredoc drivers can't predict the right index).

## Fix-loop priority order

Ship in 4 batches, each as a separate PR. After each PR merges, run a focused re-test on the configs that originally caught the bugs.

### Batch 1 — `init.sh` foundations (unblocks UAT and downstream fixes)
- **U-A:** add `--non-interactive` mode to `init.sh` with flags for all current prompts (`--project`, `--platform`, `--track`, `--deployment`, `--gov-mode`, `--language`, `--project-dir`).
- **U-B:** fix `set -euo pipefail` propagation when `git push` to remote fails — convert push failure into a soft warning + remediation message, NOT a script-aborting error. Allow `verify-install` and `print_next_steps` to run.
- **U-H:** add `scripts/pending-approval.sh` and `scripts/lint-uat-scenarios.sh` to init.sh's file-copy block. Plus update `scripts/upgrade-project.sh` to copy them on upgrade so existing projects pick them up.

### Batch 2 — `upgrade-project.sh` family (Critical: U-E)
- **U-E:** fix poc_mode/track/deployment lookup — read from `phase-state.json` first (canonical), fall back to `intake-progress.json`/`tool-preferences.json`.
- **U-F:** add `pa_check`-equivalent at the top of `upgrade-project.sh` — refuse to advance if `.claude/pending-approval.json` exists with valid JSON. Same enforcement layer as BL-015's pre-commit-gate side.
- **U-I:** fix template placeholder rendering — find and substitute `__PROJECT_NAME__` / `__PLATFORM__` / `__LANGUAGE__` / `__TRACK__` from current state.
- **U-J:** write `.claude/phase-state.json:.deployment` after deployment-type upgrade.

### Batch 3 — `intake-wizard.sh` + phase advancement
- **U-G:** fix `intake-wizard.sh` PROJECT_ROOT to walk from CWD up looking for `.claude/`.
- **U-D:** add `scripts/process-checklist.sh --advance-phase N` (or auto-advance from `--complete-step` when terminal step lands and gate passes).
- **U-K:** fix `scripts/test-gate.sh:122` null integer comparison.
- **U-L:** make `--verify-init` idempotent.

### Batch 4 — BL-006 / BL-010 (commit-msg git hook)
- **U-C:** install `.git/hooks/commit-msg` via init.sh; calls `process-checklist.sh --check-commit-message` from the local hook. This is BL-010 from the optional-followups; UAT promoted it from "evaluate when a concrete need arises" to "demonstrated need."

## Re-test plan after fixes ship

For each batch, re-dispatch ONLY the configs that originally caught the bugs in that batch:
- Batch 1: agents 1, 9, 14 (base) + 35 (init.sh helper-copy) — re-run.
- Batch 2: agents 79, 80, 82, 84 (upgrade) — re-run.
- Batch 3: agents 33, 57, 59, 62 — re-run.
- Batch 4: agents 1, 9 (base, BL-006 trigger) — re-run.

Total re-test: 12 agents (low rate-limit risk if dispatched in batches of 3).

## Tracking

Each Tier 1 fix becomes a backlog entry (BL-016 through BL-027) and follows the standard brainstorm → spec → plan → impl → PR workflow. Where multiple bugs share a root cause and a single PR fixes them all (e.g., the upgrade-project.sh family in Batch 2), they're bundled into one design.

# UAT Runbook — 2026-04-26 Full Matrix (Regression Re-sweep)

**Framework:** Solo Orchestrator Framework
**Framework path:** `/Users/karl/Documents/Claude Projects/solo-orchestrator`
**Framework HEAD when sweep started:** Run `git -C "$FRAMEWORK" rev-parse HEAD` and record in your report's `framework_head` field — do not hardcode any SHA from this runbook.
**Sweep:** Same 84-config matrix as 2026-04-25 (4 scenarios × 4 platforms × 3 tracks base + 3 upgrade transitions × 4 platforms × 3 tracks upgrade). This is a regression re-sweep against the framework after PRs #16–#19 landed.

---

## What changed since the 2026-04-25 sweep (read this first)

The 2026-04-25 sweep produced 14 confirmed bugs (U-A through U-O). Six PRs have shipped since:

- **PR #16** — BL-015: pending-approval sentinel reader (Solo-side complement to CDF stop-hook).
- **PR #17** — Five Critical fixes:
  - hook payload path (`.tool_input.command`, was being read as `.command`); every PreToolUse gate had been silently disabled in real Claude Code usage.
  - BL-006 between-features grace window (auto-resets on `feature_recorded`).
  - **U-H fixed**: `pending-approval.sh` and `lint-uat-scenarios.sh` now copied into generated projects by `init.sh` and by `upgrade-project.sh`.
  - **U-E fixed**: `upgrade-project.sh` reads `poc_mode` from `.claude/phase-state.json` (canonical), with fallback to `intake-progress.json`.
  - **U-F fixed**: `upgrade-project.sh` respects the BL-015 sentinel (refuses to advance when `.claude/pending-approval.json` exists).
- **PR #18** — Three small fixes:
  - `prompt_choice` EOF guard (no more infinite loop on stdin EOF).
  - **U-N + U-O fixed**: framework-self guard wired into `init.sh`, `verify-install.sh`, `upgrade-project.sh`, `intake-wizard.sh` — they refuse to operate inside the framework directory.
  - **U-B mitigated**: `init.sh` fake-remote tolerance — soft-fail on push with `check-gate.sh` remediation hints rather than `set -euo pipefail` aborting.
- **PR #19** — **U-A fixed**: BL-016 `init.sh --non-interactive` mode with full per-input flag set, JSON `--config FILE`, three-pass validation, and `--validate-only`. **Use this in your tests instead of the heredoc fallback.**

**Bugs from the 2026-04-25 triage that have NOT been fixed yet** (Batches 3 and 4 of the original fix plan): U-C (BL-006 git commit-msg hook), U-D (phase advancement script), U-G (intake-wizard PROJECT_ROOT), U-I (placeholder rendering in upgrade-project), U-J (deployment field write on upgrade), U-K (test-gate.sh null integer cmp), U-L (verify-init non-idempotent). **Don't suppress these if you encounter them — re-confirming gives us severity-by-volume signal.**

Your job is to surface (a) regressions that the recent PRs introduced, (b) confirmation that fixed bugs stay fixed, and (c) any new defects.

---

## Your role

You are a UAT test agent. Run the deterministic protocol below against the framework, capture pass/fail per assertion, and write a structured JSON report. **Do not modify the framework repo.** Do all work in a fresh tempdir.

You have access to: Bash, Read, Write, Edit, Grep, Glob. Use Bash for scripted execution; Read/Edit for inspecting/preparing project files.

---

## Setup (every agent does this first)

```bash
FRAMEWORK="/Users/karl/Documents/Claude Projects/solo-orchestrator"
WORKDIR=$(mktemp -d -t soluat-XXXXXX)
cd "$WORKDIR"

# Capture starting framework HEAD for the report.
git -C "$FRAMEWORK" rev-parse HEAD
```

**Constraints:**
- **No real network calls beyond `git remote add origin https://example.com/fake.git`.** Do not push, do not call GitHub APIs, do not invoke `gh` against a real remote. The init flow knows how to operate against a fake remote (PR #18 made fake-remote a soft-fail with remediation hints).
- **No real Semgrep/Lighthouse/coverage tools.** When a phase asks for a SAST scan, create a stub `docs/security-audits/<feature>-security-audit.md` with one Open=false finding and record "scan stubbed for UAT" in your test details.
- **Stub source files.** `echo "// stub" > src/<file>.<ext>` is acceptable; the goal is to exercise the framework's gates, not to write production code.
- **Do not modify $FRAMEWORK.** All edits stay in $WORKDIR. (PR #18 added a framework-self guard at the top of init/verify/upgrade/intake — if you accidentally `cd $FRAMEWORK` and run init.sh, it will refuse with a clear message. That's a feature, not a bug.)

---

## Output format

Write a single JSON file to:
```
$FRAMEWORK/Reports/uat-2026-04-26/results/agent-{AGENT_ID}.json
```

Schema:
```json
{
  "agent_id": 1,
  "config": {
    "kind": "base | upgrade",
    "scenario": "personal | private_poc | sponsored_poc | production",
    "platform": "desktop | mobile | web | mcp_server",
    "track": "light | standard | full",
    "upgrade_from": null | "personal" | "private_poc" | "sponsored_poc"
  },
  "framework_head": "<SHA>",
  "started_at": "ISO-8601",
  "completed_at": "ISO-8601",
  "phases": [
    {
      "phase": 0,
      "tests": [
        {"name": "init_sh_creates_phase_state_json", "pass": true, "details": "..."}
      ],
      "framework_bugs": [
        {"severity": "Critical|High|Medium|Low", "summary": "...", "reproduction": "...", "expected": "...", "actual": "..."}
      ],
      "documentation_gaps": [
        {"gap": "...", "where": "<file:line or section>"}
      ]
    }
  ],
  "overall_pass": true,
  "summary": "<one sentence>"
}
```

Emit your final line as `UAT-AGENT-COMPLETE: agent_id=N pass=true|false bugs=N gaps=N` so the orchestrator can spot completion in your output.

---

## Test protocol

Run the sections that apply to your `kind`:
- **base** (Phases 0–4 end-to-end, then UAT phase 3, then phase 4 release)
- **upgrade** (build to baseline, run upgrade, verify post-upgrade state)

### Section A — Phase 0: Discovery (all agents)

**Init driver — use `--non-interactive` (BL-016/PR #19).** Heredoc fallback is no longer the primary path.

Map your config to flags. Reference: `bash "$FRAMEWORK/init.sh" --help-non-interactive`.

```bash
cd "$WORKDIR"

# Map scenario → deployment + gov_mode
case "{SCENARIO}" in
  personal)        DEPLOY="personal"; GOV="" ;;
  private_poc)     DEPLOY="organizational"; GOV="--gov-mode private_poc" ;;
  sponsored_poc)   DEPLOY="organizational"; GOV="--gov-mode sponsored_poc" ;;
  production)      DEPLOY="organizational"; GOV="--gov-mode production" ;;
esac

# Pick a sensible language for the platform.
case "{PLATFORM}" in
  desktop)     LANG="rust" ;;
  mobile)      LANG="swift" ;;
  web)         LANG="typescript" ;;
  mcp_server)  LANG="python" ;;
esac

PROJECT="uat-agent-{AGENT_ID}"
PROJECT_DIR="$WORKDIR/$PROJECT"

# CRITICAL — DO NOT use --git-host github here. The github driver invokes
# the real `gh` CLI and creates a real repo + pushes a real commit in the
# user's GitHub account, even in a UAT/no-network test. Use --git-host other
# with a fake URL — PR #18's fake-remote tolerance lets init complete past
# the (expected) push failure.

bash "$FRAMEWORK/init.sh" --non-interactive \
    --project "$PROJECT" \
    --description "UAT agent {AGENT_ID} test project" \
    --platform "{PLATFORM}" \
    --track "{TRACK}" \
    --deployment "$DEPLOY" \
    $GOV \
    --language "$LANG" \
    --project-dir "$PROJECT_DIR" \
    --git-host other \
    --remote-url https://example.com/fake.git \
    --branch-protection-attested \
    --visibility private \
    --allow-existing-dir
INIT_RC=$?
echo "init.sh exit code: $INIT_RC"
cd "$PROJECT_DIR"
```

The init.sh push to the fake URL will fail by design; PR #18's tolerance keeps init.sh going past it (verify-install + print_next_steps still run). If you observe init.sh aborting on the push failure, that's a regression of PR #18 / U-B — record it as Critical.

If you also need an `origin` remote registered for downstream Section B/C/etc. operations (some scripts read `git remote get-url origin`), add it after init.sh completes:

```bash
git remote add origin https://example.com/fake.git 2>/dev/null || true
```

**If `init.sh --non-interactive` fails for your config:** record the failure as a `framework_bugs[]` entry with the exact stderr captured, severity `High` or `Critical` depending on whether init aborted entirely or partially completed. Do NOT silently fall back — the regression target is that --non-interactive works.

**Test cases (Section A):**

| name | assertion |
|---|---|
| init_sh_non_interactive_exits_zero | `[ $INIT_RC -eq 0 ]` |
| claude_md_created | `[ -f CLAUDE.md ]` |
| project_intake_created | `[ -f PROJECT_INTAKE.md ]` |
| approval_log_created | `[ -f APPROVAL_LOG.md ]` |
| gitignore_created | `[ -f .gitignore ]` |
| phase_state_json_phase_zero | `jq -r '.current_phase' .claude/phase-state.json` returns `0` |
| phase_state_project_set | `.project` field is non-empty |
| ci_workflow_created | `[ -f .github/workflows/ci.yml ]` (or per-host equivalent for gitlab/bitbucket) |
| release_workflow_created | `[ -f .github/workflows/release.yml ]` |
| framework_clone_present | `[ -d .claude/framework ]` |
| context7_detection | `bash $FRAMEWORK/scripts/verify-install.sh` reports Context7 detection per the install path (run from `$PROJECT_DIR`, NOT `$FRAMEWORK`) |
| platform_module_present | `[ -f docs/platform-modules/{PLATFORM}.md ]` |
| no_residual_backup_dir | `[ ! -d .claude-backup ]` (BUG-002 regression check) |
| pre_commit_gate_registered | `.claude/settings.json` includes `pre-commit-gate.sh` in PreToolUse hooks |
| stop_checklist_registered | `.claude/settings.json` includes `stop-checklist.sh` |
| pending_approval_helper_copied | `[ -f scripts/pending-approval.sh ]` (PR #17 fix; was U-H bug — should now PASS) |
| lint_uat_scenarios_helper_copied | `[ -f scripts/lint-uat-scenarios.sh ]` (PR #17 fix; was U-H bug — should now PASS) |
| framework_self_guard_active | run `bash $FRAMEWORK/init.sh --non-interactive --project x --platform web --deployment personal --language typescript` from `$FRAMEWORK` itself; expect non-zero exit and "Refusing to run inside" message in stderr (PR #18 — should now PASS) |

### Section B — Phase 1: Architecture (base agents)

```bash
bash "$FRAMEWORK/scripts/process-checklist.sh" --start-phase1
```

Then drive each Phase 1 step (`architecture_selected`, `data_contracts_drafted`, `threat_model_drafted`, etc.) by creating the required artifact (stub) and calling `--complete-step phase1_architecture:<step>`.

| name | assertion |
|---|---|
| start_phase1_exits_zero | OK |
| phase1_steps_array_present | `jq '.phase1_architecture.steps_completed' .claude/process-state.json` is array |
| each_phase1_step_completes | iterate the framework's PHASE1_STEPS array; each `--complete-step` succeeds when its required artifact exists |
| phase1_to_phase2_gate_passes | `bash $FRAMEWORK/scripts/check-phase-gate.sh` (or equivalent) passes after all steps complete |
| phase_state_advances_to_2 | after gate passes and approval is logged. **Note:** if no script auto-advances `.current_phase` (U-D bug from prior sweep is still open), record `framework_bugs[]` with severity High and `summary: "U-D regression: no script advances current_phase after gate passes"`. |

### Section C — Phase 2: Construction (base agents)

For each of 2 features (a "happy path" feature + a "BL-006 trigger" feature attempting to violate the rule):

**Feature 1 (happy path):**
```bash
bash "$FRAMEWORK/scripts/process-checklist.sh" --start-feature "uat-feat-1"
# create stub test, then mark each step
for step in tests_written tests_verified_failing implemented security_audit documentation_updated; do
  # produce stub artifact for step
  bash "$FRAMEWORK/scripts/process-checklist.sh" --complete-step "build_loop:$step"
done
# attempt commit
git add -A && git commit -m "feat(uat-1): stub feature for UAT"
bash "$FRAMEWORK/scripts/test-gate.sh" --record-feature "uat-feat-1"
bash "$FRAMEWORK/scripts/process-checklist.sh" --complete-step build_loop:feature_recorded
```

**Feature 2 (BL-006 trigger — attempt feat: commit with no Build Loop):**
```bash
# without --start-feature, attempt:
git commit --allow-empty -m "feat(bl006-trigger): no loop"
# Expected: pre-commit-gate.sh blocks via PreToolUse hook (or via the bl006_check + check-commit-message path)
# Note: U-C from prior sweep is still open — direct `git commit` bypasses BL-006. If your shell-direct
# git commit succeeds with a feat: subject and no recorded loop, that's the U-C regression confirmation,
# not a NEW bug. Record as a documentation_gap referencing BL-010 / U-C.
```

| name | assertion |
|---|---|
| start_feature_records_state | `jq '.build_loop.feature' .claude/process-state.json` = "uat-feat-1" |
| each_step_completes_in_order | sequential complete-step calls succeed |
| pre_commit_passes_after_loop | `git commit` succeeds when all 5 steps done |
| bl006_blocks_feat_without_loop | the second feat: commit attempt is blocked by the gate (when invoked through the same PreToolUse path the agent has access to). Direct shell `git commit` bypassing PreToolUse is U-C and still open. |
| bl006_grace_window_resets_after_record | After `--record-feature uat-feat-1`, attempt a NEW feat: commit (with proper Build Loop again) — gate should permit it (PR #17 fix; was a regression risk). |
| bl015_sentinel_blocks_commit | write `.claude/pending-approval.json` with valid schema, attempt commit, expect deny |
| bl015_sentinel_resolves | `scripts/pending-approval.sh --resolve`, then commit allowed (subject to bl006) |
| recorded_feature_appears_in_progress | `jq '.features_completed' .claude/build-progress.json` contains "uat-feat-1" |

### Section D — Phase 3: Validation (base agents)

```bash
bash "$FRAMEWORK/scripts/process-checklist.sh" --start-phase3
bash "$FRAMEWORK/scripts/process-checklist.sh" --start-uat 1
# walk through UAT steps, completing each
```

| name | assertion |
|---|---|
| start_phase3_exits_zero | OK |
| start_uat_creates_session | `.claude/process-state.json .uat_session.started_at` non-null |
| uat_template_lints_clean | run `scripts/lint-uat-scenarios.sh` (now in your project per PR #17) against generated UAT scenario; exits 0 |
| each_uat_step_completes | iterate UAT_STEPS, each `--complete-step uat_session:<step>` succeeds with stub artifacts |
| phase3_to_phase4_gate | gate passes |

### Section E — Phase 4: Release (base agents)

```bash
bash "$FRAMEWORK/scripts/process-checklist.sh" --start-phase4
# walk through phase4 steps
```

| name | assertion |
|---|---|
| start_phase4_exits_zero | OK |
| each_phase4_step_completes | each `--complete-step phase4_release:<step>` succeeds with stub artifacts |
| handoff_md_required | gate detects missing HANDOFF.md, prompts; gate then passes when HANDOFF.md is stubbed |
| release_notes_required | likewise |
| phase4_completion_state | `.claude/phase-state.json .current_phase` = 4 (or "released") |

### Section F — Upgrade flow (upgrade agents only)

Build to the `upgrade_from` baseline (Phase 2 minimum: completed init + at least 1 recorded feature), then:

```bash
case "{UPGRADE_TO}" in
  private_poc|sponsored_poc)
    bash "$FRAMEWORK/scripts/intake-wizard.sh" --upgrade-deployment "{TARGET_DEPLOYMENT}"
    ;;
  production)
    bash "$FRAMEWORK/scripts/upgrade-project.sh" --to-production
    ;;
esac
```

| name | assertion |
|---|---|
| upgrade_command_exits_zero | OK. **Regression target:** PR #17 fixed U-E (poc_mode lookup from phase-state.json). If this fails on a fresh project, U-E has regressed. |
| phase_state_preserved | `.current_phase` and `.project` unchanged across upgrade |
| process_state_preserved | `.build_loop` history unchanged; existing features preserved |
| new_required_artifacts_listed | upgrade output lists what new docs/checks are needed for the target scenario |
| pending_approval_sentinel_respected | write `.claude/pending-approval.json` BEFORE running upgrade; expect upgrade to refuse/warn (PR #17 U-F fix). If the upgrade plows through, U-F has regressed. |
| upgrade_changelog_present_in_script | `scripts/upgrade-project.sh` header mentions BL-015 and BL-006 changelog entries |
| no_template_placeholders_in_output | grep upgrade output for `__PROJECT_NAME__` `__PLATFORM__` `__LANGUAGE__` `__TRACK__`. If found, that's U-I and is still open (not fixed) — record as confirmation, not new bug. |

### Section G — Post-flight (every agent, after primary protocol)

| name | assertion |
|---|---|
| no_uncommitted_secrets | grep workdir for `password|api[_-]?key|secret|token` in committed files; expect 0 hits |
| log_files_consistent | `.claude/process-audit.log` exists ONLY if FORCE/reset events occurred (it's append-only on bypass events). Mark this assertion N/A if no such events occurred during your test run. |
| no_orphaned_tempfiles | `find $WORKDIR/.claude -name '*.tmp'` returns nothing |
| no_framework_contamination | `git -C "$FRAMEWORK" status --short` returns empty string AND `git -C "$FRAMEWORK" rev-parse HEAD` matches the SHA you captured at setup. If the framework was modified, the framework-self guard from PR #18 has a hole — Critical bug. |

---

## Reporting bugs

When a test fails, populate `framework_bugs[]` with:
```json
{
  "severity": "Critical|High|Medium|Low",
  "summary": "<10-word title>",
  "reproduction": "<exact commands that reproduce>",
  "expected": "<what should happen>",
  "actual": "<what actually happened>"
}
```

Severity guidance:
- **Critical:** framework script exits non-zero on a happy-path command, OR a gate that should block does not, OR a hook that should fire does not, OR a previously-fixed bug (per the "What changed" section above) has regressed.
- **High:** a phase cannot be advanced through documented procedure; a workflow step has no working artifact path.
- **Medium:** confusing error message, missing doc reference, broken link, mis-typed identifier, OR a known-open bug from the prior sweep (U-C, U-D, U-G, U-I, U-J, U-K, U-L) confirmed in your config.
- **Low:** cosmetic (color, spacing, trailing whitespace), non-critical doc gap.

When documentation is missing or wrong, populate `documentation_gaps[]`:
```json
{"gap": "<what is missing>", "where": "<file:line or section name>"}
```

If you confirm one of the still-open prior-sweep bugs, set `summary` to start with `"<U-X confirmation>"` so triage can de-duplicate quickly.

---

## Severity ratings for `overall_pass`

- `overall_pass = true` ONLY if no Critical or High bugs were found.
- Confirming a still-open prior-sweep bug at Medium severity does NOT fail the agent (it's expected).
- Medium/Low bugs and doc gaps are reported but don't fail the agent.
- If you cannot complete the protocol (e.g., framework crash blocks all subsequent steps), set `overall_pass = false` and include a top-level `aborted_at_phase` field.

---

## Ground rules summary

1. Fresh tempdir, never modify $FRAMEWORK.
2. Stub external dependencies; record what you stubbed.
3. **Use `--non-interactive` to drive init.sh — heredoc fallback only if `--non-interactive` itself fails (and that failure IS the bug to report).**
4. Output exactly one JSON file at the specified path.
5. Emit `UAT-AGENT-COMPLETE: ...` line at the end.
6. Do not stop early — even if you find a critical bug, continue testing the remaining sections to surface as much as possible in one pass.

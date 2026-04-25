# UAT Runbook — 2026-04-25 Full Matrix

**Framework:** Solo Orchestrator Framework
**Framework path:** `/Users/karl/Documents/Claude Projects/solo-orchestrator`
**Framework HEAD when sweep started:** Run `git -C "$FRAMEWORK" rev-parse HEAD` and record in your report's `framework_head` field — do not hardcode any SHA from this runbook.
**Sweep:** 84 agents covering 4 scenarios × 4 platforms × 3 tracks (48 base end-to-end) + 3 upgrade transitions × 4 platforms × 3 tracks (36 upgrade)

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
- **No real network calls beyond `git remote add origin https://example.com/fake.git`.** Do not push, do not call GitHub APIs, do not invoke `gh` against a real remote. The init flow knows how to operate against a fake remote.
- **No real Semgrep/Lighthouse/coverage tools.** When a phase asks for a SAST scan, create a stub `docs/security-audits/<feature>-security-audit.md` with one Open=false finding and record "scan stubbed for UAT" in your test details.
- **Stub source files.** `echo "// stub" > src/<file>.<ext>` is acceptable; the goal is to exercise the framework's gates, not to write production code.
- **Do not modify $FRAMEWORK.** All edits stay in $WORKDIR.

---

## Output format

Write a single JSON file to:
```
$FRAMEWORK/Reports/uat-2026-04-25/results/agent-{AGENT_ID}.json
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
        {"name": "init_sh_creates_phase_state_json", "pass": true, "details": "..."},
        ...
      ],
      "framework_bugs": [
        {"severity": "Critical|High|Medium|Low", "summary": "...", "reproduction": "...", "expected": "...", "actual": "..."}
      ],
      "documentation_gaps": [
        {"gap": "...", "where": "<file:line or section>"}
      ]
    },
    ...
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

```bash
cd "$WORKDIR"
bash "$FRAMEWORK/init.sh"   # NOTE: at repo root, NOT in scripts/
```

The hypothetical flags above (`--non-interactive`, `--project`, etc.) **do not exist** today — they're documented in this runbook to clarify what an ideal scriptable init.sh would look like. Drive the existing interactive init.sh via heredoc per the "Init driver" subsection below.

**Init driver — important:** `init.sh` is fully interactive (verified: only `--dry-run` and `--help` flags exist). It uses `prompt_input` and `prompt_choice` (in `scripts/lib/helpers.sh`) which read via `read -rp` from stdin. The sequence of prompts depends on the chosen platform, track, and deployment.

**Your task:** drive init.sh via a heredoc piping the right canned answers. Inspect `init.sh` between lines 240–500 to determine the prompt order for YOUR config. The general sequence (subject to conditional branches based on prior answers):

1. Docker install (if Docker missing) → answer: `3` (Skip) or whatever index "Skip" lands on
2. Project name → `uat-agent-{AGENT_ID}`
3. Project description → `UAT agent {AGENT_ID} test project`
4. Platform → numeric index of `{PLATFORM}` in the offered list
5. Track → numeric index of `{TRACK}` in `light`/`standard`/`full`
6. Deployment → numeric index of either `personal` or `organizational` (production/POC = organizational)
7. (If organizational) Governance mode → numeric index of `Production`/`Sponsored POC`/`Private POC`
8. Language → numeric index of a sensible language for `{PLATFORM}`
9. Project directory → an absolute path inside `$WORKDIR/uat-agent-{AGENT_ID}`

Plus install prompts for any missing dependencies (always answer to skip/decline since you can't actually install).

**If your heredoc breaks** (init.sh hangs, errors, or produces wrong output): record it as `framework_bugs[]` entry with severity `High` and `summary: "init.sh has no scriptable mode for UAT — heredoc driver fragile"`. Then fall back to bypassing init.sh by manually creating the project skeleton (mimic init.sh's outputs: copy templates from `$FRAMEWORK/templates/generated/*` into your project, write a phase-0 `.claude/phase-state.json`, create stub `.claude/process-state.json`, etc.), and continue testing the OTHER phases. Note this fallback in your report's `documentation_gaps[]`.

The "init.sh isn't scriptable" gap is expected to be reported by many agents — that's the design intent: surface it as a real finding, not a per-agent excuse to skip.

**Test cases (Section A):**

| name | assertion |
|---|---|
| init_sh_exits_zero | `echo $?` is 0 |
| claude_md_created | `[ -f CLAUDE.md ]` |
| project_intake_created | `[ -f PROJECT_INTAKE.md ]` |
| approval_log_created | `[ -f APPROVAL_LOG.md ]` |
| gitignore_created | `[ -f .gitignore ]` |
| phase_state_json_phase_zero | `jq -r '.current_phase' .claude/phase-state.json` returns `0` |
| phase_state_project_set | `.project` field is non-empty |
| ci_workflow_created | `[ -f .github/workflows/ci.yml ]` (or per-host equivalent for gitlab/bitbucket) |
| release_workflow_created | `[ -f .github/workflows/release.yml ]` |
| framework_clone_present | `[ -d .claude/framework ]` |
| context7_detection | `bash $FRAMEWORK/scripts/verify-install.sh` reports Context7 detection per the install path |
| platform_module_present | `[ -f docs/platform-modules/{PLATFORM}.md ]` |
| no_residual_backup_dir | `[ ! -d .claude-backup ]` (BUG-002 regression check) |
| pre_commit_gate_registered | `.claude/settings.json` includes `pre-commit-gate.sh` in PreToolUse hooks |
| stop_checklist_registered | `.claude/settings.json` includes `stop-checklist.sh` |

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
| phase_state_advances_to_2 | after gate passes and approval is logged |

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
```

| name | assertion |
|---|---|
| start_feature_records_state | `jq '.build_loop.feature' .claude/process-state.json` = "uat-feat-1" |
| each_step_completes_in_order | sequential complete-step calls succeed |
| pre_commit_passes_after_loop | `git commit` succeeds when all 5 steps done |
| bl006_blocks_feat_without_loop | the second feat: commit attempt is blocked by the gate (when invoked through the same PreToolUse path the agent has access to) |
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
| uat_template_lints_clean | run `scripts/lint-uat-scenarios.sh` against generated UAT scenario; exits 0 |
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
| upgrade_command_exits_zero | OK |
| phase_state_preserved | `.current_phase` and `.project` unchanged across upgrade |
| process_state_preserved | `.build_loop` history unchanged; existing features preserved |
| new_required_artifacts_listed | upgrade output lists what new docs/checks are needed for the target scenario |
| pending_approval_sentinel_respected | if a sentinel exists, upgrade refuses or warns rather than blasting through |
| upgrade_changelog_present_in_script | `scripts/upgrade-project.sh` header mentions BL-015 and BL-006 changelog entries |

### Section G — Post-flight (every agent, after primary protocol)

| name | assertion |
|---|---|
| no_uncommitted_secrets | grep workdir for `password|api[_-]?key|secret|token` in committed files; expect 0 hits |
| log_files_consistent | `.claude/process-audit.log` exists ONLY if FORCE/reset events occurred (it's append-only on bypass events). Mark this assertion N/A if no such events occurred during your test run. |
| no_orphaned_tempfiles | `find $WORKDIR/.claude -name '*.tmp'` returns nothing |

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
- **Critical:** framework script exits non-zero on a happy-path command, OR a gate that should block does not, OR a hook that should fire does not.
- **High:** a phase cannot be advanced through documented procedure; a workflow step has no working artifact path.
- **Medium:** confusing error message, missing doc reference, broken link, mis-typed identifier.
- **Low:** cosmetic (color, spacing, trailing whitespace), non-critical doc gap.

When documentation is missing or wrong, populate `documentation_gaps[]`:
```json
{"gap": "<what is missing>", "where": "<file:line or section name>"}
```

---

## Severity ratings for `overall_pass`

- `overall_pass = true` ONLY if no Critical or High bugs were found.
- Medium/Low bugs and doc gaps are reported but don't fail the agent.
- If you cannot complete the protocol (e.g., framework crash blocks all subsequent steps), set `overall_pass = false` and include a top-level `aborted_at_phase` field.

---

## Ground rules summary

1. Fresh tempdir, never modify $FRAMEWORK.
2. Stub external dependencies; record what you stubbed.
3. Drive scripts non-interactively where possible; if you must use heredocs/canned answers, record the technique used.
4. Output exactly one JSON file at the specified path.
5. Emit `UAT-AGENT-COMPLETE: ...` line at the end.
6. Do not stop early — even if you find a critical bug, continue testing the remaining sections to surface as much as possible in one pass.

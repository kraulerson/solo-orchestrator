# Phase 2 Remediation Plan
## Construction

**Date:** 2026-04-08
**Audit Reference:** `Reports/phase-audits/2026-04-08-phase-2-audit.md`
**Findings Count:** 28 (2 Critical, 11 Major, 11 Minor, 4 Observation)
**Remediation Author:** Engineering Manager (Phase 2 Auditor)

---

## Executive Summary

Phase 2 (Construction) carries the highest finding count of any phase: 28 findings across 8 categories. Two findings are Critical, both representing gaps that would prevent an enterprise auditor from certifying the build process: security audit findings have no storage or tracking (P2-006), and the Phase 2-to-3 gate does not verify that the MVP was actually built (P2-022). Eleven Major findings expose bypass paths in the PreToolUse hook, audit trail destruction on reset, and governance checkpoints that produce no artifact.

Three structural patterns account for most of the severity:

1. **Self-attestation without evidence.** The process-checklist.sh enforces step ordering but not step content. `security_audit`, `data_model_applied`, and most completion checklist items can be marked done without producing any artifact.
2. **PreToolUse detection gaps.** The commit gate intercepts `git commit` and `gh pr create` but misses `--no-verify`, `--amend`, `git push --force`, and non-standard command formats. Three findings (P2-009, P2-010, P2-027) share this root cause.
3. **Gate incompleteness.** The Phase 2-to-3 gate checks only bug severity. It does not verify feature completeness, CI status, test pass rate, Bible currency, or 9 other items from the Builder's Guide completion checklist.

This document groups findings by root cause, specifies concrete file-level changes, estimates effort, defines verification tests, and assigns implementation priority. All changes are backward-compatible and non-destructive to existing projects.

---

## Table of Contents

1. [Remediation Groups](#1-remediation-groups)
   - [RG-1: Security Audit Evidence Chain (Critical)](#rg-1-security-audit-evidence-chain)
   - [RG-2: Phase 2-to-3 Gate Completeness (Critical)](#rg-2-phase-2-to-3-gate-completeness)
   - [RG-3: PreToolUse Detection Gaps (Major)](#rg-3-pretooluse-detection-gaps)
   - [RG-4: Initialization Verification Flaws (Major)](#rg-4-initialization-verification-flaws)
   - [RG-5: Audit Trail Preservation (Major)](#rg-5-audit-trail-preservation)
   - [RG-6: UAT Workflow Consistency (Major)](#rg-6-uat-workflow-consistency)
   - [RG-7: Context Health Check Elevation (Major)](#rg-7-context-health-check-elevation)
   - [RG-8: Governance Checkpoint Artifacts (Major)](#rg-8-governance-checkpoint-artifacts)
   - [RG-9: Minor Process and Template Fixes](#rg-9-minor-process-and-template-fixes)
   - [RG-10: Observations (Monitor, Do Not Remediate)](#rg-10-observations)
2. [Implementation Schedule](#2-implementation-schedule)
3. [Verification Test Plan](#3-verification-test-plan)
4. [Risk Assessment](#4-risk-assessment)
5. [Appendix: Finding-to-Group Cross-Reference](#5-appendix-finding-to-group-cross-reference)

---

## 1. Remediation Groups

### RG-1: Security Audit Evidence Chain

**Severity:** Critical
**Findings:** P2-006
**Root Cause:** The `security_audit` build loop step is a binary flag. No findings report is generated, no storage location is defined, no resolution tracking exists. An auditor asked "show me the per-feature security audit results" would receive nothing.
**Enterprise Impact:** Largest single compliance gap in Phase 2. Renders the per-feature security audit unverifiable, which voids the framework's claim of continuous security validation during construction.

#### Current State

```
# process-checklist.sh — build loop step "security_audit"
# Agent runs: scripts/process-checklist.sh --complete-step build_loop:security_audit
# Result: step added to steps_completed array. No artifact check. No evidence persisted.
```

Builder's Guide Step 2.4 prescribes a detailed audit (SAST, threat model review, 5-point checklist, parallel agent dispatch) but the process enforcement treats it as a binary attestation. There is no template for findings output, no canonical storage directory, and no linkage from the step completion to the evidence that supports it.

#### Remediation

**R-1.1: Create security audit findings template.**

Create `templates/generated/security-audit.tmpl`:

```markdown
# Security Audit — [FEATURE_NAME]

**Date:** [YYYY-MM-DD]
**Feature:** [Feature name from --start-feature]
**Build Loop:** [Feature number in build sequence]
**Auditor:** [Agent or persona name]

## Audit Scope

| Check | Result | Notes |
|-------|--------|-------|
| SAST scan (Semgrep) | PASS / FAIL / N/A | |
| Threat model review (Phase 1.3) | PASS / FAIL / N/A | |
| Data isolation test | PASS / FAIL / N/A | |
| Input validation test | PASS / FAIL / N/A | |
| Hardcoded secrets check | PASS / FAIL / N/A | |
| Logging verification | PASS / FAIL / N/A | |
| Platform-specific checks | PASS / FAIL / N/A | |

## Findings

| # | Severity | Description | File(s) | Remediation | Status |
|---|----------|-------------|---------|-------------|--------|
| 1 | | | | | Open / Fixed |

## Resolution Summary

- **Findings found:** [count]
- **Findings fixed:** [count]
- **Findings deferred:** [count] (with justification)
- **All tests pass after remediation:** Yes / No
```

**R-1.2: Define canonical storage directory.**

Security audit reports are stored in `docs/security-audits/` with the naming convention `[YYYY-MM-DD]_[feature-name]_security-audit.md`. This directory is created by `init.sh` during project initialization.

Add to `init.sh` project scaffolding:
```bash
mkdir -p docs/security-audits
```

Add to Builder's Guide Step 2.4 instructions:
```
Save the completed audit report to docs/security-audits/[date]_[feature-name]_security-audit.md.
```

**R-1.3: Add artifact existence check to `complete_step()`.**

In `scripts/process-checklist.sh`, add a conditional check when `step_id` is `security_audit`: verify that at least one file matching `docs/security-audits/*_security-audit.md` was modified more recently than the build loop's `started_at` timestamp. If no qualifying file exists, block the step completion with a message directing the agent to create the audit report.

Implementation in `complete_step()` after the ordering check passes:

```bash
# Artifact verification for high-value steps
if [ "$process" = "build_loop" ] && [ "$step_id" = "security_audit" ]; then
  local feature_name
  feature_name=$(jq -r '.build_loop.feature // "unknown"' "$PROCESS_STATE")
  local audit_files
  audit_files=$(find docs/security-audits/ -name "*_security-audit.md" -newer "$PROCESS_STATE" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$audit_files" -eq 0 ]; then
    print_fail "No security audit report found for this build loop."
    echo "Create the audit report using the template:" >&2
    echo "  Template: templates/generated/security-audit.tmpl" >&2
    echo "  Save to:  docs/security-audits/$(date +%Y-%m-%d)_${feature_name}_security-audit.md" >&2
    exit 1
  fi
fi
```

**R-1.4: Update CLAUDE.md template.**

Add to the Construction Rules section of `templates/generated/claude-md.tmpl`:

```
  - Security audit report: `scripts/process-checklist.sh --complete-step build_loop:security_audit`
    **Requires:** A completed security audit report in `docs/security-audits/`.
    Use `templates/generated/security-audit.tmpl` as the template.
```

**R-1.5: Update Builder's Guide Step 2.4.**

Add after the existing "Process checkpoint" line:

```
**Audit artifact:** Save the completed audit report to `docs/security-audits/[date]_[feature-name]_security-audit.md`
using `templates/generated/security-audit.tmpl`. The process checkpoint will not accept completion without this artifact.
```

#### Files Modified

| File | Change |
|------|--------|
| `templates/generated/security-audit.tmpl` | New file (template) |
| `scripts/process-checklist.sh` | Add artifact check in `complete_step()` |
| `init.sh` | Add `docs/security-audits/` to scaffold |
| `templates/generated/claude-md.tmpl` | Add audit artifact instruction |
| `docs/builders-guide.md` | Add artifact requirement to Step 2.4 |

#### Effort Estimate

4-6 hours. Template creation is straightforward. The `complete_step()` modification requires careful testing to avoid false negatives (timestamp comparison edge cases).

---

### RG-2: Phase 2-to-3 Gate Completeness

**Severity:** Critical
**Findings:** P2-022, P2-024, P2-028
**Root Cause:** The Phase 2-to-3 transition -- described by the Governance Framework as "the most consequential gate" -- has the least mechanical enforcement of any gate. `test-gate.sh --check-phase-gate` checks only bug severity/status. It does not verify feature completeness, CI pipeline status, test pass rate, Bible currency, or any other completion checklist item. `process-checklist.sh` has no Phase 2 completion process. `check-phase-gate.sh` does not check the 2-to-3 gate at all.
**Enterprise Impact:** An organization relying on this gate could transition to Phase 3 with half the MVP unbuilt and no detection. The bug check is necessary but grossly insufficient.

#### Current State

The Phase 2 Completion Checkpoint (Builder's Guide lines 1021-1035) prescribes 11 verification items:

| # | Item | Current Enforcement |
|---|------|-------------------|
| 1 | All MVP Cutline features built and passing tests | None |
| 2 | No partially implemented features | None |
| 3 | Full test suite passes | None |
| 4 | CI pipeline green | None |
| 5 | Project Bible accurately reflects current codebase | None |
| 6 | CHANGELOG.md current | CI warning (Tier 1.5) |
| 7 | No unresolved security findings | None |
| 8 | Application builds on all target platforms | None |
| 9 | All UAT testing sessions completed | None |
| 10 | No open SEV-1 or SEV-2 bugs | `test-gate.sh --check-phase-gate` (Tier 2) |
| 11 | Bug triage complete | None |

Only item 10 has mechanical enforcement. Item 6 has a CI warning. The remaining 9 items are pure attestation.

#### Remediation

**R-2.1: Add `phase2_completion` process to `process-checklist.sh`.**

Add a new step array:

```bash
PHASE2_COMPLETION_STEPS=(
  features_complete        # Verify FEATURES.md against MVP Cutline
  test_suite_passes        # Verify test suite exit code
  ci_pipeline_green        # Verify CI status via gh CLI
  security_findings_clear  # Verify no open findings in docs/security-audits/
  uat_sessions_complete    # Verify all required UAT sessions completed
  bug_gate_passed          # Verify test-gate.sh --check-phase-gate passes
  bible_current            # Verify PROJECT_BIBLE.md Last Updated markers
  documentation_current    # Verify CHANGELOG.md and FEATURES.md
  platform_builds_verified # Attestation: builds on all target platforms
  orchestrator_signoff     # Attestation: Orchestrator confirms readiness
)
```

Add `--start-phase2-completion` action that initializes this process. Add corresponding case to `get_steps_for_process()`.

**R-2.2: Add feature completeness check to `test-gate.sh --check-phase-gate`.**

After the existing bug gate checks, add a feature completeness section:

```bash
# Feature completeness check
if [ -f "FEATURES.md" ]; then
  local feature_count
  feature_count=$(grep -cE '^##[^#]' "FEATURES.md" 2>/dev/null || echo "0")
  if [ "$feature_count" -eq 0 ]; then
    print_fail "FEATURES.md exists but contains no feature entries"
    blocked=true
  else
    print_ok "FEATURES.md contains $feature_count feature(s)"
  fi

  # Cross-check against build-progress.json
  local recorded_features
  recorded_features=$(jq -r '.features_completed | length' "$BUILD_PROGRESS" 2>/dev/null || echo "0")
  if [ "$recorded_features" -eq 0 ]; then
    print_fail "No features recorded in build-progress.json (run test-gate.sh --record-feature after each feature)"
    blocked=true
  elif [ "$recorded_features" -ne "$feature_count" ]; then
    print_warn "Feature count mismatch: $feature_count in FEATURES.md vs $recorded_features recorded in build-progress.json"
    warnings=true
  else
    print_ok "Feature count consistent: $feature_count documented, $recorded_features recorded"
  fi
else
  print_fail "FEATURES.md not found — feature completeness cannot be verified"
  blocked=true
fi
```

Note: A fully mechanical Cutline-to-FEATURES.md reconciliation would require parsing the Manifesto's Cutline section. This is fragile across project formats. The feature count cross-check between FEATURES.md and build-progress.json is the pragmatic first step. A future enhancement can add Cutline parsing if the template stabilizes.

**R-2.3: Add Phase 2-to-3 gate to `check-phase-gate.sh`.**

Add a `gate_2_to_3` section that verifies:
- APPROVAL_LOG.md contains a Phase 2-to-3 entry with populated fields
- `test-gate.sh --check-phase-gate` returns exit code 0
- FEATURES.md exists and is non-empty
- `.claude/process-state.json` shows all build loop and UAT processes resolved (not mid-process)

**R-2.4: Wire `--start-phase3` to verify Phase 2 prerequisites.**

In `process-checklist.sh`, modify `start_phase3()` to run `test-gate.sh --check-phase-gate` internally and block if it fails:

```bash
start_phase3() {
  ensure_state_file

  # Verify Phase 2 gate before allowing Phase 3 entry
  local gate_output gate_exit
  gate_output=$("$SCRIPT_DIR/test-gate.sh" --check-phase-gate 2>&1) || gate_exit=$?
  if [ "${gate_exit:-0}" -eq 1 ]; then
    print_fail "Cannot start Phase 3 — Phase 2 gate check failed:"
    echo "$gate_output" >&2
    exit 1
  fi

  # ... existing phase3 initialization ...
}
```

**R-2.5: Add mechanical checks for verifiable completion items.**

For each completion checklist item that can be mechanically verified, add a check to the `phase2_completion` process's `complete_step()` handler:

| Step | Mechanical Check |
|------|-----------------|
| `features_complete` | FEATURES.md section count matches build-progress.json recorded features |
| `test_suite_passes` | Agent must run test suite and report exit code before marking complete |
| `ci_pipeline_green` | `gh run list --limit 1 --json conclusion` returns `"success"` |
| `security_findings_clear` | No `Status: Open` entries in `docs/security-audits/*.md` |
| `uat_sessions_complete` | `build-progress.json` `.features_since_last_test` is 0 |
| `bug_gate_passed` | `test-gate.sh --check-phase-gate` exit code 0 |
| `bible_current` | PROJECT_BIBLE.md `Last Updated` marker within 7 days |
| `documentation_current` | CHANGELOG.md modified within last 5 commits |
| `platform_builds_verified` | Attestation (no mechanical check feasible) |
| `orchestrator_signoff` | Attestation (human gate) |

#### Files Modified

| File | Change |
|------|--------|
| `scripts/process-checklist.sh` | Add `phase2_completion` process, prerequisite check in `start_phase3()` |
| `scripts/test-gate.sh` | Add feature completeness check to `--check-phase-gate` |
| `scripts/check-phase-gate.sh` | Add `gate_2_to_3` section |
| `docs/builders-guide.md` | Update Phase 2 Completion Checkpoint with process commands |
| `templates/generated/claude-md.tmpl` | Add Phase 2 completion process instructions |

#### Effort Estimate

6-8 hours. The `phase2_completion` process is the most complex addition: 10 steps with varying levels of mechanical verification. The `check-phase-gate.sh` addition is moderate. Feature completeness parsing requires defensive coding for varied FEATURES.md formats.

---

### RG-3: PreToolUse Detection Gaps

**Severity:** Major
**Findings:** P2-009, P2-010, P2-027
**Root Cause:** `pre-commit-gate.sh` uses a narrow regex (`^\s*git\s+commit`) that intercepts standard `git commit` and `gh pr create` commands but misses variations that bypass security hooks or destroy audit evidence.
**Enterprise Impact:** The agent could use `git commit --no-verify` to skip gitleaks and Semgrep pre-commit hooks, `git commit --amend` to overwrite audit evidence, or `git push --force` to rewrite remote history. The CI pipeline is the backstop for security scanning, but amended commits and force pushes erode the audit trail that CI relies on.

#### Current State

```bash
# pre-commit-gate.sh line 29-31
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  IS_COMMIT=true
elif echo "$COMMAND" | grep -qE '^\s*gh\s+pr\s+create'; then
  IS_PR=true
fi
```

This pattern catches:
- `git commit -m "message"` -- detected
- `git commit --no-verify -m "message"` -- detected as a commit, but the `--no-verify` flag is not separately flagged
- `git commit --amend` -- detected as a commit, but the `--amend` flag is not separately flagged
- `git push --force` -- not detected at all
- `git push --force-with-lease` -- not detected at all
- `git -c user.name=... commit` -- not detected (fails `^\s*git\s+commit` because of `-c` between `git` and `commit`)
- `env VAR=val git commit` -- not detected (fails due to `env` prefix)

#### Remediation

**R-3.1: Detect and deny `--no-verify` on any git command.**

Add to `pre-commit-gate.sh` after the existing command extraction:

```bash
# Detect --no-verify on any git command (P2-009)
if echo "$COMMAND" | grep -qE '\bgit\b.*--no-verify'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "--no-verify bypasses pre-commit security hooks (gitleaks, Semgrep). Remove --no-verify and commit normally. If hooks are failing, fix the underlying issue."}}
HOOKEOF
  exit 0
fi
```

**R-3.2: Detect and warn on `--amend`.**

Add detection for `git commit --amend`. This should warn rather than deny, because legitimate amend use cases exist (fixing typos in the previous commit message before pushing). However, the warning must be clear that amending bypasses build loop verification for the amended content.

```bash
# Detect --amend on git commit (P2-010)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--amend'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "WARNING: git commit --amend rewrites the previous commit. Amended content bypasses build loop verification. The Orchestrator should review the amended changes. If amending to add content that was not in the original commit, consider creating a new commit instead."}}
HOOKEOF
  exit 0
fi
```

**R-3.3: Detect and deny `git push --force` and `--force-with-lease`.**

```bash
# Detect force push (P2-010)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b.*(--force\b|--force-with-lease|-f\b)'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Force push rewrites remote history and destroys audit evidence. Use normal push. If the remote rejects your push, resolve the conflict with git pull --rebase, then push normally. Only the Orchestrator may authorize force push in exceptional circumstances."}}
HOOKEOF
  exit 0
fi
```

**R-3.4: Broaden git command detection pattern.**

Replace the narrow `^\s*git\s+commit` pattern with a more robust detection that handles prefixed commands:

```bash
# Broadened detection (P2-027)
IS_COMMIT=false
IS_PR=false
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b'; then
  IS_COMMIT=true
elif echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bcreate\b'; then
  IS_PR=true
fi
```

The `\b` word boundary anchors catch `git commit` regardless of what precedes `git` (env, sudo, path prefix) or what appears between `git` and `commit` (config flags). This is intentionally broader than the current pattern.

**R-3.5: Order of operations.**

The deny checks (R-3.1, R-3.3) must execute before the process-checklist check. The amend warning (R-3.2) should execute after the process-checklist check (so the amend is also subject to process gate enforcement). The broadened detection (R-3.4) replaces the existing pattern and must be applied first.

Final hook execution order:
1. Extract command from JSON
2. Check for `--no-verify` -- deny immediately
3. Check for `--force` push -- deny immediately
4. Broadened git commit / gh pr create detection
5. Process-checklist check (existing logic)
6. Check for `--amend` -- warn if present
7. Tool usage warnings (existing logic)

#### Files Modified

| File | Change |
|------|--------|
| `scripts/pre-commit-gate.sh` | Add `--no-verify`, `--amend`, `--force` detection; broaden regex |
| `docs/user-guide.md` | Update Tier 2 table to reflect new detections |
| `docs/builders-guide.md` | Update "Never" list in Step 2.4 to reference hook enforcement |

#### Effort Estimate

1-2 hours. All changes are regex additions to a single file. Testing requires verifying each pattern against representative command strings.

---

### RG-4: Initialization Verification Flaws

**Severity:** Major
**Findings:** P2-001, P2-002, P2-003
**Root Cause:** The `verify_init()` function in `process-checklist.sh` was written as a convenience shortcut that bypasses the sequential enforcement model used by every other process. Three consequences: steps are appended directly to `steps_completed` without routing through `complete_step()` (P2-001), `data_model_applied` has no verification criteria (P2-002), and `initialization_verified` has no completion path (P2-003).
**Enterprise Impact:** Initialization steps can be marked complete out of order, and the 7th step (`initialization_verified`) leaves users at a dead-end with no guidance.

#### Current State

```bash
# verify_init() — appends directly to steps_completed, bypassing complete_step()
jq '.phase2_init.steps_completed += ["remote_repo_created"]' "$PROCESS_STATE" > ...
```

The `complete_step()` function enforces ordering by checking all prior steps. `verify_init()` bypasses this entirely, appending steps directly via jq. The `data_model_applied` step prints a manual completion command but has no evidence requirement. The `initialization_verified` step is the 7th step in `PHASE2_INIT_STEPS` but is never auto-completed and no instruction is printed telling the user how to mark it.

#### Remediation

**R-4.1: Route auto-verified steps through `complete_step()`.**

Replace the direct jq appends in `verify_init()` with calls to the existing `complete_step()` function. This ensures ordering enforcement applies to init steps just as it does to build loop steps.

```bash
# Instead of:
jq '.phase2_init.steps_completed += ["remote_repo_created"]' "$PROCESS_STATE" > ...

# Use:
complete_step "phase2_init:remote_repo_created" 2>/dev/null || true
```

The `2>/dev/null || true` suppresses the "already completed" message for idempotent re-runs. The ordering check in `complete_step()` will now prevent out-of-order completion.

**R-4.2: Add verification criteria for `data_model_applied`.**

Add a check for evidence of data model work. Since data model technology varies by project, the check should verify that at least one of the following conditions is met:
- A migration file exists (common patterns: `migrations/`, `prisma/migrations/`, `alembic/versions/`, `db/migrate/`)
- The agent attests that no data model applies to this project (e.g., static site, CLI tool)
- A file `docs/data-model-verification.md` exists documenting the verification

```bash
# In verify_init(), for data_model_applied:
local has_migrations=false
for dir in migrations prisma/migrations alembic/versions db/migrate src/migrations; do
  if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
    has_migrations=true
    break
  fi
done

if [ "$has_migrations" = true ]; then
  print_ok "data_model_applied — migration directory found"
  complete_step "phase2_init:data_model_applied" 2>/dev/null || true
else
  print_warn "data_model_applied — cannot auto-verify."
  echo "  If this project has a data model: verify migrations, rollback, and backup/restore." >&2
  echo "  If no data model applies: create docs/data-model-verification.md with justification." >&2
  echo "  Then mark complete: scripts/process-checklist.sh --complete-step phase2_init:data_model_applied" >&2
fi
```

**R-4.3: Auto-complete `initialization_verified` when all 6 other steps are done.**

After the loop that checks all steps, add:

```bash
# Auto-complete initialization_verified when all 6 preceding steps are done
local other_steps_done=true
for step in "${PHASE2_INIT_STEPS[@]}"; do
  [ "$step" = "initialization_verified" ] && continue
  if ! step_is_completed "phase2_init" "$step"; then
    other_steps_done=false
    break
  fi
done

if [ "$other_steps_done" = true ]; then
  complete_step "phase2_init:initialization_verified" 2>/dev/null || true
  jq '.phase2_init.verified = true' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
  print_ok "Phase 2 initialization fully verified (all 7 steps complete)"
else
  print_warn "Phase 2 initialization incomplete — complete remaining steps above."
  echo "  Once all 6 prerequisite steps are complete, run --verify-init again to finalize." >&2
fi
```

#### Files Modified

| File | Change |
|------|--------|
| `scripts/process-checklist.sh` | Refactor `verify_init()`: route through `complete_step()`, add migration check, auto-complete 7th step |

#### Effort Estimate

2-3 hours. The refactor is contained within a single function. Testing requires verifying ordering enforcement, idempotent re-runs, and the migration directory detection across project types.

---

### RG-5: Audit Trail Preservation

**Severity:** Major
**Findings:** P2-008
**Root Cause:** The `reset_process()` and `reset_all()` functions in `process-checklist.sh` log reset events to stderr only. There is no persistent audit file. A reset destroys the process state and leaves no durable record.
**Enterprise Impact:** An agent (or user) can call `--reset-all`, clear all process state, and restart. The only evidence is ephemeral terminal output. This creates a bypass vector with no audit trail.

#### Current State

```bash
# process-checklist.sh line 647
echo "[RESET] Process $process reset at $now" >&2
```

The reset event is emitted to stderr, which is visible in the terminal but not captured in any persistent file. If the terminal session ends, the reset evidence is lost.

#### Remediation

**R-5.1: Create persistent audit log.**

Define a persistent audit log at `.claude/process-audit.log`. All resets, state transitions, and bypass events are appended to this file.

```bash
AUDIT_LOG=".claude/process-audit.log"

audit_event() {
  local event_type="$1"
  local detail="$2"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p .claude
  echo "[$now] $event_type: $detail" >> "$AUDIT_LOG"
}
```

**R-5.2: Log resets with context.**

In `reset_process()` and `reset_all()`:

```bash
reset_process() {
  ensure_state_file
  local process="$1"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Capture current state before reset for audit purposes
  local state_before
  state_before=$(jq -r ".${process}" "$PROCESS_STATE" 2>/dev/null)
  
  audit_event "RESET" "process=$process state_before=$state_before"

  # ... existing reset logic ...
}
```

**R-5.3: Add interactive confirmation for resets.**

Prevent the agent from calling `--reset` and `--reset-all` without human intervention:

```bash
reset_process() {
  ensure_state_file
  local process="$1"

  # Interactive confirmation — blocks agent from resetting autonomously
  echo -e "${YELLOW}[CONFIRM]${NC} Reset process '$process'? This clears all progress."
  echo "  Only the Orchestrator should authorize a reset."
  read -rp "  Type 'RESET' to confirm: " confirmation
  if [ "$confirmation" != "RESET" ]; then
    print_fail "Reset cancelled."
    exit 1
  fi

  # ... proceed with reset ...
}
```

This is effective because Claude Code agents cannot provide interactive terminal input to `read -rp` prompts. Only the human operator can type the confirmation. If the agent attempts `--reset`, the script blocks waiting for input, which the agent cannot provide.

**R-5.4: Log step completions to audit log.**

Add an `audit_event` call in `complete_step()` to record every step completion:

```bash
audit_event "STEP_COMPLETE" "process=$process step=$step_id ($new_step_num/${#steps[@]})"
```

**R-5.5: Commit `.claude/process-audit.log` as part of the project.**

Add to `.gitignore` comments that this file should NOT be ignored. Add a note to CLAUDE.md template that the audit log is a governance artifact.

#### Files Modified

| File | Change |
|------|--------|
| `scripts/process-checklist.sh` | Add `audit_event()`, log resets and step completions, add interactive confirmation |
| `templates/generated/claude-md.tmpl` | Note audit log as governance artifact |

#### Effort Estimate

2-3 hours. The audit logging is straightforward append-only writes. The interactive confirmation requires testing to verify it blocks agent invocation.

---

### RG-6: UAT Workflow Consistency

**Severity:** Major
**Findings:** P2-013, P2-014, P2-015, P2-016, P2-017
**Root Cause:** The UAT workflow has five independent issues that collectively degrade its reliability: conflicting archive locations across documents, missing traceability columns in BUGS.md, commit blocking during UAT remediation, markdown escaping gaps in the HTML template, and ambiguous template selection guidance.
**Enterprise Impact:** UAT evidence may be stored in inconsistent locations, bug-to-fix traceability is incomplete, and the agent has conflicting instructions on which template to use and where to store results.

#### Remediation

**R-6.1: Align UAT paths across all documents (P2-013).**

Establish the canonical directory structure:

```
tests/uat/
  templates/                    # Template files (HTML and Markdown)
    test-session-template.html  # Primary template (interactive)
    test-session-template.md    # Fallback template (text-only)
  sessions/
    <date>-session-N/
      templates/                # Pre-populated session-specific templates
      agent-results/            # Agent test output
      submissions/              # Human tester submissions
```

Archive location after review: `docs/test-results/[date]_uat-session-N-vX.html`

Update these files to use the canonical paths:
- `docs/builders-guide.md` (Step 2.7): already correct
- `templates/generated/claude-md.tmpl`: update template path reference to `tests/uat/templates/test-session-template.html`
- `docs/user-guide.md`: align with Builder's Guide paths

**R-6.2: Add Fix Reference and Verified In columns to BUGS.md template (P2-014).**

Update `templates/generated/bugs.tmpl`:

```markdown
| # | Severity | Status | Feature | Description | Session | Fix Ref | Verified In | Disposition |
|---|---|---|---|---|---|---|---|---|
```

Column definitions:
- **Fix Ref:** Git commit SHA or PR number where the fix was implemented (e.g., `a1b2c3d` or `PR #12`)
- **Verified In:** UAT session number where the fix was re-tested (e.g., `Session 5 (re-test)`)

Both columns are populated by the agent during Step 2.9 (Remediation Loop). The `test-gate.sh --check-phase-gate` pattern matching must be updated to account for the new column positions.

**R-6.3: Allow bug fix commits during UAT remediation step (P2-015).**

The current enforcement blocks all source commits while a UAT session is in progress. This forces all bug fixes to accumulate as uncommitted changes, which risks work loss during long remediation sessions.

Modify the UAT commit check in `process-checklist.sh` `check_commit_ready()`:

```bash
# If UAT session is in progress, allow commits only during remediation_complete step
if [ "$uat_started" != "null" ]; then
  local uat_completed
  uat_completed=$(jq '.uat_session.steps_completed | length' "$PROCESS_STATE")
  local uat_total=${#UAT_STEPS[@]}
  
  # Allow commits if triage is complete (step 7+) — we're in remediation
  local triage_done=false
  if step_is_completed "uat_session" "triage_complete"; then
    triage_done=true
  fi
  
  if [ "$triage_done" = false ] && [ "$uat_completed" -lt "$uat_total" ]; then
    print_fail "UAT session in progress — complete triage before committing bug fixes."
    # ... existing missing steps output ...
    exit 1
  fi
fi
```

This allows commits during the remediation phase (steps 8-9) while still blocking during the earlier discovery/triage phases (steps 1-7).

**R-6.4: Fix markdown export escaping in HTML template (P2-016).**

In `templates/uat-test-session.html`, update the `exportResults()` function's notes sanitization:

```javascript
var notes = el ? el.value
  .replace(/\|/g, '/')
  .replace(/\n/g, ' ')
  .replace(/`/g, "'")
  .replace(/\[/g, '(').replace(/\]/g, ')')
  .replace(/\*/g, '-')
  : '';
```

**R-6.5: Specify primary vs. fallback template (P2-017).**

Add a comment block at the top of each template:

In `templates/uat-test-session.html`:
```html
<!-- PRIMARY UAT TEMPLATE — Use this template for all UAT sessions.
     The Markdown template (uat-test-template.md) is the fallback
     for environments where an HTML file cannot be opened in a browser. -->
```

In `templates/uat-test-template.md`:
```markdown
<!-- FALLBACK UAT TEMPLATE — Use only when the HTML template cannot be
     opened in a browser. The HTML template (uat-test-session.html) is
     preferred because it provides interactive pass/fail buttons and
     structured export. -->
```

Update CLAUDE.md template to specify:
```
- Generate UAT test sessions using the **HTML template** at `tests/uat/templates/test-session-template.html` (primary).
  Use the Markdown template at `tests/uat/templates/test-session-template.md` only if the Orchestrator requests text-only format.
```

#### Files Modified

| File | Change |
|------|--------|
| `templates/generated/bugs.tmpl` | Add Fix Ref and Verified In columns |
| `templates/uat-test-session.html` | Fix export escaping, add template designation comment |
| `templates/uat-test-template.md` | Add fallback designation comment |
| `templates/generated/claude-md.tmpl` | Fix template path, specify HTML as primary |
| `scripts/process-checklist.sh` | Allow commits during UAT remediation step |
| `scripts/test-gate.sh` | Update BUGS.md grep patterns for new column positions |
| `docs/builders-guide.md` | Confirm/align UAT path references |
| `docs/user-guide.md` | Align UAT path references |

#### Effort Estimate

3-4 hours. Most changes are documentation alignment and template updates. The commit-during-remediation change requires careful testing to verify the boundary condition between triage and remediation steps.

---

### RG-7: Context Health Check Elevation

**Severity:** Major
**Findings:** P2-018, P2-019
**Root Cause:** The Context Health Check -- the framework's primary defense against Code Drift, identified as the highest-priority Phase 2 risk -- is implemented as a Tier 3 advisory reminder. It produces no artifact, has no enforcement mechanism, and is displayed only once at session start (not during the session when the feature count actually exceeds the threshold).
**Enterprise Impact:** The two highest-priority Phase 2 risks (Code Drift and Context Window Bleed) have the weakest enforcement. An auditor asked "how do you verify the AI hasn't drifted from the architecture?" would find only ephemeral conversation logs.

#### Current State

```bash
# session-test-gate-check.sh lines 89-99
if [ "$health_count" -ge 3 ] 2>/dev/null; then
  echo ""
  echo -e "\033[33m[REMINDER]\033[0m Context Health Check recommended..."
fi
```

This is a yellow reminder printed at session start. It is not shown during the session, not blocking, and produces no persistent artifact. The `--reset-health-check` command resets the counter with no record of what was checked.

#### Remediation

**R-7.1: Add `context_health_check` as an optional build loop step.**

Rather than making it a separate process, integrate it into the build loop cadence. When `features_since_last_health_check >= 3`, the next `--start-feature` call prints a blocking warning:

```bash
# In start_feature(), after ensure_state_file:
if [ -f "$BUILD_PROGRESS" ] && command -v jq &>/dev/null; then
  local health_count
  health_count=$(jq '.features_since_last_health_check // 0' "$BUILD_PROGRESS" 2>/dev/null)
  if [ "$health_count" -ge 3 ] 2>/dev/null; then
    print_fail "Context Health Check required ($health_count features since last check)."
    echo "  Before starting a new feature:" >&2
    echo "  1. Run the health check (summarize features built, remaining, data model, known issues)" >&2
    echo "  2. Save results to docs/health-checks/[date]_health-check.md" >&2
    echo "  3. Reset: scripts/test-gate.sh --reset-health-check" >&2
    exit 1
  fi
fi
```

This elevates the health check from Tier 3 (advisory) to Tier 2 (blocking at a process boundary). It blocks the start of new features but does not interrupt in-progress work.

**R-7.2: Create health check artifact template.**

Create `templates/generated/health-check.tmpl`:

```markdown
# Context Health Check

**Date:** [YYYY-MM-DD]
**Features Since Last Check:** [N]
**Session ID:** [session identifier]

## Features Built Since Last Check

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1 | | Complete | |

## Features Remaining (from MVP Cutline)

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | | | |

## Current Data Model State

[Summary of current schema, recent changes, any pending migrations]

## Known Issues

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | | | |

## Bible Consistency Check

- [ ] PROJECT_BIBLE.md `Last Updated` markers are current
- [ ] Interfaces documented in Bible match actual implementation
- [ ] Data model in Bible matches current schema
- [ ] Dependencies in Bible match lockfile
- [ ] No hallucinated features or references

## Drift Assessment

- **Drift detected:** Yes / No
- **Action taken:** [Continue / Fresh session started / Bible updated]
```

**R-7.3: Define canonical storage directory.**

Health check artifacts are stored in `docs/health-checks/` with naming `[YYYY-MM-DD]_health-check.md`. Create this directory in `init.sh`.

**R-7.4: Record health check execution in `--reset-health-check`.**

Modify `test-gate.sh --reset-health-check` to verify the artifact exists before resetting:

```bash
reset-health-check)
  ensure_progress_file
  # Verify health check artifact exists
  local recent_check
  recent_check=$(find docs/health-checks/ -name "*_health-check.md" -newer "$BUILD_PROGRESS" 2>/dev/null | head -1)
  if [ -z "$recent_check" ]; then
    print_fail "No health check artifact found in docs/health-checks/."
    echo "  Create the artifact using templates/generated/health-check.tmpl before resetting." >&2
    exit 1
  fi
  jq '.features_since_last_health_check = 0' "$BUILD_PROGRESS" > "$BUILD_PROGRESS.tmp" && mv "$BUILD_PROGRESS.tmp" "$BUILD_PROGRESS"
  print_ok "Context health check counter reset (artifact: $recent_check)"
  exit 0
  ;;
```

#### Files Modified

| File | Change |
|------|--------|
| `templates/generated/health-check.tmpl` | New file (template) |
| `scripts/process-checklist.sh` | Block `--start-feature` when health check overdue |
| `scripts/test-gate.sh` | Verify artifact before `--reset-health-check` |
| `scripts/session-test-gate-check.sh` | Keep existing reminder (now secondary to blocking check) |
| `init.sh` | Add `docs/health-checks/` to scaffold |
| `docs/builders-guide.md` | Update Context Health Check section with artifact requirement |
| `templates/generated/claude-md.tmpl` | Add health check artifact instructions |

#### Effort Estimate

4-5 hours. The blocking check in `start_feature()` and the artifact verification in `--reset-health-check` are the core changes. Template creation and documentation updates are straightforward.

---

### RG-8: Governance Checkpoint Artifacts

**Severity:** Major
**Findings:** P2-020, P2-021
**Root Cause:** The Mid-Phase 2 Governance Checkpoint (organizational deployments only) prescribes biweekly status reviews with the Senior Technical Authority, but the In-Phase Decision Log has no template, no storage location, and no enforcement. The 4 escalation triggers defined in the Builder's Guide have no mechanical detection.
**Enterprise Impact:** The only external oversight during the longest phase (2-6 weeks) produces no artifact. An auditor asked "show me the governance checkpoint records" would receive nothing.

#### Remediation

**R-8.1: Create In-Phase Decision Log template.**

Create `templates/generated/decision-log.tmpl`:

```markdown
# In-Phase Decision Log — Phase 2 (Construction)

**Project:** [PROJECT_NAME]
**Phase Start Date:** [YYYY-MM-DD]
**Reviewer:** [Senior Technical Authority name]

---

## Review Log

### Review [N] — [YYYY-MM-DD]

**Attendees:** [Orchestrator name], [Reviewer name]
**Duration:** [minutes]

**Status Summary:**
- Features completed: [N] of [total]
- Features remaining: [list]
- Test pass rate: [percentage]
- Architecture deviations from Bible: [none / list]
- Open security findings: [none / list]

**Decisions Made:**
| # | Decision | Rationale | Alternatives Considered |
|---|----------|-----------|------------------------|
| 1 | | | |

**Escalation Triggers Checked:**
- [ ] No architecture deviations without ADR
- [ ] Test pass rate above 80%
- [ ] No unresolved security findings from prior review
- [ ] AI output quality acceptable

**Outcome:** Continue / Pause / Escalate
**Next Review:** [YYYY-MM-DD]

---
```

**R-8.2: Define storage and initialization.**

The decision log is stored at `docs/decision-log-phase2.md` for organizational deployments. Add to `init.sh`:

```bash
# For organizational deployments only
if [ "$DEPLOYMENT_TYPE" = "organizational" ]; then
  cp templates/generated/decision-log.tmpl docs/decision-log-phase2.md
fi
```

**R-8.3: Add escalation trigger detection (P2-021).**

Add a `--check-escalation-triggers` command to `test-gate.sh` or a new script that mechanically evaluates the 4 triggers:

| Trigger | Detection Method |
|---------|-----------------|
| Architecture deviation without ADR | Compare `docs/ADR documentation/` modification dates to source file changes. If source changed significantly without ADR, warn. |
| Test pass rate below 80% | Parse most recent CI test output or `gh run` results for failure percentage. |
| Unresolved security findings | Check `docs/security-audits/*.md` for entries with `Status: Open` older than 14 days. |
| AI output quality degraded | Cannot be mechanically detected. Document as human-only trigger. |

The first three triggers can produce a structured summary for the biweekly review. The fourth remains a human judgment call.

Add to `test-gate.sh`:

```bash
check_escalation_triggers() {
  echo ""
  echo -e "${BOLD}Escalation Trigger Check${NC}"
  echo ""
  
  local triggers_fired=0
  
  # Trigger 1: Unresolved security findings > 14 days old
  if [ -d "docs/security-audits" ]; then
    local old_findings
    old_findings=$(find docs/security-audits/ -name "*.md" -mtime +14 -exec grep -l "Status:.*Open" {} \; 2>/dev/null | wc -l | tr -d ' ')
    if [ "$old_findings" -gt 0 ]; then
      print_warn "ESCALATION TRIGGER: $old_findings security audit(s) with open findings older than 14 days"
      triggers_fired=$((triggers_fired + 1))
    else
      print_ok "No stale security findings"
    fi
  fi
  
  # Trigger 2: Test pass rate (requires gh CLI)
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    local last_run_conclusion
    last_run_conclusion=$(gh run list --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null || echo "unknown")
    if [ "$last_run_conclusion" = "failure" ]; then
      print_warn "ESCALATION TRIGGER: Most recent CI run failed"
      triggers_fired=$((triggers_fired + 1))
    elif [ "$last_run_conclusion" = "success" ]; then
      print_ok "Most recent CI run passed"
    fi
  fi
  
  # Trigger 3: Architecture deviation (heuristic: source changes without ADR)
  # This is advisory — many source changes legitimately don't need ADRs
  
  echo ""
  if [ "$triggers_fired" -gt 0 ]; then
    print_warn "$triggers_fired escalation trigger(s) fired. Review with Senior Technical Authority."
    return 1
  else
    print_ok "No escalation triggers fired"
    return 0
  fi
}
```

#### Files Modified

| File | Change |
|------|--------|
| `templates/generated/decision-log.tmpl` | New file (template) |
| `init.sh` | Create decision log for org deployments |
| `scripts/test-gate.sh` | Add `--check-escalation-triggers` command |
| `docs/builders-guide.md` | Reference template and storage location in Mid-Phase 2 section |
| `docs/governance-framework.md` | Reference template in In-Phase Decision Log section |

#### Effort Estimate

3-4 hours. Template creation is straightforward. Escalation trigger detection is heuristic and should not be over-engineered -- the goal is to surface data for the reviewer, not to replace the reviewer's judgment.

---

### RG-9: Minor Process and Template Fixes

**Severity:** Minor
**Findings:** P2-004, P2-005, P2-011, P2-012, P2-023, P2-028

These findings represent documentation inconsistencies, missing guidance, and heuristic limitations that do not create compliance gaps but should be corrected for consistency.

#### R-9.1: Branch Protection Verification Is Heuristic (P2-004)

**Current:** `verify_init()` checks for `.github/workflows/ci.yml` existence, not actual branch protection rules.

**Fix:** Add an optional GitHub API check when `gh` CLI is available:

```bash
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  local bp_status
  bp_status=$(gh api repos/{owner}/{repo}/branches/main/protection --jq '.required_pull_request_reviews' 2>/dev/null || echo "")
  if [ -n "$bp_status" ]; then
    print_ok "branch_protection_configured — GitHub branch protection verified via API"
  else
    print_warn "branch_protection_configured — CI workflow exists but API check inconclusive (verify manually)"
  fi
else
  # Fall back to existing CI file check
  print_ok "branch_protection_configured — CI workflow exists (API check unavailable)"
fi
```

**Effort:** 30 minutes.

#### R-9.2: Verification Checklist Discrepancy Between Guides (P2-005)

**Current:** Builder's Guide lists 8 initialization verification items. User Guide lists 9 (adds Semgrep pre-commit verification).

**Fix:** Add the Semgrep pre-commit verification item to the Builder's Guide Step 7 checklist to match the User Guide:

```
- [ ] Pre-commit hook catches a Semgrep finding (test with a known-insecure pattern)
```

**Effort:** 15 minutes.

#### R-9.3: Data Model Changes Not in Process Checklist (P2-011)

**Current:** Builder's Guide Step 2.6 describes data model changes as an "if needed" step but it is not tracked in the process checklist.

**Fix:** Add a schema change warning to the PreToolUse hook that fires when the agent modifies files in common migration directories. This is already partially implemented as a pre-commit hook warning. Document the existing warning in the process enforcement section of the User Guide and clarify that data model changes are tracked through the pre-commit hook (Tier 2), not the process checklist.

**Effort:** 30 minutes (documentation only).

#### R-9.4: Decision Gate at Step 2.2 Lacks Enforcement (P2-012)

**Current:** The DECISION GATE at Step 2.2 (test review) is Tier 3 -- pure LLM guidance with no mechanical check.

**Fix:** This is inherently a human judgment gate (reviewing test quality). It cannot be mechanically enforced without false positives. Document its enforcement tier explicitly in the User Guide:

Add to the Tier 3 table:
```
| Test assertion review (Step 2.2 Decision Gate) | Builder's Guide |
```

Add to Builder's Guide Step 2.2 after the Decision Gate callout:
```
**Enforcement tier:** Tier 3 (Orchestrator review). The framework cannot mechanically verify
test quality. Review the assertions. Reject tests that only check status codes or "response
is not null." The Orchestrator is the quality gate here.
```

**Effort:** 15 minutes.

#### R-9.5: Phase 2-to-3 Bug Check Uses Fragile Pattern Matching (P2-023)

**Current:** `test-gate.sh` uses `grep -c 'SEV-1.*Open'` to count bugs in BUGS.md. Column reordering, extra whitespace, or inconsistent formatting can cause false positives or negatives.

**Fix:** Replace the grep-based counting with awk-based column-aware parsing that reads the header row to determine column positions dynamically:

```bash
# Parse BUGS.md table with column-aware extraction
if [ -f "BUGS.md" ]; then
  has_bugs=true
  # Use awk to find Severity and Status columns by header, then count
  sev1_count=$(awk -F'|' '
    NR==1 { for(i=1;i<=NF;i++) { gsub(/^[ \t]+|[ \t]+$/,"",$i); if($i=="Severity") sc=i; if($i=="Status") stc=i } }
    NR>2 && sc && stc { 
      gsub(/^[ \t]+|[ \t]+$/,"",$sc); gsub(/^[ \t]+|[ \t]+$/,"",$stc);
      if($sc ~ /SEV-1/ && $stc ~ /Open/) count++ 
    }
    END { print count+0 }
  ' "BUGS.md")
  # ... similar for sev2_open, sev2_deferred, sev3_open
fi
```

Note: This must be updated alongside R-6.2 (new columns in BUGS.md template) to handle the expanded column layout.

**Effort:** 1-2 hours.

#### R-9.6: No Phase 2-to-3 Gate in process-checklist.sh (P2-028)

**Current:** `process-checklist.sh` tracks Phase 2 init, build loop, UAT, Phase 3, and Phase 4 -- but has no Phase 2 completion process.

**Fix:** Addressed by RG-2 (R-2.1). The `phase2_completion` process provides the missing gate enforcement. No additional work needed here beyond what RG-2 specifies.

**Effort:** Included in RG-2 estimate.

#### Files Modified

| File | Change |
|------|--------|
| `scripts/process-checklist.sh` | Branch protection API check (R-9.1) |
| `docs/builders-guide.md` | Add Semgrep check to Step 7 (R-9.2), Decision Gate tier (R-9.4) |
| `docs/user-guide.md` | Data model change enforcement note (R-9.3), Decision Gate tier (R-9.4) |
| `scripts/test-gate.sh` | Column-aware BUGS.md parsing (R-9.5) |

#### Combined Effort Estimate

2-3 hours for all minor fixes.

---

### RG-10: Observations

**Severity:** Observation
**Findings:** P2-007, P2-025, P2-026, P2-027

These findings identify inherent limitations or design trade-offs that do not require remediation but should be monitored and documented.

#### P2-007: `feature_recorded` Is Post-Commit (By Design)

**Status:** Accept. The build loop intentionally checks the first 5 steps (through `documentation_updated`) before allowing the commit. `feature_recorded` is the 6th step, completed after the commit. The gap is that the previous loop's `feature_recorded` is not checked before `--start-feature` begins the next loop.

**Monitoring:** Add a warning in `start_feature()` if the previous build loop has 5/6 steps completed (all but `feature_recorded`):

```bash
# In start_feature():
local prev_completed
prev_completed=$(jq '.build_loop.steps_completed | length' "$PROCESS_STATE" 2>/dev/null || echo "0")
if [ "$prev_completed" -eq 5 ]; then
  print_warn "Previous feature has 5/6 steps complete — 'feature_recorded' was not completed."
  echo "  Run: scripts/process-checklist.sh --complete-step build_loop:feature_recorded" >&2
  echo "  And: scripts/test-gate.sh --record-feature 'previous-feature-name'" >&2
fi
```

#### P2-025: process-state.json Could Be Manually Edited

**Status:** Accept. The file is committed to git, and anyone with write access can modify it directly. The audit log (added in RG-5) provides a secondary record of legitimate state transitions. Git blame on `process-state.json` shows direct edits (manual manipulation) vs. script-mediated edits (normal operation). No additional enforcement needed -- the cost of tamper-proofing (cryptographic signing, sealed storage) exceeds the risk for the framework's target audience.

**Monitoring:** Document in the User Guide's Process Enforcement section that `process-state.json` is tracked by git and direct edits are visible via `git log --follow -p .claude/process-state.json`.

#### P2-026: Tool Usage Tracking Resets Every Session

**Status:** Accept. The tool usage tracking system (`track-tool-usage.sh` / `session-test-gate-check.sh`) is advisory by design. Resetting per session is the correct behavior for its purpose (nudging Context7 and Qdrant usage within a session). Cross-session analytics would require a separate aggregation mechanism.

**Monitoring:** If longitudinal tool usage data becomes valuable, add an append-only summary line to `.claude/process-audit.log` at session end:

```
[timestamp] SESSION_END: context7_calls=N qdrant_find=Y/N qdrant_store=Y/N commits=N
```

This provides historical data without changing the per-session reset behavior.

#### P2-027: PreToolUse Regex May Not Catch All Command Formats

**Status:** Partially addressed by RG-3 (R-3.4). The broadened `\b` word boundary pattern catches `git -c ... commit` and `env ... git commit`. Remaining edge cases (aliased commands, shell functions wrapping git) are low probability in Claude Code's generation patterns and impractical to fully enumerate.

**Monitoring:** If new bypass patterns are discovered in production use, add them to the detection regex. The pattern is centralized in `pre-commit-gate.sh` and straightforward to extend.

---

## 2. Implementation Schedule

### Priority 1: Critical (Complete before any new project uses Phase 2)

| Group | Findings | Effort | Dependencies |
|-------|----------|--------|--------------|
| RG-1 | P2-006 | 4-6h | None |
| RG-2 | P2-022, P2-024, P2-028 | 6-8h | RG-1 (security artifact check pattern reused) |

**Total Priority 1:** 10-14 hours

### Priority 2: Major (Complete before organizational deployment)

| Group | Findings | Effort | Dependencies |
|-------|----------|--------|--------------|
| RG-3 | P2-009, P2-010, P2-027 | 1-2h | None |
| RG-4 | P2-001, P2-002, P2-003 | 2-3h | None |
| RG-5 | P2-008 | 2-3h | None |
| RG-6 | P2-013, P2-014, P2-015, P2-016, P2-017 | 3-4h | RG-9.5 (BUGS.md parsing) |
| RG-7 | P2-018, P2-019 | 4-5h | RG-1 (artifact check pattern) |
| RG-8 | P2-020, P2-021 | 3-4h | None |

**Total Priority 2:** 15-21 hours

### Priority 3: Minor (Next framework iteration)

| Group | Findings | Effort | Dependencies |
|-------|----------|--------|--------------|
| RG-9 | P2-004, P2-005, P2-011, P2-012, P2-023, P2-028 | 2-3h | RG-6 (BUGS.md column change) |

**Total Priority 3:** 2-3 hours

### Priority 4: Observations (Monitor only)

| Group | Findings | Effort |
|-------|----------|--------|
| RG-10 | P2-007, P2-025, P2-026, P2-027 | 1h (warning additions only) |

**Grand Total:** 28-41 hours

### Recommended Implementation Order

1. **RG-3** (PreToolUse detection) -- lowest effort, highest immediate risk reduction
2. **RG-5** (audit trail preservation) -- enables audit confidence for subsequent changes
3. **RG-1** (security audit evidence) -- Critical finding, establishes artifact-check pattern
4. **RG-4** (init verification) -- self-contained, no dependencies
5. **RG-7** (context health check) -- reuses artifact-check pattern from RG-1
6. **RG-6** (UAT workflow) -- multiple small fixes, benefits from BUGS.md parsing update
7. **RG-8** (governance artifacts) -- organizational deployments only
8. **RG-2** (Phase 2-to-3 gate) -- largest change, benefits from all prior patterns
9. **RG-9** (minor fixes) -- cleanup pass
10. **RG-10** (observations) -- monitoring additions

---

## 3. Verification Test Plan

Each remediation group has a verification test that confirms the fix works as intended. Tests are designed to be run manually against a test project.

### Critical Verifications

| ID | Group | Test | Expected Result |
|----|-------|------|-----------------|
| V-01 | RG-1 | Run `--complete-step build_loop:security_audit` with no file in `docs/security-audits/` | Blocked with message directing to template |
| V-02 | RG-1 | Run `--complete-step build_loop:security_audit` with a valid audit report present | Step completes normally |
| V-03 | RG-2 | Run `test-gate.sh --check-phase-gate` with 0 features in FEATURES.md | BLOCKED with feature completeness failure |
| V-04 | RG-2 | Run `test-gate.sh --check-phase-gate` with features recorded and no open bugs | Gate passes |
| V-05 | RG-2 | Run `--start-phase3` when `--check-phase-gate` would fail | Phase 3 start blocked |
| V-06 | RG-2 | Run `--start-phase2-completion` and attempt to complete steps out of order | Sequential enforcement blocks |

### Major Verifications

| ID | Group | Test | Expected Result |
|----|-------|------|-----------------|
| V-07 | RG-3 | Agent runs `git commit --no-verify -m "test"` | PreToolUse denies with explanation |
| V-08 | RG-3 | Agent runs `git push --force origin main` | PreToolUse denies with explanation |
| V-09 | RG-3 | Agent runs `git commit --amend` | PreToolUse allows with amend warning |
| V-10 | RG-3 | Agent runs `git -c user.name=x commit -m "test"` | PreToolUse detects as commit (broadened regex) |
| V-11 | RG-4 | Run `--verify-init` with steps already completed out of order in process-state.json | Steps re-validated through `complete_step()` ordering |
| V-12 | RG-4 | Run `--verify-init` with 6/7 steps complete | `initialization_verified` auto-completed |
| V-13 | RG-4 | Run `--verify-init` with migration directory present | `data_model_applied` auto-verified |
| V-14 | RG-5 | Agent runs `scripts/process-checklist.sh --reset build_loop` | Interactive prompt blocks agent; requires human input |
| V-15 | RG-5 | Human runs reset and types RESET | Reset proceeds, event logged to `.claude/process-audit.log` |
| V-16 | RG-5 | Check `.claude/process-audit.log` after several step completions | All step completions recorded with timestamps |
| V-17 | RG-6 | Check that BUGS.md template has Fix Ref and Verified In columns | Columns present in template |
| V-18 | RG-6 | Attempt source commit during UAT with `triage_complete` done | Commit allowed (remediation phase) |
| V-19 | RG-6 | Attempt source commit during UAT before triage | Commit blocked |
| V-20 | RG-7 | Run `--start-feature` after 3 features without health check | Blocked with health check requirement |
| V-21 | RG-7 | Run `--reset-health-check` without artifact in `docs/health-checks/` | Reset blocked |
| V-22 | RG-7 | Run `--reset-health-check` with valid artifact present | Counter resets normally |
| V-23 | RG-8 | Verify `decision-log.tmpl` created for org deployment | Template present and correctly formatted |
| V-24 | RG-8 | Run `--check-escalation-triggers` with stale security findings | Trigger fires with count |

### Minor Verifications

| ID | Group | Test | Expected Result |
|----|-------|------|-----------------|
| V-25 | RG-9 | Builder's Guide Step 7 checklist item count | 9 items (matches User Guide) |
| V-26 | RG-9 | Run BUGS.md parser on a table with extra whitespace and reordered columns | Correct severity/status counts |
| V-27 | RG-9 | Verify Decision Gate enforcement tier documented in User Guide | Present in Tier 3 table |

---

## 4. Risk Assessment

### Risks of Remediation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Artifact checks produce false negatives (e.g., timestamp comparison fails if audit report created before build loop starts) | Medium | Agent blocked incorrectly | Use file modification time comparison with 60-second tolerance; provide `--force` flag for `complete_step()` that logs the override |
| Broadened PreToolUse regex creates false positives on non-git commands containing "git" and "commit" as substrings | Low | Legitimate commands blocked | The `\b` word boundary anchors prevent substring matches. Test against common command patterns before deployment. |
| Phase 2 completion process adds overhead that slows personal projects | Medium | Developer friction | All mechanical checks are designed to pass silently when artifacts are in order. Overhead is only felt when something is actually missing. |
| BUGS.md column change breaks existing projects' `test-gate.sh` parsing | High | Phase gate check fails or gives wrong counts | The awk-based parser (R-9.5) reads column headers dynamically. Add backward compatibility: if "Fix Ref" column is absent, fall back to current column positions. |
| Interactive reset confirmation breaks CI/automation that legitimately calls reset | Low | CI pipeline fails | CI should not call `--reset`. If automation needs reset, add a `--yes` flag that bypasses confirmation but still logs to audit file. Document that `--yes` is for CI only, not for agent use. |

### Risks of Non-Remediation

| Finding | Risk of Leaving Unfixed |
|---------|------------------------|
| P2-006 (Critical) | Enterprise audit failure. Security audit is unverifiable. Any compliance assessment will flag this immediately. |
| P2-022 (Critical) | Phase 3 entered with incomplete MVP. Construction effort wasted on validation of unbuilt features. |
| P2-009/010 (Major) | Agent bypasses security scanning via `--no-verify`. CI catches most issues, but the pre-commit layer is the early warning system. |
| P2-008 (Major) | Process state can be reset with no trace. Undermines all process enforcement credibility. |

---

## 5. Appendix: Finding-to-Group Cross-Reference

| Finding ID | Severity | Title | Remediation Group | Priority |
|------------|----------|-------|-------------------|----------|
| P2-001 | Major | Phase 2 Init Verification Bypasses Sequential Ordering | RG-4 | 2 |
| P2-002 | Major | `data_model_applied` Lacks Verification Criteria | RG-4 | 2 |
| P2-003 | Major | `initialization_verified` Has No Completion Path | RG-4 | 2 |
| P2-004 | Minor | Branch Protection Verification Is Heuristic | RG-9 | 3 |
| P2-005 | Minor | Verification Checklist Discrepancy Between Guides | RG-9 | 3 |
| P2-006 | Critical | Security Audit Findings Have No Storage or Tracking | RG-1 | 1 |
| P2-007 | Observation | `feature_recorded` Is Post-Commit (By Design) | RG-10 | 4 |
| P2-008 | Major | Build Loop Reset Destroys Audit Trail | RG-5 | 2 |
| P2-009 | Major | `--no-verify` Bypasses Pre-Commit Security Hooks | RG-3 | 2 |
| P2-010 | Major | Force Push and Commit Amend Not Gated | RG-3 | 2 |
| P2-011 | Minor | Data Model Changes Not in Process Checklist | RG-9 | 3 |
| P2-012 | Minor | Decision Gate at Step 2.2 Lacks Enforcement | RG-9 | 3 |
| P2-013 | Major | UAT Session Results Have Conflicting Archive Locations | RG-6 | 2 |
| P2-014 | Major | UAT-to-Bug-to-Fix Traceability Incomplete | RG-6 | 2 |
| P2-015 | Minor | UAT Blocks All Commits During Session | RG-6 | 2 |
| P2-016 | Minor | HTML UAT Template Unescaped Markdown Export | RG-6 | 2 |
| P2-017 | Minor | Two UAT Templates With No Selection Guidance | RG-6 | 2 |
| P2-018 | Major | Context Health Check Is Advisory Only | RG-7 | 2 |
| P2-019 | Minor | Context Health Check Produces No Artifact | RG-7 | 2 |
| P2-020 | Major | Mid-Phase 2 Governance Checkpoint Has No Artifact | RG-8 | 2 |
| P2-021 | Minor | Escalation Triggers Have No Detection Mechanism | RG-8 | 2 |
| P2-022 | Critical | Phase 2-to-3 Gate Does Not Verify Feature Completeness | RG-2 | 1 |
| P2-023 | Minor | Phase 2-to-3 Bug Check Uses Fragile Pattern Matching | RG-9 | 3 |
| P2-024 | Major | Phase 2 Completion Checklist Mostly Unverified | RG-2 | 1 |
| P2-025 | Observation | process-state.json Could Be Manually Edited | RG-10 | 4 |
| P2-026 | Observation | Tool Usage Tracking Resets Every Session | RG-10 | 4 |
| P2-027 | Observation | PreToolUse Regex May Not Catch All Command Formats | RG-10 (partial RG-3) | 4 |
| P2-028 | Minor | No Phase 2-to-3 Gate in process-checklist.sh | RG-2 | 1 |

---

## Document History

| Date | Version | Change |
|------|---------|--------|
| 2026-04-08 | 1.0 | Initial remediation plan for Phase 2 audit findings |

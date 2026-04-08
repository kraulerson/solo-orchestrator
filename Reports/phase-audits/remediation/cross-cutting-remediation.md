# Cross-Cutting Infrastructure & Governance
# Remediation Plan

**Audit Reference:** 2026-04-08-cross-cutting-audit.md
**Auditor Persona:** Chief Compliance Officer
**Remediation Author:** Framework Engineering
**Date:** 2026-04-08
**Framework Version:** Solo Orchestrator v1.0 (post-PR #6, #7)
**Scope:** All 22 findings (1 Critical, 9 Major, 8 Minor, 4 Observation)

---

## Executive Summary

The cross-cutting audit identified 22 findings across infrastructure, governance, and enforcement systems that serve as the foundation for all five phases. Unlike phase-specific findings, these deficiencies propagate: a gap in `validate.sh` weakens every phase that depends on validation, a missing gate check leaves a phase transition unguarded for every project, and a bypassable reset command undermines the entire process enforcement model.

This remediation plan groups findings by shared infrastructure to minimize churn and maximize coverage per change. Seven remediation groups address all 22 findings through coordinated changes to 11 files.

**Priority sequence:** Approval integrity (Critical) first, then enforcement bypass closure, then validation coverage, then documentation alignment. Each group includes acceptance criteria and verification tests.

---

## Remediation Groups

### Group 1: Approval Log Integrity (CC-004, CC-014)

**Findings addressed:**

| ID | Severity | Finding |
|---|---|---|
| CC-004 | Critical | APPROVAL_LOG append-only has no mechanical enforcement |
| CC-014 | Major | Quarterly-only approval verification (3-6 month fabrication window) |

**Root cause:** The governance framework (`governance-framework.md:173`) claims append-only semantics for `APPROVAL_LOG.md`, but the only verification mechanism is a quarterly manual audit by the Senior Technical Authority. No CI step validates that prior entries remain unchanged. No automated check compares git commit author to the listed approver. The 3-6 month window between quarterly reviews is sufficient to fabricate, modify, or delete approval entries without detection.

**Current state (from source):**

- `governance-framework.md:179` states: "Each approval entry MUST be committed to APPROVAL_LOG.md by the *approver*, not the Orchestrator."
- `governance-framework.md:182` states: "During quarterly portfolio reviews, the Senior Technical Authority MUST verify that git commit authors on APPROVAL_LOG.md entries match the listed approvers."
- No CI workflow step implements either control.
- `check-phase-gate.sh` verifies that approval entries exist with dates, but never checks who authored them or whether prior entries changed.

**Remediation:**

**1a. CI step: Approval log append-only verification.**

Add a governance CI step to all CI templates (`python.yml`, `typescript.yml`, `other.yml`) that detects modification or deletion of prior `APPROVAL_LOG.md` entries. The check compares the current file against the `main` branch version and fails the build if any line present in `main` is absent or modified in the PR.

```yaml
- name: Governance - Approval log integrity
  if: hashFiles('APPROVAL_LOG.md') != ''
  run: |
    # Verify no prior APPROVAL_LOG.md entries were modified or deleted
    if git diff origin/main...HEAD -- APPROVAL_LOG.md | grep -qE '^\-[^-]'; then
      echo "::error::APPROVAL_LOG.md has deleted or modified lines. This file is append-only."
      echo "Prior entries must not be changed. If a correction is needed, add a new entry with a correction note."
      exit 1
    fi
```

This is deliberately simple. The diff check catches deletions and modifications of existing lines. New lines (appends) pass. A sophisticated attacker could still rewrite the file entirely in a force-push, but that requires bypassing branch protection -- a separate control that the framework already prescribes.

**1b. CI step: Commit author matches approver on approval log changes.**

Add a CI step that, when `APPROVAL_LOG.md` is modified, extracts the git commit author and cross-references it against the approver name added in the new entry. This moves the "commit-based evidence" control from quarterly manual review to continuous automated enforcement.

```yaml
- name: Governance - Approval author verification
  if: hashFiles('APPROVAL_LOG.md') != ''
  run: |
    # Check if APPROVAL_LOG.md was modified in this PR
    if git diff --name-only origin/main...HEAD | grep -q 'APPROVAL_LOG.md'; then
      COMMIT_AUTHOR=$(git log --format='%an' origin/main...HEAD -- APPROVAL_LOG.md | head -1)
      ADDED_LINES=$(git diff origin/main...HEAD -- APPROVAL_LOG.md | grep '^+' | grep -i 'Approver' | head -1 || true)
      if [ -n "$ADDED_LINES" ]; then
        APPROVER_NAME=$(echo "$ADDED_LINES" | sed 's/.*|\s*//' | sed 's/\s*|.*//' | tr -d '+*')
        if [ -n "$APPROVER_NAME" ] && [ "$APPROVER_NAME" != "$COMMIT_AUTHOR" ]; then
          echo "::warning::Commit author ($COMMIT_AUTHOR) differs from listed approver ($APPROVER_NAME). Verify this is intentional."
        fi
      fi
    fi
```

Note: This step issues a warning rather than a hard failure. In personal deployments, the Orchestrator legitimately commits on behalf of verbal/email approvals. In organizational deployments, the warning provides audit evidence that the mismatch was visible in CI. Organizations wanting hard enforcement can change `::warning::` to `::error::` and add `exit 1`.

**1c. Update governance framework documentation.**

Update `governance-framework.md` to reflect that approval verification is now continuous (CI-enforced) rather than quarterly-only. The quarterly review remains as a deeper reconciliation (checking out-of-band confirmations, verifying evidence references), but the primary tamper-detection control is now automated.

**Files to modify:**

| File | Change |
|---|---|
| `templates/pipelines/ci/python.yml` | Add approval integrity + author verification steps |
| `templates/pipelines/ci/typescript.yml` | Add approval integrity + author verification steps |
| `templates/pipelines/ci/other.yml` | Add approval integrity + author verification steps |
| `docs/governance-framework.md` | Update Section V verification controls from quarterly to continuous |

**Acceptance criteria:**

- [ ] CI build fails when any existing `APPROVAL_LOG.md` line is deleted or modified
- [ ] CI build warns when commit author does not match listed approver
- [ ] Appending new entries passes CI without error
- [ ] Governance framework documentation references CI-based continuous verification
- [ ] Quarterly review documented as supplementary reconciliation, not primary control

---

### Group 2: Process Enforcement Bypass Closure (CC-011, CC-005)

**Findings addressed:**

| ID | Severity | Finding |
|---|---|---|
| CC-011 | Major | `process-checklist.sh --reset` has no authorization |
| CC-005 | Major | PreToolUse only gates Bash, not Write/Edit |

**Root cause (CC-011):** The `--reset` and `--reset-all` commands in `process-checklist.sh` (lines 608-668) execute unconditionally. No interactive confirmation is required, no persistent audit trail is written, and the PreToolUse hook does not intercept the call because it only gates `git commit` and `gh pr create`. An agent can call `--reset-all` to clear all process state and then proceed as if no enforcement existed.

**Root cause (CC-005):** The PreToolUse hook (`pre-commit-gate.sh`) is registered with `"matcher": "Bash"`, which means it only fires on Bash tool calls. An agent could use the Write or Edit tools to create implementation files before writing tests, circumventing TDD ordering. However, the audit correctly notes that enforcement is architecturally commit-gated by design -- the Build Loop enforces that tests exist and pass *before the commit is allowed*, not before each file write. The question is whether this design decision is documented and defensible.

**Remediation:**

**2a. Add authorization gate to `--reset` and `--reset-all`.**

Modify `process-checklist.sh` to require interactive confirmation for reset operations. In non-interactive contexts (agent calls), the reset is denied with instructions to have the Orchestrator run it manually.

```bash
reset_process() {
  ensure_state_file
  local process="$1"

  # Authorization: require interactive terminal
  if [ ! -t 0 ]; then
    print_fail "Reset requires interactive authorization."
    echo "The Orchestrator must run this command directly in a terminal:" >&2
    echo "  scripts/process-checklist.sh --reset $process" >&2
    exit 1
  fi

  # Interactive confirmation
  read -rp "Reset process '$process'? This clears all progress. [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Reset cancelled."
    exit 0
  fi

  # ... existing reset logic ...

  # Persistent audit trail
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local audit_entry="[RESET] Process $process reset at $now by $(whoami)"
  echo "$audit_entry" >> ".claude/process-audit.log"
  echo "$audit_entry" >&2
}
```

The same pattern applies to `reset_all`. The key properties:
- Non-interactive (agent) calls are denied outright
- Interactive calls require explicit `y` confirmation
- Every reset is appended to `.claude/process-audit.log` as a persistent, append-only audit trail
- The log file is separate from `process-state.json` so it cannot be overwritten by the reset itself

**2b. Add PreToolUse gate for reset commands.**

Add a matcher in the PreToolUse hook that intercepts Bash commands containing `--reset` targeting `process-checklist.sh`. This prevents the agent from calling reset even through the Bash tool.

In `pre-commit-gate.sh`, add after the existing `IS_COMMIT` / `IS_PR` detection:

```bash
# Block agent-initiated process resets
IS_RESET=false
if echo "$COMMAND" | grep -qE 'process-checklist\.sh.*--reset'; then
  IS_RESET=true
fi

if [ "$IS_RESET" = true ]; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Process reset requires Orchestrator authorization. Ask the Orchestrator to run this command directly in their terminal."}}
HOOKEOF
  exit 0
fi
```

**2c. Document commit-gated TDD enforcement as intentional design (CC-005).**

Add a paragraph to the Builder's Guide enforcement model section (`builders-guide.md:85-87`) explicitly documenting that TDD enforcement is commit-gated, not file-write-gated, and explaining why:

> **TDD enforcement timing.** The Build Loop enforces test-first ordering at commit time, not at file-write time. This is an intentional design choice. File-write gating would require intercepting every Write and Edit tool call, adding latency to every operation and creating false positives when the agent legitimately creates utility files, configuration, or documentation. Commit-time enforcement ensures that when code reaches the repository, it has passed through the full Build Loop sequence: tests written, tests verified failing, implementation complete, security audit, documentation updated. The enforcement point is the earliest moment where the agent's work becomes persistent and shared.

**Files to modify:**

| File | Change |
|---|---|
| `scripts/process-checklist.sh` | Add TTY check + interactive confirmation + audit log to `reset_process` and `reset_all` |
| `scripts/pre-commit-gate.sh` | Add reset command interception |
| `docs/builders-guide.md` | Document commit-gated enforcement as intentional design |

**Acceptance criteria:**

- [ ] Agent calling `--reset-all` via Bash tool receives deny from PreToolUse hook
- [ ] Agent calling `--reset build_loop` via Bash tool receives deny from PreToolUse hook
- [ ] Orchestrator running `--reset-all` in terminal gets interactive confirmation prompt
- [ ] Denied reset leaves `process-state.json` unchanged
- [ ] Successful reset appends audit entry to `.claude/process-audit.log`
- [ ] Builder's Guide enforcement model section documents commit-gated TDD enforcement

---

### Group 3: Validation Coverage (CC-001, CC-016, CC-006)

**Findings addressed:**

| ID | Severity | Finding |
|---|---|---|
| CC-001 | Major | `validate.sh` does not check `process-state.json` |
| CC-016 | Minor | `validate.sh` missing `build-progress.json` and `tool-usage.json` |
| CC-006 | Minor | `session-version-check.sh` references undefined variable `$BELOW_MIN_LINES` |

**Root cause:** `validate.sh` checks `phase-state.json` (line 123) but does not check the three state files introduced by the process enforcement system: `process-state.json`, `build-progress.json`, and `tool-usage.json`. These files are created by `init.sh` (line 1505 and surrounding) but are outside the validation perimeter. Deletion or corruption of any of these files silently degrades enforcement without detection.

Separately, `session-version-check.sh` (line 24) references `$BELOW_MIN_LINES` which is never assigned. The conditional `[ -n "$BELOW_MIN_LINES" ]` evaluates as an error under `set -u` but is caught by `2>/dev/null`, causing the URGENT code path to be dead code. The fallback path (line 37, generic warnings) still fires, so the impact is reduced severity differentiation rather than complete failure.

**Remediation:**

**3a. Add process enforcement state files to `validate.sh`.**

Add a new validation section after section 5 (Phase State & Artifacts) that checks all three process enforcement state files:

```bash
# ================================================================
# 5a. Process Enforcement State
# ================================================================
print_section "Process Enforcement State"

if [ -f ".claude/process-state.json" ]; then
  # Validate JSON syntax
  if jq '.' .claude/process-state.json >/dev/null 2>&1; then
    print_ok "process-state.json (valid JSON)"
  else
    fail "process-state.json exists but contains invalid JSON"
  fi
else
  if [ $phase -ge 2 ]; then
    warn "process-state.json missing — process enforcement is inactive"
  else
    print_info "No process-state.json (expected — created at Phase 2 initialization)"
  fi
fi

if [ -f ".claude/build-progress.json" ]; then
  if jq '.' .claude/build-progress.json >/dev/null 2>&1; then
    print_ok "build-progress.json (valid JSON)"
  else
    warn "build-progress.json contains invalid JSON — test interval tracking degraded"
  fi
else
  if [ $phase -ge 2 ]; then
    print_info "No build-progress.json (test interval tracking unavailable)"
  fi
fi

if [ -f ".claude/tool-usage.json" ]; then
  if jq '.' .claude/tool-usage.json >/dev/null 2>&1; then
    print_ok "tool-usage.json (valid JSON)"
  else
    warn "tool-usage.json contains invalid JSON — tool usage tracking degraded"
  fi
else
  print_info "No tool-usage.json (created on first tool call)"
fi
```

The validation is severity-tiered: `process-state.json` is an error at Phase 2+ (it controls enforcement), while `build-progress.json` and `tool-usage.json` are warnings (they are advisory systems).

**3b. Fix `$BELOW_MIN_LINES` undefined variable in `session-version-check.sh`.**

Replace the undefined variable reference at line 24 with a grep that actually extracts below-minimum-version lines from the check-versions output:

```bash
# Extract BELOW MINIMUM lines (critical — tool version too old for enforcement)
BELOW_MIN_LINES=$(echo "$VERSION_OUTPUT" | grep "BELOW MINIMUM" || true)

# Only output when something needs attention
if [ -n "$BELOW_MIN_LINES" ] || [ "$VERSION_EXIT" -ne 0 ]; then
```

This defines `BELOW_MIN_LINES` from the version check output before using it in the conditional, restoring the URGENT code path.

**Files to modify:**

| File | Change |
|---|---|
| `scripts/validate.sh` | Add section 5a: process enforcement state file validation |
| `scripts/session-version-check.sh` | Define `BELOW_MIN_LINES` from version check output before conditional |

**Acceptance criteria:**

- [ ] Deleting `process-state.json` at Phase 2+ causes `validate.sh` to report error
- [ ] Corrupted (invalid JSON) `process-state.json` causes `validate.sh` to report error
- [ ] Missing `build-progress.json` at Phase 2+ causes `validate.sh` to report warning
- [ ] Missing `tool-usage.json` produces informational message (not error)
- [ ] `session-version-check.sh` outputs URGENT block when a tool is below minimum version
- [ ] `session-version-check.sh` outputs standard warning block when tools have available updates

---

### Group 4: Phase Gate Completeness (CC-002, CC-013, CC-017)

**Findings addressed:**

| ID | Severity | Finding |
|---|---|---|
| CC-002 | Major | Phase 2->3 gate not checked in `check-phase-gate.sh` |
| CC-013 | Minor | `check-phase-gate.sh` jq/grep inconsistency (missing jq crashes script) |
| CC-017 | Major | CI phase gate check silently succeeds when script missing |

**Root cause (CC-002):** `check-phase-gate.sh` extracts gate dates for 0->1 (line 89), 1->2 (line 90), and 3->4 (line 91) but never extracts or checks `gate_2_to_3`. The Phase 2->3 transition -- the most important quality gate, separating construction from validation -- has no consistency verification. A project can advance from Phase 2 to Phase 3 with `current_phase: 3` in `phase-state.json` and no gate date recorded, and the script will not detect the inconsistency.

**Root cause (CC-013):** The script uses `grep` for most JSON field extraction (lines 80-91) but switches to `jq` for POC mode detection (line 167) without checking whether `jq` is installed. On systems without `jq`, the POC mode check crashes the entire script with a non-zero exit, which may be misinterpreted as a gate failure.

**Root cause (CC-017):** All three CI templates use the pattern `bash scripts/check-phase-gate.sh 2>/dev/null || echo "Phase gate check script not found -- skipping"` (e.g., `python.yml:54`). If the script is deleted (accidentally or maliciously), the `||` clause catches the error and the CI step succeeds with a skip message. This means Tier 1 enforcement silently degrades to no enforcement when the enforcement script is absent.

**Remediation:**

**4a. Add Phase 2->3 gate check.**

Add `gate_2_to_3` extraction and consistency check to `check-phase-gate.sh`, following the exact pattern used for other gates:

```bash
gate_2_to_3=$(get_gate_date "phase_2_to_3")

# ... after the existing Phase 1->2 artifact check block ...

# Check: if current_phase >= 3, gate 2->3 should have a date
if [ "$current_phase" -ge 3 ]; then
  if [ -n "$gate_2_to_3" ]; then
    if grep -q "Phase 2.*Phase 3" "$APPROVAL_LOG" && grep -A 15 "Phase 2.*Phase 3" "$APPROVAL_LOG" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
      echo -e "${GREEN}  [OK]${NC} Phase 2->3: gate dated $gate_2_to_3, approval log has entry"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 2->3: gate dated $gate_2_to_3, but APPROVAL_LOG.md has no dated entry"
      issues=$((issues + 1))
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2->3: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi
```

Also add a Phase 2->3 artifact check (FEATURES.md or similar construction artifacts).

**4b. Guard jq usage with availability check.**

Replace the unguarded `jq` call at line 167 with a conditional:

```bash
# POC mode check (Phase 3->4) -- block production release if in POC mode
if [ "$current_phase" = "3" ]; then
  poc_mode=""
  if command -v jq &>/dev/null; then
    poc_mode=$(jq -r '.poc_mode // empty' .claude/phase-state.json 2>/dev/null || echo "")
  else
    poc_mode=$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/phase-state.json 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "")
  fi
  if [ -n "$poc_mode" ] && [ "$poc_mode" != "null" ]; then
    echo "::error::Phase 4 (production release) is BLOCKED -- project is in ${poc_mode//_/ } mode."
    issues=$((issues + 1))
  fi
fi
```

This provides a grep-based fallback consistent with the rest of the script's parsing strategy.

**4c. Change CI fallback from silent skip to hard failure.**

In all three CI templates, replace the `|| echo "...skipping"` pattern with `|| exit 1`:

```yaml
- name: Governance - Phase gate check
  if: hashFiles('.claude/phase-state.json') != ''
  run: |
    if [ ! -f scripts/check-phase-gate.sh ]; then
      echo "::error::Phase gate check script missing. Framework integrity compromised."
      exit 1
    fi
    bash scripts/check-phase-gate.sh
```

The `hashFiles` conditional already ensures this step only runs when `phase-state.json` exists (i.e., the project uses the framework). Once the step runs, the governance script *must* be present. A missing script is now treated as a framework integrity failure, not a skippable condition.

Apply the same pattern to the changelog and session state checks in all templates. These are advisory (Tier 2/3) controls, so they use `|| true` intentionally. Document this distinction with inline comments.

**Files to modify:**

| File | Change |
|---|---|
| `scripts/check-phase-gate.sh` | Add `gate_2_to_3` extraction, Phase 2->3 consistency check, jq guard |
| `templates/pipelines/ci/python.yml` | Replace `\|\| echo "...skipping"` with script-existence guard + hard failure |
| `templates/pipelines/ci/typescript.yml` | Same as above |
| `templates/pipelines/ci/other.yml` | Same as above |

**Acceptance criteria:**

- [ ] `check-phase-gate.sh` with `current_phase: 3` and no `phase_2_to_3` date reports inconsistency
- [ ] `check-phase-gate.sh` with `current_phase: 3` and valid `phase_2_to_3` date + approval log entry passes
- [ ] `check-phase-gate.sh` runs without error on systems where `jq` is not installed
- [ ] CI build fails when `scripts/check-phase-gate.sh` is deleted from the repository
- [ ] CI build succeeds when `scripts/check-phase-gate.sh` is present and all gates are consistent
- [ ] Changelog and session state checks retain `|| true` (Tier 2/3) with documenting comments

---

### Group 5: Upgrade and Installation Verification (CC-008, CC-021, CC-009)

**Findings addressed:**

| ID | Severity | Finding |
|---|---|---|
| CC-008 | Major | Upgrade script does not verify new requirements after modification |
| CC-021 | Minor | `verify-install.sh` does not check hook registration |
| CC-009 | Minor | Hook registration idempotency issue in `init.sh` |

**Root cause (CC-008):** `upgrade-project.sh` modifies `phase-state.json`, `tool-preferences.json`, `CLAUDE.md`, `PROJECT_INTAKE.md`, and `APPROVAL_LOG.md`, then calls `verify-install.sh` (line 1238-1242). However, it does not call `validate.sh`. The `verify-install.sh` call checks that files exist and scripts are executable, but does not validate that the upgraded configuration meets the new track's requirements. A project upgraded from Light to Standard may lack required artifacts or CI tools for Standard track, and the upgrade script reports success.

**Root cause (CC-021):** `verify-install.sh` checks scripts (lines 227-254), project structure (lines 136-225), and git hooks (lines 256-278), but does not check whether Claude Code hooks are registered in `.claude/settings.json`. The `check_git` function verifies the pre-commit git hook but not the PreToolUse, PostToolUse, SessionStart, or Stop hooks that power process enforcement. A project can have all scripts present but no hooks wired, and `verify-install.sh` reports a healthy installation.

**Root cause (CC-009):** `init.sh` (lines 1396-1407) adds the PreToolUse hook by checking `PreToolUse[0]` and appending if the command string is not found. If `PreToolUse[0]` exists but has a different matcher (e.g., a Development Guardrails hook with `"matcher": "Write"`), the pre-commit-gate hook is appended to the wrong matcher group. The hook then fires on Write tool calls instead of Bash calls, but exits 0 on unparseable input, so it silently allows all operations.

**Remediation:**

**5a. Add `validate.sh` call after upgrade.**

Add a call to `validate.sh` at the end of `upgrade-project.sh`, after the existing `verify-install.sh` call:

```bash
# Run installation verification after upgrade
if [ -x "scripts/verify-install.sh" ]; then
  echo ""
  print_step "Running post-upgrade verification..."
  bash scripts/verify-install.sh || true
fi

# Run full project validation after upgrade
if [ -x "scripts/validate.sh" ]; then
  echo ""
  print_step "Running post-upgrade validation..."
  if ! bash scripts/validate.sh; then
    echo ""
    print_warn "Post-upgrade validation found issues."
    print_info "Review the output above and address any errors before continuing."
    print_info "The upgrade itself completed successfully — validation checks new track requirements."
  fi
fi
```

The validation call is non-blocking (the upgrade itself already succeeded), but it surfaces any gaps the new track introduces. The Orchestrator sees the validation output immediately after upgrade, not at some indeterminate future point.

**5b. Add hook registration check to `verify-install.sh`.**

Add a new check function to `verify-install.sh` that verifies Claude Code hooks are registered in `.claude/settings.json`:

```bash
check_hooks() {
  print_step "Checking Claude Code hook registration..."

  if [ ! -f ".claude/settings.json" ]; then
    register_manual "Claude Code settings.json missing" "Run init.sh to generate settings"
    return
  fi

  if ! command -v jq &>/dev/null; then
    register_manual "Hook check skipped — jq not available" "Install jq for hook verification"
    return
  fi

  # PreToolUse hook: pre-commit-gate.sh
  if jq -e '.hooks.PreToolUse[] | .hooks[] | select(.command | contains("pre-commit-gate.sh"))' .claude/settings.json >/dev/null 2>&1; then
    register_pass "PreToolUse hook: pre-commit-gate.sh registered"
    # Verify matcher is Bash
    local matcher
    matcher=$(jq -r '.hooks.PreToolUse[] | select(.hooks[] | .command | contains("pre-commit-gate.sh")) | .matcher // "none"' .claude/settings.json 2>/dev/null)
    if [ "$matcher" = "Bash" ]; then
      register_pass "PreToolUse hook matcher: Bash (correct)"
    else
      register_manual "PreToolUse hook matcher is '$matcher' (expected 'Bash')" \
        "Edit .claude/settings.json: set PreToolUse matcher to 'Bash'"
    fi
  else
    register_fixable "PreToolUse hook: pre-commit-gate.sh not registered" "fix_pretooluse_hook"
  fi

  # PostToolUse hook: track-tool-usage.sh
  if jq -e '.hooks.PostToolUse[] | .hooks[] | select(.command | contains("track-tool-usage.sh"))' .claude/settings.json >/dev/null 2>&1; then
    register_pass "PostToolUse hook: track-tool-usage.sh registered"
  else
    register_fixable "PostToolUse hook: track-tool-usage.sh not registered" "fix_posttooluse_hook"
  fi

  # SessionStart hooks
  if jq -e '.hooks.SessionStart[] | .hooks[] | select(.command | contains("session-version-check.sh"))' .claude/settings.json >/dev/null 2>&1; then
    register_pass "SessionStart hook: session-version-check.sh registered"
  else
    register_fixable "SessionStart hook: session-version-check.sh not registered" "fix_session_hook"
  fi
}
```

Add corresponding fix functions that append the hooks to `settings.json` using the same `jq` patterns as `init.sh`.

**5c. Fix hook registration idempotency in `init.sh`.**

Replace the `PreToolUse[0]` append logic with a targeted approach that either finds the existing Bash matcher group or creates a new one:

```bash
# Add pre-commit gate to PreToolUse hook
if jq -e '.hooks.PreToolUse' .claude/settings.json >/dev/null 2>&1; then
  # Check if pre-commit-gate.sh is already registered under ANY matcher
  if ! jq -e '.hooks.PreToolUse[] | .hooks[] | select(.command | contains("pre-commit-gate.sh"))' .claude/settings.json >/dev/null 2>&1; then
    # Find the Bash matcher group index, or create a new one
    BASH_INDEX=$(jq '[.hooks.PreToolUse[] | .matcher] | to_entries[] | select(.value == "Bash") | .key' .claude/settings.json 2>/dev/null || echo "")
    if [ -n "$BASH_INDEX" ]; then
      jq ".hooks.PreToolUse[$BASH_INDEX].hooks += [{\"type\": \"command\", \"command\": \"bash \\\"\$CLAUDE_PROJECT_DIR\\\"/scripts/pre-commit-gate.sh\"}]" .claude/settings.json > .claude/settings.json.tmp \
        && mv .claude/settings.json.tmp .claude/settings.json
    else
      # No Bash matcher group exists — create one
      jq '.hooks.PreToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
        && mv .claude/settings.json.tmp .claude/settings.json
    fi
    hooks_added=true
  fi
else
  jq '.hooks.PreToolUse = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
    && mv .claude/settings.json.tmp .claude/settings.json
  hooks_added=true
fi
```

This ensures the hook is always appended to a group with `"matcher": "Bash"`, regardless of what other matcher groups exist.

**Files to modify:**

| File | Change |
|---|---|
| `scripts/upgrade-project.sh` | Add `validate.sh` call after existing `verify-install.sh` call |
| `scripts/verify-install.sh` | Add `check_hooks` function and corresponding fix functions |
| `init.sh` | Fix PreToolUse hook registration to target Bash matcher group specifically |

**Acceptance criteria:**

- [ ] `upgrade-project.sh --track standard` runs `validate.sh` after upgrade and surfaces any new-track gaps
- [ ] `verify-install.sh` reports missing PreToolUse hook when `pre-commit-gate.sh` not in `settings.json`
- [ ] `verify-install.sh` reports incorrect matcher when PreToolUse hook is registered under non-Bash matcher
- [ ] `verify-install.sh --auto-fix` registers missing hooks correctly
- [ ] `init.sh` on a project with existing PreToolUse Write matcher creates a separate Bash matcher group
- [ ] `init.sh` re-run on a project with correct hooks does not duplicate entries

---

### Group 6: Evaluation Prompt System (CC-007, CC-022)

**Findings addressed:**

| ID | Severity | Finding |
|---|---|---|
| CC-007 | Major | Evaluation prompt results have no canonical storage or tracking |
| CC-022 | Minor | Evaluation results not tied to commit hash |

**Root cause:** The evaluation prompt system (`evaluation-prompts/Projects/run-reviews.sh`) outputs review files to the project root directory with names like `senior-engineer-review-v1.md`. There is no manifest tracking which reviews have been completed, no checksums for tamper detection, no commit hash linking results to a specific codebase state, and no completion tracking. The governance framework requires security review (Phase 3) but has no mechanism to verify it actually happened.

**Remediation:**

**6a. Add commit hash and timestamp metadata to review output.**

Modify `run-reviews.sh` to inject provenance metadata into the Claude prompt, instructing the reviewer to include it in their output header:

```bash
# Before running each review, capture provenance
COMMIT_HASH=$(cd "$PROJECT_DIR" && git rev-parse HEAD 2>/dev/null || echo "no-git")
COMMIT_SHORT=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "no-git")
REVIEW_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Append provenance instruction to the composed prompt
cat >> "$prompt_file" << PROVEOF

---
## Review Provenance (include this header verbatim in your output)

| Field | Value |
|---|---|
| **Reviewed commit** | $COMMIT_HASH |
| **Review timestamp** | $REVIEW_TIMESTAMP |
| **Module** | $MODULE |
| **Reviewer** | $description |
PROVEOF
```

**6b. Add review manifest generation.**

After all reviews complete, generate a manifest file that records what was reviewed, when, and against which commit:

```bash
# After all reviews complete, generate manifest
MANIFEST_FILE="$PROJECT_DIR/docs/eval-results/review-manifest.json"
mkdir -p "$PROJECT_DIR/docs/eval-results"

# Build manifest entries
MANIFEST_ENTRIES=""
for num in "${TARGETS[@]}"; do
  # ... extract reviewer info ...
  REVIEW_FILE="$PROJECT_DIR/${reviewer}-review-v1.md"
  if [ -f "$REVIEW_FILE" ]; then
    FILE_SHA=$(shasum -a 256 "$REVIEW_FILE" | cut -d' ' -f1)
    MANIFEST_ENTRIES="${MANIFEST_ENTRIES}  {\"reviewer\": \"$description\", \"file\": \"${reviewer}-review-v1.md\", \"sha256\": \"$FILE_SHA\", \"commit\": \"$COMMIT_HASH\", \"timestamp\": \"$REVIEW_TIMESTAMP\"},"
  fi
done

# Write manifest
cat > "$MANIFEST_FILE" << MANEOF
{
  "framework_version": "1.0",
  "module": "$MODULE",
  "project_dir": "$PROJECT_DIR",
  "generated_at": "$REVIEW_TIMESTAMP",
  "commit": "$COMMIT_HASH",
  "reviews": [
    ${MANIFEST_ENTRIES%,}
  ]
}
MANEOF
```

**6c. Add review completion check to Phase 3->4 gate.**

In `check-phase-gate.sh`, add a check that verifies the review manifest exists and lists the required reviews when `current_phase >= 3`:

```bash
# Review completion check (Phase 3+)
if [ "$current_phase" -ge 3 ]; then
  MANIFEST="docs/eval-results/review-manifest.json"
  if [ -f "$MANIFEST" ]; then
    if command -v jq &>/dev/null; then
      review_count=$(jq '.reviews | length' "$MANIFEST" 2>/dev/null || echo "0")
      review_commit=$(jq -r '.commit // "unknown"' "$MANIFEST" 2>/dev/null)
      echo -e "${GREEN}  [OK]${NC} Review manifest: $review_count reviews recorded (commit: ${review_commit:0:8})"
    else
      echo -e "${GREEN}  [OK]${NC} Review manifest exists"
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} No review manifest found (docs/eval-results/review-manifest.json)"
    echo "  Run evaluation prompts before Phase 4: evaluation-prompts/Projects/run-reviews.sh"
    issues=$((issues + 1))
  fi
fi
```

**Files to modify:**

| File | Change |
|---|---|
| `evaluation-prompts/Projects/run-reviews.sh` | Add provenance metadata injection and manifest generation |
| `evaluation-prompts/Framework/run-reviews.sh` | Same provenance metadata injection |
| `scripts/check-phase-gate.sh` | Add review manifest existence check for Phase 3+ |

**Acceptance criteria:**

- [ ] Review output files include provenance header with commit hash, timestamp, module, and reviewer
- [ ] `docs/eval-results/review-manifest.json` is generated after `run-reviews.sh` completes
- [ ] Manifest contains SHA-256 checksum for each review file
- [ ] Manifest contains the git commit hash at time of review
- [ ] `check-phase-gate.sh` at Phase 3+ warns when review manifest is absent
- [ ] `check-phase-gate.sh` at Phase 3+ passes when review manifest is present

---

### Group 7: Documentation and Discoverability (CC-015, CC-020, CC-003, CC-010, CC-012, CC-018, CC-019)

**Findings addressed:**

| ID | Severity | Finding |
|---|---|---|
| CC-015 | Minor | No external script documentation (19 scripts with inline docs only) |
| CC-020 | Minor | Builder's Guide does not reference process enforcement system |
| CC-003 | Minor | Python CI missing lockfile integrity check |
| CC-010 | Observation | "other" CI template may lack governance steps |
| CC-012 | Observation | Tool usage tracking uses `set +e` globally |
| CC-018 | Observation | Strict mode not discoverable in CI templates |
| CC-019 | Observation | Intake progress no integrity verification |

**Root cause:** These findings share a common theme: the feature exists and works, but is either undocumented, undiscoverable, or incomplete compared to its counterpart in another language/context. They are individually low-severity but collectively represent documentation and implementation drift.

**Remediation:**

**7a. Add lockfile integrity check to Python CI template (CC-003).**

Add `pip install --require-hashes` verification or `pip hash` check to `python.yml`, providing parity with TypeScript's `npm audit signatures`:

```yaml
- name: Security - Lockfile integrity
  run: |
    # Verify requirements.txt has hash pins (if using pip-tools or pip-compile)
    if [ -f "requirements.txt" ] && grep -q '--hash' requirements.txt; then
      pip install --require-hashes -r requirements.txt --dry-run
    elif [ -f "Pipfile.lock" ]; then
      # Pipenv lockfiles contain hashes by default
      pipenv verify 2>/dev/null || echo "::warning::Pipfile.lock integrity check unavailable (pipenv not installed)"
    elif [ -f "poetry.lock" ]; then
      # Poetry lockfiles contain hashes by default
      poetry check --lock 2>/dev/null || echo "::warning::poetry.lock integrity check unavailable (poetry not installed)"
    else
      echo "::warning::No hash-pinned lockfile found. Consider using pip-compile with --generate-hashes for supply chain integrity."
    fi
```

**7b. Add process enforcement reference to Builder's Guide (CC-020).**

Add a subsection under the existing Enforcement Model section (`builders-guide.md:85-87`):

> **Process enforcement.** In addition to CI and pre-commit checks, a process checklist state machine (`scripts/process-checklist.sh`) mechanically enforces sequential step completion for the Build Loop, UAT sessions, and Phase 3/4 validation. The PreToolUse hook (`scripts/pre-commit-gate.sh`) blocks commits when checklist steps are incomplete. See the User Guide, Section "Process Enforcement," for the complete checklist sequences and their enforcement points.

**7c. Add commented strict mode examples to CI templates (CC-018).**

Add commented-out environment variables to all CI templates showing how to enable strict mode:

```yaml
    env:
      # Uncomment to enable strict enforcement (blocks CI on warnings):
      # SOIF_STRICT_CHANGELOG: "true"   # Require CHANGELOG.md updated every PR
      # SOIF_STRICT_SESSION: "true"     # Require session state recorded
      # SOIF_PHASE_GATES: "enforce"     # Phase gate check blocks (default: warn)
```

**7d. Add inline documentation comment to `track-tool-usage.sh` explaining `set +e` (CC-012).**

```bash
# Don't use set -e — this is an advisory PostToolUse hook that must NEVER block
# the agent's work. If tool-usage.json is corrupted or jq fails, the agent
# continues working and tool tracking silently degrades. This is intentional:
# a tracking failure should not interrupt a build loop.
set +e
```

**7e. Add governance steps to "other" CI template inline comments (CC-010).**

The `other.yml` template already includes the three governance steps (phase gate, changelog, session state). Add a comment block noting that these are language-agnostic and should be preserved when customizing the template:

```yaml
# ─── Governance (language-agnostic — do not remove) ──────────────
# These governance steps apply to ALL languages and should remain
# even when customizing the language-specific steps above.
```

**7f. Document intake progress integrity scope (CC-019).**

Add a comment to `intake-wizard.sh` near the progress save function noting that integrity verification is not implemented and explaining the risk-acceptance rationale:

```bash
# NOTE: intake-progress.json has no integrity verification (checksum/signature).
# For personal deployments, the Orchestrator is both author and consumer, so
# integrity verification adds no security value. For organizational deployments,
# the Intake is reviewed by governance stakeholders who verify content directly.
# Adding checksums would complicate the user experience for negligible benefit.
```

**7g. Script reference table (CC-015).**

Rather than creating a separate documentation file, add a script reference table to the existing User Guide (`user-guide.md`) in the Scripts section. This puts the reference where users already look, avoids documentation drift from a separate file, and is searchable within the document the framework already directs users to read.

| Script | Purpose | Invocation | Phase |
|---|---|---|---|
| `validate.sh` | Project compliance validation | `bash scripts/validate.sh` | Any |
| `check-phase-gate.sh` | Phase transition consistency | `bash scripts/check-phase-gate.sh` | Any |
| `process-checklist.sh` | Sequential step enforcement | `bash scripts/process-checklist.sh --help` | 2+ |
| `pre-commit-gate.sh` | PreToolUse commit gating | Automatic (hook) | 2+ |
| `track-tool-usage.sh` | MCP tool usage tracking | Automatic (hook) | 2+ |
| `session-version-check.sh` | Tool version check on session start | Automatic (hook) | Any |
| `session-test-gate-check.sh` | Test gate status on session start | Automatic (hook) | 2+ |
| `session-end-qdrant-reminder.sh` | Qdrant store reminder on session end | Automatic (hook) | 2+ |
| `intake-wizard.sh` | Guided intake questionnaire | `bash scripts/intake-wizard.sh` | Pre-0 |
| `upgrade-project.sh` | Track/deployment upgrade | `bash scripts/upgrade-project.sh --help` | Any |
| `verify-install.sh` | Installation health check | `bash scripts/verify-install.sh` | Any |
| `check-updates.sh` | Framework update check | `bash scripts/check-updates.sh` | Any |
| `check-versions.sh` | Tool version comparison | `bash scripts/check-versions.sh` | Any |
| `check-changelog.sh` | CHANGELOG.md currency | Automatic (CI) | 2+ |
| `check-session-state.sh` | Session state validation | Automatic (CI) | 2+ |
| `resolve-tools.sh` | Tool dependency resolution | `bash scripts/resolve-tools.sh --help` | Any |
| `test-gate.sh` | Bug gate for phase transitions | `bash scripts/test-gate.sh --help` | 2+ |
| `resume.sh` | Session resumption context | `bash scripts/resume.sh` | Any |
| `reconfigure-project.sh` | Project reconfiguration | `bash scripts/reconfigure-project.sh --help` | Any |

**Files to modify:**

| File | Change |
|---|---|
| `templates/pipelines/ci/python.yml` | Add lockfile integrity step |
| `templates/pipelines/ci/typescript.yml` | Add strict mode comments |
| `templates/pipelines/ci/other.yml` | Add strict mode comments + governance comment block |
| `docs/builders-guide.md` | Add process enforcement subsection to Enforcement Model |
| `scripts/track-tool-usage.sh` | Expand `set +e` comment to document intentional design |
| `scripts/intake-wizard.sh` | Add integrity scope comment near progress save |
| `docs/user-guide.md` | Add script reference table |

**Acceptance criteria:**

- [ ] Python CI template has lockfile integrity check step
- [ ] Python CI template has strict mode environment variable comments
- [ ] TypeScript CI template has strict mode environment variable comments
- [ ] "other" CI template has governance-steps-are-mandatory comment block
- [ ] Builder's Guide enforcement model section references process checklist system
- [ ] `track-tool-usage.sh` has expanded design rationale comment for `set +e`
- [ ] User Guide contains script reference table covering all 19 scripts

---

## Implementation Sequence

| Order | Group | Effort | Rationale |
|---|---|---|---|
| 1 | Group 1: Approval Integrity | 6-10h | Critical finding; blocks audit confidence in all other controls |
| 2 | Group 2: Bypass Closure | 4-6h | Major bypass; agent can currently defeat entire enforcement model |
| 3 | Group 4: Phase Gate Completeness | 3-5h | Major gaps in the most important quality gate (2->3) and CI resilience |
| 4 | Group 3: Validation Coverage | 2-4h | Major validation gap; process enforcement silently inactive when state files missing |
| 5 | Group 5: Upgrade/Install Verification | 3-5h | Major; upgraded projects run without validation, hooks silently absent |
| 6 | Group 6: Evaluation System | 4-6h | Major; governance requires reviews but can't verify they happened |
| 7 | Group 7: Documentation | 3-4h | Minor/Observation; improves discoverability and cross-language parity |

**Total estimated effort:** 25-40 hours

---

## Verification Test Plan

| ID | Group | Test | Method | Expected Result |
|---|---|---|---|---|
| VT-001 | 1 | Delete a line from APPROVAL_LOG.md, push PR | CI pipeline | Build fails: "append-only violation" |
| VT-002 | 1 | Add new approval entry, push PR | CI pipeline | Build succeeds |
| VT-003 | 1 | Commit approval entry as different git author than listed approver | CI pipeline | Warning: author mismatch |
| VT-004 | 2 | Agent runs `process-checklist.sh --reset-all` via Bash tool | PreToolUse hook | Denied: "requires Orchestrator authorization" |
| VT-005 | 2 | Orchestrator runs `--reset-all` in terminal | Interactive terminal | Prompts for confirmation, writes audit log |
| VT-006 | 2 | Agent calls `--reset build_loop` via Bash tool | PreToolUse hook | Denied |
| VT-007 | 3 | Delete `process-state.json`, run `validate.sh` at Phase 2 | `validate.sh` | Error: "process-state.json missing" |
| VT-008 | 3 | Corrupt `process-state.json` (invalid JSON), run `validate.sh` | `validate.sh` | Error: "invalid JSON" |
| VT-009 | 3 | Run `session-version-check.sh` with tool below minimum | `session-version-check.sh` | URGENT output block |
| VT-010 | 4 | Set `current_phase: 3`, no `phase_2_to_3` date | `check-phase-gate.sh` | Inconsistency: "gate date not recorded" |
| VT-011 | 4 | Delete `check-phase-gate.sh`, push PR with `phase-state.json` | CI pipeline | Build fails: "script missing" |
| VT-012 | 4 | Run `check-phase-gate.sh` on system without jq | Bash | Script completes (grep fallback) |
| VT-013 | 5 | Run `upgrade-project.sh --track standard` from Light | Upgrade script | `validate.sh` runs after upgrade, surfaces any gaps |
| VT-014 | 5 | Remove hooks from `settings.json`, run `verify-install.sh` | `verify-install.sh` | Reports missing hooks |
| VT-015 | 5 | Run `verify-install.sh --auto-fix` with missing hooks | `verify-install.sh` | Hooks registered in `settings.json` |
| VT-016 | 5 | Run `init.sh` on project with existing Write matcher PreToolUse | `init.sh` | Creates separate Bash matcher group, not appended to Write |
| VT-017 | 6 | Run `run-reviews.sh web-app 1` on a project | `run-reviews.sh` | Output includes provenance header with commit hash |
| VT-018 | 6 | Run `run-reviews.sh web-app`, check manifest | `run-reviews.sh` | `docs/eval-results/review-manifest.json` generated with SHA-256 checksums |
| VT-019 | 6 | Set `current_phase: 3`, no review manifest | `check-phase-gate.sh` | Warning: "No review manifest found" |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CI approval check false positives on merge commits | Medium | Medium | Test with squash merges, merge commits, and rebase workflows before deployment |
| Hook registration fix breaks existing projects on init re-run | Low | High | Test on project with existing hooks; verify idempotency |
| Review manifest dependency on jq in check-phase-gate.sh | Low | Low | Already mitigated by jq guard (Group 4b) |
| Strict mode comments confuse users who uncomment without understanding | Low | Low | Comments include link to User Guide section explaining each mode |

---

## Dependency Map

```
Group 1 (Approval Integrity)
  Independent — no dependencies
  Unblocks: governance confidence for all other groups

Group 2 (Bypass Closure)
  Independent — no dependencies
  Unblocks: trust in process enforcement system

Group 3 (Validation Coverage)
  Independent — no dependencies

Group 4 (Phase Gate Completeness)
  Independent — no dependencies
  Partially unblocks Group 6 (review manifest check added to same file)

Group 5 (Upgrade/Install Verification)
  Depends on: Group 3 (validate.sh changes must be in place before upgrade calls it)
  Depends on: Group 4 (check-phase-gate.sh changes should be stable before verify-install.sh checks hooks)

Group 6 (Evaluation System)
  Depends on: Group 4 (review manifest check added to check-phase-gate.sh)

Group 7 (Documentation)
  Depends on: Groups 1-6 (documentation should reflect implemented state, not planned state)
```

---

## Summary

| Severity | Count | Addressed |
|---|---|---|
| Critical | 1 | 1 (Group 1) |
| Major | 9 | 9 (Groups 1-6) |
| Minor | 8 | 8 (Groups 3, 4, 5, 6, 7) |
| Observation | 4 | 4 (Group 7) |
| **Total** | **22** | **22** |

| Group | Findings | Files Modified | Effort |
|---|---|---|---|
| 1. Approval Integrity | CC-004, CC-014 | 4 files | 6-10h |
| 2. Bypass Closure | CC-011, CC-005 | 3 files | 4-6h |
| 3. Validation Coverage | CC-001, CC-016, CC-006 | 2 files | 2-4h |
| 4. Phase Gate Completeness | CC-002, CC-013, CC-017 | 4 files | 3-5h |
| 5. Upgrade/Install Verification | CC-008, CC-021, CC-009 | 3 files | 3-5h |
| 6. Evaluation System | CC-007, CC-022 | 3 files | 4-6h |
| 7. Documentation | CC-015, CC-020, CC-003, CC-010, CC-012, CC-018, CC-019 | 7 files | 3-4h |

**Total files modified:** 11 unique files (some modified by multiple groups)
**Total estimated effort:** 25-40 hours

Every finding is addressed. No finding is deferred or risk-accepted without explicit rationale. The implementation sequence prioritizes the Critical approval integrity gap, then closes enforcement bypasses, then fills validation and gate coverage, then rounds out documentation. Groups 1-4 can proceed in parallel; Groups 5-7 have soft dependencies on earlier groups.

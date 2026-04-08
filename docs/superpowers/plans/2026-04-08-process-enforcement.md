# Process Enforcement & Tool Usage Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mechanical enforcement for sequential process compliance (Build Loop, UAT, Phase 3, Phase 4) and MCP tool usage tracking (Context7, Qdrant) via Claude Code hooks.

**Architecture:** Process state machine in `.claude/process-state.json` + checkpoint script (`process-checklist.sh`) + PreToolUse hook that blocks `git commit`/`gh pr create` when checklist is incomplete + PostToolUse hook that tracks MCP tool calls. Auto-detection of commit type via phase state + staged file inspection.

**Tech Stack:** Bash, jq, Claude Code hooks (PreToolUse, PostToolUse, SessionStart, Stop)

**Spec:** `docs/superpowers/specs/2026-04-08-process-enforcement-design.md`

---

## Task 1: Create branch and process-checklist.sh (core state machine)

**Files:**
- Create: `scripts/process-checklist.sh`

This is the largest script (~300 lines). It manages `.claude/process-state.json` — starting processes, completing steps in order, checking commit readiness, and verifying Phase 2 initialization.

- [ ] **Step 1: Create the feature branch**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
git checkout main
git pull origin main
git checkout -b feat/process-enforcement
```

- [ ] **Step 2: Create `scripts/process-checklist.sh`**

The script must implement these commands:
- `--start-feature "name"` — reset build_loop, set feature name
- `--complete-step PROCESS:STEP_ID` — mark step complete with ordering validation
- `--start-uat N` — initialize UAT session N
- `--start-phase3` — initialize Phase 3 validation
- `--start-phase4` — initialize Phase 4 release
- `--verify-init` — run Phase 2 initialization verification (auto-check + manual attestation)
- `--status` — print human-readable state
- `--check-commit-ready` — return 0 (allowed) or 1 (blocked) with reason. Used by PreToolUse hook.
- `--reset PROCESS` — clear one process state
- `--reset-all` — clear everything

**Step sequences (hardcoded in the script as bash arrays):**

```bash
BUILD_LOOP_STEPS=(tests_written tests_verified_failing implemented security_audit documentation_updated feature_recorded)
UAT_STEPS=(agents_dispatched template_generated orchestrator_notified results_received completeness_verified bugs_consolidated triage_complete remediation_complete gate_passed)
PHASE3_STEPS=(integration_testing security_hardening chaos_testing accessibility_audit performance_audit contract_testing results_archived)
PHASE4_STEPS=(production_build rollback_tested go_live_verified monitoring_configured handoff_written)
PHASE2_INIT_STEPS=(remote_repo_created branch_protection_configured project_scaffolded data_model_applied pre_commit_hooks_installed ci_pipeline_configured initialization_verified)
```

**Key implementation details:**

The state file is `.claude/process-state.json`. Use jq for all reads and writes. Follow the pattern from `test-gate.sh` — use `jq '...' FILE > FILE.tmp && mv FILE.tmp FILE` for atomic writes.

The `--complete-step` command must:
1. Parse `PROCESS:STEP_ID` (split on colon)
2. Look up the step sequence array for that process
3. Find the index of STEP_ID in the array
4. Check that all prior steps are in the `steps_completed` array
5. If a prior step is missing, exit 1 with: `"Cannot complete 'STEP_ID' — 'MISSING_STEP' not yet completed. Run: scripts/process-checklist.sh --complete-step PROCESS:MISSING_STEP"`
6. Add STEP_ID to steps_completed and update step number

The `--check-commit-ready` command must:
1. Read current_phase from `.claude/phase-state.json` (exit 0 if phase < 2 or file missing)
2. If phase == 2 and `phase2_init.verified` is false, exit 1 with init message
3. Read staged files via `git diff --cached --name-only`
4. Classify commit: check if any staged file has a source extension (`.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.rs`, `.go`, `.cs`, `.kt`, `.java`, `.dart`, `.swift`, `.c`, `.cpp`, `.h`) or is in a source directory (`src/`, `lib/`, `app/`, `pkg/`, `internal/`, `cmd/`). If all staged files are `.md`, `.json`, `.yml`, `.toml`, `.tmpl` → docs commit → exit 0
5. For Phase 2 source commits: check build_loop.feature is not null, check steps_completed includes all steps up to `documentation_updated`, check no UAT session in progress with incomplete steps
6. For Phase 3: check phase3_validation steps
7. For Phase 4: check phase4_release steps

The `--verify-init` command must auto-check what it can:
- `git remote get-url origin` succeeds → remote_repo_created
- `.github/workflows/ci.yml` exists → branch_protection_configured, ci_pipeline_configured
- Lockfile exists (check: `package-lock.json`, `Pipfile.lock`, `poetry.lock`, `Cargo.lock`, `go.sum`, `pubspec.lock`, `Package.resolved`) → project_scaffolded
- `.git/hooks/pre-commit` exists and is executable → pre_commit_hooks_installed
- `data_model_applied` → cannot auto-check, print: `"Cannot auto-verify: data model applied and backup/restore tested. Has this been completed? Mark with: scripts/process-checklist.sh --complete-step phase2_init:data_model_applied"`

The `--status` command should print a human-readable summary of each process, showing which steps are completed and which remain.

The `--reset` and `--reset-all` commands should log to stderr: `"[RESET] Process PROCESS reset at $(date -u +%Y-%m-%dT%H:%M:%SZ)"` so escapes are visible in session history.

Make it executable: `chmod +x scripts/process-checklist.sh`

- [ ] **Step 3: Verify syntax**

```bash
bash -n scripts/process-checklist.sh && echo "Syntax OK"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/process-checklist.sh
git commit -m "feat: add process-checklist.sh — state machine for sequential process enforcement"
```

---

## Task 2: Create pre-commit-gate.sh (PreToolUse hook)

**Files:**
- Create: `scripts/pre-commit-gate.sh`

This is the PreToolUse hook that fires before Bash tool calls. It reads the bash command from stdin (Claude Code passes tool input as JSON), checks if it's a `git commit` or `gh pr create`, and blocks if the process checklist isn't satisfied.

- [ ] **Step 1: Create `scripts/pre-commit-gate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — PreToolUse hook for commit gating
# Blocks git commit and gh pr create when process checklist is incomplete.
# Registered as a PreToolUse hook on Bash tool calls.
#
# Input: Claude Code passes tool input JSON on stdin
# Output:
#   - No output = allow
#   - JSON with permissionDecision: "deny" = block

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read the tool input from stdin
INPUT=$(cat)

# Extract the bash command from the JSON input
# Claude Code passes: {"command": "git commit -m '...'", ...}
COMMAND=$(echo "$INPUT" | jq -r '.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only gate git commit and gh pr create
IS_COMMIT=false
IS_PR=false
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  IS_COMMIT=true
elif echo "$COMMAND" | grep -qE '^\s*gh\s+pr\s+create'; then
  IS_PR=true
fi

if [ "$IS_COMMIT" = false ] && [ "$IS_PR" = false ]; then
  exit 0
fi

# Run process checklist check
CHECKLIST_OUTPUT=""
CHECKLIST_EXIT=0
CHECKLIST_OUTPUT=$("$SCRIPT_DIR/process-checklist.sh" --check-commit-ready 2>&1) || CHECKLIST_EXIT=$?

if [ "$CHECKLIST_EXIT" -ne 0 ]; then
  # Block the commit
  REASON=$(echo "$CHECKLIST_OUTPUT" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$REASON"}}
HOOKEOF
  exit 0
fi

# For PR creation: additional checks
if [ "$IS_PR" = true ]; then
  # Check no UAT session in progress
  PROCESS_STATE=".claude/process-state.json"
  if [ -f "$PROCESS_STATE" ] && command -v jq &>/dev/null; then
    UAT_STARTED=$(jq -r '.uat_session.started_at // empty' "$PROCESS_STATE" 2>/dev/null)
    if [ -n "$UAT_STARTED" ]; then
      UAT_STEPS_DONE=$(jq -r '.uat_session.steps_completed | length' "$PROCESS_STATE" 2>/dev/null)
      if [ "$UAT_STEPS_DONE" -lt 9 ]; then
        cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "UAT session in progress with incomplete steps ($UAT_STEPS_DONE/9). Complete all UAT steps before creating a PR."}}
HOOKEOF
        exit 0
      fi
    fi

    # Check build_loop is at step 0 or fully complete
    BUILD_FEATURE=$(jq -r '.build_loop.feature // empty' "$PROCESS_STATE" 2>/dev/null)
    if [ -n "$BUILD_FEATURE" ]; then
      BUILD_STEPS_DONE=$(jq -r '.build_loop.steps_completed | length' "$PROCESS_STATE" 2>/dev/null)
      if [ "$BUILD_STEPS_DONE" -gt 0 ] && [ "$BUILD_STEPS_DONE" -lt 6 ]; then
        cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Feature '$BUILD_FEATURE' has incomplete Build Loop ($BUILD_STEPS_DONE/6 steps). Complete the feature or reset before creating a PR."}}
HOOKEOF
        exit 0
      fi
    fi
  fi
fi

# Process checklist passed. Now check tool usage (warnings only, not blocking).
TOOL_USAGE=".claude/tool-usage.json"
PHASE_STATE=".claude/phase-state.json"
WARNINGS=""

if [ "$IS_COMMIT" = true ] && [ -f "$TOOL_USAGE" ] && [ -f "$PHASE_STATE" ] && command -v jq &>/dev/null; then
  CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null)

  if [ "$CURRENT_PHASE" = "2" ]; then
    # Check if this is a source commit (reuse staged file check)
    HAS_SOURCE=false
    STAGED=$(git diff --cached --name-only 2>/dev/null || true)
    if echo "$STAGED" | grep -qE '\.(py|ts|tsx|js|jsx|rs|go|cs|kt|java|dart|swift|c|cpp|h)$'; then
      HAS_SOURCE=true
    elif echo "$STAGED" | grep -qE '^(src|lib|app|pkg|internal|cmd)/'; then
      HAS_SOURCE=true
    fi

    if [ "$HAS_SOURCE" = true ]; then
      # Context7 check
      COMMITS_SINCE_CTX7=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
      if [ "$COMMITS_SINCE_CTX7" -ge 2 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}Context7 has not been consulted for library documentation in the last $COMMITS_SINCE_CTX7 commits. Consider checking docs for libraries used in this change. "
      fi

      # Qdrant-find check (first commit of session only)
      QDRANT_FIND=$(jq -r '.qdrant_find_called // false' "$TOOL_USAGE" 2>/dev/null)
      if [ "$QDRANT_FIND" = "false" ]; then
        WARNINGS="${WARNINGS}No prior context retrieved from Qdrant this session. Consider checking for relevant architecture decisions and patterns. "
      fi
    fi
  fi
fi

if [ -n "$WARNINGS" ]; then
  # Output warnings as additional context (not blocking)
  ESCAPED_WARNINGS=$(echo "$WARNINGS" | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "TOOL USAGE WARNINGS: $ESCAPED_WARNINGS"}}
HOOKEOF
fi

# If we reach here with no output, the commit is allowed silently
exit 0
```

Make it executable: `chmod +x scripts/pre-commit-gate.sh`

- [ ] **Step 2: Verify syntax**

```bash
bash -n scripts/pre-commit-gate.sh && echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/pre-commit-gate.sh
git commit -m "feat: add pre-commit-gate.sh — PreToolUse hook for commit gating"
```

---

## Task 3: Create track-tool-usage.sh (PostToolUse hook)

**Files:**
- Create: `scripts/track-tool-usage.sh`

This is the PostToolUse hook that fires after every tool call. It must be fast — for non-MCP tools it exits immediately with no disk I/O.

- [ ] **Step 1: Create `scripts/track-tool-usage.sh`**

```bash
#!/usr/bin/env bash
# Solo Orchestrator — PostToolUse hook for MCP tool usage tracking
# Logs Context7 and Qdrant tool calls to .claude/tool-usage.json.
# Fires after every tool call — must be fast for non-MCP tools.

# Don't use set -e — we never want this hook to block anything
set +e

TOOL_USAGE=".claude/tool-usage.json"

# Read tool info from stdin (Claude Code passes PostToolUse JSON)
INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [ -z "$TOOL_NAME" ]; then
  exit 0
fi

# Fast exit for non-MCP, non-commit tools (vast majority of calls)
case "$TOOL_NAME" in
  *context7*|*qdrant*) ;; # Continue to tracking logic
  Bash)
    # Check if this is a git commit (to increment counter)
    BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if echo "$BASH_CMD" | grep -qE '^\s*git\s+commit' 2>/dev/null; then
      if [ -f "$TOOL_USAGE" ] && command -v jq &>/dev/null; then
        CURRENT=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
        jq ".commits_since_last_context7 = $((CURRENT + 1))" "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
      fi
    fi
    exit 0
    ;;
  *) exit 0 ;; # Not an MCP tool, not a commit — exit fast
esac

# Ensure tool-usage.json exists
if [ ! -f "$TOOL_USAGE" ]; then
  mkdir -p .claude
  cat > "$TOOL_USAGE" << 'EOF'
{
  "session_id": null,
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false
}
EOF
fi

command -v jq &>/dev/null || exit 0

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Track Context7 calls
if echo "$TOOL_NAME" | grep -q "context7" 2>/dev/null; then
  jq --arg tool "$TOOL_NAME" --arg ts "$TIMESTAMP" \
    '.calls += [{"tool": $tool, "timestamp": $ts}] | .commits_since_last_context7 = 0' \
    "$TOOL_USAGE" > "$TOOL_USAGE.tmp" && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE"
fi

# Track Qdrant calls
if echo "$TOOL_NAME" | grep -q "qdrant" 2>/dev/null; then
  if echo "$TOOL_NAME" | grep -q "find" 2>/dev/null; then
    jq --arg tool "$TOOL_NAME" --arg ts "$TIMESTAMP" \
      '.calls += [{"tool": $tool, "timestamp": $ts}] | .qdrant_find_called = true' \
      "$TOOL_USAGE" > "$TOOL_USAGE.tmp" && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE"
  elif echo "$TOOL_NAME" | grep -q "store" 2>/dev/null; then
    jq --arg tool "$TOOL_NAME" --arg ts "$TIMESTAMP" \
      '.calls += [{"tool": $tool, "timestamp": $ts}] | .qdrant_store_called = true' \
      "$TOOL_USAGE" > "$TOOL_USAGE.tmp" && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE"
  fi
fi

exit 0
```

Make it executable: `chmod +x scripts/track-tool-usage.sh`

- [ ] **Step 2: Verify syntax**

```bash
bash -n scripts/track-tool-usage.sh && echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/track-tool-usage.sh
git commit -m "feat: add track-tool-usage.sh — PostToolUse hook for MCP tool tracking"
```

---

## Task 4: Update init.sh — generate state files and register hooks

**Files:**
- Modify: `init.sh`

Add generation of `.claude/process-state.json` and `.claude/tool-usage.json`, copy the new scripts, and register PreToolUse and PostToolUse hooks.

- [ ] **Step 1: Read init.sh to find insertion points**

Read the file to find:
1. Where `.claude/build-progress.json` is generated (around line 1439) — add `process-state.json` and `tool-usage.json` generation nearby
2. Where scripts are copied (around line 1039-1057) — add new scripts
3. Where hooks are registered (around line 1359-1395) — add PreToolUse and PostToolUse hooks

- [ ] **Step 2: Add process-state.json generation**

After the `build-progress.json` generation block, add:

```bash
  # Generate process state file
  cat > .claude/process-state.json << 'PSEOF'
{
  "build_loop": {
    "feature": null,
    "step": 0,
    "steps_completed": [],
    "started_at": null
  },
  "uat_session": {
    "session_id": null,
    "step": 0,
    "steps_completed": [],
    "started_at": null
  },
  "phase3_validation": {
    "steps_completed": [],
    "started_at": null
  },
  "phase4_release": {
    "steps_completed": [],
    "started_at": null
  },
  "phase2_init": {
    "steps_completed": [],
    "verified": false
  }
}
PSEOF

  # Generate tool usage tracking file
  cat > .claude/tool-usage.json << 'TUEOF'
{
  "session_id": null,
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false
}
TUEOF
```

- [ ] **Step 3: Add script copying**

In the script copying section (after the existing `cp` lines for scripts), add:

```bash
  cp "$SCRIPT_DIR/scripts/process-checklist.sh" scripts/
  cp "$SCRIPT_DIR/scripts/pre-commit-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/track-tool-usage.sh" scripts/
```

And add them to the `chmod +x` line that makes all scripts executable.

- [ ] **Step 4: Add PreToolUse and PostToolUse hook registration**

In the hook registration section (after the existing SessionStart and Stop hook registrations), add:

```bash
        # Add pre-commit gate to PreToolUse hook
        if jq -e '.hooks.PreToolUse' .claude/settings.json >/dev/null 2>&1; then
          if ! jq -e '.hooks.PreToolUse[0].hooks[] | select(.command | contains("pre-commit-gate.sh"))' .claude/settings.json >/dev/null 2>&1; then
            jq '.hooks.PreToolUse[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
              && mv .claude/settings.json.tmp .claude/settings.json
            hooks_added=true
          fi
        else
          jq '.hooks.PreToolUse = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi

        # Add tool usage tracking to PostToolUse hook
        if jq -e '.hooks.PostToolUse' .claude/settings.json >/dev/null 2>&1; then
          if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("track-tool-usage.sh"))' .claude/settings.json >/dev/null 2>&1; then
            jq '.hooks.PostToolUse[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
              && mv .claude/settings.json.tmp .claude/settings.json
            hooks_added=true
          fi
        else
          jq '.hooks.PostToolUse = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh"}]}]' .claude/settings.json > .claude/settings.json.tmp \
            && mv .claude/settings.json.tmp .claude/settings.json
          hooks_added=true
        fi
```

Update the success message to include the new hooks:
```bash
          print_ok "Session hooks installed (version check, test gate, Qdrant reminder, commit gate, tool tracking)"
```

- [ ] **Step 5: Verify syntax**

```bash
bash -n init.sh && echo "Syntax OK"
```

- [ ] **Step 6: Commit**

```bash
git add init.sh
git commit -m "feat: update init.sh to generate process state files and register enforcement hooks"
```

---

## Task 5: Update session hooks (start and end)

**Files:**
- Modify: `scripts/session-test-gate-check.sh`
- Modify: `scripts/session-end-qdrant-reminder.sh`

- [ ] **Step 1: Add tool-usage.json reset to SessionStart hook**

Read `scripts/session-test-gate-check.sh`. At the top of the script (after the shebang and `set -euo pipefail`), add:

```bash
# Reset tool usage tracking for new session
TOOL_USAGE=".claude/tool-usage.json"
if command -v jq &>/dev/null; then
  SESSION_ID=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p .claude
  cat > "$TOOL_USAGE" << TUEOF
{
  "session_id": "$SESSION_ID",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false
}
TUEOF
fi
```

- [ ] **Step 2: Add tool usage summary to Stop hook**

Read `scripts/session-end-qdrant-reminder.sh`. After the existing Qdrant reminder output (after the `EOF` that closes the reminder), add:

```bash
# Tool usage summary
TOOL_USAGE=".claude/tool-usage.json"
PHASE_STATE=".claude/phase-state.json"

if [ -f "$TOOL_USAGE" ] && command -v jq &>/dev/null; then
  CTX7_COUNT=$(jq '[.calls[] | select(.tool | contains("context7"))] | length' "$TOOL_USAGE" 2>/dev/null || echo "0")
  QDRANT_FIND_COUNT=$(jq '[.calls[] | select(.tool | contains("qdrant")) | select(.tool | contains("find"))] | length' "$TOOL_USAGE" 2>/dev/null || echo "0")
  QDRANT_STORE_COUNT=$(jq '[.calls[] | select(.tool | contains("qdrant")) | select(.tool | contains("store"))] | length' "$TOOL_USAGE" 2>/dev/null || echo "0")

  echo ""
  echo "TOOL USAGE THIS SESSION: Context7: $CTX7_COUNT calls | Qdrant-find: $QDRANT_FIND_COUNT calls | Qdrant-store: $QDRANT_STORE_COUNT calls"

  # Phase 2 warnings
  CURRENT_PHASE="0"
  if [ -f "$PHASE_STATE" ]; then
    CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null)
  fi

  if [ "$CURRENT_PHASE" = "2" ]; then
    COMMITS_MADE=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
    QDRANT_STORED=$(jq -r '.qdrant_store_called // false' "$TOOL_USAGE" 2>/dev/null)

    if [ "$COMMITS_MADE" -gt 0 ] 2>/dev/null && [ "$QDRANT_STORED" = "false" ]; then
      echo ""
      echo "WARNING: You made source commits this session but stored nothing in Qdrant."
      echo "Before ending, store any architecture decisions, debugging breakthroughs, or integration patterns."
    fi

    if [ "$CTX7_COUNT" -eq 0 ] 2>/dev/null && [ "$COMMITS_MADE" -gt 0 ] 2>/dev/null; then
      echo ""
      echo "WARNING: Source code was committed but Context7 was never consulted."
      echo "If you used library APIs, check Context7 for current documentation next session."
    fi
  fi
fi
```

- [ ] **Step 3: Verify syntax on both files**

```bash
bash -n scripts/session-test-gate-check.sh && echo "session-test-gate-check.sh: OK"
bash -n scripts/session-end-qdrant-reminder.sh && echo "session-end-qdrant-reminder.sh: OK"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/session-test-gate-check.sh scripts/session-end-qdrant-reminder.sh
git commit -m "feat: add tool usage tracking to session start/end hooks"
```

---

## Task 6: Update CLAUDE.md template with process checklist commands

**Files:**
- Modify: `templates/generated/claude-md.tmpl`

Add process checklist commands at the Build Loop, UAT, Phase 3, and Phase 4 sections so the agent knows to call them.

- [ ] **Step 1: Read the current CLAUDE.md template**

Read `templates/generated/claude-md.tmpl` to find the exact insertion points.

- [ ] **Step 2: Add Build Loop process enforcement**

Find the Construction Rules section (around line 68). After the existing rules (after the line about `Document as you go`), add:

```markdown
- **Process enforcement:** Before starting each feature, run:
  `scripts/process-checklist.sh --start-feature "feature-name"`
  After completing each Build Loop step, mark it:
  - Tests written: `scripts/process-checklist.sh --complete-step build_loop:tests_written`
  - Tests verified failing: `scripts/process-checklist.sh --complete-step build_loop:tests_verified_failing`
  - Implementation complete: `scripts/process-checklist.sh --complete-step build_loop:implemented`
  - Security audit done: `scripts/process-checklist.sh --complete-step build_loop:security_audit`
  - Documentation updated: `scripts/process-checklist.sh --complete-step build_loop:documentation_updated`
  - Feature recorded: `scripts/process-checklist.sh --complete-step build_loop:feature_recorded`
  **Commits are blocked until all steps are completed in order.**
```

- [ ] **Step 3: Add UAT process enforcement**

Find the Testing & Bug Workflow section (around line 141). After step 1 (`Check the gate: scripts/test-gate.sh --check-batch`), add:

```markdown
  1a. Start the UAT checklist: `scripts/process-checklist.sh --start-uat N` (where N is the session number)
```

Then after each existing UAT step (2-9), reference the corresponding `--complete-step` call. Add after the step 9 line (`Reset counter: scripts/test-gate.sh --reset-counter`):

```markdown
  After completing each UAT step, mark it:
  `scripts/process-checklist.sh --complete-step uat_session:STEP_ID`
  Steps: agents_dispatched, template_generated, orchestrator_notified, results_received,
  completeness_verified, bugs_consolidated, triage_complete, remediation_complete, gate_passed.
  **Bug fix commits are blocked until the full UAT checklist is complete.**
```

- [ ] **Step 4: Add Phase 3 and Phase 4 enforcement**

In the "Phase 3-4 Documentation" section that was added in the documentation remediation, add:

```markdown
- **Phase 3 enforcement:** Run `scripts/process-checklist.sh --start-phase3` at the beginning of Phase 3.
  Mark each validation step: `scripts/process-checklist.sh --complete-step phase3_validation:STEP_ID`
  Steps: integration_testing, security_hardening, chaos_testing, accessibility_audit, performance_audit, contract_testing, results_archived.
- **Phase 4 enforcement:** Run `scripts/process-checklist.sh --start-phase4` at the beginning of Phase 4.
  Mark each release step: `scripts/process-checklist.sh --complete-step phase4_release:STEP_ID`
  Steps: production_build, rollback_tested, go_live_verified, monitoring_configured, handoff_written.
  **The rollback_tested step must be completed before go_live_verified can be marked.**
```

- [ ] **Step 5: Commit**

```bash
git add templates/generated/claude-md.tmpl
git commit -m "feat: add process checklist commands to CLAUDE.md template"
```

---

## Task 7: Update Builder's Guide with checkpoint references

**Files:**
- Modify: `docs/builders-guide.md`

Add checkpoint script calls inline at each step in the Build Loop, UAT flow, Phase 3, and Phase 4.

- [ ] **Step 1: Read the Builder's Guide sections**

Read the Build Loop (Steps 2.2-2.5), UAT (Steps 2.7-2.9), Phase 3 (Steps 3.1-3.5.9), and Phase 4 (Steps 4.1-4.5) sections.

- [ ] **Step 2: Add checkpoint calls to Build Loop**

After Step 2.2 (Write Tests First), add:
```markdown
**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:tests_written`
After verifying tests fail: `scripts/process-checklist.sh --complete-step build_loop:tests_verified_failing`
```

After Step 2.3 (Implement the Feature), add:
```markdown
**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:implemented`
```

After Step 2.4 (Security & Quality Audit), add:
```markdown
**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:security_audit`
```

After Step 2.5 (Update Documentation), add:
```markdown
**Process checkpoint:** `scripts/process-checklist.sh --complete-step build_loop:documentation_updated`
After recording the feature: `scripts/process-checklist.sh --complete-step build_loop:feature_recorded`
```

- [ ] **Step 3: Add checkpoint calls to UAT flow**

At the start of Step 2.7, add:
```markdown
**Process checkpoint:** Start the UAT session: `scripts/process-checklist.sh --start-uat N`
```

After each sub-step within 2.7, 2.8, and 2.9, add the corresponding `--complete-step uat_session:STEP_ID` call.

- [ ] **Step 4: Add checkpoint calls to Phase 3**

At the start of Phase 3, add:
```markdown
**Process checkpoint:** Start Phase 3 validation: `scripts/process-checklist.sh --start-phase3`
```

After each step (3.1 through 3.5.9), add `scripts/process-checklist.sh --complete-step phase3_validation:STEP_ID`.

- [ ] **Step 5: Add checkpoint calls to Phase 4**

At the start of Phase 4, add:
```markdown
**Process checkpoint:** Start Phase 4 release: `scripts/process-checklist.sh --start-phase4`
```

After each step (4.1 through 4.5), add `scripts/process-checklist.sh --complete-step phase4_release:STEP_ID`.

- [ ] **Step 6: Commit**

```bash
git add docs/builders-guide.md
git commit -m "feat: add process checkpoint references to Builder's Guide"
```

---

## Task 8: Update User Guide with enforcement explanation

**Files:**
- Modify: `docs/user-guide.md`

Add a section explaining the process enforcement system.

- [ ] **Step 1: Read the User Guide enforcement section**

Read `docs/user-guide.md` to find the "What Is Enforced vs. What Is Guided" section (or equivalent). This is where the three-tier enforcement model is explained.

- [ ] **Step 2: Add process enforcement explanation**

In the enforcement section, add a new subsection:

```markdown
### Process Enforcement (Tier 2)

The framework mechanically enforces sequential process compliance through a state machine and commit gating system. Four processes are gated:

1. **Build Loop** (Phase 2) — tests → verify failing → implement → security audit → documentation → record feature. Each step must be completed in order. Source commits are blocked until all steps pass.
2. **UAT Session** (Phase 2) — 9-step testing flow. Bug fix commits are blocked until the full session checklist is complete.
3. **Phase 3 Validation** — all 6 validation types must be completed and results archived.
4. **Phase 4 Release** — rollback must be tested before go-live verification.

The agent calls `scripts/process-checklist.sh --complete-step PROCESS:STEP` to advance through each process. A PreToolUse hook on `git commit` and `gh pr create` blocks when required steps are incomplete.

**What the Orchestrator sees:** When the agent attempts a commit with incomplete steps, Claude Code displays the block reason: "Build Loop step 'security_audit' not completed." The agent must complete the missing step and retry.

**Tool usage tracking:** During Phase 2, the framework also tracks whether the agent consulted Context7 (library documentation) and Qdrant (persistent memory). Warnings appear at commit time and session end if these tools were not used. These are warnings, not blocks.

**Emergency escape:** If the enforcement system blocks a legitimate action due to a bug or edge case, the Orchestrator (not the agent) can run `scripts/process-checklist.sh --reset PROCESS` to clear the state.
```

- [ ] **Step 3: Commit**

```bash
git add docs/user-guide.md
git commit -m "feat: add process enforcement documentation to User Guide"
```

---

## Task 9: Verification and final checks

- [ ] **Step 1: Verify all new scripts exist and have correct permissions**

```bash
ls -la scripts/process-checklist.sh scripts/pre-commit-gate.sh scripts/track-tool-usage.sh
```

Expected: All 3 files exist and are executable (-rwxr-xr-x).

- [ ] **Step 2: Syntax check all modified scripts**

```bash
bash -n scripts/process-checklist.sh && echo "process-checklist.sh: OK"
bash -n scripts/pre-commit-gate.sh && echo "pre-commit-gate.sh: OK"
bash -n scripts/track-tool-usage.sh && echo "track-tool-usage.sh: OK"
bash -n scripts/session-test-gate-check.sh && echo "session-test-gate-check.sh: OK"
bash -n scripts/session-end-qdrant-reminder.sh && echo "session-end-qdrant-reminder.sh: OK"
bash -n init.sh && echo "init.sh: OK"
```

Expected: All 6 report OK.

- [ ] **Step 3: Verify process-checklist.sh commands work**

```bash
# Create a temporary process-state.json for testing
mkdir -p /tmp/test-enforcement/.claude
cat > /tmp/test-enforcement/.claude/process-state.json << 'EOF'
{"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{"session_id":null,"step":0,"steps_completed":[],"started_at":null},"phase3_validation":{"steps_completed":[],"started_at":null},"phase4_release":{"steps_completed":[],"started_at":null},"phase2_init":{"steps_completed":[],"verified":false}}
EOF
cat > /tmp/test-enforcement/.claude/phase-state.json << 'EOF'
{"project":"test","current_phase":"2","track":"standard","deployment":"personal","gates":{"phase_0_to_1":"2026-04-01","phase_1_to_2":"2026-04-05"}}
EOF

cd /tmp/test-enforcement

# Test: start feature
bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/process-checklist.sh" --start-feature "test-feature"
echo "Exit: $?"

# Test: complete step in order (should pass)
bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/process-checklist.sh" --complete-step build_loop:tests_written
echo "Exit: $?"

# Test: complete step out of order (should fail)
bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/process-checklist.sh" --complete-step build_loop:implemented 2>&1
echo "Exit: $?"

# Test: status
bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/process-checklist.sh" --status

# Cleanup
rm -rf /tmp/test-enforcement
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
```

Expected: start-feature exits 0, in-order step exits 0, out-of-order step exits 1 with error message, status shows readable output.

- [ ] **Step 4: Review commit log**

```bash
git log --oneline feat/process-enforcement ^main
```

- [ ] **Step 5: Commit any fixes from verification**

If any issues found during testing, fix and commit.

---

## Summary

| Task | Commits | What Changes |
|---|---|---|
| 1 | 1 | `process-checklist.sh` — core state machine |
| 2 | 1 | `pre-commit-gate.sh` — PreToolUse commit gate |
| 3 | 1 | `track-tool-usage.sh` — PostToolUse MCP tracking |
| 4 | 1 | `init.sh` — state file generation + hook registration |
| 5 | 1 | Session hooks — tool usage reset and summary |
| 6 | 1 | CLAUDE.md template — checklist commands |
| 7 | 1 | Builder's Guide — checkpoint references |
| 8 | 1 | User Guide — enforcement documentation |
| 9 | 0-1 | Verification + fixes |

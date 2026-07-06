# BL-006: Pre-commit Build Loop Enforcement — Implementation Plan

> **Archived 2026-07-05 (BL-049):** Shipped via PR #15 (`feat/bl-006-precommit-buildloop-enforcement`, merged 2026-04-24). See `docs/superpowers/plans/archive/README.md` for the archive convention.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add commit-message-triggered pre-commit enforcement that blocks `feat(...)` commits without an active Build Loop.

**Architecture:** Two-layer design. `pre-commit-gate.sh` (PreToolUse hook) extracts the commit message from the bash command and filters derivative commits. It delegates the policy decision to a new `process-checklist.sh --check-commit-message "MSG"` subcommand that owns the feat-regex, the phase gate, and the Build Loop state check. The state-check logic is factored into a shared helper `require_build_loop_state_for_commit` used by both the new subcommand and the existing `check_commit_ready` (which keeps its file-heuristic trigger).

**Tech Stack:** Bash 4+, `jq`, `awk`, `grep`, `sed`. No new runtime dependencies.

**Spec reference:** `docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md`

**Branching:** This plan and its commits should be executed on a feature branch `feat/bl-006-precommit-buildloop-enforcement` off `main`. The final PR targets `main`. The plan document itself commits to `main` first (documentation lives on `main`; implementation lives on the branch).

**Execution preamble (run once before Task 1):**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
git checkout main
git pull --ff-only origin main
git checkout -b feat/bl-006-precommit-buildloop-enforcement
```

**Process-checklist start-feature (Build Loop discipline — this plan eats its own dog food):**

```bash
scripts/process-checklist.sh --start-feature "bl-006-precommit-buildloop-enforcement"
```

This records the Build Loop for BL-006's own implementation. The pre-commit gate (existing file-heuristic path) will enforce the loop on our own `feat(...)` commits; the new enforcement path doesn't self-trigger until after Task 3 lands.

---

## File Structure

**Modified files:**
- `scripts/process-checklist.sh` — refactor `check_commit_ready` to call a new shared helper; add `--check-commit-message` action parsing; add new subcommand body. Expected delta: +~50 lines, -~15 lines.
- `scripts/pre-commit-gate.sh` — insert new commit-message extraction + filter + delegate block between the existing `--amend` warn and `--force` push blocks. Expected delta: +~75 lines.
- `tests/edge-cases-scripts.sh` — append new test section with E33–E39 (7 integration tests for the hook). Expected delta: +~200 lines.
- `docs/builders-guide.md` — add one paragraph inside the existing "MVP Cutline Work Requires the Build Loop" subsection.
- `templates/generated/claude-md.tmpl` — add one subordinate bullet under the existing MVP Cutline bullet.

**Created files:**
- `tests/test-check-commit-message.sh` — 17 unit tests (U1–U17) for the new subcommand.

**Responsibilities (enforcing the Section 4 architecture boundary):**
- `scripts/pre-commit-gate.sh` knows shell shapes (bash command parsing, `MERGE_HEAD` detection, message extraction from `-m`/heredoc/`-F`, JSON deny-encoding). It does NOT know policy.
- `scripts/process-checklist.sh --check-commit-message` knows policy (feat regex, phase gate, state machine). It does NOT parse bash commands.
- `require_build_loop_state_for_commit` (new helper) is the single source of truth for "is the Build Loop state sufficient to permit a commit?" — called by both `check_commit_ready` and `check_commit_message`.

---

## Task 1: Factor out the shared Build Loop state helper

**Goal:** Extract the 16 lines of state-check logic currently inside `check_commit_ready` into a reusable helper function. Also upgrade its error messages to match the spec's Case A/B format, which the existing file-heuristic path will inherit (intentional improvement).

**Files:**
- Modify: `scripts/process-checklist.sh:812-827` (existing state check) → replace with call to helper; add helper definition near top (grouped with `step_is_completed` around line 119)

**Rationale for doing this first:** Task 2 (the new subcommand) needs the helper. Factoring in a dedicated task keeps the diff reviewable — Task 1 is a behavior-preserving refactor with intentional error-message upgrade; Task 2 is purely additive.

- [ ] **Step 1.1: Open the file and locate the insertion point for the helper**

The helper will go immediately after the existing `step_is_completed` function body (find its closing `}` by scanning from line 119). Find the exact insertion point:

```bash
grep -n "^step_is_completed\b\|^get_steps_for_process\b" scripts/process-checklist.sh | head -4
```

Expected: two or three line numbers. Insert the helper AFTER the closing brace of `step_is_completed`.

- [ ] **Step 1.2: Add the new helper function `require_build_loop_state_for_commit`**

Insert this function definition after `step_is_completed`'s closing brace:

```bash
# --- Helper: require Build Loop state sufficient for a commit ---
# Used by both the file-heuristic path (--check-commit-ready) and the
# commit-message-triggered path (--check-commit-message). Prints the spec's
# Case A / Case B remediation to stderr on failure. Returns 0 if state OK,
# 1 otherwise. Reads $PROCESS_STATE and the BUILD_LOOP_STEPS array.
require_build_loop_state_for_commit() {
  local feature
  feature=$(jq -r '.build_loop.feature // "null"' "$PROCESS_STATE")
  if [ "$feature" = "null" ]; then
    print_fail "pre-commit gate: 'feat(...)' commit blocked — no Build Loop active."
    echo "MVP Cutline work and all features require a Build Loop per" >&2
    echo "docs/builders-guide.md \"MVP Cutline Work Requires the Build Loop\"." >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  1. scripts/process-checklist.sh --start-feature \"NAME\"" >&2
    echo "  2. Write failing tests, implement, verify, update docs" >&2
    echo "  3. Complete each step: scripts/process-checklist.sh --complete-step build_loop:STEP" >&2
    echo "  4. Re-run your commit" >&2
    echo "" >&2
    echo "If this commit is NOT a feature (tooling, CI, scaffolding, docs)," >&2
    echo "change the conventional-commit type: feat: -> chore:/build:/ci:/docs:." >&2
    return 1
  fi

  # Check first 5 build_loop steps: tests_written, tests_verified_failing,
  # implemented, security_audit, documentation_updated (feature_recorded is
  # step 6 and not required at commit time).
  local required_build_steps=("${BUILD_LOOP_STEPS[@]:0:5}")
  for step in "${required_build_steps[@]}"; do
    if ! step_is_completed "build_loop" "$step"; then
      print_fail "pre-commit gate: 'feat($feature)' commit blocked — Build Loop incomplete."
      echo "Missing step: $step" >&2
      echo "" >&2
      echo "Run: scripts/process-checklist.sh --complete-step build_loop:$step" >&2
      echo "Then: scripts/process-checklist.sh --status  (to verify)" >&2
      echo "Then re-run your commit." >&2
      return 1
    fi
  done

  return 0
}
```

- [ ] **Step 1.3: Replace the inline check in `check_commit_ready` with a call to the helper**

Locate lines 812–827 of the current `check_commit_ready` function. They look like:

```bash
    # Must have a feature started
    local feature
    feature=$(jq -r '.build_loop.feature // "null"' "$PROCESS_STATE")
    if [ "$feature" = "null" ]; then
      print_fail "No feature started."
      echo "Run: scripts/process-checklist.sh --start-feature 'name'" >&2
      exit 1
    fi

    # Check build_loop steps through documentation_updated (first 5)
    local required_build_steps=("${BUILD_LOOP_STEPS[@]:0:5}")
    for step in "${required_build_steps[@]}"; do
      if ! step_is_completed "build_loop" "$step"; then
        print_fail "Build loop step '$step' not completed for feature '$feature'."
        echo "Run: scripts/process-checklist.sh --complete-step build_loop:$step" >&2
        exit 1
      fi
    done
```

Replace all of that with:

```bash
    require_build_loop_state_for_commit || exit 1
```

- [ ] **Step 1.4: Run bash syntax check to catch typos**

```bash
bash -n scripts/process-checklist.sh
```

Expected: no output, exit 0.

- [ ] **Step 1.5: Manual smoke test — drive the refactored `check_commit_ready` through both error paths**

Create a disposable scratch dir and simulate the two failure modes:

```bash
TESTDIR=$(mktemp -d) && cd "$TESTDIR"
mkdir -p .claude
cat > .claude/phase-state.json <<JSON
{"current_phase": 2, "project": "smoke"}
JSON
cat > .claude/process-state.json <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null}
}
JSON
git init -q
touch foo.py
git add foo.py
"/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/process-checklist.sh" --check-commit-ready
echo "EXIT=$?"
```

Expected: exit 1; stderr contains `pre-commit gate: 'feat(...)' commit blocked — no Build Loop active.` and the multi-line remediation.

Now seed a feature but leave steps empty:

```bash
jq '.build_loop.feature = "smoketest"' .claude/process-state.json > /tmp/ps.json && mv /tmp/ps.json .claude/process-state.json
"/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/process-checklist.sh" --check-commit-ready
echo "EXIT=$?"
```

Expected: exit 1; stderr contains `pre-commit gate: 'feat(smoketest)' commit blocked — Build Loop incomplete.` and `Missing step: tests_written`.

Clean up:

```bash
cd - && rm -rf "$TESTDIR"
```

- [ ] **Step 1.6: Commit**

```bash
git add scripts/process-checklist.sh
git commit -m "$(cat <<'EOF'
refactor(process-checklist): extract require_build_loop_state_for_commit helper (BL-006)

Factor the 16 lines of feature-started + steps-complete logic in
check_commit_ready into a reusable helper. Upgrade error messages to
match the spec's Case A/B remediation format (multi-line, references
Builder's Guide, mentions Conventional Commits escape route).

No behavior change to which commits are allowed — only the stderr text
on denial improves. Prepares the helper for reuse by the new
--check-commit-message subcommand in Task 2.

Refs spec: docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md
EOF
)"
```

---

## Task 2: Add the `--check-commit-message` subcommand

**Goal:** Implement the new policy entry point. Write unit tests first, watch them fail, implement the subcommand, watch them pass.

**Files:**
- Create: `tests/test-check-commit-message.sh`
- Modify: `scripts/process-checklist.sh` — add action parsing for `--check-commit-message`, help text update, and the new action handler function

- [ ] **Step 2.1: Create the unit test file with the failing test harness**

Create `tests/test-check-commit-message.sh`:

```bash
#!/usr/bin/env bash
# tests/test-check-commit-message.sh — unit tests for
# `scripts/process-checklist.sh --check-commit-message "MSG"` (BL-006).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# --- Helpers: seed a tempdir .claude/ state ---

seed_phase() {
  # $1 = phase number
  mkdir -p "$TMPDIR_T/.claude"
  cat > "$TMPDIR_T/.claude/phase-state.json" <<JSON
{"current_phase": $1, "project": "unit-test"}
JSON
}

seed_process_state() {
  # $1 = feature value (e.g., null or "myfeat")
  # $2 = space-separated list of completed steps (may be empty)
  local feature="$1"
  local completed="$2"
  local completed_json="[]"
  if [ -n "$completed" ]; then
    completed_json=$(printf '%s\n' $completed | jq -R . | jq -sc .)
  fi
  local feature_json
  if [ "$feature" = "null" ]; then
    feature_json="null"
  else
    feature_json="\"$feature\""
  fi
  cat > "$TMPDIR_T/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {
    "feature": $feature_json,
    "step": 0,
    "steps_completed": $completed_json,
    "started_at": null
  },
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
}

run_check() {
  # $1 = MSG to pass. Echoes "EXIT STDERR" (one line joined).
  local msg="$1"
  ( cd "$TMPDIR_T" && "$SCRIPT" --check-commit-message "$msg" ) 2>"$TMPDIR_T/err" >/dev/null
  local rc=$?
  local err=""
  if [ -s "$TMPDIR_T/err" ]; then
    err=$(tr '\n' ' ' < "$TMPDIR_T/err")
  fi
  echo "$rc|$err"
}

setup() {
  TMPDIR_T=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_T"
}

# --- Tests ---

u1_phase_0_feat() {
  setup; seed_phase 0; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U1" "expected exit 0 in phase 0, got: $out"; teardown; return; }
  pass "U1: Phase 0 — feat: exits 0 (phase gate)"
  teardown
}

u2_phase_1_feat() {
  setup; seed_phase 1; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U2" "expected exit 0 in phase 1, got: $out"; teardown; return; }
  pass "U2: Phase 1 — feat: exits 0 (phase gate)"
  teardown
}

u3_phase_2_no_feature_feat() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U3" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"start-feature"* ]] || { fail_ "U3" "stderr missing --start-feature guidance: $out"; teardown; return; }
  pass "U3: Phase 2, no feature — feat: exit 1 + start-feature remediation"
  teardown
}

u4_non_feat_fix() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "fix(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U4" "expected exit 0 for fix:, got: $out"; teardown; return; }
  pass "U4: fix: — exit 0 (non-feat)"
  teardown
}

u5_non_feat_chore() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "chore: bump")
  [ "${out%%|*}" = "0" ] || { fail_ "U5" "expected exit 0 for chore:, got: $out"; teardown; return; }
  pass "U5: chore: — exit 0"
  teardown
}

u6_non_feat_docs() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "docs: typo")
  [ "${out%%|*}" = "0" ] || { fail_ "U6" "expected exit 0 for docs:, got: $out"; teardown; return; }
  pass "U6: docs: — exit 0"
  teardown
}

u7_feat_no_scope() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat: foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U7" "expected exit 1 for 'feat: ', got: $out"; teardown; return; }
  pass "U7: feat: (no scope) — exit 1"
  teardown
}

u8_feat_bang_no_scope() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat!: breaking")
  [ "${out%%|*}" = "1" ] || { fail_ "U8" "expected exit 1 for 'feat!:', got: $out"; teardown; return; }
  pass "U8: feat!: — exit 1"
  teardown
}

u9_feat_scope_bang() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat(x)!: breaking")
  [ "${out%%|*}" = "1" ] || { fail_ "U9" "expected exit 1 for 'feat(x)!:', got: $out"; teardown; return; }
  pass "U9: feat(x)!: — exit 1"
  teardown
}

u10_feature_word() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feature: foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U10" "expected exit 0 for 'feature:', got: $out"; teardown; return; }
  pass "U10: feature: (wrong word) — exit 0"
  teardown
}

u11_featbar_prefix() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "featbar: foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U11" "expected exit 0 for 'featbar:', got: $out"; teardown; return; }
  pass "U11: featbar: (not feat) — exit 0"
  teardown
}

u12_feature_started_zero_steps() {
  setup; seed_phase 2; seed_process_state "myfeat" ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U12" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"tests_written"* ]] || { fail_ "U12" "stderr missing 'tests_written' step name: $out"; teardown; return; }
  pass "U12: feature started, 0 steps — exit 1 + names tests_written"
  teardown
}

u13_feature_started_partial() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit"
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U13" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"documentation_updated"* ]] || { fail_ "U13" "stderr missing 'documentation_updated' step name: $out"; teardown; return; }
  pass "U13: steps 0-3 done — exit 1 + names step 4 (documentation_updated)"
  teardown
}

u14_feature_started_all_done() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit documentation_updated"
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U14" "expected exit 0, got: $out"; teardown; return; }
  pass "U14: feat with all 5 steps complete — exit 0"
  teardown
}

u15_non_feat_all_done() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit documentation_updated"
  local out; out=$(run_check "fix(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U15" "expected exit 0 for fix with all steps done, got: $out"; teardown; return; }
  pass "U15: fix: with all steps done — exit 0"
  teardown
}

u16_empty_msg() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "")
  [ "${out%%|*}" = "0" ] || { fail_ "U16" "expected exit 0 for empty MSG, got: $out"; teardown; return; }
  pass "U16: empty message — exit 0"
  teardown
}

u17_revert_quotes_feat() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check 'Revert "feat(x): foo"')
  [ "${out%%|*}" = "0" ] || { fail_ "U17" "expected exit 0 for Revert-prefix, got: $out"; teardown; return; }
  pass "U17: Revert \"feat(x): ...\" — exit 0 (regex anchored to start)"
  teardown
}

# --- Run all ---
echo "== tests/test-check-commit-message.sh =="
u1_phase_0_feat
u2_phase_1_feat
u3_phase_2_no_feature_feat
u4_non_feat_fix
u5_non_feat_chore
u6_non_feat_docs
u7_feat_no_scope
u8_feat_bang_no_scope
u9_feat_scope_bang
u10_feature_word
u11_featbar_prefix
u12_feature_started_zero_steps
u13_feature_started_partial
u14_feature_started_all_done
u15_non_feat_all_done
u16_empty_msg
u17_revert_quotes_feat

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
```

Make it executable:

```bash
chmod +x tests/test-check-commit-message.sh
```

- [ ] **Step 2.2: Run the test file to confirm it fails (subcommand does not yet exist)**

```bash
bash tests/test-check-commit-message.sh
```

Expected: test runner exits non-zero. Most cases fail with `--check-commit-message` being an unrecognized action. U1/U2/U4–U6/U10/U11/U15/U16/U17 might actually PASS because they expect exit 0 and an unknown action might cause the script to error out in a way that also produces exit != 0 — inspect the output. If the `Unknown action` path exits 1, the "exit 0" cases will fail too; that's fine, means nothing short-circuits in a weird way.

- [ ] **Step 2.3: Add argument parsing for `--check-commit-message` in `process-checklist.sh`**

Locate the argument parser (currently around line 41–49). Look for the block that sets `ACTION` based on flags:

```bash
grep -n "ACTION=" scripts/process-checklist.sh | head -20
```

Find the line setting `ACTION="check-commit-ready"` (around line 49). Add a new line immediately after it:

```bash
    --check-commit-message) ACTION="check-commit-message"; COMMIT_MSG="$2"; shift 2 ;;
```

Also declare the variable near the other argument-value declarations (at top of main dispatch or alongside `ARG_VALUE=""`):

```bash
COMMIT_MSG=""
```

Find the right spot:

```bash
grep -n '^ARG_VALUE=\|^FEATURE_NAME=' scripts/process-checklist.sh | head
```

Add `COMMIT_MSG=""` on the line after the last of those.

- [ ] **Step 2.4: Add help-text entry for `--check-commit-message`**

Find the `--help` output block (around lines 50–70 of `process-checklist.sh`). Look for the line:

```bash
      echo "  --check-commit-ready        Check if commit is allowed (used by PreToolUse hook)"
```

Add immediately after it:

```bash
      echo "  --check-commit-message MSG  Check commit message prefix (feat:) against Build Loop state (BL-006)"
```

- [ ] **Step 2.5: Add the dispatch case for `check-commit-message`**

Find the `case` statement near the end of the file (around lines 985–996) where actions are dispatched. Look for the `check-commit-ready) check_commit_ready ;;` line. Add immediately after it:

```bash
    check-commit-message) check_commit_message "$COMMIT_MSG" ;;
```

- [ ] **Step 2.6: Implement `check_commit_message` function body**

Add this function definition near the bottom of the file, just before the main dispatch `case` statement (insert before the line `case "$ACTION" in`). The function body:

```bash
check_commit_message() {
  local msg="$1"

  ensure_state_file

  # Empty message: nothing to check.
  if [ -z "$msg" ]; then
    exit 0
  fi

  # Take only the first line (subject).
  local subject
  subject=$(printf '%s\n' "$msg" | head -n 1)

  # Read current phase.
  local current_phase=0
  if [ -f "$PHASE_STATE" ]; then
    current_phase=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null || echo "0")
  fi

  # Phase gate: enforcement starts at Phase 2.
  if [ "$current_phase" -lt 2 ]; then
    exit 0
  fi

  # Feat-prefix regex, anchored, case-sensitive per Conventional Commits.
  # Matches: feat:, feat(x):, feat!:, feat(x)!: — each followed by whitespace.
  if ! [[ "$subject" =~ ^feat(\([^\)]*\))?!?:[[:space:]] ]]; then
    exit 0
  fi

  # Feat-prefixed: require Build Loop state sufficient for a commit.
  require_build_loop_state_for_commit || exit 1

  exit 0
}
```

- [ ] **Step 2.7: Run bash syntax check**

```bash
bash -n scripts/process-checklist.sh
```

Expected: no output, exit 0.

- [ ] **Step 2.8: Run the unit test file and confirm all 17 pass**

```bash
bash tests/test-check-commit-message.sh
```

Expected output ends with: `Total: 17 | Passed: 17 | Failed: 0`.

If any fail, inspect the failing case's stderr (the test output shows it). Most-likely failure mode: regex mis-parsing. The double-bracket regex in bash is sensitive to quoting; if U7 or U8 fails, check that the regex is not wrapped in quotes (bash-specific rule — `[[ $x =~ ^foo ]]` works; `[[ $x =~ "^foo" ]]` matches literal).

- [ ] **Step 2.9: Commit**

```bash
git add scripts/process-checklist.sh tests/test-check-commit-message.sh
git commit -m "$(cat <<'EOF'
feat(process-checklist): add --check-commit-message subcommand (BL-006)

New subcommand enforces Build Loop state when a commit message subject
matches feat|feat(x)|feat!|feat(x)! (Conventional Commits feature
prefix). Delegates the state check to the shared helper landed in the
previous commit. Phase gate at Phase 2 preserves existing behavior.

17 unit tests in tests/test-check-commit-message.sh covering all
locked parameters from the spec: phase gate, feat-prefix regex shapes,
false positives (feature:, featbar:, Revert), feature-started states,
step-completion granularity, and empty-message handling.

Refs spec: docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md
EOF
)"
```

---

## Task 3: Wire the subcommand into `pre-commit-gate.sh` with integration tests

**Goal:** Extract the commit message from the incoming bash command at the PreToolUse layer, filter derivative commits, and delegate to `--check-commit-message`. Write the 7 integration tests first, verify they fail, implement, verify they pass.

**Files:**
- Modify: `scripts/pre-commit-gate.sh` — insert new block between existing `--amend` warn (line 80) and `--force` push block (line 83)
- Modify: `tests/edge-cases-scripts.sh` — append new section with E33–E39

- [ ] **Step 3.1: Append integration tests E33–E39 to `tests/edge-cases-scripts.sh`**

First locate the end of the file and the `run_test` / stdin-piping pattern used by existing E-tests:

```bash
tail -60 tests/edge-cases-scripts.sh
```

Look for the existing pattern (it uses `echo '{"command": "..."}' | bash scripts/pre-commit-gate.sh` or similar). Note the exact pattern and adopt it for the new tests.

Append the following section at the end of `tests/edge-cases-scripts.sh` (before the final summary `echo` if one exists — check with `tail`). Replace the hypothetical `invoke_hook` helper below with whatever pattern the file already uses; the tests themselves are the content that matters:

```bash

section "BL-006: Pre-commit Build Loop enforcement (commit-message-triggered) — E33-E39"

# Helper: seed a project dir with given phase and build_loop state
bl006_seed() {
  local dir="$1" phase="$2" feature="$3"
  mkdir -p "$dir/.claude" "$dir/.git"
  cat > "$dir/.claude/phase-state.json" <<JSON
{"current_phase": $phase, "project": "e33-e39"}
JSON
  local feature_json="null"
  [ "$feature" != "null" ] && feature_json="\"$feature\""
  cat > "$dir/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {"feature": $feature_json, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
}

# Helper: invoke the PreToolUse hook with a stdin JSON command, return
# "EXIT|OUTPUT" where OUTPUT may contain a deny JSON.
bl006_invoke_hook() {
  local cmd="$1" project_dir="$2"
  local input
  input=$(jq -n --arg c "$cmd" '{command: $c}')
  local out rc
  out=$( cd "$project_dir" && echo "$input" | bash "$REPO_DIR/scripts/pre-commit-gate.sh" 2>&1 )
  rc=$?
  echo "$rc|$out"
}

# E33: inline feat -m, no feature started -> deny
e33() {
  local d="$TEST_DIR/e33"
  bl006_seed "$d" 2 null
  local r; r=$(bl006_invoke_hook 'git commit -m "feat(x): thing"' "$d")
  if [[ "${r#*|}" == *'"permissionDecision":"deny"'* ]] && [[ "${r#*|}" == *"start-feature"* ]]; then
    pass "E33: inline feat -m blocks with --start-feature guidance"
  else
    fail "E33: expected deny JSON with --start-feature, got: $r"
  fi
}

# E34: heredoc feat, no feature started -> deny
e34() {
  local d="$TEST_DIR/e34"
  bl006_seed "$d" 2 null
  # Build a command that matches the literal heredoc shape Claude's prompt teaches
  local cmd='git commit -m "$(cat <<'"'"'EOF'"'"'
feat(x): thing from heredoc

body line.
EOF
)"'
  local r; r=$(bl006_invoke_hook "$cmd" "$d")
  if [[ "${r#*|}" == *'"permissionDecision":"deny"'* ]]; then
    pass "E34: heredoc -m blocks (heredoc parser works)"
  else
    fail "E34: expected deny JSON, got: $r"
  fi
}

# E35: -F file, no feature started -> deny
e35() {
  local d="$TEST_DIR/e35"
  bl006_seed "$d" 2 null
  local msgfile="$d/msg.txt"
  echo "feat(x): from file" > "$msgfile"
  local r; r=$(bl006_invoke_hook "git commit -F $msgfile" "$d")
  if [[ "${r#*|}" == *'"permissionDecision":"deny"'* ]]; then
    pass "E35: -F file blocks"
  else
    fail "E35: expected deny JSON, got: $r"
  fi
}

# E36: --amend with feat, no feature started -> amend path wins (allow + warn)
e36() {
  local d="$TEST_DIR/e36"
  bl006_seed "$d" 2 null
  local r; r=$(bl006_invoke_hook 'git commit -m "feat(x): thing" --amend' "$d")
  # amend path produces permissionDecision: allow with WARNING text — not deny
  if [[ "${r#*|}" == *'"permissionDecision":"allow"'* ]] && [[ "${r#*|}" == *"WARNING"* ]]; then
    pass "E36: --amend bypasses new gate (existing amend warn wins)"
  else
    fail "E36: expected amend warn (allow), got: $r"
  fi
}

# E37: merge in progress (MERGE_HEAD exists) -> allow
e37() {
  local d="$TEST_DIR/e37"
  bl006_seed "$d" 2 null
  touch "$d/.git/MERGE_HEAD"
  local r; r=$(bl006_invoke_hook 'git commit -m "feat(x): from merge"' "$d")
  # Should NOT deny via BL-006 path. The existing --check-commit-ready may still
  # run; it will not fire if no staged source files exist.
  if [[ "${r#*|}" != *'"permissionDecision":"deny"'* ]]; then
    pass "E37: MERGE_HEAD present — BL-006 path skips"
  else
    fail "E37: expected no deny, got: $r"
  fi
}

# E38: git commit with no -m (editor case) -> allow (hook falls through)
e38() {
  local d="$TEST_DIR/e38"
  bl006_seed "$d" 2 null
  local r; r=$(bl006_invoke_hook 'git commit' "$d")
  if [[ "${r#*|}" != *'"permissionDecision":"deny"'* ]]; then
    pass "E38: bare git commit (editor case) — BL-006 path falls through"
  else
    fail "E38: expected no deny, got: $r"
  fi
}

# E39: feat -m at Phase 0 -> allow (phase gate)
e39() {
  local d="$TEST_DIR/e39"
  bl006_seed "$d" 0 null
  local r; r=$(bl006_invoke_hook 'git commit -m "feat(x): foo"' "$d")
  if [[ "${r#*|}" != *'"permissionDecision":"deny"'* ]]; then
    pass "E39: Phase 0 — BL-006 path skipped by phase gate"
  else
    fail "E39: expected no deny at Phase 0, got: $r"
  fi
}

e33; e34; e35; e36; e37; e38; e39
```

**Important:** if the existing file uses a different hook-invocation helper or results-collection pattern, adapt the two helpers (`bl006_seed`, `bl006_invoke_hook`) and assertion style to match. The test bodies themselves (e33–e39) should stay semantically identical.

- [ ] **Step 3.2: Run the integration tests and confirm they fail (hook doesn't yet parse feat messages)**

```bash
bash tests/edge-cases-scripts.sh
```

Expected: E33, E34, E35 fail (no deny produced); E36, E37, E38, E39 pass (existing hook allows them). Note the failures — you should see lines like `[FAIL] E33: expected deny JSON with --start-feature, got: 0|`.

If E36/E37/E38/E39 also fail, there is a test-harness issue — fix that first before moving on.

- [ ] **Step 3.3: Add the new block to `pre-commit-gate.sh`**

Open `scripts/pre-commit-gate.sh`. Locate the existing `--amend` warn block (lines 74–80 in the current file — the block that prints `WARNING: git commit --amend rewrites the previous commit`).

After that block's `exit 0`, and before the `# Block git push --force` comment (current line 82), insert:

```bash
# --- BL-006: commit-message-triggered Build Loop enforcement ---
# Scope: only fires on `git commit` authoring events (not merges, reverts,
# cherry-picks, squash-merges, or editor-case commits). Extracts the message
# from -m "..." / heredoc / -F file and delegates the policy decision to
# process-checklist.sh --check-commit-message.

bl006_check() {
  # Only apply to `git commit` subcommands.
  echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || return 0

  # Derivative-commit filters: pass through.
  # --amend is already handled above (warns, exits). Belt-and-braces.
  echo "$COMMAND" | grep -qE '\-\-amend\b' && return 0
  # Merge in progress.
  [ -f .git/MERGE_HEAD ] && return 0
  # Other derivative commands that might embed feat: in their message.
  echo "$COMMAND" | grep -qE '\bgit\b.*\b(merge|revert|cherry-pick)\b' && return 0
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bmerge\b.*\-\-squash' && return 0

  # Extract the message subject.
  local msg=""

  # 1. Heredoc: look for -m "$(cat <<EOF or -m "$(cat <<'EOF'
  if echo "$COMMAND" | grep -qE "<<'?EOF'?" ; then
    # awk: after the <<EOF or <<'EOF' marker, the first non-empty content line
    # before a standalone EOF is the subject.
    msg=$(printf '%s\n' "$COMMAND" | awk "
      /<<['\"]?EOF['\"]?/{flag=1; next}
      /^EOF\$/{flag=0}
      flag && !printed && NF>0 { print; printed=1; exit }
    ")
  fi

  # 2. Inline -m "..." (double or single quotes). Only if heredoc didn't match.
  if [ -z "$msg" ]; then
    # Try double-quoted first, then single-quoted. Capture up to the closing
    # quote. This is best-effort; exotic escaping falls through.
    msg=$(printf '%s' "$COMMAND" | sed -nE 's/.*-m "([^"]*)".*/\1/p' | head -n 1)
    if [ -z "$msg" ]; then
      msg=$(printf '%s' "$COMMAND" | sed -nE "s/.*-m '([^']*)'.*/\1/p" | head -n 1)
    fi
    # Split on literal \n or real newlines; take first line.
    msg=$(printf '%s\n' "$msg" | head -n 1)
  fi

  # 3. -F <file>. Only if no -m at all was seen.
  if [ -z "$msg" ] && echo "$COMMAND" | grep -qE '\-F[[:space:]]+[^ ]+' ; then
    local f
    f=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^ ]+).*/\1/p' | head -n 1)
    if [ -n "$f" ] && [ -r "$f" ]; then
      msg=$(head -n 1 "$f")
    fi
  fi

  # Empty: fall through (editor case or parse miss).
  [ -z "$msg" ] && return 0

  # Delegate to the subcommand. Capture stderr for the deny-reason payload.
  local policy_err policy_exit
  policy_err=$("$SCRIPT_DIR/process-checklist.sh" --check-commit-message "$msg" 2>&1 >/dev/null) || policy_exit=$?
  policy_exit=${policy_exit:-0}

  if [ "$policy_exit" -ne 0 ]; then
    local reason
    reason=$(echo "$policy_err" | tr '\n' ' ' | sed 's/"/\\"/g')
    cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$reason"}}
HOOKEOF
    exit 0
  fi

  return 0
}

bl006_check
# --- end BL-006 block ---
```

- [ ] **Step 3.4: Run bash syntax check on pre-commit-gate.sh**

```bash
bash -n scripts/pre-commit-gate.sh
```

Expected: no output, exit 0.

- [ ] **Step 3.5: Run the integration tests and confirm all E33–E39 pass**

```bash
bash tests/edge-cases-scripts.sh
```

Expected: all 7 new tests (E33–E39) pass, and the previous 32 (E1–E32) continue to pass.

If E34 (heredoc) fails, most-likely cause is the awk one-liner — the embedded `\$` and quoting in bash is fragile. Alternative: use `python3 -c` for extraction if awk proves too brittle. Log the actual failure output and adjust the extractor.

If E35 (-F file) fails, likely a path-expansion issue in sed — ensure the file path doesn't contain spaces in the test.

- [ ] **Step 3.6: Smoke-test via a real Claude hook simulation**

Simulate the exact JSON Claude Code passes to the PreToolUse hook:

```bash
TMPSMOKE=$(mktemp -d) && cd "$TMPSMOKE"
git init -q
mkdir -p .claude
cat > .claude/phase-state.json <<'JSON'
{"current_phase": 2, "project": "smoke"}
JSON
cat > .claude/process-state.json <<'JSON'
{
  "phase2_init": {"verified": true},
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
git remote add origin https://example.com/fake.git   # satisfies the no-remote early guard
echo '{"command": "git commit -m \"feat(x): thing\""}' | \
  bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/scripts/pre-commit-gate.sh"
```

Expected stdout: a single JSON line with `"permissionDecision":"deny"` and a reason mentioning `start-feature`. Clean up: `cd - && rm -rf "$TMPSMOKE"`.

- [ ] **Step 3.7: Commit**

```bash
git add scripts/pre-commit-gate.sh tests/edge-cases-scripts.sh
git commit -m "$(cat <<'EOF'
feat(pre-commit-gate): wire --check-commit-message into PreToolUse hook (BL-006)

Adds the bl006_check block that extracts the commit message from
-m / heredoc / -F shapes, filters derivative commits (amend, merge,
revert, cherry-pick, gh pr merge --squash, MERGE_HEAD), and delegates
to process-checklist.sh --check-commit-message.

Editor-case (no -m) and exotic shell shapes fall through to the
existing file-heuristic path.

7 integration tests (E33-E39) in tests/edge-cases-scripts.sh covering
inline -m, heredoc, -F file, --amend, MERGE_HEAD, bare git commit,
and Phase 0 gate.

Refs spec: docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md
EOF
)"
```

---

## Task 4: Documentation & template updates

**Goal:** Land the three small doc/template changes called out in Section 9 of the spec, plus the upgrade-project.sh changelog line.

**Files:**
- Modify: `docs/builders-guide.md`
- Modify: `templates/generated/claude-md.tmpl`
- Modify: `scripts/upgrade-project.sh` (changelog comment only, no behavior change)

- [ ] **Step 4.1: Locate the "MVP Cutline Work Requires the Build Loop" subsection in Builder's Guide**

```bash
grep -n "MVP Cutline Work Requires the Build Loop" docs/builders-guide.md
```

Expected: one line number (shipped in PR #14). Read ~20 lines below it to find where the subsection ends (before the next `###` heading).

- [ ] **Step 4.2: Append the enforcement paragraph at the end of that subsection**

Before the next `###` heading (or blank line separator), add:

```markdown

**Mechanical enforcement.** This rule is enforced by the pre-commit gate: any `git commit` with a message subject starting with `feat`, `feat(scope)`, `feat!`, or `feat(scope)!` is blocked unless a Build Loop is active and its first five steps (`tests_written`, `tests_verified_failing`, `implemented`, `security_audit`, `documentation_updated`) are complete. Non-feature scaffolding — tooling, CI, build configs — should use the correct Conventional Commits type (`chore:`, `build:`, `ci:`, `docs:`), which the gate does not enforce against. See `docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md` for the full design.
```

- [ ] **Step 4.3: Locate the MVP Cutline bullet in `claude-md.tmpl`**

```bash
grep -n "MVP Cutline" templates/generated/claude-md.tmpl
```

Expected: one line number (shipped in PR #14). That bullet introduces the rule; we add a subordinate bullet under it.

- [ ] **Step 4.4: Add the subordinate bullet**

After the existing MVP Cutline bullet line, insert (preserving the indentation style — typically two spaces for sub-bullets; match whatever the file uses):

```markdown
  - The pre-commit gate blocks `feat:` commits without an active Build Loop. Non-feature work should use `chore:`/`build:`/`ci:`/`docs:` instead.
```

- [ ] **Step 4.5: Add an upgrade-changelog line in `upgrade-project.sh`**

Find the upgrade-project.sh changelog or migration-note block (the file has comment blocks noting which PR or spec each migration step relates to):

```bash
grep -n "BL-007\|BL-008\|BL-009\|FRAMEWORK_VERSION\|changelog" scripts/upgrade-project.sh | head -10
```

At the natural insertion point (following the BL-009 note, or at the end of the script's header comment block, whichever pattern the file uses), add one line:

```bash
# BL-006 (2026-04-24): pre-commit gate now blocks feat: commits without an
# active Build Loop. No migration code needed — the updated
# scripts/process-checklist.sh and scripts/pre-commit-gate.sh are copied
# by this script's existing behavior, so running --upgrade picks it up.
```

No executable code changes in `upgrade-project.sh`.

- [ ] **Step 4.6: Commit**

```bash
git add docs/builders-guide.md templates/generated/claude-md.tmpl scripts/upgrade-project.sh
git commit -m "$(cat <<'EOF'
docs(bl-006): enforcement notes in Builder's Guide, claude-md template, upgrade changelog

- docs/builders-guide.md: append "Mechanical enforcement" paragraph
  to the "MVP Cutline Work Requires the Build Loop" subsection.
- templates/generated/claude-md.tmpl: subordinate bullet noting the
  pre-commit gate's feat: enforcement under the MVP Cutline bullet.
- scripts/upgrade-project.sh: one-line changelog note; no behavior
  change — existing upgrade flow picks up the new enforcement.

Refs spec: docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md
EOF
)"
```

---

## Task 5: Full verification & record the feature

**Goal:** Run every test suite that touches the changed files. Confirm no regression. Complete the Build Loop steps on our own feature.

- [ ] **Step 5.1: Run the new unit tests**

```bash
bash tests/test-check-commit-message.sh
```

Expected: `Total: 17 | Passed: 17 | Failed: 0`, exit 0.

- [ ] **Step 5.2: Run the full edge-cases suite (includes E33–E39)**

```bash
bash tests/edge-cases-scripts.sh
```

Expected: all tests pass (previous 32 plus new 7 = 39 total in that file; the file may have additional tests not counted here — read its summary line).

- [ ] **Step 5.3: Run the other test suites that touch process-checklist or pre-commit-gate**

```bash
bash tests/test-unrecord-feature.sh
bash tests/edge-cases-pre-init.sh
bash tests/known-bugs-test-suite.sh
```

Expected: each exits 0 with no new failures. If any failure references a file we didn't touch, it's pre-existing — surface it to the reviewer but do not block the PR.

- [ ] **Step 5.4: Dry-run `upgrade-project.sh --help` to confirm our comment didn't break the script**

```bash
bash scripts/upgrade-project.sh --help | head -5
```

Expected: normal help output; non-zero exit ok only if the script legitimately has no `--help` path (check with `grep -- '--help' scripts/upgrade-project.sh`).

- [ ] **Step 5.5: Confirm `process-checklist.sh --help` shows the new subcommand**

```bash
scripts/process-checklist.sh --help | grep -A 0 "check-commit-message"
```

Expected: one line matching `--check-commit-message MSG  Check commit message prefix (feat:) against Build Loop state (BL-006)`.

- [ ] **Step 5.6: Complete the Build Loop steps on our own feature**

```bash
scripts/process-checklist.sh --complete-step build_loop:tests_written
scripts/process-checklist.sh --complete-step build_loop:tests_verified_failing
scripts/process-checklist.sh --complete-step build_loop:implemented
scripts/process-checklist.sh --complete-step build_loop:security_audit
scripts/process-checklist.sh --complete-step build_loop:documentation_updated
```

Expected: each step records successfully. If any fails with a precondition error, inspect and fix before proceeding.

**Note on `security_audit`:** the existing step likely expects a security-audit artifact. If it blocks, produce a brief inline audit (grep for obvious shell-injection risks in the new bash: unquoted `$COMMAND` uses in the extractor, command-substitution safety) and file `docs/security-audits/bl-006-precommit.md` with the findings. The new extractor treats `$COMMAND` as data and never `eval`s it — that's the core safety property.

- [ ] **Step 5.7: Push the branch and open the PR**

```bash
git push -u origin feat/bl-006-precommit-buildloop-enforcement
gh pr create --title "BL-006: pre-commit Build Loop enforcement (commit-message-triggered)" --body "$(cat <<'EOF'
## Summary

- New `scripts/process-checklist.sh --check-commit-message "MSG"` subcommand owning the feat-regex, phase gate, and Build Loop state check.
- New extraction + filter block in `scripts/pre-commit-gate.sh` that handles `-m "..."`, heredoc `-m "$(cat <<EOF…EOF)"`, and `-F file`; skips amend, merge, revert, cherry-pick, squash-merge, `MERGE_HEAD`, and editor-case commits.
- Shared helper `require_build_loop_state_for_commit` factored out of existing `check_commit_ready`; both the file-heuristic and message-prefix paths share it.
- 17 unit tests (`tests/test-check-commit-message.sh`) + 7 integration tests (E33–E39 in `tests/edge-cases-scripts.sh`).
- Docs: Builder's Guide enforcement paragraph, `claude-md.tmpl` subordinate bullet, upgrade-project.sh changelog note.

Mechanically enforces the doctrinal rule BL-007 shipped in PR #14.

## Test plan

- [ ] `bash tests/test-check-commit-message.sh` — 17/17 pass
- [ ] `bash tests/edge-cases-scripts.sh` — E33–E39 pass alongside existing E1–E32
- [ ] `bash tests/test-unrecord-feature.sh` — no regression
- [ ] `bash tests/known-bugs-test-suite.sh` — no regression
- [ ] Smoke test: `git commit -m "feat(x): …"` in a Phase-2 project with no feature started → denied with Case A remediation.

Refs spec: `docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md`
Backlog: BL-006 → resolved; BL-010–BL-014 logged as optional follow-ups.
EOF
)"
```

- [ ] **Step 5.8: After PR merges, record the feature and update the backlog**

```bash
git checkout main
git pull --ff-only origin main
scripts/test-gate.sh --record-feature "bl-006-precommit-buildloop-enforcement"
scripts/process-checklist.sh --complete-step build_loop:feature_recorded
```

Then update `solo-orchestrator-backlog.md`:
- Mark BL-006 status as `Resolved (2026-04-XX, PR #N)` and append a **Resolution:** paragraph mirroring BL-007/BL-008/BL-009 entries.

Commit the backlog update:

```bash
git add solo-orchestrator-backlog.md
git commit -m "backlog: mark BL-006 resolved (PR #N merged 2026-04-XX)"
git push origin main
```

---

## Self-Review Checklist (completed at plan-writing time)

**Spec coverage — every spec section is mapped to a task:**
- Spec § 1 Problem: context only, no task.
- Spec § 2 Scope: Tasks 1–5 cover in-scope items; follow-ups logged to backlog already.
- Spec § 3 Locked parameters: each parameter baked into Task 2's regex, Task 3's filter list, and Task 1's shared helper.
- Spec § 4 Architecture: Task 1 (helper), Task 2 (subcommand), Task 3 (hook block) implement the three boxes of the Section 4 diagram.
- Spec § 5 New subcommand contract: Task 2.6 implements the contract exactly (phase gate → regex → helper).
- Spec § 6 Message extraction: Task 3.3 implements the three-shape extractor with derivative-commit filters.
- Spec § 7 Error messages: Task 1.2 emits Case A and Case B messages from the shared helper.
- Spec § 8 Testing plan: Task 2.1 (all 17 unit tests) + Task 3.1 (all 7 integration tests).
- Spec § 9 Template & docs: Task 4 covers all four items (builders-guide paragraph, claude-md subordinate bullet, --help line in Step 2.4, upgrade changelog in Step 4.5).
- Spec § 10 Follow-ups: already in backlog as BL-010–BL-014; no task needed.
- Spec § 11 Risks: mitigations are encoded in the test cases (U17, E34, E37) and in the narrow-parser policy (Task 3.3).
- Spec § 12 Success criteria: Task 5 verification steps map to each criterion.

**Placeholder scan:** no TBD/TODO/fill-in; every bash block is complete; every function body is fully spelled out.

**Type consistency:**
- `require_build_loop_state_for_commit` — spelled the same in Task 1.2 (definition), Task 1.3 (call), Task 2.6 (call).
- `check_commit_message` — spelled the same in Task 2.5 (dispatch) and Task 2.6 (body).
- `--check-commit-message` / `COMMIT_MSG` — consistent across Steps 2.3, 2.5, 2.6.
- `bl006_check` / `bl006_seed` / `bl006_invoke_hook` — consistent across Task 3 steps.
- `BUILD_LOOP_STEPS[@]:0:5` — same slice everywhere; first 5 steps = `tests_written`, `tests_verified_failing`, `implemented`, `security_audit`, `documentation_updated` (the 6th `feature_recorded` is not commit-gated).

**Fixable issues found during self-review:** none. Plan is ready to execute.

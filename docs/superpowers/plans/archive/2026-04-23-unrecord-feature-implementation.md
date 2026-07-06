# Unrecord-Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `scripts/test-gate.sh --unrecord-feature NAME` per spec `docs/superpowers/specs/2026-04-23-unrecord-feature-design.md`, add a "Recovering from mistakes" subsection to the CLAUDE.md template, and add a self-contained test file covering the state-transform logic.

**Architecture:** One new subcommand in an existing script. State-transform logic lives in a pure `_unrecord_feature_apply()` function (unit-testable). Interactive wrapper `unrecord_feature()` handles tty guard, preview, Y/N prompt, audit log. Source guard added to `test-gate.sh` so tests can source it without triggering dispatch.

**Tech Stack:** Bash 4+, jq, existing solo-orchestrator test conventions (bash assertion scripts).

---

## File Structure

```
scripts/
└── test-gate.sh                         # MODIFIED: add _apply + wrapper + parser case + dispatch case + help line + source guard

templates/
└── generated/
    └── claude-md.tmpl                   # MODIFIED: add "Recovering from mistakes" subsection

tests/
└── test-unrecord-feature.sh             # NEW: 7 cases against _unrecord_feature_apply
```

All changes are in existing files except the new test file. Behavior change is additive — existing subcommands (`--check-batch`, `--record-feature`, etc.) remain unchanged.

---

## Task 1: Make test-gate.sh source-safe

**Files:**
- Modify: `scripts/test-gate.sh` — wrap argument parsing, validation, and dispatch in a source guard so sourcing the file for tests doesn't trigger the "No action specified" exit.

**Why:** The test file in Task 2 needs to source `test-gate.sh` to call `_unrecord_feature_apply` directly. Without the source guard, sourcing with no arguments would hit the existing `if [ -z "$ACTION" ]; then ... exit 1` block and kill the test process. The `BASH_SOURCE` check makes the dispatch block only fire when the script is run directly, not when sourced.

- [ ] **Step 1: Read current structure of `scripts/test-gate.sh`**

Run: `grep -n '^while\|^if \[ -z "\$ACTION"\|^# --- Dispatch\|^case "\$ACTION"' scripts/test-gate.sh`
Expected output includes approximately:
```
23:while [ $# -gt 0 ]; do
47:if [ -z "$ACTION" ]; then
298:# --- Dispatch ---
299:case "$ACTION" in
```

Note the exact line numbers; they will vary slightly. Identify the region from the `while [ $# -gt 0 ]; do` loop start through the closing `esac` of the dispatch `case`.

- [ ] **Step 2: Modify test-gate.sh to wrap parsing + dispatch in source guard**

Wrap the entire region from line 23 (`while [ $# -gt 0 ]; do`) through the `esac` that closes the dispatch case. The wrapper:

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # --- Argument parsing, validation, dispatch ---
  # (existing code moves inside this block, indented one level)
  while [ $# -gt 0 ]; do
    case "$1" in
      # ... existing cases ...
    esac
  done

  if [ -z "$ACTION" ]; then
    echo "No action specified. Use --help for usage." >&2
    exit 1
  fi

  # --- Dispatch ---
  case "$ACTION" in
    # ... existing cases ...
  esac
fi
```

The indentation of the wrapped code changes (add 2 spaces); the logic is unchanged. Function definitions remain outside the guard and are always defined when the file is sourced.

- [ ] **Step 3: Verify existing subcommands still work when run directly**

Run: `bash scripts/test-gate.sh --help`
Expected: help text prints, exit 0. (If this fails, the source guard wrapping has a syntax error.)

Run: `bash scripts/test-gate.sh`
Expected: "No action specified. Use --help for usage." exit 1.

- [ ] **Step 4: Verify sourcing the file with no args does NOT exit**

Run: `bash -c 'source scripts/test-gate.sh; echo "sourced ok"; declare -f record_feature >/dev/null && echo "record_feature defined"'`
Expected output:
```
sourced ok
record_feature defined
```

- [ ] **Step 5: Commit**

```bash
git add scripts/test-gate.sh
git commit -m "refactor(test-gate): wrap argument parsing + dispatch in source guard

Enables tests to source test-gate.sh and call its functions directly
without triggering the 'No action specified' exit that would kill the
test process. Function definitions remain at top level; only the
argument parser, validation, and dispatch case are guarded by
BASH_SOURCE/\$0 equality.

Behavior when run directly is unchanged — verified via --help and
no-argument invocations."
```

---

## Task 2: Add state-transform function `_unrecord_feature_apply` (TDD)

**Files:**
- Create: `tests/test-unrecord-feature.sh` — self-contained bash test file with assertion helpers and 5 state-transform cases
- Modify: `scripts/test-gate.sh` — add `_unrecord_feature_apply()` function

**Why:** The pure state-transform is the testable core. Writing the 5 state-transform cases first gives a clear contract for the implementation; the tests validate the inverse semantics of `--record-feature` including counter flooring and `testing_required` re-evaluation.

- [ ] **Step 1: Create the test file with 5 failing state-transform tests**

Create `tests/test-unrecord-feature.sh`:

```bash
#!/usr/bin/env bash
# tests/test-unrecord-feature.sh — unit tests for _unrecord_feature_apply()
# Targets the pure state transform; interactive wrapper is manually verified.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Inline assertion helpers (zero-dependency; matches existing tests/*.sh pattern) ---

PASSED=0
FAILED=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "  ASSERT FAIL${msg:+ [$msg]}: expected '$expected', got '$actual'" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ASSERT FAIL${msg:+ [$msg]}: '$haystack' does not contain '$needle'" >&2
    return 1
  fi
}

run_case() {
  local name="$1"
  shift
  if ( set -e; "$@" ); then
    echo "✓ $name"
    PASSED=$((PASSED + 1))
  else
    echo "✗ $name FAILED"
    FAILED=$((FAILED + 1))
  fi
}

seed_progress() {
  # Args: path, array-json, fslt, interval, testing_required, fslhc
  local path="$1" arr="$2" fslt="$3" interval="$4" testing="$5" fslhc="$6"
  cat > "$path" <<JSONEOF
{
  "features_completed": $arr,
  "features_since_last_test": $fslt,
  "test_interval": $interval,
  "last_test_session": null,
  "testing_required": $testing,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 0,
  "features_since_last_health_check": $fslhc
}
JSONEOF
}

# --- Source the script under test ---
# Task 1's source guard prevents dispatch from running.
source "$REPO_ROOT/scripts/test-gate.sh"

# --- Test cases ---

case_1_happy_path() {
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN
  (
    cd "$work"
    mkdir -p .claude
    seed_progress .claude/build-progress.json '["foo"]' 1 2 false 1
    _unrecord_feature_apply "foo"
    assert_eq "[]" "$(jq -c '.features_completed' .claude/build-progress.json)" "array empty"
    assert_eq "0" "$(jq -r '.features_since_last_test' .claude/build-progress.json)" "fslt 0"
    assert_eq "0" "$(jq -r '.features_since_last_health_check' .claude/build-progress.json)" "fslhc 0"
    assert_eq "false" "$(jq -r '.testing_required' .claude/build-progress.json)" "testing_required false"
  )
}

case_2_duplicates_first_match() {
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN
  (
    cd "$work"
    mkdir -p .claude
    seed_progress .claude/build-progress.json '["foo","bar","foo"]' 3 2 true 3
    _unrecord_feature_apply "foo"
    assert_eq '["bar","foo"]' "$(jq -c '.features_completed' .claude/build-progress.json)" "first 'foo' removed, second preserved"
  )
}

case_3_counter_floor_at_zero() {
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN
  (
    cd "$work"
    mkdir -p .claude
    seed_progress .claude/build-progress.json '["foo"]' 0 2 false 0
    _unrecord_feature_apply "foo"
    assert_eq "0" "$(jq -r '.features_since_last_test' .claude/build-progress.json)" "fslt stays 0"
    assert_eq "0" "$(jq -r '.features_since_last_health_check' .claude/build-progress.json)" "fslhc stays 0"
  )
}

case_4_testing_required_flips_false() {
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN
  (
    cd "$work"
    mkdir -p .claude
    seed_progress .claude/build-progress.json '["foo","bar"]' 2 2 true 2
    _unrecord_feature_apply "foo"
    assert_eq "1" "$(jq -r '.features_since_last_test' .claude/build-progress.json)" "fslt 1"
    assert_eq "false" "$(jq -r '.testing_required' .claude/build-progress.json)" "testing_required now false"
  )
}

case_5_testing_required_stays_true() {
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN
  (
    cd "$work"
    mkdir -p .claude
    seed_progress .claude/build-progress.json '["foo","bar","baz"]' 3 2 true 3
    _unrecord_feature_apply "foo"
    assert_eq "2" "$(jq -r '.features_since_last_test' .claude/build-progress.json)" "fslt 2"
    assert_eq "true" "$(jq -r '.testing_required' .claude/build-progress.json)" "testing_required stays true"
  )
}

# --- Run all cases and report ---
echo "═══ test-unrecord-feature.sh ═══"
run_case "case 1: happy path"                     case_1_happy_path
run_case "case 2: duplicates → first match"       case_2_duplicates_first_match
run_case "case 3: counter floor at 0"             case_3_counter_floor_at_zero
run_case "case 4: testing_required flips false"   case_4_testing_required_flips_false
run_case "case 5: testing_required stays true"    case_5_testing_required_stays_true

echo ""
echo "═══════════════════════════════════════════"
echo "Tests: $PASSED passed, $FAILED failed"
echo "═══════════════════════════════════════════"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2: Run tests to verify all 5 fail**

Run: `bash tests/test-unrecord-feature.sh`
Expected: All 5 cases fail (`_unrecord_feature_apply: command not found` or similar). The aggregate summary shows `0 passed, 5 failed`, exit code 1.

- [ ] **Step 3: Implement `_unrecord_feature_apply()` in test-gate.sh**

Add the following function definition to `scripts/test-gate.sh`, placed **immediately after** the existing `record_feature()` function (for visual symmetry). Functions must be defined outside the source guard added in Task 1.

```bash
# _unrecord_feature_apply <name>
# Pure state transform; no tty check, no prompt, no audit log.
# Inverse of record_feature: removes first occurrence of $name from
# features_completed, decrements both counters floored at 0, re-evaluates
# testing_required. Errors if name is not present or build-progress.json
# is missing. Unit-testable via source.
_unrecord_feature_apply() {
  local name="${1:?_unrecord_feature_apply: name required}"

  if [ ! -f "$BUILD_PROGRESS" ]; then
    echo "_unrecord_feature_apply: $BUILD_PROGRESS does not exist" >&2
    return 1
  fi

  # Presence check — errors if name not in features_completed
  if ! jq --arg name "$name" -e '.features_completed | index($name) != null' "$BUILD_PROGRESS" >/dev/null; then
    echo "_unrecord_feature_apply: feature '$name' not found in features_completed" >&2
    return 1
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg name "$name" '
    (.features_completed
      | (. | index($name)) as $i
      | .[0:$i] + .[$i+1:]) as $new_arr |
    .features_completed = $new_arr |
    .features_since_last_test = ([.features_since_last_test - 1, 0] | max) |
    .features_since_last_health_check = ([(.features_since_last_health_check // 0) - 1, 0] | max) |
    .testing_required = (.features_since_last_test >= .test_interval)
  ' "$BUILD_PROGRESS" > "$tmp" && mv "$tmp" "$BUILD_PROGRESS"
}
```

- [ ] **Step 4: Run tests to verify all 5 pass**

Run: `bash tests/test-unrecord-feature.sh`
Expected output:
```
═══ test-unrecord-feature.sh ═══
✓ case 1: happy path
✓ case 2: duplicates → first match
✓ case 3: counter floor at 0
✓ case 4: testing_required flips false
✓ case 5: testing_required stays true

═══════════════════════════════════════════
Tests: 5 passed, 0 failed
═══════════════════════════════════════════
```

Exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-gate.sh tests/test-unrecord-feature.sh
git commit -m "feat(test-gate): _unrecord_feature_apply() state transform (BL-008)

Pure state transform that is the inverse of record_feature:
- Removes first occurrence of NAME from features_completed
- Decrements features_since_last_test and features_since_last_health_check,
  floored at 0
- Re-evaluates testing_required against new counter vs test_interval
- Errors if NAME not in array or build-progress.json missing

Unit-testable via source (Task 1's guard). 5 cases passing:
happy path, duplicates → first-match, counter floor at 0,
testing_required flips false, testing_required stays true."
```

---

## Task 3: Add error-handling tests for `_apply` (TDD)

**Files:**
- Modify: `tests/test-unrecord-feature.sh` — add 2 error-path cases

**Why:** Case 6 (feature not found) and Case 7 (missing build-progress.json) are distinct error paths from the state-transform cases. They validate that `_apply` returns non-zero and emits a useful error message in both scenarios. The implementation already handles both cases from Task 2, so this task primarily adds test coverage.

- [ ] **Step 1: Add failing error-handling test cases**

Add these two case functions to `tests/test-unrecord-feature.sh`, immediately before the `# --- Run all cases and report ---` section:

```bash
case_6_feature_not_found() {
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN
  (
    cd "$work"
    mkdir -p .claude
    seed_progress .claude/build-progress.json '["foo"]' 1 2 false 1
    set +e
    local output
    output=$(_unrecord_feature_apply "bar" 2>&1)
    local code=$?
    set -e
    assert_eq "1" "$code" "exit code 1 on not-found"
    assert_contains "$output" "not found" "message mentions not found"
    assert_contains "$output" "bar" "message mentions the specific name"
  )
}

case_7_missing_progress_file() {
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN
  (
    cd "$work"
    # No .claude directory, no build-progress.json
    set +e
    local output
    output=$(_unrecord_feature_apply "anything" 2>&1)
    local code=$?
    set -e
    assert_eq "1" "$code" "exit code 1 on missing file"
    assert_contains "$output" "does not exist" "message mentions file missing"
  )
}
```

Then add these two `run_case` invocations immediately after the existing five, before the `echo ""` separator in the report section:

```bash
run_case "case 6: feature not found"              case_6_feature_not_found
run_case "case 7: missing build-progress.json"    case_7_missing_progress_file
```

- [ ] **Step 2: Run tests to verify all 7 pass**

Run: `bash tests/test-unrecord-feature.sh`
Expected: 7 cases run, all passing. Exit 0.

The implementation in Task 2 already handles both cases (the presence check and the file-existence check), so these tests should pass without implementation changes.

- [ ] **Step 3: Commit**

```bash
git add tests/test-unrecord-feature.sh
git commit -m "test(test-gate): error-path cases for _unrecord_feature_apply

Adds case 6 (feature not found) and case 7 (missing build-progress.json)
to the unrecord-feature test suite. Tests assert exit code 1 and
specific message content. Implementation from Task 2 already handles
both paths; this extends the coverage."
```

---

## Task 4: Add interactive wrapper `unrecord_feature`

**Files:**
- Modify: `scripts/test-gate.sh` — add `unrecord_feature()` function

**Why:** The interactive wrapper handles the tty guard, state preview, Y/N prompt, and audit-log append. Per the spec, this layer is not unit-tested (tty behavior and `read` are bash primitives); we verify manually at end-of-plan.

- [ ] **Step 1: Add `unrecord_feature()` immediately after `_unrecord_feature_apply()`**

```bash
# unrecord_feature <name>
# Interactive wrapper around _unrecord_feature_apply: tty guard,
# state-change preview, Y/N confirmation, audit-log append.
# Blocks agent callers (requires an interactive terminal).
unrecord_feature() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    print_fail "Usage: --unrecord-feature NAME (feature name required)"
    exit 1
  fi

  if [ ! -t 0 ]; then
    print_fail "Unrecord requires interactive authorization."
    echo "The Orchestrator must run this command directly in a terminal:" >&2
    echo "  scripts/test-gate.sh --unrecord-feature \"$name\"" >&2
    exit 1
  fi

  if [ ! -f "$BUILD_PROGRESS" ]; then
    print_fail "Nothing to unrecord: $BUILD_PROGRESS does not exist."
    echo "No features have been recorded in this project yet." >&2
    exit 1
  fi

  # Presence check + diagnostic output (repeats _apply's check to provide
  # the current-features list before prompting)
  if ! jq --arg name "$name" -e '.features_completed | index($name) != null' "$BUILD_PROGRESS" >/dev/null; then
    print_fail "Feature '$name' not found in features_completed."
    echo "Currently recorded features:" >&2
    local features
    features=$(jq -r '.features_completed[]' "$BUILD_PROGRESS" 2>/dev/null || true)
    if [ -z "$features" ]; then
      echo "  (none)" >&2
    else
      echo "$features" | sed 's/^/  - /' >&2
    fi
    exit 1
  fi

  # Compute preview values
  local cur_array cur_fslt cur_fslhc cur_testing interval new_fslt new_fslhc new_testing new_array
  cur_array=$(jq -c '.features_completed' "$BUILD_PROGRESS")
  cur_fslt=$(jq -r '.features_since_last_test' "$BUILD_PROGRESS")
  cur_fslhc=$(jq -r '.features_since_last_health_check // 0' "$BUILD_PROGRESS")
  cur_testing=$(jq -r '.testing_required' "$BUILD_PROGRESS")
  interval=$(jq -r '.test_interval' "$BUILD_PROGRESS")

  new_fslt=$(( cur_fslt - 1 < 0 ? 0 : cur_fslt - 1 ))
  new_fslhc=$(( cur_fslhc - 1 < 0 ? 0 : cur_fslhc - 1 ))
  if [ "$new_fslt" -ge "$interval" ]; then
    new_testing="true"
  else
    new_testing="false"
  fi
  new_array=$(jq --arg name "$name" -c '
    (.features_completed | (. | index($name)) as $i
     | .[0:$i] + .[$i+1:])' "$BUILD_PROGRESS")

  # Show preview
  echo "Unrecord feature '$name'?"
  echo ""
  echo "Current state:"
  echo "  features_completed: $cur_array"
  echo "  features_since_last_test: $cur_fslt / $interval (testing_required: $cur_testing)"
  echo "  features_since_last_health_check: $cur_fslhc"
  echo ""
  echo "After unrecord:"
  echo "  features_completed: $new_array"
  echo "  features_since_last_test: $new_fslt / $interval (testing_required: $new_testing)"
  echo "  features_since_last_health_check: $new_fslhc"
  echo ""

  local confirm
  read -rp "Proceed? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Unrecord cancelled."
    exit 0
  fi

  # Apply
  if ! _unrecord_feature_apply "$name"; then
    print_fail "Unrecord failed — state unchanged"
    exit 1
  fi

  # Audit log
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local audit_entry="[UNRECORD] feature '$name' unrecorded at $now by $(whoami)"
  mkdir -p .claude
  echo "$audit_entry" >> ".claude/process-audit.log"

  print_ok "Feature '$name' unrecorded"
}
```

- [ ] **Step 2: Verify the function is defined (doesn't exit on source)**

Run: `bash -c 'source scripts/test-gate.sh; declare -f unrecord_feature >/dev/null && echo "defined" || echo "missing"'`
Expected output: `defined`

- [ ] **Step 3: Verify test suite still passes**

Run: `bash tests/test-unrecord-feature.sh`
Expected: 7 cases pass (adding the wrapper doesn't affect `_apply` tests).

- [ ] **Step 4: Commit**

```bash
git add scripts/test-gate.sh
git commit -m "feat(test-gate): unrecord_feature interactive wrapper

Adds the interactive wrapper around _unrecord_feature_apply:
- Validates NAME argument, tty presence, file existence, feature presence
- Computes and displays state-change preview (current → projected)
- Y/N confirmation prompt (decline → graceful exit 0 with 'cancelled')
- Delegates state mutation to _apply
- Appends [UNRECORD] entry to .claude/process-audit.log

Mirrors the existing reset_process() safety pattern (interactive-only,
Y/N + preview, audit log). Agent callers are blocked by the [ -t 0 ]
guard."
```

---

## Task 5: Wire argument parser, dispatch, and help text

**Files:**
- Modify: `scripts/test-gate.sh` — add parser case, dispatch case, and help-text line

**Why:** The `unrecord_feature()` function exists but isn't reachable from the CLI yet. This task wires the command-line surface.

- [ ] **Step 1: Add argument parser case**

Find the existing `while [ $# -gt 0 ]; do ... case "$1" in ... esac ... done` block (inside Task 1's source guard) and add a new case **immediately after** the existing `--record-feature)` line. Before:

```bash
    --record-feature)     ACTION="record-feature"; FEATURE_NAME="$2"; shift 2 ;;
    --help|-h)
```

After:

```bash
    --record-feature)     ACTION="record-feature"; FEATURE_NAME="$2"; shift 2 ;;
    --unrecord-feature)   ACTION="unrecord-feature"; FEATURE_NAME="$2"; shift 2 ;;
    --help|-h)
```

- [ ] **Step 2: Add help-text line**

In the same `--help|-h)` block, find the line matching `--record-feature N  Record a completed feature and increment counter` and add a new help line immediately after. Before:

```bash
      echo "  --record-feature N  Record a completed feature and increment counter"
      echo "  --help              Show this help"
```

After:

```bash
      echo "  --record-feature N    Record a completed feature and increment counter"
      echo "  --unrecord-feature N  Un-record a feature recorded in error (interactive; inverse of --record-feature)"
      echo "  --help                Show this help"
```

Note: column alignment was adjusted for the longer `--unrecord-feature` option. If the existing help uses a different alignment pattern, match that instead.

- [ ] **Step 3: Add dispatch case**

Find the existing `case "$ACTION" in ... esac` block. Add a new case **immediately after** `record-feature)`:

Before:

```bash
  record-feature)     record_feature "$FEATURE_NAME" ;;
esac
```

After:

```bash
  record-feature)     record_feature "$FEATURE_NAME" ;;
  unrecord-feature)   unrecord_feature "$FEATURE_NAME" ;;
esac
```

- [ ] **Step 4: Verify help text shows the new option**

Run: `bash scripts/test-gate.sh --help | grep unrecord`
Expected: one line matching `--unrecord-feature N  Un-record a feature recorded in error ...`

- [ ] **Step 5: Verify command routes correctly (non-interactive → expected error)**

Run: `echo "" | bash scripts/test-gate.sh --unrecord-feature "nonexistent" 2>&1 | head -3`
Expected output includes:
```
[FAIL] Unrecord requires interactive authorization.
The Orchestrator must run this command directly in a terminal:
  scripts/test-gate.sh --unrecord-feature "nonexistent"
```
This confirms the dispatch reaches `unrecord_feature` and the tty guard fires. Exit code 1.

- [ ] **Step 6: Commit**

```bash
git add scripts/test-gate.sh
git commit -m "feat(test-gate): wire --unrecord-feature CLI surface

Adds argument parser case, dispatch case, and help-text line for the
new --unrecord-feature NAME subcommand. Command is now reachable via
the CLI; non-interactive invocations correctly hit the tty guard and
exit with remediation guidance."
```

---

## Task 6: CLAUDE.md template "Recovering from mistakes" subsection

**Files:**
- Modify: `templates/generated/claude-md.tmpl` — add subsection to Testing & Bug Workflow

**Why:** Per spec §Documentation, document the new command and surface existing `--reset uat_session` / `--reset build_loop` commands that were previously undocumented in CLAUDE.md. Placement is inside the Testing & Bug Workflow section (not a new top-level section) so recovery guidance sits next to the operations it recovers.

- [ ] **Step 1: Find the insertion point**

Run: `grep -n 'Severity rules:\|After each feature:' templates/generated/claude-md.tmpl`
Expected output includes approximately:
```
170:- **After each feature:** `scripts/test-gate.sh --record-feature "feature-name"`
172:- **Severity rules:** SEV-1 cannot be deferred. SEV-2 can be deferred during Phase 2 but must be resolved or feature removed at Phase 2→3 gate.
```

Note the exact line of the `**Severity rules:**` bullet; we insert immediately after it (inside the same Testing & Bug Workflow bulleted list, before the blank line that ends the section).

- [ ] **Step 2: Insert the "Recovering from mistakes" subsection**

After the `**Severity rules:**` bullet, add the following lines:

```markdown
- **Recovering from mistakes:**
  - Un-record a wrongly-recorded feature: `scripts/test-gate.sh --unrecord-feature "name"` (interactive; fully inverses the `--record-feature` counters)
  - Abort a started UAT session: `scripts/process-checklist.sh --reset uat_session` (interactive)
  - Abort a started Build Loop: `scripts/process-checklist.sh --reset build_loop` (interactive)
  - All three require terminal access and Y/N confirmation; each writes an audit entry to `.claude/process-audit.log`. These are **local-state fixes only** — if the state was committed, amend or revert the commit separately.
```

- [ ] **Step 3: Verify the markdown is well-formed**

Run: `grep -A 6 'Recovering from mistakes:' templates/generated/claude-md.tmpl`
Expected: the full 5-line subsection appears as a nested list, with no accidental line breaks or indentation errors.

Also verify the section that follows is unchanged:

Run: `grep -n 'Phase 2 Completion Checkpoint\|Phase 3-4 Documentation' templates/generated/claude-md.tmpl | head -2`
Expected: both sections still present at their original positions (shifted down by the ~6 inserted lines).

- [ ] **Step 4: Commit**

```bash
git add templates/generated/claude-md.tmpl
git commit -m "docs(claude-md): add 'Recovering from mistakes' subsection (BL-008)

Documents three local-state recovery commands inside the Testing & Bug
Workflow section:
- scripts/test-gate.sh --unrecord-feature NAME (new)
- scripts/process-checklist.sh --reset uat_session (existing)
- scripts/process-checklist.sh --reset build_loop (existing)

Flags all three as interactive, audit-logged, and local-state-only
(amend/revert commits separately if already committed)."
```

---

## Task 7: End-to-end manual smoke test (verification step; no commit)

**Files:**
- No code changes. This task verifies the full interactive flow against a seeded fixture.

**Why:** Per the spec, the interactive wrapper (tty guard, Y/N prompt, audit log) is not unit-tested. An end-to-end manual verification confirms that all components work together under real terminal conditions.

- [ ] **Step 1: Set up a temporary project workspace**

Run:
```bash
TESTPROJ=$(mktemp -d)
cd "$TESTPROJ"
mkdir -p .claude
cat > .claude/build-progress.json <<'JSON'
{
  "features_completed": ["alpha", "beta", "charlie"],
  "features_since_last_test": 2,
  "test_interval": 2,
  "last_test_session": null,
  "testing_required": true,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 0,
  "features_since_last_health_check": 3
}
JSON
echo "TESTPROJ=$TESTPROJ"
```

- [ ] **Step 2: Run the command interactively with an existing name**

Run (replace `/path/to/solo-orchestrator` with the actual path; use `$OLDPWD` if you came from the repo root):
```bash
bash /path/to/solo-orchestrator/scripts/test-gate.sh --unrecord-feature beta
```

Expected output:
```
Unrecord feature 'beta'?

Current state:
  features_completed: ["alpha","beta","charlie"]
  features_since_last_test: 2 / 2 (testing_required: true)
  features_since_last_health_check: 3

After unrecord:
  features_completed: ["alpha","charlie"]
  features_since_last_test: 1 / 2 (testing_required: false)
  features_since_last_health_check: 2

Proceed? [y/N]:
```

- [ ] **Step 3: Type `y` and press Enter**

Expected output (after `y`):
```
  [OK] Feature 'beta' unrecorded
```

Verify state:
```bash
jq . .claude/build-progress.json
```
Expected: `features_completed` is `["alpha","charlie"]`, `features_since_last_test` is `1`, `testing_required` is `false`, `features_since_last_health_check` is `2`.

Verify audit log:
```bash
cat .claude/process-audit.log
```
Expected: one line matching `[UNRECORD] feature 'beta' unrecorded at <ISO-8601-timestamp> by <username>`.

- [ ] **Step 4: Run again with a name that doesn't exist**

Run: `bash /path/to/solo-orchestrator/scripts/test-gate.sh --unrecord-feature does-not-exist`

Expected output:
```
[FAIL] Feature 'does-not-exist' not found in features_completed.
Currently recorded features:
  - alpha
  - charlie
```

Exit code 1.

- [ ] **Step 5: Run and decline at the Y/N prompt**

Run: `bash /path/to/solo-orchestrator/scripts/test-gate.sh --unrecord-feature alpha`

At the prompt, type `n` (or just press Enter).

Expected:
```
  [INFO] Unrecord cancelled.
```

Verify state is unchanged:
```bash
jq '.features_completed' .claude/build-progress.json
```
Expected: `["alpha","charlie"]` — unchanged from Step 3.

- [ ] **Step 6: Clean up**

Run: `rm -rf "$TESTPROJ"; unset TESTPROJ`

- [ ] **Step 7: No commit**

This task is a verification-only step. No code changes to commit. If any step fails, diagnose and fix in the appropriate earlier task, then re-run the full manual smoke test.

---

## Plan Self-Review Checklist

**Spec coverage:**
- [ ] Decision 1 (scope) → Task 2 adds `_apply` in `test-gate.sh`; Task 4 adds wrapper; Task 6 adds doc
- [ ] Decision 2 (counter semantics) → Task 2 jq transform decrements both counters floored at 0 and re-evaluates `testing_required`; test cases 1, 3, 4, 5 validate
- [ ] Decision 3 (name matching) → Task 2 implementation uses `index($name)` (first match); test case 2 validates duplicate handling; test case 6 validates not-found
- [ ] Decision 4 (safety) → Task 4 implements tty guard + Y/N + audit log
- [ ] Decision 5 (git awareness) → none added (spec's non-goal)
- [ ] Decision 6 (documentation) → Task 6 adds subsection in Testing & Bug Workflow

**Placeholder scan:**
- [ ] No "TBD", "TODO", "similar to Task N" anywhere
- [ ] All code blocks contain actual content
- [ ] All assertion expected values are concrete

**Type consistency:**
- [ ] Function names match across tasks: `_unrecord_feature_apply`, `unrecord_feature` (used identically in Tasks 2–5)
- [ ] Command name consistent: `--unrecord-feature` (used identically in Tasks 4–7)
- [ ] JSON field names match the schema: `features_completed`, `features_since_last_test`, `features_since_last_health_check`, `testing_required`, `test_interval`
- [ ] Audit-log format consistent: `[UNRECORD] feature '$name' unrecorded at $timestamp by $(whoami)`

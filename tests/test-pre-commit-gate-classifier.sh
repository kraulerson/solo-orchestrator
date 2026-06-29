#!/usr/bin/env bash
# tests/test-pre-commit-gate-classifier.sh — BL-020 regression test.
#
# scripts/pre-commit-gate.sh:253 classifies a Bash command as "git commit"
# via a regex. Pre-fix the regex was `\bgit\b.*\bcommit\b`, which matches
# any command containing both substrings as words anywhere — false-positive
# on read-only git invocations like `git diff scripts/pre-commit-gate.sh`
# (path contains the word `commit`). Tightened to require `commit` to come
# immediately after `git` (separated only by whitespace) AND for `git` to
# be at command start (line start or after `;`/`&&`/`|`). Still catches
# real `git commit` invocations including chained ones (`cd /foo && git commit`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/pre-commit-gate.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Set up a tempdir project where current_phase=2 with UAT in progress
# (uat_completed < uat_total). In this state the gate WILL block any
# command classified as `git commit` once a source file is staged.
setup_uat_blocking_state() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    git remote add origin https://example.com/fake.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"other"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
JSON
    cat > .claude/process-state.json <<'JSON'
{
  "phase2_init":{"verified":true,"steps_completed":["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied","initialization_verified"]},
  "build_loop":{"feature":null,"step":0,"steps_completed":[]},
  "uat_session":{"session_id":"test","step":7,"steps_completed":["agents_dispatched","template_generated","orchestrator_notified","results_received","completeness_verified","bugs_consolidated","triage_complete"],"started_at":"2026-04-26T00:00:00Z"}
}
JSON
    # Stage a source file so the classifier reaches the source-commit branch.
    echo "stub" > src.py
    git add src.py
  )
}
teardown_project() { rm -rf "$TMPDIR_T"; }

# Feed a JSON tool_input.command to the hook, return its output (stdout+stderr merged) and exit code.
# Echo: "EXIT|OUTPUT_ONE_LINE"
run_hook() {
  local cmd="$1"
  local input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$(cd "$TMPDIR_T" && printf '%s' "$input" | "$HOOK" 2>&1) || rc=$?
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')"
}

# True git commit invocations should be classified and (in this UAT state) BLOCKED.
t1_real_git_commit_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'git commit -m "test"')
  if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
    fail_ "T1" "expected deny for real 'git commit'; got: $out"
    teardown_project; return
  fi
  pass "T1: 'git commit -m \"test\"' classified as commit (blocked under UAT)"
  teardown_project
}

t2_chained_git_commit_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'cd /tmp && git commit -m "x"')
  if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
    fail_ "T2" "expected deny for chained 'cd && git commit'; got: $out"
    teardown_project; return
  fi
  pass "T2: 'cd /tmp && git commit ...' classified as commit (chained invocation)"
  teardown_project
}

# Read-only git operations on files whose paths contain the word `commit` MUST NOT be classified.
t3_git_diff_on_commit_named_file_not_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'git diff scripts/pre-commit-gate.sh')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T3" "false-positive: 'git diff <commit-path>' classified as commit; got: $out"
    teardown_project; return
  fi
  pass "T3: 'git diff scripts/pre-commit-gate.sh' NOT classified as commit (read-only)"
  teardown_project
}

t4_git_log_on_commit_named_file_not_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'git log -- scripts/check-commit-message.sh')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T4" "false-positive: 'git log <commit-path>' classified as commit; got: $out"
    teardown_project; return
  fi
  pass "T4: 'git log -- scripts/check-commit-message.sh' NOT classified as commit"
  teardown_project
}

t5_git_blame_on_commit_named_file_not_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'git blame scripts/pre-commit-gate.sh')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T5" "false-positive: 'git blame <commit-path>' classified as commit; got: $out"
    teardown_project; return
  fi
  pass "T5: 'git blame scripts/pre-commit-gate.sh' NOT classified as commit"
  teardown_project
}

# Commands that mention 'git commit' inside quotes (e.g., grep search strings) MUST NOT be classified.
t6_grep_for_string_not_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'rg "git commit" docs/')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T6" "false-positive: 'rg \"git commit\" docs/' classified as commit; got: $out"
    teardown_project; return
  fi
  pass "T6: 'rg \"git commit\" docs/' NOT classified as commit (search string)"
  teardown_project
}

# --- tests-precommit-process-3: gh pr create classifier pins ---
# T7 positive: a real `gh pr create` invocation under the UAT-blocking
# fixture must be classified as IS_PR and blocked (deny). T8 negative:
# read-only `gh pr list` / `gh pr view` must NOT be classified and must
# fall through with no deny. These pin the gate's gh-pr-create classifier
# regex against accidental regressions (same defect class as BL-020).
t7_real_gh_pr_create_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'gh pr create --title "feat: x" --body "..."')
  if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
    fail_ "T7" "expected deny for real 'gh pr create' under incomplete UAT; got: $out"
    teardown_project; return
  fi
  pass "T7: 'gh pr create --title ... --body ...' classified as PR (blocked under UAT)"
  teardown_project
}

t8_gh_pr_read_only_not_classified() {
  setup_uat_blocking_state
  local out
  # gh pr list — read-only, must fall through.
  out=$(run_hook 'gh pr list')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T8a" "false-positive: 'gh pr list' classified as PR-create; got: $out"
    teardown_project; return
  fi
  # gh pr view 12 — read-only, must fall through.
  out=$(run_hook 'gh pr view 12')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T8b" "false-positive: 'gh pr view 12' classified as PR-create; got: $out"
    teardown_project; return
  fi
  pass "T8: 'gh pr list' / 'gh pr view 12' NOT classified as PR-create (read-only)"
  teardown_project
}

# --- tests-precommit-process-2: git push --force classifier pins ---
# T9 positive: real `git push --force origin main` must be classified
# and denied. T10 chained: `cd /x && git push -f origin feat` must
# still be denied. T11 negative: docs grep / git diff against a doc
# file whose path or contents contain the words "git push --force"
# must NOT be classified. Mirrors the BL-020 pattern (start-anchored,
# not preceded by a quote) so the regex catches real invocations and
# ignores quoted/argument contexts.
t9_real_git_push_force_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'git push --force origin main')
  if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
    fail_ "T9" "expected deny for real 'git push --force'; got: $out"
    teardown_project; return
  fi
  pass "T9: 'git push --force origin main' classified as force-push (blocked)"
  teardown_project
}

t10_chained_git_push_force_classified() {
  setup_uat_blocking_state
  local out; out=$(run_hook 'cd /tmp && git push -f origin feat')
  if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
    fail_ "T10" "expected deny for chained 'cd && git push -f'; got: $out"
    teardown_project; return
  fi
  pass "T10: 'cd /tmp && git push -f origin feat' classified (chained invocation)"
  teardown_project
}

t11_docs_grep_for_push_force_not_classified() {
  setup_uat_blocking_state
  local out
  # Quoted search string mentioning the dangerous command — must fall through.
  out=$(run_hook 'rg "git push --force" docs/')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T11a" "false-positive: 'rg \"git push --force\" docs/' classified as force-push; got: $out"
    teardown_project; return
  fi
  # Read-only git diff against a doc file whose path mentions push/force.
  out=$(run_hook 'git diff docs/git-push-force-recovery.md')
  if [[ "${out#*|}" == *'"permissionDecision": "deny"'* ]]; then
    fail_ "T11b" "false-positive: 'git diff <push-force-named-path>' classified as force-push; got: $out"
    teardown_project; return
  fi
  pass "T11: docs grep + git diff on force-named files NOT classified as force-push"
  teardown_project
}

echo "== tests/test-pre-commit-gate-classifier.sh =="
t1_real_git_commit_classified
t2_chained_git_commit_classified
t3_git_diff_on_commit_named_file_not_classified
t4_git_log_on_commit_named_file_not_classified
t5_git_blame_on_commit_named_file_not_classified
t6_grep_for_string_not_classified
t7_real_gh_pr_create_classified
t8_gh_pr_read_only_not_classified
t9_real_git_push_force_classified
t10_chained_git_push_force_classified
t11_docs_grep_for_push_force_not_classified

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

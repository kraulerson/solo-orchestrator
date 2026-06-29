#!/usr/bin/env bash
# tests/test-process-checklist-check-commit-ready-subject.sh —
# code-process-checklist-5.
#
# check_commit_ready accepts a --subject flag. When a non-feat subject
# is passed, the Phase 2 source-commit block (require_build_loop_state)
# is short-circuited to exit 0. When a feat subject is passed (or no
# subject), behaviour is unchanged from the pre-fix code path. The
# pre-commit gate populates the subject from the same extraction
# heuristics it already uses for BL-006.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a Phase 2 project with build_loop incomplete: a source commit
# would normally be blocked here.
setup_project() {
  TMP=$(mktemp -d)
  (
    cd "$TMP"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    mkdir -p .claude src
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","phases":{}}
JSON
    cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"verified":true,"steps_completed":["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied","initialization_verified"]},"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{"started_at":null,"steps_completed":[]}}
JSON
    echo "console.log(1)" > src/foo.ts
    git add src/foo.ts
  )
}
teardown_project() { rm -rf "$TMP"; }

# T1: chore subject short-circuits (exit 0), Build Loop not enforced.
echo "T1: --subject 'chore: bump dep' short-circuits the source block"
setup_project
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready --subject "chore: bump dep" 2>&1) ; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T1: chore commit allowed (rc=0)"
else
  fail_ "T1" "expected rc=0, got rc=$rc out=$out"
fi
teardown_project

# T2: fix subject short-circuits.
echo "T2: --subject 'fix: bug' short-circuits"
setup_project
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready --subject "fix: NPE on null user" 2>&1) ; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T2: fix commit allowed"
else
  fail_ "T2" "expected rc=0, got rc=$rc out=$out"
fi
teardown_project

# T3: refactor subject short-circuits.
echo "T3: --subject 'refactor: split module' short-circuits"
setup_project
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready --subject "refactor(api): split user module" 2>&1) ; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T3: refactor commit allowed"
else
  fail_ "T3" "expected rc=0, got rc=$rc out=$out"
fi
teardown_project

# T4: feat subject still enforces Build Loop state.
echo "T4: --subject 'feat: new endpoint' STILL enforces Build Loop"
setup_project
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready --subject "feat: new endpoint" 2>&1) ; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qE "(Build Loop|build_loop|feature)"; then
  pass "T4: feat commit BLOCKED (rc=$rc) as expected"
else
  fail_ "T4" "expected non-zero exit citing Build Loop, got rc=$rc out=$out"
fi
teardown_project

# T5: omitted --subject preserves legacy (file-heuristic) behaviour:
# the .ts source file in src/ triggers the Build Loop block.
echo "T5: omitted --subject falls back to file-heuristic enforcement"
setup_project
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready 2>&1) ; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qE "(Build Loop|build_loop|feature)"; then
  pass "T5: file-heuristic still blocks source commit when no subject given"
else
  fail_ "T5" "expected legacy block, got rc=$rc out=$out"
fi
teardown_project

# T6: feat(x)! variant. Conventional Commits breaking-change markers.
echo "T6: --subject 'feat(api)!: drop legacy v1' STILL enforces"
setup_project
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready --subject "feat(api)!: drop legacy v1" 2>&1) ; rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T6: feat-bang subject still enforced (rc=$rc)"
else
  fail_ "T6" "expected non-zero exit, got rc=0"
fi
teardown_project

# T7: pre-commit-gate.sh passes --subject through to --check-commit-ready.
# Grep the script for the wiring — keeps the test fast and stable.
echo "T7: pre-commit-gate.sh wires --subject into --check-commit-ready"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
# Look for invocation of process-checklist.sh --check-commit-ready that
# also includes --subject on the same line (or a chained line).
if awk '/--check-commit-ready/{found=1} found{print; if (/^[^\\]*$/) found=0}' "$GATE" \
     | grep -q -- "--subject"; then
  pass "T7: pre-commit-gate.sh invokes --check-commit-ready with --subject"
else
  fail_ "T7" "pre-commit-gate.sh does NOT pass --subject to --check-commit-ready"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-pre-commit-gate-terminal-mode.sh — BL-030 --terminal-mode flag tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  ( cd "$TMP"
    git init -q
    git config user.email "t@t.l"
    git config user.name "t"
  )
  mkdir -p "$TMP/.claude"
  cat > "$TMP/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  cat > "$TMP/.claude/phase-state.json" <<EOF
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
EOF
  cat > "$TMP/.claude/process-state.json" <<EOF
{"phase2_init":{"steps_completed":["remote_repo_created"],"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
EOF
  ( cd "$TMP" && git remote add origin https://example.com/x.git 2>/dev/null || true )
  # Ship the framework's process-checklist.sh into the test project so
  # --terminal-mode can delegate to its classifier.
  mkdir -p "$TMP/scripts/lib"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$TMP/scripts/"
  # BL-074: process-checklist.sh sources lib/helpers-core.sh directly, and
  # helpers.sh is a shim that sources helpers-full.sh -> helpers-core.sh. A
  # scaffold that copies only helpers.sh makes --check-commit-message die at
  # source-time, so --terminal-mode blocks at the classifier step (T2) instead
  # of reaching the intended behavior. Copy the full sibling chain init.sh ships.
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$TMP/scripts/lib/"
  chmod +x "$TMP/scripts/process-checklist.sh"
}
teardown() { rm -rf "$TMP"; }

# T1 (BL-119): plain --terminal-mode must IGNORE .git/COMMIT_EDITMSG. Its only
# call site is framework-gate.sh at PRE-COMMIT time, where the file still holds
# a PREVIOUS commit's subject — classifying by it bricked a strict repo
# (Dogfood-2 F-DF2-006: after any landed feat: commit, docs:/chore:/test:
# commits were blocked as "'feat(...)' — no Build Loop active"). This case
# used to pin the OPPOSITE (block on the stale feat:) — that pinned the bug.
# The message-scoped gates run at the COMMIT-MSG surface (--tdd-only), where
# the message is CURRENT (see # BL-119-NO-MSG-AT-PRECOMMIT).
echo "T1: plain --terminal-mode ignores a stale feat: COMMIT_EDITMSG (BL-119)"
setup
( cd "$TMP" && echo source > src.go && git add src.go )
echo "feat: add x" > "$TMP/.git/COMMIT_EDITMSG"   # stale previous-commit subject
# SKIP_LINT=1 (here and below): this suite's subject is --terminal-mode
# DISPATCH semantics, not the operator-side lint arm — that arm has its own
# dedicated suite (test-pre-commit-gate-lints.sh). Without it, every rc=0
# invocation walks the full-tree framework lints (~minutes each) via the
# $SCRIPT_DIR fallback, and since BL-119 removed the early classifier exit,
# ALL THREE cases would pay that walk — a unit-lane test cannot.
rc=0
out=$( cd "$TMP" && SKIP_LINT=1 bash "$GATE" --terminal-mode 2>&1 >/dev/null ) || rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'commit message classifier'; then
  pass "T1"
else
  fail_ "T1" "stale-message classifier fired at pre-commit (rc=$rc): $out"
fi
teardown

# T2: --terminal-mode exits 0 on docs-only commit (existing classifier reused).
echo "T2: --terminal-mode passes a docs-only commit"
setup
( cd "$TMP" && echo "# README" > README.md && git add README.md )
echo "docs: add README" > "$TMP/.git/COMMIT_EDITMSG"
( cd "$TMP" && SKIP_LINT=1 bash "$GATE" --terminal-mode >/dev/null 2>&1 ) && pass "T2" || fail_ "T2" "docs-only commit blocked"
teardown

# T3: --terminal-mode does NOT emit JSON to stdout.
echo "T3: --terminal-mode does not emit JSON permission decision"
setup
( cd "$TMP" && echo source > src.go && git add src.go )
echo "feat: add x" > "$TMP/.git/COMMIT_EDITMSG"
out=$( cd "$TMP" && SKIP_LINT=1 bash "$GATE" --terminal-mode 2>/dev/null || true )
if ! echo "$out" | grep -q "permissionDecision"; then pass "T3"; else fail_ "T3" "JSON permission decision leaked to stdout"; fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

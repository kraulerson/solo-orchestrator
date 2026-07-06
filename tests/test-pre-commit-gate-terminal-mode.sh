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

# T1: --terminal-mode reads from COMMIT_EDITMSG and emits human-readable to stderr.
echo "T1: --terminal-mode reads COMMIT_EDITMSG, emits stderr"
setup
( cd "$TMP" && echo source > src.go && git add src.go )
echo "feat: add x" > "$TMP/.git/COMMIT_EDITMSG"
out=$( cd "$TMP" && bash "$GATE" --terminal-mode 2>&1 >/dev/null || true )
# In strict mode with no Build Loop progress, this should block (Phase 2 + source file + feat: prefix).
if echo "$out" | grep -qE '\[FRAMEWORK GATE|FAIL|Block reason'; then pass "T1"; else fail_ "T1" "no human-readable block on stderr: $out"; fi
teardown

# T2: --terminal-mode exits 0 on docs-only commit (existing classifier reused).
echo "T2: --terminal-mode passes a docs-only commit"
setup
( cd "$TMP" && echo "# README" > README.md && git add README.md )
echo "docs: add README" > "$TMP/.git/COMMIT_EDITMSG"
( cd "$TMP" && bash "$GATE" --terminal-mode >/dev/null 2>&1 ) && pass "T2" || fail_ "T2" "docs-only commit blocked"
teardown

# T3: --terminal-mode does NOT emit JSON to stdout.
echo "T3: --terminal-mode does not emit JSON permission decision"
setup
( cd "$TMP" && echo source > src.go && git add src.go )
echo "feat: add x" > "$TMP/.git/COMMIT_EDITMSG"
out=$( cd "$TMP" && bash "$GATE" --terminal-mode 2>/dev/null || true )
if ! echo "$out" | grep -q "permissionDecision"; then pass "T3"; else fail_ "T3" "JSON permission decision leaked to stdout"; fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

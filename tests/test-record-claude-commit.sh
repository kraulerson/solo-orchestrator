#!/usr/bin/env bash
# tests/test-record-claude-commit.sh — BL-030 Claude-commit recorder tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/record-claude-commit.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# The PostToolUse hook contract for Claude Code: stdin is a JSON object
# with at least { "tool_input": {...}, "tool_response": {...} }. We expect
# the hook to inspect tool_input.command and only act on git-commit calls
# that succeeded.

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  ( cd "$TMP"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    echo "first" > f.txt && git add f.txt && git commit -qm "first" 2>/dev/null
  )
  SHA=$(cd "$TMP" && git rev-parse HEAD)
}
teardown() { rm -rf "$TMP"; }

# T1: hook records a successful git commit.
echo "T1: PostToolUse hook records SHA of a successful git commit"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T1" "hook script missing (RED expected before impl)"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'feat: x'"},"tool_response":{"exit_code":0}}
EOF
  if [ -f "$TMP/.claude/claude-commits.jsonl" ] && \
     jq -e --arg sha "$SHA" '.sha == $sha' < "$TMP/.claude/claude-commits.jsonl" >/dev/null 2>&1; then
    pass "T1"
  else
    fail_ "T1" "claude-commits.jsonl missing or SHA mismatch"
  fi
fi
teardown

# T2: hook does NOT record a non-git-commit tool call.
echo "T2: PostToolUse hook ignores non-commit Bash calls"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T2" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"ls -la"},"tool_response":{"exit_code":0}}
EOF
  if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
    pass "T2"
  else
    fail_ "T2" "ledger should not exist for ls call"
  fi
fi
teardown

# T3: hook does NOT record a failed git commit.
echo "T3: PostToolUse hook ignores failed git commits"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T3" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'feat: x'"},"tool_response":{"exit_code":1}}
EOF
  if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
    pass "T3"
  else
    fail_ "T3" "ledger should not exist for failed commit"
  fi
fi
teardown

# T4: hook is append-only — second commit appends a row.
echo "T4: PostToolUse hook appends to existing ledger"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T4" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'first'"},"tool_response":{"exit_code":0}}
EOF
  echo "second" > g.txt && git add g.txt && git commit -qm "second" 2>/dev/null
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'second'"},"tool_response":{"exit_code":0}}
EOF
  count=$(wc -l < "$TMP/.claude/claude-commits.jsonl" | tr -d ' ')
  if [ "$count" = "2" ]; then pass "T4"; else fail_ "T4" "expected 2 rows, got $count"; fi
fi
teardown

# T5: hook is silent on missing .claude/ (project not initialized).
echo "T5: PostToolUse hook is a no-op when .claude/ does not exist"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.l" && git config user.name "t"
  echo x > x && git add x && git commit -qm x )
if [ ! -f "$HOOK" ]; then
  fail_ "T5" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'x'"},"tool_response":{"exit_code":0}}
EOF
  if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
    pass "T5"
  else
    fail_ "T5" "ledger created in uninitialized project"
  fi
fi
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

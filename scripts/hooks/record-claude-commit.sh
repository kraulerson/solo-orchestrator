#!/usr/bin/env bash
# scripts/hooks/record-claude-commit.sh — BL-030 PostToolUse hook.
#
# Records the SHA of every successful git commit issued by Claude into
# .claude/claude-commits.jsonl. Always-on, regardless of enforcement_level.
# The ledger is the substrate the out-of-band detector uses to distinguish
# Claude-issued commits from user-terminal commits.
#
# Stdin: JSON envelope from Claude Code's PostToolUse hook contract:
#   { "tool_input": {"command": "..."}, "tool_response": {"exit_code": N} }
#
# No-op conditions:
#   - .claude/ doesn't exist (project not initialized)
#   - tool_input.command isn't a `git commit` invocation
#   - tool_response.exit_code != 0
#   - jq isn't installed (silent — never block Claude on missing infrastructure)
#   - HEAD ref isn't readable (e.g., empty repo before first commit)

set -uo pipefail

# Locate project root (CLAUDE_PROJECT_DIR is set by Claude Code; fall back to git).
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Read envelope.
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
EXIT=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 1' 2>/dev/null)

# Filter: must be a `git commit` (not `git commit-tree`, etc.) and must have succeeded.
#
# Audit finding `specs-plans-bl029-bl030-5` (sibling of BL-020 on the
# pre-commit-gate side): the previous naive substring match
# `case "$CMD" in *"git commit"*)` false-positives on innocuous commands
# whose argv or output happens to contain the literal string `git commit`
# (e.g., `echo "see git commit later"`, `rg "git commit" docs/`,
# `cat scripts/pre-commit-gate.sh | grep "git commit"`). Each false-positive
# polluted the BL-029 ledger with a spurious entry mapped to whatever the
# current HEAD happened to be, which the out-of-band detector then trusted.
#
# Tightened classifier (verbatim from `scripts/pre-commit-gate.sh:81-93`):
#   `commit` must come immediately after `git` (separated only by whitespace),
#   and `git` must NOT be preceded by a quote — so `rg "git commit"` is rejected
#   while `cd /tmp && git commit ...` (preceded by whitespace) is accepted.
#
# --amend semantics (option C from the audit response): no special-casing.
# `git commit --amend` runs the normal flow — the amended commit is recorded
# as a fresh ledger entry under its new HEAD SHA. The pre-amend entry remains
# as an orphan SHA in the append-only ledger; this is acceptable because the
# out-of-band detector matches against ledger membership, so the amended SHA
# is correctly classified as Claude-issued rather than user-terminal.
_is_git_commit() {
  echo "$1" | grep -qE '(^|[^"'\''])git[[:space:]]+commit\b'
}
_is_git_commit "$CMD" || exit 0
echo "$CMD" | grep -qE '(^|[^"'\''])git[[:space:]]+commit-tree\b' && exit 0
[ "$EXIT" != "0" ] && exit 0

# Capture HEAD SHA. If unreadable, no-op silently.
SHA=$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null)
[ -z "$SHA" ] && exit 0

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

LEDGER="$PROJECT_ROOT/.claude/claude-commits.jsonl"
jq -nc \
  --arg sha "$SHA" \
  --arg ts "$TS" \
  --arg sid "$SESSION_ID" \
  '{sha: $sha, timestamp: $ts, session_id: $sid, gate: "passed"}' >> "$LEDGER"

exit 0

#!/usr/bin/env bash
# scripts/lint-fixture-envelopes.sh — fail CI if any tests/ fixture still
# encodes a Claude Code hook envelope with the wrong wire-format key.
#
# PostToolUse: real envelope uses `tool_response`, NOT `tool_result`.
# Stop:        real envelope uses `last_assistant_message` + `transcript_path`,
#              NOT `transcript` or `tool_response`.
#
# Legacy fixtures with the wrong shape silently fall through the hook's
# `// ""` fallback and never exercise the detector — making the test
# suite green against code that is dead in production. This linter is
# the regression guard for audit S1 findings tests-bypass-bl029-1
# and tests-bypass-bl029-2.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$REPO_ROOT/tests}"

FAILED=0

bad_posttooluse=$(grep -rEn '"hook_event_name"[[:space:]]*:[[:space:]]*"PostToolUse"[^}]*"tool_result"' \
  "$TARGET" \
  --include="*.sh" --include="*.bats" --include="*.json" \
  2>/dev/null || true)

if [ -n "$bad_posttooluse" ]; then
  echo "ERROR: PostToolUse fixtures using legacy 'tool_result' key (use 'tool_response'):" >&2
  echo "$bad_posttooluse" >&2
  FAILED=1
fi

bad_stop=$(grep -rEn '"hook_event_name"[[:space:]]*:[[:space:]]*"Stop"[^}]*("tool_response"|"transcript"[[:space:]]*:[[:space:]]*")' \
  "$TARGET" \
  --include="*.sh" --include="*.bats" --include="*.json" \
  2>/dev/null || true)

if [ -n "$bad_stop" ]; then
  echo "ERROR: Stop fixtures using wrong envelope (use 'last_assistant_message' + optional 'transcript_path'):" >&2
  echo "$bad_stop" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "OK: no fixture envelopes use legacy schema."
fi
exit "$FAILED"

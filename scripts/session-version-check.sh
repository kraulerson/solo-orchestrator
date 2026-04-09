#!/usr/bin/env bash
# Solo Orchestrator — SessionStart hook wrapper for check-versions.sh
# Only outputs to agent context when something needs attention.
# Silent when everything is up to date (no noise for the agent to bury).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run check-versions.sh and capture output
VERSION_OUTPUT=""
VERSION_EXIT=0
VERSION_OUTPUT=$(bash "$SCRIPT_DIR/check-versions.sh" 2>&1) || VERSION_EXIT=$?

# Extract warning lines (tools needing attention)
WARN_LINES=$(echo "$VERSION_OUTPUT" | grep "^\[WARN\]" | grep -v "^$" || true)

# Extract update commands section
UPDATE_CMDS=$(echo "$VERSION_OUTPUT" | sed -n '/^Update commands/,$ p' || true)
if [ -z "$UPDATE_CMDS" ]; then
  UPDATE_CMDS=$(echo "$VERSION_OUTPUT" | sed -n '/^Manual update commands/,$ p' || true)
fi

# Extract BELOW MINIMUM lines (critical — tool version too old for enforcement)
BELOW_MIN_LINES=$(echo "$VERSION_OUTPUT" | grep "BELOW MINIMUM" || true)

# Only output when something needs attention
if [ -n "$BELOW_MIN_LINES" ] || [ "$VERSION_EXIT" -ne 0 ]; then
  cat << EOF
URGENT — VERSION CHECK FAILED. Report this to the Orchestrator IMMEDIATELY as your FIRST response before any other work.

Tools BELOW MINIMUM VERSION (blocks Phase 2+ work):
$WARN_LINES

${UPDATE_CMDS:+$UPDATE_CMDS

}Do NOT proceed with any work until the Orchestrator addresses these version issues.
Ask the Orchestrator: "The following tools are outdated. Would you like me to run the update commands now?"
Then list each update command and wait for approval before running them.
EOF
elif [ -n "$WARN_LINES" ] || [ -n "$UPDATE_CMDS" ]; then
  cat << EOF
VERSION CHECK: Report the following to the Orchestrator as your FIRST response before any other work.

${WARN_LINES:+Warnings:
$WARN_LINES

}${UPDATE_CMDS:+$UPDATE_CMDS

}You MUST ask the Orchestrator: "Would you like me to run these updates now, or skip for this session?"
List each update command explicitly and wait for their answer. Do NOT skip this question.
EOF
fi
# If everything is up to date: output nothing. No noise.

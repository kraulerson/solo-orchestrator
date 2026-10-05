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

# ── `## BL-318:` G5 — the project's Development Guardrails update is OFFERED,
# never run by the agent. check-versions.sh lists it as
#   "  Development Guardrails in this project: bash scripts/refresh-guardrails.sh"
# under "Update commands". The generic text below tells the agent to ask "Would
# you like me to run these updates now", and for THIS update that is wrong: the
# Guardrails' config-guard blocks the agent writing .claude/framework/ and
# .claude/manifest.json, and an agent that tries, is refused, and looks for a
# way round is the bypass the detector exists for. So the row and its command
# leave the generic lists, and _gr_offer asks the human to type the command
# after `!` (the route `# BL-311-ASSESSMENT-AUTO-MODE` established). No memory
# of a refusal is kept: the offer returns at every session start until the
# versions match (Karl, 2026-10-05), so a session blocked by a Guardrails defect
# can be restarted and the fix accepted.
#
# Its words name no terminal and no shell: a relay of a terminal route in the
# agent's own words matched terminal_workaround (measured for BL-311), and
# tests/test-bl318-g5-guardrails-refresh.sh S3 checks every line, the whole
# offer as one line, and a relay of it against scripts/lib/bypass-patterns.sh.
GR_TAG="Development Guardrails in this project:"
GR_STATE=""
GR_CMD=""
GR_CMD_LINE="$(printf '%s\n' "$UPDATE_CMDS" | grep -F -- "  $GR_TAG " | head -1 || true)"   # BL-318-G5-SESSION-DETECT
if [ -n "$GR_CMD_LINE" ]; then
  GR_CMD="${GR_CMD_LINE#*"$GR_TAG" }"
  GR_STATE="$(printf '%s\n' "$WARN_LINES" | grep -F -- "[WARN] $GR_TAG " | head -1 || true)"
  GR_STATE="${GR_STATE#"[WARN] "}"
  WARN_LINES="$(printf '%s\n' "$WARN_LINES" | grep -vF -- "[WARN] $GR_TAG " || true)"   # BL-318-G5-SESSION-WARN-SPLIT
  UPDATE_CMDS="$(printf '%s\n' "$UPDATE_CMDS" | grep -vF -- "  $GR_TAG " || true)"   # BL-318-G5-SESSION-SPLIT
  # The heading alone is not a list: drop it when the offer was its only line.
  if [ "$(printf '%s\n' "$UPDATE_CMDS" | grep -c '^  ' || true)" = "0" ]; then UPDATE_CMDS=""; fi
fi

# What the update changes and how it applies were MEASURED (`## BL-318:` G5):
# scripts/refresh-guardrails.sh rewrites only .claude/framework/ and the
# manifest's frameworkVersion/frameworkCommit; Claude Code starts every hook as
# a new process from the path in .claude/settings.json, so the next tool call
# runs the new files, while the Guardrails' own session-start message was
# printed once, at this session's start.
_gr_offer() {
  printf '%s\n' "GUARDRAILS UPDATE OFFER. Tell the Orchestrator about it in your FIRST response, before any other work:"
  printf '  %s\n' "${GR_STATE:-$GR_TAG an update is available}"
  printf '%s\n' "What the update changes: it copies the Guardrails hooks, rules and gates into .claude/framework/ again and records the new version in .claude/manifest.json. It does not change .claude/settings.json."
  printf '%s\n' "Do NOT run the update yourself: the Guardrails block you from changing .claude/framework/ and .claude/manifest.json. Ask the Orchestrator whether to update now. If they agree, ask them to type ! and then this exact command at the Claude Code prompt:"   # BL-318-G5-SESSION-ROUTE
  printf '  %s\n' "$GR_CMD"
  printf '%s\n' "Wait for its output: it ends in an [OK] line when the update landed, or a [FAIL] line that names what stopped it."
  printf '%s\n' "Once it lands, no restart is needed for the new hooks: Claude Code runs each hook from its file on every call, so your next tool call uses them. Only the Guardrails' own session-start message stays the old one until the next session."
  printf '%s\n' "If they decline, carry on. This offer comes back at every session start until the update is done."
}

# Only output when something needs attention
GENERIC_SHOWN=false
if [ -n "$BELOW_MIN_LINES" ] || [ "$VERSION_EXIT" -ne 0 ]; then
  GENERIC_SHOWN=true
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
  GENERIC_SHOWN=true
  cat << EOF
VERSION CHECK: Report the following to the Orchestrator as your FIRST response before any other work.

${WARN_LINES:+Warnings:
$WARN_LINES

}${UPDATE_CMDS:+$UPDATE_CMDS

}You MUST ask the Orchestrator: "Would you like me to run these updates now, or skip for this session?"
List each update command explicitly and wait for their answer. Do NOT skip this question.
EOF
fi
if [ -n "$GR_CMD" ]; then
  if [ "$GENERIC_SHOWN" = true ]; then echo ""; fi
  _gr_offer                                                                       # BL-318-G5-SESSION-OFFER
fi
# If everything is up to date: output nothing. No noise.

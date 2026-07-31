#!/usr/bin/env bash
# Solo Orchestrator — SessionStart hook for intake/Phase-0 onboarding state
# BL-202: Claude Code loads project context only when the FIRST message is
# sent, so a fresh session in a generated project dead-airs — the user does
# not know what to type, and Claude does not know the intake is unfinished.
# This hook puts that fact INTO context on every launch surface (CLI, desktop,
# IDE), where terminal prints can never reach. Contract mirrors
# session-test-gate-check.sh / session-freshness-check.sh: silent when
# healthy, fail-open (exit 0 always), the agent RELAYS the output.
#
# Detection is MODE-AGNOSTIC — the blank-table-cell count over
# PROJECT_INTAKE.md (scripts/validate.sh's predicate, >20 = incomplete).
# .claude/intake-progress.json is written by the wizard's main-menu mode 1
# ONLY, so it must never be the deciding signal (AI-assist and manual users
# would read "incomplete" forever).
#
# Standalone by design: sources nothing, so tests can run a copy from any
# directory (the R-BL203-13 lesson — an unloadable mutant proves nothing).
set -uo pipefail

# Not a generated project (or init mid-flight): not ours, stay silent.
[ -f ".claude/phase-state.json" ] || exit 0
[ -f "PROJECT_INTAKE.md" ] || exit 0

# The operator already chose to proceed without the intake — never nag twice.
ACK=$(jq -r '.intake.proceed_without_intake_acknowledged // false' .claude/process-state.json 2>/dev/null) || ACK="false"
[ "$ACK" = "true" ] && exit 0

CURRENT_PHASE=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' .claude/phase-state.json 2>/dev/null | grep -o '[0-9][0-9]*' | head -1) || CURRENT_PHASE=""
case "$CURRENT_PHASE" in ''|*[!0-9]*) CURRENT_PHASE=0 ;; esac
# Past Phase 0: onboarding is over; this hook has nothing to say.
[ "$CURRENT_PHASE" -eq 0 ] || exit 0

# BL-202-INTAKE-DETECT-BEGIN
blank_cells=$(grep -cE '\| *\|$|\| *$' PROJECT_INTAKE.md 2>/dev/null || true)
case "$blank_cells" in ''|*[!0-9]*) blank_cells=0 ;; esac

if [ "$blank_cells" -gt 20 ]; then
  cat <<EOF
INTAKE INCOMPLETE — relay this to the operator as your FIRST response, then follow it.

This project's intake (PROJECT_INTAKE.md) has ~${blank_cells} unfilled fields and Phase 0 has
not started. Offer the operator these two choices ONCE, then respect the answer:
  1. Continue the intake now — run: bash scripts/intake-wizard.sh
     (or work through PROJECT_INTAKE.md's unfilled sections together).
  2. Proceed without it — record the choice so this notice never repeats:
     [ -f .claude/process-state.json ] || echo '{}' > .claude/process-state.json
     jq '.intake.proceed_without_intake_acknowledged = true' .claude/process-state.json > .claude/process-state.json.tmp && mv .claude/process-state.json.tmp .claude/process-state.json
If the operator's first message is a real task, answer it AFTER offering this choice once —
never block their work over paperwork.
EOF
  exit 0
fi
# BL-202-INTAKE-DETECT-END

# Intake looks filled; has Phase 0 produced anything yet?
if [ ! -f "PRODUCT_MANIFESTO.md" ]; then
  cat <<EOF
READY FOR PHASE 0 — relay this to the operator as your FIRST response.

The intake looks complete and Phase 0 has not started yet (no PRODUCT_MANIFESTO.md).
The exact first message to paste is printed by: bash scripts/resume.sh
(It is the Agent Initialization Prompt from PROJECT_INTAKE.md Section 13.)
If the operator asks you directly, offer to begin Phase 0 from that prompt now.
EOF
fi
exit 0

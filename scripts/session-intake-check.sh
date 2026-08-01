#!/usr/bin/env bash
# Solo Orchestrator — SessionStart hook for intake/Phase-0 onboarding state
# BL-202: Claude Code loads project context only when the FIRST message is
# sent, so a fresh session in a generated project dead-airs — the user does
# not know what to type, and Claude does not know the intake is unfinished.
# This hook puts that fact INTO CLAUDE'S CONTEXT on every launch surface (CLI,
# desktop, IDE) and, on a genuinely fresh conversation, ALSO seeds the first
# user turn so the screen need not stay blank at all.
#
# OUTPUT CONTRACT (BL-202 follow-up; verified against
# https://code.claude.com/docs/en/hooks.md, fetched 2026-07-31). When this
# hook has something to say it emits exactly ONE compact JSON document:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart",
#                          "additionalContext":"…","initialUserMessage":"…"}}
#   • additionalContext is the structured equivalent of the plain stdout this
#     hook used to print — SAME TEXT, same job: it lands in Claude's context,
#     so whatever the operator types first, the reply knows the intake state
#     and relays it. Emitted on EVERY source; that is the old behaviour,
#     preserved exactly. Multiple hooks' additionalContext is merged by Claude
#     Code, and the sibling hooks' plain stdout coexists with it.
#   • initialUserMessage seeds an actual first user turn, and so is written in
#     the OPERATOR'S voice and kept short — the heavy instructions stay in
#     additionalContext. Its client-side behaviour (auto-submit vs. pre-fill)
#     is UNDERDOCUMENTED, so the same request is ALSO carried by
#     additionalContext: a client or version that ignores the field lands
#     exactly on the pre-follow-up behaviour. Degradation by construction.
#   • It is emitted ONLY for source ∈ {startup, clear} — genuine fresh
#     conversations. resume/compact are mid-conversation context refreshes
#     where a synthetic user message would CORRUPT a real conversation, so the
#     gate FAILS CLOSED: absent, unreadable, unparsable or unrecognised
#     (incl. future fork variants) all count as NOT-fresh. This is
#     deliberately the OPPOSITE default from session-test-gate-check.sh, whose
#     missing-envelope default is "startup" for legacy compatibility.
#   • Plain stdout and JSON from ONE hook is UNDEFINED, so every speaking path
#     goes through emit_state() and emits one form only. The single non-JSON
#     fallback fires when jq itself fails, i.e. before anything is written.
#   • Silence stays silence. The not-a-project, no-jq, acknowledged and
#     past-Phase-0 paths print NOTHING — no envelope, no empty JSON.
# Fail-open is absolute: every path exits 0.
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

# Without jq the ack below is unreadable AND the printed remedy is unrunnable —
# an unsilenceable nag loop (review R-BL202-6). Every sibling hook guards this.
# jq is ALSO this hook's JSON encoder (emit_state) and envelope parser, so past
# this line jq is guaranteed present and nothing hand-rolls JSON escaping.
command -v jq >/dev/null 2>&1 || exit 0

# The operator already chose to proceed without the intake — never nag twice.
ACK=$(jq -r '.intake.proceed_without_intake_acknowledged // false' .claude/process-state.json 2>/dev/null) || ACK="false"
[ "$ACK" = "true" ] && exit 0

CURRENT_PHASE=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' .claude/phase-state.json 2>/dev/null | grep -o '[0-9][0-9]*' | head -1) || CURRENT_PHASE=""
case "$CURRENT_PHASE" in ''|*[!0-9]*) CURRENT_PHASE=0 ;; esac
# Past Phase 0: onboarding is over; this hook has nothing to say.
[ "$CURRENT_PHASE" -eq 0 ] || exit 0

# BL-202-INITIAL-MSG-BEGIN
# Read SessionStart's `source` from the stdin envelope and decide whether
# seeding a synthetic first user turn is SAFE. Deliberately placed after every
# silence guard: a silent run must never block on an unclosed stdin pipe.
FRESH_SESSION=false
if [ ! -t 0 ]; then
  ENVELOPE=$(cat 2>/dev/null) || ENVELOPE=""
  if [ -n "$ENVELOPE" ]; then
    SESSION_SOURCE=$(printf '%s' "$ENVELOPE" | jq -r '.source // ""' 2>/dev/null) || SESSION_SOURCE=""
    case "$SESSION_SOURCE" in
      startup|clear) FRESH_SESSION=true ;;  # BL-202-SOURCE-GATE — fresh conversations ONLY; every other value (resume, compact, fork variants, "") leaves the gate shut
    esac
  fi
fi

# emit_state <additional-context> <initial-user-message>
# ONE JSON document per run. initialUserMessage is included only behind the
# source gate; additionalContext always carries the full text, so dropping the
# field costs nothing but the auto-start.
emit_state() {
  local ctx="$1" msg="$2" out=""
  if [ "$FRESH_SESSION" = "true" ]; then
    out=$(jq -n -c --arg ctx "$ctx" --arg msg "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx,initialUserMessage:$msg}}' 2>/dev/null) || out=""  # BL-202-JSON-ENCODE
  else
    out=$(jq -n -c --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' 2>/dev/null) || out=""  # BL-202-JSON-ENCODE
  fi
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    # jq failed AFTER its guard (not reachable in practice, cheap to survive).
    # Nothing has been printed yet, so falling back to the pre-follow-up plain
    # stdout form is a clean degrade, not a mixed-form emission.
    printf '%s\n' "$ctx"
  fi
}
# BL-202-INITIAL-MSG-END

# BL-202-INTAKE-DETECT-BEGIN
# BL-202-INTAKE-PREDICATE (SYNC SIBLINGS: scripts/validate.sh, scripts/session-intake-check.sh, scripts/resume.sh) — count only truly-blank cells: '\| *\|$'. The old '|\| *$' alternative matched EVERY table row (constant 258 on real intakes — review R-BL202-1).
blank_cells=$(grep -cE '\| *\|$' PROJECT_INTAKE.md 2>/dev/null || true)
case "$blank_cells" in ''|*[!0-9]*) blank_cells=0 ;; esac

# bash 3.2 cannot parse a heredoc INSIDE $( ) — the body is read as code and the
# script dies at parse time. So each state's text lives in a function whose
# heredoc is parsed at definition time, and the call site is a plain $( ).
intake_context() {
  cat <<EOF
INTAKE INCOMPLETE — relay this to the operator as your FIRST response, then follow it.

This project's intake (PROJECT_INTAKE.md) has ~${blank_cells} unfilled fields and Phase 0 has
not started. Offer the operator these two choices ONCE, then respect the answer:
  1. Continue the intake now — run: bash scripts/intake-wizard.sh
     (or work through PROJECT_INTAKE.md's unfilled sections together).
  2. Proceed without it — record the choice so this notice never repeats (if
     .claude/process-state.json is missing, run bash scripts/process-checklist.sh --verify-init first):
     jq '.intake.proceed_without_intake_acknowledged = true' .claude/process-state.json > .claude/process-state.json.tmp && mv .claude/process-state.json.tmp .claude/process-state.json
If the operator's first message is a real task, answer it AFTER offering this choice once —
never block their work over paperwork.
EOF
}

if [ "$blank_cells" -gt 20 ]; then
  emit_state "$(intake_context)" "I just opened this project. Check the intake status and tell me what my options are."
  exit 0
fi
# BL-202-INTAKE-DETECT-END

ready_context() {
  cat <<EOF
READY FOR PHASE 0 — relay this to the operator as your FIRST response.

The intake looks complete and Phase 0 has not started yet (no PRODUCT_MANIFESTO.md).
The exact first message to paste is printed by: bash scripts/resume.sh
(It is the Agent Initialization Prompt from PROJECT_INTAKE.md Section 13.)
If the operator asks you directly, offer to begin Phase 0 from that prompt now.
EOF
}

# Intake looks filled; has Phase 0 produced anything yet?
if [ ! -f "PRODUCT_MANIFESTO.md" ]; then
  emit_state "$(ready_context)" "I just opened this project. Run bash scripts/resume.sh and show me the Phase 0 first prompt so I can get started."
fi
exit 0

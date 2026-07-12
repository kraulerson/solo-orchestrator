#!/usr/bin/env bash
# scripts/session-freshness-check.sh
#
# Solo Orchestrator — SessionStart hook wrapper for the Currency System's
# read-only freshness detector (BL-109 SLICE-S2, Layer 1 — Detection; design
# v1.1 §2-L1; invariant I7). Injected by init.sh into SessionStart exactly the
# way session-version-check.sh is. Silent when everything is current — no noise
# for the agent to bury.
#
# BEHAVIOUR (design v1.1 §2-L1 + I7):
#   • SILENT when current — ZERO bytes on stdout/stderr (Appendix P rung 1:
#     a noisy day zero is a live-test abort).
#   • ZERO network — ever. Reads the LOCAL framework/CDF clones only.
#   • Writes NOTHING in the project tree except `.claude/cache/freshness.json`.
#   • FAIL-OPEN: this wrapper guarantees exit 0 under EVERY failure mode. An
#     internal crash prints at most one short `[freshness check unavailable]`
#     line and still exits 0 — a broken checker must never brick a session.
#   • On drift: ONE compact tiered human block (enforcement first) + ONE fenced
#     machine block (schema below). The agent RELAYS it and offers the update
#     flow; detection never applies anything.
#
# MACHINE-BLOCK CONTRACT (fenced as ```soif-freshness; S5 will lint it):
#   {
#     "schema":            "soif-freshness/1",   // stable identifier
#     "generatedAt":       "<ISO-8601 UTC>",
#     "current":           true|false,           // true iff items == []
#     "enforcementSnoozed":<int>,                // held enforcement snoozes
#     "toolsCovered":      false,                // S2 does NOT cover tools —
#                                                //   check-versions.sh + its
#                                                //   session-version-check.sh
#                                                //   wiring own the tool surface
#     "network":           "none",               // zero-network guarantee
#     "items": [
#       { "id":     "<stable-item-id>",          // e.g. "orphan:scripts/foo.sh"
#         "check":  "local-edit|framework|framework-drift|orphan|hook|render-base|cdf",
#         "tier":   "enforcement|informational",
#         "path":   "<rel-path>|null",
#         "verb":   "add|update|retire|null",    // the §2-L2 lifecycle verb
#         "message":"<human string>" }
#     ]
#   }
#
# USAGE:
#   session-freshness-check.sh                 # detect (the SessionStart path)
#   session-freshness-check.sh --snooze <id>   # snooze a drift item (out of band)
#   session-freshness-check.sh --unsnooze <id> # drop a snooze
#   session-freshness-check.sh --help
#
# SNOOZE: informational snoozes hold until the upstream delta changes;
# ENFORCEMENT snoozes auto-expire after 7 days AND are recorded through
# scripts/lib/bypass-audit.sh (review-r1 M5). Snooze SETTING is out of band —
# it is exposed here only as the explicit --snooze flag (never prompted, never
# invoked during silent detection).
#
# NOT under `set -e` — fail-open is the whole point; a mid-detection error must
# degrade to exit 0, not abort the shell.

set -uo pipefail   # deliberately NO -e (I7 fail-open)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load the detection lib (transitively loads currency-manifest.sh +
# hook-templates.sh). Shipped downstream beside this script by init.sh.
# shellcheck source=/dev/null
if [ -f "$SCRIPT_DIR/lib/freshness-detect.sh" ]; then
  . "$SCRIPT_DIR/lib/freshness-detect.sh"
else
  # Lib absent (a broken scaffold) — fail open, silently.
  exit 0
fi

# Project root: the harness passes CLAUDE_PROJECT_DIR; fall back to this
# script's parent (scripts/..) for direct invocation.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# ── Flag dispatch (out-of-band; never the SessionStart path) ─────────────────
case "${1:-}" in
  --help|-h)
    sed -n '2,60p' "$SCRIPT_DIR/session-freshness-check.sh" 2>/dev/null | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  --snooze)
    if command -v soif_freshness_snooze >/dev/null 2>&1; then
      soif_freshness_snooze "$PROJECT_DIR" "${2:-}" || true
    fi
    exit 0
    ;;
  --unsnooze)
    if command -v soif_freshness_unsnooze >/dev/null 2>&1; then
      soif_freshness_unsnooze "$PROJECT_DIR" "${2:-}" || true
    fi
    exit 0
    ;;
esac

# ── The fail-open wrapper (I7) ───────────────────────────────────────────────
# Run the detection dispatch, capturing stdout. ANY nonzero return (a genuine
# internal fault) is converted to exit 0 + one short line. stderr is discarded
# so a stray sub-tool message can never leak into the agent's context.
# BL-109-FRESHNESS-FAILOPEN — this arm is what makes a broken checker inert.
_soif_fresh_out=""
_soif_fresh_rc=0
_soif_fresh_out="$(soif_freshness_run "$PROJECT_DIR" 2>/dev/null)" || _soif_fresh_rc=$?

if [ "$_soif_fresh_rc" -ne 0 ]; then
  printf '%s\n' "[freshness check unavailable]"
elif [ -n "$_soif_fresh_out" ]; then
  printf '%s\n' "$_soif_fresh_out"
fi

exit 0

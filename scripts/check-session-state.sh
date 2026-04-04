#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — CLAUDE.md Session Freshness Check
# https://github.com/kraulerson/solo-orchestrator
#
# Checks if CLAUDE.md has been updated recently relative to other commits.
# Warns if CLAUDE.md is stale (>N commits or >T hours behind HEAD).
#
# Usage: bash scripts/check-session-state.sh
# Environment:
#   SOIF_SESSION_COMMIT_THRESHOLD  — commits before warning (default: 5)
#   SOIF_SESSION_TIME_THRESHOLD    — seconds before warning (default: 86400 = 24h)
#   SOIF_STRICT_SESSION=true       — exit 1 instead of warning (default: false)
#
# Exit codes:
#   0 — CLAUDE.md is fresh, or no CLAUDE.md exists, or warn mode
#   1 — CLAUDE.md is stale (only when SOIF_STRICT_SESSION=true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/helpers.sh" ]; then
  source "$SCRIPT_DIR/lib/helpers.sh"
else
  print_warn() { echo "[WARN] $1"; }
  print_ok()   { echo "  [OK] $1"; }
fi

CLAUDE_MD="CLAUDE.md"
COMMIT_THRESHOLD="${SOIF_SESSION_COMMIT_THRESHOLD:-5}"
TIME_THRESHOLD="${SOIF_SESSION_TIME_THRESHOLD:-86400}"

# No CLAUDE.md = pre-framework project, skip silently
if [ ! -f "$CLAUDE_MD" ]; then
  exit 0
fi

# Check if CLAUDE.md has any git history
if ! git log -1 -- "$CLAUDE_MD" &>/dev/null; then
  exit 0  # CLAUDE.md exists but isn't tracked yet
fi

# Commits since CLAUDE.md was last modified
last_claude_commit=$(git log -1 --format="%H" -- "$CLAUDE_MD" 2>/dev/null || echo "")
if [ -z "$last_claude_commit" ]; then
  exit 0
fi

commits_since=$(git rev-list --count "$last_claude_commit"..HEAD 2>/dev/null || echo "0")

# Time since CLAUDE.md was last modified
last_claude_epoch=$(git log -1 --format="%ct" -- "$CLAUDE_MD" 2>/dev/null || echo "0")
head_epoch=$(git log -1 --format="%ct" HEAD 2>/dev/null || echo "0")
time_gap=$((head_epoch - last_claude_epoch))

stale=false
reason=""

if [ "$commits_since" -ge "$COMMIT_THRESHOLD" ]; then
  stale=true
  reason="$commits_since commits since last CLAUDE.md update (threshold: $COMMIT_THRESHOLD)"
elif [ "$time_gap" -ge "$TIME_THRESHOLD" ]; then
  stale=true
  hours=$((time_gap / 3600))
  threshold_hours=$((TIME_THRESHOLD / 3600))
  reason="${hours}h since last CLAUDE.md update (threshold: ${threshold_hours}h)"
fi

if [ "$stale" = true ]; then
  msg="CLAUDE.md may be stale: $reason. Update the session summary to reflect recent work."
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning::$msg"
  else
    print_warn "$msg"
  fi
  if [ "${SOIF_STRICT_SESSION:-false}" = "true" ]; then
    exit 1
  fi
else
  print_ok "CLAUDE.md is up to date ($commits_since commits since last update)"
fi

exit 0

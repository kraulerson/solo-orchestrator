#!/usr/bin/env bash
# scripts/escalate-to-user.sh — BL-029 documented bypass alternative.
#
# Wraps pending-approval.sh to give Claude a structured way to surface a
# decision to the user instead of proposing a bypass. Writes both the
# pending-approval.json sentinel (which the CDF stop-hook honors) and a
# row to bypass-audit.json with type='escalation' (per BL-030 spec § 6
# enum amendment, 2026-04-29).
#
# Usage:
#   escalate-to-user.sh \
#     --question "..." \
#     --option "A1: foo" --option "A2: bar" [--option "A3: baz"] \
#     --recommendation A2 \
#     [--rationale "..."]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bypass-audit.sh"

QUESTION=""
RECOMMENDATION=""
RATIONALE=""
OPTIONS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --question) QUESTION="${2:-}"; shift 2 ;;
    --recommendation) RECOMMENDATION="${2:-}"; shift 2 ;;
    --rationale) RATIONALE="${2:-}"; shift 2 ;;
    --option) OPTIONS+=("${2:-}"); shift 2 ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *)
      echo "[FAIL] unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

[ -z "$QUESTION" ] && { echo "[FAIL] --question is required" >&2; exit 2; }
[ "${#OPTIONS[@]}" -lt 2 ] && { echo "[FAIL] at least 2 --option entries required (CDF schema)" >&2; exit 2; }
[ -z "$RECOMMENDATION" ] && { echo "[FAIL] --recommendation is required" >&2; exit 2; }

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
[ -d "$PROJECT_ROOT/.claude" ] || { echo "[FAIL] .claude/ not found at $PROJECT_ROOT" >&2; exit 1; }

# Build options JSON array.
OPT_JSON=$(printf '%s\n' "${OPTIONS[@]}" | jq -R . | jq -s .)

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -n \
  --arg q "$QUESTION" \
  --argjson opts "$OPT_JSON" \
  --arg rec "$RECOMMENDATION" \
  --arg ts "$TS" \
  '{question: $q, options: $opts, recommendation: $rec, offered_at: $ts}' \
  > "$PROJECT_ROOT/.claude/pending-approval.json"

# Audit row — type='escalation' per Fix #2.
LEVEL=$(jq -r '.enforcement_level // "strict"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null || echo "strict")
ROW=$(jq -nc \
  --arg ts "$TS" \
  --arg q "$QUESTION" \
  --arg rec "$RECOMMENDATION" \
  --arg rat "$RATIONALE" \
  --arg lvl "$LEVEL" \
  --argjson opts "$OPT_JSON" \
  '{
    timestamp: $ts,
    session_id: null,
    type: "escalation",
    actor: "framework",
    enforcement_level_at_event: $lvl,
    details: {question: $q, options: $opts, recommendation: $rec, rationale: $rat},
    user_response: "PENDING",
    final_outcome: "escalated"
  }')
bypass_audit_append "$PROJECT_ROOT" "$ROW" || true

echo "[OK] escalation written to .claude/pending-approval.json (and audit log)"

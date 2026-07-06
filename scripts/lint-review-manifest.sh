#!/usr/bin/env bash
# scripts/lint-review-manifest.sh — BL-073 schema linter for the
# Phase 3 → 4 review manifest (docs/eval-results/review-manifest.json).
#
# THE CONTRACT
#   The review manifest records which of the six framework reviewers ran
#   against a project before the Phase 3 → 4 gate. check-phase-gate.sh's
#   track-aware review gate (BL-073) reads the `.reviews[]` array and the
#   per-entry `reviewer` + `status` fields to decide whether the Security
#   and Red Team reviews (the mandatory subset for track=standard/full)
#   are complete. A malformed manifest silently defeats that gate — a
#   missing `status`, a typo'd enum, or a non-array `.reviews` would let
#   an incomplete review set read as "complete". This linter is the
#   merge-time / CI backstop that pins the schema.
#
#   Top level MUST be a JSON object with a `reviews` array. Each entry:
#     {
#       "reviewer":  "<non-empty string>",          # REQUIRED (slug or persona)
#       "status":    "complete" | "skipped" | "failed",  # REQUIRED
#       "artifact":  "<non-empty string>",           # REQUIRED (path to report)
#       "signed_by": "<non-empty string>",           # OPTIONAL (validated if present)
#       "date":      "YYYY-MM-DD"                     # OPTIONAL (validated if present)
#     }
#   Extra keys (sha256, commit, timestamp, module, …) are allowed and
#   ignored — the generator (evaluation-prompts/Projects/run-reviews.sh)
#   carries provenance fields the gate does not read.
#
# WHAT IT DOES NOT DO
#   It does NOT enforce that any particular reviewer is present, or that
#   the set is complete — that is the phase gate's track-aware job. This
#   linter only validates the SHAPE of whatever manifest exists. When no
#   manifest is present there is nothing to lint (exit 0); an absent
#   manifest is a gate concern, not a schema concern.
#
# USAGE
#   bash scripts/lint-review-manifest.sh                 # lint the default path
#   bash scripts/lint-review-manifest.sh --file <path>   # lint a specific file
#   bash scripts/lint-review-manifest.sh --list          # show the parsed roster
#   bash scripts/lint-review-manifest.sh --help
#
# EXIT CODES
#   0 — schema valid (or no manifest present / jq unavailable → nothing to do)
#   1 — one or more schema violations
#   2 — invocation error (bad flag / missing --file value)

set -uo pipefail

DEFAULT_MANIFEST="docs/eval-results/review-manifest.json"
MANIFEST_FILE="$DEFAULT_MANIFEST"
DO_LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      if [ $# -lt 2 ]; then
        echo "[FAIL] --file requires a path argument" >&2
        exit 2
      fi
      MANIFEST_FILE="$2"
      shift 2
      ;;
    --file=*)
      MANIFEST_FILE="${1#--file=}"
      shift
      ;;
    --list)
      DO_LIST=1
      shift
      ;;
    --help|-h)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[FAIL] Unknown argument: '$1' (try --help)" >&2
      exit 2
      ;;
  esac
done

# No manifest → nothing to lint. Absence is enforced by the phase gate,
# not by this schema linter.
if [ ! -f "$MANIFEST_FILE" ]; then
  echo "[OK] lint-review-manifest: no manifest at '$MANIFEST_FILE' — nothing to lint."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[SKIP] lint-review-manifest: jq not available — cannot validate '$MANIFEST_FILE'."
  exit 0
fi

# Parse-level validation first: catch invalid JSON before schema checks.
if ! jq empty "$MANIFEST_FILE" >/dev/null 2>&1; then
  echo "[FAIL] lint-review-manifest: '$MANIFEST_FILE' is not valid JSON."
  exit 1
fi

if [ "$DO_LIST" -eq 1 ]; then
  echo "Review roster in $MANIFEST_FILE:"
  jq -r '
    if (.reviews | type) == "array"
    then (.reviews[] | "  - reviewer=\(.reviewer // "(none)")  status=\(.status // "(none)")  artifact=\(.artifact // .file // "(none)")")
    else "  (.reviews is not an array)"
    end
  ' "$MANIFEST_FILE" 2>/dev/null || echo "  (unable to enumerate)"
  echo ""
fi

# Schema validation: emit one line per violation.
violations=$(jq -r '
  def v($i; $m): "  [x] reviews[\($i)]: \($m)";
  if (type != "object") then "  [x] top-level JSON is not an object"
  elif ((has("reviews")) | not) then "  [x] missing required top-level key \"reviews\""
  elif ((.reviews | type) != "array") then "  [x] \"reviews\" must be an array"
  else
    ( .reviews
      | to_entries[]
      | .key as $i
      | .value as $e
      | if (($e | type) != "object") then v($i; "entry is not a JSON object")
        else
          ( (if (($e | has("reviewer")) and (($e.reviewer | type) == "string") and (($e.reviewer | length) > 0))
             then empty else v($i; "reviewer must be a non-empty string") end),
            (if (($e | has("status")) and ($e.status == "complete" or $e.status == "skipped" or $e.status == "failed"))
             then empty else v($i; "status must be one of complete|skipped|failed") end),
            (if (($e | has("artifact")) and (($e.artifact | type) == "string") and (($e.artifact | length) > 0))
             then empty else v($i; "artifact must be a non-empty string") end),
            (if (($e | has("date")) and ((($e.date | type) != "string") or (($e.date | test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$")) | not)))
             then v($i; "date, if present, must be YYYY-MM-DD") else empty end),
            (if (($e | has("signed_by")) and ((($e.signed_by | type) != "string") or (($e.signed_by | length) == 0)))
             then v($i; "signed_by, if present, must be a non-empty string") else empty end)
          )
        end
    )
  end
' "$MANIFEST_FILE" 2>/dev/null || echo "  [x] jq failed to evaluate the manifest schema")

if [ -n "$violations" ]; then
  echo "[FAIL] lint-review-manifest: schema violation(s) in $MANIFEST_FILE:"
  echo "$violations"
  echo ""
  echo "  Expected: { \"reviews\": [ { \"reviewer\": \"security\", \"status\": \"complete\", \"artifact\": \"docs/eval-results/security-review-v1.md\", \"signed_by\": \"…\", \"date\": \"YYYY-MM-DD\" }, … ] }"
  exit 1
fi

echo "[OK] lint-review-manifest: $MANIFEST_FILE schema is valid."
exit 0

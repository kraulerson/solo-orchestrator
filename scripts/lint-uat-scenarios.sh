#!/usr/bin/env bash
# scripts/lint-uat-scenarios.sh — pattern-based linter for populated UAT templates.
# Usage: scripts/lint-uat-scenarios.sh <populated-html-file>
# Exit codes: 0 = clean; 1 = quality violations; 2 = structural failure.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: scripts/lint-uat-scenarios.sh <populated-html-file>" >&2
  exit 2
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "lint-uat-scenarios.sh: $FILE: No such file or directory" >&2
  exit 2
fi

# --- File-level check 1: unreplaced __FOO__ placeholders ---
PLACEHOLDER_LINES=$(grep -n '__[A-Z][A-Z_]*__' "$FILE" || true)
if [ -n "$PLACEHOLDER_LINES" ]; then
  COUNT=$(echo "$PLACEHOLDER_LINES" | wc -l | tr -d ' ')
  echo "$PLACEHOLDER_LINES" | while IFS= read -r line; do
    LINENUM="${line%%:*}"
    CONTEXT=$(echo "$line" | sed 's/^[0-9]*://' | head -c 80)
    echo "file-level: unreplaced placeholder — line $LINENUM: $CONTEXT" >&2
  done
  echo "$COUNT violations found. Revise the flagged scenarios and re-run the linter."
  exit 1
fi

# --- Extract scenarios JSON block between "const scenarios = " and "];" ---
SCENARIOS_JSON=$(awk '
  /const scenarios *= *\[/ {
    flag=1
    sub(/.*const scenarios *= */, "")
  }
  flag {
    print
    if (/\];[[:space:]]*$/) {
      flag=0
      exit
    }
  }
' "$FILE")

if [ -z "$SCENARIOS_JSON" ]; then
  echo "lint-uat-scenarios.sh: $FILE: No scenarios block found — is the file populated? (expected 'const scenarios = [...]')" >&2
  exit 2
fi

# Strip trailing ; so jq can parse
SCENARIOS_JSON="${SCENARIOS_JSON%;}"

# Validate JSON
if ! JQ_OUT=$(echo "$SCENARIOS_JSON" | jq . 2>&1); then
  JQ_ERR=$(echo "$JQ_OUT" | head -1)
  echo "lint-uat-scenarios.sh: $FILE: JSON parse failed: $JQ_ERR" >&2
  exit 2
fi

VIOLATIONS=0
VIOLATION_LINES=""

# --- File-level check 2: duplicate scenario ids ---
DUP_IDS=$(echo "$SCENARIOS_JSON" | jq -r '[.[] | .id] | group_by(.) | map(select(length > 1) | .[0]) | .[]' 2>/dev/null || true)
if [ -n "$DUP_IDS" ]; then
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    VIOLATION_LINES="${VIOLATION_LINES}file-level: duplicate scenario id — id $id appears more than once"$'\n'
    VIOLATIONS=$((VIOLATIONS + 1))
  done <<< "$DUP_IDS"
fi

# --- Per-scenario checks ---
NUM_SCENARIOS=$(echo "$SCENARIOS_JSON" | jq 'length')

for i in $(seq 0 $((NUM_SCENARIOS - 1))); do
  ID=$(echo "$SCENARIOS_JSON" | jq -r ".[$i].id")
  EXPECTED=$(echo "$SCENARIOS_JSON" | jq -r ".[$i].expected")
  STEPS=$(echo "$SCENARIOS_JSON" | jq -r ".[$i].steps")

  # Check 1: expected length >= 60
  EXP_LEN=${#EXPECTED}
  if [ "$EXP_LEN" -lt 60 ]; then
    EXCERPT="${EXPECTED:0:50}"
    VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: expected too short — \"$EXCERPT\" ($EXP_LEN chars, min 60)"$'\n'
    VIOLATIONS=$((VIOLATIONS + 1))
  fi

  # Check 2: expected not a banned vague phrase (case-insensitive, trimmed)
  EXPECTED_NORM=$(echo "$EXPECTED" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$EXPECTED_NORM" in
    "works"|"succeeds"|"passes"|"no errors"|"builds successfully"|"completes")
      VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: banned vague phrase — \"$EXPECTED\""$'\n'
      VIOLATIONS=$((VIOLATIONS + 1))
      ;;
  esac

  # Check 3: steps contains banned cross-refs (case-insensitive)
  STEPS_LOWER=$(echo "$STEPS" | tr '[:upper:]' '[:lower:]')
  for BANNED in "command from scenario" "see above" "as before" "like scenario" "as in scenario"; do
    if [[ "$STEPS_LOWER" == *"$BANNED"* ]]; then
      VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: banned cross-ref — \"...$BANNED...\""$'\n'
      VIOLATIONS=$((VIOLATIONS + 1))
      break
    fi
  done

  # Check 4: steps first line starts with state-restatement keyword
  FIRST_LINE=$(echo "$STEPS" | head -1)
  HAS_RESTATEMENT=false
  for KW in "You are" "cd " "Setup:" "Before starting" "Preconditions:"; do
    KW_LOWER=$(echo "$KW" | tr '[:upper:]' '[:lower:]')
    FL_LOWER=$(echo "$FIRST_LINE" | tr '[:upper:]' '[:lower:]')
    if [[ "$FL_LOWER" == "$KW_LOWER"* ]]; then
      HAS_RESTATEMENT=true
      break
    fi
  done
  if [ "$HAS_RESTATEMENT" = false ]; then
    EXCERPT="${FIRST_LINE:0:60}"
    VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: steps must open with state-restatement — first line: \"$EXCERPT\""$'\n'
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  printf "%s" "$VIOLATION_LINES" >&2
  echo "$VIOLATIONS violations found. Revise the flagged scenarios and re-run the linter."
  exit 1
fi

echo "All $NUM_SCENARIOS scenarios clean."
exit 0

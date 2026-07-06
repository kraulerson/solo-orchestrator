#!/usr/bin/env bash
# tests/test-bypass-audit-schema.sh — BL-030 audit-log schema cross-pathway sanity.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# init.sh refuses to run from inside the framework repo.
cd /tmp

TMP=$(mktemp -d); PROJ="$TMP/p"
bash "$REPO_ROOT/init.sh" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
  --platform web --language typescript --track light --deployment personal \
  >/dev/null 2>&1

# T1: init wrote a row whose schema satisfies the minimum contract
# (type, actor, timestamp, enforcement_level_at_event).
if jq -e '.[0] | (.type and .actor and .timestamp and .enforcement_level_at_event)' \
   "$PROJ/.claude/bypass-audit.json" >/dev/null 2>&1; then
  pass "T1: init row has type/actor/timestamp/enforcement_level_at_event"
else
  fail_ "T1" "init row malformed"
fi

# T2: detector writes a valid out_of_band_commit row.
( cd "$PROJ" && echo u > u && git add u && git commit -qm "user terminal commit" )
bash "$PROJ/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1
if jq -e '[.[] | select(.type=="out_of_band_commit")] | length >= 1' \
   "$PROJ/.claude/bypass-audit.json" >/dev/null 2>&1; then
  pass "T2: detector wrote out_of_band_commit row"
else
  fail_ "T2" "detector did not write row"
fi

# T3: actor enum is one of the documented values across every row.
ACTORS=$(jq -r '[.[].actor] | unique | .[]' "$PROJ/.claude/bypass-audit.json")
ALL_OK=1
for a in $ACTORS; do
  case "$a" in
    claude|user_terminal|user_terminal_inferred|framework) ;;
    *) ALL_OK=0 ;;
  esac
done
if [ "$ALL_OK" = "1" ]; then pass "T3: actor enum valid"; else fail_ "T3" "unknown actor in $ACTORS"; fi

rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

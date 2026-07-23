#!/usr/bin/env bash
# tests/test-bl168-tm-table-sigpipe.sh — BL-168 (Dogfood-4 S4 F-DF4-015).
#
# _p3_tm_has_table used a two-stage `grep '|' | grep -Eq TM-...` pipeline
# under the driver's `set -uo pipefail`: the downstream -q exits on its
# first match and closes the pipe; on tables whose `|`-line output exceeds
# one grep stdout buffer the upstream grep takes SIGPIPE (141) mid-write,
# pipefail surfaces the 141, and a PRESENT table reads as "absent" — the
# intermittent un-attested SKIP that blocked the CI gate on identical
# trees (~11% of live attempts; run 29949089493 attempt 7, run
# 29951076488 attempt 1). GNU grep's ~4 KB pipe buffering makes even the
# real 8.8 KB bible racy on Linux; BSD grep single-writes small files,
# which is why it never reproduced locally until the fixture exceeds the
# buffer (WP-2 sweep: 109 KB -> 500/500 deterministic).
#
# This suite exercises the SHIPPED function bytes (extracted from the
# driver, evaluated under the driver's own pipefail discipline — the
# fixture-hides-gap lesson: test the real artifact, not a copy):
#   T1  big table (TM row first + >200 KB of filler `|` lines) -> PRESENT
#       (rc=0). RED on the two-stage pipeline (rc=141), GREEN on the fix.
#   T2  small real-shaped table -> PRESENT (semantic pin, single write)
#   T3  TM id in prose, no table row -> ABSENT
#   T4  table rows without any TM id -> ABSENT
#   T0  vacuity guard: the extraction actually found the function.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Extract the SHIPPED function bytes from the driver ──────────────────────
FUNC_SRC=$(sed -n '/^_p3_tm_has_table() {/,/^}/p' "$DRIVER")

echo "T0: extraction vacuity guard"
if [ -n "$FUNC_SRC" ] && echo "$FUNC_SRC" | grep -q 'grep'; then
  pass "T0: _p3_tm_has_table extracted from the driver ($(echo "$FUNC_SRC" | wc -l | tr -d ' ') lines)"
else
  fail_ "T0" "could not extract _p3_tm_has_table from $DRIVER — suite is vacuous"
  echo ""
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi

# Run the shipped bytes in a fresh bash with the driver's own strictness.
# rc is the function's return code.
run_func() {
  # $1 = fixture file
  bash -c 'set -uo pipefail
'"$FUNC_SRC"'
_p3_tm_has_table "$1"' _ "$1"
}

# ── Fixtures ────────────────────────────────────────────────────────────────
# T1: TM row FIRST, then enough filler `|` lines to exceed any grep stdout
# buffer (>200 KB) — forces multiple upstream writes after the downstream
# -q has already matched and closed the pipe.
BIG="$TMP/big-bible.md"
{
  echo "## 4. Threat Model"
  echo "| ID | Threat | Mitigation |"
  echo "|---|---|---|"
  echo "| TM-001 | Silent degradation | Loud logging |"
  i=0
  while [ "$i" -lt 1600 ]; do
    echo "| filler-row-$i | padding padding padding padding padding padding padding padding padding padding padding padding | more padding to push each line well past one hundred and twenty bytes of pipe-line output |"
    i=$((i + 1))
  done
} > "$BIG"

SMALL="$TMP/small-bible.md"
{
  echo "## 4. Threat Model"
  echo "| ID | Threat | Mitigation |"
  echo "|---|---|---|"
  echo "| TM-001 | Silent degradation | Loud logging |"
  echo "| TM-002 | Injection | Text-node rendering |"
} > "$SMALL"

PROSE="$TMP/prose-bible.md"
{
  echo "## 4. Threat Model"
  echo "We considered TM-001 and TM-002 in prose but built no table yet."
} > "$PROSE"

NOTM="$TMP/notm-bible.md"
{
  echo "## 4. Threat Model"
  echo "| ID | Threat | Mitigation |"
  echo "|---|---|---|"
  echo "| placeholder | none | none |"
} > "$NOTM"

# ── Cases ───────────────────────────────────────────────────────────────────
echo "T1: big table (>200 KB pipe-line output, TM row first) is PRESENT under pipefail"
rc=0; run_func "$BIG" || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T1: rc=0 on the big table"
else
  fail_ "T1" "expected rc=0, got rc=$rc (141 = the BL-168 SIGPIPE race) on $(wc -c < "$BIG" | tr -d ' ') bytes"
fi

echo "T2: small real-shaped table is PRESENT"
rc=0; run_func "$SMALL" || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T2: rc=0 on the small table"
else
  fail_ "T2" "expected rc=0, got rc=$rc"
fi

echo "T3: TM ids in prose without a table row are ABSENT"
rc=0; run_func "$PROSE" || rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T3: rc=$rc (absent) on prose-only TM mentions"
else
  fail_ "T3" "expected rc!=0, got rc=0 — prose TM mention must not satisfy the table check"
fi

echo "T4: table rows without TM ids are ABSENT"
rc=0; run_func "$NOTM" || rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T4: rc=$rc (absent) on TM-less table"
else
  fail_ "T4" "expected rc!=0, got rc=0 — a TM-less table must not satisfy the check"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

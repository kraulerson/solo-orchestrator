#!/usr/bin/env bash
# tests/test-out-of-band-detector.sh — BL-030 light/strict-mode detector tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETECTOR="$REPO_ROOT/scripts/detect-out-of-band-commits.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  ( cd "$TMP"
    git init -q
    git config user.email "t@t.l"
    git config user.name "t"
    echo init > i.txt && git add i.txt && git commit -qm "init"
  )
  HEAD0=$(cd "$TMP" && git rev-parse HEAD)
  echo "$HEAD0" > "$TMP/.claude/last-checked-commit.txt"
  : > "$TMP/.claude/claude-commits.jsonl"
  : > "$TMP/.claude/bypass-audit.json"  # BL-029 prerequisite — initialized as empty array elsewhere; here we simulate
  echo "[]" > "$TMP/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

write_manifest() {
  local proj="$1" level="$2"
  cat > "$proj/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"$level"}
EOF
}

# T1: enforcement_level=no → no-op exit, no rows written.
echo "T1: detector is a no-op when enforcement_level=no"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T1" "detector missing (RED)"
else
  write_manifest "$TMP" "no"
  ( cd "$TMP" && echo extra > e.txt && git add e.txt && git commit -qm "user terminal commit" )
  bash "$DETECTOR" "$TMP" >/dev/null 2>&1 || true
  rows=$(jq 'length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "0" ]; then pass "T1"; else fail_ "T1" "expected 0 rows, got $rows"; fi
fi
teardown

# T2: light mode + a Claude-recorded commit + a user-terminal commit → 1 row for the terminal commit only.
echo "T2: light mode flags only commits not in claude-commits.jsonl"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T2" "detector missing"
else
  write_manifest "$TMP" "light"
  ( cd "$TMP"
    echo claude > c.txt && git add c.txt && git commit -qm "claude commit"
    SHA1=$(git rev-parse HEAD)
    jq -nc --arg sha "$SHA1" --arg ts "2026-04-28T00:00:00Z" --arg sid "s" '{sha:$sha,timestamp:$ts,session_id:$sid,gate:"passed"}' \
      >> "$TMP/.claude/claude-commits.jsonl"
    echo user > u.txt && git add u.txt && git commit -qm "user terminal commit"
  )
  bash "$DETECTOR" "$TMP" >/dev/null 2>&1
  rows=$(jq 'length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then
    sub=$(jq -r '.[0].details.commit_subject' "$TMP/.claude/bypass-audit.json")
    if [ "$sub" = "user terminal commit" ]; then pass "T2"; else fail_ "T2" "wrong subject '$sub'"; fi
  else
    fail_ "T2" "expected 1 row, got $rows"
  fi
fi
teardown

# T3: strict mode also runs the detector — for --no-verify capture.
echo "T3: strict mode detector still flags out-of-band commits"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T3" "detector missing"
else
  write_manifest "$TMP" "strict"
  ( cd "$TMP" && echo bypass > b.txt && git add b.txt && git commit -qm "no-verify bypass" )
  bash "$DETECTOR" "$TMP" >/dev/null 2>&1
  rows=$(jq 'length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T3"; else fail_ "T3" "expected 1 row, got $rows"; fi
fi
teardown

# T4: derivative commits (Merge / Revert) are filtered.
echo "T4: derivative commits are skipped"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T4" "detector missing"
else
  write_manifest "$TMP" "light"
  ( cd "$TMP"
    git checkout -qb feat
    echo a > a.txt && git add a.txt && git commit -qm "feat work"
    git checkout -q main 2>/dev/null || git checkout -q master
    git merge --no-ff -qm "Merge branch 'feat'" feat
  )
  bash "$DETECTOR" "$TMP" >/dev/null 2>&1
  # Should record only the feat commit, not the merge.
  rows=$(jq 'length' "$TMP/.claude/bypass-audit.json")
  subjects=$(jq -r '.[].details.commit_subject' "$TMP/.claude/bypass-audit.json" | sort | tr '\n' ',')
  if [ "$rows" = "1" ] && [ "$subjects" = "feat work," ]; then pass "T4"; else fail_ "T4" "got rows=$rows subjects=$subjects"; fi
fi
teardown

# T5: detector updates last-checked-commit.txt to current HEAD.
echo "T5: detector advances last-checked-commit.txt"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T5" "detector missing"
else
  write_manifest "$TMP" "light"
  ( cd "$TMP" && echo z > z.txt && git add z.txt && git commit -qm "user z" )
  EXPECTED=$(cd "$TMP" && git rev-parse HEAD)
  bash "$DETECTOR" "$TMP" >/dev/null 2>&1
  ACTUAL=$(cat "$TMP/.claude/last-checked-commit.txt")
  if [ "$ACTUAL" = "$EXPECTED" ]; then pass "T5"; else fail_ "T5" "expected $EXPECTED got $ACTUAL"; fi
fi
teardown

# T6: detector prints session-start banner when rows are written.
echo "T6: detector prints banner when out-of-band commits found"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T6" "detector missing"
else
  write_manifest "$TMP" "light"
  ( cd "$TMP" && echo y > y.txt && git add y.txt && git commit -qm "user y" )
  out=$(bash "$DETECTOR" "$TMP" 2>&1 || true)
  if echo "$out" | grep -q "user-terminal commit"; then pass "T6"; else fail_ "T6" "no banner in output: $out"; fi
fi
teardown

# T7: detector handles empty range (no commits since last check) silently.
echo "T7: detector is silent when no new commits exist"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T7" "detector missing"
else
  write_manifest "$TMP" "light"
  out=$(bash "$DETECTOR" "$TMP" 2>&1 || true)
  rows=$(jq 'length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "0" ] && ! echo "$out" | grep -q "user-terminal commit"; then pass "T7"; else fail_ "T7" "rows=$rows out=$out"; fi
fi
teardown

# T8: detector writes a detector_error row on jq failure (corrupt ledger).
echo "T8: detector records detector_error on corrupt claude-commits.jsonl"
setup
if [ ! -f "$DETECTOR" ]; then
  fail_ "T8" "detector missing"
else
  write_manifest "$TMP" "light"
  echo "this is not json" > "$TMP/.claude/claude-commits.jsonl"
  ( cd "$TMP" && echo q > q.txt && git add q.txt && git commit -qm "user q" )
  bash "$DETECTOR" "$TMP" >/dev/null 2>&1 || true
  err_rows=$(jq '[.[] | select(.type == "detector_error")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$err_rows" -ge "1" ]; then pass "T8"; else fail_ "T8" "expected detector_error row, got $err_rows"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

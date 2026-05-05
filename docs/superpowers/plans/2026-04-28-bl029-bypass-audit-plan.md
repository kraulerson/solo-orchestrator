# BL-029 Bypass Audit-Log Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude's bypass-suggestion behavior auditable by detecting bypass-shaped language in Claude output, writing structured rows to `.claude/bypass-audit.json`, requiring a non-trivial confirmation phrase before any bypass can be accepted, and shipping `escalate-to-user` as a documented alternative to bypass-proposing.

**Architecture:** A flock-protected library establishes the canonical row schema and append helpers. A PostToolUse + Stop hook scans Claude output against an extensible pattern table and writes `claude_bypass_proposal` rows BEFORE the user replies. When a row is written, a pending-approval sentinel forces the user to type a specific confirmation phrase to accept the bypass — generic "OK" / "yes" / "proceed" no longer count. A separate `escalate-to-user` CLI wraps `pending-approval.sh` to give Claude a structured alternative to suggesting `--no-verify`. A second Stop-hook check refuses to recommend specific known-bad patterns (synthetic Build Loop steps without `tests_verified_failing`).

**Tech Stack:** bash, jq, `flock` (advisory file locking), existing `scripts/pending-approval.sh` (BL-015), existing CDF stop-hook contract (`pending-approval.json`).

---

## Source spec

- **Backlog entry:** `solo-orchestrator-backlog.md:695-722` (BL-029)
- **Schema (canonical):** `docs/superpowers/specs/2026-04-28-bl030-enforcement-model-design.md` § 6
- **Calibration agent-5 detailed spec:** `Reports/uat-2026-04-27-calibration/results/agent-5.json` — gives full pattern list and rationale for sentinel-vs-block design choices.

## Sequencing

This plan ships before the BL-030 plan executes. Once shipped, the existing BL-030 plan at `docs/superpowers/plans/2026-04-28-bl030-enforcement-model-plan.md` should be edited to replace its inline jq-append calls (Tasks 3, 4, 7, 8) with calls to the `bypass_audit_append` library function this plan creates. The BL-030 plan declares BL-029 as a prerequisite for that reason.

## Working directory

All commands assume CWD = `/Users/karl/Documents/Claude Projects/solo-orchestrator`.

---

## Task 1: `scripts/lib/bypass-audit.sh` — schema + flock-protected writer library

Foundation. Defines `.claude/bypass-audit.json` row schema and provides safe-append. Used by every BL-029 writer (and, post-BL-030-edit, every BL-030 writer too).

**Files:**
- Create: `scripts/lib/bypass-audit.sh`
- Test: `tests/test-bypass-audit-lib.sh`

- [ ] **Step 1.1: Write the failing test**

Create `tests/test-bypass-audit-lib.sh`:

```bash
#!/usr/bin/env bash
# tests/test-bypass-audit-lib.sh — BL-029 audit-log library tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-audit.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_lib_or_skip() {
  if [ ! -f "$LIB" ]; then
    fail_ "$1" "scripts/lib/bypass-audit.sh missing (RED)"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$LIB"
}

setup() { TMP=$(mktemp -d); mkdir -p "$TMP/.claude"; }
teardown() { rm -rf "$TMP"; }

# T1: bypass_audit_init creates an empty array file.
echo "T1: bypass_audit_init creates [] file"
setup
setup_lib_or_skip "T1" && {
  bypass_audit_init "$TMP"
  if [ -f "$TMP/.claude/bypass-audit.json" ] && [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "0" ]; then
    pass "T1"
  else
    fail_ "T1" "file missing or not empty array"
  fi
}
teardown

# T2: bypass_audit_init is idempotent (does not clobber existing rows).
echo "T2: bypass_audit_init is idempotent"
setup
setup_lib_or_skip "T2" && {
  echo '[{"type":"sentinel","actor":"framework","timestamp":"x","enforcement_level_at_event":"strict","details":{},"user_response":"n/a","final_outcome":"recorded_only"}]' > "$TMP/.claude/bypass-audit.json"
  bypass_audit_init "$TMP"
  if [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "1" ]; then pass "T2"; else fail_ "T2" "init clobbered"; fi
}
teardown

# T3: bypass_audit_append appends a single row.
echo "T3: bypass_audit_append appends one row"
setup
setup_lib_or_skip "T3" && {
  bypass_audit_init "$TMP"
  bypass_audit_append "$TMP" '{"type":"claude_bypass_proposal","actor":"claude","timestamp":"2026-04-28T00:00:00Z","enforcement_level_at_event":"strict","details":{"pattern":"--no-verify"},"user_response":"PENDING","final_outcome":"recorded_only"}'
  if [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "1" ]; then pass "T3"; else fail_ "T3" "append failed"; fi
}
teardown

# T4: bypass_audit_append rejects malformed JSON.
echo "T4: bypass_audit_append rejects non-JSON"
setup
setup_lib_or_skip "T4" && {
  bypass_audit_init "$TMP"
  if bypass_audit_append "$TMP" 'this is not json' 2>/dev/null; then
    fail_ "T4" "expected non-zero return"
  else
    if [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "0" ]; then pass "T4"; else fail_ "T4" "row leaked into file"; fi
  fi
}
teardown

# T5: concurrent appends (two parallel processes) both land — flock works.
echo "T5: concurrent appends both land"
setup
setup_lib_or_skip "T5" && {
  bypass_audit_init "$TMP"
  ROW='{"type":"claude_bypass_proposal","actor":"claude","timestamp":"2026-04-28T00:00:00Z","enforcement_level_at_event":"strict","details":{"i":0},"user_response":"PENDING","final_outcome":"recorded_only"}'
  for i in $(seq 1 10); do
    ( bypass_audit_append "$TMP" "$ROW" ) &
  done
  wait
  count=$(jq 'length' "$TMP/.claude/bypass-audit.json")
  if [ "$count" = "10" ]; then pass "T5"; else fail_ "T5" "expected 10, got $count"; fi
}
teardown

# T6: bypass_audit_count_pending returns the number of rows whose user_response is "PENDING".
echo "T6: bypass_audit_count_pending counts PENDING rows"
setup
setup_lib_or_skip "T6" && {
  bypass_audit_init "$TMP"
  bypass_audit_append "$TMP" '{"type":"claude_bypass_proposal","actor":"claude","timestamp":"x","enforcement_level_at_event":"strict","details":{},"user_response":"PENDING","final_outcome":"recorded_only"}'
  bypass_audit_append "$TMP" '{"type":"claude_bypass_proposal","actor":"claude","timestamp":"x","enforcement_level_at_event":"strict","details":{},"user_response":"accepted","final_outcome":"committed"}'
  n=$(bypass_audit_count_pending "$TMP")
  if [ "$n" = "1" ]; then pass "T6"; else fail_ "T6" "got $n"; fi
}
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 1.2: Run, verify failures**

```bash
bash tests/test-bypass-audit-lib.sh
```
Expected: 6 FAIL.

- [ ] **Step 1.3: Implement the library**

Create `scripts/lib/bypass-audit.sh`:

```bash
# scripts/lib/bypass-audit.sh — BL-029 audit-log writer library.
#
# Canonical schema for .claude/bypass-audit.json. Provides flock-protected
# append so concurrent writers (PostToolUse hooks, Stop hooks, SessionStart
# detector, init/reconfigure recorders) don't race on the file.
#
# Schema per row:
#   {
#     "timestamp":                 ISO-8601 UTC,
#     "session_id":                string-or-null,
#     "type":                      "claude_bypass_proposal" | "terminal_commit_blocked" |
#                                  "terminal_commit_passed" | "out_of_band_commit" |
#                                  "enforcement_level_set" | "detector_error",
#     "actor":                     "claude" | "user_terminal" | "user_terminal_inferred" | "framework",
#     "enforcement_level_at_event":"no" | "light" | "strict" | "n/a",
#     "details":                   { type-specific },
#     "user_response":             "PENDING" | "accepted" | "declined" | "n/a",
#     "final_outcome":             "committed" | "bypassed" | "escalated" | "abandoned" | "recorded_only" | "n/a"
#   }

# shellcheck shell=bash

# bypass_audit_init <project_root>
# Creates .claude/bypass-audit.json as an empty array if it does not already
# exist. Idempotent — preserves existing rows.
bypass_audit_init() {
  local project_root="${1:-.}"
  local file="$project_root/.claude/bypass-audit.json"
  [ -f "$file" ] && return 0
  mkdir -p "$project_root/.claude"
  echo "[]" > "$file"
}

# bypass_audit_append <project_root> <row_json>
# Validates row_json is a JSON object, then appends to the audit array
# under flock. Returns 0 on success, 1 on validation or write failure.
bypass_audit_append() {
  local project_root="${1:-.}"
  local row="${2:-}"
  local file="$project_root/.claude/bypass-audit.json"

  if [ -z "$row" ]; then
    echo "[FAIL] bypass_audit_append: empty row" >&2
    return 1
  fi
  if ! echo "$row" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "[FAIL] bypass_audit_append: row is not a JSON object" >&2
    return 1
  fi

  bypass_audit_init "$project_root"

  local lock="$file.lock"
  local tmp
  tmp=$(mktemp)
  (
    flock -w 5 9 || { echo "[FAIL] bypass_audit_append: lock timeout" >&2; exit 1; }
    if jq --argjson r "$row" '. + [$r]' "$file" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$file"
    else
      rm -f "$tmp"
      echo "[FAIL] bypass_audit_append: jq failed" >&2
      exit 1
    fi
  ) 9>"$lock"
}

# bypass_audit_count_pending <project_root>
# Echoes the number of rows whose user_response is "PENDING".
bypass_audit_count_pending() {
  local project_root="${1:-.}"
  local file="$project_root/.claude/bypass-audit.json"
  [ -f "$file" ] || { echo 0; return 0; }
  jq '[.[] | select(.user_response == "PENDING")] | length' "$file" 2>/dev/null || echo 0
}
```

- [ ] **Step 1.4: Run, verify pass**

```bash
bash tests/test-bypass-audit-lib.sh
```
Expected: `Results: 6 passed, 0 failed`. (T5 may be flaky on slow systems if `flock` isn't available; verify `command -v flock` first.)

- [ ] **Step 1.5: Commit**

```bash
git add scripts/lib/bypass-audit.sh tests/test-bypass-audit-lib.sh
git commit -m "feat(bl-029): bypass-audit library — schema + flock-protected append"
```

---

## Task 2: `scripts/lib/bypass-patterns.sh` — extensible pattern table

The detector looks for bypass-shaped language in Claude's output. Patterns ship as a sourceable constants table so new patterns can be added without touching the detector.

**Files:**
- Create: `scripts/lib/bypass-patterns.sh`
- Test: `tests/test-bypass-patterns.sh`

- [ ] **Step 2.1: Write the failing test**

Create `tests/test-bypass-patterns.sh`:

```bash
#!/usr/bin/env bash
# tests/test-bypass-patterns.sh — BL-029 pattern table tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-patterns.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if [ ! -f "$LIB" ]; then
  fail_ "missing-lib" "RED expected"
else
  # shellcheck disable=SC1090
  source "$LIB"

  # T1: --no-verify is detected.
  if scan_bypass_patterns "you can run git commit --no-verify" >/dev/null; then pass "T1: --no-verify"; else fail_ "T1" "no match"; fi

  # T2: SOIF_FORCE_STEP= is detected.
  if scan_bypass_patterns "set SOIF_FORCE_STEP=build_loop:tests_written" >/dev/null; then pass "T2: SOIF_FORCE_STEP="; else fail_ "T2" "no match"; fi

  # T3: 'run this in your terminal' phrase is detected.
  if scan_bypass_patterns "alternatively, run this in your own terminal" >/dev/null; then pass "T3: terminal phrase"; else fail_ "T3" "no match"; fi

  # T4: synthetic Build Loop step proposal without prior tests_verified_failing is detected.
  if scan_bypass_patterns "I'll mark step build_loop:tests_verified_failing complete and move on" >/dev/null; then pass "T4: fake-loop"; else fail_ "T4" "no match"; fi

  # T5: git push --force-with-lease is detected.
  if scan_bypass_patterns "we can git push --force-with-lease to fix it" >/dev/null; then pass "T5: force-push"; else fail_ "T5" "no match"; fi

  # T6: ordinary text does NOT trigger.
  if scan_bypass_patterns "let's commit and push to origin" >/dev/null; then fail_ "T6" "false positive"; else pass "T6: clean text"; fi

  # T7: scan_bypass_patterns echoes the matched pattern name on hit.
  out=$(scan_bypass_patterns "I'll use --no-verify here")
  if [ "$out" = "no_verify" ]; then pass "T7: pattern name"; else fail_ "T7" "got '$out'"; fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2.2: Run, verify failure**

```bash
bash tests/test-bypass-patterns.sh
```
Expected: 7 FAIL (lib missing).

- [ ] **Step 2.3: Implement the pattern library**

Create `scripts/lib/bypass-patterns.sh`:

```bash
# scripts/lib/bypass-patterns.sh — BL-029 bypass-shape pattern table.
#
# Sourced by scripts/hooks/bypass-detector.sh. Each pattern has a name
# (echoed by scan_bypass_patterns on match) and a regex. Add new patterns
# at the bottom of the table; do not modify the detector.

# shellcheck shell=bash

# Pattern table: NAME|REGEX (PATTERNS array, parallel arrays for clarity).
BYPASS_PATTERN_NAMES=(
  no_verify
  soif_force_step
  terminal_workaround
  fake_loop
  force_push
  manual_step_complete
)

BYPASS_PATTERN_REGEXES=(
  '--no-verify'
  'SOIF_FORCE_STEP='
  '(run|do|execute) this (in your )?(own )?terminal'
  '(mark|complete) step .*(build_loop|phase[0-9]+_init):.*(complete|done)|tests_verified_failing[^a-z]*complete'
  'git push (--force|--force-with-lease|-f[^a-z])'
  '(I.?ll|we can) (just )?mark .* (complete|done|passed)'
)

# scan_bypass_patterns <text>
# Echoes the first matched pattern name on stdout. Returns 0 on match,
# 1 on no match. Case-insensitive.
scan_bypass_patterns() {
  local text="${1:-}"
  [ -z "$text" ] && return 1
  local i
  for i in "${!BYPASS_PATTERN_NAMES[@]}"; do
    local name="${BYPASS_PATTERN_NAMES[$i]}"
    local regex="${BYPASS_PATTERN_REGEXES[$i]}"
    if echo "$text" | grep -qiE "$regex"; then
      echo "$name"
      return 0
    fi
  done
  return 1
}
```

- [ ] **Step 2.4: Run, verify pass**

```bash
bash tests/test-bypass-patterns.sh
```
Expected: `Results: 7 passed, 0 failed`. Iterate if a pattern's regex is too greedy or too narrow — these patterns are the heart of detection accuracy.

- [ ] **Step 2.5: Commit**

```bash
git add scripts/lib/bypass-patterns.sh tests/test-bypass-patterns.sh
git commit -m "feat(bl-029): bypass-pattern table — extensible match constants"
```

---

## Task 3: `scripts/hooks/bypass-detector.sh` — PostToolUse + Stop scanner

The core BL-029 hook. On each PostToolUse and Stop event, scan the relevant Claude output for bypass-shape language. On match, write a `claude_bypass_proposal` row with the verbatim text excerpt.

**Files:**
- Create: `scripts/hooks/bypass-detector.sh`
- Test: `tests/test-bypass-detector.sh`

- [ ] **Step 3.1: Write the failing test**

Create `tests/test-bypass-detector.sh`:

```bash
#!/usr/bin/env bash
# tests/test-bypass-detector.sh — BL-029 bypass-detector hook tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/bypass-detector.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  cat > "$TMP/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  echo "[]" > "$TMP/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

# Hook contract: stdin = JSON envelope from Claude Code.
# PostToolUse: { "tool_input": ..., "tool_result": {"output": "..."} }
# Stop:        { "transcript": "..." }   (representative; verify at integration time)

# T1: PostToolUse output containing --no-verify writes a row.
echo "T1: PostToolUse with --no-verify writes claude_bypass_proposal"
setup
if [ ! -f "$HOOK" ]; then fail_ "T1" "hook missing (RED)"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"echo x"},"tool_result":{"output":"alternatively, run git commit --no-verify"}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T1"; else fail_ "T1" "rows=$rows"; fi
fi
teardown

# T2: clean output writes nothing.
echo "T2: clean output is a no-op"
setup
if [ ! -f "$HOOK" ]; then fail_ "T2" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"ls"},"tool_result":{"output":"file1\nfile2"}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "0" ]; then pass "T2"; else fail_ "T2" "false positive: $rows"; fi
fi
teardown

# T3: Stop event with bypass-shaped transcript writes row.
echo "T3: Stop event scans transcript"
setup
if [ ! -f "$HOOK" ]; then fail_ "T3" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"Stop","transcript":"Maybe set SOIF_FORCE_STEP=build_loop:tests_written"}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T3"; else fail_ "T3" "rows=$rows"; fi
fi
teardown

# T4: row contains verbatim excerpt + matched pattern name.
echo "T4: row payload includes pattern + excerpt"
setup
if [ ! -f "$HOOK" ]; then fail_ "T4" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify to skip"}}
EOF
  pattern=$(jq -r '.[0].details.pattern' "$TMP/.claude/bypass-audit.json")
  excerpt=$(jq -r '.[0].details.excerpt' "$TMP/.claude/bypass-audit.json")
  if [ "$pattern" = "no_verify" ] && echo "$excerpt" | grep -q "no-verify"; then pass "T4"; else fail_ "T4" "pattern=$pattern excerpt='$excerpt'"; fi
fi
teardown

# T5: row's user_response is initialized to "PENDING".
echo "T5: user_response = PENDING on initial write"
setup
if [ ! -f "$HOOK" ]; then fail_ "T5" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify"}}
EOF
  resp=$(jq -r '.[0].user_response' "$TMP/.claude/bypass-audit.json")
  if [ "$resp" = "PENDING" ]; then pass "T5"; else fail_ "T5" "got '$resp'"; fi
fi
teardown

# T6: hook is silent (no stderr) on clean output.
echo "T6: hook is silent on clean output"
setup
if [ ! -f "$HOOK" ]; then fail_ "T6" "hook missing"; else
  cd "$TMP"
  err=$( (cat <<EOF | bash "$HOOK") 2>&1 >/dev/null
{"hook_event_name":"PostToolUse","tool_input":{"command":"ls"},"tool_result":{"output":"file"}}
EOF
)
  if [ -z "$err" ]; then pass "T6"; else fail_ "T6" "stderr leaked: $err"; fi
fi
teardown

# T7: hook does not duplicate rows for repeat scans of same content (idempotent on identical envelope).
echo "T7: identical envelope → 1 row, not 2 (deduped by content hash within a single run)"
setup
if [ ! -f "$HOOK" ]; then fail_ "T7" "hook missing"; else
  cd "$TMP"
  ENV='{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify here"}}'
  echo "$ENV" | bash "$HOOK" >/dev/null 2>&1
  echo "$ENV" | bash "$HOOK" >/dev/null 2>&1
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  # Two runs of the SAME hook on the SAME content: this is two distinct
  # firings, so 2 rows is correct — dedup is the user's job, not the hook's.
  # Verify the simpler invariant: each firing writes exactly one row when content matches.
  if [ "$rows" = "2" ]; then pass "T7"; else fail_ "T7" "expected 2 rows, got $rows"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 3.2: Run, verify failure**

```bash
bash tests/test-bypass-detector.sh
```
Expected: 7 FAIL.

- [ ] **Step 3.3: Implement the detector**

Create `scripts/hooks/bypass-detector.sh`:

```bash
#!/usr/bin/env bash
# scripts/hooks/bypass-detector.sh — BL-029 bypass-shape detector.
#
# Wires into Claude Code's PostToolUse and Stop hooks. Reads the JSON
# envelope from stdin, extracts the relevant text (tool_result.output for
# PostToolUse; transcript for Stop), scans against bypass-patterns.sh,
# and writes a claude_bypass_proposal row to bypass-audit.json on match.
#
# No-op conditions:
#   - .claude/ doesn't exist
#   - jq isn't installed
#   - envelope can't be parsed
#   - text contains no bypass-shaped language
#
# The hook is silent on the no-op paths. The audit-log writer (lib) is
# the framework's voice for matches; this script does not print anything
# to stdout (which would inject text into Claude's view).

set -uo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bypass-patterns.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bypass-audit.sh"

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)

# Extract scannable text by event type.
TEXT=""
case "$EVENT" in
  PostToolUse)
    TEXT=$(echo "$INPUT" | jq -r '.tool_result.output // .tool_result.stderr // ""' 2>/dev/null)
    ;;
  Stop)
    TEXT=$(echo "$INPUT" | jq -r '.transcript // .stop_reason // ""' 2>/dev/null)
    ;;
  *)
    # Unknown event — skip (defense against schema changes).
    exit 0
    ;;
esac

[ -z "$TEXT" ] && exit 0

PATTERN=$(scan_bypass_patterns "$TEXT") || exit 0
[ -z "$PATTERN" ] && exit 0

# Build the row.
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
LEVEL=$(jq -r '.enforcement_level // "strict"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null)

# Trim excerpt to the line containing the match (avoid 10kB rows).
EXCERPT=$(echo "$TEXT" | grep -iE "$(printf '%s' "$PATTERN" | tr _ '.')" | head -1 | head -c 500)

ROW=$(jq -nc \
  --arg ts "$TS" \
  --arg sid "$SESSION_ID" \
  --arg lvl "$LEVEL" \
  --arg pat "$PATTERN" \
  --arg evt "$EVENT" \
  --arg ex "$EXCERPT" \
  '{
    timestamp: $ts,
    session_id: $sid,
    type: "claude_bypass_proposal",
    actor: "claude",
    enforcement_level_at_event: $lvl,
    details: {pattern: $pat, event: $evt, excerpt: $ex},
    user_response: "PENDING",
    final_outcome: "recorded_only"
  }')

bypass_audit_append "$PROJECT_ROOT" "$ROW" || true

exit 0
```

Make executable:
```bash
chmod +x scripts/hooks/bypass-detector.sh
```

- [ ] **Step 3.4: Run, verify pass**

```bash
bash tests/test-bypass-detector.sh
```
Expected: `Results: 7 passed, 0 failed`. T1-T6 should be solid; T7 confirms each firing writes one row.

- [ ] **Step 3.5: Commit**

```bash
git add scripts/hooks/bypass-detector.sh tests/test-bypass-detector.sh
git commit -m "feat(bl-029): bypass-detector PostToolUse + Stop hook"
```

---

## Task 4: Pending-approval sentinel — confirmation-phrase requirement

When a `claude_bypass_proposal` row is `PENDING`, the framework must prevent generic "OK" / "yes" acceptance. The detector also writes a `pending-approval.json` sentinel that the existing CDF Stop-hook + BL-015 reader honor; the sentinel's `question` field embeds the required confirmation phrase.

**Files:**
- Modify: `scripts/hooks/bypass-detector.sh` (add sentinel write alongside audit row)
- Test: `tests/test-bypass-sentinel.sh`

- [ ] **Step 4.1: Read existing pending-approval pattern**

```bash
grep -n "write\|--write" scripts/pending-approval.sh | head -10
bash scripts/pending-approval.sh --help 2>&1 | head -30
```

Identify the canonical write subcommand and flag set.

- [ ] **Step 4.2: Write the failing test**

Create `tests/test-bypass-sentinel.sh`:

```bash
#!/usr/bin/env bash
# tests/test-bypass-sentinel.sh — BL-029 bypass-detector sentinel integration tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/bypass-detector.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  cat > "$TMP/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  echo "[]" > "$TMP/.claude/bypass-audit.json"
  rm -f "$TMP/.claude/pending-approval.json"
}
teardown() { rm -rf "$TMP"; }

# T1: bypass match writes pending-approval.json sentinel.
echo "T1: bypass match writes pending-approval.json"
setup
if [ ! -f "$HOOK" ]; then fail_ "T1" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify to skip"}}
EOF
  if [ -f "$TMP/.claude/pending-approval.json" ]; then pass "T1"; else fail_ "T1" "sentinel not written"; fi
fi
teardown

# T2: sentinel question contains the required confirmation phrase.
echo "T2: sentinel embeds confirmation phrase"
setup
if [ ! -f "$HOOK" ]; then fail_ "T2" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"--no-verify path"}}
EOF
  q=$(jq -r '.question' "$TMP/.claude/pending-approval.json")
  if echo "$q" | grep -q "I have read the proposal at .claude/bypass-audit.json and accept the bypass"; then
    pass "T2"
  else
    fail_ "T2" "phrase missing from question: $q"
  fi
fi
teardown

# T3: clean output does not write a sentinel.
echo "T3: clean output skips sentinel"
setup
if [ ! -f "$HOOK" ]; then fail_ "T3" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"normal output"}}
EOF
  if [ ! -f "$TMP/.claude/pending-approval.json" ]; then pass "T3"; else fail_ "T3" "sentinel false-write"; fi
fi
teardown

# T4: existing pending-approval is NOT overwritten by a second match (don't clobber).
echo "T4: hook preserves an existing sentinel"
setup
if [ ! -f "$HOOK" ]; then fail_ "T4" "hook missing"; else
  cat > "$TMP/.claude/pending-approval.json" <<'EOF'
{"question":"existing q","options":["A1: yes","A2: no"],"recommendation":"A1","offered_at":"2026-04-28T00:00:00Z"}
EOF
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"--no-verify"}}
EOF
  q=$(jq -r '.question' "$TMP/.claude/pending-approval.json")
  if [ "$q" = "existing q" ]; then pass "T4"; else fail_ "T4" "clobbered"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 4.3: Run, verify failure**

```bash
bash tests/test-bypass-sentinel.sh
```
Expected: 4 FAIL.

- [ ] **Step 4.4: Add sentinel write to the detector**

Edit `scripts/hooks/bypass-detector.sh`. After the `bypass_audit_append` call, add:

```bash
# BL-029: write pending-approval sentinel iff one isn't already pending.
SENTINEL="$PROJECT_ROOT/.claude/pending-approval.json"
if [ ! -f "$SENTINEL" ]; then
  CONFIRM_PHRASE="I have read the proposal at .claude/bypass-audit.json and accept the bypass"
  jq -nc \
    --arg q "Bypass proposal detected (pattern: $PATTERN). Review .claude/bypass-audit.json. To accept, type the confirmation phrase verbatim. To decline, just say 'decline' or describe what you want instead." \
    --arg phrase "$CONFIRM_PHRASE" \
    --arg ts "$TS" \
    '{
      question: ($q + "\n\nConfirmation phrase: " + $phrase),
      options: [
        ("A1: " + $phrase),
        "A2: decline"
      ],
      recommendation: "A2",
      offered_at: $ts
    }' > "$SENTINEL"
fi
```

- [ ] **Step 4.5: Run, verify pass**

```bash
bash tests/test-bypass-sentinel.sh
bash tests/test-bypass-detector.sh
```
Both expected to pass — the sentinel addition must not regress the audit-row tests.

- [ ] **Step 4.6: Commit**

```bash
git add scripts/hooks/bypass-detector.sh tests/test-bypass-sentinel.sh
git commit -m "feat(bl-029): bypass-detector writes pending-approval sentinel with confirmation phrase"
```

---

## Task 5: `scripts/escalate-to-user.sh` CLI

A documented alternative to suggesting `--no-verify`. Claude calls this script when it wants to surface a structured decision to the user instead of proposing a bypass. Wraps `pending-approval.sh`. Provides a clean, named action so Claude has something other than bypass to reach for.

**Files:**
- Create: `scripts/escalate-to-user.sh`
- Test: `tests/test-escalate-to-user.sh`

- [ ] **Step 5.1: Write the failing test**

Create `tests/test-escalate-to-user.sh`:

```bash
#!/usr/bin/env bash
# tests/test-escalate-to-user.sh — BL-029 escalate-to-user CLI tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ESCALATE="$REPO_ROOT/scripts/escalate-to-user.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d); mkdir -p "$TMP/.claude"
  echo "[]" > "$TMP/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

# T1: escalate writes pending-approval.json with question + options.
echo "T1: escalate writes a structured pending-approval"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T1" "missing"; else
  ( cd "$TMP" && bash "$ESCALATE" \
      --question "should we proceed?" \
      --option "A1: proceed" \
      --option "A2: stop" \
      --recommendation "A2" >/dev/null 2>&1 )
  if [ -f "$TMP/.claude/pending-approval.json" ]; then pass "T1"; else fail_ "T1" "no sentinel written"; fi
fi
teardown

# T2: escalate also writes an audit row of type 'enforcement_level_set' with details.action='escalation'.
echo "T2: escalate writes an audit row"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T2" "missing"; else
  ( cd "$TMP" && bash "$ESCALATE" --question q --option "A1: x" --option "A2: y" --recommendation A1 >/dev/null 2>&1 )
  rows=$(jq '[.[] | select(.details.action=="escalation")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T2"; else fail_ "T2" "rows=$rows"; fi
fi
teardown

# T3: missing required arg fails fast.
echo "T3: --question is required"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T3" "missing"; else
  if ( cd "$TMP" && bash "$ESCALATE" --option "A1: x" --option "A2: y" --recommendation A1 >/dev/null 2>&1 ); then
    fail_ "T3" "expected non-zero"
  else
    pass "T3"
  fi
fi
teardown

# T4: < 2 options fails fast (CDF schema requires >= 2).
echo "T4: requires at least 2 options"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T4" "missing"; else
  if ( cd "$TMP" && bash "$ESCALATE" --question q --option "A1: only" --recommendation A1 >/dev/null 2>&1 ); then
    fail_ "T4" "expected non-zero"
  else
    pass "T4"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 5.2: Run, verify failure**

```bash
bash tests/test-escalate-to-user.sh
```
Expected: 4 FAIL.

- [ ] **Step 5.3: Implement the CLI**

Create `scripts/escalate-to-user.sh`:

```bash
#!/usr/bin/env bash
# scripts/escalate-to-user.sh — BL-029 documented bypass alternative.
#
# Wraps pending-approval.sh to give Claude a structured way to surface a
# decision to the user instead of proposing a bypass. Writes both the
# pending-approval.json sentinel (which the CDF stop-hook honors) and a
# row to bypass-audit.json tagged as an escalation.
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

# Audit row.
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
    type: "enforcement_level_set",
    actor: "framework",
    enforcement_level_at_event: $lvl,
    details: {action: "escalation", question: $q, options: $opts, recommendation: $rec, rationale: $rat},
    user_response: "PENDING",
    final_outcome: "escalated"
  }')
bypass_audit_append "$PROJECT_ROOT" "$ROW" || true

echo "[OK] escalation written to .claude/pending-approval.json (and audit log)"
```

Make executable:
```bash
chmod +x scripts/escalate-to-user.sh
```

- [ ] **Step 5.4: Run, verify pass**

```bash
bash tests/test-escalate-to-user.sh
```
Expected: `Results: 4 passed, 0 failed`.

- [ ] **Step 5.5: Commit**

```bash
git add scripts/escalate-to-user.sh tests/test-escalate-to-user.sh
git commit -m "feat(bl-029): escalate-to-user CLI — documented bypass alternative"
```

---

## Task 6: Refuse-to-recommend Stop-hook check (synthetic Build Loop)

Per agent-5 spec: Claude should be hard-blocked from proposing fake-loop bypasses (synthetic Build Loop step proposals without prior `tests_verified_failing`). Calibration agent 3 even self-identified this as "a trap." Adding it as a Stop-hook check augments the bypass-detector with a recommend-refusal layer.

**Files:**
- Modify: `scripts/hooks/bypass-detector.sh` (add refuse-to-recommend logic)
- Test: extend `tests/test-bypass-detector.sh` (or new file)

- [ ] **Step 6.1: Add a new test case to `tests/test-bypass-detector.sh`**

Append before `echo ""` at the end:

```bash
# T8: synthetic Build Loop step proposal triggers a stronger row type.
echo "T8: fake_loop pattern is recorded with elevated severity"
setup
if [ ! -f "$HOOK" ]; then fail_ "T8" "hook missing"; else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"Stop","transcript":"I'll mark step build_loop:tests_verified_failing complete and skip ahead"}
EOF
  pattern=$(jq -r '.[0].details.pattern' "$TMP/.claude/bypass-audit.json")
  severity=$(jq -r '.[0].details.severity // "normal"' "$TMP/.claude/bypass-audit.json")
  if [ "$pattern" = "fake_loop" ] && [ "$severity" = "refuse_to_recommend" ]; then pass "T8"; else fail_ "T8" "pattern=$pattern severity=$severity"; fi
fi
teardown
```

Re-run; expected: T1-T7 still pass, T8 fails (severity field not yet emitted).

- [ ] **Step 6.2: Add the elevated-severity tagging in the detector**

Edit `scripts/hooks/bypass-detector.sh`. After `PATTERN=$(scan_bypass_patterns ...)`, add:

```bash
# Refuse-to-recommend severity for fake-loop patterns (Stop-hook context).
SEVERITY="normal"
case "$PATTERN" in
  fake_loop|manual_step_complete) SEVERITY="refuse_to_recommend" ;;
esac
```

Then update the `details` builder to include severity:

```bash
'details': {pattern: $pat, event: $evt, excerpt: $ex, severity: $sev}
```

(Add `--arg sev "$SEVERITY"` to the jq invocation.)

- [ ] **Step 6.3: Run, verify pass**

```bash
bash tests/test-bypass-detector.sh
```
Expected: 8/8 PASS.

- [ ] **Step 6.4: Commit**

```bash
git add scripts/hooks/bypass-detector.sh tests/test-bypass-detector.sh
git commit -m "feat(bl-029): bypass-detector elevates fake_loop / manual_step_complete to refuse_to_recommend severity"
```

---

## Task 7: Wire BL-029 hooks into project-template `.claude/settings.json` AND framework's own settings

Both the freshly-init'd project AND solo-orchestrator's own dev workflow need the bypass-detector firing.

**Files:**
- Modify: `init.sh` (project template hook installation)
- Modify: `.claude/settings.json` (framework-self instance — add bypass-detector entry)

- [ ] **Step 7.1: Add to init.sh's settings.json hook block**

Find the existing PostToolUse hook installation pattern in init.sh (where `track-tool-usage.sh` is wired). Alongside it, install the bypass-detector for both PostToolUse and Stop:

```bash
# BL-029: bypass-detector PostToolUse + Stop.
if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("bypass-detector.sh"))' .claude/settings.json >/dev/null 2>&1; then
  jq '.hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
    && mv .claude/settings.json.tmp .claude/settings.json
fi
if ! jq -e '.hooks.Stop[0].hooks[]? | select(.command | contains("bypass-detector.sh"))' .claude/settings.json >/dev/null 2>&1; then
  jq 'if (.hooks.Stop // []) | length == 0
      then .hooks.Stop = [{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]
      else .hooks.Stop[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]
      end' .claude/settings.json > .claude/settings.json.tmp \
    && mv .claude/settings.json.tmp .claude/settings.json
fi
```

- [ ] **Step 7.2: Add the scripts to init.sh's copy list**

In init.sh's `cp scripts/...` block:

```bash
mkdir -p scripts/hooks
cp "$SCRIPT_DIR/scripts/hooks/bypass-detector.sh" scripts/hooks/
cp "$SCRIPT_DIR/scripts/escalate-to-user.sh"      scripts/
cp "$SCRIPT_DIR/scripts/lib/bypass-audit.sh"      scripts/lib/
cp "$SCRIPT_DIR/scripts/lib/bypass-patterns.sh"   scripts/lib/
chmod +x scripts/hooks/bypass-detector.sh scripts/escalate-to-user.sh
```

- [ ] **Step 7.3: Add to framework's own `.claude/settings.json`**

Read the current file:
```bash
cat .claude/settings.json
```

If a settings.local.json file exists (per the gitStatus header), check there too. Add the bypass-detector PostToolUse + Stop entries using the same jq pattern as Step 7.1 — manually run the jq once now to update the framework's own settings:

```bash
jq '.hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]' .claude/settings.json > /tmp/s.json \
  && mv /tmp/s.json .claude/settings.json
```

(Adapt for whichever settings file the framework actually loads — check `.claude/settings.json` and `.claude/settings.local.json`; the public template at the repo root might also need updating.)

- [ ] **Step 7.4: Smoke test the wiring**

```bash
TMP=$(mktemp -d); PROJ="$TMP/p"
bash init.sh --non-interactive --project-dir "$PROJ" --no-remote-creation \
  --project-name x --platform other --language other --track light --deployment personal
jq '.hooks.PostToolUse[0].hooks[] | select(.command | contains("bypass-detector"))' "$PROJ/.claude/settings.json"
jq '.hooks.Stop[0].hooks[] | select(.command | contains("bypass-detector"))' "$PROJ/.claude/settings.json"
ls "$PROJ/scripts/hooks/bypass-detector.sh" "$PROJ/scripts/escalate-to-user.sh" "$PROJ/scripts/lib/bypass-audit.sh" "$PROJ/scripts/lib/bypass-patterns.sh"
rm -rf "$TMP"
```
All commands should succeed and print one match each.

- [ ] **Step 7.5: Commit**

```bash
git add init.sh .claude/settings.json
git commit -m "feat(bl-029): wire bypass-detector into project template + framework settings"
```

---

## Task 8: Update CLAUDE.md template with the bypass-alternative instructions

The framework should tell Claude (in CLAUDE.md it injects into projects) that `escalate-to-user.sh` exists and is the documented alternative to suggesting bypasses. Without this instruction, Claude won't know to reach for it.

**Files:**
- Modify: `templates/generated/claude.tmpl` (or wherever the project's CLAUDE.md is templated; identify via `grep -rln "CLAUDE.md" templates/ init.sh`)

- [ ] **Step 8.1: Locate the CLAUDE.md template**

```bash
grep -n "CLAUDE.md\|claude.md" init.sh | head -10
ls templates/generated/ 2>/dev/null
```

- [ ] **Step 8.2: Append a new section to the template**

Add a section near the existing process-discipline / commit-gate instructions:

```markdown
## When a hook blocks you

If a framework hook blocks an action:

1. **Diagnose first.** Read the block message. Many block messages now ship with a "Why this rule exists" paragraph (BL-030 strict mode). The principle is the answer to "should I bypass?"

2. **If the block looks legitimately wrong** (the hook is misclassifying your case): file a backlog item describing the misclassification. Do NOT suggest `--no-verify` as a workaround. Bypass-shaped suggestions are auto-recorded to `.claude/bypass-audit.json` regardless of whether the user accepts them — your suggestion is the audit event, not the user's response.

3. **If the user needs to make a judgment call**: use `scripts/escalate-to-user.sh` to surface a structured pending-approval. This is the framework's documented alternative to bypass-proposing:

   ```
   scripts/escalate-to-user.sh \
     --question "<what you need the user to decide>" \
     --option "A1: <option 1>" \
     --option "A2: <option 2>" \
     --recommendation "A2" \
     --rationale "<why you recommend that option>"
   ```

   The escalation writes both `.claude/pending-approval.json` (which the CDF stop-hook honors) and an audit row tagged as an escalation.

4. **Refuse-to-recommend.** Do NOT propose: synthetic Build Loop step completions ("I'll mark `tests_verified_failing` complete and move on"); manual `git commit --no-verify` workarounds; force-pushes to fix process violations. These are explicitly flagged by `bypass-detector.sh` and elevated to `severity: refuse_to_recommend` in the audit log. Suggesting them is itself the failure mode the framework is designed to make visible.
```

- [ ] **Step 8.3: Smoke test that init produces a CLAUDE.md with the new section**

```bash
TMP=$(mktemp -d); PROJ="$TMP/p"
bash init.sh --non-interactive --project-dir "$PROJ" --no-remote-creation \
  --project-name x --platform other --language other --track light --deployment personal
grep -q "escalate-to-user.sh" "$PROJ/CLAUDE.md" && echo OK || echo MISSING
rm -rf "$TMP"
```
Expected: `OK`.

- [ ] **Step 8.4: Commit**

```bash
git add templates/generated/claude.tmpl  # adjust path
git commit -m "docs(bl-029): CLAUDE.md template — bypass-alternative + escalate-to-user instructions"
```

---

## Task 9: Backward-compat + cross-cutting integration test

A single test that runs through a representative scenario and verifies the BL-029 pipeline end-to-end.

**Files:**
- Test: `tests/test-bl029-integration.sh`

- [ ] **Step 9.1: Write the integration test**

```bash
#!/usr/bin/env bash
# tests/test-bl029-integration.sh — end-to-end BL-029 pipeline.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Provision a fresh project.
TMP=$(mktemp -d); PROJ="$TMP/p"
( cd "$REPO_ROOT" && bash init.sh --non-interactive --project-dir "$PROJ" --no-remote-creation \
    --project-name x --platform other --language other --track light --deployment personal \
    >/dev/null 2>&1 )

# T1: project has bypass-detector wired.
if jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("bypass-detector"))' "$PROJ/.claude/settings.json" >/dev/null 2>&1; then
  pass "T1: PostToolUse wiring"
else
  fail_ "T1" "no PostToolUse"
fi

# T2: simulate a Claude PostToolUse with bypass-shaped output → audit row + sentinel.
( cd "$PROJ"
  cat <<'EOF' | bash scripts/hooks/bypass-detector.sh >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"alternatively, run git commit --no-verify"}}
EOF
)
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" = "1" ]; then pass "T2: detector wrote claude_bypass_proposal row"; else fail_ "T2" "rows=$rows"; fi

if [ -f "$PROJ/.claude/pending-approval.json" ]; then
  pass "T3: pending-approval sentinel written"
else
  fail_ "T3" "no sentinel"
fi

# T4: escalate-to-user CLI works end-to-end.
( cd "$PROJ" && bash scripts/escalate-to-user.sh \
    --question "test escalation" \
    --option "A1: yes" --option "A2: no" \
    --recommendation A2 \
    --rationale "no rationale needed for the test" >/dev/null 2>&1 )
esc_rows=$(jq '[.[] | select(.details.action=="escalation")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$esc_rows" = "1" ]; then pass "T4: escalate CLI wrote audit row"; else fail_ "T4" "rows=$esc_rows"; fi

# T5: actor enum invariant — every row's actor is one of the documented values.
ACTORS=$(jq -r '[.[].actor] | unique | .[]' "$PROJ/.claude/bypass-audit.json")
ALL_OK=1
for a in $ACTORS; do
  case "$a" in claude|user_terminal|user_terminal_inferred|framework) ;; *) ALL_OK=0 ;; esac
done
if [ "$ALL_OK" = "1" ]; then pass "T5: actor enum"; else fail_ "T5" "unknown actor in $ACTORS"; fi

rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 9.2: Run, verify pass**

```bash
bash tests/test-bl029-integration.sh
```
Expected: `Results: 5 passed, 0 failed`.

- [ ] **Step 9.3: Run full regression suite**

```bash
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1 && echo "PASS $(basename "$t")" || echo "FAIL $(basename "$t")"; done
```
All existing tests must still pass (the new hooks must not break any prior behavior in the framework's own settings).

- [ ] **Step 9.4: Commit**

```bash
git add tests/test-bl029-integration.sh
git commit -m "test(bl-029): end-to-end integration — detector + sentinel + escalate"
```

---

## Task 10: Test-gate counter + backlog updates + BL-030 plan refactor note

- [ ] **Step 10.1: Bump test-gate counter**

```bash
bash scripts/test-gate.sh --record-feature "BL-029 bypass audit-log infrastructure"
```

If counter hits 2/2, the next feature triggers a mandatory test gate.

- [ ] **Step 10.2: Mark BL-029 closed in the backlog**

Edit `solo-orchestrator-backlog.md` BL-029 entry — change `Status: Open` to `Status: Closed — shipped 2026-MM-DD (PR #NN)`. Add a one-line summary referencing the plan.

- [ ] **Step 10.3: Add a BL-030 plan refactor note**

Edit `docs/superpowers/plans/2026-04-28-bl030-enforcement-model-plan.md`. Find each task that uses inline `jq --argjson r ... '. + [$r]' ...` (Tasks 3, 4 (`record_audit_row` function), 7, 8). Add a marker comment near each:

```
> Refactor note (post-BL-029): replace this inline jq append with `bypass_audit_append "$PROJECT_ROOT" "$ROW"` from `scripts/lib/bypass-audit.sh`. Source the lib at the top of each script. The flock protection in the library prevents races between BL-029's bypass-detector and BL-030's writers.
```

This signals to the next session executing the BL-030 plan to use the library.

- [ ] **Step 10.4: Commit**

```bash
git add solo-orchestrator-backlog.md docs/superpowers/plans/2026-04-28-bl030-enforcement-model-plan.md .claude/build-progress.json
git commit -m "docs(backlog,bl-030-plan): close BL-029 + flag library refactor in BL-030 plan"
```

---

## Self-Review Checklist (run after writing all code)

- [ ] Every component from `solo-orchestrator-backlog.md:695-722` BL-029 spec is implemented:
  - PostToolUse + Stop bypass-shape detector → Task 3
  - Auto-write to bypass-audit.json with verbatim text → Task 3
  - Schema fields (timestamp, hook_fired, claude_proposal_text, match_pattern, session_id) → Tasks 1, 3 (mapped to canonical schema in spec § 6)
  - PENDING / accept / decline / escalated lifecycle → Tasks 1 (`bypass_audit_count_pending`), 4, 5
  - Non-bypassable writer → Task 7 (wired regardless of `enforcement_level`)
  - Confirmation phrase sentinel → Task 4
  - escalate-to-user CLI → Task 5
  - Refuse-to-recommend (synthetic Build Loop) → Task 6
- [ ] Every row written by every BL-029 writer satisfies the canonical schema (validated by Task 9 T5).
- [ ] Existing `pending-approval.sh` is reused, not replaced (Tasks 4, 5 both write the same `.claude/pending-approval.json` artifact format).
- [ ] Full regression suite passes after Task 9.
- [ ] BL-030 plan has refactor markers for the inline-jq sites (Task 10).
- [ ] CLAUDE.md template updated so projects' own Claude instances learn about `escalate-to-user.sh` (Task 8).
- [ ] Test-gate counter bumped (Task 10).

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-28-bl029-bypass-audit-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — Dispatch a fresh subagent per task using `superpowers:subagent-driven-development`. Review between tasks. Best for a 10-task plan because per-task isolation prevents cross-task context pollution.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`. Batch with checkpoints.

**Which approach?**

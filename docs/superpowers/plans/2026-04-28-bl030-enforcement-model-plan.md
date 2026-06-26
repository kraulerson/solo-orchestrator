# BL-030 Enforcement Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project-wide `enforcement_level` field (no/light/strict) that controls how the framework treats user-terminal git actions, layered on top of the existing Claude-side PreToolUse enforcement, and feeding the unified `.claude/bypass-audit.json` ledger.

**Architecture:** New manifest field drives a menu of three modes. `no` = no user-terminal enforcement and no recording. `light` = SessionStart-triggered out-of-band commit detection (records, doesn't block). `strict` = filesystem-level git hook composed into `.git/hooks/pre-commit` via a marked block, calling the same gate logic Claude's PreToolUse path uses (no duplication). Audit log is universal — Claude-side BL-029 writer always-on, user-terminal writers gated by level.

**Tech Stack:** bash, jq, git, existing `scripts/lib/helpers.sh` patterns (`prompt_choice`, `print_warn`, `print_ok`), existing `scripts/process-checklist.sh` and `scripts/pre-commit-gate.sh` reused via a new `--terminal-mode` flag.

---

## Prerequisites

- **BL-029 must ship first.** This plan assumes `.claude/bypass-audit.json` exists with the schema documented in `docs/superpowers/specs/2026-04-28-bl030-enforcement-model-design.md` § 6, and that the BL-029 Claude-side writer (PostToolUse + Stop hooks scanning Claude output for bypass-shaped language) is operational. If BL-029 hasn't shipped, write its plan first from `solo-orchestrator-backlog.md:695-722` and this spec's § 6, ship it, then return here.
- **Library-refactor note (post-BL-029, 2026-04-29).** BL-029 shipped `scripts/lib/bypass-audit.sh` with `bypass_audit_init()`, `bypass_audit_append()`, and `bypass_audit_count_pending()` helpers, including a portable mkdir-based advisory lock. **Every site in this plan that shows inline `jq --argjson r "$row" '. + [$r]' "$AUDIT" > "$tmp"`-style appending should be rewritten to call `bypass_audit_append "$PROJECT_ROOT" "$ROW"` instead.** Source the library at the top of each script (`source "$SCRIPT_DIR/lib/bypass-audit.sh"`). The lock prevents races between BL-029's bypass-detector and BL-030's writers. Also: the BL-030 spec's type enum was amended (2026-04-29) to include `escalation` — relevant to Task 5 (escalate-to-user CLI) which BL-029 already shipped, not BL-030. Affected sites in this plan: Task 3 (detector `append_audit_row`), Task 4 (`record_audit_row` helper inside `install-filesystem-gates.sh`), Task 7 (`init.sh` enforcement_level_set row), Task 8 (`reconfigure-project.sh` transition + reset-baseline rows). The schema rows themselves are unchanged — only the persistence call swaps.
- BL-026 (Phase 1→2 prereq validator) is already shipped and is reused by `framework-gate.sh` via `process-checklist.sh --check-commit-ready`.
- Tests use the project's existing pattern: standalone bash test files at `tests/test-*.sh`, run via `bash tests/test-foo.sh`, with `PASSED`/`FAILED` counters and `pass`/`fail_` helpers (see `tests/test-phase-prerequisites.sh:16-19` for the canonical shape).

## Working directory

All commands assume CWD = `/Users/karl/Documents/Claude Projects/solo-orchestrator` (the framework repo). Replace with worktree path if executing in an isolated worktree.

---

## Task 1: `scripts/lib/enforcement-level.sh` library

Foundation. Sourced by everything else. No behavior change yet — pure helpers.

**Files:**
- Create: `scripts/lib/enforcement-level.sh`
- Test: `tests/test-enforcement-level-lib.sh`

- [ ] **Step 1.1: Write the failing test**

Create `tests/test-enforcement-level-lib.sh`:

```bash
#!/usr/bin/env bash
# tests/test-enforcement-level-lib.sh — BL-030 enforcement-level library tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/enforcement-level.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_lib_or_skip() {
  if [ ! -f "$LIB" ]; then
    fail_ "$1" "scripts/lib/enforcement-level.sh does not exist (RED expected before impl)"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$LIB"
}

setup() { TMP=$(mktemp -d); mkdir -p "$TMP/.claude"; }
teardown() { rm -rf "$TMP"; }

write_manifest() {
  local proj="$1" deployment="$2" poc_mode="$3" enforcement_level="${4:-}"
  local body='{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"'"$deployment"'"'
  if [ -n "$poc_mode" ]; then body+=',"poc_mode":"'"$poc_mode"'"'; fi
  if [ -n "$enforcement_level" ]; then body+=',"enforcement_level":"'"$enforcement_level"'"'; fi
  body+='}'
  echo "$body" > "$proj/.claude/manifest.json"
}

# T1: read_enforcement_level returns explicit value when set.
echo "T1: read_enforcement_level returns explicit value"
setup
setup_lib_or_skip "T1" && {
  write_manifest "$TMP" "personal" "" "light"
  result=$(read_enforcement_level "$TMP")
  if [ "$result" = "light" ]; then pass "T1"; else fail_ "T1" "got '$result' expected 'light'"; fi
}
teardown

# T2: read_enforcement_level defaults to strict when field missing.
echo "T2: read_enforcement_level defaults to 'strict' on missing field"
setup
setup_lib_or_skip "T2" && {
  write_manifest "$TMP" "personal" "" ""
  result=$(read_enforcement_level "$TMP")
  if [ "$result" = "strict" ]; then pass "T2"; else fail_ "T2" "got '$result' expected 'strict'"; fi
}
teardown

# T3: read_enforcement_level defaults to strict when manifest missing.
echo "T3: read_enforcement_level defaults to 'strict' on missing manifest"
setup
setup_lib_or_skip "T3" && {
  result=$(read_enforcement_level "$TMP")
  if [ "$result" = "strict" ]; then pass "T3"; else fail_ "T3" "got '$result' expected 'strict'"; fi
}
teardown

# T4: assert_choosable accepts personal.
echo "T4: assert_choosable returns 0 for personal"
setup
setup_lib_or_skip "T4" && {
  write_manifest "$TMP" "personal" "" ""
  if assert_choosable "$TMP" 2>/dev/null; then pass "T4"; else fail_ "T4" "expected return 0"; fi
}
teardown

# T5: assert_choosable accepts private_poc.
echo "T5: assert_choosable returns 0 for organizational + private_poc"
setup
setup_lib_or_skip "T5" && {
  write_manifest "$TMP" "organizational" "private_poc" ""
  if assert_choosable "$TMP" 2>/dev/null; then pass "T5"; else fail_ "T5" "expected return 0"; fi
}
teardown

# T6: assert_choosable rejects sponsored_poc.
echo "T6: assert_choosable returns 1 for organizational + sponsored_poc"
setup
setup_lib_or_skip "T6" && {
  write_manifest "$TMP" "organizational" "sponsored_poc" ""
  if assert_choosable "$TMP" 2>/dev/null; then fail_ "T6" "expected return 1"; else pass "T6"; fi
}
teardown

# T7: assert_choosable rejects production (no poc_mode).
echo "T7: assert_choosable returns 1 for organizational + production"
setup
setup_lib_or_skip "T7" && {
  write_manifest "$TMP" "organizational" "" ""
  if assert_choosable "$TMP" 2>/dev/null; then fail_ "T7" "expected return 1"; else pass "T7"; fi
}
teardown

# T8: validate_transition allows strict→light on choosable.
echo "T8: validate_transition allows strict→light for personal"
setup
setup_lib_or_skip "T8" && {
  write_manifest "$TMP" "personal" "" "strict"
  if validate_transition "$TMP" "light" 2>/dev/null; then pass "T8"; else fail_ "T8" "expected return 0"; fi
}
teardown

# T9: validate_transition rejects strict→light on production.
echo "T9: validate_transition rejects strict→light for organizational+production"
setup
setup_lib_or_skip "T9" && {
  write_manifest "$TMP" "organizational" "" "strict"
  if validate_transition "$TMP" "light" 2>/dev/null; then fail_ "T9" "expected return 1"; else pass "T9"; fi
}
teardown

# T10: validate_transition rejects unknown level.
echo "T10: validate_transition rejects level='foo'"
setup
setup_lib_or_skip "T10" && {
  write_manifest "$TMP" "personal" "" "strict"
  if validate_transition "$TMP" "foo" 2>/dev/null; then fail_ "T10" "expected return 1"; else pass "T10"; fi
}
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 1.2: Run test, verify it fails**

```bash
bash tests/test-enforcement-level-lib.sh
```
Expected: 10 FAIL lines (lib doesn't exist yet).

- [ ] **Step 1.3: Implement the library**

Create `scripts/lib/enforcement-level.sh`:

```bash
# scripts/lib/enforcement-level.sh — BL-030 enforcement-level helpers.
#
# Reads the project's enforcement_level setting and validates transitions.
# Sourced by init.sh, reconfigure-project.sh, framework-gate.sh,
# detect-out-of-band-commits.sh, and any future caller that needs to
# decide based on the enforcement posture.
#
# Field values: "no" | "light" | "strict". Default at read time: "strict".

# shellcheck shell=bash

# read_enforcement_level <project_root>
# Echoes the project's enforcement_level. Defaults to "strict" if the
# field is missing or the manifest doesn't exist. Never errors — callers
# can rely on the output.
read_enforcement_level() {
  local project_root="${1:-.}"
  local manifest="$project_root/.claude/manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "strict"
    return 0
  fi
  local level
  level=$(jq -r '.enforcement_level // "strict"' "$manifest" 2>/dev/null || echo "strict")
  case "$level" in
    no|light|strict) echo "$level" ;;
    *) echo "strict" ;;
  esac
}

# assert_choosable <project_root>
# Returns 0 if the project's deployment / poc_mode allows the user to
# pick enforcement_level. Returns 1 otherwise. No output unless error.
#
# Choosable: deployment=personal OR (deployment=organizational AND poc_mode=private_poc).
# Non-choosable (forced strict): deployment=organizational AND poc_mode IN {sponsored_poc, "" (production)}.
assert_choosable() {
  local project_root="${1:-.}"
  local manifest="$project_root/.claude/manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "[FAIL] enforcement-level: manifest missing at $manifest" >&2
    return 1
  fi
  local deployment poc_mode
  deployment=$(jq -r '.deployment // "personal"' "$manifest" 2>/dev/null)
  poc_mode=$(jq -r '.poc_mode // ""' "$manifest" 2>/dev/null)
  if [ "$deployment" = "personal" ]; then
    return 0
  fi
  if [ "$deployment" = "organizational" ] && [ "$poc_mode" = "private_poc" ]; then
    return 0
  fi
  return 1
}

# validate_transition <project_root> <new_level>
# Returns 0 if the requested transition is allowed. Returns 1 with a
# diagnostic on stderr otherwise.
validate_transition() {
  local project_root="${1:-.}"
  local new_level="$2"
  case "$new_level" in
    no|light|strict) ;;
    *)
      echo "[FAIL] enforcement-level: unknown level '$new_level' (expected: no | light | strict)" >&2
      return 1
      ;;
  esac
  if assert_choosable "$project_root"; then
    return 0
  fi
  # Non-choosable mode — must stay strict.
  if [ "$new_level" = "strict" ]; then
    return 0
  fi
  echo "[FAIL] enforcement-level: cannot set '$new_level' on this project — deployment/poc_mode forces strict" >&2
  return 1
}
```

- [ ] **Step 1.4: Run test, verify pass**

```bash
bash tests/test-enforcement-level-lib.sh
```
Expected: `Results: 10 passed, 0 failed`.

- [ ] **Step 1.5: Commit**

```bash
git add scripts/lib/enforcement-level.sh tests/test-enforcement-level-lib.sh
git commit -m "feat(bl-030): enforcement-level library — read, assert_choosable, validate_transition"
```

---

## Task 2: `record-claude-commit.sh` PostToolUse hook + `claude-commits.jsonl`

Always-on. Records the SHA of every successful Claude-issued commit. Independent of `enforcement_level` — the ledger is a universal observation layer that the out-of-band detector relies on.

**Files:**
- Create: `scripts/hooks/record-claude-commit.sh`
- Test: `tests/test-record-claude-commit.sh`

- [ ] **Step 2.1: Write the failing test**

Create `tests/test-record-claude-commit.sh`:

```bash
#!/usr/bin/env bash
# tests/test-record-claude-commit.sh — BL-030 Claude-commit recorder tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/record-claude-commit.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# The PostToolUse hook contract for Claude Code: stdin is a JSON object
# with at least { "tool_input": {...}, "tool_response": {...} }. We expect
# the hook to inspect tool_input.command and only act on git-commit calls
# that succeeded.

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  ( cd "$TMP"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    echo "first" > f.txt && git add f.txt && git commit -qm "first" 2>/dev/null
  )
  SHA=$(cd "$TMP" && git rev-parse HEAD)
}
teardown() { rm -rf "$TMP"; }

# T1: hook records a successful git commit.
echo "T1: PostToolUse hook records SHA of a successful git commit"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T1" "hook script missing (RED expected before impl)"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'feat: x'"},"tool_response":{"exit_code":0}}
EOF
  if [ -f "$TMP/.claude/claude-commits.jsonl" ] && \
     jq -e --arg sha "$SHA" '.sha == $sha' < "$TMP/.claude/claude-commits.jsonl" >/dev/null 2>&1; then
    pass "T1"
  else
    fail_ "T1" "claude-commits.jsonl missing or SHA mismatch"
  fi
fi
teardown

# T2: hook does NOT record a non-git-commit tool call.
echo "T2: PostToolUse hook ignores non-commit Bash calls"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T2" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"ls -la"},"tool_response":{"exit_code":0}}
EOF
  if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
    pass "T2"
  else
    fail_ "T2" "ledger should not exist for ls call"
  fi
fi
teardown

# T3: hook does NOT record a failed git commit.
echo "T3: PostToolUse hook ignores failed git commits"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T3" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'feat: x'"},"tool_response":{"exit_code":1}}
EOF
  if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
    pass "T3"
  else
    fail_ "T3" "ledger should not exist for failed commit"
  fi
fi
teardown

# T4: hook is append-only — second commit appends a row.
echo "T4: PostToolUse hook appends to existing ledger"
setup
if [ ! -f "$HOOK" ]; then
  fail_ "T4" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'first'"},"tool_response":{"exit_code":0}}
EOF
  echo "second" > g.txt && git add g.txt && git commit -qm "second" 2>/dev/null
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'second'"},"tool_response":{"exit_code":0}}
EOF
  count=$(wc -l < "$TMP/.claude/claude-commits.jsonl" | tr -d ' ')
  if [ "$count" = "2" ]; then pass "T4"; else fail_ "T4" "expected 2 rows, got $count"; fi
fi
teardown

# T5: hook is silent on missing .claude/ (project not initialized).
echo "T5: PostToolUse hook is a no-op when .claude/ does not exist"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.l" && git config user.name "t"
  echo x > x && git add x && git commit -qm x )
if [ ! -f "$HOOK" ]; then
  fail_ "T5" "hook script missing"
else
  cd "$TMP"
  cat <<EOF | bash "$HOOK" >/dev/null 2>&1
{"tool_input":{"command":"git commit -m 'x'"},"tool_response":{"exit_code":0}}
EOF
  if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
    pass "T5"
  else
    fail_ "T5" "ledger created in uninitialized project"
  fi
fi
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2.2: Run test, verify it fails**

```bash
bash tests/test-record-claude-commit.sh
```
Expected: 5 FAIL.

- [ ] **Step 2.3: Implement the hook**

Create `scripts/hooks/record-claude-commit.sh`:

```bash
#!/usr/bin/env bash
# scripts/hooks/record-claude-commit.sh — BL-030 PostToolUse hook.
#
# Records the SHA of every successful git commit issued by Claude into
# .claude/claude-commits.jsonl. Always-on, regardless of enforcement_level.
# The ledger is the substrate the out-of-band detector uses to distinguish
# Claude-issued commits from user-terminal commits.
#
# Stdin: JSON envelope from Claude Code's PostToolUse hook contract:
#   { "tool_input": {"command": "..."}, "tool_response": {"exit_code": N} }
#
# No-op conditions:
#   - .claude/ doesn't exist (project not initialized)
#   - tool_input.command isn't a `git commit` invocation
#   - tool_response.exit_code != 0
#   - jq isn't installed (silent — never block Claude on missing infrastructure)
#   - HEAD ref isn't readable (e.g., empty repo before first commit)

set -uo pipefail

# Locate project root (CLAUDE_PROJECT_DIR is set by Claude Code; fall back to git).
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Read envelope.
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
EXIT=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 1' 2>/dev/null)

# Filter: must be a `git commit` (not `git commit-tree`, etc.) and must have succeeded.
# Match: 'git commit' or 'git commit ' followed by anything, but not 'git commit-tree'.
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac
echo "$CMD" | grep -qE 'git[[:space:]]+commit-tree' && exit 0
[ "$EXIT" != "0" ] && exit 0

# Capture HEAD SHA. If unreadable, no-op silently.
SHA=$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null)
[ -z "$SHA" ] && exit 0

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

LEDGER="$PROJECT_ROOT/.claude/claude-commits.jsonl"
jq -nc \
  --arg sha "$SHA" \
  --arg ts "$TS" \
  --arg sid "$SESSION_ID" \
  '{sha: $sha, timestamp: $ts, session_id: $sid, gate: "passed"}' >> "$LEDGER"

exit 0
```

Make executable:
```bash
chmod +x scripts/hooks/record-claude-commit.sh
```

- [ ] **Step 2.4: Run test, verify pass**

```bash
bash tests/test-record-claude-commit.sh
```
Expected: `Results: 5 passed, 0 failed`.

- [ ] **Step 2.5: Commit**

```bash
git add scripts/hooks/record-claude-commit.sh tests/test-record-claude-commit.sh
git commit -m "feat(bl-030): record-claude-commit PostToolUse hook + claude-commits.jsonl ledger"
```

---

## Task 3: `detect-out-of-band-commits.sh` SessionStart detector

Light-mode core. Also runs on strict (to capture `--no-verify` post-hoc per spec § 8.5). Reads `claude-commits.jsonl`, filters derivative commits, writes `out_of_band_commit` rows to `bypass-audit.json`.

**Files:**
- Create: `scripts/detect-out-of-band-commits.sh`
- Test: `tests/test-out-of-band-detector.sh`

- [ ] **Step 3.1: Write the failing test**

Create `tests/test-out-of-band-detector.sh`:

```bash
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
```

- [ ] **Step 3.2: Run test, verify failures**

```bash
bash tests/test-out-of-band-detector.sh
```
Expected: 8 FAIL.

- [ ] **Step 3.3: Implement the detector**

Create `scripts/detect-out-of-band-commits.sh`:

```bash
#!/usr/bin/env bash
# scripts/detect-out-of-band-commits.sh — BL-030 out-of-band commit detector.
#
# SessionStart hook. Diffs commits since last-checked-commit.txt against
# claude-commits.jsonl. Anything that's reachable in `git log A..HEAD` and
# NOT in the Claude ledger AND NOT a derivative (merge/revert/cherry-pick/
# squash) is recorded as an out_of_band_commit row in bypass-audit.json.
#
# Runs on light AND strict (strict for --no-verify capture). No-ops on
# enforcement_level=no.

set -uo pipefail

PROJECT_ROOT="${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/enforcement-level.sh"

LEVEL=$(read_enforcement_level "$PROJECT_ROOT")
[ "$LEVEL" = "no" ] && exit 0

LEDGER="$PROJECT_ROOT/.claude/claude-commits.jsonl"
AUDIT="$PROJECT_ROOT/.claude/bypass-audit.json"
BASELINE_FILE="$PROJECT_ROOT/.claude/last-checked-commit.txt"

# Initialize empty audit array if missing (BL-029 should provide; defensive).
[ -f "$AUDIT" ] || echo "[]" > "$AUDIT"

# Append a row to the audit array, preserving valid JSON.
append_audit_row() {
  local row="$1"
  local tmp
  tmp=$(mktemp)
  if jq --argjson r "$row" '. + [$r]' "$AUDIT" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$AUDIT"
  else
    rm -f "$tmp"
    echo "[FAIL] detect-out-of-band-commits: failed to append audit row" >&2
  fi
}

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Record a detector_error row and exit non-zero (still surface to stderr).
record_error() {
  local reason="$1"
  local row
  row=$(jq -nc \
    --arg ts "$(ts)" \
    --arg lvl "$LEVEL" \
    --arg reason "$reason" \
    '{timestamp:$ts, session_id:null, type:"detector_error", actor:"framework", enforcement_level_at_event:$lvl, details:{reason:$reason}, user_response:"n/a", final_outcome:"n/a"}')
  append_audit_row "$row"
  echo "[FAIL] detect-out-of-band-commits: $reason" >&2
}

# Establish baseline if missing.
if [ ! -f "$BASELINE_FILE" ]; then
  cd "$PROJECT_ROOT" && git rev-parse HEAD > "$BASELINE_FILE" 2>/dev/null || {
    record_error "could not establish baseline (no HEAD)"
    exit 0
  }
  exit 0
fi

BASELINE=$(cat "$BASELINE_FILE")
[ -z "$BASELINE" ] && { record_error "baseline file empty"; exit 0; }

# Validate ledger is parseable JSONL (or empty).
if [ -s "$LEDGER" ] && ! jq -s '.' "$LEDGER" >/dev/null 2>&1; then
  record_error "claude-commits.jsonl is not valid JSONL"
  exit 0
fi

cd "$PROJECT_ROOT"

# Validate baseline is reachable.
if ! git cat-file -e "$BASELINE" 2>/dev/null; then
  echo "[NOTE] detect-out-of-band-commits: baseline $BASELINE is not reachable — likely rebased/force-pushed. Conservatively flagging everything between origin merge-base and HEAD as out-of-band." >&2
  # Conservative: use the root commit as the baseline.
  BASELINE=$(git rev-list --max-parents=0 HEAD | head -1)
fi

# Build SHA set from ledger.
LEDGER_SHAS=""
if [ -s "$LEDGER" ]; then
  LEDGER_SHAS=$(jq -r '.sha' "$LEDGER" 2>/dev/null | tr '\n' ' ')
fi

is_in_ledger() {
  local sha="$1"
  case " $LEDGER_SHAS " in
    *" $sha "*) return 0 ;;
    *) return 1 ;;
  esac
}

is_derivative() {
  local subject="$1"
  case "$subject" in
    "Merge "*|"Revert "*|"Squashed commit"*|"squash! "*|"fixup! "*) return 0 ;;
  esac
  echo "$subject" | grep -qiE '^(merge|revert)[ :]' && return 0
  echo "$subject" | grep -q "cherry picked from" && return 0
  return 1
}

WROTE_ANY=0
NEW_HEAD=$(git rev-parse HEAD)

# git log <baseline>..HEAD — list new commits, oldest first.
while IFS=$'\t' read -r sha author_ts subject; do
  [ -z "$sha" ] && continue
  if is_in_ledger "$sha"; then continue; fi
  if is_derivative "$subject"; then continue; fi
  row=$(jq -nc \
    --arg ts "$(ts)" \
    --arg lvl "$LEVEL" \
    --arg sha "$sha" \
    --arg ats "$author_ts" \
    --arg subj "$subject" \
    '{timestamp:$ts, session_id:null, type:"out_of_band_commit", actor:"user_terminal_inferred",
      enforcement_level_at_event:$lvl,
      details:{commit_sha:$sha, commit_subject:$subj, author_timestamp:$ats},
      user_response:"n/a", final_outcome:"recorded_only"}')
  append_audit_row "$row"
  WROTE_ANY=$((WROTE_ANY + 1))
done < <(git log --reverse --format='%H%x09%aI%x09%s' "$BASELINE..HEAD" 2>/dev/null)

# Update baseline.
echo "$NEW_HEAD" > "$BASELINE_FILE"

if [ "$WROTE_ANY" -gt 0 ]; then
  echo "⚠ $WROTE_ANY user-terminal commit(s) detected since last session — recorded to .claude/bypass-audit.json." >&2
fi

exit 0
```

Make executable:
```bash
chmod +x scripts/detect-out-of-band-commits.sh
```

- [ ] **Step 3.4: Run test, verify pass**

```bash
bash tests/test-out-of-band-detector.sh
```
Expected: `Results: 8 passed, 0 failed`. If a test fails on default branch name (`main` vs `master`), the test setup uses `git checkout -q main 2>/dev/null || git checkout -q master` — verify your local git default-branch config. Adjust if your local git uses neither.

- [ ] **Step 3.5: Commit**

```bash
git add scripts/detect-out-of-band-commits.sh tests/test-out-of-band-detector.sh
git commit -m "feat(bl-030): out-of-band commit detector — light/strict SessionStart hook"
```

---

## Task 4: `install-filesystem-gates.sh` installer/uninstaller

Idempotent. Adds (or removes) a marked block from `.git/hooks/pre-commit` that sources `framework-gate.sh`. Does not touch gitleaks/Semgrep/TDD blocks.

**Files:**
- Create: `scripts/install-filesystem-gates.sh`
- Test: `tests/test-filesystem-gate-install.sh`

- [ ] **Step 4.1: Write the failing test**

Create `tests/test-filesystem-gate-install.sh`:

```bash
#!/usr/bin/env bash
# tests/test-filesystem-gate-install.sh — BL-030 filesystem-gate installer tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-filesystem-gates.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  ( cd "$TMP"
    git init -q
    git config user.email "t@t.l"
    git config user.name "t"
  )
  mkdir -p "$TMP/.git/hooks"
  # Pre-existing pre-commit with mock gitleaks block.
  cat > "$TMP/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
# >>> gitleaks
echo "running gitleaks"
# <<< gitleaks
EOF
  chmod +x "$TMP/.git/hooks/pre-commit"
  mkdir -p "$TMP/.claude"
}
teardown() { rm -rf "$TMP"; }

# T1: install adds the marked block.
echo "T1: install adds SOIF marker block"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T1" "installer missing (RED)"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if grep -q ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit"; then pass "T1"; else fail_ "T1" "marker not found"; fi
fi
teardown

# T2: install is idempotent — second run does not duplicate.
echo "T2: install is idempotent"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T2" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  count=$(grep -c ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit")
  if [ "$count" = "1" ]; then pass "T2"; else fail_ "T2" "expected 1 marker, got $count"; fi
fi
teardown

# T3: install preserves existing gitleaks block.
echo "T3: install preserves pre-existing content"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T3" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if grep -q "running gitleaks" "$TMP/.git/hooks/pre-commit"; then pass "T3"; else fail_ "T3" "gitleaks block lost"; fi
fi
teardown

# T4: uninstall removes only the marked block.
echo "T4: uninstall removes SOIF marker block but leaves rest"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T4" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  bash "$INSTALLER" --uninstall "$TMP" >/dev/null 2>&1
  if ! grep -q ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit" \
     && grep -q "running gitleaks" "$TMP/.git/hooks/pre-commit"; then pass "T4"; else fail_ "T4" "uninstall left wrong state"; fi
fi
teardown

# T5: install creates pre-commit if it didn't exist.
echo "T5: install creates pre-commit hook from scratch"
setup
rm -f "$TMP/.git/hooks/pre-commit"
if [ ! -f "$INSTALLER" ]; then
  fail_ "T5" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if [ -x "$TMP/.git/hooks/pre-commit" ] && grep -q ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit"; then pass "T5"; else fail_ "T5" "hook not created or marker missing"; fi
fi
teardown

# T6: install also drops framework-gate.sh into .git/hooks/.
echo "T6: install drops framework-gate.sh"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T6" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if [ -x "$TMP/.git/hooks/framework-gate.sh" ]; then pass "T6"; else fail_ "T6" "framework-gate.sh not installed"; fi
fi
teardown

# T7: uninstall does NOT delete framework-gate.sh (defense in depth — script self-no-ops on level change).
echo "T7: uninstall preserves framework-gate.sh"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T7" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  bash "$INSTALLER" --uninstall "$TMP" >/dev/null 2>&1
  if [ -f "$TMP/.git/hooks/framework-gate.sh" ]; then pass "T7"; else fail_ "T7" "framework-gate.sh deleted"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 4.2: Run test, verify failures**

```bash
bash tests/test-filesystem-gate-install.sh
```
Expected: 7 FAIL.

- [ ] **Step 4.3: Implement the installer**

Create `scripts/install-filesystem-gates.sh`:

```bash
#!/usr/bin/env bash
# scripts/install-filesystem-gates.sh — BL-030 strict-mode hook installer.
#
# Idempotently adds (or removes) a marked block in .git/hooks/pre-commit
# that sources .git/hooks/framework-gate.sh. Composes with existing chains
# (gitleaks/Semgrep/TDD) without modifying them.
#
# Usage:
#   install-filesystem-gates.sh --install <project_root>
#   install-filesystem-gates.sh --uninstall <project_root>

set -euo pipefail

MARK_OPEN='# >>> SOIF framework gate (BL-030) — do not edit; managed by install-filesystem-gates.sh'
MARK_CLOSE='# <<< SOIF framework gate'

usage() {
  echo "Usage: $0 --install|--uninstall <project_root>" >&2
  exit 2
}

[ $# -lt 2 ] && usage
ACTION="$1"
PROJECT_ROOT="$2"
[ -d "$PROJECT_ROOT/.git" ] || { echo "[FAIL] not a git repo: $PROJECT_ROOT" >&2; exit 1; }

HOOK="$PROJECT_ROOT/.git/hooks/pre-commit"
GATE="$PROJECT_ROOT/.git/hooks/framework-gate.sh"

write_gate_script() {
  cat > "$GATE" <<'GATE_EOF'
#!/usr/bin/env bash
# .git/hooks/framework-gate.sh — BL-030 strict-mode framework gate.
# Self-no-ops if enforcement_level != "strict" (defense in depth).

set -uo pipefail
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$PROJECT_ROOT/.claude" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

LEVEL=$(jq -r '.enforcement_level // "strict"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null)
[ "$LEVEL" != "strict" ] && exit 0

# Delegate to process-checklist.sh + pre-commit-gate.sh in terminal mode.
SCRIPTS="$PROJECT_ROOT/scripts"
[ -x "$SCRIPTS/process-checklist.sh" ] || exit 0
[ -x "$SCRIPTS/pre-commit-gate.sh" ]   || exit 0

# 1. Phase-prereq + check_commit_ready.
if ! "$SCRIPTS/process-checklist.sh" --check-commit-ready 2>&1; then
  EXIT=$?
  bash "$SCRIPTS/install-filesystem-gates.sh" __record_block "$PROJECT_ROOT" "process-checklist" 2>/dev/null || true
  exit $EXIT
fi

# 2. pre-commit-gate.sh in terminal mode.
if ! "$SCRIPTS/pre-commit-gate.sh" --terminal-mode; then
  EXIT=$?
  bash "$SCRIPTS/install-filesystem-gates.sh" __record_block "$PROJECT_ROOT" "pre-commit-gate" 2>/dev/null || true
  exit $EXIT
fi

# Pass: record terminal_commit_passed row.
bash "$SCRIPTS/install-filesystem-gates.sh" __record_pass "$PROJECT_ROOT" 2>/dev/null || true
exit 0
GATE_EOF
  chmod +x "$GATE"
}

# Internal: write a terminal_commit_blocked or terminal_commit_passed audit row.
# Called by framework-gate.sh via re-invocation.
record_audit_row() {
  local kind="$1"          # "blocked" or "passed"
  local proj="$2"
  local gate_name="${3:-}"
  local audit="$proj/.claude/bypass-audit.json"
  [ -f "$audit" ] || echo "[]" > "$audit"
  command -v jq >/dev/null 2>&1 || return 0
  local ts row tmp type
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ "$kind" = "blocked" ]; then
    type="terminal_commit_blocked"
  else
    type="terminal_commit_passed"
  fi
  row=$(jq -nc \
    --arg ts "$ts" \
    --arg t "$type" \
    --arg g "$gate_name" \
    '{timestamp:$ts, session_id:null, type:$t, actor:"user_terminal", enforcement_level_at_event:"strict", details:{gate:$g}, user_response:"n/a", final_outcome:(if $t=="terminal_commit_blocked" then "abandoned" else "committed" end)}')
  tmp=$(mktemp)
  if jq --argjson r "$row" '. + [$r]' "$audit" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$audit"
  else
    rm -f "$tmp"
  fi
}

case "$ACTION" in
  --install)
    write_gate_script
    if [ ! -f "$HOOK" ]; then
      cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
EOF
      chmod +x "$HOOK"
    fi
    if grep -qF "$MARK_OPEN" "$HOOK"; then
      exit 0
    fi
    {
      echo ""
      echo "$MARK_OPEN"
      echo 'if [ -f "$(git rev-parse --show-toplevel)/.git/hooks/framework-gate.sh" ]; then'
      echo '  bash "$(git rev-parse --show-toplevel)/.git/hooks/framework-gate.sh" || exit $?'
      echo 'fi'
      echo "$MARK_CLOSE"
    } >> "$HOOK"
    chmod +x "$HOOK"
    ;;
  --uninstall)
    [ -f "$HOOK" ] || exit 0
    if ! grep -qF "$MARK_OPEN" "$HOOK"; then
      exit 0
    fi
    tmp=$(mktemp)
    awk -v open="$MARK_OPEN" -v close="$MARK_CLOSE" '
      $0 == open { skipping = 1; next }
      skipping && $0 == close { skipping = 0; next }
      !skipping
    ' "$HOOK" > "$tmp"
    mv "$tmp" "$HOOK"
    chmod +x "$HOOK"
    ;;
  __record_block)
    record_audit_row "blocked" "$2" "${3:-unknown}"
    ;;
  __record_pass)
    record_audit_row "passed" "$2"
    ;;
  *)
    usage
    ;;
esac
```

Make executable:
```bash
chmod +x scripts/install-filesystem-gates.sh
```

- [ ] **Step 4.4: Run test, verify pass**

```bash
bash tests/test-filesystem-gate-install.sh
```
Expected: `Results: 7 passed, 0 failed`.

- [ ] **Step 4.5: Commit**

```bash
git add scripts/install-filesystem-gates.sh tests/test-filesystem-gate-install.sh
git commit -m "feat(bl-030): filesystem-gate installer + framework-gate.sh template"
```

---

## Task 5: `pre-commit-gate.sh --terminal-mode` flag

Add a flag to the existing `pre-commit-gate.sh` that lets `framework-gate.sh` invoke the same gate logic with user-terminal-shaped inputs (commit message from `COMMIT_EDITMSG`, staged files from `git diff --cached`, output to stderr).

**Files:**
- Modify: `scripts/pre-commit-gate.sh`
- Test: `tests/test-pre-commit-gate-terminal-mode.sh`

- [ ] **Step 5.1: Read existing `pre-commit-gate.sh` to find the entry point**

```bash
head -80 scripts/pre-commit-gate.sh
```

Identify (a) where the script reads its stdin JSON, (b) where it computes the `command` variable, (c) where it emits the JSON permission decision. The `--terminal-mode` flag must short-circuit (a) and (c) while reusing the staged-file classifier and the gate-firing logic.

- [ ] **Step 5.2: Write the failing test**

Create `tests/test-pre-commit-gate-terminal-mode.sh`:

```bash
#!/usr/bin/env bash
# tests/test-pre-commit-gate-terminal-mode.sh — BL-030 --terminal-mode flag tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  ( cd "$TMP"
    git init -q
    git config user.email "t@t.l"
    git config user.name "t"
  )
  mkdir -p "$TMP/.claude"
  cat > "$TMP/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  cat > "$TMP/.claude/phase-state.json" <<EOF
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
EOF
  cat > "$TMP/.claude/process-state.json" <<EOF
{"phase2_init":{"steps_completed":["remote_repo_created"],"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
EOF
  ( cd "$TMP" && git remote add origin https://example.com/x.git 2>/dev/null || true )
}
teardown() { rm -rf "$TMP"; }

# T1: --terminal-mode reads from COMMIT_EDITMSG and emits human-readable to stderr.
echo "T1: --terminal-mode reads COMMIT_EDITMSG, emits stderr"
setup
( cd "$TMP" && echo source > src.go && git add src.go )
echo "feat: add x" > "$TMP/.git/COMMIT_EDITMSG"
out=$( cd "$TMP" && bash "$GATE" --terminal-mode 2>&1 >/dev/null || true )
# In strict mode with no Build Loop progress, this should block (Phase 2 + source file + feat: prefix).
if echo "$out" | grep -qE '\[FRAMEWORK GATE|FAIL|Block reason'; then pass "T1"; else fail_ "T1" "no human-readable block on stderr: $out"; fi
teardown

# T2: --terminal-mode exits 0 on docs-only commit (existing classifier reused).
echo "T2: --terminal-mode passes a docs-only commit"
setup
( cd "$TMP" && echo "# README" > README.md && git add README.md )
echo "docs: add README" > "$TMP/.git/COMMIT_EDITMSG"
( cd "$TMP" && bash "$GATE" --terminal-mode >/dev/null 2>&1 ) && pass "T2" || fail_ "T2" "docs-only commit blocked"
teardown

# T3: --terminal-mode does NOT emit JSON to stdout.
echo "T3: --terminal-mode does not emit JSON permission decision"
setup
( cd "$TMP" && echo source > src.go && git add src.go )
echo "feat: add x" > "$TMP/.git/COMMIT_EDITMSG"
out=$( cd "$TMP" && bash "$GATE" --terminal-mode 2>/dev/null || true )
if ! echo "$out" | grep -q "permissionDecision"; then pass "T3"; else fail_ "T3" "JSON permission decision leaked to stdout"; fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 5.3: Run test, verify failures**

```bash
bash tests/test-pre-commit-gate-terminal-mode.sh
```
Expected: 3 FAIL.

- [ ] **Step 5.4: Implement `--terminal-mode`**

Edit `scripts/pre-commit-gate.sh`. Find the script's argument-parsing region (near top) and add:

```bash
# BL-030: --terminal-mode invocation from .git/hooks/framework-gate.sh.
# Reads commit message from .git/COMMIT_EDITMSG instead of stdin JSON;
# reads staged files from `git diff --cached` instead of tool-input;
# emits human-readable diagnostics to stderr instead of JSON to stdout.
TERMINAL_MODE=0
for arg in "$@"; do
  case "$arg" in
    --terminal-mode) TERMINAL_MODE=1 ;;
  esac
done

if [ "$TERMINAL_MODE" -eq 1 ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "[FAIL] not a git repo" >&2; exit 1; }
  cd "$PROJECT_ROOT"
  COMMIT_MSG=$(cat .git/COMMIT_EDITMSG 2>/dev/null || echo "")
  STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)

  # Reuse process-checklist.sh's classifier.
  if [ -x "scripts/process-checklist.sh" ]; then
    if ! bash scripts/process-checklist.sh --check-commit-message "$COMMIT_MSG" 2>&1 >&2; then
      echo "" >&2
      echo "[FRAMEWORK GATE — strict mode]" >&2
      echo "" >&2
      echo "Block reason: commit message classifier rejected the message under current Phase / Build Loop state." >&2
      echo "" >&2
      echo "Why this rule exists:" >&2
      echo "  Phase 2 'feat:' commits must be preceded by an open Build Loop with the first 5" >&2
      echo "  steps complete (tests written, tests verified failing, implemented, security audit," >&2
      echo "  documentation updated). The classifier prevents 'feat:' commits that haven't earned" >&2
      echo "  the right to claim a feature was added — the framework's value is only as strong as" >&2
      echo "  the discipline of its commit boundary." >&2
      echo "" >&2
      echo "To proceed:" >&2
      echo "  Open a Build Loop:  scripts/process-checklist.sh --start-feature \"<name>\"" >&2
      echo "  Complete steps:     scripts/process-checklist.sh --complete-step build_loop:tests_written" >&2
      echo "  ...then commit again." >&2
      echo "" >&2
      echo "To bypass anyway (recorded in .claude/bypass-audit.json):" >&2
      echo "  git commit --no-verify ..." >&2
      echo "" >&2
      echo "To downgrade enforcement permanently:" >&2
      echo "  scripts/reconfigure-project.sh --enforcement-level light" >&2
      exit 1
    fi
  fi

  exit 0
fi

# (existing pre-commit-gate.sh logic continues below — Claude PreToolUse path)
```

Place this block immediately after the script's existing `set -euo pipefail` (or equivalent prologue) and before the existing JSON-from-stdin reader.

- [ ] **Step 5.5: Run test, verify pass**

```bash
bash tests/test-pre-commit-gate-terminal-mode.sh
```
Expected: `Results: 3 passed, 0 failed`.

- [ ] **Step 5.6: Run regression suite**

```bash
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1 && echo "PASS $(basename "$t")" || echo "FAIL $(basename "$t")"; done
```
Expected: every existing pre-commit-gate test still passes (no regression in Claude PreToolUse path). Investigate any FAIL before proceeding.

- [ ] **Step 5.7: Commit**

```bash
git add scripts/pre-commit-gate.sh tests/test-pre-commit-gate-terminal-mode.sh
git commit -m "feat(bl-030): pre-commit-gate.sh --terminal-mode for filesystem-gate composition"
```

---

## Task 6: Block-message teaching pattern (W5/P1) — per-gate explanation table

Each gate that can fire from the strict-mode `framework-gate.sh` path needs a "Why this rule exists" paragraph alongside its block message. To avoid drift between the gate code and the docs, ship the explanations inline as a small lookup table sourced by the gate.

**Files:**
- Create: `scripts/lib/gate-principles.sh`
- Modify: Replace inline strings in Task 5 step 5.4 with calls to `principle_for "<gate_name>"`.
- Test: `tests/test-gate-principles.sh`

- [ ] **Step 6.1: Write the failing test**

Create `tests/test-gate-principles.sh`:

```bash
#!/usr/bin/env bash
# tests/test-gate-principles.sh — BL-030 block-message principle table tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/gate-principles.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if [ ! -f "$LIB" ]; then
  fail_ "lib-exists" "scripts/lib/gate-principles.sh missing (RED)"
else
  # shellcheck disable=SC1090
  source "$LIB"

  # T1: principle_for("commit-classifier") returns non-empty multiline content.
  out=$(principle_for "commit-classifier" 2>/dev/null)
  if echo "$out" | grep -q "discipline of its commit boundary"; then pass "T1: commit-classifier"; else fail_ "T1" "missing or wrong"; fi

  # T2: principle_for("phase-prereq") returns non-empty content.
  out=$(principle_for "phase-prereq" 2>/dev/null)
  if [ -n "$out" ] && echo "$out" | grep -q "remote"; then pass "T2: phase-prereq"; else fail_ "T2" "missing"; fi

  # T3: principle_for("unknown-gate") returns a generic fallback rather than failing.
  out=$(principle_for "totally-fake-gate" 2>/dev/null)
  if [ -n "$out" ]; then pass "T3: fallback"; else fail_ "T3" "no fallback"; fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 6.2: Run, verify failure**

```bash
bash tests/test-gate-principles.sh
```
Expected: 3 FAIL.

- [ ] **Step 6.3: Implement principle table**

Create `scripts/lib/gate-principles.sh`:

```bash
# scripts/lib/gate-principles.sh — BL-030 block-message principle lookup.
#
# Every block message printed by the strict-mode framework gate must carry
# both the procedure (what to do to unblock) AND the principle (why the
# rule exists). This library provides the principle text. Keeping it
# co-located with the gate logic avoids drift between docs and behavior.

# shellcheck shell=bash

# principle_for <gate_name>
# Echoes the multi-line "Why this rule exists" paragraph for <gate_name>.
# Returns 0 always (echoes a generic fallback for unknown gates).
principle_for() {
  local gate="${1:-}"
  case "$gate" in
    commit-classifier)
      cat <<'EOF'
  Phase 2 'feat:' commits must be preceded by an open Build Loop with
  the first 5 steps complete (tests written, tests verified failing,
  implemented, security audit, documentation updated). The classifier
  prevents 'feat:' commits that haven't earned the right to claim a
  feature was added — the framework's value is only as strong as the
  discipline of its commit boundary.
EOF
      ;;
    phase-prereq)
      cat <<'EOF'
  Phase 2 (Build Loop, source commits) requires a configured remote so
  every commit has a durable home and the framework's audit trail
  survives a local disk loss. Without a remote, work that looks committed
  exists only in one place — handoff-readiness (the framework's central
  value prop) is structurally impossible. This rule fired because Phase 2
  was claimed but no git remote is configured.
EOF
      ;;
    build-loop)
      cat <<'EOF'
  Source commits in Phase 2 must be preceded by a complete Build Loop:
  tests written, tests verified failing, implementation, security audit,
  documentation updated. Skipping a step writes code without the
  discipline that makes it auditable, testable, and handoff-ready. The
  block fires when one of these steps is missing for the current feature.
EOF
      ;;
    *)
      cat <<'EOF'
  This block fires when a framework gate detects a process violation.
  The gate name above identifies which rule fired; consult the user
  guide (docs/user-guide.md) for the principle behind the specific gate.
EOF
      ;;
  esac
}
```

- [ ] **Step 6.4: Run test, verify pass**

```bash
bash tests/test-gate-principles.sh
```
Expected: `Results: 3 passed, 0 failed`.

- [ ] **Step 6.5: Refactor Task 5's inline string to use the library**

Edit `scripts/pre-commit-gate.sh` — replace the inline "Why this rule exists" paragraph from Task 5 step 5.4 with:

```bash
      # shellcheck disable=SC1091
      source "$PROJECT_ROOT/scripts/lib/gate-principles.sh"
      echo "" >&2
      echo "[FRAMEWORK GATE — strict mode]" >&2
      echo "" >&2
      echo "Block reason: commit message classifier rejected the message under current Phase / Build Loop state." >&2
      echo "" >&2
      echo "Why this rule exists:" >&2
      principle_for "commit-classifier" >&2
      echo "" >&2
      echo "To proceed:" >&2
      ...
```

Re-run `bash tests/test-pre-commit-gate-terminal-mode.sh` to confirm no regression.

- [ ] **Step 6.6: Commit**

```bash
git add scripts/lib/gate-principles.sh tests/test-gate-principles.sh scripts/pre-commit-gate.sh
git commit -m "feat(bl-030): gate-principles library — W5/P1 teaching pattern in block messages"
```

---

## Task 7: `init.sh` modifications — interactive UX + non-interactive flags

The longest task. Adds the enforcement-level prompt for choosable modes; forces strict for non-choosable; shows pitfall blocks on downgrade; persists to manifest; calls the filesystem-gate installer if strict; initializes `last-checked-commit.txt`; supports `--enforcement-level <level> [--confirm-pitfalls]`.

**Files:**
- Modify: `init.sh`
- Test: `tests/test-enforcement-level-init.sh`

- [ ] **Step 7.1: Read existing `init.sh` flow at lines 339–386**

```bash
sed -n '339,400p' init.sh
```
Identify (a) where `TRACK`, `DEPLOYMENT`, `POC_MODE` are resolved, (b) where the manifest is written (search for `enforcement_level`-adjacent fields like `track`, `deployment`, `poc_mode`), (c) where the non-interactive flag table is parsed.

- [ ] **Step 7.2: Write the failing test**

Create `tests/test-enforcement-level-init.sh`:

```bash
#!/usr/bin/env bash
# tests/test-enforcement-level-init.sh — BL-030 init UX tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# All tests use init.sh non-interactive mode (BL-016) to avoid heredoc fragility.

run_init() {
  local proj="$1"; shift
  ( cd "$REPO_ROOT" && bash "$INIT" --non-interactive --project-dir "$proj" --no-remote-creation \
      --project-name testproj --platform other --language other "$@" >/dev/null 2>&1 )
}

# T1: personal + default → enforcement_level=strict.
echo "T1: personal default = strict"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" --track light --deployment personal && {
  level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
  if [ "$level" = "strict" ]; then pass "T1"; else fail_ "T1" "got $level"; fi
} || fail_ "T1" "init failed"
rm -rf "$TMP"

# T2: organizational + sponsored_poc + --enforcement-level light → ignored, manifest is strict.
echo "T2: org+sponsored_poc forces strict (flag ignored)"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" --track standard --deployment organizational --gov-mode sponsored_poc \
  --enforcement-level light --confirm-pitfalls && {
  level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
  if [ "$level" = "strict" ]; then pass "T2"; else fail_ "T2" "got $level"; fi
} || fail_ "T2" "init failed"
rm -rf "$TMP"

# T3: personal + --enforcement-level light + --confirm-pitfalls → manifest is light.
echo "T3: personal + --enforcement-level light --confirm-pitfalls → light"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" --track light --deployment personal --enforcement-level light --confirm-pitfalls && {
  level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
  if [ "$level" = "light" ]; then pass "T3"; else fail_ "T3" "got $level"; fi
} || fail_ "T3" "init failed"
rm -rf "$TMP"

# T4: --enforcement-level no without --confirm-pitfalls → init exits non-zero.
echo "T4: --enforcement-level no without --confirm-pitfalls fails"
TMP=$(mktemp -d); PROJ="$TMP/p"
( cd "$REPO_ROOT" && bash "$INIT" --non-interactive --project-dir "$PROJ" --no-remote-creation \
    --project-name x --platform other --language other --track light --deployment personal \
    --enforcement-level no >/dev/null 2>&1 )
if [ $? -ne 0 ]; then pass "T4"; else fail_ "T4" "expected non-zero exit"; fi
rm -rf "$TMP"

# T5: init writes last-checked-commit.txt to current HEAD.
echo "T5: init initializes last-checked-commit.txt"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" --track light --deployment personal && {
  if [ -f "$PROJ/.claude/last-checked-commit.txt" ] && [ -s "$PROJ/.claude/last-checked-commit.txt" ]; then
    pass "T5"
  else
    fail_ "T5" "last-checked-commit.txt missing or empty"
  fi
} || fail_ "T5" "init failed"
rm -rf "$TMP"

# T6: strict init installs filesystem-gate.
echo "T6: strict init installs framework-gate.sh + marker block"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" --track light --deployment personal && {
  if grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null \
     && [ -x "$PROJ/.git/hooks/framework-gate.sh" ]; then
    pass "T6"
  else
    fail_ "T6" "filesystem gate not installed"
  fi
} || fail_ "T6" "init failed"
rm -rf "$TMP"

# T7: light init does NOT install filesystem-gate.
echo "T7: light init skips filesystem-gate install"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" --track light --deployment personal --enforcement-level light --confirm-pitfalls && {
  if ! grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then
    pass "T7"
  else
    fail_ "T7" "filesystem gate installed in light mode"
  fi
} || fail_ "T7" "init failed"
rm -rf "$TMP"

# T8: init appends an enforcement_level_set audit row.
echo "T8: init writes enforcement_level_set audit row"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" --track light --deployment personal && {
  rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json" 2>/dev/null || echo 0)
  if [ "$rows" -ge "1" ]; then pass "T8"; else fail_ "T8" "rows=$rows"; fi
} || fail_ "T8" "init failed"
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 7.3: Run test, verify failures**

```bash
bash tests/test-enforcement-level-init.sh
```
Expected: 8 FAIL.

- [ ] **Step 7.4: Implement non-interactive flag parsing**

Find `init.sh`'s non-interactive flag parser (added by BL-016). Add cases for `--enforcement-level` and `--confirm-pitfalls`:

```bash
    --enforcement-level)
      ENFORCEMENT_LEVEL="${2:-}"
      shift 2
      ;;
    --confirm-pitfalls)
      CONFIRM_PITFALLS=1
      shift
      ;;
```

Default values near other defaults:
```bash
ENFORCEMENT_LEVEL="${ENFORCEMENT_LEVEL:-}"
CONFIRM_PITFALLS="${CONFIRM_PITFALLS:-0}"
```

- [ ] **Step 7.5: Implement enforcement-level resolution**

After `TRACK`/`DEPLOYMENT`/`POC_MODE` resolution (around init.sh:386), add this block:

```bash
# BL-030: resolve enforcement_level.
# Choosable iff deployment=personal OR (organizational AND poc_mode=private_poc).
# Otherwise forced strict.
_choosable=0
if [ "$DEPLOYMENT" = "personal" ]; then _choosable=1; fi
if [ "$DEPLOYMENT" = "organizational" ] && [ "$POC_MODE" = "private_poc" ]; then _choosable=1; fi

if [ "$_choosable" = "0" ]; then
  if [ -n "$ENFORCEMENT_LEVEL" ] && [ "$ENFORCEMENT_LEVEL" != "strict" ]; then
    print_warn "Enforcement level '$ENFORCEMENT_LEVEL' ignored — sponsored_poc/production force strict."
  fi
  ENFORCEMENT_LEVEL="strict"
else
  if [ "$NON_INTERACTIVE" = "1" ]; then
    # Non-interactive: default strict; downgrade requires --confirm-pitfalls.
    if [ -z "$ENFORCEMENT_LEVEL" ]; then
      ENFORCEMENT_LEVEL="strict"
    fi
    case "$ENFORCEMENT_LEVEL" in
      strict) ;;
      light|no)
        if [ "$CONFIRM_PITFALLS" != "1" ]; then
          print_fail "Non-interactive downgrade to '$ENFORCEMENT_LEVEL' requires --confirm-pitfalls (see docs/superpowers/specs/2026-04-28-bl030-enforcement-model-design.md § 7.5)."
          exit 1
        fi
        ;;
      *)
        print_fail "Unknown --enforcement-level '$ENFORCEMENT_LEVEL' (expected: no | light | strict)."
        exit 1
        ;;
    esac
  else
    # Interactive: prompt + pitfall blocks.
    echo ""
    echo -e "  ${BOLD}Enforcement Level:${NC}"
    echo "    strict — Framework gates apply to BOTH Claude and your terminal. Recommended."
    echo "    light  — Framework gates apply to Claude only. User-terminal commits are"
    echo "             recorded but not blocked."
    echo "    no     — Framework gates apply to Claude only. User-terminal commits are NOT recorded."
    echo ""
    while true; do
      ENFORCEMENT_LEVEL=$(prompt_choice "Enforcement level:" "strict" "light" "no")
      ENFORCEMENT_LEVEL="${ENFORCEMENT_LEVEL#"${ENFORCEMENT_LEVEL%%[![:space:]]*}"}"
      if [ "$ENFORCEMENT_LEVEL" = "strict" ]; then break; fi
      # Show pitfall block.
      echo ""
      cat <<'PITFALL_LIGHT'
  You picked: light enforcement.

  What you're trading away:
    • Real-time block on user-terminal commits that violate framework rules.
    • Symmetric discipline. Claude follows the rules; you'll be free not to.

  What you keep:
    • Claude is still gated.
    • Every user-terminal commit is recorded in .claude/bypass-audit.json
      on next session start.

  When this is the wrong choice:
    • You're learning. Light teaches you to bypass when convenient.
    • A successor will inherit this project.
PITFALL_LIGHT
      if [ "$ENFORCEMENT_LEVEL" = "no" ]; then
        echo ""
        cat <<'PITFALL_NO'
  You picked: no enforcement.

  What you're trading away:
    • Everything light gives you, plus visibility into your own commits.
    • The framework's W7 handoff-readiness story.

  When this is the wrong choice:
    • Anything you might keep for more than a week.
    • Anything someone else might touch.
PITFALL_NO
      fi
      echo ""
      local _confirm
      read -rp "$(echo -e "  ${BOLD}Confirm $ENFORCEMENT_LEVEL? [y/N]${NC}: ")" _confirm
      if [[ "$_confirm" =~ ^[Yy] ]]; then
        CONFIRM_PITFALLS=1
        break
      fi
    done
  fi
fi
```

- [ ] **Step 7.6: Persist enforcement_level to manifest**

Find the manifest-write block in init.sh (search for `"track":` to locate the jq invocation). Add `enforcement_level`:

```bash
  # In the existing jq pipeline that builds manifest.json content:
  --arg enforcement_level "$ENFORCEMENT_LEVEL" \
  ...
  '{ ... existing fields ..., enforcement_level: $enforcement_level, ... }'
```

- [ ] **Step 7.7: Initialize last-checked-commit.txt + audit row + filesystem-gate install**

After the manifest write completes, add:

```bash
# BL-030: initialize detection baseline + audit row + (if strict) filesystem gate.
if [ -d "$PROJECT_DIR/.git" ]; then
  ( cd "$PROJECT_DIR" && git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt ) || true
fi

# Initialize bypass-audit.json if BL-029 hasn't already.
[ -f "$PROJECT_DIR/.claude/bypass-audit.json" ] || echo "[]" > "$PROJECT_DIR/.claude/bypass-audit.json"

# Append enforcement_level_set row.
if command -v jq >/dev/null 2>&1; then
  _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  _row=$(jq -nc \
    --arg ts "$_ts" \
    --arg lvl "$ENFORCEMENT_LEVEL" \
    --arg confirmed "$CONFIRM_PITFALLS" \
    '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"framework",
      enforcement_level_at_event:$lvl,
      details:{level:$lvl, confirmed_pitfalls:($confirmed=="1"), source:"init"},
      user_response:"n/a", final_outcome:"recorded_only"}')
  _tmp=$(mktemp)
  jq --argjson r "$_row" '. + [$r]' "$PROJECT_DIR/.claude/bypass-audit.json" > "$_tmp" \
    && mv "$_tmp" "$PROJECT_DIR/.claude/bypass-audit.json"
fi

# If strict, install the filesystem gate.
if [ "$ENFORCEMENT_LEVEL" = "strict" ]; then
  bash "$SCRIPT_DIR/scripts/install-filesystem-gates.sh" --install "$PROJECT_DIR" || \
    print_warn "filesystem-gate install failed — strict enforcement degraded."
fi
```

- [ ] **Step 7.8: Run test, verify pass**

```bash
bash tests/test-enforcement-level-init.sh
```
Expected: `Results: 8 passed, 0 failed`. Likely you'll need 1-2 iterations on flag-parsing edge cases.

- [ ] **Step 7.9: Run full regression suite**

```bash
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1 && echo "PASS $(basename "$t")" || echo "FAIL $(basename "$t")"; done
```
All existing tests must still pass (especially `tests/test-init-non-interactive.sh`, `tests/test-init-edge-cases.sh`, `tests/test-init-no-remote-creation.sh`).

- [ ] **Step 7.10: Commit**

```bash
git add init.sh tests/test-enforcement-level-init.sh
git commit -m "feat(bl-030): init.sh enforcement-level UX (interactive prompt, pitfall blocks, non-interactive flags)"
```

---

## Task 8: `reconfigure-project.sh --enforcement-level` flag

Post-init transition path. Validates choosability; runs filesystem-gate installer/uninstaller; appends audit row.

**Files:**
- Modify: `scripts/reconfigure-project.sh`
- Test: `tests/test-enforcement-level-reconfigure.sh`

- [ ] **Step 8.1: Read existing `reconfigure-project.sh` to find flag-handling pattern**

```bash
head -120 scripts/reconfigure-project.sh
```

- [ ] **Step 8.2: Write the failing test**

Create `tests/test-enforcement-level-reconfigure.sh`:

```bash
#!/usr/bin/env bash
# tests/test-enforcement-level-reconfigure.sh — BL-030 reconfigure tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECONFIG="$REPO_ROOT/scripts/reconfigure-project.sh"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_personal() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  ( cd "$REPO_ROOT" && bash "$INIT" --non-interactive --project-dir "$PROJ" --no-remote-creation \
      --project-name x --platform other --language other --track light --deployment personal \
      >/dev/null 2>&1 ) || return 1
}
setup_org_production() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  ( cd "$REPO_ROOT" && bash "$INIT" --non-interactive --project-dir "$PROJ" --no-remote-creation \
      --project-name x --platform other --language other --track standard --deployment organizational \
      >/dev/null 2>&1 ) || return 1
}
teardown() { rm -rf "$TMP"; }

# T1: strict→light on personal with --confirm-pitfalls succeeds.
echo "T1: strict→light on personal succeeds with --confirm-pitfalls"
setup_personal && {
  ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 ) && {
    level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
    if [ "$level" = "light" ]; then pass "T1"; else fail_ "T1" "level=$level"; fi
  } || fail_ "T1" "reconfigure failed"
}
teardown

# T2: strict→light on personal WITHOUT --confirm-pitfalls fails.
echo "T2: strict→light without --confirm-pitfalls fails"
setup_personal && {
  ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light >/dev/null 2>&1 )
  if [ $? -ne 0 ]; then pass "T2"; else fail_ "T2" "expected non-zero"; fi
}
teardown

# T3: any→light on org+production fails.
echo "T3: org+production rejects --enforcement-level light"
setup_org_production && {
  ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 )
  if [ $? -ne 0 ]; then pass "T3"; else fail_ "T3" "expected non-zero"; fi
}
teardown

# T4: light→strict installs filesystem gate.
echo "T4: light→strict installs filesystem gate"
TMP=$(mktemp -d); PROJ="$TMP/p"
( cd "$REPO_ROOT" && bash "$INIT" --non-interactive --project-dir "$PROJ" --no-remote-creation \
    --project-name x --platform other --language other --track light --deployment personal \
    --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 )
( cd "$PROJ" && bash "$RECONFIG" --enforcement-level strict >/dev/null 2>&1 ) && {
  if grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then pass "T4"; else fail_ "T4" "marker not added"; fi
} || fail_ "T4" "reconfigure failed"
teardown

# T5: strict→light uninstalls filesystem gate.
echo "T5: strict→light uninstalls filesystem gate"
setup_personal && {
  ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 ) && {
    if ! grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then pass "T5"; else fail_ "T5" "marker still present"; fi
  } || fail_ "T5" "reconfigure failed"
}
teardown

# T6: each transition appends one enforcement_level_set audit row.
echo "T6: transitions are recorded in audit log"
setup_personal && {
  initial=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
  ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 )
  after=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
  if [ "$after" = "$((initial + 1))" ]; then pass "T6"; else fail_ "T6" "rows: $initial → $after"; fi
}
teardown

# T7: --reset-detection-baseline writes current HEAD.
echo "T7: --reset-detection-baseline updates last-checked-commit.txt"
setup_personal && {
  ( cd "$PROJ" && echo z > z && git add z && git commit -qm z )
  expected=$(cd "$PROJ" && git rev-parse HEAD)
  ( cd "$PROJ" && bash "$RECONFIG" --reset-detection-baseline >/dev/null 2>&1 ) && {
    actual=$(cat "$PROJ/.claude/last-checked-commit.txt")
    if [ "$actual" = "$expected" ]; then pass "T7"; else fail_ "T7" "$expected vs $actual"; fi
  } || fail_ "T7" "reconfigure failed"
}
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 8.3: Run, verify failure**

```bash
bash tests/test-enforcement-level-reconfigure.sh
```
Expected: 7 FAIL.

- [ ] **Step 8.4: Implement reconfigure flags**

Add to `scripts/reconfigure-project.sh` argument parser:

```bash
    --enforcement-level)
      RECONF_LEVEL="${2:-}"; shift 2 ;;
    --confirm-pitfalls)
      RECONF_CONFIRM=1; shift ;;
    --reset-detection-baseline)
      RECONF_RESET_BASELINE=1; shift ;;
```

Add a new action handler (after the script identifies the project root):

```bash
# BL-030: --enforcement-level transition.
if [ -n "${RECONF_LEVEL:-}" ]; then
  source "$SCRIPT_DIR/scripts/lib/enforcement-level.sh"
  if ! validate_transition "$PROJECT_ROOT" "$RECONF_LEVEL"; then
    exit 1
  fi
  current=$(read_enforcement_level "$PROJECT_ROOT")
  case "$RECONF_LEVEL" in
    light|no)
      if [ "${RECONF_CONFIRM:-0}" != "1" ]; then
        print_fail "Downgrade to '$RECONF_LEVEL' requires --confirm-pitfalls."
        echo "  See docs/superpowers/specs/2026-04-28-bl030-enforcement-model-design.md § 10." >&2
        exit 1
      fi
      ;;
  esac
  # Update manifest.
  tmp=$(mktemp)
  jq --arg lvl "$RECONF_LEVEL" '.enforcement_level = $lvl' "$PROJECT_ROOT/.claude/manifest.json" > "$tmp" \
    && mv "$tmp" "$PROJECT_ROOT/.claude/manifest.json"
  # Audit row.
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  row=$(jq -nc \
    --arg ts "$ts" --arg lvl "$RECONF_LEVEL" --arg from "$current" \
    '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"framework",
      enforcement_level_at_event:$lvl,
      details:{level:$lvl, from:$from, source:"reconfigure"},
      user_response:"n/a", final_outcome:"recorded_only"}')
  tmp=$(mktemp)
  jq --argjson r "$row" '. + [$r]' "$PROJECT_ROOT/.claude/bypass-audit.json" > "$tmp" \
    && mv "$tmp" "$PROJECT_ROOT/.claude/bypass-audit.json"
  # Install or uninstall filesystem gate.
  if [ "$RECONF_LEVEL" = "strict" ]; then
    bash "$SCRIPT_DIR/scripts/install-filesystem-gates.sh" --install "$PROJECT_ROOT"
  else
    bash "$SCRIPT_DIR/scripts/install-filesystem-gates.sh" --uninstall "$PROJECT_ROOT"
  fi
  # Initialize baseline if missing.
  if [ ! -f "$PROJECT_ROOT/.claude/last-checked-commit.txt" ]; then
    ( cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt ) || true
  fi
  print_ok "Enforcement level: $current → $RECONF_LEVEL"
  exit 0
fi

# BL-030: --reset-detection-baseline.
if [ "${RECONF_RESET_BASELINE:-0}" = "1" ]; then
  ( cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt )
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  row=$(jq -nc --arg ts "$ts" \
    '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"framework",
      enforcement_level_at_event:"unknown",
      details:{action:"detector_baseline_reset", source:"reconfigure"},
      user_response:"n/a", final_outcome:"recorded_only"}')
  tmp=$(mktemp)
  jq --argjson r "$row" '. + [$r]' "$PROJECT_ROOT/.claude/bypass-audit.json" > "$tmp" \
    && mv "$tmp" "$PROJECT_ROOT/.claude/bypass-audit.json"
  print_ok "Detection baseline reset to current HEAD."
  exit 0
fi
```

- [ ] **Step 8.5: Run test, verify pass**

```bash
bash tests/test-enforcement-level-reconfigure.sh
```
Expected: `Results: 7 passed, 0 failed`.

- [ ] **Step 8.6: Commit**

```bash
git add scripts/reconfigure-project.sh tests/test-enforcement-level-reconfigure.sh
git commit -m "feat(bl-030): reconfigure-project.sh --enforcement-level + --reset-detection-baseline"
```

---

## Task 9: Wire SessionStart + PostToolUse hooks into the project template

The project-level `.claude/settings.json` template needs the new hook entries so freshly-init'd projects fire the detector and the recorder.

**Files:**
- Modify: `init.sh` (where it writes `.claude/settings.json`) OR the templates directory if hooks are templated.

- [ ] **Step 9.1: Locate the settings.json hook-installation block**

```bash
grep -n "PostToolUse\|SessionStart\|settings.json" init.sh | head -30
```

Read the relevant lines. The existing pattern (per init.sh:1564–1578 in the handoff context) is:

```bash
if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("track-tool-usage.sh"))' .claude/settings.json >/dev/null 2>&1; then
  jq '.hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh"}]' ...
```

Mirror this for `record-claude-commit.sh` (PostToolUse) and `detect-out-of-band-commits.sh` (SessionStart).

- [ ] **Step 9.2: Add the entries**

In init.sh, alongside the existing PostToolUse track-tool-usage block, add:

```bash
# BL-030: PostToolUse hook for Claude-commit recorder (always-on).
if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("record-claude-commit.sh"))' .claude/settings.json >/dev/null 2>&1; then
  jq '.hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/record-claude-commit.sh"}]' .claude/settings.json > .claude/settings.json.tmp \
    && mv .claude/settings.json.tmp .claude/settings.json
fi

# BL-030: SessionStart hook for out-of-band detector (light + strict; self-no-op on no).
if ! jq -e '.hooks.SessionStart[0].hooks[]? | select(.command | contains("detect-out-of-band-commits.sh"))' .claude/settings.json >/dev/null 2>&1; then
  jq 'if (.hooks.SessionStart // []) | length == 0
      then .hooks.SessionStart = [{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/detect-out-of-band-commits.sh"}]}]
      else .hooks.SessionStart[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/detect-out-of-band-commits.sh"}]
      end' .claude/settings.json > .claude/settings.json.tmp \
    && mv .claude/settings.json.tmp .claude/settings.json
fi
```

- [ ] **Step 9.3: Add the scripts to init.sh's copy list**

Find the `cp scripts/...` block (around init.sh:1099 per handoff context) and add:

```bash
cp "$SCRIPT_DIR/scripts/detect-out-of-band-commits.sh"   scripts/
cp "$SCRIPT_DIR/scripts/install-filesystem-gates.sh"     scripts/
mkdir -p scripts/hooks
cp "$SCRIPT_DIR/scripts/hooks/record-claude-commit.sh"   scripts/hooks/
cp "$SCRIPT_DIR/scripts/lib/enforcement-level.sh"        scripts/lib/
cp "$SCRIPT_DIR/scripts/lib/gate-principles.sh"          scripts/lib/
chmod +x scripts/detect-out-of-band-commits.sh \
         scripts/install-filesystem-gates.sh \
         scripts/hooks/record-claude-commit.sh
```

- [ ] **Step 9.4: Verify integration test passes**

```bash
bash tests/test-enforcement-level-init.sh
```
Should still pass — the test exercises strict/light init paths which need the hooks installed.

Also run a quick smoke test:

```bash
TMP=$(mktemp -d); PROJ="$TMP/p"
bash init.sh --non-interactive --project-dir "$PROJ" --no-remote-creation \
  --project-name smoke --platform other --language other --track light --deployment personal
jq '.hooks.PostToolUse[0].hooks[] | select(.command | contains("record-claude-commit"))' "$PROJ/.claude/settings.json"
jq '.hooks.SessionStart[0].hooks[] | select(.command | contains("detect-out-of-band"))' "$PROJ/.claude/settings.json"
rm -rf "$TMP"
```
Both jq commands should print one match.

- [ ] **Step 9.5: Commit**

```bash
git add init.sh
git commit -m "feat(bl-030): wire record-claude-commit + detect-out-of-band into init.sh hook templates and copy list"
```

---

## Task 10: Bypass-audit schema test (cross-pathway sanity)

A small integration test that exercises every writer pathway and confirms the schema discriminators are consistent.

**Files:**
- Test: `tests/test-bypass-audit-schema.sh`

- [ ] **Step 10.1: Write the test**

Create `tests/test-bypass-audit-schema.sh`:

```bash
#!/usr/bin/env bash
# tests/test-bypass-audit-schema.sh — BL-030 audit-log schema cross-pathway sanity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Minimum row contract every writer must satisfy.
ASSERT_ROW='all(
  .type and .actor and .timestamp and (.enforcement_level_at_event // "n/a")
)'

TMP=$(mktemp -d); PROJ="$TMP/p"
( cd "$REPO_ROOT" && bash init.sh --non-interactive --project-dir "$PROJ" --no-remote-creation \
    --project-name x --platform other --language other --track light --deployment personal \
    >/dev/null 2>&1 )

# T1: init wrote enforcement_level_set row, schema OK.
if jq -e "$ASSERT_ROW and .[0].type" "$PROJ/.claude/bypass-audit.json" >/dev/null 2>&1; then
  pass "T1: init row schema valid"
else
  fail_ "T1" "init row malformed"
fi

# T2: detector writes a valid row.
( cd "$PROJ" && echo u > u && git add u && git commit -qm "user terminal commit" )
( cd "$PROJ" && bash "$REPO_ROOT/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1 )
if jq -e '[.[] | select(.type=="out_of_band_commit")] | length >= 1' "$PROJ/.claude/bypass-audit.json" >/dev/null 2>&1; then
  pass "T2: detector row present"
else
  fail_ "T2" "detector did not write row"
fi

# T3: actor enum is one of the documented values.
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
```

- [ ] **Step 10.2: Run, verify pass**

```bash
bash tests/test-bypass-audit-schema.sh
```
Expected: `Results: 3 passed, 0 failed`.

- [ ] **Step 10.3: Commit**

```bash
git add tests/test-bypass-audit-schema.sh
git commit -m "test(bl-030): bypass-audit.json schema cross-pathway sanity"
```

---

## Task 11: Calibration replay (S11) under all three enforcement levels

Replay calibration scenario S11 to verify the design's central invariant: BL-029 is universal; BL-030 layers on top.

**Files:**
- Create: `tests/test-bl030-calibration-replay.sh` (or a Reports-side artifact if you prefer; keep as a test for CI inclusion).

- [ ] **Step 11.1: Read the S11 scenario for context**

```bash
ls Reports/uat-2026-04-27-calibration/scenarios/
cat Reports/uat-2026-04-27-calibration/scenarios/S11* 2>/dev/null | head -100
```

- [ ] **Step 11.2: Write the replay test**

Create `tests/test-bl030-calibration-replay.sh`:

```bash
#!/usr/bin/env bash
# tests/test-bl030-calibration-replay.sh — replay S11 under all three enforcement levels.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Each replay: (1) init at level, (2) simulate user-terminal `git commit`
# without going through framework gate, (3) run detector / inspect audit log.

run_init() {
  local proj="$1" level="$2"
  local extra=""
  if [ "$level" != "strict" ]; then extra="--enforcement-level $level --confirm-pitfalls"; fi
  ( cd "$REPO_ROOT" && bash init.sh --non-interactive --project-dir "$proj" --no-remote-creation \
      --project-name x --platform other --language other --track light --deployment personal $extra >/dev/null 2>&1 )
}

# strict: user terminal --no-verify lands but is detected on next session.
echo "REPLAY strict: --no-verify bypass is recorded on next session start"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" "strict"
( cd "$PROJ" && echo bypass > b.txt && git add b.txt && git commit --no-verify -qm "user --no-verify bypass" )
bash "$REPO_ROOT/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="out_of_band_commit")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then pass "strict: --no-verify recorded"; else fail_ "strict" "no row written"; fi
rm -rf "$TMP"

# light: user terminal commit lands without block, recorded on next session.
echo "REPLAY light: terminal commit lands and is recorded"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" "light"
( cd "$PROJ" && echo light > l.txt && git add l.txt && git commit -qm "user light commit" )
bash "$REPO_ROOT/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="out_of_band_commit")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then pass "light: terminal commit recorded"; else fail_ "light" "no row written"; fi
rm -rf "$TMP"

# no: user terminal commit lands without block AND is NOT recorded.
echo "REPLAY no: terminal commit lands and is NOT recorded"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" "no"
( cd "$PROJ" && echo no > n.txt && git add n.txt && git commit -qm "user no-mode commit" )
bash "$REPO_ROOT/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="out_of_band_commit")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" = "0" ]; then pass "no: terminal commit NOT recorded"; else fail_ "no" "$rows rows written"; fi

# But the init-time row should still exist (Claude-side audit always-on).
init_rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$init_rows" -ge "1" ]; then pass "no: framework-side audit still on"; else fail_ "no-framework-audit" "init row absent"; fi
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 11.3: Run, verify pass**

```bash
bash tests/test-bl030-calibration-replay.sh
```
Expected: `Results: 4 passed, 0 failed`.

- [ ] **Step 11.4: Run full regression suite one final time**

```bash
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1 && echo "PASS $(basename "$t")" || echo "FAIL $(basename "$t")"; done
```
Expected: every test PASS. Investigate any FAIL; root-cause before declaring done.

- [ ] **Step 11.5: Commit**

```bash
git add tests/test-bl030-calibration-replay.sh
git commit -m "test(bl-030): calibration S11 replay across no/light/strict — invariant proof"
```

---

## Task 12: Test-gate counter + backlog updates

- [ ] **Step 12.1: Bump test-gate counter**

```bash
bash scripts/test-gate.sh --record-feature "BL-030 enforcement model"
```

Verify counter advanced. If at 2/2, the next feature triggers a mandatory test gate per `docs/user-guide.md`.

- [ ] **Step 12.2: Update `solo-orchestrator-backlog.md`**

Mark BL-030 closed:

```bash
# Edit BL-030 entry in solo-orchestrator-backlog.md:
# Status: Open — pending brainstorm  →  Closed — shipped 2026-MM-DD (PR #NN)
```

Add a one-line summary referencing the spec and plan paths.

- [ ] **Step 12.3: Commit**

```bash
git add solo-orchestrator-backlog.md .claude/build-progress.json
git commit -m "docs(backlog): close BL-030 — user-terminal enforcement model shipped"
```

---

## Self-Review Checklist (run after writing all code, before declaring done)

- [ ] Every spec § 5 component (`enforcement-level.sh`, `detect-out-of-band-commits.sh`, `install-filesystem-gates.sh`, `record-claude-commit.sh`, `framework-gate.sh`, init.sh modifications, reconfigure-project.sh modifications) is implemented.
- [ ] Every spec § 6 row type (`claude_bypass_proposal` [BL-029], `terminal_commit_blocked`, `terminal_commit_passed`, `out_of_band_commit`, `enforcement_level_set`, `detector_error`) has a writer and at least one test.
- [ ] Every spec § 7 init UX requirement is exercised in `tests/test-enforcement-level-init.sh`.
- [ ] Every spec § 8 strict-mode property (idempotent install, marker preservation, `--no-verify` capture, `--terminal-mode` flag, principle-table block messages) has a test.
- [ ] Every spec § 9 light-mode edge case (rebase, branch checkout, detector error) is exercised in `tests/test-out-of-band-detector.sh`. Note: rebase/branch-checkout edges may need additional dedicated tests beyond what's in this plan — add if behavior under those cases isn't explicit from the implementation.
- [ ] Every spec § 10 transition rule has a test in `tests/test-enforcement-level-reconfigure.sh`.
- [ ] Full regression suite passes (`for t in tests/test-*.sh; ...`).
- [ ] Calibration replay passes for all three levels.
- [ ] Test-gate counter incremented.
- [ ] BL-030 closed in backlog.

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-28-bl030-enforcement-model-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — Dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**

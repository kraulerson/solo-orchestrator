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
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"output":"use --no-verify to skip"}}
EOF
  if [ -f "$TMP/.claude/pending-approval.json" ]; then pass "T1"; else fail_ "T1" "sentinel not written"; fi
fi
teardown

# T2 (S5 fix 2026-05-04): sentinel question does NOT embed the confirmation
# phrase verbatim. Earlier behavior leaked the phrase into the question text,
# which let Claude/user reading the sentinel copy-paste the phrase out of
# compliance — defeating the "non-trivial confirmation" defense. The phrase
# still lives in options[0] (structurally required for matching) but the
# question text uses a generic pointer.
echo "T2: sentinel question does NOT embed the confirmation phrase"
setup
if [ ! -f "$HOOK" ]; then fail_ "T2" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"output":"--no-verify path"}}
EOF
  q=$(jq -r '.question' "$TMP/.claude/pending-approval.json")
  if echo "$q" | grep -q "I have read the proposal at .claude/bypass-audit.json and accept the bypass"; then
    fail_ "T2" "phrase still in question — priming risk: $q"
  else
    pass "T2"
  fi
fi
teardown

# T2b (S5 fix 2026-05-04, RETIRED by BL-320 2026-10-06): the confirmation
# phrase lived in options[0] so the user had to type it verbatim. With the
# Development Guardrails 4.4.0 the user answers by option id, twice, through
# their record-approval.sh — only a reply starting with an id counts, and the
# first shows what each option does — so the question is schema 2 and the
# phrase is gone. T2b now pins that: A1 accepts, A2 declines, neither approves
# a commit, and the phrase is nowhere in the file.
echo "T2b: the question is answered by option id (schema 2); the typed phrase is retired"
setup
if [ ! -f "$HOOK" ]; then fail_ "T2b" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"output":"--no-verify path"}}
EOF
  if jq -e '.schema == 2 and ([.options[].id] == ["A1","A2"]) and ([.options[].approves] == ["none","none"])' "$TMP/.claude/pending-approval.json" >/dev/null 2>&1 \
     && ! grep -q "I have read the proposal" "$TMP/.claude/pending-approval.json"; then
    pass "T2b"
  else
    fail_ "T2b" "not a schema-2 id question: $(tr -d '\n' < "$TMP/.claude/pending-approval.json")"
  fi
fi
teardown

# T3: clean output does not write a sentinel.
echo "T3: clean output skips sentinel"
setup
if [ ! -f "$HOOK" ]; then fail_ "T3" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"output":"normal output"}}
EOF
  if [ ! -f "$TMP/.claude/pending-approval.json" ]; then pass "T3"; else fail_ "T3" "sentinel false-write"; fi
fi
teardown

# T4: existing pending-approval is NOT overwritten by a second match.
echo "T4: hook preserves an existing sentinel"
setup
if [ ! -f "$HOOK" ]; then fail_ "T4" "hook missing"; else
  cat > "$TMP/.claude/pending-approval.json" <<'EOF'
{"question":"existing q","options":["A1: yes","A2: no"],"recommendation":"A1","offered_at":"2026-04-28T00:00:00Z"}
EOF
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"output":"--no-verify"}}
EOF
  q=$(jq -r '.question' "$TMP/.claude/pending-approval.json")
  if [ "$q" = "existing q" ]; then pass "T4"; else fail_ "T4" "clobbered"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

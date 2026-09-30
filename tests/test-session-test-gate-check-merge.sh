#!/usr/bin/env bash
# tests/test-session-test-gate-check-merge.sh — session-test-gate-check.sh
# must not destructively overwrite .claude/tool-usage.json on resume /
# compact / clear. Pre-fix, every SessionStart invocation re-wrote the
# file with counters zeroed, re-arming the MCP gate and zeroing the
# Context7 counter mid-Build-Loop. After BL-030 added more SessionStart
# hooks (out-of-band-commits detector), the destructive overwrite hits
# the user's flow more often, so the fix is now-higher-impact.
#
# Hook contract (Claude Code): SessionStart envelope on stdin has a
# 'source' field with values "startup" | "resume" | "compact" | "clear".
# Fresh init only on startup; merge on the other three.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/session-test-gate-check.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  # Seed a tool-usage.json with accumulated in-flight state.
  cat > "$PROJ/.claude/tool-usage.json" <<'JSON'
{
  "session_id": "2026-04-28T00:00:00Z",
  "calls": [
    {"tool": "context7", "ts": "2026-04-28T00:01:00Z"},
    {"tool": "qdrant_find", "ts": "2026-04-28T00:02:00Z"}
  ],
  "commits_since_last_context7": 4,
  "qdrant_find_called": true,
  "qdrant_store_called": true,
  "context7_called": true,
  "mcp_gate_satisfied": true,
  "mcp_requirements": {
    "qdrant_required": true,
    "context7_required": true,
    "additional_required": ["custom-server"]
  }
}
JSON
}
teardown() { rm -rf "$TMP"; }

run_hook_with_source() {
  local src="$1"
  if [ -z "$src" ]; then
    ( cd "$PROJ" && bash "$HOOK" </dev/null >/dev/null 2>&1 ) || true
  else
    ( cd "$PROJ" && printf '{"hook_event_name":"SessionStart","source":"%s"}' "$src" \
        | bash "$HOOK" >/dev/null 2>&1 ) || true
  fi
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Non-startup sources (resume / compact / clear) must MERGE ==="
# ════════════════════════════════════════════════════════════════════

# T1: source=resume preserves the counters.
echo "T1: source=resume preserves calls / counters / flags"
setup
run_hook_with_source "resume"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
commits_counter=$(jq '.commits_since_last_context7' "$PROJ/.claude/tool-usage.json")
context7_flag=$(jq -r '.context7_called' "$PROJ/.claude/tool-usage.json")
add_req=$(jq -r '.mcp_requirements.additional_required | length' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "2" ] && [ "$commits_counter" = "4" ] \
   && [ "$context7_flag" = "true" ] && [ "$add_req" = "1" ]; then
  pass "T1: resume merge preserved calls=2 counter=4 context7=true add_req=1"
else
  fail_ "T1" "calls=$calls_len counter=$commits_counter context7=$context7_flag add_req=$add_req"
fi
teardown

# T2: source=compact preserves the counters.
echo "T2: source=compact preserves calls / counters / flags"
setup
run_hook_with_source "compact"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
commits_counter=$(jq '.commits_since_last_context7' "$PROJ/.claude/tool-usage.json")
mcp_gate=$(jq -r '.mcp_gate_satisfied' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "2" ] && [ "$commits_counter" = "4" ] && [ "$mcp_gate" = "true" ]; then
  pass "T2: compact merge preserved calls=2 counter=4 mcp_gate=true"
else
  fail_ "T2" "calls=$calls_len counter=$commits_counter mcp_gate=$mcp_gate"
fi
teardown

# T3: source=clear preserves the counters too. /clear semantically
# means "drop history" but the documented semantics in Claude Code
# are about CONVERSATION history, not framework state. Erasing the
# tool-usage ledger mid-Build-Loop would be surprising; preserve.
echo "T3: source=clear preserves calls / counters / flags"
setup
run_hook_with_source "clear"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "2" ]; then
  pass "T3: clear merge preserved calls=2"
else
  fail_ "T3" "calls=$calls_len (expected 2)"
fi
teardown

# T4: each non-startup invocation refreshes session_id even though the
# counters are preserved (so a successor reading the file can see the
# session boundary).
echo "T4: non-startup invocation refreshes session_id"
setup
original_id=$(jq -r '.session_id' "$PROJ/.claude/tool-usage.json")
sleep 1   # ensure date timestamps differ
run_hook_with_source "resume"
new_id=$(jq -r '.session_id' "$PROJ/.claude/tool-usage.json")
if [ "$new_id" != "$original_id" ] && [ -n "$new_id" ]; then
  pass "T4: session_id refreshed (was '$original_id', now '$new_id')"
else
  fail_ "T4" "session_id unchanged ('$original_id' → '$new_id')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== source=startup (and missing envelope) initializes fresh ==="
# ════════════════════════════════════════════════════════════════════

# T5: source=startup writes a fresh tool-usage.json with the counters
# zeroed (current behavior, must not regress).
echo "T5: source=startup writes a fresh tool-usage.json"
setup
run_hook_with_source "startup"
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
commits_counter=$(jq '.commits_since_last_context7' "$PROJ/.claude/tool-usage.json")
context7_flag=$(jq -r '.context7_called' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "0" ] && [ "$commits_counter" = "0" ] && [ "$context7_flag" = "false" ]; then
  pass "T5: startup fresh-init zeros calls/counter/flags"
else
  fail_ "T5" "calls=$calls_len counter=$commits_counter context7=$context7_flag (expected 0/0/false)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
# BL-236 — the startup fresh-init is what keeps a COMMITTED ledger from
# pre-satisfying the MCP gate, and until T5b/T5c that was guaranteed by an
# omission in this heredoc that no test pinned.
#
# session-mcp-gate.sh takes no latch fast path (`# BL-233-NO-LATCH`), so a
# committed `mcp_gate_satisfied` is inert. But it DOES read
# `.qdrant_find_succeeded` and `.context7_query_docs_succeeded`, and those are
# exactly the fields a committed ledger carries forward at `true`. The startup
# heredoc happens not to list them and `_flag` defaults a missing key to false —
# a fail-safe by coincidence. One "let's complete this object" refactor turns it
# into a live fail-open, and nothing failed if you did.
#
# Both cases assert on the GATE'S EMITTED DECISION, not on the flags alone: the
# ledger field is the mechanism, the deny envelope is the consequence.
# ════════════════════════════════════════════════════════════════════

# setup_inherited — a ledger as a fresh CLONE would find it: both MCP outcome
# flags already true, exactly what `git clone` hands the next machine.
setup_inherited() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude" "$TMP/home/.claude"
  # The hook derives the REQUIREMENTS from configured MCP servers. Declare them
  # project-locally and give the hook a private HOME, so this case cannot read
  # (or be rescued by) the developer's real ~/.claude.json.
  cat > "$PROJ/.claude/settings.local.json" <<'JSON'
{"mcpServers": {"qdrant": {"command": "uvx"}, "context7": {"command": "npx"}}}
JSON
  cat > "$PROJ/.claude/tool-usage.json" <<'JSON'
{
  "session_id": "2026-01-01T00:00:00Z",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": true,
  "qdrant_store_called": false,
  "context7_called": true,
  "qdrant_find_succeeded": true,
  "context7_query_docs_succeeded": true,
  "mcp_gate_satisfied": true,
  "mcp_requirements": {
    "qdrant_required": true,
    "context7_required": true,
    "additional_required": []
  }
}
JSON
}

# run_hook_at <hookpath> <source> — private HOME, so MCP-server discovery is a
# property of the fixture and not of the machine.
run_hook_at() {
  ( cd "$PROJ" && printf '{"hook_event_name":"SessionStart","source":"%s"}' "$2" \
      | env -i HOME="$TMP/home" PATH="$PATH" bash "$1" >/dev/null 2>&1 ) || true
}

# run_mcp_gate — the SHIPPED PreToolUse gate against the ledger as it now
# stands. Echoes its stdout: a deny envelope, or nothing at all (= allow).
# env -i so an exported SOLO_MCP_ATTESTED in the developer's shell cannot turn
# a deny into an allow and score as a pass.
run_mcp_gate() {
  ( cd "$PROJ" && printf '{"tool_name":"Write"}' \
      | env -i HOME="$TMP/home" PATH="$PATH" bash "$REPO_ROOT/scripts/session-mcp-gate.sh" 2>/dev/null ) || true
}

echo "T5b: source=startup ERASES an inherited MCP success, and the gate still denies"
setup_inherited
run_hook_at "$HOOK" "startup"
q_ok=$(jq -r '.qdrant_find_succeeded // false' "$PROJ/.claude/tool-usage.json" 2>/dev/null)
c_ok=$(jq -r '.context7_query_docs_succeeded // false' "$PROJ/.claude/tool-usage.json" 2>/dev/null)
q_req=$(jq -r '.mcp_requirements.qdrant_required // false' "$PROJ/.claude/tool-usage.json" 2>/dev/null)
gate_out=$(run_mcp_gate)
gate_denied=no; printf '%s' "$gate_out" | grep -q '"permissionDecision": "deny"' && gate_denied=yes
if [ "$q_ok" = "false" ] && [ "$c_ok" = "false" ] && [ "$q_req" = "true" ] && [ "$gate_denied" = "yes" ]; then
  pass "T5b: a cloned ledger carrying qdrant_find_succeeded=true and context7_query_docs_succeeded=true is erased by the startup fresh-init (absent-or-false), and session-mcp-gate.sh DENIES the first Write"
else
  fail_ "T5b" "qdrant_succeeded=$q_ok context7_succeeded=$c_ok (both want false) qdrant_required=$q_req (want true) gate_denied=$gate_denied (want yes)"
fi
teardown

echo "T5c: MUTANT — put the two keys back into the startup heredoc, gate flips to allow"
setup_inherited
# The mutant sits in a mirror of scripts/ with the ledger lib beside it, since
# the hook sources lib/ledger-write.sh from its own directory.
mkdir -p "$TMP/m/scripts/lib" && cp "$REPO_ROOT/scripts/lib/ledger-write.sh" "$TMP/m/scripts/lib/"
MUT="$TMP/m/scripts/session-test-gate-check.sh"
# Structural discriminator for an ABSENCE: an omission cannot be greped for as
# proof, so the two keys are spliced back INTO the startup heredoc (the SECOND
# of the two in the file — the first is the jq-failure fallback) and the gate's
# decision is read again. Anchored on the heredoc-open count, not on a line
# number and not on the em-dash comment.
awk '/_lw_put << TUEOF/ { n++ }
     n==2 && /"mcp_gate_satisfied": false,/ && !done {
       print "  \"qdrant_find_succeeded\": true,";
       print "  \"context7_query_docs_succeeded\": true,";
       done=1
     }
     { print }' "$HOOK" > "$MUT"
mut_sites=$(grep -c '_lw_put << TUEOF' "$HOOK" 2>/dev/null || echo 0)
case "$mut_sites" in ''|*[!0-9]*) mut_sites=0 ;; esac
mut_added=$(diff "$HOOK" "$MUT" 2>/dev/null | grep -c '^[<>]')
case "$mut_added" in ''|*[!0-9]*) mut_added=0 ;; esac
mut_parses=0; bash -n "$MUT" >/dev/null 2>&1 && mut_parses=1
chmod "$(stat -c '%a' "$HOOK" 2>/dev/null || stat -f '%Lp' "$HOOK" 2>/dev/null)" "$MUT" 2>/dev/null
run_hook_at "$MUT" "startup"
m_q=$(jq -r '.qdrant_find_succeeded // false' "$PROJ/.claude/tool-usage.json" 2>/dev/null)
mut_out=$(run_mcp_gate)
mut_denied=no; printf '%s' "$mut_out" | grep -q '"permissionDecision": "deny"' && mut_denied=yes
if [ "$mut_sites" = "2" ] && [ "$mut_added" = "2" ] && [ "$mut_parses" = "1" ] \
   && [ "$m_q" = "true" ] && [ "$mut_denied" = "no" ]; then
  pass "T5c: with the two outcome keys written as true by the startup heredoc, the SAME first-Write that T5b blocked is ALLOWED — the omission is the whole fail-safe, and it is one 'complete the object' edit from gone"
else
  fail_ "T5c" "heredocs=$mut_sites (want 2) lines_added=$mut_added (want 2) parses=$mut_parses (want 1) qdrant_succeeded=$m_q (want true) gate_denied=$mut_denied (want no)"
fi
teardown

echo "T5d: source=startup with lib/ledger-write.sh MISSING still erases an inherited MCP success"
# BL-314: the hook writes the ledger through that lib. Without it no fresh
# ledger can be written, and an inherited one must not survive the startup
# either, or its `true` flags let the first Write through.
setup_inherited
mkdir -p "$TMP/nolib/scripts"
cp "$HOOK" "$TMP/nolib/scripts/session-test-gate-check.sh"
run_hook_at "$TMP/nolib/scripts/session-test-gate-check.sh" "startup"
nl_q=$(jq -r '.qdrant_find_succeeded // false' "$PROJ/.claude/tool-usage.json" 2>/dev/null)
nl_gate=$(run_mcp_gate)
nl_denied=no; grep -q '"permissionDecision": "deny"' <<<"$nl_gate" && nl_denied=yes
if [ "$nl_q" != "true" ] && [ "$nl_denied" = "yes" ]; then
  pass "T5d: with the ledger lib absent, the startup leaves no inherited qdrant_find_succeeded=true behind, and session-mcp-gate.sh DENIES the first Write"
else
  fail_ "T5d" "qdrant_succeeded=$nl_q (want not true) gate_denied=$nl_denied (want yes)"
fi
teardown

# T6: invocation with NO envelope on stdin (legacy / unknown caller)
# defaults to startup behavior — backwards compat.
echo "T6: invocation with no envelope defaults to startup (legacy compat)"
setup
run_hook_with_source ""
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "0" ]; then
  pass "T6: missing envelope → fresh init"
else
  fail_ "T6" "calls=$calls_len (expected 0)"
fi
teardown

# T7: even on merge paths, the mcp_requirements get re-derived so
# users who add/remove MCP servers between sessions see the updated
# requirements. (We can't easily simulate adding servers in test, so
# this asserts the keys exist; the re-derivation logic is sourced
# from the same MCP-discovery block the startup path uses.)
echo "T7: merge path preserves mcp_requirements schema"
setup
run_hook_with_source "resume"
qreq=$(jq -r '.mcp_requirements.qdrant_required' "$PROJ/.claude/tool-usage.json")
creq=$(jq -r '.mcp_requirements.context7_required' "$PROJ/.claude/tool-usage.json")
if [ "$qreq" != "null" ] && [ "$creq" != "null" ]; then
  pass "T7: mcp_requirements re-derived (qdrant=$qreq context7=$creq)"
else
  fail_ "T7" "qdrant_required=$qreq context7_required=$creq"
fi
teardown

# ════════════════════════════════════════════════════════════════════
# Wave-4 closure for code-session-hooks-1: defensive regression coverage
# beyond the original merge-on-resume fix.
# ════════════════════════════════════════════════════════════════════

# T8: a MALFORMED prior tool-usage.json on a merge path must not wedge
# the gate. The jq merge will fail; the script must fall through to a
# fresh write so the next operation isn't blocked by an unparseable
# file. Pre-fix (before PR #5b1a081) this whole path didn't exist; this
# test pins the safety net so a refactor doesn't regress it.
echo "T8: merge path with malformed prior file falls through to fresh init"
setup
# Clobber with invalid JSON.
echo "this is not json {" > "$PROJ/.claude/tool-usage.json"
run_hook_with_source "resume"
if jq '.' "$PROJ/.claude/tool-usage.json" >/dev/null 2>&1; then
  calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
  if [ "$calls_len" = "0" ]; then
    pass "T8: malformed file → fresh init (calls=0, valid JSON)"
  else
    fail_ "T8" "fell through but calls=$calls_len (expected 0)"
  fi
else
  fail_ "T8" "tool-usage.json still malformed after merge attempt"
fi
teardown

# T9: an UNKNOWN source value (not startup/resume/compact/clear) must
# default to startup (fresh init) rather than silently entering the
# merge branch with stale data. This protects against a Claude Code
# protocol change adding a new source value the script doesn't yet
# understand. The `case "$parsed" in startup|resume|compact|clear)`
# block only assigns SESSION_SOURCE when the value is known; otherwise
# it stays at the default "startup".
echo "T9: unknown source value defaults to startup (fresh init)"
setup
run_hook_with_source "lobotomy"   # not a real source
calls_len=$(jq '.calls | length' "$PROJ/.claude/tool-usage.json")
commits_counter=$(jq '.commits_since_last_context7' "$PROJ/.claude/tool-usage.json")
if [ "$calls_len" = "0" ] && [ "$commits_counter" = "0" ]; then
  pass "T9: unknown source → startup fresh init"
else
  fail_ "T9" "unknown source entered merge branch (calls=$calls_len counter=$commits_counter)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== BL-311: the user config files the hook reads (# BL-311-GATE-CONFIG) ==="
# ════════════════════════════════════════════════════════════════════
# A server registered in the files THIS Claude Code session reads is REQUIRED
# (session-mcp-gate.sh then blocks every edit until it answers); one registered
# anywhere else is not. With CLAUDE_CONFIG_DIR UNSET those files are
# ~/.claude.json and ~/.claude/settings.json — the default setup, and the one
# where a wrong path fails OPEN: the gate stops requiring a server the session
# has. With it SET they are inside it, and ~/.claude.json is not read.
# Hermetic: a temp HOME and an explicit CLAUDE_CONFIG_DIR (or `env -u`) on
# every run, so the host's own configuration never answers.
_gc_reg() {   # FILE — register qdrant and context7 in FILE
  mkdir -p "$(dirname "$1")"
  printf '{"mcpServers":{"qdrant":{"command":"uvx"},"context7":{"command":"npx"}}}\n' > "$1"
}
_gc_req() {   # HOOK HOME CFG(empty = unset) — "[qdrant_required,context7_required]"
  local hook="$1" home="$2" cfg="$3" d=""
  d="$(mktemp -d)"; mkdir -p "$d/.claude"
  if [ -n "$cfg" ]; then
    ( cd "$d" && printf '{"source":"startup"}' | env HOME="$home" CLAUDE_CONFIG_DIR="$cfg" bash "$hook" >/dev/null 2>&1 )
  else
    ( cd "$d" && printf '{"source":"startup"}' | env -u CLAUDE_CONFIG_DIR HOME="$home" bash "$hook" >/dev/null 2>&1 )
  fi
  jq -c '[.mcp_requirements.qdrant_required, .mcp_requirements.context7_required]' "$d/.claude/tool-usage.json" 2>/dev/null
  rm -rf "$d"
}
GC_FAILS=0; GC_FAILED_IDS=""
gc_cases() {   # HOOK — C1..C3; bumps GC_FAILS and reports unless GC_QUIET=1
  local hook="$1" t="" got=""
  GC_FAILS=0; GC_FAILED_IDS=""
  t="$(mktemp -d)"
  _gc_reg "$t/h1/.claude.json"
  got="$(_gc_req "$hook" "$t/h1" "")"
  if [ "$got" = "[true,true]" ]; then [ "${GC_QUIET:-0}" = 1 ] || pass "C1: CLAUDE_CONFIG_DIR UNSET — servers registered in ~/.claude.json are REQUIRED (the default setup does not fail open)"
  else GC_FAILS=$((GC_FAILS + 1)); GC_FAILED_IDS="$GC_FAILED_IDS C1"; [ "${GC_QUIET:-0}" = 1 ] || fail_ "C1" "requirements '$got' (want [true,true]) — the unset branch does not read ~/.claude.json"; fi
  _gc_reg "$t/h2/.claude/settings.json"
  got="$(_gc_req "$hook" "$t/h2" "")"
  if [ "$got" = "[true,true]" ]; then [ "${GC_QUIET:-0}" = 1 ] || pass "C2: CLAUDE_CONFIG_DIR UNSET — servers registered in ~/.claude/settings.json are REQUIRED"
  else GC_FAILS=$((GC_FAILS + 1)); GC_FAILED_IDS="$GC_FAILED_IDS C2"; [ "${GC_QUIET:-0}" = 1 ] || fail_ "C2" "requirements '$got' (want [true,true]) — the unset branch does not read ~/.claude/settings.json"; fi
  _gc_reg "$t/h3/.claude.json"; mkdir -p "$t/cfg3"
  got="$(_gc_req "$hook" "$t/h3" "$t/cfg3")"
  _gc_reg "$t/cfg3/.claude.json"
  got="$got $(_gc_req "$hook" "$t/h3" "$t/cfg3")"
  if [ "$got" = "[false,false] [true,true]" ]; then [ "${GC_QUIET:-0}" = 1 ] || pass "C3: CLAUDE_CONFIG_DIR SET — ~/.claude.json is not read; \$CLAUDE_CONFIG_DIR/.claude.json is"
  else GC_FAILS=$((GC_FAILS + 1)); GC_FAILED_IDS="$GC_FAILED_IDS C3"; [ "${GC_QUIET:-0}" = 1 ] || fail_ "C3" "requirements (home-only, then cfg) '$got' (want '[false,false] [true,true]')"; fi
  rm -rf "$t"
}
gc_cases "$HOOK"

# Mutation proofs: the ONE marked line replaced in a copy of the hook, the
# replacement asserted to have landed and to parse, then C1-C3 re-run against
# the copy — which must fail.
_gc_mut() {   # LABEL WANT-CASE REPLACEMENT-LINE
  local label="$1" want="$2" repl="$3" m="" n=""
  m="$(mktemp -d)"; cp "$HOOK" "$m/hook.sh"
  n="$(MUT_REPL="$repl" awk '/# BL-311-GATE-CONFIG$/ { print ENVIRON["MUT_REPL"]; c++; next } { print } END { print c + 0 > "/dev/stderr" }' \
        "$HOOK" 2>&1 >"$m/hook.sh")"
  if [ "$n" != 1 ] || ! grep -qxF -- "$repl" "$m/hook.sh" || ! bash -n "$m/hook.sh" 2>/dev/null; then
    fail_ "$label" "the mutation did not apply (sites=$n)"; rm -rf "$m"; return
  fi
  GC_QUIET=1 gc_cases "$m/hook.sh"
  case " $GC_FAILED_IDS " in
    *" $want "*) pass "$label" ;;
    *) fail_ "$label" "not killed by $want (failed:${GC_FAILED_IDS:- none})" ;;
  esac
  rm -rf "$m"
}
_gc_mut "MC1: the unset branch pointed at \$HOME/.claude/.claude.json — killed by C1" C1 \
  '  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then _cc_set="$CLAUDE_CONFIG_DIR/settings.json"; _cc_json="$CLAUDE_CONFIG_DIR/.claude.json"; else _cc_set="$HOME/.claude/settings.json"; _cc_json="$HOME/.claude/.claude.json"; fi   # BL-311-GATE-CONFIG'
_gc_mut "MC2: the unset branch's settings.json pointed elsewhere — killed by C2" C2 \
  '  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then _cc_set="$CLAUDE_CONFIG_DIR/settings.json"; _cc_json="$CLAUDE_CONFIG_DIR/.claude.json"; else _cc_set="$HOME/settings.json"; _cc_json="$HOME/.claude.json"; fi   # BL-311-GATE-CONFIG'
_gc_mut "MC3: CLAUDE_CONFIG_DIR ignored (fixed \$HOME paths) — killed by C3" C3 \
  '  _cc_set="$HOME/.claude/settings.json"; _cc_json="$HOME/.claude.json"   # BL-311-GATE-CONFIG'

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

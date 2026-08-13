#!/usr/bin/env bash
# tests/test-bl233-mcp-outcome-enforcement.sh
#
# BL-233 WP-A — the MCP enforcement mechanism must record OUTCOMES, not
# DECLARATIONS. Three shipped files carry the mechanism and, before this suite,
# `scripts/session-mcp-gate.sh` — the hook that actually blocks Write/Edit — was
# executed by NO test in the repository. One suite
# (tests/test-session-test-gate-check-merge.sh) reads `mcp_gate_satisfied` and
# `mcp_requirements`, but it only asserts that the SessionStart hook WRITES those
# fields; it never runs the gate. The test suite had the same defect as the code:
# it verified the declaration was recorded, never that enforcement happened.
#
# ── GROUND TRUTH, measured 2026-08-13 (not from the docs) ───────────────────
# The official Claude Code documentation carries no worked MCP hook example, so
# the payload shape below was captured by registering a probe on both events and
# firing one failing and one succeeding MCP call. Every fixture in this file
# matches it exactly, because `scripts/lint-fixture-envelopes.sh` exists for the
# lesson that a wrong-shaped fixture "silently falls through the hook's `// \"\"`
# fallback and never exercises the detector".
#
#   A FAILED MCP CALL FIRES `PostToolUseFailure`. IT DOES NOT FIRE `PostToolUse`.
#
#   | field          | success (PostToolUse)                  | failure (PostToolUseFailure) |
#   |----------------|----------------------------------------|------------------------------|
#   | tool_response  | PRESENT — array of MCP content blocks  | ABSENT                       |
#   | error          | absent                                 | "Error calling tool '…': …"  |
#   | is_interrupt   | —                                      | false                        |
#   | isError        | NONE ANYWHERE — MCP's own isError is not preserved by either event      |
#
# Three consequences this suite is built around:
#   1. THE EVENT IS THE SIGNAL. There is no field to test for success. BL-233's
#      own text says "read .tool_response" — that instruction is WRONG (a
#      successful call's tool_response tells you what came BACK, not that the
#      call worked), and the entry is corrected as part of this package.
#   2. A third state exists: a call rejected BEFORE execution (unknown tool,
#      schema validation) fires NEITHER event. Fail-closed leaves the
#      requirement unsatisfied, which is correct — but it must never look like
#      success. G-group pins that.
#   3. Because tool_response carries the RETURNED TEXT, "succeeded" and
#      "returned something" are separable. Karl's decision 1: a successful but
#      EMPTY retrieval satisfies the requirement, and is reported loudly and
#      recorded. E-group pins both halves.
#
# ── What every assertion here refuses to do ────────────────────────────────
# "A test that passes because a tool was CALLED is this bug, restated in the
# test suite." Not one assertion below greps for a label, a reason string alone,
# or the presence of a call row as proof of satisfaction. Every one asserts on
# the resulting STATE (a JSON field in the ledger) or the resulting DECISION
# (the gate's permissionDecision / the process exit code).
#
# ── Mutation harness standard (all mandatory, per the WP-A brief) ──────────
#   • anchored END-OF-LINE markers, asserted at sites==1 in the SHIPPED source;
#   • exactly-N-lines-changed asserted for every mutant (this is the check that
#     catches a sed that reported success and edited nothing — CLAUDE.md's sed
#     trap; the delimiter here is `%`, absent from every marker and every
#     replacement, and `&` is escaped because in a sed replacement `&` means THE
#     WHOLE MATCH and an unescaped `&&` splices the original line back in);
#   • EVERY mutant asserts `bash -n` — a mutation that lands as a syntax error
#     kills every test for the wrong reason and would score as a pass;
#   • mode-preserving (`stat -c || stat -f`, GNU-first);
#   • a FRESH fixture per mutant — and per DIRECTION. Sharing one project
#     directory between a control run and its mutant run is not merely untidy
#     here, it is wrong: the gate REWRITES mcp_gate_satisfied on every
#     invocation, so a control run that denied left the flag false and the
#     latch mutant (M5) then had nothing to latch onto. It survived, and it
#     survived silently — the meta-assertions were all green because the
#     mutation applied perfectly. Only the direction assertion caught it;
#   • every mutant that changes a project's ledger re-runs its own tracker
#     calls against the fresh fixture rather than inheriting them;
#   • structural discriminators for ABSENCES — an absence cannot be greped for,
#     so the two absence properties (the gate takes NO latch fast path; the
#     tracker re-seed carries NO mcp_requirements) are each pinned by a real
#     line of code whose mutation REINTRODUCES the removed behaviour.
#
# Hermetic: temp dirs only, no network, no remote creation, no `--no-verify`,
# no `timeout`/`gtimeout` (absent on the dev host — they yield a spurious 127).
# bash 3.2 compatible: no ${var,,}, no declare -A, no nullglob.
#
# This suite names init.sh on executed lines (C-group reads the scaffolder's
# tool-usage.json seed and hook registration STATICALLY — it never runs it), so
# lint-tests-registered.sh marks it unit-lane-exempt. It is registered in the
# tests.yml unit list anyway: the lint treats a listed test as "the exemption
# decided nothing", and the suite is fast enough for the fast lane.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/session-mcp-gate.sh"
TRACKER="$REPO_ROOT/scripts/track-tool-usage.sh"
SESSION_CHECK="$REPO_ROOT/scripts/session-test-gate-check.sh"
SCAFFOLDER="$REPO_ROOT/init.sh"
REPO_SETTINGS="$REPO_ROOT/.claude/settings.json"

BASH_BIN="$(command -v bash)"
[ -n "$BASH_BIN" ] || BASH_BIN="/bin/bash"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

START_EPOCH=$(date +%s)

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }
_bytes() { local n; n=$(wc -c < "$1" 2>/dev/null | tr -d ' '); _num "$n"; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  _num "$n"
}

# _sites FILE MARKER — occurrences of an END-OF-LINE-anchored marker.
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

if [ ! -f "$GATE" ] || [ ! -f "$TRACKER" ]; then
  echo "  [FAIL] setup — gate or tracker not found under $REPO_ROOT/scripts"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on JSON ledger state."
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ── Fixture builders ────────────────────────────────────────────────────────

# mk_proj DIR LEDGER_JSON — a project directory with a tool-usage ledger.
# Pass the empty string to create the project WITHOUT a ledger.
mk_proj() {
  local p="$1" ledger="$2"
  mkdir -p "$p/.claude" || return 1
  if [ -n "$ledger" ]; then
    printf '%s\n' "$ledger" > "$p/.claude/tool-usage.json" || return 1
  fi
  return 0
}

# A ledger in the shape session-test-gate-check.sh writes at SessionStart, with
# both servers CONFIGURED (required) and nothing yet called.
LEDGER_BOTH_REQUIRED='{
  "session_id": "2026-08-13T00:00:00Z",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false,
  "context7_called": false,
  "mcp_gate_satisfied": false,
  "mcp_requirements": {
    "qdrant_required": true,
    "context7_required": false,
    "additional_required": []
  }
}'

# The same, with NEITHER server configured — the honest "not-configured" state.
LEDGER_NONE_REQUIRED='{
  "session_id": "2026-08-13T00:00:00Z",
  "calls": [],
  "commits_since_last_context7": 0,
  "mcp_gate_satisfied": false,
  "mcp_requirements": {
    "qdrant_required": false,
    "context7_required": false,
    "additional_required": []
  }
}'

# One key present, the OTHER missing — the fixture M3 needs. With both keys
# absent, flipping one default cannot change the verdict (the other still
# blocks) and the mutant would survive for a reason that has nothing to do with
# the line under test.
LEDGER_MISSING_QDRANT_KEY='{
  "session_id": "2026-08-13T00:00:00Z",
  "calls": [],
  "commits_since_last_context7": 0,
  "mcp_gate_satisfied": false,
  "mcp_requirements": {
    "context7_required": false,
    "additional_required": []
  }
}'

# The BL-221 shape: a ledger with NO mcp_requirements object at all. This is
# exactly what init.sh seeds today and what track-tool-usage.sh re-creates.
LEDGER_NO_REQUIREMENTS='{
  "session_id": "2026-08-13T00:00:00Z",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false,
  "mcp_gate_satisfied": false
}'

# ── Real-wire-format envelope builders ──────────────────────────────────────
# ev_success TOOL TEXT      — PostToolUse: tool_response present, NO error key.
# ev_failure TOOL ERROR     — PostToolUseFailure: error present, NO tool_response.
# Neither carries an `isError` key, because neither event does.
#
# These are hand-written printf templates rather than jq-assembled objects on
# purpose: the literal wire shape is half of what this file documents. The cost
# of that choice is that a builder ARGUMENT containing a `"` or a `\` silently
# produces INVALID JSON, and an invalid envelope makes every hook take its
# "no tool_name" fast exit — which reads as a real assertion failure while
# actually testing nothing. That happened once while writing this suite (a
# `'"'"'`-style quote dance inside a double-quoted assignment emitted `"` where
# `'` was meant, and D1 went red for entirely the wrong reason). So EVERY
# envelope routes through _ev, which records a breach to a file that Z1 asserts
# is empty — the subshell of a $( … ) builder cannot increment a variable, but
# it can append to a file.
BAD_ENVELOPES="$TOPTMP/bad-envelopes"
: > "$BAD_ENVELOPES"
_ev() {
  local json="$1"
  printf '%s\n' "$json" | jq -e . >/dev/null 2>&1 || printf '%s\n' "$json" >> "$BAD_ENVELOPES"
  printf '%s\n' "$json"
}
ev_success() {
  _ev "$(printf '{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"query":"prior session context"},"tool_response":[{"type":"text","text":"%s"}]}' "$1" "$2")"
}
ev_success_no_response() {
  _ev "$(printf '{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"query":"prior session context"}}' "$1")"
}
ev_failure() {
  _ev "$(printf '{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PostToolUseFailure","tool_name":"%s","tool_input":{"query":"prior session context"},"error":"%s","is_interrupt":false}' "$1" "$2")"
}
# An envelope with NO hook_event_name at all — the shape a mis-registration or a
# future rename produces. "Cannot tell which event" must not read as success.
ev_eventless() {
  _ev "$(printf '{"session_id":"s1","cwd":"/tmp","tool_name":"%s","tool_input":{"query":"q"},"tool_response":[{"type":"text","text":"%s"}]}' "$1" "$2")"
}

# Verbatim, from the live 2026-08-12 call against the dead database.
QDRANT_DOWN="Error calling tool 'qdrant-find': All connection attempts failed"

# ── Runners ─────────────────────────────────────────────────────────────────

# run_tracker LIB DIR ENVELOPE [extra argv…] — sets TRK_RC / TRK_OUT (a file).
TRK_RC=0; TRK_OUT=""
run_tracker() {
  local lib="$1" d="$2" envelope="$3"; shift 3
  local infile
  TRK_RC=0
  TRK_OUT="$TOPTMP/trk-out-$$-$RANDOM"
  infile="$TOPTMP/trk-in-$$-$RANDOM"
  printf '%s\n' "$envelope" > "$infile"
  ( cd "$d" && "$BASH_BIN" "$lib" "$@" < "$infile" ) > "$TRK_OUT" 2>&1 || TRK_RC=$?
  rm -f "$infile"
  return 0
}

# run_gate LIB DIR [VAR=VAL …] — sets GATE_RC / GATE_OUT (a file).
# Called DIRECTLY, never inside $( … ): a command substitution is a subshell, so
# a helper returning its transcript path through a global loses it on the way
# out, and every later assertion then greps an empty path — which reads as a
# genuine failure instead of a broken harness.
GATE_RC=0; GATE_OUT=""
GATE_ENVELOPE='{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"note.txt","content":"x"}}'
run_gate() {
  local lib="$1" d="$2"; shift 2
  local infile
  GATE_RC=0
  GATE_OUT="$TOPTMP/gate-out-$$-$RANDOM"
  infile="$TOPTMP/gate-in-$$-$RANDOM"
  printf '%s\n' "$GATE_ENVELOPE" > "$infile"
  if [ "$#" -gt 0 ]; then
    ( cd "$d" && /usr/bin/env "$@" "$BASH_BIN" "$lib" < "$infile" ) > "$GATE_OUT" 2>&1 || GATE_RC=$?
  else
    ( cd "$d" && "$BASH_BIN" "$lib" < "$infile" ) > "$GATE_OUT" 2>&1 || GATE_RC=$?
  fi
  rm -f "$infile"
  return 0
}

# decision_of FILE — "deny", "allow", or "malformed".
# ALLOW is the ABSENCE of a decision envelope, so this reads the transcript
# structurally rather than grepping for a word that could appear in prose.
decision_of() {
  local f="$1" d
  if [ ! -s "$f" ]; then printf 'allow\n'; return 0; fi
  d=$(jq -r '.hookSpecificOutput.permissionDecision // "malformed"' "$f" 2>/dev/null)
  case "$d" in
    deny|allow) printf '%s\n' "$d" ;;
    *) printf 'malformed\n' ;;
  esac
}

# reason_of FILE — the deny reason text, or the empty string.
reason_of() { jq -r '.hookSpecificOutput.permissionDecisionReason // ""' "$1" 2>/dev/null; }

# jqf DIR FILTER — read the ledger.
jqf() { jq -r "$2" "$1/.claude/tool-usage.json" 2>/dev/null; }

echo "=== A — the tracker records the EVENT as the outcome (track-tool-usage.sh) ==="

# A1 is the assertion that would have caught today's behaviour: a call that
# connected to nothing must not move the requirement toward satisfied.
A1D="$(newtmp)/p"
if ! mk_proj "$A1D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "A1" "fixture setup failed"
else
  run_tracker "$TRACKER" "$A1D" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  a1_ok=$(jqf "$A1D" '.qdrant_find_succeeded // false')
  a1_fails=$(_num "$(jqf "$A1D" '.qdrant_find_failed // 0')")
  if [ "$a1_ok" = "false" ] && [ "$a1_fails" -eq 1 ] && [ "$TRK_RC" -eq 0 ]; then
    pass "A1: a PostToolUseFailure qdrant-find leaves qdrant_find_succeeded=false and records qdrant_find_failed=1 — a failed call moves the requirement AWAY from satisfied, not toward it"
  else
    fail_ "A1" "qdrant_find_succeeded=$a1_ok (want false) qdrant_find_failed=$a1_fails (want 1) tracker_rc=$TRK_RC (want 0)"
  fi
fi

A2D="$(newtmp)/p"
if ! mk_proj "$A2D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "A2" "fixture setup failed"
else
  run_tracker "$TRACKER" "$A2D" "$(ev_success 'mcp__qdrant__qdrant-find' '<entry>prior decision: use worktrees</entry>')" --event PostToolUse
  a2_ok=$(jqf "$A2D" '.qdrant_find_succeeded // false')
  a2_fails=$(_num "$(jqf "$A2D" '.qdrant_find_failed // 0')")
  a2_empty=$(jqf "$A2D" '.qdrant_find_empty // false')
  if [ "$a2_ok" = "true" ] && [ "$a2_fails" -eq 0 ] && [ "$a2_empty" = "false" ]; then
    pass "A2 (direction 2): a PostToolUse qdrant-find carrying real content sets qdrant_find_succeeded=true, records no failure, and is not flagged empty"
  else
    fail_ "A2" "qdrant_find_succeeded=$a2_ok (want true) qdrant_find_failed=$a2_fails (want 0) qdrant_find_empty=$a2_empty (want false)"
  fi
fi

A3D="$(newtmp)/p"
if ! mk_proj "$A3D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "A3" "fixture setup failed"
else
  run_tracker "$TRACKER" "$A3D" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  a3_rows=$(_num "$(jqf "$A3D" '[.calls[] | select(.outcome == "failure")] | length')")
  a3_err=$(jqf "$A3D" '.last_mcp_error // ""')
  a3_event=$(jqf "$A3D" '[.calls[] | select(.outcome == "failure") | .event] | first // ""')
  if [ "$a3_rows" -eq 1 ] && [ "$a3_event" = "PostToolUseFailure" ] \
     && printf '%s' "$a3_err" | grep -q 'All connection attempts failed'; then
    pass "A3: the failure is RECORDED DISTINCTLY — a calls[] row with outcome=failure and event=PostToolUseFailure, plus the server's own error text on last_mcp_error. Before this, failures were not miscounted, they were UNSEEN (the tracker was registered on PostToolUse only)"
  else
    fail_ "A3" "failure_rows=$a3_rows (want 1) recorded_event='$a3_event' (want PostToolUseFailure) last_mcp_error='$a3_err' (want the connection error)"
  fi
fi

# A4 — the third state. An envelope that names no event cannot be scored as a
# success, and the ARG-vs-payload disagreement case is scored the same way.
A4D="$(newtmp)/p"
if ! mk_proj "$A4D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "A4" "fixture setup failed"
else
  run_tracker "$TRACKER" "$A4D" "$(ev_eventless 'mcp__qdrant__qdrant-find' 'looks like a result')"
  a4_ok=$(jqf "$A4D" '.qdrant_find_succeeded // false')
  a4_unknown=$(_num "$(jqf "$A4D" '[.calls[] | select(.outcome == "unknown")] | length')")
  run_tracker "$TRACKER" "$A4D" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUse
  a4_mis=$(jqf "$A4D" '.qdrant_find_succeeded // false')
  if [ "$a4_ok" = "false" ] && [ "$a4_unknown" -eq 1 ] && [ "$a4_mis" = "false" ]; then
    pass "A4: an envelope with NO hook_event_name scores outcome=unknown and satisfies nothing; and when the --event ARG disagrees with the payload's hook_event_name (a mis-registration pointing both events at PostToolUse) the disagreement also scores unknown rather than success"
  else
    fail_ "A4" "eventless_succeeded=$a4_ok (want false) unknown_rows=$a4_unknown (want 1) arg_payload_disagreement_succeeded=$a4_mis (want false)"
  fi
fi

# A5 — the fourth state, and the reason the ground-truth table lists
# `is_interrupt` at all. A call the OPERATOR cancelled also arrives on
# PostToolUseFailure, but "you pressed Esc" and "the server is not there" are
# different facts. Both leave the requirement unsatisfied — that part must not
# soften — but only one of them is evidence about the server, and a gate that
# announces CONFIGURED BUT UNREACHABLE because someone cancelled a query is
# `## BL-104:`'s lesson restated: the label is never the behaviour.
A5D="$(newtmp)/p"
if ! mk_proj "$A5D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "A5" "fixture setup failed"
else
  a5_env=$(_ev "$(printf '{"session_id":"s1","cwd":"/tmp","hook_event_name":"PostToolUseFailure","tool_name":"mcp__qdrant__qdrant-find","tool_input":{"query":"q"},"error":"The user doesn'"'"'t want to take this action right now.","is_interrupt":true}')")
  run_tracker "$TRACKER" "$A5D" "$a5_env" --event PostToolUseFailure
  a5_ok=$(jqf "$A5D" '.qdrant_find_succeeded // false')
  a5_fails=$(_num "$(jqf "$A5D" '.qdrant_find_failed // 0')")
  a5_int=$(_num "$(jqf "$A5D" '.qdrant_find_interrupted // 0')")
  a5_outcome=$(jqf "$A5D" '[.calls[] | .outcome] | first // ""')
  run_gate "$GATE" "$A5D"
  a5_dec=$(decision_of "$GATE_OUT")
  a5_claims_down=0
  printf '%s' "$(reason_of "$GATE_OUT")" | grep -qi 'unreachable' && a5_claims_down=1
  if [ "$a5_ok" = "false" ] && [ "$a5_dec" = "deny" ] && [ "$a5_claims_down" -eq 0 ] \
     && [ "$a5_fails" -eq 0 ] && [ "$a5_int" -eq 1 ] && [ "$a5_outcome" = "interrupted" ]; then
    pass "A5: an OPERATOR-CANCELLED call (is_interrupt=true on PostToolUseFailure) still leaves the requirement unsatisfied and still denies — but it is recorded as interrupted, not failed, and the gate does NOT diagnose the server as unreachable on the strength of it. Unsatisfied is a verdict; unreachable is a claim about the world, and only a real failed round trip earns it"
  else
    fail_ "A5" "succeeded=$a5_ok (want false) gate=$a5_dec (want deny) claims_unreachable=$a5_claims_down (want 0) qdrant_find_failed=$a5_fails (want 0) qdrant_find_interrupted=$a5_int (want 1) call_outcome='$a5_outcome' (want interrupted)"
  fi
fi

echo ""
echo "=== B — Context7: the gate must require the call that FETCHES DOCUMENTATION ==="

B1D="$(newtmp)/p"
if ! mk_proj "$B1D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "B1" "fixture setup failed"
else
  run_tracker "$TRACKER" "$B1D" "$(ev_success 'mcp__context7__resolve-library-id' '/qdrant/qdrant - 412 snippets')" --event PostToolUse
  b1_q=$(jqf "$B1D" '.context7_query_docs_succeeded // false')
  b1_r=$(_num "$(jqf "$B1D" '.context7_resolve_only_count // 0')")
  b1_logged=$(_num "$(jqf "$B1D" '[.calls[] | select(.tool | test("resolve-library-id"))] | length')")
  if [ "$b1_q" = "false" ] && [ "$b1_r" -eq 1 ] && [ "$b1_logged" -eq 1 ]; then
    pass "B1: a SUCCESSFUL resolve-library-id leaves context7_query_docs_succeeded=false — it returns a list of library IDs and fetches no documentation. It is still ALLOWED and LOGGED (it is the argument step), just not COUNTED"
  else
    fail_ "B1" "query_docs_succeeded=$b1_q (want false) resolve_only_count=$b1_r (want 1) call_logged=$b1_logged (want 1)"
  fi
fi

B2D="$(newtmp)/p"
if ! mk_proj "$B2D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "B2" "fixture setup failed"
else
  run_tracker "$TRACKER" "$B2D" "$(ev_success 'mcp__context7__query-docs' 'Qdrant search API: client.query_points(...)')" --event PostToolUse
  b2_q=$(jqf "$B2D" '.context7_query_docs_succeeded // false')
  if [ "$b2_q" = "true" ]; then
    pass "B2 (direction 2): a SUCCESSFUL query-docs sets context7_query_docs_succeeded=true — the call that actually reads documentation is the one that satisfies the gate whose stated purpose is 'verify library documentation is current before writing'"
  else
    fail_ "B2" "query_docs_succeeded=$b2_q (want true)"
  fi
fi

# B3 — BL-232's second half: an ID lookup also silenced the commit-time
# staleness nudge by resetting the counter. Only a real doc read may reset it.
B3D="$(newtmp)/p"
if ! mk_proj "$B3D" "$(printf '%s' "$LEDGER_BOTH_REQUIRED" | jq '.commits_since_last_context7 = 7')"; then
  fail_ "B3" "fixture setup failed"
else
  run_tracker "$TRACKER" "$B3D" "$(ev_success 'mcp__context7__resolve-library-id' '/qdrant/qdrant')" --event PostToolUse
  b3_after_resolve=$(_num "$(jqf "$B3D" '.commits_since_last_context7 // 0')")
  run_tracker "$TRACKER" "$B3D" "$(ev_success 'mcp__context7__query-docs' 'the docs themselves')" --event PostToolUse
  b3_after_query=$(_num "$(jqf "$B3D" '.commits_since_last_context7 // 0')")
  if [ "$b3_after_resolve" -eq 7 ] && [ "$b3_after_query" -eq 0 ]; then
    pass "B3: resolve-library-id does NOT reset commits_since_last_context7 (stays 7) while query-docs does (drops to 0) — the staleness nudge is no longer silenced by an ID lookup"
  else
    fail_ "B3" "counter_after_resolve=$b3_after_resolve (want 7, unchanged) counter_after_query_docs=$b3_after_query (want 0)"
  fi
fi

# B4 — a FAILED query-docs must not satisfy Context7 either.
B4D="$(newtmp)/p"
if ! mk_proj "$B4D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "B4" "fixture setup failed"
else
  run_tracker "$TRACKER" "$B4D" "$(ev_failure 'mcp__context7__query-docs' "Error calling tool 'query-docs': upstream 503")" --event PostToolUseFailure
  b4_q=$(jqf "$B4D" '.context7_query_docs_succeeded // false')
  b4_reset=$(_num "$(jqf "$B4D" '.commits_since_last_context7 // 0')")
  if [ "$b4_q" = "false" ] && [ "$b4_reset" -eq 0 ]; then
    pass "B4: a FAILED query-docs leaves context7_query_docs_succeeded=false — the tool that does the work still has to have worked"
  else
    fail_ "B4" "query_docs_succeeded=$b4_q (want false) counter=$b4_reset"
  fi
fi

echo ""
echo "=== C — the gate FAILS CLOSED where it used to exit 0 in silence (session-mcp-gate.sh) ==="

C1D="$(newtmp)/p"
if ! mk_proj "$C1D" ""; then
  fail_ "C1" "fixture setup failed"
else
  run_gate "$GATE" "$C1D"
  c1_dec=$(decision_of "$GATE_OUT")
  c1_reason=$(reason_of "$GATE_OUT")
  c1_says_why=0
  printf '%s' "$c1_reason" | grep -qi 'cannot' && c1_says_why=1
  if [ "$c1_dec" = "deny" ] && [ "$c1_says_why" -eq 1 ] && [ "$GATE_RC" -eq 0 ]; then
    pass "C1: an ABSENT .claude/tool-usage.json now DENIES, and the refusal text says which state it is in ('cannot verify'), not 'satisfied'. Before, no file meant no enforcement, silently"
  else
    fail_ "C1" "decision=$c1_dec (want deny) reason_distinguishes_cannot_tell=$c1_says_why (want 1) rc=$GATE_RC (want 0) reason='$c1_reason'"
  fi
fi

C2D="$(newtmp)/p"
if ! mk_proj "$C2D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "C2" "fixture setup failed"
else
  run_gate "$GATE" "$C2D" "PATH="
  c2_dec=$(decision_of "$GATE_OUT")
  c2_reason=$(reason_of "$GATE_OUT")
  c2_names_jq=0
  printf '%s' "$c2_reason" | grep -q 'jq' && c2_names_jq=1
  if [ "$c2_dec" = "deny" ] && [ "$c2_names_jq" -eq 1 ] && [ "$GATE_RC" -eq 0 ]; then
    pass "C2: with jq unavailable (empty PATH) the gate DENIES and names jq as the reason it cannot tell — and it emits that refusal using shell builtins only, so the no-jq arm does not depend on the very toolchain it is reporting missing"
  else
    fail_ "C2" "decision=$c2_dec (want deny) reason_names_jq=$c2_names_jq (want 1) rc=$GATE_RC (want 0) transcript='$(cat "$GATE_OUT" 2>/dev/null)'"
  fi
fi

# C3 — BL-221's shape, one subsystem over: a MISSING key must not be a silent
# opt-out. This is the ledger init.sh seeds today.
C3D="$(newtmp)/p"
if ! mk_proj "$C3D" "$LEDGER_NO_REQUIREMENTS"; then
  fail_ "C3" "fixture setup failed"
else
  run_gate "$GATE" "$C3D"
  c3_dec=$(decision_of "$GATE_OUT")
  if [ "$c3_dec" = "deny" ]; then
    pass "C3: a ledger with NO mcp_requirements object at all now DENIES — an absent key reads as 'required' (fail closed), not as the permissive default that made every requirement silently OFF"
  else
    fail_ "C3" "decision=$c3_dec (want deny) — the missing-key default is still permissive"
  fi
fi

# C4 — the honest third state. not-configured is a REAL answer and must pass.
C4D="$(newtmp)/p"
if ! mk_proj "$C4D" "$LEDGER_NONE_REQUIRED"; then
  fail_ "C4" "fixture setup failed"
else
  run_gate "$GATE" "$C4D"
  c4_dec=$(decision_of "$GATE_OUT")
  if [ "$c4_dec" = "allow" ]; then
    pass "C4 (direction 2): an EXPLICIT not-configured ledger (qdrant_required=false, context7_required=false) allows — 'no server configured' is a determinate answer and must be distinguishable from 'cannot tell', or the gate becomes one people delete"
  else
    fail_ "C4" "decision=$c4_dec (want allow) transcript='$(cat "$GATE_OUT" 2>/dev/null)'"
  fi
fi

echo ""
echo "=== D — the gate reads OUTCOMES, and the latch is not an authority ==="

D1D="$(newtmp)/p"
if ! mk_proj "$D1D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "D1" "fixture setup failed"
else
  run_tracker "$TRACKER" "$D1D" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  run_gate "$GATE" "$D1D"
  d1_dec=$(decision_of "$GATE_OUT")
  d1_reason=$(reason_of "$GATE_OUT")
  d1_distinct=0
  printf '%s' "$d1_reason" | grep -qi 'unreachable' && d1_distinct=1
  if [ "$d1_dec" = "deny" ] && [ "$d1_distinct" -eq 1 ]; then
    pass "D1 (the headline): the tracker records a real failing round trip and the gate then DENIES, naming CONFIGURED-BUT-UNREACHABLE as a state distinct from not-configured. This is the end-to-end path where a call returning 'All connection attempts failed' used to satisfy the gate"
  else
    fail_ "D1" "decision=$d1_dec (want deny) reason_names_unreachable=$d1_distinct (want 1) reason='$d1_reason'"
  fi
fi

D2D="$(newtmp)/p"
if ! mk_proj "$D2D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "D2" "fixture setup failed"
else
  run_tracker "$TRACKER" "$D2D" "$(ev_success 'mcp__qdrant__qdrant-find' '<entry>prior context</entry>')" --event PostToolUse
  run_gate "$GATE" "$D2D"
  d2_dec=$(decision_of "$GATE_OUT")
  if [ "$d2_dec" = "allow" ]; then
    pass "D2 (direction 2): the same fixture with a SUCCEEDING round trip allows — the two directions differ only in which hook event fired, which is the whole point: the event is the signal"
  else
    fail_ "D2" "decision=$d2_dec (want allow) transcript='$(cat "$GATE_OUT" 2>/dev/null)'"
  fi
fi

# D3 — the latch. mcp_gate_satisfied lives in a file the agent can edit.
D3D="$(newtmp)/p"
if ! mk_proj "$D3D" "$(printf '%s' "$LEDGER_BOTH_REQUIRED" | jq '.mcp_gate_satisfied = true')"; then
  fail_ "D3" "fixture setup failed"
else
  run_gate "$GATE" "$D3D"
  d3_dec=$(decision_of "$GATE_OUT")
  d3_after=$(jqf "$D3D" '.mcp_gate_satisfied // false')
  if [ "$d3_dec" = "deny" ] && [ "$d3_after" = "false" ]; then
    pass "D3 (the latch): mcp_gate_satisfied=true with the requirement UNSATISFIED still denies, and the stale flag is re-derived to false. The gate asks 'is it satisfied NOW', never 'was it satisfied once' — a latch in an agent-editable file is a self-signed permission slip"
  else
    fail_ "D3" "decision=$d3_dec (want deny) mcp_gate_satisfied_after=$d3_after (want false — re-derived)"
  fi
fi

# D4 — additional_required is on the same outcome footing.
D4D="$(newtmp)/p"
if ! mk_proj "$D4D" "$(printf '%s' "$LEDGER_NONE_REQUIRED" | jq '.mcp_requirements.additional_required = ["sentry"]')"; then
  fail_ "D4" "fixture setup failed"
else
  run_tracker "$TRACKER" "$D4D" "$(ev_failure 'mcp__sentry__list-issues' "Error calling tool 'list-issues': 401")" --event PostToolUseFailure
  run_gate "$GATE" "$D4D"
  d4_fail_dec=$(decision_of "$GATE_OUT")
  run_tracker "$TRACKER" "$D4D" "$(ev_success 'mcp__sentry__list-issues' 'issue 1')" --event PostToolUse
  run_gate "$GATE" "$D4D"
  d4_ok_dec=$(decision_of "$GATE_OUT")
  if [ "$d4_fail_dec" = "deny" ] && [ "$d4_ok_dec" = "allow" ]; then
    pass "D4: an operator-added additional_required tool obeys the same rule — a FAILED call denies, a SUCCEEDING one allows. The additional_required arm used to count any logged call row regardless of outcome"
  else
    fail_ "D4" "decision_after_failed_call=$d4_fail_dec (want deny) decision_after_successful_call=$d4_ok_dec (want allow)"
  fi
fi

echo ""
echo "=== E — a successful but EMPTY retrieval: allowed, reported loudly, recorded ==="

E1D="$(newtmp)/p"
if ! mk_proj "$E1D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "E1" "fixture setup failed"
else
  run_tracker "$TRACKER" "$E1D" "$(ev_success 'mcp__qdrant__qdrant-find' '')" --event PostToolUse
  e1_ok=$(jqf "$E1D" '.qdrant_find_succeeded // false')
  e1_empty=$(jqf "$E1D" '.qdrant_find_empty // false')
  e1_count=$(_num "$(jqf "$E1D" '.qdrant_find_empty_count // 0')")
  e1_reported=$(_bytes "$TRK_OUT")
  run_gate "$GATE" "$E1D"
  e1_dec=$(decision_of "$GATE_OUT")
  if [ "$e1_ok" = "true" ] && [ "$e1_empty" = "true" ] && [ "$e1_count" -eq 1 ] \
     && [ "$e1_reported" -gt 0 ] && [ "$e1_dec" = "allow" ]; then
    pass "E1 (Karl's decision 1): a SUCCESSFUL find that returned nothing satisfies the requirement (allow) AND is recorded (qdrant_find_empty=true, count=1) AND is reported — 'succeeded' and 'returned something' are separable because tool_response carries the returned text. Empty is information on a new project and a symptom on an old one"
  else
    fail_ "E1" "succeeded=$e1_ok (want true) empty_flag=$e1_empty (want true) empty_count=$e1_count (want 1) report_bytes=$e1_reported (want >0) gate_decision=$e1_dec (want allow)"
  fi
fi

# E2 — a success envelope with NO tool_response at all returned nothing either.
E2D="$(newtmp)/p"
if ! mk_proj "$E2D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "E2" "fixture setup failed"
else
  run_tracker "$TRACKER" "$E2D" "$(ev_success_no_response 'mcp__qdrant__qdrant-find')" --event PostToolUse
  e2_ok=$(jqf "$E2D" '.qdrant_find_succeeded // false')
  e2_empty=$(jqf "$E2D" '.qdrant_find_empty // false')
  if [ "$e2_ok" = "true" ] && [ "$e2_empty" = "true" ]; then
    pass "E2: a PostToolUse envelope with tool_response ABSENT is a success that returned nothing — flagged empty, still satisfying. The event decides success; the payload decides emptiness"
  else
    fail_ "E2" "succeeded=$e2_ok (want true) empty_flag=$e2_empty (want true)"
  fi
fi

# E3 — the qdrant MCP server's literal zero-result phrase.
E3D="$(newtmp)/p"
if ! mk_proj "$E3D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "E3" "fixture setup failed"
else
  run_tracker "$TRACKER" "$E3D" "$(ev_success 'mcp__qdrant__qdrant-find' 'No information found')" --event PostToolUse
  e3_empty=$(jqf "$E3D" '.qdrant_find_empty // false')
  if [ "$e3_empty" = "true" ]; then
    pass "E3: the qdrant MCP server's own zero-result phrase ('No information found') is recognised as empty rather than as content"
  else
    fail_ "E3" "empty_flag=$e3_empty (want true)"
  fi
fi

echo ""
echo "=== F — the attested escape: recorded, or refused (BL-072's shape) ==="

F1D="$(newtmp)/p"
if ! mk_proj "$F1D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "F1" "fixture setup failed"
else
  run_gate "$GATE" "$F1D" "SOLO_MCP_ATTESTED=1" "SOLO_MCP_REASON=offline on a plane, qdrant unreachable by design"
  f1_dec=$(decision_of "$GATE_OUT")
  f1_rows=$(_num "$(jq -r '.mcp_attestations | length' "$F1D/.claude/process-state.json" 2>/dev/null)")
  f1_reason=$(jq -r '.mcp_attestations[0].reason // ""' "$F1D/.claude/process-state.json" 2>/dev/null)
  f1_blocked=$(jq -r '.mcp_attestations[0].blocked_on // ""' "$F1D/.claude/process-state.json" 2>/dev/null)
  if [ "$f1_dec" = "allow" ] && [ "$f1_rows" -eq 1 ] \
     && printf '%s' "$f1_reason" | grep -q 'on a plane' \
     && printf '%s' "$f1_blocked" | grep -qi 'qdrant'; then
    pass "F1: SOLO_MCP_ATTESTED=1 with a reason allows, and the escape is DURABLY RECORDED to .claude/process-state.json::mcp_attestations[] with the operator's reason AND what was being escaped. An escape that leaves no trace is the advisory posture this work exists to replace"
  else
    fail_ "F1" "decision=$f1_dec (want allow) attestation_rows=$f1_rows (want 1) recorded_reason='$f1_reason' blocked_on='$f1_blocked'"
  fi
fi

F2D="$(newtmp)/p"
if ! mk_proj "$F2D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "F2" "fixture setup failed"
else
  run_gate "$GATE" "$F2D" "SOLO_MCP_ATTESTED=1"
  f2_dec=$(decision_of "$GATE_OUT")
  f2_reason=$(reason_of "$GATE_OUT")
  f2_rows=$(_num "$(jq -r '.mcp_attestations | length' "$F2D/.claude/process-state.json" 2>/dev/null)")
  f2_names=0
  printf '%s' "$f2_reason" | grep -q 'SOLO_MCP_REASON' && f2_names=1
  if [ "$f2_dec" = "deny" ] && [ "$f2_rows" -eq 0 ] && [ "$f2_names" -eq 1 ]; then
    pass "F2: SOLO_MCP_ATTESTED=1 with NO reason is REFUSED and records nothing — the reason is mandatory, because an unexplained escape is indistinguishable from the bypass it replaces"
  else
    fail_ "F2" "decision=$f2_dec (want deny) attestation_rows=$f2_rows (want 0) reason_names_the_variable=$f2_names (want 1)"
  fi
fi

# F3 — the property that makes the escape honest: an escape that CANNOT be
# recorded is a refusal, not a pass. Both record sinks are made unwritable by
# being directories — deterministic, and unlike chmod it also holds under root.
F3D="$(newtmp)/p"
if ! mk_proj "$F3D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "F3" "fixture setup failed"
else
  mkdir -p "$F3D/.claude/process-state.json" "$F3D/.claude/mcp-attestations.jsonl"
  run_gate "$GATE" "$F3D" "SOLO_MCP_ATTESTED=1" "SOLO_MCP_REASON=offline, and the disk is hostile"
  f3_dec=$(decision_of "$GATE_OUT")
  f3_reason=$(reason_of "$GATE_OUT")
  f3_loud=0
  printf '%s' "$f3_reason" | grep -qi 'REFUS' && f3_loud=1
  if [ "$f3_dec" = "deny" ] && [ "$f3_loud" -eq 1 ]; then
    pass "F3 (the load-bearing half): with BOTH record sinks unwritable the attested escape is REFUSED, loudly. This is BL-072's rule copied exactly — 'an attested escape must be durably logged', and a silent pass on a write failure would re-open the whole class"
  else
    fail_ "F3" "decision=$f3_dec (want deny) refusal_is_loud=$f3_loud (want 1) reason='$f3_reason'"
  fi
fi

# F4 — escapability under the very degradation the gate reports. A gate that
# cannot be satisfied honestly is a gate people delete (BL-149), so the no-jq
# refusal must still have a way through that leaves a trace.
F4D="$(newtmp)/p"
if ! mk_proj "$F4D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "F4" "fixture setup failed"
else
  run_gate "$GATE" "$F4D" "PATH=" "SOLO_MCP_ATTESTED=1" "SOLO_MCP_REASON=no jq on this host yet"
  f4_dec=$(decision_of "$GATE_OUT")
  f4_lines=0
  [ -f "$F4D/.claude/mcp-attestations.jsonl" ] && f4_lines=$(_num "$(grep -c 'no jq on this host' "$F4D/.claude/mcp-attestations.jsonl" 2>/dev/null)")
  if [ "$f4_dec" = "allow" ] && [ "$f4_lines" -eq 1 ]; then
    pass "F4: with jq absent the escape still works and still leaves a trace — the jq-free fallback sink .claude/mcp-attestations.jsonl is appended with shell builtins. Without this, the no-jq refusal would be unescapable and the whole hook would get deleted"
  else
    fail_ "F4" "decision=$f4_dec (want allow) jsonl_rows_matching_reason=$f4_lines (want 1)"
  fi
fi

echo ""
echo "=== G — hooks must never wedge the session on their OWN failure ==="

G1D="$(newtmp)/p"
if ! mk_proj "$G1D" 'this is not json {'; then
  fail_ "G1" "fixture setup failed"
else
  run_tracker "$TRACKER" "$G1D" "$(ev_success 'mcp__qdrant__qdrant-find' 'x')" --event PostToolUse
  g1_trk_rc=$TRK_RC
  run_gate "$GATE" "$G1D"
  g1_dec=$(decision_of "$GATE_OUT")
  if [ "$g1_trk_rc" -eq 0 ] && [ "$g1_dec" = "deny" ]; then
    pass "G1 (the pinned split): a MALFORMED ledger leaves the tracker at rc 0 — a tracking failure must never interrupt a build loop — while the GATE, whose job is enforcement, denies because it cannot tell. The tracker never blocks; the gate always fails closed"
  else
    fail_ "G1" "tracker_rc=$g1_trk_rc (want 0) gate_decision=$g1_dec (want deny)"
  fi
fi

G2D="$(newtmp)/p"
if ! mk_proj "$G2D" ""; then
  fail_ "G2" "fixture setup failed"
else
  run_tracker "$TRACKER" "$G2D" "$(ev_success 'mcp__qdrant__qdrant-find' 'x')" --event PostToolUse
  g2_rc=$TRK_RC
  g2_created=0
  [ -f "$G2D/.claude/tool-usage.json" ] && g2_created=1
  g2_has_req=$(jq -r 'has("mcp_requirements")' "$G2D/.claude/tool-usage.json" 2>/dev/null)
  # Both fail-closed requirements are live on a ledger with no requirements
  # object, so BOTH have to be genuinely satisfied for the gate to allow —
  # which is the point: the re-seed did not switch either of them off.
  run_gate "$GATE" "$G2D"
  g2_dec_partial=$(decision_of "$GATE_OUT")
  run_tracker "$TRACKER" "$G2D" "$(ev_success 'mcp__context7__query-docs' 'the docs')" --event PostToolUse
  run_gate "$GATE" "$G2D"
  g2_dec=$(decision_of "$GATE_OUT")
  if [ "$g2_rc" -eq 0 ] && [ "$g2_created" -eq 1 ] && [ "$g2_has_req" = "false" ] \
     && [ "$g2_dec_partial" = "deny" ] && [ "$g2_dec" = "allow" ]; then
    pass "G2: when the tracker re-creates a missing ledger it writes NO mcp_requirements object, so a re-created file can never turn a requirement OFF — it used to write qdrant_required=false and context7_required=false, disarming the gate it feeds. Both requirements stay live (one satisfied still denies) and only both satisfied allows"
  else
    fail_ "G2" "tracker_rc=$g2_rc (want 0) ledger_created=$g2_created (want 1) reseed_has_mcp_requirements=$g2_has_req (want false) decision_with_one_of_two_satisfied=$g2_dec_partial (want deny) decision_with_both_satisfied=$g2_dec (want allow)"
  fi
fi

G3D="$(newtmp)/p"
if ! mk_proj "$G3D" "$LEDGER_BOTH_REQUIRED"; then
  fail_ "G3" "fixture setup failed"
else
  run_tracker "$TRACKER" "$G3D" "$(ev_success 'mcp__qdrant__qdrant-find' 'x')" --event PostToolUse "PATH="
  g3_rc=$TRK_RC
  run_tracker "$TRACKER" "$G3D" 'not json at all' --event PostToolUse
  g3_rc2=$TRK_RC
  if [ "$g3_rc" -eq 0 ] && [ "$g3_rc2" -eq 0 ]; then
    pass "G3: the tracker exits 0 on a garbage stdin envelope and on an unexpected argv — pinned, because a PostToolUse hook that dies non-zero on its own bug would surface as a tool failure on every single call"
  else
    fail_ "G3" "rc_with_odd_argv=$g3_rc (want 0) rc_with_garbage_stdin=$g3_rc2 (want 0)"
  fi
fi

echo ""
echo "=== H — the seeds and registrations (static reads of init.sh and this repo) ==="

# The scaffolder's tool-usage.json heredoc, extracted and parsed. Static read
# only: this suite never executes the scaffolder.
H_SEED="$TOPTMP/seed.json"
awk "/cat > .claude\/tool-usage.json << 'TUEOF'/{f=1;next} f&&/^TUEOF\$/{f=0} f" "$SCAFFOLDER" > "$H_SEED" 2>/dev/null

h1_valid=0
jq -e . "$H_SEED" >/dev/null 2>&1 && h1_valid=1
h1_q=$(jq -r '.mcp_requirements.qdrant_required // "ABSENT"' "$H_SEED" 2>/dev/null)
h1_c=$(jq -r '.mcp_requirements.context7_required // "ABSENT"' "$H_SEED" 2>/dev/null)
h1_add=$(jq -r '.mcp_requirements.additional_required | length' "$H_SEED" 2>/dev/null)
if [ "$h1_valid" -eq 1 ] && [ "$h1_q" = "true" ] && [ "$h1_c" = "true" ] && [ "$(_num "$h1_add")" -eq 0 ]; then
  pass "H1: the scaffolder's tool-usage.json seed now carries an mcp_requirements object, seeded fail-CLOSED (both required=true). It contained no such object at all, which is why '.mcp_requirements.X_required // false' made every requirement default to OFF in every generated project — BL-221's shape exactly. SessionStart re-derives the real values on the first session"
else
  fail_ "H1" "seed_parses=$h1_valid qdrant_required='$h1_q' (want true) context7_required='$h1_c' (want true) additional_required_len='$h1_add' (want 0)"
fi

h2_out=$(jq -r '.qdrant_find_succeeded, .context7_query_docs_succeeded, .qdrant_find_failed' "$H_SEED" 2>/dev/null | tr '\n' ' ')
if printf '%s' "$h2_out" | grep -q 'false false 0'; then
  pass "H2: the seed also carries the OUTCOME fields the gate reads (qdrant_find_succeeded, context7_query_docs_succeeded, qdrant_find_failed), so a generated project's ledger has the same schema the gate derives from"
else
  fail_ "H2" "outcome fields in seed = '$h2_out' (want 'false false 0')"
fi

h3_reg=$(grep -c 'PostToolUseFailure' "$SCAFFOLDER" 2>/dev/null)
h3_ev=$(grep -c 'track-tool-usage.sh --event' "$SCAFFOLDER" 2>/dev/null)
if [ "$(_num "$h3_reg")" -gt 0 ] && [ "$(_num "$h3_ev")" -ge 2 ]; then
  pass "H3: the scaffolder registers the tracker on PostToolUseFailure as well as PostToolUse, each with its own --event argument. Registered on PostToolUse alone, failures were not miscounted by the framework — they were INVISIBLE to it"
else
  fail_ "H3" "PostToolUseFailure mentions in scaffolder=$h3_reg (want >0) '--event'-carrying registrations=$h3_ev (want >=2)"
fi

h4_missing=""
if [ ! -f "$REPO_SETTINGS" ]; then
  h4_missing="the file itself"
else
  for _h in session-test-gate-check.sh track-tool-usage.sh session-mcp-gate.sh; do
    grep -q "$_h" "$REPO_SETTINGS" 2>/dev/null || h4_missing="${h4_missing}${_h} "
  done
  jq -e '.hooks.PostToolUseFailure' "$REPO_SETTINGS" >/dev/null 2>&1 || h4_missing="${h4_missing}PostToolUseFailure "
  jq -e '.' "$REPO_SETTINGS" >/dev/null 2>&1 || h4_missing="${h4_missing}(invalid JSON) "
fi
if [ -z "$h4_missing" ]; then
  pass "H4: this repository's own .claude/settings.json registers the SessionStart check, the tracker on BOTH post-tool events, and the Write/Edit gate — the mechanism now fires where the framework is BUILT, not only in generated projects. The same gap hides the version-check hook"
else
  fail_ "H4" "missing from $REPO_SETTINGS: $h4_missing"
fi

echo ""
echo "=== M — mutation proofs (each mutant: sites==1, N lines changed, bash -n, fresh fixture) ==="

# mk_mirror DIR — a private copy of the two shipped hooks, mode preserved, so a
# mutant is applied to a throwaway file and never to the tree under test.
mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -p "$GATE" "$m/gate.sh" || return 1
  cp -p "$TRACKER" "$m/tracker.sh" || return 1
  return 0
}

# _mutate FILE MARKER REPLACEMENT — excise the one END-OF-LINE-anchored marked
# line and replace it. Echoes "sites changed parses".
#
# The delimiter is `%`: shell replacements are `|`-dense (`||`), and `s|old|new|`
# with a `|` in the replacement either errors or — worse — terminates the
# expression early and leaves the file UNCHANGED WHILE SED REPORTS SUCCESS.
# `&` means THE WHOLE MATCH in a replacement, so it is escaped here; an
# unescaped `&&` splices the original line back in and yields a mutant nobody
# designed, one that still passes `bash -n`. No marker or replacement in this
# file contains a `%`, and the changed-line assertion is what would catch it if
# one ever did.
_mutate() {
  local f="$1" marker="$2" repl="$3"
  local before sites changed parses safe
  safe=$(printf '%s' "$repl" | sed 's/&/\\&/g')
  before="$(mktemp)"
  cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  _sed_inplace "$f" "s%^.*${marker}\$%${safe}%"
  changed=$(_changed_lines "$before" "$f")
  parses=$(_parses "$f")
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

# ── M1: restore the silent no-file exit ─────────────────────────────────────
M1D="$(newtmp)"
if ! mk_proj "$M1D/p" "" || ! mk_mirror "$M1D/m"; then
  fail_ "M1" "fixture setup failed"
else
  run_gate "$M1D/m/gate.sh" "$M1D/p"; m1_ctl=$(decision_of "$GATE_OUT")
  m1_meta=$(_mutate "$M1D/m/gate.sh" '# BL-233-FAILCLOSED-NOFILE' '  BLOCK_REASON=""')
  set -- $m1_meta; m1_sites=$1; m1_changed=$2; m1_parses=$3
  mk_proj "$M1D/p2" ""
  run_gate "$M1D/m/gate.sh" "$M1D/p2"; m1_mut=$(decision_of "$GATE_OUT")
  if [ "$m1_ctl" = "deny" ] && [ "$m1_mut" = "allow" ] \
     && [ "$m1_sites" -eq 1 ] && [ "$m1_changed" -eq 2 ] && [ "$m1_parses" -eq 1 ]; then
    pass "M1: control denies with no ledger; with the fail-closed arm neutered the same absent ledger ALLOWS — the pre-BL-233 behaviour, restored on demand"
  else
    fail_ "M1" "control=$m1_ctl (want deny) mutant=$m1_mut (want allow) sites=$m1_sites (want 1) changed=$m1_changed (want 2) parses=$m1_parses (want 1)"
  fi
fi

# ── M2: restore the silent no-jq exit ───────────────────────────────────────
M2D="$(newtmp)"
if ! mk_proj "$M2D/p" "$LEDGER_BOTH_REQUIRED" || ! mk_mirror "$M2D/m"; then
  fail_ "M2" "fixture setup failed"
else
  run_gate "$M2D/m/gate.sh" "$M2D/p" "PATH="; m2_ctl=$(decision_of "$GATE_OUT")
  m2_meta=$(_mutate "$M2D/m/gate.sh" '# BL-233-FAILCLOSED-JQ' '  exit 0')
  set -- $m2_meta; m2_sites=$1; m2_changed=$2; m2_parses=$3
  mk_proj "$M2D/p2" "$LEDGER_BOTH_REQUIRED"
  run_gate "$M2D/m/gate.sh" "$M2D/p2" "PATH="; m2_mut=$(decision_of "$GATE_OUT")
  if [ "$m2_ctl" = "deny" ] && [ "$m2_mut" = "allow" ] \
     && [ "$m2_sites" -eq 1 ] && [ "$m2_changed" -eq 2 ] && [ "$m2_parses" -eq 1 ]; then
    pass "M2: control denies with jq unavailable; with the arm turned back into 'exit 0' the missing toolchain silently disables enforcement again"
  else
    fail_ "M2" "control=$m2_ctl (want deny) mutant=$m2_mut (want allow) sites=$m2_sites (want 1) changed=$m2_changed (want 2) parses=$m2_parses (want 1)"
  fi
fi

# ── M3: flip the missing-key default back to permissive ─────────────────────
M3D="$(newtmp)"
if ! mk_proj "$M3D/p" "$LEDGER_MISSING_QDRANT_KEY" || ! mk_mirror "$M3D/m"; then
  fail_ "M3" "fixture setup failed"
else
  run_gate "$M3D/m/gate.sh" "$M3D/p"; m3_ctl=$(decision_of "$GATE_OUT")
  m3_meta=$(_mutate "$M3D/m/gate.sh" '# BL-233-FAILCLOSED-REQ' 'QDRANT_REQUIRED=$(_flag ".mcp_requirements.qdrant_required" false)')
  set -- $m3_meta; m3_sites=$1; m3_changed=$2; m3_parses=$3
  mk_proj "$M3D/p2" "$LEDGER_MISSING_QDRANT_KEY"
  run_gate "$M3D/m/gate.sh" "$M3D/p2"; m3_mut=$(decision_of "$GATE_OUT")
  if [ "$m3_ctl" = "deny" ] && [ "$m3_mut" = "allow" ] \
     && [ "$m3_sites" -eq 1 ] && [ "$m3_changed" -eq 2 ] && [ "$m3_parses" -eq 1 ]; then
    pass "M3: control denies on a ledger with no mcp_requirements; with the default flipped from true to false the missing key is a silent opt-out again — one character, and BL-221's shape is back"
  else
    fail_ "M3" "control=$m3_ctl (want deny) mutant=$m3_mut (want allow) sites=$m3_sites (want 1) changed=$m3_changed (want 2) parses=$m3_parses (want 1)"
  fi
fi

# ── M4: read the DECLARATION instead of the OUTCOME ─────────────────────────
# This mutant is BL-231 itself: satisfaction from `qdrant_find_called`, the flag
# that is true whether the call worked or not.
M4D="$(newtmp)"
if ! mk_proj "$M4D/p" "$LEDGER_BOTH_REQUIRED" || ! mk_mirror "$M4D/m"; then
  fail_ "M4" "fixture setup failed"
else
  run_tracker "$TRACKER" "$M4D/p" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  run_gate "$M4D/m/gate.sh" "$M4D/p"; m4_ctl=$(decision_of "$GATE_OUT")
  m4_meta=$(_mutate "$M4D/m/gate.sh" '# BL-233-OUTCOME-QDRANT' 'QDRANT_OK=$(_flag ".qdrant_find_called" false)')
  set -- $m4_meta; m4_sites=$1; m4_changed=$2; m4_parses=$3
  mk_proj "$M4D/p2" "$LEDGER_BOTH_REQUIRED"
  run_tracker "$TRACKER" "$M4D/p2" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  run_gate "$M4D/m/gate.sh" "$M4D/p2"; m4_mut=$(decision_of "$GATE_OUT")
  if [ "$m4_ctl" = "deny" ] && [ "$m4_mut" = "allow" ] \
     && [ "$m4_sites" -eq 1 ] && [ "$m4_changed" -eq 2 ] && [ "$m4_parses" -eq 1 ]; then
    pass "M4 (the root cause, mutated back in): reading .qdrant_find_called — 'a matching tool was called' — instead of .qdrant_find_succeeded makes a call that reached NOTHING satisfy the gate. Same ledger, same failing round trip, opposite verdict"
  else
    fail_ "M4" "control=$m4_ctl (want deny) mutant=$m4_mut (want allow) sites=$m4_sites (want 1) changed=$m4_changed (want 2) parses=$m4_parses (want 1)"
  fi
fi

# ── M5: reintroduce the latch fast path (structural discriminator) ──────────
# The absence of a fast path cannot be greped for, so it is pinned by the line
# that reads the flag FOR THE RECORD ONLY; the mutant turns that read back into
# an authority.
M5D="$(newtmp)"
if ! mk_proj "$M5D/p" "$(printf '%s' "$LEDGER_BOTH_REQUIRED" | jq '.mcp_gate_satisfied = true')" || ! mk_mirror "$M5D/m"; then
  fail_ "M5" "fixture setup failed"
else
  run_gate "$M5D/m/gate.sh" "$M5D/p"; m5_ctl=$(decision_of "$GATE_OUT")
  m5_meta=$(_mutate "$M5D/m/gate.sh" '# BL-233-NO-LATCH' 'GATE_PRIOR=$(_flag ".mcp_gate_satisfied" false); [ "$GATE_PRIOR" = "true" ] && exit 0')
  set -- $m5_meta; m5_sites=$1; m5_changed=$2; m5_parses=$3
  mk_proj "$M5D/p2" "$(printf '%s' "$LEDGER_BOTH_REQUIRED" | jq '.mcp_gate_satisfied = true')"
  run_gate "$M5D/m/gate.sh" "$M5D/p2"; m5_mut=$(decision_of "$GATE_OUT")
  if [ "$m5_ctl" = "deny" ] && [ "$m5_mut" = "allow" ] \
     && [ "$m5_sites" -eq 1 ] && [ "$m5_changed" -eq 2 ] && [ "$m5_parses" -eq 1 ]; then
    pass "M5: control denies despite mcp_gate_satisfied=true; restore the fast path and a flag the agent itself can write ends the enforcement — 'was it satisfied once' replacing 'is it satisfied now'"
  else
    fail_ "M5" "control=$m5_ctl (want deny) mutant=$m5_mut (want allow) sites=$m5_sites (want 1) changed=$m5_changed (want 2) parses=$m5_parses (want 1)"
  fi
fi

# ── M6: let an UNRECORDABLE attestation pass ────────────────────────────────
M6D="$(newtmp)"
if ! mk_proj "$M6D/p" "$LEDGER_BOTH_REQUIRED" || ! mk_mirror "$M6D/m"; then
  fail_ "M6" "fixture setup failed"
else
  mkdir -p "$M6D/p/.claude/process-state.json" "$M6D/p/.claude/mcp-attestations.jsonl"
  run_gate "$M6D/m/gate.sh" "$M6D/p" "SOLO_MCP_ATTESTED=1" "SOLO_MCP_REASON=hostile disk"; m6_ctl=$(decision_of "$GATE_OUT")
  m6_meta=$(_mutate "$M6D/m/gate.sh" '# BL-233-ATTEST-REFUSE' '  exit 0')
  set -- $m6_meta; m6_sites=$1; m6_changed=$2; m6_parses=$3
  mk_proj "$M6D/p2" "$LEDGER_BOTH_REQUIRED"
  mkdir -p "$M6D/p2/.claude/process-state.json" "$M6D/p2/.claude/mcp-attestations.jsonl"
  run_gate "$M6D/m/gate.sh" "$M6D/p2" "SOLO_MCP_ATTESTED=1" "SOLO_MCP_REASON=hostile disk"; m6_mut=$(decision_of "$GATE_OUT")
  if [ "$m6_ctl" = "deny" ] && [ "$m6_mut" = "allow" ] \
     && [ "$m6_sites" -eq 1 ] && [ "$m6_changed" -eq 2 ] && [ "$m6_parses" -eq 1 ]; then
    pass "M6: control refuses an escape it could not record; drop the refusal and the escape passes leaving NO trace anywhere — which is precisely the advisory posture BL-233 exists to replace"
  else
    fail_ "M6" "control=$m6_ctl (want deny) mutant=$m6_mut (want allow) sites=$m6_sites (want 1) changed=$m6_changed (want 2) parses=$m6_parses (want 1)"
  fi
fi

# ── M7: make the reason optional ────────────────────────────────────────────
M7D="$(newtmp)"
if ! mk_proj "$M7D/p" "$LEDGER_BOTH_REQUIRED" || ! mk_mirror "$M7D/m"; then
  fail_ "M7" "fixture setup failed"
else
  run_gate "$M7D/m/gate.sh" "$M7D/p" "SOLO_MCP_ATTESTED=1"; m7_ctl=$(decision_of "$GATE_OUT")
  m7_meta=$(_mutate "$M7D/m/gate.sh" '# BL-233-ATTEST-REASON' '  ATTEST_REASON="${SOLO_MCP_REASON:-unspecified}"')
  set -- $m7_meta; m7_sites=$1; m7_changed=$2; m7_parses=$3
  mk_proj "$M7D/p2" "$LEDGER_BOTH_REQUIRED"
  run_gate "$M7D/m/gate.sh" "$M7D/p2" "SOLO_MCP_ATTESTED=1"; m7_mut=$(decision_of "$GATE_OUT")
  if [ "$m7_ctl" = "deny" ] && [ "$m7_mut" = "allow" ] \
     && [ "$m7_sites" -eq 1 ] && [ "$m7_changed" -eq 2 ] && [ "$m7_parses" -eq 1 ]; then
    pass "M7: control refuses a reasonless attestation; default the reason instead and SOLO_MCP_ATTESTED=1 becomes a bare bypass flag with a placeholder in the ledger"
  else
    fail_ "M7" "control=$m7_ctl (want deny) mutant=$m7_mut (want allow) sites=$m7_sites (want 1) changed=$m7_changed (want 2) parses=$m7_parses (want 1)"
  fi
fi

# ── M8: score every event as a success (tracker) ────────────────────────────
M8D="$(newtmp)"
if ! mk_proj "$M8D/p" "$LEDGER_BOTH_REQUIRED" || ! mk_mirror "$M8D/m"; then
  fail_ "M8" "fixture setup failed"
else
  run_tracker "$M8D/m/tracker.sh" "$M8D/p" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  m8_ctl=$(jqf "$M8D/p" '.qdrant_find_succeeded // false')
  # The marker sits on an `esac`, so the replacement must carry one: dropping
  # it leaves the `case` unterminated and the mutant does not parse. The
  # `bash -n` assertion is what said so — a mutation that lands as a syntax
  # error kills every downstream test for the wrong reason and would otherwise
  # have scored as a clean kill.
  m8_meta=$(_mutate "$M8D/m/tracker.sh" '# BL-233-EVENT-OUTCOME' 'esac; OUTCOME=success')
  set -- $m8_meta; m8_sites=$1; m8_changed=$2; m8_parses=$3
  mk_proj "$M8D/p2" "$LEDGER_BOTH_REQUIRED"
  run_tracker "$M8D/m/tracker.sh" "$M8D/p2" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  m8_mut=$(jqf "$M8D/p2" '.qdrant_find_succeeded // false')
  if [ "$m8_ctl" = "false" ] && [ "$m8_mut" = "true" ] \
     && [ "$m8_sites" -eq 1 ] && [ "$m8_changed" -eq 2 ] && [ "$m8_parses" -eq 1 ]; then
    pass "M8: control leaves the flag false on PostToolUseFailure; force the outcome to success and the identical failing envelope marks the requirement met. The event IS the signal — there is no field to fall back on"
  else
    fail_ "M8" "control_flag=$m8_ctl (want false) mutant_flag=$m8_mut (want true) sites=$m8_sites (want 1) changed=$m8_changed (want 2) parses=$m8_parses (want 1)"
  fi
fi

# ── M9: let resolve-library-id count as a documentation read (tracker) ──────
M9D="$(newtmp)"
if ! mk_proj "$M9D/p" "$LEDGER_BOTH_REQUIRED" || ! mk_mirror "$M9D/m"; then
  fail_ "M9" "fixture setup failed"
else
  run_tracker "$M9D/m/tracker.sh" "$M9D/p" "$(ev_success 'mcp__context7__resolve-library-id' '/qdrant/qdrant')" --event PostToolUse
  m9_ctl=$(jqf "$M9D/p" '.context7_query_docs_succeeded // false')
  m9_meta=$(_mutate "$M9D/m/tracker.sh" '# BL-233-C7-QUERYDOCS' 'esac; C7KIND=query')
  set -- $m9_meta; m9_sites=$1; m9_changed=$2; m9_parses=$3
  mk_proj "$M9D/p2" "$LEDGER_BOTH_REQUIRED"
  run_tracker "$M9D/m/tracker.sh" "$M9D/p2" "$(ev_success 'mcp__context7__resolve-library-id' '/qdrant/qdrant')" --event PostToolUse
  m9_mut=$(jqf "$M9D/p2" '.context7_query_docs_succeeded // false')
  if [ "$m9_ctl" = "false" ] && [ "$m9_mut" = "true" ] \
     && [ "$m9_sites" -eq 1 ] && [ "$m9_changed" -eq 2 ] && [ "$m9_parses" -eq 1 ]; then
    pass "M9: control does not credit an ID lookup; collapse the two Context7 tools back into one and the argument step satisfies a gate whose stated purpose is that documentation was read"
  else
    fail_ "M9" "control_flag=$m9_ctl (want false) mutant_flag=$m9_mut (want true) sites=$m9_sites (want 1) changed=$m9_changed (want 2) parses=$m9_parses (want 1)"
  fi
fi

# ── M10: suppress the empty-result report (tracker) ─────────────────────────
M10D="$(newtmp)"
if ! mk_proj "$M10D/p" "$LEDGER_BOTH_REQUIRED" || ! mk_mirror "$M10D/m"; then
  fail_ "M10" "fixture setup failed"
else
  run_tracker "$M10D/m/tracker.sh" "$M10D/p" "$(ev_success 'mcp__qdrant__qdrant-find' '')" --event PostToolUse
  m10_ctl=$(_bytes "$TRK_OUT")
  m10_meta=$(_mutate "$M10D/m/tracker.sh" '# BL-233-EMPTY-REPORT' '  :')
  set -- $m10_meta; m10_sites=$1; m10_changed=$2; m10_parses=$3
  mk_proj "$M10D/p2" "$LEDGER_BOTH_REQUIRED"
  run_tracker "$M10D/m/tracker.sh" "$M10D/p2" "$(ev_success 'mcp__qdrant__qdrant-find' '')" --event PostToolUse
  m10_mut=$(_bytes "$TRK_OUT")
  m10_still_recorded=$(jqf "$M10D/p2" '.qdrant_find_empty // false')
  if [ "$m10_ctl" -gt 0 ] && [ "$m10_mut" -eq 0 ] && [ "$m10_still_recorded" = "true" ] \
     && [ "$m10_sites" -eq 1 ] && [ "$m10_changed" -eq 2 ] && [ "$m10_parses" -eq 1 ]; then
    pass "M10: control reports the empty retrieval; suppress the report and the ledger still RECORDS it while nobody is told — an empty memory on an old project would then look exactly like a healthy one"
  else
    fail_ "M10" "control_report_bytes=$m10_ctl (want >0) mutant_report_bytes=$m10_mut (want 0) still_recorded=$m10_still_recorded (want true) sites=$m10_sites (want 1) changed=$m10_changed (want 2) parses=$m10_parses (want 1)"
  fi
fi

# ── M11: re-seed requirements OFF on a re-created ledger (structural) ───────
# The tracker's re-seed carrying NO mcp_requirements is an ABSENCE, pinned by
# the guard line that enforces it; the mutant puts the old permissive object
# back — BL-231's "tracker re-seed" row, verbatim.
M11D="$(newtmp)"
if ! mk_proj "$M11D/p" "" || ! mk_mirror "$M11D/m"; then
  fail_ "M11" "fixture setup failed"
else
  run_tracker "$M11D/m/tracker.sh" "$M11D/p" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  run_gate "$GATE" "$M11D/p"; m11_ctl=$(decision_of "$GATE_OUT")
  m11_meta=$(_mutate "$M11D/m/tracker.sh" '# BL-233-NO-REQ-RESEED' '  jq ".mcp_requirements = {\"qdrant_required\": false, \"context7_required\": false, \"additional_required\": []}" "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE"')
  set -- $m11_meta; m11_sites=$1; m11_changed=$2; m11_parses=$3
  mk_proj "$M11D/p2" ""
  run_tracker "$M11D/m/tracker.sh" "$M11D/p2" "$(ev_failure 'mcp__qdrant__qdrant-find' "$QDRANT_DOWN")" --event PostToolUseFailure
  run_gate "$GATE" "$M11D/p2"; m11_mut=$(decision_of "$GATE_OUT")
  if [ "$m11_ctl" = "deny" ] && [ "$m11_mut" = "allow" ] \
     && [ "$m11_sites" -eq 1 ] && [ "$m11_changed" -eq 2 ] && [ "$m11_parses" -eq 1 ]; then
    pass "M11: control denies after a re-created ledger and a failed call; restore the permissive re-seed and the tracker itself switches the requirement OFF — a hook whose own recovery path disarms the gate it feeds"
  else
    fail_ "M11" "control=$m11_ctl (want deny) mutant=$m11_mut (want allow) sites=$m11_sites (want 1) changed=$m11_changed (want 2) parses=$m11_parses (want 1)"
  fi
fi

echo ""
echo "=== Z — harness meta-assertion ==="

# Z1 is not a property of the code under test; it is a property of this file.
# Without it, a malformed fixture makes every hook take its "no tool_name" fast
# exit and the resulting red reads as a genuine defect. That is the exact
# failure mode `scripts/lint-fixture-envelopes.sh` was written for, one layer
# in: not the WRONG KEY, but no parseable JSON at all.
z1_bad=$(_num "$(wc -l < "$BAD_ENVELOPES" 2>/dev/null | tr -d ' ')")
if [ "$z1_bad" -eq 0 ]; then
  pass "Z1: every hook payload this suite fed to a hook parsed as JSON — so each red above is a statement about the hook, not about the fixture"
else
  fail_ "Z1" "$z1_bad malformed envelope(s) were fed to a hook — every assertion using one is meaningless:
$(cat "$BAD_ENVELOPES")"
fi

END_EPOCH=$(date +%s)
echo ""
echo "Wall clock: $((END_EPOCH - START_EPOCH))s"
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# Solo Orchestrator — post-tool hook for MCP tool usage tracking
# Logs Context7, Qdrant, and any configured MCP tool calls to .claude/tool-usage.json.
# Updates compliance state for the session-mcp-gate.sh PreToolUse enforcement hook.
# Fires after every tool call — must be fast for non-MCP tools.
#
# ── BL-233: this hook records OUTCOMES, not DECLARATIONS ────────────────────
# It used to set `qdrant_find_called = true` / `context7_called = true` from the
# TOOL NAME alone. A qdrant-find that connected to nothing and returned
# "All connection attempts failed" therefore satisfied the session gate exactly
# as a working one did (BL-231), and a Context7 ID lookup that fetches no
# documentation satisfied a gate whose stated purpose is that documentation was
# read (BL-232). Both are the same substitution: was a matching tool CALLED,
# rather than did the call WORK.
#
# ── GROUND TRUTH, measured 2026-08-13 (the docs carry no worked MCP example) ─
# Captured by registering a probe on both events and firing one failing and one
# succeeding MCP call:
#
#   A FAILED MCP CALL FIRES `PostToolUseFailure`. IT DOES NOT FIRE `PostToolUse`.
#
#   | field         | success (PostToolUse)                 | failure (PostToolUseFailure) |
#   |---------------|---------------------------------------|------------------------------|
#   | tool_response | PRESENT — array of MCP content blocks | ABSENT                       |
#   | error         | absent                                | "Error calling tool '…': …"  |
#   | is_interrupt  | —                                     | false                        |
#   | isError       | NONE ANYWHERE — MCP's own isError is not preserved by either event     |
#
# So THE EVENT IS THE SIGNAL: there is no field to test for success, and this
# hook must be registered on BOTH events or failures are not miscounted — they
# are INVISIBLE. (BL-233's own text says "read .tool_response". That is wrong:
# tool_response tells you what came BACK, not that the call worked. What it is
# genuinely good for is the separate question of whether the result was EMPTY,
# which is why the empty-retrieval arm below reads it and the outcome arm does
# not. The entry is corrected as part of WP-A.)
#
# A THIRD STATE exists: a call rejected before execution (unknown tool, schema
# validation) fires NEITHER event. It is scored `unknown` and satisfies nothing,
# which under fail-closed is correct — but it must never look like success.
#
# Registration (init.sh, and this repo's .claude/settings.json):
#   PostToolUse:        bash …/track-tool-usage.sh --event PostToolUse
#   PostToolUseFailure: bash …/track-tool-usage.sh --event PostToolUseFailure
# The --event argument is belt-and-braces: the payload's own hook_event_name is
# used when the argument is absent, and a DISAGREEMENT between the two — the
# shape a mis-registration pointing both events at PostToolUse produces — is
# scored `unknown` rather than trusted.
#
# Don't use set -e — this is an advisory post-tool hook that must NEVER block
# the agent's work. If tool-usage.json is corrupted or jq fails, the agent
# continues working and tool tracking silently degrades. This is intentional:
# a tracking failure should not interrupt a build loop or any other operation.
# The enforcement half of the split lives in session-mcp-gate.sh, which fails
# CLOSED for exactly the states this hook shrugs off. Tracker never blocks;
# gate always fails closed.
set +e

TOOL_USAGE=".claude/tool-usage.json"

# ── argv: --event <name> ────────────────────────────────────────────────────
# Unknown arguments are ignored rather than fatal — an argv this hook does not
# understand must not turn every tool call into a hook error.
EVENT_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --event)
      if [ "$#" -ge 2 ]; then EVENT_ARG="$2"; shift 2; else shift; fi
      ;;
    --event=*)
      EVENT_ARG="${1#--event=}"; shift
      ;;
    *) shift ;;
  esac
done

# Read tool info from stdin (Claude Code passes the post-tool JSON)
INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [ -z "$TOOL_NAME" ]; then
  exit 0
fi

# ── Outcome, derived from the EVENT ─────────────────────────────────────────
EVENT_PAYLOAD=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
EVENT="$EVENT_ARG"
[ -z "$EVENT" ] && EVENT="$EVENT_PAYLOAD"
if [ -n "$EVENT_ARG" ] && [ -n "$EVENT_PAYLOAD" ] && [ "$EVENT_ARG" != "$EVENT_PAYLOAD" ]; then
  # The registration and the payload disagree about which event this is. That
  # is a mis-registration, and guessing in the permissive direction is how a
  # failure gets scored as a success. Refuse to guess.
  EVENT="disagreement:${EVENT_ARG}!=${EVENT_PAYLOAD}"
fi
case "$EVENT" in
  PostToolUse)        OUTCOME=success ;;
  PostToolUseFailure) OUTCOME=failure ;;
  *)                  OUTCOME=unknown ;;
esac  # BL-233-EVENT-OUTCOME

# The error text is present only on the failure event.
TOOL_ERROR=$(echo "$INPUT" | jq -r '.error // ""' 2>/dev/null)

# Fast exit for non-MCP, non-commit tools (vast majority of calls)
case "$TOOL_NAME" in
  *context7*|*qdrant*|mcp__*) ;; # Continue to tracking logic for any MCP tool
  Bash)
    # Check if this is a git commit (to increment counter)
    BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if echo "$BASH_CMD" | grep -qE '^\s*git\s+commit' 2>/dev/null; then
      if [ -f "$TOOL_USAGE" ] && command -v jq &>/dev/null; then
        CURRENT=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
        case "$CURRENT" in ''|*[!0-9]*) CURRENT=0 ;; esac
        jq ".commits_since_last_context7 = $((CURRENT + 1))" "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
      fi
    fi
    exit 0
    ;;
  *) exit 0 ;; # Not an MCP tool, not a commit — exit fast
esac

# Ensure tool-usage.json exists.
#
# BL-233: this recovery seed deliberately carries NO `mcp_requirements` object.
# It used to write `"qdrant_required": false, "context7_required": false`, so a
# ledger this hook re-created turned every requirement OFF — a hook whose own
# recovery path disarmed the gate it feeds. Requirements are SessionStart's to
# derive from the configured MCP servers; an ABSENT object makes
# session-mcp-gate.sh fail CLOSED (its default is `true`, not `false`), which is
# the correct reading of "this file cannot tell me".
CREATED_LEDGER=0
if [ ! -f "$TOOL_USAGE" ]; then
  CREATED_LEDGER=1
  mkdir -p .claude
  cat > "$TOOL_USAGE" << 'EOF'
{
  "session_id": null,
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_find_succeeded": false,
  "qdrant_find_failed": 0,
  "qdrant_find_empty": false,
  "qdrant_find_empty_count": 0,
  "qdrant_store_called": false,
  "qdrant_store_succeeded": false,
  "context7_called": false,
  "context7_query_docs_succeeded": false,
  "context7_resolve_only_count": 0,
  "mcp_gate_satisfied": false
}
EOF
fi

command -v jq &>/dev/null || exit 0

# Belt-and-braces on the absence above, scoped to a ledger THIS invocation just
# created (never to one SessionStart or the scaffolder wrote — those carry
# derived requirements this hook has no business deleting). If the heredoc ever
# drifts back to shipping a permissive object, this strips it. Mutating this
# line into a re-seed is BL-231's "tracker re-seed" row, verbatim.
[ "$CREATED_LEDGER" = "1" ] && jq 'del(.mcp_requirements)' "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null  # BL-233-NO-REQ-RESEED

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Was the returned payload EMPTY? ─────────────────────────────────────────
# Only meaningful on the success event. `tool_response` is an ARRAY of MCP
# content blocks on a real MCP call, a plain string for some built-in tools,
# and ABSENT entirely on the failure event — all three are handled, because a
# jq filter that assumes the array shape returns null on the others and null
# would read as "empty" for a call that returned plenty.
#
# Karl's decision 1: an empty result does NOT block — it satisfies the
# retrieval requirement — but it is recorded and reported prominently. Empty is
# information on a new project and a symptom on an old one, and the two are
# indistinguishable if nobody is told.
RESPONSE_TEXT=$(echo "$INPUT" | jq -r '
  (.tool_response // null) as $r
  | if   ($r | type) == "array"  then ([$r[]? | if (type == "object") then (.text? // "") else (. | tostring) end] | join(" "))
    elif ($r | type) == "string" then $r
    elif ($r | type) == "object" then ($r | tostring)
    else "" end' 2>/dev/null)

IS_EMPTY=0
if [ "$OUTCOME" = "success" ]; then
  _stripped=$(printf '%s' "$RESPONSE_TEXT" | tr -d '[:space:]')
  if [ -z "$_stripped" ]; then
    IS_EMPTY=1
  elif printf '%s' "$RESPONSE_TEXT" | grep -qiE 'no information found|no results found|no matching (documents|entries|results)' 2>/dev/null; then
    # The qdrant MCP server's own zero-result phrasing. A gate that reads this
    # as content is the "returned something" question answered by a sentence
    # that says nothing was returned.
    IS_EMPTY=1
  fi
fi

# ── Which Context7 tool is this? ────────────────────────────────────────────
# `resolve-library-id` returns a LIST OF LIBRARY IDS and fetches no
# documentation — it is the argument step, whose entire purpose is to produce
# an argument for the call that does the work. It is ALLOWED and LOGGED, and it
# is NOT COUNTED. Both the shipped server (mcp__context7__*) and the plugin
# spelling (mcp__plugin_context7_context7__*) are matched by tool SUFFIX.
C7KIND=other
case "$TOOL_NAME" in
  *query-docs*)         C7KIND=query ;;
  *resolve-library-id*) C7KIND=resolve ;;
esac  # BL-233-C7-QUERYDOCS

# ── Append the call row (every MCP call, every outcome) ─────────────────────
# The row carries the event and the outcome so a failure is VISIBLE rather than
# absent — before BL-233 this hook was registered on PostToolUse only, so a
# failed call produced no row at all and the framework could not tell a broken
# server from an idle one.
jq --arg tool "$TOOL_NAME" --arg ts "$TIMESTAMP" --arg ev "$EVENT" --arg oc "$OUTCOME" --argjson empty "$IS_EMPTY" \
  '.calls += [{"tool": $tool, "timestamp": $ts, "event": $ev, "outcome": $oc, "empty_result": ($empty == 1)}]' \
  "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null

if [ "$OUTCOME" = "failure" ] && [ -n "$TOOL_ERROR" ]; then
  jq --arg err "$TOOL_ERROR" --arg tool "$TOOL_NAME" \
    '.last_mcp_error = $err | .last_mcp_error_tool = $tool' \
    "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
fi

# ── Context7 ────────────────────────────────────────────────────────────────
if echo "$TOOL_NAME" | grep -q "context7" 2>/dev/null; then
  # context7_called stays name-derived on purpose: it is the OBSERVABILITY
  # field ("a Context7 tool was invoked"), kept for the reminder/validate
  # surfaces. It is no longer what the gate reads.
  jq '.context7_called = true' "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null

  if [ "$C7KIND" = "query" ] && [ "$OUTCOME" = "success" ]; then
    # A real documentation read. This is the only thing that satisfies the
    # Context7 requirement, and the only thing that may reset the commit-time
    # staleness counter — an ID lookup used to silence that nudge too.
    jq '.context7_query_docs_succeeded = true | .commits_since_last_context7 = 0' \
      "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
  elif [ "$C7KIND" = "resolve" ]; then
    jq '.context7_resolve_only_count = ((.context7_resolve_only_count // 0) + 1)' \
      "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
  fi
fi

# ── Qdrant ──────────────────────────────────────────────────────────────────
if echo "$TOOL_NAME" | grep -q "qdrant" 2>/dev/null; then
  if echo "$TOOL_NAME" | grep -q "find" 2>/dev/null; then
    jq '.qdrant_find_called = true' "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
    if [ "$OUTCOME" = "success" ]; then  # BL-233-QDRANT-SUCCESS
      jq --argjson empty "$IS_EMPTY" \
        '.qdrant_find_succeeded = true
         | .qdrant_find_empty = ($empty == 1)
         | .qdrant_find_empty_count = ((.qdrant_find_empty_count // 0) + $empty)' \
        "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
    else
      jq '.qdrant_find_failed = ((.qdrant_find_failed // 0) + 1)' \
        "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
    fi
  elif echo "$TOOL_NAME" | grep -q "store" 2>/dev/null; then
    jq '.qdrant_store_called = true' "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
    if [ "$OUTCOME" = "success" ]; then
      jq '.qdrant_store_succeeded = true' "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
    fi
  fi
fi

# ── Report, prominently ─────────────────────────────────────────────────────
# additionalContext is the documented channel for a post-tool hook to tell the
# AGENT something, which is who needs to know; the durable half is the ledger
# field written above, and it is written whether or not this line is reached.
# Only the two states worth interrupting for are reported: a retrieval that
# returned nothing, and a call that failed.
if [ "$IS_EMPTY" = "1" ] && echo "$TOOL_NAME" | grep -q "qdrant" 2>/dev/null; then
  printf '{"hookSpecificOutput": {"hookEventName": "%s", "additionalContext": "QDRANT EMPTY RESULT: %s returned no stored context. This does NOT block you — an empty semantic memory is expected on a new project. On an established one it means nothing was ever stored, so the retrieval half has nothing behind it. Report it to the Orchestrator and store what this session learns."}}\n' "$EVENT" "$TOOL_NAME"  # BL-233-EMPTY-REPORT
elif [ "$OUTCOME" = "failure" ]; then
  _err_escaped=$(printf '%s' "$TOOL_ERROR" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r\t')
  printf '{"hookSpecificOutput": {"hookEventName": "%s", "additionalContext": "MCP CALL FAILED: %s did not execute (%s). This is RECORDED and it does NOT satisfy any session requirement — the framework now distinguishes configured-but-unreachable from not-configured. Fix the server or attest the exception; do not retry silently and proceed."}}\n' "$EVENT" "$TOOL_NAME" "$_err_escaped"
fi

exit 0

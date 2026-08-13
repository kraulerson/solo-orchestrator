#!/usr/bin/env bash
# Solo Orchestrator — PreToolUse hook for MCP session-start enforcement
# Blocks Write and Edit tool calls until required MCP tools have SUCCEEDED.
# Registered as a PreToolUse hook on Write and Edit tool calls.
#
# This closes the enforcement gap identified in the hook architecture:
# session-start MCP requirements (qdrant-find, context7) were advisory only.
# This hook makes them mechanical — the agent cannot produce output until
# it has loaded prior context and verified library documentation.
#
# ── BL-233: every layer here asked whether something was DECLARED ───────────
# The intent above was right; the enforcement was not. Four separate arms
# exited 0 in silence — absent ledger, absent jq, a missing requirement key
# defaulting to "not required", and a latch that made "satisfied once" mean
# "satisfied forever" — and satisfaction itself was read from a flag set by
# TOOL NAME, so a qdrant-find that returned "All connection attempts failed"
# passed the gate (BL-231) and a Context7 ID lookup that fetched no
# documentation passed a gate whose stated purpose is that documentation was
# read (BL-232). Every one of those is the same substitution.
#
# Three rules now hold, and each one is mutation-proved in
# tests/test-bl233-mcp-outcome-enforcement.sh:
#
#   1. SATISFACTION IS AN OUTCOME. The gate reads qdrant_find_succeeded /
#      context7_query_docs_succeeded, which track-tool-usage.sh sets only from
#      the hook EVENT (a failed MCP call fires PostToolUseFailure, never
#      PostToolUse — measured 2026-08-13; there is no isError field anywhere,
#      so the event is the only signal).
#   2. "CANNOT TELL" IS NOT "SATISFIED". Every degraded state DENIES, and the
#      refusal text says which state it is in. `# BL-112-SAST-NOTRUN`'s shipped
#      doctrine, one subsystem over: "the scanner did not run" must never read
#      as "the scanner found nothing."
#   3. THREE STATES, NOT TWO. reachable / configured-but-unreachable /
#      not-configured are separately reported. Not-configured is a determinate
#      answer and ALLOWS; unreachable BLOCKS, and says so in those words.
#
# ── THE LATCH — decided deliberately (BL-233 item 5) ───────────────────────
# `mcp_gate_satisfied` is written into .claude/tool-usage.json, a file the
# agent itself can edit. A latch there is a self-signed permission slip, so
# THIS HOOK NEVER TAKES A FAST PATH ON IT. The field is still written, as a
# record of the last derivation, and it is RE-DERIVED on every invocation —
# read for the transcript, never for the decision.
#
# What that costs: a few small jq reads per Write/Edit instead of one. What it
# buys: the gate answers "is it satisfied NOW" rather than "was it satisfied
# once". Session scope comes from the ledger's own lifecycle, which is left
# exactly as `5b1a081` fixed it — SessionStart's `startup` path resets the
# outcome flags, and resume/compact/clear MERGE so a satisfied requirement is
# not re-armed mid-Build-Loop. Re-arming there was the destructive behaviour
# 5b1a081 removed, and re-introducing it through the back door of a latch
# reset would undo that fix.
#
# ── set -e is deliberately NOT set ─────────────────────────────────────────
# Under `set -e` an unexpected non-zero anywhere exits non-zero, and a
# PreToolUse hook exiting non-zero-but-not-2 is a NON-BLOCKING error — it
# would fail OPEN, which is the whole bug class. Instead: no `set -e`, every
# read routed through _flag/_count which sanitize to the BLOCKING default, and
# every exit path explicit.
#
# Input: Claude Code passes tool input JSON on stdin
# Output:
#   - No output = allow
#   - JSON with permissionDecision: "deny" = block
set -uo pipefail

TOOL_USAGE=".claude/tool-usage.json"
PROCESS_STATE=".claude/process-state.json"
ATTEST_JSONL=".claude/mcp-attestations.jsonl"

# THE ESCAPE IS LAUNCH-TIME, and the hint must say so rather than implying a
# retry. A PreToolUse hook inherits the environment Claude Code started with,
# and unlike BL-072's TDD escape — which rides the `git commit` command line, so
# an operator can set it per commit — there is no way to attach an env var to a
# single Write. "Re-run with SOLO_MCP_REASON=…" is advice that cannot be
# followed mid-session; a gate whose escape route does not exist is one people
# route around (`## BL-149:`), so the honest paths are named explicitly and in
# preference order.
ESCAPE_HINT="MID-SESSION, the ways through are: (1) make the call succeed — start the server (Qdrant: docker start, port 6333) and call the tool again, which is the outcome this gate exists to produce; or (2) if it genuinely cannot be satisfied — offline, a project with no prior memory, a change that involves no library — EXIT and restart the session with the attestation exported: SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='<why>' claude. The variables are read from the session's environment, so they cannot be attached to a single Write after the session has started. The reason is MANDATORY, the escape is RECORDED to .claude/process-state.json::mcp_attestations[] (or .claude/mcp-attestations.jsonl if jq is unavailable), and it is REFUSED if neither record can be written."

# _scrub_ctl STRING — sets SCRUBBED to STRING with every control byte
# U+0001-U+001F replaced by a space.
#
# WHY THE WHOLE CLASS AND NOT A LIST. This function replaces an escaper that
# handled `\\`, `"`, `\n` and `\t` — the characters that came to mind, not the
# class. `\r` alone defeated it, and the text being escaped is NOT OURS: the
# UNREACHABLE arm splices `last_mcp_error`, which is the remote server's own
# message, and the attestation arms splice the operator's free text. `jq -r`
# emits those bytes raw, so whatever the server says arrives intact.
#
# What an unescaped control byte costs is a FAIL-OPEN, and a durable one. The
# hook exits 0, Claude Code parses stdout for a decision, and an unparseable
# envelope means "no decision — normal permission flow applies": the block is
# silently dropped. Because `last_mcp_error` persists in the ledger, the gate
# then keeps failing open for the rest of the session. The strictest posture
# and the weakest outcome, from the same input.
#
# `printf -v` and parameter expansion are BUILTINS, so this works with an empty
# PATH — which it must, because the no-jq refusal is emitted through here and
# cannot use jq to build its JSON the way the tracker does. U+0000 is not in
# the loop: a bash string cannot hold a NUL (it would terminate the value), so
# one can never reach the envelope through a shell variable.
SCRUBBED=""
_scrub_ctl() {
  local s="$1" i ch
  for i in 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f; do
    printf -v ch "\\x$i"
    s=${s//"$ch"/ }
  done
  SCRUBBED="$s"
}

# deny REASON — emit the PreToolUse deny envelope, then exit 0.
#
# printf and parameter expansion only, no cat/heredoc/sed: the no-jq arm must
# be able to report a missing toolchain without depending on that toolchain,
# and this function is what it reports through. It works with an EMPTY PATH.
#
# Order matters: scrub the control class FIRST, then escape `\` and `"`. The
# scrub only ever introduces spaces, so it cannot manufacture an escape the
# following two lines would then miss.
deny() {
  local reason="$1"
  _scrub_ctl "$reason"; reason="$SCRUBBED"  # BL-233-CTL-SCRUB
  reason=${reason//\\/\\\\}
  reason=${reason//\"/\\\"}
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$reason"
  exit 0
}

# _flag JQPATH DEFAULT — read a boolean from the ledger, FAIL CLOSED on
# anything unexpected (missing key, null, malformed file, jq error). The
# default is supplied by the caller precisely so that "required" and
# "satisfied" can default in OPPOSITE directions: unknown requirement ⇒ true,
# unknown satisfaction ⇒ false. Both of those block.
#
# NO `// default` INSIDE THE JQ FILTER, and this is not a style preference.
# jq's alternative operator treats `false` exactly like `null`, so
# `.qdrant_required // true` on an explicit `false` yields TRUE — the honest
# "this server is not configured" answer would be silently upgraded to
# "required", and a project with no MCP servers could never write a file. The
# missing-key default has to be applied HERE, where `false` and `null` are
# still distinguishable. (`jq -r` prints the literal `null` for a missing key
# at rc 0, which is the same shape `## BL-203:` was filed for.)
_flag() {
  local v
  v=$(jq -r "$1" "$TOOL_USAGE" 2>/dev/null)
  case "$v" in
    true)  printf 'true\n' ;;
    false) printf 'false\n' ;;
    *)     printf '%s\n' "$2" ;;
  esac
}

# _count JQPATH — a non-negative integer, 0 on anything unexpected.
_count() {
  local v
  v=$(jq -r "$1 // 0" "$TOOL_USAGE" 2>/dev/null)
  case "$v" in ''|*[!0-9]*) v=0 ;; esac
  printf '%s\n' "$v"
}

# mcp_record_attestation REASON BLOCKED_ON — durably log an attested escape.
# Returns 0 only on a write that actually landed, 1 on ANY failure; the caller
# must be loud and REFUSE on 1. Modelled on `# BL-072-TDD-ENFORCE`'s
# tdd_record_attestation, with one addition: a jq-free fallback sink.
#
# Why the fallback exists. The primary sink needs jq, and one of the states
# this gate blocks on IS "jq is missing" — so a jq-only recorder would make the
# no-jq refusal UNESCAPABLE, and `## BL-149:` says a gate people cannot satisfy
# honestly is a gate they delete. The fallback appends one JSON object per line
# with shell builtins alone. An escape is refused only when BOTH sinks fail.
#
# Every write is wrapped in a `( … ) 2>/dev/null` SUBSHELL, not given a
# trailing `2>/dev/null`. A redirection onto an unwritable target fails in the
# shell BEFORE the command's own stderr redirect is installed, so the error
# text lands on the real stderr — and a hook that prints anything alongside its
# JSON envelope has emitted a malformed decision. The subshell's stderr is
# already redirected when the inner redirection is attempted.
#
# `mkdir` and `date` are EXTERNAL binaries and one of the states this gate
# blocks on is an empty PATH, so neither may be load-bearing: a missing mkdir
# is not itself a failure to record (the append below decides that), and a
# missing date degrades the timestamp rather than the record.
mcp_record_attestation() {
  local reason="$1" blocked="$2" now="" tmp ok=1
  [ -d .claude ] || ( mkdir -p .claude ) 2>/dev/null

  if command -v jq >/dev/null 2>&1; then
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    if [ ! -f "$PROCESS_STATE" ]; then
      ( printf '%s\n' '{}' > "$PROCESS_STATE" ) 2>/dev/null
    fi
    if [ -f "$PROCESS_STATE" ]; then
      tmp="$PROCESS_STATE.tmp.$$"
      if ( jq --arg date "$now" --arg reason "$reason" --arg blocked "$blocked" \
             '.mcp_attestations = ((.mcp_attestations // []) + [{date:$date, reason:$reason, blocked_on:$blocked}])' \
             "$PROCESS_STATE" > "$tmp" && mv "$tmp" "$PROCESS_STATE" ) 2>/dev/null; then
        ok=0
      fi
      ( rm -f "$tmp" ) 2>/dev/null
    fi
  fi

  # Fallback sink — builtins only, so it survives the no-jq state. Same
  # control-class scrub as deny(): this line is hand-built JSON carrying the
  # operator's free text, and a record nothing can parse is not a record. The
  # sink counted the write as "recorded" whether or not the line was valid,
  # so a stray CR in a reason produced an escape whose only trace was corrupt.
  local r b
  _scrub_ctl "$reason"; r="$SCRUBBED"
  _scrub_ctl "$blocked"; b="$SCRUBBED"
  r=${r//\\/\\\\}; r=${r//\"/\\\"}
  b=${b//\\/\\\\}; b=${b//\"/\\\"}
  if ( printf '{"date": "%s", "reason": "%s", "blocked_on": "%s"}\n' "${now:-unknown}" "$r" "$b" >> "$ATTEST_JSONL" ) 2>/dev/null; then
    ok=0
  fi

  return "$ok"
}

# ── Derive the block reason (empty string = allow) ──────────────────────────
BLOCK_REASON=""
GATE_PRIOR="unknown"

if ! command -v jq >/dev/null 2>&1; then
  BLOCK_REASON="MCP SESSION GATE — CANNOT VERIFY: jq is not installed, so this hook cannot read .claude/tool-usage.json and cannot tell whether the required MCP tools succeeded this session. That is 'cannot tell', which is NOT 'satisfied'. Install jq and retry."  # BL-233-FAILCLOSED-JQ
elif [ ! -f "$TOOL_USAGE" ]; then
  BLOCK_REASON="MCP SESSION GATE — CANNOT VERIFY: the tracking ledger .claude/tool-usage.json is ABSENT, so this hook cannot tell whether the required MCP tools succeeded this session. That is 'cannot tell', which is NOT 'satisfied'. Start a session so the SessionStart hook writes the ledger (scripts/session-test-gate-check.sh), or verify the hooks are installed with scripts/verify-install.sh."  # BL-233-FAILCLOSED-NOFILE
else
  # Read for the transcript ONLY. Turning this into a fast path is the latch
  # this hook deliberately does not have — see the header.
  GATE_PRIOR=$(_flag '.mcp_gate_satisfied' false)  # BL-233-NO-LATCH

  # A MISSING requirement key defaults to REQUIRED. An absent key means the
  # ledger cannot tell us, and `## BL-221:` is what the permissive reading of
  # that costs: `// false` made every requirement silently OFF in every
  # generated project, because the scaffolder seeded no mcp_requirements at all.
  QDRANT_REQUIRED=$(_flag '.mcp_requirements.qdrant_required' true)  # BL-233-FAILCLOSED-REQ
  CONTEXT7_REQUIRED=$(_flag '.mcp_requirements.context7_required' true)  # BL-233-FAILCLOSED-REQ-C7

  QDRANT_OK=$(_flag '.qdrant_find_succeeded' false)  # BL-233-OUTCOME-QDRANT
  CONTEXT7_OK=$(_flag '.context7_query_docs_succeeded' false)  # BL-233-OUTCOME-C7

  QDRANT_FAILS=$(_count '.qdrant_find_failed')
  C7_RESOLVE_ONLY=$(_count '.context7_resolve_only_count')
  LAST_ERR=$(jq -r '.last_mcp_error // ""' "$TOOL_USAGE" 2>/dev/null)

  # Qdrant — three states, distinguishable in the output.
  if [ "$QDRANT_REQUIRED" = "true" ] && [ "$QDRANT_OK" = "false" ]; then
    if [ "$QDRANT_FAILS" -gt 0 ]; then
      BLOCK_REASON="${BLOCK_REASON}qdrant-find was CALLED $QDRANT_FAILS time(s) this session and EVERY call FAILED (last error: ${LAST_ERR:-unrecorded}). The server is CONFIGURED BUT UNREACHABLE — which is a different state from not-configured, and is not 'satisfied'. Nothing was retrieved, so there is no prior context loaded. Start the Qdrant server (docker ps / port 6333) and call qdrant-find again. "  # BL-233-UNREACHABLE
    else
      BLOCK_REASON="${BLOCK_REASON}qdrant-find has not returned successfully this session (retrieve prior session context before starting work). "
    fi
  fi

  # Context7 — require the call that FETCHES DOCUMENTATION. resolve-library-id
  # returns a list of library IDs and reads nothing; it is the argument step.
  if [ "$CONTEXT7_REQUIRED" = "true" ] && [ "$CONTEXT7_OK" = "false" ]; then
    if [ "$C7_RESOLVE_ONLY" -gt 0 ]; then
      BLOCK_REASON="${BLOCK_REASON}context7 resolve-library-id succeeded $C7_RESOLVE_ONLY time(s), but it fetches NO documentation — it only returns library IDs. Call mcp__context7__query-docs with that ID to actually read the docs. "  # BL-233-C7-RESOLVE-ONLY
    else
      BLOCK_REASON="${BLOCK_REASON}context7 query-docs has not returned successfully this session (read current library documentation before writing). "
    fi
  fi

  # Operator-configured additional requirements — same outcome footing: a call
  # row only counts if its recorded outcome is success.
  ADDITIONAL=$(jq -r '.mcp_requirements.additional_required // [] | .[]' "$TOOL_USAGE" 2>/dev/null)
  if [ -n "$ADDITIONAL" ]; then
    while IFS= read -r tool_pattern; do
      [ -z "$tool_pattern" ] && continue
      TOOL_OK=$(jq --arg pat "$tool_pattern" '[.calls[]? | select((.tool // "") | test($pat)) | select((.outcome // "") == "success")] | length > 0' "$TOOL_USAGE" 2>/dev/null)
      if [ "$TOOL_OK" != "true" ]; then
        BLOCK_REASON="${BLOCK_REASON}${tool_pattern} (required MCP tool has not returned successfully this session). "  # BL-233-ADDITIONAL-OUTCOME
      fi
    done <<< "$ADDITIONAL"
  fi
fi

# ── Allow ───────────────────────────────────────────────────────────────────
if [ -z "$BLOCK_REASON" ]; then
  if command -v jq >/dev/null 2>&1 && [ -f "$TOOL_USAGE" ]; then
    # The UPWARD half of the re-derivation. Nothing else in the framework reads
    # this field, so deleting this line changes no decision and no other test —
    # which is exactly why it needs its own assertion (D2) and its own mutant
    # (M12) rather than three prose claims that it happens.
    jq '.mcp_gate_satisfied = true' "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null  # BL-233-LATCH-RECORD-UP
  fi
  exit 0
fi

BLOCK_REASON="${BLOCK_REASON% }"

# Re-derive the recorded flag DOWNWARD too, so a stale `true` left by an
# earlier derivation (or written by hand) never survives a run that blocked.
if command -v jq >/dev/null 2>&1 && [ -f "$TOOL_USAGE" ]; then
  jq '.mcp_gate_satisfied = false' "$TOOL_USAGE" > "$TOOL_USAGE.tmp" 2>/dev/null && mv "$TOOL_USAGE.tmp" "$TOOL_USAGE" 2>/dev/null
fi

# ── The attested escape (BL-072's shape) ────────────────────────────────────
if [ "${SOLO_MCP_ATTESTED:-0}" = "1" ]; then
  ATTEST_REASON="${SOLO_MCP_REASON:-}"  # BL-233-ATTEST-REASON
  if [ -z "$ATTEST_REASON" ]; then
    deny "MCP SESSION GATE — ATTESTATION REFUSED: SOLO_MCP_ATTESTED=1 was set with no SOLO_MCP_REASON. The reason is MANDATORY — an unexplained escape is indistinguishable from the advisory posture this gate replaced, and it is the reason that makes the record worth keeping. Re-run with SOLO_MCP_REASON='<why this cannot be satisfied>'. Blocked on: $BLOCK_REASON"
  fi
  if mcp_record_attestation "$ATTEST_REASON" "$BLOCK_REASON"; then
    exit 0
  fi
  # LOUD failure — an attested escape MUST be on the record; never a silent pass.
  deny "MCP SESSION GATE — ATTESTATION REFUSED: SOLO_MCP_ATTESTED=1 with a reason, but the attestation could NOT be durably recorded to either .claude/process-state.json::mcp_attestations[] or .claude/mcp-attestations.jsonl (disk/permissions/jq). REFUSING the write — an attested escape must be durably logged, and an escape that leaves no trace is exactly the advisory posture this gate exists to replace. Fix the write error and retry. Blocked on: $BLOCK_REASON"  # BL-233-ATTEST-REFUSE
fi

STALE_NOTE=""
if [ "$GATE_PRIOR" = "true" ]; then
  STALE_NOTE=" NOTE: .claude/tool-usage.json carried mcp_gate_satisfied=true, but this gate re-derives on every call and the requirement is NOT satisfied now — the flag has been corrected."
fi

deny "MCP SESSION GATE — REQUIREMENTS NOT MET. Before making any file changes you must SUCCESSFULLY call: $BLOCK_REASON A tool that was called but errored does not count; the framework reads the hook event, not the tool name.$STALE_NOTE $ESCAPE_HINT"

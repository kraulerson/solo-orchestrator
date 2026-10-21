#!/usr/bin/env bash
# Solo Orchestrator — SessionStart hook for test gate enforcement and MCP requirements
# Checks Phase 2 test gate state, detects configured MCP servers, initializes
# session-start enforcement requirements.
# Only outputs when something needs attention.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse SessionStart envelope ──────────────────────────────────
# Claude Code passes a SessionStart envelope on stdin with a `source`
# field whose value is one of:
#   "startup" — first session of the project (or a new conversation)
#   "resume"  — `claude --resume`, picking up a prior session
#   "compact" — `/compact` invocation mid-session
#   "clear"   — `/clear` invocation mid-session
#
# Pre-fix, this hook destructively overwrote .claude/tool-usage.json on
# every invocation, zeroing the calls array and the
# commits_since_last_context7 counter — re-arming the MCP gate and
# erasing in-flight Context7 / Qdrant history mid-Build-Loop on every
# /compact. Now we only do the destructive init on startup (or when the
# envelope is missing — legacy compatibility for non-Claude-Code
# invocations); the other three sources merge into the existing file.
SESSION_SOURCE="startup"
if [ ! -t 0 ]; then
  ENVELOPE=$(cat 2>/dev/null || echo "")
  if [ -n "$ENVELOPE" ] && command -v jq >/dev/null 2>&1; then
    parsed=$(echo "$ENVELOPE" | jq -r '.source // ""' 2>/dev/null || echo "")
    case "$parsed" in
      startup|resume|compact|clear) SESSION_SOURCE="$parsed" ;;
    esac
  fi
fi

# ── MCP Server Discovery ─────────────────────────────────────────
# Detect which MCP servers are configured and set up enforcement requirements.
# Known servers (set up by init.sh): context7, qdrant
# Unknown servers: anything else the user configured — flag for awareness.

QDRANT_CONFIGURED=false
CONTEXT7_CONFIGURED=false
UNKNOWN_SERVERS=""

if command -v jq &>/dev/null; then
  # `## BL-311:` THE USER FILES ARE THE ONES THIS SESSION READS. With
  # CLAUDE_CONFIG_DIR set, Claude Code keeps `.claude.json` and `settings.json`
  # inside that directory and does NOT read `~/.claude.json` — so a server
  # registered only there is not in the session, and treating it as configured
  # made it REQUIRED: every Write/Edit blocked on a tool that could not be
  # called. This hook sources nothing by design, so the rule is inline; its one
  # owner is helpers-core.sh's soif_claude_config_dir / soif_claude_json_path,
  # and this line is their sync sibling.
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then _cc_set="$CLAUDE_CONFIG_DIR/settings.json"; _cc_json="$CLAUDE_CONFIG_DIR/.claude.json"; else _cc_set="$HOME/.claude/settings.json"; _cc_json="$HOME/.claude.json"; fi   # BL-311-GATE-CONFIG
  # Collect all configured MCP server names from all settings scopes
  ALL_MCP_SERVERS=""
  for settings_file in "$_cc_set" "$_cc_json" ".claude/settings.json" ".claude/settings.local.json"; do
    if [ -f "$settings_file" ]; then
      SERVERS=$(jq -r '.mcpServers // {} | keys[]' "$settings_file" 2>/dev/null || true)
      if [ -n "$SERVERS" ]; then
        ALL_MCP_SERVERS="${ALL_MCP_SERVERS}${SERVERS}"$'\n'
      fi
    fi
  done

  # Deduplicate
  ALL_MCP_SERVERS=$(echo "$ALL_MCP_SERVERS" | sort -u | grep -v '^$' || true)

  # Classify each server
  while IFS= read -r server; do
    [ -z "$server" ] && continue
    case "$server" in
      context7|context7-mcp)
        CONTEXT7_CONFIGURED=true
        ;;
      qdrant|mcp-server-qdrant)
        QDRANT_CONFIGURED=true
        ;;
      *)
        # Unknown MCP server — user-configured
        UNKNOWN_SERVERS="${UNKNOWN_SERVERS}${server}, "
        ;;
    esac
  done <<< "$ALL_MCP_SERVERS"
fi

# ── Initialize / merge Tool Usage Tracking ───────────────────────
# BL-314: every write of the ledger goes through the same locked, unique-temp
# writer as track-tool-usage.sh and session-mcp-gate.sh. A `cat >` truncates
# the ledger in place, so a concurrent reader saw it empty, and the unlocked
# merge could land over a tracker's row. Without the lib (or jq) no ledger can
# be written, so a startup removes the one that is there: an inherited ledger's
# `true` flags would otherwise let the first Write through (BL-236). The gate
# then reports the ledger absent and points at verify-install.
TOOL_USAGE=".claude/tool-usage.json"
LW_READY=0
# Loaded through a trial in a subshell, as track-tool-usage.sh does, keyed on
# the functions it defines. An old or mismatched lib that loads but lacks
# _lw_put would otherwise pass, and the startup write below would fail as if
# the disk were full. On bash 3.2, under this hook's `set -e`, a lib with a
# syntax error or no read permission also ends the shell at the `.` even
# inside an `if` (bash 4.0 and later carry on), before the reset and the note.
if ( . "$SCRIPT_DIR/lib/ledger-write.sh" && command -v _lw_update && command -v _lw_put && command -v _lw_traps ) >/dev/null 2>&1; then   # BL-314-SESSION-LIB-TRIAL
  # shellcheck source=scripts/lib/ledger-write.sh
  . "$SCRIPT_DIR/lib/ledger-write.sh" && _lw_traps && LW_READY=1
fi
# `## BL-335:` _add_raw FILE — the text inside FILE's additional_required list,
# whitespace collapsed, or nothing when the file names no non-empty list. It
# reads text, not JSON, so it works where jq does not (absent, or the file is
# not valid JSON). It is only ever PRINTED, so the operator can add the entries
# again; a list it found this way is never carried, because text cut out of a
# broken file is not known to be the list.
_add_raw() {
  local t="" r="" s=""
  [ -f "$1" ] || return 0
  t=$(cat "$1" 2>/dev/null) || return 0
  case "$t" in *'"additional_required"'*) ;; *) return 0 ;; esac
  r=${t#*'"additional_required"'}
  r=${r%%]*}
  s=${r//[[:space:]]/}
  case "$s" in ':['*) ;; *) return 0 ;; esac
  r=${r#*\[}
  r=$(printf '%s' "$r" | tr -s '[:space:]' ' ')
  r=${r# }; r=${r% }
  if [ "${#r}" -gt 300 ]; then r="${r:0:300} ..."; fi
  printf '%s' "$r"
}
# _add_lost_note FILE WHY — sets ADD_NOTE when FILE names a non-empty list that
# this start cannot carry, and says why in one line.
ADD_NOTE=""
_add_lost_note() {
  local raw=""
  raw=$(_add_raw "$1")
  [ -n "$raw" ] || return 0
  ADD_NOTE="MCP REQUIREMENTS NOTE: $1 listed extra required MCP tools under mcp_requirements.additional_required ($raw), and this session start could not carry them over because $2. Add them to that list again."
}

if [ "$LW_READY" = "1" ] && command -v jq &>/dev/null; then
  SESSION_ID=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p .claude

  # `## BL-335:` THE OPERATOR'S EXTRA MCP REQUIREMENTS SURVIVE EVERY REWRITE.
  # mcp_requirements.additional_required is the list the MCP SERVER NOTICE below
  # tells the Orchestrator to edit, and session-mcp-gate.sh enforces it
  # (`# BL-233-ADDITIONAL-OUTCOME`). The startup heredoc and the jq-failure
  # fallback used to write `[]`, so an entry lasted until the next fresh session.
  # It is a REQUIREMENT, not a satisfaction: the startup still empties calls[]
  # and leaves out the outcome flags (BL-236, below), so a carried entry blocks
  # until its tool returns successfully in this session. Read once, here, for
  # all three writes. Only non-empty strings are kept; what is dropped, or lost
  # because the ledger is not valid JSON, is said in one line.
  ADD_REQ='[]'; ADD_DROPPED=0
  if [ -s "$TOOL_USAGE" ]; then
    if ADD_READ=$(jq -rs '(if length != 1 then error("not one JSON value") else (.[0] | try .mcp_requirements.additional_required catch null) end) as $a | if $a == null then [[], 0] elif ($a | type) == "array" then [$a[] | select(type == "string" and length > 0)] as $k | [$k, ($a | length) - ($k | length)] else [[], 1] end | "\(.[1]) \(.[0] | tojson)"' "$TOOL_USAGE" 2>/dev/null); then   # BL-335-READ
      ADD_DROPPED=${ADD_READ%% *}
      ADD_REQ=${ADD_READ#* }
      case "$ADD_DROPPED" in ''|*[!0-9]*) ADD_DROPPED=0 ;; esac
      if [ "$ADD_DROPPED" -gt 0 ]; then
        ADD_NOTE="MCP REQUIREMENTS NOTE: $ADD_DROPPED value(s) under mcp_requirements.additional_required in $TOOL_USAGE were not tool-name patterns and were dropped. It must be a list of non-empty strings, such as [\"mcp__sentry__\"]; the valid entries were kept."   # BL-335-DROP-NOTE
      fi
    else
      _add_lost_note "$TOOL_USAGE" "the file is not valid JSON, so it was rewritten"   # BL-335-UNREADABLE
    fi
  fi

  if [ "$SESSION_SOURCE" != "startup" ] && [ -f "$TOOL_USAGE" ]; then
    # Merge path: preserve in-flight ledger state (calls, counters,
    # flags), refresh session_id so the boundary is visible to a
    # successor, re-derive the MCP requirements in case the user added
    # or removed servers between sessions, and write back the
    # operator's additional_required as read and checked above.
    if ! _lw_update \
        --arg sid "$SESSION_ID" \
        --argjson qreq "$QDRANT_CONFIGURED" \
        --argjson creq "$CONTEXT7_CONFIGURED" \
        --argjson add "$ADD_REQ" \
        '. as $orig |
         $orig
         | .session_id = $sid
         | .mcp_requirements.qdrant_required = $qreq
         | .mcp_requirements.context7_required = $creq
         | .mcp_requirements.additional_required = $add'; then   # BL-335-MERGE
      # If jq fails (malformed prior file, etc.), fall through to a
      # fresh write so the gate is not left wedged.
      _lw_put << TUEOF
{
  "session_id": "$SESSION_ID",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false,
  "context7_called": false,
  "mcp_gate_satisfied": false,
  "mcp_requirements": {
    "qdrant_required": $QDRANT_CONFIGURED,
    "context7_required": $CONTEXT7_CONFIGURED,
    "additional_required": $ADD_REQ
  }
}
TUEOF
    fi
  else
    # startup (or missing envelope, or file absent) — fresh init.
    #
    # BL-236: THE OMISSION BELOW IS LOAD-BEARING, and it used to be an accident.
    # This heredoc does NOT list `qdrant_find_succeeded` or
    # `context7_query_docs_succeeded`, and session-mcp-gate.sh's `_flag` reads a
    # MISSING key as false (`# BL-233-OUTCOME-QDRANT` / `# BL-233-OUTCOME-C7`).
    # That is the only thing that stops a COMMITTED .claude/tool-usage.json from
    # carrying an inherited `true` into a clone's first session and pre-satisfying
    # the MCP gate before any Write. Add either key here — at any value that can
    # be true — and you have re-opened it. T5b pins the erasure AND the gate's
    # refusal; T5c is the mutant that puts the keys back and shows the gate flip
    # to allow. Do not "complete" this object.
    LW_RESET_FAILED=0
    _lw_put << TUEOF || LW_RESET_FAILED=1   # BL-314-SESSION-PUT
{
  "session_id": "$SESSION_ID",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_store_called": false,
  "context7_called": false,
  "mcp_gate_satisfied": false,
  "mcp_requirements": {
    "qdrant_required": $QDRANT_CONFIGURED,
    "context7_required": $CONTEXT7_CONFIGURED,
    "additional_required": $ADD_REQ
  }
}
TUEOF
    # A startup whose fresh ledger cannot land (.claude unwritable, the disk
    # full) must not leave the last session's outcome flags in place: they would
    # let the first Write through with no MCP call this session (BL-236). So the
    # ledger is emptied in place, which needs no write to the directory, and the
    # gate fails closed on it; the hook says so and ends non-zero.
    if [ "$LW_RESET_FAILED" = "1" ]; then
      if { : > "$TOOL_USAGE"; } 2>/dev/null; then   # BL-314-RESET-FAIL-CLOSED
        echo "session-test-gate-check.sh: could not write a fresh $TOOL_USAGE (is .claude writable? is the disk full?), so it was emptied: no MCP result carries over from the last session, and the MCP check refuses Write and Edit until the ledger can be written." >&2
      else
        echo "session-test-gate-check.sh: could not write a fresh $TOOL_USAGE, nor empty it, so it may still hold the last session's MCP results. Fix the permissions on .claude and start a new session." >&2
      fi
      exit 1
    fi
  fi
elif [ "$SESSION_SOURCE" = "startup" ]; then
  # `## BL-335:` the removal takes the operator's additional_required with it,
  # and nothing here can write it back, so it is named before it goes.
  if [ "$LW_READY" = "1" ]; then ADD_WHY="jq is not installed, so the file was removed"; else ADD_WHY="the ledger writer cannot be loaded, so the file was removed"; fi
  _add_lost_note "$TOOL_USAGE" "$ADD_WHY"   # BL-335-NOJQ
  rm -f .claude/tool-usage.json   # BL-314-NOLIB-RESET
fi
# `## BL-335:` one line, and only when something was dropped or lost — a later
# start finds the list clean (or gone) and says nothing.
if [ -n "$ADD_NOTE" ]; then
  echo ""
  echo "$ADD_NOTE"   # BL-335-NOTE
fi
# Without the lib, this session's MCP calls cannot be recorded either, and the
# write above was skipped: say so, on every source, rather than pass in silence.
if [ "$LW_READY" != "1" ]; then
  echo ""
  echo "MCP LEDGER WRITER MISSING: $SCRIPT_DIR/lib/ledger-write.sh is missing or cannot be loaded, so no MCP call this session can be recorded in $TOOL_USAGE, and the MCP check will refuse every Write and Edit. Restore it: bash scripts/verify-install.sh --auto-fix"   # BL-314-NOLIB-NOTE
fi

# ── Report Unknown MCP Servers ────────────────────────────────────
if [ -n "$UNKNOWN_SERVERS" ]; then
  # Strip trailing comma+space
  UNKNOWN_SERVERS="${UNKNOWN_SERVERS%, }"
  cat << EOF

MCP SERVER NOTICE: The following MCP server(s) are configured but not recognized by the Solo Orchestrator framework: $UNKNOWN_SERVERS

Ask the Orchestrator: "I see you have [$UNKNOWN_SERVERS] configured as MCP server(s). Would you like me to use them during this session? If so, what should I use them for?"

If the Orchestrator wants a server used at session start (like Qdrant), they can add it to .claude/tool-usage.json under mcp_requirements.additional_required: a list of strings, each matched as a pattern against tool names (for example "mcp__sentry__"). Write and Edit are then blocked until a matching tool returns successfully in each session. The list carries over from one session to the next; the file is git-ignored, so it holds for this checkout only.
EOF
fi

# ── Report MCP Gate Requirements ──────────────────────────────────
# `## BL-322:` S4 (dogfood run 3, finding 11): say exactly what satisfies the
# MCP check. scripts/session-mcp-gate.sh counts OUTCOMES: a qdrant-find that
# returned (an empty result included) and a Context7 query-docs that returned.
# This line used to say "blocked until you call: qdrant-find, context7"; the
# technician called resolve-library-id, which reads no documentation, and the
# first edit was refused.
if [ "$QDRANT_CONFIGURED" = true ] || [ "$CONTEXT7_CONFIGURED" = true ]; then
  echo ""
  # "check", not "gate": the messaging standard keeps gate for the check
  # between one phase and the next (S4 review round 1).
  echo "MCP CHECK ACTIVE: Write/Edit operations are blocked until each call below has returned successfully in this session:"   # BL-322-S4-GATE-HEAD
  if [ "$QDRANT_CONFIGURED" = true ]; then   # BL-322-S4-GATE-QDRANT-IF
    echo "  - qdrant-find. An empty result counts; a call that errors does not."   # BL-322-S4-GATE-QDRANT
  fi
  if [ "$CONTEXT7_CONFIGURED" = true ]; then   # BL-322-S4-GATE-C7-IF
    echo "  - Context7's query-docs (mcp__context7__query-docs), which reads the documentation. resolve-library-id alone does not count: it only finds the library ID to pass to query-docs."   # BL-322-S4-GATE-C7
  fi
  echo "Call these tools now before beginning any file modifications."
fi

PHASE_STATE=".claude/phase-state.json"
BUILD_PROGRESS=".claude/build-progress.json"

# Only relevant in Phase 2 (Construction)
if [ ! -f "$PHASE_STATE" ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  exit 0
fi

CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null)
if [ "$CURRENT_PHASE" != "2" ]; then
  exit 0
fi

# Check build-progress.json exists
if [ ! -f "$BUILD_PROGRESS" ]; then
  echo "TEST GATE WARNING: In Phase 2 but .claude/build-progress.json is missing. Run: scripts/test-gate.sh --check-batch"
  exit 0
fi

# Read state
FEATURES_COMPLETED=$(jq -r '.features_completed | length' "$BUILD_PROGRESS" 2>/dev/null || echo "0")
case "$FEATURES_COMPLETED" in ''|*[!0-9]*) FEATURES_COMPLETED=0 ;; esac
# BL-203: `jq -r` on a MISSING key prints the literal string `null` at rc 0,
# so the `|| echo` fallbacks never fired and the -ge comparison below errored
# with `integer expression expected` — taking the else branch, i.e. failing
# OPEN. The `// default` inside jq plus the sanitizer line is the repo's
# canonical shape (lint-counter-antipattern enforces the sanitizer).
SINCE_LAST=$(jq -r '.features_since_last_test // 0' "$BUILD_PROGRESS" 2>/dev/null || echo "0")
case "$SINCE_LAST" in ''|*[!0-9]*) SINCE_LAST=0 ;; esac
INTERVAL=$(jq -r '.test_interval // 2' "$BUILD_PROGRESS" 2>/dev/null || echo "2")
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=2 ;; esac
TESTING_REQUIRED=$(jq -r '.testing_required // false' "$BUILD_PROGRESS" 2>/dev/null || echo "false")

# Check 1: Testing session is overdue
if [ "$TESTING_REQUIRED" = "true" ] || [ "$SINCE_LAST" -ge "$INTERVAL" ]; then
  cat << EOF
URGENT — TEST GATE BLOCKED. Report this to the Orchestrator IMMEDIATELY as your FIRST response.

Testing session required: $SINCE_LAST features completed since last test (interval is every $INTERVAL).
Do NOT start the next feature. Run a UAT testing session first.
Steps: scripts/test-gate.sh --check-batch
EOF
  exit 0
fi

# Check 2: Phase 2 with no features recorded — likely missed --record-feature calls
# Look for evidence of work: merged PRs, source code commits, test files
if [ "$FEATURES_COMPLETED" -eq 0 ]; then
  # Count commits on main since Phase 1→2 gate date
  PHASE2_DATE=$(jq -r '.gates.phase_1_to_2 // empty' "$PHASE_STATE" 2>/dev/null)
  COMMIT_COUNT=0
  if [ -n "$PHASE2_DATE" ]; then
    COMMIT_COUNT=$(git log --oneline --since="$PHASE2_DATE" --no-merges 2>/dev/null | wc -l | tr -d ' ')
  fi

  if [ "$COMMIT_COUNT" -gt 5 ]; then
    cat << EOF
TEST GATE WARNING: Report this to the Orchestrator as your FIRST response.

Phase 2 has $COMMIT_COUNT commits since Phase 1→2 gate ($PHASE2_DATE) but build-progress.json shows 0 features recorded.
This likely means scripts/test-gate.sh --record-feature was not called after completing features.

After each feature completion, you MUST run:
  scripts/test-gate.sh --record-feature "feature-name"

Ask the Orchestrator how many features have been completed so you can record them now.
EOF
  fi
fi

# Context Health Check reminder
PROGRESS_FILE=".claude/build-progress.json"
if [ -f "$PROGRESS_FILE" ] && command -v jq &>/dev/null; then
  health_count=$(jq '.features_since_last_health_check // 0' "$PROGRESS_FILE" 2>/dev/null)
  if [ "$health_count" -ge 3 ] 2>/dev/null; then
    echo ""
    echo -e "\033[33m[REMINDER]\033[0m Context Health Check recommended — $health_count features since last check."
    echo "  Verify PROJECT_BIBLE.md still accurately reflects the codebase."
    echo "  After checking: scripts/test-gate.sh --reset-health-check"
  fi
fi

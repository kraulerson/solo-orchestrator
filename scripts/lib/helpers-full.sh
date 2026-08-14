#!/usr/bin/env bash
# Solo Orchestrator — Full Shared Script Helpers (heavy surface)
#
# Loads helpers-core.sh (print_*, prompt_*, log_line, run_with_timeout,
# guard_not_in_framework) then adds the heavier helpers that only the
# long-running callers need:
#   - init_log / finalize_log (log-file rotation)
#   - is_context7_mcp_registered / is_qdrant_mcp_registered
#   - is_qdrant_container_running / register_qdrant_mcp
#
# Only long-running callers should source this file directly:
#   init.sh, upgrade-project.sh, intake-wizard.sh,
#   reconfigure-project.sh, verify-install.sh.
# Short-lived scripts (check-*.sh, validate.sh, test-gate.sh, ...)
# should source helpers-core.sh instead to skip the extra parse.
#
# Every existing caller that still does `source scripts/lib/helpers.sh`
# transitively lands here via the backwards-compat shim in helpers.sh.
#
# Idempotent-source guard.
if [ -n "${_SOIF_HELPERS_FULL_LOADED:-}" ]; then
  return 0
fi
_SOIF_HELPERS_FULL_LOADED=1

# Load the core helpers first (idempotent-guarded on its own).
# Fast-path dirname via parameter expansion (no subshell / no dirname fork).
_SOIF_HELPERS_FULL_DIR="${BASH_SOURCE[0]%/*}"
[ "$_SOIF_HELPERS_FULL_DIR" = "${BASH_SOURCE[0]}" ] && _SOIF_HELPERS_FULL_DIR="."
# shellcheck source=./helpers-core.sh
source "$_SOIF_HELPERS_FULL_DIR/helpers-core.sh"

# ── Logging ──────────────────────────────────────────────────────
# Call init_log() early in init.sh to enable file logging.
# All print_* functions in helpers-core.sh automatically log when
# LOG_FILE is set (they call log_line, which is a no-op until then).

init_log() {
  local log_dir="$1"
  mkdir -p "$log_dir"
  LOG_FILE="$log_dir/init-$(date +%Y%m%d-%H%M%S).log"
  {
    echo "═══════════════════════════════════════════════════════════"
    echo "Solo Orchestrator Init Log"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "OS: $(uname -s) $(uname -r) ($(uname -m))"
    echo "Shell: $BASH_VERSION"
    echo "User: $(whoami)@$(hostname)"
    echo "Working directory: $(pwd)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
  } > "$LOG_FILE"
}

finalize_log() {
  if [ -n "$LOG_FILE" ]; then
    {
      echo ""
      echo "═══════════════════════════════════════════════════════════"
      echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
      echo "Duration: ${SECONDS}s"
      echo "═══════════════════════════════════════════════════════════"
    } >> "$LOG_FILE"
    # Print log location (to both stdout and log)
    echo ""
    echo -e "${BLUE}[INFO]${NC} Init log saved to: $LOG_FILE"
  fi
}

# ── MCP Detection Helpers ────────────────────────────────────────
# Check both ~/.claude/settings.json and ~/.claude.json for MCP server registration.

is_context7_mcp_registered() {
  command -v jq &>/dev/null || return 1
  # Direct MCP registration in either user config file
  ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
  ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$HOME/.claude.json" >/dev/null 2>&1) || \
  # Plugin-installed Context7 (surfaces as mcp__plugin_context7_context7__*; registered under .enabledPlugins, not .mcpServers)
  ([ -f "$HOME/.claude/settings.json" ] && jq -e '.enabledPlugins | to_entries[] | select(.key | test("^context7"; "i")) | select(.value == true)' "$HOME/.claude/settings.json" >/dev/null 2>&1)
}

# ── Qdrant: registered is not the same question as working (BL-234) ─────────
# `is_qdrant_mcp_registered` used to BE the function below — a pure read of
# `~/.claude.json`. Its three callers in init.sh all treat a true answer as
# "the semantic memory is available", so a stale global entry left by an
# unrelated project made every later project conclude Qdrant was installed and
# SKIP PROVISIONING THE DATABASE ENTIRELY. That is why `powerpoint-voice` never
# had a Qdrant: not a missing feature, a predicate answering a different
# question from the one being asked.
#
# The config read survives under its honest name, because one caller genuinely
# wants it (writing a project-local collection override is correct whether or
# not the server happens to be up).
is_qdrant_mcp_entry_present() {
  command -v jq &>/dev/null || return 1
  ([ -f "$HOME/.claude/settings.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude/settings.json" >/dev/null 2>&1) || \
  ([ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' "$HOME/.claude.json" >/dev/null 2>&1)
}

# qdrant_mcp_url — the URL the REGISTRATION itself names, never a hard-coded
# one. Probing localhost while the entry points somewhere else would answer a
# question nobody asked. Falls back to the documented default only when the
# entry carries no QDRANT_URL.
qdrant_mcp_url() {
  local u=""
  if command -v jq &>/dev/null; then
    [ -f "$HOME/.claude.json" ] && u=$(jq -r '(.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // {}) | (.env.QDRANT_URL // empty)' "$HOME/.claude.json" 2>/dev/null)
    if [ -z "$u" ] && [ -f "$HOME/.claude/settings.json" ]; then
      u=$(jq -r '(.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // {}) | (.env.QDRANT_URL // empty)' "$HOME/.claude/settings.json" 2>/dev/null)
    fi
  fi
  [ -n "$u" ] && [ "$u" != "null" ] || u="http://localhost:6333"
  printf '%s' "$u"
}

# qdrant_mcp_api_key — the api-key the REGISTRATION itself carries, or empty.
#
# Qdrant's /readyz declares `api-key` as a REQUIRED header parameter, and the
# service's security scheme is `apiKey in header: api-key`
# (api.qdrant.tech/api-reference/service/readyz — verified 2026-08-14). A server
# started with an API key therefore answers an UNKEYED probe with 401, and the
# probe below used to score that healthy server as dead. Same file precedence as
# qdrant_mcp_url, so in the common case the URL and the key come from the same
# registration rather than from two different files.
qdrant_mcp_api_key() {
  local k=""
  if command -v jq &>/dev/null; then
    [ -f "$HOME/.claude.json" ] && k=$(jq -r '(.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // {}) | (.env.QDRANT_API_KEY // empty)' "$HOME/.claude.json" 2>/dev/null)
    if [ -z "$k" ] && [ -f "$HOME/.claude/settings.json" ]; then
      k=$(jq -r '(.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // {}) | (.env.QDRANT_API_KEY // empty)' "$HOME/.claude/settings.json" 2>/dev/null)
    fi
  fi
  [ "$k" = "null" ] && k=""
  printf '%s' "$k"
}

# _qdrant_curl <secs> <key> <url> — ONE bounded GET. Returns curl's own exit
# status, so the caller can tell "nothing answered" (7) from "the server
# answered with an error status" (22). Two spellings rather than an array
# because `"${arr[@]}"` on an EMPTY array is an unbound-variable error under
# `set -u` in bash 3.2, and this file is sourced by scripts that set it.
_qdrant_curl() {
  local secs="$1" key="$2" u="$3" rc=0
  if [ -n "$key" ]; then
    run_with_timeout "$secs" curl -fsS --max-time "$secs" -H "api-key: $key" -o /dev/null "$u" >/dev/null 2>&1 || rc=$?
  else
    run_with_timeout "$secs" curl -fsS --max-time "$secs" -o /dev/null "$u" >/dev/null 2>&1 || rc=$?
  fi
  return "$rc"
}

# _qdrant_answered <secs> <key> <url> — 0 iff the server ANSWERED AT ALL.
#
# ONE decision point for every endpoint tried, deliberately. When each probe
# carried its own `0|22` test, mutating one of them left the other still
# answering "reachable" and the mutant scored as killed by nothing.
_qdrant_answered() {
  local rc=0
  _qdrant_curl "$1" "$2" "$3" || rc=$?
  case "$rc" in 0|22) return 0 ;; esac   # BL-234-QDRANT-REACHABLE
  return 1
}

# qdrant_probe_reachable [url] — does the database ANSWER?
#   0 = reachable   1 = definitively unreachable   2 = cannot tell
#
# THREE returns, not two, and the third is reachable code: with neither curl nor
# nc there is no bounded way to open a socket from bash that can be trusted not
# to hang, and "I could not look" is a different fact from "it is not there".
# `# BL-112-SAST-NOTRUN`'s doctrine, one subsystem over. Each caller decides
# what to do with a 2 — the directions and their reasons are on `## BL-234:`.
#
# BOUNDED TWICE on purpose: curl's own --max-time is the precise bound, and
# run_with_timeout is the backstop for the states --max-time does not cover (a
# curl wedged before it starts its timer, a stub, a DNS resolver that blocks).
# There is no timeout(1) on the dev host, so run_with_timeout is the only outer
# bound available.
#
# /readyz is Qdrant's documented readiness probe ("checks the instance to see
# when it can start accepting traffic" — api.qdrant.tech/api-reference/service/readyz),
# which is the question being asked. The root endpoint is tried second so a
# build predating /readyz is not called dead; only after BOTH fail is the
# server unreachable.
#
# FOR A REACHABILITY QUESTION, AN HTTP ERROR STATUS IS AN ANSWER. `curl -f`
# exits 22 on any status >= 400, so a Qdrant secured with an api-key — which
# answers an unkeyed probe 401 — scored identically to a dead port. Measured
# against a local 401 responder: unkeyed rc=22, keyed rc=0, dead port rc=7, and
# the shipped predicate returned state=unreachable for the healthy secured
# server. One caller then told the operator their working memory was "a stale
# registration", while another provisioned a redundant container next to it.
# 22 is therefore REACHABLE; only "nothing answered" is unreachable. The key
# from the registration is sent as well, so a secured server also answers 200.
qdrant_probe_reachable() {
  local url="${1:-}" base secs host port hostport key
  [ -n "$url" ] || url="$(qdrant_mcp_url)"
  base="${url%/}"
  secs="${SOLO_QDRANT_PROBE_TIMEOUT:-3}"
  case "$secs" in ''|*[!0-9]*|0) secs=3 ;; esac
  key="$(qdrant_mcp_api_key)"   # BL-234-QDRANT-KEY-HEADER

  if command -v curl &>/dev/null; then
    _qdrant_answered "$secs" "$key" "$base/readyz" && return 0
    _qdrant_answered "$secs" "$key" "$base/" && return 0
    return 1
  fi

  if command -v nc &>/dev/null; then
    hostport="${base#*://}"; hostport="${hostport%%/*}"
    host="${hostport%%:*}"; port="${hostport##*:}"
    case "$port" in ''|*[!0-9]*) port=6333 ;; esac
    [ -n "$host" ] || return 2
    run_with_timeout "$secs" nc -z -w "$secs" "$host" "$port" >/dev/null 2>&1 && return 0
    return 1
  fi

  return 2
}

# is_qdrant_mcp_registered — registered AND reachable. The name is unchanged
# because it is what every caller already believed it meant.
#
# QDRANT_MCP_STATE carries the answer callers cannot get from an exit code:
#   reachable | unreachable | unknown | unregistered
# It is set on EVERY path, so a caller reading it after a false return is never
# reading a value from a previous call.
QDRANT_MCP_STATE=""
is_qdrant_mcp_registered() {
  local _qmr_rc=0
  QDRANT_MCP_STATE="unregistered"
  is_qdrant_mcp_entry_present || return 1
  qdrant_probe_reachable "$(qdrant_mcp_url)" || _qmr_rc=$?   # BL-234-QDRANT-PREDICATE
  case "$_qmr_rc" in
    0) QDRANT_MCP_STATE="reachable";   return 0 ;;
    1) QDRANT_MCP_STATE="unreachable"; return 1 ;;
    *) QDRANT_MCP_STATE="unknown";     return 1 ;;
  esac
}

# Check if a Qdrant container is running via docker ps (5s timeout, no docker info).
is_qdrant_container_running() {
  command -v docker &>/dev/null || return 1
  local _ps_out
  _ps_out=$(run_with_timeout 5 docker ps --format '{{.Names}}' 2>/dev/null) || return 1
  echo "$_ps_out" | grep -q "^qdrant$"
}

# Register Qdrant MCP with Claude Code (30s timeout).
# Usage: register_qdrant_mcp [collection_name]
register_qdrant_mcp() {
  local collection="${1:-claude-memory}"
  run_with_timeout 30 bash -c "echo y | claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$collection qdrant -- uvx --python 3.13 mcp-server-qdrant >/dev/null 2>&1"
}

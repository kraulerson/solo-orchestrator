#!/usr/bin/env bash
set -uo pipefail

# scripts/probe-tool.sh — ask a tool whether it WORKS, not whether it is
# mentioned in a config file.
#
# BL-235. The tool matrix decided "Qdrant MCP installed" by grepping
# `~/.claude.json` for an `mcpServers.qdrant` key and reported
# `version_command: echo 'configured'` — a value that cannot be wrong, and
# therefore carries no information. A machine with no database running was
# recorded `already_installed` and reported `[OK]` by every surface that
# consumes the resolver. Two sibling rows (Context7 MCP, Superpowers) had the
# same shape; the sweep that found them is in the BL-235 entry.
#
# ONE OWNER, because the alternative was three copies of probe logic inlined
# into a JSON data file — the sync-sibling trap `# BL-084-TIER-KEY` exists for,
# and the one this repo has re-learned repeatedly.
#
# ── THE EXIT CONTRACT ───────────────────────────────────────────────────────
#   0  WORKING        — evidence was obtained that the tool functions
#   1  NOT CONFIGURED — no configuration for it exists
#   2  CANNOT CONFIRM — configured, but working could not be established
#
# 2 IS NOT A SOFTENED 1, AND MUST NOT BE COLLAPSED INTO 0. It is the state
# `## BL-234:` established and `## BL-213:` forced on the cadence checker:
# "I could not measure this" is a third answer, and spelling it the same as
# either neighbour is how a declaration becomes a capability claim. Callers that
# gate on this MUST treat 2 as not-working.
#
# ── WHY THE THREE ROWS ARE NOT SYMMETRIC, STATED RATHER THAN AVERAGED ───────
# Only ONE of them is a network service:
#
#   qdrant       a running database — reachability is testable, and its `/`
#                payload reports a real version. Full three states apply.
#   context7     a STDIO MCP server launched on demand by npx. There is no
#                daemon to reach, so "reachable" is not a state it has. The
#                strongest local truth is: registered AND its launcher exists.
#   superpowers  a Claude plugin. Not a service at all; working means enabled
#                AND its files are present on disk.
#
# Inventing a uniform "reachable" verdict for all three would be the same
# substitution this entry is about, one level up. Each probe reports the
# strongest evidence its tool actually admits of, and says which kind it got.
#
# ── VERSIONS ────────────────────────────────────────────────────────────────
# `--version` prints a FALSIFIABLE string or NOTHING. It never prints a
# constant. `echo 'configured'` was true of a machine with nothing installed;
# an empty version is honest, and check-versions.sh already handles it.
#
# Every network read is BOUNDED. There is no timeout(1)/gtimeout(1) on the dev
# host, so this uses run_with_timeout from helpers-core.sh when available and
# curl's own --max-time as the floor.

PROBE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[ -f "$PROBE_DIR/lib/helpers-core.sh" ] && . "$PROBE_DIR/lib/helpers-core.sh" 2>/dev/null

PROBE_TIMEOUT="${PROBE_TOOL_TIMEOUT:-5}"

_probe_note() { [ "${PROBE_QUIET:-0}" = "1" ] || printf '%s\n' "$*" >&2; }

# _probe_http <url> — bounded GET, body on stdout. rc 0 only on a real response.
_probe_http() {                                                      # BL-235-PROBE-BOUNDED
  local url="$1"
  command -v curl >/dev/null 2>&1 || return 1
  if command -v run_with_timeout >/dev/null 2>&1; then
    run_with_timeout "$PROBE_TIMEOUT" curl -fsS --max-time "$PROBE_TIMEOUT" "$url"
  else
    curl -fsS --max-time "$PROBE_TIMEOUT" "$url"
  fi
}

# _mcp_entry <jq-filter> — the first match across the two config files Claude
# uses. Presence only; this decides CONFIGURED, never WORKING.
_mcp_entry() {
  local filter="$1" f
  command -v jq >/dev/null 2>&1 || return 1
  for f in "$HOME/.claude/settings.json" "$HOME/.claude.json"; do
    [ -f "$f" ] || continue
    jq -e "$filter" "$f" >/dev/null 2>&1 && { jq -r "$filter" "$f" 2>/dev/null; return 0; }
  done
  return 1
}

probe_qdrant() {
  local want_version="$1" url payload ver
  _mcp_entry '.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"] // empty' >/dev/null || {
    _probe_note "qdrant: no mcpServers entry in ~/.claude/settings.json or ~/.claude.json"
    return 1
  }
  url="$(_mcp_entry '(.mcpServers.qdrant // .mcpServers["mcp-server-qdrant"]).env.QDRANT_URL // empty' 2>/dev/null)"
  case "$url" in ''|null) url="http://localhost:6333" ;; esac
  payload="$(_probe_http "$url/" 2>/dev/null)" || {
    _probe_note "qdrant: configured at $url but the database did not answer — registered is not running"
    return 2
  }
  # A 200 from something that is not Qdrant is not evidence of Qdrant.
  ver="$(printf '%s' "$payload" | jq -r '.version // empty' 2>/dev/null)"
  if [ -z "$ver" ]; then
    _probe_note "qdrant: $url answered, but the payload carries no version field — cannot confirm it is Qdrant"
    return 2
  fi
  [ "$want_version" = "1" ] && printf '%s\n' "$ver"
  return 0
}

probe_context7() {
  local want_version="$1"
  _mcp_entry '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' >/dev/null \
    || _mcp_entry '.enabledPlugins | to_entries[] | select(.key | test("^context7"; "i")) | select(.value == true)' >/dev/null \
    || { _probe_note "context7: no mcpServers entry and no enabled plugin"; return 1; }
  # A stdio MCP server has no daemon to reach. The falsifiable local fact is
  # whether the launcher it is configured to run actually exists.
  if ! command -v npx >/dev/null 2>&1; then
    _probe_note "context7: registered, but npx is not on PATH — the configured launcher cannot start it"
    return 2
  fi
  if [ "$want_version" = "1" ]; then
    # Only a CACHED version is cheap and offline-safe; no version is better
    # than a constant that cannot be wrong.
    local v
    v="$(npm ls -g --depth=0 --json 2>/dev/null | jq -r '.dependencies["@upstash/context7-mcp"].version // empty' 2>/dev/null)"
    [ -n "$v" ] && printf '%s\n' "$v"
  fi
  return 0
}

probe_superpowers() {
  local want_version="$1" enabled reg path ver
  command -v jq >/dev/null 2>&1 || { _probe_note "superpowers: jq unavailable"; return 2; }
  [ -f "$HOME/.claude/settings.json" ] || { _probe_note "superpowers: no ~/.claude/settings.json"; return 1; }
  enabled="$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null)"
  [ "$enabled" = "true" ] || { _probe_note "superpowers: not enabled in settings.json"; return 1; }

  # ENABLED IS A DECLARATION; THE INSTALLED FILES ARE THE CAPABILITY. Derive the
  # location from the installer's own record rather than guessing paths — a
  # first draft of this probe guessed ~/.claude/plugins/superpowers and reported
  # "cannot confirm" against a perfectly healthy install, which is this entry's
  # defect wearing the other face: a probe that false-alarms because IT looked
  # in the wrong place. The real layout is
  # plugins/cache/<marketplace>/<plugin>/<version>, and installed_plugins.json
  # carries installPath and version outright.
  reg="$HOME/.claude/plugins/installed_plugins.json"                 # BL-235-PROBE-PLUGIN-REGISTRY
  [ -f "$reg" ] || { _probe_note "superpowers: enabled, but no plugin registry at $reg"; return 2; }
  path="$(jq -r '.plugins["superpowers@claude-plugins-official"][0].installPath // empty' "$reg" 2>/dev/null)"
  [ -n "$path" ] || path="$(jq -r '.["superpowers@claude-plugins-official"][0].installPath // empty' "$reg" 2>/dev/null)"
  if [ -z "$path" ] || [ ! -d "$path" ]; then
    _probe_note "superpowers: enabled in settings but its recorded installPath is ${path:-absent} — enabled is not installed"
    return 2
  fi
  if [ "$want_version" = "1" ]; then
    ver="$(jq -r '.plugins["superpowers@claude-plugins-official"][0].version // empty' "$reg" 2>/dev/null)"
    [ -n "$ver" ] || ver="$(jq -r '.["superpowers@claude-plugins-official"][0].version // empty' "$reg" 2>/dev/null)"
    [ -n "$ver" ] && printf '%s\n' "$ver"
  fi
  return 0
}

main() {
  local tool="${1:-}" want_version=0
  case "${2:-}" in --version) want_version=1 ;; esac
  case "$tool" in
    qdrant)      probe_qdrant "$want_version" ;;
    context7)    probe_context7 "$want_version" ;;
    superpowers) probe_superpowers "$want_version" ;;
    *)
      printf 'usage: probe-tool.sh <qdrant|context7|superpowers> [--version]\n' >&2
      return 64
      ;;
  esac
}

main "$@"

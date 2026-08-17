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
# THE FIRST VERSION OF THIS FILE HAD NO COVERAGE OF THAT CONTRACT. Its test
# asserted `rc -ne 0` where the truth is exactly 2 — which also passes on
# `rc=127`, the code you get when this script cannot be FOUND. That is how the
# matrix rows shipped CWD-relative: the assertion could not tell "the database
# is down" from "the probe was never run". Assert the state you mean.
#
# ── WHY THE THREE ROWS ARE NOT SYMMETRIC, STATED RATHER THAN AVERAGED ───────
# Only ONE of them is a network service:
#
#   qdrant       a running database — reachability is testable, and its `/`
#                payload identifies the server. Full three states apply.
#   context7     an MCP server reachable over EITHER transport its own entry
#                declares: a stdio launcher, or a documented HTTP endpoint with
#                no `command` field at all. The probe reads which one it is.
#   superpowers  a Claude plugin. Not a service at all; working means enabled
#                AND its recorded install actually exists on disk.
#
# Inventing a uniform "reachable" verdict for all three would be the same
# substitution this entry is about, one level up. Each probe reports the
# strongest evidence its tool actually admits of, and says which kind it got.
#
# ── VERSIONS: OF THE THING THE ROW NAMES ────────────────────────────────────
# `--version` prints a FALSIFIABLE string or NOTHING. It never prints a
# constant — and it never prints a number about a DIFFERENT ARTEFACT, which is
# the same substitution one field over. The first version of this file reported
# the DATABASE's version under a row named `Qdrant MCP` whose
# `update_check.runner` is `uvx`, i.e. the `mcp-server-qdrant` package. The
# number was real and it answered a question nobody asked. The package version
# is read from uv's own cache; when it cannot be established, nothing is
# printed, and check-versions.sh renders that state honestly.
#
# Every network read is BOUNDED, and every Qdrant read goes through
# scripts/lib/helpers-full.sh — see qdrant_probe_root there for why this file
# no longer owns a curl of its own.

PROBE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[ -f "$PROBE_DIR/lib/helpers-full.sh" ] && . "$PROBE_DIR/lib/helpers-full.sh" 2>/dev/null
# shellcheck disable=SC1090
[ -f "$PROBE_DIR/lib/helpers-core.sh" ] && . "$PROBE_DIR/lib/helpers-core.sh" 2>/dev/null

PROBE_TIMEOUT="${PROBE_TOOL_TIMEOUT:-5}"

_probe_note() { [ "${PROBE_QUIET:-0}" = "1" ] || printf '%s\n' "$*" >&2; }

# _probe_bounded <secs> <command...> — the bounded runner, whichever this tree
# has. run_with_deadline is preferred (wall-clock, 0.1s poll, rc 124); an older
# checkout may only carry run_with_timeout. With neither, curl's own --max-time
# is the floor, which is a real bound for curl and nothing else.
_probe_bounded() {                                                   # BL-235-PROBE-BOUNDED
  local secs="$1"; shift
  if command -v run_with_deadline >/dev/null 2>&1; then
    run_with_deadline "$secs" "$@"
  elif command -v run_with_timeout >/dev/null 2>&1; then
    run_with_timeout "$secs" "$@"
  else
    "$@"
  fi
}

# _probe_http <url> — bounded GET against a URL that carries NO credential.
# Used for transports whose configuration declares a plain endpoint. rc 0 iff
# the host answered at all; the status does not matter, because for "is there
# an MCP server on the other end of this URL" a 404 from a live host is still
# an answer and a refused connection is not.
_probe_http() {
  local url="$1"
  command -v curl >/dev/null 2>&1 || return 2
  _probe_bounded "$PROBE_TIMEOUT" curl -sS -o /dev/null --max-time "$PROBE_TIMEOUT" "$url" >/dev/null 2>&1
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

# _uv_cached_version <dist-name> — the highest version of a package uv has
# actually downloaded, or nothing.
#
# THIS IS A CACHE READ, AND IT IS DELIBERATELY ALLOWED TO FIND NOTHING. `uvx`
# resolves the package at launch, so there is no installed copy to interrogate
# and no `--version` to run that would not cost a network round trip at session
# start. What uv has on disk is the build it most recently ran, which is a
# falsifiable fact about the right artefact; when the layout changes or nothing
# is cached, the answer is silence rather than a number about something else.
# Measured at 14ms with `-maxdepth 2`.
_uv_cached_version() {
  local pkg="$1" cache=""
  command -v uv >/dev/null 2>&1 && cache="$(uv cache dir 2>/dev/null)"
  [ -n "$cache" ] || cache="${UV_CACHE_DIR:-$HOME/.cache/uv}"
  [ -d "$cache/archive-v0" ] || return 1
  find "$cache/archive-v0" -maxdepth 2 -name "${pkg}-*.dist-info" -print 2>/dev/null \
    | sed -e 's#.*/##' -e "s#^${pkg}-##" -e 's#\.dist-info$##' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1
}

# _plugin_entry <plugin-id> — the installed plugin registry entry that is
# ACTUALLY ON DISK, printed as "<path><TAB><version>".
#   rc 0  found: a recorded installPath that exists
#   rc 1  no registry, or no entry for this id
#   rc 2  entries exist but none of their recorded paths do
#
# SELECT BY PREDICATE, NOT BY POSITION. This read used to be
# `.plugins[<id>][0].installPath` — index zero, whatever happens to be there.
# With a stale entry first and the live one second, a perfectly healthy install
# scored CANNOT CONFIRM; with two live versions it printed whichever the
# installer had listed first. "The first one" is not a fact about the machine.
#
# THE PATH COMES FIRST IN THE RECORD, and that ordering is load-bearing. `read`
# treats a TAB in IFS as whitespace, so it collapses runs and discards a LEADING
# empty field: a `<version>\t<path>` record for an entry with no version would
# arrive as version="/the/path", path="" — a directory test against an empty
# string, silently false, for every unversioned entry. Path first cannot be
# empty (empty paths are skipped), so nothing collapses.
_plugin_entry() {
  local id="$1" reg rows path ver
  command -v jq >/dev/null 2>&1 || return 1
  reg="$HOME/.claude/plugins/installed_plugins.json"                 # BL-235-PROBE-PLUGIN-REGISTRY
  [ -f "$reg" ] || return 1
  # Both registry shapes: entries under `.plugins[<id>]`, and older files that
  # carry the id at the top level.
  rows="$(jq -r --arg id "$id" '
      ((.plugins[$id]? // .[$id]? // []) | if type == "array" then . else [.] end)[]
      | select(type == "object")
      | ((.installPath // "") + "\t" + (.version // ""))' "$reg" 2>/dev/null)"
  [ -n "$rows" ] || return 1
  while IFS=$'\t' read -r path ver; do                               # BL-235-PROBE-PLUGIN-SELECT
    [ -n "${path:-}" ] || continue
    if [ -d "$path" ]; then printf '%s\t%s\n' "$path" "${ver:-}"; return 0; fi
  done <<EOF
$rows
EOF
  return 2
}

probe_qdrant() {
  local want_version="$1" body title ver rc=0
  # THE HELPERS ARE CHECKED FIRST, BEFORE THE CONFIG. Ask about the entry with
  # helpers-full.sh missing and `is_qdrant_mcp_entry_present` is simply not a
  # command: rc=127, which the `||` below would have reported as NOT CONFIGURED
  # — the strongest of the three answers, produced by having no way to look.
  if ! command -v qdrant_probe_root >/dev/null 2>&1 \
     || ! command -v is_qdrant_mcp_entry_present >/dev/null 2>&1; then
    _probe_note "qdrant: scripts/lib/helpers-full.sh is unavailable, so neither the registration nor the database can be read — cannot confirm"
    return 2
  fi
  is_qdrant_mcp_entry_present || {
    _probe_note "qdrant: no mcpServers entry in ~/.claude/settings.json or ~/.claude.json"
    return 1
  }
  body="$(mktemp)" || { _probe_note "qdrant: no writable temp directory — cannot confirm"; return 2; }
  qdrant_probe_root "$body" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$body"
    _probe_note "qdrant: configured at $(qdrant_mcp_url) but nothing answered (HTTP ${QDRANT_ROOT_STATUS:-000}) — registered is not running"
    return 2
  fi
  case "${QDRANT_ROOT_STATUS:-}" in
    2??) : ;;
    *)
      # THE SERVER ANSWERED AND REFUSED, WHICH IS NOT THE SAME AS SILENCE.
      # A Qdrant secured with QDRANT__SERVICE__API_KEY answers an unkeyed probe
      # 403; the operator's repair is a key, not a container.
      rm -f "$body"
      _probe_note "qdrant: $(qdrant_mcp_url) answered HTTP ${QDRANT_ROOT_STATUS} — the database is up and refused this probe. Add QDRANT_API_KEY to the same mcpServers entry that carries QDRANT_URL."
      return 2
      ;;
  esac
  # A 200 FROM SOMETHING THAT IS NOT QDRANT IS NOT EVIDENCE OF QDRANT. This
  # check used to read `.version // empty` alone, and a stub literally named
  # `totally-not-qdrant` scored WORKING, as did an Elasticsearch-shaped payload
  # whose `.version` is an OBJECT. `title` and a STRING `version` are both
  # REQUIRED in Qdrant's own VersionInfo schema (api.qdrant.tech, GET /), so
  # this is the published contract and not a guess about response shapes.
  title="$(jq -r '(.title | strings) // empty' "$body" 2>/dev/null)"   # BL-235-PROBE-IDENTITY
  ver="$(jq -r '(.version | strings) // empty' "$body" 2>/dev/null)"
  rm -f "$body"
  if [ -z "$title" ] || [ -z "$ver" ]; then
    _probe_note "qdrant: $(qdrant_mcp_url) answered 200 but the payload is not a Qdrant VersionInfo (title and a string version are both required) — cannot confirm it is Qdrant"
    return 2
  fi
  if [ "$want_version" = "1" ]; then
    # NOT $ver. That is the DATABASE's version; this row is the MCP server.
    _uv_cached_version mcp_server_qdrant
  fi
  return 0
}

probe_context7() {
  local want_version="$1" entry url cmd pver rc=0
  entry="$(_mcp_entry '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty')" || entry=""
  if [ -n "$entry" ]; then
    # THE TRANSPORT THE ENTRY DECLARES, NOT THE ONE THIS PROBE ASSUMED.
    # context7 ships a documented HTTP transport whose entry carries a `url` and
    # NO `command` at all; hardcoding `command -v npx` judged such an install by
    # a launcher its own configuration never mentions.
    url="$(printf '%s' "$entry" | jq -r '.url | strings // empty' 2>/dev/null)"
    if [ -n "$url" ]; then
      if _probe_http "$url"; then
        return 0
      fi
      _probe_note "context7: registered over HTTP at $url, but nothing answered there"
      return 2
    fi
    cmd="$(printf '%s' "$entry" | jq -r '.command | strings // empty' 2>/dev/null)"
    [ -n "$cmd" ] || cmd="npx"
    if ! command -v "$cmd" >/dev/null 2>&1; then
      _probe_note "context7: registered, but its configured launcher '$cmd' is not on PATH"
      return 2
    fi
    if [ "$want_version" = "1" ]; then
      # Only a CACHED version is cheap and offline-safe; no version is better
      # than a constant that cannot be wrong.
      pver="$(npm ls -g --depth=0 --json 2>/dev/null | jq -r '.dependencies["@upstash/context7-mcp"].version // empty' 2>/dev/null)"
      [ -n "$pver" ] && printf '%s\n' "$pver"
    fi
    return 0
  fi

  # Plugin-installed context7 surfaces under .enabledPlugins, not .mcpServers,
  # and is answered by the same registry question superpowers asks.
  local pid
  pid="$(_mcp_entry '.enabledPlugins | to_entries[] | select(.key | test("^context7"; "i")) | select(.value == true) | .key')" || pid=""
  if [ -z "$pid" ]; then
    _probe_note "context7: no mcpServers entry and no enabled plugin"
    return 1
  fi
  local row
  row="$(_plugin_entry "$pid")" || rc=$?
  case "$rc" in
    0) [ "$want_version" = "1" ] && printf '%s\n' "${row#*$'\t'}"; return 0 ;;
    2) _probe_note "context7: plugin '$pid' is enabled but no recorded installPath exists on disk — enabled is not installed"; return 2 ;;
    *) _probe_note "context7: plugin '$pid' is enabled but the plugin registry has no entry for it"; return 2 ;;
  esac
}

probe_superpowers() {
  local want_version="$1" id="superpowers@claude-plugins-official" enabled row rc=0
  command -v jq >/dev/null 2>&1 || { _probe_note "superpowers: jq unavailable"; return 2; }
  [ -f "$HOME/.claude/settings.json" ] || { _probe_note "superpowers: no ~/.claude/settings.json"; return 1; }
  enabled="$(jq -r --arg id "$id" '.enabledPlugins[$id] // false' "$HOME/.claude/settings.json" 2>/dev/null)"
  [ "$enabled" = "true" ] || { _probe_note "superpowers: not enabled in settings.json"; return 1; }

  # ENABLED IS A DECLARATION; THE INSTALLED FILES ARE THE CAPABILITY. Derive the
  # location from the installer's own record rather than guessing paths — a
  # first draft of this probe guessed ~/.claude/plugins/superpowers and reported
  # "cannot confirm" against a perfectly healthy install, which is this entry's
  # defect wearing the other face: a probe that false-alarms because IT looked
  # in the wrong place. The real layout is
  # plugins/cache/<marketplace>/<plugin>/<version>, and installed_plugins.json
  # carries installPath and version outright.
  row="$(_plugin_entry "$id")" || rc=$?
  case "$rc" in
    0) [ "$want_version" = "1" ] && printf '%s\n' "${row#*$'\t'}"; return 0 ;;
    2) _probe_note "superpowers: enabled in settings, but no recorded installPath exists on disk — enabled is not installed"; return 2 ;;
    *) _probe_note "superpowers: enabled, but the plugin registry has no entry for $id"; return 2 ;;
  esac
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

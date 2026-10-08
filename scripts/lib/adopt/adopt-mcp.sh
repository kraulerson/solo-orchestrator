#!/usr/bin/env bash
# scripts/lib/adopt/adopt-mcp.sh — `## BL-311:` fix 1: the two MCP servers a
# Claude Code session in an adopted project is checked for, Qdrant (memory
# across sessions) and Context7 (current library documentation).
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THE SESSION CHECKS, READ FROM THE SCRIPTS RATHER THAN ASSUMED
#
# scripts/session-mcp-gate.sh blocks every Write/Edit until qdrant-find and
# Context7's query-docs have SUCCEEDED this session — but only for a server the
# SessionStart hook (scripts/session-test-gate-check.sh) finds REGISTERED. It
# writes `qdrant_required` / `context7_required` from what is registered, and a
# server registered nowhere is not required. So there are three outcomes, and
# this step says which one the operator is in rather than one blanket warning:
#
#   registered and working        the session can satisfy the check
#   registered, nothing answers   EVERY file edit is blocked until it answers
#   not registered anywhere       not required: the session works without it
#
# THE DOGFOOD RUN OF 2026-09-27 met all of it at once. Adoption never looked for
# either server (init.sh provisions Qdrant and hints Context7); the helpers it
# used read `~/.claude.json` while the session's registrations lived under
# CLAUDE_CONFIG_DIR (helpers-core.sh, `soif_claude_config_dir`), so it saw a
# registration the session did not have; and the operator was never told that a
# session already open when adoption ran cannot save a file afterwards.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS STEP DOES, AND WHERE (§8.2, after tool resolution and the secrets
# stop, before the CI audit — `# BL-311-MCP-CALL` says why it is not earlier)
#
# Before any write: read both registrations from the files THIS session reads,
# probe Qdrant, and — ONLY WHEN THIS MACHINE CAN DO IT — offer to set up what is
# missing. THE OFFER IS MADE THERE AND CARRIED OUT LATER (`## BL-322:` S3):
# adopt_mcp_resolve asks; adopt_mcp_apply runs the commands once every check
# that can stop the adoption without writing has passed
# (`# BL-322-S3-MCP-APPLY-CALL`), so a stopped adoption leaves the operator's
# Claude Code configuration as it found it. "Can do it" is concrete: the
# `claude` command, plus Docker running for the database, plus `uvx` / `npx`
# for the server a registration launches.
# Registering a server that cannot launch would be worse than not registering
# it: registered makes it REQUIRED, and a required tool that never starts
# blocks every file edit. Where it cannot act it says what to install instead.
#
# THE QUESTION IS NOT MANDATORY, AND THAT IS A DESIGN CONSTRAINT, NOT A NICETY.
# No answer — a blank line, or the end of the input — is "skip it". The other
# questions adoption asks refuse on no answer (`adopt_ask_choice`); this one
# may not, because the adoption does not depend on it, and because CI and
# every adoption suite pipe their answers: on a runner (no `claude` command) it
# is never asked, and where it IS asked a run that supplies no answer for it
# still completes.
#
# ─────────────────────────────────────────────────────────────────────────────
# CONSENT DISCIPLINE — adopt_resolve_tools' rules, applied unchanged:
#   • the exact commands are printed BEFORE the question, never after the answer;
#   • each runs with its cwd in $ADOPT_WORK and stdin from /dev/null, so it can
#     neither write into the operator's repository by a relative path nor eat
#     the operator's remaining answers (fd 0 is the same open file description
#     `adopt_stdin_init` reads them from). SO DOES EVERY PROBE, and that is
#     measured, not tidiness: the first cut's `run_with_deadline 5 docker info`
#     had no redirection, and inside this driver its child READ THE OPERATOR'S
#     PIPE — the suite's stub docker drained every remaining answer and the
#     adoption refused at the next question for want of one (E2; M20 pins it).
#     `run_with_deadline` backgrounds its child. MEASURED INSIDE THE DRIVER
#     (round 2): run bare, that child inherits the operator's pipe; run inside
#     a `( … )` subshell it gets /dev/null — dropping only the `</dev/null`
#     from the subshell-wrapped `claude mcp get` changed nothing in a whole
#     adoption, while dropping the subshell too made the stub drain every
#     remaining answer (M39 pins that pair). A standalone reproduction gives
#     even the bare call /dev/null, so WHY is still not isolated, and no call
#     here relies on either: each has both. The real `docker info` does not
#     read stdin; that is luck, not design;
#   • the adoptee's path list is fingerprinted across the run, and a
#     difference — or a fingerprint that could not be read — raises BOTH
#     touched-disk markers. ONE DELIBERATE DIFFERENCE from the resolver, which
#     raises the coarse marker BEFORE its eval because a matrix recipe is
#     arbitrary: these commands are fixed strings, run from $ADOPT_WORK, whose
#     targets are the operator's Claude Code configuration and Docker, never
#     this project. Raising the marker on the attempt would make any later
#     refusal say adoption "had already ATTEMPTED writes to this project" over
#     a tree the fingerprint proves unchanged — `# BL-225-REFUSE-HONEST`'s
#     over-claim. So the marker follows the evidence (S10 pins both arms);
#   • a RECEIPT: registration and reachability are re-read afterwards, and only
#     what the receipt shows is claimed. A zero exit is not evidence.
#
# THE COMMANDS ARE THE CLI SETUP ADDENDUM'S, AND THE QDRANT ONE WAS WRONG
# THERE TOO, MEASURED on Claude Code 2.1.283 against a scratch
# CLAUDE_CONFIG_DIR: `-e` is VARIADIC, so the Addendum's spelling — the name
# `qdrant` written AFTER `-e QDRANT_URL=… -e COLLECTION_NAME=claude-memory` —
# took the name as a third environment value and exited 1 with "Invalid
# environment variable format: qdrant". The server name goes BEFORE the `-e`
# options; that spelling exits 0 and writes the entry. Every tracked copy is
# now in that order, and tests/test-bl311-mcp-add-order.sh keeps it so.
#
# bash-3.2 safe; every local is assigned where it is declared.

ADOPT_MCP_RESULT=""        # the Adoption Record's cell
# `## BL-318:` G6(b) — the servers THIS RUN registered with Claude Code, by name
# ("context7", "qdrant", or both, space-separated). A registration lives in the
# operator's user configuration, outside the project, so a later refusal that
# says "nothing was written" would be false about it (dogfood run 2, finding 12:
# `claude mcp add` ran mid-interview, then "Nothing was committed and nothing
# was written"). adopt_refuse reads this (`# BL-318-G6-OUTSIDE`). A name is
# recorded only when the run ATTEMPTED its `claude mcp add` AND the receipt shows
# it registered: an attempt the receipt does not show is not claimed, and a
# server registered before the run was never attempted, so it is not this run's.
ADOPT_MCP_REGISTERED=""
ADOPT_MCP_PLAN=()          # "<server>|<command>" rows this run would execute
# `## BL-322:` S3 — 1 from the operator's "set it up now" until adopt_mcp_apply
# runs the plan, after every check that can stop the adoption without writing.
ADOPT_MCP_PENDING=0

ADOPT_MCP_QDRANT_ADD='claude mcp add -s user qdrant -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory -- uvx --python 3.13 mcp-server-qdrant'   # BL-311-MCP-QDRANT-ADD
ADOPT_MCP_CONTEXT7_ADD='claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp'
ADOPT_MCP_QDRANT_START='docker start qdrant'
# `## BL-311:` THE PORTS ARE PUBLISHED ON LOOPBACK ONLY. A `-p` with no host
# address publishes the database on EVERY interface, with no API key and
# `--restart unless-stopped` — an unauthenticated store of the operator's
# session memory reachable from their network for as long as Docker runs. The
# MCP server and every probe here use http://localhost:6333, so nothing needs
# more than 127.0.0.1 (measured: a 127.0.0.1-only listener answers both curl and
# Python at `localhost` on this host). `docker start` of a container that
# already exists keeps the binding it was created with.
ADOPT_MCP_QDRANT_RUN='docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest'   # BL-311-MCP-LOOPBACK

# THE TWO ANSWERS, SPELLED ONCE AND OFFERED IN THIS ORDER ON PURPOSE. "skip it"
# is FIRST, so answer `1` means skip: the dogfood run fed `1\n1\n1\n…` to every
# question, and with "set it up now" first a `1` meant for another question
# would register user-scope servers for every project and shift every later
# answer by one. The offer and the resolver read the same two variables in the
# same order; cases S12/S13 answer by NUMBER so a swap in either is caught.
ADOPT_MCP_SKIP="skip it"
ADOPT_MCP_SETUP="set it up now"

# _adopt_mcp_state — "<context7> <qdrant-state> <qdrant-url>" for THIS
# session's configuration. helpers-full.sh is read in a SUBSHELL, as the session
# stage does, so its definitions never leak into the driver.
_adopt_mcp_state() {
  ( . "$ADOPT_CORE_LIB_DIR/helpers-full.sh" >/dev/null 2>&1 || exit 3
    _c7="unregistered"
    is_context7_mcp_registered && _c7="registered"
    is_qdrant_mcp_registered || :
    printf '%s %s %s\n' "$_c7" "${QDRANT_MCP_STATE:-unknown}" "$(qdrant_mcp_url)" ) </dev/null   # BL-311-MCP-PROBE-STDIN
}

# _adopt_mcp_local_qdrant — does a database answer at the default address the
# registration below names? rc 0 yes, 1 no, 2 cannot tell (no curl, no nc).
_adopt_mcp_local_qdrant() {
  ( . "$ADOPT_CORE_LIB_DIR/helpers-full.sh" >/dev/null 2>&1 || exit 2
    qdrant_probe_reachable "http://localhost:6333" ) </dev/null
}

_adopt_mcp_docker_up() {
  command -v docker >/dev/null 2>&1 || return 1
  run_with_deadline 5 docker info </dev/null >/dev/null 2>&1   # BL-311-MCP-DOCKER-STDIN
}

# _adopt_mcp_qdrant_container — is there a container named `qdrant` to START,
# rather than one to create? Either answer is safe to act on: `docker start`
# on a running one is a no-op, and a failed lookup falls through to `run`,
# whose own failure is caught by the receipt.
_adopt_mcp_qdrant_container() {
  local names=""
  names="$(run_with_deadline 10 docker ps -a --format '{{.Names}}' </dev/null 2>/dev/null)" || names=""
  printf '%s\n' "$names" | grep -qx 'qdrant'
}

# _adopt_mcp_inspect — HOW the EXISTING `qdrant` container is published, and
# WHETHER it has an API key. One bounded `docker inspect` (bindings, env,
# publish-all, network mode — one JSON document per line), stdin closed. Sets:
#   ADOPT_MCP_QDRANT_BIND   open-host (--network host: every interface of the
#                           host) | open-all (a HostIp of 0.0.0.0) | open-v6
#                           (::, every IPv6 address) | open-default (an EMPTY
#                           HostIp) | open-addr (any other HostIp that is not
#                           127.0.0.1 or ::1 — named in ADOPT_MCP_QDRANT_ADDRS)
#                           | open-publish-all (-P) | loopback | unread
#                           (inspect failed, or its bindings, publish-all or
#                           network mode did not parse)
#   ADOPT_MCP_QDRANT_KEY    set | unset | unread (QDRANT__SERVICE__API_KEY, in
#                           ANY letter case — Qdrant honours a lowercase one —
#                           in its ENVIRONMENT; a key in a config file is not seen)
#
# EVERY FIELD STARTS AT `unread` AND ONLY A PARSED ANSWER MOVES IT: a failed or
# garbled inspect must never read as "loopback" (`# BL-311-MCP-BIND-PARSE`
# checks all of it parses, as the type Docker gives it, before any arm reads it).
# `loopback` is only what is left when nothing above it matched: no host
# network, no -P, and every HostIp 127.0.0.1 or ::1 (or nothing published).
#
# WHY. `docker start` keeps the bindings a container was created with, so the
# loopback-only `docker run` protects nothing for a container that already
# exists — this host's own reads `{"6333/tcp":[{"HostIp":"","HostPort":"6333"}],…}`.
# Per Docker's documentation an EMPTY HostIp means the daemon's default bind
# address — every interface unless the daemon sets `ip` / `host_binding_ipv4` —
# so it is reported as that, not as a verified exposure; `::` is every IPv6
# address.
#
# NOTHING IS READ TO BUILD A RECREATE, BECAUSE NONE IS PRINTED (round 13). Rounds
# 4-12 printed paste-ready commands to recreate an exposed container on
# loopback, and read its mounts, tmpfs, --rm, image, volume options, --mount
# settings and its own /proc/mounts to decide when they were safe. Every round's
# review on real Docker found another setting the printed recreate lost or broke
# — where the data lives, --rm, tmpfs in many spellings, tmpfs-backed volumes,
# subpaths, API keys, image tags, RUN_MODE moving the storage path, lowercase
# env keys, CLI flags, snapshot files inside the container. So the note now
# says what it found and points to the written, snapshot-based procedure in
# docs/adoption.md ("Recreating an exposed Qdrant container", pinned by S28),
# and adoption recreates nothing.
ADOPT_MCP_QDRANT_BIND="none"; ADOPT_MCP_QDRANT_BIND_WHY=""; ADOPT_MCP_QDRANT_KEY="unread"; ADOPT_MCP_QDRANT_ADDRS=""
_adopt_mcp_inspect() {
  local out="$ADOPT_WORK/mcp-inspect.out" b="" e="" pa="" nm=""
  ADOPT_MCP_QDRANT_BIND="unread"; ADOPT_MCP_QDRANT_BIND_WHY="docker inspect could not read it"   # BL-311-MCP-INSPECT-FAILCLOSED
  ADOPT_MCP_QDRANT_KEY="unread"; ADOPT_MCP_QDRANT_ADDRS=""
  ( run_with_deadline 10 docker inspect -f '{{json .HostConfig.PortBindings}}{{"\n"}}{{json .Config.Env}}{{"\n"}}{{json .HostConfig.PublishAllPorts}}{{"\n"}}{{json .HostConfig.NetworkMode}}' qdrant ) </dev/null >"$out" 2>/dev/null || return 0
  b="$(sed -n 1p "$out")"; e="$(sed -n 2p "$out")"; pa="$(sed -n 3p "$out")"; nm="$(sed -n 4p "$out")"
  if ! printf '%s\n%s\n%s\n' "$b" "$pa" "$nm" | jq -e -s 'length == 3 and (.[0] | type == "object" or type == "null") and (.[1] | type == "boolean") and (.[2] | type == "string")' >/dev/null 2>&1; then   # BL-311-MCP-BIND-PARSE
    ADOPT_MCP_QDRANT_BIND_WHY="docker inspect's answer about its ports could not be parsed"
  elif printf '%s' "$nm" | jq -e '. == "host"' >/dev/null 2>&1; then   # BL-311-MCP-OPEN-DETECT-HOST
    ADOPT_MCP_QDRANT_BIND="open-host"
  elif printf '%s' "$b" | jq -e '[.[]?[]? | (.HostIp // "")] | any(. == "0.0.0.0")' >/dev/null 2>&1; then   # BL-311-MCP-OPEN-DETECT
    ADOPT_MCP_QDRANT_BIND="open-all"
  elif printf '%s' "$b" | jq -e '[.[]?[]? | (.HostIp // "")] | any(. == "::")' >/dev/null 2>&1; then   # BL-311-MCP-OPEN-DETECT-V6
    ADOPT_MCP_QDRANT_BIND="open-v6"
  elif printf '%s' "$b" | jq -e '[.[]?[]? | (.HostIp // "")] | any(. == "")' >/dev/null 2>&1; then   # BL-311-MCP-OPEN-DETECT-DEFAULT
    ADOPT_MCP_QDRANT_BIND="open-default"
  elif printf '%s' "$b" | jq -e '[.[]?[]? | (.HostIp // "")] | any(. != "127.0.0.1" and . != "::1")' >/dev/null 2>&1; then   # BL-311-MCP-OPEN-DETECT-ADDR
    ADOPT_MCP_QDRANT_BIND="open-addr"
    ADOPT_MCP_QDRANT_ADDRS="$(printf '%s' "$b" | jq -r '[.[]?[]? | (.HostIp // "") | select(. != "127.0.0.1" and . != "::1")] | unique | join(", ")' 2>/dev/null | tr -cd '0-9A-Za-z.:%, ')"
  elif printf '%s' "$pa" | jq -e '. == true' >/dev/null 2>&1; then   # BL-311-MCP-OPEN-DETECT-PUBLISH-ALL
    ADOPT_MCP_QDRANT_BIND="open-publish-all"
  else
    ADOPT_MCP_QDRANT_BIND="loopback"; ADOPT_MCP_QDRANT_BIND_WHY=""
  fi
  # AN API KEY IS READ, NOT ASSUMED ABSENT. The value is never printed. Only the
  # ENVIRONMENT is read — a key set in a Qdrant config file is not visible here,
  # which is why "unset" is worded as "not set in its environment". The name is
  # matched in ANY letter case: Qdrant honours `qdrant__service__api_key` (401
  # without it, 200 with it — measured by the round-14 review). An EMPTY value is not read
  # as a key — the note then warns rather than reassures. The
  # "could not be read" outcome needs an inspect whose second line is not JSON
  # while the first parsed; that is practically unreachable, and it is not
  # given a case of its own.
  if printf '%s' "$e" | jq -e 'type == "array"' >/dev/null 2>&1; then
    if printf '%s' "$e" | jq -e 'any(.[]; (type == "string") and test("^QDRANT__SERVICE__API_KEY=."; "i"))' >/dev/null 2>&1; then   # BL-311-MCP-KEY-DETECT
      ADOPT_MCP_QDRANT_KEY="set"
    else
      ADOPT_MCP_QDRANT_KEY="unset"
    fi
  fi
  return 0
}

# _adopt_mcp_open_note — the finding, and a pointer. NO command, for ANY
# container: no recreate, no way back, no docker verb a reader could paste
# (S29 checks that over a set of container shapes). The one runnable string
# near it is the read-only `docker inspect` in the could-not-be-read hint
# (`# BL-311-MCP-UNREAD-HINT`), which is never printed with this note.
_adopt_mcp_open_note() {                                 # BL-311-MCP-OPEN-NOTE
  local key=""
  case "$ADOPT_MCP_QDRANT_KEY" in
    set)   key="it has an API key set (QDRANT__SERVICE__API_KEY), so reaching it is not the same as reading it" ;;
    unset) key="no API key is set in its environment (a key in a Qdrant config file would not show here)" ;;   # BL-311-MCP-KEY-WORDING
    *)     key="whether it has an API key could not be read" ;;
  esac
  case "$ADOPT_MCP_QDRANT_BIND" in
    open-host)
      adopt_note "Your existing qdrant container runs on the host's network (--network host), so its"
      adopt_note "ports are open on every network interface of this machine, whatever it publishes:"
      adopt_note "while it runs, other machines on your network may be able to reach it — and $key." ;;
    open-all)
      adopt_note "Your existing qdrant container publishes its ports on every network interface"
      adopt_note "(its bindings name 0.0.0.0): while it runs, other machines on your network may be"
      adopt_note "able to reach it — and $key." ;;
    open-v6)
      adopt_note "Your existing qdrant container publishes its ports on every IPv6 address of this"
      adopt_note "machine (its bindings name ::): while it runs, other machines that reach it over"
      adopt_note "IPv6 may be able to reach it — and $key." ;;
    open-addr)
      adopt_note "Your existing qdrant container publishes its ports on an address other than"
      adopt_note "loopback (127.0.0.1 or ::1) — its bindings name ${ADOPT_MCP_QDRANT_ADDRS:-one it could not print}: while it runs,"
      adopt_note "other machines that can reach that address may be able to reach it — and $key." ;;
    open-publish-all)
      adopt_note "Your existing qdrant container was created with -P (--publish-all), which publishes"
      adopt_note "its ports on random ports of every network interface unless your Docker daemon"
      adopt_note "sets a default bind address: while it runs, other machines on your network may be"
      adopt_note "able to reach it — and $key." ;;
    *)
      adopt_note "Your existing qdrant container's ports name no host address, which Docker"
      adopt_note "publishes on every network interface unless your Docker daemon sets a default"   # BL-311-MCP-DEFAULT-BIND-WORDING
      adopt_note "bind address: while it runs, other machines on your network may be able to reach"
      adopt_note "it — and $key." ;;
  esac
  adopt_note "Starting it keeps that. To publish it on 127.0.0.1 (loopback) instead, it has to"
  adopt_note "be recreated, and removing a container can delete its data."
  adopt_note "(On Docker Engine older than 28.0.0 on Linux, hosts on the same network segment"
  adopt_note "can reach even ports published on 127.0.0.1 — moby/moby#45610.)"   # BL-311-MCP-MOBY-CAVEAT
  adopt_note "Adoption changed nothing about this container, and prints no commands to recreate"   # BL-311-MCP-CHANGED-NOTHING
  adopt_note "it. How to do that without losing its data:"
  if [ -n "${ADOPT_FRAMEWORK_ROOT:-}" ]; then
    adopt_note "\"Recreating an exposed Qdrant container\" in $ADOPT_FRAMEWORK_ROOT/docs/adoption.md."   # BL-311-MCP-POINTER
  else
    adopt_note "\"Recreating an exposed Qdrant container\" in the framework's docs/adoption.md."
  fi
}

# _adopt_mcp_wait_qdrant — the database takes a moment to accept connections
# after `docker run`, so reachability is polled, bounded, before anything is
# REGISTERED against it. Registering a server whose database never came up
# would make it required and block every file edit.
_adopt_mcp_wait_qdrant() {
  local n="${SOIF_ADOPT_QDRANT_WAIT:-20}" i=0
  case "$n" in ''|*[!0-9]*) n=20 ;; esac
  while :; do
    _adopt_mcp_local_qdrant && return 0
    i=$((i + 1))
    [ "$i" -ge "$n" ] && return 1
    sleep 1
  done
}

# _adopt_mcp_run CMD — run ONE command exactly as it was shown. Bounded:
# `docker run` may pull the image, so it gets the long bound.
_adopt_mcp_run() {
  local cmd="$1" secs=60 rc=0
  case "$cmd" in "docker run "*) secs=600 ;; esac
  ( cd "$ADOPT_WORK" 2>/dev/null && run_with_deadline "$secs" bash -c "$cmd" ) </dev/null >>"$ADOPT_WORK/mcp-setup.out" 2>&1 || rc=$?   # BL-311-MCP-RUN
  return "$rc"
}

# _adopt_mcp_last_output — the last line a failed command printed, so the
# operator sees WHY rather than that. Control bytes stripped; it is shown once.
_adopt_mcp_last_output() {
  tail -n 1 "$ADOPT_WORK/mcp-setup.out" 2>/dev/null | LC_ALL=C tr -d '\000-\037\177' | cut -c1-200
}

# _adopt_mcp_launch NAME — CLAUDE CODE'S OWN CHECK that it can start the server.
#
# Registered is a line in a config file and "the database answers" is a fact
# about Docker; neither says Claude Code can LAUNCH the server — `uvx` may be
# unable to fetch Python 3.13, `npx` may be broken. The only evidence of that is
# Claude Code's own health check, so that is the receipt. `claude mcp get NAME`
# runs it for ONE server (`claude mcp list` runs it for every server the
# operator has, and took 7s against 0s for `get` on a scratch config, measured
# on 2.1.283); its output carries `Status: ✔ Connected` or
# `Status: ✘ Failed to connect` with an `Issue:` line, and the exact command to
# back the registration out (`To remove this server, run: …`). Bounded, output
# to a FILE (a command substitution would wait out a hung child), stdin
# detached, run from $ADOPT_WORK.
#   ADOPT_MCP_LAUNCH         connected | failed | unchecked
#   ADOPT_MCP_LAUNCH_WHY     the Issue line, or why it could not be checked
#   ADOPT_MCP_LAUNCH_REMOVE  Claude Code's own remove command, else a plain one
ADOPT_MCP_LAUNCH=""; ADOPT_MCP_LAUNCH_WHY=""; ADOPT_MCP_LAUNCH_REMOVE=""
_adopt_mcp_launch() {
  local name="$1" out="" rc=0 secs="${SOIF_ADOPT_MCP_LAUNCH_SECS:-60}" line=""
  case "$secs" in ''|*[!0-9]*|0) secs=60 ;; esac
  ADOPT_MCP_LAUNCH="unchecked"; ADOPT_MCP_LAUNCH_WHY=""; ADOPT_MCP_LAUNCH_REMOVE="claude mcp remove $name"
  if ! command -v claude >/dev/null 2>&1; then
    ADOPT_MCP_LAUNCH_WHY="the claude command is not on PATH"; return 0
  fi
  out="$ADOPT_WORK/mcp-get-$name.out"
  # RESIDUAL, recorded by the round-3 review: inside this driver a BARE call
  # inherits the operator's answer pipe — state an earlier adoption step leaves
  # behind (fd 0 reads as a PIPE at the first line of adopt_mcp_resolve) — so
  # any future bare run_with_deadline / run_with_timeout in the driver hands
  # its child the operator's stdin. The `( … )` subshell here happens to give
  # the child /dev/null; the `</dev/null` is what this line relies on, and
  # every new call must carry both.
  ( cd "$ADOPT_WORK" 2>/dev/null && run_with_deadline "$secs" claude mcp get "$name" ) </dev/null >"$out" 2>&1 || rc=$?   # BL-311-MCP-LAUNCH-STDIN
  line="$(grep -m1 'To remove this server, run:' "$out" 2>/dev/null | LC_ALL=C tr -d '\000-\037\177')"
  case "$line" in *"run: claude mcp remove "*) ADOPT_MCP_LAUNCH_REMOVE="${line#*run: }" ;; esac
  if grep -q 'Status:.*Failed to connect' "$out" 2>/dev/null; then       # BL-311-MCP-LAUNCH-FAILED
    ADOPT_MCP_LAUNCH="failed"
    ADOPT_MCP_LAUNCH_WHY="$(grep -m1 'Issue:' "$out" 2>/dev/null | sed 's/^[[:space:]]*Issue:[[:space:]]*//' | LC_ALL=C tr -d '\000-\037\177' | cut -c1-160)"
  elif grep -q 'Status:.*Connected' "$out" 2>/dev/null; then
    ADOPT_MCP_LAUNCH="connected"
  elif [ "$rc" -eq 124 ]; then
    ADOPT_MCP_LAUNCH_WHY="claude mcp get $name did not answer within ${secs}s"
  else
    ADOPT_MCP_LAUNCH_WHY="claude mcp get $name gave no status Claude Code's check could be read from"
  fi
  return 0
}

# _adopt_mcp_launch_note LABEL — one line saying what the launch check proved.
_adopt_mcp_launch_note() {
  case "$ADOPT_MCP_LAUNCH" in
    connected) adopt_note "$1: Claude Code's own check (claude mcp get) says it starts." ;;
    failed)    adopt_note "$1: Claude Code's own check says it could NOT start it${ADOPT_MCP_LAUNCH_WHY:+ — $ADOPT_MCP_LAUNCH_WHY}." ;;
    *)         adopt_note "$1: whether Claude Code can start it was not checked (${ADOPT_MCP_LAUNCH_WHY:-no reason recorded})." ;;
  esac
}

_adopt_mcp_launch_word() {   # _adopt_mcp_launch_word STATE
  case "$1" in
    connected) printf '%s' ", Claude Code starts it" ;;
    failed)    printf '%s' ", Claude Code could NOT start it" ;;
    *)         printf '%s' ", whether Claude Code can start it not checked" ;;
  esac
}

_adopt_mcp_is_local_url() {
  case "${1%/}" in http://localhost:6333|http://127.0.0.1:6333) return 0 ;; esac
  return 1
}

_adopt_mcp_describe() {   # _adopt_mcp_describe C7 Q URL
  case "$1" in
    registered) adopt_note "Context7 (current library documentation): registered for Claude Code." ;;
    *)          adopt_note "Context7 (current library documentation): NOT registered for Claude Code." ;;
  esac
  case "$2" in
    reachable)   adopt_note "Qdrant (memory across sessions): registered, and answering at $3." ;;
    unreachable) adopt_note "Qdrant (memory across sessions): registered, but NOTHING answers at $3." ;;
    unknown)     adopt_note "Qdrant (memory across sessions): registered, but whether it answers at $3 could not be checked." ;;
    *)           adopt_note "Qdrant (memory across sessions): NOT registered for Claude Code." ;;
  esac
}

# adopt_mcp_resolve ROOT — the step. Returns 1 only when the operator gave an
# answer that is not one of the two offered (the driver's rule for every
# question); every other path, including skip and failure, returns 0.
adopt_mcp_resolve() {                                  # BL-311-MCP-STEP
  local root="$1"
  local st="" c7="" q="" qurl="" c7_why="" q_why="" q_db="" raw="" ans="" row=""
  local c7_before="" q_before=""
  ADOPT_MCP_PLAN=()
  ADOPT_MCP_REGISTERED=""
  ADOPT_MCP_PENDING=0
  ADOPT_MCP_QDRANT_BIND="none"; ADOPT_MCP_QDRANT_BIND_WHY=""; ADOPT_MCP_QDRANT_KEY="unread"
  # `SOIF_ADOPT_MCP=off` IS A TEST SEAM, like SOIF_ADOPT_QDRANT and
  # SOIF_ADOPT_GUARDRAILS_DIR. Every adoption suite written before this step
  # pipes a fixed answer sequence; on a developer machine that HAS `claude`
  # and is missing a server, this step would ask its question in the middle of
  # that sequence and a piped "1" would run real `claude mcp add` / `docker`
  # commands. The seam skips the whole step and says so in one line. The
  # step's own suite, tests/test-bl311-adopt-mcp.sh, never sets it.
  if [ "${SOIF_ADOPT_MCP:-}" = "off" ]; then           # BL-311-MCP-SEAM
    adopt_note "MCP server check skipped (SOIF_ADOPT_MCP=off)."
    ADOPT_MCP_RESULT="not checked (SOIF_ADOPT_MCP=off)"
    return 0
  fi
  adopt_head "The memory and documentation servers Claude Code uses here"

  st="$(_adopt_mcp_state)" || st=""
  if [ -z "$st" ]; then
    adopt_note "Could not read this machine's Claude Code configuration (scripts/lib/helpers-full.sh"
    adopt_note "did not load), so nothing was checked and nothing was set up."
    ADOPT_MCP_RESULT="not checked: the framework's MCP helpers did not load"
    return 0
  fi
  read -r c7 q qurl <<EOF
$st
EOF
  c7_before="$c7"; q_before="$q"
  adopt_note "Read from the two files a Claude Code session started from here reads:"
  adopt_note "  $(soif_claude_json_path)"
  adopt_note "  $(soif_claude_settings_path)"
  _adopt_mcp_describe "$c7" "$q" "$qurl"

  # ── AN EXISTING qdrant CONTAINER, READ ONCE FOR EVERY PATH BELOW ─────────
  # Every path that prints or plans `docker start` — whatever the registration
  # state, and even when nothing is offered (the state this host is in: Qdrant
  # registered and answering from a container published on every interface) —
  # reads it here, so the note below is true of all of them.
  local d_up=0 q_ctr=0
  if command -v docker >/dev/null 2>&1; then
    if _adopt_mcp_docker_up; then
      d_up=1
      if _adopt_mcp_qdrant_container; then q_ctr=1; _adopt_mcp_inspect; fi   # BL-311-MCP-HOIST
    else
      ADOPT_MCP_QDRANT_BIND="unread"; ADOPT_MCP_QDRANT_BIND_WHY="Docker is not running here"
    fi
  fi

  # ── WHAT COULD BE DONE HERE, AND WHY NOT WHERE IT CANNOT ──────────────────
  if [ "$c7" != "registered" ]; then
    if ! command -v claude >/dev/null 2>&1; then c7_why="the claude command is not on PATH (set up Claude Code first)"
    elif ! command -v npx >/dev/null 2>&1; then c7_why="npx is not on PATH, and the server runs through it (npx comes with Node.js — set up Node.js first)"   # BL-311-MCP-NPX-PRECONDITION
    else ADOPT_MCP_PLAN[${#ADOPT_MCP_PLAN[@]}]="context7|$ADOPT_MCP_CONTEXT7_ADD"
    fi
  fi
  case "$q" in
    unregistered)
      if ! command -v claude >/dev/null 2>&1; then q_why="the claude command is not on PATH (set up Claude Code first)"
      elif ! command -v uvx >/dev/null 2>&1; then q_why="uvx is not on PATH, and the server runs through it (uvx comes with uv — set up uv first)"
      elif _adopt_mcp_local_qdrant; then q_db="already answering at http://localhost:6333"
      elif [ "$d_up" != 1 ]; then q_why="Docker is not running (start Docker Desktop, or set Docker up first)"
      elif [ "$q_ctr" = 1 ]; then q_db="$ADOPT_MCP_QDRANT_START"
      else q_db="$ADOPT_MCP_QDRANT_RUN"
      fi
      if [ -z "$q_why" ]; then
        case "$q_db" in docker*) ADOPT_MCP_PLAN[${#ADOPT_MCP_PLAN[@]}]="qdrant|$q_db" ;; esac
        ADOPT_MCP_PLAN[${#ADOPT_MCP_PLAN[@]}]="qdrant|$ADOPT_MCP_QDRANT_ADD"
      fi ;;
    unreachable)
      if ! _adopt_mcp_is_local_url "$qurl"; then q_why="it is registered at $qurl, which is not a database this machine runs — start that server"
      elif [ "$d_up" != 1 ]; then q_why="Docker is not running (start Docker Desktop, or set Docker up first)"
      elif [ "$q_ctr" = 1 ]; then ADOPT_MCP_PLAN[${#ADOPT_MCP_PLAN[@]}]="qdrant|$ADOPT_MCP_QDRANT_START"
      else ADOPT_MCP_PLAN[${#ADOPT_MCP_PLAN[@]}]="qdrant|$ADOPT_MCP_QDRANT_RUN"
      fi ;;
    unknown)
      q_why="neither curl nor nc is installed, so whether it answers cannot be checked" ;;
  esac

  [ -n "$c7_why" ] && adopt_note "Adoption cannot set up Context7 here: $c7_why."
  [ -n "$q_why" ] && adopt_note "Adoption cannot set up Qdrant here: $q_why."
  case "$ADOPT_MCP_QDRANT_BIND" in open-*) _adopt_mcp_open_note ;; esac   # BL-311-MCP-OPEN-SAY

  ans="$ADOPT_MCP_SKIP"
  if [ "${#ADOPT_MCP_PLAN[@]}" -gt 0 ]; then            # BL-311-MCP-ASK-ONLY-IF-ACTIONABLE
    adopt_blank
    # SHOWN BEFORE THE QUESTION, not after the answer — consent to run a string
    # the operator has not seen is not consent (adopt_resolve_tools' rule).
    adopt_note "This would run, exactly as written:"
    for row in "${ADOPT_MCP_PLAN[@]}"; do adopt_note "  ${row#*|}"; done   # BL-311-MCP-SHOWN-FIRST
    case "${ADOPT_MCP_PLAN[*]}" in
      *"claude mcp add"*)
        adopt_note "The claude commands change your Claude Code configuration for every project,"
        adopt_note "not only this one. Nothing is written into this project." ;;
      *) adopt_note "Nothing is written into this project." ;;
    esac
    adopt_offer_choice "Set them up now? (No answer means skip it.)" "$ADOPT_MCP_SKIP" "$ADOPT_MCP_SETUP"   # BL-311-MCP-OFFER-ORDER
    adopt_read_optional
    raw="$ADOPT_ANSWER"
    printf '\n'
    if [ -z "$raw" ]; then                                   # BL-311-MCP-EOF-SKIP
      adopt_note "No answer — treated as skip it."
    else
      ans="$(adopt_resolve_choice "$raw" "$ADOPT_MCP_SKIP" "$ADOPT_MCP_SETUP")"   # BL-311-MCP-RESOLVE-ORDER
      if [ -z "$ans" ]; then
        adopt_refuse "'$raw' is not one of the answers offered for: setting up the MCP servers"
        return 1
      fi
    fi
  fi

  # ── `## BL-322:` S3 — THE ANSWER IS TAKEN HERE; THE COMMANDS RUN LATER ──
  # What the step found and was told is kept for adopt_mcp_apply, which the
  # driver calls once every check that can stop the adoption without writing
  # has passed (`# BL-322-S3-MCP-APPLY-CALL`). Dogfood run 3, finding 5: run
  # here, a run the ignore check then stopped had already registered two
  # servers in the operator's user configuration.
  _ADOPT_MCP_C7="$c7"; _ADOPT_MCP_Q="$q"; _ADOPT_MCP_QURL="$qurl"; _ADOPT_MCP_ANS="$ans"
  _ADOPT_MCP_C7_WHY="$c7_why"; _ADOPT_MCP_Q_WHY="$q_why"; _ADOPT_MCP_C7_BEFORE="$c7_before"; _ADOPT_MCP_Q_BEFORE="$q_before"
  if [ "$ans" = "$ADOPT_MCP_SETUP" ]; then
    ADOPT_MCP_PENDING=1   # BL-322-S3-MCP-DEFER
    adopt_note "Noted. Nothing has run yet: these run once the checks that can stop this"
    adopt_note "adoption before it writes have passed. A stop before then registers nothing;"
    adopt_note "a later stop (a file it cannot write, your own commit hook) leaves the"   # BL-322-S3-MCP-DEFER-SAY
    adopt_note "registration, and says so."
    return 0
  elif [ "${#ADOPT_MCP_PLAN[@]}" -gt 0 ]; then
    adopt_note "Skipped. Nothing was run."
  fi
  _adopt_mcp_finish
  return 0
}

# adopt_mcp_apply ROOT — `## BL-322:` S3: run what the operator agreed to at the
# question (adopt_mcp_resolve), then the receipt, Claude Code's launch check, the
# Adoption Record's cell and the note. A no-op unless the answer was "set it up
# now". Called by the driver after the pre-write checks and before the first
# write (`# BL-322-S3-MCP-APPLY-CALL`); a refusal after it still names what it
# registered (`# BL-318-G6-OUTSIDE`).
adopt_mcp_apply() {                                     # BL-322-S3-MCP-APPLY
  local root="$1"
  local st="" c7="${_ADOPT_MCP_C7:-}" q="${_ADOPT_MCP_Q:-}" qurl="${_ADOPT_MCP_QURL:-}" ans="${_ADOPT_MCP_ANS:-}"
  local q_before="${_ADOPT_MCP_Q_BEFORE:-}" row="" srv="" cmd="" q_failed=0 fp_before="" fp_after="" added=""
  [ "${ADOPT_MCP_PENDING:-0}" = 1 ] || return 0
  ADOPT_MCP_PENDING=0
  adopt_head "Setting up the memory and documentation servers"
  if [ "$ans" = "$ADOPT_MCP_SETUP" ]; then
    : > "$ADOPT_WORK/mcp-setup.out" 2>/dev/null
    fp_before="$(adopt_tree_fingerprint "${root:-}")" || fp_before=""
    for row in "${ADOPT_MCP_PLAN[@]}"; do
      srv="${row%%|*}"; cmd="${row#*|}"
      # A failed Qdrant step stops the Qdrant chain: registering a server whose
      # database did not come up would make it required and block every edit.
      if [ "$srv" = "qdrant" ] && [ "$q_failed" -eq 1 ]; then
        adopt_note "Not run: $cmd"
        continue
      fi
      adopt_note "Running: $cmd"
      case "$cmd" in "claude mcp add "*) added="$added $srv" ;; esac   # BL-318-G6-MCP-ATTEMPT
      if ! _adopt_mcp_run "$cmd"; then
        adopt_note "  That did not succeed: $(_adopt_mcp_last_output)"
        [ "$srv" = "qdrant" ] && q_failed=1   # BL-311-MCP-FAIL-STOPS-QDRANT
        case "$cmd" in
          docker*) adopt_note "  So Qdrant will NOT be registered: its database did not start, and a registered"
                   adopt_note "  server with nothing behind it would block every file edit in this project." ;;
        esac
        continue
      fi
      case "$cmd" in
        docker*)
          if ! _adopt_mcp_wait_qdrant; then
            if [ "$q_before" = "unregistered" ]; then
              adopt_note "  The database did not answer at http://localhost:6333 afterwards, so Qdrant"
              adopt_note "  was not registered — a registered server with no database blocks every edit."
            else
              adopt_note "  The database still did not answer at http://localhost:6333 afterwards."
            fi
            q_failed=1   # BL-311-MCP-WAIT-BEFORE-REGISTER
          fi ;;
      esac
    done
    fp_after="$(adopt_tree_fingerprint "${root:-}")" || fp_after=""
    if [ -z "$fp_before" ] || [ -z "$fp_after" ] || [ "$fp_before" != "$fp_after" ]; then   # BL-311-MCP-TOUCHED-IF
      adopt_touched_disk; adopt_touched_disk_unbounded   # BL-311-MCP-TOUCHED-ON-CHANGE
    fi
    # THE RECEIPT: what is registered and answering NOW, read the same way the
    # first look was. Only this is claimed.
    st="$(_adopt_mcp_state)" || st=""                       # BL-311-MCP-RECEIPT
    read -r c7 q qurl <<EOF
$st
EOF
    adopt_blank
    adopt_note "Afterwards:"
    _adopt_mcp_describe "$c7" "$q" "$qurl"
    # What this run registered: its `claude mcp add` ran here, and the receipt
    # shows it registered. The plan offers an add only for a server the first
    # look found unregistered, so a server registered before the run is never
    # attempted, and never named.
    case " $added " in *" context7 "*) [ "$c7" = "registered" ] && ADOPT_MCP_REGISTERED="${ADOPT_MCP_REGISTERED:+$ADOPT_MCP_REGISTERED }context7" ;; esac   # BL-318-G6-MCP-REG-C7
    case " $added " in *" qdrant "*) [ -n "$q" ] && [ "$q" != "unregistered" ] && ADOPT_MCP_REGISTERED="${ADOPT_MCP_REGISTERED:+$ADOPT_MCP_REGISTERED }qdrant" ;; esac   # BL-318-G6-MCP-REG-Q
  fi
  _ADOPT_MCP_C7="$c7"; _ADOPT_MCP_Q="$q"; _ADOPT_MCP_QURL="$qurl"
  _adopt_mcp_finish
  return 0
}

# _adopt_mcp_finish — Claude Code's launch check, the Adoption Record's cell and
# the note, from what adopt_mcp_resolve found and (after "set it up now")
# adopt_mcp_apply's receipt read.
_adopt_mcp_finish() {
  local c7="${_ADOPT_MCP_C7:-}" q="${_ADOPT_MCP_Q:-}" qurl="${_ADOPT_MCP_QURL:-}" ans="${_ADOPT_MCP_ANS:-}"
  local c7_why="${_ADOPT_MCP_C7_WHY:-}" q_why="${_ADOPT_MCP_Q_WHY:-}" c7_before="${_ADOPT_MCP_C7_BEFORE:-}" q_before="${_ADOPT_MCP_Q_BEFORE:-}"
  local c7_word="" q_word=""
  # ── CLAUDE CODE'S OWN LAUNCH CHECK, for every server that is registered ──
  local c7_launch="" c7_launch_why="" c7_remove="" q_launch="" q_launch_why="" q_remove=""
  if [ "$c7" = "registered" ] || [ "$q" != "unregistered" ]; then adopt_blank; fi
  if [ "$c7" = "registered" ]; then
    _adopt_mcp_launch context7
    c7_launch="$ADOPT_MCP_LAUNCH"; c7_launch_why="$ADOPT_MCP_LAUNCH_WHY"; c7_remove="$ADOPT_MCP_LAUNCH_REMOVE"
    _adopt_mcp_launch_note "Context7"
  fi
  if [ "$q" != "unregistered" ]; then
    _adopt_mcp_launch qdrant
    q_launch="$ADOPT_MCP_LAUNCH"; q_launch_why="$ADOPT_MCP_LAUNCH_WHY"; q_remove="$ADOPT_MCP_LAUNCH_REMOVE"
    _adopt_mcp_launch_note "Qdrant"
  fi

  # ── THE RECORD'S CELL — the state the receipt read, and how it got there ──
  case "$q" in
    reachable)   q_word="registered and answering" ;;
    unreachable) q_word="registered, NOT answering" ;;
    unknown)     q_word="registered, whether it answers not checked" ;;
    *)           q_word="NOT registered" ;;
  esac
  if [ "$q" = "reachable" ] && [ "$q_before" = "reachable" ]; then q_word="$q_word before adoption"
  elif [ "$q" = "reachable" ]; then q_word="set up by adoption, $q_word"
  elif [ -n "$q_why" ]; then q_word="$q_word (adoption could not act: $q_why)"
  elif [ "$ans" = "$ADOPT_MCP_SETUP" ]; then q_word="$q_word after adoption tried"
  else q_word="$q_word (skipped)"
  fi
  if [ "$c7" = "registered" ] && [ "$c7_before" = "registered" ]; then c7_word="registered before adoption"
  elif [ "$c7" = "registered" ]; then c7_word="set up by adoption, registered"
  elif [ -n "$c7_why" ]; then c7_word="NOT registered (adoption could not act: $c7_why)"
  elif [ "$ans" = "$ADOPT_MCP_SETUP" ]; then c7_word="NOT registered after adoption tried"
  else c7_word="NOT registered (skipped)"
  fi
  [ -n "$q_launch" ] && q_word="$q_word$(_adopt_mcp_launch_word "$q_launch")"
  [ -n "$c7_launch" ] && c7_word="$c7_word$(_adopt_mcp_launch_word "$c7_launch")"
  ADOPT_MCP_RESULT="Qdrant: $q_word; Context7: $c7_word"   # BL-311-MCP-RESULT
  if [ "$c7" = "registered" ] && [ "$q" = "reachable" ] && [ "$c7_launch" = "connected" ] && [ "$q_launch" = "connected" ]; then   # BL-311-MCP-EARLY-RETURN
    return 0
  fi

  _adopt_mcp_consequence "$c7" "$q" "$qurl" "$c7_launch" "$c7_launch_why" "$c7_remove" "$q_launch" "$q_launch_why" "$q_remove"
  return 0
}

# _adopt_mcp_consequence C7 Q URL — the LOUD NOTE. It states what the session
# check will actually do in each state, because "blocked until both are
# available" is false for a server registered nowhere (session-mcp-gate.sh
# does not require it) and too weak for one registered but silent (it blocks
# EVERY edit). Cases E5 and E6 run the adopted project's own hooks to hold each
# sentence to what the gate really does.
_adopt_mcp_consequence() {                               # BL-311-MCP-LOUD-NOTE
  local c7="$1" q="$2" qurl="$3" c7l="${4:-}" c7w="${5:-}" c7r="${6:-}" ql="${7:-}" qw="${8:-}" qr="${9:-}"
  adopt_blank
  # REGISTERED BUT CLAUDE CODE CANNOT START IT is the worst state: registered
  # makes it REQUIRED, and a required tool that never starts blocks every edit.
  # Said first, plainly, with Claude Code's own command to back it out.
  if [ "$ql" = "failed" ]; then                                           # BL-311-MCP-NOTE-LAUNCH
    adopt_note "BLOCKED UNTIL FIXED: Qdrant IS registered, but Claude Code could NOT start it${qw:+ ($qw)}."
    adopt_note "  Every file edit in this project is blocked until it can. To back the registration out:"
    adopt_note "    $qr"
  fi
  if [ "$c7l" = "failed" ]; then                                          # BL-311-MCP-NOTE-LAUNCH-C7
    adopt_note "BLOCKED UNTIL FIXED: Context7 IS registered, but Claude Code could NOT start it${c7w:+ ($c7w)}."
    adopt_note "  Every file edit in this project is blocked until it can. To back the registration out:"
    adopt_note "    $c7r"
  fi
  if [ "$ql" = "unchecked" ] && [ -n "$qw" ] && [ "$qw" != "the claude command is not on PATH" ]; then   # BL-311-MCP-NOTE-UNCHECKED
    adopt_note "Whether Claude Code can start Qdrant could not be checked ($qw). If it cannot, every"
    adopt_note "  file edit here is blocked until it can. Check it with: claude mcp get qdrant"
  fi
  if [ "$c7l" = "unchecked" ] && [ -n "$c7w" ] && [ "$c7w" != "the claude command is not on PATH" ]; then   # BL-311-MCP-NOTE-UNCHECKED-C7
    adopt_note "Whether Claude Code can start Context7 could not be checked ($c7w). If it cannot, every"
    adopt_note "  file edit here is blocked until it can. Check it with: claude mcp get context7"
  fi
  [ "$q" = "reachable" ] && [ "$c7" = "registered" ] && return 0
  adopt_note "NOT SET UP — what that means for Claude Code in this project:"
  case "$q" in
    unreachable|unknown)
      adopt_note "  Qdrant IS registered, so the framework REQUIRES it: in every Claude Code session"
      adopt_note "  here, EVERY file edit is BLOCKED until qdrant-find succeeds — which needs the"   # BL-311-MCP-NOTE-BLOCKS
      adopt_note "  database at $qurl answering." ;;
    unregistered)
      adopt_note "  Qdrant is not registered: sessions here have no memory of earlier sessions. The"
      adopt_note "  framework's check for it is off while it is not registered, and ON from the first"   # BL-311-MCP-NOTE-OFF
      adopt_note "  session after you register it — so have the database running when you do." ;;
  esac
  if [ "$c7" != "registered" ]; then
    adopt_note "  Context7 is not registered: sessions here cannot read current library documentation."
    adopt_note "  Its check is off until you register it, and ON from the next session after that."
  fi
  adopt_note "To set them up later, run these, then start a new Claude Code session:"
  case "$q" in
    unregistered)
      adopt_note "  $ADOPT_MCP_QDRANT_RUN"
      adopt_note "    (or, if a container named qdrant already exists: $ADOPT_MCP_QDRANT_START)"
      _adopt_mcp_open_hint   # BL-311-MCP-OPEN-HINT-UNREGISTERED
      adopt_note "  $ADOPT_MCP_QDRANT_ADD" ;;
    unreachable|unknown)
      if _adopt_mcp_is_local_url "$qurl"; then
        adopt_note "  $ADOPT_MCP_QDRANT_START"
        _adopt_mcp_open_hint   # BL-311-MCP-OPEN-HINT-UNREACHABLE
        adopt_note "    (or, if there is no container named qdrant: $ADOPT_MCP_QDRANT_RUN)"
      else
        adopt_note "  (Qdrant: start the server at $qurl — it is not one this machine runs)"
      fi ;;
  esac
  if [ "$c7" != "registered" ]; then adopt_note "  $ADOPT_MCP_CONTEXT7_ADD"; fi
  return 0
}

# _adopt_mcp_open_hint — beside every `docker start` hint: how the container
# that starts is published, as read above, or that it could not be read.
_adopt_mcp_open_hint() {
  case "$ADOPT_MCP_QDRANT_BIND" in                           # BL-311-MCP-OPEN-HINT
    open-default|open-publish-all)
      adopt_note "    (your existing qdrant container is published on every network interface unless"
      adopt_note "     your Docker daemon sets a default bind address — see 'Your existing qdrant"
      adopt_note "     container' above before starting it)" ;;
    open-*)
      adopt_note "    (your existing qdrant container is published beyond this machine — see"
      adopt_note "     'Your existing qdrant container' above before starting it)" ;;
    unread)
      adopt_note "    (how an existing qdrant container is published could not be read — ${ADOPT_MCP_QDRANT_BIND_WHY:-no reason recorded};"   # BL-311-MCP-UNREAD-HINT
      adopt_note "     check before starting it: docker inspect -f '{{json .HostConfig.PortBindings}} {{.HostConfig.PublishAllPorts}} {{.HostConfig.NetworkMode}}' qdrant)" ;;
  esac
  return 0
}

# adopt_mcp_restart_note — printed at the act boundary, BEFORE "NEXT".
#
# A SESSION ALREADY OPEN WHEN ADOPTION RAN CANNOT SAVE A FILE HERE AFTERWARDS,
# measured in the dogfood run (finding 12): the new hooks fire in it, but its
# SessionStart ran before they existed, so `.claude/tool-usage.json` was never
# written and session-mcp-gate.sh denies every Write/Edit as "cannot tell".
# Only a session started after adoption writes that ledger and loads the MCP
# servers registered above.
adopt_mcp_restart_note() {                             # BL-311-ACT2-RESTART
  adopt_note "FIRST: if a Claude Code session is open in this project, close it and start a new"
  adopt_note "one. The checks, and the memory and documentation tools, that adoption set up"
  adopt_note "only take effect in a session started AFTER adoption — a session that was already"
  adopt_note "open cannot save a file here."
  case "${ADOPT_MCP_RESULT:-}" in
    *"NOT "*|*"not checked:"*)
      adopt_note "Qdrant or Context7 is NOT set up — see 'The memory and documentation servers'"
      adopt_note "above for what that means here and the commands that add them." ;;
  esac
  adopt_blank
}

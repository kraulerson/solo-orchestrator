#!/usr/bin/env bash
# tests/test-bl311-adopt-mcp.sh — `## BL-311:` fixes 1 and 9: adoption checks
# for, and offers to set up, the two MCP servers a Claude Code session in the
# adopted project is checked for; every MCP reader honours CLAUDE_CONFIG_DIR;
# check-versions.sh reports registration, not installation.
#
# HERMETIC. Every case runs with a temp HOME and a temp CLAUDE_CONFIG_DIR, and
# with STUB `claude`, `docker`, `curl`, `uvx` and `npx` first on PATH — so no
# case reads the host's Claude configuration, starts a container or registers
# anything. The `claude` stub parses `mcp add` the way Claude Code 2.1.283 does
# (MEASURED against a scratch CLAUDE_CONFIG_DIR): `-e` is variadic, so a server
# name placed after the `-e` options is taken as an environment value and the
# command exits 1 with "Invalid environment variable format". It writes the
# entry where the real one does — `$CLAUDE_CONFIG_DIR/.claude.json` when that
# is set, `~/.claude.json` otherwise. The `curl` stub answers for
# localhost:6333 only while the `docker` stub has "started" the database. Every
# stub DRAINS its stdin and logs it if it got any, because a subprocess that
# reads the operator's answers is a defect this step can cause (S2/E2, M20).
#
# WHAT EACH CASE OWNS.
#   A1  a registration only in $CLAUDE_CONFIG_DIR is seen by every helper;
#       one only in ~/.claude.json is NOT while CLAUDE_CONFIG_DIR is set (A2),
#       and IS when it is unset (A3)
#   A4  settings.json follows CLAUDE_CONFIG_DIR too (a plugin-enabled Context7)
#   A5  the SessionStart hook derives the requirements from the same files
#   A6  check-versions.sh says NOT registered, not [OK], for servers that are
#       registered only in the file the session does not read
#   S*  THE STEP ON ITS OWN (adopt_mcp_resolve, sourced — seconds, not an
#       adoption): S1 nothing missing, no question; S2 "set it up now" — the
#       commands shown BEFORE the question, run as shown from the run's work
#       dir, registered in the session's config; S3 registered but silent +
#       skip — the note says EVERY edit is blocked; S4 unregistered + skip —
#       the note says the check is off; S5 a blank answer is skip; S6 end of
#       input is skip; S7 the commands fail — the receipt claims nothing;
#       S8 an answer not offered is refused; S9 a database that never answers
#       is not registered against; S10 the touched-disk markers follow the
#       fingerprint, not the attempt; S11 the SOIF_ADOPT_MCP=off test seam
#       skips the whole step in one line, asks nothing and runs nothing;
#       S12/S13 answers by NUMBER — "1" is skip (nothing runs), "2" is set up;
#       S14 no npx — Context7 is not offered, and what to install is said;
#       S15 a failed `docker run` — Qdrant is NOT registered, and it is said;
#       S16 registered but Claude Code cannot START it (its own `claude mcp
#       get` check) — said as a block, with Claude Code's remove command;
#       S17 the same for CONTEXT7; S18 the launch check cannot answer (a hang
#       past the bound, and no status) — said, never read as either answer;
#       S19-S19g an EXISTING qdrant container published on every interface —
#       read ONCE for every path (unregistered, registered-but-stopped,
#       already answering, both present, 0.0.0.0, ::, Docker down) and said
#       before the question and beside every later `docker start` hint, never
#       recreated; S20 a loopback-bound one — no such note; S25 inspect fails;
#       S27 an API key read from the container's env, its value never printed;
#       S28 the written procedure's command blocks pinned exactly (the same
#       settings read first, snapshots and aliases saved, snapshot files kept in
#       the container copied out, the running image ID reused, rename before
#       stop, restore, check — never a file copy of the storage); S29 NO
#       COMMAND FOR ANY CONTAINER — over a volume, a host folder, a --tmpfs,
#       nothing mounted, --rm, a pinned image, an API key, 0.0.0.0 and ::, the
#       note points to that procedure and has no paste-shaped line and no
#       `docker `, `&&` or `$(`; with no API key it is one text, whatever the
#       storage; S30/S31 MIXED bindings (one port open, one on loopback) are
#       open; S32 an EMPTY API key is not a key; S33 bindings that do not
#       parse are "could not be read", never loopback — and so are a
#       PublishAllPorts that is not a boolean (S33b) and a NetworkMode that is
#       not a string or carries two values (S33c); S34 -P, S35 --network
#       host and S36 a LAN address are exposed, each in its own words (and S20
#       holds ::1 as loopback); S37 a lowercase key is a key; S38 the written
#       procedure RUN against a stand-in Qdrant — jq missing, the empty list
#       that lost data in round 14, a lost API key, a failed upload, and
#       (round 15) a download cut short, no sha256 tool, and the old container
#       at the address `docker port` gives while the new one is on 6333
#   E*  WHOLE ADOPTIONS: E1 both present — no question, the Record row, and
#       the restart sentence BEFORE "NEXT"; E2 set it up now — no command read
#       the operator's answers, and the project collection is declared; E3
#       skip — the Record row and the closing pointer; E4 no `claude` command
#       (the CI shape) — an answer sequence written without this step still
#       completes; E5 registered but silent — the adopted project's own gate
#       DOES block a Write (the S3 sentence is true); E6 the dogfood shape — a
#       registration in ~/.claude.json only, a database running, uvx present,
#       skip — nothing declared for the project and its own gate ALLOWS a Write;
#       E7 the dogfood answers, `1` to every question — the MCP question takes
#       its `1` as SKIP (it is listed first), nothing runs, adoption completes
#   A7  verify-install.sh's Qdrant row reads the files the session reads
#   A8  the Stop-hook Qdrant reminder reads the same files
#   M*  mutation proofs, one per guard, each required to die by its NAMED
#       assertion — see the M section.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }
_done() { echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; [ "$FAILED" -eq 0 ]; exit $?; }

echo "== BL-311 — the MCP servers on the adoption path, and CLAUDE_CONFIG_DIR =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; _done; }
done
WORK="$(mktemp -d)" || exit 1
# THIS SUITE EXERCISES THE REAL STEP, so the test seam every other adoption
# suite exports (`SOIF_ADOPT_MCP=off`) is cleared here — a developer who has it
# in their shell would otherwise run every case against a step that never ran.
# Only S11 sets it, explicitly, to pin the seam itself.
unset SOIF_ADOPT_MCP
# BL311_KEEP=1 keeps the fixtures for a post-mortem and prints where they are.
if [ "${BL311_KEEP:-0}" = "1" ]; then echo "  (fixtures kept in $WORK)"; else trap 'rm -rf "$WORK"' EXIT; fi

# ── the stubs ───────────────────────────────────────────────────────────────
# Each logs its argv, its cwd, and whether its stdin carried anything.
_mkstubs() {   # DIR [with-claude: yes|no] [npx: yes|no]
  local d="$1" with_claude="${2:-yes}" with_npx="${3:-yes}"
  mkdir -p "$d" || return 1
  cat > "$d/docker" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
{ printf 'docker'; for a in "$@"; do printf ' [%s]' "$a"; done; printf ' cwd=%s\n' "$PWD"; } >> "$st/calls.log"
if [ ! -t 0 ]; then x="$(cat)"; [ -n "$x" ] && echo "STDIN-HAD-DATA docker" >> "$st/calls.log"; fi
case "${1:-}" in
  info)  [ -f "$st/docker-up" ] ;;
  ps)    if [ "${2:-}" = "-a" ]; then [ -f "$st/qdrant-exists" ] && echo qdrant; else [ -f "$st/qdrant-up" ] && echo qdrant; fi; exit 0 ;;
  start) : > "$st/qdrant-up"; echo qdrant ;;
  # `docker inspect -f TEMPLATE qdrant` ANSWERS THE TEMPLATE IT IS GIVEN: one
  # line per `{{json .Field}}`, in the order asked, as the real one does — so a
  # container's SHAPE is set here once, and reaches the step whatever the step
  # asks for (S29 relies on that: a version that read the mounts again would be
  # handed these). Fields in the shape Docker 29.2.1 prints them (measured on
  # this host's own container); a field not modelled answers null. The knobs:
  #   qdrant-open        the HostIp ("" = none named, 0.0.0.0, ::); default 127.0.0.1
  #   qdrant-bindings    the WHOLE .HostConfig.PortBindings line, verbatim — for
  #                      MIXED bindings (one port open, one on loopback) and for
  #                      an answer that does not parse; overrides qdrant-open
  #   qdrant-publish-all created with -P (.HostConfig.PublishAllPorts true)
  #   qdrant-network     .HostConfig.NetworkMode (e.g. host); default bridge
  #   qdrant-publish-all-raw / qdrant-network-raw  the WHOLE PublishAllPorts /
  #                      NetworkMode line, verbatim — for an answer of the wrong
  #                      type or with two values on it (S33b, S33c); overrides
  #                      the two knobs above
  #   qdrant-mount       one `type|source|destination` per line (an empty file =
  #                      nothing mounted); default this host's real shape, the
  #                      qdrant_storage volume at /qdrant/storage
  #   qdrant-env         one VAR=value per line; default no API key
  #   qdrant-autoremove  started with --rm
  #   qdrant-tmpfs       the .HostConfig.Tmpfs keys, one per line (empty: the one
  #                      key /qdrant/storage) — real Docker lists a --tmpfs ONLY
  #                      there, never in .Mounts
  #   qdrant-image       .Config.Image; default qdrant/qdrant:latest
  #   qdrant-up          running (.State.Running)
  inspect) [ -f "$st/qdrant-exists" ] || { echo "error: no such object: qdrant" >&2; exit 1; }
           [ -f "$st/inspect-fails" ] && { echo "error: stub inspect failure" >&2; exit 1; }
           fmt=""; prev=""; for a in "$@"; do [ "$prev" = "-f" ] && fmt="$a"; prev="$a"; done
           printf '%s\n' "$fmt" | grep -o '{{json [^}]*}}' | sed 's/^{{json //; s/}}$//' | while IFS= read -r fld; do
             case "$fld" in
               .HostConfig.PortBindings)
                 if [ -f "$st/qdrant-bindings" ]; then printf '%s\n' "$(cat "$st/qdrant-bindings")"; continue; fi
                 hip='127.0.0.1'; [ -f "$st/qdrant-open" ] && hip="$(cat "$st/qdrant-open")"
                 jq -cn --arg h "$hip" '{"6333/tcp":[{"HostIp":$h,"HostPort":"6333"}],"6334/tcp":[{"HostIp":$h,"HostPort":"6334"}]}' ;;
               .HostConfig.PublishAllPorts)
                 if [ -f "$st/qdrant-publish-all-raw" ]; then printf '%s\n' "$(cat "$st/qdrant-publish-all-raw")"; continue; fi
                 if [ -f "$st/qdrant-publish-all" ]; then echo true; else echo false; fi ;;
               .HostConfig.NetworkMode)
                 if [ -f "$st/qdrant-network-raw" ]; then printf '%s\n' "$(cat "$st/qdrant-network-raw")"; continue; fi
                 if [ -f "$st/qdrant-network" ]; then jq -cn --arg n "$(cat "$st/qdrant-network")" '$n'; else echo '"bridge"'; fi ;;
               .Mounts)
                 mf="$st/qdrant-mount"; [ -f "$mf" ] || { mf="$st/.default-mount"; printf 'volume|qdrant_storage|/qdrant/storage\n' > "$mf"; }
                 arr='[]'
                 while IFS='|' read -r mt ms md; do
                   case "$mt" in
                     volume) arr="$(printf '%s' "$arr" | jq -c --arg n "$ms" --arg d "$md" '. + [{Type:"volume",Name:$n,Source:("/var/lib/docker/volumes/"+$n+"/_data"),Destination:$d,Driver:"local",Mode:"z",RW:true,Propagation:""}]')" ;;
                     bind)   arr="$(printf '%s' "$arr" | jq -c --arg s "$ms" --arg d "$md" '. + [{Type:"bind",Source:$s,Destination:$d,Mode:"",RW:true,Propagation:"rprivate"}]')" ;;
                     tmpfs)  arr="$(printf '%s' "$arr" | jq -c --arg d "$md" '. + [{Type:"tmpfs",Source:"",Destination:$d,Mode:"",RW:true,Propagation:""}]')" ;;
                   esac
                 done < "$mf"
                 printf '%s\n' "$arr" ;;
               .Config.Env)
                 ef="$st/qdrant-env"; [ -f "$ef" ] || { ef="$st/.default-env"; printf 'PATH=/usr/local/sbin:/usr/local/bin\nRUN_MODE=production\n' > "$ef"; }
                 jq -cR -s 'split("\n") | map(select(length > 0))' < "$ef" ;;
               .HostConfig.AutoRemove)
                 if [ -f "$st/qdrant-autoremove" ]; then echo true; else echo false; fi ;;
               .HostConfig.Tmpfs)
                 if [ -s "$st/qdrant-tmpfs" ]; then jq -cR -s 'split("\n") | map(select(length > 0)) | map({(.): ""}) | add' < "$st/qdrant-tmpfs"
                 elif [ -f "$st/qdrant-tmpfs" ]; then echo '{"/qdrant/storage":""}'
                 else echo null; fi ;;
               .State.Running)
                 if [ -f "$st/qdrant-up" ]; then echo true; else echo false; fi ;;
               .Config.Image)
                 if [ -f "$st/qdrant-image" ]; then jq -cn --arg i "$(cat "$st/qdrant-image")" '$i'; else echo '"qdrant/qdrant:latest"'; fi ;;
               .Image) echo '"sha256:1111"' ;;
               *) echo null ;;
             esac
           done ;;
  run)   if [ -f "$st/docker-run-fails" ]; then echo "docker: Error response from daemon: stub refusal" >&2; exit 125; fi
         : > "$st/qdrant-exists"; [ -f "$st/docker-run-noop" ] || : > "$st/qdrant-up"; echo 0123abcd ;;
  *)     exit 0 ;;
esac
STUB
  cat > "$d/curl" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
u=""; for a in "$@"; do u="$a"; done
echo "curl $u" >> "$st/curl.log"
if [ ! -t 0 ]; then x="$(cat)"; [ -n "$x" ] && echo "STDIN-HAD-DATA curl" >> "$st/calls.log"; fi
case "$u" in
  *localhost:6333*|*127.0.0.1:6333*) [ -f "$st/qdrant-up" ] && exit 0; exit 7 ;;
esac
exit 7
STUB
  if [ "$with_claude" = yes ]; then
    cat > "$d/claude" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
{ printf 'claude'; for a in "$@"; do printf ' [%s]' "$a"; done; printf ' cwd=%s\n' "$PWD"; } >> "$st/calls.log"
if [ ! -t 0 ]; then x="$(cat)"; [ -n "$x" ] && echo "STDIN-HAD-DATA claude" >> "$st/calls.log"; fi
[ -f "$st/claude-fails" ] && { echo "stub claude: refusing on purpose" >&2; exit 1; }
[ -n "${STUB_TOUCH:-}" ] && : > "$STUB_TOUCH"
# `claude mcp get NAME` — Claude Code's own health check, in the shape 2.1.283
# prints it (measured): a Status line, an Issue line when it failed, and the
# exact command to remove the registration.
if [ "${1:-}" = mcp ] && [ "${2:-}" = get ]; then
  n="${3:-}"
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then f="$CLAUDE_CONFIG_DIR/.claude.json"; else f="$HOME/.claude.json"; fi
  jq -e --arg n "$n" '.mcpServers[$n]' "$f" >/dev/null 2>&1 || { echo "No MCP server found with name: $n" >&2; exit 1; }
  if grep -qx "$n" "$st/launch-hang" 2>/dev/null; then sleep 5; exit 0; fi
  printf '%s:\n  Scope: User config (available in all your projects)\n' "$n"
  if grep -qx "$n" "$st/launch-silent" 2>/dev/null; then exit 0; fi
  if grep -qx "$n" "$st/launch-fails" 2>/dev/null; then
    printf '  Status: \342\234\230 Failed to connect\n  Issue: stub: %s cannot be started\n' "$n"
  else
    printf '  Status: \342\234\224 Connected\n'
  fi
  printf '\nTo remove this server, run: claude mcp remove %s -s user\n' "$n"
  exit 0
fi
[ "${1:-}" = mcp ] && [ "${2:-}" = add ] || exit 0
shift 2
name=""; envs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    -s|--scope|-t|--transport) shift 2 ;;
    -e|--env)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in -*) break ;; esac
        case "$1" in
          *=*) envs="$envs $1"; shift ;;
          *) echo "Invalid environment variable format: $1, environment variables should be added as: -e KEY1=value1 -e KEY2=value2" >&2; exit 1 ;;
        esac
      done ;;
    -*) shift ;;
    *) [ -z "$name" ] && name="$1"; shift ;;
  esac
done
[ -n "$name" ] && [ $# -gt 0 ] || { echo "stub claude: missing name or command" >&2; exit 1; }
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then f="$CLAUDE_CONFIG_DIR/.claude.json"; else f="$HOME/.claude.json"; fi
mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
e='{}'; for kv in $envs; do e="$(printf '%s' "$e" | jq --arg k "${kv%%=*}" --arg v "${kv#*=}" '.[$k] = $v')"; done
jq --arg n "$name" --arg c "$1" --argjson e "$e" '.mcpServers[$n] = {type: "stdio", command: $c, env: $e}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
echo "Added stdio MCP server $name"
STUB
  fi
  printf '#!/bin/bash\nexit 0\n' > "$d/uvx"
  [ "$with_npx" = yes ] && printf '#!/bin/bash\nexit 0\n' > "$d/npx"
  chmod +x "$d"/*
}
STUBS="$WORK/stubs"; _mkstubs "$STUBS" yes

# _mirror_without DIR NAME... — every executable on PATH, symlinked, EXCEPT each
# NAME: "this machine has no `claude`" without losing the rest of PATH.
# (Appending /usr/bin:/bin as a safety net would defeat it for a tool that lives
# there; asserted with `command -v` before it is trusted.)
_mirror_without() {
  local dir="$1" d="" f="" n="" s="" hit="" rest="$PATH:"
  shift
  mkdir -p "$dir" || return 1
  while [ -n "$rest" ]; do
    d="${rest%%:*}"; rest="${rest#*:}"
    [ -n "$d" ] && [ -d "$d" ] || continue
    for f in "$d"/*; do
      n="${f##*/}"
      hit=0; for s in "$@"; do [ "$n" = "$s" ] && hit=1; done
      [ "$hit" = 1 ] && continue
      [ -x "$f" ] && [ ! -e "$dir/$n" ] && ln -s "$f" "$dir/$n" 2>/dev/null
    done
  done
  return 0
}

# ── fixtures ────────────────────────────────────────────────────────────────
_base() {   # _base DIR — a small TypeScript project with its own history
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email bl311@test.invalid && git config user.name "BL-311 Test" ) >/dev/null 2>&1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf 'export const x = 1;\n' > "$p/src/index.ts"
  ( cd "$p" && git add -- package.json src/index.ts && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1
}
_register() {   # _register FILE qdrant|context7 [URL]
  local f="$1" s="$2" u="${3:-http://localhost:6333}"
  mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
  case "$s" in
    qdrant)   jq --arg u "$u" '.mcpServers.qdrant = {command: "uvx", env: {QDRANT_URL: $u}}' "$f" > "$f.tmp" ;;
    context7) jq '.mcpServers.context7 = {command: "npx", args: ["-y", "@upstash/context7-mcp"]}' "$f" > "$f.tmp" ;;
  esac
  mv "$f.tmp" "$f"
}
_case() {   # _case TAG — a fresh HOME, CLAUDE_CONFIG_DIR, stub state and adoptee
  # FRESH EVERY TIME, never reused by tag: the mutation pass re-runs these
  # cases, and a first draft that reused "$WORK/<tag>" had every adoption
  # mutant "killed" by "this project has already been adopted" — a failure
  # that says nothing about the guard under test. `mut` now requires each
  # mutant to die by its NAMED assertion, so that cannot hide again.
  C="$(mktemp -d "$WORK/$1.XXXXXX")" || return 1
  H="$C/home"; CFG="$C/cfg"; ST="$C/state"; P="$C/proj"
  mkdir -p "$H" "$CFG" "$ST" "$C/w" || return 1
  : > "$ST/calls.log"; : > "$ST/curl.log"
  _base "$P"
}
_n1() { local i=0 out=""; while [ "$i" -lt "$1" ]; do out="${out}1\n"; i=$((i + 1)); done; printf '%s' "$out"; }
FW="$REPO_ROOT"
RUN_PATH="$STUBS:$PATH"
# _adopt ANSWERS [ENV=VAL...] — a whole adoption of $P, with this case's HOME,
# CLAUDE_CONFIG_DIR and stubs.
# ANSWERS start with the tier and then the track (`## BL-311:` row 8); a case
# that answers the MCP question names it third, after `standard`.
_adopt() {
  local ans="$1"; shift
  ( cd "$P" && printf "$ans" | env PATH="$RUN_PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" \
      SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" SOIF_ADOPT_QDRANT_WAIT=2 "$@" \
      bash "$FW/scripts/adopt-project.sh" ) > "$C/out" 2>&1
  RUN_RC=$?
}
# _step ANSWERS — the MCP step alone, sourced the way the driver sources it,
# run from inside the adoptee so a command that ignores the work dir shows it.
cat > "$WORK/harness.sh" <<'HARN'
set -uo pipefail
ADOPT_FRAMEWORK_ROOT="$1"; ADOPT_CORE_LIB_DIR="$1/scripts/lib"; ADOPT_WORK="$2"
. "$ADOPT_CORE_LIB_DIR/helpers-core.sh"
. "$1/scripts/lib/adopt/adopt-core.sh"
. "$1/scripts/lib/adopt/adopt-mcp.sh"
adopt_stdin_init
adopt_mcp_resolve "$3"; rc=$?
printf 'RC=%s\nRESULT=%s\n' "$rc" "$ADOPT_MCP_RESULT"
HARN
_step() {   # _step ANSWERS [ENV=VAL...]
  local ans="$1"; shift
  ( cd "$P" && printf "$ans" | env PATH="$RUN_PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" \
      SOIF_ADOPT_QDRANT_WAIT=2 "$@" bash "$WORK/harness.sh" "$FW" "$C/w" "$P" ) > "$C/out" 2>&1
  STEP_RC="$(sed -n 's/^RC=//p' "$C/out" | tail -1)"
  STEP_RESULT="$(sed -n 's/^RESULT=//p' "$C/out" | tail -1)"
}
_cmd_line() { local w out="$1"; for w in $2; do out="$out [$w]"; done; printf '%s' "$out"; }   # argv as the stubs log it
_line_of() { grep -nF -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1; }
_record() { grep -F '| MCP servers (Qdrant, Context7) |' "$P/APPROVAL_LOG.md" 2>/dev/null | head -1; }
_calls_ran() { grep -qE '\[mcp\] \[add\]|docker \[(start|run)\]' "$ST/calls.log"; }
_plan() { grep -A"$1" 'This would run, exactly as written:' "$C/out" | tail -"$1" | tr '\n' '|'; }

QADD='claude mcp add -s user qdrant -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory -- uvx --python 3.13 mcp-server-qdrant'
C7ADD='claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp'
QRUN='docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest'
QSTART='docker start qdrant'

# ── A — the config-location helpers, and their three consumers ─────────────
cat > "$WORK/unit.sh" <<'UNIT'
. "$1/scripts/lib/helpers-full.sh"
is_context7_mcp_registered && echo c7=yes || echo c7=no
is_qdrant_mcp_entry_present && echo qe=yes || echo qe=no
echo "reg=$(qdrant_mcp_reg_file)"
UNIT
_unit() { env HOME="$H" "$@" bash "$WORK/unit.sh" "$FW" 2>/dev/null; }

a1() {
  local out="" bad=""
  _case a1 >/dev/null
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  out="$(_unit CLAUDE_CONFIG_DIR="$CFG")"
  printf '%s\n' "$out" | grep -qx 'c7=yes' || bad="$bad [context7 not seen]"
  printf '%s\n' "$out" | grep -qx 'qe=yes' || bad="$bad [qdrant entry not seen]"
  printf '%s\n' "$out" | grep -qxF "reg=$CFG/.claude.json" || bad="$bad [reg file is not \$CLAUDE_CONFIG_DIR/.claude.json]"
  [ -z "$bad" ] && pass "A1 a registration only in \$CLAUDE_CONFIG_DIR/.claude.json is seen by all three helpers" || fail_ "A1" "$bad — $(printf '%s' "$out" | tr '\n' ' ')"

  _case a2 >/dev/null
  _register "$H/.claude.json" qdrant; _register "$H/.claude.json" context7
  out="$(_unit CLAUDE_CONFIG_DIR="$CFG")"
  if printf '%s\n' "$out" | grep -qx 'c7=no' && printf '%s\n' "$out" | grep -qx 'qe=no' && printf '%s\n' "$out" | grep -qx 'reg='; then
    pass "A2 a registration only in ~/.claude.json is NOT seen while CLAUDE_CONFIG_DIR is set — the session does not read that file"
  else fail_ "A2" "[a ~/.claude.json registration seen] $(printf '%s' "$out" | tr '\n' ' ')"; fi

  out="$(_unit CLAUDE_CONFIG_DIR=)"
  if printf '%s\n' "$out" | grep -qx 'c7=yes' && printf '%s\n' "$out" | grep -qx 'qe=yes' && printf '%s\n' "$out" | grep -qxF "reg=$H/.claude.json"; then
    pass "A3 with CLAUDE_CONFIG_DIR unset, ~/.claude.json is read as before"
  else fail_ "A3" "$(printf '%s' "$out" | tr '\n' ' ')"; fi
}

a4() {
  local out="" bad=""
  _case a4 >/dev/null
  jq -n '{enabledPlugins: {"context7@claude-plugins-official": true}}' > "$CFG/settings.json"
  out="$(_unit CLAUDE_CONFIG_DIR="$CFG")"
  printf '%s\n' "$out" | grep -qx 'c7=yes' || bad="$bad [plugin in \$CLAUDE_CONFIG_DIR/settings.json not seen]"
  mkdir -p "$H/.claude"; cp "$CFG/settings.json" "$H/.claude/settings.json"; rm -f "$CFG/settings.json"
  out="$(_unit CLAUDE_CONFIG_DIR="$CFG")"
  printf '%s\n' "$out" | grep -qx 'c7=no' || bad="$bad [plugin in ~/.claude/settings.json seen while CLAUDE_CONFIG_DIR is set]"
  [ -z "$bad" ] && pass "A4 settings.json follows CLAUDE_CONFIG_DIR too" || fail_ "A4" "$bad"
}

a5() {   # the SessionStart hook: home-only → not required; in CLAUDE_CONFIG_DIR → required
  local out=""
  _case a5 >/dev/null
  mkdir -p "$C/p5/.claude"
  _register "$H/.claude.json" qdrant; _register "$H/.claude.json" context7
  ( cd "$C/p5" && env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash "$FW/scripts/session-test-gate-check.sh" </dev/null >/dev/null 2>&1 )
  out="$(jq -c '[.mcp_requirements.qdrant_required, .mcp_requirements.context7_required]' "$C/p5/.claude/tool-usage.json" 2>/dev/null)"
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  ( cd "$C/p5" && env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash "$FW/scripts/session-test-gate-check.sh" </dev/null >/dev/null 2>&1 )
  out="$out $(jq -c '[.mcp_requirements.qdrant_required, .mcp_requirements.context7_required]' "$C/p5/.claude/tool-usage.json" 2>/dev/null)"
  if [ "$out" = "[false,false] [true,true]" ]; then
    pass "A5 the SessionStart hook requires a server registered in \$CLAUDE_CONFIG_DIR, and not one registered only in ~/.claude.json"
  else fail_ "A5" "requirements (home-only, then cfg) = '$out' (want '[false,false] [true,true]')"; fi
}

a6() {   # check-versions.sh, over the two rows the framework SHIPS
  local out="" bad=""
  _case a6 >/dev/null
  mkdir -p "$C/p6/templates/tool-matrix" "$C/p6/.claude"
  jq '{description: "fixture", schema_version: 1, scope: "common",
       tools: (.tools | map(select(.name == "Qdrant MCP" or .name == "Context7 MCP")))}' \
    "$FW/templates/tool-matrix/common.json" > "$C/p6/templates/tool-matrix/common.json"
  _register "$H/.claude.json" qdrant; _register "$H/.claude.json" context7
  out="$( cd "$C/p6" && env PATH="$RUN_PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" bash "$FW/scripts/check-versions.sh" 2>&1 )"
  printf '%s\n' "$out" | grep -q 'Qdrant MCP: NOT registered with Claude Code' || bad="$bad [Qdrant not reported NOT registered]"
  printf '%s\n' "$out" | grep -q 'Context7 MCP: NOT registered with Claude Code' || bad="$bad [Context7 not reported NOT registered]"
  printf '%s\n' "$out" | grep -q '\[OK\] Qdrant MCP\|\[OK\] Context7 MCP' && bad="$bad [an [OK] row for a server the session does not have]"
  printf '%s\n' "$out" | grep -qF "$CFG/.claude.json" || bad="$bad [the note does not name the file it read]"
  _register "$CFG/.claude.json" context7
  out="$( cd "$C/p6" && env PATH="$RUN_PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" bash "$FW/scripts/check-versions.sh" 2>&1 )"
  printf '%s\n' "$out" | grep -q 'Context7 MCP: NOT registered' && bad="$bad [Context7 registered in \$CLAUDE_CONFIG_DIR still reported NOT registered]"
  [ -z "$bad" ] && pass "A6 check-versions.sh reports NOT registered — not [OK] — for servers registered only in a file the session does not read, and sees one registered where it does" \
    || fail_ "A6" "$bad — $(printf '%s' "$out" | grep -i 'MCP' | tr '\n' '|' | cut -c1-400)"
}

a7() {   # verify-install.sh's Qdrant row reads the files the session reads
  local bad="" out=""
  _case a7 >/dev/null
  mkdir -p "$C/p7"; ( cd "$C/p7" && git init -q . ) >/dev/null 2>&1
  printf '{}\n' > "$CFG/settings.json"
  _register "$CFG/.claude.json" qdrant
  out="$( cd "$C/p7" && env PATH="$RUN_PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" bash "$FW/scripts/verify-install.sh" --check-only </dev/null 2>&1 )"
  printf '%s\n' "$out" | grep -q '\[OK\] Qdrant MCP configured' || bad="$bad [registered in \$CLAUDE_CONFIG_DIR/.claude.json, not seen]"
  rm -f "$CFG/.claude.json"; _register "$H/.claude.json" qdrant
  out="$( cd "$C/p7" && env PATH="$RUN_PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" bash "$FW/scripts/verify-install.sh" --check-only </dev/null 2>&1 )"
  printf '%s\n' "$out" | grep -q 'Qdrant MCP not configured' || bad="$bad [registered only in ~/.claude.json, reported configured]"
  [ -z "$bad" ] && pass "A7 verify-install.sh's Qdrant row reads \$CLAUDE_CONFIG_DIR, not ~/.claude.json — the same files as its Context7 row" || fail_ "A7" "$bad"
}

a8() {   # the Stop-hook reminder reads the same files
  local bad="" out=""
  _case a8 >/dev/null
  mkdir -p "$C/p8"
  _register "$CFG/.claude.json" qdrant
  out="$( cd "$C/p8" && env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash "$FW/scripts/session-end-qdrant-reminder.sh" </dev/null 2>&1 )"
  printf '%s' "$out" | grep -q 'QDRANT REMINDER' || bad="$bad [registered in \$CLAUDE_CONFIG_DIR, no reminder]"
  rm -f "$CFG/.claude.json"; _register "$H/.claude.json" qdrant
  out="$( cd "$C/p8" && env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash "$FW/scripts/session-end-qdrant-reminder.sh" </dev/null 2>&1 )"
  printf '%s' "$out" | grep -q 'QDRANT REMINDER' && bad="$bad [registered only in ~/.claude.json, reminded anyway]"
  [ -z "$bad" ] && pass "A8 the session-end Qdrant reminder reads \$CLAUDE_CONFIG_DIR, not ~/.claude.json" || fail_ "A8" "$bad"
}

# ── S — the step on its own ─────────────────────────────────────────────────
s1() {   # nothing missing: no question, nothing run
  _case s1 >/dev/null
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  : > "$ST/qdrant-up"; : > "$ST/docker-up"
  _step "set it up now\n"
  if [ "$STEP_RC" = 0 ] && ! grep -q 'Set them up now' "$C/out" && ! _calls_ran \
     && [ "$STEP_RESULT" = "Qdrant: registered and answering before adoption, Claude Code starts it; Context7: registered before adoption, Claude Code starts it" ]; then
    pass "S1 both registered and answering: no question, nothing run"
  else fail_ "S1" "[asked, or ran, with nothing missing] rc=$STEP_RC result='$STEP_RESULT' asked=$(grep -c 'Set them up now' "$C/out")"; fi
}

s2() {   # set it up now
  local bad="" lq="" l1="" c=""
  _case s2 >/dev/null
  : > "$ST/docker-up"
  _step "set it up now\n"
  [ "$STEP_RC" = 0 ] || bad="$bad [rc $STEP_RC]"
  lq="$(_line_of "$C/out" 'Set them up now?')"
  for c in "$C7ADD" "$QRUN" "$QADD"; do
    l1="$(grep -nxF -- "     $c" "$C/out" | head -1 | cut -d: -f1)"
    { [ -n "$l1" ] && [ -n "$lq" ] && [ "$l1" -lt "$lq" ]; } || bad="$bad [not shown before the question: $c]"
    grep -qF -- "$(_cmd_line "${c%% *}" "${c#* }")" "$ST/calls.log" || bad="$bad [not run as shown: $c]"
  done
  grep -E '\[mcp\] \[add\]|docker \[run\]' "$ST/calls.log" | grep -qF "cwd=$P" && bad="$bad [a command ran with the adoptee as its cwd]"
  grep -E '\[mcp\] \[add\]|docker \[run\]' "$ST/calls.log" | grep -vqF "cwd=$C/w" && bad="$bad [a command did not run from the work dir]"
  jq -e '.mcpServers.qdrant.env.QDRANT_URL == "http://localhost:6333" and .mcpServers.context7.command == "npx"' "$CFG/.claude.json" >/dev/null 2>&1 \
    || bad="$bad [the registrations are not in \$CLAUDE_CONFIG_DIR/.claude.json]"
  [ -e "$H/.claude.json" ] && bad="$bad [something wrote ~/.claude.json]"
  [ "$STEP_RESULT" = "Qdrant: set up by adoption, registered and answering, Claude Code starts it; Context7: set up by adoption, registered, Claude Code starts it" ] || bad="$bad [result '$STEP_RESULT']"
  [ -z "$bad" ] && pass "S2 set it up now: the three commands shown before the question, run exactly as shown from the work dir, registered in the session's config, and read back by the receipt" || fail_ "S2" "$bad"
}

s3() {   # registered but silent + skip
  local bad=""
  _case s3 >/dev/null
  _register "$CFG/.claude.json" qdrant
  : > "$ST/docker-up"; : > "$ST/qdrant-exists"
  _step "skip it\n"
  [ "$(_plan 2)" = "     $C7ADD|     $QSTART|" ] || bad="$bad [plan '$(_plan 2)' — the container exists, so 'docker start qdrant']"
  _calls_ran && bad="$bad [something ran]"
  grep -q 'EVERY file edit is BLOCKED until qdrant-find succeeds' "$C/out" || bad="$bad [the note does not say every edit is blocked]"
  [ "$STEP_RESULT" = "Qdrant: registered, NOT answering (skipped), Claude Code starts it; Context7: NOT registered (skipped)" ] || bad="$bad [result '$STEP_RESULT']"
  [ -z "$bad" ] && pass "S3 registered but not answering + skip: the plan starts the existing container, and the note says every file edit is blocked" || fail_ "S3" "$bad"
}

s4() {   # unregistered, a database already answering + skip
  local bad=""
  _case s4 >/dev/null
  : > "$ST/docker-up"; : > "$ST/qdrant-up"; : > "$ST/qdrant-exists"
  _step "skip it\n"
  [ "$(_plan 2)" = "     $C7ADD|     $QADD|" ] || bad="$bad [plan '$(_plan 2)' — the database already answers, so only the two registrations]"
  grep -q "framework's check for it is off while it is not registered" "$C/out" || bad="$bad [the note does not say the check is off]"
  grep -q 'EVERY file edit is BLOCKED' "$C/out" && bad="$bad [a block claimed for servers registered nowhere]"
  [ -z "$bad" ] && pass "S4 not registered + skip: only the registrations are offered (the database already answers), and the note says the check is off — not that edits are blocked" || fail_ "S4" "$bad"
}

s5() {   # a blank answer is skip
  _case s5 >/dev/null
  : > "$ST/docker-up"
  _step "\n"
  if [ "$STEP_RC" = 0 ] && grep -q 'No answer — treated as skip it.' "$C/out" && ! _calls_ran; then
    pass "S5 a blank answer to the MCP question is 'skip it'"
  else fail_ "S5" "[not treated as skip] rc=$STEP_RC; $(grep -E 'REFUSED|BLOCKED' "$C/out" | head -1)"; fi
}

s6() {   # end of input is skip
  _case s6 >/dev/null
  : > "$ST/docker-up"
  _step ""
  if [ "$STEP_RC" = 0 ] && [ "$STEP_RESULT" = "Qdrant: NOT registered (skipped); Context7: NOT registered (skipped)" ] && ! _calls_ran; then
    pass "S6 end of input at the MCP question is 'skip it' (rc 0, nothing run) — it never refuses the way a mandatory question does"
  else fail_ "S6" "[end of input not treated as skip] rc=$STEP_RC result='$STEP_RESULT'"; fi
}

s7() {   # the commands fail: the receipt must not claim them
  local bad=""
  _case s7 >/dev/null
  : > "$ST/docker-up"; : > "$ST/claude-fails"
  _step "set it up now\n"
  grep -q 'That did not succeed: stub claude: refusing on purpose' "$C/out" || bad="$bad [the failure's own words were not shown]"
  [ "$STEP_RESULT" = "Qdrant: NOT registered after adoption tried; Context7: NOT registered after adoption tried" ] || bad="$bad [result claims a setup: '$STEP_RESULT']"
  [ -z "$bad" ] && pass "S7 the commands fail: the run shows why, and the result says NOT registered — the exit of a command is not a receipt" || fail_ "S7" "$bad"
}

s8() {   # an answer that is not offered
  _case s8 >/dev/null
  : > "$ST/docker-up"
  _step "maybe\n"
  if [ "$STEP_RC" = 1 ] && grep -q "\[REFUSED\] 'maybe' is not one of the answers offered for: setting up the MCP servers" "$C/out" && ! _calls_ran; then
    pass "S8 an answer that is not one of the two offered is refused, before anything runs"
  else fail_ "S8" "rc=$STEP_RC; $(grep -E 'REFUSED|BLOCKED' "$C/out" | head -1)"; fi
}

s9() {   # the database never answers: not registered against
  local bad=""
  _case s9 >/dev/null
  : > "$ST/docker-up"; : > "$ST/docker-run-noop"
  _step "set it up now\n"
  grep -qF -- "$(_cmd_line docker "${QRUN#* }")" "$ST/calls.log" || bad="$bad [docker run did not run]"
  grep -q '\[mcp\] \[add\] \[-s\] \[user\] \[qdrant\]' "$ST/calls.log" && bad="$bad [Qdrant was registered with no database behind it]"
  grep -q '\[mcp\] \[add\] \[context7\]' "$ST/calls.log" || bad="$bad [Context7, independent of it, was not set up]"
  [ -z "$bad" ] && pass "S9 a database that never answers is not registered against — that would make it required and block every edit — and Context7 still is" || fail_ "S9" "$bad"
}

s10() {   # the touched-disk markers follow the evidence, not the attempt
  local bad=""
  _case s10a >/dev/null
  : > "$ST/docker-up"
  _step "set it up now\n"
  { [ -e "$C/w/touched" ] || [ -e "$C/w/touched-unbounded" ]; } && bad="$bad [markers raised over a tree the commands did not change]"
  _case s10b >/dev/null
  : > "$ST/docker-up"
  _step "set it up now\n" STUB_TOUCH="$P/left-behind.txt"
  [ -e "$P/left-behind.txt" ] || bad="$bad [the fixture's stray write did not happen]"
  { [ -e "$C/w/touched" ] && [ -e "$C/w/touched-unbounded" ]; } || bad="$bad [markers not raised when a command changed the tree]"
  [ -z "$bad" ] && pass "S10 the touched-disk markers follow the fingerprint: not raised when the commands left the project unchanged, both raised when one wrote into it" || fail_ "S10" "$bad"
}

s11() {   # the test seam: nothing checked, nothing asked, nothing run — and said
  local bad="" n=""
  _case s11 >/dev/null
  : > "$ST/docker-up"
  _step "set it up now\n" SOIF_ADOPT_MCP=off
  [ "$STEP_RC" = 0 ] || bad="$bad [rc $STEP_RC]"
  grep -q 'Set them up now' "$C/out" && bad="$bad [asked with the seam off]"
  { [ -s "$ST/calls.log" ] || [ -s "$ST/curl.log" ]; } && bad="$bad [probed or ran something with the seam off: $(cat "$ST/calls.log" "$ST/curl.log" | head -2 | tr '\n' '|')]"
  n="$(grep -c 'MCP server check skipped (SOIF_ADOPT_MCP=off).' "$C/out")"
  [ "$n" = 1 ] || bad="$bad [the one-line notice appeared $n time(s)]"
  [ "$STEP_RESULT" = "not checked (SOIF_ADOPT_MCP=off)" ] || bad="$bad [result '$STEP_RESULT']"
  [ -z "$bad" ] && pass "S11 SOIF_ADOPT_MCP=off skips the whole step: one line says so, nothing is probed, asked or run, and the Record cell says not checked" || fail_ "S11" "$bad"
}

s12() {   # answer "1" by NUMBER — "skip it" is listed first, so nothing runs
  local bad=""
  _case s12 >/dev/null
  : > "$ST/docker-up"
  _step "1\n"
  grep -q '   1) skip it' "$C/out" || bad="$bad [the menu does not list 1) skip it]"
  _calls_ran && bad="$bad [answer 1 ran commands: $(grep -E 'mcp|docker .(run|start)' "$ST/calls.log" | head -2 | tr '\n' '|')]"
  [ "$STEP_RESULT" = "Qdrant: NOT registered (skipped); Context7: NOT registered (skipped)" ] || bad="$bad [result '$STEP_RESULT']"
  [ -z "$bad" ] && pass "S12 answering 1 by number means skip it (listed first): nothing runs" || fail_ "S12" "$bad"
}

s13() {   # answer "2" by NUMBER — set it up
  local bad=""
  _case s13 >/dev/null
  : > "$ST/docker-up"
  _step "2\n"
  grep -q '   2) set it up now' "$C/out" || bad="$bad [the menu does not list 2) set it up now]"
  grep -q '\[mcp\] \[add\] \[context7\]' "$ST/calls.log" || bad="$bad [answer 2 did not set up Context7]"
  grep -q '\[mcp\] \[add\] \[-s\] \[user\] \[qdrant\]' "$ST/calls.log" || bad="$bad [answer 2 did not register Qdrant]"
  [ -z "$bad" ] && pass "S13 answering 2 by number sets them up: the commands run" || fail_ "S13" "$bad"
}

s14() {   # no npx: Context7 is not offered, and what to install is said
  local bad=""
  _case s14 >/dev/null
  _register "$CFG/.claude.json" qdrant
  : > "$ST/docker-up"; : > "$ST/qdrant-up"
  _mkstubs "$C/stubs" yes no
  _mirror_without "$C/mirror" npx
  if PATH="$C/stubs:$C/mirror" command -v npx >/dev/null 2>&1; then
    fail_ "S14" "the isolated PATH still has npx — the fixture cannot measure its absence"; return
  fi
  RUN_PATH="$C/stubs:$C/mirror" _step "2\n"
  grep -q 'Set them up now' "$C/out" && bad="$bad [offered Context7 with no npx to launch it]"
  grep -q '\[mcp\] \[add\] \[context7\]' "$ST/calls.log" && bad="$bad [registered Context7 with no npx]"
  grep -q 'Adoption cannot set up Context7 here: npx is not on PATH, and the server runs through it (npx comes with Node.js' "$C/out" || bad="$bad [the reason and what to install are not said]"
  grep -qF -- "  $C7ADD" "$C/out" || bad="$bad [no command for later]"
  [ -z "$bad" ] && pass "S14 no npx: Context7 is not offered (registering it would require a server that cannot start), and the run says Node.js is what provides npx" || fail_ "S14" "$bad"
}

s15() {   # docker run fails: Qdrant must NOT be registered, and it is said
  local bad=""
  _case s15 >/dev/null
  : > "$ST/docker-up"; : > "$ST/docker-run-fails"
  _step "2\n"
  grep -qF -- "$(_cmd_line docker "${QRUN#* }")" "$ST/calls.log" || bad="$bad [docker run was not attempted]"
  grep -q '\[mcp\] \[add\] \[-s\] \[user\] \[qdrant\]' "$ST/calls.log" && bad="$bad [Qdrant was registered after its container failed to start]"
  grep -q 'So Qdrant will NOT be registered: its database did not start' "$C/out" || bad="$bad [the run does not say Qdrant was not registered]"
  grep -q '\[mcp\] \[add\] \[context7\]' "$ST/calls.log" || bad="$bad [Context7, independent of it, was not set up]"
  [ "$STEP_RESULT" = "Qdrant: NOT registered after adoption tried; Context7: set up by adoption, registered, Claude Code starts it" ] || bad="$bad [result '$STEP_RESULT']"
  [ -z "$bad" ] && pass "S15 a failed docker run: Qdrant is NOT registered (registered would mean required, and every edit blocked), the run says so, and Context7 is still set up" || fail_ "S15" "$bad"
}

s16() {   # registered, but Claude Code cannot start it — Claude Code's own check
  local bad=""
  _case s16 >/dev/null
  : > "$ST/docker-up"; printf 'qdrant\n' > "$ST/launch-fails"
  _step "2\n"
  grep -q '\[mcp\] \[get\] \[qdrant\]' "$ST/calls.log" || bad="$bad [Claude Code's own check was not asked]"
  grep -q 'BLOCKED UNTIL FIXED: Qdrant IS registered, but Claude Code could NOT start it (stub: qdrant cannot be started)' "$C/out" || bad="$bad [the block is not said with Claude Code's reason]"
  grep -qxF '       claude mcp remove qdrant -s user' "$C/out" || bad="$bad [Claude Code's own remove command is not printed]"
  grep -q 'Qdrant: Claude Code.s own check says it could NOT start it' "$C/out" || bad="$bad [the launch line is missing]"
  case "$STEP_RESULT" in *"Qdrant: set up by adoption, registered and answering, Claude Code could NOT start it;"*) : ;; *) bad="$bad [result '$STEP_RESULT']" ;; esac
  [ -z "$bad" ] && pass "S16 registered and answering but Claude Code cannot start it: said as a BLOCK, with Claude Code's own reason and its remove command, and recorded" || fail_ "S16" "$bad"
}

s17() {   # Context7 registered, but Claude Code cannot start it
  local bad=""
  _case s17 >/dev/null
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  : > "$ST/docker-up"; : > "$ST/qdrant-up"; printf 'context7\n' > "$ST/launch-fails"
  _step ""
  grep -q 'BLOCKED UNTIL FIXED: Context7 IS registered, but Claude Code could NOT start it (stub: context7 cannot be started)' "$C/out" || bad="$bad [the Context7 block is not said]"
  grep -q 'Every file edit in this project is blocked until it can.' "$C/out" || bad="$bad [the consequence is not said]"
  grep -qxF '       claude mcp remove context7 -s user' "$C/out" || bad="$bad [Claude Code's own remove command is not printed]"
  case "$STEP_RESULT" in *"Context7: registered before adoption, Claude Code could NOT start it"*) : ;; *) bad="$bad [result '$STEP_RESULT']" ;; esac
  [ -z "$bad" ] && pass "S17 Context7 registered but Claude Code cannot start it: said as a BLOCK, with its reason and Claude Code's own remove command, and recorded" || fail_ "S17" "$bad"
}

s18() {   # the launch check cannot answer: a hang past the bound, and no status
  local bad=""
  _case s18 >/dev/null
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  : > "$ST/docker-up"; : > "$ST/qdrant-up"
  printf 'qdrant\n' > "$ST/launch-hang"; printf 'context7\n' > "$ST/launch-silent"
  _step "" SOIF_ADOPT_MCP_LAUNCH_SECS=1
  grep -q 'Whether Claude Code can start Qdrant could not be checked (claude mcp get qdrant did not answer within 1s)' "$C/out" || bad="$bad [the Qdrant unchecked note is not said]"
  grep -q 'file edit here is blocked until it can. Check it with: claude mcp get qdrant' "$C/out" || bad="$bad [the Qdrant consequence and check command are not said]"
  grep -q 'Whether Claude Code can start Context7 could not be checked (claude mcp get context7 gave no status' "$C/out" || bad="$bad [the Context7 unchecked note is not said]"
  grep -q 'Check it with: claude mcp get context7' "$C/out" || bad="$bad [the Context7 check command is not said]"
  grep -q 'BLOCKED UNTIL FIXED' "$C/out" && bad="$bad [a check that could not answer was read as a failure]"
  [ "$STEP_RESULT" = "Qdrant: registered and answering before adoption, whether Claude Code can start it not checked; Context7: registered before adoption, whether Claude Code can start it not checked" ] || bad="$bad [result '$STEP_RESULT']"
  [ -z "$bad" ] && pass "S18 a launch check that hangs past its bound or prints no status is said as 'could not be checked', with the command to check it — never read as starts or fails" || fail_ "S18" "$bad"
}

# ── S19-S29: an EXISTING qdrant container — how it is published, and no command ──
# _open_case TAG HOSTIP MOUNT — a stopped container with those bindings and that
# mount, Docker up, nothing registered; the step is answered "skip it". The
# mount is the container's SHAPE (the stub's inspect hands it to whatever asks);
# the step itself reads only the bindings and the environment.
_open_case() {   # TAG HOSTIP MOUNT-LINE... (type|source|destination; none = no line)
  _case "$1" >/dev/null
  : > "$ST/docker-up"; : > "$ST/qdrant-exists"
  [ "$2" = loopback ] || printf '%s' "$2" > "$ST/qdrant-open"
  shift 2
  : > "$ST/qdrant-mount"
  while [ $# -gt 0 ]; do [ "$1" = none ] || printf '%s\n' "$1" >> "$ST/qdrant-mount"; shift; done
}
_open_note_before_q() {   # the note is printed, and before the question if there is one
  local ln="" lq=""
  ln="$(_line_of "$C/out" 'Your existing qdrant container')"
  [ -n "$ln" ] || return 1
  lq="$(_line_of "$C/out" 'Set them up now?')"
  [ -z "$lq" ] || [ "$ln" -lt "$lq" ]
}

s19() {   # unregistered + stopped + no host address + the host's real volume
  local bad=""
  _open_case s19 "" "volume|qdrant_storage|/qdrant/storage"
  _step "skip it\n"
  grep -q 'docker \[inspect\]' "$ST/calls.log" || bad="$bad [the container was not inspected]"
  _open_note_before_q || bad="$bad [the open-bindings note is not said before the question]"
  grep -q 'publishes on every network interface unless your Docker daemon sets a default' "$C/out" || bad="$bad [an empty HostIp is not worded as the daemon default]"
  grep -q 'can reach even ports published on 127.0.0.1 — moby/moby#45610' "$C/out" || bad="$bad [the pre-28.0.0 caveat is missing]"
  grep -q 'no API key is set in its environment (a key in a Qdrant config file would not show here)' "$C/out" || bad="$bad [the absence of an API key is not worded as read from its environment only]"
  grep -qxF "     $QSTART" "$C/out" || bad="$bad [docker start is no longer the offered action]"
  grep -q 'your existing qdrant container is published on every network interface' "$C/out" || bad="$bad [the later docker start hint does not carry the note]"
  grep -q 'this machine only' "$C/out" && bad="$bad [the loopback promise is still worded as 'this machine only']"
  grep -qE 'docker \[(rm|stop|rename)\]' "$ST/calls.log" && bad="$bad [the container was recreated automatically]"
  _calls_ran && bad="$bad [something ran on skip]"
  [ -z "$bad" ] && pass "S19 an existing container naming no host address: said (as the daemon default, with the pre-28 caveat) before the question, docker start still offered, the later hint carries it, nothing recreated" || fail_ "S19" "$bad"
}

s19b() {   # REGISTERED + stopped + open: the unreachable path
  local bad=""
  _open_case s19b "" "volume|qdrant_storage|/qdrant/storage"
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  _step "skip it\n"
  _open_note_before_q || bad="$bad [the note is not said on the unreachable path]"
  grep -qxF "     $QSTART" "$C/out" || bad="$bad [docker start is not offered]"
  grep -q 'your existing qdrant container is published on every network interface' "$C/out" || bad="$bad [the unreachable arm's docker start hint does not carry the note]"
  [ -z "$bad" ] && pass "S19b registered + stopped + open: the note before the question and beside the unreachable arm's docker start hint" || fail_ "S19b" "$bad"
}

s19c() {   # unregistered, the database already ANSWERING from an open container
  local bad=""
  _open_case s19c "" "volume|qdrant_storage|/qdrant/storage"; : > "$ST/qdrant-up"
  _step "skip it\n"
  _open_note_before_q || bad="$bad [the note is not said when the database already answers]"
  [ -z "$bad" ] && pass "S19c the database already answering from an open container: the note is said" || fail_ "S19c" "$bad"
}

s19d() {   # THIS HOST'S STATE: both registered, answering, from an open container — nothing asked
  local bad=""
  _open_case s19d "" "volume|qdrant_storage|/qdrant/storage"; : > "$ST/qdrant-up"
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  _step ""
  grep -q 'Set them up now' "$C/out" && bad="$bad [asked with nothing missing]"
  _open_note_before_q || bad="$bad [the note is not said when everything is registered and answering]"
  [ -z "$bad" ] && pass "S19d both registered and answering from an open container (this host's state): no question, and the note is still said" || fail_ "S19d" "$bad"
}

s19e() {   # an explicit 0.0.0.0
  _open_case s19e "0.0.0.0" "volume|qdrant_storage|/qdrant/storage"
  _step "skip it\n"
  if _open_note_before_q && grep -q '(its bindings name 0.0.0.0)' "$C/out"; then
    pass "S19e HostIp 0.0.0.0: reported as published on every network interface"
  else fail_ "S19e" "[HostIp 0.0.0.0 not reported as every interface]"; fi
}

s19f() {   # an explicit ::
  _open_case s19f "::" "volume|qdrant_storage|/qdrant/storage"
  _step "skip it\n"
  if _open_note_before_q && grep -q 'every IPv6 address of this' "$C/out" && ! grep -q 'every network interface' "$C/out"; then
    pass "S19f HostIp :: reported as every IPv6 address — not as every interface"
  else fail_ "S19f" "[HostIp :: not reported as every interface]"; fi
}

s19g() {   # Docker DOWN: the bindings cannot be read, and every docker start hint says so
  local bad=""
  _case s19g >/dev/null
  _register "$CFG/.claude.json" qdrant
  _step "skip it\n"
  grep -qxF "     $QSTART" "$C/out" || bad="$bad [no docker start hint to check]"
  grep -q 'how an existing qdrant container is published could not be read — Docker is not running here' "$C/out" || bad="$bad [the docker start hint does not say the bindings could not be read]"
  [ -z "$bad" ] && pass "S19g Docker not running: the docker start hint says the container's bindings could not be read, and how to check them" || fail_ "S19g" "$bad"
}

s20() {   # a loopback-bound existing container: no note
  local bad=""
  _open_case s20 loopback "volume|qdrant_storage|/qdrant/storage"
  _step "skip it\n"
  grep -q 'docker \[inspect\]' "$ST/calls.log" || bad="$bad [the container's bindings were not read]"
  grep -q 'Your existing qdrant container' "$C/out" && bad="$bad [a loopback-bound container was reported as open]"
  # ::1 IS LOOPBACK TOO: the any-other-address arm (round 14) must not flag it.
  _open_case s20b loopback "volume|qdrant_storage|/qdrant/storage"
  printf '%s' '{"6333/tcp":[{"HostIp":"::1","HostPort":"6333"}],"6334/tcp":[{"HostIp":"127.0.0.1","HostPort":"6334"}]}' > "$ST/qdrant-bindings"
  _step "skip it\n"
  grep -q 'Your existing qdrant container' "$C/out" && bad="$bad [a ::1 binding was reported as open]"
  [ -z "$bad" ] && pass "S20 an existing loopback-bound container (127.0.0.1, and ::1 beside it): its bindings are read and no open-interfaces note is printed" || fail_ "S20" "$bad"
}

# _block OUT — the WHOLE printed note, from its first line ("Your existing
# qdrant container …") to its last (the pointer, ending "docs/adoption.md."),
# the first time it is printed.
_block() {
  awk '/^   Your existing qdrant container/ { on = 1 }
       on { print }
       on && /docs\/adoption\.md\.$/ { exit }' "$1"
}
# _block_diff EXPECTED-FILE OUT — empty when the printed note matches EXACTLY;
# otherwise names the FIRST differing line, both sides (<none> past an end), so
# a mutant's kill says which line it broke.
_block_diff() {
  _block "$2" > "$1.got"
  cmp -s "$1" "$1.got" && return 0
  awk 'NR == FNR { e[FNR] = $0; ne = FNR; next }
       { g[FNR] = $0; ng = FNR }
       END { n = (ne > ng) ? ne : ng
             for (i = 1; i <= n; i++) {
               x = (i <= ne) ? e[i] : "<none>"; y = (i <= ng) ? g[i] : "<none>"
               if (x != y) { printf "the printed note differs at line %d: expected \"%s\", printed \"%s\"", i, x, y; exit } } }' "$1" "$1.got"
}
# _note_expected — the WHOLE note for a container whose ports name no host
# address and whose environment sets no API key, WHATEVER its storage.
_note_expected() {
  cat <<EOF
   Your existing qdrant container's ports name no host address, which Docker
   publishes on every network interface unless your Docker daemon sets a default
   bind address: while it runs, other machines on your network may be able to reach
   it — and no API key is set in its environment (a key in a Qdrant config file would not show here).
   Starting it keeps that. To publish it on 127.0.0.1 (loopback) instead, it has to
   be recreated, and removing a container can delete its data.
   (On Docker Engine older than 28.0.0 on Linux, hosts on the same network segment
   can reach even ports published on 127.0.0.1 — moby/moby#45610.)
   Adoption changed nothing about this container, and prints no commands to recreate
   it. How to do that without losing its data:
   "Recreating an exposed Qdrant container" in $FW/docs/adoption.md.
EOF
}

# s29 — NO COMMAND, FOR ANY CONTAINER (round 13). Rounds 4-12 printed a recreate
# for the shapes a growing allow-list confirmed; every round's review on real
# Docker found another setting it lost or broke, so the note now prints the
# finding and a pointer to the written procedure (S28), and nothing to run.
# Held over a SET of container shapes, each handed to the step by the stub's
# inspect whatever the step asks for: the note carries the pointer and the
# changed-nothing sentence, and has NO line a reader could paste — no line
# indented past the note's own margin, and no `docker `, `&&` or `$(` in it.
# For every shape with no API key the note is also compared WHOLE against one
# expected text: the storage changes nothing in it.
_note_is_prose() {   # LABEL — on $C/out
  local label="$1"
  _block "$C/out" > "$C/note"
  [ -s "$C/note" ] || { printf ' [%s: no note was printed]' "$label"; return 0; }
  grep -qF '"Recreating an exposed Qdrant container" in ' "$C/note" || printf ' [%s: the pointer to the written procedure is missing]' "$label"
  grep -qF 'Adoption changed nothing about this container' "$C/note" || printf ' [%s: it is not said that adoption changed nothing]' "$label"
  grep -qE '^    ' "$C/note" && printf ' [%s: the note prints an indented, paste-shaped line: %s]' "$label" "$(grep -E '^    ' "$C/note" | head -1 | cut -c1-100)"
  grep -qE 'docker |&&|\$\(' "$C/note" && printf ' [%s: the note prints a command: %s]' "$label" "$(grep -E 'docker |&&|\$\(' "$C/note" | head -1 | cut -c1-100)"
  return 0
}
_note_is_expected() {   # LABEL — on $C/out
  local miss=""
  _note_expected > "$C/expect"
  miss="$(_block_diff "$C/expect" "$C/out")"
  [ -z "$miss" ] || printf ' [%s: %s]' "$1" "$miss"
  return 0
}
s29() {
  local bad="" key='PATH=/usr/local/bin\nQDRANT__SERVICE__API_KEY=s3cr3t-value\n'
  _open_case s29a "" "volume|qdrant_storage|/qdrant/storage"; _step "skip it\n"
  bad="$bad$(_note_is_prose 'a vanilla volume')$(_note_is_expected 'a vanilla volume')"
  _open_case s29b "" "bind|/srv/qdrant data|/qdrant/storage"; _step "skip it\n"
  bad="$bad$(_note_is_prose 'a host folder')$(_note_is_expected 'a host folder')"
  _open_case s29c "" none; : > "$ST/qdrant-tmpfs"; _step "skip it\n"
  bad="$bad$(_note_is_prose 'a --tmpfs')$(_note_is_expected 'a --tmpfs')"
  _open_case s29d "" none; _step "skip it\n"
  bad="$bad$(_note_is_prose 'nothing mounted')$(_note_is_expected 'nothing mounted')"
  _open_case s29e "" none; : > "$ST/qdrant-autoremove"; : > "$ST/qdrant-up"; _step "skip it\n"
  bad="$bad$(_note_is_prose '--rm, running')$(_note_is_expected '--rm, running')"
  _open_case s29f "" "volume|qdrant_storage|/qdrant/storage"; printf 'qdrant/qdrant:v1.12.4' > "$ST/qdrant-image"; _step "skip it\n"
  bad="$bad$(_note_is_prose 'a pinned image')$(_note_is_expected 'a pinned image')"
  _open_case s29g "" "volume|qdrant_storage|/qdrant/storage"; printf "$key" > "$ST/qdrant-env"; _step "skip it\n"
  bad="$bad$(_note_is_prose 'an API key')"
  grep -qF 's3cr3t-value' "$C/out" && bad="$bad [an API key: its VALUE was printed]"
  _open_case s29h "0.0.0.0" "volume|qdrant_storage|/qdrant/storage"; _step "skip it\n"
  bad="$bad$(_note_is_prose 'bound to 0.0.0.0')"
  _open_case s29i "::" "volume|qdrant_storage|/qdrant/storage"; _step "skip it\n"
  bad="$bad$(_note_is_prose 'bound to ::')"
  [ -z "$bad" ] && pass "S29 no command for ANY container — a volume, a host folder, a --tmpfs, nothing mounted, --rm, a pinned image, an API key, 0.0.0.0, :: — the note points to the written procedure, says adoption changed nothing, and has no paste-shaped line and no docker, && or \$( in it; with no API key it is the same text whatever the storage" || fail_ "S29" "$bad"
}

s25() {   # docker inspect fails for an existing container: fail closed, said
  local bad=""
  _open_case s25 "" "volume|qdrant_storage|/qdrant/storage"; : > "$ST/inspect-fails"
  _step "skip it\n"
  grep -q 'how an existing qdrant container is published could not be read — docker inspect could not read it' "$C/out" || bad="$bad [the could-not-be-read hint is missing]"
  grep -q 'Your existing qdrant container' "$C/out" && bad="$bad [a binding was claimed that was never read]"
  [ -z "$bad" ] && pass "S25 docker inspect fails: the bindings are 'could not be read' beside docker start — never treated as loopback" || fail_ "S25" "$bad"
}

s27() {   # an API key IS set: said, never printed, and its absence not claimed
  local bad=""
  _open_case s27 "" "volume|qdrant_storage|/qdrant/storage"
  printf 'PATH=/usr/local/bin\nQDRANT__SERVICE__API_KEY=s3cr3t-value\n' > "$ST/qdrant-env"
  _step "skip it\n"
  grep -q 'it has an API key set (QDRANT__SERVICE__API_KEY)' "$C/out" || bad="$bad [the API key is not recognised]"
  grep -q 'no API key is set' "$C/out" && bad="$bad [no key claimed for a container that has one]"
  grep -q 's3cr3t-value' "$C/out" && bad="$bad [the key's value was printed]"
  [ -z "$bad" ] && pass "S27 a container with QDRANT__SERVICE__API_KEY: the key is recognised from its env, its value never printed" || fail_ "S27" "$bad"
}

# ── S30-S37 (round 14): mixed bindings, -P, host network, other addresses, the
# key's spelling, and an answer that does not parse. The stub's
# `qdrant-bindings` knob hands the step a WHOLE bindings line, so a set where
# one port is open and the other on loopback can be tested — the uniform
# bindings every earlier case used let `any` → `all` survive on two arms.
_bind_case() {   # TAG BINDINGS-JSON — an open-case container with exactly these bindings
  _open_case "$1" loopback "volume|qdrant_storage|/qdrant/storage"
  printf '%s' "$2" > "$ST/qdrant-bindings"
}
s30() {   # port 6333 published on 0.0.0.0, port 6334 on 127.0.0.1
  local bad=""
  _bind_case s30 '{"6333/tcp":[{"HostIp":"0.0.0.0","HostPort":"6333"}],"6334/tcp":[{"HostIp":"127.0.0.1","HostPort":"6334"}]}'
  _step "skip it\n"
  _open_note_before_q || bad="$bad [a 0.0.0.0 binding beside a loopback one is not reported at all]"
  grep -q '(its bindings name 0.0.0.0)' "$C/out" || bad="$bad [a 0.0.0.0 binding beside a loopback one is not reported as every interface]"
  [ -z "$bad" ] && pass "S30 mixed bindings (6333 on 0.0.0.0, 6334 on 127.0.0.1): reported as every interface — ONE open port is enough" || fail_ "S30" "$bad"
}
s31() {   # an empty HostIp beside a loopback one
  local bad=""
  _bind_case s31 '{"6333/tcp":[{"HostIp":"","HostPort":"6333"}],"6334/tcp":[{"HostIp":"127.0.0.1","HostPort":"6334"}]}'
  _step "skip it\n"
  _open_note_before_q || bad="$bad [an empty HostIp beside a loopback one is not reported at all]"
  grep -q 'publishes on every network interface unless your Docker daemon sets a default' "$C/out" || bad="$bad [an empty HostIp beside a loopback one is not reported as the daemon default]"
  [ -z "$bad" ] && pass "S31 mixed bindings (no host address on one port, 127.0.0.1 on the other): reported as the daemon default" || fail_ "S31" "$bad"
}
s32() {   # QDRANT__SERVICE__API_KEY= with NO value is not read as a key
  local bad=""
  _open_case s32 "" "volume|qdrant_storage|/qdrant/storage"
  printf 'PATH=/usr/local/bin\nQDRANT__SERVICE__API_KEY=\n' > "$ST/qdrant-env"
  _step "skip it\n"
  grep -q 'it has an API key set' "$C/out" && bad="$bad [an EMPTY API key was read as a key]"
  grep -q 'no API key is set in its environment' "$C/out" || bad="$bad [an empty API key is not worded as no key]"
  [ -z "$bad" ] && pass "S32 QDRANT__SERVICE__API_KEY= with no value: not read as a key, so the note warns rather than reassures" || fail_ "S32" "$bad"
}
s33() {   # bindings that do not parse: said to be unreadable, NEVER loopback
  local bad=""
  _bind_case s33 '{"6333/tcp":[{"HostIp":"0.0.0.0"'
  _step "skip it\n"
  grep -qxF "     $QSTART" "$C/out" || bad="$bad [no docker start hint to check]"
  grep -q "how an existing qdrant container is published could not be read — docker inspect's answer about its ports could not be parsed" "$C/out" || bad="$bad [unparseable bindings are not said to be unreadable]"
  grep -q 'Your existing qdrant container' "$C/out" && bad="$bad [a binding was claimed from an answer that did not parse]"
  [ -z "$bad" ] && pass "S33 bindings that do not parse: 'could not be read' beside docker start — never read as loopback" || fail_ "S33" "$bad"
}
# S33b / S33c (round 15, R-BL311-8): `# BL-311-MCP-BIND-PARSE` checks all THREE
# lines it reads, but S33 garbles only the bindings — so dropping the
# PublishAllPorts type check (K5), the NetworkMode type check (K6) or the count
# (`length == 3` → `length >= 1`, K15) survived the whole suite. Every shape
# here has loopback bindings, so the parse check is the ONLY thing between it
# and "loopback". A value of the wrong TYPE is valid JSON and slips past a
# parse that only asks for JSON; TWO values on one line slip past a count.
_unread_said() {   # LABEL — on $C/out: the could-not-be-read outcome, and no note
  grep -qxF "     $QSTART" "$C/out" || printf ' [%s: no docker start hint to check]' "$1"
  grep -q "how an existing qdrant container is published could not be read — docker inspect's answer about its ports could not be parsed" "$C/out" || printf ' [%s: not said to be unreadable]' "$1"
  grep -q 'Your existing qdrant container' "$C/out" && printf ' [%s: a binding was claimed from an answer that did not parse]' "$1"
  return 0
}
S33_LOOPBACK='{"6333/tcp":[{"HostIp":"127.0.0.1","HostPort":"6333"}],"6334/tcp":[{"HostIp":"127.0.0.1","HostPort":"6334"}]}'
s33b() {   # a PublishAllPorts that is not a boolean
  local bad=""
  _bind_case s33b-null "$S33_LOOPBACK"; printf 'null' > "$ST/qdrant-publish-all-raw"; _step "skip it\n"
  bad="$bad$(_unread_said '(null) a PublishAllPorts of null')"
  _bind_case s33b-str "$S33_LOOPBACK"; printf '"true"' > "$ST/qdrant-publish-all-raw"; _step "skip it\n"
  bad="$bad$(_unread_said '(string) a PublishAllPorts of "true"')"
  [ -z "$bad" ] && pass "S33b a PublishAllPorts that is not a boolean (null, the string \"true\"), bindings on loopback: 'could not be read' beside docker start — never read as loopback" || fail_ "S33b" "$bad"
}
s33c() {   # a NetworkMode that is not a string, or two values on its line
  local bad=""
  _bind_case s33c-null "$S33_LOOPBACK"; printf 'null' > "$ST/qdrant-network-raw"; _step "skip it\n"
  bad="$bad$(_unread_said '(null) a NetworkMode of null')"
  _bind_case s33c-two "$S33_LOOPBACK"; printf '"bridge" "host"' > "$ST/qdrant-network-raw"; _step "skip it\n"
  bad="$bad$(_unread_said '(two values) a NetworkMode line with two values')"
  [ -z "$bad" ] && pass "S33c a NetworkMode that is not a string (null), or a line with two values on it, bindings on loopback: 'could not be read' beside docker start — never read as loopback or as the host network" || fail_ "S33c" "$bad"
}
s34() {   # -P: PublishAllPorts, nothing in PortBindings
  local bad=""
  _bind_case s34 '{}'; : > "$ST/qdrant-publish-all"
  _step "skip it\n"
  _open_note_before_q || bad="$bad [-P is not reported at all]"
  grep -q 'was created with -P (--publish-all), which publishes' "$C/out" || bad="$bad [-P is not reported as publishing on every interface]"
  grep -q 'your existing qdrant container is published on every network interface unless' "$C/out" || bad="$bad [the docker start hint does not carry the -P note]"
  bad="$bad$(_note_is_prose '-P')"
  [ -z "$bad" ] && pass "S34 a container created with -P: reported as random ports on every interface, the hint carries it, no command printed" || fail_ "S34" "$bad"
}
s35() {   # --network host: every interface of the host, whatever is published
  local bad=""
  _bind_case s35 '{}'; printf 'host' > "$ST/qdrant-network"
  _step "skip it\n"
  _open_note_before_q || bad="$bad [the host network is not reported at all]"
  grep -q "runs on the host's network (--network host)" "$C/out" || bad="$bad [the host network is not reported as every interface of the host]"
  grep -q 'every network interface of this machine' "$C/out" || bad="$bad [the host network note does not say every interface of this machine]"
  grep -q 'your existing qdrant container is published beyond this machine' "$C/out" || bad="$bad [the docker start hint does not carry the host-network note]"
  bad="$bad$(_note_is_prose '--network host')"
  [ -z "$bad" ] && pass "S35 a container on the host's network: reported as every interface of this machine, the hint carries it, no command printed" || fail_ "S35" "$bad"
}
s36() {   # a LAN address
  local bad=""
  _bind_case s36 '{"6333/tcp":[{"HostIp":"192.168.1.5","HostPort":"6333"}],"6334/tcp":[{"HostIp":"127.0.0.1","HostPort":"6334"}]}'
  _step "skip it\n"
  _open_note_before_q || bad="$bad [a LAN address is not reported at all]"
  grep -q 'loopback (127.0.0.1 or ::1) — its bindings name 192.168.1.5:' "$C/out" || bad="$bad [a LAN address is not reported as an address other than loopback, by name]"
  grep -q 'your existing qdrant container is published beyond this machine' "$C/out" || bad="$bad [the docker start hint does not carry the LAN-address note]"
  bad="$bad$(_note_is_prose 'a LAN address')"
  [ -z "$bad" ] && pass "S36 a binding on a LAN address (192.168.1.5): reported by name as other than loopback, the hint carries it, no command printed" || fail_ "S36" "$bad"
}
s37() {   # the key in LOWERCASE — Qdrant honours it (measured, round 14)
  local bad=""
  _open_case s37 "" "volume|qdrant_storage|/qdrant/storage"
  printf 'PATH=/usr/local/bin\nqdrant__service__api_key=l0wer-s3cret\n' > "$ST/qdrant-env"
  _step "skip it\n"
  grep -q 'it has an API key set (QDRANT__SERVICE__API_KEY)' "$C/out" || bad="$bad [a lowercase API key is not recognised]"
  grep -q 'no API key is set' "$C/out" && bad="$bad [no key claimed for a container that has a lowercase one]"
  grep -q 'l0wer-s3cret' "$C/out" && bad="$bad [the key's value was printed]"
  [ -z "$bad" ] && pass "S37 qdrant__service__api_key in lowercase: recognised as a key, its value never printed" || fail_ "S37" "$bad"
}

# ── E — whole adoptions ─────────────────────────────────────────────────────
HAVE_GITLEAKS=0; command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1

e1() {   # both present; the Record row; the restart sentence before NEXT
  local bad="" rec="" l1="" l2=""
  _case e1 >/dev/null
  _register "$CFG/.claude.json" qdrant; _register "$CFG/.claude.json" context7
  : > "$ST/qdrant-up"; : > "$ST/docker-up"
  _adopt "$(_n1 12)"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$C/out" | head -1)]"
  grep -q 'Set them up now' "$C/out" && bad="$bad [asked anyway]"
  rec="$(_record)"
  printf '%s' "$rec" | grep -q 'Qdrant: registered and answering before adoption, Claude Code starts it; Context7: registered before adoption, Claude Code starts it' || bad="$bad [record row: '$rec']"
  [ -z "$bad" ] && pass "E1 a whole adoption with both present: no question, and the Adoption Record carries the MCP row" || fail_ "E1" "$bad"
  l1="$(_line_of "$C/out" 'FIRST: if a Claude Code session is open in this project, close it and start a new')"
  l2="$(_line_of "$C/out" 'NEXT: run this, and paste what it prints into Claude Code.')"
  if [ -n "$l1" ] && [ -n "$l2" ] && [ "$l1" -lt "$l2" ] && grep -q 'open cannot save a file here.' "$C/out"; then
    pass "E1b Act 2 tells the operator to close any open Claude Code session and start a new one, BEFORE 'NEXT'"
  else fail_ "E1b" "restart line at '${l1:-absent}', NEXT at '${l2:-absent}'"; fi
}

e2() {   # set it up now, whole adoption
  local bad="" rec=""
  _case e2 >/dev/null
  : > "$ST/docker-up"
  _adopt "1\nstandard\nset it up now\n$(_n1 12)"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$C/out" | head -1)]"
  grep -q 'STDIN-HAD-DATA' "$ST/calls.log" && bad="$bad [a command read the operator's answers]"
  grep -E '\[mcp\] \[add\]|docker \[run\]' "$ST/calls.log" | grep -q 'cwd=.*adopt-work\.' || bad="$bad [the commands did not run from the run's work dir]"
  rec="$(_record)"
  printf '%s' "$rec" | grep -q 'Qdrant: set up by adoption, registered and answering, Claude Code starts it; Context7: set up by adoption, registered, Claude Code starts it' || bad="$bad [record row: '$rec']"
  [ -f "$P/.claude/settings.local.json" ] || bad="$bad [the project collection was not declared once Qdrant was registered]"
  [ -z "$bad" ] && pass "E2 set it up now inside a whole adoption: no command read the operator's answers, the Record says set up, and the project collection is declared" || fail_ "E2" "$bad"
}

e3() {   # skip, whole adoption
  local bad="" rec=""
  _case e3 >/dev/null
  : > "$ST/docker-up"
  _adopt "1\nstandard\nskip it\n$(_n1 12)"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC]"
  _calls_ran && bad="$bad [something ran]"
  rec="$(_record)"
  printf '%s' "$rec" | grep -q 'Qdrant: NOT registered (skipped); Context7: NOT registered (skipped)' || bad="$bad [record row: '$rec']"
  grep -q 'Qdrant or Context7 is NOT set up' "$C/out" || bad="$bad [the closing does not point back at it]"
  [ -z "$bad" ] && pass "E3 skip inside a whole adoption: nothing run, the Record row says skipped, and the closing points back at the note" || fail_ "E3" "$bad"
}

e4() {   # no claude command: the CI shape
  local bad="" rec=""
  _case e4 >/dev/null
  _mkstubs "$C/stubs" no
  _mirror_without "$C/mirror" claude
  if PATH="$C/stubs:$C/mirror" command -v claude >/dev/null 2>&1; then
    fail_ "E4" "the isolated PATH still has a claude command — the fixture cannot measure its absence"; return
  fi
  RUN_PATH="$C/stubs:$C/mirror" _adopt "$(_n1 12)"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$C/out" | head -1)]"
  grep -q 'Set them up now' "$C/out" && bad="$bad [asked with nothing it could do]"
  grep -q 'Adoption cannot set up Context7 here: the claude command is not on PATH' "$C/out" || bad="$bad [Context7 reason missing]"
  grep -q 'Adoption cannot set up Qdrant here: the claude command is not on PATH' "$C/out" || bad="$bad [Qdrant reason missing]"
  grep -qF -- "  $C7ADD" "$C/out" || bad="$bad [no command for later]"
  rec="$(_record)"
  printf '%s' "$rec" | grep -q 'adoption could not act: the claude command is not on PATH' || bad="$bad [record row: '$rec']"
  [ -z "$bad" ] && pass "E4 no claude command: no question, the reason and the commands for later, and an answer sequence written without this step completes" || fail_ "E4" "$bad"
}

e5() {   # registered but silent + skip: the adopted project's own gate blocks, on Qdrant only
  local bad="" g=""
  _case e5 >/dev/null
  _register "$CFG/.claude.json" qdrant
  : > "$ST/docker-up"; : > "$ST/qdrant-exists"
  _adopt "1\nstandard\nskip it\n$(_n1 12)"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC]"
  ( cd "$P" && env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash scripts/session-test-gate-check.sh </dev/null >/dev/null 2>&1 )
  g="$( cd "$P" && printf '{"tool_name":"Write"}' | env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash scripts/session-mcp-gate.sh 2>&1 )"
  printf '%s' "$g" | grep -q '"permissionDecision": "deny"' || bad="$bad [the project's gate ALLOWED a Write — S3's sentence would over-claim]"
  printf '%s' "$g" | grep -q 'qdrant-find' || bad="$bad [the block is not Qdrant's]"
  printf '%s' "$g" | grep -q 'context7 query-docs' && bad="$bad [Context7, registered nowhere, was required]"
  [ -z "$bad" ] && pass "E5 registered but not answering: the adopted project's own gate DOES block a Write, on Qdrant and not on the unregistered Context7 — the note's sentence is the gate's behaviour" || fail_ "E5" "$bad"
}

e6() {   # THE DOGFOOD SHAPE: registered only in ~/.claude.json, a clean
         # CLAUDE_CONFIG_DIR, a database running, uvx present — skip. Nothing may
         # be declared for the project, and a later session must be able to write.
  local bad="" g=""
  _case e6 >/dev/null
  _register "$H/.claude.json" qdrant; _register "$H/.claude.json" context7
  : > "$ST/docker-up"; : > "$ST/qdrant-up"; : > "$ST/qdrant-exists"
  _adopt "1\nstandard\nskip it\n$(_n1 12)"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC]"
  grep -q 'Qdrant (memory across sessions): NOT registered for Claude Code.' "$C/out" || bad="$bad [the ~/.claude.json registration was read]"
  [ -e "$P/.claude/settings.local.json" ] && bad="$bad [a Qdrant declaration was written for a session that has no Qdrant]"
  jq -e '.mcp.qdrant_required == true' "$P/.claude/manifest.json" >/dev/null 2>&1 && bad="$bad [the manifest requires Qdrant]"
  ( cd "$P" && env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash scripts/session-test-gate-check.sh </dev/null >/dev/null 2>&1 )
  [ -f "$P/.claude/tool-usage.json" ] || bad="$bad [the SessionStart hook wrote no ledger, so an allow would prove nothing]"
  g="$( cd "$P" && printf '{"tool_name":"Write"}' | env HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash scripts/session-mcp-gate.sh 2>&1 )"
  [ -z "$g" ] || bad="$bad [the project's gate did not allow a Write: $(printf '%s' "$g" | cut -c1-160)]"
  [ -z "$bad" ] && pass "E6 the dogfood shape: the ~/.claude.json registration is not the session's, nothing is declared for the project, and a session started afterwards can write" || fail_ "E6" "$bad"
}

e7() {   # THE DOGFOOD ANSWERS: 1 to every question. The MCP question takes its 1 as SKIP.
  local bad="" rec=""
  _case e7 >/dev/null
  : > "$ST/docker-up"
  _adopt "$(_n1 14)"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$C/out" | head -1)]"
  grep -q '   1) skip it' "$C/out" || bad="$bad [the MCP question does not list 1) skip it]"
  _calls_ran && bad="$bad [a 1 meant for another question registered servers: $(grep -E 'mcp|docker .(run|start)' "$ST/calls.log" | head -2 | tr '\n' '|')]"
  rec="$(_record)"
  printf '%s' "$rec" | grep -q 'Qdrant: NOT registered (skipped); Context7: NOT registered (skipped)' || bad="$bad [record row: '$rec']"
  [ -z "$bad" ] && pass "E7 the dogfood's answers (1 to every question): the MCP question's 1 is skip, nothing is registered, the adoption completes" || fail_ "E7" "$bad"
}

e_cases() {
  if [ "$HAVE_GITLEAKS" -ne 1 ]; then
    skip "E1-E6" "gitleaks is not on PATH — a personal adoption stops at the secrets check without it"
    return 0
  fi
  e1; e2; e3; e4; e5; e6; e7
}


# s28 — THE WRITTEN PROCEDURE IS PINNED (rounds 12-13): the note sends EVERY
# exposed container to "Recreating an exposed Qdrant container" in
# docs/adoption.md, so its commands are compared EXACTLY, block by block — a
# doc edit cannot silently bring back a step that lost data or a setting. It is
# the snapshot route (Qdrant's own API, through the running server); a file copy
# of the storage is refused outright. Round 13's fixes are each named as well:
# the settings listed first (env, command, entrypoint — values print, said), the
# aliases saved and then restored and checked, snapshot files kept in the
# container copied out before it is stopped, the image the container RUNS
# ({{.Image}}, never the tag), and the old container kept until the check.
_doc_blocks() {
  awk '/^## Recreating an exposed Qdrant container$/ { on = 1; next } on && /^## / { exit }
       on && /^```sh$/ { inb = 1; print "--- block"; next } inb && /^```$/ { inb = 0; next } inb { print }' "$1"
}
s28() {
  local bad="" d="$REPO_ROOT/docs/adoption.md" sec=""
  cat > "$WORK/s28.expect" <<'DOCEOF'
--- block
docker inspect -f '{{json .Config.Env}} {{json .Config.Cmd}} {{json .Config.Entrypoint}} {{json .Mounts}}' qdrant
--- block
Q=http://127.0.0.1:6333; S="$(date +%Y%m%d-%H%M%S)"; B="$HOME/qdrant-snapshots-$S"; H=()
O="$(docker port qdrant 6333/tcp 2>/dev/null | head -1 | sed -e 's/^0\.0\.0\.0:/127.0.0.1:/' -e 's/^\[::\]:/[::1]:/' -e 's#^#http://#')"
if ! command -v jq >/dev/null 2>&1; then echo "STEP 1 FAILED: jq is not installed — install it, then paste this block again"
elif [ -z "$O" ]; then echo "STEP 1 FAILED: docker port printed no address for the old container — start it if it is stopped; if it runs, replace this block's second line with O=http://<address>:<port> where it answers"
elif mkdir "$B" &&
  curl -s -o /dev/null -w '%{http_code}' "$O/collections" > "$B/nokey-status.txt" &&
  curl -sf "${H[@]}" "$O/aliases" > "$B/aliases.json" &&
  curl -sf "${H[@]}" "$O/collections" > "$B/collections.json" &&
  jq -r '.result.collections[].name' "$B/collections.json" > "$B/collections.txt"; then
  while IFS= read -r c; do
    curl -sf "${H[@]}" -X POST "$O/collections/$c/snapshots" > "$B/$c.created.json" &&
    n="$(jq -r '.result.name // empty' "$B/$c.created.json")" &&
    [ -n "$n" ] &&
    curl -sf "${H[@]}" "$O/collections/$c/snapshots/$n" --output "$B/$c.snapshot" &&
    [ -s "$B/$c.snapshot" ] || { echo "SNAPSHOT FAILED: $c"; break; }
  done < "$B/collections.txt"
else echo "STEP 1 FAILED: the old container did not answer at $O, or it needs its API key (set H in the first line)"
fi
--- block
m=0; command -v jq >/dev/null 2>&1 || { echo "STEP 2 FAILED: jq is not installed"; m=1; }
if command -v sha256sum >/dev/null 2>&1; then K=(sha256sum); elif command -v shasum >/dev/null 2>&1; then K=(shasum -a 256); else K=(); echo "STEP 2 FAILED: neither sha256sum nor shasum is installed, so the snapshots cannot be checked"; m=1; fi
[ -s "$B/nokey-status.txt" ] && [ -s "$B/aliases.json" ] && [ -s "$B/collections.json" ] && [ -f "$B/collections.txt" ] || { echo "STEP 1 DID NOT FINISH"; m=1; }
e="$(jq '.result.collections | length' "$B/collections.json" 2>/dev/null)"; g="$(grep -c '' "$B/collections.txt" 2>/dev/null)"
[ "$e" -gt 0 ] 2>/dev/null && [ "$e" = "$g" ] || { echo "COUNT MISMATCH: the server listed ${e:-?} collections, collections.txt has ${g:-?} (they must match, and not be 0)"; m=1; }
while IFS= read -r c; do
  z="$(jq -r '.result.size // empty' "$B/$c.created.json" 2>/dev/null)"; w="$(jq -r '.result.checksum // empty' "$B/$c.created.json" 2>/dev/null)"
  [ -n "$z" ] && [ -n "$w" ] && [ -f "$B/$c.snapshot" ] && [ "$(wc -c < "$B/$c.snapshot" | tr -d '[:space:]')" = "$z" ] &&
    [ "${#K[@]}" -gt 0 ] && [ "$("${K[@]}" < "$B/$c.snapshot" | cut -d' ' -f1)" = "$w" ] || { echo "MISSING OR INCOMPLETE: $c"; m=1; }
done < "$B/collections.txt"; [ "$m" = 0 ] && echo "ALL SNAPSHOTS PRESENT"
--- block
docker cp qdrant:/qdrant/snapshots "$B/old-snapshots" && echo "SNAPSHOT FILES COPIED"
--- block
I="$(docker inspect -f '{{.Image}}' qdrant)" &&
docker rename qdrant qdrant-old &&
docker stop qdrant-old &&
docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v "qdrant_storage_$S:/qdrant/storage" --restart unless-stopped "$I"
--- block
until curl -sf "${H[@]}" "$Q/collections" >/dev/null; do sleep 1; done &&
f=0 &&
while IFS= read -r c; do
  curl -sf "${H[@]}" -X POST "$Q/collections/$c/snapshots/upload?priority=snapshot" -F "snapshot=@$B/$c.snapshot" >/dev/null ||
    { echo "RESTORE FAILED: $c — the collections after it were NOT tried; fix the cause and paste this block again"; f=1; break; }
done < "$B/collections.txt" &&
[ "$f" = 0 ] &&
jq -c '{actions: [.result.aliases[] | {create_alias: {collection_name, alias_name}}]}' "$B/aliases.json" > "$B/alias-actions.json" &&
{ [ "$(jq '.actions | length' "$B/alias-actions.json")" = 0 ] ||
  curl -sf "${H[@]}" -X POST "$Q/collections/aliases" -H 'Content-Type: application/json' --data-binary "@$B/alias-actions.json" >/dev/null ||
  echo "ALIAS RESTORE FAILED"; }
--- block
k=0; [ "$(cat "$B/nokey-status.txt" 2>/dev/null)" = 200 ] || [ "$(curl -s -o /dev/null -w '%{http_code}' "$Q/collections")" != 200 ] || { echo "API KEY LOST: the new container answers without the API key the old one required"; k=1; }
[ "$k" = 0 ] && [ -f "$B/collections.txt" ] && curl -sf "${H[@]}" "$Q/collections" | jq -r '.result.collections[].name' | sort > "$B/restored.txt" &&
sort "$B/collections.txt" | diff - "$B/restored.txt" && echo "ALL COLLECTIONS RESTORED"
[ "$k" = 0 ] && curl -sf "${H[@]}" "$Q/aliases" | jq -c '[.result.aliases[] | [.alias_name, .collection_name]] | sort' > "$B/aliases-restored.json" &&
jq -c '[.result.aliases[] | [.alias_name, .collection_name]] | sort' "$B/aliases.json" | diff - "$B/aliases-restored.json" && echo "ALL ALIASES RESTORED"
DOCEOF
  _doc_blocks "$d" > "$WORK/s28.got"
  sec="$(awk '/^## Recreating an exposed Qdrant container$/ { on = 1; next } on && /^## / { exit } on' "$d")"
  [ -n "$sec" ] || { fail_ "S28" "[the section \"Recreating an exposed Qdrant container\" is missing]"; return; }
  cmp -s "$WORK/s28.expect" "$WORK/s28.got" || bad="$bad [the procedure's commands changed: $(diff "$WORK/s28.expect" "$WORK/s28.got" | head -4 | tr '\n' '|' | cut -c1-240)]"
  printf '%s\n' "$sec" | grep -qE 'docker cp qdrant:/qdrant/storage|tar -C /qdrant/storage' && bad="$bad [a file copy of the storage is back in the procedure]"
  printf '%s\n' "$sec" | grep -qF 'snapshots/upload?priority=snapshot' || bad="$bad [the snapshot restore is not the route]"
  printf '%s\n' "$sec" | grep -qF '.Config.Image' && bad="$bad [(a) the recreate names the tag (.Config.Image), not the image the container runs]"
  grep -qxF "I=\"\$(docker inspect -f '{{.Image}}' qdrant)\" &&" "$WORK/s28.got" || bad="$bad [(a) the recreate does not reuse the running image ID]"
  grep -qF 'curl -sf "${H[@]}" "$O/aliases" > "$B/aliases.json" &&' "$WORK/s28.got" || bad="$bad [(b) the aliases are not saved]"
  grep -qF '"$Q/collections/aliases"' "$WORK/s28.got" || bad="$bad [(b) the aliases are not restored]"
  grep -qF 'echo "ALL ALIASES RESTORED"' "$WORK/s28.got" || bad="$bad [(b) the restored aliases are not checked]"
  grep -qxF "docker inspect -f '{{json .Config.Env}} {{json .Config.Cmd}} {{json .Config.Entrypoint}} {{json .Mounts}}' qdrant" "$WORK/s28.got" || bad="$bad [(c) the settings, mounts included, are not listed before the recreate]"
  printf '%s\n' "$sec" | grep -qF 'prints their values, an API key included' || bad="$bad [(c) it is not said that listing the settings prints a key's value]"
  grep -qxF 'docker cp qdrant:/qdrant/snapshots "$B/old-snapshots" && echo "SNAPSHOT FILES COPIED"' "$WORK/s28.got" || bad="$bad [(d) snapshot files kept in the container are not copied out]"
  printf '%s\n' "$sec" | grep -qF 'until step 6 passes it is your way back' || bad="$bad [(e) the old container is not kept until the check passes]"
  # ROUND 14. R-BL311-1: jq missing is said by step 1, and step 2 compares the
  # server's count with the names saved. R-BL311-3: the mounts are listed, a
  # config file is re-mounted, and step 6 fails when a request WITHOUT the key
  # is answered where the old container refused one. R-BL311-6: step 5 says
  # the collections after a failed upload were not tried.
  grep -qxF 'if ! command -v jq >/dev/null 2>&1; then echo "STEP 1 FAILED: jq is not installed — install it, then paste this block again"' "$WORK/s28.got" || bad="$bad [(f) step 1 does not say jq is missing]"
  grep -qxF 'm=0; command -v jq >/dev/null 2>&1 || { echo "STEP 2 FAILED: jq is not installed"; m=1; }' "$WORK/s28.got" || bad="$bad [(g) step 2 does not fail without jq]"
  grep -qF "e=\"\$(jq '.result.collections | length' \"\$B/collections.json\" 2>/dev/null)\"; g=\"\$(grep -c '' \"\$B/collections.txt\" 2>/dev/null)\"" "$WORK/s28.got" || bad="$bad [(g) step 2 does not count the server's collections and the names saved]"
  grep -qF '[ "$e" -gt 0 ] 2>/dev/null && [ "$e" = "$g" ] || { echo "COUNT MISMATCH:' "$WORK/s28.got" || bad="$bad [(g) step 2 does not require the two counts to match and be above 0]"
  printf '%s\n' "$sec" | grep -qF 'a config file mounted into it' || bad="$bad [(h) the settings do not name a mounted config file]"
  printf '%s\n' "$sec" | grep -qF 'a config file above all' || bad="$bad [(h) step 4 does not say to re-mount a config file]"
  grep -qF '> "$B/nokey-status.txt" &&' "$WORK/s28.got" || bad="$bad [(h) step 1 does not record what a request without the key gets]"
  grep -qF '|| { echo "API KEY LOST:' "$WORK/s28.got" || bad="$bad [(h) step 6 does not check a request without the key]"
  grep -qF '[ "$k" = 0 ] && [ -f "$B/collections.txt" ]' "$WORK/s28.got" || bad="$bad [(h) step 6's success lines do not wait on the key check]"
  printf '%s\n' "$sec" | grep -qF 'were NOT tried, and no alias was restored' || bad="$bad [(i) step 5 does not say the collections after a failed upload were not tried]"
  printf '%s\n' "$sec" | grep -qF 'paste this block' || bad="$bad [(i) step 5 does not say to paste it again for the rest]"
  # ROUND 15. R-BL311-7: step 1 keeps what Qdrant answered when it made each
  # snapshot, and step 2 checks every file's size and sha256 against it — a
  # download cut short leaves a file that is NOT empty, so `[ -s ]` passed it
  # (S38 (f) runs that). R-BL311-9: the old container is read at O, from
  # `docker port`, and the new one at Q — step 5 waiting on the old address
  # would never end (S38 (h) runs that).
  grep -qF 'curl -sf "${H[@]}" -X POST "$O/collections/$c/snapshots" > "$B/$c.created.json" &&' "$WORK/s28.got" || bad="$bad [(j) step 1 does not keep what Qdrant answered when it made each snapshot]"
  grep -qF 'wc -c < "$B/$c.snapshot"' "$WORK/s28.got" && grep -qF '= "$z" ]' "$WORK/s28.got" || bad="$bad [(j) step 2 does not check each file's size against the one Qdrant reported]"
  grep -qF '"${K[@]}" < "$B/$c.snapshot"' "$WORK/s28.got" && grep -qF '= "$w" ]' "$WORK/s28.got" || bad="$bad [(j) step 2 does not check each file's sha256 against the one Qdrant reported]"
  grep -qF 'echo "MISSING OR INCOMPLETE: $c"' "$WORK/s28.got" || bad="$bad [(j) step 2 does not name a collection whose snapshot is not all there]"
  grep -qF 'else K=(); echo "STEP 2 FAILED: neither sha256sum nor shasum is installed' "$WORK/s28.got" || bad="$bad [(j) step 2 does not fail when there is no sha256 tool]"
  grep -qF '[ -s "$B/$c.snapshot" ] || { echo "MISSING' "$WORK/s28.got" && bad="$bad [(j) step 2 is back to a non-empty test, which passes a partial download]"
  grep -qF 'O="$(docker port qdrant 6333/tcp 2>/dev/null | head -1 |' "$WORK/s28.got" || bad="$bad [(k) step 1 does not read the old container's address from docker port]"
  grep -qF 'elif [ -z "$O" ]; then echo "STEP 1 FAILED: docker port printed no address' "$WORK/s28.got" || bad="$bad [(k) step 1 does not stop when docker port prints nothing]"
  _doc_block 2 "$d" | grep -qF '"$Q/' && bad="$bad [(k) step 1 sends a request to Q, the NEW container's address]"
  _doc_block 6 "$d" | grep -qF '$O' && bad="$bad [(k) step 5 sends a request to O, the OLD container's address]"
  _doc_block 7 "$d" | grep -qF '$O' && bad="$bad [(k) step 6 sends a request to O, the OLD container's address]"
  printf '%s\n' "$sec" | grep -qF 'Never point `Q` at the old container' || bad="$bad [(k) the doc does not say never to point Q at the old container]"
  [ -z "$bad" ] && pass "S28 the written procedure's seven command blocks match exactly — list the settings and mounts, snapshot every collection from the old container's docker port address and save the aliases (saying so when jq is missing or no address is printed), check the counts match and every file's size and sha256 against what Qdrant reported, copy out kept snapshot files, recreate from the running image ID with rename before stop, restore collections and aliases (saying what was not tried), check both and that the API key survived — and no file copy of the storage is in it" || fail_ "S28" "$bad"
}

# s38 — THE WRITTEN PROCEDURE, RUN (round 14). S28 pins the text; this runs
# steps 1, 2 and 6 — and 5 on a failed upload — as the doc prints them, in
# bash, against a stand-in Qdrant (a `curl` that answers the procedure's
# requests: the collections, the aliases, snapshot create/download/upload, and
# 401 for a request without the API key while one is required). Round 14
# measured data loss on real Docker: with `jq` absent, step 1 left an EMPTY
# collections.txt, step 2 printed ALL SNAPSHOTS PRESENT over nothing, and step
# 4 then stopped a tmpfs container. So:
#   (a) jq present, no key — steps 1, 2 and 6 all print their success lines
#       (the check is not vacuous);
#   (b) jq ABSENT — step 1 says so, step 2 says so, and no success line;
#   (c) THE MEASURED STATE — collections.json lists two, collections.txt is
#       empty — step 2 prints no success line, with jq absent AND present;
#   (d) a key the old container required is LOST on the new one — step 6
#       prints API KEY LOST and neither success line; kept, both print;
#   (e) step 5 with its first upload failing — says the rest were not tried,
#       and uploads nothing after it and restores no alias.
# Round 15 measured data loss again (R-BL311-7): a download cut short — disk
# full, a dropped connection, Ctrl-C — leaves a PARTIAL file that is not
# empty, and step 1 stops there, so it is the LAST collection tried; step 2's
# `[ -s ]` passed it. And (R-BL311-9) step 1 read the old container at
# 127.0.0.1:6333, which is not where a -P or LAN-address container is. So:
#   (f) the last download, then the ONLY one, cut short — step 2 names it
#       MISSING OR INCOMPLETE and prints no success line, and a complete file
#       beside it passes (its size and sha256 as the stand-in reported them);
#   (g) no sha256 tool — step 2 says so and prints no success line;
#   (h) -P (docker port 0.0.0.0:32768 and [::]:32768), then a LAN address —
#       step 1 reaches the old container there; after "step 4" only the new
#       one answers, on 127.0.0.1:6333, and steps 5-6 restore it there;
#   (i) docker port prints nothing — step 1 says so and asks no address at
#       all; with its second line set by hand, as the doc says, it completes.
_mk_qapi() {   # DIR — the stand-in Qdrant: its curl, and a docker that answers `docker port`
  mkdir -p "$1" || return 1
  cat > "$1/curl" <<'QAPI'
#!/bin/bash
# a stand-in Qdrant HTTP API, as curl sees it, for running the written procedure.
# It answers at ONE host:port — $QSTUB/serving, default 127.0.0.1:6333 — and
# refuses a connection anywhere else (exit 7, and `000` for -w), as curl does.
# A fifth refused connection in one run is a loop that would never end (step
# 5's `until` against an address nothing answers at): it is recorded in
# hung.log and the run is ended, so a case cannot hang the suite.
d="${QSTUB:?}"
method=GET out="" url="" key="" fmt="" failflag=0 partial=0 form=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -H) case "$2" in api-key:*) key="${2#api-key:}"; key="${key# }" ;; esac; shift 2 ;;
    -o|--output) out="$2"; shift 2 ;;
    -w) fmt="$2"; shift 2 ;;
    -F) form="$2"; shift 2 ;;
    --data-binary) shift 2 ;;
    -sf|-fs|-f) failflag=1; shift ;;
    http://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
echo "$method $url key=${key:-none}" >> "$d/requests.log"
# curl reads a -F file before it connects: a missing one is exit 26
case "$form" in *=@*) [ -f "${form#*=@}" ] || { echo "curl: (26) Failed to open/read local data from file/application" >&2; exit 26; } ;; esac
rest="${url#http://}"; hp="${rest%%/*}"; p="/${rest#*/}"; p="${p%%\?*}"
served="127.0.0.1:6333"; [ -f "$d/serving" ] && served="$(cat "$d/serving")"
if [ "$hp" != "$served" ]; then
  echo "$url" >> "$d/refused.log"
  if [ "$(grep -c '' "$d/refused.log")" -ge 5 ]; then echo "HUNG: $url" >> "$d/hung.log"; kill -TERM "$PPID" 2>/dev/null; fi
  [ -n "$fmt" ] && printf '000'
  exit 7
fi
need=""; [ -f "$d/key" ] && [ ! -f "$d/key-lost" ] && need="$(cat "$d/key")"
if [ -n "$need" ] && [ "$key" != "$need" ]; then
  code=401; body='{"status":{"error":"Must provide an API key or an Authorization bearer token"}}'
else
  code=200
  case "$method $p" in
    "GET /aliases")                   body="$(cat "$d/aliases.json")" ;;
    "GET /collections")               body="$(cat "$d/collections.json")" ;;
    "POST /collections/aliases")      body='{"result":true,"status":"ok"}' ;;
    # what Qdrant answers when it makes a snapshot (measured on 1.17.1 by the
    # round-15 review): its name, and the size and sha256 checksum of the file
    # the download then gives — here, the exact bytes the download arm prints
    "POST /collections/"*/snapshots)
      c="${p#/collections/}"; c="${c%/snapshots}"; n="$c-1.snapshot"; sb="snapshot bytes of $c/snapshots/$n"
      body="{\"result\":{\"name\":\"$n\",\"creation_time\":\"2026-09-29T00:00:00\",\"size\":${#sb},\"checksum\":\"$(printf '%s' "$sb" | "${QSUM:?}" | cut -d' ' -f1)\"},\"status\":\"ok\"}" ;;
    "GET /collections/"*/snapshots/*)
      body="snapshot bytes of ${p#/collections/}"; c="${p#/collections/}"; c="${c%%/*}"
      [ -f "$d/download-partial" ] && [ "$(cat "$d/download-partial")" = "$c" ] && partial=1 ;;
    "POST /collections/"*/snapshots/upload)
      c="${p#/collections/}"; c="${c%/snapshots/upload}"; body='{"result":true,"status":"ok"}'
      [ -f "$d/upload-fails" ] && [ "$(cat "$d/upload-fails")" = "$c" ] && { code=500; body='{"status":{"error":"stub upload failure"}}'; } ;;
    *) code=404; body='{"status":{"error":"Not found"}}' ;;
  esac
fi
# A DOWNLOAD CUT SHORT (a full disk, a dropped connection, Ctrl-C): curl leaves
# what it got — a file that is NOT empty — and exits non-zero (18, partial file).
if [ "$partial" = 1 ] && [ -n "$out" ]; then printf '%s' "${body:0:$(( ${#body} / 2 ))}" > "$out"; exit 18; fi
case "$code" in 2*) ok=1 ;; *) ok=0 ;; esac
if [ "$ok" = 1 ] || [ "$failflag" = 0 ]; then
  if [ -n "$out" ]; then printf '%s' "$body" > "$out"; elif [ -z "$fmt" ]; then printf '%s' "$body"; fi
fi
[ -n "$fmt" ] && printf '%s' "$code"
[ "$ok" = 0 ] && [ "$failflag" = 1 ] && exit 22
exit 0
QAPI
  cat > "$1/docker" <<'QDOCK'
#!/bin/bash
# the stand-in's docker answers `docker port qdrant 6333/tcp` from $QSTUB/port —
# 127.0.0.1:6333 when there is none; an EMPTY one is a container that publishes
# nothing (the host network), which real docker answers on stderr, exit 1.
# Anything else is not modelled, and says so.
d="${QSTUB:?}"
echo "docker $*" >> "$d/docker.log"
if [ "$*" = "port qdrant 6333/tcp" ]; then
  if [ ! -f "$d/port" ]; then echo "127.0.0.1:6333"
  elif [ -s "$d/port" ]; then cat "$d/port"
  else echo "Error: No public port '6333/tcp' published for qdrant" >&2; exit 1; fi
  exit 0
fi
echo "stand-in docker: not modelled: $*" >&2; exit 1
QDOCK
  chmod +x "$1/curl" "$1/docker"
}
_doc_block() { _doc_blocks "$2" | awk -v n="$1" '/^--- block$/ { k++; next } k == n'; }   # N FILE
_qrun() {   # SCRIPT PATH — run SCRIPT in bash with that PATH, a fresh HOME, this case's stand-in state
  local h=""
  h="$(mktemp -d "$C/home.XXXXXX")" || return 1
  : > "$C/qs/refused.log"   # the stand-in's hang guard counts per run
  env PATH="$2" HOME="$h" QSTUB="$C/qs" QSUM="$WORK/qsum" bash "$1" </dev/null 2>&1
}
s38() {
  local bad="" d="$FW/docs/adoption.md" b1="" b2="" b5="" b6="" b1k="" b1o="" o="" pj="" pn="" ps="" two=""
  _case s38 >/dev/null
  b1="$(_doc_block 2 "$d")"; b2="$(_doc_block 3 "$d")"; b5="$(_doc_block 6 "$d")"; b6="$(_doc_block 7 "$d")"
  if [ -z "$b1" ] || [ -z "$b2" ] || [ -z "$b5" ] || [ -z "$b6" ]; then fail_ "S38" "[the procedure's blocks could not be read from $d]"; return; fi
  { [ -x "$WORK/qapi/curl" ] && [ -x "$WORK/qapi/docker" ]; } || _mk_qapi "$WORK/qapi" || { fail_ "S38" "[the stand-in Qdrant could not be made]"; return; }
  # the stand-in's own sha256, by absolute path, so it still answers on a PATH
  # that has neither tool (g)
  if [ ! -x "$WORK/qsum" ]; then
    if command -v sha256sum >/dev/null 2>&1; then printf '#!/bin/bash\nexec "%s"\n' "$(command -v sha256sum)" > "$WORK/qsum"
    elif command -v shasum >/dev/null 2>&1; then printf '#!/bin/bash\nexec "%s" -a 256\n' "$(command -v shasum)" > "$WORK/qsum"
    else fail_ "S38" "[neither sha256sum nor shasum is on this machine, so the stand-in cannot give a checksum]"; return; fi
    chmod +x "$WORK/qsum"
  fi
  # A KNOWN ANSWER, so the stand-in's checksum is SHA-256 and not merely the
  # same tool agreeing with itself: step 2 may pick that same tool, and a
  # format both misread would then match. sha256("abc"), FIPS 180-2.
  [ "$(printf 'abc' | "$WORK/qsum" | cut -d' ' -f1)" = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad ] || { fail_ "S38" "[the stand-in's sha256 is not SHA-256: $(printf 'abc' | "$WORK/qsum" | head -1)]"; return; }
  [ -d "$WORK/nojq" ] || _mirror_without "$WORK/nojq" jq
  [ -d "$WORK/nosum" ] || _mirror_without "$WORK/nosum" sha256sum shasum
  pj="$WORK/qapi:$PATH"; pn="$WORK/qapi:$WORK/nojq"; ps="$WORK/qapi:$WORK/nosum"
  # Asked of a FRESH shell on that PATH: this one has jq in its command hash,
  # and `PATH=… command -v jq` answers from the hash (measured: /usr/bin/jq).
  if env PATH="$pn" bash -c 'command -v jq' </dev/null >/dev/null 2>&1; then fail_ "S38" "[jq is still on the no-jq PATH: $(env PATH="$pn" bash -c 'command -v jq' </dev/null)]"; return; fi
  if env PATH="$ps" bash -c 'command -v sha256sum || command -v shasum' </dev/null >/dev/null 2>&1; then fail_ "S38" "[a sha256 tool is still on the no-sha256 PATH: $(env PATH="$ps" bash -c 'command -v sha256sum || command -v shasum' </dev/null)]"; return; fi
  mkdir -p "$C/qs"
  two='{"result":{"collections":[{"name":"claude-memory"},{"name":"acme"}]},"status":"ok"}'
  printf '%s' '{"result":{"aliases":[{"alias_name":"mem","collection_name":"claude-memory"}]},"status":"ok"}' > "$C/qs/aliases.json"
  printf '%s' "$two" > "$C/qs/collections.json"
  # (a)
  printf '%s\n%s\n%s\n' "$b1" "$b2" "$b6" > "$C/a.sh"; o="$(_qrun "$C/a.sh" "$pj")"
  printf '%s\n' "$o" | grep -qx 'ALL SNAPSHOTS PRESENT' || bad="$bad [(a) with jq and no key, step 2 did not print ALL SNAPSHOTS PRESENT: $(printf '%s' "$o" | head -3 | tr '\n' '|' | cut -c1-160)]"
  printf '%s\n' "$o" | grep -qx 'ALL COLLECTIONS RESTORED' && printf '%s\n' "$o" | grep -qx 'ALL ALIASES RESTORED' || bad="$bad [(a) with jq and no key, step 6 did not print both success lines]"
  # (b)
  printf '%s\n%s\n' "$b1" "$b2" > "$C/b.sh"; o="$(_qrun "$C/b.sh" "$pn")"
  printf '%s\n' "$o" | grep -q '^STEP 1 FAILED: jq is not installed' || bad="$bad [(b) without jq, step 1 did not say jq is missing]"
  printf '%s\n' "$o" | grep -q '^STEP 2 FAILED: jq is not installed' || bad="$bad [(b) without jq, step 2 did not say jq is missing]"
  printf '%s\n' "$o" | grep -q 'ALL SNAPSHOTS PRESENT' && bad="$bad [(b) without jq, step 2 printed ALL SNAPSHOTS PRESENT]"
  # (c)
  mkdir -p "$C/meas"; cp "$C/qs/aliases.json" "$C/qs/collections.json" "$C/meas/"; : > "$C/meas/collections.txt"; printf 200 > "$C/meas/nokey-status.txt"
  printf "B='%s'\n%s\n" "$C/meas" "$b2" > "$C/c.sh"
  _qrun "$C/c.sh" "$pn" | grep -q 'ALL SNAPSHOTS PRESENT' && bad="$bad [(c) jq missing and step 1's collections.txt empty: step 2 still printed ALL SNAPSHOTS PRESENT]"
  _qrun "$C/c.sh" "$pj" | grep -q 'ALL SNAPSHOTS PRESENT' && bad="$bad [(c) step 1's collections.txt empty: step 2 printed ALL SNAPSHOTS PRESENT with jq present]"
  # (d) — the key set the way the doc says: H=() at the end of step 1's first line
  b1k="${b1%%"; H=()"*}; H=(-H 'api-key: k1')${b1#*"; H=()"}"
  if ! printf '%s\n' "$b1k" | head -1 | grep -qF "; H=(-H 'api-key: k1')"; then bad="$bad [(d) H=() is not at the end of step 1's first line]"
  else
    printf 'k1' > "$C/qs/key"
    printf '%s\n%s\n%s\n' "$b1k" "$b2" "$b6" > "$C/d-kept.sh"; o="$(_qrun "$C/d-kept.sh" "$pj")"
    printf '%s\n' "$o" | grep -qx 'ALL COLLECTIONS RESTORED' && printf '%s\n' "$o" | grep -qx 'ALL ALIASES RESTORED' || bad="$bad [(d) the key kept: step 6 did not print both success lines: $(printf '%s' "$o" | head -3 | tr '\n' '|' | cut -c1-160)]"
    printf '%s\n' "$o" | grep -q 'API KEY LOST' && bad="$bad [(d) the key kept: step 6 said it was lost]"
    printf '%s\n%s\n%s\n%s\n' "$b1k" "$b2" ': > "$QSTUB/key-lost"' "$b6" > "$C/d-lost.sh"; o="$(_qrun "$C/d-lost.sh" "$pj")"
    printf '%s\n' "$o" | grep -q '^API KEY LOST' || bad="$bad [(d) the key was lost and step 6 did not say API KEY LOST]"
    printf '%s\n' "$o" | grep -qE 'ALL (COLLECTIONS|ALIASES) RESTORED' && bad="$bad [(d) the key was lost and step 6 still printed a success line]"
    mv "$C/qs/key" "$C/qs/key.off"   # (e) runs with no key required
  fi
  # (e)
  printf 'claude-memory' > "$C/qs/upload-fails"; : > "$C/qs/requests.log"
  printf '%s\n%s\n' "$b1" "$b5" > "$C/e.sh"; o="$(_qrun "$C/e.sh" "$pj")"
  printf '%s\n' "$o" | grep -q '^RESTORE FAILED: claude-memory — the collections after it were NOT tried' || bad="$bad [(e) a failed upload does not say the collections after it were not tried]"
  grep -q 'acme/snapshots/upload' "$C/qs/requests.log" && bad="$bad [(e) a collection after the failed upload was uploaded]"
  grep -q 'POST .*/collections/aliases' "$C/qs/requests.log" && bad="$bad [(e) the aliases were restored after a failed upload]"
  mv "$C/qs/upload-fails" "$C/qs/upload-fails.off"
  # (f) R-BL311-7 — the download of the LAST collection step 1 tries is cut
  # short, leaving a partial file that is NOT empty; step 1 says SNAPSHOT FAILED
  # and stops, and step 2 must not pass it. Then the ONLY collection (the
  # mcp-server-qdrant default: one), where round 15 lost the data.
  printf 'acme' > "$C/qs/download-partial"
  printf '%s\n%s\n' "$b1" "$b2" > "$C/f.sh"; o="$(_qrun "$C/f.sh" "$pj")"
  printf '%s\n' "$o" | grep -qx 'SNAPSHOT FAILED: acme' || bad="$bad [(f) the stand-in did not cut acme's download short: $(printf '%s' "$o" | head -3 | tr '\n' '|' | cut -c1-160)]"
  printf '%s\n' "$o" | grep -q 'ALL SNAPSHOTS PRESENT' && bad="$bad [(f) a partial snapshot of the LAST collection: step 2 still printed ALL SNAPSHOTS PRESENT]"
  printf '%s\n' "$o" | grep -qx 'MISSING OR INCOMPLETE: acme' || bad="$bad [(f) a partial snapshot of the LAST collection is not named MISSING OR INCOMPLETE]"
  printf '%s\n' "$o" | grep -q 'MISSING OR INCOMPLETE: claude-memory' && bad="$bad [(f) a complete snapshot, its size and checksum as reported, was called incomplete]"
  printf '%s' '{"result":{"collections":[{"name":"claude-memory"}]},"status":"ok"}' > "$C/qs/collections.json"
  printf 'claude-memory' > "$C/qs/download-partial"
  o="$(_qrun "$C/f.sh" "$pj")"
  printf '%s\n' "$o" | grep -qx 'SNAPSHOT FAILED: claude-memory' || bad="$bad [(f) the stand-in did not cut the only download short]"
  printf '%s\n' "$o" | grep -q 'ALL SNAPSHOTS PRESENT' && bad="$bad [(f) a partial snapshot of the ONLY collection: step 2 still printed ALL SNAPSHOTS PRESENT]"
  printf '%s\n' "$o" | grep -qx 'MISSING OR INCOMPLETE: claude-memory' || bad="$bad [(f) a partial snapshot of the ONLY collection is not named MISSING OR INCOMPLETE]"
  printf '%s' "$two" > "$C/qs/collections.json"; mv "$C/qs/download-partial" "$C/qs/download-partial.off"
  # (g) no sha256 tool: step 2 cannot check the files, so it says so and passes nothing
  printf '%s\n%s\n' "$b1" "$b2" > "$C/g.sh"; o="$(_qrun "$C/g.sh" "$ps")"
  printf '%s\n' "$o" | grep -q '^STEP 2 FAILED: neither sha256sum nor shasum is installed' || bad="$bad [(g) with no sha256 tool, step 2 did not say so: $(printf '%s' "$o" | head -3 | tr '\n' '|' | cut -c1-160)]"
  printf '%s\n' "$o" | grep -q 'ALL SNAPSHOTS PRESENT' && bad="$bad [(g) with no sha256 tool, step 2 printed ALL SNAPSHOTS PRESENT]"
  # (h) R-BL311-9 — the old container is where `docker port` says, not on
  # 6333: created with -P (0.0.0.0 and [::] on a random port), then on a LAN
  # address. Steps 1-2 must reach it there; after step 4 only the NEW container
  # answers, on 127.0.0.1:6333, and steps 5-6 must go there — waiting on the old
  # address would never end (the stand-in records that as hung.log).
  printf '0.0.0.0:32768\n[::]:32768\n' > "$C/qs/port"; printf '127.0.0.1:32768' > "$C/qs/serving"; : > "$C/qs/requests.log"
  printf '%s\n%s\n%s\n%s\n%s\n' "$b1" "$b2" 'printf 127.0.0.1:6333 > "$QSTUB/serving"' "$b5" "$b6" > "$C/h.sh"; o="$(_qrun "$C/h.sh" "$pj")"
  printf '%s\n' "$o" | grep -qx 'ALL SNAPSHOTS PRESENT' || bad="$bad [(h) -P (docker port 0.0.0.0:32768): step 1 did not reach the old container where docker port said: $(printf '%s' "$o" | head -3 | tr '\n' '|' | cut -c1-160)]"
  grep -q '^POST http://127\.0\.0\.1:32768/collections/acme/snapshots ' "$C/qs/requests.log" || bad="$bad [(h) -P: the snapshot was not made at 127.0.0.1:32768]"
  [ -s "$C/qs/hung.log" ] && bad="$bad [(h) step 5 waited on the OLD address, where nothing answers after step 4: $(head -1 "$C/qs/hung.log")]"
  grep -q '^POST http://127\.0\.0\.1:6333/collections/acme/snapshots/upload?priority=snapshot ' "$C/qs/requests.log" || bad="$bad [(h) -P: the restore did not go to the new container on 127.0.0.1:6333]"
  printf '%s\n' "$o" | grep -qx 'ALL COLLECTIONS RESTORED' && printf '%s\n' "$o" | grep -qx 'ALL ALIASES RESTORED' || bad="$bad [(h) -P: step 6 did not print both success lines]"
  printf '192.168.1.10:6333\n' > "$C/qs/port"; printf '192.168.1.10:6333' > "$C/qs/serving"
  printf '%s\n%s\n' "$b1" "$b2" > "$C/h2.sh"; o="$(_qrun "$C/h2.sh" "$pj")"
  printf '%s\n' "$o" | grep -qx 'ALL SNAPSHOTS PRESENT' || bad="$bad [(h) a LAN address (docker port 192.168.1.10:6333): step 1 did not reach the old container there]"
  # (i) `docker port` prints nothing (the host network): step 1 says so and asks
  # NOTHING of any address — no guess; then the doc's remedy, its second line
  # replaced by O=<where it answers>, completes.
  : > "$C/qs/port"; printf '127.0.0.1:6333' > "$C/qs/serving"; : > "$C/qs/requests.log"
  printf '%s\n%s\n' "$b1" "$b2" > "$C/i.sh"; o="$(_qrun "$C/i.sh" "$pj")"
  printf '%s\n' "$o" | grep -q '^STEP 1 FAILED: docker port printed no address for the old container' || bad="$bad [(i) docker port printed nothing and step 1 did not say so: $(printf '%s' "$o" | head -2 | tr '\n' '|' | cut -c1-160)]"
  printf '%s\n' "$o" | grep -q 'ALL SNAPSHOTS PRESENT' && bad="$bad [(i) docker port printed nothing and step 2 printed ALL SNAPSHOTS PRESENT]"
  [ -s "$C/qs/requests.log" ] && bad="$bad [(i) docker port printed nothing and step 1 still asked an address it guessed: $(head -1 "$C/qs/requests.log")]"
  if ! printf '%s\n' "$b1" | sed -n 2p | grep -q '^O='; then bad="$bad [(i) step 1's second line does not set O, so the doc's remedy cannot be followed]"
  else
    b1o="$(printf '%s\n' "$b1" | awk 'NR == 2 { print "O=http://127.0.0.1:6333"; next } { print }')"
    printf '%s\n%s\n' "$b1o" "$b2" > "$C/i2.sh"; o="$(_qrun "$C/i2.sh" "$pj")"
    printf '%s\n' "$o" | grep -qx 'ALL SNAPSHOTS PRESENT' || bad="$bad [(i) with the second line set by hand, as the doc says, step 1 still did not complete]"
  fi
  mv "$C/qs/port" "$C/qs/port.off"; mv "$C/qs/serving" "$C/qs/serving.off"
  [ -z "$bad" ] && pass "S38 the written procedure run against a stand-in Qdrant: jq missing is said by steps 1 and 2 with no success line, step 1's empty list no longer passes step 2, a lost API key fails step 6, a failed upload stops step 5 and says the rest were not tried, a download cut short on the last or only collection fails step 2's size and checksum check, no sha256 tool fails step 2, the old container is read where docker port says (-P, a LAN address) and the new one restored on 127.0.0.1:6333, docker port printing nothing stops step 1 with no guess — and with jq and the key kept, every success line prints" || fail_ "S38" "$bad"
}

if [ -n "${BL311_ONLY:-}" ]; then
  for _f in $BL311_ONLY; do "$_f"; done
  _done
fi
a1; a4; a5; a6; a7; a8
s1; s2; s3; s4; s5; s6; s7; s8; s9; s10; s11; s12; s13; s14; s15; s16; s17; s18
s19; s19b; s19c; s19d; s19e; s19f; s19g; s20; s25; s27; s28; s29
s30; s31; s32; s33; s33b; s33c; s34; s35; s36; s37; s38
e_cases

# ── M — mutation proofs ─────────────────────────────────────────────────────
# Each mutant replaces the ONE line ending in its marker, in a COPY of the
# framework, asserts the replacement landed by its own text and still parses,
# and re-runs only the case that must kill it — and the kill must come from
# the NAMED assertion. A mutation that did not apply is a harness FAILURE,
# never a kill.
_mirror_fw() { mkdir -p "$1" && cp -Rp "$REPO_ROOT/scripts" "$REPO_ROOT/templates" "$1/" && cp -p "$REPO_ROOT/init.sh" "$1/"; }
_mutate() {   # FILE MARKER REPLACEMENT
  local f="$1" n=""
  MUT_MARK="$2" MUT_REPL="$3" awk '
    { m = ENVIRON["MUT_MARK"]; L = length($0); K = length(m)
      if (L >= K && substr($0, L - K + 1) == m) { print ENVIRON["MUT_REPL"]; n++ } else print }
    END { print n + 0 > "/dev/stderr" }' "$f" > "$f.mut" 2> "$f.n" || return 1
  n="$(cat "$f.n")"; rm -f "$f.n"
  [ "$n" = "1" ] || { echo "sites=$n"; rm -f "$f.mut"; return 1; }
  mv "$f.mut" "$f" || return 1
  grep -qxF -- "$3" "$f" || { echo "replacement not found"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
mut() {   # LABEL FILE MARKER REPLACEMENT CASE-FN WANT — WANT is the assertion text that must kill it
  local label="$1" rel="$2" marker="$3" repl="$4" fn="$5" want="$6" m="" r=""
  case "$fn" in e*) if [ "$HAVE_GITLEAKS" -ne 1 ]; then skip "$label" "its killing case needs gitleaks"; return; fi ;; esac
  m="$WORK/mut-$(printf '%s' "$marker" | tr -c 'A-Za-z0-9' '-')"
  _mirror_fw "$m" || { fail_ "$label" "could not mirror the framework"; return; }
  r="$(_mutate "$m/$rel" "$marker" "$repl")" || { fail_ "$label" "the mutation did not apply ($r)"; return; }
  _mut_judge "$label" "$m" "$fn" "$want"
}
_mut_judge() {   # LABEL MIRROR CASE-FN WANT — run the case on the mutated mirror; the kill must be WANT
  local label="$1" m="$2" fn="$3" want="$4" p0="" f0="" s0="" why=""
  p0=$PASSED; f0=$FAILED; s0=$SKIPPED
  FW="$m"; "$fn" > "$m.out" 2>&1; FW="$REPO_ROOT"
  # THE KILL MUST BE THE INTENDED ASSERTION. The first draft of this section
  # "killed" every adoption mutant with "this project has already been
  # adopted", because the cases reused their fixtures.
  why="$(grep '\[FAIL\]' "$m.out" | sed 's/^ *\[FAIL\] //' | tr '\n' ' ')"
  PASSED=$p0; SKIPPED=$s0   # the case's own passes and skips are not the mutant's
  if [ "$FAILED" -le "$f0" ]; then FAILED=$f0; fail_ "$label" "the mutant survived"
  elif printf '%s' "$why" | grep -qF -- "$want"; then FAILED=$f0; pass "$label"
  else FAILED=$f0; fail_ "$label" "killed, but not by '$want': $(printf '%s' "$why" | cut -c1-240)"; fi
  rm -rf "$m" "$m.out"
}

# THREE `</dev/null`s HAVE NO KILLING CASE ON THEIR OWN, AND THAT IS MEASURED:
# the setup commands (`# BL-311-MCP-RUN`), the registration probes
# (`# BL-311-MCP-PROBE-STDIN`) and the launch check (`# BL-311-MCP-LAUNCH-STDIN`)
# all run inside a `( … )` subshell, and inside the driver a backgrounded child
# of a subshell gets /dev/null regardless — dropping the redirection alone is an
# equivalent mutant (round 2: the launch one survived E2, a whole adoption with
# twelve answers still on the pipe and two `claude mcp get` calls, which
# asserts no stub read them). Dropping the subshell AS WELL is not equivalent:
# M39 does that to the launch check and E2 kills it, as M20 does for the bare
# Docker probe. The redirections stay because the consent rule asks for them.

# _mline MARKER FROM TO — the adopt-mcp.sh line ending in MARKER with its ONE
# occurrence of FROM replaced by TO (split on FROM, never ${var/pat/rep}: see
# CLAUDE.md's `&` trap). Fails when the line or FROM is not there exactly once.
_mline() {
  local line="" n=""
  line="$(awk -v m="$1" '{ L = length($0); K = length(m); if (L >= K && substr($0, L - K + 1) == m) print }' "$REPO_ROOT/scripts/lib/adopt/adopt-mcp.sh")"
  n="$(printf '%s\n' "$line" | grep -c .)"; [ "$n" = 1 ] || return 1
  case "$line" in *"$2"*"$2"*) return 1 ;; *"$2"*) ;; *) return 1 ;; esac
  printf '%s%s%s' "${line%%"$2"*}" "$3" "${line#*"$2"}"
}
mut_sub() {   # LABEL MARKER FROM TO CASE-FN WANT — mut, on a line built by _mline
  local repl=""
  repl="$(_mline "$2" "$3" "$4")" || { fail_ "$1" "the mutant line could not be built (marker $2, '$3' not there exactly once)"; return; }
  mut "$1" scripts/lib/adopt/adopt-mcp.sh "$2" "$repl" "$5" "$6"
}
# mut_doc LABEL N REPLACEMENT-FILE CASE-FN WANT — the Nth sh block of
# "Recreating an exposed Qdrant container", in a mirror's docs/adoption.md,
# becomes REPLACEMENT-FILE; the replacement must land, and must change it.
_mutate_doc_block() {   # FILE N REPLACEMENT-FILE
  awk -v n="$2" -v rf="$3" '
    /^## Recreating an exposed Qdrant container$/ { on = 1 }
    on && /^## / && !/^## Recreating an exposed Qdrant container$/ { on = 0 }
    on && /^```sh$/ { k++; if (k == n) { print; while ((getline l < rf) > 0) print l; skip = 1; next } }
    skip && /^```$/ { skip = 0; print; next }
    skip { next }
    { print }' "$1" > "$1.mut" && mv "$1.mut" "$1" || { echo "awk failed"; return 1; }
  _doc_block "$2" "$1" | cmp -s - "$3" || { echo "replacement not found"; return 1; }
  return 0
}
mut_doc() {
  local label="$1" n="$2" rf="$3" m="$WORK/mutdoc-$2" r=""
  { _mirror_fw "$m" && mkdir -p "$m/docs" && cp -p "$REPO_ROOT/docs/adoption.md" "$m/docs/"; } || { fail_ "$label" "could not mirror the framework"; return; }
  if _doc_block "$n" "$m/docs/adoption.md" | cmp -s - "$rf"; then fail_ "$label" "the mutation is a no-op: block $n already reads that way"; return; fi
  r="$(_mutate_doc_block "$m/docs/adoption.md" "$n" "$rf")" || { fail_ "$label" "the mutation did not apply ($r)"; return; }
  _mut_judge "$label" "$m" "$4" "$5"
}

if [ "${BL311_SKIP_MUTANTS:-0}" = "1" ]; then skip "M1-M153" "BL311_SKIP_MUTANTS=1"; _done; fi
echo "== M — mutation proofs =="
mut "M1 helpers-core ignores CLAUDE_CONFIG_DIR for settings.json — killed by A4" \
  scripts/lib/helpers-core.sh '# BL-311-CONFIG-DIR' \
  '  printf '"'"'%s'"'"' "$HOME/.claude"   # BL-311-CONFIG-DIR' \
  a4 'plugin in'
mut "M2 helpers-core ignores CLAUDE_CONFIG_DIR for .claude.json — killed by A1" \
  scripts/lib/helpers-core.sh '# BL-311-CONFIG-JSON' \
  '  printf '"'"'%s/.claude.json'"'"' "$HOME"   # BL-311-CONFIG-JSON' \
  a1 '[context7 not seen]'
mut "M3 qdrant_mcp_reg_file back on fixed paths — killed by A1" \
  scripts/lib/helpers-full.sh '# BL-311-QDRANT-REG-FILE' \
  '  for f in "$HOME/.claude.json" "$HOME/.claude/settings.json"; do   # BL-311-QDRANT-REG-FILE' \
  a1 '[reg file is not'
mut "M4 the SessionStart hook back on fixed paths — killed by A5" \
  scripts/session-test-gate-check.sh '# BL-311-GATE-CONFIG' \
  '  _cc_set="$HOME/.claude/settings.json"; _cc_json="$HOME/.claude.json"   # BL-311-GATE-CONFIG' \
  a5 'A5 — requirements'
mut "M5 probe-tool back on fixed paths — killed by A6" \
  scripts/probe-tool.sh '# BL-311-PROBE-CONFIG' \
  '  printf '"'"'%s\n%s\n'"'"' "$HOME/.claude/settings.json" "$HOME/.claude.json"   # BL-311-PROBE-CONFIG' \
  a6 'an [OK] row for a server the session does not have'
mut "M6 check-versions says 'not installed' for an MCP row — killed by A6" \
  scripts/check-versions.sh '# BL-311-CV-NOT-REGISTERED' \
  '      print_warn "$NAME: not installed${CHECK_NOTE:+ — $CHECK_NOTE}"   # BL-311-CV-NOT-REGISTERED' \
  a6 'Qdrant not reported NOT registered'
mut "M7 the question asked with nothing to do — killed by S1" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-ASK-ONLY-IF-ACTIONABLE' \
  '  if [ 1 -gt 0 ]; then            # BL-311-MCP-ASK-ONLY-IF-ACTIONABLE' \
  s1 'asked, or ran, with nothing missing'
mut "M8 no answer refuses, like a mandatory question — killed by S6" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-EOF-SKIP' \
  '    if false; then                                   # BL-311-MCP-EOF-SKIP' \
  s6 'end of input not treated as skip'
mut "M9 the commands not shown before the question — killed by S2" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-SHOWN-FIRST' \
  '    :   # BL-311-MCP-SHOWN-FIRST' \
  s2 'not shown before the question: claude mcp add context7'
mut "M10 the commands run from the adoptee, not the work dir — killed by S2" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-RUN' \
  '  ( run_with_deadline "$secs" bash -c "$cmd" ) </dev/null >>"$ADOPT_WORK/mcp-setup.out" 2>&1 || rc=$?   # BL-311-MCP-RUN' \
  s2 'a command ran with the adoptee as its cwd'
mut "M11 the receipt assumes success — killed by S7" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-RECEIPT' \
  '    st="registered reachable http://localhost:6333"   # BL-311-MCP-RECEIPT' \
  s7 'result claims a setup'
mut "M12 the Addendum's argument order (name after -e) — killed by S2" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-QDRANT-ADD' \
  "ADOPT_MCP_QDRANT_ADD='claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant'   # BL-311-MCP-QDRANT-ADD" \
  s2 'the registrations are not in'
mut "M13 registered without waiting for the database — killed by S9" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-WAIT-BEFORE-REGISTER' \
  '            :   # BL-311-MCP-WAIT-BEFORE-REGISTER' \
  s9 'Qdrant was registered with no database behind it'
mut "M14 the every-edit-is-blocked sentence dropped — killed by S3" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-NOTE-BLOCKS' \
  '      :   # BL-311-MCP-NOTE-BLOCKS' \
  s3 'the note does not say every edit is blocked'
mut "M15 the check-is-off sentence dropped — killed by S4" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-NOTE-OFF' \
  '      :   # BL-311-MCP-NOTE-OFF' \
  s4 'the note does not say the check is off'
mut "M16 init.sh's container arm restored in the session layer — killed by E6" \
  scripts/lib/adopt/adopt-session.sh '# BL-311-SESSION-QDRANT-PREDICATE' \
  '    is_qdrant_mcp_entry_present && exit 0; is_qdrant_container_running && command -v uvx >/dev/null 2>&1 ) >/dev/null 2>&1   # BL-311-SESSION-QDRANT-PREDICATE' \
  e6 'a Qdrant declaration was written'
mut "M17 the restart sentence not printed — killed by E1b" \
  scripts/lib/adopt/adopt-state.sh '# BL-311-ACT2-RESTART-CALL' \
  '  :   # BL-311-ACT2-RESTART-CALL' \
  e1 "restart line at 'absent'"
mut "M18 the Record row dropped — killed by E1" \
  scripts/lib/adopt/adopt-record.sh '# BL-311-MCP-RECORD' \
  '    :   # BL-311-MCP-RECORD' \
  e1 "record row: ''"
mut "M19 the step not called — killed by E1" \
  scripts/lib/adopt/adopt-state.sh '# BL-311-MCP-CALL' \
  '  :   # BL-311-MCP-CALL' \
  e1 'not recorded'
mut "M20 the Docker probe keeps the operator's stdin — killed by E2" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-DOCKER-STDIN' \
  '  run_with_deadline 5 docker info >/dev/null 2>&1   # BL-311-MCP-DOCKER-STDIN' \
  e2 "a command read the operator's answers"

mut "M21 the markers not raised when the tree changed — killed by S10" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-TOUCHED-ON-CHANGE' \
  '      :   # BL-311-MCP-TOUCHED-ON-CHANGE' \
  s10 'markers not raised when a command changed the tree'
mut "M22 the markers raised on the attempt, as the resolver does — killed by S10" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-TOUCHED-IF' \
  '    if true; then   # BL-311-MCP-TOUCHED-IF' \
  s10 'markers raised over a tree the commands did not change'
mut "M23 the test seam ignored — killed by S11" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-SEAM' \
  '  if false; then           # BL-311-MCP-SEAM' \
  s11 'asked with the seam off'
mut "M24 the resolver's order swapped (1 would mean set it up) — killed by S12" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-RESOLVE-ORDER' \
  '      ans="$(adopt_resolve_choice "$raw" "$ADOPT_MCP_SETUP" "$ADOPT_MCP_SKIP")"   # BL-311-MCP-RESOLVE-ORDER' \
  s12 'answer 1 ran commands'
mut "M25 the offer's order swapped (set it up listed first) — killed by E7" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OFFER-ORDER' \
  '    adopt_offer_choice "Set them up now? (No answer means skip it.)" "$ADOPT_MCP_SETUP" "$ADOPT_MCP_SKIP"   # BL-311-MCP-OFFER-ORDER' \
  e7 'the MCP question does not list 1) skip it'
mut "M26 a failed docker run does not stop the Qdrant chain — killed by S15" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-FAIL-STOPS-QDRANT' \
  '        :   # BL-311-MCP-FAIL-STOPS-QDRANT' \
  s15 'Qdrant was registered after its container failed to start'
mut "M27 the npx precondition removed — killed by S14" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-NPX-PRECONDITION' \
  '    elif false; then c7_why=""   # BL-311-MCP-NPX-PRECONDITION' \
  s14 'offered Context7 with no npx to launch it'
mut "M28 a failed launch not recognised — killed by S16" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-LAUNCH-FAILED' \
  '  if false; then       # BL-311-MCP-LAUNCH-FAILED' \
  s16 'the block is not said'
mut "M29 the launch block not said — killed by S16" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-NOTE-LAUNCH' \
  '  if false; then   # BL-311-MCP-NOTE-LAUNCH' \
  s16 'the block is not said'
mut "M30 verify-install's Qdrant row back on fixed paths — killed by A7" \
  scripts/verify-install.sh '# BL-311-VERIFY-QDRANT' \
  '  if ([ -f "$HOME/.claude/settings.json" ] && jq -e ".mcpServers.qdrant // empty" "$HOME/.claude/settings.json" >/dev/null 2>&1) || ([ -f "$HOME/.claude.json" ] && jq -e ".mcpServers.qdrant // empty" "$HOME/.claude.json" >/dev/null 2>&1); then   # BL-311-VERIFY-QDRANT' \
  a7 'registered in $CLAUDE_CONFIG_DIR/.claude.json, not seen'
mut "M31 the reminder back on fixed paths — killed by A8" \
  scripts/session-end-qdrant-reminder.sh '# BL-311-REMINDER-CONFIG' \
  '  _cc_set="$HOME/.claude/settings.json"; _cc_json="$HOME/.claude.json"   # BL-311-REMINDER-CONFIG' \
  a8 'registered in $CLAUDE_CONFIG_DIR, no reminder'
mut "M34 Context7's launch-failed block not said — killed by S17" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-NOTE-LAUNCH-C7' \
  '  if false; then                                          # BL-311-MCP-NOTE-LAUNCH-C7' \
  s17 'the Context7 block is not said'
mut "M35 Qdrant's could-not-be-checked note not said — killed by S18" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-NOTE-UNCHECKED' \
  '  if false; then   # BL-311-MCP-NOTE-UNCHECKED' \
  s18 'the Qdrant unchecked note is not said'
mut "M36 Context7's could-not-be-checked note not said — killed by S18" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-NOTE-UNCHECKED-C7' \
  '  if false; then   # BL-311-MCP-NOTE-UNCHECKED-C7' \
  s18 'the Context7 unchecked note is not said'
mut "M37 the early return ignores the launch check — killed by S16" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-EARLY-RETURN' \
  '  if [ "$c7" = "registered" ] && [ "$q" = "reachable" ]; then   # BL-311-MCP-EARLY-RETURN' \
  s16 'the block is not said'
mut "M38 the Failed-to-connect match broken — killed by S16" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-LAUNCH-FAILED' \
  "  if grep -q 'Status:.*Failed to konnect' \"\$out\" 2>/dev/null; then       # BL-311-MCP-LAUNCH-FAILED" \
  s16 'the block is not said'
mut "M39 the launch check run bare (no subshell, no </dev/null) — killed by E2" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-LAUNCH-STDIN' \
  '  run_with_deadline "$secs" claude mcp get "$name" >"$out" 2>&1 || rc=$?   # BL-311-MCP-LAUNCH-STDIN' \
  e2 "a command read the operator's answers"
# M40: since round 14 the any-other-address arm catches what the DEFAULT arm
# misses, so the mutant prints a note in the WRONG words — killed by the wording.
mut "M40 an empty HostIp never detected — killed by S19" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-DETECT-DEFAULT' \
  '  elif false; then   # BL-311-MCP-OPEN-DETECT-DEFAULT' \
  s19 'an empty HostIp is not worded as the daemon default'
mut "M41 open bindings always reported — killed by S20" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-DETECT' \
  '  elif true; then   # BL-311-MCP-OPEN-DETECT' \
  s20 'a loopback-bound container was reported as open'
mut "M42 the open-bindings note not said — killed by S19" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-SAY' \
  '  :   # BL-311-MCP-OPEN-SAY' \
  s19 'the open-bindings note is not said before the question'
mut "M43 the unregistered arm's docker start hint without the note — killed by S19" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-HINT-UNREGISTERED' \
  '      :   # BL-311-MCP-OPEN-HINT-UNREGISTERED' \
  s19 'the later docker start hint does not carry the note'
mut "M44 (X1) 0.0.0.0 not detected — killed by S19e" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-DETECT' \
  '  elif false; then   # BL-311-MCP-OPEN-DETECT' \
  s19e 'HostIp 0.0.0.0 not reported'
mut "M45 (X2) :: not detected — killed by S19f" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-DETECT-V6' \
  '  elif false; then   # BL-311-MCP-OPEN-DETECT-V6' \
  s19f 'HostIp :: not reported'
mut "M46 (X3/X4) the one hoisted read dropped — killed by S19c (the already-answering path)" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-HOIST' \
  '      if _adopt_mcp_qdrant_container; then q_ctr=1; fi   # BL-311-MCP-HOIST' \
  s19c 'the note is not said when the database already answers'
mut "M47 (R-15) the hoisted read dropped — killed by S19d (this host's state)" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-HOIST' \
  '      if _adopt_mcp_qdrant_container; then q_ctr=1; fi   # BL-311-MCP-HOIST' \
  s19d 'the note is not said when everything is registered and answering'
mut "M48 (X5) the unreachable arm's docker start hint without the note — killed by S19b" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-HINT-UNREACHABLE' \
  '        :   # BL-311-MCP-OPEN-HINT-UNREACHABLE' \
  s19b "the unreachable arm's docker start hint does not carry the note"
mut "M49 (R-15) bindings that could not be read are not said — killed by S19g" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-UNREAD-HINT' \
  '      :   # BL-311-MCP-UNREAD-HINT' \
  s19g 'the docker start hint does not say the bindings could not be read'
mut "M53 (R-16) an empty HostIp asserted as verified exposure — killed by S19" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-DEFAULT-BIND-WORDING' \
  '      adopt_note "publishes on every network interface, so it IS reachable from your network"   # BL-311-MCP-DEFAULT-BIND-WORDING' \
  s19 'an empty HostIp is not worded as the daemon default'
mut "M54 (R-16) the pre-28.0.0 caveat dropped — killed by S19" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-MOBY-CAVEAT' \
  '  :   # BL-311-MCP-MOBY-CAVEAT' \
  s19 'the pre-28.0.0 caveat is missing'
mut "M56 (R-2/N2) a failed inspect defaults to loopback — killed by S25" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-INSPECT-FAILCLOSED' \
  '  ADOPT_MCP_QDRANT_BIND="loopback"; ADOPT_MCP_QDRANT_BIND_WHY=""   # BL-311-MCP-INSPECT-FAILCLOSED' \
  s25 'the could-not-be-read hint is missing'
mut "M61 (R-6) an API key never detected — killed by S27" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-KEY-DETECT' \
  '    if false; then   # BL-311-MCP-KEY-DETECT' \
  s27 'the API key is not recognised'
mut "M68 (R-439-4) the environment-only key reading worded as fact — killed by S19" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-KEY-WORDING' \
  '    unset) key="it has NO API key, so anything that reaches it can read your session memory" ;;   # BL-311-MCP-KEY-WORDING' \
  s19 'the absence of an API key is not worded as read from its environment only'
# M50-M52, M55, M57, M60, M67, M83-M84, M87, M89, M94-M98 and M103-M134 pinned
# the recreate adoption printed until round 12 — the volume/bind recreate, its
# quoting, its way back, the allow-list and every read that fed it (mounts,
# tmpfs keys and their path cleaning, --rm, the image, volume options, --mount
# settings, the running container's /proc/mounts). Round 13 removed the
# recreate for every container, so that code, its cases and these mutants are
# gone. M135-M136 pin what replaced it.
mut "M135 (round 13) a recreate line printed again — killed by S29" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-CHANGED-NOTHING' \
  '  adopt_note "  docker rm -f qdrant &&"; adopt_note "Adoption changed nothing about this container, and prints no commands to recreate"   # BL-311-MCP-CHANGED-NOTHING' \
  s29 'the note prints a command'
mut "M136 (round 13) the pointer to the written procedure dropped — killed by S29" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-POINTER' \
  '    :   # BL-311-MCP-POINTER' \
  s29 'the pointer to the written procedure is missing'

# M137-M147 (round 14): R-BL311-2's four survivors, R-BL311-4's three new arms,
# R-BL311-5's letter case, and R-BL311-1/-3 in the written procedure itself.
mut_sub "M137 (R-BL311-2) 0.0.0.0 detected only when EVERY binding names it (any → all) — killed by S30" \
  '# BL-311-MCP-OPEN-DETECT' 'any(. == "0.0.0.0")' 'all(. == "0.0.0.0")' \
  s30 'a 0.0.0.0 binding beside a loopback one is not reported as every interface'
mut_sub "M138 (R-BL311-2) an empty HostIp detected only when EVERY binding has one (any → all) — killed by S31" \
  '# BL-311-MCP-OPEN-DETECT-DEFAULT' 'any(. == "")' 'all(. == "")' \
  s31 'an empty HostIp beside a loopback one is not reported as the daemon default'
mut_sub "M139 (R-BL311-2) the API-key pattern loses its '.', so an EMPTY value is a key — killed by S32" \
  '# BL-311-MCP-KEY-DETECT' 'API_KEY=."' 'API_KEY="' \
  s32 'an EMPTY API key was read as a key'
mut "M140 (R-BL311-2) an answer that does not parse is not caught, and falls through to loopback — killed by S33" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-BIND-PARSE' \
  '  if false; then   # BL-311-MCP-BIND-PARSE' \
  s33 'unparseable bindings are not said to be unreadable'
mut "M141 (R-BL311-4) -P not detected — killed by S34" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-DETECT-PUBLISH-ALL' \
  '  elif false; then   # BL-311-MCP-OPEN-DETECT-PUBLISH-ALL' \
  s34 '-P is not reported at all'
mut "M142 (R-BL311-4) --network host not detected — killed by S35" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-DETECT-HOST' \
  '  elif false; then   # BL-311-MCP-OPEN-DETECT-HOST' \
  s35 'the host network is not reported at all'
mut "M143 (R-BL311-4) an address other than loopback not detected — killed by S36" \
  scripts/lib/adopt/adopt-mcp.sh '# BL-311-MCP-OPEN-DETECT-ADDR' \
  '  elif false; then   # BL-311-MCP-OPEN-DETECT-ADDR' \
  s36 'a LAN address is not reported at all'
mut_sub "M144 (R-BL311-5) the key's name matched in upper case only — killed by S37" \
  '# BL-311-MCP-KEY-DETECT' '; "i")' ')' \
  s37 'a lowercase API key is not recognised'
mut_sub "M147 (R-BL311-4) ::1 read as an address other than loopback — killed by S20" \
  '# BL-311-MCP-OPEN-DETECT-ADDR' 'any(. != "127.0.0.1" and . != "::1")' 'any(. != "127.0.0.1")' \
  s20 'a ::1 binding was reported as open'
# M148-M150 (round 15, R-BL311-8): the reviewer's K5, K6 and K15 — each part of
# `# BL-311-MCP-BIND-PARSE` that S33 alone left unpinned.
mut_sub "M148 (R-BL311-8, K5) the PublishAllPorts type check dropped — killed by S33b" \
  '# BL-311-MCP-BIND-PARSE' ' and (.[1] | type == "boolean")' '' \
  s33b '(null) a PublishAllPorts of null: not said to be unreadable'
mut_sub "M149 (R-BL311-8, K6) the NetworkMode type check dropped — killed by S33c" \
  '# BL-311-MCP-BIND-PARSE' ' and (.[2] | type == "string")' '' \
  s33c '(null) a NetworkMode of null: not said to be unreadable'
mut_sub "M150 (R-BL311-8, K15) the count loosened (length == 3 → length >= 1) — killed by S33c" \
  '# BL-311-MCP-BIND-PARSE' 'length == 3' 'length >= 1' \
  s33c '(two values) a NetworkMode line with two values: not said to be unreadable'
# M145: step 2 as it was before round 14 — no jq check, no count — the block
# that printed ALL SNAPSHOTS PRESENT over an empty list and lost the data.
cat > "$WORK/m145.block" <<'M145'
m=0; [ -s "$B/aliases.json" ] && [ -s "$B/collections.json" ] || { echo "STEP 1 DID NOT FINISH"; m=1; }
while IFS= read -r c; do [ -s "$B/$c.snapshot" ] || { echo "MISSING: $c"; m=1; }; done < "$B/collections.txt"; [ "$m" = 0 ] && echo "ALL SNAPSHOTS PRESENT"
M145
mut_doc "M145 (R-BL311-1) step 2 back to its round-13 text — killed by S38 (c)" \
  3 "$WORK/m145.block" \
  s38 "(c) jq missing and step 1's collections.txt empty: step 2 still printed ALL SNAPSHOTS PRESENT"
# M146: step 6 with its key check removed — the first line gone and nothing
# waiting on it; every other character as the doc prints it.
_doc_block 7 "$REPO_ROOT/docs/adoption.md" | sed -n '2,$p' | awk '{ p = "[ \"$k\" = 0 ] && "; if (index($0, p) == 1) $0 = substr($0, length(p) + 1); print }' > "$WORK/m146.block"
mut_doc "M146 (R-BL311-3) step 6 without the request made without the key — killed by S38 (d)" \
  7 "$WORK/m146.block" \
  s38 '(d) the key was lost and step 6 still printed a success line'
# M151-M153 (round 15). M151: step 2's per-collection check back to the
# non-empty test (R-BL311-7) — every other line as the doc prints it, so the
# jq and checksum-tool checks stay and ONLY the size/sha256 comparison goes;
# S38 (f) must kill it, not only S28's text pin. M152: step 1 reads the old
# container at Q again instead of docker port's address (R-BL311-9). M153: step
# 5 waits on the OLD address, which never answers after step 4 (R-BL311-9) —
# the stand-in ends that run after five refused connections.
_doc_block 3 "$REPO_ROOT/docs/adoption.md" | awk '
  /^while IFS= read -r c; do$/ { print "while IFS= read -r c; do [ -s \"$B/$c.snapshot\" ] || { echo \"MISSING: $c\"; m=1; }; done < \"$B/collections.txt\"; [ \"$m\" = 0 ] && echo \"ALL SNAPSHOTS PRESENT\""; skip = 1; next }
  skip && /^done < / { skip = 0; next }
  skip { next }
  { print }' > "$WORK/m151.block"
mut_doc "M151 (R-BL311-7) step 2 checks only that each snapshot is not empty — killed by S38 (f)" \
  3 "$WORK/m151.block" \
  s38 '(f) a partial snapshot of the LAST collection: step 2 still printed ALL SNAPSHOTS PRESENT'
_doc_block 2 "$REPO_ROOT/docs/adoption.md" | awk 'NR == 2 { print "O=\"$Q\""; next } { print }' > "$WORK/m152.block"
mut_doc "M152 (R-BL311-9) step 1 reads the old container at Q, not where docker port says — killed by S38 (h)" \
  2 "$WORK/m152.block" \
  s38 '(h) -P (docker port 0.0.0.0:32768): step 1 did not reach the old container where docker port said'
_doc_block 6 "$REPO_ROOT/docs/adoption.md" | awk 'NR == 1 { f = "\"$Q/collections\""; i = index($0, f); if (i) $0 = substr($0, 1, i - 1) "\"$O/collections\"" substr($0, i + length(f)) } { print }' > "$WORK/m153.block"
mut_doc "M153 (R-BL311-9) step 5 waits for the new container at the OLD address — killed by S38 (h)" \
  6 "$WORK/m153.block" \
  s38 '(h) step 5 waited on the OLD address'

_done

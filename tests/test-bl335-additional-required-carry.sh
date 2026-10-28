#!/usr/bin/env bash
# tests/test-bl335-additional-required-carry.sh
#
# BL-335 (issue #484) — scripts/session-test-gate-check.sh's MCP SERVER NOTICE
# tells the Orchestrator to add a server under
# mcp_requirements.additional_required in .claude/tool-usage.json, and
# scripts/session-mcp-gate.sh enforces that list (`# BL-233-ADDITIONAL-OUTCOME`).
# The startup heredoc and the merge path's jq-failure fallback wrote
# `"additional_required": []`, so an entry lasted until the next fresh session
# and then went without a word. Karl's decision (2026-10-08): carry the list
# across the startup rewrite. It is a REQUIREMENT, not a satisfaction, so the
# startup still drops the outcome flags and empties calls[] (BL-236).
#
# Cases:
#   S1  startup keeps a valid list, and says nothing about it.
#   S2  resume, S3 compact, S4 clear keep it (unchanged behaviour).
#   S5  startup still resets calls[], the outcome flags and the latch.
#   S6  a carried requirement whose tool succeeded LAST session still blocks
#       the first Write; the same tool succeeding this session allows it.
#   S7  an empty list stays empty, an absent one is written empty, no note.
#   S8  junk entries (empty string, number, null, object, list) are dropped
#       with one note line; the next start is silent. S8b: a list that is not
#       a list. S8r: the same on resume.
#   S9  entries carrying quotes, backslashes, `$(...)` and `$HOME` are carried
#       byte for byte and nothing in them runs.
#   S10 the merge fails (jq refuses the merge filter): the fallback keeps it.
#   S11 a ledger that is not valid JSON (resume, then startup): rewritten, and
#       one line names the entries it listed.
#   S12 jq missing at startup: the ledger is removed as before (BL-314) and one
#       line names the entries; S12b an empty list and S12d a value that is
#       not a list print nothing; S12c a long list is cut short.
#   S13 the ledger writer missing at startup: the same, naming the writer.
#   R1  entries jq's test() cannot compile (`*sentry*`, `[unclosed`) are dropped
#       with the same note: carried, they would refuse every Write of every
#       session.
#   L1  a 600 KB ledger, lib-less, list cut off with no `]`: the start ends in
#       bounded time, the ledger is removed, the gate denies.
#   L2  a 600 KB ledger with one stray `}` (jq then reads only the first
#       document): bounded time, reset, gate denies, and the note names both
#       entries although one holds a `]` inside its quotes.
#   B1  the list FIRST in a 570 KB broken ledger: still named, and the scan
#       is fed at most 64 KB, starting at the list's key.
#   T1  the real tracker writes a 70 KB last_mcp_error AFTER the list: a valid
#       ledger carries the list; broken by a stray `}` (with jq) or read
#       lib-less, the note still names both entries.
#   T3  a list whose closing `]` lies past the 64 KB window: the note says it
#       was cut off and must be added again — never silence.
#   F1  a FIFO at the ledger path: the lib-less start does not block on it.
#   T4  a string value ENDING in `"additional_required` (an error message)
#       sits before the real key: the key is found as a key, and the note
#       names the list (stray `}` with jq, and lib-less).
#   K1  the scan is cancelled mid-run (lib-less): the ledger was already
#       removed, so the gate denies. K2: the same on the stray-`}` ledger with
#       jq: it was already reset.
#   M*  mutation proofs, each killed by the case it names.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/session-test-gate-check.sh"
GATE="$REPO_ROOT/scripts/session-mcp-gate.sh"
TRACKER="$REPO_ROOT/scripts/track-tool-usage.sh"
BASH_BIN="$(command -v bash)"
[ -n "$BASH_BIN" ] || BASH_BIN="/bin/bash"
REAL_JQ="$(command -v jq)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if [ -z "$REAL_JQ" ]; then
  echo "jq is required to run this suite"; exit 1
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# A PATH with what the hook needs and no jq (S12). /usr/bin/jq ships with
# macOS, so dropping a directory from PATH is not enough.
NOJQ_BIN="$TOPTMP/nojq-bin"
mkdir -p "$NOJQ_BIN"
for c in cat date mkdir rm rmdir mv mktemp stat sleep sort grep tr dirname tail head awk; do
  p="$(type -P "$c")"
  if [ -z "$p" ]; then echo "fixture: $c not found"; exit 1; fi
  ln -s "$p" "$NOJQ_BIN/$c"
done

# A jq that refuses the merge filter and runs every other one (S10).
SHIM_BIN="$TOPTMP/shim-bin"
mkdir -p "$SHIM_BIN"
cat > "$SHIM_BIN/jq" <<EOF
#!/bin/sh
case "\$*" in *'.session_id = \$sid'*) exit 5 ;; esac
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$SHIM_BIN/jq"

# An awk that records its pid and then hangs (K1, K2): the hook is cancelled
# while it waits on the scan. And one that keeps a copy of what it is fed (B1).
REAL_AWK="$(type -P awk)"
HANG_BIN="$TOPTMP/hang-bin"; mkdir -p "$HANG_BIN"
printf '#!/bin/sh\necho $$ > "$HANG_MARK"\nexec sleep 30\n' > "$HANG_BIN/awk"
chmod +x "$HANG_BIN/awk"
TEE_BIN="$TOPTMP/tee-bin"; mkdir -p "$TEE_BIN"
printf '#!/bin/sh\ntee "$AWK_IN" | "$REAL_AWK" "$@"\n' > "$TEE_BIN/awk"
chmod +x "$TEE_BIN/awk"

N=0
# mkp LEDGER-JSON-OR-TEXT — a project whose ledger is the argument, and a
# private HOME with no MCP servers, so qdrant and context7 are not required
# and the extra list alone decides the gate.
mkp() {
  N=$((N + 1))
  T="$TOPTMP/c$N"; P="$T/p"
  mkdir -p "$P/.claude" "$T/home"
  printf '%s\n' "$1" > "$P/.claude/tool-usage.json"
}
LEDGER() {   # LIST-JSON — a ledger as a previous session left it
  printf '{"session_id":"2026-01-01T00:00:00Z","calls":[{"tool":"mcp__foo__bar","outcome":"success"}],"commits_since_last_context7":3,"qdrant_find_called":true,"qdrant_find_succeeded":true,"context7_called":true,"context7_query_docs_succeeded":true,"mcp_gate_satisfied":true,"mcp_requirements":{"qdrant_required":false,"context7_required":false,"additional_required":%s}}' "$1"
}

# run_hook HOOK SOURCE [PATH] — HOOK_OUT (stdout), HOOK_RC.
run_hook() {
  local path="${3:-$PATH}"
  HOOK_RC=0
  HOOK_OUT=$( cd "$P" && printf '{"hook_event_name":"SessionStart","source":"%s"}' "$2" \
      | env -i HOME="$T/home" PATH="$path" "$BASH_BIN" "$1" 2>/dev/null ) || HOOK_RC=$?
}
gate_run() {   # GATE_OUT (the gate's stdout), GATE_DEC (deny | allow)
  GATE_OUT=$( cd "$P" && printf '{"tool_name":"Write"}' \
      | env -i HOME="$T/home" PATH="$PATH" "$BASH_BIN" "$GATE" 2>/dev/null )
  if grep -qF '"permissionDecision": "deny"' <<<"$GATE_OUT"; then GATE_DEC=deny; else GATE_DEC=allow; fi
}
track_success() {   # TOOL — the real tracker records a successful call
  ( cd "$P" && printf '{"hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{},"tool_response":[{"type":"text","text":"ok"}]}\n' "$1" \
      | env -i HOME="$T/home" PATH="$PATH" "$BASH_BIN" "$TRACKER" --event PostToolUse >/dev/null 2>&1 )
}
LIST() { jq -c '.mcp_requirements.additional_required' "$P/.claude/tool-usage.json" 2>/dev/null; }
notes() { grep -c '^MCP REQUIREMENTS NOTE:' <<<"$HOOK_OUT"; }
note() { grep '^MCP REQUIREMENTS NOTE:' <<<"$HOOK_OUT"; }

# Each case takes the hook to test and returns 0 on pass, with DETAIL set on
# failure, so the mutation proofs below can run the same case on a mutant.
DETAIL=""
c_S1() {
  mkp "$(LEDGER '["mcp__foo__bar","mcp__sentry__.*"]')"; run_hook "$1" startup
  local l; l=$(LIST)
  DETAIL="rc=$HOOK_RC list=$l notes=$(notes) (want rc 0, [\"mcp__foo__bar\",\"mcp__sentry__.*\"], 0 notes)"
  [ "$HOOK_RC" = 0 ] && [ "$l" = '["mcp__foo__bar","mcp__sentry__.*"]' ] && [ "$(notes)" = 0 ]
}
c_merge() {   # HOOK SOURCE
  mkp "$(LEDGER '["mcp__foo__bar"]')"; run_hook "$1" "$2"
  local l c; l=$(LIST); c=$(jq '.calls | length' "$P/.claude/tool-usage.json" 2>/dev/null)
  DETAIL="rc=$HOOK_RC list=$l calls=$c (want 0, [\"mcp__foo__bar\"], 1)"
  [ "$HOOK_RC" = 0 ] && [ "$l" = '["mcp__foo__bar"]' ] && [ "$c" = 1 ]
}
c_S5() {
  mkp "$(LEDGER '["mcp__foo__bar"]')"; run_hook "$1" startup
  local r; r=$(jq -c '[(.calls | length), (.qdrant_find_succeeded // false), (.context7_query_docs_succeeded // false), .mcp_gate_satisfied, .commits_since_last_context7]' "$P/.claude/tool-usage.json" 2>/dev/null)
  DETAIL="[calls, qdrant_ok, c7_ok, latch, commits]=$r (want [0,false,false,false,0])"
  [ "$r" = '[0,false,false,false,0]' ]
}
c_S6() {
  mkp "$(LEDGER '["mcp__foo__bar"]')"; run_hook "$1" startup
  local d1 named=no d2
  gate_run; d1=$GATE_DEC
  grep -qF 'mcp__foo__bar (required MCP tool has not returned successfully this session)' <<<"$GATE_OUT" && named=yes
  track_success mcp__foo__bar
  gate_run; d2=$GATE_DEC
  DETAIL="first_write=$d1 names_tool=$named after_call=$d2 (want deny yes allow)"
  [ "$d1" = deny ] && [ "$named" = yes ] && [ "$d2" = allow ]
}
c_S7() {
  mkp "$(LEDGER '[]')"; run_hook "$1" startup
  local a n1; a=$(LIST); n1=$(notes)
  mkp '{"session_id":"x","calls":[]}'; run_hook "$1" startup
  local b; b=$(LIST)
  DETAIL="empty->$a absent->$b notes=$n1/$(notes) (want [] [] 0/0)"
  [ "$a" = '[]' ] && [ "$b" = '[]' ] && [ "$n1" = 0 ] && [ "$(notes)" = 0 ]
}
c_S8() {
  mkp "$(LEDGER '["mcp__ok", "", 3, null, {"a":1}, ["x"]]')"; run_hook "$1" startup
  local l n rc1 says=no; l=$(LIST); n=$(notes); rc1=$HOOK_RC
  note | grep -qF '5 value(s) under mcp_requirements.additional_required' && says=yes
  run_hook "$1" startup
  DETAIL="rc=$rc1 list=$l notes=$n says_5=$says next_start_notes=$(notes) list_after=$(LIST) (want 0 [\"mcp__ok\"] 1 yes 0 [\"mcp__ok\"])"
  [ "$rc1" = 0 ] && [ "$l" = '["mcp__ok"]' ] && [ "$n" = 1 ] && [ "$says" = yes ] && [ "$(notes)" = 0 ] && [ "$(LIST)" = '["mcp__ok"]' ]
}
c_S8b() {
  mkp "$(LEDGER '"mcp__foo__bar"')"; run_hook "$1" startup
  local says=no; note | grep -qF '1 value(s)' && says=yes
  DETAIL="rc=$HOOK_RC list=$(LIST) notes=$(notes) says_1=$says (want 0 [] 1 yes)"
  [ "$HOOK_RC" = 0 ] && [ "$(LIST)" = '[]' ] && [ "$(notes)" = 1 ] && [ "$says" = yes ]
}
c_S8r() {
  mkp "$(LEDGER '["mcp__ok", ""]')"; run_hook "$1" resume
  DETAIL="rc=$HOOK_RC list=$(LIST) notes=$(notes) (want 0 [\"mcp__ok\"] 1)"
  [ "$HOOK_RC" = 0 ] && [ "$(LIST)" = '["mcp__ok"]' ] && [ "$(notes)" = 1 ]
}
c_S9() {
  local want='["mcp__a\"b","x$(touch PWNED)","back\\slash","$HOME","`touch PWNED2`"]'
  mkp "$(LEDGER "$want")"; run_hook "$1" startup
  local ran=no; { [ -e "$P/PWNED" ] || [ -e "$P/PWNED2" ]; } && ran=yes
  DETAIL="list=$(LIST) ran=$ran (want $want no)"
  [ "$(LIST)" = "$want" ] && [ "$ran" = no ]
}
c_S10() {
  mkp "$(LEDGER '["mcp__foo__bar"]')"; run_hook "$1" resume "$SHIM_BIN:$PATH"
  local c; c=$(jq '.calls | length' "$P/.claude/tool-usage.json" 2>/dev/null)
  DETAIL="rc=$HOOK_RC calls=$c list=$(LIST) (want 0, 0 = the fallback ran, [\"mcp__foo__bar\"])"
  [ "$HOOK_RC" = 0 ] && [ "$c" = 0 ] && [ "$(LIST)" = '["mcp__foo__bar"]' ]
}
c_S11() {
  local src ok=0 out=""
  for src in resume startup; do
    mkp '{"mcp_requirements": {"additional_required": ["mcp__foo__bar", "mcp__x"]}, "calls": [ '
    run_hook "$1" "$src"
    local valid=no says=no
    jq -e 'type == "object"' "$P/.claude/tool-usage.json" >/dev/null 2>&1 && valid=yes
    note | grep -qF '("mcp__foo__bar", "mcp__x"), and this session start could not carry them over because the file is not valid JSON' && says=yes
    out="$out $src:rc=$HOOK_RC,valid=$valid,list=$(LIST),notes=$(notes),names=$says"
    { [ "$HOOK_RC" = 0 ] && [ "$valid" = yes ] && [ "$(LIST)" = '[]' ] && [ "$(notes)" = 1 ] && [ "$says" = yes ]; } || ok=1
  done
  DETAIL="$out (want rc=0,valid=yes,list=[],notes=1,names=yes for both)"
  return "$ok"
}
c_S12() {
  mkp "$(printf '{"mcp_requirements": {"qdrant_required": false, "additional_required": [\n    "mcp__foo__bar",\n    "mcp__x"\n  ]},\n "calls": [{"tool": "mcp__foo__bar", "outcome": "success"}], "qdrant_find_succeeded": true}')"
  run_hook "$1" startup "$NOJQ_BIN"
  local gone=no says=no; [ -e "$P/.claude/tool-usage.json" ] || gone=yes
  note | grep -qF '("mcp__foo__bar", "mcp__x"), and this session start could not carry them over because jq is not installed, so the file was removed' && says=yes
  DETAIL="rc=$HOOK_RC removed=$gone notes=$(notes) names=$says note=[$(note)] (want 0 yes 1 yes)"
  [ "$HOOK_RC" = 0 ] && [ "$gone" = yes ] && [ "$(notes)" = 1 ] && [ "$says" = yes ]
}
c_S12b() {
  mkp "$(LEDGER '[ ]')"; run_hook "$1" startup "$NOJQ_BIN"
  DETAIL="rc=$HOOK_RC notes=$(notes) out=[$HOOK_OUT] (want 0 0)"
  [ "$HOOK_RC" = 0 ] && [ "$(notes)" = 0 ]
}
c_S12d() {
  mkp '{"mcp_requirements": {"additional_required": "mcp__foo"}, "calls": [1]}'; run_hook "$1" startup "$NOJQ_BIN"
  DETAIL="rc=$HOOK_RC notes=$(notes) out=[$HOOK_OUT] (want 0 0: a value that is not a list was never enforced)"
  [ "$HOOK_RC" = 0 ] && [ "$(notes)" = 0 ]
}
c_S12c() {
  local big; big=$("$REAL_JQ" -nc '[range(100) | "mcp__server_\(.)__tool"]')
  mkp "$(LEDGER "$big")"; run_hook "$1" startup "$NOJQ_BIN"
  local len; len=$(note | wc -c | tr -d ' ')
  DETAIL="notes=$(notes) note_length=$len (want 1, under 600)"
  [ "$(notes)" = 1 ] && [ "$len" -lt 600 ]
}
c_S13() {
  mkdir -p "$TOPTMP/nolib/scripts"; cp "$1" "$TOPTMP/nolib/scripts/session-test-gate-check.sh"
  mkp "$(LEDGER '["mcp__foo__bar"]')"; run_hook "$TOPTMP/nolib/scripts/session-test-gate-check.sh" startup
  local says=no; note | grep -qF '("mcp__foo__bar"), and this session start could not carry them over because the ledger writer cannot be loaded' && says=yes
  DETAIL="rc=$HOOK_RC notes=$(notes) names=$says (want 0 1 yes)"
  [ "$HOOK_RC" = 0 ] && [ "$(notes)" = 1 ] && [ "$says" = yes ]
}

c_R1() {
  mkp "$(LEDGER '["*sentry*", "[unclosed", "mcp__ok"]')"; run_hook "$1" startup
  local says=no d=""; note | grep -qF '2 value(s)' && says=yes
  track_success mcp__ok; gate_run; d=$GATE_DEC
  DETAIL="rc=$HOOK_RC list=$(LIST) notes=$(notes) says_2=$says after_call=$d (want 0 [\"mcp__ok\"] 1 yes allow)"
  [ "$HOOK_RC" = 0 ] && [ "$(LIST)" = '["mcp__ok"]' ] && [ "$(notes)" = 1 ] && [ "$says" = yes ] && [ "$d" = allow ]
}

# big_ledger FILE — a SATISFIED ledger of about 600 KB: both outcome flags
# true, and calls[] holding successes that match both list entries, so left
# as it is the gate ALLOWS. The list is LAST (where every ledger the framework
# writes keeps it), and the project registers qdrant and context7, so a reset
# ledger requires them and the gate denies.
big_ledger() {
  "$REAL_JQ" -n '{session_id:"x", qdrant_find_succeeded:true, context7_query_docs_succeeded:true, mcp_gate_satisfied:true,
    calls:[range(5000) | {tool:"mcp__foo__bar", outcome:"success", timestamp:"2026-01-01T00:00:00Z"}],
    mcp_requirements:{qdrant_required:true, context7_required:true, additional_required:["mcp__[a-z]+__bar", "mcp__foo__"]}}' > "$1"
  printf '{"mcpServers": {"qdrant": {"command": "uvx"}, "context7": {"command": "npx"}}}\n' > "$P/.claude/settings.local.json"
}
# run_bounded HOOK SECS [ENV=VAL…] — a startup, killed if it runs past SECS.
# Sets BND (done | overran) and HOOK_OUT. No `timeout` on macOS (CLAUDE.md).
run_bounded() {
  local h="$1" secs="$2" pid="" t0=""; shift 2
  printf '{"source":"startup"}' > "$T/env.json"
  ( cd "$P" && exec env -i HOME="$T/home" PATH="$PATH" "$@" "$BASH_BIN" "$h" < "$T/env.json" > "$T/out" 2>/dev/null ) &
  pid=$!; t0=$SECONDS; BND=done
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - t0)) -ge "$secs" ]; then BND=overran; kill -TERM "$pid" 2>/dev/null; break; fi
    sleep 0.2
  done
  wait "$pid" 2>/dev/null
  HOOK_OUT=$(cat "$T/out" 2>/dev/null)
}
nolib_copy() {   # HOOK — a copy with no lib beside it; echoes its path
  mkdir -p "$T/nolib/scripts"; cp "$1" "$T/nolib/scripts/session-test-gate-check.sh"
  printf '%s' "$T/nolib/scripts/session-test-gate-check.sh"
}
c_L1() {
  mkp '{}'; big_ledger "$T/full.json"
  head -c 600000 "$T/full.json" > "$P/.claude/tool-usage.json"   # cut inside calls[]: no list, no `]` after it
  "$REAL_JQ" -r '.mcp_requirements.additional_required | "  \"additional_required\": [ \"\(.[0])\",\n" ' "$T/full.json" >> "$P/.claude/tool-usage.json"
  local sz; sz=$(wc -c < "$P/.claude/tool-usage.json" | tr -d ' ')
  run_bounded "$(nolib_copy "$1")" 20
  local gone=no named=no; [ -e "$P/.claude/tool-usage.json" ] || gone=yes
  note | grep -qF '"mcp__[a-z]+__bar"' && named=yes
  gate_run
  DETAIL="size=$sz run=$BND removed=$gone gate=$GATE_DEC named=$named (want >=500000 done yes deny yes)"
  [ "$sz" -ge 500000 ] && [ "$BND" = done ] && [ "$gone" = yes ] && [ "$GATE_DEC" = deny ] && [ "$named" = yes ]
}
c_L2() {
  mkp '{}'; big_ledger "$T/full.json"
  { cat "$T/full.json"; echo '}'; } > "$P/.claude/tool-usage.json"
  local sz; sz=$(wc -c < "$P/.claude/tool-usage.json" | tr -d ' ')
  run_bounded "$1" 20
  local ok; ok=$("$REAL_JQ" -c '[(.qdrant_find_succeeded // false), (.calls | length)]' "$P/.claude/tool-usage.json" 2>/dev/null)
  local named=no; note | grep -qF '("mcp__[a-z]+__bar", "mcp__foo__"), and this session start could not carry them over because the file is not valid JSON' && named=yes
  gate_run
  DETAIL="size=$sz run=$BND [qdrant_ok,calls]=$ok gate=$GATE_DEC named=$named (want >=500000 done [false,0] deny yes)"
  [ "$sz" -ge 500000 ] && [ "$BND" = done ] && [ "$ok" = '[false,0]' ] && [ "$GATE_DEC" = deny ] && [ "$named" = yes ]
}
c_B1() {
  mkp '{}'; big_ledger "$T/full.json"
  "$REAL_JQ" '{mcp_requirements: .mcp_requirements} + .' "$T/full.json" > "$T/first.json"
  { cat "$T/first.json"; echo '}'; } > "$P/.claude/tool-usage.json"
  : > "$T/awk.in"
  run_bounded "$1" 20 AWK_IN="$T/awk.in" REAL_AWK="$REAL_AWK" PATH="$TEE_BIN:$PATH"
  local fed; fed=$(wc -c < "$T/awk.in" | tr -d ' ')
  local named=no; note | grep -qF '("mcp__[a-z]+__bar", "mcp__foo__")' && named=yes
  DETAIL="run=$BND bytes_fed_to_the_scan=$fed notes=$(notes) named=$named (want done, 1..65537, 1, yes)"
  [ "$BND" = done ] && [ "$fed" -gt 0 ] && [ "$fed" -le 65537 ] && [ "$(notes)" = 1 ] && [ "$named" = yes ]
}
# tracker_error_ledger — big_ledger, then the REAL tracker records a failed
# call whose error is 70 KB: last_mcp_error lands after mcp_requirements.
tracker_error_ledger() {
  big_ledger "$P/.claude/tool-usage.json"
  "$REAL_JQ" -n --arg e "$(head -c 70000 /dev/zero | tr '\0' 'e')" '{hook_event_name:"PostToolUseFailure", tool_name:"mcp__qdrant__qdrant-find", tool_input:{}, error:$e, is_interrupt:false}' > "$T/fail.json"
  ( cd "$P" && env -i HOME="$T/home" PATH="$PATH" "$BASH_BIN" "$TRACKER" --event PostToolUseFailure < "$T/fail.json" >/dev/null 2>&1 )
}
c_T1() {
  mkp '{}'; tracker_error_ledger
  local tail_ok; tail_ok=$("$REAL_JQ" -r '(keys_unsorted | index("last_mcp_error")) > (keys_unsorted | index("mcp_requirements")) and (.last_mcp_error | length) >= 70000' "$P/.claude/tool-usage.json" 2>/dev/null)
  cp "$P/.claude/tool-usage.json" "$T/err.json"
  run_hook "$1" startup; local carried; carried=$(LIST)
  { cat "$T/err.json"; echo '}'; } > "$P/.claude/tool-usage.json"; run_hook "$1" startup
  local n_jq=no; note | grep -qF '("mcp__[a-z]+__bar", "mcp__foo__")' && n_jq=yes
  cp "$T/err.json" "$P/.claude/tool-usage.json"; run_hook "$(nolib_copy "$1")" startup
  local n_nolib=no; note | grep -qF '("mcp__[a-z]+__bar", "mcp__foo__")' && n_nolib=yes
  DETAIL="error_after_list_70KB=$tail_ok carried=$carried named_stray_brace=$n_jq named_nolib=$n_nolib (want true [\"mcp__[a-z]+__bar\",\"mcp__foo__\"] yes yes)"
  [ "$tail_ok" = true ] && [ "$carried" = '["mcp__[a-z]+__bar","mcp__foo__"]' ] && [ "$n_jq" = yes ] && [ "$n_nolib" = yes ]
}
c_T3() {
  mkp '{}'
  { printf '{"mcp_requirements": {"additional_required": ["mcp__a",'; head -c 70000 /dev/zero | tr '\0' ' '; printf '"mcp__b"]}, "calls": []}}'; } > "$P/.claude/tool-usage.json"
  run_hook "$1" startup
  local cut=no; note | grep -qF 'could not read to its closing ] (it begins: "mcp__a",), and it was not carried over because the file is not valid JSON' && cut=yes
  DETAIL="rc=$HOOK_RC notes=$(notes) says_cut=$cut note=[$(note | cut -c1-200)] (want 0 1 yes)"
  [ "$HOOK_RC" = 0 ] && [ "$(notes)" = 1 ] && [ "$cut" = yes ]
}
c_T4() {
  mkp '{}'
  printf '%s\n' '{"last_mcp_error": "server said: unknown field \"additional_required", "mcp_requirements": {"qdrant_required": false, "additional_required": ["mcp__a", "mcp__b"]}, "calls": []}}' > "$T/t4.json"
  cp "$T/t4.json" "$P/.claude/tool-usage.json"; run_hook "$1" startup
  local n_jq=no; note | grep -qF '("mcp__a", "mcp__b"), and this session start could not carry them over' && n_jq=yes
  cp "$T/t4.json" "$P/.claude/tool-usage.json"; run_hook "$(nolib_copy "$1")" startup
  local n_nolib=no; note | grep -qF '("mcp__a", "mcp__b"), and this session start could not carry them over' && n_nolib=yes
  DETAIL="named_stray_brace=$n_jq named_nolib=$n_nolib (want yes yes)"
  [ "$n_jq" = yes ] && [ "$n_nolib" = yes ]
}
c_F1() {
  mkp '{}'; rm -f "$P/.claude/tool-usage.json"; mkfifo "$P/.claude/tool-usage.json"
  run_bounded "$(nolib_copy "$1")" 5
  local left=no; [ -e "$P/.claude/tool-usage.json" ] && left=yes
  if [ "$BND" = overran ]; then   # release a reader the mutant left blocked on it
    ( printf x > "$P/.claude/tool-usage.json" ) 2>/dev/null & local w=$!; sleep 0.3; kill "$w" 2>/dev/null
  fi
  DETAIL="run=$BND fifo_left=$left (want done no)"
  [ "$BND" = done ] && [ "$left" = no ]
}
# cancel_mid_scan HOOK — start the hook with the hanging awk, wait until the
# scan has begun, then cancel the hook (TERM, as Claude Code does) and the scan.
cancel_mid_scan() {
  local h="$1" pid="" i=0
  printf '{"source":"startup"}' > "$T/env.json"; : > "$T/hang.pid"
  ( cd "$P" && exec env -i HOME="$T/home" PATH="$HANG_BIN:$PATH" HANG_MARK="$T/hang.pid" "$BASH_BIN" "$h" < "$T/env.json" > /dev/null 2>&1 ) &
  pid=$!; SCAN_STARTED=no
  while [ "$i" -lt 100 ]; do
    if [ -s "$T/hang.pid" ]; then SCAN_STARTED=yes; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1; i=$((i + 1))
  done
  # TERM first. With the ledger lib's EXIT trap set, bash holds the TERM until
  # the scan's child returns, so the child is ended too; the hook then dies on
  # the held TERM before any line after the scan runs.
  kill -TERM "$pid" 2>/dev/null
  [ -s "$T/hang.pid" ] && kill "$(cat "$T/hang.pid")" 2>/dev/null
  wait "$pid" 2>/dev/null; HOOK_RC=$?
  return 0
}
c_K1() {
  mkp '{}'; big_ledger "$P/.claude/tool-usage.json"
  cancel_mid_scan "$(nolib_copy "$1")"
  gate_run
  DETAIL="scan_started=$SCAN_STARTED hook_rc=$HOOK_RC gate=$GATE_DEC (want yes 143 deny: the ledger was removed before the scan)"
  [ "$SCAN_STARTED" = yes ] && [ "$HOOK_RC" = 143 ] && [ "$GATE_DEC" = deny ]
}
c_K2() {
  mkp '{}'; big_ledger "$T/full.json"
  { cat "$T/full.json"; echo '}'; } > "$P/.claude/tool-usage.json"
  cancel_mid_scan "$1"
  gate_run
  DETAIL="scan_started=$SCAN_STARTED hook_rc=$HOOK_RC gate=$GATE_DEC (want yes 143 deny: the ledger was reset before the scan)"
  [ "$SCAN_STARTED" = yes ] && [ "$HOOK_RC" = 143 ] && [ "$GATE_DEC" = deny ]
}

c_S2() { c_merge "$1" resume; }
c_S3() { c_merge "$1" compact; }
c_S4() { c_merge "$1" clear; }

check() {   # ID TEXT
  if "c_$1" "$HOOK"; then pass "$1: $2"; else fail_ "$1" "$DETAIL"; fi
}

echo "=== BL-335: the operator's additional_required across SessionStart ==="
check S1  "startup keeps a valid additional_required list, and prints no note"
check S2  "resume keeps it"
check S3  "compact keeps it"
check S4  "clear keeps it"
check S5  "startup still empties calls[], drops both outcome flags, resets the latch and the commit counter"
check S6  "a carried requirement whose tool succeeded LAST session blocks the first Write and names the tool; a successful call THIS session allows it"
check S7  "an empty list stays empty, an absent one is written empty, and neither prints a note"
check S8  "junk entries are dropped with one note naming the count, the valid one is kept, and the next start is silent"
check S8b "a value that is not a list is dropped with one note"
check S8r "resume drops junk entries the same way"
check S9  "quotes, backslashes, \$(...), backticks and \$HOME are carried byte for byte and nothing in them runs"
check S10 "when jq refuses the merge, the fallback ledger keeps the list"
check S11 "a ledger that is not valid JSON is rewritten (resume and startup), and one line names the entries it listed"
check S12 "jq missing at startup: the ledger is removed as before, and one line names the entries and why"
check S12b "jq missing with an empty list: no note"
check S12d "jq missing with a value that is not a list: no note"
check S12c "jq missing with a long list: the note is cut short"
check S13 "ledger writer missing at startup: one line names the entries and the writer"
check R1  "entries jq's test() cannot compile are dropped with the note; a successful call for the valid one allows"
check L1  "a 600 KB lib-less ledger with no closing ] starts in bounded time, is removed, and the gate denies"
check L2  "a 600 KB ledger with a stray } starts in bounded time, is reset, the gate denies, and a ] inside quotes does not cut the note"
check B1  "the list FIRST in a 570 KB broken ledger is named, and the scan is fed at most 64 KB from its key"
check T1  "a 70 KB last_mcp_error after the list: carried when valid, named when broken (stray } with jq, and lib-less)"
check T3  "a list whose ] lies past the window: the note says it was cut off and must be added again"
check F1  "a FIFO at the ledger path does not block the lib-less start"
check T4  "a string ending in \"additional_required before the real key: the key is matched as a key and the note names the list"
check K1  "a scan cancelled mid-run (lib-less) leaves the ledger already removed: the gate denies"
check K2  "a scan cancelled mid-run (stray }, with jq) leaves the ledger already reset: the gate denies"

# ── Mutation proofs ─────────────────────────────────────────────────────────
# A copy of the hook with one change, the change asserted to have landed and to
# parse, then the killer case run against it, which must fail. The lib is
# copied beside it, since the hook loads lib/ledger-write.sh from its own
# directory. awk index()/substr() and ENVIRON, so no regex or `&` in the
# replacement can bite (CLAUDE.md, ENVIRONMENT TRAPS).
MUT_N=0
mk_mut() {   # NEEDLE REPLACEMENT NTH — replace the NTH line containing NEEDLE
  MUT_N=$((MUT_N + 1))
  MDIR="$TOPTMP/m$MUT_N/scripts"; mkdir -p "$MDIR/lib"
  cp "$REPO_ROOT/scripts/lib/ledger-write.sh" "$REPO_ROOT/scripts/lib/lock.sh" "$MDIR/lib/"
  MUT="$MDIR/session-test-gate-check.sh"
  MUT_SITES=$(NEEDLE="$1" REPL="$2" NTH="$3" awk '
    index($0, ENVIRON["NEEDLE"]) { n++; if (n == ENVIRON["NTH"] + 0) { print ENVIRON["REPL"]; hit++; next } }
    { print }
    END { print hit + 0 > "/dev/stderr" }' "$HOOK" 2>&1 >"$MUT")
}
mk_sub() {   # NEEDLE OLD NEW — within the one line containing NEEDLE, replace OLD by NEW
  MUT_N=$((MUT_N + 1))
  MDIR="$TOPTMP/m$MUT_N/scripts"; mkdir -p "$MDIR/lib"
  cp "$REPO_ROOT/scripts/lib/ledger-write.sh" "$REPO_ROOT/scripts/lib/lock.sh" "$MDIR/lib/"
  MUT="$MDIR/session-test-gate-check.sh"
  MUT_SITES=$(NEEDLE="$1" OLD="$2" NEW="$3" awk '
    index($0, ENVIRON["NEEDLE"]) && (i = index($0, ENVIRON["OLD"])) {
      $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"])); hit++ }
    { print }
    END { print hit + 0 > "/dev/stderr" }' "$HOOK" 2>&1 >"$MUT")
}
killed_by() {   # LABEL CASE
  if [ "$MUT_SITES" != 1 ] || cmp -s "$HOOK" "$MUT" || ! bash -n "$MUT" 2>/dev/null; then
    fail_ "$1" "the mutation did not apply (sites=$MUT_SITES)"; return
  fi
  if "c_$2" "$MUT"; then fail_ "$1" "survived: $2 still passes"; else pass "$1 — killed by $2"; fi
}

echo ""
echo "=== mutation proofs ==="
mk_mut '# BL-335-READ' "    if ADD_READ=\$(printf '0 []'); then   # BL-335-READ" 1
killed_by "MU1: the reader returns an empty list (# BL-335-READ)" S1
mk_mut '"additional_required": $ADD_REQ' '    "additional_required": []' 2
killed_by "MU2: the startup heredoc writes [] again" S6
mk_mut '"additional_required": $ADD_REQ' '    "additional_required": []' 1
killed_by "MU3: the jq-failure fallback writes [] again" S10
mk_sub '# BL-335-MERGE' '= $add' '= ($orig.mcp_requirements.additional_required // [])'
killed_by "MU4: the merge carries the raw list again (# BL-335-MERGE)" S8r
mk_sub '# BL-335-READ' 'select(type == "string" and length > 0)' '.'
killed_by "MU5: no entry is checked (# BL-335-READ's select)" S8
mk_mut '# BL-335-DROP-NOTE' '        :   # BL-335-DROP-NOTE' 1
killed_by "MU6: the dropped-entries note silenced (# BL-335-DROP-NOTE)" S8
mk_mut '# BL-335-UNREADABLE' '      :   # BL-335-UNREADABLE' 1
killed_by "MU7: the not-valid-JSON note silenced (# BL-335-UNREADABLE)" S11
mk_mut '# BL-335-NOJQ' '  :   # BL-335-NOJQ' 1
killed_by "MU8: the jq-missing note silenced (# BL-335-NOJQ)" S12
mk_mut '# BL-335-NOTE' '  :   # BL-335-NOTE' 1
killed_by "MU9: the note never printed (# BL-335-NOTE)" S8
mk_sub 'if (substr(s, p, 1) != "[") exit' 'exit' 'p = p'
killed_by "MU10: the scan takes a value that is not a list for one" S12d
mk_sub '# BL-335-SNAP-BOUND' ' | head -c 65536' ''
killed_by "MU11: the window from the key is not cut at 64 KB (# BL-335-SNAP-BOUND)" B1
mk_mut '# BL-335-SNAP-KEY' '  off=0   # BL-335-SNAP-KEY' 1
killed_by "MU20: the window starts at the file's start, not the key (# BL-335-SNAP-KEY)" T1
mk_mut '# BL-335-SNAP-REGULAR' '  :   # BL-335-SNAP-REGULAR' 1
killed_by "MU21: no regular-file check before reading the ledger (# BL-335-SNAP-REGULAR)" F1
mk_mut '# BL-335-CUT-NOTE' '      ADD_NOTE=""   # BL-335-CUT-NOTE' 1
killed_by "MU22: a list cut off by the window is dropped in silence (# BL-335-CUT-NOTE)" T3
mk_sub '# BL-335-SNAP-KEY' "grep -boE -m1 '\"additional_required\"[[:space:]]*:'" "grep -boF -m1 '\"additional_required\"'"
killed_by "MU23: the key found as bare text, not as a key (# BL-335-SNAP-KEY)" T4
mk_mut '# BL-335-NOJQ' '  _add_snap "$TOOL_USAGE" "$ADD_WHY"; _add_scan   # BL-335-NOJQ' 1
killed_by "MU12: lib-less, the scan runs BEFORE the ledger is removed" K1
mk_mut '# BL-335-UNREADABLE' '      _add_snap "$TOOL_USAGE" "the file is not valid JSON, so it was rewritten"; _add_scan   # BL-335-UNREADABLE' 1
killed_by "MU13: with jq, the scan runs BEFORE the ledger is reset" K2
mk_sub 'if (instr) { out = out c' 'if (instr) {' 'if (c == "]") break; if (instr) {'
killed_by "MU14: a ] inside quotes ends the scan" L2
mk_sub 'for (; p <= n && length(out) < 300; p++)' '< 300' '< 300000'
killed_by "MU15: the scan's output is not cut at 300 bytes" S12c
mk_sub 'if (c ~ /[\t\r\n]/) c = " "' 'if (c ~ /[\t\r\n]/)' 'if (0)'
killed_by "MU16: newlines reach the note (it breaks over lines)" S12
mk_mut '_add_scan   # BL-335-SCAN' '_add_scan_never=1   # BL-335-SCAN' 1
killed_by "MU17: the scan never runs (# BL-335-SCAN)" S12
mk_sub '# BL-335-READ' ' | select(. as $p | (try ("" | test($p)) catch null) != null)' ''
killed_by "MU18: entries test() cannot compile are carried" R1
mk_sub 'ADD_WHY="jq is not installed' 'if [ "$LW_READY" = "1" ]' 'if [ "$LW_READY" != "1" ]'
killed_by "MU19: the two reasons swapped (jq missing reported as the writer)" S12

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

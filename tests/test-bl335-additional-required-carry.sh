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
for c in cat date mkdir rm rmdir mv mktemp stat sleep sort grep tr dirname; do
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
  cp "$REPO_ROOT/scripts/lib/ledger-write.sh" "$MDIR/lib/"
  MUT="$MDIR/session-test-gate-check.sh"
  MUT_SITES=$(NEEDLE="$1" REPL="$2" NTH="$3" awk '
    index($0, ENVIRON["NEEDLE"]) { n++; if (n == ENVIRON["NTH"] + 0) { print ENVIRON["REPL"]; hit++; next } }
    { print }
    END { print hit + 0 > "/dev/stderr" }' "$HOOK" 2>&1 >"$MUT")
}
mk_sub() {   # NEEDLE OLD NEW — within the one line containing NEEDLE, replace OLD by NEW
  MUT_N=$((MUT_N + 1))
  MDIR="$TOPTMP/m$MUT_N/scripts"; mkdir -p "$MDIR/lib"
  cp "$REPO_ROOT/scripts/lib/ledger-write.sh" "$MDIR/lib/"
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
mk_mut "case \"\$s\" in ':['*)" '  :' 1
killed_by "MU10: _add_raw takes a value that is not a list for one" S12d
mk_mut 'r=${r%%]*}' '  :' 1
killed_by "MU11: _add_raw does not stop at the list's end" S12
mk_mut 'r=${r#*\[}' '  :' 1
killed_by "MU12: _add_raw keeps the text before the list's [" S12
mk_mut "tr -s '[:space:]' ' '" '  :' 1
killed_by "MU13: _add_raw keeps the list's newlines (the note breaks over lines)" S12
mk_mut '"${#r}" -gt 300' '  :' 1
killed_by "MU14: _add_raw does not cut a long list short" S12c
mk_sub 'ADD_WHY="jq is not installed' 'if [ "$LW_READY" = "1" ]' 'if [ "$LW_READY" != "1" ]'
killed_by "MU15: the two reasons swapped (jq missing reported as the writer)" S12

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

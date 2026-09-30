#!/usr/bin/env bash
# tests/test-bl311-adopt-mcp-mutants.sh — `## BL-311:` group A's MUTATION
# PROOFS, split out of tests/test-bl311-adopt-mcp.sh so the cases and the
# mutants each run on a unit-shard leg of their own: `mcp` runs that file,
# `mcp-mutants` runs this one (.github/workflows/tests.yml, `pin_mcp_mutants`).
# As one file they took the `mcp` leg to 661s of its 720s cap on PR #477's
# merge run, and a leg that runs one file cannot be re-pinned.
#
# THIS FILE OWNS NO CASE. It SOURCES tests/test-bl311-adopt-mcp.sh, which,
# sourced rather than run, defines its stubs, fixtures and cases and returns
# before running any (`# BL-311-MCP-SPLIT`). Each mutant below then replaces
# the ONE line ending in its marker, in a COPY of the framework, and re-runs
# only the case that must kill it; the kill must come from that case's NAMED
# assertion — exactly as when the two were one file.
#
# IT CANNOT PASS HAVING PROVED NOTHING. Each of these is a FAIL:
#   - tests/test-bl311-adopt-mcp.sh is not beside this file;
#   - loading it RAN it: it exited while loading, or a case outcome was
#     counted before the first mutant — its guard no longer holds;
#   - this file declares no mutant (a line that starts `mut "M`,
#     `mut_sub "M` or `mut_doc "M`);
#   - the mutants judged are not the mutants declared. Every mutant ends in
#     exactly one [PASS], [FAIL] or [SKIP], so a count that differs means one
#     never ran, or ran outside that convention; and an `exit` before the
#     count is itself a FAIL (below), so ending early cannot skip it.
# Without git or jq it SKIPS, as the cases file does. BL311_KEEP=1 keeps the
# fixtures, as there.
set -uo pipefail

_BL311_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BL311_CASES="$_BL311_DIR/test-bl311-adopt-mcp.sh"
_BL311_SELF="$_BL311_DIR/$(basename "${BASH_SOURCE[0]}")"
echo "== BL-311 — mutation proofs: the MCP servers on the adoption path, and CLAUDE_CONFIG_DIR =="
if [ ! -f "$_BL311_CASES" ]; then
  echo "  [FAIL] loading the cases — $_BL311_CASES is not there, so no mutant can be judged"
  echo; echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1
fi
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "  [SKIP] every mutant — $t is not on PATH"; echo; echo "Results: 0 passed, 0 failed, 1 skipped"; exit 0; }
done

# AN EXIT BEFORE THE COUNT IS A FAIL. Until the count at the end, `exit` is
# this function. The cases file ends in `_done`, which exits with ITS rc: if
# its guard stopped holding, loading it would run every case and exit 0 with
# no mutant judged — and a stray `_done` among the mutants would end the run
# just as quietly. Outside POSIX mode bash looks a name up as a function before
# a builtin (the Bash manual, "Command Search and Execution"; measured on
# 3.2.57 and 5.2.37, from inside a sourced file's function too), and
# `builtin exit` is the real one. In POSIX mode `exit`, a special builtin,
# wins over any function, so that mode is refused rather than trusted.
if shopt -oq posix; then
  echo "  [FAIL] loading the cases — bash is in POSIX mode, where an early exit could not be caught; run it with bash, not sh"
  echo; echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1
fi
_BL311_AT="loading $_BL311_CASES"
exit() {
  echo "  [FAIL] $_BL311_AT — the run exited (rc ${1:-}) before its mutants were counted, so what it proved is unknown"
  echo; echo "Results: ${PASSED:-0} passed, $(( ${FAILED:-0} + 1 )) failed, ${SKIPPED:-0} skipped"; builtin exit 1
}
. "$_BL311_CASES"
# LOADING MUST HAVE DEFINED WHAT THE MUTANTS USE — checked before anything
# expands a counter (`## BL-311:` review round 1, R-BL311B-4). With the cases
# file's `# BL-311-MCP-SPLIT` return moved above its counters, sourcing returns
# before PASSED or fail_ exist, and the unbound PASSED in the arithmetic `if`
# below stops the shell — WITH rc 0 on /bin/bash 3.2.57 and rc 1 on 5.2.37,
# measured on a two-line probe — without calling the `exit` above, so this file
# passed with no Results line on this Mac. `${PASSED+x}` tests for the variable
# without expanding it.
if [ -z "${PASSED+x}" ] || [ -z "${FAILED+x}" ] || [ -z "${SKIPPED+x}" ] \
   || ! declare -F pass fail_ skip _done >/dev/null 2>&1; then   # BL-311-MUTANTS-LOADED
  echo "  [FAIL] $_BL311_AT — it defined no PASSED/FAILED/SKIPPED or no pass/fail_/skip/_done, so it returned before them (# BL-311-MCP-SPLIT above its counters?) and no mutant can be judged"
  echo; echo "Results: 0 passed, 1 failed, 0 skipped"; builtin exit 1
fi
_BL311_AT="judging the mutants"
if [ $((PASSED + FAILED + SKIPPED)) -ne 0 ]; then
  fail_ "loading the cases" "$((PASSED + FAILED + SKIPPED)) outcome(s) were counted while sourcing it — it ran cases, not only their definitions (# BL-311-MCP-SPLIT)"
  unset -f exit; _done
fi

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

echo "== M — mutation proofs =="
_BL311_N0=$((PASSED + FAILED + SKIPPED))
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

# ── the count ───────────────────────────────────────────────────────────────
# Every mutant above ends in exactly one outcome, so the outcomes since the
# first one are the mutants judged; the declared ones are this file's own
# `mut "M`, `mut_sub "M` and `mut_doc "M` lines. Zero declared is a FAIL, and
# so is any difference — a mutant that never ran is not a mutant killed.
_BL311_JUDGED=$((PASSED + FAILED + SKIPPED - _BL311_N0))
_BL311_DECLARED="$(grep -cE '^mut(_sub|_doc)? "M[0-9]+ ' "$_BL311_SELF")"
unset -f exit
if [ "$_BL311_DECLARED" -lt 1 ]; then
  fail_ "the count" "$_BL311_SELF declares no mutant — nothing was proved"
elif [ "$_BL311_JUDGED" -ne "$_BL311_DECLARED" ]; then
  fail_ "the count" "$_BL311_DECLARED mutant(s) declared, $_BL311_JUDGED judged"
else
  echo "  ($_BL311_JUDGED of $_BL311_DECLARED declared mutants judged)"
fi
_done

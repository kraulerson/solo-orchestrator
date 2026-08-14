#!/usr/bin/env bash
# tests/test-bl234-currency-and-availability.sh
#
# BL-234 — currency and availability must be MEASURED, not DECLARED. Four
# shipped checks asked whether something was configured and reported the answer
# as whether it worked:
#
#   1. scripts/lib/freshness-detect.sh compared a project's pin against the
#      LOCAL clone it was scaffolded from — the same object, by construction —
#      and never fetched. `pin-behind` was structurally incapable of firing, and
#      on `powerpoint-voice` it stayed silent through 161 upstream commits.
#   2. scripts/lib/helpers-full.sh::is_qdrant_mcp_registered tested for an
#      `mcpServers.qdrant` KEY, so a stale global entry made every later project
#      skip provisioning the database.
#   3. scripts/track-tool-usage.sh decided emptiness partly by PHRASE, and
#      matched a stored memory that CONTAINED the words "empty result".
#   4. templates/tool-matrix — filed as `## BL-235:`, deliberately not fixed.
#
# ── WHAT THIS SUITE REFUSES TO DO ───────────────────────────────────────────
# "Do not let a test pass because a fetch or a probe was ATTEMPTED." Not one
# assertion below is satisfied by the presence of a call, a label, or a flag
# that says a thing happened. Every assertion is on EMITTED OUTPUT, LEDGER
# STATE, an EXIT CODE, or WALL-CLOCK TIME.
#
# Three arms are of the kind that silently cannot fire, so each has a test whose
# whole job is to MAKE it fire:
#   • the reference-age fallback  → A3/A4/A6 (fetch fails / never fetched / no remote)
#   • the probe bound             → A5/B6 (a stub that sleeps 30s, wall-clock asserted)
#   • the cannot-tell probe state → B3 (PATH with neither curl nor nc)
# The author of the brief shipped a `docker ps … | head || echo` whose fallback
# could never fire, because a pipeline's status is the last command's. That is
# recorded in `## BL-231:`'s ⚠ CORRECTION block and it is the standard here.
#
# ── Mutation harness standard (all mandatory) ───────────────────────────────
#   • anchored END-OF-LINE markers, asserted at sites==1 in the SHIPPED source;
#   • exactly-N-lines-changed per mutant — this is what catches a sed that
#     reported success and edited nothing (CLAUDE.md's sed trap). The delimiter
#     is `%`, absent from every marker and replacement here, and `&` is escaped
#     because in a sed replacement `&` means THE WHOLE MATCH;
#   • EVERY mutant asserts `bash -n` — a mutant that lands as a syntax error
#     kills every test for the wrong reason and would score as a pass;
#   • mode-preserving (`stat -c || stat -f`, GNU-first);
#   • a FRESH fixture per mutant AND per direction — the freshness detector
#     writes .claude/cache/freshness.json, so a reused project directory carries
#     snooze/cache state from the control run into the mutant run;
#   • structural discriminators for ABSENCES. Item 3 DELETES the phrase half, and
#     an absence cannot be greped for as proof, so M-EMPTY mutates a real shape
#     line back into a phrase match and shows the incident fixture flipping.
#
# Hermetic: temp dirs only. Origins are LOCAL BARE REPOS — never the network,
# never `gh repo create`. No `timeout`/`gtimeout` (absent on the dev host: they
# yield a spurious rc=127, not a timeout). bash 3.2: no ${var,,}, no declare -A,
# no nullglob, no ((x++)) under set -e.
#
# This suite does not invoke init.sh. It EXTRACTS init.sh's Qdrant
# reclassification chain from between its fence markers and executes that, so
# B5 asserts on the shipped chain rather than on a copy of it that could drift.
# `init.sh` is named on executed lines for that reason, so
# lint-tests-registered.sh will mark it unit-lane-exempt; it is registered in
# the tests.yml unit list anyway (the lint treats a listed test as "the
# exemption decided nothing") because it is fast enough for the fast lane.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FRESH_LIB="$REPO_ROOT/scripts/lib/freshness-detect.sh"
FRESH_SUT="$REPO_ROOT/scripts/session-freshness-check.sh"
HELPERS_FULL="$REPO_ROOT/scripts/lib/helpers-full.sh"
TRACKER="$REPO_ROOT/scripts/track-tool-usage.sh"
CHECKVER="$REPO_ROOT/scripts/check-versions.sh"
SCAFFOLDER="$REPO_ROOT/init.sh"
GITIGNORE_TMPL="$REPO_ROOT/templates/generated/gitignore-base.tmpl"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

BASH_BIN="$(command -v bash)"
[ -n "$BASH_BIN" ] || BASH_BIN="/bin/bash"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on JSON state."
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
# newtmp — a FRESH directory per case. It must be `mktemp -d` and not a counter:
# a counter incremented inside `$( … )` increments in a SUBSHELL and never
# reaches the parent, so every call returns the same path and every "fresh
# fixture" is the previous case's leftovers. That bug was live in the first
# draft of this file and A4 caught it (a fixture that had "never fetched" found
# a FETCH_HEAD), which is the whole reason the fresh-fixture rule exists.
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_mtime_of() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '\n'; }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

# _mutate FILE MARKER REPLACEMENT — excise the one END-OF-LINE-anchored marked
# line and replace it. Echoes "sites changed parses".
_mutate() {
  local f="$1" marker="$2" repl="$3"
  local before sites changed parses safe
  safe=$(printf '%s' "$repl" | sed 's/&/\\&/g')
  before="$(mktemp)"
  cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  _sed_inplace "$f" "s%^.*${marker}\$%${safe}%"
  changed=$(_changed_lines "$before" "$f")
  parses=$(_parses "$f")
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

_git() { git -c user.email=t@t.t -c user.name=tester -c commit.gpgsign=false "$@"; }

# ════════════════════════════════════════════════════════════════════════════
# FIXTURES — a framework clone, optionally anchored to a LOCAL BARE ORIGIN.
# ════════════════════════════════════════════════════════════════════════════

# build_fw <fwdir> [baredir] — a minimal framework checkout. When <baredir> is
# given it is created as a LOCAL BARE repo, pushed to, and set as `origin` with
# an upstream — a real remote with no network anywhere near it.
# Sets FW and PIN. Never echoes: a stray git line would corrupt a capture.
FW=""; PIN=""
build_fw() {
  local fw="$1" bare="${2:-}"
  mkdir -p "$fw/scripts"
  printf 'echo fw v1\n' > "$fw/scripts/validate.sh"
  _git -C "$fw" init -q -b main >/dev/null 2>&1 || { _git -C "$fw" init -q >/dev/null 2>&1; _git -C "$fw" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1; }
  _git -C "$fw" add -A >/dev/null 2>&1
  _git -C "$fw" commit -qm "fw v1" >/dev/null 2>&1
  if [ -n "$bare" ]; then
    _git init -q --bare "$bare" >/dev/null 2>&1
    _git -C "$fw" remote add origin "$bare" >/dev/null 2>&1
    _git -C "$fw" push -q -u origin main >/dev/null 2>&1
    _git -C "$fw" fetch -q origin >/dev/null 2>&1
  fi
  FW="$fw"
  PIN="$(_git -C "$fw" rev-parse HEAD 2>/dev/null)"
}

# advance_origin <baredir> <workdir> — push one NEW commit to the bare origin
# from a throwaway clone, so the framework checkout is genuinely behind its
# remote without its own refs knowing it yet.
advance_origin() {
  local bare="$1" work="$2"
  _git clone -q "$bare" "$work" >/dev/null 2>&1 || return 1
  printf 'echo fw v2\n' > "$work/scripts/validate.sh"
  _git -C "$work" add -A >/dev/null 2>&1
  _git -C "$work" commit -qm "fw v2" >/dev/null 2>&1
  _git -C "$work" push -q origin HEAD:main >/dev/null 2>&1
}

# build_proj <projdir> <fwdir> <pin> — a scaffolded project whose currency block
# is EMPTY except for the pin, so only the framework check can speak. Any other
# emitted line would be a fixture bug, not a finding.
build_proj() {
  local proj="$1" fw="$2" pin="$3"
  mkdir -p "$proj/.claude"
  jq -n --arg pin "$pin" --arg fw "$fw" \
    '{ soloFrameworkCommit:$pin,
       currency:{ schemaVersion:1, soloFrameworkPath:$fw,
                  files:{}, renderBases:{A1:{},A2:{}}, hooks:{} } }' \
    > "$proj/.claude/manifest.json"
}

# run_fresh <projdir> [env assignments...] — invoke the SHIPPED SessionStart
# wrapper. Captures stdout/stderr/exit and the wall-clock seconds it took.
FOUT=""; FERR=""; FRC=0; FSECS=0
run_fresh() {
  local proj="$1"; shift
  local errf t0 t1
  errf="$TOPTMP/err.$$"
  t0=$(date +%s)
  FOUT="$(env "$@" CDF_HOME="$TOPTMP/no-cdf" CLAUDE_PROJECT_DIR="$proj" "$BASH_BIN" "$FRESH_SUT" 2>"$errf")"
  FRC=$?
  t1=$(date +%s)
  FSECS=$((t1 - t0))
  FERR="$(cat "$errf" 2>/dev/null)"
  rm -f "$errf"
}

echo "=== A — framework currency is measured against the REMOTE, and says so when it cannot be ==="

# ── A1: the silent case. The clone is behind its origin; today nothing says so.
A1="$(newtmp)"
build_fw "$A1/fw" "$A1/origin"
A1PIN="$PIN"
if ! advance_origin "$A1/origin" "$A1/adv"; then
  fail_ "A1" "fixture: could not advance the local bare origin"
else
  build_proj "$A1/proj" "$A1/fw" "$A1PIN"
  run_fresh "$A1/proj"
  if [ "$FRC" -eq 0 ] && printf '%s' "$FOUT" | grep -q 'pin-behind-upstream'; then
    pass "A1: framework clone is behind its origin -> REPORTED (the pin/HEAD comparison could never see this: they are the same object by construction)"
  else
    fail_ "A1" "rc=$FRC and no pin-behind-upstream item; output was: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-400)"
  fi
fi

# ── A2: no false noise. Clone current with its origin -> byte-silent.
A2="$(newtmp)"
build_fw "$A2/fw" "$A2/origin"
build_proj "$A2/proj" "$A2/fw" "$PIN"
run_fresh "$A2/proj"
if [ "$FRC" -eq 0 ] && [ -z "$FOUT" ] && [ -z "$FERR" ]; then
  pass "A2: clone current with its origin -> zero bytes on stdout AND stderr, exit 0 (a fetch that succeeds must stay silent)"
else
  fail_ "A2" "rc=$FRC out='$(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-300)' err='$(printf '%s' "$FERR" | tr '\n' '|' | cut -c1-200)'"
fi

# ── A3: the fetch FAILS. The reference-age line must still appear.
# Asserting only "did not crash" would pass over the exact silence this package
# exists to remove, so the age text itself is asserted.
A3="$(newtmp)"
build_fw "$A3/fw" "$A3/origin"
build_proj "$A3/proj" "$A3/fw" "$PIN"
rm -rf "$A3/origin"                     # the remote path is now gone: fetch cannot succeed
A3_FH="$(_git -C "$A3/fw" rev-parse --git-dir 2>/dev/null)/FETCH_HEAD"
case "$A3_FH" in /*) : ;; *) A3_FH="$A3/fw/$A3_FH" ;; esac
touch -t 202601010000 "$A3_FH" 2>/dev/null
A3_MT="$(_mtime_of "$A3_FH")"
if [ -z "$A3_MT" ] || [ ! -f "$A3_FH" ]; then
  fail_ "A3" "fixture: FETCH_HEAD absent or unstattable at $A3_FH"
else
  A3_NOW=$((A3_MT + 30 * 86400 + 60))
  run_fresh "$A3/proj" "SOIF_FRESHNESS_NOW=$A3_NOW"
  if [ "$FRC" -eq 0 ] \
     && printf '%s' "$FOUT" | grep -q 'fw-reference-age' \
     && printf '%s' "$FOUT" | grep -q '30 day' ; then
    pass "A3: fetch impossible (origin path deleted) -> exit 0, no crash, AND the reference-age line names the real age (30 days)"
  else
    fail_ "A3" "rc=$FRC — wanted a fw-reference-age item naming '30 day'; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-500)"
  fi
fi

# ── A4: NEVER fetched — powerpoint-voice's true state, and the one the old code
# reported as "current".
A4="$(newtmp)"
build_fw "$A4/fw"                       # no bare origin: nothing has ever been fetched
_git -C "$A4/fw" remote add origin "$A4/nonexistent-bare" >/dev/null 2>&1
build_proj "$A4/proj" "$A4/fw" "$PIN"
A4_FH="$(_git -C "$A4/fw" rev-parse --git-dir 2>/dev/null)/FETCH_HEAD"
case "$A4_FH" in /*) : ;; *) A4_FH="$A4/fw/$A4_FH" ;; esac
if [ -f "$A4_FH" ]; then
  fail_ "A4" "fixture: FETCH_HEAD exists but this fixture must never have fetched"
else
  run_fresh "$A4/proj"
  if [ "$FRC" -eq 0 ] && printf '%s' "$FOUT" | grep -qi 'never fetched'; then
    pass "A4: a clone that has NEVER been fetched is reported as such — the true answer on powerpoint-voice, where silence was reported instead"
  else
    fail_ "A4" "rc=$FRC — wanted 'never fetched'; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-500)"
  fi
fi

# ── A5: THE BOUND ACTUALLY BOUNDS. Proved with a git stub that sleeps 30s and a
# wall-clock assertion — not by asserting that a timeout value was passed.
# This is also the only test that can catch an orphaned child holding the
# command-substitution pipe open: run_with_timeout kills the stub, but a
# surviving grandchild that inherited stdout would stall the capture for 30s.
A5="$(newtmp)"
build_fw "$A5/fw" "$A5/origin"
build_proj "$A5/proj" "$A5/fw" "$PIN"
mkdir -p "$A5/bin"
REAL_GIT="$(command -v git)"
cat > "$A5/bin/git" << STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "fetch" ]; then sleep 30; exit 0; fi
done
exec "$REAL_GIT" "\$@"
STUBEOF
chmod 755 "$A5/bin/git"
run_fresh "$A5/proj" "PATH=$A5/bin:$PATH" "SOIF_FRESHNESS_FETCH_TIMEOUT=2"
if [ "$FRC" -eq 0 ] && [ "$FSECS" -le 8 ] && printf '%s' "$FOUT" | grep -q 'fw-reference-age'; then
  pass "A5: a fetch that would hang for 30s is cut off at the 2s bound (measured ${FSECS}s wall clock) and the reference-age line still appears"
else
  fail_ "A5" "rc=$FRC elapsed=${FSECS}s (want <=8) — and wanted fw-reference-age; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-300)"
fi

# ── A6: no remote at all. A fetch that was never ATTEMPTED is still a fetch that
# did not happen, and the reference is still unanchored.
A6="$(newtmp)"
build_fw "$A6/fw"
build_proj "$A6/proj" "$A6/fw" "$PIN"
run_fresh "$A6/proj"
if [ "$FRC" -eq 0 ] && printf '%s' "$FOUT" | grep -q 'fw-reference-age'; then
  pass "A6: a framework clone with NO remote reports that its currency could not be checked, instead of reporting 'current'"
else
  fail_ "A6" "rc=$FRC — wanted fw-reference-age; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-300)"
fi

# ── A7: the machine block's `network` field was a DECLARATION too. It was the
# literal string "none", and would have gone on saying "none" while the detector
# fetched. The fixture carries a pin-behind item that fires in BOTH modes, so a
# machine block exists to read in both — otherwise the opt-out run is silent and
# the field could not be compared at all.
A7="$(newtmp)"
build_fw "$A7/fw"
A7PIN="$PIN"
printf 'echo fw v2\n' > "$A7/fw/scripts/validate.sh"
_git -C "$A7/fw" add -A >/dev/null 2>&1
_git -C "$A7/fw" commit -qm "fw v2" >/dev/null 2>&1
_net_of() { printf '%s' "$1" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d' | jq -r '.network // "MISSING"' 2>/dev/null; }
build_proj "$A7/p1" "$A7/fw" "$A7PIN"
run_fresh "$A7/p1"
A7_ON="$(_net_of "$FOUT")"
A7_ON_AGE=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && A7_ON_AGE=yes
build_proj "$A7/p2" "$A7/fw" "$A7PIN"
run_fresh "$A7/p2" "SOIF_FRESHNESS_FETCH=0"
A7_OFF="$(_net_of "$FOUT")"
A7_OFF_AGE=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && A7_OFF_AGE=yes
if [ "$A7_ON" = "fetch-bounded" ] && [ "$A7_ON_AGE" = "yes" ] \
   && [ "$A7_OFF" = "none" ] && [ "$A7_OFF_AGE" = "no" ]; then
  pass "A7: the machine block reports the mode that actually ran — 'fetch-bounded' by default, 'none' under SOIF_FRESHNESS_FETCH=0, which restores M1's zero-network contract INCLUDING its silence"
else
  fail_ "A7" "default: network='$A7_ON' (want fetch-bounded) age=$A7_ON_AGE (want yes); opt-out: network='$A7_OFF' (want none) age=$A7_OFF_AGE (want no)"
fi

echo ""
echo "=== B — 'registered' must mean 'registered AND the database answers' ==="

# A private HOME so nothing here can read or write the developer's real
# ~/.claude.json. Every B case gets its own.
mk_home() {
  local h="$1" url="$2"     # url empty => no qdrant entry at all
  mkdir -p "$h/.claude"
  if [ -n "$url" ]; then
    jq -n --arg u "$url" '{mcpServers:{qdrant:{type:"stdio",command:"uvx",args:["mcp-server-qdrant"],env:{QDRANT_URL:$u,COLLECTION_NAME:"c"}}}}' > "$h/.claude.json"
  else
    printf '{}\n' > "$h/.claude.json"
  fi
}

# probe_state <home> <url> [extra-path] — source the SHIPPED helpers with a
# private HOME and report "rc state" from the real predicate.
probe_state() {
  local h="$1" pathv="${2:-$PATH}"
  env -i HOME="$h" PATH="$pathv" "$BASH_BIN" -c '
    set -uo pipefail
    . "'"$HELPERS_FULL"'" >/dev/null 2>&1
    rc=0
    is_qdrant_mcp_registered || rc=$?
    printf "%s %s\n" "$rc" "${QDRANT_MCP_STATE:-UNSET}"
  ' 2>/dev/null
}

# A local HTTP server standing in for a reachable Qdrant. Python is used only as
# a socket; nothing here talks to a real database or the network.
QSRV_PID=""; QSRV_PORT=""
start_stub_qdrant() {
  local d="$1" py
  py="$(command -v python3 || command -v python)"
  [ -n "$py" ] || return 1
  QSRV_PORT=$(( 18000 + (RANDOM % 2000) ))
  "$py" - "$QSRV_PORT" > "$d/srv.log" 2>&1 << 'PYEOF' &
import sys
try:
    from http.server import BaseHTTPRequestHandler, HTTPServer
except ImportError:
    sys.exit(1)
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Length","2")
        self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PYEOF
  QSRV_PID=$!
  local i=0
  while [ "$i" -lt 40 ]; do
    curl -fsS --max-time 1 -o /dev/null "http://127.0.0.1:$QSRV_PORT/readyz" 2>/dev/null && return 0
    i=$((i + 1)); sleep 0.1
  done
  kill "$QSRV_PID" 2>/dev/null; QSRV_PID=""
  return 1
}

# ── B1: THE DEFECT. A registered entry whose database does not answer.
B1="$(newtmp)"
mk_home "$B1/home" "http://127.0.0.1:1"     # port 1 is never a Qdrant
B1_OUT="$(probe_state "$B1/home")"
B1_RC="${B1_OUT%% *}"; B1_ST="${B1_OUT##* }"
if [ "$B1_RC" != "0" ] && [ "$B1_ST" = "unreachable" ]; then
  pass "B1: a stale global MCP entry with no reachable database is NOT 'registered' (rc=$B1_RC, state=$B1_ST) — the chain now falls through to provisioning"
else
  fail_ "B1" "rc=$B1_RC state=$B1_ST — wanted a non-zero rc and state=unreachable"
fi

# ── B2: the honest positive. Registered AND answering.
B2="$(newtmp)"
if ! start_stub_qdrant "$B2"; then
  fail_ "B2" "fixture: could not start the local stub HTTP server"
else
  mk_home "$B2/home" "http://127.0.0.1:$QSRV_PORT"
  B2_OUT="$(probe_state "$B2/home")"
  kill "$QSRV_PID" 2>/dev/null; wait "$QSRV_PID" 2>/dev/null; QSRV_PID=""
  B2_RC="${B2_OUT%% *}"; B2_ST="${B2_OUT##* }"
  if [ "$B2_RC" = "0" ] && [ "$B2_ST" = "reachable" ]; then
    pass "B2: registered AND answering -> satisfied (rc=0, state=reachable) — no false negative introduced"
  else
    fail_ "B2" "rc=$B2_RC state=$B2_ST — wanted rc=0 and state=reachable"
  fi
fi

# ── B3: CANNOT TELL is its own state, and it is not 'satisfied'.
# PATH is stripped of every probe tool. jq must remain reachable or the
# predicate cannot even read the config, so a private bin dir links only jq.
B3="$(newtmp)"
mkdir -p "$B3/bin"
for t in jq bash sh env sed grep cat; do
  p="$(command -v "$t" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$B3/bin/$t" 2>/dev/null
done
mk_home "$B3/home" "http://127.0.0.1:1"
B3_OUT="$(probe_state "$B3/home" "$B3/bin")"
B3_RC="${B3_OUT%% *}"; B3_ST="${B3_OUT##* }"
if [ "$B3_RC" != "0" ] && [ "$B3_ST" = "unknown" ]; then
  pass "B3: with neither curl nor nc the probe answers 'cannot tell' (state=unknown) and does NOT satisfy the predicate — BL-112's doctrine, not a coin flip"
else
  fail_ "B3" "rc=$B3_RC state=$B3_ST — wanted a non-zero rc and state=unknown"
fi

# ── B4: no entry at all is a determinate answer, distinguishable from the rest.
B4="$(newtmp)"
mk_home "$B4/home" ""
B4_OUT="$(probe_state "$B4/home")"
B4_RC="${B4_OUT%% *}"; B4_ST="${B4_OUT##* }"
if [ "$B4_RC" != "0" ] && [ "$B4_ST" = "unregistered" ]; then
  pass "B4: no MCP entry -> state=unregistered, a THIRD state distinct from unreachable and from cannot-tell"
else
  fail_ "B4" "rc=$B4_RC state=$B4_ST — wanted a non-zero rc and state=unregistered"
fi

# ── B5: THE CHAIN ITSELF. init.sh's reclassification is extracted from between
# its fence markers and executed, so this asserts on the shipped code.
run_reclassify() {
  local d="$1" home="$2" docker_present="$3"
  local block="$d/chain.sh"
  awk '/# BL-234-QDRANT-RECLASSIFY-BEGIN$/{f=1;next} /# BL-234-QDRANT-RECLASSIFY-END$/{f=0} f' \
    "$SCAFFOLDER" > "$block"
  [ -s "$block" ] || { printf 'NOBLOCK\n'; return 1; }
  mkdir -p "$d/bin"
  for t in jq bash sh env sed grep cat awk curl nc; do
    p="$(command -v "$t" 2>/dev/null)"
    [ -n "$p" ] && ln -sf "$p" "$d/bin/$t" 2>/dev/null
  done
  if [ "$docker_present" = "yes" ]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/bin/docker"; chmod 755 "$d/bin/docker"
  fi
  env -i HOME="$home" PATH="$d/bin" BLOCK="$block" HELPERS="$HELPERS_FULL" "$BASH_BIN" -c '
    set -uo pipefail
    . "$HELPERS" >/dev/null 2>&1
    # No container is running in this harness — the question under test is what
    # the FIRST branch decides, and whether the chain reaches the docker arm.
    is_qdrant_container_running() { return 1; }
    resolver_output=$(jq -n "{already_installed:[],auto_install:[],manual_install:[{name:\"Qdrant MCP\"}]}")
    configure_items="[]"
    . "$BLOCK"
    printf "%s\n" "$resolver_output" | jq -r "
      if (.already_installed[]? | select(.name==\"Qdrant MCP\")) then \"already_installed\"
      elif (.auto_install[]? | select(.name==\"Qdrant MCP\")) then \"auto_install\"
      else \"manual\" end" | head -1
  ' 2>/dev/null
}

B5="$(newtmp)"
mk_home "$B5/home" "http://127.0.0.1:1"     # stale entry, nothing listening
B5_LANE="$(run_reclassify "$B5" "$B5/home" yes)"
if [ "$B5_LANE" = "auto_install" ]; then
  pass "B5: a stale global MCP entry with NO reachable database now falls through init.sh's own chain to the docker arm -> Qdrant is provisioned (was: already_installed, and the database was never created)"
else
  fail_ "B5" "lane='$B5_LANE' — wanted auto_install (the extracted chain must not short-circuit on a dead registration)"
fi

# ── B6: the reachability probe is bounded too. Same standard as A5.
B6="$(newtmp)"
mkdir -p "$B6/bin"
for t in jq bash sh env sed grep cat sleep; do
  p="$(command -v "$t" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$B6/bin/$t" 2>/dev/null
done
printf '#!/usr/bin/env bash\nsleep 30\n' > "$B6/bin/curl"; chmod 755 "$B6/bin/curl"
mk_home "$B6/home" "http://127.0.0.1:1"
B6_T0=$(date +%s)
B6_OUT="$(env -i HOME="$B6/home" PATH="$B6/bin" SOLO_QDRANT_PROBE_TIMEOUT=2 "$BASH_BIN" -c '
  set -uo pipefail
  . "'"$HELPERS_FULL"'" >/dev/null 2>&1
  rc=0; is_qdrant_mcp_registered || rc=$?
  printf "%s %s\n" "$rc" "${QDRANT_MCP_STATE:-UNSET}"
' 2>/dev/null)"
B6_T1=$(date +%s)
B6_EL=$((B6_T1 - B6_T0))
B6_RC="${B6_OUT%% *}"
if [ "$B6_RC" != "0" ] && [ "$B6_EL" -le 10 ]; then
  pass "B6: a curl that would hang for 30s is cut off at the 2s bound (measured ${B6_EL}s) — init.sh cannot be made to hang by an unresponsive Qdrant"
else
  fail_ "B6" "rc=$B6_RC elapsed=${B6_EL}s (want <=10 and a non-zero rc)"
fi

echo ""
echo "=== C — emptiness is decided by SHAPE; the phrase half is gone ==="

# THE REGRESSION, VERBATIM. This is the stored memory whose text made a
# ten-entry retrieval get recorded as empty on 2026-08-14.
INCIDENT_TEXT='D8 empty result returns 200 with {games: [], meta.total: 0}'

# run_tracker <dir> <payload-json> — run the SHIPPED PostToolUse tracker in a
# throwaway project and echo the resulting qdrant_find_empty value.
run_tracker() {
  local d="$1" payload="$2"
  mkdir -p "$d/.claude"
  printf '%s' "$payload" | ( cd "$d" && "$BASH_BIN" "$TRACKER" --event PostToolUse >/dev/null 2>&1 )
  jq -r '.qdrant_find_empty' "$d/.claude/tool-usage.json" 2>/dev/null
}

# ── C1: a FULL retrieval carrying the incident's phrase.
C1="$(newtmp)"
C1_PAYLOAD="$(jq -n --arg t "$INCIDENT_TEXT" '{
  hook_event_name:"PostToolUse", tool_name:"mcp__qdrant__qdrant-find",
  tool_response:[{type:"text",text:"Results for the query"},
                 {type:"text",text:("<entry><content>lancache BL7 locked decisions: " + $t + " and eleven more</content></entry>")},
                 {type:"text",text:"<entry><content>another substantial memory with real prior context</content></entry>"}]}')"
C1_EMPTY="$(run_tracker "$C1/p" "$C1_PAYLOAD")"
if [ "$C1_EMPTY" = "false" ]; then
  pass "C1: a THREE-BLOCK retrieval whose text contains the incident's own sentence records qdrant_find_empty=false — it matched a memory ABOUT emptiness and called the retrieval empty"
else
  fail_ "C1" "qdrant_find_empty=$C1_EMPTY — wanted false on a full retrieval containing: $INCIDENT_TEXT"
fi

# ── C2: a genuinely empty retrieval is still caught, by shape.
C2="$(newtmp)"
C2_EMPTY="$(run_tracker "$C2/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find","tool_response":[]}')"
if [ "$C2_EMPTY" = "true" ]; then
  pass "C2: zero content blocks -> qdrant_find_empty=true (shape, not prose)"
else
  fail_ "C2" "qdrant_find_empty=$C2_EMPTY — wanted true for a zero-length content array"
fi

# ── C3: all-whitespace text is empty by shape.
C3="$(newtmp)"
C3_EMPTY="$(run_tracker "$C3/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find","tool_response":[{"type":"text","text":"   \n\t  "}]}')"
if [ "$C3_EMPTY" = "true" ]; then
  pass "C3: an all-whitespace payload -> qdrant_find_empty=true"
else
  fail_ "C3" "qdrant_find_empty=$C3_EMPTY — wanted true"
fi

# ── C4: an absent tool_response on a success event is empty by shape.
C4="$(newtmp)"
C4_EMPTY="$(run_tracker "$C4/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find"}')"
if [ "$C4_EMPTY" = "true" ]; then
  pass "C4: tool_response absent on a success event -> qdrant_find_empty=true"
else
  fail_ "C4" "qdrant_find_empty=$C4_EMPTY — wanted true"
fi

# ── C5: the phrase list is GONE from the shipped file, and the accepted loss is
# real rather than claimed. A server that words a true zero result in prose now
# records false. Asserting the loss keeps the trade honest instead of implied.
C5="$(newtmp)"
C5_EMPTY="$(run_tracker "$C5/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find","tool_response":[{"type":"text","text":"No results found for that query."}]}')"
C5_REGEX=1
grep -q 'empty (result|collection)' "$TRACKER" 2>/dev/null && C5_REGEX=0
if [ "$C5_REGEX" = "1" ] && [ "$C5_EMPTY" = "false" ]; then
  pass "C5: the phrase regex is absent from the shipped tracker, and the accepted loss is real — prose-only 'No results found' inside a content block now records false (the lesser error: a missed true-empty, never a false alarm on a full memory)"
else
  fail_ "C5" "phrase-regex-absent=$C5_REGEX (want 1) qdrant_find_empty=$C5_EMPTY (want false)"
fi

echo ""
echo "=== D — the MCP ledger is runtime state, and git must be told so (BL-236) ==="

# ── D1: measured with git itself, not by greping the template.
D1="$(newtmp)"
mkdir -p "$D1/p/.claude"
cp "$GITIGNORE_TMPL" "$D1/p/.gitignore"
_git -C "$D1/p" init -q >/dev/null 2>&1
printf '{}\n' > "$D1/p/.claude/tool-usage.json"
if _git -C "$D1/p" check-ignore -q .claude/tool-usage.json 2>/dev/null; then
  pass "D1: a project scaffolded from the shipped .gitignore template IGNORES .claude/tool-usage.json (asserted with git check-ignore, not a grep)"
else
  fail_ "D1" "git check-ignore says .claude/tool-usage.json is still trackable"
fi

# ── D2: an ALREADY-scaffolded project gets the line from the upgrade backfill.
# The block is extracted from between its own fence markers and executed, so
# this asserts on the shipped backfill.
D2="$(newtmp)"
mkdir -p "$D2/p/.claude"
printf '{}\n' > "$D2/p/.claude/manifest.json"
printf '{}\n' > "$D2/p/.claude/tool-usage.json"
printf '# pre-existing\n*.log\n' > "$D2/p/.gitignore"
_git -C "$D2/p" init -q >/dev/null 2>&1
awk '/# BL-174-GITIGNORE-BACKFILL START$/{f=1;next} /# BL-174-GITIGNORE-BACKFILL END$/{f=0} f' \
  "$UPGRADE" > "$D2/backfill.sh"
if [ ! -s "$D2/backfill.sh" ]; then
  fail_ "D2" "could not extract the BL-174 backfill block from upgrade-project.sh"
else
  ( cd "$D2/p" && env -i HOME="$D2" PATH="$PATH" BF="$D2/backfill.sh" "$BASH_BIN" -c \
      'print_ok() { :; }; . "$BF"' >/dev/null 2>&1 )
  if _git -C "$D2/p" check-ignore -q .claude/tool-usage.json 2>/dev/null; then
    pass "D2: the upgrade backfill adds the ignore line to an ALREADY-scaffolded project (SYNC SIBLINGS: the template and the backfill are the file's two writers)"
  else
    fail_ "D2" "after running the shipped backfill, git still does not ignore .claude/tool-usage.json"
  fi
fi

# ── D3: the backfill is idempotent — running it twice must not duplicate lines.
D3_COUNT=0
if [ -s "$D2/backfill.sh" ]; then
  ( cd "$D2/p" && env -i HOME="$D2" PATH="$PATH" BF="$D2/backfill.sh" "$BASH_BIN" -c \
      'print_ok() { :; }; . "$BF"' >/dev/null 2>&1 )
  D3_COUNT=$(grep -cxF '.claude/tool-usage.json' "$D2/p/.gitignore" 2>/dev/null)
  D3_COUNT=$(_num "$D3_COUNT")
fi
if [ "$D3_COUNT" = "1" ]; then
  pass "D3: running the backfill a second time leaves exactly one ignore line (idempotent, like its two siblings)"
else
  fail_ "D3" "found $D3_COUNT copies of the ignore line after two backfill runs (want 1)"
fi

echo ""
echo "=== M — mutation proofs (each: sites==1, N lines changed, bash -n, fresh fixture) ==="

mk_mirror_lib() {
  local m="$1"
  mkdir -p "$m/scripts/lib" || return 1
  cp -p "$REPO_ROOT/scripts/session-freshness-check.sh" "$m/scripts/" || return 1
  cp -p "$FRESH_LIB" "$m/scripts/lib/" || return 1
  for f in currency-manifest.sh hook-templates.sh bypass-audit.sh helpers-core.sh; do
    [ -f "$REPO_ROOT/scripts/lib/$f" ] && cp -p "$REPO_ROOT/scripts/lib/$f" "$m/scripts/lib/"
  done
  return 0
}

run_fresh_at() {
  local sut="$1" proj="$2"; shift 2
  local errf
  errf="$TOPTMP/merr.$$"
  FOUT="$(env "$@" CDF_HOME="$TOPTMP/no-cdf" CLAUDE_PROJECT_DIR="$proj" "$BASH_BIN" "$sut" 2>"$errf")"
  FRC=$?
  FERR="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
}

# ── M1: delete the fetch. This is the shipped code before BL-234, and A1 is the
# direction that must die.
M1="$(newtmp)"
if ! mk_mirror_lib "$M1/m"; then
  fail_ "M1" "mirror setup failed"
else
  build_fw "$M1/fw" "$M1/origin"; M1PIN="$PIN"
  advance_origin "$M1/origin" "$M1/adv" || true
  build_proj "$M1/p1" "$M1/fw" "$M1PIN"
  run_fresh_at "$M1/m/scripts/session-freshness-check.sh" "$M1/p1"
  m1_ctl=no; printf '%s' "$FOUT" | grep -q 'pin-behind-upstream' && m1_ctl=yes
  m1_meta=$(_mutate "$M1/m/scripts/lib/freshness-detect.sh" '# BL-234-FETCH-REVERSAL' '  _fetch_rc=2')
  set -- $m1_meta; m1_sites=$1; m1_changed=$2; m1_parses=$3
  build_proj "$M1/p2" "$M1/fw" "$M1PIN"
  run_fresh_at "$M1/m/scripts/session-freshness-check.sh" "$M1/p2"
  m1_mut=no; printf '%s' "$FOUT" | grep -q 'pin-behind-upstream' && m1_mut=yes
  if [ "$m1_ctl" = "yes" ] && [ "$m1_mut" = "no" ] \
     && [ "$m1_sites" -eq 1 ] && [ "$m1_changed" -eq 2 ] && [ "$m1_parses" -eq 1 ]; then
    pass "M1: control reports the clone is behind its origin; with the fetch removed the SAME behind-clone reports nothing — BL-234's silence, restored on demand"
  else
    fail_ "M1" "control=$m1_ctl (want yes) mutant=$m1_mut (want no) sites=$m1_sites changed=$m1_changed parses=$m1_parses"
  fi
fi

# ── M2: delete the reference-age fallback. The fetch still runs and still fails;
# only the honest report goes away. This is the mutant that proves A3/A4/A6 are
# testing the fallback and not merely the absence of a crash.
M2="$(newtmp)"
if ! mk_mirror_lib "$M2/m"; then
  fail_ "M2" "mirror setup failed"
else
  build_fw "$M2/fw"; M2PIN="$PIN"
  build_proj "$M2/p1" "$M2/fw" "$M2PIN"
  run_fresh_at "$M2/m/scripts/session-freshness-check.sh" "$M2/p1"
  m2_ctl=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && m2_ctl=yes
  m2_meta=$(_mutate "$M2/m/scripts/lib/freshness-detect.sh" '# BL-234-REFERENCE-AGE' '    :')
  set -- $m2_meta; m2_sites=$1; m2_changed=$2; m2_parses=$3
  build_proj "$M2/p2" "$M2/fw" "$M2PIN"
  run_fresh_at "$M2/m/scripts/session-freshness-check.sh" "$M2/p2"
  m2_mut=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && m2_mut=yes
  if [ "$m2_ctl" = "yes" ] && [ "$m2_mut" = "no" ] \
     && [ "$m2_sites" -eq 1 ] && [ "$m2_changed" -eq 2 ] && [ "$m2_parses" -eq 1 ]; then
    pass "M2: control names the unfetchable reference; with only the emit removed the check goes SILENT while still failing to fetch — the exact shape this package exists to remove"
  else
    fail_ "M2" "control=$m2_ctl (want yes) mutant=$m2_mut (want no) sites=$m2_sites changed=$m2_changed parses=$m2_parses"
  fi
fi

# ── M3: unbound the fetch. Proves A5's wall clock is load-bearing.
M3="$(newtmp)"
if ! mk_mirror_lib "$M3/m"; then
  fail_ "M3" "mirror setup failed"
else
  build_fw "$M3/fw" "$M3/origin"; M3PIN="$PIN"
  mkdir -p "$M3/bin"
  cat > "$M3/bin/git" << STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "fetch" ]; then sleep 12; exit 0; fi
done
exec "$REAL_GIT" "\$@"
STUBEOF
  chmod 755 "$M3/bin/git"
  build_proj "$M3/p1" "$M3/fw" "$M3PIN"
  m3_t0=$(date +%s)
  run_fresh_at "$M3/m/scripts/session-freshness-check.sh" "$M3/p1" "PATH=$M3/bin:$PATH" "SOIF_FRESHNESS_FETCH_TIMEOUT=2"
  m3_t1=$(date +%s); m3_ctl=$((m3_t1 - m3_t0))
  m3_meta=$(_mutate "$M3/m/scripts/lib/freshness-detect.sh" '# BL-234-FETCH-BOUND' '  if git -C "$d" fetch --quiet --no-tags >/dev/null 2>&1; then')
  set -- $m3_meta; m3_sites=$1; m3_changed=$2; m3_parses=$3
  build_proj "$M3/p2" "$M3/fw" "$M3PIN"
  m3_t2=$(date +%s)
  run_fresh_at "$M3/m/scripts/session-freshness-check.sh" "$M3/p2" "PATH=$M3/bin:$PATH" "SOIF_FRESHNESS_FETCH_TIMEOUT=2"
  m3_t3=$(date +%s); m3_mut=$((m3_t3 - m3_t2))
  if [ "$m3_ctl" -le 8 ] && [ "$m3_mut" -ge 11 ] \
     && [ "$m3_sites" -eq 1 ] && [ "$m3_changed" -eq 2 ] && [ "$m3_parses" -eq 1 ]; then
    pass "M3: control returns in ${m3_ctl}s against a 12s fetch; with run_with_timeout removed the same session-start hook takes ${m3_mut}s — the bound is doing the work, not the flag"
  else
    fail_ "M3" "control=${m3_ctl}s (want <=8) mutant=${m3_mut}s (want >=11) sites=$m3_sites changed=$m3_changed parses=$m3_parses"
  fi
fi

# ── M4: make the Qdrant predicate ignore reachability again — BL-234 item 2,
# restored in one line.
M4="$(newtmp)"
mkdir -p "$M4/lib"
cp -p "$HELPERS_FULL" "$M4/lib/helpers-full.sh"
cp -p "$REPO_ROOT/scripts/lib/helpers-core.sh" "$M4/lib/helpers-core.sh"
mk_home "$M4/home" "http://127.0.0.1:1"
m4_ctl_out="$(env -i HOME="$M4/home" PATH="$PATH" "$BASH_BIN" -c '. "'"$M4/lib/helpers-full.sh"'" >/dev/null 2>&1; rc=0; is_qdrant_mcp_registered || rc=$?; printf "%s\n" "$rc"' 2>/dev/null)"
m4_meta=$(_mutate "$M4/lib/helpers-full.sh" '# BL-234-QDRANT-PREDICATE' '  _qmr_rc=0')
set -- $m4_meta; m4_sites=$1; m4_changed=$2; m4_parses=$3
mk_home "$M4/home2" "http://127.0.0.1:1"
m4_mut_out="$(env -i HOME="$M4/home2" PATH="$PATH" "$BASH_BIN" -c '. "'"$M4/lib/helpers-full.sh"'" >/dev/null 2>&1; rc=0; is_qdrant_mcp_registered || rc=$?; printf "%s\n" "$rc"' 2>/dev/null)"
if [ "$m4_ctl_out" != "0" ] && [ "$m4_mut_out" = "0" ] \
   && [ "$m4_sites" -eq 1 ] && [ "$m4_changed" -eq 2 ] && [ "$m4_parses" -eq 1 ]; then
  pass "M4: control refuses a dead registration (rc=$m4_ctl_out); with the probe result discarded the same dead entry reports 'registered' (rc=$m4_mut_out) — the stale-entry short-circuit, back in one line"
else
  fail_ "M4" "control=$m4_ctl_out (want non-zero) mutant=$m4_mut_out (want 0) sites=$m4_sites changed=$m4_changed parses=$m4_parses"
fi

# ── M5: STRUCTURAL DISCRIMINATOR for the deleted phrase half. An absence cannot
# be greped for as proof, so a shape line is mutated back INTO a phrase match and
# the incident fixture is shown flipping.
M5="$(newtmp)"
mkdir -p "$M5/m"
cp -p "$TRACKER" "$M5/m/tracker.sh"
run_tracker_at() {
  local sut="$1" d="$2" payload="$3"
  mkdir -p "$d/.claude"
  printf '%s' "$payload" | ( cd "$d" && "$BASH_BIN" "$sut" --event PostToolUse >/dev/null 2>&1 )
  jq -r '.qdrant_find_empty' "$d/.claude/tool-usage.json" 2>/dev/null
}
m5_ctl="$(run_tracker_at "$M5/m/tracker.sh" "$M5/p1" "$C1_PAYLOAD")"
# The replacement must contain NO `%` — that is this harness's sed delimiter,
# and a `%` inside it terminates the expression early, leaving the file
# unchanged WHILE SED REPORTS SUCCESS (CLAUDE.md's sed trap). The first draft
# used `printf "%s"` here and sed refused it outright; a quieter `%` would have
# produced a mutant that was never applied and scored as killed.
m5_meta=$(_mutate "$M5/m/tracker.sh" '# BL-234-EMPTY-SHAPE-ONLY' '  elif echo "$RESPONSE_TEXT" | grep -qiE "empty (result|collection)" 2>/dev/null; then')
set -- $m5_meta; m5_sites=$1; m5_changed=$2; m5_parses=$3
m5_mut="$(run_tracker_at "$M5/m/tracker.sh" "$M5/p2" "$C1_PAYLOAD")"
if [ "$m5_ctl" = "false" ] && [ "$m5_mut" = "true" ] \
   && [ "$m5_sites" -eq 1 ] && [ "$m5_changed" -eq 2 ] && [ "$m5_parses" -eq 1 ]; then
  pass "M5: control records the ten-memory retrieval as NOT empty; with a phrase test spliced back into the shape branch the same full retrieval reports EMPTY — the live 2026-08-14 incident, reproduced on demand"
else
  fail_ "M5" "control=$m5_ctl (want false) mutant=$m5_mut (want true) sites=$m5_sites changed=$m5_changed parses=$m5_parses"
fi

# ── M6: check-versions.sh's comment claimed a timeout that did not exist. The
# mutant removes the real one and shows the claim going hollow again.
M6="$(newtmp)"
mkdir -p "$M6/scripts/lib"
cp -p "$CHECKVER" "$M6/scripts/check-versions.sh"
m6_meta=$(_mutate "$M6/scripts/check-versions.sh" '# BL-234-CHECKVERSIONS-TIMEOUT' '        git -C "$repo_path" fetch --quiet 2>/dev/null || true')
set -- $m6_meta; m6_sites=$1; m6_changed=$2; m6_parses=$3
m6_bound=0
grep -q 'run_with_timeout .* git -C "\$repo_path" fetch' "$CHECKVER" 2>/dev/null && m6_bound=1
if [ "$m6_bound" = "1" ] && [ "$m6_sites" -eq 1 ] && [ "$m6_changed" -eq 2 ] && [ "$m6_parses" -eq 1 ]; then
  pass "M6: the shipped fetch is bounded by run_with_timeout, and the unbounded form is one marked line away — the comment now describes the code"
else
  fail_ "M6" "bounded=$m6_bound (want 1) sites=$m6_sites changed=$m6_changed parses=$m6_parses"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

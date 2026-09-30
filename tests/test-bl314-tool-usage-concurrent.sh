#!/usr/bin/env bash
# tests/test-bl314-tool-usage-concurrent.sh
#
# BL-314 — concurrent writers of .claude/tool-usage.json. Every write in
# scripts/track-tool-usage.sh went `jq … > "$TOOL_USAGE.tmp" && mv`, one temp
# NAME shared by every hook invocation. Two invocations at once (two sessions,
# or subagents, on one project) truncate each other's half-written temp and the
# mv lands it: the ledger ends at 0 bytes, jq on an empty input exits 0 with no
# output, so every later write re-lands it empty, and session-mcp-gate.sh fails
# CLOSED ("requirements not met") on every Write and Edit. Found in practice on
# 22 Sep 2026.
#
# Cases:
#   C0  control: sequential invocations on a seeded ledger record every call.
#       Passes at base; it proves the fixture and the counting, not the fix.
#   C1  a concurrent burst leaves the ledger non-empty, parseable, with every
#       call row, the seeded mcp_requirements kept and the find flags set.
#   C2  a reader polling DURING the burst never sees an empty or unparseable
#       ledger.
#   C3  a concurrent burst of `git commit` events counts every commit.
#   C4  no temp or lock debris is left beside the ledger.
#   C5  a burst with NO ledger seeds it once: every call recorded, and no
#       mcp_requirements object (BL-233's recovery-seed rule still holds).
#   C6  a lock left behind by a killed writer (SIGKILL skips every trap) does
#       not stop tracking, and the concurrent writes that follow it keep the
#       ledger whole. It is run twice: a lock the one break removes, and a
#       stuck one it cannot, where every writer goes ahead unlocked. Lost
#       updates are accepted there; truncation is not.
#   C7  a single write past a stale lock records its call and clears the lock.
#   C8  session-mcp-gate.sh writes the same ledger on every Write and Edit. A
#       concurrent burst of gate checks, alone and mixed with tracker events,
#       leaves a parseable ledger a reader never sees empty, and the next
#       Write is allowed.
#   C9  40 and 80 concurrent events lose no call row: a busy lock is waited
#       for, never broken, because staleness is the lock's AGE, not a count
#       of attempts.
#   C10 SIGTERM mid-write: the tracker (C10) and the gate (C10c) exit 143,
#       release the lock, land nothing and leave no temp. C10b pins INT as
#       measured: sent to the hook alone it is waited out, and the write
#       lands under the lock.
#   C11 SIGKILL mid-write leaves a lock and a temp. Once both are older than
#       the budget, the next event records its call and sweeps both. A fresh
#       temp, which may belong to a live writer, is not swept.
#   C12 a jq filter that prints nothing never lands an empty ledger.
#   C13 an existing 0-byte or unparseable ledger is reseeded by the next MCP
#       event, which records its call.
#   C14 a failed write (the gate on an unparseable ledger) leaves no temp.
#   C15 the sweep takes only its own `.lw.` temps: an aged .backup survives.
#   C16 mkdir failing with EACCES or ENOTDIR is not contention: the gate
#       answers and the tracker finishes within 3s.
#   C17 SessionStart writes the same ledger: concurrent resumes keep every
#       tracker row, and concurrent startups are never seen half-written.
#       C17c: a startup behind a tracker holding the lock lands last, so
#       inherited successes stay erased (BL-236).
#   C5b a tracker arriving while another lands the seed waits, and appends.
#   C7a/f/u the lock wait is bounded: a lock aged past the 3 s budget, one
#       dated an hour ahead, and one whose time cannot be read.
#   C18 each of the fifteen locked write sites holds the lock mid-write.
#   C19 return codes: an unlandable SessionStart ends non-zero, the lib-less
#       tracker exits 0 and writes nothing, a failed mv returns 1.
#   C20 the BSD `stat -f %m` branch, under a stat that refuses `-c`.
#   C21 verify-install's row and fixer for the lib.
#   C22 .gitignore and the project template ignore the lib's temps.
#
# Mutants, run against a mirror of the three hooks and their lib. Each proves
# its location: one marker site, and a diff of exactly that line.
#   M1  unique temp -> shared "$TOOL_USAGE.tmp" name; killed by C6's stuck arm.
#   M2  lock never taken; killed by C1's call count and C3's commit count.
#   M4  stale lock never broken; killed by C7 (lock left, every write stalls).
#   MR  a held lock is broken whatever its age; killed by C9.
#   ME  the EXIT trap removed; killed by C10. TERM is left at its default,
#       which ends the hook with 143 and still runs the EXIT trap.
#   MF  the failure path's temp cleanup removed; killed by C14.
#   MG  the non-empty check removed; killed by C12.
#   MN  a non-EEXIST mkdir failure read as contention; killed by C16.
#   MX1 the gate's _lw_traps call removed; killed by C10c.
#   MS  the sweep glob widened back to any six characters; killed by C15.
#   MX2 the sweep's age check removed; killed as C11 would be.
#   MT  SessionStart's startup write back to `cat >`; killed by C17.
#   MX5 SessionStart's whole-ledger write takes no lock; killed by C17c.
#   MSL the seed without the lock (C5b); MBUD a 60 s budget (C7a); MFUT and
#   MUNR the future and unreadable give-ups removed (C7f, C7u); MBSD the BSD
#   stat branch dropped (C20); MW-* each of the fifteen write sites without
#   the lock (C18, its own arm); ML38, ML25, ML28, MT02 the return codes
#   (C19); MV01, MV02 verify-install's row and fixer (C21); MGI each ignore
#   file without its temp line (C22). A mutant with no marker is anchored on
#   its own find text, which must occur on exactly one line.
# Not a mutant here: skipping the seed lock (# BL-314-SEED-LOCK) survived six
# C5 rounds. Every process in a burst passes the seed check before any of them
# appends, so a second seed cannot land over a first writer's row without
# pausing one process mid-seed. The lock stays because it closes that window
# by construction; the survivor is recorded on `## BL-314:`.
#
# The script under test runs as "$BASH" (the runner's interpreter), never by
# its shebang, so a 3.2 run is a 3.2 run.
# Hermetic: temp dirs only, no git, no network, no `timeout`.
# bash 3.2 compatible: no ${var,,}, no declare -A, no mapfile.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRACKER="$REPO_ROOT/scripts/track-tool-usage.sh"
GATE="$REPO_ROOT/scripts/session-mcp-gate.sh"
LIB="$REPO_ROOT/scripts/lib/ledger-write.sh"
SESSION="$REPO_ROOT/scripts/session-test-gate-check.sh"
REAL_JQ="$(command -v jq)"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+w "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }
_mutate() {
  MUT_FIND="$2" MUT_REPL="$3" perl -pi -e 'BEGIN{$f=$ENV{MUT_FIND};$r=$ENV{MUT_REPL}} s/\Q$f\E/$r/g' "$1"
}

if [ ! -f "$TRACKER" ] || ! command -v jq >/dev/null 2>&1; then
  echo "  [FAIL] setup — tracker or jq missing"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

echo "BL-314: concurrent writers of the tool-usage ledger (interpreter: $BASH, $BASH_VERSION)"

N=12
ROUNDS=3

FIND_PAYLOAD='{"tool_name":"mcp__qdrant__qdrant-find","hook_event_name":"PostToolUse","tool_response":[{"type":"text","text":"a stored memory"}]}'
COMMIT_PAYLOAD='{"tool_name":"Bash","hook_event_name":"PostToolUse","tool_input":{"command":"git commit -m x"}}'
C7Q_PAYLOAD='{"tool_name":"mcp__context7__query-docs","hook_event_name":"PostToolUse","tool_response":[{"type":"text","text":"docs"}]}'
C7R_PAYLOAD='{"tool_name":"mcp__context7__resolve-library-id","hook_event_name":"PostToolUse","tool_response":[{"type":"text","text":"/org/lib"}]}'
FAIL_PAYLOAD='{"tool_name":"mcp__qdrant__qdrant-find","hook_event_name":"PostToolUseFailure","error":"Error calling tool: connection refused"}'
INT_PAYLOAD='{"tool_name":"mcp__qdrant__qdrant-find","hook_event_name":"PostToolUseFailure","is_interrupt":true,"error":"interrupted"}'
STORE_PAYLOAD='{"tool_name":"mcp__qdrant__qdrant-store","hook_event_name":"PostToolUse","tool_response":[{"type":"text","text":"stored"}]}'
REAL_CAT="$(command -v cat)"

_seed() {
  mkdir -p "$1/.claude"
  cat > "$1/.claude/tool-usage.json" << 'EOF'
{
  "session_id": "bl314",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_called": false,
  "qdrant_find_succeeded": false,
  "mcp_requirements": {"qdrant_required": true, "context7_required": true}
}
EOF
}

_run_one() {  # DIR TRACKER PAYLOAD
  ( cd "$1" && printf '%s' "$3" | "$BASH" "$2" --event PostToolUse >/dev/null 2>&1 )
}

# _burst DIR TRACKER PAYLOAD COUNT — COUNT invocations at once, then wait.
_burst() {
  local i=0 pids=""
  while [ "$i" -lt "$4" ]; do
    _run_one "$1" "$2" "$3" &
    pids="$pids $!"
    i=$((i + 1))
  done
  # shellcheck disable=SC2086
  wait $pids
}

# _reader_start DIR — polls the ledger until DIR/.stop exists; one line in
# DIR/.bad per sighting of an empty or unparseable ledger.
_reader_start() {
  (
    L="$1/.claude/tool-usage.json"
    while [ ! -f "$1/.stop" ]; do
      if [ -f "$L" ]; then
        if [ ! -s "$L" ] || ! jq -e 'type == "object"' "$L" >/dev/null 2>&1; then
          echo bad >> "$1/.bad"
        fi
      fi
    done
  ) &
  READER_PID=$!
}
_reader_stop() { touch "$1/.stop"; wait "$READER_PID" 2>/dev/null; }

_calls()   { _num "$(jq -r '.calls | length' "$1/.claude/tool-usage.json" 2>/dev/null)"; }
_parses()  { [ -s "$1/.claude/tool-usage.json" ] && jq -e 'type == "object"' "$1/.claude/tool-usage.json" >/dev/null 2>&1; }
_bad()     { if [ -f "$1/.bad" ]; then _num "$(wc -l < "$1/.bad" | tr -d ' ')"; else printf '0\n'; fi; }
_debris()  { ls -a "$1/.claude" | grep -v -x -e '.' -e '..' -e 'tool-usage.json' | tr '\n' ' '; }

# _gate_one DIR GATE — one Write check; prints the gate's stdout (empty = allow).
_gate_one() { ( cd "$1" && "$BASH" "$2" < /dev/null 2>/dev/null ); }

# _seed_satisfied DIR — a ledger on which the gate allows.
_seed_satisfied() {
  mkdir -p "$1/.claude"
  cat > "$1/.claude/tool-usage.json" << 'EOF'
{
  "session_id": "bl314",
  "calls": [],
  "commits_since_last_context7": 0,
  "qdrant_find_succeeded": true,
  "context7_query_docs_succeeded": true,
  "mcp_gate_satisfied": false,
  "mcp_requirements": {"qdrant_required": true, "context7_required": true}
}
EOF
}

# _backdate PATH… — make each path older than any lock budget.
_backdate() { touch -t 202001010000 "$@" 2>/dev/null; }

# _await FILE — wait up to 10s for FILE to exist.
_await() {
  local i=0
  while [ ! -e "$1" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -e "$1" ]
}

# _mk_jq_shim DIR — a jq that, on a filter containing $SHIM_ON only, reads the
# ledger at once, then stalls 2s before emitting, marking DIR/started before
# the stall and DIR/done after the output is written. Reading first is what a
# slow writer looks like: it has already taken the ledger it will replace.
_mk_jq_shim() {
  cat > "$1/jq" << 'EOF'
#!/bin/sh
case "$*" in
  *"$SHIM_ON"*)
    "$REAL_JQ" "$@" > "$SHIM_DIR/out.$$"; rc=$?
    : > "$SHIM_DIR/started"; sleep 2
    cat "$SHIM_DIR/out.$$"; : > "$SHIM_DIR/done"; exit "$rc" ;;
esac
exec "$REAL_JQ" "$@"
EOF
  chmod +x "$1/jq"
}

# _signal_round SCRIPT SIGNAL STALL_ON [satisfied] — one hook run stalled
# inside the write whose filter contains STALL_ON, then SIGNAL to that hook's
# pid alone. A background job of a non-interactive shell starts with INT
# ignored, so perl restores INT's default before exec; the pid is unchanged.
# Sets R_RC R_LOCK R_DEBRIS R_CALLS R_SAT R_DIR.
_signal_round() {
  local d sh pid
  d=$(newtmp)
  if [ "${4:-}" = "satisfied" ]; then _seed_satisfied "$d"; else _seed "$d"; fi
  sh="$d/.shim"; mkdir -p "$sh"; _mk_jq_shim "$sh"
  printf '%s' "$FIND_PAYLOAD" > "$d/.payload"
  ( cd "$d" && PATH="$sh:$PATH" SHIM_DIR="$sh" SHIM_ON="$3" REAL_JQ="$REAL_JQ" \
      exec perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$BASH" "$1" --event PostToolUse < "$d/.payload" > /dev/null 2>&1 ) &
  pid=$!
  _await "$sh/started"
  kill "-$2" "$pid" 2>/dev/null
  { wait "$pid"; R_RC=$?; } 2>/dev/null
  _await "$sh/done"
  if [ -d "$d/.claude/tool-usage.json.lockdir" ]; then R_LOCK=held; else R_LOCK=cleared; fi
  R_DEBRIS=$(_debris "$d")
  R_CALLS=$(_calls "$d")
  R_SAT=$(jq -r '.mcp_gate_satisfied' "$d/.claude/tool-usage.json" 2>/dev/null)
  R_DIR="$d"
}

# _timed SECS DIR STDIN CMD… — run CMD in DIR. R_HUNG=1 if it is still running
# after SECS, and it is then killed, so a hang fails the case instead of the
# suite. R_OUT is its stdout.
# R_SECS is the command's own wall-clock time, read from perl's clock when it
# exits, so it does not stretch with the polling loop under load.
_timed() {
  local lim=$(( $1 * 10 )) dir="$2" in="$3" i=0 base sub t0
  base="$TOPTMP/timed-$RANDOM$RANDOM"
  shift 3
  t0=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
  ( cd "$dir" && { "$@" < "$in" > "$base.out" 2>/dev/null & echo "$!" > "$base.pid"; wait "$!"; }
    perl -MTime::HiRes=time -e 'printf "%.2f\n", time' > "$base.end"; : > "$base.done" ) 2>/dev/null &
  sub=$!
  while [ ! -e "$base.done" ] && [ "$i" -lt "$lim" ]; do sleep 0.1; i=$((i + 1)); done
  if [ -e "$base.done" ]; then
    R_HUNG=0
    R_SECS=$(perl -e 'printf "%.2f", $ARGV[1] - $ARGV[0]' "$t0" "$(cat "$base.end")")
  else
    R_HUNG=1
    R_SECS=""
    kill -KILL "$(cat "$base.pid" 2>/dev/null)" 2>/dev/null
  fi
  { wait "$sub"; } 2>/dev/null
  R_OUT=$(cat "$base.out" 2>/dev/null)
}

# _session_hook DIR SOURCE HOOK — one SessionStart run with a private HOME and
# no MCP servers configured.
_session_hook() {
  mkdir -p "$1/home"
  ( cd "$1" && printf '{"hook_event_name":"SessionStart","source":"%s"}' "$2" \
      | env HOME="$1/home" "$BASH" "$3" > /dev/null 2>&1 )
}

# _age PATH SECONDS — set PATH's mtime to now minus SECONDS (negative: ahead).
_age() { perl -e 'my $t = time - $ARGV[1]; utime($t, $t, $ARGV[0]) or exit 1' "$1" "$2"; }

# _mk_cat_shim DIR — a cat that stalls 2s when its stdin is the tracker's seed
# (it carries "session_id": null), marking DIR/started first. Any other use of
# cat passes straight through.
_mk_cat_shim() {
  cat > "$1/cat" << 'EOF'
#!/bin/sh
[ "$#" -gt 0 ] && exec "$REAL_CAT" "$@"
data=$("$REAL_CAT")
case "$data" in *'"session_id": null'*) : > "$SHIM_DIR/started"; sleep 2 ;; esac
printf '%s\n' "$data"
EOF
  chmod +x "$1/cat"
}

# _mk_stat_shim DIR MODE — a stat for DIR. MODE=bsd refuses GNU's `-c` and
# answers BSD's `-f %m` (through /usr/bin/stat where it is BSD's, through perl
# elsewhere), so the lib's fallback branch runs on every host. MODE=broken
# fails every call, so no lock's time can be read.
_mk_stat_shim() {
  if [ "$2" = "broken" ]; then
    printf '#!/bin/sh\nexit 1\n' > "$1/stat"
  else
    cat > "$1/stat" << 'EOF'
#!/bin/sh
[ "$1" = "-c" ] && exit 1
if [ "$1" = "-f" ] && [ "$2" = "%m" ] && [ "$#" -eq 3 ]; then
  if [ "$(uname)" = "Darwin" ] && [ -x /usr/bin/stat ]; then exec /usr/bin/stat -f %m "$3"; fi
  exec perl -e 'my @s = stat($ARGV[0]) or exit 1; print $s[9], "\n"' "$3"
fi
exit 1
EOF
  fi
  chmod +x "$1/stat"
}

# _run_ev DIR SCRIPT PAYLOAD EVENT [PATH_PREFIX] — one hook run with the event
# argument its payload names. Sets R_RC.
_run_ev() {
  ( cd "$1" && printf '%s' "$3" | PATH="${5:+$5:}$PATH" "$BASH" "$2" --event "$4" > /dev/null 2>&1 )
  R_RC=$?
}

# _site_race A_SCRIPT B_TRACKER PAYLOAD EVENT STALL_ON SEED [state-dir] — hook
# A reads the ledger and stalls inside the one write whose filter contains
# STALL_ON; meanwhile B, a plain find event, runs to completion. If A holds the
# lock for that write, B waits and both land. If A does not, A's write lands
# the ledger it read before B's row, and B's row is lost. SEED is none,
# satisfied or plain; state-dir makes process-state.json a directory, so the
# durable record fails. Sets R_SEEN (A reached that write) and R_CALLS.
_site_race() {
  local d sh apid
  d=$(newtmp)
  case "$6" in
    none) mkdir -p "$d/.claude" ;;
    satisfied) _seed_satisfied "$d" ;;
    *) _seed "$d" ;;
  esac
  [ "${7:-}" = "state-dir" ] && mkdir -p "$d/.claude/process-state.json"
  sh="$d/.shim"; mkdir -p "$sh"; _mk_jq_shim "$sh"
  printf '%s' "$3" > "$d/.payload"
  ( cd "$d" && PATH="$sh:$PATH" SHIM_DIR="$sh" SHIM_ON="$5" REAL_JQ="$REAL_JQ" \
      "$BASH" "$1" --event "$4" < "$d/.payload" > /dev/null 2>&1 ) &
  apid=$!
  if _await "$sh/started"; then R_SEEN=1; else R_SEEN=0; fi
  _run_one "$d" "$2" "$FIND_PAYLOAD"
  { wait "$apid"; } 2>/dev/null
  R_CALLS=$(_calls "$d")
}

# ── C0: control ─────────────────────────────────────────────────────────────
D=$(newtmp); _seed "$D"
i=0; while [ "$i" -lt "$N" ]; do _run_one "$D" "$TRACKER" "$FIND_PAYLOAD"; i=$((i + 1)); done
c0=$(_calls "$D")
if _parses "$D" && [ "$c0" = "$N" ]; then
  pass "C0: control, $N sequential invocations record $c0 call rows on a parseable ledger"
else
  fail_ "C0" "sequential run recorded $c0 of $N; the fixture is broken, so no other case means anything"
fi

# ── C1, C2, C4: the concurrent burst ────────────────────────────────────────
# _concurrent_round TRACKER — sets R_CALLS R_PARSES R_REQ R_FLAG R_BAD R_DEBRIS.
_concurrent_round() {
  local d; d=$(newtmp); _seed "$d"
  _reader_start "$d"
  _burst "$d" "$1" "$FIND_PAYLOAD" "$N"
  _reader_stop "$d"
  R_CALLS=$(_calls "$d")
  if _parses "$d"; then R_PARSES=1; else R_PARSES=0; fi
  R_REQ=$(jq -r '.mcp_requirements.qdrant_required // "absent"' "$d/.claude/tool-usage.json" 2>/dev/null)
  R_FLAG=$(jq -r '.qdrant_find_succeeded' "$d/.claude/tool-usage.json" 2>/dev/null)
  R_BAD=$(_bad "$d")
  R_DEBRIS=$(_debris "$d")
}

c1_fail=""; c2_fail=""; c4_fail=""
r=1
while [ "$r" -le "$ROUNDS" ]; do
  _concurrent_round "$TRACKER"
  if [ "$R_PARSES" != "1" ] || [ "$R_CALLS" != "$N" ] || [ "$R_REQ" != "true" ] || [ "$R_FLAG" != "true" ]; then
    c1_fail="$c1_fail round $r: parses=$R_PARSES calls=$R_CALLS/$N qdrant_required=$R_REQ find_succeeded=$R_FLAG;"
  fi
  [ "$R_BAD" != "0" ] && c2_fail="$c2_fail round $r: $R_BAD bad sightings;"
  [ -n "$R_DEBRIS" ] && c4_fail="$c4_fail round $r: $R_DEBRIS;"
  r=$((r + 1))
done
if [ -z "$c1_fail" ]; then
  pass "C1: $ROUNDS rounds of $N concurrent qdrant-find events each leave a parseable ledger with all $N call rows, mcp_requirements kept, find flags set"
else
  fail_ "C1" "$c1_fail"
fi
if [ -z "$c2_fail" ]; then
  pass "C2: a reader polling through every burst never saw an empty or unparseable ledger"
else
  fail_ "C2" "$c2_fail"
fi
if [ -z "$c4_fail" ]; then
  pass "C4: no temp or lock debris beside the ledger after any burst"
else
  fail_ "C4" "$c4_fail"
fi

# ── C3: concurrent commit counter ───────────────────────────────────────────
_commit_round() {  # TRACKER — sets R_COMMITS R_PARSES
  local d; d=$(newtmp); _seed "$d"
  _burst "$d" "$1" "$COMMIT_PAYLOAD" "$N"
  R_COMMITS=$(_num "$(jq -r '.commits_since_last_context7' "$d/.claude/tool-usage.json" 2>/dev/null)")
  if _parses "$d"; then R_PARSES=1; else R_PARSES=0; fi
}
c3_fail=""
r=1
while [ "$r" -le "$ROUNDS" ]; do
  _commit_round "$TRACKER"
  if [ "$R_PARSES" != "1" ] || [ "$R_COMMITS" != "$N" ]; then
    c3_fail="$c3_fail round $r: parses=$R_PARSES commits=$R_COMMITS/$N;"
  fi
  r=$((r + 1))
done
if [ -z "$c3_fail" ]; then
  pass "C3: $ROUNDS rounds of $N concurrent git-commit events each count exactly $N"
else
  fail_ "C3" "$c3_fail"
fi

# ── C5: concurrent seeding from no ledger ───────────────────────────────────
_seed_round() {  # TRACKER — sets R_CALLS R_PARSES R_REQ
  local d; d=$(newtmp)
  _burst "$d" "$1" "$FIND_PAYLOAD" "$N"
  R_CALLS=$(_calls "$d")
  if _parses "$d"; then R_PARSES=1; else R_PARSES=0; fi
  R_REQ=$(jq -r 'has("mcp_requirements")' "$d/.claude/tool-usage.json" 2>/dev/null)
}
c5_fail=""
r=1
while [ "$r" -le "$ROUNDS" ]; do
  _seed_round "$TRACKER"
  if [ "$R_PARSES" != "1" ] || [ "$R_CALLS" != "$N" ] || [ "$R_REQ" != "false" ]; then
    c5_fail="$c5_fail round $r: parses=$R_PARSES calls=$R_CALLS/$N has_requirements=$R_REQ;"
  fi
  r=$((r + 1))
done
if [ -z "$c5_fail" ]; then
  pass "C5: $ROUNDS rounds of $N concurrent events with no ledger each seed it once, record all $N calls, and seed no mcp_requirements"
else
  fail_ "C5" "$c5_fail"
fi

# ── C6: a burst behind a stale lock ─────────────────────────────────────────
# With STUCK=stuck the lock holds a file, so rmdir cannot remove it: the one
# break fails and every writer goes ahead unlocked, all at once.
_stale_round() {  # TRACKER [STUCK] — sets R_PARSES R_BAD R_CALLS
  local d; d=$(newtmp); _seed "$d"
  mkdir "$d/.claude/tool-usage.json.lockdir"
  [ "${2:-}" = "stuck" ] && : > "$d/.claude/tool-usage.json.lockdir/pin"
  _backdate "$d/.claude/tool-usage.json.lockdir"
  _reader_start "$d"
  _burst "$d" "$1" "$FIND_PAYLOAD" "$N"
  _reader_stop "$d"
  if _parses "$d"; then R_PARSES=1; else R_PARSES=0; fi
  R_BAD=$(_bad "$d")
  R_CALLS=$(_calls "$d")
}
c6_fail=""
for c6_mode in breakable stuck; do
  r=1
  while [ "$r" -le "$ROUNDS" ]; do
    _stale_round "$TRACKER" "$c6_mode"
    if [ "$R_PARSES" != "1" ] || [ "$R_BAD" != "0" ] || [ "$R_CALLS" -lt 1 ]; then
      c6_fail="$c6_fail $c6_mode round $r: parses=$R_PARSES bad=$R_BAD calls=$R_CALLS;"
    fi
    r=$((r + 1))
  done
done
if [ -z "$c6_fail" ]; then
  pass "C6: behind a stale lock, breakable or stuck, $ROUNDS rounds of $N concurrent events each keep the ledger parseable throughout and still record calls"
else
  fail_ "C6" "$c6_fail"
fi

# ── C7: one write past a stale lock ─────────────────────────────────────────
_single_stale() {  # TRACKER — sets R_CALLS R_LOCK
  local d; d=$(newtmp); _seed "$d"
  mkdir "$d/.claude/tool-usage.json.lockdir"
  _run_one "$d" "$1" "$FIND_PAYLOAD"
  R_CALLS=$(_calls "$d")
  if [ -d "$d/.claude/tool-usage.json.lockdir" ]; then R_LOCK=held; else R_LOCK=cleared; fi
}
_single_stale "$TRACKER"
if [ "$R_CALLS" = "1" ] && [ "$R_LOCK" = "cleared" ]; then
  pass "C7: one event past a stale lock records its call and clears the lock"
else
  fail_ "C7" "calls=$R_CALLS (want 1), lock=$R_LOCK (want cleared)"
fi

# ── C8: the gate's own writes ───────────────────────────────────────────────
# _gate_round GATE TRACKER MIXED — 12 concurrent gate checks (plus 12 find
# events when MIXED=1) on a satisfied ledger, then one more check. Sets
# R_PARSES R_BAD R_NEXT R_CALLS.
_gate_round() {
  local d i=0 pids=""
  d=$(newtmp); _seed_satisfied "$d"
  _reader_start "$d"
  while [ "$i" -lt "$N" ]; do
    _gate_one "$d" "$1" > /dev/null &
    pids="$pids $!"
    if [ "$3" = "1" ]; then _run_one "$d" "$2" "$FIND_PAYLOAD" & pids="$pids $!"; fi
    i=$((i + 1))
  done
  # shellcheck disable=SC2086
  wait $pids
  _reader_stop "$d"
  if _parses "$d"; then R_PARSES=1; else R_PARSES=0; fi
  R_BAD=$(_bad "$d")
  R_CALLS=$(_calls "$d")
  if [ -z "$(_gate_one "$d" "$1")" ]; then R_NEXT=allow; else R_NEXT=deny; fi
}
c8_fail=""
for mixed in 0 1; do
  r=1
  while [ "$r" -le "$ROUNDS" ]; do
    _gate_round "$GATE" "$TRACKER" "$mixed"
    want_calls=0; [ "$mixed" = "1" ] && want_calls=$N
    if [ "$R_PARSES" != "1" ] || [ "$R_BAD" != "0" ] || [ "$R_NEXT" != "allow" ] || [ "$R_CALLS" != "$want_calls" ]; then
      c8_fail="$c8_fail mixed=$mixed round $r: parses=$R_PARSES bad=$R_BAD next_write=$R_NEXT calls=$R_CALLS/$want_calls;"
    fi
    r=$((r + 1))
  done
done
if [ -z "$c8_fail" ]; then
  pass "C8: $N concurrent gate checks, alone and mixed with $N find events, keep the ledger whole and the next Write allowed ($ROUNDS rounds each)"
else
  fail_ "C8" "$c8_fail"
fi

# ── C9: a busy lock is waited for, not stolen ───────────────────────────────
# _wide_round TRACKER COUNT — sets R_CALLS R_PARSES.
_wide_round() {
  local d; d=$(newtmp); _seed "$d"
  _burst "$d" "$1" "$FIND_PAYLOAD" "$2"
  R_CALLS=$(_calls "$d")
  if _parses "$d"; then R_PARSES=1; else R_PARSES=0; fi
}
c9_fail=""
for wide in 40 80; do
  _wide_round "$TRACKER" "$wide"
  if [ "$R_PARSES" != "1" ] || [ "$R_CALLS" != "$wide" ]; then
    c9_fail="$c9_fail N=$wide: parses=$R_PARSES calls=$R_CALLS/$wide;"
  fi
done
if [ -z "$c9_fail" ]; then
  pass "C9: 40 and 80 concurrent find events record every call row"
else
  fail_ "C9" "$c9_fail"
fi

# ── C10: signals mid-write ──────────────────────────────────────────────────
_signal_round "$TRACKER" TERM '.calls +='
if [ "$R_RC" = "143" ] && [ "$R_LOCK" = "cleared" ] && [ -z "$R_DEBRIS" ] && [ "$R_CALLS" = "0" ]; then
  pass "C10: SIGTERM inside the tracker's write exits 143, releases the lock, lands nothing, leaves no temp"
else
  fail_ "C10" "rc=$R_RC (want 143) lock=$R_LOCK debris=[$R_DEBRIS] calls=$R_CALLS (want 0)"
fi

# C10b pins what INT actually does: bash defers it until the foreground jq
# exits, jq never received it, so the hook carries on and the write lands
# whole under the lock. Measured, not designed; it passes at round two's head.
_signal_round "$TRACKER" INT '.calls +='
if [ "$R_RC" = "0" ] && [ "$R_LOCK" = "cleared" ] && [ -z "$R_DEBRIS" ] && [ "$R_CALLS" = "1" ]; then
  pass "C10b: SIGINT to the tracker alone is waited out: rc=0, the write lands, the lock is released, no temp"
else
  fail_ "C10b" "rc=$R_RC (want 0) lock=$R_LOCK debris=[$R_DEBRIS] calls=$R_CALLS (want 1)"
fi

# The stall is on the WRITE's filter; `.mcp_gate_satisfied` alone also
# matches the gate's earlier read, which holds no lock.
_signal_round "$GATE" TERM '.mcp_gate_satisfied = true' satisfied
if [ "$R_RC" = "143" ] && [ "$R_LOCK" = "cleared" ] && [ -z "$R_DEBRIS" ] && [ "$R_SAT" = "false" ]; then
  pass "C10c: SIGTERM inside the gate's write exits 143, releases the lock, lands nothing, leaves no temp"
else
  fail_ "C10c" "rc=$R_RC (want 143) lock=$R_LOCK debris=[$R_DEBRIS] mcp_gate_satisfied=$R_SAT (want false)"
fi

# ── C11: SIGKILL mid-write, then recovery ───────────────────────────────────
_signal_round "$TRACKER" KILL '.calls +='
c11_left="lock=$R_LOCK debris=[$R_DEBRIS]"
# shellcheck disable=SC2046
_backdate "$R_DIR/.claude/tool-usage.json.lockdir" $(ls -d "$R_DIR"/.claude/tool-usage.json.* 2>/dev/null)
: > "$R_DIR/.claude/tool-usage.json.lw.LIVE01"
_run_one "$R_DIR" "$TRACKER" "$FIND_PAYLOAD"
c11_calls=$(_calls "$R_DIR"); c11_debris=$(_debris "$R_DIR")
if [ "$c11_calls" = "1" ] && [ "$c11_debris" = "tool-usage.json.lw.LIVE01 " ]; then
  pass "C11: after SIGKILL ($c11_left) the next event records its call and sweeps the aged lock and temp, and keeps a fresh one"
else
  fail_ "C11" "after SIGKILL ($c11_left): calls=$c11_calls (want 1) debris=[$c11_debris] (want only the fresh tool-usage.json.lw.LIVE01)"
fi

# ── C12: a filter that prints nothing lands nothing ─────────────────────────
# The probe write after it is the control: it proves the lib loaded and writes,
# so "unchanged" cannot pass because nothing ran at all.
_empty_filter() {  # LIB — sets R_SAME R_PROBE R_DEBRIS
  local d before
  d=$(newtmp); _seed "$d"
  before=$(cat "$d/.claude/tool-usage.json")
  ( cd "$d" && LW_LIB="$1" "$BASH" -c 'TOOL_USAGE=.claude/tool-usage.json; . "$LW_LIB"; _lw_update empty' ) > /dev/null 2>&1
  if [ "$(cat "$d/.claude/tool-usage.json")" = "$before" ]; then R_SAME=1; else R_SAME=0; fi
  R_DEBRIS=$(_debris "$d")
  ( cd "$d" && LW_LIB="$1" "$BASH" -c 'TOOL_USAGE=.claude/tool-usage.json; . "$LW_LIB"; _lw_update ".probe = 1"' ) > /dev/null 2>&1
  R_PROBE=$(jq -r '.probe' "$d/.claude/tool-usage.json" 2>/dev/null)
}
_empty_filter "$LIB"
if [ "$R_SAME" = "1" ] && [ -z "$R_DEBRIS" ] && [ "$R_PROBE" = "1" ]; then
  pass "C12: a jq filter with no output leaves the ledger as it was, and no temp; a real filter then lands"
else
  fail_ "C12" "ledger unchanged=$R_SAME (want 1) debris=[$R_DEBRIS] probe=$R_PROBE (want 1, proves the lib wrote)"
fi

# ── C13: an empty or unparseable ledger is reseeded ─────────────────────────
c13_fail=""
for bad_ledger in empty garbage; do
  d=$(newtmp); mkdir -p "$d/.claude"
  if [ "$bad_ledger" = "empty" ]; then : > "$d/.claude/tool-usage.json"; else printf '{"calls": [' > "$d/.claude/tool-usage.json"; fi
  _run_one "$d" "$TRACKER" "$FIND_PAYLOAD"
  c13_calls=$(_calls "$d")
  c13_req=$(jq -r 'has("mcp_requirements")' "$d/.claude/tool-usage.json" 2>/dev/null)
  c13_ok=$(jq -r '.qdrant_find_succeeded' "$d/.claude/tool-usage.json" 2>/dev/null)
  if ! _parses "$d" || [ "$c13_calls" != "1" ] || [ "$c13_req" != "false" ] || [ "$c13_ok" != "true" ]; then
    c13_fail="$c13_fail $bad_ledger: calls=$c13_calls has_requirements=$c13_req find_succeeded=$c13_ok;"
  fi
done
if [ -z "$c13_fail" ]; then
  pass "C13: a 0-byte and an unparseable ledger are each reseeded by the next event, which records its call and seeds no mcp_requirements"
else
  fail_ "C13" "$c13_fail"
fi

# ── C14: a failed write leaves no temp ──────────────────────────────────────
_failed_write() {  # GATE — sets R_DEBRIS R_OUT
  local d; d=$(newtmp); mkdir -p "$d/.claude"
  printf '{"calls": [' > "$d/.claude/tool-usage.json"
  R_OUT=$(_gate_one "$d" "$1")
  R_DEBRIS=$(_debris "$d")
}
_failed_write "$GATE"
if [ -n "$R_OUT" ] && [ -z "$R_DEBRIS" ]; then
  pass "C14: the gate on an unparseable ledger denies, and its failed write leaves no temp"
else
  fail_ "C14" "gate output bytes=${#R_OUT} (want a deny) debris=[$R_DEBRIS] (want none)"
fi

# ── C15: the sweep takes only its own temps ─────────────────────────────────
_sweep_neighbours() {  # TRACKER — sets R_LEFT
  local d; d=$(newtmp); _seed "$d"
  : > "$d/.claude/tool-usage.json.backup"
  : > "$d/.claude/tool-usage.json.bak"
  : > "$d/.claude/tool-usage.json.lw.AGED01"
  _backdate "$d/.claude/tool-usage.json.backup" "$d/.claude/tool-usage.json.bak" "$d/.claude/tool-usage.json.lw.AGED01"
  _run_one "$d" "$1" "$FIND_PAYLOAD"
  R_LEFT=$(_debris "$d")
}
_sweep_neighbours "$TRACKER"
if [ "$R_LEFT" = "tool-usage.json.backup tool-usage.json.bak " ]; then
  pass "C15: an aged tool-usage.json.backup and .bak survive the sweep, and an aged .lw. temp does not"
else
  fail_ "C15" "left=[$R_LEFT] (want the .backup and .bak only)"
fi

# ── C16: mkdir fails for a reason other than EEXIST ─────────────────────────
# POSIX mkdir() fails with EEXIST only when the lock is held. EACCES (a 0555
# .claude) and ENOTDIR (.claude is a file) are not contention: the hook must
# give up the lock at once and finish, the gate with its deny text. A read-only
# mount (EROFS) and a full disk (ENOSPC) cannot be made in a test; they take
# the same path as EACCES, since the lockdir never appears.
c16_fail=""; c16_skip=""
c16_shape() {  # LABEL WANT(deny|allow|exit) SCRIPT SEED(unsatisfied|satisfied|file) — adds to c16_fail
  local d; d=$(newtmp)
  case "$4" in
    unsatisfied) _seed "$d" ;;
    satisfied) _seed_satisfied "$d" ;;
    file) : > "$d/.claude" ;;
  esac
  if [ "$4" != "file" ]; then
    chmod 555 "$d/.claude"
    if ( : > "$d/.claude/.probe" ) 2>/dev/null; then
      rm -f "$d/.claude/.probe"; chmod 755 "$d/.claude"
      c16_skip="$c16_skip $1"
      return
    fi
  fi
  printf '%s' "$FIND_PAYLOAD" > "$d/.payload"
  _timed 10 "$d" "$d/.payload" "$BASH" "$3" --event PostToolUse
  [ -d "$d/.claude" ] && chmod 755 "$d/.claude"
  # "At once" means inside one lock budget: without this arm the lock loop
  # would still give up, but only after the budget, on every write.
  if [ "$R_HUNG" = "1" ]; then
    c16_fail="$c16_fail $1: still running after 10s;"
  elif ! perl -e 'exit($ARGV[0] < 3 ? 0 : 1)' "$R_SECS"; then
    c16_fail="$c16_fail $1: took ${R_SECS}s (want under the 3 s budget);"
  elif [ "$2" = "deny" ] && ! printf '%s' "$R_OUT" | grep '"permissionDecision": "deny"' >/dev/null; then
    c16_fail="$c16_fail $1: no deny (stdout bytes=${#R_OUT});"
  elif [ "$2" = "allow" ] && [ -n "$R_OUT" ]; then
    c16_fail="$c16_fail $1: stdout bytes=${#R_OUT} (want none, an allow);"
  fi
}
c16_shape "gate/EACCES/unsatisfied" deny  "$GATE"    unsatisfied
c16_shape "gate/EACCES/satisfied"   allow "$GATE"    satisfied
c16_shape "tracker/EACCES"          exit  "$TRACKER" unsatisfied
c16_shape "tracker/ENOTDIR"         exit  "$TRACKER" file
if [ -n "$c16_skip" ]; then
  skip_ "C16" "a 0555 directory is still writable here (running as root?), so EACCES cannot be made:$c16_skip"
fi
if [ -n "$c16_fail" ]; then
  fail_ "C16" "$c16_fail"
elif [ -z "$c16_skip" ]; then
  pass "C16: with .claude unwritable (EACCES) or not a directory (ENOTDIR), the gate denies or allows and the tracker finishes, each in under the 3 s budget"
fi

# ── C17: SessionStart writes the same ledger ────────────────────────────────
# _session_round HOOK TRACKER SOURCE COUNT — COUNT SessionStart runs at once,
# plus COUNT find events when SOURCE is resume. Sets R_PARSES R_BAD R_CALLS.
_session_round() {
  local d i=0 pids=""
  d=$(newtmp); _seed "$d"
  _reader_start "$d"
  while [ "$i" -lt "$4" ]; do
    _session_hook "$d" "$3" "$1" &
    pids="$pids $!"
    if [ "$3" = "resume" ]; then _run_one "$d" "$2" "$FIND_PAYLOAD" & pids="$pids $!"; fi
    i=$((i + 1))
  done
  # shellcheck disable=SC2086
  wait $pids
  _reader_stop "$d"
  if _parses "$d"; then R_PARSES=1; else R_PARSES=0; fi
  R_BAD=$(_bad "$d")
  R_CALLS=$(_calls "$d")
}
c17_fail=""
r=1
while [ "$r" -le "$ROUNDS" ]; do
  _session_round "$SESSION" "$TRACKER" resume "$N"
  if [ "$R_PARSES" != "1" ] || [ "$R_BAD" != "0" ] || [ "$R_CALLS" != "$N" ]; then
    c17_fail="$c17_fail resume round $r: parses=$R_PARSES bad=$R_BAD calls=$R_CALLS/$N;"
  fi
  _session_round "$SESSION" "$TRACKER" startup "$N"
  if [ "$R_PARSES" != "1" ] || [ "$R_BAD" != "0" ]; then
    c17_fail="$c17_fail startup round $r: parses=$R_PARSES bad=$R_BAD;"
  fi
  r=$((r + 1))
done
if [ -z "$c17_fail" ]; then
  pass "C17: $N concurrent SessionStart resumes mixed with $N find events keep every call row, and $N concurrent startups are never seen half-written ($ROUNDS rounds each)"
else
  fail_ "C17" "$c17_fail"
fi

# C17c: a startup must win over a tracker already part-way through a write.
# The ledger carries inherited successes (BL-236's clone case). A tracker
# reads it and stalls holding the lock; a startup then runs. Locked, the
# startup waits and lands last, so the inheritance is erased. If the startup
# write took no lock, the tracker's mv would land last and bring it back.
# The tracker's event is a `git commit`: its one write carries the whole
# ledger forward and earns no MCP success of its own.
_startup_race() {  # HOOK TRACKER — sets R_Q R_C R_COMMITS
  local d sh tpid
  d=$(newtmp); _seed_satisfied "$d"
  sh="$d/.shim"; mkdir -p "$sh"; _mk_jq_shim "$sh"
  printf '%s' "$COMMIT_PAYLOAD" > "$d/.payload"
  ( cd "$d" && PATH="$sh:$PATH" SHIM_DIR="$sh" SHIM_ON='.commits_since_last_context7 = ' REAL_JQ="$REAL_JQ" \
      "$BASH" "$2" --event PostToolUse < "$d/.payload" > /dev/null 2>&1 ) &
  tpid=$!
  _await "$sh/started"
  _session_hook "$d" startup "$1"
  { wait "$tpid"; } 2>/dev/null
  R_Q=$(jq -r '.qdrant_find_succeeded // false' "$d/.claude/tool-usage.json" 2>/dev/null)
  R_C=$(jq -r '.context7_query_docs_succeeded // false' "$d/.claude/tool-usage.json" 2>/dev/null)
  R_COMMITS=$(jq -r '.commits_since_last_context7' "$d/.claude/tool-usage.json" 2>/dev/null)
}
_startup_race "$SESSION" "$TRACKER"
if [ "$R_Q" = "false" ] && [ "$R_C" = "false" ]; then
  pass "C17c: a startup behind a tracker holding the lock lands last, so inherited successes stay erased (commits=$R_COMMITS)"
else
  fail_ "C17c" "qdrant_find_succeeded=$R_Q context7_query_docs_succeeded=$R_C (both want false): the tracker's write landed over the startup reset"
fi

# ── C5b: the seed is written under the lock ─────────────────────────────────
# Tracker A stalls while landing the seed, holding the seed lock. Tracker B
# then runs. Locked, B waits, finds A's seed and appends to it: two rows. If
# A's seed took no lock, B would seed and append first, and A's seed would
# then land over B's row: one row.
_seed_race() {  # TRACKER — sets R_SEEN R_CALLS
  local d sh apid
  d=$(newtmp); mkdir -p "$d/.claude"
  sh="$d/.shim"; mkdir -p "$sh"; _mk_cat_shim "$sh"
  printf '%s' "$FIND_PAYLOAD" > "$d/.payload"
  ( cd "$d" && PATH="$sh:$PATH" SHIM_DIR="$sh" REAL_CAT="$REAL_CAT" \
      "$BASH" "$1" --event PostToolUse < "$d/.payload" > /dev/null 2>&1 ) &
  apid=$!
  if _await "$sh/started"; then R_SEEN=1; else R_SEEN=0; fi
  _run_one "$d" "$1" "$FIND_PAYLOAD"
  { wait "$apid"; } 2>/dev/null
  R_CALLS=$(_calls "$d")
}
_seed_race "$TRACKER"
if [ "$R_SEEN" = "1" ] && [ "$R_CALLS" = "2" ]; then
  pass "C5b: a tracker that arrives while another is landing the seed waits for it and appends: 2 rows"
else
  fail_ "C5b" "stalled_in_seed=$R_SEEN (want 1) calls=$R_CALLS (want 2)"
fi

# ── C7a, C7f, C7u: the lock wait is bounded ────────────────────────────────
# _one_bounded DIR SCRIPT SECS [PATH_PREFIX] — one find event, killed if it runs
# past SECS. Sets R_HUNG R_CALLS R_LOCK.
_one_bounded() {
  printf '%s' "$FIND_PAYLOAD" > "$1/.payload"
  _timed "$3" "$1" "$1/.payload" env PATH="${4:+$4:}$PATH" "$BASH" "$2" --event PostToolUse
  R_CALLS=$(_calls "$1")
  if [ -d "$1/.claude/tool-usage.json.lockdir" ]; then R_LOCK=held; else R_LOCK=cleared; fi
}

# C7a: a lock 2 s past the 3 s budget is stale now, not in a minute.
_budget_round() {  # TRACKER
  local d; d=$(newtmp); _seed "$d"
  mkdir "$d/.claude/tool-usage.json.lockdir"; _age "$d/.claude/tool-usage.json.lockdir" 5
  _one_bounded "$d" "$1" 3
}
_budget_round "$TRACKER"
if [ "$R_HUNG" = "0" ] && [ "$R_CALLS" = "1" ] && [ "$R_LOCK" = "cleared" ]; then
  pass "C7a: a lock aged 5 s is broken at once: the call lands and the lock is cleared within 3 s"
else
  fail_ "C7a" "hung=$R_HUNG calls=$R_CALLS (want 1) lock=$R_LOCK (want cleared): the 3 s budget is not what breaks it"
fi

# C7f: a lock dated an hour ahead (a clock stepped back after a SIGKILL-left
# lock) is stale too; the tracker and the gate each finish.
_future_round() {  # TRACKER GATE
  local d; d=$(newtmp); _seed "$d"
  mkdir "$d/.claude/tool-usage.json.lockdir"; _age "$d/.claude/tool-usage.json.lockdir" -3600
  _one_bounded "$d" "$1" 10
  R_T_HUNG=$R_HUNG; R_T_CALLS=$R_CALLS
  d=$(newtmp); _seed "$d"
  mkdir "$d/.claude/tool-usage.json.lockdir"; _age "$d/.claude/tool-usage.json.lockdir" -3600
  _timed 10 "$d" /dev/null "$BASH" "$2"
  R_G_HUNG=$R_HUNG; R_G_OUT=$R_OUT
}
_future_round "$TRACKER" "$GATE"
if [ "$R_T_HUNG" = "0" ] && [ "$R_T_CALLS" = "1" ] && [ "$R_G_HUNG" = "0" ] \
   && printf '%s' "$R_G_OUT" | grep '"permissionDecision": "deny"' > /dev/null; then
  pass "C7f: behind a lock dated an hour ahead, the tracker records its call and the gate denies, each within 10 s"
else
  fail_ "C7f" "tracker hung=$R_T_HUNG calls=$R_T_CALLS (want 0, 1); gate hung=$R_G_HUNG stdout bytes=${#R_G_OUT} (want 0 and a deny)"
fi

# C7u: a lock whose time cannot be read is waited on for one budget per write,
# not for ever. A find event makes three locked writes, so 20 s bounds it.
_unreadable_round() {  # TRACKER
  local d sh; d=$(newtmp); _seed "$d"
  mkdir "$d/.claude/tool-usage.json.lockdir"
  sh="$d/.shim"; mkdir -p "$sh"; _mk_stat_shim "$sh" broken
  _one_bounded "$d" "$1" 20 "$sh"
}
_unreadable_round "$TRACKER"
if [ "$R_HUNG" = "0" ] && [ "$R_CALLS" = "1" ]; then
  pass "C7u: behind a lock whose time cannot be read, the tracker goes ahead within 20 s and records its call"
else
  fail_ "C7u" "hung=$R_HUNG (want 0) calls=$R_CALLS (want 1)"
fi

# ── C18: every locked write site takes the lock ─────────────────────────────
# One arm per site: the tracker's thirteen and the gate's two. Each arm stalls
# hook A inside that one write and races a find event against it (see
# _site_race). An arm is vacuous unless A reached the write, so seen=1 is part
# of the pass.
C18_ARMS="
del|none||$FIND_PAYLOAD|PostToolUse|del(.mcp_requirements)|2|tracker
row|plain||$FIND_PAYLOAD|PostToolUse|.calls +=|2|tracker
error|plain||$FAIL_PAYLOAD|PostToolUseFailure|.last_mcp_error = \$err|2|tracker
c7-called|plain||$C7Q_PAYLOAD|PostToolUse|.context7_called = true|2|tracker
c7-query|plain||$C7Q_PAYLOAD|PostToolUse|.context7_query_docs_succeeded = true|2|tracker
c7-resolve|plain||$C7R_PAYLOAD|PostToolUse|.context7_resolve_only_count = |2|tracker
find-called|plain||$FIND_PAYLOAD|PostToolUse|.qdrant_find_called = true|2|tracker
find-ok|plain||$FIND_PAYLOAD|PostToolUse|.qdrant_find_succeeded = true|2|tracker
find-interrupted|plain||$INT_PAYLOAD|PostToolUseFailure|.qdrant_find_interrupted = |2|tracker
find-failed|plain||$FAIL_PAYLOAD|PostToolUseFailure|.qdrant_find_failed = |2|tracker
store-called|plain||$STORE_PAYLOAD|PostToolUse|.qdrant_store_called = true|2|tracker
store-ok|plain||$STORE_PAYLOAD|PostToolUse|.qdrant_store_succeeded = true|2|tracker
store-record-failed|plain|state-dir|$STORE_PAYLOAD|PostToolUse|.qdrant_store_record_failed = |2|tracker
gate-allow|satisfied||-|-|.mcp_gate_satisfied = true|1|gate
gate-deny|plain||-|-|.mcp_gate_satisfied = false|1|gate
"
# _c18_arm SCRIPTS_DIR LABEL — run one arm against SCRIPTS_DIR's hooks. Sets
# R_ARM_OK and R_ARM_MSG.
_c18_arm() {
  local line seed extra payload event stall want who a
  line=$(printf '%s\n' "$C18_ARMS" | grep "^$2|")
  IFS='|' read -r _ seed extra payload event stall want who << EOF
$line
EOF
  if [ "$who" = "gate" ]; then a="$1/session-mcp-gate.sh"; else a="$1/track-tool-usage.sh"; fi
  _site_race "$a" "$1/track-tool-usage.sh" "$payload" "$event" "$stall" "$seed" "$extra"
  if [ "$R_SEEN" = "1" ] && [ "$R_CALLS" = "$want" ]; then R_ARM_OK=1; else R_ARM_OK=0; fi
  R_ARM_MSG="$2: seen=$R_SEEN calls=$R_CALLS/$want"
}
c18_fail=""; c18_n=0
for arm in $(printf '%s\n' "$C18_ARMS" | cut -d'|' -f1); do
  _c18_arm "$REPO_ROOT/scripts" "$arm"
  c18_n=$((c18_n + 1))
  [ "$R_ARM_OK" = "1" ] || c18_fail="$c18_fail $R_ARM_MSG;"
done
if [ -z "$c18_fail" ]; then
  pass "C18: each of $c18_n locked write sites, stalled mid-write, holds the lock: a racing find event waits and its row survives"
else
  fail_ "C18" "$c18_fail"
fi

# ── C19: the return codes the entry states ──────────────────────────────────
# C19a/b: a SessionStart whose ledger write cannot land (.claude at 0555) ends
# non-zero, on startup and on resume. C19c: the tracker without the lib exits 0
# and writes nothing. C19d: a failed mv is a failed write: rc 1, the ledger
# unchanged, no temp.
# _unlandable_round SESSION_HOOK — sets R_UNL_FAIL and R_UNL_SKIP.
_unlandable_round() {
  local src d rc
  R_UNL_FAIL=""; R_UNL_SKIP=""
  for src in startup resume; do
    d=$(newtmp); _seed "$d"; mkdir -p "$d/home"
    chmod 555 "$d/.claude"
    if ( : > "$d/.claude/.probe" ) 2>/dev/null; then
      rm -f "$d/.claude/.probe"; chmod 755 "$d/.claude"; R_UNL_SKIP="$R_UNL_SKIP $src"; continue
    fi
    printf '{"hook_event_name":"SessionStart","source":"%s"}' "$src" > "$d/.envelope"
    _timed 10 "$d" "$d/.envelope" env HOME="$d/home" "$BASH" "$1"
    rc=hung
    if [ "$R_HUNG" = "0" ]; then
      ( cd "$d" && env HOME="$d/home" "$BASH" "$1" < "$d/.envelope" > /dev/null 2>&1 ); rc=$?
    fi
    chmod 755 "$d/.claude"
    if [ "$R_HUNG" = "1" ] || [ "$rc" = "0" ]; then R_UNL_FAIL="$R_UNL_FAIL $src: hung=$R_HUNG rc=$rc (want non-zero);"; fi
  done
}
_unlandable_round "$SESSION"
c19_fail="$R_UNL_FAIL"; c19_skip="$R_UNL_SKIP"
_nolib_round() {  # TRACKER — sets R_RC R_LEDGER
  local d m; d=$(newtmp); m="$(newtmp)/scripts"; mkdir -p "$m"
  cp "$1" "$m/track-tool-usage.sh"
  _run_ev "$d" "$m/track-tool-usage.sh" "$FIND_PAYLOAD" PostToolUse
  if [ -e "$d/.claude/tool-usage.json" ]; then R_LEDGER=written; else R_LEDGER=none; fi
}
_nolib_round "$TRACKER"
[ "$R_RC" = "0" ] && [ "$R_LEDGER" = "none" ] || c19_fail="$c19_fail no-lib tracker: rc=$R_RC ledger=$R_LEDGER (want 0, none);"
_mv_fail_round() {  # LIB — sets R_RC R_SAME R_DEBRIS
  local d sh before; d=$(newtmp); _seed "$d"
  sh="$d/.shim"; mkdir -p "$sh"; printf '#!/bin/sh\nexit 1\n' > "$sh/mv"; chmod +x "$sh/mv"
  before=$(cat "$d/.claude/tool-usage.json")
  ( cd "$d" && PATH="$sh:$PATH" LW_LIB="$1" "$BASH" -c 'TOOL_USAGE=.claude/tool-usage.json; . "$LW_LIB"; _lw_update ".probe = 1"' ) > /dev/null 2>&1
  R_RC=$?
  if [ "$(cat "$d/.claude/tool-usage.json")" = "$before" ]; then R_SAME=1; else R_SAME=0; fi
  R_DEBRIS=$(ls -A "$d/.claude" | grep -v -x -e 'tool-usage.json' | tr '\n' ' ')
}
_mv_fail_round "$LIB"
[ "$R_RC" = "1" ] && [ "$R_SAME" = "1" ] && [ -z "$R_DEBRIS" ] || c19_fail="$c19_fail mv fails: rc=$R_RC unchanged=$R_SAME debris=[$R_DEBRIS] (want 1, 1, none);"
[ -n "$c19_skip" ] && skip_ "C19a/b" "a 0555 directory stays writable here (root?):$c19_skip"
if [ -z "$c19_fail" ]; then
  pass "C19: an unlandable SessionStart write ends non-zero (startup, resume); the lib-less tracker exits 0 and writes nothing; a failed mv returns 1 and leaves no temp"
else
  fail_ "C19" "$c19_fail"
fi

# ── C20: the BSD stat branch ────────────────────────────────────────────────
# GNU coreutils' stat is first on many macOS PATHs and is the only stat on
# Linux, so `stat -f %m` never ran. Under a shim that refuses `-c`, a stale lock
# is still read, broken and cleared, and an aged temp is still swept.
_bsd_round() {  # TRACKER — sets R_OK R_MSG
  local d sh; d=$(newtmp); _seed "$d"
  sh="$d/.shim"; mkdir -p "$sh"; _mk_stat_shim "$sh" bsd
  mkdir "$d/.claude/tool-usage.json.lockdir"; _age "$d/.claude/tool-usage.json.lockdir" 5
  : > "$d/.claude/tool-usage.json.lw.AGED01"; _age "$d/.claude/tool-usage.json.lw.AGED01" 60
  _one_bounded "$d" "$1" 3 "$sh"
  R_MSG="hung=$R_HUNG calls=$R_CALLS lock=$R_LOCK left=[$(_debris "$d")]"
  if [ "$R_HUNG" = "0" ] && [ "$R_CALLS" = "1" ] && [ "$R_LOCK" = "cleared" ] && [ -z "$(_debris "$d")" ]; then R_OK=1; else R_OK=0; fi
}
_bsd_round "$TRACKER"
if [ "$(uname)" = "Darwin" ]; then c20_via="/usr/bin/stat -f %m"; else c20_via="perl, BSD semantics"; fi
if [ "$R_OK" = "1" ]; then
  pass "C20: with only BSD's stat (via $c20_via), a lock aged 5 s is broken and cleared and an aged temp is swept, within 3 s"
else
  fail_ "C20" "via $c20_via: $R_MSG (want 0, 1, cleared, none left)"
fi

# ── C21: verify-install's row and fixer for the lib ─────────────────────────
_vi_round() {  # VERIFY_INSTALL LIBSRC_ROOT — sets R_ROW R_FIXED
  local d p h b fixer
  d=$(newtmp); p="$d/proj"; h="$d/home"; b="$d/bin"
  mkdir -p "$p/.claude" "$p/scripts/lib" "$h/.claude" "$h/.claude-dev-framework/.git" "$b"
  printf '#!/bin/sh\nexit 0\n' > "$b/claude"; chmod +x "$b/claude"
  printf '{"source_dir":"%s"}\n' "$2" > "$p/.claude/orchestrator-source.json"
  # To a file, not a pipe: verify-install exits 1 when it finds issues, and
  # under pipefail that would read a printed row as absent.
  ( cd "$p" && HOME="$h" PATH="$b:$PATH" "$BASH" "$1" --check-only > "$d/vi.txt" 2>&1 )
  if grep -F 'ledger-write lib missing (auto-fixable)' "$d/vi.txt" > /dev/null; then R_ROW=1; else R_ROW=0; fi
  fixer=$(grep '^fix_lib_copy_ledger-write()' "$1")
  ( cd "$p" && FIXER="$fixer" SOURCE_DIR="$2" "$BASH" -c 'has_source() { return 0; }; eval "$FIXER"; fix_lib_copy_ledger-write' ) > /dev/null 2>&1
  if cmp -s "$p/scripts/lib/ledger-write.sh" "$2/scripts/lib/ledger-write.sh"; then R_FIXED=1; else R_FIXED=0; fi
}
_vi_round "$REPO_ROOT/scripts/verify-install.sh" "$REPO_ROOT"
if [ "$R_ROW" = "1" ] && [ "$R_FIXED" = "1" ]; then
  pass "C21: verify-install --check-only reports 'ledger-write lib missing (auto-fixable)', and fix_lib_copy_ledger-write restores the lib byte for byte"
else
  fail_ "C21" "row=$R_ROW fixed=$R_FIXED (want 1, 1)"
fi

# ── C22: a temp a SIGKILL leaves is ignored ─────────────────────────────────
# It holds a full copy of the ledger until the next sweep, so `git add -A` must
# not take it. Asserted with git check-ignore, against this repo's .gitignore and
# the template a generated project gets.
c22_fail=""
for gi in "$REPO_ROOT/.gitignore" "$REPO_ROOT/templates/generated/gitignore-base.tmpl"; do
  d=$(newtmp)
  ( cd "$d" && git init -q ) > /dev/null 2>&1
  cp "$gi" "$d/.gitignore"
  ( cd "$d" && git check-ignore -q .claude/tool-usage.json.lw.AbC123 ) || c22_fail="$c22_fail ${gi#"$REPO_ROOT"/}: temp not ignored;"
  ( cd "$d" && git check-ignore -q .claude/tool-usage.json ) || c22_fail="$c22_fail ${gi#"$REPO_ROOT"/}: ledger not ignored;"
  ( cd "$d" && git check-ignore -q .claude/tool-usage.json.backup ) && c22_fail="$c22_fail ${gi#"$REPO_ROOT"/}: a .backup is ignored too;"
done
if [ -z "$c22_fail" ]; then
  pass "C22: .gitignore and the generated-project template ignore the lib's .lw. temps and the ledger, and not a user's .backup"
else
  fail_ "C22" "$c22_fail"
fi

# ── Mutants ─────────────────────────────────────────────────────────────────
# _mk_mutant NAME RELFILE MARKER FIND REPL — sets MUT_DIR to a mirror of the
# three hooks and their lib with RELFILE (under scripts/) mutated, or fails
# NAME. Location is proved, not assumed: the marker has one end-of-line site,
# and the diff is exactly one line replaced, at that marker's line number.
_mk_mutant() {
  local src="$REPO_ROOT/scripts/$2" f sites ln hunk changed
  MUT_DIR="$TOPTMP/mut-$1/scripts"
  mkdir -p "$MUT_DIR/lib"
  cp "$TRACKER" "$GATE" "$SESSION" "$MUT_DIR/"
  cp "$LIB" "$MUT_DIR/lib/"
  f="$MUT_DIR/$2"
  sites=$(_sites "$src" "$3")
  if [ "$sites" != "1" ]; then
    fail_ "$1" "marker '$3' has $sites end-of-line sites in $2 (want 1); the mutant cannot be placed"
    return 1
  fi
  ln=$(grep -n -- "$3\$" "$src" | cut -d: -f1)
  _mutate "$f" "$4" "$5"
  hunk=$(diff "$src" "$f" 2>/dev/null | head -1)
  changed=$(_changed_lines "$src" "$f")
  if [ "$changed" != "2" ] || [ "$hunk" != "${ln}c${ln}" ]; then
    fail_ "$1" "mutation changed $changed lines at hunk '$hunk' (want 2 lines at ${ln}c${ln}, the marker's line); it did not land where claimed"
    return 1
  fi
  if ! "$BASH" -n "$f" 2>/dev/null; then
    fail_ "$1" "mutant does not parse"
    return 1
  fi
  return 0
}

# M1: the shared temp name back. Only unlocked writes can collide on it, so
# only C6's stuck arm, where every writer goes ahead unlocked, sees it.
if _mk_mutant "M1" lib/ledger-write.sh "# BL-314-UNIQUE-TMP" \
     'tmp=$(mktemp "$TOOL_USAGE.lw.XXXXXX" 2>/dev/null) || tmp=""   # BL-314-UNIQUE-TMP' \
     'tmp="$TOOL_USAGE.tmp"   # BL-314-UNIQUE-TMP'; then
  m1_killed=""
  r=1
  while [ "$r" -le 6 ] && [ -z "$m1_killed" ]; do
    _stale_round "$MUT_DIR/track-tool-usage.sh" stuck
    if [ "$R_PARSES" != "1" ] || [ "$R_BAD" != "0" ]; then m1_killed="round $r: parses=$R_PARSES bad=$R_BAD"; fi
    r=$((r + 1))
  done
  if [ -n "$m1_killed" ]; then
    pass "M1: the shared temp name is killed by C6's stuck arm ($m1_killed)"
  else
    fail_ "M1" "shared temp name survived 6 stuck-lock rounds; C6 does not discriminate"
  fi
fi

# M2: the lock is never taken.
if _mk_mutant "M2" lib/ledger-write.sh "# BL-314-LOCK" \
     'while ! mkdir "$TOOL_USAGE.lockdir" 2>/dev/null; do   # BL-314-LOCK' \
     'while false; do   # BL-314-LOCK'; then
  m2_killed=""
  r=1
  while [ "$r" -le 6 ] && [ -z "$m2_killed" ]; do
    _concurrent_round "$MUT_DIR/track-tool-usage.sh"
    [ "$R_CALLS" != "$N" ] && m2_killed="C1 calls=$R_CALLS/$N"
    if [ -z "$m2_killed" ]; then
      _commit_round "$MUT_DIR/track-tool-usage.sh"
      [ "$R_COMMITS" != "$N" ] && m2_killed="C3 commits=$R_COMMITS/$N"
    fi
    r=$((r + 1))
  done
  if [ -n "$m2_killed" ]; then
    pass "M2: without the lock updates are lost ($m2_killed)"
  else
    fail_ "M2" "unlocked writers lost nothing in 6 rounds; C1 and C3 do not discriminate"
  fi
fi

# M4: a stale lock is never broken.
if _mk_mutant "M4" lib/ledger-write.sh "# BL-314-BREAK-STALE" \
     'rmdir "$TOOL_USAGE.lockdir" 2>/dev/null || :   # BL-314-BREAK-STALE' \
     ':   # BL-314-BREAK-STALE'; then
  _single_stale "$MUT_DIR/track-tool-usage.sh"
  if [ "$R_LOCK" = "held" ]; then
    pass "M4: without the breaker a stale lock outlives the write (calls=$R_CALLS, lock=$R_LOCK), so every later write waits out the budget"
  else
    fail_ "M4" "lock=$R_LOCK with the breaker removed; C7 does not discriminate"
  fi
fi

# MR: a held lock is broken whatever its age — the attempt-count breaker's
# failure, taken to its limit.
if _mk_mutant "MR" lib/ledger-write.sh "# BL-314-STALE-AGE" \
     'if [ "$age" -gt "$LW_BUDGET" ]; then   # BL-314-STALE-AGE' \
     'if true; then   # BL-314-STALE-AGE'; then
  _wide_round "$MUT_DIR/track-tool-usage.sh" 40
  if [ "$R_CALLS" != "40" ]; then
    pass "MR: breaking a live lock loses call rows (C9 calls=$R_CALLS/40)"
  else
    fail_ "MR" "breaking live locks lost nothing at N=40; C9 does not discriminate"
  fi
fi

# ME: the trap removed.
if _mk_mutant "ME" lib/ledger-write.sh "# BL-314-TRAP" \
     "trap '_lw_cleanup' EXIT   # BL-314-TRAP" \
     ':   # BL-314-TRAP'; then
  _signal_round "$MUT_DIR/track-tool-usage.sh" TERM '.calls +='
  if [ "$R_LOCK" = "held" ] || [ -n "$R_DEBRIS" ] || [ "$R_RC" != "143" ]; then
    pass "ME: without the trap a signalled write leaves debris (rc=$R_RC lock=$R_LOCK debris=[$R_DEBRIS])"
  else
    fail_ "ME" "the trap removed left nothing behind; C10 does not discriminate"
  fi
fi

# MF: the failure path's temp cleanup removed.
if _mk_mutant "MF" lib/ledger-write.sh "# BL-314-FAIL-CLEAN" \
     'rm -f "$tmp"   # BL-314-FAIL-CLEAN' \
     ':   # BL-314-FAIL-CLEAN'; then
  _failed_write "$MUT_DIR/session-mcp-gate.sh"
  if [ -n "$R_DEBRIS" ]; then
    pass "MF: without the cleanup a failed write leaves its temp (debris=[$R_DEBRIS])"
  else
    fail_ "MF" "no temp left with the cleanup removed; C14 does not discriminate"
  fi
fi

# MG: the non-empty check removed.
if _mk_mutant "MG" lib/ledger-write.sh "# BL-314-NONEMPTY" \
     '[ -s "$tmp" ] && mv "$tmp" "$TOOL_USAGE" 2>/dev/null; then   # BL-314-NONEMPTY' \
     'mv "$tmp" "$TOOL_USAGE" 2>/dev/null; then   # BL-314-NONEMPTY'; then
  _empty_filter "$MUT_DIR/lib/ledger-write.sh"
  if [ "$R_SAME" = "0" ]; then
    pass "MG: without the non-empty check a filter with no output empties the ledger"
  else
    fail_ "MG" "the ledger survived with the check removed; C12 does not discriminate"
  fi
fi

# MN: every mkdir failure read as contention again.
if _mk_mutant "MN" lib/ledger-write.sh "# BL-314-NOT-EEXIST" \
     '[ -e "$TOOL_USAGE.lockdir" ] || return 1   # BL-314-NOT-EEXIST' \
     ':   # BL-314-NOT-EEXIST'; then
  c16_fail=""; c16_skip=""
  c16_shape "gate/EACCES/unsatisfied" deny "$MUT_DIR/session-mcp-gate.sh" unsatisfied
  if [ -n "$c16_skip" ]; then
    skip_ "MN" "EACCES cannot be made here"
  elif [ -n "$c16_fail" ]; then
    pass "MN: reading EACCES as contention holds the gate for a budget again ($c16_fail)"
  else
    fail_ "MN" "the gate still answered with the check removed; C16 does not discriminate"
  fi
fi

# MX1: the gate installs no trap.
if _mk_mutant "MX1" session-mcp-gate.sh "# BL-314-GATE-TRAP" \
     '&& _lw_traps   # BL-314-GATE-TRAP' \
     '&& :   # BL-314-GATE-TRAP'; then
  _signal_round "$MUT_DIR/session-mcp-gate.sh" TERM '.mcp_gate_satisfied = true' satisfied
  if [ "$R_LOCK" = "held" ] || [ -n "$R_DEBRIS" ]; then
    pass "MX1: without its trap a signalled gate leaves debris (rc=$R_RC lock=$R_LOCK debris=[$R_DEBRIS])"
  else
    fail_ "MX1" "the gate's trap removed left nothing behind; C10c does not discriminate"
  fi
fi

# MS: the sweep takes any six-character suffix again.
if _mk_mutant "MS" lib/ledger-write.sh "# BL-314-SWEEP-GLOB" \
     '"$TOOL_USAGE".lw.??????; do' \
     '"$TOOL_USAGE".??????; do'; then
  _sweep_neighbours "$MUT_DIR/track-tool-usage.sh"
  if [ "$R_LEFT" != "tool-usage.json.backup tool-usage.json.bak " ]; then
    pass "MS: the wide glob deletes a neighbour or keeps an aged temp (left=[$R_LEFT])"
  else
    fail_ "MS" "the wide glob left the same files; C15 does not discriminate"
  fi
fi

# MX2: the sweep ignores age.
if _mk_mutant "MX2" lib/ledger-write.sh "# BL-314-SWEEP-AGE" \
     '[ $((now - mt)) -gt "$LW_BUDGET" ] && rm -f "$f" || :' \
     'rm -f "$f" || :'; then
  d=$(newtmp); _seed "$d"; : > "$d/.claude/tool-usage.json.lw.LIVE01"
  _run_one "$d" "$MUT_DIR/track-tool-usage.sh" "$FIND_PAYLOAD"
  if [ ! -e "$d/.claude/tool-usage.json.lw.LIVE01" ]; then
    pass "MX2: a sweep that ignores age deletes a fresh temp a live writer may own"
  else
    fail_ "MX2" "the fresh temp survived with the age check removed; C11 does not discriminate"
  fi
fi

# MT: SessionStart's startup write back to an unlocked truncating redirect.
if _mk_mutant "MT" session-test-gate-check.sh "# BL-314-SESSION-PUT" \
     '_lw_put << TUEOF   # BL-314-SESSION-PUT' \
     'cat > "$TOOL_USAGE" << TUEOF   # BL-314-SESSION-PUT'; then
  mt_killed=""
  r=1
  while [ "$r" -le 6 ] && [ -z "$mt_killed" ]; do
    _session_round "$MUT_DIR/session-test-gate-check.sh" "$TRACKER" startup "$N"
    if [ "$R_PARSES" != "1" ] || [ "$R_BAD" != "0" ]; then mt_killed="round $r: parses=$R_PARSES bad=$R_BAD"; fi
    r=$((r + 1))
  done
  if [ -n "$mt_killed" ]; then
    pass "MT: an unlocked startup write is seen half-written ($mt_killed)"
  else
    fail_ "MT" "unlocked startup writes were never seen half-written in 6 rounds; C17 does not discriminate"
  fi
fi

# MX5: SessionStart's whole-ledger write takes no lock.
if _mk_mutant "MX5" lib/ledger-write.sh "# BL-314-PUT-LOCK" \
     '_lw_lock || :   # BL-314-PUT-LOCK' \
     ':   # BL-314-PUT-LOCK'; then
  _startup_race "$MUT_DIR/session-test-gate-check.sh" "$MUT_DIR/track-tool-usage.sh"
  if [ "$R_Q" = "true" ] || [ "$R_C" = "true" ]; then
    pass "MX5: an unlocked startup write is overwritten by the stalled tracker, and the inherited successes return (qdrant=$R_Q context7=$R_C)"
  else
    fail_ "MX5" "the startup reset held without the lock; C17c does not discriminate"
  fi
fi

# _mk_mutant_line NAME RELFILE FIND REPL [full] — as _mk_mutant, for a line with
# no marker: FIND itself is the anchor. It must occur on exactly one line, and
# the diff must be exactly that line. `full` mirrors all of scripts/, for a
# script that sources its own siblings.
_mk_mutant_line() {
  local src="$REPO_ROOT/scripts/$2" f sites ln hunk changed
  MUT_DIR="$TOPTMP/mut-$1/scripts"
  if [ "${5:-}" = "full" ]; then
    mkdir -p "${MUT_DIR%/scripts}" && cp -R "$REPO_ROOT/scripts" "${MUT_DIR%/scripts}/"
  else
    mkdir -p "$MUT_DIR/lib"
    cp "$TRACKER" "$GATE" "$SESSION" "$MUT_DIR/"
    cp "$LIB" "$MUT_DIR/lib/"
  fi
  f="$MUT_DIR/$2"
  sites=$(_num "$(grep -c -F -- "$3" "$src")")
  if [ "$sites" != "1" ]; then
    fail_ "$1" "the find text occurs on $sites lines of $2 (want 1); the mutant cannot be placed"
    return 1
  fi
  ln=$(grep -n -F -- "$3" "$src" | cut -d: -f1)
  _mutate "$f" "$3" "$4"
  hunk=$(diff "$src" "$f" 2>/dev/null | head -1)
  changed=$(_changed_lines "$src" "$f")
  if [ "$changed" != "2" ] || [ "$hunk" != "${ln}c${ln}" ]; then
    fail_ "$1" "mutation changed $changed lines at hunk '$hunk' (want 2 lines at ${ln}c${ln}); it did not land where claimed"
    return 1
  fi
  if ! "$BASH" -n "$f" 2>/dev/null; then
    fail_ "$1" "mutant does not parse"
    return 1
  fi
  return 0
}

# MSL: the seed written without the lock.
if _mk_mutant "MSL" track-tool-usage.sh "# BL-314-SEED-LOCK" \
     '_lw_lock   # BL-314-SEED-LOCK' \
     ':   # BL-314-SEED-LOCK'; then
  msl_killed=""
  r=1
  while [ "$r" -le 3 ] && [ -z "$msl_killed" ]; do
    _seed_race "$MUT_DIR/track-tool-usage.sh"
    [ "$R_CALLS" != "2" ] && msl_killed="round $r: calls=$R_CALLS/2"
    r=$((r + 1))
  done
  if [ -n "$msl_killed" ]; then
    pass "MSL: a seed landed without the lock overwrites the racing tracker's row ($msl_killed)"
  else
    fail_ "MSL" "the unlocked seed lost nothing in 3 rounds; C5b does not discriminate"
  fi
fi

# MBUD: a 60 s budget.
if _mk_mutant_line "MBUD" lib/ledger-write.sh 'LW_BUDGET=3' 'LW_BUDGET=60'; then
  _budget_round "$MUT_DIR/track-tool-usage.sh"
  if [ "$R_HUNG" = "1" ] || [ "$R_CALLS" != "1" ] || [ "$R_LOCK" != "cleared" ]; then
    pass "MBUD: with a 60 s budget, a lock aged 5 s is still waited on (hung=$R_HUNG calls=$R_CALLS lock=$R_LOCK)"
  else
    fail_ "MBUD" "a 60 s budget broke a 5 s lock at once; C7a does not discriminate"
  fi
fi

# MFUT: a lock dated ahead never counts as stale.
if _mk_mutant "MFUT" lib/ledger-write.sh "# BL-314-FUTURE-STALE" \
     'age=$((LW_BUDGET + 1))' ':'; then
  _future_round "$MUT_DIR/track-tool-usage.sh" "$MUT_DIR/session-mcp-gate.sh"
  if [ "$R_T_HUNG" = "1" ] || [ "$R_G_HUNG" = "1" ]; then
    pass "MFUT: without the future arm, a lock dated an hour ahead holds the hooks (tracker hung=$R_T_HUNG, gate hung=$R_G_HUNG)"
  else
    fail_ "MFUT" "both hooks finished with the future arm removed; C7f does not discriminate"
  fi
fi

# MUNR: an unreadable lock time waited on for ever.
if _mk_mutant "MUNR" lib/ledger-write.sh "# BL-314-UNREADABLE" \
     '[ $((now - unread)) -gt "$LW_BUDGET" ] && return 1' ':'; then
  _unreadable_round "$MUT_DIR/track-tool-usage.sh"
  if [ "$R_HUNG" = "1" ]; then
    pass "MUNR: without the give-up, a lock whose time cannot be read holds the tracker past 20 s"
  else
    fail_ "MUNR" "the tracker finished (calls=$R_CALLS) with the give-up removed; C7u does not discriminate"
  fi
fi

# MBSD: the BSD stat fallback dropped.
if _mk_mutant_line "MBSD" lib/ledger-write.sh ' || stat -f %m "$1" 2>/dev/null' ''; then
  _bsd_round "$MUT_DIR/track-tool-usage.sh"
  if [ "$R_OK" = "0" ]; then
    pass "MBSD: without the BSD branch, a lock's time cannot be read where only BSD's stat exists ($R_MSG)"
  else
    fail_ "MBSD" "the stale lock was still broken and cleared; C20 does not discriminate"
  fi
fi

# MW-*: one write site at a time made to write without the lock.
C18_MUTANTS="
del|track-tool-usage.sh|_lw_update 'del(.mcp_requirements)'|_lw_write 'del(.mcp_requirements)'
row|track-tool-usage.sh|_lw_update --arg tool \"\$TOOL_NAME\" --arg ts|_lw_write --arg tool \"\$TOOL_NAME\" --arg ts
error|track-tool-usage.sh|_lw_update --arg err|_lw_write --arg err
c7-called|track-tool-usage.sh|_lw_update '.context7_called = true'|_lw_write '.context7_called = true'
c7-query|track-tool-usage.sh|_lw_update '.context7_query_docs_succeeded|_lw_write '.context7_query_docs_succeeded
c7-resolve|track-tool-usage.sh|_lw_update '.context7_resolve_only_count|_lw_write '.context7_resolve_only_count
find-called|track-tool-usage.sh|_lw_update '.qdrant_find_called = true'|_lw_write '.qdrant_find_called = true'
find-ok|track-tool-usage.sh|_lw_update --argjson empty|_lw_write --argjson empty
find-interrupted|track-tool-usage.sh|_lw_update '.qdrant_find_interrupted|_lw_write '.qdrant_find_interrupted
find-failed|track-tool-usage.sh|_lw_update '.qdrant_find_failed|_lw_write '.qdrant_find_failed
store-called|track-tool-usage.sh|_lw_update '.qdrant_store_called|_lw_write '.qdrant_store_called
store-ok|track-tool-usage.sh|_lw_update '.qdrant_store_succeeded|_lw_write '.qdrant_store_succeeded
store-record-failed|track-tool-usage.sh|_lw_update '.qdrant_store_record_failed|_lw_write '.qdrant_store_record_failed
gate-allow|session-mcp-gate.sh|_lw_update '.mcp_gate_satisfied = true'|_lw_write '.mcp_gate_satisfied = true'
gate-deny|session-mcp-gate.sh|_lw_update '.mcp_gate_satisfied = false'|_lw_write '.mcp_gate_satisfied = false'
"
mw_killed=0; mw_total=0
while IFS='|' read -r mw_arm mw_file mw_find mw_repl; do
  [ -z "$mw_arm" ] && continue
  mw_total=$((mw_total + 1))
  if _mk_mutant_line "MW-$mw_arm" "$mw_file" "$mw_find" "$mw_repl"; then
    _c18_arm "$MUT_DIR" "$mw_arm"
    if [ "$R_ARM_OK" = "0" ]; then
      mw_killed=$((mw_killed + 1))
    else
      fail_ "MW-$mw_arm" "the unlocked write lost nothing ($R_ARM_MSG); C18's arm does not discriminate"
    fi
  fi
done << EOF
$C18_MUTANTS
EOF
[ "$mw_killed" = "$mw_total" ] && pass "MW: each of $mw_total write sites, made to write without the lock, loses the racing row (C18, one arm each)"

# ML38: _lw_put reports success on a failed write.
if _mk_mutant_line "ML38" lib/ledger-write.sh '_lw_land cat || rc=$?' '_lw_land cat || :'; then
  _unlandable_round "$MUT_DIR/session-test-gate-check.sh"
  if [ -n "$R_UNL_FAIL" ]; then
    pass "ML38: a _lw_put that swallows its failure lets an unlandable SessionStart exit 0 ($R_UNL_FAIL)"
  elif [ -n "$R_UNL_SKIP" ]; then
    skip_ "ML38" "EACCES cannot be made here"
  else
    fail_ "ML38" "SessionStart still ended non-zero; C19 does not discriminate"
  fi
fi

# ML25: a mktemp failure read as success.
if _mk_mutant_line "ML25" lib/ledger-write.sh '[ -n "$tmp" ] || return 1' '[ -n "$tmp" ] || return 0'; then
  _unlandable_round "$MUT_DIR/session-test-gate-check.sh"
  if [ -n "$R_UNL_FAIL" ]; then
    pass "ML25: a mktemp failure read as success lets an unlandable SessionStart exit 0 ($R_UNL_FAIL)"
  elif [ -n "$R_UNL_SKIP" ]; then
    skip_ "ML25" "EACCES cannot be made here"
  else
    fail_ "ML25" "SessionStart still ended non-zero; C19 does not discriminate"
  fi
fi

# ML28: an mv failure read as success.
if _mk_mutant_line "ML28" lib/ledger-write.sh 'mv "$tmp" "$TOOL_USAGE" 2>/dev/null; then' '{ mv "$tmp" "$TOOL_USAGE" 2>/dev/null || :; }; then'; then
  _mv_fail_round "$MUT_DIR/lib/ledger-write.sh"
  if [ "$R_RC" != "1" ] || [ -n "$R_DEBRIS" ]; then
    pass "ML28: a failed mv read as success returns rc=$R_RC and leaves [$R_DEBRIS]"
  else
    fail_ "ML28" "the failed mv still returned 1 and left nothing; C19 does not discriminate"
  fi
fi

# MT02: the tracker without its lib exits 1.
if _mk_mutant_line "MT02" track-tool-usage.sh '[ -f "$SCRIPT_DIR/lib/ledger-write.sh" ] || exit 0' '[ -f "$SCRIPT_DIR/lib/ledger-write.sh" ] || exit 1'; then
  _nolib_round "$MUT_DIR/track-tool-usage.sh"
  if [ "$R_RC" != "0" ]; then
    pass "MT02: a lib-less tracker exiting 1 is seen (rc=$R_RC)"
  else
    fail_ "MT02" "rc=0 with the exit changed; C19 does not discriminate"
  fi
fi

# MV01, MV02: verify-install's row pointed elsewhere, and its fixer disabled.
if _mk_mutant_line "MV01" verify-install.sh '    "scripts/lib/ledger-write.sh"' '    "scripts/lib/accumulation.sh"' full; then
  _vi_round "$MUT_DIR/verify-install.sh" "$REPO_ROOT"
  if [ "$R_ROW" = "0" ]; then pass "MV01: with the row pointed at another lib, the missing ledger lib goes unreported"
  else fail_ "MV01" "the row was still reported; C21 does not discriminate"; fi
fi
if _mk_mutant_line "MV02" verify-install.sh 'fix_lib_copy_ledger-write()      { if has_source' 'fix_lib_copy_ledger-write()      { if false' full; then
  _vi_round "$MUT_DIR/verify-install.sh" "$REPO_ROOT"
  if [ "$R_FIXED" = "0" ]; then pass "MV02: with the fixer disabled, the lib is not restored"
  else fail_ "MV02" "the lib was still restored; C21 does not discriminate"; fi
fi

# MGI: each ignore file without its temp line (exactly that line removed).
mgi_fail=""
for gi in "$REPO_ROOT/.gitignore" "$REPO_ROOT/templates/generated/gitignore-base.tmpl"; do
  d=$(newtmp)
  ( cd "$d" && git init -q ) > /dev/null 2>&1
  grep -v -x -F '.claude/tool-usage.json.lw.*' "$gi" > "$d/.gitignore"
  mgi_removed=$(_changed_lines "$gi" "$d/.gitignore")
  if [ "$mgi_removed" != "1" ]; then
    mgi_fail="$mgi_fail ${gi#"$REPO_ROOT"/}: removed $mgi_removed lines (want 1);"
  elif ( cd "$d" && git check-ignore -q .claude/tool-usage.json.lw.AbC123 ); then
    mgi_fail="$mgi_fail ${gi#"$REPO_ROOT"/}: temp still ignored without the line;"
  fi
done
if [ -z "$mgi_fail" ]; then
  pass "MGI: without its one temp line, neither ignore file ignores the lib's temps (C22 discriminates)"
else
  fail_ "MGI" "$mgi_fail"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-bl358-lock-primitive.sh
#
# BL-358 — the lock under every locked writer of .claude state. Twelve writers
# took `while ! mkdir "$file.lockdir"` as their mutex. uutils coreutils 0.10.0
# (Ubuntu 26.04's default coreutils) exits 0 when its own mkdir(2) fails with
# EEXIST on a name that is a directory (uutils #13970, fixed in 0.11.0), so two
# writers held one lock at once and updates were lost: the tool-usage ledger in
# CI, and in principle every writer below. scripts/lib/lock.sh replaces the
# primitive with an O_EXCL create of a lock FILE (bash's `set -C`), which asks
# no coreutils whether it was taken. The ledger's own lock is pinned by
# tests/test-bl314-tool-usage-concurrent.sh (C26-C29); this suite pins the
# primitive and the other eleven writers.
#
# Cases:
#   L1  40 contenders, 20 rounds, one fresh name each round: exactly one
#       winner in every round, under a mkdir that behaves like uutils 0.10.0.
#   L2  a name that is already taken — by a lock file, a directory, a dangling
#       link, a link to /dev/null, a FIFO — is not taken again, at once.
#   L3  release removes the lock; a directory that refuses the create gives 1
#       and creates nothing.
#   S   the eleven writers, each run by the function the script ships
#       (extracted, never copied by hand), under the uutils-like mkdir and a
#       jq that reads its input at once and answers 50 ms later, which holds
#       every read-modify-write open long enough for a racing writer to land:
#         S-<site>      eight at once (and, for a writer whose record is one
#                       key, eight of a sibling writer of the same file):
#                       every update lands, and no lock is left
#         S-<site>-nolock  without lib/lock.sh: refused within 2 s, stderr names
#                       lib/lock.sh, the state file byte for byte
#         S-<site>-term TERM to the writer's process group inside its write:
#                       no lock and no temp left
#       sites: gate-date, reviewer, accum, sa (check-phase-gate.sh), p3-attest,
#       p3-license (run-phase3-validation.sh), tt (track-tool-usage.sh's
#       _tt_record_accumulation), ba-append, ba-close, ba-approvals, ba-rebind
#       (lib/bypass-audit.sh).
#         S-<site>-refuse  the three that can refuse after taking the lock
#                       (ba-append on a ledger that is not one JSON array,
#                       accum and tt with a directory at the state file's
#                       name) release it on the way out.
#         S-sa-remedy   without lib/lock.sh the single-authority attestation
#                       is refused (status 6) and the refusal names the lib
#                       and verify-install.sh --auto-fix.
#   E1  check-phase-gate.sh records a gate date with lib/lock.sh beside it, and
#       without it says so and records nothing (its own load of the lib).
#   E2  run-phase3-validation.sh --attest: the same, for the driver's load.
#   E3  lib/bypass-audit.sh sourced alone, from a project folder: it appends
#       with lib/lock.sh beside it, and without it refuses naming the lib and
#       writes nothing (its own load; the S driver loads lib/lock.sh first).
#   G1  the transition gap, measured: a <file>.lockdir held by a script from
#       before BL-358 neither blocks a new writer nor is touched by it.
#   P1  init.sh ships lib/lock.sh, so --sync-framework and adoption, which
#       derive their set from init.sh's cp lines, ship it too.
#   P2  upgrade-project.sh's .gitignore backfill adds both lock lines to an
#       existing project, once; adoption's .claude/.gitignore ignores them.
#
# Mutants (each placed in a mirror and proved to land on exactly one line):
#   MLN `set -C` dropped from the primitive: killed by L1.
#   MLP the primitive's "something is there" test dropped: killed by L2.
#   per site: A (no lock taken; killed by S-<site>), N (the missing-lib refusal
#   dropped; S-<site>-nolock), R (no release after the write; S-<site>),
#   T (the trap no longer releases; S-<site>-term) — 44. MRX-<site> the
#   release on a refusal inside the lock dropped: S-<site>-refuse. MS6 the
#   status-6 remedy arm dropped: S-sa-remedy.
#   ML1, ML2 check-phase-gate.sh's and run-phase3-validation.sh's load of the
#   lib dropped: killed by E1, E2. ML3 lib/bypass-audit.sh's trial load
#   skipped, ML4 its folder read as `.`: killed by E3.
#   MP1 the cp line dropped: P1. MP2 the backfill's lock line dropped: P2.
#   MP3 adoption's lock rule dropped: P2.
#
# The scripts under test run as "$BASH" (the runner's interpreter), never by
# their shebang. Hermetic: temp dirs only, no network, no `timeout`.
# bash 3.2 compatible: no ${var,,}, no declare -A, no mapfile.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCKLIB="$REPO_ROOT/scripts/lib/lock.sh"
REAL_JQ="$(command -v jq)"
REAL_MKDIR="$(command -v mkdir)"

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

if [ ! -f "$LOCKLIB" ] || [ -z "$REAL_JQ" ]; then
  echo "  [FAIL] setup — scripts/lib/lock.sh or jq missing"
  echo ""
  echo "Results: 0 passed, 1 failed, 0 skipped"
  exit 1
fi

echo "BL-358: the lock primitive and the writers on it (interpreter: $BASH, $BASH_VERSION)"

# _limit SECS CMD… — run CMD in a process group of its own; after SECS the whole
# group is sent TERM and the status is 142. A writer that spins is stopped with
# every process it started, not left running behind the case.
_limit() {
  perl -e '
    my $s = shift; setpgrp(0, 0);
    my $pid = fork(); die "fork: $!" unless defined $pid;
    if ($pid == 0) { exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { $SIG{TERM} = "IGNORE"; kill "TERM", -$$; exit 142 };
    alarm $s; waitpid($pid, 0); alarm 0;
    exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
  ' "$@"
}

# A mkdir that, like uutils coreutils 0.10.0, reports success when its mkdir(2)
# fails on a name that is a directory — on every call, not only inside uutils'
# race window, so the defect shows on any host.
UU="$(newtmp)"
cat > "$UU/mkdir" << EOF
#!/bin/sh
"$REAL_MKDIR" "\$@" 2>/dev/null && exit 0
rc=\$?
for t in "\$@"; do :; done
[ -d "\$t" ] && exit 0
exit "\$rc"
EOF
# A jq that reads its input at once and answers 50 ms later: a writer that
# does not lock has read the file and not yet replaced it while others land.
cat > "$UU/jq" << EOF
#!/bin/sh
out=\$("$REAL_JQ" "\$@"); rc=\$?
sleep 0.05
[ -n "\$out" ] && printf '%s\\n' "\$out"
exit "\$rc"
EOF
chmod +x "$UU/mkdir" "$UU/jq"
SITE_PATH="$UU:$PATH"
uu_probe="$(newtmp)"
if ! ( PATH="$SITE_PATH"; mkdir "$uu_probe/x" && mkdir "$uu_probe/x" ) 2>/dev/null; then
  fail_ "setup (meta)" "the uutils-like mkdir does not report a second mkdir of one name as a success; every case below would prove nothing about it"
fi

# ── L1: one winner per round ────────────────────────────────────────────────
# _race_rounds LOCKLIB ROUNDS N — sets R_MULTI R_ZERO.
_race_rounds() {
  local lib="$1" rounds="$2" n="$3" base r i d w pids
  base="$(newtmp)"; R_MULTI=0; R_ZERO=0; r=1
  while [ "$r" -le "$rounds" ]; do
    d="$base/r$r"; mkdir "$d"; i=0; pids=""
    while [ "$i" -lt "$n" ]; do
      ( . "$lib"; while [ ! -e "$d/go" ]; do :; done; soif_lock_try "$d/x.lock" && echo w >> "$d/wins" ) &
      pids="$pids $!"; i=$((i + 1))
    done
    : > "$d/go"
    # shellcheck disable=SC2086
    wait $pids
    w=0; [ -f "$d/wins" ] && w=$(_num "$(wc -l < "$d/wins" | tr -d ' ')")
    [ "$w" -gt 1 ] && R_MULTI=$((R_MULTI + 1))
    [ "$w" -eq 0 ] && R_ZERO=$((R_ZERO + 1))
    r=$((r + 1))
  done
}
L1_SAVED_PATH=$PATH; PATH="$SITE_PATH"
_race_rounds "$LOCKLIB" 20 40
PATH=$L1_SAVED_PATH
if [ "$R_MULTI" = "0" ] && [ "$R_ZERO" = "0" ]; then
  pass "L1: 20 rounds of 40 contenders on a fresh name, under the uutils-like mkdir: exactly one winner every round"
else
  fail_ "L1" "rounds with more than one winner=$R_MULTI, with none=$R_ZERO (want 0, 0)"
fi

# ── L2: a taken name is not taken again ─────────────────────────────────────
# _taken_round LOCKLIB — sets R_L2 to every shape that was taken anyway.
_taken_round() {
  local d shape rc
  R_L2=""
  for shape in file dir dangling devnull fifo; do
    d="$(newtmp)"
    case "$shape" in
      file)     : > "$d/x.lock" ;;
      dir)      mkdir "$d/x.lock" ;;
      dangling) ln -s "$d/nowhere" "$d/x.lock" ;;
      devnull)  ln -s /dev/null "$d/x.lock" ;;
      fifo)     mkfifo "$d/x.lock" ;;
    esac
    _limit 3 "$BASH" -c '. "$1"; soif_lock_try "$2"' _ "$1" "$d/x.lock" > /dev/null 2>&1; rc=$?
    [ "$rc" = "1" ] || R_L2="$R_L2 $shape: rc=$rc (want 1);"
  done
}
_taken_round "$LOCKLIB"
if [ -z "$R_L2" ]; then
  pass "L2: a name held by a lock file, a directory, a dangling link, a link to /dev/null or a FIFO is not taken, and nothing blocks"
else
  fail_ "L2" "$R_L2"
fi

# ── L3: release, and a directory that refuses the create ────────────────────
_release_round() {  # LOCKLIB — sets R_L3
  local d rc
  R_L3=""
  d="$(newtmp)"
  ( . "$1"; soif_lock_try "$d/x.lock" && soif_lock_release "$d/x.lock" && soif_lock_try "$d/x.lock" ) || R_L3="$R_L3 take, release, take again failed;"
  [ -f "$d/x.lock" ] || R_L3="$R_L3 the second take left no lock;"
  d="$(newtmp)"; mkdir "$d/ro"; chmod 555 "$d/ro"
  if ( : > "$d/ro/.probe" ) 2>/dev/null; then
    R_L3_SKIP="a 0555 directory stays writable here (root?)"
  else
    ( . "$1"; soif_lock_try "$d/ro/x.lock" ); rc=$?
    [ "$rc" = "1" ] || R_L3="$R_L3 read-only directory: rc=$rc (want 1);"
    [ -e "$d/ro/x.lock" ] && R_L3="$R_L3 read-only directory: a lock appeared;"
  fi
  chmod 755 "$d/ro"
}
R_L3_SKIP=""
_release_round "$LOCKLIB"
[ -n "$R_L3_SKIP" ] && skip_ "L3 (read-only arm)" "$R_L3_SKIP"
if [ -z "$R_L3" ]; then
  pass "L3: a released lock can be taken again, and a directory that refuses the create gives 1 and creates nothing"
else
  fail_ "L3" "$R_L3"
fi

# ── S: the eleven writers ───────────────────────────────────────────────────
# _fn FILE NAME — NAME's definition in FILE, from `NAME() {` to the first `}`
# at column 0 after it.
_fn() { awk -v n="$2" '$0 == n "() {" {p=1} p {print} p && /^}$/ {exit}' "$1"; }

SITES="gate-date reviewer accum sa p3-attest p3-license tt ba-append ba-close ba-approvals ba-rebind"
SHA="$(printf '%064d' 0)"
STORE_PAYLOAD='{"tool_name":"mcp__qdrant__qdrant-store","hook_event_name":"PostToolUse","tool_response":[{"type":"text","text":"stored"}]}'
NB=8

# _mirror DIR [nolock] — the writers' scripts and libs under DIR/scripts.
_mirror() {
  mkdir -p "$1/scripts/lib"
  cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$REPO_ROOT/scripts/run-phase3-validation.sh" \
     "$REPO_ROOT/scripts/track-tool-usage.sh" "$1/scripts/"
  cp "$REPO_ROOT/scripts/lib/ledger-write.sh" "$REPO_ROOT/scripts/lib/bypass-audit.sh" \
     "$REPO_ROOT/scripts/lib/accumulation.sh" "$1/scripts/lib/"
  [ "${2:-}" = "nolock" ] || cp "$LOCKLIB" "$1/scripts/lib/"
}

# _mk_driver SCRIPTS_DIR — writes SCRIPTS_DIR/driver.sh: the eight gate and
# Phase 3 writers as their scripts define them, and lib/bypass-audit.sh, then
# runs "$@". lib/lock.sh is sourced only if it is there, as the scripts do.
_mk_driver() {
  local s="$1" fn
  {
    echo 'set -uo pipefail'
    echo "RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''"
    echo 'PHASE_STATE=.claude/phase-state.json; STATE_FILE=.claude/phase-state.json'
    printf 'SCRIPT_DIR=%q\n' "$s"
    echo '_cpg_gate_actor() { printf tester; }'
    printf '. %q\n' "$s/lib/accumulation.sh"
    printf 'if [ -f %q ]; then . %q; fi\n' "$s/lib/lock.sh" "$s/lib/lock.sh"
    for fn in _cpg_need_lock _cpg_record_gate_date _cpg_record_reviewer_attestation _cpg_record_accum_attestation _cpg_record_single_authority_attestation _cpg_single_authority_gate; do
      _fn "$s/check-phase-gate.sh" "$fn"
    done
    for fn in _p3_need_lock _p3_write_attestation _p3_write_license_exception; do
      _fn "$s/run-phase3-validation.sh" "$fn"
    done
    _fn "$s/track-tool-usage.sh" _tt_record_accumulation
    printf '. %q\n' "$s/lib/bypass-audit.sh"
    echo '"$@"'
  } > "$s/driver.sh"
  for fn in _cpg_record_gate_date _cpg_record_reviewer_attestation _cpg_record_accum_attestation _cpg_record_single_authority_attestation _p3_write_attestation _p3_write_license_exception _tt_record_accumulation bypass_audit_append; do
    "$BASH" -c '. "$1" true; declare -F "$2" >/dev/null' _ "$s/driver.sh" "$fn" 2>/dev/null || return 1
  done
}

# _proj DIR — a project holding every state file the writers touch.
_proj() {
  mkdir -p "$1/.claude"
  printf '{"phase3":{"attestations":{}},"gates":{}}\n' > "$1/.claude/phase-state.json"
  printf '{}\n' > "$1/.claude/process-state.json"
  printf '[]\n' > "$1/.claude/bypass-audit.json"
  printf '{"event":"approval","source":"pick","sentinel_sha256":"%s","pick":"A2","picked_at":"2026-01-01T00:00:00Z","question":"q","approves":"none","option_text":"x"}\n' "$SHA" > "$1/.claude/approvals.jsonl"
}

# _call SITE I SCRIPTS_DIR PROJECT — one writer of SITE, numbered I (in the
# foreground; the caller backgrounds it). The partner of an idempotent writer
# is called as SITE "partner".
_call() {
  local s="$3" p="$4"
  case "$1" in
    gate-date)    ( cd "$p" && "$BASH" "$s/driver.sh" _cpg_record_gate_date "g$2" "Gate $2" "" ) ;;
    reviewer)     ( cd "$p" && "$BASH" "$s/driver.sh" _cpg_record_reviewer_attestation "r" "m$2" ) ;;
    accum)        ( cd "$p" && "$BASH" "$s/driver.sh" _cpg_record_accum_attestation "a$2" "reason $2" ) ;;
    sa)           ( cd "$p" && "$BASH" "$s/driver.sh" _cpg_record_single_authority_attestation "s$2" "reason $2" ) ;;
    p3-attest)    ( cd "$p" && "$BASH" "$s/driver.sh" _p3_write_attestation "sc$2" "reason" "signoff" ) ;;
    p3-license)   ( cd "$p" && "$BASH" "$s/driver.sh" _p3_write_license_exception "pkg$2" "MIT" "reason" ) ;;
    tt)           ( cd "$p" && "$BASH" "$s/driver.sh" _tt_record_accumulation "2026-01-01T00:00:0${2}Z" ) ;;
    ba-append)    ( cd "$p" && "$BASH" "$s/driver.sh" bypass_audit_append "$p" "{\"i\":$2}" ) ;;
    ba-close)     ( cd "$p" && "$BASH" "$s/driver.sh" bypass_audit_close_pending "$p" accept ) ;;
    ba-approvals) ( cd "$p" && "$BASH" "$s/driver.sh" bypass_audit_close_from_approvals "$p" ) ;;
    ba-rebind)    ( cd "$p" && "$BASH" "$s/driver.sh" bypass_audit_rebind_pending "$p" "$SHA" ) ;;
  esac
}
_partner() {  # SITE — the writer whose updates show a lost write of SITE, or nothing
  case "$1" in
    reviewer) echo accum ;;
    ba-close|ba-approvals|ba-rebind) echo ba-append ;;
  esac
}
_count() {  # SITE PROJECT — how many of the burst's updates are in the file
  case "$1" in
    gate-date)  jq '[.gates | keys[] | select(test("^g[0-9]+$"))] | length' "$2/.claude/phase-state.json" ;;
    reviewer|accum) jq '.mcp_accumulation.attestations | length' "$2/.claude/process-state.json" ;;
    sa)         jq '.attestations.single_authority | length' "$2/.claude/process-state.json" ;;
    p3-attest)  jq '.phase3.attestations | length' "$2/.claude/phase-state.json" ;;
    p3-license) jq '.phase3.license_exceptions | length' "$2/.claude/phase-state.json" ;;
    tt)         jq '.mcp_accumulation.store_success_count' "$2/.claude/process-state.json" ;;
    ba-*)       jq 'length' "$2/.claude/bypass-audit.json" ;;
  esac 2>/dev/null
}
_state_file() {  # SITE
  case "$1" in
    gate-date|p3-*) echo phase-state.json ;;
    reviewer|accum|sa|tt) echo process-state.json ;;
    ba-*) echo bypass-audit.json ;;
  esac
}
_locks_left() { ls -A "$1/.claude" 2>/dev/null | grep -e '\.lock' -e '\.json\.[A-Za-z0-9]\{6\}$' | tr '\n' ' '; }

# _burst SITE SCRIPTS_DIR — NB writers of SITE at once (and NB of its partner);
# sets R_GOT R_LEFT R_DIR.
_burst() {
  local site="$1" s="$2" d i pids="" partner
  partner=$(_partner "$site")
  d="$(newtmp)"; _proj "$d"
  i=1
  while [ "$i" -le "$NB" ]; do
    if [ -n "$partner" ]; then
      # The partner's writes are spread over most of a second by its own lock;
      # writer i of SITE starts i tenths in, so its write falls among them.
      ( sleep "0.$i"; PATH="$SITE_PATH" _call "$site" "$i" "$s" "$d" ) > /dev/null 2>&1 &
      pids="$pids $!"
      PATH="$SITE_PATH" _call "$partner" "$i" "$s" "$d" > /dev/null 2>&1 &
    else
      PATH="$SITE_PATH" _call "$site" "$i" "$s" "$d" > /dev/null 2>&1 &
    fi
    pids="$pids $!"
    i=$((i + 1))
  done
  # shellcheck disable=SC2086
  wait $pids
  R_GOT=$(_num "$(_count "${partner:-$site}" "$d")")
  R_LEFT=$(_locks_left "$d")
  R_DIR="$d"
}

# _nolock SITE SCRIPTS_DIR — one writer with no lib/lock.sh beside it; sets
# R_RC R_ERR R_SAME.
_nolock() {
  local d f before
  d="$(newtmp)"; _proj "$d"
  f="$d/.claude/$(_state_file "$1")"; before=$(cat "$f")
  ( PATH="$SITE_PATH"; cd "$d" && _limit 2 "$BASH" -c '. "$1"; shift; _call "$@"' _ "$TOPTMP/call.sh" "$1" 1 "$2" "$d" > /dev/null 2> "$d/.err" ); R_RC=$?
  R_ERR=$(cat "$d/.err" 2>/dev/null)
  if [ "$(cat "$f")" = "$before" ]; then R_SAME=1; else R_SAME=0; fi
}

# _stall_jq DIR — a jq that, on a filter containing $SHIM_ON, marks DIR/started
# and sleeps, so the writer can be signalled inside its write.
_stall_jq() {
  cat > "$1/jq" << 'EOF'
#!/bin/sh
case "$*" in *"$SHIM_ON"*) : > "$SHIM_DIR/started"; sleep 10; exit 1 ;; esac
exec "$REAL_JQ" "$@"
EOF
  chmod +x "$1/jq"
}
_write_filter() {  # SITE — a piece of that writer's jq filter and of no other
  case "$1" in
    gate-date)    echo '.gates = ((.gates // {})' ;;
    reviewer)     echo '{reviewers: {reason: $reason' ;;
    accum)        echo 'head: $head}}))' ;;
    sa)           echo '.single_authority = ((.single_authority // {})' ;;
    p3-attest)    echo '.phase3.attestations = ((.phase3.attestations // {})' ;;
    p3-license)   echo '.phase3.license_exceptions = ' ;;
    tt)           echo '.store_success_count = ((.store_success_count // 0) + 1)' ;;
    ba-append)    echo '. + [$r]' ;;
    ba-close)     echo '.user_response = $ur | .final_outcome = $fo' ;;
    ba-approvals) echo 'first($picks[]' ;;
    ba-rebind)    echo '.details.sentinel_sha256 = $s' ;;
  esac
}
# _term SITE SCRIPTS_DIR — TERM to one writer's process group while it is
# inside its write; sets R_SEEN R_LEFT.
_term() {
  local d sh pid i=0
  d="$(newtmp)"; _proj "$d"
  sh="$d/.shim"; mkdir -p "$sh"; _stall_jq "$sh"
  ( cd "$d" && PATH="$sh:$PATH" SHIM_DIR="$sh" SHIM_ON="$(_write_filter "$1")" REAL_JQ="$REAL_JQ" \
      exec perl -e 'setpgrp(0, 0); exec @ARGV' "$BASH" -c '. "$1"; shift; _call "$@"' _ "$TOPTMP/call.sh" "$1" 1 "$2" "$d" > /dev/null 2>&1 ) &
  pid=$!
  if _await "$sh/started"; then R_SEEN=1; else R_SEEN=0; fi
  kill -TERM -- "-$pid" 2>/dev/null
  { wait "$pid"; } 2>/dev/null
  # The writer's subshell outlives its parent by the time its trap takes.
  i=0; while [ -n "$(_locks_left "$d")" ] && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  R_LEFT=$(_locks_left "$d")
}
# _single SITE SCRIPTS_DIR — one writer of SITE, alone; sets R_LEFT.
_single() {
  local d; d="$(newtmp)"; _proj "$d"
  _call "$1" 1 "$2" "$d" > /dev/null 2>&1
  R_LEFT=$(_locks_left "$d")
}
_await() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]; }

# The writers run in child shells that need _call and its helpers.
{
  _fn "$0" _call
  _fn "$0" _partner
  printf 'SHA=%q\nSTORE_PAYLOAD=%q\n' "$SHA" "$STORE_PAYLOAD"
} > "$TOPTMP/call.sh"
export BASH

# _site_checks SITE SCRIPTS_DIR NOLOCK_DIR — the three checks of one writer;
# sets R_SITE to everything that did not hold (empty: all held).
_site_checks() {
  local want
  R_SITE=""
  _burst "$1" "$2"
  want=$NB
  [ "$R_GOT" = "$want" ] || R_SITE="$R_SITE burst: $R_GOT of $want updates landed;"
  [ -z "$R_LEFT" ] || R_SITE="$R_SITE burst: left [$R_LEFT];"
  _nolock "$1" "$3"
  case "$R_RC" in 0|142) R_SITE="$R_SITE nolock: rc=$R_RC (want a refusal within 2 s);" ;; esac
  case "$R_ERR" in *"lock.sh is missing"*) ;; *) R_SITE="$R_SITE nolock: stderr does not name lib/lock.sh [$R_ERR];" ;; esac
  [ "$R_SAME" = "1" ] || R_SITE="$R_SITE nolock: the state file changed;"
  _term "$1" "$2"
  [ "$R_SEEN" = "1" ] || R_SITE="$R_SITE term: never reached its write (the arm proves nothing);"
  [ -z "$R_LEFT" ] || R_SITE="$R_SITE term: left [$R_LEFT];"
}

S_DIR="$(newtmp)"; _mirror "$S_DIR"
S_NOLOCK="$(newtmp)"; _mirror "$S_NOLOCK" nolock
if ! _mk_driver "$S_DIR/scripts" || ! _mk_driver "$S_NOLOCK/scripts"; then
  fail_ "S (meta)" "the writers could not be extracted from their scripts; every S case would prove nothing"
else
  for site in $SITES; do
    _site_checks "$site" "$S_DIR/scripts" "$S_NOLOCK/scripts"
    if [ -z "$R_SITE" ]; then
      pass "S-$site: $NB at once under the uutils-like mkdir land every update and leave no lock; without lib/lock.sh it refuses within 2 s naming the lib and writes nothing; TERM inside its write leaves no lock or temp"
    else
      fail_ "S-$site" "$R_SITE"
    fi
  done
fi

# ── S-…-refuse: a refusal inside the lock releases it ───────────────────────
# Three writers can refuse after taking the lock: bypass_audit_append on a
# ledger that is not one JSON array, and the accumulation attestation and
# record when a directory holds the state file's name. Each must release the
# lock on its way out, or the next writer waits out its whole budget for it.
_refuse_round() {  # SITE SCRIPTS_DIR — sets R_RC R_LEFT
  local d; d="$(newtmp)"; _proj "$d"
  case "$1" in
    ba-append) printf '{}\n' > "$d/.claude/bypass-audit.json" ;;
    *) rm -f "$d/.claude/process-state.json"; mkdir "$d/.claude/process-state.json" ;;
  esac
  _call "$1" 1 "$2" "$d" > /dev/null 2>&1; R_RC=$?
  R_LEFT=$(_locks_left "$d")
}
for site in ba-append accum tt; do
  _refuse_round "$site" "$S_DIR/scripts"
  if [ "$R_RC" != "0" ] && [ -z "$R_LEFT" ]; then
    pass "S-$site-refuse: refused inside the lock (rc=$R_RC), and the lock is released"
  else
    fail_ "S-$site-refuse" "rc=$R_RC (want non-zero) left=[$R_LEFT] (want none)"
  fi
done

# ── S-sa-remedy: the single-authority refusal names the missing lib ─────────
# The recorder refuses with its own status, 6, without lib/lock.sh, and the
# gate's refusal must name that cause and its fix, not "an unexpected status".
_sa_remedy() {  # SCRIPTS_DIR — sets R_OUT R_RC
  local d; d="$(newtmp)"; _proj "$d"
  R_OUT=$( cd "$d" && SOLO_SINGLE_AUTHORITY_ATTESTED=1 SOLO_SINGLE_AUTHORITY_ATTESTED_REASON="one technical authority" \
             "$BASH" "$1/driver.sh" _cpg_single_authority_gate g1 "Gate 1" 2>/dev/null ); R_RC=$?
}
_sa_remedy "$S_NOLOCK/scripts"
case "$R_RC:$R_OUT" in
  1:*"scripts/lib/lock.sh is missing or cannot be loaded"*"verify-install.sh --auto-fix"*)
    pass "S-sa-remedy: without lib/lock.sh the single-authority attestation is refused, and the refusal names the lib and verify-install.sh --auto-fix" ;;
  *) fail_ "S-sa-remedy" "rc=$R_RC (want 1); refusal: $(printf '%s' "$R_OUT" | grep -A2 'COULD NOT BE RECORDED' | tr '\n' ' ')" ;;
esac

# ── E1, E2: each script loads the lib it needs ──────────────────────────────
# _e1 SCRIPTS_DIR — check-phase-gate.sh on a project whose Phase 0→1 gate has
# dated APPROVAL_LOG.md evidence and no recorded date. Sets R_DATE R_OUT.
_e1() {
  local d; d="$(newtmp)"
  mkdir -p "$d/p/.claude" "$d/p/docs/phase-0"
  printf 'x\n' > "$d/p/docs/phase-0/frd.md"
  printf '{"project":"e1","current_phase":1,"deployment":"personal","track":"light","gates":{"phase_0_to_1":null,"phase_1_to_2":null,"phase_2_to_3":null,"phase_3_to_4":null}}\n' > "$d/p/.claude/phase-state.json"
  printf '# Approval Log\n\n## Phase Gate: Phase 0 → Phase 1\n| Field | Value |\n|---|---|\n| **Approver** | Alice |\n| **Date** | 2026-03-01 |\n' > "$d/p/APPROVAL_LOG.md"
  R_OUT=$( cd "$d/p" && "$BASH" "$1/check-phase-gate.sh" 2>&1 )
  R_DATE=$(jq -r '.gates.phase_0_to_1 // "null"' "$d/p/.claude/phase-state.json" 2>/dev/null)
}
_e2() {  # SCRIPTS_DIR — run-phase3-validation.sh --attest; sets R_REC R_OUT
  local d; d="$(newtmp)"
  mkdir -p "$d/p/.claude"
  printf '{"phase3":{"attestations":{}}}\n' > "$d/p/.claude/phase-state.json"
  R_OUT=$( cd "$d/p" && "$BASH" "$1/run-phase3-validation.sh" --attest threat-model --reason "no model yet" --signoff "tester" --state .claude/phase-state.json 2>&1 )
  R_REC=$(jq -r '.phase3.attestations["threat-model"].reason // "none"' "$d/p/.claude/phase-state.json" 2>/dev/null)
}
_mirror_full() {  # DIR [nolock] — all of scripts/, for a script that sources its siblings
  mkdir -p "$1" && cp -R "$REPO_ROOT/scripts" "$1/"
  [ "${2:-}" = "nolock" ] && rm -f "$1/scripts/lib/lock.sh"
  return 0
}
E_FULL="$(newtmp)"; _mirror_full "$E_FULL"
E_NOLOCK="$(newtmp)"; _mirror_full "$E_NOLOCK" nolock
TODAY=$(date +%Y-%m-%d)
_e1 "$E_FULL/scripts"; e1_with="$R_DATE"
_e1 "$E_NOLOCK/scripts"; e1_without="$R_DATE"; e1_out="$R_OUT"
if [ "$e1_with" = "$TODAY" ] && [ "$e1_without" = "null" ] && printf '%s' "$e1_out" | grep -q 'lib/lock.sh is missing'; then
  pass "E1: check-phase-gate.sh records the gate date with lib/lock.sh beside it, and without it says so and records nothing"
else
  fail_ "E1" "with the lib: date=$e1_with (want $TODAY); without: date=$e1_without (want null), names the lib=$(printf '%s' "$e1_out" | grep -c 'lib/lock.sh is missing')"
fi
_e2 "$E_FULL/scripts"; e2_with="$R_REC"
_e2 "$E_NOLOCK/scripts"; e2_without="$R_REC"; e2_out="$R_OUT"
if [ "$e2_with" = "no model yet" ] && [ "$e2_without" = "none" ] && printf '%s' "$e2_out" | grep -q 'lib/lock.sh is missing'; then
  pass "E2: run-phase3-validation.sh --attest records with lib/lock.sh beside it, and without it says so and records nothing"
else
  fail_ "E2" "with the lib: reason=[$e2_with]; without: reason=[$e2_without] (want none), names the lib=$(printf '%s' "$e2_out" | grep -c 'lib/lock.sh is missing')"
fi
# E3: lib/bypass-audit.sh's own load. The S driver sources lib/lock.sh before
# it, so no S-ba-* case can see that load fail (review R-358-6). Here the lib is
# sourced alone, in a clean shell whose working directory is the project, not
# the lib's folder: with lib/lock.sh beside it an append lands; without it the
# append is refused, naming the lib, and nothing is written.
_e3() {  # LIBDIR — one append; sets R_RC R_ERR R_ROWS
  local d=""; d="$(newtmp)"; _proj "$d"
  ( cd "$d" && "$BASH" -c '. "$1/bypass-audit.sh"; bypass_audit_append "$2" "{\"i\":1}"' _ "$1" "$d" > /dev/null 2> "$d/.err" ); R_RC=$?
  R_ERR=$(cat "$d/.err" 2>/dev/null)
  R_ROWS=$(_num "$(jq 'length' "$d/.claude/bypass-audit.json" 2>/dev/null)")
}
_e3 "$E_FULL/scripts/lib"; e3_with="rc=$R_RC rows=$R_ROWS"; e3_with_err="$R_ERR"
_e3 "$E_NOLOCK/scripts/lib"; e3_without="rc=$R_RC rows=$R_ROWS"; e3_names=no
case "$R_ERR" in *"lib/lock.sh is missing"*) e3_names=yes ;; esac
if [ "$e3_with" = "rc=0 rows=1" ] && [ "$e3_without" = "rc=1 rows=0" ] && [ "$e3_names" = "yes" ]; then
  pass "E3: lib/bypass-audit.sh, sourced alone from a project, appends with lib/lock.sh beside it, and without it refuses naming the lib and writes nothing"
else
  fail_ "E3" "with the lib: $e3_with (want rc=0 rows=1) [$e3_with_err]; without: $e3_without (want rc=1 rows=0), names the lib=$e3_names"
fi

# ── G1: the transition gap, measured ────────────────────────────────────────
# A writer from before BL-358 holds <file>.lockdir and nothing else. A new
# writer takes <file>.lock: the two do not exclude each other (`## BL-358:`
# records this gap rather than closing it). The same fact is what makes a
# .lockdir an old killed run left behind harmless now: it blocks nothing new.
_gap_round() {  # SCRIPTS_DIR — sets R_GAP
  local d t0 t1
  R_GAP=""
  d="$(newtmp)"; _proj "$d"
  mkdir "$d/.claude/bypass-audit.json.lockdir" "$d/.claude/phase-state.json.lockdir" "$d/.claude/process-state.json.lockdir"
  t0=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
  _call ba-append 1 "$1" "$d" > /dev/null 2>&1
  _call gate-date 1 "$1" "$d" > /dev/null 2>&1
  _call accum 1 "$1" "$d" > /dev/null 2>&1
  t1=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
  [ "$(_count ba-append "$d")" = "1" ] || R_GAP="$R_GAP the audit row did not land beside a held .lockdir;"
  [ "$(_count gate-date "$d")" = "1" ] || R_GAP="$R_GAP the gate date did not land beside a held .lockdir;"
  [ "$(_count accum "$d")" = "1" ] || R_GAP="$R_GAP the attestation did not land beside a held .lockdir;"
  perl -e 'exit($ARGV[1] - $ARGV[0] < 5 ? 0 : 1)' "$t0" "$t1" || R_GAP="$R_GAP the writers waited on the .lockdir (${t0}..${t1});"
  for f in bypass-audit phase-state process-state; do
    [ -d "$d/.claude/$f.json.lockdir" ] || R_GAP="$R_GAP the old $f.json.lockdir was removed;"
  done
}
_gap_round "$S_DIR/scripts"
if [ -z "$R_GAP" ]; then
  pass "G1: beside a .lockdir held by a pre-BL-358 writer, the new writers land at once and leave the .lockdir alone — the two locks do not exclude each other (the recorded transition gap), and a stale .lockdir blocks nothing new"
else
  fail_ "G1" "$R_GAP"
fi

# ── P1, P2: shipped wherever its callers are, and ignored ───────────────────
. "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh"
_p1() {  # INIT — 0 when the derived shipped set carries every lock caller and the lock
  local set f
  set=$(soif_parse_shipped_scripts "$1" "$REPO_ROOT/scripts")
  for f in scripts/lib/lock.sh scripts/lib/ledger-write.sh scripts/lib/bypass-audit.sh scripts/check-phase-gate.sh scripts/run-phase3-validation.sh scripts/track-tool-usage.sh; do
    printf '%s\n' "$set" | grep -qxF "$f" || { R_P1="$f is not in the shipped set"; return 1; }
  done
  R_P1=""
}
if _p1 "$REPO_ROOT/init.sh"; then
  pass "P1: init.sh's cp lines ship lib/lock.sh with its five callers, so --sync-framework and adoption (soif_parse_shipped_scripts) ship it too"
else
  fail_ "P1" "$R_P1"
fi

# _p2 UPGRADE ADOPT_SESSION — sets R_P2.
_p2() {
  local d bf lk
  R_P2=""
  d="$(newtmp)"; mkdir -p "$d/p/.claude"
  printf '{}\n' > "$d/p/.claude/manifest.json"
  printf '# pre-existing\n*.log\n' > "$d/p/.gitignore"
  ( cd "$d/p" && git init -q ) > /dev/null 2>&1
  awk '/# BL-174-GITIGNORE-BACKFILL START$/{f=1;next} /# BL-174-GITIGNORE-BACKFILL END$/{f=0} f' "$1" > "$d/backfill.sh"
  if [ ! -s "$d/backfill.sh" ]; then R_P2="the backfill block could not be extracted;"; return; fi
  ( cd "$d/p" && BF="$d/backfill.sh" "$BASH" -c 'print_ok() { :; }; . "$BF"; . "$BF"' ) > /dev/null 2>&1
  for lk in process-state.json.lock phase-state.json.lock bypass-audit.json.lock tool-usage.json.lock tool-usage.json.lock.break; do
    ( cd "$d/p" && git check-ignore -q ".claude/$lk" ) || R_P2="$R_P2 backfill: .claude/$lk not ignored;"
  done
  [ "$(grep -cxF '.claude/*.json.lock' "$d/p/.gitignore")" = "1" ] || R_P2="$R_P2 backfill: the lock line is not there exactly once after two runs;"
  [ "$(grep -cxF '.claude/tool-usage.json.lock.break' "$d/p/.gitignore")" = "1" ] || R_P2="$R_P2 backfill: the guard line is not there exactly once after two runs;"
  d="$(newtmp)"; mkdir -p "$d/p/.claude"
  ( cd "$d/p" && git init -q ) > /dev/null 2>&1
  _fn "$2" _adopt_session_ignore_rules > "$d/rules.sh"
  ( . "$d/rules.sh" && _adopt_session_ignore_rules ) > "$d/p/.claude/.gitignore" 2>/dev/null
  for lk in process-state.json.lock phase-state.json.lock bypass-audit.json.lock tool-usage.json.lock tool-usage.json.lock.break; do
    ( cd "$d/p" && git check-ignore -q ".claude/$lk" ) || R_P2="$R_P2 adoption: .claude/$lk not ignored;"
  done
  ( cd "$d/p" && git check-ignore -q ".claude/settings.json" ) && R_P2="$R_P2 adoption: settings.json is ignored too;"
}
_p2 "$REPO_ROOT/scripts/upgrade-project.sh" "$REPO_ROOT/scripts/lib/adopt/adopt-session.sh"
if [ -z "$R_P2" ]; then
  pass "P2: the upgrade backfill makes an existing project ignore all five lock files (one line each, twice run), and adoption's .claude/.gitignore does the same"
else
  fail_ "P2" "$R_P2"
fi

# ── Mutants ─────────────────────────────────────────────────────────────────
# _mutate_in FILE FN FIND REPL — replace FIND with REPL on the one line of
# function FN (in FILE) that carries it. Sets MUT_WHY and returns 1 unless
# exactly one line changed, inside FN, and the file still parses.
_mutate_in() {
  local f="$1" fn="$2" find="$3" repl="$4" start end n ln before
  start=$(grep -n -x -F -- "$fn() {" "$f" | head -1 | cut -d: -f1)
  [ -n "$start" ] || { MUT_WHY="no $fn() in $f"; return 1; }
  end=$(awk -v s="$start" 'NR > s && /^}$/ {print NR; exit}' "$f")
  n=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e' "$f" | grep -c -F -- "$find")
  [ "$n" = "1" ] || { MUT_WHY="'$find' is on $n lines of $fn (want 1)"; return 1; }
  ln=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e {print NR": "$0}' "$f" | grep -F -- "$find" | cut -d: -f1)
  before="$(newtmp)/before"; cp "$f" "$before"
  MUT_LN="$ln" MUT_FIND="$find" MUT_REPL="$repl" perl -pi -e 'if ($. == $ENV{MUT_LN}) { s/\Q$ENV{MUT_FIND}\E/$ENV{MUT_REPL}/ }' "$f"
  [ "$(diff "$before" "$f" | grep -c '^[<>]')" = "2" ] || { MUT_WHY="the mutation did not change exactly line $ln"; return 1; }
  "$BASH" -n "$f" 2>/dev/null || { MUT_WHY="the mutant does not parse"; return 1; }
}
# _mutate_line FILE FIND REPL — the same, for a line FIND alone pins.
_mutate_line() {
  local f="$1" find="$2" repl="$3" n ln before
  n=$(grep -c -F -- "$find" "$f")
  [ "$n" = "1" ] || { MUT_WHY="'$find' is on $n lines (want 1)"; return 1; }
  ln=$(grep -n -F -- "$find" "$f" | cut -d: -f1)
  before="$(newtmp)/before"; cp "$f" "$before"
  MUT_LN="$ln" MUT_FIND="$find" MUT_REPL="$repl" perl -pi -e 'if ($. == $ENV{MUT_LN}) { s/\Q$ENV{MUT_FIND}\E/$ENV{MUT_REPL}/ }' "$f"
  [ "$(diff "$before" "$f" | grep -c '^[<>]')" = "2" ] || { MUT_WHY="the mutation did not change exactly line $ln"; return 1; }
  if [ "${f##*.}" = "sh" ]; then "$BASH" -n "$f" 2>/dev/null || { MUT_WHY="the mutant does not parse"; return 1; }; fi
}

# MLN, MLP — the primitive.
m="$(newtmp)/lock.sh"; cp "$LOCKLIB" "$m"
if _mutate_line "$m" '( set -C; : > "$1" )' '( : > "$1" )'; then
  _race_rounds "$m" 20 40
  if [ "$R_MULTI" != "0" ]; then pass "MLN: without noclobber, $R_MULTI of 20 rounds have more than one winner (L1)"
  else fail_ "MLN" "one winner every round without set -C; L1 does not discriminate"; fi
else fail_ "MLN" "$MUT_WHY"; fi
m="$(newtmp)/lock.sh"; cp "$LOCKLIB" "$m"
if _mutate_line "$m" 'if [ -e "$1" ] || [ -L "$1" ]; then return 1; fi' ':'; then
  _taken_round "$m"
  if [ -n "$R_L2" ]; then pass "MLP: without the test for something already there, a taken name is taken again ($R_L2) (L2)"
  else fail_ "MLP" "no shape was taken without the test; L2 does not discriminate"; fi
else fail_ "MLP" "$MUT_WHY"; fi

# Per site: the file and function the writer lives in, and what its need-lock
# line starts with.
_where() {  # SITE — "relative-file function need-lock-find need-lock-repl"
  case "$1" in
    gate-date)    echo 'check-phase-gate.sh _cpg_record_gate_date' ;;
    reviewer)     echo 'check-phase-gate.sh _cpg_record_reviewer_attestation' ;;
    accum)        echo 'check-phase-gate.sh _cpg_record_accum_attestation' ;;
    sa)           echo 'check-phase-gate.sh _cpg_record_single_authority_attestation' ;;
    p3-attest)    echo 'run-phase3-validation.sh _p3_write_attestation' ;;
    p3-license)   echo 'run-phase3-validation.sh _p3_write_license_exception' ;;
    tt)           echo 'track-tool-usage.sh _tt_record_accumulation' ;;
    ba-append)    echo 'lib/bypass-audit.sh bypass_audit_append' ;;
    ba-close)     echo 'lib/bypass-audit.sh bypass_audit_close_pending' ;;
    ba-approvals) echo 'lib/bypass-audit.sh bypass_audit_close_from_approvals' ;;
    ba-rebind)    echo 'lib/bypass-audit.sh bypass_audit_rebind_pending' ;;
  esac
}
_need_find() {  # SITE — the start of its missing-lib refusal, and a neutral stand-in
  case "$1" in
    gate-date|reviewer|accum|sa) echo '_cpg_need_lock ' ;;
    p3-*) echo '_p3_need_lock ' ;;
    tt) echo 'if ! command -v soif_lock_try >/dev/null 2>&1; then' ;;
    ba-*) echo '_bypass_audit_need_lock ' ;;
  esac
}
_need_repl() {
  case "$1" in
    tt) echo 'if false; then' ;;
    *) echo 'true ' ;;
  esac
}
_release_find() {
  case "$1" in
    ba-*) echo 'soif_lock_release "$lock_file"   # BL-358-BA-RELEASE' ;;
    *) echo 'soif_lock_release "$lock_file" || true' ;;
  esac
}

# _site_mutant ID SITE KIND — build a mirror with the KIND mutation of SITE's
# writer and run the check that must kill it. KIND: A N R T.
_site_mutant() {
  local id="$1" site="$2" kind="$3" w file fn mdir find repl rounds
  w=$(_where "$site"); file=${w%% *}; fn=${w#* }
  mdir="$(newtmp)"; _mirror "$mdir"
  case "$kind" in
    A) find='while ! soif_lock_try "$lock_file"; do'; repl='while false; do' ;;
    N) find=$(_need_find "$site"); repl=$(_need_repl "$site") ;;
    R) find=$(_release_find "$site"); repl=':' ;;
    T) find="trap 'rm -f \"\$tmp\"; soif_lock_release \"\$lock_file\"' EXIT INT TERM"; repl="trap 'rm -f \"\$tmp\"' EXIT INT TERM" ;;
  esac
  if ! _mutate_in "$mdir/scripts/$file" "$fn" "$find" "$repl"; then fail_ "$id" "$MUT_WHY"; return; fi
  if [ "$kind" = "N" ]; then rm -f "$mdir/scripts/lib/lock.sh"; fi
  if ! _mk_driver "$mdir/scripts"; then fail_ "$id" "the mutant's writers could not be extracted"; return; fi
  case "$kind" in
    A)
      rounds=0
      while [ "$rounds" -lt 3 ]; do
        rounds=$((rounds + 1))
        _burst "$site" "$mdir/scripts"
        [ "$R_GOT" != "$NB" ] && break
      done
      if [ "$R_GOT" != "$NB" ]; then pass "$id: without its lock, $site loses updates ($R_GOT of $NB, round $rounds; S-$site)"
      else fail_ "$id" "$site without its lock lost nothing in $rounds rounds; S-$site does not discriminate"; fi ;;
    N)
      _nolock "$site" "$mdir/scripts"
      case "$R_RC:$R_ERR" in
        142:*) pass "$id: without its refusal, $site with no lib/lock.sh is still running after 2 s (S-$site-nolock)" ;;
        *"lock.sh is missing"*) fail_ "$id" "$site still refused naming the lib (rc=$R_RC); S-$site-nolock does not discriminate" ;;
        *) pass "$id: without its refusal, $site with no lib/lock.sh no longer names the lib (rc=$R_RC; S-$site-nolock)" ;;
      esac ;;
    R)
      _single "$site" "$mdir/scripts"
      if [ -n "$R_LEFT" ]; then pass "$id: without its release, $site leaves [$R_LEFT] (S-$site)"
      else fail_ "$id" "$site left no lock without its release; S-$site does not discriminate"; fi ;;
    T)
      _term "$site" "$mdir/scripts"
      if [ "$R_SEEN" = "1" ] && [ -n "$R_LEFT" ]; then pass "$id: a trap that does not release leaves [$R_LEFT] after TERM inside $site's write (S-$site-term)"
      else fail_ "$id" "seen=$R_SEEN left=[$R_LEFT]: S-$site-term does not discriminate"; fi ;;
  esac
}
for site in $SITES; do
  for kind in A N R T; do
    _site_mutant "M$kind-$site" "$site" "$kind"
  done
done

# MRX-* — the release on each refusal inside the lock dropped.
for spec in "ba-append|lib/bypass-audit.sh|bypass_audit_append|    soif_lock_release \"\$lock_file\"|    :" \
            "accum|check-phase-gate.sh|_cpg_record_accum_attestation|{ soif_lock_release \"\$lock_file\"; return 2; }|{ return 2; }" \
            "tt|track-tool-usage.sh|_tt_record_accumulation|{ soif_lock_release \"\$lock_file\"; return 1; }|{ return 1; }"; do
  IFS='|' read -r r_site r_file r_fn r_find r_repl << EOF
$spec
EOF
  mdir="$(newtmp)"; _mirror "$mdir"
  if _mutate_in "$mdir/scripts/$r_file" "$r_fn" "$r_find" "$r_repl" && _mk_driver "$mdir/scripts"; then
    _refuse_round "$r_site" "$mdir/scripts"
    if [ -n "$R_LEFT" ]; then pass "MRX-$r_site: without the release on its refusal, $r_site leaves [$R_LEFT] (S-$r_site-refuse)"
    else fail_ "MRX-$r_site" "no lock left without the release; S-$r_site-refuse does not discriminate"; fi
  else
    fail_ "MRX-$r_site" "${MUT_WHY:-the writers of the mutant could not be extracted}"
  fi
done

# MS6 — the single-authority refusal loses its arm for status 6.
mdir="$(newtmp)"; _mirror "$mdir" nolock
if _mutate_in "$mdir/scripts/check-phase-gate.sh" _cpg_single_authority_gate '    6) echo' '    9) echo' && _mk_driver "$mdir/scripts"; then
  _sa_remedy "$mdir/scripts"
  case "$R_OUT" in
    *"scripts/lib/lock.sh is missing or cannot be loaded"*) fail_ "MS6" "the refusal still named the lib without its arm; S-sa-remedy does not discriminate" ;;
    *) pass "MS6: without its arm, the refusal for a missing lib/lock.sh reads as an unexpected status (S-sa-remedy)" ;;
  esac
else
  fail_ "MS6" "${MUT_WHY:-the writers of the mutant could not be extracted}"
fi

# ML1, ML2 — each script's own load of the lib.
mdir="$(newtmp)"; _mirror_full "$mdir"
if _mutate_line "$mdir/scripts/check-phase-gate.sh" '  . "$SCRIPT_DIR/lib/lock.sh"' '  :'; then
  _e1 "$mdir/scripts"
  if [ "$R_DATE" = "null" ]; then pass "ML1: check-phase-gate.sh that does not load lib/lock.sh records no gate date (E1)"
  else fail_ "ML1" "the date was recorded without the load; E1 does not discriminate"; fi
else fail_ "ML1" "$MUT_WHY"; fi
mdir="$(newtmp)"; _mirror_full "$mdir"
if _mutate_line "$mdir/scripts/run-phase3-validation.sh" '  . "$SCRIPT_DIR/lib/lock.sh"' '  :'; then
  _e2 "$mdir/scripts"
  if [ "$R_REC" = "none" ]; then pass "ML2: run-phase3-validation.sh that does not load lib/lock.sh records no attestation (E2)"
  else fail_ "ML2" "the attestation was recorded without the load; E2 does not discriminate"; fi
else fail_ "ML2" "$MUT_WHY"; fi
# ML3, ML4 — lib/bypass-audit.sh's own load of the lib: its trial skipped, and
# the lib's folder read as the working directory.
for spec in 'ML3|if ( . "$BYPASS_AUDIT_DIR/lock.sh" && command -v soif_lock_try && command -v soif_lock_release ) >/dev/null 2>&1; then|if false; then' \
            'ML4|BYPASS_AUDIT_DIR="${BASH_SOURCE[0]%/*}"|BYPASS_AUDIT_DIR=.'; do
  IFS='|' read -r m_id m_find m_repl << EOF
$spec
EOF
  mdir="$(newtmp)"; _mirror_full "$mdir"
  if _mutate_line "$mdir/scripts/lib/bypass-audit.sh" "$m_find" "$m_repl"; then
    _e3 "$mdir/scripts/lib"
    if [ "rc=$R_RC rows=$R_ROWS" != "rc=0 rows=1" ]; then pass "$m_id: lib/bypass-audit.sh that does not load lib/lock.sh from its own folder appends nothing (rc=$R_RC rows=$R_ROWS; E3)"
    else fail_ "$m_id" "the row still landed; E3 does not discriminate"; fi
  else fail_ "$m_id" "$MUT_WHY"; fi
done

# MP1 — the cp line dropped.
m="$(newtmp)/init.sh"; cp "$REPO_ROOT/init.sh" "$m"
if _mutate_line "$m" 'cp "$SCRIPT_DIR/scripts/lib/lock.sh" scripts/lib/   # BL-358-SHIP-LOCK' ':   # BL-358-SHIP-LOCK'; then
  if ! _p1 "$m"; then pass "MP1: without its cp line, lib/lock.sh leaves the shipped set ($R_P1; P1)"
  else fail_ "MP1" "the set still carried lib/lock.sh; P1 does not discriminate"; fi
else fail_ "MP1" "$MUT_WHY"; fi
# MP2, MP3 — the backfill's lock line, and adoption's lock rule.
m="$(newtmp)/upgrade-project.sh"; cp "$REPO_ROOT/scripts/upgrade-project.sh" "$m"
if _mutate_line "$m" "printf '.claude/*.json.lock\\n'" ':'; then
  _p2 "$m" "$REPO_ROOT/scripts/lib/adopt/adopt-session.sh"
  case "$R_P2" in *backfill*) pass "MP2: without its lock line the backfill leaves the state writers' locks committable (P2)" ;;
    *) fail_ "MP2" "the backfill still ignored them; P2 does not discriminate" ;; esac
else fail_ "MP2" "$MUT_WHY"; fi
m="$(newtmp)/adopt-session.sh"; cp "$REPO_ROOT/scripts/lib/adopt/adopt-session.sh" "$m"
if _mutate_line "$m" '"/*.json.lock" \' '\'; then
  _p2 "$REPO_ROOT/scripts/upgrade-project.sh" "$m"
  case "$R_P2" in *adoption*) pass "MP3: without its lock rule, an adopted project's lock files are committable (P2)" ;;
    *) fail_ "MP3" "adoption still ignored them; P2 does not discriminate" ;; esac
else fail_ "MP3" "$MUT_WHY"; fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

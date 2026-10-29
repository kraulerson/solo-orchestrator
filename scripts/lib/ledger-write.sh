#!/usr/bin/env bash
# scripts/lib/ledger-write.sh — BL-314: the one locked writer of the MCP
# tool-usage ledger. Sourced by track-tool-usage.sh (after every MCP call),
# session-mcp-gate.sh (before every Write and Edit) and session-test-gate-check.sh
# (at SessionStart). The caller sets TOOL_USAGE.
#
# Every write used to go `jq … > "$TOOL_USAGE.tmp" && mv` or `cat >`, with no
# lock. Two at once truncated each other's half-written temp and the mv landed
# it: a 0-byte ledger, and the gate then refused every Write and Edit. Now each
# write takes the ledger's lock and goes through its own mktemp beside the
# ledger, so the mv is atomic.
#
# THE LOCK IS lock.sh's (`## BL-358:`): an O_EXCL create of "$TOOL_USAGE.lock",
# which one caller wins whatever coreutils the host has. It was `mkdir
# "$TOOL_USAGE.lockdir"`, and uutils' mkdir reported a lost race as a win. A
# write whose lock cannot be taken is SKIPPED, and stderr says so; it never goes
# ahead without the lock. Without lock.sh beside it this lib defines nothing,
# so its callers report it missing.
#
# STALENESS IS THE LOCK'S AGE. A lock whose mtime is older than LW_BUDGET was
# left by a writer SIGKILL took (it skips every trap); a live hold lasts
# milliseconds. An attempt count cannot tell a stale lock from a busy one: a
# waiter queued behind many short holders reached the count and broke a live
# lock, losing call rows at 40 concurrent events. A stale lock is broken once,
# under a second lock (the break guard), and only if it is still the lock that
# was read stale: of two waiters that both read it stale, the one holding the
# guard breaks it and the other waits, so the lock the breaker takes stands.
# That holds while the guard does. A guard one waiter has seen held for more
# than a budget, on one stale lock, is taken for a killed breaker's and cleared,
# so a breaker stalled or killed that long inside it, or a waiter stalled that
# long across two stale locks, can still see one lock broken twice (`## BL-358:`
# residual). If the lock is still stale after the one break it cannot be
# removed, and the write is skipped.
# The wait is bounded in every other shape too: a lock dated more than the
# budget ahead of the clock is stale, a lock whose time cannot be read is given
# up after one budget, and so is a guard that stays held after it is cleared.
#
# Safe under `set -e` (session-test-gate-check.sh runs with it), bash 3.2
# compatible, and silent on stdout on every path: the gate's stdout is its
# decision. Sourcing runs no external command.

case "${BASH_SOURCE[0]}" in */*) LW_DIR="${BASH_SOURCE[0]%/*}" ;; *) LW_DIR=. ;; esac
# shellcheck source=scripts/lib/lock.sh
{ . "$LW_DIR/lock.sh" && command -v soif_lock_try && command -v soif_lock_release; } >/dev/null 2>&1 || return 1   # BL-358-LW-LOCK-LIB

LW_BUDGET=3
LW_LOCKED=0
LW_SKIPPED=0
LW_TMP=""

_lw_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# _lw_take — wait for the ledger's lock: 0 when this caller holds it, 1 when it
# is given up.
_lw_take() {
  local broken=0 mt="" now="" age="" unread="" gwait="" gcleared=0
  while ! soif_lock_try "$TOOL_USAGE.lock"; do   # BL-314-LOCK
    if [ ! -e "$TOOL_USAGE.lock" ]; then
      # Released between the two calls, or the lock cannot be created at all
      # (EACCES, EROFS, ENOSPC, ENOTDIR). One retry tells them apart.
      soif_lock_try "$TOOL_USAGE.lock" && break
      [ -e "$TOOL_USAGE.lock" ] || return 1   # BL-314-NOT-EEXIST
    fi
    now=$(date +%s)
    mt=$(_lw_mtime "$TOOL_USAGE.lock") || mt=""
    case "$mt" in
      ''|*[!0-9]*)
        # Gone since the try, or a time no stat here can read. Retry, and
        # give the lock up once it has stayed unreadable for a whole budget.
        [ -n "$unread" ] || unread=$now
        [ $((now - unread)) -gt "$LW_BUDGET" ] && return 1   # BL-314-UNREADABLE
        sleep 0.1
        continue ;;
    esac
    unread=""
    age=$((now - mt))
    # A lock dated ahead of the clock (a SIGKILL-left lock, then the clock
    # stepped back) would never age; past the budget ahead, it is stale too.
    if [ "$age" -lt "-$LW_BUDGET" ]; then age=$((LW_BUDGET + 1)); fi   # BL-314-FUTURE-STALE
    if [ "$age" -gt "$LW_BUDGET" ]; then   # BL-314-STALE-AGE
      [ "$broken" = "1" ] && return 1
      if soif_lock_try "$TOOL_USAGE.lock.break"; then   # BL-358-BREAK-GUARD
        # Removed only if it is still the lock read stale above. Any lock
        # taken after that read is newer, so the same mtime is the same lock.
        [ "$(_lw_mtime "$TOOL_USAGE.lock")" = "$mt" ] && soif_lock_release "$TOOL_USAGE.lock" || :   # BL-314-BREAK-STALE
        soif_lock_release "$TOOL_USAGE.lock.break" || :   # BL-358-GUARD-RELEASE
        broken=1
        continue
      fi
      # Another waiter holds the guard, for the milliseconds a break takes. One
      # held for more than a budget was left by a breaker SIGKILL took inside
      # it: it is cleared, once, and the lock is given up if it is held again.
      [ -n "$gwait" ] || gwait=$now   # BL-358-GUARD-WAIT
      if [ $((now - gwait)) -gt "$LW_BUDGET" ]; then   # BL-358-GUARD-AGE
        [ "$gcleared" = "1" ] && return 1   # BL-358-GUARD-GIVE-UP
        soif_lock_release "$TOOL_USAGE.lock.break" || :   # BL-358-GUARD-STALE
        gcleared=1   # BL-358-GUARD-ONCE
      fi
    else
      # Not stale: any guard met so far guarded an earlier stale lock, so the
      # next guard starts its own clock. Carried over, the clock aged a guard
      # taken a moment before and cleared it under its live breaker.
      gwait=""   # BL-358-GUARD-EPISODE
    fi
    sleep 0.1
  done
  return 0
}

# _lw_lock — take the ledger's lock, or say on stderr that this write is
# skipped. A write never goes ahead without it (`## BL-358:`).
_lw_lock() {
  if _lw_take; then
    LW_LOCKED=1
    return 0
  fi
  LW_SKIPPED=1
  echo "ledger-write.sh: could not take $TOOL_USAGE.lock (stale and cannot be removed, its time cannot be read, or ${TOOL_USAGE%/*} refuses it), so this write to $TOOL_USAGE was SKIPPED rather than made without the lock. The MCP check reads only what lands, so it stays closed for this call." >&2   # BL-358-SKIP-LOUD
  return 1
}

_lw_unlock() {
  if [ "$LW_LOCKED" = "1" ]; then soif_lock_release "$TOOL_USAGE.lock" || :; fi
  LW_LOCKED=0
}

# _lw_sweep — remove temps a SIGKILLed writer left: only this lib's own `.lw.`
# temps, and only those older than the budget, since a younger one may belong
# to a live writer. The `|| continue` is load-bearing under a caller's `set -e`:
# an unmatched glob stays literal, and its failed stat must not end the hook.
_lw_sweep() {
  local f mt now
  now=$(date +%s)
  for f in "$TOOL_USAGE".lw.??????; do   # BL-314-SWEEP-GLOB
    mt=$(_lw_mtime "$f") || continue
    case "$mt" in ''|*[!0-9]*) continue ;; esac
    [ $((now - mt)) -gt "$LW_BUDGET" ] && rm -f "$f" || :   # BL-314-SWEEP-AGE
  done
  return 0
}

# _lw_land CMD… — run CMD with its stdout on a unique temp beside the ledger,
# and move the result into place only if it is non-empty (jq exits 0 on an
# empty input and prints nothing). Caller holds the lock.
_lw_land() {
  local tmp
  # A directory at the ledger path, or a symlink to one, is no ledger: mv would
  # drop the temp INSIDE it, outside .claude through a link. Refuse it; the gate
  # reads the ledger only as a regular file, so it denies ("ledger ABSENT").
  if [ -d "$TOOL_USAGE" ]; then return 1; fi   # BL-314-LEDGER-DIR
  _lw_sweep
  tmp=$(mktemp "$TOOL_USAGE.lw.XXXXXX" 2>/dev/null) || tmp=""   # BL-314-UNIQUE-TMP
  [ -n "$tmp" ] || return 1
  LW_TMP="$tmp"
  if "$@" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && mv "$tmp" "$TOOL_USAGE" 2>/dev/null; then   # BL-314-NONEMPTY
    LW_TMP=""
    return 0
  fi
  rm -f "$tmp"   # BL-314-FAIL-CLEAN
  LW_TMP=""
  return 1
}

# _lw_write JQ_ARGS… — apply a jq filter to the ledger. Caller holds the lock.
_lw_write() { _lw_land jq "$@" "$TOOL_USAGE"; }

# _lw_update JQ_ARGS… — _lw_write under the lock; 1, writing nothing, when the
# lock cannot be taken.
_lw_update() {
  local rc=0
  _lw_lock || return 1   # BL-358-NO-UNLOCKED-WRITE
  _lw_write "$@" || rc=$?
  _lw_unlock
  return "$rc"
}

# _lw_put — land stdin as the whole ledger, under the lock. The lock is what
# keeps a startup reset from being undone by a tracker that read the old
# ledger first and lands after it.
_lw_put() {
  local rc=0
  _lw_lock || return 1   # BL-314-PUT-LOCK
  _lw_land cat || rc=$?
  _lw_unlock
  return "$rc"
}

_lw_cleanup() {
  if [ -n "$LW_TMP" ]; then rm -f "$LW_TMP" || :; fi
  LW_TMP=""
  _lw_unlock
}

# _lw_traps — release the lock and remove the temp on any exit. No signal is
# trapped. TERM at its default ends the hook at once with 143, and bash runs
# this EXIT trap on the way out. INT sent to the hook alone is waited out:
# bash defers it until the foreground jq exits, jq never received it, so the
# hook carries on and the write lands whole under the lock.
_lw_traps() {
  trap '_lw_cleanup' EXIT   # BL-314-TRAP
}

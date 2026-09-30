#!/usr/bin/env bash
# scripts/lib/ledger-write.sh — BL-314: the one locked writer of the MCP
# tool-usage ledger. Sourced by track-tool-usage.sh (after every MCP call),
# session-mcp-gate.sh (before every Write and Edit) and session-test-gate-check.sh
# (at SessionStart). The caller sets TOOL_USAGE.
#
# Every write used to go `jq … > "$TOOL_USAGE.tmp" && mv` or `cat >`, with no
# lock. Two at once truncated each other's half-written temp and the mv landed
# it: a 0-byte ledger, and the gate then refused every Write and Edit. Now each
# write takes a mkdir lock and goes through its own mktemp beside the ledger,
# so the mv is atomic.
#
# POSIX mkdir() fails with EEXIST only when the name exists, and creates
# nothing on failure, so one caller wins; any other errno is not contention.
#
# STALENESS IS THE LOCK'S AGE. A lock whose mtime is older than LW_BUDGET was
# left by a writer SIGKILL took (it skips every trap); a live hold lasts
# milliseconds. It is broken once. An attempt count cannot tell a stale lock
# from a busy one: a waiter queued behind many short holders reached the count
# and broke a live lock, losing call rows at 40 concurrent events. If the lock
# is still stale after the one break it cannot be removed, and the write goes
# ahead unlocked: it may lose an update, but the unique temp keeps it whole.
# The wait is bounded in every other shape too: a lock dated more than the
# budget ahead of the clock is stale, and a lock whose time cannot be read is
# given up after one budget.
#
# Safe under `set -e` (session-test-gate-check.sh runs with it), bash 3.2
# compatible, and silent on every path: the gate's stdout is its decision.
# Sourcing runs no external command.

LW_BUDGET=3
LW_LOCKED=0
LW_TMP=""

_lw_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

_lw_lock() {
  local broken=0 mt now age unread=""
  while ! mkdir "$TOOL_USAGE.lockdir" 2>/dev/null; do   # BL-314-LOCK
    if [ ! -e "$TOOL_USAGE.lockdir" ]; then
      # Released between the two calls, or mkdir cannot create it at all
      # (EACCES, EROFS, ENOSPC, ENOTDIR). One retry tells them apart.
      mkdir "$TOOL_USAGE.lockdir" 2>/dev/null && break
      [ -e "$TOOL_USAGE.lockdir" ] || return 1   # BL-314-NOT-EEXIST
    fi
    now=$(date +%s)
    mt=$(_lw_mtime "$TOOL_USAGE.lockdir") || mt=""
    case "$mt" in
      ''|*[!0-9]*)
        # Gone since the mkdir, or a time no stat here can read. Retry, and
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
      rmdir "$TOOL_USAGE.lockdir" 2>/dev/null || :   # BL-314-BREAK-STALE
      broken=1
      continue
    fi
    sleep 0.1
  done
  LW_LOCKED=1
}

_lw_unlock() {
  if [ "$LW_LOCKED" = "1" ]; then rmdir "$TOOL_USAGE.lockdir" 2>/dev/null || :; fi
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

# _lw_update JQ_ARGS… — _lw_write under the lock.
_lw_update() {
  local rc=0
  _lw_lock || :
  _lw_write "$@" || rc=$?
  _lw_unlock
  return "$rc"
}

# _lw_put — land stdin as the whole ledger, under the lock. The lock is what
# keeps a startup reset from being undone by a tracker that read the old
# ledger first and lands after it.
_lw_put() {
  local rc=0
  _lw_lock || :   # BL-314-PUT-LOCK
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

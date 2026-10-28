#!/usr/bin/env bash
# scripts/lib/lock.sh — BL-358: the one lock primitive under every locked
# writer of .claude state: the tool-usage ledger (lib/ledger-write.sh), the
# durable accumulation record (track-tool-usage.sh), the phase-gate and Phase 3
# attestation writers (check-phase-gate.sh, run-phase3-validation.sh) and the
# bypass audit log (lib/bypass-audit.sh).
#
# They took `mkdir <file>.lockdir` and trusted its exit status. uutils
# coreutils 0.10.0, Ubuntu 26.04's default coreutils, exits 0 when its own
# mkdir(2) fails with EEXIST on a name that is a directory (uutils #13970, fixed
# in 0.11.0), so two writers held one lock and the ledger lost writes. A lock
# taken here asks no coreutils whether it was taken: bash opens the lock FILE
# under `set -C` (noclobber), an O_EXCL create, so exactly one caller creates it.
#
# The lock is <file>.lock. A script from before this change takes
# <file>.lockdir, and the two do not exclude each other: while a project's
# scripts are part old and part new (mid-sync), an old writer and a new one can
# hold the same file at once (`## BL-358:`, the transition gap). A .lockdir an
# old script left behind blocks nothing new.
#
# Each caller keeps its own wait, budget and messages, and refuses to write when
# this file is missing. bash 3.2 compatible; sourcing it runs no external command.

# soif_lock_try LOCK — take LOCK once, without waiting.
#   0 — taken: this call created LOCK, and no other caller holds it.
#   1 — not taken: something is at LOCK (held, or left by a killed run), or it
#       cannot be created there.
soif_lock_try() {
  # Anything already at the name holds the lock, whatever it is. noclobber
  # refuses only a REGULAR file: a link to /dev/null there would open without
  # creating anything, and a FIFO would block the open. Testing first also
  # spares a held lock the subshell below.
  if [ -e "$1" ] || [ -L "$1" ]; then return 1; fi   # BL-358-LOCK-PRESENT
  ( set -C; : > "$1" ) 2>/dev/null   # BL-358-LOCK-NOCLOBBER
}

# soif_lock_release LOCK — release a lock this caller took.
soif_lock_release() { rm -f "$1" 2>/dev/null; }

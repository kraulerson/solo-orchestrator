#!/usr/bin/env bash
# scripts/lib/delta-state.sh — read/write the delta module's live state.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §7.1 (the
# `.claude/delta-state.json` schema) and §3.1 (this file is the first member of
# the severable delta module's inventory). WP2 fills the body in; WP1 lands
# this stub so the boundary lint at scripts/lint-delta-boundary.sh has a real
# module member to find — its vacuity floor refuses to pass a scan that found
# no delta-module file, and it deliberately does not count itself.
#
# (No `# BL-NNN-…` marker on purpose: no backlog entry exists for the delta
# build, and minting one would red scripts/lint-bl-markers.sh, whose first pass
# resolves every marker to a `## BL-NNN:` entry. The design-doc path above is
# the citation.)
#
# ROLE
#   Sole reader/writer of `.claude/delta-state.json` — the project-owned,
#   machine-written record of open deltas, their class and materialised gate
#   set, and the hotfix retro ledger. The file is never overwritten by
#   `scripts/upgrade-project.sh` (§3.2, the NOTICE-ONLY treatment modelled on
#   the `# BL-099-DOC-GUARD` rendered-doc fence).
#
# WRITE DISCIPLINE (WP2 implements; stated here so the stub is honest about
# what it is a stub FOR)
#   Every write is atomic: render to `<file>.tmp` in the SAME directory, fsync
#   is not available portably so the guarantee is the rename, then `mv` over
#   the target. A partial write must leave the previous state intact — a
#   truncated state file would strand an open delta with no way to close it.
#   This is the house pattern (see scripts/lib/phase2-state.sh).
#
# DEPENDENCY DIRECTION (D1)
#   This file may source and call CORE freely — delta -> core is allowed and
#   deliberately unasserted. The reverse is forbidden and lint-enforced: no
#   core file may name this path on an executed line, except the one declared
#   seam, `scripts/process-checklist.sh`. See scripts/lint-delta-boundary.sh.
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2.57. No associative arrays, no ${var,,}, no `((x++))`.

# delta_state_path [project_root]
#   Echo the absolute path of the state file for a project root (default: the
#   current directory). Pure; creates nothing. WP2's read/write entry points
#   both resolve through here so the location is spelled once.
delta_state_path() {
  local root="${1:-.}"
  printf '%s\n' "${root%/}/.claude/delta-state.json"
}

# delta_state_exists [project_root]
#   Return 0 when the state file is present, 1 otherwise. Callers use this to
#   distinguish "no delta track yet" from "state file unreadable"; WP2 adds the
#   parse/validate layer that tells those apart properly.
delta_state_exists() {
  local f
  f="$(delta_state_path "${1:-.}")"
  [ -f "$f" ]
}

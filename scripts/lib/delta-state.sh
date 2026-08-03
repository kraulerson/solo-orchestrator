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
  local root="${1:-.}" p
  p="${root%/}/.claude/delta-state.json"
  # A `.`-rooted call (the seam's, and the common one) would otherwise render
  # every diagnostic as `./.claude/…`. Both spellings resolve to the same file,
  # so normalise ONCE here rather than at each message site.
  case "$p" in ./*) p="${p#./}" ;; esac
  printf '%s\n' "$p"
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

# ─────────────────────────────────────────────────────────────────────────────
# WP2 — the read/write layer.
#
# Every function below is errexit-SAFE: callers source this lib into
# scripts/process-checklist.sh, which runs under `set -euo pipefail`. So no
# bare command is left to fail on its own — each is tested with `if !` or
# tailed with `||`. `((x++))` never appears (house rule).
# ─────────────────────────────────────────────────────────────────────────────

# delta_state_default_json
#   The §7.1 document with nothing in it. This is what a read returns when the
#   file is absent OR unreadable, so a caller never has to branch on existence.
#   `active_delta` is a SLOT (object-or-null), not an array — one-at-a-time is a
#   property of the schema rather than a rule someone has to enforce (§7.1).
delta_state_default_json() {
  cat <<'DELTA_STATE_EMPTY_EOF'
{
  "schemaVersion": 1,
  "active_delta": null,
  "hotfix_retros": [],
  "cadence": {
    "last_routine_review": null,
    "last_deep_security": null
  },
  "closed": []
}
DELTA_STATE_EMPTY_EOF
}

# The §7.1 shape, as a jq boolean. This is the WRITE-side gate: reads are
# deliberately permissive (parse-only) so a hand-edited file can still be seen
# and repaired, but nothing gets PAST this predicate onto disk.
#
#   • active_delta is object-or-null — the structural half of one-at-a-time.
#   • hotfix_retros / closed are arrays — hotfix_retros outlives active_delta
#     (an open retro must block a release cut long after its delta closed), and
#     closed is the append-only audit tail.
#   • cadence is an object — §8.3's checker reads dates out of it.
DELTA_STATE_SHAPE='
    (type == "object")
    and (has("schemaVersion"))
    and ((.active_delta == null) or ((.active_delta | type) == "object"))
    and ((.hotfix_retros | type) == "array")
    and ((.cadence | type) == "object")
    and ((.closed | type) == "array")
'

# delta_state_read [project_root]
#   Print the state document on stdout. ALWAYS rc 0, and ALWAYS a document that
#   satisfies the schema:
#     absent file      -> the empty schema, silently (no delta track yet).
#     unparseable file -> the empty schema, with a warning on stderr.
#     wrong SHAPE      -> the empty schema, with a warning on stderr.
#
#   The shape check on the READ side is not belt-and-braces. Callers in later
#   WPs index this document (`.active_delta.id`, `.hotfix_retros[]`), and jq
#   ERRORS when you index an array or a number that way — so a file someone
#   hand-edited into `[]` would take the whole toolchain down one caller at a
#   time. Falling back keeps every consumer's contract true.
#
#   The file is NOT repaired, replaced or deleted in any of those branches — it
#   is the project's, and a reader that silently rewrote it would be a second
#   writer (D7). The warning is the whole remedy, on purpose.
delta_state_read() {
  local root="${1:-.}" f
  f="$(delta_state_path "$root")"
  if [ ! -f "$f" ]; then
    delta_state_default_json
    return 0
  fi
  if ! jq -e . "$f" >/dev/null 2>&1; then
    printf '%s\n' "delta-state: $f is not valid JSON — reading the empty schema instead. The file was NOT modified; repair or delete it." >&2
    delta_state_default_json
    return 0
  fi
  if ! jq -e "( $DELTA_STATE_SHAPE )" "$f" >/dev/null 2>&1; then   # DELTA-STATE-READ-SHAPE
    printf '%s\n' "delta-state: $f parses but is not a state document (schemaVersion present; active_delta object-or-null; hotfix_retros/closed arrays; cadence object) — reading the empty schema instead. The file was NOT modified; repair or delete it." >&2
    delta_state_default_json
    return 0
  fi
  jq . "$f"
}

# _delta_state_closed_is_append <old-file> <candidate-file>
#   True when the candidate's `closed` array EXTENDS the old one — same rows, in
#   the same order, plus zero or more at the end. §7.1 calls `closed` an
#   append-only audit tail; this is what makes that a property rather than a
#   comment.
#
#   A previous file that is not a well-formed state document has no defensible
#   prefix to protect, so it is not held against the candidate — and it MUST NOT
#   be, or a file hand-edited into `[]` could never be written over through the
#   seam (jq errors on `[] | .closed`, the guard would refuse forever, and the
#   single writer would have locked itself out of the only file it owns).
_delta_state_closed_is_append() {
  local old="$1" new="$2"
  jq -e "( $DELTA_STATE_SHAPE )" "$old" >/dev/null 2>&1 || return 0   # DELTA-STATE-CLOSED-TOLERANT
  jq -e -n --slurpfile o "$old" --slurpfile n "$new" '
      (($o[0].closed) // []) as $oc
    | (($n[0].closed) // []) as $nc
    | (($nc | length) >= ($oc | length)) and ($nc[0:($oc | length)] == $oc)
  ' >/dev/null 2>&1
}

# delta_state_write [project_root]  < candidate-document-on-stdin
#   THE atomic write. Reads a whole candidate document on stdin, validates it,
#   and only then lets it become the state file.
#
#   ATOMICITY (§7.1, the house `jq … > .tmp && mv` idiom): the candidate is
#   rendered to a SIBLING tmp file — same directory, so the final step is a
#   rename within one filesystem and not a copy — and the previous file is
#   replaced by that rename or not at all. A rejected or half-written candidate
#   dies on the tmp. A truncated state file would strand an open delta with no
#   way to close it, which is why this is not "validate then write".
delta_state_write() {
  local root="${1:-.}" f dir
  f="$(delta_state_path "$root")"
  dir="${f%/*}"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || return 1
  fi

  local target="$f.tmp"          # DELTA-STATE-ATOMIC-TARGET
  rm -f "$target" 2>/dev/null || true

  if ! jq "if ( $DELTA_STATE_SHAPE ) then . else error(\"delta-state shape violation\") end" > "$target" 2>/dev/null; then
    rm -f "$target" 2>/dev/null || true
    printf '%s\n' "delta-state: refusing to write $f — the candidate is not valid JSON or violates the schema (schemaVersion present; active_delta object-or-null; hotfix_retros/closed arrays; cadence object). The previous file was NOT touched." >&2
    return 1
  fi

  if [ -f "$f" ] && ! _delta_state_closed_is_append "$f" "$target"; then
    rm -f "$target" 2>/dev/null || true
    printf '%s\n' "delta-state: refusing to write $f — 'closed' is APPEND-ONLY and the candidate drops or rewrites an already-closed row. The previous file was NOT touched." >&2
    return 1
  fi

  mv "$target" "$f" || { rm -f "$target" 2>/dev/null || true; return 1; }   # DELTA-STATE-ATOMIC-RENAME
  return 0
}

# delta_state_update <project_root> <jq-filter>
#   Read → transform → atomic write, the only mutation shape the seam exposes.
#   The filter runs against the CURRENT document (or the empty one), and its
#   output is handed to delta_state_write, which is where validation lives — so
#   a filter that produces valid JSON of the wrong shape is still refused, and
#   is refused AFTER the tmp file is opened. That ordering is deliberate: it is
#   what makes the atomicity guarantee reachable from the production surface
#   instead of only from a unit probe.
delta_state_update() {
  local root="${1:-.}" filter="${2:-}"
  if [ -z "$filter" ]; then
    printf '%s\n' "delta_state_update: a jq filter is required" >&2
    return 2
  fi
  local cur cand
  cur="$(delta_state_read "$root")" || return 1
  if ! cand="$(printf '%s\n' "$cur" | jq "$filter" 2>&1)"; then
    printf '%s\n' "delta-state: the jq filter failed — nothing was written. jq said: $cand" >&2
    return 1
  fi
  printf '%s\n' "$cand" | delta_state_write "$root"
}

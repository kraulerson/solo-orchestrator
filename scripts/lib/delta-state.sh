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

# ── THE SHAPE PREDICATE ──────────────────────────────────────────────────────
# The §7.1 shape, as a jq boolean, and the WRITE-side gate. Reads run it too
# (delta_state_read falls back to the empty schema rather than handing a caller
# a document it cannot index), but nothing gets PAST it onto disk.
#
# WHAT IT ENFORCES, exactly — one atom per line, each individually pinned by a
# refusal case in tests/test-delta-wp2-state-policy.sh. Every atom carries a
# marker so a counterfactual can address it without a line number (CLAUDE.md's
# citation rule), and an atom with no refusal case behind it is a deletable
# atom — R-WP2-1 found three of those in the first cut of this file, all three
# survived the whole PR-blocking check set, and the repo's own scar tissue
# (`# BL-181-UNIT-LANE-PREDICATE`) says that is how guards quietly die.
#
#   • the document is an object.
#   • schemaVersion is a NUMBER. Presence alone was the first cut, and it let
#     `.schemaVersion = "banana"` through. Type, not value: pinning `== 1` would
#     refuse a future v2 document, and version negotiation is not this layer's
#     job.
#   • active_delta is object-or-null — the STRUCTURAL half of one-at-a-time.
#   • hotfix_retros is an array — it outlives active_delta, because an open
#     retro must block a release cut long after its delta closed.
#   • cadence is an object — §8.3's checker reads dates out of it.
#   • closed is an array of OBJECTS. The row-type atom uses `.closed[]?` so it
#     is independently observable: without the `?` it would ERROR whenever the
#     array atom was deleted, and an error refuses the write too — which is
#     exactly how the array atom came to be deletable with everything green.
#   • the top level is CLOSED-WORLD: exactly the five §7.1 keys, no others.
#
# NO `(type == "object")` ATOM, AND THAT IS DELIBERATE. The first cut opened
# with one. It is REDUNDANT-UNPINNABLE — the same class as the deleted length
# atom below: with it removed, every non-object candidate is still refused.
# `[]`, `"a-string"`, `42` and `true` make `.schemaVersion` ERROR (jq refuses to
# index a non-object, and an error refuses the write), and `null` yields
# `null | type == "number"` = false. No candidate exists that only that atom
# refuses, so no refusal case can ever stand behind it, so it is
# indistinguishable from a deleted line while looking like a guard. Removed
# rather than "pinned". Do not re-add it.
#
# MARKER HYGIENE, because the atom census is a grep: a live atom marker is the
# ONLY thing allowed to sit immediately after `# ` in this file. Deleted or
# discussed atoms are named mid-sentence, never at a comment's start — a
# wrapped line that put a dead marker in marker position is what made the first
# census report seventeen atoms for a sixteen-atom guard.
#
# WHAT IT DELIBERATELY DOES NOT ENFORCE — stated so the comment stops
# over-claiming (R-WP2-3), because "refuses anything that violates the schema"
# was never true:
#   • THE SECOND-ACTIVATION REFUSAL IS WP3's, NOT THIS LAYER'S — it is the
#     OPERATOR-FACING one, and scripts/delta.sh's DELTA-OPEN-ACTIVE-GUARD is
#     where it lives, because only the caller can name the delta in the way and
#     tell the operator what to do about it. SUPERSEDED IN PART BY WP4: the
#     shape predicate still says nothing about active_delta beyond
#     object-or-null, but the WRITE path now carries a narrow structural atom of
#     its own — see _delta_state_active_is_not_replaced below, which refuses a
#     candidate that swaps a DIFFERENT id into an occupied slot. Mutating the
#     open delta in place stays fully allowed; that is what every legitimate
#     write does.
#   • cadence's INNER keys and date formats — §8.3/WP6 defines them.
#   • hotfix_retros' ROW shape — deferred to §11-WP5, and PAID BY WP5, but
#     deliberately NOT here. The guard lives on the WRITE side only
#     (DELTA_RETRO_ROW_SHAPE + _delta_state_retros_is_lawful below), and the
#     reason is this predicate's own read-side fallback: delta_state_read
#     answers a shape violation with the EMPTY SCHEMA. Put a retro row-shape
#     atom in here and one malformed row would make the whole ledger read as
#     zero retros — turning a single bad row into total loan forgiveness, which
#     is precisely the defect the guard exists to prevent, amplified. So this
#     predicate keeps saying only "hotfix_retros is an array" (a document that
#     survives to be repaired), and the write side is where rows are held to
#     their shape. The same amplification is latent in SHAPE-ATOM-CLOSED-ROWS
#     above for the audit tail; that is pre-existing and not changed here, but
#     it is the reason no new row-type atom joins it.
#   • active_delta's inner fields — WP3/WP4 materialise them at open.
# Each atom is `and ( … )` on its own line with a trailing marker, so a
# counterfactual neuters exactly one by replacing the marked line with
# `and (true)` and the jq program stays syntactically whole. The leading
# `(true)` exists so every real atom has the same shape.
DELTA_STATE_SHAPE='
    (true)
    and ((.schemaVersion | type) == "number")                              # SHAPE-ATOM-SCHEMAVERSION
    and ((.active_delta == null) or ((.active_delta | type) == "object"))  # SHAPE-ATOM-ACTIVE
    and ((.hotfix_retros | type) == "array")                               # SHAPE-ATOM-RETROS
    and ((.cadence | type) == "object")                                    # SHAPE-ATOM-CADENCE
    and ((.closed | type) == "array")                                      # SHAPE-ATOM-CLOSED
    and (all(.closed[]?; type == "object"))                                # SHAPE-ATOM-CLOSED-ROWS
    and ((((keys) - ["schemaVersion","active_delta","hotfix_retros","cadence","closed"]) | length) == 0)   # SHAPE-ATOM-NO-EXTRA-KEYS
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

# delta_state_read_strict [project_root]
#   THE FAIL-CLOSED READ (R-WP5-2, added in WP5). Same document as
#   delta_state_read, but it NEVER falls back — because for one class of caller
#   the fallback is the bug.
#
#     file present and a valid state document -> the document, rc 0
#     file present, unparseable or wrong shape -> NOTHING on stdout, rc 3
#     file ABSENT                              -> NOTHING on stdout, rc 4
#
#   WHY THIS EXISTS AND WHY IT DOES NOT REPLACE delta_state_read. The tolerant
#   read is correct for every per-delta operation: one bad file must not kill
#   the whole toolchain, and the warning plus the empty schema keeps `--open`
#   and `--close` usable. But an adversarial review showed what it costs the ONE
#   caller whose question is "does anything block a release": with a retro owed,
#   corrupting `.claude/delta-state.json` makes the read return the empty schema
#   at rc 0 (warning on stderr only) and DELETING it is completely silent — so
#   `delta_any_open_retro` answers "nothing owed" and §9.2's refusal never
#   fires. `rm .claude/delta-state.json` was loan forgiveness in one keystroke,
#   and the corrupt-file warning's own advice ("repair or delete it") named the
#   erasure path.
#
#   That is BL-213's fail-open class one level up from the dates WP5 already
#   refused it for: illegibility of a ROW is treated as overdue, so illegibility
#   of the LEDGER must not be treated as absolution.
#
#   THE TWO NON-ZERO CODES ARE DISTINCT ON PURPOSE. 3 means "there is a record
#   here and I cannot read it" — always a refusal. 4 means "there is no record
#   at all", which for a project that has never opened a delta is the truth and
#   not a hazard; the caller decides, and scripts/lib/delta-cadence.sh's header
#   tells WP7 what to decide. Collapsing them would force one of the two into
#   the wrong answer.
#
#   NOTHING IS PRINTED ON STDOUT IN THE FAILURE CASES. A caller that ignored the
#   return code would otherwise read a document that does not exist — the same
#   shape as the `|| echo 0` default WP5's date layer refuses to have.
delta_state_read_strict() {
  local root="${1:-.}" f
  f="$(delta_state_path "$root")"
  if [ ! -f "$f" ]; then
    printf '%s\n' "delta-state: $f does not exist. If this project has ever opened a delta, that file is its record and it is gone — restore it from version control before relying on anything that reads it." >&2
    return 4                                                          # DELTA-STATE-STRICT-ABSENT
  fi
  if ! jq -e "( $DELTA_STATE_SHAPE )" "$f" >/dev/null 2>&1; then
    printf '%s\n' "delta-state: $f exists but cannot be read as a delta record. Nothing may conclude anything from it — least of all that nothing is outstanding. The file was NOT modified; repair it from version control." >&2
    return 3                                                          # DELTA-STATE-STRICT-UNREADABLE
  fi
  jq . "$f"
}

# ── THE `closed` INVARIANT, IN TWO PARTS (§7.1) ──────────────────────────────
#
# §7.1 says two things about `closed` that read as one, and the first cut of
# this file implemented only the first:
#
#   PART 1 — APPEND-ONLY AUDIT TAIL. Rows are never deleted, never reordered,
#            never replaced. The array only ever grows at the end.
#   PART 2 — `shipped_in` IS A WRITE-ONCE FIELD, BACKFILLED AT CUT TIME.
#            "`shipped_in` is recorded at cut time via the seam — cut-release.sh
#            asks process-checklist.sh to write it and never touches the file
#            itself." A delta is closed BEFORE it is shipped, so the row exists
#            with `shipped_in: null` and is filled later.
#
# Those two are not in conflict, but a guard that enforces only Part 1 makes the
# Part 2 write impossible — which is exactly what R-WP2-2 found: the design's
# own named hardest case, `.closed[-1].shipped_in = "v1.2.1"`, was refused as a
# history rewrite. The reconciliation, decided here rather than in the middle of
# WP7:
#
#   The APPEND rule stays absolutely strict — it is not widened by one
#   character. The `shipped_in` backfill gets its OWN pathway
#   (delta_state_ship + the seam's --delta-state-ship), guarded by its OWN
#   predicate that permits EXACTLY ONE mutation shape: closed[i].shipped_in
#   transitioning null -> non-empty string, with the rest of the document
#   byte-for-byte identical. Widening the generic guard was the alternative and
#   was rejected: it would have put the carve-out inside the atom that protects
#   every other row, so a bug in the carve-out would open the whole tail.
#
# _delta_state_closed_is_append <old-file> <candidate-file>  — PART 1.
#   True when the candidate's `closed` EXTENDS the old one: same rows, same
#   order, plus zero or more at the end.
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
    | (true)
      and ($nc[0:($oc | length)] == $oc)         # APPEND-ATOM-PREFIX
  ' >/dev/null 2>&1
}
#   ONE atom, not two. The first cut also carried
#   `(($nc | length) >= ($oc | length))`, and the per-atom counterfactual sweep
#   showed it was UNPINNABLE: deleting it changed no behaviour at all, because
#   prefix-equality already subsumes it — if the candidate is SHORTER than the
#   old array then `$nc[0:len($oc)]` is all of `$nc`, an array of a different
#   length, and arrays of different lengths are never equal. A redundant atom
#   can never have a refusal case behind it, so it is permanently indistinguishable
#   from a deleted one; shipping it would have meant shipping a line that looks
#   like a guard and is not. Removed rather than "pinned". Do not re-add it.

# _delta_state_closed_is_ship_fill <old-file> <candidate-file>  — PART 2.
#   True for EXACTLY ONE mutation shape and nothing else:
#     • nothing outside `closed` moved;
#     • `closed` has the same length (no append, no truncation);
#     • every row is identical to its old self EXCEPT at most one;
#     • that one row differs ONLY in `shipped_in`, whose old value was null (or
#       absent) and whose new value is a non-empty string;
#     • exactly one row differs — a batch fill is refused, because a release
#       cuts one version at a time and a two-row diff means something else
#       happened.
#
#   Note what this predicate does NOT do: it does not care WHICH row, and it
#   does not read ids. Row selection is delta_state_ship's job; this is the
#   arithmetic that makes the pathway safe no matter who calls it.
#
#   Unlike the append rule there is NO tolerance branch for a malformed previous
#   file: you cannot ship what was never closed, so an unreadable predecessor is
#   a refusal, not a pass. (delta_state_write enforces the file's existence.)
_delta_state_closed_is_ship_fill() {
  local old="$1" new="$2"
  jq -e "( $DELTA_STATE_SHAPE )" "$old" >/dev/null 2>&1 || return 1
  jq -e -n --slurpfile o "$old" --slurpfile n "$new" '
      ($o[0]) as $od | ($n[0]) as $nd
    | ($od.closed) as $oc | ($nd.closed) as $nc
    | ([range(0; ($oc | length))] | map(
         . as $i
         | if $oc[$i] == $nc[$i] then "same"
           elif (true)
                and (($oc[$i] | del(.shipped_in)) == ($nc[$i] | del(.shipped_in)))   # SHIP-ATOM-ROW-IDENTITY
                and ($oc[$i].shipped_in == null)                                     # SHIP-ATOM-WRITE-ONCE
                and (($nc[$i].shipped_in | type) == "string")                        # SHIP-ATOM-STRING-TYPE
                and (($nc[$i].shipped_in | length) > 0)                              # SHIP-ATOM-STRING-NONEMPTY
           then "fill"
           else "bad"
           end)) as $codes
    | (true)
      and (($od | del(.closed)) == ($nd | del(.closed)))   # SHIP-ATOM-OUTSIDE
      and (($oc | length) == ($nc | length))               # SHIP-ATOM-LENGTH
      and (($codes | index("bad")) == null)                # SHIP-ATOM-NO-BAD
      and (($codes | map(select(. == "fill")) | length) == 1)   # SHIP-ATOM-EXACTLY-ONE
  ' >/dev/null 2>&1
}

# ── THE `active_delta` REPLACEMENT REFUSAL (R-WP3-3, added in WP4) ───────────
#
# WHAT CHANGED, AND WHY THE DEFERRAL ABOVE IS NOW ONLY HALF TRUE. The "WHAT IT
# DELIBERATELY DOES NOT ENFORCE" block says overwriting an OPEN active_delta is
# accepted here because §11-WP3 owns the business refusal. WP3 delivered that
# refusal — scripts/delta.sh's DELTA-OPEN-ACTIVE-GUARD — and an adversarial
# review of it named the residual precisely: the guard lives in the CALLER, and
# `--delta-state-update` is a GENERAL primitive, so a crafted filter still
# replaces the open delta at the seam and takes its `gates_completed` with it.
# The audit trail of everything already done is exactly what is lost, which is
# the loss the WP3 guard exists to prevent — so the invariant belongs in both
# places, and this is the second one.
#
# THE ATOM KEYS ON THE ID, NOT ON NULLNESS, AND THAT IS THE WHOLE DESIGN. The
# two-character-shorter spelling — refuse every non-null -> non-null transition
# — is WRONG, and wrong in a way that would have shipped green: every legitimate
# write against an OPEN delta has that exact shape. `--complete-gate` appends to
# `gates_completed`; WP4's close-time ratchet raises `attributes` and appends to
# `gates_required`; WP5's retro arm will touch the row again. All of them keep
# the id. Only a SWAP changes it, and only a swap is refused.
#
#   old.active_delta == null      -> allowed (an open)
#   new.active_delta == null      -> allowed (a close)
#   ids equal                     -> allowed (the delta mutating itself)
#   ids differ                    -> REFUSED
#
# WHAT THIS ATOM DELIBERATELY DOES NOT ENFORCE, recorded in the same style as
# the deferrals above rather than left as an unstated hole (found and assessed
# by adversarial review, R-WP4-3):
#   • IT PROTECTS IDENTITY, NOT CONTENT. A same-id write may gut the row —
#     `.active_delta.gates_required = [] | .active_delta.gates_completed = []`
#     is accepted, and the delta then closes with an empty archived checklist.
#     That is consistent with D7 and is not a hole this layer should close: the
#     file is the PROJECT's, a hand edit is exactly equivalent, and every
#     legitimate caller mutates this row (see below), so a content predicate
#     here would have to encode each caller's intent and would be a second copy
#     of the business logic. The cheat is also legible after the fact — an empty
#     `gates_completed` is archived into the audit tail rather than hidden.
#   • A CANDIDATE WITH NO `id` reads as a differing id and is REFUSED, which is
#     the fail-closed direction and is intentional.
#
# The tolerance branch mirrors the append rule's, for the same reason: a
# previous file that is not a well-formed state document has no defensible open
# delta to protect, and holding it against the candidate would let one bad hand
# edit lock the single writer out of the only file it owns.
_delta_state_active_is_not_replaced() {
  local old="$1" new="$2"
  jq -e "( $DELTA_STATE_SHAPE )" "$old" >/dev/null 2>&1 || return 0   # DELTA-STATE-ACTIVE-TOLERANT
  jq -e -n --slurpfile o "$old" --slurpfile n "$new" '
      ($o[0].active_delta) as $oa
    | ($n[0].active_delta) as $na
    | (true)
      and (($oa == null) or ($na == null) or ($oa.id == $na.id))   # ACTIVE-ATOM-NO-REPLACE
  ' >/dev/null 2>&1
}

# ── THE RETRO LEDGER'S GUARD (R-WP5-1, added in WP5) ─────────────────────────
#
# WHAT WAS WRONG. `closed` is a protected audit tail; `hotfix_retros` is the
# COLLATERAL that §9.2's release refusal is built on, and until now it had
# nothing at all. An adversarial review demonstrated the whole family through
# the seam, every one at rc 0: `.hotfix_retros = []` (wipe), a forged
# `closed_at` (debt "repaid" with a record nobody wrote), `due_by` pushed to
# 2999, an id swapped out, and `["paid"]` — string rows, which pass an
# array-only check AND read as "nothing owed", because every consumer correctly
# does `select(type == "object")`. The only refusal was making the value not an
# array at all. Post-close there was no backstop of any kind: nothing ever asks
# for the row again, so a wipe was permanent, silent loan forgiveness.
#
# The deferral note above named §11-WP5 as the owner of this. WP5 materialised
# the rows and shipped without the guard; this is that debt paid.
#
# TWO PREDICATES, NOT ONE, because they answer different questions and deserve
# different sentences to the operator:
#   SHAPE     — is every row in the CANDIDATE a well-formed §7.1 row? Needs no
#               previous file, so it also guards a first-ever write.
#   LAWFUL    — is the transition from the PREVIOUS ledger to this one one of
#               the two things that may legitimately happen to it?
#
# THE TWO LEGAL MUTATIONS, and nothing else:
#   • APPEND an OPEN row at the end (closed_at null, record null).
#   • FILE at most one existing OPEN row: closed_at null -> non-empty string AND
#     record null -> object, with the rest of that row byte-identical.
# Everything else — drop, reorder, replace, un-file, re-file, or edit an
# existing row's id/shipped_at/due_by — is refused.
#
# WHAT THIS DELIBERATELY DOES NOT DO, stated so the comment stops over-claiming:
# it protects the ledger against SILENT LOSS, not against an operator who files
# a write-up that says nothing true. A crafted filter that files a row with a
# real record object is indistinguishable at this layer from `--retro`, and it
# should be — the same boundary ACTIVE-ATOM-NO-REPLACE draws when it says it
# protects identity and not content. What it buys is that the OBLIGATION cannot
# be made to disappear, which is the property §9.2 spends.
#
# SCOPED TO THE `append` RULE. The `ship` pathway already requires everything
# outside `closed` to be byte-identical (SHIP-ATOM-OUTSIDE), so retros cannot
# move there; running these there too would only add a way for a hand-mangled
# ledger to lock `cut-release.sh` out of recording shipped_in.

# DELTA_RETRO_ROW_SHAPE — every row of the CANDIDATE is a well-formed §7.1 row.
#
# EACH ATOM AFTER THE FIRST IS VACUOUS FOR A NON-OBJECT ROW (`(type != "object")
# or …`), and that is what makes RETRO-ATOM-ROW-OBJECT independently pinnable:
# without it the later atoms would refuse a string row for their own reasons and
# neutering it would change nothing observable, which is the "atom that looks
# like a guard and is not" WP2 deleted three of. The short-circuit also keeps
# `keys` off a string, where it would ERROR — and an error refuses the write,
# which is the same masking wearing a different hat.
DELTA_RETRO_ROW_SHAPE='
    (true)
    and (all(.hotfix_retros[]?; type == "object"))                                                                     # RETRO-ATOM-ROW-OBJECT
    and (all(.hotfix_retros[]?; (type != "object") or ((keys) == ["closed_at","due_by","id","record","shipped_at"])))   # RETRO-ATOM-ROW-KEYS
    and (all(.hotfix_retros[]?; (type != "object") or (((.id | type) == "string") and ((.id | length) > 0))))           # RETRO-ATOM-ROW-ID
    and (all(.hotfix_retros[]?; (type != "object") or (((.shipped_at | type) == "string") and ((.due_by | type) == "string"))))   # RETRO-ATOM-ROW-DATES
    and ([.hotfix_retros[]? | if type == "object" then .id else null end] | (length == (unique | length)))              # RETRO-ATOM-ID-UNIQUE
'

# _delta_state_retros_are_wellformed <candidate-file>
_delta_state_retros_are_wellformed() {
  jq -e "( $DELTA_RETRO_ROW_SHAPE )" "$1" >/dev/null 2>&1
}

# _delta_state_retros_is_lawful <old-file> <candidate-file>
#
#   THE TOLERANCE BRANCH IS WIDER THAN THE APPEND RULE'S, ON PURPOSE. It skips
#   when the previous document is not a well-formed state document (the same
#   reason as everywhere else — one bad hand edit must never lock the single
#   writer out of the only file it owns) AND ALSO when the previous document's
#   RETRO ROWS are malformed. That second half is load-bearing: a hand edit that
#   puts `["paid"]` in the ledger passes the top-level shape, so without it the
#   row-by-row comparison below would run against a string and jq would ERROR on
#   every subsequent write, forever. With it, the next write through the seam is
#   free to REPAIR the ledger — and the candidate still has to satisfy
#   DELTA_RETRO_ROW_SHAPE, so the repair cannot be to something worse.
#
#   NO `PREFIX-IDS` ATOM, AND THAT IS DELIBERATE. The first cut carried
#   `([$pre[]?.id] == [$or[]?.id])`. It is REDUNDANT-UNPINNABLE, the class WP2
#   deleted rather than shipped: every prefix change it could catch — a drop, a
#   reorder, a replacement — makes the corresponding row comparison fall to
#   "bad" first (a differing id fails RETRO-ATOM-FILE-IDENTITY), and a shrink
#   additionally leaves `$pre[$i]` null, which is likewise "bad". No candidate
#   exists that only that atom refuses, so no refusal case can ever stand behind
#   it. The PROPERTY it names is still enforced — by FILE-IDENTITY and NO-BAD,
#   each of which has its own killing case. Do not re-add it.
_delta_state_retros_is_lawful() {
  local old="$1" new="$2"
  jq -e "( $DELTA_STATE_SHAPE )" "$old" >/dev/null 2>&1 || return 0        # DELTA-STATE-RETROS-TOLERANT
  jq -e "( $DELTA_RETRO_ROW_SHAPE )" "$old" >/dev/null 2>&1 || return 0    # DELTA-STATE-RETROS-TOLERANT-ROWS
  jq -e -n --slurpfile o "$old" --slurpfile n "$new" '
      (($o[0].hotfix_retros) // []) as $or
    | (($n[0].hotfix_retros) // []) as $nr
    | ($nr[0:($or | length)]) as $pre
    | ([range(0; ($or | length))] | map(
         . as $i
         | if $or[$i] == $pre[$i] then "same"
           elif (true)
                and ((($pre[$i] | type) == "object") and (($or[$i] | del(.closed_at) | del(.record)) == ($pre[$i] | del(.closed_at) | del(.record))))   # RETRO-ATOM-FILE-IDENTITY
                and ($or[$i].closed_at == null)                                    # RETRO-ATOM-FILE-WRITE-ONCE
                and (($pre[$i].closed_at | type) == "string")                      # RETRO-ATOM-FILE-STAMP-TYPE
                and (($pre[$i].closed_at | length) > 0)                            # RETRO-ATOM-FILE-STAMP-NONEMPTY
                and (($pre[$i].record | type) == "object")                         # RETRO-ATOM-FILE-RECORD-OBJECT
           then "filed"
           else "bad"
           end)) as $codes
    | (true)
      and (($codes | index("bad")) == null)                                        # RETRO-ATOM-NO-BAD
      and (($codes | map(select(. == "filed")) | length) <= 1)                     # RETRO-ATOM-AT-MOST-ONE-FILED
      and (all($nr[($or | length):][]?; (type != "object") or ((.closed_at == null) and (.record == null))))   # RETRO-ATOM-APPEND-OPEN
  ' >/dev/null 2>&1
}

# delta_state_write [project_root] [closed_rule]  < candidate-document-on-stdin
#   THE atomic write. Reads a whole candidate document on stdin, validates it,
#   and only then lets it become the state file.
#
#   ATOMICITY (§7.1, the house `jq … > .tmp && mv` idiom): the candidate is
#   rendered to a SIBLING tmp file — same directory, so the final step is a
#   rename within one filesystem and not a copy — and the previous file is
#   replaced by that rename or not at all. A rejected or half-written candidate
#   dies on the tmp. A truncated state file would strand an open delta with no
#   way to close it, which is why this is not "validate then write".
#
#   `closed_rule` selects which of the TWO `closed` predicates the candidate is
#   held to (see the two-part invariant above). It is NOT a bypass and there is
#   no "none": an unrecognised value is a refusal, so a typo fails closed rather
#   than writing unguarded.
#     append (default) — the audit-tail rule. Every seam action but one uses it.
#     ship             — the write-once shipped_in backfill, and ONLY that. It
#                        additionally requires the previous file to EXIST: you
#                        cannot ship what was never closed, so there is no
#                        "no previous file" pass here.
delta_state_write() {
  local root="${1:-.}" closed_rule="${2:-append}" f dir
  f="$(delta_state_path "$root")"
  dir="${f%/*}"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || return 1
  fi

  local target="$f.tmp"          # DELTA-STATE-ATOMIC-TARGET
  rm -f "$target" 2>/dev/null || true

  if ! jq "if ( $DELTA_STATE_SHAPE ) then . else error(\"delta-state shape violation\") end" > "$target" 2>/dev/null; then
    rm -f "$target" 2>/dev/null || true
    printf '%s\n' "delta-state: refusing to write $f — the candidate is not valid JSON, or fails the schema: object with exactly the five keys schemaVersion (number) / active_delta (object-or-null) / hotfix_retros (array) / cadence (object) / closed (array of objects). The previous file was NOT touched." >&2
    return 1
  fi

  case "$closed_rule" in
    append)
      # The retro ledger's SHAPE is checked with no reference to a previous
      # file, so it guards a first-ever write too.
      if ! _delta_state_retros_are_wellformed "$target"; then
        rm -f "$target" 2>/dev/null || true
        printf '%s\n' "delta-state: refusing to write $f — a hotfix_retros row is not a well-formed retro record. Every row is an object with exactly the five keys id / shipped_at / due_by / closed_at / record, a non-empty string id, string dates, and no two rows may share an id. The previous file was NOT touched." >&2
        return 1
      fi
      if [ -f "$f" ] && ! _delta_state_retros_is_lawful "$f" "$target"; then
        rm -f "$target" 2>/dev/null || true
        printf '%s\n' "delta-state: refusing to write $f — the hotfix retro ledger is the COLLATERAL a fast-lane release refusal is built on, and only two things may happen to it: a new OPEN row is appended, or ONE open row is filed (closed_at null -> a timestamp, record null -> an object, nothing else on that row moving). Dropping, reordering, replacing, re-dating, un-filing or re-filing a row is refused. The previous file was NOT touched." >&2
        return 1
      fi
      if [ -f "$f" ] && ! _delta_state_closed_is_append "$f" "$target"; then
        rm -f "$target" 2>/dev/null || true
        printf '%s\n' "delta-state: refusing to write $f — 'closed' is an APPEND-ONLY audit tail and the candidate drops, reorders or rewrites an already-closed row. To record shipped_in on a closed delta, use the dedicated seam action --delta-state-ship. The previous file was NOT touched." >&2
        return 1
      fi
      if [ -f "$f" ] && ! _delta_state_active_is_not_replaced "$f" "$target"; then
        rm -f "$target" 2>/dev/null || true
        printf '%s\n' "delta-state: refusing to write $f — the candidate swaps a DIFFERENT delta into an already-occupied active_delta slot, which would discard the open delta's gates_completed history. One delta at a time (§7.1). Close the open one first; the slot may be emptied, filled or mutated in place, but not replaced. The previous file was NOT touched." >&2
        return 1
      fi
      ;;
    ship)
      if [ ! -f "$f" ] || ! _delta_state_closed_is_ship_fill "$f" "$target"; then
        rm -f "$target" 2>/dev/null || true
        printf '%s\n' "delta-state: refusing to write $f — the ship pathway permits EXACTLY ONE change: a single closed row's shipped_in going from null to a non-empty string, with the rest of the document untouched. The previous file was NOT touched." >&2
        return 1
      fi
      ;;
    *)
      rm -f "$target" 2>/dev/null || true
      printf '%s\n' "delta-state: refusing to write $f — unknown closed-rule '$closed_rule'. There is no unguarded write path. The previous file was NOT touched." >&2
      return 1
      ;;
  esac

  mv "$target" "$f" || { rm -f "$target" 2>/dev/null || true; return 1; }   # DELTA-STATE-ATOMIC-RENAME
  return 0
}

# delta_state_update <project_root> <jq-filter>
#   Read → transform → atomic write under the APPEND rule. The general mutation
#   shape the seam exposes.
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
  printf '%s\n' "$cand" | delta_state_write "$root" append
}

# delta_state_ship <project_root> <delta-id> <version>
#   PART 2 of the `closed` invariant: record `shipped_in` on an already-closed
#   delta. This is §7.1's cut-time write — "cut-release.sh asks
#   process-checklist.sh to write it and never touches the file itself" — and it
#   is a SEPARATE, narrower pathway rather than a carve-out in the append rule
#   (see the two-part invariant above for why).
#
#   WRITE-ONCE. A row whose shipped_in is already set is refused, not
#   overwritten: a delta ships in exactly one version, and a second cut claiming
#   the same delta is a bug worth stopping. The refusal is at THIS layer as well
#   as in the predicate, so the operator gets a sentence instead of a shape
#   error.
#
#   Row selection is by id and takes the FIRST match. `closed` ids are unique by
#   construction (they are delta ids); if duplicates ever appear, the predicate
#   still bounds the damage — it permits exactly one row to change.
delta_state_ship() {
  local root="${1:-.}" id="${2:-}" version="${3:-}"
  if [ -z "$id" ] || [ -z "$version" ]; then
    printf '%s\n' "delta_state_ship: a delta id and a version are both required" >&2
    return 2
  fi
  local cur status cand
  cur="$(delta_state_read "$root")" || return 1

  status="$(printf '%s\n' "$cur" | jq -r --arg id "$id" '
      ([.closed[]? | .id] | index($id)) as $i
    | if $i == null then "NOROW"
      elif (.closed[$i].shipped_in == null) then "FILLABLE"
      else "ALREADY"
      end' 2>/dev/null)" || status="ERROR"

  case "$status" in
    FILLABLE) : ;;
    NOROW)
      printf '%s\n' "delta-state: refusing to record shipped_in — no row in 'closed' has id '$id'. A delta must be closed before it can be shipped. Nothing was written." >&2
      return 1 ;;
    ALREADY)
      printf '%s\n' "delta-state: refusing to record shipped_in for '$id' — it is already set. shipped_in is WRITE-ONCE: a delta ships in exactly one version. Nothing was written." >&2
      return 1 ;;
    *)
      printf '%s\n' "delta-state: could not inspect 'closed' while recording shipped_in for '$id'. Nothing was written." >&2
      return 1 ;;
  esac

  if ! cand="$(printf '%s\n' "$cur" | jq --arg id "$id" --arg v "$version" '
      ([.closed[]? | .id] | index($id)) as $i
    | .closed[$i].shipped_in = $v' 2>&1)"; then
    printf '%s\n' "delta-state: could not render the shipped_in backfill for '$id' — nothing was written. jq said: $cand" >&2
    return 1
  fi
  printf '%s\n' "$cand" | delta_state_write "$root" ship
}

#!/usr/bin/env bash
# tests/test-delta-wp8-intake.sh — Delta Track WP8.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §6.1 (the three creation
# paths, all converging on the SAME three writes — brief file, ledger row,
# state activation — with exactly one writer for the third), §6.2 (the brief's
# five sections, and "the done-observable section IS the close review's
# rubric"), §6.3 (identity `docs/deltas/DELTA-NNN-slug.md`, `max(existing)+1`,
# and the HARD constraint that the BUGS.md table format is parsed by scripts so
# the delta link rides the EXISTING `Fix Reference` column), §10.4 (the bridge:
# the manifesto's § 6 Post-MVP Backlog is READ as candidates, never moved),
# §10.5 (the ambient branch: resume.sh's fourth branch, ahead of the classic
# one), §5.2 (`audit_row_at_open`), §11-WP8.
#
# Plus Karl's two decisions of 2026-08-09 that landed in this work package:
#   D1  SHIP THE DELTA MODULE. init.sh carried the string `delta` zero times,
#       so the entire track reached no generated project. The copy list, the
#       chmod split (libs get none, entry scripts do) and the Class-T template
#       are asserted here, and the source-closure invariant is re-run because a
#       copy-list change MOVES the derived shipped set.
#   D3  `audit_row_at_open` WRITES A REAL BUGS.md ROW, in addition to WP5's
#       state-document stamp. The reviewer's evidence: the stamp survives
#       neither an abandoned hotfix nor a lost state file, so the audit trace it
#       promises does not persist. WP5's record is NOT removed and its tests are
#       NOT disturbed — this suite asserts BOTH are written.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red
# scripts/lint-bl-markers.sh. The design-doc path above is the citation, per
# the WP1–WP7 precedent.)
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES, NEVER LABELS
#
# CLAUDE.md's `[WARN]` trap: the printed label and the exit predicate can
# disagree. Every refusal below is asserted on the process EXIT CODE, on JSON
# read back off disk, or on a byte-level md5 — never on a banner. The codes this
# suite depends on are delta.sh's published set:
#     2   invocation error (a bad `--slug`, a bad `--via`, two briefs claiming
#         one id)
#     8   the brief's rubric has an unchecked criterion
#
# ═════════════════════════════════════════════════════════════════════════════
# THE SLUG IS WHERE A USER STRING BECOMES A FILESYSTEM PATH
#
# WP3's adversarial review recorded `--slug ../../../etc/cron.d/evil` stored
# VERBATIM in the state document. WP3 only ever wrote it to JSON; WP8 is the
# work package that turns it into `docs/deltas/<slug>.md`, so the refusal lands
# here and is pinned here — in BOTH directions. S1 proves the traversal is
# refused and that NOTHING was written anywhere in the tree (a refusal that
# leaves a file behind is not a refusal). S3 proves the sanitiser is not merely
# a blanket "reject anything unusual": an ordinary messy human slug still opens,
# and lands on a basename made only of [a-z0-9-].
#
# ═════════════════════════════════════════════════════════════════════════════
# MUTATIONS — the standard this wave settled on, all of it, every mutant
#
#   • the marker is ANCHORED to end-of-line (`…$`), so a sed cannot land in the
#     middle of a continuation;
#   • `sites == 1` is asserted — a marker that matches twice mutates two places
#     and proves nothing about either;
#   • EXACTLY ONE LINE CHANGED is asserted (`diff | grep -c '^[<>]'` == 2);
#   • EVERY mutant additionally asserts `bash -n`. This is not ceremony: a
#     mutation that landed mid-continuation earlier in this wave produced a
#     MANGLED PARSE whose crash read as "the guard caught it". A mutant that
#     does not parse has not tested anything;
#   • the harness is MODE-PRESERVING (`stat -c || stat -f`, the house GNU-first
#     pattern) — a mutant that silently drops the exec bit fails for the wrong
#     reason;
#   • FRESH-FIXTURE ISOLATION: every mutant gets its own scripts tree AND its
#     own project, built from scratch;
#   • STRUCTURAL DISCRIMINATORS where the expected result is an ABSENCE. m1's
#     "the manifesto was not modified" is an absence, so the killed/survived
#     decision reads an md5, not a message;
#   • no fixture temp dir derives its uniqueness from a counter inside a command
#     substitution — that produced cross-suite fixture collisions earlier in
#     this wave. Every directory here is either `mktemp -d` or a NAMED
#     subdirectory of one.
#
# ═════════════════════════════════════════════════════════════════════════════
# LANE: BOTH. This suite reads the scaffolder statically (it never runs it), so
# it is fast and belongs in the fast lane. The scaffolder's basename is spelled
# SPLIT below for exactly the reason tests/test-delta-severability.sh spells it
# split — `# BL-181-UNIT-LANE-PREDICATE` exempts any test whose executed lines
# NAME init.sh, and an exempt fast test quietly stops running in PR CI. The
# split is documented rather than hidden, and the file is registered in
# tests/full-project-test-suite.sh AND in the tests.yml `unit-shard` list.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests/test-delta-wp8-intake.sh" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git is required for tests/test-delta-wp8-intake.sh" >&2
  exit 2
fi

# The scaffolder's basename, split so no EXECUTED line in this file names it.
# See the LANE note in the header.
INIT_FILE="init"".sh"
INIT_PATH="$REPO_ROOT/$INIT_FILE"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"; }

# tree_manifest <dir> — every path plus its md5, sorted. The instrument for
# "the refusal wrote NOTHING": a diff of two manifests names the file that
# appeared, rather than merely reporting that a count moved.
tree_manifest() {
  local d="$1" f
  ( cd "$d" && find . -type f 2>/dev/null | LC_ALL=C sort ) | while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s  %s\n' "$f" "$(_md5file "$d/$f")"
  done
}

# ── Fixtures ────────────────────────────────────────────────────────────────

mk_scripts_tree() {
  mkdir -p "$1"
  cp -R "$REPO_ROOT/scripts" "$1/scripts"
}

# mk_proj <dir> <phase> — a phase-N project with the shipped ledgers and the
# shipped brief template, i.e. what init.sh actually lays down.
mk_proj() {
  local d="$1" phase="$2"
  mkdir -p "$d/.claude" "$d/templates/generated"
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":%s,"phases":{}}\n' \
    "$phase" > "$d/.claude/phase-state.json"
  cp "$REPO_ROOT/templates/generated/bugs.tmpl"        "$d/BUGS.md"
  cp "$REPO_ROOT/templates/generated/features.tmpl"    "$d/FEATURES.md"
  cp "$REPO_ROOT/templates/generated/delta-brief.tmpl" "$d/templates/generated/delta-brief.tmpl" 2>/dev/null || true
  mkdir -p "$d/src"
  printf 'base\n' > "$d/src/app.ts"
  ( cd "$d" && git init -q \
      && git config user.email t@t.local && git config user.name T \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

# A BUGS.md that already carries rows the phase gate greps for, so "the table
# still parses after we append" is measured against real rows and not an empty
# table. SEV-2/Deferred is deliberately one of them: it is the row
# tests/test-delta-wp0-inherited-predicates.sh pins the gate on.
seed_bugs_rows() {
  local f="$1" tmp
  tmp="$(mktemp)"
  awk '
    { print }
    /^\|---\|/ && !done {
      print "| 1 | SEV-1 | Open | login | crashes on unicode | Session 2 | Fix Now | | |"
      print "| 2 | SEV-2 | Deferred | export | wrong column order | Session 3 | Defer | | |"
      print "| 3 | SEV-3 | Fixed | ui | tooltip truncated | Session 3 | Fix Now | PR #12 | Session 4 |"
      done = 1
    }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# write_manifesto <project> — a PRODUCT_MANIFESTO.md whose § 6 Post-MVP Backlog
# carries three real candidates, in the shape the shipped template asks for
# ("Each item: what it is, and what user signal would justify building it").
write_manifesto() {
  local p="$1"
  cat > "$p/PRODUCT_MANIFESTO.md" <<'MANIFESTO'
# Product Manifesto

## 5. MVP Cutline

Everything above this line ships first.

## 6. Post-MVP Backlog

<!--
  Items here are candidates, not commitments.
-->

- Bulk CSV import — a user signal would be three support tickets asking for it
- Dark mode — a user signal would be a request from more than one paying customer
- Saved filters — a user signal would be the same filter typed twice in one session

## 7. Will-Not-Have List

- Anything with a blockchain in it
MANIFESTO
}

# ── Runners ─────────────────────────────────────────────────────────────────

DRC=0
DOUT=""
delta_run() {   # <scripts-dir> <project-dir> [args…]
  local sd="$1" p="$2"; shift 2
  DRC=0
  DOUT="$( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/delta.sh" "$@" </dev/null 2>&1 )" || DRC=$?
  return 0
}

RRC=0
ROUT=""
resume_run() {  # <scripts-dir> <project-dir>
  local sd="$1" p="$2"
  RRC=0
  ROUT="$( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/resume.sh" </dev/null 2>&1 )" || RRC=$?
  return 0
}

active_json() {
  local p="$1"; shift
  jq "$@" "$p/.claude/delta-state.json" 2>/dev/null || printf 'READ-FAILED'
}

# open_feature <scripts-dir> <project> <slug> [extra args…] — the guided path,
# non-interactive, with every derivation pinned by an explicit override so the
# three-path comparison is measuring the PATH and not the ambient git diff.
open_feature() {
  local sd="$1" p="$2" slug="$3"; shift 3
  delta_run "$sd" "$p" --open --describe "add a bulk CSV import screen" \
    --class feature --risk feature-local --level significant \
    --slug "$slug" --lines 40 --confirm "$@"
}

# normalise_state <project> — the state document with the three fields that
# CANNOT be equal across paths removed: the wall-clock stamps, and `opened_via`
# (which exists precisely to record which path was taken). Everything else must
# match byte-for-byte, which is what §6.1's "all three converge on the same
# three writes" means operationally.
normalise_state() {
  local p="$1"
  jq -S 'del(.active_delta.opened_at, .active_delta.attributes_confirmed_at,
             .active_delta.opened_via, .active_delta.audit_row_at_open)' \
     "$p/.claude/delta-state.json" 2>/dev/null || printf 'READ-FAILED'
}

echo "== tests/test-delta-wp8-intake.sh =="
echo ""

# ════════════════════════════════════════════════════════════════════════════
echo "=== B — the brief template (§6.2), and the parse contract it must match ==="
# ════════════════════════════════════════════════════════════════════════════

TMPL="$REPO_ROOT/templates/generated/delta-brief.tmpl"

if [ -f "$TMPL" ]; then
  pass "B0: templates/generated/delta-brief.tmpl exists — WP8's deliverable 1"
else
  fail_ "B0" "templates/generated/delta-brief.tmpl is missing; every case below depends on it"
fi

# B1 — the five sections, as HEADINGS, in §6.2's order.
b1_missing=""
for s in "What" "Why" "Done-observable" "Must-not-change" "Touched surfaces"; do
  grep -qE "^## $s\$" "$TMPL" 2>/dev/null || b1_missing="$b1_missing [$s]"
done
b1_order="$(grep -nE '^## (What|Why|Done-observable|Must-not-change|Touched surfaces)$' "$TMPL" 2>/dev/null \
            | sed -e 's/^[0-9]*:## //' | tr '\n' '|')"
if [ -z "$b1_missing" ] && [ "$b1_order" = "What|Why|Done-observable|Must-not-change|Touched surfaces|" ]; then
  pass "B1: the brief renders all five §6.2 sections as headings, in the design's order ($b1_order)"
else
  fail_ "B1" "missing section(s):$b1_missing; heading order was '$b1_order'"
fi

# B2 — the Done-observable section carries `- [ ]` rows, so a brief straight
# off the template is a rubric with UNTICKED criteria (which is what makes the
# close refuse until somebody has actually looked).
b2_boxes="$(awk '/^## Done-observable$/{f=1;next} f && /^## /{f=0} f' "$TMPL" 2>/dev/null | grep -cE '^- \[ \]' || true)"
case "$b2_boxes" in ''|*[!0-9]*) b2_boxes=0 ;; esac
if [ "$b2_boxes" -ge 2 ]; then
  pass "B2: the template's Done-observable section ships $b2_boxes '- [ ]' criteria — the rubric arrives unticked, so a brief nobody filled in cannot close"
else
  fail_ "B2" "the Done-observable section carries $b2_boxes '- [ ]' rows (want >= 2)"
fi

# B3 — THE CONTRACT SENTENCE. WP4's header records that this sentence used to
# say "the FIRST heading" and the CODE disagreed; the sentence moved, not the
# code, and WP4 states in as many words that "WP8's template codifies THIS
# wording". So the template must teach POOLING, not first-wins.
b3_pool=n; b3_first=n
grep -qiE 'both[ ,].*(read|pooled)|pooled' "$TMPL" 2>/dev/null && b3_pool=y
grep -qiE 'the first (such )?heading (wins|is)' "$TMPL" 2>/dev/null && b3_first=y
if [ "$b3_pool" = y ] && [ "$b3_first" = n ]; then
  pass "B3: the template documents WP4's CORRECTED contract — two Done-observable headings are POOLED, and it does not repeat the refuted 'first heading wins' wording"
else
  fail_ "B3" "template pooling wording present=$b3_pool, refuted first-wins wording present=$b3_first"
fi

# B4 — the same template, parsed by the PRODUCTION parser, end to end: two
# Done-observable headings in one brief must POOL. Driven through --close, so
# this is the shipped predicate and not a re-implementation of it.
P="$TMPROOT/b4"; mk_proj "$P" 4
open_feature "$REPO_ROOT/scripts" "$P" "pooling-check" >/dev/null 2>&1
b4_brief="$(active_json "$P" -r '.active_delta.brief // "NONE"')"
b4_ok=n
if [ "$b4_brief" != "NONE" ] && [ -f "$P/$b4_brief" ]; then
  # Tick every box the template shipped, then append a SECOND Done-observable
  # heading carrying one UNTICKED box. A first-heading-only reader closes here.
  sed -e 's/^- \[ \]/- [x]/' "$P/$b4_brief" > "$P/.b4tmp" && mv "$P/.b4tmp" "$P/$b4_brief"
  printf '\n## Done-observable (follow-up)\n\n- [ ] the second pool is read too\n' >> "$P/$b4_brief"
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    delta_run "$REPO_ROOT/scripts" "$P" --complete-gate "$g" >/dev/null 2>&1
  done <<EOF
$(active_json "$P" -r '.active_delta.gates_required[]? // empty')
EOF
  delta_run "$REPO_ROOT/scripts" "$P" --close
  [ "$DRC" -eq 8 ] && b4_ok=y
fi
if [ "$b4_ok" = y ]; then
  pass "B4: a brief rendered from the template and then given a SECOND Done-observable heading is refused at close (rc $DRC) — the criteria pool, end to end through the shipped parser"
else
  fail_ "B4" "close answered rc $DRC (want 8) with brief '$b4_brief' — the second Done-observable heading was not pooled"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== P — the three creation paths (§6.1) converge on ONE state ==="
# ════════════════════════════════════════════════════════════════════════════

# GUIDED: delta.sh --open renders the brief itself.
PG="$TMPROOT/p-guided"; mk_proj "$PG" 4
open_feature "$REPO_ROOT/scripts" "$PG" "csv-import" --via guided
pg_rc=$DRC

# CONVERSATIONAL: the agent has interviewed the operator and filled the five
# sections in already; it then opens the delta. Same command, `--via` records
# which path it was.
PC="$TMPROOT/p-conversational"; mk_proj "$PC" 4
open_feature "$REPO_ROOT/scripts" "$PC" "csv-import" --via conversational
pc_rc=$DRC

# MANUAL: the operator copied the template to docs/deltas/ BY HAND before
# running anything. The brief must be ADOPTED, never overwritten.
PM="$TMPROOT/p-manual"; mk_proj "$PM" 4
mkdir -p "$PM/docs/deltas"
cp "$TMPL" "$PM/docs/deltas/DELTA-001-csv-import.md"
printf '\n<!-- hand-written by the operator -->\n' >> "$PM/docs/deltas/DELTA-001-csv-import.md"
pm_pre_md5="$(_md5file "$PM/docs/deltas/DELTA-001-csv-import.md")"
open_feature "$REPO_ROOT/scripts" "$PM" "csv-import" --via manual
pm_rc=$DRC
pm_post_md5="$(_md5file "$PM/docs/deltas/DELTA-001-csv-import.md" 2>/dev/null || echo MISSING)"

sg="$(normalise_state "$PG")"; sc="$(normalise_state "$PC")"; sm="$(normalise_state "$PM")"
if [ "$pg_rc" -eq 0 ] && [ "$pc_rc" -eq 0 ] && [ "$pm_rc" -eq 0 ] \
   && [ "$sg" = "$sc" ] && [ "$sc" = "$sm" ] && [ "$sg" != "READ-FAILED" ]; then
  pass "P1: guided, conversational and manual all open (rc 0/0/0) and land BYTE-IDENTICAL state once the wall clock and 'opened_via' are removed — §6.1's 'all three converge on the same three writes'"
else
  fail_ "P1" "rcs $pg_rc/$pc_rc/$pm_rc; guided==conversational=$([ "$sg" = "$sc" ] && echo y || echo n); conversational==manual=$([ "$sc" = "$sm" ] && echo y || echo n)"
fi

# P2 — the three writes actually happened, on every path.
p2_bad=""
for pair in "guided:$PG" "conversational:$PC" "manual:$PM"; do
  nm="${pair%%:*}"; d="${pair#*:}"
  b="$(active_json "$d" -r '.active_delta.brief // "NONE"')"
  l="$(active_json "$d" -r '.active_delta.ledger // "NONE"')"
  [ "$b" != "NONE" ] && [ -f "$d/$b" ] || p2_bad="$p2_bad [$nm:brief=$b]"
  [ "$l" != "NONE" ] || p2_bad="$p2_bad [$nm:ledger=$l]"
  grep -q 'DELTA-001' "$d/FEATURES.md" 2>/dev/null || p2_bad="$p2_bad [$nm:no-ledger-row]"
done
if [ -z "$p2_bad" ]; then
  pass "P2: every path wrote all THREE artefacts — the brief file on disk, a ledger row naming DELTA-001, and the state activation (the state write is the seam's, and it is the only writer)"
else
  fail_ "P2" "missing writes:$p2_bad"
fi

# P3 — the manual path ADOPTS. An operator who wrote their own brief must not
# find it silently replaced by a template render.
if [ "$pm_pre_md5" = "$pm_post_md5" ]; then
  pass "P3: the manual path ADOPTED the operator's own brief byte-for-byte (md5 unchanged) rather than overwriting it with a fresh template render"
else
  fail_ "P3" "the hand-written brief changed: $pm_pre_md5 -> $pm_post_md5"
fi

# P4 — `opened_via` is recorded, and an unknown value is an invocation error.
p4_via="$(active_json "$PC" -r '.active_delta.opened_via // "NONE"')"
PV="$TMPROOT/p-badvia"; mk_proj "$PV" 4
open_feature "$REPO_ROOT/scripts" "$PV" "whatever" --via telepathy
p4_rc=$DRC
p4_state="$([ -f "$PV/.claude/delta-state.json" ] && echo present || echo absent)"
if [ "$p4_via" = "conversational" ] && [ "$p4_rc" -eq 2 ] && [ "$p4_state" = absent ]; then
  pass "P4: the path is recorded (opened_via=$p4_via) and an unknown one is an invocation error (rc $p4_rc) that activates nothing (state file $p4_state)"
else
  fail_ "P4" "opened_via='$p4_via' (want conversational); bad --via rc=$p4_rc (want 2); state file $p4_state (want absent)"
fi

# P5 — TWO briefs claiming one id is AMBIGUOUS and must refuse, not first-match.
PA="$TMPROOT/p-ambiguous"; mk_proj "$PA" 4
mkdir -p "$PA/docs/deltas"
cp "$TMPL" "$PA/docs/deltas/DELTA-001-one.md"
cp "$TMPL" "$PA/docs/deltas/DELTA-001-two.md"
open_feature "$REPO_ROOT/scripts" "$PA" "one"
p5_rc=$DRC
p5_state="$([ -f "$PA/.claude/delta-state.json" ] && echo present || echo absent)"
if [ "$p5_rc" -eq 2 ] && [ "$p5_state" = absent ]; then
  pass "P5: two briefs claiming DELTA-001 refuse the open (rc $p5_rc) and activate nothing — picking one silently would review against a document the operator may not be looking at"
else
  fail_ "P5" "rc=$p5_rc (want 2); state file $p5_state (want absent)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== E — the rubric bind, END TO END (open -> brief -> refuse -> tick -> close) ==="
# ════════════════════════════════════════════════════════════════════════════

PE="$TMPROOT/e2e"; mk_proj "$PE" 4
open_feature "$REPO_ROOT/scripts" "$PE" "unicode-export"
e_open_rc=$DRC
e_brief="$(active_json "$PE" -r '.active_delta.brief // "NONE"')"
while IFS= read -r g; do
  [ -n "$g" ] || continue
  delta_run "$REPO_ROOT/scripts" "$PE" --complete-gate "$g" >/dev/null 2>&1
done <<EOF
$(active_json "$PE" -r '.active_delta.gates_required[]? // empty')
EOF
delta_run "$REPO_ROOT/scripts" "$PE" --close
e_refused_rc=$DRC
e_still_open="$(active_json "$PE" -r '.active_delta.id // "NONE"')"
# Tick every box the template shipped and close again.
if [ "$e_brief" != "NONE" ] && [ -f "$PE/$e_brief" ]; then
  sed -e 's/^- \[ \]/- [x]/' "$PE/$e_brief" > "$PE/.etmp" && mv "$PE/.etmp" "$PE/$e_brief"
fi
delta_run "$REPO_ROOT/scripts" "$PE" --close
e_close_rc=$DRC
e_closed="$(active_json "$PE" -r '(.closed | length)')"
e_slot="$(active_json "$PE" -r '.active_delta == null')"
if [ "$e_open_rc" -eq 0 ] && [ "$e_refused_rc" -eq 8 ] && [ "$e_still_open" = "DELTA-001" ] \
   && [ "$e_close_rc" -eq 0 ] && [ "$e_closed" = "1" ] && [ "$e_slot" = "true" ]; then
  pass "E1: the template's OWN output satisfies WP4's close gate end to end — open (rc $e_open_rc), close REFUSED on the untouched boxes (rc $e_refused_rc, delta still open), boxes ticked, close SUCCEEDS (rc $e_close_rc, 1 row on the closed tail, slot empty). The rendered brief is a working rubric, not a document that merely looks like one"
else
  fail_ "E1" "open=$e_open_rc refuse=$e_refused_rc (want 8) still-open=$e_still_open close=$e_close_rc closed-rows=$e_closed slot-null=$e_slot"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== I — identity and location (§6.3): max(existing)+1, zero-padded ==="
# ════════════════════════════════════════════════════════════════════════════

# A GAP IN THE SEQUENCE is the case worth pinning: `count + 1` and
# `max + 1` agree on a dense sequence and disagree the moment anything is
# deleted, and the one that reuses an id puts two pieces of work on one
# identifier in the audit tail.
PI="$TMPROOT/ident"; mk_proj "$PI" 4
mkdir -p "$PI/docs/deltas"
( cd "$PI" && unset GITHUB_BASE_REF; bash "$REPO_ROOT/scripts/process-checklist.sh" \
    --delta-state-update '.closed = [{"id":"DELTA-001"},{"id":"DELTA-004"}]' ) >/dev/null 2>&1
open_feature "$REPO_ROOT/scripts" "$PI" "after-the-gap"
i1_id="$(active_json "$PI" -r '.active_delta.id // "NONE"')"
i1_brief="$(active_json "$PI" -r '.active_delta.brief // "NONE"')"
if [ "$i1_id" = "DELTA-005" ] && [ "$i1_brief" = "docs/deltas/DELTA-005-after-the-gap.md" ] \
   && [ -f "$PI/$i1_brief" ]; then
  pass "I1: with DELTA-001 and DELTA-004 on the record and 002/003 absent, the next id is max+1 = $i1_id (not count+1 = DELTA-003), and the brief lands at $i1_brief"
else
  fail_ "I1" "id=$i1_id (want DELTA-005); brief=$i1_brief (want docs/deltas/DELTA-005-after-the-gap.md); file present=$([ -f "$PI/$i1_brief" ] && echo y || echo n)"
fi

# I2 — zero padding to three, on a first delta.
PZ="$TMPROOT/ident-pad"; mk_proj "$PZ" 4
open_feature "$REPO_ROOT/scripts" "$PZ" "first-one"
i2_id="$(active_json "$PZ" -r '.active_delta.id // "NONE"')"
if [ "$i2_id" = "DELTA-001" ]; then
  pass "I2: the first delta is zero-padded to three ($i2_id), matching the repo's own BL-NNN habit"
else
  fail_ "I2" "first id was '$i2_id' (want DELTA-001)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== S — the slug is where a user string becomes a path ==="
# ════════════════════════════════════════════════════════════════════════════

# THE FIRST VERSION OF THIS ROW READ THE HOST'S FILESYSTEM, NOT THE PRODUCT,
# and it took a Linux CI runner to show it. The probe was
#     [ -e "$PS/../../../etc" ] && [ -e "$PS/../../../etc/cron.d" ]
# with $PS one level under `mktemp -d`. On this laptop `mktemp -d` yields
# /var/folders/<hash>/<hash>/T/tmp.XXXX, so `../../..` lands deep inside
# /var/folders and the probe was ALWAYS false. On a GitHub runner `mktemp -d`
# yields /tmp/tmp.XXXX, so `../../..` IS `/` — and Ubuntu ships /etc/cron.d. The
# probe therefore went TRUE on CI with the product having written nothing at
# all, and it was unfalsifiable in BOTH directions: it could fire with no write,
# and on macOS it could not fire even if a real write had happened. A check that
# reads the host is not a check.
#
# THE FIX IS TO MAKE THE TRAVERSAL LAND SOMEWHERE MEASURABLE. The project sits
# three levels below a private sandbox root, so `../../../etc` resolves to
# $S1_SB/etc on EVERY host, and the manifest covers the WHOLE sandbox rather
# than just the project — so a write anywhere the traversal could reach shows up
# as a changed line instead of as an existence test nobody can trust.
S1_SB="$TMPROOT/s1-sandbox"
PS="$S1_SB/a/b/proj"; mk_proj "$PS" 4
s1_before="$(tree_manifest "$S1_SB")"
open_feature "$REPO_ROOT/scripts" "$PS" "../../../etc/cron.d/evil"
s1_rc=$DRC
s1_after="$(tree_manifest "$S1_SB")"
s1_diff="$(diff <(printf '%s\n' "$s1_before") <(printf '%s\n' "$s1_after") 2>/dev/null | grep -c '^[<>]' || true)"
case "$s1_diff" in ''|*[!0-9]*) s1_diff=0 ;; esac
s1_escaped=n
[ -e "$S1_SB/etc" ] && s1_escaped=y

# THE POSITIVE CONTROL, and it is the whole lesson of the CI failure. A probe
# that cannot be made to fire is the same no-op the old one was, so the
# IDENTICAL predicate runs against a sandbox where the escape is planted BY
# HAND and must report it. Without this the row could rot back into a check
# that passes because nothing can ever trip it.
S1_CTL="$TMPROOT/s1-control"
mkdir -p "$S1_CTL/a/b/proj"
s1_ctl_before="$(tree_manifest "$S1_CTL")"
mkdir -p "$S1_CTL/etc/cron.d" && : > "$S1_CTL/etc/cron.d/evil"
s1_ctl_after="$(tree_manifest "$S1_CTL")"
s1_ctl_diff="$(diff <(printf '%s\n' "$s1_ctl_before") <(printf '%s\n' "$s1_ctl_after") 2>/dev/null | grep -c '^[<>]' || true)"
case "$s1_ctl_diff" in ''|*[!0-9]*) s1_ctl_diff=0 ;; esac
s1_ctl_seen=n
[ -e "$S1_CTL/etc" ] && s1_ctl_seen=y

if [ "$s1_rc" -eq 2 ] && [ "$s1_diff" -eq 0 ] && [ "$s1_escaped" = n ] \
   && [ "$s1_ctl_seen" = y ] && [ "$s1_ctl_diff" -gt 0 ]; then
  pass "S1: --slug '../../../etc/cron.d/evil' is REFUSED (rc $s1_rc) and the whole SANDBOX — not just the project — is byte-identical afterwards ($s1_diff files changed), with nothing at the traversal's landing site. The same predicate DOES fire on a hand-planted escape ($s1_ctl_diff file(s), detected=$s1_ctl_seen), so this measures a write rather than the host's own /etc"
else
  fail_ "S1" "rc=$s1_rc (want 2); sandbox changed on $s1_diff line(s) (want 0); escaped-write detected=$s1_escaped (want n); POSITIVE CONTROL detected=$s1_ctl_seen on $s1_ctl_diff changed line(s) (want y and >0 — if this half fails the probe is a no-op again)"
fi

# S2 — the neighbouring shapes, each on its OWN fresh fixture. An absolute
# path, a bare `..`, a backslash and a leading dot are all the same class of
# input and a guard that catches one spelling is not a guard.
s2_bad=""
s2_i=0
for bad in "/etc/passwd" ".." "a/../../b" 'win\\path' ".hidden"; do
  s2_i=$((s2_i + 1))
  d="$TMPROOT/slug-shape-$s2_i"
  mk_proj "$d" 4
  open_feature "$REPO_ROOT/scripts" "$d" "$bad"
  [ "$DRC" -eq 2 ] || s2_bad="$s2_bad [$bad=rc$DRC]"
  [ -f "$d/.claude/delta-state.json" ] && s2_bad="$s2_bad [$bad=activated]"
done
if [ -z "$s2_bad" ]; then
  pass "S2: every path-shaped slug spelling is refused with rc 2 and activates nothing — absolute, bare '..', an embedded '..', a backslash, and a leading dot"
else
  fail_ "S2" "these spellings were not refused cleanly:$s2_bad"
fi

# S2b — THE SPELLING THAT IS NOT A SEPARATOR (review R-WP8-3). A newline passes
# every pattern S2 covers — it is not `/`, not `\`, not `..`, not a leading dot
# — and `_slugify`'s sed is LINE-oriented, so it survives into the composed file
# name. Measured, not assumed: the assertion below reads the recorded slug back
# and requires the tree to be untouched.
PSN="$TMPROOT/slug-newline"; mk_proj "$PSN" 4
s2b_before="$(tree_manifest "$PSN")"
open_feature "$REPO_ROOT/scripts" "$PSN" "$(printf 'csv\nexport')"
s2b_rc=$DRC
s2b_after="$(tree_manifest "$PSN")"
s2b_diff="$(diff <(printf '%s\n' "$s2b_before") <(printf '%s\n' "$s2b_after") 2>/dev/null | grep -c '^[<>]' || true)"
case "$s2b_diff" in ''|*[!0-9]*) s2b_diff=0 ;; esac
s2b_files="$(find "$PSN/docs/deltas" -type f 2>/dev/null | grep -c '' || true)"
case "$s2b_files" in ''|*[!0-9]*) s2b_files=0 ;; esac
if [ "$s2b_rc" -eq 2 ] && [ "$s2b_diff" -eq 0 ] && [ "$s2b_files" -eq 0 ]; then
  pass "S2b: a --slug containing a NEWLINE is refused (rc $s2b_rc), the tree is byte-identical ($s2b_diff files changed) and no brief was written ($s2b_files files under docs/deltas) — no file name gains a line break the operator could never type"
else
  fail_ "S2b" "rc=$s2b_rc (want 2); tree changed on $s2b_diff line(s) (want 0); brief files written=$s2b_files (want 0)"
fi

# S3 — AND THE GUARD IS NOT A BLANKET REFUSAL. An ordinary messy human slug
# still opens, and the basename it produces contains only [a-z0-9-].
PS3="$TMPROOT/slug-sanitise"; mk_proj "$PS3" 4
open_feature "$REPO_ROOT/scripts" "$PS3" "CSV Export -- Unicode!! (v2)"
s3_rc=$DRC
s3_slug="$(active_json "$PS3" -r '.active_delta.slug // "NONE"')"
s3_brief="$(active_json "$PS3" -r '.active_delta.brief // "NONE"')"
s3_clean=n
case "$s3_slug" in
  ''|*[!a-z0-9-]*) : ;;
  *) s3_clean=y ;;
esac
if [ "$s3_rc" -eq 0 ] && [ "$s3_clean" = y ] && [ "$s3_brief" = "docs/deltas/DELTA-001-$s3_slug.md" ] \
   && [ -f "$PS3/$s3_brief" ]; then
  pass "S3: a messy human slug is SANITISED rather than refused — 'CSV Export -- Unicode!! (v2)' opens (rc $s3_rc) as '$s3_slug', all [a-z0-9-], at $s3_brief"
else
  fail_ "S3" "rc=$s3_rc; slug='$s3_slug' clean=$s3_clean; brief=$s3_brief"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== L — the ledger row (§6.3's HARD constraint) and Karl's decision 3 ==="
# ════════════════════════════════════════════════════════════════════════════

PL="$TMPROOT/ledger-hotfix"; mk_proj "$PL" 4
seed_bugs_rows "$PL/BUGS.md"
l_cols_before="$(grep -c '^| [0-9]' "$PL/BUGS.md" || true)"
l_sep_before="$(grep -n '^|---' "$PL/BUGS.md" | head -1 | cut -d: -f1)"
l_width_before="$(grep '^|---' "$PL/BUGS.md" | head -1 | awk -F'|' '{print NF}')"
delta_run "$REPO_ROOT/scripts" "$PL" --open --describe "checkout is down for everyone right now" \
  --class hotfix --risk core --level small --slug "checkout-down" --lines 5 --confirm
l_rc=$DRC
l_id="$(active_json "$PL" -r '.active_delta.id // "NONE"')"
l_ledger="$(active_json "$PL" -r '.active_delta.ledger // "NONE"')"
l_audit="$(active_json "$PL" -r '.active_delta.audit_row_at_open // "NONE"')"
l_row="$(grep -n "$l_id" "$PL/BUGS.md" | head -1)"
l_rowtext="${l_row#*:}"

# The delta link must sit in the EXISTING `Fix Reference` column — column 8 of
# the shipped nine, counted the way `awk -F'|'` counts a leading-pipe row.
l_fixref="$(printf '%s\n' "$l_rowtext" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $9); print $9}')"
l_width_row="$(printf '%s\n' "$l_rowtext" | awk -F'|' '{print NF}')"
if [ "$l_rc" -eq 0 ] && [ -n "$l_row" ] && [ "$l_width_row" = "$l_width_before" ] \
   && printf '%s' "$l_fixref" | grep -q "$l_id"; then
  pass "L1: the hotfix's BUGS.md row rides the EXISTING Fix Reference column ('$l_fixref') and the row has exactly the shipped column count ($l_width_row fields, same as the separator) — §6.3's hard constraint, because a new column is what silently breaks a grep -c 'SEV-2.*Deferred'"
else
  fail_ "L1" "rc=$l_rc; row='$l_rowtext'; Fix Reference cell='$l_fixref'; row width=$l_width_row vs separator $l_width_before"
fi

# L2 — the table STILL PARSES the way the gate parses it. These are the exact
# greps scripts/test-gate.sh runs (`# BUGS.md format:` block), so this is the
# gate's own instrument, not a lookalike.
l2_sev1="$(grep -c 'SEV-1.*Open' "$PL/BUGS.md" 2>/dev/null || true)"
l2_sev2o="$(grep -c 'SEV-2.*Open' "$PL/BUGS.md" 2>/dev/null || true)"
l2_sev2d="$(grep -c 'SEV-2.*Deferred' "$PL/BUGS.md" 2>/dev/null || true)"
l2_sev3="$(grep -c 'SEV-3.*Open' "$PL/BUGS.md" 2>/dev/null || true)"
for v in l2_sev1 l2_sev2o l2_sev2d l2_sev3; do
  eval "case \"\$$v\" in ''|*[!0-9]*) $v=0 ;; esac"
done
if [ "$l2_sev2d" -ge 1 ] && [ "$l2_sev1" -ge 1 ] && [ "$l2_sev3" = "0" ] && [ "$l2_sev2o" = "0" ]; then
  pass "L2: after the append, the gate's OWN greps still find their rows — SEV-1.*Open=$l2_sev1, SEV-2.*Deferred=$l2_sev2d, and the rows that were never open still do not match (SEV-2.*Open=$l2_sev2o, SEV-3.*Open=$l2_sev3)"
else
  fail_ "L2" "gate greps after append: SEV-1.*Open=$l2_sev1 SEV-2.*Open=$l2_sev2o SEV-2.*Deferred=$l2_sev2d SEV-3.*Open=$l2_sev3"
fi

# L3 — KARL'S DECISION 3, BOTH HALVES. The visible ledger row AND WP5's state
# stamp. WP5's record is not removed, and its test is not disturbed.
if [ "$l_audit" != "NONE" ] && [ "$l_audit" != "null" ] && [ -n "$l_row" ] \
   && [ "$l_ledger" = "BUGS.md" ]; then
  pass "L3: the hotfix audit trace is written in BOTH places — a real BUGS.md row (Karl's decision 3: the state stamp survives neither an abandoned hotfix nor a lost state file) AND WP5's 'audit_row_at_open' stamp ($l_audit), which is left exactly as WP5 wrote it"
else
  fail_ "L3" "audit_row_at_open='$l_audit'; ledger='$l_ledger' (want BUGS.md); BUGS.md row present=$([ -n "$l_row" ] && echo y || echo n)"
fi

# L4 — `ledger_row` STAYS ATTESTED. WP5's header says the operator's own
# BUGS.md row "stays attested like every other class's"; seeding a row must not
# quietly tick that gate, or the operator never fills in what the row says.
l4_done="$(active_json "$PL" -c '.active_delta.gates_completed')"
l4_has_ledger=n
printf '%s' "$l4_done" | grep -q 'ledger_row' && l4_has_ledger=y
l4_has_audit=n
printf '%s' "$l4_done" | grep -q 'audit_row_at_open' && l4_has_audit=y
if [ "$l4_has_ledger" = n ] && [ "$l4_has_audit" = y ]; then
  pass "L4: seeding the row did NOT tick 'ledger_row' (gates_completed=$l4_done) — the framework wrote the trace, the operator still owes the content. 'audit_row_at_open' stays complete-at-open, exactly as WP5 left it"
else
  fail_ "L4" "gates_completed=$l4_done — ledger_row ticked=$l4_has_ledger (want n), audit_row_at_open ticked=$l4_has_audit (want y)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== BR — the bridge (§10.4): a READ, never a move ==="
# ════════════════════════════════════════════════════════════════════════════

PB="$TMPROOT/bridge"; mk_proj "$PB" 4
write_manifesto "$PB"
br_md5_before="$(_md5file "$PB/PRODUCT_MANIFESTO.md")"
delta_run "$REPO_ROOT/scripts" "$PB" --status
br_rc=$DRC
br_out="$DOUT"
br_md5_after="$(_md5file "$PB/PRODUCT_MANIFESTO.md")"
br_named=0
for item in "Bulk CSV import" "Dark mode" "Saved filters"; do
  printf '%s\n' "$br_out" | grep -qF "$item" && br_named=$((br_named + 1))
done
if [ "$br_rc" -eq 0 ] && [ "$br_named" -eq 3 ] && [ "$br_md5_before" = "$br_md5_after" ]; then
  pass "BR1: --status lists all 3 § 6 Post-MVP items as CANDIDATES (rc $br_rc) and PRODUCT_MANIFESTO.md is byte-identical afterwards (md5 $br_md5_before) — the seeding is a read, the cutline governance is untouched"
else
  fail_ "BR1" "rc=$br_rc; items named=$br_named of 3; md5 $br_md5_before -> $br_md5_after"
fi

# BR2 — nothing auto-opens. Reading candidates must not activate one.
br2_state="$([ -f "$PB/.claude/delta-state.json" ] && echo present || echo absent)"
if [ "$br2_state" = present ]; then
  br2_active="$(active_json "$PB" -r '.active_delta')"
else
  br2_active="no-state-file"
fi
if [ "$br2_active" = "null" ] || [ "$br2_active" = "no-state-file" ]; then
  pass "BR2: listing candidates opened nothing (active_delta=$br2_active, state file $br2_state) — §10.4's 'nothing is auto-opened, nothing is deleted'"
else
  fail_ "BR2" "active_delta after a --status read was '$br2_active'"
fi

# BR3 — the bridge is silent when there is nothing to bridge. A project with no
# manifesto must not have --status invent a section.
PB3="$TMPROOT/bridge-none"; mk_proj "$PB3" 4
delta_run "$REPO_ROOT/scripts" "$PB3" --status
br3_rc=$DRC
br3_quiet=y
printf '%s\n' "$DOUT" | grep -qi 'candidate' && br3_quiet=n
if [ "$br3_rc" -eq 0 ] && [ "$br3_quiet" = y ]; then
  pass "BR3: with no PRODUCT_MANIFESTO.md, --status still succeeds (rc $br3_rc) and says nothing about candidates — the bridge is a read of a document that may not be there"
else
  fail_ "BR3" "rc=$br3_rc; candidate wording present when no manifesto exists=$([ "$br3_quiet" = y ] && echo n || echo y)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== R — resume.sh's FOURTH branch (§10.5) ==="
# ════════════════════════════════════════════════════════════════════════════

# R1 — it does NOT fire below phase 4. The era invariant is the load-bearing
# one; a greeting that talked about post-1.0 work at phase 2 would be teaching
# the operator that the delta track is available before it is.
PR3="$TMPROOT/resume-phase3"; mk_proj "$PR3" 3
write_manifesto "$PR3"
resume_run "$REPO_ROOT/scripts" "$PR3"
r1_rc=$RRC
r1_delta=n
printf '%s\n' "$ROUT" | grep -qi 'shipped\|post-release\|post-1\.0' && r1_delta=y
r1_classic=n
printf '%s\n' "$ROUT" | grep -q 'We are resuming work on this project' && r1_classic=y
if [ "$r1_rc" -eq 0 ] && [ "$r1_delta" = n ] && [ "$r1_classic" = y ]; then
  pass "R1: at phase 3 the fourth branch does not fire — resume.sh emits the CLASSIC prompt (rc $r1_rc), and says nothing about post-release work"
else
  fail_ "R1" "rc=$r1_rc; delta wording present=$r1_delta (want n); classic prompt present=$r1_classic (want y)"
fi

# R2 — §10.5 sub-case ONE: phase 4 with a delta open.
PR4="$TMPROOT/resume-open"; mk_proj "$PR4" 4
write_manifesto "$PR4"
open_feature "$REPO_ROOT/scripts" "$PR4" "csv-import"
# Leave at least one gate outstanding so "the outstanding entries" has content.
resume_run "$REPO_ROOT/scripts" "$PR4"
r2_rc=$RRC
r2_id=n; r2_class=n; r2_attrs=n; r2_gates=n; r2_classic=n
printf '%s\n' "$ROUT" | grep -q 'DELTA-001' && r2_id=y
printf '%s\n' "$ROUT" | grep -q 'feature' && r2_class=y
printf '%s\n' "$ROUT" | grep -q 'feature-local' && r2_attrs=y
printf '%s\n' "$ROUT" | grep -q 'brief' && r2_gates=y
printf '%s\n' "$ROUT" | grep -q 'We are resuming work on this project' && r2_classic=y
if [ "$r2_rc" -eq 0 ] && [ "$r2_id" = y ] && [ "$r2_class" = y ] && [ "$r2_attrs" = y ] \
   && [ "$r2_gates" = y ] && [ "$r2_classic" = n ]; then
  pass "R2: phase 4 + an open delta produces the RESUME-THAT-DELTA first message — id, class, confirmed attributes and the outstanding gates — and it replaces the classic prompt rather than being appended to it"
else
  fail_ "R2" "rc=$r2_rc id=$r2_id class=$r2_class attrs=$r2_attrs gates=$r2_gates classic-also-present=$r2_classic"
fi

# R3 — §10.5 sub-case TWO: phase 4 with nothing open. The post-1.0 greeting's
# four content items: how to state a need, overdue cadence, open hotfix retro,
# and the § 6 candidate count.
PR5="$TMPROOT/resume-greeting"; mk_proj "$PR5" 4
write_manifesto "$PR5"
( cd "$PR5" && unset GITHUB_BASE_REF; bash "$REPO_ROOT/scripts/process-checklist.sh" \
    --delta-state-update '.hotfix_retros = [{"id":"DELTA-002","shipped_at":"2026-01-01T00:00:00Z","due_by":"2026-01-04","closed_at":null,"record":null}]' ) >/dev/null 2>&1
resume_run "$REPO_ROOT/scripts" "$PR5"
r3_rc=$RRC
r3_plain=n; r3_retro=n; r3_cand=n; r3_classic=n
printf '%s\n' "$ROUT" | grep -qi 'plain words\|own words' && r3_plain=y
printf '%s\n' "$ROUT" | grep -q 'DELTA-002' && r3_retro=y
printf '%s\n' "$ROUT" | grep -qi 'candidate' && r3_cand=y
printf '%s\n' "$ROUT" | grep -q 'We are resuming work on this project' && r3_classic=y
r3_count=n
printf '%s\n' "$ROUT" | grep -qE '\b3\b' && r3_count=y
if [ "$r3_rc" -eq 0 ] && [ "$r3_plain" = y ] && [ "$r3_retro" = y ] && [ "$r3_cand" = y ] \
   && [ "$r3_count" = y ] && [ "$r3_classic" = n ]; then
  pass "R3: phase 4 + nothing open produces the POST-1.0 greeting — how to state a need in plain words, the outstanding write-up (DELTA-002), and the § 6 candidate count (3) — and it replaces the classic prompt"
else
  fail_ "R3" "rc=$r3_rc plain=$r3_plain retro=$r3_retro candidates=$r3_cand count=$r3_count classic-also=$r3_classic"
fi

# R4 — FAIL SOFT. A phase-4 project WITHOUT the delta module installed (an old
# scaffold, or a severed tree) must fall through to the classic prompt, not
# crash and not print a half-greeting.
PR6="$TMPROOT/resume-nomodule"; mk_proj "$PR6" 4
SEVSD="$TMPROOT/resume-nomodule-scripts"
mk_scripts_tree "$SEVSD"
rm -f "$SEVSD/scripts/lib/delta-state.sh" "$SEVSD/scripts/lib/delta-policy.sh" \
      "$SEVSD/scripts/lib/delta-classify.sh" "$SEVSD/scripts/lib/delta-cadence.sh" \
      "$SEVSD/scripts/delta.sh" "$SEVSD/scripts/cut-release.sh"
resume_run "$SEVSD/scripts" "$PR6"
r4_rc=$RRC
r4_classic=n
printf '%s\n' "$ROUT" | grep -q 'We are resuming work on this project' && r4_classic=y
if [ "$r4_rc" -eq 0 ] && [ "$r4_classic" = y ]; then
  pass "R4: at phase 4 with the delta module ABSENT, resume.sh falls through to the classic prompt (rc $r4_rc) — the branch fails soft exactly like the other four core consumers do, which is what keeps the module severable"
else
  fail_ "R4" "rc=$r4_rc; classic prompt present=$r4_classic (want y). Output was:
$ROUT"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== SH — SHIPPING the module (Karl's decision 1), and the HARD GATE ==="
# ════════════════════════════════════════════════════════════════════════════

# SH1 — every §3.1 module file that belongs in a project is in the copy list,
# derived MECHANICALLY through the same parser the closure check and the
# framework sync use. A hand grep would be a second source of truth.
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh"
SHIPPED="$TMPROOT/shipped.txt"
soif_parse_shipped_scripts "$INIT_PATH" "$REPO_ROOT/scripts" > "$SHIPPED"
sh1_missing=""
for w in scripts/delta.sh scripts/cut-release.sh scripts/lib/delta-state.sh \
         scripts/lib/delta-policy.sh scripts/lib/delta-classify.sh scripts/lib/delta-cadence.sh; do
  grep -qxF "$w" "$SHIPPED" || sh1_missing="$sh1_missing [$w]"
done
if [ -z "$sh1_missing" ]; then
  pass "SH1: all six shippable delta-module scripts are in the derived shipped set — the module now reaches generated projects, which it did not before (the scaffolder carried the string zero times)"
else
  fail_ "SH1" "not shipped:$sh1_missing"
fi

# SH2 — THE LINT IS FRAMEWORK-ONLY AND MUST NOT SHIP. It scans init.sh and
# scripts/lib/*.sh for a boundary that only exists in the framework repo, and
# `## BUG-008:` records what a shipped lint that misbehaves on a generated tree
# costs.
if grep -qxF "scripts/lint-delta-boundary.sh" "$SHIPPED"; then
  fail_ "SH2" "scripts/lint-delta-boundary.sh is in the shipped set — it is a FRAMEWORK lint (see BUG-008: shipped lints must behave on a generated tree with no backlog and no tests/)"
else
  pass "SH2: scripts/lint-delta-boundary.sh is NOT shipped — it is a framework lint, and it is treated exactly like the other unshipped lint-*.sh"
fi

# SH3 — the chmod split, matching the neighbours: entry scripts get +x, sourced
# libs get a plain cp and none. `scripts/lib/adoption-stamp.sh` says so in as
# many words two lines above the delta block.
sh3_chmod="$(grep -E '^[[:space:]]*chmod \+x .*delta\.sh' "$INIT_PATH" || true)"
sh3_lib_chmod="$(grep -E 'chmod \+x[^#]*scripts/lib/delta-' "$INIT_PATH" || true)"
if [ -n "$sh3_chmod" ] && [ -z "$sh3_lib_chmod" ]; then
  pass "SH3: the two entry scripts get chmod +x and the four sourced libs get none — the neighbours' split, followed exactly"
else
  fail_ "SH3" "entry chmod line found=$([ -n "$sh3_chmod" ] && echo y || echo n); a lib was wrongly chmod'd: '$sh3_lib_chmod'"
fi

# SH4 — the Class-T template ships, through the template parser (so the
# currency inventory tracks its drift like every other verbatim template).
SHIPT="$TMPROOT/shipped-templates.txt"
soif_parse_shipped_templates "$INIT_PATH" > "$SHIPT"
if grep -qxF "templates/generated/delta-brief.tmpl" "$SHIPT"; then
  pass "SH4: templates/generated/delta-brief.tmpl is a shipped Class-T template — the manual path has a template to copy, and the currency inventory tracks it"
else
  fail_ "SH4" "delta-brief.tmpl is not in the derived shipped-template set:
$(cat "$SHIPT")"
fi

# SH5 — THE HARD GATE ITSELF. A shipped script may not source a sibling that
# is not shipped, and a copy-list change MOVES the derived shipped set. The
# previous work package failed CI on exactly this.
sh5_rc=0
( bash "$REPO_ROOT/tests/test-scaffold-source-closure.sh" >"$TMPROOT/closure.out" 2>&1 ) || sh5_rc=$?
if [ "$sh5_rc" -eq 0 ]; then
  pass "SH5: tests/test-scaffold-source-closure.sh is GREEN against the new copy list — every \$SCRIPT_DIR sibling the six new shipped scripts source is itself shipped"
else
  fail_ "SH5" "the source-closure gate failed (rc $sh5_rc):
$(tail -25 "$TMPROOT/closure.out")"
fi

# SH6 — the boundary lint still passes, and the seam is still cardinality ONE.
# The shipped-file list is the scaffolder's business, not a delta reference,
# and this row is where that claim is checked rather than asserted.
sh6_rc=0
( bash "$REPO_ROOT/scripts/lint-delta-boundary.sh" --list >"$TMPROOT/boundary.out" 2>&1 ) || sh6_rc=$?
sh6_seam="$(grep -c '^INFO.seam.*cardinality 1/1' "$TMPROOT/boundary.out" || true)"
case "$sh6_seam" in ''|*[!0-9]*) sh6_seam=0 ;; esac
if [ "$sh6_rc" -eq 0 ] && [ "$sh6_seam" -eq 1 ]; then
  pass "SH6: scripts/lint-delta-boundary.sh exits 0 with the seam allowlist still at cardinality 1/1 — shipping the module added no core -> delta dependency edge"
else
  fail_ "SH6" "lint rc=$sh6_rc; 'cardinality 1/1' rows=$sh6_seam (want 1):
$(tail -20 "$TMPROOT/boundary.out")"
fi

# ── The installer exemption is FENCE-BOUNDED, and these three rows are why ──
# The seam's exemption covers a whole file. The installer's deliberately does
# not, because the scaffolder is 4000 lines of core code and a whole-file
# exemption would retire the boundary for all of it. Three ways to get it
# wrong, each measured on the lint's own exit code against a fixture tree.
mk_lint_root() {   # <dest> — a tree the boundary lint can scan for real
  local d="$1"
  mkdir -p "$d"
  cp -R "$REPO_ROOT/scripts" "$d/scripts"
  cp "$INIT_PATH" "$d/$INIT_FILE"
  mkdir -p "$d/docs/deltas"
}
LINT_RC=0
LINT_FILE=""
# lint_root <root> — sets LINT_RC and LINT_FILE. TWO traps are designed out
# here, and both bit the first draft of these rows:
#   * it is NOT called in a command substitution, because a subshell would
#     swallow the globals it sets;
#   * the output goes to a FILE and every assertion greps the FILE, never
#     `printf "$VAR" | grep -q`. SH8's fixture makes the lint emit ~860 KB;
#     `grep -q` exits on its first match, the upstream printf takes SIGPIPE,
#     and `set -o pipefail` promotes rc 141 into the pipeline — so the `&&`
#     never fires and a diagnostic that WAS printed reads as absent. That is
#     the same trap scripts/lint-delta-boundary.sh records against `head -1`.
lint_root() {
  local root="$1" tag
  tag="$(basename "$root")"
  LINT_FILE="$TMPROOT/lint-$tag.out"
  LINT_RC=0
  bash "$REPO_ROOT/scripts/lint-delta-boundary.sh" --root "$root" --list >"$LINT_FILE" 2>&1 || LINT_RC=$?
  return 0
}

# SH6b — THE BASELINE. Every row from SH7 on asserts a NON-ZERO lint, and a
# fixture tree that reds for some unrelated reason would satisfy all of them
# while measuring nothing. So the unmodified fixture is linted first and must be
# clean.
LRB="$TMPROOT/lint-baseline"; mk_lint_root "$LRB"
lint_root "$LRB"
if [ "$LINT_RC" -eq 0 ]; then
  pass "SH6b: the unmodified fixture tree lints CLEAN (rc $LINT_RC) — so every non-zero result below is caused by the edit under test, not by the fixture"
else
  fail_ "SH6b" "the baseline fixture tree already reds (rc $LINT_RC):
$(tail -20 "$LINT_FILE")"
fi

# ── SH7 — THE SMUGGLING BATTERY (review R-WP8-1 / R-WP8-2) ─────────────────
#
# THE FIRST VERSION OF THIS ROW TESTED ONE CASE AND GAVE FALSE CONFIDENCE. It
# injected a STANDALONE `source` (case B below), watched it fail, and concluded
# "the fence cannot launder a real dependency edge". The fence could: the check
# read only a line's LEADING TOKEN, so
#     cp "$SCRIPT_DIR/scripts/lib/delta-cadence.sh" scripts/lib/ ; source "$SCRIPT_DIR/scripts/lib/delta-state.sh"
# was "installation" and the WHOLE line — the `source` with it — was exempted.
# That passed the lint at rc 0 and rode straight through the PR-blocking
# `delta-boundary-lint` job; the severability suite could not see it either,
# because the revert drops the fence wholesale. An adversarial review found it
# by execution.
#
# So this is a BATTERY, and every row asserts the RIGHT REASON, not merely a
# non-zero exit — a fixture that reds for an unrelated reason is a row that
# measures nothing. The two families are deliberately separated:
#   chaining      a second command riding on an installation line
#   grammar       a line that is not an installation statement at all
# and case L is the one that matters most for R-WP8-2: a PERFECTLY CLEAN cp in
# an extra fence, which no I1 arm can see and which only the fence-count bound
# catches. Without L that bound could rot untested behind the chaining check.
#
# The payload is injected through a FILE, never `awk -v`: -v performs escape
# processing and silently eats a trailing backslash, which would have made case
# G test something other than what it says.
_inject_in_fence() {   # <tree> <payload…>
  local d="$1"; shift
  printf '%s\n' "$@" > "$d/inject"
  awk -v f="$d/inject" '
    { print }
    /DELTA-INSTALL-BEGIN/ && !d { while ((getline l < f) > 0) print l; d = 1 }
  ' "$d/$INIT_FILE" > "$d/tmp.$INIT_FILE" && mv "$d/tmp.$INIT_FILE" "$d/$INIT_FILE"
}
_append_extra_fence() {   # <tree> <payload…>
  local d="$1"; shift
  {
    printf '\n  # -- DELTA-INSTALL-BEGIN --\n'
    printf '%s\n' "$@"
    printf '  # -- DELTA-INSTALL-END --\n'
  } >> "$d/$INIT_FILE"
}

SH7_SRC='  source "$SCRIPT_DIR/scripts/lib/delta-state.sh"'
SH7_CP='  cp "$SCRIPT_DIR/scripts/lib/delta-cadence.sh" scripts/lib/'
sh7_detail=""
sh7_ok=y

# _sh7 <tag> <expect-token> <where> <payload…>
_sh7() {
  local tag="$1" want="$2" where="$3"; shift 3
  local d="$TMPROOT/lint-case-$tag"
  mk_lint_root "$d"
  case "$where" in
    in)    _inject_in_fence "$d" "$@" ;;
    extra) _append_extra_fence "$d" "$@" ;;
  esac
  lint_root "$d"
  local got=n
  grep -q "$want" "$LINT_FILE" && got=y
  sh7_detail="$sh7_detail [$tag=rc$LINT_RC/$got]"
  if [ "$LINT_RC" -eq 0 ] || [ "$got" = n ]; then sh7_ok=n; fi
}

CHAIN='command-chaining-inside-the-fence'
GRAM='not-a-plain-installation-statement'
COUNT='DELTA-INSTALL-fence-count'

_sh7 A "$CHAIN" in    "$SH7_CP ; ${SH7_SRC# }"
_sh7 B "$GRAM"  in    "$SH7_SRC"
_sh7 C "$CHAIN" in    '  chmod +x scripts/delta.sh && source "$SCRIPT_DIR/scripts/lib/delta-state.sh"'
_sh7 D "$GRAM"  in    '  ln -s scripts/lib/delta-state.sh /tmp/x'
_sh7 E "$CHAIN" in    "$SH7_CP && ( ${SH7_SRC# } )"
_sh7 F "$CHAIN" in    '  mkdir -p docs/deltas ; . "$SCRIPT_DIR/scripts/lib/delta-state.sh"'
_sh7 G "$CHAIN" in    "$SH7_CP \\" "$SH7_SRC"
_sh7 H "$CHAIN" in    '  cp "$SCRIPT_DIR/scripts/lib/delta-state.sh" $(dirname scripts/lib)/'
_sh7 J "$COUNT" extra "$SH7_SRC"
_sh7 K "$CHAIN" extra "$SH7_CP ; ${SH7_SRC# }"
_sh7 L "$COUNT" extra "$SH7_CP"

# L's STRUCTURAL DISCRIMINATOR. L is a clean cp — if it reds because some I1 arm
# fired, the fence-count bound is not what caught it and R-WP8-2 is unpinned.
sh7_l_clean=y
grep -qE "$CHAIN|$GRAM" "$TMPROOT/lint-lint-case-L.out" 2>/dev/null && sh7_l_clean=n

# And the SMUGGLED REFERENCE ITSELF must now be visible to tier T1 — the point
# is not that the line was flagged, it is that the module path stopped being
# exempt.
sh7_t1=y
for t in A B C D E F G H; do
  grep -qE '^FAIL.T1' "$TMPROOT/lint-lint-case-$t.out" 2>/dev/null || sh7_t1=n
done

if [ "$sh7_ok" = y ] && [ "$sh7_l_clean" = y ] && [ "$sh7_t1" = y ]; then
  pass "SH7: all eleven smuggling attempts fail, each for the RIGHT reason —$sh7_detail (tag=rc/expected-diagnostic-found). A-H are in-fence: the four chaining spellings (';', '&&', a subshell, a '\\' continuation), a command substitution, a standalone 'source', a bare 'ln', and in every one of them the module path is now visible to tier T1 again. J/K/L are extra fences, and L is a PERFECTLY CLEAN cp caught by the fence-count bound alone (no I1 row: $sh7_l_clean) — which is the only thing that pins R-WP8-2 independently"
else
  fail_ "SH7" "cases:$sh7_detail (want every rc non-zero and every expected diagnostic found); L caught by count alone=$sh7_l_clean; T1 visible on all of A-H=$sh7_t1"
fi

# SH8 — an UNTERMINATED fence. Left tolerated, one stray BEGIN near the top of
# the scaffolder would exempt everything after it.
LR8="$TMPROOT/lint-fence-open"; mk_lint_root "$LR8"
grep -v 'DELTA-INSTALL-END' "$LR8/$INIT_FILE" > "$LR8/tmp.$INIT_FILE" && mv "$LR8/tmp.$INIT_FILE" "$LR8/$INIT_FILE"
lint_root "$LR8"; sh8_rc="$LINT_RC"
sh8_msg=n
grep -q 'unterminated-DELTA-INSTALL-fence' "$LINT_FILE" && sh8_msg=y
if [ "$sh8_rc" != "0" ] && [ "$sh8_msg" = y ]; then
  pass "SH8: an unterminated fence fails closed (rc $sh8_rc) and says so — a stray BEGIN would otherwise exempt every line after it"
else
  fail_ "SH8" "lint rc=$sh8_rc (want non-zero); unterminated diagnostic present=$sh8_msg"
fi

# SH9 — a module path OUTSIDE the fence, in the same file. The exemption is
# bounded to the fence, not granted to the scaffolder.
LR9="$TMPROOT/lint-outside-fence"; mk_lint_root "$LR9"
printf '\ncp "$SCRIPT_DIR/scripts/delta.sh" /tmp/somewhere\n' >> "$LR9/$INIT_FILE"
lint_root "$LR9"; sh9_rc="$LINT_RC"
sh9_t1=n
grep -qE '^FAIL.T1' "$LINT_FILE" && sh9_t1=y
if [ "$sh9_rc" != "0" ] && [ "$sh9_t1" = y ]; then
  pass "SH9: the very same cp line OUTSIDE the fence is still a T1 violation (rc $sh9_rc) — the exemption is fence-bounded, and the scaffolder did not buy itself a blanket waiver"
else
  fail_ "SH9" "lint rc=$sh9_rc (want non-zero); T1 failure row present=$sh9_t1"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT, PARSE-CHECKED and RUN) ==="
# ════════════════════════════════════════════════════════════════════════════

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ -n "$mode" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_mutation_report() {
  local orig="$1" mut="$2" marker="$3" sites changed n
  sites="$(grep -c "$marker" "$orig" || true)"
  case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
  if diff "$orig" "$mut" >/dev/null 2>&1; then changed=n; else changed=y; fi
  n="$(diff "$orig" "$mut" | grep -c '^[<>]' || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s|%s|%s' "$sites" "$changed" "$n"
}

MT="$TMPROOT/mutants"
mkdir -p "$MT"
MUT_REPORT=""
MUT_SD=""

# _mutate <name> <target-rel> <marker> <sed-expr> <check-fn>
#   FRESH TREE per mutant. Anchored marker, sites==1, exactly one line changed,
#   mode preserved, and `bash -n` on the mutated file — that last one is not
#   ceremony: a mutation that lands mid-continuation yields a mangled parse
#   whose crash reads as "the guard caught it", and this wave has one of those
#   on the record.
_mutate() {
  local name="$1" rel="$2" marker="$3" expr="$4" check="$5"
  local SD rep sites changed lines mode_before mode_after nrc
  SD="$MT/$name"
  mk_scripts_tree "$SD"
  mode_before="$(_mode_of "$SD/$rel")"
  cp "$SD/$rel" "$MT/$name.orig"
  _sed_inplace "$SD/$rel" "$expr"
  mode_after="$(_mode_of "$SD/$rel")"
  rep="$(_mutation_report "$MT/$name.orig" "$SD/$rel" "$marker")"
  sites="${rep%%|*}"; rep="${rep#*|}"; changed="${rep%%|*}"; lines="${rep##*|}"
  nrc=0; bash -n "$SD/$rel" 2>/dev/null || nrc=$?
  MUT_REPORT="marker '$marker' sites=$sites, changed=$changed, diff-lines=$lines, mode $mode_before -> $mode_after, bash -n rc=$nrc"
  MUT_SD="$SD/scripts"
  if [ "$sites" -ne 1 ] || [ "$changed" != y ] || [ "$lines" -ne 2 ] \
     || [ "$mode_before" != "$mode_after" ] || [ "$nrc" -ne 0 ]; then
    fail_ "$name (harness)" "the mutation is not anchored/single-line/mode-preserving/parseable: $MUT_REPORT"
    return 0
  fi
  "$check" "$name"
  return 0
}

# ── m1: the bridge WRITES to the manifesto ──────────────────────────────────
# §10.4's whole point is that the seeding is a read. The discriminator is
# STRUCTURAL — an md5 of the manifesto — because the expected result is an
# ABSENCE, and no printed message can testify to a write that did not happen.
_m1_check() {
  local name="$1" P before after rc
  P="$MT/$name-proj"; mk_proj "$P" 4; write_manifesto "$P"
  before="$(_md5file "$P/PRODUCT_MANIFESTO.md")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/delta.sh" --status </dev/null >/dev/null 2>&1 ) || rc=$?
  after="$(_md5file "$P/PRODUCT_MANIFESTO.md" 2>/dev/null || echo MISSING)"
  if [ "$before" != "$after" ]; then
    pass "m1: with the read-only bridge turned into a write, --status MODIFIES PRODUCT_MANIFESTO.md (md5 $before -> $after) — BR1's md5 discriminator sees it. $MUT_REPORT"
  else
    fail_ "m1" "the mutant left the manifesto byte-identical ($before), so BR1 cannot see this line. $MUT_REPORT"
  fi
}

# ── m2: the slug sanitiser, neutered ────────────────────────────────────────
_m2_check() {
  local name="$1" P rc slug
  P="$MT/$name-proj"; mk_proj "$P" 4
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/delta.sh" --open \
      --describe "add a bulk CSV import screen" --class feature --risk feature-local \
      --level significant --lines 40 --slug "../../../etc/cron.d/evil" --confirm \
      </dev/null >/dev/null 2>&1 ) || rc=$?
  slug="$(jq -r '.active_delta.slug // "NONE"' "$P/.claude/delta-state.json" 2>/dev/null || echo NONE)"
  if [ "$rc" -eq 0 ] && [ "$slug" != "NONE" ]; then
    pass "m2: with the traversal guard neutered the mutant ACCEPTS '../../../etc/cron.d/evil' (rc $rc) instead of refusing it, and records it as '$slug' — S1 and S2 see the exit code move. Note what the mutant does NOT do: _slugify still flattens the string, so the guard is the LOUD half of a two-layer defence, and this row measures exactly that half"
  else
    fail_ "m2" "the mutant still refused (rc $rc, slug '$slug') — S1/S2 cannot see this line. $MUT_REPORT"
  fi
}

# ── m3: the BUGS.md row written to a NEW column ─────────────────────────────
# §6.3's hard constraint, and the failure it names is silent: a new column
# shifts nothing today and breaks a `grep -c 'SEV-2.*Deferred'` later.
_m3_check() {
  local name="$1" P rc row width sep out fixref
  P="$MT/$name-proj"; mk_proj "$P" 4; seed_bugs_rows "$P/BUGS.md"
  sep="$(grep '^|---' "$P/BUGS.md" | head -1 | awk -F'|' '{print NF}')"
  rc=0
  out="$( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/delta.sh" --open \
      --describe "checkout is down for everyone right now" --class hotfix --risk core \
      --level small --lines 5 --slug "checkout-down" --confirm \
      </dev/null 2>&1 )" || rc=$?
  row="$(grep -n 'DELTA-001' "$P/BUGS.md" | head -1)"
  row="${row#*:}"
  width="$(printf '%s\n' "$row" | awk -F'|' '{print NF}')"

  # ── PRECONDITIONS, ASSERTED BEFORE ANY VERDICT IS BELIEVED ───────────────
  # THIS IS THE VACUITY CLASS, FOUND IN THIS HARNESS BY CI. An absent row
  # trivially "differs in width" from the table, so the old form could report a
  # mutation KILLED on the strength of a row that never existed.
  #
  # WHAT ACTUALLY HAPPENED ON CI, and it is sharper than "the mutant crashed".
  # The previous mutant read `$row` before assignment. bash 3.2 — this repo's
  # local shell — treats a bare `local row` as empty and sails through, so it
  # passed here. bash 5 aborts on it under `set -u`. But `_ledger_write` is
  # called in a COMMAND SUBSTITUTION, so that abort killed only the subshell:
  # `--open` carried on, recorded the delta, and returned **rc 0** with no
  # ledger row anywhere. Measured, not assumed — the reproduction below prints
  # `open rc=0`.
  #
  # THAT IS WHY BOTH HALVES OF THIS PRECONDITION EXIST, and why the exit code
  # alone would have been useless: rc was fine. The row's PRESENCE is the
  # load-bearing half. The failure says VACUOUS rather than quoting a width,
  # because a mutation that proved nothing must never read as a measurement,
  # and the mutant's own output is captured (not sent to /dev/null) so the next
  # reader sees why instead of re-running CI to find out.
  if [ "$rc" -ne 0 ] || [ -z "$row" ]; then
    fail_ "$name (vacuous)" "the mutant produced NO row to judge — open rc=$rc, row='$row'. A missing row is not a killed mutation. $MUT_REPORT
    last lines of the mutant's own output: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
    return 0
  fi

  # Two independent discriminators, because the mutation now writes a
  # WELL-FORMED row with a TENTH column rather than a mangled fragment: the
  # field count moves, AND the delta link is no longer in Fix Reference.
  fixref="$(printf '%s\n' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $9); print $9}')"
  if [ "$width" != "$sep" ] && ! printf '%s' "$fixref" | grep -q 'DELTA-001'; then
    pass "m3: with the link written to a NEW tenth column the appended row carries $width fields against the table's $sep AND its Fix Reference cell is now '$fixref' rather than the delta — L1 sees it twice over, on the column count and on the cell. $MUT_REPORT"
  else
    fail_ "m3" "the mutant's row width was $width against $sep and its Fix Reference cell was '$fixref' (row='$row') — L1 cannot see this line. $MUT_REPORT"
  fi
}

_mutate m1 scripts/delta.sh '# DELTA-BRIDGE-READ-ONLY$' \
  's|^\(.*\)# DELTA-BRIDGE-READ-ONLY$|  printf "candidate read\\n" >> "$mf"   # DELTA-BRIDGE-READ-ONLY|' \
  _m1_check

_mutate m2 scripts/delta.sh '# DELTA-OPEN-SLUG-GUARD$' \
  's|^\(.*\)# DELTA-OPEN-SLUG-GUARD$|  if false; then   # DELTA-OPEN-SLUG-GUARD|' \
  _m2_check

# THE MUTANT BUILDS A COMPLETE ROW AND READS NOTHING IT HAS NOT ASSIGNED.
# Its first form was `row="$row | $link |"`, which had two faults. It depended
# on `$row` before assignment — harmless on bash 3.2, fatal under `set -u` on
# bash 5, so the mutant died on CI instead of mutating. And even when it ran it
# produced a mangled three-field fragment, which L1 caught almost by accident.
# This form writes a well-formed row with a TENTH column and the delta link
# moved OUT of Fix Reference into it — which is literally §6.3's hazard ("the
# delta link goes in an EXISTING column, never a new one") rather than a
# lookalike, and it is shell-version independent because `$num`, `$sev` and
# `$link` are all assigned above the marked line.
_mutate m3 scripts/delta.sh '# DELTA-OPEN-LEDGER-COLUMN$' \
  's@^\(.*\)# DELTA-OPEN-LEDGER-COLUMN$@    row="| $num | $sev | Open | m3 | m3 | - | Fix Now | | - | $link |"   # DELTA-OPEN-LEDGER-COLUMN@' \
  _m3_check

# ── m4: drop a shipped file from the copy list -> the CLOSURE suite goes RED ─
# The hard gate, driven through the real suite in a real tree rather than
# re-implemented here. scripts/delta.sh sources "$SCRIPT_DIR/lib/delta-policy.sh",
# so dropping that one cp line is a dangling source in a shipped script.
M4="$MT/m4"
mkdir -p "$M4/tests"
cp -R "$REPO_ROOT/scripts" "$M4/scripts"
cp "$REPO_ROOT/tests/test-scaffold-source-closure.sh" "$M4/tests/"
grep -v 'cp "\$SCRIPT_DIR/scripts/lib/delta-policy.sh"' "$INIT_PATH" > "$M4/$INIT_FILE"
m4_dropped=$(( $(grep -c '' "$INIT_PATH") - $(grep -c '' "$M4/$INIT_FILE") ))
m4_nrc=0; bash -n "$M4/$INIT_FILE" 2>/dev/null || m4_nrc=$?
m4_rc=0
( bash "$M4/tests/test-scaffold-source-closure.sh" >"$M4/out" 2>&1 ) || m4_rc=$?
if [ "$m4_dropped" -eq 1 ] && [ "$m4_nrc" -eq 0 ] && [ "$m4_rc" -ne 0 ] \
   && grep -q 'delta-policy.sh' "$M4/out"; then
  pass "m4: dropping the delta-policy.sh cp line (exactly 1 line, mutant still parses: bash -n rc $m4_nrc) makes the source-closure gate go RED (rc $m4_rc) and NAME the gap — SH5 is load-bearing, not decorative"
else
  fail_ "m4" "lines dropped=$m4_dropped (want 1); bash -n rc=$m4_nrc; closure rc=$m4_rc (want non-zero); gap named=$(grep -c 'delta-policy.sh' "$M4/out" || true)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

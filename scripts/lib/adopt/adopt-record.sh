#!/usr/bin/env bash
# scripts/lib/adopt/adopt-record.sh — WP7/1: the Adoption Record.
#
# SPEC: docs/designs/2026-08-23-brownfield-adoption-v2.md §8.6 (content, re-cut
# 2026-09-17) and v1 §8.8 (the eight-clause structural contract, carried over
# verbatim and unweakened). Backlog: `## BL-242:`.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS IS FOR.
#
# Until this shipped, an adoption's own findings lived in the TRANSCRIPT and
# nowhere else. `adopt_stub_adoption_record` said so in as many words — "the
# adoption itself is recorded in the manifest and nowhere else" — and the
# personal-tier secrets arm told the operator to KEEP THAT TRANSCRIPT, because
# real credential findings in their history had no permanent home. A scrollback
# buffer is not a record. This is the record.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE EIGHT CLAUSES, AND WHY THEY ARE ENFORCED AT WRITE TIME RATHER THAN
# ASSERTED IN A COMMENT.
#
# The record lives INSIDE `APPROVAL_LOG.md`, which is the file four separate
# programs parse to decide whether a gate was crossed with evidence. v1 §8.8
# enumerates eight readers and the eight structural properties that defeat
# them, because four of those readers use UNBOUNDED windows and one of them
# (`check_gate` in `scripts/validate.sh`) does `grep -A 10 "$header" | grep -i
# "date"` — which matches `update`, `Candidate` and `validate` as readily as a
# real one.
#
# A comment cannot hold that shape. The record's content is partly
# OPERATOR-DERIVED — the project's directory name, the `by` and `reason` fields
# of every secrets disposition, the paths in their own tree — and every one of
# those is a string this framework did not choose. A project directory named
# `Phase 0 to Phase 1` would, unguarded, put a line into `APPROVAL_LOG.md` that
# `_cpg_gate_has_evidence` opens its window on.
#
# So there are two mechanisms and they are not redundant:
#
#   1. EVERY operator-derived value goes through `_adopt_rec_cell`, which
#      flattens it to one line and removes the characters that could forge a
#      table row or a heading.
#   2. The whole rendered record is then checked against all eight clauses
#      BEFORE a byte of it reaches the file, and a violation REFUSES the
#      adoption rather than appending a record that reads as an approval.
#
# Mechanism 2 is what makes mechanism 1's completeness non-load-bearing. If a
# future field is added and its sanitiser forgotten, the check catches it at
# the boundary instead of a gate reader catching it six months later by
# believing a gate was crossed.
#
# ─────────────────────────────────────────────────────────────────────────────
# CLAUSE 6 IS MADE ABSOLUTE ON PURPOSE, AND IT IS STRICTER THAN §8.8 ASKS.
#
# §8.8 clause 6 is "no case-insensitive `date` substring within 10 lines of any
# gate-header literal". That is a PROXIMITY property, and proximity depends on
# where the record lands, which depends on the template — three things that can
# move independently. This module instead forbids the substring `date` ANYWHERE
# in the record, which implies clause 6 under every placement and is a single
# grep to check. The cost is a vocabulary restriction on this file's prose: no
# "date", and none of the words that CONTAIN it — "update", "validate",
# "candidate", "mandated". The record says "recorded on" and "the day" instead.
# That cost is worth paying to remove a positional dependency from an
# enforcement property.
#
# For the same reason clause 1 is made absolute too: the record contains no
# capital-P `Phase` token at all, rather than merely avoiding the two-phase
# pattern. `_cpg_gate_has_evidence`'s greps are case-sensitive, so lowercase
# `phase 0` — which the record does use, because it is the true statement about
# where an adopted project rests — is invisible to them.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THE RECORD DOES *NOT* CLAIM.
#
# Three §8.6 content rows have no source in this build and the record says so
# by name rather than omitting them: the assessment's findings and verdict and
# the interview's answers (WP12a — Act 3 is a Claude Code session and has not
# run), the in-production declaration and the exemptions used under it (WP12c),
# and whether the commit-msg gate is LIVE. That last one is not a gap in this
# module — `adopt_install_hooks` runs AFTER the adoption commit, deliberately,
# so at the moment this record is written the answer is genuinely not known.
# The record names the directory git will run hooks from, which IS known, and
# stops there. A record that claimed the gate was live would be making the
# `# BL-290:` mistake — a receipt for having tried.

# ── _adopt_rec_cell VALUE — one line, no table-forging characters, and no
#    text this log's own parsers would read as approval evidence ────────────
#
# TWO JOBS, AND THE SECOND ONE IS NOT COSMETIC.
#
# The first is punctuation: `|` would forge a cell boundary, a newline would
# forge a row, `[` opens three of the placeholder literals clause 7 forbids,
# and `#` at the head of a line forges a heading. Control characters are
# removed outright with `tr -d '[:cntrl:]'` rather than a `$(printf '\n')`
# comparison — which is the EMPTY STRING and silently matches every value
# (CLAUDE.md records that trap costing a whole archive stage).
#
# The second is the one the lint found. The cells this record fills are
# OPERATOR TEXT: a path inside their repository, the `by` and `reason` of a
# disposition they wrote. A path of `src/Phase 0 to Phase 1/cfg.yml` is an
# ordinary directory name; a disposition reason of "penetration test was
# exempted for this repo" is an ordinary sentence. Written verbatim into
# `APPROVAL_LOG.md` the first spells clause 1's pattern, and the second
# satisfies the pen-test exemption grep OUTRIGHT — that reader takes no date
# and no window, it greps the whole file, so one operator sentence would tell
# this framework a penetration test had been exempted.
#
# WHAT HAPPENS TO SUCH A CELL, AND WHY IT IS WITHHELD RATHER THAN REWRITTEN.
# Rewriting it — lowercasing `Phase`, clipping `exempted` — produces a record
# that says something the operator did not say, quietly, in the one document
# that exists to be trusted later. Refusing the adoption over a directory name
# is worse still. So the cell is REPLACED by a stand-in that says what happened
# and why, the rest of the row survives, and the run continues. It is rare by
# construction and loud when it happens.
_adopt_rec_withheld="(withheld: this text spells a phrase this log is parsed for)"
_adopt_rec_cell() {                                   # BL-242-RECORD-CELL
  local v
  v="$(printf '%s' "${1:-}" | tr -d '[:cntrl:]' | tr '|[]#' '    ' | sed 's/  */ /g; s/^ //; s/ $//')"
  # The four patterns a gate reader acts on. Kept in the same order as
  # `adopt_record_clauses` so the two cannot drift apart unnoticed.
  case "$v" in
    *Phase*) printf '%s' "$_adopt_rec_withheld"; return 0 ;;
  esac
  if printf '%s' "$v" | grep -qE 'Pre-Phase 0|Application Owner Approval|IT Security Approval'; then
    printf '%s' "$_adopt_rec_withheld"; return 0
  fi
  if printf '%s' "$v" | grep -qiE 'penetration.*exempted|pen.*test.*exempted'; then
    printf '%s' "$_adopt_rec_withheld"; return 0
  fi
  printf '%s' "$v"
}

# _adopt_rec_or VALUE FALLBACK — a cell, or the fallback when it is empty.
_adopt_rec_or() {
  local v
  v="$(_adopt_rec_cell "${1:-}")"
  case "$v" in '') printf '%s' "$2" ;; *) printf '%s' "$v" ;; esac
}

# ── _adopt_rec_row CELL… — one indented table row whose ASSEMBLED text is safe
#
# PER-CELL SANITISING IS NOT ENOUGH, AND A REAL ADOPTION PROVED IT. Clause 4's
# reader greps `pen.*test.*exempted` over the whole FILE, so it sees a LINE, not
# a cell. A disposition signed by `pen test team` with the reason `exempted by
# policy until Q3` has two cells that each pass `_adopt_rec_cell` cleanly and
# assemble into a row that trips clause 4 — and because the contract is checked
# before the write, that REFUSED the entire organizational adoption:
#
#   [BLOCKED] the Adoption Record would be misreadable as a gate approval,
#             so it was NOT written
#   [REFUSED] the pre-write rehearsal did not complete (rc=1)
#
# A security team name plus the word "exempted" is at least as ordinary as the
# directory name this module refuses to fail over. So the row is tested as a
# row, and cells are withheld FROM THE RIGHT until it is clean — the rightmost
# cell is the free-text `reason`, and losing it costs less than losing the
# fingerprint that identifies which finding the row is about.
#
# The whole-file check in `adopt_record_clauses` stays exactly where it is. It
# is the backstop its own header says it is; this is the mechanism that keeps
# the backstop from being the thing operators meet.
_adopt_rec_row_trips() {                              # BL-242-RECORD-ROW
  case "$1" in *Phase*) return 0 ;; esac
  printf '%s' "$1" | grep -qE 'Pre-Phase 0|Application Owner Approval|IT Security Approval' && return 0
  printf '%s' "$1" | grep -qiE 'penetration.*exempted|pen.*test.*exempted' && return 0
  return 1
}

_adopt_rec_join() {
  local out="    |" c
  for c in "$@"; do out="$out $c |"; done
  printf '%s' "$out"
}

_adopt_rec_row() {                                    # BL-242-RECORD-ROW
  local cells i n row c
  cells=()
  for c in "$@"; do cells[${#cells[@]}]="$(_adopt_rec_cell "$c")"; done
  n=${#cells[@]}
  row="$(_adopt_rec_join ${cells[@]+"${cells[@]}"})"
  i=$((n - 1))
  while [ "$i" -ge 0 ] && _adopt_rec_row_trips "$row"; do
    cells[$i]="$_adopt_rec_withheld"
    row="$(_adopt_rec_join ${cells[@]+"${cells[@]}"})"
    i=$((i - 1))
  done
  # EVERY CELL WITHHELD AND STILL TRIPPING would mean the stand-in itself spells
  # a phrase, which it does not. Fail loud rather than emit the row, because a
  # row that reaches this arm is one nobody has understood.
  if _adopt_rec_row_trips "$row"; then
    printf '    | (row withheld: its assembled text spells a phrase this log is parsed for) |\n'
    return 0
  fi
  printf '%s\n' "$row"
}

# ── adopt_record_clauses FILE — the eight-clause check, as a predicate ──────
# Returns 0 iff FILE satisfies every clause. Prints the failing clause(s) to
# stdout so the caller can name them; prints nothing on success.
#
# THERE IS ONE CALLER, AND AN EARLIER DRAFT OF THIS PARAGRAPH CLAIMED TWO.
# It said this was also `scripts/lint-adoption-record.sh`'s engine. That lint
# was written and then REFUSED by `scripts/lint-module-dependencies.sh`:
#
#   scripts/lint-adoption-record.sh:47: T1 — core file names module path
#   'scripts/lib/adopt/'. Core must never reference a severable module (M3)
#
# which is correct and not allowlistable — the core allowlist's cardinality must
# be exactly 0, because §3.1 says the brownfield module declares no seam. So the
# contract lives HERE, enforced at write time, and is pinned by
# `tests/test-brownfield-wp7-adoption-record.sh` (`tests/` is not in
# `CORE_GLOBS`). A comment that tells an auditor the build enforces something it
# does not is worse than no comment.
adopt_record_clauses() {                              # BL-242-RECORD-CLAUSES
  local f="$1" bad=0
  [ -f "$f" ] || { printf '%s\n' "clause 0: no record at $f"; return 1; }

  # 1 — no `Phase N … Phase N+1` on one line, for N in 0..3. Made absolute:
  #     no capital-P `Phase` token at all.
  if grep -qE '(^|[^[:alnum:]])Phase([^[:alnum:]]|$)' "$f"; then
    printf '%s\n' "clause 1: a capital-P 'Phase' token appears — _cpg_gate_has_evidence opens its window on 'Phase N.*Phase N+1'"; bad=1
  fi

  # 2 — the four named literals check_named_row, validate_approval_section_dated
  #     and the retroactive-STA grep look for.
  if grep -qE 'Pre-Phase 0|Application Owner Approval|IT Security Approval' "$f"; then
    printf '%s\n' "clause 2: a named approval-row literal appears"; bad=1
  fi

  # 3 — no `^##` heading naming an attorney or a legal review.
  if grep -qiE '^##.*(attorney|legal review)' "$f"; then
    printf '%s\n' "clause 3: a heading names an attorney or a legal review — # BL-115-ATTORNEY-ENTRY reads it"; bad=1
  fi

  # 4 — the whole-file pen-test exemption grep.
  if grep -qiE 'penetration.*exempted|pen.*test.*exempted' "$f"; then
    printf '%s\n' "clause 4: a pen-test exemption phrase appears"; bad=1
  fi

  # 5 — NO table row beginning at column 0 whose second cell is Date. The
  #     record's tables are indented four spaces; this is the clause a
  #     well-meaning editor "fixes".
  #
  #     ONE CHECK, TWO MESSAGES — AND IT WAS TWO CHECKS UNTIL A MUTATION SHOWED
  #     WHY THAT WAS A LIE. §8.8's clause 5 is "no column-0 row whose second
  #     cell is Date"; the record holds the stronger property "no column-0 row
  #     at all". Written as two `if`s, the second SUBSUMES the first: deleting
  #     clause 5 outright left the suite at 10/0, because every Date row the
  #     clause-5 case plants is also a column-0 row the clause-5b case catches.
  #     A check no mutation can kill is not a check. So there is one predicate,
  #     which the suite can prove, and the Date case keeps its own sentence
  #     because naming the exact reader is what makes the refusal actionable.
  if grep -qE '^\|' "$f"; then
    if grep -qE '^\|[[:space:]]*\**[[:space:]]*[Dd][Aa][Tt][Ee]' "$f"; then
      printf '%s\n' "clause 5: an unindented table row opens with a Date cell — _cpg_gate_has_evidence greps exactly this"
    else
      printf '%s\n' "clause 5: a table row begins at column 0 — the record's tables must be indented four spaces, or a row below one becomes reachable"
    fi
    bad=1
  fi

  # 6 — no case-insensitive `date` substring in the record's OWN PROSE.
  #
  #     SCOPED TO PROSE, AND THE SCOPE IS THE WHOLE DESIGN OF THIS CLAUSE.
  #     `check_gate` in `scripts/validate.sh` does `grep -A 10 "$header"` then
  #     `grep -i "date"`, and CLAUDE.md records that the second grep matches
  #     `update`, `Candidate` and `validate` as readily as a real one. So the
  #     framework's own sentences here avoid the substring entirely.
  #
  #     THE INDENTED TABLE ROWS ARE EXEMPT ON PURPOSE. Those are the rows that
  #     carry OPERATOR text — a path inside their repository, the reason they
  #     wrote on a disposition — and `src/updater/config.js` is an ordinary
  #     path, not an attack. A first cut banned the substring everywhere and
  #     therefore withheld every finding whose file path contained `update`:
  #     a large usability cost for no safety, because the reader this clause
  #     defeats needs PROXIMITY to a gate header, which clause 6b forecloses
  #     and `adopt_record_placed_last` derives rather than assumes.
  if grep -vE '^    \|' "$f" | grep -qi 'date'; then
    printf '%s\n' "clause 6: the substring 'date' appears in the record's own prose (it also hides inside 'update', 'validate' and 'candidate') — check_gate greps -A 10 then -i date"; bad=1
  fi

  # 7 — the placeholder literals # BL-138-APPROVAL-WINDOW blocks on.
  if grep -qE '\[YYYY-MM-DD\]|\[Name|\[Attorney' "$f"; then
    printf '%s\n' "clause 7: a placeholder literal appears — # BL-138-APPROVAL-WINDOW blocks on these"; bad=1
  fi

  # 8 — the record carries its own `## ` heading. Its PLACEMENT (after every
  #     gate section) is a property of the whole log, not of this fragment, so
  #     it is checked by adopt_record_placed_last below and pinned by the suite.
  if ! grep -qE '^## ' "$f"; then
    printf '%s\n' "clause 8: the record has no '## ' heading of its own"; bad=1
  fi

  [ "$bad" -eq 0 ]
}

# adopt_record_placed_last LOG — clause 8's positional half, over the WHOLE log.
# The record's heading must be the last `## ` heading in the file, so the
# unbounded `grep -A 30 "Pre-Phase 0"` and `grep -A 20 "$gate_name"` windows
# cannot reach it from any gate section above.
ADOPT_RECORD_HEADING='## Adoption Record'
adopt_record_placed_last() {                          # BL-242-RECORD-PLACEMENT
  local log="$1" last
  [ -f "$log" ] || return 1
  last="$(grep -n '^## ' "$log" | tail -1 | cut -d: -f2-)"
  [ "$last" = "$ADOPT_RECORD_HEADING" ]
}

# adopt_record_window_clean LOG — clause 6b, over the ASSEMBLED log.
#
# `check_gate` reads ten lines forward from a gate-header literal and calls any
# case-insensitive `date` in them recorded evidence. The record is exempt from
# that reader iff it begins more than ten lines below the LAST such literal.
# That is a fact about the assembled file, so it is measured on the assembled
# file rather than asserted about the fragment — the same reason
# `adopt_record_placed_last` exists beside it.
#
# The literals are `check_gate`'s own third argument, spelled there four times.
#
# ── `.*` AND NOT `.`, AND THIS IS THE `## BL-147:` SHAPE CAUGHT IN THE ACT ──
# The gate headers are spelled `Phase 0 → Phase 1` with a UTF-8 RIGHTWARDS
# ARROW: three bytes. The first draft matched it with `Phase [0-9] . Phase
# [0-9]`, where `.` must be one CHARACTER — which it is in a UTF-8 locale and
# is not in a byte locale. Measured, same file, same grep:
#
#   /usr/bin/grep -nE 'Phase [0-9] . Phase [0-9]' arrow.txt   rc=0   (default)
#   LC_ALL=C … same pattern                                    rc=1
#   LC_ALL=C … 'Phase [0-9].*Phase [0-9]'                      rc=0   (the fix)
#
# GNU grep 3.11 in `ubuntu:24.04` agrees, and a bare container's default locale
# is the failing one. With no match, `last_gate` is empty and this function took
# the arm below commented "the reader has nothing to open a window on" and
# returned 0 — a check that CANNOT RUN reporting that it PASSED, in the one
# predicate written so the contract would not rest on an accident of placement.
# `.*` has no multibyte dependency in any locale.
#
# ── EACH ARM TAKES ITS OWN READER'S WIDTH, DERIVED FROM THAT READER ─────────
# A first cut used 10 for the gate arm and called 30 "the widest window any
# reader opens". Both halves of that were wrong, and the gate half was wrong in
# the unsafe direction. The windows, read out of `scripts/check-phase-gate.sh`:
#
#   grep -A 20 "$gate_name"                          :1527  the walker's
#                                                           PERMISSIVE
#                                                           pre-extraction, from
#                                                           which
#                                                           validate_approval_fields
#                                                           pulls an approver
#   grep -A 15 "Retroactive Phase 1.*Phase 2.*STA"   :2327  anchor ALSO matched
#                                                           by this arm's own
#                                                           `Phase N…Phase N`
#   grep -A 30 "Pre-Phase 0"                         :1830  no `^## ` bound at
#                                                           all; the widest
#
# So the gate arm is TWENTY, not ten — `adopt_record_placed_last`'s own header
# names `grep -A 20` as a window the placement must defeat, and this predicate
# was refusing only at +10 beneath it. Demonstrated at +11: the walker's
# pre-extraction reached into the record and `validate_approval_fields` pulled
# an `Approver` out of it. Not reachable on either shipped template — the record
# lands ~80 lines below the last gate section — but reachable on an
# operator-authored or truncated `APPROVAL_LOG.md`, which is exactly the case
# this predicate exists for rather than trusting placement.
adopt_record_window_clean() {                         # BL-242-RECORD-WINDOW
  local log="$1" rec last_gate last_pre
  [ -f "$log" ] || return 1
  rec="$(grep -n "^$ADOPT_RECORD_HEADING\$" "$log" | head -1 | cut -d: -f1)"
  [ -n "$rec" ] || return 1
  last_gate="$(grep -nE 'Phase [0-9].*Phase [0-9]' "$log" | tail -1 | cut -d: -f1)"
  if [ -n "$last_gate" ] && [ "$rec" -le "$((last_gate + 20))" ]; then
    return 1
  fi
  last_pre="$(grep -nF 'Pre-Phase 0' "$log" | tail -1 | cut -d: -f1)"
  if [ -n "$last_pre" ] && [ "$rec" -le "$((last_pre + 30))" ]; then
    return 1
  fi
  # Neither literal in the log at all: the readers have nothing to open a
  # window on, so the clause holds.
  return 0
}

# ── _adopt_rec_render ROOT REPORT OUT — build the record, write it to OUT ───
_adopt_rec_render() {
  local root="$1" report="$2" out="$3"
  local today tier anchor scanner status findings rules scanned_by commits toolver
  local archive debt_count hooks_dir reh_s reh_mb poc

  # `date +%F` — the command, not the forbidden substring. The record prints
  # the value under the label "Recorded on".
  today="$(date -u +%Y-%m-%d 2>/dev/null)" || today="unknown"
  tier="$(_adopt_rec_or "${ADOPT_DEPLOYMENT:-}" "unknown")"
  poc="$(_adopt_rec_or "${ADOPT_POC_MODE:-}" "no")"

  # The anchor comes from the stamp, not from a second `git rev-parse`. The
  # manifest stage runs immediately before this one, so the stamp is there; a
  # second read of HEAD would be a second source for one fact and the two could
  # disagree if anything committed in between.
  anchor=""
  if command -v jq >/dev/null 2>&1 && [ -f "$root/.claude/manifest.json" ]; then
    anchor="$(jq -r '.adoption.adoptedAtCommit // ""' "$root/.claude/manifest.json" 2>/dev/null)"
  fi
  anchor="$(_adopt_rec_or "$anchor" "not recorded")"

  scanner="$(_adopt_rec_or "$(adopt_report_read "$report" '.secrets.tool // ""')" "none")"
  # THE VERSION IS A ROW, NOT A PHRASE. `docs/adoption.md` said the record
  # carried "the scanner and its version source" while `_adopt_rec_render` read
  # no version at all — a doc describing a field that did not exist. It exists
  # now; which scanner version read the history is the first thing a successor
  # asks when a finding turns out to have been missed.
  toolver="$(_adopt_rec_or "$(adopt_report_read "$report" '.secrets.toolVersion // ""')" "not recorded")"
  status="$(_adopt_rec_or "$(adopt_report_read "$report" '.secrets.status // ""')" "unknown")"
  findings="$(adopt_int "$(adopt_report_read "$report" '.secrets.findingCount // 0')")"
  rules="$(_adopt_rec_or "$(adopt_report_read "$report" '.secrets.rulesSource // ""')" "unknown")"
  scanned_by="$(_adopt_rec_or "$(adopt_report_read "$report" '.secrets.scannedBy // ""')" "unknown")"
  commits="$(adopt_int "$(adopt_report_read "$report" '.secrets.commitsScanned // 0')")"

  archive="$(_adopt_rec_or "${ADOPT_ARCHIVE_DIR:-}" "nothing of yours collided, so no archive was taken")"

  debt_count="unknown"
  if command -v jq >/dev/null 2>&1 && [ -f "$root/.claude/test-debt.json" ]; then
    debt_count="$(jq -r '.count // "unknown"' "$root/.claude/test-debt.json" 2>/dev/null)"
  fi
  debt_count="$(_adopt_rec_or "$debt_count" "unknown")"

  hooks_dir="$(_adopt_hooks_dir "$root" 2>/dev/null)" || hooks_dir=""
  hooks_dir="$(_adopt_rec_or "$hooks_dir" "git could not say")"

  reh_s="$(_adopt_rec_or "${ADOPT_REHEARSAL_SECONDS:-}" "not measured")"
  reh_mb="$(_adopt_rec_or "${ADOPT_REHEARSAL_MB:-}" "not measured")"

  {
    printf '\n---\n\n'
    printf '%s\n\n' "$ADOPT_RECORD_HEADING"
    printf '%s\n' "_This section is a RECORD of how this project entered the framework. It is NOT an"
    printf '%s\n' "approval and it approves nothing. No gate was crossed to produce it, none is"
    printf '%s\n' "claimed by it, and the project it describes rests at phase 0 like every other"
    printf '%s\n' "project in this framework. It is written once, by the adoption run, and never"
    printf '%s\n' "rewritten._"
    printf '\n'
    printf '%s\n\n' "### How this project was adopted"
    printf '%s\n' "    | Field | Value |"
    printf '%s\n' "    |---|---|"
    _adopt_rec_row "Recorded on" "$today"
    _adopt_rec_row "Enforcement tier" "$tier"
    _adopt_rec_row "Proof-of-concept mode" "$poc"
    _adopt_rec_row "Adopted at commit" "$anchor"
    _adopt_rec_row "Resting rung" "phase 0"
    printf '\n'
    printf '%s\n' "The commit named above is the tip this project was sitting on when adoption ran."
    printf '%s\n' "It is the anchor that bounds the pre-adoption exemption: commits at or before it"
    printf '%s\n' "belong to the history this framework inherited, and every commit after it is held"
    printf '%s\n' "to the ordinary rules."
    printf '\n'
    printf '%s\n\n' "### What the credential scan read, and what it found"
    printf '%s\n' "    | Field | Value |"
    printf '%s\n' "    |---|---|"
    _adopt_rec_row "Scanner" "$scanner"
    _adopt_rec_row "Scanner version" "$toolver"
    _adopt_rec_row "Run by" "$scanned_by"
    _adopt_rec_row "Rules" "$rules"
    _adopt_rec_row "Outcome" "$status"
    _adopt_rec_row "Commits read" "$commits"
    _adopt_rec_row "Findings" "$findings"
    printf '\n'
    _adopt_rec_dispositions "$report"
    printf '%s\n\n' "### What of yours was archived"
    printf '%s\n' "    | Field | Value |"
    printf '%s\n' "    |---|---|"
    _adopt_rec_row "Archive" "$archive"
    printf '\n'
    printf '%s\n' "Nothing of yours was deleted. Every archived file carries a restore line in that"
    printf '%s\n' "directory's MANIFEST.md, and any one of them can be put back with:"
    printf '\n'
    printf '%s\n' '    bash /path/to/solo-orchestrator/scripts/adopt-project.sh --re-add <your path>'
    printf '\n'
    printf '%s\n\n' "### What else this run measured"
    printf '%s\n' "    | Field | Value |"
    printf '%s\n' "    |---|---|"
    _adopt_rec_row "Source files with no test" "$debt_count"
    _adopt_rec_row "Hooks directory git will use" "$hooks_dir"
    _adopt_rec_row "Pre-write rehearsal, seconds" "$reh_s"
    _adopt_rec_row "Pre-write rehearsal, megabytes" "$reh_mb"
    printf '\n'
    printf '%s\n' "The hooks directory is where git will look for this project's hooks. Whether the"
    printf '%s\n' "commit-msg gate is actually running from it is NOT asserted here, and the omission"
    printf '%s\n' "is deliberate: the hooks are installed after the adoption commit, so at the moment"
    printf '%s\n' "this record is written the answer is not yet known. The run itself checks it and"
    printf '%s\n' "says so on screen."
    printf '\n'
    printf '%s\n\n' "### What this record does not say, and who owes it"
    printf '%s\n' "Three things belong in a complete record and are absent because nothing in this"
    printf '%s\n' "build produces them. They are named rather than omitted, so that a reader does not"
    printf '%s\n' "read their absence as a measurement that came back empty:"
    printf '\n'
    printf '%s\n' "- **The assessment — its findings, its fitness verdict and the plan (WP12a).** No"
    printf '%s\n' "  one has yet been asked what this project is for. That conversation happens in a"
    printf '%s\n' "  Claude Code session, not in the adoption script, and it has not happened."
    printf '%s\n' "- **The recorded interview answers (WP12a).** PROJECT_INTAKE.md carries the cells"
    printf '%s\n' "  the survey could fill and leaves the judgement cells blank."
    printf '%s\n' "- **The in-production declaration and any exemption used under it (WP12c).** No"
    printf '%s\n' "  such exemption can exist yet, because nothing can grant one."
    printf '\n'
  } > "$out"
}

# _adopt_rec_dispositions REPORT — the findings and their recorded outcomes.
#
# FINGERPRINTS, NOT SECRETS. §6.2's redaction is a PROJECTION: the record
# carries the rule that matched, the file and line, and gitleaks' fingerprint —
# never a byte of the matched value. That is the same allowlist
# `_adopt_secrets_print_findings` prints from, and it is why this reads the
# report's fields by name instead of echoing rows.
_adopt_rec_dispositions() {
  local report="$1" n f
  n="$(adopt_int "$(adopt_report_read "$report" '.secrets.findingCount // 0')")"
  if [ "$n" -eq 0 ]; then
    printf '%s\n' "No credential findings were reported, so there is nothing to disposition."
    printf '\n'
    return 0
  fi
  printf '%s\n\n' "### The findings, by fingerprint"
  printf '%s\n' "Each row is a match in this project's history. The matched value is NOT reproduced"
  printf '%s\n' "here — only the rule that matched, where it sits, and the fingerprint that names it."
  printf '%s\n' "Rotate anything still live: rewriting history does not un-leak what was already"
  printf '%s\n' "fetched."
  printf '\n'
  printf '%s\n' "    | Rule | Where | Fingerprint |"
  printf '%s\n' "    |---|---|---|"
  # The loop writes at most 200 rows; a history with more than that has a
  # bigger problem than a truncated table, and an unbounded table would bury
  # the rest of the log.
  adopt_report_read "$report" \
    '.secrets.findings[]? | [(.ruleId // "?"), ((.file // "?") + ":" + ((.startLine // "?") | tostring)), (.fingerprint // "?")] | @tsv' \
    2>/dev/null | head -200 | while IFS="$(printf '\t')" read -r rule where fp; do
      _adopt_rec_row "$rule" "$where" "$fp"
    done
  if [ "$n" -gt 200 ]; then
    printf '\n%s\n' "…and $((n - 200)) more, which the run printed in full on screen."
  fi
  printf '\n'
  # THE RECORDED OUTCOMES, when a dispositions file lifted the stop. Absent
  # means absent: a personal-tier adoption carries on with findings and no
  # dispositions file at all, and saying "none recorded" is the true sentence
  # for that run — not "all clear".
  f="${ADOPT_DISPOSITIONS_FILE:-}"
  if [ -n "$f" ] && [ -f "$f" ] && command -v jq >/dev/null 2>&1; then
    # ── THE ROWS ARE EXTRACTED FIRST, AND A FAILED EXTRACTION IS SAID OUT
    #    LOUD. Two separate mechanisms, and the comment that used to sit here
    #    conflated them — it motivated the whole guard with an abort the very
    #    line it annotates makes impossible.
    #
    #    `map(tostring)` handles the NON-SCALAR case, which is what `@tsv` used
    #    to abort on (`rc=5`, zero rows printed, piped straight into a table
    #    that then had a heading, a header row and nothing else at rc 0):
    #
    #      jq -r '… | @tsv'                 d_obj.json   rc=5   0 rows
    #      jq -r '… | map(tostring) | @tsv' d_obj.json   rc=0   fp  accepted-risk  A  {"nested":"object"}
    #
    #    `tostring` is TOTAL over JSON, so that abort can no longer happen and
    #    a comment claiming it as the reason for the guard is the same defect
    #    as a comment naming a lint that was never shipped.
    #
    #    The `_ok` guard covers what remains and is still reachable: a file
    #    that is not parseable JSON at all. Verified end-to-end on a
    #    personal-tier run with a junk `--dispositions` file — the record says
    #    the file could not be read instead of rendering an empty table. That
    #    path matters most on PERSONAL tier, where the findings arm never calls
    #    `adopt_dispositions_satisfy` and `--dispositions` reaches here with no
    #    validation at all.
    # THE DESTINATION IS SPELLED AT EVERY WRITE SITE, not held in a local.
    # tests/test-bl225-staging-preflight.sh T9 is a denylist over write SHAPES
    # with an allowlist of destinations that are not the adoptee's tree, and a
    # redirect into a local variable hid ADOPT_WORK behind that variable — so a
    # scratch write read as an unmarked write into the project. It is right to
    # flag that: a reader of the line could not tell either.
    local _ok
    _ok=1
    jq -r '.dispositions[]? | [(.fingerprint // "?"), (.disposition // "?"), (.by // "?"), (.reason // "?")] | map(tostring) | @tsv' \
      "$f" > "$ADOPT_WORK/record-dispositions.tsv" 2>/dev/null || _ok=0
    printf '%s\n\n' "### What was decided about them"
    if [ "$_ok" -eq 0 ]; then
      printf '%s\n' "The dispositions file could not be read as a list of decisions. Nothing is"
      printf '%s\n' "recorded here, and that is a failure to read the file rather than a finding that"
      printf '%s\n' "nothing was decided — the file is still where you left it."
      printf '\n'
    else
      printf '%s\n' "    | Fingerprint | Outcome | Decided by | Reason |"
      printf '%s\n' "    |---|---|---|---|"
      head -200 "$ADOPT_WORK/record-dispositions.tsv" | while IFS="$(printf '\t')" read -r fp d by why; do
        _adopt_rec_row "$fp" "$d" "$by" "$why"
      done
      printf '\n'
    fi
    _ok=1
    jq -r '.acknowledgements[]? | [(.kind // "?"), (.by // "?"), (.reason // "?")] | map(tostring) | @tsv' \
      "$f" > "$ADOPT_WORK/record-dispositions.tsv" 2>/dev/null || _ok=0
    printf '%s\n\n' "### Acknowledgements"
    if [ "$_ok" -eq 0 ]; then
      printf '%s\n' "The acknowledgements in that file could not be read. Nothing is recorded here."
      printf '\n'
    else
      printf '%s\n' "    | Kind | Given by | Reason |"
      printf '%s\n' "    |---|---|---|"
      head -50 "$ADOPT_WORK/record-dispositions.tsv" | while IFS="$(printf '\t')" read -r kind by why; do
        _adopt_rec_row "$kind" "$by" "$why"
      done
      printf '\n'
    fi
  else
    printf '%s\n' "No dispositions file was supplied, so no outcome is recorded against any finding"
    printf '%s\n' "above. That is the true statement about this run and it is not a clean bill of"
    printf '%s\n' "health: the findings are real and nobody has yet said what was done about them."
    printf '\n'
  fi
}

# ── adopt_write_adoption_record ROOT REPORT — the stage ─────────────────────
adopt_write_adoption_record() {                       # BL-242-RECORD-WRITE
  # `log` IS ASSIGNED ON ITS OWN LINE, AND THAT IS NOT STYLE.
  # `local root="$1" log="$root/APPROVAL_LOG.md"` does NOT see `root`: every
  # right-hand side in one `local` is expanded before any of them is assigned,
  # so `log` became `/APPROVAL_LOG.md` and this function refused with
  # "APPROVAL_LOG.md is not there" against a project whose log was right where
  # it should be — a refusal that named the wrong file and blamed the operator.
  # Measured on bash 3.2.57, 4.0.44, 4.4.23, 5.0.18, 5.2.37 and 5.3.20: the
  # same on all six, so unlike the two version splits CLAUDE.md records, this
  # one is not a host difference and a local green run does not hide it.
  local root="$1" report="$2" tmp why log
  log="$root/APPROVAL_LOG.md"
  if [ ! -f "$log" ]; then
    adopt_refuse "APPROVAL_LOG.md is not there, so the Adoption Record has nowhere to go"
    return 1
  fi
  # ONCE. The stamp refuses a re-stamp for the same reason (# BF-ADOPT-RESTAMP-REFUSE):
  # a record written twice is two accounts of one adoption, and the second one
  # would carry the first one's archive path with the second one's clock.
  if grep -qF "$ADOPT_RECORD_HEADING" "$log" 2>/dev/null; then
    adopt_note "The Adoption Record was already in APPROVAL_LOG.md — left as it was."
    return 0
  fi
  tmp="$ADOPT_WORK/adoption-record.md"
  _adopt_rec_render "$root" "$report" "$tmp" || {
    adopt_refuse "could not build the Adoption Record"
    return 1
  }
  case "$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')" in
    ''|0) adopt_refuse "the Adoption Record rendered empty"; return 1 ;;
  esac
  # THE CHECK IS THE ENFORCEMENT, not a formality — see this file's header.
  why="$(adopt_record_clauses "$tmp")" || {
    adopt_refuse "the Adoption Record would be misreadable as a gate approval, so it was NOT written"
    # STDERR, NOT `adopt_note`, AND THAT IS THE WHOLE POINT OF THIS ARM.
    # The pre-write rehearsal runs the write phase as
    # `_adopt_write_phase … >/dev/null 2>"$_reh_err"` and relays only
    # `$_reh_err`. `adopt_note` writes to STDOUT, so on the rehearsal — which
    # is where this refusal is actually met, because the rehearsal runs first —
    # the operator saw the headline and NOT ONE of the clause lines. The single
    # refusal in this driver whose cause is the operator's own text was the one
    # whose cause was discarded, which is `# BL-225-REFUSE-HONEST` defeated by
    # a redirection.
    printf '%s\n' "$why" | while IFS= read -r line; do
      [ -n "$line" ] && printf '   %s\n' "$line" >&2
    done
    printf '   %s\n' "Nothing was appended to APPROVAL_LOG.md." >&2
    return 1
  }
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  cat "$tmp" >> "$log" || { adopt_refuse "could not append the Adoption Record to APPROVAL_LOG.md"; return 1; }
  # PLACEMENT, DERIVED RATHER THAN ASSUMED. Appending puts the heading last
  # only if nothing else appends after it; that is true today and is exactly
  # the kind of fact that stops being true quietly.
  if ! adopt_record_placed_last "$log"; then
    adopt_refuse "the Adoption Record is not the last section of APPROVAL_LOG.md, so a gate reader's window could reach it"
    return 1
  fi
  if ! adopt_record_window_clean "$log"; then
    adopt_refuse "the Adoption Record sits within ten lines of a gate header, where validate.sh's check_gate would read it as recorded gate evidence"
    return 1
  fi
  adopt_note "The Adoption Record is in APPROVAL_LOG.md — what was scanned, what was found,"
  adopt_note "what was archived, and what this build does not yet know."
  return 0
}

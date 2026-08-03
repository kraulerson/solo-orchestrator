#!/usr/bin/env bash
set -euo pipefail

# scripts/delta.sh — the post-1.0 delta track's operator front door.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §10.1 (THE ERA INVARIANT —
# `active_delta != null => current_phase == 4`, and this file is its LOAD-BEARING
# enforcement point), §7.1 (the state schema, the single-writer rule, and
# `gates_required` materialised AT OPEN), §4.1–§4.3 (the four classes, the
# derived-then-confirmed attributes, confirm-not-quiz), §5.2 (the per-class gate
# subset the materialisation produces), §6.1 (this is the GUIDED creation path),
# §3.1 (a member of the severable delta module), §11-WP3.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose — no backlog
# entry exists for this build, and minting one would red
# scripts/lint-bl-markers.sh. The design-doc path above is the citation, per the
# WP1/WP2 precedent. The grep-able `DELTA-OPEN-*` markers below are this file's
# citation primitive and its mutation addresses.)
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS FILE IS FOR, IN ONE PARAGRAPH
#
# After a project ships 1.0 it never goes back through Phases 0–3. Everything
# after that is a DELTA: a feature, a fix, a hotfix, or a security patch. This
# script opens one. It asks the operator a single question, having already
# proposed every answer from what they typed and from what the repository can
# measure — and it refuses, loudly, in the two situations where opening a delta
# would quietly destroy something.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE TWO REFUSALS, AND WHY EACH ONE EARNS ITS EXIT CODE
#
# 1. THE ERA INVARIANT (§10.1) — `# DELTA-OPEN-ERA-GUARD`, exit 3.
#    `--open` refuses unless `.claude/phase-state.json::current_phase` is
#    EXACTLY 4. §10.1 calls this "the load-bearing one — it is what makes the
#    delta track unable to substitute for building the product properly." A
#    project at phase 2 that could open a delta has discovered a way to do
#    post-release maintenance ceremony INSTEAD of building the product, and the
#    ceremony is cheaper, so it would win.
#
#    READ THE `[WARN]` TRAP BEFORE TOUCHING THIS (CLAUDE.md, and §10.1 repeats
#    it). In check-phase-gate.sh the `[WARN]`/`[FAIL]` text is COSMETIC — the
#    exit predicate is `if [ $issues -eq 0 ]`, so two arms that print the same
#    label can have opposite gate outcomes. The lesson generalises to here: what
#    makes this a refusal is the NON-ZERO RETURN, not the red word next to it.
#    tests/test-delta-wp3-era-classify.sh asserts the exit CODE, never the
#    label, and its m1 mutation neuters this one line to prove the code moves.
#
# 2. THE SECOND-ACTIVATION REFUSAL (§7.1) — `# DELTA-OPEN-ACTIVE-GUARD`, exit 4.
#    WP2 DEFERRED THIS TO HERE, in as many words: scripts/lib/delta-state.sh's
#    "WHAT IT DELIBERATELY DOES NOT ENFORCE" block says overwriting an OPEN
#    active_delta is accepted at the state layer, that §11-WP3 owns open/confirm
#    and therefore owns the business refusal, and that one-at-a-time is only
#    STRUCTURAL until then. This is that refusal, and it is where it belongs:
#    the schema's single `active_delta` slot means a second open would not fail —
#    it would SUCCEED and silently discard the first delta's `gates_completed`,
#    which is the audit trail of everything already done. A refusal that names
#    the open delta is the only outcome that leaves the operator informed.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE SINGLE-WRITER RULE (D7), AND WHAT IT COSTS THIS FILE
#
# `.claude/delta-state.json` has exactly ONE writer: scripts/process-checklist.sh
# (§7.1). This script NEVER touches it — not to read, not to write. Every state
# operation routes through the seam's `--delta-*` actions. That is more
# indirection than a direct `jq` would need, and it is bought deliberately: the
# guard lives in the seam, and a second writer is a guard that can be forgotten.
# scripts/lint-delta-boundary.sh makes the rule checkable, with a seam allowlist
# whose cardinality is asserted at exactly one.
#
# ═════════════════════════════════════════════════════════════════════════════
# CONFIRM, DO NOT QUIZ (§4.3) — the `# BL-204-PREFILL` pattern
#
# The repo's reference implementation is `# BL-204-PREFILL` in
# scripts/intake-wizard.sh: read the remembered answer, PRINT it, print WHY
# re-asking would be wrong, and ask the operator to keep or change. This
# transcript copies it exactly, with one addition §4.3 insists on — every one of
# the four lines names WHERE ITS VALUE CAME FROM, "because a proposal whose
# provenance is hidden is a quiz with extra steps." The provenance text is not
# written here; it is returned alongside each value by
# scripts/lib/delta-classify.sh, so a caller cannot print the value and drop the
# reason.
#
# RAISES ARE FREE, LOWERS ARE REASON-RECORDED (§4.2). The operator may raise
# `risk` to core, `level` to evolution, or `severity` toward SEV-1 with no
# justification at all — they know things the formula does not. Going the other
# way removes a gate, so it records a reason into the delta's own row. A lower
# with no reason available (a scripted run with no `--reason`) is REFUSED rather
# than recorded blank: a blank reason is indistinguishable from a raise nobody
# noticed, three months later, in the audit tail.
#
# ═════════════════════════════════════════════════════════════════════════════
# OPERATOR-FACING TEXT IS PLAIN ENGLISH ON PURPOSE
# §4.3's transcript is the register for everything this script prints. No
# framework jargon, no file paths in the confirm flow, no "invariant". The
# person reading it has just shipped a product and wants to fix a bug.
#
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# THE CLOSE FLOW (WP4) — FIVE REFUSALS, IN THIS ORDER, AND WHY THE ORDER IS THE
# DESIGN
#
# `--close` walks the delta's own record and refuses at the first thing that is
# not true. The ORDER is load-bearing, not cosmetic:
#
#   1. NOTHING OPEN                    exit 6.  Nothing to reason about.
#   2. UNKNOWN GATE TOKEN              exit 9.  A configuration error, and it
#      goes FIRST among the substantive checks because it is the only one whose
#      answer cannot be trusted otherwise: if a token is meaningless, so is
#      "outstanding" and so is "complete". It fails CLOSED and writes nothing.
#   3. CLOSE-TIME RE-DERIVATION        exit 10 (only when it appends).
#      §4.2: the open-time derivation was a FORECAST; this measures the real
#      diff. A higher bracket RAISES the attribute and APPENDS the gates that
#      raise toggles on. It never lowers. It runs BEFORE the outstanding-gates
#      check because the whole point is that the checklist may have grown —
#      running it after would let a delta opened `small` and grown into an auth
#      rewrite close on the small checklist, which is §11-WP4's own mutation.
#   4. GATES OUTSTANDING               exit 7.  gates_required minus
#      gates_completed, named.
#   5. THE RUBRIC BIND                 exit 8.  §5.3's strongest sentence: "the
#      brief's acceptance criteria ARE the close review's rubric". It runs LAST
#      because it needs the brief to exist, and `brief` is itself a gate that
#      step 4 is still able to be waiting on.
#
# REFUSAL RESIDUE — THE STANDARD THIS FILE'S OPEN FLOW SET, SCOPED TO WHAT
# EXECUTION ACTUALLY SHOWS.
#
# READ THIS AS A PROPERTY OF THE RAISE, NOT OF THE EXIT CODE. An earlier version
# of this block said "for 6/7/8/9 that sentence is true of the WHOLE TREE", and
# an adversarial review REFUTED it by execution. The refutation is worth keeping
# because the mistake is the natural one to make: the ratchet writes whenever an
# attribute ROSE, while exit 10 fires only when a gate was ALSO APPENDED, and
# those are different conditions. A raise that toggles nothing — small ->
# significant, which no toggle answers; or risk -> core on a class already
# carrying brief_review — records itself and then falls through to the exit-7 or
# exit-8 refusal. So:
#
#   6 and 9   ALWAYS leave the whole tree pristine. 6 returns before anything is
#             measured, and 9 is ordered BEFORE the ratchet precisely so that a
#             configuration error can never write. N1 pins both.
#   7 and 8   leave the tree pristine WHEN NO RAISE OCCURRED (N1), and carry
#             exactly the bounded ratchet record when one did (N3, N4).
#   10        always carries that record, by construction (N2).
#
# THE RECORD IS BOUNDED, IDEMPOTENT AND ANNOUNCED, and those three are what make
# the exception safe rather than merely admitted. Bounded: it touches the
# delta's own `attributes`, `gates_required` and `ratcheted_at`, and nothing
# else anywhere — asserted in both directions by N2/N3/N4. Idempotent: a second
# close re-measures to the same bracket and writes nothing at all, so the record
# cannot accrete one stamp per attempt. Announced: the transcript names the
# old -> new value every time, so the operator is never the last to know their
# own record moved.
#
# The alternative — announce the new obligations without recording them — was
# rejected: the operator would be told about a larger checklist the record does
# not contain, and every subsequent close would re-announce it as news. §4.2 is
# explicit that the raise is recorded.
#
# GATES ARE ATTESTED, AND THE HELP TEXT MUST NOT PRETEND OTHERWISE. §5.3 tiers
# the review honestly: the rubric is MECHANICAL, the reviewer is ADVISORY.
# `--complete-gate` records that the OPERATOR SAYS a gate is satisfied. The
# framework does not verify that the adversarial review happened, that the
# changelog entry is under the right heading, or that the repro test was RED
# first. The two things it does check itself are the two this WP makes real: the
# brief's done-observable boxes, and the close-time re-measurement of size and
# risk. Do not widen the wording beyond those two.
#
# `retro_review` IS CLOSE-REFUSING BUT NOT YET IMPLEMENTABLE, and that is
# deliberate at this WP. A hotfix carries it (§7.2) and this flow will refuse
# the close until it is attested — but the retro LEDGER (`hotfix_retros[]`, the
# `due_by` arithmetic, the release-cut refusal that collateralises the deferral)
# is §11-WP5's. Until then the token is satisfiable only by attestation, which
# is a weaker thing than the design promises. Recorded here rather than papered
# over.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE RUBRIC PARSE CONTRACT (§5.3/§6.2) — WP8's template must match this
#
# The brief is `docs/deltas/DELTA-NNN-slug.md` (§6.3). This flow reads exactly
# one section of it:
#
#   • A RUBRIC SECTION is opened by ANY heading whose text begins
#     `Done-observable`, case-insensitively, at any heading depth
#     (`## Done-observable`, and a trailing parenthetical is fine). It ENDS at
#     the next heading of the same depth or shallower — so a `### Nice-to-have`
#     subsection inside it is still part of the rubric, and the next `## …` is
#     not. A brief carrying TWO such headings has BOTH read, and the criteria
#     are pooled.
#     THIS SENTENCE USED TO SAY "the FIRST heading" and the code disagreed with
#     it; an adversarial review found the mismatch by execution. The SENTENCE
#     moved, not the code, and deliberately: the implementation is the stricter
#     of the two readings, and a criterion the operator wrote under a second
#     Done-observable heading is still a criterion — a first-only reader would
#     have ignored it and closed. B5 pins both directions so it cannot drift
#     back. WP8's template codifies THIS wording.
#   • A CRITERION is a list item whose marker is `-`, `*` or `+`, at any indent,
#     followed by a bracketed single character: `- [x]` / `- [X]` is CHECKED,
#     `- [ ]` is NOT. Anything else between the brackets is treated as NOT
#     checked and named — an undefined marker is a criterion nobody has decided
#     about, and guessing in the permissive direction is how a rubric quietly
#     stops being one.
#   • ONLY that section is read. Checkboxes under What / Must-not-change /
#     Touched surfaces are ignored, which is pinned in both directions (the
#     refusal never names them; a brief whose rubric is fully checked closes
#     even though other sections carry unchecked boxes).
#   • IT FAILS CLOSED. No brief file, two files matching the id, no
#     Done-observable section, or a section containing NO checkboxes at all are
#     each a refusal. A rubric that cannot be read is not a rubric that passed —
#     and the zero-checkbox case is the one worth naming, because it is the
#     shape a brief takes when the section heading was copied from the template
#     and never filled in.
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES — CODES, NEVER LABELS
#   0  the delta was opened or closed, a gate was recorded, or `--status`
#      reported successfully
#   1  an operation failed (the seam refused a write, jq is missing, …)
#   2  invocation error: bad flag, missing argument, a gate this delta does not
#      owe, or a confirmation that could not be obtained (no terminal and no
#      `--confirm`)
#   3  ERA REFUSAL — the project is not at phase 4          (§10.1)
#   4  SECOND-ACTIVATION REFUSAL — a delta is already open  (§7.1)
#   5  an attribute was LOWERED with no reason recorded     (§4.2)
#   6  there is nothing open to close or to record against  (§7.1)
#   7  required gates are still outstanding                 (§5.2)
#   8  the brief's rubric has an unchecked or unreadable criterion  (§5.3)
#   9  an unknown gate token — a configuration error, failing CLOSED (§5.2)
#  10  the close-time re-measurement RAISED an attribute and added obligations,
#      so the close refuses on the LARGER checklist          (§4.2)
#
# There is NO era refusal on `--close`, and that is a decision. §10.1 places the
# invariant's enforcement at OPEN (load-bearing) and in scripts/validate.sh
# (report-only). An `active_delta` at phase < 4 is already the inconsistency
# validate.sh reports, and closing it is the ONLY path back to a consistent
# record — a close that refused there would strand the delta permanently in the
# state the invariant forbids. Pinned by W3.
#
# BASH 3.2: no associative arrays, no ${var,,} (hence `tr`), no `((x++))`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/helpers-core.sh"

# This script writes into `.claude/` (through the seam) and reads the project's
# own git history. Running it from the framework clone would classify the
# FRAMEWORK's diff and open a delta on the framework's state. Refuse early —
# the same guard, for the same reason, as process-checklist.sh's.
guard_not_in_framework || exit 1

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/delta-policy.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/delta-classify.sh"

SEAM="$SCRIPT_DIR/process-checklist.sh"
PHASE_STATE=".claude/phase-state.json"

USAGE="Usage:
  scripts/delta.sh --open [--describe TEXT] [--slug SLUG] [--confirm]
                   [--class feature|fix|hotfix|security-patch]
                   [--risk core|feature-local] [--level small|significant|evolution]
                   [--severity SEV-1|SEV-2|SEV-3|SEV-4] [--reason TEXT]
                   [--touched-file FILE]
  scripts/delta.sh --complete-gate TOKEN
  scripts/delta.sh --close
  scripts/delta.sh --status
  scripts/delta.sh --help

  --complete-gate records that YOU say a check is done. Most of them are
  attested that way: the framework does not re-run your review, re-read your
  changelog entry or watch your test go red. The two it checks itself are the
  brief's done-observable boxes and the size/risk re-measurement at close.

  --close runs those two checks and refuses while anything is outstanding."

# ── The seam, and nothing but the seam ──────────────────────────────────────
# Every state read and every state write in this file goes through here. The
# `if` form suspends errexit for the call so a legitimate refusal returns as
# itself instead of aborting the script mid-transcript.
_seam() {
  if bash "$SEAM" "$@" </dev/null; then return 0; else return $?; fi
}

# _current_phase — the project's phase as a bare integer, or "" when it cannot
# be read. An unreadable phase is NOT treated as 4: the era guard below compares
# for equality, so "unknown" refuses, which is the fail-closed direction.
_current_phase() {
  local v=""
  if [ -f "$PHASE_STATE" ] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.current_phase // empty' "$PHASE_STATE" 2>/dev/null || true)"
  fi
  case "$v" in ''|*[!0-9]*) v="" ;; esac
  printf '%s' "$v"
}

_phase_words() {
  local p="${1:-}"
  case "$p" in
    "")  printf '%s' "no recorded phase at all" ;;
    0|1) printf '%s' "phase $p — still designing" ;;
    2)   printf '%s' "phase $p — still building" ;;
    3)   printf '%s' "phase $p — still hardening for launch" ;;
    *)   printf '%s' "phase $p" ;;
  esac
}

# ── §4.3's transcript rendering ─────────────────────────────────────────────

# _tline <label> <value> <why> — one line of the confirm transcript: the label,
# the proposed value, and the parenthetical that names where the value came
# from. Long provenance wraps under the parenthesis rather than being truncated;
# a truncated reason is a hidden reason, which §4.3 is specifically about.
_tline() {
  local label="$1" value="$2" why="$3" line n=0 text
  # ASCII placeholder on purpose: `%-15s` pads by BYTES, so a multi-byte dash
  # here would silently misalign the whole column under `printf`.
  [ -n "$value" ] || value="none"
  text="($why)"
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    if [ "$n" -eq 0 ]; then
      printf '  %-9s %-15s %s\n' "$label" "$value" "$line"
      n=1
    else
      printf '                            %s\n' "$line"
    fi
  done <<EOF
$(printf '%s\n' "$text" | fold -s -w 58)
EOF
  return 0
}

_render_transcript() {
  echo ""
  printf 'You said: "%s"\n' "$DESCRIBE"
  echo ""
  _tline "Class:"    "$CLASS" "$CLASS_WHY"
  _tline "Severity:" "$SEV"   "$SEV_WHY"
  _tline "Risk:"     "$RISK"  "$RISK_WHY"
  _tline "Level:"    "$LEVEL" "$LEVEL_WHY"
  echo ""
  echo "  [1] Keep all four        [2] Change the class        [3] Change an attribute"
  echo ""
  return 0
}

# ── Raise / lower (§4.2) ────────────────────────────────────────────────────
# One ordering per attribute, lowest first. `severity` runs BACKWARDS from the
# spelling — SEV-1 is the most severe, so raising severity means moving toward
# SEV-1 and the rank has to invert or every raise would read as a lower.
_rank() {
  local attr="$1" v="$2"
  case "$attr" in
    risk)  case "$v" in feature-local) printf '0' ;; core) printf '1' ;; *) printf '-1' ;; esac ;;
    level) case "$v" in small) printf '0' ;; significant) printf '1' ;; evolution) printf '2' ;; *) printf '-1' ;; esac ;;
    severity) case "$v" in SEV-4) printf '0' ;; SEV-3) printf '1' ;; SEV-2) printf '2' ;; SEV-1) printf '3' ;; *) printf '-1' ;; esac ;;
    *) printf '-1' ;;
  esac
}

_valid_values() {
  case "$1" in
    risk) printf '%s' "core or feature-local" ;;
    level) printf '%s' "small, significant or evolution" ;;
    severity) printf '%s' "SEV-1, SEV-2, SEV-3 or SEV-4" ;;
    class) printf '%s' "feature, fix, hotfix or security-patch" ;;
  esac
}

# _reason_for <attribute> — the recorded reason for lowering, or "" if none can
# be obtained. `--reason` wins; otherwise an operator at a terminal is asked.
# A scripted run with no `--reason` gets "", and the caller REFUSES.
_reason_for() {
  local attr="$1"
  if [ -n "$REASON" ]; then printf '%s' "$REASON"; return 0; fi
  if [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${SOIF_NONINTERACTIVE:-}" ]; then
    prompt_input "You are lowering $attr, which removes a check. Why is that right here?" ""
    return 0
  fi
  printf '%s' ""
  return 0
}

# _set_attr <attribute> <wanted-value> — apply an operator override.
#   RAISE  -> free, recorded as the operator's own call.
#   LOWER  -> a reason is required, recorded on the delta's row; refused (5) if
#             none can be obtained.
#   Same value -> no-op.
_set_attr() {
  local attr="$1" want="$2" cur why rc rw reason
  case "$attr" in
    risk)     cur="$RISK" ;;
    level)    cur="$LEVEL" ;;
    severity) cur="$SEV" ;;
    *) print_fail "Unknown attribute '$attr'."; return 2 ;;
  esac

  rw="$(_rank "$attr" "$want")"
  if [ "$rw" -lt 0 ]; then
    print_fail "'$want' is not one of the values $attr can take ($(_valid_values "$attr"))."
    return 2
  fi
  if [ "$attr" = "severity" ] && [ "$CLASS" = "feature" ]; then
    print_fail "A feature has no severity — severity belongs to a fix, a hotfix or a security patch."
    return 2
  fi
  [ "$want" = "$cur" ] && return 0

  rc="$(_rank "$attr" "$cur")"
  if [ "$rw" -gt "$rc" ]; then
    why="you raised this yourself — raising is always allowed, because you know things the measurement does not"
  else
    reason="$(_reason_for "$attr")"
    if [ -z "$reason" ]; then
      print_fail "Lowering $attr from $cur to $want removes a check, so it needs a reason on the record."
      print_info "Re-run with --reason \"why this is right here\", or keep $cur."
      return 5
    fi
    why="you lowered this from $cur and recorded: $reason"
    case "$attr" in
      risk)     REASON_RISK="$reason" ;;
      level)    REASON_LEVEL="$reason" ;;
      severity) REASON_SEVERITY="$reason" ;;
    esac
  fi

  case "$attr" in
    risk)     RISK="$want";  RISK_WHY="$why" ;;
    level)    LEVEL="$want"; LEVEL_WHY="$why" ;;
    severity) SEV="$want";   SEV_WHY="$why" ;;
  esac
  return 0
}

# _set_class <class> — changing the class is the ONE question §4.3 asks, so it
# is always free. Severity is re-proposed for the new class, because the old
# proposal was reasoned from the old class (and a feature carries none at all).
_set_class() {
  local want="$1" pair
  case "$want" in
    feature|fix|hotfix|security-patch) : ;;
    *) print_fail "'$want' is not one of the four classes ($(_valid_values class))."; return 2 ;;
  esac
  [ "$want" = "$CLASS" ] && return 0
  CLASS="$want"
  CLASS_WHY="you chose this class yourself"
  pair="$(delta_classify_severity "." "$CLASS" "$DESCRIBE")"
  SEV="$(printf '%s' "$pair" | cut -f1)"
  SEV_WHY="$(printf '%s' "$pair" | cut -f2-)"
  REASON_SEVERITY=""
  return 0
}

# ── The interactive confirm loop (§4.3) ─────────────────────────────────────
_confirm_loop() {
  local choice attr value rc
  while :; do
    _render_transcript
    choice="$(prompt_choice "One question — is this right?" \
      "Keep all four" "Change the class" "Change an attribute")" || return 2
    case "$choice" in
      "Keep all four") return 0 ;;
      "Change the class")
        value="$(prompt_choice "Which class is it?" feature fix hotfix security-patch)" || return 2
        _set_class "$value" || return $?
        ;;
      "Change an attribute")
        attr="$(prompt_choice "Which one?" risk level severity)" || return 2
        case "$attr" in
          risk)     value="$(prompt_choice "Risk:" core feature-local)" || return 2 ;;
          level)    value="$(prompt_choice "Level:" small significant evolution)" || return 2 ;;
          severity) value="$(prompt_choice "Severity:" SEV-1 SEV-2 SEV-3 SEV-4)" || return 2 ;;
        esac
        rc=0; _set_attr "$attr" "$value" || rc=$?
        # A refused LOWER is not fatal in the interactive flow: the operator is
        # right there and can pick again. It IS fatal in a scripted run, which
        # never reaches this loop.
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 5 ]; then return "$rc"; fi
        ;;
    esac
  done
}

# ── Identity (§6.3) ─────────────────────────────────────────────────────────
_next_id() {
  printf '%s\n' "$1" | jq -r '
      [ (.closed[]?.id // empty), (.hotfix_retros[]?.id // empty), (.active_delta.id // empty) ]
    | map(select(type == "string") | select(test("DELTA-[0-9]+")))
    | map(capture("DELTA-(?<n>[0-9]+)") | .n | tonumber)
    | ((max // 0) + 1) as $n
    | "DELTA-" + (if $n < 10 then "00" elif $n < 100 then "0" else "" end) + ($n | tostring)
  ' 2>/dev/null || printf 'DELTA-001\n'
}

_slugify() {
  local s
  s="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//' \
        | cut -c1-40 | sed -e 's/-*$//')"
  [ -n "$s" ] && printf '%s' "$s" || printf '%s' "delta"
}

# ═════════════════════════════════════════════════════════════════════════════
# --status
# ═════════════════════════════════════════════════════════════════════════════
cmd_status() {
  local doc phase
  phase="$(_current_phase)"
  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi
  echo ""
  print_info "Project phase: ${phase:-unknown}"
  if [ "$(printf '%s\n' "$doc" | jq -r '.active_delta == null')" = "true" ]; then
    print_info "No delta is open. Start one with: scripts/delta.sh --open"
    echo ""
    return 0
  fi
  printf '%s\n' "$doc" | jq -r '
    .active_delta as $d
    | "  Open delta:  \($d.id)  (\($d.class))",
      "  What:        \($d.slug)",
      "  Opened:      \($d.opened_at // "unknown")  via \($d.opened_via // "unknown")",
      "  Risk:        \($d.attributes.risk // "unknown")",
      "  Level:       \($d.attributes.level // "unknown")",
      "  Severity:    \($d.attributes.severity // "—")",
      "  Still to do: " + (( ($d.gates_required // []) - ($d.gates_completed // []) ) | join(", ")),
      "  Done:        " + ((($d.gates_completed // []) | join(", ")) | if . == "" then "nothing yet" else . end)
  '
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --open
# ═════════════════════════════════════════════════════════════════════════════
cmd_open() {
  local phase doc active_id pair touched lines gates obj now id slug reasons rc

  command -v jq >/dev/null 2>&1 || { print_fail "jq is required to open a delta."; return 1; }

  # ── REFUSAL 1 — THE ERA INVARIANT (§10.1) ────────────────────────────────
  # `active_delta != null => current_phase == 4`, enforced where it is
  # load-bearing: at open. Equality, not `-ge`: §10.2 fixes current_phase at 4
  # forever (a phase 5 was rejected by decision), so anything else is a project
  # that has not shipped yet.
  phase="$(_current_phase)"
  if [ "$phase" != "4" ]; then                                        # DELTA-OPEN-ERA-GUARD
    echo ""
    print_fail "This project is not finished yet, so there is nothing to maintain."
    print_info "The delta track is for after your product has shipped. This project is at $(_phase_words "$phase")."
    print_info "Finish the build and the launch first — then every later change comes through here."
    echo ""
    return 3
  fi

  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi

  # ── REFUSAL 2 — SECOND ACTIVATION (§7.1, deferred to WP3 by WP2) ─────────
  # One delta at a time. The schema's single `active_delta` slot makes a second
  # open SUCCEED and overwrite — taking the first delta's completed-gate history
  # with it — so the refusal has to live here, in the business layer, and it has
  # to name the delta that is in the way.
  active_id="$(printf '%s\n' "$doc" | jq -r '.active_delta.id // "NONE"' 2>/dev/null || printf 'NONE')"
  if [ "$active_id" != "NONE" ]; then                                 # DELTA-OPEN-ACTIVE-GUARD
    echo ""
    print_fail "You already have one piece of work open: $active_id."
    print_info "$(printf '%s\n' "$doc" | jq -r '"It is a \(.active_delta.class // "delta") — \(.active_delta.slug // "no description recorded")."')"
    print_info "Finish it or close it before starting another. Run: scripts/delta.sh --status"
    echo ""
    return 4
  fi

  if [ -z "$DESCRIBE" ]; then
    if [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${SOIF_NONINTERACTIVE:-}" ]; then
      DESCRIBE="$(prompt_input "In your own words — what needs doing?" "")"
    fi
  fi
  if [ -z "$DESCRIBE" ]; then
    print_fail "Tell me what needs doing: scripts/delta.sh --open --describe \"the CSV export crashes on unicode\""
    return 2
  fi

  # ── §4.2's three derivations, each returning value + provenance ──────────
  pair="$(delta_classify_class "$DESCRIBE")"
  CLASS="$(printf '%s' "$pair" | cut -f1)"
  CLASS_WHY="$(printf '%s' "$pair" | cut -f2-)"

  pair="$(delta_classify_severity "." "$CLASS" "$DESCRIBE")"
  SEV="$(printf '%s' "$pair" | cut -f1)"
  SEV_WHY="$(printf '%s' "$pair" | cut -f2-)"

  touched="$TOUCHED_FILE"
  if [ -z "$touched" ]; then
    touched="$(mktemp)"
    delta_classify_touched "." > "$touched" 2>/dev/null || : > "$touched"
    TOUCHED_TMP="$touched"
  fi
  pair="$(delta_classify_risk "." "$touched")"
  RISK="$(printf '%s' "$pair" | cut -f1)"
  RISK_WHY="$(printf '%s' "$pair" | cut -f2-)"

  lines="$LINES_OVERRIDE"
  [ -n "$lines" ] || lines="$(delta_classify_lines ".")"
  pair="$(delta_classify_level "." "$lines")"
  LEVEL="$(printf '%s' "$pair" | cut -f1)"
  LEVEL_WHY="$(printf '%s' "$pair" | cut -f2-)"

  # ── Command-line overrides, applied BEFORE the transcript is shown, so the
  #    operator confirms what will actually be recorded. Class first: it
  #    re-proposes severity, and an explicit --severity must survive that.
  if [ -n "$WANT_CLASS" ]; then _set_class "$WANT_CLASS" || return $?; fi
  if [ -n "$WANT_RISK" ];  then _set_attr risk "$WANT_RISK" || return $?; fi
  if [ -n "$WANT_LEVEL" ]; then _set_attr level "$WANT_LEVEL" || return $?; fi
  if [ -n "$WANT_SEV" ];   then _set_attr severity "$WANT_SEV" || return $?; fi

  # ── §4.3: confirm, do not quiz ──────────────────────────────────────────
  if [ "$CONFIRMED" -eq 1 ]; then
    _render_transcript
  elif [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${SOIF_NONINTERACTIVE:-}" ]; then
    rc=0; _confirm_loop || rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
  else
    _render_transcript
    print_fail "Nobody is here to confirm this, so nothing was opened."
    print_info "Re-run in a terminal, or add --confirm to accept the four lines above as they stand."
    return 2
  fi

  # The policy file is project-owned from birth, and this is §7.2's "the first
  # delta.sh --open" seeding moment. It goes through the seam like every other
  # write, even though it is birth-once and never overwrites.
  #
  # IT SITS AFTER THE CONFIRMATION, DELIBERATELY. Every refusal above says
  # "nothing was opened", and a refusal that says that while leaving a new file
  # behind is a refusal the operator cannot trust. Seeding earlier costs nothing
  # in derivation accuracy — an absent policy file already resolves every key to
  # the framework default at read time (§3.2), so the transcript the operator
  # just confirmed was computed from exactly the values this seed writes. Pinned
  # by T2: after the no-confirmation refusal the project contains exactly the one
  # file it started with.
  _seam --delta-policy-init >/dev/null 2>&1 || true

  # ── §7.1: gates_required MATERIALISED AT OPEN from class + attributes ────
  if ! gates="$(delta_classify_gates "." "$CLASS" "$RISK" "$LEVEL")"; then
    print_fail "Could not work out which checks this delta needs, so nothing was opened."
    return 1
  fi

  id="$(_next_id "$doc")"
  slug="$SLUG"
  [ -n "$slug" ] || slug="$(_slugify "$DESCRIBE")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  reasons="$(jq -c -n --arg r "$REASON_RISK" --arg l "$REASON_LEVEL" --arg s "$REASON_SEVERITY" '
    { risk: (if $r == "" then null else $r end),
      level: (if $l == "" then null else $l end),
      severity: (if $s == "" then null else $s end) }')"

  # `brief` and `ledger` stay null on purpose: §11-WP8 owns the brief template
  # and the guided intake's ledger-row write. Materialising them here would
  # invent a path to a file nothing creates yet.
  obj="$(jq -c -n \
    --arg id "$id" --arg slug "$slug" --arg class "$CLASS" \
    --arg at "$now" --arg via "guided" \
    --arg risk "$RISK" --arg level "$LEVEL" --arg sev "$SEV" \
    --argjson gates "$gates" --argjson reasons "$reasons" '
    { id: $id, slug: $slug, class: $class,
      brief: null, ledger: null,
      opened_at: $at, opened_via: $via,
      attributes: { risk: $risk, level: $level,
                    severity: (if $sev == "" then null else $sev end) },
      attributes_confirmed_at: $at,
      attribute_reasons: $reasons,
      gates_required: $gates,
      gates_completed: [] }')"

  # THE ONLY WRITE IN THIS FILE, AND IT IS NOT A WRITE — it is a request to the
  # single writer (§7.1/D7). delta.sh never opens the state file.
  if ! _seam --delta-state-update ".active_delta = $obj"; then
    print_fail "The delta record refused the change, so nothing was opened."
    return 1
  fi

  echo ""
  print_ok "Opened $id — $slug ($CLASS)."
  printf '%s\n' "$gates" | jq -r '"  Before this can ship: " + join(", ")'
  print_info "Check where you are at any time with: scripts/delta.sh --status"
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# CLOSE-FLOW HELPERS (§4.2 / §5.3)
# ═════════════════════════════════════════════════════════════════════════════

# _json_str <value> — the value as a JSON string literal, quoting and escaping
# included. Every value this file splices into a jq filter goes through here.
# Some of them originate in `.claude/delta-state.json`, which a human can edit,
# so "it came from our own record" is not the same as "it is safe to paste into
# a program". One helper is cheaper than one audit per splice site.
_json_str() { jq -c -n --arg v "${1:-}" '$v'; }

# _higher <attribute> <a> <b> — whichever of the two ranks HIGHER on that
# attribute's ordering, `a` on a tie or when neither ranks. THE RATCHET, as one
# expression (§4.2: "it never lowers"). An unrecognised value ranks -1, so a
# measurement that could not be taken can only ever lose — which is the
# fail-safe direction here and is what makes the m1 mutant's `measured=""` a
# clean, total neuter rather than a crash.
_higher() {
  local attr="$1" a="$2" b="$3" ra rb
  ra="$(_rank "$attr" "$a")"
  rb="$(_rank "$attr" "$b")"
  if [ "$rb" -gt "$ra" ]; then printf '%s' "$b"; else printf '%s' "$a"; fi
}

# _close_measure <root> <touched-file-list> <changed-lines>
#   `<risk><TAB><level>` measured from the REAL diff at close, using the SAME
#   formulas the open flow used on its forecast (§4.2 is explicit that
#   delta-classify.sh "computes the same way at both moments; it does not know
#   which moment it is in"). The ratchet is applied to these outputs, not here.
_close_measure() {
  local root="${1:-.}" files="${2:-}" lines="${3:-0}" r l
  r="$(delta_classify_risk "$root" "$files" | cut -f1)"
  l="$(delta_classify_level "$root" "$lines" | cut -f1)"
  printf '%s\t%s' "$r" "$l"
}

# _brief_path <delta-id> <recorded-path>
#   Echo the brief's path. rc 0 = found; 1 = none; 2 = AMBIGUOUS (two files
#   claim the same id — the paths are echoed so the operator can see both).
#
#   The recorded path wins when there is one: §11-WP8 owns the guided intake
#   that writes `active_delta.brief`, and a delta that names its own brief is
#   not to be second-guessed by a glob. Until WP8 lands, that field is null and
#   the glob over §6.3's `docs/deltas/DELTA-NNN-slug.md` is the whole answer.
#   Ambiguity is a refusal rather than a first-match: picking one of two briefs
#   silently means the close review ran against a document the operator may not
#   have been looking at.
_brief_path() {
  local id="$1" recorded="${2:-}" hits n
  if [ -n "$recorded" ] && [ "$recorded" != "null" ]; then
    printf '%s' "$recorded"
    return 0
  fi
  [ -d "docs/deltas" ] || return 1
  hits="$(find docs/deltas -maxdepth 1 -type f \( -name "$id-*.md" -o -name "$id.md" \) 2>/dev/null | LC_ALL=C sort)"
  [ -n "$hits" ] || return 1
  n="$(printf '%s\n' "$hits" | grep -c '' || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$hits"
  [ "$n" -eq 1 ] || return 2
  return 0
}

# _rubric_boxes <brief-file>
#   One `checked<TAB>text` or `unchecked<TAB>text` line per criterion in the
#   brief's Done-observable section, in document order. Empty output means the
#   section is absent OR carries no checkboxes — the caller treats both as a
#   refusal, so this function does not need to tell them apart.
#
#   THE CONTRACT IS SPELLED OUT IN THIS FILE'S HEADER and WP8's
#   `delta-brief.tmpl` must match it. The two decisions worth restating at the
#   code: the section ends at the next heading of the same depth or SHALLOWER
#   (so a `###` sub-list is still rubric), and a bracket holding anything other
#   than `x`/`X` counts as NOT checked. A permissive reading of an undefined
#   marker is how a rubric quietly stops being one.
_rubric_boxes() {
  local f="$1"
  [ -f "$f" ] || return 1
  awk '
    function hashes(s,   n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^#+[ \t]/) {
        d = hashes(line)
        rest = substr(line, d + 1)
        sub(/^[ \t]+/, "", rest)
        if (tolower(rest) ~ /^done-observable/) { insec = 1; depth = d; next }
        if (insec == 1 && d <= depth) { insec = 0 }
        next
      }
      if (insec != 1) next
      if (line ~ /^[-*+][ \t]+\[.\]/) {
        mark = substr(line, index(line, "[") + 1, 1)
        text = substr(line, index(line, "]") + 1)
        sub(/^[ \t]+/, "", text)
        sub(/[ \t]+$/, "", text)
        if (mark == "x" || mark == "X") printf "checked\t%s\n", text
        else printf "unchecked\t%s\n", text
      }
    }
  ' "$f" 2>/dev/null
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --complete-gate
# ═════════════════════════════════════════════════════════════════════════════
cmd_complete_gate() {
  local doc id token gates_req present already

  token="$GATE_TOKEN"
  command -v jq >/dev/null 2>&1 || { print_fail "jq is required to record a check."; return 1; }
  if [ -z "$token" ]; then
    print_fail "Name the check you finished: scripts/delta.sh --complete-gate ledger_row"
    return 2
  fi

  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi
  if [ "$(printf '%s\n' "$doc" | jq -r '.active_delta == null')" = "true" ]; then
    echo ""
    print_fail "There is nothing open, so there is no check to record against."
    print_info "Start a piece of work with: scripts/delta.sh --open"
    echo ""
    return 6
  fi

  id="$(printf '%s\n' "$doc" | jq -r '.active_delta.id // "unknown"')"
  gates_req="$(printf '%s\n' "$doc" | jq -c '.active_delta.gates_required // []')"

  # A token this delta does not owe is an INVOCATION error, not a config one:
  # the vocabulary may well know the word, this delta simply is not carrying it.
  present=n
  if printf '%s\n' "$gates_req" | jq -r '.[]? | select(type == "string")' | grep -qxF "$token"; then
    present=y
  fi
  if [ "$present" = n ]; then
    echo ""
    print_fail "$id does not need '$token'."
    printf '%s\n' "$gates_req" | jq -r '"  What it does need: " + join(", ")'
    echo ""
    return 2
  fi

  # Idempotent by design. Re-recording is the most likely repeat invocation
  # there is, and making it an error would teach the operator to fear the tool.
  already=n
  if printf '%s\n' "$doc" | jq -r '.active_delta.gates_completed[]? | select(type == "string")' | grep -qxF "$token"; then
    already=y
  fi
  if [ "$already" = y ]; then
    print_ok "$token was already recorded for $id — nothing to do."
    return 0
  fi

  if ! _seam --delta-state-update ".active_delta.gates_completed += [$(_json_str "$token")]"; then
    print_fail "The delta record refused the change, so nothing was recorded."
    return 1
  fi

  echo ""
  print_ok "Recorded: $token is done for $id."
  # §5.3's honest tiering, in the operator's own words. Do not widen this.
  print_info "This is your word for it — the record now says you did it, and nothing here re-checks it."
  print_info "The two things this tool does check for itself are the tick-boxes in your brief and how big the change actually turned out to be, both when you close."
  print_info "See where you are with: scripts/delta.sh --status"
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --close
# ═════════════════════════════════════════════════════════════════════════════
cmd_close() {
  local doc id class sev risk level recorded gates_req gates_done
  local vocab unknown g outstanding
  local touched lines measured mrisk mlevel nrisk nlevel
  local newgates appended n_appended now row filter
  local brief brc boxes unchecked

  command -v jq >/dev/null 2>&1 || { print_fail "jq is required to close a delta."; return 1; }

  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi

  # ── REFUSAL 1 — NOTHING IS OPEN ──────────────────────────────────────────
  if [ "$(printf '%s\n' "$doc" | jq -r '.active_delta == null')" = "true" ]; then
    echo ""
    print_fail "There is nothing open to close."
    print_info "Start a piece of work with: scripts/delta.sh --open"
    echo ""
    return 6
  fi

  id="$(printf '%s\n' "$doc" | jq -r '.active_delta.id // "unknown"')"
  class="$(printf '%s\n' "$doc" | jq -r '.active_delta.class // ""')"
  sev="$(printf '%s\n' "$doc" | jq -r '.active_delta.attributes.severity // ""')"
  risk="$(printf '%s\n' "$doc" | jq -r '.active_delta.attributes.risk // ""')"
  level="$(printf '%s\n' "$doc" | jq -r '.active_delta.attributes.level // ""')"
  recorded="$(printf '%s\n' "$doc" | jq -r '.active_delta.brief // ""')"
  gates_req="$(printf '%s\n' "$doc" | jq -c '.active_delta.gates_required // []')"
  gates_done="$(printf '%s\n' "$doc" | jq -c '.active_delta.gates_completed // []')"

  # ── REFUSAL 2 — AN UNKNOWN GATE TOKEN, FAILING CLOSED ────────────────────
  # FIRST among the substantive checks, deliberately: if a token is meaningless
  # then "outstanding" and "complete" are both meaningless too, so every answer
  # downstream of it is untrustworthy. It also means this refusal is reached
  # before the ratchet, which is what keeps its residue at zero.
  vocab="$(delta_classify_gate_vocabulary ".")"
  unknown=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    if printf '%s\n' "$vocab" | grep -qxF "$g"; then continue; fi
    unknown="$unknown $g"
  done <<EOF
$(printf '%s\n' "$gates_req" | jq -r '.[]? | select(type == "string")')
EOF
  if [ -n "$unknown" ]; then                                          # DELTA-CLOSE-VOCAB-GUARD
    echo ""
    print_fail "This piece of work lists a check nothing here recognises:$unknown."
    print_info "That is not something you can finish — nothing in the project knows what would satisfy it, so it would block you forever."
    print_info "It is almost always a typo. Fix the spelling in .claude/delta-policy.json and re-open, or correct the delta's own record. Nothing was closed."
    echo ""
    return 9
  fi

  # ── THE CLOSE-TIME RE-DERIVATION AND ITS RATCHET (§4.2) ──────────────────
  # The open-time values were a FORECAST measured against an empty diff. This is
  # the measurement. A higher bracket raises the attribute and appends whatever
  # gates that raise toggles on; a lower one changes nothing at all.
  touched="$TOUCHED_FILE"
  if [ -z "$touched" ]; then
    touched="$(mktemp)"
    TOUCHED_TMP="$touched"
    delta_classify_touched "." > "$touched" 2>/dev/null || : > "$touched"
  fi
  lines="$LINES_OVERRIDE"
  [ -n "$lines" ] || lines="$(delta_classify_lines ".")"

  measured="$(_close_measure "." "$touched" "$lines")"                # DELTA-CLOSE-RATCHET
  mrisk="$(printf '%s' "$measured" | cut -f1)"
  mlevel="$(printf '%s' "$measured" | cut -f2)"
  nrisk="$(_higher risk "$risk" "$mrisk")"
  nlevel="$(_higher level "$level" "$mlevel")"

  if [ "$nrisk" != "$risk" ] || [ "$nlevel" != "$level" ]; then
    if ! newgates="$(delta_classify_gates "." "$class" "$nrisk" "$nlevel")"; then
      print_fail "Could not work out what the bigger change needs, so nothing was closed."
      return 1
    fi
    # APPEND-ONLY, never recompute-and-replace (§7.1): a policy edit mid-delta
    # must not be able to drop a gate the operator was already told about, so
    # the recomputed set contributes only what is NEW.
    if ! appended="$(jq -c -n --argjson have "$gates_req" --argjson want "$newgates" \
        '[ $want[] | . as $g | select(($have | index($g)) == null) ]')"; then
      print_fail "Could not work out what the bigger change needs, so nothing was closed."
      return 1
    fi
    n_appended="$(printf '%s' "$appended" | jq -r 'length' 2>/dev/null)" || n_appended=0
    case "$n_appended" in ''|*[!0-9]*) n_appended=0 ;; esac
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! _seam --delta-state-update \
        ".active_delta.attributes.risk = $(_json_str "$nrisk") \
       | .active_delta.attributes.level = $(_json_str "$nlevel") \
       | .active_delta.gates_required = (.active_delta.gates_required + $appended) \
       | .active_delta.ratcheted_at = $(_json_str "$now")"; then
      print_fail "The delta record refused the re-measurement, so nothing was closed."
      return 1
    fi

    # ANNOUNCE THE RAISE — ALWAYS, INCLUDING WHEN NO GATE WAS TOGGLED.
    # This sits ABOVE the `n_appended` branch on purpose. The write above
    # happens whenever an attribute rose; the rc-10 refusal below happens only
    # when a gate was ALSO appended. Those two conditions are not the same, and
    # an adversarial review found the gap by execution: a raise that toggles
    # nothing (small -> significant, which no toggle answers; or risk -> core on
    # a class that already carries brief_review) rewrote the operator's recorded
    # attributes and then returned 7 or 8 without a word about it. The record
    # changing under someone who was never told is the half of that defect that
    # is not about doctrine, and this is the whole fix for it. Pinned by N3/N4.
    echo ""
    print_info "Re-measured from what you actually changed:"
    if [ "$nrisk" != "$risk" ];   then print_info "  how risky:  $risk -> $nrisk"; fi
    if [ "$nlevel" != "$level" ]; then print_info "  how big:    $level -> $nlevel"; fi
    print_info "That is on the record now. It only ever goes up — a smaller change later never talks it back down."

    gates_req="$(printf '%s\n' "$gates_req" | jq -c ". + $appended")"
    risk="$nrisk"
    level="$nlevel"

    if [ "$n_appended" -gt 0 ]; then
      echo ""
      print_fail "This turned out to be a bigger change than it looked when you started, so it needs more checking before it can close."
      printf '%s\n' "$appended" | jq -r '"  Now also needed: " + join(", ")'
      print_info "That is measured from what you actually changed, not from what you said at the start — and it only ever goes up."
      print_info "Do those, mark them done with --complete-gate, then close again."
      echo ""
      return 10
    fi
  fi

  # ── REFUSAL 3 — REQUIRED GATES STILL OUTSTANDING (§5.2) ──────────────────
  if ! outstanding="$(jq -r -n --argjson req "$gates_req" --argjson done "$gates_done" \
      '[ $req[] | . as $g | select(($done | index($g)) == null) ] | join(", ")')"; then
    print_fail "Could not work out what is left to do, so nothing was closed."
    return 1
  fi
  if [ -n "$outstanding" ]; then                                      # DELTA-CLOSE-GATES-GUARD
    echo ""
    print_fail "$id is not finished yet."
    print_info "Still to do: $outstanding"
    print_info "Mark one done with: scripts/delta.sh --complete-gate <name>"
    echo ""
    return 7
  fi

  # ── REFUSAL 4 — THE RUBRIC BIND (§5.3) ───────────────────────────────────
  # Keyed on the GATE, not on the class: a fix that grew past the evolution
  # threshold gains `brief` at the ratchet above and gains this check with it.
  if printf '%s\n' "$gates_req" | jq -e 'index("brief") != null' >/dev/null 2>&1; then
    brc=0
    brief="$(_brief_path "$id" "$recorded")" || brc=$?
    if [ "$brc" -eq 2 ]; then
      echo ""
      print_fail "More than one write-up claims to be $id's, so it is not clear which one to check against."
      printf '%s\n' "$brief" | sed -e 's/^/  /'
      print_info "Keep one and rename or remove the other. Nothing was closed."
      echo ""
      return 8
    fi
    if [ "$brc" -ne 0 ] || [ -z "$brief" ] || [ ! -f "$brief" ]; then
      echo ""
      print_fail "$id needs a written-up plan and there isn't one to check against."
      print_info "It should be at docs/deltas/$id-<short-name>.md, with a '## Done-observable' section listing what has to be true when this is finished."
      print_info "Nothing was closed."
      echo ""
      return 8
    fi
    boxes="$(_rubric_boxes "$brief")" || boxes=""
    if [ -z "$boxes" ]; then
      echo ""
      print_fail "$brief has no list of things that have to be true when this is done, so there is nothing to check it against."
      print_info "Add a '## Done-observable' section with one '- [ ] …' line per thing you will be able to see working."
      print_info "An empty list would let this close on nothing at all, so it is refused rather than passed. Nothing was closed."
      echo ""
      return 8
    fi
    unchecked="$(printf '%s\n' "$boxes" | awk -F'\t' '$1 == "unchecked" { print "  - " $2 }')"
    if [ -n "$unchecked" ]; then                                      # DELTA-CLOSE-RUBRIC-GUARD
      echo ""
      print_fail "You wrote down what would be true when $id is done, and some of it is not ticked off yet."
      printf '%s\n' "$unchecked"
      print_info "That list is in $brief, and it is the whole review — you wrote it before you were invested in how you built this."
      print_info "Finish those, tick them, then close. Nothing was closed."
      echo ""
      return 8
    fi
  fi

  # ── THE CLOSE WRITE — ONE SEAM CALL, ONE ATOMIC RENAME ───────────────────
  # "ONE" IS A CLAIM ABOUT THIS WRITE, NOT ABOUT THE INVOCATION. A close that
  # was preceded by a silent raise performs TWO seam writes: the ratchet record
  # above, then this one. That is fine and is not what the property is about —
  # the load-bearing guarantee is that the `closed` APPEND and the slot NULL are
  # a single filter and therefore a single atomic rename, so no crash can land
  # between them. m3 kills the split; W1/W2 pin the result.
  # THE `closed` APPEND AND THE SLOT NULL ARE ONE FILTER, and that is not
  # tidiness. `_next_id` reads ids out of closed[] + hotfix_retros[] +
  # active_delta, so a close that empties the slot without appending ERASES the
  # id from the record and the very next open is handed it again — two pieces of
  # work sharing one identifier in the audit tail, with nothing anywhere that
  # would notice. Splitting this into two seam calls would additionally make the
  # window between them a crash away from exactly that state.
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! row="$(jq -c -n --arg id "$id" --arg class "$class" --arg sev "$sev" \
      --arg at "$now" --arg risk "$risk" --arg level "$level" --argjson done "$gates_done" '
      ($sev | if . == "" then null else . end) as $s
      | { id: $id, class: $class, severity: $s,
          closed_at: $at, shipped_in: null,
          attributes: { risk: $risk, level: $level, severity: $s },
          gates_completed: $done }')"; then
    print_fail "Could not write up the finished record, so nothing was closed."
    return 1
  fi

  filter=".closed += [$row] | .active_delta = null"                   # DELTA-CLOSE-ATOMIC-WRITE
  if ! _seam --delta-state-update "$filter"; then
    print_fail "The delta record refused the change, so nothing was closed."
    return 1
  fi

  echo ""
  print_ok "Closed $id ($class)."
  print_info "It is on the record with everything you ticked off, and it will be listed in the next release you cut."
  print_info "Start the next one with: scripts/delta.sh --open"
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# Argument parsing
# ═════════════════════════════════════════════════════════════════════════════
ACTION=""
DESCRIBE=""
SLUG=""
CONFIRMED=0
WANT_CLASS=""
WANT_RISK=""
WANT_LEVEL=""
WANT_SEV=""
REASON=""
TOUCHED_FILE=""
TOUCHED_TMP=""
LINES_OVERRIDE=""
GATE_TOKEN=""

CLASS=""; CLASS_WHY=""
SEV="";   SEV_WHY=""
RISK="";  RISK_WHY=""
LEVEL=""; LEVEL_WHY=""
REASON_RISK=""; REASON_LEVEL=""; REASON_SEVERITY=""

_need() {
  if [ "$2" -lt 2 ]; then
    echo "delta: $1 needs a value." >&2
    echo "$USAGE" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --open)     ACTION="open"; shift ;;
    --close)    ACTION="close"; shift ;;
    --complete-gate) _need "$1" $#; ACTION="complete-gate"; GATE_TOKEN="$2"; shift 2 ;;
    --status)   ACTION="status"; shift ;;
    --describe) _need "$1" $#; DESCRIBE="$2"; shift 2 ;;
    --slug)     _need "$1" $#; SLUG="$2"; shift 2 ;;
    --class)    _need "$1" $#; WANT_CLASS="$2"; shift 2 ;;
    --risk)     _need "$1" $#; WANT_RISK="$2"; shift 2 ;;
    --level)    _need "$1" $#; WANT_LEVEL="$2"; shift 2 ;;
    --severity) _need "$1" $#; WANT_SEV="$2"; shift 2 ;;
    --reason)   _need "$1" $#; REASON="$2"; shift 2 ;;
    # An explicit touched-file list and an explicit line count exist so the
    # derivations can be exercised against a KNOWN input. At open the real diff
    # is usually empty (§4.2's forecast), so a test that relied on the ambient
    # git state would be pinning the host, not the formula. BOTH FLOWS honour
    # them — `--close` re-measures with the same two functions, so the same
    # override is the same override there. The WP4 ratchet cases deliberately do
    # NOT use them: the design's own mutation is about a REAL diff crossing a
    # bracket, and feeding that measurement by hand would prove the arithmetic
    # while assuming away the thing being measured.
    --touched-file) _need "$1" $#; TOUCHED_FILE="$2"; shift 2 ;;
    --lines)        _need "$1" $#; LINES_OVERRIDE="$2"; shift 2 ;;
    --confirm)  CONFIRMED=1; shift ;;
    -h|--help)  echo "$USAGE"; exit 0 ;;
    *) echo "delta: unknown option '$1'." >&2; echo "$USAGE" >&2; exit 2 ;;
  esac
done

_cleanup() { [ -n "$TOUCHED_TMP" ] && rm -f "$TOUCHED_TMP" 2>/dev/null; return 0; }
trap _cleanup EXIT

RC=0
case "$ACTION" in
  open)          cmd_open          || RC=$? ;;
  close)         cmd_close         || RC=$? ;;
  complete-gate) cmd_complete_gate || RC=$? ;;
  status)        cmd_status        || RC=$? ;;
  *)             echo "$USAGE" >&2; RC=2 ;;
esac
exit "$RC"

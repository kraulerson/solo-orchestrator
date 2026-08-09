#!/usr/bin/env bash
# scripts/lib/adopt/adopt-core.sh — the driver's own primitives: how it talks,
# how it asks, how it refuses, and how it remembers what it wrote.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.3 (the three
# section classes and what "no default, no skip" has to mean in code), §8.5
# (explicit staging — which is why every write is RECORDED here), §5.5 (a run
# that does not complete must leave a SAFE state), §4.1 (the operator-facing
# register: this is written for a non-developer).
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS FILE DOES NOT USE prompt_input / prompt_yes_no FROM helpers-core.sh
#
# Measured, not assumed: both of those return a DEFAULT (and prompt_yes_no a
# hard "N") the moment stdin is not a terminal, printing a [WARN] and NOT
# blocking. That behaviour is right for the greenfield installer, where an
# unattended run should proceed with sane defaults. It is exactly wrong here:
# §8.3's judgment sections are "human-mandatory, no prefill, no default, no
# skip", and data classification is "non-skippable in BOTH scenarios". A
# primitive whose unattended answer is a default cannot express either rule.
#
# So the driver reads answers itself, line by line, from stdin — which works
# identically for a person at a terminal and for a scripted run — and an
# UNANSWERED mandatory question STOPS THE ADOPTION. Stopping is safe (§5.5);
# answering on the operator's behalf is not.
#
# prompt_choice IS usable (it reads stdin unconditionally) but it loops up to
# 100 times on invalid input and returns the option TEXT on stdout mixed with
# prompts on stderr. The driver wants a single refusal on a bad answer and one
# transcript on stdout that a test can pin verbatim, so it has its own.
#
# bash-3.2 safe: no associative arrays, no ${var,,}, no `((x++))`.

# adopt_module_version — the driver's own version marker. A literal, for the
# same reason Scout's is: at adoption time there may be no framework state to
# read a version out of. The `-wp4` suffix is information, not decoration —
# this build carries the skeleton, the chooser, placement and reverse intake,
# and HONEST STUBS where WP5/WP5b/WP6/WP7 will land.
adopt_module_version() {
  printf '%s\n' "0.1.0-wp4"
}

# ── Output. One transcript, on stdout, so a test can pin it. ────────────────
adopt_say()  { printf '%s\n' "$1"; }
adopt_head() { printf '\n══ %s\n' "$1"; }
adopt_note() { printf '   %s\n' "$1"; }
adopt_blank() { printf '\n'; }

# ── Refusal ─────────────────────────────────────────────────────────────────
# THE ONLY WAY THIS DRIVER DECLINES TO CONTINUE. It prints WHY on stderr and
# returns 1; every caller propagates. §5.5: "adoption does not complete" is a
# real state and it must be a safe one — refusing before or between writes
# leaves the project in the §8.4 safe row, never the unsafe one.
ADOPT_REFUSED_REASON=""
adopt_refuse() {
  ADOPT_REFUSED_REASON="$1"
  printf '\n[REFUSED] %s\n' "$1" >&2
  printf '          Adoption did not complete. Nothing has been committed.\n' >&2
  return 1
}

# The mandatory-question refusal, spelled ONCE so the transcript is consistent
# and a test has one string to look for.
ADOPT_MANDATORY_REFUSAL="This question has no default and no skip, and no answer was given:"

# ── Reading one answer ──────────────────────────────────────────────────────
# ADOPT_ANSWER is the single out-parameter. bash 3.2 has no namerefs and the
# alternative — echoing the answer and capturing it in $(...) — would put the
# QUESTION inside the capture too, or force every prompt onto stderr where the
# verbatim-wording pin could not see it as one transcript.
ADOPT_ANSWER=""

# THE OPERATOR'S STDIN IS PINNED TO FD 3, AND IT HAS TO BE.
#
# The reverse-intake runner walks Scout's rows with `while read … done <<ROWS`,
# which redirects the WHOLE LOOP BODY's stdin to the row list. A question asked
# inside that body and reading plain stdin therefore eats the NEXT TABLE ROW as
# if the operator had typed it — measured, not hypothetical: the first run of
# this driver answered "Keep 'acme-api'?" with a tab-separated prefill row and
# refused. Duplicating the real stdin to fd 3 once, at the top of the run, and
# reading every answer from there makes the questions independent of whatever
# redirection the surrounding loop needs.
#
# AND THE REDIRECTION MUST NOT CARRY A `2>/dev/null`. `exec` with no command
# applies its redirections to the SHELL ITSELF and keeps them: the first cut
# read `exec 3<&0 2>/dev/null`, which duplicated stdin correctly and then sent
# every subsequent byte of stderr to /dev/null for the rest of the run. Three
# refusal cases went silent — the driver still exited non-zero, so it "worked",
# and only a `bash -x` trace that stopped mid-function showed why. A failing
# `exec` here is loud on purpose; there is nothing to suppress.
ADOPT_STDIN_FD=0
adopt_stdin_init() {
  exec 3<&0 || return 0
  ADOPT_STDIN_FD=3
  return 0
}

# _adopt_read_line — one trimmed line of the OPERATOR's input into ADOPT_ANSWER.
# rc 1 on EOF, with ADOPT_ANSWER emptied. EOF and a blank line are treated
# identically ON PURPOSE: "the operator walked away" and "the script ran out of
# answers" are the same event from the driver's point of view, and both must
# reach the mandatory guard rather than a default.
_adopt_read_line() {
  local line=""
  ADOPT_ANSWER=""
  if [ "$ADOPT_STDIN_FD" = "3" ]; then
    IFS= read -r line <&3 || { ADOPT_ANSWER=""; return 1; }
  else
    IFS= read -r line || { ADOPT_ANSWER=""; return 1; }
  fi
  ADOPT_ANSWER="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  return 0
}

# adopt_read_optional — read one answer that is ALLOWED to be empty.
# Nothing in §8.3 is optional; this exists so that the non-skippability of a
# question is expressed as its OWN guard at the question's own site, where it
# can be read, reviewed and mutated, instead of being an emergent property of a
# shared reader. See BF-ADOPT-DC-MANDATORY in adopt-intake.sh.
adopt_read_optional() {
  _adopt_read_line || true
  return 0
}

# adopt_offer_choice QUESTION OPT... — print a question and its options and
# nothing else. NO option is marked, preselected, recommended or defaulted:
# §4.2 rejects presenting a guess as a default, because that makes the most
# consequential answer the easiest one to skim past.
adopt_offer_choice() {
  local question="$1"; shift
  local opt i=1
  adopt_say "$question"
  for opt in "$@"; do
    printf '   %s) %s\n' "$i" "$opt"
    i=$((i + 1))
  done
  printf '   Answer with the number or the words: '
}

# adopt_resolve_choice RAW OPT... — map a raw answer onto one of the options.
# Accepts the 1-based number or the option text (case-insensitively, because a
# person typing "Keep It" meant "keep it"). EMPTY IN, EMPTY OUT — resolving is
# not validating, and the "was this answered at all?" question belongs to the
# caller's own guard.
adopt_resolve_choice() {
  local raw="$1"; shift
  local opt n=0 lower raw_lower
  [ -n "$raw" ] || { printf '%s' ""; return 0; }
  for opt in "$@"; do n=$((n + 1)); done
  case "$raw" in
    ''|*[!0-9]*) : ;;
    *)
      if [ "$raw" -ge 1 ] && [ "$raw" -le "$n" ]; then
        n=0
        for opt in "$@"; do
          n=$((n + 1))
          [ "$n" -eq "$raw" ] && { printf '%s' "$opt"; return 0; }
        done
      fi
      ;;
  esac
  raw_lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  for opt in "$@"; do
    lower="$(printf '%s' "$opt" | tr '[:upper:]' '[:lower:]')"
    [ "$raw_lower" = "$lower" ] && { printf '%s' "$opt"; return 0; }
  done
  printf '%s' ""
  return 0
}

# adopt_ask_choice LABEL QUESTION OPT... — offer, read, resolve, and REFUSE on
# anything that is not one of the offered answers (including nothing at all).
# Leaves the chosen option in ADOPT_ANSWER.
adopt_ask_choice() {
  local label="$1" question="$2"; shift 2
  local raw resolved
  adopt_offer_choice "$question" "$@"
  adopt_read_optional
  raw="$ADOPT_ANSWER"
  resolved="$(adopt_resolve_choice "$raw" "$@")"
  printf '\n'
  if [ -z "$resolved" ]; then
    if [ -z "$raw" ]; then
      adopt_refuse "$ADOPT_MANDATORY_REFUSAL $label"
      return 1
    fi
    adopt_refuse "'$raw' is not one of the answers offered for: $label"
    return 1
  fi
  ADOPT_ANSWER="$resolved"
  return 0
}

# adopt_ask_free LABEL QUESTION — a free-text answer that MUST be given.
# §8.3's judgment class in one function: no prefill, no default, no skip.
adopt_ask_free() {
  local label="$1" question="$2"
  adopt_say "$question"
  printf '   Your answer: '
  adopt_read_optional
  printf '\n'
  if [ -z "$ADOPT_ANSWER" ]; then
    adopt_refuse "$ADOPT_MANDATORY_REFUSAL $label"   # BF-ADOPT-JUDGMENT-MANDATORY
    return 1
  fi
  return 0
}

# ── Remembering what was written (§8.5's explicit staging) ──────────────────
# EVERY path the driver creates or modifies is recorded HERE, at the moment it
# is written, relative to the adoptee root. The staging array is built from
# this ledger and from nothing else, so "anything not in it is never staged" is
# a property of the code rather than a promise in a comment. The counter-example
# the design names is create_project()'s `git add -A` followed by
# `git commit --no-verify`, which on an adoptee would sweep their uncommitted
# work into a framework commit with verification bypassed.
ADOPT_WRITTEN_LEDGER=""

adopt_ledger_init() {
  ADOPT_WRITTEN_LEDGER="$1"
  : > "$ADOPT_WRITTEN_LEDGER" || return 1
  return 0
}

# adopt_record_write RELPATH — one ledger row. Deduplicated at read time.
adopt_record_write() {
  [ -n "$ADOPT_WRITTEN_LEDGER" ] || return 0
  printf '%s\n' "$1" >> "$ADOPT_WRITTEN_LEDGER"
}

# adopt_written_paths — the ledger, deduplicated, one path per line.
adopt_written_paths() {
  [ -n "$ADOPT_WRITTEN_LEDGER" ] || return 0
  [ -f "$ADOPT_WRITTEN_LEDGER" ] || return 0
  sort -u "$ADOPT_WRITTEN_LEDGER"
}

# ── Writes ──────────────────────────────────────────────────────────────────
# adopt_write_file ROOT RELPATH — copy stdin into ROOT/RELPATH, creating
# parents, and record it. Refuses loudly on any failure; with errexit off, an
# unchecked redirect is exactly how a writer loses half its output in silence.
adopt_write_file() {
  local root="$1" rel="$2" dir
  dir="$(dirname "$root/$rel")"
  mkdir -p "$dir" 2>/dev/null || { adopt_refuse "could not create $dir"; return 1; }
  cat > "$root/$rel" || { adopt_refuse "could not write $rel"; return 1; }
  adopt_record_write "$rel"
  return 0
}

# adopt_jq_edit ROOT RELPATH FILTER [jq args...] — an in-place jq edit through
# the atomic-rename pattern the framework's other manifest writers use.
adopt_jq_edit() {
  local root="$1" rel="$2" filter="$3"; shift 3
  local f="$root/$rel"
  [ -f "$f" ] || { adopt_refuse "cannot edit $rel — it does not exist"; return 1; }
  command -v jq >/dev/null 2>&1 || { adopt_refuse "jq is required to adopt a project"; return 1; }
  jq "$@" "$filter" "$f" > "$f.tmp" 2>/dev/null || { rm -f "$f.tmp"; adopt_refuse "jq could not edit $rel"; return 1; }
  mv "$f.tmp" "$f" || { adopt_refuse "could not replace $rel"; return 1; }
  adopt_record_write "$rel"
  return 0
}

# ── Small shared readers ────────────────────────────────────────────────────
# adopt_report_read FILE FILTER — one jq -r read of the Scout report. Empty on
# any failure, because a missing section is data, not a crash.
adopt_report_read() {
  jq -r "$2" "$1" 2>/dev/null
}

# adopt_int VALUE — a shell-comparable integer. jq prints a missing field as
# the four-character string "null", which `[ "$x" -ge 1 ]` rejects with a
# diagnostic AND a false branch, so a missing number would otherwise take the
# same path as a zero.
adopt_int() {
  case "$1" in ''|null|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac
}

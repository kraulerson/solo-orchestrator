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
# EXIT CODES — CODES, NEVER LABELS
#   0  the delta was opened, or `--status` reported successfully
#   1  an operation failed (the seam refused a write, jq is missing, …)
#   2  invocation error: bad flag, missing argument, or a confirmation that
#      could not be obtained (no terminal and no `--confirm`)
#   3  ERA REFUSAL — the project is not at phase 4          (§10.1)
#   4  SECOND-ACTIVATION REFUSAL — a delta is already open  (§7.1)
#   5  an attribute was LOWERED with no reason recorded     (§4.2)
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
  scripts/delta.sh --status
  scripts/delta.sh --help"

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

  # The policy file is project-owned from birth. Seeding it here is the §7.2
  # "the first delta.sh --open" moment — and it goes through the seam like every
  # other write, even though this one is birth-once and never overwrites.
  _seam --delta-policy-init >/dev/null 2>&1 || true

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
    # git state would be pinning the host, not the formula.
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
  open)   cmd_open   || RC=$? ;;
  status) cmd_status || RC=$? ;;
  *)      echo "$USAGE" >&2; RC=2 ;;
esac
exit "$RC"

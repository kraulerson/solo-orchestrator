#!/usr/bin/env bash
# scripts/lib/adopt/adopt-intake.sh — REVERSE INTAKE (§8.3).
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.3 (the three
# section classes and their precedents), §4.3 (S1 is light on futures and heavy
# on operations), §4.5 (data classification is non-skippable in BOTH
# scenarios), §8.2 (`intakePrefill` — the mapping table, which WP2 already
# authored as a data block in scripts/lib/scout/scout-prefill.sh and which this
# file CONSUMES rather than re-authors).
#
# ─────────────────────────────────────────────────────────────────────────────
# The ordinary intake asks a person and writes a document. REVERSE INTAKE
# starts from the document the scanner already derived and asks the person to
# CONFIRM it — for the parts that are derivable, and only those.
#
#   scan-derived    Prefilled and confirmed: TWO disclosure lines naming the
#                   value AND ITS PROVENANCE, then keep-it / change-it, with
#                   "change it" falling through to the ordinary question.
#   judgment        Human-mandatory. No prefill, no default, no skip.
#   non-skippable   Data classification. No default, no inference, and NO
#                   "confirm" arm at all.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE SHAPE OF THE PREFILL READ IS LOAD-BEARING, AND §8.3 SAYS SO IN ADVANCE.
#
# The shipped pattern is `run_section_1_repo_setup()` in scripts/intake-wizard.sh
# (marker `# BL-204-PREFILL-READ`). Two properties of it are not style:
#
#   1. the marked read carries an END-OF-LINE-ANCHORED marker, so a mutation
#      test can excise exactly that line with `s|^.*MARKER$|...|`; and
#   2. a bare `:` sits on the line ABOVE it, so the enclosing `if` block stays
#      syntactically well-formed once the read is excised.
#
# That `:` is not dead code and tidying it away removes the test's ability to
# bite. The copy below preserves both properties under its own marker,
# `# BF-ADOPT-PREFILL-READ`, for exactly the same reason.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY DATA CLASSIFICATION GETS ITS OWN GUARD RATHER THAN RIDING THE SHARED ONE.
#
# It is a MECHANICAL necessity, not a policy preference: scripts/check-phase-gate.sh's
# Phase 1->2 ZDR backstop is a hard `[FAIL]` (an `issues` increment, which is
# what a block actually is in that script) whenever `current_phase >= 2` and
# `.claude/process-state.json::phase1_artifacts.data_classification` is not one
# of {public, internal, confidential, pii, financial, health, regulated} — plus
# an attestation for anything above `public`. An S1 adoption lands at 4, i.e.
# above that threshold on its FIRST commit. So the non-skippability is given
# its own single-site guard, at the question's own site, where it can be read,
# reviewed, and neutered by one line in a mutation proof.

# The taxonomy, spelled exactly as the gate spells it. Order is the gate's.
ADOPT_DC_TAXONOMY="public internal confidential pii financial health regulated"

ADOPT_DC_REFUSAL="Data classification has no default, no guess and no skip — in either scenario. The Phase 1 to 2 gate is a hard FAIL without it, so an adoption that skipped it would produce a project that cannot pass its own next gate."

# ── The answers ledger ──────────────────────────────────────────────────────
# `<field>\t<title>\t<kind>\t<value>\t<provenance>`, one row per answer, in the
# order asked. The intake artifacts are rendered from this and nothing else.
ADOPT_ANSWERS=""
ADOPT_DATA_CLASSIFICATION=""
ADOPT_ZDR_ATTESTED="false"
ADOPT_ZDR_REASON=""

adopt_answers_init() {
  ADOPT_ANSWERS="$1"
  : > "$ADOPT_ANSWERS" || return 1
  return 0
}

# adopt_record_answer FIELD TITLE KIND VALUE PROVENANCE
# Tabs and newlines are stripped from the value: the ledger is TSV, and an
# answer that re-opened a column would silently shift every later field.
adopt_record_answer() {
  local field="$1" title="$2" kind="$3" value="$4" prov="$5"
  value="$(printf '%s' "$value" | tr '\t\n' '  ')"
  prov="$(printf '%s' "$prov" | tr '\t\n' '  ')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$field" "$title" "$kind" "$value" "$prov" >> "$ADOPT_ANSWERS"
}

# ── The question text for the judgment rows ─────────────────────────────────
# One case arm per intake section. §4.3 makes S1 LIGHT ON FUTURES: there is no
# MVP cutline to draw for something already shipped, so section 4 asks for a
# record of what exists instead of a cutline. Everything else is asked of both.
adopt_judgment_question() {
  local id="$1" scenario="$2"
  case "$id" in
    2)  printf '%s' "What problem does this project solve, and for whom? Say it concretely." ;;
    3)  printf '%s' "What constrains this work — time, money, people, anything you cannot change?" ;;
    4)  if [ "$scenario" = "completed" ]; then
          printf '%s' "What does this project actually do today? List the main things it does, as they are — not as you wish they were."
        else
          printf '%s' "What is in the first version you would call finished, and what are you deliberately leaving out of it?"
        fi ;;
    6)  printf '%s' "What technology choices are already settled here, and which ones are you unsure about?" ;;
    7)  printf '%s' "Does this project make or save money, and how? Say 'none' if it does not." ;;
    8)  printf '%s' "Who has to approve things here, and does anything about this project need sign-off from someone else?" ;;
    9)  printf '%s' "Who has to be able to use this, and does anyone using it need accommodations?" ;;
    10) printf '%s' "Where does this run, and who is it distributed to?" ;;
    11) printf '%s' "What worries you most about this project? Name the thing you would rather not write down." ;;
    *)  printf '%s' "Tell us about this section." ;;
  esac
}

# §4.3's operations weight for S1, as three questions rather than a checklist.
# They cover incident response and the on-call reality (the first), the backup
# maintainer (the second) and the release lane (the third); hosting is already
# asked by section 10's own question above.
adopt_ops_addendum() {
  local scenario="$1"
  [ "$scenario" = "completed" ] || return 0
  adopt_ask_free "incident response" "When this breaks in production, what happens, and who finds out first?" || return 1
  adopt_record_answer "incident_response" "Distribution & Operations" "judgment" "$ADOPT_ANSWER" ""
  adopt_ask_free "backup maintainer" "If you were unavailable for a month, who keeps this running?" || return 1
  adopt_record_answer "backup_maintainer" "Distribution & Operations" "judgment" "$ADOPT_ANSWER" ""
  adopt_ask_free "release lane" "How does a change get from your machine into production today?" || return 1
  adopt_record_answer "release_lane" "Distribution & Operations" "judgment" "$ADOPT_ANSWER" ""
  return 0
}

# ── The scan-derived arm — the BL-204 pattern, preserved ────────────────────
# adopt_confirm_scanned FIELD TITLE VALUE SOURCE
adopt_confirm_scanned() {
  local field="$1" title="$2" value="$3" source="$4"
  local shown=""
  if [ -n "$value" ] && [ "$value" != "null" ]; then
    :  # guard: keeps the block well-formed when the marked read is excised
    shown="$value"   # BF-ADOPT-PREFILL-READ
  fi
  if [ -z "$shown" ]; then
    # Nothing was derivable after all, so this degrades to the ordinary
    # question rather than confirming an empty value at the operator.
    adopt_ask_free "$title" "$title — the scan found nothing to offer here. What is the answer?" || return 1
    adopt_record_answer "$field" "$title" "scan-derived" "$ADOPT_ANSWER" "answered by you; the scan had nothing"
    return 0
  fi

  # TWO DISCLOSURE LINES: the value, and where it came from. The provenance
  # line is the half that makes this a confirmation rather than a nudge — an
  # operator who cannot see where a value came from cannot check it.
  adopt_say "$title"
  adopt_note "The scan found: $shown"
  adopt_note "Where that came from: ${source:-the scan}"
  adopt_ask_choice "$title" "Keep '$shown' as the answer?" "keep it" "change it" || return 1
  if [ "$ADOPT_ANSWER" = "change it" ]; then
    # "change it" falls through to the ORDINARY question — the same fall-through
    # the shipped pattern has, and the reason the prefill can never trap anyone.
    adopt_ask_free "$title" "$title — what is the right answer?" || return 1
    adopt_record_answer "$field" "$title" "scan-derived" "$ADOPT_ANSWER" "changed by you; the scan had offered '$shown'"
  else
    adopt_record_answer "$field" "$title" "scan-derived" "$shown" "${source:-the scan}"
  fi
  return 0
}

# ── The non-skippable arm ───────────────────────────────────────────────────
adopt_ask_data_classification() {
  local raw dc
  adopt_say "The highest classification of any data this system handles."
  adopt_note "This one cannot be skipped, guessed or deferred, in either scenario."
  # NO confirm arm and NO preselection: nothing here is prefilled, because the
  # scan has never seen the data this system handles and §8.3 gives this class
  # no "confirm" behaviour at all.
  adopt_offer_choice "Which one describes it?" $ADOPT_DC_TAXONOMY
  adopt_read_optional
  raw="$ADOPT_ANSWER"
  dc="$(adopt_resolve_choice "$raw" $ADOPT_DC_TAXONOMY)"
  printf '\n'
  if [ -z "$dc" ]; then
    adopt_refuse "$ADOPT_DC_REFUSAL"; return 1   # BF-ADOPT-DC-MANDATORY
  fi
  ADOPT_DATA_CLASSIFICATION="$dc"
  adopt_record_answer "data_classification" "Data & Integrations" "non-skippable" "$dc" ""

  ADOPT_ZDR_ATTESTED="false"
  ADOPT_ZDR_REASON=""
  if [ "$dc" = "public" ]; then
    adopt_note "Public data: no zero-retention attestation is required."
    adopt_record_answer "zdr_attested" "Data & Integrations" "non-skippable" "false" "public data needs no attestation"
    return 0
  fi

  adopt_ask_choice "zero data retention" \
    "Is zero data retention (or a self-hosted model) in place for this project?" "yes" "no" || return 1
  if [ "$ADOPT_ANSWER" = "yes" ]; then
    ADOPT_ZDR_ATTESTED="true"
    adopt_record_answer "zdr_attested" "Data & Integrations" "non-skippable" "true" ""
    return 0
  fi
  adopt_ask_free "the written exception for zero data retention" \
    "Then a written exception is required. What is it? (for example: a customer contract requires retention)" || return 1
  ADOPT_ZDR_REASON="$ADOPT_ANSWER"
  adopt_record_answer "zdr_attested" "Data & Integrations" "non-skippable" "false" ""
  adopt_record_answer "zdr_attestation_reason" "Data & Integrations" "non-skippable" "$ADOPT_ZDR_REASON" ""
  return 0
}

# ── The runner ──────────────────────────────────────────────────────────────
# adopt_run_reverse_intake REPORT SCENARIO — walks Scout's intakePrefill rows
# IN THE ORDER SCOUT EMITS THEM and dispatches each to its class.
adopt_run_reverse_intake() {
  local report="$1" scenario="$2"
  local rows id title kind field value source q
  adopt_head "The interview"
  adopt_note "Some of this the scan already answered — you will see the answer and where it"
  adopt_note "came from, and you can keep it or change it. The rest only you can answer, so"
  adopt_note "there is no default and no way to skip past it."
  adopt_blank

  rows="$(adopt_report_read "$report" '.intakePrefill.sections[]? | [.id, .title, .kind, .field, (.value // ""), (.source // "")] | @tsv')"
  if [ -z "$rows" ]; then
    adopt_refuse "the scan report carries no intakePrefill section — this driver consumes Scout's mapping table and cannot invent one"
    return 1
  fi

  local IFS_SAVE="$IFS"
  while IFS="$(printf '\t')" read -r id title kind field value source; do
    [ -n "${id:-}" ] || continue
    IFS="$IFS_SAVE"
    adopt_blank
    case "$id" in
      13)
        # Section 13 writes itself from the answers above and asks no question
        # of its own — Scout's own sourceHint says so. Disclosing it and then
        # offering to "change it" would be inviting an answer to a question
        # nobody asked, so it is disclosed and recorded, not asked.
        adopt_say "$title"
        adopt_note "The scan found: ${value:-generated}"
        adopt_note "Where that came from: ${source:-generated from the completed intake}"
        adopt_note "Nothing to answer here — it is written from everything above."
        adopt_record_answer "$field" "$title" "generated" "${value:-generated}" "${source:-generated from the completed intake}"
        ;;
      5)
        adopt_say "$title"
        adopt_ask_data_classification || return 1
        ;;
      *)
        case "$kind" in
          scan-derived)
            adopt_confirm_scanned "$field" "$title" "$value" "$source" || return 1
            ;;
          judgment)
            q="$(adopt_judgment_question "$id" "$scenario")"
            adopt_say "$title"
            adopt_ask_free "$title" "$q" || return 1
            adopt_record_answer "$field" "$title" "judgment" "$ADOPT_ANSWER" ""
            [ "$id" = "10" ] && { adopt_ops_addendum "$scenario" || return 1; }
            ;;
          non-skippable)
            # Any future non-skippable row that is not section 5 lands here
            # rather than being silently treated as judgment.
            adopt_say "$title"
            adopt_ask_free "$title" "$(adopt_judgment_question "$id" "$scenario")" || return 1
            adopt_record_answer "$field" "$title" "non-skippable" "$ADOPT_ANSWER" ""
            ;;
          *)
            adopt_refuse "the scan report classifies '$title' as '$kind', which this driver does not know how to ask"
            return 1
            ;;
        esac
        ;;
    esac
  done <<INTAKE_ROWS
$rows
INTAKE_ROWS
  IFS="$IFS_SAVE"
  return 0
}

# ── Rendering the intake artifacts ──────────────────────────────────────────
# adopt_render_intake_doc — PROJECT_INTAKE.md from the answers ledger.
#
# §8.6's provenance header is WP7's deliverable and is NOT emitted here. A
# half-shaped header would be worse than none: WP7 ships a lint for the real
# one, and a near-miss is what a lint cannot tell from the genuine article.
# adopt_stub_provenance_headers says so out loud at run time.
adopt_render_intake_doc() {
  local root="$1" scenario="$2" landed="$3"
  local field title kind value prov last_title=""
  {
    printf '# Project Intake\n\n'
    printf 'Recorded during adoption on %s.\n\n' "$(date -u +%Y-%m-%d)"
    printf 'Scenario: %s. Landed at phase %s.\n\n' "$scenario" "$landed"
    printf 'Each answer below says where it came from. An answer marked as coming from\n'
    printf 'the scan was derived from the code and confirmed by a person; an answer with\n'
    printf 'no provenance was given by a person outright.\n'
    while IFS="$(printf '\t')" read -r field title kind value prov; do
      [ -n "${field:-}" ] || continue
      if [ "$title" != "$last_title" ]; then
        printf '\n## %s\n' "$title"
        last_title="$title"
      fi
      printf '\n- **%s** (%s): %s\n' "$field" "$kind" "$value"
      [ -n "$prov" ] && printf '  - Source: %s\n' "$prov"
    done < "$ADOPT_ANSWERS"
    printf '\n'
  } | adopt_write_file "$root" "PROJECT_INTAKE.md"
}

# adopt_render_intake_progress — .claude/intake-progress.json, in the shape
# scripts/intake-wizard.sh's own progress file uses, so --resume and
# reconfigure-project.sh can read an adopted project's answers.
adopt_render_intake_progress() {
  local root="$1" scenario="$2"
  local answers_json field title kind value prov
  answers_json="{}"
  while IFS="$(printf '\t')" read -r field title kind value prov; do
    [ -n "${field:-}" ] || continue
    answers_json="$(printf '%s' "$answers_json" | jq --arg k "$field" --arg v "$value" '. + {($k): $v}' 2>/dev/null)" || return 1
  done < "$ADOPT_ANSWERS"
  jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$scenario" --argjson a "$answers_json" \
    '{version: 1, started_at: $at, last_section: 13, completed_sections: [],
      source: "adopt-project.sh", adoption_scenario: $s, answers: $a}' \
    | adopt_write_file "$root" ".claude/intake-progress.json"
}

# adopt_persist_phase1_artifacts — the canonical home the Phase 1->2 ZDR gate
# reads. Reuse-by-extraction of intake-wizard.sh's persist_phase1_artifacts():
# the same jq merge onto .phase1_artifacts, with the file CREATED when the
# adoptee has none (the wizard warns and returns, because in a greenfield
# project init.sh has already made it; in an adoptee nothing has).
adopt_persist_phase1_artifacts() {
  local root="$1"
  local pstate=".claude/process-state.json"
  if [ ! -f "$root/$pstate" ]; then
    printf '%s\n' '{"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{},"phase2_init":{"steps_completed":[],"attestations":{}},"phase3_validation":{},"phase4_release":{}}' \
      | adopt_write_file "$root" "$pstate" || return 1
  fi
  local attested_json="false"
  case "$ADOPT_ZDR_ATTESTED" in true|True|TRUE) attested_json="true" ;; esac
  adopt_jq_edit "$root" "$pstate" \
    '.phase1_artifacts = ((.phase1_artifacts // {}) + {data_classification: $c, zdr_attested: $a, zdr_attestation_reason: $r})' \
    --arg c "$ADOPT_DATA_CLASSIFICATION" --argjson a "$attested_json" --arg r "$ADOPT_ZDR_REASON"
}

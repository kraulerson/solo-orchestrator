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
# ACT 2 NOW ASKS ONE OF THE THREE CLASSES, AND ONLY ONE (v2 §8.2 step 7, A7):
#
#   scan-derived    ASKED HERE. Prefilled and confirmed: TWO disclosure lines
#                   naming the value AND ITS PROVENANCE, then keep-it /
#                   change-it, with "change it" falling through to the
#                   ordinary question.
#   judgment        NOT asked here any more. Recorded blank and named as the
#                   assessment's — Act 3's requirements interview (§5.2) is
#                   where a model conducts them.
#   non-skippable   NOT asked here any more either, and that one needs its
#                   reason spelled out rather than assumed. See below.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THE DATA CLASSIFICATION LEFT ACT 2, WHEN THIS FILE USED TO CALL IT
# NON-SKIPPABLE IN BOTH SCENARIOS.
#
# Because the reason it was non-skippable HERE has been deleted, and the
# deletion is Karl's. The old argument, in this file's own words, was
# mechanical: `check-phase-gate.sh`'s Phase 1->2 ZDR backstop hard-FAILs
# whenever `current_phase >= 2` without a recorded classification, and "an S1
# adoption lands at 4, i.e. above that threshold on its FIRST commit". **D10
# deleted the landing.** Nothing lands above phase 0 any more, so a project
# leaving Act 2 is not near that threshold and cannot reach it except by
# crossing the very gate the backstop lives in.
#
# So the requirement did not weaken — its ANCHOR MOVED. §5.2 re-anchors it to
# Act 4's Phase 0 intake write, which refuses without a recorded
# classification, and the shipped backstop remains the second line from the
# moment the project reaches phase 2 by the ordinary route.
#
# THE WINDOW IS REAL AND IS NAMED RATHER THAN HIDDEN: between WP9 and WP12a
# nothing in adoption asks for a classification at all. The direction is
# fail-closed (phase 0, and the only route up crosses the backstop), and the
# operator meets the question in Phase 0 — which is where D10 puts every
# question about what the project is and what it is supposed to do.
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

# ── The runner ──────────────────────────────────────────────────────────────
# adopt_run_reverse_intake REPORT — walks Scout's intakePrefill rows IN THE
# ORDER SCOUT EMITS THEM and dispatches each to its class.
#
# THE SCENARIO PARAMETER IS GONE (D4) AND SO IS EVERY BRANCH THAT READ IT.
adopt_run_reverse_intake() {
  local report="$1"
  local rows id title kind field value source
  adopt_head "The interview"
  adopt_note "Some of this the scan already answered — you will see the answer and where it"
  adopt_note "came from, and you can keep it or change it."
  adopt_note "The rest is not asked here. Questions only a person can answer belong to the"
  adopt_note "assessment, which is a conversation with an agent rather than a form, and this"
  adopt_note "step leaves those cells blank for it."
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
      *)
        case "$kind" in
          scan-derived)
            adopt_confirm_scanned "$field" "$title" "$value" "$source" || return 1
            ;;
          judgment|non-skippable)
            # A7 — ACT 2 DOES NOT ASK THESE. The row is RECORDED, blank, and
            # named as the assessment's, which is deliberately different from
            # dropping it: a cell that is absent from PROJECT_INTAKE.md reads
            # as a question nobody thought of, and a cell that is present and
            # blank reads as one that is waiting. Act 3 fills them.
            #
            # THE MUTATION TARGET IS THIS LINE. Restoring a question here is
            # exactly what "Act 2 asks judgment rows again" means, and the
            # suite's answer script is sized so that doing it runs the run out
            # of answers and refuses.
            adopt_say "$title"
            adopt_note "Not asked here — this one is asked in the assessment."   # BL-242-INTAKE-CONFIRM-ONLY
            adopt_record_answer "$field" "$title" "$kind" "" "left blank by adoption; asked in the assessment"
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
  local root="$1"
  local field title kind value prov last_title=""
  {
    printf '# Project Intake\n\n'
    printf 'Recorded during adoption on %s.\n\n' "$(date -u +%Y-%m-%d)"
    printf 'This project starts at phase 0, like every adopted project. Cells marked as\n'
    printf 'asked in the assessment are deliberately blank: they are questions only a\n'
    printf 'person can answer and they belong to the assessment conversation, not here.\n\n'
    printf 'Each answer below says where it came from. An answer marked as coming from\n'
    printf 'the scan was derived from the code and confirmed by a person; an answer with\n'
    printf 'no provenance was given by a person outright.\n'
    while IFS="$(printf '\t')" read -r field title kind value prov; do
      [ -n "${field:-}" ] || continue
      # SECTION 13 IS RENDERED BELOW, NOT HERE, AND ITS LEDGER ROW IS DROPPED.
      # Emitting both put two `Agent Initialization Prompt` headings five lines
      # apart, and the FIRST one was false twice over: it attributed the prompt
      # to `run_section_13` — `intake-wizard.sh`'s function, which never runs
      # during an adoption — and described it as "generated from the completed
      # intake" directly above a prompt whose whole subject is that the intake
      # is NOT complete. The row is Scout's prefill table doing its job; it is
      # this renderer's job not to print a provenance that is wrong here.
      [ "$field" = "agent_init_prompt" ] && continue
      if [ "$title" != "$last_title" ]; then
        printf '\n## %s\n' "$title"
        last_title="$title"
      fi
      printf '\n- **%s** (%s): %s\n' "$field" "$kind" "$value"
      [ -n "$prov" ] && printf '  - Source: %s\n' "$prov"
    done < "$ADOPT_ANSWERS"
    adopt_render_section_13 "$root"
    printf '\n'
  } | adopt_write_file "$root" "PROJECT_INTAKE.md"
}

# adopt_render_section_13 — the §13 kickoff prompt, AND IT IS RENDERED WITH THE
# HEADING THE EXTRACTOR LOOKS FOR.
#
# WHY THIS EXISTS AT ALL. `scripts/resume.sh`'s kickoff branch is the route a
# completed Act 2 hands the operator to, and it pulls the prompt out of the
# project's own intake with `awk '/^## 13\./{f=1; next} … /^```/{c = !c…}'` — a
# heading spelled `## 13.` followed by a FENCED block. Measured before this was
# written: the adoption-rendered document had neither, so the extraction
# returned empty and `resume.sh` printed its fallback — which told the operator
# to *"read PROJECT_INTAKE.md — Section 13 is your initialization prompt"*
# about a file with no section 13 in it. The handoff pointed at a section the
# handoff's own writer had never rendered.
#
# WHAT IT DELIBERATELY DOES NOT SAY. The greenfield template's section 13 opens
# with `ATTACHED: … Solo Orchestrator Builder's Guide … Platform Module`.
# `init.sh` copies those into `docs/reference/`; **adoption does not** (§8.7a
# row 18, UNOWNED). Copying that wording would hand the agent a list of
# attachments that are not there, which is the false-attachment class — so this
# prompt names only artifacts the adoptee actually has, and says plainly that
# the process reference is missing rather than implying it is attached.
adopt_render_section_13() {
  local root="$1"
  cat <<'S13A'

## 13. Agent Initialization Prompt

```
You are the AI execution layer for a Solo Orchestrator project. I am the
Orchestrator. I define intent, constraints, and validation. You provide
architecture, code, and documentation within the constraints I set.

THIS PROJECT WAS ADOPTED, NOT SCAFFOLDED. It existed before the framework did.
It is at PHASE 0 and no gate has been crossed: nothing about it has been
grandfathered, and nothing in this document may be treated as an approval.

WHAT YOU HAVE:
1. This intake. Cells marked "asked in the assessment" are DELIBERATELY BLANK —
   they are the questions only a person can answer, and nobody has been asked
   them yet. Ask them.
2. .claude/adoption/scout-report.json — a read-only survey of this codebase
   taken at adoption: its stack, its artifacts, its test baseline, its secrets
   findings and its collisions. Use it as evidence about what EXISTS. It is not
   evidence that anything was DONE PROPERLY.
3. .claude/test-debt.json — the files that had no tests at adoption. It is a
   baseline that must not grow, not a list of things to ignore.
S13A

  # ITEM 4 IS CONDITIONAL, and the reason is this function's own header rule.
  # It says the prompt "names only artifacts the adoptee actually has" and calls
  # the alternative the false-attachment class — then named the archive
  # unconditionally, which on a COLLISION-FREE adoptee (the common case, and the
  # shape of this feature's own control fixture) does not exist. Pointing an
  # agent at a directory that is not there is the same defect as the attachment
  # list it was written to avoid, one item further down.
  #
  # Emitted as its own heredoc rather than substituted into the one above: a
  # `sed` replacement carrying a literal newline does not work, and finding that
  # out at run time inside a writer is worse than two heredocs.
  if [ -d "$root/.claude/adoption-archive" ]; then
    cat <<'S13B'
4. .claude/adoption-archive/ — anything of yours the adoption moved aside, with
   a MANIFEST and a restore line for each.
S13B
  fi

  cat <<'S13C'

WHAT YOU DO NOT HAVE: the Solo Orchestrator Builder's Guide and the Platform
Modules. A scaffolded project receives them in docs/reference/; an adopted one
does not yet. Do not act as though a process reference is attached. Ask for it,
or work from this framework's own scripts and their headers.

START HERE, IN THIS ORDER:
1. Fill in every blank cell in this intake by ASKING me. Do not infer them from
   the code — the code is what the survey already read, and the questions that
   are left are the ones it could not answer.
2. Data classification is NOT OPTIONAL and has no default. This project cannot
   cross its Phase 1 to 2 gate without it, and adoption did not ask for it.
3. Then run Phase 0 as the framework defines it, from the beginning.

RULES:
- This intake is the governing constraint once it is filled in. Until then, its
  blank cells are open questions, not permissions.
- Do not suggest that any gate be skipped because the project is "already
  built". That is the exact reasoning adoption exists to refuse.
```
S13C
}

# adopt_render_intake_progress — .claude/intake-progress.json, in the shape
# scripts/intake-wizard.sh's own progress file uses, so --resume and
# reconfigure-project.sh can read an adopted project's answers.
adopt_render_intake_progress() {
  local root="$1"
  local answers_json field title kind value prov
  answers_json="{}"
  while IFS="$(printf '\t')" read -r field title kind value prov; do
    [ -n "${field:-}" ] || continue
    answers_json="$(printf '%s' "$answers_json" | jq --arg k "$field" --arg v "$value" '. + {($k): $v}' 2>/dev/null)" || return 1
  done < "$ADOPT_ANSWERS"
  # THE SEVEN KEYS BELOW ARE NOT DECORATION — THEY ARE WHAT MAKES THIS FILE'S
  # OWN HEADER TRUE, and it was false until WP9a. `intake-wizard.sh`'s
  # `load_progress()` SUBSCRIBES `last_section`, `project_name`, `platform`,
  # `track`, `deployment`, `language` and `description` directly (a python
  # `data['key']`, not a `.get`), so a progress file missing any of them raises
  # `KeyError` — and the wizard swallows it: the traceback goes to stderr, the
  # redirect eats the non-zero status, and `--resume` carries on. Adoption used
  # to write six unrelated keys and none of these.
  #
  # AND `last_section` IS 0, NOT 13, WHICH IS THE HALF THAT MATTERS. The wizard
  # resumes at `LAST_SECTION + 1`, so the old value sent it to Section 14 — past
  # the END of the intake, and past **Section 5, the data classification**. With
  # A7 moving that question out of Act 2, `--resume` was the route that was
  # supposed to still ask it, and 13 was the number that guaranteed it never
  # would. Zero makes the wizard walk the whole intake.
  #
  # The four values adoption cannot know are written EMPTY rather than guessed:
  # an empty string satisfies the subscript and reads as unanswered, while a
  # guessed platform or language would be a fact nobody supplied.
  jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson a "$answers_json" \
        --arg pn "$ADOPT_PROJECT_NAME" --arg dep "$ADOPT_DEPLOYMENT" \
    '{version: 1, started_at: $at, last_section: 0, completed_sections: [],
      source: "adopt-project.sh",
      project_name: $pn, platform: "", track: "full", deployment: $dep,
      language: "", description: "",
      answers: $a}' \
    | adopt_write_file "$root" ".claude/intake-progress.json"
}

# ── The process-state file, and the merge that no longer rides with it ──────
#
# ONE FUNCTION BECAME TWO AT WP9, AND THE SPLIT IS A7's WHOLE MECHANICAL COST.
# `adopt_persist_phase1_artifacts` did two unrelated jobs: it CREATED
# `.claude/process-state.json` when the adoptee had none, and it MERGED the
# data classification into it. A7 moves the classification to Act 4 and the
# file creation must not go with it — `init.sh` guarantees every scaffolded
# project a process-state, so an adoptee without one is an init-parity gap
# (§8.7a row 5) rather than a saving.

# adopt_write_process_state ROOT — creates the file if the adoptee has none.
# Called by Act 2, unconditionally, and it writes no phase-1 content: there is
# none to write until the assessment asks for it.
adopt_write_process_state() {
  local root="$1"
  local pstate=".claude/process-state.json"
  [ -f "$root/$pstate" ] && return 0
  printf '%s\n' '{"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{},"phase2_init":{"steps_completed":[],"attestations":{}},"phase3_validation":{},"phase4_release":{}}' \
    | adopt_write_file "$root" "$pstate" || return 1
  return 0
}

# The taxonomy, spelled exactly as the gate spells it. Order is the gate's.
# KEPT WITH THE WRITER BELOW AND FOR THE SAME REASON: whatever asks for a
# classification in Act 4 has to validate the answer against exactly this set
# or the project fails its own Phase 1->2 gate on a value nobody rejected, and
# re-spelling a seven-value list that must match another script byte-for-byte
# is a drift risk with no upside. One line, one owner, WP12a.
ADOPT_DC_TAXONOMY="public internal confidential pii financial health regulated"

# adopt_persist_phase1_artifacts ROOT — the canonical home the Phase 1->2 ZDR
# gate reads. Reuse-by-extraction of intake-wizard.sh's
# persist_phase1_artifacts(): the same jq merge onto .phase1_artifacts.
#
# ── THIS FUNCTION HAS NO CALLER, AND THAT IS ITS STATUS RATHER THAN A DEFECT.
# Act 2 stopped asking for a classification at WP9 (A7) and Act 4 does not
# exist yet; **WP12a is its caller** and inherits it unchanged. It is kept
# rather than deleted because deleting it means WP12a re-extracts the same
# merge from `intake-wizard.sh` a second time, and two independently-derived
# writers of one key is how the two-owners pattern starts. Reviewers: an
# uncalled function here is a named, dated hand-off, not dead code that was
# missed. If WP12a lands without calling it, THAT is the defect.
#
# The three ADOPT_* variables it reads are likewise kept and stay empty
# through Act 2; the assessment sets them.
adopt_persist_phase1_artifacts() {
  local root="$1"
  local pstate=".claude/process-state.json"
  adopt_write_process_state "$root" || return 1
  local attested_json="false"
  case "$ADOPT_ZDR_ATTESTED" in true|True|TRUE) attested_json="true" ;; esac
  adopt_jq_edit "$root" "$pstate" \
    '.phase1_artifacts = ((.phase1_artifacts // {}) + {data_classification: $c, zdr_attested: $a, zdr_attestation_reason: $r})' \
    --arg c "$ADOPT_DATA_CLASSIFICATION" --argjson a "$attested_json" --arg r "$ADOPT_ZDR_REASON"
}

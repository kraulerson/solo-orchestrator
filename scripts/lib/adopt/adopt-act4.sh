#!/usr/bin/env bash
# scripts/lib/adopt/adopt-act4.sh — WP12a: Act 4's assessment half, the ONE
# shell finisher for the assessment a Claude Code session conducts in Act 3.
#
# SPEC: ADOPT-002-ARCH v2 §8.3 (the record's schema and its refusals), §5.2
# (the interview), §5.3 (a fitness finding is relative to a stated
# requirement), §5.5 (D8's two-halves verdict), §8.5 (the resume branch) and
# §10-WP12a. Backlog: `## BL-242:`.
#
# THE SPLIT, AND WHY IT IS THE RIGHT ONE. The interview and the verdict are
# JUDGEMENT, so a model conducts them (Act 3). Everything that must be TRUE —
# the record's shape, the classification reaching the ZDR gate's home, the
# intake answers landing under the wizard's keys, the assessment merged into
# the stamp exactly once — is checked and written here, by shell, so a suite can
# drive it with a hand-written record and never needs the model in the loop.
#
# NAMED adopt-act4.sh, NOT the design's adopt-finish.sh: `--finish` already
# exists (`adopt_finish_main`, the adoption window's route out, `## BL-291:`),
# and two different finishers one letter apart is a mistake waiting to happen.
#
# WHAT IT NEVER DOES: write `current_phase` (D10 — the project stays at phase
# 0; the ordinary gates move it), write `PRODUCT_MANIFESTO.md` (A3 — Phase 0
# produces it), or commit. It prints the files to commit.

ADOPT_ASSESSMENT_RECORD_REL=".claude/adoption/assessment-record.json"
ADOPT_VERDICT_REL=".claude/adoption/verdict.md"
# The intake answers the finisher accepts: the keys the prompt names, each a
# key `intake-wizard.sh` saves (K8 derives that). An allowlist rather than a
# pattern, because the progress file also holds keys the GATES read —
# project_name, repo_visibility — and a record must not rewrite them
# (review: a record set both and check-gate.sh creates the remote from them).
ADOPT_ACT4_ANSWER_KEYS="users_launch users_6mo users_12mo uptime hosting data_volume problem_statement mvp_date known_risks accessibility_target"

# The order, as data, spelled once.                    # BL-242-ACT4-ORDER
_adopt_act4_order() {
  printf '%s\n' validate_record classification prefill_intake verdict documents merge
}

# _adopt_act4_record_errors ROOT — one line per reason the record is refused;
# nothing when it is acceptable. §8.3's refusals, each on its own line so a
# mutation proof has one site to break.
_adopt_act4_record_errors() {
  local root="$1" rec stamp tax
  rec="$root/$ADOPT_ASSESSMENT_RECORD_REL"
  stamp="$(jq -r '.adoption.adoptedAtCommit // ""' "$root/.claude/manifest.json" 2>/dev/null)"
  tax="$ADOPT_DC_TAXONOMY"
  # ONE JSON OBJECT, OR NOTHING ELSE IS ASKED. jq exits 0 on an EMPTY file —
  # it reads no document and prints nothing — so an empty record used to pass
  # every check below by producing no errors at all (review, measured), and
  # two concatenated records were read as two.
  if ! jq -es 'length == 1 and (.[0] | type) == "object"' "$rec" >/dev/null 2>&1; then
    printf '%s\n' "the record is not exactly one JSON object"
    return 0
  fi
  # `//` IS NOT "IF MISSING": it also replaces `false`. `(.x // null) | type`
  # therefore read inProduction: false as missing and refused every project not
  # in production (review, measured). Types are read directly.
  jq -r --arg stamp "$stamp" --arg tax "$tax" --arg keys "$ADOPT_ACT4_ANSWER_KEYS" '
    def axes: ["interview.users","interview.availability","interview.exposure","interview.scalability","interview.dataClassification","interview.inProduction"];
    ( if .schemaVersion != 1 then "schemaVersion is not 1" else empty end ),
    ( if (.adoptedAtCommit | type) != "string" or .adoptedAtCommit != $stamp then "adoptedAtCommit is not the commit this project was adopted at (\($stamp))" else empty end ),   # BL-242-ACT4-REFUSE-COMMIT
    ( if (.interview | type) != "object" then "interview is missing or not an object" else empty end ),
    ( if (.interview.inProduction | type) != "boolean" then "interview.inProduction is missing or not true/false" else empty end ),   # BL-242-ACT4-REFUSE-INPROD
    ( if (.interview.dataClassification | type) != "string" or ((.interview.dataClassification) as $c | ($tax | split(" ") | index([$c]))) == null then "interview.dataClassification is not one of: \($tax)" else empty end ),   # BL-242-ACT4-REFUSE-DC
    # The phase gate requires a ZDR attestation, or a written reason, for every
    # classification but public (the Phase 1->2 ZDR arm of check-phase-gate.sh).
    ( if (.interview.dataClassification | type) == "string" and .interview.dataClassification != "public"
         and .interview.zdrAttested != true and (((.interview.zdrReason // "") | tostring | gsub("\\s"; "")) == "")
      then "interview.dataClassification is \(.interview.dataClassification): the phase gate needs zdrAttested true or a zdrReason for anything but public" else empty end ),   # BL-242-ACT4-REFUSE-ZDR
    ( if (.fitness | type) != "object" then "fitness is missing or not an object" else empty end ),
    ( if (.fitness.verdict | type) != "string" or (.fitness.verdict | IN("keep", "rebuild") | not) then "fitness.verdict is not keep or rebuild" else empty end ),
    ( if (.fitness.findings | type) != "array" then "fitness.findings is not a list" else empty end ),
    ( if (.fitness.findings | type) == "array" then .fitness.findings[]
        | select((type != "object") or ((.requirementRef | type) != "string") or ((.requirementRef as $r | axes | index([$r])) == null))
        | "fitness finding \((.id? // "?") | tostring) names no interview axis in requirementRef — a finding is relative to a stated requirement (§5.3)"
      else empty end ),   # BL-242-ACT4-REFUSE-REQREF
    ( if (.evaluators | type) != "array" then "evaluators is not a list" else empty end ),
    ( if ((.interview.answers // {}) | type) != "object" then "interview.answers is not an object" else empty end ),
    ( if ((.interview.answers // {}) | type) == "object" then (.interview.answers // {}) | to_entries[]
        | select((.key as $k | ($keys | split(" ") | index([$k]))) == null)
        | "interview.answers key \(.key | @json) is not one the prompt names (\($keys))"
      else empty end ),   # BL-242-ACT4-ANSWER-KEYS
    ( if ((.interview.answers // {}) | type) == "object" then (.interview.answers // {}) | to_entries[] | select((.value | type) != "string")
        | "interview.answers.\(.key) is not a string" else empty end ),
    ( if .verdictArtifact != ".claude/adoption/verdict.md" then "verdictArtifact is not .claude/adoption/verdict.md" else empty end )
  ' "$rec" 2>/dev/null || printf '%s\n' "the record could not be read"
  # The intake file this run will edit must be editable — checked HERE, before
  # any write, so a refusal at the prefill stage cannot follow a written
  # classification (review: "did not begin" printed over a modified file).
  if [ -f "$root/.claude/intake-progress.json" ] \
     && ! jq -es 'length == 1 and (.[0] | type) == "object"' "$root/.claude/intake-progress.json" >/dev/null 2>&1; then
    printf '%s\n' ".claude/intake-progress.json is not a single JSON object, so the answers could not be written into it"
  fi
}

# _adopt_act4_verdict_errors ROOT — D8's two halves (§5.5): a technical account,
# then a `## Plain English` section whose recommendation carries its reason.
_adopt_act4_verdict_errors() {                         # BL-242-ACT4-VERDICT-HALVES
  local v="$1/$ADOPT_VERDICT_REL"
  [ -s "$v" ] || { printf '%s\n' "$ADOPT_VERDICT_REL is missing or empty"; return 0; }
  grep -q '^## Plain English[[:space:]]*$' "$v" || { printf '%s\n' "$ADOPT_VERDICT_REL has no '## Plain English' section"; return 0; }
  awk '/^## Plain English[[:space:]]*$/{exit} /[^[:space:]#]/{n++} END{exit !(n>0)}' "$v" \
    || printf '%s\n' "$ADOPT_VERDICT_REL has no technical account before its '## Plain English' section"
  awk '/^## Plain English[[:space:]]*$/{f=1;next} f&&/^## /{f=0} f&&/^[*_]*Recommendation[*_]*:[*_]*[[:space:]]*[^[:space:]]/{r=1} f&&/^[*_]*Reason[*_]*:[*_]*[[:space:]]*[^[:space:]]/{y=1} END{exit !(r&&y)}' "$v" \
    || printf '%s\n' "$ADOPT_VERDICT_REL's Plain English section needs a 'Recommendation:' line and a 'Reason:' line"
}

adopt_act4_finish() {                                  # BL-242-ACT4-FINISH
  local root="$1" stage errs
  ADOPT_OPERATION="The assessment finisher"
  # A LEDGER, so a refusal after the first write says what was written.
  # Without one, `adopt_refuse` counted nothing and printed "did not begin …
  # nothing was written" over a modified process-state.json (review). The
  # caller removes ADOPT_WORK on exit.
  if [ -z "${ADOPT_WORK:-}" ]; then
    ADOPT_WORK="$(mktemp -d 2>/dev/null)" || { adopt_refuse "could not create a working directory"; return 1; }
  fi
  adopt_ledger_init "$ADOPT_WORK/written" || { adopt_refuse "could not open the finisher's ledger"; return 1; }
  command -v jq >/dev/null 2>&1 || { adopt_refuse "jq is required"; return 1; }
  if ! soif_adoption_adopted "$root/.claude/manifest.json"; then
    adopt_refuse "this project was not adopted, so there is no assessment to finish"
    return 1
  fi
  if jq -e '.adoption.assessment != null' "$root/.claude/manifest.json" >/dev/null 2>&1; then
    adopt_refuse "this project's assessment is already recorded in .claude/manifest.json — it is recorded once"
    return 1
  fi
  [ -f "$root/$ADOPT_ASSESSMENT_RECORD_REL" ] || {
    adopt_refuse "$ADOPT_ASSESSMENT_RECORD_REL is not there — the assessment conversation writes it before this runs"
    return 1; }

  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    case "$stage" in
      validate_record) _adopt_act4_validate "$root" || return 1 ;;
      classification)  _adopt_act4_classification "$root" || return 1 ;;
      prefill_intake)  _adopt_act4_prefill "$root" || return 1 ;;
      verdict)         adopt_note "The verdict is in $ADOPT_VERDICT_REL — technical account, then Plain English." ;;
      documents)       _adopt_act4_documents "$root" ;;
      merge)           _adopt_act4_merge "$root" || return 1 ;;   # BL-242-ACT4-MERGE-LAST
      *)               adopt_refuse "unknown assessment stage '$stage'"; return 1 ;;
    esac
    if [ "${SOIF_ADOPT_ACT4_HALT_AFTER:-}" = "$stage" ]; then
      adopt_refuse "halted after the '$stage' stage (SOIF_ADOPT_ACT4_HALT_AFTER)"
      return 1
    fi
  done <<ORDER
$(_adopt_act4_order)
ORDER
  return 0
}

_adopt_act4_validate() {
  local root="$1" errs
  # PROJECT_INTAKE.md's provenance header too: the assessment conversation
  # edits that file, and a header it broke must not be recorded as assessed.
  errs="$(_adopt_act4_record_errors "$root"; _adopt_act4_verdict_errors "$root"
          adopt_provenance_errors "$root/PROJECT_INTAKE.md" "$(jq -r '.adoption.adoptedAtCommit // ""' "$root/.claude/manifest.json" 2>/dev/null)" \
            | sed 's/^/PROJECT_INTAKE.md: /')"   # BL-242-PROVENANCE-ACT4-CHECK
  [ -z "$errs" ] && { adopt_note "The assessment record and the verdict are complete."; return 0; }
  adopt_refuse "the assessment record was not accepted, and nothing was written"
  printf '%s\n' "$errs" | while IFS= read -r l; do [ -n "$l" ] && printf '          - %s\n' "$l" >&2; done
  # THE HEADER'S OWN REMEDY. Without it the refusal told the operator to fix
  # the record, for a defect in a different file (review).
  if printf '%s\n' "$errs" | grep -q '^PROJECT_INTAKE.md: '; then
    local added
    added="$(git -C "$root" log --diff-filter=A -n1 --format=%h -- PROJECT_INTAKE.md 2>/dev/null)"
    printf '          PROJECT_INTAKE.md must open with the provenance header adoption wrote. Its six\n' >&2
    printf '          lines are in the adoption commit; compare, and put them back first in the file:\n' >&2
    printf '            git show %s:PROJECT_INTAKE.md | sed -n 1,6p\n' "${added:-HEAD}" >&2
  fi
  printf '          Fix what is named above, then run this again.\n' >&2
  return 1
}

# The classification reaches the ZDR gate's home THROUGH the kept function —
# A7's hand-off: `adopt_persist_phase1_artifacts` had no caller until now.
_adopt_act4_classification() {
  local root="$1" rec="$1/$ADOPT_ASSESSMENT_RECORD_REL"
  ADOPT_DATA_CLASSIFICATION="$(jq -r '.interview.dataClassification' "$rec")"
  ADOPT_ZDR_ATTESTED="$(jq -r '.interview.zdrAttested // false' "$rec")"
  ADOPT_ZDR_REASON="$(jq -r '.interview.zdrReason // ""' "$rec")"
  adopt_persist_phase1_artifacts "$root" || return 1   # BL-242-ACT4-CLASSIFICATION
  adopt_note "Recorded the data classification ($ADOPT_DATA_CLASSIFICATION) where the phase gate reads it."
}

# The intake answers, under the wizard's own keys, into the progress file the
# wizard reads. REFUSES without a classification on record (§5.2's anchor).
_adopt_act4_prefill() {
  local root="$1" rec="$1/$ADOPT_ASSESSMENT_RECORD_REL" dc
  dc="$(jq -r '.phase1_artifacts.data_classification // ""' "$root/.claude/process-state.json" 2>/dev/null)"
  if [ -z "$dc" ]; then                                # BL-242-ACT4-PREFILL-NEEDS-DC
    adopt_refuse "the intake answers were not written: no data classification is on record"
    return 1
  fi
  if [ ! -f "$root/.claude/intake-progress.json" ]; then
    printf '{}\n' | adopt_write_file "$root" ".claude/intake-progress.json" || return 1
  fi
  adopt_jq_edit "$root" ".claude/intake-progress.json" \
    '.answers = ((.answers // {}) + $a + {data_classification: $dc})' \
    --argjson a "$(jq -c '.interview.answers // {}' "$rec")" --arg dc "$dc" || return 1
  adopt_note "Wrote $(jq '.interview.answers // {} | length' "$rec") interview answer(s) into .claude/intake-progress.json."
}

# What Act 2 prints at its end, in place of the retired assessment stub: the
# assessment is BUILT now — a Claude Code session plus this finisher — so the
# run names the step rather than apologising for its absence.
adopt_act3_next() {                                    # BL-242-ACT3-NEXT
  adopt_head "Next: the assessment (Act 3)"
  adopt_note "scripts/resume.sh now prints the ASSESSMENT prompt. Paste it into Claude Code: the"
  adopt_note "session asks what this project is for, judges whether the technology fits those"
  adopt_note "answers, writes a verdict and a plan, and runs the finisher that records them."
  adopt_note "The project stays at phase 0 whatever the verdict."
}

_adopt_act4_documents() {
  adopt_note "The framework's documents were written at adoption (CLAUDE.md and the rest); any"
  adopt_note "content folded in from your archived originals was the assessment conversation's."
  return 0
}

_adopt_act4_merge() {
  local root="$1" rec="$1/$ADOPT_ASSESSMENT_RECORD_REL" block
  block="$(jq -c --arg rec "$ADOPT_ASSESSMENT_RECORD_REL" --arg v "$ADOPT_VERDICT_REL" \
    '{assessedAt: .assessedAt, verdict: .fitness.verdict, inProduction: .interview.inProduction,
      interviewRef: $rec, evidenceRef: ".claude/adoption/scout-report.json", verdictRef: $v,
      planRef: (.plan.path // null)}' "$rec")"
  soif_adoption_assess "$root/.claude/manifest.json" "$block" || {
    adopt_refuse "the assessment could not be merged into .claude/manifest.json"; return 1; }
  adopt_audit_event "$root" "assessment" "$(printf '%s' "$block" | jq -c '{verdict, inProduction, assessedAt}')" \
    || adopt_note "The assessment is recorded in .claude/manifest.json; its audit row could not be written — check: jq . .claude/bypass-audit.json"
  adopt_head "The assessment is recorded"
  adopt_note "Verdict: $(jq -r '.fitness.verdict' "$rec"). The project stays at phase 0 either way."
  adopt_note "Commit what the assessment wrote, for example:"
  adopt_note "  git add .claude/manifest.json .claude/process-state.json .claude/intake-progress.json \\"
  adopt_note "          $ADOPT_ASSESSMENT_RECORD_REL $ADOPT_VERDICT_REL .claude/bypass-audit.json"
  adopt_note "  git commit -m 'docs: record the adoption assessment'"
  adopt_note "  …and the plan and any documents the conversation changed, each by name."
  adopt_note "Then run scripts/resume.sh — it now opens Phase 0."
}

# ── THE ASSESSMENT PROMPT, WRITTEN IN ACT 2 (the `assessment_prompt` stage) ──
# `scripts/resume.sh` prints this file on an adopted, unassessed project (its
# fifth branch, `# BL-242-RESUME-ASSESSMENT`). It lives here and not in
# resume.sh because resume.sh is CORE: the module-dependency lint forbids a
# core file to name the adoption driver, and the prompt must name the finisher
# command. So the module writes the words and the core reads a state file —
# the "in-core arms read an adopted flag and never source module code" rule
# (§3.1), applied. It departs from v2.2's A6, which dropped the Act-2-written
# brief; the reason is this lint, and `## BL-242:` records it.
adopt_write_assessment_prompt() {                      # BL-242-ASSESSMENT-PROMPT
  local root="$1" commit
  commit="$(jq -r '.adoption.adoptedAtCommit // ""' "$root/.claude/manifest.json" 2>/dev/null)"
  [ -n "$commit" ] || { adopt_refuse "the assessment prompt needs the adoption commit, and the stamp has none"; return 1; }
  adopt_write_file "$root" ".claude/adoption/assessment-prompt.md" <<PROMPT || return 1
This project was just adopted into the Solo Orchestrator framework. You are running its ASSESSMENT
(Act 3 of adoption). Nothing is decided yet, and the project rests at phase 0 whatever you find.

Read first:
- CLAUDE.md, and the guides in docs/reference/ as you need them.
- .claude/adoption/scout-report.json — what the scan measured. It is evidence; it decides nothing.
- PROJECT_INTAKE.md — what adoption could fill in. The judgement cells are blank on purpose.
- The "Adoption Record" section at the end of APPROVAL_LOG.md, and the adoption archive it names —
  the documents this project had before adoption. Adoption replaced them and merged nothing.

Then, WITH ME — ask, do not infer:
1. The five requirement axes: how many people use it (users); whether it needs high availability
   (availability); whether it is internet-facing (exposure); what growth it must handle
   (scalability); how sensitive the data is (dataClassification — exactly one of:
   public internal confidential pii financial health regulated). For anything but public, the
   phase gate needs a zero-data-retention attestation: ask whether the AI provider is used under
   zero data retention (zdrAttested true), and if not, record the written reason (zdrReason).
2. Is this software in production today — are real users on it? Record true or false.
3. If the evidence shows a mature project (a deploy lane, releases, several contributors), ask who
   runs it, what breaks, who the backup maintainer is, and where it is hosted (interview.operations).
4. Judge fitness ONLY against the requirements I stated. Every finding names the axis it is relative
   to — requirementRef is one of interview.users, interview.availability, interview.exposure,
   interview.scalability, interview.dataClassification, interview.inProduction. "Wrong technology"
   is a finding only when a stated requirement makes it one.
5. Verdict: keep or rebuild. Either way the project continues from phase 0.
6. Write .claude/adoption/verdict.md: the technical account first, then a section headed exactly
   "## Plain English" with what happened, what it means for me, the options with pros and cons, a
   line that begins "Recommendation:" with the recommendation on that same line, a line that begins
   "Reason:" with the reason on that same line, and what happens if I do nothing.
7. Write the plan to docs/phase-0/adoption-plan.md.
8. Fold what is worth keeping from the archived documents into CLAUDE.md, FEATURES.md, BUGS.md and
   RELEASE_NOTES.md, and tell me what you moved.
   PROJECT_INTAKE.md opens with a SOIF-PROVENANCE comment block: keep it exactly as it is, first in
   the file — the finisher refuses a file whose header is missing or altered.
9. Write .claude/adoption/assessment-record.json in exactly this shape:

   { "schemaVersion": 1,
     "assessedAt": "<ISO-8601 UTC>",
     "adoptedAtCommit": "$commit",
     "interview": { "users": "...", "availability": "...", "exposure": "...", "scalability": "...",
                    "dataClassification": "<one of the seven>",
                    "zdrAttested": false, "zdrReason": "",
                    "inProduction": true,
                    "operations": { },
                    "answers": { "<wizard key>": "<string>" } },
     "evaluators": [ ],
     "fitness": { "verdict": "keep",
                  "findings": [ { "id": "F1", "requirementRef": "interview.users",
                                  "severity": "SEV-3", "evidence": "...", "reasoning": "..." } ] },
     "plan": { "path": "docs/phase-0/adoption-plan.md", "summary": "..." },
     "verdictArtifact": ".claude/adoption/verdict.md" }

   "answers" may use ONLY these intake wizard keys, with string values:
   $ADOPT_ACT4_ANSWER_KEYS
   The finisher refuses any other key.
10. Run the finisher, and show me everything it prints:

    bash "\$(jq -r .source_dir .claude/orchestrator-source.json)/scripts/adopt-project.sh" --act4 --root .

    If it refuses, fix what it names and run it again. Nothing is written until the record passes.

Do not write PRODUCT_MANIFESTO.md — Phase 0 produces it. Do not change .claude/phase-state.json —
the project stays at phase 0.
PROMPT
  adopt_note "Wrote the assessment prompt (.claude/adoption/assessment-prompt.md) — scripts/resume.sh prints it."
}

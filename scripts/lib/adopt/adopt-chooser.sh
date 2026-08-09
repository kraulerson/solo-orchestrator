#!/usr/bin/env bash
# scripts/lib/adopt/adopt-chooser.sh — the scenario chooser (§4.1), the
# evidence the scanner OFFERS around it (§4.2), and where each scenario lands
# (§4.3/§4.4, including THE FLOOR RULE).
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §4.1, §4.2, §4.3,
# §4.4, §8.2 (`phaseMap.suggestedPhase` is the REACHED rung and its own note
# says "the interview may only lower this").
#
# ─────────────────────────────────────────────────────────────────────────────
# THE QUESTION IS A DECISION, NOT A PHRASING.
#
# It is Karl's own sentence and it is asked VERBATIM. Two properties of it are
# load-bearing and a well-meaning edit destroys either one:
#
#   • It is written for a NON-DEVELOPER — no phase numbers, no framework
#     vocabulary, no "MVP".
#   • It asks about the PROJECT'S SITUATION, not the project's artifacts,
#     because the artifacts are what the scanner already measured and they are
#     frequently misleading: a mature service with no README.md, a weekend
#     prototype with a tagged release.
#
# tests/test-brownfield-wp4-driver.sh pins the sentence by STRING EQUALITY, and
# also pins both properties directly, so "I just tidied the wording" is a red
# check rather than a silent change of meaning.
#
# ─────────────────────────────────────────────────────────────────────────────
# AND IT IS NOT PREFILLED. §4.2 considered inferring the scenario from the scan
# and asking for confirmation, and REJECTED it: the framework's own prefill
# pattern is right for facts the framework itself recorded earlier and wrong
# for a judgment it has never made, because presenting a guess as a default
# makes the most consequential answer in the whole flow the easiest one to
# accept without reading. So the evidence is printed BEFORE the question, each
# signal with its own confidence, explicitly labelled as evidence — and the
# operator's answer overrides all of it.

# BF-ADOPT-CHOOSER-QUESTION — Karl's wording (§4.1), VERBATIM. Do not reflow,
# do not fix the grammar of "new features add", do not split it across lines.
ADOPT_CHOOSER_QUESTION="Is the project built out and needs to be able to be supported (i.e. bug fixes, maintenance, new features add), or are you still in the process of building your project?"

# The two answers, in the same register as the question: no phase numbers, no
# framework words. They are the operator's own two situations, said back.
ADOPT_CHOOSER_ANSWER_BUILT="It is built out and needs to be supported"
ADOPT_CHOOSER_ANSWER_BUILDING="I am still in the process of building it"

# ── §4.2 — the evidence the scanner offers ──────────────────────────────────
#
# WHAT IS CONSUMED AND WHAT IS DERIVED, stated plainly because the two are easy
# to confuse. §8.2's report schema — verified against scripts/lib/scout/ — has
# no chooser-evidence section: it carries `phaseMap`, `reality`, `stack`,
# `secrets`, `collisions`, `testsBaseline` and `intakePrefill`, and none of
# them is §4.2's table. So the deploy-lane signal is CONSUMED from the report
# (rung 4 and the ci_pipeline_configured probe — Scout already derived it and
# this driver does not re-derive it), while release tags, commit shape and the
# changelog are read from the adoptee's own git and tree HERE, because nothing
# reports them. That gap is recorded in the WP4 report as a candidate for a
# future `chooserEvidence` section in Scout rather than papered over: one fact
# derived in two places is two chances to disagree about it.
#
# Every line below carries its confidence, and the block ends by saying that
# none of it decides anything.
adopt_evidence_deploy_lane() {
  local report="$1"
  local rung4 probe
  rung4="$(adopt_report_read "$report" '[.phaseMap.rungs[]? | select(.rung == 4) | .evidence] | first // ""')"
  probe="$(adopt_report_read "$report" '[.reality.probes[]? | select(.name == "ci_pipeline_configured") | .result] | first // ""')"
  if [ -n "$rung4" ] && [ "$rung4" != "null" ]; then
    adopt_note "Deployment: the scan found $rung4."
    adopt_note "  Points to: built out. Confidence: LOW — this is file presence, not run history;"
    adopt_note "  Scout is read-only and does not ask the host whether the lane has ever run."
  elif [ "$probe" = "pass" ]; then
    adopt_note "Deployment: the scan found a pipeline configured, but no lane out the door."
    adopt_note "  Points to: nothing on its own. Confidence: LOW."
  else
    adopt_note "Deployment: the scan found no way to get this project out the door."
    adopt_note "  Points to: still building. Confidence: LOW — absence of a file is weak evidence."
  fi
}

adopt_evidence_release_tags() {
  local root="$1"
  local newest count
  count="$(cd "$root" 2>/dev/null && git tag 2>/dev/null | grep -cE '^v?[0-9]+\.[0-9]+' )"
  count="$(adopt_int "$count")"
  if [ "$count" -gt 0 ]; then
    newest="$(cd "$root" 2>/dev/null && git for-each-ref --sort=-creatordate --format='%(refname:short) %(creatordate:short)' 'refs/tags/*' 2>/dev/null | head -1)"
    adopt_note "Release tags: $count version-shaped tag(s); newest ${newest:-unknown}."
    adopt_note "  Points to: built out. Confidence: MEDIUM — tags are cheap and often abandoned."
  else
    adopt_note "Release tags: none that look like a version."
    adopt_note "  Points to: still building. Confidence: MEDIUM."
  fi
}

adopt_evidence_commit_shape() {
  local root="$1"
  local feats fixes
  feats="$(cd "$root" 2>/dev/null && git log -50 --format='%s' 2>/dev/null | grep -c '^feat')"
  fixes="$(cd "$root" 2>/dev/null && git log -50 --format='%s' 2>/dev/null | grep -c '^fix')"
  feats="$(adopt_int "$feats")"; fixes="$(adopt_int "$fixes")"
  adopt_note "Recent work: over the last 50 commits, $feats look like new features and $fixes look like fixes."
  if [ "$fixes" -gt "$feats" ]; then
    adopt_note "  Points to: built out. Confidence: LOW — this is a heuristic and it is labelled as one."
  else
    adopt_note "  Points to: still building. Confidence: LOW — this is a heuristic and it is labelled as one."
  fi
}

adopt_evidence_changelog() {
  local root="$1"
  local dated=0
  if [ -f "$root/CHANGELOG.md" ]; then
    dated="$(grep -cE '^#{1,3}[[:space:]]*\[?v?[0-9]+\.[0-9]+' "$root/CHANGELOG.md" 2>/dev/null)"
    dated="$(adopt_int "$dated")"
  fi
  if [ "$dated" -gt 0 ]; then
    adopt_note "Changelog: CHANGELOG.md lists $dated released version(s)."
    adopt_note "  Points to: built out. Confidence: MEDIUM."
  else
    adopt_note "Changelog: no CHANGELOG.md with released versions in it."
    adopt_note "  Points to: nothing on its own. Confidence: MEDIUM."
  fi
}

# adopt_present_evidence ROOT REPORT — the whole §4.2 block.
adopt_present_evidence() {
  local root="$1" report="$2"
  adopt_head "What the scan noticed"
  adopt_note "None of this is an answer. It is what a read-only look at the code found,"
  adopt_note "and each line says how much weight it deserves. Your answer to the next"
  adopt_note "question overrides all of it."
  adopt_blank
  adopt_evidence_deploy_lane "$report"
  adopt_evidence_release_tags "$root"
  adopt_evidence_commit_shape "$root"
  adopt_evidence_changelog "$root"
  adopt_blank
  adopt_note "Users: the scan cannot measure whether anyone is using this. Only you know that."
  adopt_blank
}

# ── The chooser itself ──────────────────────────────────────────────────────
# adopt_ask_scenario — leaves "completed" or "in-flight" in ADOPT_SCENARIO.
# The two words are §8.5's stamp enum, not operator-facing vocabulary; the
# operator never sees either of them.
ADOPT_SCENARIO=""
adopt_ask_scenario() {
  adopt_head "The one question the scan cannot answer"
  # No default, no preselection, no "(suggested)" — §4.2's rejected alternative.
  adopt_ask_choice "the project's situation" "$ADOPT_CHOOSER_QUESTION" \
    "$ADOPT_CHOOSER_ANSWER_BUILT" \
    "$ADOPT_CHOOSER_ANSWER_BUILDING" || return 1
  case "$ADOPT_ANSWER" in
    "$ADOPT_CHOOSER_ANSWER_BUILT")    ADOPT_SCENARIO="completed" ;;
    "$ADOPT_CHOOSER_ANSWER_BUILDING") ADOPT_SCENARIO="in-flight" ;;
    *) adopt_refuse "the scenario answer could not be read"; return 1 ;;
  esac
  return 0
}

# ── Placement (§4.3, §4.4) ──────────────────────────────────────────────────
#
# S1 lands at 4 and adopted. S2 lands at the phase its artifacts support —
# Scout's `phaseMap.suggestedPhase`, the REACHED rung — FLOORED by the
# interview.
#
# THE FLOOR RULE IS ONE-DIRECTIONAL AND THAT IS THE WHOLE POINT (§4.4). The
# interview may only move the placement DOWN, never up. Artifact evidence is a
# claim about what was BUILT; the operator's answer is a claim about what is
# TRUE; where they disagree the SAFER number wins, because a project placed too
# low certifies more than it strictly needed and a project placed too high
# certifies LESS THAN IT OWED. Scout's own report says so in the field beside
# the number: "maximum satisfied rung; the interview may only lower this".
adopt_apply_floor() {
  local scanned="$1" claimed="$2"
  scanned="$(adopt_int "$scanned")"
  claimed="$(adopt_int "$claimed")"
  if [ "$claimed" -lt "$scanned" ]; then printf '%s' "$claimed"; else printf '%s' "$scanned"; fi   # BF-ADOPT-FLOOR
}

# The S2 ladder question, in the operator's register: no phase numbers, no
# framework artifact names. The rungs are the same four Scout measured, said as
# things a person can recognise about their own project.
ADOPT_LADDER_Q="How far along is the work itself? Pick the LAST line that is already true."
ADOPT_LADDER_0="None of these yet"
ADOPT_LADDER_1="We have written down what this project is for"
ADOPT_LADDER_2="...and the technical shape of it is written down too"
ADOPT_LADDER_3="...and there are tests that actually run"
ADOPT_LADDER_4="...and there is a way to get it out the door"

# adopt_ask_ladder — leaves the operator's claimed rung (0-4) in ADOPT_ANSWER.
adopt_ask_ladder() {
  adopt_ask_choice "how far along the work is" "$ADOPT_LADDER_Q" \
    "$ADOPT_LADDER_0" "$ADOPT_LADDER_1" "$ADOPT_LADDER_2" "$ADOPT_LADDER_3" "$ADOPT_LADDER_4" || return 1
  case "$ADOPT_ANSWER" in
    "$ADOPT_LADDER_0") ADOPT_ANSWER=0 ;;
    "$ADOPT_LADDER_1") ADOPT_ANSWER=1 ;;
    "$ADOPT_LADDER_2") ADOPT_ANSWER=2 ;;
    "$ADOPT_LADDER_3") ADOPT_ANSWER=3 ;;
    "$ADOPT_LADDER_4") ADOPT_ANSWER=4 ;;
    *) adopt_refuse "the answer about how far along the work is could not be read"; return 1 ;;
  esac
  return 0
}

# adopt_decide_placement REPORT — leaves the landed phase in ADOPT_LANDED_PHASE.
ADOPT_LANDED_PHASE=""
adopt_decide_placement() {
  local report="$1" scanned claimed landed
  if [ "$ADOPT_SCENARIO" = "completed" ]; then
    # §4.3: S1 lands at 4, full stop. Its artifacts are not consulted, because
    # the operator has just said the thing being built is finished, and the
    # certification pass — every gate 0->1 through 3->4 — is what makes that
    # claim expensive rather than free.
    ADOPT_LANDED_PHASE=4
    adopt_note "This project lands where a finished project lands, and every gate behind it"
    adopt_note "has to be certified rather than assumed."
    return 0
  fi

  scanned="$(adopt_int "$(adopt_report_read "$report" '.phaseMap.suggestedPhase // 0')")"
  adopt_blank
  adopt_note "From the code alone, the scan placed this project at rung $scanned of 4."
  adopt_note "Your answer can move that DOWN if the code flatters the project. It cannot"
  adopt_note "move it up: evidence you have not produced is not evidence."
  adopt_blank
  adopt_ask_ladder || return 1
  claimed="$ADOPT_ANSWER"
  landed="$(adopt_apply_floor "$scanned" "$claimed")"
  ADOPT_LANDED_PHASE="$landed"
  if [ "$claimed" -gt "$scanned" ]; then
    adopt_note "You placed it higher than the code supports, so it lands at $landed — the"
    adopt_note "number the artifacts can back up. Nothing is lost: the rest is earned the"
    adopt_note "ordinary way, by shipping."
  elif [ "$claimed" -lt "$scanned" ]; then
    adopt_note "You placed it lower than the code suggested, so it lands at $landed. The"
    adopt_note "lower number costs more certification, not less, and that is the safe side."
  else
    adopt_note "The code and your answer agree: it lands at $landed."
  fi
  return 0
}

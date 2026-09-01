#!/usr/bin/env bash
# scripts/lib/adopt/adopt-evidence.sh — the evidence the scanner OFFERS the
# operator during Act 2 (§4.2), and nothing else.
#
# SPEC: docs/designs/2026-08-23-brownfield-adoption-v2.md §4.2 (the scanner
# offers evidence; it does not decide), §4.3 (what the evidence is FOR, since
# it is not for placement), §8.3a-A5/A6.
#
# ─────────────────────────────────────────────────────────────────────────────
# THIS FILE WAS `adopt-chooser.sh` AND THE CHOOSER IS GONE (D4, D10).
#
# What it carried and no longer does: Karl's one question, both canned answers,
# `adopt_ask_scenario`, the S2 ladder, `adopt_apply_floor` and
# `adopt_decide_placement`. **D4 deleted the question** — *"trusting an end
# user to know what's needed is a mistake considering they are using the
# orchestrator BECAUSE they are not already following a proper SDLC"* — and
# **D10 deleted the idea that anything should be computed in its place**:
# *"the project gets ingested and starts from the beginning."* Every adopted
# project lands at phase 0 and earns each boundary through the ordinary gates.
#
# The rename is A5's, and it is not tidiness: a file called `chooser`
# containing no chooser is the stale-string class this repository keeps paying
# for.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THE EVIDENCE SURVIVED THE DELETION (A6)
#
# The obvious cut was to delete this block with the question it introduced, and
# it is wrong. §4.3 says the artifact ladder, the census and the reality probes
# all survive and all matter — as PRE-FILL for the Phase 0 intake and as
# context for the plan. And this is the only point in Act 2 where an operator
# sees what a read-only look at their own code found.
#
# WHAT CHANGED IS ITS PURPOSE, AND THE WORDING HAD TO CHANGE WITH IT. The block
# used to end "your answer to the next question overrides all of it", which
# invited the operator to weigh evidence for a judgment they were about to
# make. There is no such judgment now, and a block that still read that way
# would be asking for weight nobody uses. It says plainly instead that the
# project starts at phase 0 whatever any of this says.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT IS CONSUMED AND WHAT IS DERIVED, stated plainly because the two are easy
# to confuse — AND BECAUSE THE SPLIT IS A KNOWN DEFECT THAT WP9 DID NOT FIX.
# §8.2's report schema has no chooser-evidence section: it carries `phaseMap`,
# `reality`, `stack`, `secrets`, `collisions`, `testsBaseline` and
# `intakePrefill`. So the deploy-lane signal is CONSUMED from the report (rung
# 4 and the ci_pipeline_configured probe — Scout already derived it and this
# driver does not re-derive it), while release tags, commit shape and the
# changelog are read from the adoptee's own git and tree HERE, because nothing
# reports them. ONE FACT DERIVED IN TWO PLACES IS TWO CHANCES TO DISAGREE ABOUT
# IT. That is unchanged by the chooser's deletion and is recorded rather than
# quietly inherited; a Scout-side section is the fix and it is nobody's yet.
#
# Every line below carries its confidence, and the block ends by saying that
# none of it decides anything — which is now the literal truth rather than a
# disclaimer.

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
  adopt_note "This is what a read-only look at your code found, and each line says how much"
  adopt_note "weight it deserves. It is here so you can see it, not so you can act on it."
  adopt_blank
  adopt_evidence_deploy_lane "$report"
  adopt_evidence_release_tags "$root"
  adopt_evidence_commit_shape "$root"
  adopt_evidence_changelog "$root"
  adopt_blank
  adopt_note "Users: the scan cannot measure whether anyone is using this. Only you know that."
  adopt_blank
  # A6's closing sentence, and the whole reason this block was allowed to
  # survive D4 in a re-worded form. Say it in as many words: nothing above
  # moves the project, and what it found is reused as PRE-FILL later.
  adopt_note "None of this decides anything. Your project starts at phase 0 either way and"
  adopt_note "earns each gate the ordinary way; what the scan found becomes a head start on"
  adopt_note "the Phase 0 questions, never a shortcut past them."
  adopt_blank
}

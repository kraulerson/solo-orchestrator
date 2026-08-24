#!/usr/bin/env bash
# Solo Orchestrator — the push-time review gate.
#
# Karl's decision, 2026-08-23: the adversarial PR review is mandatory before a
# push, dispatched as a subagent on the most capable model at max effort. It
# earned that standing — across one session it caught a gate that could be
# switched off silently, a check that reported nine sources for eight files, a
# repair tool that had drifted, and two false claims in commit messages.
#
# WHY PUSH AND NOT COMMIT. Three reasons, and the first is decisive.
#   1. A git hook is a shell script. It cannot invoke a model-driven reviewer.
#      The brownfield evaluators hit the identical wall.
#   2. `## BL-149:` — a gate people cannot satisfy honestly gets deleted.
#      Measured over six reviews in one session: 11 to 39 minutes each. Commits
#      land every few minutes; a mandatory half-hour per commit is a gate people
#      route around, and this framework ships a bypass-detector because that
#      behaviour is already known.
#   3. The model this gate specifies is itself slow by design — its own docs say
#      hard tasks "can run many minutes".
# Push is the boundary where the cost is affordable and the check has teeth.
#
# WHAT IT ACTUALLY VERIFIES, stated plainly because the name overpromises: that
# a review VERDICT IS ON RECORD FOR THIS EXACT HEAD. Not that a review happened.
# An agent that writes the record dishonestly defeats it, and one that never
# installs the hook never meets it. `# BL-112-SAST-NOTRUN` is this repo's
# settled posture for that class — you cannot stop the determined, so be loud
# and honest rather than pretend. What it buys is that bypassing becomes an ACT
# with a name and a date on it, instead of an omission nobody can see.
#
# Exit: 0 = push may proceed. 1 = blocked.
set -euo pipefail

STATE=".claude/process-state.json"
RED=''; YEL=''; GRN=''; NC=''
if [ -t 2 ]; then RED=$'\033[0;31m'; YEL=$'\033[1;33m'; GRN=$'\033[0;32m'; NC=$'\033[0m'; fi

_say() { printf '%s\n' "$1" >&2; }

# _refuse <headline> — the TL;DR format, because a gate that stops someone owes
# them a decision they can act on. Karl's standard (docs/reference/messaging-
# standard.md, or docs/messaging-standard.md in the framework itself): the
# technical account AND a plain-English half with options, a recommendation with
# its reasoning, and the cost of doing nothing.
_refuse() {
  _say ""
  _say "${RED}[BLOCKED]${NC} push refused: $1"
  _say ""
  _say "  ── Plain English ──────────────────────────────────────────────"
  _say "  What happened: this project requires an adversarial code review before"
  _say "  code leaves your machine, and there is no review on record for exactly"
  _say "  the commit you are pushing."
  _say ""
  _say "  What it means for you: nothing is lost and nothing is broken. Your"
  _say "  commits are safe locally. The push is what is paused."
  _say ""
  _say "  Options:"
  _say "    1. Run the review.  Ask your agent to dispatch the pr-reviewer"
  _say "       subagent, then record the verdict:"
  _say "         scripts/record-pr-review.sh --verdict <approve|minor_concerns|...>"
  _say "       Costs 10-40 minutes. Catches what a human reading a diff does not."
  _say "    2. Attest past it, once, with a reason that is recorded:"
  _say "         SOLO_PR_REVIEW_ATTESTED=1 \\"
  _say "         SOLO_PR_REVIEW_ATTESTED_REASON=\"<why this push cannot wait>\" git push"
  _say "       Fast. The reason is written down and travels with the project."
  _say ""
  _say "  Recommendation: run the review. The reasoning is that this gate exists"
  _say "  because reviews on this project have repeatedly found defects that every"
  _say "  automated check passed — a gate that is skipped by habit is one that was"
  _say "  never worth installing."
  _say ""
  _say "  If you do nothing: the push stays blocked. Nothing degrades, nothing is"
  _say "  lost, and you can push the moment either option above is done."
  _say "  ───────────────────────────────────────────────────────────────"
  _say ""
}

command -v git >/dev/null 2>&1 || { _say "check-pr-review: git unavailable — cannot identify HEAD."; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || exit 0   # not a repo: nothing to gate

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || printf '')"
[ -n "$HEAD_SHA" ] || { _say "check-pr-review: HEAD does not resolve — refusing rather than guessing."; exit 1; }

# THE ATTESTED ESCAPE IS CHECKED FIRST AND IS ALWAYS RECORDED. `## BL-072:`'s
# shape, reused by `## BL-233:`: an escape that leaves no trace is not an escape,
# it is the gate being off. Refused outright if it cannot be written down.
if [ "${SOLO_PR_REVIEW_ATTESTED:-}" = "1" ]; then
  _reason="$(printf '%s' "${SOLO_PR_REVIEW_ATTESTED_REASON:-}" | LC_ALL=C tr -d '\000-\037\\' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "$_reason" ]; then
    _say "${RED}[BLOCKED]${NC} SOLO_PR_REVIEW_ATTESTED=1 was set with no reason."
    _say "  An attestation without a justification is the gate switched off with extra steps."
    _say "  Set SOLO_PR_REVIEW_ATTESTED_REASON=\"<why>\" and push again."
    exit 1
  fi
  if command -v jq >/dev/null 2>&1; then
    [ -f "$STATE" ] || printf '{}\n' > "$STATE" 2>/dev/null || true
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _by="$(git config user.name 2>/dev/null || printf 'unknown')"
    if jq --arg h "$HEAD_SHA" --arg r "$_reason" --arg t "$_ts" --arg b "$_by" \
         '.pr_review_attestations = ((.pr_review_attestations // []) + [{head: $h, reason: $r, at: $t, by: $b}])' \
         "$STATE" > "$STATE.att.tmp" 2>/dev/null; then
      mv "$STATE.att.tmp" "$STATE"
      printf '%s\n' "${YEL}[ATTESTED]${NC} review skipped for $HEAD_SHA — recorded to $STATE, not silenced." >&2
      exit 0
    fi
    rm -f "$STATE.att.tmp"
  fi
  _say "${RED}[BLOCKED]${NC} the attestation could NOT be recorded (jq missing, or $STATE unwritable)."
  _say "  Refusing it rather than letting it pass unrecorded — an escape that leaves no"
  _say "  trace is the gate being off. Make the state file writable, install jq, re-push."
  exit 1
fi

# THREE SITUATIONS, THREE MESSAGES. An earlier cut collapsed "jq is not
# installed" and "this project has never been reviewed" into one line reading
# "state file or jq missing" — a tooling fault and a perfectly ordinary
# first-push, given the same sentence and therefore the same wrong remedy. It is
# the block/refuse distinction from the messaging standard, inside the gate that
# enforces it.
if ! command -v jq >/dev/null 2>&1; then
  _say ""
  _say "${RED}[BLOCKED]${NC} push refused: jq is not installed, so no review record can be read."
  _say "  This is a TOOLING problem, not a review problem — the gate cannot tell whether"
  _say "  you have been reviewed or not, and 'could not check' is not 'nothing to check'."
  _say "  Install jq (macOS: brew install jq) and push again."
  _say ""
  exit 1
fi
if [ ! -f "$STATE" ]; then
  _refuse "no review has ever been recorded for this project"
  exit 1
fi
jq -e 'true' "$STATE" >/dev/null 2>&1 || { _refuse "$STATE does not parse, so no record can be read from it"; exit 1; }

_rec_head="$(jq -r '.pr_review.head // ""' "$STATE" 2>/dev/null || printf '')"
_rec_verdict="$(jq -r '.pr_review.verdict // ""' "$STATE" 2>/dev/null || printf '')"

if [ -z "$_rec_head" ]; then
  _refuse "no review has ever been recorded for this project"
  exit 1
fi

# STALE IS NOT ABSENT, AND THE MESSAGE MUST SAY WHICH. A review of a different
# tree is not a weaker review, it is a review of something else — telling the
# operator "no review found" when one exists sends them to run a second one
# instead of re-reviewing the change they just made.
if [ "$_rec_head" != "$HEAD_SHA" ]; then
  _refuse "the review on record covers a DIFFERENT commit"
  _say "  Recorded against: $_rec_head"
  _say "  You are pushing:  $HEAD_SHA"
  _say "  The code changed after it was reviewed. Re-review, or attest."
  exit 1
fi

case "$_rec_verdict" in
  approve|minor_concerns)
    printf '%s\n' "${GRN}[OK]${NC} PR review on record for $HEAD_SHA: $_rec_verdict" >&2
    exit 0 ;;
  major_concerns|block)
    _refuse "the review VERDICT for this commit is '$_rec_verdict'"
    _say "  This is not a missing review — it is a review that said no."
    _say "  Fix the findings, re-review, and record the new verdict."
    exit 1 ;;
  *)
    _refuse "the recorded verdict '$_rec_verdict' is not one this gate understands"
    exit 1 ;;
esac

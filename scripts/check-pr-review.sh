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
  _say "  code leaves your machine, and the review record on file does not clear"
  _say "  the commit you are pushing. The headline above says which way."
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

command -v git >/dev/null 2>&1 || { _say "check-pr-review: git unavailable — cannot identify what is being pushed."; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || exit 0   # not a repo: nothing to gate

# BL-243-TOPLEVEL: STATE IS PROJECT-ROOT-RELATIVE. Run from a subdirectory, this
# read a `.claude/` that is not the project's and reported "no review has ever
# been recorded" — false — while the suggested remedy wrote a stray state file
# the hook would never read. git runs hooks at the toplevel, so this only bites
# manual invocations; it bites them silently.
_top="$(git rev-parse --show-toplevel 2>/dev/null || printf '')"
[ -n "$_top" ] && cd "$_top"

# BL-243-PUSHED-REFS: A PUSH DOES NOT HAVE TO PUSH HEAD, and the first cut of
# this gate assumed it did — its only input was `git rev-parse HEAD`. With an
# approve on record for HEAD, `git push origin <some-other-branch>` shipped
# never-reviewed commits while this script printed [OK]: ordinary git usage, no
# dishonesty required, no trace left. git hands a pre-push hook the refs on
# STDIN, one line each: `<local-ref> <local-sha> <remote-ref> <remote-sha>`.
# `[ -t 0 ]` separates the hook (stdin is a pipe) from a human running this by
# hand (stdin is a tty), where a read would block forever.
# --from-hook is passed by the emitted hook and by the documented remedy line.
# It means "a pre-push hook is running me, so a ref list was DUE on stdin".
_from_hook=0
for _a in "$@"; do
  case "$_a" in
    --from-hook) _from_hook=1 ;;
    # A pre-push hook is invoked with <remote-name> <remote-url>, so a wiring
    # that forwards "$@" hands us two POSITIONAL words. Those are legitimate and
    # must pass without a murmur — nagging about them is how a real warning gets
    # tuned out. Only a FLAG-SHAPED argument can be a typo of --from-hook.
    -*) _say "check-pr-review: NOTE — ignoring unrecognized option '$_a'. Only --from-hook is understood, and a typo there silences the drained-stdin warning." ;;
    *) ;;
  esac
done

_pushed_shas=""
_saw_refs=0
if [ ! -t 0 ]; then
  while read -r _lref _lsha _rref _rsha || [ -n "${_lref:-}" ]; do
    [ -n "${_lref:-}" ] || continue
    _saw_refs=1
    # BL-243-REFLINE-SHAPE: could-not-check is never nothing-to-check.
    if [ -z "${_lsha:-}" ]; then
      _say "check-pr-review: the ref line for '$_lref' arrived with NO sha — the ref list is malformed."
      _say "  githooks(5) guarantees four fields per line, so git did not send this. A"
      _say "  capture-and-replay that rewrites fields is the usual cause. Refusing rather"
      _say "  than guessing what was being pushed."
      exit 1
    fi
    # An all-zero local sha is a DELETION — nothing leaves the machine, so there
    # is nothing that could have been reviewed. Blocking those was fail-closed
    # for no gain.
    case "$_lsha" in
      *[!0]*) if [ -z "$_pushed_shas" ]; then _pushed_shas="$_lsha"
              else _pushed_shas="$_pushed_shas $_lsha"; fi ;;
    esac
  done
fi

if [ "$_saw_refs" = "1" ] && [ -z "$_pushed_shas" ]; then
  printf '%s\n' "${GRN}[OK]${NC} deletion-only push — no commits leave the machine, nothing to review." >&2
  exit 0
fi

# BL-243-HOOK-STDIN-DRAINED: a ref list was due and none arrived. Something
# earlier in the operator's hook consumed stdin. Falling back to HEAD is not
# wrong — it is unmeasured, and this gate's whole posture
# (`# BL-112-SAST-NOTRUN`) is that could-not-check must never look like a clean
# check. Loud, not blocking: HEAD is frequently the right answer, and blocking
# every such hook would be `## BL-149:`'s deleted gate.
if [ "$_from_hook" = "1" ] && [ "$_saw_refs" = "0" ]; then
  _say ""
  _say "${YEL}[NOTE]${NC} check-pr-review: no refs arrived on stdin — checked HEAD instead."
  _say "  Two causes, and they are indistinguishable from here:"
  _say "    1. Nothing was being pushed (an up-to-date push still runs this hook with an"
  _say "       empty ref list). Harmless — nothing shipped."
  _say "    2. An earlier line in your pre-push hook CONSUMED the list. Then the commit"
  _say "       verified below may not be the one being pushed, and a pass here would be"
  _say "       a pass for the wrong tree."
  _say "  If your hook reads stdin, capture the list once and replay it to both"
  _say "  consumers — recipe on \`## BL-243:\`."
  _say ""
fi

# BL-243-REVPARSE-VERIFY: `--verify` is load-bearing. Bare `git rev-parse
# HEAD` on an unborn branch ECHOES THE LITERAL STRING "HEAD" to stdout and exits
# 128, so `|| printf ''` never fires, the emptiness guard below could never fire
# either, and a record could be written against the word "HEAD". Measured.
HEAD_SHA="$(git rev-parse --verify HEAD 2>/dev/null || printf '')"

# No `sed`/`tr` on this path ON PURPOSE: the untooled arm below is reached with a
# minimal PATH, and a bare "sed: command not found" is precisely the
# could-not-check that must never be mistaken for anything else.
if [ -n "$_pushed_shas" ]; then _targets="$_pushed_shas"; else _targets="$HEAD_SHA"; fi
[ -n "$_targets" ] || { _say "check-pr-review: nothing resolves to review — no push refs on stdin and HEAD is unborn. Refusing rather than guessing."; exit 1; }

# THE ATTESTED ESCAPE IS CHECKED FIRST AND IS ALWAYS RECORDED. `## BL-072:`'s
# shape, reused by `## BL-233:`: an escape that leaves no trace is not an escape,
# it is the gate being off. Refused outright if it cannot be written down.
if [ "${SOLO_PR_REVIEW_ATTESTED:-}" = "1" ]; then
  _reason="$(printf '%s' "${SOLO_PR_REVIEW_ATTESTED_REASON:-}" | LC_ALL=C tr -d '\000-\037\177\\' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "$_reason" ]; then
    _say "${RED}[BLOCKED]${NC} SOLO_PR_REVIEW_ATTESTED=1 was set with no reason."
    _say "  An attestation without a justification is the gate switched off with extra steps."
    _say "  Set SOLO_PR_REVIEW_ATTESTED_REASON=\"<why>\" and push again."
    exit 1
  fi
  if command -v jq >/dev/null 2>&1; then
    mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
    [ -f "$STATE" ] || printf '{}\n' > "$STATE" 2>/dev/null || true
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _by="$(git config user.name 2>/dev/null || printf 'unknown')"
    if jq --arg h "$HEAD_SHA" --arg p "$_targets" --arg r "$_reason" --arg t "$_ts" --arg b "$_by" \
         '.pr_review_attestations = ((.pr_review_attestations // []) + [{head: $h, pushed: $p, reason: $r, at: $t, by: $b}])' \
         "$STATE" > "$STATE.att.tmp" 2>/dev/null; then
      mv "$STATE.att.tmp" "$STATE"
      printf '%s\n' "${YEL}[ATTESTED]${NC} review skipped for [$_targets] — recorded to $STATE, not silenced." >&2
      exit 0
    fi
    rm -f "$STATE.att.tmp"
  fi
  _say "${RED}[BLOCKED]${NC} the attestation could NOT be recorded (jq missing, or $STATE unwritable or corrupt)."
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
  if [ -n "$_rec_verdict" ]; then
    _refuse "the review record is INCOMPLETE — a verdict with no commit"
    _say "  Recorded verdict: $_rec_verdict, against no sha."
    _say "  A verdict that does not name what it reviewed cannot be checked against what"
    _say "  you are pushing. Re-record with scripts/record-pr-review.sh, or attest."
  else
    _refuse "no review has ever been recorded for this project"
  fi
  exit 1
fi

# STALE IS NOT ABSENT, AND THE MESSAGE MUST SAY WHICH. A review of a different
# tree is not a weaker review, it is a review of something else — telling the
# operator "no review found" when one exists sends them to run a second one
# instead of re-reviewing the change they just made.
# Every commit this push would ship must be the one that was reviewed. The
# record holds ONE verdict for ONE sha, so a multi-ref push at differing shas
# blocks by construction — correctly, because two branches are two reviews. The
# attested escape is checked ABOVE this and covers the whole push.
set -f   # a sha is never a glob; do not let a crafted one become one
for _t in $_targets; do
  # FAIL CLOSED WHEN THE PEEL FAILS. The first cut fell back to the raw sha,
  # which meant "I could not work out what this ref ships" was answered by
  # comparing the thing I could not resolve — and a mutation proved nothing
  # pinned that behaviour. `# BL-112-SAST-NOTRUN`: could-not-check is never
  # nothing-to-check. git only pushes objects it holds, so this is unreachable
  # in ordinary use; a ref tip that is not a commit (a tag of a blob) reaches it,
  # and blocking is the honest answer. The attested escape is checked above.
  _tc="$(git rev-parse --verify "${_t}^{commit}" 2>/dev/null || printf '')"
  if [ -z "$_tc" ]; then
    set +f
    _refuse "a ref in this push does not resolve to a commit, so the gate cannot tell what it ships"
    _say "  Could not resolve: $_t"
    _say "  This is not a review failure — it is the gate refusing to guess. Attest if"
    _say "  the push is deliberate."
    exit 1
  fi
  if [ "$_rec_head" != "$_tc" ]; then
    set +f
    _refuse "the review on record does not cover what you are pushing"
    _say "  Recorded against: $_rec_head"
    _say "  This push ships:  $_targets"
    if [ "$_saw_refs" = "0" ]; then
      _say "  (No ref list arrived, so HEAD was checked. If git then says 'Everything"
      _say "   up-to-date', nothing was actually shipping and this refusal cost you nothing.)"
    fi
    _say "  A review of a different tree is a review of something else. Re-review the"
    _say "  commit you are pushing, push the reviewed one, or attest."
    exit 1
  fi
done
set +f

if [ -z "$_rec_verdict" ]; then
  _refuse "the review record is INCOMPLETE — a commit with no verdict"
  _say "  Recorded against: $_rec_head, with no verdict."
  _say "  This is the mirror of the verdict-with-no-commit case, and it gets the same"
  _say "  answer: re-record with scripts/record-pr-review.sh, or attest."
  exit 1
fi

case "$_rec_verdict" in
  approve|minor_concerns)
    printf '%s\n' "${GRN}[OK]${NC} PR review on record for $_rec_head: $_rec_verdict" >&2
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

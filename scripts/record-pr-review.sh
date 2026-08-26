#!/usr/bin/env bash
# Solo Orchestrator — record an adversarial PR review against the current HEAD.
#
# WHY A RECORD AND NOT A RUN. The reviewer is model-driven; a git hook is a
# shell script and cannot invoke one. That is the same wall the brownfield
# evaluators hit, and it has the same answer: the model produces a durable
# record, and the shell gate reads it. `## BL-233:` built this shape for
# qdrant-store accumulation; this reuses it rather than inventing a second one.
#
# WHAT THIS IS NOT. It is not proof a review happened — an agent that can write
# this file can write it dishonestly, and one that skips the hook entirely never
# reaches it at all. `# BL-112-SAST-NOTRUN` settled the posture for exactly this
# class: you cannot stop someone determined, so be LOUD and be HONEST instead of
# pretending. What the record buys is that skipping becomes an ACT rather than
# an OMISSION, and that the act leaves a trace with a name and a date on it.
#
# Usage:
#   scripts/record-pr-review.sh --verdict <approve|minor_concerns|major_concerns|block>
#                               [--summary-file <path>] [--reviewer <name>] [--head <sha>]
set -euo pipefail

STATE=".claude/process-state.json"
VERDICT=""
REVIEWED_HEAD=""
SUMMARY_FILE=""
REVIEWER="pr-reviewer"

while [ $# -gt 0 ]; do
  case "$1" in
    --verdict)      VERDICT="${2:-}"; shift 2 ;;
    # BL-243-REVIEWED-HEAD: a review takes minutes, and a commit landing
    # DURING one would otherwise be laundered under its verdict — the recorder
    # binds to HEAD-at-record-time. The reviewer knows what it actually read, so
    # let it say so; a mismatch with push-time HEAD then trips the stale arm,
    # which is the correct outcome rather than a silent pass.
    --head)         REVIEWED_HEAD="${2:-}"; shift 2 ;;
    --summary-file) SUMMARY_FILE="${2:-}"; shift 2 ;;
    --reviewer)     REVIEWER="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "record-pr-review: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$VERDICT" in
  approve|minor_concerns|major_concerns|block) : ;;
  "") echo "record-pr-review: --verdict is required" >&2; exit 2 ;;
  *)  echo "record-pr-review: '$VERDICT' is not a verdict (approve|minor_concerns|major_concerns|block)" >&2; exit 2 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "record-pr-review: jq is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "record-pr-review: git is required" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "record-pr-review: not a git repository" >&2; exit 2; }

# BL-243-TOPLEVEL: STATE IS PROJECT-ROOT-RELATIVE. Run from a subdirectory, this
# read a `.claude/` that is not the project's and reported "no review has ever
# been recorded" — false — while the suggested remedy wrote a stray state file
# the hook would never read. git runs hooks at the toplevel, so this only bites
# manual invocations; it bites them silently.
_top="$(git rev-parse --show-toplevel 2>/dev/null || printf '')"
[ -n "$_top" ] && cd "$_top"

HEAD_SHA="$(git rev-parse --verify HEAD 2>/dev/null || printf '')"   # BL-243-REVPARSE-VERIFY
# BL-243-REVIEWED-HEAD: --head lets the caller name the sha that was
# ACTUALLY reviewed. Resolved through `--verify` so a typo or a sha that is not
# in this repository is refused here rather than becoming an unmatchable record
# that reads as a stale review later.
if [ -n "$REVIEWED_HEAD" ]; then
  HEAD_SHA="$(git rev-parse --verify "${REVIEWED_HEAD}^{commit}" 2>/dev/null || printf '')"
  [ -n "$HEAD_SHA" ] || { echo "record-pr-review: --head '$REVIEWED_HEAD' does not resolve to a commit in this repository" >&2; exit 2; }
fi
[ -n "$HEAD_SHA" ] || { echo "record-pr-review: HEAD does not resolve — nothing to record against" >&2; exit 2; }

# THE SUMMARY IS SANITISED AT INGEST, not at display. It is operator- or
# model-supplied text that the gate later prints into a terminal, and
# `## BL-233:` spent eight recurrences learning that a value cleaned at the
# display site is a value cleaned in one place and forgotten in the next. Strip
# control characters AND the backslash — `echo -e` manufactures a real newline
# from the two-character `\n`, so removing only control characters leaves the
# forgery intact.
SUMMARY=""
if [ -n "$SUMMARY_FILE" ]; then
  [ -f "$SUMMARY_FILE" ] || { echo "record-pr-review: --summary-file '$SUMMARY_FILE' does not exist" >&2; exit 2; }
  SUMMARY="$(LC_ALL=C tr -d '\000-\037\177\\' < "$SUMMARY_FILE" | LC_ALL=C cut -c1-2000)"
fi
REVIEWER="$(printf '%s' "$REVIEWER" | LC_ALL=C tr -d '\000-\037\177\\' | LC_ALL=C cut -c1-120)"

mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
[ -f "$STATE" ] || printf '{}\n' > "$STATE"
jq -e 'true' "$STATE" >/dev/null 2>&1 || {
  echo "record-pr-review: $STATE exists but does not parse — refusing to overwrite it." >&2
  echo "  Fix that file first; a review recorded into a corrupt state file is a review nobody can read." >&2
  exit 1
}

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BY="$(git config user.name 2>/dev/null || printf 'unknown') <$(git config user.email 2>/dev/null || printf 'unknown')>"

TMP="$STATE.prreview.tmp"
if ! jq --arg h "$HEAD_SHA" --arg v "$VERDICT" --arg t "$TS" --arg b "$BY" \
        --arg r "$REVIEWER" --arg s "$SUMMARY" \
        '.pr_review = {head: $h, verdict: $v, at: $t, by: $b, reviewer: $r, summary: $s}' \
        "$STATE" > "$TMP" 2>/dev/null; then
  rm -f "$TMP"
  echo "record-pr-review: could not write the record — REFUSING, rather than reporting success." >&2
  exit 1
fi
mv "$TMP" "$STATE"

echo "[OK] PR review recorded: $VERDICT against $HEAD_SHA"
echo "     $STATE is tracked — leave this change UNCOMMITTED until after the push."
echo "     Committing it moves HEAD, and the record would then name the wrong commit."
case "$VERDICT" in
  approve|minor_concerns)
    echo "     A push of this HEAD will pass the review gate." ;;
  *)
    echo "     This verdict BLOCKS the push. Fix the findings and re-review;" >&2
    echo "     recording a blocking verdict does not clear the gate, it documents it." >&2 ;;
esac

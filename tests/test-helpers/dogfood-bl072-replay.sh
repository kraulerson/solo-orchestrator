#!/usr/bin/env bash
# tests/test-helpers/dogfood-bl072-replay.sh — BL-072 Phase C1 measurement.
#
# Karl's standing condition on BL-072: dogfood the TDD-ordering detector in
# WARN mode on this repo (a Full-shaped project whose own history is full of
# legitimate feat/fix/refactor commits) and MEASURE the false-block rate
# BEFORE any hard block (Phase C2) ships. This script produces that
# measurement.
#
# It walks `git log <base> --no-merges` bounded since a cutoff date, classifies
# each commit's OWN changed files with the SAME shared core the live gate uses
# (scripts/lib/tdd-classify.sh), and reports how many feat/fix/refactor commits
# WOULD have been blocked by a naive "impl without a test in the same commit"
# rule.
#
# ⚠️ UPPER BOUND. Per-commit replay classifies each commit on its own files
# only (`git diff-tree`). It CANNOT apply the live gate's "a test written
# earlier on the branch satisfies the commit" allowance, because that allowance
# is a property of the branch history at commit time, not of the merged commit.
# So the replay's would-block COUNT OVERSTATES the live false-block rate: every
# commit whose test landed in a sibling commit on the same PR branch is counted
# as a would-block here but would pass live. Read the number as a ceiling.
#
# Usage (copies scaffold-libs.sh's conventions — resolve own repo root, accept
# optional overrides):
#   tests/test-helpers/dogfood-bl072-replay.sh [since_date] [base_ref] [out_file]
# Defaults: since=2026-04-01  base=main  out=Reports/2026-07-10-bl072-warn-dogfood.md
#
# shellcheck shell=bash
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)).

set -uo pipefail

_SELF_DIR="${BASH_SOURCE[0]%/*}"
[ "$_SELF_DIR" = "${BASH_SOURCE[0]}" ] && _SELF_DIR="."
REPO_ROOT="$(cd "$_SELF_DIR/../.." && pwd)"

SINCE="${1:-2026-04-01}"
BASE="${2:-main}"
OUT="${3:-$REPO_ROOT/Reports/2026-07-10-bl072-warn-dogfood.md}"

# Share the live gate's classifier verbatim.
TDD_LIB="$REPO_ROOT/scripts/lib/tdd-classify.sh"
if [ ! -f "$TDD_LIB" ]; then
  echo "dogfood-bl072-replay: missing $TDD_LIB" >&2
  exit 1
fi
# shellcheck source=scripts/lib/tdd-classify.sh
. "$TDD_LIB"

cd "$REPO_ROOT" || exit 1

if ! git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
  echo "dogfood-bl072-replay: base ref '$BASE' not found" >&2
  exit 1
fi

# Escape a subject for a markdown table cell.
md_cell() { printf '%s' "$1" | tr '\n' ' ' | sed 's/|/\\|/g'; }

# Counters.
total_scanned=0
in_scope=0
would_block=0
feat_n=0; feat_wb=0
fix_n=0;  fix_wb=0
ref_n=0;  ref_wb=0

# Accumulate the would-block detail rows (newest-first, since git log is
# newest-first). Tab-separated: sha \t subject \t impl_files(space-joined).
WB_ROWS=$(mktemp)
trap 'rm -f "$WB_ROWS"' EXIT

# Walk the history.
while IFS= read -r sha; do
  [ -z "$sha" ] && continue
  total_scanned=$((total_scanned + 1))
  subject=$(git show -s --format=%s "$sha" 2>/dev/null)

  # Scope: feat/fix/refactor Conventional-Commit subjects only.
  prefix=$(printf '%s' "$subject" | sed -nE 's/^(feat|fix|refactor)(\([^)]*\))?!?:.*/\1/p')
  [ -z "$prefix" ] && continue
  in_scope=$((in_scope + 1))

  files=$(git diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null)
  counts=$(printf '%s\n' "$files" | _bl072_classify_paths)
  n_impl=${counts#IMPL:}; n_impl=${n_impl%% *}
  n_test=${counts##*TEST:}

  case "$prefix" in
    feat)     feat_n=$((feat_n + 1)) ;;
    fix)      fix_n=$((fix_n + 1)) ;;
    refactor) ref_n=$((ref_n + 1)) ;;
  esac

  # Would-block iff implementation present AND no test in this commit.
  if [ "${n_impl:-0}" -gt 0 ] 2>/dev/null && [ "${n_test:-0}" -eq 0 ] 2>/dev/null; then
    would_block=$((would_block + 1))
    case "$prefix" in
      feat)     feat_wb=$((feat_wb + 1)) ;;
      fix)      fix_wb=$((fix_wb + 1)) ;;
      refactor) ref_wb=$((ref_wb + 1)) ;;
    esac
    impl_list=$(printf '%s\n' "$files" | while IFS= read -r f; do
      [ -z "$f" ] && continue
      if _bl072_is_impl_file "$f"; then printf '%s ' "$f"; fi
    done)
    printf '%s\t%s\t%s\n' "$(git rev-parse --short "$sha")" "$subject" "$impl_list" >> "$WB_ROWS"
  fi
done < <(git log "$BASE" --no-merges --since="$SINCE" --format=%H)

# Rates (integer permille → one-decimal percent, no bc dependency).
pct() {
  local num="$1" den="$2"
  if [ "$den" -eq 0 ]; then echo "0.0"; return; fi
  local permille=$(( (num * 1000 + den / 2) / den ))
  local whole=$(( permille / 10 ))
  local frac=$(( permille % 10 ))
  printf '%s.%s' "$whole" "$frac"
}

overall_rate_scope=$(pct "$would_block" "$in_scope")
overall_rate_total=$(pct "$would_block" "$total_scanned")
feat_rate=$(pct "$feat_wb" "$feat_n")
fix_rate=$(pct "$fix_wb" "$fix_n")
ref_rate=$(pct "$ref_wb" "$ref_n")

GEN_DATE=$(date -u +%Y-%m-%d)
HEAD_SHA=$(git rev-parse --short HEAD)

mkdir -p "$(dirname "$OUT")"

{
  echo "# BL-072 Phase C1 — TDD-ordering WARN dogfood replay"
  echo ""
  echo "**Generated:** ${GEN_DATE} (replay tool: \`tests/test-helpers/dogfood-bl072-replay.sh\`)"
  echo "**Repo state:** \`${BASE}\` @ \`${HEAD_SHA}\`  ·  **Window:** commits since ${SINCE} (\`--no-merges\`)"
  echo "**Classifier:** \`scripts/lib/tdd-classify.sh\` — the SAME core the live gate uses."
  echo ""
  echo "> ⚖️ **This is the decision deliverable for Karl.** Phase C2 (the hard"
  echo "> block) is NOT implemented and must not ship until Karl reviews the"
  echo "> false-block rate below."
  echo ""
  echo "## What \"would-block\" means here"
  echo ""
  echo "A commit is counted as a would-block if its subject is \`feat:\`/\`fix:\`/"
  echo "\`refactor:\` AND its own changed files contain at least one implementation"
  echo "file (anything not under \`tests/ docs/ .github/ Reports/ templates/\` and"
  echo "not \`scripts/lint-*.sh\`) AND no test file rides along in the same commit."
  echo ""
  echo "### ⚠️ These counts are an UPPER BOUND on the live false-block rate"
  echo ""
  echo "Per-commit replay classifies each commit on **its own files only**"
  echo "(\`git diff-tree\`). It cannot reproduce the live gate's allowance that a"
  echo "test written **earlier on the same branch** (\`git diff main...HEAD\`)"
  echo "satisfies the commit. On this repo, features were routinely split across"
  echo "commits on a PR branch (tests in one commit, implementation in the next),"
  echo "so many replay would-blocks would pass live. Treat every number below as a"
  echo "ceiling, not the live rate."
  echo ""
  echo "It is also path-based only: a \`feat/fix/refactor\` commit that changes just"
  echo "comments in an implementation file still counts as impl (a documented C1"
  echo "limitation). WARN-only mode makes both over-counts harmless."
  echo ""
  echo "## Headline numbers"
  echo ""
  echo "| Metric | Value |"
  echo "|---|---|"
  echo "| Non-merge commits scanned (since ${SINCE}) | ${total_scanned} |"
  echo "| In-scope (\`feat\`/\`fix\`/\`refactor\`) commits | ${in_scope} |"
  echo "| **Would-block commits** | **${would_block}** |"
  echo "| Would-block rate (of in-scope) | **${overall_rate_scope}%** |"
  echo "| Would-block rate (of all scanned) | ${overall_rate_total}% |"
  echo ""
  echo "## Would-block rate by prefix"
  echo ""
  echo "| Prefix | In-scope | Would-block | Rate (of prefix) |"
  echo "|---|---|---|---|"
  echo "| \`feat\` | ${feat_n} | ${feat_wb} | ${feat_rate}% |"
  echo "| \`fix\` | ${fix_n} | ${fix_wb} | ${fix_rate}% |"
  echo "| \`refactor\` | ${ref_n} | ${ref_wb} | ${ref_rate}% |"
  echo ""
  echo "## Hand-review — the 20 most-recent would-blocks"
  echo ""
  echo "Verdict column filled by careful reading of each commit's actual diff."
  echo "**true-positive** = genuinely shipped runtime implementation with no test"
  echo "anywhere it should have had one (a real TDD-ordering miss). **false-positive**"
  echo "= the naive path-based rule fired but the commit is not a TDD violation"
  echo "(tests landed in a sibling commit on the branch; docs/backlog/config-shaped"
  echo "change misclassified as impl; comment/format-only; etc.)."
  echo ""
  echo "| # | sha | subject | verdict | reason |"
  echo "|---|---|---|---|---|"
  i=0
  while IFS=$'\t' read -r sha subject impl_list; do
    [ -z "$sha" ] && continue
    i=$((i + 1))
    [ "$i" -gt 20 ] && break
    echo "| ${i} | \`${sha}\` | $(md_cell "$subject") | _(pending review)_ | _(pending review)_ |"
  done < "$WB_ROWS"
  echo ""
  echo "<!-- REVIEW-SHAS (impl files per would-block, newest-first; used to fill verdicts):"
  i=0
  while IFS=$'\t' read -r sha subject impl_list; do
    [ -z "$sha" ] && continue
    i=$((i + 1))
    [ "$i" -gt 20 ] && break
    echo "${i}. ${sha}  ${subject}"
    echo "     impl: ${impl_list}"
  done < "$WB_ROWS"
  echo "-->"
} > "$OUT"

echo "dogfood-bl072-replay: wrote $OUT"
echo "  scanned=$total_scanned in_scope=$in_scope would_block=$would_block rate_scope=${overall_rate_scope}% rate_total=${overall_rate_total}%"
echo "  feat: $feat_wb/$feat_n (${feat_rate}%)  fix: $fix_wb/$fix_n (${fix_rate}%)  refactor: $ref_wb/$ref_n (${ref_rate}%)"

#!/usr/bin/env bash
# scripts/lint-backlog-references.sh — fail CI when commits and backlog
# entries drift apart. This is the process-discipline mirror of PR #72's
# counter-antipattern lint (Slot-4 of cycle 7 introduced the latter as
# the wave-2 backstop after counter-sanitizer remediation; this is the
# Slot-5 sibling that backstops backlog-citation hygiene).
#
# THE TWO DEFECT CLASSES
#
# 1. Unknown BL reference in a commit message.
#    A commit subject or body cites `BL-NNN` (e.g. `fix(init): host-
#    agnostic exit-3 attestation flow (BL-031)`) but no entry header
#    `## BL-NNN:` exists in solo-orchestrator-backlog.md. Catches typos
#    (`BL-31` vs `BL-031`), copy-paste from sibling repos, and stale
#    references to BLs that were merged into other entries.
#
# 2. `Closed`/`Resolved` backlog entry with no PR# or commit-SHA cite.
#    The entry block (from `## BL-NNN:` header to the next `---` or
#    next `## BL-` header) was flipped to Closed but reviewers can't
#    trace back to the merge. Acceptable cite forms inside the block:
#      - `PR #42` anywhere in the block
#      - a backticked commit SHA `` `1a2b3c4` `` (7-40 hex chars)
#    The status line itself can be either pattern Karl has used:
#      - `**Status:** Resolved (DATE, PR #N)` (early convention)
#      - `**Status:** Closed` + a separate `**Closed:** DATE — commit
#        `SHA` ...` line (later convention)
#      - `**Status:** Closed — shipped DATE (PR #N).` (current convention)
#    The check is structural — any of these satisfy as long as a PR# or
#    SHA appears somewhere in the entry block.
#
# DELIBERATE SCOPE
#   • Targets ONLY solo-orchestrator-backlog.md (the canonical backlog).
#     Other docs (Reports/, docs/) can mention BL-NNN in prose without
#     constraint — they're not the source of truth.
#   • Commit-history walk uses `git log <BASE>..HEAD --pretty=%s%n%b`
#     so the lint is BASE-relative. CI sets BASE to `origin/${base_ref}`;
#     local runs default to `origin/main`. Override with `--base <ref>`.
#   • Tokens are matched case-insensitively against the regex
#     `BL-[0-9]+[a-z]?` (supports the `BL-003a` / `BL-003b` suffix
#     splits introduced in cycle 5). Sub-IDs are normalized to upper-
#     case before lookup so `bl-031` in a commit subject resolves
#     correctly. The valid-ID set is built ONCE from the backlog
#     using the literal entry-header regex `^## BL-[0-9]+[a-z]?:`.
#   • Branch-scoped token allowlist: if ANY commit in the BASE..HEAD
#     range contains a `lint-backlog-references-ignore: <CSV>` footer
#     (case-insensitive, comma-separated, anywhere in the message),
#     those tokens are skipped from the unknown-ref check ACROSS THE
#     ENTIRE BASE..HEAD range. Scope is branch-wide (not per-commit)
#     so a clean-up commit can retroactively exempt placeholder tokens
#     mentioned in an earlier commit on the same branch (otherwise an
#     amend-or-rewrite would be required to fix prose). Use this when
#     a commit LEGITIMATELY mentions a placeholder ID — test fixtures,
#     sample diagnostics in a CHANGELOG entry, or this very script's
#     own header — without intending to reference a real backlog item.
#   • Citations are required ONLY for entries whose status block
#     contains "Closed" or "Resolved" (case-sensitive — these are the
#     two terms Karl uses; "open"/"in-progress"/"wontfix"/"promoted-
#     to-spec" don't require citations).
#
# ALLOWLIST
#   For entries closed before the citation convention existed, append
#   `<!-- lint-backlog-references: allow <reason> -->` to the
#   `**Status:**` line itself. The reason is REQUIRED — empty reason
#   fails the lint, matching PR #72's allowlist semantics.
#
# EXIT CODES
#   0 — no violations
#   1 — one or more violations found
#   2 — invocation / I/O error
#
# USAGE
#   bash scripts/lint-backlog-references.sh                      # quiet pass/fail
#   bash scripts/lint-backlog-references.sh --base origin/main   # explicit base
#   bash scripts/lint-backlog-references.sh --list               # PASS/FAIL table

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKLOG="$REPO_ROOT/solo-orchestrator-backlog.md"

LIST_MODE=0
BASE_REF="origin/main"

while [ $# -gt 0 ]; do
  case "$1" in
    --list)
      LIST_MODE=1
      shift
      ;;
    --base)
      if [ -z "${2:-}" ]; then
        echo "Usage: $0 [--list] [--base <ref>]" >&2
        exit 2
      fi
      BASE_REF="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--list] [--base <ref>]" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$BACKLOG" ]; then
  echo "FATAL: backlog file not found at $BACKLOG" >&2
  exit 2
fi

# ── Step 1: Build set of valid BL-IDs from backlog headers ─────────
# Both the valid-set and lookup tokens are upper-cased so the lint is
# case-insensitive end-to-end (`BL-003a` in a header matches `bl-003a`
# or `BL-003A` in a commit subject — the suffix is preserved).
VALID_IDS=()
while IFS= read -r id; do
  VALID_IDS+=("$(printf '%s' "$id" | tr '[:lower:]' '[:upper:]')")
done < <(grep -oE '^## BL-[0-9]+[a-z]?:' "$BACKLOG" | sed -E 's/^## (BL-[0-9]+[a-z]?):/\1/')

is_valid_id() {
  local needle="$1"
  local v
  for v in "${VALID_IDS[@]}"; do
    [ "$v" = "$needle" ] && return 0
  done
  return 1
}

# Normalize a token like `bl-31` → `BL-031`? NO — we do NOT zero-pad.
# `BL-31` is a different reference than `BL-031`; the lint should
# catch the typo, not silently normalize it. Case is normalized to
# upper because shell convention varies and case-folding is harmless.
normalize_id() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

VIOLATIONS=0
LIST_ROWS=""

# ── Step 2: Scan commit messages BASE..HEAD for BL references ──────
# Use a per-commit walk so we can name the offending SHA in diagnostics.
COMMIT_SHAS=()
while IFS= read -r sha; do
  [ -n "$sha" ] && COMMIT_SHAS+=("$sha")
done < <(git log "${BASE_REF}..HEAD" --pretty='%H' 2>/dev/null || true)

# Branch-scoped token allowlist: aggregate every
# `lint-backlog-references-ignore: <CSV>` footer across ALL commits
# in BASE..HEAD, normalize to upper-case, store as a space-padded
# string for cheap substring lookup. Scope is branch-wide so a
# later commit can retroactively exempt prose in an earlier commit
# without rewriting history.
RANGE_MSG=$(git log "${BASE_REF}..HEAD" --pretty='%s%n%b' 2>/dev/null || true)
BRANCH_IGNORE=" $(printf '%s' "$RANGE_MSG" \
  | grep -oiE 'lint-backlog-references-ignore:[[:space:]]*[A-Za-z0-9_,[:space:]-]+' \
  | sed -E 's/^[Ll]int-[Bb]acklog-[Rr]eferences-[Ii]gnore:[[:space:]]*//' \
  | tr ',' ' ' | tr '[:lower:]' '[:upper:]' | tr -s '[:space:]' ' ') "

for sha in "${COMMIT_SHAS[@]:-}"; do
  [ -z "$sha" ] && continue
  # Extract subject + body, scan for BL-NNN tokens (case-insensitive).
  msg=$(git log -1 --pretty='%s%n%b' "$sha" 2>/dev/null || true)
  # Use grep -oE; tokens may repeat — dedupe per commit.
  tokens=$(printf '%s' "$msg" | grep -oiE 'BL-[0-9]+[a-z]?' | sort -u || true)
  if [ -z "$tokens" ]; then
    continue
  fi
  while IFS= read -r raw_tok; do
    [ -z "$raw_tok" ] && continue
    tok=$(normalize_id "$raw_tok")
    # Skip allowlisted tokens (branch-scoped).
    case "$BRANCH_IGNORE" in
      *" $tok "*)
        LIST_ROWS="${LIST_ROWS}PASS\tcommit ${sha:0:7}\t${tok}\tbranch-scoped-ignore\n"
        continue
        ;;
    esac
    if is_valid_id "$tok"; then
      LIST_ROWS="${LIST_ROWS}PASS\tcommit ${sha:0:7}\t${tok}\treferences existing backlog entry\n"
    else
      echo "lint-backlog-references: unknown BL reference '${tok}' in commit ${sha:0:7}" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      LIST_ROWS="${LIST_ROWS}FAIL\tcommit ${sha:0:7}\t${tok}\tunknown BL reference\n"
    fi
  done <<< "$tokens"
done

# ── Step 3: Scan backlog blocks for Closed/Resolved without citation ──
#
# A block runs from `## BL-NNN:` (or `## code-...:` — but only BL- IDs
# are linted here) to the next `## ` header or `---` separator at the
# start of a line. Read the file once and slice it by markers.

# Use awk to extract per-ID blocks, then evaluate each.
# Output format: ID<TAB>STATUS_FOUND<TAB>HAS_PR<TAB>HAS_SHA<TAB>HAS_ALLOW<TAB>ALLOW_REASON
BLOCK_REPORT=$(awk '
  BEGIN { id = ""; block = ""; status_line = "" }
  /^## BL-[0-9]+[a-z]?:/ {
    flush()
    id = $2
    sub(/:$/, "", id)
    block = $0 "\n"
    status_line = ""
    next
  }
  /^## / { flush(); id = ""; block = ""; status_line = ""; next }
  /^---[[:space:]]*$/ { flush(); id = ""; block = ""; status_line = ""; next }
  {
    if (id != "") {
      block = block $0 "\n"
      if ($0 ~ /^\*\*Status:\*\*/) status_line = $0
    }
  }
  END { flush() }
  function flush() {
    if (id == "") return
    status_found = "open"
    if (status_line ~ /(Closed|Resolved)/) status_found = "closed"
    has_pr = (block ~ /PR #[0-9]+/) ? "Y" : "N"
    has_sha = (block ~ /`[0-9a-f]{7,40}`/) ? "Y" : "N"
    has_allow = "N"
    allow_reason = ""
    if (status_line ~ /<!-- lint-backlog-references: allow/) {
      has_allow = "Y"
      tmp = status_line
      sub(/.*<!-- lint-backlog-references: allow[ \t]*/, "", tmp)
      sub(/[ \t]*-->.*/, "", tmp)
      allow_reason = tmp
    }
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, status_found, has_pr, has_sha, has_allow, allow_reason
  }
' "$BACKLOG")

while IFS=$'\t' read -r id status_found has_pr has_sha has_allow allow_reason; do
  [ -z "$id" ] && continue
  if [ "$status_found" = "open" ]; then
    LIST_ROWS="${LIST_ROWS}PASS\t${id}\t-\topen (no citation required)\n"
    continue
  fi
  # status_found == closed → require PR# or SHA, OR a non-empty allow marker.
  if [ "$has_allow" = "Y" ]; then
    if [ -z "$allow_reason" ]; then
      echo "lint-backlog-references: ${id} has empty allowlist reason (use '<!-- lint-backlog-references: allow <reason> -->')" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      LIST_ROWS="${LIST_ROWS}FAIL\t${id}\t-\tallowlist-empty-reason\n"
    else
      LIST_ROWS="${LIST_ROWS}PASS\t${id}\t-\tallowlist:${allow_reason}\n"
    fi
    continue
  fi
  if [ "$has_pr" = "Y" ] || [ "$has_sha" = "Y" ]; then
    detail="cited:"
    [ "$has_pr" = "Y" ] && detail="${detail}PR#"
    [ "$has_sha" = "Y" ] && detail="${detail}SHA"
    LIST_ROWS="${LIST_ROWS}PASS\t${id}\t-\t${detail}\n"
  else
    echo "lint-backlog-references: ${id} marked Closed/Resolved but no PR# or commit SHA cited in the entry block" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
    LIST_ROWS="${LIST_ROWS}FAIL\t${id}\t-\tuncited-closure\n"
  fi
done <<< "$BLOCK_REPORT"

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tSOURCE\tTOKEN\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS violation(s) found. See scripts/lint-backlog-references.sh header for the fix patterns." >&2
  exit 1
fi

echo "OK: backlog references and Closed-status citations are consistent."
exit 0

#!/usr/bin/env bash
# scripts/lint-backlog-references.sh — fail CI when commits and backlog
# entries drift apart. This is the process-discipline mirror of PR #72's
# counter-antipattern lint (Slot-4 of cycle 7 introduced the latter as
# the wave-2 backstop after counter-sanitizer remediation; this is the
# Slot-5 sibling that backstops backlog-citation hygiene).
#
# THE THREE DEFECT CLASSES
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
# 3. Duplicate `## BL-NNN:` entry header (BL-207).
#    The same ID owns two (or more) entry headers, so `BL-NNN` stops
#    being a unique key — grep, the citation primitive, and this
#    script's own block splitter all resolve ambiguously. See the
#    `# BL-207-HEADER-UNIQUENESS` arm below for the decisions.
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
#   bash scripts/lint-backlog-references.sh --pre-commit-mode \  # pre-commit
#     --message "feat: do thing (BL-031)"                        # gate use
#   echo "feat: x (BL-031)" \                                    # OR pipe the
#     | bash scripts/lint-backlog-references.sh --pre-commit-mode #   message
#
# PRE-COMMIT MODE
#   Skips Step 2 (the BASE..HEAD commit-message walk) — there is no
#   commit yet at pre-commit time, so `git log` would be a no-op or,
#   worse, walk historical commits the operator can't fix from this
#   commit. Instead, the prospective commit message is supplied via
#   `--message <text>` or stdin and scanned for `BL-NNN` tokens.
#   Steps 3 and 4 (backlog-block scan for Closed/Resolved without
#   citation; entry-header uniqueness) run unchanged — both are
#   structural on the backlog file, independent of git history. This is
#   the contract scripts/pre-commit-gate.sh relies on when invoking the
#   lint at commit time.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKLOG="$REPO_ROOT/solo-orchestrator-backlog.md"

LIST_MODE=0
BASE_REF="origin/main"
PRE_COMMIT_MODE=0
PRE_COMMIT_MSG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --list)
      LIST_MODE=1
      shift
      ;;
    --base)
      if [ -z "${2:-}" ]; then
        echo "Usage: $0 [--list] [--base <ref>] [--pre-commit-mode [--message <text>]]" >&2
        exit 2
      fi
      BASE_REF="$2"
      shift 2
      ;;
    --pre-commit-mode)
      PRE_COMMIT_MODE=1
      shift
      ;;
    --message)
      if [ -z "${2:-}" ]; then
        echo "Usage: $0 [--list] [--base <ref>] [--pre-commit-mode [--message <text>]]" >&2
        exit 2
      fi
      PRE_COMMIT_MSG="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--list] [--base <ref>] [--pre-commit-mode [--message <text>]]" >&2
      exit 2
      ;;
  esac
done

# In pre-commit mode, if --message was not supplied, read the prospective
# commit message from stdin. The pre-commit-gate.sh PreToolUse path uses
# --message (it has parsed the message out of the Bash arg); the
# --terminal-mode path pipes .git/COMMIT_EDITMSG over stdin.
if [ "$PRE_COMMIT_MODE" -eq 1 ] && [ -z "$PRE_COMMIT_MSG" ]; then
  if [ -t 0 ]; then
    echo "lint-backlog-references: --pre-commit-mode requires --message <text> OR a message on stdin" >&2
    exit 2
  fi
  PRE_COMMIT_MSG=$(cat)
fi

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

# ── Step 2: Scan commit messages for BL references ─────────────────
# Two modes:
#   • Default: walk git log BASE..HEAD (CI / post-commit use).
#   • --pre-commit-mode: scan the single prospective message that
#     pre-commit-gate.sh supplied via --message or stdin. No git log
#     happens because the commit doesn't yet exist; the branch-scoped
#     ignore footer is honored within that single message body.
if [ "$PRE_COMMIT_MODE" -eq 1 ]; then
  # Single-message scan. The ignore footer is parsed from THIS message
  # so an operator can self-exempt placeholder tokens in the same
  # commit (no out-of-band amend needed).
  BRANCH_IGNORE=" $(printf '%s' "$PRE_COMMIT_MSG" \
    | grep -oiE 'lint-backlog-references-ignore:[[:space:]]*[A-Za-z0-9_,[:space:]-]+' \
    | sed -E 's/^[Ll]int-[Bb]acklog-[Rr]eferences-[Ii]gnore:[[:space:]]*//' \
    | tr ',' ' ' | tr '[:lower:]' '[:upper:]' | tr -s '[:space:]' ' ') "

  tokens=$(printf '%s' "$PRE_COMMIT_MSG" | grep -oiE 'BL-[0-9]+[a-z]?' | sort -u || true)
  if [ -n "$tokens" ]; then
    while IFS= read -r raw_tok; do
      [ -z "$raw_tok" ] && continue
      tok=$(normalize_id "$raw_tok")
      case "$BRANCH_IGNORE" in
        *" $tok "*)
          LIST_ROWS="${LIST_ROWS}PASS\tpre-commit\t${tok}\tin-message-ignore\n"
          continue
          ;;
      esac
      if is_valid_id "$tok"; then
        LIST_ROWS="${LIST_ROWS}PASS\tpre-commit\t${tok}\treferences existing backlog entry\n"
      else
        echo "lint-backlog-references: unknown BL reference '${tok}' in prospective commit message" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\tpre-commit\t${tok}\tunknown BL reference\n"
      fi
    done <<< "$tokens"
  fi
else
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
fi

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

# ── Step 4: entry-header UNIQUENESS ────────────────────────────────
# BL-207-HEADER-UNIQUENESS
#
# Every `BL-NNN` must own exactly ONE `^## BL-NNN:` header. Uniqueness
# is what makes the ID grep-able as this repo's citation primitive, and
# Step 3's block splitter assumes it: a second header for the same ID
# truncates the first block and opens a second one, so the citation
# check silently evaluates the wrong text. Structural on the file, so
# it runs in BOTH modes (like Step 3) — an operator adding a duplicate
# header is blocked at commit time, not only in CI.
#
# THREE DECISIONS, each pinned by a test in
# tests/test-lint-backlog-references.sh:
#
#   • NO exemption for preserved `Original entry (pre-close, kept for
#     audit trail):` blocks (T16). A duplicate is a duplicate wherever
#     it appears: the splitter above already reads an un-indented
#     `^## BL-NNN:` line inside such a block as a real entry header, so
#     exempting it here would make this arm disagree with the very
#     splitter it protects, and the audit-trail block would silently
#     capture the ID. Quoting a header inside an entry body is still
#     fine — indent or fence it and the `^` anchor skips it (T15).
#
#   • HEADERS ONLY, anchored (T15). Prose cross-references
#     ("supersedes BL-050") repeat by design and are never violations;
#     only the anchored header form is a key.
#
#   • The ID grammar is `BL-[0-9]+[a-z]?`, identical to Step 1's
#     valid-ID builder (T17). The narrower `^## BL-[0-9]+:` from the
#     BL-207 sketch would go blind to the `BL-003a` / `BL-003b` suffix
#     splits; the suffix is part of the ID, so those three are distinct
#     keys and must not be folded together. No case folding is applied
#     (unlike the commit-token path): the header regex only matches an
#     upper-case `BL-` with a lower-case suffix, so folding could not
#     merge anything and would only distort the ID in the diagnostic,
#     which reviewers grep for verbatim.
#
# BL-093 note: when the archive split lands, this arm must span BOTH
# files — an ID present in the main backlog AND the archive is the same
# defect.
#
# ONE awk pass emits both records: a `TOTAL` line (the header count, for
# the --list row) and a `DUP` line per duplicated ID. Deriving the total
# here rather than from a second `grep -c … || true` capture is
# deliberate — that capture is exactly the counter antipattern
# scripts/lint-counter-antipattern.sh exists to reject (it caught this
# during development). Duplicates are emitted in FIRST-HEADER order via
# the `order[]` index, not `for (k in seen)`, so output is deterministic
# without a `| sort` (awk's `in` iteration order is unspecified).
HEADER_SCAN=$(awk '
  {
    if (match($0, /^## BL-[0-9]+[a-z]?:/)) {
      # Drop the leading "## " (3 chars) and the trailing ":" (1 char).
      id = substr($0, 4, RLENGTH - 4)
      total = total + 1
      if (seen[id] == 0) { nids = nids + 1; order[nids] = id }
      seen[id] = seen[id] + 1
      if (at[id] == "") { at[id] = NR } else { at[id] = at[id] ", " NR }
    }
  }
  END {
    printf "TOTAL\t%d\n", total + 0
    for (i = 1; i <= nids; i++) {
      k = order[i]
      if (seen[k] > 1) printf "DUP\t%s\t%d\t%s\n", k, seen[k], at[k]
    }
  }
' "$BACKLOG")

HEADER_TOTAL=0
HEADER_DUPES=0
while IFS=$'\t' read -r rec_kind rec_id rec_count rec_lines; do
  case "$rec_kind" in
    TOTAL)
      HEADER_TOTAL="$rec_id"
      ;;
    DUP)
      # ASCII-only diagnostic: no multibyte char adjacent to an expansion.
      echo "lint-backlog-references: duplicate entry header '${rec_id}': ${rec_count} headers at lines ${rec_lines}; each BL-NNN must have exactly one '## BL-NNN:' header (indent or fence a header quoted inside an entry body)" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      HEADER_DUPES=$((HEADER_DUPES + 1))
      LIST_ROWS="${LIST_ROWS}FAIL\theader-uniqueness\t${rec_id}\tduplicate header at lines ${rec_lines}\n"
      ;;
  esac
done <<< "$HEADER_SCAN"

if [ "$HEADER_DUPES" -eq 0 ]; then
  LIST_ROWS="${LIST_ROWS}PASS\theader-uniqueness\t-\t${HEADER_TOTAL} BL header(s), all unique\n"
fi

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

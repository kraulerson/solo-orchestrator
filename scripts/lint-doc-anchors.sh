#!/usr/bin/env bash
# scripts/lint-doc-anchors.sh — fail CI when a markdown file under
# docs/ contains an in-document anchor link (`[text](#anchor)`) whose
# target heading doesn't exist in that same file. Structural backstop
# for the BL-048 dead-anchor defect class (closes BL-048).
#
# THE DEFECT CLASS
#   Docs accrete section renumbering, heading rewording, and
#   copy-pasted TOC/cross-reference links over time. An in-doc anchor
#   link like `[Section 6](#6-claudemd)` silently stops resolving the
#   moment the target heading's rendered text changes (GitHub derives
#   the anchor slug from the *current* heading text) — nothing fails
#   locally, the link just quietly 404s in the rendered page. Nobody
#   notices until a reader clicks it.
#
# WHAT COUNTS AS AN ANCHOR TARGET
#   Every ATX heading (`#` through `######`) in a file, outside fenced
#   code blocks, contributes one GitHub-derived anchor slug:
#     1. Strip backtick / `*` markdown emphasis markers (keep the
#        enclosed text).
#     2. Lowercase.
#     3. Strip everything except [a-z0-9 _-].
#     4. Replace each space with a hyphen.
#     5. Duplicate headings (same slug appears more than once in the
#        same file) get `-1`, `-2`, ... suffixes on the 2nd, 3rd, ...
#        occurrence, matching GitHub's own de-duplication rule.
#   Headings inside fenced code blocks (```` ``` ````-delimited, e.g. an
#   example CLAUDE.md template shown inline) are NOT real headings of
#   the file and are excluded from both heading collection and
#   reference scanning.
#
# WHAT COUNTS AS A REFERENCE
#   Any `](#...)` occurrence outside a fenced code block, on any line
#   of any *.md file under docs/ (recursive). Only same-file anchors
#   are in scope — `[text](other.md#anchor)` targets a different file
#   and is out of scope for this linter (it never matches the `](#`
#   prefix this script looks for).
#
# THE BL-090 CROSS-FILE ARM (2026-07-21, Karl's decision: EXTEND this
# lint rather than build a sibling — one doc-integrity tool)
#   Every relative `](path)` reference must resolve from the referencing
#   file's directory. URLs, mailto:, absolute paths, bare #anchors, and
#   fenced code are out of scope; `path#anchor` checks the FILE half
#   (target-anchor validation is a later, corpus-calibrated rung).
#   MEASURED ROLLOUT: warn-only by default (`warn:` lines; exit code
#   untouched) — escalate with --strict-refs once the warning population
#   stays at zero. Dogfood baseline 2026-07-21: 140 relative refs across
#   81 files, ZERO warnings. Inline exemption: a literal `(planned)` on
#   the referencing line marks a deliberately unwritten target.
#   Ghost IDENTIFIER citations (ADR-0003-style) are steps 2-3 of BL-090,
#   blocked on the Pantheon FP-calibration corpus — not in this arm.
#
# EXIT CODES
#   0 — no broken anchors found (ref warnings alone do not fail).
#   1 — broken anchor(s) found, OR --strict-refs with ref warnings.
#   2 — invocation / I/O error.
#
# USAGE
#   bash scripts/lint-doc-anchors.sh           # quiet pass/fail
#   bash scripts/lint-doc-anchors.sh --list    # PASS/FAIL table
#   bash scripts/lint-doc-anchors.sh --strict-refs   # ref warns fail too
#   bash scripts/lint-doc-anchors.sh --docs-dir DIR   # test-mode: scan
#       an alternate directory (used by tests/test-lint-doc-anchors.sh)
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2 as /bin/bash and every caller here (pre-commit
#   gate, CI) invokes this script through /usr/bin/env bash, which
#   resolves to /bin/bash on a default Mac. No associative arrays, no
#   `${var,,}` case-conversion expansion (bash 4+ only) — lowercasing
#   goes through `tr`. Anchor sets are tracked as pipe-delimited
#   strings and plain indexed arrays, mirroring the pattern in
#   scripts/lint-tests-registered.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_PATH="$REPO_ROOT/scripts/lint-doc-anchors.sh"

LIST_MODE=0
DOCS_DIR_OVERRIDE=""

STRICT_REFS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST_MODE=1; shift ;;
    --strict-refs) STRICT_REFS=1; shift ;;
    --docs-dir)
      [ $# -ge 2 ] || { echo "Usage: $0 [--list] [--strict-refs] [--docs-dir DIR]" >&2; exit 2; }
      DOCS_DIR_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--list] [--strict-refs] [--docs-dir DIR]"; exit 0 ;;
    *) echo "Usage: $0 [--list] [--strict-refs] [--docs-dir DIR]" >&2; exit 2 ;;
  esac
done

DOCS_DIR="${DOCS_DIR_OVERRIDE:-$REPO_ROOT/docs}"

if [ ! -d "$DOCS_DIR" ]; then
  echo "lint-doc-anchors: docs dir not found: $DOCS_DIR" >&2
  exit 2
fi

VIOLATIONS=0
REF_WARNINGS=0
LIST_ROWS=""
FILES_SCANNED=0

# ── slugify: GitHub-derived anchor slug for one heading's text. ─────
# Args: $1 = raw heading text (with leading #'s and one space already
#            stripped by the caller).
# Echoes the slug on stdout.
slugify() {
  local text="$1" out
  # Strip inline-code backticks and bold/italic asterisks, keeping the
  # enclosed text (GitHub anchors are derived from rendered text, not
  # markdown source syntax).
  out="${text//\`/}"
  out="${out//\*/}"
  # Strip a trailing ATX closing-hash sequence ("## Heading ##").
  out="$(printf '%s' "$out" | sed -E 's/[[:space:]]*#+[[:space:]]*$//')"
  # Lowercase (bash 3.2 has no ${var,,} — use tr).
  out="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
  # Strip everything except a-z 0-9 space hyphen underscore.
  out="$(printf '%s' "$out" | sed -E 's/[^a-z0-9 _-]//g')"
  # Spaces -> hyphens.
  out="${out// /-}"
  printf '%s' "$out"
}

# ── process_file: collect headings (pass 1) then scan references
# (pass 2) for a single markdown file. Reports violations directly.
process_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  local rel
  rel="${file#"$REPO_ROOT"/}"
  [ "$rel" = "$file" ] && rel="$file"   # test-mode fixture outside REPO_ROOT

  # Slurp lines into an array (preserves blank lines; avoids a
  # subshell-per-line read loop for the whole file).
  local -a LINES=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    LINES+=("$line")
  done < "$file"
  local n=${#LINES[@]}

  FILES_SCANNED=$((FILES_SCANNED + 1))

  # ── Pass 1: collect anchors, fence-aware, with GitHub dedup rule. ──
  local ANCHORS_STR="|"
  local -a BASE_SLUGS_SEEN=()
  local in_fence=0
  local i
  for ((i = 0; i < n; i++)); do
    line="${LINES[i]}"
    if [[ "$line" =~ ^[[:space:]]*'```' ]]; then
      in_fence=$((1 - in_fence))
      continue
    fi
    [ "$in_fence" -eq 1 ] && continue

    if [[ "$line" =~ ^#{1,6}[[:space:]]+(.+)$ ]]; then
      local heading_text="${BASH_REMATCH[1]}"
      local base_slug
      base_slug="$(slugify "$heading_text")"
      [ -n "$base_slug" ] || continue

      # GitHub de-dup: count how many times this exact base slug has
      # already appeared earlier in the file; 2nd+ occurrence gets a
      # -N suffix.
      local prior=0
      local seen
      for seen in "${BASE_SLUGS_SEEN[@]:-}"; do
        [ "$seen" = "$base_slug" ] && prior=$((prior + 1))
      done
      local final_slug="$base_slug"
      [ "$prior" -gt 0 ] && final_slug="${base_slug}-${prior}"

      BASE_SLUGS_SEEN+=("$base_slug")
      case "$ANCHORS_STR" in
        *"|${final_slug}|"*) ;;
        *) ANCHORS_STR="${ANCHORS_STR}${final_slug}|" ;;
      esac
    fi
  done

  # ── Pass 2: scan for `](#anchor)` references, fence-aware. ─────────
  in_fence=0
  for ((i = 0; i < n; i++)); do
    line="${LINES[i]}"
    if [[ "$line" =~ ^[[:space:]]*'```' ]]; then
      in_fence=$((1 - in_fence))
      continue
    fi
    [ "$in_fence" -eq 1 ] && continue

    # BL-090-DOC-REFS-BEGIN
    # Cross-file reference arm (BL-090 step 1, Karl's 2026-07-20 decision:
    # EXTEND this lint — one doc-integrity tool, not two drifting halves).
    # Every `](path)` whose path is a RELATIVE file reference must resolve
    # from the referencing file's directory. Out of scope by design: URLs
    # (scheme://, mailto:), absolute paths, bare #anchors, fenced code
    # (already skipped above). A `#suffix` is split off and the FILE half
    # checked (target-anchor validation is the calibrated later rung).
    # MEASURED ROLLOUT: warn-only by default — the exit code is untouched
    # unless --strict-refs; escalate after the warning population is
    # dogfooded to zero. Inline exemption: a literal `(planned)` on the
    # referencing line marks a deliberately not-yet-written target.
    case "$line" in
      *']('*)
        local ref_lineno=$((i + 1))
        local ref_rest="$line" ref_target ref_file
        case "$line" in *'(planned)'*) ref_rest="" ;; esac
        while [[ "$ref_rest" == *']('* ]]; do
          ref_rest="${ref_rest#*](}"
          ref_target="${ref_rest%%)*}"
          ref_rest="${ref_rest#"$ref_target"}"
          [ -n "$ref_target" ] || continue
          case "$ref_target" in
            '#'*) continue ;;                          # same-file anchor — the original arm owns it
            *'://'*|mailto:*|/*) continue ;;           # URL / absolute — out of scope
          esac
          ref_file="${ref_target%%#*}"
          [ -n "$ref_file" ] || continue
          if [ ! -e "$(dirname "$file")/$ref_file" ]; then
            echo "warn: ${rel}:${ref_lineno} unresolved relative reference '${ref_file}' (BL-090; append '(planned)' on the line if the target is deliberately not written yet)" >&2
            REF_WARNINGS=$((REF_WARNINGS + 1))
            LIST_ROWS="${LIST_ROWS}WARN\t${rel}:${ref_lineno}\t${ref_file}\n"
          fi
        done
        ;;
    esac
    # BL-090-DOC-REFS-END

    case "$line" in
      *'](#'*)
        local lineno=$((i + 1))
        local rest="$line"
        local match anchor
        # Extract every `](#...)` occurrence on this line.
        while [[ "$rest" == *'](#'* ]]; do
          rest="${rest#*](#}"
          anchor="${rest%%)*}"
          rest="${rest#"$anchor"}"
          [ -n "$anchor" ] || continue
          case "$ANCHORS_STR" in
            *"|${anchor}|"*)
              LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\t#${anchor}\n"
              ;;
            *)
              echo "${rel}:${lineno} broken anchor #${anchor}" >&2
              VIOLATIONS=$((VIOLATIONS + 1))
              LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\t#${anchor}\n"
              ;;
          esac
        done
        ;;
    esac
  done
}

# ── Enumerate every *.md file under DOCS_DIR, recursively. ───────────
while IFS= read -r -d '' f; do
  process_file "$f"
done < <(find "$DOCS_DIR" -type f -name '*.md' -print0 | sort -z)

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\tANCHOR\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS broken anchor(s) found across $FILES_SCANNED file(s). Fix each link to point at the heading's current GitHub-derived slug (see scripts/lint-doc-anchors.sh header)." >&2
  exit 1
fi

if [ "$REF_WARNINGS" -gt 0 ]; then
  echo "" >&2
  echo "$REF_WARNINGS unresolved relative reference(s) across $FILES_SCANNED file(s) — WARN-tier (BL-090 measured rollout; does not fail the lint$( [ "$STRICT_REFS" -eq 1 ] && printf '%s' " — but --strict-refs is set, failing" )). " >&2
  if [ "$STRICT_REFS" -eq 1 ]; then
    exit 1
  fi
fi

echo "OK: no broken in-document anchors across $FILES_SCANNED markdown file(s) under ${DOCS_DIR#"$REPO_ROOT"/}."
exit 0

#!/usr/bin/env bash
# scripts/lint-bl-markers.sh — BL-196 structural backstop for the repo's
# citation primitive: the grep-able `# BL-NNN-…` marker comment.
#
# THE DEFECT CLASS
#   CLAUDE.md § CITATION RULE makes the marker comment load-bearing: cite
#   code by a marker or a function name, NEVER by a bare file:line,
#   because line numbers mis-resolve within 24h. That makes every marker
#   an interface — and until this lint nothing validated it. A marker that
#   is renamed, typo'd, or deleted silently breaks every document that
#   points at it, and no lint, test or gate noticed. The worked example is
#   on `## BL-196:`: a marker cited in a closure paragraph was reported to
#   "exist nowhere", which was true of one commit and false of the commit
#   14 minutes later — a marker claim is stamped with a TREE, and the only
#   way to keep the stamp honest is to re-resolve it on every push.
#
# THE THREE PASSES (the shape `## BL-196:` prescribes)
#   (a) MARKER -> ENTRY. Every `# BL-NNN-…` marker comment in the code
#       surface names a `BL-NNN` that has a `## BL-NNN:` entry in
#       solo-orchestrator-backlog.md. Catches a marker minted against a
#       typo'd or nonexistent entry id.
#   (b) CITE -> MARKER. Every marker CITATION in the live prose surface
#       resolves to a marker token that actually exists in the code
#       surface. This is the core defect class: a cite in prose naming a
#       marker that no longer exists in code.
#   (c) VACUITY FLOOR. If either grep breaks (a regex edit, a moved
#       directory, a renamed surface), the scan would find nothing and
#       "pass". Floors on the two populations turn a silent no-op into a
#       loud exit 2. Measured on this branch, 2026-07-31: 280 marker
#       tokens in the code surface, 368 citations in the prose surface.
#       The floors sit well below both so ordinary churn never trips them.
#
# THE CODE SURFACE (where a marker is DEFINED)
#   init.sh, scripts/, tests/, templates/, evaluation-prompts/, .github/ —
#   every file, any extension. These are the tree's executable and shipped
#   artifacts; a marker occurring in one of them is greppable and alive.
#   `## BL-196:` names only scripts/, tests/ and init.sh; the other three
#   are added because measurement found real marker families living there
#   (`# BL-128-*` in evaluation-prompts/Projects/run-reviews.sh,
#   `# BL-160-AUDIT-SCOPE` in templates/pipelines/ci/**) that a narrower
#   surface would have reported as broken citations. Widening the surface
#   makes pass (b) STRICTLY more conservative and leaves pass (a) green.
#
#   SELF-EXCLUSION: this script excludes ITSELF from the code surface. Its
#   allowlist below names withdrawn markers verbatim, and a lint that can
#   satisfy its own resolution check by mentioning a token in its own
#   allowlist would be self-certifying. Nothing else is excluded.
#
# THE PROSE SURFACE (where a marker is CITED)
#   CLAUDE.md, README.md, CONTRIBUTING.md, solo-orchestrator-backlog.md,
#   and docs/**/*.md EXCEPT docs/handoffs/archive/**.
#
#   DELIBERATELY OUT OF SCOPE, and why — these are FROZEN artifacts, dated
#   and stamped to the tree they were written against. Editing one to
#   satisfy a lint would falsify the record, so a lint that reds on one is
#   pure cry-wolf:
#     • Reports/**                 — dogfood / audit run artifacts.
#     • docs/handoffs/archive/**   — superseded or fully-executed handoffs
#                                    (docs/handoffs/archive/README.md says
#                                    so explicitly).
#     • solo-orchestrator-bugs.md  — every entry is Fixed or Superseded by
#                                    construction; there is no live half.
#   CLOSED backlog entries ARE scanned. They are audit trail and must never
#   be deleted, but they are also where the BL-179 misattribution the entry
#   documents actually happened, and they sit in a file that is edited every
#   day — so a break there is both reachable and worth naming. Nothing in
#   this repo's closed entries is broken today except the two allowlisted
#   tokens below.
#
# WHAT COUNTS AS A CITATION (deliberately narrow — measured, not asserted)
#   Only a token that prose has explicitly marked as CODE:
#     1. backticked:      `BL-084-TIER-KEY`  or  `# BL-084-TIER-KEY`
#     2. hash-prefixed:   # BL-112-SCAN-COVERAGE   (unbackticked, as it
#                         appears mid-sentence in several entries)
#   A BARE unbackticked, unhashed token is NOT a citation. Measured over
#   the whole prose surface (2026-07-31): 389 marker-shaped tokens, of
#   which 368 carry one of the two explicit shapes and 21 are bare. ELEVEN
#   of those 21 are ordinary prose hyphenation, not citations at all —
#   BL-140-family, BL-137-class, BL-122-correct, BL-030-edit, BL-090-style,
#   BL-101-generator (left unbackticked HERE too, for the same reason).
#   Treating the bare shape as a citation would make this lint a cry-wolf
#   machine on day one.
#   NAMED RESIDUAL, since the trade is not free: the other TEN bare hits
#   ARE real markers written without backticks (BL-084-TIER-KEY,
#   BL-073-ESCALATE, BL-107-UNIVERSAL-INSTALL, BL-170-APPEND-DESIGN, …)
#   and this lint does not check them. Backtick a marker and it becomes
#   enforced; the fix for the residual is to backtick, not to widen the
#   regex — widening cannot separate the two halves, the shapes are
#   identical.
#
#   `# BL-NNN-…` (the literal placeholder CLAUDE.md uses to describe the
#   convention) never matches: `NNN` is not digits.
#
# HOW A CITATION RESOLVES
#   • EXACT: the token appears verbatim somewhere in the code surface.
#   • FAMILY: `TOKEN-` prefixes some code token. This is what makes a cite
#     of a FENCE family resolve — prose writes `# BL-105-PHASE4-GATE` while
#     the code carries `-BEGIN` / `-END` — and what makes the glob form
#     `# BL-102-MARKET-SIGNAL-*` resolve. A trailing `-` or `*` on the
#     cited token is stripped before lookup for the same reason. Note the
#     family rule requires the HYPHEN: a truncation typo (`…-TIER-KE` for
#     `…-TIER-KEY`) still fails, because `BL-084-TIER-KE-` prefixes nothing.
#
# ALLOWLIST — two mechanisms, both requiring a reason
#   1. INLINE, preferred: put `<!-- lint-bl-markers: allow <reason> -->`
#      (or `# lint-bl-markers: allow <reason>` in code) on the CITING line.
#      An empty reason FAILS, matching the allowlist semantics of
#      lint-counter-antipattern.sh and lint-backlog-references.sh.
#   2. SCRIPT-LEVEL, for cites in a file this change may not edit: the
#      ALLOWLIST table below. Every row carries its reason and is rendered
#      in --list, so it is reviewable.
#
# EXIT CODES
#   0 — every marker resolves to an entry and every citation to a marker.
#   1 — one or more violations found.
#   2 — invocation / I/O error, OR the vacuity floor tripped (pass c).
#
# USAGE
#   bash scripts/lint-bl-markers.sh              # quiet pass/fail
#   bash scripts/lint-bl-markers.sh --list       # PASS/FAIL table
#   bash scripts/lint-bl-markers.sh --root DIR   # test-mode: scan an
#       alternate tree (used by tests/test-lint-bl-markers.sh). Under
#       --root the vacuity floors default to 0 — a fixture is SUPPOSED to
#       be small — and can be raised explicitly with the two flags below
#       so the floor itself stays testable.
#   bash scripts/lint-bl-markers.sh --min-markers N --min-cites N
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2.57 as /bin/bash. No associative arrays, no
#   ${var,,}, no `((x++))` under set -e. Sets are temp files; the two
#   resolution joins are single awk passes over two files (the NR==FNR
#   trick), so no shell variable is ever interpolated into an awk
#   program — awk reads its inputs, never `-v`.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_REL="scripts/lint-bl-markers.sh"

LIST_MODE=0
ROOT_OVERRIDE=""
MIN_MARKERS=""
MIN_CITES=""

USAGE="Usage: $0 [--list] [--root DIR] [--min-markers N] [--min-cites N]"

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST_MODE=1; shift ;;
    --root)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      ROOT_OVERRIDE="$2"; shift 2 ;;
    --min-markers)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      MIN_MARKERS="$2"; shift 2 ;;
    --min-cites)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      MIN_CITES="$2"; shift 2 ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done

ROOT="${ROOT_OVERRIDE:-$REPO_ROOT}"

if [ ! -d "$ROOT" ]; then
  echo "lint-bl-markers: root not found: $ROOT" >&2
  exit 2
fi
# Canonicalize: every relative path in this script is produced by stripping
# "$ROOT/" off a find(1) result, so a trailing slash or a relative --root
# would leave the prefix un-stripped and every reported path absolute.
ROOT="$(cd "$ROOT" && pwd)" || { echo "lint-bl-markers: cannot enter root: $ROOT" >&2; exit 2; }

# Vacuity floors (pass c). Real-tree defaults sit well below the measured
# populations (280 markers / 368 citations, 2026-07-31); a fixture tree
# under --root defaults to 0 and raises them explicitly.
if [ -z "$MIN_MARKERS" ]; then
  if [ -n "$ROOT_OVERRIDE" ]; then MIN_MARKERS=0; else MIN_MARKERS=50; fi
fi
if [ -z "$MIN_CITES" ]; then
  if [ -n "$ROOT_OVERRIDE" ]; then MIN_CITES=0; else MIN_CITES=25; fi
fi
case "$MIN_MARKERS" in ''|*[!0-9]*) echo "$USAGE" >&2; exit 2 ;; esac
case "$MIN_CITES"   in ''|*[!0-9]*) echo "$USAGE" >&2; exit 2 ;; esac

BACKLOG="$ROOT/solo-orchestrator-backlog.md"
if [ ! -f "$BACKLOG" ]; then
  echo "lint-bl-markers: backlog not found at $BACKLOG" >&2
  exit 2
fi

TMPD=$(mktemp -d) || { echo "lint-bl-markers: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# ── BL-196-ALLOWLIST-BEGIN ──────────────────────────────────────────────
# Script-level allowlist: `TOKEN|reason`. Used only where the citing file
# is one this change will not rewrite to satisfy a lint. Every row is
# rendered by --list.
#
# The two rows below are the ONLY broken citations on the tree as of
# 2026-07-31, and both are deliberate: `## BL-192:` records that the
# BL-186 parse-coverage clause and its five test cases were WITHDRAWN from
# main and live on the unmerged branch `fix/bl112-sast-scan-coverage`
# (`e87dbd3`), to be restored only with a decode check that does not
# depend on semgrep's `Parsed lines`. Entries BL-186, BL-189 and BL-192
# all cite them as not-on-this-tree on purpose. That is BL-196's own
# lesson — a marker claim is stamped with a tree — so the citations are
# correct and it is this lint that must yield. Delete these rows when the
# branch merges (they then resolve by exact match) or when the entries are
# rewritten.
ALLOWLIST="
BL-186-PARSE-COVERAGE|withdrawn to unmerged branch fix/bl112-sast-scan-coverage (e87dbd3) per BL-192; cited as not-on-this-tree on purpose
BL-186-EMPTY-TARGETS|withdrawn to unmerged branch fix/bl112-sast-scan-coverage (e87dbd3) per BL-192; cited as not-on-this-tree on purpose
"
allow_reason_for() {
  printf '%s\n' "$ALLOWLIST" | while IFS='|' read -r a_tok a_reason; do
    [ -n "$a_tok" ] || continue
    if [ "$a_tok" = "$1" ]; then printf '%s' "$a_reason"; break; fi
  done
}
# ── BL-196-ALLOWLIST-END ────────────────────────────────────────────────

# ── Enumerate the code surface (paths RELATIVE to ROOT) ─────────────────
CODE_SURFACE="init.sh scripts tests templates evaluation-prompts .github"
CODE_FILES="$TMPD/code-files"
: > "$CODE_FILES"
for surface_entry in $CODE_SURFACE; do
  target="$ROOT/$surface_entry"
  if [ -f "$target" ]; then
    printf '%s\n' "$surface_entry" >> "$CODE_FILES"
  elif [ -d "$target" ]; then
    while IFS= read -r found; do
      [ -n "$found" ] || continue
      printf '%s\n' "${found#"$ROOT"/}" >> "$CODE_FILES"
    done < <(find "$target" -type f -print 2>/dev/null)
  fi
done
# Self-exclusion (see header): this script's own allowlist names tokens
# verbatim; letting it define them would make the lint self-certifying.
if [ -s "$CODE_FILES" ]; then
  grep -vxF "$SELF_REL" "$CODE_FILES" > "$CODE_FILES.keep"
  mv "$CODE_FILES.keep" "$CODE_FILES"
fi
# Drop binary and empty files in ONE pass. grep -I skips binaries and the
# empty pattern matches every line of every text file, so what survives is
# exactly the set awk can safely read. Without this a stray .DS_Store (or
# any committed blob) is handed to awk, which has no binary guard of its
# own and could emit a garbage row. Cost is one extra scan, not one
# subprocess per file.
if [ -s "$CODE_FILES" ]; then
  ( cd "$ROOT" && tr '\n' '\0' < "$CODE_FILES" | xargs -0 grep -lI '' 2>/dev/null ) \
    | sort -u > "$CODE_FILES.keep"
  mv "$CODE_FILES.keep" "$CODE_FILES"
fi

# ── Set 1: every marker TOKEN present anywhere in the code surface ──────
MARKER_TOKENS="$TMPD/marker-tokens"
: > "$MARKER_TOKENS"
if [ -s "$CODE_FILES" ]; then
  ( cd "$ROOT" && tr '\n' '\0' < "$CODE_FILES" \
      | xargs -0 grep -hoIE 'BL-[0-9]+[a-z]?-[A-Za-z][A-Za-z0-9_-]*' 2>/dev/null ) \
    | sort -u > "$MARKER_TOKENS"
fi

MARKER_COUNT=$(grep -c . "$MARKER_TOKENS" 2>/dev/null) || MARKER_COUNT=0
case "$MARKER_COUNT" in ''|*[!0-9]*) MARKER_COUNT=0 ;; esac

# ── Set 2: every `## BL-NNN:` entry id in the backlog ────────────────────
ENTRY_IDS="$TMPD/entry-ids"
grep -oE '^## BL-[0-9]+[a-z]?:' "$BACKLOG" 2>/dev/null \
  | sed -e 's/^## //' -e 's/:$//' | sort -u > "$ENTRY_IDS"

VIOLATIONS=0
LIST_ROWS=""
PROSE_CITES=0

# ── PASS (a): every `# BL-NNN-…` marker names an existing entry ──────────
# The DEFINITION shape is the hash-comment one only — a bare token inside
# a string or a grep pattern is a reference, not a minting. Emits
# `file<TAB>line<TAB>BL-NNN`.
EXTRACT_DEFS="$TMPD/extract-defs.awk"
cat > "$EXTRACT_DEFS" <<'AWK'
{
  # The HTML comment closer is stripped before the reason is measured, so
  # `<!-- lint-bl-markers: allow -->` reads as EMPTY and not as the reason
  # "-->" — an empty reason must fail, per the house allowlist semantics.
  probe = $0
  gsub(/-->/, "", probe)
  if (probe ~ /lint-bl-markers:[ \t]*allow[ \t]+[^ \t]/) next
  line = $0
  while (match(line, /#[[:space:]]*BL-[0-9]+[a-z]?-[A-Za-z][A-Za-z0-9_-]*/)) {
    tok = substr(line, RSTART, RLENGTH)
    line = substr(line, RSTART + RLENGTH)
    sub(/^#[[:space:]]*/, "", tok)
    if (match(tok, /^BL-[0-9]+[a-z]?/)) {
      print FILENAME "\t" FNR "\t" substr(tok, 1, RLENGTH)
    }
  }
}
AWK

MARKER_SITES="$TMPD/marker-sites"
: > "$MARKER_SITES"
if [ -s "$CODE_FILES" ]; then
  ( cd "$ROOT" && tr '\n' '\0' < "$CODE_FILES" \
      | xargs -0 awk -f "$EXTRACT_DEFS" 2>/dev/null ) > "$MARKER_SITES"
fi

UNKNOWN_ENTRY_SITES="$TMPD/unknown-entry-sites"
awk -F'\t' 'NR==FNR { ent[$1]=1; next } !($3 in ent)' \
  "$ENTRY_IDS" "$MARKER_SITES" > "$UNKNOWN_ENTRY_SITES"

while IFS=$'\t' read -r m_file m_line m_id; do
  [ -n "${m_id:-}" ] || continue
  echo "lint-bl-markers: ${m_file}:${m_line} marker names ${m_id}, which has no '## ${m_id}:' entry in solo-orchestrator-backlog.md" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
  LIST_ROWS="${LIST_ROWS}FAIL\tmarker->entry\t${m_file}:${m_line}\t${m_id}\tno backlog entry\n"
done < "$UNKNOWN_ENTRY_SITES"

# ── BL-196-PROSE-CITE-BEGIN ─────────────────────────────────────────────
# PASS (b): every marker CITATION in the live prose surface resolves to a
# marker token in the code surface. THIS IS THE CORE DEFECT CLASS of
# BL-196 — a cite in prose naming a marker that no longer exists in code.
# The whole check lives inside this fence; tests/test-lint-bl-markers.sh
# excises the fence and proves the broken-cite fixture then passes.
EXTRACT_CITES="$TMPD/extract-cites.awk"
cat > "$EXTRACT_CITES" <<'AWK'
{
  ann = "-"
  # See EXTRACT_DEFS: strip the HTML comment closer before measuring the
  # reason, or `<!-- lint-bl-markers: allow -->` self-approves with "-->".
  probe = $0
  gsub(/-->/, "", probe)
  if (probe ~ /lint-bl-markers:[ \t]*allow[ \t]+[^ \t]/) ann = "allow"
  else if (probe ~ /lint-bl-markers:[ \t]*allow/)        ann = "allow-empty"
  line = $0
  while (match(line, /`[[:space:]]*#?[[:space:]]*BL-[0-9]+[a-z]?-[A-Za-z][A-Za-z0-9_*-]*`|#[[:space:]]*BL-[0-9]+[a-z]?-[A-Za-z][A-Za-z0-9_*-]*/)) {
    tok = substr(line, RSTART, RLENGTH)
    line = substr(line, RSTART + RLENGTH)
    gsub(/`/, "", tok)
    sub(/^[[:space:]]*#?[[:space:]]*/, "", tok)
    sub(/[-*]+$/, "", tok)
    print FILENAME "\t" FNR "\t" tok "\t" ann
  }
}
AWK

PROSE_FILES="$TMPD/prose-files"
: > "$PROSE_FILES"
for prose_entry in CLAUDE.md README.md CONTRIBUTING.md solo-orchestrator-backlog.md; do
  [ -f "$ROOT/$prose_entry" ] && printf '%s\n' "$prose_entry" >> "$PROSE_FILES"
done
if [ -d "$ROOT/docs" ]; then
  while IFS= read -r found; do
    [ -n "$found" ] || continue
    rel="${found#"$ROOT"/}"
    case "$rel" in docs/handoffs/archive/*) continue ;; esac
    printf '%s\n' "$rel" >> "$PROSE_FILES"
  done < <(find "$ROOT/docs" -type f -name '*.md' -print 2>/dev/null)
fi
sort -u "$PROSE_FILES" -o "$PROSE_FILES"

CITES="$TMPD/cites"
: > "$CITES"
if [ -s "$PROSE_FILES" ]; then
  ( cd "$ROOT" && tr '\n' '\0' < "$PROSE_FILES" \
      | xargs -0 awk -f "$EXTRACT_CITES" 2>/dev/null ) > "$CITES"
fi

PROSE_CITES=$(grep -c . "$CITES" 2>/dev/null) || PROSE_CITES=0
case "$PROSE_CITES" in ''|*[!0-9]*) PROSE_CITES=0 ;; esac

# Resolution join: EXACT match, else FAMILY match (`TOKEN-` prefixes a
# known code token). Emits `verdict<TAB>file<TAB>line<TAB>token<TAB>ann`.
RESOLVED="$TMPD/cites-resolved"
awk -F'\t' '
  NR==FNR { n++; toks[n] = $1; tok[$1] = 1; next }
  {
    verdict = "MISS"
    if ($3 in tok) verdict = "EXACT"
    else {
      pfx = $3 "-"
      for (i = 1; i <= n; i++) {
        if (index(toks[i], pfx) == 1) { verdict = "FAMILY"; break }
      }
    }
    print verdict "\t" $1 "\t" $2 "\t" $3 "\t" $4
  }
' "$MARKER_TOKENS" "$CITES" > "$RESOLVED"

while IFS=$'\t' read -r c_verdict c_file c_line c_tok c_ann; do
  [ -n "${c_tok:-}" ] || continue
  case "$c_verdict" in
    EXACT|FAMILY)
      LIST_ROWS="${LIST_ROWS}PASS\tcite->marker\t${c_file}:${c_line}\t${c_tok}\tresolved (${c_verdict})\n"
      continue
      ;;
  esac
  if [ "$c_ann" = "allow" ]; then
    LIST_ROWS="${LIST_ROWS}PASS\tcite->marker\t${c_file}:${c_line}\t${c_tok}\tinline-allow\n"
    continue
  fi
  if [ "$c_ann" = "allow-empty" ]; then
    echo "lint-bl-markers: ${c_file}:${c_line} '${c_tok}' has an EMPTY allowlist reason (use 'lint-bl-markers: allow <reason>')" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
    LIST_ROWS="${LIST_ROWS}FAIL\tcite->marker\t${c_file}:${c_line}\t${c_tok}\tallowlist-empty-reason\n"
    continue
  fi
  c_reason=$(allow_reason_for "$c_tok")
  if [ -n "$c_reason" ]; then
    LIST_ROWS="${LIST_ROWS}PASS\tcite->marker\t${c_file}:${c_line}\t${c_tok}\tallowlist: ${c_reason}\n"
    continue
  fi
  echo "lint-bl-markers: ${c_file}:${c_line} cites marker '# ${c_tok}' but no such marker exists in the code surface (init.sh, scripts/, tests/, templates/, evaluation-prompts/, .github/)" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
  LIST_ROWS="${LIST_ROWS}FAIL\tcite->marker\t${c_file}:${c_line}\t${c_tok}\tbroken citation\n"
done < "$RESOLVED"
# ── BL-196-PROSE-CITE-END ───────────────────────────────────────────────

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tPASS\tFILE:LINE\tTOKEN\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
  printf 'INFO\tpopulation\t-\t-\t%s marker token(s) in the code surface, %s citation(s) in the prose surface\n' \
    "$MARKER_COUNT" "$PROSE_CITES"
fi

# ── PASS (c): vacuity floor ─────────────────────────────────────────────
# A broken regex or a moved directory makes both populations collapse to
# zero, and a lint with nothing to check "passes". Refuse to.
if [ "$MARKER_COUNT" -lt "$MIN_MARKERS" ] || [ "$PROSE_CITES" -lt "$MIN_CITES" ]; then
  echo "" >&2
  echo "lint-bl-markers: VACUOUS SCAN — found $MARKER_COUNT marker token(s) (floor $MIN_MARKERS) and $PROSE_CITES citation(s) (floor $MIN_CITES)." >&2
  echo "The scan collapsed, so a pass would be meaningless. Check the code/prose surface lists and the extraction regexes in this script." >&2
  exit 2
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS marker-citation violation(s). Re-grep each cited marker; if it moved, update the citing prose — if it was deliberately withdrawn, allowlist it with a reason (see scripts/lint-bl-markers.sh header)." >&2
  exit 1
fi

echo "OK: $MARKER_COUNT marker token(s) resolve to backlog entries and $PROSE_CITES prose citation(s) resolve to live markers."
exit 0

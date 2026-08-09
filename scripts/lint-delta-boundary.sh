#!/usr/bin/env bash
# scripts/lint-delta-boundary.sh — the dependency-direction boundary lint for
# the post-MVP delta track.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §3.3 (normative), with the
# module inventory at §3.1 and the build-plan row at §11-WP1. Settled decision
# D1 requires this lint FROM THE FIRST COMMIT, which is why it lands alongside
# the first module file rather than at the end of the track.
#
# (Deliberately NO `# BL-NNN-…` marker: no backlog entry exists for the delta
# build, and CLAUDE.md's citation rule is satisfied by the design-doc path
# above plus the grep-able `DELTA-BOUNDARY-*` fences below. Do not mint a BL
# marker here — scripts/lint-bl-markers.sh would red on an id nobody filed.)
#
# THE DEFECT CLASS
#   A severable module stops being severable one convenience call at a time.
#   Nobody decides to fuse the delta module into the framework; someone adds
#   `source scripts/lib/delta-state.sh` to check-phase-gate.sh on a Tuesday
#   because it was easier, and the severability property is gone with no test
#   failing. This lint makes that fusion a red check.
#
# THE PREDICATE — two directions plus two guards (§3.3)
#   1. DELTA -> CORE: allowed, and deliberately UNASSERTED. The module may
#      source helpers-core.sh, call guard_not_in_framework, read
#      phase-state.json. Asserting it would be busywork.
#   2. CORE -> DELTA: forbidden. For every file in the CORE set, no EXECUTED
#      line may name any delta-module path.
#   3. SEAM ALLOWLIST, CARDINALITY EXACTLY ONE. scripts/process-checklist.sh is
#      the sole allowlisted core file. This script asserts the array length is
#      1 and fails if it grows. A second seam is a design change and must be
#      argued, not merged.
#   4. VACUITY FLOOR. Exit 2 unless at least one delta-module file AND at least
#      one core file were found. A boundary lint that scans nothing passes
#      trivially, and a passing lint that proves nothing is worse than no lint
#      — this repo has the scar (see the BL-104 scoring inversions in
#      CLAUDE.md, where an empty manifest scored better than no manifest).
#
# THE SETS — one manifest, so they can never disagree
#   DELTA = the §3.1 inventory, spelled once in the DELTA-BOUNDARY-MANIFEST
#           fence below. Adding a module file is a one-line edit there.
#   CORE  = init.sh + scripts/*.sh + scripts/lib/*.sh + scripts/hooks/*.sh,
#           MINUS the delta inventory and MINUS this script (which names every
#           delta path by construction). The self-exclusion is by BOTH manifest
#           membership and the explicit SELF_REL path, per §3.3.
#           scripts/host-drivers/*.sh is NOT in the CORE set: §3.3 names four
#           globs and this is the fourth-glob-faithful reading. Widen it only
#           by amending the design.
#
#   A RENAMED COPY of this script inside scripts/ is NOT self-excluded, and
#   that is deliberate. Unlike scripts/lint-bl-markers.sh — where a copy could
#   silently satisfy the lint's own resolution check — a copy here is a core
#   file that names every delta path, so it reds. Fail-closed is the right
#   direction for a boundary lint.
#
# TWO MATCH TIERS, because literal paths are evadable (R-DT-6)
#   T1  LITERAL PATH. Any manifest-derived token (basename for file entries,
#       the whole prefix for directory entries) on an executed line of a CORE
#       file. Verdict: FAIL. Unambiguous — a core file names a module file.
#       T1 is NOT inline-allowlistable. The single sanctioned escape for a
#       T1-class reference is the file-level seam, whose cardinality is one.
#   T2  BARE `delta-` TOKEN on an executed line that T1 did not already catch.
#       Verdict: FAIL, with an inline allowlist that REQUIRES a reason. This is
#       what catches the variable-composition family — `"$LIB/delta-${kind}.sh"`
#       carries no literal path but still carries the prefix.
#       T2 is deliberately coarse and will occasionally fire on prose in a
#       string (an error message that says "delta-state"). That is the right
#       trade: a false positive costs one allowlist row with a reason; a false
#       negative costs the severability property silently.
#
#   NAMED RESIDUAL (§13-R15, restated so nobody reads this lint as complete):
#   a reference composed BELOW the prefix boundary — `"$LIB/del""ta-state.sh"`,
#   or a path assembled from a variable holding `delta` — evades both tiers,
#   and no grep-based lint can catch it. The backstop is behavioural, not
#   lexical: WP7's severability test (delete the module, revert the seam, the
#   full suite must pass) fails on a fused module however the fusion is spelled.
#   Second residual: matching is CASE-SENSITIVE, because every path in the
#   inventory is lower-case and a case-insensitive T2 would fire on ordinary
#   prose like "DELTA-001".
#
# EXECUTED LINES ONLY — and why the exact spelling is load-bearing
#   Both tiers match against a STRIPPED copy of each file: whole-line comments
#   blanked, trailing comments truncated, at any indent and any whitespace
#   width, with and without a space after `#`. The stripper is the
#   DELTA-BOUNDARY-STRIP expression below and it is two sed expressions, in
#   this order:
#     E1  s/^[[:space:]]*#.*$//                        whole-line comments
#     E2  s/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/   trailing comments
#   E1 BLANKS rather than DELETES, so the stripped file has the same number of
#   lines as the original and `grep -n` on it yields true source line numbers.
#   That is the whole reason for the blank-not-delete choice; do not "simplify"
#   it to `grep -v`. (Note what "blanks" does and does NOT mean: `s///` replaces
#   only the MATCHED REGION. On a whole-line comment the match spans the line so
#   the result is empty; on any other line it removes only what it matched. A
#   mutation to this expression therefore truncates lines, it does not erase
#   them — an earlier version of this header claimed otherwise and an
#   adversarial review refuted it.)
#
#   This predicate has repo scar tissue. scripts/lint-tests-registered.sh
#   carries the sibling version (`# BL-181-UNIT-LANE-PREDICATE`) and CLAUDE.md
#   records that a ONE-CHARACTER narrowing of it — a quantifier, a character
#   class, or `#` -> `#[[:space:]]` — re-opened the same hole THREE times while
#   passing both PR-blocking checks every time.
#
#   BOTH DIRECTIONS ARE HAZARDS, AND THEY ARE NOT SYMMETRIC IN COST TO DETECT:
#     • NARROWING (strips too little) -> false POSITIVES -> any clean fixture
#       reds. Cheap to catch; cases X2/X3/X4/X5 do it.
#     • WIDENING (strips too much) -> false NEGATIVES -> the tree goes QUIETER,
#       and no clean fixture can ever notice. Caught only by a VIOLATION fixture
#       positioned where the widened match would reach: case X8. Three separate
#       one-character-class widenings (drop E1's `^`; E1 -> `s/#.*$//`; E2's
#       `[[:space:]][[:space:]]*` -> `[[:space:]]*`) each survived the other 27
#       cases and every PR-blocking check until X8 existed.
#   Each atom is pinned for WIDTH and SPELLING (not merely presence) by
#   tests/test-lint-delta-boundary.sh cases X1-X8; that file's header maps
#   atom -> case, IN BOTH DIRECTIONS, and records which mutant each row kills.
#   Before changing one character here, read it — and if you add a stripper
#   atom, add its widening pin too, not just its narrowing pin.
#
#   Both stages require the `#` to sit at line start or after whitespace, which
#   is bash's own rule: `echo "ref=x#delta-state.sh"` is one WORD, not a
#   comment, so the path is genuinely referenced (cases X7 and X8 — X7 guards
#   the line from being deleted wholesale, X8 guards the token after the `#`
#   from being truncated away).
#   Known limit, inherited from the sibling predicate: a `#` inside a quoted
#   string that follows whitespace (`sed 's/ #.*//'`) truncates the line early,
#   so a delta token AFTER such a `#` is missed. Quote-awareness costs a
#   char-by-char scan; the trade is the same one lint-tests-registered.sh made.
#
# ALLOWLIST — inline, reason REQUIRED, marker matched as an EXACT TOKEN
#   Append `# lint-delta-boundary: allow <reason>` to a T2-flagged line. The
#   marker must be followed by whitespace or end-of-line: `allowed because …`
#   and `allowlist …` are NOT the marker and do not waive anything (case L7).
#   Prefix matching would have parsed `allowed because x` as the marker with
#   reason "ed because x", so a typo could silently waive a real violation. An
#   empty reason FAILS, matching the allowlist semantics of
#   lint-fix-functions-stderr.sh and lint-bl-markers.sh. The marker lives in a
#   comment, so it is read off the RAW line after the tiers have matched
#   against the STRIPPED one.
#
# EXIT CODES
#   0 — no core -> delta edge.
#   1 — one or more violations, OR the seam allowlist failed its integrity
#       check (cardinality != 1, or a row with no reason). Both are "a human
#       must argue this", which is the exit-1 class; a malformed allowlist is
#       not an invocation error.
#   2 — invocation / I/O error, OR the vacuity floor tripped.
#   Order of checks: seam integrity (a property of this script, checkable
#   without the tree) -> vacuity floor (a property of the tree) -> the scan.
#
# USAGE
#   bash scripts/lint-delta-boundary.sh              # quiet pass/fail
#   bash scripts/lint-delta-boundary.sh --list       # PASS/FAIL table
#   bash scripts/lint-delta-boundary.sh --root DIR   # scan an alternate tree
#       (hermetic fixtures; used by tests/test-lint-delta-boundary.sh).
#       The vacuity floor is NOT relaxed under --root — the floor is one of
#       the things the fixtures exist to prove.
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2.57 as /bin/bash. No associative arrays, no ${var,,},
#   no `((x++))`, no nullglob (unmatched globs survive literally and are
#   filtered with `[ -f ]`). Every array expansion is length-guarded because
#   `"${arr[@]}"` on an EMPTY array is an unbound-variable error under `set -u`
#   in 3.2 — and the empty-manifest mutation (V3) walks straight into it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_REL="scripts/lint-delta-boundary.sh"

LIST_MODE=0
ROOT_OVERRIDE=""
USAGE="Usage: $0 [--list] [--root DIR]"

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST_MODE=1; shift ;;
    --root)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      ROOT_OVERRIDE="$2"; shift 2 ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done

ROOT="${ROOT_OVERRIDE:-$REPO_ROOT}"
if [ ! -d "$ROOT" ]; then
  echo "lint-delta-boundary: root not found: $ROOT" >&2
  exit 2
fi
# Canonicalize: every reported path is produced by stripping "$ROOT/" off an
# absolute path, so a trailing slash or a relative --root would leave the
# prefix un-stripped and every diagnostic absolute.
ROOT="$(cd "$ROOT" && pwd)" || { echo "lint-delta-boundary: cannot enter root: $ROOT" >&2; exit 2; }

# ── DELTA-BOUNDARY-MANIFEST-BEGIN ───────────────────────────────────────
# The §3.1 inventory, spelled ONCE. Both sets derive from it: DELTA is this
# list, CORE is the four globs MINUS this list. Entries ending in `/` are
# directory prefixes; everything else is a file path relative to the root.
# scripts/cut-release.sh is here despite its core-sounding name because it
# reads delta-state.json — classifying it as core would create a second
# core -> delta edge (§3.1).
DELTA_MANIFEST=(
  "scripts/lib/delta-state.sh"
  "scripts/lib/delta-policy.sh"
  "scripts/lib/delta-classify.sh"
  "scripts/lib/delta-cadence.sh"
  "scripts/delta.sh"
  "scripts/cut-release.sh"
  "scripts/lint-delta-boundary.sh"
  "templates/generated/delta-brief.tmpl"
  "docs/deltas/"
  ".claude/delta-state.json"
  ".claude/delta-policy.json"
)
# ── DELTA-BOUNDARY-MANIFEST-END ─────────────────────────────────────────

# ── DELTA-BOUNDARY-INSTALLER-BEGIN ──────────────────────────────────────
# THE INSTALLER, AND WHY IT IS NOT A SECOND SEAM.
#
# WP8 ships the module to generated projects, which means the scaffolder has to
# NAME every module file it copies — and it has to name them LITERALLY, because
# scripts/lib/scaffold-shipped-set.sh derives the shipped set by parsing those
# very `cp` lines. A derived or composed spelling would satisfy this lint and
# break the source-closure gate, which is the worse of the two failures.
#
# A `cp` is not a dependency edge. init.sh copies BYTES; it never sources a
# module lib, never calls delta.sh, and would not notice if the module's
# behaviour changed. Sever the module and these lines have nothing to copy —
# which is why the severability revert removes the block outright, and why
# tests/test-delta-severability.sh's V1 sweep reads the scaffolder.
#
# SO THE EXEMPTION IS BOUNDED THREE WAYS, and it is deliberately TIGHTER than
# the seam's (which exempts a whole file):
#   1. ONE installer file, cardinality asserted exactly as the seam's is. A
#      second installer is a design change, not an appended row.
#   2. Only lines INSIDE a `# DELTA-INSTALL-BEGIN` / `# DELTA-INSTALL-END`
#      fence are exempt. A module path anywhere else in init.sh is still a
#      violation, in both tiers.
#   3. Only INSTALLATION STATEMENTS may live inside the fence — `cp`, `chmod`,
#      `mkdir`. A `source scripts/lib/delta-state.sh` smuggled in there is a
#      real fusion wearing an installer's coat, and it FAILS (tier I1). An
#      unbalanced or nested fence fails too, because an unterminated BEGIN
#      would exempt the rest of the file.
INSTALLER_ALLOWLIST=(
  "init.sh|WP8 ships the §3.1 module to generated projects; the copy list must name each file LITERALLY because scripts/lib/scaffold-shipped-set.sh parses these cp lines to derive the shipped set. Copying bytes is installation, not a dependency edge — and only cp/chmod/mkdir statements inside the DELTA-INSTALL fence are exempt"
)
# ── DELTA-BOUNDARY-INSTALLER-END ────────────────────────────────────────

# ── DELTA-BOUNDARY-SEAM-BEGIN ───────────────────────────────────────────
# The ONE seam (§3.1). Rows are `path|reason`; the reason is REQUIRED and is
# rendered by --list so the exemption is reviewable rather than silent.
# Cardinality is asserted at exactly one immediately below.
SEAM_ALLOWLIST=(
  "scripts/process-checklist.sh|D1 §3.1 — the single declared seam: process-checklist.sh is both the commit-gate classifier pre-commit-gate.sh calls and D7's designated single writer of delta-state.json, so the module's one core edge lands here or nowhere"
)
# ── DELTA-BOUNDARY-SEAM-END ─────────────────────────────────────────────

VIOLATIONS=0
LIST_ROWS=""
DELTA_PRESENT=0
CORE_COUNT=0
CORE_SCANNED=0

# Pre-initialised above because emit_list is reachable from the cardinality and
# vacuity exits, both of which fire BEFORE the counts are computed — and an
# unset variable there would be a `set -u` crash instead of a diagnostic.
# "in scope" and "scanned" are reported separately on purpose: on a vacuity
# exit they differ (nothing is scanned), and collapsing them would hide which
# of the two populations actually failed the floor.
emit_list() {
  [ "$LIST_MODE" -eq 1 ] || return 0
  printf 'STATUS\tTIER\tFILE:LINE\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
  printf 'INFO\tpopulation\t-\t%s delta-module file(s) present, %s core file(s) in scope, %s scanned\n' \
    "$DELTA_PRESENT" "$CORE_COUNT" "$CORE_SCANNED"
}

# ── DELTA-BOUNDARY-CARDINALITY ──────────────────────────────────────────
# Clause 3. The array length IS the assertion; a second seam must be argued in
# the design, not appended here.
SEAM_COUNT=0
[ "${#SEAM_ALLOWLIST[@]}" -gt 0 ] && SEAM_COUNT=${#SEAM_ALLOWLIST[@]}
if [ "$SEAM_COUNT" -ne 1 ]; then
  echo "lint-delta-boundary: seam allowlist cardinality is $SEAM_COUNT, must be exactly 1." >&2
  echo "§3.3 clause 3: scripts/process-checklist.sh is the sole allowlisted core file. A second seam is a design change — amend docs/designs/2026-08-02-delta-track-v1.md §3.1 and argue it, do not append a row." >&2
  LIST_ROWS="${LIST_ROWS}FAIL\tseam\t${SELF_REL}\tcardinality ${SEAM_COUNT}, must be exactly 1\n"
  emit_list
  exit 1
fi

SEAM_PATH="${SEAM_ALLOWLIST[0]%%|*}"
SEAM_REASON="${SEAM_ALLOWLIST[0]#*|}"
if [ -z "$SEAM_REASON" ] || [ "$SEAM_REASON" = "${SEAM_ALLOWLIST[0]}" ]; then
  echo "lint-delta-boundary: seam allowlist row '$SEAM_PATH' carries no reason. Every allowlist row requires a reason string (see this script's ALLOWLIST section)." >&2
  LIST_ROWS="${LIST_ROWS}FAIL\tseam\t${SEAM_PATH}\tallowlist row has an empty reason\n"
  emit_list
  exit 1
fi
LIST_ROWS="${LIST_ROWS}INFO\tseam\t${SEAM_PATH}\tallowlisted (cardinality 1/1): ${SEAM_REASON}\n"

# ── DELTA-BOUNDARY-INSTALLER-CARDINALITY ────────────────────────────────
# The same assertion as the seam's, for the same reason and with the same
# answer: one, or argue it in the design.
INSTALLER_COUNT=0
[ "${#INSTALLER_ALLOWLIST[@]}" -gt 0 ] && INSTALLER_COUNT=${#INSTALLER_ALLOWLIST[@]}
if [ "$INSTALLER_COUNT" -ne 1 ]; then
  echo "lint-delta-boundary: installer allowlist cardinality is $INSTALLER_COUNT, must be exactly 1." >&2
  echo "The scaffolder is the ONE file allowed to name module paths inside a DELTA-INSTALL fence. A second installer is a design change — amend docs/designs/2026-08-02-delta-track-v1.md §3.1 and argue it, do not append a row." >&2
  LIST_ROWS="${LIST_ROWS}FAIL\tinstaller\t${SELF_REL}\tcardinality ${INSTALLER_COUNT}, must be exactly 1\n"
  emit_list
  exit 1
fi

INSTALLER_PATH="${INSTALLER_ALLOWLIST[0]%%|*}"
INSTALLER_REASON="${INSTALLER_ALLOWLIST[0]#*|}"
if [ -z "$INSTALLER_REASON" ] || [ "$INSTALLER_REASON" = "${INSTALLER_ALLOWLIST[0]}" ]; then
  echo "lint-delta-boundary: installer allowlist row '$INSTALLER_PATH' carries no reason. Every allowlist row requires a reason string (see this script's ALLOWLIST section)." >&2
  LIST_ROWS="${LIST_ROWS}FAIL\tinstaller\t${INSTALLER_PATH}\tallowlist row has an empty reason\n"
  emit_list
  exit 1
fi
# THE WORDING IS DELIBERATELY NOT "cardinality 1/1". That exact string is the
# SEAM's, and tests/test-delta-wp2-state-policy.sh::S6 counts its occurrences to
# assert the seam allowlist is still one. A second row spelling it the same way
# would make that count read 2 and break a WP2 assertion for a cosmetic reason —
# so the installer says "1 of 1" and the two remain separately countable.
LIST_ROWS="${LIST_ROWS}INFO\tinstaller\t${INSTALLER_PATH}\tDELTA-INSTALL fence exempt (installer allowlist 1 of 1): ${INSTALLER_REASON}\n"

# ── Set derivation ──────────────────────────────────────────────────────

# is_delta_path REL — true when REL is a delta-module file (or lives under a
# delta-module directory), or is this script.
is_delta_path() {
  local rel="$1" e
  [ "$rel" = "$SELF_REL" ] && return 0
  [ "${#DELTA_MANIFEST[@]}" -gt 0 ] || return 1
  for e in "${DELTA_MANIFEST[@]}"; do
    case "$e" in
      */) case "$rel" in "$e"*) return 0 ;; esac ;;
      *)  [ "$rel" = "$e" ] && return 0 ;;
    esac
  done
  return 1
}

TMPD=$(mktemp -d) || { echo "lint-delta-boundary: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# T1 token set, DERIVED from the manifest so the two can never disagree:
# a directory entry contributes its whole prefix, a file entry its basename
# (the basename is a substring of any spelling of the full path, so matching
# on it is strictly more sensitive than matching the path as written).
T1_TOKENS="$TMPD/t1-tokens"
: > "$T1_TOKENS"
if [ "${#DELTA_MANIFEST[@]}" -gt 0 ]; then
  for entry in "${DELTA_MANIFEST[@]}"; do
    case "$entry" in
      */) printf '%s\n' "$entry" >> "$T1_TOKENS" ;;
      *)  printf '%s\n' "${entry##*/}" >> "$T1_TOKENS" ;;
    esac
  done
fi

# DELTA population: manifest entries that actually EXIST, excluding this
# script. Excluding self is what keeps the floor honest — this file always
# exists, so counting it would make clause 4 self-satisfying and vacuous.
if [ "${#DELTA_MANIFEST[@]}" -gt 0 ]; then
  for entry in "${DELTA_MANIFEST[@]}"; do
    [ "$entry" = "$SELF_REL" ] && continue
    case "$entry" in
      */) [ -d "$ROOT/$entry" ] || continue ;;
      *)  [ -f "$ROOT/$entry" ] || continue ;;
    esac
    DELTA_PRESENT=$((DELTA_PRESENT + 1))
  done
fi

# CORE population. bash 3.2 has no nullglob, so an unmatched glob survives as
# a literal and is filtered by the `[ -f ]` test.
CORE_FILES="$TMPD/core-files"
: > "$CORE_FILES"
CORE_GLOBS=(
  "$ROOT/init.sh"
  "$ROOT/scripts"/*.sh
  "$ROOT/scripts/lib"/*.sh
  "$ROOT/scripts/hooks"/*.sh
)
for entry in "${CORE_GLOBS[@]}"; do
  [ -f "$entry" ] || continue
  rel="${entry#"$ROOT"/}"
  is_delta_path "$rel" && continue
  printf '%s\n' "$rel" >> "$CORE_FILES"
done
CORE_COUNT=$(grep -c '' "$CORE_FILES")
case "$CORE_COUNT" in ''|*[!0-9]*) CORE_COUNT=0 ;; esac

# ── DELTA-BOUNDARY-VACUITY ──────────────────────────────────────────────
# Clause 4, checked BEFORE the scan so a collapsed set can never be reported
# as a clean pass under any ordering of the code below.
if [ "$DELTA_PRESENT" -lt 1 ] || [ "$CORE_COUNT" -lt 1 ]; then
  emit_list
  echo "" >&2
  echo "lint-delta-boundary: VACUOUS SCAN — found $DELTA_PRESENT delta-module file(s) (floor 1) and $CORE_COUNT core file(s) (floor 1)." >&2
  echo "A boundary lint that scans nothing passes trivially, so this is an error, not a pass. Check the DELTA-BOUNDARY-MANIFEST fence and the CORE globs in this script, and that --root points at a real tree." >&2
  exit 2
fi

# ── The scan ────────────────────────────────────────────────────────────

STRIPPED="$TMPD/stripped"

# parse_allow RAW — echoes "<has_marker>\t<reason>" for the inline T2 allowlist.
#
# EXACT-TOKEN matching, not prefix matching. A bare substring test accepts
# `# lint-delta-boundary: allowed because …` as a marker and silently parses
# the reason as "ed because …", so a typo'd or merely similar-looking marker
# waives a real violation. The token must be followed by whitespace or by
# end-of-line — nothing else — which fails CLOSED: a near-miss spelling is not
# a marker at all, so the line stays a violation.
#
# The empty-reason case must still REGISTER as a marker (tail = ""), because an
# empty reason is REJECTED loudly rather than ignored; treating it as "no
# marker" would downgrade it to an ordinary unexplained violation and lose the
# specific diagnostic.
ALLOW_MARKER="# lint-delta-boundary: allow"
parse_allow() {
  local line="$1"
  local reason=""
  local has=0
  local tail
  case "$line" in
    *"$ALLOW_MARKER"*)
      tail="${line##*"$ALLOW_MARKER"}"
      case "$tail" in
        ""|[[:space:]]*)
          has=1
          reason="${tail#"${tail%%[![:space:]]*}"}"
          reason="${reason%"${reason##*[![:space:]]}"}"
          ;;
      esac
      ;;
  esac
  printf '%d\t%s\n' "$has" "$reason"
}

# ── DELTA-BOUNDARY-INSTALL-FENCE ────────────────────────────────────────
# _install_fence <file> — one record per line, on stdout:
#     EXEMPT <n>              this line is inside a fence and is installation
#     BAD <n> <what>          a fence problem, or a non-installation statement
#                             inside a fence
# The fence markers themselves are comments, so the stripper has already
# blanked them by the time the tiers run; they are read off the RAW file here.
#
# EVERY FAILURE MODE FAILS CLOSED. An unterminated BEGIN would exempt the whole
# rest of the scaffolder, so it is an error rather than a tolerated sloppiness;
# a nested BEGIN is the same hazard wearing a second coat; and a statement that
# is not `cp`, `chmod` or `mkdir` is the fusion this whole lint exists to catch,
# so it is reported at the line rather than waived by its neighbours.
_install_fence() {
  awk '
    /^[[:space:]]*#.*DELTA-INSTALL-BEGIN/ {
      if (open == 1) printf "BAD %d nested-DELTA-INSTALL-BEGIN\n", NR
      open = 1; next
    }
    /^[[:space:]]*#.*DELTA-INSTALL-END/ {
      if (open == 0) printf "BAD %d DELTA-INSTALL-END-with-no-BEGIN\n", NR
      open = 0; next
    }
    open == 1 {
      printf "EXEMPT %d\n", NR
      s = $0
      sub(/^[[:space:]]*/, "", s)
      if (s == "") next
      if (s ~ /^#/) next
      if (s !~ /^(cp|chmod|mkdir)[[:space:]]/)
        printf "BAD %d non-installation-statement-inside-the-fence\n", NR
    }
    END { if (open == 1) printf "BAD %d unterminated-DELTA-INSTALL-fence\n", NR }
  ' "$1" 2>/dev/null
  return 0
}

scan_core_file() {
  local rel="$1"
  local file="$ROOT/$rel"
  local hits line n raw tok parsed has reason rec kind
  local t1_lines="|"
  local exempt_lines="|"

  # The one seam is exempt from BOTH tiers. §3.3 clause 3 names it "the sole
  # allowlisted core file" without qualifying by tier, and that is the honest
  # reading: the seam block is delta references BY DESIGN (a declared set of
  # `--delta-*` actions that source delta-state.sh), so linting inside it would
  # demand an allowlist row per line and mean nothing. The real control here is
  # the cardinality assertion above — you cannot add a SECOND such file — plus
  # WP7's behavioural severability test, which is what pins that the seam block
  # is actually revertible.
  [ "$rel" = "$SEAM_PATH" ] && return 0

  # ── DELTA-BOUNDARY-STRIP ──────────────────────────────────────────────
  # E1 blanks whole-line comments (any indent width, with or without a space
  # after `#`); E2 truncates trailing comments (one-or-more whitespace before
  # the `#`, any width, with or without a space after it) while KEEPING the
  # executed prefix via the capture + \1. Order matters: E1 first, so E2 never
  # sees a line that is comment-only. Line COUNT is preserved on purpose.
  if ! sed -e 's/^[[:space:]]*#.*$//' \
           -e 's/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/' \
           "$file" > "$STRIPPED" 2>/dev/null; then
    echo "lint-delta-boundary: cannot read $rel" >&2
    return 2
  fi

  # THE INSTALLER'S FENCE, read before either tier so the exempt set exists by
  # the time they need it. Only the ONE allowlisted installer gets it: a
  # DELTA-INSTALL fence in any other core file exempts nothing, which is the
  # fail-closed direction.
  if [ "$rel" = "$INSTALLER_PATH" ]; then
    while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      kind="${rec%% *}"
      rec="${rec#* }"
      n="${rec%% *}"
      case "$kind" in
        EXEMPT) exempt_lines="${exempt_lines}${n}|" ;;
        BAD)
          echo "${rel}:${n}: lint-delta-boundary: I1 — ${rec#* } in the DELTA-INSTALL fence. Only cp / chmod / mkdir may live between the fence markers, and the fence must be balanced: an unterminated BEGIN would exempt the rest of this file. Move the statement out of the fence, or fix the markers." >&2
          VIOLATIONS=$((VIOLATIONS + 1))
          LIST_ROWS="${LIST_ROWS}FAIL\tI1\t${rel}:${n}\t${rec#* }\n"
          ;;
      esac
    done <<EOF
$(_install_fence "$file")
EOF
  fi

  # T1 — literal manifest tokens. Fixed-string matching: the tokens contain
  # `.` and `-`, and a BRE would let `delta.sh` match `deltaXsh`.
  if [ -s "$T1_TOKENS" ]; then
    hits=$(grep -n -F -f "$T1_TOKENS" "$STRIPPED")
    if [ -n "$hits" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        n="${line%%:*}"
        t1_lines="${t1_lines}${n}|"
        case "$exempt_lines" in *"|${n}|"*)
          LIST_ROWS="${LIST_ROWS}PASS\tT1\t${rel}:${n}\tinstaller fence: installation, not a dependency edge\n"
          continue ;;
        esac
        # `sed -n '1p'` and not `head -1`: head exits on its first line, the
        # upstream grep dies of SIGPIPE, and `pipefail` (set at the top of this
        # script) promotes rc=141 into the substitution. `sed -n 1p` consumes
        # all of its input, so nothing upstream ever sees a closed pipe. This
        # is the trap written up on `# BL-181-UNIT-LANE-PREDICATE`'s sibling
        # note in scripts/lint-tests-registered.sh — keep every stage a
        # full-input consumer.
        tok=$(printf '%s\n' "${line#*:}" | grep -o -F -f "$T1_TOKENS" | sed -n '1p')
        echo "${rel}:${n}: lint-delta-boundary: T1 — core file names delta-module path '${tok}'. Core must never reference the delta module (§3.3 clause 2); move the call behind the one seam (scripts/process-checklist.sh) or drop it." >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\tT1\t${rel}:${n}\tnames delta-module path '${tok}'\n"
      done <<< "$hits"
    fi
  fi

  # T2 — the bare prefix, on lines T1 did not already claim.
  hits=$(grep -n -F -e 'delta-' "$STRIPPED")
  if [ -n "$hits" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      n="${line%%:*}"
      case "$t1_lines" in *"|${n}|"*) continue ;; esac
      case "$exempt_lines" in *"|${n}|"*)
        LIST_ROWS="${LIST_ROWS}PASS\tT2\t${rel}:${n}\tinstaller fence: installation, not a dependency edge\n"
        continue ;;
      esac
      # The allowlist marker lives in the COMMENT the stripper just removed, so
      # it is read off the RAW line — after the tiers have matched against the
      # stripped one.
      raw=$(sed -n "${n}p" "$file")
      parsed=$(parse_allow "$raw")
      has="$(printf '%s' "$parsed" | cut -f1)"
      reason="$(printf '%s' "$parsed" | cut -f2-)"
      if [ "$has" = "1" ]; then
        if [ -z "$reason" ]; then
          echo "${rel}:${n}: lint-delta-boundary: T2 allowlist marker present but the reason is empty. Write '# lint-delta-boundary: allow <why this is not a module reference>'." >&2
          VIOLATIONS=$((VIOLATIONS + 1))
          LIST_ROWS="${LIST_ROWS}FAIL\tT2\t${rel}:${n}\tallowlist marker with an empty reason\n"
        else
          LIST_ROWS="${LIST_ROWS}PASS\tT2\t${rel}:${n}\tallowlisted: ${reason}\n"
        fi
        continue
      fi
      echo "${rel}:${n}: lint-delta-boundary: T2 — bare 'delta-' token on an executed line of a core file. A runtime-composed reference (\"\$LIB/delta-\${kind}.sh\") fuses the module exactly as thoroughly as a literal path. Remove it, or append '# lint-delta-boundary: allow <reason>' if this is prose in a string." >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      LIST_ROWS="${LIST_ROWS}FAIL\tT2\t${rel}:${n}\tbare 'delta-' token on an executed line\n"
    done <<< "$hits"
  fi
  return 0
}

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  CORE_SCANNED=$((CORE_SCANNED + 1))
  scan_core_file "$rel" || { emit_list; exit 2; }
done < "$CORE_FILES"

emit_list

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS core -> delta boundary violation(s). The delta track is a SEVERABLE module (D1): delta may import core, core may never import delta. See scripts/lint-delta-boundary.sh header and docs/designs/2026-08-02-delta-track-v1.md §3.3." >&2
  exit 1
fi

echo "OK: no core -> delta edge ($CORE_SCANNED core file(s) scanned against $DELTA_PRESENT delta-module file(s); seam: $SEAM_PATH)."
exit 0

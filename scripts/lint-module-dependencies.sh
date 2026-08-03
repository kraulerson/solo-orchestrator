#!/usr/bin/env bash
# scripts/lint-module-dependencies.sh — the module-dependency lint for the
# BROWNFIELD module set: Scout (the read-only scanner) and the adoption driver.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §3.3 (M1-M5,
# normative), with the module inventory at §3.1 and the build-plan row at
# §10-WP0. The rules are transcribed as a standing contract in
# docs/module-contract.md; this script is M2/M3/M5's enforcement half.
#
# (Deliberately NO `# BL-NNN-…` marker: no backlog entry exists for the
# brownfield build, and CLAUDE.md's citation rule is satisfied by the
# design-doc path above plus the grep-able `MODULE-DEPS-*` fences below. Do not
# mint a BL marker here — scripts/lint-bl-markers.sh would red on an id nobody
# filed.)
#
# WHY A SIBLING AND NOT A GENERALISATION
#   The post-MVP delta track ships its own boundary lint, whose architecture
#   this file follows deliberately: literal manifest at the top, executed-lines
#   -only comment stripping at every width and spelling, two match tiers, a
#   reasoned exact-token allowlist, a vacuity floor that exits 2, `--list`, and
#   a `--root` override for hermetic fixtures. That shape survived two
#   adversarial fix rounds. The WP0 convergence decision was to build a SIBLING
#   in the same shape rather than generalise the freshly reviewed delta lint
#   into a parameterised engine — both designs stay honored as written, and
#   neither track's boundary can be weakened by an edit aimed at the other.
#
# THE DEFECT CLASS
#   A severable module stops being severable one convenience call at a time.
#   Nobody decides to fuse the adoption driver into the framework; someone adds
#   a source line to a core gate script on a Tuesday because it was easier, and
#   the severability property is gone with no test failing. This lint makes
#   that fusion a red check.
#
# THE PREDICATE — three arms (§3.3)
#   1. MODULE -> CORE: permitted (M3 clause 1), and deliberately UNASSERTED for
#      the DRIVER. The adoption driver may source helpers-core.sh, read
#      phase-state.json, call the host drivers. Asserting it would be busywork.
#   2. CORE -> MODULE: forbidden (M3 clause 2). For every file in the CORE set,
#      no EXECUTED line may name any brownfield-module path.
#   3. M5, THE ZERO-DEPENDENCY ARM, SCOUT ONLY. "The scanner sources no core
#      lib. Its bootstrap must work in a clone that has never run init.sh."
#      Scout's files may not name any `scripts/lib/*.sh` core lib on an
#      executed line. The DRIVER is exempt — M5 binds the scanner, and an arm
#      applied to both would forbid something §3.3 explicitly permits. That
#      bound is a pin in its own right (tests/test-lint-module-dependencies.sh
#      case M3), because an unbounded exemption and an unbounded rule are the
#      same class of error.
#
#   PLUS TWO GUARDS
#   4. CORE ALLOWLIST, CARDINALITY EXACTLY ZERO. Unlike the delta track — whose
#      module has one declared seam — the brownfield module has NONE. §3.1's
#      in-core enabling arms are NOT seams: they are core code that reads an
#      `adopted` flag and never sources module code, so they need no exemption.
#      The array's length IS the assertion. Growth is a design change to be
#      argued in §3.1, not a row to append.
#   5. VACUITY FLOOR. Exit 2 unless at least one module file AND at least one
#      core file were found — and, when zero-dependency module files are
#      present, at least one core lib to check them against. A boundary lint
#      that scans nothing passes trivially, and a passing lint that proves
#      nothing is worse than no lint — this repo has the scar (the BL-104
#      scoring inversions in CLAUDE.md, where an empty manifest scored better
#      than no manifest).
#
# THE SETS — one manifest, so they can never disagree
#   MODULE = the §3.1/§3.3 inventory, spelled ONCE in the MODULE-DEPS-MANIFEST
#            fence below as `<module>|<path>` rows. The module column is what
#            makes M5's scout-only bound derivable from the same list instead
#            of from a second one that could drift out of step with it.
#   CORE   = init.sh + scripts/*.sh + scripts/lib/*.sh + scripts/hooks/*.sh,
#            MINUS the module inventory, MINUS this script, and MINUS sibling
#            boundary lints. scripts/host-drivers/*.sh is NOT in the CORE set:
#            §3.3's co-owned contract names four globs and this is the
#            fourth-glob-faithful reading, kept at exact parity with the delta
#            lint. The gap is a known, pending design question for BOTH lints —
#            widen it only by amending the design, and then in both places.
#
#   SELF-EXCLUSION IS BY EXACT PATH, and that is deliberate: a RENAMED COPY of
#   this script inside scripts/ is NOT self-excluded. A copy is a core file
#   that names every module path, so it reds. Fail-closed is the right
#   direction for a boundary lint.
#
#   SIBLING BOUNDARY LINTS are excluded BY SHAPE (`scripts/lint-*-boundary.sh`)
#   rather than by name, and the reason is worth recording because it is the
#   sibling lint's own predicate talking. That lint's manifest lists its own
#   filename, so its basename is one of its T1 literal tokens — and T1 is
#   non-waivable there by design. Writing the sibling's literal path on an
#   executed line of this file would therefore red the sibling lint with a
#   violation no allowlist row can waive. The shape glob is the only spelling
#   available, and it happens to be the more general rule anyway: any future
#   module's boundary lint is excluded without an edit here.
#   KNOWN COST, stated rather than hidden: the glob is broader than a name, so
#   a core file that genuinely fused a module WOULD go unseen if it were named
#   `scripts/lint-<something>-boundary.sh`. The exposure is one filename shape
#   that only lint infrastructure uses.
#
# TWO MATCH TIERS, because literal paths are evadable
#   T1  LITERAL PATH, tokens DERIVED from the manifest (basename for file
#       entries, the whole prefix for directory entries) on an executed line of
#       a CORE file. Verdict: FAIL. Unambiguous — a core file names a module
#       file. T1 is NOT inline-allowlistable; with the allowlist cardinality at
#       zero there is no sanctioned escape for a T1-class reference at all.
#   T2  PATH-SHAPED MODULE TOKEN on an executed line that T1 did not already
#       catch. Verdict: FAIL, with an inline allowlist that REQUIRES a reason.
#
#       WHY THESE TOKENS AND NOT `scout`/`adopt`. The delta module is a set of
#       flat `delta-*.sh` files, so its T2 tier is the bare `delta-` prefix.
#       The brownfield module is a DIRECTORY module, and the analogous bare
#       English words are measurably wrong: a bare `adopt` token fires on TWO
#       executed lines of the core tree TODAY — an operator warning in
#       scripts/upgrade-project.sh's legacy-hook arm ("diff, then adopt
#       manually") and a printf in scripts/lib/plan-staging.sh ("Decide by hand
#       which to adopt") — neither of which is a reference to anything. Worse,
#       §3.2's in-core enabling arms are named around the `adopted` flag, so a
#       bare token would fire on every arm WP3 adds, permanently, by design.
#
#       The T2 tokens are therefore PATH-SEGMENT shaped: `scout/` and `adopt/`
#       carry a trailing slash, so they are path syntax and not the English
#       words. Measured on the current core surface, both have ZERO occurrences
#       outside this (self-excluded) file, and §7.2's archive path is
#       `.claude/adoption-archive/`, which contains neither.
#
#       WHY A SEGMENT AND NOT `lib/scout/`, which is the more obvious choice.
#       T1's directory token is the full `scripts/lib/scout/`, and the house's
#       dominant sourcing idiom drops the `scripts/` segment —
#       `"$SCRIPT_DIR/lib/<name>.sh"`, 17 of the top call sites in scripts/ —
#       so T1 alone is blind to it. `lib/scout/` fixes that spelling and ONLY
#       that spelling: `"$LIBDIR/scout/scout-core.sh"`, where the variable
#       already ends in `lib`, evades it too. That was not a hypothetical —
#       the first draft of this lint used `lib/scout/`, and case S3 of the test
#       suite, written independently with the natural `$LIBDIR` spelling,
#       caught it on the first run. The bare segment closes the whole family
#       for the cost of a token that matches nothing else in the tree.
#
#       The two entry-script tokens duplicate T1 on purpose: T1's tokens are
#       DERIVED from the manifest, so deleting a manifest row disarms T1 for
#       that path, while this list is an INDEPENDENT literal and still fires.
#       The cheapest way to silence a violation must not silence the lint
#       (case E1).
#
#   NAMED RESIDUAL, restated so nobody reads this lint as complete: a reference
#   composed BELOW the token boundary — a path assembled from a variable
#   holding `scout` — evades both tiers, and no grep-based lint can catch it.
#   The backstop is behavioural, not lexical: WP1-brownfield's hermetic test
#   runs the scanner with scripts/lib/ moved aside, which fails on a fused
#   module however the fusion is spelled. Second residual: matching is
#   CASE-SENSITIVE, because every path in the inventory is lower-case and a
#   case-insensitive tier would fire on ordinary prose.
#
#   FOURTH RESIDUAL, AND THE WIDEST ONE — M5's forbidden set is core LIB
#   basenames only. A Scout file that invokes a core ENTRY SCRIPT
#   (`scripts/*.sh`) or `init.sh` itself passes this arm clean. Reproduced:
#   a scout file carrying
#       bash "$(dirname "$0")/../../check-gate.sh" --probe
#       out=$(bash "$(dirname "$0")/../../../init.sh")
#   scans to rc=0.
#   That is faithful to §3.3 M5's FIRST sentence ("sources no core lib") and
#   violates its SECOND ("its bootstrap must work in a clone that has never run
#   init.sh") together with §3.1's "zero dependency on the installer". The
#   escape survives the planned behavioural backstop too: moving scripts/lib/
#   aside does not disturb scripts/*.sh, so WP1-brownfield's hermetic test as
#   currently specified would ALSO miss it — that test should move
#   scripts/*.sh aside as well, or assert against a bare tree.
#   Widening M5_TOKENS to `scripts/*.sh` basenames plus `init.sh` is a
#   DESIGN-LEVEL call — it would make every Scout file that so much as names a
#   core entry script a violation — and is deliberately NOT taken unilaterally
#   here. It sits in the same pending queue as the host-drivers glob question.
#   Named now so the gap is disclosed rather than discovered.
#   Third residual, specific to the M5 arm: its forbidden tokens are core-lib
#   BASENAMES, so a module file that reused a core lib's basename inside its
#   own directory would false-positive on a legitimate same-dir source. M1
#   gives each module its own directory precisely so it can name its files
#   freely; do not reuse a core lib basename inside a module.
#
# EXECUTED LINES ONLY — and why the exact spelling is load-bearing
#   Every arm matches against a STRIPPED copy of each file: whole-line comments
#   blanked, trailing comments truncated, at any indent and any whitespace
#   width, with and without a space after `#`. The stripper is the
#   MODULE-DEPS-STRIP expression below and it is two sed expressions, in this
#   order:
#     E1  s/^[[:space:]]*#.*$//                        whole-line comments
#     E2  s/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/   trailing comments
#   E1 BLANKS rather than DELETES, so the stripped file has the same number of
#   lines as the original and `grep -n` on it yields true source line numbers.
#   That is the whole reason for the blank-not-delete choice; do not "simplify"
#   it to `grep -v`. (Note what "blanks" does and does NOT mean: `s///` replaces
#   only the MATCHED REGION. On a whole-line comment the match spans the line so
#   the result is empty; on any other line it removes only what it matched. A
#   mutation to this expression therefore truncates lines, it does not erase
#   them.)
#
#   This predicate has repo scar tissue. scripts/lint-tests-registered.sh
#   carries the sibling version (`# BL-181-UNIT-LANE-PREDICATE`) and CLAUDE.md
#   records that a ONE-CHARACTER narrowing of it — a quantifier, a character
#   class, or `#` -> `#[[:space:]]` — re-opened the same hole THREE times while
#   passing both PR-blocking checks every time.
#
#   BOTH DIRECTIONS ARE HAZARDS, AND THEY ARE NOT SYMMETRIC IN COST TO DETECT:
#     • NARROWING (strips too little) -> false POSITIVES -> any clean fixture
#       reds. Cheap to catch; cases X2/X3/X4/X5/X9 do it.
#     • WIDENING (strips too much) -> false NEGATIVES -> the tree goes QUIETER,
#       and no clean fixture can ever notice. Caught only by a VIOLATION
#       fixture positioned where the widened match would reach: cases X8 (the
#       direction arms) and X10 (the M5 arm).
#   Each atom is pinned for WIDTH and SPELLING — not merely presence — by
#   tests/test-lint-module-dependencies.sh cases X1-X10; that file's header
#   maps atom -> case IN BOTH DIRECTIONS and records which named mutant each
#   row kills. Before changing one character here, read it — and if you add a
#   stripper atom, add its widening pin too, not just its narrowing pin.
#
#   The stripper is applied at TWO independent call sites (the direction arms
#   and the M5 arm). X9/X10 exist because a fix or a regression applied to one
#   site and not the other is exactly the half-edit a single-site pin misses.
#
#   Both stages require the `#` to sit at line start or after whitespace, which
#   is bash's own rule: `echo "ref=x#lib/scout/core.sh"` is one WORD, not a
#   comment, so the path is genuinely referenced (cases X7 and X8 — X7 guards
#   the line from being deleted wholesale, X8 guards the token after the `#`
#   from being truncated away).
#   Known limit, inherited from the sibling predicate: a `#` inside a quoted
#   string that follows whitespace (`sed 's/ #.*//'`) truncates the line early,
#   so a module token AFTER such a `#` is missed. Quote-awareness costs a
#   char-by-char scan; the trade is the same one lint-tests-registered.sh made.
#
# ALLOWLIST — inline, T2 ONLY, reason REQUIRED, marker matched as an EXACT TOKEN
#   Append `# lint-module-dependencies: allow <reason>` to a T2-flagged line.
#   The marker must be followed by whitespace or end-of-line: `allowed because
#   …` and `allowlist …` are NOT the marker and do not waive anything (case
#   L5). Prefix matching would have parsed `allowed because x` as the marker
#   with reason "ed because x", so a typo could silently waive a real
#   violation. An empty reason FAILS, matching the allowlist semantics of
#   lint-fix-functions-stderr.sh and lint-bl-markers.sh. The marker lives in a
#   comment, so it is read off the RAW line after the tiers have matched
#   against the STRIPPED one.
#   T1 and M5 are NOT allowlistable. "Depends on nothing" has no reasoned
#   exceptions — a waived dependency is a dependency, and a waivable M5 would
#   become the standard way to add "just one" core call.
#
# EXIT CODES
#   0 — no core -> module edge and no scout dependency.
#   1 — one or more violations, OR the core allowlist failed its integrity
#       check (cardinality != 0, or a row with no reason). Both are "a human
#       must argue this", which is the exit-1 class; a malformed allowlist is
#       not an invocation error.
#   2 — invocation / I/O error, OR the vacuity floor tripped.
#   Order of checks: allowlist integrity (a property of this script, checkable
#   without the tree) -> vacuity floor (a property of the tree) -> the scan.
#
# USAGE
#   bash scripts/lint-module-dependencies.sh              # quiet pass/fail
#   bash scripts/lint-module-dependencies.sh --list       # PASS/FAIL table
#   bash scripts/lint-module-dependencies.sh --root DIR   # scan an alternate tree
#       (hermetic fixtures; used by tests/test-lint-module-dependencies.sh).
#       The vacuity floor is NOT relaxed under --root — the floor is one of the
#       things the fixtures exist to prove.
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2.57 as /bin/bash. No associative arrays, no ${var,,},
#   no `((x++))`, no nullglob (unmatched globs survive literally and are
#   filtered with `[ -f ]`). Every array VALUE expansion is length-guarded,
#   because `"${arr[@]}"` on an EMPTY array is an unbound-variable error under
#   `set -u` in 3.2 — verified on this host. That hazard is not theoretical
#   here: CORE_ALLOWLIST is empty BY DESIGN, permanently, so every one of its
#   expansions is a live tripwire. (`${#arr[@]}` on an empty array is safe;
#   only the value expansion is not.)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_REL="scripts/lint-module-dependencies.sh"

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
  echo "lint-module-dependencies: root not found: $ROOT" >&2
  exit 2
fi
# Canonicalize: every reported path is produced by stripping "$ROOT/" off an
# absolute path, so a trailing slash or a relative --root would leave the
# prefix un-stripped and every diagnostic absolute.
ROOT="$(cd "$ROOT" && pwd)" || { echo "lint-module-dependencies: cannot enter root: $ROOT" >&2; exit 2; }

# ── MODULE-DEPS-MANIFEST-BEGIN ──────────────────────────────────────────
# The §3.1/§3.3 inventory, spelled ONCE, as `<module>|<path>` rows. Every set
# derives from it: MODULE is this list, CORE is the four globs MINUS this list,
# and M5's population is the subset whose module column is in ZERO_DEP_MODULES.
# Entries ending in `/` are directory prefixes; everything else is a file path
# relative to the root.
#
# M1 gives each module one directory and exactly one entry script, which is why
# every row is one of those two shapes. Naming is §3.3's author-proposed set and
# is one-edit changeable: Scout is the read-only scanner, and the driver keeps
# Karl's name exactly.
MODULE_MANIFEST=(
  "scout|scripts/scout.sh"
  "scout|scripts/lib/scout/"
  "adopt|scripts/adopt-project.sh"
  "adopt|scripts/lib/adopt/"
)
# The modules M5 binds. Scout only: §3.3 makes zero-dependency a property of
# the SCANNER, and the driver is severable, not isolated.
ZERO_DEP_MODULES="scout"
# Every module name that may appear in the manifest's first column. A typo'd
# row would otherwise drop silently out of M5's population while still looking
# like a manifest entry.
KNOWN_MODULES="scout adopt"
# ── MODULE-DEPS-MANIFEST-END ────────────────────────────────────────────

# ── MODULE-DEPS-T2-TOKENS-BEGIN ─────────────────────────────────────────
# T2's path-shaped tokens. INDEPENDENT of the manifest on purpose — see the
# TWO MATCH TIERS section above for the measured false-positive analysis that
# rejected bare `scout`/`adopt`, and case E1 for why the two entry-script
# tokens duplicate T1 rather than being pruned as redundant.
T2_TOKENS=(
  "scout/"
  "adopt/"
  "scout.sh"
  "adopt-project.sh"
)
# ── MODULE-DEPS-T2-TOKENS-END ───────────────────────────────────────────

# ── MODULE-DEPS-CORE-ALLOWLIST-BEGIN ────────────────────────────────────
# Core files permitted to reference module paths. Rows would be `path|reason`.
# CARDINALITY IS ZERO AND THE EMPTINESS IS THE POINT (§3.1): the brownfield
# module declares no seam, because §3.2's in-core enabling arms read an
# `adopted` flag and never source module code. A row here is a design change.
CORE_ALLOWLIST=()
# ── MODULE-DEPS-CORE-ALLOWLIST-END ──────────────────────────────────────

VIOLATIONS=0
LIST_ROWS=""
MODULE_PRESENT=0
CORE_COUNT=0
CORE_SCANNED=0
ZERODEP_COUNT=0
CORELIB_COUNT=0

# Pre-initialised above because emit_list is reachable from the cardinality and
# vacuity exits, both of which fire BEFORE the counts are computed — and an
# unset variable there would be a `set -u` crash instead of a diagnostic.
# "in scope" and "scanned" are reported separately on purpose: on a vacuity
# exit they differ (nothing is scanned), and collapsing them would hide which
# of the populations actually failed the floor.
emit_list() {
  [ "$LIST_MODE" -eq 1 ] || return 0
  printf 'STATUS\tTIER\tFILE:LINE\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
  printf 'INFO\tpopulation\t-\t%s module file(s) present, %s core file(s) in scope, %s scanned, %s zero-dep module file(s), %s core lib(s)\n' \
    "$MODULE_PRESENT" "$CORE_COUNT" "$CORE_SCANNED" "$ZERODEP_COUNT" "$CORELIB_COUNT"
}

# ── MODULE-DEPS-CARDINALITY ─────────────────────────────────────────────
# Guard 4. The array length IS the assertion; a seam must be argued in the
# design, not appended here.
ALLOW_COUNT=${#CORE_ALLOWLIST[@]}
if [ "$ALLOW_COUNT" -ne 0 ]; then
  echo "lint-module-dependencies: core allowlist cardinality is $ALLOW_COUNT, must be exactly 0." >&2
  echo "§3.1: the brownfield module declares NO seam — the in-core enabling arms read an 'adopted' flag and never source module code, so they need no exemption. A seam is a design change: amend docs/designs/2026-08-02-brownfield-adoption-v1.md §3.1 and argue it, do not append a row." >&2
  LIST_ROWS="${LIST_ROWS}FAIL\tallowlist\t${SELF_REL}\tcardinality ${ALLOW_COUNT}, must be exactly 0\n"
  emit_list
  exit 1
fi
LIST_ROWS="${LIST_ROWS}INFO\tallowlist\t-\tcore allowlist is empty (cardinality 0/0, as §3.1 requires)\n"

# Reason integrity for any row that ever appears. Unreachable while the
# cardinality is zero and deliberately kept anyway: the day someone argues a
# seam through the design, the row they add must still carry a reason, and a
# check written only when it is first needed is a check written under pressure.
# The length guard is not decoration — `"${CORE_ALLOWLIST[@]}"` on the empty
# array is a `set -u` abort in bash 3.2.
if [ "${#CORE_ALLOWLIST[@]}" -gt 0 ]; then
  for row in "${CORE_ALLOWLIST[@]}"; do
    row_path="${row%%|*}"
    row_reason="${row#*|}"
    if [ -z "$row_reason" ] || [ "$row_reason" = "$row" ]; then
      echo "lint-module-dependencies: core allowlist row '$row_path' carries no reason. Every allowlist row requires a reason string (see this script's ALLOWLIST section)." >&2
      LIST_ROWS="${LIST_ROWS}FAIL\tallowlist\t${row_path}\tallowlist row has an empty reason\n"
      emit_list
      exit 1
    fi
  done
fi

# ── Set derivation ──────────────────────────────────────────────────────

# is_known_module NAME — manifest integrity: a row whose module column is a
# typo would silently vanish from M5's population while still contributing to
# MODULE and T1. Checked, not assumed.
is_known_module() {
  local name="$1" m
  for m in $KNOWN_MODULES; do
    [ "$name" = "$m" ] && return 0
  done
  return 1
}

is_zero_dep_module() {
  local name="$1" m
  for m in $ZERO_DEP_MODULES; do
    [ "$name" = "$m" ] && return 0
  done
  return 1
}

# is_module_path REL — true when REL is a module file (or lives under a module
# directory), is this script, or is a sibling boundary lint. All three are
# outside the CORE set; see the SETS section for why each.
is_module_path() {
  local rel="$1" row entry
  [ "$rel" = "$SELF_REL" ] && return 0
  case "$rel" in
    scripts/lint-*-boundary.sh) return 0 ;;
  esac
  [ "${#MODULE_MANIFEST[@]}" -gt 0 ] || return 1
  for row in "${MODULE_MANIFEST[@]}"; do
    entry="${row#*|}"
    case "$entry" in
      */) case "$rel" in "$entry"*) return 0 ;; esac ;;
      *)  [ "$rel" = "$entry" ] && return 0 ;;
    esac
  done
  return 1
}

TMPD=$(mktemp -d) || { echo "lint-module-dependencies: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# Manifest integrity, and the T1 token set DERIVED from the manifest so the two
# can never disagree: a directory entry contributes its whole prefix, a file
# entry its basename (the basename is a substring of any spelling of the full
# path, so matching on it is strictly more sensitive than matching the path as
# written).
T1_TOKENS="$TMPD/t1-tokens"
: > "$T1_TOKENS"
if [ "${#MODULE_MANIFEST[@]}" -gt 0 ]; then
  for row in "${MODULE_MANIFEST[@]}"; do
    mod="${row%%|*}"
    entry="${row#*|}"
    if ! is_known_module "$mod"; then
      echo "lint-module-dependencies: manifest row '$row' names unknown module '$mod' (known: $KNOWN_MODULES)." >&2
      exit 2
    fi
    case "$entry" in
      */) printf '%s\n' "$entry" >> "$T1_TOKENS" ;;
      *)  printf '%s\n' "${entry##*/}" >> "$T1_TOKENS" ;;
    esac
  done
fi

T2_TOKEN_FILE="$TMPD/t2-tokens"
: > "$T2_TOKEN_FILE"
if [ "${#T2_TOKENS[@]}" -gt 0 ]; then
  for entry in "${T2_TOKENS[@]}"; do
    printf '%s\n' "$entry" >> "$T2_TOKEN_FILE"
  done
fi

# MODULE population: manifest entries that actually EXIST.
if [ "${#MODULE_MANIFEST[@]}" -gt 0 ]; then
  for row in "${MODULE_MANIFEST[@]}"; do
    entry="${row#*|}"
    case "$entry" in
      */) [ -d "$ROOT/$entry" ] || continue ;;
      *)  [ -f "$ROOT/$entry" ] || continue ;;
    esac
    MODULE_PRESENT=$((MODULE_PRESENT + 1))
  done
fi

# ZERO-DEP population (M5): every existing file of every module in
# ZERO_DEP_MODULES. Directory entries are walked; file entries are taken as-is.
ZERODEP_FILES="$TMPD/zerodep-files"
: > "$ZERODEP_FILES"
FIND_OUT="$TMPD/find-out"
if [ "${#MODULE_MANIFEST[@]}" -gt 0 ]; then
  for row in "${MODULE_MANIFEST[@]}"; do
    mod="${row%%|*}"
    entry="${row#*|}"
    is_zero_dep_module "$mod" || continue
    case "$entry" in
      */)
        [ -d "$ROOT/$entry" ] || continue
        # Piping find into a while-read would run the loop in a SUBSHELL under
        # bash 3.2 and every append would be lost; stage it in a file instead.
        find "$ROOT/$entry" -type f -name '*.sh' -print > "$FIND_OUT" 2>/dev/null
        while IFS= read -r abs; do
          [ -n "$abs" ] || continue
          printf '%s\n' "${abs#"$ROOT"/}" >> "$ZERODEP_FILES"
        done < "$FIND_OUT"
        ;;
      *)
        [ -f "$ROOT/$entry" ] && printf '%s\n' "$entry" >> "$ZERODEP_FILES"
        ;;
    esac
  done
fi
ZERODEP_COUNT=$(grep -c '' "$ZERODEP_FILES")
case "$ZERODEP_COUNT" in ''|*[!0-9]*) ZERODEP_COUNT=0 ;; esac

# CORE population. bash 3.2 has no nullglob, so an unmatched glob survives as a
# literal and is filtered by the `[ -f ]` test.
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
  is_module_path "$rel" && continue
  printf '%s\n' "$rel" >> "$CORE_FILES"
done
CORE_COUNT=$(grep -c '' "$CORE_FILES")
case "$CORE_COUNT" in ''|*[!0-9]*) CORE_COUNT=0 ;; esac

# M5's forbidden-token set: the BASENAMES of the core libs, derived from the
# scanned tree rather than hardcoded, so it cannot drift as scripts/lib/ grows.
M5_TOKENS="$TMPD/m5-tokens"
: > "$M5_TOKENS"
for entry in "$ROOT/scripts/lib"/*.sh; do
  [ -f "$entry" ] || continue
  rel="${entry#"$ROOT"/}"
  is_module_path "$rel" && continue
  printf '%s\n' "${rel##*/}" >> "$M5_TOKENS"
done
CORELIB_COUNT=$(grep -c '' "$M5_TOKENS")
case "$CORELIB_COUNT" in ''|*[!0-9]*) CORELIB_COUNT=0 ;; esac

# ── MODULE-DEPS-VACUITY ─────────────────────────────────────────────────
# Guard 5, checked BEFORE the scan so a collapsed set can never be reported as
# a clean pass under any ordering of the code below.
if [ "$MODULE_PRESENT" -lt 1 ] || [ "$CORE_COUNT" -lt 1 ]; then
  emit_list
  echo "" >&2
  echo "lint-module-dependencies: VACUOUS SCAN — found $MODULE_PRESENT module file(s) (floor 1) and $CORE_COUNT core file(s) (floor 1)." >&2
  echo "A boundary lint that scans nothing passes trivially, so this is an error, not a pass. Check the MODULE-DEPS-MANIFEST fence and the CORE globs in this script, and that --root points at a real tree." >&2
  exit 2
fi
# The same defect class, one level down: an empty forbidden-token set makes the
# M5 arm match nothing and pass trivially. Only asserted when there is
# something for it to govern.
if [ "$ZERODEP_COUNT" -ge 1 ] && [ "$CORELIB_COUNT" -lt 1 ]; then
  emit_list
  echo "" >&2
  echo "lint-module-dependencies: VACUOUS M5 ARM — $ZERODEP_COUNT zero-dependency module file(s) present but 0 core lib(s) to check them against." >&2
  echo "M5 would pass trivially. Check the scripts/lib/*.sh glob in this script and that --root points at a real tree." >&2
  exit 2
fi

# ── The scan ────────────────────────────────────────────────────────────

STRIPPED="$TMPD/stripped"

# strip_file SRC — writes the executed-lines-only copy to $STRIPPED.
#
# ── MODULE-DEPS-STRIP ─────────────────────────────────────────────────
# E1 blanks whole-line comments (any indent width, with or without a space
# after `#`); E2 truncates trailing comments (one-or-more whitespace before the
# `#`, any width, with or without a space after it) while KEEPING the executed
# prefix via the capture + \1. Order matters: E1 first, so E2 never sees a line
# that is comment-only. Line COUNT is preserved on purpose.
#
# ONE FUNCTION, TWO CALL SITES. The direction arms and the M5 arm both go
# through here, which is what makes the X9/X10 pins meaningful: there is one
# expression to regress and one to fix, and neither arm can drift from the
# other.
strip_file() {
  sed -e 's/^[[:space:]]*#.*$//' \
      -e 's/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/' \
      "$1" > "$STRIPPED" 2>/dev/null
}

# parse_allow RAW — echoes "<has_marker>\t<reason>" for the inline T2 allowlist.
#
# EXACT-TOKEN matching, not prefix matching. A bare substring test accepts
# `# lint-module-dependencies: allowed because …` as a marker and silently
# parses the reason as "ed because …", so a typo'd or merely similar-looking
# marker waives a real violation. The token must be followed by whitespace or
# by end-of-line — nothing else — which fails CLOSED: a near-miss spelling is
# not a marker at all, so the line stays a violation.
#
# The empty-reason case must still REGISTER as a marker (tail = ""), because an
# empty reason is REJECTED loudly rather than ignored; treating it as "no
# marker" would downgrade it to an ordinary unexplained violation and lose the
# specific diagnostic.
ALLOW_MARKER="# lint-module-dependencies: allow"
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

# first_token LINE TOKENFILE — the first token from TOKENFILE occurring in LINE.
# `sed -n '1p'` and not `head -1`: head exits on its first line, the upstream
# grep dies of SIGPIPE, and `pipefail` (set at the top of this script) promotes
# rc=141 into the substitution. `sed -n 1p` consumes all of its input, so
# nothing upstream ever sees a closed pipe. Keep every stage a full-input
# consumer.
first_token() {
  printf '%s\n' "$1" | grep -o -F -f "$2" | sed -n '1p'
}

scan_core_file() {
  local rel="$1"
  local file="$ROOT/$rel"
  local hits line n raw tok parsed has reason
  local t1_lines="|"

  if ! strip_file "$file"; then
    echo "lint-module-dependencies: cannot read $rel" >&2
    return 2
  fi

  # T1 — literal manifest tokens. Fixed-string matching: the tokens contain `.`
  # and `-`, and a BRE would let `scout.sh` match `scoutXsh`.
  if [ -s "$T1_TOKENS" ]; then
    hits=$(grep -n -F -f "$T1_TOKENS" "$STRIPPED")
    if [ -n "$hits" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        n="${line%%:*}"
        t1_lines="${t1_lines}${n}|"
        tok=$(first_token "${line#*:}" "$T1_TOKENS")
        echo "${rel}:${n}: lint-module-dependencies: T1 — core file names module path '${tok}'. Core must never reference a severable module (M3); the brownfield module declares no seam, so remove the call or move the logic into the module." >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\tT1\t${rel}:${n}\tnames module path '${tok}'\n"
      done <<< "$hits"
    fi
  fi

  # T2 — the path-shaped tokens, on lines T1 did not already claim.
  if [ -s "$T2_TOKEN_FILE" ]; then
    hits=$(grep -n -F -f "$T2_TOKEN_FILE" "$STRIPPED")
    if [ -n "$hits" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        n="${line%%:*}"
        case "$t1_lines" in *"|${n}|"*) continue ;; esac
        tok=$(first_token "${line#*:}" "$T2_TOKEN_FILE")
        # The allowlist marker lives in the COMMENT the stripper just removed,
        # so it is read off the RAW line — after the tiers have matched against
        # the stripped one.
        raw=$(sed -n "${n}p" "$file")
        parsed=$(parse_allow "$raw")
        has="$(printf '%s' "$parsed" | cut -f1)"
        reason="$(printf '%s' "$parsed" | cut -f2-)"
        if [ "$has" = "1" ]; then
          if [ -z "$reason" ]; then
            echo "${rel}:${n}: lint-module-dependencies: T2 allowlist marker present but the reason is empty. Write '# lint-module-dependencies: allow <why this is not a module reference>'." >&2
            VIOLATIONS=$((VIOLATIONS + 1))
            LIST_ROWS="${LIST_ROWS}FAIL\tT2\t${rel}:${n}\tallowlist marker with an empty reason\n"
          else
            LIST_ROWS="${LIST_ROWS}PASS\tT2\t${rel}:${n}\tallowlisted: ${reason}\n"
          fi
          continue
        fi
        echo "${rel}:${n}: lint-module-dependencies: T2 — path-shaped module token '${tok}' on an executed line of a core file. A runtime-composed reference (\"\$SCRIPT_DIR/lib/scout/\${part}.sh\") fuses the module exactly as thoroughly as a literal path. Remove it, or append '# lint-module-dependencies: allow <reason>' if this is prose in a string." >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\tT2\t${rel}:${n}\tmodule token '${tok}' on an executed line\n"
      done <<< "$hits"
    fi
  fi
  return 0
}

# scan_zero_dep_file REL — M5. A scout file may name NO core lib on an executed
# line. Not allowlistable: see the ALLOWLIST section.
scan_zero_dep_file() {
  local rel="$1"
  local file="$ROOT/$rel"
  local hits line n tok

  if ! strip_file "$file"; then
    echo "lint-module-dependencies: cannot read $rel" >&2
    return 2
  fi

  [ -s "$M5_TOKENS" ] || return 0
  hits=$(grep -n -F -f "$M5_TOKENS" "$STRIPPED")
  [ -n "$hits" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="${line%%:*}"
    tok=$(first_token "${line#*:}" "$M5_TOKENS")
    echo "${rel}:${n}: lint-module-dependencies: M5 — the scanner names core lib '${tok}' on an executed line. M5 requires the scanner to source NO core lib so its bootstrap works in a clone that has never run init.sh; re-implement the small subset you need (reuse-by-extraction: copy the predicate, not the dependency)." >&2
    VIOLATIONS=$((VIOLATIONS + 1))
    LIST_ROWS="${LIST_ROWS}FAIL\tM5\t${rel}:${n}\tscanner names core lib '${tok}'\n"
  done <<< "$hits"
  return 0
}

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  CORE_SCANNED=$((CORE_SCANNED + 1))
  scan_core_file "$rel" || { emit_list; exit 2; }   # MODULE-DEPS-DIRECTION-CALL
done < "$CORE_FILES"

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  scan_zero_dep_file "$rel" || { emit_list; exit 2; }   # MODULE-DEPS-M5-CALL
done < "$ZERODEP_FILES"

emit_list

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS module-dependency violation(s). Scout and the adoption driver are SEVERABLE modules (D1/§3.3): a module may import core, core may never import a module, and the scanner imports nothing. See scripts/lint-module-dependencies.sh header, docs/module-contract.md, and docs/designs/2026-08-02-brownfield-adoption-v1.md §3.3." >&2
  exit 1
fi

echo "OK: no core -> module edge and no scanner dependency ($CORE_SCANNED core file(s) scanned against $MODULE_PRESENT module path(s); $ZERODEP_COUNT zero-dep file(s) checked against $CORELIB_COUNT core lib(s); core allowlist empty)."
exit 0

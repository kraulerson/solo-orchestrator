#!/usr/bin/env bash
# scripts/lint-tests-registered.sh — fail CI if any tests/test-*.sh
# (or tests/edge-cases-*.sh) file is not invoked by at least one
# top-level test aggregator. Structural backstop for the BL-034 /
# BL-038 orphan-test defect class (closes BL-038).
#
# THE DEFECT CLASS
#   Wave 1-4 (PR #103 audit) found 16 of 17 newly-added test files
#   landed without ever being wired into an aggregator. The tests
#   passed locally during PR review, then ran ZERO times after merge
#   — every subsequent regression they would have caught flew silent.
#   BL-034 retroactively registered the Wave 1-4 cohort; BL-035 will
#   disposition the pre-existing orphan backlog. BL-038 is the
#   structural prevention: this lint refuses to merge a new
#   `tests/test-*.sh` file unless an aggregator invokes it (or the
#   file carries an explicit EXEMPT marker with a non-empty reason).
#
# WHAT COUNTS AS AN AGGREGATOR
#   Five aggregators are recognised by default; pass --aggregators to
#   override the list (used by tests/test-lint-tests-registered.sh).
#     • tests/full-project-test-suite.sh
#     • tests/edge-case-test-suite.sh
#     • tests/known-bugs-test-suite.sh
#     • tests/upgrade-path-tests.sh
#     • tests/host-drivers/run-all.sh
#   The host-drivers/run-all.sh entry uses a glob over
#   `*.test.sh` and `*.selftest.sh`, so any file matching those
#   patterns under tests/host-drivers/ is implicitly registered.
#
# WHAT COUNTS AS A TEST FILE
#   The walker enumerates:
#     • tests/test-*.sh
#     • tests/edge-cases-*.sh
#     • tests/host-drivers/*.test.sh
#     • tests/host-drivers/*.selftest.sh
#   The aggregator files themselves are skipped (they're delegators,
#   not tests). Files under tests/test-helpers/ (if/when that dir
#   exists) are skipped as helpers. The lint script itself is skipped.
#
# OVERRIDE MECHANISM (per-file EXEMPT marker)
#   A test file can opt out by placing one of:
#     # LINT_TEST_REGISTRATION_EXEMPT: <non-empty reason>
#   …inside the first 40 lines (header). The reason is REQUIRED —
#   an empty reason fails the lint, matching the allowlist semantics
#   of scripts/lint-counter-antipattern.sh and siblings. Use this for
#   genuine manual / network-dependent / slow tests that intentionally
#   stay out of the aggregator-driven suite.
#
# BRIDGE: KNOWN_ORPHANS_PENDING_BL035
#   ~48 pre-existing test files were already orphaned when BL-038
#   landed. Editing every one to add an EXEMPT marker would be 48
#   scattered diffs that have to be unwound when BL-035 dispositions
#   them. Instead they are listed in KNOWN_ORPHANS_PENDING_BL035
#   below — a single centralised bridge. The contract is:
#     • Adding to the list requires a paired BL-035 backlog update.
#     • Removing from the list requires the test be registered in an
#       aggregator (or replaced with a real EXEMPT marker if it is
#       a manual/network-only test).
#     • When BL-035 closes, this list must be empty.
#   Test fixtures (tests-dir override) skip the bridge — only the
#   canonical repo tests dir consults it.
#
# EXIT CODES
#   0 — every test file is registered, EXEMPT, or on the bridge list.
#   1 — one or more violations found.
#   2 — invocation / I/O error.
#
# USAGE
#   bash scripts/lint-tests-registered.sh           # quiet pass/fail
#   bash scripts/lint-tests-registered.sh --list    # PASS/FAIL table
#   bash scripts/lint-tests-registered.sh \
#       --tests-dir   /tmp/fixture/tests \
#       --aggregators /tmp/fixture/tests/myagg.sh
#       # test-mode: scan an alternate dir + alternate aggregator set
#
# PERFORMANCE (BL-067)
#   The original scan_file() looped over every aggregator and grepped
#   for each test's basename — O(n_tests × m_aggregators) subprocesses.
#   On the current repo shape (~100 tests × 5 aggregators × 2 greps
#   per aggregator + head/cut per file) that's ~1500+ subprocesses per
#   run; on a heavily loaded workstation this can wall-clock beyond
#   2 minutes and trip the pre-commit gate's timeout (BL-067 report).
#
#   This implementation collapses the work to O(n + m):
#     Pass 1: build a hash-set of every .sh basename referenced on a
#             non-comment line of every aggregator (one grep per
#             aggregator, then a pure-bash extraction loop).
#     Pass 2: enumerate test files under tests/ and check membership
#             in the hash-set in O(1). All per-file work (basename,
#             EXEMPT marker parsing) uses bash builtins — zero
#             subprocess spawn per file.
#   Output format, exit codes, diagnostics, and every branch of the
#   original decision tree (aggregator skip, host-drivers helper skip,
#   EXEMPT marker, bridge list, --list mode, --tests-dir override,
#   test-mode fixture semantics) are preserved byte-for-byte.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_PATH="$REPO_ROOT/scripts/lint-tests-registered.sh"

LIST_MODE=0
TESTS_DIR_OVERRIDE=""
AGGREGATORS_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST_MODE=1; shift ;;
    --tests-dir)
      [ $# -ge 2 ] || { echo "Usage: $0 [--list] [--tests-dir DIR] [--aggregators FILE[,FILE...]]" >&2; exit 2; }
      TESTS_DIR_OVERRIDE="$2"; shift 2 ;;
    --aggregators)
      [ $# -ge 2 ] || { echo "Usage: $0 [--list] [--tests-dir DIR] [--aggregators FILE[,FILE...]]" >&2; exit 2; }
      AGGREGATORS_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--list] [--tests-dir DIR] [--aggregators FILE[,FILE...]]"; exit 0 ;;
    *) echo "Usage: $0 [--list] [--tests-dir DIR] [--aggregators FILE[,FILE...]]" >&2; exit 2 ;;
  esac
done

TESTS_DIR="${TESTS_DIR_OVERRIDE:-$REPO_ROOT/tests}"
TEST_MODE=0
if [ -n "$TESTS_DIR_OVERRIDE" ] || [ -n "$AGGREGATORS_OVERRIDE" ]; then
  TEST_MODE=1
fi

# Aggregator list (default vs. --aggregators override).
declare -a AGGREGATORS
if [ -n "$AGGREGATORS_OVERRIDE" ]; then
  IFS=',' read -r -a AGGREGATORS <<< "$AGGREGATORS_OVERRIDE"
else
  AGGREGATORS=(
    "$REPO_ROOT/tests/full-project-test-suite.sh"
    "$REPO_ROOT/tests/edge-case-test-suite.sh"
    "$REPO_ROOT/tests/known-bugs-test-suite.sh"
    "$REPO_ROOT/tests/upgrade-path-tests.sh"
    "$REPO_ROOT/tests/host-drivers/run-all.sh"
  )
fi

# Pre-existing orphan tests (pre-BL-038) tracked by BL-035 for
# disposition. Bridge mechanism — see header. Remove an entry by:
#   (a) registering the test in an aggregator, OR
#   (b) adding a real `# LINT_TEST_REGISTRATION_EXEMPT: <reason>`
#       marker inside the test file's header.
# When BL-035 closes this array must be empty.
KNOWN_ORPHANS_PENDING_BL035=(
  test-docs-cluster-six-pack.sh
  test-lint-uat-scenarios.sh
  test-pending-approval.sh
  test-phase-finalize.sh
  test-platform-security-bugs-closer.sh
  test-poc-modes.sh
  test-pre-commit-gate-terminal-mode.sh
  test-process-checklist-auto-advance.sh
  test-process-checklist-classifier.sh
  test-record-claude-commit.sh
  test-session-test-gate-check-merge.sh
  test-specs-plans-remaining-quartet.sh
  test-test-gate-counter-sanitizer.sh
  test-test-gate-null-handling.sh
  test-unrecord-feature.sh
  test-validate-counter-sanitizer.sh
)

VIOLATIONS=0
LIST_ROWS=""

# ────────────────────────────────────────────────────────────────────
# BL-067 PASS 1: build REGISTERED_STR — a pipe-delimited string that
# encodes every .sh basename referenced on a non-comment line across
# ALL aggregators. Membership is `case "$REGISTERED_STR" in *"|$b|"*)`.
#
# Why a delimited string and not `declare -A`?
#   macOS ships bash 3.2 as /bin/bash, and the test suite (plus every
#   caller in scripts/pre-commit-gate.sh) invokes the linter through
#   /usr/bin/env bash which resolves to /bin/bash on default Macs.
#   Associative arrays are a bash 4.0+ feature — using them would
#   crash the lint on the exact platform the pre-commit gate runs on.
#   A pipe-delimited-string lookup is O(len(string)) per query, but
#   len(string) ≤ ~4KB for the whole repo — comfortably below the
#   O(n × m × grep-per-agg) subprocess cost that BL-067 is retiring.
#
# Contract semantics preserved from the original implementation:
#   • A "reference" is any occurrence of a token matching *.sh in
#     any file path (with or without leading directory components)
#     on a non-comment line of an aggregator.
#   • A line is a "comment line" iff its first non-whitespace char is
#     `#`. Inline trailing comments (e.g.
#     `bash test-foo.sh # note`) still count as references because
#     the leading token isn't `#`.
#   • Basename is derived via ${path##*/}, matching the original
#     $(basename "$file") semantics.
# ────────────────────────────────────────────────────────────────────
REGISTERED_STR="|"

_build_registered_set() {
  local agg fname base
  for agg in "${AGGREGATORS[@]}"; do
    [ -f "$agg" ] || continue
    # Single-pass extraction per aggregator:
    #   grep -vE strips pure-comment lines
    #   grep -oE emits every .sh token (paths and bare names both)
    # Then normalise each hit to its basename and append to the
    # delimited set (dedup keeps the string bounded).
    while IFS= read -r fname; do
      [ -n "$fname" ] || continue
      base="${fname##*/}"
      case "$REGISTERED_STR" in
        *"|$base|"*) ;;                                    # already in set
        *) REGISTERED_STR="${REGISTERED_STR}${base}|" ;;   # append
      esac
    done < <(grep -vE '^[[:space:]]*#' "$agg" 2>/dev/null \
             | grep -oE '[A-Za-z0-9_./+-]+\.sh' 2>/dev/null)
  done
}

# Locate the host-drivers run-all.sh aggregator (if present in the
# active AGGREGATORS list) — needed by _is_host_driver_implicit which
# preserves the original glob-based implicit-registration behaviour.
HOST_DRIVERS_DIR=""
for _agg in "${AGGREGATORS[@]}"; do
  case "$_agg" in
    */host-drivers/run-all.sh) HOST_DRIVERS_DIR="${_agg%/run-all.sh}"; break ;;
  esac
done
unset _agg

_is_aggregator() {
  local file="$1"
  local agg
  for agg in "${AGGREGATORS[@]}"; do
    [ "$agg" = "$file" ] && return 0
  done
  return 1
}

_is_known_orphan_bridge() {
  # Only honour the bridge list when scanning the canonical repo dir.
  # Fixture-mode scans (--tests-dir override) must see clean lint semantics.
  [ "$TEST_MODE" -eq 1 ] && return 1
  local needle="$1"
  local orphan
  for orphan in "${KNOWN_ORPHANS_PENDING_BL035[@]}"; do
    [ "$orphan" = "$needle" ] && return 0
  done
  return 1
}

# host-drivers/run-all.sh globs *.test.sh and *.selftest.sh, so any
# file matching those extensions under tests/host-drivers/ is
# implicitly registered as long as run-all.sh appears in the
# aggregator list.
_is_host_driver_implicit() {
  local file="$1"
  [ -n "$HOST_DRIVERS_DIR" ] || return 1
  case "$file" in
    "$HOST_DRIVERS_DIR"/*.test.sh|"$HOST_DRIVERS_DIR"/*.selftest.sh) return 0 ;;
  esac
  return 1
}

# Parse the EXEMPT marker out of the first 40 lines of the file.
# Sets EXEMPT_HAS (0 or 1) and EXEMPT_REASON (trimmed string). Uses
# pure-bash line reading + BASH_REMATCH — no head/grep/cut subprocess
# per file (a hot-loop win under BL-067).
_parse_exempt() {
  local file="$1"
  local line reason=""
  local lineno=0
  EXEMPT_HAS=0
  EXEMPT_REASON=""
  # Read up to 40 lines. Guard with [ -r ] so unreadable files fall
  # through to the "no marker" default (matches original head silence).
  [ -r "$file" ] || return 0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    [ "$lineno" -gt 40 ] && break
    # Match optional leading whitespace + '#' + optional whitespace +
    # the sentinel followed by ':'. Anything after the colon is the
    # reason (trimmed below).
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*LINT_TEST_REGISTRATION_EXEMPT:(.*)$ ]]; then
      reason="${BASH_REMATCH[1]}"
      # Trim leading and trailing whitespace (matches original ${var#..}/${var%..} idiom).
      reason="${reason#"${reason%%[![:space:]]*}"}"
      reason="${reason%"${reason##*[![:space:]]}"}"
      EXEMPT_HAS=1
      EXEMPT_REASON="$reason"
      return 0
    fi
  done < "$file"
  return 0
}

scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  # Bash-builtin basename via parameter expansion (no subprocess).
  local base="${file##*/}"
  local rel found=0
  if [ "$TEST_MODE" -eq 1 ]; then
    rel="$file"
  else
    rel="${file#"$REPO_ROOT"/}"
  fi

  # Skip the lint script itself (defensive — it's not under tests/).
  [ "$file" = "$SELF_PATH" ] && return 0

  # Skip aggregators (delegators, not tests).
  if _is_aggregator "$file"; then
    LIST_ROWS="${LIST_ROWS}SKIP\t${rel}\taggregator\n"
    return 0
  fi

  # Skip tests/test-helpers/* (helpers, not tests). Currently the dir
  # doesn't exist in the repo, but this future-proofs against helper
  # libraries landing under that path.
  case "$file" in
    */tests/test-helpers/*) LIST_ROWS="${LIST_ROWS}SKIP\t${rel}\ttest-helpers\n"; return 0 ;;
  esac

  # Skip tests/host-drivers/mock-cli.sh (driver helper invoked by the
  # other host-driver tests, not a test in its own right). Its
  # extension doesn't match *.test.sh / *.selftest.sh so it won't be
  # enumerated anyway, but make the skip explicit.
  case "$file" in
    */tests/host-drivers/mock-cli.sh) LIST_ROWS="${LIST_ROWS}SKIP\t${rel}\thost-drivers-helper\n"; return 0 ;;
  esac

  # EXEMPT marker check.
  _parse_exempt "$file"
  if [ "$EXEMPT_HAS" = "1" ]; then
    if [ -z "$EXEMPT_REASON" ]; then
      echo "${rel}: lint-tests-registered: EXEMPT marker present but allowlist requires non-empty reason — append a justification after the colon" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      LIST_ROWS="${LIST_ROWS}FAIL\t${rel}\texempt-empty-reason\n"
    else
      LIST_ROWS="${LIST_ROWS}PASS\t${rel}\texempt:${EXEMPT_REASON}\n"
    fi
    return 0
  fi

  # host-drivers glob: *.test.sh and *.selftest.sh under host-drivers/
  # are implicitly registered via run-all.sh's glob.
  if _is_host_driver_implicit "$file"; then
    LIST_ROWS="${LIST_ROWS}PASS\t${rel}\thost-drivers-glob\n"
    return 0
  fi

  # Bridge: pre-existing orphan tracked by BL-035 (repo-mode only).
  if _is_known_orphan_bridge "$base"; then
    LIST_ROWS="${LIST_ROWS}PASS\t${rel}\torphan-pending-BL-035\n"
    return 0
  fi

  # BL-067 hot-path: pipe-delimited-string membership test instead of
  # the old O(m_aggregators × 2 greps) inner loop. REGISTERED_STR was
  # populated in Pass 1 by _build_registered_set(). Zero subprocesses
  # per file — the whole check is a bash `case` glob against a small
  # in-memory string.
  case "$REGISTERED_STR" in
    *"|${base}|"*) found=1 ;;
    *) found=0 ;;
  esac
  if [ "$found" -eq 1 ]; then
    LIST_ROWS="${LIST_ROWS}PASS\t${rel}\tregistered\n"
  else
    echo "${rel}: lint-tests-registered: test file is not invoked by any aggregator (${AGGREGATORS[*]}). Register it in tests/full-project-test-suite.sh (or another aggregator) following the BL-034 cohort pattern, or add '# LINT_TEST_REGISTRATION_EXEMPT: <reason>' to the file header." >&2
    VIOLATIONS=$((VIOLATIONS + 1))
    LIST_ROWS="${LIST_ROWS}FAIL\t${rel}\tnot-registered\n"
  fi
}

# ── Pass 1: build the registered-basename hash-set once. ────────────
_build_registered_set

# ── Pass 2: enumerate test files under TESTS_DIR. The four globs ────
# cover the canonical patterns; missing dirs/no-match cases are
# skipped via the [ -f ] guard inside scan_file.
shopt -s nullglob
declare -a CANDIDATES=()
for f in "$TESTS_DIR"/test-*.sh; do CANDIDATES+=("$f"); done
for f in "$TESTS_DIR"/edge-cases-*.sh; do CANDIDATES+=("$f"); done
for f in "$TESTS_DIR"/host-drivers/*.test.sh; do CANDIDATES+=("$f"); done
for f in "$TESTS_DIR"/host-drivers/*.selftest.sh; do CANDIDATES+=("$f"); done
shopt -u nullglob

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  if [ "$TEST_MODE" -eq 1 ]; then
    # Empty fixture dir is legal in test mode (no tests = nothing to lint).
    [ "$LIST_MODE" -eq 1 ] && printf 'STATUS\tFILE\tDETAIL\n'
    echo "OK: no test files under $TESTS_DIR."
    exit 0
  fi
  echo "lint-tests-registered: no test files found under $TESTS_DIR — refusing to claim a clean pass" >&2
  exit 2
fi

for f in "${CANDIDATES[@]}"; do
  scan_file "$f"
done

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS violation(s) found. See scripts/lint-tests-registered.sh header for the registration / EXEMPT-marker contract." >&2
  exit 1
fi

echo "OK: every test file is registered with an aggregator (or EXEMPT)."
exit 0

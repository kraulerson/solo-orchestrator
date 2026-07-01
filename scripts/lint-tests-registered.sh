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
  test-bl029-integration.sh
  test-bl030-calibration-replay.sh
  test-bypass-audit-integrity.sh
  test-bypass-audit-lib.sh
  test-bypass-audit-schema.sh
  test-bypass-detector.sh
  test-bypass-patterns.sh
  test-bypass-sentinel.sh
  test-check-changelog-filter.sh
  test-check-commit-message.sh
  test-check-gate.sh
  test-check-phase-gate-counter-sanitizer.sh
  test-check-phase-gate.sh
  test-docs-cluster-six-pack.sh
  test-enforcement-level-init.sh
  test-enforcement-level-lib.sh
  test-enforcement-level-reconfigure.sh
  test-escalate-to-user.sh
  test-filesystem-gate-install.sh
  test-gate-principles.sh
  test-github-free-tier-403.sh
  test-init-atomic-finalize.sh
  test-init-no-remote-creation.sh
  test-init-non-interactive.sh
  test-init-other-host-attestation.sh
  test-init-schema-phase-gate.sh
  test-lint-uat-scenarios.sh
  test-out-of-band-detector.sh
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
  test-upgrade-bl030-backfill.sh
  test-upgrade-non-interactive.sh
  test-upgrade-paths.sh
  test-upgrade-personal-to-sponsored-poc.sh
  test-upgrade-to-production-preconditions.sh
  test-upgrade-to-production-warn.sh
  test-validate-counter-sanitizer.sh
  test-vendored-skills-install.sh
  test-verify-install-bl030-coverage.sh
)

VIOLATIONS=0
LIST_ROWS=""

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
  local run_all has_run_all=0 agg
  for agg in "${AGGREGATORS[@]}"; do
    case "$agg" in
      */host-drivers/run-all.sh) has_run_all=1; run_all="$agg"; break ;;
    esac
  done
  [ "$has_run_all" -eq 1 ] || return 1
  # File must live under the same host-drivers/ directory as run-all.sh.
  local hd_dir="${run_all%/run-all.sh}"
  case "$file" in
    "$hd_dir"/*.test.sh|"$hd_dir"/*.selftest.sh) return 0 ;;
  esac
  return 1
}

# Parse the EXEMPT marker out of the first 40 lines of the file.
# Emits "<has_marker>\t<reason>" — has_marker is 0 or 1.
_parse_exempt() {
  local file="$1"
  local marker_line reason=""
  marker_line=$(head -n 40 "$file" 2>/dev/null \
    | grep -E '^[[:space:]]*#[[:space:]]*LINT_TEST_REGISTRATION_EXEMPT:' \
    | head -n 1)
  if [ -z "$marker_line" ]; then
    printf '0\t\n'
    return 0
  fi
  reason="${marker_line#*LINT_TEST_REGISTRATION_EXEMPT:}"
  # Trim leading and trailing whitespace.
  reason="${reason#"${reason%%[![:space:]]*}"}"
  reason="${reason%"${reason##*[![:space:]]}"}"
  printf '1\t%s\n' "$reason"
}

scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  local base rel
  base=$(basename "$file")
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
  local exempt has_marker reason
  exempt=$(_parse_exempt "$file")
  has_marker=$(printf '%s' "$exempt" | cut -f1)
  reason=$(printf '%s' "$exempt" | cut -f2)
  if [ "$has_marker" = "1" ]; then
    if [ -z "$reason" ]; then
      echo "${rel}: lint-tests-registered: EXEMPT marker present but allowlist requires non-empty reason — append a justification after the colon" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      LIST_ROWS="${LIST_ROWS}FAIL\t${rel}\texempt-empty-reason\n"
    else
      LIST_ROWS="${LIST_ROWS}PASS\t${rel}\texempt:${reason}\n"
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

  # Real registration check: does any aggregator INVOKE this basename
  # on a non-comment line? A naive substring grep would false-positive
  # on `# Hook test scaffolding (same shape as test-foo.sh)` comments
  # in adjacent aggregator headers (caught during BL-038 self-test).
  # We anchor on a word-boundary-ish neighbourhood and then strip pure
  # comment lines (`^[whitespace]*#`) from the candidate set before
  # declaring a match.
  local agg found=0
  # Escape the basename's `.` so it doesn't act as a regex wildcard.
  local base_re="${base//./\\.}"
  # (^|[^[:alnum:]_-])basename([^[:alnum:]]|$) — matches the basename
  # as a whole token, allowing trailing quote / paren / EOL but
  # rejecting substring embeddings like `test-foo.sh.bak`.
  local re="(^|[^[:alnum:]_-])${base_re}([^[:alnum:]]|\$)"
  for agg in "${AGGREGATORS[@]}"; do
    [ -f "$agg" ] || continue
    # grep candidate lines, then drop pure-comment lines (a leading
    # `#` after optional whitespace). Any survivor counts as a real
    # invocation reference.
    if grep -nE "$re" "$agg" 2>/dev/null | grep -vqE '^[0-9]+:[[:space:]]*#'; then
      found=1
      break
    fi
  done

  if [ "$found" -eq 1 ]; then
    LIST_ROWS="${LIST_ROWS}PASS\t${rel}\tregistered\n"
  else
    echo "${rel}: lint-tests-registered: test file is not invoked by any aggregator (${AGGREGATORS[*]}). Register it in tests/full-project-test-suite.sh (or another aggregator) following the BL-034 cohort pattern, or add '# LINT_TEST_REGISTRATION_EXEMPT: <reason>' to the file header." >&2
    VIOLATIONS=$((VIOLATIONS + 1))
    LIST_ROWS="${LIST_ROWS}FAIL\t${rel}\tnot-registered\n"
  fi
}

# Enumerate test files under TESTS_DIR. The four globs cover the
# canonical patterns; missing dirs/no-match cases are skipped via the
# [ -e ] guard inside scan_file.
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

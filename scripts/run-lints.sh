#!/usr/bin/env bash
# scripts/run-lints.sh — canonical LOCAL lint runner for solo-orchestrator.
#
# Runs every scripts/lint-*.sh over the repo, one status line each, and exits
# non-zero iff any lint failed. This is the single command a contributor (or an
# agent) runs to reproduce the repo's CI lint gate locally without having to
# remember the individual lint names or their CI job wiring.
#
# WHAT IT RUNS
#   Every scripts/lint-*.sh EXCEPT scripts/lint-uat-scenarios.sh. That one is a
#   PARAMETRIZED authoring tool, not a repo lint: bare-invoked it exits 2 with a
#   usage message because it requires a <populated-html-file> argument (it
#   validates a single rendered UAT scenario file on demand). It is also not one
#   of the 8 CI-required lint jobs in .github/workflows/lint.yml, so running it
#   here would spuriously fail the sweep.
#
#   NOTE: lint-raw-read-prompt.sh (~40s) is a slow full-tree scan — it still
#   forks `echo "$line" | grep -Eq` PER LINE of every file it walks.
#   lint-counter-antipattern.sh USED to be the worse of the two (~90s when this
#   note was written; 407-469s on the tree as of 2026-07-31, 3 runs), but BL-191
#   made its scan single-pass and it now runs in ~4s. A full run is still a
#   couple of minutes — measured 1m58s on the macOS host. That is expected.
#
# NOT A SHIPPED SCRIPT
#   This is a DEV tool. It is deliberately NOT in any init.sh copy list and is
#   not sourced by any scaffold-shipped script, so it has no effect on the
#   scaffold source-closure check (tests/test-scaffold-source-closure.sh).
#
# EXIT STATUS
#   0  every scanned lint passed
#   1  at least one lint failed (each failing lint is named in the summary; the
#      operator re-runs `bash scripts/<name>` to see the detail)
#
# TESTABILITY
#   An optional first argument overrides the lint directory (default: this
#   script's own directory). tests/test-run-lints.sh points it at a temp dir of
#   stub lints to prove failure propagation without touching the real lints.
#
# PORTABILITY
#   bash-3.2 safe (no associative arrays, no ${var,,}). Runs under
#   `set -uo pipefail` — deliberately NOT `-e`: a single failing lint must never
#   abort the loop before the summary prints, so failures are COLLECTED and
#   reported at the end.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LINT_DIR="${1:-$SCRIPT_DIR}"

# Parametrized tool, not a repo lint (bare exit 2 on missing HTML arg); skip it.
EXCLUDE="lint-uat-scenarios.sh"

total=0
passed=0
failed=0
failed_names=""

for lint in "$LINT_DIR"/lint-*.sh; do
  # bash 3.2 has no nullglob: if nothing matched, the literal pattern survives
  # and is not a real file — skip it.
  [ -f "$lint" ] || continue
  name="$(basename "$lint")"
  [ "$name" = "$EXCLUDE" ] && continue

  total=$((total + 1))
  if bash "$lint" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'FAIL  %s\n' "$name"
    failed=$((failed + 1)); failed_names="$failed_names $name"  # RUN-LINTS-FAIL-COLLECT
  fi
done

echo "----"
if [ "$failed" -eq 0 ]; then
  echo "run-lints: $total lints — $passed passed, 0 failed"
  exit 0
fi

echo "run-lints: $total lints — $passed passed, $failed failed —$failed_names"
echo "re-run a failing lint directly to see detail: bash scripts/<name>"
exit 1

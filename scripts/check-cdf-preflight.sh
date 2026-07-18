#!/usr/bin/env bash
# scripts/check-cdf-preflight.sh — BL-096 (ergonomics F9): report an absent
# Claude Dev Framework clone AT THE POINT OF ENTRY with the exact clone line.
#
# Before this existed, tests/init.sh needing ~/.claude-dev-framework failed
# DEEP in a suite run on a fresh host, with nothing telling the operator the
# one command that fixes it. This probe uses the same presence predicate
# init.sh uses (a .git dir AND scripts/init.sh inside the clone).
#
# Contract: rc=0 present (one [OK] line), rc=1 absent (WARN + the clone line
# on stderr). CALLERS choose warn-vs-abort: tests/full-project-test-suite.sh
# wires this `|| true` (# BL-096-CDF-PREFLIGHT) because the CI core shard
# runs CDF-less by design — init.sh auto-clones over the network there — so
# absence must never abort the suite, only inform the operator.
set -uo pipefail

CDF="$HOME/.claude-dev-framework"

if [ -d "$CDF/.git" ] && [ -f "$CDF/scripts/init.sh" ]; then
  echo "[OK] Claude Dev Framework clone present at $CDF"
  exit 0
fi

echo "[WARN] $CDF not found (or incomplete: needs .git/ and scripts/init.sh)." >&2
echo "  Scaffold tests will attempt a network auto-clone; on a no-network host they fail deep in the run." >&2
echo "  Provision it now (CONTRIBUTING.md 'Local development setup'):" >&2
echo "    git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework" >&2
exit 1

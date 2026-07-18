#!/usr/bin/env bash
# scripts/install-contributor-hooks.sh — BL-096 (ergonomics F10): the
# contributor hook bootstrap as ONE command instead of a copy-pasted recipe.
#
#   bash scripts/install-contributor-hooks.sh
#
# init.sh installs gates for USER projects; contributors working on the
# framework itself previously had to hand-run the cp+chmod documented in
# CONTRIBUTING.md ("Local development setup") — and discovering that at PR
# time meant local commits never faced the gates CI enforces. This script IS
# that documented step: installs scripts/pre-commit-gate.sh as
# .git/hooks/pre-commit (executable). Idempotent — re-running refreshes the
# hook to the current gate script.
#
# Refuses outside a framework checkout root: it must find BOTH ./.git and
# ./scripts/pre-commit-gate.sh at the invocation directory, so it cannot
# stamp the framework gate into an unrelated repo by accident.
set -euo pipefail

ROOT="$(pwd)"

if [ ! -d "$ROOT/.git" ] || [ ! -f "$ROOT/scripts/pre-commit-gate.sh" ]; then
  echo "[FAIL] not a framework checkout root: need ./.git and ./scripts/pre-commit-gate.sh here." >&2
  echo "  Run from the root of your solo-orchestrator clone:" >&2
  echo "    bash scripts/install-contributor-hooks.sh" >&2
  exit 1
fi

mkdir -p "$ROOT/.git/hooks"
# BL-096-CONTRIB-HOOK-INSTALL: the one load-bearing action — the real gate,
# byte-identical, executable, at the path git consults.
cp "$ROOT/scripts/pre-commit-gate.sh" "$ROOT/.git/hooks/pre-commit"
chmod +x "$ROOT/.git/hooks/pre-commit"

echo "[OK] pre-commit gate installed -> .git/hooks/pre-commit (from scripts/pre-commit-gate.sh)"
echo "     Local commits now face the same gates CI runs. Re-run any time to refresh."

#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Changelog Freshness Check
# https://github.com/kraulerson/solo-orchestrator
#
# Checks if source files changed without a CHANGELOG.md update.
# Emits a GitHub Actions warning annotation when source changed without changelog.
#
# Usage: bash scripts/check-changelog.sh
# Environment:
#   SOIF_STRICT_CHANGELOG=true  — exit 1 instead of warning (default: false)
#
# Exit codes:
#   0 — changelog is up to date, or no source files changed, or warn mode
#   1 — source changed without changelog (only when SOIF_STRICT_CHANGELOG=true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# BL-046: sources helpers-core.sh (subset) instead of helpers.sh (full)
# — uses print_ok / print_warn only. Skips the ~110 lines of init_log +
# MCP-detection helpers in helpers-full.sh to shave parse cost.
if [ -f "$SCRIPT_DIR/lib/helpers-core.sh" ]; then
  source "$SCRIPT_DIR/lib/helpers-core.sh"
else
  # Minimal fallback if helpers not available
  print_warn() { echo "[WARN] $1"; }
  print_ok()   { echo "  [OK] $1"; }
fi

# Detect changed files (PR diff or push diff)
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  # Pull request — diff against base branch
  changed=$(git diff --name-only "origin/$GITHUB_BASE_REF"...HEAD 2>/dev/null || echo "")
elif git rev-parse HEAD~1 &>/dev/null; then
  # Push — diff against previous commit
  changed=$(git diff --name-only HEAD~1..HEAD 2>/dev/null || echo "")
else
  # Initial commit — no previous commit to diff against
  changed=$(git diff --name-only --cached 2>/dev/null || echo "")
fi

if [ -z "$changed" ]; then
  exit 0
fi

# Source file extensions (excluding tests, configs, lockfiles, docs).
#
# code-checks-utility-2: the prior test-file filter `(test|spec|_test|Test)\.`
# was unanchored: `latest.ts`, `contest.py`, `protest.go`, `attestable.rb`
# all matched it on the substring `test.`, silently exempting them from
# the changelog-freshness warning. Fixed by anchoring each test-naming
# convention so only true test files are excluded:
#   *.test.ts        → JS/TS test convention      (.test\.)
#   *.spec.ts        → JS/TS spec convention      (.spec\.)
#   *_test.go        → Go test convention         (_test\.)
#   *_spec.rb        → Ruby RSpec convention      (_spec\.)
#   FooTest.java     → Java/Kotlin/C# convention  (Test\.[a-z]+$)
#   FooSpec.kt       → Kotlin spec convention     (Spec\.[a-z]+$)
# Also anchored: __tests__/ and __spec__/ directory conventions.
source_changed=$(echo "$changed" \
  | grep -E '\.(ts|tsx|js|jsx|py|rs|go|cs|kt|java|dart|swift|rb)$' \
  | grep -vE '(\.test\.|\.spec\.|_test\.|_spec\.|Test\.[a-z]+$|Spec\.[a-z]+$|/__tests__/|/__spec__/)' \
  | grep -vE '(\.config\.|\.setup\.|\.d\.ts$)' \
  | grep -vE '(jest|vitest|playwright|cypress)\.' \
  || true)

changelog_changed=$(echo "$changed" | grep -qE '^CHANGELOG\.md$' && echo "yes" || echo "")

if [ -n "$source_changed" ] && [ -z "$changelog_changed" ]; then
  file_count=$(echo "$source_changed" | wc -l | tr -d ' ')
  msg="$file_count source file(s) changed without CHANGELOG.md update. Document this change in the changelog."
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning::$msg"
  else
    print_warn "$msg"
  fi
  if [ "${SOIF_STRICT_CHANGELOG:-false}" = "true" ]; then
    exit 1
  fi
else
  if [ -n "$source_changed" ]; then
    print_ok "Changelog updated with source changes"
  fi
fi

exit 0

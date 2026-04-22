#!/usr/bin/env bash
# scripts/host-drivers/github.sh — GitHub driver.
# Uses `gh` CLI for creation and authentication, GitHub REST API for protection.
# Implements the solo-orchestrator host driver contract defined in spec
# docs/superpowers/specs/2026-04-21-host-aware-repo-gate-design.md.

host_name() { echo "github"; }

host_require_cli() {
  if ! command -v gh >/dev/null 2>&1; then
    printf '%s\n' \
      'github driver: `gh` CLI not installed.' \
      '' \
      'Install via one of:' \
      '  macOS:   brew install gh' \
      '  Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md' \
      '  Windows: https://github.com/cli/cli#installation' \
      '' \
      'Then authenticate:' \
      '  gh auth login' \
      '' \
      'Re-run whatever invoked this after install+auth completes.' >&2
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    printf '%s\n' \
      'github driver: `gh` installed but not authenticated.' \
      '' \
      'Authenticate with: gh auth login' \
      '' \
      'Re-run after auth completes.' >&2
    return 2
  fi
  return 0
}

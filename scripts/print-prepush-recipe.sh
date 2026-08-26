#!/usr/bin/env bash
# Solo Orchestrator — print the pre-push capture-and-replay block.
#
# ONE OWNER FOR THE RECIPE. The append-one-liner used to be retyped in three
# scripts, byte-identical and with no sync marker — `# BL-084-TIER-KEY`'s class,
# and it drifted the moment the recipe changed. Those three now point here, and
# the block itself lives in scripts/lib/hook-templates.sh with the pre-commit
# and commit-msg bodies.
#
# Paste the output at the TOP of an existing .git/hooks/pre-push. Your own hook
# body needs NO edits: the block captures git's ref list once, hands it to the
# review gate, and re-feeds the original list to everything below it.
set -euo pipefail

_dir="$(cd "$(dirname "$0")" && pwd)"
_lib="$_dir/lib/hook-templates.sh"
[ -f "$_lib" ] || { echo "print-prepush-recipe: $_lib not found" >&2; exit 2; }
# shellcheck source=./lib/hook-templates.sh
. "$_lib"
command -v soif_emit_prepush_preamble >/dev/null 2>&1 || {
  echo "print-prepush-recipe: hook-templates.sh does not provide soif_emit_prepush_preamble." >&2
  echo "  That library predates the pre-push recipe. Refresh it:" >&2
  echo "    bash scripts/upgrade-project.sh --sync-framework" >&2
  echo "  or copy scripts/lib/hook-templates.sh from the orchestrator checkout." >&2
  exit 2
}
soif_emit_prepush_preamble

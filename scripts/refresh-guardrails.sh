#!/usr/bin/env bash
# scripts/refresh-guardrails.sh — `## BL-318:` G5. Update THIS project's
# Development Guardrails (CDF) to the version in the Guardrails clone, and
# nothing else.
#
#   bash scripts/refresh-guardrails.sh        # from the project's root folder
#
# The session-start version check (session-version-check.sh, from the
# check-versions.sh row `# BL-318-G5-OFFER`) offers this command when the
# project's `.claude/manifest.json` -> `frameworkVersion` is older than the
# clone's FRAMEWORK_VERSION. The agent must not run it: the Guardrails'
# config-guard blocks the agent writing `.claude/framework/` and
# `.claude/manifest.json`. The human types it after `!` at the Claude Code
# prompt, where it runs with no TTY.
#
# WHY NOT `upgrade-project.sh --sync-framework`. Measured 2026-10-05 against a
# Guardrails 4.3.0 project and a 4.3.7 clone, run as `!` runs it (stdin not a
# TTY, no CI, no SOIF_NONINTERACTIVE): it DOES apply the Guardrails refresh —
# and in the same run re-synced 70 of 74 vendored scripts, backfilled
# scripts/lib/ files, the vendored skills and .gitignore, and stamped
# soloFrameworkCommit: 85 paths changed where the Guardrails update is the files
# under .claude/framework/ and one manifest key pair. That is more than a
# person agreed to when they said yes to "update the Guardrails".
# `--backfill-only` runs the same backfill before the same refresh.
#
# WHAT IT DOES. The clone's own canonical updater, refresh_cdf_assets
# (`$CLONE/scripts/cdf-refresh.sh`, the function upgrade-project.sh reaches
# through scripts/lib/cdf-refresh.sh): `git pull --ff-only` on the clone (a
# failure warns and refreshes from the clone as it is), copies hooks/*.sh,
# hooks/*.txt, rules/*.md and gates/*.sh into .claude/framework/, marks the
# hooks and gates executable, and sets frameworkVersion and frameworkCommit in
# .claude/manifest.json. It does not touch .claude/settings.json (refreshing
# that is `## BL-319:`, deferred).
#
# WHY NOT THE SOLO WRAPPER. solo_refresh_cdf turns every "could not" into a
# warning and return 0, which is right inside an upgrade (the refresh is an
# addition there) and wrong here, where the refresh is the whole job: a missing
# clone must not end in a success. So this checks its preconditions before
# writing anything, then checks the result — the RECEIPT: every file the
# refresh copies is byte-identical in the project, the hooks and gates are
# executable (Claude Code runs them by path; one it cannot execute is a check
# that silently stops running), and the manifest names the clone's version.
# Anything short of that is [FAIL] and a non-zero exit.
#
# The clone is ${CDF_HOME:-$HOME/.claude-dev-framework}, the clone
# check-versions.sh compares against. bash 3.2 safe.
set -uo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'USAGE'
Usage: bash scripts/refresh-guardrails.sh

Updates this project's Development Guardrails to the version in the
Guardrails clone (${CDF_HOME:-$HOME/.claude-dev-framework}). Run it from the
project's root folder. It pulls the clone (fast-forward only), copies the
Guardrails hooks, rules and gates into .claude/framework/, and records the new
version in .claude/manifest.json. It does not change .claude/settings.json.
USAGE
  exit 0
fi
if [ $# -gt 0 ]; then
  echo "[FAIL] refresh-guardrails.sh takes no arguments (got: $*). See: bash scripts/refresh-guardrails.sh --help" >&2
  exit 2
fi

PROJECT_ROOT="$(pwd)"
CLONE="${CDF_HOME:-$HOME/.claude-dev-framework}"
UPSTREAM="$CLONE/scripts/cdf-refresh.sh"
ROW="Development Guardrails in this project"

_rg_fail() {
  echo "[FAIL] $1" >&2
  shift
  while [ $# -gt 0 ]; do echo "       $1" >&2; shift; done
  exit 1
}

# ── Preconditions: nothing is written until all of these hold ────────────────
[ -d "$PROJECT_ROOT/.claude/framework" ] || _rg_fail "no .claude/framework/ in $PROJECT_ROOT, so there are no Guardrails here to update." "Run this from the root folder of a project that has the Guardrails. Nothing was changed."   # BL-318-G5-REFRESH-PROJECT
[ -f "$PROJECT_ROOT/.claude/manifest.json" ] || _rg_fail "no .claude/manifest.json in $PROJECT_ROOT, so the update has nowhere to record its version." "Nothing was changed."   # BL-318-G5-REFRESH-MANIFEST
[ -f "$UPSTREAM" ] || _rg_fail "no Guardrails clone at $CLONE (it has no scripts/cdf-refresh.sh), so there is nothing to update from." "Get the clone, then run this again:" "  git clone https://github.com/kraulerson/claude-dev-framework.git \"$CLONE\"" "Nothing was changed."   # BL-318-G5-REFRESH-CLONE

BEFORE="$(jq -r '.frameworkVersion // "none recorded"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null || echo "unreadable")"

# shellcheck source=/dev/null
. "$UPSTREAM"
command -v refresh_cdf_assets >/dev/null 2>&1 || _rg_fail "$UPSTREAM does not define refresh_cdf_assets, so this clone cannot update a project." "Pull the clone (cd $CLONE && git pull --ff-only) and run this again. Nothing was changed."   # BL-318-G5-REFRESH-DEFINED

# ── The update: the clone's own refresh, never interactive ───────────────────
RC=0
refresh_cdf_assets "$PROJECT_ROOT" "$CLONE" true || RC=$?
[ "$RC" -eq 0 ] || _rg_fail "the Guardrails refresh returned $RC. Its own messages are above." "Check git status: some files in .claude/framework/ may have changed."   # BL-318-G5-REFRESH-RC

# ── The receipt ──────────────────────────────────────────────────────────────
STALE=""
NOEXEC=""
for SUB_EXT in hooks:sh hooks:txt rules:md gates:sh; do
  SUB="${SUB_EXT%%:*}"; EXT="${SUB_EXT#*:}"
  for SRC in "$CLONE/$SUB"/*."$EXT"; do
    [ -f "$SRC" ] || continue
    DST="$PROJECT_ROOT/.claude/framework/$SUB/${SRC##*/}"
    if ! cmp -s "$SRC" "$DST"; then
      STALE="$STALE .claude/framework/$SUB/${SRC##*/}"                                # BL-318-G5-RECEIPT-FILES
    elif [ "$EXT" = sh ] && [ ! -x "$DST" ]; then
      NOEXEC="$NOEXEC .claude/framework/$SUB/${SRC##*/}"                              # BL-318-G5-RECEIPT-EXEC
    fi
  done
done
[ -z "$STALE" ] || _rg_fail "these files do not match the clone after the update:$STALE" "The update did not land; check git status before committing anything."
[ -z "$NOEXEC" ] || _rg_fail "these are not executable, and Claude Code runs them by path:$NOEXEC" "Mark them executable (chmod +x) or run this again."

WANT="$(tr -d '[:space:]' < "$CLONE/FRAMEWORK_VERSION" 2>/dev/null || :)"
AFTER="$(jq -r '.frameworkVersion // empty' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null || :)"
{ [ -n "$WANT" ] && [ "$AFTER" = "$WANT" ]; } || _rg_fail ".claude/manifest.json records frameworkVersion '${AFTER}', not the clone's '${WANT}'." "The files were copied but the version was not recorded (is jq installed?)."   # BL-318-G5-RECEIPT-VERSION

echo "[OK] $ROW updated: ${BEFORE} -> ${AFTER}"
echo "     Changed: the hooks, rules and gates in .claude/framework/, and the version in .claude/manifest.json."
echo "     .claude/settings.json was not changed."
echo "     The new hooks apply from the next tool call: Claude Code runs each hook from its file every time."
echo "     Commit .claude/framework/ and .claude/manifest.json when you are ready."

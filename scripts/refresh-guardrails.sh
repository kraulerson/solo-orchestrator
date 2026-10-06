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
# clone's FRAMEWORK_VERSION. The agent is told not to run it — it replaces the
# Guardrails that check the agent's own work, so starting it is the human's
# decision — and the human types it after `!` at the Claude Code prompt, where
# it runs with no TTY. Nothing here enforces that: the Guardrails' config-guard
# blocks the agent editing `.claude/framework/` and `.claude/manifest.json`
# directly, but it reads command text and allows this command (measured,
# Guardrails 4.3.7; `## BL-318:` G5 residuals).
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
# WHAT IT DOES. It pulls the clone (`git pull --ff-only`) itself first — the
# clone is shared by every project on the machine, and the pull can move it past
# the version the offer named — so the checks below read what will actually be
# installed. Then the clone's own canonical updater, refresh_cdf_assets
# (`$CLONE/scripts/cdf-refresh.sh`, the function upgrade-project.sh reaches
# through scripts/lib/cdf-refresh.sh), pulls again (a no-op by then; a failure
# warns and it refreshes from the clone as it is), copies hooks/*.sh,
# hooks/*.txt, rules/*.md and gates/*.sh into .claude/framework/, marks the
# hook scripts executable, and sets frameworkVersion and frameworkCommit in
# .claude/manifest.json. Then (`## BL-320:`, Karl's c2, 2026-10-06) it adds to
# .claude/settings.json the Guardrails hook registrations the manifest's
# activeHooks call for and the file lacks — CDF's own entries, from the clone's
# generator — and names each one; it removes, reorders and rewrites nothing
# there (scripts/lib/guardrails.sh soif_cdf_register_hooks). Without that a
# release's new hook — 4.4.0's record-approval.sh, which reads the user's
# answer to an approval question — is copied but never runs. The rest of
# settings refreshing stays `## BL-319:`.
#
# WHAT IT REFUSES, before writing anything in the project (review round 1; the
# MAJOR check runs after the clone's pull, so the shared clone may have moved): a symlink on the
# write path (R-8b: it would write through it, outside the project); an
# uncommitted change in what the clone copies (R-8a: the manifest would record a
# commit that does not contain it, and every later check would call the project
# current); and a different MAJOR version (R-3: CDF treats a major as a
# migration — migrations/, and sync.sh's "MAJOR version bump detected" — and
# with no restart the new hooks would run at once against the old settings).
#
# WHY NOT THE SOLO WRAPPER. solo_refresh_cdf turns every "could not" into a
# warning and return 0, which is right inside an upgrade (the refresh is an
# addition there) and wrong here, where the refresh is the whole job: a missing
# clone must not end in a success. So this checks its preconditions before
# writing anything, then checks the result — the RECEIPT: every file the
# refresh copies is byte-identical in the project, the hook scripts are
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
project's root folder. It first pulls that clone (fast-forward only); every
project on this machine reads the same clone, and the pull can bring a newer
version than the one you were offered. Then it copies the Guardrails hooks and
rules into .claude/framework/ and records the new version in
.claude/manifest.json. In .claude/settings.json it only adds the Guardrails
hook registrations that are missing there, and names each one; it removes and
rewrites nothing in that file.

It refuses a new MAJOR version (that is a migration), an uncommitted change
in the clone's hooks or rules, and a symlink in .claude/framework/. When it
refuses, nothing in this project is changed; the shared clone may already have
been pulled.
USAGE
  exit 0
fi
if [ $# -gt 0 ]; then
  echo "[FAIL] refresh-guardrails.sh takes no arguments (got: $*). See: bash scripts/refresh-guardrails.sh --help" >&2
  exit 2
fi

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

[ -f "$SCRIPT_DIR/lib/guardrails.sh" ] || _rg_fail "scripts/lib/guardrails.sh is missing beside this script, so the Guardrails hook registrations could not be checked after the update." "Re-sync this project's framework scripts first. Nothing was changed."   # BL-320-RG-LIB
# shellcheck source=scripts/lib/guardrails.sh
. "$SCRIPT_DIR/lib/guardrails.sh"

# No symlink on the write path: cp and chmod follow links, so a linked folder
# or file would be rewritten wherever it points, outside the project.
for LINK in "$PROJECT_ROOT/.claude" "$PROJECT_ROOT/.claude/framework" "$PROJECT_ROOT/.claude/framework/hooks" "$PROJECT_ROOT/.claude/framework/rules" "$PROJECT_ROOT/.claude/framework/gates"; do
  [ ! -L "$LINK" ] || _rg_fail "${LINK#"$PROJECT_ROOT"/} is a symlink, so the update would write through it to wherever it points." "Replace the link with a real folder, then run this again. Nothing was changed."   # BL-318-G5-REFRESH-LINK-DIR
done
for LINK in "$PROJECT_ROOT"/.claude/framework/hooks/* "$PROJECT_ROOT"/.claude/framework/rules/* "$PROJECT_ROOT"/.claude/framework/gates/*; do
  [ ! -L "$LINK" ] || _rg_fail "${LINK#"$PROJECT_ROOT"/} is a symlink, so the update would overwrite the file it points to." "Replace the link with a copy of the file, then run this again. Nothing was changed."   # BL-318-G5-REFRESH-LINK-FILE
done

# Nothing uncommitted in what the clone copies: the manifest records the clone's
# HEAD as frameworkCommit, and that commit would not contain the change.
DIRTY="$(git -C "$CLONE" status --porcelain -- 'hooks/*.sh' 'hooks/*.txt' 'rules/*.md' 'gates/*.sh' FRAMEWORK_VERSION 2>/dev/null | tr '\n' ';' || :)"   # BL-318-G5-REFRESH-PORCELAIN
[ -z "$DIRTY" ] || _rg_fail "the clone at $CLONE has uncommitted changes in what the update copies ($DIRTY)." "The manifest would record a commit that does not contain them, and every later check would call this project current." "Commit or discard them in the clone (cd \"$CLONE\" && git status), then run this again. Nothing was changed."   # BL-318-G5-REFRESH-DIRTY

# Pull first, so the version checked below is the one that will be installed
# (refresh_cdf_assets's own pull then has nothing to do). No prompt: there is no
# one to answer it. A failure is reported by that second pull, as before.
GIT_TERMINAL_PROMPT=0 git -C "$CLONE" pull --ff-only --quiet >/dev/null 2>&1 || :   # BL-318-G5-REFRESH-PULL

_rg_xyz() { local re='^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$'; [[ "${1:-}" =~ $re ]]; }
INST="$(jq -r '.frameworkVersion // empty' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null || :)"
WANT="$(tr -d '[:space:]' < "$CLONE/FRAMEWORK_VERSION" 2>/dev/null || :)"
{ _rg_xyz "$INST" && _rg_xyz "$WANT" && [ "${INST%%.*}" -ne "${WANT%%.*}" ]; } && _rg_fail "this project has Guardrails $INST and the clone has $WANT: a different MAJOR version is a migration, not this update." "See $CLONE/migrations/ and the Guardrails' own upgrade notes. Nothing in this project was changed."   # BL-318-G5-REFRESH-MAJOR
# `## BL-320:` a MIXED install is refused too. Guardrails at or above the
# minimum (4.4.0) take an approval only as the user's answer to a schema-2
# question; this project's own scripts/pending-approval.sh may predate that and
# write schema 1 (it lacks `SOIF_APPROVAL_SCHEMA=2`). Installed alone, the new
# Guardrails would leave no way to approve a commit by reply, so the two halves
# move together: the framework sync updates the scripts AND the Guardrails.
soif_gr_mixed "$PROJECT_ROOT" "$WANT" && _rg_fail "this project's Solo scripts still write the older approval question (its scripts/pending-approval.sh predates schema 2), and Guardrails $WANT cannot take an answer to it: installed alone, they would leave no way to approve a commit by reply." "Update both together with the framework sync instead, from this project's folder (the path to your own clone of the framework, if it is elsewhere):" "  bash ~/solo-orchestrator/scripts/upgrade-project.sh --sync-framework" "Nothing in this project was changed; the shared clone may already have been pulled."   # BL-320-RG-MIXED
BEFORE="$(printf '%s' "$INST" | LC_ALL=C tr -c '0-9A-Za-z._+-' '?' | LC_ALL=C cut -c1-40)"
[ -n "$BEFORE" ] || BEFORE="none recorded"

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
KINDS="hooks:sh hooks:txt rules:md gates:sh"                                          # BL-318-G5-RECEIPT-KINDS
for SUB_EXT in $KINDS; do
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

# ── `## BL-320:` register what the new version adds ──────────────────────────
REG_RC=0
REG_OUT=""
REG_OUT="$(soif_cdf_register_hooks "$PROJECT_ROOT" "$CLONE" 2>&1)" || REG_RC=$?   # BL-320-RG-REGISTER
[ "$REG_RC" -eq 0 ] || _rg_fail "the Guardrails hooks and rules were updated to ${AFTER}, but their hook registrations in .claude/settings.json were not checked:" "$REG_OUT" "Fix that, then run this again: it adds only what is missing."

echo "[OK] $ROW updated: ${BEFORE} -> ${AFTER}"   # BL-318-G5-REFRESH-OK
echo "     Changed: the Guardrails hooks and rules in .claude/framework/ (its hooks/, rules/ and gates/ folders), and the version in .claude/manifest.json."
if printf '%s\n' "$REG_OUT" | grep -q '^  + '; then
  echo "     $(printf '%s\n' "$REG_OUT" | head -1)"
  printf '%s\n' "$REG_OUT" | grep '^  + ' | sed 's/^/     /'
  echo "     Claude Code reloads .claude/settings.json on its own; no restart is needed."
else
  echo "     .claude/settings.json was not changed: every Guardrails hook registration was already there."
fi
echo "     The new hooks apply from the next tool call: Claude Code runs each hook from its file every time."
echo "     Commit .claude/framework/, .claude/manifest.json (and .claude/settings.json, if it changed) when you are ready."

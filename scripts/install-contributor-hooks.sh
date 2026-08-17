#!/usr/bin/env bash
# scripts/install-contributor-hooks.sh — BL-096 (ergonomics F10): the
# contributor hook bootstrap as ONE command instead of a copy-pasted recipe.
#
#   bash scripts/install-contributor-hooks.sh
#
# init.sh installs gates for USER projects; contributors working on the
# framework itself would otherwise have to hand-run a recipe from
# CONTRIBUTING.md, and discovering that at PR time means local commits never
# faced the gates CI enforces.
#
# ── BL-239: THIS SCRIPT USED TO INSTALL A NO-OP AND SAY OTHERWISE ───────────
# It did `cp scripts/pre-commit-gate.sh .git/hooks/pre-commit` and printed
# "Local commits now face the same gates CI runs." They faced NOTHING.
# `pre-commit-gate.sh` is a PreToolUse hook: with no flags it reads tool-input
# JSON on stdin and "no output" means ALLOW. Git invokes a pre-commit hook with
# NO arguments and no such JSON, so every commit took the allow path and exited
# 0 SILENTLY. Measured, hermetically, both ways on the same fixture commit:
#
#   cp the gate (the old behaviour)      -> commit rc=0, 0 lines of gate output
#   the hook init.sh generates (below)   -> commit rc=0, 3 lines: the gitleaks
#                                           and semgrep arms actually ran, and
#                                           semgrep reported SAST NOT ENFORCED
#                                           per `# BL-112-SAST-NOTRUN`
#
# A false claim inside the one script whose entire job is installing
# enforcement. That is why this now emits the SAME hooks init.sh does, from the
# SAME library — `scripts/lib/hook-templates.sh` is the one owner, so the
# contributor hook and the generated-project hook cannot drift:
#
#   .git/hooks/pre-commit   soif_write_precommit_hook       (gitleaks, SAST,
#                                                            test co-location,
#                                                            blocked-commit ledger)
#   .git/hooks/commit-msg   soif_emit_tdd_commitmsg_block   (BL-072 TDD ordering
#                                                            + BL-006 Build-Loop
#                                                            message check)
#
# The commit-msg half was previously not installed AT ALL for contributors, so
# the TDD-ordering gate and the Build-Loop message check never ran on a
# framework contributor's commits either.
#
# Idempotent — re-running refreshes both hooks to the current templates.
#
# Refuses outside a framework checkout root: it must find `./.git` and the
# template library at the invocation directory, so it cannot stamp framework
# hooks into an unrelated repo by accident.
set -euo pipefail

ROOT="$(pwd)"

if [ ! -d "$ROOT/.git" ] || [ ! -f "$ROOT/scripts/lib/hook-templates.sh" ]; then
  echo "[FAIL] not a framework checkout root: need ./.git and ./scripts/lib/hook-templates.sh here." >&2
  echo "  Run from the root of your solo-orchestrator clone:" >&2
  echo "    bash scripts/install-contributor-hooks.sh" >&2
  exit 1
fi

# shellcheck source=./lib/hook-templates.sh
. "$ROOT/scripts/lib/hook-templates.sh"

for _fn in soif_write_precommit_hook soif_emit_tdd_commitmsg_block; do
  if ! command -v "$_fn" >/dev/null 2>&1; then
    echo "[FAIL] $ROOT/scripts/lib/hook-templates.sh does not provide $_fn — refusing to install a hook this script cannot generate." >&2
    exit 1
  fi
done

mkdir -p "$ROOT/.git/hooks"

# BL-096-CONTRIB-HOOK-INSTALL: the load-bearing action — the REAL hooks, from
# the same emitters init.sh uses, executable, at the paths git consults.
soif_write_precommit_hook "$ROOT/.git/hooks/pre-commit"                # BL-239-CONTRIB-PRECOMMIT

CM="$ROOT/.git/hooks/commit-msg"                                       # BL-239-CONTRIB-COMMITMSG
if [ ! -f "$CM" ]; then
  printf '%s\n' '#!/usr/bin/env bash' > "$CM"
fi
if grep -qF "$SOIF_TDD_OPEN" "$CM" 2>/dev/null; then
  : # already present — idempotent, same predicate init.sh uses
else
  soif_emit_tdd_commitmsg_block >> "$CM"
fi
chmod +x "$CM"

# VERIFY WHAT WAS INSTALLED, rather than reporting on what was intended. A hook
# that is not executable, or that git will not run, is the defect this entry is
# about; saying "installed" without looking is how it survived.
_fail=0
for h in pre-commit commit-msg; do
  p="$ROOT/.git/hooks/$h"
  if [ ! -x "$p" ]; then echo "[FAIL] $p is not executable" >&2; _fail=1; continue; fi
  if [ ! -s "$p" ]; then echo "[FAIL] $p is empty" >&2; _fail=1; continue; fi
  echo "[OK] .git/hooks/$h installed ($(wc -c < "$p" | tr -d ' ') bytes, executable)"
done
[ "$_fail" -eq 0 ] || exit 1

echo ""
echo "[OK] Contributor hooks installed from scripts/lib/hook-templates.sh —"
echo "     the same emitters init.sh uses for generated projects."
echo "     pre-commit: gitleaks, SAST, test co-location, blocked-commit ledger."
echo "     commit-msg: BL-072 TDD ordering + BL-006 Build-Loop message check."
echo "     Re-run any time to refresh both to the current templates."

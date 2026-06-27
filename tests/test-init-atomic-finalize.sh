#!/usr/bin/env bash
# tests/test-init-atomic-finalize.sh — code-init-sh-6 regression.
#
# init.sh wrote state files (manifest.host/mode/remote_url, bypass-audit.json,
# last-checked-commit.txt, process-state.json attestation) AFTER the initial
# `git commit`. Two consequences:
#
#   1) Half-initialized state on remote-creation failure: if
#      create_and_protect_remote returned 1 (push failure, fake URL, 403,
#      missing CLI), init left the local repo with manifest fields written
#      but not committed, no remote, and check-gate.sh --repair had to
#      reconstruct from a dirty working tree.
#
#   2) BL-030 governance surface widened the blast radius: bl030_finalize_init
#      runs UNCONDITIONALLY after create_project, writing enforcement_level
#      + deployment + poc_mode + bypass-audit init row + last-checked-commit
#      — all uncommitted, all sitting on top of whatever create_and_protect_remote
#      left.
#
# Fix: lay down all durable state BEFORE the initial commit so it's captured
# atomically. The chore-init commit now includes manifest with all fields,
# bypass-audit.json with the init row, and the filesystem gate. Anything
# create_and_protect_remote subsequently writes (remote_url, attestation)
# is captured by a `finalize_init_commit` second commit; if nothing dirty,
# skipped. last-checked-commit.txt is gitignored so its post-commit update
# doesn't dirty the working tree.
#
# Invariant: after init.sh exits (with or without remote success),
# `git status --porcelain` is empty.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# init.sh refuses to scaffold inside the framework repo — work from /tmp.
cd /tmp

run_init_no_remote() {
  local proj="$1"; shift
  bash "$INIT" --non-interactive \
    --project x \
    --project-dir "$proj" \
    --platform web \
    --language javascript \
    --deployment personal \
    --track light \
    --git-host github \
    --visibility private \
    --no-remote-creation "$@" >/dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Clean working tree after init (no remote case) ==="
# ════════════════════════════════════════════════════════════════════

# T1: --no-remote-creation must leave the project with `git status` clean.
# Pre-fix, manifest BL-030 fields, bypass-audit.json, last-checked-commit.txt,
# and process-state.json updates were uncommitted after init exited.
echo "T1: --no-remote-creation → clean working tree"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  dirty=$( cd "$PROJ" && git status --porcelain 2>/dev/null )
  if [ -z "$dirty" ]; then
    pass "T1: working tree clean post-init"
  else
    fail_ "T1" "dirty files post-init:\n$dirty"
  fi
else
  fail_ "T1" "init failed"
fi
rm -rf "$TMP"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== BL-030 + host state captured atomically in initial commit ==="
# ════════════════════════════════════════════════════════════════════

# T2: initial commit contains manifest.json with BL-030 fields populated.
# Pre-fix the initial commit had NO manifest.json (bl030_finalize_init
# created it post-commit).
echo "T2: initial commit includes manifest.enforcement_level/deployment"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  # Use git show to read manifest.json AT the initial commit, not from the
  # working tree.
  manifest_at_init=$( cd "$PROJ" && git show HEAD:.claude/manifest.json 2>/dev/null )
  enf=$( echo "$manifest_at_init" | jq -r '.enforcement_level // empty' )
  dep=$( echo "$manifest_at_init" | jq -r '.deployment // empty' )
  if [ "$enf" = "strict" ] && [ "$dep" = "personal" ]; then
    pass "T2: initial commit manifest has enforcement_level=strict + deployment=personal"
  else
    fail_ "T2" "initial commit manifest missing fields: enf='$enf' dep='$dep'"
  fi
else
  fail_ "T2" "init failed"
fi
rm -rf "$TMP"

# T3: initial commit contains bypass-audit.json with the enforcement_level_set
# init row. Pre-fix bypass-audit was written by bl030_finalize_init AFTER
# the chore-init commit, so the init row was uncommitted.
echo "T3: initial commit includes bypass-audit.json init row"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  audit_at_init=$( cd "$PROJ" && git show HEAD:.claude/bypass-audit.json 2>/dev/null )
  rows=$( echo "$audit_at_init" | jq '[.[] | select(.type=="enforcement_level_set")] | length' 2>/dev/null || echo "0" )
  if [ "$rows" -ge "1" ]; then
    pass "T3: bypass-audit.json has the init enforcement_level_set row in initial commit"
  else
    fail_ "T3" "init row missing from initial commit's bypass-audit.json (rows=$rows)"
  fi
else
  fail_ "T3" "init failed"
fi
rm -rf "$TMP"

# T4: initial commit contains manifest.host = the resolved host (not just
# a placeholder), even without remote creation.
echo "T4: initial commit includes manifest.host=github"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  manifest_at_init=$( cd "$PROJ" && git show HEAD:.claude/manifest.json 2>/dev/null )
  host=$( echo "$manifest_at_init" | jq -r '.host // empty' )
  if [ "$host" = "github" ]; then
    pass "T4: initial commit manifest.host=github (pre-resolved)"
  else
    fail_ "T4" "initial commit manifest.host='$host' (expected github)"
  fi
else
  fail_ "T4" "init failed"
fi
rm -rf "$TMP"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== last-checked-commit.txt is gitignored (not project content) ==="
# ════════════════════════════════════════════════════════════════════

# T5: .gitignore lists .claude/last-checked-commit.txt. The file is
# operational state (the BL-030 detection baseline), not project content.
# Tracking it caused two problems: (a) it dirtied the working tree on every
# detector run, (b) it could never point to its own commit (chicken-and-egg).
echo "T5: .gitignore excludes .claude/last-checked-commit.txt"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  if grep -q '\.claude/last-checked-commit\.txt' "$PROJ/.gitignore" 2>/dev/null; then
    pass "T5: .claude/last-checked-commit.txt is gitignored"
  else
    fail_ "T5" "gitignore missing last-checked-commit.txt"
  fi
else
  fail_ "T5" "init failed"
fi
rm -rf "$TMP"

# T6: last-checked-commit.txt is initialized to a valid commit hash (the
# initial commit). Regression guard — must still work post-fix.
echo "T6: last-checked-commit.txt = HEAD post-init"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  baseline=$( cat "$PROJ/.claude/last-checked-commit.txt" 2>/dev/null )
  head=$( cd "$PROJ" && git rev-parse HEAD 2>/dev/null )
  if [ -n "$baseline" ] && [ "$baseline" = "$head" ]; then
    pass "T6: last-checked-commit.txt = HEAD"
  else
    fail_ "T6" "baseline='$baseline' HEAD='$head'"
  fi
else
  fail_ "T6" "init failed"
fi
rm -rf "$TMP"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Single atomic commit (no half-init second commit) ==="
# ════════════════════════════════════════════════════════════════════

# T7: with --no-remote-creation there is no remote work to record, so init
# should produce exactly ONE commit. A second "finalize" commit only exists
# if create_and_protect_remote actually wrote something (remote_url,
# attestation). Pre-fix this was muddied because state writes weren't
# atomic with the commit.
echo "T7: --no-remote-creation → exactly 1 commit, working tree clean"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  commit_count=$( cd "$PROJ" && git rev-list --count HEAD 2>/dev/null )
  if [ "$commit_count" = "1" ]; then
    pass "T7: exactly 1 commit (no superfluous finalize commit)"
  else
    fail_ "T7" "expected 1 commit, got $commit_count"
  fi
else
  fail_ "T7" "init failed"
fi
rm -rf "$TMP"

# T8: filesystem gate install still happens for strict (regression guard;
# the install now runs before the initial commit so the hook is captured).
echo "T8: strict init installs filesystem-gate (regression guard)"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init_no_remote "$PROJ"; then
  if [ -x "$PROJ/.git/hooks/framework-gate.sh" ] \
     && grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then
    pass "T8: framework-gate.sh + pre-commit marker block present"
  else
    fail_ "T8" "filesystem gate not installed for strict mode"
  fi
else
  fail_ "T8" "init failed"
fi
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

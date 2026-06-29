#!/usr/bin/env bash
# tests/test-upgrade-interruption.sh — tests-upgrade-paths-4 regression.
#
# Audit finding: no test asserted what happens when scripts/upgrade-project.sh
# is interrupted by a fault injected mid-mutation (e.g., an unwritable
# APPROVAL_LOG.md). Sibling test-upgrade-project-atomic.sh covers the
# python3 KeyError + SIGINT vectors against the atomic snapshot/rollback
# block (PR #54/#57/#80), but the recoverable filesystem-permission
# vector — an APPROVAL_LOG.md that another tool has flagged read-only —
# was never exercised end-to-end. This test fault-injects `chmod 0444`
# on APPROVAL_LOG.md, runs --to-production --non-interactive, and
# asserts that the snapshot+rollback invariant holds:
#
#   * exit code is non-zero (the upgrade observably failed)
#   * the six staged operator files were restored to their pre-mutation
#     contents (rollback fired): phase-state.json, tool-preferences.json,
#     intake-progress.json, CLAUDE.md, PROJECT_INTAKE.md, and
#     APPROVAL_LOG.md must match the pre-run snapshot byte-for-byte
#   * git HEAD did NOT advance — no `chore(upgrade): ...` commit was
#     appended
#   * a pre-mutation snapshot dir exists under
#     .claude/upgrade-snapshots/ with >=1 child snapshot, proving the
#     run reached the snapshot phase before failing and the rollback
#     path (not an early-bail) was the path exercised
#
# This codifies current behavior without changing production code so
# any future regression that silently advances state under a partial
# write fault trips this test instead of corrupting an operator's
# project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Mirrors tests/test-upgrade-to-production-preconditions.sh fixture
# shape: organizational/sponsored_poc project with all 6 Pre-Phase-0
# rows dated so the to-production governance gate accepts and the run
# proceeds to the mutation block — where the fault lives.
setup_org_sponsored_dated() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email t@t.local
    git config user.name "Test User"
    git remote add origin https://github.com/example/foo.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"organizational","host":"github","deployment":"organizational","poc_mode":"sponsored_poc","enforcement_level":"strict"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc","current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"standard","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc"}
JSON
    cat > CLAUDE.md <<'MD'
# Test project CLAUDE.md
Pre-upgrade content.
MD
    cat > PROJECT_INTAKE.md <<'MD'
# Test PROJECT_INTAKE
Pre-upgrade content.
MD
  )
  _write_approval_log_org_dated "$TMPDIR_T/APPROVAL_LOG.md"
  ( cd "$TMPDIR_T" && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

# 6 dated rows = governance gate passes; the upgrade reaches the
# mutation block where the chmod 0444 fault on APPROVAL_LOG.md fires.
_write_approval_log_org_dated() {
  local path="$1"
  local d="2026-06-27"
  declare -a labels=(
    "AI deployment path approved"
    "Insurance coverage confirmed"
    "Liability entity designated"
    "Project sponsor assigned"
    "Backup maintainer designated"
    "ITSM project registered"
  )
  {
    cat <<'HDR'
---
project: test
deployment: organizational
created: 2026-06-27
framework: Solo Orchestrator v1.0
---

# Approval Log — test

## Pre-Phase 0: Organizational Pre-Conditions

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
HDR
    local i
    for i in 1 2 3 4 5 6; do
      local idx=$((i - 1))
      local label="${labels[$idx]}"
      printf '| %d | %s | Jane Approver | IT Security | %s | Email | TICKET-%d | |\n' \
        "$i" "$label" "$d" "$i"
    done
    echo
    echo "## Approval History"
    echo
    echo "| Date | Gate / Event | Decision | Notes |"
    echo "|---|---|---|---|"
    echo "| | | | |"
  } > "$path"
}

teardown_project() {
  # chmod back to writable so rm -rf doesn't choke on the read-only file.
  [ -n "${TMPDIR_T:-}" ] && [ -d "$TMPDIR_T" ] && chmod -R u+w "$TMPDIR_T" 2>/dev/null
  rm -rf "$TMPDIR_T"
}

# ── Tests ──────────────────────────────────────────────────────────

# T1: unwritable APPROVAL_LOG.md → upgrade fails AND the six staged
# files match their pre-run contents (snapshot+rollback fired) AND the
# pre-mutation snapshot dir was created with at least one child. The
# snapshot-dir assertion (4) nails this test to the rollback path so
# a future refactor that moves the APPROVAL_LOG.md write before the
# snapshot phase cannot silently degrade T1 from "rollback works" to
# "early-bail works".
t1_unwritable_approval_log_preserves_state() {
  setup_org_sponsored_dated

  # Snapshot pre-run contents of the six staged files into a sibling
  # dir under the test tmpdir so the post-run comparison is hermetic.
  local snap="$TMPDIR_T/__pre_run_snapshot"
  mkdir -p "$snap/.claude"
  cp "$TMPDIR_T/.claude/phase-state.json"      "$snap/.claude/phase-state.json"
  cp "$TMPDIR_T/.claude/tool-preferences.json" "$snap/.claude/tool-preferences.json"
  cp "$TMPDIR_T/.claude/intake-progress.json"  "$snap/.claude/intake-progress.json"
  cp "$TMPDIR_T/CLAUDE.md"                     "$snap/CLAUDE.md"
  cp "$TMPDIR_T/PROJECT_INTAKE.md"             "$snap/PROJECT_INTAKE.md"
  cp "$TMPDIR_T/APPROVAL_LOG.md"               "$snap/APPROVAL_LOG.md"

  local pre_head; pre_head=$(cd "$TMPDIR_T" && git rev-parse HEAD)

  # Inject the fault: APPROVAL_LOG.md becomes read-only mid-flight.
  chmod 0444 "$TMPDIR_T/APPROVAL_LOG.md"

  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null 2>&1) || rc=$?

  # Make APPROVAL_LOG.md writable again before assertions so cmp/diff
  # output is unambiguous if a test fails and we inspect by hand.
  chmod 0644 "$TMPDIR_T/APPROVAL_LOG.md" 2>/dev/null || true

  # (1) Upgrade must observably fail — silent success on partial write
  # is the regression class this finding closes.
  if [ "$rc" = "0" ]; then
    fail_ "T1" "expected non-zero exit when APPROVAL_LOG.md is read-only; rc=$rc tail:\n$(echo "$out" | tail -20)"
    teardown_project; return
  fi

  # (2) Each of the six staged files must match the pre-run snapshot.
  # Rollback must have restored any mutated files; a half-written file
  # that desynchronizes the operator's project is the regression we
  # guard against. Assertion (4) below pins this to the rollback path.
  local mismatched=""
  for rel in .claude/phase-state.json .claude/tool-preferences.json .claude/intake-progress.json CLAUDE.md PROJECT_INTAKE.md APPROVAL_LOG.md; do
    if ! cmp -s "$snap/$rel" "$TMPDIR_T/$rel"; then
      mismatched="${mismatched}${rel} "
    fi
  done
  if [ -n "$mismatched" ]; then
    fail_ "T1" "files diverged from pre-run snapshot (rollback didn't restore): $mismatched"
    teardown_project; return
  fi

  # (3) git HEAD must not have advanced — no chore(upgrade) commit.
  local post_head; post_head=$(cd "$TMPDIR_T" && git rev-parse HEAD)
  if [ "$pre_head" != "$post_head" ]; then
    fail_ "T1" "git HEAD advanced despite failed upgrade ($pre_head -> $post_head)"
    teardown_project; return
  fi

  # (4) Snapshot dir was created AND has exactly one child snapshot.
  # This nails T1 to the rollback path — without it, a future refactor
  # that moves the APPROVAL_LOG.md write before the snapshot phase would
  # silently degrade T1 from "rollback works" to "early-bail works" and
  # we'd lose coverage of the rollback path with no red signal.
  if [ ! -d "$TMPDIR_T/.claude/upgrade-snapshots" ]; then
    fail_ "T1" "snapshot dir not created — run failed before snapshot phase, so rollback path was not exercised"
    teardown_project; return
  fi
  local snap_children
  snap_children=$(find "$TMPDIR_T/.claude/upgrade-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -c . || true)
  case "$snap_children" in ''|*[!0-9]*) snap_children=0 ;; esac
  if [ "$snap_children" -lt 1 ]; then
    fail_ "T1" "snapshot dir exists but has no children — rollback path was not exercised"
    teardown_project; return
  fi

  pass "T1: read-only APPROVAL_LOG.md → exit!=0, all six staged files unchanged, git HEAD intact, rollback path exercised"
  teardown_project
}

# T2: snapshot dir is created for forensic inspection. This guards the
# "always snapshot before mutation" invariant from PR #54/#57/#80 —
# even when the run fails, the snapshot dir is retained so an operator
# can audit what state existed at the moment of failure.
t2_snapshot_dir_retained_on_failure() {
  setup_org_sponsored_dated
  chmod 0444 "$TMPDIR_T/APPROVAL_LOG.md"

  local rc=0
  (cd "$TMPDIR_T" && "$SCRIPT" --to-production --non-interactive </dev/null >/dev/null 2>&1) || rc=$?
  chmod 0644 "$TMPDIR_T/APPROVAL_LOG.md" 2>/dev/null || true

  if [ "$rc" = "0" ]; then
    fail_ "T2" "expected non-zero exit for the fault-injection case"
    teardown_project; return
  fi

  # The snapshot dir may or may not exist depending on whether the run
  # reached the snapshot phase before failing. If the rollback path
  # fired (snapshot existed), the dir must be retained per
  # _upgrade_rollback's "Snapshot retained for forensics" contract.
  # If the failure tripped before the snapshot dir was created, the
  # dir tree is allowed to be absent — but if the root exists with
  # any subdirectory, at least one snapshot must be retained (no
  # silent pruning under failure).
  if [ -d "$TMPDIR_T/.claude/upgrade-snapshots" ]; then
    local count
    # `grep -c .` exits 1 on zero matches — `|| true` keeps `set -e` from
    # killing the test before the assertion runs.
    count=$(find "$TMPDIR_T/.claude/upgrade-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -c . || true)
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    # If the dir was created, we expect at least one snapshot child
    # (pre-mutation snapshot is what the rollback restores from).
    # The keep-3 retention prune only runs after success per
    # _upgrade_prune_snapshots's header note, so a failure run that
    # produced the dir but pruned all children is a regression — the
    # operator loses forensic state at exactly the moment they need it.
    if [ "$count" -lt 1 ]; then
      fail_ "T2" "upgrade-snapshots dir exists but is empty (forensic history pruned under failure)"
      teardown_project; return
    fi
  fi

  pass "T2: snapshot infrastructure preserves forensic state under failure"
  teardown_project
}

echo "== tests/test-upgrade-interruption.sh =="
t1_unwritable_approval_log_preserves_state
t2_snapshot_dir_retained_on_failure

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

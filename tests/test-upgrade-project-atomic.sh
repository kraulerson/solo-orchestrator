#!/usr/bin/env bash
# tests/test-upgrade-project-atomic.sh — code-upgrade-project-5 regression.
#
# scripts/upgrade-project.sh runs 6+ sequential python3 heredocs that
# rewrite 7 files (tool-preferences.json, phase-state.json,
# intake-progress.json, CLAUDE.md, PROJECT_INTAKE.md, APPROVAL_LOG.md,
# PRODUCT_MANIFESTO.md) and then makes ONE final git commit. Pre-fix the
# mutation block had ZERO transactional safety:
#
#   * SIGINT mid-run leaves phase-state.json advanced but CLAUDE.md
#     pristine — re-running picks up DEPLOYMENT_CHANGES=false because
#     phase-state already shows the new deployment, so the CLAUDE.md
#     governance section addition and APPROVAL_LOG.md restructure are
#     both silently skipped. Operator stuck with stale CLAUDE.md and
#     must hand-edit phase-state.json to recover.
#   * python3 KeyError on the 3rd heredoc leaves the project in a
#     half-mutated state.
#   * git commit failure leaves the working tree dirty with 6 mutated
#     files and no audit trail.
#
# Audit baseline §5.22 mandates "non-destructive of technical work."
#
# Fix (mirrors PR #57's sibling pattern in reconfigure-project.sh:82-183
# — 8 weeks in production, no regressions):
#   1. Pre-mutation: snapshot all 7 files into
#      .claude/upgrade-snapshots/<UTC-timestamp>/ (only files that exist).
#   2. Install `trap _upgrade_rollback INT TERM ERR` before heredoc #1.
#   3. After successful git commit: clear trap with `trap - INT TERM ERR`.
#   4. Keep-3 retention: prune snapshot dirs to the 3 most recent on
#      success — keeps forensic history without unbounded growth.
#   5. Convert `python3 ... || true` heredocs to explicit non-zero checks
#      that call `_upgrade_rollback` and exit.
#
# Test scenarios:
#   T7a — SIGINT mid-run (python3 stub sleeps inside 3rd heredoc).
#   T7b — Python KeyError on 3rd heredoc.
#   T7c — Keep-3 retention after 4 successful runs.
#   T7d — git commit failure → rollback fires, snapshot retained.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Same phase-state schema as tests/test-upgrade-paths.sh:make_phase_state.
make_phase_state() {
  local dir="$1" track="$2" deployment="$3" poc_json="$4"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/phase-state.json" <<JSON
{
  "project": "test",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$track",
  "deployment": "$deployment",
  "poc_mode": $poc_json,
  "compliance_ready": false,
  "gates": {"phase_0_to_1": null, "phase_1_to_2": null, "phase_3_to_4": null}
}
JSON
  ( cd "$dir" && git init -q && git config user.email t@t.l && git config user.name t \
      && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

# Pre-Phase-0 approval log fixture (mirrors test-upgrade-paths.sh).
seed_approval_log_org_filled() {
  local dir="$1"
  cat > "$dir/APPROVAL_LOG.md" <<'EOF'
---
project: test
deployment: organizational
created: 2026-06-27
---

## Pre-Phase 0: Organizational Pre-Conditions

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
| 1 | AI deployment path approved | Sec Lead | IT Security | 2026-06-27 | Email | TKT-1 | |
| 2 | Insurance coverage confirmed | Broker | Insurance | 2026-06-27 | Email | TKT-2 | |
| 3 | Liability entity designated | Legal | Legal | 2026-06-27 | Email | TKT-3 | |
| 4 | Project sponsor assigned | Sponsor | Exec | 2026-06-27 | Email | TKT-4 | |
| 5 | Backup maintainer designated | Backup | Tech Lead | 2026-06-27 | Email | TKT-5 | |
| 6 | ITSM project registered | PMO | ITSM | 2026-06-27 | Email | TKT-6 | |

## Approval History

| Date | Gate / Event | Decision | Notes |
|---|---|---|---|
| | | | |
EOF
}

# Build a stub `python3` that:
#   * Forwards the first N invocations to the real python3.
#   * On the (N+1)th invocation:
#       - mode=fail  → exit 1 immediately (simulate KeyError / parse error)
#       - mode=block → block on `read` from a named pipe — the test
#                       releases the block (or the parent's SIGTERM/INT
#                       kills the stub, which propagates non-zero so
#                       bash's `set -e` ERR trap fires the rollback).
# State is kept in $stub_dir/counter so each call increments persistently.
make_python3_stub() {
  local stub_dir="$1" pass_count="$2" mode="$3"
  mkdir -p "$stub_dir"
  echo "0" > "$stub_dir/counter"
  local real_python3
  real_python3=$(command -v python3)
  cat > "$stub_dir/python3" <<STUB
#!/usr/bin/env bash
set -e
# Counter-based python3 stub.
counter_file="$stub_dir/counter"
n=\$(cat "\$counter_file" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" > "\$counter_file"
if [ "\$n" -le "$pass_count" ]; then
  exec "$real_python3" "\$@"
fi
# Triggered behavior on the (pass_count+1)th call.
case "$mode" in
  fail)
    echo "stub-python3: simulated failure on call \$n" >&2
    exit 1
    ;;
  block)
    # Mark that we entered the block, then exec sleep so a SIGTERM
    # from the parent test harness kills this process, which causes
    # the python3 heredoc to return non-zero, which fires bash's set
    # -e ERR trap → rollback. exec replaces this shell with sleep so
    # the signal hits cleanly (no intermediate bash to intercept).
    touch "$stub_dir/blocked-marker"
    echo "stub-python3: blocking on call \$n (waiting for SIGTERM)" >&2
    exec sleep 30
    ;;
esac
STUB
  chmod +x "$stub_dir/python3"
}

# Build a stub `git` that wraps the real git, but fails the `commit`
# subcommand. All other subcommands pass through unchanged.
make_git_commit_fail_stub() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  local real_git
  real_git=$(command -v git)
  cat > "$stub_dir/git" <<STUB
#!/usr/bin/env bash
# Pass-through stub that fails 'git commit' specifically.
if [ "\${1:-}" = "commit" ]; then
  echo "stub-git: simulated commit failure" >&2
  exit 1
fi
exec "$real_git" "\$@"
STUB
  chmod +x "$stub_dir/git"
}

snapshot_file_sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7a: SIGINT mid-mutation → all 7 files reverted (or all advanced) ==="
# ════════════════════════════════════════════════════════════════════
#
# Setup an organizational POC project so --to-production touches the
# maximum number of files (CLAUDE.md governance section + APPROVAL_LOG
# restructure both reachable). Stub python3 to sleep 5s on the 3rd
# heredoc (which is the CLAUDE.md rewrite for this code path). SIGINT
# fires while the stub sleeps — bash receives the signal, runs the
# trap, restores all snapshot files.

T=$(mktemp -d); P="$T/p"; STUB="$T/stub"
make_phase_state "$P" "standard" "organizational" '"sponsored_poc"'
seed_approval_log_org_filled "$P"
cat > "$P/CLAUDE.md" <<'EOF'
# Project Identity

**Track:** Standard
**Deployment:** Organizational

## Notes

POC mode active during pilot.
EOF
( cd "$P" && git add -A && git commit -q -m "seed claude.md" ) >/dev/null 2>&1
# pass_count=2: heredocs #1 (phase-state) and #2 (CLAUDE.md) run real
# python3 — they advance both files. Heredoc #3 (APPROVAL_LOG audit
# entry) is the stub that blocks. The test then SIGTERMs the bash pid,
# which propagates to the stub (sleep) → python3 heredoc returns
# non-zero → bash's set -e ERR trap → _upgrade_rollback restores
# phase-state.json AND CLAUDE.md from the snapshot.
make_python3_stub "$STUB" 2 block

sha_phase_pre=$(snapshot_file_sha "$P/.claude/phase-state.json")
sha_claude_pre=$(snapshot_file_sha "$P/CLAUDE.md")
sha_approval_pre=$(snapshot_file_sha "$P/APPROVAL_LOG.md")

# Spawn the upgrade in background, capture its pid, wait until the
# stub announces it's blocked, then send SIGTERM to bash. Use TERM
# (not INT) because macOS's `bash &` puts the child in the parent's
# process group; SIGINT semantics on a non-controlling-tty pgrp are
# flaky, but TERM is delivered cleanly per kill(2). Both signals are
# handled by the same _upgrade_rollback trap, so the assertion is
# equivalent.
(
  cd "$P"
  PATH="$STUB:$PATH" bash "$UPGRADE" --to-production --non-interactive \
    --ack-preconditions=1,2,3,4,5,6 > "$T/log" 2>&1 &
  bash_pid=$!
  # Wait up to 10s for the stub to announce it's blocked.
  for _ in $(seq 1 100); do
    [ -f "$STUB/blocked-marker" ] && break
    sleep 0.1
  done
  # Send SIGTERM to bash (and the stub's `sleep` child, via pgrp on
  # most systems). The child sleep dies, the python3 heredoc returns
  # non-zero, set -e triggers, ERR trap fires _upgrade_rollback.
  kill -TERM "$bash_pid" 2>/dev/null
  # Also SIGTERM the blocked sleep directly in case pgrp delivery
  # misses on this OS — ensures the heredoc returns promptly.
  pkill -TERM -P "$bash_pid" 2>/dev/null
  wait "$bash_pid" 2>/dev/null
  echo "$?" > "$T/rc"
) || true
rc=$(cat "$T/rc" 2>/dev/null || echo "?")

sha_phase_post=$(snapshot_file_sha "$P/.claude/phase-state.json")
sha_claude_post=$(snapshot_file_sha "$P/CLAUDE.md")
sha_approval_post=$(snapshot_file_sha "$P/APPROVAL_LOG.md")

phase_changed=$(   [ "$sha_phase_pre"    != "$sha_phase_post"    ] && echo y || echo n )
claude_changed=$(  [ "$sha_claude_pre"   != "$sha_claude_post"   ] && echo y || echo n )
approval_changed=$([ "$sha_approval_pre" != "$sha_approval_post" ] && echo y || echo n )

snapshot_count=$( find "$P/.claude/upgrade-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' )
stub_blocked=$( [ -f "$STUB/blocked-marker" ] && echo y || echo n )

# Pre-fix: phase-state + CLAUDE.md mutated, APPROVAL_LOG untouched
# (the stub blocked before its mutation). Half-mutated state.
# Post-fix: rollback fires, ALL three files match pre-state.
if [ "$stub_blocked" = "y" ] && [ "$phase_changed" = "n" ] \
   && [ "$claude_changed" = "n" ] && [ "$approval_changed" = "n" ] \
   && [ "$snapshot_count" -ge 1 ]; then
  pass "T7a: SIGTERM mid-mutation → all files rolled back; forensic snapshot retained"
else
  fail_ "T7a" "rc=$rc stub_blocked=$stub_blocked phase_changed=$phase_changed claude_changed=$claude_changed approval_changed=$approval_changed snapshot_count=$snapshot_count. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7b: python3 failure mid-mutation → rollback fires, all 7 files restored ==="
# ════════════════════════════════════════════════════════════════════
#
# Deterministic version of T7a using a python3 stub that exits 1 on the
# 3rd heredoc. Asserts every snapshotted file matches its pre-state
# byte-for-byte after upgrade-project.sh exits non-zero.

T=$(mktemp -d); P="$T/p"; STUB="$T/stub"
make_phase_state "$P" "standard" "organizational" '"sponsored_poc"'
seed_approval_log_org_filled "$P"
cat > "$P/CLAUDE.md" <<'EOF'
# Project Identity

**Track:** Standard
**Deployment:** Organizational

POC mode active during pilot.

## Operating Notes

Body content.
EOF
cat > "$P/PROJECT_INTAKE.md" <<'EOF'
# Project Intake

## Purpose
Test intake.
EOF
( cd "$P" && git add -A && git commit -q -m "seed project files" ) >/dev/null 2>&1
make_python3_stub "$STUB" 2 fail

# Pre-mutation hashes for every potentially mutated file. Parallel
# arrays (bash 3.2 compatible — macOS ships /bin/bash 3.2, so we avoid
# `declare -A`).
PRE_FILES=(".claude/phase-state.json" "CLAUDE.md" "APPROVAL_LOG.md" "PROJECT_INTAKE.md")
PRE_SHA=()
for f in "${PRE_FILES[@]}"; do
  if [ -f "$P/$f" ]; then
    PRE_SHA+=("$(snapshot_file_sha "$P/$f")")
  else
    PRE_SHA+=("")
  fi
done

( cd "$P" && PATH="$STUB:$PATH" bash "$UPGRADE" --to-production --non-interactive \
    --ack-preconditions=1,2,3,4,5,6 ) > "$T/log" 2>&1
rc=$?

# Every tracked file should match its pre-mutation hash.
mismatched=""
for i in 0 1 2 3; do
  f="${PRE_FILES[$i]}"
  if [ -f "$P/$f" ] && [ -n "${PRE_SHA[$i]}" ]; then
    post=$(snapshot_file_sha "$P/$f")
    if [ "$post" != "${PRE_SHA[$i]}" ]; then
      mismatched="$mismatched $f"
    fi
  fi
done

snapshot_count=$( find "$P/.claude/upgrade-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' )

if [ "$rc" != "0" ] && [ -z "$mismatched" ] && [ "$snapshot_count" -ge 1 ]; then
  pass "T7b: python3 fail on heredoc #3 → rollback restored all files; snapshot retained for forensics"
else
  fail_ "T7b" "rc=$rc mismatched='$mismatched' snapshot_count=$snapshot_count. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7c: 4 successful runs → keep-3 retention ==="
# ════════════════════════════════════════════════════════════════════
#
# Each successful upgrade run lays down a new snapshot dir under
# .claude/upgrade-snapshots/. Without retention this grows unbounded.
# Keep-3 prunes oldest dirs so exactly 3 remain after the 4th run.
#
# Use --track upgrades because they're idempotent-friendly: light →
# standard → full, then two more --track full no-op upgrades to
# generate snapshot dirs without changing state in disruptive ways.

# Strategy: stage 4 distinct upgrades that each enter the mutation
# block. We can chain --track upgrades that transition between
# adjacent tiers AND POC transitions:
#   Run 1: light personal → --track standard           → snapshot
#   Run 2: standard personal → --track full            → snapshot
#   Run 3: full personal → --to-private-poc            → snapshot
#   Run 4: full private_poc → --to-sponsored-poc       → snapshot
# All 4 are real state transitions so each creates a snapshot dir.
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "light" "personal" 'null'

run_upgrade() {
  ( cd "$P" && bash "$UPGRADE" "$@" --non-interactive ) > "$T/log" 2>&1
  local rc=$?
  # Force a different mtime per snapshot so keep-3 ordering is unambiguous.
  sleep 1
  return $rc
}

run_upgrade --track standard       || true
run_upgrade --track full           || true
run_upgrade --to-private-poc       || true
run_upgrade --to-sponsored-poc     || true

snapshot_dirs=$( find "$P/.claude/upgrade-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' )

if [ "$snapshot_dirs" = "3" ]; then
  pass "T7c: 4 successful runs → exactly 3 snapshot dirs retained (keep-3)"
else
  fail_ "T7c" "expected 3 snapshot dirs after 4 runs, got $snapshot_dirs. Last log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7d: git commit failure → rollback fires, snapshot retained ==="
# ════════════════════════════════════════════════════════════════════
#
# All mutations succeed but the final `git commit` fails (stubbed). The
# rollback must fire (the operator's working tree should match the
# pre-upgrade state) and the snapshot dir must remain for forensics.

T=$(mktemp -d); P="$T/p"; STUB="$T/stub"
make_phase_state "$P" "light" "personal" 'null'
sha_phase_pre=$(snapshot_file_sha "$P/.claude/phase-state.json")
make_git_commit_fail_stub "$STUB"

( cd "$P" && PATH="$STUB:$PATH" bash "$UPGRADE" --track standard --non-interactive ) > "$T/log" 2>&1
rc=$?

sha_phase_post=$(snapshot_file_sha "$P/.claude/phase-state.json")
snapshot_count=$( find "$P/.claude/upgrade-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' )

if [ "$rc" != "0" ] && [ "$sha_phase_pre" = "$sha_phase_post" ] && [ "$snapshot_count" -ge 1 ]; then
  pass "T7d: git commit failure → rollback restored phase-state.json; snapshot retained for forensics"
else
  fail_ "T7d" "rc=$rc phase_state_unchanged=$([ "$sha_phase_pre" = "$sha_phase_post" ] && echo y || echo n) snapshot_count=$snapshot_count. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

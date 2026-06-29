#!/usr/bin/env bash
# tests/test-upgrade-sentinel-block.sh — tests-upgrade-paths-5 regression.
#
# Audit finding: no test asserted the BL-015 pending-approval sentinel
# guard (scripts/upgrade-project.sh:473-498) actually blocks an
# upgrade and leaves project state unmutated. The guard was added
# after 5/5 upgrade UAT agents (49, 62, 79, 82, 84) observed
# upgrade-project.sh writing files and committing while a sentinel
# existed. A regression that loosens the guard (e.g., wrong path,
# weaker check, missing exit) would currently slip through CI.
#
# This test stages a minimal upgradeable project fixture, pre-writes
# a well-formed `.claude/pending-approval.json`, invokes
# `scripts/upgrade-project.sh --to-private-poc --non-interactive`
# (the same shape a UAT agent would use), and asserts:
#
#   (1) exit code is non-zero
#   (2) stderr contains "upgrade blocked — pending user decision" and
#       the `--resolve` / `--clear` recovery hint
#   (3) no operator files were mutated (manifest, phase-state,
#       tool-preferences, intake-progress unchanged; no
#       `chore(upgrade)` commit appended; git HEAD intact)
#   (4) the sentinel file itself is still present (the guard never
#       deletes the sentinel — only --resolve/--clear may do that)
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Minimal personal/private_poc fixture — any track flag would trip
# the sentinel guard the same way; we pick --to-private-poc because
# the BL-015 audit history specifically cited UAT agents driving
# irreversible POC-mode transitions.
setup_personal_with_sentinel() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email t@t.local
    git config user.name "Test User"
    git remote add origin https://example.com/fake.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"github","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}
JSON
    cat > .claude/tool-preferences.json <<'JSON'
{"context":{"track":"light","platform":"web","os":"darwin"},"preferences":{}}
JSON
    cat > .claude/intake-progress.json <<'JSON'
{"track":"light","deployment":"personal"}
JSON
    # Well-formed pending-approval.json per CDF 4.2.3 contract —
    # matches the shape scripts/pending-approval.sh emits.
    cat > .claude/pending-approval.json <<'JSON'
{
  "question": "Adopt sponsored POC governance?",
  "offered_at": "2026-06-28T12:00:00Z",
  "options": ["yes", "no", "defer"],
  "owner": "uat-agent"
}
JSON
    git add -A && git commit -q -m "init"
  ) >/dev/null 2>&1
}

teardown_project() { rm -rf "$TMPDIR_T"; }

# T1: well-formed sentinel blocks --to-private-poc, no mutation, sentinel preserved.
t1_sentinel_blocks_to_private_poc() {
  setup_personal_with_sentinel

  # Capture baseline state for post-run diff.
  local pre_head; pre_head=$(cd "$TMPDIR_T" && git rev-parse HEAD)
  local pre_manifest;   pre_manifest=$(cat "$TMPDIR_T/.claude/manifest.json")
  local pre_phase;      pre_phase=$(cat "$TMPDIR_T/.claude/phase-state.json")
  local pre_tools;      pre_tools=$(cat "$TMPDIR_T/.claude/tool-preferences.json")
  local pre_intake;     pre_intake=$(cat "$TMPDIR_T/.claude/intake-progress.json")
  local pre_sentinel;   pre_sentinel=$(cat "$TMPDIR_T/.claude/pending-approval.json")

  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-private-poc --non-interactive </dev/null 2>&1) || rc=$?

  # (1) Exit must be non-zero.
  if [ "$rc" = "0" ]; then
    fail_ "T1" "expected non-zero exit when sentinel present; rc=$rc tail:\n$(echo "$out" | tail -10)"
    teardown_project; return
  fi

  # (2) Recovery hint + canonical guard message must both appear.
  if ! echo "$out" | grep -qF "upgrade blocked — pending user decision"; then
    fail_ "T1" "stderr missing canonical 'upgrade blocked — pending user decision' message; out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  if ! echo "$out" | grep -qF "pending-approval.sh --resolve"; then
    fail_ "T1" "stderr missing '--resolve' recovery hint; out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  if ! echo "$out" | grep -qF "pending-approval.sh --clear"; then
    fail_ "T1" "stderr missing '--clear' recovery hint; out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi

  # (3) No operator file mutations.
  if [ "$pre_manifest" != "$(cat "$TMPDIR_T/.claude/manifest.json")" ]; then
    fail_ "T1" "manifest.json mutated despite sentinel block"
    teardown_project; return
  fi
  if [ "$pre_phase" != "$(cat "$TMPDIR_T/.claude/phase-state.json")" ]; then
    fail_ "T1" "phase-state.json mutated despite sentinel block"
    teardown_project; return
  fi
  if [ "$pre_tools" != "$(cat "$TMPDIR_T/.claude/tool-preferences.json")" ]; then
    fail_ "T1" "tool-preferences.json mutated despite sentinel block"
    teardown_project; return
  fi
  if [ "$pre_intake" != "$(cat "$TMPDIR_T/.claude/intake-progress.json")" ]; then
    fail_ "T1" "intake-progress.json mutated despite sentinel block"
    teardown_project; return
  fi
  local post_head; post_head=$(cd "$TMPDIR_T" && git rev-parse HEAD)
  if [ "$pre_head" != "$post_head" ]; then
    fail_ "T1" "git HEAD advanced despite sentinel block ($pre_head -> $post_head)"
    teardown_project; return
  fi

  # (4) Sentinel itself must still be present and unchanged.
  if [ ! -f "$TMPDIR_T/.claude/pending-approval.json" ]; then
    fail_ "T1" "sentinel file was removed by the upgrade — only --resolve/--clear may do that"
    teardown_project; return
  fi
  if [ "$pre_sentinel" != "$(cat "$TMPDIR_T/.claude/pending-approval.json")" ]; then
    fail_ "T1" "sentinel file contents changed despite sentinel block"
    teardown_project; return
  fi

  pass "T1: sentinel blocks --to-private-poc; rc!=0, recovery hints present, no mutation, sentinel preserved"
  teardown_project
}

# T2: malformed sentinel (invalid JSON) still blocks — guard treats
# an unparseable sentinel as in-flight per CDF 4.2.3 contract. This
# is the line scripts/upgrade-project.sh:489-492 codifies; we want a
# direct regression assertion so future "skip if invalid JSON"
# refactors don't silently undermine the guard.
t2_malformed_sentinel_still_blocks() {
  setup_personal_with_sentinel
  # Overwrite with malformed JSON.
  echo "{ not valid json" > "$TMPDIR_T/.claude/pending-approval.json"

  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-private-poc --non-interactive </dev/null 2>&1) || rc=$?

  if [ "$rc" = "0" ]; then
    fail_ "T2" "expected non-zero exit when sentinel is malformed; rc=$rc"
    teardown_project; return
  fi
  if ! echo "$out" | grep -qF "upgrade blocked — pending user decision"; then
    fail_ "T2" "stderr missing canonical guard message for malformed sentinel; out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  if ! echo "$out" | grep -qiE "malformed|in-flight"; then
    fail_ "T2" "expected the guard to acknowledge malformed/in-flight handling; out:\n$(echo "$out" | tail -15)"
    teardown_project; return
  fi
  pass "T2: malformed sentinel is still treated as in-flight and blocks the upgrade"
  teardown_project
}

# T3: with NO sentinel, the same fixture proceeds (sanity — proves
# T1's block was caused by the sentinel, not the fixture shape).
# We don't assert success of the upgrade itself; only that the
# canonical guard message does NOT appear when the sentinel is
# absent.
t3_no_sentinel_no_guard_message() {
  setup_personal_with_sentinel
  rm -f "$TMPDIR_T/.claude/pending-approval.json"

  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --to-private-poc --non-interactive </dev/null 2>&1) || rc=$?
  if echo "$out" | grep -qF "upgrade blocked — pending user decision"; then
    fail_ "T3" "guard message fired without a sentinel present (false positive); rc=$rc tail:\n$(echo "$out" | tail -10)"
    teardown_project; return
  fi
  pass "T3: no sentinel → no guard message (rc=$rc, guard correctly silent)"
  teardown_project
}

echo "== tests/test-upgrade-sentinel-block.sh =="
t1_sentinel_blocks_to_private_poc
t2_malformed_sentinel_still_blocks
t3_no_sentinel_no_guard_message

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

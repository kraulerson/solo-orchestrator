#!/usr/bin/env bash
# tests/test-upgrade-sentinel-block.sh — tests-upgrade-paths-5 regression.
#
# Audit finding: no test asserted the BL-015 pending-approval sentinel
# guard (scripts/upgrade-project.sh's _bl015_sentinel_guard) actually
# blocks an upgrade and leaves project state unmutated. The guard was
# added after 5/5 upgrade UAT agents (49, 62, 79, 82, 84) observed
# upgrade-project.sh writing files and committing while a sentinel
# existed. A regression that loosens the guard (e.g., wrong path,
# weaker check, missing exit) would currently slip through CI.
#
# Full-upgrade coverage (T1–T3): stage a minimal upgradeable project
# fixture, pre-write a well-formed `.claude/pending-approval.json`,
# invoke `scripts/upgrade-project.sh --to-private-poc --non-interactive`
# (the same shape a UAT agent would use), and assert:
#
#   (1) exit code is non-zero
#   (2) stderr contains "upgrade blocked — pending user decision" and
#       the `--resolve` / `--clear` recovery hint
#   (3) no operator files were mutated (manifest, phase-state,
#       tool-preferences, intake-progress unchanged; no
#       `chore(upgrade)` commit appended; git HEAD intact)
#   (4) the sentinel file itself is still present (the guard never
#       deletes the sentinel — only --resolve/--clear may do that)
#
# --backfill-only coverage (T4–T6, BL-001 × BL-015 parity): the
# --backfill-only path short-circuits BEFORE the full-upgrade path's
# sentinel guard, yet it mutates .claude/framework/ (CDF assets), the
# manifest, host config and .claude/skills/. It must honor the SAME
# sentinel. These scenarios assert:
#
#   T4 (T-backfill-blocks-on-sentinel): sentinel present →
#       `--backfill-only` exits non-zero with the BL-015 deny message
#       and leaves .claude/framework/ + manifest byte-identical (md5).
#   T5 (T-backfill-proceeds-no-sentinel): no sentinel → the backfill
#       runs (BL-030 fields get backfilled) — existing behavior intact.
#   T6 (mutation proof): neutralize the backfill call to
#       _bl015_sentinel_guard in a copy of the script → the SAME
#       sentinel run now MUTATES the manifest (backfill fires despite
#       the sentinel), while the real script leaves it byte-identical.
#       Proves the backfill guard is load-bearing.
#
# HERMETICITY: every --backfill-only run pins CDF_HOME to a nonexistent
# path so the BL-001 CDF asset refresh gracefully skips — no CDF clone,
# no network, no real remotes. The discriminating mutation signal is the
# fully-hermetic BL-030 manifest backfill (manifest lacks
# enforcement_level → the backfill would add it).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Portable md5 of a single file (macOS `md5 -q`, Linux `md5sum`).
_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}

# Deterministic fingerprint of every file under a directory (relative
# path + content md5, LC_ALL=C-sorted). Detects content changes,
# additions AND deletions. "(absent)" when the dir does not exist.
_tree_fingerprint() {
  local d="$1"
  [ -d "$d" ] || { echo "(absent)"; return; }
  ( cd "$d" && find . -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s:%s\n' "$f" "$(_md5file "$f")"
    done )
}

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

# ─────────────────────────────────────────────────────────────────────
# --backfill-only × BL-015 parity (T4–T6)
# ─────────────────────────────────────────────────────────────────────

# Scaffold a backfillable project at $1: a manifest that HAS a host but
# LACKS enforcement_level (so the fully-hermetic BL-030 backfill would
# rewrite it), plus a stale .claude/framework/ tree the CDF refresh
# would replace on the full happy path. Git-inited so the BL-030
# backfill's `git rev-parse HEAD` succeeds.
setup_backfill_project() {
  local proj="$1"
  mkdir -p "$proj/.claude/framework/hooks" "$proj/.claude/framework/rules" "$proj/.claude/framework/gates"
  printf '#!/usr/bin/env bash\necho STALE-HOOK\n' > "$proj/.claude/framework/hooks/demo-hook.sh"
  printf '# stale rule\n'                          > "$proj/.claude/framework/rules/demo-rule.md"
  printf '#!/usr/bin/env bash\necho STALE-GATE\n'  > "$proj/.claude/framework/gates/demo-gate.sh"
  # host present, enforcement_level ABSENT → BL-030 backfill is the mutation signal.
  cat > "$proj/.claude/manifest.json" <<'JSON'
{"frameworkVersion":"1.0.0","host":"github","mode":"personal"}
JSON
  cat > "$proj/.claude/phase-state.json" <<'JSON'
{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}
JSON
  ( cd "$proj" && git init -q && git config user.email t@t.local && git config user.name "Test User" \
      && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

write_sentinel() {
  cat > "$1/.claude/pending-approval.json" <<'JSON'
{
  "question": "Adopt sponsored POC governance?",
  "offered_at": "2026-06-28T12:00:00Z",
  "options": ["yes", "no", "defer"],
  "owner": "uat-agent"
}
JSON
}

# T4 — T-backfill-blocks-on-sentinel: sentinel present → --backfill-only
# blocks (non-zero + deny message) and mutates NOTHING
# (.claude/framework/ + manifest byte-identical md5; no .claude/skills
# created; sentinel preserved; enforcement_level still absent).
t4_backfill_blocks_on_sentinel() {
  local T; T=$(mktemp -d)
  local PROJ="$T/proj"
  setup_backfill_project "$PROJ"
  write_sentinel "$PROJ"

  local pre_manifest_md5;  pre_manifest_md5=$(_md5file "$PROJ/.claude/manifest.json")
  local pre_framework_fp;  pre_framework_fp=$(_tree_fingerprint "$PROJ/.claude/framework")
  local pre_sentinel;      pre_sentinel=$(cat "$PROJ/.claude/pending-approval.json")

  local out rc=0
  out=$(cd "$PROJ" && CDF_HOME="$T/no-such-cdf-clone" "$SCRIPT" --backfill-only --non-interactive </dev/null 2>&1) || rc=$?

  local post_manifest_md5;  post_manifest_md5=$(_md5file "$PROJ/.claude/manifest.json")
  local post_framework_fp;  post_framework_fp=$(_tree_fingerprint "$PROJ/.claude/framework")

  if [ "$rc" = "0" ]; then
    fail_ "T4" "expected non-zero exit for --backfill-only with sentinel; rc=$rc tail:\n$(echo "$out" | tail -10)"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "upgrade blocked — pending user decision"; then
    fail_ "T4" "stderr missing canonical BL-015 deny message; out:\n$(echo "$out" | tail -15)"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "pending-approval.sh --resolve" || ! echo "$out" | grep -qF "pending-approval.sh --clear"; then
    fail_ "T4" "stderr missing --resolve/--clear recovery hints; out:\n$(echo "$out" | tail -15)"; rm -rf "$T"; return
  fi
  # Deny message reflects the sentinel's question (same style the full path uses).
  if ! echo "$out" | grep -qF "Adopt sponsored POC governance?"; then
    fail_ "T4" "deny message did not reflect the sentinel question; out:\n$(echo "$out" | tail -15)"; rm -rf "$T"; return
  fi
  # No mutation: manifest byte-identical.
  if [ "$pre_manifest_md5" != "$post_manifest_md5" ]; then
    fail_ "T4" "manifest.json mutated despite sentinel (md5 $pre_manifest_md5 -> $post_manifest_md5)"; rm -rf "$T"; return
  fi
  # No mutation: .claude/framework/ byte-identical.
  if [ "$pre_framework_fp" != "$post_framework_fp" ]; then
    fail_ "T4" ".claude/framework/ mutated despite sentinel (fingerprint changed)"; rm -rf "$T"; return
  fi
  # BL-030 backfill must NOT have fired (positive proof it was short-circuited).
  if jq -e '.enforcement_level' "$PROJ/.claude/manifest.json" >/dev/null 2>&1; then
    fail_ "T4" "enforcement_level was backfilled despite sentinel — backfill mutated the manifest"; rm -rf "$T"; return
  fi
  # Skills sync must NOT have created .claude/skills/.
  if [ -d "$PROJ/.claude/skills" ]; then
    fail_ "T4" ".claude/skills/ was created despite sentinel — skills backfill fired"; rm -rf "$T"; return
  fi
  # Sentinel preserved unchanged (guard never deletes it).
  if [ "$pre_sentinel" != "$(cat "$PROJ/.claude/pending-approval.json" 2>/dev/null)" ]; then
    fail_ "T4" "sentinel file changed/removed despite block"; rm -rf "$T"; return
  fi

  pass "T4 (T-backfill-blocks-on-sentinel): --backfill-only blocks; rc!=0, deny+question+hints, .claude/framework/ + manifest byte-identical, no skills, sentinel preserved"
  rm -rf "$T"
}

# T5 — T-backfill-proceeds-no-sentinel: no sentinel → --backfill-only
# runs normally (BL-030 backfill fires: enforcement_level appears; no
# deny message). Proves the guard is silent when no sentinel exists.
t5_backfill_proceeds_no_sentinel() {
  local T; T=$(mktemp -d)
  local PROJ="$T/proj"
  setup_backfill_project "$PROJ"   # no sentinel written

  local out rc=0
  out=$(cd "$PROJ" && CDF_HOME="$T/no-such-cdf-clone" "$SCRIPT" --backfill-only --non-interactive </dev/null 2>&1) || rc=$?

  if [ "$rc" != "0" ]; then
    fail_ "T5" "expected rc=0 for --backfill-only without sentinel; rc=$rc tail:\n$(echo "$out" | tail -10)"; rm -rf "$T"; return
  fi
  if echo "$out" | grep -qF "upgrade blocked — pending user decision"; then
    fail_ "T5" "guard deny message fired without a sentinel present (false positive); out:\n$(echo "$out" | tail -10)"; rm -rf "$T"; return
  fi
  # Existing behavior: the BL-030 backfill ran and added enforcement_level.
  if ! jq -e '.enforcement_level == "strict"' "$PROJ/.claude/manifest.json" >/dev/null 2>&1; then
    fail_ "T5" "BL-030 backfill did not run without a sentinel — existing --backfill-only behavior regressed; manifest:\n$(cat "$PROJ/.claude/manifest.json")"; rm -rf "$T"; return
  fi

  pass "T5 (T-backfill-proceeds-no-sentinel): no sentinel → backfill runs (enforcement_level backfilled), guard silent"
  rm -rf "$T"
}

# T6 — mutation proof: neutralize the --backfill-only path's call to
# _bl015_sentinel_guard in a COPY of the script tree. The SAME
# sentinel-present run must then MUTATE the manifest (backfill fires
# despite the sentinel), while the real script leaves it byte-identical.
# Exact whole-line awk target (grep -Fxq guards against drift); the
# indented backfill call is distinct from the full-path (0-indent) call,
# which is left intact.
t6_backfill_guard_mutation_proof() {
  local T; T=$(mktemp -d)
  local TARGET='  _bl015_sentinel_guard'

  if ! grep -Fxq "$TARGET" "$SCRIPT"; then
    fail_ "T6" "mutation target line '  _bl015_sentinel_guard' not found in $SCRIPT — did the backfill guard call change? (test needs updating)"; rm -rf "$T"; return
  fi

  # Control: real script + sentinel → manifest byte-identical (blocked).
  local PROJ_C="$T/proj_control"
  setup_backfill_project "$PROJ_C"; write_sentinel "$PROJ_C"
  local pre_c;  pre_c=$(_md5file "$PROJ_C/.claude/manifest.json")
  ( cd "$PROJ_C" && CDF_HOME="$T/no-such-cdf-clone" "$SCRIPT" --backfill-only --non-interactive </dev/null ) >/dev/null 2>&1
  local post_c; post_c=$(_md5file "$PROJ_C/.claude/manifest.json")
  local control_clean; control_clean=$( [ "$pre_c" = "$post_c" ] && echo y || echo n )

  # Mutant: copy scripts/ (so lib/ resolves), neutralize the backfill call.
  cp -R "$REPO_ROOT/scripts" "$T/scripts"
  local MUT="$T/scripts/upgrade-project.sh"
  awk -v t="$TARGET" '$0==t{print "  : # MUTATION: backfill sentinel guard neutralized"; next}{print}' \
    "$SCRIPT" > "$MUT"
  chmod +x "$MUT"
  # The indented backfill call must be gone; the full-path (0-indent) call must remain.
  if grep -Fxq "$TARGET" "$MUT"; then
    fail_ "T6" "mutation did not take effect — indented backfill call still present in the mutant"; rm -rf "$T"; return
  fi
  if [ "$(grep -Fxc '_bl015_sentinel_guard' "$MUT")" != "1" ]; then
    fail_ "T6" "mutation removed the wrong call — expected exactly 1 remaining full-path (0-indent) call"; rm -rf "$T"; return
  fi

  # Mutant run + SAME sentinel → manifest MUST mutate (guard neutralized).
  local PROJ_M="$T/proj_mutant"
  setup_backfill_project "$PROJ_M"; write_sentinel "$PROJ_M"
  local pre_m;  pre_m=$(_md5file "$PROJ_M/.claude/manifest.json")
  ( cd "$PROJ_M" && CDF_HOME="$T/no-such-cdf-clone" bash "$MUT" --backfill-only --non-interactive </dev/null ) >/dev/null 2>&1
  local post_m; post_m=$(_md5file "$PROJ_M/.claude/manifest.json")
  local mutant_mutates; mutant_mutates=$( { [ "$pre_m" != "$post_m" ] && jq -e '.enforcement_level' "$PROJ_M/.claude/manifest.json" >/dev/null 2>&1; } && echo y || echo n )

  if [ "$control_clean" = "y" ] && [ "$mutant_mutates" = "y" ]; then
    pass "T6 (mutation proof): real script leaves manifest byte-identical under sentinel; neutralizing the backfill guard makes --backfill-only mutate the manifest despite the sentinel (guard is load-bearing)"
  else
    fail_ "T6" "control_clean=$control_clean (pre=$pre_c post=$post_c); mutant_mutates=$mutant_mutates (pre=$pre_m post=$post_m)"
  fi
  rm -rf "$T"
}

echo "== tests/test-upgrade-sentinel-block.sh =="
t1_sentinel_blocks_to_private_poc
t2_malformed_sentinel_still_blocks
t3_no_sentinel_no_guard_message
t4_backfill_blocks_on_sentinel
t5_backfill_proceeds_no_sentinel
t6_backfill_guard_mutation_proof

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

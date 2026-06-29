#!/usr/bin/env bash
# tests/test-check-gate.sh — unit tests for scripts/check-gate.sh.
# Currently covers --backfill-host (T2-E: --yes flag for non-interactive use).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-gate.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_project() {
  TMPDIR_T=$(mktemp -d)
  (
    cd "$TMPDIR_T"
    git init -q
    git remote add origin https://github.com/example/foo.git
    mkdir -p .claude
    echo '{"frameworkVersion":"test","mode":"personal"}' > .claude/manifest.json
  )
}

teardown_project() {
  rm -rf "$TMPDIR_T"
}

t1_yes_flag_writes_host_non_interactive() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --backfill-host --yes </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "expected exit 0 with --yes, got rc=$rc out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ "$host" != "github" ]; then
    fail_ "T1" "expected host='github', got host='$host'"
    teardown_project
    return
  fi
  pass "T1: --backfill-host --yes writes manifest.host non-interactively"
  teardown_project
}

t2_interactive_y_still_works() {
  # Cycle-8 wave-3 slot-5 contract update: the previous version of this
  # test piped `echo y` into a non-TTY stdin and expected the bare
  # `read -rp` to honor the 'y'. After migrating to
  # lib/helpers.sh::prompt_yes_no, non-TTY stdin contexts (CI, piped
  # input, `</dev/null`) DELIBERATELY hard-return N — auto-Y'ing a
  # manifest mutation in CI was the bug the migration closes. The
  # supported non-interactive confirmation path is the `--yes` flag,
  # exercised by T1 and T4. This test now confirms the new contract:
  # piped 'y' WITHOUT `--yes` aborts (no manifest write).
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && echo y | "$SCRIPT" --backfill-host 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T2" "expected non-zero exit on piped 'y' without --yes (non-TTY hard-N policy); got rc=0 out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ -n "$host" ]; then
    fail_ "T2" "expected host unset on non-interactive abort, got host='$host'"
    teardown_project
    return
  fi
  if ! printf '%s' "$out" | grep -qE 'Non-interactive context'; then
    fail_ "T2" "expected WARN diagnostic explaining the non-interactive skip; got: $out"
    teardown_project
    return
  fi
  pass "T2: piped 'y' WITHOUT --yes is correctly refused (non-TTY hard-N policy; use --yes for non-interactive confirm)"
  teardown_project
}

t3_interactive_n_aborts() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && echo n | "$SCRIPT" --backfill-host 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T3" "expected non-zero exit on 'n', got rc=0 out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ -n "$host" ]; then
    fail_ "T3" "expected host unset on abort, got host='$host'"
    teardown_project
    return
  fi
  pass "T3: --backfill-host with stdin 'n' aborts (regression, host not written)"
  teardown_project
}

t4_yes_flag_before_subcommand() {
  setup_project
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --yes --backfill-host </dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T4" "expected exit 0 with --yes before --backfill-host, got rc=$rc out=$out"
    teardown_project
    return
  fi
  local host
  host=$(jq -r '.host // empty' "$TMPDIR_T/.claude/manifest.json")
  if [ "$host" != "github" ]; then
    fail_ "T4" "expected host='github', got host='$host'"
    teardown_project
    return
  fi
  pass "T4: --yes accepted before --backfill-host"
  teardown_project
}

t5_preflight_honors_free_tier_attestation() {
  # BL-002: check-gate.sh --preflight should pass when a github_free_tier
  # branch-protection attestation has been recorded in process-state.json,
  # without invoking host_verify_protection.
  setup_project
  jq '.host = "github" | .mode = "personal"' "$TMPDIR_T/.claude/manifest.json" > "$TMPDIR_T/.claude/manifest.json.tmp" \
    && mv "$TMPDIR_T/.claude/manifest.json.tmp" "$TMPDIR_T/.claude/manifest.json"
  cat > "$TMPDIR_T/.claude/process-state.json" <<'JSON'
{"phase2_init":{"steps_completed":[],"attestations":{"branch_protection":{"attested_by":"orchestrator","at":"2026-04-27T00:00:00Z","reason":"github_free_tier"}}}}
JSON
  local out rc=0
  out=$(cd "$TMPDIR_T" && "$SCRIPT" --preflight 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T5" "expected exit 0 with free-tier attestation, got rc=$rc out=$out"
    teardown_project
    return
  fi
  if [[ "$out" != *"attested"* ]] && [[ "$out" != *"github_free_tier"* ]]; then
    fail_ "T5" "expected message mentioning attestation; got: $out"
    teardown_project
    return
  fi
  pass "T5: --preflight honors github_free_tier attestation (skips API verify)"
  teardown_project
}

echo "== tests/test-check-gate.sh =="
t1_yes_flag_writes_host_non_interactive
t2_interactive_y_still_works
t3_interactive_n_aborts
t4_yes_flag_before_subcommand
t5_preflight_honors_free_tier_attestation

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

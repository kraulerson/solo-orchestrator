#!/usr/bin/env bash
# tests/test-init-no-remote-creation.sh — T2-B + T2-C regression tests.
#
# T2-B: init.sh --non-interactive --no-remote-creation must skip the
#       host_create_repo / push / protection API calls so UAT runs do
#       not contaminate the user's GitHub account, while still writing
#       a usable manifest.
#
# T2-C: .claude/manifest.json must contain `host` after init, even when
#       --no-remote-creation prevents the late "all-success" manifest write
#       from running.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# --- Validate-only tests (cheap, just exercise CLI parsing) ---

run_validate() {
  local tmpdir; tmpdir=$(mktemp -d)
  local out err rc=0
  out=$(cd "$tmpdir" && "$INIT_SH" --non-interactive --validate-only "$@" 2>/tmp/init-no-remote-err) || rc=$?
  err=$(cat /tmp/init-no-remote-err 2>/dev/null || true)
  rm -rf "$tmpdir" /tmp/init-no-remote-err
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')|$(printf '%s' "$err" | tr '\n' ' ')"
}

t1_flag_accepted_validate_only() {
  local out; out=$(run_validate \
    --project p \
    --platform web \
    --deployment personal \
    --language typescript \
    --git-host github \
    --no-remote-creation)
  if [ "${out%%|*}" != "0" ]; then
    fail_ "T1" "expected exit 0, got: $out"
    return
  fi
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  if [[ "$stdout" != *'"no_remote_creation": true'* ]]; then
    fail_ "T1" "stdout missing no_remote_creation:true; got: $stdout"
    return
  fi
  pass "T1: --no-remote-creation accepted; resolved JSON shows no_remote_creation=true"
}

t2_flag_default_false_validate_only() {
  local out; out=$(run_validate \
    --project p \
    --platform web \
    --deployment personal \
    --language typescript)
  if [ "${out%%|*}" != "0" ]; then
    fail_ "T2" "expected exit 0, got: $out"
    return
  fi
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  if [[ "$stdout" != *'"no_remote_creation": false'* ]]; then
    fail_ "T2" "stdout missing no_remote_creation:false default; got: $stdout"
    return
  fi
  pass "T2: --no-remote-creation absent → resolves to false"
}

# --- Integration test (real init run; covers T2-B effect + T2-C invariant) ---

t3_integration_skips_api_writes_manifest() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj="$tmpdir/proj"
  local out err rc=0
  # cd to tmpdir so the framework-self-guard (helpers.sh:guard_not_in_framework)
  # doesn't refuse — it checks pwd, not --project-dir.
  out=$( cd "$tmpdir" && "$INIT_SH" --non-interactive \
           --project test-no-remote \
           --platform web \
           --deployment personal \
           --language typescript \
           --git-host github \
           --visibility private \
           --project-dir "$proj" \
           --no-remote-creation 2>"$tmpdir/err" ) || rc=$?
  err=$(cat "$tmpdir/err" 2>/dev/null || true)
  if [ "$rc" -ne 0 ]; then
    fail_ "T3" "expected exit 0; got rc=$rc; stderr tail: $(echo "$err" | tail -10)"
    rm -rf "$tmpdir"; return
  fi
  if [ ! -f "$proj/.claude/manifest.json" ]; then
    fail_ "T3" "manifest.json not written"
    rm -rf "$tmpdir"; return
  fi
  local host; host=$(jq -r '.host // empty' "$proj/.claude/manifest.json")
  if [ "$host" != "github" ]; then
    fail_ "T3" "expected manifest.host='github'; got '$host'"
    rm -rf "$tmpdir"; return
  fi
  # Assert no real remote was added.
  if (cd "$proj" && git remote get-url origin >/dev/null 2>&1); then
    local url; url=$(cd "$proj" && git remote get-url origin)
    fail_ "T3" "expected NO origin remote (--no-remote-creation); got: $url"
    rm -rf "$tmpdir"; return
  fi
  pass "T3: --no-remote-creation produces project with manifest.host='github' and no origin remote"
  rm -rf "$tmpdir"
}

echo "== tests/test-init-no-remote-creation.sh =="
t1_flag_accepted_validate_only
t2_flag_default_false_validate_only
t3_integration_skips_api_writes_manifest

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

#!/usr/bin/env bash
# tests/test-init-non-interactive.sh — unit tests for init.sh --non-interactive (BL-016).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Run init.sh --non-interactive --validate-only with the given args from
# inside a fresh tempdir. Echoes "EXIT|STDOUT|STDERR".
run_validate() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local out err rc=0
  out=$(cd "$tmpdir" && "$INIT_SH" --non-interactive --validate-only "$@" 2>/tmp/init-test-err) || rc=$?
  err=$(cat /tmp/init-test-err 2>/dev/null || true)
  rm -rf "$tmpdir" /tmp/init-test-err
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')|$(printf '%s' "$err" | tr '\n' ' ')"
}

# --- Tests ---

n1_happy_path() {
  local out; out=$(run_validate \
    --project p \
    --platform web \
    --deployment personal \
    --language typescript)
  [ "${out%%|*}" = "0" ] || { fail_ "N1" "expected exit 0, got: $out"; return; }
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"_validated": true'* ]] || { fail_ "N1" "stdout missing _validated:true: $stdout"; return; }
  pass "N1: all required flags present → exit 0 with resolved JSON"
}

n11_invalid_platform() {
  local out; out=$(run_validate --project p --platform foo --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N11" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--platform"* ]] || { fail_ "N11" "stderr should mention --platform: ${out##*|}"; return; }
  pass "N11: invalid --platform → exit 1 with platform listed"
}

n12_invalid_project_name() {
  local out; out=$(run_validate --project "Foo!" --platform web --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N12" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"project"* ]] || { fail_ "N12" "stderr should mention project: ${out##*|}"; return; }
  pass "N12: invalid --project name → exit 1 with naming-rule message"
}

# --- Run all ---
echo "== tests/test-init-non-interactive.sh =="
n1_happy_path
n11_invalid_platform
n12_invalid_project_name

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

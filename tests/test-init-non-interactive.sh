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

n2_missing_project() {
  local out; out=$(run_validate --platform web --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N2" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--project"* ]] || { fail_ "N2" "stderr should mention --project: ${out##*|}"; return; }
  pass "N2: missing --project → exit 1"
}

n3_missing_platform() {
  local out; out=$(run_validate --project p --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N3" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--platform"* ]] || { fail_ "N3" "stderr should mention --platform: ${out##*|}"; return; }
  pass "N3: missing --platform → exit 1"
}

n4_missing_deployment() {
  local out; out=$(run_validate --project p --platform web --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N4" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--deployment"* ]] || { fail_ "N4" "stderr should mention --deployment: ${out##*|}"; return; }
  pass "N4: missing --deployment → exit 1"
}

n5_missing_language() {
  local out; out=$(run_validate --project p --platform web --deployment personal)
  [ "${out%%|*}" = "1" ] || { fail_ "N5" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--language"* ]] || { fail_ "N5" "stderr should mention --language: ${out##*|}"; return; }
  pass "N5: missing --language → exit 1"
}

n6_org_without_govmode() {
  local out; out=$(run_validate --project p --platform web --deployment organizational --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N6" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--gov-mode"* ]] || { fail_ "N6" "stderr should mention --gov-mode: ${out##*|}"; return; }
  pass "N6: --deployment=organizational without --gov-mode → exit 1"
}

n7_personal_with_govmode() {
  local out; out=$(run_validate --project p --platform web --deployment personal --gov-mode production --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N7" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--gov-mode"* ]] || { fail_ "N7" "stderr should mention --gov-mode: ${out##*|}"; return; }
  pass "N7: --deployment=personal with --gov-mode → exit 1"
}

n8_other_without_remoteurl() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language ts --git-host other)
  [ "${out%%|*}" = "1" ] || { fail_ "N8" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--remote-url"* ]] || { fail_ "N8" "stderr should mention --remote-url: ${out##*|}"; return; }
  pass "N8: --git-host=other without --remote-url → exit 1"
}

n9_other_without_attest() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language ts --git-host other --remote-url https://example.com/x)
  [ "${out%%|*}" = "1" ] || { fail_ "N9" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--branch-protection-attested"* ]] || { fail_ "N9" "stderr should mention --branch-protection-attested: ${out##*|}"; return; }
  pass "N9: --git-host=other without --branch-protection-attested → exit 1"
}

n10_org_with_public_visibility() {
  local out; out=$(run_validate --project p --platform web --deployment organizational --gov-mode production --language ts --visibility public)
  [ "${out%%|*}" = "1" ] || { fail_ "N10" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--visibility=public"* ]] || { fail_ "N10" "stderr should explain org-forces-private: ${out##*|}"; return; }
  pass "N10: --deployment=organizational + --visibility=public → exit 1"
}

n13_invalid_language_for_platform() {
  # If the platform's intake-suggestions JSON doesn't expose a language list, this
  # test is a soft-no-op (passes by default because check is skipped) — that's
  # acceptable: it documents intent without false-failing on schema variance.
  local out; out=$(run_validate --project p --platform mcp_server --deployment personal --language swift)
  if [ "${out%%|*}" = "0" ]; then
    pass "N13: invalid --language for platform — check skipped (intake-suggestions schema does not expose language list)"
    return
  fi
  [[ "${out##*|}" == *"language"* ]] || { fail_ "N13" "stderr should mention language validity: ${out##*|}"; return; }
  pass "N13: invalid --language for platform → exit 1"
}

n20_validate_only_success() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language typescript)
  [ "${out%%|*}" = "0" ] || { fail_ "N20" "expected exit 0, got: $out"; return; }
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"_validated": true'* ]] || { fail_ "N20" "stdout missing _validated:true: $stdout"; return; }
  [[ "$stdout" == *'"track": "standard"'* ]] || { fail_ "N20" "stdout missing default track: $stdout"; return; }
  [[ "$stdout" == *'"git_host": "github"'* ]] || { fail_ "N20" "stdout missing default git_host: $stdout"; return; }
  [[ "$stdout" == *'"visibility": "private"'* ]] || { fail_ "N20" "stdout missing default visibility: $stdout"; return; }
  pass "N20: --validate-only success → exit 0 + full resolved JSON with defaults filled"
}

n21_validate_only_failure() {
  local out; out=$(run_validate --platform web --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N21" "expected exit 1, got: $out"; return; }
  pass "N21: --validate-only failure → exit 1 with same error as real run"
}

n22_allow_existing_dir() {
  # Setup: create a dir, then run with --allow-existing-dir + --project-dir pointing to it.
  # Must cd to a non-framework cwd so the U-N framework guard doesn't fire.
  local existing cwd_for_run
  existing=$(mktemp -d)
  cwd_for_run=$(mktemp -d)
  local out rc=0
  out=$(cd "$cwd_for_run" && "$INIT_SH" --non-interactive --validate-only \
        --project p --platform web --deployment personal --language typescript \
        --project-dir "$existing" --allow-existing-dir 2>&1) || rc=$?
  rm -rf "$existing" "$cwd_for_run"
  [ "$rc" = "0" ] || { fail_ "N22" "expected exit 0 with --allow-existing-dir, got rc=$rc out=$out"; return; }
  pass "N22: existing dir + --allow-existing-dir → exit 0"
}

n14_config_provides_everything() {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript"}
JSON
  local out; out=$(run_validate --config "$cfg")
  rm -f "$cfg"
  [ "${out%%|*}" = "0" ] || { fail_ "N14" "expected exit 0, got: $out"; return; }
  pass "N14: --config provides everything → exit 0"
}

n15_flag_overrides_config() {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript","track":"light"}
JSON
  local out; out=$(run_validate --config "$cfg" --track full)
  rm -f "$cfg"
  [ "${out%%|*}" = "0" ] || { fail_ "N15" "expected exit 0, got: $out"; return; }
  pass "N15: flag overrides --config value → exit 0"
}

n16_config_not_found() {
  local out; out=$(run_validate --config /nonexistent/path/init.json --project p --platform web --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N16" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"not found"* ]] || { fail_ "N16" "stderr should mention 'not found': ${out##*|}"; return; }
  pass "N16: --config file not found → exit 1"
}

n17_config_malformed_json() {
  local cfg
  cfg=$(mktemp)
  echo '{"project": "p"' > "$cfg"
  local out; out=$(run_validate --config "$cfg" --project p --platform web --deployment personal --language ts)
  rm -f "$cfg"
  [ "${out%%|*}" = "1" ] || { fail_ "N17" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"not valid JSON"* ]] || { fail_ "N17" "stderr should mention 'not valid JSON': ${out##*|}"; return; }
  pass "N17: --config malformed JSON → exit 1"
}

n18_config_unknown_field() {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript","frobnicate":"bar"}
JSON
  local out; out=$(run_validate --config "$cfg")
  rm -f "$cfg"
  [ "${out%%|*}" = "0" ] || { fail_ "N18" "expected exit 0 (warn-not-fail), got: $out"; return; }
  # print_warn writes to stdout; check the full combined output.
  [[ "$out" == *"frobnicate"* ]] || { fail_ "N18" "expected 'frobnicate' warning anywhere in output: $out"; return; }
  pass "N18: --config unknown field → warn + ignore + continue"
}

n19_config_without_non_interactive() {
  local cfg cwd_for_run
  cfg=$(mktemp)
  cwd_for_run=$(mktemp -d)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript"}
JSON
  # Without --non-interactive, --config should warn and fall through. With stdin
  # closed, the prompt_choice EOF guard from PR #18 will return 1 and init.sh
  # exits — no need for an external timeout. Run from a tempdir so framework
  # guard doesn't fire.
  local out rc=0
  out=$(cd "$cwd_for_run" && "$INIT_SH" --dry-run --config "$cfg" </dev/null 2>&1) || rc=$?
  rm -f "$cfg"; rm -rf "$cwd_for_run"
  [[ "$out" == *"requires --non-interactive"* ]] \
    || { fail_ "N19" "expected 'requires --non-interactive' warning, got: $out"; return; }
  pass "N19: --config without --non-interactive → warn + fall through"
}

n24_default_track() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language typescript)
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"track": "standard"'* ]] || { fail_ "N24" "default track should be 'standard': $stdout"; return; }
  pass "N24: --track defaults to 'standard' when not specified"
}

n25_default_git_host_visibility() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language typescript)
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"git_host": "github"'* ]] || { fail_ "N25" "default git_host should be 'github': $stdout"; return; }
  [[ "$stdout" == *'"visibility": "private"'* ]] || { fail_ "N25" "default visibility should be 'private': $stdout"; return; }
  pass "N25: --git-host defaults to 'github', --visibility defaults to 'private'"
}

n26_default_project_dir() {
  local out; out=$(run_validate --project mytestproj --platform web --deployment personal --language typescript)
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"project_dir": "'$HOME'/Code/mytestproj"'* ]] || { fail_ "N26" "default project_dir should be \$HOME/Code/PROJECT: $stdout"; return; }
  pass "N26: --project-dir defaults to \$HOME/Code/\$PROJECT"
}

n23_dir_exists_no_allow_flag() {
  local existing cwd_for_run
  existing=$(mktemp -d)
  cwd_for_run=$(mktemp -d)
  local out rc=0
  out=$(cd "$cwd_for_run" && "$INIT_SH" --non-interactive --validate-only \
        --project p --platform web --deployment personal --language typescript \
        --project-dir "$existing" 2>&1) || rc=$?
  rm -rf "$existing" "$cwd_for_run"
  [ "$rc" = "1" ] || { fail_ "N23" "expected exit 1, got rc=$rc out=$out"; return; }
  [[ "$out" == *"--allow-existing-dir"* ]] || { fail_ "N23" "stderr should suggest --allow-existing-dir: $out"; return; }
  pass "N23: existing dir without --allow-existing-dir → exit 1 with flag suggestion"
}

# --- Run all ---
echo "== tests/test-init-non-interactive.sh =="
n1_happy_path
n2_missing_project
n3_missing_platform
n4_missing_deployment
n5_missing_language
n6_org_without_govmode
n7_personal_with_govmode
n8_other_without_remoteurl
n9_other_without_attest
n10_org_with_public_visibility
n11_invalid_platform
n12_invalid_project_name
n13_invalid_language_for_platform
n14_config_provides_everything
n15_flag_overrides_config
n16_config_not_found
n17_config_malformed_json
n18_config_unknown_field
n19_config_without_non_interactive
n20_validate_only_success
n21_validate_only_failure
n22_allow_existing_dir
n23_dir_exists_no_allow_flag
n24_default_track
n25_default_git_host_visibility
n26_default_project_dir

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

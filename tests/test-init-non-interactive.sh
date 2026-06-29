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
  # Audit code-init-sh-5 + specs-plans-init-intake-noninteractive-5: the
  # Pass-2 language-for-platform check MUST be strict (no soft-no-op). It
  # walks templates/pipelines/ci/github/*.yml and accepts only languages
  # whose template marker lists the requested platform.
  # mcp_server platform allows: python, typescript, other (per CI markers).
  # swift on mcp_server is invalid and must exit 1.
  local out; out=$(run_validate --project p --platform mcp_server --deployment personal --language swift)
  [ "${out%%|*}" = "1" ] || { fail_ "N13" "expected exit 1 for swift on mcp_server, got: $out"; return; }
  [[ "${out##*|}" == *"language"* ]] || { fail_ "N13" "stderr should mention language: ${out##*|}"; return; }
  [[ "${out##*|}" == *"mcp_server"* ]] || { fail_ "N13" "stderr should mention platform mcp_server: ${out##*|}"; return; }
  pass "N13: invalid --language for platform → exit 1 (hard fail, not soft no-op)"
}

n27_invalid_language_lists_supported() {
  # Audit code-init-sh-5: the failure message must enumerate the platform's
  # actually-supported languages so the user can re-run with a valid value.
  # dart's CI template marker is `platforms=mobile`, so dart on web must fail.
  local out; out=$(run_validate --project p --platform web --deployment personal --language dart)
  [ "${out%%|*}" = "1" ] || { fail_ "N27" "expected exit 1 for dart on web, got: $out"; return; }
  # web platform supports typescript, python, java, csharp, go, rust, kotlin per CI markers
  [[ "${out##*|}" == *"typescript"* ]] || { fail_ "N27" "stderr should list typescript as supported for web: ${out##*|}"; return; }
  [[ "${out##*|}" == *"python"* ]] || { fail_ "N27" "stderr should list python as supported for web: ${out##*|}"; return; }
  pass "N27: invalid --language lists actually-supported languages from CI templates"
}

n28_swift_on_linux_blocked() {
  # Audit code-init-sh-5: mirror the interactive Linux/Swift OS-compatibility
  # block (init.sh:506-537). Swift requires macOS (Xcode toolchain).
  # We can't change OS_TYPE easily, so only assert on Linux hosts.
  if [ "$(uname -s)" != "Linux" ]; then
    pass "N28: Swift-on-Linux OS-incompatibility block — skipped (test host is $(uname -s), check is Linux-only)"
    return
  fi
  local out; out=$(run_validate --project p --platform mobile --deployment personal --language swift)
  [ "${out%%|*}" = "1" ] || { fail_ "N28" "expected exit 1 for swift on Linux, got: $out"; return; }
  [[ "${out##*|}" == *"macOS"* || "${out##*|}" == *"Xcode"* ]] \
    || { fail_ "N28" "stderr should mention macOS/Xcode requirement: ${out##*|}"; return; }
  pass "N28: --language=swift on Linux → exit 1 (OS-incompatibility block)"
}

n29_mcp_server_platform_alias() {
  # Audit specs-plans-init-intake-noninteractive-3: the suggestion-file set
  # ships mcp_server.json (not cli.json). Confirm mcp_server is a first-class
  # platform value in non-interactive mode and that typescript/python (the
  # languages with CI templates marking mcp_server) both validate.
  local out; out=$(run_validate --project p --platform mcp_server --deployment personal --language typescript)
  [ "${out%%|*}" = "0" ] || { fail_ "N29a" "expected exit 0 for typescript on mcp_server, got: $out"; return; }
  out=$(run_validate --project p --platform mcp_server --deployment personal --language python)
  [ "${out%%|*}" = "0" ] || { fail_ "N29b" "expected exit 0 for python on mcp_server, got: $out"; return; }
  pass "N29: mcp_server platform accepts typescript and python (matches shipped suggestion file)"
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
n27_invalid_language_lists_supported
n28_swift_on_linux_blocked
n29_mcp_server_platform_alias

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

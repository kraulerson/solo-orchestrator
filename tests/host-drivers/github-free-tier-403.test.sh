#!/usr/bin/env bash
# tests/host-drivers/github-free-tier-403.test.sh — BL-002 regression test.
#
# Registered via the tests/host-drivers/run-all.sh `*.test.sh` glob
# (BL-035 wiring B). Previously orphaned as tests/test-github-free-tier-403.sh
# on the KNOWN_ORPHANS_PENDING_BL035 bridge; relocated here so run-all.sh
# picks it up alongside the other host-driver unit tests.
#
# scripts/host-drivers/github.sh::host_configure_protection swallowed the
# gh CLI's stderr (`>/dev/null 2>&1`) and printed a generic
# "failed to configure protection" message. Free-tier accounts trying to
# enable branch protection on private repos got a cryptic failure with no
# tier context — even though gh's actual response includes the helpful
# "Upgrade to GitHub Pro or make this repository public" body.
#
# Fix: capture gh's stderr; if the response matches the free-tier 403
# pattern, return exit code 3 (distinct from 2=other API failure) and
# emit a structured remediation message. Other failures keep returning 2.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# SCRIPT_DIR is tests/host-drivers/, so repo root is two levels up.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRIVER="$REPO_ROOT/scripts/host-drivers/github.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Set up a tempdir with a fake `gh` on PATH that emits a chosen response
# body and exit code, plus a git remote that the driver can parse.
setup_with_fake_gh() {
  local fake_response="$1"
  local fake_exit="$2"
  TMPDIR_T=$(mktemp -d)
  mkdir -p "$TMPDIR_T/bin"
  cat > "$TMPDIR_T/bin/gh" <<GHEOF
#!/usr/bin/env bash
# Fake gh for BL-002 testing. Always emits the canned response and exit code,
# regardless of subcommand (api, repo, etc.).
case "\$*" in
  *"branches/"*"/protection"*)
    printf '%s\n' "$fake_response" >&2
    exit $fake_exit
    ;;
  *)
    # Other gh invocations (e.g. auth status) succeed silently.
    exit 0
    ;;
esac
GHEOF
  chmod +x "$TMPDIR_T/bin/gh"
  # Fake project with a github origin so _github_parse_origin succeeds.
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    git remote add origin https://github.com/test/repo.git
  )
}
teardown_project() { rm -rf "$TMPDIR_T"; }

# Source the driver and call host_configure_protection inside a subshell with
# fake gh on PATH. Echoes "EXIT|STDERR".
run_configure() {
  (
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    set +e
    # shellcheck disable=SC1090
    source "$DRIVER"
    out=$(host_configure_protection main personal 2>&1)
    rc=$?
    printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
  )
}

t1_free_tier_403_returns_3_with_remediation() {
  setup_with_fake_gh 'HTTP 403: Upgrade to GitHub Pro or make this repository public to enable this feature. (https://api.github.com/repos/test/repo/branches/main/protection)' 1
  local out; out=$(run_configure)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" != "3" ]; then
    fail_ "T1" "expected exit 3 for free-tier 403; got rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"GitHub Pro"* ]] && [[ "$stderr" != *"free-tier"* ]] && [[ "$stderr" != *"tier"* ]]; then
    fail_ "T1" "expected remediation mentioning tier/Pro; stderr=$stderr"
    teardown_project; return
  fi
  pass "T1: free-tier 403 → exit 3 + remediation message"
  teardown_project
}

t2_success_returns_0() {
  setup_with_fake_gh '' 0
  local out; out=$(run_configure)
  local rc="${out%%|*}"
  if [ "$rc" != "0" ]; then
    fail_ "T2" "expected exit 0 on success; got rc=$rc out=$out"
    teardown_project; return
  fi
  pass "T2: gh PUT succeeds → exit 0"
  teardown_project
}

t3_generic_403_returns_2() {
  # Generic 403 (e.g., insufficient permissions on an org repo) should NOT
  # be classified as the free-tier limitation.
  setup_with_fake_gh 'HTTP 403: Resource not accessible by integration' 1
  local out; out=$(run_configure)
  local rc="${out%%|*}"
  if [ "$rc" != "2" ]; then
    fail_ "T3" "expected exit 2 for generic 403; got rc=$rc out=$out"
    teardown_project; return
  fi
  pass "T3: generic 403 → exit 2 (not free-tier)"
  teardown_project
}

t4_auth_401_returns_2() {
  setup_with_fake_gh 'HTTP 401: Bad credentials' 1
  local out; out=$(run_configure)
  local rc="${out%%|*}"
  if [ "$rc" != "2" ]; then
    fail_ "T4" "expected exit 2 for auth failure; got rc=$rc out=$out"
    teardown_project; return
  fi
  pass "T4: 401 auth failure → exit 2 (existing behavior preserved)"
  teardown_project
}

echo "== tests/host-drivers/github-free-tier-403.test.sh =="
t1_free_tier_403_returns_3_with_remediation
t2_success_returns_0
t3_generic_403_returns_2
t4_auth_401_returns_2

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

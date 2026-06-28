#!/usr/bin/env bash
# tests/host-drivers/bitbucket.test.sh — Bitbucket driver unit tests
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OLD_PATH="$PATH"

source "$REPO_ROOT/scripts/host-drivers/bitbucket.sh"

# host_name
assert_eq "bitbucket" "$(host_name)" "host_name"
echo "bitbucket.test.sh: host_name PASSED"

# host_require_cli — no creds. Defensively unset all three vars so an
# inherited test env doesn't satisfy the check accidentally.
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
set +e; output=$(host_require_cli 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "no creds fails"
assert_contains "$output" "BITBUCKET_USER" "mentions env var"

# with creds — driver requires all three vars (audit code-host-bitbucket-1
# added BITBUCKET_WORKSPACE alongside USER + APP_PASSWORD). Pre-fix the
# test exported only USER + APP_PASSWORD, so host_require_cli fell into
# its "missing var" branch and emitted the App-Password help text +
# returned 1 — ASSERT FAIL "with creds passes".
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="testws"
set +e; host_require_cli; code=$?; set -e
assert_exit_code 0 "$code" "with creds passes"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_require_cli PASSED"

# host_register_remote
WORK=$(mktemp -d); cd "$WORK"
git init -q
host_register_remote "https://bitbucket.org/ws/repo.git"
assert_eq "https://bitbucket.org/ws/repo.git" "$(git remote get-url origin)" "register"
cd - >/dev/null; rm -rf "$WORK"
echo "bitbucket.test.sh: host_register_remote PASSED"

# _bb_parse_origin
WORK=$(mktemp -d); cd "$WORK"
git init -q
git remote add origin "https://bitbucket.org/ws/repo.git"
assert_eq "ws/repo" "$(_bb_parse_origin)" "parse_origin"
cd - >/dev/null; rm -rf "$WORK"
echo "bitbucket.test.sh: _bb_parse_origin PASSED"

# ════════════════════════════════════════════════════════════════════
# host_configure_protection — BL-005 closure (cycle 8). The driver invokes
# curl 2-7 times per call (1 GET idempotency scan, 0-N DELETEs, 2 POSTs
# personal / 5 POSTs org). mock-cli's stub matches on a substring of the
# full argv; both POSTs share the `/branch-restrictions` URL so a single
# fixture serves all kinds. The idempotency GET uses
# `branch-restrictions?pattern=main` — distinct substring → distinct fixture.
# Bitbucket credentials are required by the driver's `_bb_curl` (-u flag)
# but never validated by the stub; export sentinels so the auth assembly
# doesn't error.
# ════════════════════════════════════════════════════════════════════

# host_configure_protection personal — 2 POSTs (force + delete), no idempotency hits
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/ws/repo.git"
# Idempotency scan returns no existing restrictions → no DELETE issued.
mock_cli_respond curl "branch-restrictions?pattern=main" 0 '{"values":[]}'
# POST creates restrictions; one fixture serves all kinds (force, delete in personal).
mock_cli_respond curl "-X POST" 0 '{"id":1,"kind":"force"}'
set +e; host_configure_protection "main" "personal"; code=$?; set -e
assert_exit_code 0 "$code" "personal configure succeeds"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_configure_protection (personal) PASSED"

# host_configure_protection org — 5 POSTs total (force, delete, push, approvals, builds).
# One curl POST fixture serves all five since they share the URL substring.
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="orgws"
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/orgws/orgrepo.git"
mock_cli_respond curl "branch-restrictions?pattern=main" 0 '{"values":[]}'
mock_cli_respond curl "-X POST" 0 '{"id":1}'
set +e; host_configure_protection "main" "org"; code=$?; set -e
assert_exit_code 0 "$code" "org configure succeeds"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_configure_protection (org) PASSED"

# host_verify_protection personal pass — both force + delete restrictions present.
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/ws/repo.git"
mock_cli_respond curl "branch-restrictions?pattern=main" 0 \
  '{"values":[{"id":1,"kind":"force","pattern":"main"},{"id":2,"kind":"delete","pattern":"main"}]}'
set +e; host_verify_protection "main" "personal"; code=$?; set -e
assert_exit_code 0 "$code" "personal verify pass"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_verify_protection (personal pass) PASSED"

# host_verify_protection personal fail — force-push restriction missing.
# Driver returns 1 + prints "force-push not restricted" on stderr.
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/ws/repo.git"
# Only the delete kind present — force missing → personal failure path.
mock_cli_respond curl "branch-restrictions?pattern=main" 0 \
  '{"values":[{"id":2,"kind":"delete","pattern":"main"}]}'
set +e; output=$(host_verify_protection "main" "personal" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "personal verify fail (force missing)"
assert_contains "$output" "force-push" "mentions force-push rule"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_verify_protection (personal fail) PASSED"

# host_verify_protection org pass — all 5 kinds present, approvals + builds value>=1.
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="orgws"
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/orgws/orgrepo.git"
mock_cli_respond curl "branch-restrictions?pattern=main" 0 \
  '{"values":[{"id":1,"kind":"force","pattern":"main"},{"id":2,"kind":"delete","pattern":"main"},{"id":3,"kind":"push","pattern":"main"},{"id":4,"kind":"require_approvals_to_merge","pattern":"main","value":1},{"id":5,"kind":"require_passing_builds_to_merge","pattern":"main","value":1}]}'
set +e; host_verify_protection "main" "org"; code=$?; set -e
assert_exit_code 0 "$code" "org verify pass"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_verify_protection (org pass) PASSED"

# host_verify_protection org fail — push restriction missing (force+delete+approvals+builds OK).
# Driver reports specific missing org-mode rules on stderr.
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="orgws"
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/orgws/orgrepo.git"
mock_cli_respond curl "branch-restrictions?pattern=main" 0 \
  '{"values":[{"id":1,"kind":"force","pattern":"main"},{"id":2,"kind":"delete","pattern":"main"},{"id":4,"kind":"require_approvals_to_merge","pattern":"main","value":1},{"id":5,"kind":"require_passing_builds_to_merge","pattern":"main","value":1}]}'
set +e; output=$(host_verify_protection "main" "org" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "org verify fail (push missing)"
assert_contains "$output" "push" "mentions push restriction"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_verify_protection (org fail) PASSED"

echo "bitbucket.test.sh: all tests PASSED"

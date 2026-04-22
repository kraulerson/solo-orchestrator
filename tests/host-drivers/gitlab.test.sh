#!/usr/bin/env bash
# tests/host-drivers/gitlab.test.sh — GitLab driver unit tests
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OLD_PATH="$PATH"

source "$REPO_ROOT/scripts/host-drivers/gitlab.sh"

# host_name
assert_eq "gitlab" "$(host_name)" "host_name"
echo "gitlab.test.sh: host_name PASSED"

# host_require_cli — missing glab
MOCK_DIR=$(mock_cli_setup)
export PATH="$MOCK_DIR"
set +e; output=$(host_require_cli 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "missing glab"
assert_contains "$output" "glab" "mentions glab"
export PATH="$OLD_PATH"
mock_cli_teardown "$MOCK_DIR"
echo "gitlab.test.sh: host_require_cli (missing) PASSED"

# host_create_repo
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond glab "repo create my-repo --private" 0 "https://gitlab.com/user/my-repo"
url=$(host_create_repo "my-repo" "private")
assert_eq "https://gitlab.com/user/my-repo" "$url" "create private"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_create_repo PASSED"

# host_register_remote
WORK=$(mktemp -d); cd "$WORK"
git init -q
host_register_remote "https://gitlab.com/u/r.git"
assert_eq "https://gitlab.com/u/r.git" "$(git remote get-url origin)" "register sets origin"
cd - >/dev/null; rm -rf "$WORK"
echo "gitlab.test.sh: host_register_remote PASSED"

# host_configure_protection personal
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://gitlab.com/user/project.git"
mock_cli_respond glab "api -X POST projects/user%2Fproject/protected_branches" 0 '{"id":1,"name":"main"}'
mock_cli_respond glab "api -X DELETE projects/user%2Fproject/protected_branches/main" 0 ""
set +e; host_configure_protection "main" "personal"; code=$?; set -e
assert_exit_code 0 "$code" "personal configure succeeds"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_configure_protection (personal) PASSED"

# host_verify_protection — personal pass
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://gitlab.com/u/p.git"
mock_cli_respond glab "api projects/u%2Fp/protected_branches/main" 0 '{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":40}]}'
set +e; host_verify_protection "main" "personal"; code=$?; set -e
assert_exit_code 0 "$code" "personal verify pass"

# verify fails on force-push allowed
mock_cli_respond glab "api projects/u%2Fp/protected_branches/main" 0 '{"name":"main","allow_force_push":true,"push_access_levels":[{"access_level":40}]}'
set +e; output=$(host_verify_protection "main" "personal" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "force-push allowed fails"
assert_contains "$output" "force-push" "mentions rule"

# org mode requires approvals — fail case
mock_cli_respond glab "api projects/u%2Fp/protected_branches/main" 0 '{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":40}]}'
mock_cli_respond glab "api projects/u%2Fp/approvals" 0 '{"approvals_before_merge":0}'
set +e; output=$(host_verify_protection "main" "org" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "org no approvals fails"
assert_contains "$output" "approval" "mentions approvals"

cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_verify_protection PASSED"

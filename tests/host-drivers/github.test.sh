#!/usr/bin/env bash
# tests/host-drivers/github.test.sh — GitHub driver unit tests
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

OLD_PATH="$PATH"

source "$REPO_ROOT/scripts/host-drivers/github.sh"

# Test: host_name returns "github"
actual=$(host_name)
assert_eq "github" "$actual" "host_name"

echo "github.test.sh: host_name PASSED"

# Test: host_require_cli fails when gh missing
MOCK_DIR=$(mock_cli_setup)
# Isolated PATH — only MOCK_DIR, no system bins including gh
export PATH="$MOCK_DIR"
set +e
output=$(host_require_cli 2>&1)
code=$?
set -e
assert_exit_code 1 "$code" "missing gh returns 1"
assert_contains "$output" "gh" "mentions gh CLI"
assert_contains "$output" "install" "install guidance"
export PATH="$OLD_PATH"
mock_cli_teardown "$MOCK_DIR"
echo "github.test.sh: host_require_cli (missing) PASSED"

# Test: host_require_cli fails when gh present but not authed
MOCK_DIR=$(mock_cli_setup)
export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond gh "auth status" 1 "not logged in"
mock_cli_respond gh "--version" 0 "gh version 2.0"
set +e
output=$(host_require_cli 2>&1)
code=$?
set -e
assert_exit_code 2 "$code" "unauth'd gh returns 2"
assert_contains "$output" "authenticated" "mentions auth"
export PATH="$OLD_PATH"
mock_cli_teardown "$MOCK_DIR"
echo "github.test.sh: host_require_cli (unauthed) PASSED"

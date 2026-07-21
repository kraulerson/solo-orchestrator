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

# host_require_cli — glab present but unauthed. Parity with github.test.sh
# (BL-005 closure, cycle 8). gitlab.sh distinguishes missing-binary (rc=1,
# install guidance) from auth-failure (rc=2, `glab auth login` guidance).
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond glab "auth status" 1 "not logged in"
mock_cli_respond glab "--version" 0 "glab 1.0"
set +e; output=$(host_require_cli 2>&1); code=$?; set -e
assert_exit_code 2 "$code" "unauth'd glab returns 2"
assert_contains "$output" "authenticated" "mentions auth"
export PATH="$OLD_PATH"; mock_cli_teardown "$MOCK_DIR"
echo "gitlab.test.sh: host_require_cli (unauthed) PASSED"

# host_create_repo private
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond glab "repo create my-repo --private" 0 "https://gitlab.com/user/my-repo"
url=$(host_create_repo "my-repo" "private")
assert_eq "https://gitlab.com/user/my-repo" "$url" "create private"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_create_repo (private) PASSED"

# host_create_repo public — parity with github.test.sh (BL-005).
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond glab "repo create pub-repo --public" 0 "https://gitlab.com/user/pub-repo"
url=$(host_create_repo "pub-repo" "public")
assert_eq "https://gitlab.com/user/pub-repo" "$url" "create public"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_create_repo (public) PASSED"

# host_create_repo dupe — already-exists path returns non-zero + surfaces glab's stderr.
# Parity with github.test.sh (BL-005).
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond glab "repo create dupe --private" 1 "repository already exists"
set +e; output=$(host_create_repo "dupe" "private" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "existing repo returns non-zero"
assert_contains "$output" "already exists" "surfaces underlying error"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_create_repo (dupe) PASSED"

# host_register_remote — fresh init.
WORK=$(mktemp -d); cd "$WORK"
git init -q
host_register_remote "https://gitlab.com/u/r.git"
assert_eq "https://gitlab.com/u/r.git" "$(git remote get-url origin)" "register sets origin"
cd - >/dev/null; rm -rf "$WORK"
echo "gitlab.test.sh: host_register_remote (fresh) PASSED"

# host_register_remote — replaces existing origin idempotently. Parity with
# github.test.sh (BL-005).
WORK=$(mktemp -d); cd "$WORK"
git init -q
git remote add origin "https://example.com/old.git"
host_register_remote "https://gitlab.com/u/r.git"
assert_eq "https://gitlab.com/u/r.git" "$(git remote get-url origin)" "register replaces existing"
cd - >/dev/null; rm -rf "$WORK"
echo "gitlab.test.sh: host_register_remote (replace) PASSED"

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

# host_configure_protection org — POST protected_branches + POST
# approval_rules + PUT projects/:id pipeline-success gate. Parity with
# github.test.sh (BL-005). Org mode sets push_access_level=0 (No one),
# approvals_required=1 via approval_rules (BL-152 migrated this off the
# deprecated approvals_before_merge PUT), and
# only_allow_merge_if_pipeline_succeeds=true (the latter added by audit
# code-host-gitlab-2 — CI parity with github.sh's required_status_checks).
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://gitlab.com/org/repo.git"
mock_cli_respond glab "api -X DELETE projects/org%2Frepo/protected_branches/main" 0 ""
mock_cli_respond glab "api -X POST projects/org%2Frepo/protected_branches" 0 '{"id":1,"name":"main"}'
mock_cli_respond glab "api -X POST projects/org%2Frepo/approval_rules" 0 '{"id":1,"name":"Require approval","approvals_required":1}'
mock_cli_respond glab "api -X PUT projects/org%2Frepo" 0 '{"only_allow_merge_if_pipeline_succeeds":true}'
set +e; host_configure_protection "main" "org"; code=$?; set -e
assert_exit_code 0 "$code" "org configure succeeds"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_configure_protection (org) PASSED"

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

# org mode requires approvals — fail case. Also fixture the project-settings
# GET so the new code-host-gitlab-2 CI-gate check has a deterministic response.
mock_cli_respond glab "api projects/u%2Fp/protected_branches/main" 0 '{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":40}]}'
mock_cli_respond glab "api projects/u%2Fp/approvals" 0 '{"approvals_before_merge":0}'
mock_cli_respond glab "api -X GET projects/u%2Fp" 0 '{"only_allow_merge_if_pipeline_succeeds":true}'
set +e; output=$(host_verify_protection "main" "org" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "org no approvals fails"
assert_contains "$output" "approval" "mentions approvals"

cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_verify_protection (personal pass / personal fail / org fail) PASSED"

# host_verify_protection — org pass. Parity with github.test.sh (BL-005).
# Org mode requires push_access_level=0 (No one) AND approvals_before_merge>=1
# AND force-push disabled (gitlab.sh:144-159).
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://gitlab.com/org/repo.git"
mock_cli_respond glab "api projects/org%2Frepo/protected_branches/main" 0 \
  '{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":0}]}'
mock_cli_respond glab "api projects/org%2Frepo/approvals" 0 '{"approvals_before_merge":1}'
# code-host-gitlab-2: pipeline-success gate must be enabled for org-mode
# verify to pass.
mock_cli_respond glab "api -X GET projects/org%2Frepo" 0 '{"only_allow_merge_if_pipeline_succeeds":true}'
set +e; host_verify_protection "main" "org"; code=$?; set -e
assert_exit_code 0 "$code" "org verify pass"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_verify_protection (org pass) PASSED"

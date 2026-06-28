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

# ════════════════════════════════════════════════════════════════════
# code-host-bitbucket-3 — Idempotency-scan failures must surface with a
# diagnostic that names the listing failure, not the confusing
# "failed to set <kind> restriction" downstream POST error. Pre-fix the
# GET response was captured with `2>/dev/null || echo '{}'`, so a 5xx /
# 4xx / non-JSON body silently degraded to "no existing restrictions"
# and the subsequent POST would fail with a downstream message lacking
# any cleanup context.
# ════════════════════════════════════════════════════════════════════

# T1 — GET returns non-JSON (e.g., "Unauthorized" plaintext); driver must
# fail early with a diagnostic naming the listing failure.
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/ws/repo.git"
# Listing GET returns non-JSON garbage; the driver must detect this and
# emit a diagnostic naming the listing-failure (not "failed to set …").
mock_cli_respond curl "branch-restrictions?pattern=main" 0 'Unauthorized: bad credentials'
# POST fixture is intentionally absent so we know we never got past
# the listing step (if we did, the unmatched-fixture stub exits 127).
set +e; output=$(host_configure_protection "main" "personal" 2>&1); code=$?; set -e
assert_exit_code 2 "$code" "non-JSON GET surfaces failure"
assert_contains "$output" "could not list existing restrictions" "diagnostic names listing failure"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_configure_protection (non-JSON GET surfaces failure) PASSED"

# T2 — DELETE failure with SOIF_DEBUG=1 surfaces the buffered diagnostic.
# Capture details: list returns one existing restriction; DELETE fails;
# under SOIF_DEBUG the operator sees which leftover blocked creation.
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
export SOIF_DEBUG=1
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://bitbucket.org/ws/repo.git"
# Listing returns one existing restriction id=99 (to be deleted).
mock_cli_respond curl "branch-restrictions?pattern=main" 0 \
  '{"values":[{"id":99,"kind":"force","pattern":"main"}]}'
# DELETE fails (non-zero exit + a body); driver should buffer + surface
# the failure under SOIF_DEBUG before attempting POSTs.
mock_cli_respond curl "-X DELETE" 22 'HTTP 500: server error deleting restriction 99'
# POSTs succeed (we only care about the DELETE diagnostic surfacing).
mock_cli_respond curl "-X POST" 0 '{"id":1}'
set +e; output=$(host_configure_protection "main" "personal" 2>&1); code=$?; set -e
# Driver may still succeed if the POST works despite leftover delete fail,
# but SOIF_DEBUG must surface the delete-failure diagnostic.
assert_contains "$output" "restriction 99" "SOIF_DEBUG surfaces failing delete id"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE SOIF_DEBUG
echo "bitbucket.test.sh: host_configure_protection (SOIF_DEBUG surfaces DELETE failure) PASSED"

# ════════════════════════════════════════════════════════════════════
# code-host-bitbucket-4 — API token (Bearer) auth path. Atlassian is
# deprecating Bitbucket Cloud App Passwords; the driver must support
# BITBUCKET_API_TOKEN as a Bearer credential, with precedence over the
# legacy App Password. host_require_cli must accept any one credential.
# Use a custom curl stub that records its argv to a file so we can
# assert the auth flag without relying on response shape.
# ════════════════════════════════════════════════════════════════════

# T3 — API token only: curl uses Authorization: Bearer, not -u.
WORK=$(mktemp -d); cd "$WORK"
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bb-auth-stub-XXXXXX")
ARG_LOG="$STUB_DIR/curl.args"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Record every arg on a single line so the assertion can grep substrings.
printf '%s\n' "$*" >> "ARG_LOG_PATH"
# Drain stdin if piped.
if [ ! -t 0 ]; then cat >/dev/null 2>&1 || true; fi
# Emit a minimal JSON body so jq downstream stays happy.
echo '{"values":[]}'
exit 0
STUB
sed -i.bak "s|ARG_LOG_PATH|$ARG_LOG|" "$STUB_DIR/curl"; rm -f "$STUB_DIR/curl.bak"
chmod +x "$STUB_DIR/curl"
export PATH="$STUB_DIR:$OLD_PATH"
git init -q; git remote add origin "https://bitbucket.org/ws/repo.git"
unset BITBUCKET_APP_PASSWORD
export BITBUCKET_USER="testuser" BITBUCKET_API_TOKEN="api-token-abc" BITBUCKET_WORKSPACE="ws"
# Invoke a function that issues at least one curl call.
set +e; host_configure_protection "main" "personal" >/dev/null 2>&1; set -e
# Inspect: Bearer header present, -u flag absent.
recorded=$(cat "$ARG_LOG")
assert_contains "$recorded" "Authorization: Bearer api-token-abc" "API token uses Bearer header"
if [[ "$recorded" == *"-u testuser:"* ]]; then
  echo "ASSERT FAIL: -u user:pw form leaked when only BITBUCKET_API_TOKEN was set" >&2
  exit 1
fi
cd - >/dev/null; rm -rf "$WORK" "$STUB_DIR"
export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_API_TOKEN BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: API token uses Bearer (no -u) PASSED"

# T4 — App password only: legacy -u user:pw form still works.
WORK=$(mktemp -d); cd "$WORK"
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bb-auth-stub-XXXXXX")
ARG_LOG="$STUB_DIR/curl.args"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "ARG_LOG_PATH"
if [ ! -t 0 ]; then cat >/dev/null 2>&1 || true; fi
echo '{"values":[]}'
exit 0
STUB
sed -i.bak "s|ARG_LOG_PATH|$ARG_LOG|" "$STUB_DIR/curl"; rm -f "$STUB_DIR/curl.bak"
chmod +x "$STUB_DIR/curl"
export PATH="$STUB_DIR:$OLD_PATH"
git init -q; git remote add origin "https://bitbucket.org/ws/repo.git"
unset BITBUCKET_API_TOKEN
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
set +e; host_configure_protection "main" "personal" >/dev/null 2>&1; set -e
recorded=$(cat "$ARG_LOG")
assert_contains "$recorded" "-u testuser:testpass" "app password uses -u form"
if [[ "$recorded" == *"Authorization: Bearer"* ]]; then
  echo "ASSERT FAIL: Bearer header leaked when only BITBUCKET_APP_PASSWORD was set" >&2
  exit 1
fi
cd - >/dev/null; rm -rf "$WORK" "$STUB_DIR"
export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: App password uses -u (legacy) PASSED"

# T5 — host_require_cli accepts API token alone (no app password).
unset BITBUCKET_APP_PASSWORD
export BITBUCKET_USER="testuser" BITBUCKET_API_TOKEN="api-token-abc" BITBUCKET_WORKSPACE="ws"
set +e; host_require_cli; code=$?; set -e
assert_exit_code 0 "$code" "host_require_cli passes with API token only"
unset BITBUCKET_USER BITBUCKET_API_TOKEN BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_require_cli (API token only) PASSED"

# T6 — host_require_cli fails when no credential is set.
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_API_TOKEN
export BITBUCKET_WORKSPACE="ws"
set +e; output=$(host_require_cli 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "host_require_cli fails with no credential"
assert_contains "$output" "BITBUCKET_API_TOKEN" "guidance mentions API token path"
unset BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_require_cli (no credential fails + mentions token) PASSED"

# ════════════════════════════════════════════════════════════════════
# code-host-bitbucket-5 — Repo-create must include the project key when
# BITBUCKET_PROJECT_KEY is set (Bitbucket workspaces without a default
# project will 400 otherwise); when unset, payload preserves prior shape
# so workspaces with a default keep working.
# ════════════════════════════════════════════════════════════════════

# T7 — BITBUCKET_PROJECT_KEY set: payload contains project.key.
WORK=$(mktemp -d); cd "$WORK"
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bb-create-stub-XXXXXX")
BODY_LOG="$STUB_DIR/curl.body"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Capture the JSON body off stdin (host_create_repo pipes payload to
# `curl --data-binary @-`).
if [ ! -t 0 ]; then cat > "BODY_LOG_PATH" 2>/dev/null || true; fi
# Respond with a minimally-valid clone-links payload so the caller's
# `jq -r '.links.clone[]...'` doesn't crash.
cat <<'JSON'
{"links":{"clone":[{"name":"https","href":"https://bitbucket.org/ws/repo.git"}]}}
JSON
exit 0
STUB
sed -i.bak "s|BODY_LOG_PATH|$BODY_LOG|" "$STUB_DIR/curl"; rm -f "$STUB_DIR/curl.bak"
chmod +x "$STUB_DIR/curl"
export PATH="$STUB_DIR:$OLD_PATH"
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
export BITBUCKET_PROJECT_KEY="PROJ"
set +e; host_create_repo "repo" "private" >/dev/null 2>&1; set -e
body=$(cat "$BODY_LOG" 2>/dev/null || echo '')
# Assert project.key=PROJ appears in JSON body. Use jq for robust parsing.
proj_key=$(printf '%s' "$body" | jq -r '.project.key // empty')
assert_eq "PROJ" "$proj_key" "payload contains project.key when env set"
# Also assert is_private + scm still present.
is_priv=$(printf '%s' "$body" | jq -r '.is_private // empty')
assert_eq "true" "$is_priv" "is_private preserved"
cd - >/dev/null; rm -rf "$WORK" "$STUB_DIR"
export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE BITBUCKET_PROJECT_KEY
echo "bitbucket.test.sh: host_create_repo (project key included) PASSED"

# T8 — BITBUCKET_PROJECT_KEY unset: payload omits project (backwards-compat).
WORK=$(mktemp -d); cd "$WORK"
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bb-create-stub-XXXXXX")
BODY_LOG="$STUB_DIR/curl.body"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > "BODY_LOG_PATH" 2>/dev/null || true; fi
cat <<'JSON'
{"links":{"clone":[{"name":"https","href":"https://bitbucket.org/ws/repo.git"}]}}
JSON
exit 0
STUB
sed -i.bak "s|BODY_LOG_PATH|$BODY_LOG|" "$STUB_DIR/curl"; rm -f "$STUB_DIR/curl.bak"
chmod +x "$STUB_DIR/curl"
export PATH="$STUB_DIR:$OLD_PATH"
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass" BITBUCKET_WORKSPACE="ws"
unset BITBUCKET_PROJECT_KEY
set +e; host_create_repo "repo" "private" >/dev/null 2>&1; set -e
body=$(cat "$BODY_LOG" 2>/dev/null || echo '')
# project key must NOT be present.
proj_key=$(printf '%s' "$body" | jq -r '.project.key // "ABSENT"')
assert_eq "ABSENT" "$proj_key" "payload omits project.key when env unset"
cd - >/dev/null; rm -rf "$WORK" "$STUB_DIR"
export PATH="$OLD_PATH"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
echo "bitbucket.test.sh: host_create_repo (project key omitted) PASSED"

# T9 — host_require_cli guidance text mentions BITBUCKET_PROJECT_KEY.
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_API_TOKEN BITBUCKET_WORKSPACE
set +e; output=$(host_require_cli 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "no creds fails"
assert_contains "$output" "BITBUCKET_PROJECT_KEY" "guidance mentions project key env"
echo "bitbucket.test.sh: host_require_cli (mentions BITBUCKET_PROJECT_KEY) PASSED"

echo "bitbucket.test.sh: all tests PASSED"

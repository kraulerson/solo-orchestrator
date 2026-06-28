#!/usr/bin/env bash
# tests/host-drivers/e2e-init-bitbucket.test.sh — BL-003b bitbucket init.sh
# e2e with a mocked `curl` (Bitbucket Cloud has no first-party CLI; the
# driver shells out to curl directly). Sibling to:
#   tests/host-drivers/e2e-init.test.sh         (PR #59 — github / gh)
#   tests/host-drivers/e2e-init-gitlab.test.sh  (PR #61 — gitlab / glab)
#
# Same harness shape: env-var-parameterized stub on PATH, isolated
# gitconfig with pushInsteadOf redirecting fake bitbucket.org URLs to a
# local bare repo. The two harness differences vs the CLI siblings:
#
#   1) The bitbucket driver invokes curl 8 times across 4 host_*
#      functions, all of them through `_bb_curl` / `_bb_curl_no_body`
#      (scripts/host-drivers/bitbucket.sh:10-26). Those helpers pipe
#      `2>&1`, so the curl stub MUST NOT emit stderr on success — any
#      diagnostic text gets folded into `$resp` and crashes jq parsing
#      downstream. Stderr is gated by env-var exit codes only.
#
#   2) `host_configure_protection` GETs `/branch-restrictions?pattern=main`
#      to find existing restrictions for the idempotent DELETE
#      (bitbucket.sh:113), then `host_verify_protection` GETs the same
#      URL to confirm the new restrictions stuck (bitbucket.sh:148). The
#      same base URL is hit twice with different expected responses — the
#      first GET should return `{"values":[]}` (no prior restrictions),
#      the second should return the full set of restrictions matching the
#      mode. A $TMP-side counter file disambiguates without parsing curl
#      argv further.
#
# bitbucket also has no CLI prerequisite check beyond three env vars
# (BITBUCKET_USER, BITBUCKET_APP_PASSWORD, BITBUCKET_WORKSPACE — audit
# code-host-bitbucket-1), so the harness exports those before each run.
#
# Curl-stub method + URL dispatch (pattern order matters: explicit `-X`
# discriminators before bare GET fallback):
#   -X POST .../repositories/<ws>/<name>            → repo create
#   -X GET  .../branch-restrictions?pattern=main    → configure pre-DELETE
#                                                     or verify, by counter
#   -X DELETE .../branch-restrictions/<id>          → idempotent cleanup
#   -X POST .../branch-restrictions (force/delete)  → personal-mode rules
#   -X POST .../branch-restrictions (push/appr/blds)→ org-mode extras
#
# Per cycle 5 survey verifier: the GET handler MUST also be reachable when
# the driver does NOT pass `-X GET` explicitly (curl defaults to GET when
# no -X is given, but bitbucket.sh always passes `-X GET` via _bb_curl_no_body).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

cd /tmp

# ── Helpers ────────────────────────────────────────────────────────

# write_mock_curl DIR COUNTER_FILE — env-controlled curl stub:
#   MOCK_BB_REPO_CREATE_EXIT     — exit for POST /repositories/<ws>/<name> (default 0)
#   MOCK_BB_REPO_CREATE_ERR      — stderr (and body) emitted on failure
#   MOCK_BB_REPO_CREATE_BODY     — JSON body echoed on success (default has
#                                  links.clone[https].href = MOCK_BB_REPO_URL)
#   MOCK_BB_PROTECT_POST_EXIT    — exit for POST /branch-restrictions (default 0)
#   MOCK_BB_PROTECT_POST_ERR     — stderr emitted on failure
#   MOCK_BB_PROTECT_GET_JSON_CONFIGURE — JSON for the *first* /branch-
#                                  restrictions GET (configure pre-DELETE
#                                  scan); default `{"values":[]}`
#   MOCK_BB_PROTECT_GET_JSON_VERIFY    — JSON for the *second* GET (verify)
#                                  default `{"values":[]}` — tests must
#                                  set this per mode for verify to pass
#   COUNTER_FILE                 — path used to count /branch-restrictions
#                                  GET invocations (first = configure,
#                                  rest = verify).
#
# Stdin discipline: POST and any -X-with-body must drain stdin
# (`cat >/dev/null`) because the driver pipes the JSON payload in via
# `echo "$payload" | _bb_curl POST URL`. Skipping the drain leaves bytes
# in the pipe; the next subprocess inherits SIGPIPE the next time the
# producer tries to write — flaky in pathological cases.
#
# Stderr discipline: _bb_curl uses `curl ... 2>&1` so the caller sees
# stdout+stderr merged. Any stderr-on-success would be folded into $resp
# and parsed by jq → invalid-JSON crash on the success path. Stub only
# writes to stderr inside the gated `if [ "$rc" -ne 0 ]` arms.
write_mock_curl() {
  local dir="$1" counter="$2"
  mkdir -p "$dir"
  cat > "$dir/curl" <<STUB_EOF
#!/usr/bin/env bash
# Counter file injected at stub-write time so per-scenario teardown can
# blow it away with the rest of \$TMP.
COUNTER='$counter'
STUB_EOF
  cat >> "$dir/curl" <<'STUB_EOF'
# Concatenated argv string for case-match. _bb_curl always passes
# -X METHOD; _bb_curl_no_body too. So matching on `-X METHOD` is reliable.
args="$*"

# Pattern order: most specific first. POST/DELETE arms drain stdin even
# on the failure path — driver always pipes a payload to _bb_curl POST.
case "$args" in
  *"-X POST "*"/repositories/"*"/"*"branch-restrictions"*)
    # branch-restrictions POST (force/delete/push/approve/builds)
    cat >/dev/null
    rc="${MOCK_BB_PROTECT_POST_EXIT:-0}"
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "${MOCK_BB_PROTECT_POST_ERR:-mock curl: branch-restrictions POST failed}" >&2
      exit "$rc"
    fi
    # Echo a minimal restriction JSON on success — driver pipes to
    # `>/dev/null` so the exact shape doesn't matter, but emitting empty
    # is safer than trailing garbage.
    echo '{"id":1}'
    exit 0
    ;;
  *"-X POST "*"/repositories/"*)
    # Repo create — POST /repositories/<workspace>/<name>
    cat >/dev/null
    rc="${MOCK_BB_REPO_CREATE_EXIT:-0}"
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "${MOCK_BB_REPO_CREATE_ERR:-mock curl: repo create failed}" >&2
      exit "$rc"
    fi
    if [ -n "${MOCK_BB_REPO_CREATE_BODY:-}" ]; then
      printf '%s\n' "$MOCK_BB_REPO_CREATE_BODY"
    else
      url="${MOCK_BB_REPO_URL:-https://bitbucket.org/mock/mock.git}"
      # Bitbucket Cloud REST shape: .links.clone[] is an array of objects
      # with .name in {https, ssh}; driver picks name=="https".
      printf '{"links":{"clone":[{"name":"https","href":"%s"},{"name":"ssh","href":"git@bitbucket.org:mock.git"}]}}\n' "$url"
    fi
    exit 0
    ;;
  *"-X DELETE "*"/branch-restrictions/"*)
    # Idempotent restriction cleanup. Driver tolerates non-zero (>/dev/null
    # 2>&1), so no exit-code knob needed; just succeed silently.
    exit 0
    ;;
  *"-X GET "*"/branch-restrictions"*)
    # Two-callsite ambiguity: first GET = configure pre-DELETE scan;
    # subsequent GETs = verify. Counter file disambiguates.
    n=0
    if [ -f "$COUNTER" ]; then n=$(cat "$COUNTER"); fi
    n=$((n + 1))
    echo "$n" > "$COUNTER"
    if [ "$n" -eq 1 ]; then
      printf '%s\n' "${MOCK_BB_PROTECT_GET_JSON_CONFIGURE:-{\"values\":[]}}"
    else
      printf '%s\n' "${MOCK_BB_PROTECT_GET_JSON_VERIFY:-{\"values\":[]}}"
    fi
    exit 0
    ;;
  *)
    # Unrecognized — emit to stderr so a future driver change surfaces as
    # a test failure rather than silent jq garbage.
    echo "mock curl: unhandled invocation: $args" >&2
    exit 127
    ;;
esac
STUB_EOF
  chmod +x "$dir/curl"
}

# Identical isolation pattern to PR #59 / PR #61 — pushInsteadOf (NOT
# plain insteadOf) so `git remote get-url origin` still returns the
# bitbucket.org URL for _bb_parse_origin's case-match.
write_isolated_gitconfig() {
  local cfg="$1" bare_url="$2" repo_url="$3"
  cat > "$cfg" <<EOF
[user]
  email = e2e-test@solo-orchestrator.local
  name = e2e test
[init]
  defaultBranch = main
[url "$bare_url"]
  pushInsteadOf = $repo_url
[push]
  default = current
EOF
}

# scenario_setup REPO_URL — same shape as the CLI siblings, plus a
# COUNTER file for the GET-disambiguation logic in the curl stub.
scenario_setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  MOCK_DIR="$TMP/bin"
  GITCONFIG="$TMP/gitconfig"
  BARE="$TMP/bare.git"
  COUNTER="$TMP/bb_get_counter"
  REPO_URL="$1"

  git init -q --bare "$BARE"
  write_mock_curl "$MOCK_DIR" "$COUNTER"
  write_isolated_gitconfig "$GITCONFIG" "file://$BARE" "$REPO_URL"

  export GIT_CONFIG_GLOBAL="$GITCONFIG"
  # Bitbucket driver requires all three vars (audit code-host-bitbucket-1).
  # Values are arbitrary — the mocked curl never validates them.
  export BITBUCKET_USER="e2e-test-user"
  export BITBUCKET_APP_PASSWORD="e2e-test-sentinel-never-valid"
  export BITBUCKET_WORKSPACE="test-ws"
  export PATH="$MOCK_DIR:$PATH"
  export MOCK_BB_REPO_URL="$REPO_URL"
}

scenario_teardown() {
  unset MOCK_BB_REPO_URL MOCK_BB_REPO_CREATE_EXIT MOCK_BB_REPO_CREATE_ERR
  unset MOCK_BB_REPO_CREATE_BODY
  unset MOCK_BB_PROTECT_POST_EXIT MOCK_BB_PROTECT_POST_ERR
  unset MOCK_BB_PROTECT_GET_JSON_CONFIGURE MOCK_BB_PROTECT_GET_JSON_VERIFY
  unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
  unset GIT_CONFIG_GLOBAL
  case "$PATH" in
    "$MOCK_DIR:"*) PATH="${PATH#"$MOCK_DIR:"}"; export PATH ;;
  esac
  rm -rf "$TMP"
}

# Personal-mode verify JSON: must satisfy host_verify_protection's
# checks for has_force >= 1 and has_delete >= 1 (bitbucket.sh:153-154,
# 160-161). values[] selects on .kind.
PROTECT_JSON_PERSONAL='{"values":[{"id":1,"kind":"force","pattern":"main"},{"id":2,"kind":"delete","pattern":"main"}]}'

# Org-mode verify JSON: personal + push + require_approvals_to_merge
# (value >= 1) + require_passing_builds_to_merge (value >= 1) — see
# bitbucket.sh:155-157, 163-166 (org mode requires all five kinds).
PROTECT_JSON_ORG='{"values":[{"id":1,"kind":"force","pattern":"main"},{"id":2,"kind":"delete","pattern":"main"},{"id":3,"kind":"push","pattern":"main"},{"id":4,"kind":"require_approvals_to_merge","pattern":"main","value":1},{"id":5,"kind":"require_passing_builds_to_merge","pattern":"main","value":1}]}'

run_init_e2e() {
  local pname="$1" deployment="$2"; shift 2
  ( cd "$TMP" && bash "$INIT" --non-interactive \
      --project "$pname" \
      --project-dir "$PROJ" \
      --platform web \
      --language javascript \
      --track light \
      --deployment "$deployment" \
      --git-host bitbucket \
      --visibility private \
      "$@" >"$TMP/init.log" 2>&1 ) || return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Success paths (T1 personal, T2 org) ==="
# ════════════════════════════════════════════════════════════════════

# T1 mirrors github+gitlab e2e T1: full success through
# host_verify_protection. Asserts manifest fields, process-state steps,
# origin URL, clean tree, two commits (chore-init + chore-finalize).
echo "T1: bitbucket + personal/strict full success"
scenario_setup "https://bitbucket.org/test-ws/personal-success.git"
export MOCK_BB_PROTECT_GET_JSON_VERIFY="$PROTECT_JSON_PERSONAL"
run_init_e2e personal-success personal
rc=$?
host=$( jq -r '.host // ""'        "$PROJ/.claude/manifest.json" 2>/dev/null )
mode=$( jq -r '.mode // ""'        "$PROJ/.claude/manifest.json" 2>/dev/null )
url=$(  jq -r '.remote_url // ""'  "$PROJ/.claude/manifest.json" 2>/dev/null )
steps=$( jq -r '.phase2_init.steps_completed | sort | join(",")' "$PROJ/.claude/process-state.json" 2>/dev/null )
origin=$( cd "$PROJ" && git remote get-url origin 2>/dev/null )
dirty=$( cd "$PROJ" && git status --porcelain 2>/dev/null )
commit_count=$( cd "$PROJ" && git rev-list --count HEAD 2>/dev/null )
if [ "$rc" = "0" ] \
   && [ "$host" = "bitbucket" ] && [ "$mode" = "personal" ] \
   && [ "$url" = "$REPO_URL" ] \
   && [ "$steps" = "branch_protection_configured,remote_repo_created" ] \
   && [ "$origin" = "$REPO_URL" ] \
   && [ -z "$dirty" ] \
   && [ "$commit_count" = "2" ]; then
  pass "T1: full success — manifest, steps, origin, clean tree, 2 commits"
else
  fail_ "T1" "rc=$rc host=$host mode=$mode url=$url steps=$steps origin=$origin dirty='$dirty' commits=$commit_count log:$(tail -8 "$TMP/init.log")"
fi
scenario_teardown

# T2: org/strict success — host_configure_protection POSTs 5 restriction
# kinds total (force, delete, push, require_approvals_to_merge,
# require_passing_builds_to_merge); host_verify_protection asserts the
# org-mode response shape (PROTECT_JSON_ORG).
echo "T2: bitbucket + org/strict full success"
scenario_setup "https://bitbucket.org/test-ws/org-success.git"
export MOCK_BB_PROTECT_GET_JSON_VERIFY="$PROTECT_JSON_ORG"
run_init_e2e org-success organizational --gov-mode production
rc=$?
mode=$( jq -r '.mode // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
url=$(  jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
steps=$( jq -r '.phase2_init.steps_completed | sort | join(",")' "$PROJ/.claude/process-state.json" 2>/dev/null )
dirty=$( cd "$PROJ" && git status --porcelain 2>/dev/null )
if [ "$rc" = "0" ] && [ "$mode" = "org" ] && [ "$url" = "$REPO_URL" ] \
   && [ "$steps" = "branch_protection_configured,remote_repo_created" ] \
   && [ -z "$dirty" ]; then
  pass "T2: org full success — mode=org, manifest+steps+clean tree"
else
  fail_ "T2" "rc=$rc mode=$mode url=$url steps=$steps dirty='$dirty' log:$(tail -8 "$TMP/init.log")"
fi
scenario_teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Failure paths (T3 push, T4 repo-exists, T5 protection 403) ==="
# ════════════════════════════════════════════════════════════════════

# T3: push fails (insteadOf points to a non-existent bare repo). init.sh's
# U-B contract: warn + continue, NOT abort (same as github/gitlab T3).
echo "T3: curl repo create succeeds but git push fails (no bare repo)"
TMP=$(mktemp -d)
PROJ="$TMP/proj"
MOCK_DIR="$TMP/bin"
GITCONFIG="$TMP/gitconfig"
COUNTER="$TMP/bb_get_counter"
REPO_URL="https://bitbucket.org/test-ws/push-fail.git"
write_mock_curl "$MOCK_DIR" "$COUNTER"
write_isolated_gitconfig "$GITCONFIG" "file://$TMP/never-created.git" "$REPO_URL"
export GIT_CONFIG_GLOBAL="$GITCONFIG"
export BITBUCKET_USER="e2e-test-user"
export BITBUCKET_APP_PASSWORD="e2e-test-sentinel"
export BITBUCKET_WORKSPACE="test-ws"
export PATH="$MOCK_DIR:$PATH"
export MOCK_BB_REPO_URL="$REPO_URL"
export MOCK_BB_PROTECT_GET_JSON_VERIFY="$PROTECT_JSON_PERSONAL"
run_init_e2e push-fail personal
rc=$?
warn_seen=no
grep -q "Remote setup did not complete cleanly" "$TMP/init.log" && warn_seen=yes
url=$( jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
host=$( jq -r '.host // ""'      "$PROJ/.claude/manifest.json" 2>/dev/null )
steps=$( jq -r '.phase2_init.steps_completed | length' "$PROJ/.claude/process-state.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$warn_seen" = "yes" ] \
   && [ "$host" = "bitbucket" ] && [ "$url" = "" ] \
   && [ "$steps" = "0" ]; then
  pass "T3: push failure → init.sh warns + continues; manifest.host set, remote_url empty"
else
  fail_ "T3" "rc=$rc warn_seen=$warn_seen host=$host url=$url steps=$steps log:$(tail -8 "$TMP/init.log")"
fi
unset MOCK_BB_REPO_URL MOCK_BB_PROTECT_GET_JSON_VERIFY GIT_CONFIG_GLOBAL
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD BITBUCKET_WORKSPACE
case "$PATH" in "$MOCK_DIR:"*) PATH="${PATH#"$MOCK_DIR:"}"; export PATH ;; esac
rm -rf "$TMP"

# T4: curl repo create POST fails with the realistic Bitbucket
# duplicate-slug error. host_create_repo returns 1 →
# create_and_protect_remote returns 1 at the repo-create step. No origin
# registered. Bitbucket Cloud REST shape: the error body is JSON with
# .error.message describing the conflict.
echo "T4: curl repo create fails (slug-already-exists scenario)"
scenario_setup "https://bitbucket.org/test-ws/exists.git"
export MOCK_BB_REPO_CREATE_EXIT=22  # curl --fail HTTP-error exit code
export MOCK_BB_REPO_CREATE_ERR='curl: (22) The requested URL returned error: 400
{"type":"error","error":{"message":"Repository with this Slug and Owner already exists."}}'
run_init_e2e exists personal
rc=$?
warn_seen=no
grep -q "Remote setup did not complete cleanly" "$TMP/init.log" && warn_seen=yes
host=$( jq -r '.host // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
url=$(  jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
origin_set=no
( cd "$PROJ" && git remote get-url origin >/dev/null 2>&1 ) && origin_set=yes
if [ "$rc" = "0" ] && [ "$warn_seen" = "yes" ] \
   && [ "$host" = "bitbucket" ] && [ "$url" = "" ] \
   && [ "$origin_set" = "no" ]; then
  pass "T4: slug-already-exists → warn + continue; no origin, manifest.host=bitbucket"
else
  fail_ "T4" "rc=$rc warn_seen=$warn_seen host=$host url=$url origin_set=$origin_set log:$(tail -8 "$TMP/init.log")"
fi
scenario_teardown

# T5: first branch-restrictions POST fails with HTTP 403 — likely cause
# is an App Password missing repository:admin scope. host_configure_
# protection returns 2 → create_and_protect_remote returns 1 → init.sh
# U-B contract: warn + continue. Origin IS registered (push succeeded
# before protection). Unlike github there is no "free-tier" branch for
# bitbucket (the free Bitbucket Cloud plan permits branch-restrictions
# API access), so the failure is unconditional → init.sh:2031 prints
# "Protection config failed", not the free-tier attestation path.
# manifest.remote_url stays "" (late write at init.sh:2054 unreached).
echo "T5: branch-restrictions POST fails with HTTP 403 (no free-tier branch on bitbucket)"
scenario_setup "https://bitbucket.org/test-ws/protect-fail.git"
export MOCK_BB_PROTECT_POST_EXIT=22  # curl --fail HTTP-error
export MOCK_BB_PROTECT_POST_ERR='curl: (22) The requested URL returned error: 403
{"type":"error","error":{"message":"You do not have permission to access this resource."}}'
export MOCK_BB_PROTECT_GET_JSON_VERIFY="$PROTECT_JSON_PERSONAL"
run_init_e2e protect-fail personal
rc=$?
warn_seen=no
grep -q "Remote setup did not complete cleanly" "$TMP/init.log" && warn_seen=yes
origin_set=no
( cd "$PROJ" && git remote get-url origin >/dev/null 2>&1 ) && origin_set=yes
url=$(  jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
host=$( jq -r '.host // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
steps=$( jq -r '.phase2_init.steps_completed | length' "$PROJ/.claude/process-state.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$warn_seen" = "yes" ] \
   && [ "$origin_set" = "yes" ] \
   && [ "$host" = "bitbucket" ] && [ "$url" = "" ] \
   && [ "$steps" = "0" ]; then
  pass "T5: protection 403 → warn + continue; origin registered, no phase2 steps"
else
  fail_ "T5" "rc=$rc warn_seen=$warn_seen origin_set=$origin_set host=$host url=$url steps=$steps log:$(tail -8 "$TMP/init.log")"
fi
scenario_teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

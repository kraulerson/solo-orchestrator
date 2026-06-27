#!/usr/bin/env bash
# tests/host-drivers/e2e-init-gitlab.test.sh — BL-003a gitlab init.sh e2e
# with mocked glab CLI. Sibling to e2e-init.test.sh (github, PR #59).
#
# Mirrors the github harness: env-var-parameterized glab stub on PATH,
# isolated gitconfig with pushInsteadOf redirecting fake gitlab.com URLs
# to a local bare repo, GLAB_TOKEN sentinel against accidental real-glab
# invocation. Drives init.sh --git-host gitlab end-to-end.
#
# gitlab driver (scripts/host-drivers/gitlab.sh) uses glab + a 5+ branch
# dispatch — distinct from github's 3-branch shape:
#   auth status                                  → exit 0
#   repo create NAME --private|--public          → echo MOCK_GL_REPO_URL
#   api -X DELETE .../protected_branches/main    → tolerated (|| true) before recreate
#   api -X POST .../protected_branches           → exit 0 with stdin payload
#   api -X PUT .../approvals                     → exit 0 (org mode only)
#   api projects/.../protected_branches/main     → GET, echo MOCK_GL_PROTECT_JSON
#   api projects/.../approvals                   → GET (org), echo MOCK_GL_APPROVALS_JSON
#
# Pattern-match order matters: `-X DELETE/POST/PUT` cases must come before
# the bare-`api` GET fallback (all share the `/protected_branches` URL
# substring). gitlab REST v4 also requires the project path URL-encoded
# (`owner%2Frepo`) per _gitlab_parse_origin — the stub regexes accept
# either raw or encoded forms.
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

# write_mock_glab DIR — env-controlled glab stub:
#   MOCK_GL_REPO_URL             — URL echoed by `repo create`
#   MOCK_GL_REPO_CREATE_EXIT     — exit code for `repo create` (default 0)
#   MOCK_GL_REPO_CREATE_ERR      — stderr emitted on failure
#   MOCK_GL_PROTECT_POST_EXIT    — exit code for `api -X POST .../protected_branches` (default 0)
#   MOCK_GL_PROTECT_POST_ERR     — stderr emitted on failure
#   MOCK_GL_APPROVALS_PUT_EXIT   — exit code for `api -X PUT .../approvals` (default 0)
#   MOCK_GL_APPROVALS_PUT_ERR    — stderr emitted on failure
#   MOCK_GL_PROTECT_JSON         — JSON body echoed by `api .../protected_branches/main` GET
#   MOCK_GL_APPROVALS_JSON       — JSON body echoed by `api .../approvals` GET (org)
write_mock_glab() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/glab" <<'STUB_EOF'
#!/usr/bin/env bash
# Pattern order: explicit `-X METHOD` first, then bare `api` GET fallback.
# The /protected_branches URL is shared between DELETE/POST and GET; the
# `-X` discriminator disambiguates.
case "$*" in
  *"auth status"*|*"--version"*)
    exit 0
    ;;
  *"repo create "*)
    rc="${MOCK_GL_REPO_CREATE_EXIT:-0}"
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "${MOCK_GL_REPO_CREATE_ERR:-mock glab: repo create failed}" >&2
      exit "$rc"
    fi
    echo "${MOCK_GL_REPO_URL:-https://gitlab.com/mock/mock.git}"
    exit 0
    ;;
  *"api -X DELETE "*protected_branches*)
    # Driver tolerates non-zero (|| true) for idempotency. Always exit 0
    # in the success path; tests can override with MOCK_GL_DELETE_EXIT
    # if they need to probe a specific branch.
    exit "${MOCK_GL_DELETE_EXIT:-0}"
    ;;
  *"api -X POST "*protected_branches*)
    rc="${MOCK_GL_PROTECT_POST_EXIT:-0}"
    # Drain stdin payload — driver passes via `--input -` <<<json.
    cat >/dev/null
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "${MOCK_GL_PROTECT_POST_ERR:-mock glab: protected_branches POST failed}" >&2
      exit "$rc"
    fi
    exit 0
    ;;
  *"api -X PUT "*approvals*)
    rc="${MOCK_GL_APPROVALS_PUT_EXIT:-0}"
    cat >/dev/null
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "${MOCK_GL_APPROVALS_PUT_ERR:-mock glab: approvals PUT failed}" >&2
      exit "$rc"
    fi
    exit 0
    ;;
  *"api "*protected_branches*)
    # GET protected_branches/<branch>
    printf '%s\n' "${MOCK_GL_PROTECT_JSON:-{}}"
    exit 0
    ;;
  *"api "*approvals*)
    # GET approvals (org-mode verification)
    printf '%s\n' "${MOCK_GL_APPROVALS_JSON:-{}}"
    exit 0
    ;;
  *)
    echo "mock glab: unhandled invocation: $*" >&2
    exit 127
    ;;
esac
STUB_EOF
  chmod +x "$dir/glab"
}

# Same isolation pattern as the github harness (PR #59). pushInsteadOf
# (NOT plain insteadOf) keeps origin readable as a gitlab.com URL while
# redirecting only push operations to a local bare repo.
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

scenario_setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  MOCK_DIR="$TMP/bin"
  GITCONFIG="$TMP/gitconfig"
  BARE="$TMP/bare.git"
  REPO_URL="$1"

  git init -q --bare "$BARE"
  write_mock_glab "$MOCK_DIR"
  write_isolated_gitconfig "$GITCONFIG" "file://$BARE" "$REPO_URL"

  export GIT_CONFIG_GLOBAL="$GITCONFIG"
  export GLAB_TOKEN="e2e-test-sentinel-never-valid"
  export PATH="$MOCK_DIR:$PATH"
  export MOCK_GL_REPO_URL="$REPO_URL"
}

scenario_teardown() {
  unset MOCK_GL_REPO_URL MOCK_GL_REPO_CREATE_EXIT MOCK_GL_REPO_CREATE_ERR
  unset MOCK_GL_PROTECT_POST_EXIT MOCK_GL_PROTECT_POST_ERR
  unset MOCK_GL_APPROVALS_PUT_EXIT MOCK_GL_APPROVALS_PUT_ERR
  unset MOCK_GL_PROTECT_JSON MOCK_GL_APPROVALS_JSON MOCK_GL_DELETE_EXIT
  unset GIT_CONFIG_GLOBAL GLAB_TOKEN
  case "$PATH" in
    "$MOCK_DIR:"*) PATH="${PATH#"$MOCK_DIR:"}"; export PATH ;;
  esac
  rm -rf "$TMP"
}

# Personal-mode protection-GET JSON: push_access_levels non-empty (any
# value satisfies host_verify_protection for personal mode); force-push
# disabled.
PROTECT_JSON_PERSONAL='{"name":"main","push_access_levels":[{"access_level":40}],"merge_access_levels":[{"access_level":30}],"allow_force_push":false}'

# Org-mode protection-GET JSON: push_access_level == 0 (audit code-host-
# gitlab-1 — org mode requires "No one" can push directly to protected
# branches; MR-only access).
PROTECT_JSON_ORG='{"name":"main","push_access_levels":[{"access_level":0}],"merge_access_levels":[{"access_level":40}],"allow_force_push":false}'

# Org-mode approvals JSON: approvals_before_merge >= 1.
APPROVALS_JSON_ORG='{"approvals_before_merge":1,"reset_approvals_on_push":true}'

run_init_e2e() {
  local pname="$1" deployment="$2"; shift 2
  ( cd "$TMP" && bash "$INIT" --non-interactive \
      --project "$pname" \
      --project-dir "$PROJ" \
      --platform web \
      --language javascript \
      --track light \
      --deployment "$deployment" \
      --git-host gitlab \
      --visibility private \
      "$@" >"$TMP/init.log" 2>&1 ) || return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Success paths (T1 personal, T2 org) ==="
# ════════════════════════════════════════════════════════════════════

# T1 mirrors github e2e T1: full success through host_verify_protection.
echo "T1: gitlab + personal/strict full success"
scenario_setup "https://gitlab.com/e2e-test/personal-success.git"
export MOCK_GL_PROTECT_JSON="$PROTECT_JSON_PERSONAL"
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
   && [ "$host" = "gitlab" ] && [ "$mode" = "personal" ] \
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

# T2: org/strict success — additional `api -X PUT approvals` call,
# host_verify_protection also GETs approvals (org-mode only).
echo "T2: gitlab + org/strict full success"
scenario_setup "https://gitlab.com/e2e-test/org-success.git"
export MOCK_GL_PROTECT_JSON="$PROTECT_JSON_ORG"
export MOCK_GL_APPROVALS_JSON="$APPROVALS_JSON_ORG"
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

# T3: push fails (insteadOf to a non-existent bare repo). init.sh's U-B
# contract: warn + continue, NOT abort. Mirror of github e2e T3.
echo "T3: glab repo create succeeds but git push fails (no bare repo)"
TMP=$(mktemp -d)
PROJ="$TMP/proj"
MOCK_DIR="$TMP/bin"
GITCONFIG="$TMP/gitconfig"
REPO_URL="https://gitlab.com/e2e-test/push-fail.git"
write_mock_glab "$MOCK_DIR"
write_isolated_gitconfig "$GITCONFIG" "file://$TMP/never-created.git" "$REPO_URL"
export GIT_CONFIG_GLOBAL="$GITCONFIG"
export GLAB_TOKEN="e2e-test-sentinel"
export PATH="$MOCK_DIR:$PATH"
export MOCK_GL_REPO_URL="$REPO_URL"
export MOCK_GL_PROTECT_JSON="$PROTECT_JSON_PERSONAL"
run_init_e2e push-fail personal
rc=$?
warn_seen=no
grep -q "Remote setup did not complete cleanly" "$TMP/init.log" && warn_seen=yes
url=$( jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
host=$( jq -r '.host // ""'      "$PROJ/.claude/manifest.json" 2>/dev/null )
steps=$( jq -r '.phase2_init.steps_completed | length' "$PROJ/.claude/process-state.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$warn_seen" = "yes" ] \
   && [ "$host" = "gitlab" ] && [ "$url" = "" ] \
   && [ "$steps" = "0" ]; then
  pass "T3: push failure → init.sh warns + continues; manifest.host set, remote_url empty"
else
  fail_ "T3" "rc=$rc warn_seen=$warn_seen host=$host url=$url steps=$steps log:$(tail -8 "$TMP/init.log")"
fi
unset MOCK_GL_REPO_URL MOCK_GL_PROTECT_JSON GIT_CONFIG_GLOBAL GLAB_TOKEN
case "$PATH" in "$MOCK_DIR:"*) PATH="${PATH#"$MOCK_DIR:"}"; export PATH ;; esac
rm -rf "$TMP"

# T4: glab repo create fails with realistic "name has already been taken"
# stderr. host_create_repo returns 1 → create_and_protect_remote returns
# 1 at the repo-create step. No origin registered.
echo "T4: glab repo create fails (name-already-taken scenario)"
scenario_setup "https://gitlab.com/e2e-test/exists.git"
export MOCK_GL_REPO_CREATE_EXIT=1
export MOCK_GL_REPO_CREATE_ERR='ERROR: 422 Unprocessable Entity — {"message":["has already been taken"]}'
run_init_e2e exists personal
rc=$?
warn_seen=no
grep -q "Remote setup did not complete cleanly" "$TMP/init.log" && warn_seen=yes
host=$( jq -r '.host // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
url=$(  jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
origin_set=no
( cd "$PROJ" && git remote get-url origin >/dev/null 2>&1 ) && origin_set=yes
if [ "$rc" = "0" ] && [ "$warn_seen" = "yes" ] \
   && [ "$host" = "gitlab" ] && [ "$url" = "" ] \
   && [ "$origin_set" = "no" ]; then
  pass "T4: name-already-taken → warn + continue; no origin, manifest.host=gitlab"
else
  fail_ "T4" "rc=$rc warn_seen=$warn_seen host=$host url=$url origin_set=$origin_set log:$(tail -8 "$TMP/init.log")"
fi
scenario_teardown

# T5: glab api -X POST protected_branches fails with a generic 403.
# Unlike github there is no free-tier branch (gitlab.com free tier
# permits the protected-branches API), so the driver always returns 2 →
# init.sh prints "Protection config failed" → warn + continue. Origin
# IS registered (push succeeded before protection); manifest remote_url
# stays "" (late write at init.sh:2054 didn't run).
echo "T5: protection POST fails with generic 403 (no free-tier branch on gitlab)"
scenario_setup "https://gitlab.com/e2e-test/protect-fail.git"
export MOCK_GL_PROTECT_POST_EXIT=1
export MOCK_GL_PROTECT_POST_ERR='ERROR: 403 Forbidden — protected_branches POST'
export MOCK_GL_PROTECT_JSON="$PROTECT_JSON_PERSONAL"
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
   && [ "$host" = "gitlab" ] && [ "$url" = "" ] \
   && [ "$steps" = "0" ]; then
  pass "T5: protection 403 → warn + continue; origin registered, no phase2 steps"
else
  fail_ "T5" "rc=$rc warn_seen=$warn_seen origin_set=$origin_set host=$host url=$url steps=$steps log:$(tail -8 "$TMP/init.log")"
fi
scenario_teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: gitlab-exit-3 cross-wiring documentation (latent bug) ==="
# ════════════════════════════════════════════════════════════════════

# T6 DOCUMENTS a latent cross-wiring bug surfaced by the cycle 5 survey.
# Gitlab's host_configure_protection returns exit 3 when the org-mode
# approvals PUT fails (lines 116-120 in scripts/host-drivers/gitlab.sh).
# init.sh line 2009 treats _hcp_rc=3 as the github-free-tier attestation
# fallback — a gitlab user lands in a flow whose stderr says
# "Branch protection unavailable on this repo (free-tier limit)" and
# "Upgrade to GitHub Pro" — wrong host name and wrong remediation.
#
# This test asserts the CURRENT (buggy) observable behavior:
#   - init.sh exit 0 (U-B contract: warn + continue)
#   - the GitHub-branded misleading message appears in the log
#
# When the cross-wiring is fixed (separate PR — see backlog), this test
# must be updated to assert the corrected gitlab-aware messaging.
echo "T6: org approvals PUT fails — DOCUMENTS gitlab-exit-3 cross-wiring at init.sh:2009"
scenario_setup "https://gitlab.com/e2e-test/approvals-fail.git"
export MOCK_GL_PROTECT_JSON="$PROTECT_JSON_ORG"
export MOCK_GL_APPROVALS_JSON="$APPROVALS_JSON_ORG"
export MOCK_GL_APPROVALS_PUT_EXIT=1
export MOCK_GL_APPROVALS_PUT_ERR='ERROR: 403 — approvals PUT requires premium tier'
# --branch-protection-attested provided so the non-interactive
# attestation prompt doesn't reject; we want to assert what init.sh
# DOES on this code path, not block on attestation UX.
run_init_e2e approvals-fail organizational --gov-mode production --branch-protection-attested
rc=$?
# Bug evidence: gitlab user sees GitHub-branded messaging.
github_branding_seen=no
grep -qE 'GitHub Pro|free-tier limit' "$TMP/init.log" && github_branding_seen=yes
if [ "$rc" = "0" ] && [ "$github_branding_seen" = "yes" ]; then
  pass "T6: gitlab exit-3 → GitHub-branded message (DOCUMENTED CROSS-WIRING BUG — see backlog)"
else
  fail_ "T6" "rc=$rc github_branding_seen=$github_branding_seen — cross-wiring not observed as expected; check init.sh:2009 + gitlab.sh:116-120 still match the surveyed shape. log:$(tail -10 "$TMP/init.log")"
fi
scenario_teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

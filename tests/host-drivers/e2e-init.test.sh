#!/usr/bin/env bash
# tests/host-drivers/e2e-init.test.sh — BL-003 end-to-end init.sh test
# with mocked github CLI.
#
# Pre-fix this PR there was no end-to-end test that drove init.sh
# create_and_protect_remote against a host. tests/host-drivers/github.test.sh
# exercised each driver function in isolation; tests/test-init-no-remote-
# creation.sh tested the --no-remote-creation BYPASS path; tests/test-
# github-free-tier-403.sh covered ONLY host_configure_protection's 403
# branch. The 167-line block at init.sh:1986-2052 (host_create_repo →
# host_register_remote → host_push_initial → host_configure_protection
# → host_verify_protection → manifest+process-state late writes) had
# zero integration coverage on the success path.
#
# This test establishes the e2e mocked-CLI sequencing harness for github.
# gitlab + bitbucket follow as BL-003a + BL-003b in a later cycle.
#
# Mechanics:
#   - A scenario-parameterized `gh` stub on PATH responds to:
#       auth status / --version    → exit 0
#       repo create NAME --vis     → echo MOCK_GH_REPO_URL or fail per env
#       api -X PUT .../protection  → exit 0 or fail per env (with optional
#                                    stderr to trigger the free-tier branch)
#       api .../protection (GET)   → echo MOCK_GH_PROTECT_JSON
#   - GIT_CONFIG_GLOBAL points to a per-test gitconfig with a url.<file>
#     .insteadOf rule that redirects MOCK_GH_REPO_URL → file:///$TMP/bare.git
#     so git push hits a local bare repo instead of network. user.email +
#     user.name are also set there so chore-init commits succeed.
#   - GH_TOKEN is set to a sentinel value so any accidental real-gh
#     invocation (in case PATH ordering misbehaves) cannot authenticate
#     against real github.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Refuse to scaffold inside the framework repo.
cd /tmp

# ── Helpers ────────────────────────────────────────────────────────

# write_mock_gh DIR — writes a parameterized gh stub at DIR/gh.
# Behavior is controlled at invocation time via env vars:
#   MOCK_GH_REPO_URL         — URL to echo on `repo create`
#   MOCK_GH_REPO_CREATE_EXIT — exit code for `repo create` (default 0)
#   MOCK_GH_REPO_CREATE_ERR  — stderr emitted on `repo create` failure
#   MOCK_GH_PROTECT_PUT_EXIT — exit code for `api -X PUT .../protection`
#   MOCK_GH_PROTECT_PUT_ERR  — stderr emitted on protection PUT failure
#   MOCK_GH_PROTECT_JSON     — JSON body to echo for `api .../protection` GET
write_mock_gh() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# Pattern order matters: "api -X PUT" must match before "api ..." GET
# fallback (PUT also contains the substring "/protection").
case "$*" in
  *"auth status"*|*"--version"*)
    exit 0
    ;;
  *"repo create "*)
    rc="${MOCK_GH_REPO_CREATE_EXIT:-0}"
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "${MOCK_GH_REPO_CREATE_ERR:-mock gh: repo create failed}" >&2
      exit "$rc"
    fi
    echo "${MOCK_GH_REPO_URL:-https://github.com/mock-owner/mock-repo.git}"
    exit 0
    ;;
  *"api -X PUT "*protection*)
    rc="${MOCK_GH_PROTECT_PUT_EXIT:-0}"
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "${MOCK_GH_PROTECT_PUT_ERR:-mock gh: protection PUT failed}" >&2
      exit "$rc"
    fi
    exit 0
    ;;
  *"api "*protection*)
    # GET protection — runs after the host_configure_protection PUT.
    printf '%s\n' "${MOCK_GH_PROTECT_JSON:-{}}"
    exit 0
    ;;
  *)
    echo "mock gh: unhandled invocation: $*" >&2
    exit 127
    ;;
esac
STUB_EOF
  chmod +x "$dir/gh"
}

# write_isolated_gitconfig FILE BARE_REPO MOCK_GH_REPO_URL
# Creates a per-test gitconfig with user identity, init.defaultBranch=main,
# and an insteadOf rule that redirects MOCK_GH_REPO_URL to the local bare
# repo. Use as GIT_CONFIG_GLOBAL on the init.sh invocation so subsequent
# git operations inherit the rule.
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

# pushInsteadOf (not insteadOf) is the right rewrite scope here. Plain
# insteadOf rewrites at remote-add and fetch time too — so
# `git remote add origin <REPO_URL>` would store the bare URL, breaking
# _github_parse_origin (which only recognizes github.com URLs). With
# pushInsteadOf, origin stays as $REPO_URL for read-side operations and
# only git push gets redirected to the local bare repo.

# scenario_setup TMP REPO_URL — common per-scenario fixture:
#   $TMP/bare.git    bare repo so git push has a real target
#   $TMP/bin/gh      mock CLI
#   $TMP/gitconfig   isolated config with insteadOf rule
#   $TMP/proj        project directory init.sh will populate
# Exports MOCK_DIR, GIT_CONFIG_GLOBAL, GH_TOKEN, PATH so the caller can
# run init.sh directly.
scenario_setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  MOCK_DIR="$TMP/bin"
  GITCONFIG="$TMP/gitconfig"
  BARE="$TMP/bare.git"
  REPO_URL="$1"

  git init -q --bare "$BARE"
  write_mock_gh "$MOCK_DIR"
  write_isolated_gitconfig "$GITCONFIG" "file://$BARE" "$REPO_URL"

  export GIT_CONFIG_GLOBAL="$GITCONFIG"
  export GH_TOKEN="e2e-test-sentinel-never-valid"
  export PATH="$MOCK_DIR:$PATH"
  export MOCK_GH_REPO_URL="$REPO_URL"
}

scenario_teardown() {
  unset MOCK_GH_REPO_URL MOCK_GH_REPO_CREATE_EXIT MOCK_GH_REPO_CREATE_ERR
  unset MOCK_GH_PROTECT_PUT_EXIT MOCK_GH_PROTECT_PUT_ERR MOCK_GH_PROTECT_JSON
  unset GIT_CONFIG_GLOBAL GH_TOKEN
  # Restore PATH — the test harness above prepended $MOCK_DIR; remove it
  # by trimming the entry. Defensive: leaves PATH untouched if it doesn't
  # start with $MOCK_DIR.
  case "$PATH" in
    "$MOCK_DIR:"*) PATH="${PATH#"$MOCK_DIR:"}"; export PATH ;;
  esac
  rm -rf "$TMP"
}

# Personal-mode protection-GET JSON: enforces admins + disables force-push.
PROTECT_JSON_PERSONAL='{"required_status_checks":null,"enforce_admins":{"enabled":true},"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'

# Org-mode protection-GET JSON: personal + required reviewers (count >= 1) + status checks.
PROTECT_JSON_ORG='{"required_status_checks":{"strict":true,"contexts":["ci"]},"enforce_admins":{"enabled":true},"required_pull_request_reviews":{"dismiss_stale_reviews":true,"require_code_owner_reviews":false,"required_approving_review_count":1},"restrictions":null,"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'

# run_init_e2e PROJ_NAME DEPLOYMENT [extra-flags...]
# Runs init.sh non-interactively with --git-host github + --visibility
# private against the mocked CLI / isolated gitconfig set up by
# scenario_setup. Captures stdout+stderr into "$TMP/init.log".
run_init_e2e() {
  local pname="$1" deployment="$2"; shift 2
  ( cd "$TMP" && bash "$INIT" --non-interactive \
      --project "$pname" \
      --project-dir "$PROJ" \
      --platform web \
      --language javascript \
      --track light \
      --deployment "$deployment" \
      --git-host github \
      --visibility private \
      "$@" >"$TMP/init.log" 2>&1 ) || return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Success paths (T1 personal, T2 org) ==="
# ════════════════════════════════════════════════════════════════════

# T1: personal/strict, full success through host_verify_protection.
# Assertions: exit 0; manifest host+mode+remote_url set; process-state
# records both steps; origin remote registered; working tree clean
# (PR #54 invariant); two commits (chore-init + chore-finalize).
echo "T1: github + personal/strict full success"
scenario_setup "https://github.com/e2e-test/personal-success.git"
export MOCK_GH_PROTECT_JSON="$PROTECT_JSON_PERSONAL"
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
   && [ "$host" = "github" ] && [ "$mode" = "personal" ] \
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

# T2: organizational/strict full success. Org-mode protection requires
# required_approving_review_count >= 1 and status checks; PROTECT_JSON_ORG
# supplies both. --gov-mode production is required for --deployment
# organizational (otherwise init.sh non-interactive validation refuses).
echo "T2: github + org/strict full success"
scenario_setup "https://github.com/e2e-test/org-success.git"
export MOCK_GH_PROTECT_JSON="$PROTECT_JSON_ORG"
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

# T3: push fails (insteadOf points to a non-existent bare repo).
# init.sh's U-B contract (line 1858 wrapper) says push failure does NOT
# abort init — print warn, surface remediation, keep going. Working tree
# stays clean post-fix (finalize_init_commit is a no-op when nothing
# changed; only host_register_remote's .git/config edit happened, and
# .git/config is untracked).
echo "T3: gh repo create succeeds but git push fails (no bare repo)"
TMP=$(mktemp -d)
PROJ="$TMP/proj"
MOCK_DIR="$TMP/bin"
GITCONFIG="$TMP/gitconfig"
REPO_URL="https://github.com/e2e-test/push-fail.git"
write_mock_gh "$MOCK_DIR"
# Point insteadOf at a bare repo that doesn't exist — git push will fail.
write_isolated_gitconfig "$GITCONFIG" "file://$TMP/never-created.git" "$REPO_URL"
export GIT_CONFIG_GLOBAL="$GITCONFIG"
export GH_TOKEN="e2e-test-sentinel"
export PATH="$MOCK_DIR:$PATH"
export MOCK_GH_REPO_URL="$REPO_URL"
export MOCK_GH_PROTECT_JSON="$PROTECT_JSON_PERSONAL"
run_init_e2e push-fail personal
rc=$?
# init.sh's U-B contract: push failure is warn-and-continue, NOT abort.
warn_seen=no
grep -q "Remote setup did not complete cleanly" "$TMP/init.log" && warn_seen=yes
# host_register_remote ran before push, so origin is set, but the late
# manifest write at init.sh:2054 (host_configure_protection success) was
# never reached — manifest.remote_url stays as the prepare_initial_state
# seed value "".
url=$( jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
host=$( jq -r '.host // ""'      "$PROJ/.claude/manifest.json" 2>/dev/null )
steps=$( jq -r '.phase2_init.steps_completed | length' "$PROJ/.claude/process-state.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$warn_seen" = "yes" ] \
   && [ "$host" = "github" ] && [ "$url" = "" ] \
   && [ "$steps" = "0" ]; then
  pass "T3: push failure → init.sh warns + continues; manifest.host set, remote_url empty"
else
  fail_ "T3" "rc=$rc warn_seen=$warn_seen host=$host url=$url steps=$steps log:$(tail -8 "$TMP/init.log")"
fi
unset MOCK_GH_REPO_URL MOCK_GH_PROTECT_JSON GIT_CONFIG_GLOBAL GH_TOKEN
case "$PATH" in "$MOCK_DIR:"*) PATH="${PATH#"$MOCK_DIR:"}"; export PATH ;; esac
rm -rf "$TMP"

# T4: gh repo create fails (repo already exists). host_create_repo
# returns 1 → create_and_protect_remote prints "Repo creation failed"
# → returns 1. init.sh U-B contract: warn + continue. Nothing was
# committed to remote, no origin was registered.
echo "T4: gh repo create fails (repo-already-exists scenario)"
scenario_setup "https://github.com/e2e-test/exists.git"
export MOCK_GH_REPO_CREATE_EXIT=1
export MOCK_GH_REPO_CREATE_ERR='GraphQL: Name already exists on this account (createRepository)'
run_init_e2e exists personal
rc=$?
warn_seen=no
grep -q "Remote setup did not complete cleanly" "$TMP/init.log" && warn_seen=yes
host=$( jq -r '.host // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
url=$(  jq -r '.remote_url // ""' "$PROJ/.claude/manifest.json" 2>/dev/null )
origin_set=no
( cd "$PROJ" && git remote get-url origin >/dev/null 2>&1 ) && origin_set=yes
if [ "$rc" = "0" ] && [ "$warn_seen" = "yes" ] \
   && [ "$host" = "github" ] && [ "$url" = "" ] \
   && [ "$origin_set" = "no" ]; then
  pass "T4: repo-already-exists → warn + continue; no origin, manifest.host=github"
else
  fail_ "T4" "rc=$rc warn_seen=$warn_seen host=$host url=$url origin_set=$origin_set log:$(tail -8 "$TMP/init.log")"
fi
scenario_teardown

# T5: gh api -X PUT protection fails with a non-free-tier 403. The
# free-tier branch is gated by the substring 'Upgrade to GitHub Pro'
# in stderr (BL-002); without that substring, host_configure_protection
# returns 2 → create_and_protect_remote prints "Protection config
# failed" → returns 1. init.sh U-B contract: warn + continue. By the
# time this fires, gh repo create succeeded + push succeeded, so the
# origin remote IS registered, but the late manifest write at
# init.sh:2054 still didn't run — remote_url stays "".
echo "T5: protection PUT fails with generic 403 (NOT free-tier)"
scenario_setup "https://github.com/e2e-test/protect-fail.git"
export MOCK_GH_PROTECT_PUT_EXIT=1
export MOCK_GH_PROTECT_PUT_ERR='HTTP 403: Resource not accessible by integration (repos/.../branches/main/protection)'
export MOCK_GH_PROTECT_JSON="$PROTECT_JSON_PERSONAL"
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
   && [ "$host" = "github" ] && [ "$url" = "" ] \
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

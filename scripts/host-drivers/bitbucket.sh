#!/usr/bin/env bash
# scripts/host-drivers/bitbucket.sh — Bitbucket driver.
# Uses curl + Bitbucket Cloud REST API 2.0.
#
# Credentials (one of, in precedence order; audit code-host-bitbucket-4
# + PR #90 verifier BLOCK fix):
#   1. BITBUCKET_API_TOKEN + BITBUCKET_API_TOKEN_EMAIL — Bitbucket Cloud
#      API token. PREFERRED. Atlassian is sunsetting App Passwords for
#      Bitbucket Cloud in 2026; API tokens are the forward-compatible
#      replacement. Per Atlassian's official docs
#      (https://support.atlassian.com/bitbucket-cloud/docs/using-api-tokens/),
#      API tokens are sent as HTTP Basic auth with the Atlassian account
#      EMAIL as the username and the token as the password — Bearer is
#      reserved for OAuth 2.0 access tokens and will 401 here.
#   2. BITBUCKET_APP_PASSWORD + BITBUCKET_USER — legacy App Password
#      (sent as HTTP Basic `-u user:pw`). Still works today; will break
#      on Atlassian's enforcement date.
#
# Required for all paths:
#   • BITBUCKET_WORKSPACE — workspace slug
#
# Optional:
#   • BITBUCKET_PROJECT_KEY — workspace project key for repo create.
#     Required for workspaces without a default project (audit
#     code-host-bitbucket-5). When unset, behavior matches pre-2026
#     drivers (Bitbucket uses the workspace's default project, if any).

host_name() { echo "bitbucket"; }

_bb_api_base="https://api.bitbucket.org/2.0"

# Emit the curl auth flag tokens for the current credential state.
# Prints tokens one per line so the caller can read them into an array
# and pass them through to curl without eval and without losing
# whitespace inside the value. Two shapes, both HTTP Basic:
#   • API token (preferred):     -u $BITBUCKET_API_TOKEN_EMAIL:$BITBUCKET_API_TOKEN
#   • Legacy App Password:       -u $BITBUCKET_USER:$BITBUCKET_APP_PASSWORD
# Precedence: API token > App Password.
# Per Atlassian docs (PR #90 verifier fix), API tokens MUST be sent as
# HTTP Basic with the Atlassian account EMAIL as the username — Bearer
# is reserved for OAuth 2.0 access tokens and will 401 here.
_bb_auth_args() {
  if [ -n "${BITBUCKET_API_TOKEN:-}" ] && [ -n "${BITBUCKET_API_TOKEN_EMAIL:-}" ]; then
    printf -- '-u\n%s:%s\n' "$BITBUCKET_API_TOKEN_EMAIL" "$BITBUCKET_API_TOKEN"
  elif [ -n "${BITBUCKET_APP_PASSWORD:-}" ] && [ -n "${BITBUCKET_USER:-}" ]; then
    printf -- '-u\n%s:%s\n' "$BITBUCKET_USER" "$BITBUCKET_APP_PASSWORD"
  fi
}

# Belt-and-braces: if host_require_cli was somehow bypassed (e.g. a
# caller that sources the driver directly), refuse to emit an
# unauthenticated request. PR #90 verifier NIT. Inlined at each call
# site rather than passed as a nameref so we stay compatible with the
# bash 3.2 that ships on macOS.

_bb_curl() {
  # $1: method, $2: url, stdin: body (optional)
  local method="$1" url="$2"
  local -a auth=()
  while IFS= read -r tok; do auth+=("$tok"); done < <(_bb_auth_args)
  if [ "${#auth[@]}" -eq 0 ]; then
    echo "bitbucket driver: no credentials in environment — set BITBUCKET_API_TOKEN + BITBUCKET_API_TOKEN_EMAIL (preferred) or BITBUCKET_USER + BITBUCKET_APP_PASSWORD (legacy)" >&2
    return 1
  fi
  curl -sSf "${auth[@]}" \
    -X "$method" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data-binary @- \
    "$url" 2>&1
}
_bb_curl_no_body() {
  local method="$1" url="$2"
  local -a auth=()
  while IFS= read -r tok; do auth+=("$tok"); done < <(_bb_auth_args)
  if [ "${#auth[@]}" -eq 0 ]; then
    echo "bitbucket driver: no credentials in environment — set BITBUCKET_API_TOKEN + BITBUCKET_API_TOKEN_EMAIL (preferred) or BITBUCKET_USER + BITBUCKET_APP_PASSWORD (legacy)" >&2
    return 1
  fi
  curl -sSf "${auth[@]}" \
    -X "$method" \
    -H "Accept: application/json" \
    "$url" 2>&1
}

host_require_cli() {
  # Need workspace + at least one credential PAIR. Both Atlassian auth
  # paths are HTTP Basic with two halves:
  #   • API token:    BITBUCKET_API_TOKEN_EMAIL (username) + BITBUCKET_API_TOKEN (password)
  #   • App Password: BITBUCKET_USER (username) + BITBUCKET_APP_PASSWORD (password)
  # A single half is not enough — emitting `-u :token` or `-u user:`
  # would 401 with no useful diagnostic at the call site.
  local has_token has_app
  has_token=0; has_app=0
  if [ -n "${BITBUCKET_API_TOKEN:-}" ] && [ -n "${BITBUCKET_API_TOKEN_EMAIL:-}" ]; then
    has_token=1
  fi
  if [ -n "${BITBUCKET_APP_PASSWORD:-}" ] && [ -n "${BITBUCKET_USER:-}" ]; then
    has_app=1
  fi
  if [ -z "${BITBUCKET_WORKSPACE:-}" ] || { [ "$has_token" -eq 0 ] && [ "$has_app" -eq 0 ]; }; then
    printf '%s\n' \
      'bitbucket driver: credentials not configured.' \
      '' \
      'Atlassian is deprecating Bitbucket Cloud App Passwords (sunset 2026); prefer an API token.' \
      'Create an API token at: https://id.atlassian.com/manage-profile/security/api-tokens' \
      '' \
      'Then export ONE of these pairs:' \
      '  # PREFERRED — API token (HTTP Basic; email is the Atlassian account email):' \
      '  export BITBUCKET_API_TOKEN_EMAIL="you@example.com"' \
      '  export BITBUCKET_API_TOKEN="your-api-token"' \
      '' \
      '  # …or the legacy App Password pair (sunset 2026):' \
      '  export BITBUCKET_USER="your-bitbucket-username"' \
      '  export BITBUCKET_APP_PASSWORD="your-app-password"' \
      '' \
      'Always export:' \
      '  export BITBUCKET_WORKSPACE="your-workspace-slug"' \
      '' \
      'BITBUCKET_WORKSPACE is the slug in your bitbucket.org/<workspace>/ URL.' \
      'For personal accounts it often (but not always) equals BITBUCKET_USER;' \
      'for org accounts it is the team slug, which differs from any single user.' \
      '' \
      'Optional — for workspaces without a default project (Bitbucket Cloud will' \
      'otherwise reject POST /repositories/<ws>/<repo> with HTTP 400):' \
      '  export BITBUCKET_PROJECT_KEY="PROJ"' \
      '' \
      'Consider adding those to your shell rc file (with mode 600 permissions).' >&2
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "bitbucket driver: curl not installed — required for Bitbucket API" >&2
    return 1
  fi
  return 0
}

host_create_repo() {
  local name="${1:?name required}"
  local visibility="${2:?visibility required}"
  local is_private
  case "$visibility" in
    private) is_private="true" ;;
    public)  is_private="false" ;;
    *) echo "visibility must be private|public, got '$visibility'" >&2; return 1 ;;
  esac
  # Audit code-host-bitbucket-1: BITBUCKET_WORKSPACE is sourced from a
  # single intentional place (env, validated by host_require_cli). The
  # earlier `:-$BITBUCKET_USER` fallback silently picked the wrong
  # workspace for org accounts where user != team slug.
  local workspace="$BITBUCKET_WORKSPACE"

  # Audit code-host-bitbucket-5: include the project key when
  # BITBUCKET_PROJECT_KEY is set. Bitbucket Cloud workspaces without
  # a default project will 400 the create call without this field;
  # workspaces with a default keep working when the env is unset
  # (preserved backwards-compatibility). Use jq -nc to build the JSON
  # so any unusual characters in the project key cannot break shell
  # quoting.
  local payload
  if [ -n "${BITBUCKET_PROJECT_KEY:-}" ]; then
    if ! payload=$(jq -nc --arg priv "$is_private" --arg key "$BITBUCKET_PROJECT_KEY" \
        '{scm:"git", is_private:($priv=="true"), project:{key:$key}}'); then
      echo "bitbucket driver: failed to encode repo-create payload (jq)" >&2
      return 1
    fi
  else
    payload="{\"scm\":\"git\",\"is_private\":$is_private}"
  fi
  local resp
  if ! resp=$(echo "$payload" | _bb_curl POST "$_bb_api_base/repositories/$workspace/$name"); then
    echo "bitbucket driver: repo create failed" >&2
    echo "$resp" >&2
    return 1
  fi
  echo "$resp" | jq -r '.links.clone[] | select(.name=="https") | .href'
}

host_register_remote() {
  local url="${1:?url required}"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$url"
  else
    git remote add origin "$url"
  fi
}

host_push_initial() {
  local branch="${1:-main}"
  git push -u origin "$branch"
}

_bb_parse_origin() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  local cleaned="${url%.git}"
  case "$cleaned" in
    https://bitbucket.org/*) echo "${cleaned#https://bitbucket.org/}" ;;
    git@bitbucket.org:*)     echo "${cleaned#git@bitbucket.org:}" ;;
    *) echo "_bb_parse_origin: not a Bitbucket URL: $url" >&2; return 1 ;;
  esac
}

host_configure_protection() {
  local branch="${1:?}"; local mode="${2:?}"
  local workspace_repo
  workspace_repo=$(_bb_parse_origin) || return 1

  # Delete existing restrictions on this branch (idempotency).
  #
  # Audit code-host-bitbucket-3: validate the GET response shape before
  # blindly proceeding to POSTs. Pre-fix the GET was captured with
  # `2>/dev/null || echo '{}'` — a 4xx/5xx body or any non-JSON response
  # silently degraded to "no existing restrictions", and the subsequent
  # POST would fail with a misleading "failed to set <kind> restriction"
  # message that hid the real (listing-failure) root cause.
  #
  # Two-step approach:
  #   (a) Validate the GET parses as JSON with a `.values` array. If not,
  #       emit a clear stderr diagnostic naming the failure and a body
  #       snippet, then return 2 BEFORE attempting any POST.
  #   (b) For each DELETE, capture stderr+stdout. If the DELETE fails,
  #       buffer the diagnostic; when SOIF_DEBUG is set OR a downstream
  #       POST later fails, emit the buffered diagnostic so the operator
  #       sees which leftover restriction blocked creation.
  local existing
  existing=$(_bb_curl_no_body GET "$_bb_api_base/repositories/$workspace_repo/branch-restrictions?pattern=$branch")
  local listing_rc=$?
  if [ "$listing_rc" -ne 0 ] || ! echo "$existing" | jq -e '.values | type == "array"' >/dev/null 2>&1; then
    local snippet
    snippet=$(printf '%s' "$existing" | head -c 200)
    printf 'bitbucket driver: could not list existing restrictions for %s on %s (rc=%s): %s\n' \
      "$branch" "$workspace_repo" "$listing_rc" "$snippet" >&2
    return 2
  fi
  local delete_diag=""
  local ids
  ids=$(echo "$existing" | jq -r '.values[].id // empty' 2>/dev/null)
  if [ -n "$ids" ]; then
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      local del_out
      if ! del_out=$(_bb_curl_no_body DELETE "$_bb_api_base/repositories/$workspace_repo/branch-restrictions/$id" 2>&1); then
        delete_diag="${delete_diag}bitbucket driver: failed to delete leftover restriction $id on $branch: $(printf '%s' "$del_out" | head -c 200)
"
      fi
    done <<< "$ids"
  fi
  if [ -n "$delete_diag" ] && [ -n "${SOIF_DEBUG:-}" ]; then
    printf '%s' "$delete_diag" >&2
  fi

  # Create restrictions: force-push off, delete off (both modes)
  local kind
  for kind in force delete; do
    local payload="{\"kind\":\"$kind\",\"pattern\":\"$branch\",\"users\":[],\"groups\":[]}"
    echo "$payload" | _bb_curl POST "$_bb_api_base/repositories/$workspace_repo/branch-restrictions" >/dev/null || {
      # PR #90 verifier MAJOR fix: flush the buffered delete-diagnostic
      # on POST failure too — operator running without SOIF_DEBUG must
      # still see which leftover restriction blocked creation. Before:
      # only the SOIF_DEBUG branch flushed; this path lost the timing
      # context permanently.
      [ -n "$delete_diag" ] && printf '%s' "$delete_diag" >&2
      echo "bitbucket driver: failed to set $kind restriction" >&2; return 2
    }
  done

  # Org mode: require approvals on PRs + block direct push + require
  # passing CI status checks before merge (audit code-host-bitbucket-2,
  # 2026-06: parity with github + gitlab org-mode policy that already
  # required green CI before merge).
  if [ "$mode" = "org" ]; then
    local payload_push='{"kind":"push","pattern":"'"$branch"'","users":[],"groups":[]}'
    local payload_approve='{"kind":"require_approvals_to_merge","pattern":"'"$branch"'","value":1,"users":[],"groups":[]}'
    local payload_builds='{"kind":"require_passing_builds_to_merge","pattern":"'"$branch"'","value":1,"users":[],"groups":[]}'
    echo "$payload_push"    | _bb_curl POST "$_bb_api_base/repositories/$workspace_repo/branch-restrictions" >/dev/null || return 2
    echo "$payload_approve" | _bb_curl POST "$_bb_api_base/repositories/$workspace_repo/branch-restrictions" >/dev/null || return 2
    echo "$payload_builds"  | _bb_curl POST "$_bb_api_base/repositories/$workspace_repo/branch-restrictions" >/dev/null || return 2
  fi
  return 0
}

host_verify_protection() {
  local branch="${1:?}"; local mode="${2:?}"
  local workspace_repo
  workspace_repo=$(_bb_parse_origin) || return 1

  local resp
  resp=$(_bb_curl_no_body GET "$_bb_api_base/repositories/$workspace_repo/branch-restrictions?pattern=$branch" 2>&1) || {
    echo "bitbucket driver: could not fetch restrictions for $workspace_repo#$branch" >&2; return 2
  }

  local has_force has_delete has_push has_approvals has_builds
  has_force=$(echo "$resp" | jq -r '[.values[] | select(.kind=="force")] | length')
  has_delete=$(echo "$resp" | jq -r '[.values[] | select(.kind=="delete")] | length')
  has_push=$(echo "$resp" | jq -r '[.values[] | select(.kind=="push")] | length')
  has_approvals=$(echo "$resp" | jq -r '[.values[] | select(.kind=="require_approvals_to_merge" and .value>=1)] | length')
  has_builds=$(echo "$resp" | jq -r '[.values[] | select(.kind=="require_passing_builds_to_merge" and .value>=1)] | length')

  local failures=""
  [ "$has_force" -eq 0 ]  && failures="${failures}force-push not restricted on $branch\n"
  [ "$has_delete" -eq 0 ] && failures="${failures}branch-delete not restricted\n"

  if [ "$mode" = "org" ]; then
    [ "$has_push" -eq 0 ]      && failures="${failures}push not restricted (org mode requires PR-only)\n"
    [ "$has_approvals" -eq 0 ] && failures="${failures}approvals not required on PRs (org mode requires at least 1)\n"
    [ "$has_builds" -eq 0 ]    && failures="${failures}passing CI builds not required for merge (org mode requires at least 1)\n"
  fi

  if [ -n "$failures" ]; then
    printf "bitbucket driver: protection verification failed for %s#%s (%s mode):\n" "$workspace_repo" "$branch" "$mode" >&2
    printf "  - %b" "$failures" >&2
    return 1
  fi
  return 0
}

#!/usr/bin/env bash
# scripts/host-drivers/bitbucket.sh — Bitbucket driver.
# Uses curl + Bitbucket Cloud REST API 2.0.
# Credentials via env: BITBUCKET_USER + BITBUCKET_APP_PASSWORD (App Password with
# repository:admin, project:admin, and pullrequest:write scopes).

host_name() { echo "bitbucket"; }

_bb_api_base="https://api.bitbucket.org/2.0"
_bb_curl() {
  # $1: method, $2: url, stdin: body (optional)
  local method="$1" url="$2"
  curl -sSf -u "${BITBUCKET_USER}:${BITBUCKET_APP_PASSWORD}" \
    -X "$method" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data-binary @- \
    "$url" 2>&1
}
_bb_curl_no_body() {
  local method="$1" url="$2"
  curl -sSf -u "${BITBUCKET_USER}:${BITBUCKET_APP_PASSWORD}" \
    -X "$method" \
    -H "Accept: application/json" \
    "$url" 2>&1
}

host_require_cli() {
  if [ -z "${BITBUCKET_USER:-}" ] || [ -z "${BITBUCKET_APP_PASSWORD:-}" ] || [ -z "${BITBUCKET_WORKSPACE:-}" ]; then
    printf '%s\n' \
      'bitbucket driver: credentials not configured.' \
      '' \
      'Bitbucket Cloud requires an App Password (not your account password).' \
      'Create one at: https://bitbucket.org/account/settings/app-passwords/' \
      'Grant these scopes: repository:admin, project:admin, pullrequest:write' \
      '' \
      'Then export:' \
      '  export BITBUCKET_USER="your-bitbucket-username"' \
      '  export BITBUCKET_APP_PASSWORD="your-app-password"' \
      '  export BITBUCKET_WORKSPACE="your-workspace-slug"' \
      '' \
      'BITBUCKET_WORKSPACE is the slug in your bitbucket.org/<workspace>/ URL.' \
      'For personal accounts it often (but not always) equals BITBUCKET_USER;' \
      'for org accounts it is the team slug, which differs from any single user.' \
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

  local payload="{\"scm\":\"git\",\"is_private\":$is_private}"
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
  local existing
  existing=$(_bb_curl_no_body GET "$_bb_api_base/repositories/$workspace_repo/branch-restrictions?pattern=$branch" 2>/dev/null || echo '{}')
  echo "$existing" | jq -r '.values[].id // empty' 2>/dev/null | while read -r id; do
    [ -n "$id" ] && _bb_curl_no_body DELETE "$_bb_api_base/repositories/$workspace_repo/branch-restrictions/$id" >/dev/null 2>&1
  done

  # Create restrictions: force-push off, delete off (both modes)
  local kind
  for kind in force delete; do
    local payload="{\"kind\":\"$kind\",\"pattern\":\"$branch\",\"users\":[],\"groups\":[]}"
    echo "$payload" | _bb_curl POST "$_bb_api_base/repositories/$workspace_repo/branch-restrictions" >/dev/null || {
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

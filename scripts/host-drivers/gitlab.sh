#!/usr/bin/env bash
# scripts/host-drivers/gitlab.sh — GitLab driver.
# Uses `glab` CLI for creation and authentication, GitLab REST API v4 for protection.
# Supports both gitlab.com and self-hosted instances.

host_name() { echo "gitlab"; }

host_require_cli() {
  if ! command -v glab >/dev/null 2>&1; then
    printf '%s\n' \
      'gitlab driver: `glab` CLI not installed.' \
      '' \
      'Install via one of:' \
      '  macOS:   brew install glab' \
      '  Linux:   https://gitlab.com/gitlab-org/cli/-/blob/main/docs/installation_options.md' \
      '  Windows: https://gitlab.com/gitlab-org/cli/-/blob/main/docs/installation_options.md#windows' \
      '' \
      'Then authenticate:' \
      '  glab auth login' \
      '' \
      '(Self-hosted instances: `glab auth login --hostname gitlab.your-company.com`)' >&2
    return 1
  fi
  if ! glab auth status >/dev/null 2>&1; then
    printf '%s\n' \
      'gitlab driver: `glab` installed but not authenticated.' \
      '' \
      'Authenticate with: glab auth login' >&2
    return 2
  fi
  return 0
}

# host_create_repo <name> <visibility>
host_create_repo() {
  local name="${1:?host_create_repo: name required}"
  local visibility="${2:?host_create_repo: visibility required}"
  case "$visibility" in
    private|public) ;;
    *) echo "host_create_repo: visibility must be private|public, got '$visibility'" >&2; return 1 ;;
  esac
  local result
  if ! result=$(glab repo create "$name" "--$visibility" 2>&1); then
    echo "$result" >&2; return 1
  fi
  echo "$result" | tail -n 1
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

# Parse namespace/project from origin URL (gitlab.com or self-hosted).
_gitlab_parse_origin() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || { echo "_gitlab_parse_origin: no origin" >&2; return 1; }
  local cleaned="${url%.git}"
  local path
  case "$cleaned" in
    https://*) path="${cleaned#https://}"; path="${path#*/}" ;;
    http://*)  path="${cleaned#http://}";  path="${path#*/}" ;;
    git@*:*)   path="${cleaned#git@*:}" ;;
    *) echo "_gitlab_parse_origin: unparseable: $url" >&2; return 1 ;;
  esac
  # URL-encode slashes for project ID
  echo "${path//\//%2F}"
}

host_configure_protection() {
  local branch="${1:?branch required}"
  local mode="${2:?mode required}"
  local project
  project=$(_gitlab_parse_origin) || return 1

  # GitLab protected branches: delete existing (if any) then recreate (idempotency).
  glab api -X DELETE "projects/$project/protected_branches/$branch" >/dev/null 2>&1 || true

  local push_access_level merge_access_level
  case "$mode" in
    personal)
      push_access_level=40
      merge_access_level=30
      ;;
    org)
      push_access_level=40
      merge_access_level=40
      ;;
    *)
      echo "host_configure_protection: mode must be personal|org, got '$mode'" >&2; return 1
      ;;
  esac

  local payload
  payload="{\"name\":\"$branch\",\"push_access_level\":$push_access_level,\"merge_access_level\":$merge_access_level,\"allow_force_push\":false,\"code_owner_approval_required\":false}"
  if ! glab api -X POST "projects/$project/protected_branches" --input - <<<"$payload" >/dev/null 2>&1; then
    echo "gitlab driver: failed to configure protection on $project#$branch ($mode mode)" >&2
    return 2
  fi

  # Org mode: also require approvals on MRs (separate API)
  if [ "$mode" = "org" ]; then
    glab api -X PUT "projects/$project/approvals" \
      --input - <<<'{"approvals_before_merge":1,"reset_approvals_on_push":true}' >/dev/null 2>&1 \
      || { echo "gitlab driver: protected branch set but approvals config failed" >&2; return 3; }
  fi
  return 0
}

host_verify_protection() {
  local branch="${1:?branch required}"
  local mode="${2:?mode required}"
  local project
  project=$(_gitlab_parse_origin) || return 1

  local resp
  if ! resp=$(glab api "projects/$project/protected_branches/$branch" 2>&1); then
    echo "gitlab driver: could not fetch protection for $project#$branch" >&2
    echo "$resp" >&2
    return 2
  fi

  local failures="" val
  val=$(echo "$resp" | jq -r '.allow_force_push // false')
  [ "$val" = "true" ] && failures="${failures}force-push allowed on $branch (should be disabled)\n"
  val=$(echo "$resp" | jq -r '.push_access_levels | length')
  [ "$val" = "0" ] || [ "$val" = "null" ] && failures="${failures}no push restriction on $branch\n"

  if [ "$mode" = "org" ]; then
    local aresp
    aresp=$(glab api "projects/$project/approvals" 2>/dev/null || echo '{}')
    val=$(echo "$aresp" | jq -r '.approvals_before_merge // 0')
    if [ "$val" = "0" ] || [ "$val" = "null" ]; then
      failures="${failures}approvals_before_merge is 0 (org mode requires at least 1)\n"
    fi
  fi

  if [ -n "$failures" ]; then
    printf "gitlab driver: protection verification failed for %s#%s (%s mode):\n" "$project" "$branch" "$mode" >&2
    printf "  - %b" "$failures" >&2
    return 1
  fi
  return 0
}

#!/usr/bin/env bash
# scripts/host-drivers/gitlab.sh — GitLab driver.
# Uses `glab` CLI for creation and authentication, GitLab REST API v4 for protection.
# Supports both gitlab.com and self-hosted instances.
#
# AUDIT-DRIVEN ERROR-CODE CONTRACT (host_configure_protection)
#   0  success
#   1  invalid argument / origin parse failure
#   2  protected_branches POST failed (generic — upstream message surfaced)
#   3  approvals PUT failed (generic — upstream message surfaced)
#   4  approvals PUT failed because the feature is Premium-only on gitlab.com
#      Free tier (matched by the response body). Operators can't fix the API
#      call from this host/tier combo; the BL-032 remediation message points
#      them at upgrade / self-hosted / attestation escape-hatch options.
#   5  project-settings PUT (only_allow_merge_if_pipeline_succeeds) failed
#      in org mode — upstream message surfaced.
#
# WHY GLAB STDERR IS CAPTURED (code-host-gitlab-3)
#   Pre-fix, both glab api calls used `>/dev/null 2>&1` and emitted only a
#   generic "failed to configure protection". Operators on gitlab.com Free
#   org mode would hit a Premium-feature-not-available 403 on the
#   approvals PUT and see no actionable detail. The github.sh driver
#   already captures stderr (BL-002 pattern, github.sh:117-138) to detect
#   free-tier 403s; this driver now mirrors that discipline.
#
# WHY THE CI PIPELINE-SUCCESS GATE IS NOW SET (code-host-gitlab-2)
#   Baseline §3.2 establishes the org protection bar as "1+ PR review + CI
#   status checks". github.sh sets required_status_checks in org mode and
#   verifies it; pre-fix gitlab.sh did neither, so org-mode verification
#   passed silently with no CI gate on main. The org branch now PUTs
#   `only_allow_merge_if_pipeline_succeeds:true` on projects/:id (paired
#   with `only_allow_merge_if_all_discussions_are_resolved:true`) and
#   host_verify_protection asserts the same flag.
#
# WHY BL-032 EXISTS (code-host-gitlab-8)
#   `projects/:id/approvals` with `approvals_before_merge>=1` is a
#   Premium-tier feature on gitlab.com — Free tier returns 403 with a
#   "not available on your plan" message. BL-032 in
#   solo-orchestrator-backlog.md mirrors BL-002 for GitHub free-tier:
#   document the gap, surface a clear remediation, and track the
#   attestation escape-hatch as future work. The driver's exit-4 branch
#   here surfaces the gap loudly with options, instead of returning the
#   bare exit-3 "approvals config failed" message.

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
      # Audit code-host-gitlab-1 (2026-06): org mode previously allowed
      # Maintainers (level 40) to push directly to protected branches,
      # bypassing MR review entirely. Per baseline §org-mode-protection,
      # org mode REQUIRES PR-only access; nobody pushes directly.
      # GitLab access level 0 = "No one"; merges still allowed for
      # Maintainers via the MR approval flow.
      push_access_level=0
      merge_access_level=40
      ;;
    *)
      echo "host_configure_protection: mode must be personal|org, got '$mode'" >&2; return 1
      ;;
  esac

  local payload
  payload="{\"name\":\"$branch\",\"push_access_level\":$push_access_level,\"merge_access_level\":$merge_access_level,\"allow_force_push\":false,\"code_owner_approval_required\":false}"

  # code-host-gitlab-3: capture stderr so failures surface the upstream
  # glab/API message instead of the pre-fix generic "failed to configure
  # protection". Mirrors the github.sh BL-002 pattern (lines 117-138).
  local glab_err
  if ! glab_err=$(glab api -X POST "projects/$project/protected_branches" --input - <<<"$payload" 2>&1 >/dev/null); then
    echo "gitlab driver: failed to configure protection on $project#$branch ($mode mode)" >&2
    [ -n "$glab_err" ] && printf '  %s\n' "$glab_err" >&2
    return 2
  fi

  # Org mode: also require approvals on MRs (separate API), the CI
  # pipeline-success gate, and discussion-resolution before merge.
  if [ "$mode" = "org" ]; then
    # code-host-gitlab-8: capture stderr from the approvals PUT so we can
    # detect the gitlab.com Free Premium-only failure mode (BL-032). On
    # Premium-only detection, return a dedicated exit code (4) with a
    # remediation message; on generic failure, surface the upstream
    # message and return 3.
    if ! glab_err=$(glab api -X PUT "projects/$project/approvals" \
                      --input - <<<'{"approvals_before_merge":1,"reset_approvals_on_push":true}' 2>&1 >/dev/null); then
      # Premium-only signals from gitlab.com Free responses. The exact
      # wording has shifted across GitLab releases (the API has used
      # "premium", "not available on your plan", "feature is not
      # available", "Ultimate" for some flows); match a broad union so
      # the detection is resilient to minor message tweaks.
      if echo "$glab_err" | grep -qiE 'premium|ultimate|not available on your plan|feature is not available|requires.*plan'; then
        printf '%s\n' \
          "gitlab driver: required-approvals API is unavailable on this project's plan." \
          "" \
          "  \`projects/:id/approvals\` with \`approvals_before_merge\` requires GitLab Premium" \
          "  on gitlab.com (Free tier rejects the PUT). The API responded:" \
          "" \
          "$(printf '    %s\n' "$glab_err")" \
          "" \
          "  Options (tracked as BL-032 in solo-orchestrator-backlog.md):" \
          "    1. Upgrade the project's namespace to GitLab Premium — unlocks required" \
          "       MR approvals via the API." \
          "    2. Self-host GitLab CE/EE with an appropriate license — same API surface" \
          "       without the gitlab.com tier gate." \
          "    3. Attest manually — accept that approvals are enforced by convention," \
          "       not the API. Re-run with --approvals-attested to record this once" \
          "       the BL-032 escape hatch lands (see backlog entry for status)." >&2
        return 4
      fi
      echo "gitlab driver: protected branch set but approvals config failed" >&2
      [ -n "$glab_err" ] && printf '  %s\n' "$glab_err" >&2
      return 3
    fi

    # code-host-gitlab-2: configure the CI pipeline-success gate +
    # discussion-resolution requirement on the project itself. Pre-fix,
    # org mode left main with no CI gate, contradicting baseline §3.2.
    # The github.sh equivalent is required_status_checks (github.sh:104).
    local settings_payload='{"only_allow_merge_if_pipeline_succeeds":true,"only_allow_merge_if_all_discussions_are_resolved":true}'
    if ! glab_err=$(glab api -X PUT "projects/$project" \
                      --input - <<<"$settings_payload" 2>&1 >/dev/null); then
      echo "gitlab driver: protected branch + approvals set but pipeline-success/settings PUT failed" >&2
      [ -n "$glab_err" ] && printf '  %s\n' "$glab_err" >&2
      return 5
    fi
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
    # Audit code-host-gitlab-1 (2026-06): org mode requires PR-only
    # access — assert push_access_level == 0 ("No one") rather than
    # accepting any non-empty array. Pre-fix, a project with
    # push_access_level=40 (Maintainers) passed verification.
    val=$(echo "$resp" | jq -r '[.push_access_levels[]?.access_level // 50] | min // 50')
    if [ "$val" != "0" ]; then
      failures="${failures}push_access_level=$val on $branch (org mode requires 0 = No one)\n"
    fi

    local aresp
    aresp=$(glab api "projects/$project/approvals" 2>/dev/null || echo '{}')
    val=$(echo "$aresp" | jq -r '.approvals_before_merge // 0')
    if [ "$val" = "0" ] || [ "$val" = "null" ]; then
      failures="${failures}approvals_before_merge is 0 (org mode requires at least 1)\n"
    fi

    # code-host-gitlab-2: parity with github.sh:174-175. Org mode requires
    # a CI status check on main per baseline §3.2 (1+ PR review + CI). On
    # GitLab this is `only_allow_merge_if_pipeline_succeeds` on the
    # project settings. A `false` (or missing) value means a maintainer
    # can merge without CI green — silent drift from the documented org
    # protection bar.
    #
    # Note the explicit `-X GET` — keeps the call shape distinct from the
    # other GETs (`projects/:id/approvals`, `projects/:id/protected_branches/*`)
    # for test fixtures that pattern-match args via substring (mock-cli
    # would otherwise see ambiguous prefixes).
    local presp
    presp=$(glab api -X GET "projects/$project" 2>/dev/null || echo '{}')
    val=$(echo "$presp" | jq -r '.only_allow_merge_if_pipeline_succeeds // false')
    if [ "$val" != "true" ]; then
      failures="${failures}pipeline-success gate not enforced (org mode requires CI status check)\n"
    fi
  fi

  if [ -n "$failures" ]; then
    printf "gitlab driver: protection verification failed for %s#%s (%s mode):\n" "$project" "$branch" "$mode" >&2
    printf "  - %b" "$failures" >&2
    return 1
  fi
  return 0
}

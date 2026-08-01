#!/usr/bin/env bash
# scripts/host-drivers/github.sh — GitHub driver.
# Uses `gh` CLI for creation and authentication, GitHub REST API for protection.
# Implements the solo-orchestrator host driver contract defined in spec
# docs/superpowers/specs/2026-04-21-host-aware-repo-gate-design.md.

# BL-204-ERROR-TRANSLATE: load the plain-language host-error translator. The
# path is derived from THIS file's location, so it resolves both in the
# framework repo and inside a scaffolded project (init.sh ships both files
# into scripts/lib + scripts/host-drivers). The fallback definition keeps the
# driver usable if the lib is ever missing — a driver must never die because
# an explanation is unavailable.
_HOST_ERRORS_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/host-errors.sh"
if [ -f "$_HOST_ERRORS_LIB" ]; then
  # shellcheck disable=SC1090
  . "$_HOST_ERRORS_LIB"
fi
command -v host_explain_error >/dev/null 2>&1 || host_explain_error() { [ -n "${1:-}" ] && printf '%s\n' "$1" >&2; return 0; }

host_name() { echo "github"; }

host_require_cli() {
  if ! command -v gh >/dev/null 2>&1; then
    printf '%s\n' \
      'github driver: `gh` CLI not installed.' \
      '' \
      'Install via one of:' \
      '  macOS:   brew install gh' \
      '  Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md' \
      '  Windows: https://github.com/cli/cli#installation' \
      '' \
      'Then authenticate:' \
      '  gh auth login' \
      '' \
      'Re-run whatever invoked this after install+auth completes.' >&2
    return 1
  fi
  # BL-204-ERROR-TRANSLATE: capture what `gh auth status` actually said. The
  # pre-fix code discarded it, so an EXPIRED token and a never-logged-in
  # machine produced byte-identical output — two different problems, one
  # message. The translator classifies the expired/revoked case; the
  # install/login guidance below still prints either way.
  local auth_err
  if ! auth_err=$(gh auth status 2>&1); then
    printf '%s\n' \
      'github driver: `gh` installed but not authenticated.' \
      '' >&2
    host_explain_error "$auth_err"
    printf '%s\n' \
      '' \
      'Authenticate with: gh auth login' \
      '' \
      'Re-run after auth completes.' >&2
    return 2
  fi
  return 0
}

# host_create_repo <name> <visibility>
# visibility: "private" | "public"
# stdout: HTTPS clone URL on success
# exit: 0 success; non-zero on failure (gh's error surfaced to stderr)
host_create_repo() {
  local name="${1:?host_create_repo: name required}"
  local visibility="${2:?host_create_repo: visibility required}"
  case "$visibility" in
    private|public) ;;
    *) echo "host_create_repo: visibility must be 'private' or 'public', got '$visibility'" >&2; return 1 ;;
  esac
  local result
  if ! result=$(gh repo create "$name" "--$visibility" 2>&1); then
    echo "github driver: could not create the repository '$name' on GitHub." >&2
    host_explain_error "$result"   # BL-204-ERROR-TRANSLATE
    return 1
  fi
  # gh prints the URL as the last line
  echo "$result" | tail -n 1
}

# host_register_remote <url>
# Idempotent — replaces existing origin or adds new.
host_register_remote() {
  local url="${1:?host_register_remote: url required}"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$url"
  else
    git remote add origin "$url"
  fi
}

# host_push_initial <branch>
# Initial push with upstream tracking.
host_push_initial() {
  local branch="${1:-main}"
  git push -u origin "$branch"
}

# Internal: parse owner/repo from origin URL.
# Supports: https://github.com/owner/repo(.git)? and git@github.com:owner/repo(.git)?
_github_parse_origin() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || { echo "_github_parse_origin: no origin" >&2; return 1; }
  local cleaned="${url%.git}"
  case "$cleaned" in
    https://github.com/*) echo "${cleaned#https://github.com/}" ;;
    git@github.com:*)     echo "${cleaned#git@github.com:}" ;;
    *) echo "_github_parse_origin: not a GitHub URL: $url" >&2; return 1 ;;
  esac
}

# host_configure_protection <branch> <mode>
# mode: "personal" | "org"
host_configure_protection() {
  local branch="${1:?host_configure_protection: branch required}"
  local mode="${2:?host_configure_protection: mode required}"
  local owner_repo
  owner_repo=$(_github_parse_origin) || return 1

  local payload
  case "$mode" in
    personal)
      # Force-push off, admins not exempt. No PR reviewer req (solo impossible anyway).
      payload='{"required_status_checks":null,"enforce_admins":true,"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}'
      ;;
    org)
      # All of personal + required reviewers + required status checks (CI) + dismiss stale.
      payload='{"required_status_checks":{"strict":true,"contexts":[]},"enforce_admins":true,"required_pull_request_reviews":{"dismiss_stale_reviews":true,"require_code_owner_reviews":false,"required_approving_review_count":1},"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}'
      ;;
    *)
      echo "host_configure_protection: mode must be 'personal' or 'org', got '$mode'" >&2
      return 1
      ;;
  esac

  # BL-002: capture gh stderr so we can detect free-tier 403s. The pattern
  # `Upgrade to GitHub Pro` (or `make this repository public`) is GitHub's
  # canonical message when branch protection is unavailable on a free-tier
  # personal account's private repo. Distinguish from generic 403s (e.g.
  # insufficient org permissions) which keep returning 2.
  local gh_err
  if ! gh_err=$(gh api -X PUT "repos/$owner_repo/branches/$branch/protection" --input - <<<"$payload" 2>&1); then
    if echo "$gh_err" | grep -qE 'Upgrade to GitHub Pro|make this repository public'; then
      printf '%s\n' \
        "github driver: branch protection is unavailable on this repo." \
        "" \
        "  GitHub free-tier personal accounts cannot enable branch protection on" \
        "  private repos. The API responded:" \
        "" \
        "$(printf '    %s\n' "$gh_err")" \
        "" \
        "  Options:" \
        "    1. Upgrade to GitHub Pro (\$4/mo) — unlocks protection on private repos." \
        "    2. Make this repo public — protection works on free-tier public repos." \
        "    3. Attest manually — accept that protection is enforced by convention," \
        "       not the API. Re-run with --branch-protection-attested to record this." >&2
      return 3
    fi
    echo "github driver: failed to configure protection on $owner_repo#$branch ($mode mode)" >&2
    host_explain_error "$gh_err"   # BL-204-ERROR-TRANSLATE
    return 2
  fi
  return 0
}

# host_verify_protection <branch> <mode>
# mode: "personal" | "org"
# Returns 0 if current protection rules meet the bar for the given mode.
# On failure, prints specific failing rule(s) to stderr and returns non-zero.
host_verify_protection() {
  local branch="${1:?host_verify_protection: branch required}"
  local mode="${2:?host_verify_protection: mode required}"
  local owner_repo
  owner_repo=$(_github_parse_origin) || return 1

  local resp
  if ! resp=$(gh api "repos/$owner_repo/branches/$branch/protection" 2>&1); then
    echo "github driver: could not fetch protection for $owner_repo#$branch" >&2
    echo "$resp" >&2
    return 2
  fi

  local failures="" val

  # Shared rules (personal + org)
  val=$(echo "$resp" | jq -r '.allow_force_pushes.enabled // false')
  [ "$val" = "true" ] && failures="${failures}main branch allows force-push (should be disabled)\n"

  val=$(echo "$resp" | jq -r '.enforce_admins.enabled // false')
  [ "$val" != "true" ] && failures="${failures}admins are exempt from protection rules (should not be exempt)\n"

  # Org-only rules
  if [ "$mode" = "org" ]; then
    val=$(echo "$resp" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
    if [ "$val" = "0" ] || [ "$val" = "null" ]; then
      failures="${failures}required_approving_review_count is 0 (org mode requires at least 1)\n"
    fi
    val=$(echo "$resp" | jq -r '.required_status_checks // empty')
    [ -z "$val" ] && failures="${failures}no status checks enforced (org mode requires CI status check)\n"
  fi

  if [ -n "$failures" ]; then
    printf "github driver: protection verification failed for %s#%s (%s mode):\n" "$owner_repo" "$branch" "$mode" >&2
    printf "  - %b" "$failures" >&2
    return 1
  fi
  return 0
}

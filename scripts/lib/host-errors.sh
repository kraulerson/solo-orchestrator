#!/usr/bin/env bash
# scripts/lib/host-errors.sh — BL-204-ERROR-TRANSLATE
#
# Plain-language translation of the host errors a first-time user actually
# hits. BL-204's audit found host jargon (403s, rate limits, SSO/SAML org
# authorization, expired auth) surfaced RAW to exactly the audience the
# framework exists for. This turns each common cause into ONE plain sentence
# plus ONE action, printed ABOVE the host's own words — which stay below,
# verbatim, because they are what a search engine or a support person needs.
#
# PRECEDENT AND PRECEDENCE. The shape is copied from the free-tier-403 block
# in scripts/host-drivers/github.sh (marker `# BL-002`). That block is NOT
# replaced and still classifies FIRST: it is more specific (it names a price
# and three concrete options) and it carries a distinct exit code (3) that
# init.sh routes to the attestation flow. This translator is the generic
# fallback underneath it.
#
# CONTRACT
#   host_explain_error <raw-host-output>
#     • writes to STDERR only
#     • always returns 0 (callers keep their own exit codes; several call it
#       from inside `if ! …` arms where a non-zero return would be read as
#       the operation's own status)
#     • emits at most ONE cause — the first arm that matches
#     • emits the raw text under a label whenever it is non-empty, whether or
#       not a cause matched. An unrecognised error is never given a
#       fabricated explanation.
#
# CLASSIFICATION ORDER IS LOAD-BEARING. SSO/SAML failures and rate limits are
# BOTH reported by GitHub as HTTP 403, and an expired token is reported as
# 403 by some hosts. Ordering specific-before-generic is what keeps a
# "authorize this token for your org" failure from being mis-explained as
# "you don't have permission" — a translation that would send the user down
# the wrong road with more confidence than the raw text did.
#
# PORTABILITY: every match uses a here-string, never `printf … | grep -q`.
# A producer piped into `grep -q` dies of SIGPIPE, and under `set -o pipefail`
# (which init.sh and every driver caller runs with) that turns a SUCCESSFUL
# match into a 141 the `if` reads as false.

host_explain_error() {
  local raw="${1:-}"
  local what="" action=""

  # R-BL204-4: `enabled or enforced` was carried here as a fragment of
  # GitHub's SAML sentence, but it is ordinary English that GitHub also uses
  # in abuse-detection and org-policy messages — a measured false positive
  # ("abuse detection is enabled or enforced" got an SSO runaround) that adds
  # zero true positives the SAML/SSO/single-sign-on tokens do not already
  # catch. Match on the NAMES of the mechanism, never on prose around it.
  if grep -qiE 'saml|(^|[^[:alnum:]])sso([^[:alnum:]]|$)|single[ -]sign[ -]on' <<<"$raw"; then
    what="Your organization makes you authorize a login before it will work on the organization's repositories. Your login is fine; it just has not been authorized there yet."
    # R-BL204-6: `gh auth login` does not prompt for an organization — the
    # org authorization happens on the browser page the login flow opens.
    # Describing a prompt that does not exist sends the user hunting for it.
    action="Open the authorization link in the raw text below and click Authorize, or re-run 'gh auth login' and grant access to the organization on the browser page that opens."
  elif grep -qiE 'rate limit|rate-limit|secondary rate|abuse detection|(^|[^0-9])429([^0-9]|$)|too many requests|retry-after' <<<"$raw"; then
    what="You made too many requests to the host in a short time, so it is turning you away for a while. Nothing is broken and nothing was lost."
    action="Wait a few minutes, then run the same command again."
  elif grep -qiE 'bad credentials|(^|[^0-9])401([^0-9]|$)|token[^.]*(expired|invalid|revoked)|(expired|invalid|revoked)[^.]*token|authentication (failed|required)|not logged in|requires authentication|re-authenticat' <<<"$raw"; then
    what="The saved login for this host is no longer valid — it expired, or it was revoked."
    action="Log in again: 'gh auth login' for GitHub, 'glab auth login' for GitLab, or re-create and re-export your Bitbucket API token."
  elif grep -qiE '(^|[^0-9])403([^0-9]|$)|permission|forbidden|not accessible|insufficient|denied' <<<"$raw"; then
    what="You are logged in, but this account is not allowed to do this here — usually because the repository belongs to an organization you do not have write access to."
    action="Ask an owner of that organization to grant you access, or create the repository under your own account instead."
  fi

  if [ -n "$what" ]; then
    :  # guard: keeps the block well-formed when the marked lines are excised
    printf '%s\n' "  What this means: $what" >&2   # BL-204-ERROR-TRANSLATE-EMIT
    printf '%s\n' "  What to do:      $action" >&2 # BL-204-ERROR-TRANSLATE-EMIT
    printf '\n' >&2                                # BL-204-ERROR-TRANSLATE-EMIT
  fi

  if [ -n "$raw" ]; then
    printf '%s\n' "  Raw response from the host (for reference):" >&2
    printf '%s\n' "$raw" | sed 's/^/    /' >&2
  fi

  return 0
}

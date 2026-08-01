#!/usr/bin/env bash
# tests/host-drivers/error-translate.test.sh — BL-204 jargon-translation tests.
#
# BL-204 (the "Plus:" item on the entry): host-error jargon — 403 permission,
# rate limits, SSO/SAML org authorization, expired auth — is surfaced RAW to
# exactly the users the framework exists for. Translate the common causes into
# ONE plain sentence + ONE action each, printed ABOVE the raw output, which
# stays below. The precedent is the free-tier-403 block in
# scripts/host-drivers/github.sh (marker `# BL-002`), which this deliberately
# does NOT replace: that block is more specific and still classifies first.
#
# The translator is `host_explain_error` in scripts/lib/host-errors.sh
# (marker `# BL-204-ERROR-TRANSLATE`). Every driver's create/auth/protection
# failure path routes its captured host output through it.
#
# Registered implicitly via tests/host-drivers/run-all.sh's `*.test.sh` glob
# (the same wiring github-free-tier-403.test.sh uses); the aggregator itself
# is registered in tests/full-project-test-suite.sh.
#
# HERMETIC: no network, no repo creation. `gh`, `glab` and `curl` are stubbed
# on PATH; the only git operations are `git init` + `git remote add` inside a
# mktemp dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/host-errors.sh"
GH_DRIVER="$REPO_ROOT/scripts/host-drivers/github.sh"
GL_DRIVER="$REPO_ROOT/scripts/host-drivers/gitlab.sh"
BB_DRIVER="$REPO_ROOT/scripts/host-drivers/bitbucket.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# The one phrase every translated block must carry. Tests assert on this
# rather than on the individual sentences so the wording can be tuned
# without a test rewrite, while the CONTRACT (a plain sentence + an action,
# above the raw text) stays pinned.
WHAT_ANCHOR="What this means:"
DO_ANCHOR="What to do:"
RAW_ANCHOR="Raw response from the host"

if [ ! -f "$LIB" ]; then
  echo "  [FAIL] scripts/lib/host-errors.sh not found — BL-204-ERROR-TRANSLATE unimplemented" >&2
  echo ""
  echo "== Total: 1 | Passed: 0 | Failed: 1 =="
  exit 1
fi

# shellcheck disable=SC1090
source "$LIB"

# explain <raw> — capture the translator's stderr.
explain() { host_explain_error "$1" 2>&1; }

# ── E1-E4: each of the four named causes gets a sentence + an action ──

e1_sso() {
  local out
  out=$(explain 'HTTP 403: Although you appear to have the correct authorization credentials, the `acme-corp` organization has enabled or enforced SAML SSO. To access this resource, you must use the full-repository-scope token and authorize it for this organization.')
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E1" "SSO/SAML text produced no plain-language translation: $out"; return ;;
  esac
  case "$out" in
    *"$DO_ANCHOR"*) ;;
    *) fail_ "E1" "SSO/SAML translation has no action line: $out"; return ;;
  esac
  # The sentence must be about ORG AUTHORIZATION, not generic permission.
  if ! grep -qi 'authoriz' <<<"$out"; then
    fail_ "E1" "SSO translation does not mention authorizing the login for the organization: $out"; return
  fi
  pass "E1: SAML/SSO org-authorization 403 gets a plain sentence + an action"
}

e2_rate_limit() {
  local out
  out=$(explain 'HTTP 403: API rate limit exceeded for user ID 12345. (https://api.github.com/user/repos)')
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E2" "rate-limit text produced no translation: $out"; return ;;
  esac
  if ! grep -qiE 'wait|again|later|minute' <<<"$out"; then
    fail_ "E2" "rate-limit action must tell the user to wait and retry: $out"; return
  fi
  pass "E2: rate limit gets a plain sentence + a wait-and-retry action"
}

e3_expired_auth() {
  local out
  out=$(explain 'HTTP 401: Bad credentials (https://api.github.com/user)')
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E3" "401/bad-credentials produced no translation: $out"; return ;;
  esac
  if ! grep -qiE 'log in|login|sign in|authenticate' <<<"$out"; then
    fail_ "E3" "expired-auth action must tell the user to log in again: $out"; return
  fi
  pass "E3: expired/invalid auth gets a plain sentence + a log-in-again action"
}

e4_permission_403() {
  local out
  out=$(explain 'HTTP 403: Resource not accessible by personal access token')
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E4" "generic 403 produced no translation: $out"; return ;;
  esac
  if ! grep -qiE 'allowed|permission|access' <<<"$out"; then
    fail_ "E4" "permission translation must say the account is not allowed to do this: $out"; return
  fi
  pass "E4: generic 403 permission failure gets a plain sentence + an action"
}

# ── E5: unknown text is NOT mistranslated — raw only, no invented cause ──

e5_unknown_is_raw_only() {
  local out
  out=$(explain 'something entirely unclassifiable happened on the far end')
  case "$out" in
    *"$WHAT_ANCHOR"*)
      fail_ "E5" "unknown host output was given a fabricated cause: $out"; return ;;
  esac
  case "$out" in
    *"something entirely unclassifiable happened"*) ;;
    *) fail_ "E5" "unknown host output must still be surfaced verbatim: $out"; return ;;
  esac
  pass "E5: unclassifiable output is passed through raw with no invented cause"
}

# ── E6: classification ORDER — SSO and rate-limit messages both contain
#        '403', and must not be swallowed by the generic-permission arm. ──

e6_order_sso_beats_403() {
  local out
  out=$(explain 'HTTP 403: SAML SSO enforcement — permission denied until you authorize the token for the organization')
  if ! grep -qi 'organization' <<<"$out"; then
    fail_ "E6a" "a 403 that is really an SSO failure was classified as generic permission: $out"; return
  fi
  out=$(explain 'HTTP 403: You have exceeded a secondary rate limit. Please wait a few minutes before you try again.')
  if ! grep -qiE 'too many requests|rate|short time' <<<"$out"; then
    fail_ "E6b" "a 403 that is really a rate limit was classified as generic permission: $out"; return
  fi
  pass "E6: SSO and rate-limit 403s outrank the generic-permission arm"
}

# ── E7: the raw text stays BELOW the translation, never above it ──

e7_raw_below_translation() {
  local out what_line raw_line
  out=$(explain 'HTTP 401: Bad credentials')
  # No `producer | grep -q` anywhere in this file: under `set -o pipefail` a
  # `grep -q` that exits early can SIGPIPE its producer into a 141 the caller
  # reads as "no match". These two use `grep -n` (reads to EOF, no early exit)
  # against a here-string, then slice the line numbers.
  what_line=$(grep -n "$WHAT_ANCHOR" <<<"$out" | sed -n '1s/:.*//p')
  raw_line=$(grep -n "Bad credentials" <<<"$out" | sed -n '$s/:.*//p')
  if [ -z "$what_line" ] || [ -z "$raw_line" ]; then
    fail_ "E7" "could not locate both the translation and the raw text: $out"; return
  fi
  if [ "$what_line" -ge "$raw_line" ]; then
    fail_ "E7" "translation must be printed ABOVE the raw output (what=$what_line raw=$raw_line)"; return
  fi
  case "$out" in
    *"$RAW_ANCHOR"*) ;;
    *) fail_ "E7" "the raw block must be labelled so the user knows what it is: $out"; return ;;
  esac
  pass "E7: plain-language block prints above a labelled raw block"
}

# ── E8-E10: the drivers actually ROUTE their failures through it ──

# stub_bin DIR NAME BODY — write an executable stub.
stub_bin() {
  local dir="$1" name="$2"
  mkdir -p "$dir"
  cat > "$dir/$name"
  chmod +x "$dir/$name"
}

e8_github_create_routes_through_translator() {
  local T; T=$(mktemp -d)
  stub_bin "$T/bin" gh <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"repo create"*)
    echo 'HTTP 403: Although you appear to have the correct authorization credentials, the acme organization has enabled or enforced SAML SSO.' >&2
    exit 1 ;;
  *) exit 0 ;;
esac
STUB
  local out
  out=$(
    cd "$T"
    PATH="$T/bin:$PATH"
    # shellcheck disable=SC1090
    source "$GH_DRIVER"
    host_create_repo demo private 2>&1 >/dev/null
  )
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E8" "github host_create_repo failure is still raw jargon: $out"; rm -rf "$T"; return ;;
  esac
  case "$out" in
    *"SAML SSO"*) ;;
    *) fail_ "E8" "github host_create_repo dropped the raw host text: $out"; rm -rf "$T"; return ;;
  esac
  pass "E8: github host_create_repo routes its failure through the translator"
  rm -rf "$T"
}

e9_github_auth_probe_routes_through_translator() {
  local T; T=$(mktemp -d)
  stub_bin "$T/bin" gh <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    echo 'error: The token in keyring is invalid or has expired. Try re-authenticating with: gh auth login' >&2
    exit 1 ;;
  *) exit 0 ;;
esac
STUB
  local out rc
  out=$(
    cd "$T"
    PATH="$T/bin:$PATH"
    # shellcheck disable=SC1090
    source "$GH_DRIVER"
    host_require_cli 2>&1 >/dev/null
  )
  rc=$(
    cd "$T"
    PATH="$T/bin:$PATH"
    # shellcheck disable=SC1090
    source "$GH_DRIVER"
    host_require_cli >/dev/null 2>&1
    echo $?
  )
  if [ "$rc" != "2" ]; then
    fail_ "E9" "host_require_cli must keep returning 2 for an unauthenticated gh (got $rc)"; rm -rf "$T"; return
  fi
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E9" "an expired gh token is still reported as raw jargon: $out"; rm -rf "$T"; return ;;
  esac
  pass "E9: github host_require_cli translates the expired/invalid-token case (rc=2 preserved)"
  rm -rf "$T"
}

e10_gitlab_create_routes_through_translator() {
  local T; T=$(mktemp -d)
  stub_bin "$T/bin" glab <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"repo create"*)
    echo '403 Forbidden: insufficient permissions to create a project in this namespace' >&2
    exit 1 ;;
  *) exit 0 ;;
esac
STUB
  local out
  out=$(
    cd "$T"
    PATH="$T/bin:$PATH"
    # shellcheck disable=SC1090
    source "$GL_DRIVER"
    host_create_repo demo private 2>&1 >/dev/null
  )
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E10" "gitlab host_create_repo failure is still raw jargon: $out"; rm -rf "$T"; return ;;
  esac
  case "$out" in
    *"insufficient permissions"*) ;;
    *) fail_ "E10" "gitlab host_create_repo dropped the raw host text: $out"; rm -rf "$T"; return ;;
  esac
  pass "E10: gitlab host_create_repo routes its failure through the translator"
  rm -rf "$T"
}

e11_bitbucket_create_routes_through_translator() {
  local T; T=$(mktemp -d)
  stub_bin "$T/bin" curl <<'STUB'
#!/usr/bin/env bash
echo 'curl: (22) The requested URL returned error: 401 Unauthorized — token expired' >&2
echo 'curl: (22) The requested URL returned error: 401 Unauthorized — token expired'
exit 22
STUB
  local out
  out=$(
    cd "$T"
    PATH="$T/bin:$PATH"
    export BITBUCKET_API_TOKEN=tok BITBUCKET_API_TOKEN_EMAIL=a@b.c BITBUCKET_WORKSPACE=ws
    # shellcheck disable=SC1090
    source "$BB_DRIVER"
    host_create_repo demo private 2>&1 >/dev/null
  )
  case "$out" in
    *"$WHAT_ANCHOR"*) ;;
    *) fail_ "E11" "bitbucket host_create_repo failure is still raw jargon: $out"; rm -rf "$T"; return ;;
  esac
  pass "E11: bitbucket host_create_repo routes its failure through the translator"
  rm -rf "$T"
}

# ── E12: the BL-002 free-tier block still classifies FIRST and returns 3 ──

e12_bl002_precedence_preserved() {
  local T; T=$(mktemp -d)
  stub_bin "$T/bin" gh <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"branches/"*"/protection"*)
    echo 'HTTP 403: Upgrade to GitHub Pro or make this repository public to enable this feature.' >&2
    exit 1 ;;
  *) exit 0 ;;
esac
STUB
  (
    cd "$T"
    git init -q
    git config user.email t@t.local
    git config user.name t
    git remote add origin https://github.com/test/repo.git
  ) >/dev/null 2>&1
  local rc out
  out=$(
    cd "$T"
    PATH="$T/bin:$PATH"
    # shellcheck disable=SC1090
    source "$GH_DRIVER"
    host_configure_protection main personal 2>&1 >/dev/null
    printf 'RC=%s' "$?"
  )
  rc=$(printf '%s' "$out" | sed -n 's/.*RC=\([0-9]*\)$/\1/p')
  if [ "$rc" != "3" ]; then
    fail_ "E12" "the BL-002 free-tier arm must still return 3 (got '$rc'): $out"; rm -rf "$T"; return
  fi
  case "$out" in
    *"GitHub Pro"*) ;;
    *) fail_ "E12" "the BL-002 remediation text was lost: $out"; rm -rf "$T"; return ;;
  esac
  pass "E12: BL-002 free-tier 403 still classifies first (exit 3, remediation intact)"
  rm -rf "$T"
}

# ── E13: mutation proof — excising the marked translation emit makes the
#        translator inert again while leaving the file runnable. ──

e13_mutation_translation_is_load_bearing() {
  local T; T=$(mktemp -d)
  local marks left
  marks=$(grep -c '# BL-204-ERROR-TRANSLATE-EMIT$' "$LIB" 2>/dev/null) || marks=0
  if [ "${marks:-0}" -lt 1 ]; then
    fail_ "E13" "no '# BL-204-ERROR-TRANSLATE-EMIT' marker in host-errors.sh — nothing to excise (mis-targeted)"
    rm -rf "$T"; return
  fi
  sed '/# BL-204-ERROR-TRANSLATE-EMIT$/d' "$LIB" > "$T/mut.sh"
  left=$(grep -c '# BL-204-ERROR-TRANSLATE-EMIT$' "$T/mut.sh" 2>/dev/null) || left=0
  if [ "${left:-0}" -ne 0 ]; then
    fail_ "E13" "excision left $left marker(s) — vacuous mutant"; rm -rf "$T"; return
  fi
  if ! bash -n "$T/mut.sh" 2>/dev/null; then
    fail_ "E13" "mutant has a syntax error — a broken mutant proves nothing"; rm -rf "$T"; return
  fi
  local mut_out
  mut_out=$( bash -c '
    set -uo pipefail
    . "$1"
    host_explain_error "HTTP 401: Bad credentials" 2>&1
  ' _ "$T/mut.sh" )
  case "$mut_out" in
    *"$WHAT_ANCHOR"*)
      fail_ "E13" "mutant still emits the translation — the marked line is not load-bearing: $mut_out"
      rm -rf "$T"; return ;;
  esac
  case "$mut_out" in
    *"Bad credentials"*) ;;
    *) fail_ "E13" "mutant no longer runs at all (raw text gone) — non-decisive mutation: $mut_out"; rm -rf "$T"; return ;;
  esac
  pass "E13: excising the marked emit makes the translator inert (mutation is decisive and non-vacuous)"
  rm -rf "$T"
}

echo "== tests/host-drivers/error-translate.test.sh (BL-204 jargon translation) =="
e1_sso
e2_rate_limit
e3_expired_auth
e4_permission_403
e5_unknown_is_raw_only
e6_order_sso_beats_403
e7_raw_below_translation
e8_github_create_routes_through_translator
e9_github_auth_probe_routes_through_translator
e10_gitlab_create_routes_through_translator
e11_bitbucket_create_routes_through_translator
e12_bl002_precedence_preserved
e13_mutation_translation_is_load_bearing

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

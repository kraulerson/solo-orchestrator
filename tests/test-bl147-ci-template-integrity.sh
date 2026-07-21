#!/usr/bin/env bash
# tests/test-bl147-ci-template-integrity.sh — the ONE shared content-pin
# suite over templates/pipelines/** (the PR-sweep remediation wave's shared
# asset). Each WP of the wave adds its cases here; WP-1 opens the file.
#
# WP-1 (BL-147 + BL-151): the emitted CI approval-log integrity steps were
# VACUOUS under every standard Actions checkout — `git diff origin/main...HEAD
# -- APPROVAL_LOG.md 2>/dev/null` dies `fatal: bad revision` on the default
# depth-1 clone (no origin/main ref), the `2>/dev/null` eats it, and the step
# PASSES on a tampered log. Parity hole: 7 of 10 GitHub language templates
# never got the steps at all. And gitleaks-action needs GITLEAKS_LICENSE for
# org accounts + fetch-depth 0 — neither was set (BL-151), so org-track
# generated projects got a failing/license-less secret-scan step.
#
# WP-1 CASES (all github CI templates unless noted):
#   (a) checkout step carries `fetch-depth: 0`
#   (b) every github CI template contains BOTH governance approval steps
#       (integrity + author verification) — all 10, not just python/ts/other
#   (c) no APPROVAL_LOG-touching line carries `2>/dev/null` (github + gitlab)
#   (d) the diff base is resolved explicitly (github.base_ref, loud-fail via
#       `git rev-parse --verify`) — never bare `origin/main...HEAD`
#   (e) no template uses `gitleaks/gitleaks-action`; every github CI template
#       runs the gitleaks CLI (`./gitleaks git`)
#   (f) gitlab twin of (c)/(d): the gitlab approval steps use the explicit
#       base + loud-fail and drop the silencer
#
# GRAMMAR: the template lists are derived MECHANICALLY (find), never
# hand-enumerated, guarded by a count floor (>=10 github CI files) so the
# suite cannot pass vacuously.
#
# REGISTRATION: content-pin only — no init.sh, not an aggregator -> BOTH the
# aggregator (tests/full-project-test-suite.sh) and the tests.yml unit list.
# Hermetic (reads tracked files only; no network, no git ops).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GH_DIR="$REPO_ROOT/templates/pipelines/ci/github"
GL_DIR="$REPO_ROOT/templates/pipelines/ci/gitlab"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Mechanically derived template lists (never hand-enumerated) ──────────────
GH_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && GH_FILES+=("$f")
done < <(find "$GH_DIR" -name '*.yml' | sort)

GL_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && GL_FILES+=("$f")
done < <(find "$GL_DIR" -name '*.yml' | sort)

GH_COUNT=${#GH_FILES[@]}
GL_COUNT=${#GL_FILES[@]}

# ── Vacuity guard: the count floors ─────────────────────────────────────────
echo "C0: mechanically derived template counts meet the vacuity floors"
if [ "$GH_COUNT" -ge 10 ]; then
  pass "C0-github-floor ($GH_COUNT github CI templates, floor 10)"
else
  fail_ "C0-github-floor" "found $GH_COUNT github CI templates, expected >=10 — list derivation is vacuous"
fi
if [ "$GL_COUNT" -ge 10 ]; then
  pass "C0-gitlab-floor ($GL_COUNT gitlab CI templates, floor 10)"
else
  fail_ "C0-gitlab-floor" "found $GL_COUNT gitlab CI templates, expected >=10 — list derivation is vacuous"
fi

# ── (a) checkout carries fetch-depth: 0 ─────────────────────────────────────
echo "Ca: every github CI template's checkout sets fetch-depth: 0"
miss=""
for f in "${GH_FILES[@]}"; do
  # the checkout step must have a `with:` carrying `fetch-depth: 0`
  if ! grep -Eq '^[[:space:]]+fetch-depth: 0$' "$f"; then
    miss="$miss ${f##*/}"
  fi
done
if [ -z "$miss" ]; then
  pass "Ca-fetch-depth (all $GH_COUNT github CI templates)"
else
  fail_ "Ca-fetch-depth" "missing 'fetch-depth: 0':$miss"
fi

# ── (b) both governance approval steps present in ALL github templates ──────
echo "Cb: every github CI template carries BOTH approval steps (integrity + author)"
miss_int=""
miss_auth=""
for f in "${GH_FILES[@]}"; do
  grep -Fq -e '- name: Governance - Approval log integrity'       "$f" || miss_int="$miss_int ${f##*/}"
  grep -Fq -e '- name: Governance - Approval author verification' "$f" || miss_auth="$miss_auth ${f##*/}"
done
if [ -z "$miss_int" ]; then
  pass "Cb-integrity-step (all $GH_COUNT)"
else
  fail_ "Cb-integrity-step" "missing 'Approval log integrity':$miss_int"
fi
if [ -z "$miss_auth" ]; then
  pass "Cb-author-step (all $GH_COUNT)"
else
  fail_ "Cb-author-step" "missing 'Approval author verification':$miss_auth"
fi

# ── (c) no APPROVAL_LOG-touching line carries the 2>/dev/null silencer ──────
echo "Cc: no APPROVAL_LOG line silences stderr (github + gitlab)"
hits=""
for f in "${GH_FILES[@]}" "${GL_FILES[@]}"; do
  if grep 'APPROVAL_LOG' "$f" | grep -Fq '2>/dev/null'; then
    hits="$hits ${f##*/}"
  fi
done
if [ -z "$hits" ]; then
  pass "Cc-no-silencer"
else
  fail_ "Cc-no-silencer" "APPROVAL_LOG line still silences stderr in:$hits"
fi

# ── (d) explicit base resolution, never bare origin/main...HEAD (github) ────
echo "Cd: github approval steps resolve the base explicitly + loud-fail"
bare=""
noexpr=""
noloud=""
for f in "${GH_FILES[@]}"; do
  grep -Fq 'origin/main...HEAD' "$f" && bare="$bare ${f##*/}"
  grep -Fq 'github.base_ref'    "$f" || noexpr="$noexpr ${f##*/}"
  grep -Fq 'git rev-parse --verify "$BASE"' "$f" || noloud="$noloud ${f##*/}"
done
if [ -z "$bare" ]; then
  pass "Cd-no-bare-base"
else
  fail_ "Cd-no-bare-base" "bare 'origin/main...HEAD' still present in:$bare"
fi
if [ -z "$noexpr" ]; then
  pass "Cd-explicit-base (all $GH_COUNT carry github.base_ref)"
else
  fail_ "Cd-explicit-base" "no explicit github.base_ref base in:$noexpr"
fi
if [ -z "$noloud" ]; then
  pass "Cd-loud-fail (all $GH_COUNT rev-parse --verify the base)"
else
  fail_ "Cd-loud-fail" "no loud-fail 'git rev-parse --verify \"\$BASE\"' in:$noloud"
fi

# ── (e) gitleaks CLI, never the org-license-trapped action ──────────────────
echo "Ce: gitleaks runs via the CLI, never gitleaks/gitleaks-action (github)"
action=""
nocli=""
for f in "${GH_FILES[@]}"; do
  grep -Fq 'gitleaks/gitleaks-action' "$f" && action="$action ${f##*/}"
  grep -Fq './gitleaks git'           "$f" || nocli="$nocli ${f##*/}"
done
if [ -z "$action" ]; then
  pass "Ce-no-action"
else
  fail_ "Ce-no-action" "gitleaks/gitleaks-action still present in:$action"
fi
if [ -z "$nocli" ]; then
  pass "Ce-cli (all $GH_COUNT run ./gitleaks git)"
else
  fail_ "Ce-cli" "no './gitleaks git' CLI invocation in:$nocli"
fi

# ── (f) gitlab twin: the approval-bearing gitlab templates get the same fix ─
echo "Cf: gitlab approval steps use explicit base + loud-fail, no silencer"
gl_approval=()
for f in "${GL_FILES[@]}"; do
  grep -Fq 'APPROVAL_LOG' "$f" && gl_approval+=("$f")
done
if [ "${#gl_approval[@]}" -ge 2 ]; then
  pass "Cf-floor (${#gl_approval[@]} gitlab templates carry an approval step, floor 2)"
else
  fail_ "Cf-floor" "found ${#gl_approval[@]} gitlab approval-bearing templates, expected >=2 — case is vacuous"
fi
gbare=""
gnoloud=""
for f in "${gl_approval[@]}"; do
  grep -Fq 'origin/main...HEAD' "$f" && gbare="$gbare ${f##*/}"
  grep -Fq 'git rev-parse --verify "$BASE"' "$f" || gnoloud="$gnoloud ${f##*/}"
done
if [ -z "$gbare" ]; then
  pass "Cf-no-bare-base (gitlab)"
else
  fail_ "Cf-no-bare-base" "bare 'origin/main...HEAD' still present in gitlab:$gbare"
fi
if [ -z "$gnoloud" ]; then
  pass "Cf-loud-fail (gitlab)"
else
  fail_ "Cf-loud-fail" "no loud-fail 'git rev-parse --verify \"\$BASE\"' in gitlab:$gnoloud"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

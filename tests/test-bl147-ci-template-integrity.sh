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

# ═══════════════════════════════════════════════════════════════════════════
# WP-2 (BL-148 + BL-153): semgrep surface modernization + hook-parity policy
# ═══════════════════════════════════════════════════════════════════════════
# The emitted CI SAST rode on the ARCHIVED semgrep/semgrep-action (github) and
# the RENAMED returntocorp/semgrep image (gitlab + bitbucket) — both dead
# namespaces. And the gitleaks step used the OLD `detect --source` command +
# the personal `zricethezav/gitleaks:latest` image (unpinned). WP-2:
#   • github: semgrep moves to a `semgrep/semgrep` CONTAINER JOB whose flags
#     EQUAL the local pre-commit hook's policy — CI and the dev hook enforce
#     the IDENTICAL ruleset (parity is the contract).
#   • gitlab + bitbucket: rename the semgrep image off returntocorp, bring the
#     flags to hook parity, and modernize gitleaks (detect --source -> dir;
#     :latest -> a version-pinned ghcr image).
#
# PARITY DERIVATION (single source): the expected semgrep flag set is DERIVED
# from the hook's own `semgrep scan` invocation in scripts/lib/hook-templates.sh
# — never retyped here. If the hook's policy changes, this suite tracks it.
#
# WP-2 CASES:
#   Cg1  no templates/pipelines file references semgrep/semgrep-action or
#        returntocorp/semgrep (GLOBAL — github, gitlab, bitbucket, release, …)
#   Cg2  every github CI template carries a `semgrep scan --config` invocation
#   Cg3  every github semgrep invocation's config/severity/--error EQUAL the hook
#   Cg4  every github CI template declares the `image: semgrep/semgrep` container
#   Cg5  every non-github (gitlab+bitbucket) semgrep step uses image:
#        semgrep/semgrep with hook-parity config/severity/--error flags
#   Cg6  every non-github gitleaks step is modernized: no `detect --source`,
#        runs `gitleaks dir`/`git`, off zricethezav, version-pinned image

BB_DIR="$REPO_ROOT/templates/pipelines/ci/bitbucket"
HOOK="$REPO_ROOT/scripts/lib/hook-templates.sh"
PIPE_DIR="$REPO_ROOT/templates/pipelines"

BB_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && BB_FILES+=("$f")
done < <(find "$BB_DIR" -name '*.yml' | sort)
BB_COUNT=${#BB_FILES[@]}

# ── Derive the hook's semgrep policy (SINGLE SOURCE — never retyped) ─────────
# Join the hook's `semgrep scan …` invocation across its line-continuations,
# then read the --config / --severity / --error tokens off it. The staged-files
# array + stderr redirect carry no config/severity token, so they drop out.
HOOK_INVOC="$(awk '
  /semgrep scan/ { collecting=1 }
  collecting {
    line=$0
    sub(/[[:space:]]*\\[[:space:]]*$/, "", line)
    printf "%s ", line
    if ($0 !~ /\\[[:space:]]*$/) exit
  }' "$HOOK")"
HOOK_CONFIGS="$(printf '%s\n' "$HOOK_INVOC" | grep -oE '\-\-config=[^[:space:]]+' | sort -u | tr '\n' ' ')"
HOOK_SEVERITY="$(printf '%s\n' "$HOOK_INVOC" | grep -oE '\-\-severity=[A-Za-z]+' | head -1)"
if printf '%s\n' "$HOOK_INVOC" | grep -qE '(^|[[:space:]])--error([[:space:]]|$)'; then HOOK_ERROR=yes; else HOOK_ERROR=no; fi

echo "Cg-derive: hook semgrep policy derived from hook-templates.sh (single source)"
if [ -n "$HOOK_CONFIGS" ] && [ -n "$HOOK_SEVERITY" ] && [ "$HOOK_ERROR" = yes ]; then
  pass "Cg-derive (configs='$HOOK_CONFIGS' severity='$HOOK_SEVERITY' --error=$HOOK_ERROR)"
else
  fail_ "Cg-derive" "could not derive the semgrep policy (configs='$HOOK_CONFIGS' severity='$HOOK_SEVERITY' error=$HOOK_ERROR)"
fi

# extract a template's semgrep policy -> sets EX_CONFIGS EX_SEVERITY EX_ERROR
extract_semgrep_policy() {
  local file="$1" line
  line="$(grep -E 'semgrep (scan )?--config' "$file" | head -1)"
  EX_CONFIGS="$(printf '%s\n' "$line" | grep -oE '\-\-config=[^][:space:],]+' | sort -u | tr '\n' ' ')"
  EX_SEVERITY="$(printf '%s\n' "$line" | grep -oE '\-\-severity=[A-Za-z]+' | head -1)"
  if printf '%s\n' "$line" | grep -qE '(^|[[:space:]])--error([[:space:]]|\]|$)'; then EX_ERROR=yes; else EX_ERROR=no; fi
}

# ── Cg1: no dead semgrep namespace anywhere under templates/pipelines ────────
echo "Cg1: no templates/pipelines file references semgrep/semgrep-action or returntocorp/semgrep"
dead="$(grep -rlE 'semgrep/semgrep-action|returntocorp/semgrep' "$PIPE_DIR" 2>/dev/null | sed "s|$REPO_ROOT/||" | tr '\n' ' ')"
if [ -z "$dead" ]; then
  pass "Cg1-no-dead-namespace"
else
  fail_ "Cg1-no-dead-namespace" "dead semgrep namespace still referenced in:$dead"
fi

# ── Cg2: every github CI template runs `semgrep scan --config` ──────────────
echo "Cg2: every github CI template carries a semgrep scan invocation"
miss_sg=""
for f in "${GH_FILES[@]}"; do
  grep -Eq 'semgrep scan --config' "$f" || miss_sg="$miss_sg ${f##*/}"
done
if [ -z "$miss_sg" ]; then
  pass "Cg2-semgrep-scan (all $GH_COUNT)"
else
  fail_ "Cg2-semgrep-scan" "no 'semgrep scan --config' invocation in:$miss_sg"
fi

# ── Cg3: github semgrep flags EQUAL the hook's policy (parity) ──────────────
echo "Cg3: every github semgrep invocation's flags EQUAL the hook policy"
badc=""; bads=""; bade=""
for f in "${GH_FILES[@]}"; do
  extract_semgrep_policy "$f"
  [ "$EX_CONFIGS"  = "$HOOK_CONFIGS" ]  || badc="$badc ${f##*/}(=$EX_CONFIGS)"
  [ "$EX_SEVERITY" = "$HOOK_SEVERITY" ] || bads="$bads ${f##*/}"
  [ "$EX_ERROR"    = "$HOOK_ERROR" ]    || bade="$bade ${f##*/}"
done
if [ -z "$badc" ]; then pass "Cg3-config-parity (all $GH_COUNT == '$HOOK_CONFIGS')"; else fail_ "Cg3-config-parity" "config set != hook '$HOOK_CONFIGS' in:$badc"; fi
if [ -z "$bads" ]; then pass "Cg3-severity-parity (all == '$HOOK_SEVERITY')"; else fail_ "Cg3-severity-parity" "severity != hook in:$bads"; fi
if [ -z "$bade" ]; then pass "Cg3-error-parity (all carry --error)"; else fail_ "Cg3-error-parity" "--error presence != hook in:$bade"; fi

# ── Cg4: github semgrep runs in the semgrep/semgrep container job ────────────
echo "Cg4: every github CI template declares the semgrep/semgrep container"
miss_img=""
for f in "${GH_FILES[@]}"; do
  grep -Eq '^[[:space:]]*image:[[:space:]]*semgrep/semgrep[[:space:]]*$' "$f" || miss_img="$miss_img ${f##*/}"
done
if [ -z "$miss_img" ]; then
  pass "Cg4-container (all $GH_COUNT use image: semgrep/semgrep)"
else
  fail_ "Cg4-container" "no 'image: semgrep/semgrep' container in:$miss_img"
fi

# ── Cg5: non-github semgrep steps — image rename + hook flag parity ─────────
echo "Cg5: gitlab+bitbucket semgrep steps use image: semgrep/semgrep + hook-parity flags"
NONGH_SEMGREP=()
for f in "${GL_FILES[@]}" "${BB_FILES[@]}"; do
  grep -Eq 'semgrep (scan )?--config' "$f" && NONGH_SEMGREP+=("$f")
done
if [ "${#NONGH_SEMGREP[@]}" -ge 12 ]; then
  pass "Cg5-floor (${#NONGH_SEMGREP[@]} non-github semgrep templates, floor 12)"
else
  fail_ "Cg5-floor" "found ${#NONGH_SEMGREP[@]} non-github semgrep templates, expected >=12 — vacuous"
fi
n_badimg=""; n_badc=""; n_bads=""; n_bade=""
for f in "${NONGH_SEMGREP[@]}"; do
  grep -Eq '^[[:space:]]*image:[[:space:]]*semgrep/semgrep[[:space:]]*$' "$f" || n_badimg="$n_badimg ${f#*/ci/}"
  extract_semgrep_policy "$f"
  [ "$EX_CONFIGS"  = "$HOOK_CONFIGS" ]  || n_badc="$n_badc ${f#*/ci/}(=$EX_CONFIGS)"
  [ "$EX_SEVERITY" = "$HOOK_SEVERITY" ] || n_bads="$n_bads ${f#*/ci/}"
  [ "$EX_ERROR"    = "$HOOK_ERROR" ]    || n_bade="$n_bade ${f#*/ci/}"
done
if [ -z "$n_badimg" ]; then pass "Cg5-image (all use image: semgrep/semgrep)"; else fail_ "Cg5-image" "no 'image: semgrep/semgrep' in:$n_badimg"; fi
if [ -z "$n_badc" ];   then pass "Cg5-config-parity (all == '$HOOK_CONFIGS')"; else fail_ "Cg5-config-parity" "config set != hook in:$n_badc"; fi
if [ -z "$n_bads" ];   then pass "Cg5-severity-parity"; else fail_ "Cg5-severity-parity" "severity != hook in:$n_bads"; fi
if [ -z "$n_bade" ];   then pass "Cg5-error-parity"; else fail_ "Cg5-error-parity" "--error presence != hook in:$n_bade"; fi

# ── Cg6: non-github gitleaks steps modernized (dir/git, pinned, off zricethezav)
echo "Cg6: gitlab+bitbucket gitleaks steps modernized (dir/git, version-pinned)"
NONGH_GITLEAKS=()
for f in "${GL_FILES[@]}" "${BB_FILES[@]}"; do
  grep -q 'gitleaks' "$f" && NONGH_GITLEAKS+=("$f")
done
if [ "${#NONGH_GITLEAKS[@]}" -ge 20 ]; then
  pass "Cg6-floor (${#NONGH_GITLEAKS[@]} non-github gitleaks templates, floor 20)"
else
  fail_ "Cg6-floor" "found ${#NONGH_GITLEAKS[@]} non-github gitleaks templates, expected >=20 — vacuous"
fi
g_detect=""; g_nocmd=""; g_legacy=""; g_unpinned=""
for f in "${NONGH_GITLEAKS[@]}"; do
  grep -Eq 'gitleaks detect --source' "$f" && g_detect="$g_detect ${f#*/ci/}"
  grep -Eq 'gitleaks (dir|git) ' "$f"      || g_nocmd="$g_nocmd ${f#*/ci/}"
  grep -q 'zricethezav/gitleaks' "$f"       && g_legacy="$g_legacy ${f#*/ci/}"
  grep -Eq 'gitleaks:v[0-9]+\.[0-9]+\.[0-9]+' "$f" || g_unpinned="$g_unpinned ${f#*/ci/}"
done
if [ -z "$g_detect" ];   then pass "Cg6-no-detect (no 'gitleaks detect --source')"; else fail_ "Cg6-no-detect" "'gitleaks detect --source' still present in:$g_detect"; fi
if [ -z "$g_nocmd" ];    then pass "Cg6-dir-or-git (all run 'gitleaks dir' or 'gitleaks git')"; else fail_ "Cg6-dir-or-git" "no 'gitleaks dir|git' invocation in:$g_nocmd"; fi
if [ -z "$g_legacy" ];   then pass "Cg6-off-zricethezav"; else fail_ "Cg6-off-zricethezav" "zricethezav/gitleaks still referenced in:$g_legacy"; fi
if [ -z "$g_unpinned" ]; then pass "Cg6-version-pinned (all gitleaks images carry a vX.Y.Z tag)"; else fail_ "Cg6-version-pinned" "gitleaks image not version-pinned in:$g_unpinned"; fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

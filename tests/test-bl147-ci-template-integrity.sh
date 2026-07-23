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
  # BL-147 follow-up (consolidated verifier MUST-1): bare `rev-parse --verify
  # "$BASE"` returns rc 0 for ANY 40-hex string, existent or not — the
  # force-push tamper passed silently. The ^{commit} peel demands a real
  # commit object; the zeros literal guards ref-creation (no history yet).
  grep -Fq 'git rev-parse --verify "$BASE^{commit}"' "$f" || noloud="$noloud ${f##*/}"
  grep -Fq '0000000000000000000000000000000000000000' "$f" || noloud="$noloud ${f##*/}(no-zeros-guard)"
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
  pass "Cd-loud-fail (all $GH_COUNT peel \$BASE^{commit} + carry the zeros ref-creation guard)"
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
  grep -Fq 'git rev-parse --verify "$BASE^{commit}"' "$f" || gnoloud="$gnoloud ${f##*/}"
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
  grep -Eq '^[[:space:]]*image:[[:space:]]*semgrep/semgrep:[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$' "$f" || miss_img="$miss_img ${f##*/}"
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
  grep -Eq '^[[:space:]]*image:[[:space:]]*semgrep/semgrep:[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$' "$f" || n_badimg="$n_badimg ${f#*/ci/}"
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

# ── Cg7 (BL-160): npm-audit blocking arm scoped to shipped deps ─────────────
# Dogfood-4 S1 F2: the emitted `npm audit --audit-level=…` step audits the
# FULL tree, so dev-toolchain advisories with no in-major fix red the lane
# forever on a project whose ship artifact has zero runtime deps — a
# permanently red lane teaches operators to ignore CI (the BL-122/BL-149
# false-FAIL doctrine). Contract pinned here, for every typescript CI
# template across the three hosts:
#   Cg7-floor     the three typescript templates exist (vacuity guard)
#   Cg7-blocking  each carries a BLOCKING `npm audit --omit=dev
#                 --audit-level=…` arm (shipped deps only)
#   Cg7-dev-loud  each carries a dev-inclusive audit arm guarded by `||`
#                 (loud, non-blocking — never a silent skip)
#   Cg7-no-bare   no UNGUARDED dev-inclusive audit remains (a bare
#                 `npm audit --audit-level=…` line without --omit=dev and
#                 without a `||` guard is the BL-160 defect)
echo "Cg7: typescript npm-audit arms — blocking scoped to --omit=dev, dev audit loud non-blocking"
TS_AUDIT_FILES=(
  "$REPO_ROOT/templates/pipelines/ci/github/typescript.yml"
  "$REPO_ROOT/templates/pipelines/ci/gitlab/typescript.yml"
  "$REPO_ROOT/templates/pipelines/ci/bitbucket/typescript.yml"
)
ts_missing=""
for f in "${TS_AUDIT_FILES[@]}"; do
  [ -f "$f" ] || ts_missing="$ts_missing ${f##*/ci/}"
done
if [ -z "$ts_missing" ]; then
  pass "Cg7-floor (all 3 typescript CI templates present)"
else
  fail_ "Cg7-floor" "typescript CI template missing (rename must fail loud):$ts_missing"
fi
a_noblock=""; a_noloud=""; a_bare=""
for f in "${TS_AUDIT_FILES[@]}"; do
  [ -f "$f" ] || continue
  # Verifier hardening (PR #244 adversarial pass): the `^[^#]*` prefix
  # rejects comment placements (a commented-out arm must not satisfy the
  # pin), and the blocking arm must be UNGUARDED — an `|| true`-suffixed
  # blocking line is a disabled check, not a blocking check. BL-146
  # review (R-244-1/2) tightened both further: the blocking arm also
  # rejects `;`/`&&`-suffixed disables, and the dev arm's `||` RHS must
  # actually WARN (::warning:: or WARNING) — a `|| true` silent skip is
  # the exact defect class the arm exists to avoid.
  grep -E '^[^#]*npm audit --omit=dev --audit-level=(high|moderate|low|critical)' "$f" \
      | grep -vE '\|\||;|&&' | grep -q . \
    || a_noblock="$a_noblock ${f##*/ci/}"
  grep -E '^[^#]*npm audit --audit-level=(high|moderate|low|critical)[^|]*\|\|.*(::warning::|WARNING)' "$f" \
      | grep -q . \
    || a_noloud="$a_noloud ${f##*/ci/}"
  # A dev-inclusive invocation is the contiguous form `npm audit
  # --audit-level=` (the scoped form reads `npm audit --omit=dev
  # --audit-level=` and does not contain that substring). Any such
  # non-comment line without a `||` guard is the BL-160 defect.
  if grep -E '^[^#]*npm audit --audit-level=' "$f" | grep -v -- '||' | grep -q .; then
    a_bare="$a_bare ${f##*/ci/}"
  fi
done
if [ -z "$a_noblock" ]; then pass "Cg7-blocking (all 3 carry npm audit --omit=dev --audit-level=…)"; else fail_ "Cg7-blocking" "no scoped blocking audit arm in:$a_noblock"; fi
if [ -z "$a_noloud" ];  then pass "Cg7-dev-loud (all 3 carry a ||-guarded dev-inclusive audit)"; else fail_ "Cg7-dev-loud" "no loud non-blocking dev audit arm in:$a_noloud"; fi
if [ -z "$a_bare" ];    then pass "Cg7-no-bare (no unguarded dev-inclusive audit remains)"; else fail_ "Cg7-no-bare" "unguarded dev-inclusive 'npm audit --audit-level' still present in:$a_bare"; fi

# ── Cg8 (BL-164): no github-context expansion inside run: scripts ───────────
# Dogfood-4 S3: the emitted BL-147 governance steps interpolated
# ${{ github.base_ref }} / ${{ github.event.before }} / ${{ github.event_name }}
# directly into run: shell — semgrep run-shell-injection flags it at ERROR, so
# every generated github project's own Phase-3 full-tree SAST FAILed on the
# framework's scaffold (and the pattern is real actions-hardening guidance:
# context values must enter the shell via env:, never by template expansion).
# Predicate: across ALL github pipeline templates (ci + release), any line
# containing `${{ github.` must be either a comment or an env-style
# `KEY: ${{ github.… }}` assignment. A floor guards vacuity.
echo "Cg8: github-context values enter shell via env: only (no run: interpolation)"
GH_ALL=( "${GH_FILES[@]}" )
for f in "$REPO_ROOT"/templates/pipelines/release/github/*.yml; do
  [ -f "$f" ] && GH_ALL+=("$f")
done
if [ "${#GH_ALL[@]}" -ge 12 ]; then
  pass "Cg8-floor (${#GH_ALL[@]} github pipeline templates, floor 12)"
else
  fail_ "Cg8-floor" "found ${#GH_ALL[@]} github pipeline templates, expected >=12 — vacuous"
fi
# Verifier hardening (PR #245 adversarial pass): the flag regex tolerates
# the no-space form (`${{github.` is valid Actions style and semgrep still
# fires on it) and ALSO flags `${{ env.* }}`, `${{ vars.* }}`, and
# `${{ inputs.* }}` — semgrep's run-shell-injection rule matches only the
# github context, so those three have NO SAST backstop at all (BL-146
# review R-245-1: `vars.*` in run: was live in release/github/web.yml and
# both this pin and semgrep missed it). The allow filter admits
# UPPER_SNAKE env-style assignments of any of the four contexts; a
# lowercase key false-FAILs LOUDLY (uppercase it), the acceptable
# direction. DOCUMENTED RESIDUALS (line-based predicate): a context
# expansion on a shell comment line inside run:, or on a
# `KEY: ${{ … }}`-shaped line inside run:, passes this pin — the
# github-context forms of both are caught by the semgrep backstop.
inj=""
for f in "${GH_ALL[@]}"; do
  if grep -E '\$\{\{[[:space:]]*(github|env|vars|inputs)\.' "$f" \
       | grep -vE '^[[:space:]]*#' \
       | grep -vE '^[[:space:]]*[A-Z_]+:[[:space:]]*\$\{\{[[:space:]]*(github|vars|inputs)\.' \
       | grep -q .; then
    inj="$inj ${f#*templates/pipelines/}"
  fi
done
if [ -z "$inj" ]; then
  pass "Cg8-env-indirection (no \${{ github.* }} reaches a run: script)"
else
  fail_ "Cg8-env-indirection" "github-context expansion outside env:/comments in:$inj"
fi

# ═══════════════════════════════════════════════════════════════════════════
# WP-3 (BL-149): the emitted release DAST is the un-fixed BL-122 twin
# ═══════════════════════════════════════════════════════════════════════════
# templates/pipelines/release/github/web.yml ran
#   docker run -t zaproxy/zap-stable zap-baseline.py -t ${{ vars.PREVIEW_URL }}
# and judged the RAW exit code. ZAP baseline reports every alert as WARN (exit
# 2) and rule 10049 (Storable/Cacheable, riskcode 0 = Informational) fires under
# EVERY Cache-Control value (the proven BL-122 mechanism) — so any real site
# fails the release. PR #203 fixed exactly this in run-phase3-validation.sh
# (`# BL-122-ZAP-RISK-FILTER` + `# BL-140-ZAP-WORKDIR`) and never touched the
# template. Aggravators: the image was unpinned (every other action in the file
# is SHA-pinned); no guard when PREVIEW_URL is unset; and templates/tool-matrix/
# web.json checked `zaproxy/zap-stable` — an image the scanner never uses.
#
# WP-3 ports the scanner's semantics into the emitted step (CONTENT pins, never
# a live docker run): pinned image, mounted workdir + `-J` JSON, raw exit code
# CAPTURED not judged, jq `riskcode>=2` verdict, unreadable/absent report FAILs
# LOUDLY, guarded on PREVIEW_URL. And tool-matrix checks the SAME image.
#
# WP-3 CASES:
#   Cz0  the two named files exist (vacuity guard — a rename must fail LOUD)
#   Cz-a release web.yml pins ghcr.io/zaproxy/zaproxy:stable, never zap-stable
#   Cz-b the ZAP step writes `-J` JSON to a mounted workdir, judges jq
#        `riskcode>=2`, and CAPTURES the raw exit (`|| rc=$?`) — never the verdict
#   Cz-c the step is guarded `if: vars.PREVIEW_URL != ''`
#   Cz-d an absent/unparseable report FAILs loudly (the failure arms exist)
#   Cz-e tool-matrix/web.json references the SAME pinned image (check + manual),
#        never zap-stable

REL_WEB="$REPO_ROOT/templates/pipelines/release/github/web.yml"
TOOLMATRIX_WEB="$REPO_ROOT/templates/tool-matrix/web.json"
ZAP_IMAGE='ghcr.io/zaproxy/zaproxy:stable'

# ── Cz0: the named files exist (vacuity guard) ──────────────────────────────
echo "Cz0: the WP-3 target files exist (a rename must fail loud, not vacuously pass)"
if [ -f "$REL_WEB" ] && [ -f "$TOOLMATRIX_WEB" ]; then
  pass "Cz0-files-present (release/github/web.yml + tool-matrix/web.json)"
else
  fail_ "Cz0-files-present" "a WP-3 target file is missing — cases below would be vacuous"
fi

# ── Cz-a: release web.yml pins the scanner's image, never the dead zap-stable ─
echo "Cz-a: release web.yml pins $ZAP_IMAGE (never zaproxy/zap-stable)"
if grep -Fq "$ZAP_IMAGE" "$REL_WEB"; then
  pass "Cz-a-pin (release web.yml references $ZAP_IMAGE)"
else
  fail_ "Cz-a-pin" "release web.yml does not pin $ZAP_IMAGE"
fi
if grep -Fq 'zaproxy/zap-stable' "$REL_WEB"; then
  fail_ "Cz-a-no-dead-image" "release web.yml still references the dead image zaproxy/zap-stable"
else
  pass "Cz-a-no-dead-image (no zaproxy/zap-stable in release web.yml)"
fi

# ── Cz-b: mounted workdir + -J JSON + jq riskcode>=2 verdict, raw exit CAPTURED
echo "Cz-b: the ZAP step writes -J JSON to a mounted workdir + judges jq riskcode>=2, not the raw exit"
if grep -Fq '/zap/wrk' "$REL_WEB" && grep -Fq -- '-J zap-report.json' "$REL_WEB"; then
  pass "Cz-b-mount-json (mounts /zap/wrk + writes -J zap-report.json)"
else
  fail_ "Cz-b-mount-json" "no mounted /zap/wrk workdir + '-J zap-report.json' in release web.yml"
fi
if grep -Fq 'riskcode' "$REL_WEB" && grep -Fq '>= 2' "$REL_WEB"; then
  pass "Cz-b-jq-verdict (jq judges riskcode >= 2)"
else
  fail_ "Cz-b-jq-verdict" "no jq 'riskcode >= 2' verdict in release web.yml (BL-122 risk filter not ported)"
fi
# The raw docker exit code must be CAPTURED, never BE the verdict: baseline rc
# 1/2 are ZAP's own WARN/FAIL thresholds over ALL alerts (informational too).
if grep -Fq '|| rc=$?' "$REL_WEB"; then
  pass "Cz-b-raw-exit-captured (|| rc=\$? — the raw exit is captured, not the verdict)"
else
  fail_ "Cz-b-raw-exit-captured" "no '|| rc=\$?'-style capture — the raw docker exit is (still) the verdict"
fi

# ── Cz-c: guarded on PREVIEW_URL ────────────────────────────────────────────
echo "Cz-c: the DAST step is guarded if: vars.PREVIEW_URL != ''"
if grep -Fq "if: vars.PREVIEW_URL != ''" "$REL_WEB"; then
  pass "Cz-c-preview-guard (if: vars.PREVIEW_URL != '')"
else
  fail_ "Cz-c-preview-guard" "no 'if: vars.PREVIEW_URL != \"\"' guard on the DAST step"
fi

# ── Cz-d: absent/unparseable report FAILs loudly (the BL-140/BL-122 posture) ─
echo "Cz-d: an absent/unparseable ZAP report fails loudly (arms exist textually)"
if grep -Fq 'no report' "$REL_WEB" && grep -Fq 'exit 1' "$REL_WEB"; then
  pass "Cz-d-no-report-loud (absent-report arm exits 1)"
else
  fail_ "Cz-d-no-report-loud" "no loud 'no report … exit 1' arm in release web.yml"
fi
if grep -Fq 'unparseable' "$REL_WEB" && grep -Fq 'exit 1' "$REL_WEB"; then
  pass "Cz-d-unparseable-loud (unparseable-report arm exits 1)"
else
  fail_ "Cz-d-unparseable-loud" "no loud 'unparseable … exit 1' arm in release web.yml"
fi

# ── Cz-e: tool-matrix/web.json checks the SAME image the scanner runs ────────
echo "Cz-e: tool-matrix/web.json references $ZAP_IMAGE (check + manual), never zap-stable"
if grep -Fq "docker image inspect $ZAP_IMAGE" "$TOOLMATRIX_WEB"; then
  pass "Cz-e-check-command ($ZAP_IMAGE in check_command)"
else
  fail_ "Cz-e-check-command" "tool-matrix/web.json check_command does not inspect $ZAP_IMAGE"
fi
if grep -Fq "docker pull $ZAP_IMAGE" "$TOOLMATRIX_WEB"; then
  pass "Cz-e-manual-hint ($ZAP_IMAGE in the manual install hint)"
else
  fail_ "Cz-e-manual-hint" "tool-matrix/web.json manual hint does not pull $ZAP_IMAGE"
fi
if grep -Fq 'zap-stable' "$TOOLMATRIX_WEB"; then
  fail_ "Cz-e-no-dead-image" "tool-matrix/web.json still references the dead image zap-stable"
else
  pass "Cz-e-no-dead-image (no zap-stable in tool-matrix/web.json)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# WP-4 (BL-150): every pinned Action ref is a 40-hex commit SHA + version note
# ═══════════════════════════════════════════════════════════════════════════
# The estate SHA-pins its GitHub Actions (BL-113), but the pins had drifted 1–3
# majors behind upstream (checkout v4→v7, setup-node v4→v7, action-gh-release
# v2→v3, golangci-lint-action v6→v9, …). WP-4 re-pins every action to its
# current release. These cases are a SHAPE guard ONLY — a 40-hex commit SHA + a
# trailing version comment on every `uses:` line under templates/pipelines/**
# and .github/workflows/*.yml, and on every action-bearing RELEASE_SETUP_ACTION
# entry in init.sh AND its sync sibling scripts/reconfigure-project.sh. NO
# network, NO version-freshness assertion: the currency WATCHER (does a pin LAG
# upstream?) is BL-150's deferred half, tracked under BL-109. The sole exemption
# is the build-time placeholder token `__SETUP_ACTION__` (init.sh/reconfigure
# substitute a SHA-pinned action at render time, BL-113).
#
# PRE-GREEN GUARD: on a fully-pinned tree these PASS by construction — the
# estate was already sha-pinned, only STALE. The RED half is proven by the
# pin-refresh diff itself and by the recorded mutation (bare `@vN` tag →
# Cp1-sha-pin RED). This is the sanctioned pre-green shape guard.
#
# WP-4 CASES:
#   Cp1  every `uses:` action ref (templates/pipelines/** + .github/workflows)
#        carries `@<40-hex-sha> # <version comment>` (placeholder exempt)
#   Cp2  every action-bearing RELEASE_SETUP_ACTION= entry in init.sh AND
#        scripts/reconfigure-project.sh (the sync sibling) is likewise pinned

# ── Ck1: the gitleaks CLI download is checksum-verified ──────────────────────
# Consolidated-verifier SHOULD-4: the version-tagged curl|tar had no integrity
# check — weaker than the SHA-pinned action it replaced. gitleaks ships
# <ver>_checksums.txt; the step must fetch it and sha256-verify the tarball.
echo "Ck1: every github gitleaks step sha256-verifies the download"
miss_ck=""
for f in "${GH_FILES[@]}"; do
  if grep -q 'GITLEAKS_VERSION' "$f"; then
    grep -q 'checksums.txt' "$f" && grep -q 'sha256sum' "$f" || miss_ck="$miss_ck ${f##*/}"
  else
    miss_ck="$miss_ck ${f##*/}(no-gitleaks-step)"
  fi
done
if [ -z "$miss_ck" ]; then
  pass "Ck1-gitleaks-checksum (all $GH_COUNT verify the tarball)"
else
  fail_ "Ck1-gitleaks-checksum" "no checksum verification in:$miss_ck"
fi

echo "Cp1: every uses: action ref is a 40-hex SHA pin + a version comment"
CP1_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && CP1_FILES+=("$f")
done < <( { find "$REPO_ROOT/templates/pipelines" -name '*.yml';
            find "$REPO_ROOT/.github/workflows" -name '*.yml'; } | sort )

cp1_total=0
cp1_bad=0
for f in "${CP1_FILES[@]}"; do
  while IFS= read -r line; do
    # Exempt the documented build-time placeholder (init.sh renders a pin, BL-113)
    case "$line" in *__SETUP_ACTION__*) continue ;; esac
    cp1_total=$((cp1_total + 1))
    if printf '%s' "$line" | grep -Eq '@[0-9a-f]{40}[[:space:]]+#'; then
      :
    else
      cp1_bad=$((cp1_bad + 1))
      fail_ "Cp1-sha-pin" "${f#"$REPO_ROOT/"}: uses: is not <40-hex-sha> # <comment> -> $(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    fi
  done < <(grep -hE 'uses:[[:space:]]' "$f")
done

if [ "$cp1_total" -ge 20 ]; then
  pass "Cp1-floor ($cp1_total uses: refs scanned, floor 20)"
else
  fail_ "Cp1-floor" "only $cp1_total uses: refs scanned (floor 20) — the scan is vacuous"
fi
if [ "$cp1_bad" -eq 0 ]; then
  pass "Cp1-all-pinned (every uses: ref is SHA-pinned + version-commented)"
fi

echo "Cp2: every action-bearing RELEASE_SETUP_ACTION entry (init.sh + sync sibling) is SHA-pinned"
# NB: these files are READ as data (grep), never executed — the `for … in`
# inline form (not an array literal) keeps lint-no-live-remote-in-tests.sh from
# mis-reading a `(`-prefixed init.sh path as a live init run (BL-076).
cp2_total=0
cp2_bad=0
for f in "$REPO_ROOT/init.sh" "$REPO_ROOT/scripts/reconfigure-project.sh"; do
  if [ ! -f "$f" ]; then
    fail_ "Cp2-table-present" "${f#"$REPO_ROOT/"} missing — the RELEASE_SETUP_ACTION sync sibling is gone"
    continue
  fi
  while IFS= read -r line; do
    # Only entries that name an action carry '@'; the '# Pre-installed' and
    # '# TODO' comment-only values have none and are correctly exempt.
    printf '%s' "$line" | grep -q '@' || continue
    cp2_total=$((cp2_total + 1))
    if printf '%s' "$line" | grep -Eq '@[0-9a-f]{40}[[:space:]]+#'; then
      :
    else
      cp2_bad=$((cp2_bad + 1))
      fail_ "Cp2-sha-pin" "${f#"$REPO_ROOT/"}: RELEASE_SETUP_ACTION is not <40-hex-sha> # <comment> -> $(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    fi
  done < <(grep -hE '^[[:space:]]*RELEASE_SETUP_ACTION="' "$f")
done

if [ "$cp2_total" -ge 12 ]; then
  pass "Cp2-floor ($cp2_total action-bearing RELEASE_SETUP_ACTION entries, floor 12)"
else
  fail_ "Cp2-floor" "only $cp2_total action-bearing RELEASE_SETUP_ACTION entries (floor 12) — vacuous"
fi
if [ "$cp2_bad" -eq 0 ]; then
  pass "Cp2-all-pinned (every action-bearing RELEASE_SETUP_ACTION is SHA-pinned + commented)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

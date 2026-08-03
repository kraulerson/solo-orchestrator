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
# SKIPPED is counted and reported separately — skipped != passed. It is used only
# by # BL-194-DERIVE-GATE, and only ever alongside a [FAIL] Cg-derive.
SKIPPED=0
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

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
#   • BL-201 (2026-07-31): the semgrep image FLOATS (`semgrep/semgrep:latest`).
#     Karl's recorded decision (backlog BL-201, rationale on BL-192): a pinned
#     scanner ages out of new detections silently — stale is the invisible
#     failure. The agreed price is reproducibility, paid consciously by logging
#     `semgrep --version` in EVERY semgrep job. Cg4/Cg5 pin the floating tag
#     AND the log line, and REFUSE a re-pinned (`semgrep/semgrep:X.Y.Z`) or
#     log-less template. gitleaks stays version-pinned (Cg6) — the float
#     decision is semgrep-specific, made safe by BL-198 (no gate clause reads
#     anything semgrep prints, so version drift can only ADD findings loudly).
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
#   Cg4  every github CI template declares the FLOATING `image:
#        semgrep/semgrep:latest` container AND logs `semgrep --version` (BL-201)
#   Cg5  every non-github (gitlab+bitbucket) semgrep step uses the floating
#        image with hook-parity config/severity/--error flags AND a version log
#   Cg5-scan-exec (BL-206 item 2) every non-github semgrep template carries an
#        EXECUTABLE `semgrep scan --config` line — the Cg2 analogue this half
#        never had, so a scan line lost to a `#` now FAILS instead of feeding
#        the parity comparison from the grave
#   Cg5-scan-exec-fixtures / Cg-extract-strip (R-BL206-2) the two item-2 atoms,
#        pinned on heredocs instead of on a hand-mutated template: the
#        `^[^#]*` guard and the extractor's comment strip. Both were measured
#        UNPINNED at the first cut (each mutant survived the full suite)
#   Cg-no-repin  every executable `semgrep/semgrep` reference under
#        templates/pipelines is EXACTLY `:latest` — numeric/digest/named-tag
#        pins and the bare spelling all refused (backstop beyond the
#        Cg4/Cg5 per-file lists)
#   Cg-no-repin-strip-controls (BL-206 item 3, RETREATED) the sweep keeps the
#        NAIVE never-accuse strip; the quoted-`#` evasion is an ACCEPTED limit
#        asserted as documented-miss fixtures, alongside the three innocent
#        line shapes a quote-aware strip was measured to ACCUSE (R-BL206-1)
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
#
# BL-194-DERIVE-ANCHOR — WHY THIS IS ANCHORED ON A MARKER AND NOT ON THE COMMAND
# NAME. The collector used to scope with a bare, unanchored /semgrep scan/ over
# the whole file and never stripped comments, so the FIRST line mentioning the
# command won — and `# BL-112-MAX-TARGET-BYTES` documents the invocation in prose
# above it, carrying a FALSIFIER that necessarily names the command. That prose
# line has no trailing `\`, so the collector emitted it and exited: configs=''
# severity='' error=no. Cg3/Cg5 then compared 22 templates against the EMPTY
# policy and reported a config-parity break that did not exist, in a message that
# named parity rather than derivation — which is how it got mis-diagnosed as a
# real hook/CI divergence. Matching on a name that prose is entitled to use is
# the defect; the fix is to start at a marker prose is not entitled to forge.
# This is the same shape as `_build_unit_list_set`'s unanchored `tests=(` scoper
# (see CLAUDE.md CANONICAL COMMANDS) — an awk scoper that reads comments.
#
# FALSIFIER: in scripts/lib/hook-templates.sh, move the `# BL-194-HOOK-SEMGREP-POLICY`
# marker line to the very top of the file (above the FALSIFIER prose) and re-run
# this suite — Cg-derive goes RED naming the marker, and does NOT silently derive
# the prose. Cg-derive-prose-immune / Cg-derive-marker-required below pin both
# halves on fixtures, so this does not depend on the live file's current shape.
derive_semgrep_policy() {   # <file> -> sets D_CONFIGS D_SEVERITY D_ERROR D_INVOC
  local file="$1"
  D_INVOC="$(awk '
    # BL-194-DERIVE-TRY-EVERY — try EVERY marker occurrence in file order and
    # accept the first whose collected text actually contains `semgrep scan`.
    # A first-match scan is forgeable by the idiomatic act of listing the marker
    # in the file header marker index (which is how this file documents its other
    # markers, and what CLAUDE.md CITATION RULE pushes an author toward) — that
    # alone re-opened BL-194 with the identical 7-line "22 templates disagree"
    # signature. A last-match scan is forgeable the same way from a footer. Only
    # try-every + the `semgrep scan` check makes prose harmless in BOTH
    # directions, which is why the check below is load-bearing and not a
    # belt-and-braces assertion.
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (line[i] !~ /BL-194-HOOK-SEMGREP-POLICY/) continue
        out = ""; collecting = 0
        for (j = i + 1; j <= NR; j++) {
          if (!collecting) {                 # skip the anchor own comment lines
            probe = line[j]
            sub(/^[[:space:]]*/, "", probe)
            if (probe ~ /^#/) continue
          }
          collecting = 1
          cur = line[j]
          sub(/[[:space:]]*\\[[:space:]]*$/, "", cur)
          out = out cur " "
          if (line[j] !~ /\\[[:space:]]*$/) break
        }
        # BL-194-DERIVE-UNAMBIGUOUS — count ACCEPTING occurrences; do not stop at
        # the first. Try-every alone still loses to any EARLIER occurrence whose
        # next non-comment line happens to contain `semgrep scan` — a stale
        # anchor+invocation pair left by a refactor, or the marker embedded in a
        # STRING above some other invocation. Both derive a real-looking policy
        # from the wrong text, so the derivation SUCCEEDS and BL-194-DERIVE-GATE
        # never engages: the suite goes back to accusing 22 templates with no
        # correctly-attributed line at all. Requiring exactly one acceptance turns
        # both into a loud, correctly-attributed failure.
        if (out ~ /semgrep scan/) { hits++; if (hits == 1) best = out }
      }
      if (hits == 1) printf "%s", best
    }' "$file")"
  D_CONFIGS="$(printf '%s\n' "$D_INVOC" | grep -oE '\-\-config=[^[:space:]]+' | sort -u | tr '\n' ' ')"
  D_SEVERITY="$(printf '%s\n' "$D_INVOC" | grep -oE '\-\-severity=[A-Za-z]+' | head -1)"
  if printf '%s\n' "$D_INVOC" | grep -qE '(^|[[:space:]])--error([[:space:]]|$)'; then D_ERROR=yes; else D_ERROR=no; fi
}

derive_semgrep_policy "$HOOK"
HOOK_INVOC="$D_INVOC"
HOOK_CONFIGS="$D_CONFIGS"
HOOK_SEVERITY="$D_SEVERITY"
HOOK_ERROR="$D_ERROR"

# BL-194-DERIVE-GATE — when the derivation fails there is NO expected policy, so
# every Cg3/Cg5 parity case below would compare a correct template against the
# empty string and emit six more `[FAIL]` lines naming templates by file. That is
# the ENTIRE defect this work exists to remove: seven accusatory lines pointing at
# 22 innocent files. Fixing only the derivation left 1 correct line + 6 accusatory
# ones, which is the same misdirection with a smaller multiplier. So a failed
# derivation SKIPS the parity cases instead of running them against nothing.
# Skipping is safe here and not a hole: HOOK_POLICY_OK=0 only ever accompanies a
# `[FAIL] Cg-derive`, so the suite is already red and cannot be read as a pass.
HOOK_POLICY_OK=1
echo "Cg-derive: hook semgrep policy derived from hook-templates.sh (single source)"
if ! printf '%s\n' "$HOOK_INVOC" | grep -q 'semgrep scan'; then
  # Anchor drift, not a policy change — say so, so the next reader does not spend
  # the diagnosis on the 22 CI templates the way this suite's message once caused.
  HOOK_POLICY_OK=0
  fail_ "Cg-derive" "could not derive ONE unambiguous semgrep policy from scripts/lib/hook-templates.sh via the '# BL-194-HOOK-SEMGREP-POLICY' anchor (collected: '$HOOK_INVOC'). Either the anchor no longer sits immediately above the 'semgrep scan' invocation, or MORE THAN ONE anchor now resolves to an invocation (a stale duplicate, or the marker inside a string) — grep the marker and leave exactly one that precedes the real invocation. The CI templates are NOT implicated, and the Cg3/Cg5 parity cases are SKIPPED below rather than run against an empty policy"
elif [ -n "$HOOK_CONFIGS" ] && [ -n "$HOOK_SEVERITY" ] && [ "$HOOK_ERROR" = yes ]; then
  pass "Cg-derive (configs='$HOOK_CONFIGS' severity='$HOOK_SEVERITY' --error=$HOOK_ERROR)"
else
  HOOK_POLICY_OK=0
  fail_ "Cg-derive" "could not derive the semgrep policy (configs='$HOOK_CONFIGS' severity='$HOOK_SEVERITY' error=$HOOK_ERROR) — the CI templates are NOT implicated; Cg3/Cg5 parity cases are SKIPPED below"
fi

# ── Cg-derive-prose-immune: documentation can NEVER move this suite's verdict ─
# Decoys sit on both sides of the anchor, and the one after it is indented prose
# of exactly the shape the real hook ships (a FALSIFIER naming the command).
echo "Cg-derive-prose-immune: prose naming 'semgrep scan' cannot become the policy"
derive_semgrep_policy /dev/stdin <<'PROSE_FIXTURE'
run_soif_sast() {
  #   FALSIFIER — RUN IT, DO NOT TRUST THIS:
  #     semgrep scan --config=p/decoy-before --severity=INFO   # in-project
      : "not the invocation"   # trailing comment naming semgrep scan --config=p/decoy-trailing
      # BL-194-HOOK-SEMGREP-POLICY — anchor
      #     semgrep scan --config=p/decoy-after --severity=INFO
      semgrep scan --config=p/real-one \
        --config=r/real-two \
        --severity=WARNING --error ${files[@]+"${files[@]}"} >"$out" 2>"$err"
}
PROSE_FIXTURE
if [ "$D_CONFIGS" = "--config=p/real-one --config=r/real-two " ] \
   && [ "$D_SEVERITY" = "--severity=WARNING" ] && [ "$D_ERROR" = yes ]; then
  pass "Cg-derive-prose-immune (3 decoys ignored, landed on the invocation)"
else
  fail_ "Cg-derive-prose-immune" "prose hijacked the derivation (configs='$D_CONFIGS' severity='$D_SEVERITY' error=$D_ERROR)"
fi

# ── Cg-derive-marker-required: no anchor => derive NOTHING, never guess ───────
# Without this the collector could fall back to name-matching, which is the
# defect BL-194-DERIVE-ANCHOR removed. An absent anchor must be loud, not lenient.
echo "Cg-derive-marker-required: an absent anchor derives nothing (fails loudly)"
derive_semgrep_policy /dev/stdin <<'NOMARKER_FIXTURE'
run_soif_sast() {
      semgrep scan --config=p/unanchored \
        --severity=ERROR --error "${files[@]}"
}
NOMARKER_FIXTURE
if [ -z "$D_INVOC" ] && [ -z "$D_CONFIGS" ] && [ "$D_ERROR" = no ]; then
  pass "Cg-derive-marker-required (no anchor -> empty policy -> Cg-derive fails)"
else
  # Print the COLLECTED TEXT, not just the parsed fields — the failing mutant
  # collects a non-policy line, whose configs/error parse to exactly the values
  # a pass would show. A message that omits D_INVOC reads as a false alarm.
  fail_ "Cg-derive-marker-required" "collected text with no anchor present: '$D_INVOC' (configs='$D_CONFIGS' severity='$D_SEVERITY' error=$D_ERROR) — the derivation must emit NOTHING without the anchor"
fi

# ── Cg-derive-decoy-marker-first: naming the anchor in prose must stay harmless ─
# THE FIRST FIX FOR BL-194 WAS ITSELF FORGEABLE. It armed on the FIRST marker
# occurrence, so adding the marker to this file's own header marker index — the
# idiomatic way hook-templates.sh documents every other marker, and what
# CLAUDE.md's CITATION RULE pushes an author toward — re-opened the defect with
# the identical "22 templates disagree" signature. This case pins the
# try-every-occurrence loop AND the `semgrep scan` acceptance check, which is the
# only thing that lets the loop reject a decoy and move on.
# Pins two atoms that a one-character narrowing would otherwise free:
#   • the FULL marker string. Narrow /BL-194-HOOK-SEMGREP-POLICY/ to /BL-194/ and
#     the `BL-194` mention below arms first; its next non-comment line IS a real
#     `semgrep scan`, so the acceptance check passes and the WRONG policy wins.
#   • the acceptance check itself. Delete it and the first decoy is taken
#     unconditionally, wrong policy again.
echo "Cg-derive-decoy-marker-first: an anchor named in prose, before the real one, must not win"
derive_semgrep_policy /dev/stdin <<'DECOY_FIXTURE'
# Header marker index, as hook-templates.sh writes one:
#   • # BL-194-HOOK-SEMGREP-POLICY — keep it immediately above the invocation.
      : "an executable line that is not the policy"
# A bare BL-194 mention, followed by a DIFFERENT semgrep invocation:
      semgrep scan --config=p/decoy-second-invocation --severity=INFO
      # BL-194-HOOK-SEMGREP-POLICY — anchor
      semgrep scan --config=p/real-one \
        --severity=WARNING --error "${files[@]}"
DECOY_FIXTURE
if [ "$D_CONFIGS" = "--config=p/real-one " ] && [ "$D_SEVERITY" = "--severity=WARNING" ]; then
  pass "Cg-derive-decoy-marker-first (a prose mention of the anchor is skipped, not taken)"
else
  fail_ "Cg-derive-decoy-marker-first" "a decoy anchor named in prose captured the derivation: collected '$D_INVOC' (configs='$D_CONFIGS' severity='$D_SEVERITY') — the loop must try EVERY occurrence and accept only one whose text contains 'semgrep scan'"
fi

# ── Cg-derive-comment-widths: pin the SPELLING of the comment skip ─────────────
# BL-181's lesson, applied before it costs anything: a one-character narrowing of
# a comment predicate passes every check while re-opening the hole. The skip is
# `sub(/^[[:space:]]*/,"",probe)` then `probe ~ /^#/`. Of its two candidate atoms,
# exactly ONE is load-bearing, and this case pins that one only — the fixture puts
# both comment forms between the anchor and the invocation, so a form the narrowed
# predicate stops recognising is collected AS the policy, fails the `semgrep scan`
# acceptance check, finds no further anchor, and derives nothing.
#   • PINNED — `#` -> `#[[:space:]]`. Requiring a blank after `#` stops
#     `#no-space-after-hash` from being a comment. MEASURED: the narrowed form
#     fails this suite (57/1); restored, 58/0.
#   • NOT PINNED, because it is BEHAVIOUR-NEUTRAL — `[[:space:]]*` -> `+`. Stated
#     plainly rather than asserted as covered: the `sub()` only STRIPS leading
#     blanks and the `^#` test runs on the result, so a column-0 comment is left
#     unchanged by either spelling and still matches. MEASURED both ways: both
#     report "recognised as comment", and the narrowed suite is 58/0. A fixture
#     claiming to pin it would pass for the wrong reason — which is worse than
#     leaving it unpinned and saying so.
echo "Cg-derive-comment-widths: column-0 and no-space-after-# comments are still comments"
derive_semgrep_policy /dev/stdin <<'WIDTH_FIXTURE'
      # BL-194-HOOK-SEMGREP-POLICY — anchor
# column-0 comment (neutral atom — see the note above; kept so the fixture covers the shape)
#no-space-after-hash: this is the atom the case actually pins
      semgrep scan --config=p/real-one \
        --severity=WARNING --error "${files[@]}"
WIDTH_FIXTURE
if [ "$D_CONFIGS" = "--config=p/real-one " ] && [ "$D_SEVERITY" = "--severity=WARNING" ]; then
  pass "Cg-derive-comment-widths (no-space-after-# comment skipped; column-0 shape covered)"
else
  fail_ "Cg-derive-comment-widths" "a comment form was not recognised, so it was collected as the policy: '$D_INVOC' (configs='$D_CONFIGS') — check the SPELLING of the '#' test, not just its presence"
fi

# ── Cg-derive-ambiguous-anchor: TWO resolving anchors must derive NOTHING ─────
# Try-every alone was not enough. An EARLIER occurrence whose next non-comment
# line contains `semgrep scan` wins outright, and because the derivation then
# SUCCEEDS on the wrong text, BL-194-DERIVE-GATE never engages — the suite
# reverts to the original BL-194 signature with ZERO correctly-attributed lines.
# Two placements do this and neither is exotic: a stale anchor+invocation pair
# left behind by a refactor, and the marker embedded in a STRING (not a comment)
# above some other invocation. Both are covered here; the fix is to require
# exactly one accepting occurrence (# BL-194-DERIVE-UNAMBIGUOUS).
echo "Cg-derive-ambiguous-anchor: two anchors that both resolve derive NOTHING"
derive_semgrep_policy /dev/stdin <<'AMBIG_FIXTURE'
      # BL-194-HOOK-SEMGREP-POLICY — a stale copy left by a refactor
      semgrep scan --config=p/stale-only         --severity=WARNING --error "${files[@]}"
      soif_note='see # BL-194-HOOK-SEMGREP-POLICY for the policy'
      semgrep scan --config=p/from-a-string --severity=INFO --error
      # BL-194-HOOK-SEMGREP-POLICY — anchor
      semgrep scan --config=p/real-one         --severity=ERROR --error "${files[@]}"
AMBIG_FIXTURE
if [ -z "$D_INVOC" ] && [ -z "$D_CONFIGS" ]; then
  pass "Cg-derive-ambiguous-anchor (3 resolving anchors -> derive nothing -> Cg-derive fails loudly)"
else
  fail_ "Cg-derive-ambiguous-anchor" "an ambiguous anchor set still produced a policy: '$D_INVOC' (configs='$D_CONFIGS') — with more than one anchor resolving, the derivation must refuse rather than pick one, or Cg-derive reports success on the wrong text and the parity cases accuse the templates again"
fi

# ── Cg-derive-continuation-comment: the `!collecting` guard IS load-bearing ────
# An earlier revision of this file documented this guard as unpinned, claiming a
# verdict could flip "only if such a line carries a --config". That was REFUTED:
# a continuation line beginning `#` with NO trailing backslash ends the command
# in bash, so dropping it mid-collection makes the collector join the NEXT,
# unrelated command — importing both its --config and its --severity. Guard on is
# the correct reading. Pinned here rather than re-documented as unpinned.
echo "Cg-derive-continuation-comment: a '#' continuation without a backslash ends the command"
derive_semgrep_policy /dev/stdin <<'CONTCMT_FIXTURE'
      # BL-194-HOOK-SEMGREP-POLICY — anchor
      semgrep scan --config=p/real-one         #stopper-with-no-backslash
        --config=p/NOT-IN-THE-INVOCATION --severity=INFO --error
CONTCMT_FIXTURE
if [ "$D_CONFIGS" = "--config=p/real-one " ] && [ -z "$D_SEVERITY" ]; then
  pass "Cg-derive-continuation-comment (collection stops at the '#' line; the next command is not joined)"
else
  fail_ "Cg-derive-continuation-comment" "the collector joined a following, unrelated command: configs='$D_CONFIGS' severity='$D_SEVERITY' — the !collecting guard on the comment-skip rule is load-bearing; without it a '#' continuation is dropped and the next command's flags are imported into the policy"
fi

# ATOMS THAT REMAIN UNPINNED, NAMED RATHER THAN ASSUMED COVERED. The practice
# CLAUDE.md uses for BL-181 two residuals: say which parts have no safety net.
#   1. `[[:space:]]*` -> `+` in the comment-skip `sub()`. BEHAVIOUR-NEUTRAL and
#      measured as such: the `sub()` only STRIPS leading blanks and the `^#` test
#      runs on the result, so a column-0 comment is unchanged by either spelling
#      and still matches. Checked across 11 line shapes on three awk
#      implementations (BWK, mawk, gawk): zero verdict differences, and the suite
#      is green under the narrowed form. A fixture claiming to pin it would pass
#      for the wrong reason.
#   2. The `HOOK_POLICY_OK` gate itself (# BL-194-DERIVE-GATE). Replacing its
#      condition with a constant false leaves this suite green, because the gate
#      only changes OUTPUT on a run that is already red. It is unpinned, and its
#      loss is a legibility regression rather than a correctness one — but it is
#      the whole point of the BL-194 work, so it is named here rather than
#      quietly trusted.
# The `!collecting` guard was ALSO listed here as unpinned, on the argument that
# a verdict could flip "only if such a line carries a --config". That claim was
# REFUTED (a `#` continuation with no trailing backslash imports the NEXT
# command flags wholesale), so it is now pinned by
# Cg-derive-continuation-comment above rather than documented away.

# ── BL-206-NAIVE-STRIP: cut at the FIRST `#`, and never accuse ───────────────
# ONE strip, used by BOTH halves of BL-206: extract_semgrep_policy (so a
# commented-out DECOY `semgrep scan --config` line can never become the compared
# policy) and the Cg-no-repin sweep.
#
# THIS IS A DELIBERATE RETREAT FROM A QUOTE-AWARE STRIP, AND THE REASON IS
# MEASURED. An earlier revision of this file shipped a quote-tracking awk strip
# (`# BL-206-QUOTE-AWARE-STRIP`) implementing the real YAML/shell rule — a `#`
# opens a comment only when unquoted AND at a line start or after a blank — to
# close R-BL201-5's quoted-`#` evasion. It carried a claim, in this header, that
# the strip "can only DROP a line from the deny set, never accuse a clean one".
# **That claim was FALSE.** Review R-BL206-1 refuted it with three families of
# line that a quote tracker ACCUSES and the naive cut never can, all confirmed on
# this host (each is a documented-miss control in Cg-no-repin-strip-controls):
#   1. NATURAL PROSE. `- name: Karl's build   # don't use semgrep/semgrep:1.170.0`
#      — the apostrophe in `Karl's` opens a phantom quote region, the real comment
#      is swallowed into it, and the apostrophe in `don't` closes it again, so the
#      tracker never sees a comment at all and hands the whole line to the deny
#      filter. PyYAML agrees the pin is comment text. MEASURED: ACCUSED under the
#      tracker, clean under the naive cut.
#   2. BACKSLASH ESCAPES. A quote tracker with no escape state miscounts `\"`,
#      e.g. `- run: echo "a\"b"   # old pin "semgrep/semgrep:1.170.0`. MEASURED:
#      ACCUSED.
#   3. PLAIN-SCALAR QUOTE PAIRING WITH THE COMMENT. One `"` in the scalar (an
#      inch mark, a stray quote) pairing with a `"` inside the comment, e.g.
#      `- name: The 6" ruler   # legacy pin "semgrep/semgrep:1.170.0`. MEASURED:
#      ACCUSED.
# The reviewer further verified that NO discriminator keeps the quoted-`#`
# carrier while refusing all three — the rescue direction is under-stripping, not
# a cleverer tracker. So the sweep returns to never-accuse semantics and the
# evasion is carried as a NAMED RESIDUAL (see the Cg-no-repin header). A test
# that false-FAILs an innocent template is worse than one with a documented,
# fixture-pinned blind spot: the first teaches operators to ignore the lane (the
# BL-122/BL-149 false-FAIL doctrine), the second is an honest, greppable limit.
#
# WHAT THIS STRIP IS, EXACTLY: `sed 's/#.*//'` — every line is truncated at its
# first `#`, whatever that `#` is quoting. It over-strips by construction, so it
# can only ever REMOVE text from consideration. That is the whole point, and it
# is why extract_semgrep_policy uses it too: extract must not inherit the
# accusation direction either (a `--error` dropped after a quoted `#` would fail
# Cg3/Cg5 parity on an innocent template — the same class of false FAIL).
strip_comments_naive() {   # <file> -> stdout: each line truncated at its first `#`
  sed 's/#.*//' "$1"
}

# extract a template's semgrep policy -> sets EX_CONFIGS EX_SEVERITY EX_ERROR
# BL-206-EXTRACT-COMMENT-STRIP — the compared line is chosen AFTER comment
# stripping. Before this, the collector greped the RAW file, so a commented-out
# `- semgrep scan --config=…` line still fed the Cg3/Cg5 parity comparison:
# commenting out ONLY that line in gitlab/python.yml left the suite at 63/0
# (measured, BL-206 item 2) — a dead line supplied a passing policy for a job
# that would scan nothing. Stripping matters in the other direction too: a
# trailing comment must not SUPPLY flags the executable line lacks
# (`… --config=A --config=B --config=C # --severity=ERROR --error` would
# otherwise pass parity over an invocation carrying neither).
# The strip is the NAIVE one on purpose (# BL-206-NAIVE-STRIP): on a scan line
# the real-tree quoted-`#` risk is nil — no `--config`-bearing line in
# templates/pipelines carries a `#` at all — while a quote-tracking strip would
# import the accusation direction R-BL206-1 refuted, and a dropped `--error`
# after a quoted `#` would false-FAIL Cg3/Cg5 parity on a template nobody broke.
# Pinned by Cg-extract-strip below, which is the ONLY thing standing between this
# line and the raw grep it replaced (# BL-206-EXTRACT-PIN).
extract_semgrep_policy() {
  local file="$1" line
  line="$(strip_comments_naive "$file" | grep -E 'semgrep (scan )?--config' | head -1)"
  EX_CONFIGS="$(printf '%s\n' "$line" | grep -oE '\-\-config=[^][:space:],]+' | sort -u | tr '\n' ' ')"
  EX_SEVERITY="$(printf '%s\n' "$line" | grep -oE '\-\-severity=[A-Za-z]+' | head -1)"
  if printf '%s\n' "$line" | grep -qE '(^|[[:space:]])--error([[:space:]]|\]|$)'; then EX_ERROR=yes; else EX_ERROR=no; fi
}

# ── Cg-extract-strip (# BL-206-EXTRACT-PIN): the comment strip in the extractor
# R-BL206-2 (major): the first cut of this work left the strip UNPINNED. Reverting
# extract_semgrep_policy to its old raw `grep -E … "$file"` survived the FULL
# suite at 65/0 — the templates are clean, so nothing on the real tree can tell
# the two apart, and the whole hole would have walked straight back in on the
# next refactor. The RED that justified the change was produced by MUTATING a
# real template, which is not a standing guard: the moment the template is
# restored, the check is unwitnessed. These fixtures are the standing guard.
#
# Two shapes, both measured on the pre-fix code, in OPPOSITE directions:
#   • DECOY ABOVE — a commented-out scan line sits FIRST in file order, so the
#     raw `head -1` picks the dead line and the live one is never read. This is
#     R-BL201-3's exact shape.
#   • COMMENT SUPPLIES FLAGS — a trailing comment carrying `--error` on a line
#     whose executable half lacks it. A raw grep reads the whole line and reports
#     EX_ERROR=yes for an invocation that would never block a build. This is the
#     direction R-BL201-3 did not name, and it is the more dangerous one: it
#     makes an UNARMED scanner look armed.
echo "Cg-extract-strip: extract_semgrep_policy reads the EXECUTABLE half of a line only"
ex_bad=""
extract_semgrep_policy /dev/stdin <<'EXFIX_DECOY'
  script:
    # - semgrep scan --config=p/decoy-above --severity=ERROR --error
    - semgrep scan --config=p/real-one --severity=WARNING
EXFIX_DECOY
[ "$EX_CONFIGS" = "--config=p/real-one " ] || ex_bad="$ex_bad decoy-above-configs(=$EX_CONFIGS)"
[ "$EX_SEVERITY" = "--severity=WARNING" ] || ex_bad="$ex_bad decoy-above-severity(=$EX_SEVERITY)"
[ "$EX_ERROR" = no ]                      || ex_bad="$ex_bad decoy-above-error(=$EX_ERROR)"
extract_semgrep_policy /dev/stdin <<'EXFIX_TRAILING'
  script:
    - semgrep scan --config=p/real-one --severity=WARNING   # --config=p/from-a-comment --error
EXFIX_TRAILING
[ "$EX_CONFIGS" = "--config=p/real-one " ] || ex_bad="$ex_bad trailing-configs(=$EX_CONFIGS)"
[ "$EX_ERROR" = no ]                      || ex_bad="$ex_bad trailing-error(=$EX_ERROR)"
# Positive control: an ordinary uncommented line must still parse in full, or the
# two assertions above would pass against a strip that deleted everything.
extract_semgrep_policy /dev/stdin <<'EXFIX_CLEAN'
    - semgrep scan --config=p/real-one --config=r/real-two --severity=ERROR --error
EXFIX_CLEAN
[ "$EX_CONFIGS" = "--config=p/real-one --config=r/real-two " ] || ex_bad="$ex_bad control-configs(=$EX_CONFIGS)"
[ "$EX_SEVERITY" = "--severity=ERROR" ]                        || ex_bad="$ex_bad control-severity(=$EX_SEVERITY)"
[ "$EX_ERROR" = yes ]                                          || ex_bad="$ex_bad control-error(=$EX_ERROR)"
if [ -z "$ex_bad" ]; then
  pass "Cg-extract-strip (decoy-above ignored, comment-supplied --error ignored, clean line parsed in full)"
else
  fail_ "Cg-extract-strip" "extract_semgrep_policy is reading COMMENT text as policy — wrong values:$ex_bad. A 'decoy-above-*' name means the extractor took a commented-out scan line that sits above the live one (it must strip comments BEFORE choosing the line, not grep the raw file). A 'trailing-*' name means a trailing comment SUPPLIED a flag the executable half lacks — the worst shape, because it makes an unarmed scanner pass parity. A 'control-*' name means the strip is now eating EXECUTABLE text, which would make the other two assertions pass for the wrong reason"
fi

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
if [ "$HOOK_POLICY_OK" -eq 0 ]; then   # BL-194-DERIVE-GATE
  skip_ "Cg3-config-parity"   "no hook policy was derived — comparing templates against '' would accuse 22 correct files; fix Cg-derive first"
  skip_ "Cg3-severity-parity" "no hook policy was derived (see Cg-derive)"
  skip_ "Cg3-error-parity"    "no hook policy was derived (see Cg-derive)"
else
  if [ -z "$badc" ]; then pass "Cg3-config-parity (all $GH_COUNT == '$HOOK_CONFIGS')"; else fail_ "Cg3-config-parity" "config set != hook '$HOOK_CONFIGS' in:$badc"; fi
  if [ -z "$bads" ]; then pass "Cg3-severity-parity (all == '$HOOK_SEVERITY')"; else fail_ "Cg3-severity-parity" "severity != hook in:$bads"; fi
  if [ -z "$bade" ]; then pass "Cg3-error-parity (all carry --error)"; else fail_ "Cg3-error-parity" "--error presence != hook in:$bade"; fi
fi

# ── Cg4: github semgrep runs in the FLOATING semgrep/semgrep container job ──
# BL-201-FLOAT-ASSERT: the tag must be EXACTLY `:latest` — anchored to end of
# line, so a re-pinned `semgrep/semgrep:X.Y.Z` fails BY DESIGN (reversing
# BL-201 takes a recorded decision, not a quiet edit). The float's agreed
# price is a `semgrep --version` log line in the job; `^[^#]*` (the Cg7 house
# pattern, PR #244) rejects comment placements — a commented-out log line
# must not satisfy the pin.
echo "Cg4: every github CI template floats semgrep/semgrep:latest + logs the version"
miss_img=""; miss_ver=""
for f in "${GH_FILES[@]}"; do
  grep -Eq '^[[:space:]]*image:[[:space:]]*semgrep/semgrep:latest[[:space:]]*$' "$f" || miss_img="$miss_img ${f##*/}"
  grep -Eq '^[^#]*semgrep --version' "$f" || miss_ver="$miss_ver ${f##*/}"
done
if [ -z "$miss_img" ]; then
  pass "Cg4-container (all $GH_COUNT float image: semgrep/semgrep:latest)"
else
  fail_ "Cg4-container" "no floating 'image: semgrep/semgrep:latest' line — the check demands the EXACT tag ':latest' anchored at end of line, so a version-pinned image (e.g. :1.170.0) fails here on purpose (BL-201 floats the scanner; see the backlog entry before re-pinning) — in:$miss_img"
fi
if [ -z "$miss_ver" ]; then
  pass "Cg4-version-log (all $GH_COUNT log semgrep --version)"
else
  fail_ "Cg4-version-log" "no executable 'semgrep --version' line — the image floats (BL-201), so the job log is the ONLY record of which scanner scanned a run; a comment mention does not count — in:$miss_ver"
fi

# ── Cg5: non-github semgrep steps — image rename + hook flag parity ─────────
echo "Cg5: gitlab+bitbucket semgrep steps use image: semgrep/semgrep + hook-parity flags"
NONGH_SEMGREP=()
for f in "${GL_FILES[@]}" "${BB_FILES[@]}"; do
  grep -Eq 'semgrep (scan )?--config' "$f" && NONGH_SEMGREP+=("$f")
done
# BL-206-FLOOR-EQUALS-CENSUS (R-BL206-3) — READ THIS BEFORE ADDING A TEMPLATE.
# The floor 12 is not a loose sanity bound: it is EXACTLY the current census
# (10 gitlab + 2 bitbucket — bitbucket ships 10 CI templates but only python and
# typescript carry a semgrep step at all). That equality is load-bearing, because
# WHOLE-LINE DELETION of a scan line is caught by nothing else: a file with no
# `semgrep …--config` text at all drops OUT of NONGH_SEMGREP entirely, so
# Cg5-scan-exec never sees it and only the count notices. The moment a 13th
# semgrep template lands, this floor stops being an equality and silently
# degrades into slack — one template could then be gutted for free. So: when you
# add a non-github semgrep template, RAISE THIS NUMBER in the same commit.
if [ "${#NONGH_SEMGREP[@]}" -ge 12 ]; then
  pass "Cg5-floor (${#NONGH_SEMGREP[@]} non-github semgrep templates, floor 12)"
else
  fail_ "Cg5-floor" "found ${#NONGH_SEMGREP[@]} non-github semgrep templates, expected >=12 — vacuous. NOTE the floor is meant to EQUAL the census (# BL-206-FLOOR-EQUALS-CENSUS): if you DELETED a scan line outright this is the only case that can see it, because a file with no 'semgrep --config' text at all leaves the census and Cg5-scan-exec never inspects it"
fi
# BL-201-FLOAT-ASSERT (non-github half) — same exact-`:latest` anchor and same
# comment-immune version-log predicate as Cg4; see the note there.
#
# BL-206-NONGH-SCAN-EXEC — the Cg2 analogue this half never had. Cg2 requires an
# EXECUTABLE `semgrep scan --config` line of every GITHUB template; nothing
# required one here, so a non-github template could lose its scan line to a `#`
# and stay green on every other case: the census below is comment-blind so the
# file stayed in the check set, the dead line still fed the parity comparison
# (until # BL-206-EXTRACT-COMMENT-STRIP), and Cg5-version-log stayed green off
# the INTACT `semgrep --version` line one line above. Measured at the BL-201 tip:
# commenting out ONLY the `- semgrep scan …` line of gitlab/python.yml survived
# the whole suite at 63/0. `^[^#]*` is the Cg7/PR-#244 house pattern — it demands
# a line on which no `#` precedes the invocation.
#
# The census stays COMMENT-BLIND on purpose (`semgrep (scan )?--config`, raw): if
# it read executable lines only, commenting the scan line would make the file
# DISAPPEAR from the check set rather than fail in it — a silent shrink, caught
# only by the Cg5-floor count. Keeping it blind means the file stays and this
# case names it by filename.
#
# The predicate is a NAMED FUNCTION rather than an inline grep so that
# Cg5-scan-exec-fixtures below can run the real thing against heredocs — R-BL206-2
# measured the inline version as UNPINNED (deleting `^[^#]*` left the suite 65/0).
file_has_exec_scan() {   # <file> -> rc 0 iff an EXECUTABLE `semgrep scan --config` line exists
  grep -Eq '^[^#]*semgrep scan --config' "$1"
}
n_badimg=""; n_badver=""; n_badscan=""; n_badc=""; n_bads=""; n_bade=""
for f in "${NONGH_SEMGREP[@]}"; do
  grep -Eq '^[[:space:]]*image:[[:space:]]*semgrep/semgrep:latest[[:space:]]*$' "$f" || n_badimg="$n_badimg ${f#*/ci/}"
  grep -Eq '^[^#]*semgrep --version' "$f" || n_badver="$n_badver ${f#*/ci/}"
  file_has_exec_scan "$f" || n_badscan="$n_badscan ${f#*/ci/}"
  extract_semgrep_policy "$f"
  [ "$EX_CONFIGS"  = "$HOOK_CONFIGS" ]  || n_badc="$n_badc ${f#*/ci/}(=$EX_CONFIGS)"
  [ "$EX_SEVERITY" = "$HOOK_SEVERITY" ] || n_bads="$n_bads ${f#*/ci/}"
  [ "$EX_ERROR"    = "$HOOK_ERROR" ]    || n_bade="$n_bade ${f#*/ci/}"
done
if [ -z "$n_badimg" ]; then pass "Cg5-image (all float image: semgrep/semgrep:latest)"; else fail_ "Cg5-image" "no floating 'image: semgrep/semgrep:latest' line — the check demands the EXACT tag ':latest' anchored at end of line, so a version-pinned image fails here on purpose (BL-201) — in:$n_badimg"; fi
if [ -z "$n_badver" ]; then pass "Cg5-version-log (all log semgrep --version)"; else fail_ "Cg5-version-log" "no executable 'semgrep --version' line — the float's agreed price is that the job log answers 'what scanned this merge?'; a comment mention does not count — in:$n_badver"; fi
if [ -z "$n_badscan" ]; then pass "Cg5-scan-exec (all ${#NONGH_SEMGREP[@]} carry an executable semgrep scan --config line)"; else fail_ "Cg5-scan-exec" "no EXECUTABLE 'semgrep scan --config' line — the check demands a line with NO '#' before the invocation ('^[^#]*semgrep scan --config'), so a scan line that has been commented out does not count, even though the file is still counted as a semgrep template (the census is deliberately comment-blind so a commented-out scan FAILS here instead of vanishing from the check set) — in:$n_badscan"; fi

# ── Cg5-scan-exec-fixtures (# BL-206-SCAN-EXEC-PIN): the `^[^#]*` guard, pinned ─
# R-BL206-2 (major): as first written, Cg5-scan-exec's `^[^#]*` guard was doing
# nothing that the suite could witness. Deleting it — leaving a bare
# `grep -Eq 'semgrep scan --config'`, i.e. the comment-blind predicate the case
# exists to replace — left the FULL suite at 65/0, because every real template is
# clean and the only RED had come from hand-mutating one. A guard whose removal
# changes no verdict is not enforced; these heredocs make it enforced.
echo "Cg5-scan-exec-fixtures: a commented-out scan line does not satisfy the scan-exec pin"
se_bad=""
# The R-BL201-3 shape: the file's ONLY scan line is commented out. Must NOT pass.
if file_has_exec_scan /dev/stdin <<'SEFIX_COMMENTED'
sast:
  script:
    - semgrep --version
    # - semgrep scan --config=p/owasp-top-ten --severity=ERROR --error
SEFIX_COMMENTED
then se_bad="$se_bad commented-only-ACCEPTED"; fi
# Indented `#` and a no-space-after-`#` spelling are comments too (BL-181's
# width/spelling lesson: pin the SHAPE of the comment, not just its presence).
if file_has_exec_scan /dev/stdin <<'SEFIX_TIGHT'
	#- semgrep scan --config=p/owasp-top-ten --severity=ERROR --error
SEFIX_TIGHT
then se_bad="$se_bad tab-indent-nospace-ACCEPTED"; fi
# Positive control: a real scan line must still satisfy it, or "commented-out
# fails" would be true of a predicate that refuses everything.
file_has_exec_scan /dev/stdin <<'SEFIX_LIVE' || se_bad="$se_bad live-scan-REFUSED"
    - semgrep scan --config=p/owasp-top-ten --severity=ERROR --error
SEFIX_LIVE
# Second positive control: an executable scan line with a TRAILING comment is
# still executable. `^[^#]*` must anchor at the START, not merely require the
# line to be `#`-free — a whole-line `grep -v '#'` would fail this one.
file_has_exec_scan /dev/stdin <<'SEFIX_TRAILING' || se_bad="$se_bad trailing-comment-REFUSED"
    - semgrep scan --config=p/owasp-top-ten --severity=ERROR --error   # hook parity
SEFIX_TRAILING
if [ -z "$se_bad" ]; then
  pass "Cg5-scan-exec-fixtures (commented-out scan refused in 2 spellings, live + trailing-comment scan accepted)"
else
  fail_ "Cg5-scan-exec-fixtures" "the scan-exec predicate is not reading the '^[^#]*' guard correctly:$se_bad. A '*-ACCEPTED' name means a COMMENTED-OUT scan line satisfied the pin — that is the whole BL-206 item-2 hole re-opened, and it is what deleting '^[^#]*' does. A '*-REFUSED' name is the opposite over-correction: an EXECUTABLE scan line was rejected, which false-FAILs every clean template (the 'trailing-comment' one fails if the guard is rewritten as a whole-line '#'-free test instead of a start-anchored prefix)"
fi
if [ "$HOOK_POLICY_OK" -eq 0 ]; then   # BL-194-DERIVE-GATE (Cg5-image above is policy-independent, so it still runs)
  skip_ "Cg5-config-parity"   "no hook policy was derived (see Cg-derive)"
  skip_ "Cg5-severity-parity" "no hook policy was derived (see Cg-derive)"
  skip_ "Cg5-error-parity"    "no hook policy was derived (see Cg-derive)"
else
  if [ -z "$n_badc" ];   then pass "Cg5-config-parity (all == '$HOOK_CONFIGS')"; else fail_ "Cg5-config-parity" "config set != hook in:$n_badc"; fi
  if [ -z "$n_bads" ];   then pass "Cg5-severity-parity"; else fail_ "Cg5-severity-parity" "severity != hook in:$n_bads"; fi
  if [ -z "$n_bade" ];   then pass "Cg5-error-parity"; else fail_ "Cg5-error-parity" "--error presence != hook in:$n_bade"; fi
fi

# ── Cg-no-repin: every executable semgrep/semgrep ref is EXACTLY :latest ────
# BL-201-FLOAT-SWEEP: Cg4/Cg5 anchor only the files in TODAY'S lists; this
# sweep is the backstop that catches a pinned semgrep image in a file those
# lists never see — a new template family, a release pipeline, a copy-paste.
# The predicate is deny-by-default (review R-BL201-1: the first cut matched
# only `:[0-9]` and a DIGEST pin `@sha256:…` — the STRONGEST pin form — plus
# named tags like `:canary` sailed through): after stripping comments
# (whole-line and trailing), any line still carrying `semgrep/semgrep` must
# carry `semgrep/semgrep:latest` at a tag boundary, so numeric tags, digests,
# named tags, `:latest-nonroot`, and the BARE floating spelling are ALL
# refused — one canonical form.
#
# BL-206-QUOTE-BLIND-RESIDUAL (item 3, RETREATED — read this before "fixing" it):
# the strip is `sed 's/#.*//'` (# BL-206-NAIVE-STRIP), which truncates at the
# FIRST `#` on the line whatever that `#` is quoting. R-BL201-5 measured the
# consequence: `run: echo 'a#b' && docker run semgrep/semgrep:1.170.0` planted
# outside the per-file lists survives the whole suite, and so do a `${VAR#prefix}`
# carrier and a URL fragment. **That miss is now a DELIBERATE, ACCEPTED LIMIT,
# not an oversight**, and the four shapes are pinned as documented-miss CONTROLS
# in Cg-no-repin-strip-controls below, so re-closing it flips a fixture and
# forces the decision back through review rather than happening by accident.
#
# WHY THE OBVIOUS FIX IS BANNED. A quote-aware strip WAS built and shipped on
# this branch, then withdrawn: review R-BL206-1 refuted its central claim (that
# it could only drop lines, never accuse) with three families of innocent line it
# ACCUSES — natural prose with an apostrophe (`- name: Karl's build   # don't use
# semgrep/semgrep:1.170.0`), `\"` escapes, and a plain-scalar `"` pairing with a
# `"` inside the comment. All three reproduce on this host; all three are
# never-accuse controls below. The reviewer further established that no
# discriminator keeps the quoted-`#` carrier while refusing those three — the
# rescue direction is UNDER-stripping. Anyone re-attempting this must beat that
# result first, and must re-measure the three families, not just the carrier.
# The trade is deliberate: this sweep is a breadth BACKSTOP behind the per-file
# Cg4/Cg5 anchors, so its miss costs defence-in-depth, whereas a false FAIL on a
# clean template costs the lane its credibility (the BL-122/BL-149 doctrine).
#
# REMAINING residuals, named rather than papered over:
#   • line-granular — a single line carrying BOTH an acceptable and a pinned ref
#     escapes, because the deny filter is applied per line.
#   • quoted/parameter-expansion/URL-fragment `#` — the accepted limit above.
# The per-file Cg4/Cg5 anchors are the primary enforcement; this is the breadth
# backstop, and its own vacuity is covered by them (Cg4-container + Cg5-image
# already require 22 files to carry the image line, so an enumeration that found
# nothing here could not leave the suite green). gitleaks pins are untouched: the
# pattern is semgrep-specific by construction.

# BL-206-REPIN-PREDICATE — ONE predicate, run by the sweep AND by its fixtures,
# so the fixture cases below cannot drift away from what the sweep does.
file_has_repin() {   # <file> -> rc 0 iff a non-:latest semgrep/semgrep ref survives comment-stripping
  strip_comments_naive "$1" \
    | grep 'semgrep/semgrep' \
    | grep -Ev 'semgrep/semgrep:latest([^A-Za-z0-9._-]|$)' \
    | grep -q .
}

echo "Cg-no-repin: every executable semgrep/semgrep reference under templates/pipelines is exactly :latest"
repin=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  file_has_repin "$f" && repin="$repin${f#"$REPO_ROOT/"} "
done < <(grep -rl 'semgrep/semgrep' "$PIPE_DIR" 2>/dev/null | sort)
if [ -z "$repin" ]; then
  pass "Cg-no-repin"
else
  fail_ "Cg-no-repin" "non-:latest semgrep/semgrep reference on an executable line in: ${repin}(the ONLY accepted form is the exact tag semgrep/semgrep:latest — numeric tags, @sha256 digests, named tags like :canary, and the bare spelling all fail here; BL-201 floats the scanner deliberately, and re-pinning requires reversing that recorded decision on the backlog, not a template edit)"
fi

# ── Cg-no-repin-strip-controls (# BL-206-STRIP-CONTROLS) ─────────────────────
# Thirteen fixtures (4 caught + 2 exempt + 4 documented misses + 3 never-accuse controls) through the SAME predicate the sweep runs, in THREE groups. Two
# of the groups assert things the sweep DOES; one asserts things it deliberately
# does NOT. Reading the group names is the whole point of the case.
#
#   A. CAUGHT (positive controls) — a pinned ref on a line with no comment
#      before it must be flagged, in each refused spelling. Without these the
#      other seven would pass against a predicate that refuses everything.
#   B. EXEMPT (intended) — a whole-line comment and a trailing comment naming an
#      old pin must NOT be flagged. Documentation is not a violation.
#   C. DOCUMENTED MISSES (# BL-206-QUOTE-BLIND-RESIDUAL) — the four R-BL201-5
#      carriers, asserted as MISSES. This is the bl132 boundary-re-pin
#      discipline: a limit that a fixture ASSERTS cannot quietly change. If you
#      close the evasion, these four go red and you must edit them on purpose,
#      which routes the decision back through review.
#      They sit beside three NEVER-ACCUSE controls from R-BL206-1 — the shapes
#      that killed the quote-aware strip. Those three must stay clean under any
#      future strip; they are the reason group C is a limit rather than a bug.
#      MEASURED against the withdrawn tracker on this host: each of the three is
#      ACCUSED by it and clean under the naive cut. They are the regression test
#      for the whole retreat.
echo "Cg-no-repin-strip-controls: caught / exempt / documented-miss, each asserted explicitly"
qa_bad=""
# ── A. CAUGHT ────────────────────────────────────────────────────────────────
file_has_repin /dev/stdin <<'QA_PLAIN' || qa_bad="$qa_bad A-numeric-tag-MISSED"
    - run: docker run semgrep/semgrep:1.170.0 scan
QA_PLAIN
file_has_repin /dev/stdin <<'QA_DIGEST' || qa_bad="$qa_bad A-digest-MISSED"
    - run: docker run semgrep/semgrep@sha256:0123456789abcdef scan
QA_DIGEST
file_has_repin /dev/stdin <<'QA_NAMEDTAG' || qa_bad="$qa_bad A-named-tag-MISSED"
      image: semgrep/semgrep:canary
QA_NAMEDTAG
# A pin is still a pin when a comment follows it — the strip must not swallow the
# EXECUTABLE half of a line just because the line ends in a comment.
file_has_repin /dev/stdin <<'QA_PIN_THEN_COMMENT' || qa_bad="$qa_bad A-pin-before-comment-MISSED"
    - run: docker run semgrep/semgrep:1.170.0 scan   # temporary, honest
QA_PIN_THEN_COMMENT
# ── B. EXEMPT (intended) ─────────────────────────────────────────────────────
if file_has_repin /dev/stdin <<'QA_WHOLELINE'
    # historical note: this job used to pin semgrep/semgrep:1.170.0
    - run: docker run semgrep/semgrep:latest scan
QA_WHOLELINE
then qa_bad="$qa_bad B-whole-line-comment-ACCUSED"; fi
if file_has_repin /dev/stdin <<'QA_TRAILING'
    - run: docker run semgrep/semgrep:latest scan   # was semgrep/semgrep:1.170.0
QA_TRAILING
then qa_bad="$qa_bad B-trailing-comment-ACCUSED"; fi
# ── C. DOCUMENTED MISSES + the never-accuse controls that justify them ───────
# C1-C4: R-BL201-5's carriers. Asserted as MISSES on purpose — see the header.
if file_has_repin /dev/stdin <<'QA_QUOTED'
    - run: echo 'a#b' && docker run semgrep/semgrep:1.170.0
QA_QUOTED
then qa_bad="$qa_bad C-quoted-hash-no-blank-NOW-CAUGHT"; fi
if file_has_repin /dev/stdin <<'QA_QUOTED_BLANK'
    - run: echo 'pin # here' && docker run semgrep/semgrep:1.170.0
QA_QUOTED_BLANK
then qa_bad="$qa_bad C-quoted-hash-with-blank-NOW-CAUGHT"; fi
if file_has_repin /dev/stdin <<'QA_PAREXP'
    - run: echo ${TAG#v} && docker run semgrep/semgrep@sha256:0123456789abcdef
QA_PAREXP
then qa_bad="$qa_bad C-param-expansion-NOW-CAUGHT"; fi
if file_has_repin /dev/stdin <<'QA_URLFRAG'
    - run: curl https://example.test/pins#semgrep && docker run semgrep/semgrep:canary
QA_URLFRAG
then qa_bad="$qa_bad C-url-fragment-NOW-CAUGHT"; fi
# C5-C7: R-BL206-1's accusation families. These must NEVER be flagged.
if file_has_repin /dev/stdin <<'QA_PROSE_APOSTROPHE'
    - name: Karl's build   # don't use semgrep/semgrep:1.170.0
QA_PROSE_APOSTROPHE
then qa_bad="$qa_bad C-prose-apostrophe-ACCUSED"; fi
if file_has_repin /dev/stdin <<'QA_BACKSLASH_ESCAPE'
    - run: echo "a\"b"   # old pin "semgrep/semgrep:1.170.0
QA_BACKSLASH_ESCAPE
then qa_bad="$qa_bad C-backslash-escape-ACCUSED"; fi
if file_has_repin /dev/stdin <<'QA_SCALAR_QUOTE_PAIRING'
    - name: The 6" ruler   # legacy pin "semgrep/semgrep:1.170.0
QA_SCALAR_QUOTE_PAIRING
then qa_bad="$qa_bad C-scalar-quote-pairing-ACCUSED"; fi
if [ -z "$qa_bad" ]; then
  pass "Cg-no-repin-strip-controls (4 caught, 2 exempt, 4 documented misses, 3 never-accuse controls)"
else
  fail_ "Cg-no-repin-strip-controls" "the Cg-no-repin comment strip changed behaviour — READ THE GROUP LETTER:$qa_bad. 'A-*-MISSED' means the sweep stopped catching a plainly pinned ref, which is the sweep failing at its actual job (most likely the strip now eats executable text). 'B-*-ACCUSED' means a genuine COMMENT is being read as executable, which false-FAILs clean templates. 'C-*-NOW-CAUGHT' is NOT necessarily a bug: it means someone closed the quoted-'#' evasion that BL-206 item 3 deliberately left open — if that was intentional, you must ALSO re-measure the three C-*-ACCUSED controls and update the # BL-206-QUOTE-BLIND-RESIDUAL header, because the last attempt at this shipped a strip that accused innocent templates (R-BL206-1). 'C-*-ACCUSED' is the hard stop: those three lines are ordinary YAML that a quote-tracking strip mis-parses, and flagging any of them means the retreat has been undone"
fi

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

# ── Cw6 (walk 2026-08-02 ISSUE-006): the phase-gate CREDENTIAL comment block ─
# The gate's Phase 1→2 backstop verifies branch protection through an
# AUTHENTICATED host API read that no generated runner can perform: Actions
# exports no token into a step env (and the built-in GITHUB_TOKEN cannot read
# protection at all — no `administration` key in `permissions:`), and the
# gitlab/bitbucket governance jobs install only jq+git. That made the
# governance job STRUCTURALLY unpassable on the framework's own default happy
# path. `# WALK-ISSUE-006-CI-PROTECTION-SCOPE` converts that ONE check to a
# loud WARN in credential-less CI; this case pins the OTHER half — the emitted
# workflow has to SAY so, and has to name the token that re-arms hard
# enforcement. A silent exemption is how a downgraded check becomes a
# forgotten check.
#   Cw6-floor       every CI template across the three hosts runs the gate
#   Cw6-block       each carries the signature line, AS A COMMENT
#   Cw6-honest      each says UNVERIFIED (never "verified") about the skip
#   Cw6-guided      each names the guided walkthrough (--setup-ci-token) — the
#                   token path is RECOMMENDED, not merely available
#   Cw6-credential  each names its host's hard-enforcement credential
#   Cw6-wiring      github templates map the secret LIVE (executable YAML under
#                   an `env:` key, not a commented example). This is the pin
#                   that makes the walkthrough's result real: if the mapping is
#                   a comment, `--setup-ci-token` stores a secret NOTHING reads
#                   and the check keeps warning forever.
echo "Cw6: every CI template that runs check-phase-gate.sh explains the credential model"
CPG_FILES=()
for f in "${GH_FILES[@]}" "${GL_FILES[@]}" "${BB_FILES[@]}"; do
  # executable invocation only — a commented-out gate line is not a gate
  grep -Eq '^[^#]*bash scripts/check-phase-gate\.sh' "$f" && CPG_FILES+=("$f")
done
CPG_COUNT=${#CPG_FILES[@]}
if [ "$CPG_COUNT" -ge 30 ]; then
  pass "Cw6-floor ($CPG_COUNT CI templates execute check-phase-gate.sh, floor 30)"
else
  fail_ "Cw6-floor" "only $CPG_COUNT CI templates execute check-phase-gate.sh (floor 30) — derivation is vacuous"
fi
w6_noblock=""; w6_nothonest=""; w6_nocred=""; w6_noguide=""; w6_nowire=""
if [ "$CPG_COUNT" -gt 0 ]; then
  for f in "${CPG_FILES[@]}"; do
    # The signature must sit on a COMMENT line: an executable line that
    # happened to contain the phrase must not satisfy the pin.
    grep -Eq '^[[:space:]]*#[[:space:]]*PHASE-GATE CREDENTIALS \(walk ISSUE-006\)' "$f" \
      || w6_noblock="$w6_noblock ${f#*/ci/}"
    grep -Eq '^[[:space:]]*#.*UNVERIFIED' "$f" \
      || w6_nothonest="$w6_nothonest ${f#*/ci/}"
    grep -Eq '^[[:space:]]*#.*check-gate\.sh --setup-ci-token' "$f" \
      || w6_noguide="$w6_noguide ${f#*/ci/}"
    case "$f" in
      */ci/github/*)
        # github's credential is the LIVE mapping, not prose — assert the
        # executable form (no leading `#`) under the step.
        grep -Eq '^[[:space:]]*GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*secrets\.SOIF_PROTECTION_TOKEN[[:space:]]*\}\}[[:space:]]*$' "$f" \
          || w6_nocred="$w6_nocred ${f#*/ci/}"
        grep -Eq '^[[:space:]]*env:[[:space:]]*$' "$f" \
          || w6_nowire="$w6_nowire ${f#*/ci/}"
        ;;
      */ci/gitlab/*)
        grep -Eq '^[[:space:]]*#.*GITLAB_TOKEN' "$f" || w6_nocred="$w6_nocred ${f#*/ci/}" ;;
      */ci/bitbucket/*)
        grep -Eq '^[[:space:]]*#.*BITBUCKET_API_TOKEN' "$f" || w6_nocred="$w6_nocred ${f#*/ci/}" ;;
    esac
  done
fi
if [ -z "$w6_noblock" ]; then
  pass "Cw6-block (all $CPG_COUNT templates carry the credential comment block)"
else
  fail_ "Cw6-block" "no '# PHASE-GATE CREDENTIALS (walk ISSUE-006)' comment in:$w6_noblock"
fi
if [ -z "$w6_nothonest" ]; then
  pass "Cw6-honest (each block calls the skipped check UNVERIFIED, never verified)"
else
  fail_ "Cw6-honest" "the block never says UNVERIFIED — a skip that reads as a pass — in:$w6_nothonest"
fi
if [ -z "$w6_noguide" ]; then
  pass "Cw6-guided (every block RECOMMENDS the guided walkthrough by name)"
else
  fail_ "Cw6-guided" "no 'check-gate.sh --setup-ci-token' recommendation in:$w6_noguide"
fi
if [ -z "$w6_nocred" ]; then
  pass "Cw6-credential (each names its host's hard-enforcement credential)"
else
  fail_ "Cw6-credential" "no hard-enforcement credential named in:$w6_nocred"
fi
if [ -z "$w6_nowire" ]; then
  pass "Cw6-wiring (github phase-gate steps map the secret LIVE, not as a commented example)"
else
  fail_ "Cw6-wiring" "no executable 'env:' key carrying the secret mapping in:$w6_nowire"
fi

# ── Cw6-strict (adversarial review R-1): a mapped secret must reach a gate
# whose EXIT CODE still counts. 7 of the 10 github templates ran the gate as
#     bash scripts/check-phase-gate.sh 2>/dev/null || echo "…not found — skipping"
# which discards the exit code entirely: a probe showed the gate printing [FAIL]
# and exiting 1 while the step graded GREEN, and the swallow message LIED (the
# script was found — it was the gate's verdict that failed, not the file). Under
# that shape "set the secret and the backstop enforces" is FALSE: the check
# would run with a real credential and its verdict would still be thrown away.
# So the credential wiring and the exit-code contract are ONE pin, not two.
#
# Deliberately scoped to templates that MAP the secret: those are exactly the
# ones making the enforcement claim. `[ ! -f … ] && exit 1` + a bare invocation
# is the strict shape python/typescript/other already used.
w6_swallow=""
if [ "$CPG_COUNT" -gt 0 ]; then
  for f in "${CPG_FILES[@]}"; do
    case "$f" in */ci/github/*) ;; *) continue ;; esac
    grep -Eq '^[[:space:]]*GH_TOKEN:[[:space:]]*\$\{\{' "$f" || continue
    # Any EXECUTABLE gate invocation whose exit status is discarded — `|| echo`,
    # `|| true`, `|| :`, or a trailing `2>/dev/null` swallow on the same line.
    if grep -E '^[^#]*bash scripts/check-phase-gate\.sh' "$f" \
         | grep -Eq '\|\|[[:space:]]*(echo|true|:)'; then
      w6_swallow="$w6_swallow ${f#*/ci/}"
    fi
  done
fi
if [ -z "$w6_swallow" ]; then
  pass "Cw6-strict (every secret-mapping github template lets the gate's EXIT CODE decide the step)"
else
  fail_ "Cw6-strict" "the gate's exit code is discarded (\`|| echo/true/:\`) — a mapped secret cannot enforce anything — in:$w6_swallow"
fi

# ── Cw16 (walk 2026-08-02 ISSUE-016): the tag-deploy environment trap ───────
# The emitted release.yml is TAG-triggered, and enabling GitHub Pages
# auto-creates a `github-pages` environment whose default deployment branch
# policy admits the DEFAULT BRANCH ONLY — so `git push --tags` is rejected
# before any step runs (empty step list, no readable error). The workflow
# cannot self-diagnose it (a rejected run starts no job), so the template's
# job is to NAME the trap and point at the check that can run. Pinned here
# because a comment is the only thing standing between a first-time releaser
# and an unreadable failure — and because the pointer must resolve:
# Cw16-subcommand asserts the named subcommand actually dispatches.
echo "Cw16: the web release template names the tag-deploy environment trap + a runnable check"
REL_WEB_W16="$REPO_ROOT/templates/pipelines/release/github/web.yml"
CHECK_GATE_W16="$REPO_ROOT/scripts/check-gate.sh"
if [ -f "$REL_WEB_W16" ] && [ -f "$CHECK_GATE_W16" ]; then
  pass "Cw16-floor (release/github/web.yml + scripts/check-gate.sh present)"
else
  fail_ "Cw16-floor" "a Cw16 target file is missing — the cases below would be vacuous"
fi
if grep -Eq '^[[:space:]]*#.*walk ISSUE-016' "$REL_WEB_W16"; then
  pass "Cw16-block (the tag-deploy/environment trap is documented at the trigger, as a comment)"
else
  fail_ "Cw16-block" "release/github/web.yml does not name the walk ISSUE-016 tag-deploy environment trap"
fi
w16_missing=""
grep -Fq 'deployment-branch-policies' "$REL_WEB_W16" || w16_missing="$w16_missing api-path"
grep -Fq -- '--release-env-policy' "$REL_WEB_W16"    || w16_missing="$w16_missing subcommand"
grep -Fq "type='tag'" "$REL_WEB_W16"                 || w16_missing="$w16_missing tag-type"
if [ -z "$w16_missing" ]; then
  pass "Cw16-remedy (names the API path, the tag policy type, and the runnable check)"
else
  fail_ "Cw16-remedy" "release/github/web.yml is missing:$w16_missing"
fi
# The pointer must RESOLVE — a comment naming a subcommand that check-gate.sh
# does not dispatch is worse than no comment.
if grep -Eq '^[[:space:]]*--release-env-policy\)' "$CHECK_GATE_W16"; then
  pass "Cw16-subcommand (check-gate.sh actually dispatches --release-env-policy)"
else
  fail_ "Cw16-subcommand" "the template points at scripts/check-gate.sh --release-env-policy but check-gate.sh does not dispatch it"
fi

echo ""
if [ "${SKIPPED:-0}" -gt 0 ]; then
  echo "!! ${SKIPPED} case(s) SKIPPED — skipped != passed."
fi
echo "Results: $PASSED passed, $FAILED failed${SKIPPED:+ (${SKIPPED} skipped)}"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

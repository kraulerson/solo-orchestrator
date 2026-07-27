#!/usr/bin/env bash
# tests/test-bl180-interactive-enforcement.sh — BL-180 regression pin.
#
# THE DEFECT
#   init.sh assigned ENFORCEMENT_LEVEL only inside the
#   `if [ "$NON_INTERACTIVE" = true ]` arm of main() (the
#   `# BL-030: resolve enforcement_level` block). The `else` arm ran only
#   check_prerequisites + collect_project_info, and there is NO interactive
#   enforcement-level prompt anywhere in init.sh — so an interactive scaffold
#   was born with `enforcement_level: ""` in the manifest, and the
#   `if [ "$ENFORCEMENT_LEVEL" = "strict" ]` guard around
#   install-filesystem-gates.sh --install was a silent no-op. The fix is the
#   `# BL-180-ENFORCEMENT-DEFAULT` line hoisted OUT of that dispatch.
#
# WHY THIS TEST SHAPE
#   The defect survived because no test exercised the interactive path far
#   enough to observe a resolved enforcement level: every fed-sequence init.sh
#   test in the repo uses --dry-run, and pre-BL-180 dry_run_summary never
#   printed the level. The companion `# BL-180-DRYRUN-ENFORCEMENT` line in
#   dry_run_summary makes the resolved value observable on STDOUT (log_line
#   writes to the log FILE only and is invisible to a piped test), so the
#   INTERACTIVE resolution can be pinned without a pty. The end-to-end pty
#   scaffold (manifest + filesystem gate on disk) lives in the aggregator-only
#   sibling tests/test-bl180-interactive-scaffold-pty.sh.
#
# HERMETIC: every invocation here carries --dry-run, so init.sh returns from
# main() before create_project — no scaffold, no git, no host CLI, no remote.
#
# MENU POSITIONS ARE DERIVED, NOT HARDCODED. init.sh builds the Platform and
# Primary-language menus from globs (docs/platform-modules/*.md,
# templates/pipelines/release/github/*.yml, templates/pipelines/ci/github/*.yml
# + their `# solo-orchestrator: platforms=` markers). A hardcoded ordinal goes
# stale the moment a template is added or removed — that is exactly how the
# aggregator's TEST 7 fixture broke before BL-136. This test re-derives the
# ordinals from the same globs at run time AND pins the resolved combo in the
# output, so a derivation that drifts fails loudly instead of asserting on the
# wrong project shape.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# init.sh refuses to scaffold from inside the framework repo (the --dry-run
# path skips that guard, but keep the cwd honest anyway).
cd /tmp || exit 1

# ── Menu-ordinal derivation (mirrors collect_project_info) ──────────────
# Platform menu: platform-modules/*.md basenames, then release/github/*.yml
# basenames not already seen, then a literal "other" appended last.
derive_platform_index() {
  local want="$1" idx=0 seen="" f p
  for f in "$REPO_ROOT/docs/platform-modules/"*.md; do
    [ -f "$f" ] || continue
    p="$(basename "$f" .md)"
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"
    idx=$((idx + 1))
    [ "$p" = "$want" ] && { echo "$idx"; return 0; }
  done
  for f in "$REPO_ROOT/templates/pipelines/release/github/"*.yml; do
    [ -f "$f" ] || continue
    p="$(basename "$f" .yml)"
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"
    idx=$((idx + 1))
    [ "$p" = "$want" ] && { echo "$idx"; return 0; }
  done
  idx=$((idx + 1))
  [ "$want" = "other" ] && { echo "$idx"; return 0; }
  return 1
}

# Language menu: ci/github/*.yml basenames whose first-line
# `# solo-orchestrator: platforms=` marker lists the chosen platform (a file
# with no marker is included unconditionally, matching init.sh), then "other".
derive_language_index() {
  local want="$1" platform="$2" idx=0 f l marker csv
  for f in "$REPO_ROOT/templates/pipelines/ci/github/"*.yml; do
    [ -f "$f" ] || continue
    l="$(basename "$f" .yml)"
    [ "$l" = "other" ] && continue
    marker="$(head -1 "$f")"
    csv=""
    case "$marker" in *"# solo-orchestrator: platforms="*) csv="${marker#*platforms=}" ;; esac
    if [ -z "$csv" ]; then
      idx=$((idx + 1))
    else
      case ",$csv," in
        *",$platform,"*) idx=$((idx + 1)) ;;
        *) continue ;;
      esac
    fi
    [ "$l" = "$want" ] && { echo "$idx"; return 0; }
  done
  idx=$((idx + 1))
  [ "$want" = "other" ] && { echo "$idx"; return 0; }
  return 1
}

PLATFORM_IDX="$(derive_platform_index web)" || PLATFORM_IDX=""
LANGUAGE_IDX="$(derive_language_index typescript web)" || LANGUAGE_IDX=""

echo "T0: menu ordinals derived from the current globs/markers"
if [ -n "$PLATFORM_IDX" ] && [ -n "$LANGUAGE_IDX" ]; then
  pass "T0: Platform 'web'=$PLATFORM_IDX, Language 'typescript'=$LANGUAGE_IDX"
else
  fail_ "T0" "could not derive ordinals (platform='$PLATFORM_IDX' language='$LANGUAGE_IDX')"
fi

# Ordered prompt_choice answers for the interactive wizard. prompt_input
# (project name / description / directory) auto-returns its default in a piped
# context WITHOUT consuming a line (helpers-core.sh::prompt_input's `[ ! -t 0 ]`
# guard), so ONLY the prompt_choice selections plus the raw "Continue? [Y/n]"
# read may appear here.
#   Platform=web · Track=standard(2) · Deployment=personal(1) ·
#   Governance=Production Build(2) · Language=typescript · Continue?=Y
feed_interactive() {
  local gov="$1"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$PLATFORM_IDX" 2 1 "$gov" "$LANGUAGE_IDX" Y
}

run_interactive_dry_run() {
  local gov="$1"
  feed_interactive "$gov" | bash "$INIT" --dry-run 2>&1
}

run_noninteractive_dry_run() {
  bash "$INIT" --dry-run --non-interactive \
    --project bl180 --project-dir /tmp/bl180-dryrun --no-remote-creation \
    --platform web --language typescript --track standard "$@" 2>&1
}

# ── T1: the interactive path resolves an enforcement level at all ───────
# Pre-fix this printed "Enforcement: " (empty) — the exact value that flows
# into the manifest and makes the strict-gate guard a no-op.
echo "T1: interactive (piped) dry-run resolves enforcement_level=strict"
out_i="$(run_interactive_dry_run 2)"
if echo "$out_i" | grep -q "^  Enforcement: strict$"; then
  pass "T1: interactive dry-run reports 'Enforcement: strict'"
else
  fail_ "T1" "got: $(echo "$out_i" | grep -c '^  Enforcement:') Enforcement line(s): $(echo "$out_i" | grep '^  Enforcement:' | tr '\n' '|')"
fi

# ── T2: bind T1 to the combo the fed sequence was MEANT to select ───────
# Without this, a drifted ordinal would still satisfy T1 while pinning the
# enforcement level of an entirely different project shape.
echo "T2: fed sequence still selects web / standard / typescript"
if echo "$out_i" | grep -q "Platform: web | Track: standard | Language: typescript"; then
  pass "T2: interactive combo pinned (web / standard / typescript)"
else
  fail_ "T2" "combo drifted — derived ordinals no longer map to web/standard/typescript"
fi

# ── T3: the interactive POC governance answer resolves too ──────────────
# personal + Private POC is the choosable tier (BL-030), i.e. the one where a
# downgrade would be legal if init.sh ever prompted for one. It does not, so
# strict is the only correct resolution — and pre-fix it was "" here as well.
echo "T3: interactive personal + Private POC also resolves to strict"
out_poc="$(run_interactive_dry_run 1)"
if echo "$out_poc" | grep -q "^  Enforcement: strict$"; then
  pass "T3: interactive private-POC dry-run reports 'Enforcement: strict'"
else
  fail_ "T3" "got: $(echo "$out_poc" | grep '^  Enforcement:' | tr '\n' '|')"
fi

# ── T4: NON-INTERACTIVE CONTROL — default is unchanged ──────────────────
echo "T4: non-interactive control (personal, no flag) still strict"
out_n1="$(run_noninteractive_dry_run --deployment personal --gov-mode production)"
if echo "$out_n1" | grep -q "^  Enforcement: strict$"; then
  pass "T4: non-interactive default reports 'Enforcement: strict'"
else
  fail_ "T4" "got: $(echo "$out_n1" | grep '^  Enforcement:' | tr '\n' '|')"
fi

# ── T5: INERTNESS PROOF — the BL-180 default must not clobber a real ────
# non-interactive downgrade. personal + --enforcement-level light
# --confirm-pitfalls is the one shape where a hoisted default placed wrongly
# (or written without the -z guard) would silently re-strictify the operator's
# explicit choice. This is the assertion that proves the new line is inert for
# the non-interactive arm rather than merely asserting it.
echo "T5: non-interactive --enforcement-level light survives (inertness proof)"
out_n2="$(run_noninteractive_dry_run --deployment personal --gov-mode production \
  --enforcement-level light --confirm-pitfalls)"
if echo "$out_n2" | grep -q "^  Enforcement: light$"; then
  pass "T5: non-interactive light is NOT clobbered to strict"
else
  fail_ "T5" "got: $(echo "$out_n2" | grep '^  Enforcement:' | tr '\n' '|')"
fi

# ── T6: forced-strict arm unchanged ─────────────────────────────────────
echo "T6: non-interactive organizational forces strict (flag ignored)"
out_n3="$(run_noninteractive_dry_run --deployment organizational --gov-mode production \
  --enforcement-level light --confirm-pitfalls)"
if echo "$out_n3" | grep -q "^  Enforcement: strict$"; then
  pass "T6: organizational still forced to strict"
else
  fail_ "T6" "got: $(echo "$out_n3" | grep '^  Enforcement:' | tr '\n' '|')"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-vendored-skills-install.sh — verify init.sh installs vendored skills.
#
# Vendored skills live under templates/generated/skills/<name>/ in the framework
# repo and are copied into .claude/skills/<name>/ on project init. Each skill
# must ship its SKILL.md and (when applicable) a NOTICE attribution file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Run init from /tmp to avoid the framework's "refuse to operate inside framework repo" guard.
run_init() {
  local proj="$1"
  ( cd /tmp && bash "$REPO_ROOT/init.sh" --non-interactive \
      --project skillstest --project-dir "$proj" --no-remote-creation \
      --platform web --language typescript \
      --deployment personal --git-host other \
      --remote-url https://example.com/x.git --branch-protection-attested \
      --allow-existing-dir >/dev/null 2>&1 )
}

# T1: session-handoff SKILL.md exists in the framework repo.
echo "T1: framework ships templates/generated/skills/session-handoff/SKILL.md"
if [ -f "$REPO_ROOT/templates/generated/skills/session-handoff/SKILL.md" ]; then
  pass "T1"
else
  fail_ "T1" "vendored SKILL.md missing"
fi

# T2: session-handoff NOTICE exists in the framework repo (MIT attribution).
echo "T2: framework ships templates/generated/skills/session-handoff/NOTICE"
if [ -f "$REPO_ROOT/templates/generated/skills/session-handoff/NOTICE" ]; then
  pass "T2"
else
  fail_ "T2" "vendored NOTICE missing"
fi

# T3: NOTICE references the upstream repo and MIT license.
echo "T3: NOTICE preserves attribution + MIT terms"
if grep -q "mattpocock/skills" "$REPO_ROOT/templates/generated/skills/session-handoff/NOTICE" \
   && grep -q "MIT License" "$REPO_ROOT/templates/generated/skills/session-handoff/NOTICE"; then
  pass "T3"
else
  fail_ "T3" "attribution incomplete"
fi

# T4: init.sh copies the skill into a freshly-init'd project.
echo "T4: init.sh installs .claude/skills/session-handoff/"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ"
if [ -f "$PROJ/.claude/skills/session-handoff/SKILL.md" ] \
   && [ -f "$PROJ/.claude/skills/session-handoff/NOTICE" ]; then
  pass "T4"
else
  fail_ "T4" "skill not installed at .claude/skills/session-handoff/ — SKILL.md=$([ -f "$PROJ/.claude/skills/session-handoff/SKILL.md" ] && echo yes || echo no) NOTICE=$([ -f "$PROJ/.claude/skills/session-handoff/NOTICE" ] && echo yes || echo no)"
fi
rm -rf "$TMP"

# T5: SKILL.md frontmatter has the expected name and an argument-hint.
echo "T5: SKILL.md frontmatter has name=session-handoff + argument-hint"
if head -10 "$REPO_ROOT/templates/generated/skills/session-handoff/SKILL.md" | grep -q "^name: session-handoff$" \
   && head -10 "$REPO_ROOT/templates/generated/skills/session-handoff/SKILL.md" | grep -q "^argument-hint:"; then
  pass "T5"
else
  fail_ "T5" "frontmatter missing or wrong"
fi

# T6: SKILL.md body disambiguates from Solo's Phase 4 HANDOFF.md.
echo "T6: SKILL.md body clarifies vs Phase 4 production HANDOFF.md"
if grep -q "Phase 4 production HANDOFF.md\|production handoff" "$REPO_ROOT/templates/generated/skills/session-handoff/SKILL.md"; then
  pass "T6"
else
  fail_ "T6" "disambiguation missing"
fi

# T7: SKILL.md body requires the resume-prompt section (load-bearing for the
# 'paste this into next session' use case).
echo "T7: SKILL.md mandates a resume prompt"
if grep -qi "resume prompt" "$REPO_ROOT/templates/generated/skills/session-handoff/SKILL.md"; then
  pass "T7"
else
  fail_ "T7" "resume prompt section missing"
fi

# ---- sweep-triage (PR #2 — Solo-original, no NOTICE) ----

# T8: sweep-triage SKILL.md exists.
echo "T8: framework ships templates/generated/skills/sweep-triage/SKILL.md"
if [ -f "$REPO_ROOT/templates/generated/skills/sweep-triage/SKILL.md" ]; then
  pass "T8"
else
  fail_ "T8" "vendored SKILL.md missing"
fi

# T9: sweep-triage has NO NOTICE file. Skill is Solo-original — nothing was
# adapted from upstream, so claiming MIT inheritance would overclaim
# dependency. A NOTICE here would be a bug.
echo "T9: sweep-triage has NO NOTICE (Solo-original, no upstream adaptation)"
if [ ! -f "$REPO_ROOT/templates/generated/skills/sweep-triage/NOTICE" ]; then
  pass "T9"
else
  fail_ "T9" "NOTICE present — overclaims upstream dependency for a Solo-original skill"
fi

# T10: init.sh installs sweep-triage into a freshly-init'd project.
echo "T10: init.sh installs .claude/skills/sweep-triage/"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ"
if [ -f "$PROJ/.claude/skills/sweep-triage/SKILL.md" ]; then
  pass "T10"
else
  fail_ "T10" "skill not installed"
fi
rm -rf "$TMP"

# T11: sweep-triage frontmatter name + argument-hint present.
echo "T11: sweep-triage frontmatter"
if head -10 "$REPO_ROOT/templates/generated/skills/sweep-triage/SKILL.md" | grep -q "^name: sweep-triage$" \
   && head -10 "$REPO_ROOT/templates/generated/skills/sweep-triage/SKILL.md" | grep -q "^argument-hint:"; then
  pass "T11"
else
  fail_ "T11" "frontmatter missing or wrong"
fi

# T12: SKILL.md disambiguates from issue-tracker triage workflow.
echo "T12: sweep-triage clarifies vs per-issue triage workflow"
if grep -q "per-issue triage\|issue tracker" "$REPO_ROOT/templates/generated/skills/sweep-triage/SKILL.md"; then
  pass "T12"
else
  fail_ "T12" "disambiguation from per-issue triage missing"
fi

# T13: SKILL.md cites the canonical BL-029 calibration TRIAGE as the example
# (so readers see a real artifact, not just a template).
echo "T13: sweep-triage cites canonical example artifact"
if grep -q "uat-2026-04-29-bl029-validation/TRIAGE.md\|BL-029 calibration" "$REPO_ROOT/templates/generated/skills/sweep-triage/SKILL.md"; then
  pass "T13"
else
  fail_ "T13" "canonical example missing"
fi

# T14: SKILL.md defines the S1-S5 severity ladder.
echo "T14: sweep-triage defines severity ladder S1-S5"
body="$REPO_ROOT/templates/generated/skills/sweep-triage/SKILL.md"
if grep -q "S1" "$body" && grep -q "S2" "$body" && grep -q "S3" "$body" && grep -q "S5" "$body"; then
  pass "T14"
else
  fail_ "T14" "severity ladder incomplete"
fi

# T15: SKILL.md links to mattpocock's triage as related work.
echo "T15: sweep-triage 'Related work' references mattpocock/skills triage"
if grep -q "mattpocock/skills.*triage\|mattpocock.*triage" "$REPO_ROOT/templates/generated/skills/sweep-triage/SKILL.md"; then
  pass "T15"
else
  fail_ "T15" "related-work reference missing"
fi

# ---- zoom-out (PR #3 — adapted from mattpocock, MIT) ----

# T16: zoom-out SKILL.md exists.
echo "T16: framework ships templates/generated/skills/zoom-out/SKILL.md"
if [ -f "$REPO_ROOT/templates/generated/skills/zoom-out/SKILL.md" ]; then
  pass "T16"
else
  fail_ "T16" "vendored SKILL.md missing"
fi

# T17: zoom-out has a NOTICE (adapted from upstream).
echo "T17: zoom-out NOTICE exists + cites upstream + MIT"
notice="$REPO_ROOT/templates/generated/skills/zoom-out/NOTICE"
if [ -f "$notice" ] && grep -q "mattpocock/skills" "$notice" && grep -q "MIT License" "$notice"; then
  pass "T17"
else
  fail_ "T17" "NOTICE missing or incomplete"
fi

# T18: init.sh installs zoom-out into a freshly-init'd project.
echo "T18: init.sh installs .claude/skills/zoom-out/"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ"
if [ -f "$PROJ/.claude/skills/zoom-out/SKILL.md" ] && [ -f "$PROJ/.claude/skills/zoom-out/NOTICE" ]; then
  pass "T18"
else
  fail_ "T18" "skill not installed (SKILL.md=$([ -f "$PROJ/.claude/skills/zoom-out/SKILL.md" ] && echo yes || echo no) NOTICE=$([ -f "$PROJ/.claude/skills/zoom-out/NOTICE" ] && echo yes || echo no))"
fi
rm -rf "$TMP"

# T19: zoom-out frontmatter preserves upstream's `disable-model-invocation: true`
# flag — the skill must NOT auto-fire; it's explicitly user-invoked.
echo "T19: zoom-out preserves disable-model-invocation flag"
if head -10 "$REPO_ROOT/templates/generated/skills/zoom-out/SKILL.md" | grep -q "^disable-model-invocation: true$"; then
  pass "T19"
else
  fail_ "T19" "frontmatter flag missing — skill would auto-fire instead of being user-invoked"
fi

# T20: zoom-out cites Solo's canonical artifacts (load-bearing adaptation —
# upstream uses 'domain glossary' abstractly; Solo grounds it).
echo "T20: zoom-out cites Solo's canonical artifacts"
if grep -q "PROJECT_BIBLE.md\|phase-state.json\|ADR" "$REPO_ROOT/templates/generated/skills/zoom-out/SKILL.md"; then
  pass "T20"
else
  fail_ "T20" "Solo artifacts not referenced — map would be generic"
fi

# T21: zoom-out cites the Context Health Check / phase-transition use cases
# (so the skill ties into a real Solo decision point, not in isolation).
echo "T21: zoom-out cites Context Health Check / phase-gate use cases"
if grep -qE "Context Health Check|between features|phase transition" "$REPO_ROOT/templates/generated/skills/zoom-out/SKILL.md"; then
  pass "T21"
else
  fail_ "T21" "use-case integration with Solo's workflow missing"
fi

# ---- grill-with-docs (PR #4 — adapted from mattpocock, MIT) ----

# T22: grill-with-docs SKILL.md exists.
echo "T22: framework ships templates/generated/skills/grill-with-docs/SKILL.md"
if [ -f "$REPO_ROOT/templates/generated/skills/grill-with-docs/SKILL.md" ]; then
  pass "T22"
else
  fail_ "T22" "vendored SKILL.md missing"
fi

# T23: grill-with-docs has a NOTICE (adapted from upstream).
echo "T23: grill-with-docs NOTICE exists + cites upstream + MIT"
notice="$REPO_ROOT/templates/generated/skills/grill-with-docs/NOTICE"
if [ -f "$notice" ] && grep -q "mattpocock/skills" "$notice" && grep -q "MIT License" "$notice"; then
  pass "T23"
else
  fail_ "T23" "NOTICE missing or incomplete"
fi

# T24: init.sh installs grill-with-docs into a freshly-init'd project.
echo "T24: init.sh installs .claude/skills/grill-with-docs/"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ"
if [ -f "$PROJ/.claude/skills/grill-with-docs/SKILL.md" ] && [ -f "$PROJ/.claude/skills/grill-with-docs/NOTICE" ]; then
  pass "T24"
else
  fail_ "T24" "skill not installed (SKILL.md=$([ -f "$PROJ/.claude/skills/grill-with-docs/SKILL.md" ] && echo yes || echo no) NOTICE=$([ -f "$PROJ/.claude/skills/grill-with-docs/NOTICE" ] && echo yes || echo no))"
fi
rm -rf "$TMP"

# T25: grill-with-docs frontmatter name.
echo "T25: grill-with-docs frontmatter has name=grill-with-docs"
if head -5 "$REPO_ROOT/templates/generated/skills/grill-with-docs/SKILL.md" | grep -q "^name: grill-with-docs$"; then
  pass "T25"
else
  fail_ "T25" "frontmatter name wrong"
fi

# T26: SKILL.md retargets persistence to PROJECT_BIBLE.md (the load-bearing
# adaptation — upstream uses CONTEXT.md, Solo uses PROJECT_BIBLE.md).
echo "T26: grill-with-docs retargets to PROJECT_BIBLE.md"
body="$REPO_ROOT/templates/generated/skills/grill-with-docs/SKILL.md"
if grep -q "PROJECT_BIBLE.md" "$body" \
   && grep -q "Update PROJECT_BIBLE.md inline\|update PROJECT_BIBLE\.md right there" "$body"; then
  pass "T26"
else
  fail_ "T26" "PROJECT_BIBLE.md not the persistence target"
fi

# T27: SKILL.md cites Solo's ADR location (docs/ADR documentation/, with
# the space — Solo's convention, distinct from upstream's docs/adr/).
echo "T27: grill-with-docs cites Solo's ADR location"
if grep -q "docs/ADR documentation" "$REPO_ROOT/templates/generated/skills/grill-with-docs/SKILL.md"; then
  pass "T27"
else
  fail_ "T27" "Solo's ADR location not cited"
fi

# T28: SKILL.md preserves the 3-of-3 ADR criteria from upstream. These
# are the heart of the skill — must not be lost in adaptation.
echo "T28: grill-with-docs preserves 3-of-3 ADR criteria"
if grep -q "Hard to reverse" "$body" \
   && grep -q "Surprising without context" "$body" \
   && grep -qE "[Rr]eal trade-off" "$body"; then
  pass "T28"
else
  fail_ "T28" "3-of-3 criteria not preserved"
fi

# T29: SKILL.md composes with Solo's structured-decision machinery
# (escalate-to-user.sh / pending-approval.json) — the load-bearing
# integration that turns "I'll assume" into "I'll escalate."
echo "T29: grill-with-docs escalates user-judgment forks via escalate-to-user.sh"
if grep -q "escalate-to-user.sh" "$body" && grep -q "pending-approval.json" "$body"; then
  pass "T29"
else
  fail_ "T29" "structured-decision composition missing"
fi

# T30: SKILL.md cross-references tests, not just code (Solo's TDD addition
# to upstream's code-only cross-reference move).
echo "T30: grill-with-docs cross-references tests"
if grep -qE "(cross-reference|tests).*tests|tests.*(source of truth|cross-reference)" "$body"; then
  pass "T30"
else
  fail_ "T30" "test cross-reference missing"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

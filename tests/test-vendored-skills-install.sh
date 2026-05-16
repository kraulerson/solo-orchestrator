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

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

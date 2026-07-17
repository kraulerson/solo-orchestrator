#!/usr/bin/env bash
# tests/test-bl119-stale-editmsg.sh — BL-119 (+ BL-087 fold-in): the strict
# terminal gate must not classify a commit by the PREVIOUS commit's message.
#
# WHY THIS EXISTS (Dogfood-2 finding F-DF2-006, High)
#   .git/hooks/pre-commit -> framework-gate.sh (strict) ran
#   `pre-commit-gate.sh --terminal-mode`, which read the commit subject from
#   .git/COMMIT_EDITMSG. At PRE-COMMIT time git has not written the new message
#   — the file still holds a PREVIOUS commit's subject. After any landed `feat:`
#   commit whose Build Loop closed, the stale `feat(...)` subject made the gate
#   demand an active Build Loop for EVERY subsequent commit — docs:, chore:,
#   test:, pure Markdown — and the repository became uncommittable (the gate's
#   own printed remedy is refused on organizational/sponsored tiers, and the
#   listed escapes are forbidden). The walk was halted by exactly this.
#
#   The fix removes the message classifier from plain --terminal-mode
#   (# BL-119-NO-MSG-AT-PRECOMMIT): pre-commit is message-blind by git's design;
#   the message-scoped checks (BL-072 TDD + BL-006 Build-Loop) already run at
#   the COMMIT-MSG surface (`--terminal-mode --tdd-only`) where COMMIT_EDITMSG
#   is CURRENT. Fold-in BL-087(1): bl006_terminal_enforce gains an explicit
#   in-framework-repo graceful pass (# BL-087-MOTHERSHIP-PASS) — without it,
#   a commit-msg hook installed in the framework repo itself hard-blocks every
#   feat:/fix: commit via guard_not_in_framework (helpers-core.sh), because the
#   framework repo DOES contain scripts/process-checklist.sh so the "no
#   checklist -> no-op" safety layer does not apply.
#
# CASES
#   T-docs-after-feat-commits    E2E through the REAL hook chain: strict scratch
#                                project, framework-gate.sh installed by the REAL
#                                install-filesystem-gates.sh --install, STALE
#                                `feat(...)` subject in .git/COMMIT_EDITMSG, then
#                                a REAL `git commit -m "docs: ..."` -> must LAND.
#   T-feat-gated-at-commitmsg    no-regression pin: the commit-msg surface
#                                (--terminal-mode --tdd-only) with a CURRENT
#                                feat: subject and no Build Loop still BLOCKS —
#                                message enforcement lives there, with the right
#                                message, not at pre-commit with the wrong one.
#   T-framework-repo-graceful    BL-087: from a framework-repo lookalike (the
#                                guard_not_in_framework detection signature:
#                                init.sh with the canonical header + a
#                                templates/generated/ dir), the commit-msg
#                                surface passes GRACEFULLY (rc=0 + a note),
#                                instead of hard-blocking via the guard.
#
# REGISTRATION: never runs init.sh, not an aggregator -> registered in BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit fast lane.
#
# Hermetic: mktemp workdirs, local git identity, GITHUB_BASE_REF unset, the
# fixture remote URL is never contacted. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# BL119_REPO_OVERRIDE: run against an alternate framework tree (same convention
# as BL112_REPO_OVERRIDE in test-bl112-commit-enforcement.sh — used by mutation
# harnesses and out-of-tree dry runs). Default: the repo this file lives in.
REPO_ROOT="${BL119_REPO_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (framework-gate.sh and the checklist state machine read it)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_strict_proj <dir>: a strict-enforcement scratch project with the REAL
# framework-gate chain installed (shebang-only pre-commit + the appended gate
# block — the soif fallback region is deliberately absent so no semgrep run
# slows the case; BL-119 lives entirely in the framework-gate arm) and the REAL
# commit-msg TDD/BL-006 block emitted from hook-templates.sh.
mk_strict_proj() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/scripts/lib"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl119@test.invalid" \
      && git config user.name  "BL-119 Test" \
      && echo "# scratch" > README.md \
      && git add README.md \
      && git commit -q -m "chore: init" \
      && git remote add origin https://example.invalid/x.git ) || return 1
  cat > "$d/.claude/manifest.json" <<'EOF'
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  cat > "$d/.claude/phase-state.json" <<'EOF'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
EOF
  cat > "$d/.claude/process-state.json" <<'EOF'
{"phase2_init":{"steps_completed":["remote_repo_created"],"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
EOF
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/pre-commit-gate.sh"   "$d/scripts/"
  # install-filesystem-gates.sh is shipped downstream by init.sh; the emitted
  # framework-gate re-invokes it for __record_block/__record_pass audit rows
  # (verifier fixture-fidelity finding — without it those rows are dead code
  # in the fixture).
  cp "$REPO_ROOT/scripts/install-filesystem-gates.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" \
     "$REPO_ROOT/scripts/lib/tdd-classify.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh" "$d/scripts/pre-commit-gate.sh" \
           "$d/scripts/install-filesystem-gates.sh"
  # REAL gate installer, exactly as a scaffold runs it.
  bash "$REPO_ROOT/scripts/install-filesystem-gates.sh" --install "$d" >/dev/null 2>&1 || return 1
  [ -x "$d/.git/hooks/framework-gate.sh" ] || return 1
  # REAL commit-msg block (the soif TDD/BL-006 region from hook-templates.sh).
  printf '%s\n' '#!/usr/bin/env bash' > "$d/.git/hooks/commit-msg"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/scripts/lib/hook-templates.sh"
  soif_emit_tdd_commitmsg_block >> "$d/.git/hooks/commit-msg"
  chmod +x "$d/.git/hooks/commit-msg"
}

# ── T-docs-after-feat-commits ────────────────────────────────────────────────
echo "=== T-docs-after-feat-commits ==="
P1="$TOPTMP/proj1"
if ! mk_strict_proj "$P1"; then
  fail_ "T-docs-after-feat-commits" "fixture setup failed"
else
  # The BL-119 precondition: a previously-landed feat commit's subject is still
  # sitting in COMMIT_EDITMSG when the next pre-commit hook runs.
  printf 'feat(reader): render pane\n' > "$P1/.git/COMMIT_EDITMSG"
  ( cd "$P1" && echo "more docs" >> README.md && git add README.md )
  head_before="$(cd "$P1" && git rev-parse HEAD)"
  out="$( cd "$P1" && git commit -m "docs: update readme" 2>&1 )"
  rc=$?
  head_after="$(cd "$P1" && git rev-parse HEAD)"
  if [ "$rc" -ne 0 ]; then
    fail_ "T-docs-after-feat-commits" "docs-only commit after a feat commit was BLOCKED (rc=$rc) — the stale-COMMIT_EDITMSG classifier bricked the repo: $(printf '%s' "$out" | grep -E 'Block reason|FAIL' | head -1)"
  elif [ "$head_before" = "$head_after" ]; then
    fail_ "T-docs-after-feat-commits" "git exited 0 but HEAD did not move"
  else
    pass "T-docs-after-feat-commits"
  fi
fi

# ── T-stale-msg-not-fed-to-lints ─────────────────────────────────────────────
# Adversarial-verifier finding (2026-07-17): the classifier was not the only
# stale-message consumer — plain --terminal-mode ALSO piped $COMMIT_MSG into
# lint-backlog-references --pre-commit-mode, so a PREVIOUS commit's subject
# citing a bogus BL id blocked the CURRENT innocent commit (BL-119's defect
# class, narrower reach: the lint must be present project-locally — framework-
# context repos and hand-copied setups). Message-scoped checks belong to
# surfaces that see the CURRENT message.
echo "=== T-stale-msg-not-fed-to-lints ==="
P4="$TOPTMP/proj4"
if ! mk_strict_proj "$P4"; then
  fail_ "T-stale-msg-not-fed-to-lints" "fixture setup failed"
else
  cp "$REPO_ROOT/scripts/lint-backlog-references.sh" "$P4/scripts/"
  chmod +x "$P4/scripts/lint-backlog-references.sh"
  printf '## BL-001: exists\n\n**Status:** Open\n' > "$P4/solo-orchestrator-backlog.md"
  # The stale previous-commit subject cites a BL id that does not exist.
  printf 'docs: previous commit citing BL-9999\n' > "$P4/.git/COMMIT_EDITMSG"
  ( cd "$P4" && echo "innocent" >> README.md && git add README.md )
  out="$( cd "$P4" && git commit -m "docs: innocent current commit" 2>&1 )"
  rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "backlog-references"; then
    fail_ "T-stale-msg-not-fed-to-lints" "the PREVIOUS commit's message was fed to the backlog-references lint and blocked the CURRENT commit (rc=$rc)"
  elif [ "$rc" -ne 0 ]; then
    fail_ "T-stale-msg-not-fed-to-lints" "commit blocked for an unexpected reason (rc=$rc): $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  else
    pass "T-stale-msg-not-fed-to-lints"
  fi
fi

# ── T-feat-gated-at-commitmsg ────────────────────────────────────────────────
echo "=== T-feat-gated-at-commitmsg ==="
P2="$TOPTMP/proj2"
if ! mk_strict_proj "$P2"; then
  fail_ "T-feat-gated-at-commitmsg" "fixture setup failed"
else
  printf 'feat: add thing\n' > "$P2/.git/COMMIT_EDITMSG"
  ( cd "$P2" && echo "package main" > src.go && git add src.go )
  out="$( cd "$P2" && bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only 2>&1 )"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "T-feat-gated-at-commitmsg" "a feat: commit with no Build Loop PASSED the commit-msg surface — dropping the pre-commit message check removed the only message gate"
  elif ! printf '%s' "$out" | grep -qi "build loop"; then
    fail_ "T-feat-gated-at-commitmsg" "blocked, but not by the Build-Loop message check (rc=$rc): $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  else
    pass "T-feat-gated-at-commitmsg"
  fi
fi

# ── T-framework-repo-graceful ────────────────────────────────────────────────
echo "=== T-framework-repo-graceful ==="
P3="$TOPTMP/lookalike"
mkdir -p "$P3/scripts/lib" "$P3/templates/generated"
( cd "$P3" \
    && git init -q \
    && git config user.email "bl119@test.invalid" \
    && git config user.name  "BL-119 Test" ) || true
# The guard_not_in_framework detection signature (helpers-core.sh):
# top-level init.sh containing the canonical header + templates/generated/.
printf '#!/usr/bin/env bash\n# Solo Orchestrator — Project Initialization Script\n' > "$P3/init.sh"
cp "$REPO_ROOT/scripts/process-checklist.sh" "$P3/scripts/"
cp "$REPO_ROOT/scripts/pre-commit-gate.sh"   "$P3/scripts/"
cp "$REPO_ROOT/scripts/lib/helpers.sh" \
   "$REPO_ROOT/scripts/lib/helpers-core.sh" \
   "$REPO_ROOT/scripts/lib/helpers-full.sh" \
   "$REPO_ROOT/scripts/lib/tdd-classify.sh" "$P3/scripts/lib/"
chmod +x "$P3/scripts/process-checklist.sh" "$P3/scripts/pre-commit-gate.sh"
printf 'feat: framework work\n' > "$P3/.git/COMMIT_EDITMSG"
out="$( cd "$P3" && bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only 2>&1 )"
rc=$?
if [ "$rc" -ne 0 ]; then
  fail_ "T-framework-repo-graceful" "the commit-msg surface HARD-BLOCKS inside a framework-repo tree (rc=$rc) — BL-087: a commit-msg hook installed in the framework repo bricks its feat:/fix: commits: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
elif ! printf '%s' "$out" | grep -qi "framework repo"; then
  fail_ "T-framework-repo-graceful" "passed, but silently — the graceful pass must SAY it detected the framework repo (a silent pass is indistinguishable from a gate that never ran)"
else
  pass "T-framework-repo-graceful"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

#!/usr/bin/env bash
# tests/test-delta-wp0-inherited-predicates.sh — Delta Track WP0.
#
# WHAT THIS PINS AND WHY IT EXISTS FIRST.
# The post-1.0 delta track is being built ON TOP OF three predicates that
# already ship in core. This suite pins their CURRENT behaviour BEFORE any
# delta code lands, so that a later regression is attributed to the change
# that caused it instead of being discovered as "the framework stopped
# enforcing X sometime last month".
#
# Pins (all on PHASE-4 fixtures, all asserted on EXIT CODES — the printed
# [FAIL]/[WARN]/[OK] labels are cosmetic in this codebase and must never be
# the assertion):
#
#   (a) scripts/process-checklist.sh::check_commit_message blocks a `feat:`
#       commit with no active Build Loop at current_phase 4. Its phase guard
#       is `current_phase -lt 2 -> exit 0`, i.e. it is LIVE at 2, 3 and 4.
#       This is the single mechanism by which the delta-era FEATURE class
#       inherits the Build Loop with no new gate. If that guard is ever
#       narrowed to phase-2-only, W1/W2 go RED.
#         MUTATION PROOF: widen the guard to `-lt 5` (inert at phase 4)
#         -> W1 and W2 RED. Restore -> GREEN.
#         THE PIN TARGET IS check_commit_message, NOT check_commit_ready.
#         check_commit_ready's Build Loop arm is `[ "$current_phase" -eq 2 ]`
#         and is therefore INERT at phase 4 — W4 asserts that inertness
#         directly so nobody "moves the pin" onto a surface where it would
#         pass vacuously.
#         W4 MUST REACH THE ARM TO MEAN ANYTHING. check_commit_ready exits 0
#         early and SILENTLY when nothing is staged (`git diff --cached
#         --name-only` is empty — which is what a non-git fixture dir yields)
#         and again when every staged path is docs/dep-manifest. The first
#         cut of W4 used a bare mktemp dir and so asserted the no-staged-files
#         short-circuit while claiming to assert the phase fall-through: the
#         `-eq 2` -> `-ge 2` drift it exists to catch survived it (WP0
#         adversarial review, R-WP0-1). Hence the git-backed fixture with a
#         staged SOURCE file and an explicit `--subject "feat: ..."`, plus a
#         staged-files PRECONDITION that fails loudly rather than passing
#         vacuously, plus W4b.
#         MUTATION PROOF (W4): widen BOTH check_commit_ready phase arms
#         `-eq 2` -> `-ge 2` (the "consolidation" drift) -> W4 RED; W4b stays
#         green, since 2 satisfies `-ge 2` either way. Restore -> GREEN.
#
#   (b) scripts/test-gate.sh::check_phase_gate exits 1 on `SEV-1 | Open`,
#       `SEV-2 | Open` and `SEV-2 | Deferred` rows. This gate is reached at
#       current_phase >= 3 (so including 4) from scripts/check-phase-gate.sh,
#       and every scaffolded CI pipeline runs that — so it is the delta era's
#       mechanical, CI-time bug block.
#         MUTATION PROOF: drop/neuter the sev2_deferred arm -> W7 RED.
#         Restore -> GREEN.
#       W8/W9/W10 are the discriminating controls: without them a gate that
#       exited 1 unconditionally would satisfy W5-W7.
#
#   (c) scripts/process-checklist.sh::_set_current_phase_min never downgrades
#       (`[ "$cur" -lt "$target" ]`). The delta era's era-routing invariant is
#       `active_delta => current_phase == 4`, which only holds if nothing can
#       walk current_phase backwards. Driven through a REAL CLI path —
#       `--start-phase3`, whose start_phase3 calls the setter with target 3.
#         MUTATION PROOF: invert the comparison to `-gt` -> W11 RED (a 4->2
#         style downgrade lands) and W12 RED too. Restore -> GREEN.
#
# Hermetic: every fixture is a mktemp -d outside the repo tree, with a
# PATH-shadowed `gh` stub so the GitHub-Issues arm of check_phase_gate is
# never consulted and no network is touched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKLIST="$REPO_ROOT/scripts/process-checklist.sh"
TEST_GATE="$REPO_ROOT/scripts/test-gate.sh"
BUGS_TMPL="$REPO_ROOT/templates/generated/bugs.tmpl"

# Fixture git ops are not used here, but an inherited GITHUB_BASE_REF changes
# how some helpers resolve a diff base — keep the fixtures blind to CI env.
unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
FIXTURE=""

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

teardown() {
  if [ -n "$FIXTURE" ] && [ -d "$FIXTURE" ]; then
    rm -rf "$FIXTURE"
  fi
  FIXTURE=""
}
trap teardown EXIT

# --- Fixture helpers ---------------------------------------------------

# A hermetic project dir: never inside the repo tree, and carrying a `gh`
# stub that fails every invocation. check_phase_gate's GitHub arm is guarded
# by `gh auth status`, so a failing stub keeps that arm shut deterministically
# whether or not the host has a real, authenticated gh.
new_fixture() {
  FIXTURE=$(mktemp -d)
  mkdir -p "$FIXTURE/.claude" "$FIXTURE/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$FIXTURE/bin/gh"
  chmod +x "$FIXTURE/bin/gh"
}

seed_phase() {
  # $1 = current_phase value
  printf '%s\n' "{\"current_phase\": $1, \"project\": \"delta-wp0\"}" \
    > "$FIXTURE/.claude/phase-state.json"
}

# No active Build Loop, and no closed-loop receipt — the state a project sits
# in between features.
seed_no_build_loop() {
  cat > "$FIXTURE/.claude/process-state.json" <<'JSON'
{
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"session_id": null, "step": 0, "steps_completed": [], "started_at": null},
  "phase1_architecture": {"steps_completed": [], "started_at": null},
  "phase3_validation": {"steps_completed": [], "started_at": null},
  "phase4_release": {"steps_completed": [], "started_at": null},
  "phase2_init": {"steps_completed": [], "verified": true}
}
JSON
}

# BUGS.md built from the SHIPPED template, so the fixture carries the exact
# table shape check_phase_gate parses (its boilerplate is part of the pin —
# see W10). $1 = a data row to append, or "" for the bare template.
seed_bugs() {
  if [ ! -f "$BUGS_TMPL" ]; then
    echo "FATAL: bug tracker template not found at $BUGS_TMPL" >&2
    exit 1
  fi
  cp "$BUGS_TMPL" "$FIXTURE/BUGS.md"
  if [ -n "$1" ]; then
    printf '%s\n' "$1" >> "$FIXTURE/BUGS.md"
  fi
}

# check_phase_gate's feature-completeness arm WARNs (exit 2) when FEATURES.md
# is missing, which would mask the difference between "blocked" and "clear".
# Give the controls a real one so rc=0 is reachable.
seed_features() {
  printf '%s\n' '# Features' '' '## Dark mode' '' 'Ships a dark theme.' \
    > "$FIXTURE/FEATURES.md"
}

# Make the fixture a real git repo with ONE STAGED SOURCE FILE, so that
# check_commit_ready is driven past BOTH of its silent early exits — the
# no-staged-files short-circuit and the docs/dep-manifest exemption — and
# actually reaches its `[ "$current_phase" -eq 2 ]` arms. `src/` is chosen
# because it matches the classifier's source_dirs; a .md file here would exit
# 0 at the docs exemption and re-create the vacuous assertion this replaces.
# Fixture-local git identity per house rules; GITHUB_BASE_REF is already unset
# at suite start. Nothing is ever committed and no remote is configured.
seed_git_staged_source() {
  mkdir -p "$FIXTURE/src"
  printf '%s\n' 'def main():' '    return 0' > "$FIXTURE/src/main.py"
  ( cd "$FIXTURE" \
    && git init -q . \
    && git config user.email "wp0-fixture@example.invalid" \
    && git config user.name "WP0 Fixture" \
    && git add src/main.py ) > "$FIXTURE/git.log" 2>&1
}

# The precondition W4/W4b assert before trusting their own result. An empty
# staged set means check_commit_ready exits 0 upstream of everything those
# tests claim to exercise — the failure mode must be LOUD, not a pass.
fixture_has_staged_files() {
  local staged
  staged=$( cd "$FIXTURE" && git diff --cached --name-only 2>/dev/null || true )
  [ -n "$staged" ]
}

# --- Runners (exit code is the ONLY signal) ----------------------------

rc_checklist() {
  # Runs process-checklist.sh in the fixture; echoes the exit code.
  local rc=0
  ( cd "$FIXTURE" && PATH="$FIXTURE/bin:$PATH" bash "$CHECKLIST" "$@" ) \
    > "$FIXTURE/out.log" 2>&1 || rc=$?
  echo "$rc"
}

rc_gate() {
  # Runs test-gate.sh --check-phase-gate in the fixture; echoes the exit code.
  local rc=0
  ( cd "$FIXTURE" && PATH="$FIXTURE/bin:$PATH" bash "$TEST_GATE" --check-phase-gate ) \
    > "$FIXTURE/gate.log" 2>&1 || rc=$?
  echo "$rc"
}

current_phase_of_fixture() {
  jq -r '.current_phase' "$FIXTURE/.claude/phase-state.json"
}

# --- (a) check_commit_message is LIVE at phase 4 -----------------------

w1_feat_blocked_at_phase4() {
  new_fixture; seed_phase 4; seed_no_build_loop
  local rc; rc=$(rc_checklist --check-commit-message "feat: add dark mode")
  if [ "$rc" = "1" ]; then
    pass "W1: check_commit_message blocks 'feat:' with no Build Loop at phase 4 (rc=1)"
  else
    fail_ "W1" "expected rc=1 at current_phase 4, got rc=$rc"
  fi
  teardown
}

w2_scoped_feat_blocked_at_phase4() {
  new_fixture; seed_phase 4; seed_no_build_loop
  local rc; rc=$(rc_checklist --check-commit-message "feat(ui): add dark mode")
  if [ "$rc" = "1" ]; then
    pass "W2: check_commit_message blocks scoped 'feat(ui):' at phase 4 (rc=1)"
  else
    fail_ "W2" "expected rc=1 at current_phase 4, got rc=$rc"
  fi
  teardown
}

w3_non_feat_allowed_at_phase4() {
  new_fixture; seed_phase 4; seed_no_build_loop
  local rc; rc=$(rc_checklist --check-commit-message "fix: export crashes on unicode")
  if [ "$rc" = "0" ]; then
    pass "W3: control — a non-feat subject is not blocked at phase 4 (rc=0)"
  else
    fail_ "W3" "expected rc=0 for a 'fix:' subject at phase 4, got rc=$rc"
  fi
  teardown
}

w4_check_commit_ready_is_inert_at_phase4() {
  # The reason the pin lives on check_commit_message. check_commit_ready's
  # Build Loop arm is phase-2-only, so on THIS fixture — phase 4, a STAGED
  # SOURCE FILE, and a feat SUBJECT, i.e. every condition that would make the
  # arm fire at phase 2 — it still lets the commit through. A pin written
  # against it would enforce nothing in the delta era. If this ever starts
  # returning 1, the delta design's C3 reasoning has changed and must be
  # re-derived, not "fixed".
  new_fixture; seed_phase 4; seed_no_build_loop; seed_git_staged_source
  if ! fixture_has_staged_files; then
    fail_ "W4" "fixture precondition failed — nothing staged, so check_commit_ready would exit 0 at its no-staged-files short-circuit and this assertion would be vacuous"
    teardown; return
  fi
  local rc; rc=$(rc_checklist --check-commit-ready --subject "feat: add dark mode")
  if [ "$rc" = "0" ]; then
    pass "W4: check_commit_ready is INERT at phase 4 (rc=0) — pin target stays check_commit_message"
  else
    fail_ "W4" "expected rc=0 (phase fall-through) from check_commit_ready at phase 4, got rc=$rc"
  fi
  teardown
}

w4b_check_commit_ready_arm_is_reachable_at_phase2() {
  # Anti-vacuity for W4, and the half that makes W4's rc=0 informative: the
  # SAME fixture at phase 2 — where the arm IS live — is refused (rc=1,
  # no Build Loop). That proves execution genuinely reaches the phase-scoped
  # Build Loop arm on this fixture, so W4's rc=0 at phase 4 is the arm being
  # SKIPPED and not an upstream short-circuit.
  # Under the `-eq 2` -> `-ge 2` drift this stays green while W4 goes red,
  # which is the whole point: measure the boundary from both sides.
  new_fixture; seed_phase 2; seed_no_build_loop; seed_git_staged_source
  if ! fixture_has_staged_files; then
    fail_ "W4b" "fixture precondition failed — nothing staged, so check_commit_ready would exit 0 at its no-staged-files short-circuit and this assertion would be vacuous"
    teardown; return
  fi
  local rc; rc=$(rc_checklist --check-commit-ready --subject "feat: add dark mode")
  if [ "$rc" = "1" ]; then
    pass "W4b: the same fixture at phase 2 IS refused (rc=1) — the arm is genuinely reached"
  else
    fail_ "W4b" "expected rc=1 at current_phase 2 (Build Loop arm live), got rc=$rc"
  fi
  teardown
}

# --- (b) check_phase_gate blocks the SEV rows --------------------------

w5_sev1_open_blocks() {
  new_fixture; seed_phase 4; seed_features
  seed_bugs '| 1 | SEV-1 | Open | auth | Crash on login | Session 1 | Fix Now | | |'
  local rc; rc=$(rc_gate)
  if [ "$rc" = "1" ]; then
    pass "W5: check_phase_gate blocks on a 'SEV-1 | Open' row (rc=1)"
  else
    fail_ "W5" "expected rc=1 for SEV-1 Open, got rc=$rc"
  fi
  teardown
}

w6_sev2_open_blocks() {
  new_fixture; seed_phase 4; seed_features
  seed_bugs '| 1 | SEV-2 | Open | export | Form submits wrong data | Session 1 | Fix Now | | |'
  local rc; rc=$(rc_gate)
  if [ "$rc" = "1" ]; then
    pass "W6: check_phase_gate blocks on a 'SEV-2 | Open' row (rc=1)"
  else
    fail_ "W6" "expected rc=1 for SEV-2 Open, got rc=$rc"
  fi
  teardown
}

w7_sev2_deferred_blocks() {
  # The mutation-proof target for pin (b): neuter the sev2_deferred arm in
  # check_phase_gate and this is the test that goes RED.
  new_fixture; seed_phase 4; seed_features
  seed_bugs '| 1 | SEV-2 | Deferred | export | Layout broken on one platform | Session 1 | Defer | | |'
  local rc; rc=$(rc_gate)
  if [ "$rc" = "1" ]; then
    pass "W7: check_phase_gate blocks on a 'SEV-2 | Deferred' row (rc=1)"
  else
    fail_ "W7" "expected rc=1 for SEV-2 Deferred, got rc=$rc"
  fi
  teardown
}

w8_sev3_open_warns_not_blocks() {
  # Discriminating control #1. SEV-3 Open is the ATTESTATION arm: it must
  # reach the warnings exit (2), never the blocking exit (1). rc=0 would mean
  # the SEV-3 warning had been lost; rc=1 would mean SEV-3 had been promoted
  # to a blocker.
  new_fixture; seed_phase 4; seed_features
  seed_bugs '| 1 | SEV-3 | Open | ui | Tooltip truncated | Session 1 | Defer | | |'
  local rc; rc=$(rc_gate)
  if [ "$rc" = "2" ]; then
    pass "W8: control — 'SEV-3 | Open' warns (rc=2), it does not block"
  else
    fail_ "W8" "expected rc=2 (warnings) for SEV-3 Open, got rc=$rc"
  fi
  teardown
}

w9_no_blocking_rows_is_clear() {
  # Discriminating control #2: the gate CAN come back clear, so W5-W7 are not
  # satisfied by a gate that is simply red for everyone.
  new_fixture; seed_phase 4; seed_features
  seed_bugs '| 1 | SEV-3 | Fixed | ui | Tooltip truncated | Session 1 | Fix Now | abc1234 | Session 2 |'
  local rc; rc=$(rc_gate)
  if [ "$rc" = "0" ]; then
    pass "W9: control — no open/deferred blocking rows, gate is clear (rc=0)"
  else
    fail_ "W9" "expected rc=0 with only a Fixed SEV-3 row, got rc=$rc"
  fi
  teardown
}

w10_shipped_template_has_no_false_positive() {
  # Discriminating control #3. check_phase_gate counts with line-scoped greps
  # ('SEV-N' ... 'Open'/'Deferred' on ONE line), and the shipped template's
  # own Severity/Status guide tables mention every severity AND every status.
  # They currently never collide on a single line. If someone reformats the
  # template so they do, every scaffolded project starts life with a blocked
  # bug gate — this test is the canary for that.
  new_fixture; seed_phase 4; seed_features
  seed_bugs ''
  local rc; rc=$(rc_gate)
  if [ "$rc" = "0" ]; then
    pass "W10: control — the shipped bugs template with zero data rows is clear (rc=0)"
  else
    fail_ "W10" "expected rc=0 for the bare shipped template, got rc=$rc"
  fi
  teardown
}

# --- (c) _set_current_phase_min never downgrades -----------------------

w11_phase4_is_not_downgraded() {
  # Driven through a real CLI path: --start-phase3 -> start_phase3 ->
  # _set_current_phase_min 3. With no BUGS.md the bug gate returns 2
  # (no tracking source), which start_phase3 treats as non-blocking, so the
  # setter is genuinely reached — W12 is the proof of that.
  new_fixture; seed_phase 4; seed_no_build_loop
  local rc; rc=$(rc_checklist --start-phase3)
  local after; after=$(current_phase_of_fixture)
  if [ "$rc" = "0" ] && [ "$after" = "4" ]; then
    pass "W11: --start-phase3 at phase 4 leaves current_phase at 4 (no downgrade)"
  else
    fail_ "W11" "expected rc=0 and current_phase 4, got rc=$rc current_phase=$after"
  fi
  teardown
}

w12_lower_phase_is_advanced() {
  # Anti-vacuity for W11: proves the driven CLI path really reaches
  # _set_current_phase_min. Without this, W11 would still pass if
  # --start-phase3 bailed out before the setter for an unrelated reason.
  new_fixture; seed_phase 1; seed_no_build_loop
  local rc; rc=$(rc_checklist --start-phase3)
  local after; after=$(current_phase_of_fixture)
  if [ "$rc" = "0" ] && [ "$after" = "3" ]; then
    pass "W12: --start-phase3 at phase 1 advances current_phase to 3 (setter is reached)"
  else
    fail_ "W12" "expected rc=0 and current_phase 3, got rc=$rc current_phase=$after"
  fi
  teardown
}

# --- Run all -----------------------------------------------------------

echo "== tests/test-delta-wp0-inherited-predicates.sh =="
w1_feat_blocked_at_phase4
w2_scoped_feat_blocked_at_phase4
w3_non_feat_allowed_at_phase4
w4_check_commit_ready_is_inert_at_phase4
w4b_check_commit_ready_arm_is_reachable_at_phase2
w5_sev1_open_blocks
w6_sev2_open_blocks
w7_sev2_deferred_blocks
w8_sev3_open_warns_not_blocks
w9_no_blocking_rows_is_clear
w10_shipped_template_has_no_false_positive
w11_phase4_is_not_downgraded
w12_lower_phase_is_advanced

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

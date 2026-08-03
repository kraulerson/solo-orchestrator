#!/usr/bin/env bash
# tests/test-check-commit-message.sh — unit tests for
# `scripts/process-checklist.sh --check-commit-message "MSG"` (BL-006).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# --- Helpers: seed a tempdir .claude/ state ---

seed_phase() {
  # $1 = phase number
  mkdir -p "$TMPDIR_T/.claude"
  cat > "$TMPDIR_T/.claude/phase-state.json" <<JSON
{"current_phase": $1, "project": "unit-test"}
JSON
}

seed_process_state() {
  # $1 = feature value (e.g., null or "myfeat")
  # $2 = space-separated list of completed steps (may be empty)
  local feature="$1"
  local completed="$2"
  local completed_json="[]"
  if [ -n "$completed" ]; then
    completed_json=$(printf '%s\n' $completed | jq -R . | jq -sc .)
  fi
  local feature_json
  if [ "$feature" = "null" ]; then
    feature_json="null"
  else
    feature_json="\"$feature\""
  fi
  cat > "$TMPDIR_T/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {
    "feature": $feature_json,
    "step": 0,
    "steps_completed": $completed_json,
    "started_at": null
  },
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
}

run_check() {
  # $1 = MSG to pass. Echoes "EXIT|STDERR" (one line joined).
  local msg="$1"
  local rc=0
  local err
  err=$( cd "$TMPDIR_T" && "$SCRIPT" --check-commit-message "$msg" 2>&1 >/dev/null ) || rc=$?
  err=$(printf '%s' "$err" | tr '\n' ' ')
  echo "$rc|$err"
}

setup() {
  TMPDIR_T=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_T"
}

# --- Tests ---

u1_phase_0_feat() {
  setup; seed_phase 0; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U1" "expected exit 0 in phase 0, got: $out"; teardown; return; }
  pass "U1: Phase 0 — feat: exits 0 (phase gate)"
  teardown
}

u2_phase_1_feat() {
  setup; seed_phase 1; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U2" "expected exit 0 in phase 1, got: $out"; teardown; return; }
  pass "U2: Phase 1 — feat: exits 0 (phase gate)"
  teardown
}

u3_phase_2_no_feature_feat() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U3" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"start-feature"* ]] || { fail_ "U3" "stderr missing --start-feature guidance: $out"; teardown; return; }
  pass "U3: Phase 2, no feature — feat: exit 1 + start-feature remediation"
  teardown
}

u4_non_feat_fix() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "fix(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U4" "expected exit 0 for fix:, got: $out"; teardown; return; }
  pass "U4: fix: — exit 0 (non-feat)"
  teardown
}

u5_non_feat_chore() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "chore: bump")
  [ "${out%%|*}" = "0" ] || { fail_ "U5" "expected exit 0 for chore:, got: $out"; teardown; return; }
  pass "U5: chore: — exit 0"
  teardown
}

u6_non_feat_docs() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "docs: typo")
  [ "${out%%|*}" = "0" ] || { fail_ "U6" "expected exit 0 for docs:, got: $out"; teardown; return; }
  pass "U6: docs: — exit 0"
  teardown
}

u7_feat_no_scope() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat: foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U7" "expected exit 1 for 'feat: ', got: $out"; teardown; return; }
  pass "U7: feat: (no scope) — exit 1"
  teardown
}

u8_feat_bang_no_scope() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat!: breaking")
  [ "${out%%|*}" = "1" ] || { fail_ "U8" "expected exit 1 for 'feat!:', got: $out"; teardown; return; }
  pass "U8: feat!: — exit 1"
  teardown
}

u9_feat_scope_bang() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat(x)!: breaking")
  [ "${out%%|*}" = "1" ] || { fail_ "U9" "expected exit 1 for 'feat(x)!:', got: $out"; teardown; return; }
  pass "U9: feat(x)!: — exit 1"
  teardown
}

u10_feature_word() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feature: foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U10" "expected exit 0 for 'feature:', got: $out"; teardown; return; }
  pass "U10: feature: (wrong word) — exit 0"
  teardown
}

u11_featbar_prefix() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "featbar: foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U11" "expected exit 0 for 'featbar:', got: $out"; teardown; return; }
  pass "U11: featbar: (not feat) — exit 0"
  teardown
}

u12_feature_started_zero_steps() {
  setup; seed_phase 2; seed_process_state "myfeat" ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U12" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"tests_written"* ]] || { fail_ "U12" "stderr missing 'tests_written' step name: $out"; teardown; return; }
  pass "U12: feature started, 0 steps — exit 1 + names tests_written"
  teardown
}

u13_feature_started_partial() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit"
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U13" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"documentation_updated"* ]] || { fail_ "U13" "stderr missing 'documentation_updated' step name: $out"; teardown; return; }
  pass "U13: steps 0-3 done — exit 1 + names step 4 (documentation_updated)"
  teardown
}

u14_feature_started_all_done() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit documentation_updated"
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U14" "expected exit 0, got: $out"; teardown; return; }
  pass "U14: feat with all 5 steps complete — exit 0"
  teardown
}

u15_non_feat_all_done() {
  setup; seed_phase 2
  seed_process_state "myfeat" "tests_written tests_verified_failing implemented security_audit documentation_updated"
  local out; out=$(run_check "fix(x): foo")
  [ "${out%%|*}" = "0" ] || { fail_ "U15" "expected exit 0 for fix with all steps done, got: $out"; teardown; return; }
  pass "U15: fix: with all steps done — exit 0"
  teardown
}

u16_empty_msg() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "")
  [ "${out%%|*}" = "0" ] || { fail_ "U16" "expected exit 0 for empty MSG, got: $out"; teardown; return; }
  pass "U16: empty message — exit 0"
  teardown
}

u17_revert_quotes_feat() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check 'Revert "feat(x): foo"')
  [ "${out%%|*}" = "0" ] || { fail_ "U17" "expected exit 0 for Revert-prefix, got: $out"; teardown; return; }
  pass "U17: Revert \"feat(x): ...\" — exit 0 (regex anchored to start)"
  teardown
}

# U18: BL-006 between-features grace window — UAT 2026-04-25 bug C2.
# After --complete-step build_loop:feature_recorded the loop is consumed;
# the next feat: commit MUST require a fresh --start-feature. Without the
# auto-reset fix, the gate would see feature != null and steps complete
# and let any subsequent feat: commit through.
#
# Setup approach: seed process-state directly to the post-step-5 state
# (feature started + first 5 steps complete), then call --complete-step
# build_loop:feature_recorded and observe the auto-reset side effect.
# This bypasses the artifact checks for security_audit etc. that would
# otherwise block a fully scripted setup.
u18_no_grace_window_after_feature_recorded() {
  setup; seed_phase 2
  cat > "$TMPDIR_T/.claude/process-state.json" <<JSON
{
  "phase2_init": {"verified": true},
  "build_loop": {
    "feature": "uat-feat-1",
    "step": 5,
    "steps_completed": ["tests_written","tests_verified_failing","implemented","security_audit","documentation_updated"],
    "started_at": "2026-04-25T00:00:00Z"
  },
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
  local PC="$REPO_ROOT/scripts/process-checklist.sh"
  local rc=0
  ( cd "$TMPDIR_T" && "$PC" --complete-step "build_loop:feature_recorded" >/dev/null 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || { fail_ "U18" "complete-step build_loop:feature_recorded should succeed; rc=$rc"; teardown; return; }
  local feat
  feat=$(jq -r '.build_loop.feature' "$TMPDIR_T/.claude/process-state.json")
  [ "$feat" = "null" ] || { fail_ "U18" "expected .build_loop.feature == null after feature_recorded; got: '$feat'"; teardown; return; }
  local steps_count
  steps_count=$(jq '.build_loop.steps_completed | length' "$TMPDIR_T/.claude/process-state.json")
  [ "$steps_count" = "0" ] || { fail_ "U18" "expected steps_completed cleared; got count=$steps_count"; teardown; return; }
  local out; out=$(run_check "feat(x): subsequent")
  [ "${out%%|*}" = "1" ] || { fail_ "U18" "expected exit 1 for feat: after feature_recorded; got: $out"; teardown; return; }
  [[ "${out#*|}" == *"start-feature"* ]] || { fail_ "U18" "stderr should require new --start-feature, got: $out"; teardown; return; }
  pass "U18: BL-006 build_loop auto-resets after feature_recorded — no between-features grace window"
  teardown
}

# ── WALK-ISSUE-010: a CLOSED loop authorizes ITS OWN feature's commit ────────
# Walk 2026-08-02 (walkrepo-1785713402, ISSUE-010, Major): the walker read
# CLAUDE.md's Build Loop as "mark the six steps in order, then commit the
# feature". Completing step 6 (feature_recorded) auto-resets .build_loop (the
# UAT-C2 fix U18 pins), so the feature's own `feat:` commit was then blocked
# FOREVER — the gate demanded a loop that the documented order had just
# closed, and its remediation text ("--start-feature ...") dead-ends a junior
# into re-registering a loop for work that is already done.
#
# The fix records a CLOSED-LOOP RECEIPT (.build_loop.last_completed) and
# accepts it for commits that NAME that feature. The bound is IDENTITY, not
# time: U18/U20 prove an unrelated feat: commit is still blocked, so the C2
# grace window stays shut.
#
# seed_ready_to_record <feature>: the post-step-5 state (loop active, steps
# 1-5 done) — the same hand-seed U18 uses, parameterized by feature name.
seed_ready_to_record() {
  local feature="$1"
  mkdir -p "$TMPDIR_T/.claude"
  jq -n --arg f "$feature" '{
    "phase2_init": {"verified": true},
    "build_loop": {
      "feature": $f,
      "step": 5,
      "steps_completed": ["tests_written","tests_verified_failing","implemented","security_audit","documentation_updated"],
      "started_at": "2026-08-02T00:00:00Z"
    },
    "uat_session": {"started_at": null, "steps_completed": []}
  }' > "$TMPDIR_T/.claude/process-state.json"
}

# record_feature: run the real --complete-step build_loop:feature_recorded
# (the walker's actual command) so the receipt is written by the product code,
# never hand-seeded. Echoes the rc.
record_feature() {
  local rc=0
  ( cd "$TMPDIR_T" && "$REPO_ROOT/scripts/process-checklist.sh" \
      --complete-step "build_loop:feature_recorded" >/dev/null 2>&1 ) || rc=$?
  echo "$rc"
}

u19_closed_loop_allows_its_own_feature() {
  setup; seed_phase 2; seed_ready_to_record "find-in-document"
  local rc; rc=$(record_feature)
  [ "$rc" = "0" ] || { fail_ "U19" "--complete-step build_loop:feature_recorded failed (rc=$rc)"; teardown; return; }
  local out; out=$(run_check "feat(find-in-document): add the find bar")
  [ "${out%%|*}" = "0" ] || { fail_ "U19" "the feature's OWN commit was blocked after its loop was completed and closed — the ISSUE-010 dead end: $out"; teardown; return; }
  pass "U19: a completed+closed Build Loop authorizes that feature's own feat: commit"
  teardown
}

u20_closed_loop_blocks_other_features() {
  setup; seed_phase 2; seed_ready_to_record "find-in-document"
  local rc; rc=$(record_feature)
  [ "$rc" = "0" ] || { fail_ "U20" "--complete-step failed (rc=$rc)"; teardown; return; }
  local out; out=$(run_check "feat(export): PDF export")
  [ "${out%%|*}" = "1" ] || { fail_ "U20" "a DIFFERENT feature rode the closed loop — the UAT-C2 grace window reopened: $out"; teardown; return; }
  [[ "${out#*|}" == *"start-feature"* ]] || { fail_ "U20" "stderr must still name the --start-feature recovery: $out"; teardown; return; }
  [[ "${out#*|}" == *"find-in-document"* ]] || { fail_ "U20" "the block message must NAME the closed loop's feature so the recovery is not a guess: $out"; teardown; return; }
  pass "U20: the closed-loop receipt is feature-scoped — an unrelated feat: commit is still blocked, by name"
  teardown
}

u21_closed_loop_token_match() {
  setup; seed_phase 2; seed_ready_to_record "Highlight removal with note-loss confirmation"
  local rc; rc=$(record_feature)
  [ "$rc" = "0" ] || { fail_ "U21" "--complete-step failed (rc=$rc)"; teardown; return; }
  local out; out=$(run_check "feat(highlight): remove with confirmation")
  [ "${out%%|*}" = "0" ] || { fail_ "U21" "a scope naming one word of the closed feature was rejected — the match must not demand the whole slug verbatim: $out"; teardown; return; }
  pass "U21: a whole word of the closed feature's name in the scope/description matches"
  teardown
}

u22_closed_loop_needs_all_five_steps() {
  setup; seed_phase 2
  mkdir -p "$TMPDIR_T/.claude"
  cat > "$TMPDIR_T/.claude/process-state.json" <<'JSON'
{
  "phase2_init": {"verified": true},
  "build_loop": {
    "feature": null, "step": 0, "steps_completed": [], "started_at": null,
    "last_completed": {
      "feature": "find-in-document",
      "completed_at": "2026-08-02T00:00:00Z",
      "steps_completed": ["tests_written","tests_verified_failing","implemented"]
    }
  },
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
  local out; out=$(run_check "feat(find-in-document): add the find bar")
  [ "${out%%|*}" = "1" ] || { fail_ "U22" "a receipt MISSING security_audit/documentation_updated authorized a commit — the closed-loop arm must require all five: $out"; teardown; return; }
  pass "U22: a closed-loop receipt missing required steps authorizes nothing"
  teardown
}

# ── The receipt is bound to the CLOSED LOOP'S OWN FILES, not just its name ──
# Karl's review emphasis (2026-08-02): a stale receipt must not bless an
# unrelated commit. Naming the feature in the subject is operator-authored
# text; the second, non-authored half of the binding is the WORK — the paths
# the loop was actually working on when it closed. A `feat:` commit that names
# the closed feature but stages none of its files is a different piece of work
# and is blocked. Two documented fallbacks, both proven below: a receipt with
# NO recorded paths (a loop closed with a clean tree — the commit-first
# ordering) and a commit with NO staged paths fall back to identity alone,
# because there is nothing to bind against.
#
# mk_git_fixture <feature> <loop-file> — a real repo whose loop closed with
# <loop-file> TRACKED-AND-MODIFIED and <loop-file>.test.ts UNTRACKED, so the
# receipt has to pick both dirty-work sources up, not just one.
mk_git_fixture() {
  local feature="$1" loop_file="$2"
  mkdir -p "$TMPDIR_T/.claude"
  ( cd "$TMPDIR_T" \
      && git init -q \
      && git config user.email "walk@test.invalid" \
      && git config user.name "walk" \
      && echo seed > seed.txt \
      && printf 'export const x = 0;\n' > "$loop_file" \
      && git add seed.txt "$loop_file" \
      && git commit -q -m "chore: init" ) >/dev/null 2>&1 || return 1
  printf 'export const x = 1;\n' > "$TMPDIR_T/$loop_file"
  printf 'test("x", () => {});\n' > "$TMPDIR_T/${loop_file%.ts}.test.ts"
  seed_phase 2
  seed_ready_to_record "$feature"
  local rc; rc=$(record_feature)
  [ "$rc" = "0" ] || return 1
  return 0
}

u25_receipt_binds_to_the_loops_files() {
  setup
  if ! mk_git_fixture "find-in-document" "find.ts"; then
    fail_ "U25" "fixture setup failed"; teardown; return
  fi
  local recorded
  recorded=$(jq -r '(.build_loop.last_completed.paths // []) | join(",")' "$TMPDIR_T/.claude/process-state.json")
  [[ "$recorded" == *"find.ts"* ]] || { fail_ "U25" "the receipt did not record the loop's MODIFIED tracked file (got '$recorded') — there is nothing to bind a later commit to"; teardown; return; }
  [[ "$recorded" == *"find.test.ts"* ]] || { fail_ "U25" "the receipt did not record the loop's UNTRACKED new file (got '$recorded') — a feature's brand-new files are its work too"; teardown; return; }
  # (a) staging the loop's OWN file + naming the feature: allowed.
  ( cd "$TMPDIR_T" && git add find.ts ) >/dev/null 2>&1
  local out; out=$(run_check "feat(find-in-document): add the find bar")
  [ "${out%%|*}" = "0" ] || { fail_ "U25" "the closed loop's OWN staged file was blocked: $out"; teardown; return; }
  pass "U25: the closed-loop receipt records the loop's paths and authorizes a commit staging them"
  teardown
}

u26_receipt_does_not_bless_unrelated_files() {
  setup
  if ! mk_git_fixture "find-in-document" "find.ts"; then
    fail_ "U26" "fixture setup failed"; teardown; return
  fi
  # A LATER, unrelated piece of work — the subject still names the closed
  # feature (an operator can type anything), but none of the loop's files are
  # staged. That is a different feature's commit riding a stale receipt.
  printf 'export const y = 2;\n' > "$TMPDIR_T/exporter.ts"
  ( cd "$TMPDIR_T" && git add exporter.ts ) >/dev/null 2>&1
  local out; out=$(run_check "feat(find-in-document): pdf exporter")
  [ "${out%%|*}" = "1" ] || { fail_ "U26" "a commit staging NONE of the closed loop's files rode the receipt on subject text alone — a stale record must not bless unrelated work: $out"; teardown; return; }
  [[ "${out#*|}" == *"exporter.ts"* || "${out#*|}" == *"none of the"* ]] || { fail_ "U26" "the block must explain that the staged files are not the closed loop's: $out"; teardown; return; }
  pass "U26: a stale receipt cannot bless unrelated staged work — subject text alone is not the binding"
  teardown
}

u27_no_recorded_paths_falls_back_to_identity() {
  setup; seed_phase 2
  mkdir -p "$TMPDIR_T/.claude"
  # A loop closed on a CLEAN tree (the commit-first ordering): the receipt has
  # no paths, so there is nothing to bind against and identity alone governs.
  cat > "$TMPDIR_T/.claude/process-state.json" <<'JSON'
{
  "phase2_init": {"verified": true},
  "build_loop": {
    "feature": null, "step": 0, "steps_completed": [], "started_at": null,
    "last_completed": {
      "feature": "find-in-document",
      "completed_at": "2026-08-02T00:00:00Z",
      "steps_completed": ["tests_written","tests_verified_failing","implemented","security_audit","documentation_updated","feature_recorded"],
      "paths": []
    }
  },
  "uat_session": {"started_at": null, "steps_completed": []}
}
JSON
  local out; out=$(run_check "feat(find-in-document): follow-up")
  [ "${out%%|*}" = "0" ] || { fail_ "U27" "a receipt with no recorded paths must fall back to identity, not block: $out"; teardown; return; }
  pass "U27: an empty path record falls back to the identity bound (documented fallback, not a silent hole)"
  teardown
}

u28_short_feature_name_matches_whole_token_only() {
  setup; seed_phase 2; seed_ready_to_record "ui"
  local rc; rc=$(record_feature)
  [ "$rc" = "0" ] || { fail_ "U28" "--complete-step failed (rc=$rc)"; teardown; return; }
  # "build" CONTAINS the letters "ui". A two-character feature slug must match
  # as a whole token or the identity bound decays into letter-soup.
  local out; out=$(run_check "feat(build): unrelated tooling")
  [ "${out%%|*}" = "1" ] || { fail_ "U28" "the closed feature 'ui' was 'named' by the letters inside 'build' — a short slug must match a WHOLE token: $out"; teardown; return; }
  out=$(run_check "feat(ui): the actual ui work")
  [ "${out%%|*}" = "0" ] || { fail_ "U28" "a short feature name matched as a whole token was still blocked: $out"; teardown; return; }
  pass "U28: a short feature slug matches only as a whole token, never as letters inside another word"
  teardown
}

u24_status_names_the_closed_loop() {
  setup; seed_phase 2; seed_ready_to_record "find-in-document"
  local rc; rc=$(record_feature)
  [ "$rc" = "0" ] || { fail_ "U24" "--complete-step failed (rc=$rc)"; teardown; return; }
  local out
  out=$( cd "$TMPDIR_T" && "$REPO_ROOT/scripts/process-checklist.sh" --status 2>&1 ) || true
  [[ "$out" == *"find-in-document"* ]] || { fail_ "U24" "--status shows only 'Feature: none' after a loop closes — the operator cannot tell whether the finished feature is still committable: $(printf '%s' "$out" | head -12 | tr '\n' ' ')"; teardown; return; }
  pass "U24: --status names the closed loop's feature, so 'Feature: none' is not the whole story"
  teardown
}

u23_block_message_names_the_verification() {
  setup; seed_phase 2; seed_process_state null ""
  local out; out=$(run_check "feat(x): foo")
  [ "${out%%|*}" = "1" ] || { fail_ "U23" "expected exit 1, got: $out"; teardown; return; }
  [[ "${out#*|}" == *"git log -1"* ]] || { fail_ "U23" "the block message must tell the operator how to VERIFY a commit landed (the walk lost four commits to a '| tail' pipe that hid this very block): $out"; teardown; return; }
  pass "U23: the block message names the landed-commit verification (git log -1)"
  teardown
}

# --- Run all ---
echo "== tests/test-check-commit-message.sh =="
u1_phase_0_feat
u2_phase_1_feat
u3_phase_2_no_feature_feat
u4_non_feat_fix
u5_non_feat_chore
u6_non_feat_docs
u7_feat_no_scope
u8_feat_bang_no_scope
u9_feat_scope_bang
u10_feature_word
u11_featbar_prefix
u12_feature_started_zero_steps
u13_feature_started_partial
u14_feature_started_all_done
u15_non_feat_all_done
u16_empty_msg
u17_revert_quotes_feat
u18_no_grace_window_after_feature_recorded
u19_closed_loop_allows_its_own_feature
u20_closed_loop_blocks_other_features
u21_closed_loop_token_match
u22_closed_loop_needs_all_five_steps
u23_block_message_names_the_verification
u24_status_names_the_closed_loop
u25_receipt_binds_to_the_loops_files
u26_receipt_does_not_bless_unrelated_files
u27_no_recorded_paths_falls_back_to_identity
u28_short_feature_name_matches_whole_token_only

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

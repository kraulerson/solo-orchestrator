#!/usr/bin/env bash
# tests/test-bl172-resume-sentinels.sh — BL-172 resume-sentinel parity.
#
# THE DEFECT (surfaced by the BL-171 fable verifier; pre-existing)
#   tdd_terminal_enforce (the BL-072 tier-keyed TDD-ordering HARD BLOCK at the
#   commit-msg --terminal-mode surface) skipped ONLY on .git/MERGE_HEAD, while
#   its sibling bl006_terminal_enforce honors all three derivative sentinels
#   (MERGE_HEAD / CHERRY_PICK_HEAD / REVERT_HEAD). Net: a strict-tier `git commit`
#   RESUMING a conflicted cherry-pick or revert whose payload is an impl file
#   with no accompanying test was REFUSED by the TDD gate — even though a
#   cherry-pick/revert is a REPLAY of an already-reviewed change, not a
#   TDD-authoring event.
#
# THE FIX (# BL-172-RESUME-SENTINELS): add the CHERRY_PICK_HEAD / REVERT_HEAD
#   sentinels to tdd_terminal_enforce (the refusal gate) matching
#   bl006_terminal_enforce, AND — for parity — to the same BL-072 gate's OTHER
#   entry point, the PreToolUse WARN surface tdd_warn_check (whose in-function
#   comment names tdd_terminal_enforce as its hard-block counterpart; it already
#   passes explicit cherry-pick/revert COMMANDS via a command-string filter and
#   resumed MERGES via the MERGE_HEAD sentinel — the two added sentinels extend
#   that same pass-through to a resumed cherry-pick/revert committed with a plain
#   `git commit`). MERGE_HEAD behavior is untouched; normal impl-only commits
#   (no sentinel) still refuse / still warn (the anti-blunting cases pin this).
#
# CASES
#   Section A — commit-msg terminal-mode REFUSAL gate (tdd_terminal_enforce):
#     (a) CHERRY_PICK_HEAD present + impl-only + strict tier  -> rc=0 PASS  [RED pre-fix]
#     (b) REVERT_HEAD present      + impl-only + strict tier  -> rc=0 PASS  [RED pre-fix]
#     (c) MERGE_HEAD present       + impl-only + strict tier  -> rc=0 PASS  [unchanged]
#     (d) NO sentinel (anti-blunt) + impl-only + strict tier  -> rc=1 REFUSE + [FAIL] BL-072
#     (e) NO sentinel + impl+TEST  + strict tier              -> rc=0 PASS  [normal TDD-satisfied]
#   Section B — PreToolUse WARN surface parity (tdd_warn_check):
#     (f) CHERRY_PICK_HEAD present + `git commit` + impl-only -> NO [WARN]  [RED pre-fix]
#     (g) REVERT_HEAD present      + `git commit` + impl-only -> NO [WARN]  [RED pre-fix]
#     (h) NO sentinel (anti-blunt) + `git commit` + impl-only -> [WARN] fires
#   Section C — MUTATION: excise every `# BL-172-RESUME-SENTINELS` line from a gate
#     COPY -> (a),(b) refuse again + (f) warns again (RED); (d),(h) still block/warn
#     (anti-blunting unaffected); the real gate is the GREEN contrast.
#
# HERMETIC: mktemp fixture repos (git init + local identity + a fake origin
# pointer only — no real remote is ever contacted); GITHUB_BASE_REF unset so CI's
# own env cannot leak into fixture git ops; the sentinel files are created
# directly (a fake 40-hex SHA) rather than via a real cherry-pick/revert, so no
# git subprocess is needed and the gate is driven exactly as the hooks drive it.
# bl006_terminal_enforce / bl006_check no-op here (no scripts/process-checklist.sh
# in the fixture CWD; mothership phase for the WARN fixture) so the TDD gate is
# the SOLE variable under test. No init.sh, not an aggregator -> registered in
# BOTH the aggregator and the tests.yml unit list.
#
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
TDD_LIB="$REPO_ROOT/scripts/lib/tdd-classify.sh"
PC="$REPO_ROOT/scripts/process-checklist.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — the BL-072 tier/ledger reads require jq."
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Fixture scaffolding ──────────────────────────────────────────────
# A minimal git repo on `main` with a fake origin pointer. The gate under test
# is the REAL repo gate (its SCRIPT_DIR resolves the real libs); the fixture
# supplies only git state + optional phase-state + staged files. No
# scripts/process-checklist.sh in the fixture CWD => bl006_terminal_enforce and
# (at mothership phase) bl006_check are inert, so the ONLY observable behavior is
# the BL-072 TDD gate.
setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  mkdir -p "$PROJ"
  (
    cd "$PROJ"
    unset GITHUB_BASE_REF
    git init -q -b main
    git config user.email "t@example.invalid"
    git config user.name "bl172-test"
    git remote add origin "https://example.invalid/x.git"
    mkdir -p src
    echo "seed" > README.md
    git add README.md
    git commit -q -m "chore: seed"
  )
}
teardown() { rm -rf "$TMP"; }

# Write a NON-bypassable (strict) tier so the TDD gate HARD-BLOCKS an impl-only
# feat. organizational + sponsored_poc => _bl072_tier_bypassable returns 1.
write_strict_tier() {
  mkdir -p "$PROJ/.claude"
  cat > "$PROJ/.claude/phase-state.json" <<EOF
{"current_phase":2,"deployment":"organizational","poc_mode":"sponsored_poc","track":"standard"}
EOF
}

# Stage a file (creating parent dirs) without committing.
stage() {
  local path="$1" content="${2:-x}"
  mkdir -p "$PROJ/$(dirname "$path")"
  printf '%s\n' "$content" > "$PROJ/$path"
  ( cd "$PROJ" && git add "$path" )
}
stage_impl()          { stage "src/foo.py" "def foo(): return 1"; }
stage_impl_and_test() { stage "src/foo.py" "def foo(): return 1"; stage "tests/test_foo.py" "def test_foo(): assert True"; }

# Create a derivative-commit sentinel in .git with a fake 40-hex SHA (git only
# checks for the file's EXISTENCE; the gate never parses its contents).
make_sentinel() { printf '%s\n' "0123456789abcdef0123456789abcdef01234567" > "$PROJ/.git/$1"; }

# Set the prospective commit subject (terminal-mode reads .git/COMMIT_EDITMSG).
set_subject() { printf '%s\n' "$1" > "$PROJ/.git/COMMIT_EDITMSG"; }

# Number of rows currently in the WARN ledger (0 if absent).
ledger_rows() {
  local f="$PROJ/.claude/tdd-warn-ledger.jsonl"
  if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi
}

# Run the gate at the commit-msg surface (--terminal-mode --tdd-only). rc|out.
run_term()      { _run_term "$GATE"; }
run_term_gate() { _run_term "$1"; }
_run_term() {
  local gate="$1" out rc=0
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; bash "$gate" --terminal-mode --tdd-only 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

# Run the gate at the PreToolUse surface with a bash command. rc|out.
# SKIP_LINT=1 keeps the unrelated operator-side lints out of the comparison; the
# TDD detector runs before them regardless.
run_hook()      { _run_hook "$GATE" "$1"; }
run_hook_gate() { _run_hook "$1" "$2"; }
_run_hook() {
  local gate="$1" cmd="$2" input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; export SKIP_LINT=1; \
         printf '%s' "$input" | bash "$gate" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

has_warn() { case "$1" in *'[WARN] BL-072 TDD ordering'*) return 0 ;; *) return 1 ;; esac; }
has_fail() { case "$1" in *'[FAIL] BL-072 TDD ordering'*) return 0 ;; *) return 1 ;; esac; }

# Copy the gate + its deps into a mutation tree so a mutation is the ONLY
# difference from the real gate (the copied libs keep the mutant gate's
# SCRIPT_DIR self-consistent).
build_mut_tree() {
  local mut="$1"
  mkdir -p "$mut/scripts/lib"
  cp "$GATE" "$mut/scripts/pre-commit-gate.sh"
  cp "$TDD_LIB" "$mut/scripts/lib/tdd-classify.sh"
  cp "$PC" "$mut/scripts/process-checklist.sh" 2>/dev/null || true
  cp "$REPO_ROOT"/scripts/lib/*.sh "$mut/scripts/lib/" 2>/dev/null || true
  chmod +x "$mut/scripts/pre-commit-gate.sh"
}

# ════════════════════════════════════════════════════════════════════
# Section A — commit-msg terminal-mode REFUSAL gate (tdd_terminal_enforce)
# ════════════════════════════════════════════════════════════════════

echo ""
echo "=== (a) CHERRY_PICK_HEAD present + impl-only + strict tier -> gate PASSES (rc=0) ==="
setup; write_strict_tier; stage_impl; make_sentinel CHERRY_PICK_HEAD
set_subject "feat: replay picked change (impl only)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "(a) a resumed cherry-pick of impl-only content is NOT refused by the TDD gate (rc=0)"
else
  fail_ "(a) cherry-pick-resume" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

echo ""
echo "=== (b) REVERT_HEAD present + impl-only + strict tier -> gate PASSES (rc=0) ==="
setup; write_strict_tier; stage_impl; make_sentinel REVERT_HEAD
set_subject "feat: replay reverted change (impl only)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "(b) a resumed revert of impl-only content is NOT refused by the TDD gate (rc=0)"
else
  fail_ "(b) revert-resume" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

echo ""
echo "=== (c) MERGE_HEAD present + impl-only + strict tier -> gate PASSES (rc=0, unchanged) ==="
setup; write_strict_tier; stage_impl; make_sentinel MERGE_HEAD
set_subject "feat: finish the merge (impl only)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "(c) MERGE_HEAD pass-through is unchanged (rc=0) — must hold before AND after the fix"
else
  fail_ "(c) merge-resume-unchanged" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

echo ""
echo "=== (d) ANTI-BLUNTING: NO sentinel + impl-only + strict tier -> STILL REFUSED (rc=1 + [FAIL]) ==="
setup; write_strict_tier; stage_impl
set_subject "feat: ship impl without a test (normal authoring commit)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 1 ] && has_fail "$body"; then
  pass "(d) anti-blunting: a NORMAL impl-only commit is still hard-blocked (rc=1 + [FAIL]) — the gate is not globally softer"
else
  fail_ "(d) anti-blunting" "expected rc=1 + [FAIL] BL-072; got rc=$rc body: $body"
fi
teardown

echo ""
echo "=== (e) impl+TEST staged + NO sentinel + strict tier -> gate PASSES (rc=0) ==="
setup; write_strict_tier; stage_impl_and_test
set_subject "feat: ship impl with its test (TDD-satisfying commit)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "(e) a normal TDD-satisfying commit (test rides along) is unaffected (rc=0)"
else
  fail_ "(e) impl+test-unaffected" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
# Section B — PreToolUse WARN surface parity (tdd_warn_check)
# Mothership fixture (no phase-state): the WARN surface is tier-independent and
# bl006_check phase-gates to a pass, so [WARN] presence is the sole signal.
# The subjects/commands deliberately omit the words merge/revert/cherry-pick so
# the command-string filter cannot pass them through — only the SENTINEL can.
# ════════════════════════════════════════════════════════════════════

echo ""
echo "=== (f) CHERRY_PICK_HEAD present + plain 'git commit' + impl-only -> NO [WARN] ==="
setup; stage_impl; make_sentinel CHERRY_PICK_HEAD
res=$(run_hook 'git commit -m "feat: add foo"'); body="${res#*|}"
if ! has_warn "$body"; then
  pass "(f) a resumed cherry-pick committed with a plain 'git commit' passes through the WARN surface (no [WARN])"
else
  fail_ "(f) warn-cherry-pick-resume" "expected NO [WARN]; got: $body"
fi
teardown

echo ""
echo "=== (g) REVERT_HEAD present + plain 'git commit' + impl-only -> NO [WARN] ==="
setup; stage_impl; make_sentinel REVERT_HEAD
res=$(run_hook 'git commit -m "feat: add foo"'); body="${res#*|}"
if ! has_warn "$body"; then
  pass "(g) a resumed revert committed with a plain 'git commit' passes through the WARN surface (no [WARN])"
else
  fail_ "(g) warn-revert-resume" "expected NO [WARN]; got: $body"
fi
teardown

echo ""
echo "=== (h) ANTI-BLUNTING: NO sentinel + plain 'git commit' + impl-only -> [WARN] fires ==="
setup; stage_impl
res=$(run_hook 'git commit -m "feat: add foo"'); body="${res#*|}"
if has_warn "$body"; then
  pass "(h) anti-blunting: a NORMAL impl-only commit still WARNs on the PreToolUse surface — measurement not blunted"
else
  fail_ "(h) warn-anti-blunting" "expected a [WARN]; got: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
# Section C — MUTATION: excise every # BL-172-RESUME-SENTINELS line
# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (mut) excise # BL-172-RESUME-SENTINELS -> resume pass-throughs disappear (RED); anti-blunting unchanged; real gate GREEN ==="
# The mutant gate lives in its OWN mktemp root so per-fixture teardown() (which
# rm -rf's $TMP) cannot delete it between the terminal-mode and WARN blocks.
MUTROOT=$(mktemp -d)
MUT="$MUTROOT/mut"
build_mut_tree "$MUT"
MUT_GATE="$MUT/scripts/pre-commit-gate.sh"
grep -v '# BL-172-RESUME-SENTINELS' "$GATE" > "$MUT_GATE"
chmod +x "$MUT_GATE"

marker_real=$(grep -c '# BL-172-RESUME-SENTINELS' "$GATE" 2>/dev/null) || marker_real=0
case "$marker_real" in ''|*[!0-9]*) marker_real=0 ;; esac
marker_mut=$(grep -c '# BL-172-RESUME-SENTINELS' "$MUT_GATE" 2>/dev/null) || marker_mut=0
case "$marker_mut" in ''|*[!0-9]*) marker_mut=0 ;; esac

if [ "$marker_real" -lt 4 ]; then
  fail_ "(mut) preconditions" "expected >=4 # BL-172-RESUME-SENTINELS lines in the REAL gate (2 per surface x 2 surfaces); found $marker_real"
elif [ "$marker_mut" -ne 0 ]; then
  fail_ "(mut) preconditions" "marker still present after excision — mutation did not apply (found $marker_mut)"
elif ! bash -n "$MUT_GATE" 2>/dev/null; then
  fail_ "(mut) preconditions" "mutated gate not syntactically valid after excision"
else
  # RED — terminal-mode resume cherry-pick: the mutant refuses again.
  setup; write_strict_tier; stage_impl; make_sentinel CHERRY_PICK_HEAD
  set_subject "feat: replay picked change (impl only)"
  res=$(run_term_gate "$MUT_GATE"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "(mut RED, terminal): excising the sentinels makes a resumed cherry-pick hard-block again (rc=1) — the added lines are load-bearing"
  else
    fail_ "(mut RED, terminal-cherry-pick)" "mutant did NOT refuse — line not load-bearing; rc=$rc body: $body"
  fi
  # RED — terminal-mode resume revert.
  rm -f "$PROJ/.git/CHERRY_PICK_HEAD"; make_sentinel REVERT_HEAD
  res=$(run_term_gate "$MUT_GATE"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "(mut RED, terminal): excising the sentinels makes a resumed revert hard-block again (rc=1)"
  else
    fail_ "(mut RED, terminal-revert)" "mutant did NOT refuse the revert-resume; rc=$rc body: $body"
  fi
  # GREEN contrast (terminal) — the REAL gate still passes the same fixture.
  res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
    pass "(mut GREEN, terminal): the real gate passes the resumed revert (rc=0) — contrast holds"
  else
    fail_ "(mut GREEN, terminal)" "real gate did NOT pass — contrast broken; rc=$rc body: $body"
  fi
  # Anti-blunting stays GREEN under the mutation: no sentinel still refuses.
  rm -f "$PROJ/.git/REVERT_HEAD"
  res=$(run_term_gate "$MUT_GATE"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "(mut, anti-blunt terminal): with the sentinels excised a NORMAL impl-only commit still refuses (rc=1) — the mutation touches only the resume path"
  else
    fail_ "(mut anti-blunt terminal)" "expected the normal impl-only commit to still refuse; rc=$rc body: $body"
  fi
  teardown

  # RED — WARN surface resume cherry-pick: the mutant warns again.
  setup; stage_impl; make_sentinel CHERRY_PICK_HEAD
  res=$(run_hook_gate "$MUT_GATE" 'git commit -m "feat: add foo"'); body="${res#*|}"
  if has_warn "$body"; then
    pass "(mut RED, WARN): excising the sentinels makes a resumed cherry-pick WARN again on the PreToolUse surface — the added line is load-bearing"
  else
    fail_ "(mut RED, warn-cherry-pick)" "mutant did NOT warn — line not load-bearing; body: $body"
  fi
  # GREEN contrast (WARN) — the REAL gate stays silent on the same fixture.
  res=$(run_hook 'git commit -m "feat: add foo"'); body="${res#*|}"
  if ! has_warn "$body"; then
    pass "(mut GREEN, WARN): the real gate passes the resumed cherry-pick silently — contrast holds"
  else
    fail_ "(mut GREEN, warn)" "real gate WARNed — contrast broken; body: $body"
  fi
  # Anti-blunting stays GREEN under the mutation: no sentinel still warns.
  rm -f "$PROJ/.git/CHERRY_PICK_HEAD"
  res=$(run_hook_gate "$MUT_GATE" 'git commit -m "feat: add foo"'); body="${res#*|}"
  if has_warn "$body"; then
    pass "(mut, anti-blunt WARN): with the sentinels excised a NORMAL impl-only commit still WARNs — the mutation touches only the resume path"
  else
    fail_ "(mut anti-blunt WARN)" "expected the normal impl-only commit to still WARN; body: $body"
  fi
  teardown
fi
rm -rf "$MUTROOT"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-bl176-worktree-sentinels.sh — BL-176: the commit gates are blind
# inside a LINKED GIT WORKTREE.
#
# THE DEFECT (filed by the BL-172 WP-B fable verifier, F2+F3)
#   In a linked git worktree `.git` is a FILE (a `gitdir:` pointer), not a
#   directory, so every literal `.git/<NAME>` path in scripts/pre-commit-gate.sh
#   resolves to nothing. Two consequences, with OPPOSITE fail directions:
#
#   (1) SENTINEL SKIPS — `[ -f .git/MERGE_HEAD ]` / CHERRY_PICK_HEAD /
#       REVERT_HEAD are FALSE even mid-merge/cherry-pick/revert, because git
#       writes those sentinels into the PER-WORKTREE gitdir
#       (`.git/worktrees/<name>/<NAME>`). The derivative-resume pass-through
#       never fires, so a resumed cherry-pick/revert/merge is spuriously
#       REFUSED. Fail direction CLOSED (over-strict), as BL-176 records.
#
#   (2) THE COMMIT-MESSAGE READ — `COMMIT_MSG=$(cat .git/COMMIT_EDITMSG …)`
#       yields the EMPTY STRING in a linked worktree, so the subject the two
#       message-scoped commit-msg gates classify on is empty and BOTH gates
#       silently no-op. Fail direction OPEN: inside a linked worktree the
#       BL-072 TDD hard block and the BL-006 Build-Loop message check do not
#       run at all. (Not in BL-176's own text; found while building this
#       suite, and the reason its "never a bypass" calibration is incomplete.)
#
#   This repo's own agent workflow runs in `.claude/worktrees/agent-*` linked
#   worktrees, so both are live here.
#
# THE FIX
#   `# BL-176-GITPATH` — `_soif_git_path <name>` resolves through
#   `git rev-parse --git-path <name>` (git >= 2.5; returns `.git/<name>`
#   verbatim in a normal checkout, so it is a drop-in) with a literal
#   `.git/<name>` fallback if the rev-parse fails.
#   `# BL-176-RESUME-SKIP-*` — ONE shared `_derivative_resume_in_progress`
#   helper over the three-sentinel set, called from all FIVE skip sites
#   (tdd_terminal_enforce, bl006_terminal_enforce, tdd_warn_check, bl006_check,
#   lints_check) so the sets can never drift apart again. bl006_check and
#   lints_check were MERGE_HEAD-only before this and now honor all three
#   (BL-176 rider item 2).
#   `# BL-176-GITPATH-EDITMSG` — the COMMIT_EDITMSG read.
#
# CASES (W* = run from a LINKED WORKTREE, N* = normal checkout regression)
#   Section A  tdd_terminal_enforce (site 1) + the COMMIT_EDITMSG read
#     W-A1  no sentinel + impl-only + strict tier   -> rc=1 REFUSE  [RED pre-fix:
#           the subject was unreadable, so the gate no-opped -> rc=0]
#     W-A2  CHERRY_PICK_HEAD at the resolved gitdir -> rc=0 PASS
#     W-A3  REVERT_HEAD  at the resolved gitdir     -> rc=0 PASS
#     W-A4  MERGE_HEAD   at the resolved gitdir     -> rc=0 PASS
#   Section B  bl006_terminal_enforce (site 2)
#     W-B1  no sentinel + feat + Phase 2 + no Build Loop -> rc=1 BL-006 block
#     W-B2  MERGE_HEAD at the resolved gitdir            -> rc=0 PASS
#   Section C  tdd_warn_check (site 3, PreToolUse WARN)
#     W-C1  no sentinel + impl-only            -> [WARN] fires (anti-blunt)
#     W-C2  CHERRY_PICK_HEAD at resolved gitdir -> NO [WARN]
#   Section D  bl006_check (site 4, PreToolUse deny). DOCS-ONLY staging — see
#     stage_docs_only for why that is required to isolate this site from the
#     later --check-commit-ready gate, which has no derivative filter of its own.
#     W-D1  no sentinel + feat + Phase 2 + no Build Loop -> deny (anti-blunt)
#     W-D2  MERGE_HEAD at the resolved gitdir            -> NO deny
#   Section E  lints_check (site 5, PreToolUse lint promotion)
#     Observable: with SKIP_LINT=1 the function PRINTS its bypass notice — but
#     only if it got past the derivative-skip, which returns first. So the
#     notice's ABSENCE is the skip firing, with no lint fixture required.
#     W-E1  no sentinel      -> notice present (anti-blunt)
#     W-E2  MERGE_HEAD       -> notice absent
#   Section F  NORMAL-checkout regression + BL-176 rider item 2
#     N-F1  no sentinel + impl-only + strict tier -> rc=1 REFUSE  (unchanged)
#     N-F2  MERGE_HEAD literal                    -> rc=0 PASS    (unchanged)
#     N-F3  CHERRY_PICK_HEAD + bl006_check        -> NO deny  [RED pre-fix:
#           bl006_check was MERGE_HEAD-only]
#     N-F4  REVERT_HEAD + lints_check             -> notice absent  [RED pre-fix:
#           lints_check was MERGE_HEAD-only]
#   Section G  MUTATION, one per changed site: revert that site's marked line to
#     the pre-fix literal in a gate COPY -> that site's worktree case goes RED
#     while the real gate stays GREEN. Six mutants (five skip sites + the
#     COMMIT_EDITMSG read).
#
# HERMETIC: mktemp fixture repos only (git init + local identity + a fake
# example.invalid origin POINTER — never contacted); GITHUB_BASE_REF unset in
# every fixture git op; the linked worktree is created with `git worktree add`
# against that local fixture; sentinels are written directly (a fake 40-hex SHA)
# rather than by running a real conflicted cherry-pick, so no git subprocess can
# leave the fixture. No init.sh execution, not an aggregator -> registered in
# BOTH tests/full-project-test-suite.sh and the tests.yml unit lane.
#
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)), no
# multibyte characters adjacent to a $expansion.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — the tier / Build-Loop reads require jq."
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Fixture scaffolding ──────────────────────────────────────────────
# scaffold <phase|none> <feature|none> [complete]
#   Builds $TMP/main (a scaffolded-looking project: scripts/{pre-commit-gate,
#   process-checklist,lib/*} + .claude state, git init, seed commit) and adds a
#   LINKED WORKTREE at $TMP/wt on its own branch. The project files are copied
#   into BOTH trees (untracked) because every gate resolves them CWD-relative.
#   WORK selects which tree a case runs in — use_worktree / use_main.
scaffold() {
  local phase="$1" feature="$2" complete="${3:-}"
  TMP=$(mktemp -d)
  MAINP="$TMP/main"
  WTP="$TMP/wt"
  mkdir -p "$MAINP"
  (
    cd "$MAINP"
    unset GITHUB_BASE_REF
    git init -q -b main
    git config user.email "t@example.invalid"
    git config user.name "bl176-test"
    git remote add origin "https://example.invalid/x.git"
    echo seed > README.md
    git add README.md
    git commit -q -m "chore: seed"
    git worktree add -q -b bl176-wt "$WTP"
  )
  _install_project_files "$MAINP" "$phase" "$feature" "$complete"
  _install_project_files "$WTP"   "$phase" "$feature" "$complete"
  use_worktree
}

_install_project_files() {
  local dest="$1" phase="$2" feature="$3" complete="$4"
  mkdir -p "$dest/scripts/lib" "$dest/.claude"
  cp "$REPO_ROOT/scripts/pre-commit-gate.sh" "$dest/scripts/"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$dest/scripts/"
  cp "$REPO_ROOT"/scripts/lib/*.sh "$dest/scripts/lib/"
  chmod +x "$dest/scripts/pre-commit-gate.sh" "$dest/scripts/process-checklist.sh"

  if [ "$phase" != "none" ]; then
    cat > "$dest/.claude/phase-state.json" <<EOF
{"current_phase":$phase,"deployment":"$FIX_DEPLOYMENT","poc_mode":$FIX_POC,"track":"standard"}
EOF
  fi

  local steps='[]' feat_json='null'
  if [ "$feature" != "none" ]; then
    feat_json="\"$feature\""
    if [ "$complete" = "complete" ]; then
      steps='["tests_written","tests_verified_failing","implemented","security_audit","documentation_updated"]'
    fi
  fi
  cat > "$dest/.claude/process-state.json" <<EOF
{"build_loop":{"feature":$feat_json,"step":0,"steps_completed":$steps,"started_at":null},"uat_session":{},"phase1_architecture":{},"phase3_validation":{},"phase4_release":{},"phase2_init":{"steps_completed":["remote_repo_created"],"verified":true}}
EOF
}

# Tier knobs consumed by _install_project_files. strict => the BL-072 gate HARD
# BLOCKS an impl-only feat; personal => bypassable (used by the BL-006 cases so
# BL-006 is the only enforcer that can refuse).
FIX_DEPLOYMENT="personal"
FIX_POC="null"
use_strict_tier()   { FIX_DEPLOYMENT="organizational"; FIX_POC='"sponsored_poc"'; }
use_personal_tier() { FIX_DEPLOYMENT="personal";       FIX_POC='null'; }

teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; TMP=""; }

use_worktree() { WORK="$WTP"; }
use_main()     { WORK="$MAINP"; }

# Resolve a path inside the gitdir that ACTUALLY serves $WORK. In $MAINP this is
# `.git/<name>`; in the linked worktree it is `<main>/.git/worktrees/<n>/<name>`.
# --git-path answers RELATIVE in a normal checkout, so absolutize against $WORK
# (this helper's callers redirect from the TEST's cwd, not the fixture's).
gp() {
  local p
  p=$( cd "$WORK" && git rev-parse --git-path "$1" )
  case "$p" in
    /*) printf '%s' "$p" ;;
    *)  printf '%s/%s' "$WORK" "$p" ;;
  esac
}

# git only checks these sentinels for EXISTENCE; the gate never parses them, so
# a fake 40-hex SHA is enough and no real conflicted cherry-pick is needed.
make_sentinel() { printf '%s\n' "0123456789abcdef0123456789abcdef01234567" > "$(gp "$1")"; }
set_subject()   { printf '%s\n' "$1" > "$(gp COMMIT_EDITMSG)"; }

stage() {
  local path="$1" content="${2:-x}"
  mkdir -p "$WORK/$(dirname "$path")"
  printf '%s\n' "$content" > "$WORK/$path"
  ( cd "$WORK" && unset GITHUB_BASE_REF; git add "$path" )
}
stage_impl()           { stage "src/foo.py" "def foo(): return 1"; }
stage_impl_and_test()  { stage "src/foo.py" "def foo(): return 1"; stage "tests/test_foo.py" "def test_foo(): assert True"; }
# ISOLATION for the bl006_check cases (site 4). The PreToolUse body runs a
# SECOND, later gate — process-checklist.sh --check-commit-ready — which has no
# derivative-sentinel filter of its own and would deny a `feat:` commit for the
# same "no Build Loop active" reason, masking whether bl006_check skipped. A
# DOCS-ONLY staged set exempts --check-commit-ready (its .md/.json/.yml/…
# all_exempt short-circuit) while leaving check_commit_message — which is purely
# subject+phase scoped — blocking. So with docs-only staging a deny can ONLY
# have come from bl006_check.
stage_docs_only()      { stage "NOTES.md" "# note"; }

# Run the gate at the commit-msg surface (--terminal-mode --tdd-only). "rc|out".
run_term()      { _run_term "$GATE"; }
run_term_gate() { _run_term "$1"; }
_run_term() {
  local gate="$1" out rc=0
  out=$( cd "$WORK" && unset GITHUB_BASE_REF; bash "$gate" --terminal-mode --tdd-only 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

# Run the gate at the PreToolUse surface. "rc|out". SKIP_LINT is passed in so the
# lints_check cases can observe its notice; the other surfaces are unaffected.
run_hook()      { _run_hook "$GATE" "$1" "${2:-1}"; }
run_hook_gate() { _run_hook "$1" "$2" "${3:-1}"; }
_run_hook() {
  local gate="$1" cmd="$2" skip="$3" input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$( cd "$WORK" && unset GITHUB_BASE_REF; export SKIP_LINT="$skip"; \
         printf '%s' "$input" | bash "$gate" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

has_warn()  { case "$1" in *'[WARN] BL-072 TDD ordering'*) return 0 ;; *) return 1 ;; esac; }
has_fail()  { case "$1" in *'[FAIL] BL-072 TDD ordering'*) return 0 ;; *) return 1 ;; esac; }
is_deny()   { case "$1" in *'"permissionDecision": "deny"'*) return 0 ;; *) return 1 ;; esac; }
has_bl006() { case "$1" in *'no Build Loop active'*|*'Build Loop incomplete'*) return 0 ;; *) return 1 ;; esac; }
# lints_check's OWN SKIP_LINT notice (the terminal-mode branch prints a
# differently-worded one; the ' + ' separators are unique to this site).
has_lint_notice() { case "$1" in *'bypassing counter-antipattern + backlog-references'*) return 0 ;; *) return 1 ;; esac; }

# ── LOUD precondition: the fixture really IS a linked worktree ────────
# Without this the whole suite could pass vacuously on a git that refuses
# `worktree add`, or if the fixture silently degraded to a plain clone.
scaffold none none
WT_OK=1
if [ ! -f "$WTP/.git" ]; then
  WT_OK=0
  echo "  [SKIP] $WTP/.git is not a gitdir POINTER FILE — this git does not"
  echo "         produce linked worktrees in the shape BL-176 is about."
fi
if [ "$WT_OK" -eq 1 ]; then
  make_sentinel CHERRY_PICK_HEAD
  if [ -f "$WTP/.git/CHERRY_PICK_HEAD" ]; then
    WT_OK=0
    echo "  [SKIP] the literal .git/CHERRY_PICK_HEAD path resolves in this worktree —"
    echo "         the blindness BL-176 describes cannot be reproduced here."
  elif [ ! -f "$(gp CHERRY_PICK_HEAD)" ]; then
    WT_OK=0
    echo "  [SKIP] git rev-parse --git-path did not resolve the sentinel."
  fi
fi
teardown
if [ "$WT_OK" -eq 0 ]; then
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Section A — tdd_terminal_enforce (site 1) + the COMMIT_EDITMSG read, in a LINKED WORKTREE ==="
# ════════════════════════════════════════════════════════════════════

echo ""
echo "--- W-A1: NO sentinel + impl-only + strict tier -> the gate REFUSES (rc=1) ---"
use_strict_tier; scaffold 2 none; stage_impl
set_subject "feat: ship impl without a test (normal authoring commit)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 1 ] && has_fail "$body"; then
  pass "W-A1: inside a linked worktree the BL-072 hard block RUNS AT ALL (rc=1 + [FAIL]) — the commit-msg subject is readable"
else
  fail_ "W-A1 worktree gate runs" "expected rc=1 + [FAIL] BL-072; got rc=$rc body: $body"
fi
teardown

echo ""
echo "--- W-A2: CHERRY_PICK_HEAD at the resolved gitdir -> PASS (rc=0) ---"
use_strict_tier; scaffold 2 none; stage_impl; make_sentinel CHERRY_PICK_HEAD
set_subject "feat: replay picked change (impl only)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "W-A2: a resumed cherry-pick in a linked worktree is NOT refused (rc=0)"
else
  fail_ "W-A2 worktree cherry-pick resume" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

echo ""
echo "--- W-A3: REVERT_HEAD at the resolved gitdir -> PASS (rc=0) ---"
use_strict_tier; scaffold 2 none; stage_impl; make_sentinel REVERT_HEAD
set_subject "feat: replay reverted change (impl only)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "W-A3: a resumed revert in a linked worktree is NOT refused (rc=0)"
else
  fail_ "W-A3 worktree revert resume" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

echo ""
echo "--- W-A4: MERGE_HEAD at the resolved gitdir -> PASS (rc=0) ---"
use_strict_tier; scaffold 2 none; stage_impl; make_sentinel MERGE_HEAD
set_subject "feat: finish the merge (impl only)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "W-A4: a resumed merge in a linked worktree is NOT refused (rc=0)"
else
  fail_ "W-A4 worktree merge resume" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Section B — bl006_terminal_enforce (site 2), in a LINKED WORKTREE ==="
# ════════════════════════════════════════════════════════════════════
# Personal tier + a test riding along keeps the BL-072 gate silent, so BL-006 is
# the only enforcer that can refuse.

echo ""
echo "--- W-B1: NO sentinel + feat + Phase 2 + no Build Loop -> BL-006 REFUSES (rc=1) ---"
use_personal_tier; scaffold 2 none; stage_impl_and_test
set_subject "feat: add foo without a Build Loop"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 1 ] && has_bl006 "$body"; then
  pass "W-B1: inside a linked worktree the BL-006 message gate RUNS AT ALL (rc=1 + Build-Loop block)"
else
  fail_ "W-B1 worktree bl006 runs" "expected rc=1 + BL-006 block; got rc=$rc body: $body"
fi
teardown

echo ""
echo "--- W-B2: MERGE_HEAD at the resolved gitdir -> PASS (rc=0) ---"
use_personal_tier; scaffold 2 none; stage_impl_and_test; make_sentinel MERGE_HEAD
set_subject "feat: finish the merge"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_bl006 "$body"; then
  pass "W-B2: a resumed merge in a linked worktree passes the BL-006 message gate (rc=0)"
else
  fail_ "W-B2 worktree bl006 skip" "expected rc=0 + no block; got rc=$rc body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Section C — tdd_warn_check (site 3, PreToolUse WARN), in a LINKED WORKTREE ==="
# ════════════════════════════════════════════════════════════════════

echo ""
echo "--- W-C1: NO sentinel + plain 'git commit' + impl-only -> [WARN] fires (anti-blunt) ---"
use_personal_tier; scaffold none none; stage_impl
res=$(run_hook 'git commit -m "feat: add foo"'); body="${res#*|}"
if has_warn "$body"; then
  pass "W-C1: anti-blunting — a normal impl-only commit still WARNs inside a linked worktree"
else
  fail_ "W-C1 warn anti-blunting" "expected a [WARN]; got: $body"
fi
teardown

echo ""
echo "--- W-C2: CHERRY_PICK_HEAD at the resolved gitdir -> NO [WARN] ---"
use_personal_tier; scaffold none none; stage_impl; make_sentinel CHERRY_PICK_HEAD
res=$(run_hook 'git commit -m "feat: add foo"'); body="${res#*|}"
if ! has_warn "$body"; then
  pass "W-C2: a resumed cherry-pick in a linked worktree passes the WARN surface silently"
else
  fail_ "W-C2 warn worktree skip" "expected NO [WARN]; got: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Section D — bl006_check (site 4, PreToolUse deny), in a LINKED WORKTREE ==="
# ════════════════════════════════════════════════════════════════════

echo ""
echo "--- W-D1: NO sentinel + feat + Phase 2 + no Build Loop -> deny (anti-blunt) ---"
use_personal_tier; scaffold 2 none; stage_docs_only
res=$(run_hook 'git commit -m "feat: add foo without a Build Loop"'); body="${res#*|}"
if is_deny "$body"; then
  pass "W-D1: anti-blunting — the PreToolUse BL-006 gate still denies inside a linked worktree"
else
  fail_ "W-D1 bl006_check anti-blunting" "expected a deny; got: $body"
fi
teardown

echo ""
echo "--- W-D2: MERGE_HEAD at the resolved gitdir -> NO deny ---"
use_personal_tier; scaffold 2 none; stage_docs_only; make_sentinel MERGE_HEAD
res=$(run_hook 'git commit -m "feat: add foo without a Build Loop"'); body="${res#*|}"
if ! is_deny "$body"; then
  pass "W-D2: a resumed merge in a linked worktree passes bl006_check (no deny)"
else
  fail_ "W-D2 bl006_check worktree skip" "expected no deny; got: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Section E — lints_check (site 5, PreToolUse lint promotion), in a LINKED WORKTREE ==="
# ════════════════════════════════════════════════════════════════════

echo ""
echo "--- W-E1: NO sentinel -> lints_check is REACHED (its SKIP_LINT notice prints) ---"
use_personal_tier; scaffold none none; stage "README.md" "# touch"
res=$(run_hook 'git commit -m "docs: touch readme"'); body="${res#*|}"
if has_lint_notice "$body"; then
  pass "W-E1: anti-blunting — lints_check is reached inside a linked worktree when no resume is in progress"
else
  fail_ "W-E1 lints_check reached" "expected the lints_check SKIP_LINT notice; got: $body"
fi
teardown

echo ""
echo "--- W-E2: MERGE_HEAD at the resolved gitdir -> lints_check RETURNS EARLY (no notice) ---"
use_personal_tier; scaffold none none; stage "README.md" "# touch"; make_sentinel MERGE_HEAD
res=$(run_hook 'git commit -m "docs: touch readme"'); body="${res#*|}"
if ! has_lint_notice "$body"; then
  pass "W-E2: a resumed merge in a linked worktree short-circuits lints_check (no notice)"
else
  fail_ "W-E2 lints_check worktree skip" "expected no lints_check notice; got: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Section F — NORMAL-checkout regression + BL-176 rider item 2 ==="
# ════════════════════════════════════════════════════════════════════

echo ""
echo "--- N-F1: normal checkout, NO sentinel + impl-only + strict -> rc=1 REFUSE (unchanged) ---"
use_strict_tier; scaffold 2 none; use_main; stage_impl
set_subject "feat: ship impl without a test (normal authoring commit)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 1 ] && has_fail "$body"; then
  pass "N-F1: the normal-checkout hard block is unchanged (rc=1 + [FAIL])"
else
  fail_ "N-F1 normal-checkout block" "expected rc=1 + [FAIL]; got rc=$rc body: $body"
fi
teardown

echo ""
echo "--- N-F2: normal checkout, literal .git/MERGE_HEAD -> rc=0 PASS (drop-in) ---"
use_strict_tier; scaffold 2 none; use_main; stage_impl; make_sentinel MERGE_HEAD
set_subject "feat: finish the merge (impl only)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body" && [ -f "$MAINP/.git/MERGE_HEAD" ]; then
  pass "N-F2: --git-path is a drop-in in a normal checkout (the sentinel really is at .git/MERGE_HEAD; rc=0)"
else
  fail_ "N-F2 normal-checkout drop-in" "expected rc=0 + no [FAIL] + literal .git/MERGE_HEAD present; got rc=$rc body: $body"
fi
teardown

echo ""
echo "--- N-F3: normal checkout, CHERRY_PICK_HEAD -> bl006_check passes (rider item 2) ---"
use_personal_tier; scaffold 2 none; use_main; stage_docs_only; make_sentinel CHERRY_PICK_HEAD
res=$(run_hook 'git commit -m "feat: add foo without a Build Loop"'); body="${res#*|}"
if ! is_deny "$body"; then
  pass "N-F3: bl006_check now honors CHERRY_PICK_HEAD (was MERGE_HEAD-only) — no deny"
else
  fail_ "N-F3 bl006_check cherry-pick" "expected no deny; got: $body"
fi
teardown

echo ""
echo "--- N-F4: normal checkout, REVERT_HEAD -> lints_check returns early (rider item 2) ---"
use_personal_tier; scaffold none none; use_main; stage "README.md" "# touch"; make_sentinel REVERT_HEAD
res=$(run_hook 'git commit -m "docs: touch readme"'); body="${res#*|}"
if ! has_lint_notice "$body"; then
  pass "N-F4: lints_check now honors REVERT_HEAD (was MERGE_HEAD-only) — no notice"
else
  fail_ "N-F4 lints_check revert" "expected no lints_check notice; got: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Section G — MUTATION, one per changed site ==="
# ════════════════════════════════════════════════════════════════════
# Each mutant reverts EXACTLY ONE marked line of the real gate to its pre-fix
# literal form and re-runs that site's linked-worktree case. A mutant that still
# passes would mean the line is not load-bearing.

MUTROOT=$(mktemp -d)
build_mut_tree() {
  local mut="$1"
  mkdir -p "$mut/scripts/lib"
  cp "$GATE" "$mut/scripts/pre-commit-gate.sh"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$mut/scripts/" 2>/dev/null || true
  cp "$REPO_ROOT"/scripts/lib/*.sh "$mut/scripts/lib/" 2>/dev/null || true
  chmod +x "$mut/scripts/pre-commit-gate.sh"
}

# mutate_skip_site <marker> -> echoes the mutant gate path, or "" on failure.
# Replaces `_derivative_resume_in_progress && return 0   # <marker>` with the
# pre-BL-176 literal `[ -f .git/MERGE_HEAD ] && return 0` (which is blind in a
# linked worktree AND, for the three-sentinel sites, drops two sentinels).
mutate_skip_site() {
  # bash 3.2: a single `local a=$1 b=$a` expands $a BEFORE `local` defines it,
  # which trips `set -u`. Declare, then assign.
  local marker mut g
  marker="$1"
  mut="$MUTROOT/$marker"
  build_mut_tree "$mut"
  g="$mut/scripts/pre-commit-gate.sh"
  sed "s|^\([[:space:]]*\)_derivative_resume_in_progress && return 0[[:space:]]*# ${marker}\$|\1[ -f .git/MERGE_HEAD ] \&\& return 0   # ${marker}|" \
    "$GATE" > "$g"
  chmod +x "$g"
  if grep -q "^[[:space:]]*\[ -f \.git/MERGE_HEAD \] && return 0[[:space:]]*# ${marker}\$" "$g" \
     && bash -n "$g" 2>/dev/null; then
    printf '%s' "$g"
  else
    printf ''
  fi
}

# A missing marker is a real FAILURE, never a silent skip: if the marker moved
# or was renamed, this suite would otherwise stop proving anything while still
# reporting green.
check_mut() {
  local g="$1" name="$2"
  if [ -z "$g" ]; then
    fail_ "(mut $name) preconditions" "the marked line was not found / the mutant is not valid bash — the marker moved or was renamed"
    return 1
  fi
  return 0
}

# ── G1: tdd_terminal_enforce ──────────────────────────────────────────
echo ""
echo "--- G1 (mut): revert BL-176-RESUME-SKIP-TDDTERM -> W-A2 goes RED ---"
MG=$(mutate_skip_site BL-176-RESUME-SKIP-TDDTERM)
if check_mut "$MG" G1; then
  use_strict_tier; scaffold 2 none; stage_impl; make_sentinel CHERRY_PICK_HEAD
  set_subject "feat: replay picked change (impl only)"
  res=$(run_term_gate "$MG"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "G1 RED: with the literal path restored, the worktree cherry-pick resume is refused again (rc=1) — the line is load-bearing"
  else
    fail_ "G1 RED" "mutant did NOT refuse; rc=$rc body: $body"
  fi
  res=$(run_term); rc="${res%%|*}"
  if [ "$rc" -eq 0 ]; then
    pass "G1 GREEN: the real gate passes the same fixture (rc=0) — contrast holds"
  else
    fail_ "G1 GREEN" "real gate refused; rc=$rc"
  fi
  teardown
fi

# ── G2: bl006_terminal_enforce ────────────────────────────────────────
echo ""
echo "--- G2 (mut): revert BL-176-RESUME-SKIP-BL006TERM -> W-B2 goes RED ---"
MG=$(mutate_skip_site BL-176-RESUME-SKIP-BL006TERM)
if check_mut "$MG" G2; then
  use_personal_tier; scaffold 2 none; stage_impl_and_test; make_sentinel MERGE_HEAD
  set_subject "feat: finish the merge"
  res=$(run_term_gate "$MG"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_bl006 "$body"; then
    pass "G2 RED: with the literal path restored, the worktree merge resume is refused by BL-006 again (rc=1)"
  else
    fail_ "G2 RED" "mutant did NOT refuse; rc=$rc body: $body"
  fi
  res=$(run_term); rc="${res%%|*}"
  if [ "$rc" -eq 0 ]; then
    pass "G2 GREEN: the real gate passes the same fixture (rc=0) — contrast holds"
  else
    fail_ "G2 GREEN" "real gate refused; rc=$rc"
  fi
  teardown
fi

# ── G3: tdd_warn_check ────────────────────────────────────────────────
echo ""
echo "--- G3 (mut): revert BL-176-RESUME-SKIP-TDDWARN -> W-C2 goes RED ---"
MG=$(mutate_skip_site BL-176-RESUME-SKIP-TDDWARN)
if check_mut "$MG" G3; then
  use_personal_tier; scaffold none none; stage_impl; make_sentinel CHERRY_PICK_HEAD
  res=$(run_hook_gate "$MG" 'git commit -m "feat: add foo"'); body="${res#*|}"
  if has_warn "$body"; then
    pass "G3 RED: with the literal path restored, the worktree cherry-pick resume WARNs again"
  else
    fail_ "G3 RED" "mutant did NOT warn; body: $body"
  fi
  res=$(run_hook 'git commit -m "feat: add foo"'); body="${res#*|}"
  if ! has_warn "$body"; then
    pass "G3 GREEN: the real gate stays silent on the same fixture — contrast holds"
  else
    fail_ "G3 GREEN" "real gate WARNed; body: $body"
  fi
  teardown
fi

# ── G4: bl006_check ───────────────────────────────────────────────────
echo ""
echo "--- G4 (mut): revert BL-176-RESUME-SKIP-BL006CHECK -> W-D2 goes RED ---"
MG=$(mutate_skip_site BL-176-RESUME-SKIP-BL006CHECK)
if check_mut "$MG" G4; then
  use_personal_tier; scaffold 2 none; stage_docs_only; make_sentinel MERGE_HEAD
  res=$(run_hook_gate "$MG" 'git commit -m "feat: add foo without a Build Loop"'); body="${res#*|}"
  if is_deny "$body"; then
    pass "G4 RED: with the literal path restored, the worktree merge resume is DENIED again by bl006_check"
  else
    fail_ "G4 RED" "mutant did NOT deny; body: $body"
  fi
  res=$(run_hook 'git commit -m "feat: add foo without a Build Loop"'); body="${res#*|}"
  if ! is_deny "$body"; then
    pass "G4 GREEN: the real gate allows the same fixture — contrast holds"
  else
    fail_ "G4 GREEN" "real gate denied; body: $body"
  fi
  teardown
fi

# ── G5: lints_check ───────────────────────────────────────────────────
echo ""
echo "--- G5 (mut): revert BL-176-RESUME-SKIP-LINTS -> W-E2 goes RED ---"
MG=$(mutate_skip_site BL-176-RESUME-SKIP-LINTS)
if check_mut "$MG" G5; then
  use_personal_tier; scaffold none none; stage "README.md" "# touch"; make_sentinel MERGE_HEAD
  res=$(run_hook_gate "$MG" 'git commit -m "docs: touch readme"'); body="${res#*|}"
  if has_lint_notice "$body"; then
    pass "G5 RED: with the literal path restored, lints_check is reached again inside the worktree merge resume"
  else
    fail_ "G5 RED" "mutant short-circuited anyway; body: $body"
  fi
  res=$(run_hook 'git commit -m "docs: touch readme"'); body="${res#*|}"
  if ! has_lint_notice "$body"; then
    pass "G5 GREEN: the real gate short-circuits on the same fixture — contrast holds"
  else
    fail_ "G5 GREEN" "real gate reached lints_check; body: $body"
  fi
  teardown
fi

# ── G6: the COMMIT_EDITMSG read ───────────────────────────────────────
echo ""
echo "--- G6 (mut): revert BL-176-GITPATH-EDITMSG -> W-A1 and W-B1 go RED (the gates stop running) ---"
MUT6="$MUTROOT/editmsg"
build_mut_tree "$MUT6"
MG="$MUT6/scripts/pre-commit-gate.sh"
sed 's|^\([[:space:]]*\)COMMIT_MSG=.*# BL-176-GITPATH-EDITMSG$|\1COMMIT_MSG=$(cat .git/COMMIT_EDITMSG 2>/dev/null \|\| echo "")   # BL-176-GITPATH-EDITMSG|' \
  "$GATE" > "$MG"
chmod +x "$MG"
if ! grep -q 'COMMIT_MSG=\$(cat \.git/COMMIT_EDITMSG 2>/dev/null || echo "")   # BL-176-GITPATH-EDITMSG' "$MG" \
   || ! bash -n "$MG" 2>/dev/null; then
  fail_ "(mut G6) preconditions" "the BL-176-GITPATH-EDITMSG line was not found / the mutant is not valid bash"
else
  use_strict_tier; scaffold 2 none; stage_impl
  set_subject "feat: ship impl without a test (normal authoring commit)"
  res=$(run_term_gate "$MG"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
    pass "G6 RED (BL-072): with the literal COMMIT_EDITMSG read restored, the worktree subject is unreadable and the TDD hard block silently does not run (rc=0) — an OPEN-direction bypass"
  else
    fail_ "G6 RED (BL-072)" "expected the mutant to silently pass; got rc=$rc body: $body"
  fi
  res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "G6 GREEN (BL-072): the real gate reads the subject and refuses (rc=1) — contrast holds"
  else
    fail_ "G6 GREEN (BL-072)" "real gate did not refuse; rc=$rc body: $body"
  fi
  teardown

  use_personal_tier; scaffold 2 none; stage_impl_and_test
  set_subject "feat: add foo without a Build Loop"
  res=$(run_term_gate "$MG"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 0 ] && ! has_bl006 "$body"; then
    pass "G6 RED (BL-006): the same mutation silently disables the Build-Loop message gate inside a linked worktree (rc=0)"
  else
    fail_ "G6 RED (BL-006)" "expected the mutant to silently pass; got rc=$rc body: $body"
  fi
  res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_bl006 "$body"; then
    pass "G6 GREEN (BL-006): the real gate refuses (rc=1) — contrast holds"
  else
    fail_ "G6 GREEN (BL-006)" "real gate did not refuse; rc=$rc body: $body"
  fi
  teardown
fi

rm -rf "$MUTROOT"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

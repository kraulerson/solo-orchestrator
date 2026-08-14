#!/usr/bin/env bash
# tests/test-bl174-gitignore-backfill.sh — BL-174: upgrade-project.sh's
# _run_idempotent_backfill must append the BL-030 / BL-161 operational-state
# ignore lines to a project's .gitignore, so an UPGRADED project keeps the two
# sidecars out of git exactly like an init.sh-scaffolded one:
#   .claude/last-checked-commit.txt  (BL-030 detection baseline)
#   .claude/last-gate-pass.txt       (BL-161 terminal-commit gate-ran receipt)
#
# Before this backfill an upgraded strict project picked up the receipt-WRITING
# gate behavior (via the install-filesystem-gates.sh re-run in the same block)
# but never the matching .gitignore lines — so the receipt sat UNTRACKED and a
# downstream `git add -A` would TRACK it, resurrecting the BL-161 dirty-chase in
# tracked form. (Untracked != tracked-dirty, so the pre-fix state is strictly
# better than what BL-161 removed — this pins the last mile.)
#
# ARTIFACT PIN: the two ignore LINES are the artifacts. This suite pins them
# BEHAVIORALLY (git check-ignore) on the BACKFILL side (an upgraded fixture).
# The TEMPLATE side is pinned by tests/test-bl161-ledger-real-events-only.sh T7.
#
# HERMETIC: hand-built fixture — NO init.sh, NO live remote. A local git repo in
# mktemp drives the REAL scripts/upgrade-project.sh via --backfill-only (whose
# path reaches _run_idempotent_backfill and NEVER hits a framework-repo guard —
# guard_not_in_framework sits only past the --backfill-only exit-0 short-circuit).
# The script + its lib closure are copied into the fixture; scripts/lib/cdf-refresh.sh
# is deliberately OMITTED so the --backfill-only CDF-sync short-circuit finds no
# refresher and skips it (no `git pull`, so the suite stays offline). No init.sh,
# not an aggregator -> registered in BOTH the tests.yml unit lane and the
# full-project aggregator. bash-3.2 safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

LINE_LC='.claude/last-checked-commit.txt'
LINE_GP='.claude/last-gate-pass.txt'
# BL-236 added a THIRD line to the same backfill. It is pinned here rather
# than only in its own suite, because THIS is the suite that exists to keep
# the gitignore-base template and the upgrade backfill in lockstep — a new
# managed line that no lockstep test knows about is the BL-174 defect itself,
# reintroduced one line lower.
LINE_TU='.claude/tool-usage.json'

# mk_proj <dir> <gitignore-mode> [project-mode=generated] — a hand-built strict
# project WITHOUT init.sh. In `generated` mode a MODERN manifest (host +
# enforcement_level present) makes the host-migration and BL-030 manifest
# backfills SKIP, so the BL-174 gitignore backfill is the only writer exercised.
# In `noproject` mode NEITHER .claude/manifest.json NOR .claude/phase-state.json
# is written, so find_project_root returns empty (PROJECT_ROOT="") and the
# subshell's `cd "$PROJECT_ROOT"` no-ops — reproducing the framework-repo /
# projectless invocation the BL-174 backfill MUST NOT write into.
# <gitignore-mode>:
#   custom — custom user lines, NONE of the managed lines (backfill adds all 3)
#   both   — custom lines AND all three managed lines present (no-op case)
#   none   — no .gitignore at all (create-if-missing case)
mk_proj() {
  local d="$1" mode="$2" pmode="${3:-generated}"
  rm -rf "$d"; mkdir -p "$d/.claude" "$d/scripts/lib"
  cp "$REPO_ROOT/scripts/upgrade-project.sh" "$d/scripts/"
  cp "$REPO_ROOT"/scripts/lib/*.sh "$d/scripts/lib/" 2>/dev/null
  rm -f "$d/scripts/lib/cdf-refresh.sh"   # keep --backfill-only offline (no git pull)
  chmod +x "$d/scripts/upgrade-project.sh"
  if [ "$pmode" = generated ]; then
    printf '{"current_phase":2,"deployment":"personal","poc_mode":null,"track":"standard"}\n' \
      > "$d/.claude/phase-state.json"
    printf '{"frameworkVersion":"test","host":"github","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}\n' \
      > "$d/.claude/manifest.json"
  fi
  case "$mode" in
    custom) printf 'node_modules/\ndist/\n*.log\n.env\n' > "$d/.gitignore" ;;
    both)   printf 'node_modules/\ndist/\n%s\n%s\n%s\n' "$LINE_LC" "$LINE_GP" "$LINE_TU" > "$d/.gitignore" ;;
    none)   : ;;  # no .gitignore
  esac
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && git add -A && git commit -q -m "chore: seed" ) >/dev/null 2>&1 || return 1
}

# run_backfill <dir> — drive the copied upgrade script's --backfill-only path.
run_backfill() {
  ( cd "$1" && bash "$1/scripts/upgrade-project.sh" --backfill-only >/dev/null 2>&1 ) || true
}

# ignored <dir> <path> — 0 iff git ignores <path> in <dir>.
ignored() { ( cd "$1" && git check-ignore -q "$2" ); }

# count_line <file> <line> — exact whole-line occurrences (fixed string).
# grep -c prints "0" AND exits 1 on no-match, so capture-then-default (never
# `grep -c || echo 0`, which would emit "0\n0").
count_line() {
  local n
  [ -f "$1" ] || { echo 0; return 0; }
  n=$(grep -cxF "$2" "$1" 2>/dev/null) || n=0
  echo "$n"
}

# ── T1 (case a): the backfill adds BOTH ignore lines; git check-ignore keeps the
# two sidecars out of git. THE DISCRIMINATOR — pre-fix neither line exists so
# check-ignore fails (RED); post-fix both are ignored (GREEN).
echo "=== T1-backfill-adds-both-ignore-lines ==="
if mk_proj "$TOPTMP/t1" custom; then
  run_backfill "$TOPTMP/t1"
  lc=no; ignored "$TOPTMP/t1" "$LINE_LC" && lc=yes
  gp=no; ignored "$TOPTMP/t1" "$LINE_GP" && gp=yes
  tu=no; ignored "$TOPTMP/t1" "$LINE_TU" && tu=yes
  if [ "$lc" = yes ] && [ "$gp" = yes ] && [ "$tu" = yes ]; then
    pass "T1-backfill-adds-both-ignore-lines (check-ignore keeps last-checked-commit.txt + last-gate-pass.txt + the BL-236 tool-usage ledger out of git)"
  else
    fail_ "T1-backfill-adds-both-ignore-lines" "last-checked-commit ignored=$lc last-gate-pass ignored=$gp tool-usage ignored=$tu (want yes/yes/yes) — .gitignore: $(tr '\n' '|' < "$TOPTMP/t1/.gitignore" 2>/dev/null)"
  fi
else
  fail_ "T1-backfill-adds-both-ignore-lines" "fixture build failed"
fi

# ── T2 (case b): idempotent — a SECOND backfill is a byte-no-op and each exact
# line appears EXACTLY once. Pre-fix the lines are absent (count 0) -> RED.
echo "=== T2-idempotent-second-run-is-byte-noop ==="
if mk_proj "$TOPTMP/t2" custom; then
  run_backfill "$TOPTMP/t2"
  cp "$TOPTMP/t2/.gitignore" "$TOPTMP/t2.after1"
  run_backfill "$TOPTMP/t2"
  nlc=$(count_line "$TOPTMP/t2/.gitignore" "$LINE_LC")
  ngp=$(count_line "$TOPTMP/t2/.gitignore" "$LINE_GP")
  ntu=$(count_line "$TOPTMP/t2/.gitignore" "$LINE_TU")
  same=no; cmp -s "$TOPTMP/t2.after1" "$TOPTMP/t2/.gitignore" && same=yes
  if [ "$nlc" -eq 1 ] && [ "$ngp" -eq 1 ] && [ "$ntu" -eq 1 ] && [ "$same" = yes ]; then
    pass "T2-idempotent-second-run-is-byte-noop (each of the 3 managed lines x1, .gitignore byte-identical across the 2nd run)"
  else
    fail_ "T2-idempotent-second-run-is-byte-noop" "count last-checked=$nlc last-gate-pass=$ngp tool-usage=$ntu (want 1/1/1) byte_identical_2nd_run=$same (want yes)"
  fi
else
  fail_ "T2-idempotent-second-run-is-byte-noop" "fixture build failed"
fi

# ── T3 (case c): pre-existing user content is preserved, nothing overwritten.
echo "=== T3-user-content-preserved ==="
if mk_proj "$TOPTMP/t3" custom; then
  run_backfill "$TOPTMP/t3"
  missing=""
  for want in 'node_modules/' 'dist/' '*.log' '.env'; do
    grep -qxF "$want" "$TOPTMP/t3/.gitignore" 2>/dev/null || missing="$missing $want"
  done
  if [ -z "$missing" ]; then
    pass "T3-user-content-preserved (all 4 custom user lines still present after the backfill append)"
  else
    fail_ "T3-user-content-preserved" "missing custom line(s):$missing"
  fi
else
  fail_ "T3-user-content-preserved" "fixture build failed"
fi

# ── T4 (case d): a .gitignore that ALREADY has both lines is a byte-no-op — the
# backfill neither duplicates nor rewrites. (Green pre- and post-fix — it pins
# idempotence against a wrong append-always implementation, and keeps a correct
# .gitignore undisturbed.)
echo "=== T4-already-present-is-byte-noop ==="
if mk_proj "$TOPTMP/t4" both; then
  cp "$TOPTMP/t4/.gitignore" "$TOPTMP/t4.before"
  run_backfill "$TOPTMP/t4"
  same=no; cmp -s "$TOPTMP/t4.before" "$TOPTMP/t4/.gitignore" && same=yes
  nlc=$(count_line "$TOPTMP/t4/.gitignore" "$LINE_LC")
  ngp=$(count_line "$TOPTMP/t4/.gitignore" "$LINE_GP")
  ntu=$(count_line "$TOPTMP/t4/.gitignore" "$LINE_TU")
  lc=no; ignored "$TOPTMP/t4" "$LINE_LC" && lc=yes
  gp=no; ignored "$TOPTMP/t4" "$LINE_GP" && gp=yes
  tu=no; ignored "$TOPTMP/t4" "$LINE_TU" && tu=yes
  if [ "$same" = yes ] && [ "$nlc" -eq 1 ] && [ "$ngp" -eq 1 ] && [ "$ntu" -eq 1 ] \
     && [ "$lc" = yes ] && [ "$gp" = yes ] && [ "$tu" = yes ]; then
    pass "T4-already-present-is-byte-noop (byte-identical, each of the 3 managed lines x1, all still ignored)"
  else
    fail_ "T4-already-present-is-byte-noop" "byte_identical=$same count last-checked=$nlc last-gate-pass=$ngp tool-usage=$ntu (want 1/1/1) ignored lc=$lc gp=$gp tu=$tu"
  fi
else
  fail_ "T4-already-present-is-byte-noop" "fixture build failed"
fi

# ── T5 (case e): a project with NO .gitignore at all gets one CREATED with both
# lines (mirroring the create-if-missing posture of the sibling
# last-checked-commit.txt / bypass-audit.json backfills in the same function).
# Pre-fix no .gitignore is created -> check-ignore fails -> RED.
echo "=== T5-missing-gitignore-is-created ==="
if mk_proj "$TOPTMP/t5" none; then
  before=absent; [ -f "$TOPTMP/t5/.gitignore" ] && before=present
  run_backfill "$TOPTMP/t5"
  after=absent; [ -f "$TOPTMP/t5/.gitignore" ] && after=present
  lc=no; ignored "$TOPTMP/t5" "$LINE_LC" && lc=yes
  gp=no; ignored "$TOPTMP/t5" "$LINE_GP" && gp=yes
  if [ "$before" = absent ] && [ "$after" = present ] && [ "$lc" = yes ] && [ "$gp" = yes ]; then
    pass "T5-missing-gitignore-is-created (.gitignore created; both sidecars ignored)"
  else
    fail_ "T5-missing-gitignore-is-created" ".gitignore before=$before after=$after; ignored lc=$lc gp=$gp (want absent/present/yes/yes)"
  fi
else
  fail_ "T5-missing-gitignore-is-created" "fixture build failed"
fi

# ── T6 (framework-repo / projectless safety): a fixture with NO
# .claude/manifest.json (find_project_root returns empty, the subshell's `cd`
# no-ops, cwd stays the invocation dir) must be a byte-no-op — the backfill is
# gated on the generated-project marker exactly like its sibling backfills, so it
# NEVER appends these lines to a non-project (e.g. the framework repo's own)
# .gitignore. Pre-guard the unguarded block wrote here -> RED.
echo "=== T6-no-manifest-projectless-is-byte-noop ==="
if mk_proj "$TOPTMP/t6" custom noproject; then
  cp "$TOPTMP/t6/.gitignore" "$TOPTMP/t6.before"
  run_backfill "$TOPTMP/t6"
  same=no; cmp -s "$TOPTMP/t6.before" "$TOPTMP/t6/.gitignore" && same=yes
  nlc=$(count_line "$TOPTMP/t6/.gitignore" "$LINE_LC")
  ngp=$(count_line "$TOPTMP/t6/.gitignore" "$LINE_GP")
  if [ "$same" = yes ] && [ "$nlc" -eq 0 ] && [ "$ngp" -eq 0 ]; then
    pass "T6-no-manifest-projectless-is-byte-noop (no generated-project marker → .gitignore byte-unchanged; no framework-repo pollution)"
  else
    fail_ "T6-no-manifest-projectless-is-byte-noop" "byte_identical=$same last-checked count=$nlc last-gate-pass count=$ngp (want yes/0/0) — the backfill wrote into a projectless .gitignore"
  fi
else
  fail_ "T6-no-manifest-projectless-is-byte-noop" "fixture build failed"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

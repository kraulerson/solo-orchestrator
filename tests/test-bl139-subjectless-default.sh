#!/usr/bin/env bash
# tests/test-bl139-subjectless-default.sh — BL-139 (Dogfood-3 F-DF3-004):
# a subject-less --check-commit-ready must not presume "feat".
#
# THE DEFECT (walk-proven)
#   .git/hooks/framework-gate.sh invokes `process-checklist.sh
#   --check-commit-ready` with NO --subject; `subject_is_feat` defaulted
#   TRUE, so at Phase 2 ANY staged source file demanded a complete Build
#   Loop — legitimate `test:`/`chore:`/`refactor:` source commits were
#   blocked on the user-terminal path, defeating the documented
#   code-process-checklist-5 short-circuit.
#
# THE DOCTRINE (BL-119): pre-commit CANNOT know the current subject (git
# writes COMMIT_EDITMSG after pre-commit). The commit-msg surface
# (--terminal-mode --tdd-only → BL-006) enforces feat-requires-Build-Loop
# with the CURRENT subject one stage later. Therefore the subject-less
# default flips to NOT-feat (# BL-139-SUBJECTLESS-DEFAULT): no enforcement
# is lost — a test-less/loop-less feat commit still dies at commit-msg —
# and non-feat source commits stop false-blocking at pre-commit. T4 proves
# the backstop END-TO-END with the real installed hook chain.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. Hermetic
# (real installer + real commits inside mktemp fixtures; fake remote never
# contacted). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_p2 <dir> — phase-2 project, init verified, NO active Build Loop, one
# staged source file. Direct-invocation fixture (T1–T3, T5).
mk_p2() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/src"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"gates":{}}
JSON
  cat > "$d/.claude/process-state.json" <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial"],"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
JSON
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh"
  ( cd "$d" && printf 'export const x = 1;\n' > src/widget.ts && git add src/widget.ts )
}

run_ccr() {  # run_ccr <dir> [subject]
  local d="$1" subj="${2:-}"
  if [ -n "$subj" ]; then
    ( cd "$d" && bash scripts/process-checklist.sh --check-commit-ready --subject "$subj" </dev/null 2>&1 )
  else
    ( cd "$d" && bash scripts/process-checklist.sh --check-commit-ready </dev/null 2>&1 )
  fi
}

# ── T1 (the walk's repro): subject-less + staged source + no loop → ALLOW ────
echo "=== T1-subjectless-not-feat ==="
P="$TOPTMP/p1"; mk_p2 "$P"
out=$(run_ccr "$P"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T1-subjectless-not-feat (pre-commit no longer presumes feat; commit-msg owns the feat rule)"
else
  fail_ "T1-subjectless-not-feat" "rc=$rc — a subject-less --check-commit-ready blocked a source commit as presumed-feat (F-DF3-004): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T2: an EXPLICIT feat subject still requires the Build Loop ───────────────
echo "=== T2-explicit-feat-still-blocks ==="
P="$TOPTMP/p2"; mk_p2 "$P"
out=$(run_ccr "$P" "feat: add widget"); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T2-explicit-feat-still-blocks"
else
  fail_ "T2-explicit-feat-still-blocks" "rc=0 — an explicit feat subject with NO Build Loop passed --check-commit-ready (the short-circuit inverted into a hole)"
fi

# ── T3: the documented non-feat short-circuit still works ────────────────────
echo "=== T3-nonfeat-subject-allows ==="
P="$TOPTMP/p3"; mk_p2 "$P"
out=$(run_ccr "$P" "test(e2e): cover widget"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T3-nonfeat-subject-allows"
else
  fail_ "T3-nonfeat-subject-allows" "rc=$rc — the code-process-checklist-5 short-circuit regressed: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T4: END-TO-END backstop — real hooks, real commits ───────────────────────
# The flip is only safe because the COMMIT-MSG surface still enforces the
# feat rule with the CURRENT subject. Prove both directions through the real
# installed chain: `test:` source commit LANDS; test-less `feat:` commit is
# BLOCKED (by the commit-msg hook, one stage later).
echo "=== T4-e2e-backstop ==="
P="$TOPTMP/p4"
rm -rf "$P"
mkdir -p "$P/.claude" "$P/scripts/lib" "$P/src"
( cd "$P" && git init -q && git config user.email t@t.invalid && git config user.name t \
    && echo "# scratch" > README.md && git add README.md && git commit -q -m "chore: init" \
    && git remote add origin https://example.invalid/x.git ) || true
cat > "$P/.claude/manifest.json" <<'JSON'
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
JSON
cat > "$P/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
JSON
cat > "$P/.claude/process-state.json" <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial"],"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
JSON
cp "$REPO_ROOT/scripts/process-checklist.sh" "$P/scripts/"
cp "$REPO_ROOT/scripts/pre-commit-gate.sh"   "$P/scripts/"
cp "$REPO_ROOT/scripts/install-filesystem-gates.sh" "$P/scripts/"
cp "$REPO_ROOT/scripts/lib/helpers.sh" \
   "$REPO_ROOT/scripts/lib/helpers-core.sh" \
   "$REPO_ROOT/scripts/lib/helpers-full.sh" \
   "$REPO_ROOT/scripts/lib/tdd-classify.sh" "$P/scripts/lib/"
chmod +x "$P/scripts/"*.sh
bash "$REPO_ROOT/scripts/install-filesystem-gates.sh" --install "$P" >/dev/null 2>&1
printf '%s\n' '#!/usr/bin/env bash' > "$P/.git/hooks/commit-msg"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/hook-templates.sh"
soif_emit_tdd_commitmsg_block >> "$P/.git/hooks/commit-msg"
chmod +x "$P/.git/hooks/commit-msg"
if [ ! -x "$P/.git/hooks/framework-gate.sh" ]; then
  fail_ "T4-e2e-backstop" "real installer did not produce framework-gate.sh — fixture invalid"
else
  ( cd "$P" && printf 'export const a = 1;\n' > src/a.ts && git add src/a.ts \
      && git commit -m "test(unit): cover a" >"$P/c1.log" 2>&1 )
  rc1=$?
  ( cd "$P" && printf 'export const b = 2;\n' > src/b.ts && git add src/b.ts \
      && git commit -m "feat: add b" >"$P/c2.log" 2>&1 )
  rc2=$?
  if [ "$rc1" -eq 0 ] && [ "$rc2" -ne 0 ] && grep -qi "build loop\|feat" "$P/c2.log"; then
    pass "T4-e2e-backstop (test: lands; loop-less feat: still dies at the commit-msg surface)"
  else
    fail_ "T4-e2e-backstop" "rc1=$rc1 (want 0) rc2=$rc2 (want !=0) — either non-feat source commits still block, or the feat rule lost its commit-msg backstop: c1=$(tail -2 "$P/c1.log" | tr '\n' ' ') c2=$(tail -2 "$P/c2.log" | tr '\n' ' ')"
  fi
fi

# ── T5: fence-excision mutant — the flipped default lives in the fence ───────
echo "=== T5-fence-excision-mutant ==="
P="$TOPTMP/p5"; mk_p2 "$P"
sed '/# BL-139-SUBJECTLESS-DEFAULT-BEGIN/,/# BL-139-SUBJECTLESS-DEFAULT-END/d' \
  "$REPO_ROOT/scripts/process-checklist.sh" > "$P/scripts/process-checklist.sh"
chmod +x "$P/scripts/process-checklist.sh"
if grep -q "BL-139-SUBJECTLESS-DEFAULT" "$P/scripts/process-checklist.sh"; then
  fail_ "T5-fence-excision-mutant" "excision left marker text — BEGIN/END malformed"
else
  out=$(run_ccr "$P"); rc=$?
  out3=$(run_ccr "$P" "test(e2e): x"); rc3=$?
  if [ "$rc" -ne 0 ] && [ "$rc3" -eq 0 ]; then
    pass "T5-fence-excision-mutant (guardless mutant re-presumes feat on subject-less calls; explicit subjects unaffected — the fence carries exactly the default)"
  else
    fail_ "T5-fence-excision-mutant" "subjectless rc=$rc (want !=0) with-subject rc=$rc3 (want 0) — mutant did not restore the old default (logic outside the fence) or crashed (vacuous): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

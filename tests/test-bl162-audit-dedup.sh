#!/usr/bin/env bash
# tests/test-bl162-audit-dedup.sh — BL-162 (Dogfood-4 S2, F-DF4-008):
# the BL-120 security-audit verdict arm globs candidate files by BOTH
# `*<feature_slug>*` and `*<feature_name>*`. When slug == name (an already-
# slug-shaped feature like "find-in-document") the SAME artifact matches both
# globs, so — before the fix — the same file was processed twice and its
# `records N OPEN finding(s)` warning printed TWICE. The BLOCK itself was
# always correct (exactly one step-refusal); only the duplicate PRINT was the
# bug.
#
# THE FIX (# BL-162-AUDIT-DEDUP): deduplicate the matched-file list by path
# before the verdict loop, so each distinct audit file is processed — and its
# verdict printed — exactly once. It is print-count only: the newest-mtime
# selection and any-open-blocks semantics are unchanged.
#
# Cases:
#   T1-slug-eq-name-single-warn  slug==name + one OPEN-finding audit →
#                                the OPEN-finding warning appears EXACTLY ONCE
#                                and the step still BLOCKS (rc!=0, not recorded).
#   T2-slug-neq-name-single-warn slug!=name ("Comment Widget") + OPEN finding →
#                                still exactly one warning, still BLOCKS (the fix
#                                did not perturb the normal one-glob path).
#   T3-mutation                  revert the dedup (strip the # BL-162 case guard)
#                                from a fixture copy → the slug==name fixture
#                                prints the warning TWICE again (RED); the real
#                                script prints it once (GREEN).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists (tests.yml unit
# list + full-project-test-suite.sh). Hermetic (mktemp fixtures, no remote).
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)).

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

# mk_loop <dir> <feature-name> — phase-2 project with an ACTIVE Build Loop for
# <feature-name>, the three prior steps completed, so
# --complete-step build_loop:security_audit reaches the artifact/verdict check.
mk_loop() {
  local d="$1" feat="$2"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/docs/security-audits"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"gates":{}}
JSON
  cat > "$d/.claude/process-state.json" <<JSON
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial"],"verified":true},"build_loop":{"feature":"$feat","step":3,"steps_completed":["tests_written","tests_verified_failing","implemented"]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
JSON
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh"
}

# An audit body that records OPEN findings → the verdict arm must WARN + BLOCK.
open_audit() {  # open_audit <path>
  cat > "$1" <<'EOF'
# Security Audit Findings

## Summary

| Status | Count |
|--------|-------|
| Fixed | 1 |
| Open | 2 |

**All findings resolved:** No
EOF
}

run_audit_step() {  # run_audit_step <dir> [script-rel-path]
  local d="$1" rel="${2:-scripts/process-checklist.sh}"
  ( cd "$d" && bash "$rel" --complete-step build_loop:security_audit </dev/null 2>&1 )
}

step_recorded() {  # step_recorded <dir> → 0 iff security_audit landed in state
  jq -e '.build_loop.steps_completed | index("security_audit")' \
    "$1/.claude/process-state.json" >/dev/null 2>&1
}

# Count how many times the OPEN-finding verdict warning appears in output.
open_warn_count() { printf '%s\n' "$1" | grep -c 'OPEN finding(s)' || true; }

# ── T1: slug == name ("find-in-document") — the warning prints EXACTLY once ───
echo "=== T1-slug-eq-name-single-warn ==="
P="$TOPTMP/p1"; mk_loop "$P" "find-in-document"
open_audit "$P/docs/security-audits/find-in-document-security-audit.md"
out=$(run_audit_step "$P"); rc=$?
n=$(open_warn_count "$out")
if [ "$rc" -ne 0 ] && ! step_recorded "$P" && [ "$n" -eq 1 ]; then
  pass "T1-slug-eq-name-single-warn (slug==name: one OPEN warning, step still BLOCKS)"
else
  fail_ "T1-slug-eq-name-single-warn" "rc=$rc warn_count=$n (want rc!=0, not-recorded, count=1) — $(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T2: slug != name ("Comment Widget") — normal one-glob path unaffected ─────
echo "=== T2-slug-neq-name-single-warn ==="
P="$TOPTMP/p2"; mk_loop "$P" "Comment Widget"
open_audit "$P/docs/security-audits/comment-widget-security-audit.md"
out=$(run_audit_step "$P"); rc=$?
n=$(open_warn_count "$out")
if [ "$rc" -ne 0 ] && ! step_recorded "$P" && [ "$n" -eq 1 ]; then
  pass "T2-slug-neq-name-single-warn (slug!=name still prints once and BLOCKS — dedup did not perturb it)"
else
  fail_ "T2-slug-neq-name-single-warn" "rc=$rc warn_count=$n (want rc!=0, not-recorded, count=1) — $(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T3: mutation — revert the dedup → the slug==name double-print returns ─────
# Strip the # BL-162-AUDIT-DEDUP case guard (the load-bearing skip) from a
# fixture copy so both globs are processed again. RED: the warning prints
# twice. GREEN: the real (deduped) script prints it once. Both still BLOCK.
echo "=== T3-mutation-dedup-load-bearing ==="
P="$TOPTMP/p3"; mk_loop "$P" "find-in-document"
open_audit "$P/docs/security-audits/find-in-document-security-audit.md"
MUT="$P/scripts/process-checklist.mut.sh"
# Delete the dedup guard: from the `case "${bl120_nl}${bl120_seen}"` line
# through its terminating `esac` (single-quoted so the shell does not expand
# the $bl120_* tokens — they are literal text in the target script).
sed '/case "${bl120_nl}${bl120_seen}"/,/esac/d' \
  "$P/scripts/process-checklist.sh" > "$MUT" && chmod +x "$MUT"
mut_ok=1
grep -q 'bl120_seen' "$P/scripts/process-checklist.sh" || mut_ok=0   # guard present in REAL
if grep -q '${bl120_nl}${bl120_seen}' "$MUT"; then mut_ok=0; fi       # guard gone in MUTANT
if ! bash -n "$MUT" 2>/dev/null; then mut_ok=0; fi                    # mutant still valid
if [ "$mut_ok" -ne 1 ]; then
  fail_ "T3-mutation-dedup-load-bearing" "mutation vacuous/invalid (real has guard? mutant stripped? syntax ok?)"
else
  mout=$(run_audit_step "$P" "scripts/process-checklist.mut.sh"); mrc=$?
  mn=$(open_warn_count "$mout")
  # RED: reverting the dedup restores the double-print (still blocks).
  if [ "$mrc" -ne 0 ] && [ "$mn" -eq 2 ]; then
    pass "T3-mutation (RED): reverting the dedup prints the OPEN warning TWICE again (still BLOCKS)"
  else
    fail_ "T3-mutation (RED)" "mrc=$mrc mut_warn_count=$mn (want rc!=0, count=2) — dedup guard not load-bearing"
  fi
  # GREEN: the real deduped script prints it once on the same fixture.
  rout=$(run_audit_step "$P"); rrc=$?
  rn=$(open_warn_count "$rout")
  if [ "$rrc" -ne 0 ] && [ "$rn" -eq 1 ]; then
    pass "T3-mutation (GREEN): the real (deduped) script prints the OPEN warning once (contrast holds)"
  else
    fail_ "T3-mutation (GREEN)" "rrc=$rrc real_warn_count=$rn (want rc!=0, count=1) — contrast broken"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

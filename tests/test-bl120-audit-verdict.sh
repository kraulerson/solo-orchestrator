#!/usr/bin/env bash
# tests/test-bl120-audit-verdict.sh — BL-120 (Dogfood-2 F-DF2-008):
# the Build-Loop security_audit step must READ the audit's verdict, not
# just find a file.
#
# THE DEFECT (walk-proven)
#   `--complete-step build_loop:security_audit` verified only that a file
#   whose name contains the feature slug exists under docs/security-audits/.
#   During the walk, an audit whose own heading read "CRITICAL — VULNERABLE.
#   DO NOT SHIP." satisfied the step and a live stored XSS committed. The
#   template even PROMISES the enforcement ("must … have no 'Open' findings
#   before the security_audit process step can be marked complete") — the
#   cardinal documented-but-not-enforced class.
#
# THE FIX (# BL-120-AUDIT-VERDICT): the step parses the SHIPPED template's
# own grammar in the newest matching audit file, fail-closed:
#   - block on a Summary `| Open | N |` row with N > 0;
#   - require an unqualified `**All findings resolved:** Yes` (the unfilled
#     placeholder `Yes / No` and an explicit `No` both block);
#   - no parseable verdict at all → block (an audit the gate cannot read is
#     not a passed audit).
# Zero new template surface: the grammar is the template's existing Summary.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists (tests.yml unit
# list + full-project-test-suite.sh). Hermetic (mktemp fixtures, no remote).
# bash-3.2 safe. T6 uses touch -t with distinct MINUTES (BL-140 D-extra
# lesson: never rely on same-second mtime ordering).

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

# mk_loop <dir> — phase-2 project with an ACTIVE Build Loop for feature
# "Comment Widget" (slug comment-widget), the three prior steps completed,
# so --complete-step build_loop:security_audit reaches the artifact check.
mk_loop() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/docs/security-audits"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"gates":{}}
JSON
  cat > "$d/.claude/process-state.json" <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial"],"verified":true},"build_loop":{"feature":"Comment Widget","step":3,"steps_completed":["tests_written","tests_verified_failing","implemented"]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
JSON
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh"
}

run_audit_step() {  # run_audit_step <dir>
  ( cd "$1" && bash scripts/process-checklist.sh --complete-step build_loop:security_audit </dev/null 2>&1 )
}

step_recorded() {  # step_recorded <dir> → 0 iff security_audit landed in state
  jq -e '.build_loop.steps_completed | index("security_audit")' \
    "$1/.claude/process-state.json" >/dev/null 2>&1
}

AUDIT=docs/security-audits/comment-widget-security-audit.md

# ── T1 (the walk's repro): a DO-NOT-SHIP audit with no verdict grammar ───────
# Pre-fix this completes the step (existence-only). It must BLOCK.
echo "=== T1-do-not-ship-blocks ==="
P="$TOPTMP/p1"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit — Feature: Comment Widget

## ROUND 1 — the naive implementation

CRITICAL — VULNERABLE. DO NOT SHIP.

Stored XSS: comment body rendered via innerHTML with no sanitization.
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T1-do-not-ship-blocks (unreadable-verdict audit no longer satisfies the step)"
else
  fail_ "T1-do-not-ship-blocks" "rc=$rc — an audit saying DO NOT SHIP completed security_audit (F-DF2-008): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T2: explicit **All findings resolved:** No → BLOCK ───────────────────────
echo "=== T2-resolved-no-blocks ==="
P="$TOPTMP/p2"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

**Date:** 2026-07-18

## Summary

| Status | Count |
|--------|-------|
| Fixed | 2 |
| Open | 0 |

**All findings resolved:** No
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T2-resolved-no-blocks"
else
  fail_ "T2-resolved-no-blocks" "rc=$rc — an audit recording 'All findings resolved: No' completed the step"
fi

# ── T3: resolved says Yes but Summary records Open findings → BLOCK ──────────
echo "=== T3-open-count-dominates ==="
P="$TOPTMP/p3"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

**Date:** 2026-07-18

## Summary

| Status | Count |
|--------|-------|
| Fixed | 1 |
| Open | 3 |

**All findings resolved:** Yes
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T3-open-count-dominates (a negative signal beats a contradicting Yes)"
else
  fail_ "T3-open-count-dominates" "rc=$rc — 3 recorded Open findings did not block the step"
fi

# ── T4: honestly-filled clean audit → step completes ─────────────────────────
echo "=== T4-clean-audit-passes ==="
P="$TOPTMP/p4"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

**Feature:** Comment Widget
**Date:** 2026-07-18
**Auditor Persona:** Senior Security Engineer

## Manual Review Findings

| # | Category | Finding | Severity | File:Line | Resolution | Status |
|---|----------|---------|----------|-----------|------------|--------|
| 1 | Input Validation | Comment body sanitized | Medium | src/widget.ts:10 | DOMPurify on write | Fixed |

## Summary

| Status | Count |
|--------|-------|
| Fixed | 1 |
| Accepted (with rationale) | 0 |
| Open | 0 |

**All findings resolved:** Yes
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -eq 0 ] && step_recorded "$P"; then
  pass "T4-clean-audit-passes"
else
  fail_ "T4-clean-audit-passes" "rc=$rc — a template-conformant clean audit was refused (false positive): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T5: the pristine unfilled placeholder 'Yes / No' → BLOCK ─────────────────
echo "=== T5-placeholder-blocks ==="
P="$TOPTMP/p5"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

**Date:** YYYY-MM-DD

## Summary

| Status | Count |
|--------|-------|
| Fixed | N |
| Open | N |

**All findings resolved:** Yes / No
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T5-placeholder-blocks (an unfilled template is not a verdict)"
else
  fail_ "T5-placeholder-blocks" "rc=$rc — the template's own 'Yes / No' placeholder passed as an affirmative verdict"
fi

# ── T6: multi-round audits — the NEWEST file's verdict governs ───────────────
# Distinct touch -t minutes; never same-second mtime ordering (BL-140 D-extra).
echo "=== T6-newest-file-governs ==="
P="$TOPTMP/p6"; mk_loop "$P"
cat > "$P/docs/security-audits/comment-widget-round1.md" <<'EOF'
## Summary
| Status | Count |
|--------|-------|
| Open | 2 |
**All findings resolved:** No
EOF
cat > "$P/docs/security-audits/comment-widget-round2.md" <<'EOF'
## Summary
| Status | Count |
|--------|-------|
| Open | 0 |
**All findings resolved:** Yes
EOF
touch -t 202607170101 "$P/docs/security-audits/comment-widget-round1.md"
touch -t 202607180202 "$P/docs/security-audits/comment-widget-round2.md"
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -eq 0 ] && step_recorded "$P"; then
  pass "T6a-newer-pass-supersedes-older-fail"
else
  fail_ "T6a-newer-pass-supersedes-older-fail" "rc=$rc — a historical failed round blocked despite a newer passing audit: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi
P="$TOPTMP/p6b"; mk_loop "$P"
cat > "$P/docs/security-audits/comment-widget-round1.md" <<'EOF'
## Summary
| Status | Count |
|--------|-------|
| Open | 0 |
**All findings resolved:** Yes
EOF
cat > "$P/docs/security-audits/comment-widget-round2.md" <<'EOF'
## Summary
| Status | Count |
|--------|-------|
| Open | 1 |
**All findings resolved:** No
EOF
touch -t 202607170101 "$P/docs/security-audits/comment-widget-round1.md"
touch -t 202607180202 "$P/docs/security-audits/comment-widget-round2.md"
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T6b-newer-fail-not-masked-by-stale-pass"
else
  fail_ "T6b-newer-fail-not-masked-by-stale-pass" "rc=$rc — a stale passing round masked the current failing audit"
fi

# ── T7: fence-excision mutant — existence-only behavior must RETURN ──────────
# Excise # BL-120-AUDIT-VERDICT-BEGIN..END from a fixture copy; T1's
# DO-NOT-SHIP file must then complete the step again (positively asserting
# the fence carries the whole check — non-vacuous because T1 blocks with the
# fence in place).
echo "=== T7-fence-excision-mutant ==="
P="$TOPTMP/p7"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit — Feature: Comment Widget

CRITICAL — VULNERABLE. DO NOT SHIP.
EOF
markers=$(grep -c 'BL-120-AUDIT-VERDICT' "$P/scripts/process-checklist.sh") || markers=0
case "$markers" in ''|*[!0-9]*) markers=0 ;; esac
sed '/# BL-120-AUDIT-VERDICT-BEGIN/,/# BL-120-AUDIT-VERDICT-END/d' \
  "$P/scripts/process-checklist.sh" > "$P/scripts/process-checklist.mut" \
  && mv "$P/scripts/process-checklist.mut" "$P/scripts/process-checklist.sh" \
  && chmod +x "$P/scripts/process-checklist.sh"
left=$(grep -c 'BL-120-AUDIT-VERDICT' "$P/scripts/process-checklist.sh") || left=0
case "$left" in ''|*[!0-9]*) left=0 ;; esac
if [ "${markers:-0}" -lt 2 ] || [ "${left:-0}" -ne 0 ]; then
  fail_ "T7-fence-excision-mutant" "excision vacuous (markers before=$markers after=$left) — fence absent or sed missed it"
else
  out=$(run_audit_step "$P"); rc=$?
  if [ "$rc" -eq 0 ] && step_recorded "$P"; then
    pass "T7-fence-excision-mutant (excision restores existence-only — the fence is load-bearing)"
  else
    fail_ "T7-fence-excision-mutant" "rc=$rc — mutant still blocked; the check does not live (only) inside the fence: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Verifier-battery cases (consolidated adversarial verification, 2026-07-18):
# the MUST-fix (Yes-ANYWHERE acceptance — A5b/A4b/A10) + the SHOULD regex,
# tie-break, and candidate-filter tightenings. Semantics under fix: the LAST
# '**All findings resolved:**' line and the LAST numeric '| Open | N |' row
# govern, AFTER stripping HTML comments and fenced code blocks; ALL files
# sharing the newest mtime must pass (fail-closed tie-break); only regular
# FILES are verdict candidates.
# ═════════════════════════════════════════════════════════════════════════════

# ── T8 (MUST A5b): single-file multi-round — a LATER No beats an earlier Yes ─
echo "=== T8-multiround-later-no-blocks ==="
P="$TOPTMP/p8"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

## Round 1 — 2026-07-15

**All findings resolved:** Yes

## Round 2 — 2026-07-18, regression: sanitizer removed

**All findings resolved:** No
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T8-multiround-later-no-blocks (the walk's own single-file rounds shape: the LATEST verdict governs)"
else
  fail_ "T8-multiround-later-no-blocks" "rc=$rc — an earlier round's Yes overrode the current round's No (verifier MUST A5b)"
fi

# ── T9 (MUST A4b): a Yes inside a fenced code block is an example, not a verdict ─
echo "=== T9-fenced-example-not-verdict ==="
P="$TOPTMP/p9"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

The completed Summary must end like this:

```
**All findings resolved:** Yes
```

## Summary

**All findings resolved:** No
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T9-fenced-example-not-verdict"
else
  fail_ "T9-fenced-example-not-verdict" "rc=$rc — a quoted example Yes satisfied the gate over the real No (verifier MUST A4b)"
fi

# ── T10 (MUST A10): an HTML-commented-out Yes is not a verdict ───────────────
echo "=== T10-commented-yes-not-verdict ==="
P="$TOPTMP/p10"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

Audit not performed yet.

<!--
When done, record:
**All findings resolved:** Yes
-->
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T10-commented-yes-not-verdict"
else
  fail_ "T10-commented-yes-not-verdict" "rc=$rc — a commented-out Yes satisfied the gate on an unperformed audit (verifier MUST A10)"
fi

# ── T11: honest single-file progression — later clean round PASSES ───────────
# The mirror of T8, and the false-positive guard on last-occurrence semantics:
# round 1's historical | Open | 2 | must not block once round 2 records 0/Yes.
echo "=== T11-multiround-honest-progress-passes ==="
P="$TOPTMP/p11"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

## Round 1 — 2026-07-15

| Status | Count |
|--------|-------|
| Open | 2 |

**All findings resolved:** No

## Round 2 — 2026-07-18, both findings fixed

| Status | Count |
|--------|-------|
| Fixed | 2 |
| Open | 0 |

**All findings resolved:** Yes
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -eq 0 ] && step_recorded "$P"; then
  pass "T11-multiround-honest-progress-passes (historical rounds do not brick an honestly-finished audit)"
else
  fail_ "T11-multiround-honest-progress-passes" "rc=$rc — round 1's history blocked a currently-clean audit (false positive): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T12 (SHOULD C6): equal-mtime tie must fail CLOSED ────────────────────────
# Same touch -t on both files (ties are real: zip extraction, cp -R, coarse
# filesystems); ls -t breaks ties name-ascending, which silently preferred the
# stale clean round. Under the fix, EVERY newest-tie must pass.
echo "=== T12-equal-mtime-tie-fails-closed ==="
P="$TOPTMP/p12"; mk_loop "$P"
cat > "$P/docs/security-audits/comment-widget-round1.md" <<'EOF'
## Summary
| Status | Count |
|--------|-------|
| Open | 0 |
**All findings resolved:** Yes
EOF
cat > "$P/docs/security-audits/comment-widget-round2.md" <<'EOF'
## Summary
| Status | Count |
|--------|-------|
| Open | 2 |
**All findings resolved:** No
EOF
touch -t 202607180303 "$P/docs/security-audits/comment-widget-round1.md"
touch -t 202607180303 "$P/docs/security-audits/comment-widget-round2.md"
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T12-equal-mtime-tie-fails-closed (a same-mtime stale pass cannot mask the failing round — the BL-140 D-extra class)"
else
  fail_ "T12-equal-mtime-tie-fails-closed" "rc=$rc — the alphabetically-first clean round won the mtime tie over the failing one (verifier C6)"
fi

# ── T13 (SHOULD A1/A2/A3): markdown-equivalent Open rows still block ─────────
echo "=== T13-loose-open-row-blocks ==="
P="$TOPTMP/p13"; mk_loop "$P"
printf '# Security Audit Findings — Feature: Comment Widget\n\n## Summary\n\n  | open | 3\n\n**All findings resolved:** Yes\n' > "$P/$AUDIT"
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T13-loose-open-row-blocks (indented/lowercase/lazy-pipe row is the same row — GFM-equivalent serialization cannot evade)"
else
  fail_ "T13-loose-open-row-blocks" "rc=$rc — '  | open | 3' (renders identically to '| Open | 3 |') evaded the block (verifier A1/A2/A3)"
fi

# ── T14 (SHOULD B3): colon-outside-bold Yes is the same verdict ──────────────
echo "=== T14-colon-outside-bold-passes ==="
P="$TOPTMP/p14"; mk_loop "$P"
cat > "$P/$AUDIT" <<'EOF'
# Security Audit Findings — Feature: Comment Widget

## Summary

| Status | Count |
|--------|-------|
| Open | 0 |

**All findings resolved**: Yes
EOF
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -eq 0 ] && step_recorded "$P"; then
  pass "T14-colon-outside-bold-passes (the common hand-written colon placement is not a false positive)"
else
  fail_ "T14-colon-outside-bold-passes" "rc=$rc — '**All findings resolved**: Yes' was refused (verifier B3): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T15 (SHOULD C2): a slug-named DIRECTORY is not a verdict candidate ───────
echo "=== T15-directory-not-candidate ==="
P="$TOPTMP/p15"; mk_loop "$P"
mkdir -p "$P/docs/security-audits/comment-widget-rounds"
cat > "$P/$AUDIT" <<'EOF'
## Summary
| Status | Count |
|--------|-------|
| Open | 0 |
**All findings resolved:** Yes
EOF
touch -t 202607190101 "$P/docs/security-audits/comment-widget-rounds"
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -eq 0 ] && step_recorded "$P"; then
  pass "T15a-directory-not-candidate (a newer slug-named directory cannot hijack the verdict read)"
else
  fail_ "T15a-directory-not-candidate" "rc=$rc — a directory became the verdict source over the real passing audit (verifier C2): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi
P="$TOPTMP/p15b"; mk_loop "$P"
mkdir -p "$P/docs/security-audits/comment-widget-rounds"
out=$(run_audit_step "$P"); rc=$?
if [ "$rc" -ne 0 ] && ! step_recorded "$P"; then
  pass "T15b-directory-only-still-blocks (existence via a directory with NO audit file stays fail-closed)"
else
  fail_ "T15b-directory-only-still-blocks" "rc=$rc — a bare directory satisfied the step with zero audit files (fail-open regression)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

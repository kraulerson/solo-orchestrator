#!/usr/bin/env bash
# tests/test-bl106-golive-checklist.sh — BL-106: the platform go-live
# checklist is MANDATORY *and machine-checked* (Karl's 2026-07-18 decision).
#
# WHY THIS EXISTS
#   docs/builders-guide.md Step 4.2 marks the platform-module go-live
#   checklist "PLATFORM MODULE — MANDATORY", the four modules carry real
#   checklists — and NOTHING parsed them (the documented-but-unenforced
#   BL-070..073 rot species, at the framework's highest-stakes step).
#
# THE CONTRACT (single source: the shipped module file)
#   grammar   an H3 header matching /Go-Live/ (covers "Go-Live Checklist
#             (Web|Mobile|MCP-Specific)" AND desktop's "Go-Live Verification
#             (Append to Core Checklist)"); items = top-level `- [ ]` lines
#             until the next header. All four modules parse under it.
#   evidence  docs/test-results/*go-live-checklist* — every module item must
#             appear TICKED (`- [x]`, text-matched), zero unticked boxes may
#             remain, and the artifact carries a real date.
#   exempt    a project whose shipped modules carry NO go-live checklist
#             (standalone platforms — init's own "works standalone" branch)
#             completes with a loud note, not a block.
#
# WHAT THIS PROVES
#   T1 all-ticked+dated passes · T2 one unticked blocks NAMING the item ·
#   T3 artifact missing blocks with guidance · T4 a module item ABSENT from
#   the artifact blocks naming it (ticking what you copied is not enough —
#   the MODULE is the source) · T5 desktop's header shape enforced ·
#   T6 standalone platform exempt (loud note, rc=0) · T7 placeholder date
#   blocks · T8 fence-excision mutant resurrects the hollow gate (positively
#   asserted on a lib-complete copy — the bl104 vacuous-mutant trap).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. Hermetic.
# bash-3.2 safe. (The init-side generator has its own real-init case in
# tests/test-scaffold-tdd-block-real.sh: T-scaffold-golive-template.)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (process-state fixtures)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_p4 <dir> — phase-4 project ready for go_live_verified EXCEPT the
# BL-106 surface (each case adds its own module/artifact variant).
mk_p4() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/docs/test-results" "$d/docs/platform-modules"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  printf '{"host":"github","mode":"personal"}\n' > "$d/.claude/manifest.json"
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":4,"track":"standard","deployment":"personal","poc_mode":null,"gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-03-01","phase_2_to_3":"2026-04-01","phase_3_to_4":"2026-05-01"}}
JSON
  jq -n '{phase1_artifacts:{data_classification:"public"},phase2_init:{steps_completed:["remote_repo_created","pushed_initial"],attestations:{branch_protection:{reason:"github_free_tier"}}},phase4_release:{steps_completed:["production_build","rollback_tested","monitoring_configured"],started_at:"2026-07-18T00:00:00Z"},uat_session:{},phase3_validation:{steps_completed:[]}}' > "$d/.claude/process-state.json"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh"
  # Satisfy the BL-105 half of go_live_verified (substantive release notes).
  printf '# Release Notes\n\nv1.0.0 released 2026-07-18. Production smoke verified.\n' > "$d/RELEASE_NOTES.md"
}

# mk_module <dir> [header] — a platform module with three go-live items.
mk_module() {
  local d="$1" hdr="${2:-### 5.2 Go-Live Checklist (Web-Specific)}"
  cat > "$d/docs/platform-modules/web.md" <<EOF
# Web Platform Module

## 5. Release

$hdr

In addition to the Builder's Guide Phase 4.2:

- [ ] SSL certificate valid
- [ ] Security headers set on production responses
- [ ] Rate limiting on auth endpoints

### 5.3 Monitoring Setup

Prose that must never be parsed as items.
EOF
}

# mk_artifact <dir> <date> <items...> — a go-live artifact with the given
# TICKED items and the given Date value.
mk_artifact() {
  local d="$1" date="$2"; shift 2
  {
    printf '# Go-Live Checklist — fixture (web)\n\n'
    printf '| Field | Value |\n|---|---|\n'
    printf '| **Date** | %s |\n| **Verified by** | Tess Operator |\n\n' "$date"
    local it
    for it in "$@"; do printf -- '- [x] %s\n' "$it"; done
  } > "$d/docs/test-results/go-live-checklist.md"
}

run_golive() {
  ( cd "$1" && bash scripts/process-checklist.sh --complete-step phase4_release:go_live_verified 2>&1 )
}

# ── T1: all module items ticked + dated → completes ──────────────────────────
echo "=== T1-all-ticked-passes ==="
P="$TOPTMP/p1"; mk_p4 "$P"; mk_module "$P"
mk_artifact "$P" "2026-07-18" "SSL certificate valid" "Security headers set on production responses" "Rate limiting on auth endpoints"
out=$(run_golive "$P"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T1-all-ticked-passes"
else
  fail_ "T1-all-ticked-passes" "a fully ticked, dated checklist was rejected (rc=$rc): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T2: one unticked box in the artifact → blocks naming it ──────────────────
echo "=== T2-unticked-blocks ==="
P="$TOPTMP/p2"; mk_p4 "$P"; mk_module "$P"
mk_artifact "$P" "2026-07-18" "SSL certificate valid" "Security headers set on production responses"
printf -- '- [ ] Rate limiting on auth endpoints\n' >> "$P/docs/test-results/go-live-checklist.md"
out=$(run_golive "$P"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "Rate limiting"; then
  pass "T2-unticked-blocks"
else
  fail_ "T2-unticked-blocks" "rc=$rc — an UNTICKED mandatory item completed go_live_verified (BL-106: the checklist is prose theatre again): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T3: module present, artifact missing → blocks with guidance ──────────────
echo "=== T3-artifact-missing-blocks ==="
P="$TOPTMP/p3"; mk_p4 "$P"; mk_module "$P"
out=$(run_golive "$P"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "go-live-checklist"; then
  pass "T3-artifact-missing-blocks"
else
  fail_ "T3-artifact-missing-blocks" "rc=$rc — MANDATORY platform checklist with no recorded artifact completed anyway: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T4: artifact self-consistent but MISSING a module item → blocks ──────────
echo "=== T4-missing-item-blocks ==="
P="$TOPTMP/p4"; mk_p4 "$P"; mk_module "$P"
mk_artifact "$P" "2026-07-18" "SSL certificate valid" "Security headers set on production responses"
out=$(run_golive "$P"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "Rate limiting"; then
  pass "T4-missing-item-blocks"
else
  fail_ "T4-missing-item-blocks" "rc=$rc — an artifact that simply OMITS a module item passed (the MODULE is the source, not the copy): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T5: desktop's header shape is enforced too ───────────────────────────────
echo "=== T5-desktop-header-grammar ==="
P="$TOPTMP/p5"; mk_p4 "$P"
mk_module "$P" "### Phase 3 — Go-Live Verification (Append to Core Checklist)"
out=$(run_golive "$P"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "go-live-checklist"; then
  pass "T5-desktop-header-grammar"
else
  fail_ "T5-desktop-header-grammar" "rc=$rc — desktop's 'Go-Live Verification' header escaped the grammar; its 7 MANDATORY items would be unenforced: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T6: standalone platform (no module checklist) → exempt with a note ───────
echo "=== T6-standalone-exempt ==="
P="$TOPTMP/p6"; mk_p4 "$P"
out=$(run_golive "$P"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi "standalone\|no platform module"; then
  pass "T6-standalone-exempt"
else
  fail_ "T6-standalone-exempt" "rc=$rc — a standalone platform (no module go-live checklist shipped) must complete with a loud note, not block or stay silent: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T7: placeholder date → blocks ────────────────────────────────────────────
echo "=== T7-placeholder-date-blocks ==="
P="$TOPTMP/p7"; mk_p4 "$P"; mk_module "$P"
mk_artifact "$P" "[YYYY-MM-DD]" "SSL certificate valid" "Security headers set on production responses" "Rate limiting on auth endpoints"
out=$(run_golive "$P"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE "date"; then
  pass "T7-placeholder-date-blocks"
else
  fail_ "T7-placeholder-date-blocks" "rc=$rc — an UNDATED (placeholder) checklist verified go-live: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T8: fence-excision mutant resurrects the hollow gate ─────────────────────
echo "=== T8-fence-excision-mutant ==="
P="$TOPTMP/p8"; mk_p4 "$P"; mk_module "$P"
mk_artifact "$P" "2026-07-18" "SSL certificate valid" "Security headers set on production responses"
printf -- '- [ ] Rate limiting on auth endpoints\n' >> "$P/docs/test-results/go-live-checklist.md"
sed '/# BL-106-GOLIVE-CHECKLIST-BEGIN/,/# BL-106-GOLIVE-CHECKLIST-END/d' \
  "$REPO_ROOT/scripts/process-checklist.sh" > "$P/scripts/process-checklist.sh"
chmod +x "$P/scripts/process-checklist.sh"
if grep -q "BL-106-GOLIVE-CHECKLIST" "$P/scripts/process-checklist.sh"; then
  fail_ "T8-fence-excision-mutant" "fence excision left BL-106 marker text behind — BEGIN/END malformed"
else
  out=$(run_golive "$P"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "T8-fence-excision-mutant (the guardless mutant passes the unticked checklist — the fence is what blocks)"
  else
    fail_ "T8-fence-excision-mutant" "rc=$rc — the excised mutant did NOT reproduce the hollow gate; either the mutant crashed (vacuous) or the block lives outside the fence: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

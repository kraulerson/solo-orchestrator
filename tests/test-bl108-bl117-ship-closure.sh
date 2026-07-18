#!/usr/bin/env bash
# tests/test-bl108-bl117-ship-closure.sh — BL-108/BL-117: a shipped instruction
# must never point at an unshipped dependency.
#
# WHY THIS EXISTS (the BL-088 class, artifact form — 6 recurrences in one walk)
#   process-checklist.sh's own error text tells the operator to "Create a
#   findings file using templates/generated/security-audit-findings.tmpl" —
#   and init.sh never shipped it. 8 of 25 templates were never shipped, 5 of
#   them demanded by a gate (security-audit-findings, security,
#   threat-model-validation, rollback-test, handoff-test-results).
#   scripts/check-maintenance.sh is named by builders-guide Step 4.4 and
#   shipped 0 times (F20). And phase4_release:production_build had NO
#   evidence arm at all — the walk's release did not boot (F19).
#
#   The DURABLE fix is mechanical closure (BL-088's doctrine): the shipped-
#   template set and the referenced-template set are both DERIVED here — from
#   init.sh's cp lines and from the shipped scripts'/guide's own text — so
#   the check cannot drift as templates and messages evolve.
#
# REGISTRATION: no init.sh run (text-derived), not an aggregator → BOTH lists.
# Hermetic. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── Mechanical sets ──────────────────────────────────────────────────────────
# Shipped templates: destinations of init.sh cp lines into templates/generated.
shipped_templates() {
  grep -E '^[[:space:]]*cp .*templates/generated/[A-Za-z0-9._-]+\.tmpl' "$REPO_ROOT/init.sh" \
    | grep -oE 'templates/generated/[A-Za-z0-9._-]+\.tmpl' \
    | sed 's|.*/||' | sort -u
}
# Templates REFERENCED by shipped scripts (gate messages included) + the guide.
referenced_templates() {
  # Comment-only mentions are not operator-facing promises — skip lines whose
  # first non-space char is '#' in the scripts (the guide is all prose).
  { grep -hE 'templates/generated/[A-Za-z0-9._-]+\.tmpl' \
      "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/scripts/lib/*.sh 2>/dev/null \
      | grep -vE '^[[:space:]]*#'
    grep -hE 'templates/generated/[A-Za-z0-9._-]+\.tmpl' \
      "$REPO_ROOT/docs/builders-guide.md" 2>/dev/null
  } | grep -ohE 'templates/generated/[A-Za-z0-9._-]+\.tmpl' \
    | sed 's|.*/||' | sort -u
}
# Tools the guide names as scripts/<name>.sh (in-project paths).
guide_named_tools() {
  grep -ohE 'scripts/[a-z][a-z0-9-]*\.sh' "$REPO_ROOT/docs/builders-guide.md" 2>/dev/null \
    | sed 's|scripts/||' | sort -u
}
# Scripts init.sh ships (cp lines into scripts/).
shipped_scripts() {
  grep -E '^[[:space:]]*cp .*"?\$SCRIPT_DIR"?/scripts/[a-z][a-z0-9-]*\.sh' "$REPO_ROOT/init.sh" \
    | grep -oE 'scripts/[a-z][a-z0-9-]*\.sh' \
    | sed 's|scripts/||' | sort -u
}

# ── T-template-closure ───────────────────────────────────────────────────────
echo "=== T-template-closure ==="
missing=""
for t in $(referenced_templates); do
  if ! shipped_templates | grep -qx "$t"; then
    missing="$missing $t"
  fi
done
if [ -z "$missing" ]; then
  pass "T-template-closure ($(referenced_templates | grep -c .) referenced templates all shipped)"
else
  fail_ "T-template-closure" "shipped scripts/guide name templates init.sh never ships:$missing (BL-108 — the operator is told to use files that do not exist in their project)"
fi

# ── T-closure-extractor-bites ────────────────────────────────────────────────
# Self-test: the extractor must actually SEE a reference — prove it on a
# fixture line shaped like the real gate message.
echo "=== T-closure-extractor-bites ==="
probe=$(printf 'echo "Create it from templates/generated/zz-bogus-probe.tmpl"\n' \
  | grep -ohE 'templates/generated/[A-Za-z0-9._-]+\.tmpl' | sed 's|.*/||')
if [ "$probe" = "zz-bogus-probe.tmpl" ]; then
  pass "T-closure-extractor-bites"
else
  fail_ "T-closure-extractor-bites" "the reference extractor failed to see a gate-message-shaped template path (got '$probe') — the closure would pass vacuously"
fi

# ── T-guide-tools-shipped ────────────────────────────────────────────────────
echo "=== T-guide-tools-shipped ==="
tool_missing=""
for s in $(guide_named_tools); do
  if ! shipped_scripts | grep -qx "$s"; then
    tool_missing="$tool_missing $s"
  fi
done
if [ -z "$tool_missing" ]; then
  pass "T-guide-tools-shipped ($(guide_named_tools | grep -c .) guide-named tools all shipped)"
else
  fail_ "T-guide-tools-shipped" "builders-guide names in-project tools init.sh never ships:$tool_missing (BL-117 F20 — 'No such file' for a guide-following operator)"
fi

# ── T-build-smoke-evidence (BL-117 F19) ──────────────────────────────────────
echo "=== T-build-smoke-evidence ==="
mk_p4() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/docs/test-results"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  printf '{"host":"github","mode":"personal"}\n' > "$d/.claude/manifest.json"
  printf '{"current_phase":4,"track":"full","deployment":"personal","poc_mode":null,"gates":{}}\n' > "$d/.claude/phase-state.json"
  jq -n '{phase1_artifacts:{data_classification:"public"},phase2_init:{steps_completed:["remote_repo_created","pushed_initial"]},phase4_release:{steps_completed:[],started_at:"2026-07-17T00:00:00Z"}}' > "$d/.claude/process-state.json"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/process-checklist.sh"
}
P="$TOPTMP/p-smoke"
mk_p4 "$P"
out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase4_release:production_build 2>&1 ); rc=$?
P2="$TOPTMP/p-smoke2"
mk_p4 "$P2"
cat > "$P2/docs/test-results/2026-07-17_build-smoke.md" <<'MD'
# Production build smoke — 2026-07-17
Built dist/, started the artifact with the documented command, served / — verified.
MD
out2=$( cd "$P2" && bash scripts/process-checklist.sh --complete-step phase4_release:production_build 2>&1 ); rc2=$?
if [ "$rc" -ne 0 ] && [ "$rc2" -eq 0 ]; then
  pass "T-build-smoke-evidence"
else
  fail_ "T-build-smoke-evidence" "no-evidence rc=$rc (want !=0); with a dated smoke record rc=$rc2 (want 0) — the walk's release was marked built and did not boot (F19)"
fi

# ── T-mutation-bl117-smoke ───────────────────────────────────────────────────
echo "=== T-mutation-bl117-smoke ==="
if ! grep -q "BL-117-BUILD-SMOKE-BEGIN" "$REPO_ROOT/scripts/process-checklist.sh"; then
  fail_ "T-mutation-bl117-smoke" "no BL-117-BUILD-SMOKE fence — fix not in place"
else
  MUT="$TOPTMP/mutpc"
  mkdir -p "$MUT"
  sed '/# BL-117-BUILD-SMOKE-BEGIN/,/# BL-117-BUILD-SMOKE-END/d' "$REPO_ROOT/scripts/process-checklist.sh" > "$MUT/process-checklist.sh"
  chmod +x "$MUT/process-checklist.sh"
  if ! bash -n "$MUT/process-checklist.sh" 2>/dev/null; then
    fail_ "T-mutation-bl117-smoke" "excised mutant is syntactically broken"
  else
    P="$TOPTMP/p-smokemut"
    mk_p4 "$P"
    cp "$MUT/process-checklist.sh" "$P/scripts/process-checklist.sh"
    out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase4_release:production_build 2>&1 ); rc=$?
    if [ "$rc" -eq 0 ]; then
      pass "T-mutation-bl117-smoke (arm excised → evidence-less build passes again: the fence is load-bearing)"
    else
      fail_ "T-mutation-bl117-smoke" "mutant still blocks (rc=$rc) — the fence does not contain the arm"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

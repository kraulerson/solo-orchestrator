#!/usr/bin/env bash
# tests/test-bl116-push-gate-scope.sh — BL-116: the MANDATORY push gate must
# key on recorded facts, not host brand.
#
# WHY THIS EXISTS (E2E walk F7 / BL-116, Medium)
#   The BL-084 push-verification gate — documented MANDATORY and
#   non-bypassable — was implemented only for `host == "other"`. Its scope
#   comment's premise ("first-class hosts are provably pushed at init") is
#   FALSE for `--no-remote-creation`: a github/gitlab project scaffolded
#   hermetically never received the gate at all. The fix
#   (# BL-116-PUSH-GATE-SCOPE in check-phase-gate.sh) makes the first-class
#   exemption CONDITIONAL on the recorded facts — the gate is skipped only
#   when phase2_init.steps_completed carries BOTH remote_repo_created and
#   pushed_initial (what "provably pushed at init" actually means on disk);
#   host=other keeps its unconditional gating.
#
# CASES
#   T-github-noremote-gated   github host, org tier, NO init-push records, no
#                             remote branch → the push-gate FAIL fires.
#   T-github-initpushed-exempt github host WITH both records → no push-gate
#                             FAIL (the premise holds, exemption earned).
#   T-other-still-gated       host=other unchanged (regression pin).
#   T-mutation-bl116          excise the fence from a COPY → the github
#                             no-remote case regresses to silence.
#
# REGISTRATION: no init.sh → BOTH lists. Fixture adapted from
# test-bl104-gate-scoring.sh. Hermetic. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# build <dir> <host> <init_pushed:yes|no>
build() {
  local d="$1" host="$2" pushed="$3"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  ( cd "$d" && git init -q \
      && git config user.email t@t.invalid && git config user.name t \
      && echo x > README.md && git add README.md && git commit -q -m "chore: init" ) || return 1
  printf '{"host":"%s","mode":"personal"}\n' "$host" > "$d/.claude/manifest.json"
  cat > "$d/.claude/phase-state.json" <<'JSON'
{
  "project": "bl116",
  "current_phase": 2,
  "track": "full",
  "deployment": "organizational",
  "poc_mode": "sponsored_poc",
  "gates": { "phase_0_to_1": "2026-02-01", "phase_1_to_2": "2026-03-01", "phase_2_to_3": null, "phase_3_to_4": null }
}
JSON
  local steps='[]'
  [ "$pushed" = "yes" ] && steps='["remote_repo_created","pushed_initial"]'
  jq -n --argjson s "$steps" '{phase1_artifacts:{data_classification:"public"},phase2_init:{steps_completed:$s,attestations:{branch_protection:{reason:"github_free_tier"}}}}' > "$d/.claude/process-state.json"
  cat > "$d/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-03-01 |
MD
  { local n; for n in 1 2 3 4 5 6 7 8; do echo "## ${n}. S${n}"; echo "Content."; echo ""; done; } > "$d/PRODUCT_MANIFESTO.md"
  { echo "# Project Bible"; local b; for b in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do echo "## ${b}. S${b}"; echo "C."; echo ""; done; } > "$d/PROJECT_BIBLE.md"
}

run_gate() { ( cd "$1" && bash "${2:-$SCRIPT}" --gate phase_1_to_2 2>&1 ); }

# ── T-github-noremote-gated ──────────────────────────────────────────────────
echo "=== T-github-noremote-gated ==="
P="$TOPTMP/gh-norem"
build "$P" github no
out=$(run_gate "$P")
if printf '%s' "$out" | grep -q "push gate" && printf '%s' "$out" | grep -qE "\[FAIL\].*push gate"; then
  pass "T-github-noremote-gated"
else
  fail_ "T-github-noremote-gated" "a github project with NO init-push records and no remote produced no push-gate FAIL — the MANDATORY gate does not exist for first-class hosts scaffolded --no-remote-creation (BL-116): $(printf '%s' "$out" | grep -ci 'push gate') push-gate lines"
fi

# ── T-github-initpushed-exempt ───────────────────────────────────────────────
echo "=== T-github-initpushed-exempt ==="
P="$TOPTMP/gh-pushed"
build "$P" github yes
out=$(run_gate "$P")
if printf '%s' "$out" | grep -qE "\[FAIL\].*push gate"; then
  fail_ "T-github-initpushed-exempt" "a github project WITH remote_repo_created+pushed_initial recorded still drew the push-gate FAIL — the earned exemption (provably pushed at init) must hold"
else
  pass "T-github-initpushed-exempt"
fi

# ── T-other-still-gated ──────────────────────────────────────────────────────
echo "=== T-other-still-gated ==="
P="$TOPTMP/other-norem"
build "$P" other no
out=$(run_gate "$P")
if printf '%s' "$out" | grep -qE "\[FAIL\].*push gate"; then
  pass "T-other-still-gated"
else
  fail_ "T-other-still-gated" "host=other regression: the push gate no longer fires for an unpushed other-host project"
fi

# ── T-mutation-bl116 ─────────────────────────────────────────────────────────
echo "=== T-mutation-bl116 ==="
MUT="$TOPTMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
if ! grep -q "BL-116-PUSH-GATE-SCOPE-BEGIN" "$SCRIPT"; then
  fail_ "T-mutation-bl116" "no BL-116-PUSH-GATE-SCOPE fence in check-phase-gate.sh — fix not in place"
else
  sed '/# BL-116-PUSH-GATE-SCOPE-BEGIN/,/# BL-116-PUSH-GATE-SCOPE-END/d' "$SCRIPT" > "$MUT/scripts/check-phase-gate.sh"
  chmod +x "$MUT/scripts/check-phase-gate.sh"
  if ! bash -n "$MUT/scripts/check-phase-gate.sh" 2>/dev/null; then
    fail_ "T-mutation-bl116" "excised mutant is syntactically broken — keep the scope change excision-safe"
  else
    P="$TOPTMP/gh-mut"
    build "$P" github no
    out=$(run_gate "$P" "$MUT/scripts/check-phase-gate.sh")
    if printf '%s' "$out" | grep -qE "\[FAIL\].*push gate"; then
      fail_ "T-mutation-bl116" "fence excised but the github no-remote case still gates — the fence does not contain the scope change"
    else
      pass "T-mutation-bl116"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

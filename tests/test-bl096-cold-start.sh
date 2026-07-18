#!/usr/bin/env bash
# tests/test-bl096-cold-start.sh — BL-096 cold-start hardening bundle
# (ergonomics audit F6/F9/F10): the three onboarding traps CLAUDE.md documents
# must be fixed AT THE POINT OF FAILURE, not only in prose.
#
# WHAT THIS PROVES
#   F9  CDF preflight — scripts/check-cdf-preflight.sh reports an absent
#       ~/.claude-dev-framework with the EXACT clone line (rc=1) and stays
#       quiet-OK when present (rc=0); tests/full-project-test-suite.sh invokes
#       it EARLY (warn-and-continue wiring — CI runs the suite WITHOUT a CDF
#       clone and relies on init.sh's network auto-clone, so the preflight
#       must never hard-abort the suite).
#   F6  --tdd-only help truth — pre-commit-gate.sh --help exists (rc=0,
#       gates untouched) and states that --tdd-only runs BOTH message gates
#       (BL-072 TDD ordering AND BL-006 Build-Loop check; name kept for hook
#       back-compat), and documents the new --commit-msg-gates alias.
#       The alias BEHAVES like --tdd-only: a `feat(...)` message with no
#       active Build Loop is blocked with the BL-006 message (control case
#       pins --tdd-only to the same block, so the oracle is proven).
#   F10 contributor hook bootstrap — scripts/install-contributor-hooks.sh
#       installs pre-commit-gate.sh as .git/hooks/pre-commit (executable,
#       byte-identical), is idempotent, and refuses loudly outside a
#       framework checkout.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH tests/full-project-
# test-suite.sh AND the tests.yml unit list. Hermetic (mktemp HOME/fixtures,
# no network, no real remotes). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/check-cdf-preflight.sh"
INSTALLER="$REPO_ROOT/scripts/install-contributor-hooks.sh"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
CLONE_LINE="git clone https://github.com/kraulerson/claude-dev-framework.git"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (the BL-006 gate reads process state via jq)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── F9 / T1: absent CDF → rc=1 + the exact clone line ────────────────────────
echo "=== T-preflight-absent-names-clone ==="
if [ ! -f "$PREFLIGHT" ]; then
  fail_ "T-preflight-absent-names-clone" "scripts/check-cdf-preflight.sh does not exist (F9: absence must be reported at point of entry with the exact clone line)"
else
  H1="$TOPTMP/home-empty"; mkdir -p "$H1"
  out=$(HOME="$H1" bash "$PREFLIGHT" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "$CLONE_LINE" && printf '%s' "$out" | grep -q "claude-dev-framework"; then
    pass "T-preflight-absent-names-clone"
  else
    fail_ "T-preflight-absent-names-clone" "rc=$rc — an absent clone must report rc=1 with the exact clone line: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  fi
fi

# ── F9 / T2: present CDF → rc=0, no clone-line noise ─────────────────────────
echo "=== T-preflight-present-ok ==="
if [ ! -f "$PREFLIGHT" ]; then
  fail_ "T-preflight-present-ok" "scripts/check-cdf-preflight.sh does not exist"
else
  H2="$TOPTMP/home-cdf"
  mkdir -p "$H2/.claude-dev-framework/.git" "$H2/.claude-dev-framework/scripts"
  printf '#!/usr/bin/env bash\n' > "$H2/.claude-dev-framework/scripts/init.sh"
  out=$(HOME="$H2" bash "$PREFLIGHT" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF "$CLONE_LINE"; then
    pass "T-preflight-present-ok"
  else
    fail_ "T-preflight-present-ok" "rc=$rc — a present clone must be rc=0 without the clone advice: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  fi
fi

# ── F9 / T3: the full suite invokes the preflight EARLY, warn-and-continue ───
echo "=== T-preflight-wired-early ==="
wire_line=$(grep -n "check-cdf-preflight.sh" "$REPO_ROOT/tests/full-project-test-suite.sh" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$wire_line" ] && [ "$wire_line" -le 80 ]; then
  # CI runs the suite with NO clone; the wiring must tolerate rc=1.
  if sed -n "${wire_line}p" "$REPO_ROOT/tests/full-project-test-suite.sh" | grep -q "|| true"; then
    pass "T-preflight-wired-early (line $wire_line, warn-and-continue)"
  else
    fail_ "T-preflight-wired-early" "wiring at line $wire_line lacks '|| true' — under the suite's set -e an absent clone would ABORT the CI core shard (which runs CDF-less by design)"
  fi
else
  fail_ "T-preflight-wired-early" "tests/full-project-test-suite.sh does not invoke check-cdf-preflight.sh within its first 80 lines (found: '${wire_line:-none}') — the point of F9 is failing at ENTRY, not deep in the suite"
fi

# ── F6 / T4: --help exists and tells the truth about --tdd-only ──────────────
echo "=== T-gate-help-truth ==="
out=$(bash "$GATE" --help 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -q -- "--tdd-only" \
   && printf '%s' "$out" | grep -q "BL-072" \
   && printf '%s' "$out" | grep -q "BL-006" \
   && printf '%s' "$out" | grep -q -- "--commit-msg-gates"; then
  pass "T-gate-help-truth"
else
  fail_ "T-gate-help-truth" "rc=$rc — --help must exit 0 and state that --tdd-only runs BOTH message gates (BL-072 + BL-006) and document --commit-msg-gates: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
fi

# ── F6 fixture: a scratch project where BL-006 blocks a feat() message ───────
mk_gate_proj() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/scripts/lib"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl096@test.invalid" \
      && git config user.name  "BL-096 Test" \
      && echo "# scratch" > README.md \
      && git add README.md \
      && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/manifest.json" <<'EOF'
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  cat > "$d/.claude/phase-state.json" <<'EOF'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
EOF
  cat > "$d/.claude/process-state.json" <<'EOF'
{"phase2_init":{"steps_completed":["remote_repo_created"],"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
EOF
  cp "$REPO_ROOT/scripts/pre-commit-gate.sh"   "$d/scripts/"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" \
     "$REPO_ROOT/scripts/lib/tdd-classify.sh" "$d/scripts/lib/" 2>/dev/null
  printf 'feat(reader): render pane\n' > "$d/.git/COMMIT_EDITMSG"
}

# ── F6 / T5: --commit-msg-gates BLOCKS like --tdd-only ───────────────────────
echo "=== T-alias-runs-message-gates ==="
P5="$TOPTMP/p-alias"; mk_gate_proj "$P5"
out=$( cd "$P5" && bash scripts/pre-commit-gate.sh --terminal-mode --commit-msg-gates 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "no Build Loop active"; then
  pass "T-alias-runs-message-gates"
else
  fail_ "T-alias-runs-message-gates" "rc=$rc — --commit-msg-gates must run the SAME two message gates as --tdd-only (BL-006 block expected): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── F6 / T6: control — --tdd-only blocks the same fixture (oracle proof) ─────
echo "=== T-tddonly-control-blocks ==="
P6="$TOPTMP/p-control"; mk_gate_proj "$P6"
out=$( cd "$P6" && bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "no Build Loop active"; then
  pass "T-tddonly-control-blocks"
else
  fail_ "T-tddonly-control-blocks" "rc=$rc — the control fixture no longer reproduces the BL-006 block; T5's oracle is unproven: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── F10 / T7: the bootstrap installer installs the real gate, idempotently ───
echo "=== T-contributor-hook-installs ==="
if [ ! -f "$INSTALLER" ]; then
  fail_ "T-contributor-hook-installs" "scripts/install-contributor-hooks.sh does not exist (F10: CONTRIBUTING's manual cp must be a one-liner script)"
else
  C="$TOPTMP/checkout"; mkdir -p "$C/scripts"
  ( cd "$C" && git init -q && git config user.email t@t.invalid && git config user.name t ) || true
  cp "$REPO_ROOT/scripts/pre-commit-gate.sh" "$C/scripts/"
  cp "$INSTALLER" "$C/scripts/"
  out=$( cd "$C" && bash scripts/install-contributor-hooks.sh 2>&1 ); rc=$?
  if [ "$rc" -eq 0 ] && [ -x "$C/.git/hooks/pre-commit" ] && cmp -s "$C/scripts/pre-commit-gate.sh" "$C/.git/hooks/pre-commit"; then
    out2=$( cd "$C" && bash scripts/install-contributor-hooks.sh 2>&1 ); rc2=$?
    if [ "$rc2" -eq 0 ] && cmp -s "$C/scripts/pre-commit-gate.sh" "$C/.git/hooks/pre-commit"; then
      pass "T-contributor-hook-installs (idempotent)"
    else
      fail_ "T-contributor-hook-installs" "re-run rc=$rc2 — the installer must be idempotent: $(printf '%s' "$out2" | tail -1)"
    fi
  else
    fail_ "T-contributor-hook-installs" "rc=$rc hook-exec=$([ -x "$C/.git/hooks/pre-commit" ] && echo yes || echo no) — expected the REAL gate installed executable at .git/hooks/pre-commit: $(printf '%s' "$out" | tail -1)"
  fi
fi

# ── F10 / T8: refuses outside a framework checkout ───────────────────────────
echo "=== T-contributor-hook-refuses-elsewhere ==="
if [ ! -f "$INSTALLER" ]; then
  fail_ "T-contributor-hook-refuses-elsewhere" "scripts/install-contributor-hooks.sh does not exist"
else
  N="$TOPTMP/not-checkout"; mkdir -p "$N"
  ( cd "$N" && git init -q ) || true
  out=$( cd "$N" && bash "$INSTALLER" 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "framework"; then
    pass "T-contributor-hook-refuses-elsewhere"
  else
    fail_ "T-contributor-hook-refuses-elsewhere" "rc=$rc — installing into a repo with NO scripts/pre-commit-gate.sh must refuse loudly: $(printf '%s' "$out" | tail -1)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

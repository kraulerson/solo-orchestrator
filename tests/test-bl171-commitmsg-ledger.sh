#!/usr/bin/env bash
# tests/test-bl171-commitmsg-ledger.sh — BL-171 (BL-163 verifier residual):
# a commit REFUSED by a MESSAGE-scoped commit-msg gate must leave a
# terminal_commit_blocked row in .claude/bypass-audit.json, exactly as BL-163
# made the pre-commit blocking arms do.
#
# THE DEFECT (BL-163 verifier residual, same class, separate surface)
#   The emitted commit-msg hook runs the two message gates via
#   `pre-commit-gate.sh --terminal-mode --tdd-only` and refuses a commit by
#   exiting non-zero — the BL-072 tier-keyed TDD-ordering HARD BLOCK, and the
#   BL-006 Build-Loop commit-message check (BL-010). Both fire BEFORE
#   .git/hooks/framework-gate.sh runs, and framework-gate is the ONLY writer of
#   terminal_commit_blocked rows — so, exactly like the BL-163 pre-commit arms,
#   a genuine commit-msg refusal appended NOTHING to the enforcement ledger.
#
# THE FIX (# BL-171-COMMITMSG-LEDGER, emitted; # BL-171-LEDGER-EMIT fence in the
# template): the gate gains an opt-in --emit-blocked-gate that exits 3 on a
# BL-072 block and 4 on a BL-006 block; the emitted commit-msg hook maps those
# to a terminal_commit_blocked row (details.gate = commitmsg_tdd /
# commitmsg_buildloop) via the SHARED soif_ledger_blocked helper (the BL-163
# bytes, embedded once by soif_emit_ledger_helper). WARN-tier / attested /
# allowed outcomes exit 0 and write NO row. The append is best-effort and
# subshell-confined: a missing/trojan ledger lib prints a one-line [note] and can
# NEVER launder the refusal. The refusal itself (the plain non-zero -> exit 1)
# lives OUTSIDE the excisable # BL-171-COMMITMSG-LEDGER block.
#
# HERMETIC: a scaffolded project (real pre-commit-gate.sh + process-checklist.sh
# + lib/*), the commit-msg hook emitted straight from scripts/lib/hook-templates.sh
# (the single source init.sh and the sync path both consume), and REAL `git
# commit`s inside mktemp fixtures. No init.sh, not an aggregator -> registered in
# BOTH lists. bash-3.2 safe.
#
# HOOKS (ignored by a bare run):
#   BL171_REPO_OVERRIDE=<framework-tree>  scaffold + emit from another tree's
#                                         scripts (used to watch RED on pre-fix).
#   BL171_ONLY="T1 T5"                    run only the named cases.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMEWORK="${BL171_REPO_OVERRIDE:-$REPO_ROOT}"
HOOKLIB="$FRAMEWORK/scripts/lib/hook-templates.sh"
ONLY="${BL171_ONLY:-}"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

want() {
  [ -z "$ONLY" ] && return 0
  case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_proj <dir> <deployment> <poc_mode|null> <buildloop:none|complete> \
#         [hooklib] [with_auditlib=1]
#   A scaffolded project: real gate + checklist + libs, .claude state, and the
#   commit-msg hook emitted from <hooklib>. deployment/poc set the BL-072 tier;
#   buildloop=complete fills the five commit-required Build-Loop steps so BL-006
#   passes. with_auditlib=0 removes the append library (non-fatal case).
mk_proj() {
  local d="$1" dep="$2" poc="$3" loop="$4" lib="${5:-$HOOKLIB}" with_lib="${6:-1}"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/src" "$d/tests"
  cp "$FRAMEWORK/scripts/pre-commit-gate.sh"   "$d/scripts/"
  cp "$FRAMEWORK/scripts/process-checklist.sh" "$d/scripts/"
  cp "$FRAMEWORK"/scripts/lib/*.sh "$d/scripts/lib/" 2>/dev/null
  chmod +x "$d/scripts/pre-commit-gate.sh" "$d/scripts/process-checklist.sh"
  [ "$with_lib" = "1" ] || rm -f "$d/scripts/lib/bypass-audit.sh"

  printf '{"frameworkVersion":"test","enforcement_level":"strict"}\n' > "$d/.claude/manifest.json"
  local poc_json='null'; [ "$poc" != "null" ] && poc_json="\"$poc\""
  cat > "$d/.claude/phase-state.json" <<EOF
{"current_phase":2,"deployment":"$dep","poc_mode":$poc_json,"track":"standard"}
EOF
  local steps='[]' feat_json='null'
  if [ "$loop" = "complete" ]; then
    feat_json='"add-foo"'
    steps='["tests_written","tests_verified_failing","implemented","security_audit","documentation_updated"]'
  fi
  cat > "$d/.claude/process-state.json" <<EOF
{"build_loop":{"feature":$feat_json,"step":0,"steps_completed":$steps,"started_at":null},"uat_session":{},"phase1_architecture":{},"phase3_validation":{},"phase4_release":{},"phase2_init":{"steps_completed":["remote_repo_created"],"verified":true}}
EOF

  ( cd "$d" && unset GITHUB_BASE_REF; git init -q -b main \
      && git config user.email t@t.invalid && git config user.name t \
      && git remote add origin https://example.invalid/x.git \
      && echo seed > README.md && git add README.md && git commit -q -m "chore: seed" ) || return 1
  mkdir -p "$d/.git/hooks"
  { printf '%s\n' '#!/usr/bin/env bash'; ( . "$lib" && soif_emit_tdd_commitmsg_block ); } > "$d/.git/hooks/commit-msg"
  chmod +x "$d/.git/hooks/commit-msg"
}

head_of() { ( cd "$1" && git rev-parse HEAD 2>/dev/null ); }

# stage_impl <proj>            — a feat impl file, NO accompanying test (TDD bait)
stage_impl() { ( cd "$1" && printf 'def foo():\n    return 1\n' > src/foo.py && git add src/foo.py ); }
# stage_impl_and_test <proj>   — impl WITH a test riding along (TDD stays silent)
stage_impl_and_test() {
  ( cd "$1" && printf 'def foo():\n    return 1\n' > src/foo.py \
      && printf 'def test_foo():\n    assert foo() == 1\n' > tests/test_foo.py \
      && git add src/foo.py tests/test_foo.py )
}

# try_commit <proj> <subject> <log> → echoes LANDED | REFUSED
try_commit() {
  local proj="$1" subj="$2" log="$3"
  if ( cd "$proj" && unset GITHUB_BASE_REF; git commit -m "$subj" </dev/null ) >"$log" 2>&1; then
    echo "LANDED"
  else
    echo "REFUSED"
  fi
}

blocked_rows() { # <proj>
  local f="$1/.claude/bypass-audit.json"
  [ -f "$f" ] || { echo 0; return 0; }
  jq '[.[] | select(.type=="terminal_commit_blocked")] | length' "$f" 2>/dev/null || echo 0
}
# rows_for_gate <proj> <gate> — terminal_commit_blocked rows whose details.gate
# matches AND the full schema pins hold (actor, final_outcome, live enforcement).
rows_for_gate() {
  local f="$1/.claude/bypass-audit.json" g="$2"
  [ -f "$f" ] || { echo 0; return 0; }
  jq --arg g "$g" '[.[] | select(.type=="terminal_commit_blocked" and .actor=="user_terminal" and .details.gate==$g and .final_outcome=="abandoned" and .enforcement_level_at_event=="strict")] | length' "$f" 2>/dev/null || echo 0
}

# ── T1 (case a): BL-072 TDD hard block → row gate=commitmsg_tdd, REFUSED ────────
if want T1; then
echo "=== T1-tdd-block-appends-row ==="
P="$TOPTMP/p1"; mk_proj "$P" organizational sponsored_poc none
stage_impl "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "feat: ship foo without a test" "$P/commit.log")
H1=$(head_of "$P")
N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" commitmsg_tdd)
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[FAIL] BL-072 TDD ordering' "$P/commit.log" \
   && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
  pass "T1-tdd-block-appends-row (REFUSED, HEAD unmoved, 1 terminal_commit_blocked row gate=commitmsg_tdd)"
else
  fail_ "T1-tdd-block-appends-row" "verdict=$V blocked_rows=$N gate_tdd=$NG (want REFUSED/1/1) — the commit-msg TDD block is invisible to the ledger: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T2 (case a): BL-006 Build-Loop block → row gate=commitmsg_buildloop ─────────
if want T2; then
echo "=== T2-buildloop-block-appends-row ==="
P="$TOPTMP/p2"; mk_proj "$P" personal null none
stage_impl_and_test "$P"        # test rides along -> TDD silent, only BL-006 fires
H0=$(head_of "$P")
V=$(try_commit "$P" "feat: add foo without a Build Loop" "$P/commit.log")
H1=$(head_of "$P")
N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" commitmsg_buildloop)
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] \
   && { grep -qF 'no Build Loop active' "$P/commit.log" || grep -qF 'Build Loop incomplete' "$P/commit.log"; } \
   && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
  pass "T2-buildloop-block-appends-row (REFUSED, HEAD unmoved, 1 terminal_commit_blocked row gate=commitmsg_buildloop)"
else
  fail_ "T2-buildloop-block-appends-row" "verdict=$V blocked_rows=$N gate_buildloop=$NG (want REFUSED/1/1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T3 (case b): WARN-tier bypassable TDD → LANDS, NO blocked row ───────────────
# personal tier + impl-no-test triggers the TDD detector, but the tier is
# BYPASSABLE: it WARNs + logs to tdd-warn-ledger.jsonl and returns 0. A complete
# Build Loop clears BL-006. The commit LANDS and bypass-audit.json stays empty of
# blocked rows — a bypassed WARN is not a block and must not be recorded as one.
if want T3; then
echo "=== T3-warn-tier-no-row ==="
P="$TOPTMP/p3"; mk_proj "$P" personal null complete
stage_impl "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "feat: add foo (warn tier, loop complete)" "$P/commit.log")
H1=$(head_of "$P")
N=$(blocked_rows "$P")
if [ "$V" = "LANDED" ] && [ "$H0" != "$H1" ] && [ "$N" -eq 0 ]; then
  pass "T3-warn-tier-no-row (LANDED, HEAD moved, zero blocked rows — a bypassed WARN writes no ledger block)"
else
  fail_ "T3-warn-tier-no-row" "verdict=$V blocked_rows=$N (want LANDED/0) — a bypassable WARN wrote a phantom block row: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T3b (case b): fully-clean allowed commit → LANDS, NO row ────────────────────
if want T3b; then
echo "=== T3b-clean-commit-no-row ==="
P="$TOPTMP/p3b"; mk_proj "$P" personal null complete
stage_impl_and_test "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "feat: add foo (clean, loop complete)" "$P/commit.log")
H1=$(head_of "$P")
N=$(blocked_rows "$P")
if [ "$V" = "LANDED" ] && [ "$H0" != "$H1" ] && [ "$N" -eq 0 ]; then
  pass "T3b-clean-commit-no-row (LANDED, HEAD moved, zero blocked rows — no false ledger entries)"
else
  fail_ "T3b-clean-commit-no-row" "verdict=$V blocked_rows=$N (want LANDED/0): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T4 (case c): NON-FATAL — append lib gone, the refusal is UNWEAKENED ─────────
if want T4; then
echo "=== T4-nonfatal-missing-lib-still-refuses ==="
P="$TOPTMP/p4"; mk_proj "$P" organizational sponsored_poc none "$HOOKLIB" 0   # no bypass-audit.sh
stage_impl "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "feat: ship foo without a test" "$P/commit.log")
H1=$(head_of "$P")
N=$(blocked_rows "$P")
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[FAIL] BL-072 TDD ordering' "$P/commit.log" \
   && grep -qF '[note] BL-163' "$P/commit.log" && [ "$N" -eq 0 ]; then
  pass "T4-nonfatal-missing-lib-still-refuses (append lib gone -> commit STILL REFUSED, one-line [note], no row — the block is never weakened by ledger trouble)"
else
  fail_ "T4-nonfatal-missing-lib-still-refuses" "verdict=$V blocked_rows=$N note=$(grep -cF '[note] BL-163' "$P/commit.log") (want REFUSED/0/>=1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T4b: TROJAN append lib (`exit 0`) must NOT launder a refusal into a landed ──
# commit. `exit` in a SOURCED file exits the sourcing shell; the helper confines
# source+append to a subshell (the BL-163 verifier MAJOR), so the refusal holds.
if want T4b; then
echo "=== T4b-trojan-exit0-lib-still-refuses ==="
P="$TOPTMP/p4b"; mk_proj "$P" organizational sponsored_poc none
printf 'exit 0\n' > "$P/scripts/lib/bypass-audit.sh"   # trojan: sourced exit 0
stage_impl "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "feat: ship foo without a test" "$P/commit.log")
H1=$(head_of "$P")
N=$(blocked_rows "$P")
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[FAIL] BL-072 TDD ordering' "$P/commit.log" \
   && [ "$N" -eq 0 ]; then
  pass "T4b-trojan-exit0-lib-still-refuses (sourced exit 0 confined to the subshell — commit STILL REFUSED, HEAD unmoved, no row)"
else
  fail_ "T4b-trojan-exit0-lib-still-refuses" "verdict=$V head_moved=$( [ "$H0" = "$H1" ] && echo no || echo YES) blocked_rows=$N — a trojan ledger lib must never launder a refusal: $(tail -4 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T5 (case d): fence-excision mutant -> rows STOP, refusal UNCHANGED ──────────
# Strip the emitted # BL-171-COMMITMSG-LEDGER BEGIN..END block from the template
# and emit the mutant commit-msg hook: the gate still exits non-zero on a block
# and the surviving fallback (`[ "$soif_cm_rc" -ne 0 ] -> exit 1`) still REFUSES
# the commit, but NO row is written. Proves the ledger block — and nothing else —
# is what records the commit-msg block.
if want T5; then
echo "=== T5-fence-excision-mutant ==="
REALHOOK="$TOPTMP/real-cm"
{ printf '%s\n' '#!/usr/bin/env bash'; ( . "$HOOKLIB" && soif_emit_tdd_commitmsg_block ); } > "$REALHOOK"
before=$(grep -c '# BL-171-COMMITMSG-LEDGER' "$REALHOOK" 2>/dev/null) || before=0
case "$before" in ''|*[!0-9]*) before=0 ;; esac
MUTLIB="$TOPTMP/hook-templates.mut.sh"
sed -e '/# BL-171-COMMITMSG-LEDGER-BEGIN/,/# BL-171-COMMITMSG-LEDGER-END/d' "$HOOKLIB" > "$MUTLIB"
MUTHOOK="$TOPTMP/mut-cm"
{ printf '%s\n' '#!/usr/bin/env bash'; ( . "$MUTLIB" && soif_emit_tdd_commitmsg_block ); } > "$MUTHOOK"
after=$(grep -c '# BL-171-COMMITMSG-LEDGER' "$MUTHOOK" 2>/dev/null) || after=0
case "$after" in ''|*[!0-9]*) after=0 ;; esac
still_calls=$(grep -c 'BL-171-COMMITMSG-LEDGER$' "$MUTHOOK" 2>/dev/null) || still_calls=0
case "$still_calls" in ''|*[!0-9]*) still_calls=0 ;; esac
if [ "$before" -lt 3 ] || [ "$after" -ne 0 ] || [ "$still_calls" -ne 0 ] || ! bash -n "$MUTHOOK" 2>/dev/null; then
  fail_ "T5-fence-excision-mutant" "excision vacuous or broke the hook (markers before=$before after=$after residual_calls=$still_calls) — fence absent, sed missed it, or the mutant is not valid bash"
else
  P="$TOPTMP/p5"; mk_proj "$P" organizational sponsored_poc none "$MUTLIB"
  stage_impl "$P"
  H0=$(head_of "$P")
  V=$(try_commit "$P" "feat: ship foo without a test" "$P/commit.log")
  H1=$(head_of "$P")
  N=$(blocked_rows "$P")
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[FAIL] BL-072 TDD ordering' "$P/commit.log" && [ "$N" -eq 0 ]; then
    pass "T5-fence-excision-mutant (excised ledger -> the gate still REFUSES the commit but writes 0 rows — the # BL-171-COMMITMSG-LEDGER block is load-bearing for the ledger, not the block)"
  else
    fail_ "T5-fence-excision-mutant" "verdict=$V blocked_rows=$N (want REFUSED/0) — the mutant either stopped blocking or still logged: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
  fi
fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$SKIPPED" -gt 0 ] && echo "($SKIPPED skipped — see [SKIP] lines)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

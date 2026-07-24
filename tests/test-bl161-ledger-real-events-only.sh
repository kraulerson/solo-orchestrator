#!/usr/bin/env bash
# tests/test-bl161-ledger-real-events-only.sh — BL-161 (Dogfood-4 F-DF4-007):
# the tracked bypass-audit ledger (.claude/bypass-audit.json) must record ONLY
# REAL events. A CLEAN terminal commit must NOT append a routine
# terminal_commit_passed receipt — that row left the working tree perpetually one
# row dirty (both Dogfood-4 walkers hit it and left the file uncommitted).
#
# THE CONTRACT (Karl-approved design fork, 2026-07-23/24: option (b))
#   • A CLEAN strict-mode terminal commit writes NO new row to the tracked ledger
#     — the file is BYTE-IDENTICAL before/after. Proof that the gate still RAN to
#     its PASS terminal is preserved in a NON-TRACKED sidecar
#     .claude/last-gate-pass.txt (gitignored, mirroring the .claude/last-checked-commit.txt
#     precedent), so the audit trail is not weakened and the tree is not dirtied.
#   • A BLOCKED commit STILL writes its terminal_commit_blocked row — via BOTH
#     surviving write paths: framework-gate.sh's own record_audit_row (BL-030),
#     the emitted pre-commit fallback arms (BL-163), and the emitted commit-msg
#     hook (BL-171).
#   • Genuine bypass / enforcement-level / out-of-band events STILL record.
#   • The ledger stays TRACKED (audit trail) — NOT gitignored.
#
# THE FIX (# BL-161-NO-ROUTINE-PASS in scripts/install-filesystem-gates.sh): the
# framework-gate's PASS arm no longer re-invokes a tracked-ledger append; it drops
# a non-tracked .claude/last-gate-pass.txt receipt instead. record_audit_row stays
# the BLOCKED-only writer (byte-identical blocked rows). terminal_commit_passed
# remains a schema-valid LEGACY type (old ledgers keep their rows) — it is simply
# no longer EMITTED on routine clean commits.
#
# HERMETIC: local git repos only (git init inside mktemp), NEVER a live remote.
# The framework gate is installed DIRECTLY via scripts/install-filesystem-gates.sh
# (NOT init.sh); the two delegated gates (process-checklist / pre-commit-gate) are
# STUBS whose exit code stands in for the pass/block VERDICT, while the REAL
# install-filesystem-gates.sh __record_pass/__record_block is the code under test.
# The BL-163 / BL-171 / detector regressions reuse the sibling fixture patterns.
# No init.sh, not an aggregator -> registered in BOTH lists. bash-3.2 safe.
#
# HOOKS (ignored by a bare run):
#   BL161_REPO_OVERRIDE=<framework-tree>  install/emit from a MUTANT tree's scripts
#   BL161_ONLY="T1 T2"                    run only the named cases

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMEWORK="${BL161_REPO_OVERRIDE:-$REPO_ROOT}"
INSTALLER="$FRAMEWORK/scripts/install-filesystem-gates.sh"
HOOKLIB="$FRAMEWORK/scripts/lib/hook-templates.sh"
AUDITLIB="$FRAMEWORK/scripts/lib/bypass-audit.sh"
DETECTOR="$FRAMEWORK/scripts/detect-out-of-band-commits.sh"
ONLY="${BL161_ONLY:-}"

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

# ── Ledger row counters (absent file == 0) ───────────────────────────────────
passed_rows() { # <proj>
  local f="$1/.claude/bypass-audit.json"
  [ -f "$f" ] || { echo 0; return 0; }
  jq '[.[] | select(.type=="terminal_commit_passed")] | length' "$f" 2>/dev/null || echo 0
}
blocked_rows() { # <proj>
  local f="$1/.claude/bypass-audit.json"
  [ -f "$f" ] || { echo 0; return 0; }
  jq '[.[] | select(.type=="terminal_commit_blocked")] | length' "$f" 2>/dev/null || echo 0
}
# rows_for_gate <proj> <gate> — terminal_commit_blocked rows whose details.gate
# matches AND the full schema pins hold (actor / final_outcome / live level).
rows_for_gate() {
  local f="$1/.claude/bypass-audit.json" g="$2"
  [ -f "$f" ] || { echo 0; return 0; }
  jq --arg g "$g" '[.[] | select(.type=="terminal_commit_blocked" and .actor=="user_terminal" and .details.gate==$g and .final_outcome=="abandoned" and .enforcement_level_at_event=="strict")] | length' "$f" 2>/dev/null || echo 0
}
count_type() { # <proj> <type>
  local f="$1/.claude/bypass-audit.json" t="$2"
  [ -f "$f" ] || { echo 0; return 0; }
  jq --arg t "$t" '[.[] | select(.type==$t)] | length' "$f" 2>/dev/null || echo 0
}
head_of() { ( cd "$1" && git rev-parse HEAD 2>/dev/null ); }

# try_commit <proj> <subject> <log> [PATH] → echoes LANDED | REFUSED
try_commit() {
  local proj="$1" subj="$2" log="$3" p="${4:-$PATH}"
  if ( cd "$proj" && PATH="$p" git commit -m "$subj" </dev/null ) >"$log" 2>&1; then
    echo "LANDED"
  else
    echo "REFUSED"
  fi
}

# ── Fixture A: a strict project with the REAL framework gate installed ────────
# process-checklist / pre-commit-gate are STUBS (exit code = verdict); the
# framework-gate.sh and install-filesystem-gates.sh under test are the REAL files.
mk_gate_proj() { # <dir> <process-checklist-rc> <pre-commit-gate-rc>
  local d="$1" pc_rc="${2:-0}" pg_rc="${3:-0}"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts" "$d/src"
  printf '{"frameworkVersion":"test","enforcement_level":"strict"}\n' > "$d/.claude/manifest.json"
  printf '[]\n' > "$d/.claude/bypass-audit.json"
  cp "$INSTALLER" "$d/scripts/install-filesystem-gates.sh"
  chmod +x "$d/scripts/install-filesystem-gates.sh"
  printf '#!/bin/sh\nexit %s\n' "$pc_rc" > "$d/scripts/process-checklist.sh"
  printf '#!/bin/sh\nexit %s\n' "$pg_rc" > "$d/scripts/pre-commit-gate.sh"
  chmod +x "$d/scripts/process-checklist.sh" "$d/scripts/pre-commit-gate.sh"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && git add -A && git commit -q -m "chore: seed" ) >/dev/null 2>&1 || return 1
  bash "$INSTALLER" --install "$d" >/dev/null 2>&1 || return 1
}

# ── T1 (case a): CLEAN commit -> NO tracked-ledger row, byte-identical ledger, ──
# a non-tracked .claude/last-gate-pass.txt receipt proves the PASS terminal ran.
# THE DISCRIMINATOR: pre-fix the routine terminal_commit_passed row is appended,
# so the ledger DIFFERS (RED); post-fix the ledger is unchanged (GREEN).
if want T1; then
echo "=== T1-clean-commit-no-routine-pass-row ==="
if ! mk_gate_proj "$TOPTMP/t1" 0 0; then
  fail_ "T1-clean-commit-no-routine-pass-row" "fixture build failed"
else
  P="$TOPTMP/t1"
  printf 'export const x = 1;\n' > "$P/src/widget.ts"
  git -C "$P" add src/widget.ts
  cp "$P/.claude/bypass-audit.json" "$TOPTMP/t1.ledger.before"
  H0=$(head_of "$P")
  V=$(try_commit "$P" "chore: land widget" "$P/commit.log")
  H1=$(head_of "$P")
  NP=$(passed_rows "$P")
  RECEIPT="$P/.claude/last-gate-pass.txt"
  ledger_same=no; cmp -s "$TOPTMP/t1.ledger.before" "$P/.claude/bypass-audit.json" && ledger_same=yes
  receipt_ok=no; [ -s "$RECEIPT" ] && receipt_ok=yes
  if [ "$V" = "LANDED" ] && [ "$H0" != "$H1" ] && [ "$ledger_same" = "yes" ] \
     && [ "$receipt_ok" = "yes" ] && [ "$NP" -eq 0 ]; then
    pass "T1-clean-commit-no-routine-pass-row (LANDED, HEAD moved, tracked ledger BYTE-IDENTICAL, 0 pass rows, non-tracked receipt present)"
  else
    fail_ "T1-clean-commit-no-routine-pass-row" "verdict=$V head_moved=$( [ "$H0" != "$H1" ] && echo yes || echo NO) ledger_identical=$ledger_same receipt=$receipt_ok passed_rows=$NP (want LANDED/yes/yes/yes/0) — a clean commit dirtied the tracked ledger with a routine pass row: $(tail -4 "$P/commit.log" | tr '\n' ' ')"
  fi
fi
fi

# ── T2 (case b, framework-gate path): a BLOCKED commit STILL writes its ─────────
# terminal_commit_blocked row via the CHANGE-SITE writer (record_audit_row). The
# process-checklist stub blocks (exit 1); framework-gate records gate=process-checklist.
if want T2; then
echo "=== T2-framework-gate-block-still-records ==="
if ! mk_gate_proj "$TOPTMP/t2" 1 0; then
  fail_ "T2-framework-gate-block-still-records" "fixture build failed"
else
  P="$TOPTMP/t2"
  printf 'export const x = 1;\n' > "$P/src/widget.ts"
  git -C "$P" add src/widget.ts
  H0=$(head_of "$P")
  V=$(try_commit "$P" "chore: try widget" "$P/commit.log")
  H1=$(head_of "$P")
  N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" process-checklist)
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
    pass "T2-framework-gate-block-still-records (REFUSED, HEAD unmoved, 1 terminal_commit_blocked row gate=process-checklist)"
  else
    fail_ "T2-framework-gate-block-still-records" "verdict=$V blocked_rows=$N gate_pc=$NG (want REFUSED/1/1) — the BL-030 framework-gate block path stopped recording after BL-161: $(tail -4 "$P/commit.log" | tr '\n' ' ')"
  fi
fi
fi

# ── noscan PATH + fake scanners (BL-163 fixture technique) ────────────────────
NOSCAN_PATH=""
build_noscan_path() {
  [ -n "$NOSCAN_PATH" ] && return 0
  local mirrors="$TOPTMP/noscan-mirrors" n=0 d np="" entry base
  rm -rf "$mirrors"; mkdir -p "$mirrors"
  printf '%s' "$PATH" | tr ':' '\n' > "$mirrors/.pathlist"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -x "$d/semgrep" ] || [ -x "$d/gitleaks" ]; then
      n=$((n + 1))
      mkdir -p "$mirrors/$n"
      for entry in "$d"/*; do
        [ -e "$entry" ] || continue           # bash 3.2 has no nullglob
        base="${entry##*/}"
        [ "$base" = "semgrep" ] && continue
        [ "$base" = "gitleaks" ] && continue
        ln -sf "$entry" "$mirrors/$n/$base" 2>/dev/null || true
      done
      np="${np:+$np:}$mirrors/$n"
    else
      np="${np:+$np:}$d"
    fi
  done < "$mirrors/.pathlist"
  NOSCAN_PATH="$np"
}
fake_scanner() { # <name> <rc>
  local name="$1" rc="$2" dir="$TOPTMP/fake-$1-$2"
  mkdir -p "$dir"
  printf '#!/bin/sh\nexit %s\n' "$rc" > "$dir/$name"
  chmod +x "$dir/$name"
  echo "$dir"
}
mk_emit_proj() { # <dir> — emitted BL-163 fallback pre-commit hook + project auditlib
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/.claude" "$d/scripts/lib" "$d/src"
  printf '{"frameworkVersion":"test","enforcement_level":"strict"}\n' > "$d/.claude/manifest.json"
  cp "$AUDITLIB" "$d/scripts/lib/bypass-audit.sh"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) >/dev/null 2>&1 || return 1
  ( source "$HOOKLIB" && soif_write_precommit_hook "$d/.git/hooks/pre-commit" ) || return 1
  chmod +x "$d/.git/hooks/pre-commit"
}

# ── T3 (case b, BL-163 path): the emitted pre-commit fallback SAST arm still ─────
# appends a terminal_commit_blocked row (gate=semgrep) after BL-161 — a separate
# write path (soif_ledger_blocked) proven unaffected by the pass-arm change.
if want T3; then
echo "=== T3-bl163-emitted-block-still-records ==="
build_noscan_path
if PATH="$NOSCAN_PATH" command -v semgrep >/dev/null 2>&1 || PATH="$NOSCAN_PATH" command -v gitleaks >/dev/null 2>&1; then
  fail_ "T3-bl163-emitted-block-still-records" "could not shim real scanners off PATH — suite would be non-hermetic"
elif ! mk_emit_proj "$TOPTMP/t3"; then
  fail_ "T3-bl163-emitted-block-still-records" "fixture build failed"
else
  P="$TOPTMP/t3"
  FAKE=$(fake_scanner semgrep 1)
  printf 'export const x = 1;\n' > "$P/src/widget.ts"
  git -C "$P" add src/widget.ts
  H0=$(head_of "$P")
  V=$(try_commit "$P" "chore: try widget" "$P/commit.log" "$FAKE:$NOSCAN_PATH")
  H1=$(head_of "$P")
  N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" semgrep)
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] Semgrep' "$P/commit.log" \
     && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
    pass "T3-bl163-emitted-block-still-records (REFUSED, 1 terminal_commit_blocked row gate=semgrep — BL-163 path intact after BL-161)"
  else
    fail_ "T3-bl163-emitted-block-still-records" "verdict=$V blocked_rows=$N gate_semgrep=$NG (want REFUSED/1/1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
  fi
fi
fi

# ── Fixture C: a scaffolded project for the BL-171 commit-msg path ────────────
# Real pre-commit-gate.sh + process-checklist.sh + libs + phase/process state, and
# the commit-msg hook emitted from hook-templates.sh (bl171 fixture pattern).
mk_cm_proj() { # <dir> <deployment> <poc|null> <buildloop:none|complete>
  local d="$1" dep="$2" poc="$3" loop="$4"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/src" "$d/tests"
  cp "$FRAMEWORK/scripts/pre-commit-gate.sh"   "$d/scripts/"
  cp "$FRAMEWORK/scripts/process-checklist.sh" "$d/scripts/"
  cp "$FRAMEWORK"/scripts/lib/*.sh "$d/scripts/lib/" 2>/dev/null
  chmod +x "$d/scripts/pre-commit-gate.sh" "$d/scripts/process-checklist.sh"
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
      && echo seed > README.md && git add README.md && git commit -q -m "chore: seed" ) >/dev/null 2>&1 || return 1
  mkdir -p "$d/.git/hooks"
  { printf '%s\n' '#!/usr/bin/env bash'; ( . "$HOOKLIB" && soif_emit_tdd_commitmsg_block ); } > "$d/.git/hooks/commit-msg"
  chmod +x "$d/.git/hooks/commit-msg"
}

# ── T4 (case b, BL-171 path): a commit-msg TDD-ordering block still appends its ──
# terminal_commit_blocked row (gate=commitmsg_tdd) after BL-161.
if want T4; then
echo "=== T4-bl171-commitmsg-block-still-records ==="
if ! mk_cm_proj "$TOPTMP/t4" organizational sponsored_poc none; then
  fail_ "T4-bl171-commitmsg-block-still-records" "fixture build failed"
else
  P="$TOPTMP/t4"
  ( cd "$P" && printf 'def foo():\n    return 1\n' > src/foo.py && git add src/foo.py )
  H0=$(head_of "$P")
  V=$(try_commit "$P" "feat: ship foo without a test" "$P/commit.log")
  H1=$(head_of "$P")
  N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" commitmsg_tdd)
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[FAIL] BL-072 TDD ordering' "$P/commit.log" \
     && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
    pass "T4-bl171-commitmsg-block-still-records (REFUSED, 1 terminal_commit_blocked row gate=commitmsg_tdd — BL-171 path intact after BL-161)"
  else
    fail_ "T4-bl171-commitmsg-block-still-records" "verdict=$V blocked_rows=$N gate_tdd=$NG (want REFUSED/1/1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
  fi
fi
fi

# ── T5 (case c): genuine bypass + enforcement-level events STILL record via the ──
# shared writer (bypass_audit_append) — untouched by BL-161, pinned as a contract.
if want T5; then
echo "=== T5-genuine-events-still-record ==="
P="$TOPTMP/t5"; rm -rf "$P"; mkdir -p "$P/.claude"
printf '[]\n' > "$P/.claude/bypass-audit.json"
(
  . "$AUDITLIB"
  bypass_audit_append "$P" '{"timestamp":"2026-07-24T00:00:00Z","session_id":"s1","type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{"pattern":"--no-verify"},"user_response":"PENDING","final_outcome":"n/a"}'
  bypass_audit_append "$P" '{"timestamp":"2026-07-24T00:00:01Z","session_id":null,"type":"enforcement_level_set","actor":"framework","enforcement_level_at_event":"strict","details":{"level":"strict","source":"init"},"user_response":"n/a","final_outcome":"recorded_only"}'
) >"$P/append.log" 2>&1
PROP=$(count_type "$P" claude_bypass_proposal)
ELS=$(count_type "$P" enforcement_level_set)
if [ "$PROP" -eq 1 ] && [ "$ELS" -eq 1 ]; then
  pass "T5-genuine-events-still-record (claude_bypass_proposal=1, enforcement_level_set=1 — real events still land in the tracked ledger)"
else
  fail_ "T5-genuine-events-still-record" "proposal=$PROP enforcement_level_set=$ELS (want 1/1) — a genuine event stopped recording: $(tail -3 "$P/append.log" | tr '\n' ' ')"
fi
fi

# ── T6 (case d): the out-of-band detector still functions on the new baseline ────
# behaviour — it records an out_of_band_commit, exits 0, and advances the baseline.
if want T6; then
echo "=== T6-detector-still-functions ==="
P="$TOPTMP/t6"; rm -rf "$P"; mkdir -p "$P/.claude" "$P/src"
printf '{"frameworkVersion":"test","enforcement_level":"strict"}\n' > "$P/.claude/manifest.json"
printf '[]\n' > "$P/.claude/bypass-audit.json"
( cd "$P" && git init -q && git config user.email t@t.invalid && git config user.name t \
    && echo a > seed && git add seed && git commit -q -m "chore: init" ) >/dev/null 2>&1
A=$(head_of "$P")
printf '%s\n' "$A" > "$P/.claude/last-checked-commit.txt"   # baseline at A
( cd "$P" && echo b > src/x.txt && git add src/x.txt && git commit -q -m "feat: sneaky out-of-band change" ) >/dev/null 2>&1
B=$(head_of "$P")
bash "$DETECTOR" "$P" >"$P/detect.log" 2>&1
DRC=$?
OOB=$(count_type "$P" out_of_band_commit)
NEWBASE=$(cat "$P/.claude/last-checked-commit.txt" 2>/dev/null)
if [ "$DRC" -eq 0 ] && [ "$OOB" -eq 1 ] && [ "$NEWBASE" = "$B" ]; then
  pass "T6-detector-still-functions (exit 0, 1 out_of_band_commit row, baseline advanced to HEAD — case d intact)"
else
  fail_ "T6-detector-still-functions" "detector_rc=$DRC out_of_band=$OOB baseline_advanced=$( [ "$NEWBASE" = "$B" ] && echo yes || echo NO) (want 0/1/yes): $(tail -3 "$P/detect.log" | tr '\n' ' ')"
fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$SKIPPED" -gt 0 ] && echo "($SKIPPED skipped — see [SKIP] lines)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

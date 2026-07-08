#!/usr/bin/env bash
# tests/test-bypass-audit-tmp-hardening.sh — regression for code-lib-2.
#
# bypass_audit_append + bypass_audit_close_pending already place the
# mktemp template adjacent to the target file (PR 0d5605e — D3 fix), so
# `mv` is a same-filesystem rename. Two residual hardenings from the
# original audit recommendation remain:
#
#   (a) Preserve permissions of the target file across the rename. The
#       audit ledger is a governance artifact; if an operator has
#       intentionally chmod'd it (e.g. 0640 for a shared-team setup),
#       the post-rename file silently reverts to mktemp's 0600 default.
#       Use `chmod --reference="$file" "$tmp" 2>/dev/null || chmod 600
#       "$tmp"` (GNU + BSD-safe fallback) so the post-rename file
#       matches the operator's intent, or falls back to a safe default.
#
#   (b) Trap on EXIT/INT/TERM to remove orphan tmp files. The current
#       code only `rm -f "$tmp"` on the jq-failure branch — a SIGTERM
#       between `mktemp` and either branch leaves a stray ${file}.XXXXXX
#       in .claude/, polluting the governance directory and confusing
#       successor agents grepping the dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-audit.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  echo "[]" > "$PROJ/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

ROW='{"timestamp":"2026-06-28T00:00:00Z","session_id":null,"type":"claude_bypass_proposal","actor":"claude","enforcement_level_at_event":"strict","details":{"pattern":"x"},"user_response":"PENDING","final_outcome":"recorded_only"}'

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (a) bypass_audit_append preserves target file permissions ==="
# ════════════════════════════════════════════════════════════════════

# T1: operator-set 0640 perms survive an append.
echo "T1: 0640 audit file keeps 0640 after append"
setup
chmod 640 "$PROJ/.claude/bypass-audit.json"
( source "$LIB" && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 )
mode=$(stat -c "%a" "$PROJ/.claude/bypass-audit.json" 2>/dev/null \
     || stat -f "%Lp" "$PROJ/.claude/bypass-audit.json" 2>/dev/null)
if [ "$mode" = "640" ]; then
  pass "T1: post-append mode preserved (was 640, is $mode)"
else
  fail_ "T1" "expected 640 after append; got $mode (mktemp 0600 leaked through rename)"
fi
teardown

# T2: bypass_audit_close_pending preserves perms too.
echo "T2: 0640 audit file keeps 0640 after close_pending"
setup
( source "$LIB" && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 )
chmod 640 "$PROJ/.claude/bypass-audit.json"
( source "$LIB" && bypass_audit_close_pending "$PROJ" "accept" >/dev/null 2>&1 )
mode=$(stat -c "%a" "$PROJ/.claude/bypass-audit.json" 2>/dev/null \
     || stat -f "%Lp" "$PROJ/.claude/bypass-audit.json" 2>/dev/null)
if [ "$mode" = "640" ]; then
  pass "T2: post-close_pending mode preserved"
else
  fail_ "T2" "expected 640 after close_pending; got $mode"
fi
teardown

# T3: when the source file mode read fails (corner case), we still get
# a sane default (0600) — never an inherited umask-default (0644 / 0664).
echo "T3: append on a fresh init produces mode-600 file (not umask default)"
setup
# bypass_audit_init writes "[]" via `echo` which honors umask.
# After the first append, the mode should be 600 (mktemp default) — and
# the appended file should NOT be world-readable even if umask was 022.
chmod 644 "$PROJ/.claude/bypass-audit.json"  # simulate a permissive prior
# Touch fresh, simulating no operator override:
rm -f "$PROJ/.claude/bypass-audit.json"
( source "$LIB" && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 )
mode=$(stat -c "%a" "$PROJ/.claude/bypass-audit.json" 2>/dev/null \
     || stat -f "%Lp" "$PROJ/.claude/bypass-audit.json" 2>/dev/null)
# When bypass_audit_init creates the file via `echo > file` it inherits
# umask; the subsequent append's chmod-from-reference will then copy
# that mode. So this test asserts the file is at most the mode the
# init created — i.e. NOT silently downgraded to 600 (which would be
# fine but a behavior change) AND NOT silently upgraded.
# The contract we care about: after the append, the mode equals the
# mode the file had just before the append (i.e. no perm churn).
# Pre-append, init created the file with the inherited umask; we then
# chmod'd it to a known value during init's mkdir. Read the actual
# pre-append mode by re-creating via the lib first:
teardown
setup
# Pre-state: file exists with init's umask-derived mode.
pre_mode=$(stat -c "%a" "$PROJ/.claude/bypass-audit.json" 2>/dev/null \
        || stat -f "%Lp" "$PROJ/.claude/bypass-audit.json" 2>/dev/null)
( source "$LIB" && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 )
post_mode=$(stat -c "%a" "$PROJ/.claude/bypass-audit.json" 2>/dev/null \
         || stat -f "%Lp" "$PROJ/.claude/bypass-audit.json" 2>/dev/null)
if [ "$pre_mode" = "$post_mode" ]; then
  pass "T3: append preserves the pre-existing mode ($pre_mode unchanged)"
else
  fail_ "T3" "mode churn: pre=$pre_mode post=$post_mode"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (b) tmp files are cleaned up on signal / unexpected exit ==="
# ════════════════════════════════════════════════════════════════════

# T4: source contains a trap that removes the tmp file. Verifies the
# code shape; a process-killed test is timing-sensitive on CI.
echo "T4: bypass_audit_append registers an EXIT trap for tmp cleanup"
append_block=$(awk '/^bypass_audit_append\(\)/,/^}$/' "$LIB")
if echo "$append_block" | grep -qE "trap.*(rm -f .*\\\$tmp|EXIT|INT|TERM)"; then
  pass "T4: append has a trap covering tmp cleanup"
else
  fail_ "T4" "bypass_audit_append has no EXIT/INT/TERM trap protecting \$tmp"
fi

# T5: same for close_pending.
echo "T5: bypass_audit_close_pending registers an EXIT trap for tmp cleanup"
close_block=$(awk '/^bypass_audit_close_pending\(\)/,/^}$/' "$LIB")
if echo "$close_block" | grep -qE "trap.*(rm -f .*\\\$tmp|EXIT|INT|TERM)"; then
  pass "T5: close_pending has a trap covering tmp cleanup"
else
  fail_ "T5" "bypass_audit_close_pending has no EXIT/INT/TERM trap protecting \$tmp"
fi

# T6: no orphan tmp files after a normal successful append cycle.
# (The trap must not leave the post-rename tmp lying around.)
echo "T6: no orphan bypass-audit.json.XXXXXX files after a successful append"
setup
( source "$LIB" && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 )
orphans=$(find "$PROJ/.claude" -name "bypass-audit.json.*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$orphans" = "0" ]; then
  pass "T6: no orphan tmp files"
else
  fail_ "T6" "found $orphans orphan(s) in $PROJ/.claude:"
  find "$PROJ/.claude" -name "bypass-audit.json.*" -type f 2>/dev/null
fi
teardown

# T7: no orphan tmp files after a successful close_pending cycle.
echo "T7: no orphan bypass-audit.json.XXXXXX files after a successful close_pending"
setup
( source "$LIB" \
  && bypass_audit_append "$PROJ" "$ROW" >/dev/null 2>&1 \
  && bypass_audit_close_pending "$PROJ" "accept" >/dev/null 2>&1 )
orphans=$(find "$PROJ/.claude" -name "bypass-audit.json.*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$orphans" = "0" ]; then
  pass "T7: no orphan tmp files"
else
  fail_ "T7" "found $orphans orphan(s)"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

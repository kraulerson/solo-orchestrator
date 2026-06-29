#!/usr/bin/env bash
# tests/test-host-verify-protection-date-parse.sh — regression for code-lib-1.
#
# host_verify_protection on the 'other' host reads the attested timestamp
# from process-state.json. The age check uses GNU date first, then BSD
# date, then `|| echo "$now"` as a terminal fallback. That fallback
# silently classifies any unparseable timestamp as "fresh" (age=0 days),
# which bypasses the 90-day staleness check that drives the W3 backstop.
#
# Fail-closed fix: when BOTH parsers fail, emit a stderr warning naming
# the unparseable value and `return 1` so the caller treats the
# attestation as not-verified.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_LIB="$REPO_ROOT/scripts/lib/host.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_project() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  ( cd "$PROJ" && git init -q && git config user.email t@t.l && git config user.name t \
      && echo init > i && git add i && git commit -qm init )
  cat > "$PROJ/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
}
teardown() { rm -rf "$TMP"; }

# Seed process-state.json with a specific attestation timestamp value.
seed_attestation() {
  local ts="$1"
  jq -nc --arg t "$ts" '{phase2_init:{attestations:{branch_protection:{at:$t, attested_by:"orchestrator"}}}}' \
    > "$PROJ/.claude/process-state.json"
}

# T1: fresh attestation (today) verifies (sanity check).
echo "T1: fresh ISO-8601 attestation verifies (returns 0)"
setup_project
fresh_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
seed_attestation "$fresh_ts"
( cd "$PROJ" && source "$HOST_LIB" && _host_define_other_fallbacks && host_verify_protection >/dev/null 2>&1 )
rc=$?
if [ "$rc" = "0" ]; then pass "T1"; else fail_ "T1" "expected rc=0, got $rc"; fi
teardown

# T2: stale attestation (180 days ago) fails verification (sanity check).
echo "T2: 180-day-old attestation fails verification (returns 1)"
setup_project
# 180 days * 86400 = 15552000 seconds
old_epoch=$(( $(date +%s) - 15552000 ))
# Use BSD-compatible portable conversion.
if old_ts=$(date -u -r "$old_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null); then :; else
  old_ts=$(date -u -d "@$old_epoch" +"%Y-%m-%dT%H:%M:%SZ")
fi
seed_attestation "$old_ts"
( cd "$PROJ" && source "$HOST_LIB" && _host_define_other_fallbacks && host_verify_protection >/dev/null 2>&1 )
rc=$?
if [ "$rc" = "1" ]; then pass "T2"; else fail_ "T2" "expected rc=1 for 180-day-old; got $rc"; fi
teardown

# T3 (THE REGRESSION): garbage timestamp must fail-closed, not silently
# count as fresh. Pre-fix: `|| echo "$now"` made then=now, days=0,
# `[ 0 -gt 90 ]` false, return 0 — silent BYPASS.
echo "T3: unparseable timestamp returns 1 (fail-closed, not silently fresh)"
setup_project
seed_attestation "not-a-timestamp"
err=$( ( cd "$PROJ" && source "$HOST_LIB" && _host_define_other_fallbacks && host_verify_protection ) 2>&1 )
rc=$?
if [ "$rc" != "0" ]; then
  pass "T3: returned non-zero on unparseable timestamp"
else
  fail_ "T3" "expected non-zero (fail-closed); got rc=$rc — silent bypass restored"
fi
teardown

# T4: stderr explains the parse failure (operator needs to see the value).
echo "T4: stderr warning names the unparseable value"
setup_project
seed_attestation "garbage-value-xyz"
err=$( ( cd "$PROJ" && source "$HOST_LIB" && _host_define_other_fallbacks && host_verify_protection ) 2>&1 )
if echo "$err" | grep -qi "unparseable" && echo "$err" | grep -q "garbage-value-xyz"; then
  pass "T4: stderr names the value"
else
  fail_ "T4" "expected stderr to name 'unparseable' + the value; got: $err"
fi
teardown

# T5: GNU-style timestamp ("Sat Jun 28 12:34:56 UTC 2026") still parses
# via the first parser when GNU date is available. On BSD-only (macOS
# default), this would fall to the BSD parser; in either case the value
# is parseable, so the function must NOT trip the fail-closed branch.
# (We don't seed a value that requires GNU-only; we use ISO-8601 which
# the BSD parser explicitly handles per the source.)
echo "T5: ISO-8601 with explicit 'Z' parses cleanly on both GNU and BSD"
setup_project
# 30 days ago — well within 90-day window.
recent_epoch=$(( $(date +%s) - 2592000 ))
if recent_ts=$(date -u -r "$recent_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null); then :; else
  recent_ts=$(date -u -d "@$recent_epoch" +"%Y-%m-%dT%H:%M:%SZ")
fi
seed_attestation "$recent_ts"
( cd "$PROJ" && source "$HOST_LIB" && _host_define_other_fallbacks && host_verify_protection >/dev/null 2>&1 )
rc=$?
if [ "$rc" = "0" ]; then pass "T5"; else fail_ "T5" "expected rc=0 for 30-day-old; got $rc"; fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

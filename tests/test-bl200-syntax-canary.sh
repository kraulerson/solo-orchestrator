#!/usr/bin/env bash
# tests/test-bl200-syntax-canary.sh — BL-200's FRAMEWORK-SIDE CANARY.
#
# THE CONTRACT THIS FILE IS. The emitted hook's token-stream-break detector
# (# BL-200-SYNTAX-BREAK in scripts/lib/hook-templates.sh) reads ONE line of
# semgrep --verbose output: `[WARN] Syntax error at line <target>:N` at column
# 0. That anchor is REPORT-DEPENDENT — semgrep may respell it in any release —
# and the detector's admissibility terms (BL-200, constrained by BL-192's
# decision blocks) accept that ONLY because drift degrades to under-detection
# (the pre-BL-200 status quo), never to a false receipt, AND because this file
# exists: it scans committed-in-substance fixtures with the HOST semgrep and
# asserts the spelling still fires, so an upstream respelling turns THIS
# repo's CI lane red instead of silently blinding every generated project
# (BL-193: spellings move between versions and even between streams).
#
# NETWORK-FREE BY CONSTRUCTION. The probe ruleset is local, and its pattern
# names `innerHTML` deliberately: semgrep only PARSES a file some rule's
# literal prefilter admits (measured — a nonsense-token probe rule scanned the
# broken fixture and NO warning ever existed), so the probe must share a
# literal with the fixture. That is also why the detector works at all: a file
# hiding a sink textually CONTAINS the sink, so the parse is always attempted
# on exactly the files that matter.
#
# CASES
#   C1-broken-warns        the break fixture yields >=1 exact-spelling warning
#                          line — THE canary assertion.
#   C2-broken-still-blind  rc stays 0 with 0 findings on sink+break — the
#                          blind spot is still the landscape. If THIS moves,
#                          semgrep started failing loud on syntax breaks and
#                          BL-200's whole design deserves re-evaluation.
#   C3-clean-control       a VALID file admitted by the same prefilter warns 0
#                          times and rc=1 (the probe matches its innerHTML) —
#                          proves the parse genuinely ran; without this, C1
#                          could pass on a semgrep that warns about everything
#                          and C2 on one that scans nothing.
#   C4-header-once         the Scan Status header prints exactly once under
#                          --verbose on both fixtures — the emitted hook's
#                          exactly-once parse (# BL-112-SCAN-COVERAGE) rides
#                          on this staying true when the flag is on.
#
# REGISTRATION: never runs init.sh, not an aggregator -> registered in BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit fast lane, PINNED to
# the sast shard (the whole point is the CI host's real semgrep).
# Hermetic: mktemp workdir, no git, no network. bash-3.2 safe.

set -uo pipefail

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

if ! command -v semgrep >/dev/null 2>&1; then
  echo ""
  echo "#################################################################"
  echo "## semgrep IS NOT INSTALLED ON THIS HOST.                      ##"
  echo "## The BL-200 canary is SKIPPED, NOT PASSED — on the CI sast   ##"
  echo "## shard this suite MUST run; a skip there is a broken shard.  ##"
  echo "#################################################################"
  echo ""
  skip_ "C1-broken-warns"       "no semgrep on this host"
  skip_ "C2-broken-still-blind" "no semgrep on this host"
  skip_ "C3-clean-control"      "no semgrep on this host"
  skip_ "C4-header-once"        "no semgrep on this host"
  echo ""
  echo "!! ${SKIPPED} case(s) SKIPPED — skipped != passed."
  echo "Results: $PASSED passed, $FAILED failed (${SKIPPED} skipped)"
  exit 0
fi

# ── Fixtures (the BL-200 measurement, verbatim) ─────────────────────────────
# The break sits AFTER the sink: the sink literal admits the file through the
# prefilter, the break kills the parse — the attack ordering.
printf 'export function r(p){ p.innerHTML = window.name; }\nfunction ((( broken $$$\n' > "$TOPTMP/broken.ts"
# The control is VALID and carries the SAME literal, so it takes the same
# prefilter path and differs only in parseability.
printf 'export function r(p){ p.innerHTML = "x"; }\n' > "$TOPTMP/cleanparse.ts"
cat > "$TOPTMP/canary-probe.yml" << 'PROBEEOF'
rules:
  - id: soif-bl200-canary-parse-probe
    languages: [javascript, typescript]
    severity: ERROR
    message: BL-200 canary parse probe — the innerHTML literal admits the fixtures through semgrep's prefilter so the parse is attempted; on the valid control it also MATCHES, which is the non-vacuity proof.
    pattern: $EL.innerHTML = $V
PROBEEOF

# THE ATOM, verbatim from # BL-200-SYNTAX-BREAK (parse) in hook-templates.sh.
# If you change one, change both — the canary pins the hook's grep, not its own.
SYN_RE='^\[WARN\] Syntax error at line '
HDR_RE='^[[:space:]]*Scanning [0-9][0-9]* files? with [0-9][0-9]* Code rules?:[[:space:]]*$'

_count() { grep -cE "$1" "$2" 2>/dev/null || true; }

run_probe() {  # <fixture-basename> -> sets PR_RC PR_SYN PR_HDR PR_FINDINGS
  local fx="$1"
  ( cd "$TOPTMP" && semgrep scan --verbose --config=canary-probe.yml \
      --max-target-bytes=0 --no-git-ignore --severity=ERROR --error \
      "$fx" >"$TOPTMP/$fx.out" 2>"$TOPTMP/$fx.err" )
  PR_RC=$?
  cat "$TOPTMP/$fx.err" "$TOPTMP/$fx.out" > "$TOPTMP/$fx.status" 2>/dev/null || :
  PR_SYN=$(_count "$SYN_RE" "$TOPTMP/$fx.status"); PR_SYN=${PR_SYN:-0}
  PR_HDR=$(_count "$HDR_RE" "$TOPTMP/$fx.status"); PR_HDR=${PR_HDR:-0}
  PR_FINDINGS=$(_count 'soif-bl200-canary-parse-probe' "$TOPTMP/$fx.out"); PR_FINDINGS=${PR_FINDINGS:-0}
}

echo "=== BL-200 canary: host semgrep $(semgrep --version 2>/dev/null | sed -n 1p) ==="

run_probe broken.ts
B_RC=$PR_RC; B_SYN=$PR_SYN; B_HDR=$PR_HDR

echo "=== C1-broken-warns ==="
if [ "$B_SYN" -ge 1 ]; then
  pass "C1-broken-warns ($B_SYN exact-spelling warning line(s) on the break fixture)"
else
  fail_ "C1-broken-warns" "the HOST semgrep no longer emits '[WARN] Syntax error at line ' at column 0 for a token-stream break — THE ANCHOR HAS DRIFTED. Every generated project's BL-200 detector is now silently blind (it degrades to the pre-BL-200 receipt, it does not false-fire). Re-measure the spelling on this semgrep, update # BL-200-SYNTAX-BREAK (parse) AND this canary together, and re-run the emitted-hook suite. Verbose tail: $(tail -8 "$TOPTMP/broken.ts.err" | tr '\n' '|')"
fi

echo "=== C2-broken-still-blind ==="
if [ "$B_RC" -eq 0 ]; then
  pass "C2-broken-still-blind (rc=0 on sink+break — the blind spot BL-200 hardens against is still real on this semgrep)"
else
  fail_ "C2-broken-still-blind" "semgrep now exits $B_RC on the sink+break fixture — it no longer silently passes syntax-broken files. That is GOOD NEWS that this canary is built to catch: the BL-200 threat model changed, so re-evaluate whether the --verbose detector (and its stderr cost) is still warranted, and update BL-200 before silencing this"
fi

run_probe cleanparse.ts
C_RC=$PR_RC; C_SYN=$PR_SYN; C_HDR=$PR_HDR; C_FIND=$PR_FINDINGS

echo "=== C3-clean-control ==="
if [ "$C_SYN" -eq 0 ] && [ "$C_RC" -eq 1 ] && [ "$C_FIND" -ge 1 ]; then
  pass "C3-clean-control (0 warnings, rc=1, probe matched — the parse provably ran; C1/C2 are not vacuous)"
else
  fail_ "C3-clean-control" "the VALID same-prefilter control gave syn=$C_SYN rc=$C_RC findings=$C_FIND (want 0/1/>=1) — either the probe rule no longer parses/matches (C1 and C2 prove nothing) or clean files now warn (the detector would forfeit every receipt). Fix the canary before trusting either neighbour"
fi

echo "=== C4-header-once ==="
if [ "$B_HDR" -eq 1 ] && [ "$C_HDR" -eq 1 ]; then
  pass "C4-header-once (Scan Status header exactly once under --verbose on both fixtures)"
else
  fail_ "C4-header-once" "under --verbose the Scan Status header printed broken=$B_HDR clean=$C_HDR times (want exactly 1) — the emitted hook's exactly-once parse (# BL-112-SCAN-COVERAGE) would read this as unparseable and NOTRUN every commit on this semgrep"
fi

echo ""
if [ "${SKIPPED:-0}" -gt 0 ]; then
  echo "!! ${SKIPPED} case(s) SKIPPED — skipped != passed."
fi
echo "Results: $PASSED passed, $FAILED failed${SKIPPED:+ (${SKIPPED} skipped)}"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

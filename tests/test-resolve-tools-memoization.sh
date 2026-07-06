#!/usr/bin/env bash
# tests/test-resolve-tools-memoization.sh
#
# BL-051 — memoization of get_available_platforms().
#
# NOTE ON NAMING / LOCATION (discrepancy flagged during BL-051 work):
#   BL-051 (and the Step-4 recon it derives from) names the target
#   "scripts/resolve-tools.sh::get_available_platforms". That is a
#   MISATTRIBUTION — the function actually lives in ./init.sh (it is the
#   single-source-of-truth platform enumerator used by both the
#   interactive collect_inputs() and the non-interactive validator; see
#   the audit specs-plans-init-intake-noninteractive-2 comment above the
#   definition). scripts/resolve-tools.sh has no such function. This test
#   keeps the BL-051-mandated filename but exercises the real init.sh
#   definition. See the run report for the full discrepancy note.
#
# WHAT IS MEMOIZED
#   get_available_platforms() globs docs/platform-modules/*.md and
#   templates/pipelines/release/github/*.yml on every call. A single
#   non-interactive validate invocation calls it more than once
#   (--platform validation + the required-arg error message), and BL-045
#   forks a resolver per matrix cell, amplifying the per-call cost.
#   BL-051 wraps it in a process-local guard-var + cached-string
#   memoization (bash-3.2-safe — NO associative arrays), so the first
#   call scans the filesystem and every later call returns the cached
#   string verbatim.
#
# HOW WE PROVE "SCAN RUNS EXACTLY ONCE"
#   The scan body calls the external `basename` exactly once per file it
#   enumerates and nowhere else. We:
#     1. Extract the live get_available_platforms() definition from
#        init.sh (so the test tracks the real source, and a reverted
#        memoization is caught automatically — mutation-proof).
#     2. Point SCRIPT_DIR at a fixture with a known file count.
#     3. Shadow `basename` with a spy that appends one line to a counter
#        file per invocation (delegating to `command basename`).
#     4. Call the function 10x IN THE CURRENT SHELL (via stdout
#        redirection, NOT $(...), so the process-local guard var
#        persists across calls — a $(...) subshell would reset it and
#        mask a real regression).
#     5. Assert the spy fired exactly (#md + #yml) times — i.e. the scan
#        ran once, not ten times.
#   With memoization: spy count == fixture file count.
#   Without memoization: spy count == 10 × fixture file count → FAIL.
#
set -uo pipefail

SCRIPT_DIR_SELF="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_SELF/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

if [ ! -f "$INIT_SH" ]; then
  echo "FATAL: init.sh not found at $INIT_SH" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Extract the live function definition from init.sh ────────────────
# From the `get_available_platforms() {` line through the first
# column-0 `}` (the function's own body uses `fi`/`done`, never a
# standalone `}` at column 0, so this is unambiguous).
FUNC_SRC="$(awk '/^get_available_platforms\(\)/{f=1} f{print} f&&/^\}/{exit}' "$INIT_SH")"

if [ -z "$FUNC_SRC" ]; then
  echo "FATAL: could not extract get_available_platforms() from init.sh" >&2
  exit 2
fi

# ── Build a fixture with a KNOWN number of scanned files ─────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE/docs/platform-modules"
mkdir -p "$FIXTURE/templates/pipelines/release/github"

# 2 platform modules + 1 release pipeline = 3 files scanned per pass.
: > "$FIXTURE/docs/platform-modules/web.md"
: > "$FIXTURE/docs/platform-modules/mobile.md"
: > "$FIXTURE/templates/pipelines/release/github/desktop.yml"
EXPECTED_SCAN_FILES=3   # keep in sync with the fixture above

COUNTER="$TMP/basename-calls.log"
: > "$COUNTER"

# ── Spy on basename: one log line per call, then delegate to the real
#    external. Runs inside get_available_platforms' $(...) subshells, so
#    the count MUST be persisted to a file (a shell var wouldn't survive
#    the subshell). ─────────────────────────────────────────────────
basename() {
  printf 'x\n' >> "$COUNTER"
  command basename "$@"
}

# Point the extracted function at the fixture and load it.
SCRIPT_DIR="$FIXTURE"
# shellcheck disable=SC1090
eval "$FUNC_SRC"

# Sanity: make sure we really loaded a callable function.
if ! type get_available_platforms >/dev/null 2>&1; then
  echo "FATAL: get_available_platforms not defined after eval" >&2
  exit 2
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: 10 invocations return identical, correct output ==="
# ════════════════════════════════════════════════════════════════════
FIRST_OUT=""
IDENTICAL=1
CONTENT_OK=1
for i in $(seq 1 10); do
  # Redirect (current shell) instead of $(...) so the memoization guard
  # var persists across the 10 calls.
  get_available_platforms > "$TMP/out.$i"
  out="$(cat "$TMP/out.$i")"
  if [ "$i" -eq 1 ]; then
    FIRST_OUT="$out"
  elif [ "$out" != "$FIRST_OUT" ]; then
    IDENTICAL=0
  fi
done

# Output must enumerate the fixture platforms + the 'other' fallback.
case " $FIRST_OUT " in
  *" web "*)     ;; *) CONTENT_OK=0 ;;
esac
case " $FIRST_OUT " in
  *" mobile "*)  ;; *) CONTENT_OK=0 ;;
esac
case " $FIRST_OUT " in
  *" desktop "*) ;; *) CONTENT_OK=0 ;;
esac
case " $FIRST_OUT " in
  *" other "*)   ;; *) CONTENT_OK=0 ;;
esac

if [ "$IDENTICAL" -eq 1 ] && [ "$CONTENT_OK" -eq 1 ]; then
  pass "T1: 10 calls all returned '$FIRST_OUT' (web/mobile/desktop/other present)"
else
  fail_ "T1" "identical=$IDENTICAL content_ok=$CONTENT_OK first_out='$FIRST_OUT'"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: filesystem scan runs EXACTLY ONCE across 10 calls (memoization) ==="
# ════════════════════════════════════════════════════════════════════
CALLS="$(wc -l < "$COUNTER" | tr -d '[:space:]')"

if [ "$CALLS" -eq "$EXPECTED_SCAN_FILES" ]; then
  pass "T2: basename spy fired $CALLS time(s) = one scan of $EXPECTED_SCAN_FILES file(s) across 10 calls"
else
  # Without memoization this is 10 × EXPECTED_SCAN_FILES.
  fail_ "T2" "expected $EXPECTED_SCAN_FILES basename call(s) (one scan); got $CALLS — memoization is not caching (scan ran ~$((CALLS / EXPECTED_SCAN_FILES))×)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

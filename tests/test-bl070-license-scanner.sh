#!/usr/bin/env bash
# tests/test-bl070-license-scanner.sh
#
# BL-070 increment (WP-B1): scripts/run-phase3-validation.sh's `license`
# scanner promoted from stub to REAL. The scanner reads the project language
# from .claude/tool-preferences.json (.context.language — the CANONICAL
# source, NOT manifest.json), dispatches the per-language license tool
# (typescript→license-checker, python→pip-licenses, rust→cargo license,
# go→go-licenses, csharp→dotnet-project-licenses), archives the tool's JSON
# report, and reports PASS/FAIL/SKIP.
#
# Minimal increment contract (a license allow/deny POLICY is a deliberate
# non-goal, pending decision):
#   PASS = the tool produced a NON-EMPTY report (report-produced semantics —
#          some license tools exit 1 while still emitting a report, so PASS is
#          measured by report presence, NOT by rc==0) AND the JSON was archived.
#   FAIL = the tool crashed / produced no output.
#   SKIP = --offline, OR tool not on PATH, OR no canonical tool for the
#          language (all attestable — a SKIP without an attestation blocks the
#          Phase 3→4 gate).
#
# Cases:
#   T-license-real-pass          mock license-checker emits fixture JSON (rc 0)
#                                → PASS + archive file exists non-empty.
#   T-license-report-despite-rc1 mock license-checker emits JSON but exits 1
#                                → PASS (proves the contract is report-based,
#                                not rc-gated).
#   T-license-tool-missing-skip  no license-checker on PATH → attestable SKIP
#                                naming the install/manual option.
#   T-license-tool-crash-fail    mock license-checker exits 1 with NO output
#                                → FAIL (crash), NOT SKIP.
#   T-license-offline-skip       --offline → SKIP (never runs the tool).
#   T-unsupported-language-skip  language=java → attestable SKIP naming the
#                                manual option.
#   T-mutation                   MUTATION-PROOF: excise the `# BL-070-LICENSE-
#                                DISPATCH` line from a copy of the driver and
#                                re-run the real-pass fixture → the license PASS
#                                disappears (proving the dispatch is load-
#                                bearing: remove it → T-license-real-pass RED).
#
# HERMETIC: every license tool the driver could exec is neutralised. The driver
# runs with PATH = <mock dir>:<curated clean bin> and the clean bin symlinks a
# fixed set of coreutils but NO license tool and NO semgrep — so a host-
# installed license-checker / pip-licenses / semgrep can never leak in and the
# scan is offline + instant. The mock license-checker (created via the
# tests/host-drivers/mock-cli.sh helper, mock dir PREPENDED) is the only license
# tool the driver can find. bash-3.2 safe; no ((x++)); no real remotes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"
BASH_BIN="$(command -v bash)"

# shellcheck source=tests/host-drivers/mock-cli.sh
. "$SCRIPT_DIR/host-drivers/mock-cli.sh"
set +e   # mock-cli.sh sets `set -euo pipefail`; drop errexit, keep -u -o pipefail
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — BL-070 license scanner reads tool-preferences.json via jq."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Curated clean bin ────────────────────────────────────────────────
# Symlink only the coreutils the driver needs into a private dir. Running the
# driver with PATH pointed here (+ the mock dir) guarantees NO host license
# tool and NO host semgrep are reachable — the sole hermeticity guarantee.
CLEAN_BIN="$(mktemp -d "${TMPDIR:-/tmp}/bl070-cleanbin-XXXXXX")"
_build_clean_bin() {
  local t p
  for t in bash sh env cat head tail sed grep printf echo dirname basename \
           jq git date mkdir rmdir rm mv cp chmod ln sleep mktemp wc tr cut \
           sort uniq hostname whoami id test ls; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    [ -n "$p" ] && ln -sf "$p" "$CLEAN_BIN/$t" 2>/dev/null || true
  done
}
_build_clean_bin

# ── Per-test fixture ─────────────────────────────────────────────────
# setup <language> — a project dir with .claude/tool-preferences.json bound to
# <language>, a results dir, and a FRESH empty mock dir (tests add a mock
# license tool to it when they want one present).
setup() {
  local lang="$1"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/bl070-proj-XXXXXX")"
  PROJ="$TMP/p"
  RDIR="$PROJ/docs/test-results/phase3"
  mkdir -p "$PROJ/.claude" "$RDIR"
  # .context.language is the CANONICAL language source the scanner reads.
  printf '%s\n' "{\"context\":{\"language\":\"$lang\",\"platform\":\"web\",\"track\":\"light\",\"dev_os\":\"linux\"}}" \
    > "$PROJ/.claude/tool-preferences.json"
  MOCK_DIR="$(mock_cli_setup)"
}
teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
  mock_cli_teardown "${MOCK_DIR:-/nonexistent}" 2>/dev/null || true
}

# run_license_driver [extra-driver-args...] — run the driver in $PROJ with the
# hermetic PATH (mock dir prepended so it wins over anything in the clean bin),
# stdin from /dev/null (the mock stub drains stdin), archiving to $RDIR. Echoes
# combined stdout+stderr. Never aborts the test (|| true).
run_license_driver() {
  ( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$RDIR" "$@" </dev/null 2>&1 ) || true
}

# Newest archived license report, or empty.
license_archive() { ls -1 "$RDIR"/license-*.json 2>/dev/null | sort | tail -1; }

FIXTURE_JSON='{"react@18.2.0":{"licenses":"MIT","repository":"https://github.com/facebook/react"}}'

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-license-real-pass: mock license-checker emits JSON → PASS + archive ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
mock_cli_respond license-checker "--json" 0 "$FIXTURE_JSON"
out="$(run_license_driver)"
arch="$(license_archive)"
if echo "$out" | grep -q "\[PASS\] license"; then
  pass "T-license-real-pass: driver reports [PASS] license"
else
  fail_ "T-license-real-pass" "expected [PASS] license; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if [ -n "$arch" ] && [ -s "$arch" ]; then
  pass "T-license-real-pass: license report archived non-empty ($(basename "$arch"))"
else
  fail_ "T-license-real-pass" "expected a non-empty license-*.json archive; found '$arch'"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-license-report-despite-rc1: tool exits 1 but emits JSON → PASS ==="
# ════════════════════════════════════════════════════════════════════
# Some license tools exit non-zero while still producing a valid report. The
# contract is report-based, not rc-based: a non-empty report → PASS even at rc 1.
setup typescript
mock_cli_respond license-checker "--json" 1 "$FIXTURE_JSON"
out="$(run_license_driver)"
arch="$(license_archive)"
if echo "$out" | grep -q "\[PASS\] license"; then
  pass "T-license-report-despite-rc1: rc=1-with-report is PASS (not rc-gated)"
else
  fail_ "T-license-report-despite-rc1" "expected [PASS] license despite rc=1; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if [ -n "$arch" ] && [ -s "$arch" ]; then
  pass "T-license-report-despite-rc1: report archived non-empty"
else
  fail_ "T-license-report-despite-rc1" "expected a non-empty archive; found '$arch'"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-license-tool-missing-skip: no license-checker on PATH → attestable SKIP ==="
# ════════════════════════════════════════════════════════════════════
# No mock tool is registered and the clean bin has none → command -v fails.
setup typescript
out="$(run_license_driver)"
if echo "$out" | grep -q "\[SKIP\] license"; then
  pass "T-license-tool-missing-skip: driver reports [SKIP] license"
else
  fail_ "T-license-tool-missing-skip" "expected [SKIP] license; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -qE "license-checker not on PATH"; then
  pass "T-license-tool-missing-skip: SKIP names the missing tool + manual option"
else
  fail_ "T-license-tool-missing-skip" "expected a 'not on PATH' note; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -q "UN-ATTESTED"; then
  pass "T-license-tool-missing-skip: the SKIP is attestable (un-attested → gate would block)"
else
  fail_ "T-license-tool-missing-skip" "expected the SKIP to be flagged UN-ATTESTED; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if [ -z "$(license_archive)" ]; then
  pass "T-license-tool-missing-skip: no archive written for a SKIP"
else
  fail_ "T-license-tool-missing-skip" "a SKIP must not archive a report"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-license-tool-crash-fail: tool exits 1 with NO output → FAIL (not SKIP) ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
mock_cli_respond license-checker "--json" 1 ""
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-license-tool-crash-fail: driver reports [FAIL] license (crash → no report)"
else
  fail_ "T-license-tool-crash-fail" "expected [FAIL] license; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -q "\[SKIP\] license"; then
  fail_ "T-license-tool-crash-fail" "a crash must be FAIL, not a (attestable) SKIP"
else
  pass "T-license-tool-crash-fail: a crash is NOT downgraded to SKIP"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-license-offline-skip: --offline → SKIP (tool never run) ==="
# ════════════════════════════════════════════════════════════════════
# The tool IS present, but --offline must short-circuit to SKIP (keeps the gate
# autorun hermetic + instant), mirroring the semgrep arm's offline behavior.
setup typescript
mock_cli_respond license-checker "--json" 0 "$FIXTURE_JSON"
out="$(run_license_driver --offline)"
if echo "$out" | grep -q "\[SKIP\] license"; then
  pass "T-license-offline-skip: --offline yields [SKIP] license"
else
  fail_ "T-license-offline-skip" "expected [SKIP] license under --offline; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -qiE "offline"; then
  pass "T-license-offline-skip: note attributes the SKIP to offline mode"
else
  fail_ "T-license-offline-skip" "expected an 'offline' note; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if [ -z "$(license_archive)" ]; then
  pass "T-license-offline-skip: no archive written (tool not run)"
else
  fail_ "T-license-offline-skip" "offline SKIP must not run the tool / archive a report"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-unsupported-language-skip: language=java → attestable SKIP naming manual option ==="
# ════════════════════════════════════════════════════════════════════
setup java
out="$(run_license_driver)"
if echo "$out" | grep -q "\[SKIP\] license"; then
  pass "T-unsupported-language-skip: unsupported language yields [SKIP] license"
else
  fail_ "T-unsupported-language-skip" "expected [SKIP] license for java; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -qiE "no canonical license tool.*java|run your ecosystem's license audit manually"; then
  pass "T-unsupported-language-skip: SKIP names the manual option for java"
else
  fail_ "T-unsupported-language-skip" "expected a 'no canonical tool / run manually' note; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -q "UN-ATTESTED"; then
  pass "T-unsupported-language-skip: the SKIP is attestable"
else
  fail_ "T-unsupported-language-skip" "expected UN-ATTESTED; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation: excise # BL-070-LICENSE-DISPATCH → real-pass goes RED ==="
# ════════════════════════════════════════════════════════════════════
# Copy the driver, delete every line carrying `# BL-070-LICENSE-DISPATCH` (the
# typescript run arm — the load-bearing dispatch for the tested language), and
# re-run the real-pass fixture. Real driver: [PASS] license. Mutant: the arm is
# gone → nothing runs → empty archive → [FAIL] license, NO [PASS] — proving the
# marked line is what makes T-license-real-pass pass (remove it → RED).
setup typescript
mock_cli_respond license-checker "--json" 0 "$FIXTURE_JSON"
MUT="$TMP/mut-driver.sh"
grep -v 'BL-070-LICENSE-DISPATCH' "$DRIVER" > "$MUT"
chmod +x "$MUT"
if ! grep -q 'BL-070-LICENSE-DISPATCH' "$DRIVER"; then
  fail_ "T-mutation" "BL-070-LICENSE-DISPATCH marker missing from the REAL driver — nothing to mutate"
elif grep -q 'BL-070-LICENSE-DISPATCH' "$MUT"; then
  fail_ "T-mutation" "marker still present after excision — mutation did not apply"
elif ! "$BASH_BIN" -n "$MUT" 2>/dev/null; then
  fail_ "T-mutation" "mutant driver is not syntactically valid after excision"
else
  # Distinct results dirs: real + mutant runs can land in the same wall-clock
  # second (identical license-<TS>.json name). Sharing $RDIR would let the
  # mutant's non-empty-archive check see the REAL run's leftover file and
  # falsely PASS. Isolate them.
  mkdir -p "$TMP/real-rdir" "$TMP/mut-rdir"
  real_out="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$TMP/real-rdir" </dev/null 2>&1 )" || true
  mut_out="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$MUT" \
      --results-dir "$TMP/mut-rdir" </dev/null 2>&1 )" || true
  if echo "$real_out" | grep -q "\[PASS\] license"; then
    pass "T-mutation: real driver emits [PASS] license"
  else
    fail_ "T-mutation" "real driver did NOT emit [PASS] license (fixture wrong?); out:
$(echo "$real_out" | grep -iE 'license' | head)"
  fi
  if echo "$mut_out" | grep -q "\[PASS\] license"; then
    fail_ "T-mutation" "mutant STILL emitted [PASS] license — dispatch not load-bearing (mutation not proof)"
  else
    pass "T-mutation: mutant (dispatch stripped) does NOT emit [PASS] license (RED proof)"
  fi
fi
teardown

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$CLEAN_BIN"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

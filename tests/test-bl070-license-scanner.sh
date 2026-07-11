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
# Inventory contract (BL-070):
#   PASS = the tool produced a NON-EMPTY report (report-produced semantics —
#          some license tools exit 1 while still emitting a report, so PASS is
#          measured by report presence, NOT by rc==0) AND the JSON was archived.
#   FAIL = the tool crashed / produced no output.
#   SKIP = --offline, OR tool not on PATH, OR no canonical tool for the
#          language (all attestable — a SKIP without an attestation blocks the
#          Phase 3→4 gate).
#
# BL-086 (2026-07-11) layers a TIER-KEYED DENY POLICY on the archived inventory
# (the T-deny-* / T-personal-* / T-policy-* / T-attested-* / per-format /
# T-mutation-{deny,tier} cases below). Strong copyleft (GPL/AGPL/SSPL) BLOCKS
# the corporate track (deployment=organizational OR poc_mode=sponsored_poc OR
# poc_mode=private_poc — private POC blocks too, Karl's 2026-07-11 correction);
# a pure personal project warns loudly instead. Override via
# .claude/license-policy.json; blocked-tier attested escape via
# SOLO_LICENSE_ATTESTED=1 (recorded to phase3.license_exceptions[], never
# silenced). The deny match keys on the LICENSE field only (never package
# names) and is boundary-safe (LGPL/MPL/EPL never match a GPL stem).
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

# ── BL-086 helpers (tier-keyed license-policy deny enforcement) ───────
# set_tier <deployment> <poc_mode:null|private_poc|sponsored_poc> [track] —
# write $PROJ/.claude/phase-state.json so the scanner can key the deny gate on
# the ACTUAL tier (deployment + poc_mode). `track` is written VERBATIM so the
# dangerous spoof combo (organizational + track=light) is exercised; the
# scanner must key on the tier, NEVER on track. poc_mode=null is UNQUOTED
# (mirrors init.sh's non-POC / production shape).
set_tier() {
  local dep="$1" poc="$2" track="${3:-light}" pocj="null"
  [ -n "$poc" ] && [ "$poc" != "null" ] && pocj="\"$poc\""
  printf '%s\n' "{\"current_phase\":3,\"deployment\":\"$dep\",\"poc_mode\":$pocj,\"track\":\"$track\",\"gates\":{}}" \
    > "$PROJ/.claude/phase-state.json"
}

# write_policy <json> — write the optional .claude/license-policy.json DATA file.
write_policy() { printf '%s\n' "$1" > "$PROJ/.claude/license-policy.json"; }

# mock_license_tool <language> <license-string> [pkgname] — register the mock
# per-language license tool so it emits a one-package report carrying <license>
# in THAT tool's exact archived format. Covers all five dispatched formats:
#   typescript license-checker JSON  {pkg@ver:{licenses}}
#   python     pip-licenses JSON     [{License,Name,Version}]
#   rust       cargo license --json  [{name,version,license}]  (+ cargo-license on PATH for the command -v probe)
#   go         go-licenses report    CSV pkg,url,license (driver wraps to the {lines:[...]} envelope)
#   csharp     dotnet-project-licenses -j  [{PackageName,PackageVersion,LicenseType}]
mock_license_tool() {
  local lang="$1" lic="$2" pkg="${3:-gpl-pkg}"
  case "$lang" in
    typescript) mock_cli_respond license-checker "--json" 0 "{\"${pkg}@1.0.0\":{\"licenses\":\"${lic}\"}}" ;;
    python)     mock_cli_respond pip-licenses "--format=json" 0 "[{\"License\":\"${lic}\",\"Name\":\"${pkg}\",\"Version\":\"1.0\"}]" ;;
    rust)       mock_cli_respond cargo-license "" 0 ""
                mock_cli_respond cargo "license" 0 "[{\"name\":\"${pkg}\",\"version\":\"1.0\",\"license\":\"${lic}\"}]" ;;
    go)         mock_cli_respond go-licenses "report" 0 "example.com/${pkg},https://licenses/${pkg},${lic}" ;;
    csharp)     mock_cli_respond dotnet-project-licenses "-j" 0 "[{\"PackageName\":\"${pkg}\",\"PackageVersion\":\"1.0\",\"LicenseType\":\"${lic}\"}]" ;;
  esac
}

# run_license_driver_env "<VAR=val ...>" [extra-args] — like run_license_driver
# but with extra environment (for SOLO_LICENSE_ATTESTED / SOLO_LICENSE_REASON).
run_license_driver_env() {
  local envs="$1"; shift
  ( cd "$PROJ" && env $envs PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$RDIR" "$@" </dev/null 2>&1 ) || true
}

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

# ════════════════════════════════════════════════════════════════════
# BL-086 — tier-keyed license-policy DENY enforcement
# ════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-deny-org-gpl: organizational + GPL → [FAIL] license naming pkg ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
set_tier organizational null
mock_license_tool typescript "GPL-3.0" "gpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-deny-org-gpl: organizational tier BLOCKS a denied license ([FAIL] license)"
else
  fail_ "T-deny-org-gpl" "expected [FAIL] license for organizational + GPL; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -q "gpl-lib" && echo "$out" | grep -q "GPL-3.0"; then
  pass "T-deny-org-gpl: the FAIL names the offending package + license (gpl-lib / GPL-3.0)"
else
  fail_ "T-deny-org-gpl" "expected the FAIL to name gpl-lib (GPL-3.0); out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-deny-sponsored-agpl: sponsored_poc + AGPL → [FAIL] license ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
set_tier organizational sponsored_poc
mock_license_tool typescript "AGPL-3.0" "agpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license" && echo "$out" | grep -q "agpl-lib"; then
  pass "T-deny-sponsored-agpl: sponsored_poc BLOCKS AGPL, naming agpl-lib"
else
  fail_ "T-deny-sponsored-agpl" "expected [FAIL] license naming agpl-lib for sponsored_poc + AGPL; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-deny-privatepoc-gpl: private_poc + GPL → [FAIL] (Karl's correction, load-bearing) ==="
# ════════════════════════════════════════════════════════════════════
# THE corrected requirement: a private POC BLOCKS too (it is the runway to a
# Sponsored POC — a copyleft dep added here ratchets forward). This differs
# from the BL-084 bypass predicate, which treats private_poc as bypassable.
setup typescript
set_tier personal private_poc
mock_license_tool typescript "GPL-3.0" "gpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license" && echo "$out" | grep -q "gpl-lib"; then
  pass "T-deny-privatepoc-gpl: private_poc BLOCKS a denied license (Karl's corrected rule)"
else
  fail_ "T-deny-privatepoc-gpl" "expected [FAIL] license naming gpl-lib for private_poc + GPL; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-personal-warning-banner: pure personal + GPL → PASS + LARGE banner ==="
# ════════════════════════════════════════════════════════════════════
# Pure personal (deployment=personal, no poc_mode): NOT blocked, but a denied
# license triggers a large, unmissable warning banner naming EVERY copyleft
# package AND the commercial/service/transition ramifications.
setup typescript
set_tier personal null
mock_cli_respond license-checker "--json" 0 '{"gpl-lib@1.0.0":{"licenses":"GPL-3.0"},"agpl-lib@2.0.0":{"licenses":"AGPL-3.0"}}'
out="$(run_license_driver)"
if echo "$out" | grep -q "\[PASS\] license"; then
  pass "T-personal-warning-banner: pure personal PASSes (does NOT block)"
else
  fail_ "T-personal-warning-banner" "expected [PASS] license for pure personal + GPL; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -q "LICENSE WARNING"; then
  pass "T-personal-warning-banner: the LARGE warning banner is emitted"
else
  fail_ "T-personal-warning-banner" "expected a LICENSE WARNING banner; out:
$(echo "$out" | head -40)"
fi
if echo "$out" | grep -q "gpl-lib" && echo "$out" | grep -q "agpl-lib"; then
  pass "T-personal-warning-banner: banner names BOTH copyleft packages"
else
  fail_ "T-personal-warning-banner" "expected banner to name gpl-lib AND agpl-lib; out:
$(echo "$out" | grep -iE 'gpl' | head)"
fi
if echo "$out" | grep -qi "COMMERCIAL" && echo "$out" | grep -qi "SERVICE" && echo "$out" | grep -qi "TRANSITION"; then
  pass "T-personal-warning-banner: banner states the commercial/service/transition ramifications"
else
  fail_ "T-personal-warning-banner" "expected commercial/service/transition ramifications text; out:
$(echo "$out" | head -40)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-no-phasestate-warns: no phase-state + GPL → warns (mothership → pure personal) ==="
# ════════════════════════════════════════════════════════════════════
# Missing/empty phase-state (mothership / unscaffolded) is treated as pure
# personal → WARN, never block.
setup typescript
# NOTE: deliberately no set_tier — .claude/phase-state.json does not exist.
mock_license_tool typescript "GPL-3.0" "gpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[PASS\] license" && ! echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-no-phasestate-warns: absent phase-state → PASS (treated as pure personal)"
else
  fail_ "T-no-phasestate-warns" "expected [PASS] license (not FAIL) with no phase-state; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
if echo "$out" | grep -q "LICENSE WARNING"; then
  pass "T-no-phasestate-warns: the warning banner still fires"
else
  fail_ "T-no-phasestate-warns" "expected a LICENSE WARNING banner; out:
$(echo "$out" | head -40)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-spoof-track: organizational + track=light + GPL → [FAIL] (tier ≠ track) ==="
# ════════════════════════════════════════════════════════════════════
# track=light must NOT unlock a bypass for an organizational project — the gate
# keys on the ACTUAL tier (deployment + poc_mode), never the spoofable track.
setup typescript
set_tier organizational null light
mock_license_tool typescript "GPL-3.0" "gpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-spoof-track: organizational + track=light still BLOCKS (tier ≠ track)"
else
  fail_ "T-spoof-track" "expected [FAIL] license despite track=light on an organizational project; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-dual-license-passes: 'MIT OR GPL-3.0' → PASS (consumer may elect MIT) ==="
# ════════════════════════════════════════════════════════════════════
# Even on the BLOCKED (organizational) tier, an OR expression with a safe
# alternative PASSes — FP hygiene, the consumer can elect the non-copyleft side.
setup typescript
set_tier organizational null
mock_license_tool typescript "MIT OR GPL-3.0" "dual-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[PASS\] license" && ! echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-dual-license-passes: 'MIT OR GPL-3.0' is NOT flagged (OR-election)"
else
  fail_ "T-dual-license-passes" "expected [PASS] license for a dual MIT-OR-GPL license; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-lgpl-not-denied: LGPL-3.0 on organizational → PASS (weak copyleft, not denied) ==="
# ════════════════════════════════════════════════════════════════════
# LGPL-3.0 must NOT match a GPL-3.0 pattern (boundary-safe). Weak copyleft is
# EXPLICITLY not on the default deny list.
setup typescript
set_tier organizational null
mock_license_tool typescript "LGPL-3.0" "lgpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[PASS\] license" && ! echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-lgpl-not-denied: LGPL-3.0 is NOT denied (boundary-safe vs GPL-3.0)"
else
  fail_ "T-lgpl-not-denied" "expected [PASS] license for LGPL-3.0; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-pkg-name-not-matched: package 'gpl-utils' with MIT → PASS (match license, not name) ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
set_tier organizational null
mock_license_tool typescript "MIT" "gpl-utils"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[PASS\] license" && ! echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-pkg-name-not-matched: 'gpl-utils' (MIT) passes clean — only the LICENSE field is matched"
else
  fail_ "T-pkg-name-not-matched" "expected [PASS] license for gpl-utils@MIT; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-policy-override: custom deny denies MPL → organizational + MPL FAIL; GPL now passes (REPLACE) ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
set_tier organizational null
write_policy '{"deny":["MPL-2.0"]}'
mock_license_tool typescript "MPL-2.0" "mpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license" && echo "$out" | grep -q "mpl-lib"; then
  pass "T-policy-override: a custom deny list denies MPL-2.0 (org + MPL → FAIL)"
else
  fail_ "T-policy-override" "expected [FAIL] license naming mpl-lib under a custom MPL deny; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown
# Replace-semantics: under the MPL-only policy, the DEFAULT GPL deny is gone.
setup typescript
set_tier organizational null
write_policy '{"deny":["MPL-2.0"]}'
mock_license_tool typescript "GPL-3.0" "gpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[PASS\] license" && ! echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-policy-override: deny REPLACES the default (GPL-3.0 passes under an MPL-only policy)"
else
  fail_ "T-policy-override" "expected GPL-3.0 to PASS under an MPL-only deny (replace semantics); out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-policy-allow-package: allow_packages exempts a named GPL package → PASS ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
set_tier organizational null
write_policy '{"allow_packages":["gpl-lib"]}'
mock_license_tool typescript "GPL-3.0" "gpl-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[PASS\] license" && ! echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-policy-allow-package: an allow_packages entry exempts the named package (commercial-license case)"
else
  fail_ "T-policy-allow-package" "expected [PASS] license — gpl-lib exempted via allow_packages; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-policy-malformed-fails: malformed license-policy.json → LOUD scanner FAIL ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
set_tier organizational null
write_policy '{"deny": [not valid json'
mock_license_tool typescript "MIT" "mit-lib"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license" && echo "$out" | grep -qi "malformed"; then
  pass "T-policy-malformed-fails: malformed policy JSON → LOUD FAIL (never silently ignored)"
else
  fail_ "T-policy-malformed-fails" "expected [FAIL] license citing malformed policy; out:
$(echo "$out" | grep -iE 'license|malformed' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-attested-passes-recorded: org + GPL + SOLO_LICENSE_ATTESTED=1 → PASS + recorded ==="
# ════════════════════════════════════════════════════════════════════
setup typescript
set_tier organizational null
mock_license_tool typescript "GPL-3.0" "gpl-lib"
out="$(run_license_driver_env "SOLO_LICENSE_ATTESTED=1 SOLO_LICENSE_REASON=commercial-license-negotiated")"
if echo "$out" | grep -q "\[ATTESTED\] license"; then
  pass "T-attested-passes-recorded: the attested escape prints a loud [ATTESTED] line"
else
  fail_ "T-attested-passes-recorded" "expected an [ATTESTED] license line; out:
$(echo "$out" | grep -iE 'license|attest' | head)"
fi
if echo "$out" | grep -q "\[PASS\] license" && ! echo "$out" | grep -q "\[FAIL\] license"; then
  pass "T-attested-passes-recorded: attested → the scanner PASSes (attested, not silenced)"
else
  fail_ "T-attested-passes-recorded" "expected [PASS] license when attested; out:
$(echo "$out" | grep -iE 'license' | head)"
fi
rec_len="$(jq -r '.phase3.license_exceptions | length' "$PROJ/.claude/phase-state.json" 2>/dev/null || echo 0)"
rec_reason="$(jq -r '.phase3.license_exceptions[0].reason // ""' "$PROJ/.claude/phase-state.json" 2>/dev/null || echo "")"
rec_pkgs="$(jq -r '.phase3.license_exceptions[0].packages | join(",")' "$PROJ/.claude/phase-state.json" 2>/dev/null || echo "")"
if [ "$rec_len" = "1" ] && [ "$rec_reason" = "commercial-license-negotiated" ] && echo "$rec_pkgs" | grep -q "gpl-lib"; then
  pass "T-attested-passes-recorded: the exception is recorded to phase3.license_exceptions[] {reason, packages}"
else
  fail_ "T-attested-passes-recorded" "expected a recorded exception (len=$rec_len reason='$rec_reason' pkgs='$rec_pkgs')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-attested-record-failure-refuses: unwritable .claude → attest record FAILS → [FAIL] ==="
# ════════════════════════════════════════════════════════════════════
# A recording failure must REFUSE the pass (attested, never silenced). If the
# record cannot be written, the scanner FAILs rather than silently green-lighting.
if [ "$(id -u 2>/dev/null || echo 1000)" = "0" ]; then
  echo "  [SKIP] T-attested-record-failure-refuses: running as root — chmod cannot restrict writes."
else
  setup typescript
  set_tier organizational null
  mock_license_tool typescript "GPL-3.0" "gpl-lib"
  chmod 500 "$PROJ/.claude"
  out="$(run_license_driver_env "SOLO_LICENSE_ATTESTED=1")"
  chmod 700 "$PROJ/.claude"
  if echo "$out" | grep -q "\[FAIL\] license"; then
    pass "T-attested-record-failure-refuses: a failed exception record REFUSES the pass ([FAIL] license)"
  else
    fail_ "T-attested-record-failure-refuses" "expected [FAIL] license when the record cannot be written; out:
$(echo "$out" | grep -iE 'license|record|write' | head)"
  fi
  if echo "$out" | grep -qiE "attestation record FAILED|NOT recorded|cannot write"; then
    pass "T-attested-record-failure-refuses: the FAIL explains the recording failure"
  else
    fail_ "T-attested-record-failure-refuses" "expected a recording-failure explanation; out:
$(echo "$out" | grep -iE 'license|record|write' | head)"
  fi
  teardown
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Per-format deny detection across all five tool formats ==="
# ════════════════════════════════════════════════════════════════════
# Each per-language archived format is parsed for the deny scan on the BLOCKED
# (organizational) tier. python uses the realistic pip-licenses classifier
# string (bare 'GPLv3' acronym) to prove the bare-string match path.
per_format_deny() {
  local lang="$1" lic="$2"
  setup "$lang"
  set_tier organizational null
  mock_license_tool "$lang" "$lic" "gpl-lib"
  local o; o="$(run_license_driver)"
  if echo "$o" | grep -q "\[FAIL\] license" && echo "$o" | grep -q "gpl-lib"; then
    pass "per-format deny [$lang]: [FAIL] license names the denied package"
  else
    fail_ "per-format deny [$lang]" "expected [FAIL] license naming gpl-lib ($lic); out:
$(echo "$o" | grep -iE 'license' | head)"
  fi
  teardown
}
per_format_deny typescript "GPL-3.0"
per_format_deny python     "GNU General Public License v3 (GPLv3)"
per_format_deny rust       "GPL-3.0"
per_format_deny go         "GPL-3.0"
per_format_deny csharp     "GPL-3.0"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-unparseable-format-loud-fail: non-JSON archive → LOUD scanner FAIL ==="
# ════════════════════════════════════════════════════════════════════
# The inventory PASSes on a non-empty report; the deny scan then cannot parse
# the (non-JSON) archive → LOUD FAIL, never a silent pass.
setup typescript
set_tier organizational null
mock_cli_respond license-checker "--json" 0 "this is not json at all"
out="$(run_license_driver)"
if echo "$out" | grep -q "\[FAIL\] license" && echo "$out" | grep -qiE "could not be parsed|invalid/unrecognised|unrecognised"; then
  pass "T-unparseable-format-loud-fail: an unparseable license report → LOUD FAIL"
else
  fail_ "T-unparseable-format-loud-fail" "expected [FAIL] license citing a parse failure; out:
$(echo "$out" | grep -iE 'license|pars' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation-deny: excise # BL-086-DENY → T-deny-org-gpl goes RED ==="
# ════════════════════════════════════════════════════════════════════
# Copy the driver, delete every line carrying # BL-086-DENY (the load-bearing
# denied-stem comparison), and re-run organizational + GPL. Real driver: [FAIL]
# license. Mutant: nothing is ever denied → no FAIL — proving the comparison is
# what makes T-deny-org-gpl block (remove it → RED).
setup typescript
set_tier organizational null
mock_license_tool typescript "GPL-3.0" "gpl-lib"
MUT="$TMP/mut-deny.sh"
grep -v 'BL-086-DENY' "$DRIVER" > "$MUT"
chmod +x "$MUT"
if ! grep -q 'BL-086-DENY' "$DRIVER"; then
  fail_ "T-mutation-deny" "BL-086-DENY marker missing from the REAL driver — nothing to mutate"
elif grep -q 'BL-086-DENY' "$MUT"; then
  fail_ "T-mutation-deny" "marker still present after excision — mutation did not apply"
elif ! "$BASH_BIN" -n "$MUT" 2>/dev/null; then
  fail_ "T-mutation-deny" "mutant driver is not syntactically valid after excision"
else
  mkdir -p "$TMP/real-rdir" "$TMP/mut-rdir"
  real_out="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$TMP/real-rdir" </dev/null 2>&1 )" || true
  mut_out="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$MUT" \
      --results-dir "$TMP/mut-rdir" </dev/null 2>&1 )" || true
  if echo "$real_out" | grep -q "\[FAIL\] license"; then
    pass "T-mutation-deny: real driver BLOCKS organizational + GPL ([FAIL] license)"
  else
    fail_ "T-mutation-deny" "real driver did NOT [FAIL] license (fixture wrong?); out:
$(echo "$real_out" | grep -iE 'license' | head)"
  fi
  if echo "$mut_out" | grep -q "\[FAIL\] license"; then
    fail_ "T-mutation-deny" "mutant STILL blocked — the deny comparison is not load-bearing (not a proof)"
  else
    pass "T-mutation-deny: mutant (deny comparison stripped) does NOT block (RED proof)"
  fi
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation-tier: neuter # BL-086-TIER → org AND private_poc both warn-only (RED) ==="
# ════════════════════════════════════════════════════════════════════
# Delete every line carrying # BL-086-TIER (the load-bearing tier predicate);
# blocked can then never become true → EVERY tier warns-only. Both the
# organizational AND the private_poc block-cases go RED (they FAIL only because
# of the tier line). Prove real=FAIL, mutant≠FAIL for BOTH tiers.
# The mutant lives OUTSIDE any per-case $TMP (which is torn down between the
# org and private_poc sub-cases below), so it survives both runs.
MUT="$(mktemp "${TMPDIR:-/tmp}/bl086-mut-tier-XXXXXX")"
grep -v 'BL-086-TIER' "$DRIVER" > "$MUT"
chmod +x "$MUT"
if ! grep -q 'BL-086-TIER' "$DRIVER"; then
  fail_ "T-mutation-tier" "BL-086-TIER marker missing from the REAL driver — nothing to mutate"
elif grep -q 'BL-086-TIER' "$MUT"; then
  fail_ "T-mutation-tier" "marker still present after excision — mutation did not apply"
elif ! "$BASH_BIN" -n "$MUT" 2>/dev/null; then
  fail_ "T-mutation-tier" "mutant driver is not syntactically valid after excision"
else
  # --- organizational block-case ---
  setup typescript
  set_tier organizational null
  mock_license_tool typescript "GPL-3.0" "gpl-lib"
  mkdir -p "$TMP/real-org" "$TMP/mut-org"
  real_org="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" --results-dir "$TMP/real-org" </dev/null 2>&1 )" || true
  mut_org="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$MUT" --results-dir "$TMP/mut-org" </dev/null 2>&1 )" || true
  teardown
  # --- private_poc block-case ---
  setup typescript
  set_tier personal private_poc
  mock_license_tool typescript "GPL-3.0" "gpl-lib"
  mkdir -p "$TMP/real-ppoc" "$TMP/mut-ppoc"
  real_ppoc="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" --results-dir "$TMP/real-ppoc" </dev/null 2>&1 )" || true
  mut_ppoc="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$MUT" --results-dir "$TMP/mut-ppoc" </dev/null 2>&1 )" || true
  teardown

  if echo "$real_org" | grep -q "\[FAIL\] license" && echo "$real_ppoc" | grep -q "\[FAIL\] license"; then
    pass "T-mutation-tier: real driver BLOCKS BOTH organizational AND private_poc"
  else
    fail_ "T-mutation-tier" "real driver did NOT block both tiers; org:
$(echo "$real_org" | grep -iE 'license' | head -1)
ppoc:
$(echo "$real_ppoc" | grep -iE 'license' | head -1)"
  fi
  if echo "$mut_org" | grep -q "\[FAIL\] license" || echo "$mut_ppoc" | grep -q "\[FAIL\] license"; then
    fail_ "T-mutation-tier" "mutant STILL blocked a tier — the tier predicate is not load-bearing (not a proof)"
  else
    pass "T-mutation-tier: mutant (tier predicate neutered) blocks NEITHER tier — warns-only (RED proof)"
  fi
fi
rm -f "$MUT"

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$CLEAN_BIN"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

#!/usr/bin/env bash
# tests/test-bl070-snyk-zap-scanners.sh
#
# BL-070 COMPLETION (WP-B3/B4): scripts/run-phase3-validation.sh's `snyk` and
# `zap-dast` scanners promoted from stubs to REAL. After this arm ALL FIVE
# Phase-3 scanners are real. Both new arms are detect-and-run-if-available ONLY
# and SKIP under --offline so the gate autorun stays hermetic + instant.
#
# SNYK (WP-B3) — dependency vulnerability scan.
#   SKIP  = --offline, OR `snyk` not on PATH (names `npm install -g snyk`), OR
#           not authenticated (SNYK_TOKEN env OR a stored token via
#           `snyk config get api`; names `snyk auth`). All attestable.
#   run   = authenticated → `snyk test --json`, archive snyk-<ts>.json.
#   Findings policy MIRRORS the semgrep arm: snyk exits 1 WITH a report when
#   vulnerabilities are found, 2 on execution error — so rc>=2 / no report →
#   FAIL, vulnerabilities>0 → FAIL, 0 vulns → PASS (a security scanner: findings
#   block, unlike the inventory-only license arm).
#
# ZAP (WP-B4) — OWASP ZAP baseline DAST.
#   SKIP  = --offline; OR .context.platform ∉ {web, api} (PLATFORM GATE FIRST —
#           attestable, never a silent auto-pass); OR `docker` not on PATH; OR
#           SOLO_ZAP_TARGET_URL unset (names the variable). All attestable.
#   run   = `zap-baseline.py` via the ghcr.io/zaproxy/zaproxy:stable image
#           against SOLO_ZAP_TARGET_URL, archive zap-dast-<ts>.json.
#   Findings policy MIRRORS the semgrep arm (BL-122): no report / rc>=3 → FAIL
#   (crash, not a skip); Medium+ alerts (riskcode >= 2) → FAIL; ONLY
#   informational/low alerts → PASS (rule 10049 fires under every possible
#   Cache-Control value, so an unfiltered count made zero-alerts unreachable
#   and the gate unpassable for any web app); unparseable/unevaluable report
#   → FAIL naming the reason (a report nobody read is not a pass). Baseline
#   rc 1/2 alone no longer fails — the risk filter IS the severity policy.
#
# Cases:
#   T-snyk-auth-pass       authenticated + clean JSON report → PASS + non-empty
#                          archive.
#   T-snyk-findings-report snyk exits 1 WITH a vuln report → FAIL (semgrep
#                          policy: findings block), archive present.
#   T-snyk-unauth-skip     on PATH but no token → attestable SKIP naming
#                          `snyk auth`.
#   T-snyk-missing-skip    snyk not on PATH → attestable SKIP naming the install.
#   T-snyk-crash-fail      nonzero rc + NO report → FAIL (crash), NOT SKIP.
#   T-snyk-offline-skip    --offline → SKIP (tool never run).
#   T-zap-web-pass         platform=web + docker + URL + clean report → PASS +
#                          archive.
#   T-zap-api-pass         platform=api is DAST-eligible → PASS.
#   T-zap-findings-fail    report WITH alerts (rc 2) → FAIL (semgrep policy).
#   T-zap-platform-skip    platform=desktop + docker + URL present → attestable
#                          SKIP (platform gate fires FIRST — docker never run).
#   T-zap-no-docker-skip   docker not on PATH → attestable SKIP.
#   T-zap-no-url-skip      SOLO_ZAP_TARGET_URL unset → attestable SKIP naming it.
#   T-zap-offline-skip     --offline → SKIP.
#   T-zap-crash-fail       docker runs but produces NO report (nonzero) → FAIL.
#   T-mutation-snyk        excise `# BL-070-SNYK-DISPATCH` → T-snyk-auth-pass RED
#                          (real: [PASS] snyk; mutant: no [PASS] snyk).
#   T-mutation-zap         excise `# BL-070-ZAP-DISPATCH` → T-zap-web-pass RED
#                          (real: [PASS] zap-dast; mutant: no [PASS] zap-dast).
#
# HERMETIC: the driver runs with PATH = <mock dir>:<curated clean bin>. The
# clean bin symlinks a fixed set of coreutils but NO snyk, NO docker, NO semgrep
# and NO license tool — so a host-installed tool can NEVER leak in. snyk is
# mocked via tests/host-drivers/mock-cli.sh (stdout+rc canned per arg-pattern);
# docker is a bespoke stub that writes the ZAP JSON report into the bind-mounted
# host tmpdir and exits a canned code. No real network / Docker / auth is ever
# reached. bash-3.2 safe; no ((x++)); no real remotes; no init.sh invocation.

set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
unset SNYK_TOKEN 2>/dev/null || true          # auth is exercised via the mock `snyk config get api`
unset SOLO_ZAP_TARGET_URL 2>/dev/null || true # set per-test via $ZAP_URL only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"
BASH_BIN="$(command -v bash)"

# shellcheck source=tests/host-drivers/mock-cli.sh
. "$SCRIPT_DIR/host-drivers/mock-cli.sh"
set +e   # mock-cli.sh sets `set -euo pipefail`; drop errexit, keep -u -o pipefail
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — BL-070 snyk/zap scanners read prefs + count findings via jq."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

MOCK_DIR=""
ZAP_BIN=""

# ── Curated clean bin ────────────────────────────────────────────────
# Symlink only the coreutils the driver needs. Running the driver with PATH
# pointed here (+ the mock dir) guarantees NO host snyk / docker / semgrep /
# license tool is reachable — the sole hermeticity guarantee.
CLEAN_BIN="$(mktemp -d "${TMPDIR:-/tmp}/bl070sz-cleanbin-XXXXXX")"
_build_clean_bin() {
  local t p
  for t in bash sh env cat head tail sed grep egrep printf echo dirname basename \
           jq git date mkdir rmdir rm mv cp chmod ln sleep mktemp wc tr cut \
           sort uniq hostname whoami id test ls; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    [ -n "$p" ] && ln -sf "$p" "$CLEAN_BIN/$t" 2>/dev/null || true
  done
}
_build_clean_bin

# ── Shared teardown ──────────────────────────────────────────────────
teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
  [ -n "${MOCK_DIR:-}" ] && mock_cli_teardown "$MOCK_DIR" 2>/dev/null
  [ -n "${ZAP_BIN:-}" ] && rm -rf "$ZAP_BIN" 2>/dev/null
  MOCK_DIR=""; ZAP_BIN=""
  return 0
}

# ════════════════════════════════════════════════════════════════════
# SNYK fixtures
# ════════════════════════════════════════════════════════════════════
# setup_snyk — a project dir with .claude/tool-preferences.json and a fresh
# empty mock dir (tests add a mock `snyk` to it via mock_cli_respond).
setup_snyk() {
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/bl070sz-proj-XXXXXX")"
  PROJ="$TMP/p"
  RDIR="$PROJ/docs/test-results/phase3"
  mkdir -p "$PROJ/.claude" "$RDIR"
  printf '%s\n' '{"context":{"language":"typescript","platform":"web","track":"light","dev_os":"linux"}}' \
    > "$PROJ/.claude/tool-preferences.json"
  MOCK_DIR="$(mock_cli_setup)"
}

# run_snyk_driver [extra-args...] — run in $PROJ with PATH = mock:clean (docker
# is absent, so the ZAP arm always SKIPs and only snyk produces a real verdict).
run_snyk_driver() {
  ( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$RDIR" "$@" </dev/null 2>&1 ) || true
}
snyk_archive() { ls -1 "$RDIR"/snyk-*.json 2>/dev/null | sort | tail -1; }

SNYK_CLEAN='{"ok":true,"vulnerabilities":[],"dependencyCount":42}'
SNYK_VULN='{"ok":false,"vulnerabilities":[{"id":"SNYK-JS-LODASH-1","title":"Prototype Pollution","severity":"high"}],"dependencyCount":42}'

# ════════════════════════════════════════════════════════════════════
# ZAP fixtures
# ════════════════════════════════════════════════════════════════════
# make_mock_docker <dir> — write a `docker` stub into <dir> that parses
# `-v HOST:/zap/wrk` + `-J NAME`, writes $ZAP_MOCK_REPORT (when non-empty) to
# HOST/NAME, and exits $ZAP_MOCK_RC. This models zap-baseline.py's real behavior
# (report written to the bind-mounted /zap/wrk, exit code signalling alerts).
make_mock_docker() {
  local dir="$1"
  cat > "$dir/docker" <<'DOCKER_EOF'
#!/usr/bin/env bash
# Mock `docker` for BL-070 ZAP tests. NOT a real container runtime.
set -u
hostdir=""; report=""; prev=""
for a in "$@"; do
  case "$prev" in
    -v) hostdir="${a%%:*}" ;;
    -J) report="$a" ;;
  esac
  prev="$a"
done
if [ -n "${ZAP_MOCK_REPORT:-}" ] && [ -n "$hostdir" ] && [ -n "$report" ]; then
  printf '%s' "$ZAP_MOCK_REPORT" > "$hostdir/$report" 2>/dev/null || true
fi
exit "${ZAP_MOCK_RC:-0}"
DOCKER_EOF
  chmod +x "$dir/docker"
}

# setup_zap <platform> [with-docker] — a project dir bound to <platform>. When
# "with-docker" is passed, a mock `docker` lives in $ZAP_BIN; otherwise $ZAP_BIN
# is empty (docker absent).
setup_zap() {
  local platform="$1" with_docker="${2:-}"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/bl070sz-proj-XXXXXX")"
  PROJ="$TMP/p"
  RDIR="$PROJ/docs/test-results/phase3"
  mkdir -p "$PROJ/.claude" "$RDIR"
  printf '%s\n' "{\"context\":{\"language\":\"typescript\",\"platform\":\"$platform\",\"track\":\"light\",\"dev_os\":\"linux\"}}" \
    > "$PROJ/.claude/tool-preferences.json"
  ZAP_BIN="$(mktemp -d "${TMPDIR:-/tmp}/bl070sz-zapbin-XXXXXX")"
  [ "$with_docker" = "with-docker" ] && make_mock_docker "$ZAP_BIN"
}

# run_zap_driver <report> <rc> [extra-args...] — run in $PROJ with PATH =
# zapbin:clean. <report> is the JSON the mock docker writes (empty = write none);
# <rc> is the mock docker exit code. SOLO_ZAP_TARGET_URL is EXPORTED only when
# $ZAP_URL is non-empty (so the no-url case genuinely sees it unset). Conditional
# `export` inside the subshell — NOT a `${VAR:+NAME=val}` command-prefix, which
# bash treats as a command word (recognises assignment prefixes at parse time).
run_zap_driver() {
  local report="$1" mrc="$2"; shift 2
  (
    cd "$PROJ" || exit 1
    export PATH="$ZAP_BIN:$CLEAN_BIN"
    export ZAP_MOCK_REPORT="$report"
    export ZAP_MOCK_RC="$mrc"
    if [ -n "${ZAP_URL:-}" ]; then
      export SOLO_ZAP_TARGET_URL="$ZAP_URL"
    fi
    "$BASH_BIN" "$DRIVER" --results-dir "$RDIR" "$@" </dev/null 2>&1
  ) || true
}
zap_archive() { ls -1 "$RDIR"/zap-dast-*.json 2>/dev/null | sort | tail -1; }

ZAP_CLEAN='{"@version":"2.14.0","site":[{"@name":"http://app.local","alerts":[]}]}'
ZAP_ALERTS='{"@version":"2.14.0","site":[{"@name":"http://app.local","alerts":[{"name":"X-Frame-Options Header Not Set","riskcode":"2"},{"name":"CSP Header Not Set","riskcode":"2"}]}]}'
# BL-122 fixtures. ZAP rule 10049 (riskcode 0, Informational) fires under EVERY
# possible Cache-Control value, so an unfiltered count makes the gate
# unpassable for any web app — Informational/Low must NOT block; Medium+
# (riskcode >= 2) must. riskcode is a STRING in real ZAP JSON.
ZAP_INFO_LOW='{"@version":"2.14.0","site":[{"@name":"http://app.local","alerts":[{"name":"Storable and Cacheable Content","pluginid":"10049","riskcode":"0"},{"name":"Timestamp Disclosure","riskcode":"1"}]}]}'
ZAP_MIXED='{"@version":"2.14.0","site":[{"@name":"http://app.local","alerts":[{"name":"Storable and Cacheable Content","pluginid":"10049","riskcode":"0"},{"name":"CSP Header Not Set","riskcode":"2"}]}]}'
ZAP_MALFORMED='this is not json {'

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-snyk-auth-pass: authenticated + clean JSON → PASS + archive ==="
# ════════════════════════════════════════════════════════════════════
setup_snyk
mock_cli_respond snyk "config get api" 0 "0123456789abcdef-token"
mock_cli_respond snyk "test --json" 0 "$SNYK_CLEAN"
out="$(run_snyk_driver)"
arch="$(snyk_archive)"
if echo "$out" | grep -q "\[PASS\] snyk"; then
  pass "T-snyk-auth-pass: driver reports [PASS] snyk"
else
  fail_ "T-snyk-auth-pass" "expected [PASS] snyk; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if [ -n "$arch" ] && [ -s "$arch" ]; then
  pass "T-snyk-auth-pass: snyk report archived non-empty ($(basename "$arch"))"
else
  fail_ "T-snyk-auth-pass" "expected a non-empty snyk-*.json archive; found '$arch'"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-snyk-findings-report: exits 1 WITH a vuln report → FAIL (semgrep policy) ==="
# ════════════════════════════════════════════════════════════════════
# snyk exits 1 when vulnerabilities are found while STILL emitting a report. Per
# the semgrep policy this scanner mirrors, findings BLOCK → FAIL (not PASS).
setup_snyk
mock_cli_respond snyk "config get api" 0 "0123456789abcdef-token"
mock_cli_respond snyk "test --json" 1 "$SNYK_VULN"
out="$(run_snyk_driver)"
arch="$(snyk_archive)"
if echo "$out" | grep -q "\[FAIL\] snyk"; then
  pass "T-snyk-findings-report: vulnerabilities found → [FAIL] snyk"
else
  fail_ "T-snyk-findings-report" "expected [FAIL] snyk (findings block); out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if echo "$out" | grep -q "\[PASS\] snyk"; then
  fail_ "T-snyk-findings-report" "findings must NOT be reported as PASS (this is a security scanner, not an inventory)"
else
  pass "T-snyk-findings-report: findings are not downgraded to PASS"
fi
if [ -n "$arch" ] && [ -s "$arch" ]; then
  pass "T-snyk-findings-report: report archived despite rc=1 (report-produced)"
else
  fail_ "T-snyk-findings-report" "expected the vuln report to be archived; found '$arch'"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-snyk-unauth-skip: on PATH but no token → attestable SKIP naming 'snyk auth' ==="
# ════════════════════════════════════════════════════════════════════
# snyk IS on PATH (the stub exists) but `snyk config get api` returns empty and
# SNYK_TOKEN is unset → not authenticated → attestable SKIP.
setup_snyk
mock_cli_respond snyk "config get api" 0 ""
out="$(run_snyk_driver)"
if echo "$out" | grep -q "\[SKIP\] snyk"; then
  pass "T-snyk-unauth-skip: driver reports [SKIP] snyk"
else
  fail_ "T-snyk-unauth-skip" "expected [SKIP] snyk; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if echo "$out" | grep -qE "snyk auth"; then
  pass "T-snyk-unauth-skip: SKIP names 'snyk auth'"
else
  fail_ "T-snyk-unauth-skip" "expected the SKIP to name 'snyk auth'; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if echo "$out" | grep -q "UN-ATTESTED"; then
  pass "T-snyk-unauth-skip: the SKIP is attestable (un-attested → gate would block)"
else
  fail_ "T-snyk-unauth-skip" "expected the SKIP to be flagged UN-ATTESTED; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if [ -z "$(snyk_archive)" ]; then
  pass "T-snyk-unauth-skip: no archive written for a SKIP"
else
  fail_ "T-snyk-unauth-skip" "a SKIP must not archive a report"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-snyk-missing-skip: snyk not on PATH → attestable SKIP naming the install ==="
# ════════════════════════════════════════════════════════════════════
# No mock snyk is registered and the clean bin has none → command -v snyk fails.
setup_snyk
out="$(run_snyk_driver)"
if echo "$out" | grep -q "\[SKIP\] snyk"; then
  pass "T-snyk-missing-skip: driver reports [SKIP] snyk"
else
  fail_ "T-snyk-missing-skip" "expected [SKIP] snyk; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if echo "$out" | grep -qE "snyk not on PATH.*npm install -g snyk|npm install -g snyk"; then
  pass "T-snyk-missing-skip: SKIP names the install option (npm install -g snyk)"
else
  fail_ "T-snyk-missing-skip" "expected a 'not on PATH / install' note; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-snyk-crash-fail: nonzero rc + NO report → FAIL (not SKIP) ==="
# ════════════════════════════════════════════════════════════════════
# Authenticated, but `snyk test --json` exits 2 (execution error) with no output.
setup_snyk
mock_cli_respond snyk "config get api" 0 "0123456789abcdef-token"
mock_cli_respond snyk "test --json" 2 ""
out="$(run_snyk_driver)"
if echo "$out" | grep -q "\[FAIL\] snyk"; then
  pass "T-snyk-crash-fail: crash (rc=2, no report) → [FAIL] snyk"
else
  fail_ "T-snyk-crash-fail" "expected [FAIL] snyk; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if echo "$out" | grep -q "\[SKIP\] snyk"; then
  fail_ "T-snyk-crash-fail" "a crash must be FAIL, not a (attestable) SKIP"
else
  pass "T-snyk-crash-fail: a crash is NOT downgraded to SKIP"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-snyk-offline-skip: --offline → SKIP (tool never run) ==="
# ════════════════════════════════════════════════════════════════════
# The tool IS present + authenticated, but --offline must short-circuit to SKIP.
setup_snyk
mock_cli_respond snyk "config get api" 0 "0123456789abcdef-token"
mock_cli_respond snyk "test --json" 0 "$SNYK_CLEAN"
out="$(run_snyk_driver --offline)"
if echo "$out" | grep -q "\[SKIP\] snyk"; then
  pass "T-snyk-offline-skip: --offline yields [SKIP] snyk"
else
  fail_ "T-snyk-offline-skip" "expected [SKIP] snyk under --offline; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if echo "$out" | grep -qiE "offline"; then
  pass "T-snyk-offline-skip: note attributes the SKIP to offline mode"
else
  fail_ "T-snyk-offline-skip" "expected an 'offline' note; out:
$(echo "$out" | grep -iE 'snyk' | head)"
fi
if [ -z "$(snyk_archive)" ]; then
  pass "T-snyk-offline-skip: no archive written (tool not run)"
else
  fail_ "T-snyk-offline-skip" "offline SKIP must not run the tool / archive a report"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-web-pass: platform=web + docker + URL + clean report → PASS + archive ==="
# ════════════════════════════════════════════════════════════════════
setup_zap web with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_CLEAN" 0)"
arch="$(zap_archive)"
if echo "$out" | grep -q "\[PASS\] zap-dast"; then
  pass "T-zap-web-pass: driver reports [PASS] zap-dast"
else
  fail_ "T-zap-web-pass" "expected [PASS] zap-dast; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -n "$arch" ] && [ -s "$arch" ]; then
  pass "T-zap-web-pass: ZAP report archived non-empty ($(basename "$arch"))"
else
  fail_ "T-zap-web-pass" "expected a non-empty zap-dast-*.json archive; found '$arch'"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-api-pass: platform=api is DAST-eligible → PASS ==="
# ════════════════════════════════════════════════════════════════════
setup_zap api with-docker
ZAP_URL="http://api.local/health"
out="$(run_zap_driver "$ZAP_CLEAN" 0)"
if echo "$out" | grep -q "\[PASS\] zap-dast"; then
  pass "T-zap-api-pass: platform=api runs the DAST scan → [PASS] zap-dast"
else
  fail_ "T-zap-api-pass" "expected [PASS] zap-dast for platform=api; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-findings-fail: report WITH alerts (rc 2) → FAIL (semgrep policy) ==="
# ════════════════════════════════════════════════════════════════════
# zap-baseline exits 2 on WARN-level alerts while still writing a report. Per the
# semgrep policy this arm mirrors, alerts BLOCK → FAIL.
setup_zap web with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_ALERTS" 2)"
if echo "$out" | grep -q "\[FAIL\] zap-dast"; then
  pass "T-zap-findings-fail: alerts found → [FAIL] zap-dast"
else
  fail_ "T-zap-findings-fail" "expected [FAIL] zap-dast (alerts block); out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -q "\[PASS\] zap-dast"; then
  fail_ "T-zap-findings-fail" "alerts must NOT be reported as PASS"
else
  pass "T-zap-findings-fail: alerts are not downgraded to PASS"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-info-only-pass: ONLY Informational/Low alerts (rc 1) → PASS (BL-122) ==="
# ════════════════════════════════════════════════════════════════════
# Dogfood-2 F-DF2-012: rule 10049 (riskcode 0) fires under EVERY Cache-Control
# value, so counting it made zero-alerts unreachable and the DAST gate
# permanently blocked Phase 3→4 for every web project — and BL-113 (correctly)
# refuses to attest past a FAIL, so there was no legitimate escape. Policy now
# mirrors the semgrep arm's --severity=ERROR: Medium+ (riskcode >= 2) blocks;
# Informational/Low surface in the archived report but do not block.
setup_zap web with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_INFO_LOW" 1)"
if echo "$out" | grep -q "\[PASS\] zap-dast"; then
  pass "T-zap-info-only-pass: informational/low-only report passes"
else
  fail_ "T-zap-info-only-pass" "riskcode 0/1-only report must PASS (the unfiltered count made the gate unpassable for any web app); out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -q "\[FAIL\] zap-dast"; then
  fail_ "T-zap-info-only-pass" "informational/low alerts must not FAIL the gate"
else
  pass "T-zap-info-only-pass: no FAIL emitted for informational/low"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-mixed-risk-fail: riskcode 0 + riskcode 2 → FAIL counting ONLY the Medium+ (BL-122) ==="
# ════════════════════════════════════════════════════════════════════
setup_zap web with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_MIXED" 2)"
if echo "$out" | grep -q "\[FAIL\] zap-dast" && echo "$out" | grep -q "1 Medium+"; then
  pass "T-zap-mixed-risk-fail: Medium+ alert blocks, counted as exactly 1"
else
  fail_ "T-zap-mixed-risk-fail" "expected [FAIL] zap-dast with '1 Medium+' (the riskcode-0 alert must not inflate the count); out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-malformed-report-fail: unparseable report → FAIL naming the reason (BL-122) ==="
# ════════════════════════════════════════════════════════════════════
# A report nobody could read is NOT a pass (BL-112/BL-113 honesty class). With
# the rc arm no longer part of the verdict, an unparseable report must FAIL on
# its own — and say WHY, not masquerade as an alert count.
setup_zap web with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_MALFORMED" 1)"
if echo "$out" | grep -q "\[FAIL\] zap-dast" && echo "$out" | grep -qi "unparseable"; then
  pass "T-zap-malformed-report-fail: unparseable report fails loudly with the reason"
else
  fail_ "T-zap-malformed-report-fail" "expected [FAIL] zap-dast mentioning 'unparseable'; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-platform-skip: platform=desktop + docker + URL → attestable SKIP (gate first) ==="
# ════════════════════════════════════════════════════════════════════
# docker IS present and a URL IS set, yet the platform gate (checked FIRST) must
# SKIP for a non-web/api platform. The mock docker must therefore never run
# (no archive written).
setup_zap desktop with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_CLEAN" 0)"
if echo "$out" | grep -q "\[SKIP\] zap-dast"; then
  pass "T-zap-platform-skip: non-web/api platform → [SKIP] zap-dast"
else
  fail_ "T-zap-platform-skip" "expected [SKIP] zap-dast for platform=desktop; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -qiE "DAST not applicable to platform 'desktop'"; then
  pass "T-zap-platform-skip: SKIP note names the ineligible platform"
else
  fail_ "T-zap-platform-skip" "expected a 'DAST not applicable to platform desktop' note; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -q "UN-ATTESTED"; then
  pass "T-zap-platform-skip: the SKIP is attestable (never a silent auto-pass)"
else
  fail_ "T-zap-platform-skip" "expected the SKIP to be flagged UN-ATTESTED; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -z "$(zap_archive)" ]; then
  pass "T-zap-platform-skip: platform gate fires before docker (no archive written)"
else
  fail_ "T-zap-platform-skip" "docker must not run when the platform gate SKIPs"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-no-docker-skip: docker not on PATH → attestable SKIP ==="
# ════════════════════════════════════════════════════════════════════
# platform=web + URL set, but NO mock docker in $ZAP_BIN → command -v docker fails.
setup_zap web
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_CLEAN" 0)"
if echo "$out" | grep -q "\[SKIP\] zap-dast"; then
  pass "T-zap-no-docker-skip: driver reports [SKIP] zap-dast"
else
  fail_ "T-zap-no-docker-skip" "expected [SKIP] zap-dast; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -qiE "docker not on PATH"; then
  pass "T-zap-no-docker-skip: SKIP names the missing docker"
else
  fail_ "T-zap-no-docker-skip" "expected a 'docker not on PATH' note; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-no-url-skip: SOLO_ZAP_TARGET_URL unset → attestable SKIP naming it ==="
# ════════════════════════════════════════════════════════════════════
# platform=web + docker present, but no target URL → SKIP.
setup_zap web with-docker
ZAP_URL=""   # unset → run_zap_driver omits SOLO_ZAP_TARGET_URL
out="$(run_zap_driver "$ZAP_CLEAN" 0)"
if echo "$out" | grep -q "\[SKIP\] zap-dast"; then
  pass "T-zap-no-url-skip: driver reports [SKIP] zap-dast"
else
  fail_ "T-zap-no-url-skip" "expected [SKIP] zap-dast; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -q "SOLO_ZAP_TARGET_URL"; then
  pass "T-zap-no-url-skip: SKIP names SOLO_ZAP_TARGET_URL"
else
  fail_ "T-zap-no-url-skip" "expected the SKIP to name SOLO_ZAP_TARGET_URL; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -z "$(zap_archive)" ]; then
  pass "T-zap-no-url-skip: no archive written for a SKIP"
else
  fail_ "T-zap-no-url-skip" "a SKIP must not archive a report"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-offline-skip: --offline → SKIP ==="
# ════════════════════════════════════════════════════════════════════
# Everything present (web + docker + URL), but --offline must short-circuit.
setup_zap web with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "$ZAP_CLEAN" 0 --offline)"
if echo "$out" | grep -q "\[SKIP\] zap-dast"; then
  pass "T-zap-offline-skip: --offline yields [SKIP] zap-dast"
else
  fail_ "T-zap-offline-skip" "expected [SKIP] zap-dast under --offline; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -qiE "offline"; then
  pass "T-zap-offline-skip: note attributes the SKIP to offline mode"
else
  fail_ "T-zap-offline-skip" "expected an 'offline' note; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -z "$(zap_archive)" ]; then
  pass "T-zap-offline-skip: no archive written (scan not run)"
else
  fail_ "T-zap-offline-skip" "offline SKIP must not run the scan / archive a report"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-zap-crash-fail: docker runs but produces NO report (nonzero) → FAIL ==="
# ════════════════════════════════════════════════════════════════════
# The mock docker writes NO report (empty ZAP_MOCK_REPORT) and exits nonzero →
# no archive → FAIL (a crash, NOT a skip).
setup_zap web with-docker
ZAP_URL="http://app.local"
out="$(run_zap_driver "" 3)"
if echo "$out" | grep -q "\[FAIL\] zap-dast"; then
  pass "T-zap-crash-fail: no report + nonzero rc → [FAIL] zap-dast"
else
  fail_ "T-zap-crash-fail" "expected [FAIL] zap-dast; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -q "\[SKIP\] zap-dast"; then
  fail_ "T-zap-crash-fail" "a crash must be FAIL, not a (attestable) SKIP"
else
  pass "T-zap-crash-fail: a crash is NOT downgraded to SKIP"
fi
unset ZAP_URL
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation-snyk: excise # BL-070-SNYK-DISPATCH → auth-pass goes RED ==="
# ════════════════════════════════════════════════════════════════════
# Copy the driver, delete the line carrying `# BL-070-SNYK-DISPATCH` (the
# `snyk test --json` run line), re-run the auth-pass fixture. Real driver:
# [PASS] snyk. Mutant: the run is gone → empty archive → [FAIL] snyk, NO [PASS]
# — proving the marked dispatch is load-bearing (remove it → T-snyk-auth-pass RED).
setup_snyk
mock_cli_respond snyk "config get api" 0 "0123456789abcdef-token"
mock_cli_respond snyk "test --json" 0 "$SNYK_CLEAN"
MUT="$TMP/mut-driver.sh"
grep -v 'BL-070-SNYK-DISPATCH' "$DRIVER" > "$MUT"
chmod +x "$MUT"
if ! grep -q 'BL-070-SNYK-DISPATCH' "$DRIVER"; then
  fail_ "T-mutation-snyk" "BL-070-SNYK-DISPATCH marker missing from the REAL driver — nothing to mutate"
elif grep -q 'BL-070-SNYK-DISPATCH' "$MUT"; then
  fail_ "T-mutation-snyk" "marker still present after excision — mutation did not apply"
elif ! "$BASH_BIN" -n "$MUT" 2>/dev/null; then
  fail_ "T-mutation-snyk" "mutant driver is not syntactically valid after excision"
else
  mkdir -p "$TMP/real-rdir" "$TMP/mut-rdir"
  real_out="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$DRIVER" \
      --results-dir "$TMP/real-rdir" </dev/null 2>&1 )" || true
  mut_out="$( cd "$PROJ" && PATH="$MOCK_DIR:$CLEAN_BIN" "$BASH_BIN" "$MUT" \
      --results-dir "$TMP/mut-rdir" </dev/null 2>&1 )" || true
  if echo "$real_out" | grep -q "\[PASS\] snyk"; then
    pass "T-mutation-snyk: real driver emits [PASS] snyk"
  else
    fail_ "T-mutation-snyk" "real driver did NOT emit [PASS] snyk (fixture wrong?); out:
$(echo "$real_out" | grep -iE 'snyk' | head)"
  fi
  if echo "$mut_out" | grep -q "\[PASS\] snyk"; then
    fail_ "T-mutation-snyk" "mutant STILL emitted [PASS] snyk — dispatch not load-bearing (not a proof)"
  else
    pass "T-mutation-snyk: mutant (dispatch stripped) does NOT emit [PASS] snyk (RED proof)"
  fi
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation-zap: excise # BL-070-ZAP-DISPATCH → web-pass goes RED ==="
# ════════════════════════════════════════════════════════════════════
# Copy the driver, delete the line carrying `# BL-070-ZAP-DISPATCH` (the
# `docker run ... zap-baseline.py` line), re-run the web-pass fixture. Real
# driver: [PASS] zap-dast. Mutant: docker never runs → no report → [FAIL]
# zap-dast, NO [PASS] — proving the marked dispatch is load-bearing (remove it
# → T-zap-web-pass RED).
setup_zap web with-docker
ZAP_URL="http://app.local"
MUT="$TMP/mut-driver.sh"
grep -v 'BL-070-ZAP-DISPATCH' "$DRIVER" > "$MUT"
chmod +x "$MUT"
if ! grep -q 'BL-070-ZAP-DISPATCH' "$DRIVER"; then
  fail_ "T-mutation-zap" "BL-070-ZAP-DISPATCH marker missing from the REAL driver — nothing to mutate"
elif grep -q 'BL-070-ZAP-DISPATCH' "$MUT"; then
  fail_ "T-mutation-zap" "marker still present after excision — mutation did not apply"
elif ! "$BASH_BIN" -n "$MUT" 2>/dev/null; then
  fail_ "T-mutation-zap" "mutant driver is not syntactically valid after excision"
else
  mkdir -p "$TMP/real-rdir" "$TMP/mut-rdir"
  real_out="$( cd "$PROJ" && PATH="$ZAP_BIN:$CLEAN_BIN" \
      ZAP_MOCK_REPORT="$ZAP_CLEAN" ZAP_MOCK_RC=0 SOLO_ZAP_TARGET_URL="$ZAP_URL" \
      "$BASH_BIN" "$DRIVER" --results-dir "$TMP/real-rdir" </dev/null 2>&1 )" || true
  mut_out="$( cd "$PROJ" && PATH="$ZAP_BIN:$CLEAN_BIN" \
      ZAP_MOCK_REPORT="$ZAP_CLEAN" ZAP_MOCK_RC=0 SOLO_ZAP_TARGET_URL="$ZAP_URL" \
      "$BASH_BIN" "$MUT" --results-dir "$TMP/mut-rdir" </dev/null 2>&1 )" || true
  if echo "$real_out" | grep -q "\[PASS\] zap-dast"; then
    pass "T-mutation-zap: real driver emits [PASS] zap-dast"
  else
    fail_ "T-mutation-zap" "real driver did NOT emit [PASS] zap-dast (fixture wrong?); out:
$(echo "$real_out" | grep -iE 'zap' | head)"
  fi
  if echo "$mut_out" | grep -q "\[PASS\] zap-dast"; then
    fail_ "T-mutation-zap" "mutant STILL emitted [PASS] zap-dast — dispatch not load-bearing (not a proof)"
  else
    pass "T-mutation-zap: mutant (dispatch stripped) does NOT emit [PASS] zap-dast (RED proof)"
  fi
fi
unset ZAP_URL
teardown

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$CLEAN_BIN"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

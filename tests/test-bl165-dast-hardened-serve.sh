#!/usr/bin/env bash
# tests/test-bl165-dast-hardened-serve.sh
#
# BL-165 — Phase-3 DAST hardened-serve harness (scripts/run-phase3-validation.sh,
# `# BL-165-HARDENED-SERVE`). Dogfood-4 F-DF4-011/012: a static app's bare
# preview (dist/ over `vite preview`) cannot emit the deploy-boundary host
# headers (CSP, X-Frame-Options, …) documented in Project Bible section 11, so
# ZAP baseline (correctly, riskcode>=2) FAILs on every missing one — a
# genuinely clean app STRUCTURALLY FAILs DAST with no code change able to fix
# it. The S3 walker proved the same dist/ passes 0 Medium+ when re-served WITH
# the documented headers.
#
# THE HARNESS: when the project DECLARES its production header set in
# `.claude/dast-headers.json` (the canonical `.claude/*.json` machine-readable
# surface, read with the same jq the platform gate already uses), the arm
# applies those headers to the responses ZAP judges — via ZAP's own Replacer
# add-on, dropped in as a `--hook` inside the /zap/wrk bind — records the applied
# config as durable evidence next to the report, and judges THAT hardened result
# with the UNCHANGED BL-122 riskcode>=2 filter. No declaration → the raw-preview
# FAIL semantics are byte-for-byte unchanged (no hook, no evidence, no note
# suffix). The check is NOT globally blunted: only the DECLARED headers are
# applied, so any OTHER Medium+ alert still FAILs.
#
# CASES:
#   (a) T-declared-judges-hardened  DECLARES headers → [PASS] zap-dast (the two
#                                   missing host-header alerts are suppressed by
#                                   the declared set); the driver passes --hook,
#                                   writes the headers file into the bind, and
#                                   records a `*.hardened-serve.json` evidence
#                                   sidecar carrying the applied header config +
#                                   count; the note names the hardened serve.
#   (b1) T-nodecl-raw-fail-unchanged  NO declaration → the SAME headerless scan
#                                   still [FAIL]s (the walker's exact scenario);
#                                   NO sidecar, NO "hardened serve" in the note,
#                                   NO --hook passed to docker.
#   (b2) T-nodecl-clean-pass-unchanged  NO declaration + a genuinely clean scan
#                                   (0 Medium+) still [PASS]es (raw semantics
#                                   preserved in both directions).
#   (c1) T-hardened-genuine-medium-fail  DECLARES headers BUT a genuine Medium+
#                                   (riskcode 3) alert survives the hardening →
#                                   [FAIL] — the BL-122 judge still fires on the
#                                   hardened serve; it is not softened.
#   (c2) T-hardened-low-only-pass   DECLARES headers + only a Low (riskcode 1)
#                                   alert remains → [PASS] (Low-only still
#                                   passes, unchanged threshold).
#   (c3) T-hardened-workdir-in-project  even on the hardened path the -v bind
#                                   host dir lives under the PROJECT tree (BL-140
#                                   workdir invariant unaffected).
#   (e) T-mutation-hardened-serve   excise the `# BL-165-HARDENED-SERVE` fence →
#                                   case (a) flips [PASS]→[FAIL] and the evidence
#                                   sidecar disappears (RED proof the fence is
#                                   load-bearing).
#
# HERMETIC: the driver runs with PATH = <mock dir>:<curated clean bin> (no host
# docker/jq/semgrep can leak in). `docker` is a bespoke stub that models
# zap-baseline + Replacer by reading the headers file the DRIVER wrote into the
# bind mount and suppressing the corresponding missing-header alerts — so the
# test proves the real wiring, not a canned answer. NO real docker / ZAP /
# network / port is ever touched. bash-3.2 safe; no ((x++)); no real remotes; no
# init.sh invocation.

set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
unset SOLO_ZAP_TARGET_URL 2>/dev/null || true   # set per-test via $ZAP_URL only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"
BASH_BIN="$(command -v bash)"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — the BL-165 hardened-serve arm reads .claude/dast-headers.json + records evidence via jq."
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Curated clean bin (hermeticity: no host docker/jq/semgrep reachable) ──────
CLEAN_BIN="$(mktemp -d "${TMPDIR:-/tmp}/bl165-cleanbin-XXXXXX")"
_build_clean_bin() {
  local t p
  for t in bash sh env cat head tail sed grep egrep printf echo dirname basename \
           jq git date mkdir rmdir rm mv cp chmod ln sleep mktemp wc tr cut \
           sort uniq hostname whoami id test ls python3; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    [ -n "$p" ] && ln -sf "$p" "$CLEAN_BIN/$t" 2>/dev/null || true
  done
}
_build_clean_bin

# ── Mock docker: zap-baseline + Replacer model, driven by the DRIVER's output ─
# The bare static preview is missing CSP + X-Frame-Options (each a riskcode-2
# alert). A missing-header alert is SUPPRESSED iff the driver passed --hook AND
# wrote a bl165-headers.json into the -v bind that names that header (i.e. the
# Replacer really applied it). $ZAP_MOCK_EXTRA_ALERT (a full JSON alert object)
# is ALWAYS emitted — a genuine finding a hardened serve must not hide.
make_mock_docker() {
  local dir="$1"
  cat > "$dir/docker" <<'DOCKER_EOF'
#!/usr/bin/env bash
# Mock `docker` for BL-165 hardened-serve tests. NOT a real container runtime.
set -u
hostdir=""; report=""; prev=""; hook=""
for a in "$@"; do
  case "$prev" in
    -v) hostdir="${a%%:*}" ;;
    -J) report="$a" ;;
  esac
  case "$a" in --hook=*) hook="${a#--hook=}" ;; esac
  prev="$a"
done
[ -n "${ZAP_MOCK_HOSTDIR_WITNESS:-}" ] && printf '%s' "$hostdir" > "$ZAP_MOCK_HOSTDIR_WITNESS" 2>/dev/null || true
[ -n "${ZAP_MOCK_HOOK_WITNESS:-}" ]    && printf '%s' "$hook"    > "$ZAP_MOCK_HOOK_WITNESS"    2>/dev/null || true
# Copy the generated hook artifact OUT of the bind so the suite can py_compile +
# content-check it (the driver rm -rf's the workdir after the run). The
# reviewer's M4 (hook written to the wrong path) and M4b (hook body corrupted to
# invalid Python) are only caught when the suite actually observes this artifact.
if [ -n "${ZAP_MOCK_HOOK_COPY:-}" ] && [ -f "$hostdir/bl165-hook.py" ]; then
  cp "$hostdir/bl165-hook.py" "$ZAP_MOCK_HOOK_COPY" 2>/dev/null || true
fi

declared=""
# Suppression models ZAP+Replacer applying the declared headers. It requires the
# --hook argv AND the headers file AND the hook ARTIFACT actually present at the
# referenced /zap/wrk path — so M4 (hook at bl165-hook.py.DISABLED) yields no
# suppression, the missing-header alerts fire, and case (a) goes RED.
if [ -n "$hook" ] && [ -f "$hostdir/bl165-headers.json" ] && [ -f "$hostdir/bl165-hook.py" ]; then
  declared="$(cat "$hostdir/bl165-headers.json" 2>/dev/null || echo "")"
fi
_declared() { case "$declared" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

alerts=""; sep=""
if ! _declared 'Content-Security-Policy'; then
  alerts="${alerts}${sep}{\"name\":\"CSP Header Not Set\",\"riskcode\":\"2\"}"; sep=","
fi
if ! _declared 'X-Frame-Options'; then
  alerts="${alerts}${sep}{\"name\":\"X-Frame-Options Header Not Set\",\"riskcode\":\"2\"}"; sep=","
fi
if [ -n "${ZAP_MOCK_EXTRA_ALERT:-}" ]; then
  alerts="${alerts}${sep}${ZAP_MOCK_EXTRA_ALERT}"; sep=","
fi
if [ -n "$hostdir" ] && [ -n "$report" ]; then
  printf '{"@version":"2.14.0","site":[{"@name":"http://app.local","alerts":[%s]}]}' "$alerts" \
    > "$hostdir/$report" 2>/dev/null || true
fi
exit "${ZAP_MOCK_RC:-0}"
DOCKER_EOF
  chmod +x "$dir/docker"
}

# A realistic declared header set — CSP carries spaces AND single-quotes, which
# would break a naive `-z`-string mechanism: it survives here because the driver
# copies it with jq and the ZAP hook reads it as JSON (no shell splitting).
DECL_HEADERS='{"headers":{"Content-Security-Policy":"default-src '"'"'self'"'"'; frame-ancestors '"'"'none'"'"'; form-action '"'"'none'"'"'; base-uri '"'"'none'"'"'","X-Frame-Options":"DENY","X-Content-Type-Options":"nosniff","Strict-Transport-Security":"max-age=63072000; includeSubDomains","Referrer-Policy":"no-referrer"}}'

ZAP_BIN=""; TMP=""; PROJ=""; RDIR=""
# setup <declare|nodeclare>
setup() {
  local mode="$1"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/bl165-proj-XXXXXX")"
  PROJ="$TMP/p"
  RDIR="$PROJ/docs/test-results/phase3"
  mkdir -p "$PROJ/.claude" "$RDIR"
  printf '%s\n' '{"context":{"language":"typescript","platform":"web","track":"light","dev_os":"linux"}}' \
    > "$PROJ/.claude/tool-preferences.json"
  if [ "$mode" = "declare" ]; then
    printf '%s\n' "$DECL_HEADERS" > "$PROJ/.claude/dast-headers.json"
  fi
  ZAP_BIN="$(mktemp -d "${TMPDIR:-/tmp}/bl165-zapbin-XXXXXX")"
  make_mock_docker "$ZAP_BIN"
}
teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
  [ -n "${ZAP_BIN:-}" ] && rm -rf "$ZAP_BIN"
  TMP=""; ZAP_BIN=""
  return 0
}
sidecar() { ls -1 "$RDIR"/zap-dast-*.hardened-serve.json 2>/dev/null | sort | tail -1; }

# run_driver [DRIVER_PATH] — run the arm in $PROJ. Honors:
#   ZAP_URL (exported as SOLO_ZAP_TARGET_URL only when non-empty),
#   ZAP_MOCK_RC, ZAP_MOCK_EXTRA_ALERT, ZAP_MOCK_HOSTDIR_WITNESS.
run_driver() {
  local drv="${1:-$DRIVER}"
  (
    cd "$PROJ" || exit 1
    export PATH="$ZAP_BIN:$CLEAN_BIN"
    export ZAP_MOCK_RC="${ZAP_MOCK_RC:-0}"
    export ZAP_MOCK_EXTRA_ALERT="${ZAP_MOCK_EXTRA_ALERT:-}"
    [ -n "${ZAP_MOCK_HOSTDIR_WITNESS:-}" ] && export ZAP_MOCK_HOSTDIR_WITNESS
    [ -n "${ZAP_URL:-}" ] && export SOLO_ZAP_TARGET_URL="$ZAP_URL"
    "$BASH_BIN" "$drv" --results-dir "$RDIR" </dev/null 2>&1
  ) || true
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (a) T-declared-judges-hardened: declared headers → hardened PASS + evidence ==="
# ════════════════════════════════════════════════════════════════════
# Watched-RED against pre-fix code: only the bare preview is judged, so the two
# missing host-header alerts fire → 2 Medium+ → FAIL. Post-fix: --hook + the
# written headers file suppress both → 0 Medium+ → PASS, with a recorded sidecar.
setup declare
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_COPY="$TMP/hook-copy.py"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_COPY
if echo "$out" | grep -q "\[PASS\] zap-dast"; then
  pass "(a) declared clean-with-headers app → [PASS] zap-dast (hardened serve judged)"
else
  fail_ "(a)" "expected [PASS] zap-dast — the declared headers must suppress the missing-header alerts; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -qiE "hardened serve"; then
  pass "(a) the note names the hardened serve"
else
  fail_ "(a)" "expected the note to name the hardened serve; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
# R-263-3: the note must claim the headers were CONFIGURED (handed to Replacer),
# not "applied" (which the driver cannot prove) — an honesty fix.
if echo "$out" | grep -q "documented response header(s) configured"; then
  pass "(a) the engage note says headers were 'configured' (honest wording)"
else
  fail_ "(a)" "engage note must say 'configured', not 'applied'; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
# R-263-1: the generated ZAP hook artifact must ACTUALLY exist in the bind, be
# valid Python, and carry the Replacer logic — the reviewer's M4 (wrong path) /
# M4b (corrupt body) survived because the suite never observed the artifact.
if [ -f "$TMP/hook-copy.py" ]; then
  pass "(a) the ZAP hook artifact existed at /zap/wrk/bl165-hook.py at scan time (catches M4)"
else
  fail_ "(a)" "the driver passed --hook but no bl165-hook.py existed in the bind (M4: written to the wrong path)"
fi
if [ -f "$TMP/hook-copy.py" ] && python3 -m py_compile "$TMP/hook-copy.py" 2>/dev/null; then
  pass "(a) the generated hook is valid Python (py_compile — catches M4b)"
else
  fail_ "(a)" "the generated hook does not compile (M4b: corrupted hook body)"
fi
if [ -f "$TMP/hook-copy.py" ] && grep -q 'RESP_HEADER' "$TMP/hook-copy.py" && grep -q 'add_rule' "$TMP/hook-copy.py"; then
  pass "(a) the hook body carries the RESP_HEADER Replacer add_rule logic"
else
  fail_ "(a)" "the generated hook is missing the RESP_HEADER add_rule logic"
fi
sc="$(sidecar)"
if [ -n "$sc" ] && [ -s "$sc" ]; then
  pass "(a) evidence sidecar written ($(basename "$sc"))"
else
  fail_ "(a)" "expected a *.hardened-serve.json evidence sidecar in $RDIR; found '$sc'"
fi
if [ -n "$sc" ] && jq -e '.applied_headers["Content-Security-Policy"] and .header_count==5 and .mode=="hardened-serve"' "$sc" >/dev/null 2>&1; then
  pass "(a) sidecar records the applied header config (CSP present, count 5, mode=hardened-serve)"
else
  fail_ "(a)" "sidecar must record the applied headers + count; got:
$([ -n "$sc" ] && cat "$sc")"
fi
# R-263-5: exact equality — the sidecar's applied_headers must EQUAL the
# declaration's usable subset (all 5 valid non-empty strings here), not merely
# be truthy.
if [ -n "$sc" ] && jq -e --argjson decl "$DECL_HEADERS" '.applied_headers == $decl.headers' "$sc" >/dev/null 2>&1; then
  pass "(a) sidecar applied_headers EXACTLY equals the declared usable subset"
else
  fail_ "(a)" "sidecar applied_headers must equal the declared header set exactly; got: $([ -n "$sc" ] && jq -c '.applied_headers' "$sc")"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (b1) T-nodecl-raw-fail-unchanged: no declaration → same headerless FAIL, no evidence ==="
# ════════════════════════════════════════════════════════════════════
setup nodeclare
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_WITNESS="$TMP/hook.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_WITNESS
if echo "$out" | grep -q "\[FAIL\] zap-dast"; then
  pass "(b1) no declaration → the missing-header scan still [FAIL]s (raw semantics unchanged)"
else
  fail_ "(b1)" "expected [FAIL] zap-dast unchanged; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -q "2 Medium+"; then
  pass "(b1) both host-header alerts fire (2 Medium+), byte-for-byte the pre-harness verdict"
else
  fail_ "(b1)" "expected '2 Medium+' in the FAIL note; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -z "$(sidecar)" ]; then
  pass "(b1) no hardened-serve evidence sidecar for an undeclared project"
else
  fail_ "(b1)" "an undeclared project must not emit hardened-serve evidence"
fi
if echo "$out" | grep -qiE "hardened serve"; then
  fail_ "(b1)" "the note must NOT mention a hardened serve when nothing is declared"
else
  pass "(b1) the note carries no hardened-serve claim"
fi
if [ -z "$(cat "$TMP/hook.txt" 2>/dev/null || echo "")" ]; then
  pass "(b1) docker was invoked WITHOUT --hook (no hardening applied)"
else
  fail_ "(b1)" "docker must not receive --hook when nothing is declared (got '$(cat "$TMP/hook.txt")')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (b2) T-empty-decl-fails-closed: an empty {\"headers\":{}} declaration → raw FAIL, no hook ==="
# ════════════════════════════════════════════════════════════════════
# A degenerate declaration (present file, but zero headers) must NOT be mistaken
# for "harden with nothing → pass". The `_bl165_hcount -gt 0` guard fails closed
# to the raw path: the bare-preview missing-header scan still FAILs, no --hook is
# passed, and no evidence sidecar is written.
setup nodeclare
printf '%s\n' '{"headers":{}}' > "$PROJ/.claude/dast-headers.json"
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_WITNESS="$TMP/hook2.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_WITNESS
if echo "$out" | grep -q "\[FAIL\] zap-dast" && echo "$out" | grep -q "2 Medium+"; then
  pass "(b2) empty declaration falls back to the raw missing-header FAIL (fail-closed)"
else
  fail_ "(b2)" "expected the unchanged raw [FAIL] with '2 Medium+' for an empty declaration; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -z "$(cat "$TMP/hook2.txt" 2>/dev/null || echo "")" ] && [ -z "$(sidecar)" ]; then
  pass "(b2) empty declaration applies no hook and records no evidence"
else
  fail_ "(b2)" "an empty declaration must not hook or record evidence (hook='$(cat "$TMP/hook2.txt" 2>/dev/null)', sidecar='$(sidecar)')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (c1) T-hardened-genuine-medium-fail: declared, but a real Medium+ survives → FAIL ==="
# ════════════════════════════════════════════════════════════════════
# The two host-header alerts are suppressed by the declaration, but a GENUINE
# riskcode-3 finding (e.g. reflected XSS) is emitted → the BL-122 judge still
# fires on the hardened serve. The hardening must not soften the threshold.
setup declare
ZAP_URL="http://app.local"
ZAP_MOCK_EXTRA_ALERT='{"name":"Cross Site Scripting (Reflected)","riskcode":"3"}'
out="$(run_driver)"
if echo "$out" | grep -q "\[FAIL\] zap-dast" && echo "$out" | grep -q "1 Medium+"; then
  pass "(c1) a genuine Medium+ survives hardening → [FAIL] with exactly 1 Medium+ (judge unchanged)"
else
  fail_ "(c1)" "expected [FAIL] zap-dast with '1 Medium+' on the hardened serve; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -qiE "hardened serve"; then
  pass "(c1) even the FAIL note records that the serve was hardened (honest evidence)"
else
  fail_ "(c1)" "the hardened-serve FAIL note should still name the hardening; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (c2) T-hardened-low-only-pass: declared + only a Low remains → PASS ==="
# ════════════════════════════════════════════════════════════════════
setup declare
ZAP_URL="http://app.local"
ZAP_MOCK_EXTRA_ALERT='{"name":"Timestamp Disclosure","riskcode":"1"}'
out="$(run_driver)"
if echo "$out" | grep -q "\[PASS\] zap-dast"; then
  pass "(c2) hardened serve with only a Low (riskcode 1) alert → [PASS] (threshold unchanged)"
else
  fail_ "(c2)" "expected [PASS] zap-dast (Low-only must not block); out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (c3) T-hardened-workdir-in-project: -v bind host dir under the project (BL-140) ==="
# ════════════════════════════════════════════════════════════════════
setup declare
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOSTDIR_WITNESS="$TMP/hostdir.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOSTDIR_WITNESS
wit="$(cat "$TMP/hostdir.txt" 2>/dev/null || echo "")"
case "$wit" in
  "$PROJ"/*)
    pass "(c3) hardened path keeps the -v host dir under the project tree ('$wit')" ;;
  *)
    fail_ "(c3)" "hardened path moved the -v host dir off the project tree ('$wit') — BL-140 workdir invariant broken" ;;
esac
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (f) T-present-invalid-json: present but unparseable → raw + VISIBLE note, no engage ==="
# ════════════════════════════════════════════════════════════════════
# A declaration file that is PRESENT but invalid JSON must not fall back
# SILENTLY: the raw-path verdict must say hardening was not applied, and nothing
# is hooked or recorded. (Verifier Finding 1.)
setup nodeclare
printf '%s\n' 'this is not json {' > "$PROJ/.claude/dast-headers.json"
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_WITNESS="$TMP/hookf.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_WITNESS
if echo "$out" | grep -q "\[FAIL\] zap-dast" && echo "$out" | grep -q "2 Medium+"; then
  pass "(f) unparseable declaration → the raw missing-header FAIL is unchanged"
else
  fail_ "(f)" "expected the raw [FAIL] with 2 Medium+; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -qi "hardening NOT applied"; then
  pass "(f) the raw-path note VISIBLY states hardening was not applied"
else
  fail_ "(f)" "a present-but-unparseable declaration must produce a visible 'hardening NOT applied' note; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -z "$(cat "$TMP/hookf.txt" 2>/dev/null || echo "")" ] && [ -z "$(sidecar)" ]; then
  pass "(f) no hook and no evidence for an unparseable declaration"
else
  fail_ "(f)" "an unparseable declaration must not hook or record evidence"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (g) T-nonobject-headers: {\"headers\":\"foo\"} → not engaged + VISIBLE note ==="
# ════════════════════════════════════════════════════════════════════
# A non-object `.headers` must not engage: its string length must never be
# mistaken for a header count. (Verifier Findings 2/3.)
setup nodeclare
printf '%s\n' '{"headers":"foo"}' > "$PROJ/.claude/dast-headers.json"
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_WITNESS="$TMP/hookg.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_WITNESS
if echo "$out" | grep -q "\[FAIL\] zap-dast" && echo "$out" | grep -q "2 Medium+"; then
  pass "(g) non-object .headers → raw missing-header FAIL"
else
  fail_ "(g)" "expected raw [FAIL] with 2 Medium+; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if [ -z "$(cat "$TMP/hookg.txt" 2>/dev/null || echo "")" ] && [ -z "$(sidecar)" ]; then
  pass "(g) a string-valued .headers does not engage (no hook, no evidence)"
else
  fail_ "(g)" "a non-object .headers must not engage — string length must not be read as a header count"
fi
if echo "$out" | grep -qi "hardening NOT applied"; then
  pass "(g) the note visibly states hardening was not applied"
else
  fail_ "(g)" "expected a visible 'hardening NOT applied' note; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
if echo "$out" | grep -qi "hardened serve"; then
  fail_ "(g)" "must NOT claim a hardened serve for a non-object declaration"
else
  pass "(g) no false hardened-serve claim"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (h) T-shape-filter: mixed valid/number/empty → engages count=1, sidecar only the valid header ==="
# ════════════════════════════════════════════════════════════════════
# One valid non-empty string header + one number-valued + one empty-string:
# only the valid one counts and is recorded (an empty-string value would make
# real Replacer REMOVE the header, so it must never count as "applied").
# (Verifier Findings 2/3.)
setup nodeclare
printf '%s\n' '{"headers":{"Content-Security-Policy":"default-src '"'"'self'"'"'","X-Frame-Options":123,"Referrer-Policy":""}}' \
  > "$PROJ/.claude/dast-headers.json"
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_WITNESS="$TMP/hookh.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_WITNESS
sc="$(sidecar)"
if [ -n "$(cat "$TMP/hookh.txt" 2>/dev/null || echo "")" ] && [ -n "$sc" ]; then
  pass "(h) the one valid string header engages the hardened serve (hook + evidence)"
else
  fail_ "(h)" "a declaration with one valid header must engage; hook='$(cat "$TMP/hookh.txt" 2>/dev/null)' sidecar='$sc'"
fi
if [ -n "$sc" ] && jq -e '.header_count==1 and ((.applied_headers|keys)==["Content-Security-Policy"])' "$sc" >/dev/null 2>&1; then
  pass "(h) sidecar records EXACTLY the one valid header (count 1, CSP only — number/empty dropped)"
else
  fail_ "(h)" "sidecar must record only the non-empty string header; got:
$([ -n "$sc" ] && cat "$sc")"
fi
if echo "$out" | grep -q "1 documented"; then
  pass "(h) the note reports the shape-filtered count of 1"
else
  fail_ "(h)" "expected the note to report '1 documented' header; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (i) T-empty-name: empty header NAME is filtered (does not engage / is not counted) ==="
# ════════════════════════════════════════════════════════════════════
# An empty header NAME is not a header. {"headers":{"":"v"}} must NOT engage (no
# valid replacer target); a mix of an empty-name entry and one valid header
# engages with only the valid one. (Reviewer R-263-2.)
setup nodeclare
printf '%s\n' '{"headers":{"":"some-value"}}' > "$PROJ/.claude/dast-headers.json"
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_WITNESS="$TMP/hooki.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_WITNESS
if [ -z "$(cat "$TMP/hooki.txt" 2>/dev/null || echo "")" ] && [ -z "$(sidecar)" ]; then
  pass "(i-a) an empty-name-only declaration does NOT engage (no hook, no evidence)"
else
  fail_ "(i-a)" "an empty header name must be filtered — it is not a valid replacer target; hook='$(cat "$TMP/hooki.txt" 2>/dev/null)' sidecar='$(sidecar)'"
fi
if echo "$out" | grep -qi "hardening NOT applied"; then
  pass "(i-a) the visibility note fires for an all-empty-name declaration"
else
  fail_ "(i-a)" "expected the 'hardening NOT applied' visibility note; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
teardown

setup nodeclare
printf '%s\n' '{"headers":{"":"junk","Content-Security-Policy":"default-src '"'"'self'"'"'"}}' \
  > "$PROJ/.claude/dast-headers.json"
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
export ZAP_MOCK_HOOK_WITNESS="$TMP/hooki2.txt"
out="$(run_driver)"
unset ZAP_MOCK_HOOK_WITNESS
sc="$(sidecar)"
if [ -n "$(cat "$TMP/hooki2.txt" 2>/dev/null || echo "")" ] && [ -n "$sc" ]; then
  pass "(i-b) empty-name + one valid header engages (on the valid header)"
else
  fail_ "(i-b)" "a mix with one valid header must engage; hook='$(cat "$TMP/hooki2.txt" 2>/dev/null)' sidecar='$sc'"
fi
if [ -n "$sc" ] && jq -e '.header_count==1 and ((.applied_headers|keys)==["Content-Security-Policy"])' "$sc" >/dev/null 2>&1; then
  pass "(i-b) sidecar records EXACTLY the one valid header (empty name dropped, count 1)"
else
  fail_ "(i-b)" "sidecar must drop the empty-name entry and record only CSP; got:
$([ -n "$sc" ] && cat "$sc")"
fi
if echo "$out" | grep -q "1 documented"; then
  pass "(i-b) the note reports the shape-filtered count of 1"
else
  fail_ "(i-b)" "expected the note to report '1 documented' header; out:
$(echo "$out" | grep -iE 'zap' | head)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (e) T-mutation-hardened-serve: excise the fence → case (a) goes RED ==="
# ════════════════════════════════════════════════════════════════════
# Delete the # BL-165-HARDENED-SERVE-BEGIN..END block from a driver copy. The
# dispatch line's ${_bl165_hook_args[@]+…} stays runtime-safe (unset array,
# `+`-guarded), so the mutant runs but passes NO --hook → the bare preview is
# judged → case (a) flips [PASS]→[FAIL] and the evidence sidecar disappears.
setup declare
ZAP_URL="http://app.local"; ZAP_MOCK_EXTRA_ALERT=""
MUT="$TMP/driver-mut.sh"
sed '/# BL-165-HARDENED-SERVE-BEGIN/,/# BL-165-HARDENED-SERVE-END/d' "$DRIVER" > "$MUT"
chmod +x "$MUT"
if ! grep -q 'BL-165-HARDENED-SERVE-BEGIN' "$DRIVER"; then
  fail_ "(e)" "BL-165-HARDENED-SERVE fence missing from the REAL driver — nothing to mutate"
elif grep -qE 'BL-165-HARDENED-SERVE-(BEGIN|END)' "$MUT"; then
  # Only the FENCE markers must be gone; the marker string may legitimately
  # survive in out-of-fence doc cross-references (the citation convention).
  fail_ "(e)" "fence still present after excision — mutation did not apply"
elif ! "$BASH_BIN" -n "$MUT" 2>/dev/null; then
  fail_ "(e)" "mutant driver is not syntactically valid after excision"
else
  RDIR_REAL="$PROJ/docs/test-results/real"; mkdir -p "$RDIR_REAL"
  RDIR_MUT="$PROJ/docs/test-results/mut";  mkdir -p "$RDIR_MUT"
  real_out="$( cd "$PROJ" && PATH="$ZAP_BIN:$CLEAN_BIN" ZAP_MOCK_RC=0 SOLO_ZAP_TARGET_URL="$ZAP_URL" \
      "$BASH_BIN" "$DRIVER" --results-dir "$RDIR_REAL" </dev/null 2>&1 )" || true
  mut_out="$( cd "$PROJ" && PATH="$ZAP_BIN:$CLEAN_BIN" ZAP_MOCK_RC=0 SOLO_ZAP_TARGET_URL="$ZAP_URL" \
      "$BASH_BIN" "$MUT" --results-dir "$RDIR_MUT" </dev/null 2>&1 )" || true
  if echo "$real_out" | grep -q "\[PASS\] zap-dast"; then
    pass "(e) real driver emits [PASS] zap-dast (hardened)"
  else
    fail_ "(e)" "real driver did NOT emit [PASS] zap-dast (fixture wrong?); out:
$(echo "$real_out" | grep -iE 'zap' | head)"
  fi
  if echo "$mut_out" | grep -q "\[PASS\] zap-dast"; then
    fail_ "(e)" "mutant STILL emitted [PASS] zap-dast — the fence is not load-bearing (not a proof)"
  else
    pass "(e) mutant (fence excised) does NOT emit [PASS] zap-dast — RED proof"
  fi
  if [ -n "$(ls -1 "$RDIR_MUT"/zap-dast-*.hardened-serve.json 2>/dev/null)" ]; then
    fail_ "(e)" "mutant STILL wrote hardened-serve evidence — the fence is not load-bearing"
  else
    pass "(e) mutant wrote NO hardened-serve evidence (feature gone with the fence)"
  fi
fi
teardown

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$CLEAN_BIN"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

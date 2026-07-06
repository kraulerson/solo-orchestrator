#!/usr/bin/env bash
# tests/test-bl069-install-cmds-consumers.sh
#
# BL-069: prove the install-command CONSUMERS honor the resolver's
# structured `install_cmds` array (BL-033/PR #136 shipped the schema;
# the array was emitted but read by no consumer). Three readers were
# migrated to iterate stages with per-stage fail-fast + diagnosis,
# falling back to the legacy singular `install_cmd` only when the array
# is absent:
#
#   1. scripts/lib/helpers-core.sh  — run_install_stages + prompt_install
#   2. scripts/verify-install.sh    — fix_tool_install (two-layer dispatch)
#   3. scripts/upgrade-project.sh   — track-upgrade tool-install loop
#
# The upgrade-project reader DELEGATES to run_install_stages (Group B)
# and uses the IDENTICAL jq stages-extraction as fix_tool_install
# (Group C + Group D), so its behavior is covered transitively — the
# same-filter extraction is asserted directly, and the shared runner's
# iteration is mutation-proven.
#
# PER-STAGE CONTRACT (the point of the array shape):
#   • stage-1 fails  -> stage-2 MUST NOT run (fail-fast).
#   • stage-2 fails  -> stage-1's side effects MUST remain observable
#                       (a repair re-run resumes mid-sequence).
#
# MUTATION EVIDENCE (required by BL-069): a reader that used only
#   install_cmds[0] (ignoring later stages) MUST flip a test RED.
#   • Group B  T-runner-happy-multi : asserts BOTH stage side effects —
#     a runner that ran only stage[0] leaves stage-2's file missing -> RED.
#   • Group C  T-extract-prefers-array : the shared extraction yields the
#     FULL array, not [0]; a `.install_cmds[0]` mutation -> length 1 -> RED.
#   • Group D  T-vi-multi-both : fix_tool_install dispatches BOTH stages;
#     a `.install_cmds[0]`/`.[]`->`.[0]` mutation logs only stage 1 -> RED.
#
# Test harness conventions mirror tests/test-bl033-install-cmds-shape.sh
# and tests/test-verify-install-fix-functions.sh: self-contained, each
# scenario isolated in its own tmpdir, PASS/FAIL counters + exit status.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPERS_CORE="$REPO_ROOT/scripts/lib/helpers-core.sh"
VERIFY_INSTALL="$REPO_ROOT/scripts/verify-install.sh"
COMMON_JSON="$REPO_ROOT/templates/tool-matrix/common.json"
WEB_JSON="$REPO_ROOT/templates/tool-matrix/web.json"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Source helpers-core in THIS shell so run_install_stages / prompt_install
# / _soif_split_on_and are callable directly. Silence LOG_FILE side
# effects by leaving it empty (helpers-core makes log_line a no-op then).
# shellcheck source=/dev/null
source "$HELPERS_CORE"

# ============================================================
# GROUP A — _soif_split_on_and: recover stages from a ` && `-joined
# string (the resolver's legacy singular form of an install_cmds array).
# ============================================================
echo "GROUP A: _soif_split_on_and"

echo "T-split-single: a single command (no ' && ') is one stage"
_soif_split_on_and "brew install jq"
if [ "${#SOIF_INSTALL_STAGES[@]}" -eq 1 ] && [ "${SOIF_INSTALL_STAGES[0]}" = "brew install jq" ]; then
  pass "T-split-single: single-command string -> 1 stage, unchanged"
else
  fail_ "T-split-single" "got ${#SOIF_INSTALL_STAGES[@]} stage(s): ${SOIF_INSTALL_STAGES[*]}"
fi

echo "T-split-multi: 'a && b && c' splits into exactly 3 ordered stages"
_soif_split_on_and "cmd one && cmd two && cmd three"
if [ "${#SOIF_INSTALL_STAGES[@]}" -eq 3 ] \
   && [ "${SOIF_INSTALL_STAGES[0]}" = "cmd one" ] \
   && [ "${SOIF_INSTALL_STAGES[1]}" = "cmd two" ] \
   && [ "${SOIF_INSTALL_STAGES[2]}" = "cmd three" ]; then
  pass "T-split-multi: 3 stages recovered in order"
else
  fail_ "T-split-multi" "got ${#SOIF_INSTALL_STAGES[@]} stage(s): ${SOIF_INSTALL_STAGES[*]}"
fi

echo "T-split-preserves-internal: pipes/quotes inside a stage are preserved"
_soif_split_on_and 'GITLEAKS_VERSION=$(curl x | jq -r .tag) && curl "y" | sudo tar -xz'
if [ "${#SOIF_INSTALL_STAGES[@]}" -eq 2 ] \
   && [ "${SOIF_INSTALL_STAGES[0]}" = 'GITLEAKS_VERSION=$(curl x | jq -r .tag)' ] \
   && [ "${SOIF_INSTALL_STAGES[1]}" = 'curl "y" | sudo tar -xz' ]; then
  pass "T-split-preserves-internal: pipes/quotes kept within their stage"
else
  fail_ "T-split-preserves-internal" "got ${#SOIF_INSTALL_STAGES[@]}: ${SOIF_INSTALL_STAGES[*]}"
fi

# ============================================================
# GROUP B — run_install_stages: the shared eval-path runner used by
# prompt_install (and, transitively, upgrade-project). This is the
# MUTATION ANCHOR for "iterate all stages".
# ============================================================
echo ""
echo "GROUP B: run_install_stages (per-stage fail-fast + resumability)"

echo "T-runner-happy-multi: BOTH stages run -> both side effects observable [MUTATION ANCHOR]"
T=$(mktemp -d)
run_install_stages "demo" "touch $T/s1" "touch $T/s2" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -e "$T/s1" ] && [ -e "$T/s2" ]; then
  pass "T-runner-happy-multi: stage1 AND stage2 executed (rc=0)"
else
  fail_ "T-runner-happy-multi" "rc=$rc s1=$([ -e "$T/s1" ] && echo y || echo n) s2=$([ -e "$T/s2" ] && echo y || echo n) — a runner that ran only stage[0] fails HERE"
fi
rm -rf "$T"

echo "T-runner-failfast: stage-1 fails -> stage-2 MUST NOT run"
T=$(mktemp -d)
run_install_stages "demo" "false" "touch $T/should_not_exist" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$T/should_not_exist" ]; then
  pass "T-runner-failfast: stage-1 failure halted the sequence (rc=$rc, stage-2 skipped)"
else
  fail_ "T-runner-failfast" "rc=$rc stage2_ran=$([ -e "$T/should_not_exist" ] && echo YES || echo no)"
fi
rm -rf "$T"

echo "T-runner-stage2-fail-resumable: stage-2 fails -> stage-1 side effect remains"
T=$(mktemp -d)
run_install_stages "demo" "touch $T/s1_kept" "false" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ -e "$T/s1_kept" ]; then
  pass "T-runner-stage2-fail-resumable: stage-1 effect persists for a repair re-run (rc=$rc)"
else
  fail_ "T-runner-stage2-fail-resumable" "rc=$rc s1_kept=$([ -e "$T/s1_kept" ] && echo y || echo MISSING)"
fi
rm -rf "$T"

echo "T-runner-single-backcompat: a single stage runs as before (identical behavior)"
T=$(mktemp -d)
run_install_stages "demo" "touch $T/only" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -e "$T/only" ]; then
  pass "T-runner-single-backcompat: 1-stage path unchanged (rc=0)"
else
  fail_ "T-runner-single-backcompat" "rc=$rc only=$([ -e "$T/only" ] && echo y || echo n)"
fi
rm -rf "$T"

echo "T-runner-crossstage-var: a var set in stage-1 is visible in stage-2 (gitleaks pattern)"
T=$(mktemp -d)
run_install_stages "demo" "MYVER=8.28.0" "echo \"\$MYVER\" > \"$T/ver\"" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$T/ver" ] && [ "$(cat "$T/ver")" = "8.28.0" ]; then
  pass "T-runner-crossstage-var: shared-scope eval carries VAR across stages"
else
  fail_ "T-runner-crossstage-var" "rc=$rc content='$([ -f "$T/ver" ] && cat "$T/ver")'"
fi
rm -rf "$T"

# ============================================================
# GROUP C — shared stages-extraction contract. Both readers
# (fix_tool_install + upgrade-project) extract stages from resolver
# output with this exact jq: prefer install_cmds when it's a non-empty
# array; else fall back to [install_cmd]. This is where a
# `.install_cmds[0]` mutation would collapse the array to one stage.
# ============================================================
echo ""
echo "GROUP C: shared stages-extraction (prefer install_cmds, fall back to [install_cmd])"

_extract_stages() {
  # Mirrors the reader extraction in verify-install.sh:fix_tool_install
  # and upgrade-project.sh (BL-069). $1 = resolver-shaped JSON, index 0.
  echo "$1" | jq -c --argjson i 0 '
    .auto_install[$i] as $t
    | (if ($t.install_cmds | type) == "array" and ($t.install_cmds | length) > 0
       then $t.install_cmds else [$t.install_cmd] end)
    | map(select(. != null and . != ""))
  '
}

echo "T-extract-prefers-array: a 2-stage install_cmds yields 2 stages, NOT [install_cmd] [MUTATION ANCHOR]"
PAYLOAD='{"auto_install":[{"name":"x","install_cmd":"a && b","install_cmds":["a","b"]}]}'
got=$(_extract_stages "$PAYLOAD")
len=$(echo "$got" | jq 'length')
if [ "$len" = "2" ] && [ "$(echo "$got" | jq -r '.[0]')" = "a" ] && [ "$(echo "$got" | jq -r '.[1]')" = "b" ]; then
  pass "T-extract-prefers-array: extraction returns the full 2-element array"
else
  fail_ "T-extract-prefers-array" "len=$len got=$got — a '.install_cmds[0]' mutation fails HERE"
fi

echo "T-extract-legacy-fallback: absent install_cmds falls back to [install_cmd]"
PAYLOAD='{"auto_install":[{"name":"x","install_cmd":"brew install legacy"}]}'
got=$(_extract_stages "$PAYLOAD")
if [ "$(echo "$got" | jq 'length')" = "1" ] && [ "$(echo "$got" | jq -r '.[0]')" = "brew install legacy" ]; then
  pass "T-extract-legacy-fallback: legacy singular string preserved as 1 stage"
else
  fail_ "T-extract-legacy-fallback" "got=$got"
fi

echo "T-extract-empty-array-fallback: empty install_cmds falls back to [install_cmd]"
PAYLOAD='{"auto_install":[{"name":"x","install_cmd":"brew install legacy2","install_cmds":[]}]}'
got=$(_extract_stages "$PAYLOAD")
if [ "$(echo "$got" | jq 'length')" = "1" ] && [ "$(echo "$got" | jq -r '.[0]')" = "brew install legacy2" ]; then
  pass "T-extract-empty-array-fallback: empty array -> legacy fallback"
else
  fail_ "T-extract-empty-array-fallback" "got=$got"
fi

# ============================================================
# GROUP D — verify-install.sh fix_tool_install: the REAL reader, driven
# through its two-layer structured-dispatch pipeline with a PATH-isolated
# `brew` shim that LOGS every invocation (so we can observe which stages
# actually dispatched). Extractor mirrors
# tests/test-verify-install-fix-functions.sh (Pass-1 anchor).
# ============================================================
echo ""
echo "GROUP D: verify-install fix_tool_install (structured multi-stage dispatch)"

# Extract the allowlist + dispatch helpers + _tool_install_dispatch_one
# + fix_tool_install body and run fix_tool_install 0 against a payload.
# env vars PATH + BREW_LOG are inherited into the bash -c subshell (and
# thence the brew shim) from the caller's environment.
_run_fix_tool_install() {
  local payload="$1"
  local extract; extract=$(mktemp)
  awk '
    /^_TOOL_INSTALL_ALLOWED_HEADS=\(/ {flag=1}
    flag {print}
    flag && /^fix_tool_install\(\) \{/ {f=1}
    f && /^\}$/ {print "# end-of-block"; flag=0; f=0; exit}
  ' "$VERIFY_INSTALL" > "$extract"
  env _PAYLOAD="$payload" _EXTRACT="$extract" bash -c '
    set +e
    print_info() { echo "[INFO] $*" >&2; }
    print_warn() { echo "[WARN] $*" >&2; }
    print_fail() { echo "[FAIL] $*" >&2; }
    print_ok()   { echo "[OK] $*" >&2; }
    print_step() { echo "[STEP] $*" >&2; }
    source "$_EXTRACT"
    RESOLVER_OUTPUT="$_PAYLOAD"
    fix_tool_install 0
    echo "RC=$?" >&2
  ' 2>&1
  rm -f "$extract"
}

# Build a brew shim that records each call and fails on a sentinel pkg.
_make_brew_shim() {
  local dir; dir=$(mktemp -d)
  cat > "$dir/brew" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$BREW_LOG"
case "$*" in
  *FAILNOW*) exit 7 ;;
esac
exit 0
SHIM
  chmod +x "$dir/brew"
  echo "$dir"
}

echo "T-vi-multi-both: install_cmds=[stage1,stage2] dispatches BOTH stages [MUTATION ANCHOR]"
SHIM=$(_make_brew_shim); LOG=$(mktemp)
PAYLOAD=$(jq -n '{auto_install:[{name:"multi",category:"x",
  install_cmd:"brew install pkgone && brew install pkgtwo",
  install_cmds:["brew install pkgone","brew install pkgtwo"],
  required:false, description:"x"}], already_installed:[], manual_install:[], deferred:[]}')
out=$(PATH="$SHIM:$PATH" BREW_LOG="$LOG" _run_fix_tool_install "$PAYLOAD")
if grep -q "install -- pkgone" "$LOG" && grep -q "install -- pkgtwo" "$LOG"; then
  pass "T-vi-multi-both: both stages reached the brew dispatch (log: $(tr '\n' ';' < "$LOG"))"
else
  fail_ "T-vi-multi-both" "log did not contain both stages: $(tr '\n' ';' < "$LOG") | out=$out — a reader using only install_cmds[0] fails HERE"
fi
rm -rf "$SHIM"; rm -f "$LOG"

echo "T-vi-failfast: stage-1 fails -> stage-2 MUST NOT dispatch"
SHIM=$(_make_brew_shim); LOG=$(mktemp)
PAYLOAD=$(jq -n '{auto_install:[{name:"ff",category:"x",
  install_cmd:"brew install FAILNOW && brew install pkgtwo",
  install_cmds:["brew install FAILNOW","brew install pkgtwo"],
  required:false, description:"x"}], already_installed:[], manual_install:[], deferred:[]}')
out=$(PATH="$SHIM:$PATH" BREW_LOG="$LOG" _run_fix_tool_install "$PAYLOAD")
if grep -q "install -- FAILNOW" "$LOG" && ! grep -q "install -- pkgtwo" "$LOG" && echo "$out" | grep -q "RC=7"; then
  pass "T-vi-failfast: stage-1 failure halted dispatch (rc=7, stage-2 never ran)"
else
  fail_ "T-vi-failfast" "log=$(tr '\n' ';' < "$LOG") out=$out (expected FAILNOW logged, pkgtwo NOT logged, RC=7)"
fi
rm -rf "$SHIM"; rm -f "$LOG"

echo "T-vi-stage2-fail-resumable: stage-2 fails -> stage-1 dispatch already happened"
SHIM=$(_make_brew_shim); LOG=$(mktemp)
PAYLOAD=$(jq -n '{auto_install:[{name:"r",category:"x",
  install_cmd:"brew install pkgone && brew install FAILNOW",
  install_cmds:["brew install pkgone","brew install FAILNOW"],
  required:false, description:"x"}], already_installed:[], manual_install:[], deferred:[]}')
out=$(PATH="$SHIM:$PATH" BREW_LOG="$LOG" _run_fix_tool_install "$PAYLOAD")
if grep -q "install -- pkgone" "$LOG" && grep -q "install -- FAILNOW" "$LOG" && echo "$out" | grep -q "RC=7"; then
  pass "T-vi-stage2-fail-resumable: stage-1 completed before stage-2 failed (rc=7)"
else
  fail_ "T-vi-stage2-fail-resumable" "log=$(tr '\n' ';' < "$LOG") out=$out"
fi
rm -rf "$SHIM"; rm -f "$LOG"

echo "T-vi-legacy-fallback: payload with ONLY install_cmd (no install_cmds) still dispatches"
SHIM=$(_make_brew_shim); LOG=$(mktemp)
PAYLOAD=$(jq -n '{auto_install:[{name:"legacy",category:"x",
  install_cmd:"brew install legacypkg",
  required:false, description:"x"}], already_installed:[], manual_install:[], deferred:[]}')
out=$(PATH="$SHIM:$PATH" BREW_LOG="$LOG" _run_fix_tool_install "$PAYLOAD")
if grep -q "install -- legacypkg" "$LOG"; then
  pass "T-vi-legacy-fallback: legacy singular install_cmd dispatched (back-compat)"
else
  fail_ "T-vi-legacy-fallback" "legacypkg not dispatched: log=$(tr '\n' ';' < "$LOG") out=$out"
fi
rm -rf "$SHIM"; rm -f "$LOG"

# ============================================================
# GROUP E — wrapper JSON regression: gitleaks / rust / k6 are now the
# structured array shape and JOIN back to their pre-migration strings
# (catches accidental stage drop/reorder). Mirrors BL-033
# T-migrated-semantics for docker/colima.
# ============================================================
echo ""
echo "GROUP E: gitleaks / rust / k6 migrated to array shape (join-preserves-semantics)"

_assert_array_joins() {
  local label="$1" json="$2" filter="$3" expect_len="$4" expect_join="$5"
  local arr len joined
  arr=$(jq -c "$filter" "$json")
  local t; t=$(echo "$arr" | jq -r 'type')
  if [ "$t" != "array" ]; then
    fail_ "$label" "expected array, got type=$t ($arr)"
    return
  fi
  len=$(echo "$arr" | jq 'length')
  joined=$(echo "$arr" | jq -r 'join(" && ")')
  if [ "$len" = "$expect_len" ] && [ "$joined" = "$expect_join" ]; then
    pass "$label: $expect_len-stage array joins to the pre-migration string"
  else
    fail_ "$label" "len=$len (want $expect_len); joined='$joined'"
  fi
}

GITLEAKS_JOIN='GITLEAKS_VERSION=$(curl -sSf https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r .tag_name) && curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz" | sudo tar -xz -C /usr/local/bin gitleaks'
for k in linux_apt linux_dnf linux_pacman; do
  _assert_array_joins "T-wrap-gitleaks-$k" "$COMMON_JSON" \
    ".tools[] | select(.name==\"gitleaks\") | .install.$k" 2 "$GITLEAKS_JOIN"
done

RUST_JOIN="curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source \"\$HOME/.cargo/env\""
for k in darwin_brew linux_apt; do
  _assert_array_joins "T-wrap-rust-$k" "$COMMON_JSON" \
    ".tools[] | select(.name==\"Rust\") | .install.$k" 2 "$RUST_JOIN"
done

K6_JOIN="sudo gpg -k && sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 && echo 'deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main' | sudo tee /etc/apt/sources.list.d/k6.list && sudo apt update && sudo apt install k6"
_assert_array_joins "T-wrap-k6-linux_apt" "$WEB_JSON" \
  '.tools[] | select(.name=="k6") | .install.linux_apt' 5 "$K6_JOIN"

# ============================================================
# GROUP F — upgrade-project.sh reader (DIRECT coverage). The interactive
# track-upgrade auto-install loop is gated behind prompt_yes_no +
# `[ -t 0 ]`, so it is unreachable from this non-interactive suite (the
# verifier proved a `"${_stages[@]}"`->`"${_stages[0]}"` stage-drop went
# undetected). It was factored into upgrade_auto_install_from_resolver()
# specifically so the stage iteration can be exercised here. This is the
# MUTATION ANCHOR for reader #3.
# ============================================================
echo ""
echo "GROUP F: upgrade-project.sh auto-install stage loop (direct)"

UPGRADE_SH="$REPO_ROOT/scripts/upgrade-project.sh"

# Extract just upgrade_auto_install_from_resolver() and run it in a
# subshell that also sources helpers-core (for run_install_stages +
# print_*). Drives the REAL function with a fake resolver payload whose
# tool has a multi-stage install_cmds; each stage touches a file so the
# stages that actually ran are observable on disk afterward.
_run_upgrade_installer() {
  local payload="$1" count="$2"
  local fn; fn=$(mktemp)
  awk '
    /^upgrade_auto_install_from_resolver\(\) \{/ {flag=1}
    flag {print}
    flag && /^\}$/ {exit}
  ' "$UPGRADE_SH" > "$fn"
  env _PAYLOAD="$payload" _COUNT="$count" _FN="$fn" _HC="$HELPERS_CORE" bash -c '
    set +e
    # shellcheck source=/dev/null
    source "$_HC"
    # shellcheck source=/dev/null
    source "$_FN"
    upgrade_auto_install_from_resolver "$_PAYLOAD" "$_COUNT"
  ' >/dev/null 2>&1
  rm -f "$fn"
}

echo "T-upg-multi-both: 2-stage tool runs BOTH stages [MUTATION ANCHOR]"
T=$(mktemp -d)
PAYLOAD=$(jq -n --arg s1 "touch $T/u1" --arg s2 "touch $T/u2" \
  '{auto_install:[{name:"multi",category:"x",install_cmd:($s1+" && "+$s2),install_cmds:[$s1,$s2],required:false,description:"x"}],already_installed:[],manual_install:[],deferred:[]}')
_run_upgrade_installer "$PAYLOAD" 1
if [ -e "$T/u1" ] && [ -e "$T/u2" ]; then
  pass "T-upg-multi-both: upgrade loop ran stage1 AND stage2"
else
  fail_ "T-upg-multi-both" "u1=$([ -e "$T/u1" ] && echo y || echo n) u2=$([ -e "$T/u2" ] && echo y || echo n) — a '\${_stages[0]}' mutation fails HERE"
fi
rm -rf "$T"

echo "T-upg-failfast: stage-1 fails -> stage-2 MUST NOT run"
T=$(mktemp -d)
PAYLOAD=$(jq -n --arg s2 "touch $T/u2_no" \
  '{auto_install:[{name:"ff",category:"x",install_cmd:("false && "+$s2),install_cmds:["false",$s2],required:false,description:"x"}],already_installed:[],manual_install:[],deferred:[]}')
_run_upgrade_installer "$PAYLOAD" 1
if [ ! -e "$T/u2_no" ]; then
  pass "T-upg-failfast: stage-1 failure halted the upgrade loop"
else
  fail_ "T-upg-failfast" "stage-2 ran despite stage-1 failure"
fi
rm -rf "$T"

echo "T-upg-legacy-fallback: tool with ONLY install_cmd still installs (back-compat)"
T=$(mktemp -d)
PAYLOAD=$(jq -n --arg s1 "touch $T/leg" \
  '{auto_install:[{name:"leg",category:"x",install_cmd:$s1,required:false,description:"x"}],already_installed:[],manual_install:[],deferred:[]}')
_run_upgrade_installer "$PAYLOAD" 1
if [ -e "$T/leg" ]; then
  pass "T-upg-legacy-fallback: legacy singular install_cmd ran"
else
  fail_ "T-upg-legacy-fallback" "legacy install_cmd did not run"
fi
rm -rf "$T"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

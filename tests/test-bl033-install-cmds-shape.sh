#!/usr/bin/env bash
# tests/test-bl033-install-cmds-shape.sh
#
# Coverage for BL-033: templates/tool-matrix/*.json entries with
# multi-stage `install_cmd` strings are migrated to a structured
# `install_cmds` array shape so per-stage failure surfaces cleanly
# and consumers can iterate stages instead of dumping the whole
# string into `bash -c "cmd1 && cmd2 && cmd3"`.
#
# Reader contract (scripts/resolve-tools.sh):
#   1. Legacy string value at install.<key> → resolver output emits
#      install_cmd = string AND install_cmds = [string].
#   2. Array of strings at install.<key> → resolver output emits
#      install_cmds = the array AND install_cmd = array joined with
#      " && " (back-compat for legacy consumers reading the singular
#      field).
#   3. Object shape at install.<key> that contains BOTH `install_cmd`
#      and `install_cmds` → reader EXITS NONZERO with a clear error
#      identifying the offending key (mutually-exclusive shape).
#   4. Empty array or non-string array elements → reader exits nonzero
#      with a diagnostic.
#
# Consumer contract (bash script that iterates install_cmds):
#   T-array-fail-fast — stage-1 nonzero exit MUST prevent stage-2 from
#   executing. This is the fail-fast diagnosis property BL-033 requires
#   to make multi-stage installs debuggable.
#
# Mutation: revert the array-reader arm of scripts/resolve-tools.sh
# (delete the `elif ($v | type) == "array"` branch). Under the mutant,
# T-array-happy fails RED (install_cmds field missing/empty; joined
# install_cmd blank).
#
# Test harness conventions: mirrors tests/test-bl046-helpers-split.sh
# — self-contained (no init.sh setup), each scenario in an isolated
# tmpdir, PASS/FAIL counters + exit status.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-tools.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a minimal tool-matrix fixture (common.json only) with a single
# tool entry the caller supplies via $1 (the JSON body of `install`).
# The check_command is set to `false` so the tool always shows up in
# auto_install (never already_installed). Returns TMPDIR path via stdout;
# caller cleans up.
_mk_matrix() {
  local install_body="$1"
  local auto_installable="${2:-true}"
  local tmp
  tmp=$(mktemp -d)
  cat > "$tmp/common.json" <<EOF
{
  "schema_version": "1.0",
  "scope": "common",
  "description": "BL-033 test fixture",
  "tools": [
    {
      "category": "test",
      "name": "TestTool",
      "description": "BL-033 install_cmds shape probe",
      "required": false,
      "phase": 0,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "false",
      "version_command": "echo",
      "min_version": null,
      "latest_check": null,
      "install": ${install_body},
      "auto_installable": ${auto_installable},
      "substitutable": false,
      "substitution_category": null
    }
  ]
}
EOF
  echo "$tmp"
}

# Run the resolver against the fixture matrix. Uses --dev-os darwin
# and pins linux_apt keys via env so the harness never depends on the
# host's package managers. Returns resolver JSON on stdout, exit code
# from the resolver.
_run_resolver() {
  local matrix_dir="$1"
  bash "$RESOLVER" \
    --dev-os darwin \
    --platform web \
    --language typescript \
    --track light \
    --phase 3 \
    --matrix-dir "$matrix_dir" 2>&1
}

# ============================================================
# T-back-compat: legacy string value at install.darwin_brew works
# ============================================================
echo "T-back-compat: legacy string install value produces install_cmd + install_cmds"
TMP=$(_mk_matrix '{"darwin_brew": "brew install jq"}')
out=$(_run_resolver "$TMP")
if ! echo "$out" | jq -e '.' >/dev/null 2>&1; then
  fail_ "T-back-compat" "resolver output is not valid JSON: $out"
elif ! echo "$out" | jq -e '.auto_install[0]' >/dev/null 2>&1; then
  fail_ "T-back-compat" "no auto_install entry emitted for legacy-string tool"
else
  install_cmd=$(echo "$out" | jq -r '.auto_install[0].install_cmd')
  install_cmds_len=$(echo "$out" | jq -r '.auto_install[0].install_cmds | length')
  install_cmds_0=$(echo "$out" | jq -r '.auto_install[0].install_cmds[0]')
  errors=""
  [ "$install_cmd" = "brew install jq" ] || errors="${errors}install_cmd='${install_cmd}' expected 'brew install jq'; "
  [ "$install_cmds_len" = "1" ] || errors="${errors}install_cmds length=$install_cmds_len expected 1; "
  [ "$install_cmds_0" = "brew install jq" ] || errors="${errors}install_cmds[0]='${install_cmds_0}' expected 'brew install jq'; "
  if [ -n "$errors" ]; then
    fail_ "T-back-compat" "$errors"
  else
    pass "T-back-compat: legacy string emits install_cmd + 1-element install_cmds"
  fi
fi
rm -rf "$TMP"

# ============================================================
# T-array-happy: array shape emits joined install_cmd + array install_cmds
# ============================================================
echo "T-array-happy: multi-stage array emits both joined and structured fields"
TMP=$(_mk_matrix '{"darwin_brew": ["brew install colima", "brew services start colima"]}')
out=$(_run_resolver "$TMP")
if ! echo "$out" | jq -e '.auto_install[0]' >/dev/null 2>&1; then
  fail_ "T-array-happy" "no auto_install entry emitted for array-shape tool (output: $out)"
else
  install_cmd=$(echo "$out" | jq -r '.auto_install[0].install_cmd')
  install_cmds_len=$(echo "$out" | jq -r '.auto_install[0].install_cmds | length')
  install_cmds_0=$(echo "$out" | jq -r '.auto_install[0].install_cmds[0]')
  install_cmds_1=$(echo "$out" | jq -r '.auto_install[0].install_cmds[1]')
  errors=""
  [ "$install_cmd" = "brew install colima && brew services start colima" ] \
    || errors="${errors}install_cmd='${install_cmd}' expected joined 'brew install colima && brew services start colima'; "
  [ "$install_cmds_len" = "2" ] \
    || errors="${errors}install_cmds length=$install_cmds_len expected 2; "
  [ "$install_cmds_0" = "brew install colima" ] \
    || errors="${errors}install_cmds[0]='${install_cmds_0}' expected 'brew install colima'; "
  [ "$install_cmds_1" = "brew services start colima" ] \
    || errors="${errors}install_cmds[1]='${install_cmds_1}' expected 'brew services start colima'; "
  if [ -n "$errors" ]; then
    fail_ "T-array-happy" "$errors"
  else
    pass "T-array-happy: array emits joined install_cmd + 2-element install_cmds"
  fi
fi
rm -rf "$TMP"

# ============================================================
# T-array-fail-fast: iterate stages, stage-1 nonzero → stage-2 skipped
# ============================================================
# Consumer-facing contract: a caller iterating install_cmds MUST see
# stage-2 unexecuted after stage-1 fails. We prove this by (a) taking
# the resolver's `install_cmds` array, (b) running each stage in
# order via bash -c, (c) breaking on first non-zero exit, and (d)
# observing that a stage-2-side-effect file was NOT created.
#
# This tests the SEMANTIC contract of install_cmds (fail-fast per stage).
# Consumers built on the array shape MUST implement this iteration —
# blindly joining with ' && ' and passing to bash -c would also
# short-circuit correctly, but blows away per-stage diagnostics; that
# is why BL-033 requires the structured shape.
echo "T-array-fail-fast: stage-1 failure blocks stage-2 execution"
TMP=$(_mk_matrix "$(jq -n --arg m1 "/tmp/bl033-fail-fast-stage1-$$" --arg m2 "/tmp/bl033-fail-fast-stage2-$$" '
  {darwin_brew: [
    "false",
    ("touch " + $m2)
  ]}
')")
MARKER2="/tmp/bl033-fail-fast-stage2-$$"
rm -f "$MARKER2"
out=$(_run_resolver "$TMP")
stages_json=$(echo "$out" | jq -c '.auto_install[0].install_cmds // empty')

# Guard against vacuous pass under the mutation. If install_cmds is
# missing/empty, the iteration is a no-op and MARKER2 is never touched
# — the fail-fast property would trivially hold, but for the WRONG
# reason (no stages to fail-fast on). Require a 2-stage array before
# proceeding.
stages_len=$(echo "$out" | jq -r '.auto_install[0].install_cmds | length' 2>/dev/null || echo 0)
case "$stages_len" in ''|*[!0-9]*) stages_len=0 ;; esac
if [ "$stages_len" != "2" ]; then
  fail_ "T-array-fail-fast" "expected 2-stage install_cmds but got length=$stages_len (auto_install=$(echo "$out" | jq -c '.auto_install'))"
else
  # Iterate stages, fail-fast on non-zero exit.
  iterated_rc=99
  stage_index=0
  while IFS= read -r stage; do
    if ! bash -c "$stage"; then
      iterated_rc=$stage_index
      break
    fi
    stage_index=$((stage_index + 1))
  done < <(echo "$stages_json" | jq -r '.[]')

  # We expect iteration to break at stage 0 (the "false" stage).
  if [ -e "$MARKER2" ]; then
    fail_ "T-array-fail-fast" "stage-2 executed despite stage-1 failure (marker $MARKER2 exists)"
  elif [ "$iterated_rc" != "0" ]; then
    fail_ "T-array-fail-fast" "expected break at stage 0 but iterated_rc=$iterated_rc"
  else
    pass "T-array-fail-fast: stage-2 was NOT executed after stage-1 exited nonzero"
  fi
fi
rm -f "$MARKER2"
rm -rf "$TMP"

# ============================================================
# T-mixed-invalid: object with BOTH install_cmd and install_cmds errors
# ============================================================
# Reader defensiveness: if a future schema drift plants an object at
# install.<key> with both singular and plural keys, the reader must
# refuse rather than silently pick one (which would give conflicting
# consumer paths — legacy readers pick install_cmd, new readers pick
# install_cmds, and they'd install different things). BL-033 requires
# a documented failure mode here.
echo "T-mixed-invalid: object with both install_cmd and install_cmds is rejected"
TMP=$(_mk_matrix '{"darwin_brew": {"install_cmd": "brew install jq", "install_cmds": ["brew install jq"]}}')
out=$(_run_resolver "$TMP" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  fail_ "T-mixed-invalid" "resolver exited 0 despite object with mutually-exclusive install_cmd+install_cmds keys (output: $out)"
elif ! echo "$out" | grep -qiE "mutually|both|exclusive|invalid|install_cmd.*install_cmds"; then
  fail_ "T-mixed-invalid" "resolver rejected but with no clear diagnostic (rc=$rc; output: $out)"
else
  pass "T-mixed-invalid: mutually-exclusive object shape refused with clear diagnostic"
fi
rm -rf "$TMP"

# ============================================================
# T-empty-array: empty array install value is rejected
# ============================================================
# Defensiveness backstop: an empty install_cmds array would silently
# skip the tool at install time — worse than a loud refusal. The
# reader must fail fast.
echo "T-empty-array: empty install_cmds array is rejected"
TMP=$(_mk_matrix '{"darwin_brew": []}')
out=$(_run_resolver "$TMP" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  fail_ "T-empty-array" "resolver exited 0 despite empty install_cmds array (output: $out)"
elif ! echo "$out" | grep -qiE "empty|at least one"; then
  fail_ "T-empty-array" "resolver rejected but no clear diagnostic (rc=$rc; output: $out)"
else
  pass "T-empty-array: empty array refused with clear diagnostic"
fi
rm -rf "$TMP"

# ============================================================
# T-non-string-elements: array with non-string elements is rejected
# ============================================================
echo "T-non-string-elements: array with non-string elements is rejected"
TMP=$(_mk_matrix '{"darwin_brew": ["brew install jq", 42, null]}')
out=$(_run_resolver "$TMP" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  fail_ "T-non-string-elements" "resolver exited 0 despite non-string array elements (output: $out)"
elif ! echo "$out" | grep -qiE "strings|type"; then
  fail_ "T-non-string-elements" "resolver rejected but no clear diagnostic (rc=$rc; output: $out)"
else
  pass "T-non-string-elements: non-string elements refused with clear diagnostic"
fi
rm -rf "$TMP"

# ============================================================
# T-migrated-entries: shipped tool-matrix entries actually use the
# array shape (regression check — the migration must not silently
# revert).
# ============================================================
echo "T-migrated-entries: shipped tool-matrix uses array shape for docker + colima"
missing=""
for key in linux_apt linux_dnf linux_pacman; do
  t=$(jq -r --arg k "$key" '(.tools[] | select(.name == "Docker") | .install[$k] | type) // "missing"' "$REPO_ROOT/templates/tool-matrix/common.json")
  [ "$t" = "array" ] || missing="${missing}docker.$key=$t "
done
colima_t=$(jq -r '(.tools[] | select(.name == "Colima") | .install.darwin_brew | type) // "missing"' "$REPO_ROOT/templates/tool-matrix/common.json")
[ "$colima_t" = "array" ] || missing="${missing}colima.darwin_brew=$colima_t "
if [ -n "$missing" ]; then
  fail_ "T-migrated-entries" "expected array shape but found: $missing"
else
  pass "T-migrated-entries: docker (apt/dnf/pacman) + colima.darwin_brew are arrays"
fi

# ============================================================
# T-migrated-shape-preserves-semantics: the resolver's joined install_cmd
# for a migrated entry equals what the pre-migration string was. Catches
# accidental stage reordering or dropped stages during migration.
# ============================================================
echo "T-migrated-semantics: real Docker linux entries parse as arrays with expected joined form"
# Regression check: read the SHIPPED Docker entry directly from the
# real matrix JSON and prove the array shape joins into the expected
# pre-migration string. This bypasses the resolver's key-priority
# (--dev-os) filter, which is host-dependent (a macOS harness has no
# apt/dnf/pacman and would fall through to manual). We're asserting a
# property of the SCHEMA + reader logic here, not the resolver's
# key-selection policy.
docker_install=$(jq -c '.tools[] | select(.name == "Docker") | .install' "$REPO_ROOT/templates/tool-matrix/common.json")
fail_reasons=""
for key in linux_apt linux_dnf linux_pacman; do
  arr=$(echo "$docker_install" | jq -c --arg k "$key" '.[$k]')
  joined=$(echo "$arr" | jq -r 'join(" && ")')
  # Verify (a) it's a 2-element array, (b) joined contains the usermod
  # tail so the migration didn't drop the second stage, and (c) the
  # first stage installs docker/docker.io.
  len=$(echo "$arr" | jq -r 'length')
  [ "$len" = "2" ] || fail_reasons="${fail_reasons}docker.$key length=$len (expected 2); "
  case "$joined" in
    *"sudo usermod -aG docker \$USER") ;;  # OK — 2nd stage is the group add
    *) fail_reasons="${fail_reasons}docker.$key joined='$joined' missing usermod tail; " ;;
  esac
  # First stage must mention docker (all pkg mgrs do: apt install docker.io,
  # dnf install docker, pacman -S ... docker). Regex accepts either word.
  case "$joined" in
    *"docker"*) ;;  # OK — 1st stage installs docker
    *) fail_reasons="${fail_reasons}docker.$key joined='$joined' missing docker install stage; " ;;
  esac
done
# Colima: 2-stage brew install + services start
colima_install=$(jq -c '.tools[] | select(.name == "Colima") | .install.darwin_brew' "$REPO_ROOT/templates/tool-matrix/common.json")
colima_len=$(echo "$colima_install" | jq -r 'length')
colima_joined=$(echo "$colima_install" | jq -r 'join(" && ")')
[ "$colima_len" = "2" ] || fail_reasons="${fail_reasons}colima.darwin_brew length=$colima_len (expected 2); "
[ "$colima_joined" = "brew install colima && brew services start colima" ] \
  || fail_reasons="${fail_reasons}colima.darwin_brew joined='$colima_joined' expected 'brew install colima && brew services start colima'; "
if [ -n "$fail_reasons" ]; then
  fail_ "T-migrated-semantics" "$fail_reasons"
else
  pass "T-migrated-semantics: docker linux_* + colima.darwin_brew arrays join to expected shapes"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

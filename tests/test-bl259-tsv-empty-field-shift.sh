#!/usr/bin/env bash
# tests/test-bl259-tsv-empty-field-shift.sh
#
# `## BL-259:` — AN EMPTY `@tsv` FIELD COLLAPSED AND SHIFTED THE WHOLE ROW.
#
# scripts/resolve-tools.sh read nine tab-separated fields with
# `IFS=$'\t' read -r f1 … f9`. Tab is an IFS *whitespace* character, so bash
# collapses runs of tabs: an EMPTY field does not arrive as an empty field, it
# vanishes, and every later field shifts left one. `version_command` is
# optional — the producer emits `(.version_command // "")` for it — so for the
# six catalogued tools that omit it the base64 install blob landed in
# TOOL_DESCRIPTION and TOOL_INSTALL_B64 arrived EMPTY. After that every step
# succeeded at rc 0 producing nothing (`base64 -d` on empty input, then `jq` on
# empty input), so neither the `|| echo "{}"` nor the `// "See documentation"`
# default fired, and the operator was handed an EMPTY install instruction.
#
# This drives the REAL resolver against a hermetic fixture matrix — no network,
# no host tools, a `check_command` that cannot succeed — and asserts the
# install text and the description survive for a tool with no version_command.
# The control is the same tool WITH one. The mutant restores the collapsing
# read on a mirror and must re-open the defect.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-tools.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); case "$n" in ''|*[!0-9]*) n=0 ;; esac; printf '%s\n' "$n"; }

[ -f "$RESOLVER" ] || { echo "  [FAIL] setup — $RESOLVER not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "  [FAIL] setup — jq is required"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

# Distinctive payloads: if the row shifts, these are exactly what goes missing.
NOVER_INSTALL='BL259-INSTALL-TEXT-FOR-THE-TOOL-WITHOUT-A-VERSION-COMMAND'
NOVER_DESC='BL259-DESCRIPTION-NO-VERSION'
CTRL_INSTALL='BL259-INSTALL-TEXT-FOR-THE-CONTROL'
CTRL_DESC='BL259-DESCRIPTION-CONTROL'
# Field 7 by VALUE. Without this the suite pins field 7 only positionally, and a
# mutant that drops the TOOL_VERSION_CMD capture while keeping the position strip
# survives this suite AND all eight unit-lane suites that drive the resolver,
# silently emptying every already_installed[].version (measured: 15 real versions
# to 0). No other test in the repo asserts a resolver version value.
INST_VERSION='BL259-VERSION-VALUE'

# mk_matrix <dir> — a common.json with two manual-install tools that can never
# be found: one WITHOUT version_command (the trigger), one WITH it (the control).
mk_matrix() {
  local d="$1"
  mkdir -p "$d" || return 1
  cat > "$d/common.json" <<MATRIX
{
  "schema_version": "1.0",
  "scope": "common",
  "description": "BL-259 fixture",
  "tools": [
    {
      "name": "BL259 No Version Tool",
      "category": "testing",
      "description": "$NOVER_DESC",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v bl259_definitely_absent_binary",
      "auto_installable": false,
      "install": { "manual": "$NOVER_INSTALL" }
    },
    {
      "name": "BL259 Control Tool",
      "category": "testing",
      "description": "$CTRL_DESC",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v bl259_definitely_absent_binary",
      "version_command": "bl259_definitely_absent_binary --version",
      "auto_installable": false,
      "install": { "manual": "$CTRL_INSTALL" }
    },
    {
      "name": "BL259 Installed Tool",
      "category": "testing",
      "description": "BL259-DESCRIPTION-INSTALLED",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "true",
      "version_command": "printf %s $INST_VERSION",
      "auto_installable": false,
      "install": { "manual": "BL259-INSTALL-TEXT-INSTALLED" }
    }
  ]
}
MATRIX
  jq empty "$d/common.json" 2>/dev/null || return 1
  # the fixture is only honest if the check_command really cannot succeed
  if command -v bl259_definitely_absent_binary >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# run_resolver <matrix-dir> [resolver] → RESOLVER_OUT, RESOLVER_RC
run_resolver() {
  local mdir="$1" bin="${2:-$RESOLVER}"
  RESOLVER_OUT="$( bash "$bin" \
    --dev-os linux --platform web --language typescript \
    --track standard --phase 1 --matrix-dir "$mdir" 2>/dev/null )"
  RESOLVER_RC=$?
  return 0
}

# field_of <json> <tool-name> <field> → the manual_install record's field
field_of() {
  printf '%s' "$1" | jq -r --arg n "$2" --arg f "$3" \
    '(.manual_install[] | select(.name == $n) | .[$f]) // "<<ABSENT>>"' 2>/dev/null
}

echo "=== R — the real resolver, hermetic fixture matrix ==="

MX="$(newtmp)/matrix"
if ! mk_matrix "$MX"; then
  fail_ "R setup" "could not build the fixture matrix (or the absent binary is somehow present)"
else
  run_resolver "$MX"
  if [ "$RESOLVER_RC" -ne 0 ] || [ -z "$RESOLVER_OUT" ]; then
    fail_ "R0" "the resolver did not produce a plan (rc=$RESOLVER_RC)"
  else
    pass "R0 — the resolver produced a plan from the fixture matrix (rc=$RESOLVER_RC)"

    # R1 — THE DISCRIMINATOR. With the row shifted this is empty.
    got="$(field_of "$RESOLVER_OUT" "BL259 No Version Tool" instructions)"
    if [ "$got" = "$NOVER_INSTALL" ]; then
      pass "R1 — a tool with NO version_command keeps its install instructions"
    else
      fail_ "R1" "install instructions for the no-version tool are [$got], want [$NOVER_INSTALL]"
    fi

    # R2 — the same shift puts the base64 install blob into the description
    got="$(field_of "$RESOLVER_OUT" "BL259 No Version Tool" description)"
    if [ "$got" = "$NOVER_DESC" ]; then
      pass "R2 — and its description is the real description, not the base64 install blob"
    else
      fail_ "R2" "description is [$got], want [$NOVER_DESC]"
    fi

    # R4 — field 7 BY VALUE, not just by position. A mutant that drops the
    # TOOL_VERSION_CMD capture but keeps the position strip leaves fields 8 and
    # 9 correct, so R1/R2/R3 all still pass; only this case sees it.
    got="$(printf '%s' "$RESOLVER_OUT" | jq -r '(.already_installed[] | select(.name == "BL259 Installed Tool") | .version) // "<<ABSENT>>"' 2>/dev/null)"
    if [ "$got" = "$INST_VERSION" ]; then
      pass "R4 — an installed tool's version_command is captured BY VALUE (field 7)"
    else
      fail_ "R4" "version is [$got], want [$INST_VERSION] — field 7 is not captured"
    fi

    # R3 — the control: a tool WITH version_command was never affected
    got="$(field_of "$RESOLVER_OUT" "BL259 Control Tool" instructions)"
    if [ "$got" = "$CTRL_INSTALL" ]; then
      pass "R3 — the control tool (WITH version_command) keeps its install instructions"
    else
      fail_ "R3" "control install instructions are [$got], want [$CTRL_INSTALL]"
    fi
  fi
fi

echo "=== M — mutation proof on a mirror ==="

M_SPLIT="# BL-259-TSV-SPLIT"
n="$(grep -c "${M_SPLIT}\$" "$RESOLVER" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
[ "$n" = "1" ] \
  && pass "M0 — '$M_SPLIT' occurs exactly once at end-of-line in resolve-tools.sh" \
  || fail_ "M0" "'$M_SPLIT' occurs $n times in resolve-tools.sh (need exactly 1)"

# MP1 — restore the collapsing read on a mirror: R1 must go red again. The
# whole explicit-split block is replaced by the single `IFS=$'\t' read` line
# it replaced, located by the marker and the loop opener around it.
MP1="$(newtmp)/fw"
if ! mkdir -p "$MP1" || ! cp -Rp "$REPO_ROOT/scripts" "$MP1/"; then
  fail_ "MP1 setup" "could not mirror scripts/"
else
  tgt="$MP1/scripts/resolve-tools.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  open_ln="$(grep -n 'while IFS= read -r _bl259_row; do' "$before" | head -1 | cut -d: -f1)"
  mark_ln="$(grep -n "${M_SPLIT}\$" "$before" | head -1 | cut -d: -f1)"
  if [ -z "$open_ln" ] || [ -z "$mark_ln" ] || [ "$mark_ln" -le "$open_ln" ]; then
    fail_ "MP1 setup" "could not locate the split block (open=$open_ln mark=$mark_ln)"
  else
    {
      head -n $((open_ln - 1)) "$before"
      printf '%s\n' "while IFS=\$'\\t' read -r TOOL_NAME TOOL_CATEGORY TOOL_PHASE TOOL_REQUIRED TOOL_CHECK TOOL_AUTO TOOL_VERSION_CMD TOOL_DESCRIPTION TOOL_INSTALL_B64; do"
      tail -n +$((mark_ln + 1)) "$before"
    } > "$tgt"
    if ! bash -n "$tgt" 2>/dev/null \
       || [ "$(grep -c "IFS=\$'\\\\t' read -r TOOL_NAME" "$tgt")" -ne 1 ] \
       || [ "$(grep -c "${M_SPLIT}\$" "$tgt")" -ne 0 ]; then
      fail_ "MP1 setup" "the collapsing-read mutation did not apply cleanly"
    else
      MX2="$(newtmp)/matrix"
      if ! mk_matrix "$MX2"; then
        fail_ "MP1 setup" "could not build the mutant's fixture matrix"
      else
        run_resolver "$MX2" "$tgt"
        got="$(field_of "$RESOLVER_OUT" "BL259 No Version Tool" instructions)"
        if [ "$got" != "$NOVER_INSTALL" ]; then
          pass "MP1 (MUTATION) — with the collapsing read restored, the no-version tool loses its install instructions (got [$got]): R1 is what stops it"
        else
          fail_ "MP1 (MUTATION)" "the collapsing read changed nothing — R1 may be passing for another reason"
        fi
      fi
    fi
  fi
fi

# MP2 — the arity guard. Drop one field from the PRODUCER on a mirror so the
# row carries seven tabs instead of eight. Without the guard the hand split
# duplicates the last available field into every remaining slot — plausible
# data, silently. The resolver must refuse loudly instead.
MP2="$(newtmp)/fw"
if ! mkdir -p "$MP2" || ! cp -Rp "$REPO_ROOT/scripts" "$MP2/"; then
  fail_ "MP2 setup" "could not mirror scripts/"
else
  tgt2="$MP2/scripts/resolve-tools.sh"; before2="$(mktemp)"; cp "$tgt2" "$before2"
  # the producer's `.description,` element — one line, exactly one occurrence
  if [ "$(grep -c '^  \.description,$' "$before2")" -ne 1 ]; then
    fail_ "MP2 setup" "the producer's .description element is not a unique single line"
  else
    grep -v '^  \.description,$' "$before2" > "$tgt2"
    if ! bash -n "$tgt2" 2>/dev/null \
       || [ "$(grep -c '^  \.description,$' "$tgt2")" -ne 0 ] \
       || [ "$(_changed_lines "$before2" "$tgt2")" -ne 1 ]; then
      fail_ "MP2 setup" "the producer mutation did not apply cleanly"
    else
      MX3="$(newtmp)/matrix"
      if ! mk_matrix "$MX3"; then
        fail_ "MP2 setup" "could not build the mutant's fixture matrix"
      else
        MP2_ERR="$(newtmp)/err"
        RESOLVER_OUT="$( bash "$tgt2" --dev-os linux --platform web --language typescript \
          --track standard --phase 1 --matrix-dir "$MX3" 2>"$MP2_ERR" )"; MP2_RC=$?
        if [ "$MP2_RC" -ne 0 ] && grep -q 'malformed tool row' "$MP2_ERR"; then
          pass "MP2 (MUTATION) — a producer emitting one field fewer is REFUSED loudly (rc=$MP2_RC), not read as plausible data"
        else
          fail_ "MP2 (MUTATION)" "a short row was accepted (rc=$MP2_RC) — the arity guard is not load-bearing; stderr: $(head -1 "$MP2_ERR" 2>/dev/null)"
        fi
      fi
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1

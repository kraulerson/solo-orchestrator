# scripts/lib/enforcement-level.sh — BL-030 enforcement-level helpers.
#
# Reads the project's enforcement_level setting and validates transitions.
# Sourced by init.sh, reconfigure-project.sh, framework-gate.sh,
# detect-out-of-band-commits.sh, and any future caller that needs to
# decide based on the enforcement posture.
#
# Field values: "no" | "light" | "strict". Default at read time: "strict".

# shellcheck shell=bash

# read_enforcement_level <project_root>
# Echoes the project's enforcement_level. Defaults to "strict" if the
# field is missing or the manifest doesn't exist. Never errors — callers
# can rely on the output.
read_enforcement_level() {
  local project_root="${1:-.}"
  local manifest="$project_root/.claude/manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "strict"
    return 0
  fi
  local level
  level=$(jq -r '.enforcement_level // "strict"' "$manifest" 2>/dev/null || echo "strict")
  case "$level" in
    no|light|strict) echo "$level" ;;
    *) echo "strict" ;;
  esac
}

# assert_choosable <project_root>
# Returns 0 if the project's deployment / poc_mode allows the user to
# pick enforcement_level. Returns 1 otherwise. No output unless error.
#
# Choosable: deployment=personal (any poc_mode init.sh can produce for it:
# private_poc or production).
# Non-choosable (forced strict): deployment=organizational (poc_mode
# sponsored_poc or production).
# BL-129: `organizational + private_poc` is NOT a producible combination —
# init.sh's gov-mode rules reject it ("Private POC is always personal") — so
# the branch below that would make it choosable is defensive dead code kept
# only for hand-edited manifests; do not describe the combo as a choosable
# tier anywhere.
assert_choosable() {
  local project_root="${1:-.}"
  local manifest="$project_root/.claude/manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "[FAIL] enforcement-level: manifest missing at $manifest" >&2
    return 1
  fi
  local deployment poc_mode
  deployment=$(jq -r '.deployment // "personal"' "$manifest" 2>/dev/null)
  poc_mode=$(jq -r '.poc_mode // ""' "$manifest" 2>/dev/null)
  if [ "$deployment" = "personal" ]; then
    return 0
  fi
  if [ "$deployment" = "organizational" ] && [ "$poc_mode" = "private_poc" ]; then
    return 0
  fi
  return 1
}

# validate_transition <project_root> <new_level>
# Returns 0 if the requested transition is allowed. Returns 1 with a
# diagnostic on stderr otherwise.
validate_transition() {
  local project_root="${1:-.}"
  local new_level="$2"
  case "$new_level" in
    no|light|strict) ;;
    *)
      echo "[FAIL] enforcement-level: unknown level '$new_level' (expected: no | light | strict)" >&2
      return 1
      ;;
  esac
  if assert_choosable "$project_root"; then
    return 0
  fi
  # Non-choosable mode — must stay strict.
  if [ "$new_level" = "strict" ]; then
    return 0
  fi
  echo "[FAIL] enforcement-level: cannot set '$new_level' on this project — deployment/poc_mode forces strict" >&2
  return 1
}

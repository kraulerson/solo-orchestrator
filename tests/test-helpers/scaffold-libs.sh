#!/usr/bin/env bash
# tests/test-helpers/scaffold-libs.sh — shared fixture-scaffold helper.
#
# BL-074: the BL-046 helpers split (PR #125) turned scripts/lib/helpers.sh
# into a backwards-compat SHIM that sources helpers-full.sh, which in turn
# sources helpers-core.sh. The real product path copies all three into
# every generated project (init.sh:1221-1223), so shipping projects are
# fine. But hand-rolled test fixtures that copied ONLY helpers.sh died at
# helpers.sh:39 with "helpers-full.sh: No such file or directory" the
# moment a scaffolded script (reconfigure-project.sh, upgrade-project.sh,
# intake-wizard.sh, ...) sourced the shim.
#
# Route every fixture that needs the helpers through this one function so
# the copy set can never drift out of sync with the shim chain again. If a
# future split adds another sibling, it gets added HERE, in one place.
#
# Usage:
#   source "$REPO_ROOT/tests/test-helpers/scaffold-libs.sh"
#   scaffold_helpers_libs "$P/scripts/lib"              # repo inferred
#   scaffold_helpers_libs "$P/scripts/lib" "$REPO_ROOT" # repo explicit
#
# bash-3.2 safe (macOS /bin/bash): no associative arrays, no mapfile, no
# process substitution required.

# Resolve this helper's own repo root once (tests/test-helpers -> ../..).
# Callers may still pass an explicit repo root as arg 2 to override.
_SCAFFOLD_LIBS_SELF_DIR="${BASH_SOURCE[0]%/*}"
[ "$_SCAFFOLD_LIBS_SELF_DIR" = "${BASH_SOURCE[0]}" ] && _SCAFFOLD_LIBS_SELF_DIR="."
_SCAFFOLD_LIBS_DEFAULT_REPO="$(cd "$_SCAFFOLD_LIBS_SELF_DIR/../.." && pwd)"

# The full shim chain, in the order init.sh copies it. Keep in lockstep
# with init.sh:1221-1223. helpers.sh sources helpers-full.sh, which
# sources helpers-core.sh — all three MUST land together.
_SCAFFOLD_HELPERS_CHAIN="helpers.sh helpers-core.sh helpers-full.sh"

# scaffold_helpers_libs <dest_scripts_lib_dir> [repo_root]
#
# Copies the complete helpers shim chain into <dest_scripts_lib_dir>
# (created if absent). Returns non-zero — and prints to stderr — if any
# source file is missing or a copy fails. Silently omitting a sibling is
# exactly the BL-074 defect, so this fails LOUD rather than leaving a
# fixture that half-works.
scaffold_helpers_libs() {
  local dest="$1"
  local repo="${2:-$_SCAFFOLD_LIBS_DEFAULT_REPO}"
  local src="$repo/scripts/lib"
  local f

  if [ -z "$dest" ]; then
    echo "scaffold_helpers_libs: missing destination scripts/lib dir" >&2
    return 2
  fi
  mkdir -p "$dest" || return 1
  for f in $_SCAFFOLD_HELPERS_CHAIN; do
    if [ ! -f "$src/$f" ]; then
      echo "scaffold_helpers_libs: missing source $src/$f" >&2
      return 1
    fi
    cp "$src/$f" "$dest/$f" || {
      echo "scaffold_helpers_libs: failed to copy $f -> $dest" >&2
      return 1
    }
  done
  return 0
}

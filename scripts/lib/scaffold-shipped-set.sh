#!/usr/bin/env bash
# scripts/lib/scaffold-shipped-set.sh
#
# SINGLE SOURCE OF TRUTH for "which scripts/ files does init.sh ship to a
# scaffolded project?" — derived MECHANICALLY from init.sh's `cp` lines so it
# can never drift from the real copy list.
#
# Consumed by TWO callers (both must stay green):
#   • tests/test-scaffold-source-closure.sh — the BL-088 source-closure check
#     (derives the shipped set to prove no shipped script sources an unshipped
#     sibling).
#   • scripts/upgrade-project.sh --sync-framework (BL-099 SLICE-A) — the script
#     sync copies exactly this set framework→project.
#
# Placement rationale (scripts/lib, not tests/test-helpers): the sync feature
# is PRODUCT code that depends on this parser at runtime, and upgrade-project.sh
# references it via "$SCRIPT_DIR/lib/scaffold-shipped-set.sh". Under the BL-088
# source-closure doctrine every $SCRIPT_DIR sibling a shipped script sources
# must itself be shipped, so init.sh ships this lib — keeping product code out
# of tests/ and the closure invariant intact. The closure test also sources it
# from scripts/lib.
#
# Pure function, no side effects, bash-3.2 safe (no associative arrays, no
# process-substitution requirement).

# soif_parse_shipped_scripts <init_file> <scripts_dir>
#   Prints one shipped path per line ("scripts/<rel>"), LC-sorted & deduped.
#   A `cp "$SCRIPT_DIR/scripts/foo.sh" ...` line yields "scripts/foo.sh"; a glob
#   copy whose captured path ends in '/' (e.g. host-drivers/) is expanded to the
#   matching *.sh files under <scripts_dir>. Full-line matching mirrors the
#   original inline parser in tests/test-scaffold-source-closure.sh byte-for-byte
#   so both consumers observe an identical set.
soif_parse_shipped_scripts() {
  local init_file="$1" scripts_dir="$2"
  local line rel base f
  grep -E 'cp[[:space:]]+"\$SCRIPT_DIR/scripts/' "$init_file" | while IFS= read -r line; do
    rel="$(printf '%s\n' "$line" | sed -n 's#.*cp[[:space:]]*"\$SCRIPT_DIR/\(scripts/[^"]*\)".*#\1#p')"
    [ -n "$rel" ] || continue
    if [ "${rel%/}" != "$rel" ]; then
      # captured path ends in '/': a glob copy of *.sh under that dir
      base="${rel#scripts/}"
      for f in "$scripts_dir/$base"*.sh; do
        [ -f "$f" ] && printf 'scripts/%s%s\n' "$base" "$(basename "$f")"
      done
    else
      printf '%s\n' "$rel"
    fi
  done | sort -u
}

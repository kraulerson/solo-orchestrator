# scripts/lib/bypass-patterns.sh — BL-029 bypass-shape pattern table.
#
# Sourced by scripts/hooks/bypass-detector.sh. Each pattern has a name
# (echoed by scan_bypass_patterns on match) and a regex. Add new patterns
# at the bottom of the table; do not modify the detector.

# shellcheck shell=bash

# Pattern table: parallel arrays for name + regex.
BYPASS_PATTERN_NAMES=(
  no_verify
  soif_force_step
  terminal_workaround
  fake_loop
  force_push
  manual_step_complete
)

BYPASS_PATTERN_REGEXES=(
  '--no-verify'
  'SOIF_FORCE_STEP='
  '(run|do|execute) this (in your )?(own )?terminal'
  '(mark|complete) step .*(build_loop|phase[0-9]+_init):.*(complete|done)|tests_verified_failing[^a-z]*complete'
  'git push (--force|--force-with-lease|-f[^a-z])'
  '(I.?ll|we can) (just )?mark .* (complete|done|passed)'
)

# scan_bypass_patterns <text>
# Echoes the first matched pattern name on stdout. Returns 0 on match,
# 1 on no match. Case-insensitive.
scan_bypass_patterns() {
  local text="${1:-}"
  [ -z "$text" ] && return 1
  local i
  for i in "${!BYPASS_PATTERN_NAMES[@]}"; do
    local name="${BYPASS_PATTERN_NAMES[$i]}"
    local regex="${BYPASS_PATTERN_REGEXES[$i]}"
    if echo "$text" | grep -qiE -e "$regex"; then
      echo "$name"
      return 0
    fi
  done
  return 1
}

# pattern_regex_for <name>
# Echoes the original regex string for the named pattern. Returns 0 on
# success, 1 if the name is unknown. Used by the detector to extract
# excerpts (re-grepping the original text with the actual regex, not
# with a derivative of the name).
pattern_regex_for() {
  local target="${1:-}"
  local i
  for i in "${!BYPASS_PATTERN_NAMES[@]}"; do
    if [ "${BYPASS_PATTERN_NAMES[$i]}" = "$target" ]; then
      echo "${BYPASS_PATTERN_REGEXES[$i]}"
      return 0
    fi
  done
  return 1
}

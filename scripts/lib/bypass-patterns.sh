# scripts/lib/bypass-patterns.sh — BL-029 bypass-shape pattern table.
#
# Sourced by scripts/hooks/bypass-detector.sh. Each pattern has a name
# (echoed by scan_bypass_patterns on match) and a regex. Add new patterns
# at the bottom of the table; do not modify the detector.

# shellcheck shell=bash

# Pattern table: parallel arrays for name + regex.
#
# Calibration replay 2026-04-29 (Reports/uat-2026-04-29-bl029-validation/)
# surfaced 4 narrow regexes; relaxations:
#   - terminal_workaround: noun between (run|do|execute) and (terminal|shell)
#     can be anything; "this" is no longer required.
#   - fake_loop: list/comma separators allowed between tests_verified_failing
#     and complete (the canonical "mark X, Y, etc. as complete" phrasing).
#   - manual_step_complete: trigger verbs broadened beyond I'll / we can.
#   - no_verify: catches the canonical short flag `git commit -n` / `-nm`.
BYPASS_PATTERN_NAMES=(
  no_verify
  soif_force_step
  terminal_workaround
  fake_loop
  force_push
  manual_step_complete
)

BYPASS_PATTERN_REGEXES=(
  '(--no-verify|git commit[[:space:]]+-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$))'
  'SOIF_FORCE_STEP='
  '(run|do|execute) [^.]*(terminal|shell)'
  '(mark|complete) step .*(build_loop|phase[0-9]+_init):.*(complete|done)|tests_verified_failing[^a-z0-9_]+.{0,40}complete'
  'git push (--force|--force-with-lease|-f[^a-z])'
  "(I.?ll|we can|we could|let.?s|I.?d|we.?d|we should|I should) (just |simply )?mark .* (complete|done|passed)"
)

# scan_bypass_patterns <text>
# Echoes the FIRST matched pattern name on stdout. Returns 0 on match,
# 1 on no match. Case-insensitive. Backward-compatible single-match API.
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

# scan_bypass_patterns_all <text>
# Echoes EVERY matched pattern name, one per line, in table order. Returns
# 0 if any match, 1 if none. Used by the detector to write one audit row
# per matched pattern — prevents higher-severity (refuse_to_recommend)
# patterns from being silently masked by earlier no_verify / soif_force_step
# matches when a single proposal contains multiple bypass shapes.
# (Calibration replay 2026-04-29 finding S1.)
scan_bypass_patterns_all() {
  local text="${1:-}"
  [ -z "$text" ] && return 1
  local i any=0
  for i in "${!BYPASS_PATTERN_NAMES[@]}"; do
    local name="${BYPASS_PATTERN_NAMES[$i]}"
    local regex="${BYPASS_PATTERN_REGEXES[$i]}"
    if echo "$text" | grep -qiE -e "$regex"; then
      echo "$name"
      any=1
    fi
  done
  [ "$any" = "1" ]
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

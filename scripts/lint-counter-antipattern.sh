#!/usr/bin/env bash
# scripts/lint-counter-antipattern.sh — fail CI if any shell script
# captures a counter using the `|| echo "0"` antipattern without the
# canonical case-statement sanitizer on the immediately-following line.
#
# THE DEFECT CLASS
#   var=$(grep -c PATTERN file 2>/dev/null || echo "0")
#   [ "$var" -gt 0 ] && do_thing
#
# When `grep -c` matches zero lines, it prints "0\n" and exits 1; the
# `||` branch then fires and appends a second "0\n". The capture holds
# the two-line string "0\n0". Subsequent arithmetic comparisons error
# with `integer expression expected`, and under `set -euo pipefail`
# the test returns non-zero — silently flipping gates into the wrong
# branch. The CANONICAL fix (PR #53, audit-driven across PRs #67-#71):
#
#   var=$(grep -c PATTERN file 2>/dev/null || echo "0")
#   case "$var" in ''|*[!0-9]*) var=0 ;; esac
#
# This linter is the wave-2 backstop after PRs #67-#71 remediated every
# known site: it makes the antipattern un-introducible in CI going
# forward without an explicit allowlist comment justifying the choice.
# PR #72 (cycle 6) established the baseline regex for `|| echo "0"`.
# This cycle-8 follow-up extends coverage to the `|| true` and `|| :`
# variants and remediates the 17 in-tree sites that matched.
#
# DELIBERATE SCOPE
#   • Targets `|| echo "0"` (or `|| echo 0`), `|| true`, and `|| :`
#     endings on capture lines that count via `grep -c`, `jq ... length`,
#     or `wc`. All three endings collapse the subshell to a non-numeric
#     or multi-line value when the inner command exits non-zero:
#       - `|| echo "0"` → "0\n0" concat under zero-match grep -c
#       - `|| true`     → silent empty-string capture
#       - `|| :`        → silent empty-string capture (`:` is no-op)
#     All three break downstream arithmetic identically; PR #72 (cycle 6)
#     covered the `echo "0"` form, and this cycle-8 follow-up extends
#     coverage to the `|| true` / `|| :` variants and remediates the
#     17 in-tree sites that matched.
#   • DOES NOT target the `var=$(cmd) || var=0` *outer-OR* idiom where
#     the `||` lives AFTER the subshell's closing `)`. That construction
#     is structurally distinct: the assignment-exit fires the outer `||`
#     when grep exits 1, cleanly assigning `var=0` exactly once. It is
#     the CORRECT idiom and must NOT be flagged. The regex below anchors
#     `|| <fallback> )` so only IN-subshell fallbacks match. See T6c in
#     tests/test-lint-counter-antipattern.sh for the regression guard.
#   • DOES NOT cover multi-line `var=$( cmd \\` captures where the
#     fallback lives on a continuation line. PR #70 fixed the known
#     multi-line site in init.sh; future multi-line captures are out
#     of scope for this regex (a future PR can extend with a multi-line
#     walker if needed). Verifier confirmed no in-tree multi-line hits
#     for this cycle.
#
# ALLOWLIST
#   Append `# lint-counter-antipattern: allow <reason>` to the
#   antipattern line itself (NOT the sanitizer line). The reason is
#   REQUIRED — an empty reason fails the lint, so reviewers always
#   have justification text to evaluate.
#
# EXIT CODES
#   0 — no violations
#   1 — one or more violations found
#   2 — invocation / I/O error
#
# USAGE
#   bash scripts/lint-counter-antipattern.sh           # quiet pass/fail
#   bash scripts/lint-counter-antipattern.sh --list    # PASS/FAIL table

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_PATH="$REPO_ROOT/scripts/lint-counter-antipattern.sh"
TEST_FIXTURE_PATTERN="test-lint-counter-antipattern"

LIST_MODE=0
if [ "${1:-}" = "--list" ]; then
  LIST_MODE=1
elif [ -n "${1:-}" ]; then
  echo "Usage: $0 [--list]" >&2
  exit 2
fi

# Files to walk. Globs are evaluated below; missing dirs are skipped.
TARGET_GLOBS=(
  "$REPO_ROOT/scripts"/*.sh
  "$REPO_ROOT/scripts/lib"/*.sh
  "$REPO_ROOT/scripts/hooks"/*.sh
  "$REPO_ROOT/scripts/host-drivers"/*.sh
  "$REPO_ROOT/tests"/*.sh
  "$REPO_ROOT/init.sh"
)

# Per-line antipattern: extended regex for `grep -E`.
# Matches:   <leading-ws> IDENT=$( ... grep -c|jq...length|wc ... || <fallback> )
# Where <fallback> ∈ { echo "0", echo 0, true, : }, all of which leave
# the capture in a non-numeric or empty state on the inner command's
# non-zero exit. Tolerates: -c with extra flags like -cE, -ci, -ciE;
# quoted/unquoted 0; trailing whitespace and a `)` after the fallback.
#
# The terminating `\)` is load-bearing — it ensures we only match
# IN-subshell `||` fallbacks. The outer-OR idiom `var=$(...) || var=0`
# has its `||` AFTER the `)` and is the CORRECT pattern (see T6c).
ANTIPATTERN_RE='^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\(.*(grep[[:space:]]+-[a-zA-Z]*c[a-zA-Z]*|jq[[:space:]].*length|[[:space:]]wc[[:space:]]).*\|\|[[:space:]]*(echo[[:space:]]+"?0"?|true|:)[[:space:]]*\)'

# Strip a trailing `# lint-counter-antipattern: allow <reason>` and
# return: VAR_NAME<TAB>ALLOW_REASON_OR_EMPTY<TAB>HAS_MARKER (0|1)
# Caller checks: if HAS_MARKER=1 and reason empty → fail.
parse_line() {
  local line="$1"
  local marker_reason=""
  local has_marker=0
  case "$line" in
    *"# lint-counter-antipattern: allow"*)
      has_marker=1
      # Extract everything after the marker prefix; trim trailing ws.
      marker_reason="${line##*# lint-counter-antipattern: allow}"
      # Trim leading and trailing whitespace.
      marker_reason="${marker_reason#"${marker_reason%%[![:space:]]*}"}"
      marker_reason="${marker_reason%"${marker_reason##*[![:space:]]}"}"
      ;;
  esac

  # Extract var name: leading whitespace, then identifier up to '='.
  local stripped="${line#"${line%%[![:space:]]*}"}"
  local var_name="${stripped%%=*}"

  printf '%s\t%s\t%d\n' "$var_name" "$marker_reason" "$has_marker"
}

# Build PASS-marker regex for a given var name. Tolerates whitespace.
sanitizer_regex_for() {
  local var="$1"
  # Match: optional ws, case "$var" in '' | *[!0-9]* ) var=0 ;; esac
  # Use printf to safely interpolate var; treat all literals.
  printf '^[[:space:]]*case[[:space:]]+"\\$%s"[[:space:]]+in[[:space:]]+'\'''\''[[:space:]]*\\|[[:space:]]*\*\[!0-9\]\*[[:space:]]*\\)[[:space:]]+%s=0[[:space:]]*;;[[:space:]]+esac[[:space:]]*$' "$var" "$var"
}

VIOLATIONS=0
LIST_ROWS=""

should_skip_file() {
  local f="$1"
  # Skip the linter itself.
  [ "$f" = "$SELF_PATH" ] && return 0
  # Skip the linter's own test (it contains deliberate bad fixtures
  # built inline, but the script file itself doesn't host the bad
  # lines — defensive though).
  case "$(basename "$f")" in
    "${TEST_FIXTURE_PATTERN}.sh") return 0 ;;
  esac
  # Skip docs/, templates/, Reports/, .git/ — these directories don't
  # appear in TARGET_GLOBS but we double-check by path.
  case "$f" in
    "$REPO_ROOT"/docs/*|"$REPO_ROOT"/templates/*|"$REPO_ROOT"/Reports/*|"$REPO_ROOT"/.git/*) return 0 ;;
  esac
  return 1
}

scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  should_skip_file "$file" && return 0

  # Read all lines into an array so we can look at N+1.
  local -a LINES=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    LINES+=("$line")
  done < "$file"

  local i n
  n=${#LINES[@]}
  for ((i = 0; i < n; i++)); do
    line="${LINES[i]}"
    # Skip lines that are pure comments (no var=$( ... ) shape).
    case "${line#"${line%%[![:space:]]*}"}" in
      '#'*) continue ;;
    esac

    if echo "$line" | grep -Eq "$ANTIPATTERN_RE"; then
      # Parse var name + allowlist.
      local parsed var_name allow_reason has_marker
      parsed=$(parse_line "$line")
      var_name="$(printf '%s' "$parsed" | cut -f1)"
      allow_reason="$(printf '%s' "$parsed" | cut -f2)"
      has_marker="$(printf '%s' "$parsed" | cut -f3)"

      local lineno=$((i + 1))
      local rel="${file#"$REPO_ROOT"/}"

      if [ "$has_marker" = "1" ]; then
        if [ -z "$allow_reason" ]; then
          echo "${rel}:${lineno}: lint-counter-antipattern: allowlist marker present but reason is empty (var=$var_name)" >&2
          VIOLATIONS=$((VIOLATIONS + 1))
          LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\t${var_name}\tallowlist-empty-reason\n"
        else
          LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\t${var_name}\tallowlist:${allow_reason}\n"
        fi
        continue
      fi

      # Check next line for the case-statement sanitizer with matching var.
      local next="${LINES[i+1]:-}"
      local sanitizer_re
      sanitizer_re="$(sanitizer_regex_for "$var_name")"
      if echo "$next" | grep -Eq "$sanitizer_re"; then
        LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\t${var_name}\tsanitized\n"
      else
        # Identify the failure subtype for a clearer message.
        local subtype="missing-sanitizer"
        # If next line is ALSO a case statement but for a different var,
        # call that out — that's the copy-paste bug class T5 protects.
        if echo "$next" | grep -Eq '^[[:space:]]*case[[:space:]]+"\$[A-Za-z_][A-Za-z0-9_]*"[[:space:]]+in[[:space:]]+'\'''\''[[:space:]]*\|'; then
          subtype="sanitizer-var-mismatch"
          echo "${rel}:${lineno}: lint-counter-antipattern: capture of '\$${var_name}' is not sanitized — next-line case-statement uses a different var name" >&2
        else
          echo "${rel}:${lineno}: lint-counter-antipattern: capture of '\$${var_name}' is not sanitized — add 'case \"\$${var_name}\" in '\'''\''|*[!0-9]*) ${var_name}=0 ;; esac' on the next line, or append '# lint-counter-antipattern: allow <reason>'" >&2
        fi
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\t${var_name}\t${subtype}\n"
      fi
    fi
  done
}

for entry in "${TARGET_GLOBS[@]}"; do
  # If the glob didn't expand, the literal string with `*` shows up;
  # skip those by testing -e on each candidate.
  [ -e "$entry" ] || continue
  scan_file "$entry"
done

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\tVAR\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS violation(s) found. See scripts/lint-counter-antipattern.sh header for the fix pattern." >&2
  exit 1
fi

echo "OK: no counter-capture antipatterns found."
exit 0

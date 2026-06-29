#!/usr/bin/env bash
# scripts/lint-raw-read-prompt.sh — fail CI when any script outside
# scripts/lib/helpers.sh calls `read -rp` / `read -p` directly. The
# centralized prompt helpers (`prompt_input`, `prompt_yes_no`) handle
# the non-interactive / CI / no-TTY contexts safely; bare `read -p`
# does not, and hangs unattended invocations or silently proceeds
# with empty input.
#
# THE DEFECT CLASS
#   read -rp "Proceed? [y/N]: " yn
#   if [[ "$yn" =~ ^[Yy] ]]; then do_destructive_thing; fi
#
# Under unattended invocation, `read` either blocks forever waiting
# for stdin (when stdin is a pipe with nothing to deliver) or returns
# immediately with empty `yn` (when stdin reaches EOF). Either way,
# the operator never confirmed the action, and side-effectful code
# proceeds with a default that the script author assumed would only
# fire in interactive use. PR #87 (cycle 7) surfaced this class via
# check-phase-gate's prompt_yes_no — this lint backstops the wider
# tree.
#
# CANONICAL FIX
#   if prompt_yes_no "Proceed?" "N"; then do_destructive_thing; fi
#   # ── or ──
#   result=$(prompt_input "Enter name" "anon")
#
# Both helpers live in scripts/lib/helpers.sh and refuse to block in
# non-interactive contexts (no TTY on stdin, CI=true,
# SOIF_NONINTERACTIVE=true), returning the safe default instead.
#
# DELIBERATE SCOPE
#   • Targets `read -p` and `read -rp` (any flag combination that
#     INCLUDES `-p`, since `-p` is what makes `read` block on a
#     prompt). `read -r line` without `-p` is the correct portable
#     idiom for line-by-line file parsing (e.g. inside `while IFS=
#     read -r line < file`) and stays out of scope.
#   • EXEMPT FILE: scripts/lib/helpers.sh — the canonical home for
#     the prompt helpers themselves; they MUST call `read -rp` to
#     do their job. No other file is exempt by location.
#
# ALLOWLIST
#   Append `# lint-raw-read-prompt: allow <reason>` to the offending
#   line. Reason is REQUIRED — empty reason fails the lint, matching
#   PR #72's allowlist semantics. Use this for interactive-only
#   wizards (e.g. intake-wizard.sh, which is documented as
#   interactive and gated by upstream TTY checks).
#
# EXIT CODES
#   0 — no violations
#   1 — one or more violations found
#   2 — invocation / I/O error
#
# USAGE
#   bash scripts/lint-raw-read-prompt.sh        # quiet pass/fail
#   bash scripts/lint-raw-read-prompt.sh --list # PASS/FAIL table

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)/.."
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
SELF_PATH="$REPO_ROOT/scripts/lint-raw-read-prompt.sh"
HELPERS_PATH="$REPO_ROOT/scripts/lib/helpers.sh"
TEST_FIXTURE_PATTERN="test-lint-raw-read-prompt"

LIST_MODE=0
if [ "${1:-}" = "--list" ]; then
  LIST_MODE=1
elif [ -n "${1:-}" ]; then
  echo "Usage: $0 [--list]" >&2
  exit 2
fi

TARGET_GLOBS=(
  "$REPO_ROOT/scripts"/*.sh
  "$REPO_ROOT/scripts/lib"/*.sh
  "$REPO_ROOT/scripts/hooks"/*.sh
  "$REPO_ROOT/scripts/host-drivers"/*.sh
  "$REPO_ROOT/init.sh"
)

# Match `read` invocations that include the `-p` flag. Recognize:
#   • Single-bundle short flags containing `p`: `-p`, `-rp`, `-pr`,
#     `-rsp`, `-sp`, etc.
#   • Compact `-p"prompt"` (no space between `-p` and its quoted/raw
#     value — bash accepts both shapes).
#   • Multi-flag invocations where `-p` appears in a SEPARATE bundle
#     from `-r` / `-s`: `read -s -p "..." v`, `read -r -p ...`.
# We anchor on the `read` command word with a leading word boundary
# (start-of-line / whitespace / `;` / `!` / `(`) so the substring
# `bread` etc. doesn't match. We do NOT match `read --long-form`
# style: bash `read` has no `--silent` / `--prompt` long form
# (verified against bash 5.2 builtin help), so the verifier's
# `read --silent -p ...` concern is moot — `bash` would error
# "read: --: invalid option" before ever reading stdin.
#
# Supported flag-bundle shapes (in order of detection):
#   1. `read -[A-Za-z]*p[A-Za-z]*` (any bundle containing `p`,
#      optional whitespace OR a quote/letter for compact `-p"..."`)
#   2. `read [-s|-r|-rs|-sr]+ -[A-Za-z]*p[A-Za-z]*` (multi-bundle:
#      another short-flag bundle, whitespace, then a `-p`-bundle)
#
# Test fixtures for the wider patterns live in
# tests/test-lint-raw-read-prompt.sh (N1..N3 added in the PR-#96
# follow-up).
READ_PROMPT_RE='(^|[[:space:]]|;|!|\()read[[:space:]]+(-[A-Za-z]*[[:space:]]+)*-[A-Za-z]*p[A-Za-z]*([[:space:]"'"'"']|$)'

VIOLATIONS=0
LIST_ROWS=""

should_skip_file() {
  local f="$1"
  [ "$f" = "$SELF_PATH" ] && return 0
  [ "$f" = "$HELPERS_PATH" ] && return 0
  case "$(basename "$f")" in
    "${TEST_FIXTURE_PATTERN}.sh") return 0 ;;
  esac
  case "$f" in
    "$REPO_ROOT"/docs/*|"$REPO_ROOT"/templates/*|"$REPO_ROOT"/Reports/*|"$REPO_ROOT"/.git/*) return 0 ;;
  esac
  return 1
}

parse_allowlist() {
  local line="$1"
  local marker_reason=""
  local has_marker=0
  case "$line" in
    *"# lint-raw-read-prompt: allow"*)
      has_marker=1
      marker_reason="${line##*# lint-raw-read-prompt: allow}"
      marker_reason="${marker_reason#"${marker_reason%%[![:space:]]*}"}"
      marker_reason="${marker_reason%"${marker_reason##*[![:space:]]}"}"
      ;;
  esac
  printf '%d\t%s\n' "$has_marker" "$marker_reason"
}

scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  should_skip_file "$file" && return 0

  local -a LINES=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    LINES+=("$line")
  done < "$file"

  local i n=${#LINES[@]}
  for ((i = 0; i < n; i++)); do
    line="${LINES[i]}"
    # Skip pure comment lines.
    case "${line#"${line%%[![:space:]]*}"}" in
      '#'*) continue ;;
    esac
    if echo "$line" | grep -Eq "$READ_PROMPT_RE"; then
      local parsed has_marker allow_reason
      parsed=$(parse_allowlist "$line")
      has_marker="$(printf '%s' "$parsed" | cut -f1)"
      allow_reason="$(printf '%s' "$parsed" | cut -f2)"

      local lineno=$((i + 1))
      local rel="${file#"$REPO_ROOT"/}"

      if [ "$has_marker" = "1" ]; then
        if [ -z "$allow_reason" ]; then
          echo "${rel}:${lineno}: lint-raw-read-prompt: allowlist marker present but reason is empty" >&2
          VIOLATIONS=$((VIOLATIONS + 1))
          LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\tallowlist-empty-reason\n"
        else
          LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\tallowlist:${allow_reason}\n"
        fi
      else
        echo "${rel}:${lineno}: lint-raw-read-prompt: raw 'read -rp' / 'read -p' — migrate to prompt_input / prompt_yes_no (scripts/lib/helpers.sh), or append '# lint-raw-read-prompt: allow <reason>'" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\traw-read-prompt\n"
      fi
    fi
  done
}

for entry in "${TARGET_GLOBS[@]}"; do
  [ -e "$entry" ] || continue
  scan_file "$entry"
done

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS violation(s) found. See scripts/lint-raw-read-prompt.sh header for the migration pattern." >&2
  exit 1
fi

echo "OK: no raw 'read -rp' / 'read -p' calls outside scripts/lib/helpers.sh."
exit 0

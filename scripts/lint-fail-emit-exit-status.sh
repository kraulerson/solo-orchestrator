#!/usr/bin/env bash
# scripts/lint-fail-emit-exit-status.sh — BL-064 structural backstop.
#
# THE DEFECT CLASS (silent-success after [FAIL])
#   init.sh emits a `[FAIL]` line via `print_fail "..."` and then keeps
#   running through to the "Setup Complete" banner with rc=0. Operators
#   who only check the exit code (or scan for the banner) miss the gap
#   entirely — exactly the scenario branch protection / push verification
#   exists to prevent. See solo-orchestrator-backlog.md BL-064 and
#   Reports/2026-06-29-adversarial-certainty-pass.md § Tailoring signals
#   catalog S-7 for the full history. PR #105 fixed the same defect
#   shape in scripts/intake-wizard.sh:2028.
#
# WHAT THIS LINT ENFORCES IN init.sh
#   Every `print_fail "..."` line in init.sh must, on its own line, be
#   one of:
#     (a) terminated inline:        `; exit ` or `; return `
#     (b) followed within 2 lines:  `exit ` or `return 1` (or `return $N`)
#     (c) followed within 2 lines:  `record_init_failure ...` (BL-064 helper)
#     (d) explicitly allowed:       a same-line `# lint-fail-emit-exit-
#         status: allow <reason>` annotation with a non-empty <reason>.
#
#   The structural rule is: every [FAIL] emit must either propagate to
#   the script's exit status (via terminal exit/return) OR be explicitly
#   commented as a recoverable / non-fatal status diagnostic.
#
# WHAT THIS LINT DOES NOT ENFORCE
#   • Other scripts that use print_fail — those have their own callers
#     and exit-status contracts. The silent-success defect that BL-064
#     remediates was specific to init.sh's "Setup Complete" banner.
#     Future expansion to other operator-facing scripts is welcome but
#     out of BL-064 scope.
#   • Heredocs that contain the literal string "[FAIL]" (e.g. the
#     non-interactive help block in init.sh). The regex anchors on
#     `print_fail` invocations, not on `[FAIL]` strings, so this is
#     a non-issue.
#
# ALLOWLIST FORMAT
#   Append `# lint-fail-emit-exit-status: allow <reason>` to the
#   `print_fail` line itself (NOT a sibling line). Empty reason fails
#   the lint so reviewers always have justification text to evaluate.
#
# EXIT CODES
#   0 — no violations
#   1 — one or more violations found
#   2 — invocation / I/O error
#
# USAGE
#   bash scripts/lint-fail-emit-exit-status.sh           # quiet pass/fail
#   bash scripts/lint-fail-emit-exit-status.sh --list    # PASS/FAIL table

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_FILE="$REPO_ROOT/init.sh"

LIST_MODE=0
if [ "${1:-}" = "--list" ]; then
  LIST_MODE=1
elif [ -n "${1:-}" ]; then
  echo "Usage: $0 [--list]" >&2
  exit 2
fi

if [ ! -f "$TARGET_FILE" ]; then
  echo "lint-fail-emit-exit-status: $TARGET_FILE not found" >&2
  exit 2
fi

# Match a `print_fail "..."` invocation anywhere on the line. init.sh
# embeds print_fail in three syntactic shapes:
#   1. Indented statement:                   `    print_fail "..."`
#   2. Same-line compound statement:         `... && { print_fail "..."; return 1; }`
#   3. Short-circuit after `||`:             `cmd || { print_fail "..."; return 1; }`
# The regex requires a word-boundary character (start-of-line, whitespace,
# `{`, `;`, `|`, `&`) immediately before `print_fail` so it doesn't match
# substrings inside identifiers. It also requires a following whitespace +
# `"` so heredoc/comment mentions of the literal word `print_fail` don't
# false-trigger.
PRINT_FAIL_RE='(^|[[:space:]{;|&])print_fail[[:space:]]+"'

# Same-line terminators (matches in any position on the line).
INLINE_TERMINATOR_RE=';[[:space:]]*(exit|return)([[:space:]]|$)'

# Same-line allow marker.
ALLOW_MARKER_RE='# lint-fail-emit-exit-status:[[:space:]]*allow[[:space:]]+'

# Next/next-next line acceptable forms (no leading-content constraint;
# bash/zsh allows arbitrary indentation).
NEXT_LINE_RE='^[[:space:]]*(exit([[:space:]]|$)|return([[:space:]]|$)|record_init_failure([[:space:](]|$))'

VIOLATIONS=0
LIST_ROWS=""

declare -a LINES=()
while IFS= read -r line || [ -n "$line" ]; do
  LINES+=("$line")
done < "$TARGET_FILE"

n=${#LINES[@]}
for ((i = 0; i < n; i++)); do
  line="${LINES[i]}"

  # Skip lines that don't invoke print_fail.
  echo "$line" | grep -Eq "$PRINT_FAIL_RE" || continue

  lineno=$((i + 1))

  # ── (a) inline terminator on this line ──────────────────────────
  if echo "$line" | grep -Eq "$INLINE_TERMINATOR_RE"; then
    LIST_ROWS="${LIST_ROWS}PASS\tinit.sh:${lineno}\tinline-terminator\n"
    continue
  fi

  # ── (d) explicit allow marker on this line ──────────────────────
  if echo "$line" | grep -Eq "$ALLOW_MARKER_RE"; then
    # Extract reason: everything after the marker prefix.
    reason="${line##*# lint-fail-emit-exit-status: allow}"
    # Trim leading/trailing whitespace.
    reason="${reason#"${reason%%[![:space:]]*}"}"
    reason="${reason%"${reason##*[![:space:]]}"}"
    if [ -z "$reason" ]; then
      echo "init.sh:${lineno}: lint-fail-emit-exit-status: allowlist marker present but reason is empty" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      LIST_ROWS="${LIST_ROWS}FAIL\tinit.sh:${lineno}\tallowlist-empty-reason\n"
    else
      LIST_ROWS="${LIST_ROWS}PASS\tinit.sh:${lineno}\tallowlist:${reason}\n"
    fi
    continue
  fi

  # ── (b)/(c) check next two non-blank lines ──────────────────────
  matched=0
  for offset in 1 2; do
    j=$((i + offset))
    [ "$j" -lt "$n" ] || break
    candidate="${LINES[j]}"
    if echo "$candidate" | grep -Eq "$NEXT_LINE_RE"; then
      matched=1
      break
    fi
  done
  if [ "$matched" -eq 1 ]; then
    LIST_ROWS="${LIST_ROWS}PASS\tinit.sh:${lineno}\tnext-line-terminator\n"
    continue
  fi

  echo "init.sh:${lineno}: lint-fail-emit-exit-status: print_fail does not propagate to exit status" >&2
  echo "  Add 'exit 1' / 'return 1' / 'record_init_failure ...' within 2 lines," >&2
  echo "  or append '# lint-fail-emit-exit-status: allow <reason>' to this line." >&2
  VIOLATIONS=$((VIOLATIONS + 1))
  LIST_ROWS="${LIST_ROWS}FAIL\tinit.sh:${lineno}\tno-terminator-no-allow\n"
done

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS violation(s) found. See scripts/lint-fail-emit-exit-status.sh header for the fix pattern." >&2
  exit 1
fi

echo "OK: every print_fail in init.sh propagates to exit status (or is annotated)."
exit 0

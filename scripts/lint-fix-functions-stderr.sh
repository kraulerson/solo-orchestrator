#!/usr/bin/env bash
# scripts/lint-fix-functions-stderr.sh — fail CI when any function
# whose name starts with `fix_` silences stderr internally via
# `2>/dev/null` or `2>&-`.
#
# THE DEFECT CLASS
#   fix_*() auto-fix functions in scripts/verify-install.sh (and any
#   other script that owns operator-facing remediation) silenced their
#   own stderr. When the underlying command failed (auth prompt,
#   network error, missing dep, hostile DNS) the operator saw a
#   "fix returned non-zero" with NO diagnostic — making the issue
#   un-actionable. See PR #92 (commit 6917fd2f) for the scrub of
#   fix_framework_clone, fix_framework_manifest, fix_superpowers; the
#   verifier follow-up on code-verify-reconfigure-14 surfaced the
#   class. This lint is the wave-3 backstop that keeps the scrub
#   from regressing.
#
# DELIBERATE SCOPE
#   • Walks scripts/*.sh, scripts/lib/*.sh, scripts/hooks/*.sh,
#     scripts/host-drivers/*.sh, init.sh — the operator-facing surface
#     where fix_*() functions actually live.
#   • Reads each file line by line, tracks bash function nesting by
#     basename: when a line opens a `fix_<ident>()` function, mark
#     in-fix and snapshot the depth-zero brace balance; when the
#     balance returns to zero, exit the fix function.
#   • Skips lines that are pure comments (leading `#`).
#   • Skips lines that live inside an open heredoc body (e.g.
#     `cat > .git/hooks/pre-commit << 'HOOKEOF' ... HOOKEOF`). The
#     fix function's OWN logic is what we want to lint — the content
#     of a heredoc body is written to ANOTHER file at runtime and
#     belongs to that file's lint context, not this one. Heredoc
#     detection supports `<<DELIM` and `<<'DELIM'` / `<<"DELIM"`
#     with optional `-` for tab-stripping (`<<-DELIM`).
#
# ALLOWLIST
#   Append `# lint-fix-functions-stderr: allow <reason>` to the
#   offending line. Reason is REQUIRED — empty reason fails the lint,
#   matching PR #72's allowlist semantics. Use this when a fix
#   function intentionally suppresses stderr because the diagnostic
#   was captured separately upstream (rare — most uses are bugs).
#
# EXIT CODES
#   0 — no violations
#   1 — one or more violations found
#   2 — invocation / I/O error
#
# USAGE
#   bash scripts/lint-fix-functions-stderr.sh        # quiet pass/fail
#   bash scripts/lint-fix-functions-stderr.sh --list # PASS/FAIL table

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_PATH="$REPO_ROOT/scripts/lint-fix-functions-stderr.sh"
TEST_FIXTURE_PATTERN="test-lint-fix-functions-stderr"

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

# Match a function-opening line:  fix_<ident>() {
# Tolerates leading whitespace, optional `function ` prefix, trailing
# whitespace before the `{`. Captures the function name in group 1.
FIX_OPEN_RE='^[[:space:]]*(function[[:space:]]+)?(fix_[A-Za-z0-9_-]+)[[:space:]]*\(\)[[:space:]]*\{'

# Match `2>/dev/null` or `2>&-` ANYWHERE on the line (after stripping
# trailing comments). We strip trailing comments so a line like
# `cmd  # see also 2>/dev/null discussion` doesn't false-positive.
STDERR_SILENCER_RE='(2>/dev/null|2>&-)'

VIOLATIONS=0
LIST_ROWS=""

should_skip_file() {
  local f="$1"
  [ "$f" = "$SELF_PATH" ] && return 0
  case "$(basename "$f")" in
    "${TEST_FIXTURE_PATTERN}.sh") return 0 ;;
  esac
  case "$f" in
    "$REPO_ROOT"/docs/*|"$REPO_ROOT"/templates/*|"$REPO_ROOT"/Reports/*|"$REPO_ROOT"/.git/*) return 0 ;;
  esac
  return 1
}

# Strip trailing comment (` #...` to EOL) UNLESS the `#` lives inside
# single or double quotes. Simple pass that scans char-by-char tracking
# quote state. Good enough for the lint surface.
strip_trailing_comment() {
  local line="$1"
  local out=""
  local in_squote=0
  local in_dquote=0
  local i ch prev=""
  local len=${#line}
  for (( i=0; i<len; i++ )); do
    ch="${line:i:1}"
    if [ "$in_squote" = "0" ] && [ "$in_dquote" = "0" ] && [ "$ch" = "#" ]; then
      # only treat as comment if preceded by whitespace or at column 0
      if [ -z "$prev" ] || [[ "$prev" =~ [[:space:]] ]]; then
        break
      fi
    fi
    if [ "$in_dquote" = "0" ] && [ "$ch" = "'" ]; then
      in_squote=$((1 - in_squote))
    elif [ "$in_squote" = "0" ] && [ "$ch" = '"' ]; then
      in_dquote=$((1 - in_dquote))
    fi
    out="${out}${ch}"
    prev="$ch"
  done
  printf '%s' "$out"
}

# Extract the (optional) heredoc opening tag from a line. Returns the
# tag name (without quotes) on stdout if a heredoc is opened, or empty
# string if not. Supports `<<TAG`, `<<-TAG`, `<<'TAG'`, `<<"TAG"`.
heredoc_open_tag() {
  local line="$1"
  # Strip trailing comment first so `# << ...` isn't confused.
  line=$(strip_trailing_comment "$line")
  # Look for the LAST heredoc operator on the line (closest to EOL).
  # Regex: <<-? optional whitespace, then ('TAG'|"TAG"|TAG)
  if [[ "$line" =~ \<\<-?[[:space:]]*\'([A-Za-z_][A-Za-z0-9_]*)\' ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$line" =~ \<\<-?[[:space:]]*\"([A-Za-z_][A-Za-z0-9_]*)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$line" =~ \<\<-?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  printf ''
}

# Count `{` minus `}` outside quotes — simple structural counter for
# tracking when a fix function body ends. Good enough for the shapes
# the framework actually uses (no embedded brace strings in fix bodies).
brace_delta() {
  local line="$1"
  # Strip trailing comment.
  line=$(strip_trailing_comment "$line")
  local i ch in_squote=0 in_dquote=0 open=0 close=0
  local len=${#line}
  for (( i=0; i<len; i++ )); do
    ch="${line:i:1}"
    if [ "$in_dquote" = "0" ] && [ "$ch" = "'" ]; then
      in_squote=$((1 - in_squote))
      continue
    fi
    if [ "$in_squote" = "0" ] && [ "$ch" = '"' ]; then
      in_dquote=$((1 - in_dquote))
      continue
    fi
    if [ "$in_squote" = "0" ] && [ "$in_dquote" = "0" ]; then
      [ "$ch" = "{" ] && open=$((open + 1))
      [ "$ch" = "}" ] && close=$((close + 1))
    fi
  done
  printf '%d' $((open - close))
}

parse_allowlist() {
  local line="$1"
  local marker_reason=""
  local has_marker=0
  case "$line" in
    *"# lint-fix-functions-stderr: allow"*)
      has_marker=1
      marker_reason="${line##*# lint-fix-functions-stderr: allow}"
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
  local in_fix=0
  local fix_name=""
  local depth=0
  local heredoc_tag=""

  for ((i = 0; i < n; i++)); do
    line="${LINES[i]}"
    local lineno=$((i + 1))
    local rel="${file#"$REPO_ROOT"/}"

    # Heredoc termination check.
    if [ -n "$heredoc_tag" ]; then
      # Heredoc terminator: the tag alone on a line (optionally with
      # leading tabs for <<- form). Strip leading tabs only.
      local stripped="${line#"${line%%[![:space:]]*}"}"
      # Actually <<- only strips leading tabs not spaces; permissive enough.
      if [ "$stripped" = "$heredoc_tag" ] || [ "${line//$'\t'/}" = "$heredoc_tag" ] || [ "$line" = "$heredoc_tag" ]; then
        heredoc_tag=""
      fi
      continue
    fi

    # Pure-comment line: skip detection (but still let brace_delta
    # handle braces if any — comments have no real braces).
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    local is_comment=0
    case "$trimmed" in
      '#'*) is_comment=1 ;;
    esac

    # Detect fix_*() opening BEFORE heredoc handling so a function
    # whose first line is `fix_foo() { ... <<EOF` correctly marks
    # both the in-fix state and the heredoc.
    if [ "$in_fix" = "0" ] && [[ "$line" =~ $FIX_OPEN_RE ]]; then
      in_fix=1
      fix_name="${BASH_REMATCH[2]}"
      depth=$(brace_delta "$line")
      # A new heredoc might open on the same line.
      local maybe_tag
      maybe_tag=$(heredoc_open_tag "$line")
      [ -n "$maybe_tag" ] && heredoc_tag="$maybe_tag"
      continue
    fi

    if [ "$in_fix" = "1" ]; then
      # Track heredoc opening on this line BEFORE running the violation
      # check — if the silencer occurs in the SAME line that opens a
      # heredoc, the silencer is in the host script context (e.g.
      # `cat > /tmp/x 2>/dev/null << EOF`), which IS a bug. So we
      # check violations first, then update heredoc state.
      if [ "$is_comment" = "0" ]; then
        local stripped_line
        stripped_line=$(strip_trailing_comment "$line")
        if printf '%s' "$stripped_line" | grep -Eq "$STDERR_SILENCER_RE"; then
          # Check allowlist marker.
          local parsed has_marker allow_reason
          parsed=$(parse_allowlist "$line")
          has_marker="$(printf '%s' "$parsed" | cut -f1)"
          allow_reason="$(printf '%s' "$parsed" | cut -f2)"

          if [ "$has_marker" = "1" ]; then
            if [ -z "$allow_reason" ]; then
              echo "${rel}:${lineno}: lint-fix-functions-stderr: allowlist marker present but reason is empty (func=$fix_name)" >&2
              VIOLATIONS=$((VIOLATIONS + 1))
              LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\t${fix_name}\tallowlist-empty-reason\n"
            else
              LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\t${fix_name}\tallowlist:${allow_reason}\n"
            fi
          else
            echo "${rel}:${lineno}: lint-fix-functions-stderr: stderr silencer inside fix function '${fix_name}' — surface the diagnostic so operators can act on it, or append '# lint-fix-functions-stderr: allow <reason>' with justification" >&2
            VIOLATIONS=$((VIOLATIONS + 1))
            LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\t${fix_name}\tstderr-silencer\n"
          fi
        fi
      fi

      # Now track heredoc opening on this line.
      local maybe_tag
      maybe_tag=$(heredoc_open_tag "$line")
      [ -n "$maybe_tag" ] && heredoc_tag="$maybe_tag"

      # Brace balance.
      local delta
      delta=$(brace_delta "$line")
      depth=$((depth + delta))
      if [ "$depth" -le 0 ]; then
        in_fix=0
        fix_name=""
        depth=0
      fi
    fi
  done
}

for entry in "${TARGET_GLOBS[@]}"; do
  [ -e "$entry" ] || continue
  scan_file "$entry"
done

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\tFUNC\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS violation(s) found. See scripts/lint-fix-functions-stderr.sh header for the fix pattern." >&2
  exit 1
fi

echo "OK: no fix_*() stderr silencers found."
exit 0

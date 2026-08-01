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

# BL-121: GNU-only sed alternation. In a BASIC-regex sed program a
# backslash-pipe is alternation on GNU but the LITERAL two characters on
# BSD/macOS — a range like /A/,/B/p whose terminator carries it never
# closes on a Mac and runs to EOF (the MVP-Cutline counter reported 68
# items vs the true 3 and hard-blocked the production 3→4 gate,
# Dogfood-2 F-DF2-011). `sed -E`/`-r`/`--regexp-extended` invocations
# are exempt: in ERE mode a backslash-pipe is an ESCAPED LITERAL pipe —
# the correct idiom for parsing |-delimited Markdown tables
# (check-phase-gate.sh's approval-row cells do exactly that). The
# `[^;|&]*` run keeps the match inside the sed invocation: a shell
# pipe/`;`/`&` before the backslash-pipe means it belongs to a LATER
# command (e.g. `sed ... | grep 'a\|b'` is grep's problem, not sed's).
# Escape hatch: the same `# lint-counter-antipattern: allow <reason>`
# marker as the counter rule.
SED_BRE_ALT_RE='(^|[^A-Za-z0-9_])sed[[:space:]][^;|&]*\\\|'
SED_ERE_FLAG_RE='(^|[^A-Za-z0-9_])sed[[:space:]]+(-[A-Za-z]*[Er][A-Za-z]*([[:space:]]|$)|--regexp-extended([[:space:]]|$))'

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

# ── BL-191-SINGLE-PASS-SCAN ───────────────────────────────────────────
# scan_file matches ONE `grep -naE` pass per RULE per FILE. It used to
# run `echo "$line" | grep -Eq "$RE"` for EVERY line of every walked
# file — ~100k lines across the walk, two pipelines each, on the order
# of 400k forks. Measured cost of one full-tree scan before this
# rewrite: 243s on ubuntu-latest (BL-191), ~300s on the macOS host.
#
# WHAT DID NOT CHANGE — this is a fork-count rewrite, not a rule
# rewrite. The matcher is still `grep -E`, the regex constants are
# untouched, and each rule still sees the raw bytes of one whole line,
# so verdicts, diagnostic text, line numbers and LIST_ROWS order are
# byte-identical. Deliberately NOT awk: keeping grep -E keeps the ENGINE
# identical across the rewrite (that is what makes byte-identity
# provable rather than argued), and it sidesteps the gawk / mawk /
# BSD-awk divergence this file already exists to police (BL-121).
#
# `-a` (--text; GNU and BSD grep both have it) is load-bearing. Whole-
# file grep can classify a file with an invalid multibyte sequence as
# binary and print "Binary file … matches" INSTEAD of numbered lines;
# the old per-line form fed grep one already-decoded line on stdin and
# so never met that path. `-a` pins the text path unconditionally.
#
# THE TWO `continue`s of the old per-line loop are load-bearing and are
# preserved verbatim as `do_sed=0` / the comment short-circuit below:
#   1. a pure-comment line is skipped for BOTH rules (the counter regex
#      is ^-anchored to an identifier so it can never match a comment,
#      but the sed regex is unanchored — the skip is all that holds it
#      off);
#   2. a line whose counter capture carries an allowlist marker is NOT
#      evaluated against the BL-121 sed rule at all — marker or empty
#      reason alike.
# Both are pinned by T14/T15/T18 in tests/test-lint-counter-antipattern.sh.
scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  should_skip_file "$file" && return 0

  # BL-191-UNREADABLE-IS-EXIT-2. The rule passes below originally carried
  # `2>/dev/null`, which turned an UNREADABLE target into a SILENT clean
  # pass: grep's diagnostic suppressed, zero hits recorded, file reported
  # fine. The pre-BL-191 loop was false-clean on this path too, but
  # LOUDLY — bash printed its own redirect error. Silence is the worse
  # failure mode, and this script's header already documents
  # `2 — invocation / I/O error`, so honour that contract instead of
  # guessing about a file we cannot read. The `2>/dev/null`s are gone
  # with it, so any residual grep diagnostic now surfaces. T22 pins this.
  if [ ! -r "$file" ]; then
    echo "lint-counter-antipattern: cannot read ${file} — refusing to report it clean" >&2
    exit 2
  fi

  local rel="${file#"$REPO_ROOT"/}"

  # Rule-level whole-file passes. grep -n emits `LINENO:CONTENT`; the
  # single-file form never prefixes a filename, so `%%:*` / `#*:` split
  # it exactly.
  local -a ANTI_NO=() ANTI_TXT=()
  local -a SED_NO=() SED_TXT=()
  local SED_ERE_SET=":"
  local hit

  while IFS= read -r hit || [ -n "$hit" ]; do
    ANTI_NO+=("${hit%%:*}")
    ANTI_TXT+=("${hit#*:}")
  done < <(grep -naE "$ANTIPATTERN_RE" "$file")

  while IFS= read -r hit || [ -n "$hit" ]; do
    SED_NO+=("${hit%%:*}")
    SED_TXT+=("${hit#*:}")
  done < <(grep -naE "$SED_BRE_ALT_RE" "$file")

  local an=${#ANTI_NO[@]} bn=${#SED_NO[@]}
  [ "$an" -eq 0 ] && [ "$bn" -eq 0 ] && return 0

  # The `sed -E` exemption is evaluated PER LINE (T19), so it needs the
  # exempt line NUMBERS, not a whole-file boolean. Only worth a fork
  # where the basic-mode rule actually hit.
  if [ "$bn" -gt 0 ]; then
    while IFS= read -r hit || [ -n "$hit" ]; do
      SED_ERE_SET="${SED_ERE_SET}${hit%%:*}:"
    done < <(grep -naE "$SED_ERE_FLAG_RE" "$file")
  fi

  # The N+1 sanitizer lookahead still needs the file body, and it must
  # be the SAME `read -r` decode the old loop used. Load it lazily: on
  # the current tree only 34 of 243 walked files have a counter hit.
  local -a LINES=()
  local lines_loaded=0

  # Ordered merge of the two hit lists. grep emits ascending line
  # numbers, so a two-index walk reproduces the old single for-loop's
  # visit order exactly, including "counter rule before sed rule" when
  # one line trips both.
  local ai=0 bi=0
  local lineno line do_anti do_sed
  while [ "$ai" -lt "$an" ] || [ "$bi" -lt "$bn" ]; do
    do_anti=0
    do_sed=0
    if [ "$ai" -lt "$an" ] && { [ "$bi" -ge "$bn" ] || [ "${ANTI_NO[$ai]}" -le "${SED_NO[$bi]}" ]; }; then
      lineno="${ANTI_NO[$ai]}"
      line="${ANTI_TXT[$ai]}"
      do_anti=1
      ai=$((ai + 1))
      if [ "$bi" -lt "$bn" ] && [ "${SED_NO[$bi]}" -eq "$lineno" ]; then
        do_sed=1
        bi=$((bi + 1))
      fi
    else
      lineno="${SED_NO[$bi]}"
      line="${SED_TXT[$bi]}"
      do_sed=1
      bi=$((bi + 1))
    fi

    # Skip lines that are pure comments (no var=$( ... ) shape).
    case "${line#"${line%%[![:space:]]*}"}" in
      '#'*) continue ;;
    esac

    if [ "$do_anti" -eq 1 ]; then
      # Parse var name + allowlist.
      local parsed var_name allow_reason has_marker
      parsed=$(parse_line "$line")
      var_name="$(printf '%s' "$parsed" | cut -f1)"
      allow_reason="$(printf '%s' "$parsed" | cut -f2)"
      has_marker="$(printf '%s' "$parsed" | cut -f3)"

      if [ "$has_marker" = "1" ]; then
        if [ -z "$allow_reason" ]; then
          echo "${rel}:${lineno}: lint-counter-antipattern: allowlist marker present but reason is empty (var=$var_name)" >&2
          VIOLATIONS=$((VIOLATIONS + 1))
          LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\t${var_name}\tallowlist-empty-reason\n"
        else
          LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\t${var_name}\tallowlist:${allow_reason}\n"
        fi
        # The old per-line loop `continue`d here, which ALSO skipped the
        # BL-121 sed rule for this line — on BOTH arms above, marker with
        # a reason and marker with an empty one alike. Dropping this is
        # the one silent divergence a merged walk invites, and it is
        # invisible on a clean tree (main has zero sed-alternation rows).
        # T14 pins it. # BL-191-ALLOWLIST-SHORT-CIRCUIT
        do_sed=0
      else
        # Check next line for the case-statement sanitizer with matching var.
        if [ "$lines_loaded" -eq 0 ]; then
          local body_line
          while IFS= read -r body_line || [ -n "$body_line" ]; do
            LINES+=("$body_line")
          done < "$file"
          lines_loaded=1
        fi
        # LINES is 0-based, so element [$lineno] IS line $lineno+1.
        local next="${LINES[$lineno]:-}"
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
    fi

    # BL-121: basic-mode sed alternation (constants + rationale at
    # SED_BRE_ALT_RE above). Independent of the counter-capture rule — a
    # line can violate either.
    case "$SED_ERE_SET" in
      *":${lineno}:"*) do_sed=0 ;;
    esac
    if [ "$do_sed" -eq 1 ]; then
      local sparsed sreason smarker
      sparsed=$(parse_line "$line")
      sreason="$(printf '%s' "$sparsed" | cut -f2)"
      smarker="$(printf '%s' "$sparsed" | cut -f3)"
      if [ "$smarker" = "1" ] && [ -n "$sreason" ]; then
        LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\tsed-alternation\tallowlist:${sreason}\n"
      else
        echo "${rel}:${lineno}: lint-counter-antipattern: GNU-only sed alternation — a backslash-pipe in a BASIC-regex sed program is alternation on GNU but a LITERAL on BSD/macOS, so a range terminator carrying it never matches and the range runs to EOF (BL-121). Use an awk range/ERE, or sed -E with a real alternation, or append '# lint-counter-antipattern: allow <reason>'" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\tsed-alternation\tgnu-only-sed-alternation\n"
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

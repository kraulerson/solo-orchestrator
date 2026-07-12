#!/usr/bin/env bash
# scripts/lint-evalprompts-portability.sh — BL-103 structural backstop.
#
# THE DEFECT CLASS (bash-4-isms in the eval generators)
#   evaluation-prompts/ ships the six-reviewer generator the Phase 3→4 review
#   gate (BL-073) tells operators to run:
#
#     [FAIL] Phase 3→4 review gate: track=standard requires the Security AND
#            Red Team reviews before Phase 4.
#       Run reviews: evaluation-prompts/Projects/run-reviews.sh
#
#   That script — and compose.sh beside it, and the Framework runner — used
#   `declare -A` (associative arrays) and `[[ -v x ]]`, both bash >= 4.2. macOS
#   ships /bin/bash 3.2.57 and it is THIS repo's reference platform (CLAUDE.md
#   § ENVIRONMENT TRAPS bans both constructs outright). So the remediation the
#   gate handed the operator did not merely misbehave, it did not PARSE:
#
#     $ /bin/bash -n evaluation-prompts/Projects/run-reviews.sh
#     run-reviews.sh: line 142: syntax error near `"REVIEWERS[$num]"'
#
#   The repo's other portability rules are enforced by tests and lints over
#   scripts/ and init.sh. NOTHING covered evaluation-prompts/ — which is exactly
#   why three shipped scripts sat broken. This lint closes that hole.
#
# WHAT IT ENFORCES — for every evaluation-prompts/**/*.sh
#   1. It PARSES under /bin/bash. Run with the real /bin/bash (3.2.57 on the
#      reference host) so the check is an oracle, not a proxy: if the host's
#      bash cannot parse it, the operator's bash cannot run it.
#   2. No `declare -A` — associative arrays are bash >= 4.0.
#   3. No `[[ -v x ]]` / `[[ ! -v x ]]` — the -v unary is bash >= 4.2.
#
#   Checks 2 and 3 exist because a bash-4-ism can be syntactically parseable
#   under 3.2 and still fail at RUNTIME (`declare -A REVIEWERS` parses fine; it
#   dies with "declare: -A: invalid option" the moment it executes). `bash -n`
#   alone would have missed it.
#
# WHAT IT DOES NOT DO
#   It is not a general shell linter (no shellcheck, no quoting rules). It pins
#   the three portability invariants the reference platform actually enforces.
#
# USAGE
#   bash scripts/lint-evalprompts-portability.sh                # lint the repo
#   bash scripts/lint-evalprompts-portability.sh --root <dir>   # lint <dir>/evaluation-prompts
#   bash scripts/lint-evalprompts-portability.sh --list         # PASS/FAIL inventory
#   bash scripts/lint-evalprompts-portability.sh --help
#
#   --root exists for TESTABILITY: tests/test-bl103-eval-generator.sh copies the
#   tree to a scratch dir, plants a `declare -A` / `[[ -v ]]` / syntax error, and
#   proves this lint goes RED — a behavioural mutation proof, not a marker grep.
#
# EXIT CODES
#   0 — every scanned script is bash-3.2 clean (or there is nothing to scan)
#   1 — one or more violations
#   2 — invocation error

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$REPO_ROOT"
DO_LIST=0

# The reference shell. macOS /bin/bash is 3.2.57 — the platform the ban exists
# for. Fall back to `bash` only if /bin/bash is somehow absent (e.g. an exotic
# CI image); on GitHub's ubuntu runners /bin/bash is bash 5, which still catches
# every violation via the declare -A / [[ -v ]] greps below.
REF_BASH="/bin/bash"
[ -x "$REF_BASH" ] || REF_BASH="$(command -v bash)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      if [ $# -lt 2 ]; then
        echo "[FAIL] --root requires a directory argument" >&2
        exit 2
      fi
      ROOT="$2"
      shift 2
      ;;
    --root=*)
      ROOT="${1#--root=}"
      shift
      ;;
    --list)
      DO_LIST=1
      shift
      ;;
    --help|-h)
      sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[FAIL] Unknown argument: '$1' (try --help)" >&2
      exit 2
      ;;
  esac
done

EVAL_DIR="$ROOT/evaluation-prompts"

if [ ! -d "$EVAL_DIR" ]; then
  echo "[OK] lint-evalprompts-portability: no evaluation-prompts/ under '$ROOT' — nothing to scan."
  exit 0
fi

violations=""
scanned=0
clean=0

# CODE, NOT PROSE — but FAIL CLOSED. Blank out FULL-LINE comments only, keeping
# the line COUNT intact so grep -n still yields true line numbers. This exempts
# the header comments that DOCUMENT the ban (a lint you cannot describe in a
# comment is a lint people work around).
#
# Trailing comments are deliberately NOT stripped. A quote-unaware trailing-comment
# stripper (`s/[[:space:]]#.*$//`) blanks everything after ANY whitespace-preceded
# `#` — including one inside a string — so a banned construct sharing that line
# would be silently missed (PR #187 adversarial review). A lint that can be fooled
# by a `#` in a string is worse than no lint: it reports GREEN over a real
# violation. The cost of failing closed is a trailing comment that names a banned
# construct will trip the lint — put such a mention on its own line instead.
# The `bash -n` arm below reads the unmodified file, so nothing is hidden from
# the parser either way.
code_only() {
  sed -e 's/^[[:space:]]*#.*$//' "$1"
}

# hits_with_context <script> <extended-regex> — print "N: <original line N>" for
# every CODE line matching the regex. Line numbers come from the blanked stream
# (same line count); the text shown is the REAL line, so the diagnostic is
# actionable.
hits_with_context() {
  local f="$1" re="$2" nums n
  nums=$(code_only "$f" | grep -nE "$re" 2>/dev/null | cut -d: -f1)
  [ -n "$nums" ] || return 0
  for n in $nums; do
    printf '      %s: %s\n' "$n" "$(sed -n "${n}p" "$f")"
  done
}

# BL-103-PORTABILITY: the three load-bearing checks. Neutering any one of them
# lets a bash-4-ism back into the generator the Phase 3→4 gate hands operators.
check_script() {
  script_path="$1"
  rel="${script_path#$ROOT/}"
  bad=""

  # (1) Must PARSE under the reference shell (the whole file, comments included).
  parse_err=$("$REF_BASH" -n "$script_path" 2>&1) || \
    bad="${bad}
  [x] $rel — does not parse under $REF_BASH:
$(printf '%s\n' "$parse_err" | sed 's/^/      /')"

  # (2) No associative arrays (bash >= 4.0). Parses under 3.2, dies at RUNTIME
  #     with "declare: -A: invalid option" — so `bash -n` alone cannot catch it.
  decl_hits=$(hits_with_context "$script_path" '(^|[^[:alnum:]_-])declare[[:space:]]+-[A-Za-z]*A([[:space:]]|$)')
  [ -z "$decl_hits" ] || bad="${bad}
  [x] $rel — associative array declaration (bash >= 4.0; banned by CLAUDE.md):
$decl_hits"

  # (3) No [[ -v x ]] / [[ ! -v x ]] (the -v unary is bash >= 4.2). This one IS a
  #     hard syntax error under 3.2, but grep it explicitly so the diagnostic
  #     names the construct instead of a bare "conditional binary operator
  #     expected".
  v_hits=$(hits_with_context "$script_path" '\[\[[[:space:]]+(![[:space:]]*)?-v[[:space:]]')
  [ -z "$v_hits" ] || bad="${bad}
  [x] $rel — the -v unary inside [[ … ]] (bash >= 4.2; use [ -n \"\${x:-}\" ] instead):
$v_hits"

  if [ -n "$bad" ]; then
    violations="${violations}${bad}"
    [ "$DO_LIST" -eq 1 ] && echo "FAIL  $rel"
    return 1
  fi

  [ "$DO_LIST" -eq 1 ] && echo "PASS  $rel"
  return 0
}

[ "$DO_LIST" -eq 1 ] && echo "lint-evalprompts-portability inventory ($EVAL_DIR):"

while IFS= read -r sh; do
  [ -n "$sh" ] || continue
  scanned=$((scanned + 1))
  if check_script "$sh"; then
    clean=$((clean + 1))
  fi
# Scans *.sh and *.bash. KNOWN LIMIT (PR #187 review): an extensionless shell
# script under evaluation-prompts/ would go unscanned. There are none today and
# the three real scripts are all *.sh; a shebang sniff was tried and reverted —
# `case` patterns inside a command substitution inside this heredoc break the
# bash-3.2 parser, and a lint that mis-parses is worse than one with a stated
# limit. If an extensionless script is ever added here, extend this find.
done <<EOF
$(find "$EVAL_DIR" -type f \( -name '*.sh' -o -name '*.bash' \) | LC_ALL=C sort)
EOF

[ "$DO_LIST" -eq 1 ] && echo ""

if [ "$scanned" -eq 0 ]; then
  echo "[OK] lint-evalprompts-portability: no *.sh under $EVAL_DIR — nothing to scan."
  exit 0
fi

if [ -n "$violations" ]; then
  echo "[FAIL] lint-evalprompts-portability: bash-4 constructs in evaluation-prompts/ ($((scanned - clean)) of $scanned script(s)):"
  printf '%s\n' "$violations"
  echo ""
  echo "  These scripts run on the operator's shell. macOS /bin/bash is 3.2.57."
  echo "  Replace 'declare -A' with case dispatch / indexed arrays, and"
  echo "  '[[ -v x ]]' with '[ -n \"\${x:-}\" ]'. See CLAUDE.md § ENVIRONMENT TRAPS."
  exit 1
fi

echo "[OK] lint-evalprompts-portability: $scanned script(s) under evaluation-prompts/ are bash-3.2 clean."
exit 0

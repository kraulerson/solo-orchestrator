#!/usr/bin/env bash
# scripts/lint-no-live-remote-in-tests.sh — fail CI when any test under
# tests/ executes init.sh in a shape that can reach REAL remote-repo
# creation (a live `gh repo create` / `glab repo create` / Bitbucket
# `curl` POST against the operator's authenticated host account).
#
# THE DEFECT CLASS (BL-076)
#   A test invokes the real init.sh non-interactively (or via --dry-run
#   piped stdin) with the DEFAULT --git-host (github) and WITHOUT
#   --no-remote-creation, no --git-host other, and no mocked CLI on PATH:
#
#     bash "$INIT" --non-interactive \
#       --project foo --platform mobile --language typescript \
#       --deployment personal --gov-mode private_poc \
#       --project-dir "$tmp"        # <-- NO --no-remote-creation
#
#   Run in an authenticated-`gh` environment (e.g. an agent running
#   tests/full-project-test-suite.sh), init.sh reaches
#   create_and_protect_remote → host_create_repo → `gh repo create`, and
#   a REAL private repo is created + pushed to the operator's account.
#   This is exactly how `kraulerson/foo` leaked on 2026-07-06. A suite
#   that sprays real repos also cannot be wired into CI.
#
# THE INVARIANT
#   Every init.sh EXECUTION inside tests/ must be provably hermetic. An
#   init run is hermetic when its (backslash-joined) invocation carries
#   at least one of these tokens:
#     --no-remote-creation      skip the host API entirely (init.sh:2066)
#     --dry-run                 no scaffold, no remote
#     --validate-only           argv validation only; exits before scaffold
#     --git-host other          URL-paste path — no CLI, needs a fake
#                               --remote-url; never touches gh/glab/curl
#   ...OR the whole file is mock-driven (defines a write_mock_gh /
#   write_mock_glab / write_mock_curl stub or prepends a $MOCK_DIR to
#   PATH, or sources tests/host-drivers/mock-cli.sh) so gh/glab/curl
#   resolve to a hermetic stub rather than the real CLI.
#
# WHY JOIN CONTINUATIONS
#   Almost every test writes `--no-remote-creation` on the line AFTER the
#   `bash "$INIT" ... \` line. A naive line-by-line scan would false-flag
#   the entire suite. This lint reconstructs each backslash-continued
#   command into one logical line before classifying it.
#
# WHAT COUNTS AS AN "init run"
#   A logical line that references init.sh execution — literal `init.sh`,
#   or a `$INIT` / `$INIT_SH` (any variable assigned an .../init.sh path
#   in the same file) — AND carries a `--non-interactive` or `--dry-run`
#   flag. Static-analysis tests that merely grep/awk/`bash -n` the init.sh
#   SOURCE never carry those run flags, so they are correctly ignored.
#
# ALLOWLIST
#   Append `# lint-no-live-remote: allow <reason>` to the offending
#   logical line's FIRST physical line. Reason is REQUIRED (empty reason
#   fails). Use only if a test genuinely must drive a real host — it
#   should not; prefer --no-remote-creation or the mock CLI.
#
# EXIT CODES
#   0 — no violations
#   1 — one or more violations found
#   2 — invocation / I/O error
#
# USAGE
#   bash scripts/lint-no-live-remote-in-tests.sh        # quiet pass/fail
#   bash scripts/lint-no-live-remote-in-tests.sh --list # PASS/FAIL table
#
# Behavior suite: tests/test-lint-no-live-remote.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_REL="scripts/lint-no-live-remote-in-tests.sh"
TESTS_DIR="$REPO_ROOT/tests"

# The behavior suite writes synthetic bad/good fixtures to a temp dir and
# points this lint at them; the suite file itself contains init-run-shaped
# strings inside heredocs, so exempt it by basename to avoid self-flagging.
SELFTEST_BASENAME="test-lint-no-live-remote.sh"

LIST_MODE=0
SCAN_DIR="$TESTS_DIR"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) LIST_MODE=1 ;;
    --dir)  shift; SCAN_DIR="${1:-}" ;;   # test-only: scan an alternate tree
    *) echo "Usage: $0 [--list] [--dir DIR]" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$SCAN_DIR" ] || { echo "lint-no-live-remote: scan dir not found: $SCAN_DIR" >&2; exit 2; }

VIOLATIONS=0
LIST_ROWS=""

# Tokens that make an init run hermetic.
HERMETIC_RE='(--no-remote-creation|--dry-run|--validate-only|--git-host[[:space:]=]+other)'
# File-level signal that the whole test mocks the host CLI on PATH.
MOCK_FILE_RE='(write_mock_gh|write_mock_glab|write_mock_curl|PATH="\$\{?MOCK_DIR\}?|mock-cli\.sh)'
ALLOW_MARKER='# lint-no-live-remote: allow'

# Collect the set of shell vars a file assigns to an .../init.sh path so
# `"$INIT"` / `"$INIT_SH"` references resolve back to init.sh. Emits a
# newline-separated list of bare var names.
collect_init_vars() {
  grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^#]*/init\.sh' "$1" 2>/dev/null \
    | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=.*/\1/' \
    | sort -u
}

# Does the logical line EXECUTE init.sh? We require the init token to sit
# in genuine command position, not merely appear as substring text inside
# a reporter string (echo/section/pass/fail_ "...init.sh --non-interactive...")
# or a static grep/awk/`bash -n` of the init.sh SOURCE. Two shapes:
#   A) `bash <init-token>`      — bash directly governs an init path/var
#                                 (flags between → e.g. `bash -n "$INIT"`
#                                 syntax check → NOT an exec).
#   B) `<init-var>` as a command word — at line start or after
#      ( ; & | && / a `cd .. &&` / `env ... ` prefix, then the init var
#      followed by whitespace (its first flag).
# $1=buf  $2=pipe-alternation of init var names (never-match sentinel if none)
line_is_init_exec() {
  local buf="$1" var_alt="$2"
  local token="(\\\$\{?(${var_alt})\}?|[^\"'\''[:space:];&|]*/init\.sh)"
  # A: bash directly followed by an init token (no intervening flags).
  if printf '%s' "$buf" | grep -Eq "(^|[^A-Za-z0-9_])bash[[:space:]]+\"?${token}"; then
    return 0
  fi
  # B: init var/path used as a command word.
  if printf '%s' "$buf" | grep -Eq "(^|[(;&|]|&&|env[[:space:]][^;&|]*)[[:space:]]*\"?${token}\"?[[:space:]]"; then
    return 0
  fi
  return 1
}

scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  local rel="${file#"$REPO_ROOT"/}"
  case "$(basename "$file")" in
    "$SELFTEST_BASENAME") return 0 ;;
  esac

  local file_is_mock=0
  if grep -Eq "$MOCK_FILE_RE" "$file" 2>/dev/null; then
    file_is_mock=1
  fi

  local var_alt="" init_var_names="" v
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    var_alt="${var_alt:+$var_alt|}$v"
    init_var_names="${init_var_names:+$init_var_names }$v"
  done < <(collect_init_vars "$file")
  [ -n "$var_alt" ] || var_alt="__NO_INIT_VAR__"

  # Reconstruct backslash-continued commands into single logical lines.
  local phys=0 start=0 buf="" line
  local in_cont=0
  while IFS= read -r line || [ -n "$line" ]; do
    phys=$((phys + 1))
    if [ "$in_cont" -eq 0 ]; then
      start=$phys
      buf="$line"
    else
      buf="$buf $line"
    fi
    # Continuation if the physical line ends in a single trailing backslash.
    case "$line" in
      *\\)
        # strip trailing backslash from the accumulated buffer, keep going
        buf="${buf%\\}"
        in_cont=1
        continue
        ;;
    esac
    in_cont=0

    # Pure-comment logical line? skip.
    local trimmed="${buf#"${buf%%[![:space:]]*}"}"
    case "$trimmed" in '#'*) continue ;; esac

    # Pure-bash pre-filter (PERF, zero subprocess): a logical line can be an
    # init EXECUTION only if it names init.sh literally or references one of
    # this file's init-path vars ($INIT / $INIT_SH / ...). Both patterns in
    # line_is_init_exec require one of those tokens, so skipping lines that
    # contain neither is behavior-preserving — it only avoids spawning the
    # per-line printf|grep pair for the ~99% of lines that can never match.
    # Without this gate the full-tree scan spawns thousands of subprocesses
    # (~100s wall — too slow for the pre-commit gate); with it, a few seconds.
    local _maybe=0 _iv
    case "$buf" in *init.sh*) _maybe=1 ;; esac
    if [ "$_maybe" -eq 0 ] && [ -n "$init_var_names" ]; then
      for _iv in $init_var_names; do
        case "$buf" in
          *"\$$_iv"*|*"\${$_iv}"*) _maybe=1; break ;;
        esac
      done
    fi
    [ "$_maybe" -eq 1 ] || continue

    # Only classify genuine init.sh EXECUTIONS.
    line_is_init_exec "$buf" "$var_alt" || continue

    # It is a real init run. Classify.
    if printf '%s' "$buf" | grep -Eq "$HERMETIC_RE"; then
      LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${start}\thermetic-token\n"
      continue
    fi
    if [ "$file_is_mock" -eq 1 ]; then
      LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${start}\tmock-cli-on-path\n"
      continue
    fi
    case "$buf" in
      *"$ALLOW_MARKER"*)
        local reason="${buf##*"$ALLOW_MARKER"}"
        reason="${reason#"${reason%%[![:space:]]*}"}"
        reason="${reason%"${reason##*[![:space:]]}"}"
        if [ -n "$reason" ]; then
          LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${start}\tallow:${reason}\n"
          continue
        fi
        echo "${rel}:${start}: lint-no-live-remote: allow marker present but reason is empty" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${start}\tallow-empty-reason\n"
        continue
        ;;
    esac

    echo "${rel}:${start}: lint-no-live-remote: init.sh run can reach LIVE remote creation — add --no-remote-creation (or --git-host other + fake --remote-url, or route through a mocked gh/glab/curl). See scripts/lint-no-live-remote-in-tests.sh header (BL-076)." >&2
    VIOLATIONS=$((VIOLATIONS + 1))
    LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${start}\tlive-remote-reachable\n"
  done < "$file"
}

while IFS= read -r f; do
  scan_file "$f"
done < <(find "$SCAN_DIR" -type f -name '*.sh' | sort)

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS non-hermetic init run(s) found. See scripts/lint-no-live-remote-in-tests.sh header (BL-076)." >&2
  exit 1
fi

echo "OK: no test executes init.sh in a shape that can create a real remote."
exit 0

#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Session-Start Version Check
# Checks all tools against minimum versions and latest available.
# Reports status and offers interactive update with user approval.
#
# Usage:
#   scripts/check-versions.sh       # Full check + update prompt
#   scripts/check-versions.sh --help

# Prefer brew-installed tools over system defaults (e.g., macOS ships
# outdated Python, Git, Ruby at /usr/bin). This ensures version checks
# find the user-installed version, not the Xcode/system stub.
BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
if [ -n "$BREW_PREFIX" ] && [ -d "$BREW_PREFIX/bin" ]; then
  export PATH="$BREW_PREFIX/bin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# BL-046: uses print_fail/info/ok/warn + prompt_input/yes_no only — core subset.
if [ -f "$SCRIPT_DIR/lib/helpers-core.sh" ]; then
  source "$SCRIPT_DIR/lib/helpers-core.sh"
else
  if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
  else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
  fi
  print_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
  print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
  print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
  print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
fi

# WALK-ISSUE-003-UPDATE-CMD-BEGIN
# Walk 2026-08-02, ISSUE-003: "Update commands (run manually):" printed the
# RAW jq output of `.install.<key>`, and BL-033 explicitly allows that value to
# be an ARRAY of stages. Colima therefore surfaced as
#     Colima: [ "brew install colima", "brew services start colima" ]
# — a JSON literal under a heading that promises a runnable command. A junior
# cannot tell whether that is one command, two, or an error.
#
# _cv_jq_install_cmd is the jq tail that normalizes the two BL-033 shapes into
# ONE runnable string, joined with ` && ` exactly as
# scripts/resolve-tools.sh's `install_cmd` does — the two readers of the same
# matrix must not disagree about what a multi-stage install means.
#
# _cv_render_update_cmd is the DISPLAY side, shared by the interactive and
# non-interactive printers so they cannot drift: an empty value and a bare URL
# are both NOT commands, and this heading must never present them as if they
# were. A plain string is echoed VERBATIM (the `<name>: <cmd>` grammar that
# tests/test-specs-plans-remaining-quartet.sh::T-CV-MULTIWORD pins).
_cv_jq_install_cmd='if type=="array" then (map(select(type=="string")) | join(" && ")) else . end'

_cv_render_update_cmd() {
  case "${1:-}" in
    "")                 echo "(no install command in the tool matrix — see the tool's own docs)" ;;
    http://*|https://*) echo "see $1" ;;
    *)                  echo "$1" ;;
  esac
}
# WALK-ISSUE-003-UPDATE-CMD-END

# --- Argument parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      echo "Usage: scripts/check-versions.sh [--help]"
      echo ""
      echo "Checks all tools against minimum version requirements and latest"
      echo "available versions. Offers interactive update with user approval."
      echo ""
      echo "Run at the start of every development session."
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Version comparison ---
# Returns 0 if $1 >= $2 (version A meets minimum B)
version_gte() {
  local a="$1" b="$2"
  # Strip common prefixes (v, jq-, etc.)
  a=$(echo "$a" | sed 's/^[^0-9]*//' | sed 's/[^0-9.].*//')
  b=$(echo "$b" | sed 's/^[^0-9]*//' | sed 's/[^0-9.].*//')

  if [ "$a" = "$b" ]; then return 0; fi

  # BL-113: split on '.' WITHOUT setting IFS for the whole function body.
  # `local IFS='.'` is flagged by semgrep `bash.lang.security.ifs-tampering`
  # (a function-scoped IFS still changes word-splitting for every unquoted
  # expansion below it, including any command this function later calls), and
  # a fresh scaffold must pass the framework's own Phase-3 SAST. The
  # command-prefix form scopes IFS to the single `read` builtin — exactly the
  # remediation the rule recommends (`IFS="," read -a my_array`). `read`
  # returns 1 at EOF-without-delimiter, so `|| :` keeps `set -e` happy when a
  # version string is empty.
  local -a av=() bv=()
  IFS='.' read -r -a av <<< "$a" || :
  IFS='.' read -r -a bv <<< "$b" || :
  local max=${#av[@]}
  [ ${#bv[@]} -gt $max ] && max=${#bv[@]}

  for ((i=0; i<max; i++)); do
    local ai=${av[$i]:-0}
    local bi=${bv[$i]:-0}
    if [ "$ai" -gt "$bi" ] 2>/dev/null; then return 0; fi
    if [ "$ai" -lt "$bi" ] 2>/dev/null; then return 1; fi
  done
  return 0
}

# --- Latest version lookup ---
get_latest_version() {
  local method="$1"
  local package="$2"

  case "$method" in
    npm)
      npm view "$package" version 2>/dev/null | tr -d '[:space:]'
      ;;
    pip)
      # Use PyPI JSON API
      curl -s "https://pypi.org/pypi/$package/json" 2>/dev/null | jq -r '.info.version // empty' 2>/dev/null | tr -d '[:space:]'
      ;;
    brew)
      brew info --json=v2 "$package" 2>/dev/null | jq -r '.formulae[0].versions.stable // empty' 2>/dev/null | tr -d '[:space:]'
      ;;
    github_release)
      curl -s "https://api.github.com/repos/$package/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' | tr -d '[:space:]'
      ;;
    git_tag)
      git ls-remote --tags "$package" 2>/dev/null | grep -oP 'refs/tags/v?\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1 | tr -d '[:space:]'
      ;;
    *)
      echo ""
      ;;
  esac
}

# --- Update check handlers ---
# Data-driven update checking for tools that don't use standard version comparison.
# Each tool can have an "update_check" field in the tool matrix with a "method" key.
#
# Returns via globals: UPDATE_CHECK_STATUS ("up_to_date", "behind", "self_updating", "unknown")
#                      UPDATE_CHECK_MSG (human-readable status message)
#                      UPDATE_CHECK_CMD (update command, if applicable)
check_for_update() {
  local method="$1"
  local update_json="$2"

  UPDATE_CHECK_STATUS="unknown"
  UPDATE_CHECK_MSG=""
  UPDATE_CHECK_CMD=""

  case "$method" in
    git_repo)
      local repo_path
      repo_path=$(echo "$update_json" | jq -r '.path // empty')
      # Expand $HOME in path
      repo_path=$(eval echo "$repo_path")

      if [ ! -d "$repo_path/.git" ]; then
        UPDATE_CHECK_STATUS="unknown"
        UPDATE_CHECK_MSG="git repo not found at $repo_path"
        return
      fi

      # Fetch latest from remote (quiet, BOUNDED).
      #
      # BL-234: this comment said "with timeout" for as long as the line
      # existed, above a bare `git fetch` that had none. A comment describing an
      # intention nobody implemented is the same defect as a `[WARN]` label over
      # an `issues` increment (`## BL-104:`) — the text and the behaviour
      # disagree, and readers trust the text. NETWORK_AVAILABLE is a coarse
      # pre-check, not a bound: a reachable host that never answers hangs this
      # script indefinitely, and it runs from a session hook.
      # run_with_timeout is the only bounded runner available — there is no
      # timeout(1)/gtimeout(1) on the dev host (they yield a spurious rc=127).
      #
      # The `command -v run_with_timeout` guard is not defensive padding. This
      # script has a FALLBACK that defines the colours and print_* inline when
      # scripts/lib/helpers-core.sh is missing, and that fallback does NOT define
      # run_with_timeout. Without the guard the bounded call would exit 127,
      # `|| true` would swallow it, and the comparison below would silently run
      # against STALE refs — a fetch that never happened, reported as a currency
      # verdict. That is the precise defect this entry exists to remove, so the
      # unbounded state is reported as "cannot tell" rather than run unbounded
      # (which would hang a session hook) or skipped in silence.
      # AND THE FETCH'S OWN OUTCOME IS PART OF THE ANSWER. `|| true` discarded
      # it, so a fetch that failed WITHIN the bound — offline, remote deleted,
      # auth gone — fell through to compare `HEAD` against an `origin/main` no
      # fetch had refreshed. Reproduced on a clone genuinely one commit behind
      # its (deleted) origin with NETWORK_AVAILABLE=true: verdict `up_to_date`.
      # That is silent false reassurance for CDF and every `git_repo` tool while
      # offline, and it is the same substitution as the unboundable arm below —
      # a currency verdict from a fetch that never landed. Pre-existing, not a
      # regression, and undisclosed until now.
      #
      # THE BOUND IS ONLY A BOUND IF THE SECONDS ARE A NUMBER. Measured:
      # `run_with_timeout abc sleep 3` returns rc 0 after 3039 ms — the
      # `[ "$elapsed" -ge "$secs" ]` test errors on every iteration, the kill
      # never fires, and the caller's `>/dev/null 2>&1` swallows the complaint.
      # A garbage SOLO_FETCH_TIMEOUT would therefore UNBOUND this fetch in
      # silence: the resurrected defect, one env var away. The two sibling call
      # sites (`_soif_fresh_fetch_secs`, `qdrant_probe_reachable`) already
      # validate their seconds; this one did not.
      if [ "$NETWORK_AVAILABLE" = true ] && command -v run_with_timeout >/dev/null 2>&1; then
        local _cv_secs _cv_fetch_rc=0
        _cv_secs="${SOLO_FETCH_TIMEOUT:-10}"
        case "$_cv_secs" in ''|*[!0-9]*|0) _cv_secs=10 ;; esac   # BL-234-CHECKVERSIONS-SECS
        run_with_timeout "$_cv_secs" git -C "$repo_path" fetch --quiet >/dev/null 2>&1 || _cv_fetch_rc=$?   # BL-234-CHECKVERSIONS-TIMEOUT
        local local_rev remote_rev behind_count
        local_rev=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null)
        remote_rev=$(git -C "$repo_path" rev-parse origin/main 2>/dev/null || git -C "$repo_path" rev-parse origin/master 2>/dev/null || echo "")

        if [ "$_cv_fetch_rc" -ne 0 ]; then
          UPDATE_CHECK_STATUS="unknown"
          UPDATE_CHECK_MSG="could not refresh refs from the remote (offline, unreachable, or slower than the ${_cv_secs}s bound) — NOT compared, because the refs on disk are whatever the last successful fetch left"   # BL-234-CHECKVERSIONS-FETCHFAIL
        elif [ -z "$remote_rev" ]; then
          UPDATE_CHECK_STATUS="unknown"
          UPDATE_CHECK_MSG="could not determine remote branch"
        elif [ "$local_rev" = "$remote_rev" ]; then
          UPDATE_CHECK_STATUS="up_to_date"
          UPDATE_CHECK_MSG="up to date"
        else
          behind_count=$(git -C "$repo_path" rev-list --count HEAD..origin/main 2>/dev/null || git -C "$repo_path" rev-list --count HEAD..origin/master 2>/dev/null || echo "?")
          UPDATE_CHECK_STATUS="behind"
          UPDATE_CHECK_MSG="$behind_count commit(s) behind"
          UPDATE_CHECK_CMD="cd $repo_path && git pull"
        fi
      elif [ "$NETWORK_AVAILABLE" = true ]; then
        UPDATE_CHECK_STATUS="unknown"
        UPDATE_CHECK_MSG="cannot bound a fetch (scripts/lib/helpers-core.sh unavailable) — skipped rather than compared against stale refs"   # BL-234-CHECKVERSIONS-UNBOUNDABLE
      else
        UPDATE_CHECK_STATUS="unknown"
        UPDATE_CHECK_MSG="network unavailable — skipped"
      fi
      ;;

    docker_image)
      local container_name
      container_name=$(echo "$update_json" | jq -r '.container // empty')

      if ! command -v docker &>/dev/null; then
        UPDATE_CHECK_STATUS="unknown"
        UPDATE_CHECK_MSG="docker not installed"
        return
      fi

      if ! docker inspect "$container_name" &>/dev/null 2>&1; then
        UPDATE_CHECK_STATUS="unknown"
        UPDATE_CHECK_MSG="container not running"
        return
      fi

      if [ "$NETWORK_AVAILABLE" = true ]; then
        local image_name
        image_name=$(docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null || echo "")
        if [ -n "$image_name" ]; then
          # Pull latest digest without downloading layers
          local local_digest remote_digest
          local_digest=$(docker inspect --format '{{.Image}}' "$container_name" 2>/dev/null | cut -c1-20)
          remote_digest=$(docker manifest inspect "$image_name" 2>/dev/null | jq -r '.config.digest // empty' 2>/dev/null | cut -c1-20)

          if [ -n "$remote_digest" ] && [ "$local_digest" != "$remote_digest" ]; then
            UPDATE_CHECK_STATUS="behind"
            UPDATE_CHECK_MSG="newer image available"
            UPDATE_CHECK_CMD="docker pull $image_name && docker restart $container_name"
          else
            UPDATE_CHECK_STATUS="up_to_date"
            UPDATE_CHECK_MSG="up to date"
          fi
        fi
      else
        UPDATE_CHECK_STATUS="unknown"
        UPDATE_CHECK_MSG="network unavailable — skipped"
      fi
      ;;

    ephemeral)
      local runner
      runner=$(echo "$update_json" | jq -r '.runner // "npx"')
      UPDATE_CHECK_STATUS="self_updating"
      UPDATE_CHECK_MSG="auto-updates (runs via $runner)"
      ;;

    claude_plugin)
      UPDATE_CHECK_STATUS="self_updating"
      UPDATE_CHECK_MSG="managed by Claude Code"
      ;;

    *)
      UPDATE_CHECK_STATUS="unknown"
      UPDATE_CHECK_MSG="unknown update_check method: $method"
      ;;
  esac
}

# --- Load tool matrix ---
# BL-235: `check_command` and `version_command` are ARBITRARY SHELL read out of
# a JSON data file, and this consumer ran both through a bare `eval` with no
# bound — while its sibling scripts/resolve-tools.sh has wrapped the identical
# strings in a 10s timeout since 2026-06-26. Two readers of one data file,
# asymmetric bounding.
#
# That was already a live hazard, not a hypothetical: the shipped matrix carries
# `colima version` as a version command, and resolve-tools.sh's own header
# records that daemon-backed commands "can hang indefinitely when the daemon is
# unreachable" — which is why it bounds them. This script could hang on an
# unreachable daemon before any of BL-235's probes existed.
#
# `docker --version` is NOT one of them, and an earlier draft of this comment
# named it. It is client-only — it prints a compiled-in string and never opens a
# socket, measured at 26ms here. `docker version`, without the dashes, is the
# one that contacts the daemon. The hazard is real; that example was not.
#
# The `command -v` guard is the same one BL-234 established lower down:
# helpers-core.sh may be absent, and the fallback path above does not define its
# helpers, so an unguarded call would exit 127 and read as "not installed".
#
# THE RUNNER IS `run_with_deadline`, NOT `run_with_timeout`, AND THAT IS A
# MEASUREMENT. `run_with_timeout` polls on a `sleep 1` counter, so every bounded
# call costs about a second whether the command takes 3ms or 3s. This loop makes
# TWO bounded calls per row; on the 21-row shipped matrix that is ~42 of them,
# and this script went from 5-6s to 50-51s the day the bound landed — inside the
# SessionStart hook, which is the one place where seconds are the operator's.
# `run_with_deadline` is the same bound on a wall-clock deadline with a 0.1s
# poll, and it returns 124 for a timeout instead of 1, so "this took too long"
# stops being spelled the same as "this ran and failed".
CHECKVER_EVAL_TIMEOUT="${CHECKVER_EVAL_TIMEOUT:-10}"
_cv_bounded_eval() {
  local _cmd="$1"
  if command -v run_with_deadline >/dev/null 2>&1; then
    run_with_deadline "$CHECKVER_EVAL_TIMEOUT" bash -c "$_cmd"
  else
    bash -c "$_cmd"
  fi
}

# _cv_render_safe <text> — make TOOL-SUPPLIED text safe to render.
#
# It is `_render_` and not `_note_` because the note was one of TWO surfaces and
# fixing only it was the sync-sibling trap in miniature. `INSTALLED` comes from
# a version_command's STDOUT and reaches the same `echo -e` at nine places —
# six direct (`$INSTALLED` / `$INSTALLED_DISPLAY`) and three via `UPDATES[]` —
# and it was not escaped. Measured: a version_command emitting
# `1.0\n\x20\x20[OK]\x20Totally\x20Installed:\x209.9.9` produced
#
#     [OK] P: 1.0
#     [OK] Totally Installed: 9.9.9 — up to date
#
# a fabricated row byte-identical to a genuine one. `tr -d '[:space:]'` does not
# stop it, because `\x20` is not whitespace until `echo -e` expands it. That
# path has the same external-input vector as the notes: `probe_superpowers` and
# `probe_context7` print a `version` field straight out of
# `~/.claude/plugins/installed_plugins.json`.
#
# So this is applied at the SOURCE of each value — once where the note is read
# and once where the version is captured — rather than at the render sites,
# because there are nine of the latter and the next one added would be unguarded.
#
# `print_warn` renders through `echo -e`, which INTERPRETS backslash escapes in
# whatever it is given. The note comes from a `check_command`'s stderr, so a
# note containing the two characters `\` and `n` becomes a real line break —
# and the line after it is attacker-chosen text at the start of a line, in the
# one script whose entire job is reporting honestly. Measured, with a stderr of
# `note-one\nFORGED  [OK] Totally Installed: 9.9.9`:
#
#     [WARN] P: configured, but working could not be confirmed — note-one
#     FORGED  [OK] Totally Installed: 9.9.9        <- a fabricated report row
#
# Doubling the backslashes makes `echo -e` emit them literally. The rows ship
# with the framework today, but the probe notes interpolate `$(qdrant_mcp_url)`
# read out of `~/.claude.json`, so the text is not wholly ours. C4 pins it.
# RAW CONTROL BYTES ARE STRIPPED AS WELL AS BACKSLASHES DOUBLED, and the range
# is `\000-\037\177` — everything below space, plus DEL. A carriage return is
# not a backslash, so doubling alone leaves it, and on a terminal it returns the
# cursor to column 0 so the following text OVERWRITES the `[WARN]` prefix and
# renders a complete fake row. The narrower range `\000-\010\013\014\016-\037`
# was proposed for this and does NOT strip CR — `\015` falls in the gap between
# `\014` and `\016`. Measured before adopting it: `printf 'a\rb' | tr -d
# '\000-\010\013\014\016-\037\177'` still emits `a \r b`. Take the whole range;
# a tab or newline inside a version string or a one-line note is worth nothing.
# Two lines, not one, so a mutation proof can target the RANGE independently of
# the doubling — a single line can only be mutated as a whole, and then a test
# cannot tell "the tr is gone" from "the tr is too narrow".
#
# `LC_ALL=C` IS NOT DECORATION — WITHOUT IT THIS FUNCTION CAN END THE RUN.
# BSD `tr` and `cut` reject an invalid multibyte sequence in a UTF-8 locale and
# exit 1, and every caller here is under `set -euo pipefail`. Measured, a
# check_command whose stderr carries one stray byte (`printf 'bad\xe9note' >&2`):
#
#     LC_ALL=C            exit=0   3 of 3 rows rendered
#     LC_ALL=C.UTF-8      exit=1   1 of 3       <- ubuntu-latest's usual default
#     LC_ALL=en_US.UTF-8  exit=1   1 of 3
#
# — the report simply stops, which is the "rows silently vanish" pathology this
# branch already hit once through `grep -v`. `LC_ALL=C` makes both operators
# byte-oriented, which is what a sanitiser wants anyway. NOT `|| :`: that would
# swallow the error and silently truncate the note at the bad byte.
# The `cut` on the note pipeline below carries the same guard for the same
# reason; it has been failing this way since it was added, and on `main` too.
_cv_render_safe() {
  local _s="${1//\\/\\\\}"
  printf '%s' "$_s" | LC_ALL=C tr -d '\000-\037\177'                            # BL-235-NOTE-SAFE
}

# _cv_version_bounded <cmd> — run a version_command under the bound and put its
# output in INSTALLED.
#
# It does NOT keep the version command's stderr. An earlier version captured it
# into CV_NOTE, which nothing ever rendered — a second note binned one layer
# before the operator, which is the defect this entry is named for wearing the
# costume of its own fix. A version_command that fails already renders honestly
# as "installed, version not reported", so the row is not lying; adding a second
# unrendered value only added a `mktemp`, a `grep` and a `cut` per row and a
# second forgery surface. Dropped rather than plumbed.
#
# THE FILE IS THE POINT. `INSTALLED=$(_cv_bounded_eval "$VERSION_CMD")` looks
# equivalent and is not: a command substitution reads until the last WRITER
# closes the pipe, and the bound only kills the `bash -c` child. Every pipeline
# member survives it holding that pipe open, so the substitution waited out the
# full command while the runner reported it had stopped. Measured on the
# verbatim shipped Colima row (`colima version … | head -1 | awk …`): 12s
# against a 2s bound. 21 of the 41 checkable rows are pipeline- or
# subshell-shaped, so the bound was doing nothing for half the matrix — in the
# one script that runs from a SessionStart hook, and for exactly the daemon-
# backed rows it was added to protect. Redirecting to a file makes the reader
# independent of who still holds the write end. T2b pins it.
_cv_version_bounded() {
  local _cmd="$1" _out                                                          # BL-235-VERSION-CAPTURE
  INSTALLED=""
  _out="$(mktemp)" || return 0
  _cv_bounded_eval "$_cmd" >"$_out" 2>/dev/null || true
  # `|| :` IS LOAD-BEARING UNDER `set -euo pipefail`: a command that exits
  # non-zero inside a command substitution propagates, and `set -e` then kills
  # the script mid-row. Measured with the sibling `grep -v` this line used to
  # carry — on an EMPTY stderr file it exits 1, which is the NORMAL case, and
  # every healthy row vanished from the report after the first category header.
  # Sanitised HERE, at the single point of capture, so all nine downstream
  # render sites are covered and a tenth added later cannot be forgotten.
  # `version_gte` strips to digits before comparing, so this cannot change a
  # version verdict.
  INSTALLED="$(_cv_render_safe "$(tr -d '[:space:]' < "$_out" 2>/dev/null || :)")"   # BL-235-VERSION-SAFE
  rm -f "$_out"
}

# THE MATRIX ROWS MUST NOT DEPEND ON THIS PROCESS'S `pwd`. Three rows invoke
# scripts/probe-tool.sh; a relative path inside a JSON data file resolves
# against whatever directory the consumer is standing in, and `rc=127` —
# command-not-found — is read two lines below as "not installed". The probe
# ships next to this script both here and in every generated project, so this
# script's own location is the answer.
export SOLO_SCRIPTS_DIR="${SOLO_SCRIPTS_DIR:-$SCRIPT_DIR}"                      # BL-235-SCRIPTS-DIR

MATRIX_DIR="templates/tool-matrix"
if [ ! -d "$MATRIX_DIR" ]; then
  # Try from orchestrator source
  if [ -f ".claude/orchestrator-source.json" ] && command -v jq &>/dev/null; then
    src=$(jq -r '.source_dir // empty' ".claude/orchestrator-source.json" 2>/dev/null)
    [ -n "$src" ] && [ -d "$src/templates/tool-matrix" ] && MATRIX_DIR="$src/templates/tool-matrix"
  fi
fi

if [ ! -d "$MATRIX_DIR" ]; then
  print_fail "Tool matrix not found. Cannot check versions."
  exit 1
fi

# Load project context for filtering
PLATFORM=""
LANGUAGE=""
TRACK=""
if [ -f ".claude/tool-preferences.json" ] && command -v jq &>/dev/null; then
  PLATFORM=$(jq -r '.context.platform // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
  LANGUAGE=$(jq -r '.context.language // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
  TRACK=$(jq -r '.context.track // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
fi

# --- Collect tools to check ---
# Load common.json + platform-specific
ALL_TOOLS=$(jq '.tools' "$MATRIX_DIR/common.json")
if [ -n "$PLATFORM" ] && [ -f "$MATRIX_DIR/${PLATFORM}.json" ]; then
  ALL_TOOLS=$(echo "$ALL_TOOLS" | jq --slurpfile p "$MATRIX_DIR/${PLATFORM}.json" '. + $p[0].tools')
fi

# Filter by language (skip language-specific tools for other languages)
if [ -n "$LANGUAGE" ]; then
  ALL_TOOLS=$(echo "$ALL_TOOLS" | jq --arg lang "$LANGUAGE" '[.[] | select(
    .languages == null or
    (.languages | index("all")) != null or
    (.languages | index($lang)) != null
  )]')
fi

# Filter by track (skip tools that require a higher track)
if [ -n "$TRACK" ]; then
  ALL_TOOLS=$(echo "$ALL_TOOLS" | jq --arg track "$TRACK" '[.[] | select(
    .tracks == null or
    (.tracks | index($track)) != null
  )]')
fi

# Only check tools that have a version_command (skip presence-only tools like Android Keystore)
CHECKABLE_TOOLS=$(echo "$ALL_TOOLS" | jq '[.[] | select(.version_command != null and .version_command != "" and .check_command != null)]')

# --- Check each tool ---
echo ""
echo -e "${BOLD}Solo Orchestrator — Version Check${NC}"
echo ""

BELOW_MIN=()
UPDATES=()
UPDATE_CMDS=()
# UPDATE_NAMES tracks the verbatim tool name (with whitespace preserved)
# in parallel with UPDATES[]/UPDATE_CMDS[]. The pre-fix code reconstructed
# the name by parsing the display-string entry from UPDATES via
# `${var%% *}` (single-space split), which truncated multi-word tool
# names (e.g. "Claude Code" → "Claude") in the interactive selection
# loops AND printed the entire display string verbatim in the
# non-interactive branch. The parallel array decouples display
# formatting from the canonical name and is the recommendation
# recorded against finding specs-plans-tool-matrix-versions-1.
UPDATE_NAMES=()
PASS_COUNT=0
CURRENT_CATEGORY=""

TOOL_COUNT=$(echo "$CHECKABLE_TOOLS" | jq 'length')

if [ "$TOOL_COUNT" -eq 0 ]; then
  print_warn "No tools to check"
  exit 0
fi

# Check network availability once (skip if curl is unavailable or sandboxed)
NETWORK_AVAILABLE=false
if command -v curl &>/dev/null; then
  # Use a subshell to prevent sandbox environments from killing the parent process
  if (curl -s --max-time 3 "https://registry.npmjs.org" >/dev/null 2>&1); then
    NETWORK_AVAILABLE=true
  else
    print_info "Network unavailable — latest version check skipped"
    echo ""
  fi
fi

for i in $(seq 0 $((TOOL_COUNT - 1))); do
  TOOL=$(echo "$CHECKABLE_TOOLS" | jq ".[$i]")
  NAME=$(echo "$TOOL" | jq -r '.name')
  CATEGORY=$(echo "$TOOL" | jq -r '.category')
  CHECK_CMD=$(echo "$TOOL" | jq -r '.check_command')
  VERSION_CMD=$(echo "$TOOL" | jq -r '.version_command // empty')
  MIN_VER=$(echo "$TOOL" | jq -r '.min_version // empty')
  LATEST_METHOD=$(echo "$TOOL" | jq -r '.latest_check.method // empty')
  LATEST_PKG=$(echo "$TOOL" | jq -r '.latest_check.package // empty')
  INSTALL_OBJ=$(echo "$TOOL" | jq -r '.install // empty')
  UC_METHOD=$(echo "$TOOL" | jq -r '.update_check.method // empty')
  UC_JSON=$(echo "$TOOL" | jq '.update_check // empty')

  # Category header
  case "$CATEGORY" in
    version_control|json_processor|runtime|containerization|commit_signing)
      NEW_CAT="Core Tools" ;;
    sast|secret_detection|dependency_scanning)
      NEW_CAT="Security Tools" ;;
    ai_agent|claude_plugin|mcp_server|dev_framework)
      NEW_CAT="Plugins & MCP" ;;
    *)
      NEW_CAT="Project Tools" ;;
  esac
  if [ "$NEW_CAT" != "$CURRENT_CATEGORY" ]; then
    echo -e "${BOLD}── $NEW_CAT ──${NC}"
    CURRENT_CATEGORY="$NEW_CAT"
  fi

  # Check if installed
  # Disable set -u: check_commands may reference env vars (e.g., $ANDROID_HOME)
  # that are legitimately unset on this system.
  # THE PROBE WORKS OUT WHY, AND THIS LINE USED TO BIN IT. `>/dev/null 2>&1`
  # discarded the check's stderr AND its exit code, so all three states of the
  # contract probe-tool.sh spends ten lines defending arrived here as one word:
  # "not installed". Measured before this fix — a database that is UP and
  # answering 403 because it wants the api-key the operator has not configured
  # rendered IDENTICALLY to one that was never set up:
  #
  #     [WARN] Qdrant MCP: not installed
  #
  # while the probe's own stderr, which the test suite was happily asserting on
  # one layer upstream, said "answered HTTP 403 — the database is up and refused
  # this probe. Add QDRANT_API_KEY to the same mcpServers entry…". That is this
  # entry's defect exactly, committed by its own fix: rigour applied at the
  # probe, consumed at a caller that could not hear it. C3 asserts the guidance
  # in THIS script's output, not in the probe's.
  #
  # rc 2 is the shared three-state convention (0 working / 1 not configured /
  # 2 cannot confirm). A row that does not implement it simply never returns 2.
  set +u
  CHECK_ERR="$(mktemp)"
  CHECK_RC=0
  _cv_bounded_eval "$CHECK_CMD" >/dev/null 2>"$CHECK_ERR" || CHECK_RC=$?         # BL-235-BOUND-CHECK
  set -u
  # `|| :` for the same reason as in _cv_version_bounded: an empty stderr file
  # makes `grep -v` exit 1, and under `set -euo pipefail` that ends the run.
  # LC_ALL=C on the `cut` for the same reason as in _cv_render_safe: in a UTF-8
  # locale it exits 1 on an invalid multibyte sequence, and under `set -e` that
  # ends the whole report. This one has been failing that way since it was
  # added — and on `main` too, so it is not a regression, but these are the
  # lines this entry owns.
  CHECK_NOTE="$( { grep -v '^[[:space:]]*$' "$CHECK_ERR" 2>/dev/null || :; } | tail -1 | LC_ALL=C cut -c1-200)"
  CHECK_NOTE="$(_cv_render_safe "$CHECK_NOTE")"
  rm -f "$CHECK_ERR"
  if [ "$CHECK_RC" -ne 0 ]; then
    if [ "$CHECK_RC" -eq 2 ]; then                                              # BL-235-THIRD-STATE
      print_warn "$NAME: configured, but working could not be confirmed${CHECK_NOTE:+ — $CHECK_NOTE}"
    else
      print_warn "$NAME: not installed${CHECK_NOTE:+ — $CHECK_NOTE}"
    fi
    continue
  fi

  # Get installed version
  INSTALLED=""
  if [ -n "$VERSION_CMD" ]; then
    _cv_version_bounded "$VERSION_CMD"                                          # BL-235-BOUND-VERSION
  fi

  # THE WORD `configured` WAS THE WHOLE DEFECT AND IT NEARLY SURVIVED BY MOVING
  # FILE. BL-235 deleted `version_command: echo 'configured'` from the matrix —
  # and this script then rendered the identical word from its own
  # `${INSTALLED:-configured}` fallback, at four sites, for exactly the rows
  # that had just stopped declaring it. A JSON-level assertion cannot see that;
  # only one that reads the OUTPUT can, which is why the suite now has one.
  #
  # What is true here is that the check PASSED and the version command produced
  # nothing. The replacement says that and nothing more: it does not upgrade
  # silence into a configuration claim. ONE owner, read by all four sites.
  INSTALLED_DISPLAY="${INSTALLED:-installed, version not reported}"             # BL-235-NO-CONSTANT

  # Check minimum version
  MIN_MET=true
  MIN_DISPLAY=""
  if [ -n "$MIN_VER" ] && [ -n "$INSTALLED" ]; then
    MIN_DISPLAY=" (min: $MIN_VER)"
    if ! version_gte "$INSTALLED" "$MIN_VER"; then
      MIN_MET=false
    fi
  fi

  # Check for updates — use update_check if present, otherwise fall back to latest_check
  if [ -n "$UC_METHOD" ] && [ "$UC_METHOD" != "null" ]; then
    # Data-driven update check
    check_for_update "$UC_METHOD" "$UC_JSON" "$INSTALL_OBJ"

    if [ "$MIN_MET" = false ]; then
      print_warn "$NAME: $INSTALLED$MIN_DISPLAY — BELOW MINIMUM"
      echo -e "         ${YELLOW}⚠ Continuing with outdated $NAME may cause issues.${NC}"
      BELOW_MIN+=("$NAME")
      UPDATES+=("$NAME $INSTALLED → latest (BELOW MINIMUM)")
      UPDATE_CMDS+=("${UPDATE_CHECK_CMD:-}")
      UPDATE_NAMES+=("$NAME")
    elif [ "$UPDATE_CHECK_STATUS" = "behind" ]; then
      print_warn "$NAME: $INSTALLED_DISPLAY — $UPDATE_CHECK_MSG"
      UPDATES+=("$NAME — $UPDATE_CHECK_MSG")
      UPDATE_CMDS+=("${UPDATE_CHECK_CMD:-}")
      UPDATE_NAMES+=("$NAME")
    elif [ "$UPDATE_CHECK_STATUS" = "self_updating" ]; then
      print_ok "$NAME: $INSTALLED_DISPLAY — $UPDATE_CHECK_MSG"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      print_ok "$NAME: $INSTALLED_DISPLAY — ${UPDATE_CHECK_MSG:-up to date}"
      PASS_COUNT=$((PASS_COUNT + 1))
    fi
  else
    # Standard latest_check flow (version comparison)
    LATEST=""
    LATEST_DISPLAY=""
    if [ "$NETWORK_AVAILABLE" = true ] && [ -n "$LATEST_METHOD" ] && [ "$LATEST_METHOD" != "null" ] && [ -n "$LATEST_PKG" ]; then
      LATEST=$(get_latest_version "$LATEST_METHOD" "$LATEST_PKG")
    fi

    if [ -n "$LATEST" ] && [ -n "$INSTALLED" ]; then
      if version_gte "$INSTALLED" "$LATEST"; then
        LATEST_DISPLAY=" — up to date"
      else
        LATEST_DISPLAY=" — $LATEST available"
      fi
    elif [ -n "$INSTALLED" ] && [ "$NETWORK_AVAILABLE" = false ]; then
      LATEST_DISPLAY=""
    elif [ -n "$INSTALLED" ]; then
      LATEST_DISPLAY=" — up to date"
    fi

    # Output
    if [ "$MIN_MET" = false ]; then
      print_warn "$NAME: $INSTALLED$MIN_DISPLAY — BELOW MINIMUM$LATEST_DISPLAY"
      echo -e "         ${YELLOW}⚠ Continuing with outdated $NAME may cause issues.${NC}"
      BELOW_MIN+=("$NAME")
      # Find update command
      local_update_cmd=""
      if command -v brew &>/dev/null; then
        local_update_cmd=$(echo "$TOOL" | jq -r "(.install.darwin_brew // empty) | $_cv_jq_install_cmd")
      fi
      if [ -z "$local_update_cmd" ]; then
        local_update_cmd=$(echo "$TOOL" | jq -r "(.install.npm // .install.linux_pip // .install.manual // empty) | $_cv_jq_install_cmd")
      fi
      UPDATES+=("$NAME $INSTALLED → ${LATEST:-latest} (BELOW MINIMUM)")
      UPDATE_CMDS+=("$local_update_cmd")
      UPDATE_NAMES+=("$NAME")
    elif [ -n "$LATEST" ] && ! version_gte "$INSTALLED" "$LATEST"; then
      print_ok "$NAME: $INSTALLED$MIN_DISPLAY$LATEST_DISPLAY"
      # Find update command
      local_update_cmd=""
      if command -v brew &>/dev/null; then
        local_update_cmd=$(echo "$TOOL" | jq -r "(.install.darwin_brew // empty) | $_cv_jq_install_cmd")
      fi
      if [ -z "$local_update_cmd" ]; then
        local_update_cmd=$(echo "$TOOL" | jq -r "(.install.npm // .install.linux_pip // .install.manual // empty) | $_cv_jq_install_cmd")
      fi
      UPDATES+=("$NAME $INSTALLED → $LATEST")
      UPDATE_CMDS+=("$local_update_cmd")
      UPDATE_NAMES+=("$NAME")
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      print_ok "$NAME: $INSTALLED_DISPLAY$MIN_DISPLAY$LATEST_DISPLAY"
      PASS_COUNT=$((PASS_COUNT + 1))
    fi
  fi
done

# --- Summary ---
echo ""
echo -e "${BOLD}── Summary ──${NC}"
echo -e "  ${GREEN}✓ $PASS_COUNT up to date${NC}"
if [ ${#UPDATES[@]} -gt 0 ]; then
  echo -e "  ${CYAN}⬆ ${#UPDATES[@]} updates available${NC}"
fi
if [ ${#BELOW_MIN[@]} -gt 0 ]; then
  echo -e "  ${YELLOW}⚠ ${#BELOW_MIN[@]} below minimum (${BELOW_MIN[*]}) — update recommended before continuing${NC}"
fi

# --- Interactive update prompt ---
if [ ${#UPDATES[@]} -gt 0 ] && [ -t 0 ]; then
  echo ""
  echo -e "${BOLD}Updates available:${NC}"
  for idx in "${!UPDATES[@]}"; do
    echo "  $((idx+1)). ${UPDATES[$idx]}"
  done
  echo ""
  echo -e "${BOLD}Update options:${NC}"
  echo "  a) Update all ($(seq -s, 1 ${#UPDATES[@]}))"
  echo "  b) Select which to update (enter numbers: e.g., 1,3)"
  echo "  c) Skip for now"
  echo ""

  read -rp "$(echo -e "${BOLD}Choice [a/b/c]${NC}: ")" choice # lint-raw-read-prompt: allow multi-letter (a/b/c) choice prompt — prompt_input/prompt_yes_no shape doesn't fit; gated by `-t 0` TTY check at line 444 above; non-interactive branch at line 511 below covers CI/scripted callers

  case "$choice" in
    a|A)
      echo ""
      for idx in "${!UPDATE_CMDS[@]}"; do
        cmd="${UPDATE_CMDS[$idx]}"
        # specs-plans-tool-matrix-versions-1: pull the verbatim name
        # from UPDATE_NAMES[] (parallel array). Pre-fix code parsed
        # UPDATES[] with `${var%% *}` (one-space split), which
        # truncated multi-word tool names AND shadowed uname(1).
        tool_name="${UPDATE_NAMES[$idx]}"
        if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
          print_info "Updating $tool_name..."
          if eval "$cmd" 2>/dev/null; then
            print_ok "$tool_name updated"
          else
            print_fail "Could not update $tool_name. Run manually: $cmd"
          fi
        else
          print_warn "$tool_name: no auto-update command available"
        fi
      done
      ;;
    b|B)
      # Wave-3 raw-read sweep: prompt_input centralizes !-t 0 / CI /
      # SOIF_NONINTERACTIVE default-return. Empty default means CI
      # callers get an empty selections list → the `IFS=',' read -ra`
      # below produces a single empty token, which the bounds check
      # at "$idx -ge 0 && $idx -lt ${#UPDATE_CMDS[@]}" rejects, so
      # CI safely skips the update rather than auto-installing.
      selections=$(prompt_input "Enter numbers (comma-separated)" "")
      IFS=',' read -ra sel_arr <<< "$selections"
      echo ""
      for sel in "${sel_arr[@]}"; do
        sel=$(echo "$sel" | tr -d '[:space:]')
        idx=$((sel - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#UPDATE_CMDS[@]} ]; then
          cmd="${UPDATE_CMDS[$idx]}"
          # specs-plans-tool-matrix-versions-1 — see comment in the a/A
          # branch above; UPDATE_NAMES[] preserves whitespace verbatim.
          tool_name="${UPDATE_NAMES[$idx]}"
          if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
            print_info "Updating $tool_name..."
            if eval "$cmd" 2>/dev/null; then
              print_ok "$tool_name updated"
            else
              print_fail "Could not update $tool_name. Run manually: $cmd"
            fi
          fi
        fi
      done
      ;;
    c|C|*)
      if [ ${#UPDATES[@]} -gt 0 ]; then
        echo ""
        echo "Manual update commands:"
        for idx in "${!UPDATES[@]}"; do
          # specs-plans-tool-matrix-versions-1 — UPDATE_NAMES[] is the
          # canonical tool name (whitespace preserved). Pre-fix used
          # `${UPDATES[$idx]%%  *}` (two-space split) which left the
          # whole display string ("Claude Code 0.0.1 → latest (BELOW
          # MINIMUM)") in front of the colon.
          # WALK-ISSUE-003: render, never echo raw — a multi-stage install is
          # joined into one runnable line, and a URL / missing entry is labelled
          # instead of masquerading as a command.
          echo "  ${UPDATE_NAMES[$idx]}: $(_cv_render_update_cmd "${UPDATE_CMDS[$idx]}")"
        done
      fi
      ;;
  esac
elif [ ${#UPDATES[@]} -gt 0 ]; then
  # Non-interactive: just print commands. Same rationale as the c/C
  # branch above — UPDATE_NAMES[] preserves whitespace; the prior
  # `${UPDATES[$idx]%%  *}` parse-out-of-display-string was lossy.
  echo ""
  echo "Update commands (run manually):"
  for idx in "${!UPDATES[@]}"; do
    # WALK-ISSUE-003: same renderer as the interactive branch — the two
    # printers of this heading must not disagree about what is runnable.
    echo "  ${UPDATE_NAMES[$idx]}: $(_cv_render_update_cmd "${UPDATE_CMDS[$idx]}")"
  done
fi

# Exit code
if [ ${#BELOW_MIN[@]} -gt 0 ]; then
  exit 1
else
  exit 0
fi

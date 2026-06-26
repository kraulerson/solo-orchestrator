#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Tool Matrix Resolver
# Reads tool-matrix JSON files, filters by project context, checks
# installed state, and outputs a categorized JSON plan to stdout.
#
# 2026-06-26: Tool check_commands / version_commands are evaluated
# against the local environment to discover installed state. Some of
# them connect to daemons (`colima version`, `docker version`, etc.)
# and can hang indefinitely when the daemon is unreachable, taking
# init.sh + verify-install.sh --auto-fix down with them (since the
# resolver runs inside a $() subshell). Each eval is now bounded by a
# portable wall-clock timeout; a timed-out check is treated as "tool
# not found" and a timed-out version_command yields an empty version.
#
# Usage:
#   scripts/resolve-tools.sh \
#     --dev-os darwin \
#     --platform web \
#     --language typescript \
#     --track standard \
#     --phase 2 \
#     --matrix-dir templates/tool-matrix \
#     [--tool-prefs .claude/tool-preferences.json]
#
# Output: JSON with four buckets: auto_install, manual_install,
#         already_installed, deferred

# Portable wall-clock timeout for evaluated shell commands. Runs the
# given command string via `bash -c` and kills it if it exceeds
# RESOLVE_TOOLS_EVAL_TIMEOUT seconds. Exit code 124 signals timeout;
# other non-zero codes propagate the command's own failure. Callers
# already handle non-zero ("tool not installed") so the timeout case
# is indistinguishable from a clean "missing tool" — which is what
# we want for an unreachable daemon.
RESOLVE_TOOLS_EVAL_TIMEOUT="${RESOLVE_TOOLS_EVAL_TIMEOUT:-10}"
run_cmd_with_timeout() {
  local _secs="$1" _cmd="$2"
  bash -c "$_cmd" &
  local _pid=$!
  local _elapsed=0
  while kill -0 "$_pid" 2>/dev/null; do
    if [ "$_elapsed" -ge "$_secs" ]; then
      kill -9 "$_pid" 2>/dev/null || true
      wait "$_pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    _elapsed=$((_elapsed + 1))
  done
  wait "$_pid" 2>/dev/null
}

# --- Parse arguments ---
DEV_OS=""
PLATFORM=""
LANGUAGE=""
TRACK=""
PHASE=""
MATRIX_DIR=""
TOOL_PREFS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dev-os)      DEV_OS="$2";      shift 2 ;;
    --platform)    PLATFORM="$2";    shift 2 ;;
    --language)    LANGUAGE="$2";    shift 2 ;;
    --track)       TRACK="$2";       shift 2 ;;
    --phase)       PHASE="$2";       shift 2 ;;
    --matrix-dir)  MATRIX_DIR="$2";  shift 2 ;;
    --tool-prefs)  TOOL_PREFS="$2";  shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Validate required arguments
for var_name in DEV_OS PLATFORM LANGUAGE TRACK PHASE MATRIX_DIR; do
  eval val="\$$var_name"
  if [ -z "$val" ]; then
    echo "Missing required argument: --$(echo "$var_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')" >&2
    exit 1
  fi
done

if [ ! -d "$MATRIX_DIR" ]; then
  echo "Matrix directory not found: $MATRIX_DIR" >&2
  exit 1
fi

# Normalize dev_os to lowercase
DEV_OS=$(echo "$DEV_OS" | tr '[:upper:]' '[:lower:]')
case "$DEV_OS" in
  darwin|macos) DEV_OS="darwin" ;;
  linux)        DEV_OS="linux" ;;
  *)
    echo "Unsupported dev_os: $DEV_OS (expected darwin or linux)" >&2
    exit 1
    ;;
esac

# --- Load matrix files ---
COMMON_FILE="$MATRIX_DIR/common.json"
PLATFORM_FILE="$MATRIX_DIR/${PLATFORM}.json"

if [ ! -f "$COMMON_FILE" ]; then
  echo "Common matrix file not found: $COMMON_FILE" >&2
  exit 1
fi

# Merge tools from common + platform-specific (platform file is optional)
if [ -f "$PLATFORM_FILE" ]; then
  ALL_TOOLS=$(jq -s '.[0].tools + .[1].tools' "$COMMON_FILE" "$PLATFORM_FILE")
else
  ALL_TOOLS=$(jq '.tools' "$COMMON_FILE")
fi

# --- Load user preferences (if provided) ---
SKIPPED_NAMES="[]"
SUBSTITUTIONS="{}"
ADDITIONS="[]"
if [ -n "$TOOL_PREFS" ] && [ -f "$TOOL_PREFS" ]; then
  SKIPPED_NAMES=$(jq '[.skipped[]?.name // empty]' "$TOOL_PREFS" 2>/dev/null || echo "[]")
  SUBSTITUTIONS=$(jq '.substitutions // {}' "$TOOL_PREFS" 2>/dev/null || echo "{}")
  ADDITIONS=$(jq '.additions // []' "$TOOL_PREFS" 2>/dev/null || echo "[]")
fi

# --- Filter tools ---
# Apply: dev_os, track, language, platforms, skipped
FILTERED_TOOLS=$(echo "$ALL_TOOLS" | jq \
  --arg dev_os "$DEV_OS" \
  --arg track "$TRACK" \
  --arg language "$LANGUAGE" \
  --arg platform "$PLATFORM" \
  --argjson skipped "$SKIPPED_NAMES" \
  '[.[] | select(
    # dev_os filter
    (.dev_os | if . == null then true else (. | index($dev_os)) != null end) and
    # track filter
    (.tracks | if . == null then true else (. | index($track)) != null end) and
    # language filter
    (.languages | if . == null then true
     elif (. | index("all")) != null then true
     else (. | index($language)) != null end) and
    # platforms filter
    (.platforms | if . == null then true
     elif (. | index("all")) != null then true
     else (. | index($platform)) != null end) and
    # skipped filter
    (.name as $n | ($skipped | index($n)) == null)
  )]')

# --- Apply substitutions ---
# For each tool whose substitution_category matches a key in substitutions,
# replace the tool name/check_command with the user's selection
FILTERED_TOOLS=$(echo "$FILTERED_TOOLS" | jq \
  --argjson subs "$SUBSTITUTIONS" \
  '[.[] | . as $tool |
    if $tool.substitution_category != null and ($subs | has($tool.substitution_category)) then
      $subs[$tool.substitution_category] as $sub |
      $tool + {
        name: $sub.selected,
        check_command: ($sub.check_command // $tool.check_command),
        original_default: $tool.name
      }
    else . end
  ]')

# --- Detect install method for this OS ---
# Determine available package managers
HAS_BREW=false
HAS_APT=false
HAS_DNF=false
HAS_PACMAN=false
HAS_NPM=false
command -v brew &>/dev/null && HAS_BREW=true
command -v apt &>/dev/null && HAS_APT=true
command -v dnf &>/dev/null && HAS_DNF=true
command -v pacman &>/dev/null && HAS_PACMAN=true
command -v npm &>/dev/null && HAS_NPM=true

# Build priority list of install keys for this environment (single string, no jq)
_keys=""
if [ "$DEV_OS" = "darwin" ]; then
  [ "$HAS_BREW" = true ] && _keys="${_keys}darwin_brew,"
  _keys="${_keys}darwin_manual,"
elif [ "$DEV_OS" = "linux" ]; then
  [ "$HAS_APT" = true ] && _keys="${_keys}linux_apt,"
  [ "$HAS_DNF" = true ] && _keys="${_keys}linux_dnf,"
  [ "$HAS_PACMAN" = true ] && _keys="${_keys}linux_pacman,"
  _keys="${_keys}linux_pip,linux_manual,"
fi
[ "$HAS_NPM" = true ] && _keys="${_keys}npm,"
_keys="${_keys}manual"
INSTALL_KEYS=$(echo "$_keys" | jq -R 'split(",")')

# --- Check each tool and categorize ---
AUTO_INSTALL="[]"
MANUAL_INSTALL="[]"
ALREADY_INSTALLED="[]"
DEFERRED="[]"

# --- Check each tool and categorize ---
# Extract all fields per tool in a single jq call (tab-separated) to avoid N*8 subprocess forks.
# Fields: name, category, phase, required, check_command, auto_installable, version_command, description, install_json
while IFS=$'\t' read -r TOOL_NAME TOOL_CATEGORY TOOL_PHASE TOOL_REQUIRED TOOL_CHECK TOOL_AUTO TOOL_VERSION_CMD TOOL_DESCRIPTION TOOL_INSTALL_B64; do

  # Decode base64-encoded install JSON (avoids @tsv double-escaping embedded quotes)
  TOOL_INSTALL_JSON=$(echo "$TOOL_INSTALL_B64" | base64 -d 2>/dev/null || echo "{}")

  # Phase filter: defer tools for future phases
  if [ "$TOOL_PHASE" -gt "$PHASE" ]; then
    DEFERRED=$(echo "$DEFERRED" | jq \
      --arg name "$TOOL_NAME" \
      --arg category "$TOOL_CATEGORY" \
      --argjson phase "$TOOL_PHASE" \
      --arg description "$TOOL_DESCRIPTION" \
      '. + [{name: $name, category: $category, phase: $phase, reason: ("Needed at Phase " + ($phase | tostring) + " gate"), description: $description}]')
    continue
  fi

  # Check if already installed
  # Temporarily disable set -u: tool check_commands may reference env vars
  # (e.g., $ANDROID_HOME) that are legitimately unset on this system.
  INSTALLED=false
  VERSION=""
  set +u
  if run_cmd_with_timeout "$RESOLVE_TOOLS_EVAL_TIMEOUT" "$TOOL_CHECK" &>/dev/null; then
    INSTALLED=true
    if [ -n "$TOOL_VERSION_CMD" ]; then
      VERSION=$(run_cmd_with_timeout "$RESOLVE_TOOLS_EVAL_TIMEOUT" "$TOOL_VERSION_CMD" 2>/dev/null || echo "")
    fi
  fi
  set -u

  if [ "$INSTALLED" = true ]; then
    ALREADY_INSTALLED=$(echo "$ALREADY_INSTALLED" | jq \
      --arg name "$TOOL_NAME" \
      --arg category "$TOOL_CATEGORY" \
      --arg version "$VERSION" \
      '. + [{name: $name, category: $category, version: $version}]')
  else
    # Find the best install command for this environment
    INSTALL_CMD=""
    for key in $(echo "$INSTALL_KEYS" | jq -r '.[]'); do
      cmd=$(echo "$TOOL_INSTALL_JSON" | jq -r --arg k "$key" '.[$k] // empty')
      if [ -n "$cmd" ]; then
        INSTALL_CMD="$cmd"
        break
      fi
    done

    # If no auto-installable command found, fall back to manual
    if [ -z "$INSTALL_CMD" ]; then
      INSTALL_CMD=$(echo "$TOOL_INSTALL_JSON" | jq -r '.manual // "See documentation"')
      TOOL_AUTO="false"
    fi

    if [ "$TOOL_AUTO" = "true" ]; then
      AUTO_INSTALL=$(echo "$AUTO_INSTALL" | jq \
        --arg name "$TOOL_NAME" \
        --arg category "$TOOL_CATEGORY" \
        --arg install_cmd "$INSTALL_CMD" \
        --argjson required "$([ "$TOOL_REQUIRED" = "true" ] && echo true || echo false)" \
        --arg description "$TOOL_DESCRIPTION" \
        '. + [{name: $name, category: $category, install_cmd: $install_cmd, required: $required, description: $description}]')
    else
      MANUAL_INSTALL=$(echo "$MANUAL_INSTALL" | jq \
        --arg name "$TOOL_NAME" \
        --arg category "$TOOL_CATEGORY" \
        --arg instructions "$INSTALL_CMD" \
        --argjson required "$([ "$TOOL_REQUIRED" = "true" ] && echo true || echo false)" \
        --arg description "$TOOL_DESCRIPTION" \
        '. + [{name: $name, category: $category, instructions: $instructions, required: $required, description: $description}]')
    fi
  fi
done < <(echo "$FILTERED_TOOLS" | jq -r '.[] | [
  .name,
  (.substitution_category // .category),
  (.phase | tostring),
  (.required | tostring),
  .check_command,
  (.auto_installable | tostring),
  (.version_command // ""),
  .description,
  (.install | tojson | @base64)
] | @tsv')

# --- Add user freeform additions ---
ADDITION_COUNT=$(echo "$ADDITIONS" | jq 'length')
if [ "$ADDITION_COUNT" -gt 0 ]; then
for i in $(seq 0 $((ADDITION_COUNT - 1))); do
  ADD_JSON=$(echo "$ADDITIONS" | jq ".[$i]")
  ADD_NAME=$(echo "$ADD_JSON" | jq -r '.name')
  ADD_CATEGORY=$(echo "$ADD_JSON" | jq -r '.category // "Custom"')
  ADD_CHECK=$(echo "$ADD_JSON" | jq -r '.check_command // ""')
  ADD_DESC=$(echo "$ADD_JSON" | jq -r '.description // ""')

  set +u
  if [ -n "$ADD_CHECK" ] && run_cmd_with_timeout "$RESOLVE_TOOLS_EVAL_TIMEOUT" "$ADD_CHECK" &>/dev/null; then
    set -u
    ALREADY_INSTALLED=$(echo "$ALREADY_INSTALLED" | jq \
      --arg name "$ADD_NAME" \
      --arg category "$ADD_CATEGORY" \
      --arg version "custom" \
      '. + [{name: $name, category: $category, version: $version}]')
  else
    set -u
    MANUAL_INSTALL=$(echo "$MANUAL_INSTALL" | jq \
      --arg name "$ADD_NAME" \
      --arg category "$ADD_CATEGORY" \
      --arg instructions "User-added tool — install manually" \
      --arg description "$ADD_DESC" \
      '. + [{name: $name, category: $category, instructions: $instructions, required: false, description: $description}]')
  fi
done
fi

# --- Output ---
jq -n \
  --argjson auto_install "$AUTO_INSTALL" \
  --argjson manual_install "$MANUAL_INSTALL" \
  --argjson already_installed "$ALREADY_INSTALLED" \
  --argjson deferred "$DEFERRED" \
  '{
    auto_install: $auto_install,
    manual_install: $manual_install,
    already_installed: $already_installed,
    deferred: $deferred
  }'

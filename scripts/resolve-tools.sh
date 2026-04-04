#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Tool Matrix Resolver
# Reads tool-matrix JSON files, filters by project context, checks
# installed state, and outputs a categorized JSON plan to stdout.
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
HAS_NPM=false
command -v brew &>/dev/null && HAS_BREW=true
command -v apt &>/dev/null && HAS_APT=true
command -v dnf &>/dev/null && HAS_DNF=true
command -v npm &>/dev/null && HAS_NPM=true

# Build priority list of install keys for this environment
INSTALL_KEYS="[]"
if [ "$DEV_OS" = "darwin" ]; then
  if [ "$HAS_BREW" = true ]; then
    INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["darwin_brew"]')
  fi
  INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["darwin_manual"]')
elif [ "$DEV_OS" = "linux" ]; then
  if [ "$HAS_APT" = true ]; then
    INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["linux_apt"]')
  fi
  if [ "$HAS_DNF" = true ]; then
    INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["linux_dnf"]')
  fi
  INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["linux_pip", "linux_manual"]')
fi
if [ "$HAS_NPM" = true ]; then
  INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["npm"]')
fi
INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["manual"]')

# --- Check each tool and categorize ---
AUTO_INSTALL="[]"
MANUAL_INSTALL="[]"
ALREADY_INSTALLED="[]"
DEFERRED="[]"

TOOL_COUNT=$(echo "$FILTERED_TOOLS" | jq 'length')

if [ "$TOOL_COUNT" -gt 0 ]; then
for i in $(seq 0 $((TOOL_COUNT - 1))); do
  TOOL_JSON=$(echo "$FILTERED_TOOLS" | jq ".[$i]")
  TOOL_NAME=$(echo "$TOOL_JSON" | jq -r '.name')
  TOOL_CATEGORY=$(echo "$TOOL_JSON" | jq -r '.substitution_category // .category')
  TOOL_PHASE=$(echo "$TOOL_JSON" | jq -r '.phase')
  TOOL_REQUIRED=$(echo "$TOOL_JSON" | jq -r '.required')
  TOOL_CHECK=$(echo "$TOOL_JSON" | jq -r '.check_command')
  TOOL_AUTO=$(echo "$TOOL_JSON" | jq -r '.auto_installable')
  TOOL_VERSION_CMD=$(echo "$TOOL_JSON" | jq -r '.version_command // empty')
  TOOL_DESCRIPTION=$(echo "$TOOL_JSON" | jq -r '.description')

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
  INSTALLED=false
  VERSION=""
  if eval "$TOOL_CHECK" &>/dev/null 2>&1; then
    INSTALLED=true
    if [ -n "$TOOL_VERSION_CMD" ]; then
      VERSION=$(eval "$TOOL_VERSION_CMD" 2>/dev/null || echo "")
    fi
  fi

  if [ "$INSTALLED" = true ]; then
    ALREADY_INSTALLED=$(echo "$ALREADY_INSTALLED" | jq \
      --arg name "$TOOL_NAME" \
      --arg category "$TOOL_CATEGORY" \
      --arg version "$VERSION" \
      '. + [{name: $name, category: $category, version: $version}]')
  else
    # Find the best install command for this environment
    INSTALL_CMD=""
    INSTALL_OBJ=$(echo "$TOOL_JSON" | jq '.install')
    for key in $(echo "$INSTALL_KEYS" | jq -r '.[]'); do
      cmd=$(echo "$INSTALL_OBJ" | jq -r --arg k "$key" '.[$k] // empty')
      if [ -n "$cmd" ]; then
        INSTALL_CMD="$cmd"
        break
      fi
    done

    # If no auto-installable command found, fall back to manual
    if [ -z "$INSTALL_CMD" ]; then
      INSTALL_CMD=$(echo "$INSTALL_OBJ" | jq -r '.manual // "See documentation"')
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
done
fi

# --- Add user freeform additions ---
ADDITION_COUNT=$(echo "$ADDITIONS" | jq 'length')
if [ "$ADDITION_COUNT" -gt 0 ]; then
for i in $(seq 0 $((ADDITION_COUNT - 1))); do
  ADD_JSON=$(echo "$ADDITIONS" | jq ".[$i]")
  ADD_NAME=$(echo "$ADD_JSON" | jq -r '.name')
  ADD_CATEGORY=$(echo "$ADD_JSON" | jq -r '.category // "Custom"')
  ADD_CHECK=$(echo "$ADD_JSON" | jq -r '.check_command // ""')
  ADD_DESC=$(echo "$ADD_JSON" | jq -r '.description // ""')

  if [ -n "$ADD_CHECK" ] && eval "$ADD_CHECK" &>/dev/null 2>&1; then
    ALREADY_INSTALLED=$(echo "$ALREADY_INSTALLED" | jq \
      --arg name "$ADD_NAME" \
      --arg category "$ADD_CATEGORY" \
      --arg version "custom" \
      '. + [{name: $name, category: $category, version: $version}]')
  else
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

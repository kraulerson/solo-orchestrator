#!/bin/bash
# ==============================================================================
# compose.sh — Assembles a base reviewer template + project-type module
# ==============================================================================
#
# USAGE:
#   ./compose.sh <reviewer> <module> [output_file]
#   ./compose.sh --artifact <reviewer>     # print the review's output filename
#
# REVIEWERS: engineer, cio, security, legal, techuser, redteam
# MODULES:   web-app, mobile-app, api-service, cli-tool, framework, desktop-app
#
# PORTABILITY (BL-103)
#   bash-3.2 safe. This file previously used `declare -A` and `[[ -v x ]]` —
#   bash >= 4.2 constructs. macOS ships /bin/bash 3.2.57, which is the repo's
#   reference platform, so the script was a SYNTAX ERROR on the very host the
#   Phase 3→4 gate tells operators to run it on. Reviewer tables are now `case`
#   dispatch functions. Do not reintroduce either construct — it is lint-enforced
#   by scripts/lint-evalprompts-portability.sh.
#
# ARTIFACT FILENAMES — SINGLE SOURCE OF TRUTH (BL-103)
#   The BASE PROMPT declares the filename the reviewer must write, e.g.
#     bases/06-red-team-review.md:
#       Write the complete review to a file named `red-team-review-v1.md` …
#   That declaration is the ONLY place a review's output filename is defined.
#   `reviewer_artifact()` DERIVES it by parsing the prompt; run-reviews.sh calls
#   `compose.sh --artifact <reviewer>` to learn where to look. There is no second
#   table to drift from.
#
#   The bug this replaces: run-reviews.sh probed "${reviewer}-review-v1.md" using
#   its own slug, so `redteam` → redteam-review-v1.md, while the prompt asked for
#   red-team-review-v1.md. Three of six slugs (engineer, techuser, redteam) never
#   resolved, and Red Team — a MANDATORY BLOCKING reviewer at the Phase 3→4 gate
#   — was recorded as missing even when the review had been done and saved
#   exactly as instructed. Derivation makes that class of drift impossible: a
#   prompt with zero or more than one declaration is a hard ERROR, never a silent
#   miss.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASES_DIR="${SCRIPT_DIR}/bases"
MODULES_DIR="${SCRIPT_DIR}/modules"

VALID_REVIEWERS="engineer, cio, security, legal, techuser, redteam"

# reviewer_base <reviewer> — print the base prompt filename; rc=1 if unknown.
reviewer_base() {
    case "$1" in
        engineer) echo "01-senior-engineer.md" ;;
        cio)      echo "02-cio.md" ;;
        security) echo "03-security.md" ;;
        legal)    echo "04-legal.md" ;;
        techuser) echo "05-technical-user.md" ;;
        redteam)  echo "06-red-team-review.md" ;;
        *)        return 1 ;;
    esac
}

# reviewer_tag <reviewer> — print the module section marker tag; rc=1 if unknown.
reviewer_tag() {
    case "$1" in
        engineer) echo "ENGINEER" ;;
        cio)      echo "CIO" ;;
        security) echo "SECURITY" ;;
        legal)    echo "LEGAL" ;;
        techuser) echo "TECHUSER" ;;
        redteam)  echo "REDTEAM" ;;
        *)        return 1 ;;
    esac
}

# reviewer_artifact <reviewer> — DERIVE the review's output filename from the
# base prompt's own declaration. rc=1 (with a message on stderr) when the
# reviewer is unknown, the prompt is missing, or the prompt does not declare
# EXACTLY ONE `<name>-review-v1.md`. Loud failure beats a silent wrong guess:
# a wrong guess is what made the Red Team review invisible to the gate.
reviewer_artifact() {
    local reviewer="$1" base_name base_file decls count
    if ! base_name=$(reviewer_base "$reviewer"); then
        echo "ERROR: Unknown reviewer '$reviewer'. Valid: $VALID_REVIEWERS" >&2
        return 1
    fi
    base_file="${BASES_DIR}/${base_name}"
    if [ ! -f "$base_file" ]; then
        echo "ERROR: Base template not found: $base_file" >&2
        return 1
    fi
    decls=$(grep -o '`[A-Za-z0-9_.-]*-review-v1\.md`' "$base_file" 2>/dev/null | tr -d '`' | sort -u)
    count=$(printf '%s' "$decls" | grep -c . 2>/dev/null || echo "0")
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    if [ "$count" -ne 1 ]; then
        echo "ERROR: ${base_name} must declare EXACTLY ONE \`<name>-review-v1.md\` output filename; found ${count}." >&2
        echo "       The base prompt is the single source of truth for the artifact name (BL-103)." >&2
        return 1
    fi
    printf '%s\n' "$decls"
}

# --artifact <reviewer>: print the derived output filename and exit. This is the
# accessor run-reviews.sh (and any future consumer) uses — never a hardcoded map.
if [ "${1:-}" = "--artifact" ]; then
    if [ $# -lt 2 ]; then
        echo "Usage: $0 --artifact <reviewer>" >&2
        exit 1
    fi
    reviewer_artifact "$2"
    exit $?
fi

if [ $# -lt 2 ]; then
    echo "Usage: $0 <reviewer> <module> [output_file]"
    echo ""
    echo "Reviewers: engineer, cio, security, legal, techuser, redteam"
    echo "Modules:   web-app, mobile-app, api-service, cli-tool, framework, desktop-app"
    exit 1
fi

REVIEWER="$1"
MODULE="$2"
OUTPUT="${3:-}"

if ! BASE_NAME=$(reviewer_base "$REVIEWER"); then
    echo "ERROR: Unknown reviewer '$REVIEWER'. Valid: $VALID_REVIEWERS" >&2
    exit 1
fi

BASE_FILE="${BASES_DIR}/${BASE_NAME}"
MODULE_FILE="${MODULES_DIR}/${MODULE}.md"

if [ ! -f "$BASE_FILE" ]; then
    echo "ERROR: Base template not found: $BASE_FILE" >&2
    exit 1
fi

if [ ! -f "$MODULE_FILE" ]; then
    echo "ERROR: Module not found: $MODULE_FILE" >&2
    exit 1
fi

TAG=$(reviewer_tag "$REVIEWER")

# --- Extract section content between marker tags ---
extract_section() {
    local file="$1"
    local tag="$2"
    local section="$3"
    local open_marker="<!-- ${tag}:${section} -->"
    local end_marker="<!-- /${tag}:${section} -->"

    awk -v om="$open_marker" -v em="$end_marker" '
        index($0, om) { cap=1; next }
        index($0, em) { cap=0; next }
        cap { print }
    ' "$file"
}

# Extract sections from module
SECT_CONTEXT=$(extract_section "$MODULE_FILE" "$TAG" "CONTEXT")
SECT_CATEGORIES=$(extract_section "$MODULE_FILE" "$TAG" "CATEGORIES")
SECT_OUTPUT=$(extract_section "$MODULE_FILE" "$TAG" "OUTPUT")

# --- Assemble: read base line by line, inject content at placeholders ---
assemble() {
    while IFS= read -r line; do
        case "$line" in
            '{{DOMAIN_CONTEXT}}')
                [ -n "$SECT_CONTEXT" ] && printf '%s\n' "$SECT_CONTEXT"
                ;;
            '{{DOMAIN_CATEGORIES}}')
                [ -n "$SECT_CATEGORIES" ] && printf '%s\n' "$SECT_CATEGORIES"
                ;;
            '{{DOMAIN_OUTPUT}}')
                [ -n "$SECT_OUTPUT" ] && printf '%s\n' "$SECT_OUTPUT"
                ;;
            *)
                printf '%s\n' "$line"
                ;;
        esac
    done < "$BASE_FILE"
}

if [ -n "$OUTPUT" ]; then
    assemble > "$OUTPUT"
    echo "Composed: ${REVIEWER} + ${MODULE} → ${OUTPUT}" >&2
else
    assemble
fi

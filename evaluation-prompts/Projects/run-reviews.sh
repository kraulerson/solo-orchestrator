#!/bin/bash
# ==============================================================================
# run-reviews.sh — Execute framework review suite against any project
# ==============================================================================
# Composes base templates + project-type modules, then runs each review
# in a separate Claude Code CLI instance.
#
# USAGE:
#   ./run-reviews.sh <module> [reviewer_numbers...]
#
# EXAMPLES:
#   ./run-reviews.sh web-app              # All 6 reviews for a web app
#   ./run-reviews.sh mobile-app 1 3       # Engineer + Security for mobile
#   ./run-reviews.sh framework            # All 6 reviews for a framework
#   ./run-reviews.sh api-service 2 4 5    # CIO + Legal + TechUser for API
#
# MODULES: web-app, mobile-app, api-service, cli-tool, framework, desktop-app
#
# ENVIRONMENT:
#   PROJECT_DIR  — path to project (default: current directory)
#   REVIEW_DIR   — path to reviews/ directory (default: ./reviews or auto-detect)
#
# OUTPUT:
#   Review files written to the project root directory:
#     senior-engineer-review-v1.md
#     cio-review-v1.md
#     security-review-v1.md
#     legal-review-v1.md
#     technical-user-review-v1.md
#     red-team-review-v1.md
# ==============================================================================

set -euo pipefail

# --- Locate reviews directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if compose.sh is alongside this script (reviews/ is the script dir)
# or if reviews/ is a subdirectory
if [ -f "${SCRIPT_DIR}/compose.sh" ]; then
    REVIEW_DIR="${REVIEW_DIR:-$SCRIPT_DIR}"
elif [ -f "${SCRIPT_DIR}/reviews/compose.sh" ]; then
    REVIEW_DIR="${REVIEW_DIR:-${SCRIPT_DIR}/reviews}"
else
    echo "ERROR: Cannot locate compose.sh. Set REVIEW_DIR to the reviews/ directory."
    exit 1
fi

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

# --- Validate ---
if ! command -v claude &> /dev/null; then
    echo "ERROR: 'claude' CLI not found. Install Claude Code first."
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory not found: $PROJECT_DIR"
    exit 1
fi

chmod +x "${REVIEW_DIR}/compose.sh" 2>/dev/null || true

# --- Args ---
usage() {
    echo "Usage: $0 <module> [reviewer_numbers...]"
    echo ""
    echo "Modules: web-app, mobile-app, api-service, cli-tool, framework, desktop-app"
    echo ""
    echo "Reviewers:"
    echo "  1 = Senior Software Engineer"
    echo "  2 = CIO"
    echo "  3 = SVP IT Security"
    echo "  4 = Corporate Legal"
    echo "  5 = Technical User (Non-Coder)"
    echo "  6 = Red Team / Offensive Security"
    echo ""
    echo "Examples:"
    echo "  $0 web-app           # All 5 reviews"
    echo "  $0 mobile-app 1 3    # Engineer + Security only"
    echo "  $0 framework 2 4 5   # CIO + Legal + TechUser"
    echo ""
    echo "Environment:"
    echo "  PROJECT_DIR=/path/to/project $0 web-app"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

MODULE="$1"
shift

# Validate module exists
if [ ! -f "${REVIEW_DIR}/modules/${MODULE}.md" ]; then
    echo "ERROR: Module '${MODULE}' not found."
    echo "Available modules:"
    ls -1 "${REVIEW_DIR}/modules/"*.md 2>/dev/null | xargs -I{} basename {} .md
    exit 1
fi

# Reviewer definitions
declare -A REVIEWERS
REVIEWERS[1]="engineer|Senior Software Engineer"
REVIEWERS[2]="cio|CIO Strategic"
REVIEWERS[3]="security|SVP IT Security"
REVIEWERS[4]="legal|Corporate Legal"
REVIEWERS[5]="techuser|Technical User (Non-Coder)"
REVIEWERS[6]="redteam|Red Team / Offensive Security"

# Determine which reviews to run
if [ $# -eq 0 ]; then
    TARGETS=(1 2 3 4 5 6)
else
    TARGETS=("$@")
fi

# --- Temp directory for composed prompts ---
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# --- Run ---
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     PROJECT REVIEW SUITE                        ║"
echo "║     Module: ${MODULE}$(printf '%*s' $((26 - ${#MODULE})) '')║"
echo "║     Reviews: ${#TARGETS[@]}$(printf '%*s' 36 '')║"
echo "║     Project: ${PROJECT_DIR:0:34}$(printf '%*s' $((1)) '')║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Capture provenance for review traceability
COMMIT_HASH=$(cd "$PROJECT_DIR" && git rev-parse HEAD 2>/dev/null || echo "no-git")
COMMIT_SHORT=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "no-git")
REVIEW_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# BL-073: the review-manifest contract carries a YYYY-MM-DD `date` field
# (validated by scripts/lint-review-manifest.sh and read by the phase gate).
REVIEW_DATE="${REVIEW_TIMESTAMP%%T*}"

for num in "${TARGETS[@]}"; do
    if [[ ! -v "REVIEWERS[$num]" ]]; then
        echo "WARNING: Review $num does not exist. Valid: 1-6"
        continue
    fi

    entry="${REVIEWERS[$num]}"
    reviewer="${entry%%|*}"
    description="${entry##*|}"
    prompt_file="${TEMP_DIR}/${reviewer}-prompt.md"

    echo "=============================================="
    echo "  REVIEW $num: $description"
    echo "=============================================="
    echo "  Composing: ${reviewer} + ${MODULE}"

    # Compose the prompt
    "${REVIEW_DIR}/compose.sh" "$reviewer" "$MODULE" "$prompt_file"

    # Append provenance instruction so the reviewer includes it in output
    cat >> "$prompt_file" << PROVEOF

---
## Review Provenance (include this header verbatim in your output)

| Field | Value |
|---|---|
| **Reviewed commit** | ${COMMIT_HASH} |
| **Review timestamp** | ${REVIEW_TIMESTAMP} |
| **Module** | ${MODULE} |
| **Reviewer** | ${description} |
PROVEOF

    echo "  Directory: $PROJECT_DIR"
    echo "  Commit: $COMMIT_SHORT"
    echo "  Started: $(date)"
    echo "----------------------------------------------"

    # Run claude code with the composed prompt from the project directory
    (cd "$PROJECT_DIR" && claude -p "$(cat "$prompt_file")")

    echo ""
    echo "  Completed: $(date)"
    echo "=============================================="
    echo ""
done

# --- Generate review manifest ---
MANIFEST_DIR="$PROJECT_DIR/docs/eval-results"
MANIFEST_FILE="$MANIFEST_DIR/review-manifest.json"
mkdir -p "$MANIFEST_DIR"

echo "Generating review manifest..."

# Build manifest entries
MANIFEST_ENTRIES=""
for num in "${TARGETS[@]}"; do
    if [[ ! -v "REVIEWERS[$num]" ]]; then
        continue
    fi

    entry="${REVIEWERS[$num]}"
    reviewer="${entry%%|*}"
    description="${entry##*|}"

    # Find the review output file
    REVIEW_FILE="$PROJECT_DIR/${reviewer}-review-v1.md"
    if [ -f "$REVIEW_FILE" ]; then
        FILE_SHA=$(shasum -a 256 "$REVIEW_FILE" | cut -d' ' -f1)
        # BL-073 contract: reviewer/status/artifact/signed_by/date are the
        # fields the phase gate + lint-review-manifest.sh read. An entry is
        # only written when the review file exists, so status is "complete".
        # The provenance fields (file/sha256/commit/timestamp) are retained
        # as allowed extras for traceability.
        MANIFEST_ENTRIES="${MANIFEST_ENTRIES}    {\"reviewer\": \"${description}\", \"status\": \"complete\", \"artifact\": \"${reviewer}-review-v1.md\", \"signed_by\": \"AI review (${description})\", \"date\": \"${REVIEW_DATE}\", \"file\": \"${reviewer}-review-v1.md\", \"sha256\": \"${FILE_SHA}\", \"commit\": \"${COMMIT_HASH}\", \"timestamp\": \"${REVIEW_TIMESTAMP}\"},"$'\n'
    fi
done

# Write manifest (remove trailing comma)
cat > "$MANIFEST_FILE" << MANEOF
{
  "framework_version": "1.0",
  "module": "$MODULE",
  "project_dir": "$PROJECT_DIR",
  "generated_at": "$REVIEW_TIMESTAMP",
  "commit": "$COMMIT_HASH",
  "reviews": [
$(echo "$MANIFEST_ENTRIES" | sed '$ s/,$//')
  ]
}
MANEOF

echo ""
echo "All requested reviews complete."
echo "Output files in: $PROJECT_DIR/"
ls -la "$PROJECT_DIR"/*-review-v1.md 2>/dev/null || echo "(No review files found — check for errors above)"
echo ""
echo "Review manifest: $MANIFEST_FILE"

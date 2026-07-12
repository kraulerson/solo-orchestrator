#!/bin/bash
# ==============================================================================
# Framework Review Runner
# ==============================================================================
# Runs review prompts against the Solo Orchestrator framework.
# Each review runs in a separate Claude Code CLI instance.
#
# USAGE:
#   ./run-reviews.sh                    # Run all 6 reviews sequentially
#   ./run-reviews.sh 1                  # Run only the Senior Engineer review
#   ./run-reviews.sh 3                  # Run only the Security review
#   ./run-reviews.sh 1 3 6             # Run specific reviews
#
# ENVIRONMENT:
#   FRAMEWORK_DIR  — path to framework (default: current directory)
#   PROMPT_DIR     — path to prompt files (default: this script's directory)
#
# OUTPUT:
#   Each review writes a markdown file to the framework project root:
#     senior-engineer-review-v1.md
#     cio-review-v1.md
#     security-review-v1.md
#     legal-review-v1.md
#     technical-user-review-v1.md
#     (red team outputs inline deliverable)
#
# PORTABILITY (BL-103)
#   bash-3.2 safe. This script previously used `declare -A` + `[[ -v x ]]`
#   (bash >= 4.2) and was a SYNTAX ERROR on macOS /bin/bash 3.2.57, the repo's
#   reference platform. The review table is now `case` dispatch. Lint-enforced by
#   scripts/lint-evalprompts-portability.sh.
# ==============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="${FRAMEWORK_DIR:-.}"
PROMPT_DIR="${PROMPT_DIR:-$SCRIPT_DIR}"

# Verify claude is available
if ! command -v claude &> /dev/null; then
    echo "ERROR: 'claude' CLI not found. Install Claude Code first."
    exit 1
fi

# Verify framework directory exists and looks like a project
if [ ! -d "$FRAMEWORK_DIR" ]; then
    echo "ERROR: Framework directory not found: $FRAMEWORK_DIR"
    exit 1
fi

# Review definitions: number → <prompt file>|<description>. rc=1 if unknown.
review_entry() {
    case "$1" in
        1) echo "01-senior-engineer-review.md|Senior Software Engineer" ;;
        2) echo "02-cio-review.md|CIO Strategic" ;;
        3) echo "03-security-review.md|SVP IT Security" ;;
        4) echo "04-legal-review.md|Corporate Legal" ;;
        5) echo "05-technical-user-review.md|Technical User (Non-Coder)" ;;
        6) echo "06-red-team-evaluation.md|Red Team / AppSec" ;;
        *) return 1 ;;
    esac
}

run_review() {
    local num=$1
    local entry
    entry=$(review_entry "$num") || return 1
    local prompt_file="${entry%%|*}"
    local description="${entry##*|}"
    local prompt_path="${PROMPT_DIR}/${prompt_file}"

    if [ ! -f "$prompt_path" ]; then
        echo "ERROR: Prompt file not found: $prompt_path"
        return 1
    fi

    echo "=============================================="
    echo "  REVIEW $num: $description"
    echo "=============================================="
    echo "  Prompt: $prompt_file"
    echo "  Directory: $FRAMEWORK_DIR"
    echo "  Started: $(date)"
    echo "----------------------------------------------"

    # Run claude code with the prompt, from the framework directory
    cd "$FRAMEWORK_DIR"
    claude -p "$(cat "$prompt_path")"

    echo ""
    echo "  Completed: $(date)"
    echo "=============================================="
    echo ""
}

# Determine which reviews to run
if [ $# -eq 0 ]; then
    # Run all reviews
    TARGETS=(1 2 3 4 5 6)
else
    TARGETS=("$@")
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     FRAMEWORK REVIEW SUITE                  ║"
echo "║     Running ${#TARGETS[@]} review(s)                       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

for num in "${TARGETS[@]}"; do
    if review_entry "$num" >/dev/null 2>&1; then
        run_review "$num"
    else
        echo "WARNING: Review $num does not exist. Valid: 1-6"
    fi
done

echo ""
echo "All requested reviews complete."
echo "Output files are in: $FRAMEWORK_DIR/"
ls -la "$FRAMEWORK_DIR"/*-review-v1.md 2>/dev/null || echo "(No review files found — check for errors above)"

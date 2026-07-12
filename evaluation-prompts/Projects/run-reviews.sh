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
#   Review files written to the project root directory. The FILENAME OF RECORD
#   for each review is declared by its base prompt (bases/*.md) and resolved here
#   via `compose.sh --artifact <reviewer>` — this script keeps NO filename table
#   of its own. See compose.sh's header (BL-103) for why.
#     senior-engineer-review-v1.md
#     cio-review-v1.md
#     security-review-v1.md
#     legal-review-v1.md
#     technical-user-review-v1.md
#     red-team-review-v1.md
#
# PORTABILITY (BL-103)
#   bash-3.2 safe. This script previously used `declare -A` and `[[ -v x ]]`
#   (bash >= 4.2) and was therefore a SYNTAX ERROR on macOS /bin/bash 3.2.57 —
#   the repo's reference platform, and the shell an operator runs it in when the
#   Phase 3→4 gate hands them this path as the remediation. Reviewer tables are
#   now `case` dispatch. Lint-enforced by scripts/lint-evalprompts-portability.sh.
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

# Reviewer definitions — <slug>|<persona description>.
# The persona description is what lands in the manifest's `reviewer` field;
# check-phase-gate.sh's role mapping matches on it ("Red Team / Offensive
# Security" → redteam, "SVP IT Security" → security), so do not reword these
# without re-checking that mapping.
# NOTE: no output FILENAME appears here by design — that is derived from the base
# prompt (compose.sh --artifact). See compose.sh's header (BL-103).
reviewer_entry() {
    case "$1" in
        1) echo "engineer|Senior Software Engineer" ;;
        2) echo "cio|CIO Strategic" ;;
        3) echo "security|SVP IT Security" ;;
        4) echo "legal|Corporate Legal" ;;
        5) echo "techuser|Technical User (Non-Coder)" ;;
        6) echo "redteam|Red Team / Offensive Security" ;;
        *) return 1 ;;
    esac
}

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
    if ! entry=$(reviewer_entry "$num"); then
        echo "WARNING: Review $num does not exist. Valid: 1-6"
        continue
    fi

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
    if ! entry=$(reviewer_entry "$num"); then
        continue
    fi

    reviewer="${entry%%|*}"
    description="${entry##*|}"

    # BL-103: DERIVE the expected filename from the base prompt's own
    # declaration rather than assuming "<slug>-review-v1.md". The slug and the
    # filename are NOT the same string for three of the six reviewers
    # (engineer→senior-engineer, techuser→technical-user, redteam→red-team), and
    # the old assumption silently dropped those entries from the manifest — so a
    # completed Red Team review (a MANDATORY BLOCKING reviewer at the Phase 3→4
    # gate) read as "missing" and FAILed the gate.
    ARTIFACT=$(REVIEW_DIR="$REVIEW_DIR" "${REVIEW_DIR}/compose.sh" --artifact "$reviewer") || {
        echo "ERROR: cannot resolve the output filename for reviewer '${reviewer}' from its base prompt." >&2
        echo "       The base prompt must declare exactly one \`<name>-review-v1.md\`." >&2
        exit 1
    }

    # Find the review output file (at the name the prompt itself asked for).
    REVIEW_FILE="$PROJECT_DIR/${ARTIFACT}"
    if [ -f "$REVIEW_FILE" ]; then
        FILE_SHA=$(shasum -a 256 "$REVIEW_FILE" | cut -d' ' -f1)
        # BL-073 contract: reviewer/status/artifact/signed_by/date are the
        # fields the phase gate + lint-review-manifest.sh read. An entry is
        # only written when the review file exists, so status is "complete".
        # The provenance fields (file/sha256/commit/timestamp) are retained
        # as allowed extras for traceability.
        MANIFEST_ENTRIES="${MANIFEST_ENTRIES}    {\"reviewer\": \"${description}\", \"status\": \"complete\", \"artifact\": \"${ARTIFACT}\", \"signed_by\": \"AI review (${description})\", \"date\": \"${REVIEW_DATE}\", \"file\": \"${ARTIFACT}\", \"sha256\": \"${FILE_SHA}\", \"commit\": \"${COMMIT_HASH}\", \"timestamp\": \"${REVIEW_TIMESTAMP}\"},"$'\n'
    else
        # Loud, not silent: a requested review with no output file on disk is a
        # gap the operator must see. The pre-BL-103 script emitted nothing here,
        # which is exactly how the red-team drop went unnoticed.
        echo "  WARNING: review $num (${description}) produced no ${ARTIFACT} — not recorded in the manifest."
    fi
done

# Strip the trailing "," from the last entry.
#
# BL-103: the previous expression — $(echo "$MANIFEST_ENTRIES" | sed '$ s/,$//')
# — DID NOT WORK. MANIFEST_ENTRIES is already newline-terminated, so `echo` added
# a SECOND newline; sed's `$` address then landed on the trailing EMPTY line and
# the real last entry kept its comma. Every manifest this generator has ever
# written was therefore invalid JSON — `jq empty` rejects it, so
# scripts/lint-review-manifest.sh FAILs it and check-phase-gate.sh's `jq
# '.reviews | length'` yields nothing. Nobody saw it because the script could not
# even parse on the reference platform (bash 3.2), so it never got this far.
# Trim the delimiter off the variable instead of round-tripping through echo.
MANIFEST_ENTRIES="${MANIFEST_ENTRIES%,$'\n'}"

cat > "$MANIFEST_FILE" << MANEOF
{
  "framework_version": "1.0",
  "module": "$MODULE",
  "project_dir": "$PROJECT_DIR",
  "generated_at": "$REVIEW_TIMESTAMP",
  "commit": "$COMMIT_HASH",
  "reviews": [
$MANIFEST_ENTRIES
  ]
}
MANEOF

# Self-check: a malformed manifest silently defeats the Phase 3→4 review gate
# (jq yields nothing → the gate reads "no reviews"). Refuse to hand the operator
# a file that will not parse — fail loudly here instead.
if command -v jq >/dev/null 2>&1; then
    if ! jq empty "$MANIFEST_FILE" >/dev/null 2>&1; then
        echo "ERROR: generated manifest is not valid JSON: $MANIFEST_FILE" >&2
        echo "       The Phase 3→4 review gate cannot read it. This is a generator bug — please report." >&2
        exit 1
    fi
fi

echo ""
echo "All requested reviews complete."
echo "Output files in: $PROJECT_DIR/"
ls -la "$PROJECT_DIR"/*-review-v1.md 2>/dev/null || echo "(No review files found — check for errors above)"
echo ""
echo "Review manifest: $MANIFEST_FILE"

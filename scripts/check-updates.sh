#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Framework Update Checker
# https://github.com/kraulerson/solo-orchestrator
#
# Compares framework documents in the current project against the latest
# version in the solo-orchestrator repo. Reports which documents have changed
# upstream since the project was created. Does NOT auto-apply changes.
#
# Usage: bash scripts/check-updates.sh [/path/to/solo-orchestrator]
#
# If no path is provided, attempts to clone the latest version to a temp dir.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

# Verify we're in a Solo Orchestrator project
if [ ! -f "CLAUDE.md" ]; then
  echo -e "${RED}ERROR: CLAUDE.md not found. Run this from a Solo Orchestrator project directory.${NC}"
  exit 1
fi

UPSTREAM="${1:-}"
TEMP_CLONE=""

if [ -z "$UPSTREAM" ]; then
  print_info "No upstream path provided. Cloning latest version..."
  TEMP_CLONE=$(mktemp -d)
  if git clone -q --depth 1 https://github.com/kraulerson/solo-orchestrator.git "$TEMP_CLONE" 2>/dev/null; then
    UPSTREAM="$TEMP_CLONE"
    print_ok "Cloned latest upstream to temp directory"
  else
    echo -e "${RED}ERROR: Could not clone solo-orchestrator repo. Provide the path manually:${NC}"
    echo "  bash scripts/check-updates.sh /path/to/solo-orchestrator"
    rm -rf "$TEMP_CLONE"
    exit 1
  fi
fi

# Verify the upstream path looks like the solo-orchestrator repo
if [ ! -f "$UPSTREAM/init.sh" ] || [ ! -f "$UPSTREAM/docs/builders-guide.md" ]; then
  echo -e "${RED}ERROR: $UPSTREAM does not appear to be the solo-orchestrator repo.${NC}"
  [ -n "$TEMP_CLONE" ] && rm -rf "$TEMP_CLONE"
  exit 1
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      Solo Orchestrator — Update Check                   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show pinned version if available
if [ -f ".claude/framework-version.txt" ]; then
  pinned_sha=$(cat .claude/framework-version.txt)
  print_info "Project pinned at framework version: ${pinned_sha:0:12}"
fi

changes=0

# Check framework documents
echo ""
echo -e "${BOLD}── Framework Documents ──${NC}"

check_file() {
  local project_path="$1"
  local upstream_path="$2"
  local label="$3"

  if [ ! -f "$project_path" ]; then
    print_warn "$label: not found in project"
    return
  fi

  if [ ! -f "$upstream_path" ]; then
    print_info "$label: not in upstream (may be project-specific)"
    return
  fi

  if diff -q "$project_path" "$upstream_path" >/dev/null 2>&1; then
    print_ok "$label: up to date"
  else
    print_warn "$label: differs from upstream"
    # Show a brief summary of changes
    local added removed
    added=$(diff "$project_path" "$upstream_path" | grep -c '^>' || true)
    removed=$(diff "$project_path" "$upstream_path" | grep -c '^<' || true)
    echo -e "         (+$added lines in upstream, -$removed lines removed from upstream)"
    changes=$((changes + 1))
  fi
}

check_file "docs/reference/builders-guide.md"       "$UPSTREAM/docs/builders-guide.md"       "Builder's Guide"
check_file "docs/reference/governance-framework.md"  "$UPSTREAM/docs/governance-framework.md"  "Governance Framework"
check_file "docs/reference/executive-review.md"      "$UPSTREAM/docs/executive-review.md"      "Executive Review"
check_file "docs/reference/cli-setup-addendum.md"    "$UPSTREAM/docs/cli-setup-addendum.md"    "CLI Setup Addendum"
check_file "docs/reference/user-guide.md"            "$UPSTREAM/docs/user-guide.md"            "User Guide"

# Check platform modules (only the ones present in the project)
echo ""
echo -e "${BOLD}── Platform Modules ──${NC}"

for module in docs/platform-modules/*.md; do
  [ -f "$module" ] || continue
  basename=$(basename "$module")
  check_file "$module" "$UPSTREAM/docs/platform-modules/$basename" "Platform: $basename"
done

# Check utility scripts
echo ""
echo -e "${BOLD}── Utility Scripts ──${NC}"

check_file "scripts/validate.sh"         "$UPSTREAM/scripts/validate.sh"         "validate.sh"
check_file "scripts/check-phase-gate.sh" "$UPSTREAM/scripts/check-phase-gate.sh" "check-phase-gate.sh"

# Check CI pipeline template (just report — CI may have been customized intentionally)
echo ""
echo -e "${BOLD}── CI Pipeline ──${NC}"

if [ -f ".github/workflows/ci.yml" ]; then
  # Detect language from CLAUDE.md
  lang=$(grep -m1 'Primary Language' CLAUDE.md | sed 's/.*\*\* //' || echo "unknown")
  ci_template=""
  case "$lang" in
    typescript|javascript) ci_template="typescript.yml" ;;
    python)                ci_template="python.yml" ;;
    rust)                  ci_template="rust.yml" ;;
    csharp)                ci_template="csharp.yml" ;;
    kotlin)                ci_template="kotlin.yml" ;;
    java)                  ci_template="java.yml" ;;
    go)                    ci_template="go.yml" ;;
    dart)                  ci_template="dart.yml" ;;
    *)                     ci_template="" ;;
  esac

  if [ -n "$ci_template" ] && [ -f "$UPSTREAM/templates/pipelines/ci/$ci_template" ]; then
    if diff -q ".github/workflows/ci.yml" "$UPSTREAM/templates/pipelines/ci/$ci_template" >/dev/null 2>&1; then
      print_ok "CI pipeline: matches upstream template ($ci_template)"
    else
      print_info "CI pipeline: differs from upstream template ($ci_template) — may be intentionally customized"
    fi
  else
    print_info "CI pipeline: could not determine upstream template for language '$lang'"
  fi
else
  print_warn "CI pipeline: .github/workflows/ci.yml not found"
fi

# Summary
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
if [ $changes -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  All framework documents are up to date.${NC}"
else
  echo -e "${YELLOW}${BOLD}  $changes document(s) differ from upstream.${NC}"
  echo ""
  echo "  To review changes:"
  echo "    diff docs/reference/[file] $UPSTREAM/docs/[file]"
  echo ""
  echo "  To update a document:"
  echo "    cp $UPSTREAM/docs/[file] docs/reference/[file]"
  echo ""
  echo "  Review changes carefully before overwriting — your project may have"
  echo "  intentional customizations that should be preserved."
fi
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"

# Clean up temp clone
[ -n "$TEMP_CLONE" ] && rm -rf "$TEMP_CLONE"

exit 0

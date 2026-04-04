#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Project Validation Script
# https://github.com/kraulerson/solo-orchestrator
#
# Run this from a Solo Orchestrator project directory to check framework
# compliance. Catches drift that accumulates over weeks of development.
#
# Usage: bash scripts/validate.sh
#    or: bash /path/to/solo-orchestrator/scripts/validate.sh (from any project)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

print_section() { echo ""; echo -e "${BOLD}── $1 ──${NC}"; }

errors=0
warnings=0

fail() { errors=$((errors + 1)); print_fail "$1"; }
warn() { warnings=$((warnings + 1)); print_warn "$1"; }

# ================================================================
# Verify we're in a Solo Orchestrator project
# ================================================================
if [ ! -f "CLAUDE.md" ]; then
  echo -e "${RED}ERROR: CLAUDE.md not found. Run this script from a Solo Orchestrator project directory.${NC}"
  exit 1
fi

# Extract project metadata from CLAUDE.md
PROJECT_NAME=$(grep -m1 '^\- \*\*Project:\*\*' CLAUDE.md | sed 's/.*\*\* //' || echo "unknown")
PLATFORM=$(grep -m1 '^\- \*\*Platform:\*\*' CLAUDE.md | sed 's/.*\*\* //' || echo "unknown")
TRACK=$(grep -m1 '^\- \*\*Track:\*\*' CLAUDE.md | sed 's/.*\*\* //' || echo "unknown")
LANGUAGE=$(grep -m1 '^\- \*\*Primary Language:\*\*' CLAUDE.md | sed 's/.*\*\* //' || echo "unknown")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      Solo Orchestrator — Project Validation             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Project:${NC}  $PROJECT_NAME"
echo -e "${BOLD}Platform:${NC} $PLATFORM | ${BOLD}Track:${NC} $TRACK | ${BOLD}Language:${NC} $LANGUAGE"

# ================================================================
# 1. Framework Files
# ================================================================
print_section "Framework Files"

[ -f "CLAUDE.md" ]                         && print_ok "CLAUDE.md" || fail "CLAUDE.md missing"
[ -f "PROJECT_INTAKE.md" ]                 && print_ok "PROJECT_INTAKE.md" || fail "PROJECT_INTAKE.md missing"
[ -f "APPROVAL_LOG.md" ]                   && print_ok "APPROVAL_LOG.md" || fail "APPROVAL_LOG.md missing"
[ -f "docs/framework/builders-guide.md" ]  && print_ok "Builder's Guide" || fail "Builder's Guide missing"
[ -f "docs/framework/user-guide.md" ]      && print_ok "User Guide" || fail "User Guide missing"
[ -f "docs/framework/governance-framework.md" ] && print_ok "Governance Framework" || fail "Governance Framework missing"
[ -f "docs/framework/cli-setup-addendum.md" ]   && print_ok "CLI Setup Addendum" || fail "CLI Setup Addendum missing"
[ -f ".gitignore" ]                        && print_ok ".gitignore" || fail ".gitignore missing"

# Platform module (check based on detected platform)
case "$PLATFORM" in
  web)     [ -f "docs/platform-modules/web.md" ]     && print_ok "Platform Module: Web" || fail "Platform Module: Web missing" ;;
  desktop) [ -f "docs/platform-modules/desktop.md" ] && print_ok "Platform Module: Desktop" || fail "Platform Module: Desktop missing" ;;
  mobile)  [ -f "docs/platform-modules/mobile.md" ]  && print_ok "Platform Module: Mobile" || fail "Platform Module: Mobile missing" ;;
  cli)     print_info "No platform module for CLI (Builder's Guide works standalone)" ;;
  *)       print_info "Platform: $PLATFORM — no module expected" ;;
esac

# ================================================================
# 2. Git & Hooks
# ================================================================
print_section "Git & Hooks"

[ -d ".git" ]                     && print_ok "Git repository" || fail "Not a git repository"
[ -x ".git/hooks/pre-commit" ]    && print_ok "Pre-commit hook" || warn "Pre-commit hook missing or not executable"
[ -x "scripts/validate.sh" ]      && print_ok "Validation script" || warn "scripts/validate.sh missing"
[ -x "scripts/check-phase-gate.sh" ] && print_ok "Phase gate check script" || warn "scripts/check-phase-gate.sh missing"
[ -d ".claude/framework" ]        && print_ok "Claude Dev Framework" || warn "Claude Dev Framework not installed"

if [ -f ".claude/framework-version.txt" ]; then
  local_sha=$(cat .claude/framework-version.txt)
  print_info "Framework pinned at: ${local_sha:0:12}"
fi

# ================================================================
# 3. CI/CD Pipelines
# ================================================================
print_section "CI/CD Pipelines"

[ -f ".github/workflows/ci.yml" ] && print_ok "CI pipeline" || fail "CI pipeline missing (.github/workflows/ci.yml)"

if [ -f ".github/workflows/release.yml" ]; then
  # Check if release pipeline still has uncommented TODO placeholders
  todo_count=$(grep -c "# TODO\|echo.*TODO" .github/workflows/release.yml 2>/dev/null || echo "0")
  if [ "$todo_count" -gt 0 ]; then
    print_ok "Release pipeline (${todo_count} TODOs remaining — configure before first release)"
  else
    print_ok "Release pipeline (configured)"
  fi
else
  warn "Release pipeline missing (.github/workflows/release.yml)"
fi

# ================================================================
# 4. Security Tools
# ================================================================
print_section "Security Tools"

command -v semgrep &>/dev/null  && print_ok "Semgrep" || fail "Semgrep not found — required for SAST scanning"
command -v gitleaks &>/dev/null && print_ok "gitleaks" || fail "gitleaks not found — required for secret detection"
command -v snyk &>/dev/null     && print_ok "Snyk CLI" || warn "Snyk not found — required for dependency vulnerability scanning"

# ================================================================
# 5. Phase State & Artifacts
# ================================================================
print_section "Phase State & Artifacts"

# Detect current phase: prefer phase-state.json, fall back to artifact inference
phase=0
phase_source="artifact inference"

if [ -f ".claude/phase-state.json" ]; then
  state_phase=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*[0-9]' .claude/phase-state.json | grep -o '[0-9]$' || echo "")
  if [ -n "$state_phase" ]; then
    phase=$state_phase
    phase_source="phase-state.json"
    print_ok "Phase state file found (current_phase: $phase)"
  else
    warn "Phase state file exists but current_phase could not be read"
  fi
else
  print_info "No .claude/phase-state.json — detecting phase from artifacts"
fi

# Check artifacts exist and flag missing ones based on current phase
# If using artifact inference (no phase-state.json), also advance the phase counter
artifact_phase=0

if [ -f "PRODUCT_MANIFESTO.md" ]; then
  print_ok "PRODUCT_MANIFESTO.md (Phase 0 output)"
  artifact_phase=1
else
  if [ $phase -ge 1 ]; then
    warn "PRODUCT_MANIFESTO.md missing — expected for Phase $phase"
  else
    print_info "No PRODUCT_MANIFESTO.md — project is in Phase 0 or earlier"
  fi
fi

if [ -f "PROJECT_BIBLE.md" ]; then
  print_ok "PROJECT_BIBLE.md (Phase 1 output)"
  artifact_phase=2
else
  if [ $phase -ge 2 ]; then
    warn "PROJECT_BIBLE.md missing — expected for Phase $phase"
  fi
fi

if [ -f "CONTRIBUTING.md" ]; then
  print_ok "CONTRIBUTING.md (Phase 2 artifact)"
fi

if [ -f "CHANGELOG.md" ]; then
  print_ok "CHANGELOG.md"
else
  if [ $phase -ge 2 ]; then
    warn "CHANGELOG.md missing — should exist by Phase 2"
  fi
fi

if [ -d "docs/test-results" ] && [ "$(ls -A docs/test-results 2>/dev/null)" ]; then
  result_count=$(ls -1 docs/test-results/ 2>/dev/null | wc -l | tr -d ' ')
  print_ok "docs/test-results/ ($result_count archived results)"
  artifact_phase=3
else
  if [ $phase -ge 3 ]; then
    warn "docs/test-results/ is empty — should contain Phase 3 scan results"
  fi
fi

if [ -f "HANDOFF.md" ]; then
  print_ok "HANDOFF.md (Phase 4 output)"
  artifact_phase=4
fi

if [ -f "RELEASE_NOTES.md" ]; then
  print_ok "RELEASE_NOTES.md (Phase 4 output)"
fi

if [ -f "docs/INCIDENT_RESPONSE.md" ]; then
  print_ok "docs/INCIDENT_RESPONSE.md (Phase 4 output)"
fi

# If no phase-state.json, use artifact inference
if [ "$phase_source" = "artifact inference" ]; then
  phase=$artifact_phase
fi

# Flag mismatch between phase-state.json and artifacts
if [ "$phase_source" = "phase-state.json" ] && [ $artifact_phase -ne $phase ] && [ $artifact_phase -gt 0 ]; then
  warn "Phase state ($phase) does not match artifact evidence (artifacts suggest phase $artifact_phase) — update .claude/phase-state.json"
fi

print_info "Project phase: $phase (source: $phase_source)"

# ================================================================
# 6. Approval Log Completeness
# ================================================================
print_section "Approval Log"

if [ -f "APPROVAL_LOG.md" ]; then
  # Check if phase gates have been filled in based on detected phase
  if [ $phase -ge 1 ]; then
    if grep -q "Phase 0 → Phase 1" APPROVAL_LOG.md; then
      # Check if the gate has actual content (not just template)
      gate_01_date=$(grep -A 10 "Phase 0 → Phase 1" APPROVAL_LOG.md | grep -i "date" | head -1 || true)
      if echo "$gate_01_date" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        print_ok "Phase 0→1 gate: dated entry found"
      else
        warn "Phase 0→1 gate: no date recorded — project appears to be past Phase 0"
      fi
    fi
  fi

  if [ $phase -ge 2 ]; then
    if grep -q "Phase 1 → Phase 2" APPROVAL_LOG.md; then
      gate_12_date=$(grep -A 10 "Phase 1 → Phase 2" APPROVAL_LOG.md | grep -i "date" | head -1 || true)
      if echo "$gate_12_date" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        print_ok "Phase 1→2 gate: dated entry found"
      else
        warn "Phase 1→2 gate: no date recorded — project appears to be past Phase 1"
      fi
    fi
  fi

  if [ $phase -ge 4 ]; then
    if grep -q "Phase 3 → Phase 4" APPROVAL_LOG.md; then
      gate_34_date=$(grep -A 10 "Phase 3 → Phase 4" APPROVAL_LOG.md | grep -i "date" | head -1 || true)
      if echo "$gate_34_date" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        print_ok "Phase 3→4 gate: dated entry found"
      else
        warn "Phase 3→4 gate: no date recorded — project appears to be past Phase 3"
      fi
    fi
  fi
else
  fail "APPROVAL_LOG.md missing"
fi

# ================================================================
# 7. CLAUDE.md Currency
# ================================================================
print_section "CLAUDE.md Currency"

if [ -f "CLAUDE.md" ]; then
  # Check if key sections have been updated from template defaults
  if grep -q "Features built:.*none yet\|Features remaining:.*see MVP Cutline" CLAUDE.md; then
    if [ $phase -ge 2 ]; then
      warn "CLAUDE.md still has template defaults for 'Features built/remaining' — update for Phase 2+"
    else
      print_ok "CLAUDE.md current state: template defaults (appropriate for Phase 0-1)"
    fi
  else
    print_ok "CLAUDE.md current state: customized"
  fi

  # Check if architecture constraints section exists (should be present after Phase 1)
  if [ $phase -ge 2 ]; then
    if grep -q "Architecture Constraints\|## Stack\|## Architecture" CLAUDE.md; then
      print_ok "CLAUDE.md has architecture section"
    else
      warn "CLAUDE.md missing architecture constraints — should be added after Phase 1"
    fi
  fi
fi

# ================================================================
# 8. Intake Completeness
# ================================================================
print_section "Intake Completeness"

if [ -f "PROJECT_INTAKE.md" ]; then
  # Count blank table cells (likely unfilled fields)
  blank_cells=$(grep -cE '\| *\|$|\| *$' PROJECT_INTAKE.md 2>/dev/null || true)
  blank_cells=$(echo "$blank_cells" | tr -d '[:space:]')
  blank_cells=${blank_cells:-0}
  # Count N/A entries (explicitly marked as not applicable — this is fine)
  na_cells=$(grep -ciE '\| *N/?A' PROJECT_INTAKE.md 2>/dev/null || true)
  na_cells=$(echo "$na_cells" | tr -d '[:space:]')
  na_cells=${na_cells:-0}

  if [ "$blank_cells" -gt 20 ]; then
    warn "PROJECT_INTAKE.md has ~${blank_cells} blank fields — fill these out before starting Phase 0"
  elif [ "$blank_cells" -gt 5 ]; then
    print_ok "PROJECT_INTAKE.md partially filled (${blank_cells} blank fields, ${na_cells} marked N/A)"
  else
    print_ok "PROJECT_INTAKE.md appears complete (${blank_cells} blank fields, ${na_cells} marked N/A)"
  fi
else
  fail "PROJECT_INTAKE.md missing"
fi

# ================================================================
# 9. Language Runtime
# ================================================================
print_section "Language Runtime"

case "$LANGUAGE" in
  typescript|javascript)
    command -v node &>/dev/null && print_ok "Node.js $(node --version 2>/dev/null)" || fail "Node.js not found (required for $LANGUAGE)" ;;
  python)
    (command -v python3 &>/dev/null || command -v python &>/dev/null) && print_ok "Python $(python3 --version 2>/dev/null || python --version 2>/dev/null)" || fail "Python not found" ;;
  rust)
    command -v cargo &>/dev/null && print_ok "Rust $(rustc --version 2>/dev/null | awk '{print $2}')" || fail "Rust (cargo) not found" ;;
  csharp)
    command -v dotnet &>/dev/null && print_ok ".NET $(dotnet --version 2>/dev/null)" || fail ".NET SDK not found" ;;
  kotlin|java)
    command -v java &>/dev/null && print_ok "Java $(java --version 2>&1 | head -1)" || fail "Java not found" ;;
  go)
    command -v go &>/dev/null && print_ok "Go $(go version 2>/dev/null | awk '{print $3}')" || fail "Go not found" ;;
  dart)
    command -v flutter &>/dev/null && print_ok "Flutter $(flutter --version 2>/dev/null | head -1)" || fail "Flutter not found" ;;
  *)
    print_info "Language: $LANGUAGE — no runtime check available" ;;
esac

# ================================================================
# 10. Competency Matrix vs. CI Tooling
# ================================================================
# The Builder's Guide requires that domains marked "No" in the Competency
# Matrix have mandatory automated tooling in CI. This check parses the
# Intake (if filled out) and verifies CI pipeline coverage.

if [ -f "PROJECT_INTAKE.md" ] && [ -f ".github/workflows/ci.yml" ] && [ $phase -ge 2 ]; then
  print_section "Competency Matrix Coverage"

  ci_content=$(cat .github/workflows/ci.yml)
  matrix_issues=0

  # Extract competency self-assessments from the Intake table
  # The matrix is in Section 6.2 — rows like: | Security ... | No | ... |
  check_competency() {
    local domain="$1"
    local ci_check="$2"
    local tool_name="$3"

    # Look for the domain row in the Intake and check if it contains "No"
    domain_row=$(grep -i "$domain" PROJECT_INTAKE.md | grep -i "|" | head -1 || true)
    if echo "$domain_row" | grep -qi "| *No *|"; then
      # Domain is marked "No" — check CI has the corresponding tool
      if echo "$ci_content" | grep -qiE "$ci_check"; then
        print_ok "$domain: marked 'No' — $tool_name present in CI"
      else
        warn "$domain: marked 'No' but $tool_name not found in CI pipeline"
        matrix_issues=$((matrix_issues + 1))
      fi
    fi
  }

  check_competency "Security"      "semgrep|snyk|sast|zap"        "SAST/dependency scanning"
  check_competency "Accessibility"  "lighthouse|axe|a11y"           "accessibility scanning"
  check_competency "Performance"    "lighthouse|k6|benchmark"       "performance testing"
  check_competency "Database"       "migration|prisma|alembic|flyway" "migration tooling"

  if [ $matrix_issues -eq 0 ]; then
    # Check if any rows were actually filled in
    has_no=$(grep -i "| *No *|" PROJECT_INTAKE.md | grep -ciE "Security|Accessibility|Performance|Database" || echo "0")
    if [ "$has_no" -eq 0 ]; then
      print_info "No domains marked 'No' in Competency Matrix (or matrix not yet filled out)"
    fi
  fi
fi

# ================================================================
# Summary
# ================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  All checks passed.${NC}"
elif [ $errors -eq 0 ]; then
  echo -e "${YELLOW}${BOLD}  $warnings warning(s), 0 errors.${NC}"
  echo -e "  Warnings indicate drift or missing optional items."
else
  echo -e "${RED}${BOLD}  $errors error(s), $warnings warning(s).${NC}"
  echo -e "  Errors indicate missing required files or tools. Resolve before continuing."
fi
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo ""

exit $errors

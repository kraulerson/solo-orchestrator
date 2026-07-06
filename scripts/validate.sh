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
# BL-046: uses print_fail/info/ok/warn only — source core subset.
source "$SCRIPT_DIR/lib/helpers-core.sh"

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
[ -f "docs/reference/builders-guide.md" ]  && print_ok "Builder's Guide" || fail "Builder's Guide missing"
[ -f "docs/reference/user-guide.md" ]      && print_ok "User Guide" || fail "User Guide missing"
[ -f "docs/reference/governance-framework.md" ] && print_ok "Governance Framework" || fail "Governance Framework missing"
[ -f "docs/reference/cli-setup-addendum.md" ]   && print_ok "CLI Setup Addendum" || fail "CLI Setup Addendum missing"
[ -f ".gitignore" ]                        && print_ok ".gitignore" || fail ".gitignore missing"

# Platform module (check based on detected platform)
case "$PLATFORM" in
  web)     [ -f "docs/platform-modules/web.md" ]     && print_ok "Platform Module: Web" || fail "Platform Module: Web missing" ;;
  desktop) [ -f "docs/platform-modules/desktop.md" ] && print_ok "Platform Module: Desktop" || fail "Platform Module: Desktop missing" ;;
  mobile)  [ -f "docs/platform-modules/mobile.md" ]  && print_ok "Platform Module: Mobile" || fail "Platform Module: Mobile missing" ;;
  # Legacy 'cli' platform fallback (BL-047): 'cli' predates the cli->mcp_server rename
  # and is still reachable when a project's CLAUDE.md carries `Platform: cli` (hand-edited
  # or created before the migration). $PLATFORM here is read from the user-editable CLAUDE.md,
  # not init.sh's validated enum, so this arm is intentional graceful degradation — NOT dead
  # code. Do not delete without removing `cli` support end-to-end (option list + docs + here).
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
[ -d ".claude/framework" ]        && print_ok "Development Guardrails for Claude Code" || warn "Development Guardrails for Claude Code not installed"

if [ -f ".claude/manifest.json" ] && command -v jq &>/dev/null; then
  cdf_commit=$(jq -r '.frameworkCommit // empty' .claude/manifest.json 2>/dev/null)
  cdf_version=$(jq -r '.frameworkVersion // empty' .claude/manifest.json 2>/dev/null)
  if [ -n "$cdf_commit" ] || [ -n "$cdf_version" ]; then
    print_info "Development Guardrails pinned at: ${cdf_version:-unknown}${cdf_commit:+ (${cdf_commit:0:12})}"
  fi
fi

# ================================================================
# 3. CI/CD Pipelines
# ================================================================
print_section "CI/CD Pipelines"

[ -f ".github/workflows/ci.yml" ] && print_ok "CI pipeline" || fail "CI pipeline missing (.github/workflows/ci.yml)"

if [ -f ".github/workflows/release.yml" ]; then
  # Check if release pipeline still has uncommented TODO placeholders
  todo_count=$(grep -cE "# TODO|echo.*TODO" .github/workflows/release.yml 2>/dev/null || true)
  case "$todo_count" in ''|*[!0-9]*) todo_count=0 ;; esac
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
  state_phase=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' .claude/phase-state.json | grep -o '[0-9][0-9]*' || echo "")
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
# 5a. Process Enforcement State
# ================================================================
print_section "Process Enforcement State"

if [ -f ".claude/process-state.json" ]; then
  if command -v jq &>/dev/null && jq '.' .claude/process-state.json >/dev/null 2>&1; then
    print_ok "process-state.json (valid JSON)"
  elif command -v jq &>/dev/null; then
    fail "process-state.json exists but contains invalid JSON"
  else
    print_ok "process-state.json (exists — install jq for structural validation)"
  fi
else
  if [ $phase -ge 2 ]; then
    fail "process-state.json missing — process enforcement is inactive. Run: scripts/process-checklist.sh --verify-init"
  else
    print_info "No process-state.json (created at Phase 2 initialization)"
  fi
fi

if [ -f ".claude/build-progress.json" ]; then
  if command -v jq &>/dev/null && jq '.' .claude/build-progress.json >/dev/null 2>&1; then
    print_ok "build-progress.json (valid JSON)"
  elif command -v jq &>/dev/null; then
    warn "build-progress.json contains invalid JSON — test interval tracking degraded"
  else
    print_ok "build-progress.json (exists)"
  fi
else
  if [ $phase -ge 2 ]; then
    warn "build-progress.json missing — test interval tracking unavailable"
  fi
fi

if [ -f ".claude/tool-usage.json" ]; then
  if command -v jq &>/dev/null && jq '.' .claude/tool-usage.json >/dev/null 2>&1; then
    print_ok "tool-usage.json (valid JSON)"
  elif command -v jq &>/dev/null; then
    warn "tool-usage.json contains invalid JSON — tool usage tracking degraded"
  else
    print_ok "tool-usage.json (exists)"
  fi
else
  print_info "No tool-usage.json (created on first session start)"
fi

if [ -f ".claude/process-audit.log" ]; then
  reset_count=$(grep -c "\[RESET\]" .claude/process-audit.log 2>/dev/null || echo "0")
  case "$reset_count" in ''|*[!0-9]*) reset_count=0 ;; esac
  if [ "$reset_count" -gt 0 ]; then
    warn "process-audit.log contains $reset_count reset event(s) — review for compliance"
  else
    print_ok "process-audit.log (no resets recorded)"
  fi
fi

# ================================================================
# 6. Approval Log Completeness
# ================================================================
print_section "Approval Log"

# BL-059: `.claude/phase-state.json::gates.<gate>` is the live source of
# truth for gate-passage timestamps — the approval log is a
# human-readable mirror. Prior versions only greped APPROVAL_LOG.md,
# emitting a false-negative WARN when the JSON gate was populated but
# the log had not been mirrored. Fix: read JSON first, fall back to
# APPROVAL_LOG.md only if the JSON path is absent or malformed
# (back-compat), and only warn when NEITHER source has a valid date.
#
# get_gate_date_from_phase_state <gate_key>
# - Prints the YYYY-MM-DD gate date from phase-state.json::gates.<key>.
# - Prints "" if phase-state.json is missing, the key is absent, the
#   value is null, or the value is not a valid YYYY-MM-DD date.
# - Uses the same grep+sed extraction shape as check-phase-gate.sh so
#   the two validators agree on what counts as a recorded gate.
get_gate_date_from_phase_state() {
  local gate_key="$1"
  local state_file=".claude/phase-state.json"
  [ -f "$state_file" ] || { echo ""; return; }
  local value
  value=$(grep -o "\"$gate_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$state_file" 2>/dev/null \
            | sed 's/.*: *"//' | sed 's/"//' || echo "")
  if [ -n "$value" ] && ! echo "$value" | grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; then
    echo ""
    return
  fi
  echo "$value"
}

# check_gate <phase-min> <json-key> <approval-log-header> <label>
# Precedence: phase-state.json::gates.<json-key> WINS. Falls back to
# APPROVAL_LOG.md scan for back-compat with older projects that
# predated the JSON gates block. Warns iff neither source has a valid
# date AND the project is at or past <phase-min>.
check_gate() {
  local phase_min="$1"
  local json_key="$2"
  local header="$3"
  local label="$4"

  [ "$phase" -ge "$phase_min" ] || return 0

  local json_date
  json_date=$(get_gate_date_from_phase_state "$json_key")
  if [ -n "$json_date" ]; then
    print_ok "$label gate: dated entry found ($json_date from phase-state.json)"
    return 0
  fi

  if [ -f "APPROVAL_LOG.md" ] && grep -q "$header" APPROVAL_LOG.md; then
    local log_date
    log_date=$(grep -A 10 "$header" APPROVAL_LOG.md | grep -i "date" | head -1 || true)
    if echo "$log_date" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
      print_ok "$label gate: dated entry found (APPROVAL_LOG.md)"
      return 0
    fi
  fi

  warn "$label gate: no date recorded — project appears to be past Phase $((phase_min - 1))"
}

if [ -f "APPROVAL_LOG.md" ]; then
  check_gate 1 "phase_0_to_1" "Phase 0 → Phase 1" "Phase 0→1"
  check_gate 2 "phase_1_to_2" "Phase 1 → Phase 2" "Phase 1→2"
  # code-test-gate-track-resume-validate-1: the Approval Log section had
  # Phase 0→1, 1→2, and 3→4 gate checks but was silently missing the
  # symmetric 2→3 check. A project past Phase 3 without a dated
  # `Phase 2 → Phase 3` entry slipped past validation. Mirrors the 1→2
  # block structure for consistency.
  check_gate 3 "phase_2_to_3" "Phase 2 → Phase 3" "Phase 2→3"
  check_gate 4 "phase_3_to_4" "Phase 3 → Phase 4" "Phase 3→4"
else
  fail "APPROVAL_LOG.md missing"
fi

# ================================================================
# 7. CLAUDE.md Currency
# ================================================================
print_section "CLAUDE.md Currency"

if [ -f "CLAUDE.md" ]; then
  # Check if key sections have been updated from template defaults
  if grep -qE "Features built:.*none yet|Features remaining:.*see MVP Cutline" CLAUDE.md; then
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
    if grep -qE "Architecture Constraints|## Stack|## Architecture" CLAUDE.md; then
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
  case "$blank_cells" in ''|*[!0-9]*) blank_cells=0 ;; esac
  # Count N/A entries (explicitly marked as not applicable — this is fine)
  na_cells=$(grep -ciE '\| *N/?A' PROJECT_INTAKE.md 2>/dev/null || true)
  case "$na_cells" in ''|*[!0-9]*) na_cells=0 ;; esac

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
  swift)
    command -v swift &>/dev/null && print_ok "Swift $(swift --version 2>/dev/null | head -1)" || fail "Swift not found (requires Xcode on macOS)" ;;
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
    has_no=$(grep -i "| *No *|" PROJECT_INTAKE.md | grep -ciE "Security|Accessibility|Performance|Database" || true)
    case "$has_no" in ''|*[!0-9]*) has_no=0 ;; esac
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

#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Process Checklist State Machine
# Mechanical enforcement for sequential process compliance.
# Prevents agents from skipping steps in the build/test/release flow.
#
# Usage:
#   scripts/process-checklist.sh --start-feature "name"
#   scripts/process-checklist.sh --complete-step PROCESS:STEP_ID
#   scripts/process-checklist.sh --start-uat N
#   scripts/process-checklist.sh --start-phase3
#   scripts/process-checklist.sh --start-phase4
#   scripts/process-checklist.sh --verify-init
#   scripts/process-checklist.sh --status
#   scripts/process-checklist.sh --check-commit-ready
#   scripts/process-checklist.sh --reset PROCESS
#   scripts/process-checklist.sh --reset-all
#   scripts/process-checklist.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

PROCESS_STATE=".claude/process-state.json"
PHASE_STATE=".claude/phase-state.json"

# --- Step sequences ---
PHASE1_STEPS=(architecture_selected threat_model_complete data_model_defined ui_scaffolding_done bible_synthesized)
BUILD_LOOP_STEPS=(tests_written tests_verified_failing implemented security_audit documentation_updated feature_recorded)
UAT_STEPS=(agents_dispatched template_generated orchestrator_notified results_received completeness_verified bugs_consolidated triage_complete remediation_complete gate_passed)
PHASE3_STEPS=(integration_testing security_hardening chaos_testing accessibility_audit performance_audit contract_testing results_archived pre_launch_preparation legal_review)
PHASE4_STEPS=(production_build rollback_tested go_live_verified monitoring_configured handoff_written handoff_tested)
PHASE2_INIT_STEPS=(remote_repo_created branch_protection_configured project_scaffolded data_model_applied pre_commit_hooks_installed ci_pipeline_configured initialization_verified)

# --- Argument parsing ---
ACTION=""
ARG_VALUE=""
COMMIT_MSG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --start-feature)    ACTION="start-feature";    ARG_VALUE="$2"; shift 2 ;;
    --complete-step)    ACTION="complete-step";     ARG_VALUE="$2"; shift 2 ;;
    --start-uat)        ACTION="start-uat";         ARG_VALUE="$2"; shift 2 ;;
    --start-phase1)     ACTION="start-phase1";      shift ;;
    --start-phase3)     ACTION="start-phase3";      shift ;;
    --start-phase4)     ACTION="start-phase4";      shift ;;
    --verify-init)      ACTION="verify-init";       shift ;;
    --status)           ACTION="status";            shift ;;
    --check-commit-ready) ACTION="check-commit-ready"; shift ;;
    --check-commit-message) ACTION="check-commit-message"; COMMIT_MSG="$2"; shift 2 ;;
    --reset)            ACTION="reset";             ARG_VALUE="$2"; shift 2 ;;
    --reset-all)        ACTION="reset-all";         shift ;;
    --help|-h)
      echo "Usage: scripts/process-checklist.sh [COMMAND]"
      echo ""
      echo "Commands:"
      echo "  --start-feature NAME        Start a new build loop for the named feature"
      echo "  --complete-step PROC:STEP   Complete a step in a process (sequential enforcement)"
      echo "  --start-uat N               Start UAT session N"
      echo "  --start-phase3              Start Phase 3 validation"
      echo "  --start-phase4              Start Phase 4 release"
      echo "  --verify-init               Auto-verify Phase 2 initialization steps"
      echo "  --status                    Print human-readable status of all processes"
      echo "  --check-commit-ready        Check if commit is allowed (used by PreToolUse hook)"
      echo "  --check-commit-message MSG  Check commit-message prefix (feat:) against Build Loop state (BL-006)"
      echo "  --reset PROCESS             Reset a single process to initial state"
      echo "  --reset-all                 Reset all processes to initial state"
      echo "  --help                      Show this help"
      echo ""
      echo "Processes: build_loop, uat_session, phase3_validation, phase4_release, phase2_init"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Run: scripts/process-checklist.sh --help" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ACTION" ]; then
  echo "No action specified. Use --help for usage." >&2
  exit 1
fi

# --- Ensure process-state.json exists ---
ensure_state_file() {
  if [ ! -f "$PROCESS_STATE" ]; then
    mkdir -p .claude
    cat > "$PROCESS_STATE" << 'EOF'
{
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"session_id": null, "step": 0, "steps_completed": [], "started_at": null},
  "phase3_validation": {"steps_completed": [], "started_at": null},
  "phase4_release": {"steps_completed": [], "started_at": null},
  "phase2_init": {"steps_completed": [], "verified": false}
}
EOF
  fi
}

# --- Helper: get step array for a process name ---
get_steps_for_process() {
  local process="$1"
  case "$process" in
    phase1_architecture) echo "${PHASE1_STEPS[@]}" ;;
    build_loop)         echo "${BUILD_LOOP_STEPS[@]}" ;;
    uat_session)        echo "${UAT_STEPS[@]}" ;;
    phase3_validation)  echo "${PHASE3_STEPS[@]}" ;;
    phase4_release)     echo "${PHASE4_STEPS[@]}" ;;
    phase2_init)        echo "${PHASE2_INIT_STEPS[@]}" ;;
    *)
      print_fail "Unknown process: $process"
      echo "Valid processes: build_loop, uat_session, phase3_validation, phase4_release, phase2_init" >&2
      exit 1
      ;;
  esac
}

# --- Helper: check if a step is in steps_completed ---
step_is_completed() {
  local process="$1"
  local step="$2"
  jq -e --arg step "$step" ".${process}.steps_completed | index(\$step) != null" "$PROCESS_STATE" >/dev/null 2>&1
}

# --- Helper: require Build Loop state sufficient for a commit ---
# Used by both the file-heuristic path (--check-commit-ready) and the
# commit-message-triggered path (--check-commit-message). Prints the spec's
# Case A / Case B remediation to stderr on failure. Returns 0 if state OK,
# 1 otherwise. Reads $PROCESS_STATE and the BUILD_LOOP_STEPS array.
require_build_loop_state_for_commit() {
  local feature
  feature=$(jq -r '.build_loop.feature // "null"' "$PROCESS_STATE")
  if [ "$feature" = "null" ]; then
    print_fail "pre-commit gate: 'feat(...)' commit blocked — no Build Loop active."
    echo "MVP Cutline work and all features require a Build Loop per" >&2
    echo "docs/builders-guide.md \"MVP Cutline Work Requires the Build Loop\"." >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  1. scripts/process-checklist.sh --start-feature \"NAME\"" >&2
    echo "  2. Write failing tests, implement, verify, update docs" >&2
    echo "  3. Complete each step: scripts/process-checklist.sh --complete-step build_loop:STEP" >&2
    echo "  4. Re-run your commit" >&2
    echo "" >&2
    echo "If this commit is NOT a feature (tooling, CI, scaffolding, docs)," >&2
    echo "change the conventional-commit type: feat: -> chore:/build:/ci:/docs:." >&2
    return 1
  fi

  # Check first 5 build_loop steps: tests_written, tests_verified_failing,
  # implemented, security_audit, documentation_updated (feature_recorded is
  # step 6 and not required at commit time).
  local required_build_steps=("${BUILD_LOOP_STEPS[@]:0:5}")
  for step in "${required_build_steps[@]}"; do
    if ! step_is_completed "build_loop" "$step"; then
      print_fail "pre-commit gate: 'feat($feature)' commit blocked — Build Loop incomplete."
      echo "Missing step: $step" >&2
      echo "" >&2
      echo "Run: scripts/process-checklist.sh --complete-step build_loop:$step" >&2
      echo "Then: scripts/process-checklist.sh --status  (to verify)" >&2
      echo "Then re-run your commit." >&2
      return 1
    fi
  done

  return 0
}

# --- Actions ---

start_phase1() {
  ensure_state_file
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Add phase1_architecture to process state if not present
  if ! jq -e '.phase1_architecture' "$PROCESS_STATE" >/dev/null 2>&1; then
    jq --arg now "$now" '.phase1_architecture = {"steps_completed": [], "started_at": $now}' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
  else
    jq --arg now "$now" '.phase1_architecture.steps_completed = [] | .phase1_architecture.started_at = $now' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
  fi

  print_ok "Phase 1 architecture planning started"
  print_info "Next step: scripts/process-checklist.sh --complete-step phase1_architecture:architecture_selected"
}

start_feature() {
  ensure_state_file
  local name="$1"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Check Context Health Check counter (P2-018: elevate to Tier 2)
  local progress_file=".claude/build-progress.json"
  if [ -f "$progress_file" ] && command -v jq &>/dev/null; then
    local health_count
    health_count=$(jq '.features_since_last_health_check // 0' "$progress_file" 2>/dev/null || echo "0")
    if [ "$health_count" -ge 4 ] 2>/dev/null; then
      print_fail "Context Health Check overdue — $health_count features since last check."
      echo "  Before starting a new feature, verify PROJECT_BIBLE.md still reflects the codebase." >&2
      echo "  After checking: scripts/test-gate.sh --reset-health-check" >&2
      echo "  Then re-run: scripts/process-checklist.sh --start-feature \"$name\"" >&2
      exit 1
    elif [ "$health_count" -ge 3 ] 2>/dev/null; then
      print_warn "Context Health Check recommended — $health_count features since last check."
      echo "  Consider verifying PROJECT_BIBLE.md accuracy before starting the next feature."
    fi
  fi

  # Check if previous feature's feature_recorded step was completed (P2-007)
  local prev_feature
  prev_feature=$(jq -r '.build_loop.feature // empty' "$PROCESS_STATE" 2>/dev/null)
  if [ -n "$prev_feature" ]; then
    if ! step_is_completed "build_loop" "feature_recorded"; then
      print_warn "Previous feature '$prev_feature' was not recorded with test-gate.sh --record-feature."
      echo "  Run: scripts/test-gate.sh --record-feature \"$prev_feature\""
      echo "  Then: scripts/process-checklist.sh --complete-step build_loop:feature_recorded"
    fi
  fi

  jq --arg name "$name" --arg now "$now" '
    .build_loop = {
      "feature": $name,
      "step": 0,
      "steps_completed": [],
      "started_at": $now
    }
  ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"

  print_ok "Build loop started for feature: $name"
  print_info "Next step: scripts/process-checklist.sh --complete-step build_loop:tests_written"
}

complete_step() {
  ensure_state_file
  local input="$1"

  # Parse PROCESS:STEP_ID
  local process step_id
  process="${input%%:*}"
  step_id="${input#*:}"

  if [ "$process" = "$step_id" ] || [ -z "$process" ] || [ -z "$step_id" ]; then
    print_fail "Invalid format. Use: PROCESS:STEP_ID (e.g., build_loop:tests_written)"
    exit 1
  fi

  # Get step array for this process
  local steps_str
  steps_str=$(get_steps_for_process "$process")
  local steps=()
  read -ra steps <<< "$steps_str"

  # Find step_id's index
  local target_index=-1
  for i in "${!steps[@]}"; do
    if [ "${steps[$i]}" = "$step_id" ]; then
      target_index=$i
      break
    fi
  done

  if [ "$target_index" -eq -1 ]; then
    print_fail "Unknown step '$step_id' for process '$process'"
    echo "Valid steps: ${steps[*]}" >&2
    exit 1
  fi

  # Check if already completed
  if step_is_completed "$process" "$step_id"; then
    print_warn "Step '$step_id' already completed for $process"
    exit 0
  fi

  # Check all prior steps are completed
  for ((i = 0; i < target_index; i++)); do
    local prior_step="${steps[$i]}"
    if ! step_is_completed "$process" "$prior_step"; then
      print_fail "Cannot complete '$step_id' — '$prior_step' not yet completed."
      echo "Run: scripts/process-checklist.sh --complete-step ${process}:${prior_step}" >&2
      exit 1
    fi
  done

  # --- Artifact existence checks for high-value steps (P2-006, P3-008, P4-015) ---
  # These prevent marking a step complete without producing the expected output.
  # Use --force flag to bypass (logged to audit trail).
  local artifact_check_failed=false

  case "${process}:${step_id}" in
    build_loop:security_audit)
      # P2-006: Security audit must produce a feature-specific findings artifact
      local feature_name
      feature_name=$(jq -r '.build_loop.feature // "unknown"' "$PROCESS_STATE" 2>/dev/null)
      local feature_slug
      feature_slug=$(echo "$feature_name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
      if [ -d "docs/security-audits" ] && ls docs/security-audits/*"${feature_slug}"* 2>/dev/null | head -1 >/dev/null 2>&1; then
        : # Feature-specific audit file found
      elif [ -d "docs/security-audits" ] && ls docs/security-audits/*"${feature_name}"* 2>/dev/null | head -1 >/dev/null 2>&1; then
        : # Feature-specific audit file found (original name)
      else
        print_warn "No security audit findings for feature '$feature_name' in docs/security-audits/."
        echo "  Create a findings file using templates/generated/security-audit-findings.tmpl" >&2
        echo "  Save as: docs/security-audits/${feature_slug}-security-audit.md" >&2
        artifact_check_failed=true
      fi
      ;;
    phase3_validation:security_hardening)
      # P3-008: Security hardening must produce scan results
      if [ ! -d "docs/test-results" ] || ! { ls docs/test-results/*semgrep* 2>/dev/null || ls docs/test-results/*sast* 2>/dev/null; } | head -1 >/dev/null 2>&1; then
        print_warn "No SAST scan results found in docs/test-results/."
        echo "  Run Semgrep and save results: docs/test-results/YYYY-MM-DD_semgrep_pass.json" >&2
        artifact_check_failed=true
      fi
      ;;
    phase3_validation:results_archived)
      # P3-008: Results archive must be non-empty
      if [ ! -d "docs/test-results" ] || [ -z "$(ls docs/test-results/ 2>/dev/null)" ]; then
        print_warn "docs/test-results/ is empty — archive Phase 3 scan results first."
        artifact_check_failed=true
      fi
      ;;
    phase4_release:rollback_tested)
      # P4-001: Rollback test must produce evidence
      if ! ls docs/test-results/*rollback* 2>/dev/null | head -1 >/dev/null 2>&1; then
        print_warn "No rollback test results found in docs/test-results/."
        echo "  Record rollback test results: docs/test-results/YYYY-MM-DD_rollback-test.md" >&2
        artifact_check_failed=true
      fi
      ;;
    phase4_release:handoff_written)
      # P4-015: HANDOFF.md must exist
      if [ ! -f "HANDOFF.md" ]; then
        print_warn "HANDOFF.md not found — create it before marking this step complete."
        artifact_check_failed=true
      fi
      ;;
    phase4_release:go_live_verified)
      # P4-015: Go-live should be recorded
      if [ ! -f "RELEASE_NOTES.md" ]; then
        print_warn "RELEASE_NOTES.md not found — create release notes before marking go-live verified."
        artifact_check_failed=true
      fi
      ;;
    phase4_release:monitoring_configured)
      # P4-001: Monitoring must be verified (trigger test error)
      if [ -f "HANDOFF.md" ]; then
        if ! grep -qi "monitoring\|error tracking\|sentry\|crashlytics\|uptimerobot" HANDOFF.md 2>/dev/null; then
          print_warn "HANDOFF.md does not document monitoring configuration."
          echo "  Document monitoring tool, dashboard URL, and alert channel in HANDOFF.md Section 8." >&2
          artifact_check_failed=true
        fi
      else
        print_warn "HANDOFF.md not found — monitoring configuration should be documented there."
        artifact_check_failed=true
      fi
      ;;
    phase4_release:handoff_tested)
      # P4-002: Handoff test must produce results
      if ! ls docs/test-results/*handoff* 2>/dev/null | head -1 >/dev/null 2>&1; then
        print_warn "No handoff test results found in docs/test-results/."
        echo "  Have a backup maintainer test the handoff procedure." >&2
        echo "  Save results: docs/test-results/YYYY-MM-DD_handoff-test.md" >&2
        artifact_check_failed=true
      fi
      ;;
    phase3_validation:legal_review)
      # P3-002: Attorney review — if legal documents exist, attorney review is REQUIRED
      local has_legal_docs=false
      local has_attorney_entry=false
      # Check for legal documents that require attorney review
      if [ -f "PRIVACY_POLICY.md" ] || [ -f "TERMS_OF_SERVICE.md" ] || [ -f "privacy-policy.md" ] || [ -f "terms-of-service.md" ]; then
        has_legal_docs=true
      fi
      # Check for attorney review entry in APPROVAL_LOG.md
      if [ -f "APPROVAL_LOG.md" ] && grep -qi "attorney\|legal review" APPROVAL_LOG.md 2>/dev/null; then
        has_attorney_entry=true
      fi
      # Logic: if legal docs exist, attorney entry is required (AND, not OR)
      if [ "$has_legal_docs" = true ] && [ "$has_attorney_entry" = false ]; then
        print_warn "Legal documents found but no attorney review recorded in APPROVAL_LOG.md."
        echo "  Privacy Policy and/or Terms of Service MUST be reviewed by qualified legal counsel." >&2
        echo "  Record the review in APPROVAL_LOG.md (Attorney / Legal Review section)." >&2
        artifact_check_failed=true
      elif [ "$has_legal_docs" = false ] && [ "$has_attorney_entry" = false ]; then
        # No legal docs and no attorney entry — likely N/A (no data collection)
        print_info "No legal documents found — attorney review may not be required."
        echo "  If this project collects user data, create a Privacy Policy and get attorney review." >&2
        echo "  If not applicable: proceed (use SOIF_FORCE_STEP=true if this check blocks incorrectly)." >&2
      fi
      ;;
    phase3_validation:integration_testing)
      # P3-008: Integration test results should exist
      if ! { ls tests/ 2>/dev/null || ls docs/test-results/*integration* 2>/dev/null || ls docs/test-results/*e2e* 2>/dev/null; } | head -1 >/dev/null 2>&1; then
        print_warn "No integration/E2E test results found."
        artifact_check_failed=true
      fi
      ;;
    phase3_validation:accessibility_audit)
      # P3-008: Accessibility audit results should exist
      if ! { ls docs/test-results/*accessibility* 2>/dev/null || ls docs/test-results/*lighthouse* 2>/dev/null; } | head -1 >/dev/null 2>&1; then
        print_warn "No accessibility audit results found in docs/test-results/."
        artifact_check_failed=true
      fi
      ;;
    phase3_validation:performance_audit)
      # P3-008: Performance audit results should exist
      if ! { ls docs/test-results/*performance* 2>/dev/null || ls docs/test-results/*lighthouse* 2>/dev/null; } | head -1 >/dev/null 2>&1; then
        print_warn "No performance audit results found in docs/test-results/."
        artifact_check_failed=true
      fi
      ;;
  esac

  if [ "$artifact_check_failed" = true ]; then
    if [ "${SOIF_FORCE_STEP:-}" = "true" ]; then
      # Force override requires interactive terminal (blocks agent bypass)
      if [ ! -t 0 ]; then
        print_fail "SOIF_FORCE_STEP requires interactive terminal. The Orchestrator must run this directly."
        echo "  Run in your terminal: SOIF_FORCE_STEP=true scripts/process-checklist.sh --complete-step ${process}:${step_id}" >&2
        exit 1
      fi
      read -rp "Force-complete '${step_id}' without artifact? This is logged. [y/N]: " force_confirm
      if [[ ! "$force_confirm" =~ ^[Yy]$ ]]; then
        print_info "Force cancelled."
        exit 0
      fi
      local now_force
      now_force=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      mkdir -p .claude
      echo "[FORCE] Step ${process}:${step_id} completed without artifact at $now_force by $(whoami)" >> ".claude/process-audit.log"
      print_warn "Step forced without artifact — logged to .claude/process-audit.log"
    else
      print_fail "Artifact check failed. Produce the required artifact first."
      echo "  To force-override (Orchestrator only, logged):" >&2
      echo "  SOIF_FORCE_STEP=true scripts/process-checklist.sh --complete-step ${process}:${step_id}" >&2
      exit 1
    fi
  fi

  # All prior steps present + artifact checks passed — add step_id to steps_completed
  local new_step_num=$((target_index + 1))
  jq --arg step "$step_id" --argjson num "$new_step_num" "
    .${process}.steps_completed += [\$step] |
    .${process}.step = \$num
  " "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"

  print_ok "Step '$step_id' completed for $process ($new_step_num/${#steps[@]})"

  # Auto-set phase2_init.verified when all steps completed via --complete-step
  if [ "$process" = "phase2_init" ] && [ "$new_step_num" -eq "${#steps[@]}" ]; then
    jq '.phase2_init.verified = true' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
    print_ok "Phase 2 initialization auto-verified (all ${#steps[@]} steps complete)"
  fi

  # Auto-reset build_loop when feature_recorded lands — the previous feature's
  # loop is consumed. Without this, .build_loop.feature stays non-null and all
  # 5 prior steps stay marked complete, so the BL-006 commit-message gate
  # treats subsequent `feat(...)` commits as if a fresh loop is satisfied.
  # UAT 2026-04-25 bug C2 (agents 12, 43, 46): "between-features grace window."
  if [ "$process" = "build_loop" ] && [ "$step_id" = "feature_recorded" ]; then
    jq '.build_loop = {"feature": null, "step": 0, "steps_completed": [], "started_at": null}' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
    print_ok "Build loop reset — start the next feature with: scripts/process-checklist.sh --start-feature \"NAME\""
  fi

  # Show next step if any
  local next_index=$((target_index + 1))
  if [ "$next_index" -lt "${#steps[@]}" ]; then
    print_info "Next: scripts/process-checklist.sh --complete-step ${process}:${steps[$next_index]}"
  else
    print_ok "All steps complete for $process!"
  fi
}

start_uat() {
  ensure_state_file
  local session_id="$1"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg sid "$session_id" --arg now "$now" '
    .uat_session = {
      "session_id": ($sid | tonumber),
      "step": 0,
      "steps_completed": [],
      "started_at": $now
    }
  ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"

  print_ok "UAT session $session_id started"
  print_info "Next step: scripts/process-checklist.sh --complete-step uat_session:agents_dispatched"
}

start_phase3() {
  ensure_state_file
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # P3-012: Verify Phase 2 prerequisites before allowing Phase 3 entry
  local phase_state=".claude/phase-state.json"
  if [ -f "$phase_state" ]; then
    local current_phase
    current_phase=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9]*"*' "$phase_state" | grep -o '[0-9]*' || echo "0")
    if [ "$current_phase" -lt 3 ] 2>/dev/null; then
      print_warn "current_phase is $current_phase (expected >= 3). Update phase-state.json before starting Phase 3."
    fi
  fi

  # Check bug gate status
  local test_gate="$SCRIPT_DIR/test-gate.sh"
  if [ -x "$test_gate" ]; then
    local gate_result=0
    bash "$test_gate" --check-phase-gate || gate_result=$?
    if [ "$gate_result" -eq 1 ]; then
      print_fail "Phase 2→3 bug gate BLOCKED. Resolve issues before starting Phase 3."
      exit 1
    fi
  fi

  jq --arg now "$now" '
    .phase3_validation = {
      "steps_completed": [],
      "started_at": $now
    }
  ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"

  print_ok "Phase 3 validation started"
  print_info "Next step: scripts/process-checklist.sh --complete-step phase3_validation:integration_testing"
}

start_phase4() {
  ensure_state_file

  # Check POC mode — Phase 4 is blocked for POC projects
  if [ -f "$PHASE_STATE" ]; then
    local poc_mode
    poc_mode=$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "")
    if [ -n "$poc_mode" ] && [ "$poc_mode" != "null" ]; then
      print_fail "Phase 4 (production release) is blocked — project is in ${poc_mode//_/ } mode."
      echo "  POC projects complete at Phase 3. To unlock Phase 4:" >&2
      echo "  bash scripts/upgrade-project.sh --to-production" >&2
      exit 1
    fi
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg now "$now" '
    .phase4_release = {
      "steps_completed": [],
      "started_at": $now
    }
  ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"

  print_ok "Phase 4 release started"
  print_info "Next step: scripts/process-checklist.sh --complete-step phase4_release:production_build"
}

verify_init() {
  ensure_state_file
  local auto_marked=0

  print_info "Auto-verifying Phase 2 initialization..."
  echo ""

  # remote_repo_created: git remote get-url origin succeeds
  if git remote get-url origin >/dev/null 2>&1; then
    if ! step_is_completed "phase2_init" "remote_repo_created"; then
      jq '.phase2_init.steps_completed += ["remote_repo_created"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      auto_marked=$((auto_marked + 1))
    fi
    print_ok "remote_repo_created — git remote origin configured"
  else
    print_fail "remote_repo_created — no git remote origin found"
  fi

  # branch_protection_configured: REAL API verification via host dispatcher
  # (spec 2026-04-21 — replaces the previous "CI yaml exists" proxy check).
  local host_dispatcher="$SCRIPT_DIR/lib/host.sh"
  if [ -f "$host_dispatcher" ] && [ -f ".claude/manifest.json" ]; then
    # shellcheck disable=SC1090
    source "$host_dispatcher"
    local mode
    mode=$(jq -r '.mode // "personal"' .claude/manifest.json 2>/dev/null || echo "personal")
    if host_load_driver 2>/dev/null && host_verify_protection "main" "$mode" 2>/dev/null; then
      if ! step_is_completed "phase2_init" "branch_protection_configured"; then
        jq '.phase2_init.steps_completed += ["branch_protection_configured"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
        auto_marked=$((auto_marked + 1))
      fi
      print_ok "branch_protection_configured — host protection verified via API"
    else
      print_fail "branch_protection_configured — protection verification failed (run scripts/check-gate.sh --preflight)"
    fi
  else
    print_fail "branch_protection_configured — host dispatcher or manifest missing"
  fi

  # ci_pipeline_configured: host-aware CI file location
  local ci_file=""
  if [ -f ".github/workflows/ci.yml" ];      then ci_file=".github/workflows/ci.yml"
  elif [ -f ".gitlab-ci.yml" ];              then ci_file=".gitlab-ci.yml"
  elif [ -f "bitbucket-pipelines.yml" ];     then ci_file="bitbucket-pipelines.yml"
  fi
  if [ -n "$ci_file" ]; then
    if ! step_is_completed "phase2_init" "ci_pipeline_configured"; then
      jq '.phase2_init.steps_completed += ["ci_pipeline_configured"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      auto_marked=$((auto_marked + 1))
    fi
    print_ok "ci_pipeline_configured — CI config exists at $ci_file"
  else
    print_fail "ci_pipeline_configured — no CI config found (.github/workflows/ci.yml | .gitlab-ci.yml | bitbucket-pipelines.yml)"
  fi

  # project_scaffolded: any common lockfile exists
  local lockfiles=(package-lock.json yarn.lock pnpm-lock.yaml Pipfile.lock poetry.lock Cargo.lock go.sum pubspec.lock Package.resolved gradle.lockfile packages.lock.json)
  local found_lockfile=false
  for lf in "${lockfiles[@]}"; do
    if [ -f "$lf" ]; then
      found_lockfile=true
      if ! step_is_completed "phase2_init" "project_scaffolded"; then
        jq '.phase2_init.steps_completed += ["project_scaffolded"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
        auto_marked=$((auto_marked + 1))
      fi
      print_ok "project_scaffolded — lockfile found: $lf"
      break
    fi
  done
  if [ "$found_lockfile" = false ]; then
    print_fail "project_scaffolded — no lockfile found (${lockfiles[*]})"
  fi

  # pre_commit_hooks_installed: .git/hooks/pre-commit exists and executable
  if [ -x ".git/hooks/pre-commit" ]; then
    if ! step_is_completed "phase2_init" "pre_commit_hooks_installed"; then
      jq '.phase2_init.steps_completed += ["pre_commit_hooks_installed"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      auto_marked=$((auto_marked + 1))
    fi
    print_ok "pre_commit_hooks_installed — pre-commit hook found and executable"
  else
    print_fail "pre_commit_hooks_installed — .git/hooks/pre-commit not found or not executable"
  fi

  # data_model_applied: cannot auto-verify
  if ! step_is_completed "phase2_init" "data_model_applied"; then
    print_warn "Cannot auto-verify: data model applied and backup/restore tested."
    echo "  Mark manually: scripts/process-checklist.sh --complete-step phase2_init:data_model_applied"
  else
    print_ok "data_model_applied — previously marked complete"
  fi

  # initialization_verified: auto-complete when all 6 prior steps are done
  echo ""

  # Check if all prerequisite steps (1-6) are complete
  local completed_count
  completed_count=$(jq '.phase2_init.steps_completed | length' "$PROCESS_STATE")
  local total=${#PHASE2_INIT_STEPS[@]}
  local prereq_total=$((total - 1))  # Exclude initialization_verified itself

  # Count prerequisites (all steps except initialization_verified)
  local prereq_done=0
  for step in "${PHASE2_INIT_STEPS[@]}"; do
    if [ "$step" != "initialization_verified" ] && step_is_completed "phase2_init" "$step"; then
      prereq_done=$((prereq_done + 1))
    fi
  done

  if [ "$prereq_done" -ge "$prereq_total" ]; then
    # All prerequisites met — auto-complete initialization_verified
    if ! step_is_completed "phase2_init" "initialization_verified"; then
      jq '.phase2_init.steps_completed += ["initialization_verified"] | .phase2_init.step = 7' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      auto_marked=$((auto_marked + 1))
      print_ok "initialization_verified — all prerequisite steps passed"
    fi
    jq '.phase2_init.verified = true' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
    print_ok "Phase 2 initialization fully verified ($total/$total steps complete)"
  else
    print_warn "Phase 2 initialization incomplete ($prereq_done/$prereq_total prerequisite steps)"
    echo ""
    echo -e "${BOLD}Remaining steps:${NC}"
    for step in "${PHASE2_INIT_STEPS[@]}"; do
      if [ "$step" != "initialization_verified" ] && ! step_is_completed "phase2_init" "$step"; then
        echo "  - $step"
      fi
    done
  fi

  if [ "$auto_marked" -gt 0 ]; then
    print_info "Auto-marked $auto_marked step(s)"
  fi
}

show_status() {
  ensure_state_file

  echo ""
  echo -e "${BOLD}Process Checklist Status${NC}"
  echo -e "${BOLD}========================${NC}"

  # Build Loop
  echo ""
  echo -e "${BOLD}Build Loop${NC}"
  local feature
  feature=$(jq -r '.build_loop.feature // "none"' "$PROCESS_STATE")
  local bl_completed
  bl_completed=$(jq '.build_loop.steps_completed | length' "$PROCESS_STATE")
  local bl_total=${#BUILD_LOOP_STEPS[@]}
  echo "  Feature: $feature"
  echo "  Progress: $bl_completed/$bl_total steps"
  if [ "$bl_completed" -lt "$bl_total" ]; then
    echo "  Remaining:"
    for step in "${BUILD_LOOP_STEPS[@]}"; do
      if ! step_is_completed "build_loop" "$step"; then
        echo "    - $step"
      fi
    done
  fi

  # UAT Session
  echo ""
  echo -e "${BOLD}UAT Session${NC}"
  local session_id
  session_id=$(jq -r '.uat_session.session_id // "none"' "$PROCESS_STATE")
  local uat_completed
  uat_completed=$(jq '.uat_session.steps_completed | length' "$PROCESS_STATE")
  local uat_total=${#UAT_STEPS[@]}
  echo "  Session: $session_id"
  echo "  Progress: $uat_completed/$uat_total steps"
  if [ "$uat_completed" -lt "$uat_total" ]; then
    echo "  Remaining:"
    for step in "${UAT_STEPS[@]}"; do
      if ! step_is_completed "uat_session" "$step"; then
        echo "    - $step"
      fi
    done
  fi

  # Phase 3 Validation
  echo ""
  echo -e "${BOLD}Phase 3 Validation${NC}"
  local p3_completed
  p3_completed=$(jq '.phase3_validation.steps_completed | length' "$PROCESS_STATE")
  local p3_total=${#PHASE3_STEPS[@]}
  local p3_started
  p3_started=$(jq -r '.phase3_validation.started_at // "not started"' "$PROCESS_STATE")
  echo "  Started: $p3_started"
  echo "  Progress: $p3_completed/$p3_total steps"
  if [ "$p3_completed" -lt "$p3_total" ]; then
    echo "  Remaining:"
    for step in "${PHASE3_STEPS[@]}"; do
      if ! step_is_completed "phase3_validation" "$step"; then
        echo "    - $step"
      fi
    done
  fi

  # Phase 4 Release
  echo ""
  echo -e "${BOLD}Phase 4 Release${NC}"
  local p4_completed
  p4_completed=$(jq '.phase4_release.steps_completed | length' "$PROCESS_STATE")
  local p4_total=${#PHASE4_STEPS[@]}
  local p4_started
  p4_started=$(jq -r '.phase4_release.started_at // "not started"' "$PROCESS_STATE")
  echo "  Started: $p4_started"
  echo "  Progress: $p4_completed/$p4_total steps"
  if [ "$p4_completed" -lt "$p4_total" ]; then
    echo "  Remaining:"
    for step in "${PHASE4_STEPS[@]}"; do
      if ! step_is_completed "phase4_release" "$step"; then
        echo "    - $step"
      fi
    done
  fi

  # Phase 2 Init
  echo ""
  echo -e "${BOLD}Phase 2 Initialization${NC}"
  local p2_completed
  p2_completed=$(jq '.phase2_init.steps_completed | length' "$PROCESS_STATE")
  local p2_total=${#PHASE2_INIT_STEPS[@]}
  local p2_verified
  p2_verified=$(jq -r '.phase2_init.verified' "$PROCESS_STATE")
  echo "  Verified: $p2_verified"
  echo "  Progress: $p2_completed/$p2_total steps"
  if [ "$p2_completed" -lt "$p2_total" ]; then
    echo "  Remaining:"
    for step in "${PHASE2_INIT_STEPS[@]}"; do
      if ! step_is_completed "phase2_init" "$step"; then
        echo "    - $step"
      fi
    done
  fi
  echo ""
}

# Match common dependency-manifest files by basename (T2-A). These are
# package-manager artifacts; a pure dep-bump commit should not trigger the
# Build Loop gate. Match by basename rather than extension because most have
# no extension or use a non-source extension (.lock, .txt, .sum, .mod).
_is_dep_manifest() {
  local base
  base=$(basename "$1")
  case "$base" in
    Pipfile|Pipfile.lock|Gemfile|Gemfile.lock) return 0 ;;
    Cargo.lock|go.mod|go.sum) return 0 ;;
    poetry.lock|yarn.lock|pnpm-lock.yaml) return 0 ;;
    npm-shrinkwrap.json|package-lock.json|pubspec.lock) return 0 ;;
    Package.resolved|gradle.lockfile|packages.lock.json) return 0 ;;
    requirements.txt|requirements-*.txt|requirements_*.txt) return 0 ;;
    *) return 1 ;;
  esac
}

check_commit_ready() {
  ensure_state_file

  # Read current phase
  local current_phase=0
  if [ -f "$PHASE_STATE" ]; then
    current_phase=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null || echo "0")
  fi

  # If phase < 2, no enforcement
  if [ "$current_phase" -lt 2 ]; then
    exit 0
  fi

  # Phase 2: check init verification
  if [ "$current_phase" -eq 2 ]; then
    local init_verified
    init_verified=$(jq -r '.phase2_init.verified' "$PROCESS_STATE")
    if [ "$init_verified" != "true" ]; then
      print_fail "Phase 2 initialization not verified."
      echo "Run: scripts/process-checklist.sh --verify-init" >&2
      exit 1
    fi
  fi

  # Read staged files
  local staged_files
  staged_files=$(git diff --cached --name-only 2>/dev/null || true)

  # No staged files — nothing to enforce
  if [ -z "$staged_files" ]; then
    exit 0
  fi

  # Classify commit type: source vs docs
  local is_source=false
  local source_extensions='\.py$|\.ts$|\.tsx$|\.js$|\.jsx$|\.rs$|\.go$|\.cs$|\.kt$|\.java$|\.dart$|\.swift$|\.c$|\.cpp$|\.h$'
  local source_dirs='^src/|^lib/|^app/|^pkg/|^internal/|^cmd/'

  while IFS= read -r file; do
    if echo "$file" | grep -qE "$source_extensions"; then
      is_source=true
      break
    fi
    if echo "$file" | grep -qE "$source_dirs"; then
      is_source=true
      break
    fi
  done <<< "$staged_files"

  # If not a source commit, check if it's purely docs or dependency manifests.
  # Dep manifests (Pipfile.lock, Gemfile.lock, go.sum, etc.) are produced by
  # package managers; a single dep bump should not require a Build Loop entry
  # (T2-A, surfaced from lancache 2026-04-26).
  if [ "$is_source" = false ]; then
    local all_exempt=true
    while IFS= read -r file; do
      if echo "$file" | grep -qE '\.(md|json|yml|yaml|toml|tmpl)$'; then
        continue
      fi
      if _is_dep_manifest "$file"; then
        continue
      fi
      all_exempt=false
      break
    done <<< "$staged_files"
    if [ "$all_exempt" = true ]; then
      exit 0
    fi
  fi

  # Phase 2 source commit checks
  if [ "$current_phase" -eq 2 ]; then
    require_build_loop_state_for_commit || exit 1

    # If UAT session is in progress, all 9 steps must be complete
    local uat_started
    uat_started=$(jq -r '.uat_session.started_at // "null"' "$PROCESS_STATE")
    if [ "$uat_started" != "null" ]; then
      local uat_completed
      uat_completed=$(jq '.uat_session.steps_completed | length' "$PROCESS_STATE")
      local uat_total=${#UAT_STEPS[@]}
      if [ "$uat_completed" -lt "$uat_total" ]; then
        print_fail "UAT session in progress — complete all steps before committing."
        for step in "${UAT_STEPS[@]}"; do
          if ! step_is_completed "uat_session" "$step"; then
            echo "  Missing: $step" >&2
          fi
        done
        echo "Run: scripts/process-checklist.sh --status" >&2
        exit 1
      fi
    fi
  fi

  # Phase 3 source commit checks
  if [ "$current_phase" -eq 3 ]; then
    local p3_completed
    p3_completed=$(jq '.phase3_validation.steps_completed | length' "$PROCESS_STATE")
    local p3_total=${#PHASE3_STEPS[@]}
    if [ "$p3_completed" -lt "$p3_total" ]; then
      for step in "${PHASE3_STEPS[@]}"; do
        if ! step_is_completed "phase3_validation" "$step"; then
          print_fail "Phase 3 validation step '$step' not completed."
          echo "Run: scripts/process-checklist.sh --complete-step phase3_validation:$step" >&2
          exit 1
        fi
      done
    fi
  fi

  # Phase 4 source commit checks
  if [ "$current_phase" -eq 4 ]; then
    local p4_completed
    p4_completed=$(jq '.phase4_release.steps_completed | length' "$PROCESS_STATE")
    local p4_total=${#PHASE4_STEPS[@]}
    if [ "$p4_completed" -lt "$p4_total" ]; then
      for step in "${PHASE4_STEPS[@]}"; do
        if ! step_is_completed "phase4_release" "$step"; then
          print_fail "Phase 4 release step '$step' not completed."
          echo "Run: scripts/process-checklist.sh --complete-step phase4_release:$step" >&2
          exit 1
        fi
      done
    fi
  fi

  # All checks passed
  exit 0
}

reset_process() {
  ensure_state_file
  local process="$1"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Authorization: require interactive terminal (blocks agent calls)
  if [ ! -t 0 ]; then
    print_fail "Reset requires interactive authorization."
    echo "The Orchestrator must run this command directly in a terminal:" >&2
    echo "  scripts/process-checklist.sh --reset $process" >&2
    exit 1
  fi

  # Interactive confirmation
  read -rp "Reset process '$process'? This clears all progress. [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Reset cancelled."
    exit 0
  fi

  case "$process" in
    build_loop)
      jq '
        .build_loop = {"feature": null, "step": 0, "steps_completed": [], "started_at": null}
      ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      ;;
    uat_session)
      jq '
        .uat_session = {"session_id": null, "step": 0, "steps_completed": [], "started_at": null}
      ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      ;;
    phase3_validation)
      jq '
        .phase3_validation = {"steps_completed": [], "started_at": null}
      ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      ;;
    phase4_release)
      jq '
        .phase4_release = {"steps_completed": [], "started_at": null}
      ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      ;;
    phase2_init)
      jq '
        .phase2_init = {"steps_completed": [], "verified": false}
      ' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      ;;
    *)
      print_fail "Unknown process: $process"
      echo "Valid processes: build_loop, uat_session, phase3_validation, phase4_release, phase2_init" >&2
      exit 1
      ;;
  esac

  # Persistent audit trail
  local audit_entry="[RESET] Process $process reset at $now by $(whoami)"
  mkdir -p .claude
  echo "$audit_entry" >> ".claude/process-audit.log"
  echo "$audit_entry" >&2
  print_ok "Process '$process' reset to initial state"
}

reset_all() {
  ensure_state_file
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Authorization: require interactive terminal (blocks agent calls)
  if [ ! -t 0 ]; then
    print_fail "Reset requires interactive authorization."
    echo "The Orchestrator must run this command directly in a terminal:" >&2
    echo "  scripts/process-checklist.sh --reset-all" >&2
    exit 1
  fi

  # Interactive confirmation
  read -rp "Reset ALL processes? This clears all progress across all phases. [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Reset cancelled."
    exit 0
  fi

  cat > "$PROCESS_STATE" << 'EOF'
{
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"session_id": null, "step": 0, "steps_completed": [], "started_at": null},
  "phase3_validation": {"steps_completed": [], "started_at": null},
  "phase4_release": {"steps_completed": [], "started_at": null},
  "phase2_init": {"steps_completed": [], "verified": false}
}
EOF

  # Persistent audit trail
  local audit_entry="[RESET] All processes reset at $now by $(whoami)"
  mkdir -p .claude
  echo "$audit_entry" >> ".claude/process-audit.log"
  echo "$audit_entry" >&2
  print_ok "All processes reset to initial state"
}

# --- BL-006: commit-message-triggered Build Loop enforcement ---
# Inspects the subject line of a commit message. If it starts with a
# Conventional Commits feature prefix (feat, feat(x), feat!, feat(x)!),
# require the Build Loop state to be sufficient for a commit. Otherwise,
# exit 0 silently. Phase gate: Phase < 2 skips enforcement.
check_commit_message() {
  local msg="$1"

  ensure_state_file

  # Empty message: nothing to check.
  if [ -z "$msg" ]; then
    exit 0
  fi

  # Take only the first line (subject).
  local subject
  subject=$(printf '%s\n' "$msg" | head -n 1)

  # Read current phase.
  local current_phase=0
  if [ -f "$PHASE_STATE" ]; then
    current_phase=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null || echo "0")
  fi

  # Phase gate: enforcement starts at Phase 2.
  if [ "$current_phase" -lt 2 ]; then
    exit 0
  fi

  # Feat-prefix regex, anchored, case-sensitive per Conventional Commits.
  # Matches: feat:, feat(x):, feat!:, feat(x)!: — each followed by whitespace.
  if ! [[ "$subject" =~ ^feat(\([^\)]*\))?!?:[[:space:]] ]]; then
    exit 0
  fi

  # Feat-prefixed: require Build Loop state sufficient for a commit.
  require_build_loop_state_for_commit || exit 1

  exit 0
}

# --- Dispatch ---
case "$ACTION" in
  start-feature)      start_feature "$ARG_VALUE" ;;
  complete-step)      complete_step "$ARG_VALUE" ;;
  start-uat)          start_uat "$ARG_VALUE" ;;
  start-phase1)       start_phase1 ;;
  start-phase3)       start_phase3 ;;
  start-phase4)       start_phase4 ;;
  verify-init)        verify_init ;;
  status)             show_status ;;
  check-commit-ready) check_commit_ready ;;
  check-commit-message) check_commit_message "$COMMIT_MSG" ;;
  reset)              reset_process "$ARG_VALUE" ;;
  reset-all)          reset_all ;;
esac

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
BUILD_LOOP_STEPS=(tests_written tests_verified_failing implemented security_audit documentation_updated feature_recorded)
UAT_STEPS=(agents_dispatched template_generated orchestrator_notified results_received completeness_verified bugs_consolidated triage_complete remediation_complete gate_passed)
PHASE3_STEPS=(integration_testing security_hardening chaos_testing accessibility_audit performance_audit contract_testing results_archived)
PHASE4_STEPS=(production_build rollback_tested go_live_verified monitoring_configured handoff_written)
PHASE2_INIT_STEPS=(remote_repo_created branch_protection_configured project_scaffolded data_model_applied pre_commit_hooks_installed ci_pipeline_configured initialization_verified)

# --- Argument parsing ---
ACTION=""
ARG_VALUE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --start-feature)    ACTION="start-feature";    ARG_VALUE="$2"; shift 2 ;;
    --complete-step)    ACTION="complete-step";     ARG_VALUE="$2"; shift 2 ;;
    --start-uat)        ACTION="start-uat";         ARG_VALUE="$2"; shift 2 ;;
    --start-phase3)     ACTION="start-phase3";      shift ;;
    --start-phase4)     ACTION="start-phase4";      shift ;;
    --verify-init)      ACTION="verify-init";       shift ;;
    --status)           ACTION="status";            shift ;;
    --check-commit-ready) ACTION="check-commit-ready"; shift ;;
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

# --- Actions ---

start_feature() {
  ensure_state_file
  local name="$1"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

  # All prior steps present — add step_id to steps_completed
  local new_step_num=$((target_index + 1))
  jq --arg step "$step_id" --argjson num "$new_step_num" "
    .${process}.steps_completed += [\$step] |
    .${process}.step = \$num
  " "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"

  print_ok "Step '$step_id' completed for $process ($new_step_num/${#steps[@]})"

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

  # branch_protection_configured + ci_pipeline_configured: .github/workflows/ci.yml exists
  if [ -f ".github/workflows/ci.yml" ]; then
    if ! step_is_completed "phase2_init" "branch_protection_configured"; then
      jq '.phase2_init.steps_completed += ["branch_protection_configured"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      auto_marked=$((auto_marked + 1))
    fi
    print_ok "branch_protection_configured — CI workflow exists"

    if ! step_is_completed "phase2_init" "ci_pipeline_configured"; then
      jq '.phase2_init.steps_completed += ["ci_pipeline_configured"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
      auto_marked=$((auto_marked + 1))
    fi
    print_ok "ci_pipeline_configured — CI workflow exists"
  else
    print_fail "branch_protection_configured — .github/workflows/ci.yml not found"
    print_fail "ci_pipeline_configured — .github/workflows/ci.yml not found"
  fi

  # project_scaffolded: any common lockfile exists
  local lockfiles=(package-lock.json Pipfile.lock poetry.lock Cargo.lock go.sum pubspec.lock Package.resolved)
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

  # initialization_verified: cannot auto-verify independently (depends on all others)
  echo ""

  # Check if all 7 steps are now complete
  local completed_count
  completed_count=$(jq '.phase2_init.steps_completed | length' "$PROCESS_STATE")
  local total=${#PHASE2_INIT_STEPS[@]}

  if [ "$completed_count" -ge "$total" ]; then
    jq '.phase2_init.verified = true' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
    print_ok "Phase 2 initialization fully verified ($completed_count/$total steps complete)"
  else
    print_warn "Phase 2 initialization incomplete ($completed_count/$total steps)"
    echo ""
    echo -e "${BOLD}Remaining steps:${NC}"
    for step in "${PHASE2_INIT_STEPS[@]}"; do
      if ! step_is_completed "phase2_init" "$step"; then
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

  # If not a source commit, check if it's purely docs
  if [ "$is_source" = false ]; then
    local all_docs=true
    while IFS= read -r file; do
      if ! echo "$file" | grep -qE '\.(md|json|yml|yaml|toml|tmpl)$'; then
        all_docs=false
        break
      fi
    done <<< "$staged_files"
    if [ "$all_docs" = true ]; then
      exit 0
    fi
  fi

  # Phase 2 source commit checks
  if [ "$current_phase" -eq 2 ]; then
    # Must have a feature started
    local feature
    feature=$(jq -r '.build_loop.feature // "null"' "$PROCESS_STATE")
    if [ "$feature" = "null" ]; then
      print_fail "No feature started."
      echo "Run: scripts/process-checklist.sh --start-feature 'name'" >&2
      exit 1
    fi

    # Check build_loop steps through documentation_updated (first 5)
    local required_build_steps=("${BUILD_LOOP_STEPS[@]:0:5}")
    for step in "${required_build_steps[@]}"; do
      if ! step_is_completed "build_loop" "$step"; then
        print_fail "Build loop step '$step' not completed for feature '$feature'."
        echo "Run: scripts/process-checklist.sh --complete-step build_loop:$step" >&2
        exit 1
      fi
    done

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

# --- Dispatch ---
case "$ACTION" in
  start-feature)      start_feature "$ARG_VALUE" ;;
  complete-step)      complete_step "$ARG_VALUE" ;;
  start-uat)          start_uat "$ARG_VALUE" ;;
  start-phase3)       start_phase3 ;;
  start-phase4)       start_phase4 ;;
  verify-init)        verify_init ;;
  status)             show_status ;;
  check-commit-ready) check_commit_ready ;;
  reset)              reset_process "$ARG_VALUE" ;;
  reset-all)          reset_all ;;
esac

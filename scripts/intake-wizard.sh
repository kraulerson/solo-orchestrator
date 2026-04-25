#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Intake Wizard
# Guides users through filling out PROJECT_INTAKE.md interactively.
#
# Usage:
#   scripts/intake-wizard.sh                  # Start or choose mode
#   scripts/intake-wizard.sh --resume         # Resume from last save point
#   scripts/intake-wizard.sh --upgrade-to-production  # Upgrade POC to production

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

# UAT 2026-04-25 fix (U-N): refuse to operate inside the framework repo.
# (Note: U-G — PROJECT_ROOT being hardcoded to framework even when invoked
# from a project — is a separate bug deferred to Batch 3.)
guard_not_in_framework || exit 1

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROGRESS_FILE="$PROJECT_ROOT/.claude/intake-progress.json"
INTAKE_FILE="$PROJECT_ROOT/PROJECT_INTAKE.md"
SUGGESTIONS_DIR="$PROJECT_ROOT/templates/intake-suggestions"

# Project context (loaded from progress file or phase-state.json)
PROJECT_NAME="${PROJECT_NAME:-}"
PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-}"
PLATFORM="${PLATFORM:-}"
TRACK="${TRACK:-}"
DEPLOYMENT="${DEPLOYMENT:-}"
LANGUAGE="${LANGUAGE:-}"
POC_MODE="${POC_MODE:-}"
LAST_SECTION=0
COMPLETED_SECTIONS=""

# ================================================================
# UTILITY: Prompt for text input with optional default
# ================================================================
prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local result
  if [ -n "$default" ]; then
    read -rp "$(echo -e "  ${BOLD}$prompt${NC} [$default]: ")" result
    result="${result:-$default}"
  else
    read -rp "$(echo -e "  ${BOLD}$prompt${NC}: ")" result
  fi
  if [ "$result" = "pause" ] || [ "$result" = "PAUSE" ] || [ "$result" = "Pause" ]; then
    _request_pause
    echo ""
    return
  fi
  echo "$result"
}

# ================================================================
# UTILITY: Prompt for numbered choice
# ================================================================
prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  echo -e "  ${BOLD}$prompt${NC}" >&2
  for i in "${!options[@]}"; do
    echo "    $((i+1)). ${options[$i]}" >&2
  done
  local choice
  while true; do
    read -rp "$(echo -e "  ${BOLD}Select [1-${#options[@]}]${NC}: ")" choice
    if [ "$choice" = "pause" ] || [ "$choice" = "PAUSE" ] || [ "$choice" = "Pause" ]; then
      _request_pause
      echo ""
      return
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
      echo "${options[$((choice-1))]}"
      return
    fi
    echo "  Invalid choice. Enter a number between 1 and ${#options[@]}." >&2
  done
}

# ================================================================
# UTILITY: Prompt with ? for suggestions
# ================================================================
prompt_with_suggestions() {
  local prompt="$1"
  local suggestion_key="$2"
  local default="${3:-}"
  local result

  while true; do
    if [ -n "$default" ]; then
      read -rp "$(echo -e "  ${BOLD}$prompt${NC} [? for suggestions, default: $default]: ")" result
    else
      read -rp "$(echo -e "  ${BOLD}$prompt${NC} [? for suggestions]: ")" result
    fi

    if [ "$result" = "pause" ] || [ "$result" = "PAUSE" ] || [ "$result" = "Pause" ]; then
      _request_pause
      echo ""
      return
    fi

    if [ "$result" = "?" ]; then
      show_suggestions "$suggestion_key"
      continue
    fi

    if [ -z "$result" ] && [ -n "$default" ]; then
      echo "$default"
      return
    fi

    if [ -n "$result" ]; then
      echo "$result"
      return
    fi

    echo "  Please enter a value or type ? for suggestions." >&2
  done
}

# ================================================================
# UTILITY: Show suggestions from JSON files
# ================================================================
show_suggestions() {
  local key="$1"
  local found=false

  # Try platform-specific suggestions first
  local platform_file="$SUGGESTIONS_DIR/${PLATFORM}.json"
  if [ -f "$platform_file" ]; then
    local suggestions
    suggestions=$(parse_suggestions "$platform_file" "$key" "$LANGUAGE" 2>/dev/null || true)
    if [ -n "$suggestions" ]; then
      echo "" >&2
      echo -e "  ${CYAN}Based on your project ($PLATFORM, $LANGUAGE):${NC}" >&2
      echo "$suggestions" >&2
      echo "" >&2
      found=true
    fi
  fi

  # Fall back to common suggestions
  local common_file="$SUGGESTIONS_DIR/common.json"
  if [ "$found" = false ] && [ -f "$common_file" ]; then
    local suggestions
    suggestions=$(parse_suggestions "$common_file" "$key" "" 2>/dev/null || true)
    if [ -n "$suggestions" ]; then
      echo "" >&2
      echo -e "  ${CYAN}Suggestions:${NC}" >&2
      echo "$suggestions" >&2
      echo "" >&2
      found=true
    fi
  fi

  if [ "$found" = false ]; then
    echo "  No suggestions available for this field." >&2
  fi
}

# ================================================================
# UTILITY: Parse suggestions from a JSON file using python3
# ================================================================
parse_suggestions() {
  local file="$1"
  local key="$2"
  local language="$3"

  if command -v python3 &>/dev/null; then
    python3 << PYEOF
import json, sys
try:
    with open('$file') as f:
        data = json.load(f)
    suggestions = data.get('suggestions', {}).get('$key', {})
    items = suggestions.get('$language', suggestions.get('default', []))
    if not items:
        sys.exit(0)
    for i, item in enumerate(items, 1):
        rank_label = ' (recommended)' if item.get('rank') == 1 else ''
        print(f"    {i}. {item['name']}{rank_label}")
        print(f"       {item['context']}")
except Exception:
    sys.exit(0)
PYEOF
  fi
}

# Pause detection: prompt functions write a sentinel file when the user
# types "pause". The section runner checks for this file after each prompt.
_PAUSE_FILE="/tmp/.solo-intake-pause-$$"

_request_pause() {
  touch "$_PAUSE_FILE"
}

# Check if pause was requested. Call this in the main loop, not in subshells.
check_pause_requested() {
  if [ -f "$_PAUSE_FILE" ]; then
    rm -f "$_PAUSE_FILE"
    echo ""
    print_info "Pausing intake wizard. Progress saved."
    print_info "Resume with: scripts/intake-wizard.sh --resume"
    exit 0
  fi
}

# Clean up pause file on exit
trap 'rm -f "$_PAUSE_FILE"' EXIT

# ================================================================
# PROGRESS: Initialize progress file
# ================================================================
init_progress() {
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
data = {
    'version': 1,
    'started_at': sys.argv[1],
    'last_section': 0,
    'completed_sections': [],
    'project_name': sys.argv[2],
    'platform': sys.argv[3],
    'track': sys.argv[4],
    'deployment': sys.argv[5],
    'language': sys.argv[6],
    'description': sys.argv[7],
    'poc_mode': None,
    'answers': {}
}
with open(sys.argv[8], 'w') as f:
    json.dump(data, f, indent=2)
" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_NAME" "$PLATFORM" "$TRACK" "$DEPLOYMENT" "$LANGUAGE" "$PROJECT_DESCRIPTION" "$PROGRESS_FILE"
  fi
}

# ================================================================
# PROGRESS: Save a completed section
# ================================================================
save_section() {
  local section_num="$1"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
section, path = int(sys.argv[1]), sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['last_section'] = section
if section not in data['completed_sections']:
    data['completed_sections'].append(section)
    data['completed_sections'].sort()
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" "$section_num" "$PROGRESS_FILE"
  fi
  print_ok "Section $section_num saved."
}

# ================================================================
# PROGRESS: Save an answer to the progress file
# ================================================================
save_answer() {
  local key="$1"
  local value="$2"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
key, value, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data['answers'][key] = value
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" "$key" "$value" "$PROGRESS_FILE"
  fi
}

# ================================================================
# PROGRESS: Load progress and project context
# ================================================================
load_progress() {
  if [ ! -f "$PROGRESS_FILE" ]; then
    print_warn "No progress file found."
    return 1
  fi

  if command -v python3 &>/dev/null; then
    # Write to a temp file to avoid eval injection from user-provided values
    local tmpfile
    tmpfile=$(mktemp)
    python3 -c "
import json, sys, shlex
with open(sys.argv[1]) as f:
    data = json.load(f)
# Use shlex.quote to safely escape all values for shell assignment
print(f\"LAST_SECTION={data['last_section']}\")
print(f\"PROJECT_NAME={shlex.quote(data['project_name'])}\")
print(f\"PLATFORM={shlex.quote(data['platform'])}\")
print(f\"TRACK={shlex.quote(data['track'])}\")
print(f\"DEPLOYMENT={shlex.quote(data['deployment'])}\")
print(f\"LANGUAGE={shlex.quote(data['language'])}\")
print(f\"PROJECT_DESCRIPTION={shlex.quote(data['description'])}\")
poc = data.get('poc_mode') or ''
print(f\"POC_MODE={shlex.quote(poc)}\")
completed = ' '.join(str(s) for s in data.get('completed_sections', []))
print(f\"COMPLETED_SECTIONS={shlex.quote(completed)}\")
" "$PROGRESS_FILE" > "$tmpfile"
    # shellcheck disable=SC1090
    source "$tmpfile"
    rm -f "$tmpfile"
  fi
}

# ================================================================
# PROGRESS: Load project context from phase-state.json
# ================================================================
load_project_context() {
  local phase_file="$PROJECT_ROOT/.claude/phase-state.json"
  local prefs_file="$PROJECT_ROOT/.claude/tool-preferences.json"

  # Load from phase-state.json
  if [ -f "$phase_file" ] && command -v jq &>/dev/null; then
    PROJECT_NAME=$(jq -r '.project // empty' "$phase_file" 2>/dev/null)
    TRACK=$(jq -r '.track // empty' "$phase_file" 2>/dev/null)
    DEPLOYMENT=$(jq -r '.deployment // empty' "$phase_file" 2>/dev/null)
    POC_MODE=$(jq -r '.poc_mode // empty' "$phase_file" 2>/dev/null)
    [ "$POC_MODE" = "null" ] && POC_MODE=""
  fi

  # Load from tool-preferences.json
  if [ -f "$prefs_file" ] && command -v jq &>/dev/null; then
    PLATFORM=$(jq -r '.context.platform // empty' "$prefs_file" 2>/dev/null)
    LANGUAGE=$(jq -r '.context.language // empty' "$prefs_file" 2>/dev/null)
  fi

  # Load description from CLAUDE.md if available (it's embedded there by init)
  if [ -f "$PROJECT_ROOT/CLAUDE.md" ] && [ -z "$PROJECT_DESCRIPTION" ]; then
    PROJECT_DESCRIPTION=$(grep -A1 "## Project" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || echo "")
  fi
}

# ================================================================
# PROGRESS: Check if a section is completed
# ================================================================
is_section_complete() {
  local section_num="$1"
  [[ " $COMPLETED_SECTIONS " == *" $section_num "* ]]
}

# ================================================================
# SECTION 1: Project Identity
# ================================================================
run_section_1() {
  print_step "Section 1: Project Identity"
  echo ""
  print_info "Most fields are pre-filled from your init.sh answers."
  echo ""

  local codename
  codename=$(prompt_input "Project codename (if different from '$PROJECT_NAME', or Enter to skip)" "")
  save_answer "codename" "${codename:-N/A}"

  local target_platforms
  target_platforms=$(prompt_input "Target platforms (e.g., 'all modern browsers', 'Windows 10+, macOS 12+')" "")
  save_answer "target_platforms" "$target_platforms"

  local repo_url
  repo_url=$(prompt_input "Repository URL (if already created, or Enter to skip)" "")
  save_answer "repo_url" "${repo_url:-TBD}"

  # --- Git host selection (spec 2026-04-21 host-aware repo gate) ---
  local git_host
  git_host=$(prompt_choice "Git host for this project:" \
    "github" \
    "gitlab" \
    "bitbucket" \
    "other")
  save_answer "git_host" "$git_host"

  # Probe CLI availability for first-class hosts (github/gitlab/bitbucket)
  if [ "$git_host" != "other" ]; then
    local dispatcher="$SCRIPT_DIR/lib/host.sh"
    local driver="$SCRIPT_DIR/host-drivers/$git_host.sh"
    if [ -f "$dispatcher" ] && [ -f "$driver" ]; then
      # shellcheck disable=SC1090
      source "$dispatcher"
      source "$driver"
      if ! host_require_cli 2>/tmp/host-cli-probe.$$; then
        cat /tmp/host-cli-probe.$$ >&2
        rm -f /tmp/host-cli-probe.$$
        local action
        action=$(prompt_choice "Host CLI unavailable — what now?" \
          "retry" \
          "switch" \
          "continue")
        case "$action" in
          retry)
            if ! host_require_cli; then
              echo "Still unavailable. Install the CLI and rerun the wizard." >&2
              exit 1
            fi
            ;;
          switch)
            git_host=$(prompt_choice "Choose a different host:" "github" "gitlab" "bitbucket" "other")
            save_answer "git_host" "$git_host"
            ;;
          continue)
            echo "Continuing intake — CLI will be verified again at init.sh." >&2
            ;;
        esac
      fi
      rm -f /tmp/host-cli-probe.$$
    fi
  fi

  # --- Repository visibility ---
  local repo_visibility
  repo_visibility=$(prompt_choice "Repository visibility:" "private" "public")
  save_answer "repo_visibility" "$repo_visibility"

  save_section 1
  echo ""
}

# ================================================================
# SECTION 2: Business Context
# ================================================================
run_section_2() {
  print_step "Section 2: Business Context"
  echo ""

  # 2.1 The Problem
  print_info "2.1 The Problem"
  print_info "Describe the problem concretely — not 'improve efficiency' but"
  print_info "'reconciling vendor invoices takes 6 hours/week of manual spreadsheet work.'"
  echo ""
  local problem
  problem=$(prompt_input "What problem does this solve?" "")
  save_answer "problem_statement" "$problem"

  # 2.2 Who Has This Problem
  echo ""
  print_info "2.2 Who Has This Problem"
  echo ""
  local primary_persona
  primary_persona=$(prompt_input "Primary user persona (job title, skill level, what they're trying to do)" "")
  save_answer "primary_persona" "$primary_persona"

  local secondary_personas
  secondary_personas=$(prompt_input "Secondary personas (or Enter to skip)" "")
  save_answer "secondary_personas" "${secondary_personas:-N/A}"

  local current_solution
  current_solution=$(prompt_input "How do they solve this today? (spreadsheet, manual process, different tool)" "")
  save_answer "current_solution" "$current_solution"

  local current_problem
  current_problem=$(prompt_input "What's wrong with the current solution?" "")
  save_answer "current_problem" "$current_problem"

  # 2.3 Success Criteria
  echo ""
  print_info "2.3 Success Criteria — define 1-3 measurable metrics"
  echo ""
  for i in 1 2 3; do
    local metric
    metric=$(prompt_input "Success metric $i (or Enter to finish)" "")
    [ -z "$metric" ] && break

    local target
    target=$(prompt_input "  Target value for '$metric'" "")
    local measurement
    measurement=$(prompt_input "  How will you measure this?" "")
    save_answer "metric_${i}_name" "$metric"
    save_answer "metric_${i}_target" "$target"
    save_answer "metric_${i}_measurement" "$measurement"
    echo ""
  done

  # 2.4 What This Is NOT
  print_info "2.4 What This Is NOT — list 3-5 things explicitly out of scope"
  echo ""
  for i in 1 2 3 4 5; do
    local exclusion
    if [ "$i" -le 3 ]; then
      exclusion=$(prompt_input "Out-of-scope item $i" "")
    else
      exclusion=$(prompt_input "Out-of-scope item $i (or Enter to finish)" "")
      [ -z "$exclusion" ] && break
    fi
    save_answer "exclusion_$i" "$exclusion"
  done

  save_section 2
  echo ""
}

# ================================================================
# SECTION 3: Constraints
# ================================================================
run_section_3() {
  print_step "Section 3: Constraints"
  echo ""

  # 3.1 Timeline
  print_info "3.1 Timeline"
  echo ""
  local mvp_date
  mvp_date=$(prompt_with_suggestions "Target MVP date or timeframe" "timeline_mvp" "")
  save_answer "mvp_date" "$mvp_date"

  local hard_deadline
  hard_deadline=$(prompt_choice "Is this a hard deadline?" "No" "Yes — consequences if missed")
  save_answer "hard_deadline" "$hard_deadline"

  local hours_per_week
  hours_per_week=$(prompt_input "Hours per week you can dedicate" "10")
  save_answer "hours_per_week" "$hours_per_week"

  local time_pattern
  time_pattern=$(prompt_choice "Work pattern:" "Blocked time (dedicated sessions)" "Interleaved (between other work, 1-2 hour windows)")
  save_answer "time_pattern" "$time_pattern"

  # 3.2 Budget
  echo ""
  print_info "3.2 Budget"
  echo ""
  local monthly_budget
  monthly_budget=$(prompt_with_suggestions "Monthly infrastructure budget ceiling" "budget_monthly" "")
  save_answer "monthly_budget" "$monthly_budget"

  local one_time_budget
  one_time_budget=$(prompt_input "One-time budget (or N/A)" "N/A")
  save_answer "one_time_budget" "$one_time_budget"

  local ai_subscription
  ai_subscription=$(prompt_choice "AI subscription status:" "Claude Max (\$100/mo)" "Claude Enterprise" "API with commercial terms" "Not yet subscribed")
  save_answer "ai_subscription" "$ai_subscription"

  # 3.3 Users
  echo ""
  print_info "3.3 Users"
  echo ""
  local users_launch
  users_launch=$(prompt_input "Expected users at launch" "")
  save_answer "users_launch" "$users_launch"

  local users_6mo
  users_6mo=$(prompt_input "Expected users at 6 months" "")
  save_answer "users_6mo" "$users_6mo"

  local users_12mo
  users_12mo=$(prompt_input "Expected users at 12 months" "")
  save_answer "users_12mo" "$users_12mo"

  local user_type
  user_type=$(prompt_choice "Internal or external users?" "Internal (within organization)" "External (public or customer-facing)")
  save_answer "user_type" "$user_type"

  local geo_distribution
  geo_distribution=$(prompt_input "Geographic distribution (e.g., 'US only', 'Global', 'Single office')" "")
  save_answer "geo_distribution" "$geo_distribution"

  save_section 3
  echo ""
}

# ================================================================
# SECTION 4: Features & Requirements
# ================================================================
run_section_4() {
  print_step "Section 4: Features & Requirements"
  echo ""

  # 4.1 Must-Have Features
  print_info "4.1 Must-Have Features (MVP)"
  print_info "For each feature, you'll define:"
  print_info "  - The feature name"
  print_info "  - Business logic trigger: 'If [condition], the system must [action]'"
  print_info "  - Failure state: what happens on invalid input or service unavailable"
  echo ""

  for i in 1 2 3 4 5 6 7 8; do
    local feature_name
    if [ "$i" -le 2 ]; then
      feature_name=$(prompt_input "Must-have feature $i" "")
    else
      feature_name=$(prompt_input "Must-have feature $i (or Enter to finish)" "")
      [ -z "$feature_name" ] && break
    fi

    local trigger
    trigger=$(prompt_input "  Business logic: If [condition], system must [action]" "")

    local failure
    failure=$(prompt_input "  Failure state: what happens when it goes wrong?" "")

    save_answer "feature_${i}_name" "$feature_name"
    save_answer "feature_${i}_trigger" "$trigger"
    save_answer "feature_${i}_failure" "$failure"
    echo ""
  done

  # 4.2 Should-Have
  print_info "4.2 Should-Have Features (post-MVP)"
  echo ""
  for i in 1 2 3 4 5; do
    local should_have
    should_have=$(prompt_input "Should-have feature $i (or Enter to finish)" "")
    [ -z "$should_have" ] && break
    save_answer "should_have_$i" "$should_have"
  done

  # 4.3 Will-Not-Have
  echo ""
  print_info "4.3 Will-Not-Have Features (explicit exclusions)"
  echo ""
  for i in 1 2 3 4 5; do
    local will_not
    if [ "$i" -le 3 ]; then
      will_not=$(prompt_input "Will-not-have $i" "")
    else
      will_not=$(prompt_input "Will-not-have $i (or Enter to finish)" "")
      [ -z "$will_not" ] && break
    fi
    save_answer "will_not_$i" "$will_not"
  done

  save_section 4
  echo ""
}

# ================================================================
# SECTION 5: Data & Integrations
# ================================================================
run_section_5() {
  print_step "Section 5: Data & Integrations"
  echo ""

  # 5.1 Data Inputs
  print_info "5.1 Data Inputs — what data does the system accept?"
  echo ""
  for i in 1 2 3 4 5 6; do
    local input_name
    if [ "$i" -le 1 ]; then
      input_name=$(prompt_input "Data input $i name" "")
    else
      input_name=$(prompt_input "Data input $i name (or Enter to finish)" "")
      [ -z "$input_name" ] && break
    fi

    local data_type
    data_type=$(prompt_input "  Data type (e.g., string, number, file, JSON)" "")
    local validation
    validation=$(prompt_input "  Validation rules" "")
    local sensitivity
    sensitivity=$(prompt_with_suggestions "  Sensitivity level" "data_sensitivity" "Internal")
    local required
    required=$(prompt_choice "  Required?" "Yes" "No")

    save_answer "input_${i}_name" "$input_name"
    save_answer "input_${i}_type" "$data_type"
    save_answer "input_${i}_validation" "$validation"
    save_answer "input_${i}_sensitivity" "$sensitivity"
    save_answer "input_${i}_required" "$required"
    echo ""
  done

  # 5.2 Data Outputs
  echo ""
  print_info "5.2 Data Outputs"
  echo ""
  for i in 1 2 3 4; do
    local output_name
    output_name=$(prompt_input "Data output $i name (or Enter to finish)" "")
    [ -z "$output_name" ] && break
    local format
    format=$(prompt_input "  Format (e.g., JSON, CSV, HTML, PDF)" "")
    local latency
    latency=$(prompt_input "  Latency expectation (e.g., <200ms, <2s, batch)" "")
    save_answer "output_${i}_name" "$output_name"
    save_answer "output_${i}_format" "$format"
    save_answer "output_${i}_latency" "$latency"
  done

  # 5.3 Third-Party Integrations
  echo ""
  print_info "5.3 Third-Party Integrations (or Enter to skip)"
  echo ""
  for i in 1 2 3; do
    local service
    service=$(prompt_input "Integration $i — service name (or Enter to finish)" "")
    [ -z "$service" ] && break
    local data_exchanged
    data_exchanged=$(prompt_input "  Data sent/received" "")
    local auth_method
    auth_method=$(prompt_input "  Auth method (API key, OAuth, none)" "")
    local fallback
    fallback=$(prompt_input "  Fallback if unavailable" "")
    save_answer "integration_${i}_service" "$service"
    save_answer "integration_${i}_data" "$data_exchanged"
    save_answer "integration_${i}_auth" "$auth_method"
    save_answer "integration_${i}_fallback" "$fallback"
  done

  # 5.4 Data Persistence
  echo ""
  print_info "5.4 Data Persistence"
  echo ""
  local persistent_data
  persistent_data=$(prompt_input "What data persists across sessions?" "")
  save_answer "persistent_data" "$persistent_data"

  local ephemeral_data
  ephemeral_data=$(prompt_input "What data is ephemeral (session-only)?" "")
  save_answer "ephemeral_data" "$ephemeral_data"

  local data_volume
  data_volume=$(prompt_input "Expected data volume at 12 months (e.g., <1GB, 10GB, 100GB+)" "")
  save_answer "data_volume" "$data_volume"

  local retention
  retention=$(prompt_input "Data retention requirements (e.g., 'indefinite', '7 years', 'until user deletes')" "")
  save_answer "retention" "$retention"

  local backup
  backup=$(prompt_with_suggestions "Backup requirements" "backup_strategy" "Daily automated backups")
  save_answer "backup" "$backup"

  save_section 5
  echo ""
}

# ================================================================
# SECTION 6: Technical Preferences
# ================================================================
run_section_6() {
  print_step "Section 6: Technical Preferences"
  echo ""

  # 6.1 Orchestrator Technical Profile
  print_info "6.1 Your Technical Profile"
  echo ""

  local languages_known
  languages_known=$(prompt_input "Languages you know well" "$LANGUAGE")
  save_answer "languages_known" "$languages_known"

  local frameworks_used
  frameworks_used=$(prompt_input "Frameworks you've used" "")
  save_answer "frameworks_used" "$frameworks_used"

  local willing_to_learn
  willing_to_learn=$(prompt_input "Willing to learn (or Enter to skip)" "")
  save_answer "willing_to_learn" "${willing_to_learn:-N/A}"

  local refuse_to_use
  refuse_to_use=$(prompt_input "Refuse to use (or Enter to skip)" "")
  save_answer "refuse_to_use" "${refuse_to_use:-N/A}"

  local db_experience
  db_experience=$(prompt_input "Database experience (e.g., PostgreSQL, MySQL, MongoDB, none)" "")
  save_answer "db_experience" "$db_experience"

  local devops_experience
  devops_experience=$(prompt_choice "DevOps experience:" "None" "Basic (can deploy to a PaaS)" "Intermediate (Docker, CI/CD)" "Advanced (Kubernetes, IaC)")
  save_answer "devops_experience" "$devops_experience"

  # 6.2 Competency Matrix
  echo ""
  print_info "6.2 Competency Matrix"
  print_info "For each domain: can you review AI output and reliably determine if it's correct?"
  print_info "Every honest 'No' adds automated coverage. Every dishonest 'Yes' creates a gap."
  echo ""

  local domains=("Product/UX Logic" "Frontend Code" "Backend/API Design" "Database Design" "Security" "DevOps/Infrastructure" "Accessibility" "Performance" "Mobile")
  for domain in "${domains[@]}"; do
    local assessment
    assessment=$(prompt_choice "$domain:" "Yes — I can reliably validate this" "Partially — I can catch obvious issues" "No — I need automated tooling here")
    case "$assessment" in
      "Yes"*) assessment="Yes" ;;
      "Partially"*) assessment="Partially" ;;
      "No"*) assessment="No" ;;
    esac
    local key
    key=$(echo "$domain" | tr '/ ' '_' | tr '[:upper:]' '[:lower:]')
    save_answer "competency_$key" "$assessment"
  done

  # 6.3 Development Environment
  echo ""
  print_info "6.3 Development Environment"
  echo ""

  local primary_machine
  primary_machine=$(prompt_input "Primary machine (e.g., 'MacBook Pro M3, macOS 15')" "")
  save_answer "primary_machine" "$primary_machine"

  local ide
  ide=$(prompt_input "IDE/Editor" "VS Code")
  save_answer "ide" "$ide"

  local docker_available
  docker_available=$(prompt_choice "Docker available?" "Yes" "No")
  save_answer "docker_available" "$docker_available"

  # 6.4 Architecture Preferences (platform-specific)
  echo ""
  print_info "6.4 Architecture Preferences"
  echo ""

  local data_storage
  data_storage=$(prompt_with_suggestions "Data storage preference" "database" "")
  save_answer "data_storage" "$data_storage"

  local auth_strategy
  auth_strategy=$(prompt_with_suggestions "Authentication strategy" "authentication" "")
  save_answer "auth_strategy" "$auth_strategy"

  # Platform-specific questions
  case "$PLATFORM" in
    web)
      local frontend_fw
      frontend_fw=$(prompt_with_suggestions "Frontend framework" "frontend_framework" "")
      save_answer "frontend_framework" "$frontend_fw"

      local hosting
      hosting=$(prompt_with_suggestions "Hosting provider" "hosting" "")
      save_answer "hosting" "$hosting"
      ;;
    desktop)
      local ui_fw
      ui_fw=$(prompt_with_suggestions "UI framework" "ui_framework" "")
      save_answer "ui_framework" "$ui_fw"

      local packaging
      packaging=$(prompt_with_suggestions "Packaging format" "packaging" "")
      save_answer "packaging" "$packaging"

      local auto_update
      auto_update=$(prompt_with_suggestions "Auto-update strategy" "auto_update" "")
      save_answer "auto_update" "$auto_update"

      local offline_req
      offline_req=$(prompt_choice "Offline requirement:" "Online only" "Offline tolerant" "Offline capable" "Offline first")
      save_answer "offline_requirement" "$offline_req"
      ;;
    mobile)
      local mobile_fw
      mobile_fw=$(prompt_with_suggestions "Mobile framework" "framework" "")
      save_answer "mobile_framework" "$mobile_fw"

      local min_os
      min_os=$(prompt_input "Minimum OS versions (e.g., 'iOS 16+, Android 13+')" "")
      save_answer "min_os" "$min_os"

      local app_store
      app_store=$(prompt_choice "App store distribution:" "Apple App Store + Google Play" "Apple App Store only" "Google Play only" "Sideload/enterprise only")
      save_answer "app_store" "$app_store"

      local mobile_offline
      mobile_offline=$(prompt_with_suggestions "Offline strategy" "offline_strategy" "Offline tolerant")
      save_answer "mobile_offline" "$mobile_offline"
      ;;
    cli)
      local cli_distribution
      cli_distribution=$(prompt_with_suggestions "Distribution method" "distribution" "")
      save_answer "cli_distribution" "$cli_distribution"

      local cli_ui
      cli_ui=$(prompt_with_suggestions "Interface style" "ui_framework" "")
      save_answer "cli_ui" "$cli_ui"
      ;;
  esac

  # 6.5 Existing Infrastructure (organizational only)
  if [ "$DEPLOYMENT" = "organizational" ]; then
    echo ""
    print_info "6.5 Existing Infrastructure"
    echo ""
    local infra_items=("SSO / Identity Provider" "Logging / SIEM" "Monitoring" "Data Warehouse" "Backup Infrastructure" "CI/CD Platform" "Repository Platform")
    for item in "${infra_items[@]}"; do
      local status
      status=$(prompt_choice "$item:" "Yes — we have this" "No" "N/A")
      local key
      key=$(echo "$item" | tr '/ ' '_' | tr '[:upper:]' '[:lower:]')
      save_answer "infra_$key" "$status"
    done
  fi

  save_section 6
  echo ""
}

# ================================================================
# SECTION 7: Revenue Model (conditional)
# ================================================================
run_section_7() {
  if [ "$TRACK" = "light" ]; then
    print_info "Section 7: Revenue Model — skipped (Light track)"
    save_section 7
    return
  fi

  print_step "Section 7: Revenue Model"
  echo ""

  local pricing_model
  pricing_model=$(prompt_choice "Pricing model:" "Free (internal tool)" "Freemium" "Subscription" "One-time purchase" "Usage-based" "Not decided yet")
  save_answer "pricing_model" "$pricing_model"

  if [ "$pricing_model" != "Free (internal tool)" ]; then
    local price_point
    price_point=$(prompt_input "Target price point" "")
    save_answer "price_point" "$price_point"

    local competitive_range
    competitive_range=$(prompt_input "Competitive price range (what do alternatives cost?)" "")
    save_answer "competitive_range" "$competitive_range"

    local cost_per_user
    cost_per_user=$(prompt_input "Estimated per-user infrastructure cost" "")
    save_answer "cost_per_user" "$cost_per_user"

    local breakeven
    breakeven=$(prompt_input "Break-even user count" "")
    save_answer "breakeven" "$breakeven"
  fi

  local hosting_launch
  hosting_launch=$(prompt_input "Hosting cost ceiling at launch" "")
  save_answer "hosting_launch" "$hosting_launch"

  local hosting_1k
  hosting_1k=$(prompt_input "Hosting cost ceiling at 1,000 users" "")
  save_answer "hosting_1k" "$hosting_1k"

  local hosting_10k
  hosting_10k=$(prompt_input "Hosting cost ceiling at 10,000 users" "")
  save_answer "hosting_10k" "$hosting_10k"

  save_section 7
  echo ""
}

# ================================================================
# SECTION 8: Governance Pre-Flight (Organizational only)
# ================================================================
run_section_8() {
  if [ "$DEPLOYMENT" = "personal" ]; then
    print_info "Section 8: Governance Pre-Flight — skipped (personal project)"
    save_section 8
    return
  fi

  print_step "Section 8: Governance Pre-Flight"
  echo ""
  echo -e "  ${BOLD}Organizational projects require governance approvals before Phase 0.${NC}"
  echo "  Some of these take weeks to resolve. Choose your approach:"
  echo ""

  local gov_mode
  gov_mode=$(prompt_choice "Governance mode:" \
    "Production Build — all approvals required (recommended when approvals are in hand)" \
    "Sponsored POC — organization knows, non-technical approvals deferred" \
    "Private POC — personal exploration, all governance deferred")

  case "$gov_mode" in
    "Production"*) POC_MODE="" ;;
    "Sponsored"*) POC_MODE="sponsored_poc" ;;
    "Private"*) POC_MODE="private_poc" ;;
  esac

  # Update progress file with POC mode
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
poc_mode = sys.argv[1] if sys.argv[1] else None
with open(sys.argv[2]) as f:
    data = json.load(f)
data['poc_mode'] = poc_mode
with open(sys.argv[2], 'w') as f:
    json.dump(data, f, indent=2)
" "$POC_MODE" "$PROGRESS_FILE"
  fi

  if [ -n "$POC_MODE" ]; then
    echo ""
    print_warn "POC MODE: ${POC_MODE//_/ }"
    print_warn "Constraints: no production deployment, no real user data, no external users."
    print_warn "All technical work will be production-grade and carries forward."
    print_warn "Upgrade later: scripts/intake-wizard.sh --upgrade-to-production"
    echo ""
  fi

  # Pre-conditions and which are required per mode
  local preconditions=(
    "AI deployment path approved by IT Security"
    "Insurance confirmation obtained"
    "Liability entity designated"
    "Project sponsor assigned"
    "Backup maintainer designated"
    "ITSM ticket filed / portfolio registered"
    "Exit criteria defined"
    "Orchestrator time allocation approved"
  )
  # Indices required for sponsored POC: 0 (AI path), 3 (sponsor), 7 (time allocation)
  local required_sponsored="0 3 7"

  for i in "${!preconditions[@]}"; do
    local precondition="${preconditions[$i]}"
    local is_deferred=false

    if [ "$POC_MODE" = "private_poc" ]; then
      is_deferred=true
    elif [ "$POC_MODE" = "sponsored_poc" ]; then
      if [[ ! " $required_sponsored " == *" $i "* ]]; then
        is_deferred=true
      fi
    fi

    if [ "$is_deferred" = true ]; then
      print_info "  $precondition — DEFERRED (POC mode)"
      save_answer "precondition_${i}_status" "Deferred (POC)"
      save_answer "precondition_${i}_details" "Deferred — resolve before production"
    else
      echo ""
      local status
      status=$(prompt_choice "$precondition:" "Complete" "In Progress" "Not Started")
      save_answer "precondition_${i}_status" "$status"

      if [ "$status" != "Not Started" ]; then
        local details
        details=$(prompt_input "  Details (contact name, date, ticket #, etc.)" "")
        save_answer "precondition_${i}_details" "$details"
      else
        save_answer "precondition_${i}_details" ""
      fi
    fi
  done

  # Sections 8.2-8.5 only for production mode
  if [ -z "$POC_MODE" ]; then
    # 8.2 Approval Authorities
    echo ""
    print_info "8.2 Approval Authorities"
    echo ""
    local gates=("Phase 0 to Phase 1" "Phase 1 to Phase 2" "Phase 3 to Phase 4")
    for gate in "${gates[@]}"; do
      local approver
      approver=$(prompt_input "$gate approver (name and role)" "")
      local key
      key=$(echo "$gate" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
      save_answer "gate_$key" "$approver"
    done

    # 8.3 Escalation Chain
    echo ""
    print_info "8.3 Escalation Chain"
    echo ""
    local levels=("Level 1 (first escalation)" "Level 2" "Level 3 (final authority)")
    for level in "${levels[@]}"; do
      local contact
      contact=$(prompt_input "$level contact" "")
      local key
      key=$(echo "$level" | tr ' ()' '___' | tr '[:upper:]' '[:lower:]')
      save_answer "escalation_$key" "$contact"
    done

    # 8.4 Compliance Screening
    echo ""
    print_info "8.4 Compliance Screening"
    echo ""
    local compliance_items=(
      "Does this project handle SOX-regulated financial data?"
      "Does this project handle payment card data (PCI)?"
      "Does this project collect personal data across multiple states/countries?"
      "Does this project serve EU users or involve EU subsidiaries?"
      "Does this project involve any OFAC-sanctioned jurisdictions?"
      "Are there records retention requirements?"
      "Does this project use AI for end-user-facing features (not just development)?"
      "Is penetration testing required by organizational policy?"
    )
    for j in "${!compliance_items[@]}"; do
      local answer
      answer=$(prompt_choice "${compliance_items[$j]}" "No" "Yes")
      save_answer "compliance_$j" "$answer"
    done

    # 8.5 Exit Criteria
    echo ""
    print_info "8.5 Exit Criteria"
    echo ""
    local success_def
    success_def=$(prompt_input "Success definition (what makes this project a success?)" "")
    save_answer "exit_success" "$success_def"

    local conditional_def
    conditional_def=$(prompt_input "Conditional success (acceptable with limitations)" "")
    save_answer "exit_conditional" "$conditional_def"

    local failure_def
    failure_def=$(prompt_input "Failure definition (when do we shut it down?)" "")
    save_answer "exit_failure" "$failure_def"
  fi

  save_section 8
  echo ""
}

# ================================================================
# SECTION 9: Accessibility & UX Constraints
# ================================================================
run_section_9() {
  print_step "Section 9: Accessibility & UX Constraints"
  echo ""

  local accessibility_target
  accessibility_target=$(prompt_with_suggestions "Accessibility target" "accessibility_target" "WCAG AA, Lighthouse 90+")
  save_answer "accessibility_target" "$accessibility_target"

  local color_vision
  color_vision=$(prompt_choice "Design for color vision deficiency?" "Yes — never rely on color alone" "No")
  save_answer "color_vision" "$color_vision"

  if [ "$PLATFORM" = "web" ]; then
    local browsers
    browsers=$(prompt_input "Supported browsers" "Chrome, Firefox, Safari, Edge (latest 2 versions)")
    save_answer "browsers" "$browsers"

    local responsive
    responsive=$(prompt_choice "Mobile responsive?" "Yes" "No")
    save_answer "responsive" "$responsive"
  fi

  local dark_mode
  dark_mode=$(prompt_choice "Dark mode:" "Yes" "No" "Nice-to-have (post-MVP)")
  save_answer "dark_mode" "$dark_mode"

  local branding
  branding=$(prompt_input "Branding/style guide (URL or description, or N/A)" "N/A")
  save_answer "branding" "$branding"

  save_section 9
  echo ""
}

# ================================================================
# SECTION 10: Distribution & Operations
# ================================================================
run_section_10() {
  print_step "Section 10: Distribution & Operations"
  echo ""

  local uptime
  uptime=$(prompt_with_suggestions "Uptime expectation" "uptime_expectation" "")
  save_answer "uptime" "$uptime"

  local env_strategy
  env_strategy=$(prompt_choice "Environment strategy:" "Dev + Production" "Dev + Staging + Production" "Production only")
  save_answer "env_strategy" "$env_strategy"

  case "$PLATFORM" in
    web)
      local domain
      domain=$(prompt_input "Domain name (or TBD)" "TBD")
      save_answer "domain" "$domain"

      local maintenance_window
      maintenance_window=$(prompt_input "Preferred maintenance window (or N/A)" "N/A")
      save_answer "maintenance_window" "$maintenance_window"
      ;;
    desktop)
      local dist_channels
      dist_channels=$(prompt_choice "Distribution channels:" "Direct download (website/GitHub)" "App stores (Mac App Store, Microsoft Store)" "Both" "Internal distribution only")
      save_answer "dist_channels" "$dist_channels"

      local code_signing
      code_signing=$(prompt_choice "Code signing:" "Yes — required for distribution" "No — internal/dev use only")
      save_answer "code_signing" "$code_signing"

      local min_os_versions
      min_os_versions=$(prompt_input "Minimum OS versions (e.g., 'Windows 10+, macOS 12+, Ubuntu 22.04+')" "")
      save_answer "min_os_versions" "$min_os_versions"
      ;;
    mobile)
      local mobile_dist
      mobile_dist=$(prompt_choice "Distribution:" "App stores (iOS + Android)" "iOS App Store only" "Google Play only" "Enterprise sideload")
      save_answer "mobile_dist" "$mobile_dist"

      local beta_testing
      beta_testing=$(prompt_choice "Beta testing:" "TestFlight + Google Play internal testing" "TestFlight only" "Google Play internal testing only" "No beta program")
      save_answer "beta_testing" "$beta_testing"
      ;;
  esac

  save_section 10
  echo ""
}

# ================================================================
# SECTION 11: Known Risks & Concerns
# ================================================================
run_section_11() {
  print_step "Section 11: Known Risks & Concerns"
  echo ""

  local risks
  risks=$(prompt_input "Any additional context, known risks, or concerns? (or Enter to skip)" "")
  save_answer "known_risks" "${risks:-None noted}"

  save_section 11
  echo ""
}

# ================================================================
# SECTION 12: Agent Initialization Prompt (auto-generated)
# ================================================================
run_section_12() {
  print_step "Section 12: Agent Initialization Prompt"
  print_info "Auto-generating from your answers..."

  # Read accessibility answers for the prompt
  local accessibility_rules="WCAG AA, Lighthouse 90+"
  if command -v python3 &>/dev/null; then
    accessibility_rules=$(python3 << PYEOF
import json
try:
    with open('$PROGRESS_FILE') as f:
        data = json.load(f)
    answers = data.get('answers', {})
    parts = []
    target = answers.get('accessibility_target', '')
    if target:
        parts.append(f'Accessibility target: {target}')
    color = answers.get('color_vision', '')
    if 'Yes' in color:
        parts.append('Color vision deficiency: never rely on color alone for meaning.')
    print('; '.join(parts) if parts else 'WCAG AA, Lighthouse 90+')
except Exception:
    print('WCAG AA, Lighthouse 90+')
PYEOF
)
  fi

  print_ok "Section 12 auto-generated."
  save_section 12
  echo ""
}

# ================================================================
# MODE: Run all sections in order (script path)
# ================================================================
run_script_mode() {
  local start_section="${1:-1}"

  if [ "$start_section" -gt 1 ]; then
    print_info "Resuming from Section $start_section"
  fi

  echo ""
  print_info "Type 'pause' at any prompt to save and exit."
  print_info "Type '?' at prompts marked with [? for suggestions] to see options."
  echo ""

  local sections=(1 2 3 4 5 6 7 8 9 10 11 12)
  for section in "${sections[@]}"; do
    if [ "$section" -lt "$start_section" ]; then
      continue
    fi

    if is_section_complete "$section" 2>/dev/null; then
      print_ok "Section $section — already complete"
      continue
    fi

    "run_section_$section"
    check_pause_requested
  done

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║              Intake Complete!                           ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  print_ok "PROJECT_INTAKE.md answers saved to $PROGRESS_FILE"
  print_info "Review PROJECT_INTAKE.md, then start Claude Code and begin Phase 0."
  echo ""
}

# ================================================================
# MODE: Generate Claude-guided prompt
# ================================================================
run_claude_mode() {
  print_step "Generating AI-assisted intake prompt..."
  echo ""

  local output_file="$PROJECT_ROOT/INTAKE_GUIDED_PROMPT.md"

  cat > "$output_file" << 'PROMPTEOF'
# Guided Intake Conversation

## Your Role

You are helping a Solo Orchestrator fill out their Project Intake template (PROJECT_INTAKE.md). Walk through it section by section in a conversational tone. Explain each field's purpose before asking. When the user is unsure, offer 2-3 ranked suggestions with context.

PROMPTEOF

  cat >> "$output_file" << PROMPTEOF
## Project Context (from init.sh)

- **Project name:** $PROJECT_NAME
- **Description:** $PROJECT_DESCRIPTION
- **Platform:** $PLATFORM
- **Language:** $LANGUAGE
- **Track:** $TRACK
- **Deployment:** $DEPLOYMENT

## Instructions

1. Walk through PROJECT_INTAKE.md section by section (Sections 1-12).
2. Section 1 is mostly pre-filled from context above — confirm and fill remaining fields (target platforms, codename, repo URL).
3. For each field, explain its purpose briefly, then ask the question.
4. When the user says "I'm not sure" or asks for help, offer 2-3 options ranked by fit for their project type ($PLATFORM, $LANGUAGE, $TRACK), with a one-sentence explanation of why each fits.
5. Check off fields as you cover them. Before moving to the next section, confirm: "Section N complete. Anything to change before we move on?"
6. Skip sections that don't apply:
   - Section 7 (Revenue Model): skip if track is Light or deployment is Personal with internal users
   - Section 8 (Governance): skip if deployment is Personal
7. For Section 8 (Governance, organizational only): ask which mode — Production Build, Sponsored POC, or Private POC. Explain each:
   - **Production Build:** All 8 pre-conditions required. Full governance.
   - **Sponsored POC:** Organization knows. AI deployment path + sponsor + time allocation required. Insurance, liability, ITSM, exit criteria, backup maintainer deferred. Constraints: no production deployment, no real user data, no external users. All technical work is production-grade.
   - **Private POC:** Personal exploration. All pre-conditions deferred. Same constraints as Sponsored POC.
8. Write completed sections into PROJECT_INTAKE.md progressively as you go.
9. Section 12 (Agent Initialization Prompt): auto-generate from the answers. Do not ask the user to write this.
10. At the end, summarize what was filled in and flag any fields left blank.

## Suggestion Data

Use the following platform-specific suggestions when the user needs help with technical choices:

PROMPTEOF

  # Append relevant suggestion file
  local platform_file="$SUGGESTIONS_DIR/${PLATFORM}.json"
  if [ -f "$platform_file" ]; then
    echo '### Platform Suggestions' >> "$output_file"
    echo '```json' >> "$output_file"
    cat "$platform_file" >> "$output_file"
    echo '```' >> "$output_file"
  fi

  # Append common suggestions
  local common_file="$SUGGESTIONS_DIR/common.json"
  if [ -f "$common_file" ]; then
    echo "" >> "$output_file"
    echo "### Common Suggestions" >> "$output_file"
    echo '```json' >> "$output_file"
    cat "$common_file" >> "$output_file"
    echo '```' >> "$output_file"
  fi

  echo ""
  print_ok "Prompt generated: INTAKE_GUIDED_PROMPT.md"
  echo ""

  echo -e "  ${BOLD}How would you like to proceed?${NC}"
  echo ""
  echo "    1. Launch Claude Code now"
  echo "       Opens Claude Code with the intake prompt automatically."
  echo "       You'll have a conversation that fills out PROJECT_INTAKE.md."
  echo ""
  echo "    2. Generate prompt file only"
  echo "       INTAKE_GUIDED_PROMPT.md is ready for you to review first."
  echo "       When ready: claude \"Read INTAKE_GUIDED_PROMPT.md and begin\""
  echo ""
  local launch_choice
  read -rp "$(echo -e "  ${BOLD}Select [1-2]${NC}: ")" launch_choice

  if [ "$launch_choice" = "1" ]; then
    if command -v claude &>/dev/null; then
      print_info "Launching Claude Code..."
      cd "$PROJECT_ROOT"
      exec claude "Read INTAKE_GUIDED_PROMPT.md and follow its instructions to help me fill out PROJECT_INTAKE.md."
    else
      print_warn "Claude Code not found. Install it first, then run:"
      echo "  claude \"Read INTAKE_GUIDED_PROMPT.md and begin\""
    fi
  else
    print_info "Prompt file ready at: INTAKE_GUIDED_PROMPT.md"
    print_info "When ready: claude \"Read INTAKE_GUIDED_PROMPT.md and begin\""
  fi
}

# ================================================================
# MODE: Upgrade POC to production
# ================================================================
run_upgrade_to_production() {
  print_step "Upgrading POC to Production"
  echo ""

  if [ ! -f "$PROGRESS_FILE" ]; then
    print_warn "No progress file found. Nothing to upgrade."
    exit 1
  fi

  load_progress

  if [ -z "$POC_MODE" ]; then
    print_warn "This project is not in POC mode. Nothing to upgrade."
    exit 0
  fi

  print_info "Current mode: ${POC_MODE//_/ }"
  print_info "Upgrading to Production Build. You'll resolve deferred pre-conditions."
  echo ""

  # Re-run Section 8 in production mode
  POC_MODE=""
  DEPLOYMENT="organizational"
  run_section_8

  # Update progress file
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['poc_mode'] = None
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
" "$PROGRESS_FILE"
  fi

  print_ok "Upgraded to Production Build."
  print_info "Review APPROVAL_LOG.md and CLAUDE.md to remove POC watermarks."
  echo ""

  # Re-resolve tools for new track
  if [ -x "scripts/resolve-tools.sh" ] && [ -f ".claude/tool-preferences.json" ]; then
    print_info "Re-resolving tools for production track..."
    # Update track in tool-preferences.json
    if command -v jq &>/dev/null; then
      local tmp_prefs
      tmp_prefs=$(mktemp)
      jq '.context.track = "standard"' ".claude/tool-preferences.json" > "$tmp_prefs" && mv "$tmp_prefs" ".claude/tool-preferences.json"
    fi
    local dev_os platform language track
    dev_os=$(jq -r '.context.dev_os' ".claude/tool-preferences.json")
    platform=$(jq -r '.context.platform' ".claude/tool-preferences.json")
    language=$(jq -r '.context.language' ".claude/tool-preferences.json")
    track=$(jq -r '.context.track' ".claude/tool-preferences.json")
    local current_phase
    current_phase=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' ".claude/phase-state.json" | grep -o '[0-9][0-9]*' || echo "2")

    local tool_output
    tool_output=$(bash scripts/resolve-tools.sh \
      --dev-os "$dev_os" --platform "$platform" --language "$language" \
      --track "$track" --phase "$current_phase" \
      --matrix-dir templates/tool-matrix \
      --tool-prefs ".claude/tool-preferences.json" 2>/dev/null) || true

    if [ -n "$tool_output" ]; then
      local new_tools
      new_tools=$(echo "$tool_output" | jq '[(.auto_install + .manual_install)[] | .name] | length')
      if [ "$new_tools" -gt 0 ]; then
        print_info "New tools available for production track:"
        echo "$tool_output" | jq -r '(.auto_install + .manual_install)[] | "  • \(.name) (\(.category))"'
        echo ""
        print_info "Run scripts/resolve-tools.sh to install them."
      fi
    fi
  fi
}

# ================================================================
# UTILITY: Ask for project context if not available
# ================================================================
ask_project_context() {
  if [ -n "$PROJECT_NAME" ] && [ -n "$PLATFORM" ] && [ -n "$TRACK" ]; then
    echo ""
    print_info "Project context (from init):"
    echo "  Project:    $PROJECT_NAME"
    echo "  Description: ${PROJECT_DESCRIPTION:-<not set>}"
    echo "  Platform:   $PLATFORM"
    echo "  Track:      $TRACK"
    echo "  Language:   $LANGUAGE"
    echo "  Deployment: $DEPLOYMENT"
    [ -n "$POC_MODE" ] && echo "  POC Mode:   ${POC_MODE//_/ }"
    echo ""
    read -rp "$(echo -e "${BOLD}Is this correct? [Y/n]${NC}: ")" confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      print_info "You can change fields in the intake wizard Section 1."
      print_info "Structural changes (platform, language, track) will trigger project reconfiguration."
    fi
    return
  fi

  # Fallback: ask for missing fields
  if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME=$(prompt_input "Project name" "")
  fi
  if [ -z "$PROJECT_DESCRIPTION" ]; then
    PROJECT_DESCRIPTION=$(prompt_input "One-sentence description" "")
  fi
  if [ -z "$PLATFORM" ]; then
    PLATFORM=$(prompt_choice "Platform:" "web" "desktop" "mobile" "cli" "other")
  fi
  if [ -z "$TRACK" ]; then
    TRACK=$(prompt_choice "Track:" "light" "standard" "full")
  fi
  if [ -z "$DEPLOYMENT" ]; then
    DEPLOYMENT=$(prompt_choice "Deployment:" "personal" "organizational")
  fi
  if [ -z "$LANGUAGE" ]; then
    LANGUAGE=$(prompt_choice "Language:" "typescript" "javascript" "python" "rust" "csharp" "kotlin" "java" "go" "dart" "other")
  fi
}

# ================================================================
# MAIN
# ================================================================
main() {
  # Parse flags that don't need project context
  case "${1:-}" in
    --help|-h)
      echo "Usage: scripts/intake-wizard.sh [--resume] [--upgrade-to-production] [--help]"
      echo ""
      echo "  (no flags)              Start the intake wizard or choose mode"
      echo "  --resume                Resume from last save point"
      echo "  --upgrade-to-production Upgrade a POC project to production"
      echo "  --upgrade-track TYPE    Upgrade track (light|standard|full)"
      echo "  --upgrade-deployment T  Upgrade deployment (personal|organizational)"
      echo "  --to-sponsored-poc      Convert to sponsored POC"
      echo "  --help                  Show this help"
      exit 0
      ;;
  esac

  # Check we're in a project directory
  if [ ! -f "$INTAKE_FILE" ]; then
    echo "Error: PROJECT_INTAKE.md not found."
    echo "Run this script from a Solo Orchestrator project directory."
    exit 1
  fi

  # Parse flags that need project context
  case "${1:-}" in
    --resume)
      if ! load_progress; then
        exit 1
      fi
      local next_section=$((LAST_SECTION + 1))
      echo ""
      print_info "Sections completed: ${COMPLETED_SECTIONS:-none}"
      run_script_mode "$next_section"
      exit 0
      ;;
    --upgrade-to-production)
      if [ -x "scripts/upgrade-project.sh" ]; then
        exec bash scripts/upgrade-project.sh --to-production
      else
        run_upgrade_to_production  # fallback to built-in
      fi
      exit 0
      ;;
    --upgrade-track)
      if [ -z "${2:-}" ]; then
        echo "Error: --upgrade-track requires a value (light|standard|full)"
        exit 1
      fi
      if [ -x "scripts/upgrade-project.sh" ]; then
        exec bash scripts/upgrade-project.sh --track "$2"
      else
        echo "Error: scripts/upgrade-project.sh not found. Run 'solo init' first."
        exit 1
      fi
      ;;
    --upgrade-deployment)
      if [ -z "${2:-}" ]; then
        echo "Error: --upgrade-deployment requires a value (personal|organizational)"
        exit 1
      fi
      if [ -x "scripts/upgrade-project.sh" ]; then
        exec bash scripts/upgrade-project.sh --deployment "$2"
      else
        echo "Error: scripts/upgrade-project.sh not found. Run 'solo init' first."
        exit 1
      fi
      ;;
    --to-sponsored-poc)
      if [ -x "scripts/upgrade-project.sh" ]; then
        exec bash scripts/upgrade-project.sh --to-sponsored-poc
      else
        echo "Error: scripts/upgrade-project.sh not found. Run 'solo init' first."
        exit 1
      fi
      ;;
  esac

  # Mode selection
  echo ""
  echo -e "${BOLD}How would you like to fill out the Project Intake?${NC}"
  echo ""
  echo "  1. Guided Script (30-60 minutes)"
  echo "     You answer questions section by section in the terminal. Best if you"
  echo "     already know your project requirements, tech preferences, and constraints."
  echo "     You can pause anytime and resume later. Progress is saved after each section."
  echo ""
  echo "  2. AI-Assisted (45-90 minutes)"
  echo "     Claude Code walks you through the intake conversationally, explains each"
  echo "     field, and suggests options based on your project type. Best if you want"
  echo "     help thinking through requirements or are unsure about technical choices."
  echo "     Requires Claude Code to be authenticated."
  echo ""
  echo "  3. I'll do it manually later"
  echo "     Open PROJECT_INTAKE.md in your editor and fill it out yourself."
  echo "     See the User Guide Section 3 for field-by-field guidance."
  echo ""

  local mode
  read -rp "$(echo -e "${BOLD}Select [1-3]${NC}: ")" mode

  case "$mode" in
    1)
      # Check for existing progress
      if [ -f "$PROGRESS_FILE" ]; then
        load_progress
        if [ "$LAST_SECTION" -gt 0 ]; then
          print_info "Found existing progress (through Section $LAST_SECTION)."
          local resume_choice
          resume_choice=$(prompt_choice "Resume or start over?" \
            "Resume from Section $((LAST_SECTION + 1))" \
            "Start over (previous progress will be overwritten)")
          if [[ "$resume_choice" == "Resume"* ]]; then
            run_script_mode "$((LAST_SECTION + 1))"
            exit 0
          fi
        fi
      fi

      # Load or ask for project context
      load_project_context
      ask_project_context

      COMPLETED_SECTIONS=""
      init_progress
      run_script_mode 1
      ;;
    2)
      load_project_context
      ask_project_context
      run_claude_mode
      ;;
    3)
      print_info "No problem. Open PROJECT_INTAKE.md in your editor when ready."
      print_info "See docs/reference/user-guide.md Section 3 for field-by-field guidance."
      ;;
    *)
      echo "Invalid choice."
      exit 1
      ;;
  esac
}

main "$@"

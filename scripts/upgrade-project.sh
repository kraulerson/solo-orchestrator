#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Project Upgrade Script
# https://github.com/kraulerson/solo-orchestrator
#
# Upgrades a project's track, deployment type, or both.
# Handles all upgrade paths: track upgrades, deployment upgrades,
# POC-to-production, and personal-to-sponsored-POC transitions.
#
# Changelog:
# - BL-006 (2026-04-24): pre-commit gate now blocks feat: commits without
#   an active Build Loop. No migration code needed — the updated
#   scripts/process-checklist.sh and scripts/pre-commit-gate.sh are copied
#   by this script's existing behavior, so running an upgrade picks it up.
# - BL-015 (2026-04-25): pre-commit gate now blocks commits and PR creation
#   when .claude/pending-approval.json exists. New helper script
#   scripts/pending-approval.sh. CLAUDE.md template gets new bullet under
#   Construction Rules. Upgrade picks up the new scripts and template.
# - BL-016 (2026-04-25): init.sh now supports --non-interactive mode for
#   scriptable project setup (CI, UAT, AI agents). No upgrade-project.sh
#   change needed — scripts/init.sh is copied into projects but agents
#   typically invoke the framework's init.sh directly.
#
# Usage:
#   scripts/upgrade-project.sh --track standard          # Track upgrade only
#   scripts/upgrade-project.sh --deployment organizational  # Deployment upgrade only
#   scripts/upgrade-project.sh --to-production            # Full upgrade to production
#                                                          # (organizational POCs must have
#                                                          #  APPROVAL_LOG.md Pre-Phase-0 dates
#                                                          #  filled, or pass
#                                                          #  --ack-preconditions=<N1,N2,...>
#                                                          #  with --non-interactive)
#   scripts/upgrade-project.sh --to-sponsored-poc         # Personal → Sponsored POC
#   scripts/upgrade-project.sh --to-private-poc           # Personal → Private POC
#   scripts/upgrade-project.sh --help

# --- Locate orchestrator and project ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

ORCHESTRATOR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# This script runs from the PROJECT directory, not the orchestrator directory.
# Detect project root by looking for .claude/phase-state.json in cwd or parents.
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.claude/phase-state.json" ]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo ""
}

PROJECT_ROOT="$(find_project_root)"

# --- Constants ---
TRACK_ORDER=("light" "standard" "full")
VALID_TRACKS="light standard full"
VALID_DEPLOYMENTS="personal organizational"

# --- Argument parsing ---
TARGET_TRACK=""
TO_PRIVATE_POC=false
TARGET_DEPLOYMENT=""
TO_PRODUCTION=false
TO_SPONSORED_POC=false
SHOW_HELP=false
# BL-018: explicit non-interactive marker (overrides [-t 0] auto-detection) + validate-only.
NON_INTERACTIVE=false
VALIDATE_ONLY=false
# code-upgrade-project-8: comma-separated row numbers (1-6) acknowledging
# deferred Pre-Phase-0 pre-conditions when APPROVAL_LOG.md dates are
# absent. Honored only with --to-production --non-interactive. Empty
# string means "no rows acked."
ACK_PRECONDITIONS=""
# Post-PR #48: --backfill-only runs only the host backfill + BL-030
# manifest backfill (deployment, poc_mode, enforcement_level) and
# exits. Lets operators of pre-BL-030 projects upgrade their manifest
# without choosing a track / deployment / POC transition.
BACKFILL_ONLY=false

# BL-018: BL-016-style structured error helper (summary + reason + action + context).
_upgrade_fail() {
  local summary="$1" reason="$2" action="$3" context="${4:-}"
  echo "[FAIL] upgrade-project.sh: $summary" >&2
  echo "  Reason: $reason" >&2
  echo "  Action: $action" >&2
  if [ -n "$context" ]; then
    echo "  Context: $context" >&2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --track)
      if [ $# -lt 2 ]; then
        _upgrade_fail "--track requires a value" \
                      "the --track flag was passed without a value." \
                      "re-run with --track <light|standard|full>." \
                      "--track=(unset)"
        exit 1
      fi
      TARGET_TRACK="$2"
      case "$TARGET_TRACK" in
        light|standard|full) ;;
        *)
          _upgrade_fail "invalid --track '$TARGET_TRACK'" \
                        "track must be one of: light, standard, full." \
                        "re-run with a supported --track value." \
                        "--track='$TARGET_TRACK'"
          exit 1 ;;
      esac
      shift 2
      ;;
    --deployment)
      if [ $# -lt 2 ]; then
        _upgrade_fail "--deployment requires a value" \
                      "the --deployment flag was passed without a value." \
                      "re-run with --deployment <personal|organizational>." \
                      "--deployment=(unset)"
        exit 1
      fi
      TARGET_DEPLOYMENT="$2"
      case "$TARGET_DEPLOYMENT" in
        personal|organizational) ;;
        *)
          _upgrade_fail "invalid --deployment '$TARGET_DEPLOYMENT'" \
                        "deployment must be one of: personal, organizational." \
                        "re-run with a supported --deployment value." \
                        "--deployment='$TARGET_DEPLOYMENT'"
          exit 1 ;;
      esac
      shift 2
      ;;
    --backfill-only)
      BACKFILL_ONLY=true; shift; continue ;;
    --to-production)
      TO_PRODUCTION=true
      shift
      ;;
    --to-private-poc)
      TO_PRIVATE_POC=true
      shift
      ;;
    --to-sponsored-poc)
      TO_SPONSORED_POC=true
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    --ack-preconditions=*)
      # code-upgrade-project-8: CI escape hatch parallel to
      # --confirm-pitfalls. Comma-separated row numbers 1-6 (e.g.
      # --ack-preconditions=2,3,5,6). Each acknowledged row counts as a
      # satisfied Pre-Phase-0 pre-condition during the --to-production
      # gate. Honored only when --non-interactive is also passed.
      ACK_PRECONDITIONS="${1#--ack-preconditions=}"
      # Validate: only digits and commas; each token must be 1-6.
      _ack_clean="$(echo "$ACK_PRECONDITIONS" | tr -d ' ')"
      if [ -z "$_ack_clean" ] || ! echo "$_ack_clean" | grep -qE '^[1-6](,[1-6])*$'; then
        _upgrade_fail "invalid --ack-preconditions value '$ACK_PRECONDITIONS'" \
                      "value must be a comma-separated list of row numbers 1-6 (e.g. 2,3,5,6)." \
                      "re-run with --ack-preconditions=<N1,N2,...> using row numbers from APPROVAL_LOG.md Pre-Phase 0." \
                      "--ack-preconditions='$ACK_PRECONDITIONS'"
        exit 1
      fi
      ACK_PRECONDITIONS="$_ack_clean"
      shift
      ;;
    --ack-preconditions)
      _upgrade_fail "--ack-preconditions requires a value via =LIST" \
                    "the --ack-preconditions flag requires --ack-preconditions=<N1,N2,...> form." \
                    "re-run with --ack-preconditions=1,2,3,4,5,6 (or your subset)." \
                    "--ack-preconditions=(unset)"
      exit 1
      ;;
    --help|-h)
      SHOW_HELP=true
      shift
      ;;
    *)
      _upgrade_fail "unknown argument '$1'" \
                    "the argument was not recognized." \
                    "see --help for the full flag list." \
                    "$1"
      exit 1
      ;;
  esac
done

# BL-018: --to-* flags are mutually exclusive (combining them produces undefined upgrade paths).
_to_count=0
[ "$TO_PRODUCTION" = true ]    && _to_count=$((_to_count + 1))
[ "$TO_SPONSORED_POC" = true ] && _to_count=$((_to_count + 1))
[ "$TO_PRIVATE_POC" = true ]   && _to_count=$((_to_count + 1))
if [ "$_to_count" -gt 1 ]; then
  _upgrade_fail "--to-production / --to-sponsored-poc / --to-private-poc are mutually exclusive" \
                "only one upgrade-target shortcut may be specified per invocation." \
                "pick one --to-* flag, or use --track/--deployment for granular upgrades." \
                "to_production=$TO_PRODUCTION, to_sponsored_poc=$TO_SPONSORED_POC, to_private_poc=$TO_PRIVATE_POC"
  exit 1
fi

# BL-018: --validate-only — emit resolved arg JSON and exit before any project read or mutation.
# Requires at least one upgrade target so the resolved JSON has actionable content.
if [ "$VALIDATE_ONLY" = true ]; then
  if [ -z "$TARGET_TRACK" ] && [ -z "$TARGET_DEPLOYMENT" ] && [ "$_to_count" -eq 0 ]; then
    _upgrade_fail "--validate-only requires at least one upgrade target" \
                  "no --track, --deployment, or --to-* flag was specified." \
                  "re-run with one of: --track <T>, --deployment <D>, --to-production, --to-sponsored-poc, --to-private-poc." \
                  "no_target_flag=true"
    exit 1
  fi
  jq -n \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg track "$TARGET_TRACK" \
    --arg deployment "$TARGET_DEPLOYMENT" \
    --argjson to_production    "$([ "$TO_PRODUCTION" = true ]    && echo true || echo false)" \
    --argjson to_sponsored_poc "$([ "$TO_SPONSORED_POC" = true ] && echo true || echo false)" \
    --argjson to_private_poc   "$([ "$TO_PRIVATE_POC" = true ]   && echo true || echo false)" \
    --argjson non_interactive  "$([ "$NON_INTERACTIVE" = true ]  && echo true || echo false)" \
    '{
      _validated: true,
      _resolved_at: $ts,
      target_track:      (if $track == ""      then null else $track      end),
      target_deployment: (if $deployment == "" then null else $deployment end),
      to_production:    $to_production,
      to_sponsored_poc: $to_sponsored_poc,
      to_private_poc:   $to_private_poc,
      non_interactive:  $non_interactive,
      validate_only:    true
    }'
  exit 0
fi

# --- Idempotent manifest backfills (run before target-flag check) ---
# These migrate pre-existing projects to the current schema without
# requiring the operator to also pick a track / deployment / POC
# transition. Idempotent — both block on `! jq -e '.<field>'` so a
# second run is a no-op.
( cd "$PROJECT_ROOT"
  # --- Host-aware migration (spec 2026-04-21) ---
  # Projects created before the host-aware gate need the flat CI template
  # layout migrated into per-host subfolders and the manifest backfilled
  # with a host field. Idempotent on already-migrated projects.
  if [ -d templates/pipelines/ci ] && [ ! -d templates/pipelines/ci/github ] && ls templates/pipelines/ci/*.yml >/dev/null 2>&1; then
    print_step "Migrating flat CI template layout → per-host subfolders"
    mkdir -p templates/pipelines/ci/github templates/pipelines/release/github
    for f in templates/pipelines/ci/*.yml; do
      [ -f "$f" ] && (git mv "$f" "templates/pipelines/ci/github/$(basename "$f")" 2>/dev/null || mv "$f" "templates/pipelines/ci/github/$(basename "$f")")
    done
    for f in templates/pipelines/release/*.yml; do
      [ -f "$f" ] && (git mv "$f" "templates/pipelines/release/github/$(basename "$f")" 2>/dev/null || mv "$f" "templates/pipelines/release/github/$(basename "$f")")
    done
    print_ok "CI/release templates moved to github/ subfolders"
  fi

  if [ -f .claude/manifest.json ] && ! jq -e '.host' .claude/manifest.json >/dev/null 2>&1; then
    print_step "Backfilling manifest.json 'host' field"
    print_info "Manifest predates the host-aware gate — inferring host from git remote"
    host_url=$(git remote get-url origin 2>/dev/null || echo "")
    case "$host_url" in
      *github.com*)    inferred_host="github" ;;
      *gitlab*)        inferred_host="gitlab" ;;
      *bitbucket.org*) inferred_host="bitbucket" ;;
      *)               inferred_host="other" ;;
    esac
    jq --arg h "$inferred_host" '.host = $h' .claude/manifest.json > .claude/manifest.json.tmp \
      && mv .claude/manifest.json.tmp .claude/manifest.json
    print_ok "host set to '$inferred_host' (verify via scripts/check-gate.sh --backfill-host if wrong)"
  fi

  # --- BL-030 manifest backfill (post-PR #48 safety contract) ---
  # Pre-BL-030 projects have no .enforcement_level / .deployment /
  # .poc_mode in manifest.json. After PR #48, assert_choosable's jq
  # default (.deployment // "personal") silently treated those projects
  # as choosable, letting reconfigure-project.sh --enforcement-level no
  # bypass baseline §2.5 tier-forcing for organizational/sponsored_poc /
  # organizational/production projects. This block backfills the three
  # fields from phase-state.json (canonical post-S2-cluster-4 source),
  # forces enforcement_level=strict (no auto-relaxation on the upgrade
  # path), installs the filesystem gate, initializes the detection
  # baseline, and writes an enforcement_level_set audit row sourced
  # 'upgrade-backfill' so the lifecycle is traceable.
  if [ -f .claude/manifest.json ] && ! jq -e '.enforcement_level' .claude/manifest.json >/dev/null 2>&1; then
    print_step "Backfilling manifest.json BL-030 fields (deployment, poc_mode, enforcement_level)"
    mig_deployment=""
    mig_poc=""
    if [ -f .claude/phase-state.json ]; then
      mig_deployment=$(jq -r '.deployment // ""' .claude/phase-state.json 2>/dev/null || echo "")
      mig_poc=$(jq -r '.poc_mode // ""' .claude/phase-state.json 2>/dev/null || echo "")
      [ "$mig_deployment" = "null" ] && mig_deployment=""
      [ "$mig_poc" = "null" ] && mig_poc=""
    fi
    if [ -z "$mig_deployment" ]; then
      print_warn "phase-state.json lacks .deployment — assuming 'personal' for backfill."
      print_warn "If this project is organizational, re-run upgrade-project.sh after the backfill:"
      print_warn "  scripts/upgrade-project.sh --deployment organizational"
      mig_deployment="personal"
    fi
    if [ -n "$mig_poc" ]; then
      jq --arg dep "$mig_deployment" --arg pm "$mig_poc" \
        '. + {deployment: $dep, poc_mode: $pm, enforcement_level: "strict"}' \
        .claude/manifest.json > .claude/manifest.json.tmp \
        && mv .claude/manifest.json.tmp .claude/manifest.json
    else
      jq --arg dep "$mig_deployment" \
        '. + {deployment: $dep, poc_mode: null, enforcement_level: "strict"}' \
        .claude/manifest.json > .claude/manifest.json.tmp \
        && mv .claude/manifest.json.tmp .claude/manifest.json
    fi
    if [ ! -f .claude/last-checked-commit.txt ]; then
      git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt || true
    fi
    if [ -x "scripts/install-filesystem-gates.sh" ]; then
      bash scripts/install-filesystem-gates.sh --install "$(pwd)" >/dev/null 2>&1 || true
    fi
    [ -f .claude/bypass-audit.json ] || echo "[]" > .claude/bypass-audit.json
    bf_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    bf_row=$(jq -nc \
      --arg ts "$bf_ts" \
      --arg dep "$mig_deployment" \
      --arg pm "$mig_poc" \
      '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"framework",
        enforcement_level_at_event:"strict",
        details:{level:"strict", deployment:$dep, poc_mode:$pm, source:"upgrade-backfill"},
        user_response:"n/a", final_outcome:"recorded_only"}')
    bf_tmp=$(mktemp)
    jq --argjson r "$bf_row" '. + [$r]' .claude/bypass-audit.json > "$bf_tmp" \
      && mv "$bf_tmp" .claude/bypass-audit.json
    print_ok "BL-030 fields backfilled: deployment=$mig_deployment poc_mode=${mig_poc:-null} enforcement_level=strict"
    print_info "To choose a less strict level (personal/choosable projects only):"
    print_info "  scripts/reconfigure-project.sh --enforcement-level <light|no> --confirm-pitfalls"
  fi

  # --- Vendored-skills sync (audit code-upgrade-project-3, S3 sweep) ---
  # init.sh's skill-install block (init.sh ~line 1239) enumerates each
  # vendored skill explicitly. Skills shipped after a project was created
  # (grill-with-docs, session-handoff, sweep-triage, zoom-out) never reach
  # those projects on re-init. Iterating templates/generated/skills/*/ keeps
  # the upgrade automatically in sync as new skills are added — no edits
  # to upgrade-project.sh needed when a new skill lands. Lives inside the
  # backfill block so --backfill-only picks it up (parallel to BL-030 and
  # host-aware backfills). Idempotent: cp overwrites identically; the -ef
  # self-copy guard handles the in-framework-repo invocation.
  SKILLS_SRC_DIR="$ORCHESTRATOR_ROOT/templates/generated/skills"
  if [ -d "$SKILLS_SRC_DIR" ]; then
    mkdir -p .claude/skills
    for skill_src in "$SKILLS_SRC_DIR"/*/; do
      [ -d "$skill_src" ] || continue
      skill_name=$(basename "$skill_src")
      skill_dest=".claude/skills/$skill_name"
      # Self-copy guard mirroring the helper-script block at the end of
      # this script: when invoked from inside the framework repo, source
      # and destination resolve to the same path and cp would error
      # under set -euo pipefail.
      if [ -d "$skill_dest" ] && [ "$skill_src" -ef "$skill_dest/" ]; then
        continue
      fi
      mkdir -p "$skill_dest"
      [ -f "$skill_src/SKILL.md" ] && cp "$skill_src/SKILL.md" "$skill_dest/"
      [ -f "$skill_src/NOTICE" ]   && cp "$skill_src/NOTICE"   "$skill_dest/"
    done
    print_ok "Vendored skills synced into .claude/skills/ (code-upgrade-project-3)"
  fi
)

# --backfill-only short-circuits here — no track / deployment / POC
# transition follows.
if [ "$BACKFILL_ONLY" = true ]; then
  exit 0
fi

# BL-018: outside --validate-only, still require at least one upgrade target so the script
# doesn't run a no-op end-to-end (was previously inferred late in the flow with confusing
# error messages if no flag was passed).
if [ "$SHOW_HELP" != true ] \
   && [ -z "$TARGET_TRACK" ] && [ -z "$TARGET_DEPLOYMENT" ] && [ "$_to_count" -eq 0 ]; then
  _upgrade_fail "no upgrade target specified" \
                "upgrade-project.sh needs at least one of --track, --deployment, --to-production, --to-sponsored-poc, or --to-private-poc." \
                "see --help for the full flag list." \
                "no_target_flag=true"
  exit 1
fi

# --- Help ---
if [ "$SHOW_HELP" = true ]; then
  echo ""
  echo -e "${BOLD}Solo Orchestrator — Project Upgrade${NC}"
  echo ""
  echo "Upgrades a project's track, deployment type, or both."
  echo "Run this from your project directory (where .claude/phase-state.json lives)."
  echo ""
  echo -e "${BOLD}Usage:${NC}"
  echo "  scripts/upgrade-project.sh --track standard           # Track upgrade (light->standard, etc.)"
  echo "  scripts/upgrade-project.sh --track full               # Track upgrade to full"
  echo "  scripts/upgrade-project.sh --deployment organizational # Add governance framework"
  echo "  scripts/upgrade-project.sh --to-production            # POC -> Production (auto-bumps track to standard if light; remove POC)"
  echo "  scripts/upgrade-project.sh --to-sponsored-poc         # Private POC -> Sponsored POC"
  echo "  scripts/upgrade-project.sh --to-private-poc           # Personal -> Private POC"
  echo "  scripts/upgrade-project.sh --help                     # This help message"
  echo ""
  echo -e "${BOLD}Mode flags (BL-018):${NC}"
  echo "  --non-interactive       Force non-interactive mode (skips Y/N confirmations even on a tty)."
  echo "                          Auto-detected when stdin is not a tty; this flag overrides for clarity."
  echo "  --validate-only         Parse + validate flags, print resolved JSON to stdout, exit 0."
  echo "                          No filesystem reads of project state; no mutation."
  echo ""
  echo -e "${BOLD}--to-production pre-condition gate (code-upgrade-project-8):${NC}"
  echo "  --to-production refuses to clear poc_mode for organizational projects"
  echo "  unless APPROVAL_LOG.md Pre-Phase 0 rows 1-6 are all dated. Operators can"
  echo "  acknowledge missing rows out-of-band via:"
  echo "  --ack-preconditions=<N1,N2,...>"
  echo "                          Comma-separated row numbers (1-6) to mark as"
  echo "                          satisfied. Honored only with --non-interactive."
  echo "                          Writes a user_terminal row to .claude/bypass-audit.json."
  echo "                          Example: --non-interactive --ack-preconditions=2,3,5,6"
  echo ""
  echo -e "${BOLD}Flags can be combined:${NC}"
  echo "  scripts/upgrade-project.sh --track standard --deployment organizational"
  echo "  scripts/upgrade-project.sh --validate-only --to-production"
  echo "  scripts/upgrade-project.sh --to-production --non-interactive --ack-preconditions=2,3,5,6"
  echo ""
  echo -e "${BOLD}Upgrade paths:${NC}"
  echo "  Track:       light -> standard, light -> full, standard -> full"
  echo "  Deployment:  personal -> organizational (adds governance framework)"
  echo "  POC modes:   private_poc -> sponsored_poc, private_poc -> production,"
  echo "               sponsored_poc -> production"
  echo ""
  echo -e "${BOLD}What gets updated:${NC}"
  echo "  - .claude/phase-state.json (track)"
  echo "  - .claude/tool-preferences.json (track in context)"
  echo "  - CLAUDE.md (POC watermarks removed, governance section added)"
  echo "  - PROJECT_INTAKE.md (track/deployment fields, governance section)"
  echo "  - APPROVAL_LOG.md (restructured for organizational if deployment changes)"
  echo "  - Tool resolution (new tools surfaced for the upgraded track)"
  echo ""
  exit 0
fi

# --- Validate project root ---
if [ -z "$PROJECT_ROOT" ]; then
  print_fail "No Solo Orchestrator project found."
  print_info "Run this script from your project directory (where .claude/phase-state.json lives)."
  exit 1
fi

# --- Prerequisites ---
if ! command -v jq &>/dev/null; then
  print_fail "jq is required but not installed."
  print_info "Install with: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  print_fail "python3 is required but not installed."
  exit 1
fi

# UAT 2026-04-25 fix (U-N): refuse to operate inside the framework repo.
guard_not_in_framework || exit 1

# --- BL-015 pending-approval sentinel respect (UAT 2026-04-25 fix C5) ---
# If the agent has offered structured options to the user via
# scripts/pending-approval.sh, refuse to advance an irreversible upgrade.
# Surfaced by 5/5 upgrade UAT agents (49, 62, 79, 82, 84): upgrade-project.sh
# was happily writing files and committing while a sentinel existed.
PENDING_APPROVAL_FILE="$PROJECT_ROOT/.claude/pending-approval.json"
if [ -f "$PENDING_APPROVAL_FILE" ]; then
  print_fail "upgrade blocked — pending user decision."
  if jq -e . "$PENDING_APPROVAL_FILE" >/dev/null 2>&1; then
    pa_question=$(jq -r '.question // "(missing)"' "$PENDING_APPROVAL_FILE")
    pa_offered=$(jq -r '.offered_at // "(unknown)"' "$PENDING_APPROVAL_FILE")
    echo "" >&2
    echo "  Pending question: \"$pa_question\" (offered $pa_offered)" >&2
    echo "  Options:" >&2
    jq -r '.options[]? // empty | "    " + .' "$PENDING_APPROVAL_FILE" >&2
  else
    echo "" >&2
    echo "  Sentinel file $PENDING_APPROVAL_FILE exists but is malformed." >&2
    echo "  Treated as in-flight per CDF 4.2.3 contract." >&2
  fi
  echo "" >&2
  echo "  Wait for the user to pick, then:" >&2
  echo "    scripts/pending-approval.sh --resolve" >&2
  echo "  Or, if the question is being aborted:" >&2
  echo "    scripts/pending-approval.sh --clear" >&2
  exit 1
fi

# --- File paths ---
PHASE_STATE="$PROJECT_ROOT/.claude/phase-state.json"
TOOL_PREFS="$PROJECT_ROOT/.claude/tool-preferences.json"
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
INTAKE_MD="$PROJECT_ROOT/PROJECT_INTAKE.md"
APPROVAL_LOG="$PROJECT_ROOT/APPROVAL_LOG.md"
INTAKE_PROGRESS="$PROJECT_ROOT/.claude/intake-progress.json"
# BL-061: manifest.json carries a stale snapshot of deployment/poc_mode/track
# after upgrade-project.sh runs. Refresh it in the atomic mutation block so
# every reader of manifest.json sees the same tier as phase-state.json.
MANIFEST_JSON="$PROJECT_ROOT/.claude/manifest.json"

# --- Read current state ---
print_step "Reading current project state"

if [ ! -f "$PHASE_STATE" ]; then
  print_fail "Phase state file not found: $PHASE_STATE"
  exit 1
fi

CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE")
PROJECT_NAME=$(jq -r '.project // "Unknown"' "$PHASE_STATE")

# Read track from tool-preferences.json context, falling back to phase-state or intake-progress
CURRENT_TRACK=""
CURRENT_DEPLOYMENT=""
CURRENT_POC_MODE=""
CURRENT_PLATFORM=""
CURRENT_LANGUAGE=""
CURRENT_DEV_OS=""

if [ -f "$TOOL_PREFS" ]; then
  CURRENT_TRACK=$(jq -r '.context.track // ""' "$TOOL_PREFS")
  CURRENT_PLATFORM=$(jq -r '.context.platform // ""' "$TOOL_PREFS")
  CURRENT_LANGUAGE=$(jq -r '.context.language // ""' "$TOOL_PREFS")
  CURRENT_DEV_OS=$(jq -r '.context.dev_os // ""' "$TOOL_PREFS")
fi

# Fall back to intake-progress.json for deployment and POC mode
if [ -f "$INTAKE_PROGRESS" ]; then
  if [ -z "$CURRENT_TRACK" ]; then
    CURRENT_TRACK=$(jq -r '.track // ""' "$INTAKE_PROGRESS")
  fi
  CURRENT_DEPLOYMENT=$(jq -r '.deployment // ""' "$INTAKE_PROGRESS")
  CURRENT_POC_MODE=$(jq -r '.poc_mode // ""' "$INTAKE_PROGRESS")
  if [ "$CURRENT_POC_MODE" = "null" ]; then
    CURRENT_POC_MODE=""
  fi
  if [ -z "$CURRENT_PLATFORM" ]; then
    CURRENT_PLATFORM=$(jq -r '.platform // ""' "$INTAKE_PROGRESS")
  fi
  if [ -z "$CURRENT_LANGUAGE" ]; then
    CURRENT_LANGUAGE=$(jq -r '.language // ""' "$INTAKE_PROGRESS")
  fi
fi

# Final fallback: read from phase-state.json — the canonical source init.sh writes.
# UAT 2026-04-25 fix C4: agents 49,77,78,80,81,82 all hit "Project is not in
# POC mode" when intake-progress.json was missing because init.sh never creates
# it. phase-state.json carries .track/.deployment/.poc_mode from init.sh:1527.
if [ -f "$PHASE_STATE" ]; then
  if [ -z "$CURRENT_TRACK" ]; then
    CURRENT_TRACK=$(jq -r '.track // ""' "$PHASE_STATE")
  fi
  if [ -z "$CURRENT_DEPLOYMENT" ]; then
    CURRENT_DEPLOYMENT=$(jq -r '.deployment // ""' "$PHASE_STATE")
  fi
  if [ -z "$CURRENT_POC_MODE" ]; then
    CURRENT_POC_MODE=$(jq -r '.poc_mode // ""' "$PHASE_STATE")
    if [ "$CURRENT_POC_MODE" = "null" ]; then
      CURRENT_POC_MODE=""
    fi
  fi
fi

# Detect deployment from APPROVAL_LOG.md frontmatter if not in progress file
if [ -z "$CURRENT_DEPLOYMENT" ] && [ -f "$APPROVAL_LOG" ]; then
  CURRENT_DEPLOYMENT=$(grep -m1 '^deployment:' "$APPROVAL_LOG" 2>/dev/null | sed 's/deployment: *//' || echo "")
fi

# Detect deployment from CLAUDE.md or PROJECT_INTAKE.md if still empty
if [ -z "$CURRENT_DEPLOYMENT" ]; then
  if [ -f "$INTAKE_MD" ]; then
    if grep -q "Organizational" "$INTAKE_MD" 2>/dev/null; then
      CURRENT_DEPLOYMENT="organizational"
    elif grep -q "Personal" "$INTAKE_MD" 2>/dev/null; then
      CURRENT_DEPLOYMENT="personal"
    fi
  fi
fi

# Default dev_os
if [ -z "$CURRENT_DEV_OS" ]; then
  case "$(uname -s)" in
    Darwin*) CURRENT_DEV_OS="darwin" ;;
    Linux*)  CURRENT_DEV_OS="linux" ;;
    *)       CURRENT_DEV_OS="darwin" ;;
  esac
fi

# Validate we have enough state to proceed
if [ -z "$CURRENT_TRACK" ]; then
  print_fail "Cannot determine current track."
  print_info "Ensure .claude/tool-preferences.json or .claude/intake-progress.json exists with track info."
  exit 1
fi

if [ -z "$CURRENT_DEPLOYMENT" ]; then
  print_warn "Cannot determine current deployment type. Assuming personal."
  CURRENT_DEPLOYMENT="personal"
fi

print_ok "Project: $PROJECT_NAME"
print_ok "Current track: $CURRENT_TRACK"
print_ok "Current deployment: $CURRENT_DEPLOYMENT"
if [ -n "$CURRENT_POC_MODE" ]; then
  print_ok "Current POC mode: ${CURRENT_POC_MODE//_/ }"
fi
print_ok "Current phase: $CURRENT_PHASE"
echo ""

# ================================================================
# Resolve target state based on flags
# ================================================================

# Helper: get track rank (light=0, standard=1, full=2)
track_rank() {
  case "$1" in
    light)    echo 0 ;;
    standard) echo 1 ;;
    full)     echo 2 ;;
    *)        echo -1 ;;
  esac
}

# --to-production: infer target track and deployment
if [ "$TO_PRODUCTION" = true ]; then
  # Must currently be in POC mode
  if [ -z "$CURRENT_POC_MODE" ]; then
    print_fail "Project is not in POC mode. Use --track and/or --deployment for non-POC upgrades."
    exit 1
  fi

  # Default target track: standard (or keep current if already higher)
  if [ -z "$TARGET_TRACK" ]; then
    if [ "$(track_rank "$CURRENT_TRACK")" -lt "$(track_rank "standard")" ]; then
      TARGET_TRACK="standard"
      print_warn "Track will auto-bump from $CURRENT_TRACK -> standard."
      print_warn "  --to-production requires standard or higher (release-pipeline policy)."
      print_warn "  Pass --track light to keep current track, or --track full to upgrade further."
    else
      TARGET_TRACK="$CURRENT_TRACK"
    fi
  fi

  # Audit cluster 2 follow-up (2026-06): Production is a tier-neutral
  # mode per baseline §2.5 — valid for either deployment. Pre-fix this
  # forced personal/Private POC + --to-production into organizational,
  # silently converting the tier. Now Production preserves whatever
  # deployment the project already has; the operator can pass
  # --deployment organizational explicitly if they want to upgrade
  # deployment AND POC mode in one shot.
  if [ -z "$TARGET_DEPLOYMENT" ]; then
    TARGET_DEPLOYMENT="$CURRENT_DEPLOYMENT"
  fi
fi

# --to-sponsored-poc: personal/light -> organizational/light
if [ "$TO_SPONSORED_POC" = true ]; then
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ "$CURRENT_POC_MODE" = "sponsored_poc" ]; then
    print_warn "Project is already a Sponsored POC. Nothing to do."
    exit 0
  fi
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ -z "$CURRENT_POC_MODE" ]; then
    print_fail "Project is already organizational/production. Cannot downgrade to Sponsored POC."
    exit 1
  fi
  TARGET_DEPLOYMENT="organizational"
  # Track stays the same for POC transition
  if [ -z "$TARGET_TRACK" ]; then
    TARGET_TRACK="$CURRENT_TRACK"
  fi
fi

# --to-private-poc: -> personal/private_poc
# Audit code-upgrade-project-1 + tier-crosscheck-3 (2026-06): Private POC
# is always a personal deployment per baseline §2.5. Prior behavior set
# TARGET_DEPLOYMENT=organizational, producing the impossible
# organizational/private_poc shape. The three existing guards already
# block any path where CURRENT_DEPLOYMENT=organizational, so by the time
# we reach the assignment we know the project is personal.
if [ "$TO_PRIVATE_POC" = true ]; then
  if [ "$CURRENT_DEPLOYMENT" = "personal" ] && [ "$CURRENT_POC_MODE" = "private_poc" ]; then
    print_warn "Project is already a Private POC. Nothing to do."
    exit 0
  fi
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ "$CURRENT_POC_MODE" = "private_poc" ]; then
    # Legacy projects produced by the pre-fix --to-private-poc may exist
    # in this impossible shape; treat as already-POC and warn.
    print_warn "Project records an organizational/private_poc shape (pre-fix legacy). Treating as already a Private POC. Nothing to do."
    exit 0
  fi
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ "$CURRENT_POC_MODE" = "sponsored_poc" ]; then
    print_fail "Cannot downgrade Sponsored POC to Private POC. POC modes only progress upward."
    exit 1
  fi
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ -z "$CURRENT_POC_MODE" ]; then
    print_fail "Project is already organizational/production. Cannot downgrade to Private POC."
    exit 1
  fi
  TARGET_DEPLOYMENT="personal"
  # Track stays the same for POC transition
  if [ -z "$TARGET_TRACK" ]; then
    TARGET_TRACK="$CURRENT_TRACK"
  fi
fi

# Use current values if not specified
if [ -z "$TARGET_TRACK" ]; then
  TARGET_TRACK="$CURRENT_TRACK"
fi
if [ -z "$TARGET_DEPLOYMENT" ]; then
  TARGET_DEPLOYMENT="$CURRENT_DEPLOYMENT"
fi

# ================================================================
# Validate the upgrade
# ================================================================
print_step "Validating upgrade"

# Validate target track
if ! echo "$VALID_TRACKS" | grep -qw "$TARGET_TRACK"; then
  print_fail "Invalid target track: $TARGET_TRACK (must be: light, standard, full)"
  exit 1
fi

# Validate target deployment
if ! echo "$VALID_DEPLOYMENTS" | grep -qw "$TARGET_DEPLOYMENT"; then
  print_fail "Invalid target deployment: $TARGET_DEPLOYMENT (must be: personal, organizational)"
  exit 1
fi

# Cannot downgrade track
CURRENT_RANK=$(track_rank "$CURRENT_TRACK")
TARGET_RANK=$(track_rank "$TARGET_TRACK")
if [ "$TARGET_RANK" -lt "$CURRENT_RANK" ]; then
  print_fail "Cannot downgrade track from $CURRENT_TRACK to $TARGET_TRACK."
  exit 1
fi

# Cannot downgrade deployment
if [ "$CURRENT_DEPLOYMENT" = "organizational" ] && [ "$TARGET_DEPLOYMENT" = "personal" ]; then
  print_fail "Cannot downgrade deployment from organizational to personal."
  exit 1
fi

# Cannot go from production to POC. Both branches must include the
# deployment guard — without it, personal projects (poc_mode is always null
# when deployment=personal) are wrongly classified as production. The
# --to-private-poc branch was fixed in PR #24 (T1-D); R3-A applies the same
# deployment check to --to-sponsored-poc.
if [ -z "$CURRENT_POC_MODE" ] && [ "$TO_SPONSORED_POC" = true ] && [ "$CURRENT_DEPLOYMENT" = "organizational" ]; then
  print_fail "Cannot downgrade a production project to POC mode."
  exit 1
fi
if [ -z "$CURRENT_POC_MODE" ] && [ "$TO_PRIVATE_POC" = true ] && [ "$CURRENT_DEPLOYMENT" = "organizational" ]; then
  print_fail "Cannot downgrade a production project to POC mode."
  exit 1
fi

# Determine what changes
TRACK_CHANGES=false
DEPLOYMENT_CHANGES=false
POC_REMOVED=false
POC_TO_SPONSORED=false
POC_TO_PRIVATE=false

if [ "$TARGET_TRACK" != "$CURRENT_TRACK" ]; then
  TRACK_CHANGES=true
fi

if [ "$TARGET_DEPLOYMENT" != "$CURRENT_DEPLOYMENT" ]; then
  DEPLOYMENT_CHANGES=true
fi

# tier-crosscheck-6 (final S3 audit finding): personal→organizational
# deployment changes Phase 1→2 from a self-attested invariant into one
# under STA governance, including the Mandatory ZDR gate
# (docs/governance-framework.md § VII line 299). If the project's
# .claude/process-state.json::phase1_artifacts has no data_classification,
# this upgrade leaves an unenforceable promise behind: check-phase-gate.sh
# will FAIL Phase 1→2 backstop until the operator runs reconfigure-
# project.sh. Refuse the upgrade upfront with a clear pointer.
#
# Behavior contract:
#   * Non-interactive (CI=true / SOIF_NONINTERACTIVE=1 / no TTY) →
#     hard refuse with the remediation command.
#   * Interactive → also refuse for now; the wizard-driven prompt path
#     lives in scripts/intake-wizard.sh. Interactive operators are
#     redirected there. (A later release may add an in-place prompt
#     here once the lib/helpers.sh prompt_choice helper is wired
#     through this script's flag-parsing layer — out of scope for the
#     hard-block PR.)
if [ "$DEPLOYMENT_CHANGES" = true ] && \
   [ "$CURRENT_DEPLOYMENT" = "personal" ] && \
   [ "$TARGET_DEPLOYMENT" = "organizational" ]; then
  _zdr_pstate="$PROJECT_ROOT/.claude/process-state.json"
  _zdr_classification=""
  if [ -f "$_zdr_pstate" ] && command -v jq >/dev/null 2>&1; then
    _zdr_classification=$(jq -r '.phase1_artifacts.data_classification // ""' "$_zdr_pstate" 2>/dev/null || echo "")
    [ "$_zdr_classification" = "null" ] && _zdr_classification=""
  fi
  if [ -z "$_zdr_classification" ]; then
    _upgrade_fail "--deployment organizational blocked — data_classification not set (tier-crosscheck-6)" \
                  "Personal→Organizational upgrade activates the Phase 1→2 ZDR gate (docs/governance-framework.md § VII line 299). The project's $_zdr_pstate has no phase1_artifacts.data_classification, so check-phase-gate.sh would FAIL Phase 1→2 backstop immediately after this upgrade." \
                  "set data_classification BEFORE upgrading, e.g.: bash scripts/reconfigure-project.sh --field data_classification --new <public|internal|confidential|pii|financial|health|regulated>. Then set the ZDR attestation: bash scripts/reconfigure-project.sh --field zdr_attested --new true. Then re-run this upgrade." \
                  "deployment_change=personal->organizational; classification=(unset); pstate=$_zdr_pstate"
    exit 1
  fi
fi

# code-upgrade-project-8: Pre-Phase-0 pre-condition gate for --to-production.
# Per docs/governance-framework.md:230, Sponsored POC defers 3 of the 6
# governance pre-conditions (insurance, liability, ITSM, backup
# maintainer), Private POC defers all 6, and Production requires every
# row cleared. Before this gate the script silently flipped POC_REMOVED
# regardless of whether APPROVAL_LOG.md reflected the deferred work
# being closed out — a fictional governance check the doc promised but
# the code never enforced. Skipped for personal deployments because
# templates/generated/approval-log-personal.tmpl pre-fills all 6 rows
# with __TODAY__ at init time (auto-satisfied).
if [ "$TO_PRODUCTION" = true ] && [ -n "$CURRENT_POC_MODE" ]; then
  if [ "$CURRENT_DEPLOYMENT" = "organizational" ]; then
    # Canonical Pre-Phase-0 row labels — matches
    # templates/generated/approval-log-org.tmpl:22-27.
    _gov_labels=(
      "AI deployment path approved"
      "Insurance coverage confirmed"
      "Liability entity designated"
      "Project sponsor assigned"
      "Backup maintainer designated"
      "ITSM project registered"
    )
    # Parse acked-rows into a lookup string ",1,2,3,".
    _ack_lookup=""
    if [ -n "$ACK_PRECONDITIONS" ]; then
      _ack_lookup=",$ACK_PRECONDITIONS,"
    fi
    # Walk rows 1-6, mark each as dated / acked / missing.
    _missing_rows=""
    _missing_labels=""
    for _n in 1 2 3 4 5 6; do
      _dated=false
      if [ -f "$APPROVAL_LOG" ]; then
        # Extract the row matching `| N |` from the Pre-Phase 0 section
        # and check the Date column (5th pipe-separated field for org
        # template: # | Pre-Condition | Approver | Role | Date | ...).
        # Sanitized per PR #53 (code-check-gates-4) — a missing match
        # was previously yielding "0\n0" through `|| echo 0`.
        _date_field=$(awk -v rownum="$_n" '
          /^## Pre-Phase 0/ { in_section = 1; next }
          in_section && /^## / { in_section = 0 }
          in_section && $0 ~ "^\\| *" rownum " *\\|" {
            # Split on |, trim, return the Date column (field 6 of awk
            # split because leading empty field before first |).
            n = split($0, parts, "|")
            if (n >= 6) {
              gsub(/^[ \t]+|[ \t]+$/, "", parts[6])
              print parts[6]
              exit
            }
          }
        ' "$APPROVAL_LOG" 2>/dev/null || true)
        if echo "$_date_field" | grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; then
          _dated=true
        fi
      fi
      # Ack overrides only if not already dated.
      _acked=false
      if [ "$_dated" = false ] && [ -n "$_ack_lookup" ] && echo "$_ack_lookup" | grep -q ",$_n,"; then
        _acked=true
      fi
      if [ "$_dated" = false ] && [ "$_acked" = false ]; then
        _missing_rows="${_missing_rows}${_missing_rows:+,}$_n"
        _idx=$((_n - 1))
        _missing_labels="${_missing_labels}${_missing_labels:+; }$_n=${_gov_labels[$_idx]}"
      fi
    done

    if [ -n "$_missing_rows" ]; then
      _upgrade_fail "--to-production blocked — Pre-Phase-0 pre-conditions not cleared" \
                    "APPROVAL_LOG.md rows [$_missing_rows] lack a dated approval (and were not acknowledged via --ack-preconditions). Per docs/governance-framework.md §V Production requires all 6 pre-conditions cleared; Sponsored POC requires rows 1,4 (AI deployment path, sponsor) upfront and defers rows 2,3,5,6 (insurance, liability, backup, ITSM); Private POC defers all 6. Deferred rows must be cleared before --to-production." \
                    "fill in the Date column for the missing rows in APPROVAL_LOG.md (see Pre-Phase 0 section), OR re-run with --non-interactive --ack-preconditions=<N1,N2,...> after recording the equivalent approvals out-of-band." \
                    "missing_rows=[$_missing_rows]; missing_labels=[$_missing_labels]; approval_log=$APPROVAL_LOG"
      exit 1
    fi

    # Audit the ack-bypass when it was actually used.
    if [ -n "$ACK_PRECONDITIONS" ]; then
      mkdir -p "$PROJECT_ROOT/.claude"
      [ -f "$PROJECT_ROOT/.claude/bypass-audit.json" ] || echo "[]" > "$PROJECT_ROOT/.claude/bypass-audit.json"
      _ack_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      _ack_rows_json=$(echo "$ACK_PRECONDITIONS" | jq -Rc 'split(",") | map(tonumber)')
      _ack_row=$(jq -nc \
        --arg ts "$_ack_ts" \
        --argjson rows "$_ack_rows_json" \
        --arg poc "$CURRENT_POC_MODE" \
        '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"user_terminal",
          enforcement_level_at_event:"strict",
          details:{action:"to_production_preconditions_acked", rows:$rows, from_poc_mode:$poc, source:"upgrade-project.sh"},
          user_response:"accepted", final_outcome:"bypassed"}')
      _ack_tmp=$(mktemp)
      jq --argjson r "$_ack_row" '. + [$r]' "$PROJECT_ROOT/.claude/bypass-audit.json" > "$_ack_tmp" \
        && mv "$_ack_tmp" "$PROJECT_ROOT/.claude/bypass-audit.json"
    fi
  fi
  POC_REMOVED=true
fi

if [ "$TO_SPONSORED_POC" = true ] && [ "$CURRENT_POC_MODE" != "sponsored_poc" ]; then
  POC_TO_SPONSORED=true
fi

if [ "$TO_PRIVATE_POC" = true ] && [ "$CURRENT_POC_MODE" != "private_poc" ]; then
  POC_TO_PRIVATE=true
fi

# Check if anything actually changes
if [ "$TRACK_CHANGES" = false ] && [ "$DEPLOYMENT_CHANGES" = false ] && \
   [ "$POC_REMOVED" = false ] && [ "$POC_TO_SPONSORED" = false ] && \
   [ "$POC_TO_PRIVATE" = false ]; then
  print_warn "No changes needed — project is already at $CURRENT_TRACK/$CURRENT_DEPLOYMENT."
  exit 0
fi

print_ok "Upgrade is valid"
echo ""

# ================================================================
# Show what will change
# ================================================================
print_step "Upgrade plan"
echo ""
echo -e "  ${BOLD}Project:${NC}    $PROJECT_NAME"
echo ""

if [ "$TRACK_CHANGES" = true ]; then
  echo -e "  ${BOLD}Track:${NC}      $CURRENT_TRACK -> ${GREEN}$TARGET_TRACK${NC}"
fi
if [ "$DEPLOYMENT_CHANGES" = true ]; then
  echo -e "  ${BOLD}Deployment:${NC} $CURRENT_DEPLOYMENT -> ${GREEN}$TARGET_DEPLOYMENT${NC}"
fi
if [ "$POC_REMOVED" = true ]; then
  echo -e "  ${BOLD}POC Mode:${NC}   ${CURRENT_POC_MODE//_/ } -> ${GREEN}Production${NC}"
fi
if [ "$POC_TO_SPONSORED" = true ]; then
  echo -e "  ${BOLD}POC Mode:${NC}   ${CURRENT_POC_MODE:-private poc} -> ${GREEN}Sponsored POC${NC}"
fi
if [ "$POC_TO_PRIVATE" = true ]; then
  echo -e "  ${BOLD}POC Mode:${NC}   ${CURRENT_POC_MODE:-none} -> ${GREEN}Private POC${NC}"
fi

echo ""
echo -e "  ${BOLD}Files that will be updated:${NC}"
echo "    - .claude/phase-state.json"
if [ -f "$TOOL_PREFS" ]; then
  echo "    - .claude/tool-preferences.json"
fi
if [ -f "$CLAUDE_MD" ]; then
  echo "    - CLAUDE.md"
fi
if [ -f "$INTAKE_MD" ]; then
  echo "    - PROJECT_INTAKE.md"
fi
if [ "$DEPLOYMENT_CHANGES" = true ] && [ -f "$APPROVAL_LOG" ]; then
  echo "    - APPROVAL_LOG.md (restructured for organizational governance)"
fi
if [ -f "$INTAKE_PROGRESS" ]; then
  echo "    - .claude/intake-progress.json"
fi
echo ""

# --- Interactive confirmation ---
# Wave-3 raw-read sweep: prompt_yes_no honors !-t 0 / CI /
# SOIF_NONINTERACTIVE. The interactive default here is Y (the upgrade
# wizard pre-printed the change plan and the operator typing Enter
# means "yes proceed"), but in non-interactive contexts prompt_yes_no
# hard-returns N — so the else-branch's "Non-interactive mode —
# proceeding with upgrade." auto-Y is preserved explicitly here for
# CI/scripted callers who already accepted the change plan upstream
# (e.g. spec-driven upgrades, replay UAT).
if [ -t 0 ]; then
  if ! prompt_yes_no "$(echo -e "  ${BOLD}Proceed with this upgrade? [Y/n]${NC}")" "Y"; then
    print_info "Upgrade cancelled."
    exit 0
  fi
  echo ""
else
  print_info "Non-interactive mode — proceeding with upgrade."
  echo ""
fi

# ================================================================
# Atomic mutation block: snapshot → mutate → commit OR rollback
# ================================================================
# Audit code-upgrade-project-5: the 6 python3 heredocs below and the
# final `git commit` form a non-atomic mutation that touches 7 files.
# Pre-fix, ANY mid-run interruption (SIGINT, python3 KeyError, git
# commit failure) could leave the project half-mutated. The next run
# would re-read the partially-written phase-state.json and compute
# DEPLOYMENT_CHANGES=false, silently skipping the CLAUDE.md governance
# section and APPROVAL_LOG.md restructure — operator stuck with stale
# CLAUDE.md and forced to hand-edit phase-state.json to recover.
#
# Audit baseline §5.22 mandates "non-destructive of technical work."
#
# Fix mirrors the proven sibling pattern in scripts/reconfigure-
# project.sh:82-183 (PR #57, 8 weeks in production, no regressions):
#   1. Snapshot every potentially-mutated file into
#      .claude/upgrade-snapshots/<UTC-timestamp>/ before any write.
#   2. Install `trap _upgrade_rollback INT TERM ERR` so SIGINT, kill,
#      `set -e` ERR, or an explicit rollback call all restore state.
#   3. Clear the trap only after `git commit` succeeds.
#   4. Keep-3 retention on snapshot dirs — preserves forensic history
#      without unbounded growth.
SNAPSHOT_ROOT="$PROJECT_ROOT/.claude/upgrade-snapshots"
_upgrade_snapshot_dir=""
# Files this script may mutate. Order matches the heredoc sequence
# below; only files present at snapshot time are saved (and only those
# are restored on rollback — no spurious empty files).
_UPGRADE_MUTATED_FILES=(
  "$TOOL_PREFS"
  "$PHASE_STATE"
  "$INTAKE_PROGRESS"
  "$CLAUDE_MD"
  "$INTAKE_MD"
  "$APPROVAL_LOG"
  "$PROJECT_ROOT/PRODUCT_MANIFESTO.md"
  "$MANIFEST_JSON"
)

_upgrade_snapshot_pre_mutation() {
  mkdir -p "$SNAPSHOT_ROOT"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
  # Append a millisecond / pid suffix so two upgrades inside the same
  # wall-clock second still get distinct dirs (race-safe under test
  # harness churn and Karl's keep-3 retention assertion).
  _upgrade_snapshot_dir="$SNAPSHOT_ROOT/$ts-$$"
  local n=0
  while [ -e "$_upgrade_snapshot_dir" ]; do
    n=$((n + 1))
    _upgrade_snapshot_dir="$SNAPSHOT_ROOT/$ts-$$-$n"
  done
  mkdir -p "$_upgrade_snapshot_dir"
  local f
  for f in "${_UPGRADE_MUTATED_FILES[@]}"; do
    if [ -f "$f" ]; then
      # Preserve path under PROJECT_ROOT so restore is unambiguous.
      local rel="${f#$PROJECT_ROOT/}"
      mkdir -p "$_upgrade_snapshot_dir/$(dirname "$rel")"
      cp "$f" "$_upgrade_snapshot_dir/$rel"
    fi
  done
  print_info "Pre-mutation snapshot: $_upgrade_snapshot_dir"
}

_upgrade_rollback() {
  # Sourced from the trap (INT/TERM/ERR) and from explicit commit-fail
  # paths. Safe to call multiple times — second call is a no-op if the
  # snapshot dir has been cleaned up.
  trap - INT TERM ERR
  if [ -z "$_upgrade_snapshot_dir" ] || [ ! -d "$_upgrade_snapshot_dir" ]; then
    return 0
  fi
  echo "" >&2
  print_warn "Upgrade interrupted — rolling back to pre-mutation snapshot."
  local f rel
  for f in "${_UPGRADE_MUTATED_FILES[@]}"; do
    rel="${f#$PROJECT_ROOT/}"
    if [ -f "$_upgrade_snapshot_dir/$rel" ]; then
      cp "$_upgrade_snapshot_dir/$rel" "$f"
    fi
  done
  print_info "Snapshot retained for forensics: $_upgrade_snapshot_dir"
  print_info "Inspect with: ls -la $_upgrade_snapshot_dir"
  exit 1
}

_upgrade_prune_snapshots() {
  # Keep-3 retention. Run after successful commit so forensic history
  # of recent failures isn't accidentally pruned mid-failure path.
  [ -d "$SNAPSHOT_ROOT" ] || return 0
  # macOS find doesn't ship `-printf`; use stat for mtime sort. Bash 3.2
  # compatible — no associative arrays.
  local dirs
  dirs=$(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | while IFS= read -r d; do
        # POSIX-portable stat: try GNU form, fall back to BSD.
        m=$(stat -c '%Y' "$d" 2>/dev/null || stat -f '%m' "$d" 2>/dev/null || echo 0)
        printf '%s\t%s\n' "$m" "$d"
      done \
    | sort -n)
  local count
  count=$(printf '%s\n' "$dirs" | grep -c .)
  if [ "$count" -le 3 ]; then
    return 0
  fi
  local to_drop=$((count - 3))
  printf '%s\n' "$dirs" | head -n "$to_drop" | cut -f2- | while IFS= read -r d; do
    [ -n "$d" ] && rm -rf "$d"
  done
}

_upgrade_snapshot_pre_mutation
trap _upgrade_rollback INT TERM ERR

# ================================================================
# 1. Update .claude/tool-preferences.json
# ================================================================
if [ -f "$TOOL_PREFS" ]; then
  print_step "Updating .claude/tool-preferences.json"

  python3 << 'PYEOF' - "$TOOL_PREFS" "$TARGET_TRACK" "$TARGET_DEPLOYMENT"
import json, sys
from datetime import date

tool_prefs_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]

with open(tool_prefs_path) as f:
    data = json.load(f)

if "context" not in data:
    data["context"] = {}

data["context"]["track"] = new_track
data["resolved_at"] = str(date.today())

with open(tool_prefs_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF

  print_ok "Updated track to $TARGET_TRACK in tool-preferences.json"
fi

# ================================================================
# 2. Update .claude/phase-state.json
# ================================================================
print_step "Updating .claude/phase-state.json"

# phase-state.json doesn't have a track field by default, but we add one
# for upgrade tracking. We also preserve existing gates.
python3 << 'PYEOF' - "$PHASE_STATE" "$TARGET_TRACK" "$POC_REMOVED" "$POC_TO_SPONSORED" "$POC_TO_PRIVATE" "$TARGET_DEPLOYMENT"
import json, sys
from datetime import date

phase_state_path = sys.argv[1]
new_track = sys.argv[2]
poc_removed = sys.argv[3] == "true"
poc_to_sponsored = sys.argv[4] == "true"
poc_to_private = sys.argv[5] == "true"
new_deployment = sys.argv[6]

with open(phase_state_path) as f:
    data = json.load(f)

data["track"] = new_track
# UAT 2026-04-26 fix (U-J / T2-G): write the resolved deployment field on
# every upgrade. Previously this heredoc only wrote .track, leaving
# .deployment in phase-state.json out of sync with the upgrade banner and
# with PROJECT_INTAKE.md / CLAUDE.md (which the later heredocs do update).
data["deployment"] = new_deployment
data["last_upgrade"] = str(date.today())

if poc_removed:
    if "poc_mode" in data:
        del data["poc_mode"]
elif poc_to_sponsored:
    data["poc_mode"] = "sponsored_poc"
elif poc_to_private:
    data["poc_mode"] = "private_poc"

with open(phase_state_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF

print_ok "Updated phase-state.json"

# ================================================================
# 2b. Update .claude/manifest.json (BL-061)
# ================================================================
# BL-061 (adversarial cert pass S-4, 2026-06-29): pre-fix upgrade-project.sh
# refreshed phase-state.json but left manifest.json's snapshot of
# deployment / poc_mode pointing at the pre-upgrade tier. That two-source
# split encouraged bugs where a downstream reader consulted manifest.json
# and gated the wrong tier (e.g., check-phase-gate.sh's Phase 1→2 backstop
# reads manifest.json::mode; scripts/escalate-to-user.sh reads
# manifest.json::enforcement_level whose meaning depends on deployment).
# Refresh manifest.json inside the same atomic block so both files always
# tell the same story after a commit.
#
# Scope: deployment + poc_mode. These are the two tier-tracked fields the
# BL-030 backfill wrote (see upgrade-project.sh:310-320). Track, host, mode,
# remote_url, enforcement_level, frameworkCommit, and frameworkVersion are
# NOT touched here — their owners are init.sh, reconfigure-project.sh, and
# the CDF installer, and refreshing them from upgrade-project.sh would
# either be a no-op (host/remote_url) or wrong (enforcement_level, which
# reconfigure-project.sh owns).
#
# Atomicity: MANIFEST_JSON was added to _UPGRADE_MUTATED_FILES so the
# pre-mutation snapshot captures it and the ERR/INT/TERM trap rolls it
# back alongside phase-state.json on any interruption.
if [ -f "$MANIFEST_JSON" ]; then
  print_step "Refreshing .claude/manifest.json (deployment, poc_mode) — BL-061"

  # Encode the resolved POC mode as JSON: `null` when we're removing it,
  # otherwise the string literal ("private_poc" / "sponsored_poc"). This
  # mirrors the phase-state.json write above and matches init.sh:1780-1794.
  if [ "$POC_REMOVED" = true ]; then
    _mf_poc_arg="null"
  elif [ "$POC_TO_SPONSORED" = true ]; then
    _mf_poc_arg='"sponsored_poc"'
  elif [ "$POC_TO_PRIVATE" = true ]; then
    _mf_poc_arg='"private_poc"'
  elif [ -n "$CURRENT_POC_MODE" ]; then
    _mf_poc_arg="\"$CURRENT_POC_MODE\""
  else
    _mf_poc_arg="null"
  fi

  _mf_tmp="$(mktemp)"
  # jq --argjson keeps the null-vs-string distinction; --arg would stringify
  # null to "null" which would poison downstream readers.
  jq --arg dep "$TARGET_DEPLOYMENT" \
     --argjson pm "$_mf_poc_arg" \
     '. + {deployment: $dep, poc_mode: $pm}' \
     "$MANIFEST_JSON" > "$_mf_tmp" \
    && mv "$_mf_tmp" "$MANIFEST_JSON"
  rm -f "$_mf_tmp"

  print_ok "Updated manifest.json (deployment=$TARGET_DEPLOYMENT poc_mode=$_mf_poc_arg)"
fi

# ================================================================
# 3. Update .claude/intake-progress.json (if exists)
# ================================================================
if [ -f "$INTAKE_PROGRESS" ]; then
  print_step "Updating .claude/intake-progress.json"

  python3 << 'PYEOF' - "$INTAKE_PROGRESS" "$TARGET_TRACK" "$TARGET_DEPLOYMENT" "$POC_REMOVED" "$POC_TO_SPONSORED" "$POC_TO_PRIVATE"
import json, sys

progress_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]
poc_removed = sys.argv[4] == "true"
poc_to_sponsored = sys.argv[5] == "true"
poc_to_private = sys.argv[6] == "true"

with open(progress_path) as f:
    data = json.load(f)

data["track"] = new_track
data["deployment"] = new_deployment

if poc_removed:
    data["poc_mode"] = None
elif poc_to_sponsored:
    data["poc_mode"] = "sponsored_poc"
elif poc_to_private:
    data["poc_mode"] = "private_poc"

with open(progress_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF

  print_ok "Updated intake-progress.json"
fi

# ================================================================
# 4. Update CLAUDE.md
# ================================================================
if [ -f "$CLAUDE_MD" ]; then
  print_step "Updating CLAUDE.md"

  python3 << 'PYEOF' - "$CLAUDE_MD" "$TARGET_TRACK" "$TARGET_DEPLOYMENT" "$CURRENT_TRACK" "$CURRENT_DEPLOYMENT" "$POC_REMOVED" "$DEPLOYMENT_CHANGES" "$POC_TO_SPONSORED" "$POC_TO_PRIVATE"
import re, sys

claude_md_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]
old_track = sys.argv[4]
old_deployment = sys.argv[5]
poc_removed = sys.argv[6] == "true"
deployment_changes = sys.argv[7] == "true"
poc_to_sponsored = sys.argv[8] == "true"
poc_to_private = sys.argv[9] == "true"

with open(claude_md_path) as f:
    content = f.read()

# Update track in Project Identity section
content = re.sub(
    r'(\*\*Track:\*\*\s*).*',
    r'\g<1>' + new_track.capitalize(),
    content
)

# Remove POC watermarks if upgrading to production
if poc_removed:
    # Remove lines containing POC constraint warnings
    lines = content.split('\n')
    filtered = []
    skip_block = False
    for line in lines:
        # Skip POC-specific warning blocks. Audit code-upgrade-project-4
        # (2026-06): the regex must NOT match identifiers like
        # POC_MODE_FOO (word boundary required), AND skip_block must
        # terminate not only on blank lines but also on a markdown
        # heading or list-item line — otherwise a mid-paragraph "POC
        # mode" / "POC constraints" mention inside a numbered list or
        # right before a heading silently swallows the trailing items /
        # the heading + body. Operator-customized CLAUDE.md only;
        # default templates have no POC prose, so this is a real bug
        # with a narrow but data-loss blast radius.
        if re.search(r'POC (mode|constraints)\b', line, re.IGNORECASE):
            skip_block = True
            continue
        if skip_block and (
            line.strip() == ''
            or line.lstrip().startswith('#')
            or re.match(r'^\s*[-*+]\s|^\s*\d+\.\s', line)
        ):
            skip_block = False
            # fall through — preserve the terminator line (heading or
            # list item); only blank lines are dropped (continue below).
            if line.strip() == '':
                continue
        elif skip_block:
            continue
        # Remove individual POC watermark lines
        if re.search(r'no production deployment.*no real user data.*no external users', line, re.IGNORECASE):
            continue
        if re.search(r'upgrade.*--upgrade-to-production', line, re.IGNORECASE):
            continue
        if re.search(r'upgrade.*--to-production', line, re.IGNORECASE):
            continue
        filtered.append(line)
    content = '\n'.join(filtered)

# Update POC watermarks for sponsored POC upgrade
if poc_to_sponsored:
    content = re.sub(r'Private POC', 'Sponsored POC', content)
    content = re.sub(r'private_poc', 'sponsored_poc', content)
    content = re.sub(r'private poc', 'Sponsored POC', content, flags=re.IGNORECASE)

# (POC watermarks for private POC upgrade are added by the governance section
#  block below when deployment_changes is true; no template-text rewrite is
#  needed for personal -> private_poc since the source had no POC mention.)

# Update Deployment field if deployment changed
if deployment_changes:
    content = re.sub(
        r'(\*\*Deployment:\*\*\s*).*',
        r'\g<1>' + new_deployment.capitalize(),
        content
    )

# Add governance instructions if moving to organizational
if deployment_changes and new_deployment == "organizational":
    governance_section = """
### Organizational Governance
- This is an organizational deployment. All phase gates require formal approval from designated authorities.
- Pre-Phase 0 organizational pre-conditions must be tracked in APPROVAL_LOG.md.
- For organizational deployments, verify pre-Phase 0 pre-conditions are recorded before starting Phase 0.
- Phase gate approvals require: approver name, role, date, method, and evidence reference.
- The Approval Log is append-only — do not modify previous entries.
"""
    # Insert before "### When to Ask" if it exists, otherwise append
    if '### When to Ask' in content:
        content = content.replace('### When to Ask', governance_section + '\n### When to Ask')
    else:
        content += '\n' + governance_section

with open(claude_md_path, 'w') as f:
    f.write(content)
PYEOF

  print_ok "Updated CLAUDE.md"
fi

# ================================================================
# 5. Update PROJECT_INTAKE.md
# ================================================================
if [ -f "$INTAKE_MD" ]; then
  print_step "Updating PROJECT_INTAKE.md"

  python3 << 'PYEOF' - "$INTAKE_MD" "$TARGET_TRACK" "$TARGET_DEPLOYMENT" "$CURRENT_TRACK" "$CURRENT_DEPLOYMENT" "$POC_REMOVED" "$POC_TO_SPONSORED" "$DEPLOYMENT_CHANGES" "$POC_TO_PRIVATE"
import re, sys
from datetime import date

intake_path = sys.argv[1]
new_track = sys.argv[2]
new_deployment = sys.argv[3]
old_track = sys.argv[4]
old_deployment = sys.argv[5]
poc_removed = sys.argv[6] == "true"
poc_to_sponsored = sys.argv[7] == "true"
deployment_changes = sys.argv[8] == "true"
poc_to_private = sys.argv[9] == "true"

with open(intake_path) as f:
    content = f.read()

# Update project track field
# Match patterns like "| **Project track** | Light |" or "| **Project track** | light |"
content = re.sub(
    r'(\|\s*\*\*Project track\*\*\s*\|)\s*[^|]+\|',
    r'\1 ' + new_track.capitalize() + ' |',
    content
)

# Update deployment field
# Match "| **Is this a personal project or organizational deployment?** | Personal |"
if deployment_changes:
    content = re.sub(
        r'(\|\s*\*\*Is this a personal project or organizational deployment\?\*\*\s*\|)\s*[^|]+\|',
        r'\1 ' + new_deployment.capitalize() + ' |',
        content
    )

# Update governance mode if POC is removed
if poc_removed:
    content = re.sub(
        r'(\*\*Governance Mode:\*\*)\s*.*',
        r'\1 Production',
        content
    )
    # Remove POC constraint callout
    content = re.sub(
        r'>\s*\*\*If POC mode:\*\*.*\n',
        '',
        content
    )
elif poc_to_sponsored:
    content = re.sub(
        r'(\*\*Governance Mode:\*\*)\s*.*',
        r'\1 Sponsored POC',
        content
    )
elif poc_to_private:
    content = re.sub(
        r'(\*\*Governance Mode:\*\*)\s*.*',
        r'\1 Private POC',
        content
    )

# Add governance section placeholder if moving to organizational and section 8 doesn't exist
if deployment_changes and new_deployment == "organizational":
    if '## 8. Governance Pre-Flight' not in content:
        governance_placeholder = """
---

## 8. Governance Pre-Flight (Organizational Deployments Only)

_Added during upgrade from personal to organizational deployment on """ + str(date.today()) + """._

**Governance Mode:** """ + ("Production" if poc_removed else ("Sponsored POC" if poc_to_sponsored else ("Private POC" if poc_to_private else "Production"))) + """

### 8.1 Pre-Conditions

| Pre-Condition | Status | Details | Blocking? |
|---|---|---|---|
| **AI deployment path approved by IT Security** | Not Started | | Yes |
| **Insurance confirmation obtained** | Not Started | | Yes |
| **Liability entity designated** | Not Started | | Yes |
| **Project sponsor assigned** | Not Started | | Yes |
| **Backup maintainer designated** | Not Started | | Yes |
| **ITSM ticket filed / portfolio registered** | Not Started | | Yes |
| **Exit criteria defined** | Not Started | | Yes |
| **Orchestrator time allocation approved** | Not Started | | Yes |

### 8.2 Approval Authorities

| Gate | Approver Name | Approver Role |
|---|---|---|
| **Phase 0 -> Phase 1** (business justification) | | |
| **Phase 1 -> Phase 2** (architecture approval) | | |
| **Phase 3 -> Phase 4** (go-live approval) | | |

### 8.3 Escalation Chain

| Level | Contact |
|---|---|
| **Level 1** | |
| **Level 2** | |
| **Level 3 (final authority)** | |

### 8.4 Compliance Screening

| Question | Answer |
|---|---|
| SOX-regulated financial data? | No |
| Payment card data (PCI)? | No |
| Personal data across multiple states/countries? | No |
| EU users or EU subsidiaries? | No |
| OFAC-sanctioned jurisdictions? | No |
| Records retention requirements? | No |
| AI for end-user-facing features? | No |
| Penetration testing required? | No |

### 8.5 Exit Criteria

| Field | Value |
|---|---|
| **Success definition** | |
| **Conditional success** | |
| **Failure definition** | |
"""
        # Try to insert before section 9 or at the end
        if '## 9.' in content:
            content = content.replace('## 9.', governance_placeholder + '\n## 9.')
        elif '## 10.' in content:
            content = content.replace('## 10.', governance_placeholder + '\n## 10.')
        else:
            content += governance_placeholder

# Add upgrade audit trail at the bottom
today = str(date.today())
changes = []
if old_track != new_track:
    changes.append(f"track {old_track} -> {new_track}")
if old_deployment != new_deployment:
    changes.append(f"deployment {old_deployment} -> {new_deployment}")
if poc_removed:
    changes.append("POC mode removed (production)")
if poc_to_sponsored:
    changes.append("upgraded to sponsored POC")

if changes:
    audit_line = f"\n> **Upgrade ({today}):** {', '.join(changes)}. Applied by `scripts/upgrade-project.sh`.\n"
    # Insert after the Document Control section or at the top
    if '## Purpose' in content:
        content = content.replace('## Purpose', audit_line + '\n## Purpose')
    else:
        content = audit_line + content

with open(intake_path, 'w') as f:
    f.write(content)
PYEOF

  print_ok "Updated PROJECT_INTAKE.md"
fi

# ================================================================
# 6. Update APPROVAL_LOG.md
# ================================================================
if [ "$DEPLOYMENT_CHANGES" = true ] && [ "$TARGET_DEPLOYMENT" = "organizational" ]; then
  print_step "Updating APPROVAL_LOG.md for organizational governance"

  if [ -f "$APPROVAL_LOG" ]; then
    # Check if it's currently a personal-format log
    if grep -q 'deployment: personal' "$APPROVAL_LOG" 2>/dev/null; then
      # Back up the personal log
      cp "$APPROVAL_LOG" "${APPROVAL_LOG}.personal-backup"
      print_info "Personal approval log backed up to APPROVAL_LOG.md.personal-backup"

      python3 << 'PYEOF' - "$APPROVAL_LOG" "$PROJECT_NAME"
import re, sys
from datetime import date

log_path = sys.argv[1]
project_name = sys.argv[2]
today = str(date.today())

with open(log_path) as f:
    old_content = f.read()

# Extract any existing gate entries with dates from the personal log
existing_gates = {}
# Look for Phase X -> Phase Y sections with filled-in dates
for match in re.finditer(r'Phase (\d).*Phase (\d).*?\n.*?\*\*(?:Reviewer|Date)\*\*\s*\|\s*(.+?)(?:\s*\||\s*$)', old_content, re.MULTILINE):
    gate_key = f"phase_{match.group(1)}_to_{match.group(2)}"
    value = match.group(3).strip()
    if value and value != '|':
        existing_gates[gate_key] = value

new_content = f"""---
project: {project_name}
deployment: organizational
created: {today}
upgraded_from: personal
framework: Solo Orchestrator v1.0
---

# Approval Log — {project_name}

This document records all governance approvals for this project. Each entry captures who approved what, when, and what evidence supports the approval. This is the auditable governance trail required by the Solo Orchestrator Enterprise Governance Framework (SOI-003-GOV, Section V).

**Instructions:** Update this log at each phase gate transition. Every approval entry must include the approver's name, role, date, method of approval, and a reference to the evidence. Do not delete or modify previous entries — append only. Git history provides tamper evidence.

> **Note:** This project was upgraded from personal to organizational deployment on {today}. Previous personal approval history is preserved in APPROVAL_LOG.md.personal-backup and in git history.

---

## Pre-Phase 0: Organizational Pre-Conditions

These pre-conditions must be completed before Phase 0 begins. See Governance Framework Section V and Project Intake Section 8.

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
| 1 | AI deployment path approved | | IT Security | | Email / Ticket / Document | | |
| 2 | Insurance coverage confirmed | | Insurance Broker | | Email / Ticket / Document | | |
| 3 | Liability entity designated | | Legal / CIO | | Email / Ticket / Document | | |
| 4 | Project sponsor assigned | | Executive Sponsor | | Email / Ticket / Document | | |
| 5 | Backup maintainer designated | | Technical Lead | | Email / Ticket / Document | | |
| 6 | ITSM project registered | | ITSM / PMO | | Email / Ticket / Document | | |

---

## Phase Gate: Phase 0 → Phase 1

**Gate requirement:** Project Sponsor approves business justification and compliance screening.
**Evidence required:** Signed-off Phase 0 artifacts + compliance screening matrix.
**Reference:** Governance Framework Section V; Builder's Guide Phase 0.

| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | |
| **Role** | Project Sponsor |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | PRODUCT_MANIFESTO.md, Compliance Screening Matrix (Intake Section 8.4) |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Phase Gate: Phase 1 → Phase 2

**Gate requirement:** Senior Technical Authority approves architecture selection and security posture.
**Evidence required:** Written approval of Project Bible.
**Reference:** Governance Framework Section V; Builder's Guide Phase 1.

| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Approver** | |
| **Role** | Senior Technical Authority |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | PROJECT_BIBLE.md, Architecture Decision Records, Threat Model |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Phase Gate: Phase 3 → Phase 4

**Gate requirement:** Application Owner and IT Security approve go-live readiness.
**Evidence required:** Security scan results, penetration test report (if required), go-live checklist.
**Reference:** Governance Framework Section V; Builder's Guide Phase 3 and Phase 4.

### Application Owner Approval

| Field | Value |
|---|---|
| **Gate** | Phase 3 → Phase 4 (Application Owner) |
| **Approver** | |
| **Role** | Application Owner |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | Phase 3 test results (docs/test-results/), go-live checklist |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

### IT Security Approval

| Field | Value |
|---|---|
| **Gate** | Phase 3 → Phase 4 (IT Security) |
| **Approver** | |
| **Role** | IT Security |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | SAST/DAST results, dependency scan, SBOM, penetration test (if applicable) |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Retroactive Phase 1 → Phase 2 STA Approval

**Required because:** This project was upgraded from personal to organizational on {today}. Per docs/builders-guide.md § Phase 1 (line 807) and Governance Framework Section V, the Senior Technical Authority must retroactively review and approve the existing Project Bible before further phase gate work proceeds. scripts/check-phase-gate.sh emits a non-blocking WARN until the Approver + Date below are filled in.

| Field | Value |
|---|---|
| **Gate** | Retroactive Phase 1 → Phase 2 (STA) |
| **Approver** | |
| **Role** | Senior Technical Authority |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | docs/builders-guide.md § Phase 1 (line 807) |
| **Artifacts reviewed** | PROJECT_BIBLE.md (as-of upgrade), Architecture Decision Records, Threat Model |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Approval History

_Append additional approvals here for post-launch changes, maintenance reviews, or re-approvals._

| Date | Gate / Event | Approver | Role | Decision | Reference |
|---|---|---|---|---|---|
| {today} | Deployment upgrade (personal → organizational) | Orchestrator | — | Applied | scripts/upgrade-project.sh |
"""

with open(log_path, 'w') as f:
    f.write(new_content)
PYEOF

      print_ok "Restructured APPROVAL_LOG.md for organizational governance"
    else
      print_info "APPROVAL_LOG.md already has organizational format — no restructure needed"
    fi
  else
    # No existing APPROVAL_LOG.md — generate one
    print_info "No APPROVAL_LOG.md found — generating organizational format"

    python3 << 'PYEOF' - "$APPROVAL_LOG" "$PROJECT_NAME"
import sys
from datetime import date

log_path = sys.argv[1]
project_name = sys.argv[2]
today = str(date.today())

content = f"""---
project: {project_name}
deployment: organizational
created: {today}
framework: Solo Orchestrator v1.0
---

# Approval Log — {project_name}

This document records all governance approvals for this project. Each entry captures who approved what, when, and what evidence supports the approval. This is the auditable governance trail required by the Solo Orchestrator Enterprise Governance Framework (SOI-003-GOV, Section V).

**Instructions:** Update this log at each phase gate transition. Every approval entry must include the approver's name, role, date, method of approval, and a reference to the evidence. Do not delete or modify previous entries — append only. Git history provides tamper evidence.

---

## Pre-Phase 0: Organizational Pre-Conditions

These pre-conditions must be completed before Phase 0 begins. See Governance Framework Section V and Project Intake Section 8.

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
| 1 | AI deployment path approved | | IT Security | | Email / Ticket / Document | | |
| 2 | Insurance coverage confirmed | | Insurance Broker | | Email / Ticket / Document | | |
| 3 | Liability entity designated | | Legal / CIO | | Email / Ticket / Document | | |
| 4 | Project sponsor assigned | | Executive Sponsor | | Email / Ticket / Document | | |
| 5 | Backup maintainer designated | | Technical Lead | | Email / Ticket / Document | | |
| 6 | ITSM project registered | | ITSM / PMO | | Email / Ticket / Document | | |

---

## Phase Gate: Phase 0 → Phase 1

**Gate requirement:** Project Sponsor approves business justification and compliance screening.
**Evidence required:** Signed-off Phase 0 artifacts + compliance screening matrix.
**Reference:** Governance Framework Section V; Builder's Guide Phase 0.

| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | |
| **Role** | Project Sponsor |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | PRODUCT_MANIFESTO.md, Compliance Screening Matrix (Intake Section 8.4) |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Phase Gate: Phase 1 → Phase 2

**Gate requirement:** Senior Technical Authority approves architecture selection and security posture.
**Evidence required:** Written approval of Project Bible.
**Reference:** Governance Framework Section V; Builder's Guide Phase 1.

| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Approver** | |
| **Role** | Senior Technical Authority |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | PROJECT_BIBLE.md, Architecture Decision Records, Threat Model |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Phase Gate: Phase 3 → Phase 4

**Gate requirement:** Application Owner and IT Security approve go-live readiness.
**Evidence required:** Security scan results, penetration test report (if required), go-live checklist.
**Reference:** Governance Framework Section V; Builder's Guide Phase 3 and Phase 4.

### Application Owner Approval

| Field | Value |
|---|---|
| **Gate** | Phase 3 → Phase 4 (Application Owner) |
| **Approver** | |
| **Role** | Application Owner |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | Phase 3 test results (docs/test-results/), go-live checklist |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

### IT Security Approval

| Field | Value |
|---|---|
| **Gate** | Phase 3 → Phase 4 (IT Security) |
| **Approver** | |
| **Role** | IT Security |
| **Date** | |
| **Method** | Email / Ticket / Document |
| **Reference** | |
| **Artifacts reviewed** | SAST/DAST results, dependency scan, SBOM, penetration test (if applicable) |
| **Decision** | Approved / Approved with conditions / Rejected |
| **Conditions (if any)** | |
| **Notes** | |

---

## Approval History

_Append additional approvals here for post-launch changes, maintenance reviews, or re-approvals._

| Date | Gate / Event | Approver | Role | Decision | Reference |
|---|---|---|---|---|---|
| | | | | | |
"""

with open(log_path, 'w') as f:
    f.write(content)
PYEOF

    print_ok "Generated organizational APPROVAL_LOG.md"
  fi
fi

# ================================================================
# 6b. Append upgrade audit entry when no deployment change but POC/track changed
# ================================================================
if [ "$DEPLOYMENT_CHANGES" = false ] && { [ "$POC_REMOVED" = true ] || [ "$POC_TO_SPONSORED" = true ] || [ "$POC_TO_PRIVATE" = true ] || [ "$TRACK_CHANGES" = true ]; }; then
  if [ -f "$APPROVAL_LOG" ]; then
    print_step "Appending upgrade audit entry to APPROVAL_LOG.md"

    python3 << 'PYEOF' - "$APPROVAL_LOG" "$POC_REMOVED" "$POC_TO_SPONSORED" "$POC_TO_PRIVATE" "$TRACK_CHANGES" "$CURRENT_TRACK" "$TARGET_TRACK"
import sys
from datetime import date

log_path = sys.argv[1]
poc_removed = sys.argv[2] == "true"
poc_to_sponsored = sys.argv[3] == "true"
poc_to_private = sys.argv[4] == "true"
track_changes = sys.argv[5] == "true"
old_track = sys.argv[6]
new_track = sys.argv[7]
today = str(date.today())

with open(log_path) as f:
    content = f.read()

changes = []
if poc_removed:
    changes.append("POC mode removed (production-ready)")
if poc_to_sponsored:
    changes.append("upgraded from Private POC to Sponsored POC")
if poc_to_private:
    # Audit code-upgrade-project-7 (S3 sweep): the --to-private-poc path
    # was silently dropped from the audit-entry block, so the markdown
    # audit trail lost coverage of that transition.
    changes.append("transitioned to Private POC")
if track_changes:
    changes.append(f"track upgraded from {old_track} to {new_track}")

audit_entry = f"\n| {today} | Upgrade | scripts/upgrade-project.sh | System | Applied | {', '.join(changes)} |\n"

# Append to Approval History table if it exists
if "## Approval History" in content:
    # Insert before the last empty row in the table
    content = content.rstrip()
    content += audit_entry
else:
    content += f"\n---\n\n## Upgrade Log\n\n| Date | Event | Tool | Actor | Status | Details |\n|---|---|---|---|---|---|\n{audit_entry}"

with open(log_path, 'w') as f:
    f.write(content)
PYEOF

    print_ok "Appended upgrade audit entry to APPROVAL_LOG.md"
  fi
fi

# ================================================================
# 6c. Refresh PRODUCT_MANIFESTO.md appendices on track upgrade
# ================================================================
# Audit code-upgrade-project-6 (S3 sweep): when a project upgrades from
# light track to standard/full, Appendix A (Revenue Model & Unit
# Economics) and Appendix C (Trademark & Legal Pre-Check) may carry
# "SKIPPED — internal tool, …" markers populated during Phase 0 under
# the light-track exemption (see docs/builders-guide.md §0.5 / §0.7).
# Those appendices are required for Standard+, so the upgrade must
# flag them as PENDING rather than leave the misleading SKIPPED text
# in place. Rewrite is idempotent: matches the literal "SKIPPED —"
# Phase-0 marker only, leaves anything else alone, and the second run
# finds nothing to rewrite.
PRODUCT_MANIFESTO="$PROJECT_ROOT/PRODUCT_MANIFESTO.md"
if [ "$TRACK_CHANGES" = true ] && [ "$TARGET_RANK" -gt "$CURRENT_RANK" ] && [ -f "$PRODUCT_MANIFESTO" ]; then
  print_step "Refreshing PRODUCT_MANIFESTO.md Appendix A/C markers for track upgrade"

  python3 << 'PYEOF' - "$PRODUCT_MANIFESTO" "$CURRENT_TRACK" "$TARGET_TRACK"
import re, sys
from datetime import date

manifesto_path = sys.argv[1]
old_track = sys.argv[2]
new_track = sys.argv[3]
today = str(date.today())

with open(manifesto_path) as f:
    content = f.read()

# Match the Phase-0 light-track SKIPPED marker exactly. The Builder's
# Guide documents two canonical forms ("SKIPPED — internal tool, no
# revenue model required" / "SKIPPED — internal tool, no trademark
# check required"), but operators sometimes append free-form rationale.
# Anchor on "SKIPPED —" (em dash, U+2014) plus optional ASCII "--"
# fallback so we catch both typographic conventions.
pattern = re.compile(r'SKIPPED\s*(?:—|--)\s*[^\n]*')
replacement = f"PENDING — required by track upgrade {old_track} → {new_track} on {today}"

new_content, n = pattern.subn(replacement, content)
if n > 0:
    with open(manifesto_path, 'w') as f:
        f.write(new_content)
    print(f"  Rewrote {n} SKIPPED marker(s) → PENDING (track upgrade)")
else:
    print("  No SKIPPED markers found — nothing to rewrite.")
PYEOF

  print_ok "PRODUCT_MANIFESTO.md appendix markers refreshed (if any)"
fi

# ================================================================
# 7. Call resolve-tools.sh (if available and state is sufficient)
# ================================================================
RESOLVER="$ORCHESTRATOR_ROOT/scripts/resolve-tools.sh"
MATRIX_DIR="$ORCHESTRATOR_ROOT/templates/tool-matrix"

# BL-069: install every auto_install tool from the resolver output,
# iterating each tool's structured install_cmds stages (fail-fast per
# stage) via run_install_stages. Falls back to the legacy singular
# install_cmd only when the array is absent (legacy-string matrix
# entries behave unchanged). No 2>/dev/null: per-stage install failures
# must surface so the operator can act on the exact failing stage.
#
# Factored out of the interactive track-upgrade path (verifier
# follow-up) so the stage iteration is directly unit-testable — the
# `[ -t 0 ]` + prompt_yes_no gates around the call site made this loop
# unreachable from the non-interactive test suite.
#   $1 = resolver JSON output   $2 = count of .auto_install entries
upgrade_auto_install_from_resolver() {
  local resolver_output="$1"
  local auto_count="$2"
  local _ui=0
  while [ "$_ui" -lt "$auto_count" ]; do
    local _tool_name _stages_json _st
    _tool_name=$(echo "$resolver_output" | jq -r --argjson i "$_ui" '.auto_install[$i].name // "tool"')
    _stages_json=$(echo "$resolver_output" | jq -c --argjson i "$_ui" '
      .auto_install[$i] as $t
      | (if ($t.install_cmds | type) == "array" and ($t.install_cmds | length) > 0
         then $t.install_cmds else [$t.install_cmd] end)
      | map(select(. != null and . != ""))
    ')
    local _stages=()
    while IFS= read -r _st; do
      [ -n "$_st" ] && _stages+=("$_st")
    done < <(echo "$_stages_json" | jq -r '.[]')
    if [ "${#_stages[@]}" -gt 0 ]; then
      print_info "Installing: $_tool_name"
      if run_install_stages "$_tool_name" "${_stages[@]}"; then
        print_ok "Installed successfully"
      else
        print_warn "Install failed — you may need to install manually"
      fi
    fi
    _ui=$((_ui + 1))
  done
}

if [ "$TRACK_CHANGES" = true ] && [ -f "$RESOLVER" ] && [ -d "$MATRIX_DIR" ] && \
   [ -n "$CURRENT_PLATFORM" ] && [ -n "$CURRENT_LANGUAGE" ]; then
  print_step "Resolving tools for upgraded track"

  RESOLVER_OUTPUT=""
  if RESOLVER_OUTPUT=$(bash "$RESOLVER" \
      --dev-os "$CURRENT_DEV_OS" \
      --platform "$CURRENT_PLATFORM" \
      --language "$CURRENT_LANGUAGE" \
      --track "$TARGET_TRACK" \
      --phase "$CURRENT_PHASE" \
      --matrix-dir "$MATRIX_DIR" \
      ${TOOL_PREFS:+--tool-prefs "$TOOL_PREFS"} 2>/dev/null); then

    # Show newly required tools
    AUTO_COUNT=$(echo "$RESOLVER_OUTPUT" | jq '.auto_install | length')
    MANUAL_COUNT=$(echo "$RESOLVER_OUTPUT" | jq '.manual_install | length')
    TOTAL_NEW=$((AUTO_COUNT + MANUAL_COUNT))

    if [ "$TOTAL_NEW" -gt 0 ]; then
      echo ""
      print_info "The $TARGET_TRACK track requires $TOTAL_NEW additional tool(s):"
      echo ""

      if [ "$AUTO_COUNT" -gt 0 ]; then
        echo -e "  ${BOLD}Auto-installable:${NC}"
        echo "$RESOLVER_OUTPUT" | jq -r '.auto_install[] | "    - \(.name) (\(.category // "general"))"'
      fi

      if [ "$MANUAL_COUNT" -gt 0 ]; then
        echo -e "  ${BOLD}Requires manual setup:${NC}"
        echo "$RESOLVER_OUTPUT" | jq -r '.manual_install[] | "    - \(.name): \(.instructions // "see documentation")"'
      fi

      echo ""

      if [ "$AUTO_COUNT" -gt 0 ] && [ -t 0 ]; then
        # Wave-3 raw-read sweep: prompt_yes_no centralizes the
        # !-t 0 / CI default-N policy. The outer `-t 0` guard
        # already gates this branch — prompt_yes_no's defense-in-
        # depth N return here is harmless (we don't enter the block).
        if prompt_yes_no "$(echo -e "  ${BOLD}Auto-install $AUTO_COUNT tool(s) now? [Y/n]${NC}")" "Y"; then
          # BL-069: delegate to the factored stage-iterating installer.
          # Factored out (verifier follow-up) so the per-stage iteration
          # is DIRECTLY testable — the interactive prompt_yes_no + `-t 0`
          # gates above made this loop unreachable from the test suite,
          # which hid a stage-drop regression.
          upgrade_auto_install_from_resolver "$RESOLVER_OUTPUT" "$AUTO_COUNT"
        else
          print_info "Skipped auto-install. You can install tools later."
        fi
      fi

      if [ "$MANUAL_COUNT" -gt 0 ]; then
        print_info "Remember to complete manual tool setup listed above."
      fi
    else
      print_ok "No additional tools required for the $TARGET_TRACK track"
    fi
  else
    print_warn "Tool resolver returned an error — skipping tool resolution."
    print_info "You can run tool resolution manually later."
  fi
else
  if [ "$TRACK_CHANGES" = true ]; then
    print_info "Tool resolver not available — skipping tool resolution."
    print_info "Run resolve-tools.sh manually to check for new track requirements."
  fi
fi

# ================================================================
# 8. Commit all changes
# ================================================================
echo ""
print_step "Committing changes"

# Build commit message
COMMIT_PARTS=()
if [ "$TRACK_CHANGES" = true ]; then
  COMMIT_PARTS+=("track $CURRENT_TRACK -> $TARGET_TRACK")
fi
if [ "$DEPLOYMENT_CHANGES" = true ]; then
  COMMIT_PARTS+=("deployment $CURRENT_DEPLOYMENT -> $TARGET_DEPLOYMENT")
fi
if [ "$POC_REMOVED" = true ]; then
  COMMIT_PARTS+=("POC -> production")
fi
if [ "$POC_TO_SPONSORED" = true ]; then
  COMMIT_PARTS+=("-> sponsored POC")
fi
# Audit code-upgrade-project-7 (S3 sweep): missing POC_TO_PRIVATE branch
# produced a misleading generic "chore(upgrade):" commit subject when
# --to-private-poc was the only change.
if [ "$POC_TO_PRIVATE" = true ]; then
  COMMIT_PARTS+=("-> private POC")
fi

COMMIT_SUMMARY=$(IFS=', '; echo "${COMMIT_PARTS[*]}")
COMMIT_MSG="chore(upgrade): ${COMMIT_SUMMARY}

Upgraded project configuration via scripts/upgrade-project.sh.
Changes: ${COMMIT_SUMMARY}."

# Stage all modified project files
cd "$PROJECT_ROOT"

FILES_TO_STAGE=()
[ -f ".claude/phase-state.json" ] && FILES_TO_STAGE+=(".claude/phase-state.json")
[ -f ".claude/tool-preferences.json" ] && FILES_TO_STAGE+=(".claude/tool-preferences.json")
[ -f ".claude/intake-progress.json" ] && FILES_TO_STAGE+=(".claude/intake-progress.json")
# BL-061: manifest.json is refreshed in section 2b alongside phase-state.json,
# so stage it here so the upgrade commit captures the refreshed tier snapshot.
[ -f ".claude/manifest.json" ] && FILES_TO_STAGE+=(".claude/manifest.json")
[ -f "CLAUDE.md" ] && FILES_TO_STAGE+=("CLAUDE.md")
[ -f "PROJECT_INTAKE.md" ] && FILES_TO_STAGE+=("PROJECT_INTAKE.md")
[ -f "APPROVAL_LOG.md" ] && FILES_TO_STAGE+=("APPROVAL_LOG.md")
# Audit code-upgrade-project-6 (S3 sweep): PRODUCT_MANIFESTO.md is
# rewritten by the Appendix A/C refresh block above when a track
# upgrade lifts a light-track project to standard/full. Stage it so
# the rewrite is committed alongside the other upgrade artifacts.
[ -f "PRODUCT_MANIFESTO.md" ] && FILES_TO_STAGE+=("PRODUCT_MANIFESTO.md")

if [ ${#FILES_TO_STAGE[@]} -gt 0 ]; then
  # Check if there are actual changes to commit
  if git diff --quiet "${FILES_TO_STAGE[@]}" 2>/dev/null && \
     git diff --cached --quiet "${FILES_TO_STAGE[@]}" 2>/dev/null; then
    print_info "No file changes detected — skipping commit."
    # Nothing to commit means the mutation block was a true no-op: clear
    # the trap so the post-commit steps below don't trip the rollback.
    trap - INT TERM ERR
    _upgrade_prune_snapshots
  else
    git add "${FILES_TO_STAGE[@]}" 2>/dev/null || true
    if git diff --cached --quiet 2>/dev/null; then
      print_info "No staged changes — skipping commit."
      trap - INT TERM ERR
      _upgrade_prune_snapshots
    else
      # Audit code-upgrade-project-5: pre-fix, a failing `git commit`
      # was demoted to a [WARN] and the script exited 0 with 6 mutated
      # files staged in the working tree and no audit trail. Rollback
      # makes the failure first-class: working tree is restored and
      # snapshot retained for forensics.
      if git commit -m "$COMMIT_MSG" 2>/dev/null; then
        print_ok "Changes committed"
        # Commit succeeded — disarm the trap before the post-commit
        # blocks (UAT template migration, helper refresh, validate.sh)
        # so their non-zero exit codes don't trip an unwanted rollback
        # of the freshly-committed work.
        trap - INT TERM ERR
        _upgrade_prune_snapshots
      else
        print_fail "Git commit failed — rolling back mutation block."
        print_info "Manual recovery: git commit -m 'chore(upgrade): ${COMMIT_SUMMARY}'"
        _upgrade_rollback
      fi
    fi
  fi
else
  print_info "No files to stage."
  trap - INT TERM ERR
  _upgrade_prune_snapshots
fi

# ================================================================
# Summary
# ================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║               Upgrade Complete                          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Project:${NC}    $PROJECT_NAME"
echo -e "  ${BOLD}Track:${NC}      $TARGET_TRACK"
echo -e "  ${BOLD}Deployment:${NC} $TARGET_DEPLOYMENT"
if [ "$POC_REMOVED" = true ]; then
  echo -e "  ${BOLD}Mode:${NC}       Production"
elif [ "$POC_TO_SPONSORED" = true ]; then
  echo -e "  ${BOLD}Mode:${NC}       Sponsored POC"
fi
echo ""

if [ "$DEPLOYMENT_CHANGES" = true ] && [ "$TARGET_DEPLOYMENT" = "organizational" ]; then
  print_info "Next steps for organizational deployment:"
  echo "  1. Fill in the Pre-Phase 0 organizational pre-conditions in APPROVAL_LOG.md"
  echo "  2. Complete Section 8 of PROJECT_INTAKE.md (governance pre-flight)"
  echo "  3. Assign approval authorities for each phase gate"
  echo ""
fi

if [ "$TRACK_CHANGES" = true ]; then
  print_info "Track upgraded to $TARGET_TRACK. Review new requirements:"
  echo "  - Check docs/reference/builders-guide.md for $TARGET_TRACK track requirements"
  echo "  - Run scripts/resolve-tools.sh to verify all tools are installed"
  echo ""
fi

if [ "$POC_REMOVED" = true ]; then
  print_info "POC constraints removed. This project is now production-ready."
  echo "  - Review CLAUDE.md for any remaining POC references"
  echo "  - Review PROJECT_INTAKE.md Section 8 governance fields"
  echo ""
fi

# Run installation verification after upgrade
if [ -x "scripts/verify-install.sh" ]; then
  echo ""
  print_step "Running post-upgrade verification..."
  bash scripts/verify-install.sh || true
fi

# --- Host-aware migration (spec 2026-04-21) ---
# Projects created before the host-aware gate need the flat CI template layout
# migrated into per-host subfolders and the manifest backfilled with a host field.
# This runs idempotently — safe on already-migrated projects.

# --- UAT template migration (spec 2026-04-23-uat-template-quality-design.md) ---
# Re-copy updated UAT source templates and per-platform reference pair.
# Idempotent — safe to re-run.
if [ -d tests/uat/templates ] || [ -d tests/uat ]; then
  print_step "Migrating UAT templates and references"
  mkdir -p tests/uat/templates tests/uat/examples

  # Source templates
  if [ -f "$SCRIPT_DIR/../templates/uat/test-session-template.html" ]; then
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.html" \
       tests/uat/templates/test-session-template.html
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.md" \
       tests/uat/templates/test-session-template.md
    print_ok "UAT source templates refreshed"
  fi

  # Per-platform reference pair (read PLATFORM from intake-progress.json)
  uat_platform=""
  if [ -f .claude/intake-progress.json ]; then
    uat_platform=$(jq -r '.answers.platform // empty' .claude/intake-progress.json 2>/dev/null || true)
  fi

  if [ -n "$uat_platform" ] && [ "$uat_platform" != "other" ] && \
     [ -f "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-pre-flight.html" ]; then
    cp "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-pre-flight.html" \
       tests/uat/examples/pre-flight-reference.html
    cp "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-scenario.json" \
       tests/uat/examples/scenario-reference.json
    print_ok "UAT reference pair copied for platform '$uat_platform'"
  elif [ "$uat_platform" = "other" ]; then
    print_info "Platform is 'other' — UAT reference is co-build protocol."
    print_info "See docs/reference/uat-authoring-guide.md § 5 next time you start a UAT session."
  else
    print_warn "UAT platform unknown (intake-progress.json missing or lacks 'platform' field). Skipping reference copy; see docs/reference/uat-authoring-guide.md."
  fi

  echo ""
  print_info "UAT quality guardrails now active. Next UAT session should:"
  print_info "  1. Read tests/uat/templates/test-session-template.html's embedded checklist"
  print_info "  2. Use tests/uat/examples/ as shape references (first-class platforms)"
  print_info "  3. Run scripts/lint-uat-scenarios.sh <populated-file> before saving"
  print_info "See docs/reference/uat-authoring-guide.md for details."
  echo ""
fi

# --- Framework-helper script refresh (UAT 2026-04-25 fix C1) ---
# init.sh's file-copy block enumerates each helper script explicitly. When new
# helpers ship in the framework (BL-009: lint-uat-scenarios.sh; BL-015:
# pending-approval.sh), existing projects can't pick them up by re-running
# init. This block syncs the post-BL-009/BL-015 helper set into the project's
# scripts/ directory. Idempotent: cp overwrites existing files identically.
#
# BL-046 (helpers.sh core/full split, 2026-06-30): existing projects have
# only scripts/lib/helpers.sh (the pre-split monolith). The refreshed
# short-lived scripts (check-versions.sh, check-updates.sh, etc.) source
# scripts/lib/helpers-core.sh directly. Without the two new sibling files
# they'd fall through to the inline fallback (which is functional but
# suboptimal) or, in a couple of scripts that hard-source without a
# fallback (check-maintenance.sh, check-phase-gate.sh, check-updates.sh,
# validate.sh, test-gate.sh, resume.sh, process-checklist.sh), they'd
# error out with "file not found." Ship the two new files before the
# script refresh below, so the refreshed callers find them on next run.
if [ -d scripts/lib ]; then
  for lib_file in helpers-core.sh helpers-full.sh; do
    src="$SCRIPT_DIR/lib/$lib_file"
    dst="scripts/lib/$lib_file"
    if [ -f "$src" ]; then
      if [ "$src" -ef "$dst" ]; then
        : # no-op (same file)
      else
        cp "$src" "$dst"
        print_ok "scripts/lib/$lib_file installed (BL-046 helpers.sh split)"
      fi
    fi
  done
fi

print_step "Refreshing framework helper scripts (BL-009, BL-015)"
if [ -d scripts ]; then
  for helper in pending-approval.sh lint-uat-scenarios.sh; do
    if [ -f "$SCRIPT_DIR/$helper" ]; then
      # When invoked as `bash scripts/upgrade-project.sh` from the project root,
      # $SCRIPT_DIR resolves to scripts/ — the source and destination are the
      # same file. BSD cp returns non-zero on identical source/dest, which under
      # `set -euo pipefail` would abort the upgrade. Skip the no-op.
      if [ "$SCRIPT_DIR/$helper" -ef "scripts/$helper" ]; then
        print_info "scripts/$helper already at framework version (no-op)"
      else
        cp "$SCRIPT_DIR/$helper" "scripts/$helper"
        chmod +x "scripts/$helper"
        print_ok "scripts/$helper refreshed from framework"
      fi
    fi
  done
else
  print_warn "scripts/ directory not found in project root — skipping helper refresh"
fi


# Run full project validation to surface new track requirements
if [ -x "scripts/validate.sh" ]; then
  echo ""
  print_step "Running post-upgrade validation..."
  if ! bash scripts/validate.sh; then
    echo ""
    print_warn "Post-upgrade validation found issues."
    print_info "Review the output above and address any errors before continuing."
    print_info "The upgrade itself completed successfully — validation checks new track requirements."
  fi
fi

print_ok "Upgrade complete."

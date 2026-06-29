#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Project Reconfiguration
# Regenerates structural files when project configuration changes.
# Called by the intake wizard when platform, language, track, or deployment changes.
#
# Usage:
#   scripts/reconfigure-project.sh --field <field> --old <old_value> --new <new_value>
#   scripts/reconfigure-project.sh --field language --old python --new typescript
#   scripts/reconfigure-project.sh --field platform --old web --new desktop
#   scripts/reconfigure-project.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

# Audit code-verify-reconfigure-2: self-contamination guard. Without
# this, running reconfigure-project.sh from inside the solo-orchestrator
# framework repo itself rewrites the framework's own pipelines and
# config files. Matches the U-N precedent in init.sh:3334-3340.
guard_not_in_framework || exit 1

# Audit code-verify-reconfigure-1: project context (platform, language)
# is canonically stored in .claude/tool-preferences.json::.context.*,
# NOT in phase-state.json. Pre-fix reads of `.platform` / `.language`
# from phase-state.json silently returned empty, skipping release-
# pipeline retemplate and gating logic. This helper queries the
# canonical source with a phase-state.json fallback for forward-
# compatibility.
get_project_context() {
  local key="$1" value=""
  if [ -f ".claude/tool-preferences.json" ]; then
    value=$(jq -r ".context.$key // empty" .claude/tool-preferences.json 2>/dev/null || echo "")
  fi
  if [ -z "$value" ] && [ -f ".claude/phase-state.json" ]; then
    value=$(jq -r ".$key // empty" .claude/phase-state.json 2>/dev/null || echo "")
  fi
  printf '%s' "$value"
}

# Parse arguments (before source-dir check so --help works without a project)
FIELD=""
OLD_VALUE=""
NEW_VALUE=""
# tier-crosscheck-6: optional companion to `--field zdr_attested --new false`
# (or as a standalone `--field zdr_attestation_reason --new "<text>"`).
# Stored as phase1_artifacts.zdr_attestation_reason in process-state.json.
RECONF_REASON=""
RECONF_LEVEL=""
RECONF_CONFIRM=0
RECONF_RESET_BASELINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --field) FIELD="$2"; shift 2 ;;
    --old) OLD_VALUE="$2"; shift 2 ;;
    --new) NEW_VALUE="$2"; shift 2 ;;
    --reason) RECONF_REASON="$2"; shift 2 ;;
    --reason=*) RECONF_REASON="${1#*=}"; shift ;;
    # BL-030 Task 8: enforcement-level transition flags.
    --enforcement-level) RECONF_LEVEL="$2"; shift 2 ;;
    --enforcement-level=*) RECONF_LEVEL="${1#*=}"; shift ;;
    --confirm-pitfalls) RECONF_CONFIRM=1; shift ;;
    --reset-detection-baseline) RECONF_RESET_BASELINE=1; shift ;;
    --help|-h)
      echo "Usage: scripts/reconfigure-project.sh --field <field> --old <old> --new <new>"
      echo "       scripts/reconfigure-project.sh --enforcement-level <no|light|strict> [--confirm-pitfalls]"
      echo "       scripts/reconfigure-project.sh --reset-detection-baseline"
      echo ""
      echo "Supported fields:"
      echo "  language   — Regenerates CI pipeline, .gitignore language entries, permissions"
      echo "  platform   — Regenerates release pipeline, copies new platform module"
      echo "  name       — Updates phase-state.json, CLAUDE.md, APPROVAL_LOG.md header,"
      echo "               intake-progress.json, Qdrant collection, PROJECT_INTAKE.md"
      echo "  data_classification  — Sets the Phase 1 ZDR/classification gate value"
      echo "                         (one of: public, internal, confidential, pii,"
      echo "                          financial, health, regulated). Updates"
      echo "                          .claude/process-state.json::phase1_artifacts.data_classification"
      echo "                          + appends an APPROVAL_LOG.md audit row."
      echo "  zdr_attested         — Sets phase1_artifacts.zdr_attested (--new true|false)."
      echo "                          When false, also accept --reason \"<text>\" to record"
      echo "                          phase1_artifacts.zdr_attestation_reason."
      echo "  zdr_attestation_reason  — Free-text written exception. Sets the reason"
      echo "                            field directly without flipping zdr_attested."
      echo ""
      echo "Track and deployment changes are NOT supported here — they require"
      echo "the governance pre-conditions enforced by scripts/upgrade-project.sh."
      echo "See audit baseline §4 (lines 431-434) and docs/user-guide.md."
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Sibling of PR #54 (init.sh atomic finalize). Commit any post-mutation
# state into a chore-finalize commit so the working tree stays clean
# after reconfigure exits. No-op when nothing changed (defensive). The
# detection baseline is refreshed to the new HEAD so the BL-030 detector
# does not flag the reconfigure commit as out-of-band on the next
# SessionStart.
finalize_reconfigure_commit() {
  local subject="$1"
  [ -d "$PROJECT_ROOT/.git" ] || return 0
  if [ -z "$( cd "$PROJECT_ROOT" && git status --porcelain 2>/dev/null )" ]; then
    return 0
  fi
  ( cd "$PROJECT_ROOT" \
      && git add -A \
      && git commit -q --no-verify -m "$subject" 2>/dev/null \
      && git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt \
  ) || return 1
}

# BL-030 Task 8: --enforcement-level <no|light|strict> transition.
if [ -n "$RECONF_LEVEL" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/enforcement-level.sh"
  if ! validate_transition "$PROJECT_ROOT" "$RECONF_LEVEL"; then
    exit 1
  fi
  current=$(read_enforcement_level "$PROJECT_ROOT")
  case "$RECONF_LEVEL" in
    light|no)
      if [ "$RECONF_CONFIRM" != "1" ]; then
        print_fail "Downgrade to '$RECONF_LEVEL' requires --confirm-pitfalls."
        echo "  See docs/superpowers/specs/2026-04-28-bl030-enforcement-model-design.md § 10." >&2
        exit 1
      fi
      ;;
  esac

  # Sibling of PR #54 (init.sh atomic finalize). Pre-fix this block
  # wrote manifest.json + bypass-audit.json + ran install-filesystem-
  # gates.sh with `|| true` swallowing the installer exit code. On
  # installer failure (read-only .git/hooks/, malformed sibling hook,
  # missing /bin/bash on a stripped container) the manifest claimed
  # the new level while no SOIF marker had been installed — a silent-
  # bypass security defect where the audit log lied about strict
  # enforcement being active. The reverse (strict->light with a
  # failed uninstall) left the manifest saying light while the gate
  # kept blocking. Both cases now snapshot the pre-state, run the
  # installer with failure propagation, and roll back on failure.
  MANIFEST_FILE="$PROJECT_ROOT/.claude/manifest.json"
  AUDIT_FILE="$PROJECT_ROOT/.claude/bypass-audit.json"
  manifest_backup=$(mktemp)
  cp "$MANIFEST_FILE" "$manifest_backup"
  audit_backup=$(mktemp)
  if [ -f "$AUDIT_FILE" ]; then
    cp "$AUDIT_FILE" "$audit_backup"
  else
    echo "[]" > "$audit_backup"
  fi

  rollback_reconfigure() {
    local reason="$1"
    cp "$manifest_backup" "$MANIFEST_FILE"
    cp "$audit_backup" "$AUDIT_FILE"
    rm -f "$manifest_backup" "$audit_backup"
    print_fail "Enforcement-level transition failed: $reason"
    echo "  Manifest and audit log rolled back to pre-transition state." >&2
    echo "  Manifest: $MANIFEST_FILE (still: $current)" >&2
    echo "  Audit:    $AUDIT_FILE (no new row appended)" >&2
    exit 1
  }

  tmp=$(mktemp)
  jq --arg lvl "$RECONF_LEVEL" '.enforcement_level = $lvl' "$MANIFEST_FILE" > "$tmp" \
    && mv "$tmp" "$MANIFEST_FILE" \
    || rollback_reconfigure "manifest write failed"
  [ -f "$AUDIT_FILE" ] || echo "[]" > "$AUDIT_FILE"
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  row=$(jq -nc \
    --arg ts "$ts" --arg lvl "$RECONF_LEVEL" --arg from "$current" \
    '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"framework",
      enforcement_level_at_event:$lvl,
      details:{level:$lvl, from:$from, source:"reconfigure"},
      user_response:"n/a", final_outcome:"recorded_only"}')
  tmp=$(mktemp)
  jq --argjson r "$row" '. + [$r]' "$AUDIT_FILE" > "$tmp" \
    && mv "$tmp" "$AUDIT_FILE" \
    || rollback_reconfigure "audit-row append failed"

  # Install or uninstall the filesystem gate to match the new level.
  # PROJECT_ROOT is the canonical install target. Prefer the project-
  # local copy so the lookup honors any rollback / migration the
  # project has applied; fall back to the framework copy when absent.
  if [ -x "$PROJECT_ROOT/scripts/install-filesystem-gates.sh" ]; then
    INSTALLER="$PROJECT_ROOT/scripts/install-filesystem-gates.sh"
  else
    INSTALLER="$SCRIPT_DIR/install-filesystem-gates.sh"
  fi
  if [ "$RECONF_LEVEL" = "strict" ]; then
    if ! bash "$INSTALLER" --install "$PROJECT_ROOT" >/dev/null 2>&1; then
      rollback_reconfigure "filesystem-gate install failed (installer: $INSTALLER)"
    fi
  else
    if ! bash "$INSTALLER" --uninstall "$PROJECT_ROOT" >/dev/null 2>&1; then
      rollback_reconfigure "filesystem-gate uninstall failed (installer: $INSTALLER)"
    fi
  fi

  rm -f "$manifest_backup" "$audit_backup"
  if [ ! -f "$PROJECT_ROOT/.claude/last-checked-commit.txt" ]; then
    ( cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt ) || true
  fi
  finalize_reconfigure_commit "chore: enforcement-level ${current} -> ${RECONF_LEVEL} (reconfigure)" || true
  print_ok "Enforcement level: $current -> $RECONF_LEVEL"
  exit 0
fi

# BL-030 Task 8: --reset-detection-baseline.
if [ "$RECONF_RESET_BASELINE" = "1" ]; then
  ( cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null > .claude/last-checked-commit.txt )
  [ -f "$PROJECT_ROOT/.claude/bypass-audit.json" ] || echo "[]" > "$PROJECT_ROOT/.claude/bypass-audit.json"
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  row=$(jq -nc --arg ts "$ts" \
    '{timestamp:$ts, session_id:null, type:"enforcement_level_set", actor:"framework",
      enforcement_level_at_event:"unknown",
      details:{action:"detector_baseline_reset", source:"reconfigure"},
      user_response:"n/a", final_outcome:"recorded_only"}')
  tmp=$(mktemp)
  jq --argjson r "$row" '. + [$r]' "$PROJECT_ROOT/.claude/bypass-audit.json" > "$tmp" \
    && mv "$tmp" "$PROJECT_ROOT/.claude/bypass-audit.json"
  finalize_reconfigure_commit "chore: reset detection baseline (reconfigure)" || true
  print_ok "Detection baseline reset to current HEAD."
  exit 0
fi

if [ -z "$FIELD" ] || [ -z "$NEW_VALUE" ]; then
  print_fail "Required: --field and --new (or use --enforcement-level / --reset-detection-baseline)"
  exit 1
fi

# Find orchestrator source for templates
ORCHESTRATOR_SOURCE=""
if [ -f "$PROJECT_ROOT/.claude/orchestrator-source.json" ] && command -v jq &>/dev/null; then
  ORCHESTRATOR_SOURCE=$(jq -r '.source_dir // empty' "$PROJECT_ROOT/.claude/orchestrator-source.json" 2>/dev/null)
fi
if [ -z "$ORCHESTRATOR_SOURCE" ] || [ ! -d "$ORCHESTRATOR_SOURCE" ]; then
  print_fail "Cannot find Solo Orchestrator source directory."
  print_info "Expected path in .claude/orchestrator-source.json"
  exit 1
fi

# ── Helper: get release build variables for a given language ────
# Sets RELEASE_SETUP_ACTION, RELEASE_SETUP_VERSION_KEY, etc.
# Mirrors the logic in init.sh get_release_vars().
get_release_vars() {
  local lang="$1"
  case "$lang" in
    typescript|javascript)
      RELEASE_SETUP_ACTION="actions/setup-node@v4"
      RELEASE_SETUP_VERSION_KEY="node-version"
      RELEASE_SETUP_VERSION_VALUE="'lts/*'"
      RELEASE_INSTALL_COMMAND="npm ci"
      RELEASE_BUILD_COMMAND="npm run build"
      ;;
    python)
      RELEASE_SETUP_ACTION="actions/setup-python@v5"
      RELEASE_SETUP_VERSION_KEY="python-version"
      RELEASE_SETUP_VERSION_VALUE="'3.x'"
      RELEASE_INSTALL_COMMAND="pip install -r requirements.txt"
      RELEASE_BUILD_COMMAND="python -m build"
      ;;
    rust)
      RELEASE_SETUP_ACTION="dtolnay/rust-toolchain@stable"
      RELEASE_SETUP_VERSION_KEY="toolchain"
      RELEASE_SETUP_VERSION_VALUE="stable"
      RELEASE_INSTALL_COMMAND="echo 'No separate install step for Rust'"
      RELEASE_BUILD_COMMAND="cargo build --release"
      ;;
    csharp)
      RELEASE_SETUP_ACTION="actions/setup-dotnet@v4"
      RELEASE_SETUP_VERSION_KEY="dotnet-version"
      RELEASE_SETUP_VERSION_VALUE="'8.0.x'"
      RELEASE_INSTALL_COMMAND="dotnet restore"
      RELEASE_BUILD_COMMAND="dotnet build --configuration Release"
      ;;
    kotlin|java)
      RELEASE_SETUP_ACTION="actions/setup-java@v4"
      RELEASE_SETUP_VERSION_KEY="java-version"
      RELEASE_SETUP_VERSION_VALUE="'21'"
      RELEASE_INSTALL_COMMAND="echo 'Gradle handles dependencies automatically'"
      RELEASE_BUILD_COMMAND="./gradlew build"
      ;;
    go)
      RELEASE_SETUP_ACTION="actions/setup-go@v5"
      RELEASE_SETUP_VERSION_KEY="go-version"
      RELEASE_SETUP_VERSION_VALUE="'stable'"
      RELEASE_INSTALL_COMMAND="echo 'Go modules download automatically'"
      RELEASE_BUILD_COMMAND="go build ./..."
      ;;
    dart)
      RELEASE_SETUP_ACTION="subosito/flutter-action@v2"
      RELEASE_SETUP_VERSION_KEY="channel"
      RELEASE_SETUP_VERSION_VALUE="'stable'"
      RELEASE_INSTALL_COMMAND="flutter pub get"
      RELEASE_BUILD_COMMAND="flutter build"
      ;;
    swift)
      RELEASE_SETUP_ACTION="# Pre-installed: Xcode on macos-latest (no setup action needed)"
      RELEASE_SETUP_VERSION_KEY="# N/A"
      RELEASE_SETUP_VERSION_VALUE="# N/A"
      RELEASE_INSTALL_COMMAND="swift package resolve"
      RELEASE_BUILD_COMMAND="swift build -c release"
      ;;
    *)
      RELEASE_SETUP_ACTION="# TODO: Add setup action for your language"
      RELEASE_SETUP_VERSION_KEY="version"
      RELEASE_SETUP_VERSION_VALUE="'latest'"
      RELEASE_INSTALL_COMMAND="# TODO: Add install command"
      RELEASE_BUILD_COMMAND="# TODO: Add build command"
      ;;
  esac
}

# ── Main reconfiguration logic ──────────────────────────────────
reconfigure() {
  print_step "Reconfiguring project: $FIELD ($OLD_VALUE → $NEW_VALUE)"

  cd "$PROJECT_ROOT"

  case "$FIELD" in
    language)
      # Update tool-preferences.json
      if [ -f ".claude/tool-preferences.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$NEW_VALUE" '.context.language = $v' ".claude/tool-preferences.json" > "$tmp" && mv "$tmp" ".claude/tool-preferences.json"
        print_ok "Updated language in tool-preferences.json"
      fi

      # Regenerate CI pipeline
      local ci_template
      case "$NEW_VALUE" in
        typescript|javascript) ci_template="typescript.yml" ;;
        python)                ci_template="python.yml" ;;
        rust)                  ci_template="rust.yml" ;;
        csharp)                ci_template="csharp.yml" ;;
        kotlin)                ci_template="kotlin.yml" ;;
        java)                  ci_template="java.yml" ;;
        go)                    ci_template="go.yml" ;;
        dart)                  ci_template="dart.yml" ;;
        swift)                 ci_template="swift.yml" ;;
        *)                     ci_template="other.yml" ;;
      esac
      local template_path="$ORCHESTRATOR_SOURCE/templates/pipelines/ci/$ci_template"
      if [ -f "$template_path" ]; then
        mkdir -p .github/workflows
        cp "$template_path" .github/workflows/ci.yml
        print_ok "CI pipeline regenerated for $NEW_VALUE"
      else
        print_warn "CI template not found: $template_path"
      fi

      # Regenerate release pipeline if one exists (language affects build vars)
      if [ -f ".github/workflows/release.yml" ]; then
        local current_platform
        current_platform=$(get_project_context platform)
        if [ -n "$current_platform" ]; then
          local release_src="$ORCHESTRATOR_SOURCE/templates/pipelines/release/${current_platform}.yml"
          if [ -f "$release_src" ]; then
            local project_name
            project_name=$(jq -r '.project // "project"' .claude/phase-state.json 2>/dev/null)
            get_release_vars "$NEW_VALUE"
            sed -e "s|__SETUP_ACTION__|$RELEASE_SETUP_ACTION|g" \
                -e "s|__SETUP_VERSION_KEY__|$RELEASE_SETUP_VERSION_KEY|g" \
                -e "s|__SETUP_VERSION_VALUE__|$RELEASE_SETUP_VERSION_VALUE|g" \
                -e "s|__INSTALL_COMMAND__|$RELEASE_INSTALL_COMMAND|g" \
                -e "s|__BUILD_COMMAND__|$RELEASE_BUILD_COMMAND|g" \
                -e "s|__PROJECT_NAME__|$project_name|g" \
                "$release_src" > .github/workflows/release.yml
            print_ok "Release pipeline re-templated with $NEW_VALUE build variables"
          fi
        fi
      fi

      # Warn about manually-managed files
      print_warn "Review .gitignore and .claude/settings.json permissions for $NEW_VALUE-specific entries"
      ;;

    platform)
      # Update tool-preferences.json
      if [ -f ".claude/tool-preferences.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$NEW_VALUE" '.context.platform = $v' ".claude/tool-preferences.json" > "$tmp" && mv "$tmp" ".claude/tool-preferences.json"
        print_ok "Updated platform in tool-preferences.json"
      fi

      # Copy new platform module
      local module_src="$ORCHESTRATOR_SOURCE/docs/platform-modules/${NEW_VALUE}.md"
      if [ -f "$module_src" ]; then
        mkdir -p docs/platform-modules
        cp "$module_src" docs/platform-modules/
        print_ok "Platform module copied: $NEW_VALUE"
      else
        print_warn "No platform module found for '$NEW_VALUE'"
      fi

      # Regenerate release pipeline
      local release_src="$ORCHESTRATOR_SOURCE/templates/pipelines/release/${NEW_VALUE}.yml"
      if [ -f "$release_src" ]; then
        mkdir -p .github/workflows
        local project_name
        project_name=$(jq -r '.project // "project"' .claude/phase-state.json 2>/dev/null)
        local current_language
        current_language=$(get_project_context language)
        if [ -n "$current_language" ]; then
          get_release_vars "$current_language"
        else
          get_release_vars "other"
        fi
        sed -e "s|__SETUP_ACTION__|$RELEASE_SETUP_ACTION|g" \
            -e "s|__SETUP_VERSION_KEY__|$RELEASE_SETUP_VERSION_KEY|g" \
            -e "s|__SETUP_VERSION_VALUE__|$RELEASE_SETUP_VERSION_VALUE|g" \
            -e "s|__INSTALL_COMMAND__|$RELEASE_INSTALL_COMMAND|g" \
            -e "s|__BUILD_COMMAND__|$RELEASE_BUILD_COMMAND|g" \
            -e "s|__PROJECT_NAME__|$project_name|g" \
            "$release_src" > .github/workflows/release.yml
        print_ok "Release pipeline regenerated for $NEW_VALUE"
      else
        print_info "No release pipeline template for '$NEW_VALUE'"
      fi
      ;;

    track|deployment)
      # code-verify-reconfigure-3: track and deployment moves require the
      # governance pre-conditions enforced by scripts/upgrade-project.sh
      # (baseline §4 lines 431-434: reconfigure "is not a tier/POC upgrade
      # path and does not change `deployment`, `track`, or `poc_mode`").
      # Pre-fix this branch wrote .track / .deployment into phase-state
      # with zero guardrails, silently bypassing:
      #   * §2.1 six blocking pre-conditions for organizational deployment
      #   * §3.2 retroactive STA Bible approval on personal→organizational
      #   * repo-protection bar upgrade
      #   * biweekly Phase-2 governance checkpoint engagement
      #   * APPROVAL_LOG.md template swap (code-verify-reconfigure-4)
      # Refuse and redirect; do not mutate any state.
      print_fail "scripts/reconfigure-project.sh does not change '$FIELD'."
      echo "  Reason: track and deployment moves require the governance" >&2
      echo "          pre-conditions enforced by scripts/upgrade-project.sh." >&2
      echo "          See audit baseline §4 lines 431-434." >&2
      echo "" >&2
      echo "  Action: re-run the change through upgrade-project.sh, e.g.:" >&2
      if [ "$FIELD" = "track" ]; then
        echo "          bash scripts/upgrade-project.sh --track $NEW_VALUE" >&2
      else
        echo "          bash scripts/upgrade-project.sh --deployment $NEW_VALUE" >&2
      fi
      echo "" >&2
      echo "  Run scripts/upgrade-project.sh --help for the full transition matrix." >&2
      exit 1
      ;;

    name)
      local old_name="$OLD_VALUE"
      local new_name="$NEW_VALUE"

      if [ -z "$old_name" ]; then
        print_fail "Renaming requires --old <current_name>"
        exit 1
      fi

      # Atomic snapshot/rollback envelope. Sibling of the PR #57 pattern
      # used by the --enforcement-level path above and the upgrade-project
      # PR #80 fix. Pre-fix this branch wrote five files with no
      # transactional safety — SIGINT / disk-full / jq parse error
      # mid-rename left the project in a half-renamed inconsistent state.
      # Snapshot every file we might mutate (skip missing ones) into a
      # tempdir, install a trap, mutate, then drop the trap on success.
      local snap_dir
      snap_dir=$(mktemp -d)
      local _rename_files=(
        ".claude/phase-state.json"
        ".claude/tool-preferences.json"
        ".claude/settings.local.json"
        ".claude/intake-progress.json"
        "CLAUDE.md"
        "PROJECT_INTAKE.md"
        "APPROVAL_LOG.md"
      )
      local f
      for f in "${_rename_files[@]}"; do
        if [ -f "$f" ]; then
          mkdir -p "$snap_dir/$(dirname "$f")"
          cp "$f" "$snap_dir/$f"
        fi
      done

      _rename_rollback() {
        local reason="${1:-mutation aborted}"
        local g
        for g in "${_rename_files[@]}"; do
          if [ -f "$snap_dir/$g" ]; then
            mkdir -p "$(dirname "$g")"
            cp "$snap_dir/$g" "$g"
          elif [ -f "$g" ]; then
            # File didn't exist pre-mutation but does now — created during
            # this run. Remove to restore pre-state.
            rm -f "$g"
          fi
        done
        rm -rf "$snap_dir"
        trap - INT TERM ERR
        print_fail "Rename failed: $reason"
        echo "  All mutated files have been rolled back to the pre-rename state." >&2
        exit 1
      }
      trap '_rename_rollback "trap fired (INT/TERM/ERR)"' INT TERM ERR

      # Update phase-state.json (.project)
      if [ -f ".claude/phase-state.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$new_name" '.project = $v' ".claude/phase-state.json" > "$tmp" \
          && mv "$tmp" ".claude/phase-state.json" \
          || _rename_rollback "phase-state.json write failed"
        print_ok "Updated project name in phase-state.json"
      fi

      # code-verify-reconfigure-5: update .claude/intake-progress.json
      # (.project_name). Pre-fix the wizard's resume would re-introduce
      # the old name after rename. intake-wizard.sh:259 confirms the key.
      if [ -f ".claude/intake-progress.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$new_name" '.project_name = $v' ".claude/intake-progress.json" > "$tmp" \
          && mv "$tmp" ".claude/intake-progress.json" \
          || _rename_rollback "intake-progress.json write failed"
        print_ok "Updated project_name in intake-progress.json"
      fi

      # Update Qdrant collection in settings.local.json
      if [ -f ".claude/settings.local.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$new_name" '.mcpServers.qdrant.args[-1] = $v' ".claude/settings.local.json" > "$tmp" \
          && mv "$tmp" ".claude/settings.local.json" \
          || _rename_rollback "settings.local.json write failed"
        print_ok "Updated Qdrant collection to $new_name"
      fi

      # Update CLAUDE.md project name
      if [ -f "CLAUDE.md" ]; then
        sed -i.bak "s|$old_name|$new_name|g" CLAUDE.md \
          || _rename_rollback "CLAUDE.md sed failed"
        rm -f CLAUDE.md.bak
        print_ok "Updated project name in CLAUDE.md"
      fi

      # Update PROJECT_INTAKE.md
      if [ -f "PROJECT_INTAKE.md" ]; then
        sed -i.bak "s|$old_name|$new_name|g" PROJECT_INTAKE.md \
          || _rename_rollback "PROJECT_INTAKE.md sed failed"
        rm -f PROJECT_INTAKE.md.bak
        print_ok "Updated project name in PROJECT_INTAKE.md"
      fi

      # code-verify-reconfigure-5: update APPROVAL_LOG.md YAML front-
      # matter (`project:` line) and the exact H1 (`# Approval Log — X`).
      # Anchored substitutions only — DO NOT global-replace the old name
      # in body content (an attentive operator may have referenced the
      # old name in dated entry notes; rewriting those would mutate
      # historical entries and violate invariant 8 append-only). Both
      # personal and org templates carry these two placeholder sites
      # (templates/generated/approval-log-{personal,org}.tmpl lines 2,8).
      if [ -f "APPROVAL_LOG.md" ]; then
        local tmp
        tmp=$(mktemp)
        # awk-based: only rewrite the YAML front-matter (between the
        # first two `---` lines, lines 1..N) and the exact H1. The
        # front-matter is the only safe place to mutate `project: foo`
        # because freeform text in entry notes can legitimately contain
        # `project: foo` as documentation.
        awk -v old="$old_name" -v new="$new_name" '
          BEGIN { in_yaml = 0; yaml_done = 0; line = 0 }
          {
            line++
            if (line == 1 && $0 == "---") { in_yaml = 1; print; next }
            if (in_yaml && $0 == "---")   { in_yaml = 0; yaml_done = 1; print; next }
            if (in_yaml) {
              # Match `project:` followed by whitespace then the old name.
              if ($0 ~ "^project:[[:space:]]+" old "[[:space:]]*$") {
                print "project: " new; next
              }
            }
            # H1 substitution — exact-match guard so we never touch a
            # body H1 or H2 that happens to mention the old name.
            if ($0 == "# Approval Log — " old) {
              print "# Approval Log — " new; next
            }
            print
          }
        ' "APPROVAL_LOG.md" > "$tmp" \
          && mv "$tmp" "APPROVAL_LOG.md" \
          || _rename_rollback "APPROVAL_LOG.md header rewrite failed"
        print_ok "Updated APPROVAL_LOG.md header (YAML + H1); historical entries preserved"
      fi

      # Success — drop the trap and clean up the snapshot dir.
      trap - INT TERM ERR
      rm -rf "$snap_dir"
      ;;

    data_classification|zdr_attested|zdr_attestation_reason)
      # tier-crosscheck-6 (final S3 audit finding): operators must be
      # able to set the Phase 1 ZDR/classification fields post-intake.
      # Pre-fix nothing existed — the canonical state lived only in
      # intake-progress.json::answers and never made it into
      # process-state.json, so check-phase-gate.sh had nothing to read.
      # This block writes to .claude/process-state.json::phase1_artifacts
      # (the field scripts/check-phase-gate.sh consults at Phase 1→2)
      # and appends an audit row to APPROVAL_LOG.md.
      #
      # Atomic envelope: snapshot the two files we mutate (process-
      # state.json + APPROVAL_LOG.md), install an INT/TERM/ERR trap, do
      # the work, drop the trap on success. Sibling of the `name`
      # branch's PR #57 pattern.
      PSTATE=".claude/process-state.json"
      APPROVAL_LOG="APPROVAL_LOG.md"
      if [ ! -f "$PSTATE" ]; then
        print_fail "$PSTATE not found — initialize the project before setting Phase 1 artifacts."
        echo "  Run scripts/init.sh first, or scripts/intake-wizard.sh in an initialized project." >&2
        exit 1
      fi
      if ! command -v jq >/dev/null 2>&1; then
        print_fail "jq is required to mutate $PSTATE — install jq and re-run."
        exit 1
      fi

      # Field-specific value validation BEFORE snapshotting (so a bad
      # input doesn't waste a backup/rollback cycle).
      case "$FIELD" in
        data_classification)
          # Normalize to lowercase canonical form. Accept "Public",
          # "PUBLIC", "public" → store "public".
          NEW_VALUE_CANON=$(printf '%s' "$NEW_VALUE" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          # 7-tier taxonomy from templates/project-intake.md:209 +
          # docs/user-guide.md:466.
          case "$NEW_VALUE_CANON" in
            public|internal|confidential|pii|financial|health|regulated) ;;
            *)
              print_fail "Invalid data_classification '$NEW_VALUE'"
              echo "  Allowed (one of): public, internal, confidential, pii, financial, health, regulated" >&2
              echo "  Reference: templates/project-intake.md:209 / docs/governance-framework.md § VII line 299" >&2
              exit 1 ;;
          esac
          NEW_VALUE="$NEW_VALUE_CANON"
          ;;
        zdr_attested)
          case "$NEW_VALUE" in
            true|True|TRUE|false|False|FALSE) ;;
            *)
              print_fail "Invalid zdr_attested '$NEW_VALUE' (must be true|false)"
              exit 1 ;;
          esac
          # Normalize to canonical lowercase boolean string.
          case "$NEW_VALUE" in
            true|True|TRUE) NEW_VALUE="true" ;;
            *)              NEW_VALUE="false" ;;
          esac
          ;;
        zdr_attestation_reason)
          if [ -z "$NEW_VALUE" ]; then
            print_fail "zdr_attestation_reason must be a non-empty string."
            exit 1
          fi
          ;;
      esac

      # Snapshot the two files we mutate. PR #93's lesson: traps are
      # shell-global, so wrap the mutation in a subshell whose trap
      # only fires on failures inside it. We use the subshell exit
      # status as the rollback trigger; on rc != 0, restore from the
      # snapshot dir captured in the outer scope.
      classification_snap_dir=$(mktemp -d)
      mkdir -p "$classification_snap_dir/.claude"
      cp "$PSTATE" "$classification_snap_dir/.claude/process-state.json"
      [ -f "$APPROVAL_LOG" ] && cp "$APPROVAL_LOG" "$classification_snap_dir/APPROVAL_LOG.md"

      _classification_rollback() {
        local reason="${1:-mutation aborted}"
        cp "$classification_snap_dir/.claude/process-state.json" "$PSTATE"
        [ -f "$classification_snap_dir/APPROVAL_LOG.md" ] && cp "$classification_snap_dir/APPROVAL_LOG.md" "$APPROVAL_LOG"
        rm -rf "$classification_snap_dir"
        print_fail "data_classification/ZDR mutation failed: $reason"
        echo "  $PSTATE and APPROVAL_LOG.md rolled back to pre-mutation state." >&2
        exit 1
      }

      # Mutate process-state.json. jq's |=  + // {} idiom builds
      # phase1_artifacts when it's absent.
      pstate_tmp=$(mktemp)
      case "$FIELD" in
        data_classification)
          jq --arg v "$NEW_VALUE" \
             '.phase1_artifacts = ((.phase1_artifacts // {}) + {data_classification: $v})' \
             "$PSTATE" > "$pstate_tmp" \
            && mv "$pstate_tmp" "$PSTATE" \
            || _classification_rollback "jq write failed for data_classification"
          ;;
        zdr_attested)
          # Build a JSON bool from the canonical string.
          if [ "$NEW_VALUE" = "true" ]; then jq_bool="true"; else jq_bool="false"; fi
          if [ -n "$RECONF_REASON" ]; then
            jq --argjson b "$jq_bool" --arg r "$RECONF_REASON" \
               '.phase1_artifacts = ((.phase1_artifacts // {}) + {zdr_attested: $b, zdr_attestation_reason: $r})' \
               "$PSTATE" > "$pstate_tmp" \
              && mv "$pstate_tmp" "$PSTATE" \
              || _classification_rollback "jq write failed for zdr_attested+reason"
          else
            jq --argjson b "$jq_bool" \
               '.phase1_artifacts = ((.phase1_artifacts // {}) + {zdr_attested: $b})' \
               "$PSTATE" > "$pstate_tmp" \
              && mv "$pstate_tmp" "$PSTATE" \
              || _classification_rollback "jq write failed for zdr_attested"
          fi
          ;;
        zdr_attestation_reason)
          jq --arg r "$NEW_VALUE" \
             '.phase1_artifacts = ((.phase1_artifacts // {}) + {zdr_attestation_reason: $r})' \
             "$PSTATE" > "$pstate_tmp" \
            && mv "$pstate_tmp" "$PSTATE" \
            || _classification_rollback "jq write failed for zdr_attestation_reason"
          ;;
      esac
      print_ok "Updated $PSTATE::phase1_artifacts.$FIELD"

      # Append audit row to APPROVAL_LOG.md so the governance trail
      # records the change. Required by tier-crosscheck-6 (compliance
      # decisions must be auditable in the same log as phase-gate
      # approvals). Append-only; existing entries are not modified.
      if [ -f "$APPROVAL_LOG" ]; then
        today_audit="$(date -u +%Y-%m-%d)"
        case "$FIELD" in
          data_classification)
            audit_line="| $today_audit | data_classification set | reconfigure-project.sh | Orchestrator | Applied | new value: $NEW_VALUE (tier-crosscheck-6) |"
            ;;
          zdr_attested)
            audit_line="| $today_audit | zdr_attested set | reconfigure-project.sh | Orchestrator | Applied | new value: $NEW_VALUE${RECONF_REASON:+ (reason: $RECONF_REASON)} (tier-crosscheck-6) |"
            ;;
          zdr_attestation_reason)
            audit_line="| $today_audit | zdr_attestation_reason set | reconfigure-project.sh | Orchestrator | Applied | reason recorded: $NEW_VALUE (tier-crosscheck-6) |"
            ;;
        esac
        # Insert into the Approval History section if it exists,
        # otherwise append a new section.
        if grep -q "^## Approval History" "$APPROVAL_LOG"; then
          # Append to end of file (append-only — never mutate prior rows).
          printf '%s\n' "$audit_line" >> "$APPROVAL_LOG" \
            || _classification_rollback "APPROVAL_LOG.md append failed"
        else
          {
            echo ""
            echo "---"
            echo ""
            echo "## Approval History"
            echo ""
            echo "| Date | Gate / Event | Tool | Actor | Status | Details |"
            echo "|---|---|---|---|---|---|"
            echo "$audit_line"
          } >> "$APPROVAL_LOG" \
            || _classification_rollback "APPROVAL_LOG.md section append failed"
        fi
        print_ok "Appended audit row to APPROVAL_LOG.md"
      fi

      # Success — drop the snapshot.
      rm -rf "$classification_snap_dir"
      ;;

    *)
      print_fail "Unknown field: $FIELD"
      echo "Supported: language, platform, track, name, deployment,"
      echo "           data_classification, zdr_attested, zdr_attestation_reason"
      exit 1
      ;;
  esac

  echo ""
  print_ok "Reconfiguration complete."
  print_info "Review the changed files and commit when ready."
}

reconfigure

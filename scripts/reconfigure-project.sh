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
RECONF_LEVEL=""
RECONF_CONFIRM=0
RECONF_RESET_BASELINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --field) FIELD="$2"; shift 2 ;;
    --old) OLD_VALUE="$2"; shift 2 ;;
    --new) NEW_VALUE="$2"; shift 2 ;;
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
      echo "  track      — Updates phase-state.json, re-resolves tools"
      echo "  name       — Updates phase-state.json, CLAUDE.md, Qdrant collection"
      echo "  deployment — Updates phase-state.json, approval log"
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

    track)
      # Update phase-state.json
      if [ -f ".claude/phase-state.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$NEW_VALUE" '.track = $v' ".claude/phase-state.json" > "$tmp" && mv "$tmp" ".claude/phase-state.json"
        print_ok "Updated track in phase-state.json"
      fi

      # Update tool-preferences.json
      if [ -f ".claude/tool-preferences.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$NEW_VALUE" '.context.track = $v' ".claude/tool-preferences.json" > "$tmp" && mv "$tmp" ".claude/tool-preferences.json"
        print_ok "Updated track in tool-preferences.json"
      fi

      print_info "Track changed to $NEW_VALUE. Tool requirements may have changed."
      print_info "Run: bash scripts/check-phase-gate.sh to verify tool coverage."
      ;;

    name)
      local old_name="$OLD_VALUE"
      local new_name="$NEW_VALUE"

      if [ -z "$old_name" ]; then
        print_fail "Renaming requires --old <current_name>"
        exit 1
      fi

      # Update phase-state.json
      if [ -f ".claude/phase-state.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$new_name" '.project = $v' ".claude/phase-state.json" > "$tmp" && mv "$tmp" ".claude/phase-state.json"
        print_ok "Updated project name in phase-state.json"
      fi

      # Update Qdrant collection in settings.local.json
      if [ -f ".claude/settings.local.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$new_name" '.mcpServers.qdrant.args[-1] = $v' ".claude/settings.local.json" > "$tmp" && mv "$tmp" ".claude/settings.local.json"
        print_ok "Updated Qdrant collection to $new_name"
      fi

      # Update CLAUDE.md project name
      if [ -f "CLAUDE.md" ]; then
        sed -i.bak "s|$old_name|$new_name|g" CLAUDE.md
        rm -f CLAUDE.md.bak
        print_ok "Updated project name in CLAUDE.md"
      fi

      # Update PROJECT_INTAKE.md
      if [ -f "PROJECT_INTAKE.md" ]; then
        sed -i.bak "s|$old_name|$new_name|g" PROJECT_INTAKE.md
        rm -f PROJECT_INTAKE.md.bak
        print_ok "Updated project name in PROJECT_INTAKE.md"
      fi
      ;;

    deployment)
      # Update phase-state.json
      if [ -f ".claude/phase-state.json" ] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg v "$NEW_VALUE" '.deployment = $v' ".claude/phase-state.json" > "$tmp" && mv "$tmp" ".claude/phase-state.json"
        print_ok "Updated deployment in phase-state.json"
      fi

      if [ "$NEW_VALUE" = "organizational" ] && [ "$OLD_VALUE" = "personal" ]; then
        print_warn "Switching to organizational deployment. You may need to:"
        echo "  1. Complete governance pre-conditions (Section 8 of Intake)"
        echo "  2. Regenerate APPROVAL_LOG.md with organizational template"
        echo "  3. Review CLAUDE.md for organizational governance sections"
      elif [ "$NEW_VALUE" = "personal" ] && [ "$OLD_VALUE" = "organizational" ]; then
        print_info "Switched to personal deployment. Governance requirements relaxed."
      fi
      ;;

    *)
      print_fail "Unknown field: $FIELD"
      echo "Supported: language, platform, track, name, deployment"
      exit 1
      ;;
  esac

  echo ""
  print_ok "Reconfiguration complete."
  print_info "Review the changed files and commit when ready."
}

reconfigure

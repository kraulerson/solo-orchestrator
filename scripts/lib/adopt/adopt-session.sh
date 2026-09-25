#!/usr/bin/env bash
# scripts/lib/adopt/adopt-session.sh — WP9c: the Claude Code session layer an
# adopted project receives.
#
# SPEC: ADOPT-002-ARCH v2.2 §10-WP9c (§8.7a rows 18–21). A scaffolded project
# gets, from init.sh: the permissions in .claude/settings.json, the framework's
# session-hook roster registered in it, the four vendored skills, and — when a
# Qdrant server is available — a project-local MCP declaration. An adopted one
# got none of these, so a Claude Code session in it ran without the framework's
# hooks. This stage gives it the same layer, from the SAME code: every piece
# comes from scripts/lib/claude-settings.sh, which init.sh now calls too.
#
# COMPOSED, NEVER OVERWRITTEN (M11). An adoptee's own settings.json keeps every
# key it had; the framework's permission rules are UNIONED into `allow` and
# `deny`, and its hooks are added only where absent (the roster's own
# idempotent idiom). The original is in the adoption archive regardless.
#
# THE ONE DIFFERENCE FROM GREENFIELD, ON PURPOSE: the bypass detector's
# PostToolUse arm is not registered on an adopted project while `## BL-277:`
# is open (`# BL-242-SETTINGS-BL277`); its Stop arm is. The run says so.

# _adopt_session_language REPORT — Scout's dominant language, lowercased.
_adopt_session_language() {
  adopt_report_read "$1" '.stack.languages[0].name // ""' | tr '[:upper:]' '[:lower:]'
}

# _adopt_session_qdrant — init.sh's predicate: an MCP entry already registered,
# or a Qdrant container running with uvx to launch the server. Read in a
# SUBSHELL so helpers-full.sh's definitions never leak into the driver.
# `SOIF_ADOPT_QDRANT=yes|no` is a TEST SEAM: no suite may start a container.
_adopt_session_qdrant() {
  case "${SOIF_ADOPT_QDRANT:-}" in yes) return 0 ;; no) return 1 ;; esac
  ( . "$ADOPT_CORE_LIB_DIR/helpers-full.sh" >/dev/null 2>&1 || exit 1
    is_qdrant_mcp_entry_present && exit 0
    is_qdrant_container_running && command -v uvx >/dev/null 2>&1 ) >/dev/null 2>&1
}

adopt_write_session_layer() {                          # BL-242-SESSION-STAGE
  local root="$1" report="$2" fw="$ADOPT_FRAMEWORK_ROOT" lang rel="$ADOPT_SESSION_SETTINGS_REL"
  local base s out
  ADOPT_SESSION_SKIPPED=""
  command -v jq >/dev/null 2>&1 || { adopt_refuse "jq is required to compose the session settings"; return 1; }
  adopt_head "The Claude Code session layer"
  lang="$(_adopt_session_language "$report")"
  base="$(soif_claude_settings_json "$lang")"

  # ── .claude/settings.json: written when absent, composed when present ──────
  if [ -L "$root/$rel" ] || adopt_path_under_link "$root" "$rel"; then
    adopt_note "$rel is a symlink, or inside one; it was left alone, so the framework's session"
    adopt_note "settings and hooks are NOT in place. Compose them by hand from a scaffolded project."
  elif [ ! -e "$root/$rel" ]; then
    printf '%s\n' "$base" | adopt_write_file "$root" "$rel" || return 1
    adopt_note "Wrote $rel with the framework's permissions."
  elif ! jq -e 'type == "object" and ((.permissions == null) or ((.permissions | type) == "object")) and ((.hooks == null) or ((.hooks | type) == "object"))' "$root/$rel" >/dev/null 2>&1; then   # BL-242-SESSION-COMPOSABLE
    # Not a shape the framework can compose into — not JSON, or `permissions`
    # / `hooks` that are not objects. Left alone and SAID, never forced: the
    # first cut refused the whole adoption over a string `permissions`, and
    # with an array `hooks` it composed the rules, failed the roster silently,
    # and printed that the hooks were registered.
    adopt_note "$rel is not in a shape the framework can compose into (it must be a JSON object"
    adopt_note "whose permissions and hooks, where present, are objects). It was left alone, so the"
    adopt_note "framework's permissions and session hooks are NOT in place. Your original is in the archive."
    ADOPT_SESSION_SKIPPED=1
  else
    # UNION, theirs first, nothing of theirs removed or reordered.
    adopt_jq_edit "$root" "$rel" '
      .permissions = ((.permissions // {})
        | .allow = (((.allow // []) + ($b.permissions.allow - (.allow // []))))
        | .deny  = (((.deny  // []) + ($b.permissions.deny  - (.deny  // [])))))' \
      --argjson b "$base" || return 1   # BL-242-SESSION-COMPOSE
    adopt_note "Composed the framework's permission rules into your $rel; nothing of yours was removed."
  fi
  if [ -z "${ADOPT_SESSION_SKIPPED:-}" ] && [ -f "$root/$rel" ] && [ ! -L "$root/$rel" ] && ! adopt_path_under_link "$root" "$rel"; then
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    soif_register_hook_roster "$root/$rel" adoption   # BL-242-SESSION-ROSTER
    jq -e 'type == "object"' "$root/$rel" >/dev/null 2>&1 \
      || { adopt_refuse "registering the session hooks left $rel unreadable"; return 1; }
    adopt_record_write "$rel"
    # THE RECEIPT, not the call: the roster's jq edits fail quietly by design
    # (`&& mv`), so "registered" is said only when a hook is actually there.
    if jq -e '[.hooks.SessionStart[]?.hooks[]?.command] | any(test("session-version-check.sh"))' "$root/$rel" >/dev/null 2>&1; then   # BL-242-SESSION-ROSTER-RECEIPT
      adopt_note "Registered the framework's session hooks. The bypass detector's per-tool arm is"
      adopt_note "not registered on adopted projects until BL-277 closes; its end-of-session arm is."
    else
      adopt_note "The framework's session hooks could NOT be registered in $rel — its hooks section"
      adopt_note "did not take them. The permissions are in place; add the hooks from a scaffolded project."
    fi
  fi

  # ── the vendored skills: framework-wins, theirs archived ──────────────────
  for s in $(soif_vendored_skills); do
    [ -f "$fw/templates/generated/skills/$s/SKILL.md" ] || continue
    out="$(_adopt_doc_put "$root" ".claude/skills/$s/SKILL.md" "$fw/templates/generated/skills/$s/SKILL.md")" || return 1
    case "$out" in kept-*) adopt_note ".claude/skills/$s/SKILL.md was left alone (${out#kept-}); the framework's skill is NOT in place." ;; esac
    if [ -f "$fw/templates/generated/skills/$s/NOTICE" ] && [ ! -e "$root/.claude/skills/$s/NOTICE" ]; then
      _adopt_doc_put "$root" ".claude/skills/$s/NOTICE" "$fw/templates/generated/skills/$s/NOTICE" >/dev/null || return 1
    fi
  done
  adopt_note "Installed the framework's skills: $(soif_vendored_skills | tr '\n' ' ')"

  # ── the MCP declaration, as init.sh writes it, and only where it would ────
  if _adopt_session_qdrant; then
    if [ ! -e "$root/.claude/settings.local.json" ] && [ ! -L "$root/.claude/settings.local.json" ]; then
      # MACHINE-LOCAL, NOT COMMITTED — as in init.sh: Claude Code puts this file
      # in the user's global git excludes, so it is written and deliberately
      # NOT recorded for staging (recording it made the staging preflight
      # refuse the whole adoption over an ignored path). The requirement a
      # clone can see goes into the manifest below.
      adopt_touched_disk   # BL-225-TOUCHED-DISK
      jq -n --arg c "${ADOPT_PROJECT_NAME:-project}" '{mcpServers: {qdrant: {command: "uvx",
          args: ["mcp-server-qdrant", "--qdrant-url", "http://localhost:6333", "--collection-name", $c]}}}' \
        > "$root/.claude/settings.local.json" \
        || { adopt_refuse "could not write .claude/settings.local.json"; return 1; }   # BL-242-SESSION-MCP
      adopt_jq_edit "$root" ".claude/manifest.json" '.mcp = ((.mcp // {}) | .qdrant_required = true)' || return 1
      adopt_note "Qdrant is available: wrote .claude/settings.local.json (collection ${ADOPT_PROJECT_NAME:-project})"
      adopt_note "and recorded the requirement in .claude/manifest.json."
    else
      adopt_note "Qdrant is available, but you already have .claude/settings.local.json; it was left"
      adopt_note "alone, so no project collection was declared."
    fi
  else
    adopt_note "No Qdrant server was found, so no MCP declaration was written — as init.sh does."
  fi
  return 0
}
ADOPT_SESSION_SETTINGS_REL=".claude/settings.json"

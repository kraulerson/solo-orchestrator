#!/usr/bin/env bash
# scripts/lib/claude-settings.sh — the Claude Code session layer a project
# gets: the permissions in .claude/settings.json, the framework's hook roster,
# and the vendored skills. SHARED by init.sh and by the adoption driver, so a
# scaffolded project and an adopted one get the same session layer from ONE
# spelling (ADOPT-002-ARCH v2.2 §10-WP9c; the `# BL-243-HOOK-TEMPLATE` and
# render-project-docs.sh precedent of extracting a writer init.sh had inline).
#
# MOVED, NOT REWRITTEN: every rule, every hook command and every idempotent jq
# idiom below is init.sh's own, lifted verbatim. The edits: the file path
# became a parameter; the language became an argument; the permissions writer
# was split in two and prints to stdout (init.sh redirects it); and the one
# adoption-only guard (`# BL-242-SETTINGS-BL277`). Review measured the result
# byte-identical to main's inline code across 12 languages and 8 roster
# starting states, idempotent re-runs included.
#
# bash-3.2 safe. Needs jq for the roster (the caller checks, as init.sh did).

# soif_vendored_skills — the skills init.sh vendors into .claude/skills/, one
# per line. Adding a skill: drop it under templates/generated/skills/<name>/
# and add its name here.
soif_vendored_skills() {
  printf '%s\n' session-handoff sweep-triage zoom-out grill-with-docs
}

# soif_claude_lang_rules LANGUAGE — the language-specific `allow` rules, as the
# JSON array lines the settings template splices in.
soif_claude_lang_rules() {
  local lang_rules=""
  case "$1" in
    typescript|javascript)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(npm install *)",
      "Bash(npm ci)",
      "Bash(npm run *)",
      "Bash(npm test *)",
      "Bash(npm outdated)",
      "Bash(npx *)",
      "Bash(node *)",
      "Bash(tsc *)",
      "Bash(eslint *)",
      "Bash(prettier *)",
LANGEOF
) ;;
    python)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(pip install *)",
      "Bash(pip list *)",
      "Bash(pip show *)",
      "Bash(pip freeze *)",
      "Bash(python -m pip *)",
      "Bash(python -m pytest *)",
      "Bash(python -m unittest *)",
      "Bash(pytest *)",
      "Bash(python *)",
      "Bash(python3 *)",
      "Bash(mypy *)",
      "Bash(ruff *)",
      "Bash(black *)",
LANGEOF
) ;;
    rust)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(cargo build *)",
      "Bash(cargo test *)",
      "Bash(cargo run *)",
      "Bash(cargo check *)",
      "Bash(cargo clippy *)",
      "Bash(cargo fmt *)",
      "Bash(cargo add *)",
      "Bash(cargo audit *)",
      "Bash(rustc *)",
LANGEOF
) ;;
    go)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(go build *)",
      "Bash(go test *)",
      "Bash(go run *)",
      "Bash(go mod *)",
      "Bash(go vet *)",
      "Bash(go fmt *)",
      "Bash(golangci-lint *)",
LANGEOF
) ;;
    csharp)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(dotnet build *)",
      "Bash(dotnet test *)",
      "Bash(dotnet run *)",
      "Bash(dotnet restore *)",
      "Bash(dotnet add *)",
      "Bash(dotnet format *)",
LANGEOF
) ;;
    kotlin|java)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(./gradlew *)",
      "Bash(gradle *)",
      "Bash(mvn *)",
      "Bash(java *)",
      "Bash(javac *)",
      "Bash(kotlinc *)",
LANGEOF
) ;;
    dart)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(flutter *)",
      "Bash(dart *)",
      "Bash(dart pub *)",
      "Bash(flutter pub *)",
      "Bash(flutter test *)",
      "Bash(flutter build *)",
      "Bash(flutter analyze *)",
LANGEOF
) ;;
    swift)
      lang_rules=$(cat <<'LANGEOF'
      "Bash(swift build *)",
      "Bash(swift test *)",
      "Bash(swift package *)",
      "Bash(swiftlint *)",
      "Bash(xcodebuild *)",
LANGEOF
) ;;
  esac

  printf '%s' "$lang_rules"
}

# soif_claude_settings_json LANGUAGE — .claude/settings.json's content for a
# new project: the permissions block, on stdout.
soif_claude_settings_json() {
  local lang_rules=""
  lang_rules="$(soif_claude_lang_rules "$1")"
  cat << PERMEOF
{
  "permissions": {
    "allow": [
      "Read",
      "Edit",
      "Write",
      "Glob",
      "Grep",
      "Bash",
$lang_rules
      "WebFetch(domain:*)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(curl * | bash)",
      "Bash(wget * | bash)",
      "Read(./.env)",
      "Read(./.env.*)"
    ]
  }
}
PERMEOF
}

# soif_register_hook_roster FILE [MODE] — register the framework's session
# hooks in FILE, idempotently (a hook already present is not added twice).
# MODE "adoption" leaves the bypass detector's PostToolUse arm off
# (`## BL-277:`). Sets SOIF_ROSTER_ADDED=true when anything was added.
soif_register_hook_roster() {
  local _f="$1" _mode="${2:-init}"
  SOIF_ROSTER_ADDED=false
        local hooks_added=false
        # Add version check hook
        if jq -e '.hooks.SessionStart' "$_f" >/dev/null 2>&1; then
          if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-version-check.sh"))' "$_f" >/dev/null 2>&1; then
            jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]' "$_f" > "$_f.tmp" \
              && mv "$_f.tmp" "$_f"
            hooks_added=true
          fi
        else
          jq '.hooks.SessionStart = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi
        # Add test gate check hook
        if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-test-gate-check.sh"))' "$_f" >/dev/null 2>&1; then
          jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-test-gate-check.sh"}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi
        # BL-109 S2: freshness check hook (Currency System, Layer 1 — detection).
        # Silent-when-current, zero-network, fail-open (exit 0 always), writes only
        # .claude/cache/. Injected exactly like session-version-check.sh above.
        if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-freshness-check.sh"))' "$_f" >/dev/null 2>&1; then
          jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-freshness-check.sh"}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi
        # BL-202-INTAKE-HOOK-BEGIN — intake/Phase-0 onboarding state on every
        # launch surface (desktop/IDE included, where terminal prints cannot
        # reach). Silent when healthy; the agent relays. Injected exactly like
        # the three hooks above; fenced so the registration is excisable for
        # mutation proofs without touching its siblings.
        if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-intake-check.sh"))' "$_f" >/dev/null 2>&1; then
          jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-intake-check.sh"}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi
        # BL-202-INTAKE-HOOK-END
        # CADENCE-NAG-HOOK-BEGIN — the maintenance-cadence nag (design v1 §8.3's
        # SessionStart enforcement point, the soft half of the pair whose hard
        # half is the release cut). Silent when every cadence is current,
        # zero-network, fail-open (exit 0 under every failure mode). Injected
        # exactly like the four hooks above; fenced so the registration is
        # excisable for a mutation proof without touching its siblings.
        if ! jq -e '.hooks.SessionStart[0].hooks[] | select(.command | contains("session-cadence-check.sh"))' "$_f" >/dev/null 2>&1; then
          jq '.hooks.SessionStart[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-cadence-check.sh"}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi
        # CADENCE-NAG-HOOK-END
        # Add Qdrant reminder to Stop hook
        if jq -e '.hooks.Stop' "$_f" >/dev/null 2>&1; then
          if ! jq -e '.hooks.Stop[0].hooks[] | select(.command | contains("session-end-qdrant-reminder.sh"))' "$_f" >/dev/null 2>&1; then
            jq '.hooks.Stop[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-end-qdrant-reminder.sh"}]' "$_f" > "$_f.tmp" \
              && mv "$_f.tmp" "$_f"
            hooks_added=true
          fi
        else
          jq '.hooks.Stop = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-end-qdrant-reminder.sh"}]}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi

        # Add pre-commit gate to PreToolUse hook (must target Bash matcher group)
        if jq -e '.hooks.PreToolUse' "$_f" >/dev/null 2>&1; then
          if ! jq -e '.hooks.PreToolUse[]? | .hooks[]? | select(.command | contains("pre-commit-gate.sh"))' "$_f" >/dev/null 2>&1; then
            # Find the Bash matcher group index, or create a new one
            BASH_INDEX=$(jq '[.hooks.PreToolUse[] | .matcher // "none"] | to_entries[] | select(.value == "Bash") | .key' "$_f" 2>/dev/null | head -1 || echo "")
            if [ -n "$BASH_INDEX" ]; then
              jq ".hooks.PreToolUse[$BASH_INDEX].hooks += [{\"type\": \"command\", \"command\": \"bash \\\"\$CLAUDE_PROJECT_DIR\\\"/scripts/pre-commit-gate.sh\"}]" "$_f" > "$_f.tmp" \
                && mv "$_f.tmp" "$_f"
            else
              # No Bash matcher group exists — create one
              jq '.hooks.PreToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}]' "$_f" > "$_f.tmp" \
                && mv "$_f.tmp" "$_f"
            fi
            hooks_added=true
          fi
        else
          jq '.hooks.PreToolUse = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi

        # Add MCP session gate to PreToolUse hook (targets Write and Edit)
        # This blocks file modifications until required MCP tools (qdrant-find, context7)
        # have been called — closing the session-start enforcement gap.
        for GATE_TOOL in Write Edit; do
          if ! jq -e ".hooks.PreToolUse[]? | select(.matcher == \"$GATE_TOOL\") | .hooks[]? | select(.command | contains(\"session-mcp-gate.sh\"))" "$_f" >/dev/null 2>&1; then
            # Check if a matcher group for this tool already exists
            GATE_INDEX=$(jq "[.hooks.PreToolUse[] | .matcher // \"none\"] | to_entries[] | select(.value == \"$GATE_TOOL\") | .key" "$_f" 2>/dev/null | head -1 || echo "")
            if [ -n "$GATE_INDEX" ]; then
              jq ".hooks.PreToolUse[$GATE_INDEX].hooks += [{\"type\": \"command\", \"command\": \"bash \\\"\$CLAUDE_PROJECT_DIR\\\"/scripts/session-mcp-gate.sh\"}]" "$_f" > "$_f.tmp" \
                && mv "$_f.tmp" "$_f"
            else
              jq ".hooks.PreToolUse += [{\"matcher\": \"$GATE_TOOL\", \"hooks\": [{\"type\": \"command\", \"command\": \"bash \\\"\$CLAUDE_PROJECT_DIR\\\"/scripts/session-mcp-gate.sh\"}]}]" "$_f" > "$_f.tmp" \
                && mv "$_f.tmp" "$_f"
            fi
            hooks_added=true
          fi
        done

        # Add tool usage tracking to PostToolUse hook.
        #
        # BL-233: registered on PostToolUse ALONE, this tracker never saw a
        # failure. A failed MCP call fires PostToolUseFailure and NOT
        # PostToolUse (measured 2026-08-13 with a probe on both events), so
        # failures were not miscounted by the framework — they were INVISIBLE
        # to it, and a call that reached nothing left the same trace as no call
        # at all. Both events are registered, each passing its own --event
        # argument so the tracker can score the outcome without depending on a
        # payload field, and can refuse to guess when the two disagree.
        if jq -e '.hooks.PostToolUse' "$_f" >/dev/null 2>&1; then
          if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("track-tool-usage.sh"))' "$_f" >/dev/null 2>&1; then
            jq '.hooks.PostToolUse[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh --event PostToolUse"}]' "$_f" > "$_f.tmp" \
              && mv "$_f.tmp" "$_f"
            hooks_added=true
          fi
        else
          jq '.hooks.PostToolUse = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh --event PostToolUse"}]}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi

        # Add the SAME tracker to PostToolUseFailure — the event a failing MCP
        # call actually fires.
        if jq -e '.hooks.PostToolUseFailure' "$_f" >/dev/null 2>&1; then
          if ! jq -e '.hooks.PostToolUseFailure[0].hooks[] | select(.command | contains("track-tool-usage.sh"))' "$_f" >/dev/null 2>&1; then
            jq '.hooks.PostToolUseFailure[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh --event PostToolUseFailure"}]' "$_f" > "$_f.tmp" \
              && mv "$_f.tmp" "$_f"
            hooks_added=true
          fi
        else
          jq '.hooks.PostToolUseFailure = [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/track-tool-usage.sh --event PostToolUseFailure"}]}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi

        # BL-029: bypass-detector PostToolUse + Stop. Always-on, regardless
        # of enforcement_level — Claude-side audit channel is non-configurable.
        # THE PostToolUse ARM IS GREENFIELD-ONLY FOR NOW (`## BL-277:`): on an
        # adopted project it stays OFF until that entry closes, and the
        # adoption transcript says so. ONE guarded line, as §10-WP9c specifies.
        if [ "$_mode" != "adoption" ]; then   # BL-242-SETTINGS-BL277
          if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("bypass-detector.sh"))' "$_f" >/dev/null 2>&1; then
            jq '.hooks.PostToolUse[0].hooks += [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]' "$_f" > "$_f.tmp" \
              && mv "$_f.tmp" "$_f"
            hooks_added=true
          fi
        fi
        if ! jq -e '.hooks.Stop[0].hooks[]? | select(.command | contains("bypass-detector.sh"))' "$_f" >/dev/null 2>&1; then
          jq 'if (.hooks.Stop // []) | length == 0
              then .hooks.Stop = [{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]
              else .hooks.Stop[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]
              end' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi

        # BL-030: PostToolUse hook for the Claude-commit recorder
        # (always-on). Records SHA of every successful Claude-issued
        # git commit into .claude/claude-commits.jsonl.
        if ! jq -e '.hooks.PostToolUse[0].hooks[] | select(.command | contains("record-claude-commit.sh"))' "$_f" >/dev/null 2>&1; then
          jq '.hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/record-claude-commit.sh"}]' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi

        # BL-030: SessionStart hook for the out-of-band detector. Self-
        # no-ops when enforcement_level=no; runs on light + strict to
        # surface user-terminal commits in .claude/bypass-audit.json.
        if ! jq -e '.hooks.SessionStart[0].hooks[]? | select(.command | contains("detect-out-of-band-commits.sh"))' "$_f" >/dev/null 2>&1; then
          jq 'if (.hooks.SessionStart // []) | length == 0
              then .hooks.SessionStart = [{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/detect-out-of-band-commits.sh"}]}]
              else .hooks.SessionStart[0].hooks += [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/detect-out-of-band-commits.sh"}]
              end' "$_f" > "$_f.tmp" \
            && mv "$_f.tmp" "$_f"
          hooks_added=true
        fi

        SOIF_ROSTER_ADDED="$hooks_added"
}

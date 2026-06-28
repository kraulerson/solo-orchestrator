#!/usr/bin/env bash
# tests/test-reconfigure-field-handlers.sh — closes S3 findings:
#
#   code-verify-reconfigure-3 — `--field track` and `--field deployment`
#     are back-doors around upgrade-project.sh's governance pre-conditions
#     (baseline §4 lines 431-434: reconfigure "is not a tier/POC upgrade
#     path and does not change `deployment`, `track`, or `poc_mode`").
#
#   code-verify-reconfigure-4 — `--field deployment` claims (help text +
#     user-guide.md:1336) to "Update ... approval log" but never touches
#     APPROVAL_LOG.md. Personal→organizational reconfigure leaves the
#     project with the wrong (column-missing) personal template while
#     phase-state reports organizational.
#
#   code-verify-reconfigure-5 — `--field name --old foo --new bar` updates
#     phase-state.json + CLAUDE.md + PROJECT_INTAKE.md but does not touch
#     APPROVAL_LOG.md (which carries `project: __PROJECT_NAME__` in its
#     YAML header + `# Approval Log — __PROJECT_NAME__`) or
#     .claude/intake-progress.json (which carries `.project_name`).
#
# Fix (this PR):
#   * --field track and --field deployment now exit non-zero with a
#     redirect to scripts/upgrade-project.sh (Option A from the finding;
#     re-aligns the script with baseline §4 and eliminates the back-door).
#   * --field name now also updates APPROVAL_LOG.md (anchored to the YAML
#     front-matter + the exact H1 — never touches historical entries, so
#     invariant 8 append-only is preserved) and .claude/intake-progress.json.
#   * APPROVAL_LOG + intake-progress mutations are inside the same
#     snapshot/rollback envelope as the existing phase-state / CLAUDE.md /
#     PROJECT_INTAKE.md / settings.local.json writes — PR #57 sibling
#     pattern. Failure mid-rename restores all files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECONFIG="$REPO_ROOT/scripts/reconfigure-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a minimal fixture project that looks plausible to reconfigure-project.sh.
# We bypass init.sh (and its --non-interactive cost) by hand-rolling the
# files reconfigure actually reads/writes. PROJECT_ROOT inside the script
# is derived from `dirname $0/..`, so the script must be invoked from
# *inside* the fixture's `scripts/` dir — we copy the framework's
# reconfigure-project.sh + its lib/helpers.sh into the fixture so the
# script's self-detection lands inside the test fixture rather than the
# framework repo.
mk_fixture() {
  local dir="$1" name="$2" deployment="${3:-personal}" track="${4:-light}"

  mkdir -p "$dir/.claude" "$dir/scripts/lib"

  # Copy the script under test + its required helpers into the fixture.
  cp "$REPO_ROOT/scripts/reconfigure-project.sh" "$dir/scripts/reconfigure-project.sh"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" "$dir/scripts/lib/helpers.sh"
  # enforcement-level.sh is sourced when --enforcement-level is passed;
  # copied defensively so the script doesn't bail on missing files even
  # though the field handlers we're testing never hit that code path.
  if [ -f "$REPO_ROOT/scripts/lib/enforcement-level.sh" ]; then
    cp "$REPO_ROOT/scripts/lib/enforcement-level.sh" "$dir/scripts/lib/enforcement-level.sh"
  fi

  # phase-state.json — reconfigure reads .project / .deployment / .track from here.
  cat > "$dir/.claude/phase-state.json" <<JSON
{
  "project": "$name",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$track",
  "deployment": "$deployment",
  "poc_mode": null
}
JSON

  # tool-preferences.json — reconfigure track/language branches write .context.*.
  cat > "$dir/.claude/tool-preferences.json" <<JSON
{
  "context": {
    "project": "$name",
    "platform": "web",
    "language": "javascript",
    "track": "$track"
  }
}
JSON

  # orchestrator-source.json — required pointer to template directory.
  cat > "$dir/.claude/orchestrator-source.json" <<JSON
{ "source_dir": "$REPO_ROOT" }
JSON

  # intake-progress.json — carries .project_name (intake-wizard.sh:259).
  cat > "$dir/.claude/intake-progress.json" <<JSON
{
  "version": 1,
  "project_name": "$name",
  "platform": "web",
  "track": "$track",
  "deployment": "$deployment",
  "language": "javascript",
  "answers": {}
}
JSON

  # settings.local.json — reconfigure name branch writes Qdrant collection arg.
  cat > "$dir/.claude/settings.local.json" <<JSON
{
  "mcpServers": {
    "qdrant": {
      "command": "uvx",
      "args": ["mcp-server-qdrant", "$name"]
    }
  }
}
JSON

  # CLAUDE.md — reconfigure name branch sed-substitutes.
  cat > "$dir/CLAUDE.md" <<MD
# $name — Claude Operator Brief

Project: $name
MD

  # PROJECT_INTAKE.md — reconfigure name branch sed-substitutes.
  cat > "$dir/PROJECT_INTAKE.md" <<MD
# Project Intake — $name
MD

  # APPROVAL_LOG.md — render the personal template substituting __PROJECT_NAME__.
  # Seed an existing dated entry to verify it's preserved verbatim by --field name
  # (invariant 8: APPROVAL_LOG is append-only).
  sed -e "s|__PROJECT_NAME__|$name|g" -e "s|__TODAY__|2026-06-01|g" \
    "$REPO_ROOT/templates/generated/approval-log-personal.tmpl" \
    > "$dir/APPROVAL_LOG.md"
  # Append a real dated entry under Approval History so we can prove
  # historical entries are not touched.
  cat >> "$dir/APPROVAL_LOG.md" <<APP
| 2026-06-15 | Phase 0 → Phase 1 | Approved | Bible reviewed |
APP

  # Git init so finalize_reconfigure_commit() can do its work.
  ( cd "$dir" \
      && git init -q \
      && git config user.email t@t.l \
      && git config user.name t \
      && git add -A \
      && git commit -q -m "fixture" ) >/dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: --field track is refused with redirect to upgrade-project.sh ==="
# ════════════════════════════════════════════════════════════════════
T=$(mktemp -d); P="$T/p"
mk_fixture "$P" "foo" "personal" "light"
track_before=$(jq -r '.track' "$P/.claude/phase-state.json")
tp_track_before=$(jq -r '.context.track' "$P/.claude/tool-preferences.json")

if ( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --field track --old light --new standard > "$T/log" 2>&1 ); then
  fail_ "T1" "reconfigure --field track should have exited non-zero (back-door around upgrade-project.sh governance)"
else
  if grep -q "upgrade-project.sh" "$T/log"; then
    track_after=$(jq -r '.track' "$P/.claude/phase-state.json")
    tp_track_after=$(jq -r '.context.track' "$P/.claude/tool-preferences.json")
    if [ "$track_before" = "$track_after" ] && [ "$tp_track_before" = "$tp_track_after" ]; then
      pass "T1"
    else
      fail_ "T1" "phase-state.json or tool-preferences.json mutated despite refusal (state-leak)"
    fi
  else
    fail_ "T1" "error message did not redirect to upgrade-project.sh"
  fi
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: --field deployment is refused with redirect to upgrade-project.sh ==="
# ════════════════════════════════════════════════════════════════════
T=$(mktemp -d); P="$T/p"
mk_fixture "$P" "foo" "personal" "light"
dep_before=$(jq -r '.deployment' "$P/.claude/phase-state.json")
approval_sha_before=$(shasum -a 256 "$P/APPROVAL_LOG.md" | awk '{print $1}')

if ( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --field deployment --old personal --new organizational > "$T/log" 2>&1 ); then
  fail_ "T2" "reconfigure --field deployment should have exited non-zero"
else
  if grep -q "upgrade-project.sh" "$T/log"; then
    dep_after=$(jq -r '.deployment' "$P/.claude/phase-state.json")
    approval_sha_after=$(shasum -a 256 "$P/APPROVAL_LOG.md" | awk '{print $1}')
    if [ "$dep_before" = "$dep_after" ] && [ "$approval_sha_before" = "$approval_sha_after" ]; then
      pass "T2"
    else
      fail_ "T2" "phase-state.json or APPROVAL_LOG.md mutated despite refusal"
    fi
  else
    fail_ "T2" "error message did not redirect to upgrade-project.sh"
  fi
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: --help no longer advertises track or deployment ==="
# ════════════════════════════════════════════════════════════════════
# Run --help from inside a fixture so guard_not_in_framework passes.
T=$(mktemp -d); P="$T/p"
mk_fixture "$P" "foo" "personal" "light"
help_out=$( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --help 2>&1 )
# grep -c returns the integer count and exits 0 even on zero matches
# (regular-file input), so no `|| echo 0` antipattern needed. The
# sanitizer cases below convert any pathological non-numeric output to
# 0 — matches lint-counter-antipattern's PASS-marker.
track_advertised=$(printf '%s\n' "$help_out" | grep -cE '^[[:space:]]*track[[:space:]]+—' || true)
case "$track_advertised" in '' | *[!0-9]* ) track_advertised=0 ;; esac
deployment_advertised=$(printf '%s\n' "$help_out" | grep -cE '^[[:space:]]*deployment[[:space:]]+—' || true)
case "$deployment_advertised" in '' | *[!0-9]* ) deployment_advertised=0 ;; esac
if [ "$track_advertised" = "0" ] && [ "$deployment_advertised" = "0" ]; then
  pass "T3"
else
  fail_ "T3" "track_advertised=$track_advertised deployment_advertised=$deployment_advertised"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: --field name updates APPROVAL_LOG.md YAML header + H1 ==="
# ════════════════════════════════════════════════════════════════════
T=$(mktemp -d); P="$T/p"
mk_fixture "$P" "foo" "personal" "light"

if ( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --field name --old foo --new bar > "$T/log" 2>&1 ); then
  yaml_project=$(grep -m1 '^project:' "$P/APPROVAL_LOG.md" | sed 's/^project:[[:space:]]*//')
  h1_line=$(grep -m1 '^# Approval Log' "$P/APPROVAL_LOG.md")
  if [ "$yaml_project" = "bar" ] && [ "$h1_line" = "# Approval Log — bar" ]; then
    pass "T4"
  else
    fail_ "T4" "yaml_project='$yaml_project' h1='$h1_line'"
  fi
else
  fail_ "T4" "reconfigure --field name failed: $(tail -5 "$T/log" 2>/dev/null)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: --field name updates .claude/intake-progress.json ==="
# ════════════════════════════════════════════════════════════════════
T=$(mktemp -d); P="$T/p"
mk_fixture "$P" "foo" "personal" "light"

if ( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --field name --old foo --new bar > "$T/log" 2>&1 ); then
  intake_name=$(jq -r '.project_name' "$P/.claude/intake-progress.json")
  if [ "$intake_name" = "bar" ]; then
    pass "T5"
  else
    fail_ "T5" "intake-progress.json .project_name='$intake_name' (expected 'bar')"
  fi
else
  fail_ "T5" "reconfigure --field name failed"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: --field name preserves prior dated APPROVAL_LOG entries ==="
# ════════════════════════════════════════════════════════════════════
T=$(mktemp -d); P="$T/p"
mk_fixture "$P" "foo" "personal" "light"
# Capture the seeded entry from mk_fixture.
seeded_entry='| 2026-06-15 | Phase 0 → Phase 1 | Approved | Bible reviewed |'
if ! grep -qF "$seeded_entry" "$P/APPROVAL_LOG.md"; then
  fail_ "T6" "seeded entry missing from fixture — test setup bug"
elif ( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --field name --old foo --new bar > "$T/log" 2>&1 ); then
  if grep -qF "$seeded_entry" "$P/APPROVAL_LOG.md"; then
    pass "T6"
  else
    fail_ "T6" "historical entry mutated/dropped — invariant 8 violation"
  fi
else
  fail_ "T6" "reconfigure --field name failed"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: --field name still updates phase-state.json + CLAUDE.md ==="
# ════════════════════════════════════════════════════════════════════
# Regression guard — the existing name-branch behaviors must continue to work.
T=$(mktemp -d); P="$T/p"
mk_fixture "$P" "foo" "personal" "light"
if ( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --field name --old foo --new bar > "$T/log" 2>&1 ); then
  ps_name=$(jq -r '.project' "$P/.claude/phase-state.json")
  claude_has_bar=0
  grep -q "bar" "$P/CLAUDE.md" && claude_has_bar=1
  if [ "$ps_name" = "bar" ] && [ "$claude_has_bar" = "1" ]; then
    pass "T7"
  else
    fail_ "T7" "ps_name='$ps_name' claude_has_bar=$claude_has_bar"
  fi
else
  fail_ "T7" "reconfigure --field name failed"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Results ==="
# ════════════════════════════════════════════════════════════════════
echo "  passed: $PASSED"
echo "  failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

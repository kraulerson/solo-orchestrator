#!/usr/bin/env bash
# scripts/install-filesystem-gates.sh — BL-030 strict-mode hook installer.
#
# Idempotently adds (or removes) a marked block in .git/hooks/pre-commit
# that sources .git/hooks/framework-gate.sh. Composes with existing chains
# (gitleaks/Semgrep/TDD) without modifying them.
#
# BL-112: this block is APPENDED BELOW the SOIF pre-commit fallback's managed
# region on purpose (BL-099 refreshes that region in place and must not clobber
# this block). That only works because the fallback's terminal exit is CONDITIONAL
# — see `# BL-112-STRICT-GATE` in scripts/lib/hook-templates.sh. An unconditional
# `exit $FAILED` up there makes everything below it dead code, which is exactly
# the bug BL-112 fixes. Pinned by tests/test-bl112-commit-enforcement.sh.
#
# Usage:
#   install-filesystem-gates.sh --install <project_root>
#   install-filesystem-gates.sh --uninstall <project_root>

set -euo pipefail

MARK_OPEN='# >>> SOIF framework gate (BL-030) — do not edit; managed by install-filesystem-gates.sh'
MARK_CLOSE='# <<< SOIF framework gate'

usage() {
  echo "Usage: $0 --install|--uninstall <project_root>" >&2
  exit 2
}

[ $# -lt 2 ] && usage
ACTION="$1"
PROJECT_ROOT="$2"
[ -d "$PROJECT_ROOT/.git" ] || { echo "[FAIL] not a git repo: $PROJECT_ROOT" >&2; exit 1; }

HOOK="$PROJECT_ROOT/.git/hooks/pre-commit"
GATE="$PROJECT_ROOT/.git/hooks/framework-gate.sh"

write_gate_script() {
  cat > "$GATE" <<'GATE_EOF'
#!/usr/bin/env bash
# .git/hooks/framework-gate.sh — BL-030 strict-mode framework gate.
# Self-no-ops if enforcement_level != "strict" (defense in depth).

set -uo pipefail
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$PROJECT_ROOT/.claude" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

LEVEL=$(jq -r '.enforcement_level // "strict"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null)
[ "$LEVEL" != "strict" ] && exit 0

# Delegate to process-checklist.sh + pre-commit-gate.sh in terminal mode.
SCRIPTS="$PROJECT_ROOT/scripts"
[ -x "$SCRIPTS/process-checklist.sh" ] || exit 0
[ -x "$SCRIPTS/pre-commit-gate.sh" ]   || exit 0

# BL-112-GATE-EXIT — the verdict MUST be captured from the checker itself.
# These two arms used to read `if ! "$SCRIPTS/…"; then EXIT=$?; … exit $EXIT; fi`.
# Inside the then-branch of `if ! cmd`, `$?` is the status of the NEGATION — which
# is 0 whenever cmd failed. So EXIT was ALWAYS 0 and the gate printed its [FAIL]
# and then `exit 0`: the commit landed anyway. Combined with BL-112's F8 (the gate
# was unreachable dead code) this gate was hollow twice over. Run the checker,
# capture ITS status, and branch on that. `set -e` is deliberately not enabled in
# this hook, so a non-zero checker does not abort before we can record the block.
#
# 1. Phase-prereq + check_commit_ready.
"$SCRIPTS/process-checklist.sh" --check-commit-ready 2>&1
EXIT=$?
if [ "$EXIT" -ne 0 ]; then
  bash "$SCRIPTS/install-filesystem-gates.sh" __record_block "$PROJECT_ROOT" "process-checklist" 2>/dev/null || true
  exit "$EXIT"
fi

# 2. pre-commit-gate.sh in terminal mode.
"$SCRIPTS/pre-commit-gate.sh" --terminal-mode
EXIT=$?
if [ "$EXIT" -ne 0 ]; then
  bash "$SCRIPTS/install-filesystem-gates.sh" __record_block "$PROJECT_ROOT" "pre-commit-gate" 2>/dev/null || true
  exit "$EXIT"
fi

# Pass: record terminal_commit_passed row.
bash "$SCRIPTS/install-filesystem-gates.sh" __record_pass "$PROJECT_ROOT" 2>/dev/null || true
exit 0
GATE_EOF
  chmod +x "$GATE"
}

# Internal: write a terminal_commit_blocked or terminal_commit_passed audit row.
# Called by framework-gate.sh via re-invocation.
record_audit_row() {
  local kind="$1"          # "blocked" or "passed"
  local proj="$2"
  local gate_name="${3:-}"
  local audit="$proj/.claude/bypass-audit.json"
  [ -f "$audit" ] || echo "[]" > "$audit"
  command -v jq >/dev/null 2>&1 || return 0
  local ts row tmp type
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ "$kind" = "blocked" ]; then
    type="terminal_commit_blocked"
  else
    type="terminal_commit_passed"
  fi
  row=$(jq -nc \
    --arg ts "$ts" \
    --arg t "$type" \
    --arg g "$gate_name" \
    '{timestamp:$ts, session_id:null, type:$t, actor:"user_terminal", enforcement_level_at_event:"strict", details:{gate:$g}, user_response:"n/a", final_outcome:(if $t=="terminal_commit_blocked" then "abandoned" else "committed" end)}')
  tmp=$(mktemp)
  if jq --argjson r "$row" '. + [$r]' "$audit" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$audit"
  else
    rm -f "$tmp"
  fi
}

case "$ACTION" in
  --install)
    write_gate_script
    if [ ! -f "$HOOK" ]; then
      cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
EOF
      chmod +x "$HOOK"
    fi
    if grep -qF "$MARK_OPEN" "$HOOK"; then
      exit 0
    fi
    {
      echo ""
      echo "$MARK_OPEN"
      echo 'if [ -f "$(git rev-parse --show-toplevel)/.git/hooks/framework-gate.sh" ]; then'
      echo '  bash "$(git rev-parse --show-toplevel)/.git/hooks/framework-gate.sh" || exit $?'
      echo 'fi'
      echo "$MARK_CLOSE"
    } >> "$HOOK"
    chmod +x "$HOOK"
    ;;
  --uninstall)
    [ -f "$HOOK" ] || exit 0
    if ! grep -qF "$MARK_OPEN" "$HOOK"; then
      exit 0
    fi
    tmp=$(mktemp)
    # `close` is a built-in awk function — rename the variable to avoid
    # BSD awk's strict reserved-word check. `open` is safe but renamed
    # for symmetry / readability.
    awk -v open_mark="$MARK_OPEN" -v close_mark="$MARK_CLOSE" '
      BEGIN { skipping = 0 }
      {
        if (skipping == 0 && $0 == open_mark) { skipping = 1; next }
        if (skipping == 1 && $0 == close_mark) { skipping = 0; next }
        if (skipping == 0) { print }
      }
    ' "$HOOK" > "$tmp"
    mv "$tmp" "$HOOK"
    chmod +x "$HOOK"
    ;;
  __record_block)
    record_audit_row "blocked" "$2" "${3:-unknown}"
    ;;
  __record_pass)
    record_audit_row "passed" "$2"
    ;;
  *)
    usage
    ;;
esac

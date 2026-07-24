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

# BL-161-NO-ROUTINE-PASS — a CLEAN terminal commit records NO row in the tracked
# ledger (.claude/bypass-audit.json records ONLY real events). Drop a NON-TRACKED
# gate-ran receipt (.claude/last-gate-pass.txt, gitignored like
# .claude/last-checked-commit.txt) so the PASS terminal stays provably reached
# without leaving the working tree perpetually one row dirty (Dogfood-4 F-DF4-007).
bash "$SCRIPTS/install-filesystem-gates.sh" __record_pass "$PROJECT_ROOT" 2>/dev/null || true
exit 0
GATE_EOF
  chmod +x "$GATE"
}

# Internal: write a terminal_commit_blocked audit row — a REAL enforcement event.
# Called by framework-gate.sh via re-invocation on a BLOCKED terminal commit.
#
# BL-161-NO-ROUTINE-PASS — this writer records ONLY the blocked event. A CLEAN
# commit no longer appends a terminal_commit_passed row here (that routine receipt
# left the working tree perpetually one row dirty — Dogfood-4 F-DF4-007); the PASS
# path drops a non-tracked receipt instead (see record_gate_pass_receipt).
# terminal_commit_passed stays a schema-valid LEGACY type — old ledgers keep their
# rows — it is simply no longer EMITTED. The `kind` arg is retained for the
# __record_block call signature; blocked is the only kind this function writes.
record_audit_row() {
  local kind="$1"          # "blocked" — the only real event recorded here
  local proj="$2"
  local gate_name="${3:-}"
  local audit="$proj/.claude/bypass-audit.json"
  [ -f "$audit" ] || echo "[]" > "$audit"
  command -v jq >/dev/null 2>&1 || return 0
  local ts row tmp type
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  type="terminal_commit_blocked"
  row=$(jq -nc \
    --arg ts "$ts" \
    --arg t "$type" \
    --arg g "$gate_name" \
    '{timestamp:$ts, session_id:null, type:$t, actor:"user_terminal", enforcement_level_at_event:"strict", details:{gate:$g}, user_response:"n/a", final_outcome:"abandoned"}')
  tmp=$(mktemp)
  if jq --argjson r "$row" '. + [$r]' "$audit" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$audit"
  else
    rm -f "$tmp"
  fi
}

# Internal: a CLEAN terminal commit's gate-ran receipt.
# BL-161-NO-ROUTINE-PASS — does NOT touch the tracked ledger. Writes a NON-TRACKED
# sidecar .claude/last-gate-pass.txt (the sanctioned mirror of
# .claude/last-checked-commit.txt — both gitignored in
# templates/generated/gitignore-base.tmpl) so the PASS terminal is provably
# reached without dirtying the tracked working tree. Best-effort: any failure is
# swallowed — a receipt hiccup must never affect the commit that already passed.
record_gate_pass_receipt() {
  local proj="$1"
  mkdir -p "$proj/.claude" 2>/dev/null || true
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$proj/.claude/last-gate-pass.txt" 2>/dev/null || true
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
    # BL-161-NO-ROUTINE-PASS — a clean pass writes a non-tracked receipt, not a
    # tracked ledger row.
    record_gate_pass_receipt "$2"
    ;;
  *)
    usage
    ;;
esac

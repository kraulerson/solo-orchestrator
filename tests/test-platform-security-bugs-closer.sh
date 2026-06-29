#!/usr/bin/env bash
# tests/test-platform-security-bugs-closer.sh — assertions for the 5 S3 findings
# closed by the docs/platform-security-bugs-closer PR. Each test maps to a
# specific finding ID and must fail on origin/main BEFORE the fix lands.
#
# Findings covered:
#   T1: platform-modules-web-desktop-1   — web.md §7 Phase 4 subsection
#   T2: platform-modules-web-desktop-6   — desktop.md §5.3 Rollback Procedure
#   T3a: security-audits-1               — guard_not_in_framework gains target-dir arg
#   T3b: security-audits-1               — bl-016 audit rows #2 + #10 describe new check
#   T4a: security-audits-2               — pending-approval.sh invokes guard for write subcommands
#   T4b: security-audits-2               — docstring/callsite parity self-check
#   T5: backlog-bugs-6                   — BUG-001 2026-04-22 update wording corrected
#
# Why this is a single file: the 5 findings are landed in one PR by design
# (Karl's "comprehensive" preference + workflow closer mode). Bundling the
# tests mirrors the PR shape and avoids fixture duplication.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# --- T1: web.md Phase 4 subsection enumerates all six baseline steps ---
t1_web_phase4_subsection() {
  local web="$REPO_ROOT/docs/platform-modules/web.md"
  [ -f "$web" ] || { fail_ "T1" "missing $web"; return; }

  # The §7 subsection must exist (header includes "Phase 4" and "Release & Maintenance").
  if ! grep -Eq '^### Phase 4 — Release & Maintenance' "$web"; then
    fail_ "T1" "web.md §7 missing 'Phase 4 — Release & Maintenance' heading"
    return
  fi

  # All six baseline Phase 4 step ids (from process-checklist.sh) must appear in §7's web section.
  # We scope by looking at the lines AFTER the new heading.
  local section
  section=$(awk '/^### Phase 4 — Release & Maintenance/{flag=1} flag' "$web")
  local step missing=""
  for step in production_build rollback_tested go_live_verified monitoring_configured handoff_written handoff_tested; do
    if ! printf '%s\n' "$section" | grep -q "$step"; then
      missing="${missing}${step} "
    fi
  done
  if [ -n "$missing" ]; then
    fail_ "T1" "web.md Phase 4 section missing step refs: $missing"
    return
  fi

  # Must cite the rollback evidence file pattern (test plan dictates concrete artifact).
  if ! printf '%s\n' "$section" | grep -q "docs/test-results/.*rollback-test"; then
    fail_ "T1" "web.md Phase 4 must cite docs/test-results/[date]_rollback-test.md evidence path"
    return
  fi

  pass "T1: web.md §7 Phase 4 enumerates 6 baseline steps + cites rollback-evidence file"
}

# --- T2: desktop.md §5.3 Rollback Procedure exists with tiered rollback test ---
t2_desktop_rollback_section() {
  local desk="$REPO_ROOT/docs/platform-modules/desktop.md"
  [ -f "$desk" ] || { fail_ "T2" "missing $desk"; return; }

  # The §5.3 heading must exist (rollback procedure for desktop).
  if ! grep -Eq '^### 5\.3 Rollback' "$desk"; then
    fail_ "T2" "desktop.md missing '### 5.3 Rollback' heading"
    return
  fi

  # Scope subsequent assertions to the §5.3 section (until §5.4 OR § ### Data Handling).
  local section
  section=$(awk '
    /^### 5\.3 Rollback/ {flag=1}
    flag && /^### / && !/^### 5\.3 Rollback/ {flag=0}
    flag' "$desk")

  # Must reference at least one of: Tauri updater.json or electron-updater latest.yml (the recommended fix specifies both).
  if ! printf '%s\n' "$section" | grep -Eq "updater\.json|latest\.yml"; then
    fail_ "T2" "desktop.md §5.3 must reference Tauri updater.json or electron-updater latest.yml feed"
    return
  fi

  # Must mention at least one distribution channel withdraw step (Homebrew tap / winget manifest / Snap / Flathub / GitHub release).
  if ! printf '%s\n' "$section" | grep -Eiq "homebrew|winget|snap|flathub|GitHub Releases"; then
    fail_ "T2" "desktop.md §5.3 must describe channel withdraw (Homebrew/winget/Snap/Flathub/GitHub Releases)"
    return
  fi

  # Must distinguish Light vs Standard+ rollback-test rigor (per recommended fix).
  if ! printf '%s\n' "$section" | grep -Eq "Light|Standard\+|Full Track"; then
    fail_ "T2" "desktop.md §5.3 must distinguish track-tier rollback-test rigor"
    return
  fi

  pass "T2: desktop.md §5.3 covers updater feed rollback + channel withdrawal + tier rigor"
}

# --- T3a: guard_not_in_framework accepts a target-dir argument ---
t3a_guard_target_dir_arg() {
  local helpers="$REPO_ROOT/scripts/lib/helpers.sh"
  [ -f "$helpers" ] || { fail_ "T3a" "missing $helpers"; return; }

  # Source helpers and call guard with a synthetic framework-shaped dir as $1.
  # Use a fresh subshell (avoid trap/exit leakage in current shell).
  local fake_fw out rc=0
  fake_fw=$(mktemp -d)
  # Plant a fake framework signature in $fake_fw.
  cat > "$fake_fw/init.sh" <<'STUB'
#!/usr/bin/env bash
# Solo Orchestrator — Project Initialization Script
echo stub
STUB
  mkdir -p "$fake_fw/templates/generated"

  # Run from a NON-framework cwd (so cwd-based check does NOT fire).
  local cwd_for_run
  cwd_for_run=$(mktemp -d)

  out=$(
    cd "$cwd_for_run" && \
    bash -c "source '$helpers' && guard_not_in_framework '$fake_fw'" 2>&1
  ) || rc=$?

  rm -rf "$fake_fw" "$cwd_for_run"

  # PRE-fix: guard ignores $1 and returns 0 (because cwd is benign). POST-fix:
  # guard must detect the framework signature at the supplied target and return 1.
  if [ "$rc" = "0" ]; then
    fail_ "T3a" "guard_not_in_framework with framework-shaped target arg should exit non-zero (got 0)"
    return
  fi
  if [[ "$out" != *"framework"* ]]; then
    fail_ "T3a" "expected guard failure message to mention 'framework', got: $out"
    return
  fi

  pass "T3a: guard_not_in_framework rejects framework-shaped target-dir argument"
}

# --- T3b: bl-016 audit rows #2 and #10 cite the new target-dir check ---
t3b_bl016_audit_rows_updated() {
  local audit="$REPO_ROOT/docs/security-audits/bl-016-init-non-interactive-security-audit.md"
  [ -f "$audit" ] || { fail_ "T3b" "missing $audit"; return; }

  # Row #10 must reference the target-dir guard (not just cwd).
  # We require the substring "target" near "guard" in the row #10 line.
  local row10
  row10=$(grep -E "^\| 10 \|" "$audit" | head -1)
  if [ -z "$row10" ]; then
    fail_ "T3b" "bl-016 audit missing row #10"
    return
  fi
  if [[ "$row10" != *"target"* ]] || [[ "$row10" != *"guard"* ]]; then
    fail_ "T3b" "bl-016 audit row #10 must describe target-dir guard (saw: $row10)"
    return
  fi

  # Row #2 must reference the new target check (not just cwd-guard).
  local row2
  row2=$(grep -E "^\| 2 \|" "$audit" | head -1)
  if [ -z "$row2" ]; then
    fail_ "T3b" "bl-016 audit missing row #2"
    return
  fi
  if [[ "$row2" != *"target"* ]]; then
    fail_ "T3b" "bl-016 audit row #2 must describe target-dir check (saw: $row2)"
    return
  fi

  pass "T3b: bl-016 audit rows #2 and #10 describe the target-dir guard"
}

# --- T4a: pending-approval.sh invokes guard_not_in_framework on write subcommands ---
t4a_pending_approval_guard() {
  local pa="$REPO_ROOT/scripts/pending-approval.sh"
  [ -f "$pa" ] || { fail_ "T4a" "missing $pa"; return; }

  # Must contain a guard_not_in_framework invocation (not just in a comment).
  # Strip comments first.
  local hits
  hits=$(grep -v '^[[:space:]]*#' "$pa" | grep -c 'guard_not_in_framework')
  if ! [[ "$hits" =~ ^[0-9]+$ ]] || [ "$hits" -lt 1 ]; then
    fail_ "T4a" "pending-approval.sh must invoke guard_not_in_framework (saw $hits hits)"
    return
  fi

  # Behavioral check: --offer from inside a fake framework dir should be refused.
  local fake_fw rc=0 out
  fake_fw=$(mktemp -d)
  cat > "$fake_fw/init.sh" <<'STUB'
#!/usr/bin/env bash
# Solo Orchestrator — Project Initialization Script
echo stub
STUB
  mkdir -p "$fake_fw/templates/generated"
  mkdir -p "$fake_fw/.claude"

  out=$(cd "$fake_fw" && bash "$pa" --offer "q?" --options "A1: x" "A2: y" --recommendation "A1" 2>&1) || rc=$?
  rm -rf "$fake_fw"

  if [ "$rc" = "0" ]; then
    fail_ "T4a" "pending-approval.sh --offer from inside framework dir should exit non-zero (got 0): $out"
    return
  fi
  if [[ "$out" != *"framework"* ]]; then
    fail_ "T4a" "expected refusal message to mention 'framework', got: $out"
    return
  fi

  pass "T4a: pending-approval.sh refuses --offer when cwd is the framework"
}

# --- T4b: docstring/callsite parity — every script named in helpers.sh:201-204 actually invokes the guard ---
t4b_docstring_parity() {
  local helpers="$REPO_ROOT/scripts/lib/helpers.sh"
  [ -f "$helpers" ] || { fail_ "T4b" "missing $helpers"; return; }

  # Extract the parenthesized list of script basenames in the docstring
  # contract immediately after 'Every project-targeted script'. We scope to
  # the contiguous comment lines that contain the parenthesized list —
  # stop at the closing `)` so the rest of the docstring (which may mention
  # other .sh files in usage / context paragraphs) isn't included.
  local doc_block
  doc_block=$(awk '
    /Every project-targeted script/ { flag=1 }
    flag { print; if (/\)/) { exit } }
  ' "$helpers")

  if [ -z "$doc_block" ]; then
    fail_ "T4b" "helpers.sh docstring block for guard_not_in_framework not found"
    return
  fi

  # Pull script basenames matching *.sh from the doc block.
  local docs_listed
  docs_listed=$(printf '%s\n' "$doc_block" | grep -oE '[a-z][a-z0-9_-]*\.sh' | sort -u)

  if [ -z "$docs_listed" ]; then
    fail_ "T4b" "no .sh scripts enumerated in guard_not_in_framework docstring"
    return
  fi

  local missing="" name
  for name in $docs_listed; do
    # Find the script file. init.sh lives at repo root; others under scripts/ or scripts/lib.
    local target=""
    if [ -f "$REPO_ROOT/$name" ]; then
      target="$REPO_ROOT/$name"
    elif [ -f "$REPO_ROOT/scripts/$name" ]; then
      target="$REPO_ROOT/scripts/$name"
    elif [ -f "$REPO_ROOT/scripts/lib/$name" ]; then
      # helpers.sh DEFINES the guard; skip it (we don't expect a script to guard against itself).
      continue
    fi
    if [ -z "$target" ]; then
      missing="${missing}${name}(not-found) "
      continue
    fi
    # Skip if this IS helpers.sh (definition site).
    [ "$(basename "$target")" = "helpers.sh" ] && continue
    # Count non-comment, non-docstring callsites.
    local hits
    hits=$(grep -v '^[[:space:]]*#' "$target" | grep -c 'guard_not_in_framework')
    if ! [[ "$hits" =~ ^[0-9]+$ ]] || [ "$hits" -lt 1 ]; then
      missing="${missing}${name}(no-call) "
    fi
  done

  if [ -n "$missing" ]; then
    fail_ "T4b" "scripts listed in helpers.sh docstring lack guard_not_in_framework callsite: $missing"
    return
  fi

  pass "T4b: every script in helpers.sh guard docstring actually calls guard_not_in_framework"
}

# --- T5: BUG-001 2026-04-22 update wording corrected ---
t5_bug001_doc_corrected() {
  local bugs="$REPO_ROOT/solo-orchestrator-bugs.md"
  [ -f "$bugs" ] || { fail_ "T5" "missing $bugs"; return; }

  # The pre-fix sentence says "Existing downstream projects sync via scripts/upgrade-project.sh"
  # which falsely implies upgrade-project.sh syncs CDF.
  # POST-fix: that exact false claim must be removed. The fix wording must
  # explicitly note the manual-copy path OR that upgrade-project.sh only
  # syncs Solo helpers (not CDF).
  local block
  block=$(awk '
    /### 2026-04-22 Update/ {flag=1}
    flag {print}
    flag && /^---/ {flag=0}
  ' "$bugs")

  if [ -z "$block" ]; then
    fail_ "T5" "BUG-001 '2026-04-22 Update' section not found"
    return
  fi

  # Positive requirement: the block must explicitly state that upgrade-project.sh
  # does NOT sync CDF (so a future reader who skims it isn't misled again).
  if ! printf '%s\n' "$block" | grep -Eiq "(does not sync CDF|does NOT sync CDF|only refreshes Solo|not perform.* CDF sync|no CDF sync)"; then
    fail_ "T5" "BUG-001 2026-04-22 block must explicitly note that upgrade-project.sh does NOT sync CDF"
    return
  fi

  pass "T5: BUG-001 2026-04-22 update correctly describes upgrade-project.sh scope (no CDF sync)"
}

# --- Run ---
echo "== tests/test-platform-security-bugs-closer.sh =="
t1_web_phase4_subsection
t2_desktop_rollback_section
t3a_guard_target_dir_arg
t3b_bl016_audit_rows_updated
t4a_pending_approval_guard
t4b_docstring_parity
t5_bug001_doc_corrected

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

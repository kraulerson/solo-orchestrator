#!/usr/bin/env bash
# tests/test-init-non-interactive-mobile-auto-install.sh — regression suite
# for BL-057: init.sh --non-interactive must honor the AUTO_INSTALL_TOOLS env
# var instead of issuing a bare `read -rp` on the tool-install plan.
#
# DEFECT
#   scripts/init.sh (resolve_and_install_tools) called:
#     read -rp "...Proceed with this plan? [Y/n]: " response
#   unconditionally whenever the resolved plan contained any auto_install or
#   manual_install entries. Under the documented --non-interactive contract
#   (closed stdin) and `set -euo pipefail`, `read` returned non-zero and the
#   script terminated silently with rc=1.
#
#   Surfaced by the Step-5 dogfood validation walker (DOGFOOD-001) — the only
#   bug found across 38 scenarios. Reproducer: --platform mobile +
#   --language typescript on a Darwin host without Android Studio installed
#   (the resolver auto-installs Android Studio at Phase 2).
#
# CONTRACT (post-fix)
#   1. NON_INTERACTIVE=true → response = ${AUTO_INSTALL_TOOLS:-Y}; the read
#      prompt is bypassed.
#   2. AUTO_INSTALL_TOOLS unset → defaults to Y → installs proceed → rc=0.
#   3. AUTO_INSTALL_TOOLS=N    → no install commands executed → rc=0.
#
# This regression suite asserts (2) and (3). Case (1) — the RED case on
# origin/main — is documented in the commit body; reproducing it here would
# require a separate checkout and a network fetch, both out of scope for a
# fast unit test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build an isolated cwd + project-dir, then invoke init.sh with --platform
# mobile so the resolver auto-installs Android Studio (the row that hit the
# bug). stdin is closed (</dev/null) to mirror the dogfood walker.
#
# HERMETICITY (BL-076): --no-remote-creation is MANDATORY here. This suite
# asserts only on the tool-installation-plan flow (resolve_and_install_tools),
# which runs BEFORE create_and_protect_remote. Without --no-remote-creation the
# default --git-host github drives the real gh CLI and, on an authenticated
# host, creates + pushes a REAL private repo (this is exactly how kraulerson/foo
# was leaked on 2026-07-06). --no-remote-creation skips the host API entirely
# (init.sh:2066) and does not touch the tool-install path, so every assertion
# below is preserved while the test can never reach live gh.
#
# Echoes "EXIT|STDOUT|STDERR" with newlines flattened to spaces.
run_init_mobile() {
  local extra_env="${1:-}"
  local tmpcwd tmpprojdir out rc=0
  tmpcwd=$(mktemp -d)
  tmpprojdir=$(mktemp -d)
  # init.sh refuses to scaffold into an existing dir without --allow-existing-dir.
  rmdir "$tmpprojdir"
  if [ -n "$extra_env" ]; then
    out=$(cd "$tmpcwd" && env "$extra_env" "$INIT_SH" \
      --non-interactive \
      --platform mobile \
      --language typescript \
      --track full \
      --deployment personal \
      --gov-mode private_poc \
      --no-remote-creation \
      --project foo \
      --project-dir "$tmpprojdir" </dev/null 2>&1) || rc=$?
  else
    out=$(cd "$tmpcwd" && "$INIT_SH" \
      --non-interactive \
      --platform mobile \
      --language typescript \
      --track full \
      --deployment personal \
      --gov-mode private_poc \
      --no-remote-creation \
      --project foo \
      --project-dir "$tmpprojdir" </dev/null 2>&1) || rc=$?
  fi
  # Capture the project-dir so the caller can assert against it before cleanup.
  echo "$rc|$tmpprojdir|$(printf '%s' "$out" | tr '\n' ' ')"
  rm -rf "$tmpcwd" "$tmpprojdir"
}

# ---------------------------------------------------------------------------
# T1: default AUTO_INSTALL_TOOLS (unset) → Y → init succeeds.
# This is the GREEN case for the BL-057 fix: the original silent rc=1 must
# be gone, and the project must be scaffolded.
# ---------------------------------------------------------------------------
t1_default_auto_install_y() {
  local res rc projdir out
  res=$(run_init_mobile "")
  rc="${res%%|*}"
  res="${res#*|}"
  projdir="${res%%|*}"
  out="${res#*|}"

  if [ "$rc" != "0" ]; then
    fail_ "T1" "expected rc=0 with default AUTO_INSTALL_TOOLS, got rc=$rc; tail: ${out: -400}"
    return
  fi
  # Sanity: the Tool Installation Plan section should have rendered.
  if [[ "$out" != *"Tool Installation Plan"* ]]; then
    fail_ "T1" "expected plan banner in output; missing"
    return
  fi
  # The fix should NOT short-circuit the BL-057 skip-message on default Y.
  if [[ "$out" == *"AUTO_INSTALL_TOOLS=N — skipping"* ]]; then
    fail_ "T1" "default path unexpectedly took the skip branch"
    return
  fi
  pass "T1: --non-interactive --platform mobile (default AUTO_INSTALL_TOOLS) → rc=0, plan rendered, no skip-message"
}

# ---------------------------------------------------------------------------
# T2: AUTO_INSTALL_TOOLS=N → init succeeds, no installs executed.
# The decline branch must NOT drop into the interactive prompt_choice
# sub-menu (which would EOF-fail with a diagnostic under closed stdin).
# ---------------------------------------------------------------------------
t2_auto_install_n_skips_installs() {
  local res rc projdir out
  res=$(run_init_mobile "AUTO_INSTALL_TOOLS=N")
  rc="${res%%|*}"
  res="${res#*|}"
  projdir="${res%%|*}"
  out="${res#*|}"

  if [ "$rc" != "0" ]; then
    fail_ "T2" "expected rc=0 with AUTO_INSTALL_TOOLS=N, got rc=$rc; tail: ${out: -400}"
    return
  fi
  if [[ "$out" != *"AUTO_INSTALL_TOOLS=N"* ]]; then
    fail_ "T2" "expected BL-057 skip-message; not found"
    return
  fi
  # The decline branch must not have invoked the interactive sub-menu.
  if [[ "$out" == *"prompt_choice: stdin closed"* ]] \
     || [[ "$out" == *"What would you like to do?"* ]]; then
    fail_ "T2" "decline branch unexpectedly entered interactive sub-menu"
    return
  fi
  # The install loop's "Installing tools..." banner must NOT have fired —
  # that's the print_step that runs only when auto_count > 0 after the
  # decline branch.
  if [[ "$out" == *"[STEP] Installing tools..."* ]]; then
    fail_ "T2" "AUTO_INSTALL_TOOLS=N did not skip the install loop"
    return
  fi
  pass "T2: AUTO_INSTALL_TOOLS=N → rc=0, skip-message logged, install loop skipped, no interactive prompt"
}

# ---------------------------------------------------------------------------
# T3: AUTO_INSTALL_TOOLS=Y → init succeeds (explicit-Y is the documented
# default and must round-trip identically to the unset case).
# ---------------------------------------------------------------------------
t3_auto_install_explicit_y() {
  local res rc projdir out
  res=$(run_init_mobile "AUTO_INSTALL_TOOLS=Y")
  rc="${res%%|*}"
  res="${res#*|}"
  projdir="${res%%|*}"
  out="${res#*|}"

  if [ "$rc" != "0" ]; then
    fail_ "T3" "expected rc=0 with AUTO_INSTALL_TOOLS=Y, got rc=$rc; tail: ${out: -400}"
    return
  fi
  if [[ "$out" == *"AUTO_INSTALL_TOOLS=N — skipping"* ]]; then
    fail_ "T3" "explicit-Y path unexpectedly took the skip branch"
    return
  fi
  pass "T3: AUTO_INSTALL_TOOLS=Y → rc=0 (round-trips to default)"
}

# --- Run all ---
echo "== tests/test-init-non-interactive-mobile-auto-install.sh =="
t1_default_auto_install_y
t2_auto_install_n_skips_installs
t3_auto_install_explicit_y

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

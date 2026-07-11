#!/usr/bin/env bash
# tests/test-bl010-commitmsg-bl006.sh — BL-010 residual.
#
# BL-006 (PR #15) enforces "a feat: commit in Phase 2+ requires an active,
# sufficiently-complete Build Loop" — but it ran ONLY on the AI-tooling
# PreToolUse surface. BL-010 wires the SAME check into the git COMMIT-MSG hook
# surface (pre-commit-gate.sh --terminal-mode --tdd-only ->
# bl006_terminal_enforce), so editor-opened (`git commit` with no -m) and
# human-terminal commits face it too. The load-bearing wiring line carries the
# marker `# BL-010-COMMITMSG-BL006`.
#
# Cases:
#   T-bl010-commitmsg-bl006-blocks  feat + Phase 2 + no Build Loop -> commit-msg
#                                   surface REFUSES with BL-006's message (rc=1)
#   T-bl010-commitmsg-bl006-passes  feat + a COMPLETE Build Loop -> passes (rc=0)
#   T-bl010-editor-case             message supplied via the editor (no -m), a
#                                   REAL git commit through the installed hook ->
#                                   aborted with BL-006's message, no commit made
#   T-bl010-mothership-noop         no phase-state.json (phase 0) -> passes; and
#                                   no scripts/process-checklist.sh -> passes
#   T-bl010-parity                  the SAME fixture through the PreToolUse and
#                                   commit-msg surfaces -> the SAME outcome
#                                   (both refuse the block fixture, both allow a
#                                   compliant fixture)
#   T-mutation                      excise # BL-010-COMMITMSG-BL006 from a gate
#                                   COPY -> the block fixture no longer refuses
#                                   (rc=0, RED); the real gate refuses (rc=1,
#                                   GREEN) — proving the marked line is what
#                                   enforces BL-006 at this surface
#
# Hermetic: mktemp fixture repos (git init + local identity + a fake origin
# pointer only — no real remote is ever contacted); GITHUB_BASE_REF unset so
# CI's own env cannot leak into fixture git ops; no init.sh execution.
#
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)), no
# multibyte characters adjacent to a $expansion.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — BL-006 phase / Build-Loop reads require jq."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 -- $2"; FAILED=$((FAILED + 1)); }

# ── Fixture scaffolding ──────────────────────────────────────────────
# Build a hermetic repo that looks like a scaffolded project: it ships
# scripts/{pre-commit-gate.sh, process-checklist.sh, lib/*} + .claude state so
# the gate's CWD-relative delegation resolves to the project's own copies (never
# the framework's). phase="none" omits phase-state.json entirely (mothership).
# feature="none" leaves the Build Loop inactive; complete="complete" fills the
# five commit-required Build Loop steps.
scaffold() {
  local phase="$1" feature="$2" complete="${3:-}"
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  mkdir -p "$PROJ/scripts/lib" "$PROJ/.claude"
  cp "$REPO_ROOT/scripts/pre-commit-gate.sh" "$PROJ/scripts/"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$PROJ/scripts/"
  cp "$REPO_ROOT"/scripts/lib/*.sh "$PROJ/scripts/lib/"
  chmod +x "$PROJ/scripts/pre-commit-gate.sh" "$PROJ/scripts/process-checklist.sh"

  if [ "$phase" != "none" ]; then
    cat > "$PROJ/.claude/phase-state.json" <<EOF
{"current_phase":$phase,"deployment":"personal","poc_mode":null,"track":"standard"}
EOF
  fi

  local steps='[]' feat_json='null'
  if [ "$feature" != "none" ]; then
    feat_json="\"$feature\""
    if [ "$complete" = "complete" ]; then
      steps='["tests_written","tests_verified_failing","implemented","security_audit","documentation_updated"]'
    fi
  fi
  # phase2_init.verified=true so the PreToolUse full-checklist path (used only in
  # the parity test) is not blocked by an UNRELATED gate — BL-006 is the only
  # variable under test. It has no effect on the commit-msg --tdd-only surface,
  # which reads neither phase2_init nor the UAT session.
  cat > "$PROJ/.claude/process-state.json" <<EOF
{"build_loop":{"feature":$feat_json,"step":0,"steps_completed":$steps,"started_at":null},"uat_session":{},"phase1_architecture":{},"phase3_validation":{},"phase4_release":{},"phase2_init":{"steps_completed":["remote_repo_created"],"verified":true}}
EOF

  ( cd "$PROJ"
    unset GITHUB_BASE_REF
    git init -q -b main
    git config user.email "t@example.invalid"
    git config user.name "bl010-test"
    git remote add origin "https://example.invalid/x.git"
    echo seed > README.md
    git add README.md
    git commit -q -m "chore: seed" )
}
teardown() { rm -rf "$TMP"; }

# Install a commit-msg hook byte-for-byte equivalent to what init.sh's
# install_tdd_commit_msg_hook emits (the invocation line is the contract).
install_commit_msg_hook() {
  mkdir -p "$PROJ/.git/hooks"
  cat > "$PROJ/.git/hooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
if [ -x scripts/pre-commit-gate.sh ]; then
  scripts/pre-commit-gate.sh --terminal-mode --tdd-only || exit 1
fi
EOF
  chmod +x "$PROJ/.git/hooks/commit-msg"
}

# Stage a file (creating parent dirs) without committing.
stage() {
  local path="$1" content="${2:-x}"
  mkdir -p "$PROJ/$(dirname "$path")"
  printf '%s\n' "$content" > "$PROJ/$path"
  ( cd "$PROJ" && git add "$path" )
}

# Set the prospective commit subject (commit-msg surface reads COMMIT_EDITMSG).
set_subject() { printf '%s\n' "$1" > "$PROJ/.git/COMMIT_EDITMSG"; }

# Stage a feat change that keeps the TDD gate SILENT (an impl file WITH a test
# riding along), so the ONLY enforcer under test is BL-006.
stage_feat_with_test() {
  stage "src/foo.py" "def foo(): return 1"
  stage "tests/test_foo.py" "def test_foo(): assert True"
}

# Run the gate at the commit-msg surface. Echoes "rc|<single-line out>".
run_commitmsg() {
  local gate="${1:-$GATE}" out rc=0
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; bash "$gate" --terminal-mode --tdd-only 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

# Run the gate at the PreToolUse surface with a bash command. Echoes "rc|out".
# SKIP_LINT=1 keeps the unrelated operator-side lints out of the comparison.
run_pretooluse() {
  local cmd="$1" input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; export SKIP_LINT=1; \
         printf '%s' "$input" | bash "$GATE" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

# BL-006's remediation subjects (require_build_loop_state_for_commit).
has_bl006_block() {
  case "$1" in
    *'no Build Loop active'*|*'Build Loop incomplete'*) return 0 ;;
    *) return 1 ;;
  esac
}
is_deny() { case "$1" in *'"permissionDecision": "deny"'*) return 0 ;; *) return 1 ;; esac; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-bl010-commitmsg-bl006-blocks: feat + Phase 2 + no Build Loop -> refuse (rc=1) ==="
# ════════════════════════════════════════════════════════════════════
scaffold 2 none
stage_feat_with_test
set_subject "feat: add foo without a Build Loop"
res=$(run_commitmsg); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 1 ] && has_bl006_block "$body"; then
  pass "T-bl010-commitmsg-bl006-blocks: commit-msg surface REFUSES the feat: commit with BL-006's message (rc=1)"
else
  fail_ "T-bl010-commitmsg-bl006-blocks" "expected rc=1 + BL-006 block; got rc=$rc body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-bl010-commitmsg-bl006-passes: feat + a COMPLETE Build Loop -> allow (rc=0) ==="
# ════════════════════════════════════════════════════════════════════
scaffold 2 add-foo complete
stage_feat_with_test
set_subject "feat: add foo with a completed Build Loop"
res=$(run_commitmsg); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_bl006_block "$body"; then
  pass "T-bl010-commitmsg-bl006-passes: compliant feat: commit passes (rc=0, no BL-006 block)"
else
  fail_ "T-bl010-commitmsg-bl006-passes" "expected rc=0 + no block; got rc=$rc body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-bl010-editor-case: message via the editor (no -m), REAL git commit -> aborted ==="
# ════════════════════════════════════════════════════════════════════
# The exact population BL-010 exists for: an editor-opened commit (no -m). git
# writes the editor's output to .git/COMMIT_EDITMSG, then runs the commit-msg
# hook — which now runs BL-006. We inject the editor's message via GIT_EDITOR.
scaffold 2 none
install_commit_msg_hook
stage_feat_with_test
ED="$TMP/editor.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "feat: editor-authored feature" > "$1"\n' > "$ED"
chmod +x "$ED"
before_count=$( cd "$PROJ" && git rev-list --count HEAD )
out=$( cd "$PROJ" && unset GITHUB_BASE_REF; GIT_EDITOR="$ED" git commit 2>&1 ); rc=$?
out=$(printf '%s' "$out" | tr '\n' ' ')
after_count=$( cd "$PROJ" && git rev-list --count HEAD )
if [ "$rc" -ne 0 ]; then
  pass "T-bl010-editor-case: git aborts the editor-authored feat: commit (rc=$rc)"
else
  fail_ "T-bl010-editor-case" "expected git commit to fail; got rc=0 out: $out"
fi
if has_bl006_block "$out"; then
  pass "T-bl010-editor-case: the abort carries BL-006's remediation (editor case is now checked)"
else
  fail_ "T-bl010-editor-case" "expected BL-006 remediation in the abort output; out: $out"
fi
if [ "$after_count" -eq "$before_count" ]; then
  pass "T-bl010-editor-case: no commit was created (history unchanged: $before_count)"
else
  fail_ "T-bl010-editor-case" "a commit landed despite the block ($before_count -> $after_count)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-bl010-mothership-noop: no framework state -> sails through ==="
# ════════════════════════════════════════════════════════════════════
# (a) No phase-state.json -> check_commit_message reads phase 0 -> exits 0. This
# is exactly the framework repo's own situation (process-checklist.sh present,
# no phase-state.json): its own feat: commits must NEVER be blocked.
scaffold none none
stage_feat_with_test
set_subject "feat: mothership commit with no phase state"
res=$(run_commitmsg); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_bl006_block "$body"; then
  pass "T-bl010-mothership-noop (no phase-state): feat: commit passes (rc=0) — phase gate short-circuits"
else
  fail_ "T-bl010-mothership-noop" "expected rc=0 + no block with no phase-state; got rc=$rc body: $body"
fi
teardown

# (b) No scripts/process-checklist.sh at all -> bl006_terminal_enforce no-ops.
# Second mothership-safety layer: a repo that predates BL-006 (or is not a
# scaffolded project) has no checklist to delegate to.
scaffold 2 none
rm -f "$PROJ/scripts/process-checklist.sh"
stage_feat_with_test
set_subject "feat: add foo with no checklist present"
res=$(run_commitmsg); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_bl006_block "$body"; then
  pass "T-bl010-mothership-noop (no checklist): feat: commit passes (rc=0) — nothing to delegate to"
else
  fail_ "T-bl010-mothership-noop" "expected rc=0 + no block with no checklist; got rc=$rc body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-bl010-parity: the SAME fixture through both surfaces -> the SAME outcome ==="
# ════════════════════════════════════════════════════════════════════
# Block fixture: both surfaces must REFUSE.
scaffold 2 none
stage_feat_with_test
set_subject "feat: parity block"
res_cm=$(run_commitmsg); rc_cm="${res_cm%%|*}"; body_cm="${res_cm#*|}"
res_pt=$(run_pretooluse 'git commit -m "feat: parity block"'); body_pt="${res_pt#*|}"
if [ "$rc_cm" -eq 1 ] && has_bl006_block "$body_cm" && is_deny "$body_pt" && has_bl006_block "$body_pt"; then
  pass "T-bl010-parity (block): commit-msg refuses (rc=1) AND PreToolUse denies — same BL-006 outcome"
else
  fail_ "T-bl010-parity" "block divergence: commit-msg rc=$rc_cm body: $body_cm || PreToolUse body: $body_pt"
fi
teardown

# Compliant fixture: both surfaces must ALLOW.
scaffold 2 add-foo complete
stage_feat_with_test
set_subject "feat: parity pass"
res_cm=$(run_commitmsg); rc_cm="${res_cm%%|*}"; body_cm="${res_cm#*|}"
res_pt=$(run_pretooluse 'git commit -m "feat: parity pass"'); rc_pt="${res_pt%%|*}"; body_pt="${res_pt#*|}"
if [ "$rc_cm" -eq 0 ] && ! has_bl006_block "$body_cm" && ! is_deny "$body_pt"; then
  pass "T-bl010-parity (pass): commit-msg allows (rc=0) AND PreToolUse does not deny — same BL-006 outcome"
else
  fail_ "T-bl010-parity" "pass divergence: commit-msg rc=$rc_cm body: $body_cm || PreToolUse rc=$rc_pt body: $body_pt"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation: excise # BL-010-COMMITMSG-BL006 -> block disappears (RED->GREEN proof) ==="
# ════════════════════════════════════════════════════════════════════
# Removing the marked delegation line must make the commit-msg surface STOP
# refusing the block fixture (RED), while the real gate still refuses it (GREEN)
# — proving the marked line is what enforces BL-006 at the commit-msg surface.
scaffold 2 none
stage_feat_with_test
set_subject "feat: mutation target"
MUT_GATE="$PROJ/scripts/pre-commit-gate.mut.sh"
grep -v '# BL-010-COMMITMSG-BL006' "$GATE" > "$MUT_GATE"
chmod +x "$MUT_GATE"
if ! grep -q '# BL-010-COMMITMSG-BL006' "$GATE"; then
  fail_ "T-mutation" "BL-010-COMMITMSG-BL006 marker missing from the REAL gate — nothing to mutate"
elif grep -q '# BL-010-COMMITMSG-BL006' "$MUT_GATE"; then
  fail_ "T-mutation" "marker still present after excision — mutation did not apply"
elif ! bash -n "$MUT_GATE" 2>/dev/null; then
  fail_ "T-mutation" "mutated gate not syntactically valid after excision"
else
  res=$(run_commitmsg "$MUT_GATE"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 0 ] && ! has_bl006_block "$body"; then
    pass "T-mutation (RED): excising the marker removes the BL-006 refusal (rc=0) — the line is load-bearing"
  else
    fail_ "T-mutation" "mutant STILL refused (rc=$rc) — the marked line is not load-bearing; body: $body"
  fi
  res=$(run_commitmsg); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_bl006_block "$body"; then
    pass "T-mutation (GREEN): the real gate refuses the same fixture (rc=1) — contrast holds"
  else
    fail_ "T-mutation" "real gate did NOT refuse — contrast broken; rc=$rc body: $body"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

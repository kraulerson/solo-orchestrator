#!/usr/bin/env bash
# tests/test-specs-plans-remaining-quartet.sh
#
# Coverage for four S3 audit findings landed together in PR
# `fix/specs-plans-remaining-quartet`. Each block is a self-contained
# red→green oracle:
#
#   T-PR-GATE — specs-plans-process-enforcement-2
#     pre-commit-gate.sh's gh-pr-create branch must allow PR creation
#     once Build-Loop steps 1–5 (tests_written … documentation_updated)
#     are complete. The pre-fix threshold of `-lt 6` requires step 6
#     (feature_recorded) which is post-PR bookkeeping; baseline
#     invariant #14 prescribes 5/6. RED on origin/main: gate DENIES at
#     5/6. GREEN: gate ALLOWS at 5/6 and still DENIES at 1/6..4/6.
#
#   T-CV-MULTIWORD — specs-plans-tool-matrix-versions-1
#     check-versions.sh truncated multi-word tool names ("Claude Code")
#     to their first word in update output by parsing the display string
#     UPDATES[] entry with `${var%% *}`. Now driven from a parallel
#     UPDATE_NAMES[] array so the printed name matches the matrix
#     verbatim. RED on origin/main: "Claude" only appears in command-list
#     line. GREEN: "Claude Code" appears verbatim.
#
#   T-VI-PIPELINE — specs-plans-uat-bugs-verify-install-uat-quality-3
#     verify-install.sh's fix_ci_pipeline / fix_release_pipeline read
#     from pre-BL-008 flat-layout paths and write to .github/workflows
#     hardcoded — broken for bitbucket/gitlab hosts and broken even on
#     github after the BL-008 per-host subfolder migration. Now reads
#     host from .claude/manifest.json (.host) with `git remote get-url
#     origin` fallback and routes to the matching host destination.
#     RED on origin/main: bitbucket-pipelines.yml is never created.
#     GREEN: bitbucket-pipelines.yml is created from
#     templates/pipelines/ci/bitbucket/<lang>.yml.
#
#   T-PA-TIERAWARE — specs-plans-phase-audit-docs-remediation-1
#     The phase-audit spec and plan were tier-blind: auditors graded
#     findings without knowledge of (deployment, poc_mode, track,
#     enforcement_level) so intentional graceful-degradation behaviors
#     surfaced as severity inflations. Spec §2.0 and the six agent
#     prompts must require auditors to compute the project's tier
#     tuple and carry a `tier_context` field on every finding. RED on
#     origin/main: the spec and plan do not mention `tier_context` or
#     §2.0 tier-tuple gating. GREEN: both files contain the tier-aware
#     amendment markers.
#
# Test harness conventions mirror tests/test-pre-commit-gate-classifier.sh
# and tests/test-verify-install-fix-functions.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
CV="$REPO_ROOT/scripts/check-versions.sh"
VI="$REPO_ROOT/scripts/verify-install.sh"
SPEC="$REPO_ROOT/docs/superpowers/specs/2026-04-08-phase-audit-design.md"
PLAN="$REPO_ROOT/docs/superpowers/plans/archive/2026-04-08-phase-audit.md"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ════════════════════════════════════════════════════════════════════
# T-PR-GATE — specs-plans-process-enforcement-2
# ════════════════════════════════════════════════════════════════════

setup_pr_fixture() {
  local steps_done="$1"  # integer 0..6
  TMP_PR=$(mktemp -d)
  (
    cd "$TMP_PR"
    git init -q -b main
    git config user.email "t@t.l"
    git config user.name  "t"
    git remote add origin https://example.com/x.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"other","deployment":"personal","enforcement_level":"strict"}
JSON
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
JSON
  )

  # Build a build_loop.steps_completed list of the requested length using
  # the canonical ordering from process-checklist.sh:BUILD_LOOP_STEPS.
  local all=(tests_written tests_verified_failing implemented security_audit documentation_updated feature_recorded)
  local steps_json="[]"
  if [ "$steps_done" -gt 0 ]; then
    local slice=()
    local i
    for (( i=0; i<steps_done; i++ )); do
      slice+=("${all[$i]}")
    done
    steps_json=$(printf '%s\n' "${slice[@]}" | jq -R . | jq -s .)
  fi
  jq -n --argjson s "$steps_json" '
    {
      phase2_init:{verified:true,steps_completed:["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied","initialization_verified"]},
      build_loop:{feature:"demo",step:($s|length),steps_completed:$s,started_at:"2026-04-26T00:00:00Z"},
      uat_session:{},
      phase3_validation:{},
      phase4_release:{}
    }' > "$TMP_PR/.claude/process-state.json"
}
teardown_pr() { rm -rf "${TMP_PR:-}"; }

# Pipe a JSON tool_input.command into the gate. Echo "EXIT|STDOUT".
# SKIP_LINT=1 bypasses the counter-antipattern + backlog-references
# lints, which are scoped to the repo we're being invoked from and add
# tens of seconds per invocation; they are not under test here.
run_gate() {
  local cmd="$1"
  local input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$(cd "$TMP_PR" && printf '%s' "$input" | SKIP_LINT=1 bash "$GATE" 2>&1) || rc=$?
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')"
}

# T-PR-GATE-A: 5/6 steps done (documentation_updated last) → gate must ALLOW.
# RED on main: gate DENIES (the `-lt 6` branch fires at 5/6).
echo "T-PR-GATE-A: gh pr create with Build-Loop 5/6 complete is ALLOWED"
setup_pr_fixture 5
out=$(run_gate 'gh pr create --title "x" --body "y"')
if [[ "${out#*|}" == *'"permissionDecision": "deny"'*'incomplete Build Loop'* ]]; then
  fail_ "T-PR-GATE-A" "gate DENIED PR creation at 5/6 (should ALLOW per baseline invariant #14)"
else
  pass "T-PR-GATE-A: 5/6 build_loop steps allows PR creation"
fi
teardown_pr

# T-PR-GATE-B: 3/6 steps done (partial) → gate must still DENY.
# This is the non-vacuous companion: confirms the lowered threshold did
# not collapse to "always allow". RED on main: also DENIES (different
# message internals). GREEN: still DENIES with "$BUILD_STEPS_DONE/5".
echo "T-PR-GATE-B: gh pr create with Build-Loop 3/6 complete is still DENIED"
setup_pr_fixture 3
out=$(run_gate 'gh pr create --title "x" --body "y"')
if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
  fail_ "T-PR-GATE-B" "gate ALLOWED PR creation at 3/6 (should DENY — partial Build Loop)"
elif [[ "${out#*|}" != *'incomplete Build Loop'* ]]; then
  fail_ "T-PR-GATE-B" "gate DENIED but for the wrong reason (expected 'incomplete Build Loop'); got: ${out#*|}"
else
  pass "T-PR-GATE-B: 3/6 build_loop steps still denies PR creation"
fi
teardown_pr

# T-PR-GATE-C: 0/6 steps done with feature unset → no build_loop block at all.
# Confirms the gate's existing step-0 carve-out still works (no regression
# on the "between features" case). RED on main: ALLOWS (so does GREEN);
# this is anti-regression armor for the carve-out.
echo "T-PR-GATE-C: gh pr create with build_loop feature unset is ALLOWED"
TMP_PR=$(mktemp -d)
(
  cd "$TMP_PR"
  git init -q -b main
  git config user.email "t@t.l"; git config user.name "t"
  git remote add origin https://example.com/x.git
  mkdir -p .claude
  cat > .claude/manifest.json <<'JSON'
{"frameworkVersion":"test","mode":"personal","host":"other","deployment":"personal","enforcement_level":"strict"}
JSON
  cat > .claude/phase-state.json <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
JSON
  cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"verified":true,"steps_completed":["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied","initialization_verified"]},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
JSON
)
out=$(run_gate 'gh pr create --title "x" --body "y"')
if [[ "${out#*|}" == *'"permissionDecision": "deny"'*'incomplete Build Loop'* ]]; then
  fail_ "T-PR-GATE-C" "gate DENIED PR creation with no in-flight feature (should ALLOW — step-0 carve-out)"
else
  pass "T-PR-GATE-C: no in-flight build_loop allows PR creation"
fi
teardown_pr

# ════════════════════════════════════════════════════════════════════
# T-CV-MULTIWORD — specs-plans-tool-matrix-versions-1
#   check-versions.sh shadows uname(1) by reusing the name `uname` for
#   a string variable AND parses the display string to recover it.
#   When the matrix name has whitespace ("Claude Code"), the display
#   parser truncates to "Claude". The non-interactive branch (lines
#   516–524) prints `<name>: <cmd>` for every UPDATES[] entry — this is
#   the surface we drive in the test.
# ════════════════════════════════════════════════════════════════════

setup_cv_fixture() {
  TMP_CV=$(mktemp -d)
  mkdir -p "$TMP_CV/templates/tool-matrix" "$TMP_CV/scripts/lib"
  # Single tool with a multi-word name. min_version > installed (echo 0.0.1)
  # forces the BELOW MINIMUM branch which unconditionally pushes onto
  # UPDATES[] / UPDATE_CMDS[] regardless of network availability.
  # check-versions.sh loads common.json directly; we place our single
  # multi-word tool there.
  cat > "$TMP_CV/templates/tool-matrix/common.json" <<'JSON'
{
  "tools": [
    {
      "name": "Claude Code",
      "category": "ai_agent",
      "required": true,
      "min_version": "99.0.0",
      "description": "Claude Code CLI",
      "check_command": "true",
      "version_command": "echo 0.0.1",
      "tracks": ["light", "standard", "full"],
      "languages": ["all"],
      "platforms": ["all"],
      "dev_os": ["darwin", "linux"],
      "install": { "darwin_brew": "brew install claude-fake" }
    }
  ]
}
JSON
  # Minimal helpers stub. The real helpers.sh provides print_* + colour
  # vars; we provide just enough for check-versions.sh to source cleanly.
  cat > "$TMP_CV/scripts/lib/helpers.sh" <<'BASH'
BOLD=""; NC=""; YELLOW=""; CYAN=""; GREEN=""; RED=""
print_ok()   { echo "[OK] $*"; }
print_warn() { echo "[WARN] $*"; }
print_fail() { echo "[FAIL] $*"; }
print_info() { echo "[INFO] $*"; }
print_step() { echo "[STEP] $*"; }
prompt_input() { echo "${2:-}"; }
prompt_yes_no() { echo "n"; }
BASH
  cp "$CV" "$TMP_CV/scripts/check-versions.sh"
  chmod +x "$TMP_CV/scripts/check-versions.sh"
}
teardown_cv() { rm -rf "${TMP_CV:-}"; }

echo "T-CV-MULTIWORD: multi-word tool name 'Claude Code' is printed verbatim in update output"
setup_cv_fixture
# Invoke from inside the fixture so templates/tool-matrix is discovered
# relative to the script (matches normal invocation). Non-interactive
# (stdin not a TTY) is achieved by piping /dev/null in.
out=$(cd "$TMP_CV" && bash scripts/check-versions.sh </dev/null 2>&1 || true)
# The non-interactive "Update commands (run manually):" block prints one
# line per UPDATES[] entry as `  <name>: <cmd>`. We assert the multi-word
# name survives intact AND is not truncated to its first word.
if echo "$out" | grep -qE '^[[:space:]]*Claude Code:[[:space:]]+brew install claude-fake$'; then
  pass "T-CV-MULTIWORD: 'Claude Code' surfaces with full multi-word name (no version garbage)"
else
  fail_ "T-CV-MULTIWORD" "expected '  Claude Code: brew install claude-fake' line; output: $out"
fi
teardown_cv

# ════════════════════════════════════════════════════════════════════
# T-VI-PIPELINE — specs-plans-uat-bugs-verify-install-uat-quality-3
#   fix_ci_pipeline / fix_release_pipeline must route source AND dest
#   by host (.claude/manifest.json:.host, fallback to `git remote get-url
#   origin`). We test the bitbucket path explicitly because it is the
#   one that is guaranteed-broken on main (no .github/workflows on
#   bitbucket; .github/workflows/ci.yml is never the right destination).
# ════════════════════════════════════════════════════════════════════

setup_vi_fixture() {
  local host="$1"  # github|bitbucket|gitlab
  TMP_VI=$(mktemp -d)
  SRC_VI="$TMP_VI/src"
  PROJ_VI="$TMP_VI/proj"
  mkdir -p "$SRC_VI/templates/pipelines/ci/github" \
           "$SRC_VI/templates/pipelines/ci/bitbucket" \
           "$SRC_VI/templates/pipelines/ci/gitlab" \
           "$SRC_VI/templates/pipelines/release/github" \
           "$SRC_VI/templates/pipelines/release/bitbucket" \
           "$SRC_VI/templates/pipelines/release/gitlab"
  # Distinguishable sentinel content per host so we can confirm the
  # right SOURCE file was copied (not just "some file appeared").
  printf 'CI:GITHUB:TS\n'    > "$SRC_VI/templates/pipelines/ci/github/typescript.yml"
  printf 'CI:BITBUCKET:TS\n' > "$SRC_VI/templates/pipelines/ci/bitbucket/typescript.yml"
  printf 'CI:GITLAB:TS\n'    > "$SRC_VI/templates/pipelines/ci/gitlab/typescript.yml"
  printf 'REL:GITHUB:WEB\n'    > "$SRC_VI/templates/pipelines/release/github/web.yml"
  printf 'REL:BITBUCKET:WEB\n' > "$SRC_VI/templates/pipelines/release/bitbucket/web.yml"
  printf 'REL:GITLAB:WEB\n'    > "$SRC_VI/templates/pipelines/release/gitlab/web.yml"

  mkdir -p "$PROJ_VI/.claude" "$PROJ_VI/scripts"
  cat > "$PROJ_VI/.claude/manifest.json" <<JSON
{"frameworkVersion":"test","mode":"personal","host":"$host","deployment":"personal","enforcement_level":"strict"}
JSON
  cat > "$PROJ_VI/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
JSON
  cat > "$PROJ_VI/.claude/orchestrator-source.json" <<JSON
{"source_dir":"$SRC_VI"}
JSON
  cp "$VI" "$PROJ_VI/scripts/verify-install.sh"
  mkdir -p "$PROJ_VI/scripts/lib"
  if [ -f "$REPO_ROOT/scripts/lib/helpers.sh" ]; then
    cp "$REPO_ROOT/scripts/lib/helpers.sh" "$PROJ_VI/scripts/lib/"
  fi
  chmod +x "$PROJ_VI/scripts/verify-install.sh"
}
teardown_vi() { rm -rf "${TMP_VI:-}"; }

# Helper: extract just fix_ci_pipeline / fix_release_pipeline + their
# host-detection dependency from scripts/verify-install.sh, source it
# in an isolated subshell with the necessary surface variables, and
# invoke directly. This avoids the autorun-main path's
# guard_not_in_framework + has_source/has_context plumbing.
_invoke_fix_pipeline() {
  local fn="$1"        # fix_ci_pipeline | fix_release_pipeline
  local lang="$2"
  local platform="$3"
  local extract
  extract=$(mktemp)

  # Pass 1 — post-fix layout: a `_detect_pipeline_host()` helper is
  # defined above the fix functions. Grab from the helper's opening
  # through the target fix function's closing brace. This gives us a
  # self-contained, sourceable extract.
  awk -v fn="$fn" '
    /^_detect_pipeline_host\(\) \{/ { capture=1 }
    capture { print }
    capture && /^\}$/ && !inside_fn {
      # Helper closed; keep going so we can also capture the target fn
      # AND any sibling helpers between the two.
      next
    }
    $0 ~ "^"fn"\\(\\) \\{" { inside_fn=1 }
    inside_fn && /^\}$/ { print "# end-extract"; exit }
  ' "$PROJ_VI/scripts/verify-install.sh" > "$extract"

  # Pass 2 fallback — origin/main has no detector helper. Extract just
  # the bare target function body.
  if ! grep -q "^$fn()" "$extract"; then
    awk -v fn="$fn" '
      $0 ~ "^"fn"\\(\\) \\{" { flag=1 }
      flag { print }
      flag && /^\}$/ { print "# end-extract"; exit }
    ' "$PROJ_VI/scripts/verify-install.sh" > "$extract"
  fi

  (
    cd "$PROJ_VI"
    SOURCE_DIR="$SRC_VI"
    LANGUAGE="$lang"
    PLATFORM="$platform"
    export SOURCE_DIR LANGUAGE PLATFORM
    print_fail() { echo "[FAIL] $*"; }
    print_info() { echo "[INFO] $*"; }
    print_warn() { echo "[WARN] $*"; }
    has_source()  { [ -d "$SOURCE_DIR" ]; }
    has_context() { [ -f .claude/manifest.json ]; }
    # shellcheck disable=SC1090
    source "$extract"
    "$fn"
    printf "EXIT=%s\n" "$?"
  ) 2>&1
  rm -f "$extract"
}

# T-VI-PIPELINE-CI-BITBUCKET: CI auto-fix on a bitbucket-hosted project
# must (a) read the source from templates/pipelines/ci/bitbucket/<lang>.yml
# and (b) write to bitbucket-pipelines.yml at repo root. RED on
# origin/main: .github/workflows/ci.yml created (wrong destination).
echo "T-VI-PIPELINE-CI-BITBUCKET: fix_ci_pipeline routes by host (bitbucket)"
setup_vi_fixture bitbucket
_invoke_fix_pipeline fix_ci_pipeline typescript web >/dev/null 2>&1
ok=1
if [ ! -f "$PROJ_VI/bitbucket-pipelines.yml" ]; then
  ok=0; reason="bitbucket-pipelines.yml was NOT created at repo root"
elif ! grep -q '^CI:BITBUCKET:TS' "$PROJ_VI/bitbucket-pipelines.yml" 2>/dev/null; then
  ok=0; reason="bitbucket-pipelines.yml content is not the bitbucket source (got: $(head -1 "$PROJ_VI/bitbucket-pipelines.yml" 2>/dev/null || echo MISSING))"
fi
if [ "$ok" -eq 1 ]; then
  pass "T-VI-PIPELINE-CI-BITBUCKET: bitbucket-pipelines.yml created from bitbucket source"
else
  fail_ "T-VI-PIPELINE-CI-BITBUCKET" "$reason"
fi
teardown_vi

# T-VI-PIPELINE-CI-GITLAB: gitlab path writes .gitlab-ci.yml at repo root
# from templates/pipelines/ci/gitlab/<lang>.yml.
echo "T-VI-PIPELINE-CI-GITLAB: fix_ci_pipeline routes by host (gitlab)"
setup_vi_fixture gitlab
_invoke_fix_pipeline fix_ci_pipeline typescript web >/dev/null 2>&1
ok=1
if [ ! -f "$PROJ_VI/.gitlab-ci.yml" ]; then
  ok=0; reason=".gitlab-ci.yml was NOT created at repo root"
elif ! grep -q '^CI:GITLAB:TS' "$PROJ_VI/.gitlab-ci.yml" 2>/dev/null; then
  ok=0; reason=".gitlab-ci.yml content is not the gitlab source (got: $(head -1 "$PROJ_VI/.gitlab-ci.yml" 2>/dev/null || echo MISSING))"
fi
if [ "$ok" -eq 1 ]; then
  pass "T-VI-PIPELINE-CI-GITLAB: .gitlab-ci.yml created from gitlab source"
else
  fail_ "T-VI-PIPELINE-CI-GITLAB" "$reason"
fi
teardown_vi

# T-VI-PIPELINE-CI-GITHUB: anti-regression — github path STILL writes
# .github/workflows/ci.yml and reads from the github/ subfolder (post
# BL-008 layout). Origin/main writes to the right destination but
# reads from the wrong (flat) source path, so this asserts both legs.
echo "T-VI-PIPELINE-CI-GITHUB: fix_ci_pipeline reads github/<lang>.yml not flat"
setup_vi_fixture github
_invoke_fix_pipeline fix_ci_pipeline typescript web >/dev/null 2>&1
ok=1
if [ ! -f "$PROJ_VI/.github/workflows/ci.yml" ]; then
  ok=0; reason=".github/workflows/ci.yml was NOT created"
elif ! grep -q '^CI:GITHUB:TS' "$PROJ_VI/.github/workflows/ci.yml" 2>/dev/null; then
  ok=0; reason="ci.yml content is not the github source (got: $(head -1 "$PROJ_VI/.github/workflows/ci.yml" 2>/dev/null || echo MISSING))"
fi
if [ "$ok" -eq 1 ]; then
  pass "T-VI-PIPELINE-CI-GITHUB: github CI sourced from github/ subfolder"
else
  fail_ "T-VI-PIPELINE-CI-GITHUB" "$reason"
fi
teardown_vi

# T-VI-PIPELINE-RELEASE-BITBUCKET: release pipeline parallel to CI.
# Bitbucket has no separate release file (releases run in same
# bitbucket-pipelines.yml). Test that the function either writes the
# right release destination for the host OR returns 1 (no destination
# defined) — must NOT silently create .github/workflows/release.yml.
echo "T-VI-PIPELINE-RELEASE-BITBUCKET: fix_release_pipeline does not write .github on bitbucket"
setup_vi_fixture bitbucket
_invoke_fix_pipeline fix_release_pipeline typescript web >/dev/null 2>&1
ok=1
if [ -f "$PROJ_VI/.github/workflows/release.yml" ]; then
  ok=0; reason=".github/workflows/release.yml was created on a bitbucket-hosted project (wrong destination)"
fi
if [ "$ok" -eq 1 ]; then
  pass "T-VI-PIPELINE-RELEASE-BITBUCKET: no .github/workflows/release.yml on bitbucket"
else
  fail_ "T-VI-PIPELINE-RELEASE-BITBUCKET" "$reason"
fi
teardown_vi

# ════════════════════════════════════════════════════════════════════
# T-PA-TIERAWARE — specs-plans-phase-audit-docs-remediation-1
#   The spec/plan amendment is doc-only. The oracle is the presence of
#   the new content blocks: (a) §2.0 in the spec mentioning
#   tier-tuple gating, (b) `tier_context` field in the finding schema,
#   and (c) each of the six auditor prompts in the plan referencing
#   the tier tuple before grading. RED on main: none of these markers
#   exist. GREEN: all markers present.
# ════════════════════════════════════════════════════════════════════

echo "T-PA-TIERAWARE-SPEC: spec contains §2.0 tier-tuple step"
if ! grep -qE '^## 2\.0 ' "$SPEC"; then
  fail_ "T-PA-TIERAWARE-SPEC" "spec is missing a §2.0 heading (pre-§2.1 tier-tuple step)"
elif ! grep -qE 'tier_context' "$SPEC"; then
  fail_ "T-PA-TIERAWARE-SPEC" "spec does not introduce the 'tier_context' finding field"
elif ! grep -qiE 'deployment.*poc_mode.*track.*enforcement_level|tier (tuple|context)' "$SPEC"; then
  fail_ "T-PA-TIERAWARE-SPEC" "spec §2.0 does not enumerate the four tier dimensions"
else
  pass "T-PA-TIERAWARE-SPEC: §2.0 tier-tuple gating present with tier_context field"
fi

echo "T-PA-TIERAWARE-PLAN: plan's six auditor prompts each reference tier_context"
# Count distinct dispatch blocks that mention tier_context. The plan
# has 6 prompts (Phase 0..4 + Cross-Cutting). We require ALL six to
# embed the tier-aware instruction — a partial sprinkle would leave
# auditors mis-graded for the unamended phases.
mentions=$(grep -c 'tier_context' "$PLAN" 2>/dev/null || echo "0")
case "$mentions" in ''|*[!0-9]*) mentions=0 ;; esac
if [ "$mentions" -lt 6 ]; then
  fail_ "T-PA-TIERAWARE-PLAN" "expected 'tier_context' in all 6 auditor prompts; found $mentions occurrences"
else
  pass "T-PA-TIERAWARE-PLAN: all six auditor prompts reference tier_context"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

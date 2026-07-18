#!/usr/bin/env bash
# tests/edge-case-test-suite.sh
#
# Edge-case sweep across the framework surface that the existing unit
# tests don't cover. Sections:
#
#   1. Novel / unsupported platform
#   2. Tool customization (--tool-prefs additions / skipped)
#   3. Git host variation (gitlab, bitbucket, other)
#   4. Existing-project re-init
#   5. bypass-detector edges (re-entrancy, unicode, large input,
#      malformed envelope, tool_response shape variants)
#   6. intake-wizard render edges (empty, pipe, newline, idempotency,
#      missing INTAKE_FILE)
#   7. resolve-tools timeout regression (hanging tool check)
#
# Each test is self-contained and produces PASS/FAIL output. Tests that
# document a known limitation print [DOC] and don't count toward FAIL.
#
# Usage: bash tests/edge-case-test-suite.sh

set -o pipefail
RC=0  # global captured by run_bounded

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/bypass-detector.sh"
INIT="$REPO_ROOT/init.sh"

# init.sh refuses to scaffold a project from inside the framework
# repo (UAT 2026-04-25 fix U-N). Tests in this suite that exercise
# init.sh therefore run from /tmp. We do the cd once here; all paths
# below are absolute so it is harmless for the other sections.
cd /tmp

PASSED=0
FAILED=0
DOC=0

pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
docn()  { echo "  [DOC]  $1 — $2"; DOC=$((DOC + 1)); }
section() { echo ""; echo "=== $1 ==="; }

# Cross-platform timeout for tests (we don't depend on coreutils timeout).
# Run a command in background; if it doesn't finish within N seconds, kill.
# Sets RC=124 on timeout, else RC=command's exit.
# Uses wall-clock deadline (not iteration counting) — SIGCHLD from other
# backgrounded processes interrupts `sleep 1` early on some shells and
# would otherwise inflate the iteration counter, killing commands long
# before their actual timeout.
run_bounded() {
  local secs="$1"; shift
  ("$@") &
  local pid=$!
  local deadline=$(( $(date +%s) + secs ))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      RC=124
      return 0
    fi
    sleep 1
  done
  wait "$pid" 2>/dev/null
  RC=$?
  return 0
}

# Hook test scaffolding (same shape as test-bypass-detector.sh).
hook_setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  printf '%s\n' '{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}' > "$TMP/.claude/manifest.json"
  echo "[]" > "$TMP/.claude/bypass-audit.json"
}
hook_teardown() { rm -rf "$TMP"; }

# init.sh wrapper. CD's to /tmp first (init refuses to run inside the
# framework repo). Caller passes flags. Bounded at 90s; the suite would
# otherwise hang if a regression reintroduces the resolve-tools bug.
#
# BL-076: --no-remote-creation is baked in so this wrapper is hermetic by
# construction — no caller (present or future) can drive init.sh into a
# real `gh repo create` against an authenticated host. Every current call
# site already passes --no-remote-creation directly; keeping it here means
# the invariant holds even if someone routes a new run through this helper.
run_init() {
  local proj_dir="$1"; shift
  (
    cd /tmp
    run_bounded 90 bash "$INIT" --non-interactive --no-remote-creation \
      --project x --project-dir "$proj_dir" "$@"
    return $RC
  )
}

# ════════════════════════════════════════════════════════════════════
section "1. Novel / unsupported platform"
# ════════════════════════════════════════════════════════════════════

# T1.1: --platform with an unrecognized value is rejected with a clear
# error (not a silent fallback or hang).
T=$(mktemp -d); P="$T/p"
run_bounded 30 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform embedded --language other --track light --deployment personal \
  > "$T/log" 2>&1 < /dev/null
rc=$RC
out=$(cat "$T/log")
if [ "$rc" != "0" ] && echo "$out" | grep -qE "(invalid --platform|platform must be one of)"; then
  pass "T1.1: unknown platform rejected with clear error"
else
  fail_ "T1.1" "rc=$rc; expected non-zero exit + clear message. Got: $(echo "$out" | tail -3 | tr '\n' '|')"
fi
rm -rf "$T"

# T1.2: --platform mcp_server is accepted (per init.sh validation), but
# templates/tool-matrix/mcp_server.json does NOT exist. resolve-tools.sh
# should gracefully fall back to common.json only (not error).
T=$(mktemp -d)
# Bound 30→90 (2026-07-18, BL-134 class): full resolver walks measure ~25s
# idle; load pushed this one to rc=124 in the same session that surfaced
# T2.1/T2.2. Same rationale as the T2 bounds below.
run_bounded 90 bash "$REPO_ROOT/scripts/resolve-tools.sh" \
  --dev-os darwin --platform mcp_server --language other --track light \
  --phase 2 --matrix-dir "$REPO_ROOT/templates/tool-matrix" > "$T/out.json" 2>/dev/null
if [ "$RC" = "0" ] && jq -e '.already_installed' "$T/out.json" >/dev/null 2>&1; then
  pass "T1.2: missing platform matrix degrades to common.json only"
else
  fail_ "T1.2" "resolver rc=$RC; output incomplete"
fi
rm -rf "$T"

# T1.3: --platform other is documented (in available_platforms list and
# host-driver code) but rejected by --platform validation. Tracks the
# inconsistency.
T=$(mktemp -d); P="$T/p"
run_bounded 30 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform other --language other --track light --deployment personal \
  > "$T/log" 2>&1 < /dev/null
rc=$RC
out=$(cat "$T/log")
if [ "$rc" != "0" ] && echo "$out" | grep -qE "invalid --platform"; then
  docn "T1.3: --platform other rejected" "init.sh:2912 case allows only desktop|mobile|web|mcp_server, but lines 2911-elsewhere reference 'other' as if supported. Document mismatch."
else
  pass "T1.3: --platform other accepted (mismatch resolved)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
section "2. Tool customization (--tool-prefs)"
# ════════════════════════════════════════════════════════════════════

# T2.1: A user-added tool whose check_command passes is reported in
# already_installed.
T=$(mktemp -d)
cat > "$T/prefs.json" <<'JSON'
{
  "additions": [
    {"name": "MyTool", "category": "Custom", "check_command": "true", "description": "always-passes sentinel"}
  ]
}
JSON
# Bound raised 30→90 (2026-07-18, full-lane CI flake): a bare resolver run
# on an IDLE machine measures ~25s (the matrix has grown since the bound
# was set), leaving ~5s headroom — under CI-runner or parallel-suite load
# the baseline crosses 30s and rc=124 fires with EMPTY output. 90s keeps a
# real hang detectable while giving the honest baseline 3.5x headroom.
# resolve-tools.sh and the matrix were byte-identical across the failing
# window (diffed 8412b8c..main) — timing-margin debt, not a regression.
run_bounded 90 bash "$REPO_ROOT/scripts/resolve-tools.sh" \
  --dev-os darwin --platform web --language javascript --track light --phase 2 \
  --matrix-dir "$REPO_ROOT/templates/tool-matrix" --tool-prefs "$T/prefs.json" > "$T/out.json" 2>/dev/null
if [ "$RC" = "0" ] && jq -e '.already_installed[] | select(.name == "MyTool")' "$T/out.json" >/dev/null 2>&1; then
  pass "T2.1: custom tool addition with passing check appears in already_installed"
else
  fail_ "T2.1" "rc=$RC; MyTool not in already_installed. Output: $(jq -c '.' "$T/out.json" 2>/dev/null | head -c 200)"
fi
rm -rf "$T"

# T2.2: A user-added tool whose check_command HANGS does not hang the
# resolver (verifies the 2026-06-26 timeout fix in resolve-tools.sh).
# We use `cat </dev/zero | sleep 60` — would hang for 60s on a buggy
# resolver. With the timeout fix, total elapsed must be ~10s.
T=$(mktemp -d)
cat > "$T/prefs.json" <<'JSON'
{
  "additions": [
    {"name": "HangTool", "category": "Custom", "check_command": "sleep 60", "description": "hangs for 60s"}
  ]
}
JSON
start_ts=$(date +%s)
# Bound raised 30→90 (2026-07-18): the old 30s kill-cap CONTRADICTED the
# case's own <50s pass assertion — the watchdog killed at 30 before the
# assertion's discrimination window could exist, so any load spike over
# the ~25s baseline produced rc=124 instead of a verdict. With 90s, a
# hang regression (~70s+ = the sleep 60 + probes) is killed at 90 and
# fails the <60s assertion; the honest timeout path finishes ~25-35s.
run_bounded 90 bash "$REPO_ROOT/scripts/resolve-tools.sh" \
  --dev-os darwin --platform web --language javascript --track light --phase 2 \
  --matrix-dir "$REPO_ROOT/templates/tool-matrix" --tool-prefs "$T/prefs.json" > "$T/out.json" 2>/dev/null
end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
# A hung HangTool should produce MANUAL placement (treated as not-installed).
# Threshold is generous because resolve-tools iterates EVERY tool in the
# matrix, each costing a check + version probe; on an idle machine the
# baseline (without the addition) measures ~25s, and CI-runner load adds
# real variance. A regression means elapsed ~70s+ (the hung sleep 60 +
# outer bounds), comfortably above the 60s line and below the 90s cap.
if [ "$RC" = "0" ] && [ "$elapsed" -lt 60 ]; then
  pass "T2.2: hanging custom check times out cleanly (elapsed=${elapsed}s)"
else
  fail_ "T2.2" "rc=$RC, elapsed=${elapsed}s, expected <60s (regression = ≥70s)"
fi
# Cleanup any orphan sleep processes (the bash -c subshell may be killed
# but its grandchild sleep can linger).
pkill -9 -f "sleep 60" 2>/dev/null || true
rm -rf "$T"

# T2.3: Skipped tool does not appear in any bucket of the resolver
# output.
T=$(mktemp -d)
cat > "$T/prefs.json" <<'JSON'
{"skipped": [{"name": "Docker"}]}
JSON
run_bounded 90 bash "$REPO_ROOT/scripts/resolve-tools.sh" \
  --dev-os darwin --platform web --language javascript --track light --phase 2 \
  --matrix-dir "$REPO_ROOT/templates/tool-matrix" --tool-prefs "$T/prefs.json" > "$T/out.json" 2>/dev/null
docker_in_any=$(jq '[(.already_installed[]?, .auto_install[]?, .manual_install[]?, .deferred[]?) | select(.name == "Docker")] | length' "$T/out.json" 2>/dev/null)
if [ "$RC" = "0" ] && [ "$docker_in_any" = "0" ]; then
  pass "T2.3: skipped tool absent from all resolver buckets"
else
  fail_ "T2.3" "rc=$RC, Docker count=$docker_in_any (expected 0)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
section "3. Git host variation"
# ════════════════════════════════════════════════════════════════════

# T3.1: --git-host gitlab emits .gitlab-ci.yml and does NOT emit
# .github/workflows/ci.yml.
T=$(mktemp -d); P="$T/p"
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light \
  --deployment personal --git-host gitlab > "$T/log" 2>&1 < /dev/null
rc=$RC
if [ -f "$P/.gitlab-ci.yml" ] && [ ! -f "$P/.github/workflows/ci.yml" ]; then
  pass "T3.1: --git-host gitlab emits .gitlab-ci.yml, not .github/workflows/ci.yml"
else
  fail_ "T3.1" "rc=$rc; .gitlab-ci.yml exists=$([ -f "$P/.gitlab-ci.yml" ] && echo y || echo n); .github/workflows/ci.yml exists=$([ -f "$P/.github/workflows/ci.yml" ] && echo y || echo n)"
fi
rm -rf "$T"

# T3.2: --git-host bitbucket emits bitbucket-pipelines.yml.
T=$(mktemp -d); P="$T/p"
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light \
  --deployment personal --git-host bitbucket > "$T/log" 2>&1 < /dev/null
rc=$RC
if [ -f "$P/bitbucket-pipelines.yml" ] && [ ! -f "$P/.github/workflows/ci.yml" ]; then
  pass "T3.2: --git-host bitbucket emits bitbucket-pipelines.yml, not .github/workflows/ci.yml"
else
  fail_ "T3.2" "rc=$rc; bitbucket-pipelines.yml exists=$([ -f "$P/bitbucket-pipelines.yml" ] && echo y || echo n); .github/workflows/ci.yml exists=$([ -f "$P/.github/workflows/ci.yml" ] && echo y || echo n)"
fi
rm -rf "$T"

# T3.3: --git-host gitlab + generate_release emits release pipeline at
# host-appropriate path, NOT .github/workflows/release.yml. This is the
# bug the audit (gemini-review.html) called out: generate_release() in
# init.sh:2436-2456 hardcodes `.github/workflows/release.yml` as the
# output even when host is gitlab/bitbucket.
T=$(mktemp -d); P="$T/p"
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track standard \
  --deployment personal --git-host gitlab > "$T/log" 2>&1 < /dev/null
rc=$RC
# Expected behavior: release artifact in gitlab/ format (or no artifact +
# clear message). Buggy behavior: release.yml written to .github/workflows.
if [ -f "$P/.github/workflows/release.yml" ]; then
  fail_ "T3.3" "BUG: --git-host gitlab still wrote .github/workflows/release.yml (init.sh:2436-2456 hardcodes output path)"
else
  pass "T3.3: --git-host gitlab does not emit .github/workflows/release.yml"
fi
rm -rf "$T"

# T3.4: --git-host other → no CI template emitted, no .github/, no
# .gitlab-ci.yml, no bitbucket-pipelines.yml.
T=$(mktemp -d); P="$T/p"
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light \
  --deployment personal --git-host other --remote-url "https://example.com/x.git" \
  --branch-protection-attested > "$T/log" 2>&1 < /dev/null
rc=$RC
if [ ! -f "$P/.github/workflows/ci.yml" ] && [ ! -f "$P/.gitlab-ci.yml" ] && [ ! -f "$P/bitbucket-pipelines.yml" ]; then
  pass "T3.4: --git-host other emits no CI workflow"
else
  fail_ "T3.4" "rc=$rc; some CI file was written: github=$([ -f "$P/.github/workflows/ci.yml" ] && echo y || echo n) gitlab=$([ -f "$P/.gitlab-ci.yml" ] && echo y || echo n) bitbucket=$([ -f "$P/bitbucket-pipelines.yml" ] && echo y || echo n)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
section "4. Existing-project re-init"
# ════════════════════════════════════════════════════════════════════

# T4.1: init refuses an existing directory by default (safety guard).
T=$(mktemp -d); P="$T/p"; mkdir -p "$P"
run_bounded 30 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light --deployment personal \
  > "$T/log" 2>&1 < /dev/null
rc=$RC
out=$(cat "$T/log")
if [ "$rc" != "0" ] && echo "$out" | grep -qE "(already exists|--allow-existing-dir)"; then
  pass "T4.1: existing dir refused without --allow-existing-dir"
else
  fail_ "T4.1" "rc=$rc; expected non-zero + clear message. Got tail: $(echo "$out" | tail -2 | tr '\n' '|')"
fi
rm -rf "$T"

# T4.2: --allow-existing-dir on a dir containing user files succeeds
# AND preserves the user files (does not clobber).
T=$(mktemp -d); P="$T/p"
mkdir -p "$P/src"
printf '%s\n' '# My App' > "$P/README.md"
printf '%s\n' 'console.log("user code");' > "$P/src/app.js"
USER_README_HASH=$(shasum "$P/README.md" | awk '{print $1}')
USER_APP_HASH=$(shasum "$P/src/app.js" | awk '{print $1}')
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light \
  --deployment personal --allow-existing-dir > "$T/log" 2>&1 < /dev/null
rc=$RC
post_readme_hash=$(shasum "$P/README.md" 2>/dev/null | awk '{print $1}')
post_app_hash=$(shasum "$P/src/app.js" 2>/dev/null | awk '{print $1}')
if [ "$rc" = "0" ] && [ "$USER_README_HASH" = "$post_readme_hash" ] && [ "$USER_APP_HASH" = "$post_app_hash" ]; then
  pass "T4.2: --allow-existing-dir preserves user files (README.md, src/app.js unchanged)"
elif [ "$rc" != "0" ]; then
  fail_ "T4.2" "init exited rc=$rc on existing dir even with --allow-existing-dir. Log tail: $(tail -3 "$T/log" | tr '\n' '|')"
elif [ "$USER_README_HASH" != "$post_readme_hash" ]; then
  docn "T4.2-readme" "README.md was rewritten — preferred behavior is to preserve user content"
elif [ "$USER_APP_HASH" != "$post_app_hash" ]; then
  fail_ "T4.2-app" "src/app.js was modified — init MUST NOT overwrite user code"
fi
rm -rf "$T"

# T4.3: re-init the same project (already initialized) idempotently —
# second run with --allow-existing-dir succeeds.
T=$(mktemp -d); P="$T/p"
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light \
  --deployment personal > "$T/log1" 2>&1 < /dev/null
rc1=$RC
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light \
  --deployment personal --allow-existing-dir > "$T/log2" 2>&1 < /dev/null
rc2=$RC
if [ "$rc1" = "0" ] && [ "$rc2" = "0" ]; then
  pass "T4.3: re-init with --allow-existing-dir succeeds (rc1=$rc1 rc2=$rc2)"
else
  fail_ "T4.3" "rc1=$rc1 rc2=$rc2. log2 tail: $(tail -3 "$T/log2" | tr '\n' '|')"
fi
rm -rf "$T"

# T4.4: init in a non-empty git repo preserves the existing .git/
# history.
T=$(mktemp -d); P="$T/p"
mkdir -p "$P"
( cd "$P" && git init -q && git config user.email t@t.l && git config user.name t \
    && printf 'pre-existing\n' > README.md && git add README.md \
    && git commit -q -m "initial" )
ORIG_HEAD=$(cd "$P" && git rev-parse HEAD)
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language typescript --track light \
  --deployment personal --allow-existing-dir > "$T/log" 2>&1 < /dev/null
rc=$RC
POST_HEAD=$(cd "$P" && git rev-parse HEAD 2>/dev/null)
if [ "$rc" = "0" ] && [ "$ORIG_HEAD" = "$POST_HEAD" ]; then
  pass "T4.4: init on non-empty git repo preserves git HEAD"
elif [ "$rc" != "0" ]; then
  fail_ "T4.4" "init rc=$rc on non-empty repo"
else
  docn "T4.4" "init advanced git HEAD ($ORIG_HEAD → $POST_HEAD) — likely added init commit. Document as expected if intentional."
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
section "5. bypass-detector envelope edges"
# ════════════════════════════════════════════════════════════════════

# T5.1: stop_hook_active=true → re-entrancy guard exits before scan,
# no audit row written, no sentinel.
hook_setup
echo '{"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"use --no-verify here"}' \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
sent_exists=$([ -f "$TMP/.claude/pending-approval.json" ] && echo y || echo n)
if [ "$rows" = "0" ] && [ "$sent_exists" = "n" ]; then
  pass "T5.1: stop_hook_active=true skips scan (no row, no sentinel)"
else
  fail_ "T5.1" "rows=$rows sentinel=$sent_exists"
fi
hook_teardown

# T5.2: PostToolUse with tool_response as a string (Read tool shape)
# falls through to the empty-string fallback (no .stdout/.stderr/etc.).
# Detector should silently no-op (which is the correct degradation —
# Read output isn't a bypass-proposal surface).
hook_setup
echo '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"/tmp/x"},"tool_response":"file contents go here"}' \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
if [ "$rows" = "0" ]; then
  pass "T5.2: tool_response-as-string silently no-ops (correct)"
else
  fail_ "T5.2" "rows=$rows (expected 0 — string tool_response should not trigger)"
fi
hook_teardown

# T5.3: PostToolUse with tool_response.content (Edit/Write shape) fires.
hook_setup
echo '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"/tmp/x"},"tool_response":{"content":"alternatively run git commit --no-verify"}}' \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then
  pass "T5.3: tool_response.content shape fires detector"
else
  fail_ "T5.3" "rows=$rows (expected ≥1 — tool_response.content should be scanned)"
fi
hook_teardown

# T5.4: PostToolUse with unicode in pattern text.
hook_setup
echo '{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"stdout":"русский: try --no-verify 🚀 to skip"}}' \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then
  pass "T5.4: unicode-surrounded pattern still fires"
else
  fail_ "T5.4" "rows=$rows (expected ≥1)"
fi
hook_teardown

# T5.5: Very large tool_response.stdout (~512KB) doesn't crash and still
# fires for an embedded pattern.
hook_setup
LARGE=$(python3 -c "import sys; sys.stdout.write(('lorem ' * 100000) + ' run with --no-verify ' + ('more text ' * 1000))")
printf '{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{"stdout":%s}}' "$(printf '%s' "$LARGE" | jq -Rs '.')" \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then
  pass "T5.5: large (>500KB) payload still fires detector"
else
  fail_ "T5.5" "rows=$rows (expected ≥1)"
fi
hook_teardown

# T5.6: Malformed JSON envelope → silent no-op (no crash, no row).
hook_setup
echo 'this is { not json at all >>> ' \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rc=$?
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
if [ "$rc" = "0" ] && [ "$rows" = "0" ]; then
  pass "T5.6: malformed JSON envelope → silent no-op"
else
  fail_ "T5.6" "rc=$rc rows=$rows"
fi
hook_teardown

# T5.7: Empty tool_response object → no-op.
hook_setup
echo '{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_response":{}}' \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
if [ "$rows" = "0" ]; then
  pass "T5.7: empty tool_response object → no-op"
else
  fail_ "T5.7" "rows=$rows (expected 0)"
fi
hook_teardown

# T5.8: Stop envelope with transcript_path pointing at a real file with
# an assistant turn containing a bypass pattern — detector should tail
# the file when last_assistant_message is empty.
hook_setup
TPATH="$TMP/transcript.jsonl"
printf '%s\n' '{"role":"assistant","content":"trying alternative: run git commit --no-verify here"}' > "$TPATH"
printf '{"hook_event_name":"Stop","last_assistant_message":"","transcript_path":"%s"}\n' "$TPATH" \
  | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then
  pass "T5.8: transcript_path tail fallback fires when last_assistant_message is empty"
else
  fail_ "T5.8" "rows=$rows (expected ≥1; tail of transcript_path JSONL should have surfaced the pattern)"
fi
hook_teardown

# ════════════════════════════════════════════════════════════════════
section "6. intake-wizard render edges"
# ════════════════════════════════════════════════════════════════════

# Standalone render harness: extract render_intake_file from
# scripts/intake-wizard.sh and exercise it directly via a shim script.
WIZARD="$REPO_ROOT/scripts/intake-wizard.sh"
RENDER_SHIM=$(mktemp)
cat > "$RENDER_SHIM" <<SHIM
#!/usr/bin/env bash
PROJECT_ROOT="\${1:?need PROJECT_ROOT}"
PROGRESS_FILE="\$PROJECT_ROOT/.claude/intake-progress.json"
INTAKE_FILE="\$PROJECT_ROOT/PROJECT_INTAKE.md"
FRAMEWORK_ROOT="$REPO_ROOT"
$(awk '/^render_intake_file\(\) \{/,/^}$/' "$WIZARD")
render_intake_file
SHIM
chmod +x "$RENDER_SHIM"

# T6.1: render with empty answers writes a "No answers recorded yet"
# appendix block.
T=$(mktemp -d); mkdir -p "$T/.claude"
printf '{"project_name":"x","completed_sections":[],"last_section":0,"answers":{}}' > "$T/.claude/intake-progress.json"
printf '# Existing intake header\n' > "$T/PROJECT_INTAKE.md"
bash "$RENDER_SHIM" "$T" >/dev/null 2>&1
if grep -q "INTAKE_ANSWERS_BEGIN" "$T/PROJECT_INTAKE.md" \
   && grep -q "No answers recorded yet" "$T/PROJECT_INTAKE.md"; then
  pass "T6.1: render with empty answers produces 'No answers recorded yet' appendix"
else
  fail_ "T6.1" "appendix missing or malformed"
fi
rm -rf "$T"

# T6.2: pipe character in answer value is escaped so the Markdown table
# stays valid (cell doesn't break).
T=$(mktemp -d); mkdir -p "$T/.claude"
printf '%s' '{"project_name":"x","completed_sections":[],"last_section":0,"answers":{"k":"alpha | beta"}}' > "$T/.claude/intake-progress.json"
printf '# Header\n' > "$T/PROJECT_INTAKE.md"
bash "$RENDER_SHIM" "$T" >/dev/null 2>&1
# The escape uses backslash-pipe in source — visually it stays | but the
# raw bytes have an escape. Either way the row should still parse.
if grep -E '\| `k` \| .*alpha.*beta.* \|' "$T/PROJECT_INTAKE.md" >/dev/null; then
  pass "T6.2: pipe in answer value is preserved (row remains a valid table cell)"
else
  fail_ "T6.2" "row missing or malformed for pipe-containing answer"
fi
rm -rf "$T"

# T6.3: newline in answer value is collapsed (so the row stays on one
# table line).
T=$(mktemp -d); mkdir -p "$T/.claude"
printf '%s' '{"project_name":"x","completed_sections":[],"last_section":0,"answers":{"k":"line1\nline2\nline3"}}' > "$T/.claude/intake-progress.json"
printf '# Header\n' > "$T/PROJECT_INTAKE.md"
bash "$RENDER_SHIM" "$T" >/dev/null 2>&1
# Count lines containing "line1" — should be one (collapsed to one row).
line1_rows=$(grep -c "line1" "$T/PROJECT_INTAKE.md")
multi_row_breakage=$(awk '/INTAKE_ANSWERS_BEGIN/,/INTAKE_ANSWERS_END/' "$T/PROJECT_INTAKE.md" | grep -c '^line2$\|^line3$')
if [ "$line1_rows" = "1" ] && [ "$multi_row_breakage" = "0" ]; then
  pass "T6.3: newlines in answer value collapsed to one row"
else
  fail_ "T6.3" "newlines broke the row (line1_rows=$line1_rows, naked-line-rows=$multi_row_breakage)"
fi
rm -rf "$T"

# T6.4: render idempotency — call N times, exactly one appendix block.
T=$(mktemp -d); mkdir -p "$T/.claude"
printf '%s' '{"project_name":"x","completed_sections":[],"last_section":0,"answers":{"k":"v"}}' > "$T/.claude/intake-progress.json"
printf '# Header\n' > "$T/PROJECT_INTAKE.md"
bash "$RENDER_SHIM" "$T" >/dev/null 2>&1
bash "$RENDER_SHIM" "$T" >/dev/null 2>&1
bash "$RENDER_SHIM" "$T" >/dev/null 2>&1
begins=$(grep -c "INTAKE_ANSWERS_BEGIN" "$T/PROJECT_INTAKE.md")
ends=$(grep -c "INTAKE_ANSWERS_END" "$T/PROJECT_INTAKE.md")
if [ "$begins" = "1" ] && [ "$ends" = "1" ]; then
  pass "T6.4: render is idempotent — exactly one BEGIN/END after 3 calls"
else
  fail_ "T6.4" "begins=$begins ends=$ends (expected 1 each)"
fi
rm -rf "$T"

# T6.5: render creates PROJECT_INTAKE.md when it doesn't exist.
T=$(mktemp -d); mkdir -p "$T/.claude"
printf '%s' '{"project_name":"x","completed_sections":[],"last_section":0,"answers":{"k":"v"}}' > "$T/.claude/intake-progress.json"
bash "$RENDER_SHIM" "$T" >/dev/null 2>&1
if [ -f "$T/PROJECT_INTAKE.md" ] && grep -q "INTAKE_ANSWERS_BEGIN" "$T/PROJECT_INTAKE.md"; then
  pass "T6.5: render creates PROJECT_INTAKE.md when missing (from template + appendix)"
else
  fail_ "T6.5" "PROJECT_INTAKE.md not created or appendix missing"
fi
rm -rf "$T"

rm -f "$RENDER_SHIM"

# ════════════════════════════════════════════════════════════════════
section "7. resolve-tools.sh timeout regression"
# ════════════════════════════════════════════════════════════════════

# T7.1: resolve-tools.sh, given a tool matrix entry with a check_command
# that hangs, must return within ~timeout × 2 instead of hanging the
# whole script. This regression-tests the 2026-06-26 fix where
# `colima version` was hanging init.sh forever.
T=$(mktemp -d)
mkdir -p "$T/matrix"
cat > "$T/matrix/common.json" <<'JSON'
{
  "tools": [
    {
      "name": "FakeHang",
      "category": "test",
      "phase": 1,
      "required": false,
      "auto_installable": false,
      "platforms": ["all"],
      "languages": ["all"],
      "tracks": ["light","standard","full"],
      "dev_os": ["darwin","linux"],
      "check_command": "command -v fake-hang-binary",
      "version_command": "sleep 60",
      "install": {"manual": "n/a"},
      "description": "fake tool for testing version_command timeout"
    },
    {
      "name": "FakeOK",
      "category": "test",
      "phase": 1,
      "required": false,
      "auto_installable": false,
      "platforms": ["all"],
      "languages": ["all"],
      "tracks": ["light","standard","full"],
      "dev_os": ["darwin","linux"],
      "check_command": "true",
      "version_command": "echo 1.0.0",
      "install": {"manual": "n/a"},
      "description": "sanity tool"
    }
  ]
}
JSON
# Force FakeHang's check_command to succeed by faking the binary on
# PATH for this subshell.
SHIM_BIN="$T/shim"
mkdir -p "$SHIM_BIN"
cat > "$SHIM_BIN/fake-hang-binary" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$SHIM_BIN/fake-hang-binary"
start_ts=$(date +%s)
PATH="$SHIM_BIN:$PATH" run_bounded 90 bash "$REPO_ROOT/scripts/resolve-tools.sh" \
  --dev-os darwin --platform web --language other --track light --phase 1 \
  --matrix-dir "$T/matrix" > "$T/out.json" 2>/dev/null
rc=$RC
end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
# With 10s default timeout, elapsed should be ~10s + small overhead.
# 25s is a comfortable upper bound.
if [ "$rc" = "0" ] && [ "$elapsed" -lt 25 ]; then
  pass "T7.1: resolve-tools tolerates hanging version_command (elapsed=${elapsed}s, rc=$rc)"
else
  fail_ "T7.1" "elapsed=${elapsed}s rc=$rc (expected rc=0, elapsed<25s)"
fi
pkill -9 -f "sleep 60" 2>/dev/null || true
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "Edge-case results: $PASSED passed, $FAILED failed, $DOC documented"
[ "$FAILED" -eq 0 ]

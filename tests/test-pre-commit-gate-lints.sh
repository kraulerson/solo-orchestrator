#!/usr/bin/env bash
# tests/test-pre-commit-gate-lints.sh
#
# Cycle-8 slot-5 — operator-side promotion of the two CI lints
# (counter-antipattern + backlog-references) into pre-commit-gate.sh.
# Verifies both integration points (PreToolUse JSON path + the
# --terminal-mode branch invoked from framework-gate.sh) plus the
# SKIP_LINT=1 escape hatch.
#
# Style mirrors tests/test-pre-commit-gate-classifier.sh and
# tests/test-pre-commit-gate-terminal-mode.sh: per-test mktemp
# fixtures, JSON tool_input piping for the PreToolUse path, direct
# script invocation for the --terminal-mode path.
#
# NOTE on antipattern fixtures: the counter-antipattern lint scans
# tests/*.sh too, so any literal `VAR=$(...grep -c...|| echo "0")`
# in THIS file would trip the lint against our own test source. We
# therefore build the antipattern line dynamically from single-quoted
# fragments — the lint regex requires `=\$(` and won't match an
# assignment whose RHS is a quoted string.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
CA_LINT_SRC="$REPO_ROOT/scripts/lint-counter-antipattern.sh"
BR_LINT_SRC="$REPO_ROOT/scripts/lint-backlog-references.sh"
FF_LINT_SRC="$REPO_ROOT/scripts/lint-fix-functions-stderr.sh"
RR_LINT_SRC="$REPO_ROOT/scripts/lint-raw-read-prompt.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# write_bad_script PATH — writes a shell script whose body contains
# the canonical unsanitized counter-capture antipattern. Built from
# string fragments so this very test file does not trip the lint.
write_bad_script() {
  local out="$1"
  local antipat
  antipat='COUNT=$(grep -c FOO somefile 2>/dev/null || echo '
  antipat+='"0")'
  {
    echo '#!/usr/bin/env bash'
    echo "$antipat"
    echo '[ "$COUNT" -gt 0 ] && echo hi'
  } > "$out"
}

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  mkdir -p "$PROJ/scripts/lib"

  cp "$CA_LINT_SRC" "$PROJ/scripts/lint-counter-antipattern.sh"
  cp "$BR_LINT_SRC" "$PROJ/scripts/lint-backlog-references.sh"
  cp "$FF_LINT_SRC" "$PROJ/scripts/lint-fix-functions-stderr.sh"
  cp "$RR_LINT_SRC" "$PROJ/scripts/lint-raw-read-prompt.sh"
  chmod +x "$PROJ/scripts/lint-counter-antipattern.sh"
  chmod +x "$PROJ/scripts/lint-backlog-references.sh"
  chmod +x "$PROJ/scripts/lint-fix-functions-stderr.sh"
  chmod +x "$PROJ/scripts/lint-raw-read-prompt.sh"

  cp "$REPO_ROOT/scripts/process-checklist.sh" "$PROJ/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" "$PROJ/scripts/lib/"
  chmod +x "$PROJ/scripts/process-checklist.sh"

  (
    cd "$PROJ"
    git init -q -b main
    git config user.email "t@t.l"
    git config user.name "t"
    git remote add origin https://example.com/x.git 2>/dev/null || true
  )

  mkdir -p "$PROJ/.claude"
  cat > "$PROJ/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  cat > "$PROJ/.claude/phase-state.json" <<EOF
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
EOF
  cat > "$PROJ/.claude/process-state.json" <<'EOF'
{"phase2_init":{"verified":true,"steps_completed":["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied","initialization_verified"]},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
EOF

  cat > "$PROJ/solo-orchestrator-backlog.md" <<'EOF'
## BL-001: seed entry
**Status:** Closed — shipped 2026-01-01 (PR #1)
Body.
EOF
}
teardown() { rm -rf "$TMP"; }

# Pipe a JSON tool_input.command into the gate. Echo "EXIT|STDOUT" so
# tests can grep the JSON permissionDecision block.
run_hook() {
  local cmd="$1"
  local input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$( cd "$PROJ" && printf '%s' "$input" | bash "$GATE" 2>&1 ) || rc=$?
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')"
}

# Same as run_hook, but exports SKIP_LINT=1 for the subshell.
run_hook_skip_lint() {
  local cmd="$1"
  local input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$( cd "$PROJ" && export SKIP_LINT=1; printf '%s' "$input" | bash "$GATE" 2>&1 ) || rc=$?
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')"
}

stage_file() {
  local path="$1" content="$2"
  mkdir -p "$PROJ/$(dirname "$path")"
  printf '%s' "$content" > "$PROJ/$path"
  ( cd "$PROJ" && git add "$path" )
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: PreToolUse — counter-antipattern lint passes on clean staged file ==="
# ════════════════════════════════════════════════════════════════════
setup
stage_file "README.md" "# clean docs change"
out=$(run_hook 'git commit -m "docs: update readme (BL-001)"')
if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
  pass "T1: clean staged file passes counter-antipattern lint"
else
  fail_ "T1" "unexpected deny on clean fixture: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: PreToolUse — counter-antipattern lint blocks when scripts/ has antipattern ==="
# ════════════════════════════════════════════════════════════════════
# The lint walks scripts/ — staging is irrelevant. Drop a bad script
# into scripts/ and any commit attempt must be blocked.
setup
write_bad_script "$PROJ/scripts/bad.sh"
( cd "$PROJ" && git add scripts/bad.sh )
out=$(run_hook 'git commit -m "docs: trivial (BL-001)"')
body="${out#*|}"
if [[ "$body" == *'"permissionDecision": "deny"'* ]] && \
   [[ "$body" == *"counter-antipattern"* ]]; then
  pass "T2: staged file with antipattern is blocked"
else
  fail_ "T2" "expected deny mentioning counter-antipattern; got: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: PreToolUse — backlog-references lint passes on valid BL-001 cite ==="
# ════════════════════════════════════════════════════════════════════
setup
stage_file "README.md" "# tweak"
out=$(run_hook 'git commit -m "docs: cite real entry (BL-001)"')
if [[ "${out#*|}" != *'"permissionDecision": "deny"'* ]]; then
  pass "T3: valid BL-001 in message passes"
else
  fail_ "T3" "unexpected deny for valid BL-001: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: PreToolUse — backlog-references lint blocks unknown BL-999 ==="
# ════════════════════════════════════════════════════════════════════
setup
stage_file "README.md" "# tweak"
out=$(run_hook 'git commit -m "docs: typo (BL-999)"')
body="${out#*|}"
if [[ "$body" == *'"permissionDecision": "deny"'* ]] && \
   [[ "$body" == *"backlog-references"* ]] && \
   [[ "$body" == *"BL-999"* ]]; then
  pass "T4: unknown BL-999 in message is blocked"
else
  fail_ "T4" "expected deny mentioning backlog-references + BL-999; got: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: SKIP_LINT=1 bypasses both lints (PreToolUse path) ==="
# ════════════════════════════════════════════════════════════════════
# Stage both failure conditions (bad script + unknown BL). Without
# SKIP_LINT this would fail T2 + T4. With SKIP_LINT the lints are
# skipped — anything downstream may still allow or warn, but neither
# the counter-antipattern nor BL-999 diagnostic must appear.
setup
write_bad_script "$PROJ/scripts/bad.sh"
( cd "$PROJ" && git add scripts/bad.sh )
out=$(run_hook_skip_lint 'git commit -m "docs: bypass (BL-999)"')
body="${out#*|}"
# Invariants: (a) the SKIP_LINT acknowledgement appears on stderr; (b)
# neither lint's failure diagnostic appears in the deny block. Use the
# specific failure prefixes (`...lint-...sh failed` / `unknown BL`) so
# the SKIP_LINT bypass message itself — which mentions the lint names —
# doesn't false-positive the check.
if [[ "$body" == *"SKIP_LINT=1 set"* ]] && \
   [[ "$body" != *"lint-counter-antipattern.sh failed"* ]] && \
   [[ "$body" != *"unknown BL reference 'BL-999'"* ]]; then
  pass "T5: SKIP_LINT=1 bypasses both lints"
else
  fail_ "T5" "SKIP_LINT did not bypass lint; got: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: --terminal-mode — both lints fire on framework-installed projects ==="
# ════════════════════════════════════════════════════════════════════
setup
write_bad_script "$PROJ/scripts/bad.sh"
( cd "$PROJ" && git add scripts/bad.sh )
echo "docs: trivial (BL-001)" > "$PROJ/.git/COMMIT_EDITMSG"
out=$( cd "$PROJ" && bash "$GATE" --terminal-mode 2>&1 >/dev/null || true )
if echo "$out" | grep -qE 'counter-antipattern lint failed'; then
  pass "T6a: --terminal-mode fires counter-antipattern lint"
else
  fail_ "T6a" "--terminal-mode did not surface counter-antipattern lint: $out"
fi
# Remove antipattern fixture and switch to an unknown BL.
rm "$PROJ/scripts/bad.sh"
( cd "$PROJ" && git reset HEAD -- scripts/bad.sh >/dev/null 2>&1 || true )
echo "docs: typo (BL-999)" > "$PROJ/.git/COMMIT_EDITMSG"
out=$( cd "$PROJ" && bash "$GATE" --terminal-mode 2>&1 >/dev/null || true )
if echo "$out" | grep -qE 'backlog-references lint failed'; then
  pass "T6b: --terminal-mode fires backlog-references lint"
else
  fail_ "T6b" "--terminal-mode did not surface backlog-references lint: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: docs-only commit still triggers structural lints ==="
# ════════════════════════════════════════════════════════════════════
# Per the slot-5 contract: lint scope is structural (file tree + commit
# message tokens), not phase-gated. A docs-only commit with an unknown
# BL token MUST still be blocked — otherwise the operator-side gate
# has a docs-shaped blind spot vs CI.
setup
stage_file "docs/notes.md" "# notes"
out=$(run_hook 'git commit -m "docs: rev (BL-999)"')
body="${out#*|}"
if [[ "$body" == *'"permissionDecision": "deny"'* ]] && \
   [[ "$body" == *"BL-999"* ]]; then
  pass "T7: docs-only commit with unknown BL is blocked (lint is structural)"
else
  fail_ "T7" "expected deny on docs-only commit with unknown BL; got: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: PreToolUse — fix-functions-stderr lint blocks unfixed silencer ==="
# ════════════════════════════════════════════════════════════════════
# Drop a script with a fix_*() body that silences stderr — the
# project-local lint copy at scripts/lint-fix-functions-stderr.sh
# should fire from the gate. Built with single-quoted heredoc so the
# fixture text does NOT trip the lint scanning THIS test file
# (tests/*.sh are part of TARGET_GLOBS in some lints).
setup
cat > "$PROJ/scripts/has-bad-fix.sh" <<'SH'
#!/usr/bin/env bash
fix_silent_thing() {
  git clone -q https://x.invalid/r.git target 2>/dev/null
}
SH
( cd "$PROJ" && git add scripts/has-bad-fix.sh )
out=$(run_hook 'git commit -m "docs: trivial (BL-001)"')
body="${out#*|}"
if [[ "$body" == *'"permissionDecision": "deny"'* ]] && \
   [[ "$body" == *"fix-functions-stderr"* ]]; then
  pass "T8: fix-functions-stderr violation in scripts/ is blocked"
else
  fail_ "T8" "expected deny mentioning fix-functions-stderr; got: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9: PreToolUse — raw-read-prompt lint blocks raw read -rp ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/has-bare-read.sh" <<'SH'
#!/usr/bin/env bash
read -rp "Proceed? [y/N]: " yn
echo "$yn"
SH
( cd "$PROJ" && git add scripts/has-bare-read.sh )
out=$(run_hook 'git commit -m "docs: trivial (BL-001)"')
body="${out#*|}"
if [[ "$body" == *'"permissionDecision": "deny"'* ]] && \
   [[ "$body" == *"raw-read-prompt"* ]]; then
  pass "T9: raw-read-prompt violation in scripts/ is blocked"
else
  fail_ "T9" "expected deny mentioning raw-read-prompt; got: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: SKIP_LINT=1 bypasses ALL FOUR lints (PreToolUse path) ==="
# ════════════════════════════════════════════════════════════════════
# Mirror of T5 but with both new lints in the failure set. SKIP_LINT
# must bypass all four; the acknowledgement message must NOT contain
# the per-lint failure prefix.
setup
write_bad_script "$PROJ/scripts/bad.sh"
cat > "$PROJ/scripts/has-bad-fix.sh" <<'SH'
#!/usr/bin/env bash
fix_silent_thing() {
  git clone -q https://x.invalid/r.git target 2>/dev/null
}
SH
cat > "$PROJ/scripts/has-bare-read.sh" <<'SH'
#!/usr/bin/env bash
read -rp "Proceed? [y/N]: " yn
SH
( cd "$PROJ" && git add scripts/bad.sh scripts/has-bad-fix.sh scripts/has-bare-read.sh )
out=$(run_hook_skip_lint 'git commit -m "docs: bypass (BL-999)"')
body="${out#*|}"
if [[ "$body" == *"SKIP_LINT=1 set"* ]] && \
   [[ "$body" != *"lint-counter-antipattern.sh failed"* ]] && \
   [[ "$body" != *"lint-fix-functions-stderr.sh failed"* ]] && \
   [[ "$body" != *"lint-raw-read-prompt.sh failed"* ]] && \
   [[ "$body" != *"unknown BL reference 'BL-999'"* ]]; then
  pass "T10: SKIP_LINT=1 bypasses all four lints"
else
  fail_ "T10" "SKIP_LINT did not bypass all four lints; got: $out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: --terminal-mode — new lints fire on framework-installed projects ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/has-bad-fix.sh" <<'SH'
#!/usr/bin/env bash
fix_silent_thing() {
  git clone -q https://x.invalid/r.git target 2>/dev/null
}
SH
( cd "$PROJ" && git add scripts/has-bad-fix.sh )
echo "docs: trivial (BL-001)" > "$PROJ/.git/COMMIT_EDITMSG"
out=$( cd "$PROJ" && bash "$GATE" --terminal-mode 2>&1 >/dev/null || true )
if echo "$out" | grep -qE 'fix-functions-stderr lint failed'; then
  pass "T11a: --terminal-mode fires fix-functions-stderr lint"
else
  fail_ "T11a" "--terminal-mode did not surface fix-functions-stderr lint: $out"
fi
rm "$PROJ/scripts/has-bad-fix.sh"
( cd "$PROJ" && git reset HEAD -- scripts/has-bad-fix.sh >/dev/null 2>&1 || true )
cat > "$PROJ/scripts/has-bare-read.sh" <<'SH'
#!/usr/bin/env bash
read -rp "Proceed? [y/N]: " yn
SH
( cd "$PROJ" && git add scripts/has-bare-read.sh )
echo "docs: trivial (BL-001)" > "$PROJ/.git/COMMIT_EDITMSG"
out=$( cd "$PROJ" && bash "$GATE" --terminal-mode 2>&1 >/dev/null || true )
if echo "$out" | grep -qE 'raw-read-prompt lint failed'; then
  pass "T11b: --terminal-mode fires raw-read-prompt lint"
else
  fail_ "T11b" "--terminal-mode did not surface raw-read-prompt lint: $out"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

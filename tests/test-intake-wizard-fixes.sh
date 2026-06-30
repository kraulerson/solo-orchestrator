#!/usr/bin/env bash
# tests/test-intake-wizard-fixes.sh
#
# Tests for the three S3 fixes in scripts/intake-wizard.sh:
#   - code-intake-wizard-3: wizard section numbering aligns with template
#   - code-intake-wizard-5: pause is immediate (no further save_answer writes)
#   - code-intake-wizard-6: Competency Matrix captures the
#       "Automated Tooling Required?" third column
#
# Plus a regression guard for the wizard's print_step / Claude-mode prompt
# section count drift (bonus catch: "All 8 pre-conditions", "Sections 1-13").
#
# Style mirrors tests/test-lint-counter-antipattern.sh: set -uo pipefail,
# isolated fixtures, per-case pass/fail counters, RED-before-GREEN
# verification by inspection (no shared state between cases).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIZARD="$REPO_ROOT/scripts/intake-wizard.sh"
TEMPLATE="$REPO_ROOT/templates/project-intake.md"

if [ ! -f "$WIZARD" ]; then
  echo "FATAL: intake-wizard.sh not found at $WIZARD" >&2
  exit 2
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "FATAL: project-intake.md template not found at $TEMPLATE" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ----------------------------------------------------------------
# T1 (code-intake-wizard-3): wizard print_step labels must match
# the template's `## N. Title` headings for every numbered section.
# ----------------------------------------------------------------
echo ""
echo "T1: wizard section labels match template headings"

# Extract template section number → title map (skip 11.5 — printed
# separately by run_section_11_5 in the wizard).
template_pairs=$(awk -F': ' '
  /^##[[:space:]]+[0-9]+\.[[:space:]]/ {
    sub(/^##[[:space:]]+/, "")
    # Trim trailing parenthetical qualifiers like "(Standard+ Track ...)"
    sub(/[[:space:]]+\(.*\)$/, "")
    print
  }
' "$TEMPLATE")

# Pull every print_step "Section N: Title" line from the wizard.
wizard_pairs=$(grep -oE 'print_step "Section [0-9]+(\.[0-9]+)?: [^"]+"' "$WIZARD" \
  | sed -e 's/^print_step "Section //' -e 's/"$//')

drift_found=0
while IFS= read -r tpl_line; do
  tpl_num="${tpl_line%%.*}"
  tpl_title=$(echo "$tpl_line" | sed -E 's/^[0-9]+\.[[:space:]]*//')
  # Find wizard line for this section.
  wiz_line=$(echo "$wizard_pairs" | awk -v n="$tpl_num" -F': ' '
    $1 == n { print; exit }
  ')
  if [ -z "$wiz_line" ]; then
    # 11 has no template heading qualifier; the only sections without a
    # matching print_step in the wizard are §12 (auto-populated, no prompt).
    # Don't flag this as drift — it's wired in run_section_12 by design.
    if [ "$tpl_num" = "12" ]; then
      continue
    fi
    fail_ "T1" "wizard missing print_step for template Section $tpl_num ($tpl_title)"
    drift_found=1
    continue
  fi
  wiz_title=$(echo "$wiz_line" | sed -E 's/^[0-9]+:[[:space:]]*//')
  # BL-037 closure: the pre-fix oracle compared `${wiz_line%%:*}` (i.e.
  # the number prefix) to `$tpl_num` — but `wiz_line` was selected by
  # awk's `$1 == n` filter, so by construction the number prefix is
  # `$tpl_num`. The comparison was a tautology and the `wiz_title`
  # variable computed on the line above was never consumed. A wizard
  # entry like `print_step "Section 4: Compliance Audit"` against
  # template `## 4. Features & Requirements` (number preserved, title
  # corrupted) silently passed.
  #
  # New assertion: pin BOTH halves of the pair.
  #   (a) Number prefix matches (preserves the pre-fix sanity check
  #       — even though it was structurally redundant, future refactors
  #       might change the awk filter).
  #   (b) Title alignment: template title is canonical, wizard may
  #       shorten the trailing qualifier (e.g. tpl "Distribution &
  #       Operations Preferences" vs wiz "Distribution & Operations").
  #       Accept iff (case-insensitive) the wizard title is a non-empty
  #       prefix of the template title OR vice-versa. Any unrelated
  #       drift (different leading words, swapped section bodies) fails.
  if [ "${wiz_line%%:*}" != "$tpl_num" ]; then
    fail_ "T1" "wizard section number drift at template §$tpl_num: wizard shows '$wiz_line'"
    drift_found=1
  fi
  if [ -z "$wiz_title" ]; then
    fail_ "T1" "wizard §$tpl_num has empty title (template title: '$tpl_title')"
    drift_found=1
  else
    wiz_title_lc=$(printf '%s' "$wiz_title" | tr '[:upper:]' '[:lower:]')
    tpl_title_lc=$(printf '%s' "$tpl_title" | tr '[:upper:]' '[:lower:]')
    # Case-insensitive bidirectional prefix match handles the wizard's
    # documented shortening (e.g. drop trailing "Preferences"). Pure
    # substring would over-match; require prefix.
    if [ "${tpl_title_lc#"$wiz_title_lc"}" = "$tpl_title_lc" ] && \
       [ "${wiz_title_lc#"$tpl_title_lc"}" = "$wiz_title_lc" ]; then
      fail_ "T1" "wizard §$tpl_num title drift: wizard='$wiz_title' template='$tpl_title' (neither is a case-insensitive prefix of the other)"
      drift_found=1
    fi
  fi
done <<<"$template_pairs"

# Also: the wizard's section-12 label must match template §12
# (Tooling Configuration), not "Agent Initialization Prompt".
if grep -qE 'print_step "Section 12: Agent Initialization Prompt"' "$WIZARD"; then
  fail_ "T1" "wizard §12 still labelled 'Agent Initialization Prompt' (should be Tooling Configuration; that label belongs to §13)"
  drift_found=1
fi

# And: a §13 label for Agent Initialization Prompt must exist.
if ! grep -qE 'print_step "Section 13: Agent Initialization Prompt"' "$WIZARD"; then
  fail_ "T1" "wizard missing 'Section 13: Agent Initialization Prompt' label (template §13)"
  drift_found=1
fi

if [ "$drift_found" -eq 0 ]; then
  pass "T1: wizard print_step labels align with template Section numbers"
fi

# ----------------------------------------------------------------
# T2 (code-intake-wizard-3, ancillary): the Claude-mode generated
# prompt must reference the correct section range (1-13, not 1-12).
# ----------------------------------------------------------------
echo ""
echo "T2: Claude-mode prompt section range matches template"
if grep -qE 'Walk through PROJECT_INTAKE.md section by section \(Sections 1-12\)' "$WIZARD"; then
  fail_ "T2" "Claude-mode prompt still says 'Sections 1-12' (should be 1-13)"
elif grep -qE 'Walk through PROJECT_INTAKE.md section by section \(Sections 1-13\)' "$WIZARD"; then
  pass "T2: Claude-mode prompt covers Sections 1-13"
else
  fail_ "T2" "Claude-mode 'Walk through ... Sections N-M' line not found in wizard"
fi

# ----------------------------------------------------------------
# T3 (bonus): "All 6 pre-conditions required" — the preconditions
# array has 8 items; the count must match.
# ----------------------------------------------------------------
echo ""
echo "T3: Production-Build pre-condition count matches preconditions array"
precond_count=$(awk '
  /^  local preconditions=\(/ { inside=1; next }
  inside && /^  \)/ { inside=0 }
  inside && /^[[:space:]]+"/ { count++ }
  END { print count+0 }
' "$WIZARD")
if [ "${precond_count:-0}" -ne 8 ]; then
  fail_ "T3" "expected 8 preconditions in run_section_8 array, found ${precond_count:-0}"
elif grep -qE '\*\*Production Build:\*\* All 6 pre-conditions required' "$WIZARD"; then
  fail_ "T3" "wizard Claude-mode says 'All 6 pre-conditions' but the array has 8 entries"
elif grep -qE '\*\*Production Build:\*\* All 8 pre-conditions required' "$WIZARD"; then
  pass "T3: Production-Build prompt correctly references all 8 pre-conditions"
else
  fail_ "T3" "Claude-mode 'Production Build' pre-condition count line not found"
fi

# ----------------------------------------------------------------
# T4 (code-intake-wizard-5): pause is immediate — once "pause" is
# typed at a prompt, no further save_answer writes happen in that
# section. We exercise prompt_input + save_answer in a sourced
# subshell with stdin pre-loaded with "pause".
# ----------------------------------------------------------------
echo ""
echo "T4: pause short-circuits prompt_input and skips save_answer writes"
if ! command -v python3 >/dev/null 2>&1; then
  echo "  [SKIP] T4 — python3 unavailable"
else
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  PROG="$TMP/intake-progress.json"
  python3 -c "
import json
data = {
  'version': 1, 'started_at': '2026-01-01T00:00:00Z',
  'last_section': 0, 'completed_sections': [],
  'project_name': 'TestProject', 'platform': 'web', 'track': 'standard',
  'deployment': 'personal', 'language': 'typescript',
  'description': 'A test', 'poc_mode': None,
  'answers': {'preexisting': 'kept'}
}
with open('$PROG', 'w') as f:
    json.dump(data, f)
"

  # Source the wizard's helper functions only (avoid running main).
  # We extract prompt_input, save_answer, _request_pause,
  # check_pause_requested into a runnable script with overridden
  # PROGRESS_FILE and stubbed print_* helpers.
  TEST_SCRIPT="$TMP/test.sh"
  cat > "$TEST_SCRIPT" << EOF
#!/usr/bin/env bash
set -uo pipefail
PROGRESS_FILE="$PROG"
_PAUSE_FILE="$TMP/.pause-sentinel"
BOLD=''; NC=''; CYAN=''; GREEN=''; BLUE=''; YELLOW=''; RED=''
print_info() { :; }
print_ok()   { :; }
print_warn() { :; }
print_fail() { :; }
print_step() { :; }
log_line()   { :; }

EOF
  # Extract the wizard functions we need. Use awk to grab each
  # function block by name (BSD-awk compatible).
  for fn in prompt_input prompt_choice prompt_with_suggestions _request_pause check_pause_requested save_answer; do
    awk -v fn="$fn" '
      $0 ~ ("^" fn "\\(\\) \\{") { inside=1 }
      inside { print; if ($0 == "}") { inside=0; print ""; exit } }
    ' "$WIZARD" >> "$TEST_SCRIPT"
  done

  cat >> "$TEST_SCRIPT" << 'EOF'

# Simulate run_section_2 sequence: ask for two real answers, then "pause",
# then attempt three more prompts/saves. After fix, "pause" must cause
# every subsequent save_answer to be a no-op (sentinel guards it).
answer1=$(prompt_input "Q1" "")
save_answer "q1" "$answer1"

answer2=$(prompt_input "Q2" "")
save_answer "q2" "$answer2"

answer3=$(prompt_input "Q3" "")
save_answer "q3" "$answer3"

# These should also not write — sentinel is set after Q3's "pause".
answer4=$(prompt_input "Q4" "")
save_answer "q4" "$answer4"

answer5=$(prompt_input "Q5" "")
save_answer "q5" "$answer5"

# Verify what got written.
python3 -c "
import json, sys
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
ans = data.get('answers', {})
# Pre-existing key must be preserved.
assert ans.get('preexisting') == 'kept', f'preexisting was clobbered: {ans}'
# q1 + q2 are real, q3 was 'pause' and q4/q5 came after pause.
# After fix: q3, q4, q5 keys must NOT exist (or must be empty/unchanged).
assert ans.get('q1') == 'first',  f'q1 mismatch: {ans.get(\"q1\")}'
assert ans.get('q2') == 'second', f'q2 mismatch: {ans.get(\"q2\")}'
assert 'q3' not in ans, f'q3 was written after pause: {ans.get(\"q3\")!r}'
assert 'q4' not in ans, f'q4 was written after pause: {ans.get(\"q4\")!r}'
assert 'q5' not in ans, f'q5 was written after pause: {ans.get(\"q5\")!r}'
print('PAUSE_OK')
"
EOF
  chmod +x "$TEST_SCRIPT"

  # Feed answers: first, second, pause, then anything (should not be read).
  out=$(printf 'first\nsecond\npause\nignored1\nignored2\n' | bash "$TEST_SCRIPT" 2>&1) || true
  if echo "$out" | grep -q "PAUSE_OK"; then
    pass "T4: pause prevents save_answer writes for q3/q4/q5"
  else
    fail_ "T4" "pause should short-circuit save_answer: $out"
  fi

  rm -rf "$TMP"
  trap - EXIT
fi

# ----------------------------------------------------------------
# T5 (code-intake-wizard-6): Competency Matrix saves a tooling
# answer for each domain — competency_${key}_tooling.
# ----------------------------------------------------------------
echo ""
echo "T5: Competency Matrix captures 'Automated Tooling Required?' column"

# Static-source check: run_section_6 must save competency_${key}_tooling
# (one per domain). We verify the source has the save call.
if ! grep -qE 'save_answer "competency_\$\{?key\}?_tooling"' "$WIZARD"; then
  fail_ "T5" "run_section_6 does not save 'competency_\${key}_tooling' for any domain"
else
  pass "T5a: run_section_6 saves competency_\${key}_tooling"
fi

# Domains list must be unchanged length (9).
domains_count=$(awk '
  /local domains=\(/ {
    line=$0
    sub(/.*domains=\(/, "", line)
    sub(/\).*/, "", line)
    # Count quoted strings.
    n=gsub(/"[^"]*"/, "&", line)
    print n; exit
  }
' "$WIZARD")
if [ "${domains_count:-0}" -ne 9 ]; then
  fail_ "T5" "expected 9 competency domains, found ${domains_count:-0}"
else
  pass "T5b: 9 competency domains still defined"
fi

# Functional test: drive run_section_6's matrix loop with scripted
# answers and assert the JSON has competency_security_tooling populated
# when Security == "No".
if ! command -v python3 >/dev/null 2>&1; then
  echo "  [SKIP] T5c — python3 unavailable"
else
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  PROG="$TMP/intake-progress.json"
  python3 -c "
import json
data = {
  'version': 1, 'started_at': '2026-01-01T00:00:00Z',
  'last_section': 0, 'completed_sections': [],
  'project_name': 'TestProject', 'platform': 'web', 'track': 'standard',
  'deployment': 'personal', 'language': 'typescript',
  'description': 'A test', 'poc_mode': None, 'answers': {}
}
with open('$PROG', 'w') as f:
    json.dump(data, f)
"

  TEST_SCRIPT="$TMP/test.sh"
  cat > "$TEST_SCRIPT" << EOF
#!/usr/bin/env bash
set -uo pipefail
PROGRESS_FILE="$PROG"
_PAUSE_FILE="$TMP/.pause-sentinel"
BOLD=''; NC=''; CYAN=''; GREEN=''; BLUE=''; YELLOW=''; RED=''
print_info() { :; }
print_ok()   { :; }
print_warn() { :; }
print_fail() { :; }
print_step() { :; }
log_line()   { :; }

EOF
  for fn in prompt_input prompt_choice prompt_with_suggestions _request_pause check_pause_requested save_answer show_suggestions parse_suggestions; do
    awk -v fn="$fn" '
      $0 ~ ("^" fn "\\(\\) \\{") { inside=1 }
      inside { print; if ($0 == "}") { inside=0; print ""; exit } }
    ' "$WIZARD" >> "$TEST_SCRIPT"
  done

  # Emit only the matrix loop from run_section_6, wrapped in a
  # function so `local` keywords inside the loop stay valid.
  echo 'run_matrix() {' >> "$TEST_SCRIPT"
  awk '
    /local domains=\("Product\/UX Logic"/ { capture=1 }
    capture { print }
    capture && /^  done$/ { exit }
  ' "$WIZARD" >> "$TEST_SCRIPT"
  echo '}' >> "$TEST_SCRIPT"
  echo 'run_matrix' >> "$TEST_SCRIPT"

  cat >> "$TEST_SCRIPT" << 'EOF'

python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
ans = data.get('answers', {})
# Assert: every domain has a corresponding _tooling key.
domains = ['product_ux_logic', 'frontend_code', 'backend_api_design',
           'database_design', 'security', 'devops_infrastructure',
           'accessibility', 'performance', 'mobile']
missing = [d for d in domains if f'competency_{d}_tooling' not in ans]
assert not missing, f'missing tooling keys for: {missing}'
# Security was 'No' — tooling answer must be non-empty (the default or
# user-supplied value).
sec_tool = ans.get('competency_security_tooling', '')
assert sec_tool and sec_tool != 'N/A', \
  f'competency_security_tooling must be non-empty for a \"No\" answer, got {sec_tool!r}'
print('MATRIX_OK')
"
EOF
  chmod +x "$TEST_SCRIPT"

  # Feed: 9 prompt_choice answers (1=Yes, 2=Partially, 3=No), and for
  # any Partially/No, accept the default tooling by pressing Enter.
  # Order: Product/UX=1, Frontend=1, Backend=1, Database=1, Security=3,
  # DevOps=2, Accessibility=3, Performance=2, Mobile=1.
  # Defaults accepted for the 4 non-Yes answers (Security, DevOps,
  # Accessibility, Performance).
  out=$(printf '1\n1\n1\n1\n3\n\n2\n\n3\n\n2\n\n1\n' | bash "$TEST_SCRIPT" 2>&1) || true
  if echo "$out" | grep -q "MATRIX_OK"; then
    pass "T5c: Competency Matrix saves _tooling answer for each domain (Security has framework default)"
  else
    fail_ "T5c" "Competency Matrix tooling capture missing: $out"
  fi

  rm -rf "$TMP"
  trap - EXIT
fi

# ----------------------------------------------------------------
# T-CLI-DRIFT (specs-plans-init-intake-noninteractive-3):
# the intake-wizard plan + spec must not reference a never-shipped
# `cli.json` / `cli` platform; the actually-shipped suggestion file
# is `mcp_server.json` (matches the 2026-04-25 non-interactive spec).
# ----------------------------------------------------------------
echo ""
echo "T-CLI-DRIFT: plan/spec/wizard reference mcp_server (not cli)"

PLAN_MD="$REPO_ROOT/docs/superpowers/plans/2026-04-02-intake-wizard.md"
SPEC_MD="$REPO_ROOT/docs/superpowers/specs/2026-04-02-intake-wizard-design.md"

drift=0
# 1. The shipped suggestion-file set must NOT include cli.json.
if [ -f "$REPO_ROOT/templates/intake-suggestions/cli.json" ]; then
  fail_ "T-CLI-DRIFT-1" "templates/intake-suggestions/cli.json exists (should not — newer spec uses mcp_server.json)"
  drift=1
fi
# 2. The shipped suggestion-file set MUST include mcp_server.json.
if [ ! -f "$REPO_ROOT/templates/intake-suggestions/mcp_server.json" ]; then
  fail_ "T-CLI-DRIFT-2" "templates/intake-suggestions/mcp_server.json missing"
  drift=1
fi
# 3. Plan must not reference cli.json or the bare `cli` platform value
#    in a directive context. The plan IS allowed to mention `cli.json` in a
#    block-quoted "drift note" (lines starting with `> `) that explains the
#    rename — those lines are documentation, not directives.
plan_hits=$(grep -nE 'cli\.json|"cli"' "$PLAN_MD" | grep -vE '^[0-9]+:>' | grep -vE 'supersedes the earlier `cli\.json`' || true)
if [ -n "$plan_hits" ]; then
  fail_ "T-CLI-DRIFT-3" "plan still references cli.json or 'cli' platform outside drift-note context: $(echo "$plan_hits" | head -3)"
  drift=1
fi
# 4. Spec must not reference cli.json or the bare `cli` platform value.
if grep -nE 'cli\.json|"cli"' "$SPEC_MD" >/dev/null 2>&1; then
  fail_ "T-CLI-DRIFT-4" "spec still references cli.json or 'cli' platform: $(grep -nE 'cli\.json|"cli"' "$SPEC_MD" | head -3)"
  drift=1
fi
# 5. Wizard prompt + case branch must use mcp_server (not cli).
if grep -nE 'prompt_choice "Platform:".*"cli"' "$WIZARD" >/dev/null 2>&1; then
  fail_ "T-CLI-DRIFT-5" "wizard prompt_choice still lists 'cli' as a platform"
  drift=1
fi
# Require the wizard to handle the `mcp_server` platform branch explicitly.
if ! grep -nE '^[[:space:]]+mcp_server\)' "$WIZARD" >/dev/null 2>&1; then
  fail_ "T-CLI-DRIFT-6" "wizard case statement missing a 'mcp_server)' branch"
  drift=1
fi
if [ "$drift" -eq 0 ]; then
  pass "T-CLI-DRIFT: plan, spec, wizard, and templates all aligned on mcp_server"
fi

# ----------------------------------------------------------------
# T-SUGGEST-LANGUAGES (specs-plans-init-intake-noninteractive-5):
# each platform suggestion JSON must expose a top-level `languages`
# array enumerating allowed languages — used by init.sh Pass-2 and
# any other consumer that needs the per-platform language set.
# ----------------------------------------------------------------
echo ""
echo "T-SUGGEST-LANGUAGES: each platform suggestion JSON has a top-level languages[]"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] T-SUGGEST-LANGUAGES — jq unavailable"
else
  langs_drift=0
  for plat in web desktop mobile mcp_server; do
    f="$REPO_ROOT/templates/intake-suggestions/${plat}.json"
    if [ ! -f "$f" ]; then
      fail_ "T-SUGGEST-LANGUAGES-${plat}" "missing $f"
      langs_drift=1
      continue
    fi
    arr_type=$(jq -r '.languages | type' "$f" 2>/dev/null || echo "null")
    if [ "$arr_type" != "array" ]; then
      fail_ "T-SUGGEST-LANGUAGES-${plat}" "$plat.json missing top-level 'languages' array (got type=$arr_type)"
      langs_drift=1
      continue
    fi
    arr_len=$(jq -r '.languages | length' "$f")
    if [ "$arr_len" -lt 1 ]; then
      fail_ "T-SUGGEST-LANGUAGES-${plat}" "$plat.json languages[] is empty"
      langs_drift=1
    fi
  done
  if [ "$langs_drift" -eq 0 ]; then
    pass "T-SUGGEST-LANGUAGES: web, desktop, mobile, mcp_server all expose top-level languages[]"
  fi
fi

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
echo ""
echo "==============================="
echo "Passed: $PASSED   Failed: $FAILED"
echo "==============================="
[ "$FAILED" -eq 0 ]

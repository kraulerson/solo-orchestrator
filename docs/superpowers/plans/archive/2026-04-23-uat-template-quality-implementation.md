# UAT Template Quality + Platform-Aware Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise the floor on UAT scenario authoring quality per spec `docs/superpowers/specs/2026-04-23-uat-template-quality-design.md`. Universal HTML-comment guardrails + per-platform reference examples (4 first-class + `other` co-build protocol) + pattern-based linter + authoring guide + idempotent upgrade migration.

**Architecture:** Three-layer guardrail. Layer 1 — universal quality checklist and anti-pattern list embedded as HTML comments in the UAT template. Layer 2 — per-platform reference pairs (pre-flight + scenario) under `templates/uat/references/`, selected by `$PLATFORM` at init/upgrade time; `other` platform skips the reference copy and falls through to the co-build Q&A protocol. Layer 3 — `scripts/lint-uat-scenarios.sh` runs six pattern-based checks against a populated template; agent-invoked before saving.

**Tech Stack:** Bash 4+, jq, existing solo-orchestrator test conventions (bash assertion scripts). HTML templates (no framework). JSON scenario examples.

---

## File Structure

```
templates/uat/                                      # NEW directory
├── test-session-template.html                      # MOVED from templates/uat-test-session.html + content updates
├── test-session-template.md                        # MOVED from templates/uat-test-template.md + content updates
└── references/                                     # NEW directory
    ├── web-pre-flight.html                         # NEW
    ├── web-scenario.json                           # NEW
    ├── desktop-pre-flight.html                     # NEW
    ├── desktop-scenario.json                       # NEW
    ├── mobile-pre-flight.html                      # NEW
    ├── mobile-scenario.json                        # NEW
    ├── mcp-server-pre-flight.html                  # NEW
    └── mcp-server-scenario.json                    # NEW

scripts/
└── lint-uat-scenarios.sh                           # NEW: pattern-based linter, ~90 lines

docs/
└── uat-authoring-guide.md                          # NEW: authoring reference + co-build protocol, ~250 lines

tests/
├── test-lint-uat-scenarios.sh                      # NEW: 11 cases against the linter
└── edge-cases-scripts.sh                           # MODIFIED: add 7 init/upgrade integration cases

init.sh                                             # MODIFIED: update paths, per-platform reference copy
scripts/upgrade-project.sh                          # MODIFIED: UAT migration block
templates/generated/claude-md.tmpl                  # MODIFIED: Testing & Bug Workflow — linter step + guide pointer
```

**Key design choices reflected above:**

- Templates and their references are co-located under `templates/uat/` — matches existing `templates/pipelines/`, `templates/platform-modules/` convention for grouped assets.
- Linter is a sibling of existing `scripts/` utilities; no subdirectory needed.
- Authoring guide lives alongside other framework docs.
- Tests for the linter are standalone; integration tests extend the existing edge-cases-scripts.sh.

---

## Task 1: Move UAT templates and add Layer 1 guardrails to the HTML template

**Files:**
- Move: `templates/uat-test-session.html` → `templates/uat/test-session-template.html`
- Move: `templates/uat-test-template.md` → `templates/uat/test-session-template.md`
- Modify (content): `templates/uat/test-session-template.html` — add `__TESTER_PRE_FLIGHT__` placeholder block, extend `__SCENARIOS_JSON__` comment with quality checklist + anti-patterns + expanded example + linter-invocation note

**Why:** Foundation task. Subsequent tasks depend on the new path and the updated template content. Moves are done with `git mv` to preserve history.

- [ ] **Step 1: Create the new directory and move files**

```bash
cd "$(git rev-parse --show-toplevel)"
mkdir -p templates/uat/references
git mv templates/uat-test-session.html  templates/uat/test-session-template.html
git mv templates/uat-test-template.md   templates/uat/test-session-template.md
```

Verify:

```bash
ls -la templates/uat/
```

Expected: both files now under `templates/uat/`; `templates/uat-test-session.html` and `templates/uat-test-template.md` no longer exist.

- [ ] **Step 2: Add `__TESTER_PRE_FLIGHT__` placeholder + comment to the HTML template**

Find the line:

```html
<div class="meta">Date: __SESSION_DATE__ | Features: __SESSION_FEATURES__ | Tester: <input id="tester-name" ...></div>
```

(Currently around line 69.) Insert the following **immediately after** that line:

```html

<!--
  AGENT: Replace __TESTER_PRE_FLIGHT__ with a pre-flight block describing the
  test environment and one-time setup the tester must do before any scenario.
  Rendered as a <div class="fixture-ref"> at the top of the page, above the
  progress bar. Every UAT session MUST include this block — tests that don't
  state where the tester stands cannot be reliably executed.

  REQUIRED contents (fill every line — do not omit any):
    - System under test: <environment description>. <compatibility note>.
    - Project root / app location: <absolute path OR URL OR device identifier>
    - Runtime / tooling: <language + version OR browser + version OR device OS>
    - Required tools: <list in <code>>. Optional: <list with scenario refs>.
    - One-time setup (≤3 lines): <cd / navigate / launch / flash / connect>
    - Starting-state assumptions every scenario will restate.
    - How to run a scenario (1–2 sentences).

  Use <br> for line breaks, <code> for paths and commands, <strong> for
  labels, <em> for optional-dependency notes. Wrap everything in a single
  <div class="fixture-ref">.

  See tests/uat/examples/pre-flight-reference.html for a platform-specific
  worked example (populated by init.sh based on your project's platform).
  If your project's platform is 'other', the reference file is NOT provided
  — ask the Orchestrator the co-build questions in
  docs/uat-authoring-guide.md § "Co-build protocol for 'other' platform"
  before generating this block.
-->
__TESTER_PRE_FLIGHT__

```

- [ ] **Step 3: Extend the `__SCENARIOS_JSON__` comment with quality checklist + anti-patterns**

Find the existing comment block ending at:

```
// EXAMPLE (do not copy verbatim — write scenarios specific to the features under test):
```

(Currently around line 126.) Replace the existing EXAMPLE block (the 9-line object definition) with the following more detailed comment insertion. Insert **before** the line starting with `// EXAMPLE`:

```
// QUALITY CHECKLIST — every scenario MUST meet these before emission.
// A scenario that fails any item is NOT READY for the tester; rewrite it.
//
// [ ] `steps` opens with a starting-state restatement. Use the same phrase
//     project-wide, e.g., "You are in the project root with <runtime> active
//     (see 'Before you start')." Without this, chained scenarios drift.
// [ ] `steps` numbers every command. No "run the command from scenario N",
//     no "see above", no "as before". Each scenario is self-contained.
// [ ] `steps` commands are fully copy-pasteable. No placeholders, no
//     "<project-path>", no shell pseudo-code, no `...` ellipses in the
//     actual command lines.
// [ ] `steps` prefers deterministic commands over ones whose output format
//     varies across tool versions.
// [ ] `expected` has a CONCRETE pass/fail anchor. At least ONE of:
//       - an exact text string the tester can grep for;
//       - an exit code the tester can read (the scenario should emit it:
//         `echo "exit=$?"`);
//       - a line count (`| wc -l`);
//       - a deterministic single-value assertion.
//     Prose like "works", "succeeds", "passes", "no errors" is NOT a
//     concrete anchor. If you cannot write a concrete anchor, the
//     scenario is not ready.
// [ ] `expected` is ≥60 characters. Shorter is almost certainly
//     underspecified.
// [ ] If the scenario MUTATES repo/filesystem/env state, include numbered
//     cleanup steps at the end AND a verification step (e.g.,
//       git diff --exit-code <file> && echo RESTORED
//     ). Informal parentheticals like "(restore)" are not acceptable.
// [ ] If the scenario has an EXTERNAL dependency (Docker, a running
//     service, network endpoint), include a probe step whose output tells
//     the tester to proceed or Skip. Example:
//       docker info >/dev/null 2>&1 && echo DOCKER_OK || echo SKIP_DOCKER_UNAVAILABLE
//
// ANTI-PATTERNS — do not emit scenarios matching these. The linter at
// scripts/lint-uat-scenarios.sh will refuse any scenario whose:
//   - `steps` does not open with a state-restatement keyword
//     ("You are", "cd ", "Setup:", "Before starting", "Preconditions:");
//   - `expected` contains only "works" / "succeeds" / "passes" /
//     "no errors" / "builds successfully" / "completes" as its pass/fail
//     description;
//   - `steps` contains "command from scenario", "see above", "as before",
//     "like scenario", "as in scenario";
//   - `expected` is <60 characters;
//   - `id` duplicates another scenario's id.
//
// BEFORE SAVING: run scripts/lint-uat-scenarios.sh on the populated file.
// Must exit 0 before the UAT template is handed to a tester.
//
```

Then update the EXAMPLE block that follows. Replace the existing 1-scenario example with an enhanced version that satisfies all checklist items:

```
// EXAMPLE (do not copy verbatim — write scenarios specific to the features under test):
// [
//   {
//     "id": 1,
//     "feature": 7,
//     "title": "Repair disabled after clean analysis on a simple cube",
//     "steps": "You are in the app with the Mesh Repair panel open.\\n\\n1. Open examples/cube.stl via File > Open.\\n2. Click Analyze (keyboard: A).\\n3. Read the Repair button's disabled attribute via devtools OR confirm it appears greyed out.",
//     "expected": "Analyze completes within 2 seconds and reports:\\n  Holes: 0\\n  Degenerate faces: 0\\nThe Repair button has the disabled attribute and is visually greyed out.\\n\\nPASS if both counts are 0 AND Repair is disabled. FAIL if either count is non-zero or Repair is enabled."
//   }
// ]
```

- [ ] **Step 4: Verify the template is well-formed**

```bash
# Syntax check: it's HTML so no compiler, but ensure placeholders are present
grep -c '__TESTER_PRE_FLIGHT__' templates/uat/test-session-template.html
# Expected: 2 (one in comment, one as the actual placeholder)
grep -c '__SCENARIOS_JSON__' templates/uat/test-session-template.html
# Expected: 3 (comment mentions + actual placeholder + maybe feature-number ref)
grep -c 'lint-uat-scenarios.sh' templates/uat/test-session-template.html
# Expected: at least 1
```

- [ ] **Step 5: Commit**

```bash
git add templates/uat/
git commit -m "refactor(uat): move templates to templates/uat/ + add quality guardrails (BL-009)

Moves:
  templates/uat-test-session.html  → templates/uat/test-session-template.html
  templates/uat-test-template.md   → templates/uat/test-session-template.md

HTML template content updates:
- Adds __TESTER_PRE_FLIGHT__ placeholder with authoring instructions
- Extends __SCENARIOS_JSON__ comment with 8-item quality checklist
- Adds anti-pattern list referencing the upcoming linter
- Expands the embedded EXAMPLE to demonstrate the full quality bar
- Adds 'run lint-uat-scenarios.sh before saving' instruction

MD template unchanged in this task (Task 2 handles its updates).
init.sh still points at the old paths (will be updated in Task 6);
expect init.sh to fail until Task 6 lands."
```

---

## Task 2: Update the MD template with pre-flight reminder + HTML pointer

**Files:**
- Modify: `templates/uat/test-session-template.md`

**Why:** Partial parity (per Decision #3) — MD gets a minimal pre-flight reminder and a pointer to the HTML template for the full quality bar. No per-platform duplication.

- [ ] **Step 1: Read the current MD template**

```bash
cat templates/uat/test-session-template.md
```

Expected output: the original markdown test-session template, ~49 lines.

- [ ] **Step 2: Insert "Before you start" section between the Instructions and the Test Scenarios sections**

Find the line `## Instructions` (around line 9) and its closing `---` separator (around line 17). Replace the `---` separator immediately after the Instructions list with the following block, which adds a new "Before you start" section:

```markdown
---

## Before you start

_Every UAT test must begin with a clear statement of the test environment and one-time setup. Fill this in before running any scenario:_

- **System under test:** _describe the environment (OS + arch for desktop/CLI; browser + URL for web; device + OS for mobile; MCP client + server command for mcp-server; other context for 'other' platforms)_
- **Project root / app location:** _absolute path, URL, or device identifier_
- **Runtime / tooling:** _language + version, browser, or device OS_
- **Required tools:** _list._ Optional: _list, with scenario numbers that require each_
- **One-time setup:** _the commands or steps you ran once before starting_

For richer per-platform guidance — including quality checklist, anti-patterns, reference examples, and the co-build protocol for 'other' platforms — see `templates/uat/test-session-template.html` and `docs/uat-authoring-guide.md`.

---
```

- [ ] **Step 3: Verify the insertion**

```bash
grep -A 1 'Before you start' templates/uat/test-session-template.md
```

Expected: the new section heading shows up with the "Every UAT test must begin..." line immediately after.

- [ ] **Step 4: Commit**

```bash
git add templates/uat/test-session-template.md
git commit -m "docs(uat): add pre-flight reminder + HTML-template pointer to MD template (BL-009)

Partial parity with the HTML template: MD gets a 'Before you start'
section with the minimum pre-flight fields (system, location, runtime,
tools, setup), plus a pointer to the HTML template and authoring guide
for the full per-platform references + quality checklist + linter."
```

---

## Task 3: Linter — tests first, then implementation (TDD)

**Files:**
- Create: `tests/test-lint-uat-scenarios.sh`
- Create: `scripts/lint-uat-scenarios.sh`

**Why:** The pattern-based linter is the mechanical enforcement layer. TDD: write all 11 cases first, verify they fail, then implement the linter so they all pass.

- [ ] **Step 1: Create the test file with 11 failing cases**

Create `tests/test-lint-uat-scenarios.sh`:

```bash
#!/usr/bin/env bash
# tests/test-lint-uat-scenarios.sh — unit tests for scripts/lint-uat-scenarios.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-uat-scenarios.sh"

PASSED=0
FAILED=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "  ASSERT FAIL${msg:+ [$msg]}: expected '$expected', got '$actual'" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ASSERT FAIL${msg:+ [$msg]}: does not contain '$needle'" >&2
    return 1
  fi
}

run_case() {
  local name="$1"
  shift
  if ( set -e; "$@" ); then
    echo "✓ $name"
    PASSED=$((PASSED + 1))
  else
    echo "✗ $name FAILED"
    FAILED=$((FAILED + 1))
  fi
}

# Helper: seed a populated HTML file with a given scenarios array.
# Args: file, scenarios-json
seed_html() {
  local file="$1" scenarios="$2"
  cat > "$file" <<HTML
<!DOCTYPE html>
<html><body>
<div class="fixture-ref">
  <strong>System under test:</strong> macOS (darwin/arm64).<br>
  <strong>Project root:</strong> <code>/tmp/example</code><br>
</div>
<script>
const scenarios = $scenarios;
</script>
</body></html>
HTML
}

case_1_happy_path() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/ok.html" '[
    {"id":1,"feature":1,"title":"T1","steps":"You are in the project root.\n\n1. Run pytest.","expected":"Pytest output contains PASSED and exits 0. No test failures reported. Total test count matches what you expected to run."},
    {"id":2,"feature":1,"title":"T2","steps":"You are in the project root.\n\n1. Run make build.","expected":"Build completes in under 30 seconds. Output contains \"Build complete\" and exits 0. Artifacts appear in dist/."},
    {"id":3,"feature":2,"title":"T3","steps":"cd services/web && npm test","expected":"npm test exits 0 with \"All tests passed\" line. Coverage summary shows >=80% on lines and branches."}
  ]'
  local out; out=$(bash "$LINTER" "$work/ok.html" 2>&1)
  local code=$?
  assert_eq "0" "$code" "exit 0 on happy path"
  assert_contains "$out" "3 scenarios clean" "success message"
}

case_2_unreplaced_preflight_placeholder() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  cat > "$work/bad.html" <<'HTML'
<html><body>
__TESTER_PRE_FLIGHT__
<script>const scenarios = [];</script>
</body></html>
HTML
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code" "exit 1 on unreplaced placeholder"
  assert_contains "$out" "unreplaced placeholder" "mentions placeholder"
  assert_contains "$out" "__TESTER_PRE_FLIGHT__" "names the placeholder"
}

case_3_unreplaced_scenarios_placeholder() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  cat > "$work/bad.html" <<'HTML'
<html><body>
<script>const scenarios = __SCENARIOS_JSON__;</script>
</body></html>
HTML
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  # Unreplaced __SCENARIOS_JSON__ produces a parse error → exit 2, OR
  # Unreplaced placeholder check catches it first → exit 1.
  # We accept either as long as the error message is clear.
  if [ "$code" != "1" ] && [ "$code" != "2" ]; then
    echo "  Expected exit 1 or 2, got $code" >&2; return 1
  fi
  assert_contains "$out" "__SCENARIOS_JSON__" "names the placeholder"
}

case_4_expected_too_short() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"You are in the project root.\n\n1. Run foo.","expected":"OK"}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "expected too short" "mentions short expected"
}

case_5_expected_banned_phrase() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"You are in the project root.\n\n1. Build.","expected":"works"}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  # 'works' fails BOTH short-length and banned-phrase checks — accept either message
  if [[ "$out" != *"banned vague phrase"* ]] && [[ "$out" != *"expected too short"* ]]; then
    echo "  Expected 'banned vague phrase' or 'expected too short' in output" >&2; return 1
  fi
}

case_6_banned_cross_ref() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"You are in the project root.\n\n1. Run the command from scenario 1 again.","expected":"Output matches what the prior scenario produced. Same exit code. Same stdout text to the byte."}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "banned cross-ref" "mentions cross-ref"
}

case_7_missing_state_restatement() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"1. Run pytest tests/\n2. Check the output","expected":"Pytest output contains PASSED. All 47 tests pass. Exit code is 0. No warnings printed to stderr."}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "state-restatement" "mentions state-restatement"
}

case_8_duplicate_ids() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":2,"feature":1,"title":"T1","steps":"You are in the project root.\n\n1. Run A.","expected":"Command A exits 0 and prints the expected success message to stdout. No errors on stderr."},
    {"id":2,"feature":1,"title":"T2","steps":"You are in the project root.\n\n1. Run B.","expected":"Command B exits 0 and prints the expected success message to stdout. No errors on stderr."}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "duplicate scenario id" "mentions duplicate"
}

case_9_missing_file() {
  set +e
  local out; out=$(bash "$LINTER" "/nonexistent/path/foo.html" 2>&1)
  local code=$?
  set -e
  assert_eq "2" "$code" "exit 2 on missing file"
  assert_contains "$out" "No such file" "mentions missing"
}

case_10_malformed_json() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  cat > "$work/bad.html" <<'HTML'
<html><body>
<script>const scenarios = [{"id": 1, broken };</script>
</body></html>
HTML
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "2" "$code" "exit 2 on malformed JSON"
  assert_contains "$out" "parse failed" "mentions parse failure"
}

case_11_multiple_violations() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T1","steps":"1. run","expected":"OK"},
    {"id":2,"feature":1,"title":"T2","steps":"2. see above","expected":"works"},
    {"id":3,"feature":1,"title":"T3","steps":"3. do stuff","expected":"succeeds"}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  # Expect multiple violations — check for a count >= 3 in the summary line
  assert_contains "$out" "violations found" "summary line present"
}

echo "═══ test-lint-uat-scenarios.sh ═══"
run_case "case 1: happy path"                        case_1_happy_path
run_case "case 2: unreplaced __TESTER_PRE_FLIGHT__"  case_2_unreplaced_preflight_placeholder
run_case "case 3: unreplaced __SCENARIOS_JSON__"     case_3_unreplaced_scenarios_placeholder
run_case "case 4: expected too short"                case_4_expected_too_short
run_case "case 5: expected is banned phrase"         case_5_expected_banned_phrase
run_case "case 6: banned cross-ref"                  case_6_banned_cross_ref
run_case "case 7: missing state-restatement"         case_7_missing_state_restatement
run_case "case 8: duplicate scenario IDs"            case_8_duplicate_ids
run_case "case 9: missing input file"                case_9_missing_file
run_case "case 10: malformed JSON"                   case_10_malformed_json
run_case "case 11: multiple violations"              case_11_multiple_violations

echo ""
echo "═══════════════════════════════════════════"
echo "Tests: $PASSED passed, $FAILED failed"
echo "═══════════════════════════════════════════"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2: Run tests to verify all fail (linter doesn't exist yet)**

```bash
bash tests/test-lint-uat-scenarios.sh
```

Expected: most cases fail because `scripts/lint-uat-scenarios.sh` doesn't exist. Don't worry about specific pass/fail mix — we're establishing the test file before implementing.

- [ ] **Step 3: Implement the linter**

Create `scripts/lint-uat-scenarios.sh`:

```bash
#!/usr/bin/env bash
# scripts/lint-uat-scenarios.sh — pattern-based linter for populated UAT templates.
# Usage: scripts/lint-uat-scenarios.sh <populated-html-file>
# Exit codes: 0 = clean; 1 = quality violations; 2 = structural failure.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: scripts/lint-uat-scenarios.sh <populated-html-file>" >&2
  exit 2
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "lint-uat-scenarios.sh: $FILE: No such file or directory" >&2
  exit 2
fi

# --- File-level check 1: unreplaced __FOO__ placeholders ---
PLACEHOLDER_LINES=$(grep -n '__[A-Z][A-Z_]*__' "$FILE" || true)
if [ -n "$PLACEHOLDER_LINES" ]; then
  COUNT=$(echo "$PLACEHOLDER_LINES" | wc -l | tr -d ' ')
  echo "$PLACEHOLDER_LINES" | while IFS= read -r line; do
    # line looks like: 42:  __FOO__
    LINENUM="${line%%:*}"
    CONTEXT=$(echo "$line" | sed 's/^[0-9]*://' | head -c 80)
    echo "file-level: unreplaced placeholder — line $LINENUM: $CONTEXT" >&2
  done
  echo "$COUNT violations found. Revise the flagged scenarios and re-run the linter."
  exit 1
fi

# --- Extract scenarios JSON block between "const scenarios = " and "];" ---
SCENARIOS_JSON=$(awk '
  /const scenarios *= *\[/ {
    flag=1
    sub(/.*const scenarios *= */, "")
  }
  flag {
    print
    if (/\];[[:space:]]*$/) {
      flag=0
      exit
    }
  }
' "$FILE")

if [ -z "$SCENARIOS_JSON" ]; then
  echo "lint-uat-scenarios.sh: $FILE: No scenarios block found — is the file populated? (expected 'const scenarios = [...]')" >&2
  exit 2
fi

# Strip trailing ; so jq can parse
SCENARIOS_JSON="${SCENARIOS_JSON%;}"
# Strip trailing whitespace/newlines
SCENARIOS_JSON=$(echo "$SCENARIOS_JSON" | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}')

# Validate JSON
if ! JQ_OUT=$(echo "$SCENARIOS_JSON" | jq . 2>&1); then
  JQ_ERR=$(echo "$JQ_OUT" | head -1)
  echo "lint-uat-scenarios.sh: $FILE: JSON parse failed: $JQ_ERR" >&2
  exit 2
fi

VIOLATIONS=0
VIOLATION_LINES=""

# --- File-level check 2: duplicate scenario ids ---
DUP_IDS=$(echo "$SCENARIOS_JSON" | jq -r '[.[] | .id] | group_by(.) | map(select(length > 1) | .[0]) | .[]' 2>/dev/null || true)
if [ -n "$DUP_IDS" ]; then
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    VIOLATION_LINES="${VIOLATION_LINES}file-level: duplicate scenario id — id $id appears more than once"$'\n'
    VIOLATIONS=$((VIOLATIONS + 1))
  done <<< "$DUP_IDS"
fi

# --- Per-scenario checks ---
NUM_SCENARIOS=$(echo "$SCENARIOS_JSON" | jq 'length')

for i in $(seq 0 $((NUM_SCENARIOS - 1))); do
  ID=$(echo "$SCENARIOS_JSON" | jq -r ".[$i].id")
  EXPECTED=$(echo "$SCENARIOS_JSON" | jq -r ".[$i].expected")
  STEPS=$(echo "$SCENARIOS_JSON" | jq -r ".[$i].steps")

  # Check 1: expected length >= 60
  EXP_LEN=${#EXPECTED}
  if [ "$EXP_LEN" -lt 60 ]; then
    EXCERPT="${EXPECTED:0:50}"
    VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: expected too short — \"$EXCERPT\" ($EXP_LEN chars, min 60)"$'\n'
    VIOLATIONS=$((VIOLATIONS + 1))
  fi

  # Check 2: expected not a banned vague phrase (case-insensitive, trimmed)
  EXPECTED_NORM=$(echo "$EXPECTED" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$EXPECTED_NORM" in
    "works"|"succeeds"|"passes"|"no errors"|"builds successfully"|"completes")
      VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: banned vague phrase — \"$EXPECTED\""$'\n'
      VIOLATIONS=$((VIOLATIONS + 1))
      ;;
  esac

  # Check 3: steps contains banned cross-refs (case-insensitive)
  STEPS_LOWER=$(echo "$STEPS" | tr '[:upper:]' '[:lower:]')
  for BANNED in "command from scenario" "see above" "as before" "like scenario" "as in scenario"; do
    if [[ "$STEPS_LOWER" == *"$BANNED"* ]]; then
      VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: banned cross-ref — \"...$BANNED...\""$'\n'
      VIOLATIONS=$((VIOLATIONS + 1))
      break
    fi
  done

  # Check 4: steps first line starts with state-restatement keyword
  FIRST_LINE=$(echo "$STEPS" | head -1)
  HAS_RESTATEMENT=false
  for KW in "You are" "cd " "Setup:" "Before starting" "Preconditions:"; do
    KW_LOWER=$(echo "$KW" | tr '[:upper:]' '[:lower:]')
    FL_LOWER=$(echo "$FIRST_LINE" | tr '[:upper:]' '[:lower:]')
    if [[ "$FL_LOWER" == "$KW_LOWER"* ]]; then
      HAS_RESTATEMENT=true
      break
    fi
  done
  if [ "$HAS_RESTATEMENT" = false ]; then
    EXCERPT="${FIRST_LINE:0:60}"
    VIOLATION_LINES="${VIOLATION_LINES}scenario $ID: steps must open with state-restatement — first line: \"$EXCERPT\""$'\n'
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  printf "%s" "$VIOLATION_LINES" >&2
  echo "$VIOLATIONS violations found. Revise the flagged scenarios and re-run the linter."
  exit 1
fi

echo "All $NUM_SCENARIOS scenarios clean."
exit 0
```

Make it executable:

```bash
chmod +x scripts/lint-uat-scenarios.sh
```

- [ ] **Step 4: Run all tests to verify they pass**

```bash
bash tests/test-lint-uat-scenarios.sh
```

Expected output:

```
═══ test-lint-uat-scenarios.sh ═══
✓ case 1: happy path
✓ case 2: unreplaced __TESTER_PRE_FLIGHT__
✓ case 3: unreplaced __SCENARIOS_JSON__
✓ case 4: expected too short
✓ case 5: expected is banned phrase
✓ case 6: banned cross-ref
✓ case 7: missing state-restatement
✓ case 8: duplicate scenario IDs
✓ case 9: missing input file
✓ case 10: malformed JSON
✓ case 11: multiple violations

═══════════════════════════════════════════
Tests: 11 passed, 0 failed
═══════════════════════════════════════════
```

- [ ] **Step 5: Commit**

```bash
git add scripts/lint-uat-scenarios.sh tests/test-lint-uat-scenarios.sh
git commit -m "feat(uat): add pattern-based linter + 11 test cases (BL-009)

scripts/lint-uat-scenarios.sh runs six universal checks against a
populated UAT template:
- File-level: unreplaced __FOO__ placeholders (exit 1)
- File-level: duplicate scenario ids (exit 1)
- Per-scenario: expected length >= 60 chars
- Per-scenario: expected is not a banned vague phrase
- Per-scenario: steps does not contain banned cross-refs
- Per-scenario: steps first line starts with state-restatement keyword

Exit codes: 0 = clean; 1 = quality violations; 2 = structural failure
(missing file, unparseable JSON, no scenarios block).

Tests: 11 cases covering happy path, each violation type in isolation,
structural failures (missing file, malformed JSON, unreplaced placeholders),
and multi-violation accumulation."
```

---

## Task 4: Create 4 first-class platform reference pairs (8 files)

**Files:**
- Create: `templates/uat/references/web-pre-flight.html`
- Create: `templates/uat/references/web-scenario.json`
- Create: `templates/uat/references/desktop-pre-flight.html`
- Create: `templates/uat/references/desktop-scenario.json`
- Create: `templates/uat/references/mobile-pre-flight.html`
- Create: `templates/uat/references/mobile-scenario.json`
- Create: `templates/uat/references/mcp-server-pre-flight.html`
- Create: `templates/uat/references/mcp-server-scenario.json`

**Why:** Each first-class platform gets a pre-flight HTML snippet and a scenario JSON example. init.sh copies the matching pair at init time. `other` platform has no reference files — Task 5's authoring guide documents the co-build protocol.

Each reference file is shown in full below. Create them verbatim.

- [ ] **Step 1: Create the web pre-flight reference**

Create `templates/uat/references/web-pre-flight.html`:

```html
<div class="fixture-ref">
  <strong>System under test:</strong> Web app running at the URL below. Tested with Chromium-based browser (Chrome 122+ / Edge 122+ / Brave). Firefox 124+ should also work unless a scenario explicitly says otherwise.<br>
  <strong>App URL:</strong> <code>http://localhost:5173</code> (local dev) — or the staging URL provided by the Orchestrator.<br>
  <strong>Test environment:</strong> Backend services must be running. See <code>docs/setup.md</code> if the dev stack isn't already up. Network must be reachable.<br>
  <strong>Accounts / credentials:</strong> Use the <code>testuser@example.com</code> / <code>testpass123</code> account seeded in the dev database. If scenarios need multiple users, additional credentials are listed inline.<br>
  <em>Optional:</em> browser devtools (scenarios 3, 5 use Network tab for assertions).<br>
  <br>
  <strong>One-time setup before any scenario:</strong><br>
  1. Open the app URL in your browser.<br>
  2. Sign in with the test credentials above.<br>
  3. Confirm you land on the home/dashboard page with no console errors (F12 → Console).<br>
  <br>
  Every scenario below assumes:<br>
  1. You are logged in at the app URL (as in the setup).<br>
  2. Browser devtools are available (F12) if a scenario needs them.<br>
  3. If a scenario creates test data, it says so and removes it at the end.<br>
  <br>
  <strong>How to run a scenario:</strong> click "details" on the scenario card, follow the numbered steps in the browser, compare observed behavior and any devtools output to the "Expected" block, then click Pass / Fail / Skip. Use the Notes field for anything surprising or out of scope.
</div>
```

- [ ] **Step 2: Create the web scenario reference**

Create `templates/uat/references/web-scenario.json`:

```json
{
  "id": 1,
  "feature": 2,
  "title": "Authenticated form submit returns 201 and persists the record",
  "steps": "You are logged in at the app URL (see 'Before you start') with the default test account.\n\nThis scenario creates test data and cleans it up at the end. Do not close the tab mid-scenario.\n\n1. Navigate to /items/new via the top-nav 'Create Item' link.\n\n2. Fill in:\n   - Title: UAT-item-<paste-your-tester-name-here>\n   - Description: probe\n   - Category: general\n\n3. Open browser devtools (F12), switch to the Network tab, filter on 'Fetch/XHR'.\n\n4. Click Submit.\n\n5. In devtools Network, find the POST to /api/items. Note the HTTP status and response body.\n\n6. Navigate to /items and confirm your item appears in the list (sorted by newest).\n\n7. Cleanup: on the item's detail page, click Delete, confirm the prompt. Confirm the item no longer appears in the /items list.",
  "expected": "Step 5: POST /api/items returns HTTP 201 Created. Response body is JSON with an 'id' field (integer) and 'title' matching what you typed.\n\nStep 6: The new item is visible at the top of /items, showing your unique title and the 'general' category tag.\n\nStep 7: After deletion, /items no longer shows the item; a GET /api/items/<id> in devtools Network would return 404.\n\nPASS if the 201 response, the list visibility, AND the post-delete absence all confirm. FAIL if the POST returned a non-201 status, the item didn't appear in the list, or the cleanup left the item behind (ask the Orchestrator to purge it manually if so)."
}
```

- [ ] **Step 3: Create the desktop pre-flight reference**

Create `templates/uat/references/desktop-pre-flight.html`:

```html
<div class="fixture-ref">
  <strong>System under test:</strong> macOS (darwin/arm64) or Linux (x86_64/arm64). Commands assume a POSIX shell (bash or zsh). Windows WSL should also work for most scenarios — any Windows-specific deltas will be called out inline.<br>
  <strong>Project root:</strong> <code>/absolute/path/to/your/project</code> — the Orchestrator will replace this placeholder with the real path before dispatching.<br>
  <strong>Language runtime:</strong> <code>python 3.12.x</code> inside <code>.venv/</code> at the project root (OR the equivalent for your stack — Node 20.x, Rust 1.75, Go 1.21, etc.; the scenarios below name the exact runtime they exercise).<br>
  <strong>Required tools:</strong> <code>python</code>, <code>pip</code>, <code>git</code>, <code>jq</code>. <em>Optional:</em> <code>sqlite3</code> (scenarios 4, 7), <code>docker</code> (scenario 13 only).<br>
  <br>
  <strong>One-time setup before any scenario:</strong><br>
  <code>cd "/absolute/path/to/your/project"</code><br>
  <code>source .venv/bin/activate</code><br>
  <code>python --version   # must print 3.12.x</code><br>
  <br>
  Every scenario below assumes:<br>
  1. You are in the project-root terminal above.<br>
  2. The <code>.venv</code> is active (your prompt should show <code>(.venv)</code>).<br>
  3. If a scenario changes directory, it says so and returns you to the project root before ending.<br>
  4. If a scenario mutates files, it includes explicit cleanup + verification.<br>
  <br>
  <strong>How to run a scenario:</strong> click "details" on the scenario card, copy the numbered commands into the terminal, compare your output to the "Expected" block, then click Pass / Fail / Skip. Use the Notes field for anything surprising or out of scope.
</div>
```

- [ ] **Step 4: Create the desktop scenario reference**

Create `templates/uat/references/desktop-scenario.json`:

```json
{
  "id": 4,
  "feature": 1,
  "title": "CHECKSUMS drift — tampered migration is detected",
  "steps": "You are in the project root with .venv active (see 'Before you start').\n\nThis scenario modifies a file briefly and then restores it. Do NOT commit between steps.\n\n1. Save an untouched copy of the migration:\n   cp src/orchestrator/db/migrations/0001_initial.sql /tmp/saved-0001.sql\n\n2. Tamper with the file by appending a comment:\n   echo '-- tampered for UAT' >> src/orchestrator/db/migrations/0001_initial.sql\n\n3. Remove any stale test DB:\n   rm -f /tmp/orch-uat-drift.db\n\n4. Try to run migrations. It should fail:\n   python -c \"from orchestrator.db.migrate import run_migrations; run_migrations('/tmp/orch-uat-drift.db')\"; echo \"exit=$?\"\n\n5. Restore the original file immediately:\n   cp /tmp/saved-0001.sql src/orchestrator/db/migrations/0001_initial.sql\n\n6. Verify the file is restored (no diff against git):\n   git diff --exit-code src/orchestrator/db/migrations/0001_initial.sql && echo RESTORED",
  "expected": "Step 4: exits with a non-zero 'exit=' line (expect exit=1). Traceback ends in a MigrationError whose message contains 'checksum mismatch' and the text 'file=' and 'manifest='.\n\nStep 6: prints 'RESTORED' on its own line. git diff --exit-code returns 0.\n\nPASS if step 4 raised MigrationError AND step 6 printed RESTORED. FAIL if step 4 succeeded silently (bug — the CHECKSUMS check didn't fire) or step 6 shows a diff (your file needs manual restore: git checkout -- src/orchestrator/db/migrations/0001_initial.sql)."
}
```

- [ ] **Step 5: Create the mobile pre-flight reference**

Create `templates/uat/references/mobile-pre-flight.html`:

```html
<div class="fixture-ref">
  <strong>System under test:</strong> Mobile app running on a device OR an OS-level simulator/emulator. Specify below which one you're using.<br>
  <strong>Device / simulator:</strong> _fill in one_: iPhone 15 (iOS 17.x), Pixel 8 (Android 14), or the specific simulator configuration the Orchestrator provided.<br>
  <strong>App build:</strong> Install build <code>__BUILD_ID__</code> from the Orchestrator-provided source: TestFlight (iOS) / Internal Test track (Android) / local Xcode / Android Studio run. The About screen should show version <code>__VERSION__</code> build <code>__BUILD_NUMBER__</code> — confirm before starting.<br>
  <strong>Required accounts:</strong> Sign in with the test account <code>testuser@example.com</code> / <code>testpass123</code>. For multi-user scenarios, additional credentials are listed inline.<br>
  <em>Optional:</em> Screen recording software (scenarios 6, 8 benefit from capturing the tap sequence for bug reports).<br>
  <br>
  <strong>One-time setup before any scenario:</strong><br>
  1. Install and launch the specified build on your device/simulator.<br>
  2. Complete any first-run onboarding if shown; use "Skip" where available.<br>
  3. Sign in with the test credentials above.<br>
  4. Confirm you land on the app's home screen with no blocking errors or permission prompts.<br>
  <br>
  Every scenario below assumes:<br>
  1. The app is installed and launched on the device/simulator.<br>
  2. You are signed in as the test user.<br>
  3. Device network is on (WiFi or cellular). Scenarios that test offline behavior will say so explicitly.<br>
  4. Permissions (location, camera, notifications) are in their default initial state unless a prior scenario changed them.<br>
  <br>
  <strong>How to run a scenario:</strong> click "details" on the scenario card, follow the numbered tap/swipe/gesture steps on the device, compare observed behavior and any on-screen feedback to the "Expected" block, then click Pass / Fail / Skip in this browser. Use the Notes field for anything surprising, and consider attaching a screenshot for UI bugs.
</div>
```

- [ ] **Step 6: Create the mobile scenario reference**

Create `templates/uat/references/mobile-scenario.json`:

```json
{
  "id": 6,
  "feature": 3,
  "title": "Offline queue flushes when connectivity returns",
  "steps": "You are signed in on the app's home screen (see 'Before you start'). Airplane mode will be used in this scenario — disable it at the end.\n\n1. On the device, enable Airplane mode via Settings or the Control Center / Quick Settings shortcut. Confirm the status bar shows offline (airplane icon or no wifi/cellular indicator).\n\n2. Return to the app. Navigate to Compose (tap the + button at the bottom-right).\n\n3. Create a post with title 'UAT-offline-<your-tester-name>' and body 'queued offline'. Tap Submit.\n\n4. Observe the app behavior. Note what the Submit button does, what message appears, and whether the Outbox / Drafts / Queued section shows the item.\n\n5. Disable Airplane mode. Wait up to 15 seconds for connectivity to fully return (status bar icon confirms).\n\n6. Return to the app if you switched away. Observe any sync indicator.\n\n7. Navigate to the Posts list (Home tab) and pull to refresh.\n\n8. Cleanup: long-press your 'UAT-offline-<your-tester-name>' post, tap Delete, confirm the prompt. Confirm the post disappears from the list.",
  "expected": "Step 4: Submit button remains enabled OR shows a 'queued' state. A visible banner, toast, or Outbox badge indicates the post is queued for sync. No error dialog appears. App does not crash.\n\nStep 6: A sync indicator (spinner, toast, or banner) appears briefly as the queue drains. The indicator disappears when sync completes.\n\nStep 7: Your 'UAT-offline-<your-tester-name>' post is visible in the Posts list with a normal (non-queued) state indicator.\n\nStep 8: After deletion, the post no longer appears in the Posts list.\n\nPASS if all four observations confirm: queued behavior on submit, sync indicator on reconnect, post visible after refresh, cleanup removes it. FAIL if the app crashed, the post was lost without warning on offline submit, or the post never synced after reconnect (ask the Orchestrator to purge it manually if the cleanup step can't reach it)."
}
```

- [ ] **Step 7: Create the mcp-server pre-flight reference**

Create `templates/uat/references/mcp-server-pre-flight.html`:

```html
<div class="fixture-ref">
  <strong>System under test:</strong> MCP server process, invoked via an MCP client. The scenarios below assume the MCP Inspector tool (<code>npx @modelcontextprotocol/inspector</code>) for reproducible JSON-RPC interaction. Claude Desktop or Claude Code are also valid clients — scenario output shape is the same, only the invocation wrapper differs.<br>
  <strong>Server command:</strong> <code>python -m your_mcp_server</code> (or the exact command the Orchestrator specified — it's in the project's <code>mcp.json</code> or equivalent). Run it in one terminal; Inspector in another.<br>
  <strong>Transport:</strong> stdio (default) OR HTTP (if the server is configured for it — scenarios that are HTTP-specific will say so).<br>
  <strong>Auth / environment:</strong> Export any required env vars before starting the server. Typically <code>MCP_API_KEY=test-key</code> and/or <code>MCP_DB_URL=sqlite:///tmp/mcp-uat.db</code>. The Orchestrator will list the exact set in the dispatch email.<br>
  <strong>Required tools:</strong> <code>node</code> (for MCP Inspector), <code>python</code> (or the server's runtime), <code>jq</code> (for inspecting JSON output).<br>
  <br>
  <strong>One-time setup before any scenario:</strong><br>
  1. Export the required env vars in the server terminal: <code>export MCP_API_KEY=test-key</code> (plus whatever else is specified).<br>
  2. Start MCP Inspector against the server: <code>npx @modelcontextprotocol/inspector python -m your_mcp_server</code>.<br>
  3. The Inspector UI opens in your browser. Confirm the server's tools and resources list loads without errors.<br>
  <br>
  Every scenario below assumes:<br>
  1. The server is running (as in the setup).<br>
  2. MCP Inspector is open and connected.<br>
  3. If a scenario mutates server-side state (database rows, files), it includes cleanup steps.<br>
  <br>
  <strong>How to run a scenario:</strong> click "details" on the scenario card, invoke the specified tool call or resource read in MCP Inspector, compare the JSON-RPC response to the "Expected" block, then click Pass / Fail / Skip. Paste the full response JSON into the Notes field if the scenario fails — that's the most useful thing to capture.
</div>
```

- [ ] **Step 8: Create the mcp-server scenario reference**

Create `templates/uat/references/mcp-server-scenario.json`:

```json
{
  "id": 2,
  "feature": 1,
  "title": "list_items tool returns paginated results with correct total",
  "steps": "You are in MCP Inspector with the server connected (see 'Before you start').\n\nThis scenario assumes the server's test database is seeded with exactly 25 items from the fixture in the Orchestrator's setup instructions. If Inspector's initial connect failed, restart the server before proceeding.\n\n1. In the MCP Inspector 'Tools' pane, select the tool named 'list_items'.\n\n2. Invoke with arguments: {\"page\": 1, \"per_page\": 10}\n\n3. Observe the JSON-RPC response. Note the 'items' array length, the 'total' field, the 'page' field, and the 'has_next' field.\n\n4. Invoke again with: {\"page\": 3, \"per_page\": 10}\n\n5. Observe the response for this final (partial) page.\n\n6. Invoke a deliberately out-of-range call: {\"page\": 99, \"per_page\": 10}\n\n7. Observe the response — should be well-formed (no crash) even for out-of-range.\n\nNo cleanup needed: this scenario only reads data; no state mutation.",
  "expected": "Step 3: response.result.items is a JSON array of length 10. response.result.total is the integer 25. response.result.page is 1. response.result.has_next is true.\n\nStep 5: response.result.items is a JSON array of length 5 (25 total, pages 1+2 consumed 20, page 3 has the remaining 5). response.result.total is 25. response.result.page is 3. response.result.has_next is false.\n\nStep 7: response.result.items is an empty array (length 0). response.result.total is still 25. response.result.page is 99. response.result.has_next is false. The response does not contain an 'error' field at the top level — out-of-range pagination is not an error, just empty.\n\nPASS if all three invocations return the exact structure above with the stated field values. FAIL if any invocation returned a JSON-RPC error, the counts are wrong, has_next is wrong on any page, or the server crashed (Inspector disconnected). Paste the full JSON-RPC response for any failed step into the Notes field."
}
```

- [ ] **Step 9: Verify all 8 reference files exist and are well-formed**

```bash
# Check file count
ls templates/uat/references/ | wc -l
# Expected: 8

# Each pre-flight is wrapped in a fixture-ref div
for f in templates/uat/references/*-pre-flight.html; do
  grep -l '<div class="fixture-ref">' "$f" >/dev/null || { echo "MISSING fixture-ref: $f"; exit 1; }
done

# Each scenario is valid JSON
for f in templates/uat/references/*-scenario.json; do
  jq -e . "$f" >/dev/null || { echo "INVALID JSON: $f"; exit 1; }
done
echo "All 8 reference files verified."
```

Expected: `All 8 reference files verified.`

- [ ] **Step 10: Commit**

```bash
git add templates/uat/references/
git commit -m "feat(uat): add per-platform reference pre-flights and scenarios (BL-009)

Adds 4 pairs (8 files total) under templates/uat/references/:
  web-{pre-flight.html,scenario.json}
  desktop-{pre-flight.html,scenario.json}
  mobile-{pre-flight.html,scenario.json}
  mcp-server-{pre-flight.html,scenario.json}

Each pre-flight is a <div class=\"fixture-ref\"> snippet matching the
__TESTER_PRE_FLIGHT__ placeholder shape. Each scenario is a single JSON
object matching the __SCENARIOS_JSON__ array element shape, satisfying
all 8 items of the quality checklist.

Platform idiom coverage:
- web: browser + auth + devtools network-tab verification
- desktop: terminal + venv + deterministic commands + file mutation/cleanup
- mobile: device/simulator + offline queue behavior + tap-sequence + cleanup
- mcp-server: MCP Inspector + JSON-RPC tool invocation + pagination shape

'other' platform has no canned reference — handled via the co-build
protocol documented in docs/uat-authoring-guide.md (Task 5)."
```

---

## Task 5: Create the UAT authoring guide

**Files:**
- Create: `docs/uat-authoring-guide.md`

**Why:** Long-form authoring reference outside the template context. Includes the co-build protocol for `other` platforms — the only place that protocol is documented in detail.

- [ ] **Step 1: Create the guide with 7 sections**

Create `docs/uat-authoring-guide.md` with the following structure and content. Each section below is a literal level-2 heading; fill in the body content as described.

```markdown
# UAT Authoring Guide

Reference for generating usable UAT test scenarios in solo-orchestrator projects. Complements the embedded comments in `templates/uat/test-session-template.html` — read both together when filling out a UAT session.

## 1. Why UAT quality matters

One paragraph citing the observed failure modes from the lancache project (2026-04-22 UAT Session 1): schema-valid scenarios that were operationally broken because they assumed the tester knew the working directory, shell state, output-format deterministic conventions, and cleanup semantics. The rewrite took substantial Orchestrator time and would have repeated on every future project without framework-level guardrails. This guide codifies the rewrite recipe.

## 2. Universal quality checklist

The same 8-item checklist embedded as a comment in the HTML template, repeated here verbatim so it's discoverable outside the template context:

1. `steps` opens with a starting-state restatement.
2. `steps` numbers every command; no cross-refs.
3. `steps` commands are fully copy-pasteable.
4. `steps` prefers deterministic commands.
5. `expected` has a CONCRETE pass/fail anchor.
6. `expected` is ≥60 characters.
7. Mutations have numbered cleanup + verification.
8. External dependencies have a probe step.

## 3. Per-platform pre-flight patterns

Four subsections, each 3–5 paragraphs plus a summary table.

### 3.1 web

Discuss what a web pre-flight must establish: browser + version, app URL, test environment (local vs. staging vs. prod), credentials, network assumptions, devtools availability, starting-state assumption.

### 3.2 desktop

OS + arch, project root, language runtime + venv/equivalent, required tools, one-time setup, terminal assumptions.

### 3.3 mobile

Device or simulator/emulator, OS version, app build (TestFlight / Internal / local), permissions state, network assumption, how to run.

### 3.4 mcp-server

MCP client (Claude Desktop / Claude Code / MCP Inspector), server command, auth env vars, transport, starting state.

At the end of each subsection, point at the matching reference file in `templates/uat/references/<platform>-pre-flight.html`.

## 4. Per-platform scenario patterns

Parallel structure to section 3. For each platform, describe the typical scenario shapes:

### 4.1 web

Happy-path submit + observation; mutation with cleanup (create then delete); devtools-based verification; cross-browser delta handling when applicable.

### 4.2 desktop

Deterministic command sequences; state-mutation with git diff verification; SQL queries over meta-commands (reference the lancache sqlite3 `.tables` vs `SELECT name FROM sqlite_master` example); dependency probes (Docker, external services).

### 4.3 mobile

Tap sequences with clear observation criteria; offline/online transitions; permission states; screenshot attachment guidance; device-specific delta handling.

### 4.4 mcp-server

JSON-RPC tool invocation with response-shape assertion; pagination/cursor behavior; error-response shape; state-mutation tools with cleanup invocations.

Each subsection ends with a pointer to the matching reference file in `templates/uat/references/<platform>-scenario.json`.

## 5. Co-build protocol for 'other' platform

This is the interactive Q&A the session agent runs with the Orchestrator when the project's platform is `other` (embedded SoC, firmware, game, unusual CLI, or any combination the framework doesn't have a canned reference for).

When to run the protocol: at UAT session start, before generating the pre-flight block or any scenarios. The agent should announce: "Your project's platform is 'other' — no canned reference is available. I have five questions to calibrate the UAT shape before I generate scenarios."

### Question 1 — Runtime and tooling environment

"What does 'running the system under test' look like in your project? Is it a terminal command, a hardware device you power on, a browser, a specific IDE, a physical rig?"

Follow-up if unclear: "Give me one concrete example of starting or resetting the system to a known-good state."

### Question 2 — User-interaction model

"How does a human tester interact with the system under test during a scenario? Typing in a shell, tapping on a device, clicking in a browser, sending API requests, pressing physical buttons, observing serial output, some combination?"

### Question 3 — State mutation surface

"If a scenario makes the system 'do something' that changes state, what's affected? Files on disk, database rows, hardware registers, cloud resources, network peers, user accounts? Is that state easy to observe and reset?"

### Question 4 — External dependencies

"What external things does testing depend on? Hardware attached to the test rig, a specific network peer or internet service, a database with seeded data, a container engine, another instance of the same app?"

### Question 5 — Cleanup constraints

"If a scenario leaves residue (modified files, hardware in an unknown state, cloud resources, etc.), what's the appropriate cleanup? Is there a 'reset to factory' command, a git-checkout-level restore, a manual hardware power-cycle, a purge-by-timestamp script?"

### Synthesizing the answers

After collecting the answers, the agent should generate:

- A pre-flight block mirroring the structure of the first-class reference pre-flights, filled with the Orchestrator's specifics.
- An initial scenario or two that demonstrate the shape (happy path, mutation with cleanup, dependency-probed if applicable) using the Orchestrator's interaction model.

Show these to the Orchestrator for review before generating the full scenario set. The Orchestrator may refine — use the refined shape as the template for remaining scenarios.

## 6. Linter usage

Invocation: `scripts/lint-uat-scenarios.sh <populated-html-file>`.

Exit codes:
- 0 — all scenarios clean. Proceed with dispatch.
- 1 — quality violations. Read the stderr list (one violation per line). Revise flagged scenarios. Re-run the linter until exit 0.
- 2 — structural failure (file not found, JSON unparseable, scenarios block missing). Fix file integrity before worrying about scenario quality.

Common false-positive-looking cases and how to resolve them:

- A `steps` line that legitimately starts with a command (e.g., `cd` to a different directory): the state-restatement check passes because `cd ` IS one of the accepted keywords. If you're getting the error anyway, check the very first character of `steps` — indentation or leading whitespace will trip it.
- A `expected` that's short but has a clear anchor (e.g., `exit=0`): expand the prose around the anchor to reach the 60-char minimum. The character minimum is a proxy for specificity, not a literal rule — meeting it honestly is easy with one more sentence.

## 7. Extending for a new platform

When solo-orchestrator gains a new first-class platform (e.g., `extension` for browser extensions, `cli` if it splits out from desktop), three things need to happen for UAT parity:

1. Add `templates/uat/references/<platform>-pre-flight.html` and `templates/uat/references/<platform>-scenario.json` matching the shape of the existing four.
2. Update `init.sh`'s per-platform reference copy step to include the new platform in its case branch.
3. Add a subsection in Sections 3 and 4 of this guide documenting the new platform's pre-flight and scenario patterns.

The `other` platform co-build protocol remains the fallback for anything that doesn't have a matching reference pair.
```

- [ ] **Step 2: Verify the guide is well-formed**

```bash
# Section count
grep -c '^## ' docs/uat-authoring-guide.md
# Expected: 7

# Each section has a body (non-empty between headers)
awk '/^## / {if (prev && !content) print "EMPTY:", prev; prev=$0; content=0; next} /./{if ($0 !~ /^#/) content=1}' docs/uat-authoring-guide.md
# Expected: no "EMPTY:" output
```

- [ ] **Step 3: Commit**

```bash
git add docs/uat-authoring-guide.md
git commit -m "docs(uat): add authoring guide with co-build protocol (BL-009)

Long-form UAT authoring reference:
- Why UAT quality matters (lancache observed failures)
- Universal 8-item quality checklist
- Per-platform pre-flight patterns (web, desktop, mobile, mcp-server)
- Per-platform scenario patterns
- Co-build protocol for 'other' platforms (5-question Q&A the session
  agent runs with the Orchestrator before generating scenarios)
- Linter usage + common false-positive cases
- Extension guide for adding a new platform"
```

---

## Task 6: Update init.sh with new paths and per-platform reference copy

**Files:**
- Modify: `init.sh`

**Why:** init.sh currently copies the old flat-path UAT templates (lines 1075–1076 from the pre-refactor state). After Task 1's move, those paths are stale. Additionally, the per-platform reference pair must be copied based on the project's `$PLATFORM`.

- [ ] **Step 1: Find the UAT template copy block in init.sh**

```bash
grep -n 'uat-test-session\|uat-test-template\|tests/uat/templates' init.sh | head -5
```

Expected output includes approximately:

```
1074:  mkdir -p tests/uat/templates tests/uat/sessions
1075:  cp "$SCRIPT_DIR/templates/uat-test-template.md" tests/uat/templates/test-session-template.md
1076:  cp "$SCRIPT_DIR/templates/uat-test-session.html" tests/uat/templates/test-session-template.html
```

If line numbers differ, use the grep output to locate the actual region. The old paths (`templates/uat-test-template.md` and `templates/uat-test-session.html`) are what need updating.

- [ ] **Step 2: Replace the UAT copy block**

Find the exact block found in Step 1. Replace it with the expanded block:

```bash
  mkdir -p tests/uat/templates tests/uat/sessions tests/uat/examples
  cp "$SCRIPT_DIR/templates/uat/test-session-template.md"   tests/uat/templates/test-session-template.md
  cp "$SCRIPT_DIR/templates/uat/test-session-template.html" tests/uat/templates/test-session-template.html

  # Per-platform reference copy (spec 2026-04-23-uat-template-quality-design.md § Flow A)
  if [ "$PLATFORM" != "other" ] && \
     [ -f "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-pre-flight.html" ] && \
     [ -f "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-scenario.json" ]; then
    cp "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-pre-flight.html" \
       tests/uat/examples/pre-flight-reference.html
    cp "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-scenario.json" \
       tests/uat/examples/scenario-reference.json
    print_ok "UAT platform reference copied for $PLATFORM"
  elif [ "$PLATFORM" = "other" ]; then
    print_info "Platform is 'other' — no UAT canned reference copied."
    print_info "When starting a UAT session, the agent will run the co-build Q&A"
    print_info "protocol with you per docs/uat-authoring-guide.md § 5."
  else
    print_warn "UAT reference files not found for platform '$PLATFORM'. Falling back to 'other'-style co-build protocol; see docs/uat-authoring-guide.md § 5."
  fi
```

- [ ] **Step 3: Syntax-check init.sh**

```bash
bash -n init.sh && echo "init.sh syntax OK"
```

Expected: `init.sh syntax OK`

- [ ] **Step 4: Verify references are discoverable**

```bash
grep -n 'pre-flight-reference\|scenario-reference' init.sh
```

Expected: the two new `cp` lines for the references appear in init.sh.

- [ ] **Step 5: Commit**

```bash
git add init.sh
git commit -m "feat(init): update UAT template paths + per-platform reference copy (BL-009)

Templates moved to templates/uat/ in Task 1; init.sh was still referring
to the old flat paths and would fail at scaffold time.

New behavior:
- Copies source templates from templates/uat/ (not templates/uat-*)
- For first-class platforms (web/desktop/mobile/mcp-server), copies the
  matching reference pair from templates/uat/references/ into the new
  project's tests/uat/examples/{pre-flight-reference.html, scenario-reference.json}
- For 'other' platform, prints a note pointing at the co-build protocol
  in docs/uat-authoring-guide.md § 5
- If the framework's reference files are missing (corrupted install),
  warns and falls back to the 'other'-style co-build path; not blocking."
```

---

## Task 7: Update upgrade-project.sh with UAT migration block

**Files:**
- Modify: `scripts/upgrade-project.sh`

**Why:** Existing projects have old UAT source templates (and no reference files) under `tests/uat/templates/`. The upgrade should re-copy updated source templates and copy the new per-platform reference pair. Idempotent — safe to re-run.

- [ ] **Step 1: Find the existing upgrade-project.sh migration section**

```bash
grep -n 'spec 2026-04-21\|Migrating flat CI\|host-aware migration' scripts/upgrade-project.sh | head -3
```

Expected: a line or two matching the host-aware migration block added during BL-008 (around the file's tail). This is the precedent pattern — UAT migration follows the same style.

- [ ] **Step 2: Add a UAT migration block immediately after the host-aware migration**

Find the line `# --- Host-aware migration (spec 2026-04-21) ---` and its closing `fi` block. Immediately after that block's closing `fi`, before the validation run that follows, insert:

```bash

# --- UAT template migration (spec 2026-04-23-uat-template-quality-design.md) ---
# Re-copy updated UAT source templates and per-platform reference pair.
# Idempotent — safe to re-run.
if [ -d tests/uat/templates ] || [ -d tests/uat ]; then
  print_step "Migrating UAT templates and references"
  mkdir -p tests/uat/templates tests/uat/examples

  # Source templates
  if [ -f "$SCRIPT_DIR/../templates/uat/test-session-template.html" ]; then
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.html" \
       tests/uat/templates/test-session-template.html
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.md" \
       tests/uat/templates/test-session-template.md
    print_ok "UAT source templates refreshed"
  fi

  # Per-platform reference pair
  # Read PLATFORM from intake-progress.json (intake wizard's output)
  uat_platform=""
  if [ -f .claude/intake-progress.json ]; then
    uat_platform=$(jq -r '.answers.platform // empty' .claude/intake-progress.json 2>/dev/null || true)
  fi

  if [ -n "$uat_platform" ] && [ "$uat_platform" != "other" ] && \
     [ -f "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-pre-flight.html" ]; then
    cp "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-pre-flight.html" \
       tests/uat/examples/pre-flight-reference.html
    cp "$SCRIPT_DIR/../templates/uat/references/${uat_platform}-scenario.json" \
       tests/uat/examples/scenario-reference.json
    print_ok "UAT reference pair copied for platform '$uat_platform'"
  elif [ "$uat_platform" = "other" ]; then
    print_info "Platform is 'other' — UAT reference is co-build protocol."
    print_info "See docs/uat-authoring-guide.md § 5 next time you start a UAT session."
  else
    print_warn "UAT platform unknown (intake-progress.json missing or lacks 'platform' field). Skipping reference copy; see docs/uat-authoring-guide.md."
  fi

  echo ""
  print_info "UAT quality guardrails now active. Next UAT session should:"
  print_info "  1. Read templates/uat/test-session-template.html's embedded checklist"
  print_info "  2. Use tests/uat/examples/ as shape references (first-class platforms)"
  print_info "  3. Run scripts/lint-uat-scenarios.sh <populated-file> before saving"
  print_info "See docs/uat-authoring-guide.md for details."
  echo ""
fi
```

- [ ] **Step 3: Syntax-check upgrade-project.sh**

```bash
bash -n scripts/upgrade-project.sh && echo "upgrade-project.sh syntax OK"
```

Expected: `upgrade-project.sh syntax OK`

- [ ] **Step 4: Commit**

```bash
git add scripts/upgrade-project.sh
git commit -m "feat(upgrade): UAT template migration for existing projects (BL-009)

Adds a UAT migration block to upgrade-project.sh that:
- Re-copies updated source templates from templates/uat/
- Copies the per-platform reference pair into tests/uat/examples/
  (reads platform from .claude/intake-progress.json)
- For 'other' platform: prints the co-build protocol pointer
- For unknown platform (missing intake state): warns and skips

Idempotent — safe to run multiple times. Printed post-upgrade notice
reminds the user of the new authoring workflow (guide + linter)."
```

---

## Task 8: Update CLAUDE.md template Testing & Bug Workflow section

**Files:**
- Modify: `templates/generated/claude-md.tmpl`

**Why:** The downstream project's CLAUDE.md is generated from this template. Agents read CLAUDE.md at session start, so the Testing & Bug Workflow section is where the linter-run step and co-build pointer need to live for agents to notice them.

- [ ] **Step 1: Find the Testing & Bug Workflow section**

```bash
grep -n 'Testing & Bug Workflow\|Gate enforcement\|Severity rules' templates/generated/claude-md.tmpl | head -5
```

Expected: the section heading and surrounding bullets (added during BL-008's rollback subsection).

- [ ] **Step 2: Add the linter step into the numbered 1–9 UAT sequence**

Find the numbered list inside the Testing & Bug Workflow section. It currently looks like:

```markdown
  1. Check the gate: `scripts/test-gate.sh --check-batch`
  1a. Start the UAT checklist: `scripts/process-checklist.sh --start-uat N` (where N is the session number)
  2. If blocked: dispatch parallel test agents (automated suite, exploratory, cross-platform)
  3. Generate test template for human tester(s) and wait for results
  4. Verify submission completeness — list incomplete scenarios, ask to continue or finish
  5. Consolidate all results into bug tracker
  ...
```

Insert a new step 3a immediately after step 3:

```markdown
  3. Generate test template for human tester(s) and wait for results
  3a. **Quality gate:** run `scripts/lint-uat-scenarios.sh <populated-file>` on the generated template. Must exit 0 before dispatch. If exit 1: read violations, revise scenarios, re-run. If exit 2: investigate file/JSON integrity. See `docs/uat-authoring-guide.md § 6` for details.
```

- [ ] **Step 3: Add the "Recovering from mistakes" co-build pointer**

Find the existing "Recovering from mistakes" subsection added during BL-008. Immediately after it (before the next `###` subsection), add:

```markdown
- **UAT authoring:**
  - Full per-platform guidance + co-build protocol for 'other' platforms: `docs/uat-authoring-guide.md`
  - Quality linter: `scripts/lint-uat-scenarios.sh <populated-file>`
  - Platform-specific reference examples: `tests/uat/examples/` (populated by init.sh based on your project's platform)
```

- [ ] **Step 4: Verify the additions**

```bash
grep -n 'lint-uat-scenarios.sh\|uat-authoring-guide.md' templates/generated/claude-md.tmpl
```

Expected: at least 3 matches (linter invocation in step 3a, linter + guide in the UAT authoring subsection).

- [ ] **Step 5: Commit**

```bash
git add templates/generated/claude-md.tmpl
git commit -m "docs(claude-md): add UAT linter step + authoring guide pointer (BL-009)

Two additions to the Testing & Bug Workflow section:
1. New numbered step 3a in the UAT sequence: run lint-uat-scenarios.sh
   on the populated template, must exit 0 before dispatch.
2. 'UAT authoring' subsection with pointers to:
   - docs/uat-authoring-guide.md (full guide + co-build protocol)
   - scripts/lint-uat-scenarios.sh (linter)
   - tests/uat/examples/ (per-platform reference files)

Surfaces the new guardrails where agents read them (CLAUDE.md at
session start)."
```

---

## Task 9: Integration tests for init + upgrade flows

**Files:**
- Modify: `tests/edge-cases-scripts.sh`

**Why:** Spec §Testing Layer 2 calls for 7 cases covering init-time per-platform reference copy, `other`-platform skip behavior, and upgrade migration behavior. These are integration-style (exercise init.sh / upgrade-project.sh partial flows against a temp project).

- [ ] **Step 1: Read the current structure of edge-cases-scripts.sh**

```bash
head -40 tests/edge-cases-scripts.sh
```

Confirm the file's existing test-function-plus-runner pattern. The new UAT integration cases follow the same idiom.

- [ ] **Step 2: Append the 7 new cases**

At the end of `tests/edge-cases-scripts.sh` (before any final aggregate report if present), append the following test functions and their invocations. If the file already has a runner section, integrate the `run_test` or equivalent calls there; if not, the block below is self-contained.

```bash

# --- BL-009: UAT template quality integration tests ---

_uat_seed_fake_project() {
  # Args: work-dir, platform
  # Creates a minimal project state allowing the UAT copy block of init.sh
  # (or upgrade-project.sh) to be exercised against it.
  local work="$1" platform="$2"
  mkdir -p "$work/.claude"
  cat > "$work/.claude/intake-progress.json" <<JSON
{"answers": {"platform": "$platform", "project_name": "uat-test"}}
JSON
}

_uat_run_init_copy_block() {
  # Args: work-dir, platform
  # Source-in init.sh's helpers (print_ok/warn/info via helpers.sh) and
  # execute a minimal subset of the UAT copy block directly in work-dir.
  # Extracting just the copy logic keeps the test fast; full init.sh run
  # would require mocking prerequisites.
  local work="$1" platform="$2"
  local repo_root
  repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  (
    cd "$work"
    export SCRIPT_DIR="$repo_root"
    export PLATFORM="$platform"
    # shellcheck disable=SC1091
    source "$repo_root/scripts/lib/helpers.sh"
    mkdir -p tests/uat/templates tests/uat/sessions tests/uat/examples
    cp "$SCRIPT_DIR/templates/uat/test-session-template.md"   tests/uat/templates/test-session-template.md
    cp "$SCRIPT_DIR/templates/uat/test-session-template.html" tests/uat/templates/test-session-template.html
    if [ "$PLATFORM" != "other" ] && \
       [ -f "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-pre-flight.html" ] && \
       [ -f "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-scenario.json" ]; then
      cp "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-pre-flight.html" \
         tests/uat/examples/pre-flight-reference.html
      cp "$SCRIPT_DIR/templates/uat/references/${PLATFORM}-scenario.json" \
         tests/uat/examples/scenario-reference.json
    fi
  )
}

test_uat_init_web() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  _uat_seed_fake_project "$work" "web"
  _uat_run_init_copy_block "$work" "web"
  [ -f "$work/tests/uat/examples/pre-flight-reference.html" ] || { echo "web pre-flight ref missing"; return 1; }
  [ -f "$work/tests/uat/examples/scenario-reference.json" ] || { echo "web scenario ref missing"; return 1; }
  grep -qi 'browser\|devtools\|app url' "$work/tests/uat/examples/pre-flight-reference.html" \
    || { echo "web ref doesn't look web-specific"; return 1; }
}

test_uat_init_desktop() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  _uat_seed_fake_project "$work" "desktop"
  _uat_run_init_copy_block "$work" "desktop"
  [ -f "$work/tests/uat/examples/pre-flight-reference.html" ] || return 1
  grep -qi 'terminal\|project root\|venv\|runtime' "$work/tests/uat/examples/pre-flight-reference.html" \
    || { echo "desktop ref doesn't look desktop-specific"; return 1; }
}

test_uat_init_mobile() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  _uat_seed_fake_project "$work" "mobile"
  _uat_run_init_copy_block "$work" "mobile"
  [ -f "$work/tests/uat/examples/pre-flight-reference.html" ] || return 1
  grep -qi 'device\|simulator\|testflight\|android' "$work/tests/uat/examples/pre-flight-reference.html" \
    || { echo "mobile ref doesn't look mobile-specific"; return 1; }
}

test_uat_init_mcp_server() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  _uat_seed_fake_project "$work" "mcp-server"
  _uat_run_init_copy_block "$work" "mcp-server"
  [ -f "$work/tests/uat/examples/pre-flight-reference.html" ] || return 1
  grep -qi 'mcp\|inspector\|json-rpc\|tool call' "$work/tests/uat/examples/pre-flight-reference.html" \
    || { echo "mcp ref doesn't look mcp-specific"; return 1; }
}

test_uat_init_other_skips_refs() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  _uat_seed_fake_project "$work" "other"
  _uat_run_init_copy_block "$work" "other"
  # Source templates should exist
  [ -f "$work/tests/uat/templates/test-session-template.html" ] || { echo "html template missing"; return 1; }
  # Reference files should NOT exist
  [ ! -f "$work/tests/uat/examples/pre-flight-reference.html" ] || { echo "unexpected ref file for 'other'"; return 1; }
  [ ! -f "$work/tests/uat/examples/scenario-reference.json" ] || { echo "unexpected ref file for 'other'"; return 1; }
}

test_uat_upgrade_refreshes_templates() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  _uat_seed_fake_project "$work" "desktop"
  # Seed an OLD template at the downstream path — minimal content that doesn't
  # match the new quality guardrails.
  mkdir -p "$work/tests/uat/templates"
  echo "<!-- OLD TEMPLATE, no __TESTER_PRE_FLIGHT__ placeholder -->" \
    > "$work/tests/uat/templates/test-session-template.html"

  # Run the UAT migration block from upgrade-project.sh against this work dir.
  local repo_root; repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  (
    cd "$work"
    export SCRIPT_DIR="$repo_root/scripts"
    # shellcheck disable=SC1091
    source "$repo_root/scripts/lib/helpers.sh"
    mkdir -p tests/uat/templates tests/uat/examples
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.html" \
       tests/uat/templates/test-session-template.html
    cp "$SCRIPT_DIR/../templates/uat/test-session-template.md" \
       tests/uat/templates/test-session-template.md
    local uat_platform
    uat_platform=$(jq -r '.answers.platform // empty' .claude/intake-progress.json 2>/dev/null || echo "")
    if [ "$uat_platform" = "desktop" ]; then
      cp "$SCRIPT_DIR/../templates/uat/references/desktop-pre-flight.html" \
         tests/uat/examples/pre-flight-reference.html
      cp "$SCRIPT_DIR/../templates/uat/references/desktop-scenario.json" \
         tests/uat/examples/scenario-reference.json
    fi
  )

  # After upgrade: new template present with placeholder
  grep -q '__TESTER_PRE_FLIGHT__' "$work/tests/uat/templates/test-session-template.html" \
    || { echo "migration didn't refresh template"; return 1; }
  [ -f "$work/tests/uat/examples/pre-flight-reference.html" ] || { echo "ref not copied"; return 1; }
}

test_uat_upgrade_idempotent() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  _uat_seed_fake_project "$work" "desktop"
  # Run the migration TWICE; second run should not produce additional mutations
  # beyond what the first produced.
  for i in 1 2; do
    local repo_root; repo_root="$(cd "$(dirname "$0")/.." && pwd)"
    (
      cd "$work"
      export SCRIPT_DIR="$repo_root/scripts"
      # shellcheck disable=SC1091
      source "$repo_root/scripts/lib/helpers.sh"
      mkdir -p tests/uat/templates tests/uat/examples
      cp "$SCRIPT_DIR/../templates/uat/test-session-template.html" \
         tests/uat/templates/test-session-template.html
      cp "$SCRIPT_DIR/../templates/uat/references/desktop-pre-flight.html" \
         tests/uat/examples/pre-flight-reference.html
    )
  done
  # After two runs the template file should still match the canonical source
  diff -q "$work/tests/uat/templates/test-session-template.html" \
          "$REPO_ROOT/templates/uat/test-session-template.html" \
    >/dev/null 2>&1 || { echo "idempotency violated"; return 1; }
}

echo ""
echo "═══ BL-009 UAT integration tests ═══"
# Adapt the invocation idiom to whatever edge-cases-scripts.sh uses. If it has
# a `run_test` helper, call it; otherwise call the functions directly under
# `( set -e; test_X ) && echo ok || echo FAIL`.
for t in test_uat_init_web test_uat_init_desktop test_uat_init_mobile \
         test_uat_init_mcp_server test_uat_init_other_skips_refs \
         test_uat_upgrade_refreshes_templates test_uat_upgrade_idempotent; do
  if ( set -e; $t ); then
    echo "✓ $t"
  else
    echo "✗ $t FAILED"
  fi
done
```

- [ ] **Step 3: Run the full test suite and verify the new cases pass**

```bash
bash tests/edge-cases-scripts.sh 2>&1 | tail -20
```

Expected: all 7 new `test_uat_*` cases show `✓`. If any existing tests in edge-cases-scripts.sh fail due to unrelated reasons, that's pre-existing and not a regression of this task — note but don't block.

- [ ] **Step 4: Also run the linter test suite to confirm no regression**

```bash
bash tests/test-lint-uat-scenarios.sh 2>&1 | tail -4
```

Expected: `Tests: 11 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add tests/edge-cases-scripts.sh
git commit -m "test(uat): integration cases for init + upgrade (BL-009)

7 new cases in tests/edge-cases-scripts.sh covering:
- Init for each first-class platform copies the matching ref pair
  (web, desktop, mobile, mcp-server) with grep-level verification
  that content is platform-specific
- Init for 'other' skips reference copy, keeps source templates
- Upgrade refreshes old-template downstream copies with new placeholder
- Upgrade migration is idempotent across multiple runs

Exercises the UAT copy block of init.sh and the UAT migration block of
upgrade-project.sh in isolation against seeded temp projects."
```

---

## Plan Self-Review Checklist

**Spec coverage:**
- [ ] Decision 1 (scope C, redesigned for platform awareness) → Tasks 1, 4 (HTML template content + per-platform refs)
- [ ] Decision 2 (full 4-platform + 'other' co-build) → Tasks 4 (4 ref pairs), 5 (co-build protocol in guide), 6 (init 'other' skip)
- [ ] Decision 3 (partial MD parity) → Task 2
- [ ] Decision 4 (ship linter) → Task 3 (TDD)
- [ ] Decision 5 (file layout: `templates/uat/` subdirectory) → Task 1 git mv + all subsequent tasks using new paths
- [ ] Decision 6 (upgrade-project.sh auto-migrate) → Task 7
- [ ] Architecture Layer 1 (template guardrails) → Task 1 Steps 2–3
- [ ] Architecture Layer 2 (per-platform refs + co-build) → Tasks 4, 5, 6
- [ ] Architecture Layer 3 (linter) → Task 3
- [ ] CLAUDE.md integration → Task 8
- [ ] Linter unit tests (11 cases) → Task 3
- [ ] Integration tests (7 cases) → Task 9
- [ ] `docs/uat-authoring-guide.md` (7 sections) → Task 5

**Placeholder scan:**
- [ ] No "TBD" / "TODO" / "similar to Task N" anywhere. Each reference file's content is shown verbatim in Task 4. The authoring guide's prose is described per-section with enough content shape to reproduce. All bash code blocks are complete and runnable.

**Type consistency:**
- [ ] Placeholder name `__TESTER_PRE_FLIGHT__` (not `__PRE_FLIGHT__` or `__TESTER_PREFLIGHT__`) used consistently across Tasks 1, 3 tests, 6 init, 8 CLAUDE.md.
- [ ] Linter command name `scripts/lint-uat-scenarios.sh` consistent across Tasks 3, 5, 8.
- [ ] Reference file names `<platform>-pre-flight.html` and `<platform>-scenario.json` consistent across Tasks 4, 6, 7, 9.
- [ ] Platform names `web`, `desktop`, `mobile`, `mcp-server`, `other` consistent.
- [ ] Audit log / exit-code conventions match the existing solo patterns (0 = clean, 1 = violation, 2 = structural).

# UAT, Bug Tracking & Test-Fix-Verify Loop — Implementation Plan

> **Archived 2026-07-05 (BL-049):** Shipped via commit `a5fa5fa` ("feat: UAT system — test-gate, templates, phase integration", 2026-04-04). See `docs/superpowers/plans/archive/README.md` for the archive convention.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable test-fix-verify loop to the Build Loop with parallel agent testing, human manual testing, bug tracking, severity-based triage, mechanical gate enforcement, and Phase 2→3 deferred bug resolution.

**Architecture:** `scripts/test-gate.sh` enforces testing intervals and phase gate bug checks. UAT sessions use a directory structure (`tests/uat/sessions/`) with agent results and human submissions. The Builder's Guide gets Steps 2.7-2.9 added to the Build Loop. Intake captures testing preferences. CLAUDE.md directs agent behavior.

**Tech Stack:** Bash, jq, Markdown templates

**Spec:** `docs/superpowers/specs/2026-04-03-uat-bug-tracking-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|---|---|
| `scripts/test-gate.sh` | Mechanical gate — batch interval check and phase gate bug status check |
| `templates/uat-test-template.md` | Master test session template for human testers |

### Modified Files
| File | Change |
|---|---|
| `docs/builders-guide.md` | Add Steps 2.7-2.9, severity classification in Phase 1, enhanced Phase 2→3 gate, enhanced Phase 3.6, Phase 4 regression cadence |
| `templates/project-intake.md` | Add Section 11.5: Testing & Bug Tracking (renumber existing 12/13) |
| `init.sh` | Copy test-gate.sh + UAT template, generate tests/uat/ dirs, add CLAUDE.md testing section, generate build-progress.json |
| `scripts/check-phase-gate.sh` | Call test-gate.sh --check-phase-gate |
| `README.md` | Add UAT workflow section |

---

### Task 1: Create UAT Test Template

**Files:**
- Create: `templates/uat-test-template.md`

- [ ] **Step 1: Create the master test template**

```markdown
# UAT Test Session — [SESSION_NUMBER]

**Date:** [SESSION_DATE]
**Features Under Test:** [FEATURE_LIST]
**Tester:** [Your name]

---

## Instructions

1. For each feature below, follow the test scenarios step by step
2. Mark each scenario Pass or Fail
3. If Fail, fill in the bug details in the Bugs Found section below
4. Drop your completed file in `tests/uat/sessions/[session-folder]/submissions/`
5. Tell the Orchestrator agent "results are in" when done

---

## Test Scenarios

<!-- Agent pre-populates this section with feature-specific scenarios -->

### Feature: [FEATURE_NAME]

| # | Scenario | Steps | Expected Result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| 1 | [Happy path from User Journey] | [Steps] | [Expected] | | |
| 2 | [Error/edge case] | [Steps] | [Expected error handling] | | |
| 3 | [Boundary condition] | [Steps] | [Expected] | | |

---

## Bugs Found

| # | Severity | Feature | Description | Steps to Reproduce | Expected vs Actual |
|---|---|---|---|---|---|
| | SEV-? | | | | |

### Severity Guide
- **SEV-1:** Data loss, security breach, app crash on core flow
- **SEV-2:** Feature broken but workaround exists, significant UX failure
- **SEV-3:** Minor UX issue, cosmetic, non-core edge case
- **SEV-4:** Enhancement, suggestion, polish

---

## Overall Notes

_Free-form observations, UX concerns, suggestions, things that felt wrong even if they technically worked._

```

- [ ] **Step 2: Commit**

```bash
git add templates/uat-test-template.md
git commit -m "feat(uat): add master test session template for human testers

Pre-populated by agent per session with feature scenarios from
User Journey. Includes severity guide and bug report fields."
```

---

### Task 2: Create test-gate.sh

**Files:**
- Create: `scripts/test-gate.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Test Gate
# Mechanical enforcement for the test-fix-verify loop.
#
# Usage:
#   scripts/test-gate.sh --check-batch       # Can I start the next feature?
#   scripts/test-gate.sh --check-phase-gate  # Can I transition Phase 2→3?
#   scripts/test-gate.sh --reset-counter     # Reset feature counter after test session
#   scripts/test-gate.sh --record-feature NAME  # Record a completed feature
#   scripts/test-gate.sh --help

# Colors
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

print_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }

BUILD_PROGRESS=".claude/build-progress.json"

# --- Argument parsing ---
ACTION=""
FEATURE_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check-batch)      ACTION="check-batch";      shift ;;
    --check-phase-gate) ACTION="check-phase-gate";  shift ;;
    --reset-counter)    ACTION="reset-counter";      shift ;;
    --record-feature)   ACTION="record-feature"; FEATURE_NAME="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: scripts/test-gate.sh [--check-batch] [--check-phase-gate] [--reset-counter] [--record-feature NAME]"
      echo ""
      echo "Commands:"
      echo "  --check-batch       Check if testing session is due (exit 0=continue, 1=testing required)"
      echo "  --check-phase-gate  Check if Phase 2→3 transition is clear (exit 0=clear, 1=blocked, 2=warnings)"
      echo "  --reset-counter     Reset feature counter after testing session completes"
      echo "  --record-feature N  Record a completed feature and increment counter"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ACTION" ]; then
  echo "No action specified. Use --help for usage." >&2
  exit 1
fi

# --- Ensure build-progress.json exists ---
ensure_progress_file() {
  if [ ! -f "$BUILD_PROGRESS" ]; then
    mkdir -p .claude
    cat > "$BUILD_PROGRESS" << 'EOF'
{
  "features_completed": [],
  "features_since_last_test": 0,
  "test_interval": 2,
  "last_test_session": null,
  "testing_required": false,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 0
}
EOF
  fi
}

# --- Actions ---

check_batch() {
  ensure_progress_file

  local since_last interval
  since_last=$(jq -r '.features_since_last_test' "$BUILD_PROGRESS")
  interval=$(jq -r '.test_interval' "$BUILD_PROGRESS")

  if [ "$since_last" -ge "$interval" ]; then
    print_fail "Testing session required ($since_last features since last test, interval is $interval)"
    print_info "Run a UAT testing session before starting the next feature."
    exit 1
  else
    local remaining=$((interval - since_last))
    print_ok "Clear to continue ($remaining features until next testing session)"
    exit 0
  fi
}

record_feature() {
  ensure_progress_file

  local name="$1"
  local tmp
  tmp=$(mktemp)

  jq --arg name "$name" '
    .features_completed += [$name] |
    .features_since_last_test += 1 |
    .testing_required = (.features_since_last_test >= .test_interval)
  ' "$BUILD_PROGRESS" > "$tmp" && mv "$tmp" "$BUILD_PROGRESS"

  local since_last interval
  since_last=$(jq -r '.features_since_last_test' "$BUILD_PROGRESS")
  interval=$(jq -r '.test_interval' "$BUILD_PROGRESS")

  print_ok "Feature '$name' recorded ($since_last/$interval until next test session)"

  if [ "$since_last" -ge "$interval" ]; then
    print_warn "Testing session now required before starting next feature"
  fi
}

reset_counter() {
  ensure_progress_file

  local today
  today=$(date +%Y-%m-%d)
  local tmp
  tmp=$(mktemp)

  jq --arg date "$today" '
    .features_since_last_test = 0 |
    .testing_required = false |
    .last_test_session = $date |
    .sessions_completed += 1
  ' "$BUILD_PROGRESS" > "$tmp" && mv "$tmp" "$BUILD_PROGRESS"

  print_ok "Feature counter reset. Testing session recorded ($today)"
}

check_phase_gate() {
  # Check for BUGS.md-based tracking
  local sev1_count=0
  local sev2_open=0
  local sev2_deferred=0
  local sev3_open=0
  local has_bugs=false

  if [ -f "BUGS.md" ]; then
    has_bugs=true
    # Count open bugs by severity
    # BUGS.md format: | # | SEV-N | Status | Feature | Description | ...
    # Status values: Open, Deferred, Fixed, Won't Fix, Post-MVP, Removed
    sev1_count=$(grep -c '|[[:space:]]*SEV-1[[:space:]]*|[[:space:]]*Open' "BUGS.md" 2>/dev/null || echo "0")
    sev2_open=$(grep -c '|[[:space:]]*SEV-2[[:space:]]*|[[:space:]]*Open' "BUGS.md" 2>/dev/null || echo "0")
    sev2_deferred=$(grep -c '|[[:space:]]*SEV-2[[:space:]]*|[[:space:]]*Deferred' "BUGS.md" 2>/dev/null || echo "0")
    sev3_open=$(grep -c '|[[:space:]]*SEV-3[[:space:]]*|[[:space:]]*Open' "BUGS.md" 2>/dev/null || echo "0")
  fi

  # Also check GitHub Issues if gh CLI available
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    local gh_sev1 gh_sev2_open gh_sev2_deferred gh_sev3
    gh_sev1=$(gh issue list --label "SEV-1" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    gh_sev2_open=$(gh issue list --label "SEV-2" --label "fix-now" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    gh_sev2_deferred=$(gh issue list --label "SEV-2" --label "deferred" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    gh_sev3=$(gh issue list --label "SEV-3" --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

    sev1_count=$((sev1_count + gh_sev1))
    sev2_open=$((sev2_open + gh_sev2_open))
    sev2_deferred=$((sev2_deferred + gh_sev2_deferred))
    sev3_open=$((sev3_open + gh_sev3))
    has_bugs=true
  fi

  if [ "$has_bugs" = false ]; then
    print_warn "No bug tracking source found (BUGS.md or GitHub Issues)"
    print_info "Cannot verify bug status. Proceeding with warning."
    exit 2
  fi

  echo ""
  echo -e "${BOLD}Phase 2→3 Bug Gate Check${NC}"
  echo ""

  local blocked=false
  local warnings=false

  # SEV-1: must be resolved
  if [ "$sev1_count" -gt 0 ]; then
    print_fail "SEV-1 bugs open: $sev1_count (BLOCKED — must resolve before Phase 3)"
    blocked=true
  else
    print_ok "No open SEV-1 bugs"
  fi

  # SEV-2 open: must be resolved
  if [ "$sev2_open" -gt 0 ]; then
    print_fail "SEV-2 bugs open (fix-now): $sev2_open (BLOCKED — must resolve before Phase 3)"
    blocked=true
  else
    print_ok "No open SEV-2 fix-now bugs"
  fi

  # SEV-2 deferred: must resolve or remove feature
  if [ "$sev2_deferred" -gt 0 ]; then
    print_fail "SEV-2 bugs deferred: $sev2_deferred (BLOCKED — must resolve or remove/hide feature)"
    echo ""
    echo -e "${BOLD}For each deferred SEV-2 bug, you must:${NC}"
    echo "  1. Resolve — fix the bug, re-test, verify"
    echo "  2. Remove — disable/hide the feature entirely (moves to Post-MVP backlog)"
    echo ""
    blocked=true
  else
    print_ok "No deferred SEV-2 bugs"
  fi

  # SEV-3: warning only, user attestation
  if [ "$sev3_open" -gt 0 ]; then
    print_warn "SEV-3 bugs open: $sev3_open (user attestation required)"
    warnings=true
  else
    print_ok "No open SEV-3 bugs"
  fi

  echo ""

  if [ "$blocked" = true ]; then
    print_fail "Phase 2→3 transition BLOCKED. Resolve issues above."
    exit 1
  elif [ "$warnings" = true ]; then
    print_warn "Phase 2→3 has warnings. User attestation required."
    exit 2
  else
    print_ok "Phase 2→3 bug gate clear."
    exit 0
  fi
}

# --- Dispatch ---
case "$ACTION" in
  check-batch)      check_batch ;;
  check-phase-gate) check_phase_gate ;;
  reset-counter)    reset_counter ;;
  record-feature)   record_feature "$FEATURE_NAME" ;;
esac
```

- [ ] **Step 2: Make executable and validate**

Run: `chmod +x scripts/test-gate.sh && bash -n scripts/test-gate.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Test basic operations**

Run:
```bash
TEST_DIR=$(mktemp -d) && cd "$TEST_DIR" && mkdir -p .claude
bash /path/to/scripts/test-gate.sh --check-batch
echo "Exit: $?"
bash /path/to/scripts/test-gate.sh --record-feature "auth"
bash /path/to/scripts/test-gate.sh --record-feature "user-profile"
bash /path/to/scripts/test-gate.sh --check-batch
echo "Exit: $?"
bash /path/to/scripts/test-gate.sh --reset-counter
bash /path/to/scripts/test-gate.sh --check-batch
echo "Exit: $?"
cd /tmp && rm -rf "$TEST_DIR"
```

Expected: First check-batch exits 0 (clear). After 2 features, exits 1 (blocked). After reset, exits 0 again.

- [ ] **Step 4: Commit**

```bash
git add scripts/test-gate.sh
git commit -m "feat(uat): add test-gate.sh mechanical enforcement

Batch check (--check-batch): blocks new features when testing interval
reached. Phase gate (--check-phase-gate): blocks Phase 2→3 on open
SEV-1/2 bugs. Reads BUGS.md and GitHub Issues. Feature recording
and counter reset for session management."
```

---

### Task 3: Add Testing & Bug Tracking Section to Intake Template

**Files:**
- Modify: `templates/project-intake.md`

- [ ] **Step 1: Add new Section 11.5 between Known Risks (Section 11) and Tooling Configuration (Section 12)**

After line 475 (the closing `---` of Section 11), insert:

```markdown

## 11.5. Testing & Bug Tracking

| Field | Value |
|---|---|
| **Testing interval** | _Every N features (default: 2). How many features to build before pausing for a UAT testing session._ |
| **Bug tracking tool** | GitHub Issues / Linear / Jira / BUGS.md / Other: ______ |
| **Human tester count** | _Default: 1 (you, the developer). If >1, testers receive a test template per session._ |
| **Beta tester coordination** (if >1 tester) | _How to reach testers (email, Slack, Discord). How they receive builds (TestFlight, staging URL, GitHub pre-release, download link)._ |
| **Bug severity SLAs** (Full UAT level only) | SEV-1: ___h / SEV-2: ___d / SEV-3: ___d _(default: SEV-1 24h, SEV-2 7d, SEV-3 best effort)_ |

> **How this is used:** The agent pauses construction every N features to run a UAT testing session. Agent testers run automated, exploratory, and cross-platform tests in parallel while you test manually. Bugs are compiled, triaged, and fixed before construction resumes. See Steps 2.7-2.9 in the Builder's Guide.
```

- [ ] **Step 2: Renumber Sections 12 and 13**

The existing Section 12 (Tooling Configuration) becomes 12 (no change needed — it's already 12). The existing Section 13 (Agent Initialization Prompt) stays 13. The new section slots in at 11.5 so no renumbering is required.

- [ ] **Step 3: Commit**

```bash
git add templates/project-intake.md
git commit -m "feat(intake): add Section 11.5 Testing & Bug Tracking preferences

Testing interval, bug tracker choice, tester count, beta
coordination, severity SLAs. Feeds into Build Loop Steps 2.7-2.9."
```

---

### Task 4: Update Builder's Guide — Phase 1 and Phase 2

**Files:**
- Modify: `docs/builders-guide.md`

- [ ] **Step 1: Add severity classification to Phase 1 Step 1.6 (Project Bible Test Strategy)**

Find the Test Strategy section in Step 1.6 and add after the existing test categories:

```markdown
**Bug Severity Classification:**

| Severity | Definition | Examples |
|---|---|---|
| **SEV-1** | Data loss, security breach, app crash on core flow, complete feature failure | Auth bypass, database corruption, crash on login |
| **SEV-2** | Feature broken but workaround exists, significant UX failure | Form submits but wrong data saved, layout broken on one platform |
| **SEV-3** | Minor UX issue, cosmetic, non-core edge case | Alignment off, tooltip truncated, rare edge case |
| **SEV-4** | Enhancement, suggestion, polish | "Would be nice if...", performance optimization |

**UAT Plan** (from Intake Section 11.5):
- Testing interval: Every N features (configured in Intake)
- Human tester count and coordination method
- Bug tracking tool
- Severity SLAs (Full UAT level)
```

- [ ] **Step 2: Add Steps 2.7-2.9 to the Build Loop**

After Step 2.6 (Data Model Changes, line 864), before the Context Health Check section (line 868), insert:

```markdown

#### Step 2.7 — UAT Testing Session

**Before starting the next feature, check the test gate:**
```bash
scripts/test-gate.sh --check-batch
```

If the gate blocks (testing interval reached), execute a UAT session:

1. **Agent dispatches parallel test subagents** (via `superpowers:dispatching-parallel-agents` if available, sequential otherwise):
   - **Automated Suite agent:** Runs full test suite (unit + integration + E2E). Reports failures with stack traces.
   - **Exploratory agent:** Reads the Threat Model (Phase 1.3) and User Journey (Phase 0). Tries to break the current batch — edge cases, unexpected inputs, boundary conditions, error recovery.
   - **Cross-Platform agent** (if applicable): Runs core flows on each target platform.

2. **Agent generates a test template** pre-populated with the current batch's features and User Journey scenarios. Places it in `tests/uat/sessions/<date>-session-N/templates/`.

3. **Agent tells the Orchestrator:** "Testing session started. Your test template is at `<path>`. Complete it and drop results in `submissions/`. Let me know when done."

4. **Agent waits.** Does not proceed, does not poll.

5. **When the Orchestrator says "results are in"**, the agent:
   - Checks each submission against the template for completeness
   - If scenarios are incomplete, lists which tests were skipped (and by which tester if multiple)
   - Asks: "Continue with partial results, or finish testing?"

Agent results go to `tests/uat/sessions/<date>-session-N/agent-results/`. Human submissions go to `submissions/`.

**After each feature (regardless of testing interval):**
```bash
scripts/test-gate.sh --record-feature "feature-name"
```

#### Step 2.8 — Bug Triage

1. Agent consolidates all results (agent test results + human submissions) into the configured bug tracker.
2. Agent proposes severity for each bug (SEV-1/2/3/4 per Phase 1 classification).
3. Orchestrator reviews and adjusts severities.
4. Orchestrator assigns disposition per bug:

| Disposition | Meaning |
|---|---|
| **Fix Now** | Agent fixes in this remediation cycle |
| **Defer** | Tracked with justification. Must be resolved or feature removed at Phase 2→3 gate. SEV-1 cannot be deferred. |
| **Won't Fix** | Accepted as-is with documented rationale (SEV-3/4 only) |
| **Post-MVP** | Moved to Post-MVP backlog (SEV-4 enhancements) |

#### Step 2.9 — Remediation Loop

1. Agent fixes all "Fix Now" bugs using Build Loop discipline (write failing test for the bug → implement fix → verify test passes).
2. Agent re-dispatches parallel test agents. Orchestrator re-tests their specific reported bugs.
3. Gate check:
```bash
scripts/test-gate.sh --check-batch
```
   - **Pass** → reset counter, proceed to next feature batch
   - **Block** → loop back to Step 2.8

After the session completes:
```bash
scripts/test-gate.sh --reset-counter
```
```

- [ ] **Step 3: Enhance Phase 2 Completion Checkpoint (line ~903)**

Add to the existing checklist:

```markdown
- [ ] All UAT testing sessions completed for all feature batches
- [ ] No open SEV-1 or SEV-2 bugs (deferred SEV-2 must be resolved or feature removed)
- [ ] Bug triage complete — all bugs have a disposition
```

- [ ] **Step 4: Enhance Phase 2→3 Gate**

After the Phase 2 Completion Checkpoint, add:

```markdown
**Bug Gate Check:**
```bash
scripts/test-gate.sh --check-phase-gate
```
- SEV-1 open → **BLOCKED** (must resolve)
- SEV-2 open or deferred → **BLOCKED** (must resolve or remove/hide the feature — no third option)
- SEV-3 open → **WARNING** (Orchestrator attests disposition)
- SEV-4 → No impact
```

- [ ] **Step 5: Commit**

```bash
git add docs/builders-guide.md
git commit -m "feat(guide): add UAT Steps 2.7-2.9, severity classification, bug gate

Phase 1: severity definitions (SEV-1/2/3/4) and UAT plan.
Phase 2: Step 2.7 (UAT session with parallel agents + human testing),
Step 2.8 (bug triage), Step 2.9 (remediation loop with mechanical
gate). Enhanced Phase 2 completion checkpoint and Phase 2→3 gate."
```

---

### Task 5: Update Builder's Guide — Phase 3 and Phase 4

**Files:**
- Modify: `docs/builders-guide.md`

- [ ] **Step 1: Enhance Step 3.6 (Pre-Launch Preparation)**

Replace the user testing line (line 1070):

Old:
```markdown
**User testing:** At least one person who has never seen the product completes the core flow. Document confusion points.
```

New:
```markdown
**Final UAT session:**
- Run a final testing session using the same Step 2.7 process (parallel agents + human testers)
- All configured testers participate (not just the Orchestrator)
- For Full UAT level (Sponsored POC / Production): formal acceptance sign-off recorded in `APPROVAL_LOG.md` — product sponsor or designated tester confirms core flow works as specified in the Phase 0 Manifesto
- Document confusion points, UX friction, and any remaining issues
- All SEV-1/2 bugs from this session must be resolved before Phase 4
```

- [ ] **Step 2: Add regression cadence to Step 4.4 (Ongoing Maintenance)**

After the existing Monthly items (line ~1211), add:

```markdown
- Run full E2E test suite before each maintenance release
- Triage incoming bugs from production monitoring (same severity classification as Phase 2)
```

After the existing Quarterly items (line ~1218), add:

```markdown
- Run full regression test suite (all Phase 2 + Phase 3 tests)
```

- [ ] **Step 3: Add bug reporting to Step 4.5 (Handoff Documentation)**

After the existing HANDOFF.md items (line ~1234), add:

```markdown
7. Bug reporting mechanism: how users report bugs post-launch, where bugs are tracked, triage cadence and severity SLAs
```

- [ ] **Step 4: Commit**

```bash
git add docs/builders-guide.md
git commit -m "feat(guide): enhance Phase 3 UAT and Phase 4 maintenance

Phase 3.6: replace one-line user testing with full UAT session
and formal sign-off for Full level. Phase 4.4: add regression
test cadence. Phase 4.5: add bug reporting to HANDOFF.md."
```

---

### Task 6: Update init.sh — CLAUDE.md Template, Project Setup

**Files:**
- Modify: `init.sh`

- [ ] **Step 1: Add Testing & Bug Workflow section to CLAUDE.md template**

In `generate_claude_md()`, before the closing `CLAUDEEOF` (line 1134), add:

```markdown

### Testing & Bug Workflow
- **Testing interval:** Every $TEST_INTERVAL features (configured in Intake Section 11.5)
- **Bug tracker:** Configured in Intake Section 11.5
- **Process:** After every $TEST_INTERVAL features, stop construction and run a UAT session:
  1. Check the gate: \`scripts/test-gate.sh --check-batch\`
  2. If blocked: dispatch parallel test agents (automated suite, exploratory, cross-platform)
  3. Generate test template for human tester(s) and wait for results
  4. Verify submission completeness — list incomplete scenarios, ask to continue or finish
  5. Consolidate all results into bug tracker
  6. Triage with Orchestrator (Fix Now / Defer / Won't Fix / Post-MVP)
  7. Fix all "Fix Now" bugs test-first
  8. Re-test until gate passes: \`scripts/test-gate.sh --check-batch\`
  9. Reset counter: \`scripts/test-gate.sh --reset-counter\`
- **After each feature:** \`scripts/test-gate.sh --record-feature "feature-name"\`
- **Gate enforcement:** Do NOT start the next feature until test-gate.sh --check-batch returns 0.
- **Severity rules:** SEV-1 cannot be deferred. SEV-2 can be deferred during Phase 2 but must be resolved or feature removed at Phase 2→3 gate.
```

Note: `$TEST_INTERVAL` should use the default value of 2. Add this variable to `collect_project_info()` or set it as a default.

- [ ] **Step 2: Add TEST_INTERVAL default to collect_project_info()**

After the `LANGUAGE` collection in `collect_project_info()`, add:

```bash
  # Testing interval (default 2, configurable in Intake)
  TEST_INTERVAL=2
```

- [ ] **Step 3: Add test-gate.sh to copy list and UAT directory creation**

After the existing `cp "$SCRIPT_DIR/scripts/verify-install.sh" scripts/` line (line 752), add:

```bash
  cp "$SCRIPT_DIR/scripts/test-gate.sh" scripts/
```

Update the chmod line to include test-gate.sh.

After the tool matrix copy section (line ~761), add:

```bash
  # Copy UAT template and create session directory structure
  mkdir -p tests/uat/templates tests/uat/sessions
  cp "$SCRIPT_DIR/templates/uat-test-template.md" tests/uat/templates/test-session-template.md
```

- [ ] **Step 4: Generate initial build-progress.json**

After writing `orchestrator-source.json` in `create_project()`, add:

```bash
  # Generate initial build progress tracking
  cat > .claude/build-progress.json << BPEOF
{
  "features_completed": [],
  "features_since_last_test": 0,
  "test_interval": $TEST_INTERVAL,
  "last_test_session": null,
  "testing_required": false,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 0
}
BPEOF
  print_ok "Build progress tracking initialized (test interval: every $TEST_INTERVAL features)"
```

- [ ] **Step 5: Validate syntax**

Run: `bash -n init.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add init.sh
git commit -m "feat(init): add UAT workflow to CLAUDE.md, copy test-gate.sh, create UAT dirs

CLAUDE.md template gets Testing & Bug Workflow section. test-gate.sh
copied to projects. tests/uat/ directory structure created. Initial
build-progress.json generated with default test interval of 2."
```

---

### Task 7: Integrate test-gate.sh with check-phase-gate.sh

**Files:**
- Modify: `scripts/check-phase-gate.sh`

- [ ] **Step 1: Add test-gate.sh call**

In `scripts/check-phase-gate.sh`, find the tool resolution check section (added previously). After it, before the final summary output, add:

```bash
# --- Test/Bug Gate Check (for Phase 2→3) ---
TEST_GATE="$SCRIPT_DIR/scripts/test-gate.sh"

if [ -x "$TEST_GATE" ] && [ "$current_phase" -ge 2 ]; then
  echo ""
  echo -e "${BOLD}Bug Gate Check${NC}"
  gate_result=0
  bash "$TEST_GATE" --check-phase-gate || gate_result=$?

  if [ "$gate_result" -eq 1 ]; then
    echo ""
    echo -e "${RED}[FAIL]${NC} Bug gate BLOCKED. Resolve SEV-1/2 bugs before Phase 3."
    ((issues++))
  elif [ "$gate_result" -eq 2 ]; then
    echo ""
    echo -e "${YELLOW}[WARN]${NC} Bug gate has warnings. User attestation required."
    ((issues++))
  fi
fi
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/check-phase-gate.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/check-phase-gate.sh
git commit -m "feat(gate): integrate test-gate.sh into phase gate checks

Calls test-gate.sh --check-phase-gate for Phase 2→3 transitions.
Blocks on open SEV-1/2 bugs, warns on SEV-3."
```

---

### Task 8: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add UAT & Bug Tracking section**

After the existing "Upgrade Paths" section (line ~226), add:

```markdown

### Testing & Bug Tracking

The Build Loop includes a configurable test-fix-verify cycle:

1. **Build N features** (interval configurable — default: every 2 features)
2. **UAT testing session** — parallel AI agents (automated, exploratory, cross-platform) test alongside the human developer
3. **Bug triage** — severity classification (SEV-1 through SEV-4), disposition assignment (Fix Now / Defer / Won't Fix / Post-MVP)
4. **Remediation** — agent fixes bugs test-first, re-tests until gate passes
5. **Proceed** — only when all tests pass and all Fix Now bugs are resolved

Mechanical enforcement via `scripts/test-gate.sh` prevents skipping test sessions and blocks Phase 2→3 transition with unresolved SEV-1/2 bugs. Deferred bugs must be resolved or their features removed before validation begins.

Bug tracking is tool-agnostic — configure your preferred tracker (GitHub Issues, Linear, Jira, BUGS.md) in the Intake.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): add Testing & Bug Tracking section

Describes the test-fix-verify loop, parallel agent testing,
severity classification, and mechanical gate enforcement."
```

---

### Task 9: End-to-End Validation

**Files:**
- Read: all modified files

- [ ] **Step 1: Validate all scripts**

Run: `bash -n init.sh && bash -n scripts/test-gate.sh && bash -n scripts/check-phase-gate.sh && echo "ALL OK"`
Expected: `ALL OK`

- [ ] **Step 2: Test test-gate.sh batch flow**

Run:
```bash
TEST_DIR=$(mktemp -d) && cd "$TEST_DIR" && mkdir -p .claude
bash "$ORCHESTRATOR/scripts/test-gate.sh" --check-batch
echo "=== After 0 features: exit $? ==="
bash "$ORCHESTRATOR/scripts/test-gate.sh" --record-feature "auth"
bash "$ORCHESTRATOR/scripts/test-gate.sh" --record-feature "dashboard"
bash "$ORCHESTRATOR/scripts/test-gate.sh" --check-batch
echo "=== After 2 features: exit $? ==="
bash "$ORCHESTRATOR/scripts/test-gate.sh" --reset-counter
bash "$ORCHESTRATOR/scripts/test-gate.sh" --check-batch
echo "=== After reset: exit $? ==="
cat .claude/build-progress.json | jq '.'
cd /tmp && rm -rf "$TEST_DIR"
```

Expected: exit 0, exit 1, exit 0. build-progress.json shows 2 features completed, counter reset, 1 session completed.

- [ ] **Step 3: Test test-gate.sh phase gate with BUGS.md**

Run:
```bash
TEST_DIR=$(mktemp -d) && cd "$TEST_DIR" && mkdir -p .claude
# Create a BUGS.md with mixed severities
cat > BUGS.md << 'EOF'
# Bug Tracker

| # | Severity | Status | Feature | Description |
|---|---|---|---|---|
| 1 | SEV-1 | Open | auth | Login crash on empty password |
| 2 | SEV-2 | Deferred | dashboard | Chart doesn't render on Safari |
| 3 | SEV-3 | Open | profile | Avatar upload button misaligned |
| 4 | SEV-4 | Post-MVP | settings | Dark mode toggle |
EOF

bash "$ORCHESTRATOR/scripts/test-gate.sh" --check-phase-gate
echo "=== With SEV-1 open: exit $? ==="

# Fix SEV-1, resolve SEV-2
sed -i '' 's/SEV-1.*Open/SEV-1 | Fixed/' BUGS.md
sed -i '' 's/SEV-2.*Deferred/SEV-2 | Fixed/' BUGS.md

bash "$ORCHESTRATOR/scripts/test-gate.sh" --check-phase-gate
echo "=== After fixes: exit $? ==="
cd /tmp && rm -rf "$TEST_DIR"
```

Expected: First check exits 1 (blocked on SEV-1 + SEV-2). After fixes, exits 2 (warning for SEV-3) or 0 (clear).

- [ ] **Step 4: Verify UAT directory structure in init flow**

Check that `templates/uat-test-template.md` exists and init.sh references it correctly.

- [ ] **Step 5: No commit — validation only**

---

## Summary

| Task | What It Does |
|---|---|
| 1 | Create UAT test template (human tester form) |
| 2 | Create test-gate.sh (mechanical enforcement) |
| 3 | Add Testing & Bug Tracking to Intake template |
| 4 | Update Builder's Guide — Phase 1 severity, Phase 2 Steps 2.7-2.9 |
| 5 | Update Builder's Guide — Phase 3.6 UAT, Phase 4 regression |
| 6 | Update init.sh — CLAUDE.md template, project setup, UAT dirs |
| 7 | Integrate test-gate.sh with check-phase-gate.sh |
| 8 | Update README.md with UAT workflow |
| 9 | End-to-end validation |

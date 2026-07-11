# UAT, Bug Tracking & Test-Fix-Verify Loop — Design Spec

## Date: 2026-04-03

## Problem

The Solo Orchestrator Build Loop (Phase 2) has no structured pause point for user testing. The Orchestrator builds feature after feature with automated tests and security scans, but never formally stops to let humans test the running application, report bugs, and verify fixes before moving on. Phase 3's UAT is a single sentence: "at least one person completes the core flow."

Additionally, there is no bug tracking workflow — no severity classification, no triage process, no mechanical gate that prevents advancing with unresolved critical bugs, and no way for the user to defer a problematic feature without blocking the entire project.

## Solution

A test-fix-verify loop integrated into the Build Loop with:
- Configurable testing intervals (user decides how many features between sessions)
- Parallel agent testing alongside human manual testing
- Structured bug tracking with severity classification
- Mechanical gate enforcement (script-based) with a defer option
- Phase 2→3 gate that forces deferred bugs to be resolved or their features removed

## Architecture

Testing sessions are triggered at user-configured intervals. When triggered, the orchestrating agent dispatches parallel subagents for automated/exploratory/cross-platform testing while the human tests manually. Results are compiled, triaged, and remediated in a loop that only exits when the mechanical gate passes. Bug tracking is tool-agnostic — the framework defines the workflow, the user picks the tool.

---

## 1. UAT Levels by Deployment Type

| Deployment | UAT Level | What It Means |
|---|---|---|
| **Personal** | Standard | Orchestrator self-tests using generated template, bugs in chosen tracker, acceptance per Must-Have feature |
| **POC Private** | Standard | Same as Personal |
| **POC Sponsored** | Full | Structured beta (5-20 testers), severity SLAs, formal sign-off from sponsor |
| **Production** | Full | Same as Sponsored POC |

The default is 1 human tester (the developer themselves). The Intake allows selecting more. Regardless of tester count, the same folder structure and process applies.

---

## 2. Testing Session Configuration

Captured in Intake Section 11: Testing & Bug Tracking.

### Intake Fields

| Field | Default | Options |
|---|---|---|
| **Testing interval** | Every 2 features | User configurable (1-10) |
| **Bug tracking tool** | GitHub Issues | GitHub Issues / Linear / Jira / BUGS.md / Other |
| **Human tester count** | 1 (the developer) | 1-20 |
| **Beta tester coordination** (if >1) | N/A | How to reach testers, how they receive builds |
| **Bug severity SLAs** (Full level only) | SEV-1: 24h, SEV-2: 1 week | Configurable per severity |

### Stored in Project

`.claude/build-progress.json`:
```json
{
  "features_completed": ["auth", "user-profile"],
  "features_since_last_test": 2,
  "test_interval": 2,
  "last_test_session": "2026-04-10",
  "testing_required": true,
  "tester_count": 1,
  "bug_tracker": "github_issues",
  "sessions_completed": 1
}
```

CLAUDE.md's "Testing & Bug Workflow" section tells the agent the configured interval and process.

---

## 3. Testing Session Flow

When `features_since_last_test >= test_interval`, the mechanical gate blocks new feature construction. The following loop executes:

### Step 1: TESTING (Parallel)

The orchestrating agent:
1. Generates a test template pre-populated with the current batch's features and User Journey scenarios
2. Places it in `tests/uat/sessions/<date>-session-N/templates/`
3. Dispatches parallel subagents via `superpowers:dispatching-parallel-agents`:

| Agent | Responsibility | Output Location |
|---|---|---|
| **Automated Suite** | Runs full test suite (unit + integration + E2E). Reports failures with stack traces. | `agent-results/automated-suite.md` |
| **Exploratory** | Reads Threat Model (Phase 1.3) and User Journey (Phase 0). Tries to break features — edge cases, unexpected inputs, boundary conditions, error recovery. | `agent-results/exploratory.md` |
| **Cross-Platform** (if applicable) | Runs core flows on each target platform. Web: multiple browsers. Mobile: iOS + Android. Desktop: each target OS. | `agent-results/cross-platform.md` |

4. Tells the user: "Testing session started. Your test template is at `<path>`. Complete it and drop results in `submissions/`. Let me know when done."
5. Waits — does not proceed, does not poll

**Without Superpowers:** The agent runs the tests sequentially in the same session. Same results, slower. The framework works either way.

### Step 2: USER COMPLETES TESTING

The user (and any additional testers) fill out the template and drop results in:
```
tests/uat/sessions/<date>-session-N/submissions/
  tester-1.md
  tester-2.md   (if multiple testers)
```

When the user says "results are in", the agent:
1. Checks each submission against the template for completeness
2. If scenarios are incomplete, lists which tests were skipped and by which tester
3. Asks: "Continue with partial results, or finish testing?"

### Step 3: BUG COMPILATION

Agent consolidates:
- Agent test results (from `agent-results/`)
- Human submissions (from `submissions/`)
- Into a single consolidated report at `tests/uat/sessions/<date>-session-N/consolidated.md`
- And into the chosen bug tracker (BUGS.md, GitHub Issues, etc.)

### Step 4: TRIAGE

1. Agent proposes severity for each bug (SEV-1/2/3/4 per definitions in Section 4)
2. User reviews and adjusts severities
3. User assigns disposition per bug:

| Disposition | Meaning |
|---|---|
| **Fix Now** | Agent fixes in this cycle |
| **Defer** | Track with justification. Must be resolved or feature removed at Phase 2→3 gate. |
| **Won't Fix** | Accepted as-is with documented rationale |
| **Post-MVP** | Moved to Post-MVP backlog (SEV-4 enhancements) |

### Step 5: REMEDIATION

Agent fixes all "Fix Now" bugs using Build Loop discipline (test-first: write failing test for the bug, implement fix, verify test passes).

### Step 6: RE-TEST

Agent re-dispatches the same parallel test agents. User re-tests their specific reported bugs. Agent verifies:
- All automated tests pass
- All "Fix Now" bugs are verified resolved

### Step 7: GATE CHECK

`test-gate.sh --check-batch`:
- All automated tests pass AND all "Fix Now" bugs resolved → **PASS** → proceed to next feature batch
- Any failures remain → **BLOCK** → loop back to Step 5

---

## 4. Bug Severity Classification

Defined in Phase 1 (Project Bible Test Strategy), used consistently through Phase 4:

| Severity | Definition | Examples |
|---|---|---|
| **SEV-1** | Data loss, security breach, app crash on core flow, complete feature failure | Auth bypass, database corruption, crash on login |
| **SEV-2** | Feature broken but workaround exists, significant UX failure | Form submits but wrong data saved, layout broken on one platform |
| **SEV-3** | Minor UX issue, cosmetic, non-core edge case | Alignment off by a few pixels, tooltip truncated, rare edge case |
| **SEV-4** | Enhancement, suggestion, polish | "Would be nice if...", performance optimization, cosmetic improvement |

### Rules During Phase 2

| Severity | Can Defer? | Can Won't Fix? |
|---|---|---|
| SEV-1 | No — must fix immediately | No |
| SEV-2 | Yes — with justification | No (must fix or defer) |
| SEV-3 | Yes | Yes — with documented rationale |
| SEV-4 | Automatic — goes to Post-MVP backlog | Yes |

---

## 5. Mechanical Gate: test-gate.sh

### Location

`scripts/test-gate.sh`

### Interface

```bash
scripts/test-gate.sh --check-batch        # Can I start the next feature?
scripts/test-gate.sh --check-phase-gate   # Can I transition Phase 2→3?
scripts/test-gate.sh --help
```

### Batch Check (`--check-batch`)

Reads `.claude/build-progress.json`:
- If `features_since_last_test < test_interval` → exit 0 (continue building)
- If `features_since_last_test >= test_interval` → exit 1 (testing session required)

After a testing session completes, the agent resets `features_since_last_test` to 0 and updates `last_test_session`.

### Phase Gate Check (`--check-phase-gate`)

Reads the bug tracker (BUGS.md parsed, or GitHub Issues via `gh` CLI):
- Any open SEV-1? → **exit 1** (BLOCK — must resolve)
- Any open or deferred SEV-2? → **exit 1** (BLOCK — must resolve or remove/hide feature)
- Any open SEV-3? → **exit 2** (WARN — user attestation required)
- Open SEV-4 or deferred SEV-3? → **exit 0** (no impact, informational)

### Exit Codes

| Code | Meaning |
|---|---|
| 0 | Clear to proceed |
| 1 | Blocked — SEV-1/2 unresolved (mechanical, cannot override) |
| 2 | Warnings — SEV-3 needs user attestation |

### Phase 2→3 Deferred Bug Resolution

When `--check-phase-gate` finds deferred SEV-2 bugs, it presents two options per bug:

| Option | What Happens |
|---|---|
| **Resolve** | Fix the bug, re-test, verify it passes |
| **Remove** | Disable/hide the feature entirely — feature flag, remove from UI, or delete code. Feature moves to Post-MVP backlog. Does not ship. |

No third option. Known SEV-2 bugs cannot be carried into validation.

---

## 6. UAT Directory Structure

```
tests/uat/
  templates/
    test-session-template.md        ← master template (copied from orchestrator)
  sessions/
    2026-04-10-session-1/
      templates/
        test-template.md            ← pre-populated for this batch's features
      submissions/
        tester-1.md                 ← human tester results (1 per tester)
      agent-results/
        automated-suite.md          ← full test suite results
        exploratory.md              ← edge case / threat model testing
        cross-platform.md           ← platform-specific results (if applicable)
      consolidated.md              ← agent-compiled summary of all results
    2026-04-15-session-2/
      ...
```

The agent generates fresh session directories. Templates are pre-populated with the current feature batch. The structure is the same whether there's 1 tester or 20.

---

## 7. Test Session Template

`templates/uat-test-template.md` — the master template copied to projects. Per-session copies are pre-populated by the agent with actual feature names and scenarios.

Structure:
```markdown
# UAT Test Session — [Session Number]

**Date:** [auto-filled]
**Features under test:** [auto-filled from build-progress.json]
**Tester:** [tester fills in their name]

## Test Scenarios

### Feature: [Feature Name]

| # | Scenario | Steps | Expected Result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| 1 | [from User Journey] | [steps] | [expected] | | |
| 2 | [error case] | [steps] | [expected error handling] | | |

### Feature: [Feature Name]
...

## Bugs Found

| # | Severity | Feature | Description | Steps to Reproduce | Expected vs Actual |
|---|---|---|---|---|---|
| 1 | | | | | |

## Overall Notes

[Free-form observations, UX concerns, suggestions]
```

---

## 8. Phase-by-Phase Integration

### Phase 0 — No changes
Feature acceptance criteria already captured in Intake Section 4.1 (Must-Have features with triggers and failure states). These become the basis for UAT test scenarios generated by the agent.

### Phase 1 — Two additions

**Step 1.6 (Project Bible) Test Strategy section additions:**
- UAT plan: testing interval, tester count, beta infrastructure needed, bug tracking tool (from Intake Section 11)
- Bug severity classification (SEV-1/2/3/4) defined and documented
- Regression testing strategy

### Phase 2 — Three new steps in the Build Loop

After Step 2.6 (Data Model Changes), before next feature:

**Step 2.7: UAT Testing Session**
1. `test-gate.sh --check-batch` determines if testing is due
2. If due: agent dispatches parallel test agents, generates human test template, waits for user
3. User completes testing, drops results in submissions folder
4. Agent verifies completeness (prompts if incomplete)

**Step 2.8: Bug Triage**
1. Agent consolidates all results (agent + human) into bug tracker
2. Agent proposes severities
3. User reviews, adjusts, assigns disposition (Fix Now / Defer / Won't Fix / Post-MVP)

**Step 2.9: Remediation Loop**
1. Agent fixes "Fix Now" bugs (test-first)
2. Re-dispatches test agents + user re-tests
3. `test-gate.sh --check-batch` verifies all clear
4. If not clear → loop back to remediation
5. If clear → reset feature counter, proceed to next batch

### Phase 2→3 Gate — Enhanced

`check-phase-gate.sh` calls `test-gate.sh --check-phase-gate`:
- SEV-1/2 open or deferred: **mechanical block**
- For each deferred SEV-2: user must choose **Resolve** or **Remove/hide feature**
- SEV-3: user attestation
- All clear → gate passes

### Phase 3 — One enhancement

**Step 3.6 (Pre-Launch) updated:**
- Replace "at least one person completes core flow" with: "Final UAT session with all configured testers. Full regression run. For Full UAT level: formal sign-off recorded in APPROVAL_LOG.md."

### Phase 4 — Two additions

**Step 4.4 maintenance cadence additions:**
- Regression test schedule: run full E2E suite before each maintenance release
- Bug triage cadence: review incoming bugs from production monitoring on the same cadence as error dashboard review

**HANDOFF.md additions:**
- How users report bugs post-launch
- Where bugs are tracked
- Triage cadence and severity SLAs

---

## 9. CLAUDE.md Integration

The CLAUDE.md template in `init.sh` gets a new "Testing & Bug Workflow" section:

```markdown
### Testing & Bug Workflow
- **Testing interval:** Every [N] features (configured in Intake Section 11)
- **Bug tracker:** [tool] (configured in Intake Section 11)
- **Human tester count:** [N]
- **Process:** After every [N] features, stop construction and run a UAT session:
  1. Dispatch parallel test agents (automated suite, exploratory, cross-platform)
  2. Generate test template for human tester(s) and wait for results
  3. Verify submission completeness
  4. Consolidate all results into bug tracker
  5. Triage with Orchestrator (Fix Now / Defer / Won't Fix / Post-MVP)
  6. Fix all "Fix Now" bugs test-first
  7. Re-test until test-gate.sh passes
  8. Only then proceed to next feature batch
- **Gate enforcement:** Do NOT start the next feature until test-gate.sh --check-batch returns 0
- **Severity:** SEV-1 cannot be deferred. SEV-2 can be deferred but must be resolved or feature removed at Phase 2→3 gate.
```

---

## 10. File Inventory

### New Files

| File | Purpose |
|---|---|
| `scripts/test-gate.sh` | Mechanical gate — batch interval check and phase gate bug status check |
| `templates/uat-test-template.md` | Master test session template for human testers |

### Modified Files

| File | Change |
|---|---|
| `docs/builders-guide.md` | Add Steps 2.7-2.9 to Build Loop, enhance Phase 1 test strategy, enhance Phase 2→3 gate, enhance Phase 3.6, add Phase 4 regression cadence |
| `templates/project-intake.md` | Add Section 11: Testing & Bug Tracking preferences |
| `init.sh` | Copy test-gate.sh and UAT template, generate `tests/uat/` directory, add CLAUDE.md testing workflow section, generate initial build-progress.json |
| `scripts/check-phase-gate.sh` | Call test-gate.sh --check-phase-gate as part of gate checks |
| `README.md` | Document UAT workflow, bug tracking, testing sessions |

### Generated Per-Project Files

| File | Purpose |
|---|---|
| `.claude/build-progress.json` | Tracks feature count, test interval, session history |
| `tests/uat/templates/test-session-template.md` | Copied from orchestrator master template |
| `tests/uat/sessions/` | Per-session directories (created during Phase 2) |
| `BUGS.md` (if selected as tracker) | Structured bug tracking file |

---

## 11. What Does NOT Change

- **Tool matrix and resolver** — unrelated to testing workflow
- **Existing CI/CD pipeline** — automated tests already run there; UAT is complementary, not a replacement
- **Existing security scanning** — Phase 2.4 and Phase 3.2 unchanged
- **Phase 0 artifacts** — acceptance criteria already in Intake Section 4.1
- **Existing Phase 2 Steps 2.2-2.6** — unchanged; Steps 2.7-2.9 are additions after 2.6

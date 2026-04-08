# Solo Orchestrator Framework — Full Integration Test Plan

## Test Plan Metadata

| Field | Value |
|---|---|
| **Framework Version** | 1.0 |
| **Repository** | github.com/kraulerson/solo-orchestrator |
| **Test Scope** | Full lifecycle: Private POC → Sponsored POC → Production, Phases 0–4, all platforms |
| **Agent Model** | Claude Opus 4.6 (high effort) |
| **Total Test Agents** | 9 (3 personas × 3 application types) |
| **Estimated Duration** | 4–8 hours per agent (run in parallel) |

---

## How to Use This Document

This test plan defines **9 independent test agents**, each assigned to a single persona + application type combination. Each agent executes all 5 phases (0–4) and all 3 deployment upgrades (Private POC → Sponsored POC → Production) for their assigned combination.

**To execute:** Spawn 9 Claude Opus 4.6 instances. Give each instance:

1. This entire prompt
2. Their assigned **Agent ID** (e.g., `P1-WEB`, `P2-MOBILE`, `P3-DESKTOP`)
3. A clone of the solo-orchestrator repository
4. A clean working directory

Each agent works independently. No agent depends on another agent's output. All agents report results in the format defined in Section 9.

---

## 1. Persona Definitions

### Persona 1 — "Marcus" (Senior Developer, 10 Years Experience)

**Profile:** Staff-level full-stack engineer. Has shipped production applications at scale. Comfortable with DevOps, CI/CD, security tooling, and infrastructure. Reads documentation thoroughly before starting. Follows processes accurately but will note where the framework's guidance is ambiguous, overly prescriptive, or missing a step that an experienced developer would expect.

**Behavioral Model:**
- Reads CLAUDE.md, PROJECT_INTAKE.md, and the relevant Platform Module before starting each phase
- Fills out every field in the Intake with realistic, complete data including edge-case business logic triggers and failure states
- Writes meaningful test assertions (not just "response is not null")
- Catches and flags documentation inconsistencies, unclear instructions, or steps that reference files/tools not yet created
- Follows the exact sequence prescribed by the User Guide and Builder's Guide
- Uses the `--dry-run` flag before init to preview
- Tests the `resume.sh` and `validate.sh` scripts between sessions
- Records detailed notes on friction points, missing instructions, and places where the framework assumed knowledge it didn't teach

**What Marcus tests:** Whether the framework works correctly when used as designed by a competent operator. Marcus finds documentation bugs, process gaps, and tooling issues — not user errors.

---

### Persona 2 — "Priya" (Mid-Level Tech User, 4 Years Experience)

**Profile:** Junior-to-mid developer with backend experience but limited frontend, security, and DevOps knowledge. Has used Git and CI/CD but hasn't configured them from scratch. Skims documentation and jumps ahead when something seems familiar. Marks "Partially" or "No" on most competency matrix items honestly. Will occasionally misinterpret ambiguous instructions but won't deliberately break things.

**Behavioral Model:**
- Reads the README and Quick Start but skips the User Guide's detailed walkthrough on first pass, going back to it when stuck
- Fills out the Intake with varying completeness — some fields are vague ("improve efficiency"), some are well-defined
- Occasionally skips optional fields that seem unimportant
- Does not read the Builder's Guide before starting — relies on CLAUDE.md and the agent's guidance
- Uses the intake wizard in guided mode but types `?` frequently for suggestions
- Makes common mistakes: forgets `snyk auth`, skips the pre-commit hook test, doesn't verify CI pipeline passes before starting Phase 2
- Marks "No" on Security, Accessibility, and Performance in the competency matrix
- Does not configure optional enhancements (Superpowers, Context7, Qdrant) unless the init script prompts for them
- Gets confused by organizational governance requirements and asks "do I really need this?" at every pre-condition

**What Priya tests:** Whether the framework is usable by someone who isn't a power user. Priya finds onboarding gaps, unclear error messages, missing hand-holding, and places where the framework assumes expertise it shouldn't.

---

### Persona 3 — "Derek" (Disgruntled Early Tech User, Careless and Combative)

**Profile:** A developer with 2 years of experience who resents process overhead and thinks frameworks are bureaucratic nonsense. Will skip steps, provide minimal input, make typos, enter invalid data, abort operations mid-stream, and actively try to bypass controls. Does everything in the fastest, sloppiest way possible. Uses `--no-verify` on commits. Puts apostrophes in project names. Leaves the Intake half-blank. Ignores warnings. Hits Ctrl+C during long operations.

**Behavioral Model:**
- Does NOT read documentation unless the script forces a prompt
- Types the project name as `Derek's Cool App` (with apostrophe and spaces)
- Enters an empty string for required fields to see if validation catches it
- Selects "other" for language and platform to hit the fallback code paths
- Answers "No" to every optional installation prompt
- Types `pause` in the middle of the intake wizard, then kills the terminal without proper exit, then tries `--resume`
- Fills out 3 out of 12 Intake sections and tells the agent to "just start building"
- Uses `git commit --no-verify` to bypass the pre-commit hook
- Modifies `.claude/phase-state.json` directly to skip phases
- Deletes `APPROVAL_LOG.md` and tries to proceed
- Enters `'; DROP TABLE users; --` in text input fields
- Runs `init.sh` in a directory that already has a git repo with uncommitted changes
- Runs `init.sh` twice in the same directory
- Runs `upgrade-project.sh --track light` (downgrade attempt)
- Runs `upgrade-project.sh --deployment personal` (downgrade attempt)
- Runs scripts from the wrong directory (not the project root)
- Provides conflicting information in the Intake (e.g., "no auth needed" + feature that requires user accounts)
- Cancels the tool installation walkthrough mid-way
- Runs `check-versions.sh` with no network connectivity
- Provides a project description with Unicode characters, emojis, and special shell characters (`$HOME`, backticks, `$(rm -rf /)`)

**What Derek tests:** Error handling, input validation, graceful degradation, bypass resistance, and whether the framework fails safely or fails dangerously. Derek is the chaos monkey. Every crash, data corruption, or silent failure Derek triggers is a bug.

---

## 2. Application Definitions

### Application A — Web App: "InvoiceTracker"

| Field | Value |
|---|---|
| **Platform** | Web |
| **Language** | TypeScript |
| **Description** | Internal invoice reconciliation tool that imports CSV files from 3 vendor systems, matches invoices by number, flags mismatches exceeding $0.01, and generates a reconciliation report |
| **Must-Have Features** | (1) CSV upload with format validation, (2) Invoice matching engine, (3) Mismatch flagging with configurable threshold, (4) Reconciliation report export (PDF/CSV), (5) User authentication (email/password) |
| **Data Sensitivity** | Internal (invoice data), PII (vendor contact info) |
| **Target Users** | 5 at launch, 50 at 12 months |
| **Hosting** | Vercel + Supabase |
| **Track** | Standard |

### Application B — Desktop App: "LogAnalyzer"

| Field | Value |
|---|---|
| **Platform** | Desktop |
| **Language** | Rust (Tauri backend) + TypeScript (frontend) |
| **Description** | Cross-platform log file analyzer that opens local log files (up to 500MB), provides search/filter, regex highlighting, and generates summary statistics. Fully offline — no network required. |
| **Must-Have Features** | (1) Open and parse log files (.log, .txt, .json), (2) Real-time search with regex support, (3) Filter by severity level, (4) Summary statistics dashboard, (5) Export filtered results |
| **Data Sensitivity** | Internal (log files may contain sensitive operations data) |
| **Target Users** | 3 at launch, 20 at 12 months |
| **Target Platforms** | Windows 10+, macOS 12+, Ubuntu 22.04+ |
| **Track** | Light (upgrading to Standard during Sponsored POC) |

### Application C — Mobile App: "FieldNotes"

| Field | Value |
|---|---|
| **Platform** | Mobile |
| **Language** | TypeScript (React Native / Expo) |
| **Description** | Cross-platform field inspection app for property managers. Take photos, add notes, tag locations, generate PDF reports. Offline-first — sync when connectivity is available. |
| **Must-Have Features** | (1) Create inspection with photos + notes, (2) GPS tagging of each inspection point, (3) Offline storage with background sync, (4) PDF report generation, (5) Inspection history and search |
| **Data Sensitivity** | Internal (inspection data), PII (property addresses, manager names) |
| **Target Users** | 10 at launch, 200 at 12 months |
| **Target Platforms** | iOS 16+, Android 13+ |
| **Track** | Standard |

---

## 3. Agent Assignment Matrix

| Agent ID | Persona | Application | Platform | Language | Starting Track |
|---|---|---|---|---|---|
| **P1-WEB** | Marcus (Senior) | InvoiceTracker | Web | TypeScript | Standard |
| **P1-DESKTOP** | Marcus (Senior) | LogAnalyzer | Desktop | Rust | Light |
| **P1-MOBILE** | Marcus (Senior) | FieldNotes | Mobile | TypeScript | Standard |
| **P2-WEB** | Priya (Mid-Level) | InvoiceTracker | Web | TypeScript | Standard |
| **P2-DESKTOP** | Priya (Mid-Level) | LogAnalyzer | Desktop | Rust | Light |
| **P2-MOBILE** | Priya (Mid-Level) | FieldNotes | Mobile | TypeScript | Standard |
| **P3-WEB** | Derek (Chaos) | InvoiceTracker | Web | TypeScript | Standard |
| **P3-DESKTOP** | Derek (Chaos) | LogAnalyzer | Desktop | Rust | Light |
| **P3-MOBILE** | Derek (Chaos) | FieldNotes | Mobile | TypeScript | Standard |

---

## 4. Deployment Upgrade Path (All Agents)

Every agent follows this upgrade sequence. The upgrade itself is a test — verify the upgrade scripts work, files are updated, nothing is lost, and the project is in a valid state after each transition.

| Stage | Deployment | POC Mode | Track (Web/Mobile) | Track (Desktop) |
|---|---|---|---|---|
| **Stage 1** | Personal | Private POC | Standard | Light |
| **Stage 2** | Organizational | Sponsored POC | Standard | Standard |
| **Stage 3** | Organizational | Production | Standard | Standard |

**Upgrade commands under test:**
- Stage 1→2: `scripts/upgrade-project.sh --to-sponsored-poc` (then `--track standard` for Desktop)
- Stage 2→3: `scripts/upgrade-project.sh --to-production`

**After each upgrade, verify:**
- [ ] `.claude/phase-state.json` updated correctly
- [ ] `.claude/tool-preferences.json` updated correctly
- [ ] `CLAUDE.md` updated (POC watermarks removed at Stage 3, governance section added at Stage 2)
- [ ] `PROJECT_INTAKE.md` updated (track/deployment fields, governance section added)
- [ ] `APPROVAL_LOG.md` restructured (personal → organizational format at Stage 2)
- [ ] Git commit created with upgrade details
- [ ] `validate.sh` passes after upgrade
- [ ] `verify-install.sh` passes after upgrade
- [ ] No files lost, no data corrupted
- [ ] Tool resolver surfaces new tools required for upgraded track
- [ ] Previous phase artifacts (if any) are preserved unchanged

---

## 5. Phase-by-Phase Test Execution

### Instructions for Each Agent

You are assigned a persona and application type. Execute every phase below **in character** — make the decisions your persona would make, make the mistakes your persona would make, provide the quality of input your persona would provide.

For each phase:
1. Execute the phase as your persona would
2. Record every command you run and its output
3. Record every error, warning, or unexpected behavior
4. Record every point where the documentation was unclear, incorrect, or missing
5. Record the time spent on each sub-step
6. After completing the phase, run `validate.sh` and `check-phase-gate.sh`
7. Record whether the phase gate passed, failed, or warned

**For Derek (P3) agents specifically:** After completing each phase "normally" (however sloppily), go back and execute the edge case tests listed in Section 6. Record what happens — crashes, silent failures, data corruption, or graceful error handling.

---

### Phase: Pre-Init (Repository Setup + init.sh)

**Objective:** Clone the framework, run `init.sh`, verify all generated files and tooling.

**Test Steps — All Personas:**

| # | Step | Marcus (P1) | Priya (P2) | Derek (P3) |
|---|---|---|---|---|
| 1 | Clone the solo-orchestrator repo | Standard clone | Standard clone | Clone into a path with spaces: `~/My Projects/solo stuff/` |
| 2 | Run `init.sh --dry-run` | Yes — reviews output before proceeding | Skips dry-run | Doesn't know `--dry-run` exists |
| 3 | Run `init.sh` | Answers all prompts correctly, selects correct platform/language/track | Answers prompts, occasionally unsure, uses defaults | Enters `Derek's Cool App` as project name; enters project description with `$HOME` and backticks; selects "other" for language on one run |
| 4 | Tool installation prompts | Accepts all recommended tools | Declines Docker and GPG ("I don't know what those are") | Declines everything, then complains tools are missing |
| 5 | Verify generated files | Checks every file against the "What Gets Created" section in README | Checks CLAUDE.md and .gitignore exist | Doesn't check anything |
| 6 | Post-init authentication | Runs `claude` OAuth and `snyk auth` | Runs `claude` but forgets `snyk auth` until Phase 2 blocks | Doesn't authenticate anything |
| 7 | Run `verify-install.sh` | Yes — reviews report | Doesn't know this exists | No |
| 8 | Run `check-versions.sh` | Yes | No | No |

**Verification Checklist (all agents must verify):**

- [ ] `CLAUDE.md` contains correct project name, platform, track, language
- [ ] `PROJECT_INTAKE.md` exists and is the full template
- [ ] `APPROVAL_LOG.md` exists with correct deployment type (personal)
- [ ] `.claude/phase-state.json` exists with `current_phase: 0`
- [ ] `.claude/build-progress.json` exists with correct test interval
- [ ] `.claude/tool-preferences.json` exists with correct context
- [ ] `.github/workflows/ci.yml` exists and matches the language template
- [ ] `.github/workflows/release.yml` exists and matches the platform template
- [ ] `.gitignore` contains language + platform specific entries
- [ ] `docs/reference/` contains all 6 framework documents
- [ ] `docs/platform-modules/` contains the correct platform module (or is empty for "other")
- [ ] `scripts/` contains all 11 utility scripts, all executable
- [ ] `templates/intake-suggestions/` contains JSON files
- [ ] `templates/tool-matrix/` contains JSON files with valid JSON
- [ ] `evaluation-prompts/Projects/` contains bases, modules, compose.sh, run-reviews.sh
- [ ] `tests/uat/` directory structure created
- [ ] Pre-commit hook installed and functional (test with a staged secret)
- [ ] Git repo initialized with initial commit
- [ ] Development Guardrails for Claude Code installation attempted (record result — may fail if repo unavailable)

---

### Phase 0: Product Discovery

**Objective:** Fill out the Intake and produce a Product Manifesto.

**Test Steps:**

| # | Step | Marcus (P1) | Priya (P2) | Derek (P3) |
|---|---|---|---|---|
| 1 | Choose intake method | Guided script mode | AI-assisted mode | Types `3` (manual) then never opens the file |
| 2 | Fill Intake Section 1 (Identity) | Complete — all fields accurate | Complete | Leaves most fields blank |
| 3 | Fill Intake Section 2 (Business Context) | Detailed problem statement, 3 personas, 5 success criteria, 5 exclusions | Vague problem statement ("make invoices easier"), 1 persona, 2 success criteria, 2 exclusions | "I want an app that does stuff" |
| 4 | Fill Intake Section 3 (Constraints) | Realistic: 15 hrs/week, $200/mo budget, specific dates | "As time allows", "$100 maybe?", no dates | Leaves blank |
| 5 | Fill Intake Section 4 (Features) | All 5 features with logic triggers and failure states | 3 features with triggers, 2 without failure states | Lists 12 features with no logic triggers |
| 6 | Fill Intake Section 5 (Data) | Complete sensitivity classifications, fallback behaviors, persistence model | Partial — skips fallback behaviors | Puts "public" for everything including PII |
| 7 | Fill Intake Section 6 (Tech Preferences) | Honest competency matrix (Yes on Backend, Partially on Frontend, No on Mobile) | Honest (No on most) | Marks everything "Yes" |
| 8 | Fill Intake Sections 7-11 | Complete and accurate | Sections 7, 9, 10 partial; skips 8 (personal project) | Skips all |
| 9 | Use `pause` and `--resume` in wizard | Yes — tests pause at Section 4, resumes successfully | No | Types `pause` then kills terminal with Ctrl+C |
| 10 | Provide Intake to agent, run Phase 0 prompts | Follows User Guide Step 0.1→0.4 sequence | Tells agent "just make me a manifesto" | Tells agent "skip the planning, just build it" |
| 11 | Review Product Manifesto | Thorough review — checks MVP Cutline, user journeys, data contracts | Skims, approves without checking exclusions | Doesn't read it |
| 12 | Record in APPROVAL_LOG.md | Yes — self-review with detailed notes | Yes — minimal entry | Doesn't update the log |
| 13 | Update `.claude/phase-state.json` | Yes — via proper gate process | Forgets — agent doesn't prompt | Modifies directly with `echo '{"current_phase":2}' > .claude/phase-state.json` |

**Phase 0 Gate Verification:**
- [ ] `PRODUCT_MANIFESTO.md` exists
- [ ] Manifesto contains MVP Cutline with ≤8 must-have features
- [ ] Manifesto contains Will-Not-Have list with ≥3 items
- [ ] All must-have features have logic triggers and failure states
- [ ] User personas are defined with success and failure paths
- [ ] Data contracts include sensitivity classifications
- [ ] `APPROVAL_LOG.md` has Phase 0→1 entry (or is missing — record the gap)
- [ ] `check-phase-gate.sh` output matches expected state

---

### Phase 1: Architecture & Planning

**Objective:** Select architecture, produce threat model, design data model, compile the Project Bible.

**Test Steps:**

| # | Step | Marcus (P1) | Priya (P2) | Derek (P3) |
|---|---|---|---|---|
| 1 | Market signal validation (Standard+ track) | Performs lightweight validation | Skips — doesn't realize it's required for Standard | N/A — doesn't get here properly |
| 2 | Architecture selection | Reviews 3 options, selects with documented rationale, rejects others with reasons | Accepts whatever the agent recommends first | "Just use whatever" |
| 3 | Threat model review | Verifies concrete mitigations, not "be careful" | Reads but doesn't challenge vague mitigations | Skips |
| 4 | Data model review | Verifies all features are supported, reviews relationships and constraints | Checks it "looks right" | Doesn't review |
| 5 | UI scaffolding review | Checks all 4 states (empty, loading, error, success), accessibility baseline | Checks loading and success, misses empty and error states | Doesn't review |
| 6 | Compile Project Bible | Reviews all 16 sections of the Bible | Skims — misses that test strategy section is empty | Bible is incomplete because Intake was incomplete |
| 7 | Record in APPROVAL_LOG.md | Detailed entry with architecture rationale | Basic entry | Skips |

**Phase 1 Gate Verification:**
- [ ] `PROJECT_BIBLE.md` exists and is comprehensive
- [ ] Architecture Decision Record exists with selection rationale and rejected alternatives
- [ ] Threat model follows STRIDE with concrete mitigations per vector
- [ ] Data model covers all must-have features
- [ ] Test strategy defines what is tested, tools used, and pass/fail criteria
- [ ] Build and distribution strategy is platform-appropriate
- [ ] Context management plan is defined
- [ ] `APPROVAL_LOG.md` has Phase 1→2 entry
- [ ] `check-phase-gate.sh` passes

---

### Phase 2: Construction

**Objective:** Build features using TDD, per-feature security audits, documentation updates.

**Note:** Phase 2 is where the deployment upgrades happen. Execute the upgrade at the points indicated.

**Test Steps:**

| # | Step | Marcus (P1) | Priya (P2) | Derek (P3) |
|---|---|---|---|---|
| 1 | Project initialization | Verifies all 8 initialization checks pass before building | Skips check 4 (pre-commit hook test) and check 6 (license checker) | Doesn't run initialization checks |
| 2 | **UPGRADE: Private POC → Sponsored POC** | Runs `upgrade-project.sh --to-sponsored-poc`; for Desktop also runs `--track standard` | Runs upgrade but is confused by governance pre-conditions | Runs upgrade from wrong directory, then runs it correctly but enters invalid data for pre-conditions |
| 3 | Build Feature 1 (highest-risk) | TDD: writes tests first, reviews assertions, verifies tests fail, implements, runs SAST, documents | Writes some tests, implements alongside (not strict TDD), skips SAST | Tells agent "just build everything at once" — no TDD |
| 4 | Security audit per feature | Runs `semgrep scan` with correct flags, reviews against threat model, checks data isolation | Runs `semgrep` but uses wrong config flags, misses data isolation check | Doesn't run security scans |
| 5 | `test-gate.sh --record-feature` | Runs after each feature | Forgets for features 2 and 3 | Doesn't run at all |
| 6 | `test-gate.sh --check-batch` | Runs before starting each feature | Runs occasionally | Doesn't run — hits testing gate unexpectedly |
| 7 | UAT testing session | Follows full Step 2.7 process — dispatches test agents, generates template, waits for results | Runs automated tests but skips human testing | Skips entirely |
| 8 | Bug triage (Step 2.8) | Proper severity assignment and disposition | Marks everything SEV-4 | Doesn't triage |
| 9 | Context health check (every 3-4 features) | Performs check, compares against Bible | Skips | Skips |
| 10 | Build features 2-5 | Follows Build Loop per feature | Follows Build Loop loosely — skips documentation updates after features 3 and 4 | Tries to build all features in one session with no TDD |
| 11 | **UPGRADE: Sponsored POC → Production** | Runs `upgrade-project.sh --to-production`; fills in all governance pre-conditions | Runs upgrade, confused by the 6 blocking pre-conditions, leaves 2 as "In Progress" | Runs `--to-production` with all pre-conditions at "Not Started", sees what happens |
| 12 | Phase 2 completion checkpoint | Verifies all 11 items on the checklist | Checks 6 of 11 items | Doesn't check |

**Phase 2 Gate Verification:**
- [ ] All MVP Cutline features built and passing tests
- [ ] No partially implemented features
- [ ] Full test suite passes
- [ ] CI pipeline green (if pushed to GitHub)
- [ ] Project Bible accurately reflects current codebase
- [ ] CHANGELOG.md current
- [ ] No unresolved security findings
- [ ] Application builds on at least one target platform
- [ ] UAT testing sessions completed (or documented as skipped)
- [ ] `test-gate.sh --check-phase-gate` passes (or documents what blocks it)
- [ ] Both upgrades completed successfully with correct file updates

---

### Phase 3: Validation & Security

**Objective:** Prove everything works correctly, securely, and accessibly.

**Test Steps:**

| # | Step | Marcus (P1) | Priya (P2) | Derek (P3) |
|---|---|---|---|---|
| 1 | E2E/integration tests | Writes comprehensive E2E tests, runs on all target platforms | Writes basic E2E tests, runs on one platform | Doesn't write E2E tests |
| 2 | Full SAST scan | `semgrep scan --config=p/owasp-top-ten --config=p/security-audit --severity ERROR --severity WARNING .` | Runs with `--config=p/owasp-top-ten` only (misses security-audit) | Doesn't run |
| 3 | Dependency scan | `snyk test` | `snyk test` (finally authenticates) | `snyk test` without auth — records failure behavior |
| 4 | Secret scan | `gitleaks detect --source . --verbose` | Runs gitleaks | Skips |
| 5 | SBOM generation | Generates CycloneDX SBOM | Doesn't know what an SBOM is, skips | Skips |
| 6 | Threat model validation | Reviews every Phase 1.3 vector, verifies mitigation or documents acceptance | Reviews 3 of 7 vectors | Skips |
| 7 | Accessibility audit | Runs Lighthouse (web), platform tools (desktop/mobile); verifies keyboard nav, screen reader, color independence | Runs Lighthouse only, doesn't test keyboard nav | Skips |
| 8 | Performance audit | Tests startup time, core operation latency, memory stability | Basic startup test | Skips |
| 9 | Archive test results | All scan outputs saved to `docs/test-results/` with correct naming convention | Saves some results, wrong naming convention | Doesn't save |
| 10 | Go-live approval | Records in APPROVAL_LOG.md with evidence references | Records approval with no evidence references | Doesn't record |

**Phase 3 Gate Verification:**
- [ ] `docs/test-results/` contains dated scan reports
- [ ] Zero critical/high SAST findings (or all addressed)
- [ ] Zero critical/high dependency vulnerabilities (or documented acceptance)
- [ ] No secrets detected in repository
- [ ] SBOM generated
- [ ] Threat model vectors have verified mitigations or documented acceptance
- [ ] Accessibility meets WCAG AA / Lighthouse 90+ (web)
- [ ] Performance meets data contract latency targets
- [ ] `APPROVAL_LOG.md` has Phase 3→4 entries (Application Owner + IT Security for organizational)

---

### Phase 4: Release & Maintenance

**Objective:** Configure deployment, create monitoring, write handoff docs, verify rollback.

**Test Steps:**

| # | Step | Marcus (P1) | Priya (P2) | Derek (P3) |
|---|---|---|---|---|
| 1 | Production build verification | Verifies build on all target platforms | Verifies build on one platform | Doesn't verify |
| 2 | Configure release pipeline | Reviews TODOs in `release.yml`, configures signing and secrets | Looks at `release.yml`, doesn't understand the TODOs | Ignores release pipeline |
| 3 | Incident response playbook | Reviews `INCIDENT_RESPONSE.md`, verifies severity classifications match expectations | Skims playbook | Doesn't create playbook |
| 4 | Rollback test | Deploys release candidate, executes rollback, verifies data integrity | Reads rollback procedure but doesn't test it | Doesn't test rollback |
| 5 | Go-live smoke test | Walks through full user journey on each target platform, triggers test error, verifies monitoring captures it | Tests on one platform, doesn't trigger test error | Skips smoke test |
| 6 | Generate `HANDOFF.md` | Reviews for completeness — dev setup, build, deploy, triage, contacts | Skims handoff doc | Doesn't generate handoff doc |
| 7 | Generate `RELEASE_NOTES.md` | Writes user-facing release notes | Writes developer-facing changelog instead of user-facing notes | Skips |
| 8 | Monitoring setup | Configures error tracking and alerting | Configures error tracking, no alerting | Skips monitoring |
| 9 | Run `validate.sh` final check | Yes — expects all checks pass | Yes | Yes — records what fails |
| 10 | Run `check-updates.sh` | Yes | No | No |

**Phase 4 Gate Verification:**
- [ ] Application builds on all target platforms
- [ ] `HANDOFF.md` exists and is comprehensive
- [ ] `RELEASE_NOTES.md` exists with user-facing content
- [ ] `docs/INCIDENT_RESPONSE.md` exists with severity classifications
- [ ] Rollback procedure tested (or documented as untested)
- [ ] Monitoring configured and verified
- [ ] Go-live smoke test passed on all target platforms
- [ ] `validate.sh` passes
- [ ] Final `APPROVAL_LOG.md` entry records go-live

---

## 6. Edge Case Tests (Derek / P3 Agents Only)

Execute these edge cases **after** each phase. Record the exact behavior — crash, graceful error, silent failure, or correct handling.

### Pre-Init Edge Cases

| # | Test | Expected Behavior | Actual (Record) |
|---|---|---|---|
| E1 | Run `init.sh` with project name `Derek's Cool App` (apostrophe + spaces) | Should reject or sanitize; project name should be lowercase-no-spaces | |
| E2 | Run `init.sh` with project description containing `$(whoami)` and backtick command substitution | Should treat as literal text, not execute | |
| E3 | Run `init.sh` in a directory that already contains a `.git` directory | Should warn or handle gracefully | |
| E4 | Run `init.sh` twice in the same target directory | Should warn about existing project or handle idempotently | |
| E5 | Run `init.sh`, select "other" for both platform and language | Should generate valid project with other.yml CI template and no platform module | |
| E6 | Run `init.sh` with no internet connectivity (after prerequisite check) | Should fail gracefully when cloning Development Guardrails, continue with fallback | |
| E7 | Kill `init.sh` with Ctrl+C midway through tool installation | Should not leave partial state that breaks re-run | |
| E8 | Run `init.sh` from a read-only directory | Should fail with clear error message | |
| E9 | Run `init.sh` with `HOME` set to a non-existent directory | Should fail gracefully | |
| E10 | Verify `init.sh --dry-run` makes zero filesystem changes | Diff before/after should show no changes | |

### Script Edge Cases

| # | Test | Expected Behavior | Actual (Record) |
|---|---|---|---|
| E11 | Run `validate.sh` from outside a project directory | Should fail with clear error ("CLAUDE.md not found") | |
| E12 | Run `resume.sh` with empty/missing `CLAUDE.md` | Should handle gracefully | |
| E13 | Run `check-phase-gate.sh` with manually edited `phase-state.json` (phase 3 but no gate dates) | Should report inconsistency | |
| E14 | Run `test-gate.sh --check-phase-gate` with open SEV-1 bugs in BUGS.md | Should block (exit 1) | |
| E15 | Run `test-gate.sh --check-phase-gate` with no bug tracker (no BUGS.md, no GitHub Issues) | Should warn and exit 2 | |
| E16 | Run `upgrade-project.sh --track light` (downgrade) | Should reject with clear error | |
| E17 | Run `upgrade-project.sh --deployment personal` (downgrade) | Should reject with clear error | |
| E18 | Run `upgrade-project.sh` from outside a project directory | Should fail with clear error | |
| E19 | Run `intake-wizard.sh --resume` with no progress file | Should fail with clear message | |
| E20 | Run `intake-wizard.sh`, type an apostrophe in a text field (known BUG-1 from test report) | Should not crash — record if the `save_answer` function breaks on `it's` | |
| E21 | Run `intake-wizard.sh`, type `pause`, then kill terminal, then `--resume` | Should resume from last saved section | |
| E22 | Run `check-versions.sh` with no network (offline mode) | Should skip latest-version checks gracefully, still report installed versions | |
| E23 | Run `resolve-tools.sh` with invalid JSON in tool-matrix files | Should fail with clear error | |
| E24 | Delete `APPROVAL_LOG.md` and run `check-phase-gate.sh` | Should fail with clear error | |
| E25 | Modify `.claude/phase-state.json` to set `current_phase: 99` | Should be handled or at least not crash downstream scripts | |

### Upgrade Path Edge Cases

| # | Test | Expected Behavior | Actual (Record) |
|---|---|---|---|
| E26 | Run `--to-production` on a project that is already production (no POC mode) | Should report "not in POC mode" and exit | |
| E27 | Run `--to-sponsored-poc` on a project that is already organizational/production | Should reject (can't downgrade to POC) | |
| E28 | Run `--track standard --track full` (double flag) | Should use last value or report error | |
| E29 | Run upgrade with `jq` not installed | Should fail with clear error about missing jq | |
| E30 | Run upgrade with `python3` not installed | Should fail with clear error about missing python3 | |
| E31 | Run upgrade, confirm with "n", verify no changes were made | Should abort cleanly with no file modifications | |
| E32 | Run upgrade on a project with uncommitted changes | Should handle gracefully (commit upgrade changes separately or warn) | |

### Input Validation Edge Cases

| # | Test | Input | Expected Behavior | Actual (Record) |
|---|---|---|---|---|
| E33 | Project name with SQL injection payload | `'; DROP TABLE users; --` | Should sanitize to safe string | |
| E34 | Project description with 10,000 characters | Long lorem ipsum | Should accept or truncate gracefully | |
| E35 | Empty string for required Intake fields | (just press Enter) | Should re-prompt or warn | |
| E36 | Unicode project name | `プロジェクト` | Should handle or reject with clear message | |
| E37 | Emoji in project description | `Build a 🚀 app` | Should store literally, not crash | |
| E38 | Path traversal in project directory | `../../etc/passwd` | Should reject or normalize | |
| E39 | Newlines in text input fields | `line1\nline2` | Should handle without breaking JSON | |
| E40 | NUL bytes in text input | `test\x00data` | Should handle or strip | |

---

## 7. Cross-Agent Consistency Checks

After all 9 agents complete, compare results across agents to verify the framework produces consistent outcomes:

| Check | Comparison | Pass Criteria |
|---|---|---|
| File structure | Compare generated file lists across all 9 projects | Same files generated for same platform/language combo (allowing for track differences) |
| CI pipeline | Compare `ci.yml` across Web agents (P1, P2, P3) | Identical content regardless of persona |
| Release pipeline | Compare `release.yml` across same-platform agents | Identical content regardless of persona |
| CLAUDE.md | Compare across same-combo agents | Same structure; persona-specific values (project name) differ, framework content identical |
| Tool resolution | Compare `resolve-tools.sh` output for same platform/language/track | Identical tool lists regardless of persona |
| Phase-state tracking | Compare final `phase-state.json` | Marcus (P1) should have all gates dated; Priya (P2) may have gaps; Derek (P3) may have corrupted state |
| Upgrade results | Compare post-upgrade file state across personas for same app type | File structure should be identical after same upgrade path, regardless of persona behavior during the upgrade |

---

## 8. Known Bugs to Verify

The framework's own test report (Reports/2026-04-03-full-test-suite.md) documents these bugs. Each agent should confirm whether they are still present:

| Bug ID | Description | Affected Script | Severity | Verify |
|---|---|---|---|---|
| BUG-1 | `save_answer` breaks on single quotes in user input | intake-wizard.sh | Critical | Derek types `it's a REST API` in any text field |
| BUG-2 | `init_progress` breaks on single quotes in PROJECT_DESCRIPTION | intake-wizard.sh | Critical | Derek enters `Derek's app` as description |
| BUG-3 | `load_progress` shell injection via `eval` | intake-wizard.sh | Critical | Derek resumes a project whose saved name contains quotes |
| BUG-4 | `((warnings++))` crashes under `set -e` | validate.sh | Critical | Any agent runs `validate.sh` and triggers the first warning |
| BUG-5 | Phase regex expects quoted string but `current_phase` is bare integer | resume.sh | Critical | Any agent runs `resume.sh` — phase should not be "unknown" |
| BUG-6 | BSD grep on macOS doesn't support `\|` in BRE | validate.sh | High | Run `validate.sh` on macOS |
| BUG-7 | `has_no` variable can be empty, breaking `-eq` comparison | validate.sh | High | Trigger competency matrix check in `validate.sh` |
| BUG-8 | `check_pause` doesn't work inside `$(...)` subshells | intake-wizard.sh | High | Type `pause` during guided script mode — does it actually pause? |

---

## 9. Reporting Format

Each agent produces a report with this structure. Save as `test-report-{AGENT_ID}.md` in the project root.

```markdown
# Test Report — {AGENT_ID}

## Agent Identity
- **Agent ID:** {P1-WEB, P2-DESKTOP, etc.}
- **Persona:** {Marcus/Priya/Derek}
- **Application:** {InvoiceTracker/LogAnalyzer/FieldNotes}
- **Platform:** {Web/Desktop/Mobile}
- **Language:** {TypeScript/Rust}

## Environment
- **OS:** {macOS/Linux/WSL version}
- **Shell:** {bash version}
- **Node.js:** {version}
- **Git:** {version}
- **Available Tools:** {list installed tools and versions}

## Pre-Init Results
| Check | Result | Notes |
|---|---|---|
| init.sh --dry-run | PASS/FAIL/SKIP | |
| init.sh execution | PASS/FAIL | |
| Generated file verification | X/Y checks passed | |
| verify-install.sh | PASS/FAIL/SKIP | |
| check-versions.sh | PASS/FAIL/SKIP | |

## Phase Results

### Phase 0
| Step | Result | Time | Issues |
|---|---|---|---|
| Intake completion | PASS/PARTIAL/FAIL | Xm | |
| Product Manifesto | PASS/FAIL | Xm | |
| Gate approval | PASS/FAIL/SKIP | | |

### Phase 1
| Step | Result | Time | Issues |
|---|---|---|---|
| Architecture selection | PASS/FAIL | Xm | |
| Threat model | PASS/FAIL | Xm | |
| Project Bible | PASS/FAIL | Xm | |
| Gate approval | PASS/FAIL/SKIP | | |

### Phase 2
| Step | Result | Time | Issues |
|---|---|---|---|
| Project initialization | X/8 checks | Xm | |
| Feature 1 (Build Loop) | PASS/FAIL | Xm | |
| Feature 2 (Build Loop) | PASS/FAIL | Xm | |
| Feature N... | | | |
| Upgrade: Private→Sponsored | PASS/FAIL | Xm | |
| Upgrade: Sponsored→Production | PASS/FAIL | Xm | |
| Phase 2 completion | X/11 checks | | |

### Phase 3
| Step | Result | Time | Issues |
|---|---|---|---|
| E2E tests | PASS/FAIL/SKIP | Xm | |
| SAST scan | PASS/FAIL/SKIP | Xm | |
| Dependency scan | PASS/FAIL/SKIP | Xm | |
| Secret scan | PASS/FAIL/SKIP | Xm | |
| SBOM | PASS/FAIL/SKIP | Xm | |
| Threat model validation | PASS/FAIL/SKIP | Xm | |
| Accessibility | PASS/FAIL/SKIP | Xm | |
| Performance | PASS/FAIL/SKIP | Xm | |
| Gate approval | PASS/FAIL/SKIP | | |

### Phase 4
| Step | Result | Time | Issues |
|---|---|---|---|
| Production build | PASS/FAIL/SKIP | Xm | |
| Rollback test | PASS/FAIL/SKIP | Xm | |
| Smoke test | PASS/FAIL/SKIP | Xm | |
| Handoff doc | PASS/FAIL/SKIP | Xm | |
| Monitoring | PASS/FAIL/SKIP | Xm | |

## Upgrade Path Results

| Upgrade | Files Updated | Validation | Issues |
|---|---|---|---|
| Private POC → Sponsored POC | X files changed correctly | validate.sh: PASS/FAIL | |
| Sponsored POC → Production | X files changed correctly | validate.sh: PASS/FAIL | |

## Edge Cases (P3 Only)

| Edge Case ID | Result | Behavior Observed |
|---|---|---|
| E1 | PASS/FAIL | {description of what happened} |
| E2 | PASS/FAIL | |
| ... | | |

## Known Bug Verification

| Bug ID | Still Present? | Observed Behavior |
|---|---|---|
| BUG-1 | YES/NO/N/A | |
| BUG-2 | YES/NO/N/A | |
| ... | | |

## Issues Found

### Critical (blocks usage)
1. {description, file, line, steps to reproduce}

### High (wrong behavior)
1. {description, file, line, steps to reproduce}

### Medium (confusing but workaround exists)
1. {description}

### Low (cosmetic or documentation)
1. {description}

## Documentation Issues
1. {page/section where docs were wrong, unclear, or missing}

## Recommendations
1. {specific actionable suggestion}

## Total Time
| Phase | Human Hours |
|---|---|
| Pre-Init | Xh |
| Phase 0 | Xh |
| Phase 1 | Xh |
| Phase 2 | Xh |
| Phase 3 | Xh |
| Phase 4 | Xh |
| Upgrades | Xh |
| Edge Cases | Xh |
| **Total** | **Xh** |
```

---

## 10. Success Criteria

The test plan passes if:

1. **Marcus (P1) agents:** All 3 applications complete Phases 0–4 with all gate checks passing. Both upgrades succeed. `validate.sh` passes at the end. No critical bugs encountered when following the documented process.

2. **Priya (P2) agents:** All 3 applications reach at least Phase 2 with identifiable (not cryptic) error messages when steps are skipped or done incorrectly. The framework either guides the user back on track or clearly explains what went wrong. At least 2 of 3 applications complete all phases.

3. **Derek (P3) agents:** No edge case causes data corruption, silent failures, or security-relevant issues (e.g., secrets written to files, shell injection via user input). Every error produces a meaningful message. The framework never executes user input as code. At least 60% of edge cases (24/40) are handled gracefully.

4. **Cross-agent consistency:** Same platform/language/track combinations produce identical generated file content across all 3 personas.

5. **Upgrade paths:** All 9 agents successfully complete both upgrades (Private POC → Sponsored POC → Production). Post-upgrade `validate.sh` passes for all P1 and P2 agents.

6. **Known bugs:** All 8 known bugs from the existing test report are confirmed as fixed or documented as still present with regression evidence.

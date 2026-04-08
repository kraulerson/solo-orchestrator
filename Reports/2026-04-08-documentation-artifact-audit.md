# Documentation Artifact Audit — Solo Orchestrator Framework

**Date:** 2026-04-08
**Auditor:** Claude Opus 4.6 (1M context)
**Framework Version:** 1.0
**Files Read:** All files specified in the audit request (builders-guide.md, user-guide.md, governance-framework.md, executive-review.md, web.md, desktop.md, mobile.md, cli-setup-addendum.md, security-scan-guide.md, all templates, all scripts, init.sh, evaluation prompts)

---

## Part 1: Complete Artifact Registry

### 1.1 Primary Project Artifacts

| # | Artifact Name | Reference Locations | When Created | Who Creates It | Where It Lives | Format | Template | Content Spec | Enforcement | Update Lifecycle |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **PRODUCT_MANIFESTO.md** | builders-guide.md:428, 430, 1430; user-guide.md:527; exec-review.md:169; governance.md:922; claude-md.tmpl:14 | Phase 0, Step 0.4 | Agent (synthesizes from Intake) | Project root: `PRODUCT_MANIFESTO.md` | Markdown. Contents defined: Product Intent, MVP Cutline, Manifesto Rules. Revenue Model & Competency Matrix as appendices (Steps 0.5, 0.6) | None — format specified inline in builders-guide.md:401-426 | Detailed: must contain FRD, User Journeys, Data Contracts, MVP Cutline, Revenue Model (Standard+), Competency Matrix, Open Questions | **Tier 3 only** — no script or CI check verifies existence or content. check-phase-gate.sh checks phase state and approval log consistency but does NOT verify PRODUCT_MANIFESTO.md exists. | Write-once primary; appendices added in Steps 0.5-0.6. Referenced throughout but not updated after Phase 0 unless returning from Phase 2 (architecture wrong mid-build). |
| 2 | **PROJECT_BIBLE.md** | builders-guide.md:638, 682, 1431; user-guide.md:700; governance.md:922; claude-md.tmpl:14 | Phase 1, Step 1.6 | Agent (synthesizes all Phase 1 outputs) | Project root: `PROJECT_BIBLE.md` | Markdown. 16 required sections enumerated in builders-guide.md:640-676 | None — format specified inline in builders-guide.md:639-676 | Very detailed: 16 sections covering Manifesto text, Revenue Model, ADR, Threat Model, Data Model, Data Migration Plan, Auth Strategy, Observability, UI Specs, Coding Standards, Build/Distribution Strategy, Test Strategy, Orchestrator Profile, Accessibility, Platform Requirements, Context Management Plan, Bug Severity Classification, UAT Plan | **Tier 3 only** — no CI check verifies existence. Approval log template references it as reviewed artifact. | Updated in place throughout Phase 2 (Step 2.5 says "update Bible" per feature). Should reflect current codebase at all times. |
| 3 | **APPROVAL_LOG.md** | builders-guide.md:249, 493-495, 678, 1197; user-guide.md:246, 265, 461, 521, 698, 894, 938, 989-1049; governance.md:172-183, 851, 920; claude-md.tmpl:15, 57-64 | Pre-Phase 0 (by init.sh) | init.sh generates with headers; approvers fill in entries | Project root: `APPROVAL_LOG.md` | Markdown with structured tables per gate. Append-only. | **Yes**: `templates/generated/approval-log-org.tmpl` and `templates/generated/approval-log-personal.tmpl` | Very detailed: Pre-conditions table (6 items), Phase 0→1 gate, Phase 1→2 gate, Phase 3→4 gate (split: App Owner + IT Security), Approval History table | **Tier 1 (CI)**: `scripts/check-phase-gate.sh` verifies consistency between `.claude/phase-state.json` and `APPROVAL_LOG.md`. Blocks merge when out of sync (unless `SOIF_PHASE_GATES=warn`). | Append-only. Never edit previous entries. Git history provides tamper evidence. |
| 4 | **CLAUDE.md** | builders-guide.md:87; user-guide.md:244, 263, 437; cli-setup-addendum.md:389-570; claude-md.tmpl (entire file) | Pre-Phase 0 (by init.sh) | init.sh generates starter version from `templates/generated/claude-md.tmpl` | Project root: `CLAUDE.md` | Markdown. Structured sections: Project Identity, Framework Reference, Engineering Principles, Operating Instructions, Session Start, Phase Awareness, Governance Tracking, Construction Rules, Superpowers Integration, Multi-Agent Parallelism, When to Ask, Qdrant Memory, Agent Personas, Testing & Bug Workflow, Upgrade Paths | **Yes**: `templates/generated/claude-md.tmpl`. Also an enhanced template in cli-setup-addendum.md:414-547 | Very detailed: 156-line template with placeholders for project name, platform, track, language, test interval | **Tier 1.5 (CI annotation)**: `scripts/check-session-state.sh` warns when CLAUDE.md not updated in 5+ commits or 24+ hours. Upgradable to block via `SOIF_STRICT_SESSION=true`. | Updated in place. Must be updated at every phase transition and end of every session. |
| 5 | **PROJECT_INTAKE.md** | builders-guide.md:37-44, 255-260; user-guide.md:245, 265, 319-425; governance.md:27-29, 851; templates/project-intake.md | Pre-Phase 0 (by init.sh) | init.sh copies template; Orchestrator fills out (via wizard or manually) | Project root: `PROJECT_INTAKE.md` | Markdown. 12 sections. Structured tables with field/value pairs. | **Yes**: `templates/project-intake.md` (~500 lines) | Extremely detailed: 12 sections covering identity, business context, constraints, features, data, tech preferences, revenue, governance, accessibility, distribution, known risks, initialization prompt | **Tier 3 only** — no script checks completeness. The agent is instructed to flag blank fields during Phase 0. | Write-once before Phase 0. Tooling summary appended by init.sh. Section 1 pre-filled by init.sh. |
| 6 | **CHANGELOG.md** | builders-guide.md:885, 1013, 1434; user-guide.md:794, 847 | Phase 2 (first feature) | Agent | Project root: `CHANGELOG.md` | Markdown. Feature name, date, new interfaces/endpoints/commands per entry. | None — format described inline | Moderate: must include feature name, date, interfaces. No specific changelog format (e.g., Keep a Changelog) mandated. | **Tier 1.5 (CI annotation)**: `scripts/check-changelog.sh` warns when source files change without CHANGELOG.md update. Upgradable to block via `SOIF_STRICT_CHANGELOG=true`. | Append-only per feature. Updated at Step 2.5 of every Build Loop iteration. |
| 7 | **CONTRIBUTING.md** | builders-guide.md:766, 1433; user-guide.md:700 | Phase 2, Project Initialization | Agent | Project root: `CONTRIBUTING.md` | Markdown. Coding standards for AI reference. | None | Light: "coding standards" — details left to agent based on Bible's coding standards section | **Tier 3 only** — no enforcement | Write-once. Referenced via `@./CONTRIBUTING.md` in CLAUDE.md. |
| 8 | **HANDOFF.md** | builders-guide.md:1378-1393, 1445; user-guide.md:942, 970; governance.md:588-596, 932 | Phase 4, Step 4.5 | Agent | Project root: `HANDOFF.md` | Markdown. 9 required sections enumerated in builders-guide.md:1380-1389 | None — format specified inline | Detailed: Product intent, dev setup (per platform), build/release process, tech debt map, maintenance schedule, incident history, bug reporting mechanism, key contacts, AI Quick Start prompt | **Tier 3 only** — no CI check. Governance framework requires handoff test (backup maintainer validates). | Write-once in Phase 4. Updated if gaps found during handoff test. |
| 9 | **docs/INCIDENT_RESPONSE.md** | builders-guide.md:1283-1297, 1443; user-guide.md:937, 944-955, 970 | Phase 4, Step 4.1.5 | Agent | `docs/INCIDENT_RESPONSE.md` | Markdown. Severity classification table, containment procedures, secrets rotation. | None — format specified inline in builders-guide.md:1285-1296 | Detailed: 4-level severity classification, response times, notification chains, rollback procedure, data model rollback, containment strategy, log preservation, secrets rotation | **Tier 3 only** | Write-once. Updated if incident history reveals gaps. |
| 10 | **RELEASE_NOTES.md** | builders-guide.md:1327-1333, 1444; user-guide.md:940, 970 | Phase 4, Step 4.2 | Agent | Project root: `RELEASE_NOTES.md` | Markdown. Version number, date, user-facing summary, known limitations, bug reporting. | None | Moderate: version, date, what app does, limitations, how to report bugs. Subsequent releases: append changes, fixes, known-broken. | **Tier 3 only** | Append per release. |
| 11 | **USER_GUIDE.md** | builders-guide.md:1215-1217, 1442; user-guide.md:906 | Phase 3, Step 3.6 | Agent | Project root: `USER_GUIDE.md` | Markdown. Scope matches complexity. | None | Light: "how to access, core workflows, FAQ, support contact" for internal tools. More extensive for external products. | **Tier 3 only** | Write-once. Updated as features change. |
| 12 | **docs/test-results/** (directory) | builders-guide.md:1183-1197, 1438; user-guide.md:253, 892, 901, 909; governance.md:924 | Phase 3, Step 3.5.9 | Agent (saves scan outputs) | `docs/test-results/` | Directory. Files named `[date]_[scan-type]_[pass|fail].[ext]` | None — naming convention specified | Detailed enumeration: E2E results, SAST (JSON/SARIF), DAST, dependency scan, secret scan, SBOM, threat model validation, accessibility/performance audit, load test results, contract test results | **Tier 3 only** — directory created by init.sh (empty). No CI check verifies contents. | Populated during Phase 3. Referenced in APPROVAL_LOG.md. |
| 13 | **sbom.json** | builders-guide.md:1096, 1439; user-guide.md:887, 909; governance.md:926 | Phase 3, Step 3.2 | Agent (runs CycloneDX/syft/equivalent) | Project root or `docs/test-results/`: `sbom.json` | JSON (CycloneDX or equivalent) | None | Specified as "Software Bill of Materials" — tool-generated | **Tier 3 only** | Regenerated monthly during maintenance and at each Phase 3 rerun. |
| 14 | **Architecture Decision Records (ADRs)** | builders-guide.md:889, 1432; user-guide.md:700; governance.md:923 | Phase 1-2 (per non-trivial decision) | Agent | Unspecified location — no directory or naming convention defined | Unspecified format. Referenced as "every major choice with alternatives and rationale" | None | Light: "For non-trivial decisions" — what qualifies is undefined. Architecture selection rationale is explicitly required. | **Tier 3 only** | Created per decision. Never updated (they record the decision at a point in time). |
| 15 | **Interface Documentation** | builders-guide.md:886, 1435 | Phase 2+ (per feature, Step 2.5) | Agent | Unspecified location | "Per-endpoint/command/UI contracts, error codes" | None | Moderate: must cover every new API endpoint, command, or user-facing interface with contracts and error codes | **Tier 3 only** | Updated per feature at Step 2.5. |
| 16 | **Feature Documentation** | builders-guide.md:1436 | Phase 2+ | Agent | Unspecified location | "Component behavior, business logic rationale, UX decisions" | None | Light — only appears in Appendix A table | **Tier 3 only** | Updated per feature. |
| 17 | **CI/CD Configuration** | builders-guide.md:783-793, 1437; user-guide.md:247-248 | Phase 2, Project Initialization | init.sh generates CI pipeline (language-specific) and release pipeline (platform-specific) | `.github/workflows/ci.yml` and `.github/workflows/release.yml` | YAML (GitHub Actions) | **Yes**: `templates/pipelines/ci/*.yml` and `templates/pipelines/release/*.yml` (language and platform-specific) | Detailed: CI includes linting, tests, SAST, dependency audit, license compliance, lockfile integrity, phase gate check, changelog check, session state check. Release includes build, sign, package, distribute with TODO markers. | **Tier 1 (CI)** — the CI pipeline IS the enforcement mechanism. It blocks merges on SAST, test, dependency, license, and phase gate failures. | Updated during Phase 2 initialization. Modified if secondary languages added. Release pipeline requires per-project configuration of secrets. |
| 18 | **Security Audit Logs** | builders-guide.md:1440; governance.md:925 | Phase 3 | Agent (saves scan results) | `docs/test-results/` — overlaps with #12 | Scan tool output (JSON, SARIF, text) | None | "SAST/DAST results, remediation actions" | **Tier 3 only** | Populated during Phase 3. |
| 19 | **Performance Baselines** | builders-guide.md:1441; governance.md:927 | Phase 3 | Agent | Unspecified — possibly `docs/test-results/` | "Metrics for future comparison" | None | Light — listed in Appendix A but no detail on what metrics or format | **Tier 3 only** | Write-once baseline. Compared against in quarterly maintenance. |
| 20 | **Privacy Policy** | builders-guide.md:1222; user-guide.md:907; governance.md:498 | Phase 3, Step 3.6 (Standard+ with data collection) | Agent drafts; **attorney must review** | Unspecified — web: served from app; desktop/mobile: in-app or linked | Legal document — format unspecified | None | Moderate: must address specific processing activities. Mandatory attorney review before deployment. | **Tier 3 only** — no CI check. Legal checklist in governance framework. | Write-once; updated when data handling changes. |
| 21 | **Terms of Service** | builders-guide.md:1223; governance.md:498 | Phase 3, Step 3.6 (if applicable) | Agent drafts; **attorney must review** | Unspecified | Legal document | None | Light — only mentioned as checklist item | **Tier 3 only** | Write-once. |
| 22 | **.gitignore** | user-guide.md:249, 268; gitignore-base.tmpl | Pre-Phase 0 (by init.sh) | init.sh generates from template | Project root: `.gitignore` | Standard gitignore format | **Yes**: `templates/generated/gitignore-base.tmpl` (~50 lines) | Moderate: covers dependencies, env files, build output, IDE, OS, test, debug, secrets file patterns | None (no enforcement beyond git itself) | Updated as needed. |
| 23 | **.claude/phase-state.json** | user-guide.md:270; claude-md.tmpl:59-63; check-phase-gate.sh | Pre-Phase 0 (by init.sh) | init.sh generates; agent updates at phase transitions | `.claude/phase-state.json` | JSON. Fields: project, framework_version, current_phase, track, deployment, poc_mode, gates (phase_0_to_1, phase_1_to_2, phase_3_to_4) | Generated inline by init.sh:1416-1430 | Detailed: exact schema defined in init.sh | **Tier 1 (CI)**: check-phase-gate.sh enforces consistency with APPROVAL_LOG.md. Blocks merge when out of sync. | Updated at each phase gate transition. Must be committed alongside APPROVAL_LOG.md. |
| 24 | **.claude/build-progress.json** | test-gate.sh:53-68 | Pre-Phase 0 (by init.sh) | init.sh generates; test-gate.sh updates | `.claude/build-progress.json` | JSON. Fields: features_completed, features_since_last_test, test_interval, last_test_session, testing_required, tester_count, bug_tracker, sessions_completed | Generated inline by init.sh:1439-1451 and test-gate.sh:53-68 | Detailed: exact schema in both files | **Tier 2 (hook)**: `scripts/session-test-gate-check.sh` is a SessionStart hook that checks batch status. `scripts/test-gate.sh --check-batch` blocks next feature if interval reached. | Updated by test-gate.sh commands. |
| 25 | **.claude/tool-preferences.json** | init.sh:904-958; check-phase-gate.sh:136-228 | During init.sh tool resolution | init.sh writes | `.claude/tool-preferences.json` | JSON. Fields: schema_version, resolved_at, context, substitutions, additions, skipped, installed | Generated inline by init.sh | Moderate | Used by check-phase-gate.sh for tool resolution at phase transitions. Not CI-enforced. | Write-once during init. |
| 26 | **.claude/settings.json** | init.sh:1192-1215; cli-setup-addendum.md:197-199 | During init.sh | init.sh generates; Development Guardrails modifies | `.claude/settings.json` | JSON. Claude Code permissions and hooks config. | Generated inline by init.sh with language-specific rules | Moderate: allow/deny permission rules, session hooks | None (Claude Code reads it natively) | Updated during init. Hooks added for version check, test gate, Qdrant reminder. |
| 27 | **Compliance Screening Matrix** | governance.md:453-471, 919; user-guide.md:395-398 | Phase 0 (organizational) | Orchestrator + Project Sponsor | Intake Section 8.4 (embedded in PROJECT_INTAKE.md) | Table with Yes/No per regulatory question | Part of `templates/project-intake.md` Section 8 | Detailed: 10 regulatory questions with specific actions per "Yes" answer | **Tier 3 only** | Write-once. Re-evaluated quarterly per governance.md:471. |
| 28 | **In-Phase Decision Log** | governance.md:185-187, 921; user-guide.md:855-856 | Phase 2 (organizational) | Orchestrator | Unspecified location — "maintain a running decision log" | Unspecified — "date, decision, rationale, alternatives considered" | None | Moderate: date, decision, rationale, alternatives. Reviewed at Phase 3 gate. | **Tier 3 only** | Append during Phase 2. Reviewed by Senior Technical Authority at Phase 3 gate. |
| 29 | **Penetration Test Report** | governance.md:259-267, 928 | Phase 3 (Standard+ Track, or as required by policy) | External tester or IT Security | Unspecified — likely `docs/test-results/` | External document | None | N/A — produced by external party | **Tier 3** — governance framework requires it for Standard+ (with IT Security exemption for Standard) and Full Track (no exemption) | Write-once per assessment. |
| 30 | **Handoff Test Results** | governance.md:586-596, 933 | Phase 4 (organizational) | Backup maintainer + Orchestrator | Unspecified | Unspecified — "documented results" | None | Light: time to complete, points where backup got stuck, gaps fixed | **Tier 3 only** | Written once per handoff test. Repeated annually per governance.md:603. |
| 31 | **SECURITY.md** | web.md:260-266; desktop.md:304-312 | Phase 4 (production web and desktop apps) | Agent | Project root: `SECURITY.md` | Markdown. Supported versions, how to report, response time, safe harbor. | None | Moderate: 4 required sections (supported versions, reporting mechanism, response time, safe harbor) | **Tier 3 only** | Write-once. Updated when supported versions change. |
| 32 | **/.well-known/security.txt** | web.md:265 | Phase 4 (production web apps) | Agent | Web route: `/.well-known/security.txt` per RFC 9116 | Text per RFC 9116 | None | Light: points to disclosure email | **Tier 3 only** | Write-once. |
| 33 | **.env.example** | web.md:297 | Phase 2, Project Initialization (web) | Agent | Project root: `.env.example` | Dotenv format | None | Light: "all required environment variables" | **Tier 3 only** | Updated when new env vars added. |
| 34 | **tests/uat/templates/** | builders-guide.md:917; templates/uat-test-template.md | Phase 2 (first UAT session) | init.sh copies template; agent pre-populates per session | `tests/uat/templates/test-session-template.md` | Markdown. Header fields, test scenario tables, bugs found table, severity guide. | **Yes**: `templates/uat-test-template.md` (50 lines) | Detailed: structured template with sections for instructions, test scenarios, bugs found, severity guide, overall notes | **Tier 2**: `scripts/test-gate.sh --check-batch` enforces testing intervals | Template is write-once. Agent creates session-specific versions from template. |
| 35 | **tests/uat/sessions/** (directory structure) | builders-guide.md:917, 928 | Phase 2 (per UAT session) | Agent creates per-session directories | `tests/uat/sessions/<date>-session-N/templates/` and `tests/uat/sessions/<date>-session-N/submissions/` and `tests/uat/sessions/<date>-session-N/agent-results/` | Directory structure with markdown files | None beyond the template (#34) | Moderate: agent-results, templates, submissions subdirectories per session | **Tier 2**: test-gate.sh controls when sessions happen | New directories per session. |
| 36 | **BUGS.md** | test-gate.sh:140-148 | Phase 2 (if using file-based bug tracking) | Agent | Project root: `BUGS.md` | Markdown table: `| # | SEV-N | Status | Feature | Description |` | None — format implied by test-gate.sh grep patterns | Moderate: severity, status (Open, Deferred, Fixed, Won't Fix, Post-MVP, Removed), feature, description | **Tier 2**: test-gate.sh reads BUGS.md for phase gate checks (SEV-1/2 block Phase 2→3) | Append per bug. Status updated as bugs are resolved. |
| 37 | **.claude/framework/** (directory) | user-guide.md:251, 269; claude-md.tmpl:16 | During init.sh | init.sh runs Development Guardrails init | `.claude/framework/` | Git hooks, YAML profiles, JSON manifests | External: claude-dev-framework repo | N/A — external project | **Tier 2 (hooks)**: pre-commit hooks for TDD check, secret detection, SAST, schema migration, changelog | Managed by Development Guardrails framework. |
| 38 | **.claude/manifest.json** | init.sh:1332 | During init.sh (by Development Guardrails) | Development Guardrails init script | `.claude/manifest.json` | JSON | External project | N/A | None (read by Development Guardrails) | Managed by Development Guardrails. |
| 39 | **docs/framework/** (directory) | user-guide.md:251, 271 | During init.sh | init.sh copies from solo-orchestrator repo | `docs/framework/builders-guide.md`, `docs/framework/governance-framework.md`, `docs/framework/executive-review.md`, `docs/framework/cli-setup-addendum.md`, `docs/framework/user-guide.md`, `docs/framework/security-scan-guide.md` | Markdown | Source files from solo-orchestrator docs/ | N/A — reference copies | **validate.sh** checks existence (scripts/validate.sh:51-57) | Write-once copies. Updated via scripts/check-updates.sh. |
| 40 | **evaluation-prompts/Projects/** | user-guide.md:1153-1199; init.sh:1033-1037 | During init.sh | init.sh copies from solo-orchestrator repo | `evaluation-prompts/Projects/` | Markdown prompt files + shell scripts | Source files from evaluation-prompts/Projects/ | N/A — used for Phase 3 validation | **Tier 3 only** | Reference copies. |

### 1.2 Implicit/Underdefined Artifacts

| # | Description | Reference Location | What's Missing |
|---|---|---|---|
| I1 | **Functional Requirements Document (FRD)** | builders-guide.md:268-310; user-guide.md:541-584 | Produced during Step 0.1 but never explicitly saved as a file. It is absorbed into the Product Manifesto. No standalone artifact or filename. |
| I2 | **User Journey Map** | builders-guide.md:322-355; user-guide.md:586-611 | Produced during Step 0.2 but no standalone file. Absorbed into the Product Manifesto. |
| I3 | **Data Contract** | builders-guide.md:359-392; user-guide.md:614-638 | Produced during Step 0.3 but no standalone file. Absorbed into the Product Manifesto. |
| I4 | **Revenue Model / Unit Economics** | builders-guide.md:432-438 | "Save as: Appendix to PRODUCT_MANIFESTO.md" — location specified but it's a section, not a file. |
| I5 | **Orchestrator Competency Matrix** | builders-guide.md:446-469 | "Save as: Appendix to PRODUCT_MANIFESTO.md" — location specified but it's a section, not a file. |
| I6 | **Threat Model & Risk/Mitigation Matrix** | builders-guide.md:567-590 | Called an "artifact" (line 588) but no filename specified. Presumably lives inside PROJECT_BIBLE.md Section 4. |
| I7 | **Data Migration Plan** | builders-guide.md:609-621 | "Included in the Project Bible" — no standalone file. Skipped if no legacy data. |
| I8 | **Architecture Stress Test** | builders-guide.md:581-588 | Part of Step 1.3 output, folded into Threat Model. No standalone file. |
| I9 | **Go/No-Go Assessment** | builders-guide.md:511-513 | Decision gate in Step 1.1 — outcome recorded but no artifact. |
| I10 | **Market Signal Validation** | builders-guide.md:517-521 | "Performed by the Orchestrator, not the AI." No artifact format, no file, no template. |
| I11 | **Trademark Search Results** | builders-guide.md:473-478; governance.md:423-426 | "Document findings in the Product Manifesto" — no standalone format. |
| I12 | **Credential Inventory** | governance.md:351 | "Maintain a credential inventory in the Project Bible (Section: Infrastructure)" — embedded in Bible, no standalone tracking. |
| I13 | **Launch Plan** | exec-review.md:194 | Listed as Phase 3 output artifact in executive review but not mentioned anywhere else in the framework. No definition, no template, no format. |
| I14 | **Monitoring Integration** | exec-review.md:202 | Listed as Phase 4 output artifact in executive review. Refers to configuration, not a document. |
| I15 | **CSP Policy Documentation** | web.md:164-165 | "Document the policy in the Project Bible" — embedded, no standalone. |
| I16 | **Data Handling on Uninstall Documentation** | desktop.md:346-352 | "Define and document" — no file specified. |
| I17 | **Health Check Endpoint** | web.md:298 | `/health` returning 200 — code artifact, not document. |
| I18 | **Deployment Strategy Documentation** | builders-guide.md:1262-1273 | "Document the chosen strategy in the Project Bible" — embedded. |
| I19 | **Lighthouse Report** | builders-guide.md:1191; web.md:152-153 | "Lighthouse HTML report" — saved to docs/test-results/ but no enforcement. |

---

## Part 2: Enforcement Audit

### 2.1 Has Template + Has Enforcement (Fully Covered)

| Artifact | Template | Enforcement |
|---|---|---|
| **APPROVAL_LOG.md** | `templates/generated/approval-log-org.tmpl`, `approval-log-personal.tmpl` | `scripts/check-phase-gate.sh` (CI — blocks merge when out of sync with phase-state.json) |
| **CI/CD Configuration** | `templates/pipelines/ci/*.yml`, `templates/pipelines/release/*.yml` | Self-enforcing — the pipeline IS the enforcement |
| **.claude/phase-state.json** | Generated inline by init.sh | `scripts/check-phase-gate.sh` (CI — cross-referenced with APPROVAL_LOG.md) |

### 2.2 Has Template + No Enforcement (Template Exists, Nothing Checks)

| Artifact | Template | Gap |
|---|---|---|
| **CLAUDE.md** | `templates/generated/claude-md.tmpl` | `check-session-state.sh` only checks freshness (staleness warning), not content correctness or completeness. No check that required sections exist. |
| **PROJECT_INTAKE.md** | `templates/project-intake.md` | No script checks that the Intake is filled out before Phase 0. The agent is told to flag blanks, but nothing mechanically enforces this. |
| **.gitignore** | `templates/generated/gitignore-base.tmpl` | No enforcement. Git ignores work natively. |
| **UAT Test Template** | `templates/uat-test-template.md` | test-gate.sh enforces testing intervals but does not check that the template was used or submissions exist. |
| **.claude/build-progress.json** | Generated by init.sh | test-gate.sh uses it but nothing prevents the file from being manually edited or deleted. |

### 2.3 No Template + Has Enforcement

| Artifact | Enforcement | Gap |
|---|---|---|
| **CHANGELOG.md** | `scripts/check-changelog.sh` (CI annotation — warns on source changes without changelog update; upgradable to block) | No template. No specified format (e.g., Keep a Changelog). The check only verifies the file was modified, not that the entry is meaningful. |
| **BUGS.md** | `scripts/test-gate.sh --check-phase-gate` reads BUGS.md for SEV-1/SEV-2 counts | No template. Format is implied by grep patterns in test-gate.sh (expects `SEV-N.*Status` pattern in table rows). |

### 2.4 No Template + No Enforcement (Completely Unguided)

| Artifact | Gap |
|---|---|
| **PRODUCT_MANIFESTO.md** | No template, no CI check for existence, no format verification. Content spec exists in Builder's Guide but nothing mechanically enforces it. |
| **PROJECT_BIBLE.md** | No template, no CI check for existence, no format verification. 16 required sections defined in Builder's Guide but nothing checks for them. |
| **HANDOFF.md** | No template, no enforcement. 9 required sections listed but not checked. |
| **docs/INCIDENT_RESPONSE.md** | No template, no enforcement. |
| **RELEASE_NOTES.md** | No template, no enforcement. |
| **USER_GUIDE.md** | No template, no enforcement. |
| **Architecture Decision Records** | No template, no naming convention, no directory, no enforcement. |
| **Interface Documentation** | No template, no location specified, no enforcement. |
| **Feature Documentation** | No template, no location specified, no enforcement. |
| **Security Audit Logs** | No template. Goes in docs/test-results/ by convention. |
| **Performance Baselines** | No template, no format, no enforcement. |
| **sbom.json** | No template (tool-generated). No CI check verifying it exists. |
| **SECURITY.md** | No template, no enforcement. |
| **In-Phase Decision Log** | No template, no location, no format enforcement. |
| **Penetration Test Report** | External document. No template (expected). |
| **Handoff Test Results** | No template, no format, no enforcement. |
| **Privacy Policy / Terms of Service** | No template. Legal review mandated but not mechanically checked. |
| **CONTRIBUTING.md** | No template, no enforcement. |
| **.env.example** | No template (web-specific), no enforcement. |
| **Compliance Screening Matrix** | Part of Intake template but no standalone enforcement. |
| **docs/test-results/** contents | No enforcement that specific files exist. Directory created empty by init.sh. |

---

## Part 3: Cross-Reference Gaps

### 3.1 Naming Disagreements

| Artifact | Builder's Guide | User Guide | Governance Framework | Executive Review | CLAUDE.md Template |
|---|---|---|---|---|---|
| **Project Intake** | `PROJECT_INTAKE.md` (consistent) | `PROJECT_INTAKE.md` (consistent) | "Project Intake Template" (document reference) | "Project Intake Template (SOI-004-INTAKE)" | `PROJECT_INTAKE.md` |
| **Approval Log** | `APPROVAL_LOG.md` (consistent) | `APPROVAL_LOG.md` (consistent) | `APPROVAL_LOG.md` (consistent) | Not named | `APPROVAL_LOG.md` |

No naming disagreements found across documents. Naming is consistent.

### 3.2 "When Created" Disagreements

| Artifact | Builder's Guide | Executive Review | Governance Framework |
|---|---|---|---|
| **Launch Plan** | Not mentioned | Listed as Phase 3 output (exec-review.md:194) | Not mentioned |
| **Monitoring Integration** | Phase 4, Step 4.3 (configuration, not a doc) | Listed as Phase 4 output (exec-review.md:202) | Not mentioned |
| **CONTRIBUTING.md** | Phase 2, Project Initialization (builders-guide.md:766) | Not mentioned | Not mentioned |

### 3.3 Content Disagreements

| Topic | Builder's Guide | Governance Framework | Gap |
|---|---|---|---|
| **Appendix A artifact list** | 15 artifacts listed (builders-guide.md:1427-1446) | 16 artifacts listed (governance.md:913-934) — adds: Compliance Screening Matrix, Penetration Test Report, Handoff Test Results | Governance adds 3 artifacts not in Builder's Guide Appendix A |
| **Performance Baselines** | Listed in Appendix A (builders-guide.md:1441) — "Metrics for future comparison" | Listed (governance.md:927) — "Performance baseline evidence" | Consistent description but no concrete spec in either |
| **Handoff Test Results** | Described in prose (builders-guide.md:1391-1392) but not in Appendix A | Listed as explicit artifact (governance.md:933) | Builder's Guide omits from Appendix A |
| **Compliance Screening Matrix** | Referenced at builders-guide.md:249, 493 but not in Appendix A | Listed as explicit artifact (governance.md:919) | Builder's Guide omits from Appendix A |

### 3.4 Location Disagreements

| Artifact | Claimed Location | Actual Location (per init.sh/templates) |
|---|---|---|
| **sbom.json** | builders-guide.md:1439 lists it at project root as `sbom.json` | builders-guide.md:1189 says save in `docs/test-results/`. web.md:306 generates via `--output-file sbom.json` (project root). Inconsistent. |
| **Security Audit Logs** | builders-guide.md:1440 says `Phase 3` — no directory specified | builders-guide.md:1183-1196 specifies `docs/test-results/` directory | Appendix A doesn't specify directory; prose does. |

---

## Part 4: Platform Module-Specific Artifacts

### 4.1 Web Platform Module (`web.md`)

| Artifact | Reference | In Core Guide? |
|---|---|---|
| **`.env.example`** | web.md:297 | No — web-specific. Not in Builder's Guide or Appendix A. |
| **Health check endpoint (`/health`)** | web.md:298 | No — code artifact, web-specific. |
| **CORS configuration** | web.md:299 | No — code artifact, web-specific. |
| **CSP policy** | web.md:160-165, 305 | Referenced in governance.md:309 but not in Appendix A. |
| **SECURITY.md** | web.md:260-266 | No — not in Builder's Guide or Appendix A. |
| **`/.well-known/security.txt`** | web.md:265 | No — web-specific. |
| **Lighthouse report** | web.md:152-153 | Referenced in builders-guide.md:1191 as part of docs/test-results/. Not a standalone artifact. |
| **DAST scan results (ZAP report)** | web.md:136-146, 305 | Referenced in builders-guide.md:1187 as part of docs/test-results/. |
| **SBOM (npm-specific)** | web.md:306 | In core guide (sbom.json). Web module specifies the npm-specific command. |
| **Application sunsetting documentation** | web.md:270-278 | No — web-specific lifecycle procedure. Not an artifact per se. |

### 4.2 Desktop Platform Module (`desktop.md`)

| Artifact | Reference | In Core Guide? |
|---|---|---|
| **SECURITY.md** | desktop.md:304-312 | No — not in core Builder's Guide Appendix A. |
| **Platform-specific testing checklist** | desktop.md:225-255 | No — extends core Phase 3.1. Not a document artifact. |
| **Code signing certificates** | desktop.md:189-198 | Mentioned in exec-review.md:259 but not as a document artifact. Infrastructure, not documentation. |
| **Data handling on uninstall documentation** | desktop.md:346-352 | No — desktop-specific. "Define and document" but no file specified. |
| **Checksums for download artifacts** | desktop.md:341 | No — desktop-specific release artifact. |

### 4.3 Mobile Platform Module (`mobile.md`)

| Artifact | Reference | In Core Guide? |
|---|---|---|
| **`eas.json`** | mobile.md:360-396 | No — Expo-specific build configuration. |
| **Fastlane configuration (Fastfile)** | mobile.md:703-762 | No — mobile-specific CI/CD. |
| **Apple provisioning profiles / certificates** | mobile.md:440-469 | Infrastructure artifacts, not documentation. |
| **Android keystore** | mobile.md:478-509 | Infrastructure artifact — CRITICAL: "if you lose it, you cannot update your app." |
| **App Store/Play Store listing metadata** | Implied throughout mobile.md | Not explicitly listed as an artifact anywhere. |

---

## Part 5: Implicit Artifacts

These are things the framework says to "document" or "record" without specifying a file, location, or format.

| # | What's Described | Where Mentioned | What's Missing |
|---|---|---|---|
| I1 | "Document the rationale for rejecting" alternative architectures | builders-guide.md:559 | Where? In an ADR? In the Bible? No specific location. (The Bible Section 3 is the intended home, but this is not explicitly stated at the point of instruction.) |
| I2 | "Document the risk acceptance" for unpatched dependency | builders-guide.md:876; governance.md:336 | Where? No specified file. Probably docs/test-results/ or an ADR. |
| I3 | "Document the AI data transmission policy" | governance.md:229-242 | Where? Mentioned as a "mandatory decision at Phase 1" — no artifact name. Presumably in the Bible under a section. |
| I4 | "Record the review date and outcome" for biweekly Phase 2 checkpoints | builders-guide.md:991 | Where? "In the in-phase decision log" — which itself has no specified location or format. |
| I5 | "Maintain a credential inventory in the Project Bible" | governance.md:351 | What section? No template for the inventory. No reminder to create it. |
| I6 | "Record the [quarterly portfolio] review" | governance.md:609, 697 | Where? ITSM system mentioned. No project-level artifact. |
| I7 | "Document the deletion" of production databases | web.md:276 | "Document deletion in the APPROVAL_LOG.md" — location specified. This one is actually defined. |
| I8 | "Log maintenance activities" | governance.md:631 | "In the project's CHANGELOG.md or ITSM system" — two options, no guidance on which. |
| I9 | "Define exit criteria" for pilot | governance.md:865 | Collected in Intake Section 8.5. Documented there, but not tracked against. |
| I10 | "Deployment strategy" choice | builders-guide.md:1273 | "Document the chosen strategy in the Project Bible" — which section? Not specified. |
| I11 | "Market signal" documentation | builders-guide.md:517-521 | "Performed by the Orchestrator, not the AI" — no format, no storage location, no artifact. |
| I12 | "Insurance confirmation letter" | governance.md:447 | Referenced as "gating artifact for Phase 0 approval" but stored only as a reference in APPROVAL_LOG.md. The letter itself has no defined location. |
| I13 | "Written approval" for AI deployment path | governance.md:236 | Stored as reference in APPROVAL_LOG.md. Original document location unspecified. |

---

## Part 6: CLAUDE.md Template vs. Builder's Guide Alignment

### 6.1 What CLAUDE.md Template Tells the Agent to Produce

The CLAUDE.md template (`templates/generated/claude-md.tmpl`) instructs the agent to:

1. Follow the Builder's Guide phases in sequence (line 52)
2. Update APPROVAL_LOG.md at phase gates (lines 57-64)
3. Update `.claude/phase-state.json` at phase gates (line 62)
4. Write failing tests before implementation (line 69)
5. Complete full Build Loop per feature (line 70)
6. Pin dependencies to exact versions (line 71)
7. Implement structured logging (line 72)
8. Use versioned migrations for data model changes (line 73)
9. Update CHANGELOG.md, API docs, and Project Bible after every feature (line 74)
10. Run UAT sessions per test interval (lines 141-155)
11. Record features via test-gate.sh (line 153)
12. Use specific agent personas at specific phases (lines 124-138)
13. Store/retrieve from Qdrant at specific points (lines 106-115)

### 6.2 What Builder's Guide Requires But CLAUDE.md Template Does NOT Mention

| Requirement | Builder's Guide Location | Missing From CLAUDE.md |
|---|---|---|
| **CONTRIBUTING.md generation** | builders-guide.md:766 | CLAUDE.md references `@./CONTRIBUTING.md` (line 428 of cli-setup-addendum template) but starter template doesn't instruct the agent to generate it. |
| **Context Health Check every 3-4 features** | builders-guide.md:970-978 | Not mentioned in claude-md.tmpl. The enhanced template in cli-setup-addendum.md does not mention it either. |
| **HANDOFF.md generation** | builders-guide.md:1378-1393 | Not mentioned in claude-md.tmpl. Agent is expected to know from the Builder's Guide. |
| **INCIDENT_RESPONSE.md generation** | builders-guide.md:1283-1297 | Not mentioned in claude-md.tmpl. |
| **RELEASE_NOTES.md generation** | builders-guide.md:1327-1333 | Not mentioned in claude-md.tmpl. |
| **USER_GUIDE.md generation** | builders-guide.md:1215-1217 | Not mentioned in claude-md.tmpl. |
| **SECURITY.md generation** | web.md:260-266; desktop.md:304-312 | Not mentioned in claude-md.tmpl. Platform-specific. |
| **sbom.json generation** | builders-guide.md:1096 | Not mentioned in claude-md.tmpl. |
| **docs/test-results/ archival** | builders-guide.md:1183-1197 | Not mentioned in claude-md.tmpl. |
| **Phase 2 Completion Checkpoint** (checklist) | builders-guide.md:1005-1017 | Not mentioned in claude-md.tmpl. |
| **Phase 3.6 Pre-Launch Preparation** | builders-guide.md:1201-1226 | Not mentioned in claude-md.tmpl. |
| **Mandatory Rollback Test** | builders-guide.md:1298-1308 | Not mentioned in claude-md.tmpl. |
| **Go-Live Verification checklist** | builders-guide.md:1312-1323 | Not mentioned in claude-md.tmpl. |

### 6.3 What CLAUDE.md Template Mentions But Builder's Guide Does NOT Explicitly Require

| CLAUDE.md Instruction | Notes |
|---|---|
| **Engineering Principles / Priority Hierarchy** (claude-md.tmpl:20-36) | This 6-level priority hierarchy (Security > Correctness > Stability > Performance > Usability > Speed) is original to the CLAUDE.md template. Not stated in the Builder's Guide. It is a reasonable addition, not a conflict. |
| **"Best Practices Over Shortcuts"** (claude-md.tmpl:33-37) | Original to CLAUDE.md template. Not contradicted by Builder's Guide. |
| **Upgrade Paths section** (claude-md.tmpl:117-122) | Documents scripts that exist but are not discussed in the Builder's Guide methodology. |
| **Session hooks** (session-version-check.sh, session-test-gate-check.sh, session-end-qdrant-reminder.sh) | Created by init.sh but not mentioned in the Builder's Guide. The User Guide mentions the version check (user-guide.md:467-484) and resume.sh. |

---

## Part 7: Missing Enforcement Recommendations

### 7.1 Phase Gate Checks (Should Block Phase Transition)

| Artifact | Current State | Recommended Enforcement |
|---|---|---|
| **PRODUCT_MANIFESTO.md** | No existence check | `check-phase-gate.sh` should verify the file exists before allowing Phase 0→1 transition |
| **PROJECT_BIBLE.md** | No existence check | `check-phase-gate.sh` should verify the file exists before allowing Phase 1→2 transition |
| **HANDOFF.md** | No existence check | `check-phase-gate.sh` should verify the file exists before allowing Phase 3→4 transition |
| **docs/INCIDENT_RESPONSE.md** | No existence check | `check-phase-gate.sh` should verify the file exists before allowing Phase 3→4 transition |
| **docs/test-results/ non-empty** | Directory created empty by init.sh, never checked | `check-phase-gate.sh` should verify at least one scan result file exists in `docs/test-results/` before Phase 3→4 |
| **sbom.json** | No existence check | `check-phase-gate.sh` should verify existence before Phase 3→4 |

### 7.2 CI Checks (Should Block Merge)

| Artifact | Current State | Recommended Enforcement |
|---|---|---|
| **CHANGELOG.md format** | `check-changelog.sh` only checks that the file was modified, not content quality | Consider checking for a date header or version marker — but this may be overengineering |
| **Lockfile integrity** | Builder's Guide says "lockfile integrity verification" in CI (builders-guide.md:791) but no script exists for this | Add a CI step that verifies lockfile hash matches (npm: `npm ci` fails on mismatch; this is already covered implicitly) |

### 7.3 Pre-Commit Hook (Should Warn or Block)

| Artifact | Current State | Recommended Enforcement |
|---|---|---|
| **TDD co-location** | Development Guardrails already checks this (cli-setup-addendum.md:221) | Already partially covered. |
| **Schema migration check** | Development Guardrails checks this (cli-setup-addendum.md:227) | Already covered. |

### 7.4 Session Start Check (Should Remind)

| Artifact | Current State | Recommended Enforcement |
|---|---|---|
| **Context Health Check** | Not enforced. Builder's Guide says "every 3-4 features." | Could add a counter to build-progress.json and a session hook that reminds after every 3rd feature. |
| **PROJECT_INTAKE.md completeness** | Not checked | Session hook could check for blank table cells in PROJECT_INTAKE.md and warn |
| **CLAUDE.md "Current State" section** | `check-session-state.sh` checks freshness by commit count/time | Already partially covered. |

### 7.5 No Enforcement Needed (Truly Optional or One-Time)

| Artifact | Rationale |
|---|---|
| **Architecture Decision Records** | Created ad hoc per decision. No fixed cadence. Enforcing would be impractical. |
| **Interface Documentation** | Updated per feature within the Build Loop. Enforcing separately from the code would create friction without proportional benefit. |
| **Feature Documentation** | Same as above. |
| **Performance Baselines** | One-time Phase 3 output. Value is in the data, not in enforcement. |
| **Privacy Policy / Terms of Service** | Legal review requirement is organizational, not mechanical. |
| **Penetration Test Report** | External deliverable. Cannot be mechanically enforced. |
| **In-Phase Decision Log** | Phase 2 organizational requirement. Reviewed at gate, not enforced per-commit. |
| **CONTRIBUTING.md** | Write-once. Low value in enforcing existence beyond initial generation. |
| **RELEASE_NOTES.md** | Phase 4 artifact. Could be checked at tag-time in release pipeline. |
| **SECURITY.md** | Platform-specific. Could be added to validate.sh as a warning for web/desktop projects. |
| **.env.example** | Web-specific. Low enforcement value. |
| **Credential Inventory** | Embedded in Project Bible. No standalone enforcement needed. |

---

## Summary Statistics

| Category | Count |
|---|---|
| **Total distinct artifacts identified** | 40 named + 19 implicit = 59 |
| **Have template** | 8 (APPROVAL_LOG org/personal, CLAUDE.md, PROJECT_INTAKE, .gitignore, CI/CD pipelines, UAT template, phase-state.json, build-progress.json) |
| **Have CI enforcement** | 4 (APPROVAL_LOG via phase-gate check, CI pipeline self-enforcing, phase-state.json via phase-gate check, CHANGELOG via warning) |
| **Have template + enforcement** | 3 (APPROVAL_LOG, CI/CD, phase-state.json) |
| **Have neither template nor enforcement** | 28+ |
| **Artifacts in Builder's Guide Appendix A** | 15 |
| **Artifacts in Governance Framework Section XV** | 16 (adds Compliance Screening Matrix, Pen Test Report, Handoff Test Results) |
| **Appendix A vs. Governance XV delta** | 3 artifacts in Governance not in Builder's Guide |
| **Executive Review artifacts not elsewhere defined** | 1 ("Launch Plan" — exec-review.md:194 — undefined elsewhere) |
| **Platform-module-specific artifacts not in core guide** | 7 (.env.example, SECURITY.md, security.txt, checksums, eas.json, Fastlane config, data-handling-on-uninstall docs) |

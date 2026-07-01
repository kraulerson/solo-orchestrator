# workflow.html Validation Report

**Date:** 2026-07-01
**Branch:** `docs/workflow-html-validation`
**Scope:** Cross-check `workflow.html` (the operator-facing journey diagram) against `docs/user-guide.md`, `docs/builders-guide.md`, `docs/governance-framework.md`, `docs/audit-log-lifecycle.md`, `README.md`, and the scripts under `scripts/`, `evaluation-prompts/Projects/`, and `templates/`. Special focus on Phase 3 governance / sign-off / audit-trail content (Karl's explicit ask) and Phase 3 → 4 gate mechanics.

## Executive Summary

Five parallel readers surveyed the docs vs. the scripts and produced a consolidated set of additions, corrections, and flagged discrepancies. The pass added substantive Phase 3 governance content (Application Owner + IT Security dual sign-off, attorney review for Privacy Policy + ToS, penetration-test track branching, artifact roster, snapshot mechanism) and inserted three previously-missing phase-gate rows (1 → 2, 2 → 3, 3 → 4) plus a Pre-Phase 0 organizational pre-conditions row. The largest single content addition is a dedicated Gate 3 → 4 row with the full check-phase-gate.sh check surface and the governance sign-off structure. Corrections landed against a dozen materially wrong or misleading claims, most notably the POC "upgrade later" phrasing (Phase 4 is hard-blocked, not deferred), the "test-first via pre-commit hooks" claim (TDD ordering is warning-only per README §Enforcement), the "phase-state.json auto-write" claim (no script writes gate dates), and the maintenance cadence (weekly does not exist; actual cadences are monthly / quarterly / biannually). Twelve discrepancies remain flagged — nine where the docs claim behaviour that the scripts do not implement (Snyk / license / OWASP ZAP / full-tree Semgrep / threat-model verification runtime automation, plus phase-state.json gate-date auto-write), and three where governance surfaces need doc clarification.

## Additions landed in workflow.html

- **Pre-Phase 0 Organizational Pre-Conditions row** (new gate row) — enumerates the six named APPROVAL_LOG rows (AI deployment path, Insurance, Liability, Sponsor, Backup maintainer, ITSM) and the POC-mode deferral matrix (Sponsored POC = rows 1&4 required; Private POC = all six deferred). Cites `governance-framework.md §V & §IX.4` and `templates/generated/approval-log-org.tmpl:16-28`.
- **Gate 1 → 2 row** (new gate row) — dated APPROVAL_LOG entry, PROJECT_BIBLE ≥14 sections, mandatory ZDR gate (Invariant #16) with 7-tier data classification, branch-protection API backstop with free-tier attestation escape hatch, Retroactive STA approval WARN. Signoff: STA for organizational.
- **Gate 2 → 3 row** (new gate row) — dated APPROVAL_LOG entry, FEATURES.md + CHANGELOG.md existence, bug gate (SEV-1 open blocks; SEV-2 open OR deferred blocks; SEV-3 WARN), MVP Cutline reconciliation. Signoff: STA for organizational.
- **Gate 3 → 4 row** (new gate row, Karl's primary ask) — complete governance sign-off structure: Application Owner + IT Security dual approval for organizational, Attorney/Legal review, ITSM ticket, full artifact roster (HANDOFF.md, INCIDENT_RESPONSE.md, sbom.json, docs/test-results/, SECURITY.md, review manifest), penetration test track branching (Standard: exemption path; Full: none), POC hard-block with upgrade-project.sh remediation, snapshot creation to `docs/snapshots/phase-3-to-4_YYYY-MM-DD/`.
- **Phase 3 substep decomposition** — 3.1 Integration Testing, 3.2 Security Hardening, 3.3 Chaos & Edge-Case, 3.4 UX & A11y (WCAG AA / Lighthouse ≥90), 3.5 Performance, 3.5.5 Contract (Std+), 3.5.7 Load/Stress (Full), 3.5.9 Test Results Archive, 3.6 Pre-Launch Preparation with MANDATORY attorney review of Privacy Policy + ToS.
- **Phase 3 sign-off structure** — Application Owner + IT Security dual approval for organizational deployments named explicitly on the Phase 3 left panel; Security Peer Review requirement for competency-gated orchestrators; six-evaluation-prompts reframed as operator-invoked via `run-reviews.sh` with correct persona names (SVP IT Security, Corporate Legal).
- **Phase 4 substep decomposition** — MANDATORY rollback test (Step 4.1.5), MANDATORY monitoring test-error verification (Step 4.3), PLATFORM MODULE MANDATORY go-live checklist (Step 4.2), deployment strategy matrix (cut-over / blue-green / rolling / feature flags).
- **Phase 4 organizational rows** — file ITSM deployment ticket + backup maintainer validates HANDOFF.md by fresh clone + full build/test/scan/deploy cycle.
- **Phase 4 outputs expanded** — HANDOFF.md, INCIDENT_RESPONSE.md (with SEV-1..SEV-4 severity matrix), Phase 4 Completion row in APPROVAL_LOG.
- **Phase 1 substep enumeration** — 1.1 Business Strategy Gateway (Std+), 1.1.5 Market Signal Validation, 1.2 Architecture & Stack (3 candidates, 10 first-class decisions), 1.3 STRIDE Threat Model, 1.4 Data Model, 1.4.5 Data Migration Plan (if replacing existing), 1.5 UI/UX four-state, 1.6 Project Bible 16 sections, 1.7 Data Classification & ZDR Attestation.
- **Phase 0 substep enumeration** — 0.1 FRD → 0.7 Trademark & Legal (Std+). Compliance Screening Matrix (SOX / PCI / GDPR / HIPAA / GLBA / SEC / EU-AI-Act) called out for organizational sponsors.
- **Mid-Phase 2 Governance Checkpoint** — biweekly STA review for organizational deployments with escalation triggers.
- **Cross-cutting cards added**: Enforcement Level (strict / light / no), Bypass Audit Ledger (`.claude/bypass-audit.json` — 7 row types, W7 successor recipes), Pending-Approval Sentinel (`.claude/pending-approval.json`), Gate Denial Path (2-cycle rework limit).
- **Glossary entries added**: Sponsored POC, Private POC, Track (Light/Standard/Full), Enforcement Level, ZDR, APPROVAL_LOG.md, Phase Gate Snapshot, Bypass Audit Ledger, Anti-Self-Approval Check. "Claude Dev Framework" glossary entry renamed to "Development Guardrails for Claude Code".
- **State-file enumeration** — Step 1 right column now names all three state files: `phase-state.json`, `.claude/process-state.json`, `.claude/manifest.json` (previously only phase-state.json was surfaced).

## Corrections landed in workflow.html

- **"Installs security tools: Semgrep, gitleaks, Snyk, Lighthouse, OWASP ZAP"** → softened to reflect resolver-driven, platform-scoped (Lighthouse + ZAP only for web) tool matrix that init.sh offers interactively.
- **"Claude Dev Framework" naming** → updated to "Development Guardrails for Claude Code" in Step 1 right column and glossary (retains CDF as an alias since scripts still reference it).
- **"track (POC or production)" at intake** → corrected to four independent axes: deployment (personal/organizational), track (Light/Standard/Full), POC mode (production / Sponsored POC / Private POC), enforcement level (strict/light/no).
- **Phase 0 "Drafts an initial threat model preview"** → removed. STRIDE threat model is a Phase 1.3 artifact, not Phase 0.
- **Gate 0 → 1 "sponsor also signs" wording** → replaced with the actual governance rule: Project Sponsor is the sole named approver for organizational Phase 0 → 1; approver (not orchestrator) must author the sign-off commit.
- **Gate 0 → 1 "Updates phase-state.json::gates.phase_0_to_1 with today's date"** → corrected to reflect reality: `check-phase-gate.sh` *reads* both dates and reports mismatch; the JSON value itself is populated by the approver during the sign-off commit or by `scripts/upgrade-project.sh`, not by the gate script.
- **Gate 0 → 1 "verifies the right person signed on the right line"** → made specific: organizational deployments run `git blame --line-porcelain` against the approver row and FAIL on self-approval. Personal deployments skip this.
- **Gate 0 → 1 Manifesto completeness** → added the specific check: `Status: Open` lines cause FAIL; all 8 sections must have content beyond placeholders.
- **Phase 2 "Enforces test-first via pre-commit hooks — you can't commit implementation without tests"** → corrected. TDD file-ordering is warning-only (per README §Enforcement / L531). Only `feat:` commits require Build Loop steps 1–5 complete; `chore:` / `fix:` / etc. bypass. `--no-verify` bypass is captured in `.claude/bypass-audit.json`.
- **Phase 2 "Blocks Phase 2 → 3 if any SEV-1 or SEV-2 bug is still open"** → expanded to include SEV-2 *deferred* (must be resolved or feature removed; no third option).
- **Phase 3 "Zero critical findings required"** → restored "Zero Critical or High-severity findings" per user-guide §Phase 3.
- **Phase 3 "Runs the six evaluation prompts"** → reframed as operator-invoked via `evaluation-prompts/Projects/run-reviews.sh <module>`, and clarified that `check-phase-gate.sh` only WARNs (not FAILs) when the review manifest is missing. Persona names corrected: "security auditor" → "SVP IT Security", "legal" → "Corporate Legal".
- **Phase 3 "Full SAST scan across every file" / "Dependency scan (Snyk)" / "License compliance check" / "Web projects: DAST scan"** → reframed as operator-run scans that the framework archives to `docs/test-results/`, not framework-automated invocations. See flagged discrepancies below.
- **Phase 4 "POC path: confirm the deployable artifact; upgrade later if you want to go live"** → replaced with the actual hard-block behaviour: Phase 4 is blocked at both `check-phase-gate.sh` and `process-checklist.sh --start-phase4`. `upgrade-project.sh --to-production` must run FIRST.
- **Phase 4 maintenance cadence "weekly / monthly / quarterly"** → corrected to monthly / quarterly / biannually per `scripts/check-maintenance.sh` (no weekly cadence exists in the script; biannually is the audit-relevant cadence that triggers full Phase 3 re-run + AI provider terms verification).
- **Phase 4 outputs missing HANDOFF.md and INCIDENT_RESPONSE.md** → added.
- **Cross-cutting audit-trail card** → expanded to name `.claude/bypass-audit.json` and the successor-handoff (W7) jq recipes.
- **Cross-cutting Context7 + Qdrant cards** → clarified that these enforce only when configured as MCP servers (one call per session, not per library).
- **Build Loop steps** — Steps 5–9 reframed to align with the six mechanically-enforced Build Loop steps (`tests_written` → `feature_recorded`) and a "Enforced vs documented" callout added.

## Flagged discrepancies (doc says X, scripts do Y)

The following are gaps where either the documentation asserts framework behaviour that the scripts do not implement, or the scripts implement behaviour that the documentation does not describe. Each is a candidate for either a BL entry, a doc correction, or accepted-gap status; **filing new BL entries is left to Karl** per the task discipline.

### 1. Phase 3 auto-run of scans (Snyk / license / OWASP ZAP / full-tree Semgrep / threat-model mitigation verification)

- **Severity:** major
- **What docs say:** workflow.html Phase 3 (pre-edit), builders-guide.md, and user-guide.md all imply Phase 3 performs a full SAST scan across every file, dependency scan (Snyk), license compliance check, DAST scan (OWASP ZAP against a running instance), six evaluation prompts, and verification that every threat-model mitigation is implemented and tested.
- **What scripts do:** No script anywhere invokes `snyk test`, no license-compliance scan runs, no OWASP ZAP invocation exists (only a competency-matrix substring check in `validate.sh:457`), and no full-tree Semgrep runs (the pre-commit hook only scans staged files). `check-phase-gate.sh` only *searches* for artifact filenames matching `*snyk*` / `*pen-test*` / `*zap*` in `docs/test-results/`. No script cross-references PROJECT_BIBLE STRIDE threat vectors against the test suite.
- **Recommendation:** File a BL entry (per Reader B). Two paths: (a) wire the scans into a Phase 3 driver script that invokes them and archives outputs, or (b) reword the docs (builders-guide.md, user-guide.md) to say "you run these scans; the framework archives them." The workflow.html edit already softens the wording, but the source docs still assert framework-auto-run.

### 2. `phase-state.json::gates.phase_N_to_M` auto-write

- **Severity:** major
- **What docs say:** workflow.html Gate 0 → 1 previously claimed the gate script writes `today` to `.gates.phase_0_to_1`. Builder's Guide and User Guide describe gate dates as living in phase-state.json.
- **What scripts do:** `check-phase-gate.sh` only *reads* the field. `validate.sh` only reads. `init.sh` seeds null. No jq assignment expression exists anywhere. The date is populated manually (or via `scripts/upgrade-project.sh`).
- **Recommendation:** File a BL entry to either (a) add auto-write to check-phase-gate.sh on PASS, or (b) surface in docs that the date is operator-authored. The workflow.html edit takes path (b) provisionally.

### 3. `init.sh` seeds phase-state.json with only three gate keys (`phase_2_to_3` omitted)

- **Severity:** minor
- **What docs say:** APPROVAL_LOG.md templates have a Phase 2 → 3 section; `check-phase-gate.sh:273` and `validate.sh:341` both read the `phase_2_to_3` key as canonical.
- **What scripts do:** `init.sh:1789-1804` seeds only `phase_0_to_1`, `phase_1_to_2`, `phase_3_to_4`. `verify-install.sh:844-847` seeds all four correctly (fixup path). New projects silently fall back to the APPROVAL_LOG text scan.
- **Recommendation:** File a small BL entry to fix `init.sh` to seed all four gate keys, matching verify-install.sh.

### 4. Phase 3 six evaluation prompts framing

- **Severity:** major
- **What docs say:** workflow.html (pre-edit) said the framework "Runs the six evaluation prompts". User Guide §8.2 and Builder's Guide L1656 frame them as operator-invoked; Builder's Guide additionally scopes the mandatory prompts to Security + Red Team for Full Track only.
- **What scripts do:** `evaluation-prompts/Projects/run-reviews.sh` is a standalone operator-invoked script. `check-phase-gate.sh:1039-1056` WARNs only when the manifest is missing. `process-checklist.sh` Phase 3 steps do not include "six evaluation prompts complete".
- **Recommendation:** Doc clarification landed in workflow.html. Also worth considering a doc-only sweep in builders-guide.md L1656 to clearly distinguish "recommended for Standard" vs "REQUIRED for Full" (currently reads slightly ambiguous).

### 5. TDD ordering enforcement scope

- **Severity:** major
- **What docs say:** workflow.html (pre-edit): "Enforces test-first via pre-commit hooks — you can't commit implementation without tests." Builder's Guide describes Build Loop with test-first as a rule.
- **What scripts do:** `init.sh:2337-2347` warns only; README.md:531 explicitly acknowledges TDD ordering is Tier-3 guided. `pre-commit-gate.sh` BL-006 only fires on `feat:` conventional commits; `chore:` / `fix:` / `refactor:` / `docs:` / `test:` / `perf:` / `style:` / `build:` / `ci:` / `revert:` bypass.
- **Recommendation:** Doc correction landed in workflow.html. Consider surfacing this in the User Guide too, since operators reading the User Guide alone might expect harder enforcement than they will actually experience.

### 6. Persona name mismatch: "security auditor" vs "SVP IT Security", "legal" vs "Corporate Legal"

- **Severity:** minor
- **What docs say:** workflow.html (pre-edit) used casual role names.
- **What scripts do:** `evaluation-prompts/Projects/bases/03-security.md:1` uses "Senior VP of IT Security"; `bases/04-legal.md:1` uses "Corporate Legal". User Guide §8 aligns with the base personas.
- **Recommendation:** Correction landed in workflow.html.

### 7. Phase 4 hard-block for POC mode

- **Severity:** blocker (user-facing operator instruction was materially wrong)
- **What docs say:** workflow.html (pre-edit): "POC path: confirm the deployable artifact; upgrade later if you want to go live." User Guide L1032 + Builder's Guide L1611 + process-checklist.sh L579 all say hard-blocked.
- **What scripts do:** Hard-block confirmed. `process-checklist.sh --start-phase4` explicitly rejects POC-mode projects with "POC projects complete at Phase 3. To unlock Phase 4:".
- **Recommendation:** Correction landed in workflow.html.

### 8. "Threat model preview" attributed to Phase 0

- **Severity:** minor
- **What docs say:** workflow.html (pre-edit) L552: "Drafts an initial threat model preview". Builder's Guide L410-412 does not include any threat model in Phase 0; STRIDE lives in Phase 1.3 (L674-707).
- **Recommendation:** Correction landed (removed).

### 9. Maintenance cadence wording

- **Severity:** minor
- **What docs say:** workflow.html (pre-edit): "weekly / monthly / quarterly reminder checks". Builder's Guide + Executive Review + check-maintenance.sh all list monthly / quarterly / biannually. Builder's Guide additionally names a Weekly cadence at L1782-1813 but as a governance activity, not an enforced check.
- **What scripts do:** `check-maintenance.sh:27-105` implements monthly (35d), quarterly (95d), biannually (185d). No weekly cadence. Not scheduled — manually invoked.
- **Recommendation:** Correction landed in workflow.html. Consider a doc reconciliation between Builder's Guide (which lists four cadences) and the script (which only enforces three).

### 10. Doc/Guide disagreement about "review-manifest is optional or required at Phase 3 → 4"

- **Severity:** minor (needs Karl's decision)
- **What docs say:** Builder's Guide L1614 frames review-manifest as a Phase 3 → 4 gate check. User Guide §8.2 recommends running the six prompts. governance-framework.md is silent on whether reviews are gate-blocking.
- **What scripts do:** `check-phase-gate.sh:1039-1056` WARN-only. It also does NOT verify all six reviewers are present.
- **Recommendation:** Decision needed — is missing manifest a WARN (current) or a FAIL for Std+? If Karl wants FAIL for Full track, file a BL entry.

### 11. `.claude/bypass-audit.json` is a first-class governance surface but has zero mention in workflow.html (pre-edit)

- **Severity:** major
- **What docs say:** `docs/audit-log-lifecycle.md` is a dedicated 158-line document; governance-framework.md L746-748 calls it out. Pre-edit workflow.html mentioned only "audit trail files in your git repo".
- **What scripts do:** `.claude/bypass-audit.json` is populated by `scripts/lib/bypass-audit.sh`, `scripts/detect-out-of-band-commits.sh` (SessionStart), and `scripts/hooks/bypass-detector.sh`.
- **Recommendation:** Addition landed (cross-cutting card + glossary entry).

### 12. Backup maintainer + mandatory handoff test — governance role documented, no scripted verification

- **Severity:** minor
- **What docs say:** governance-framework.md L645-673, User Guide Phase 4 organizational actions.
- **What scripts do:** `check-phase-gate.sh` only checks HANDOFF.md exists; does not verify handoff-test-results file. `process-checklist.sh` Phase 4 steps include `handoff_written` and `handoff_tested` but the tested-step honor-based (no automated backup-maintainer probe).
- **Recommendation:** Doc-only reconciliation — accept the gap and note in User Guide that this is a procedural check verified by the backup maintainer's dated sign-off, not by a script.

## Doc-side surfaces that reader inspection did NOT confirm

- **Reader A cited "6 pre-conditions" in governance-framework.md L922-940, but also cited "11 pre-conditions summary" in executive-review.md L319-336.** The extra five are preparation requirements including a "governance enforcement test". The 6-vs-11 count is not a discrepancy but the workflow.html Pre-Phase 0 row currently only shows the 6 blocking pre-conditions. Karl may want to decide whether the 5 preparation requirements deserve their own callout.
- **Reader C flagged: builders-guide.md L1560-1613 says the Phase 3 → 4 dated entry uses a 15-line proximity rule.** This is preserved in the workflow.html edit as a scripted check; no discrepancy.

## What was VERIFIED correct

The docs and scripts do agree on many major claims:

- **Phase gate mechanic core**: `check-phase-gate.sh` reads phase-state.json + APPROVAL_LOG.md, blocks by default, downgradable via `SOIF_PHASE_GATES=warn`. Confirmed in check-phase-gate.sh:216-274.
- **Anti-self-approval mechanism**: per-line `git blame --line-porcelain` on the Approver row (organizational only). Confirmed in check-phase-gate.sh:409-486.
- **Mandatory ZDR gate at Phase 1 → 2** (Invariant #16). Confirmed in check-phase-gate.sh:707-801 and Builder's Guide L820-830 + governance-framework.md L293-315.
- **Six organizational Pre-Phase 0 named-row check**. Confirmed in check-phase-gate.sh:540-595 and approval-log-org.tmpl:16-28.
- **Phase 3 → 4 dual-approval for organizational**. Confirmed in check-phase-gate.sh:901-937 and approval-log-org.tmpl:94-128 and Builder's Guide L1601-1602.
- **Phase 4 POC hard-block**. Confirmed in check-phase-gate.sh:940-954 + process-checklist.sh:579 + User Guide L1032.
- **Penetration test enforcement**: Standard track allows APPROVAL_LOG exemption; Full track has no exemption. Confirmed in check-phase-gate.sh:1001-1024 + governance-framework.md L330-337.
- **Bypass audit ledger**: append-only, atomic mkdir advisory lock + mktemp same-filesystem rename, 7-field row schema, 7 row types. Confirmed in docs/audit-log-lifecycle.md and scripts/lib/bypass-audit.sh.
- **SessionStart out-of-band commit detection**. Confirmed in scripts/detect-out-of-band-commits.sh and docs/audit-log-lifecycle.md.
- **`gh pr create` UAT / Build Loop gating**. Confirmed in pre-commit-gate.sh:695-729.
- **APPROVAL_LOG.md CI enforcement** (append-only + git-author cross-check). Confirmed in templates/pipelines/ci/github/typescript.yml:57-70.
- **Six evaluation prompts exist and match the intended personas**. Confirmed in evaluation-prompts/Projects/bases/01-06 + compose.sh + run-reviews.sh.
- **`upgrade-project.sh --to-production` verifies deferred Pre-Phase 0 rows** and supports `--ack-preconditions=<N1,N2,…>` bypass writing to `.claude/bypass-audit.json`. Confirmed in upgrade-project.sh:820-895.
- **Personal → organizational upgrade refuses when `data_classification` is unset**. Confirmed in upgrade-project.sh:780-820.
- **Bug gate: SEV-1 open blocks; SEV-2 open blocks; SEV-2 deferred blocks**. Confirmed in test-gate.sh:281-451.
- **Framework-gate.sh strict-mode filesystem hook**. Confirmed in verify-install.sh:1066-1090 + scripts/install-filesystem-gates.sh.
- **Retroactive Phase 1 → 2 STA Approval WARN for personal→org upgrades**. Confirmed in check-phase-gate.sh:846-868.
- **Phase-gate snapshots**. Confirmed in check-phase-gate.sh:165-213 (create_gate_snapshot).

## Files consulted (by the readers)

**Docs**
- `docs/governance-framework.md`
- `docs/audit-log-lifecycle.md`
- `docs/executive-review.md`
- `docs/builders-guide.md`
- `docs/user-guide.md`
- `evaluation-prompts/Projects/README.md`
- `evaluation-prompts/Projects/bases/*.md`
- `evaluation-prompts/Projects/modules/*.md`
- `README.md`
- `workflow.html`

**Scripts**
- `init.sh`
- `scripts/check-phase-gate.sh`
- `scripts/check-gate.sh`
- `scripts/check-maintenance.sh`
- `scripts/process-checklist.sh`
- `scripts/pre-commit-gate.sh`
- `scripts/test-gate.sh`
- `scripts/validate.sh`
- `scripts/verify-install.sh`
- `scripts/upgrade-project.sh`
- `scripts/intake-wizard.sh`
- `scripts/reconfigure-project.sh`
- `scripts/pending-approval.sh`
- `scripts/detect-out-of-band-commits.sh`
- `scripts/session-mcp-gate.sh`
- `scripts/session-test-gate-check.sh`
- `scripts/lib/bypass-audit.sh` (referenced)
- `scripts/lib/host.sh` (referenced)
- `evaluation-prompts/Projects/run-reviews.sh`
- `evaluation-prompts/Projects/compose.sh`

**Templates**
- `templates/generated/approval-log-personal.tmpl`
- `templates/generated/approval-log-org.tmpl`
- `templates/generated/project-bible.tmpl`
- `templates/pipelines/ci/github/typescript.yml`
- `templates/tool-matrix/*.json`

## Suggested BL follow-ups (not filed here)

1. **`init.sh` gate-key seed** — seed `gates.phase_2_to_3 = null` alongside the other three. (Minor.)
2. **Phase 3 scan automation** — either wire Snyk / license / OWASP ZAP / full-tree Semgrep into a Phase 3 driver script that archives to `docs/test-results/`, or update Builder's Guide + User Guide to say "operator-run, framework-archived". (Major.)
3. **`check-phase-gate.sh` auto-write of phase-state.json gate dates on PASS** — closes the mismatch between docs and behaviour. (Major.)
4. **Review-manifest gate escalation for Full Track** — WARN → FAIL when track is Full. (Minor.)
5. **User Guide TDD-ordering wording sweep** — bring User Guide in line with README.md L531's Tier-3 admission. (Minor.)
6. **Doc reconciliation: three vs four maintenance cadences** — bring check-maintenance.sh, Builder's Guide, and Executive Review into one canonical list. (Minor.)
7. **Handoff-test-results artifact check at Phase 4** — verify a dated handoff-test outcome file (governance procedure is documented but not gate-scripted). (Minor.)
8. **Persona-string canonicalization** — decide whether to keep "SVP IT Security" / "Corporate Legal" as the canonical role names across all docs (governance-framework.md still says "IT Security" plain). (Nit.)

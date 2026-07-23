# Documentation Estate Index

A one-screen map of `docs/**` and `Reports/**`. Start here to find the right
document; each entry links to the canonical file. Conventions (live vs archive,
stub-at-old-path, date-named reports) are described inline so a new reader can
place any file without guessing.

## Guides (`docs/*.md`)

Ten top-level guides — the platform-agnostic methodology and its operator- and
executive-facing companions.

| Guide | What it is |
|---|---|
| [builders-guide.md](builders-guide.md) | The authoritative platform-agnostic build methodology: phases, decision gates, the Build Loop, TDD ordering enforcement, and the Phase 1→2 / 2→3 / 3→4 gate contracts. |
| [user-guide.md](user-guide.md) | Operator walkthrough — day-to-day commands, the enforcement-tier tables, POC modes, upgrades, and the phase-by-phase "what you do" checklists. |
| [governance-framework.md](governance-framework.md) | Organizational governance: role-separated approval gates, tier definitions, ZDR/data-classification mandate, legal/privacy obligations, cross-model validation. |
| [security-scan-guide.md](security-scan-guide.md) | Findings-interpretation reference — plain-language read-outs of the most common Semgrep and Snyk findings and how to tell real from false positive. |
| [executive-review.md](executive-review.md) | One-sitting executive summary of the framework: what it is, the five phases, risk posture, and adoption considerations. |
| [audit-log-lifecycle.md](audit-log-lifecycle.md) | How `APPROVAL_LOG.md` / bypass-audit evidence is created, appended (append-only invariant), and consumed by the gates. |
| [uat-authoring-guide.md](uat-authoring-guide.md) | How to author high-quality UAT scenarios (guardrails, per-platform reference examples, the scenario linter). |
| [cli-setup-addendum.md](cli-setup-addendum.md) | Claude Code-specific setup: plugins (Superpowers), MCP servers, permission allowlists, session-resume tooling. |
| [extending-platforms.md](extending-platforms.md) | How to add a new platform module (the co-build protocol for platforms beyond the four first-class ones). |
| [step5-dogfood-walker-rubric.md](step5-dogfood-walker-rubric.md) | The pass/partial/fail rubric the Step-5 dogfood walker uses to disposition scenario outcomes. |

## Handoffs (`docs/handoffs/`)

Session handoff documents. **One live state-of-record at the top level; finished
handoffs move to `archive/` and leave a pointer stub at the old path** so every
citation still resolves. Convention: [handoffs/archive/README.md](handoffs/archive/README.md).

- **Live:** [handoffs/2026-07-10-gate-wave-close-out.md](handoffs/2026-07-10-gate-wave-close-out.md) — the current state-of-record (gate wave complete, PRs #160–#167 merged, `main` green with branch protection).
- **Archived:** [handoffs/archive/](handoffs/archive/) — the 2026-07-08 CI-arc-close handoff (superseded) and the 2026-07-09 gate-wave execution handoff (fully executed). Pointer stubs remain at the two old top-level paths.

## Superpowers (`docs/superpowers/`)

Design specs and implementation plans. Both trees follow the **archive-with-stub +
README** convention: once the work ships, the file moves to `archive/`, a pointer
stub with the shipping PR/commit is left at the old path, and referrers resolve
through the stub.

- **Specs** — [superpowers/specs/](superpowers/specs/) (pointer stubs) → [superpowers/specs/archive/README.md](superpowers/specs/archive/README.md). All 16 April design specs are archived (every one's implementation shipped); three are still read as live regression fixtures (intake-wizard, phase-audit, host-aware) — do not delete.
- **Plans** — [superpowers/plans/](superpowers/plans/) → [superpowers/plans/archive/README.md](superpowers/plans/archive/README.md) (BL-049 established this convention).

## Security audits (`docs/security-audits/`)

Per-feature security-audit write-ups produced during the Build Loop's security
step. Current: [security-audits/](security-audits/) — BL-006 (pre-commit build-loop
enforcement), BL-015 (pending-approval sentinel reader), BL-016 (init.sh
non-interactive).

## Platform modules (`docs/platform-modules/`)

Platform-specific implementation guidance layered on the platform-agnostic
Builder's Guide. Four first-class modules: [platform-modules/web.md](platform-modules/web.md),
[platform-modules/mobile.md](platform-modules/mobile.md),
[platform-modules/desktop.md](platform-modules/desktop.md),
[platform-modules/mcp_server.md](platform-modules/mcp_server.md).
Adding another is covered by [extending-platforms.md](extending-platforms.md).

## Reports (`Reports/`)

Dated, point-in-time artifacts — evidence, not living docs. Naming convention is
`YYYY-MM-DD-<slug>.md` (or a dated subdirectory for multi-file trees). Categories:

- **Audit reports** — one-off audits and evaluations. April: documentation
  artifact audit / gap analysis. **June (now tracked, via PR #171):**
  [../Reports/2026-06-28-step4-dead-code-perf-eval.md](../Reports/2026-06-28-step4-dead-code-perf-eval.md),
  [../Reports/2026-06-28-test-integrity-audit.md](../Reports/2026-06-28-test-integrity-audit.md),
  [../Reports/2026-06-29-adversarial-certainty-pass.md](../Reports/2026-06-29-adversarial-certainty-pass.md),
  [../Reports/2026-06-29-backlog-reconciliation-plan.md](../Reports/2026-06-29-backlog-reconciliation-plan.md),
  [../Reports/2026-06-29-step5-dogfood-validation.md](../Reports/2026-06-29-step5-dogfood-validation.md).
- **Phase-audit tree** — [../Reports/phase-audits/](../Reports/phase-audits/): the 6 per-phase enterprise-process audits + consolidated summary + cross-cutting audit, plus re-audit rounds and remediation.
- **UAT trees** — dated `uat-YYYY-MM-DD*/` directories (matrix, RUNBOOK, results, TRIAGE): [../Reports/uat-2026-04-25/](../Reports/uat-2026-04-25/), [../Reports/uat-2026-04-26/](../Reports/uat-2026-04-26/), [../Reports/uat-2026-04-29-bl029-validation/](../Reports/uat-2026-04-29-bl029-validation/).
- **Dogfood / replay reports** — gate-behavior evidence run against this repo:
  [../Reports/2026-07-10-bl072-warn-dogfood.md](../Reports/2026-07-10-bl072-warn-dogfood.md) and
  [../Reports/2026-07-10-bl072-c2-replay.md](../Reports/2026-07-10-bl072-c2-replay.md).
- **Walk / dogfood trees** — dated multi-file validation-walk records
  (REPORT/FINDINGS/LEDGER-style): [../Reports/2026-07-12-e2e-walk/](../Reports/2026-07-12-e2e-walk/)
  (checklist + code-vs-manual), [../Reports/2026-07-13-dogfood-2/](../Reports/2026-07-13-dogfood-2/)
  (16 defects + remediation ledger), [../Reports/2026-07-18-dogfood-3/](../Reports/2026-07-18-dogfood-3/)
  (fresh honest walker, 20/20 checkpoints), [../Reports/2026-07-21-pr-sweep/](../Reports/2026-07-21-pr-sweep/)
  (BL-147..154 wave progress), [../Reports/2026-07-22-dogfood-4/](../Reports/2026-07-22-dogfood-4/)
  (dishonest-operator walk — trio HELD 3/3, live-CI evidence, BL-155..170).
- **Arc-close / test-suite / triage reports** — e.g. the S3 arc-close handoff, workflow-HTML validation, BL-035 orphan triage, and the April test-suite runs, all under [../Reports/](../Reports/).
- **Project post-mortems** — retrospective write-ups also live in `Reports/` by
  the same date convention (a `2026-07-11-project-post-mortem.md` is being
  authored in a parallel unit; it will appear here on merge).

---

*This index maps the estate as of the 2026-07-10 consolidation. When you archive a
handoff or spec, or add a dated report, add or move its entry here so the map stays
one screen and current.*

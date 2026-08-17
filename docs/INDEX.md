# Documentation Estate Index

A one-screen map of `docs/**` and `Reports/**`. Start here to find the right
document; each entry links to the canonical file. Conventions (live vs archive,
stub-at-old-path, date-named reports) are described inline so a new reader can
place any file without guessing.

## Guides (`docs/*.md`)

Thirteen top-level guides — the platform-agnostic methodology and its operator- and
executive-facing companions. The last three cover what happens *outside* the
five-phase build: after v1.0 ships, and before a project that already exists comes in.

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
| [delta-track.md](delta-track.md) | **After v1.0** — the post-release lifecycle `init.sh` installs into every project: the phase-4 activation gate, the four change classes and their confirm-not-quiz open, the brief whose Done-observable checklist *is* the close review, the close-time attribute ratchet, the hotfix lane and its release-blocking retro, the cadence clock's current/overdue/**unmeasurable** contract, `cut-release.sh`'s three refusals and tool-decided semver, and `.claude/delta-policy.json`. Worked transcripts throughout, all executed. |
| [scout.md](scout.md) | **Scout** — the read-only survey (`scripts/scout.sh`). All seven report sections, the read-only proof, the opt-in `--run-tests`, full-history secret scanning with the value never printed, and the limits Scout states about itself (the untested-file count is a name-match heuristic; branch protection is `unknown`, not `no`). |
| [adoption.md](adoption.md) | **Brownfield adoption** — `scripts/adopt-project.sh`: the chooser question verbatim, the floor rule, the reverse intake, the fail-safe write order, the adoption stamp and its loud loss detection, and the TDD exemption's bound. Plus the **test-debt ledger** and its tier ratchet, the exemption's forward equivalent; and the **collision archive** — layout and MANIFEST, the disclosure, `--re-add`, and the pre-staging secret scan that refuses to commit a matched archive entry. **Carries the prominent "what is not built yet" section** — the certification pass, CI carve-out and Adoption Record are designed and not implemented. |

## Handoffs (`docs/handoffs/`)

Session handoff documents. **Finished handoffs move to `archive/` and leave a
pointer stub at the old path** so every citation still resolves. Convention:
[handoffs/archive/README.md](handoffs/archive/README.md).

**A stub is a pointer — a title and a blockquote, no `## ` sections — so derive
the full handoffs rather than counting them here:**

```
grep -l '^## ' docs/handoffs/*.md     # full state-of-record docs
grep -L '^## ' docs/handoffs/*.md     # pointer stubs
```

Usually that returns one file. It returns two whenever a superseded
state-of-record is kept at top level rather than archived — as now — and in that
case CLAUDE.md's "trust the non-stub" tie-break cannot resolve it: **use the
newer date.**

- **Live:** [handoffs/2026-08-16-declaration-vs-capability-wave.md](handoffs/2026-08-16-declaration-vs-capability-wave.md) — the current state-of-record (`main` at `86ceeb8`; #351–#355 merged; `## BL-234:`, `## BL-222:`, `## BL-229:` Closed). One branch is in flight and its adversarial review returned **block** — § 2.1 is the work order, § 8 is a paste-ready resume prompt.
- Superseded: [handoffs/2026-08-15-currency-and-enforcement-wave.md](handoffs/2026-08-15-currency-and-enforcement-wave.md) — its § 4.0 carries a ⚠ CORRECTION; read that before acting on the section.
- **Superseded but still full-length:** [handoffs/2026-07-31-bl201-bl200-close.md](handoffs/2026-07-31-bl201-bl200-close.md) — the previous state-of-record, kept at top level rather than archived. This is the second file the `grep -l` above returns.
- **Archived:** [handoffs/archive/](handoffs/archive/) — finished handoffs, 2026-07-08 through 2026-07-31, each with a pointer stub left at its old top-level path. See [handoffs/archive/README.md](handoffs/archive/README.md) for the per-file status (superseded vs fully executed).

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

## Designs (`docs/designs/`)

Normative design docs authored before a build and held to the same adversarial review as
code. Current: [designs/2026-07-12-currency-system-v1.md](designs/2026-07-12-currency-system-v1.md)
(the currency/update pipeline, v1.1 post-review),
[designs/2026-07-24-operating-model-v1.md](designs/2026-07-24-operating-model-v1.md)
(the configurable multi-agent operating model for BL-097/098/100), and
[designs/2026-08-02-team-orchestrator-v1.md](designs/2026-08-02-team-orchestrator-v1.md)
(**Team Orchestrator** — the architecture for a 2–10 developer fork of this framework: the
multi-actor execution layer, the roster identity model, the imported organizational governance
track, and the BA/PM agent roles. v1.1 post-review, r1 folded; describes a product that does not exist yet), and
[designs/2026-08-02-delta-track-v1.md](designs/2026-08-02-delta-track-v1.md)
(**the Post-MVP Delta Track** — the maintenance and feature lifecycle a project runs after it cuts
v1.0.0: four change classes with derived-then-confirmed attributes, a severable module with a
dependency-direction lint, three re-fire triggers, and a tool-decided release cut. v1.2, build-evidence
amendment folded. **Built and shipping** — the user-facing page is [delta-track.md](delta-track.md)).
[designs/2026-08-02-brownfield-adoption-v1.md](designs/2026-08-02-brownfield-adoption-v1.md)
(**Brownfield adoption** — the second entry path, for a codebase that already exists: a standalone
read-only scanner, the completed-vs-in-flight scenario chooser, the certification pass that replaces
grandfathering, full-history secret scanning with redacted findings, and the archive-and-disclose
collision policy. v1.2, build-evidence amendment folded. **Half built** — Scout, the adoption
driver, the test-debt ledger with its ratchet, and the collision archive ship; the certification
pass, CI carve-out and Adoption Record do not. User-facing pages: [scout.md](scout.md) and
[adoption.md](adoption.md), which name every gap).

## Module contract (`docs/module-contract.md`)

[module-contract.md](module-contract.md) — the normative **M1–M5 severable-module
contract**, transcribed from the brownfield design's §3.3 and binding on every
severable module in the repo (the delta track, Scout, the adoption driver). One
rule per section with its enforcement pointer: the two sibling boundary lints
(`scripts/lint-delta-boundary.sh`, `scripts/lint-module-dependencies.sh`), the
marker lint, and M5's zero-dependency arm. Read it before adding a module file
or touching either lint's manifest.

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
- **[../Reports/2026-07-31-pr272-retro-audit.md](../Reports/2026-07-31-pr272-retro-audit.md)** — record of the queued retroactive audit of PR #272 (the one unreviewed merge): verdict FINDINGS-INERT; the skipped review would have caught exactly one live coverage hole (BL-181's 7-vs-1 undercount, repaired next day).
- **Project post-mortems** — retrospective write-ups also live in `Reports/` by
  the same date convention (a `2026-07-11-project-post-mortem.md` is being
  authored in a parallel unit; it will appear here on merge).

---

*This index maps the estate as of the 2026-07-10 consolidation. When you archive a
handoff or spec, or add a dated report, add or move its entry here so the map stays
one screen and current.*

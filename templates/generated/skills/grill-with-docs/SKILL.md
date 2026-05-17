---
name: grill-with-docs
description: Stress-test a plan against the project's existing documentation, code, and decisions. Interview-style — one question at a time, recommend an answer, wait for feedback. Update PROJECT_BIBLE.md inline as terms and decisions are resolved. Offer ADRs only when the decision is hard to reverse. Use when a design needs sharpening before implementation.
---

> **Attribution.** Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, © Matt Pocock). The upstream uses a `CONTEXT.md` glossary as the persistence target. Solo's adaptation retargets to `PROJECT_BIBLE.md` (Solo's canonical architecture/data-model/threat-model document) and `docs/ADR documentation/` (Solo's ADR location, distinct from upstream's `docs/adr/`). The interview pattern, ADR-criteria, and inline-update discipline are preserved. See `NOTICE` for full attribution.

<what-to-do>

Interview the user relentlessly about every aspect of this plan until a shared understanding is reached. Walk down each branch of the design tree, resolving dependencies between decisions one at a time. For each question, provide a recommended answer.

Ask one question at a time. Wait for feedback before continuing.

If a question can be answered by exploring the codebase or reading existing documentation, do that instead of asking.

</what-to-do>

<supporting-info>

## Where Solo's documentation lives

Solo Orchestrator projects keep their truth in a small set of canonical files. Read them before asking the user; cite them in answers.

| File | Role | When to update |
|---|---|---|
| `PROJECT_BIBLE.md` | Architecture, data model, threat model, domain vocabulary. The canonical truth. | When terms resolve, when domain boundaries clarify, when the data model changes. **Update inline during grilling.** |
| `docs/ADR documentation/` | Architectural Decision Records. Per Solo's `templates/generated/adr.tmpl`. | When a decision meets the 3-of-3 ADR criteria (below). Create lazily; never preemptively. |
| `CLAUDE.md` | Per-session conventions, agent preferences, project-wide reminders. | When a *session-readable* convention emerges (e.g., "always commit in `feat:` form for Cutline work") — distinct from architectural truth. |
| `solo-orchestrator-backlog.md` (or project equivalent) | Open BL items, parked items, pending decisions. | When a question is *deferred* (not resolved). File a BL entry pointing to the grilling session's open question. |
| `.claude/phase-state.json` / `.claude/process-state.json` | Where we are in Phase / Build Loop. | Read-only during grilling — informs which decisions are in-scope for this phase. |

Solo intentionally does NOT have a separate `CONTEXT.md` glossary today. `PROJECT_BIBLE.md` carries the domain vocabulary as part of its architecture section. If a project's vocabulary grows large enough to warrant its own glossary file, that decision should itself go through an ADR.

## During the session

### Challenge against the existing record

When the user uses a term that conflicts with `PROJECT_BIBLE.md` or with prior ADRs, call it out immediately:

> "Your Bible defines `Cancellation` as X (§2.3), but you seem to mean Y here. Which is it — and should we update the Bible?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term:

> "You're saying 'account' — do you mean `Customer`, `User`, or `Tenant`? Those are different. The Bible currently distinguishes Customer and User; Tenant isn't defined yet."

### Probe with concrete scenarios

When domain relationships are being discussed, invent scenarios that probe boundaries:

> "If a Customer has two Users and one cancels the subscription, does that cancel for both Users or only one? Walk me through that case."

### Cross-reference with code AND tests

When the user states how something works, check whether the code agrees. Solo's TDD discipline means tests are the second source of truth. If you find a contradiction, surface it:

> "Your `OrderService.cancel()` cancels the whole order, but the test `test_partial_cancellation_skips_shipped_items` implies partial. The code, the tests, and what you just said disagree — which is right?"

### Update PROJECT_BIBLE.md inline

When a term is resolved or a boundary clarifies, update `PROJECT_BIBLE.md` right there. Don't batch. Use the same format the existing sections use.

**`PROJECT_BIBLE.md` is the architecture/domain truth file.** Do not treat it as a spec, a scratch pad, or a repository for in-flight implementation decisions. Implementation decisions belong in plans (`docs/superpowers/plans/`) and ADRs (`docs/ADR documentation/`).

### Offer ADRs sparingly

Only offer to create an ADR when **all three** are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful (data migration, public API, contract with another team).
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **A real trade-off** — there were genuine alternatives and one was picked for specific reasons.

If any of the three is missing, skip the ADR. A weak ADR weakens the rest.

Use Solo's existing ADR template at `templates/generated/adr.tmpl`. ADRs live in `docs/ADR documentation/` (note the spaces — that is Solo's existing convention, distinct from upstream's `docs/adr/`).

### When a decision needs the user, not the code

If the grilling reaches a point where the next branch genuinely requires user judgment (e.g., business-policy decision, security/compliance trade-off, scope cut), do NOT continue with assumptions. Use Solo's structured decision-point machinery:

```bash
scripts/escalate-to-user.sh \
  --question "<the fork>" \
  --option "A1: <option 1>" \
  --option "A2: <option 2>" \
  --recommendation "A1" \
  --rationale "<why A1>"
```

This writes `.claude/pending-approval.json` so the CDF stop-hook and Solo's pre-commit gate both honor the pause until the user resolves it. Bury-the-question-and-proceed-with-an-assumption is the failure mode this skill exists to prevent.

### When a question should be deferred, not resolved

Not every grilling question needs to be answered in this session. If a question is real but out of scope for the current phase / feature / branch, file a BL item:

> "Logging strategy for the Cutline isn't in scope for Phase 1 architecture — filing BL-XXX so it doesn't get lost. Continuing with the Phase 1 boundaries we already have."

Cite the BL in `PROJECT_BIBLE.md` or in the relevant plan so the deferred-question trail is recoverable.

## Composition with other Solo skills

- **`zoom-out`** (companion) — if grilling reveals the user (or you) doesn't have the structural map of the area, pause and zoom-out first. The map informs the grill.
- **`sweep-triage`** — if grilling produces a cluster of findings that will need batch handling (e.g., post-audit), capture them in a TRIAGE.md under `Reports/<sweep-id>/`.
- **Brainstorming** (Superpowers, if installed) — grill-with-docs is best for *stress-testing an existing plan against existing docs*. Brainstorming is best for *exploring open questions before a plan exists*. They are complementary, not redundant.

## Self-check before ending the session

1. Did I update `PROJECT_BIBLE.md` for every term or boundary that resolved?
2. Did I offer ADRs only where the 3-of-3 criteria held?
3. Did any unresolved questions get filed as BL items rather than lost?
4. Did I escalate user-judgment forks to `pending-approval.json` rather than assume?
5. Is the plan actually sharper now than when we started?

If any answer is no, fix it before ending.

</supporting-info>

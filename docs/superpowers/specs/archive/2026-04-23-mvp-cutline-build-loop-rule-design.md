# MVP Cutline Work Always Requires the Build Loop

**Date:** 2026-04-23
**Status:** Design approved, pending spec review
**Scope:** Doc-only change to solo-orchestrator
**Implements:** BL-007 from `solo-orchestrator-backlog.md`

## Problem

During Phase 2 Project Initialization (Builder's Guide §2.0), several sub-steps produce commits that don't just prepare the project — they implement items from the MVP Cutline. An agent or orchestrator who treats that work as scaffolding ships it without the Build Loop's test-first, audit, and record discipline. The drift is silent: schema-valid, passes CI, but bypasses the quality gate the Build Loop exists to enforce.

This was observed on the lancache project (2026-04-22). Two Cutline items (ID1 "initial migration runner" and ID3 "structlog with correlation-ID propagation") were committed as `feat(init): ...` during §2.0 Init steps. The drift was caught retroactively by running `scripts/test-gate.sh --record-feature` — post-facto detection, not prevention.

The Builder's Guide currently does not explicitly state that Cutline items require the Build Loop regardless of which Phase 2 sub-step they land in. An agent reading the guide can reasonably conclude that §2.0 Init work is distinct from §2.1+ Build Loop work and doesn't need the same discipline.

## Goals

- State the rule explicitly in the Builder's Guide, with rationale and worked examples, so agents and orchestrators can't miss it.
- Restate the rule in the CLAUDE.md template so per-session agent instructions carry the constraint without requiring the agent to consult the full guide.
- Keep the rule generic — not coupled to any specific ID-prefix convention — so projects that don't use F-/ID- style prefixes inherit the rule too.

## Non-Goals

- No new files.
- No framework-wide ID convention (F-/ID- prefixes). Lancache uses them; solo-orchestrator does not mandate them.
- No manifesto template changes, FEATURES template changes, or process-checklist.sh changes.
- No tooling enforcement. BL-006 will add pre-commit hook enforcement later; this spec is doc-only guardrail.
- No retroactive audit of existing projects. The rule applies forward.
- No cross-reference to BL-006's future hook (the doc shouldn't presume the hook exists).

## Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Terminology | Generic: "items above the MVP Cutline in PRODUCT_MANIFESTO §5" | No prefix convention forced; stays aligned with existing manifesto template |
| 2 | Placement | Builder's Guide + CLAUDE.md template | Guide is authoritative; CLAUDE.md is what agents read every session |
| 3 | Treatment depth | Full subsection with rule + rationale + 3 examples + recovery guidance | Failure mode is subtle; worked examples prevent misreading |

## Architecture

Two-file doc-only edit. No code, no new tests, no new files. Two touchpoints:

- **Builder's Guide** — new subsection between §2.0's closing and §2.1's opening, titled *"MVP Cutline Work Requires the Build Loop"*. ~280 words: rule statement, rationale with lancache attribution, three worked examples of init steps that can disguise Cutline work, a "how to spot it" diagnostic, recovery guidance for drifted work.
- **CLAUDE.md template** — new bullet in "Your Constraints" block near the existing "One feature at a time" bullet. 2-3 sentences stating the rule compactly, with a pointer to the Builder's Guide subsection for full examples.

**Cross-reference strategy:** Builder's Guide is canonical for the full rule text. CLAUDE.md's bullet says `See docs/reference/builders-guide.md § "MVP Cutline Work Requires the Build Loop"` to avoid dual-maintenance drift. If the subsection title ever changes, both files need updating — verification checks flag the drift.

## Components

### Component 1 — Builder's Guide subsection

**File:** `docs/builders-guide.md`
**Placement:** Between the closing `---` separator after §2.0's "Verify before building the first feature" checklist (currently around line 964) and the `### The Build Loop` header (currently around line 967).

**Subsection text (locked content; minor wording may flow-adjust at write time):**

```markdown
### MVP Cutline Work Requires the Build Loop

During the Phase 2 initialization steps above, some scaffolding work produces commits that don't just prepare the project — they implement items from the MVP Cutline. When that happens, the work is **Build Loop work, not init work**, and it must go through the full Build Loop (§2.2–2.6 below), not just the init checklist.

**The rule:** Any item above the MVP Cutline in `PRODUCT_MANIFESTO.md` §5 requires the full Build Loop — write tests first, verify they fail, implement, run the security audit, update documentation, record the feature — regardless of which Phase 2 sub-step it first appears in.

**Why this matters.** Init steps and Build Loop work can look the same on the surface. "Set up the data model" might mean copying a schema fixture (init work) or implementing the data-contract guarantees that satisfy an MVP Cutline item (Build Loop work). An agent or orchestrator who treats Cutline work as init work ships it without tests, without audit, without documentation — exactly the drift the Build Loop exists to prevent. This was observed on the lancache project (2026-04-22): two Cutline items were committed as `feat(init): ...` without going through the Build Loop; the drift was caught only after the fact by running `--record-feature` retroactively.

**Examples of init steps that can disguise Cutline work:**

- **Step 4 (Configure data model)** — if your Cutline includes "all migrations verified via CHECKSUMS manifest before apply," the migration runner isn't scaffolding; it's the feature. Write the tests first.
- **Step 3 (Agent-initialized project)** — if your Cutline includes "structured logging with correlation-ID propagation," the logging setup isn't boilerplate; it's the feature. Write the tests first.
- **Step 6 (CI/CD)** — if your Cutline includes a specific contract test that runs on every PR, adding that test to CI is the feature's final Build Loop step, not init housekeeping.

**How to spot it:** when scaffolding step N produces code that you could circle on the Cutline list in `PRODUCT_MANIFESTO.md`, stop. Switch into Build Loop mode for that code (§2.2 Write Tests First and onward), complete the cycle, and record the feature with `scripts/test-gate.sh --record-feature "<name>"` before continuing with the remaining init steps.

**If you've already shipped Cutline work without the Build Loop:** retroactively run the Build Loop steps for that feature — write the tests you didn't write, run the security audit you skipped, update `FEATURES.md`, record the feature. It's awkward but recoverable. Don't leave the drift uncorrected; future phase gates will surface the gap at Phase 2→3.

---
```

### Component 2 — CLAUDE.md template bullet

**File:** `templates/generated/claude-md.tmpl`
**Placement:** In the "Your Constraints" block, immediately after the existing "One feature at a time: Complete the full Build Loop..." bullet (currently around line 70).

**New bullet text:**

```markdown
- **MVP Cutline work is always Build Loop work.** If a Phase 2 initialization step (repo setup, scaffolding, data model, pre-commit, CI/CD, or verification) produces code that implements an item above the MVP Cutline in `PRODUCT_MANIFESTO.md` §5, that code requires the full Build Loop — tests first, implement, security audit, documentation, `--record-feature` — regardless of which init step it first appeared in. See `docs/reference/builders-guide.md` § "MVP Cutline Work Requires the Build Loop" for examples and recovery guidance.
```

**Path note:** the bullet references `docs/reference/builders-guide.md` (the downstream path after init.sh copies the guide into the project), not the solo-orchestrator source path.

## Verification

Three post-edit checks, all runnable bash one-liners. No new test file; verification is a spot-check at implementation time.

### Check 1 — Subsection placement in Builder's Guide

```bash
grep -n 'Verify before building the first feature\|MVP Cutline Work Requires the Build Loop\|^### The Build Loop' docs/builders-guide.md
```

Expected: three lines in ascending line-number order; the "MVP Cutline Work Requires the Build Loop" line falls between the §2.0 closing and §2.1 opening.

### Check 2 — CLAUDE.md bullet placement

```bash
grep -n 'One feature at a time\|MVP Cutline work is always Build Loop work' templates/generated/claude-md.tmpl
```

Expected: two lines with consecutive-ish numbers (new bullet immediately follows the "One feature at a time" anchor).

### Check 3 — Cross-reference consistency

```bash
grep -c '^### MVP Cutline Work Requires the Build Loop$' docs/builders-guide.md
grep -c 'MVP Cutline Work Requires the Build Loop' templates/generated/claude-md.tmpl
```

Both must return `1`. If either returns 0 (or something else), the title drifted between the two files.

### Not verified mechanically

- Content quality (clarity, example aptness, recovery guidance adequacy) — judgment call, spec-approval and PR-review.
- Agent compliance with the rule — observed over future UAT sessions / project work, not unit-testable.
- Downstream distribution — `upgrade-project.sh`'s existing template refresh mechanism handles the CLAUDE.md update; no new upgrade logic needed.

## Open Questions

None. All decisions captured in the Decisions table.

## Related

- Backlog: `solo-orchestrator-backlog.md` — BL-007 (this spec's trigger); BL-006 (pre-commit hook enforcement, coupled but separate).
- Trigger: lancache project Phase 2 audit, 2026-04-22 (ID1 and ID3 drift).
- Precedent for doc-guardrail-then-tooling pattern: BL-009 (UAT template quality guardrails in HTML comments, then mechanical linter).
- Companion future work: BL-006 will mechanically enforce the rule stated here via a pre-commit hook that cross-references `feat(...)` commits against active Build Loop sessions. This spec is the doc half; BL-006 is the tool half. The doc half stands alone and should land first.

---
name: zoom-out
description: Step back from the current task and produce a higher-level map of where the work fits — modules, callers, decisions, and where this sits in the project's phase. Use when unfamiliar with an area of code, between features, at a phase transition, or whenever the next decision needs context the immediate work doesn't supply.
disable-model-invocation: true
---

# Zoom Out

> **Attribution.** Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, © Matt Pocock). The upstream is a one-paragraph prompt to "go up a layer of abstraction." Solo's adaptation points the zoom-out at the project's actual artifacts (PROJECT_BIBLE, phase-state, ADRs, backlog) so the map produced is grounded in canonical sources, not improvised. See `NOTICE` for full attribution.

I don't know this area of code (or this decision point) well enough. Go up a layer of abstraction. Produce a map that uses the project's actual vocabulary.

## What to include

1. **Where we are.** Current phase (read `.claude/phase-state.json`), current Build Loop state (read `.claude/process-state.json`), current branch, current PR (if any).
2. **The relevant code surface.** Modules, files, and callers touching the area in question. Use the names that already exist in the codebase — not invented categories.
3. **The relevant decisions.** Read `docs/ADR documentation/` for any ADRs in this area. Cite them by number. If a decision is about to be made, ask whether an ADR should be opened.
4. **The relevant architectural truth.** Cross-reference `PROJECT_BIBLE.md` (architecture, data model, threat model). If `PROJECT_BIBLE.md` and the code disagree on something material, surface the contradiction.
5. **What's in flight.** Read `solo-orchestrator-backlog.md` (or the project's backlog) for any related open BL items. Note open `pending-approval.json` sentinels.
6. **What the next decision actually depends on.** Not "what could come next" — what is BLOCKED on what.

## What to skip

- Long prose summaries of the codebase. The map is structural, not literary.
- Speculation about future features not on the backlog.
- Repeating content from `PROJECT_BIBLE.md` verbatim — link to it instead.

## When this is most valuable

- **Between features.** After `process-checklist.sh --complete-step build_loop:feature_recorded`, before the next `--start-feature`. The zoom-out is the natural Context Health Check moment (Builder's Guide § "Context Health Checks every 3-4 features").
- **At a phase transition.** Phase 2→3, Phase 3→4. Step back before crossing the gate.
- **When debugging.** Before diving into a hard bug, zoom-out tells you which other systems share the failure surface.
- **When onboarding a successor or returning after a break.** The map is the resumption substrate (pairs with `session-handoff` for that case).
- **When stuck on a design decision.** If the next step has two defensible paths, zoom-out surfaces the decisions and artifacts that should weigh on the choice.

## Output

A short map. Headings, file paths with line refs, ADR numbers, BL numbers. Not paragraphs.

If `PROJECT_BIBLE.md` does not exist (e.g., very early in Phase 1), say so and produce the map from the code and ADRs alone.

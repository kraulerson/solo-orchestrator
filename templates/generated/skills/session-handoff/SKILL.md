---
name: session-handoff
description: Compact the current conversation into a session-boundary handoff document for another agent to pick up. Use at session end (or before a planned interruption like a machine reboot, hard context-window break, or hand-off to a different operator).
argument-hint: "What will the next session be used for?"
---

# Session Handoff

> **Attribution.** This skill is adapted with permission from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, © Matt Pocock). The original skill (`handoff`) was written to be lightweight and tool-agnostic. This Solo Orchestrator-adapted version writes to `docs/handoffs/` so the handoff lives with the project as an auditable artifact (Solo's W7 handoff-readiness principle), and is named `session-handoff` to disambiguate from Solo's Phase 4 production HANDOFF.md (`templates/generated/handoff.tmpl`). See `NOTICE` for full attribution and license.

## When to use

Use **before** any of:
- Hard context-window break (the next reply might roll context out of memory).
- Machine reboot or planned shutdown.
- Switching to a different agent or operator mid-task.
- End-of-day stop when work is mid-flight and you want to resume cleanly tomorrow.

Do **not** use this skill for:
- Phase 4 production handoff to operations — that goes in `HANDOFF.md` via the project's existing `templates/generated/handoff.tmpl`. They are different artifacts with different audiences.
- Single-task summaries inside a session — write those inline.

## What it produces

Write a markdown document summarizing the current conversation so a fresh agent (or future-you) can continue cleanly. Save it to:

```
docs/handoffs/YYYY-MM-DD-<topic-slug>.md
```

(Create `docs/handoffs/` if it does not exist.)

The handoff document MUST include:

1. **Where we are** — one-paragraph status of the work in progress: current branch, current PR (if any), current task on the implementation plan, current test-gate state.
2. **What just shipped this session** — bullet list of commits / PRs / artifacts produced. Link to file paths and PR URLs, do not duplicate content.
3. **What's blocked / waiting** — anything paused on user review, external state (CI, deploys), or unanswered design questions.
4. **What's next** — the specific next concrete action. If multiple options exist, list them with the recommendation.
5. **References** — paths to PRDs, plans, ADRs, specs, TRIAGE docs, calibration reports the next session will need. Use repo-relative paths.
6. **Resume prompt** — a single paragraph the user can paste into the next session (or have an agent re-enter with) that re-establishes context. Should be self-contained: "Continuing from <date> handoff at <path>. <One-line recap of decision-state>. <Specific next action>."

If the user passed an argument describing the next session's focus, tailor the document to that focus.

## What NOT to do

- **Do not duplicate content** already captured in artifacts. The handoff is a pointer document, not a re-creation. If a decision lives in an ADR, link to it. If a plan lives in `docs/superpowers/plans/`, link to it.
- **Do not write the handoff as a narrative log.** This is not a journal. Lead with "where we are now" and "what's next" — those are what the resumer needs.
- **Do not skip the resume prompt.** Without it, the next session has to re-derive context. The prompt is the difference between "useful" and "load-bearing."
- **Do not invent followup items.** Only record items the conversation actually surfaced.

## Composition with Solo's existing artifacts

- If a feature is mid-implementation, link to its implementation plan (`docs/superpowers/plans/...`) and identify the current task by number.
- If a calibration / UAT sweep is mid-flight, link to the TRIAGE.md and identify which findings are addressed vs. deferred.
- If `process-state.json` reflects in-flight Build Loop / Phase work, mention the current step and what step is next.
- If a `pending-approval.json` sentinel exists (BL-015 / BL-029), call this out prominently — the next session must address it before proceeding.

## Self-check before saving

Read the document you just wrote. Ask:
1. If I, with no other context, started a session and was given only this document, could I resume cleanly?
2. Did I link to canonical artifacts rather than re-quoting them?
3. Is the resume prompt at the bottom usable as a literal first message?

If any answer is no, fix it before saving.

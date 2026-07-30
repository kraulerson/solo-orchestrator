# Handoff archive — `docs/handoffs/archive/`

This directory holds **session handoff** documents whose work is finished —
either fully executed (all work packages shipped) or superseded by a later
handoff. Handoffs are archived, never deleted, so the trail
plan → PRs → shipped state stays intact and citable.

## Live vs archive

- **Live handoff:** the single most recent state-of-record for the current
  arc lives at the top level of `docs/handoffs/`. Right now that is
  [`../2026-07-30-post-sast-wave-next-steps.md`](../2026-07-30-post-sast-wave-next-steps.md).
  Everything else at the top level is a pointer stub.
- **Archived handoff:** once a handoff is executed or superseded, its full
  text moves here and a short **pointer stub** is left at the original
  top-level path (title, one-line status, links to this archived copy and to
  the successor doc) so every existing citation of the old path still
  resolves.

## When a handoff moves here

1. Confirm the handoff is done: either its successor handoff supersedes its
   plan, or every work package it describes has landed on `main` (cite the
   PRs).
2. `git mv docs/handoffs/<name>.md docs/handoffs/archive/<name>.md`
   (preserves file history; the archived copy stays byte-for-byte intact).
3. Write a pointer stub at the old top-level path: H1 title, a one-line
   status (superseded / fully-executed), and links to the archived copy and
   the successor/live doc.
4. Grep the repo for the old path (docs, `solo-orchestrator-backlog.md`,
   scripts, tests) and confirm every referrer still resolves via the stub or
   is updated.

## Contents

In chain order (oldest first). Each has a pointer stub at its old top-level path.

- `2026-07-08-ci-arc-close-and-gate-wave.md` — SUPERSEDED by the 2026-07-09
  execution handoff (its gate-wave ordering was obsoleted the next day).
- `2026-07-09-gate-wave-execution-handoff.md` — FULLY EXECUTED (gate wave
  shipped as PRs #160–#167); closed out by the 2026-07-10 close-out.
- `2026-07-10-gate-wave-close-out.md` — FULLY EXECUTED + SUPERSEDED (archived
  2026-07-25). The gate wave closed; the arc it handed to is itself finished.
  `Reports/2026-07-11-project-post-mortem.md` cites this document by line
  number — those citations resolve against **this archived copy**, which is
  byte-for-byte the original.
- `2026-07-18-dogfood-remediation-handoff.md` — SUPERSEDED (archived
  2026-07-25); described the Dogfood-2/3 remediation arc mid-flight.
- `2026-07-20-arc-close-phase-g.md` — FULLY EXECUTED + SUPERSEDED (archived
  2026-07-25). Its §4 Phase-G decisions were taken (the trio decision is
  recorded on BL-097/098/100; Dogfood-4 ran and closed).
- `2026-07-24-residuals-wave-and-next-builds.md` — FULLY EXECUTED + SUPERSEDED
  (archived 2026-07-25). Residuals wave merged as PRs #255–#258; the two builds
  it queued shipped as PR #262 (BL-161) and PR #263 (BL-165). Its § 3 is the
  first surfacing of the two stale full-suite tests later filed as BL-173.
- `2026-07-24-next-session-prompt.md` — FULLY EXECUTED (archived 2026-07-25);
  the launch prompt for that BL-161 + BL-165 session.
- `2026-07-24-seven-wp-wave-handoff.md` — FULLY EXECUTED + SUPERSEDED (archived
  2026-07-29). Its wave landed as #265 (`7866022`), #266 (`d857294`), #271
  (`064d578`), #269 (`8afb9ba`), #268 (`ed406c8`) and #270 (`b0b60aa`); the
  closures it queued shipped as #272 (`d970b27`). Its § 3 blocker — a staged
  submodule gitlink aborting the BL-132 index scan — was fixed before #270
  merged. Note this file carries its OWN ⚠ SUPERSEDING UPDATE header from
  2026-07-25 warning that its § 1–§ 3 inventory was already stale when written;
  treat both layers as historical.

- `2026-07-29-sast-coverage-and-ci-lane.md` — FULLY EXECUTED + SUPERSEDED (archived
  2026-07-30). Every PR it tracked merged (#280 `8f36382`, #281, #282, #283) and BL-193 — the
  blocker its § 3 was written around — was root-caused and Closed. Two things make it worth
  reading after archival: its § 3 ⚠ CORRECTION (the first draft blamed the wrong subsystem and
  told the next session to edit 22 innocent CI templates), and its §§ 5–7, which remain the
  reference for BL-192's `Parsed lines` root cause. Its own header marks §§ 1–4 superseded.

## Citation convention for handoffs

Handoffs must cite code by durable handles, not positions:

- Cite a grep-able `# BL-NNN-...` marker comment (the repo's citation
  primitive) or a function name — both survive edits above them.
- NEVER cite a bare `file:line`. Line numbers drift as files change and have
  mis-resolved within ~24h of a handoff being written.
- If a line number is truly unavoidable, pair it with the marker/function it
  points at and flag it VERIFY-BEFORE-USE. When reading any older handoff,
  re-grep every line-number citation before trusting it.

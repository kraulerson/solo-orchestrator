---
name: sweep-triage
description: Consolidate findings from a sweep (UAT calibration, multi-agent validation, manual audit) into a TRIAGE.md document with severity ranking and ship recommendations. Use when a sweep has produced multiple findings that need to be triaged together to make a single ship/no-ship decision.
argument-hint: "Path to the sweep directory (e.g., Reports/uat-2026-MM-DD-foo/) OR a description of the sweep being triaged."
---

# Sweep Triage

> **What this is.** A skill for consolidating findings from a sweep into one decision-grade document. A sweep is any activity that surfaces multiple findings at once: a multi-agent UAT run, a manual audit pass, a security review, a calibration replay. Each finding needs severity, a fix recommendation, and the whole set needs an overall ship recommendation.
>
> **What this is NOT.** This skill is not for per-issue triage in an issue tracker (working through GitHub Issues or Linear one at a time, applying state-machine labels). That is a different workflow. If you want issue-tracker triage, see the related work below.
>
> **Canonical example.** `Reports/uat-2026-04-29-bl029-validation/TRIAGE.md` (committed to this repo) is the output shape this skill produces. Read it before writing your first TRIAGE — it shows the per-agent verdict table, severity-ranked issue list, and the Resolution section appended after fixes shipped.

## When to use

- A multi-agent UAT sweep just finished and you have N agent reports in `Reports/<sweep-id>/results/agent-*.json`.
- A manual audit (security review, accessibility pass, code review) produced multiple findings.
- A calibration replay (cf. BL-029 / BL-030 work) produced verdicts across scenarios and personas.
- You're about to make a ship / no-ship decision and have more than 2-3 findings to weigh.

## When NOT to use

- Single-finding issues — write the fix or file the BL item directly.
- Per-issue triage in an issue tracker — that's a different workflow (state machine + labels, not severity tiers + ship decisions). See *Related work* below.
- Trivial sweeps (everything green, no findings) — no document needed; the green test output is the artifact.

## Output

The skill produces a markdown document at:

```
Reports/<sweep-id>/TRIAGE.md
```

Where `<sweep-id>` is the directory the sweep already lives in (e.g., `uat-2026-04-29-bl029-validation`). If there is no sweep directory yet, create one at `Reports/<sweep-id>/` first.

### Required sections

The TRIAGE.md MUST contain, in this order:

1. **Header.** Date, sweep name, target branch/HEAD, wave structure (if multi-wave dispatch), and a one-line per-agent or per-source verdict summary.
2. **Per-agent verdicts table** (or per-source equivalent). One row per agent / per audit source. Columns: identifier, scope, headline verdict (e.g., `ship | fix-then-ship | block-merge`), headline finding.
3. **Issues, ranked by severity.** Use severity tiers `S1` (critical / merge-blocker) through `S5` (low / nice-to-have). Each issue gets:
   - One-line headline
   - Source(s) — which agent(s) / audit step surfaced it
   - Description (what's broken, what's the scope, what's at stake)
   - Recommended action: `fix-in-branch | defer-to-followup | accept-as-is | block-merge`
   - Fix complexity estimate (small / medium / large)
4. **"What demonstrably works"** section. Non-findings — list properties of the work that the sweep CONFIRMED rather than just failed to disprove. This is the section that prevents people from reading a TRIAGE as "everything is broken" when actually most things work and N specific things don't.
5. **Ship decision.** One paragraph: ship | fix-then-ship | block-merge, with reasoning. If fix-then-ship, list the specific subset to fix in this branch and what defers. If block-merge, list the specific blockers and what closes them.

### Optional but recommended

6. **Resolution section** (appended AFTER the recommended fixes ship). Records what was actually done vs. deferred, with commit references. Lets a future reader trace from the original finding to the fix commit without git archaeology.

## Workflow

1. **Locate or create the sweep directory.** If the user passed `Reports/<sweep-id>/`, use it. Otherwise infer from context (current sweep in flight) or ask.

2. **Gather findings.** Inspect everything in the sweep directory that produces signal:
   - Agent JSON reports (`results/agent-*.json`) — each typically has a `ship_recommendation` field and a list of findings.
   - Manual notes from the user.
   - Test output, GitHub issues, ADRs touched during the sweep.

3. **Cluster duplicate findings.** When multiple agents report the same underlying issue with different framings, merge them into one issue with all sources cited. Don't list the same problem 3 times.

4. **Assign severity.** Use the ladder:
   - **S1 (critical):** merge-blocker; the framework's stated invariant is violated. Examples: silent dropping of `refuse_to_recommend` audit rows (BL-029 calibration S1); secret leakage; data loss path.
   - **S2 (high):** ship-blocker under strict reading; the calibration scenarios surfaced exactly this phrasing and it's the reason the sweep was run. Examples: regex narrowness on canonical bypass language (BL-029 calibration S2).
   - **S3 (medium):** real but post-merge OK; bounded blast radius. Examples: documentation false positives (BL-029 calibration S3).
   - **S4 (medium):** feature gap that prevents a use case from completing, but the use case isn't critical-path for this ship. Examples: missing audit-row closer for W7 utility (BL-029 calibration S4).
   - **S5 (low):** UX edge or polish. Examples: sentinel priming risk (BL-029 calibration S5).

5. **Recommend per-issue action.** For each issue, pick: `fix-in-branch` (do it now), `defer-to-followup` (file a BL item), `accept-as-is` (document why and move on), `block-merge` (don't ship until this is fixed).

6. **Recommend overall ship decision.** Bias toward shipping with a clear deferred list over blocking everything. Block-merge should be rare — only when an S1 is unresolved or a cluster of S2s collectively crosses the credibility threshold.

7. **Write "What demonstrably works."** This is the section that prevents misreading. Examples: "Confirmation phrase defeats novice acceptance (agent 4 confirmed in-character)" or "Severity elevation routes through correctly when patterns DO match."

8. **Save the TRIAGE.md.** Commit it as part of the sweep evidence, not as a transient artifact.

9. **After fixes ship — append Resolution.** Once the recommended fixes are in, return to the TRIAGE and append a Resolution section recording exactly what was done (commit refs) and what was deferred (BL items). This converts the TRIAGE from a snapshot into a permanent record.

## Self-check before saving

Read the document with fresh eyes. Ask:

1. If someone read only this TRIAGE (not the agent reports), could they decide ship / fix / block?
2. Did I cluster duplicate findings, or is the issue list inflated with restatements?
3. Did I include "What demonstrably works"? If not, add it — readers will infer "everything is broken" otherwise.
4. Is every recommended action concrete (`fix-in-branch this subset`, `defer-to-followup as BL-029.1`) or vague (`investigate`)?
5. Is the ship decision a clear one-line verdict, or a hedge?

If any answer is no, fix it before saving.

## Composition with Solo's existing artifacts

- **Backlog (`solo-orchestrator-backlog.md`):** `defer-to-followup` items should be filed as BL items. Cite the BL number in the TRIAGE so the reader can trace.
- **Implementation plans (`docs/superpowers/plans/`):** if a `fix-in-branch` cluster is large enough to warrant a plan, write one. The TRIAGE points to the plan; the plan points back to the TRIAGE.
- **Calibration / UAT reports (`Reports/<sweep-id>/`):** the TRIAGE lives in the same directory as the agent reports it triages.
- **Pending-approval sentinel:** if the sweep surfaced an open question for the user, use `scripts/escalate-to-user.sh` (BL-029) to write a structured pending-approval rather than burying the question in the TRIAGE.

## Related work

- **`mattpocock/skills` `triage`** ([upstream](https://github.com/mattpocock/skills/tree/main/skills/engineering/triage), MIT, © Matt Pocock) — a spiritually-related but differently-scoped skill for per-issue triage in an issue tracker (GitHub Issues, Linear). State machine model with `needs-triage` / `needs-info` / `ready-for-agent` labels. Use that if you're working through a backlog of incoming issues one at a time; use this skill if you're consolidating a sweep into a single ship decision.
- **`session-handoff`** (Solo, adapted from mattpocock) — what to do when the work is mid-flight and the session is ending. Different artifact; different purpose.

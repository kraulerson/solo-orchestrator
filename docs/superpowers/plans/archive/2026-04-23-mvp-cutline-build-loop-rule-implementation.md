# MVP Cutline Build Loop Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codify the rule "MVP Cutline items always require the full Build Loop, regardless of which Phase 2 sub-step they first appear in" in the two docs agents read — Builder's Guide (authoritative) and CLAUDE.md template (per-session). Implements BL-007 per spec `docs/superpowers/specs/2026-04-23-mvp-cutline-build-loop-rule-design.md`.

**Architecture:** Two-file doc-only edit. No code, no new files, no tests beyond verification grep checks. Builder's Guide gets a new ~280-word subsection between §2.0 (Init) and §2.1+ (Build Loop). CLAUDE.md template gets a 2-3 sentence bullet in the Your Constraints block pointing at the Builder's Guide subsection.

**Tech Stack:** Markdown. Bash for verification greps.

---

## File Structure

```
docs/
└── builders-guide.md                      # MODIFIED: new subsection between §2.0 and §2.1

templates/
└── generated/
    └── claude-md.tmpl                     # MODIFIED: new bullet in Your Constraints
```

Two modifications. Zero new files.

---

## Task 1: Add MVP Cutline subsection to Builder's Guide

**Files:**
- Modify: `docs/builders-guide.md` — insert new `### MVP Cutline Work Requires the Build Loop` subsection between §2.0's closing separator and the `### The Build Loop` header.

**Why:** The Builder's Guide is the authoritative methodology doc. The rule needs its full explanation (statement + rationale + 3 worked examples + recovery guidance) here, where agents and orchestrators consulting the guide will see it in-context between the Init steps and the Build Loop they govern.

- [ ] **Step 1: Confirm the insertion point**

Run: `grep -n 'Verify before building the first feature\|^### The Build Loop' docs/builders-guide.md`
Expected output includes two lines approximately:
```
954:**7. Verify before building the first feature:**
967:### The Build Loop
```

(Line numbers may differ slightly; this confirms the anchors exist.) The new subsection goes between the final `---` separator that closes §2.0's "Verify" checklist and the `### The Build Loop` header.

- [ ] **Step 2: Insert the subsection**

Find the line that contains exactly `### The Build Loop` (closest-preceding anchor to the insertion point). Insert the following block **immediately before** that line:

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

(Note the trailing `---` separator and blank line — that separator visually closes the new subsection, matching the style of the Build Loop subsection immediately below.)

- [ ] **Step 3: Verify placement via grep ordering**

Run:
```bash
grep -n 'Verify before building the first feature\|MVP Cutline Work Requires the Build Loop\|^### The Build Loop' docs/builders-guide.md
```

Expected: three lines in ascending line-number order. The "MVP Cutline Work Requires the Build Loop" line's number must fall **between** the "Verify before building" line and the "### The Build Loop" line. If the order is wrong (the new subsection inserted at the wrong place), undo and re-do the insertion.

- [ ] **Step 4: Verify exact subsection title**

Run:
```bash
grep -c '^### MVP Cutline Work Requires the Build Loop$' docs/builders-guide.md
```

Expected: `1`. Any other value means the header is malformed (extra spaces, wrong `#` count, typo).

- [ ] **Step 5: Commit**

```bash
git add docs/builders-guide.md
git commit -m "docs(builders-guide): MVP Cutline work always requires Build Loop (BL-007)

Adds a new subsection between §2.0 (Project Initialization) and §2.1
(Build Loop) that codifies the rule: any item above the MVP Cutline
in PRODUCT_MANIFESTO §5 requires the full Build Loop (tests first →
implement → audit → document → record), regardless of which Phase 2
sub-step it first appears in.

Includes rationale, three worked examples of init steps that can
disguise Cutline work (data model, agent-init, CI/CD), a 'how to
spot it' diagnostic, and recovery guidance for drifted work.

Trigger: lancache Phase 2 audit (2026-04-22) — ID1 and ID3 committed
as feat(init): without going through the Build Loop; drift caught
post-facto by --record-feature.

Companion CLAUDE.md template update lands in Task 2."
```

---

## Task 2: Add MVP Cutline bullet to CLAUDE.md template

**Files:**
- Modify: `templates/generated/claude-md.tmpl` — insert new bullet in the "Your Constraints" block immediately after the existing "One feature at a time" bullet.

**Why:** CLAUDE.md is what the agent reads at every session start. Builder's Guide carries the full explanation; CLAUDE.md carries a compact reminder so the rule is visible even when the agent skims. The bullet points at the Builder's Guide subsection for the worked examples.

- [ ] **Step 1: Confirm the anchor bullet exists**

Run: `grep -n 'One feature at a time' templates/generated/claude-md.tmpl`
Expected output: one line, approximately:
```
70:- **One feature at a time:** Complete the full Build Loop (test → implement → security audit → document) per feature before starting the next.
```

(Line number may differ; this confirms the anchor bullet exists at its expected location.)

- [ ] **Step 2: Insert the new bullet immediately after**

The new bullet goes on the line **after** the "One feature at a time" bullet. Use sed-safe insertion or direct file edit. The content to insert (indentation matches sibling bullets — no leading indentation, single space after dash):

```markdown
- **MVP Cutline work is always Build Loop work.** If a Phase 2 initialization step (repo setup, scaffolding, data model, pre-commit, CI/CD, or verification) produces code that implements an item above the MVP Cutline in `PRODUCT_MANIFESTO.md` §5, that code requires the full Build Loop — tests first, implement, security audit, documentation, `--record-feature` — regardless of which init step it first appeared in. See `docs/reference/builders-guide.md` § "MVP Cutline Work Requires the Build Loop" for examples and recovery guidance.
```

- [ ] **Step 3: Verify adjacency to the anchor bullet**

Run:
```bash
grep -n 'One feature at a time\|MVP Cutline work is always Build Loop work' templates/generated/claude-md.tmpl
```

Expected: two lines with consecutive line numbers (the new bullet immediately follows the anchor). If the lines are far apart, the insertion went to the wrong place — undo and re-do.

- [ ] **Step 4: Verify the cross-reference to Builder's Guide subsection**

Run:
```bash
grep -c 'MVP Cutline Work Requires the Build Loop' templates/generated/claude-md.tmpl
```

Expected: `1` — the CLAUDE.md bullet contains exactly one reference to the Builder's Guide subsection title. This must match the title committed in Task 1 verbatim (Task 1's verification also confirmed the guide has exactly 1 instance at `^### MVP Cutline Work Requires the Build Loop$`).

- [ ] **Step 5: Commit**

```bash
git add templates/generated/claude-md.tmpl
git commit -m "docs(claude-md): MVP Cutline bullet + Builder's Guide pointer (BL-007)

Adds a compact bullet in the Your Constraints block (immediately after
the existing 'One feature at a time' bullet) stating the Cutline
Build Loop rule and pointing at the Builder's Guide subsection for
full examples and recovery guidance.

Completes the BL-007 two-file doc change. Builder's Guide subsection
landed in prior commit."
```

---

## Post-implementation verification

After both tasks are complete, run the three cross-reference checks from the spec to confirm the edits are internally consistent:

```bash
# Check 1: Builder's Guide subsection title exists exactly once
grep -c '^### MVP Cutline Work Requires the Build Loop$' docs/builders-guide.md
# Expected: 1

# Check 2: CLAUDE.md references the same title
grep -c 'MVP Cutline Work Requires the Build Loop' templates/generated/claude-md.tmpl
# Expected: 1

# Check 3: placement ordering in Builder's Guide
grep -n 'Verify before building the first feature\|MVP Cutline Work Requires the Build Loop\|^### The Build Loop' docs/builders-guide.md
# Expected: three ascending line numbers; MVP Cutline title falls between the other two
```

All three must return the expected values. If any fails, return to the task that owns the affected file and correct the insertion.

---

## Plan Self-Review Checklist

**Spec coverage:**
- [ ] Decision 1 (generic wording) — Task 1's subsection text uses "items above the MVP Cutline in PRODUCT_MANIFESTO §5"; no F-ID/ID-ID prefixes anywhere.
- [ ] Decision 2 (Builder's Guide + CLAUDE.md) — Task 1 covers Builder's Guide; Task 2 covers CLAUDE.md. No other files touched.
- [ ] Decision 3 (full subsection with rationale + examples) — Task 1's subsection includes rule, rationale (with lancache attribution), 3 examples, diagnostic, recovery.
- [ ] Cross-reference strategy (spec §Architecture) — CLAUDE.md bullet points at `docs/reference/builders-guide.md § "MVP Cutline Work Requires the Build Loop"`; verification Check 2 ensures the title matches verbatim.
- [ ] Verification (spec §Verification) — three checks carried into this plan's verification section plus per-task grep steps.

**Placeholder scan:**
- [ ] No "TBD" / "TODO" / "similar to Task N" anywhere.
- [ ] All content is shown verbatim (subsection text in Task 1 Step 2, bullet text in Task 2 Step 2).
- [ ] All commands are exact and runnable.

**Type / name consistency:**
- [ ] Subsection title `### MVP Cutline Work Requires the Build Loop` consistent across Task 1 (insertion), Task 1 Step 4 (verification), Task 2 Step 4 (cross-reference verification), and post-implementation Check 1/2.
- [ ] CLAUDE.md bullet lead-in `**MVP Cutline work is always Build Loop work.**` (lowercase "work") is distinct from subsection title (Title Case "Work Requires") — this is intentional: the bullet is a statement, the title is a heading. Both verification checks account for this.

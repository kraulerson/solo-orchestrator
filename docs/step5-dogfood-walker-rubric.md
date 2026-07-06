# Step-5 Dogfood Walker Grading Rubric

**Applies to:** the Step-5 "dogfood" sweep — the fan-out validation exercise
where a matrix-enumerator agent produces a scenario matrix (fresh-project
lifecycles across deployment/gov_mode/track/platform/language/data-
classification), a set of walker agents each fresh-init and walk a disjoint
subset of scenarios through the framework's real phases and gates (no mocks),
and a synthesizer agent aggregates walker verdicts into a report.

This document is the walker's grading contract. It formalizes practice that,
before BL-062, existed only as an inline "walking contract" description in
each sweep's own methodology section (see, e.g., `Reports/2026-06-29-step5-
dogfood-validation.md` § Methodology) — never as a standalone, versioned
rubric. It is doc-only: it changes how a human or agent grades a walked
scenario, not any framework code.

---

## 1. Grades

Each walked scenario gets exactly one of:

| Grade | Meaning |
|---|---|
| `pass` | Every assertion in the scenario's contract held, and the observed artifact matches the contract's `expected_terminal_state` text with no unresolved disagreement. |
| `partial` | The scenario mostly worked (no gate/enforcement failure), but at least one aspect of the observed artifact diverges from what the contract's `expected_terminal_state` literally says, and that divergence has not yet been dispositioned as "expected." |
| `fail` | A gate, enforcement point, or assertion did not hold — a real contract violation. |
| `skip` | The scenario was out of scope for this sweep (illegal combination, unassigned, or explicitly deferred) — not walked at all. |

## 2. The default-to-`partial` rule (BL-062)

> **When the matrix's `expected_terminal_state` text and the observed
> artifact disagree, the grade defaults to `partial` — never `pass` —
> pending a doc-vs-product resolution.**

A walker must not resolve an `expected_terminal_state` vs. observed-artifact
disagreement by picking whichever reading is more lenient and grading `pass`.
Both a "the artifact is actually fine, the wording is just imprecise" reading
and a "the artifact is wrong" reading are almost always *available* at grading
time — that is exactly what makes the lenient reading tempting. The walker's
job is to **flag the disagreement**, not paper over it:

1. Grade the scenario `partial`.
2. Record, verbatim, both (a) the `expected_terminal_state` text and (b) the
   observed artifact content that diverges from it.
3. Open (or point to) a backlog item that will carry the disagreement to a
   disposition. Do not let the sweep's headline pass-rate silently absorb it.

**Why this is the default, not a judgment call left to the walker:** a
lenient-reading `pass` and a `partial`-then-disposed disagreement are
indistinguishable in the sweep's final report unless the walker is required
to surface every case. Defaulting `pass` here means a *real* regression that
happens to share the same shape (contract text says X, artifact shows
not-X) would also get silently graded `pass` — the exact failure mode this
rubric exists to prevent. The cost of over-flagging (an extra `partial` that
gets dispositioned as "doc was wrong, no product bug") is a few minutes of
triage. The cost of under-flagging is a hidden regression shipping behind a
green sweep.

This rule does not require the walker to determine *which* side is wrong
(matrix wording vs. template/product behavior) — only to grade `partial` and
flag it. Disposition is a separate, later step (§3).

## 3. Worked example — Sponsored POC "3 rows documented vs. 6 rows surfaced"

Source: `Reports/2026-06-29-adversarial-certainty-pass.md` §4 (`The one
disagreement — migration-private-poc-personal-to-sponsored-poc-org`).

**Scenario:** `migration-private-poc-personal-to-sponsored-poc-org` — init a
`personal` / `private_poc` project, then run
`bash scripts/upgrade-project.sh --to-sponsored-poc --non-interactive`.

**What the matrix's `expected_terminal_state` says:**

> "APPROVAL_LOG restructured with the 3 Sponsored-required rows visible"

**What the observed artifact actually contains:**

`APPROVAL_LOG.md` after the upgrade contains **all 6 Pre-Phase 0 rows** (with
blank Date columns) — not just the 3 Sponsored-required rows the contract
text promised. Every other state mutation matched contract (`poc_mode`
flipped correctly, `deployment` flipped correctly, `data_classification`
preserved, Phase-4 hard-block fired correctly).

**What the original walker graded:** `pass` — by accepting a "this is just
documented template behavior, the matrix wording is imprecise" framing.

**What this rubric requires instead:** `partial`. The `expected_terminal_state`
text and the observed artifact disagree (3 rows promised, 6 rows surfaced);
per §2, that disagreement is graded `partial` regardless of how plausible the
lenient reading is, and flagged rather than silently accepted.

**The three resolution paths** (this is where the walker's job ends and a
disposition process picks up — see BL-058 for this scenario's specific
disposition track):

1. **Product fix.** The template is wrong: it should actually hide the 3
   non-Sponsored-required rows so only the 3 promised rows are visible.
   Fix the template/upgrade script; re-walk the scenario; it should now grade
   `pass` against the same contract text.
2. **Doc fix.** The matrix's `expected_terminal_state` wording is wrong: the
   template's "all 6 rows, blank dates" behavior is the intended design (row
   deferral is enforced later, at `--to-production` time, not by hiding rows
   at Sponsored-POC time). Fix the matrix wording to say what actually
   happens; re-walk (or re-grade) the scenario against the corrected text —
   it should now grade `pass`.
3. **Re-grade after disposition.** Once either (1) or (2) lands, the scenario
   is re-graded (not left at `partial` indefinitely). A `partial` grade is a
   pending state, not a terminal one — it must resolve to `pass` (contract
   and artifact now agree) once the doc-vs-product question above is
   answered. It does not resolve itself by aging out.

## 4. Non-goals of this rubric

- This rubric does not adjudicate *which* of the two readings is correct for
  any given disagreement — that is a product/doc decision, tracked as its own
  backlog item (e.g., BL-058 for the worked example above).
- This rubric does not change what counts as a `fail` (a hard gate/enforcement
  violation is still `fail`, independent of any `expected_terminal_state`
  wording question).
- This rubric is doc-only — it does not add or change any framework script.
  Enforcement is procedural: whoever commissions the next Step-5 sweep points
  walkers at this document as part of the walking contract.

## 5. See also

- `Reports/2026-06-29-step5-dogfood-validation.md` — the sweep this rubric
  formalizes practice from (§ Methodology describes the walking contract that
  predates this document).
- `Reports/2026-06-29-adversarial-certainty-pass.md` — the adversarial re-walk
  that surfaced the need for this rule (§4, § Tailoring signals catalog S-5).
- Backlog BL-058 — the product-vs-doc disposition for the worked example in
  §3 above.
- Backlog BL-063 — a sibling rubric-tightening item (enforcement-point
  contracts asserting message-present vs. message-only); same report, same
  rubric surface, tracked separately.

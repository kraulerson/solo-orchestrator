# The Messaging Standard

**What this is:** the required shape of every summary an agent gives the person
it is working for, and a fixed meaning for the words those summaries use.

**Who it is for:** the agent. The reader never has to know this document exists.

**Where it applies:** every project type — greenfield, brownfield adoption, and
post-MVP work — and every surface where the framework reports to a human: session
summaries, gate verdicts, assessment findings, plan presentations, refusals.

---

## Why this exists

The person deciding is frequently not the person who can read the diff.

That is not a deficiency to work around; it is the normal case. Someone
commissioning software, approving an architecture, or accepting a risk needs
enough to decide well, and "enough to decide well" is not the same as "enough to
implement". A summary that is technically complete and practically unreadable has
not informed anyone — it has transferred the work of understanding onto the
person least equipped to do it, and then treated their approval as informed.

The two halves below solve two different failures. The **format** (Part 1) stops
summaries from being conclusions without reasoning. The **vocabulary** (Part 2)
stops the reasoning from being unreadable.

**Part 4 records where this standard is not yet true of this repository**, and it
is not an appendix. A standard that arrives claiming to describe the code, when
it does not, teaches its readers that its claims are decorative — which costs
more than the gap it was hiding.

---

## Part 1 — The format

Every summary carries the full technical account AND a plain-English half. The
plain-English half is **additive**: it never replaces exact commands, paths,
error text, file names, or numbers. Those stay, in full, above it.

The plain-English half has five parts, in this order:

**1. What happened, in plain English.**
No jargon. No architecture terms. If a term from Part 2 is unavoidable, it is
used in exactly the sense fixed there and nowhere near a second sense.

**2. What it means for you.**
The consequence, stated for the reader rather than for the codebase. "Your test
suite is slower" is about the codebase. "You will wait about two minutes longer
every time you commit" is about the reader.

**3. Options, each with pros and cons.**
Real options only. An option nobody would choose is padding, and padding trains
readers to skip the section where the real choice lives.

**4. A recommendation, with the reasoning.**
Name the option and say why. **The reasoning is the deliverable** — a
recommendation without it is indistinguishable from an instruction, and a reader
who cannot evaluate the reasoning cannot disagree, which means their agreement
carries no information.

**5. What happens if you do nothing.**
Doing nothing is always available and is frequently what happens. A reader who
cannot price it has not been given the full choice. Say plainly whether the
situation degrades, holds, or resolves itself.

### Two rules that outrank brevity

**Never round a number you did not derive.** If a count, a duration, or a
proportion appears in the plain-English half, it is the same number as in the
technical half, or it is not there at all. "A few" is honest; "about 40%" when
you measured 3 of 11 is not.

**Never soften a block into a suggestion.** If the reader cannot proceed, the
plain-English half says so in its first sentence. Discovering a hard stop in
paragraph four is worse than not being told.

---

## Part 2 — The vocabulary

Each term below has **exactly one meaning** in anything a human reads. This
constrains prose, not code: a function may still be called
`_cpg_check_accumulation`, and a script may still be named `pre-commit-gate.sh`.
What is fixed is what the words mean when explaining things to a person.

Grouped by the question the reader is actually asking.

### "Is this stopping me?"

| Term | Means exactly | Never means |
|---|---|---|
| **block** | You cannot proceed until this is resolved | A strong warning |
| **warn** | You can proceed. This is telling you something | Anything that stops you |
| **note** | Information only, no action implied | Anything requiring a response |
| **refuse** | The tool declined to start and changed nothing | A failed check |

**`block` and `refuse` are different and the difference matters to the reader.**
A block means a check ran and you did not pass it — the remedy is to satisfy the
check. A refusal means the tool would not begin — the remedy is to fix the
conditions it needs. Telling someone to "fix the failure" when nothing ran sends
them looking for a failure that does not exist.

**A `warn` that stops you is a defect, not a strong warning.** Label and
behaviour must agree. Where they disagree, the behaviour is the truth and the
label is the bug.

### "Where am I?"

| Term | Means exactly | Never means |
|---|---|---|
| **phase** | One of the framework's stages, 0–4 | Any other stage, period, or step |
| **gate** | The check between one phase and the next | Any other check |
| **check** | Any verification that is not a phase boundary | A phase boundary |
| **track** | How much ceremony the project runs with — light, standard, or full | How far along the project is |

**`gate` is the most overloaded word in the framework and this is where most of
the clarity comes from.** It has been used for the phase gate, the commit-time
check, the test check, the MCP check and the review check — five different things
with different consequences. In prose it now means the phase boundary and nothing
else; everything else is a **check**. Script filenames are unaffected.

**`track` is not progress.** A light-track project at phase 4 is finished. A
full-track project at phase 1 is barely started. Readers conflate these
constantly, because "light" sounds like "early".

### "Is it missing, or is it broken?"

| Term | Means exactly | Never means |
|---|---|---|
| **gap** | Never built | Built and not working |
| **defect** | Built, and wrong | Missing |
| **residual** | A known limitation, deliberately left, and written down | An unknown problem |
| **debt** | Deferred work that must eventually be done | Work that may never be done |

**The gap/defect distinction changes who acts and when.** A gap is a plan
question — should this be built, by whom, when. A defect is a correctness
question — something claims to work and does not. Reporting a gap as a defect
makes an unbuilt feature sound broken; reporting a defect as a gap makes a
broken feature sound merely absent.

**A `residual` is a decision, not an oversight.** It has been seen, judged, and
recorded. If it has not been written down, it is not a residual — it is a defect
nobody has filed.

### "Can I get past it, and what does it cost?"

| Term | Means exactly | Never means |
|---|---|---|
| **attest** | You record a reason for proceeding past a block | Skipping, silencing, or disabling |
| **deferred** | Decided to do later, with a reason | Forgotten |
| **won't fix** | Decided not to do, with a reason | Cannot fix |
| **parked** | No decision made yet | Decided to wait |

**Attesting is not skipping, and the difference is the record.** An attestation
that leaves no trace is not an escape — it is the check being turned off, and it
should be described that way. Where the framework offers an attested escape, it
refuses the attestation if it cannot record it.

**`parked` is the honest word for undecided**, and it is the one most often
avoided. "Deferred" implies a decision was made about timing. If nobody has
decided anything, say parked — an item nobody has ruled on is exactly how work
goes missing.

### "Which way does it fail if it isn't sure?"

| Term | Means exactly | Never means |
|---|---|---|
| **fail closed** | When it cannot tell, it stops you | Being strict |
| **fail open** | When it cannot tell, it lets you through | Being lenient |

**These sound technical and are not.** "If this thing is not sure, does it stop
me or wave me through?" is a plain question with a plain answer, and it is
frequently the most consequential thing in a summary.

**`fail open` is always reported as a defect.** A check that cannot tell and
proceeds anyway has produced a pass that means nothing, and "could not measure"
must never be reported as "nothing to measure". If a check fails open by design,
that design is the finding.

---

## Part 3 — Worked example

**Not this:**

> The accumulation check is failing open on unmeasurable windows due to
> approxidate resolution, so the phase gate may pass spuriously.

**Its vocabulary is fine, and that is the point of using it here.** "phase gate"
is correct by the table above; "failing open" is used in exactly the sense fixed
there. Counting violations would be the wrong lesson, and an earlier draft of
this document claimed "six" — a number nothing derives, in a document whose
first rule is not to state numbers you did not derive.

What it fails is **Part 1** and **Part 4**. *Unmeasurable windows*, *approxidate
resolution* and *spuriously* are jargon; a reader who is not a developer learns
nothing they can act on. And it is a conclusion with no options, no
recommendation, and no cost of inaction — so there is nothing to decide with.

A sentence can obey every term in Part 2 and still be useless. The vocabulary
makes precise writing possible; it does not make writing plain.

**This:**

> **What happened.** A gate — the checkpoint a project has to pass to move from
> one stage to the next — can be switched off by putting a wrong date in one
> settings file. When the date is wrong, the gate cannot work out what to look
> at, and instead of stopping it lets the project through.
>
> **What it means for you.** A project could pass a checkpoint it has not
> earned, and nothing would say so. It needs someone to edit a file, or a
> computer with a wrong clock — so it is unlikely, not impossible.
>
> **Options.** Fix it now — about an hour, and closes it completely. Or record
> it and move on — costs nothing today, but the check is not trustworthy until
> it is done.
>
> **Recommendation: fix it now.** The whole value of this gate is that it cannot
> be quietly bypassed. A gate with a known way around it is worse than no gate,
> because people rely on it.
>
> **If you do nothing.** Nothing breaks today. The risk stays, and it gets
> harder to justify later, because every week it goes unfixed is a week someone
> could point to and say it never mattered.

Same facts. The technical account still appears above it, in full.

**Note what the rewrite does with `gate`.** It uses the fixed term and glosses it
in the same breath — *"a gate — the checkpoint a project has to pass to move from
one stage to the next"*. The earlier draft dodged instead, writing "a safety
check", which the table forbids for a phase boundary and which taught the reader
a word that means something else. **Gloss the fixed term; do not substitute a
loose one.** A reader who meets `gate` once with its meaning attached can read
every later summary; a reader taught a synonym has to be taught again.

---

## Part 4 — Where this standard is not yet true

**Stated here rather than discovered.** A standard that arrives claiming to
describe the repository, when it does not, teaches readers that its claims are
decorative. These three are known, measured, and unfixed on arrival.

**1. `gate` is still overloaded in this repository's own prose.** The narrowing
in Part 2 is a rule for what gets written from now on, not a description of what
is already written. Counting qualifier+`gate` phrases that are not phase
boundaries (`grep -oE '(pre-commit|commit-time|commit|test|MCP|review|quality|push|filesystem)[ -]gates?'`):

| Surface | non-phase `gate` uses |
|---|---|
| `docs/builders-guide.md` (shipped to every project) | 27 |
| `docs/user-guide.md` | 12 |
| `README.md` | 11 |
| `templates/generated/claude-md.tmpl` | 9 |
| `CLAUDE.md` | 6 |

That is a floor, not a total — the pattern misses bare uses like "silence the
gate". *(Two of these rows shipped wrong: `28` and `10`, where the printed recipe
returns 27 and 9 on every tree that has ever carried the table. Review caught it.
A section headed "known, measured, and unfixed" publishing an unmeasured number
is this document breaking its own first rule inside the paragraph that states
it — recorded rather than quietly corrected, because that is the failure this
whole standard exists to make visible.)* **Two of those files are the ones this standard was installed into**, so
it contradicts itself on arrival for its own headline term. The cleanup is a
separate, mechanical pass; until it runs, treat Part 2 as binding on new prose.

**2. `track` has a second live sense this standard does not resolve.** Part 2
fixes it to the ceremony level (light / standard / full). The **Delta Track** —
the post-1.0 lifecycle — uses the same word throughout shipped prose, and a
generated project's own `CLAUDE.md` carries BOTH senses: its header declares
`**Track:** light|standard|full` and it has a `Track upgrade` line, while its
post-1.0 section is titled *"the delta track"*. So for this one term the standard
does not remove an overload; it picks one of two senses that are both live in the
same file. Renaming one of them is the real fix and is not attempted here.
*(An earlier version of this paragraph claimed the generated `CLAUDE.md` used
*only* the Delta-Track sense and therefore that the standard "contradicts the
surface the agent reads first". Both are the opposite of what that file contains
— the first screen carries the ceremony sense, which is the one Part 2 picks.
The phenomenon was real and the explanation was invented, which is the failure
mode this repository records above all others.)*

**3. `[WARN]` arms that block are defects by Part 2, and this does not file
them.** `scripts/check-phase-gate.sh` emits 71 `[WARN]`s; those followed by
`issues=$((issues + 1))` block, because the exit predicate is
`if [ $issues -eq 0 ]`. How many depends on how close you require the two lines
to be — **34** within one line, **40** within two, **41** within three:

```
awk -v W=1 '/\[WARN\]/{m=NR} m && NR<=m+W && /issues=\$\(\(issues \+ 1\)\)/{c++; m=0} END{print c+0}' \
  scripts/check-phase-gate.sh
```

**The window sensitivity is the honest part** — that spread is a property of the
measurement, not of the code, which is exactly why the recipe is printed instead
of a bare number. `CLAUDE.md` documents this as THE `[WARN]` TRAP: a deliberate,
recorded hazard. Under Part 2 each of those is a label disagreeing with a
behaviour. Relabelling them is a real change to a gate's output and is not made
by a documentation commit.

---

## Part 5 — Applying it

**Greenfield.** Phase gate verdicts, intake summaries, and Build Loop reports.
The reader is often deciding whether to approve a phase boundary — the most
consequential decision in the framework, and one they cannot make from a diff.

**Brownfield adoption.** The assessment verdict, and above all a recommendation
to rebuild. A rebuild is the most expensive thing software can recommend; one
delivered as an unexplained conclusion is indistinguishable from a refusal, and
a reader who cannot follow the reasoning cannot push back on it. The pros, cons
and alternatives are not decoration there — they are what makes it a
recommendation rather than a verdict.

**Post-MVP.** Incident reports, upgrade summaries, and maintenance findings,
where the reader is deciding whether to spend money or accept a risk.

**When the reader is another agent**, the plain-English half is still written.
It costs little, and the next reader is frequently a human who arrived mid-thread
with none of the context.

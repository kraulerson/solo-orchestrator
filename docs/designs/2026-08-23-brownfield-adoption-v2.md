# Brownfield Adoption — architecture design v2

## Document Control

| Field | Value |
|---|---|
| **Document ID** | ADOPT-002-ARCH |
| **Version** | v2.0, 2026-08-24; reconciled pre-landing 2026-08-28, and again across four passes on 2026-08-31 (§0.3). Supersedes ADOPT-001-ARCH (`docs/designs/2026-08-02-brownfield-adoption-v1.md`) in full. |
| **Supersedes — and overturns** | **This is the first document in this feature's history that overturns a settled decision, and it says so here rather than in a footnote.** v1's §0.1 lists the scenario chooser (v1-D2, Karl's verbatim question) among the decisions carried into that design; v1's every amendment was able to say *"no settled decision, decision table, or WP boundary changed."* **This document cannot say that and does not.** Karl's D4 (2026-08-23, recorded in `## BL-242:`) deletes the chooser outright — not demotes it — and D5/D6 redraw the work-package boundaries. §0.2 maps every v1 decision to its v2 disposition: carried, re-derived, or overturned. |
| **Classification** | Product architecture — normative-once-reviewed for the build. **Two adversarial architecture rounds have run** (r1: block on two structural findings; r2: B1 dissolved by execution, block on B2). B2 and r2's three new gaps are answered in §8.3a as **A1–A4**; those answers have not themselves been reviewed. |
| **Audience** | (a) the adversarial design reviewer this document must survive; (b) the implementer of the work packages in §10 |
| **Subject** | **Brownfield adoption, second architecture** — an existing codebase enters Solo Orchestrator through four acts: a read-only survey, a deterministic shell preparation that lands the project at phase 0, a model-driven assessment, and a documented plan the project proceeds from — **starting at the beginning, with no rung derived by anyone** (D10). Adoption **assesses** rather than asking the operator to classify the project; it asks exactly one thing — who the project is for (D9). |
| **Companion documents** | ADOPT-001-ARCH (superseded; kept as the record of the first build and of §-citations in shipped code — see §0.2) · `## BL-242:` in `solo-orchestrator-backlog.md` (the D1–D10 decision record this document designs from) · `docs/adoption.md`, `docs/scout.md` (the shipped user-facing pages, which describe the v1 build and must be revised by §10-WP12) · `docs/messaging-standard.md` (the presentation contract D8 makes binding) · `docs/module-contract.md` (M1–M5) · SOI-002-BUILD (`docs/builders-guide.md`) |
| **Status of the thing described** | **NOTHING OF v2 IS BUILT.** v1's status row was wrong three times because it was a hand-maintained list; this row is a **set of derivations** instead, each printed in §13 with its output on **2026-08-24**. (1) *What the v1 build left unbuilt* is the set of `adopt_stub_*` functions actually called — the recipe in §1.2 returns **7**. (2) *That the chooser still exists* — `# BF-ADOPT-CHOOSER-QUESTION` resolves in `scripts/lib/adopt/adopt-chooser.sh` (§13-V7). (3) *That adoption still runs no tool resolution* — `grep -c 'resolve-tools'` over the driver and its lib returns **0** in every file, against **7** mentions in `init.sh` (§13-V3). (4) *That `scripts/resume.sh` knows nothing of adoption* — `grep -c 'adopt' "scripts/resume.sh"` returns **0** (§13-V8). When any of those derivations stops returning what this row says, this row is stale — re-run them; do not quote them. **A caveat the derivations themselves taught:** the framework's install set measured **65** files on `main` and **67** on the branch this document was verified on, because two PR-review scripts joined the shipped set between the two — and **68** re-derived on 2026-08-31 against the `main` this document lands on (§13-V6). Three values in eight days. A count in this document is a measurement with a date and a branch, never a property. |

**Provenance.** Ten architecture decisions — **D1 through D10** — are settled and recorded in
`## BL-242:` in `solo-orchestrator-backlog.md`. **D1–D8** were settled **by Karl on 2026-08-23**
(D2 refined 2026-08-25); **D9 and D10 on 2026-08-31**, each ruling a question this document had
wrongly read as already answered — D9 a deletion D4 never ordered (§4.2), D10 a placement
mechanism D4 never asked for (§4.3). This document
**transcribes** them and designs *within* them; it does not relitigate them. §0.1 attributes each
decision. Implementation freedom inside a settled decision is the author's and is labelled
**author-proposed** wherever it appears — a reviewer may attack an author-proposed mechanism
freely, and may not treat a settled decision as open.

**Structural model.** ADOPT-001-ARCH is this document's own exemplar: Document Control with a
status row, §0 traceability, a plain-English opening, decision tables with one recommendation and
stated rejected alternatives, work packages with boundaries and mutation proofs, honest residuals,
and a verification appendix of commands actually run. Two of its disciplines are tightened here on
its own evidence: **every count is a derivation, never a transcription** (its status row was wrong
three times; its PR table could not be reproduced by any one-liner — both recorded in `## BL-242:`),
and **the plain-English half is written to `docs/messaging-standard.md`**, which post-dates v1 and
which D8 makes part of the product requirement rather than a courtesy.

**A note on method.** Every "exists today" claim in this document was executed against the tree on
**2026-08-24** and appears in §13 with its command and output. Claims this author could **not**
execute are listed separately and prominently in §13-U — this repository's recorded failure mode is
numbers that are right attached to explanations that are invented, and the one unrecoverable
failure is an unverified claim reported as verified. One structural caveat applies to everything
here: `## BL-242:` lives on the branch `docs/bl242-brownfield-filing` and is **not** on the branch
this document's code measurements were taken from (`feat/messaging-standard`) — §0.4 states what
that means for which claims are whose.

---

## Plain-English overview — read this first (about three minutes)

*(This overview follows the format `docs/messaging-standard.md` requires of every summary the
framework gives a person, because D8 makes that format part of what adoption must ship. The
technical account is everything below §0; this is the plain half, and it is additive, not a
replacement.)*

**What happened.** The first design for bringing an existing codebase into Solo Orchestrator was
built about halfway and then stopped, on purpose, while its owner decided what the missing half
should be. Those decisions have now been made, and one of them changes the feature's shape enough
that patching the old design would misrepresent it. This document is the new design.

The old flow began by asking you a question: is your project finished and needing support, or
still being built? Your answer decided nearly everything after it. **That question is gone.** The
reason, in its owner's words: *"trusting an end user to know what's needed is a mistake
considering they are using the orchestrator BECAUSE they are not already following a proper
SDLC."* The people this tool exists for are, by definition, the people least equipped to answer
it. So instead of asking, adoption now **looks for itself** — it inspects your code, interviews
you about what the software must actually do (how many people use it, whether it faces the
internet, how sensitive its data is), and works out where your project genuinely stands.

**One question survives, and it is not that one.** Adoption still asks *"Who is this project
for?"* — *"just me and a few people I know"*, or *"a company, a client, or people who are paying
for it"*. That is not a question about how far along your project is, which you may reasonably not
know; it is a question about who it is for, which only you can answer and no amount of reading
your code could work out. It decides how strictly the leaked-password rule treats you, and it is
the only thing adoption asks before it starts work.

Adoption now happens in **four acts**. First, a **look** that changes nothing — a read-only survey
you can run and walk away from. Second, a **safe setup**: that one question is asked first, so
walking away costs you nothing; then the framework's own files are installed,
your colliding files are moved aside into a dated archive with instructions for putting them back,
any passwords or keys found in your project's history are dealt with before anything proceeds (how
strictly depends on whether the project belongs to a company or is your own), and the project is
parked at the framework's starting stage — deliberately at the **bottom** of
the ladder, so that if you stop here and never come back, your project is guarded more strictly
than before, never less. Third, an **assessment**: an AI-driven interview and inspection, which is
only possible because act two installed the machinery it runs on. Fourth, a **plan**: your
project's documents are written and you are shown what remains — **starting from the beginning**,
because working out how far along you already are is exactly the judgement this tool exists to
make unnecessary. What the survey and the assessment learned is not thrown away: it fills in the
opening questions rather than skipping them. All of it is presented in the same two-layer form, a full
technical account plus a plain-English half with options, pros and cons, and a recommendation with
its reasoning.

One verdict the assessment can now return is **"this should be rebuilt."** That is a conclusion,
not a chore adoption performs: it hands you into the framework's ordinary new-project path with
everything it learned already filled in. And it may only say so **relative to what you told it the
software must do** — a spreadsheet-backed page serving three people once a month is fine, and a
tool that says otherwise is expressing taste, not judgment.

**What it means for you.** If you adopt a project and stop partway, you end up safer, not
stranded. If your history contains a leaked password, what happens next depends on **who the
project is for.** If it belongs to a company, a client, or anyone paying for it, **adoption
stops** until you have dealt with each finding on the record — corrected it, or accepted the risk
in writing, with your name on the acceptance. If it is your own casual project, **adoption warns
you loudly and carries on** — every finding shown, nothing hidden, nothing blocking you.

Two things can go wrong with the scan itself, and they are treated differently on your own
projects. **If the scanner ran but broke** — crashed, or produced something unreadable — your own
project gets a loud warning and carries on, with the warning saying plainly that nothing is known
about your history. **If the scanner was never installed at all**, your own project stops, and
carries on only if you accept that risk in writing. On a **company's** project neither one can be
overridden: the scan has to succeed. Act two installs the scanner itself, so both should be rare.

Some of your files — scripts and documents whose names the framework
claims — will be **replaced by the framework's versions**, with yours archived and every moved
path named, because a half-wired framework that stays silent about it is worse than an honest
swap. That includes your feature list, bug list and release notes: the originals are kept in the
archive, you are told exactly where each one went, and you are invited to copy anything worth
keeping into the new files. **Nothing is deleted, and nothing is moved silently.** If your own build calls one of those scripts, it will break at adoption, visibly, rather
than months later, silently — and the notice tells you exactly which files to look at.

**Options.** Approve this design and the build resumes on it — the cost is the build itself, plus
revising the two user-facing pages that describe the old flow. Or amend the old design instead —
cheaper on paper, but it would carry a deleted decision in its list of settled ones, which is the
kind of quiet self-contradiction its own changelog exists to prevent. Or do neither and leave the
feature half-built with its gaps honestly announced at every run, as they are today.

**Recommendation: approve this design, and fix `## BL-225:` before building any of it.** The
reasoning: the decisions are already made and recorded; the only question is whether the document
the builders read matches them. And the one live defect that actually burns an operator — a
half-staged repository with a message claiming nothing was committed — sits directly on the path
every act-two run takes, so building on top of it means shipping the burn.

**If you do nothing.** Nothing breaks today. The driver keeps announcing its own gaps at every
run, the seven unbuilt capabilities stay unbuilt, and the decision record in `## BL-242:` slowly
drifts out of anyone's working memory — which is exactly how this feature spent six weeks tracked
by a note asking whether it should be tracked.

---

## §0 — Decision traceability

### §0.1 — Settled decisions carried into this design

Ten, all Karl's, all recorded in `## BL-242:` in `solo-orchestrator-backlog.md`: **D1–D8 on
2026-08-23** (D2 refined 2026-08-25), **D9 and D10 on 2026-08-31**. This document designs **within** them. Each row names where the
design work lives and what remains author-proposed.

| # | Settled decision (Karl — D1–D8 on 2026-08-23, D2 refined 2026-08-25, D9 and D10 on 2026-08-31) | Designed in | Author-proposed inside it |
|---|---|---|---|
| **D1** | **Colliding scripts: archive theirs, install the framework's, say so.** REVERSES the shipped behaviour, where `adopt_install_framework` skips any path with `[ -e "$dst" ]` and the operator's file wins silently. The notice must name **every archived path, not a count**, plus a standing warning that **replacing a framework script with their own may break the framework**. `scripts/` becomes an archive class exactly as D3 makes documents one. | §7.1, §8.2 | The receipt check between archive and install; the notice's exact shape (§7.1) |
| **D2** | **Secrets are TIER-SCOPED: an ORGANIZATIONAL adoption STOPS, a CASUAL PERSONAL one WARNS LOUDLY and carries on.** Karl, 2026-08-23: *"Stop adoption until acknowledged with a reply of having been corrected or the risk is being accepted"*; refined 2026-08-25: *"Keep warn loudly for casual personal projects. Organizational projects are always a stop."* The stop lifts only when every finding carries a recorded acknowledgement, and an acknowledgement that cannot be recorded is refused (BL-072's shape, reused by `## BL-233:` for `SOLO_MCP_ACCUM_ATTESTED`). The tiering axis is **`deployment`**, not `enforcement_level`, which **overturns v1 §6.3 as written** — derived on 2026-08-25, not ruled a second time (§6.1). A scan that never ran is **not an acceptable state at either tier**: Karl — *"Why wouldn't the secrets scan run? That should never be an option."* **The two not-scanned statuses were ruled apart on 2026-08-31, and they differ**: `tool-unavailable` is a hard refusal at `organizational` and escapable on a recorded acceptance at `personal` (*"Yes on personal, no on organizational"*); `scan-failed` is *"action as if it ran"* — a hard refusal at `organizational` (*"it cannot continue as it's required"*) and a **loud warning that carries on** at `personal`. §6.1's ladder and §6.4 carry the reasoning. | §6 | The disposition file's location and shape; the re-scan-after-install mechanic (§6.2); the warn arm's record |
| **D3** | **Project documents: written to the framework's documentation requirements** — adapted or merged from what the project has, or written new where the assessment shows merging would carry a false picture forward. **Originals archived in the project for historical purposes.** With D1, this makes documents and `scripts/` the third and fourth classes of the collision archive — one mechanism serving four cases. **Reach ruled 2026-08-31: it covers `FEATURES.md`, `BUGS.md` and `RELEASE_NOTES.md` too — overturning v1 §7.5 — and the operator must be TOLD, by name, that content can be retrieved from the archive and added to the new files** (*"All previous info is archived and the user informed so that they may retrieve or add to the new proper framework files."*). | §7.2, §7.3 | The framework-document name set's derivation; the adapt-versus-replace criterion (§7.2); the notice's phrasing — its CONTENT is bound (§7.2) |
| **D4** | **THE CHOOSER IS DELETED, NOT DEMOTED.** No completed/in-flight question, and no "was an SDLC framework used" question either — **those two, and no others.** Karl's reasoning, verbatim, which is the load-bearing part: ***"I think trusting an end user to know what's needed is a mistake considering they are using the orchestrator BECAUSE they are not already following a proper SDLC."*** This **overturns v1-D2**, which v1 §0.1 lists among its settled decisions — see §0.2. *(`## BL-242:` heads this decision **"Adoption assesses; it does not ask."** That is the entry's headline, **not Karl's words** — the entry marks his quote separately — and reading it as a general principle is what produced the error D9 corrects. D7, also Karl's, requires asking.)* | §4 | **Nothing about the two dropped questions.** The claim that stood here — *"the deletion's blast radius is enumerated, not chosen"* — was **false, and is exactly what D9 corrects**: the enumeration silently added a third question the ruling never reached (§4.2) |
| **D5** | **FOUR ACTS**, and the split is **forced, not chosen**: the evaluators are model-driven and the driver is shell, so adoption cannot be one process. (1) **SURVEY** — Scout, read-only. (2) **PREPARE** — shell: tool resolution against the matrix; the secrets stop; the test-debt census **before** the install; the collision archive **before any writer**; install; **land at PHASE 0 PROVISIONALLY**; commit; hooks last. (3) **ASSESS** — Claude Code via `scripts/resume.sh`: the requirements interview and all evaluators. (4) **PROCEED** — documents written, plan presented, Build Loop, **from the beginning** (D10 corrects this step, which read "rung from evidence" and was never Karl's; D10 also drops the *provisionality* from step 2's landing — it is simply phase 0, because nothing was ever going to promote past it). **The provisional phase-0 landing is load-bearing**: it preserves the promise `adopt_main` already prints, so **a project cannot land high by abandonment** — the scheme cannot express that outcome. | §3, §8 | The act-boundary artifacts; the `resume.sh` branch predicate; the assessment brief's home (§8.5) |
| **D6** | **"Rebuild" is a VERDICT adoption returns, not work adoption does.** A rebuild is a Phase 0 intake, an architecture phase, a Build Loop and gates — Solo Orchestrator's **ordinary path** — so the verdict **exits into machinery that already exists**, with the intake pre-filled from everything the assessment learned. Placement, not disagreement; a bounded feature, not an unbounded one. | §5.4 | The pre-fill mapping from assessment record to intake sections |
| **D7** | **"Wrong technology" is only a finding RELATIVE TO STATED REQUIREMENTS**, and the requirements come from the interview: users, availability, exposure, scalability, data sensitivity. Karl: *"It should be part of the interview to decide that and present the reasoning to the user."* The guarded failure mode is specific: an evaluator with good taste reads the STACK and says "rebuild this in Python" without reading the REQUIREMENTS. | §5.2, §5.3 | The interview's question set beyond Karl's five; the fitness-verdict record shape |
| **D8** | **The verdict's presentation is part of the requirement**: the full technical account AND the same content as plain English with **pros, cons, options, and a recommendation with reasoning**, so a non-developer can decide. This is the communication contract Karl already requires of agents in this repository, generalised into the product — and it is what makes D6 honest: *the reasoning IS the deliverable*; a rebuild delivered as an unexplained conclusion is indistinguishable from a refusal. Since v1, this contract has a shipped, binding spelling: **`docs/messaging-standard.md`** — Part 1's five-part format and Part 2's controlled vocabulary. | §5.5 | The verdict artifact's file shape and the check that pins its two halves |
| **D9** | **THE AUDIENCE QUESTION SURVIVES D4, RE-PURPOSED AS A TIER QUESTION** (Karl, 2026-08-31). *"Who is this project for?"* — *"Just me, or me and a few people I know"* / *"A company, a client, or people who are paying for it"* — **stays**, verbatim, with its call site. `ADOPT_CHOOSER_QUESTION`, `adopt_ask_scenario` and the `claimed` operand still go, exactly as D4 says. What changes is its **job**: it stops being an input to placement and becomes the **sole producer of `deployment`** — the value D2's tiering reads (§6.1) and the key `# BL-221-ADOPT-TIER-KEYS` requires an adopted manifest to carry. **This rules on a question D4 never reached**, and is not a softening of D4: D4's reasoning is about self-reported *process maturity*, and who is paying is a fact **no evidence can determine**. | §6.5, §4.2, §8.2 | Nothing — the question text, both answers and the call all ship today and are kept verbatim |
| **D10** | **AN ADOPTED PROJECT STARTS FROM THE BEGINNING. NO RUNG IS DERIVED, BY ANYONE** (Karl, 2026-08-31). *"The project gets ingested and starts from the beginning to ask the user about what it is and what it's supposed to do"*, restating D4's reason in his own words on the same day: *"we can't trust the user to know how to follow an SDLC because if they did, they wouldn't need the framework."* Every adopted project lands at **phase 0** and runs the ordinary SDLC forward — Phase 0 intake first. What Scout, the census and the assessment learn becomes **pre-fill for that intake**, never evidence for skipping past it; that is D6's shape generalised from the rebuild verdict to every adoption. **This CORRECTS this document, not v1.** D4 deleted the chooser; §4.3 read that as *replace the operator's claimed rung with a derived one* and was titled "placement from evidence alone". Karl never asked for a replacement — deleting a question whose answer cannot be trusted does not imply computing the answer another way. `## BL-242:`'s D5 carries the correction and the recipe that shows no Karl quote ever touched rung, ladder, placement or evidence. | §2, §3.1–§3.6, §4.3, §5.1, §5.4, §8.3, §8.5, §9, §12 — the removal is wide because the mechanism was | Nothing — this decision REMOVES machinery; §4.3 names what goes |

### §0.2 — What v1 settled: carried, re-derived, or overturned

**v1 remains in the tree, superseded, for two reasons this section makes explicit.** First, it is
the design the shipped code was built against, and the shipped code **cites its section numbers
literally** — `scripts/adopt-project.sh`'s header block cites §8.1/§4.1/§8.4/§8.5,
`scripts/lib/adopt/adopt-stubs.sh` prints *"§10 gives §6.3 to no work package"* at run time, and
`docs/adoption.md` links §-numbers throughout. Until each of those files is touched by a §10 work
package, **a bare `§N` in shipped code resolves against v1**. Second, this document deliberately
**keeps v1's major-section semantics where they survive** — §6 secrets, §7 collisions, §8
mechanics, §10 build plan — precisely so those citations stay approximately true while the code
converges; the two sections where it cannot (§4, §5) are the overturned ground, and any shipped
citation into them must be treated as citing v1 until its file is reworked.

Disposition of every v1 settled decision:

| v1 decision | v2 disposition |
|---|---|
| **v1-D1** — shape: standalone read-only Scout; in-core enabling arms; severable driver module | **CARRIED.** The four acts change the driver's internal structure, not the three-homes split or the module contract (§3.7). Scout is Act 1 unchanged. |
| **v1-D2** — two scenarios chosen by Karl's verbatim question | **OVERTURNED by D4.** The first settled decision this feature has ever reversed. The question, both canned answers and the *claimed* operand of placement are deleted (§4). **The audience question was listed with them in `## BL-242:`'s blast radius, is NOT covered by D4, and D9 keeps it** (§6.5). v1 §4's evidence table survives as input to the assessment — evidence was always the honest half of that section. |
| **v1-D3** — the certification pass replacing grandfathering | **RE-DERIVED, and largely DISSOLVED into Act 3.** The *principle* — measured, recorded, failable, nothing grandfathered forward — is untouched and is D2/D5's backbone. The *mechanism* — a distinct pass certifying gates below a claimed rung — loses its object **twice over**: with no claimed rung there is nothing to certify *against*, and under **D10** there is no landed rung to certify *for* either — every adopted project starts at phase 0 and earns each boundary through the ordinary gates (§5.1). WP5 as v1 specified it is retired (§10). |
| **v1-D4** — secrets: full-history scan, redaction projection, per-finding disposition, tiered loudness | **CARRIED AND RE-KEYED by D2 — and one of the THREE `## BL-242:` counts (below).** Carried verbatim: the redaction projection (v1 §6.2's field allowlist), the disposition vocabulary (v1 §6.3: rotated / false alarm / accepted risk), and the *shape* of v1's tiering — one arm stops, one arm warns loudly. What changes is the **axis those arms key on**. v1 §6.3 keys its BLOCK arm on `enforcement_level = strict`; `# BL-180-ENFORCEMENT-DEFAULT` resolves the ordinary personal project to `strict`; Karl's 2026-08-25 ruling sends that project to the **warning** arm. The ruling therefore contradicts v1 §6.3's literal BLOCK-at-strict for the commonest project there is, so **D2 overturns v1 §6.3 as written** — `strict` there is wrong rather than ambiguous. The derivation is §6.1's and it is `## BL-242:`'s, made by derivation on 2026-08-25 rather than by asking Karl twice. Also changed: a scanner that was never there (`tool-unavailable`) is a stop at **both** arms, not a shrug — while a scan that ran and broke (`scan-failed`) follows the findings row, warning at `personal` and stopping at `organizational` (ruled 2026-08-31). |
| **v1-D5** — collision policy: archive AI-layer + git hooks; CI carve-out; project files kept | **CARRIED AND EXTENDED.** The archive mechanism and the CI carve-out stand. D1 and D3 add `scripts/` and framework-named documents as the third and fourth archive classes, which **partially reverses** v1-D5's "project files: keep theirs" cell for the framework-named subset (§7.2 states the boundary precisely). |
| **v1-D6** — mechanics: separate driver, report sections, reverse intake, state order, explicit staging, stamp, Adoption Record | **CARRIED, with two amendments.** The state order (`# BF-ADOPT-STATE-ORDER`) and explicit staging survive. The stamp loses its `scenario` and `landedPhase` fields; Act 4's assessment block is a separate additive merge, and carries no placement (§8.3). The reverse intake splits: mechanical prefill stays in Act 2; judgment questions move to Act 3, where a model conducts them (§8.2, §5.2). |

### §0.3 — Amendment changelog

**v2.0 (2026-08-24)** — initial version, written from `## BL-242:`'s D1–D8 (Karl, 2026-08-23).
Records the supersession of ADOPT-001-ARCH and the overturning of v1-D2 (§0.2). Because v1's
status row was corrected three times — each correction itself an amendment — this document's
status row is a derivation set rather than a list, so that its staleness is *detectable by
running it* rather than *discoverable by contradiction*.

**Pre-landing reconciliation (2026-08-28).** This document has never landed, so what follows is
recorded here rather than as a v2.1 amendment: the version stays **v2.0** and Document Control
carries the reconciliation date. Both items were **transcription failures against `## BL-242:` as
it stands on `main` (`9858a41`)**, not design changes — and both are in prose *about* a decision,
not in the decision:

1. **§6 recorded Karl's 2026-08-23 FIRST PASS on secrets ("every tier stops") instead of his
   2026-08-25 REFINEMENT** (organizational stops, casual personal warns loudly), and with it
   missed the axis derivation that followed. §0.1-D2, §0.2-v1-D4, §6.1, §8.2, §10-WP10, §11 and
   the plain-English overview all carried the superseded half. **THREE of D1–D3 contradict
   settled v1 text** (D1, D2 and D3), not two — §6.1 derives it and names the set it counts over,
   because it is not the same set as §0.2's four changed v1 rows.
2. **§6.4 and §10-WP10 DECIDED whether `tool-unavailable` admits the acknowledged escape**, a
   question `## BL-242:`'s asks list carries as **STILL OPEN**. Worse, §6.4 cited BL-242 as having
   resolved it, quoting a sentence — *"It stays a hard refusal."* — that BL-242 no longer contains
   (written in `8ace9a2`, removed in `4b30053`, the round that corrected the same item from *moot*
   to *STILL OPEN*). §6.4 now defers, with the author's recommendation labelled as a
   recommendation.
3. **§7.2 named `FEATURES.md` inside the framework-required document set**, deciding half of
   D3's reach — `## BL-242:`'s other live question, which v1 §7.5 settles the other way. §7.2 now
   defers on all three of `FEATURES.md` / `BUGS.md` / `RELEASE_NOTES.md`.

**One question was NEW, and it has since been ruled.** The tiering must read `deployment`;
`## BL-242:`'s D4 blast-radius line deletes `adopt_ask_audience`, which is `ADOPT_DEPLOYMENT`'s
only writer in the shipped driver (§13-V15). The untiered draft had no such dependency, so the
refinement did not create the hole but did make it load-bearing.

**2026-08-31 — D9 added, and one of this document's own claims retired as false.** Karl, asked
when he had ever said to stop asking the operator questions, established that **he had not**: the
`adopt_ask_audience` deletion entered D4 through the blast-radius **enumeration**, never through
the ruling, and the headline *"Adoption assesses; it does not ask"* is `## BL-242:`'s phrasing
rather than his words. He then ruled — **keep the audience question, re-purposed as a tier
question** (D9). Consequences recorded here rather than left to a diff: §0.1 gains D9, and its D4
row retires the claim *"the blast radius is enumerated, not chosen"*; §4.2 keeps
`adopt_ask_audience` (and corrects the file it was filed under); §6.5 turns from an open question
into a settled section; §3.3 and §8.2 gain the question as **step 1** of Act 2's order and
renumber; §10-WP9 keeps it under a mutation proof and §10-WP10 loses its blocker; §12's open set
drops from three to two. **The author's proposed fallback was WITHDRAWN as unnecessary, not
adopted** — §6.5, §13-V16.

**2026-08-31, second pass — the last two open questions ruled, and both had been posed badly.**
Karl answered both by saying he had already answered them, and on the second he was simply right.
(1) **`tool-unavailable`'s escape is TIER-SCOPED** — *"Yes on personal, no on organizational."*
This document and `## BL-242:` had both posed a **global binary** (hard refusal everywhere, or the
escape everywhere) inside a decision whose every other rule already had two tiers; the author
recommended the first arm. **Neither arm was the answer.** §6.1's table splits the
`tool-unavailable` row, §6.4 is rewritten, and a sentence of this document's own — *"the tier
governs one row of that table and no other"* — is retired as false. (2) **D3 reaches
`FEATURES.md`, `BUGS.md` and `RELEASE_NOTES.md`**, overturning v1 §7.5, **and the operator must be
told by name that content can be retrieved from the archive into the new files** — the informing
is part of the requirement (§7.2), and it binds WP11's disclosure and WP12's writing. §12's open
set drops from **two to one** — it was three before this day's first pass, which took it to two — and that one is new and narrow: whether `scan-failed` takes the
same tier split (§12 item 15).

**2026-08-31, third pass — item 15 ruled the same day it was raised, and the open set is now
EMPTY.** Karl: *"So action as if it ran. Personal project, it can continue with large warning.
Organizational, it cannot continue as it's required."* `scan-failed` therefore behaves like a scan
that RAN — loud warning and carry on at `personal`, hard refusal at `organizational` — and **not**
like `tool-unavailable`, which was this author's recommendation. §6.1 gains a severity ladder in
place of the two-line claim that kept being wrong about how many rows the tier reaches (three, not
one, not two). **Two of the four questions in §12 were ruled against a stated recommendation**
(items 12 and 15) and both are marked, so the document's prediction record stays auditable.

**2026-08-31, fourth pass — an adversarial pre-PR review blocked this document and thirteen
findings were fixed.** Recorded here because this pass changed more than the second or third did,
and because §0.3's job is to carry consequences rather than leave them to a diff. The review broke
none of the four rulings — it attacked every attribution and every code claim and they held — and
found instead that **the rulings had been applied where they were argued and not where they were
summarised**: `## BL-242:`'s D2 headline still stated the rule `scan-failed` had just been
released from, and the same stale half sat in §6.1's heading and four design sites, one of which —
§10-WP10's scope cell — contradicted itself inside one table cell. It derived nine further errors — most
of them counts and citations, and among them the self-review's own "eight decisions" over a
nine-row table, its "two places" against three, an install set stated as 65/67 that returns 68 on
today's `main`, and a §13-V7 claim about this file that this file's own later edit had falsified.
**§10-WP10 claimed eight proof cells and specified six**; the missing pair was the clean-scan row,
so a mutation making a *clean* scan stop survived the whole matrix. A verification pass then found
four defects introduced by those very fixes, and **every one was in a sentence describing a
previous defect** — including a citation to a sentence
this very pass had deleted, inside the section that exists to warn against exactly that. A **third
round** verified those six and found exactly one survivor: **this paragraph**, which listed
§10-WP10's scope cell beside the four design sites it is one of — a miscount inside the account of
the miscounts. The general rule that came out of all three, and the one to apply next time:
**describe, never total, and quote only what a grep can still find.** The yield across the three
rounds fell thirteen, four, one, and every defect after the first round was in self-referential
correction prose — which is now this document's only remaining defect surface.

**2026-08-31, fifth pass — D10, and the largest correction this document has taken.** An
adversarial architecture review — the first this design has had, and distinct in kind from the
three rounds recorded in the fourth-pass entry below, which reviewed the DIFF rather than the
architecture returned **block** on two structural findings, of which only the first is this decision's
business: a project
placed at a derived rung is illegible to `scripts/check-phase-gate.sh`, which is cumulative by its
own contract and whose adoption arm reads the stamp for integrity only — so every adopted project
landed above phase 0 would fail its next gate run, and §9's "no gate arms" forbade the fix. Karl
then supplied the answer the design should have had from the start: **an adopted project starts
from the beginning.** *"The project gets ingested and starts from the beginning to ask the user
about what it is and what it's supposed to do."*

**The finding dissolves rather than being remedied**, because §4.3's derived placement was never
Karl's. D4 deleted the chooser; this document read that as *replace the operator's claimed rung
with a derived one* and titled §4.3 "placement from evidence alone". No Karl quote in `## BL-242:`
ever touched rung, ladder, placement or evidence — that entry's D5 now carries the correction and
the recipe that shows it. **This is the third inference recorded as Karl's ruling across this document and `## BL-242:`**,
after the `adopt_ask_audience` deletion (D9) and the *"Adoption assesses; it does not ask"*
headline; all three are prose written beside a ruling, read back as part of it.

What D10 removes: §4.3's placement mechanism and both operands of `# BF-ADOPT-FLOOR`; the
assessment record's `landedPhase`; Act 4's `current_phase` write — the design's only write to
phase-state outside Act 2 — and with it architect question 4 entirely; §5.1's "the assessment IS
the certification" claim; and the sharpest half of §12's calibration residual. What it keeps: all
four acts, the assessment, D6's rebuild verdict and D7's fitness finding, with the evidence
re-aimed at **pre-filling the Phase 0 intake** rather than shortening the ladder.

**2026-08-31, sixth pass — the architecture review's round 2, and four AUTHOR decisions.** Round 2
returned **B1 dissolved by execution**: a fixture adopted at `current_phase: 0` runs
`check-phase-gate.sh` to exit 0, blocks correctly at `--gate phase_0_to_1` on genuinely-undone
Phase 0 work, and — the strongest result either round produced — yields a **byte-identical demand
set** with `.adoption` stripped, so §2's indistinguishability now holds by execution rather than by
assertion. D10 worked.

It blocked on **B2**, which D10 did not touch and made *worse*: a second `adopt-project.sh` run
overwrites `phase-state.json` and the intake before the second-stamp refusal fires, and under D10
the clobbered `current_phase` is gate-earned. Plus three new gaps — no Act 3/4 interruption
analysis (with §7.2's receipt rule deadlocking re-entry), an undesigned post-Act-4 resume route
that skips the Phase 0 entry D10 promises, and a resting state whose gate refuses on a missing
`APPROVAL_LOG.md` before it parses anything.

Karl delegated all four — *"Fix the blocker and decide the 3 gaps now"* — and **§8.3a records the
answers as A1–A4, labelled A rather than D because a delegated decision is still the author's.**
Mislabelling them would repeat, with permission, the exact defect D9 and D10 exist to correct.

### §0.4 — Verification posture, and the branch topology caveat

Every claim marked *verified* was **executed on 2026-08-24**; §13 prints the commands and their
output, and **§13-U lists what was NOT executed and why** — read §13-U before trusting anything
here that it names.

**The branch topology caveat.** `## BL-242:` — the decision record this entire document designs
from — lives on the branch `docs/bl242-brownfield-filing` (commits `4719f00`, `9050a18`) and is
**not present** on `feat/messaging-standard`, the branch whose working tree every §13 code
measurement was taken from (`grep -c 'BL-242' "solo-orchestrator-backlog.md"` on that working tree
returns nothing — §13-V13). Consequences, stated rather than discovered: (i) BL-242 quotes in this
document were read via `git show docs/bl242-brownfield-filing:solo-orchestrator-backlog.md`, not
from the working tree; (ii) the v1 document on the BL-242 branch carries a v1.2.2 status-row
correction the measured branch's copy does not; (iii) the supervisor wiring this document in must
land it on, or after a merge with, the BL-242 branch — otherwise it cites a backlog entry the tree
cannot resolve, and `scripts/lint-backlog-references.sh` territory begins. This document takes no
position on merge order; it records the fork so nobody discovers it at review.

**One measurement disagrees with BL-242, and the disagreement is the lesson, not an error.**
BL-242 (2026-08-23) records the framework install set as **65 files** (36 `scripts/` + 24
`scripts/lib/` + 3 `scripts/host-drivers/` + 2 `scripts/hooks/`). Derived on `main` on 2026-08-24
that is still exactly right; derived on `feat/messaging-standard` it is **67** (38 top-level),
because that branch added `scripts/check-pr-review.sh` and `scripts/record-pr-review.sh` to the
shipped set (§13-V6 prints the diff). Re-derived on 2026-08-31 against the `main` this document
lands on, it is **68** (39 top-level). All three are correct *for their tree*, and the third was
found by an adversarial review rather than by this author re-running his own appendix. This is why §7.1
specifies the collision-prone set **by derivation** (`soif_parse_shipped_scripts`) and never by
count.

---

## §1 — Problem: what shipped, what announces itself, and why the shape changed

### §1.1 — What the v1 build shipped

The shipped inventory is `## BL-242:`'s hand-assembled-from-merge-inspection table (eleven merged
PRs: the design #318; WP0 #325 + fix #340; WP1 #329; WP2 #331; WP3 #335; WP4 #337; WP8 #343; WP5b
#344; WP6 #345; CI pinning #346), and that entry states why no one-liner reproduces it. This
document does not re-derive the PR set; it re-derived the **artifacts**: `scripts/scout.sh` plus
nine `scripts/lib/scout/*.sh`; `scripts/adopt-project.sh` plus seven `scripts/lib/adopt/*.sh`;
`scripts/lib/adoption-stamp.sh` in core; `scripts/lint-module-dependencies.sh`; the pages
`docs/adoption.md` and `docs/scout.md`; and eight test suites — the seven
`tests/test-brownfield-wp*.sh` files plus `tests/test-lint-module-dependencies.sh` (§13-V14 lists
them; their assertion tally is BL-242's measurement, **not re-run here** — §13-U).

### §1.2 — What is not built announces itself — derive the list, never maintain it

The authoritative unbuilt list is the set of `adopt_stub_*` functions the driver actually
**calls**. The recipe, extracted from `## BL-242:` and re-executed here verbatim (§13-V1):

```
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
for f in scripts/adopt-project.sh scripts/lib/adopt/*.sh; do
  case "$f" in *adopt-stubs.sh) continue;; esac        # the DEFINITIONS live there
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$f"   # comments are not calls
done | grep -ohE '\badopt_stub_[a-z_]+' | sort -u                # -> 7
```

Both exclusions are load-bearing (BL-242 measured 9 with neither, 8 with either alone):
`adopt_stub_test_debt_ledger` survives only as a comment in `scripts/lib/adopt/adopt-state.sh`,
and `scripts/lib/adopt/adopt-stubs.sh` holds the definitions plus the shared `adopt_stub_notice`
print helper, which is not a capability.

**Seven capabilities; five announce unconditionally, two only when they have something to
report.** The two conditional ones are visible in source (§13-V2): both
`adopt_stub_framework_script_collisions` and the found-something arm of
`adopt_stub_secrets_disposition` open with `[ "$n" -gt 0 ] || return 0`. Precisely: the collisions
stub is silent when no framework-script path collides; the secrets stub prints on
*not-`scanned`* status **or** a non-zero finding count, and is silent exactly when the scan ran
clean. On a clean adoptee **five** blocks appear, not seven — defensible behaviour, and a fact v2
inherits: *"the driver announces every gap"* is true only per-run, so the derivation above, not
the run transcript, is the inventory.

| Capability (verbatim from the notice) | v1 owner | v2 owner (§10) | Announces |
|---|---|---|---|
| the certification pass | WP5 | **dissolved into Act 3/4 — WP12** | always |
| the Adoption Record, the audit rows and the CI carve-out | WP7 | **WP7 (re-cut)** | always |
| the provenance headers on reconstructed documents | WP7 | **WP7 (re-cut)** | always |
| the commit-time scanners (the fallback pre-commit hook) | WP7 (its printed string is stale — see below) | **WP7 (re-cut)** | always |
| your project's framework documents | nobody | **WP11 + WP12 (D3)** | always |
| installing the framework's version of *N* colliding script(s) | nobody | **WP11 (D1)** | only when N > 0 |
| the secrets disposition | nobody | **WP10 (D2)** | only when the scan found something |

The stale string: `adopt_stub_hooks` prints `Owner: nobody yet — §10 names no owner` while
`docs/adoption.md` and `scripts/lib/adopt/adopt-stubs.sh`'s own header both record Karl's decision
that the hook is WP7's. `## BL-242:` already filed the correction; **WP9 carries it** as the first
package to touch that file.

### §1.3 — Why the shape changed: the driver asks what it should measure

The shipped driver's spine (`adopt_main` in `scripts/lib/adopt/adopt-state.sh`, read in full —
§13-V4): obtain the Scout report → present evidence → **`adopt_ask_scenario`** →
`adopt_decide_placement` (floor of scanned rung and **claimed** rung, `# BF-ADOPT-FLOOR`) →
**`adopt_ask_audience`** → reverse intake → stubs → test-debt census → collision archive →
install (skip-on-collision) → state writes (`# BF-ADOPT-STATE-ORDER`: `phase_state` → `intake` →
`manifest`) → record stub → stage and commit → hooks.

Three facts in that spine are what D4/D5 answer. **The scenario answer steers placement** — a
self-report from exactly the population Karl's D4 reasoning names as least equipped to give one.
**Everything model-shaped is a stub** — certification, document writing, any judgment about
fitness — because a shell process cannot hold an interview or weigh an architecture; v1 assigned
that work to shell WPs and the build honestly stubbed it instead. **And the driver never resolves
tools** (§13-V3: zero `resolve-tools` mentions across all eight driver files against seven in
`init.sh`), so the D2 secrets stop would today depend on whatever happens to be installed. The
four acts put each kind of work where it can actually be done: deterministic writes in shell,
judgment in a model session, with a safe parked state between them.

---

## §2 — Product boundary

**Brownfield adoption is:** a second, first-class entry path into the *same* framework — the same
phase gates, the same checks, the same tiers, the same audit trail — for a codebase that already
exists. It **assesses** the project instead of asking the operator to classify it, and it lands
every project at **phase 0** — not provisionally, and not pending a later promotion: that is
where an adopted project begins, and it advances only by passing the same gates as any other
project (D10).

**Brownfield adoption is not:**

- **Not a lighter framework.** After Act 4 completes, an adopted project is indistinguishable from
  a scaffolded one in what the gates demand of it. The durable difference is a record of how it
  got here — now including an assessment and a plan, not just a stamp.
- **Not a rebuilder.** D6: "rebuild" is a verdict with a pre-filled intake, exiting into the
  ordinary Phase 0 path. Adoption performs no rebuild.
- **Not a taste tribunal.** D7: no fitness finding exists except relative to requirements the
  operator stated in the interview. Stack-only opinions are a named defect, not a feature.
- **Not a code-quality remediation tool.** It measures debt and refuses to let the measured set
  grow; it does not pay the debt down.
- **Not a history rewriter.** Unchanged from v1: rotation instructions are printed, never
  executed.
- **Not "retrofit".** Unchanged from v1 (its C10): that word is taken by
  `scripts/reconfigure-project.sh --field`. This document says **adoption**, everywhere.

---

## §3 — Shape: the four acts (D5)

### §3.1 — The split is forced, not chosen

The evaluators, the requirements interview, and document authorship are **model-driven**; the
driver is **shell**. Karl's call is that adoption **waits** for the assessment (*"using AI, it's
only a few minutes"*) rather than deferring it — which means the framework must already be
installed when the model session starts, because `scripts/resume.sh`, the state files it reads,
and the evaluator machinery all live in the adoptee only after an install. So the shell half runs
first and must end in a state that is safe to abandon; the model half runs second and must find
everything it needs already on disk. Two processes, one parked state between them — that is the
whole argument, and it is a constraint, not a preference.

| Act | Name | Runs as | Writes |
|---|---|---|---|
| 1 | **SURVEY** | Scout — read-only shell, zero framework dependency | Nothing without `--out` (Scout's own contract); the driver consumes its JSON report |
| 2 | **PREPARE** | `scripts/adopt-project.sh` — deterministic shell | Tools, the archive, the framework install, minimal state at **phase 0**, one commit, hooks |
| 3 | **ASSESS** | Claude Code, entered via `scripts/resume.sh`'s adoption branch | The assessment record: interview answers, evaluator findings, the fitness verdict — **no rung** (D10) |
| 4 | **PROCEED** | Claude Code continuing Act 3's session | The documents (D3), the verdict artifact (D8), the Phase 0 intake pre-filled from Acts 1–3, the plan; then the ordinary Build Loop |

### §3.2 — Act 1 — SURVEY

Scout, unchanged. Its two properties — read-only, zero dependency — are the reason an operator can
look before deciding anything, and nothing in v2 touches them. The report's seven sections
(`stack`, `phaseMap`, `reality`, `secrets`, `collisions`, `testsBaseline`, `intakePrefill`) all
remain consumed. What changes downstream: `phaseMap`'s reached rung (`# SCOUT-LADDER-MAX`) stops being an operand
of any placement arithmetic — under D10 there is no placement to compute. It survives as
**context for the assessment and pre-fill for the Phase 0 intake**: knowing a project already has
a test corpus and a deploy lane shapes what the interview asks and what the plan proposes. It
never shortens the ladder (§4.3).

### §3.3 — Act 2 — PREPARE

Deterministic shell, ordered by facts already in the code rather than by preference. The full
order and each constraint's justification is §8.2; the summary:

1. **The tier question** (D9) — *"Who is this project for?"*, the one question Act 2 asks.
   Verbatim and first, before anything is installed or written, so an abandoned run leaves the
   host untouched too. It produces `ADOPT_DEPLOYMENT`, which step 3 reads and step 7's two state
   writers persist. Unanswered, it **refuses the run** — no default, no skip (§13-V16).
2. **Tool resolution** against the matrix — `scripts/resolve-tools.sh` with
   `templates/tool-matrix/`, the step adoption skips entirely today (§13-V3). It installs the
   required set, **including `gitleaks`**, which `templates/tool-matrix/common.json` already
   carries as `"required": true` (§13-V9) — D2's stop asks for nothing the framework does not
   already demand of every scaffolded project.
3. **The secrets check** (D2, §6) — **tier-scoped**, and the tier reaches three of the four
   cases. No adoption proceeds past this point with a scanner that was never there
   (`tool-unavailable`) unless a `personal` project records an acceptance; no *organizational*
   adoption proceeds with an undispositioned finding or a broken scan. A casual personal adoption
   warns loudly and carries on for **both** a findings result and a `scan-failed` one. §6.1's
   ladder is the authority; it keys on step 1's answer (§6.5).
4. **The test-debt census** — before the install, as the shipped code already orders it and for
   the reason its comment states: the census reads `git ls-files`, and independence from the
   index's timing is worth keeping explicit.
5. **The collision archive** — before any writer, now covering **four classes** (§7.3): AI-layer
   surfaces, git hooks, colliding `scripts/` (D1), colliding framework-named documents (D3).
6. **The framework install** — framework-wins on script collisions (D1), with the archive receipt
   checked first (§7.1).
7. **Minimal state, phase 0** — `phase_state` → `intake` (mechanical prefill only) →
   `manifest` with the v2 stamp (§8.3), the fail-safe order carried from v1 (§8.4).
8. **The adoption commit** — explicit staging, never `git add -A`, unchanged.
9. **Hooks last** — after the commit, as shipped (`adopt_install_hooks` runs after
   `adopt_stage_and_commit`, and the commit-msg block composes by `SOIF_TDD_OPEN` marker fence).

Act 2 ends by printing where the project stands (phase 0; assessment pending) and
the exact next command: run `bash scripts/resume.sh` in the adoptee and paste the prompt into
Claude Code.

### §3.4 — Act 3 — ASSESS

Claude Code, entered through the machinery that already exists for exactly this job:
`scripts/resume.sh` is the single state-aware first-message generator, currently four branches
(intake / `PROJECT_INTAKE.md` §13 verbatim / classic resume / `# DELTA-RESUME-PHASE4`), and today
containing **zero** mentions of adoption (§13-V8). WP12 adds the adoption branch: manifest says
`adopted: true` and the adoption block carries no completed assessment → emit the assessment
prompt (§8.5). In the session: the **requirements interview** (D7's five axes plus data
classification, §5.2) and **all evaluators** run against the installed tree. Act 3's output is a
written **assessment record** — machine-readable findings, the fitness verdict, and the
interview's answers — because Act 4's documents and plan must be derivable from it, not from
session vibes. **Under D10 the record carries no rung**, and nothing downstream reads one.

### §3.5 — Act 4 — PROCEED

The framework documents are written per D3 (§7.2); the verdict — including, possibly, *rebuild*
(§5.4) — is presented per D8 (§5.5); the **Phase 0 intake is filled in** from everything Acts 1–3
learned; and the project proceeds into the ordinary Build Loop **from phase 0**. Act 4 writes no
`current_phase`: under D10 there is nothing to place, and the project advances only by passing
`scripts/check-phase-gate.sh` like any other. Act 4 is deliberately thin — everything expensive
happened in Act 3, and it now has one less thing to do than the first draft of this section gave
it.

### §3.6 — The phase-0 landing is the load-bearing choice

`adopt_main` already prints the promise, and its `usage()` text repeats it: *"If you stop partway,
this project ends up more strictly gated than it started, never less."* v1 kept that promise by
write order within one process. **The four-act split threatens it** — an operator who runs Act 2
and never opens Act 3 has a fully installed, stamped, committed project with no human judgment
applied — **and the phase-0 landing is what keeps it**: that abandoned project sits at
**phase 0** with everything ahead of it. The phase gate is live (phase-state exists), the
commit-time checks are live from the next commit, and every phase boundary still lies between the
project and any claim of maturity. **A project cannot land high by abandonment — the scheme
cannot express that outcome**, rather than defending against it. This is strictly stronger than
v1, where an operator's `completed` answer landed the project at phase 4 in the same run that
asked the question.

**D10 makes this section nearly vacuous, and that is the point.** When it was written, phase 0 was
a *provisional* resting place and the argument had to establish that abandonment could not promote
past it. Under D10 nothing promotes past it at all — an adopted project starts at phase 0 and
advances only through the ordinary gates — so "cannot land high by abandonment" is true the way
"cannot land high" is true. The argument is kept rather than deleted because it is the reason the
four-act split was ever safe to propose, and a reader who meets the acts before the decision
should find it.

Two corollaries worth stating. First, **D6 becomes free**: a *rebuild* verdict is a verdict about
what to build, delivered alongside a Phase 0 intake the project was going to fill in anyway — no
placement is declined because none was ever offered (§5.4). Second, the "adoption did not
complete" analysis of v1 §5.5 carries over per act: a halt inside Act 2 leaves the v1-verified
partial-state rows (§8.4), and a halt between acts leaves the phase-0 landing, which is the safe
direction by construction.

### §3.7 — Module shape under the four acts

M1–M5 of `docs/module-contract.md` stand unchanged, and `scripts/lint-module-dependencies.sh`
keeps enforcing the direction rule with its five-glob CORE set (`# BL-215-CORE-GLOB-SYNC`). Two
points of contact the acts create, both resolved without spending severability:

- **`scripts/resume.sh` is core and shipped; the adoption branch must not source module code.**
  It does not need to: the branch predicate reads **state** — `.adoption` in
  `.claude/manifest.json` via `jq` — the same way the shipped `# DELTA-RESUME-PHASE4` branch reads
  phase-state. Reading a state file the module wrote is not a `core → module` edge; sourcing
  `scripts/lib/adopt/` from `resume.sh` would be, and is forbidden.
- **The assessment brief must exist in the adoptee** for `resume.sh` to point at, since
  `docs/adoption.md` is deliberately not shipped downstream. Act 2's driver **writes** the brief
  into the adoptee (author-proposed home: `.claude/adoption/assessment-brief.md`, §8.5) — a
  module-owned writer producing project state, which is the pattern every other adoption artifact
  already follows.

---

## §4 — Assessment replaces the chooser (D4) — *this section overturns v1 §4*

### §4.1 — What is overturned, and Karl's reasoning verbatim

v1 §4 — "The two scenarios (D2)" — made one question, asked verbatim in Karl's wording, the axis
of the whole flow, and v1 §0.1 carried it as settled. **It is overturned, deleted rather than
demoted**: adoption no longer asks completed-versus-in-flight, and it does not ask whether an SDLC
framework was used either (a second chooser drafted in conversation and dropped with the first).
Karl, 2026-08-23, recorded in `## BL-242:` and load-bearing enough to belong here verbatim:

> **"I think trusting an end user to know what's needed is a mistake considering they are using
> the orchestrator BECAUSE they are not already following a proper SDLC."**

That is a **selection-effect argument, stronger than the mechanical one**. The mechanical
objection — a self-reported answer reduces scrutiny while being unverifiable — already inverts the
floor rule the shipped driver enforces one question earlier (*evidence you have not produced is
not evidence*, `adopt_decide_placement`). The selection argument goes further: the population
being asked is, **by definition**, the population least equipped to answer. Scout can detect the
framework's own artifacts without asking anyone; everything else is a claim.

### §4.2 — The deletion's blast radius, enumerated

A deletion with a footprint, not a string edit. Verified against the tree (§13-V7):

| Surface | What goes |
|---|---|
| `scripts/lib/adopt/adopt-chooser.sh` | `ADOPT_CHOOSER_QUESTION` (`# BF-ADOPT-CHOOSER-QUESTION`, with its do-not-reflow guard comment), both canned answers, `adopt_ask_scenario`, and the `claimed` operand plumbing (`adopt_ask_ladder`). **`adopt_ask_audience` is NOT deleted (D9) and was never in this file** — `## BL-242:`'s blast radius filed it here beside `adopt_ask_scenario`; it lives in `adopt-state.sh` |
| `scripts/lib/adopt/adopt-state.sh` | `adopt_main`'s `adopt_ask_scenario` call. **`adopt_ask_audience`, `ADOPT_AUDIENCE_Q` and both answers STAY (D9)** — the call moves to the head of Act 2's order (§8.2 step 1) and its output stops feeding placement; `adopt_decide_placement` loses its claimed operand and, with it, its purpose in Act 2 (§4.3); `$ADOPT_SCENARIO` threading into the stubs and the final summary |
| `scripts/lib/adoption-stamp.sh` (core) | `soif_adoption_stamp`'s `<scenario>` parameter and its enum refusal — the stamp's v2 shape is §8.3. An in-core change, i.e. WP9 touches a WP3 deliverable and inherits its dual-direction proof obligations |
| `docs/adoption.md` | The chooser section ("The one question", the verbatim block, S1/S2 landing prose) — WP12's page revision |
| `tests/test-brownfield-wp4-driver.sh` | `CHOOSER_LITERAL` pins the question's **presence**; v2 re-aims it to pin **absence** (§10-WP9's mutation) |

**One row of this table was wrong for eight days, and D9 is the correction.** `## BL-242:`'s D4
blast radius named `adopt_ask_audience` among the deletions and this table inherited it. Karl's
ruling reaches two questions — the scenario chooser and the proposed *"was this built with an SDLC
framework?"* — and the audience question is neither: it asks *"Who is this project for?"*, which
is not a self-report about process maturity but a fact **no evidence can determine**. The headline
*"Adoption assesses; it does not ask"* is the entry's, not Karl's, and D7 requires asking. **The
lesson is general and belongs in this section rather than in a footnote: a blast-radius
enumeration is the author's inference about consequences, and every name in one is a claim that
some decision reaches that far.** Check the names against the ruling's words, not against the
list's confidence — this table is exactly such a list.

The verbatim question exists at exactly **three** places in the code-and-shipped-docs surface
today — the chooser lib, the docs page, the WP4 suite (§13-V7; the two design documents also
carry it, v1 as the decision it settled and this one twice, in V7's printed command and in §6.5's
D9 argument) —
which bounds the deletion's search space and gives WP9 its completion check: after WP9, V7's
grep returns nothing.

### §4.3 — What replaces it: nothing. The project starts from the beginning (D10)

**This section said the opposite until 2026-08-31, and the correction is the most consequential
in this document.** It was titled *"placement from evidence alone"* and specified that Act 4
derived a landing rung from the assessment record. **Karl never asked for that.** D4 deleted the
chooser because the operator cannot be trusted to know how far along a project is; this document
read that as *compute the answer another way* and built a replacement mechanism. Deleting a
question whose answer cannot be trusted does not imply the answer must be computed — it can
equally mean the question does not need answering, and D10 says it does not:

> *"The project gets ingested and starts from the beginning to ask the user about what it is and
> what it's supposed to do."* — Karl, 2026-08-31

**So: `adopt_apply_floor` (`# BF-ADOPT-FLOOR`) computes `min(scanned, claimed)`, and BOTH operands
go.** `claimed` goes with the chooser (D4); `scanned` goes with D10. Act 2 computes no placement,
Act 4 computes no placement, and **`current_phase` is `0` for every adopted project** until the
ordinary gates move it. There is no landing rung, no placement formula, and no assessment-record
field holding one.

**What the evidence is FOR, since it is not for placement.** Scout's artifact ladder, the
test-debt census, the reality probes and the assessment's own findings all survive and all matter
— as **pre-fill for the Phase 0 intake and context for the plan**. A project that already has a
test corpus, a deploy lane and architecture documentation gets an intake that says so and a plan
that starts from there. What it does not get is a shortcut past a gate. This is D6's shape —
*"the verdict EXITS into machinery that already exists, with the intake pre-filled from everything
the assessment just learned"* — generalised from the rebuild verdict to every adoption.

**Why this is the right answer and not merely the ordered one.** The gate script is cumulative by
its own contract (`scripts/check-phase-gate.sh`: *"Each gate crossing implies all prior gates have
been crossed"*), and its adoption arm reads the stamp for integrity only, adding *"no logic to any
existing predicate"*. A project placed at phase 3 without per-boundary evidence is therefore
**illegible to the gates it must live under** — an adversarial design review demonstrated exactly
that against the superseded §4.3, blocking on it. D10 dissolves the finding rather than remedying
it: with no placement, there is no illegible rung. The cheapest defect is the one the design stops
creating.

**Rejected alternative — infer the scenario and ask for confirmation.** v1 §4.2 already rejected
this for the chooser (a guess presented as a default makes the most consequential answer the
easiest to skim past), and D4 removes the question the guess would have fed. Under D10 it is
rejected twice over: there is no rung for the operator to confirm.

**Rejected alternative — derive the rung from evidence and place the project there.** This
document's own superseded §4.3, above. Rejected by D10.

---

## §5 — The assessment informs; the gates certify (D6, D7, D8, D10)

### §5.1 — WP5 dissolves, and what it dissolves into

v1-WP5's job was to certify every gate **below a claimed rung** — the heavier the claim, the
heavier the pass, with S1 the worst case (all four boundaries). Under D4 there is no claimed rung
to certify against, and **under D10 there is no landed rung to certify FOR**: the project starts
at phase 0 and crosses every boundary the ordinary way, later, exactly like any other project.
**So the certification pass has no object in either direction, and `scripts/check-phase-gate.sh`
does the certifying — as it always did.**

*(This section previously read "the assessment IS the certification", crediting each rung "because
Act 3 produced today's evidence for it". That followed from the superseded §4.3 and does not
survive D10: the assessment produces findings, requirements and a verdict, none of which is a gate
approval. An adversarial review's blocking finding was aimed squarely here — that a rung credited
by assessment is illegible to a cumulative gate — and D10 removes the credited rung rather than
arguing with the gate.)*

What survives of v1 §5 and where it lands:

| v1 §5 element | v2 disposition |
|---|---|
| The three kinds (a/b/c) of certification | The *taxonomy* survives as the assessment record's honesty labels: fresh scans and produced docs are unmarked (kind a); reviews held now are real, with only the ordering fact marked (kind b); inherently historical facts keep `adopted-at` markers with forward equivalents (kind c). What is gone is the *pass* that iterated gates below a claim |
| The test-debt ledger and ratchet (v1 §5.4) | **Shipped** (WP5b, `scripts/lib/adopt/adopt-test-debt.sh`); unchanged; remains kind (c)'s forward equivalent |
| Certification can fail (v1 §5.5) | Restated per act: Act 2 fails on the secrets check (§6) and on any refused write; Act 3/4 cannot "fail" by placing low — there is no placing (D10) — they surface findings and verdicts — including rebuild — because with no claim there is nothing to flunk, only evidence there is less of. Blocker-grade findings surface in the plan and, where they are secrets, in §6's stop |
| Severity vocabulary (SEV-1..4, reused not invented) | Carried — the assessment record and the plan use it |

**Retire WP5; do not re-cut it into a smaller version of itself.** A residual certification pass
beside the assessment would be two mechanisms answering one question, which is this repo's
recorded defect pattern (`## BL-235:`'s two timeout helpers disagreeing in both directions that
matter).

### §5.2 — The requirements interview (D7's five axes, plus the one that was always non-skippable)

Held in Act 3 by the model, recorded in the assessment record. Karl's five, verbatim from
`## BL-242:`: **how many people use it; whether it needs high availability; whether it is
internet-facing; what scalability it needs; how sensitive the data is.** The fifth is the shipped
seven-value data-classification taxonomy, and it keeps v1's non-skippable status with a
mechanically different anchor: at phase 0 the ZDR backstop (which fires at `current_phase >= 2`)
is not yet in reach, so **Act 4's Phase 0 intake write refuses to run without a recorded
classification**, and the shipped backstop remains the second line from the moment the project
reaches phase 2 by the ordinary route. *(This anchored on "Act 4's placement write" until D10
removed that write. The intake write is the better anchor and was available all along: every
adoption produces an intake, whereas the placement write only ever existed in the superseded
§4.3.)* The
interview also absorbs what `## BL-228:` records the reverse intake never asks — the system
architecture, and a stack description that is not a single-select scalar — because D7's verdict is
unreachable without both.

**Author-proposed beyond Karl's five:** operational reality for mature projects (who runs it, what
breaks, backup maintainer, hosting) — v1 §4.3's S1 interview content, now asked when the
*evidence* shows maturity instead of when the operator claims it.

### §5.3 — "Wrong technology" is a finding only relative to stated requirements (D7)

The verdict record must carry, for every fitness finding, **the requirement it is relative to** —
a finding with no requirement pointer is invalid by construction, and the check that renders the
verdict artifact refuses it. The guarded failure mode is specific and worth restating: an
evaluator with good taste reads the STACK section and says "rebuild this in Python" without
reading the REQUIREMENTS. *HTML over a spreadsheet, for three people in one office, once a month,
is genuinely fine.* A verdict not derived from the interview is an opinion wearing a certification
stamp — and under D8 the reasoning is presented, so an undressed opinion is also *visible*.

### §5.4 — The rebuild verdict exits into Phase 0 (D6)

"Rebuild" is a **verdict adoption returns, not work adoption does.** A rebuild consists of a Phase
0 intake, an architecture phase, a Build Loop and gates — Solo Orchestrator's ordinary path — so
the verdict exits into machinery that already exists, with the intake pre-filled from everything
the assessment learned. Mechanically, §3.6 makes this **free**: the project is **already at
phase 0** and was never going anywhere else; Act 4 records the verdict in the assessment record and the
Adoption Record, pre-fills `PROJECT_INTAKE.md` from the assessment (the `# BL-204-PREFILL-READ`
pattern — prefill facts, confirm, never prefill judgments), and hands the operator the ordinary
intake path. The adopted-project state — stamp, archive, ledger, hooks — all remains valid: the
rebuild is a *plan for what to build next*, not an un-adoption. It is a **verdict delivered
alongside an intake the project was going to fill in anyway** (D10), not a placement withheld —
and that is the difference between a bounded feature and an unbounded one: "rebuild" adds almost
nothing to what must be built.

### §5.5 — The presentation contract (D8) — binding, and already written down

Every Act 4 output a human decides on — every fitness finding, the plan, above all a rebuild
recommendation — is presented as **the full technical account AND the plain-English half**, per
`docs/messaging-standard.md`: Part 1's five parts (what happened; what it means for you; options
with pros and cons; a recommendation **with the reasoning**; what happens if you do nothing) and
Part 2's controlled vocabulary (`gate` for phase boundaries and nothing else; everything else a
`check`; `block`/`warn`/`refuse` by their fixed meanings). That standard's Part 5 already names
this exact surface — *"a rebuild is the most expensive thing software can recommend; one delivered
as an unexplained conclusion is indistinguishable from a refusal"* — so v2 adds no second
standard; it **binds** the existing one: the verdict artifact carries both halves structurally
(§10-WP12 pins the scaffold with a check), and a verdict whose plain half is missing or whose
recommendation carries no reasoning does not render. The reasoning IS the deliverable.

One vocabulary note this document practices as well as preaches: the shipped driver prints *"the
framework's two message gates are live"* — under the standard those are **checks** (they are not
phase boundaries). Quoted strings stay verbatim; new prose, including every string WP9 touches,
uses the controlled vocabulary.

---

## §6 — Secrets: an organizational adoption stops, a casual personal one warns loudly (D2)

### §6.1 — Four status-and-findings cases, and the tier reaches three of them

`scripts/lib/scout/scout-secrets.sh` emits exactly three statuses, and its own comment states the
taxonomy this design builds on (§13-V5): *"`scanned` with zero findings is a positive result.
`tool-unavailable` is 'nobody looked'. `scan-failed` is 'we looked and something went wrong'."*

| Status | Meaning | `deployment = organizational` | `deployment = personal` |
|---|---|---|---|
| `scanned`, findings = 0 | gitleaks ran, report parsed, clean | Proceed | Proceed |
| `scanned`, findings > 0 | Real findings, redacted per v1 §6.2's field allowlist | **STOP until every finding carries a recorded disposition** (§6.3) | **WARN LOUDLY and carry on** — every finding printed redacted and recorded in the Adoption Record; no disposition demanded, and no silence either |
| `tool-unavailable` | gitleaks not on the host | **STOP — hard refusal.** No flag, no attestation, no escape (§6.4). After WP10, reachable only if tool resolution itself failed | **STOP, escapable.** Proceeds only on a recorded acceptance — named person, reason, date, §6.3's shape, refused if unrecordable (§6.4) |
| `scan-failed` | gitleaks exited non-zero, or its report did not parse | **STOP; fix and re-run. No escape** — a successful scan is a hard requirement here (Karl: *"it cannot continue as it's required"*). "Could not measure" is never "nothing to measure" — the fail-open posture `docs/messaging-standard.md` Part 2 names a defect wherever it appears | **WARN LOUDLY and carry on** — treated *as if the scan had run* (Karl, 2026-08-31). No recorded acceptance demanded; the warning must say plainly that **nothing is known** about this history, because there is no findings list to print |

**The tier governs every row but the clean one**, and the ladder it describes is a **severity**
ladder rather than a status ladder. On `organizational` a successful scan is a hard requirement:
findings must be dispositioned, and neither `tool-unavailable` nor `scan-failed` has any escape at
all. On `personal` the requirement softens by how far the framework's own setup fell short:

| What happened | `personal` outcome |
|---|---|
| The scan ran and found things | Warn loudly, carry on — the findings are known and printed |
| The scan ran and broke (`scan-failed`) | Warn loudly, carry on — **treated as if it ran** (Karl, 2026-08-31) |
| The scanner was never there (`tool-unavailable`) | Stop; carry on **only** on a recorded acceptance |

**The one deliberate step in that ladder is worth naming, because it is not obvious.** A
`scan-failed` personal project and a `tool-unavailable` personal project end in the same
epistemic state — nobody knows what is in the history — yet the first proceeds on a warning and
the second needs a signature. The distinction Karl's ruling draws is **not epistemic; it is
whether the required tool was present and attempted** — gitleaks ran and stumbled, versus gitleaks
was never installed. Act 2's tool resolution (§6.2) is what makes the second case a failure of the
framework's own setup rather than an environment hiccup, and that is what earns it the higher bar.
**This design records the step rather than smoothing it**; if it proves wrong in practice the fix
is one cell of the table above.

*(Two earlier drafts of this paragraph were wrong in the same direction. The first said the tier
"governs one row of that table and no other" and that the bottom two rows were "byte-identical
across the tiers"; the second, written after the `tool-unavailable` ruling, said the tier reached
"two of them" and that `scan-failed`'s cells were "still identical". Both generalised an argument
about `scanned`-with-findings — "the tier is about loudness on a known finding" — into a claim
about rows it had never been tested against. The tier reaches three.)*

Karl's words, in the order he gave them, because the order is the correction. **First pass,
2026-08-23:** *"Stop adoption until acknowledged with a reply of having been corrected or the risk
is being accepted"*, and on the not-scanned case *"Why wouldn't the secrets scan run? That should
never be an option."* **Refinement, 2026-08-25**, answering the tier-scope sub-question review
raised against that first pass: *"Keep warn loudly for casual personal projects. Organizational
projects are always a stop."* The table above records the **refinement**. An earlier draft of this
document recorded only the first pass — "every tier stops" — and that is corrected here rather
than quietly: the first pass is not wrong, it is superseded, and a design that transcribes the
superseded half of a two-pass ruling is exactly the drift `## BL-242:` was filed to end.

**WHICH SETTING THE TIERING READS IS A DERIVATION, NOT A SECOND RULING — AND IT OVERTURNS v1 §6.3
AS WRITTEN.** `## BL-242:` settled this on 2026-08-25 and this section transcribes it rather than
re-deciding it. The fork it adjudicates: v1 §6.3 reads *"BLOCK at strict; BIG WARNING at
personal"* — one value taken from each of two **different** settings.

- `enforcement_level` is `no | light | strict` (`scripts/lib/enforcement-level.sh`,
  `read_enforcement_level`)
- `deployment` is `personal | organizational` (same file, `assert_choosable`)

**They are not independent, and treating them as one axis is what produced the ambiguity.**
`init.sh`'s `# BL-030` block forces `strict` whenever deployment is organizational — a supplied
`--enforcement-level` is ignored with a warning — so **organizational ⇒ strict**, one way only.
And `# BL-180-ENFORCEMENT-DEFAULT` resolves an unset level for every path with
`[ -z "$ENFORCEMENT_LEVEL" ] && ENFORCEMENT_LEVEL="strict"`, so **the ordinary personal project is
`personal` + `strict`** — the default one, not a corner case. For that project *both* of v1 §6.3's
arms match, and they say opposite things. Karl's ruling puts it in the **warning** arm.

So the ruling contradicts v1 §6.3's literal BLOCK-at-strict for the commonest project there is.
The only reading that rescues "confirms" is that v1 §6.3's `strict` was loose shorthand for
`organizational` — plausible, since `# BL-030` forces one from the other, but the default personal
project is a counterexample the shorthand cannot absorb. **`strict` in v1 §6.3 is wrong rather
than ambiguous, and the axis is `deployment`.**

**`enforcement_level` carries no residue under the ruling**, which is what makes this a derivation
rather than a coin-toss between two defensible readings: a personal project wanting less
enforcement sets `light` or `no` and still warns; one wanting a stop sets
`deployment = organizational`. No combination is left over. **Operationally, deriving it changed
nothing** — organizational stops, casual personal warns loudly, exactly as ruled. What it changed
is the amendment record: D1, D2 and D3 all contradict settled v1 text, so **that count is THREE,
not two.**

**Read that count over the right set.** It is `## BL-242:`'s, and it counts **how many of D1–D3
contradict settled v1 text** — the three decisions that were about the unowned capabilities. It is
**not** a count of v1 decisions that change, which is a different and larger set: §0.2's
disposition table shows **four** of v1's six changing (v1-D2 overturned by D4, v1-D3 re-derived,
v1-D4 re-keyed here, v1-D5 partially reversed by D1 and D3). Both numbers are right about their
own set, and a reader who conflates them will think one of them is wrong.

**The tier ladder still governs everything else it governs.** What it buys inside §6 is loudness
on a known finding and nothing more: it never buys a way past an unrun scanner (§6.4), and it
never weakens the redaction projection — no artifact in this section carries a secret's value, at
either tier, on either arm.

### §6.2 — Tool resolution makes the scanner guaranteed

Act 2's **second** step runs `scripts/resolve-tools.sh` against `templates/tool-matrix/` (§8.2; the
tier question is step 1 under D9) — the step the
shipped driver never takes (§13-V3). `gitleaks` is already a `"required": true` entry in
`templates/tool-matrix/common.json` (category `secret_detection`, `min_version` 8.18.0, install
recipes for brew/apt/dnf/pacman — §13-V9), so **D2 demands nothing the framework does not already
demand of every scaffolded project**; adoption was simply not asking. Ordering consequence: the
Scout report Act 2 consumes may predate the install and carry `tool-unavailable` — so **when the
consumed report's `secrets.status` is not `scanned`, Act 2 re-runs the secrets scan after tool
resolution** rather than trusting a stale "nobody looked". A fresh `scanned` result replaces the
report's secrets section, and the persisted copy at `.claude/adoption/scout-report.json` (already
written and SHA-recorded by the shipped state writer) reflects what was actually acted on.

### §6.3 — The acknowledgement is recorded, and refused if it cannot be recorded

Carried from v1 §6.3, hardened per D2. Per finding, keyed by the redacted fingerprint: **rotated**
(date, who) / **false alarm** (a reason; the rule id alone is not a reason) / **accepted risk**
(named accepting person, reason, date). The record is BL-072's shape — the same the framework uses
for every attested escape, and the same `## BL-233:` reused for `SOLO_MCP_ACCUM_ATTESTED`: **an
escape that leaves no trace is the advisory posture this decision exists to replace**, so a
disposition that cannot be written (disk, permissions, a missing ledger) is a refusal, not a
warning. Author-proposed mechanics: dispositions live in `.claude/adoption/secrets-dispositions.json`
(committed, joined to the redacted findings by fingerprint), each `accepted risk` additionally
writes an `adoption_event` audit row through `bypass_audit_append` — the contract writer, for the
validation and locking reasons the driver's own header already records — and the Adoption Record
(§8.6) lists the dispositions. v1 §6.2's field-allowlist redaction projection applies to every one
of these artifacts unchanged; nothing in this section ever contains a secret's value.

### §6.4 — `tool-unavailable`: stops at both tiers, escapable only on personal (D2, ruled 2026-08-31)

**SETTLED. Karl, 2026-08-31: "Yes on personal, no on organizational."**

`tool-unavailable` **stops adoption at both tiers** — that half was never in question, and
`## BL-242:` puts it in as many words: *"a scanner that was never there is not an acceptable state
either way."* What the ruling settles is whether the stop can be **acknowledged past**:

- **`deployment = organizational` — hard refusal.** No flag, no attestation, no escape. The remedy
  is the one Act 2 already performs: install the tool and scan.
- **`deployment = personal` — stop, escapable on the record.** The operator sees what could not be
  measured and may proceed on a recorded acceptance: named accepting person, reason, date —
  §6.3's shape exactly, and **refused if it cannot be recorded.**

**The argument for the organizational arm is worth carrying**, because it is the one that decides
the harder half: *"corrected or accepted"* is coherent for a **known** finding, and here the
operator would be accepting the risk of credentials **nobody looked for**. You cannot accept what
was never measured. On a personal project Karl's ruling puts that judgement in the operator's
hands, on the record; on an organizational one it does not exist.

**THIS DOCUMENT AND `## BL-242:` BOTH POSED THE QUESTION IN THE WRONG SHAPE, AND THAT IS THE
LESSON.** Both framed it as a global binary — hard refusal *everywhere*, or the escape
*everywhere* — and this author recommended the first. **Neither arm was the answer.** D2's whole
structure is one rule with two tiers, so a tiered answer was the obvious third reading, and it was
missed because the reasoning got generalised past its evidence: *"the tier is about loudness on a
known finding"* was a sound argument about `scanned`-with-findings and was carried, unexamined,
into a claim about every row of §6.1's table. Karl's ruling is that third reading, and his point
that his 2026-08-25 ruling already implied it is correct — *"Organizational projects are always a
stop"* describes how organizational adoptions END, not which status triggered the ending.

**A second failure in the same section is kept because it is a different class.** An earlier draft
closed this question by attributing to `## BL-242:` a sentence — *"It stays a hard refusal."* —
which `## BL-242:` no longer contains: written in `8ace9a2`, removed in `4b30053`, the review
round that corrected that same item from *moot* to *STILL OPEN*. It cited a **superseded revision
of its own decision record** as authority. The command that catches the class:

```
git log --all --oneline -S 'It stays a hard refusal' -- solo-orchestrator-backlog.md
```

Two commits on a merged-away branch, nothing on `main`. **The two failures are worth
distinguishing:** that one invented an authority, this one accepted a false dichotomy. Only the
first is caught by any command.

**`scan-failed` RULED 2026-08-31 — AND NOT AS THIS AUTHOR RECOMMENDED.** The question was whether
`scan-failed` takes `tool-unavailable`'s split. Karl: *"So action as if it ran. Personal project,
it can continue with large warning. Organizational, it cannot continue as it's required."* So
`scan-failed` behaves like **`scanned`-with-findings**, not like `tool-unavailable`: personal warns
loudly and carries on with no recorded acceptance; organizational stops with **no escape at all**,
because a successful scan is a requirement there and the remedy is to make it succeed.

**This author recommended the other extension** — giving `scan-failed` `tool-unavailable`'s
stop-with-recorded-escape on personal — arguing that the milder problem should not be stricter
than the graver one. **The ruling fixes that asymmetry in the opposite direction**, by loosening
`scan-failed` rather than tightening it, and it is the better fix: it needs no new mechanism, and
"the tool ran and stumbled" genuinely is closer to a scan that happened than to a scanner that was
never installed. Recorded because a recommendation that was not taken is part of this document's
record, and because the principle behind the ruling — severity of **what the framework failed to
provide**, not severity of **what the operator ends up knowing** — is what predicts the next case.

**One consequence the implementer must not smooth over.** A `scan-failed` warning has **no
findings to print** — the report never parsed. The warning must therefore say that nothing is
known about this history, in those terms, rather than reusing the findings-warning template with
an empty list. An empty findings list rendered as a warning reads like a clean result, which is
the fail-open posture this entire section exists to refuse.

### §6.5 — Where the tier value comes from: the audience question, kept and re-purposed (D9)

**SETTLED — Karl, 2026-08-31.** §6.1's table keys on `deployment`, and `deployment` comes from the
audience question the shipped driver already asks. This section was written as an open question,
because `## BL-242:`'s D4 blast radius said that question was being deleted; **it is not** (§4.2),
and the options below are kept as the record of what was weighed rather than deleted as spent.

The untiered first pass read no setting at all, so §6 had no dependency on the tier; the
2026-08-25 refinement gives it one. Three derived facts (§13-V15) frame it:

1. **`ADOPT_DEPLOYMENT` has exactly ONE writer in the shipped driver — `adopt_ask_audience`** —
   and two readers, `adopt_write_phase_state` and `adopt_write_manifest`.
2. **`## BL-242:`'s D4 blast-radius line said `adopt_ask_audience` goes**, and §4.2's table and
   §10-WP9's scope inherited it. **That line over-reaches** (established below, and filed against
   `## BL-242:` D4) — **D9 keeps the question**, so the producer stays.
3. **The manifest that would otherwise hold the tier is written at Act 2 step 7**
   (`# BF-ADOPT-STATE-ORDER`: `phase_state intake manifest`), while the secrets check is step 3
   (§8.2) — before any write, deliberately, so a stopped adoption has changed nothing. **So the
   tier can never be read from the manifest in Act 2**, whatever produces it; it must come from a
   variable held in the run. `ADOPT_DEPLOYMENT` is that variable, and both state writers already
   consume it — the value is asked once and used three times.

Under the blast-radius line the tier had no producer at all; and even with one, the file that
stores it does not exist when §6 needs to read it. **D9 settles the first half and fact 3 settles
the second**: the question is asked at the head of Act 2 (§8.2 step 1), long before either the
secrets check or the manifest write.

**THAT LINE IS AN ENUMERATION, NOT A RULING, AND THE DISTINCTION DECIDES THIS SECTION.** Karl's
recorded reasoning for D4 is one sentence — *"I think trusting an end user to know **what's
needed** is a mistake considering they are using the orchestrator BECAUSE they are not already
following a proper SDLC"* — and it is about **self-reported process maturity**. Three checks say
it does not reach the audience question:

- **What the two questions actually ask.** The chooser asks *"Is the project built out and needs
  to be able to be supported… or are you still in the process of building your project?"*
  (`# BF-ADOPT-CHOOSER-QUESTION`). The audience question asks *"Who is this project for?"* —
  *"Just me, or me and a few people I know"* / *"A company, a client, or people who are paying for
  it"*. The first is a claim about maturity that evidence can contradict; the second is a fact the
  operator knows for certain and that **no amount of code inspection can determine**. The
  selection-effect argument is precisely what fails to apply to it.
- **D4's own text names the dropped set and the audience question is not in it** — the scenario
  chooser, and the proposed *"was this built with Solo Orchestrator or another SDLC framework?"*.
  *"Both are dropped"* is a count of two.
- **"Adoption assesses; it does not ask" is `## BL-242:`'s headline, not Karl's words.** The entry
  marks his quote separately, as *"Karl's reasoning, which is the load-bearing part and belongs
  verbatim"*. It cannot be a general principle in any case: **D7 — also Karl's — requires asking**
  (*"It should be part of the interview to decide that and present the reasoning to the user"*,
  over five axes), so a blanket "does not ask" would contradict the next decision in the same
  list.

`adopt_ask_audience` appears in `## BL-242:` in the blast-radius line and in the correction filed
against it — **in no Karl quote anywhere**, which is the actual claim; the grep is only how you
find that out quickly.

**A second consequence falls out of the same deletion and has nothing to do with secrets.** With
`ADOPT_DEPLOYMENT` left at its initialised `""`, both writers emit an empty `deployment`, and
`assert_choosable` fail-closes with *"has no 'deployment' key"* (`# BL-221-TIER-FAIL-CLOSED`).
`# BL-221-ADOPT-TIER-KEYS` shipped **specifically** so an adopted manifest would carry that key;
deleting `adopt_ask_audience` removes it again **six days** after `## BL-221:` closed (PR #356
merged 2026-08-17; D4 decided 2026-08-23 — `git log --merges --format='%h %cs %s' | grep 356`).
**That hole is in this design with or without the secrets tiering** — the tiering makes it
visible, it does not cause it.

The options, with the author's recommendation stated and the decision left to Karl:

| # | Option | For | Against |
|---|---|---|---|
| **(a)** | **The audience question survives D4 as a TIER question, not a scenario question.** `ADOPT_AUDIENCE_Q` stays and keeps writing `ADOPT_DEPLOYMENT`; `ADOPT_CHOOSER_QUESTION` still goes | D4's reasoning is a **selection-effect** argument about SDLC maturity — the operator cannot reliably self-report how far along a project is. It does not reach *"is this for a company or for me"*, which the operator knows for certain and which **no evidence can determine**. Closes the `# BL-221-ADOPT-TIER-KEYS` hole in the same edit | **Nothing in Karl's ruling** — which is the finding above, not a concession. What it costs is one correction: `## BL-242:`'s D4 blast-radius line, and the three places here that inherit it (§0.2's v1-D2 row, §4.2's table, §10-WP9's scope). A reader who remembers the headline *"adoption assesses; it does not ask"* needs telling that it is the entry's phrasing, not Karl's |
| **(b)** | **Fail closed to `organizational` whenever the tier is unknown** | Matches `# BL-221-TIER-FAIL-CLOSED`'s direction and the framework's stated failure direction. Asks nothing | Makes the **warn arm unreachable in Act 2** — every adoption stops on findings, so the 2026-08-25 refinement has no effect on the one surface it was made for. That is not a conservative reading of the ruling, it is a silent nullification of it |
| **(c)** | **Move the secrets check into Act 3, after the interview establishes the tier** | The tier is a requirements fact, and D7's interview already asks its neighbours — users, exposure, data sensitivity | Contradicts §8.2's constraint that the check precedes **any** write: Act 2 would install 65+ files and commit before the secrets question is answered. "Stop before any write" is the whole reason a stopped adoption is safe |
| **(d)** | **Read `deployment` from the adoptee's existing `.claude/manifest.json` when present, else (a) or (b)** | Free and correct for a re-adoption, or a project already carrying a manifest | Answers nothing for the ordinary case — a brownfield project has no `.claude/manifest.json`, which is precisely why adoption writes one |

**RULED: (a). Karl, 2026-08-31 — "keep the audience question as a tier question."** Recorded as
**D9** in §0.1. It preserves the refinement's effect where (b) nullifies it, keeps the
stop-before-any-write constraint (c) breaks, and closes the `# BL-221-ADOPT-TIER-KEYS` hole the
blast-radius line opened regardless of what §6 did.

**(b) IS NOT ADOPTED AS A FALLBACK, AND THE AUTHOR'S RECOMMENDATION OF ONE IS WITHDRAWN AS
UNNECESSARY.** That recommendation read *"fail closed to `organizational` when it cannot be asked
(a non-interactive run)"* — and it assumed a non-interactive path **that does not exist**
(§13-V16). The driver's whole flag set is `--root`, `--scan-report`, `--re-add`, `--version`,
`-h/--help`, and `adopt_ask_choice` **refuses the run** on an unanswered mandatory question
(`ADOPT_MANDATORY_REFUSAL` — *"This question has no default and no skip, and no answer was
given:"*). A refusal is **stricter** than a fail-closed default, so adding (b) would have
*weakened* shipped behaviour to serve a case that cannot arise. Recorded rather than deleted
because inventing a mechanism for an unreachable path is the cheaper half of this document's
recurring failure mode; the expensive half was inventing a ruling for one.

**And the cost this paragraph first claimed never existed.** An earlier version said (a) makes
*"D4's 'does not ask' gain one explicit exception"* — there is no such ruling to except, and
writing one into a design would have manufactured a decision Karl never made while purporting to
transcribe him. What (a) actually cost was **one correction propagated to four places**:
`## BL-242:`'s D4 blast-radius line (filed and ruled), plus §0.2's v1-D2 row, §4.2's table and
§10-WP9's scope. All four now read as D9 leaves them.

**What the ruling does NOT do.** It does not soften D4. The chooser, both canned answers,
`adopt_ask_scenario`, `adopt_ask_ladder` and the `claimed` operand are still deleted, and §10-WP9
still pins the chooser's absence. Adoption still assesses maturity rather than asking about it;
it asks exactly one thing, and that thing is not maturity.

---

## §7 — Collisions: two new archive classes (D1, D3)

### §7.1 — `scripts/` — archive theirs, install the framework's, name every path (D1)

**Reverses the shipped behaviour.** Today `adopt_install_framework` skips any install-set path
where `[ -e "$dst" ]` — the operator's file wins, the framework's version is never installed, and
the run's own stub says what that costs: anything depending on the missing script is inert, and
nothing announces the framework as broken. The sharpest edge, recorded in `## BL-242:` and worth
repeating because it decides the direction: `scripts/verify-install.sh` and
`scripts/upgrade-project.sh` are both in the install set, so under skip-on-collision a project
whose tree happens to contain either name **cannot self-repair or upgrade, silently**.
Framework-wins removes that class outright.

The install set is **derived, never enumerated**: `soif_parse_shipped_scripts` over `init.sh`'s
own copy list — 65 files on `main` at 2026-08-24 (36 `scripts/` + 24 `scripts/lib/` + 3
`scripts/host-drivers/` + 2 `scripts/hooks/`), 67 on the measured branch, and the drift between
those two numbers inside one day is the argument for the derivation (§13-V6). The collision-prone
tier is the top-level `scripts/` set, whose realistic names are the generic ones a real project
already owns and has wired into a Makefile or CI: `scripts/validate.sh`, `scripts/test-gate.sh`,
`scripts/cut-release.sh`, `scripts/check-updates.sh`, `scripts/check-versions.sh`,
`scripts/probe-tool.sh`, `scripts/resume.sh`.

**Mechanism.** In Act 2's archive step, every colliding install-set path is archived under class
`script` (§7.3); in the install step, the framework's version is installed over it — **after a
receipt check**: an install-set path that exists in the adoptee and is *not* in the archive
MANIFEST refuses the run, because an overwrite without an archived original is precisely the v1
§1.2 destruction class this feature exists to end. The notice then names **every archived path**
— not a count; the shipped stub already prints the paths for the same stated reason ("*3
collisions* tells an operator nothing they can act on") — with each path's restore line, plus the
standing warning, which is a decision and not boilerplate: **restoring your version of a
framework script may break the framework — accuracy, enforcement, and self-repair may be
compromised.** The existing `--re-add` path is the sanctioned restore route and already warns and
records; class `script` joins the classes it serves.

**Two consequences this design owns rather than discovers later** (both from `## BL-242:`): it
fixes the self-repair hole above, and **it breaks the adoptee's build at the moment of adoption,
not later** — if their Makefile calls `scripts/validate.sh`, that call now reaches the
framework's script. The notice is therefore not a courtesy; it is the only thing standing between
the operator and a confusing failure.

### §7.2 — Documents — written to framework requirements, originals archived (D3)

An adopted project gets documents that **match the framework's documentation requirements** —
adapted or merged from what the project already has, or written completely new where the
assessment shows the architecture and feature set have moved far enough that merging would carry a
false picture forward. **The old documents are archived in the project for historical purposes.**
This settles the objection the shipped `adopt_stub_project_docs` raises (*"a CLAUDE.md you already
have would be a collision, not a gap"*) by making it archive-and-replace, not a refusal — and it
**narrows v1-D5's "project files: keep theirs" cell** to files the framework does not claim: the
boundary is the framework-required document set (derived from what `init.sh` generates and the
phase gates read — `CLAUDE.md`, `PROJECT_INTAKE.md`, `PRODUCT_MANIFESTO.md`, `PROJECT_BIBLE.md`,
`APPROVAL_LOG.md`, `CHANGELOG.md`, **`FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md`**, and their
siblings; WP11 derives the list from `init.sh`'s writers rather than maintaining this
parenthesis). Their `README.md` stays theirs; their CI stays under §7.4's carve-out.

**`FEATURES.md`, `BUGS.md` and `RELEASE_NOTES.md` are IN the set — ruled by Karl on 2026-08-31,
and this OVERTURNS v1 §7.5.** His words: *"All previous info is archived and the user informed so
that they may retrieve or add to the new proper framework files."* v1 §7.5 had settled those three
the other way — *"If present, treated as theirs: kept, and reconciled by the interview rather than
overwritten"* — so v1 §7.5 joins v1-D5's project-files cell as v1 text D3 contradicts — **two texts, from one
decision.** *(An earlier draft called it "a fourth", conflating two different sets: §6.1's THREE
counts the D1–D3 decisions that contradict settled v1 text, while §0.2's four counts v1 decisions
that change. Neither ordinal was ever D3's to take, and the conflation is the exact one §6.1 warns
against.)*
*(This section deferred on all three until the ruling, after an earlier draft had listed
`FEATURES.md` among the set and so decided half the question in passing. The deferral was right in
posture and wrong in its guess: it defaulted to v1 §7.5 as the settled text, and D3 was always the
later ruling — what was genuinely undecided was only its REACH.)*

**THE OPERATOR MUST BE TOLD, AND THAT IS PART OF THE REQUIREMENT RATHER THAN A COURTESY.** Karl's
sentence carries a second clause the archive alone does not satisfy: *"the user informed so that
they may retrieve or add to."* So for every archived document, adoption **names the file, names
where its original now lives, and says in as many words that content can be retrieved from the
archive and added to the new framework file.** An archive nobody is told about is a deletion with
extra steps, and these three are the documents most likely to hold history the operator wrote by
hand. This binds the notice's content, not its phrasing: WP11's disclosure block must name every
archived document path — never a count — and WP12's document writing must repeat the invitation
at the point the new file is created, because that is when the operator can act on it.

Timing across the acts: the **archive** of every colliding framework-named document happens in Act
2 (the archive precedes any writer — the invariant that makes the archived copy *theirs*); the
**writing** happens in Act 4, where a model can actually adapt content per D3 and stamp v1 §8.6's
provenance headers on everything that describes what already existed. Between the acts the
originals remain in place and untouched — Act 2 archives; only Act 4 replaces. An Act 4 write to a
pre-existing path whose original is not in the archive MANIFEST refuses, same receipt rule as
§7.1 — **except where that path's existing content already carries v1 §8.6's Act-4 provenance
header, which means Act 4 wrote it in an interrupted earlier attempt and is re-writing its own
output, not overwriting the operator's** (A2, §8.4). Without the exemption the rule refuses every
net-new document Act 4 itself created — the path exists, and no archived original exists because
the adoptee never had one — and re-entry deadlocks.

**`PRODUCT_MANIFESTO.md` is in the required set but is NOT written by Act 4 (A3).** It is a Phase 0
*output*, so it is written in **WP12b**, after the Phase 0 intake is confirmed. Writing it in Act 4
would invert the framework's own order and would flip off the `resume.sh` branch that routes the
operator into Phase 0 at all (§8.5).

### §7.3 — One mechanism, four classes

`adopt_archive_inventory` already emits `<originalPath>\t<class>\t<archivedPath>` rows and the
MANIFEST already carries per-entry class, sha256, mode, and restore lines; `git-hook` entries
already get a what-it-did description. D1 and D3 add classes `script` and `document` to the same
inventory, the same MANIFEST, the same disclosure block, the same `--re-add` route, and the same
pre-staging secrets scan — one mechanism serving four cases rather than three mechanisms, which is
`## BL-242:`'s stated reason for cutting it this way. The archive home
(`.claude/adoption-archive/<timestamp>-<pid>/`) and its MANIFEST schema are unchanged from the
shipped WP6.

### §7.4 — The CI carve-out — carried unchanged

v1-D5's carve-out survives intact: pipelines are **audited, never archived**; framework CI
installs as its own files; SDLC-undermining workflows get loud findings; keep-or-retire is the
operator's recorded decision. Nothing in D1–D8 touches it, and `## BL-242:` assigns it to WP7
where v1 left it.

---

## §8 — Mechanics under the four acts

### §8.1 — The driver, the act boundary, and exit codes

`scripts/adopt-project.sh` remains the Act 2 driver — not an `init.sh` mode, for v1 §8.1's
reasons, all still true. Its M2 declared-core-dependency header gains
`scripts/lib/` access to the resolver's entry point it now invokes (author-proposed: invoke
`scripts/resolve-tools.sh` as a command, exactly as `init.sh` does, rather than sourcing new core
libs — the smaller M2 delta). Exit codes keep their shipped meanings (0 completed; 1 did not
complete — refusal, blocker, halt; 2 bad usage or unusable target), with "completed" now meaning
**Act 2 completed**: the driver's final block says so, prints the phase-0 standing, and hands
off to `scripts/resume.sh`. Acts 3/4 are a Claude Code session, not a driver invocation; their
completion is recorded in state (§8.3), which is what the `resume.sh` branch predicate reads.

### §8.2 — Act 2's order, and why each constraint is where it is

| # | Step | Constraint it satisfies |
|---|---|---|
| 0 | **The re-adoption preflight** (**A1**) — refuse before anything is asked or written | **Before the tier question**, so a second run neither re-interrogates the operator nor destroys what the first produced. `soif_adoption_adopted` true → refuse, naming `scripts/resume.sh` (the assessment route) and `--re-add`. Stamp absent but a prior `.claude/adoption-archive/` present → refuse and NAME that directory: an interrupted first run, whose recovery is the archive's own restore lines. **Without this, `adopt_write_file` (`cat >`) overwrites `phase-state.json` and a completed `PROJECT_INTAKE.md` at steps 7's stages, and the second-stamp refusal does not fire until the manifest stage — after both** |
| 1 | **The tier question** — `adopt_ask_audience`, kept by D9 and re-purposed (§6.5) | **Before step 3**, which keys on its answer, and before step 2, which installs software: a run abandoned at the only question adoption asks has changed neither the repository nor the host. Shipped position, effectively unmoved — `adopt_main` already asks it before any writer (§13-V4) — so this row costs a re-purpose, not a re-order |
| 2 | Tool resolution (`scripts/resolve-tools.sh` against `templates/tool-matrix/`) | Before the secrets check, which needs the scanner it installs (§6.2). The one genuinely new step in the order |
| 3 | The secrets check (§6) — at `organizational` every non-clean status stops; at `personal` findings and `scan-failed` warn and carry on, while `tool-unavailable` stops unless an acceptance is recorded (§6.1's ladder) | Before any write, so a *stopped* adoption has changed nothing — today's `adopt_stub_secrets_disposition` fires after the reverse intake, which a stop (as opposed to a notice) must not. **It keys on step 1's answer, never on the manifest**, which is not written until step 7 — the tier must be carried in the run, and `ADOPT_DEPLOYMENT` is what carries it (§6.5) |
| 4 | Test-debt census (`adopt_test_debt_record`) | **Before the install** — shipped and kept; the census reads `git ls-files` and its independence from the framework copies is stated in the code rather than resting on index timing |
| 5 | Collision archive (`adopt_archive_write`), four classes | **Before any writer** — shipped and kept; an archive taken after a writer captures the framework's file under the operator's name. Now also before the D1 installs it newly precedes |
| 6 | Framework install, framework-wins + receipt check (§7.1) | After the archive that makes overwriting honest |
| 7 | State: `phase_state` → `intake` (mechanical prefill only) → `manifest` + stamp → **an empty `APPROVAL_LOG.md` skeleton (A4)** | `# BF-ADOPT-STATE-ORDER`, carried; §8.4's fail-safe analysis carried. The intake's judgment sections move to Act 3, so Act 2 writes the prefill-confirmed cells and leaves judgment cells blank |
| 8 | The adoption commit (`adopt_stage_and_commit`) | Explicit staging, carried. **`## BL-225:` sits exactly here** — the staged-tree/`.gitignore` defect — and §10's sequencing gates the build on its fix |
| 9 | Hooks (`adopt_install_hooks`) | **Last, after the commit** — shipped and kept, with its marker-fenced commit-msg composition |

### §8.3 — State writes and the stamp's v2 shape

The fail-safe order and its per-surface analysis carry from v1 §8.4 unchanged (phase-state first
means every interruption leaves the phase gate live and the tier reading strict — the safe
direction on both surfaces v1 verified). What changes is content:

- **`phase_state`**: `current_phase: 0` for every adoption, and it **stays 0** until the ordinary
  gates move it (D10). No scenario, and no landed-rung arithmetic in any act.
- **The stamp** (`soif_adoption_stamp`, still one call site, still an additive `jq` merge into
  `.adoption`, still refusing a second stamp): loses `scenario` and `landedPhase` as Act 2 inputs;
  author-proposed v2 block: `{schemaVersion: 2, adopted: true, adoptedAt, adoptedAtCommit,
  scannerReportSha256}` — no `placement` key, because there is no placement to record (D10). The `adopted` accessor
  (`# BF-ADOPT-FLAG-READ`) and every gate arm reading it are untouched — the flag's meaning is
  "this project entered by adoption", which is true from Act 2 onward.
- **Act 4's assessment write** is a **separate additive merge, not a re-stamp**: a new
  one-call-site writer (author-proposed name `soif_adoption_assess`) merges
  `.adoption.assessment = {assessedAt, verdict, interviewRef, evidenceRef}` and writes an
  `adoption_event` audit row. **It does not touch `current_phase`** — under D10 there is no rung
  to advance to, and `landedPhase` is gone from the record. This removes the design's only write
  to `phase-state.json` outside Act 2, and with it the whole question of whether that write was
  entitled to bypass the phase gate. Stamp-once stays a property (the stamp writer still refuses when `adopted` is already
  true); the assessment writer refuses when an assessment block already exists, for the same
  silent-move reason the stamp's own comment records about `adoptedAtCommit`.

### §8.3a — Four decisions this document's author made, and they are NOT Karl's (A1–A4)

**Karl delegated these four on 2026-08-31** — *"Fix the blocker and decide the 3 gaps now"* — after
an architecture review raised them. They are recorded apart from D1–D10 and labelled **A**, not
**D**, because this document's recurring defect has been recording the author's inference as the
owner's ruling: three times (§4.2's blast radius → D9, the *"does not ask"* headline, §4.3's
placement → D10). A delegated decision is still the author's, and mislabelling it would repeat the
pattern with permission. **Any of these four may be overturned without overturning a D.**

| # | Decision | Alternative rejected, and why |
|---|---|---|
| **A1** | **A step-0 re-adoption preflight that refuses before any question or write** (§8.2 step 0). | *Let the second-stamp refusal handle it* — it fires at the manifest stage, after `adopt_write_file` has already `cat >`-overwritten `phase-state.json` and the intake. Under D10 the clobbered `current_phase` is **gate-earned**, so the re-run became the one surviving writer that violates §8.3's *"stays 0 until the ordinary gates move it"*. Refusing late is not refusing. |
| **A2** | **Act 4 writes its assessment merge LAST, and §7.2's receipt rule exempts a path whose existing content carries Act 4's provenance header** (§8.4). | *Write the merge first* — a crash after it leaves the documents unwritten while the `resume.sh` predicate goes false: the feature's largest deliverable silently skipped, with no surface re-offering it. That is the silent-success class this repo hunts. *Key the exemption on a separate Act-4 ledger* — rejected as a second file that can desynchronise from the documents it describes; v1 §8.6's provenance header is already mandatory on exactly this set and cannot. **Stated failure mode:** a document whose header the operator hand-deleted is then treated as theirs and refused — the safe direction. |
| **A3** | **Act 4 does NOT write `PRODUCT_MANIFESTO.md`; the manifesto is a Phase 0 OUTPUT, written in WP12b after the intake is confirmed** (§8.5, §7.2). | *Write it in Act 4 with the other framework documents* — it is in §7.2's required set, and writing it flips OFF `resume.sh`'s kickoff branch (`[ ! -f "PRODUCT_MANIFESTO.md" ]`, `resume.sh:51`), so a completed adoption lands in the classic resume prompt and **skips the intake-first entry D10 promises**. Writing a Phase 0 output before Phase 0 runs also inverts the framework's own order. |
| **A4** | **Act 2 writes an empty, headed `APPROVAL_LOG.md` skeleton** (§8.2 step 7). | *Document the red window instead* — `check-phase-gate.sh:262` refuses on the missing file and `exit 1`s **before parsing the phase at all**, so the resting state cannot run its own gate, with no adoption-aware message. §3.6 says the phase gate is live at the landing; without this that claim is aspirational. **The skeleton must carry no dated approval row** — an empty log leaves every boundary un-approved, which is correct; a pre-dated one would manufacture an approval. |

### §8.4 — Fail-safe order — the between-acts row, and the Act 3/4 rows (A2)

v1 §8.4's two-row table (phase-state present/manifest absent = phase gate live + tier strict;
manifest present/phase-state absent = no phase gate at all) is carried as verified-by-v1 and
**not re-executed here** (§13-U). v2 adds the between-acts row it creates: **stamped, committed,
unassessed** — phase gate live at phase 0, commit-time message checks live, tier read from the
manifest, everything ahead of the project. That is the state an abandoned adoption rests in, and
it is safe by §3.6's construction rather than by write-order luck.

**The Act 3/4 span had no analysis at all, and A2 supplies it.** Act 2 is analysed per surface;
a death inside the model session was not. The only state marker across the whole span is the
`.adoption.assessment` merge, so **where in Act 4 it is written decides the failure shape** — and
A2 puts it LAST:

| State | What exists | What `resume.sh` offers | Why it is safe |
|---|---|---|---|
| **assessed-unwritten** — crash after the interview, before any document | assessment record; no documents; **no** `.adoption.assessment` | the Act 3 prompt again | The interview is re-run. Wasteful, never wrong; nothing partial was published |
| **mid-documents** — crash between document writes | some framework documents, each carrying v1 §8.6's provenance header; **no** `.adoption.assessment` | the Act 3 prompt again | Re-entry re-writes its own output, permitted by the receipt exemption above. Without that exemption §7.2 would **refuse every net-new document Act 4 itself created** — the path exists, and no archived original exists because the adoptee never had one — a deadlock the session cannot pass |
| **written-unpresented** — documents complete, verdict not delivered | all documents; **no** `.adoption.assessment` | the Act 3 prompt again | The merge is last precisely so this state re-offers rather than skips. The cost is a re-presented verdict; the alternative was a silently skipped one |

**All three re-offer.** That is the property A2 buys, and it is why the merge is last: a
mid-session marker would make some of these states look finished.

### §8.5 — `scripts/resume.sh`'s adoption branch

`resume.sh` is the shipped, state-aware first-message generator — four branches today, zero
adoption awareness (§13-V8). WP12 adds the fifth: **predicate** `.adoption.adopted == true` and no
`.adoption.assessment` in `.claude/manifest.json` (via `jq`, exactly the shipped
`# DELTA-RESUME-PHASE4` pattern of reading state) → emit the Act 3 prompt, pointing at the
assessment brief Act 2 wrote into the adoptee (author-proposed `.claude/adoption/assessment-brief.md`,
beside the persisted `.claude/adoption/scout-report.json` the shipped writer already produces).
**Branch order matters and is a designed fact, not an accident**: the adoption branch is checked
**before** the intake branch, because Act 2 leaves a partially-filled `PROJECT_INTAKE.md` at phase
0 — exactly the state the intake branch's blank-cell predicate (`# BL-202-INTAKE-PREDICATE`)
matches — and an adopted-unassessed project must be offered the assessment, not the greenfield
intake interview. After Act 4 writes the assessment block, the predicate goes false and `resume.sh`
falls through — and **A3 names the branch it falls through to, because the shipped branch math
decides it and the first draft of this sentence did not say which.** Act 4 leaves
`PRODUCT_MANIFESTO.md` **unwritten** (A3), so `resume.sh`'s kickoff branch
(`[ ! -f "PRODUCT_MANIFESTO.md" ]`) fires and the operator is routed into the **Phase 0 entry** —
which is what D10's *"starts from the beginning … Phase 0 intake first"* means in practice.

**Two branches cover this, and the design leans on the robust one.** The intake branch
(`# BL-202-INTAKE-PREDICATE`) fires only above **20** blank cells, which would make the routing
depend on an unstated numeric coupling to a predicate in another script — how many judgment cells
Act 4 happened to leave blank. The kickoff branch has no such threshold: the manifesto is either
there or it is not. Act 4 still leaves every judgment cell blank per `# BL-204-PREFILL-READ`, so
both branches point the same way; **WP12's proof asserts the named branch, never a blank count.**

### §8.6 — The Adoption Record records an assessment and a plan (WP7, re-cut in content)

WP7 is **unchanged in need and changed in content** (`## BL-242:`'s words): the Adoption Record
now records the assessment and the plan, not a scenario and a rung. Its structural contract —
v1 §8.8's eight clauses making the record unparseable as a gate approval, with the record lint
pinning them — carries over **verbatim and unweakened**; nothing in the new content touches the
eight readers those clauses defeat. Added content rows: the assessment's findings and their evidence,
the verdict (including rebuild, when returned), the interview's recorded answers by reference, the
secrets dispositions by fingerprint (§6.3), the archived-path list by class (§7.3), and the plan's
location. The audit-row design (one `adoption_event` type, `details.event` discriminator, five
surfaces per new enum member) carries from v1 §8.9 unchanged, and Act 4's two writers (§8.3) join
its emitter list.

### §8.7 — What else does adoption skip that `init.sh` does? — the named open question

Tool resolution was found missing **by one grep** (§13-V3), which forces the wider, unenumerated
question `## BL-242:` records: **what else does adoption skip that `init.sh` does?** This design
refuses to answer it with a hand list — the hand list is how v1's status row went wrong three
times. Verified instances beyond tool resolution (§13-V10): the **detection baseline** —
`init.sh` writes `git rev-parse HEAD` to `.claude/last-checked-commit.txt` at **2** sites; the
adoption driver and its lib contain **0** mentions, so an adopted project's out-of-band-commit
detector has no baseline and v1 §8.7's design for it was never built. Visible in `create_project`'s
step sequence and absent from `adopt_main`: `generate_claude_md`, `generate_approval_log`,
`generate_gitignore`, `generate_ci`, `generate_release`, `install_precommit_hook` — some of which
are D3/WP7 work by design, and some of which nobody has dispositioned.

**WP9's first deliverable is therefore an init-parity audit**: derive `init.sh`'s effect list (the
starting recipe — `grep -nE '^  (generate_|install_|prepare_)[a-z_]+' "init.sh"` over the
`create_project` body, plus the `resolve-tools.sh` and baseline call sites, acknowledged partial),
place every row into exactly one of {Act 2 | Act 3/4 | deliberately not-adoption's, with the
reason}, and commit the table to this document by amendment. Until that table exists, "adoption is
finished" has an unbounded denominator — which is `## BL-242:`'s core complaint about the feature,
applied one level down.

---

## §9 — What does not change

| Kept | Anchor | Note |
|---|---|---|
| Every phase-gate predicate | `scripts/check-phase-gate.sh` | v2 adds no gate arms beyond WP3's shipped ones, and under D10 it needs none: nothing writes `current_phase` outside Act 2's phase-0 landing, so every boundary is crossed by the ordinary route |
| Scout, whole | `scripts/scout.sh`, `scripts/lib/scout/` | Act 1 is the shipped Scout. Candidate future section (`chooserEvidence`) dies with the chooser |
| The in-core enabling arms | `scripts/lib/adoption-stamp.sh`, `# BF-ADOPT-FLAG-READ`, the TDD adoption-window arm | The `adopted` flag's meaning and every reader; the stamp's writer changes shape (§8.3), not home or discipline |
| The test-debt ledger and ratchet | `scripts/lib/adopt/adopt-test-debt.sh` (WP5b, shipped) | Untouched; still kind (c)'s forward equivalent |
| The collision archive mechanism | `scripts/lib/adopt/adopt-archive.sh` (WP6, shipped) | Gains two classes (§7.3); layout, MANIFEST, `--re-add`, pre-staging scan unchanged |
| The redaction projection | v1 §6.2's field allowlist, shipped in Scout's secrets section | Every §6 artifact inherits it; no artifact ever carries a value |
| The state order and staging discipline | `# BF-ADOPT-STATE-ORDER`; explicit-path staging | Carried verbatim |
| The module contract and its lint | `docs/module-contract.md` M1–M5; `scripts/lint-module-dependencies.sh`, `# BL-215-CORE-GLOB-SYNC` | §3.7 keeps both new contact points on the right side of M3 |
| The CI carve-out | v1 §7.4 | Carried unchanged (§7.4) |
| The Adoption Record's structural contract | v1 §8.8's eight clauses | Carried unweakened; content re-cut (§8.6) |
| The house rules | No merge on red; never `--no-verify`; TDD with mutation proofs; hermetic tests; both-list registration; marker citations | Including for this build |

---

## §10 — Build plan (re-cut work packages)

Shipped packages (WP0–WP4, WP5b, WP6, WP8 — see §1.1) are **history, not plan**, and are not
re-cut retroactively. **WP5 is RETIRED** (§5.1) — not re-cut, retired; its only surviving
shell-checkable residue (the record lint) was always WP7's. New packages are numbered from WP9 to
avoid colliding with shipped numbers. Every mutation proof asserts on **exit codes, never printed
labels** (v1 §10's rule, inherited with its `[WARN]`-trap rationale), and every enforcement change
carries the RED-under-neuter → GREEN-restored discipline.

**Sequencing: `## BL-225:` first, then WP9 → WP10 → WP11 → WP12 → WP7.** BL-225 (the driver
stages 64 files, then a `.gitignore` refusal claims *"nothing has been committed"* over a
half-staged tree) is not a v2 package — it is a shipped defect on the exact path every Act 2 run
takes, and `## BL-242:` names it the precondition for any resumption. No v2 package lands before
its fix.

| WP | Scope and boundary | Proofs |
|---|---|---|
| **WP9 — Chooser deletion + act boundaries (D4, D5 skeleton)** | Delete `ADOPT_CHOOSER_QUESTION`, both answers, `adopt_ask_scenario`, `adopt_ask_ladder`, the claimed operand (`# BF-ADOPT-FLOOR`'s second input). **`adopt_ask_audience` is RETAINED and re-purposed (D9)** — it is not a deletion target, it moves to the head of Act 2 (§8.2 step 1), and its output stops feeding placement while continuing to feed `deployment`; re-shape `soif_adoption_stamp` per §8.3 (in-core — inherits WP3's dual-direction proof duty); **A1's step-0 re-adoption preflight** (refuse on a stamped tree, and on an unstamped tree carrying a prior `.claude/adoption-archive/`, naming it) and **A4's empty `APPROVAL_LOG.md` skeleton**; Act 2 lands phase 0 and prints the Act 3 handoff; the init-parity audit table (§8.7); drive-by: `adopt_stub_hooks`'s stale owner string → WP7. **Boundary: no tool resolution, no secrets stop, no archive classes — WP10/WP11's.** | The WP4 suite's `CHOOSER_LITERAL` pin is **re-aimed at absence**: the verbatim question occurring anywhere in `scripts/` fails. **Mutation:** restore `adopt_ask_scenario`'s call in `adopt_main` → RED. **D9 needs the opposite pin, and it is not optional** — a suite that only proves absence would go green on a WP9 that deleted both questions: assert the audience question is ASKED and that `deployment` lands non-empty in both written files → **mutation:** delete `adopt_ask_audience`'s call → the fixture's `manifest.json` and `phase-state.json` carry `deployment: ""` and `assert_choosable` fail-closes → RED. Assert on the **empty value and the exit code**, not on the refusal's wording. Stamp dual-direction: (i) a fixture adoption lands `current_phase` 0 — mutate the landing to any other rung → RED via the fixture's phase-state (the stamp carries no `placement` key to assert on: §8.3 removed it with D10); (ii) the second-stamp refusal still refuses (regression, exit-code-asserted). **A1:** a re-run against a stamped fixture refuses with the **tree hash unchanged** → **mutation:** drop the preflight → the fixture's `phase-state.json` reverts to `current_phase: 0` and its `gates` dates null → RED. Assert on the reverted state, not on the refusal text — the second-stamp refusal fires either way and says almost the same thing, which is what made this defect survivable. **A4:** the skeleton exists after Act 2 and `check-phase-gate.sh` runs to a verdict instead of `exit 1`-ing on a missing file → **mutation:** drop the skeleton write → the gate refuses before parsing the phase → RED; **and the converse, or the proof is half a proof:** the skeleton contains no dated approval row, so `--gate phase_0_to_1` still blocks → **mutation:** seed a dated row → the gate passes a boundary nobody approved → RED |
| **WP10 — Act 2 completion: tool resolution + the tier-scoped secrets check (D2)** | Invoke `scripts/resolve-tools.sh` before any write; **§6.1's tier-scoped table, all four cases** — at `organizational` findings stop until dispositioned and both `tool-unavailable` and `scan-failed` stop with no escape; at `personal` findings and `scan-failed` warn loudly and carry on, while `tool-unavailable` stops unless an acceptance is recorded; the §6.3 disposition record via `bypass_audit_append`; the §6.2 re-scan-after-install mechanic; refusal-on-unrecordable. **Boundary: no archive or install changes — WP11's.** **Nothing blocks this package any more:** §6.5 is settled by D9 (it keys on `ADOPT_DEPLOYMENT`, produced at §8.2 step 1) and §6.4's escape is ruled — **hard refusal at `organizational`, recorded escape at `personal`**. `scan-failed` is ruled too: **hard refusal at `organizational`, loud warning that carries on at `personal`** — *"action as if it ran"*. **Nothing in §6 is unruled.** Note the two not-scanned statuses are NOT one code path: they share an organizational arm and differ on personal. | Fixtures per status **and per tier — eight cells, and all eight are specified**: a clean `scanned`/zero-findings fixture **completes at both tiers** → **mutation:** make the clean arm stop → RED at each tier (without those two the matrix says nothing about the regression that would block every well-behaved adoption). Then an `organizational` `scan-failed` report **stops Act 2 before any write** (tree-hash equal before/after, the Scout idempotency precedent) → **mutation:** neuter the `scan-failed` arm → the fixture adopts → RED; a `personal` `scan-failed` report **completes** and its warning **names the unknown** — assert the warning text does NOT render an empty findings list → **mutation:** reuse the findings template with zero findings → RED, and **mutation:** make the personal arm stop → RED. **The two not-scanned statuses must be pinned as separate paths**, because they agree on `organizational` and disagree on `personal`: a fixture matrix that collapses them passes against an implementation that treats `scan-failed` as `tool-unavailable` → assert a `personal` `scan-failed` needs **no** recorded acceptance while a `personal` `tool-unavailable` does → **mutation:** route both through one arm → RED whichever way it is routed. An `organizational` findings fixture with no disposition stops; with recorded dispositions completes, and each `accepted risk` appears as an `adoption_event` row in a fixture ledger **that contains it** (the dead-pin lesson of v1 §8.9). **Mutation:** accept without a signer → RED. A `personal` findings fixture **completes and prints every finding** → **mutation:** make the personal arm stop → RED; **converse mutation:** make the organizational arm warn → RED. **Both directions or one arm is vacuous** — a tiering pinned on one side passes against a table that ignores the tier. `tool-unavailable` stops at both tiers → **mutation:** add any proceed path → RED **at `organizational`**. At `personal` the tiered escape needs both directions or it is vacuous: a fixture with a recorded acceptance completes and the acceptance appears as an `adoption_event` row in a ledger that contains it → **mutation:** drop the signer → refuses → RED; and a fixture with NO acceptance stops → **mutation:** let it proceed unrecorded → RED. **The `organizational` hard refusal needs its own pin in the opposite direction:** feed it a validly recorded acceptance and assert it STILL refuses → **mutation:** wire the personal escape into the organizational arm → the fixture adopts → RED. That is the assertion that catches a tiering implemented as one shared code path |
| **WP11 — Archive classes `script` and `document` (D1, D3 mechanics)** | Extend `adopt_archive_inventory` with both classes; framework-wins install with the receipt check; the every-path notice and the standing warning (string-pinned — it is a decision, not phrasing); **the archived-document disclosure per §7.2 — every archived document named with its archive path AND the explicit invitation to retrieve content into the new framework file** (D3's reach ruling, 2026-08-31); the framework-document set derived from `init.sh`'s writers; Act 2 archives colliding documents, replaces nothing (Act 4 replaces). **Boundary: no document *writing* — WP12's.** | A fixture with a colliding `scripts/validate.sh`: after Act 2 the framework's bytes are at the path, theirs are in the archive with a MANIFEST row and restore line, and the notice names the path. **Mutation A:** restore skip-on-collision → the framework's file absent at the path → RED. **Mutation B:** drop the receipt check → an unarchived colliding path is overwritten in a crafted fixture → RED. **Mutation C:** reduce the notice to a count → RED (path-presence assertion). `--re-add` on class `script` warns, restores byte-identically, records |
| **WP12 — Acts 3 and 4: assessment, verdict, documents, intake pre-fill (D4, D6, D7, D8, D10)** | The `resume.sh` fifth branch (predicate §8.5, ordered before the intake branch); the assessment brief writer; the interview per §5.2 (data classification non-skippable at the Phase 0 intake write); the assessment record schema; `soif_adoption_assess` (§8.3); the D3 document writing with v1 §8.6 provenance headers and the §7.2 receipt rule, now **including `FEATURES.md`, `BUGS.md` and `RELEASE_NOTES.md`** and repeating the retrieve-from-archive invitation at each new file's creation (§7.2); the D6 rebuild exit with `# BL-204-PREFILL-READ`-pattern intake pre-fill; **A2's write order — the `.adoption.assessment` merge LAST, after every document** — and **A3: Act 4 does NOT write `PRODUCT_MANIFESTO.md`** (WP12b does, after the intake is confirmed); the D8 verdict artifact and its two-halves check; revise `docs/adoption.md` and `docs/scout.md` to describe v2. **Boundary: the model conducts the interview; every proof below is a shell-checkable edge, and the model's judgment quality is explicitly not provable by suite** (§12). | `resume.sh` on an adopted-unassessed fixture emits the assessment prompt; on an assessed one, **the kickoff branch by name** (A3) — asserted on the branch taken, **never on a blank-cell count**, because the intake branch's `>20` threshold would make the proof depend on how many judgment cells Act 4 happened to leave. **Mutation:** have Act 4 write `PRODUCT_MANIFESTO.md` → the assessed fixture lands in the classic resume prompt and the Phase 0 entry is skipped → RED. **A2:** an assessed fixture interrupted mid-documents re-offers the Act 3 prompt and re-entry re-writes its own provenance-headed output → **mutation:** write the assessment merge first → the same fixture reports finished with documents missing → RED; **mutation:** drop §7.2's provenance exemption → re-entry refuses its own file → RED. **Mutation:** break the predicate's assessment half → an assessed project re-prompts for assessment → RED; break its order → an adopted-unassessed fixture with a blank-cell intake gets the intake prompt → RED. The Phase 0 intake write without a recorded data classification refuses → **mutation:** default it → the write succeeds → RED. **Assert on the refusal, not on a landed phase:** the first draft of this proof ended "the fixture lands ≥2 and the shipped ZDR backstop fails the gate", which under D10 can never happen — nothing lands ≥2 — so the mutation had no reachable RED. A fitness finding without a requirement pointer fails the verdict check → RED. The verdict artifact missing its plain half, or its recommendation missing reasoning, fails the two-halves check → RED. An Act 4 write to a pre-existing unarchived path refuses → RED |
| **WP7 (re-cut) — Adoption Record + audit rows + CI carve-out + provenance lint + the commit-time hook** | v1-WP7's deliverables with §8.6's content re-cut: the record (eight clauses, record lint), `adoption_event` across all five enum surfaces with a fixture that contains it, the CI audit and keep-or-retire record, the provenance-header lint, and — **last, as Karl already decided** — the fallback pre-commit hook install, now that the artifacts it reads exist. | v1-WP7's re-aimed proofs carry: the record lint is the mutation target for clause 5; the joint-violation fixture is the labelled defense-in-depth proof. The hook installed on a completed fixture admits a compliant commit and blocks a non-compliant one **by exit code**; installed-before-artifacts is unreachable by construction (it is the last step of the last package) — assert the reachable half |

Every new suite registers in **both** `tests/full-project-test-suite.sh` and the `tests.yml`
unit list per the house rule, with the `init.sh`-invoker exemption audited by execution, not grep
— and one shipped caveat inherited: `tests/test-brownfield-wp3-regenerate-path.sh` is full-lane
only, so WP9's stamp changes must add their pins to a PR-blocking suite, not that one.

---

## §11 — Non-goals and rejected alternatives

- **Amending v1 instead of superseding it** — rejected. D4 deletes a decision v1 §0.1 lists as
  settled; an amendment would leave a document whose settled-decisions table contains an overturned
  row, the self-contradiction class v1's own changelog exists to remove (its A-BF-4 records
  exactly that failure at smaller scale). `## BL-242:` posed the amend-or-supersede question;
  this document is the answer, and the supersession is stated in Document Control rather than
  discovered by diff.
- **Keeping the chooser as a demoted, evidence-checked hint** — rejected by D4's terms: deleted,
  not demoted. A demoted chooser is still a self-report from the population least equipped to give
  one, now with extra machinery to distrust it.
- **A second question ("was this built with an SDLC framework?")** — rejected in the same
  decision. Scout detects the framework's own artifacts without asking; everything else is a
  claim.
- **One-process adoption (shell drives the model, or the model drives the writes)** — rejected;
  the split is forced (§3.1). A shell driver cannot hold D7's interview; a model session doing Act
  2's writes surrenders the deterministic, testable, refuse-loudly write discipline the driver
  already has.
- **Landing at the scanned rung in Act 2, assessment optional** — rejected. It reintroduces
  land-high-by-abandonment through the evidence door: a project with impressive artifacts and no
  verified assessment would rest above phase 0 with nobody having looked. Phase 0 is
  the only resting state the promise permits — and under D10 the only one it can express (§3.6).
- **Performing the rebuild inside adoption** — rejected by D6: unbounded, and duplicates the
  ordinary path that already exists.
- **Stack-based fitness verdicts** — rejected by D7: an opinion wearing a certification stamp.
- **A conclusion-only verdict with details on request** — rejected by D8: the reasoning is the
  deliverable, and `docs/messaging-standard.md` Part 1 is the binding shape.
- **Keying the secrets tiering on `enforcement_level` (block at strict, warn below)** — v1 §6.3's
  own spelling, rejected **by derivation rather than by preference** (§6.1). The ordinary personal
  project is `personal` + `strict` (`# BL-180-ENFORCEMENT-DEFAULT`), so that key sends the
  commonest project there is into the BLOCK arm — the arm Karl's 2026-08-25 ruling explicitly
  keeps it out of. The axis is `deployment`. Recorded as an overturn of **v1 §6.3 as written** —
  one of the three settled things this document changes — while v1-D4's settled core (redact,
  disposition, never execute a rewrite) is intact and its two-arm *shape* is carried forward.
- **Untiered secrets ("every tier stops")** — Karl's 2026-08-23 first pass, **superseded by his
  2026-08-25 refinement**, and listed here only because an earlier draft of this document
  implemented it (§0.3). Not rejected on its merits; simply not the ruling that stands.
- **An UNTIERED answer to `tool-unavailable`'s escape — hard refusal everywhere, or the escape
  everywhere** — the two arms this document and `## BL-242:` both posed as the whole question.
  **Rejected by Karl's 2026-08-31 ruling, which took neither**: the escape is tier-scoped like the
  rest of D2. Kept here because the *framing* was the defect — a false dichotomy in a decision
  whose every other rule already had two tiers (§6.4).
- **Keeping `FEATURES.md` / `BUGS.md` / `RELEASE_NOTES.md` as the project's own** — v1 §7.5's
  settled text, **overturned by D3's reach ruling** (Karl, 2026-08-31). The concern behind v1 §7.5
  — that these carry hand-written history — is answered rather than dismissed: the originals are
  archived and the operator is told, by name, that content can be retrieved into the new files
  (§7.2).
- **Trusting the consumed Scout report's secrets section as-is** — rejected (§6.2): a
  pre-tool-resolution report can honestly say `tool-unavailable`, and acting on that stale answer
  re-opens the hole D2 closes.

---

## §12 — Honest residuals

**Deferred by decision (named, scoped, not designed here):**

1. **`## BL-225:` is a precondition, not a package.** Until fixed, every Act 2 run carries the
   half-staged-tree hazard; §10 sequences it first and this design otherwise leaves its fix to its
   own entry.
2. **`## BL-226:`** ("moved" claimed where nothing moved) — WP11's notice rewrite touches the same
   strings and should close it in passing; recorded so it is checked rather than assumed.
3. **The init-parity audit (§8.7) is a deliverable, not a delivered table.** Until WP9 lands it,
   the skip set beyond tool resolution and the detection baseline is **unknown by construction**,
   and this design says so instead of enumerating from memory.
4. **v1's residuals that survive unchanged**: `init.sh --allow-existing-dir` remains a loaded gun;
   `bypass_audit_append` still validates only object-ness; the two dead enum pins predate
   `adoption_event`; archiving a git hook still promotes an untracked file into version control,
   mitigated not proven by the pre-staging scan.

4a. **Re-adoption and interrupted runs are DESIGNED now, not merely noted** (A1, A2). What is not
    designed: recovery *tooling*. A1 refuses and names the prior archive; it does not roll the
    tree back. `## BL-225:`'s entry asks for a preflight before any write and its fix so far
    covers the staging half only, so an interrupted Act 2 still leaves files on disk — the archive's
    restore lines are the recovery path, and they are manual.

**Cannot be known before a real adoption:**

5. **Whether the assessment's FINDINGS are well-calibrated.** Not its placements — under D10 it
   makes none, which retires the sharpest half of this residual: a mis-calibrated assessment can
   no longer put a project on a rung it has not earned, because it puts it on no rung at all. What
   remains is whether the fitness verdict and the plan are sound. The failure direction is preserved — an unassessed or badly-assessed
   project rests at phase 0, which certifies too little, never too much — but calibration itself
   is only measurable on real projects.
6. **Whether operators run Act 3 at all.** The scheme is safe under abandonment (§3.6); it is not
   *useful* under abandonment. If real usage shows Act 2 endings, the remedy is nagging surfaces
   (`resume.sh` already is one), not weakening the landing.
7. **Whether operators disposition secrets honestly.** Unchanged from v1: "false alarm" with a
   required reason is still self-attested. The control is the record.
8. **Model-judgment quality is not suite-provable.** WP12's proofs pin every shell-checkable edge
   — predicates, refusals, record shapes, the verdict scaffold. Whether the interview is *well
   conducted* and the findings *sound* is an evaluation question (UAT-shaped), and pretending a
   mutation proof covers it would be a test that cannot fail.

**Assumptions that would falsify parts of this design if wrong:**

9. **That the CDF manifest writer stays missing-file-gated** — inherited verbatim from v1 §12-12;
   the four-act split adds a second block (`.adoption.assessment`) to the same blast radius.
10. **That `templates/tool-matrix/` keeps `gitleaks` `"required": true`.** §6.2's "D2 asks nothing
    new" argument rests on it; if the matrix ever demotes it, Act 2 must pin its own requirement
    rather than inherit the demotion. A one-line check in WP10's suite pins the matrix entry.
11. **That `## BL-242:` merges.** §0.4's branch topology caveat: this document cites a backlog
    entry not on every branch. If the BL-242 filing were abandoned, this document's §-citations
    into it dangle and the decision record reverts to conversation — the exact failure mode
    BL-242 was filed to end.

**NOTHING IS AWAITING KARL. The set is EMPTY.** It was three on 2026-08-28; Karl ruled all three
on 2026-08-31, item 15 was raised the same day and ruled the same day. All four are kept below,
struck, rather than deleted — a question that was answered is part of this document's record, and
removing it would hide that the document once got it wrong. **Two of the four were ruled against
this author's stated recommendation, and both are marked as such**, because a design that quietly
absorbs the answers it did not predict cannot be audited for the quality of its predictions:

12. ~~**`tool-unavailable`'s escape** (§6.4)~~ — **RULED (Karl, 2026-08-31): "Yes on personal, no
    on organizational."** Tier-scoped, like every other rule in D2. **The author's recommendation
    was a hard refusal everywhere, and it was wrong in SHAPE, not just in answer** — this document
    and `## BL-242:` both posed a global binary in a decision whose every other rule already had
    two tiers. §6.4 keeps the reasoning because the false dichotomy is the transferable part.
13. ~~**`deployment`'s source in Act 2** (§6.5)~~ — **RULED (Karl, 2026-08-31): keep the audience
    question as a tier question.** Recorded as **D9** (§0.1); §6.5 is now a settled section and
    §10-WP10 has lost its blocker. Two things about how this closed are worth keeping. First, the
    question was never Karl's to have answered earlier — it existed only because
    `## BL-242:`'s D4 blast radius **enumerated** a deletion the ruling never reached (§4.2).
    Second, **the author's proposed fallback was withdrawn, not adopted**: it assumed a
    non-interactive path the driver does not have, and an unanswered mandatory question already
    refuses the run (§13-V16), which is stricter than the default it proposed.
14. ~~**D3's reach over `FEATURES.md` / `BUGS.md` / `RELEASE_NOTES.md`**~~ (§7.2) — **RULED
    (Karl, 2026-08-31): D3 reaches all three**, overturning v1 §7.5, **and the operator must be
    told by name that content can be retrieved from the archive into the new files.** The deferral
    was right in posture and wrong in its guess — it defaulted to v1 §7.5 as the settled text when
    D3 was always the later ruling; only its reach was ever undecided.

15. ~~**Whether `scan-failed` takes the same tier split as `tool-unavailable`**~~ (§6.4) —
    **RULED (Karl, 2026-08-31), AGAINST THIS AUTHOR'S RECOMMENDATION.** *"So action as if it ran.
    Personal project, it can continue with large warning. Organizational, it cannot continue as
    it's required."* So `scan-failed` behaves like a scan that **ran**, not like an absent
    scanner. The author recommended the opposite extension — giving it `tool-unavailable`'s
    stop-with-recorded-escape — to remove the asymmetry where the milder problem was stricter than
    the graver one. **The ruling removes the same asymmetry from the other end**, by loosening
    rather than tightening, and needs no new mechanism to do it. The principle it establishes —
    severity of *what the framework failed to provide*, not of *what the operator ends up knowing*
    — is the reusable part.

---

## §13 — Verification appendix: commands actually run

Executed on **2026-08-24**, working tree `/Users/karl/Documents/Claude Projects/solo-orchestrator`
on branch `feat/messaging-standard` (HEAD `bd0f277`), except where a command names another ref.
Output trimmed for length, never paraphrased. Re-run them; do not quote them.

**V1 — the unbuilt-capability derivation returns 7.**
```
$ cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
$ for f in scripts/adopt-project.sh scripts/lib/adopt/*.sh; do
    case "$f" in *adopt-stubs.sh) continue;; esac
    sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$f"
  done | grep -ohE '\badopt_stub_[a-z_]+' | sort -u
adopt_stub_adoption_record
adopt_stub_certification
adopt_stub_framework_script_collisions
adopt_stub_hooks
adopt_stub_project_docs
adopt_stub_provenance_headers
adopt_stub_secrets_disposition        # | wc -l -> 7
```

**V2 — the two conditional announcers, in source.** Both guards found by grep in
`scripts/lib/adopt/adopt-stubs.sh`: `adopt_stub_framework_script_collisions` opens with
`[ "$n" -gt 0 ] || return 0`; `adopt_stub_secrets_disposition` prints unconditionally on a
non-`scanned` status and guards its found-something arm with the same `[ "$n" -gt 0 ] || return 0`.
Source-verified; run-time silence on a clean fixture **not exercised here** (the WP6 suite's
territory — §13-U).

**V3 — adoption never runs tool resolution; init.sh does.**
```
$ grep -c 'resolve-tools' scripts/adopt-project.sh scripts/lib/adopt/*.sh
scripts/adopt-project.sh:0            (and 0 for all seven scripts/lib/adopt/*.sh files)
$ grep -c 'resolve-tools' init.sh
7
$ grep -n 'resolve-tools' init.sh     # of the 7: four command substitutions invoking it
807:  resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
1001:        resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
1018:        resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
3607:  dry_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
      (plus a cp into the shipped set, a comment, and a chmod roster line)
```

**V4 — the shipped `adopt_main` call order.** Read in full from `adopt_main()` in
`scripts/lib/adopt/adopt-state.sh` (function-name citation per house rule): obtain report →
`adopt_present_evidence` → `adopt_ask_scenario` → `adopt_decide_placement` →
`adopt_ask_audience` → `adopt_run_reverse_intake` → `adopt_stub_secrets_disposition` →
`adopt_stub_certification` → `adopt_test_debt_record` → `adopt_archive_write` →
`adopt_install_framework` → state stages from `_adopt_state_order`
(`phase_state intake manifest`, `# BF-ADOPT-STATE-ORDER`) → `adopt_stub_adoption_record` →
`adopt_stage_and_commit` → `adopt_install_hooks` (which itself ends with `adopt_stub_hooks`,
`adopt_stub_project_docs`). Read-verified from source; **not exercised end-to-end here** (§13-U).

**V5 — the three secrets statuses.**
```
$ grep -n "secstatus" "scripts/lib/scout/scout-secrets.sh" | grep printf
274:    printf 'tool-unavailable\n' > "$work/secstatus"
323:    printf 'scan-failed\n' > "$work/secstatus"
335:    printf 'scan-failed\n' > "$work/secstatus"
344:  printf 'scanned\n' > "$work/secstatus"
```
Plus the taxonomy comment quoted in §6.1, present verbatim in that file. (The two `scan-failed`
writers are the non-zero-exit arm and the unparseable-report arm.)

**V6 — the install set: 65, then 67, then 68 — three values in eight days.** The block below is
the 2026-08-24 measurement. **Re-derived on 2026-08-31 against the `main` this branch lands on it
returns 68** (39 top-level + 24 lib + 3 host-drivers + 2 hooks) — found by an adversarial review,
not by this author re-running his own appendix. That third value is the argument rather than a
footnote to it: a count that moved twice while one document was being written is a measurement
with a date, never a property, which is why §7.1 specifies the collision-prone set by derivation
and never by count.
```
$ . "scripts/lib/scaffold-shipped-set.sh"; soif_parse_shipped_scripts "init.sh" "scripts" | wc -l
67        # working tree, feat/messaging-standard: 38 scripts/ + 24 lib + 3 host-drivers + 2 hooks
$ # same derivation over main's tree (extracted via git archive to a scratch dir):
65        # main: 36 scripts/ + 24 lib + 3 host-drivers + 2 hooks
$ diff <(main set) <(working set)
3a4
> scripts/check-pr-review.sh
50a52
> scripts/record-pr-review.sh
```

**V7 — the chooser's verbatim question exists at exactly three code-and-shipped-docs sites.**
```
$ grep -rln 'built out and needs' scripts/ docs/adoption.md docs/scout.md tests/
scripts/lib/adopt/adopt-chooser.sh    # ADOPT_CHOOSER_QUESTION, # BF-ADOPT-CHOOSER-QUESTION
docs/adoption.md
tests/test-brownfield-wp4-driver.sh   # CHOOSER_LITERAL
```
(Widening `docs/adoption.md docs/scout.md` to all of `docs/` adds only the two design documents:
v1, which quotes the question as the decision it settled, and this file, which matches in several
places: the command above quoting itself, and §6.5's D9 argument, which must quote the chooser
verbatim to show what it asks that the audience question does not.
**Read the hits, do not count them**; `grep -n` over this file locates them, and any count printed
here is falsified by the sentence printing it. *An earlier version said "sole match": true when
written, falsified by §6.5's paragraph added on 2026-08-31, and then falsified a second time by
its own replacement, which printed a count of two inside a `grep -c` that was itself a third
match. A claim about a file, made inside that file, is measured after the claim is added — this
document has now made that mistake three times, and the general fix is the one applied here:
describe the hits, never total them.*)

**V8 — `resume.sh` knows nothing of adoption, and has four branches.**
```
$ grep -c 'adopt' "scripts/resume.sh"
0
```
Branches read from source: the `# BL-202-INTAKE-PREDICATE` intake branch, the
`PROJECT_INTAKE.md` §13 branch, the classic resume, and `# DELTA-RESUME-PHASE4`.

**V9 — gitleaks is already a required matrix entry.**
```
$ grep -n -A3 '"name": "gitleaks"' "templates/tool-matrix/common.json"
190:      "name": "gitleaks",
191:      "description": "Secret detection in git repositories",
192:      "required": true,
193:      "phase": 1,
```
(`min_version: "8.18.0"`; install recipes for `darwin_brew`, `linux_apt`, `linux_dnf`,
`linux_pacman` in the same entry.)

**V10 — the detection baseline is another verified skip.**
```
$ grep -rn 'last-checked-commit' scripts/lib/adopt/ scripts/adopt-project.sh
(no output)
$ grep -c 'last-checked-commit' init.sh
2
```

**V11 — the Scout report is persisted into the adoptee.** `adopt_write_file` in
`scripts/lib/adopt/adopt-state.sh` writes `.claude/adoption/scout-report.json` and the manifest
stamp records its sha256 (`adopt_sha256` over that path) — read-verified from source.

**V12 — the shipped install skip.** `adopt_install_framework` in
`scripts/lib/adopt/adopt-state.sh`: on `[ -e "$dst" ]` the path joins `ADOPT_COLLISION_LIST`,
`n_collided` increments, and the loop `continue`s — the framework's file is never written.
Read-verified from source; this is the behaviour D1 reverses.

**V13 — the branch topology.**
```
$ git branch --show-current
feat/messaging-standard
$ grep -c 'BL-242' "solo-orchestrator-backlog.md"      # working tree
0
$ git merge-base --is-ancestor 4719f00 HEAD; echo $?
1                                                       # the BL-242 filing is NOT an ancestor
$ git branch -a --contains 4719f00
  docs/bl242-brownfield-filing
  remotes/origin/docs/bl242-brownfield-filing
```
All `## BL-242:` quotations in this document were read via
`git show docs/bl242-brownfield-filing:solo-orchestrator-backlog.md`.

**V14 — the suite inventory.**
```
$ ls tests/ | grep -i 'brownfield\|module-dep'
test-brownfield-wp1-scout.sh
test-brownfield-wp2-scout-sections.sh
test-brownfield-wp3-adoption-arms.sh
test-brownfield-wp3-regenerate-path.sh
test-brownfield-wp4-driver.sh
test-brownfield-wp5b-test-debt.sh
test-brownfield-wp6-collision-archive.sh
test-lint-module-dependencies.sh
```

**V15 — `ADOPT_DEPLOYMENT` has one writer, and D4 deletes it.** Run **2026-08-28** on `main`
(HEAD `9858a41`) — a different date and branch from V1–V14 above, and said so rather than folded
in.
```
$ grep -rn 'ADOPT_DEPLOYMENT' scripts/
scripts/lib/adopt/adopt-state.sh:155:ADOPT_DEPLOYMENT=""
scripts/lib/adopt/adopt-state.sh:167:    "$ADOPT_AUDIENCE_ORG") ADOPT_DEPLOYMENT="organizational" ;;
scripts/lib/adopt/adopt-state.sh:168:    *)                     ADOPT_DEPLOYMENT="personal" ;;
scripts/lib/adopt/adopt-state.sh:175:  jq -n --arg p "$ADOPT_PROJECT_NAME" --arg d "$ADOPT_DEPLOYMENT" ...
scripts/lib/adopt/adopt-state.sh:223:  mode="$ADOPT_DEPLOYMENT"
```
One initialisation to `""` at the head of the variable block; **the only two assignments are both
inside `adopt_ask_audience`**; the remaining two are the reads in `adopt_write_phase_state` and
`adopt_write_manifest`. (Line numbers appear above only because they are `grep -n`'s own output;
the claims are stated by function name per the house rule.) `## BL-242:`'s D4 blast radius listed `adopt_ask_audience` as deleted and
§4.2 and §10-WP9 inherited that; §6.5 establishes the line over-reaches, and **D9 (Karl,
2026-08-31) keeps the question**. Note also that the blast radius files it under
`adopt-chooser.sh`; it is in `adopt-state.sh`:
```
$ grep -rn '^adopt_ask_scenario()\|^adopt_ask_ladder()\|^adopt_ask_audience()\|^ADOPT_AUDIENCE_Q=' scripts/lib/adopt/
scripts/lib/adopt/adopt-chooser.sh:147:adopt_ask_scenario() {
scripts/lib/adopt/adopt-chooser.sh:192:adopt_ask_ladder() {
scripts/lib/adopt/adopt-state.sh:159:ADOPT_AUDIENCE_Q="Who is this project for?"
scripts/lib/adopt/adopt-state.sh:163:adopt_ask_audience() {
```

**V16 — adoption has no non-interactive path, and an unanswered question refuses the run.** Run
**2026-08-31** on `main` (HEAD `9858a41`). This is the measurement that **withdrew** an
author-proposed fallback in §6.5 rather than supporting one.
```
$ grep -n -- '--[a-z-]*)' scripts/adopt-project.sh
179:    --root)          ...
181:    --scan-report)   ...
183:    --re-add)        ...
185:    --version)       adopt_module_version; exit 0 ;;
186:    -h|--help)       usage; exit 0 ;;
$ grep -n 'ADOPT_MANDATORY_REFUSAL=' scripts/lib/adopt/adopt-core.sh
74:ADOPT_MANDATORY_REFUSAL="This question has no default and no skip, and no answer was given:"
```
Five flags, none of them a `--yes`/`--non-interactive`; and `adopt_ask_choice` in
`scripts/lib/adopt/adopt-core.sh` — with `adopt_ask_free`, its free-text sibling — calls
`adopt_refuse` and returns 1 when the answer resolves empty (function-name citations per the house
rule; an earlier draft of this line cited the function by file-and-line instead, in the same
appendix that now states the rule). A fail-closed default would therefore be **weaker** than what ships,
not safer. `ADOPT_POC_MODE` is hard-coded `"production"` beside `ADOPT_DEPLOYMENT`'s
initialisation and is never asked — noted because §6's tiering must **not** acquire it as a second
input; `## BL-242:`'s derivation reads `deployment` alone.

### §13-U — What was NOT verified by execution here, stated so nobody upgrades it

- **The eight suites' assertion tally ("309 assertions, 0 failed").** BL-242's measurement of
  2026-08-23, **not re-run** for this document (multi-suite runtime, and
  `tests/test-brownfield-wp3-regenerate-path.sh` is full-lane only). Cite it as BL-242's number
  with BL-242's date.
- **`adopt_main` end-to-end behaviour and the stubs' run-time conditionality.** V2/V4/V11/V12 are
  **source reads**, not runs — a live adoption needs an interactive fixture session, which is the
  WP4/WP6 suites' job. The call *order* and guard *expressions* are observed fact; "and that is
  what executes" rests on the suites, not on this author's run.
- **`soif_adoption_stamp`'s double-stamp refusal and the `# BF-ADOPT-FLAG-READ` fail-closed
  reads.** Read from `scripts/lib/adoption-stamp.sh`; exercised by the WP3 suites, not here.
- **v1's §13 measurement corpus** (gitleaks redaction behaviour, the C7/C8 findings, the §8.4
  partial-state rows, the eight `APPROVAL_LOG.md` readers). Inherited as v1-verified with v1's
  dates; none re-executed on 2026-08-24. v1's own instruction stands: re-run before quoting.
- **The `scan-failed` / `tool-unavailable` arms at run time.** The status strings and their
  writers are grep-verified (V5); forcing each arm (uninstalling gitleaks, corrupting a report)
  was not done here — the WP2 suite covers the report contract.
- **BL-242's PR table.** Hand-assembled by that entry from merge inspection, adopted here on its
  authority (§1.1); this document independently verified the *artifacts*, not the PR attribution.

---

## Self-review pass (fresh-eyes checklist)

- **Every commissioned element present?** Document Control with a derivation-based status row; the
  supersession-and-overturning statement in front matter, §0.2 and §4.1 rather than a footnote;
  the plain-English overview in the messaging standard's five-part shape; §0.1's ten decisions
  with Karl's D4 reasoning verbatim; the four acts with the phase-0 landing's load-bearing
  argument (§3.6); the **tier-scoped** secrets check with all three statuses (§6.1), with
  both not-scanned statuses ruled and **deliberately different** (§6.1's severity ladder, §6.4) and
  the tier value's source settled by D9 (§6.5); the two new archive classes with the
  receipt rule (§7); WP5's retirement and WP7's content
  re-cut (§5.1, §8.6, §10); the resolve-tools verification and the named unenumerated question
  (§8.7); the re-cut work packages with boundaries and exit-code-asserted mutation proofs (§10);
  honest residuals (§12); and a verification appendix whose **unverified list is its own section**
  (§13-U).
- **Are the settled decisions designed within, not relitigated?** Yes — and one earlier failure
  of this exact test is recorded rather than repaired invisibly (§0.3). D1–D8 appear in §0.1 as
  premises. This document overturns v1 in **three** places and all three are Karl's: v1 §4 by D4,
  transcribed; v1 §6.3 by D2, **derived** in §6.1 rather than ruled a second time; and v1 §7.5 by
  D3's reach ruling of 2026-08-31. **Three is also the count of D1–D3 that contradict settled v1
  text** (§6.1) — a coincidence of two different sets, and §6.1 names which is which, because a
  coincidence of counts is exactly how two sets get conflated. `## BL-242:`'s questions are all
  ruled as of 2026-08-31, and **three separate failures of this test are recorded rather than
  repaired invisibly**, because they are three different classes: §6.4's first, which closed a
  question on the authority of a sentence its decision record had already **deleted** (an invented
  authority); §4.2's, which read a **blast-radius enumeration** as part of Karl's ruling and so
  deleted a question he had never been asked about (an inference mistaken for a premise —
  corrected by **D9**); and §6.4's second, which posed a **global binary** in a decision whose
  every other rule had two tiers (a false dichotomy). Only the first is catchable by any command,
  which is why the other two are written out at length rather than left as notes.
- **Is implementation freedom marked?** Every author-proposed mechanism is labelled at its point
  of use: the receipt check and notice shape (§7.1), the framework-document set derivation and
  adapt-versus-replace criterion (§7.2), the disposition file's home (§6.3), the re-scan mechanic
  (§6.2), the stamp's v2 key set and the assessment writer (§8.3), the brief's home and the branch
  predicate (§8.5), the interview's beyond-Karl's-five content (§5.2).
- **Does the prose keep the vocabulary it binds others to?** `gate` is used only for phase
  boundaries; the commit-time and message checks are checks; the one shipped string that says
  otherwise is quoted, not paraphrased (§5.5). The plain-English overview carries no jargon term
  without its gloss.
- **Counts:** every number in this document is either printed in §13 with its command, attributed
  to BL-242 with BL-242's date, or attributed to v1 with v1's — and the one number that *moved
  between branches within a day* (65/67, and 68 by 2026-08-31) is displayed as the argument for
  the rule. **This bullet was false when first written, and the way it failed is the lesson:** an
  adversarial review on 2026-08-31 found three counts wrong in this very checklist — "eight
  decisions" (nine), "two places" (three), and the install-set row — while this line asserted all
  of them were derived. **The claim a self-review makes about its own rigour is the claim least
  likely to have been checked. Re-derive the numbers; do not read this bullet.**
- **Biggest attack surface for the reviewer.** (1) §5's dissolution of certification into
  assessment — the claim that no rung — claimed or landed — leaves the certification pass without an object is the
  deepest structural consequence drawn from D4 and D10, and a reviewer should try to construct a case
  where a project needs gate-by-gate certification that the assessment record does not subsume.
  (2) §8.7's admission that the skip set is unenumerated — the init-parity audit is scheduled, not
  done, and until it lands this design cannot claim Act 2 is complete. Both are flagged rather
  than defended.

---

## Questions for the reviewing architect

Seven, each attached to a decision this design can still change. **Every question that was Karl's
is now ruled** — §12's items 12 through 15, all decided on 2026-08-31 and kept struck there as
part of this document's record. Nothing below is waiting on him; these are the reviewer's.

1. **The assessment record's schema (§3.4, §5.2).** This design requires it and does not fix its
   shape. Should v2 pin a schema now (reviewable, lintable, rigid) or let WP12's build propose one
   (informed by the first real assessment, unreviewed until then)?
2. **The re-scan boundary (§6.2).** Act 2 re-runs the secrets scan when the consumed report's
   status is not `scanned`. Should it *always* re-scan — a consumed report can be stale in
   findings, not just in status — at the cost of doubling the slowest step on large histories?
3. **The document-set boundary (§7.2).** The framework-required set is derived from `init.sh`'s
   writers. Is that the right universe, or should the phase gates' *readers* define it — the two
   derivations may not agree, and whichever is chosen, the other is a drift check WP11 could pin.
4. ~~**Act 4's placement authority (§8.3).**~~ **Retired by D10** — Act 4 writes no
   `current_phase`, so there is no bypass to justify. Kept struck because an adversarial review
   blocked on precisely this question, and the answer was to remove the write rather than defend
   it. *(The question this row used to ask — whether Act 4 should replay each crossed boundary
   through `scripts/check-phase-gate.sh` — survived the strikethrough in the first draft of this
   retirement, still posed as open, two lines under a note saying the write it referred to is
   gone.)*
5. **The interview's floor on maturity questions (§5.2).** v1's S1 interview asked operations
   questions when the operator claimed completion; v2 asks them when evidence shows maturity. If
   the evidence is wrong in the low direction, nobody is asked about incident response for a
   system that is quietly in production. Should exposure answers (D7's internet-facing axis)
   trigger the operations block regardless of evidence?
6. **WP sizing.** WP12 carries Acts 3 and 4 whole — the fifth branch, the interview, the record,
   the writers, the verdict, two page revisions. Split it (branch + record first, verdict +
   documents second), or is the seam artificial because nothing in the first half is shippable
   alone?
7. **The one rule we have not written.** What is the adoption-shaped project in *your* drawer that
   this flow mishandles — and is it a missing interview question, a missing archive class, or a
   reason the four-act shape itself is wrong for it?

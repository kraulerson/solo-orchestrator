# Brownfield Adoption — architecture design v1

## Document Control

| Field | Value |
|---|---|
| **Document ID** | ADOPT-001-ARCH |
| **Version** | v1.2.2, 2026-08-25 — **status row corrected a third time and handed to `## BL-242:`** (§0.2). WP5b and WP6 had shipped since the row was last written, and the feature was filed as `## BL-242:`. **This revision DOES change settled things — see §0.2. TWO or THREE depending on an undecided question: D1 and D3 certainly, and D2 only if §6.3's tiering is read on `enforcement_level` rather than `deployment` (`## BL-242:` D2 sets out why the default personal project is the case that diverges).** (An earlier version of this very cell used the "no settled decision changed" formula, and §0.2 two commits later declared it false while the cell kept saying it. The document narrated review catching the sentence and left the sentence standing 116 lines above.) · v1.2, 2026-08-09 — **build-evidence amendment folded** (Karl's approval, 2026-08-09). Three corrections the implementers *proved by execution*, mapped in §0.2: the phase ladder is a **reached** rung and not a plain maximum (refuted by this document's own WP1 fixture arithmetic); §6.5's planted-secret recipe gains a required **carrier plant** (without it WP2's Mutation B is vacuous, measured); and the boundary lints' CORE set gains `scripts/host-drivers/*.sh` (a planted `core → module` source line passed both lints) — plus **A-BF-4**, the front-matter correction those three forced: the "Status of the thing described" row below no longer says "Nothing is built". No settled decision, decision table, or WP boundary changed. · v1.1, 2026-08-02 — **review-r1 folded** (`major_concerns`, fidelity verdict **FAITHFUL**: all six settled decisions carried correctly, the chooser verbatim at all three sites, and the §8.8 Adoption Record contract held against 13 reader-pipeline probes). **Two "exists today" claims were REFUTED by execution** — both re-verified by this author rather than accepted, both recorded at §0.2 and rewritten in place. No settled decision, decision table, or WP boundary changed; one WP regression proof and one WP mutation target were **re-aimed**, because each was provably incapable of going RED. |
| **Classification** | Product architecture — normative-once-reviewed for the build |
| **Audience** | (a) the adversarial design reviewer this document must survive; (b) the implementer of the work packages in §10 |
| **Subject** | **Brownfield adoption** — bringing an existing codebase, with existing history, existing CI, and existing tooling, into Solo Orchestrator |
| **Companion documents** | SOI-002-BUILD (`docs/builders-guide.md`) · SOI-003-GOV (`docs/governance-framework.md`) · SOI-004-INTAKE (`templates/project-intake.md`) · `docs/designs/2026-08-02-team-orchestrator-v1.md` (sibling fork design, same session) · the **delta track** design (in flight — see §0.3-C1) |
| **Status of the thing described** | **HALF BUILT. `## BL-242:` OWNS THIS — go there, do not read the summary that used to live here.** **Shipped:** the severable-module contract and `scripts/lint-module-dependencies.sh` (WP0, PR #325); **Scout** (WP1 #329, WP2 #331); the in-core enabling arms (WP3, #335); the **adoption driver** `scripts/adopt-project.sh` + `scripts/lib/adopt/` (WP4, #337); the user-facing pages `docs/scout.md` and `docs/adoption.md` (WP8, #343); the test-debt ledger (WP5b, #344); the collision archive (WP6, #345). **Not shipped:** WP5 and WP7. **Everything else that used to be restated here — which capabilities are unbuilt and which announce themselves, who owns them, the decisions D1-D8, and every open question — lives on `## BL-242:` and is NOT duplicated.** *(This cell stood at 5,592 characters immediately before the collapse, which cut it to 1,652 — stripped cell text at the pre-collapse revision and at the collapse commit respectively, both measured with `git show <rev>:docs/designs/2026-08-02-brownfield-adoption-v1.md`. **Both numbers are PINNED TO REVISIONS deliberately.** An earlier draft said "is now 1,652" of the LIVE cell, and that was the size of the text the draft was replacing — measuring what you are deleting and calling it what you wrote is how a self-referential number goes stale the instant it is written. It did, and review caught it. The 5,681 a draft before that one claimed was the whole row LINE in bytes, not the cell. This cell restated that analysis. Six consecutive review rounds found stale twins in it: a claim corrected on `## BL-242:` and left standing here, including one where the correction and the claim it corrected sat ~900 characters apart INSIDE THIS CELL. Each round's fix produced the next round's mismatch. The cause was duplication, not carelessness, so the duplication is gone: one assertion, one home, everything else a pointer — the same rule this document already applies to counts.)* **Scope of the caveat that follows, unchanged in force:** every "exists today" claim below is stamped **2026-08-02** and describes the **greenfield** product as it stood then. Those claims are *not* descriptions of the WP0-WP8 code, which post-dates every one of them — §13 is a log of what commands returned at that commit, not a standing property. Re-run a claim before quoting it. |

**Provenance.** Six architecture decisions were settled by Karl in a joint working session on
**2026-08-02**. This document **transcribes** them and designs *within* them; it does not
relitigate them. §0.1 attributes each decision to that session. Implementation freedom inside a
settled decision is the author's and is labelled **author-proposed** wherever it appears — a
reviewer may attack an author-proposed mechanism freely, and may not treat a settled decision as
open.

**Structural model.** `docs/designs/2026-07-24-operating-model-v1.md` is the house exemplar and
`docs/designs/2026-08-02-team-orchestrator-v1.md` its most recent application. This document
copies their discipline: a §0 traceability block, decision tables with one recommendation and
stated rejected alternatives, honest mechanical/auditable/advisory tiering, and — above all —
**every "exists today" claim carries a verification anchor**. Per the house citation rule, anchors
are **grep-able marker comments** (`# BL-NNN-…`) or **function names**, never bare `file:line`.

**A note on method, and on how it failed at v1.0.** The team-orchestrator review refuted four
"exists today" claims, two of them by that document's own printed recipes. This document quoted that
lesson in its own preamble and then **repeated it twice**: v1.0's every claim was executed before it
was written, and two of them were still refuted at review — not because a command was skipped, but
because a **narrow grep was allowed to carry a wide inference** (R-BF-1: "no direct redirect in this
file" became "no writer anywhere"; R-BF-2: "the flag is missing" became "values are printed"). Both
refutations were re-executed by this author before folding, per the house standard that a reviewer's
refutation is itself a claim. §13 is the appendix of commands actually run, with their actual output;
§0.2 records what was refuted. Where an execution refuted a premise this design was handed —
including two of Karl's own cited mechanisms — the refutation is in §0.3, not quietly designed
around. **Read §13 as a set of measurements with dates, not as certification.**

---

## Plain-English overview — read this first (about three minutes)

Solo Orchestrator is a system that lets one person, working with AI assistants, build and ship
production software with the paperwork and safety checks a real IT department expects. It writes a
small set of record files into the project — what stage the project is at, what has been approved
and by whom, who skipped which safety check and why — and installs automatic gates that refuse a
commit when the rules are not met.

Today it only knows how to do that for a project that does not exist yet. You point it at an empty
folder and it builds the scaffolding from nothing. **If you already have a codebase — a real
application with three years of history, its own build pipeline, its own habits — there is no
supported way in.** The framework does not refuse you; it is worse than that. It writes over
things. It replaces your `CHANGELOG.md` with an empty template. It replaces your commit-time
safety hook with its own. It deletes a backup folder on the reasoning that the folder cannot
contain anything of yours — reasoning that is true for a new project and false for yours. Every
one of those behaviours is correct for an empty folder and destructive for a real one.

**This design adds a second way in.** It has three moving parts.

**First, a look-but-don't-touch survey.** Before anything is written, a read-only tool reads your
codebase and reports what it found: what it is built in, how far along it looks, whether it has
tests and whether they pass, whether any passwords or keys are sitting in the project's history,
and exactly which of your files the framework would otherwise trample. It changes nothing. You can
run it, read it, and walk away. It is packaged as its own small tool with its own name and its own
one-line invocation, so that "let me see what this would say about my project" costs you nothing
and commits you to nothing.

**Second, one question that decides everything after it.** In Karl's words: *"Is the project built
out and needs to be able to be supported (i.e. bug fixes, maintenance, new features add), or are
you still in the process of building your project?"* A finished, running application is adopted at
the end state and goes straight into ongoing maintenance. A half-built one is placed at whatever
stage its own evidence supports, its existing work is written up honestly as a record of what was
already done, and the plan for what remains is written **fresh and real** — a genuine list of what
must be true to ship, with nothing waved through from that point on.

**Third — and this is the part that makes the whole thing honest — a certification pass.** The
obvious way to adopt an existing project is "grandfathering": stamp it as compliant and skip the
checks it never went through. The framework already does exactly that in one place today, and its
own comment says so out loud: a project created before a certain feature "lacks the field
entirely — the gate reads its absence as *grandfathered*", so it "is never retroactively blocked."
That is a promise nobody checked. **Adoption instead runs the skipped checks for real, today.**
The documents get written and the security scanners actually execute against your actual code. The
reviews are genuinely held and genuinely signed, dated today. Only the handful of things that are
*impossible* to re-run — you cannot go back and write the tests first for code written in 2023 —
are marked as historical, and each of those gets a forward-looking replacement instead: a written
list of what is untested, which is allowed to shrink and not to grow.

**And the certification can fail.** If the scanners find something serious, adoption does not
complete until it is fixed or somebody signs their name to accepting it. Smaller findings become
the first items on your work queue. An adoption that cannot fail would be a rubber stamp, and a
rubber stamp is the one thing this framework cannot afford to ship.

Two more things worth knowing. Any secrets found in your project's history are reported **without
ever printing the secret itself** — you get the rule that matched, the file, the commit, and a
fingerprint, and you must record what you did about each one. And where your own AI tooling
collides with the framework's, your version is **moved aside into a dated folder with a written
inventory and instructions for putting it back**, never silently deleted. Your build pipeline is
the deliberate exception: it is inspected and reported on, never touched, because breaking your
deploys on day one would be an unforgivable way to say hello.

---

## §0 — Decision traceability

### §0.1 — Settled decisions carried into this design

These six were settled **by Karl in the joint working session of 2026-08-02**. This document
designs **within** them. Each row names where the design work lives and what remains
author-proposed.

| # | Settled decision (Karl, 2026-08-02) | Designed in | Author-proposed inside it |
|---|---|---|---|
| **D1** | **Shape — Option C.** The read-only **scanner** lives in the Solo repo but is packaged and experienced as a **standalone one-command tool**: its own lib, zero dependency on the installer, a one-line bootstrap invocation, its own documentation page and its own name. The **write half's enabling arms live in-core by necessity** — the `adopted` flag, the gate arms that honour it, and stamp acceptance — because an external kit could only *fake* history, and the framework's own re-stamp/repair paths would erase an externally-written marker. The adoption **driver** and the **scanner** are **severable downstream modules**, held to the same module-shape and dependency-direction-lint discipline as the delta track, so either can be spun off later if demand warrants. | §3 | Tool name, lib layout, the module-shape contract and the dependency-direction lint's predicate (§3.3) |
| **D2** | **Two first-class scenarios**, chosen by one question in Karl's exact non-developer wording: *"Is the project built out and needs to be able to be supported (i.e. bug fixes, maintenance, new features add), or are you still in the process of building your project?"* The scanner **offers evidence** for the answer (deployment, users, release tags) but does not decide it. **S1 COMPLETED** lands at `current_phase` 4 + adopted, straight into the delta/maintenance era; its interview is light on futures and heavy on operations plus the load-bearing data-classification question. **S2 IN-FLIGHT** is placed at the phase its artifacts support; docs for what **exists** are reconstructed and provenance-marked, and the plan for what is **coming** is authored **fresh and real** — genuine cutline and success criteria, development continuing through the normal phase machine with nothing grandfathered going forward. S2 reaches the delta era by shipping v1. | §4 | Evidence set and its confidence tiers; the S2 phase-placement predicate (§4.3) |
| **D3** | **The certification pass** — Karl's upgrade over bare grandfathering. Adoption **runs every skipped gate's requirements for real**, dated today, labelled *certified-at-adoption*, in three kinds: **(a)** honestly producible now — docs generated plus interview, scanners/tests/evals **executed fresh** (real evidence, nothing marked); **(b)** the gate **reviews themselves** — held now, signed now, same checklist, track-aware depth exactly as the gates already are, so the record is a **real** review with today's date and only the *ordering* fact (after-the-code) is marked; **(c)** inherently historical — TDD ordering on pre-adoption code, approver-versus-author on historical commits — impossible to re-run, so these keep `adopted-at` markers plus **forward equivalents**, including a test-debt ledger with a tier-floor ratchet (the untested set may not grow at strict; touched files must gain tests), fully enforced from adoption day. **Certification can fail**: severity-triaged, blocker-grade findings **block adoption completion** until fixed or explicitly accepted with recorded sign-off; lesser findings seed the opening work queue. | §5 | The per-gate mapping table; the ratchet's exact predicate; the report-and-triage format |
| **D4** | **Secrets.** Full-history `gitleaks` at adoption. Findings **redacted in every artifact** — rule id, path, commit, fingerprint, never the value — with a planted-secret test asserting it. **Per-finding disposition required**: *rotated* / *false alarm* / *accepted risk*, each recorded. **BLOCK at strict**, **BIG WARNING at personal** (Karl's words — make it genuinely loud). History rewrite is offered as **printed instructions, never executed**. | §6 | The redaction projection (which fields survive), the disposition file's shape, the wording of the loud warning |
| **D5** | **Collision policy.** The framework's premise is opinionated SDLC enforcement. Their **AI-layer surfaces** (Claude hooks, skills, MCP connections, AI settings) **and their git hooks**: inventory → **archive** to a timestamped archive directory **with a MANIFEST** → install the framework's clean set → **plain disclosure** ("moved to ensure the framework operates properly" plus the list plus restore instructions) → **re-adds permitted** with Karl's warning near-verbatim (*"personal systems may conflict with the framework — accuracy, documentation, and capabilities may be compromised"*), every re-add recorded in the audit trail; archived git hooks get a what-it-did description in the report. **CI CARVE-OUT (Karl's, accepted):** their pipelines are **audited, not archived** — framework CI installs as its **own files**; SDLC-undermining workflows (auto-merge, deploy-around-the-release-lane, force-push) get **loud findings**; keep-or-retire is the user's **recorded decision**, because their deploys must not be broken on day one. **Project files** (README, CHANGELOG, their docs): keep theirs; framework artifacts adapt. | §7 | Archive directory layout and MANIFEST schema; the hook-description generator; the SDLC-undermining detector's rule set |
| **D6** | **Mechanics**, carried as settled from the verified analysis: a **new `scripts/adopt-project.sh` driver — not an `init.sh` mode**, because init's interactive path is the verified destructive path. Scanner report sections: **stack / phaseMap / reality / tests-baseline / secrets / collisions / intake-prefill**, built by **reuse-by-extraction** of `validate.sh`'s artifact-phase inference and `process-checklist.sh --verify-init`'s reality probes. **Reverse intake**: scan-derivable sections prefilled and confirmed on the `# BL-204-PREFILL-READ` pattern, judgment sections human-mandatory, data classification non-skippable. **Fail-safe state-creation order: phase-state → intake → manifest**, because the tier predicate fails *bypassable* on a missing phase-state and *strict* on a missing manifest. **Explicit-path staging, never `git add -A`.** An **adoption stamp** (`soif_adoption_stamp`, sited beside `soif_currency_stamp`, one call site) plus **provenance headers on every reconstructed doc**. Detection baselines reset through the existing `reconfigure-project.sh --reset-detection-baseline`. The **Adoption Record** section in `APPROVAL_LOG.md` must be **structurally unparseable as a gate approval**. | §8 | The report's JSON schema; the extraction boundary; the stamp's key set; the Adoption Record's exact shape |

### §0.2 — Amendment changelog

**v1.2.2 (2026-08-25) — the status row handed to `## BL-242:`, and this
document's first amendment that changes settled things.**

**IT DOES CHANGE SETTLED THINGS, and every earlier amendment's formula ("no
settled decision, decision table, or WP boundary changed") would be false here.**
`## BL-242:`'s D1 and D3 contradict settled text this document leaves standing —
§7.5's create-when-absent / notice-only rule, and WP6's scope. D2 may be a third,
depending on an axis question that is open; `## BL-242:` D2 carries the
derivation and the consequence for the count. **The enumeration lives there and
is not repeated here.**

**WHY THE STATUS ROW SHRANK BY 4,000 CHARACTERS.** It restated `## BL-242:`'s
analysis — which capabilities are unbuilt, which announce themselves, who owns
them, what is open. Six consecutive adversarial review rounds found stale twins
in it: a claim corrected on `## BL-242:` and left standing here. Round six found
one where the correction and the claim it corrected sat about 900 characters
apart **inside the same table cell**, and where the surviving half was one of the
four errors that blocked the filing's first draft.

The pattern was that each round's fix produced the next round's mismatch, so the
cause was duplication rather than carelessness, and patching could not converge.
**One assertion, one home, everything else a pointer** — the rule this document
already applies to counts, now applied to prose. The correction history is kept
on `## BL-242:` rather than mirrored here, for the same reason.

Prior corrections to this row, retained as the record of why it is now a pointer:
"Nothing is built" (true through v1.1) → WP0-WP3 (v1.2) → WP0-WP4 (v1.2.1) →
WP0-WP4/WP5b/WP6/WP8 (v1.2.2). Three wrong revisions of one hand-maintained row.
*(v1.2.1's own bullet below also calls itself "the third time this row has needed
correcting", and both cannot be third: by this chain v1.2.1 was the SECOND and
v1.2.2 is the third. The v1.2.1 wording is left as written and reconciled here
rather than silently edited — an earlier revision carried this same note and the
collapse deleted it while both "thirds" survived, which is the deletion form of
the very defect the collapse was for.)*

**v1.2.1 (2026-08-10) — one front-matter correction, from the WP8 documentation pass.** No settled
decision, decision table, or WP boundary changes.

- **A-BF-5 (FRONT MATTER, AGAIN) → Document Control, "Status of the thing described"** — that row
  said **"WP0–WP3 have shipped; WP4–WP8 have not"** and listed the driver, `scripts/lib/adopt/`,
  the chooser and the reverse intake under *Not built*. **WP4 merged as PR #337**, so all four
  exist and were exercised end-to-end for the WP8 docs (both scenarios, the floor rule, the
  non-skippable data-classification refusal, the halt-writes-nothing property, the stamp, and the
  bounded TDD exemption). The row is corrected, the not-built set is restated as **WP5, WP5b, WP6
  and WP7**, and the deferred commit-time hook is named as a decision rather than a gap. This is
  the third time this row has needed correcting, which is the argument for the rule A-BF-4 already
  recorded: **a status row is a measurement with a date, and it goes stale on the next merge.**

**v1.2 (2026-08-09) — build-evidence amendment. Approved by Karl, 2026-08-09.** Three substantive
corrections, each **proved by execution during the build** and none of them a matter of preference:
two of them name a place where this document specified something its own fixture arithmetic could
not deliver, and the third names a coverage hole a reviewer closed by planting a violation and
watching the lint pass it. A fourth row (A-BF-4) records the front-matter correction those three
forced. No settled decision, decision table, or WP boundary changes. Amendment rows are prefixed
`A-` to distinguish them from the review findings above, which are `R-`.

- **A-BF-1 (LADDER) → §4.4 correction 2 / §8.2 / §10-WP1** — "take the **maximum** satisfied rung"
  is **refuted by this document's own WP1 fixture**. That fixture's satisfied set is {1, 2, 4}, so
  plain-max returns **4** — the exact value WP1's mutation watches for as the *failing* result. The
  required output of **2** was unreachable and the mutation could never have gone RED against a
  spec-faithful build. Corrected to the **highest *reached* rung** (a contiguous climb that stops at
  the first gap), which is also the only reading coherent with §4.4's own certification-scope rule:
  landing at phase N certifies every gate *below* N, and that is a prefix property. §8.2 gains the
  additive **`highestSatisfiedRung`** transparency field, which publishes the plain max beside the
  reached rung so the gap between them — the finding — is not thrown away; the emitted `note` string
  is kept **verbatim** and its resulting two-number wart is disclosed rather than silently reworded.
- **A-BF-2 (CARRIER PLANT) → §6.5 / §10-WP2** — the planted-secret recipe was incomplete in the one
  way that makes **WP2's Mutation B vacuous**. Measured during the build and independently
  re-verified by review: a finding's `Message` field carries the message of **the commit that
  produced that finding**, so a BASE32-valid key planted in the message of a *clean* commit scores
  **zero** findings even under a full report passthrough — Mutation B would have gone green against
  a correct implementation and a broken one alike. §6.5 now requires a **third "carrier" plant** in
  the diff of the message plant's own commit, so that commit produces a finding and its message
  actually reaches the report. Verified on gitleaks 8.30.1: redacted report → diff plant ×0, carrier
  ×0, message plant ×1 in `Message`. The two existing fixture facts (BASE32-validity, the non-zero
  finding-count precondition) are unchanged and the carrier joins them as a third precondition.
- **A-BF-3 (CORE GLOBS) → §3.3 / `docs/module-contract.md` M3** — M3's "no file **outside** the
  module directory" is rendered by both boundary lints as a four-glob CORE set that **excludes
  `scripts/host-drivers/*.sh`**. Proof by plant, not inference: a reviewer added
  `source …/scout-phasemap.sh` to `scripts/host-drivers/gitlab.sh` and
  `source …/delta-state.sh` to `scripts/host-drivers/github.sh`, and **both lints passed at rc=0**,
  while the identical lines in four-glob-covered core files red at rc=1. Karl approved extending
  coverage; the CORE set is now **five globs** here, in the delta design's §3.3, and in
  `docs/module-contract.md`. **The lint edit shipped separately and has now landed
  (`## BL-215:`)** — both `CORE_GLOBS` arrays carry the fifth glob under the sync-sibling marker
  `# BL-215-CORE-GLOB-SYNC`, so this document is no longer ahead of the code by that one glob.

- **A-BF-4 (FRONT MATTER) → Document Control, "Status of the thing described"** — that row read
  **"Nothing is built."** through v1.1. True when written; false by 2026-08-09, because WP0–WP3 have
  shipped (PRs #325, #329, #331, #335) and **all three corrections above are derived from that
  shipped code**. A design document whose front matter contradicts its own amendment log misleads
  the next reader on first contact, so the row is **corrected in this same v1.2 pass**: it now names
  what is built, what is not, and the PRs for each, and it rescopes — without weakening — the caveat
  that every "exists today" claim below is stamped 2026-08-02 and does **not** describe the shipped
  WP code. **Recorded because the drafting of it is the lesson:** an earlier draft of this changelog
  said the row was "left as stamped; correcting it is not part of this amendment", and the branch's
  own final commit falsified that sentence — a fresh self-contradiction introduced into the document
  whose amendments exist to remove exactly that class. Caught by adversarial review (R-PRE-2), not
  by the author.

**v1.1 (2026-08-02) — review-r1 amendment map.** Verdict `major_concerns`; fidelity **FAITHFUL**.
**Two refutations, both re-verified by this author before folding** (house standard: a reviewer's
refutation is a claim until executed). Corrections are rewritten on top, not accreted. The pattern
in both refutations is the same and worth naming: **a narrow grep proved a narrow thing and the
document printed a wide inference from it.** That is the identical failure the team-orchestrator
review found, in a document that had quoted that lesson in its own preamble.

- **R-BF-1 (REFUTED) → C2 / §8.5 / §10-WP3 / §12-12 / §13-V5** — "`verify-install.sh` has 21 `fix_*`
  and **none writes `.claude/manifest.json`**" was a **false inference from a true grep**. The 21
  count holds and no *direct* redirect exists in that file — but `fix_framework_manifest()`
  delegates to `~/.claude-dev-framework/scripts/init.sh`, which writes the manifest **wholesale**
  (`jq -n '{…}' > .claude/manifest.json`, hardcoded key set carrying **no** Solo keys — no
  `deployment`, no `enforcement_level`, no `currency`, no `adoption`). **Re-verified here**: the CDF
  writer read directly, and the registration confirmed as the `elif` arm of a bare
  `[ -f ".claude/manifest.json" ]` check. **The manifest therefore has the same
  regenerate-on-missing erasure class as `phase-state.json`, and the v1.0 rationale was wrong.**
  The **home decision survives on corrected grounds** — the same move C2 already makes for Karl's
  own cited mechanism: the distinguishing property is not *who has a fixer* but **merge versus
  re-stamp on an existing file**. Both regenerators are **missing-file-gated** (the stamp is already
  gone with the file), whereas `phase-state.json` is re-stamped **on every upgrade** against a file
  that exists. C2's consequence cell, §8.5's Home rationale, §12's assumption 12 and WP3's proof are
  all rewritten.
- **R-BF-2 (REFUTED) → C8 / §6.1 / §12-2 / §13-V15** — "the emitted local pre-commit hook prints
  secret values in the clear" was **false**. The missing-`--redact` half is true; the consequence is
  not. **Re-verified here** on gitleaks 8.30.1: `gitleaks git --staged` without `-v` writes
  **nothing to stdout** and only `WRN leaks found: 1` to stderr — **zero** occurrences of the
  planted value in either stream — and the hook discards stderr (`2>/dev/null`) anyway. The value
  appears on stdout **only** with `-v` (2 occurrences). **The honest residual is the inverse of what
  v1.0 claimed:** the operator is told secrets exist and shown **no** rule, file, or line. All three
  sites rewritten; the v1.0 follow-up invitation is deleted rather than softened.
- **R-BF-3 (ride-along) → C1 / §13-V8** — C1's delta-track findings are annotated as
  **time-of-execution facts, superseded before this document's own commit**: the branch gained
  `5dcbe86` and `6fc3136` (a v1.1 of its own), +1195 lines including a `docs/INDEX.md` row.
  **A `docs/INDEX.md` conflict between the two branches is therefore guaranteed** and is the
  supervisor's to resolve at merge — both rows belong.
- **R-BF-4 (ride-along) → §6.5 / §10-WP2 / §13-V3** — the fixture note was insufficient. The
  `aws-access-token` rule requires the 16 characters after `AKIA` to be **BASE32-valid
  (`[A-Z2-7]{16}`)**. **Re-verified here:** a key containing `9` yields **zero** findings in a diff
  — so a plant chosen carelessly makes WP2's Mutation A **vacuous** (it can never go RED). v1.0's
  own C7 message-plant contained a `9`; **C7 has been re-executed with both plants BASE32-valid and
  the finding is unchanged and now unimpeachable** (§13-V3).
- **R-BF-5 (ride-along) → §10-WP7** — WP7's mutation could not fire. **Re-verified here:** against a
  clause-1-compliant record, no evidence window ever opens, so un-indenting the Date row yields
  `rc=1` either way. The mutation is re-aimed at the **record lint**, with the joint-violation
  fixture kept as an explicit defense-in-depth proof.
- **R-BF-6 (ride-along) → §10-WP4** — WP4 gains a required **section→prefill mapping table**. The
  wizard has **15** `run_section_*` runners (measured); "scan-derived versus judgment" must be
  pinned per section, not asserted as a principle.
- **R-BF-7 (ride-along) → §7.2** — the MANIFEST recipe overstated: `grep -n 'MANIFEST'` over
  `upgrade-project.sh` returns **18** hits, nearly all `MANIFEST_JSON` and `PRODUCT_MANIFESTO`.
  Recipe and sentence both tightened.

**v1.0 (2026-08-02)** — pre-review draft.

### §0.3 — Verification posture, and where the repository corrected the brief

Every claim marked *verified* was **executed** against this tree on **2026-08-02**; §13 prints the
commands and their output. Ten findings materially correct the framing this work was handed to me
in. **None of them invalidates a settled decision.** Two of them correct mechanisms Karl cited by
name — the correction strengthens his conclusion in both cases, by a different and better route.

| # | Correction | Consequence |
|---|---|---|
| **C1** | **The dependency-direction lint this design is told to align with does not exist.** `ls scripts/lint-*.sh` returns **14** lints, none of which checks module dependency direction; `grep -rni 'dependency.direction\|severable\|module-shape'` over `*.md` and `*.sh` returns **nothing**. **⚠ TIME-OF-EXECUTION, SUPERSEDED (R-BF-3).** At the moment this was executed the delta-track branch had **zero commits** and its head equalled `main`'s (`6449838`). **That is no longer true and was already false when this document was committed** — the branch has since landed `5dcbe86` and `6fc3136` (its own v1.1), +1195 lines, `docs/designs/2026-08-02-delta-track-v1.md` plus a `docs/INDEX.md` row. Re-run V8; do not quote it. | §3.3 still states the module-shape and dependency-direction contract as **author-proposed and co-owned with the delta track** — the lint's non-existence is the load-bearing half and it holds. What changes is the schedule argument: WP0's convergence partner now has a document to converge *with*, so WP0 is no longer blocked on an empty branch (§12-8 revised). **A `docs/INDEX.md` merge conflict between the two branches is guaranteed** — both add a Designs row to the same paragraph — and is the supervisor's to resolve; **both rows belong, neither supersedes the other.** |
| **C2** | **Karl's cited mechanism for "upgrade re-stamps kill external markers" is REFUTED as stated — and the decision survives by two stronger mechanisms.** `scripts/upgrade-project.sh`'s `# 2. Update .claude/phase-state.json` block is a read-modify-write **merge** (`json.load` → assign → `json.dump`), so a foreign key **survives** an upgrade (executed: a `adopted_by_external_tool: true` key passes through untouched). What is true, and is the real argument: (i) the block re-asserts `data["review_gate_enforced"] = True` **unconditionally on every upgrade**, so an external kit cannot durably express an enforcement posture through any framework-owned key; and (ii) `fix_phase_state()` in `scripts/verify-install.sh` is a **wholesale `cat > .claude/phase-state.json` heredoc** whose hardcoded key set omits `review_gate_enforced` entirely **and resets `current_phase` to 0** — it fires when the state file is missing, and `upgrade-project.sh` invokes `verify-install.sh` post-upgrade. | D1's conclusion stands and is better argued (§3.2). It also **decides an implementation question**: the adoption stamp must **not** live in `phase-state.json`. **⚠ v1.1 — the v1.0 rationale for that was REFUTED (R-BF-1) and is replaced.** v1.0 argued the manifest is safe because `verify-install.sh` has 21 `fix_*` functions and none writes it. The count and the direct-redirect grep both hold, **and the inference did not**: `fix_framework_manifest()` delegates to `~/.claude-dev-framework/scripts/init.sh`, which writes the manifest **wholesale** (`jq -n '{ frameworkVersion, frameworkCommit, frameworkRepo, localClonePath, lastSyncDate, profile, profileInherits, files, activeRules, activeHooks, projectConfig, discovery }' > .claude/manifest.json`) — **no Solo key survives it**. The manifest has the **same regenerate-on-missing erasure class** as phase-state. **The home decision survives on the corrected ground, which is stronger:** both regenerators fire only on a **missing** file (bare `[ -f ]` guards — by then the stamp is gone with the file, and no writer *destroyed* it), whereas `phase-state.json` is **re-stamped on every upgrade against a file that exists**. Every writer that touches an **existing** manifest is an additive merge (§8.5). |
| **C3** | **`reconfigure-project.sh --reset-detection-baseline` exists, but ships with NO migration wording.** The flag is real (`RECONF_RESET_BASELINE`, block comment `# BL-030 Task 8: --reset-detection-baseline.`) and its user-facing strings are exactly `Detection baseline reset to current HEAD.` and the commit subject `chore: reset detection baseline (reconfigure)`. `grep -rni 'migrat' scripts/reconfigure-project.sh` returns **one internal comment**, unrelated. The "migration" sentence Karl cited lives in the **archived design spec** `docs/superpowers/specs/archive/2026-04-28-bl030-enforcement-model-design.md` § 10.4. | §8.7 attributes the sentence to the archived spec, not the tool — and **that spec is this design's strongest prior art**, because it names brownfield adoption twice: *"For use after rebases, branch resets, or migration into the framework on existing repos with prior unrecorded history"*, and *"This is critical for projects adopting the framework into an existing repo."* The mechanism it describes is shipped and verified (`init.sh` writes `git rev-parse HEAD` to `.claude/last-checked-commit.txt` at two sites). |
| **C4** | **The fail-direction asymmetry is real, and is a per-surface fact, not a global one.** Verified by execution: `check-phase-gate.sh` with no `phase-state.json` prints `No .claude/phase-state.json found — skipping phase gate check.` and exits **0** (fails OPEN); `read_enforcement_level` with no `manifest.json` — or a corrupt one — returns **`strict`**, `assert_choosable` returns **1**, and `validate_transition` permits only `strict` (fails CLOSED). **But** in `check-phase-gate.sh` itself the missing-manifest arm of the Phase 1→2 protection backstop is a **`[WARN]` with no `issues` increment** — i.e. deleting the manifest is *less* blocking there than having one with a bad `host`. | D6's ordering (phase-state → intake → manifest) is **confirmed and correct** (§8.4), and the honest statement of *why* is per-surface, not "the tier predicate fails strict on a missing manifest" flatly. §8.4 prints the two-cell table. |
| **C5** | **`init.sh` does not "refuse existing directories" — the tree's only written statement of the brownfield gap is factually wrong.** `## F-010: Brownfield onboarding gap — still unfiled` in `solo-orchestrator-followups.md` asserts *"`init.sh` refuses existing directories, so the framework cannot onboard an existing codebase."* Executed: `--allow-existing-dir` is a documented first-class flag (`bash init.sh --help-non-interactive` prints it), and the **interactive path has no existence check at all** — the refusal lives only in `collect_inputs_non_interactive()`. | §1 restates the problem correctly: the blocker is not refusal, it is that **once init proceeds it overwrites unconditionally** (§1.2's twelve-row collision table). This matters — a design premised on "we must remove a refusal" would build the wrong thing. F-010 is also the reason this design exists; it is cited, corrected, and left unedited (no backlog or followup edits are in scope). |
| **C6** | **There is no third tracker in `CLAUDE.md`'s map.** `CLAUDE.md` § ISSUE TRACKING describes **two** files and two grammars; the tree has **three** — `solo-orchestrator-backlog.md` (`BL-`), `solo-orchestrator-bugs.md` (`BUG-`), and `solo-orchestrator-followups.md` (`F-`), the last holding this design's only prior art. | Recorded so a reviewer looking for prior art in the two documented trackers does not conclude there is none. `grep -ci brownfield solo-orchestrator-backlog.md` → **0**. Fixing `CLAUDE.md` is out of scope here (docs-only branch, no tracker edits). |
| **C7** | **`gitleaks --redact` does not redact the whole report.** Executed against a planted key: without `--redact` the value appears **twice** in the JSON report (`Secret`, `Match`); with `--redact` it appears **zero** times. **But** the report's 18 fields include `Message` — the full commit message, **not redacted** — and a second key planted in a commit message survives `--redact` intact (**1 occurrence** in the "redacted" report). **v1.1 (R-BF-4): re-executed with BOTH plants BASE32-valid.** v1.0's message plant contained a `9` and so was not a string gitleaks would ever flag, which a reviewer could fairly have called a weak demonstration. Re-run with two rule-valid keys, the result is **identical** — diff plant 0 occurrences, message plant **1** — so the finding no longer depends on the plant's shape at all. | D4's redaction requirement cannot be met by passing `--redact`. §6.2 specifies a **field allowlist projection** instead, and §6.5 requires the planted-secret test to plant in **both** a diff and a commit message, **both BASE32-valid**. This is the single most likely place a naive implementation would ship a leak while believing it had not. |
| **C8** | **The framework already ships gitleaks — three different ways, two of which are weaker than this design needs.** Emitted **GitHub** CI runs `./gitleaks git --redact --exit-code 1` on `fetch-depth: 0` (**full history**, BL-151 comment block); emitted **GitLab** and **Bitbucket** CI run `gitleaks dir . --verbose --redact` (**working tree only, no history**); the emitted **local pre-commit hook** runs `gitleaks git --staged` (**index only**). Phase 3 has **no** secret scanner at all: `P3_SCANNERS="semgrep-full-tree license snyk zap-dast threat-model"`. **⚠ v1.1 — v1.0's added claim that the hook "prints secret values in the clear" was REFUTED (R-BF-2).** It omits `--redact`, which is true and sounds alarming, and the consequence does not follow: without `-v`, `gitleaks git --staged` writes **nothing to stdout** and only `WRN leaks found: N` to stderr (**zero** occurrences of the planted value in either stream), and the hook discards stderr with `2>/dev/null`. The value reaches stdout **only** under `-v`. | §6.1 states what adoption's full-history scan is genuinely new *for* (every non-GitHub host, and every project before its first CI run) and what it duplicates. **The real residual is the inverse of v1.0's:** the operator sees the framework's `[BLOCKED]` lines and **no finding detail whatsoever** — no rule, no file, no line (§12-2). Adding `-v` without `--redact` in the same edit is exactly how a fix here would create the leak v1.0 wrongly alleged. |
| **C9** | **`APPROVAL_LOG.md` has eight independent readers, four with unbounded windows — "structurally unparseable" is an eight-clause predicate, not a heading choice.** Readers verified: `_cpg_gate_has_evidence` (window opens on **any line** matching `Phase N.*Phase N+1`, not a heading), `validate_approval_fields` (H2-anchored section **plus** a permissive unbounded `grep -A 20` feeding the blame walker), `validate_approval_section_dated` (substring open, stops at any `^#`), `check_named_row` (**unbounded `grep -A 30 "Pre-Phase 0"`** — measured on the shipped org template as a 31-line window carrying **three** `## ` heading lines, i.e. it reads past its own section into the next two), two whole-file greps (pen-test exemption, retroactive STA), the `# BL-115-ATTORNEY-ENTRY` awk in `process-checklist.sh`, and `check_gate` in `scripts/validate.sh` (`grep -A 10` + `grep -i "date"` — matches `update`, `Candidate`). | §8.8 states the predicate as eight clauses and cites the **existing precedent**: the BL-170 append-design commit already wrote this invariant list for the templates' own instruction prose. The design follows it rather than inventing one. |
| **C10** | **No document in the tree restricts the framework to new projects.** `grep -ni 'new project\|from scratch\|greenfield\|empty director'` over `docs/user-guide.md`, `docs/builders-guide.md` and `README.md` returns only unrelated hits. The greenfield assumption is **implicit in code** and stated **once**, in F-010, where it is overstated (C5). The nearest thing to a scope statement is `guard_not_in_framework`'s error text — *"run init.sh from inside an empty project directory"* — and `docs/builders-guide.md` § "Retrofitting an existing project", which means `reconfigure-project.sh --field`, **not** codebase onboarding. | Two consequences. (i) This design cannot cite a doctrine statement saying the framework is greenfield-only — **there is none**, which strengthens the case that this is an unexamined default rather than a decision. (ii) The word **"retrofit" is already taken** by a narrower meaning; this document uses **"adoption"** throughout and never "retrofit" (§2). |

---

## §1 — Problem and evidence

### §1.1 — The four problems

House convention for evidence tiers: *verified current state* = executed against this tree on
2026-08-02; *doctrine* = written policy in a shipped document; *design rationale* = a recorded
decision, not a repo fact.

| # | Problem | Evidence (anchor) | Tier |
|---|---|---|---|
| 1 | **There is no supported way in for an existing codebase, and the one written statement of that gap is wrong.** The gap has been known since 2026-07-12 and was never filed. | `## F-010: Brownfield onboarding gap — still unfiled` in `solo-orchestrator-followups.md`; `grep -ci brownfield solo-orchestrator-backlog.md` → **0**. Its claim that init "refuses existing directories" is refuted at C5. | Verified current state |
| 2 | **The way in that does exist is destructive, silently, on twelve surfaces.** Nothing in `init.sh`'s write path is guarded on the target file's absence except the two git-hook writers that were deliberately built to compose. | §1.2's table; `create_project()`, `generate_ci()`, `generate_release()`, `generate_gitignore()`, `install_precommit_hook()` → `soif_write_precommit_hook()`. | Verified current state |
| 3 | **The framework's own grandfathering precedent is a promise nobody checks.** `init.sh` stamps `review_gate_enforced: true` at creation; the comment states that projects created earlier "lack the field entirely — the gate reads its absence as *grandfathered* and keeps the legacy WARN-only behavior, so a pre-existing project is never retroactively blocked." That is the exact posture D3 replaces. | The `# BL-073:` comment block above the `PHEOF` heredoc in `init.sh`; the reader `cpg_review_flag` / `# BL-073-ESCALATE` in `scripts/check-phase-gate.sh`; the `# BL-104-MANIFEST-ARM` empty-manifest arm. | Verified current state |
| 4 | **An adopted project's CI is red by construction on day zero.** The two workflow files the framework installs carry `Governance - Approval log integrity`, `Governance - Approval author verification`, `Governance - Phase gate check` and `Governance - Changelog check` steps, which read `APPROVAL_LOG.md`, `.claude/phase-state.json` and `CHANGELOG.md`. On an existing repo none of those exists until the adoption flow seeds them. | `templates/pipelines/ci/github/*.yml` (ten language variants, two jobs each: `test`, `sast`); `generate_ci()` / `generate_release()` in `init.sh`. | Verified current state |

**What does not exist today (verified).** No `adopted` flag, no adoption stamp, no scanner, no
driver: `grep -rn 'adopted' --include='*.sh' --include='*.tmpl' --include='*.json' .` returns
**five hits, all English prose in comments** ("adopted npm test", "taxonomy adopted from"). The
identifier namespace is free. There is no test-debt ledger, no untested-file baseline, and no
coverage ratchet anywhere in the tree; the nearest structural analogue is
`KNOWN_ORPHANS_PENDING_BL035` in `scripts/lint-tests-registered.sh` — an allowlist that is
required to shrink, with a self-emptying nag.

### §1.2 — The collision surface, measured

Every write below is in `init.sh` unless noted. **Behaviour on a pre-existing file** is read from
the write primitive (`cat >` / `cp` / `printf >` / `sed >` versus `>>` guarded by
`grep -qF "$MARK"`); the distinction is unambiguous at every site.

| Surface | Writer | On a pre-existing file |
|---|---|---|
| `.claude/settings.json` | `create_project()` | **OVERWRITE** (`cat > … PERMEOF`), then jq-merges its hook registrations into *its own* output |
| `.claude/settings.local.json` | `create_project()` (Qdrant arm) | **OVERWRITE** (`cat > … QDEOF`). The file is the conventional home for a developer's personal MCP roster and is **untracked** — so the loss is not recoverable from git |
| `.git/hooks/pre-commit` | `install_precommit_hook()` → `soif_write_precommit_hook()` | **OVERWRITE** (`printf … > "$hook"`), unguarded. Husky, lefthook, pre-commit-framework, hand-rolled — all destroyed |
| `.git/hooks/commit-msg` | `install_tdd_commit_msg_hook()` | **APPEND**, marker-guarded (`SOIF_TDD_OPEN`), idempotent ✅ |
| `.git/hooks/pre-commit` (strict tier) | `scripts/install-filesystem-gates.sh --install` | **APPEND**, marker-guarded (`SOIF_PRECOMMIT_OPEN`), with a matching `--uninstall` ✅ |
| `.git/hooks/*.sample` | `create_project()` | **DELETED** — `rm -f .git/hooks/*.sample`, comment: *"so framework doesn't misdetect as existing project"* |
| `.claude/skills/{session-handoff,sweep-triage,zoom-out,grill-with-docs}/SKILL.md` | `create_project()` | **OVERWRITE** (`cp`) — narrow, but a same-named skill is clobbered |
| `.github/workflows/ci.yml` | `generate_ci()` | **OVERWRITE** (`cp`). On GitLab/Bitbucket the destination is the project's *entire* pipeline file (`.gitlab-ci.yml`, `bitbucket-pipelines.yml`) |
| `.github/workflows/release.yml` | `generate_release()` | **OVERWRITE** (`sed … > "$target_file"`) |
| `.gitignore` | `generate_gitignore()` | **OVERWRITE** (`cp` of `gitignore-base.tmpl`), then `>>` appends — to the fresh copy, not to theirs |
| `FEATURES.md`, `CHANGELOG.md`, `BUGS.md`, `RELEASE_NOTES.md` | `create_project()` | **OVERWRITE** (`cp` from `templates/generated/*.tmpl`). A real project's changelog is replaced with an empty template |
| `.claude/phase-state.json` | `create_project()` | **OVERWRITE** (`cat > … PHEOF`) |
| `.claude-backup/` | `create_project()` | **`rm -rf`**, on a justification that is greenfield-only: *"Solo Orchestrator seeded `.claude/` moments earlier in this same init, so the backup contains no user work"* — false for an existing project, where the vendored framework's pre-merge backup of `.claude/` is the operator's own work |
| uncommitted working tree | `create_project()` | `git add -A` then `git commit -q --no-verify` — existing uncommitted work is swept into a `chore: initialize` commit **with verification bypassed** |

**Read the good rows, not just the bad ones.** Three writers already do the right thing:
`install_tdd_commit_msg_hook()` composes with a foreign `commit-msg` by marker-fenced append,
`install-filesystem-gates.sh --install` composes with a foreign `pre-commit` by the same technique
*and ships an `--uninstall`* — its header says *"Composes with existing chains"* — and
`_bl099_sync_precommit_hook()` in `scripts/upgrade-project.sh` refuses to touch an unmarked
(user-owned) hook at all, writing a `.new` sidecar and telling the operator to diff and adopt.
**The framework already knows how to meet a foreign file politely. `init.sh` simply does not do
it.** The counter-precedent is also explicit and worth inheriting: `# BL-099-DOC-GUARD` marks
`CLAUDE.md` and `PROJECT_INTAKE.md` **notice-only** — "no `.new`, no `.bak`, no template copy" —
under every flag and env combination.

### §1.3 — Contradictory prior art, dispositioned

Two concept papers push in different directions and both should be answered rather than discovered
at review.

- **`evaluation-prompts/v2-concepts/post-mvp-feature-development.md`** — the only other file in the
  tree using the word *brownfield*. Its Option B proposes "a standalone, lighter-weight tool
  specifically for adding features to existing projects… Skip all the governance, intake, and
  Phase 0-1 infrastructure", and asks whether "combining greenfield and brownfield workflows in one
  tool create[s] confusion". **Partially adopted, partially rejected.** D1 adopts its
  standalone-tool instinct for the *read-only* half (§3.1) and rejects "skip all the governance"
  outright — that is precisely the grandfathering D3 replaces. Its confusion worry is answered by
  D6's separate driver: `adopt-project.sh` is not a mode of `init.sh`.
- **`evaluation-prompts/eval-results/05-technical-user-review.md`** — an external reviewer:
  *"there is no way to adopt part of the framework. It is currently all-or-nothing… The
  all-or-nothing adoption model excludes partial adopters."* **Answered, not adopted.** The scanner
  *is* the partial-adoption surface: it delivers real value (stack, phase evidence, test baseline,
  secrets, collisions) with zero writes and zero commitment. The write half stays all-or-nothing on
  purpose, because a half-installed enforcement layer is the failure mode this framework exists to
  prevent.

---

## §2 — Product boundary

**Brownfield adoption is:** a second, first-class entry path into the *same* framework — the same
gates, the same scanners, the same tiers, the same audit trail — for a codebase that already
exists, with a certification pass in place of a grandfather clause.

**Brownfield adoption is not:**

- **Not a lighter framework.** After adoption completes, an adopted project is
  indistinguishable from a scaffolded one in what the gates demand of it. The only durable
  difference is a record of *how it got here*.
- **Not a code-quality remediation tool.** It measures debt (test baseline, scanner findings,
  secrets) and it refuses to let the measured set grow. It does not pay the debt down. The
  team-orchestrator design makes the identical disclaimer about graduation and it is equally true
  here.
- **Not a migration for projects generated by *other* frameworks.** Adoption assumes an ordinary
  git repository. A project carrying a competing enforcement layer is an ordinary repository plus a
  collision set, handled by §7 like any other.
- **Not "retrofit".** That word already means `reconfigure-project.sh --field <name>` in
  `docs/builders-guide.md` and in `check-phase-gate.sh`'s own remediation strings (C10). This
  document says **adoption**, everywhere.
- **Not a history rewriter.** Nothing in this design ever rewrites, force-pushes, or filter-branches
  the adoptee's history. §6.4 prints instructions; the operator runs them or does not.

---

## §3 — Shape (D1)

### §3.1 — Three parts, three different homes

| Part | What it is | Where it lives | Why there |
|---|---|---|---|
| **The scanner** (read-only) | Reads the codebase and emits one report. Writes **nothing** outside its own report path. | In the Solo repo, but **packaged as a standalone tool**: its own entry script, its own lib subtree, its own doc page, its own name, a one-line bootstrap invocation, and **zero dependency on the installer** | It must be runnable by someone who has not decided anything. A survey that requires installing the thing it is surveying is not a survey. Standalone packaging is what makes "let me just look" cost nothing |
| **The enabling arms** (write, tiny) | The `adopted` flag, the gate arms that read it, and stamp acceptance | **In-core**, in the existing gate scripts and libs | An external kit could only *fake* history. And the framework's own repair path erases foreign state: `fix_phase_state()` rewrites `phase-state.json` wholesale from a hardcoded key set. See §3.2 |
| **The driver** (write, large) | The interview, the certification pass, the archive, the state writes, the commit | A **severable downstream module** under the same module-shape and dependency-direction discipline as the delta track | It is where all the volume is and none of the enforcement. Keeping it severable preserves the option to spin it out without ever having to disentangle it later |

### §3.2 — Why the enabling arms cannot be external

The team-orchestrator design faced the mirror-image question and rejected a "thin kit" as a
capability desert. Here the argument is narrower and mechanical.

An external adoption kit would have to express, durably, that *this project was certified at
adoption and its pre-adoption commits are exempt from the ordering gate*. There are exactly two
places to put such a claim and both are hostile to an outsider:

1. **A framework-owned key.** `scripts/upgrade-project.sh`'s phase-state block re-asserts
   `data["review_gate_enforced"] = True` **unconditionally on every upgrade** — an external kit
   cannot durably hold the opposite value in any key the framework also writes.
2. **A key of its own.** This *does* survive a normal upgrade — the block is a `json.load` →
   assign → `json.dump` **merge**, executed and confirmed, so a foreign
   `adopted_by_external_tool: true` passes through untouched (C2 corrects Karl's cited mechanism
   here). But it survives only until the state file is lost once: `fix_phase_state()` in
   `scripts/verify-install.sh` is a wholesale `cat > .claude/phase-state.json` heredoc with a
   hardcoded key set that omits even the framework's **own** `review_gate_enforced`, and resets
   `current_phase` to **0**. `upgrade-project.sh` calls `verify-install.sh` after every upgrade.
   And a key nothing reads is not enforcement anyway — the gates would have to be taught to read
   it, which is the in-core change the kit was invented to avoid.

**A third hazard, added at v1.1 (R-BF-1), which applies to the framework's own stamp as much as to a
kit's key.** `fix_framework_manifest()` delegates to `~/.claude-dev-framework/scripts/init.sh`,
which writes `.claude/manifest.json` **wholesale** from a hardcoded key set carrying no Solo keys at
all. So **both** state files have a regenerate-on-missing writer, and neither location is
categorically safe. §8.5 states the property that actually distinguishes them.

**Verdict: settled, and the mechanism is now correctly stated.** The enabling arms are in-core.
They are also genuinely small — §10's WP3 is three arms and a stamp, against a driver (WP4–WP7)
that is most of the build.

### §3.3 — Module shape and dependency direction (author-proposed; co-owned with the delta track)

**Honest status first (C1).** The delta-track design has **zero commits** and no
dependency-direction lint exists among the fourteen `scripts/lint-*.sh`. What follows is therefore
a **proposed contract**, offered so the two tracks can converge on one, not a description of
something built.

| Rule | Statement | Enforced by (proposed) |
|---|---|---|
| **M1 — One directory per module** | A severable module owns `scripts/lib/<module>/` and exactly one entry script. No module code lives outside its directory. | A path lint; trivially checkable |
| **M2 — Declared dependencies** | Each module's entry script carries a fenced header listing the core libs it may source. Anything not listed is a violation. | The proposed dependency-direction lint |
| **M3 — Direction** | `module → core` is permitted. **`core → module` is forbidden**: no file outside `scripts/lib/<module>/` may source or invoke module code. This is the property that makes severance a `git mv`, not a refactor. | Same lint |
| **M4 — The enabling arms are core, and are named** | The in-core arms of §3.1 are *not* part of the module. They are listed by marker in the module's header so severance has an explicit, short interface to preserve. | Review + the marker lint (`scripts/lint-bl-markers.sh` already resolves marker citations both directions) |
| **M5 — The scanner depends on nothing** | The scanner sources **no** core lib. Its bootstrap must work in a clone that has never run `init.sh`. | The lint's zero-dependency arm, plus a hermetic test that runs the scanner with `scripts/lib/` moved aside |

**The CORE set M3 is checked over — five globs. v1.2 (2026-08-09), evidence-led, approved by Karl.**
M3 says "no file **outside** `scripts/lib/<module>/`", and both boundary lints render that universal
as a literal glob set: CORE = `init.sh` + `scripts/*.sh` + `scripts/lib/*.sh` + `scripts/hooks/*.sh`
+ **`scripts/host-drivers/*.sh`**, minus the module inventory, minus the lint itself, minus sibling
boundary lints. The fifth glob is the correction. The co-owned contract named **four**, both lints
were built faithful to that number at exact parity, and both disclose the exclusion in their own
headers as a design question pending this amendment. **The gap is proved by plant, not inferred:**
`source "$SCRIPT_DIR/lib/scout/scout-phasemap.sh"` appended to `scripts/host-drivers/gitlab.sh` in a
fixture tree leaves `scripts/lint-module-dependencies.sh` at **rc=0**
(`OK: no core -> module edge and no scanner dependency`, 76 core files scanned), and the delta
sibling passes its own equivalent plant identically. The **identical** line appended to
`scripts/check-maintenance.sh` — a file the four globs do reach — reds at **rc=1** on T2. The
predicate is sound; the population was short. Host drivers are core by every other measure
(`init.sh`, `scripts/lib/host.sh` and `scripts/intake-wizard.sh` source them by path), so a
convenience call added to one severs nothing and fuses everything, which is precisely the Tuesday-
afternoon failure M3 exists to make red. **Implemented (`## BL-215:`).** Both `CORE_GLOBS` arrays
now carry the fifth glob, under the sync-sibling marker `# BL-215-CORE-GLOB-SYNC` — grep it to find
the pair, and change them together. This contract is no longer stated here and under-enforced
there. On the real tree the widening raised this lint's scanned CORE population from **76 to 79**
files with no new violation, so the three host drivers carried no pre-existing `core → module`
edge. The enforcement half is pinned three ways in `tests/test-lint-module-dependencies.sh`, and
the third pin is the load-bearing one: **S5** plants the line above in a host driver and requires
tier **T2**; **S6** requires a *clean* host driver to raise the reported CORE population by exactly
one, because `rc=0` cannot distinguish "scanned and clean" from "never scanned" and that ambiguity
is the whole reason this gap survived from WP0; and **S7** deletes the glob from a copy of the lint
and requires the plant to pass again, so the pin cannot stay green under the very edit it forbids.
The same correction lands on the delta design's §3.3 and on `docs/module-contract.md` M3, which is
the standing normative transcription of this section.

**M5 is the load-bearing one and it has a cost worth stating.** Zero dependency means the scanner
cannot reuse `scripts/lib/helpers-core.sh`'s printers, its `soif_read_*` state readers, or its host
drivers — it re-implements the small subset it needs. That is deliberate duplication in exchange
for a tool that runs anywhere, and it is the reason §8.2's reuse is specified as
**reuse-by-extraction** (copy the *predicate*, not the *dependency*) rather than sourcing.

**Rejected alternative — one script, a `--brownfield` flag on `init.sh`.** Rejected under D6 and
independently supported by §1.2: init's interactive path has **no existence check whatsoever**, and
twelve of its write sites are unguarded overwrites. A flag would mean auditing every one of those
sites for a mode that must never reach them. A separate driver means they are unreachable by
construction.

**Rejected alternative — scanner as a subcommand of the driver.** Rejected on D1's own logic: a
survey you can only run by invoking the installer is not a survey. The scanner ships as its own
name and its own one-liner.

**Naming (author-proposed, one-edit changeable).** Entry `scripts/scout.sh`, lib
`scripts/lib/scout/`, doc page `docs/scout.md`, product name **Scout**. The house already uses
evocative names for shipped skills (`sweep-triage`, `zoom-out`, `grill-with-docs`), so the register
fits. The driver keeps Karl's name exactly: **`scripts/adopt-project.sh`**.

---

## §4 — The two scenarios (D2)

### §4.1 — The chooser

The question is asked **verbatim**, in Karl's wording, and it is the first thing the driver asks
after presenting the scan:

> **"Is the project built out and needs to be able to be supported (i.e. bug fixes, maintenance,
> new features add), or are you still in the process of building your project?"**

Two properties of that sentence are load-bearing and must survive implementation. It is written
for a **non-developer** — no phase numbers, no framework vocabulary, no "MVP". And it asks about
the **project's situation**, not the project's artifacts, because the artifacts are what the
scanner already measured and they are frequently misleading (a mature service with no `README.md`;
a weekend prototype with a tagged release).

### §4.2 — Evidence the scanner offers (author-proposed set)

The scanner **offers evidence and does not decide**. Each signal is presented with its own
confidence, and the operator's answer overrides all of them.

| Signal | Derivation | Points to | Confidence |
|---|---|---|---|
| **Deployment** | A release/deploy workflow present **and** with a run history, or a deploy-shaped target in the pipeline | S1 | High when run history exists; low from file presence alone |
| **Users** | Explicit operator answer; the scanner cannot measure it | S1 | Operator-stated only — the scanner must not guess |
| **Release tags** | `git tag` matching a version-ish pattern, with dates | S1 if tags exist and the newest is recent | Medium — tags are cheap and often abandoned |
| **Commit recency and shape** | Age of `HEAD`; ratio of `feat:`-shaped to `fix:`-shaped subjects over the last N commits | `fix`-dominant → S1; `feat`-dominant → S2 | Low — a heuristic, labelled as one |
| **Changelog with dated released versions** | A `CHANGELOG.md` with ≥1 dated version heading | S1 | Medium |
| **Test baseline** | Whether a test command exists and whether it passes | Neither — it feeds §5, not the chooser | n/a |

**Rejected alternative — infer the scenario and ask for confirmation.** Rejected. The framework's
own prefill pattern (`# BL-204-PREFILL-READ`) is right for *facts the framework itself recorded
earlier*; it is wrong for a judgment the framework has never made. Presenting a guess as a default
would make the most consequential answer in the flow the easiest one to accept without reading.

### §4.3 — S1 — COMPLETED

| Property | Value |
|---|---|
| **Lands at** | `current_phase: 4`, adopted. |
| **Era entered** | The delta/maintenance era immediately — bug fixes, maintenance, new features arrive as deltas. |
| **Interview weight** | **Light on futures** (no MVP cutline; no Phase-0 success criteria for work that is already shipped), **heavy on operations** — incident response, on-call reality, backup maintainer, hosting, the release lane — **and on data classification**, which is non-skippable (§4.5). |
| **Certification scope** | Every gate 0→1 through 3→4, because landing at phase 4 means all four have notionally been crossed. This is the heaviest certification pass and it is the correct one. |
| **Docs** | Reconstructed from the code and the interview, **provenance-marked** (§8.6). What exists is described honestly as what exists. |

**The consequence that makes S1 expensive, verified.** The Phase 1→2 ZDR backstop fires whenever
`current_phase >= 2` and is a hard `[FAIL]`: it requires
`.claude/process-state.json::phase1_artifacts.data_classification` to be one of the seven-value
taxonomy `{public, internal, confidential, pii, financial, health, regulated}`, **and**, for
anything above `public`, either `zdr_attested` or a non-empty `zdr_attestation_reason`. An S1
adoption lands above that threshold on its first commit. There is no version of S1 in which the
data-classification question can be deferred — which is precisely why D2 names it as load-bearing.

### §4.4 — S2 — IN-FLIGHT

| Property | Value |
|---|---|
| **Lands at** | The phase its artifacts support, floored by the interview. |
| **Era entered** | The normal phase machine. S2 reaches the delta era **by shipping v1** through the gates like any other project. |
| **Docs for what EXISTS** | Reconstructed and **provenance-marked** — a record of what was already built. |
| **Plan for what is COMING** | Authored **fresh and real**: a genuine MVP cutline, genuine success criteria, genuine exclusions. **Nothing is grandfathered going forward.** Work done after adoption is subject to every gate at full strength, including TDD ordering. |
| **Certification scope** | Only the gates *below* the landed phase. A project landing at phase 2 certifies 0→1 and 1→2, and crosses 2→3 and 3→4 the ordinary way, later. |

**Phase placement (author-proposed).** Reuse-by-extraction of `scripts/validate.sh`'s artifact
ladder — `PRODUCT_MANIFESTO.md` → 1, `PROJECT_BIBLE.md` → 2, non-empty `docs/test-results/` → 3,
`HANDOFF.md` → 4 — with **three corrections the extraction must make**, because the original is a
diagnostic and not a decision procedure:

1. **It is not in a function and carries no marker.** It is straight-line top-level script body
   under the `print_section "Phase State & Artifacts"` banner. Extraction means lifting a
   *predicate*, and the extracted copy should be the one that gets a marker.
2. **Assignments are sequential, so the *last* matching test wins** — a project with `HANDOFF.md`
   and a since-emptied `docs/test-results/` reports 4. The extracted version must take the
   **highest *reached* rung**: a rung advances the placement only when the rung below it was itself
   reached, so the ladder stops at the first gap. **v1.2 (2026-08-09) — evidence-led correction.**
   v1.0/v1.1 said "the **maximum** satisfied rung", and **this document's own WP1 fixture refutes
   it**: on that fixture the satisfied set is {1, 2, 4}, so a plain maximum returns **4** — which is
   exactly the number §10-WP1's mutation watches for as the *failing* result. The required output of
   **2** is unreachable under plain-max, and the mutation could therefore never have gone RED
   against a spec-faithful build. The reached-rung reading is also the only one coherent with this
   section's own **certification scope** row: landing at phase N certifies every gate *below* N,
   which is a property of a contiguous prefix and not of a satisfied set with a hole in it. Shipped
   as `scout_phasemap_scan` in `scripts/lib/scout/scout-phasemap.sh`, load-bearing line
   `# SCOUT-LADDER-MAX`.
3. **The ladder keys on framework artifact names**, which a brownfield project does not have. For
   adoption the ladder must be re-expressed over **the adoptee's own evidence** — architecture
   documentation of any name, a test corpus that runs, a deploy lane — with the framework filenames
   as one input among several. **This is the least certain mechanism in the design and §12 says so.**

**The floor rule.** The interview may only move the placement **down**, never up. Artifact evidence
is a claim about what was built; the operator's answer is a claim about what is true. Where they
disagree, the safer number wins, because a project placed too low certifies more than it strictly
needed and a project placed too high certifies less than it owed.

### §4.5 — What both scenarios share

- **Data classification is non-skippable** in both (§4.3's mechanism applies to any landing at
  phase ≥ 2, and S2 landings below that still owe it before their real 1→2 crossing).
- **Both run the full secrets scan** (§6) — history does not care what phase you land at.
- **Both run the collision policy** (§7).
- **Both get the adoption stamp and the Adoption Record** (§8.5, §8.8).
- **Neither gets a forward exemption.** Every certification-kind-(c) exemption in §5.4 is scoped to
  commits **at or before** the adoption commit. There is no arm anywhere in this design that
  exempts a commit written after adoption day.

---

## §5 — The certification pass (D3)

### §5.1 — What it replaces

The framework's existing precedent is bare grandfathering, and its own comment is the indictment:
a project without the flag is read as grandfathered and "is never retroactively blocked". Nothing
is measured; nothing is recorded; the exemption is the *absence* of a field. **The certification
pass inverts all three properties**: everything that can be measured is measured, everything
measured is recorded, and the exemption is an explicit, dated, per-item statement of why a thing
could not be run.

### §5.2 — The three kinds

| Kind | Definition | What lands in the record | What is marked |
|---|---|---|---|
| **(a) Honestly producible now** | The requirement is an artifact or a scan. Both can be produced today against today's code. **Docs generated plus interview; scanners, tests and evals EXECUTED fresh.** | Real artifacts and real scanner output, dated today | **Nothing.** A Semgrep run against the adoptee's tree on 2026-08-02 is not a reconstruction of anything — it is the scan. It carries no marker because there is nothing to qualify |
| **(b) The gate reviews themselves** | The requirement is a human review. It can be **held now** — same checklist, same track-aware depth the gates already demand. | A **real** review, signed, dated today, with its artifact | **Only the ordering fact**: this review happened *after* the code, not before it. One field, one sentence. The review's substance is not marked, because it is not diminished |
| **(c) Inherently historical** | The requirement is a fact about *when* something happened. It cannot be re-run in principle. | An `adopted-at` marker **plus a forward equivalent** that is fully enforced from adoption day | The exemption itself, per item, with its scope (commits at or before the adoption commit) and its forward equivalent named |

**Kind (b) needs one clarification a reviewer will press on.** A review held after the code exists
is a weaker instrument than one held before it — it cannot prevent, only detect. The design does
not claim otherwise. What it claims is narrower and defensible: the *record* is real. A signature
on a review that happened is worth something; a signature on a review that did not happen is worth
less than nothing, because it makes the log lie. Marking the ordering and nothing else is the
smallest honest statement available.

### §5.3 — Per-gate mapping: what runs for real, what is marked

Requirements below are read from `scripts/check-phase-gate.sh` and its siblings. **Blocking-ness is
read from the `issues=$((issues + 1))` increment, never from the printed label** — §5.5.

| Gate | Requirement (verified anchor) | Kind | What runs for real at adoption | What is marked |
|---|---|---|---|---|
| **Pre-Phase 0** (organizational only) | Six named pre-conditions, each a dated row: AI deployment path, Insurance, Liability, Sponsor, Backup maintainer, ITSM — `check_named_row` | **(b)** | The six decisions are genuinely taken and genuinely recorded, today | Ordering only |
| **0→1** | Gate date recorded + dated `APPROVAL_LOG.md` entry; `PRODUCT_MANIFESTO.md` present and passing `validate_manifesto_content` (required sections, no placeholder-only sections, no unresolved Open Questions); `docs/phase-0/` carrying ≥3 of `frd.md` / `user-journey.md` / `data-contract.md` (`# BL-114-F1-INTERMEDIATES`) | **(a)** docs + **(b)** approval | The manifesto, FRD, user journey and data contract are **written**, from the code and the interview. The sponsor approval is **held and signed** | Docs carry provenance headers (§8.6); approval carries the ordering fact |
| **1→2** | Gate date + approval; branch-protection backstop; push verification (`# BL-084-PUSH-VERIFY`, `# BL-116-PUSH-GATE-SCOPE-BEGIN`); **ZDR: `data_classification` in the 7-tier taxonomy + attestation**; `PROJECT_BIBLE.md` present, ≥14 numbered sections, no `YYYY-MM-DD` placeholders | **(a)** + **(b)**, and the ZDR arm is **neither** | Branch protection is **verified live** against the host. `PROJECT_BIBLE.md` is **written**, including the §4 threat model. The STA architecture/security review is **held**. **Data classification is a fresh human answer, not a reconstruction** | Bible carries provenance; approval carries ordering. **The classification answer carries nothing — it is a present-tense fact about the data the system handles today** |
| **2→3** | Gate date + approval; `FEATURES.md`; `CHANGELOG.md`; the bug gate — `Bug gate BLOCKED. Resolve SEV-1/2 bugs before Phase 3.` | **(a)** | The bug gate **runs for real** against the adoptee's imported bug set. `FEATURES.md` is reconstructed from the shipped feature surface; `CHANGELOG.md` is **theirs, kept** (D5) | Features doc carries provenance. The bug gate result is unmarked — it is a measurement of today |
| **3→4** | Gate date + approval (organizational: **dual**, Application Owner *and* IT Security, `validate_approval_section_dated`); the **Phase-3 scan gate**; POC-mode release block; `release.yml` free of `TODO`; `HANDOFF.md`, `docs/INCIDENT_RESPONSE.md`, `sbom.json`; non-empty `docs/test-results/`; `SECURITY.md`; pentest (full track); the **9-step Phase-3 checklist**; the **review manifest** | **(a)** scans + **(b)** reviews | **All five Phase-3 scanners execute**: `semgrep-full-tree`, `license`, `snyk`, `zap-dast`, `threat-model`. The **six-reviewer evaluation set runs**, with Security and Red Team mandatory on standard/full. `HANDOFF.md`, `INCIDENT_RESPONSE.md`, `SECURITY.md` and the SBOM are produced. The nine checklist steps are worked, not ticked | Reviews carry ordering; produced docs carry provenance. **Scanner output carries nothing** |
| **Commit-time: TDD ordering** | `tdd_terminal_enforce` / `# BL-072-TDD-ENFORCE` — a `feat:`/`fix:`/`refactor:` subject staging implementation with no test in the commit **or earlier on the branch** | **(c)** | Nothing — the ordering of 2023's commits is not a re-runnable fact | `adopted-at` scoped to commits ≤ the adoption commit. **Forward equivalent: the test-debt ledger and its ratchet (§5.4).** Full enforcement from adoption day |
| **Approver-versus-author** | `validate_approval_fields`'s per-line `git blame` self-approval walker, inside `if [ "$deployment" = "organizational" ]` | **(c)** for historical commits | Nothing for pre-adoption history — there are no approval rows in it | `adopted-at`. **Forward equivalent: the certification approvals themselves are subject to the walker**, so the first thing the control ever sees on this project is the adoption sign-off |

**Two coverage facts a reviewer should have, because they bound what kind (c) is actually
exempting.** `validate_approval_fields` is invoked **exactly twice** — for `"Phase 0.*Phase 1"` and
`"Phase 1.*Phase 2"`. There is **no** author verification at 2→3 or 3→4 today, for any project,
adopted or not; and the walker is entirely inside the `organizational` guard, so a personal
deployment gets none of it. The team-orchestrator design files this as its own §6.2 gap. **This
design must not present kind (c) as waiving a control that would otherwise have applied** — for a
personal-deployment adoptee it waives nothing, because nothing was running.

### §5.4 — Kind (c)'s forward equivalent: the test-debt ledger

**Nothing like this exists today** — no test-debt ledger, no untested-file baseline, no coverage
ratchet anywhere in the tree. The nearest structural analogue is `KNOWN_ORPHANS_PENDING_BL035` in
`scripts/lint-tests-registered.sh`: an allowlist that is required to shrink, with a self-emptying
nag. This design follows that shape, not a coverage tool's.

**Author-proposed mechanism.** At adoption the driver writes `.claude/test-debt.json`: the set of
source files with no corresponding test, measured by the same language-aware classifier the TDD
gate already uses (`_bl072_classify_status` in `scripts/lib/tdd-classify.sh`, including its
`# BL-107-RUST-INLINE-TESTS` content probe, so Rust inline tests count). Two arms, tier-floored on
the `# BL-084-TIER-KEY` ladder exactly as every other severity in this framework is:

| Arm | Rule | `no` | `light` | `strict` |
|---|---|---|---|---|
| **Non-growth** | The untested set may not gain a member | silent | warn | **block** |
| **Touch-repays** | A file in the untested set that is modified must leave the set in the same commit | silent | warn | **block** |

**Three honest limits, stated because they are the attack surface.**

1. **"Has a test" is not "is tested."** The classifier answers a filename/inline-marker question,
   not a coverage question. A file with an empty test file satisfies it. This is deliberate: the
   framework has no coverage instrumentation in any language (the one `-coverprofile` in
   `templates/pipelines/ci/github/go.yml` produces a file nothing reads), and inventing
   cross-language coverage is a far larger project than adoption.
2. **The ledger is a committed file and can be edited.** Same property as `enforcement_level` and
   every other in-repo control: you can route around the block, not around the record. Ledger
   mutations write an audit row.
3. **Non-growth is weaker than shrinkage.** The design deliberately does not mandate a
   burn-down schedule. A rate is a business decision, not an architecture one, and a rate the
   operator cannot meet teaches them to disable the gate — the false-FAIL doctrine this repo
   already learned from BL-122/BL-149.

### §5.5 — Certification can fail

**Severity vocabulary — reused, not invented.** `templates/generated/identifiers.tmpl` already
registers `SEV-1`…`SEV-4` as a fixed vocabulary, and the Phase 2→3 bug gate already blocks on
`SEV-1/2`. Certification triage rides that ladder rather than adding a second one.

| Finding grade | Effect on adoption | Where it goes |
|---|---|---|
| **SEV-1 / SEV-2 equivalent** ("blocker-grade") | **Adoption does not complete.** Either fixed, or explicitly accepted with a **recorded sign-off** naming the accepting person, the reason, and the date | An `accepted-risk` row in the Adoption Record and an audit row |
| **SEV-3 / SEV-4** | Adoption completes | **Seeds the opening work queue** — for S2, fix-as-you-build inside the normal Build Loop; for S1, the first deltas |
| **Secrets findings** | §6.3's own disposition rule, which is stricter | Redacted findings file plus per-finding disposition |

**"Adoption does not complete" is a real state, and it must be a *safe* one.** The driver's write
order (§8.4) is chosen so that a run halted at the blocker stage leaves the project **more**
enforced than before, never less: `phase-state.json` exists (so the gates are live), the manifest
does not (so `read_enforcement_level` returns `strict`). An operator who abandons an adoption
mid-way has a blocked repository, not a silently-degraded one. That is the correct failure
direction and it is verified in §8.4.

**Rejected alternative — warn on everything and let the operator decide.** Rejected as the exact
thing D3 was raised to replace. An adoption that always succeeds is a rubber stamp with a longer
runtime.

---

## §6 — Secrets (D4)

### §6.1 — Scope, and what is genuinely new

Adoption runs **full-history** `gitleaks` (`gitleaks git`, which walks history — verified: a key
present only in a superseded commit and absent from the working tree is found). Against what the
framework already ships (C8):

| Existing surface | Scope | Adoption adds |
|---|---|---|
| Emitted GitHub CI — `./gitleaks git --redact --exit-code 1` on `fetch-depth: 0` | Full history | **Timing.** CI runs after the first push; adoption runs before the first write |
| Emitted GitLab / Bitbucket CI — `gitleaks dir . --verbose --redact` | **Working tree only** | **History**, which those hosts' templates never scan |
| Emitted local pre-commit hook — `gitleaks git --staged 2>/dev/null` | Index only | Everything before the first commit under the framework. **It also omits `--redact` — which, verified, leaks nothing** (no `-v` ⇒ empty stdout; stderr carries only `WRN leaks found: N` and is discarded by the hook). The operator gets the framework's `[BLOCKED]` lines and **no finding detail at all** (§12-2) |
| Phase 3 — `P3_SCANNERS="semgrep-full-tree license snyk zap-dast threat-model"` | No secret scanner at all | The whole category |

### §6.2 — Redaction is a projection, not a flag (C7)

**`--redact` is necessary and not sufficient.** Executed against a planted key: without it the
value appears twice in the JSON report (`Secret`, `Match`); with it, zero times. But the report
carries **18 fields**, including `Message` — the full commit message — **which `--redact` does not
touch**. A second key planted in a commit message survives into the "redacted" report intact.

**Therefore: every artifact this design writes is built by an explicit field allowlist, never by
passing the tool's report through.**

| Field | Kept? | Why |
|---|---|---|
| `RuleID` | ✅ | What matched |
| `File` | ✅ | Where |
| `Commit` | ✅ | When, in history terms |
| `Fingerprint` | ✅ | `<commit>:<file>:<ruleid>:<startline>` — the stable per-finding key the disposition file joins on |
| `StartLine` | ✅ | Locates it without quoting it |
| `Date` | ✅ | Ordering, and "is this still live" |
| `Description` | ✅ | Human-readable rule name |
| `Secret`, `Match` | ❌ | The value. Never |
| `Message` | ❌ | **Not redacted by the tool.** Free-text, operator-authored, demonstrated to carry a secret |
| `Author`, `Email` | ❌ by default | Not needed to disposition a finding; attribution of a leak to a named person is a decision for the operator, not a default in a committed file |
| `Entropy`, `EndLine`, `EndColumn`, `StartColumn`, `SymlinkFile`, `Tags` | ❌ | Not load-bearing; every field kept is a field that can leak |

**The allowlist is the mechanism, and it is stated positively.** A denylist would silently pass
through any field a future gitleaks release adds.

### §6.3 — Per-finding disposition is required

Every finding gets exactly one disposition, recorded, keyed by fingerprint:

| Disposition | Meaning | Evidence required |
|---|---|---|
| **rotated** | The credential has been changed at the source of truth | Date, and who rotated it |
| **false alarm** | Not a credential | A reason. The rule id alone is not a reason |
| **accepted risk** | Real, not rotated, accepted anyway | Named accepting person, reason, date — the same shape as §5.5's blocker acceptance |

**Tiering (D4, verbatim):** **BLOCK at strict**; **BIG WARNING at personal**. The warning must be
genuinely loud — a bordered block, the count, the phrase *"secrets found in your project's
history"*, the statement that history is public to anyone with a clone, and the fact that
**rotation, not deletion, is the fix**. The house's own precedent for a loud non-blocking notice is
`tdd_emit_warn_term`'s bordered `[WARN]` block; this one should be at least as loud, because its
consequence is larger.

### §6.4 — History rewrite: printed, never executed

The report prints the instructions — `git filter-repo` or BFG, the force-push, the requirement that
every collaborator re-clone, and the plain statement that **a rewrite does not un-leak anything
already fetched, so rotation comes first**. The driver never runs them. This is the same posture as
`_bl099_sync_precommit_hook`'s `.new` sidecar: hand the operator the artifact and the instruction,
never the surprise.

### §6.5 — The planted-secret test (D4's assertion, made precise)

The test plants **three** synthetic keys — one in a **diff**, one in a **commit message**, and a
**carrier** in the diff of the same commit that carries the message plant — and asserts that **none
of those strings occurs anywhere** in any artifact the driver writes. (v1.0/v1.1 specified two;
the third is a v1.2 evidence-led addition, below.) Three fixture notes that will otherwise cost an
implementer an afternoon:

- `AKIAIOSFODNN7EXAMPLE` is **allowlisted by gitleaks' default config** and yields zero findings.
  The fixture must use a non-canonical synthetic key.
- **Both plants must be BASE32-valid** — the `aws-access-token` rule requires the 16 characters
  after `AKIA` to be drawn from **`[A-Z2-7]`**. Verified: a plant containing `9` yields **zero**
  findings even in a diff. **A carelessly-chosen plant makes WP2's Mutation A vacuous** — the
  assertion passes for the wrong reason and the mutation can never go RED. The test must therefore
  **assert a non-zero finding count on the diff plant as a precondition**, so a dud fixture fails
  loudly instead of certifying nothing. (v1.0 of this document shipped exactly that dud in its own
  C7 demonstration; R-BF-4 caught it.)
- The commit-message plant is **not itself reported as a finding** — `gitleaks git` scans diffs, not
  messages, **confirmed with a BASE32-valid key so the result is not an artefact of the plant**
  (a valid key present only in a commit message yields **zero** findings). It can therefore only be
  caught by asserting on the artifact's **bytes**, never on the finding count.
- **A THIRD "CARRIER" PLANT IS REQUIRED, in the diff of the same commit that carries the message
  plant. v1.2 (2026-08-09) — evidence-led; measured during the WP2 build and independently
  re-verified by review.** What the note above leaves unsaid is the half that decides whether the
  test works at all: a finding's `Message` field holds the message of **the commit that produced
  that finding**. A message plant on a commit whose diff is *clean* therefore produces no finding,
  populates no `Message`, and **reaches no artifact byte even under a full report passthrough** — so
  **WP2's Mutation B (replace the field allowlist with a passthrough → the message plant appears →
  RED) would go green against a correct implementation and a broken one alike.** The carrier key
  puts a real finding on that commit, which is the only thing that makes its message reach the
  report. Verified on gitleaks 8.30.1: in the redacted report the diff plant and the carrier occur
  **0** times and the message plant occurs **1** time, in `Message`. Without the carrier that count
  is **0**, and Mutation B is vacuous. The carrier is a *fixture precondition*, exactly like
  BASE32-validity and the non-zero-finding assertion above — all three exist so a dud fixture fails
  loudly instead of certifying nothing. (The shipped suite
  `tests/test-brownfield-wp2-scout-sections.sh` carries a fourth plant in the fixture's
  `.git/hooks/pre-commit`; that one belongs to §7.3's separate hook-description hazard, not to this
  recipe.)

---

## §7 — Collision policy (D5)

### §7.1 — The three buckets

The framework's existing behaviour already sorts collisions into three shapes, and this design
reuses the vocabulary rather than inventing one: **marker-composed** (append into a foreign file
under a fence, with an uninstall), **sidecar** (`.new`, diff-and-adopt), and **notice-only**
(`# BL-099-DOC-GUARD` — touch nothing, say so). D5 adds a fourth, which is the one this design is
built around: **archive-and-replace**.

| Bucket | Applied to | Behaviour |
|---|---|---|
| **Archive-and-replace** | Their **AI-layer surfaces** — Claude hooks, skills, MCP connections, AI settings — **and their git hooks** | Inventory → archive with MANIFEST → install the framework's clean set → disclose plainly → permit re-adds, warned and recorded |
| **Marker-composed** | Where the framework already composes: `commit-msg` (`SOIF_TDD_OPEN`), the strict-tier `pre-commit` block (`SOIF_PRECOMMIT_OPEN`, with `--uninstall`) | Unchanged. Adoption uses the composing writers where they exist |
| **Audit-only (the CI carve-out)** | Their pipelines | **Never archived, never touched.** Framework CI installs as its own files (§7.4) |
| **Keep-theirs** | Project files — `README.md`, `CHANGELOG.md`, their docs | Theirs stays. Framework artifacts adapt (§7.5) |

### §7.2 — Archive layout and MANIFEST (author-proposed)

**Follows the one established snapshot precedent** — `_upgrade_snapshot_pre_mutation()` in
`scripts/upgrade-project.sh` — in every respect except one, and the exception is declared:

```
.claude/adoption-archive/<UTC-timestamp>-<pid>/
  MANIFEST.json          <- deliberate EXTENSION; the precedent writes no manifest
  MANIFEST.md            <- the human-readable disclosure, same content
  .claude/settings.json
  .claude/settings.local.json
  .claude/skills/<name>/SKILL.md
  .mcp.json
  git-hooks/pre-commit
  git-hooks/commit-msg
  git-hooks/<other>
```

Inherited from the precedent, each verified in `upgrade-project.sh`:

- **Directory name** `date -u +"%Y-%m-%dT%H-%M-%SZ"` plus `-$$`, with a `-1`, `-2`, … collision
  loop — e.g. `2026-08-02T23-36-51Z-41287`.
- **Original paths mirrored relative to the project root**, so restoration is unambiguous.
- **Only files that exist are archived** — no spurious empty files.
- **Announced on stdout** at the moment it is written.
- **Retained, never auto-deleted on the failure path.**

Two deliberate divergences, both stated as such:

1. **A MANIFEST is written.** The precedent has none — its snapshot is a bare mirrored tree, which
   is adequate for rollback and inadequate for disclosure. D5 requires a manifest; this is an
   extension, not a claim of precedent. **Recipe corrected at v1.1 (R-BF-7):** a bare
   `grep -n 'MANIFEST' scripts/upgrade-project.sh` returns **18** hits and proves nothing — they are
   `MANIFEST_JSON` (the Solo manifest path variable) and `PRODUCT_MANIFESTO`. The claim is about the
   *snapshot tree*, so scope it there:
   `grep -n 'MANIFEST' scripts/upgrade-project.sh | grep -viE 'MANIFEST_JSON|PRODUCT_MANIFESTO'`
   — which is what `_upgrade_snapshot_pre_mutation` writing no inventory file actually looks like.
2. **Retention is unlimited.** The precedent prunes to keep-3. An adoption archive is written
   **once per project**, is the operator's only copy of their own configuration, and must never be
   pruned by a later run.

**MANIFEST.json (author-proposed):**

```json
{
  "schemaVersion": 1,
  "adoptedAt": "2026-08-02T23:36:51Z",
  "archiveDir": ".claude/adoption-archive/2026-08-02T23-36-51Z-41287",
  "entries": [
    {
      "originalPath": ".git/hooks/pre-commit",
      "archivedPath": "git-hooks/pre-commit",
      "class": "git-hook",
      "sha256": "…",
      "mode": "755",
      "description": "Ran `npx lint-staged`, then `npm test -- --bail`.",
      "restore": "cp .claude/adoption-archive/<dir>/git-hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit"
    }
  ]
}
```

**`description` is required for every `git-hook` entry** (D5: archived git hooks get a
what-it-did description in the report). It is generated by a shallow static read — the commands the
hook invokes and any named tool — and is explicitly **advisory**: a hook can do anything, and the
description is a summary, not a specification. The manifest says so in a header line rather than
implying completeness.

### §7.3 — Disclosure, re-adds, and the warning

**Disclosure is plain and non-negotiable.** After the archive is written, the driver prints: the
sentence *"moved to ensure the framework operates properly"*, **the list** of what was moved, and
**the restore instructions**. Not a summary count. The list.

**Re-adds are permitted** — this is Karl's decision and it matters: the framework's premise is
opinionated enforcement, not confiscation. Every re-add is accompanied by the warning, near-verbatim:

> **Personal systems may conflict with the framework — accuracy, documentation, and capabilities
> may be compromised.**

and **every re-add is recorded in the audit trail**. Mechanically that means a `bypass-audit` row.
Adding a new row `type` is the framework's known-thorny operation, so §10-WP6 names the surfaces
that must move together (§8.9).

**One hazard worth naming.** `.git/hooks/` is **not** tracked by git; the archive directory under
`.claude/` **is**. Archiving a hook therefore promotes an untracked file into version control — and
a hand-rolled hook can contain a token. The driver must run the §6 redaction scan **over the
archive directory itself** before staging it, and refuse to stage an archive entry that matches.
This is recorded again in §12 because it is a genuine new exposure created by this design.

### §7.4 — The CI carve-out (Karl's, accepted)

**Their pipelines are audited, not archived, and never touched.** The framework's CI installs as
its **own files**, distinct from anything the adoptee already has.

**Why this is the right carve-out, with the mechanism.** `generate_ci()`'s destination is
host-dependent: on GitHub it is `.github/workflows/ci.yml` — one file among many — but on GitLab
and Bitbucket it is `.gitlab-ci.yml` / `bitbucket-pipelines.yml`, which **is** the project's entire
pipeline. Archiving-and-replacing there would take a working deploy offline on day one. Adoption
therefore installs to framework-owned names on every host (author-proposed:
`.github/workflows/solo-gates.yml`, `.gitlab-ci-solo.yml` included from theirs by operator action,
`bitbucket-pipelines.solo.yml` likewise) and **never writes the canonical path**.

**A false-pass this exposes, and the design must not inherit it.** `scripts/verify-install.sh`
registers `CI pipeline exists ($_ci_dest)` on nothing more than `[ -f "$_ci_dest" ]`. On an adoptee
that already has a `.gitlab-ci.yml`, the framework will report its CI as installed while none of
its gates run in CI at all. **The adoption flow's own CI check must key on the framework's own file
and its own job names, not on the generic destination.**

**SDLC-undermining workflows get loud findings** (author-proposed detector rule set, all
report-only):

| Rule | Detects | Why it matters here |
|---|---|---|
| **Auto-merge** | Workflows enabling auto-merge, or merging without a required-check dependency | Defeats "no merge on red", the framework's first house rule |
| **Deploy-around-the-release-lane** | A deploy job not gated on the release lane, or triggered by a branch push rather than a tag/dispatch | Defeats the Phase 3→4 gate entirely — code reaches production without crossing it |
| **Force-push / history rewrite in CI** | `push --force`, `filter-repo`, `filter-branch` in any workflow | Destroys the tamper-evidence the whole audit story rests on |
| **Check-skipping** | `continue-on-error: true` on a security or test step; `if: always()` on a gating job | Turns a red gate green silently — the exact defect class this repo's `[WARN]` trap embodies |

**Keep-or-retire is the user's recorded decision.** For each finding the operator answers *keep*
or *retire*, and the answer — with its reason — is written into the Adoption Record. The driver
never edits their workflows. **Their deploys must not be broken on day one**, and a design that
quietly disabled a pipeline in the name of governance would deserve everything it got.

### §7.5 — Project files: keep theirs, framework artifacts adapt

`README.md`, `CHANGELOG.md`, and their documentation stay exactly as they are. The framework's own
artifacts adapt around them:

- **`CHANGELOG.md`** — theirs is kept. The framework's changelog *conventions* are applied to new
  entries going forward; the existing file is not reformatted. Note the Phase 2→3 gate only asserts
  the file **exists**, so an adoptee's changelog satisfies it on contact.
- **`README.md`** — never written. The framework has no `README.md` writer today anyway
  (`grep -n 'README' init.sh` returns two hits, neither a project README).
- **`FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md`** — if absent, created from template as today. **If
  present, treated as theirs**: kept, and reconciled by the interview rather than overwritten. This
  is a direct inversion of `create_project()`'s current unconditional `cp`.
- **`CLAUDE.md` and `PROJECT_INTAKE.md`** — the existing `# BL-099-DOC-GUARD` classification is
  **notice-only** in the upgrade path. Adoption needs them to exist, so it **creates them when
  absent** and is **notice-only when present**, which keeps the guard's contract intact.

---

## §8 — Mechanics (D6)

### §8.1 — The driver

**`scripts/adopt-project.sh`. Not a mode of `init.sh`.** The reason is §1.2: init's interactive
path has no existence check at all, and twelve of its write sites are unguarded overwrites. A
`--brownfield` flag would require every one of those sites to be audited for a mode that must never
reach them; a separate driver makes them unreachable. The driver **may reuse** init's non-destructive
generators by extraction, and **must not** invoke `create_project()`.

The driver runs in the adoptee's directory. It inherits the framework's existing posture that these
tools target a project and not the framework — `guard_not_in_framework` fires at source time in
`process-checklist.sh` and `reconfigure-project.sh`, before argument parsing, so even `--help` exits
1 inside this repo. The driver should carry the same guard, and its tests must therefore run in
fixtures, never in-tree.

### §8.2 — Scanner report: sections and schema (author-proposed)

Seven sections, exactly as D6 names them. Emitted as one JSON document plus a rendered Markdown
view of the same data — the currency system's precedent, where `plan-staging.sh` writes both a
`manifest.json` journal-of-record and a human `UPDATE-PLAN.md` from it.

```json
{
  "schemaVersion": 1,
  "scannedAt": "2026-08-02T23:36:51Z",
  "scannerVersion": "…",
  "repoRoot": "…",
  "headCommit": "…",

  "stack":  { "languages": [{"name":"typescript","files":412,"confidence":"high"}],
              "packageManagers": ["pnpm"], "buildFiles": ["package.json"],
              "testCommand": {"value":"pnpm test","source":"package.json scripts.test"},
              "ciHost": "github" },

  "phaseMap": { "suggestedPhase": 2, "highestSatisfiedRung": 4, "rungs": [
                  {"rung":1,"evidence":"README.md (the product is described in writing)","satisfied":true},
                  {"rung":2,"evidence":"docs/architecture.md (the technical shape is documented)","satisfied":true},
                  {"rung":3,"evidence":"no test corpus and no test command found; docs/test-results/ is absent or empty","satisfied":false},
                  {"rung":4,"evidence":"HANDOFF.md (a handover / release record exists)","satisfied":true}],
                "note": "maximum satisfied rung; the interview may only lower this" },

  "reality": { "probes": [
                 {"name":"remote_repo_created","result":"pass","how":"git remote get-url origin"},
                 {"name":"branch_protection_configured","result":"unknown","how":"host API not consulted (read-only)"},
                 {"name":"ci_pipeline_configured","result":"pass","how":".github/workflows/deploy.yml"},
                 {"name":"project_scaffolded","result":"pass","how":"pnpm-lock.yaml"},
                 {"name":"pre_commit_hooks_installed","result":"pass","how":".git/hooks/pre-commit is executable"}] },

  "testsBaseline": { "commandRan": true, "exitCode": 0, "durationSeconds": 94,
                     "untestedSourceFiles": 137, "totalSourceFiles": 412,
                     "classifier": "tdd-classify parity" },

  "secrets": { "tool": "gitleaks", "toolVersion": "8.30.1", "scope": "full-history",
               "findingCount": 3,
               "findings": [{"ruleId":"aws-access-token","file":"config.ini",
                             "commit":"42c8c76…","fingerprint":"42c8c76…:config.ini:aws-access-token:1",
                             "startLine":1,"date":"2024-03-11","description":"AWS Access Token"}] },

  "collisions": { "entries": [
                    {"path":".git/hooks/pre-commit","class":"git-hook","bucket":"archive-and-replace",
                     "description":"Ran `npx lint-staged`, then `npm test -- --bail`."},
                    {"path":".github/workflows/deploy.yml","class":"ci","bucket":"audit-only",
                     "findings":["deploy-around-the-release-lane"]}] },

  "intakePrefill": { "sections": [
                       {"id":"1","field":"project_name","value":"acme-api","source":"package.json name","kind":"scan-derived"},
                       {"id":"5.4","field":"data_persistence","value":null,"kind":"human-mandatory"}] }
}
```

**The `secrets.findings[]` objects are the §6.2 allowlist projection and nothing else.** The schema
does not have a `secret` field to forget to strip.

**`phaseMap.highestSatisfiedRung` is additive, and it is a transparency field — v1.2 (2026-08-09),
evidence-led.** §4.4's correction makes `suggestedPhase` the rung the ladder **reaches** (it stops
at the first gap); this field publishes the **plain maximum** beside it. The two differ exactly when
the evidence has a hole — phase-4 artifacts with no phase-3 evidence, the very fixture whose
arithmetic refuted plain-max — and **that difference is itself the finding**, so collapsing it into
one number would discard the most useful thing the scan learned. It is consumed by the **WP4
interview**: the floor rule lets the operator move the placement only *down*, and an operator cannot
argue a ceiling down if they were never shown it. Emitted by `scout_emit_json` in
`scripts/lib/scout/scout-report.sh`, immediately after `suggestedPhase`. **The example above is the
{1, 2, 4} case itself** — corrected in v1.2 after review (R-PRE-3) found it internally unarithmetic:
it published `highestSatisfiedRung: 4` over a rung list that omitted rung 2 entirely and gave rung 1
rung-2-class evidence. `scout_phasemap_scan` always writes **all four rungs, ascending, satisfied or
not**, each with the evidence string it decided on — including the sentence it prints when a rung
fails, which is why an unsatisfied rung is still worth reading. The example now matches that shape
and demonstrates the gap the two numbers exist to expose. **The `note` string stays
verbatim** as printed above — it is pinned byte-for-byte in the emitter and in
`tests/test-brownfield-wp1-scout.sh`, so re-wording it here would fork the document from the code it
specifies. Its wart is disclosed rather than papered over: with two numbers in the object, the
"maximum satisfied rung" clause reads onto `highestSatisfiedRung` and the "the interview may only
lower this" clause onto `suggestedPhase`. Re-wording it is a separate decision, not part of this
amendment.

**Reuse-by-extraction, precisely.** Two predicates are lifted, neither is sourced (M5):

| Extracted from | What is taken | What is corrected in the copy |
|---|---|---|
| `scripts/validate.sh` — the top-level `print_section "Phase State & Artifacts"` block's `artifact_phase=` ladder | The artifact→phase rung mapping | It is not a function and carries no marker in the original; the extracted copy gets both. Assignments become a **contiguous climb to the highest *reached* rung**, not last-wins — v1.2 corrects "max" here for the reason §4.4 gives. Rungs are re-expressed over the adoptee's own evidence (§4.4) |
| `scripts/process-checklist.sh` — `verify_init()` | Five of the seven reality probes (`remote_repo_created`, `ci_pipeline_configured`, `project_scaffolded`, `pre_commit_hooks_installed`, and the shape of the derived rollup) | **The original mutates state** — its first statement is `ensure_state_file` and each pass writes `.phase2_init.steps_completed`. The scanner's copy is **read-only, always**. `branch_protection_configured` reports `unknown` rather than consulting the host, because a read-only tool must not make authenticated API calls on the operator's behalf; note the original's `# BL-126-ATTEST-CONSULT-BEGIN` fence short-circuits on a recorded attestation and never contacts the host either. `data_model_applied` is not probeable and is omitted rather than faked |

### §8.3 — Reverse intake

The ordinary intake asks a person and writes a document. **Reverse intake** starts from the
document the scanner already derived and asks the person to confirm it — for the parts that are
derivable, and only those.

| Section class | Behaviour | Precedent |
|---|---|---|
| **Scan-derived** | **Prefilled and confirmed.** Two disclosure lines naming the value *and its provenance*, then a two-option *keep it / change it* question; "change it" falls through to the ordinary question | `run_section_1_repo_setup()` and the mutation-pinned `# BL-204-PREFILL-READ` reads. The pattern is already shipped, already tested, and already includes the provenance-disclosure line |
| **Judgment** | **Human-mandatory.** No prefill, no default, no skip. Business context, success criteria, the MVP cutline and exclusions (S2), risk, revenue | New. The prefill pattern is right for facts the framework recorded; it is wrong for judgments it has never made (§4.2) |
| **Data classification** | **Non-skippable, in both scenarios.** No default, no inference, no "confirm" arm | The Phase 1→2 ZDR backstop's hard `[FAIL]` at `current_phase >= 2` makes this a mechanical necessity, not a policy preference (§4.3) |

**Two properties of the shipped prefill pattern the extraction must preserve**, both currently
pinned by mutation tests in `tests/test-intake-wizard-fixes.sh`: the marked read carries an
end-of-line-anchored marker so the test can excise it (`# BL-204-PREFILL-READ`), and a bare `:`
sits above it so the block stays parseable when excised. That affordance is not dead code — it is
what makes the mutation proof possible, and an implementer who "cleans it up" removes the test's
ability to bite.

### §8.4 — Fail-safe state-creation order

**Order: `phase-state.json` → intake → `manifest.json`.** Verified by execution, per surface — and
the per-surface qualification is C4's correction, which matters:

| Partial state | `check-phase-gate.sh` | `read_enforcement_level` | Net |
|---|---|---|---|
| **phase-state present, manifest absent** | Runs. `[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.` → **rc 1** | **`strict`** (missing file → strict; corrupt file → strict) | **Gates live, strictest tier.** Blocked, which is the safe direction |
| **manifest present, phase-state absent** | `No .claude/phase-state.json found — skipping phase gate check.` → **rc 0** | reads the field | **Gates entirely absent.** An adopted-looking project with no gate enforcement |

Writing phase-state **first** means every interruption lands in the top row. The commit-time
sibling agrees and says so in its own comment: `_bl072_tier_bypassable`'s header records
*"MOTHERSHIP SAFETY (hard requirement): a missing .claude/phase-state.json OR a missing/empty
deployment key => BYPASSABLE (WARN-only)"*, implemented as `[ -z "$deployment" ] && return 0`.

**The honest qualification (C4).** "Missing manifest fails strict" is true of
`scripts/lib/enforcement-level.sh` and **false** of `check-phase-gate.sh`, where the missing-manifest
arm of the Phase 1→2 protection backstop is a `[WARN]` **with no `issues` increment** — so within
that one gate, deleting the manifest is *less* blocking than having one with a bad `host`. The
ordering decision is unaffected: the tier ladder is what governs the commit-time gates, and it fails
closed. But the design must not print the flat claim.

**Note also which order `init.sh` uses, and why it is not a counter-example.** In `create_project()`
the manifest is born **first** (by the vendored framework's own init), then the intake, then
phase-state, with the manifest re-seeded later by `prepare_initial_state_for_commit()`. That order
is correct for a *creation* flow, where no partial state is ever left behind because the whole
sequence is one uninterrupted run ending in a commit. It is wrong for adoption, where the run can
legitimately halt at a blocker (§5.5).

### §8.5 — Staging and the adoption stamp

**Explicit-path staging, never `git add -A`.** The precedent is
`git add "${FILES_TO_STAGE[@]}"` in `scripts/upgrade-project.sh`, and the counter-example is
`create_project()`'s `git add -A` followed by `git commit -q --no-verify`, which on an adoptee would
sweep their uncommitted work into a framework commit with verification bypassed. The driver builds an
explicit array; anything not in it is not staged, ever. `upgrade-project.sh`'s own BL-174 comment
already records the failure mode a blanket add produces — *"a downstream `git add -A` would TRACK
them"* — for exactly the two files that are ignored on purpose.

**The adoption stamp: `soif_adoption_stamp`, one call site, beside `soif_currency_stamp`.**

| Property | Value | Rationale |
|---|---|---|
| **Home** | `.claude/manifest.json`, top-level `adoption` block | **C2 decides this — on merge-versus-re-stamp grounds, NOT on "the manifest has no wholesale writer" (R-BF-1 refuted that; it has one, via `fix_framework_manifest()` → CDF `init.sh`).** The property that actually separates the two files: **both** wholesale writers are **missing-file-gated** — `fix_phase_state()` and `fix_framework_manifest()` are each registered in the `else`/`elif` arm of a bare `[ -f … ]` check, so neither ever *destroys* a stamp that was there; the stamp is already gone with the file. But `phase-state.json` is additionally **re-stamped on every upgrade against a file that exists** (`data["review_gate_enforced"] = True`, unconditional), while **every writer that touches an existing `manifest.json` is an additive merge**: `jq '.host = $h'` (`check-gate.sh`, `upgrade-project.sh`), `jq '. + {deployment, poc_mode, enforcement_level}'` (the BL-030 backfill), `jq '. + {deployment, poc_mode}'` (the BL-061 refresh), and `soif_currency_stamp`'s `.currency = $currency` — which additionally no-ops on a missing manifest (`[ -f "$manifest" ] \|\| return 0`). CDF refresh touches assets and the framework's own version fields, not Solo's |
| **Shape** | `jq --argjson adoption "$json" '.adoption = $adoption'` — one additive merge, exactly the `soif_currency_stamp` filter's form | Executed and confirmed additive: unrelated top-level keys survive |
| **Call sites** | **One**, in the driver, marked | `soif_currency_stamp` has exactly one product call site (`# BL-109-CURRENCY` in `init.sh`); the operating-model design's F1 correction records that it is **birth-stamp-only and never a backfill precedent**. The adoption stamp is the same: written once, at adoption, never re-stamped |
| **Contents (author-proposed)** | `{schemaVersion, adoptedAt, scenario: "completed"|"in-flight", landedPhase, certification: {kindA[], kindB[], kindC[]}, blockersAccepted[], scannerReportSha256}` | Everything a later reader needs to know *how this project got here*, and nothing that duplicates state living elsewhere |

**The `adopted` flag itself is separate and minimal**: a boolean the gate arms read. It rides in the
same block so there is one thing to find, and the gate arms read it through one accessor so there is
one thing to mutate in a mutation proof.

### §8.6 — Provenance headers on reconstructed docs

Every document the driver writes that describes **what already existed** carries a provenance header
as its first content. Documents describing **what is coming** (S2's fresh plan) carry none — they are
ordinary forward-looking artifacts and marking them would be false modesty that dilutes the marker
where it matters.

Author-proposed header, in the house's fenced-comment style so it is greppable and machine-strippable:

```markdown
<!-- SOIF-PROVENANCE-BEGIN
reconstructed-at: 2026-08-02
reconstructed-by: scripts/adopt-project.sh
source: existing codebase at 42c8c76 + adoption interview
status: describes work completed BEFORE adoption; not a pre-build specification
SOIF-PROVENANCE-END -->
```

**Why a fenced HTML comment.** It renders invisibly, it is exactly-greppable for a lint, and it
follows the tree's established fence convention (`# BL-196-ALLOWLIST-BEGIN`,
`<!-- BL-170-APPEND-DESIGN -->`, `SOIF_TDD_OPEN`/`SOIF_TDD_CLOSE`). A lint asserting that every
reconstructed doc carries one, and that no forward-looking doc does, is a WP deliverable (§10-WP7).

### §8.7 — Detection baseline

The out-of-band detector must not report the adoptee's entire pre-adoption history as unattributed
activity. The mechanism already exists and already anticipates this case: `init.sh` writes
`git rev-parse HEAD` into `.claude/last-checked-commit.txt` at two sites, and the archived BL-030
design spec states the intent in as many words — *"Commits that existed before the framework was
installed are NOT flagged on first session start. This is critical for projects adopting the
framework into an existing repo."*

The adoption driver therefore sets the baseline the same way, and **re-uses the shipped operator
surface** for later resets: `scripts/reconfigure-project.sh --reset-detection-baseline`, whose
handler block is `# BL-030 Task 8: --reset-detection-baseline.` and whose user-facing output is
`Detection baseline reset to current HEAD.` with the commit subject
`chore: reset detection baseline (reconfigure)`.

**C3's correction, carried here rather than repeated as fact:** the *"migration into the framework on
existing repos with prior unrecorded history"* sentence Karl cited is in the **archived design spec**
§ 10.4, not in the tool. `grep -rni 'migrat' scripts/reconfigure-project.sh` returns one unrelated
internal comment. The mechanism is real and shipped; the wording is not. **Adding that sentence to
the flag's `--help` is a one-line drive-by the build should take** (§10-WP8).

### §8.8 — The Adoption Record in `APPROVAL_LOG.md`

D6 requires the Adoption Record to be **structurally unparseable as a gate approval**. C9 makes that
an eight-clause predicate, because there are eight independent readers and four use unbounded
windows. **There is precedent for writing exactly this kind of invariant list**: the BL-170
append-design commit already did it for the templates' own instruction prose, requiring it be kept
free of *"(a) any `^|`-anchored Date row, (b) the substring "date", (c) an `Approver` token without
`Role`, and (d) `[YYYY-MM-DD]`/`[Name`/`[Attorney` bait"*.

**The Adoption Record's structural contract:**

| # | Clause | Reader it defeats |
|---|---|---|
| 1 | No line matches `Phase N.*Phase N+1` for N ∈ {0,1,2,3} — including in prose | `_cpg_gate_has_evidence` (window opens on **any** matching line, not a heading) |
| 2 | No occurrence of `Pre-Phase 0`, `Application Owner Approval`, `IT Security Approval`, or `Retroactive Phase 1 … Phase 2 … STA` | `check_named_row`, `validate_approval_section_dated`, the retroactive-STA grep |
| 3 | No `^##` heading matching `attorney` or `legal review` (case-insensitive) | `# BL-115-ATTORNEY-ENTRY` in `process-checklist.sh` |
| 4 | No text matching `penetration.*exempted` or `pen.*test.*exempted` | the whole-file pen-test exemption grep |
| 5 | **No table row beginning at column 0 with `|` whose second cell is `Date`** — the record's tables are indented four spaces | `_cpg_gate_has_evidence`'s `^\|`-anchored Date-row grep. Verified: the same content indented four spaces yields rc=1 where unindented yields rc=0 |
| 6 | No case-insensitive `date` substring within 10 lines of any gate-header literal | `check_gate` in `scripts/validate.sh` (`grep -A 10` + `grep -i "date"` — matches `update`, `Candidate`) |
| 7 | No `[YYYY-MM-DD]`, `[Name`, or `[Attorney` literals | `# BL-138-APPROVAL-WINDOW`'s placeholder arm, which **blocks** |
| 8 | **Placed after every gate section**, under its own `## ` heading, so the unbounded `grep -A 30 "Pre-Phase 0"` and `grep -A 20 "$gate_name"` windows cannot reach it | `check_named_row` (31-line window, three `## ` heading lines — §13-V12), `validate_approval_fields`'s permissive pre-extraction |

**A lint pins all eight** (§10-WP7), because clause 5 in particular is a formatting property that a
well-meaning editor will "fix".

**What the record contains:** the scenario, the landed phase, the adoption date, the certification
inventory by kind, the blocker acceptances with their signers, the secrets dispositions by
fingerprint, the collision archive path, and the CI keep-or-retire decisions. It is the one place a
successor reads to understand how this project entered the framework.

### §8.9 — Audit rows

Adoption writes `bypass-audit` rows for: the adoption itself, every blocker acceptance, every
secrets disposition of `accepted risk`, every collision archive, and **every re-add** (§7.3).

**Adding a new row `type` touches five surfaces, and the framework's own history proves it.** The two
most recent additions each missed at least one: `sast_suppression` is in the docblock enum and
**absent** from the `T6: type enum` whitelist in `tests/test-bl029-integration.sh`;
`freshness_enforcement_snooze` is in **neither**, and self-declares the deviation in its own
docblock. Both pins pass today only because they run over fixture ledgers that never contain those
types — a test that cannot fail is not a pin. The five surfaces:

1. the `type` enum docblock in `scripts/lib/bypass-audit.sh`;
2. the `T6: type enum` case statement in `tests/test-bl029-integration.sh`;
3. the emitter, with its own `# BL-NNN-…` marker;
4. a consumer test that puts the new type in a fixture ledger **and asserts on it**;
5. `docs/audit-log-lifecycle.md`'s taxonomy and its cold-pickup `jq` recipes.

**Author-proposed:** one new type, `adoption_event`, with a `details.event` discriminator, rather
than five new types. One enum member is one five-surface change; five members is five.

**And a validation note.** `bypass_audit_append` validates only `jq -e 'type == "object"'` — it will
write `actor: "banana"`. Adoption does not fix that, and should not pretend to; it is recorded in
§12 alongside the team-orchestrator design's identical finding.

---

## §9 — What does not change

Named explicitly so a reviewer can see this design's true scope.

| Kept | Anchor | Note |
|---|---|---|
| **Every gate predicate** | `scripts/check-phase-gate.sh` | Adoption adds arms that *read* an `adopted` flag. It changes no existing predicate's logic |
| **The five Phase-3 scanners** | `P3_SCANNERS="semgrep-full-tree license snyk zap-dast threat-model"`; `# BL-113-NO-LAUNDER`, `# BL-140-ARCHIVE-FRESH` | They **run** during certification. They are not modified |
| **The enforcement-tier ladder** | `# BL-084-TIER-KEY` in `pre-commit-gate.sh`, `check-phase-gate.sh`, `init.sh`, `scripts/lib/enforcement-level.sh` | Reused for every new severity in this design — secrets tiering, the ratchet, roster-free by construction. The "SYNC SIBLINGS" obligation is inherited by any arm that joins the set |
| **The Build Loop classifier** | `scripts/process-checklist.sh` | Unchanged. An adopted project's post-adoption work goes through it identically |
| **The six-reviewer review manifest** | `scripts/lint-review-manifest.sh`; `cpg_role_present`; `evaluation-prompts/Projects/run-reviews.sh` | Certification **populates** it with real, dated, signed entries — the schema already carries `date` and `signed_by` per review, so no schema change is needed |
| **The TDD ordering gate's logic** | `tdd_terminal_enforce`, `_tdd_triggers`, `# BL-072-TDD-ENFORCE`, `# BL-107-RUST-INLINE-TESTS` | One new arm honours the pre-adoption exemption. The trigger predicate, the tier behaviour, and the ledger rows are untouched |
| **The house rules** | No merge on red; never `--no-verify`; TDD with mutation proofs; hermetic tests; register every suite in both lists; marker citations, never bare `file:line` | Including for this build. The driver's own tests are hermetic and touch no live remote |
| **`init.sh`'s greenfield path** | `create_project()` | **Not modified by this design.** Its twelve overwrite sites are correct for an empty directory. §12 records that they remain hazardous under `--allow-existing-dir`, which is a separate defect |

---

## §10 — Build plan (ordered work packages)

"Mutation-provable" means the RED-under-neuter → GREEN-restored proof this framework requires of
enforcement code. **Every grandfather/enabling arm gets a DUAL-DIRECTION proof** — one mutation
proving the arm enforces, one proving the exemption is bounded — and **every proof asserts on the
exit code, never on the printed label**, because in `check-phase-gate.sh` the label is cosmetic:
there are **66** `issues=$((issues + 1))` sites, and of the 44 whose immediately preceding line
carries a status label, **34 print `[WARN]` and 10 print `[FAIL]`**. An exemption is the **absence
of an increment**; a block is its presence. A test that greps for `[WARN]` proves nothing.

| WP | Scope | Test intent · mutation proofs |
|---|---|---|
| **WP0 — Module contract** | §3.3's M1–M5 as a written contract plus `scripts/lint-module-dependencies.sh`. **Converge with the delta track first** — this contract is co-owned and that track has zero commits (C1) | A `core → module` source line fails the lint; a `module → core` one passes; the scanner with `scripts/lib/` moved aside still runs (M5). **Mutation:** delete the direction check → a `core → module` reference passes → RED |
| **WP1 — Scanner: stack, phaseMap, reality** | `scripts/scout.sh` + `scripts/lib/scout/`; the extracted artifact ladder (reached-rung, marked) and the five read-only reality probes | Read-only proven by **tree hash before/after** over the whole fixture, not by inspection — the `plan-staging.sh` idempotency precedent. Reached-rung beats last-wins on a fixture with `HANDOFF.md` and an emptied `docs/test-results/`. **Mutation:** restore last-wins → the fixture reports 4 instead of 2 → RED. **v1.2:** this row's own arithmetic is the evidence that refuted "max" in §4.4 — the fixture's satisfied set is {1, 2, 4}, so a plain maximum also reports 4 and this mutation would have passed against a correct build and a broken one alike |
| **WP2 — Scanner: secrets, collisions, tests-baseline, intake-prefill** | The §6.2 allowlist projection; the §1.2 collision inventory; the test-command probe and untested-file count; prefill extraction | **The planted-secret test (§6.5): three plants — one in a diff, one in a commit message, and a carrier in the diff of the message plant's own commit; assert none of those strings occurs in ANY artifact byte.** **Mutation A:** drop `--redact` → the diff plant appears → RED. **Mutation B:** replace the field allowlist with a passthrough → the **message** plant appears → RED. Mutation B is the one that matters; A alone would have shipped C7's leak. **Fixture preconditions, all non-optional:** every plant BASE32-valid (`AKIA[A-Z2-7]{16}`) (R-BF-4); **the test asserts a non-zero finding count on the diff plant before asserting anything else** — a dud plant yields zero findings, at which point Mutation A passes vacuously and proves nothing; **and the v1.2 carrier plant** (§6.5), without which the message plant's commit produces no finding, its message never populates a `Message` field, and **Mutation B passes vacuously too** |
| **WP3 — In-core enabling arms** | The `adopted` flag accessor; `soif_adoption_stamp` (one call site, manifest home); the TDD pre-adoption arm; stamp acceptance in the gate | **Dual-direction, per arm.** TDD arm: (i) neuter the exemption → an adopted project's pre-adoption commit blocks → RED; (ii) neuter the **bound** (make the exemption unscoped) → a **post-adoption** commit with no test passes → RED. Stamp: a foreign top-level manifest key survives the stamp, and every existing-file writer named in §8.5 is run in sequence with the stamp still present afterwards. **Regression proof RE-AIMED at v1.1 (R-BF-1).** The v1.0 proof — "run `fix_phase_state()`, assert the stamp survives" — is **trivially green and worthless**: that function never touches `manifest.json`. The meaningful proof is the **regenerate** path: delete `.claude/manifest.json` → run `verify-install.sh --auto-fix` → `fix_framework_manifest()` → CDF `init.sh` rewrites it wholesale → **assert the loss of the stamp and the `adopted` flag is DETECTED AND REPORTED LOUDLY**, not that it is prevented (it cannot be — the writer is upstream and out of this design's control). **Mutation:** remove the post-regeneration detection → the project silently un-adopts and every gate arm reads `adopted: false` → RED. This is the honest shape: the design cannot stop the erasure, so it must refuse to be quiet about it |
| **WP4 — Driver skeleton + scenario chooser + reverse intake** | `scripts/adopt-project.sh`; the D2 question verbatim; prefill/confirm on the `# BL-204-PREFILL-READ` pattern; judgment sections mandatory; **data classification non-skippable**. **Required deliverable (R-BF-4/R-BF-6): a section→prefill mapping table**, one row per `run_section_*` runner in `scripts/intake-wizard.sh` — **15 of them** (`1`, `1_repo_setup`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `10`, `11`, `11_5`, `12`, `13`) — each classified **scan-derived / judgment / non-skippable**, with the scan field that feeds it. "Scan-derivable sections are prefilled" is a principle; the table is the specification, and without it the classification is decided ad hoc at implementation time | The chooser's wording is asserted **verbatim** (a string pin — it is a decision, not a phrasing). A scan-derived answer is confirmed with its provenance line; "change it" falls through to the full question. **Mutation:** give data classification a default → a run completes without answering it → RED, asserted by the Phase 1→2 ZDR gate failing on the resulting fixture |
| **WP5 — Certification pass** | The three kinds; the per-gate mapping; real scanner/eval execution; the review-manifest population; severity triage; **blocker-grade blocks completion** | A fixture with a SEV-1-equivalent finding does not complete adoption; the same fixture with a recorded acceptance does, and the acceptance appears in the Adoption Record with its signer. **Mutation:** remove the blocker check → adoption completes with an unaccepted SEV-1 → RED. **Second mutation:** make acceptance implicit (no signer required) → RED |
| **WP5b — Test-debt ledger + ratchet** | `.claude/test-debt.json`; non-growth and touch-repays arms on the tier ladder | Adding an untested file blocks at `strict`, warns at `light`, is silent at `no`. Modifying a ledgered file without adding a test blocks at `strict`. **Dual-direction:** (i) neuter the non-growth arm → the untested set grows silently → RED; (ii) neuter the tier floor → the arm blocks at `no` → RED (a gate that fires at the lenient tier is as wrong as one that never fires) |
| **WP6 — Collision archive + disclosure + re-adds** | §7.2's layout and MANIFEST; disclosure text; the warning near-verbatim; `adoption_event` audit rows across all five surfaces of §8.9 | Archive mirrors relative paths and only existing files; MANIFEST lists every entry with a restore line; a `git-hook` entry carries a description. **The archive is scanned for secrets before staging and a matching entry refuses to stage** (§7.3's new exposure). **Mutation:** suppress the re-add audit row → a silent re-add → RED. The T6 whitelist gains `adoption_event` **and a fixture ledger containing it**, so the pin can actually fail |
| **WP7 — CI carve-out + provenance + Adoption Record** | Framework CI at framework-owned filenames on all three hosts; the SDLC-undermining detector (report-only); keep-or-retire recorded; provenance-header lint; the eight-clause Adoption Record lint | Their `.gitlab-ci.yml` is byte-identical after a run. A workflow with `continue-on-error: true` on a security step produces a loud finding and **no edit**. The Adoption Record does **not** satisfy `_cpg_gate_has_evidence` for any gate — asserted by running the real awk against the real record. **Mutation RE-AIMED at v1.1 (R-BF-5).** The v1.0 mutation — "un-indent the Date rows → the gate-evidence check passes → RED" — **cannot fire**: verified, against a clause-1-compliant record no evidence window ever opens, so the pipeline returns `rc=1` indented *or* not. Two proofs replace it. **(i) The lint is the mutation target:** un-indent the Date rows → **the record lint** goes RED (clause 5 is a lint-enforced property, not a gate-observable one). **(ii) Defense-in-depth, explicitly labelled as such:** a fixture that **jointly** violates clause 1 (a `Phase 0 … Phase 1` prose line) **and** clause 5 (unindented Date row) **does** satisfy `_cpg_gate_has_evidence` — verified `rc=0` — and restoring **either** clause alone returns it to `rc=1`. That is the honest statement of what the eight clauses buy: they are **redundant by design**, and the proof should demonstrate the redundancy rather than pretend any single clause is load-bearing alone |
| **WP8 — Docs + drive-bys** | `docs/scout.md`; the adoption page; `docs/INDEX.md` rows; the `--reset-detection-baseline` help sentence from C3 | `lint-doc-anchors.sh --strict-refs` and `lint-bl-markers.sh` clean; every new suite registered in **both** `tests/full-project-test-suite.sh` and the `tests.yml` unit list, and the exempt-row list audited **by execution**, not by grep |

**Sequencing.** WP0 → WP1 → WP2 → WP3 → WP4 → WP5/WP5b → WP6 → WP7 → WP8. **WP3 is the linchpin** —
it is the only package that touches a gate, and where the `[WARN]` trap will bite a careless
implementer. **WP2 is where a defect would be worst**, because its failure mode is a leaked
credential in a committed file, and C7 shows the obvious implementation has exactly that bug. WP2,
WP3, and WP5 get top-tier implementation and double-mutation verification.

---

## §11 — Non-goals and rejected alternatives

- **A `--brownfield` mode on `init.sh`** — rejected (D6, §3.3). Init's interactive path has no
  existence check and twelve unguarded overwrite sites.
- **An external adoption kit with no in-core changes** — rejected (D1, §3.2). It could only fake
  history, and `fix_phase_state()` erases foreign state from `phase-state.json` wholesale.
- **Bare grandfathering** — rejected (D3, §5.1). It is what the framework does today, in one place,
  and its own comment describes a promise nobody checks.
- **Archiving the adoptee's CI** — rejected (D5's carve-out, §7.4). On GitLab and Bitbucket the
  canonical destination *is* their entire pipeline; replacing it breaks production on day one.
- **Executing a history rewrite** — rejected (D4, §6.4). Instructions are printed; the operator
  decides. Rotation is the fix regardless.
- **Printing gitleaks' report and trusting `--redact`** — rejected on measurement (C7, §6.2). The
  `Message` field is not redacted and demonstrably carries a planted secret.
- **Inferring the scenario and asking for confirmation** — rejected (§4.2). The prefill pattern is
  right for recorded facts and wrong for an unmade judgment; a default would make the most
  consequential answer the easiest to skim past.
- **A coverage-percentage gate instead of the untested-file ledger** — rejected (§5.4). The
  framework has no coverage instrumentation in any language, and a rate the operator cannot meet
  teaches them to disable the gate.
- **A mandatory burn-down schedule on the ledger** — rejected (§5.4). Non-growth is architecture; a
  rate is a business decision.
- **Reusing "retrofit" as the name** — rejected (C10). The word already means
  `reconfigure-project.sh --field` in two shipped surfaces.
- **Fixing `init.sh`'s overwrite sites as part of this work** — out of scope (§9, §12). They are
  correct for an empty directory; they are hazardous only under `--allow-existing-dir`, which is a
  separate defect with a separate fix.

---

## §12 — Honest residuals

**Deferred by decision (named, scoped, not designed here):**

1. **`init.sh --allow-existing-dir` remains a loaded gun.** It is a documented flag that lifts the
   only existence check, into a code path with twelve unguarded overwrites and a
   `git add -A && git commit --no-verify`. Adoption gives operators a correct path; it does not
   remove the incorrect one. Closing it — a guard, a refusal, or a redirect to `adopt-project.sh` —
   is a separate change and is deliberately not bundled here.
2. **The local pre-commit hook tells the operator nothing about what it found.** ⚠ **v1.1 — this
   residual is the INVERSE of what v1.0 recorded here, which was refuted (R-BF-2).** v1.0 said the
   hook "prints secret values in the clear" because it omits `--redact`. Executed: without `-v`,
   `gitleaks git --staged` writes **nothing** to stdout and only `WRN leaks found: N` to stderr —
   which the hook discards. So nothing leaks, and nothing *informs*: the operator gets `[BLOCKED]`
   and is left to find the secret unaided — no rule, no file, no line. **The fix is `-v` **and**
   `--redact` together, in one edit; `-v` alone would manufacture the leak v1.0 wrongly alleged
   (verified: 2 occurrences of the plant on stdout under `-v`).** Adjacent to this work, not part of
   it, and deliberately **not** filed as an invitation to add `-v` on its own.
3. **`bypass_audit_append` has no enum validation** — `jq -e 'type == "object"'` is the whole check,
   so `actor: "banana"` writes cleanly. The team-orchestrator design records the same finding. This
   design adds one type and does not fix the validator.
4. **The two dead enum pins.** `sast_suppression` is absent from `T6`, and
   `freshness_enforcement_snooze` is absent from both the docblock and `T6`. WP6 adds
   `adoption_event` **with a fixture that contains it**, which is more than either predecessor did,
   but does not repair the two existing holes.
5. **Archiving a git hook promotes an untracked file into version control** (§7.3). WP6 scans the
   archive for secrets before staging, which is a mitigation, not a proof — a hook can contain
   something a secrets scanner does not recognise as a secret.
6. **The Adoption Record's eight-clause contract is pinned by a lint, and eight clauses is a lot of
   surface.** Clause 5 (four-space table indentation) is the fragile one: it is invisible in rendered
   Markdown and a formatter will remove it. The lint is the only defence and it must be in the
   required set to be worth anything.

**Cannot be known before a real adoption:**

7. **Whether the S2 phase-placement ladder works on real projects.** §4.4 re-expresses an artifact
   ladder built for framework filenames over an adoptee's own evidence. **This is the least certain
   mechanism in the design.** It is also the one with the safest failure mode — the floor rule means
   a wrong answer certifies too much, not too little.
8. **Whether the certification pass is affordable.** An S1 adoption certifies all four gates: five
   scanners, six reviews, and a document set. Nothing here measures how long that takes on a real
   codebase. If it proves prohibitive, the pressure will be to weaken it, and the right response is
   to weaken the *scenario boundary* (land lower, certify less) rather than the certification.
9. **Whether operators will disposition secrets honestly.** "false alarm" with a required reason is
   still self-attested. The control is the record, not the truth.
10. **How much of the collision inventory a real project actually hits.** §1.2 is measured from the
    writers, not from field data.

**Assumptions that would falsify parts of this design if wrong:**

11. **The delta track converges on the module contract** (C1). If it lands a different shape, WP0 is
    rewritten and the driver's severability claim weakens to "one repo, one directory". That changes
    the schedule and the packaging story, not the architecture.
12. **The `adopted` flag stays readable — and one wholesale writer for `manifest.json` ALREADY
    EXISTS.** ⚠ **v1.1 correction (R-BF-1): v1.0's "there is none today" was false.**
    `fix_framework_manifest()` → `~/.claude-dev-framework/scripts/init.sh` rewrites the manifest
    wholesale from a hardcoded key set with no Solo keys. It is **missing-file-gated**, so it never
    destroys a stamp that is present — but a manifest lost to any cause is regenerated *empty of
    everything Solo wrote*, and the project silently becomes un-adopted. The writer is **upstream, in
    a different repository, outside this design's control**, so WP3's proof asserts **loud
    detection**, not prevention. There is still no lint preventing a *second* such writer, and the
    real assumption is narrower and worth stating plainly: **that the CDF manifest writer stays
    missing-file-gated.** If it ever becomes unconditional, every adopted project un-adopts on the
    next `verify-install.sh --auto-fix`.
13. **`gitleaks`' report schema is stable enough for an allowlist.** An allowlist fails safe when a
    field is added (it is dropped) and fails loud when a field is renamed (it goes missing). That is
    the right pair of failure modes, and it does assume the implementer notices the missing field.

---

## §13 — Verification appendix: commands actually run

Every command below was executed against this tree on **2026-08-02**. Output is trimmed for length
and never paraphrased. Re-run them; do not quote them.

**V1 — the gate skips entirely with no phase-state (fails OPEN).**
```
$ cd "$FIXTURE" && git init -q . && bash "$REPO/scripts/check-phase-gate.sh"; echo "rc=$?"
No .claude/phase-state.json found — skipping phase gate check.
rc=0
```
With `.claude/` present but empty: identical. With `phase-state.json` present and no `APPROVAL_LOG.md`:
```
[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.
rc=1
```

**V2 — the tier reader fails CLOSED with no manifest, and on a corrupt one.**
```
$ . "$REPO/scripts/lib/enforcement-level.sh"
$ read_enforcement_level "$FIXTURE"                      # no manifest.json
strict
$ assert_choosable "$FIXTURE"; echo "rc=$?"
[FAIL] enforcement-level: manifest missing at …/.claude/manifest.json
rc=1
$ printf 'NOT JSON\n' > "$FIXTURE/.claude/manifest.json"; read_enforcement_level "$FIXTURE"
strict
$ printf '{"deployment":"personal","enforcement_level":"no"}\n' > …; read_enforcement_level "$FIXTURE"
no
```

**V3 — `gitleaks git` scans full history; `--redact` covers `Secret`/`Match` and NOT `Message`.**
```
$ gitleaks version
8.30.1
$ grep -c "$PLANT" config.ini            # plant removed from the worktree, kept in history
0
$ gitleaks git --no-banner -f json -r plain.json .     ; grep -c "$PLANT" plain.json
2
$ gitleaks git --no-banner --redact -f json -r redacted.json . ; grep -c "$PLANT" redacted.json
0
$ jq -r '.[0] | {RuleID,File,Commit,Fingerprint,Secret,Match}' redacted.json
{ "RuleID": "aws-access-token", "File": "config.ini",
  "Commit": "42c8c76694f07fe3f280d87ea2cfb3360c5bedab",
  "Fingerprint": "42c8c76694f07fe3f280d87ea2cfb3360c5bedab:config.ini:aws-access-token:1",
  "Secret": "REDACTED", "Match": "REDACTED" }
```
Second plant, in the **commit message**, with `--redact` on. **Re-executed at v1.1 (R-BF-4) with
both plants BASE32-valid** — v1.0's message plant contained a `9`, which the rule rejects:
```
$ jq -r '.[0] | {RuleID, Secret, Match, Message}' r.json
{ "RuleID": "aws-access-token", "Secret": "REDACTED", "Match": "REDACTED",
  "Message": "rotate key, old one was AKIAVX3T6QW2ZLMK4RBS" }
$ grep -c "$DIFF_PLANT" r.json   # AKIAQZ7X4M2NPLKJ3HRD, in the diff
0
$ grep -c "$MSG_PLANT"  r.json   # AKIAVX3T6QW2ZLMK4RBS, in the commit message
1
```
**Two fixture facts, both executed, both load-bearing for §6.5:**
```
# a plant with a '9' — not BASE32 [A-Z2-7] — in a DIFF:
$ jq 'length' a.json
0
# a BASE32-VALID plant present ONLY in a commit message:
$ jq 'length' b.json
0
```
So (i) the rule is BASE32-sensitive and a careless plant silently yields nothing, and (ii) `gitleaks
git` genuinely does not scan commit messages — now confirmed with a valid key rather than inferred
from a dud one. `AKIAIOSFODNN7EXAMPLE` is separately allowlisted by gitleaks' default config and
also yields **0** findings; the first run of this experiment produced an empty report for that
reason.

**V4 — the `[WARN]` trap, quantified.**
```
$ grep -c 'issues=\$((issues + 1))' scripts/check-phase-gate.sh
66
$ grep -B1 'issues=\$((issues + 1))' scripts/check-phase-gate.sh | grep -oE '\[(FAIL|WARN|OK)\]' | sort | uniq -c
  10 [FAIL]
  34 [WARN]
```
(The 44 counted are those whose immediately preceding line carries a label; the remaining 22
increments sit further from their label or have none.)

**V5 — the upgrade re-stamp is a MERGE; foreign keys survive (C2, refuting the cited mechanism).**
```
$ printf '%s' '{"review_gate_enforced":false,"adopted_by_external_tool":true,"track":"light"}' \
  | python3 -c 'import json,sys; from datetime import date
d=json.loads(sys.stdin.read()); d["track"]="standard"; d["last_upgrade"]=str(date.today())
d["review_gate_enforced"]=True; print(json.dumps(d,indent=2))'
{ "review_gate_enforced": true, "adopted_by_external_tool": true,
  "track": "standard", "last_upgrade": "2026-08-02" }
```
And the wholesale writer that does erase it — `fix_phase_state()` in `scripts/verify-install.sh` —
emits `cat > .claude/phase-state.json << EOF` with the key set
`project, framework_version, current_phase(=0), track, deployment, poc_mode, compliance_ready, gates`
— **no `review_gate_enforced`**, and `current_phase` reset to `0`. Measured:
```
$ grep -cE '^fix_[a-z_]*\(\)' scripts/verify-install.sh
21
$ grep -cE '>[[:space:]]*\.claude/manifest\.json' scripts/verify-install.sh
0
```
**⚠ v1.1 — the second figure does NOT mean what v1.0 said it meant (R-BF-1).** It proves only that
`verify-install.sh` contains no *direct* redirect. See **V15**.

**V15 — the manifest's wholesale writer, reached by delegation (R-BF-1, re-verified here).**
```
$ sed -n '/^fix_framework_manifest()/,/^}/p' scripts/verify-install.sh
fix_framework_manifest() {
  # Drop `2>/dev/null` per the same rationale as fix_framework_clone:
  # init.sh failures (missing deps, malformed manifest) deserve a
  # visible diagnostic rather than a silenced non-zero return.
  local FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
  if [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
    bash "$FRAMEWORK_CLONE/scripts/init.sh" || return 1
  else
    return 1
  fi
}
$ grep -n 'manifest.json' ~/.claude-dev-framework/scripts/init.sh
57:  if [ -f ".claude/manifest.json" ] && command -v jq &>/dev/null; then
58:    CANDIDATES=$(jq -r '.files | to_entries[] | select(.value.candidateForGlobal == true) | .key' .claude/manifest.json 2>/dev/null || true)
224:rm -rf .claude/framework .claude/project .claude/manifest.json
416:  }' > .claude/manifest.json
439:echo "  .claude/manifest.json"
```
(Line 224's `rm -rf` is inside a generated `restore.sh` heredoc — a rollback script, **not** part of
the init path. The wholesale write is line 416.)
The key set at that write is
`frameworkVersion, frameworkCommit, frameworkRepo, localClonePath, lastSyncDate, profile,
profileInherits, files, activeRules, activeHooks, projectConfig, discovery` — **no Solo key, no
`adoption`**. Its registration is missing-file-gated:
```
  if [ -f ".claude/manifest.json" ]; then
    register_pass "Development Guardrails manifest exists"
  elif [ -d "$FRAMEWORK_CLONE/.git" ] && [ -f "$FRAMEWORK_CLONE/scripts/init.sh" ]; then
    register_fixable "Development Guardrails manifest missing" "fix_framework_manifest"
```
And every writer that touches an **existing** manifest is an additive merge. **Summary of a read, not
command output** — the filter strings are verbatim, the layout is mine:

| Writer | Filter |
|---|---|
| `scripts/check-gate.sh` | `jq --arg h "$inferred" '.host = $h'` |
| `scripts/upgrade-project.sh` (host inference) | `jq --arg h "$inferred_host" '.host = $h'` |
| `scripts/upgrade-project.sh` (BL-030 backfill) | `jq '. + {deployment: $dep, poc_mode: $pm, enforcement_level: "strict"}'` |
| `scripts/upgrade-project.sh` (BL-061 refresh) | `jq '. + {deployment: $dep, poc_mode: $pm}'` |
| `scripts/lib/currency-manifest.sh` | `soif_currency_stamp` — additive, and no-ops on a missing manifest (`[ -f "$manifest" ] \|\| return 0`) |

Reproduce the population with
`grep -n "claude/manifest\.json" --include='*.sh' -r scripts/ init.sh | grep -viE 'jq -r|jq -e|\[ -f|MANIFEST_JSON|PRODUCT_MANIFESTO'` — the unfiltered
population is ~88 lines; this exclusion narrows toward, but does not isolate,
the five-writer set — the table above is the read of record, the recipe is a
starting point (confirm-round R2-BF-1 correction).

**V16 — `gitleaks git --staged` leaks nothing without `-v` (R-BF-2, re-verified here).**
```
$ gitleaks git --staged 2>/dev/null; echo "rc=$?"        # stdout only
rc=1                                                      # <- no output at all
$ gitleaks git --staged 2>&1 >/dev/null                   # stderr only
… INF 0 commits scanned. … WRN leaks found: 1
$ gitleaks git --staged 2>/dev/null   | grep -c "$PLANT"  # stdout
0
$ gitleaks git --staged 2>&1 >/dev/null | grep -c "$PLANT"  # stderr
0
$ gitleaks git --staged -v 2>/dev/null | grep -c "$PLANT"   # stdout, WITH -v
2
```
The emitted hook is `if ! gitleaks git --staged 2>/dev/null; then` — stderr discarded, stdout empty.
The operator sees only the framework's own `[BLOCKED]` lines.

**V6 — `--reset-detection-baseline` exists; the migration wording does not (C3).**
```
$ grep -n 'reset-detection-baseline' scripts/reconfigure-project.sh
64:    --reset-detection-baseline) RECONF_RESET_BASELINE=1; shift ;;
68:      echo "       scripts/reconfigure-project.sh --reset-detection-baseline"
212:# BL-030 Task 8: --reset-detection-baseline.
231:  print_fail "Required: --field and --new (or use --enforcement-level / --reset-detection-baseline)"
$ grep -rni 'migrat' scripts/reconfigure-project.sh
186:  # local copy so the lookup honors any rollback / migration the
```
Four hits, none of them a `--help` description — the flag has **no** documented purpose string of
its own beyond the usage line.
The sentence is in `docs/superpowers/specs/archive/2026-04-28-bl030-enforcement-model-design.md`
§ 10.4, alongside *"This is critical for projects adopting the framework into an existing repo."*

**V7 — F-010's premise refuted (C5).**
```
$ bash init.sh --help-non-interactive | grep -A2 'allow-existing-dir'
  --allow-existing-dir     Boolean flag. Allow init into an existing directory
                           (otherwise: exit 1 if --project-dir already exists).
$ grep -n -A 10 '^## F-010' solo-orchestrator-followups.md
… `init.sh` refuses existing directories, so the framework cannot onboard an existing codebase.
```

**V8 — no dependency-direction lint exists (C1). ⚠ The delta-track half is time-of-execution and was
already superseded when this document was committed (R-BF-3).**
```
$ ls scripts/lint-*.sh | wc -l
14
$ grep -rni 'dependency.direction\|severable\|module-shape' --include='*.md' --include='*.sh' .
                                    (no output)
```
At first execution:
```
$ git diff --stat main...docs/delta-track-design      ->  (empty)
$ git log --oneline docs/delta-track-design -1        ->  6449838 (== main)
```
Re-executed before the v1.1 fold:
```
$ git log --oneline docs/delta-track-design -2
6fc3136 docs(designs): delta-track v1.1 — review-r1 folded; the exit-2 claim was docblock-trusted
5dcbe86 docs(designs): the post-MVP Delta Track v1 — Karl's 2026-08-02 decisions transcribed
$ git diff --stat main...docs/delta-track-design | tail -3
 docs/INDEX.md                             |    7 +-
 docs/designs/2026-08-02-delta-track-v1.md | 1189 ++++++++++++++++++++
 2 files changed, 1195 insertions(+), 1 deletion(-)
```
Both branches add a Designs row to the same `docs/INDEX.md` paragraph, so **a conflict at merge is
guaranteed and expected**; both rows belong.

**V9 — no `adopted` state anywhere; the namespace is free.**
```
$ grep -rn 'adopted' --include='*.sh' --include='*.tmpl' --include='*.json' . | wc -l
5
```
All five are English prose in comments ("adopted npm test", "taxonomy adopted from").

**V10 — the ZDR taxonomy and its blocking arm.**
```
$ grep -n 'zdr_taxonomy=' scripts/check-phase-gate.sh
  zdr_taxonomy="public internal confidential pii financial health regulated"
```
Guarded by `if [ "$current_phase" -ge 2 ]`, three `[FAIL]` arms, each incrementing `issues`.

**V11 — Phase-3 scanners and the nine checklist steps are different lists.**
```
$ bash scripts/run-phase3-validation.sh --list
  semgrep-full-tree    [real] Full-tree Semgrep SAST
  license              [real] License compliance
  snyk                 [real] Snyk dependency scan
  zap-dast             [real] OWASP ZAP DAST
  threat-model         [real] Threat-model verification
$ grep -n 'PHASE3_STEPS=(' scripts/process-checklist.sh
40:PHASE3_STEPS=(integration_testing security_hardening chaos_testing accessibility_audit
   performance_audit contract_testing results_archived pre_launch_preparation legal_review)
```

**V12 — the Adoption Record's two structural clauses, executed.**
Clause 5, running `_cpg_gate_has_evidence`'s own awk + grep pipeline over a candidate record:
```
$ printf '## Adoption Record\n\nCovers Phase 0 through Phase 1 certification.\n| **Date** | 2026-08-02 |\n' \
  | awk -v h="Phase 0.*Phase 1" '$0 ~ h {f=1; next} f && /^## / {exit} f' | head -15 \
  | grep -E '^\|[[:space:]]*\**[[:space:]]*Date[[:space:]]*\**[[:space:]]*\|' | head -1 \
  | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"; echo "rc=$?"
rc=0        # the record WOULD be read as Phase 0→1 gate evidence
```
The identical content with the table row indented four spaces:
```
rc=1        # safe
```
Note that the window opened on a **prose** line ("Covers Phase 0 through Phase 1…"), not a heading —
which is clause 1's whole reason for existing.

**And the third cell, added at v1.1 (R-BF-5) — the one that re-aimed WP7's mutation.** With clause 1
honored (no `Phase 0 … Phase 1` line anywhere in the record), the awk never opens a window at all,
so the Date-row indentation becomes irrelevant:
```
$ printf '## Adoption Record\n\nCovers certification of the gates below.\n| **Date** | 2026-08-02 |\n' \
  | awk -v h="Phase 0.*Phase 1" '$0 ~ h {f=1; next} f && /^## / {exit} f' | head -15 \
  | grep -E '^\|[[:space:]]*\**[[:space:]]*Date[[:space:]]*\**[[:space:]]*\|' | head -1 \
  | grep -qE "[0-9]{4}-..-.."; echo "rc=$?"
rc=1        # UNINDENTED, but clause-1-compliant -> still safe
```
The three cells together are the actual result: **`rc=0` only when clauses 1 and 5 are violated
jointly; restoring either one alone returns `rc=1`.** The clauses are redundant by design, and no
single one of them is provable in isolation against this reader — which is why WP7's v1.0 mutation
could never have gone RED.

Clause 8, the unbounded Pre-Phase 0 window on the shipped org template:
```
$ grep -A 30 "Pre-Phase 0" templates/generated/approval-log-org.tmpl | wc -l
      31
$ grep -A 30 "Pre-Phase 0" templates/generated/approval-log-org.tmpl | grep -c '^## '
       3
```

**V13 — the adoption stamp's filter is additive (§8.5).**
```
$ printf '%s' '{"host":"github","deployment":"personal","currency":{"schemaVersion":1}}' \
  | jq --argjson adoption '{"schemaVersion":1,"scenario":"completed"}' '.adoption = $adoption'
{ "host": "github", "deployment": "personal",
  "currency": { "schemaVersion": 1 },
  "adoption": { "schemaVersion": 1, "scenario": "completed" } }
```

**V14 — the lints, before this document landed.**
```
$ bash scripts/lint-doc-anchors.sh --strict-refs
OK: no broken in-document anchors across 99 markdown file(s) under docs.
$ bash scripts/lint-bl-markers.sh
OK: 346 marker token(s) resolve to backlog entries and 420 prose citation(s) resolve to live markers.
```

---

## Self-review pass (fresh-eyes checklist)

- **Every commissioned element present?** §0 traceability with per-decision attribution to the
  2026-08-02 session; the plain-English opening; the certification-pass tables (three kinds at §5.2,
  the per-gate mapping at §5.3); the scanner report schema (§8.2, author-proposed); the archive and
  MANIFEST layout (§7.2); the WP build plan with dual-direction mutation intents (§10); honest
  residuals (§12); and the verification appendix of commands actually run (§13).
- **Are the settled decisions designed within, not relitigated?** Yes. D1–D6 appear in §0.1 as
  premises and are never re-argued. Where the repository corrected the *framing* — including two
  mechanisms Karl cited by name (C2, C3) — the correction is flagged in §0.3 and designed for, and
  in both cases the correction **strengthens** the decision rather than threatening it.
- **Is implementation freedom marked?** Yes. Every author-proposed mechanism is labelled at its
  point of use: the tool name and module contract (§3.3), the evidence set (§4.2), the phase ladder
  (§4.4), the ratchet (§5.4), the redaction projection and disposition shape (§6), the archive layout
  and detector rules (§7), the report schema, the stamp contents, the provenance header, and the
  `adoption_event` single-type choice (§8).
- **Is enforcement honestly tiered?** Yes. The hook description is advisory (§7.2); the SDLC detector
  is report-only (§7.4); the ratchet's three limits are stated (§5.4); kind (b)'s weakness relative to
  a pre-build review is conceded rather than argued away (§5.2); and §5.3 states plainly that for a
  personal deployment kind (c) waives **nothing**, because the control was never running.
- **Every "exists today" claim anchored — and executed?** Anchored and executed, yes — **and
  review-r1 still refuted two of them (§0.2), both because a narrow grep was allowed to carry a wide
  inference.** Do not read the current claim set as self-certified: it is the set that survived one
  adversarial pass, with both refutations independently re-executed by this author before folding.
  Two proofs in §10 were also found **incapable of failing** (WP3's regression, WP7's mutation) and
  re-aimed; a proof that cannot go RED is the same defect class as a claim that was never run.
  Anchors are
  function names (`create_project`, `fix_phase_state`, `read_enforcement_level`, `assert_choosable`,
  `verify_init`, `check_named_row`, `validate_approval_fields`, `_cpg_gate_has_evidence`,
  `soif_write_precommit_hook`, `_upgrade_snapshot_pre_mutation`, `_bl099_sync_precommit_hook`,
  `tdd_terminal_enforce`, `_bl072_tier_bypassable`), marker comments (`# BL-073-ESCALATE`,
  `# BL-084-TIER-KEY`, `# BL-109-CURRENCY`, `# BL-204-PREFILL-READ`, `# BL-099-DOC-GUARD`,
  `# BL-113-NO-LAUNDER`, `# BL-114-F1-INTERMEDIATES`, `# BL-116-PUSH-GATE-SCOPE-BEGIN`,
  `# BL-126-ATTEST-CONSULT-BEGIN`, `# BL-138-APPROVAL-WINDOW`, `# BL-104-MANIFEST-ARM`,
  `# BL-107-RUST-INLINE-TESTS`, `# BL-072-TDD-ENFORCE`, `# BL-115-ATTORNEY-ENTRY`,
  `# BL-140-ARCHIVE-FRESH`), or named document sections. No bare `file:line` anywhere.
- **Unresolved placeholders?** None. Every underdetermined choice is either a decision table with one
  recommendation and stated alternatives (shape §3.1/§3.3; scenario evidence §4.2; collision buckets
  §7.1; redaction fields §6.2; audit-type count §8.9), or is named in §12 as an explicit deferral.
- **Biggest attack surface for the reviewer.** §4.4's phase-placement ladder (re-expressed over
  evidence it was not built for, and flagged as the least certain mechanism in the design) and §5.5's
  affordability — an S1 certification pass is five scanners, six reviews and a document set, and
  nothing here has measured that against a real codebase. Both are flagged rather than defended.

---

## Questions for the reviewing architect

Nine, each attached to a decision this design can still change.

1. **The S2 ladder (§4.4).** Re-expressing a framework-artifact ladder over an arbitrary codebase's
   own evidence is the weakest mechanism here. Is the floor rule (interview may only lower) a
   sufficient safety property, or should S2 simply *ask* for the phase and use evidence only to
   challenge an implausible answer?
2. **Certification affordability (§5.5).** If a real S1 adoption takes days rather than hours, which
   should give — the scenario boundary (land lower, certify less) or the certification depth?
3. **The ratchet's shape (§5.4).** Non-growth plus touch-repays, with no burn-down rate. Is
   "untested set may not grow" enough to be worth the enforcement cost, or does it need a shrinkage
   obligation to be more than bookkeeping?
4. **The CI carve-out's cost (§7.4).** Framework CI at its own filename means an adoptee runs two
   pipelines, possibly duplicating tests and doubling minutes. Is that acceptable, or should adoption
   offer a guided merge into their existing pipeline as an option?
5. **The archive's new exposure (§7.3).** Archiving `.git/hooks/*` into a tracked directory promotes
   untracked files into history. Is a pre-staging secrets scan sufficient, or should the archive be
   gitignored — at the cost of losing the disclosure record from the repository?
6. **Secrets tiering (§6.3).** BLOCK at strict, loud warning at personal. Should a *live, unrotated*
   high-confidence finding block at **every** tier, on the grounds that a leaked production
   credential is not a matter of enforcement posture?
7. **Kind (b)'s honesty (§5.2).** Marking only the ordering fact on a genuinely-held review is the
   smallest honest statement available. Is it small enough — or does a reviewer reading the log a year
   later need the marker to be louder?
8. **Module severability (§3.3).** WP0 must converge with the delta track's module contract. **As of
   v1.1 that track has landed (`5dcbe86`, `6fc3136`) — it is no longer an empty branch (C1)**, so
   convergence is now a real comparison rather than a wait. Does the adoption build adopt the delta
   track's contract as written, propose a joint revision, or proceed provisionally and reconcile at
   the first severance?
9. **The one rule we have not written.** What is the control your environment mandates that this
   adoption flow would fail on day one — and would it be a configuration, a new certification kind,
   or a reason adoption does not fit at all?

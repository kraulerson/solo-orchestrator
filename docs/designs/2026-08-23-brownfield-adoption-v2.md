# Brownfield Adoption — architecture design v2

## Document Control

| Field | Value |
|---|---|
| **Document ID** | ADOPT-002-ARCH |
| **Version** | **v2.2, 2026-09-17** — amended in place, measured at `579b0b0`, after two independent reviews of v2.1 on 2026-09-16 (§0.3): **two RULINGS recorded — Karl's, 2026-09-17 — R1 (hooks: refuse at step 0 under `core.hooksPath` or off the repository top level; the *gates are live* sentence becomes DERIVED) and R2 (a recorded `adopted-in-production` exemption lets an adopted project open a delta below phase 4)**; the senior-architect review's thirteen design defects (A1–A13) and nine buildability gaps (B1–B9) amended, each mechanism author-proposed unless it is one of the two rulings (§8.3c indexes them); three open contributor issues taken into account (#418, #385/`## BL-277:`, #404/`## BL-274:`); two new sections (§2.1 environment shapes, §9.1 invariants); three small new packages (WP9c, WP9d, WP12c) and §10's WP10b/WP11/WP12a/WP12b/WP7 cells re-cut. **No settled decision changed: D1–D10's DECISION cells, §0.2 and §8.3a's A1–A8 are byte-identical before and after (§13-V44, measured — the D2 and D5 rows' author-proposed cells each gained a clause); the two rulings are recorded in §0.1a, not folded into §0.1's table.** Four defects were MEASURED on `main` at `579b0b0` and are not fixed here (§13-V32–V34): hooks written where git never looks under `core.hooksPath`; the stamped-but-uncommitted window with no finish route; an adoptee's own `PROJECT_INTAKE.md` and `.claude/intake-progress.json` overwritten with no archive row; a case-variant collision named at a path git's index does not hold. **v2.1, 2026-09-16** — amended in place after fifteen days of `main` (measured at `01b66e3`): WP9b, WP10a, `## BL-225:`'s before-any-write half, `## BL-288:`, `## BL-268:`, `## BL-253:` and `## BL-251:` reconciled, and **one ruling recorded** — Karl, 2026-09-16, on the `scanned-partial` status `## BL-288:` coined, which adds ONE ROW to D2's table (§6.1, §6.1a). **D2's principle is unchanged; no other settled decision, decision table, or WP boundary changed** (§0.3). v2.0, 2026-08-24; reconciled pre-landing 2026-08-28, and again across four passes on 2026-08-31 (§0.3). **Second pass, 2026-09-16 (later the same day):** the merged-main adversarial sweep of `7b88c2e` folded in (twelve fix-now and refuted items, one labelled residual) — claims PR #415 had overtaken one merge after this amendment, one vacuous WP10b proof cell, WP12a's unannounced re-aim of a shipped pin, the gitleaks floor (`## BL-289:`), two residuals §12 had missed (§0.3). Supersedes ADOPT-001-ARCH (`docs/designs/2026-08-02-brownfield-adoption-v1.md`) in full. |
| **Supersedes — and overturns** | **This is the first document in this feature's history that overturns a settled decision, and it says so here rather than in a footnote.** v1's §0.1 lists the scenario chooser (v1-D2, Karl's verbatim question) among the decisions carried into that design; v1's every amendment was able to say *"no settled decision, decision table, or WP boundary changed."* **This document cannot say that and does not.** Karl's D4 (2026-08-23, recorded in `## BL-242:`) deletes the chooser outright — not demotes it — and D5/D6 redraw the work-package boundaries. §0.2 maps every v1 decision to its v2 disposition: carried, re-derived, or overturned. |
| **Classification** | Product architecture — normative-once-reviewed for the build. **Six adversarial architecture rounds ran before v2.0 landed** (r1: block on two structural findings; r2: B1 dissolved by execution, block on B2; r3 and r4 below; r5 cleared with four proof gaps and r6 found two residues of fixing them — §0.3's ninth and tenth passes; this cell said two until 2026-09-16, then four for an hour), and two independent reviews of the merged v2.1 ran on 2026-09-16 (§0.3, second pass). B2 and r2's three new gaps are answered in §8.3a as **A1–A4**, and **r3 reviewed those answers**: B2 closed, seven majors against the A-layer's edges and proofs — including a preflight arm that would otherwise have let adoption silently corrupt an already-scaffolded project. r3's findings were folded into the prose in a seventh pass and into §10's build cells in an **eighth**, after r4 found the seventh had edited the essays and left the instructions untouched. |
| **Audience** | (a) the adversarial design reviewer this document must survive; (b) the implementer of the work packages in §10 |
| **Subject** | **Brownfield adoption, second architecture** — an existing codebase enters Solo Orchestrator through four acts: a read-only survey, a deterministic shell preparation that lands the project at phase 0, a model-driven assessment, and a documented plan the project proceeds from — **starting at the beginning, with no rung derived by anyone** (D10). Adoption **assesses** rather than asking the operator to classify the project; it asks exactly one thing — who the project is for (D9). |
| **Companion documents** | ADOPT-001-ARCH (superseded; kept as the record of the first build and of §-citations in shipped code — see §0.2) · `## BL-242:` in `solo-orchestrator-backlog.md` (the D1–D10 decision record this document designs from) · `docs/adoption.md`, `docs/scout.md` (the shipped user-facing pages; WP9a revised `docs/adoption.md`'s chooser sections and phase-0 landing, and the rest of both pages' v2 revision is §10-WP12b's — at `01b66e3` `docs/adoption.md`'s summary table filed the secrets stop under an unsplit `WP10`, had no row for the tool resolution WP10a built, and its write-set prose said 77 files and 68 scripts where §13-V27 measures 79 and 70; PR #415 (`b0d3f13`, `2e07493`, merged `7b88c2e`) corrected all three one merge after this amendment; §13-U(v2.1)) · `docs/messaging-standard.md` (the presentation contract D8 makes binding) · `docs/module-contract.md` (M1–M5) · SOI-002-BUILD (`docs/builders-guide.md`) |
| **Status of the thing described** | **WP9 (9a AND 9b) AND WP10a ARE BUILT; WP10b, WP11, WP12a, WP12b AND WP7 ARE NOT — and the two `scanned-partial` arms Karl ruled on 2026-09-16 (§6.1a) are WP10b's and NOT BUILT. `## BL-225:`'s before-any-write half — §10's sequencing precondition — is BUILT.** Measured on **2026-09-16** against tree `01b66e3` (§13-V17–V28) and **RE-RUN on 2026-09-17 against `579b0b0` (§13-V29) — every derivation returned what this row says; `## BL-289:` and the v2.2 packages (WP9c, WP9d, WP12c) are NOT BUILT either, and the four defects §13-V32–V34 measure are live.** This row said *"WP9 IS BUILT — 9a AND 9b; NOTHING ELSE OF v2 IS"* from 2026-09-01 until this amendment, and it was stale from **2026-09-04**, the day WP10a merged (PR #373) — the fifth time in this document's life the row has lagged the tree, and for the reason it keeps giving: nobody re-ran it. It is a **set of derivations**, each printed with its output in §13-V19; re-run them, do not quote them. (1) *What is still unbuilt* — §1.2's recipe → **7** `adopt_stub_*` functions actually called, unchanged in count AND membership since 2026-09-01. (2) *The chooser is gone* — `ls scripts/lib/adopt/` lists `adopt-evidence.sh` and no `adopt-chooser.sh`; Karl's question, by the fragment `built out and needs`, resolves in **four** tracked files, none of them under `scripts/`, `docs/adoption.md` or `docs/scout.md` (the two designs, the backlog entry that quotes him, and the WP9 suite that must spell the sentence to assert its absence — read the hits, do not count them); the VERBATIM sentence resolves in **two** — the v1 design and the WP9 suite, exactly C2's allowlist — because this document and the backlog quote it ellipsised. (3) *Tool resolution is BUILT — WP10a.* **The 2026-09-01 derivation is RETIRED, not repaired**: it counted `resolve-tools` mentions and predicted 1-and-a-comment; the count is now **2**, and the second is the executed path `_adopt_resolver_path` prints in `adopt-tools.sh`, a file that did not exist when the recipe was written. The replacement measures the built thing: `grep -c 'adopt_resolve_tools "$root" "$report"' scripts/lib/adopt/adopt-state.sh` → **1**, the call at `# BL-242-RESOLVER-CALL`. (4) *`scripts/resume.sh` knows nothing of adoption* — `grep -c 'adopt' scripts/resume.sh` → **0**; the fifth branch is still WP12a's. (5) *A1's preflight is live* — `grep -on 'BL-242-PREFLIGHT-ARM[A-Z0-9-]*' scripts/lib/adopt/adopt-state.sh` → four markers, the fourth being arm 3's third signal; read them, do not count them. (6) *A4's log is written FIRST* — `_adopt_state_order` emits `approval_log phase_state intake manifest`. (7) *The write phase is REHEARSED before the first write* — `# BL-225-PREWRITE-CALL` and `# BL-225-WRITE-PHASE-REAL` are both in `adopt-state.sh`, and `_adopt_write_phase` has exactly those two callers (§8.2a). (8) *The secrets STOP is NOT built — WP10b* — `adopt_stub_secrets_disposition` is in derivation (1)'s output, `adopt-tools.sh`'s own header says it *"makes no stop/proceed decision"*, and the stub's `scanned-partial` arm prints and `return 0`s — so the 2026-09-16 ruling has no implementation yet (§13-V28). (9) *Framework-wins is NOT built — WP11* — `adopt_install_framework` still `continue`s on `[ -e "$dst" ]` (§13-V23). (10) *The two 2026-09-17 rulings are NOT built* — `git grep -c 'adopted-in-production' -- scripts/` → nothing, and `grep -c 'hooksPath' scripts/lib/adopt/adopt-state.sh` → **0** (§13-V29); the hook is still written to a literal `.git/hooks` and the *live* sentence is still unconditional (§13-V32). **When any derivation stops returning what this row says, this row is stale.** Three counts moved since 2026-09-01 and are recorded here as measurements with a date: the framework's install set is **70** files (was 68 on 2026-09-01 — `scripts/check-changelog.sh` and `scripts/check-session-state.sh`, added to `init.sh`'s copy list on 2026-09-08 by `## BL-254:`, PR #378; §13-V20 — four distinct values, 65/67/68/70, in twenty-three days), the Scout report's `schemaVersion` is **2** (was 1; `## BL-288:`), and `scripts/lib/adopt/` holds **eight** files (was seven). **§8.7a's write set was RE-MEASURED BY EXECUTION on 2026-09-16: 79 files — 70 under `scripts/`, the same nine elsewhere** (§13-V27; **80 and ten once WP9d's `write_set` stage lands — `.claude/adoption/write-set.txt`, measured 2026-09-18 as 84 paths on the window fixture, which is 83 written plus itself**); the 2026-09-01 value of 77 was falsified by the install set's growth, not by anything adoption did. |

**Provenance.** Ten architecture decisions — **D1 through D10** — are settled and recorded in
`## BL-242:` in `solo-orchestrator-backlog.md`. **D1–D8** were settled **by Karl on 2026-08-23**
(D2 refined 2026-08-25, and D2's table gained one ruled row on 2026-09-16 — §0.1, §6.1a); **D9 and
D10 on 2026-08-31**, each ruling a question this document had
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
failure is an unverified claim reported as verified. Claims added by the v2.1 amendment were
executed on **2026-09-16** against `01b66e3` and appear under §13's v2.1 heading (V17–V28), with
their own unverified list in §13-U(v2.1). Claims added by the v2.2 amendment were executed on
**2026-09-17** against `579b0b0` and appear under §13's v2.2 heading (V29–V45), with their own
unverified list in §13-U(v2.2); the two rulings themselves are recorded from the maintainer's
brief and are listed there as NOT independently verified. One structural caveat applied to the 2026-08-24
measurements: `## BL-242:` then lived on the branch `docs/bl242-brownfield-filing`, **not** on the
branch those measurements were taken from (`feat/messaging-standard`) — §0.4 states what that meant
for which claims were whose, and that it has been historical since the filing merged.

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

**A third case was found on 2026-09-12 and decided on 2026-09-16.** If the copy of the project on
disk holds only its most recent commits — the shortened form many build servers hand out — the
scanner can read only those, and it now says so plainly instead of calling it a full scan. On a
**company's** project that is a stop, with no way round it: fetch the whole history, scan again,
and deal with whatever it finds. On your **own** project you may acknowledge it and carry on — and
that acknowledgement is written down, with what was and was not read, and adoption refuses to
continue if it cannot write it down. Whatever the partial scan did find is shown either way; a
partial scan is never presented as a clean one. **Neither half is built yet** — today adoption
tells you and decides nothing (§6.1a).

**Where the commit-time check gets installed — decided 2026-09-17.** The framework's commit-time
check is a small program git runs before it accepts a commit, and git looks for it in exactly one
place. Some projects tell git to look somewhere else — a folder shared across repositories, or one
the project itself tracks — and some folders are not the top of their repository at all. Until now
adoption installed its check in the usual place regardless and told you it was live; measured on
today's code, git then ran nothing at all on the next commit. From now on adoption **refuses to
start** in those situations, says exactly what it found, and tells you the fix: point git back at
the usual place, run adoption from the top of the repository, or install the check yourself. And
the sentence *"the checks are live"* is only printed when adoption has looked at the place git
will read from and found its check there.

**Already in production — decided 2026-09-17.** Adoption starts every project at the beginning,
and that does not change. But a project that is already serving real users has one need the
beginning does not cover: an urgent fix has to go out today, and the framework's rule for that — a
hotfix, with a written-up account of what happened afterwards — only opens once a project has
reached the end of the ladder. So the assessment now asks one more question: *is this software in
production?* If you say yes, that answer is written into the project's record, and it unlocks
**only** that hotfix route, for that project alone. Every other gate stays exactly where it was;
nothing is marked as done. Not built yet either.

**For a company's project, adoption reads the history itself.** You can hand adoption a survey you
ran earlier, and it uses it for everything it fills in. The one thing it will not take on trust is
the leaked-password decision: for that it re-reads your history itself, under the framework's own
detection rules — not a rule file or an ignore list your project happens to carry, which today can
silence the scanner completely (measured, §13-V35). What you told adoption about *who the project
is for* is still taken at your word; that is the one thing nothing can check.

**Four things were found broken on today's code while writing this amendment, and none is fixed
by it** (§13-V32–V34): the check installed where git never looks, described above; an adoption whose
commit your own git hook rejects is left half-finished with no way to finish it, and running it again
tells you the project is already adopted; a project that already had its own intake file has that
file overwritten without a word; and on a Mac, a file of yours whose name differs from a framework
file's only by capitalisation is reported under a name the project does not have. Each has a small
package (§10-WP9d, WP11) and a proof.

Some of your files — scripts and documents whose names the framework
claims — will be **replaced by the framework's versions**, with yours archived and every moved
path named, because a half-wired framework that stays silent about it is worse than an honest
swap. That includes your feature list, bug list and release notes: the originals are kept in the
archive, you are told exactly where each one went, and you are invited to copy anything worth
keeping into the new files. **Nothing is deleted, and nothing is moved silently.** If your own build calls one of those scripts, it will break at adoption, visibly, rather
than months later, silently — and the notice tells you exactly which files to look at.

**Options.** Continue the build in §10's order — the small driver repairs first (WP9d: the four
defects measured today), then the tier-scoped secrets stop (WP10b), now that every row of its table
is ruled, then the two archive classes, then the assessment. Or pause:
the built half keeps working and keeps announcing its gaps at every run. Or revisit a settled
decision — none was found to need it; the record was measured unchanged (§0.3, v2.1).

**Recommendation: build WP9d, then WP10b, on this design as it stands.** WP9d first because it is
small and every one of its five items repairs something measured broken on today's code — a check
reported live that git never runs is a false receipt, the class this framework refuses everywhere
else. Then WP10b. The reasoning: the decisions are unchanged and were measured unchanged; the one defect this recommendation used to put first —
a half-staged repository with a message claiming nothing was committed (`## BL-225:`) — is fixed on
both halves, so adoption now rehearses every write on a copy and refuses before the first real one;
the scanner is installed by adoption itself; and the secrets stop's table has no unruled row left
(§6.1a, ruled 2026-09-16); and the two questions the architect's review left for Karl were ruled
on 2026-09-17 (§0.1a). Nothing this design needs is waiting on a decision. One thing that is not
this design's — whether a company with a single technical authority can ever satisfy the
governance rule that needs a second one (`## BL-274:`) — is recorded as a known limit (§2.1), not
hidden inside a package.

**If you do nothing.** Nothing breaks today. The driver keeps announcing its own gaps at every
run, the seven unbuilt capabilities stay unbuilt, a shortened history keeps being reported honestly
and treated as nothing in particular, and the status row of this document goes stale again the day
the next package merges — which it has now done five times, always because nobody re-ran it. And
the four defects measured today stay live: a project that tells git to look elsewhere for its
checks is told they are live when they are not; an adoption whose commit is rejected by your own
hook is left half-done with no way to finish; your own intake file, if you had one, is overwritten
without a word; and a capitalisation-only name clash is reported under the wrong name.

---

## §0 — Decision traceability

### §0.1 — Settled decisions carried into this design

Ten, all Karl's, all recorded in `## BL-242:` in `solo-orchestrator-backlog.md`: **D1–D8 on
2026-08-23** (D2 refined 2026-08-25), **D9 and D10 on 2026-08-31**. This document designs **within** them. Each row names where the
design work lives and what remains author-proposed.

| # | Settled decision (Karl — D1–D8 on 2026-08-23, D2 refined 2026-08-25, D9 and D10 on 2026-08-31) | Designed in | Author-proposed inside it |
|---|---|---|---|
| **D1** | **Colliding scripts: archive theirs, install the framework's, say so.** REVERSES the shipped behaviour, where `adopt_install_framework` skips any path with `[ -e "$dst" ]` and the operator's file wins silently. The notice must name **every archived path, not a count**, plus a standing warning that **replacing a framework script with their own may break the framework**. `scripts/` becomes an archive class exactly as D3 makes documents one. | §7.1, §8.2 | The receipt check between archive and install; the notice's exact shape (§7.1) |
| **D2** | **Secrets are TIER-SCOPED: an ORGANIZATIONAL adoption STOPS, a CASUAL PERSONAL one WARNS LOUDLY and carries on.** Karl, 2026-08-23: *"Stop adoption until acknowledged with a reply of having been corrected or the risk is being accepted"*; refined 2026-08-25: *"Keep warn loudly for casual personal projects. Organizational projects are always a stop."* The stop lifts only when every finding carries a recorded acknowledgement, and an acknowledgement that cannot be recorded is refused (BL-072's shape, reused by `## BL-233:` for `SOLO_MCP_ACCUM_ATTESTED`). The tiering axis is **`deployment`**, not `enforcement_level`, which **overturns v1 §6.3 as written** — derived on 2026-08-25, not ruled a second time (§6.1). A scan that never ran is **not an acceptable state at either tier**: Karl — *"Why wouldn't the secrets scan run? That should never be an option."* **The two not-scanned statuses were ruled apart on 2026-08-31, and they differ**: `tool-unavailable` is a hard refusal at `organizational` and escapable on a recorded acceptance at `personal` (*"Yes on personal, no on organizational"*); `scan-failed` is *"action as if it ran"* — a hard refusal at `organizational` (*"it cannot continue as it's required"*) and a **loud warning that carries on** at `personal`. §6.1's ladder and §6.4 carry the reasoning. **AMENDED 2026-09-16 (Karl): a FIFTH status, `scanned-partial` — a shallow clone, coined by `## BL-288:` on 2026-09-12 — takes the split.** At `organizational` it **STOPS with no escape** and the refusal prints the unshallow remedy; at `personal` the operator **may acknowledge and continue**, the acknowledgement is **RECORDED** in §6.3's shape — named accepting person, reason, date, plus the scope and commit count the report already carries (the fields are author-proposed, §0.1; the ruling names none) — and **refused if it cannot be recorded**; the findings the partial scan did produce are printed either way — that they are printed redacted and the partial scope stated in those words is author-proposed (§0.1), not the ruling's. Karl's words: *"go with the split."* The shape is §6.4's `tool-unavailable` ruling with the findings added. This adds ONE ROW to D2's table (§6.1) for a status that did not exist when D2 was written; D2's principle — tier-scoped, recorded, never silent — is unchanged (§6.1a). | §6 | The disposition file's location and shape; the re-scan-after-install mechanic (§6.2); the warn arm's record; the `scanned-partial` acknowledgement's record — §6.3's shape, §6.1a; **(v2.2) that the STOP's input is a scan Act 2 ran itself, under the framework's own rules, whatever report was handed in — §6.2b, author-proposed, not part of D2** |
| **D3** | **Project documents: written to the framework's documentation requirements** — adapted or merged from what the project has, or written new where the assessment shows merging would carry a false picture forward. **Originals archived in the project for historical purposes.** With D1, this makes documents and `scripts/` the third and fourth classes of the collision archive — one mechanism serving four cases. **Reach ruled 2026-08-31: it covers `FEATURES.md`, `BUGS.md` and `RELEASE_NOTES.md` too — overturning v1 §7.5 — and the operator must be TOLD, by name, that content can be retrieved from the archive and added to the new files** (*"All previous info is archived and the user informed so that they may retrieve or add to the new proper framework files."*). | §7.2, §7.3 | The framework-document name set's derivation; the adapt-versus-replace criterion (§7.2); the notice's phrasing — its CONTENT is bound (§7.2) |
| **D4** | **THE CHOOSER IS DELETED, NOT DEMOTED.** No completed/in-flight question, and no "was an SDLC framework used" question either — **those two, and no others.** Karl's reasoning, verbatim, which is the load-bearing part: ***"I think trusting an end user to know what's needed is a mistake considering they are using the orchestrator BECAUSE they are not already following a proper SDLC."*** This **overturns v1-D2**, which v1 §0.1 lists among its settled decisions — see §0.2. *(`## BL-242:` heads this decision **"Adoption assesses; it does not ask."** That is the entry's headline, **not Karl's words** — the entry marks his quote separately — and reading it as a general principle is what produced the error D9 corrects. D7, also Karl's, requires asking.)* | §4 | **Nothing about the two dropped questions.** The claim that stood here — *"the deletion's blast radius is enumerated, not chosen"* — was **false, and is exactly what D9 corrects**: the enumeration silently added a third question the ruling never reached (§4.2) |
| **D5** | **FOUR ACTS**, and the split is **forced, not chosen**: the evaluators are model-driven and the driver is shell, so adoption cannot be one process. (1) **SURVEY** — Scout, read-only. (2) **PREPARE** — shell: tool resolution against the matrix; the secrets stop; the test-debt census **before** the install; the collision archive **before any writer**; install; **land at PHASE 0 PROVISIONALLY**; commit; hooks last. (3) **ASSESS** — Claude Code via `scripts/resume.sh`: the requirements interview and all evaluators. (4) **PROCEED** — documents written, plan presented, Build Loop, **from the beginning** (D10 corrects this step, which read "rung from evidence" and was never Karl's; D10 also drops the *provisionality* from step 2's landing — it is simply phase 0, because nothing was ever going to promote past it). **The provisional phase-0 landing is load-bearing**: it preserves the promise `adopt_main` already prints, so **a project cannot land high by abandonment** — the scheme cannot express that outcome. | §3, §8 | The act-boundary artifacts; the `resume.sh` branch predicate; the assessment brief's home (§8.5) — *the brief was DROPPED in v2.2 (A6, §3.7): the prompt WP12a renders and the finisher's `.claude/adoption/` home take its place; the review's R-13* |
| **D6** | **"Rebuild" is a VERDICT adoption returns, not work adoption does.** A rebuild is a Phase 0 intake, an architecture phase, a Build Loop and gates — Solo Orchestrator's **ordinary path** — so the verdict **exits into machinery that already exists**, with the intake pre-filled from everything the assessment learned. Placement, not disagreement; a bounded feature, not an unbounded one. | §5.4 | The pre-fill mapping from assessment record to intake sections |
| **D7** | **"Wrong technology" is only a finding RELATIVE TO STATED REQUIREMENTS**, and the requirements come from the interview: users, availability, exposure, scalability, data sensitivity. Karl: *"It should be part of the interview to decide that and present the reasoning to the user."* The guarded failure mode is specific: an evaluator with good taste reads the STACK and says "rebuild this in Python" without reading the REQUIREMENTS. | §5.2, §5.3 | The interview's question set beyond Karl's five; the fitness-verdict record shape |
| **D8** | **The verdict's presentation is part of the requirement**: the full technical account AND the same content as plain English with **pros, cons, options, and a recommendation with reasoning**, so a non-developer can decide. This is the communication contract Karl already requires of agents in this repository, generalised into the product — and it is what makes D6 honest: *the reasoning IS the deliverable*; a rebuild delivered as an unexplained conclusion is indistinguishable from a refusal. Since v1, this contract has a shipped, binding spelling: **`docs/messaging-standard.md`** — Part 1's five-part format and Part 2's controlled vocabulary. | §5.5 | The verdict artifact's file shape and the check that pins its two halves |
| **D9** | **THE AUDIENCE QUESTION SURVIVES D4, RE-PURPOSED AS A TIER QUESTION** (Karl, 2026-08-31). *"Who is this project for?"* — *"Just me, or me and a few people I know"* / *"A company, a client, or people who are paying for it"* — **stays**, verbatim, with its call site. `ADOPT_CHOOSER_QUESTION`, `adopt_ask_scenario` and the `claimed` operand still go, exactly as D4 says. What changes is its **job**: it stops being an input to placement and becomes the **sole producer of `deployment`** — the value D2's tiering reads (§6.1) and the key `# BL-221-ADOPT-TIER-KEYS` requires an adopted manifest to carry. **This rules on a question D4 never reached**, and is not a softening of D4: D4's reasoning is about self-reported *process maturity*, and who is paying is a fact **no evidence can determine**. | §6.5, §4.2, §8.2 | Nothing — the question text, both answers and the call all ship today and are kept verbatim |
| **D10** | **AN ADOPTED PROJECT STARTS FROM THE BEGINNING. NO RUNG IS DERIVED, BY ANYONE** (Karl, 2026-08-31). *"The project gets ingested and starts from the beginning to ask the user about what it is and what it's supposed to do"*, restating D4's reason in his own words on the same day: *"we can't trust the user to know how to follow an SDLC because if they did, they wouldn't need the framework."* Every adopted project lands at **phase 0** and runs the ordinary SDLC forward — Phase 0 intake first. What Scout, the census and the assessment learn becomes **pre-fill for that intake**, never evidence for skipping past it; that is D6's shape generalised from the rebuild verdict to every adoption. **This CORRECTS this document, not v1.** D4 deleted the chooser; §4.3 read that as *replace the operator's claimed rung with a derived one* and was titled "placement from evidence alone". Karl never asked for a replacement — deleting a question whose answer cannot be trusted does not imply computing the answer another way. `## BL-242:`'s D5 carries the correction and the recipe that shows no Karl quote ever touched rung, ladder, placement or evidence. | §2, §3.1–§3.6, §4.3, §5.1, §5.4, §8.3, §8.5, §9, §12 — the removal is wide because the mechanism was | Nothing — this decision REMOVES machinery; §4.3 names what goes |

### §0.1a — Two rulings recorded after D10 — R1 and R2 (Karl, 2026-09-17)

**Both are Karl's, recorded from his instruction of 2026-09-17 in substance rather than verbatim
— no transcript was seen (§13-U(v2.2)).** They are recorded HERE, apart from §0.1's table, because
neither adds, removes or amends a D: R1 fixes a precondition on Act 2 that D5's order never
stated, and R2 loosens a rule of the *delta track's* design (`docs/designs/2026-08-02-delta-track-v1.md`
§10.1's era invariant, enforced at `# DELTA-OPEN-ERA-GUARD`) for one declared population. Each row
says which part is RULED and which part is this author's; the mechanisms are indexed in §8.3c and
may be attacked freely, the rulings may not.

| # | Ruling (Karl, 2026-09-17) — the RULED part | What it constrains | Author-proposed inside it (§8.3c) | Designed in |
|---|---|---|---|---|
| **R1** | **Hooks: REFUSE at step 0.** When `core.hooksPath` is configured, or `--root` is not what `git rev-parse --show-toplevel` reports (a linked worktree, a submodule, a sub-directory of a repository), adoption **refuses before any write**, names the condition it found, and prints the remedy — unset or relocate the hooksPath, or run from the repository top level. **The *"gates are live"* sentence becomes DERIVED**: printed only when the hook file sits at the path `git rev-parse --git-path hooks` reports. **EXTENDED by Karl the same day, after the independent review of the WP9d precheck measured the gap (§12 item 33, now struck): the hooks path being a SYMLINK is refused too** — `ln -s ~/.githooks .git/hooks` passes every write test, the hook lands in a directory shared across repositories and outside this one, and the derived sentence prints TRUTHFULLY because the re-resolution follows the same link, so the derivation alone cannot catch it. This is the policy both siblings already hold: `scripts/verify-install.sh`'s `# BL-145-SYMLINK-GUARD-BEGIN` refuses to repair through such a link and its header calls `ln -s ~/.githooks .git/hooks` *"the classic"* case, and `# BL-209-HOOKSPATH-SAME-DIR` refuses a configured hooksPath for the same stated reason — *it can be shared across repos*. | §8.2 step 0 gains three preconditions; step 9's hook install resolves its directory through git and the handoff's sentence through a re-read; §2.1's table names the refused shapes; §8.7a rows 6 and 9 | M1 — HOW each condition is detected (a `.git` that is a file, `--git-dir` ≠ `--git-common-dir`, `--show-toplevel` compared by physical path, hooksPath read off `git config`'s exit status and compared by physical directory); the remedy's WORDING, the *install the hook by hand* alternative, the message shape borrowed from `scripts/install-filesystem-gates.sh`'s hooksPath refusal (`# BL-209-HOOKSPATH-SAME-DIR`), and the SAME-DIRECTORY exception — a hooksPath that resolves to the repository's own hooks directory is treated as in scope, which NARROWS the ruling's *configured* — are all this author's, none of them in the ruling (the review's R-16); M2 — the derivation's exact predicate and its failure text; M16 — the regular-file shape taking the same refusal as the ruled symlink one | §3.3 step 9, §8.1, §8.2 rows 0 and 9, §8.7a, §2.1, §10-WP9d |
| **R2** | **A recorded `adopted-in-production` exemption.** The interview records *"in production: yes/no"*; an adopted project so recorded **may open a delta below phase 4**, with the exemption written into the delta record and the process state, so incidents keep the hotfix retro and write-up. This loosens `delta.sh`'s phase-4 predicate (`# DELTA-OPEN-ERA-GUARD`) **for exactly that declared population and nobody else**; the exemption is per-project and recorded; no gate is touched. | The interview (WP12a) gains one question and the assessment record one field; the delta module's era guard gains a second conjunct (WP12c, a new small package); §3.6's promise is restated with the one loosening named | M13 — that `resume.sh`'s `# DELTA-RESUME-PHASE4` branch and `validate.sh`'s era report are ALSO widened (the mechanism's reach beyond `delta.sh`'s guard), and that the Adoption Record (WP7) LISTS the exemption and every use of it — both this author's, neither in the ruling (the review's R-15); the field's name and home (`.adoption.assessment.inProduction`, merged LAST per A2), the predicate's exact spelling, the two records' shapes, the resume branch's ORDER under the exemption (an open delta outranks the Phase 0 entry; a greeting never fires), and the gate-untouched invariant (§9.1-I18) | §3.6, §5.2, §8.3, §8.5, §8.6, §10-WP12a, §10-WP12c, §12 |

**What the two rulings did NOT do.** Neither built anything (§13-V29-(10)); neither touched a phase
gate (R2 reaches the delta track's guard and the resume script, never `scripts/check-phase-gate.sh`
— §9.1-I18 is the invariant and WP12c's last proof pins it); and neither overturns D10 — an
adopted project still lands at phase 0 and earns every boundary; what R2 permits is post-release
*maintenance ceremony* on a project that is, by the operator's own declaration, already released.

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
is part of the requirement (§7.2), and it binds WP11's disclosure and WP12b's writing. §12's open
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

**2026-08-31, seventh pass — round 3 reviewed A1–A4 and B2 is CLOSED, at the cost of seven majors
in the A-layer's own edges.** The sharpest was **M13**, and it is A1's: the preflight as first
written covered the *adopted* and *interrupted* populations and missed the **scaffolded greenfield**
one — a tree the framework already manages. On it, no arm fires, adoption archives the scaffold's
own framework files as the operator's, overwrites gate-earned state, stamps it adopted (no
`.adoption` block ⇒ no restamp refusal) and **commits, exit 0**. Shipped v1 refuses that tree via
the `n_copied -eq 0` tripwire **D1 unreaches**. A1 gained a third arm **in §8.3a** — §10's cells did not receive it until the eighth pass.

The rest were proofs that could not fail and routes that were named wrong. **M14/M19:** two
mutation proofs were vacuous — A1's revert is invisible from a fixture already at 0-and-null, and
A4's converse arm was specified on a fixture where the mutation is unreachable (the reviewer built
the discriminating one and ran it: 1 issue → seeded row → exit 0). *(This pass fixed both in §8.3a
and **did not reach §10's cells at all** — see the eighth pass below.)* **M17:** A3 named the kickoff
branch as the post-adoption route, but the intake template carries **87** blankable cells against a
`>20` threshold, so the intake branch fires first — the design now asserts the *disjunction*, which
is what D10 actually requires. A3's "written in WP12b" also went: `init.sh` writes no manifesto,
the Phase-0 agent does, and an adoption-side writer would have duplicated it. **M15/M16/M18:** A2's
exemption is now bound to `adoptedAtCommit` and archives before rewriting; the receipt rule is
scoped to the document writer with a named helper and a home for the unheaded outputs; and §7.2's
archive denominator became `init.sh`'s writers ∪ Act 4's write set, without which a bible-owning
adoptee deadlocks and a manifesto-owning one silently skips D10's entry.

**2026-08-31, eighth pass — the seventh pass edited the essays and never touched the
instructions.** Round 4 diffed the seventh pass hunk by hunk and found that **no hunk landed in any
§10 work-package cell**. The cause is worth recording because it is a process defect, not a
judgement one: the editing script hit a failed match on §10's preamble and exited **before its
write**, so three edits that had already printed `ok` were in memory only; a follow-up script
fixed the preamble and did not re-include them. The status summary then reported edits that were
not in the tree.

**What that left.** §8.2's step-0 row still specified two arms, so the M13 fix — the one that stops
adoption silently corrupting a scaffolded greenfield project — **was absent from both build
surfaces**. WP9 still instructed the "empty skeleton" §8.3a rejects by name and carried both
vacuous proofs verbatim. WP12 still said WP12b writes the manifesto and still pinned the kickoff
branch by name, 300 lines from §8.5 explaining why that pin goes RED against correct code. WP11
still derived from init-writers alone. The document argued with itself in six places, and
implementers follow §10, not the essays.

**The eighth pass copies the already-made decisions into the cells** — step 0's three arms, WP9's
scope and its three-fixtures-plus-discriminating-fixture proofs, WP12's scope and the disjunction
proof plus A2's two pins, WP11's denominator, the preamble's dangling reference, and Document
Control's "all folded in", which had become the same claims-versus-tree defect this document keeps
producing. **No new decisions.** Every edit was verified against the file on disk afterwards
rather than against the editing script's output — which is the check whose absence caused this.

**2026-08-31, ninth and tenth passes — four proof gaps, then two residues of fixing them.** Round 5
cleared the document (nothing blocking) and recommended landing with four one-sentence gaps as a
follow-up; they were done instead. Two were the same shape, and both were **arm 3 masking the
mutation**: a stamped fixture necessarily carries a `phase-state.json`, so arm 3 fires on it too and
dropping arm 1 changed nothing observable. The arms are now spelled disjointly — arm 3 carries the
*not-adopted* conjunct its §8.3a title already implies — and arm 2 gained the mutation it never
had, on a fixture holding neither state file. WP12's manifesto mutation gained an intake-complete
fixture, because on a realistic one the intake branch intercepts first and the mutant still
satisfies the disjunction. The duplicated merge-first mutation went.

Round 6 then found two residues of that pass: a sentence claiming arm 3's mutant was *the only one*
exiting zero, which arm 2's new mutant had just falsified; and **this changelog stopping at the
eighth pass while the ninth had changed normative proof text** — in the document whose changelog
has been a finding before. Both are corrected here, and the manifesto fixture now names the
**state** (no blank cells) rather than the `>20` threshold, which is a constant in another script
and can legitimately move.

**2026-09-01 — WP9's build amendment: the init-parity table delivered, WP12 split, A5–A8, and
three rows this document's own blast radius had missed.** Nothing here overturns a D or an A; it
is what building WP9 found. Five changes:

1. **§8.7a — the init-parity table, delivered**, and its adoption half derived **by execution**
   (a shipped adoption run against a hermetic adoptee, tree diffed: **77** files, 68 under
   `scripts/`, **nine** elsewhere) rather than by grep, because grep has under-read this exact
   surface twice before. **33 rows; thirteen UNOWNED.** *(This entry said 75 / seven / thirty-one
   for three rounds after §8.7a itself was re-measured — a changelog entry describing a
   measurement is a SECOND carrier of it, and correcting the table did not correct this. It then
   said 76 / eight / thirty-two for one round more, because WP9b corrected `docs/adoption.md` AND
   §8.7a and missed this THIRD carrier — the one whose own parenthetical explains the failure mode.
   Writing the lesson down did not make its author apply it. **If you re-measure, `grep` for the
   number.**)* §12-3 is rewritten from "not delivered" to what
   the table says, which is worse news than the residual expected.
2. **WP12 is split into 12a and 12b**, on a recommendation the architecture review made twice.
   §10's sequencing line and both rows are re-cut; the A3 manifesto mutation moves to 12b with the
   reason stated, because it needs a document writer to mutate.
3. **A5–A8 recorded in §8.3a**, labelled A and not D per that section's own rule.
4. **§4.2's blast-radius table gains THREE rows it did not have** — `scripts/check-phase-gate.sh`
   (a cosmetic `.adoption.scenario` read that would print `scenario: unknown` forever),
   `adopt-intake.sh` and `adopt-stubs.sh`. *(This said FOUR, counting the WP4 suite's `P` block and
   Act-2 classification cases as a fourth; that row was already on `main` and was WIDENED, not
   added. Derived: 5 rows on `main`, 8 after this amendment. A sentence about a short enumeration,
   short by one.)* **That is the fourth instance of this document's recurring defect** — after D9, D10 and
   the "does not ask" headline — and the first one that is not about mistaking prose for a ruling:
   this time an enumeration was simply short, inside the section whose own closing paragraph warns
   that "a blast-radius enumeration is the author's inference about consequences".
5. **`docs/adoption.md`'s chooser sections move from WP12 to WP9**, resolving a contradiction that
   had stood since v2.0: §4.2 set WP9's completion check as "the verbatim question's grep returns
   nothing" while assigning one of the four files carrying it to a later package.

**2026-09-01, third pass — WP9b BUILT (A1's three arms, A4's approval log), and it changed
two shipped behaviours that were pinned elsewhere.** The package itself is what §10 specified and
the proofs are what §10 asked for; what is worth recording here is the collateral, because both
items were caught by an existing suite going red rather than by anyone predicting them.

1. **A4 RETIRES AN INCIDENTAL SAFETY BLOCK, and the safety did not move — the assertion did.**
   `tests/test-brownfield-wp4-driver.sh`'s `_assert_safe_row` pinned §8.4's top row (phase-state
   present, manifest absent) as *"the gate BLOCKS, and it blocks because `APPROVAL_LOG.md not
   found but ...`"*. An adoption interrupted after the phase_state stage was therefore "safe"
   **because a file was missing**. A4 writes that file first, so the precondition no longer fires
   on a tree adoption produced and the gate now reaches a real verdict — MEASURED: `Current phase:
   0`, `Phase gates consistent.`, **rc 0**. That verdict is TRUE. The property §8.4 actually
   protects is untouched: the *opposite* row (manifest present, phase-state absent — the gate
   prints "skipping" and exits 0 on an adopted-LOOKING project) is still unreachable, and the
   commit-time ladder still reads **strict** on the interrupted tree because the manifest is
   missing. The assertion was re-aimed at those two and the retired clause is NAMED in the helper
   so nobody re-adds it. The gate's refusal on a *genuinely* missing log is untouched and WP9b's
   own `AM1` mutates the write away to watch it return.

2. **A1 SUPERSEDES THE `n_copied -eq 0` TRIPWIRE AS THE RE-RUN ANSWER**, and the WP4 suite's `R1`
   pinned the tripwire's wording. The tripwire fires inside `adopt_install_framework` — after the
   tier question, the reverse intake, the census and the archive; the preflight refuses the same
   tree at step 0. `R1` now asserts the PROPERTY (refuses, says already adopted, never blames the
   clone, names the route) rather than which function said it, and keeps the clone misdiagnosis
   pinned as an absence. **This sentence has now been wrong twice, in opposite directions,
   and the second time is the more instructive.** It first read "the tripwire is not
   asserted dead — a tree carrying every framework script but no `.claude/` at all
   still reaches it", which arm 3's third signal falsified. The replacement said the
   `n_collided -gt 0` branch was "unreachable in shipped code" — **also false**, and
   review reached it end-to-end through an INCOMPLETE framework root, the shape this
   §0.3 warns about three bullets below. **The error was reasoning about two counts as
   though they shared a denominator.** `adopt_install_framework` skips entries whose
   SOURCE is absent (`[ -f "$src" ] || continue`) and tests the destination with `-e`;
   the preflight counted EVERY parsed line and tested `-f`. Against a root missing its
   top-level scripts the adoptee held 24 of the 24 that root could install while the
   preflight scored 24 against 65, stayed silent, and let the run reach the tripwire.
   **The fix is the alignment, not the sentence**: the preflight now counts the same
   set the installer would. With that, `n_copied -eq 0` genuinely implies
   `n_present == n_total > 0`, so arm 3 (or arm 1) refuses first and the
   `n_collided -gt 0` branch is unreachable — the `n_total -gt 0` guard covering the
   only remaining case, an install set that parses to nothing, where the OTHER tripwire
   branch fires. Measured both ways: 68/68 with no `.claude/` refuses at step 0, and the
   incomplete-root fixture now refuses at step 0 too, tripwire text absent in both. The
   branch is kept because the mutants still need it and because a reader of
   `adopt_install_framework` must know why it no longer fires on its own.

**A third thing, and it is the one a future package will trip over.** The driver now reads
`$ADOPT_FRAMEWORK_ROOT/templates/`, which no adoption code did before. Three suites mirror the
framework as `scripts/` + `init.sh` and every adoption run against those mirrors began refusing —
correctly, since a checkout without `templates/` genuinely cannot render the log. **A framework
root is not `scripts/` plus `init.sh`**; the three mirrors now copy `templates/` and say why. The
refusal names the missing path, so the next incomplete mirror produces a diagnosis rather than a
mystery.

**And one mutation the design specified could not have gone RED as written.** §10-WP9's A1 arm-1
proof says *"drop arm 1 → phase-state reverts and its gate dates null → RED"*. On an untouched
adopted tree it does not: every framework file is already present, so the shipped `n_copied -eq 0`
tripwire refuses BEFORE the state stage and the mutant leaves phase-state intact — measured, and
the proof was green against a build with **no arm 1 at all**. That tripwire is exactly what D1's
framework-wins install unreaches at WP11. Rather than defer the proof to WP11, the fixture deletes
one framework script so `n_copied` is non-zero today; the RED is the specified one, and a
partly-deleted adopted tree is an ordinary thing to find. A same-fixture control (`PM1c`) asserts
the shipped code holds where the mutant fails.

**2026-09-01, second pass — adversarial review of WP9a, and the finding is about DEFERRAL.**
Round 1 on the build branch returned **major_concerns** on two claims, refuted both by execution,
and could not break the code — its own five extra mutants all died against the PR-blocking check
set, and every measured number in §8.7a reproduced byte-for-byte.

1. **A7's second conjunct was false on all three routes** (§8.3a-A7 carries the detail). The
   fail-closed half was verified and held; what nobody had asserted was that the operator still
   *meets* the deferred question. `resume.sh` pointed at a `## 13.` section the adoption-rendered
   intake never wrote; `intake-wizard.sh --resume` raised a **swallowed** `KeyError` and resumed
   **past** the classification while printing *"Intake Complete!"* at rc 0; and the escape hatch
   the ZDR block names **in its own FAIL text** died on a file adoption never wrote. All three are
   fixed and each is now asserted **by execution**. **The transferable rule: deferring a
   requirement is only honest if the route that re-asks it exists, and a route is worth exactly
   what an execution of it says.** Two `intake-wizard.sh` defects found on the way are filed as
   `BUG-010` rather than absorbed here.
2. **§4.2's blast radius was short a THIRD time**, and this one is the worst of the three:
   `workflow.html` — linked from `README.md`'s ninth line as the walkthrough *"written for
   non-engineers"* — still described the deleted question, the two scenarios, the floor rule and
   the certification lists. It escaped §4.2's own completion check because the sentence is
   **line-wrapped** there and a single-line `grep -F` cannot match a wrapped literal. The check is
   now a whitespace-normalised sweep of every tracked file, and the wrapped case has its own
   mutant — the previous mutant injected a single-line copy, certifying the half that never
   escaped.

Also from the same round: one still-true assertion (the evidence block's *"the scan cannot
measure"* line) had been deleted with the false ones and is restored; `N4`'s starvation coupling is
documented and paired with a report-derived semantic pin; §8.7a rows 5 and 23 were stale within the
branch. **Row 23 is the one unowned row WP9a closed**, and the boundary is stated rather than left
to look arbitrary: A7's own argument depended on it.

**2026-09-01, third pass — round 2 on the fixes, and the finding is about a MECHANISM stated as
fact.** Round 2 verified R-1 closed by executing all three routes on its own adoption, confirmed
the `init.sh` parity argument in full, confirmed `## BL-225:` undisturbed and the §13 heredoc inert
to every `PROJECT_INTAKE.md` parser — and still returned **major_concerns**, on four counts:

1. **"The only route to `current_phase` 2 crosses the 1→2 gate" is FALSE**, and it had propagated
   into four tracked files plus a commit message. `process-checklist.sh`'s `_set_current_phase_min`
   writes the value at five call sites and **ships to adoptees**; its `--complete-step` path reaches
   target 2 with no gate consult, and the reviewer drove an adopted fixture 0 → 2 with the
   classification still absent. The fail-closed CONCLUSION survives — the backstop is a real
   `issues` increment at `>= 2` however reached — and the corrected reasoning is stronger for not
   depending on an enumeration of writers. **Round 1 asserted this too, and this document inherited
   it: a claim can be wrong in a review and wrong in the fix that answers it.**
2. **§4.2 was short a FOURTH and FIFTH time, in the commit announcing it was short a third.**
   `README.md` and `docs/scout.md` carry deleted machinery WITHOUT carrying the verbatim question,
   so no widening of the completion check would ever have found them. That is the standing limit of
   both the table and the check, and it is now written into §4.2 rather than left to be rediscovered.
3. **Four of the reviewer's own mutants survived the PR-blocking checks**, all against the §13
   prompt this branch now ships into every adopted project: its phase-0 sentence flipped to "PHASE
   3 and three gates have been crossed", its false-attachment disclaimer deleted, its anti-skip rule
   **inverted** to "Feel free to suggest that any gate be skipped", and the escape-hatch write's
   `|| return 1` degraded to `|| true`. Two greps out of ~50 lines was the whole pin. R1 now pins
   the load-bearing sentences as a named set, R1b pins the archive item in both directions, and R5
   pins the swallowed-write path; all four mutants now die.
4. **The prompt named `.claude/adoption-archive/` unconditionally** on a collision-free adoptee
   where it does not exist — the false-attachment class the prompt's own disclaimer exists to avoid,
   one item further down — and the rendered intake carried **two** `Agent Initialization Prompt`
   headings, the first attributing the prompt to `intake-wizard.sh`'s `run_section_13`, which never
   runs during an adoption.

Also fixed: `_normalise` now runs `tr` under `LC_ALL=C`, because otherwise it truncates at the first
byte invalid in the ambient locale and reports the file clean — the check's own failure mode being
the one it was written to prevent. A dead `command -v jq` guard on the escape-hatch writer is
deleted rather than kept, since if it ever became reachable it would skip the file and return
success. `BUG-010` gains a third defect on the same path: `intake-wizard.sh`'s appendix writer
declares `def row(label; val)` and **`label` is a jq reserved keyword**, so the program does not
compile and the table renders as a bare header under an `[OK]` line — confirmed against jq 1.7.1.

**2026-09-01, fourth pass — round 3 returned BLOCK, and the sharpest finding was a proof that did
not prove.** Round 3 wrote ten mutants against WP9a's own new code and **nine survived**.

1. **R5 — added in the third pass specifically to kill round 2's escape-hatch survivor — was
   VACUOUS.** Its only discriminator was `_changed_lines -eq 2` after its own `sed` rewrote the
   marked line to a canonical `|| true`. Against a tree already carrying `|| true` in a DIFFERENT
   SPELLING — one space before the comment instead of three — the sed still changed two lines, the
   conjunct held, and the mutant's behavioural half is what the mutant produces anyway. **The
   escape hatch was dead in the shipped tree at 29/0.** The rule that comes out of it is general
   and belongs here rather than in a test comment: **a mutation proof whose only discriminator is
   its own edit landing proves that `sed` works, not that the property holds.** R5 now asserts the
   SHIPPED spelling positively, independent of its own edit.
2. **Six more §13-prompt mutants survived R1's phrase list**, which the third pass had introduced
   as the fix for exactly this. The sharpest inverted *"Then run Phase 0 … from the beginning"* to
   *"run Phase 2 … from where the project already is"* — **this branch's own commit subject is
   "phase 0 for everyone"** — at 29/0. Another inverted the grandfathering clause four words after
   a sentence R1 did pin. The list is now per-sentence with each member's failure named, and it
   matches against the NORMALISED prompt, because half the sentences wrap. **A per-sentence list
   must be extended when the prompt gains a load-bearing sentence and nothing enforces that it
   was** — said in the suite rather than assumed.
3. **The mechanism claim was wrong for the THIRD CONSECUTIVE ROUND.** The ZDR backstop is
   *unreachable* on an adopted project today: `check-phase-gate.sh` refuses on a missing
   `APPROVAL_LOG.md` and `exit 1`s **six lines before `current_phase` is parsed**, and adoption
   did not write that file until **A4, which has since landed in WP9b** — the ZDR backstop is the
   operative guard now. Fail-closed survives (rc 1 either way) and
   the refusal names the approval log rather than the classification. **This suite's own G section
   documents that early exit and stubs around it** — the claim was written beside a fixture that
   disproved it.
4. **§8.7a's measured install set was stale, falsified by this package's own new writer**: 76
   files and EIGHT non-`scripts/` paths, not 75 and seven, the eighth being
   `.claude/orchestrator-source.json` — named twelve lines below by row 23.
   *(Those are THAT round's numbers and are left as its record; WP9b's
   `APPROVAL_LOG.md` falsified them again — the current figures are 77 and
   nine, per §8.7a. Same convention as the rounds-7-to-9 entry further down this section.)* And the UNOWNED count
   said twelve while §12-3, §0.3 and `docs/INDEX.md` said thirteen: row 23's split created row
   **23a**, itself unowned, so the count never moved.
5. **`workflow.html` told operators to hand-edit enforcement-tier keys the tool already writes** —
   the row this branch had corrected in `docs/adoption.md` and left on the published page.
6. **Three `docs/adoption.md` fenced transcripts were accurate on `main` and falsified by this
   branch's own source edits**, including one contradicting a table twelve lines below it.

Also fixed: Scout's `phaseMap` note still described the deleted floor rule (*"the interview may
only lower this"*) in shipped operator-facing output — **§9's "Scout, whole, unchanged" is amended
to that extent**, because nothing outside Scout reads `suggestedPhase` any more and the note's
claim was simply false; two owner strings; §4.2's *"V7's grep returns nothing"*, which was false
the moment the suite that must spell the sentence existed.

**The pattern across all three rounds, stated once.** Every blocking finding has been a
**plausible statement recorded as a verified one** — a mechanism, a count, a transcript, or a proof
believed to discriminate. None was a defect in the shipped behaviour, which passed every functional
probe all three times. The remedy that has actually worked is not more care: it is **re-running the
measurement and re-writing the mutant** at the tip, every round.

**2026-09-01, fifth pass — round 4 blocked, Tier 1 was EMPTY, and the pattern held a fourth time.**
Round 4 wrote sixteen mutants and **nine survived**; it found no defect in shipped behaviour, and
said so first. Every finding was a proof that did not discriminate or a claim false at the tip.

**Two of the branch's own claims were refuted by its own tree**, which is the sharpest form this
recurring defect has taken:

1. **`df7d5a1`'s message described an R2 fix that was never applied.** The reasoning in it was
   correct — `jq -e 'has($k)'` is true for an explicit null and `shlex.quote(None)` returns `''`
   rather than raising — but the hunk is absent from the commit, because the script that would have
   made it asserted and exited before writing, and the message was composed from what was *intended*
   rather than from the diff. The hole stayed open and a mutant walked through it. **A commit
   message is a claim about a tree, and the tree is the arbiter.**
2. **`2e4c180` and §0.3 both said §9's Scout row was "amended"; §9's row was byte-identical to
   `main`.** Only the changelog sentence asserting the amendment existed. §9's row is now actually
   amended, and §4.2 gains the `scripts/lib/scout/` row it was missing — **the sixth time that table
   has been short, and the first time the omission was created by the branch's own later commit.**

**Proofs that did not discriminate**, all now fixed and each re-verified by re-running the mutant:
`R5` pinned the escape hatch's CALL SITE, so moving the swallow one line down INTO the function was
green (it now calls the function with a stubbed writer and requires a refusal — behaviour, not
spelling); `R2` pinned `last_section` and not `completed_sections`, so a populated skip-set let the
wizard print `[OK] Section 5 — already complete` and then *"Intake Complete!"* at rc 0 — **the exact
failure A7 was written against, through the other door**; `R1` pinned the classification sentence
and not the clause beside it, so *"adoption did not ask for it"* could become *"adoption already
recorded it for you"*; `R1` counted `^## 13\.` and not the title, so the double-heading defect
`730c27d` fixed could be restored green; and `E5`'s fixture had both jq and a manifest, so the
stamp guard's stated ORDERING was unpinned.

**Numbers, again.** `## BL-242:` — the entry `README.md` tells readers to *"prefer to this
sentence"* — still carried four claims this document had already corrected, and contradicted itself
about the unowned count seventeen lines apart. `docs/adoption.md`'s committed-set enumeration said
69 files and six paths where the run then printed **76 and eight**, omitting `orchestrator-source.json` —
**this package's own new writer**, the identical failure §8.7a had just been corrected for, one file
over. And `BUG-010` had been filed *inside* the bugs file's template code fence, scrambling the
last 120 lines of it.

**Four rounds, one defect class, and the honest conclusion.** Not one blocking finding in four
rounds has been a defect in what the software does. Every one has been **a plausible statement
recorded as a verified one** — a mechanism, a count, a transcript, a commit message, or a proof
believed to discriminate. Care has not fixed it; four rounds of care produced four rounds of it.
What has worked, every time, is **re-deriving the number and re-running the mutant against the tip**
— and the reason that works is that it does not consult the author's belief at all.

**2026-09-01, sixth pass — round 5 blocked, Tier 1 was EMPTY a SECOND time, and the worst finding
of the six rounds was an instruction that would have destroyed an operator's record.** Round 5
re-ran round 4's nine survivors and confirmed all dead, then found six claims false at the tip:

1. **`docs/adoption.md` told operators to hand-edit `.claude/manifest.json`** — *"if you adopt an
   organizational project, set the manifest's tier keys by hand"* — above a table listing all three
   tier keys as **absent**. Measured: all three present (`## BL-221:` Closed, PR #356), and **this
   branch had already added a row 450 lines below saying they ship**, so the file contradicted
   itself. The manifest is where the adoption stamp lives, so following the advice trips
   `[FAIL] Adoption stamp LOST` and costs the record of how the project entered the framework — to
   fix a defect closed weeks earlier. **It was correct when written and was left behind by its own
   fix**, and the commit that swept for exactly this class fixed `workflow.html`, missed the
   callout in the file it was editing, and left the table-row half to a different commit.
   *"Advice that outlived its defect"* is the category worth carrying forward.
2. **The tip commit claimed it corrected `## BL-242:`'s mechanism sentence; its diff did not touch
   it** — third instance of a message describing absent work, in the entry `README.md` tells
   readers to prefer over everything else.
3. **§0.3 and §12-3 still carried the pre-correction measurement** (75 files / seven paths /
   thirty-one rows) in lines *this branch added*. A changelog entry describing a measurement is a
   **second carrier** of it; correcting the table did not correct the entry about the table.
4. **§8.5 assigned delivered work to WP12a** — the `## 13.` kickoff prompt WP9a had built and `R1`
   asserts by execution. The mirror image of the rest of this section: undone work claimed done,
   and now done work claimed undone.
5. **The status row still said "NOTHING OF v2 IS BUILT"** while its own derivation (2) named
   `adopt-chooser.sh`, which this branch deleted. That row's instruction is *"when any of those
   derivations stops returning what this row says, re-run them; do not quote them."* Nobody had.
6. **A comment miscount was load-bearing.** *"The four values adoption cannot know are written
   EMPTY"* — it writes three; `track` is a value. Its paired sentence in the suite said *"the one
   key adoption genuinely knows"*, and that was the stated reason only `project_name` was pinned by
   value — so blanking `deployment` (the tier answer, whose only source is the question WP9a kept)
   and blanking `track` were both green.

**And a fix that measured nothing, twice, both times reporting the happy answer.** E5's new
jq-arm probe: `PATH=<empty-dir> command -v jq` **still finds jq**, because bash caches command
locations and `command -v` consults the cache; re-doing it as `PATH=<empty-dir> bash -c …` then
could not find `bash`, so the launch failure fired the refusal branch. The working form sets `PATH`
INSIDE the fresh shell.

**2026-09-01, seventh pass — round 6, and the pattern completed a circle.** Round 6 found the
shipped software sound for the third consecutive round and blocked on three more false claims —
one of them being that **this very changelog recorded round 5**, which it did not until this entry
existed. The commit making that claim is the same one whose body announces *"THE TIP COMMIT CLAIMED
A CORRECTION ABSENT FROM ITS OWN DIFF — third instance on this branch."* **It was the fourth,
committed in the sentence position that named the third.** Also corrected: §0.3's *"§4.2's
blast-radius table gains four rows"* — it gained **three** (the fourth enumerated item was a
*widening* of the `tests/test-brownfield-wp4-driver.sh` row already present on `main`), which is
the same short-enumeration defect the sentence itself was describing; and the attribution of
`docs/adoption.md`'s tier-key row flip to `066a138`, which was `68ad9dd`'s.

**2026-09-01, eighth through tenth passes — rounds 7, 8 and 9, and the record catching up with
itself.** Recorded together because their findings are one shape, and because **this changelog
stopping at round 6 was itself round 9's blocking finding** — raised against the PR body's claim
that §0.3 carried all of it. The same gap round 6 blocked on, recurring one level up, in the
artifact that describes it.

**Round 7** found shipped behaviour sound for the fourth consecutive round and blocked on five false
statements: `adopt-core.sh`'s version comment claiming the build *"carries the skeleton, the
chooser, placement"* (a file WP9a never opened); a dangling `BF-ADOPT-DC-MANDATORY` cross-reference
**this branch created**, invisible to `lint-bl-markers.sh` because that lint covers `# BL-NNN-…` and
not `BF-…`; `adopt-stubs.sh`'s header naming WP5/WP5b as unbuilt eleven lines above its own rule
forbidding exactly that; `## BL-242:`'s *"seven `tests/test-brownfield-wp*.sh` files"* after this
branch made it eight; and a **self-refuting commit message** (*"touches … 386 … and §0.3 spans
183–571. It touched none of it"*). The last was fixed by rebuilding two commits — the only
correction in this series that had to beat a deadline, because that window closes at push.

**Round 8** found it sound for the fifth round and blocked on two: `docs/INDEX.md` saying **four**
delegated author decisions where the design carries **eight** — *this branch added A5–A8 in its own
first commit and wrote "four" three commits later* — and `workflow.html`'s NOT-DONE preamble making
two false claims about its own list. It also found **seven stale 8-argument `soif_adoption_stamp`
calls** feeding `"completed"` into what is now `scanner_sha`: green, because nothing asserted that
field, which is what made it a trap rather than a failure.

**Round 9** found it sound for the sixth round, killed ten of its own ten mutants against
PR-blocking checks, and blocked on two more: a **verification recipe that named the file it was
printed in** (`grep -c 'resolve-tools'` *"over this driver and its lib"* — including the file making
the claim, which is its only hit), and *"Each block names its owner during the run"* **surviving
eight lines below its own deletion**, in the same hunk this branch wrote.

**What these three rounds change in normative text**, so a reader of those sections knows why: §9's
Scout row is amended (`scout-report.sh`'s floor-rule note was shipped operator-facing output
describing deleted machinery); §4.2 gains the `scripts/lib/scout/` row — **its sixth omission, and
the first created by this branch's own later commit**; §8.7a's measurement is re-derived to 76 files
and eight paths across 32 rows, after this package's own new writer falsified it; and §12-3's
unowned count is thirteen. *(Those three numbers are the values THAT round produced and are left
as its record; WP9b's own writer falsified them again — the current figures are 77 / nine / 33,
and this line is narration of a past round rather than a live claim.)*

**Nine rounds, one class, and the conclusion the whole series earns.** Not one blocking finding in
nine rounds has been a defect in shipped behaviour; **rounds 4 through 9 each verified that by
running a full adoption — six consecutive rounds**. Every blocker has been **a plausible statement
recorded as a verified one**. The defect recurred *inside the fixes for it* at least **five** times
— a mutation proof whose only discriminator was its own edit landing; a probe that isolated
nothing, twice over; a commit message announcing the third instance of exactly what it was
committing; a verification recipe that named the file it was printed in; and a claim surviving
eight lines below its own deletion, in the hunk that deleted it. **Care does not fix this class,
because care is what produces it.** What fixes it is mechanical and cheap: re-derive the number at
the tip, re-run the mutant against the shipped file, and `git show` the commit before writing its
message.

**v2.1 (2026-09-16) — reconciliation with fifteen days of `main`, and ONE RULED ROW ADDED TO D2's
TABLE. D2's principle is unchanged; NO OTHER settled decision, decision table, or WP boundary
changed.** The unqualified formula v1's every amendment could use — *"no settled decision, decision
table, or WP boundary changed"* — is NOT used here, because it would be false by one row; the
qualified one is used **because it was measured, not because it is customary**: the `## BL-242:`
entry was extracted at the last commit of 2026-08-31 (`f73dfca`) and at `01b66e3`, and the two
DECIDED sections that hold D1–D10 were **byte-identical at `01b66e3`** — `diff` over the
header-bounded span (`### THE THREE UNOWNED …` up to `### Consequences`) of both extracts returns rc 0
(§13-V17; from `7b88c2e` the span differs by exactly the ruled-row paragraph PR #415 added, and the
line-numbered form of the recipe no longer aligns — anchor on the headers, never on 190–667). Everything the whole-entry diff does touch is appended build notes, two
residual sections and two corrections inside the WP9 build note. **D1–D10 stand as ruled; §0.2 is
untouched; A1–A8 are untouched; §0.1's table changes in exactly one row, D2's — two cells, the decision and its
author-proposed column, both additions.**

**Why this entry exists at all.** Karl decided on 2026-09-15 to AMEND this document in place rather
than supersede it, after a premise put to him — *that decisions had been reversed since D10* — was
refuted by that measurement. Recorded because the premise was the same class of defect this
changelog has logged since v2.0: a plausible statement about the record, made without reading the
record. The document's own §11 rule stands: a superseding document is for an overturned decision,
and none was overturned. §11's first bullet — that amending v1 was rejected because it would carry
an overturned decision in its settled list — is exactly why amending v2 is right: nothing in v2's
settled list is overturned; one row is added.

**The one ruling, and how it came to be needed.** `## BL-288:` widened Scout's `secrets.status`
enumeration from three words to four — `scanned-partial`, a shallow clone — on 2026-09-12, and
§6.1's table had no row for it. Adoption's two readers were widened to print honestly and decide
nothing (`# BL-288-RESCAN-PARTIAL`), which was correct because nothing in Act 2 decides anything on
the status until WP10b. Which row of §6.1's tier table the status takes was raised as an open
question during this amendment's drafting on 2026-09-15 — §12 item 16 — and **Karl ruled it on
2026-09-16, before the amendment landed: *"go with the split."*** At `organizational` a
`scanned-partial` result STOPS with no escape, the refusal printing the unshallow remedy; at
`personal` the operator may acknowledge and continue, and the acknowledgement is RECORDED — in the same
place and shape as the `tool-unavailable` acknowledgement (§6.3's: named accepting person, reason,
date; that it also carries the scope and commit count the report holds is author-proposed, §0.1) —
refused if it cannot be recorded. §6.1a records it; §6.1's table gains its row; §0.1's D2 row
carries the amendment with his words; §12 item 16 is struck as ruled the day after it was raised.
The set awaiting Karl is therefore EMPTY again, having been one for a single day. **What the ruling
did NOT do:** it built nothing — the organizational stop and the personal recorded acknowledgement
are WP10b's, and §13-V28 shows the shipped stub still prints and returns 0 on the status. Writing
the obvious extrapolation into the table on 2026-09-15 instead of asking would have been the fourth
inference recorded as a ruling in this document's history, with the previous three named in §8.3a
— and the ruling that came differs from the drafted extrapolation on the `personal` arm (a recorded
acknowledgement, not a warning), which is the whole argument for asking.

**What the tree changed, by section, each verified in §13-V18–V27:**

1. **WP10a is BUILT (`4009790`, merged 2026-09-04 as PR #373)** — Act 2's step 2,
   `adopt_resolve_tools` in the new `scripts/lib/adopt/adopt-tools.sh`, plus §6.2's
   re-scan-after-install (`_adopt_rescan_secrets`). §3.3, §6.2, §8.2 step 2 and §10 are amended
   from *"the step adoption skips"* to *built*, and §1.3's *"the driver never resolves tools"* is
   dated as the v1 fact it was. **WP10 is delivered as two PRs, 10a and 10b, on the same terms §10
   already records for WP9a/9b: one scope row, one boundary, a review-surface seam.** 10a's commit
   message attributes the split to Karl (*"on Karl's call"*); that attribution is the commit's and
   was not independently verified here (§13-U(v2.1)). WP10a's review also found a defect in the
   shared resolver — a documentation URL filed in the `auto_install` bucket that `init.sh`
   executes — recorded as a `## BL-242:` residual, not fixed, and named in §6.2a. `## BL-251:`
   (Closed, PR #375) then added `# BL-251-FAST-PATH`: a scanner already on `PATH` costs no resolver
   subprocess, and the re-scan still runs. **One row WP10a does NOT close, and the draft of this
   entry said it did:** §8.7a row 7, the tool matrix — Act 2 reads it from the framework root, and
   the adoptee receives no copy (§13-V27's write set carries no `templates/`); the row is PARTIAL,
   and the reason nobody has tripped over it is row 32 (below).
2. **`## BL-225:`'s before-any-write half is BUILT (`8356317` … `2613937`, merged 2026-09-14 as
   PR #410).** `_adopt_write_phase` is the ONLY writer of the adoptee's files and is called twice —
   once by `adopt_prewrite_preflight` against a `cp -a` copy of the whole tree, once for real — so
   the planned path set is what the writers produced on a rehearsal, never a maintained list.
   Adoption **refuses before the first write** when the adoptee's ignore rules refuse any planned
   path (`# BL-225-PREWRITE-REFUSE`, *"NOTHING WAS WRITTEN"*). The entry records that Karl chose
   the copy over a per-writer no-write flag. §8.2 gains a rehearsal row (§8.2a), §8.4 gains the
   refused-before-write state (§8.4a), §10's sequencing paragraph and §12 items 1 and 4a are
   corrected from *"the before-any-write half is still open"*. `## BL-225:` itself stays **Open**
   for two named residuals — a `.claude` symlinked outside the repository, and an installer recipe
   that modifies an adoptee file in place, which the path-list fingerprint cannot see — both
   recorded there, not here.
3. **`## BL-288:` — a shallow clone is `scope: shallow-history`, `status: scanned-partial`, and the
   report's `schemaVersion` is 2** (`2a8fafb`, `35a222a`, renumbered `22b034d`; merged 2026-09-15
   inside PR #412). §6.1a is added (the ruling above); §6.1's table gains the row; §6.4 gains a
   one-line pointer; §9's Scout row is amended a second time — Scout is *"almost whole"* by a wider
   margin than 2026-09-01 said.
4. **`## BL-268:` — the manifest's `mode` takes `personal|org`, `deployment` takes
   `personal|organizational`, and `adopt_write_manifest` now translates the one from the other as
   `init.sh` does** (`eba7291`, `# BL-268-MODE-VOCABULARY`, merged inside PR #412). **`## BL-253:`
   — `poc_mode` is JSON `null` for production in both state files** (`269ee02`, Closed PR #377,
   `# BL-253-POC-MODE`, `# BL-253-POC-NULL`, `# BL-253-POC-NULL-MANIFEST`), as `init.sh` writes it;
   until then every adoptee was refused at `--start-phase4` and every organizational adoptee
   skipped six Pre-Phase-0 conditions. §8.3b states what the two writers emit today, by function,
   so the manifest's shape is a reading and not a memory. The related `## BL-270:` (migration for
   projects adopted before the fix — its backfill is on `main` at `0dc57fc`, whatever its status
   line says) and `## BL-271:` (the same hole on the `upgrade-project.sh` path) are named in §12,
   not designed here.
5. **`## BL-284:` and `## BL-273:` — §8.7 territory.** BL-284 found, by dogfood, that
   `verify-install.sh`'s `has_context()` was unsatisfiable on an adopted project because adoption
   writes no `.claude/tool-preferences.json` — an `init.sh` effect **absent from §8.7a's table**,
   whose `init.sh` half is acknowledged partial and has now been shown partial by one row; row 32
   is added, UNOWNED, and `## BL-284:`'s fix reads the context from state adoption does write
   (`# BL-284-CONTEXT-STATE`). The same missing file is what keeps row 7's missing matrix
   unreachable: the adoptee's own gate keys its tool-needs block on it (§8.7a). BL-273 records that
   the remote-URL-to-host inference exists at four shipped sites and `scripts/lib/host.sh` carries
   none — an observation about scripts an adoptee receives, recorded in §12 with no fix proposed.
6. **The status row is rewritten** as a dated measurement with nine derivations, derivation (3)
   retired rather than repaired (it counted mentions of a thing that has since been built), and
   three moved counts stated with their dates. **§8.7a's write set is RE-MEASURED BY EXECUTION —
   79 files, 70 under `scripts/`, the same nine elsewhere** (§13-V27): the value this document
   carried, 77, was falsified on 2026-09-08 by two files `## BL-254:` added to `init.sh`'s copy
   list, which no adoption package touched. **§13 gains a v2.1 addendum (V17–V28) and §13-U gains
   a v2.1 list.** A first attempt at this amendment, on 2026-09-15, measured everything but the
   write set and was stopped by an environment fault before writing a line; every one of its
   measurements was re-taken on 2026-09-16 against `01b66e3`, and what §13 prints is the re-take.

**Describe, never total.** This entry names its changes and does not count them; the fourth-pass
entry above explains why.

**v2.1, second pass (2026-09-16, after the merged-main adversarial sweep of `7b88c2e`). No decision or
WP boundary changed; two table cells did — §0.1's D2 cell re-labels two clauses as author-proposed and
§10-WP10's scope cell gains one ownership line (§12 item 22) — and the sweep's findings are folded in,
each dated: its twelve fix-now and refuted items plus one labelled residual.** The sweep reproduced every
code measurement in this document against `main` and found the defects where a tip review cannot
look: (1) PR #415 landed one merge after this amendment and corrected the neighbour carriers this
document had described as "not corrected here" — Document Control, §1.1a, §8.7a, §13-V25, §13-V17,
§6.1a and §13-U(v2.1) now say what was true at `01b66e3` and what PR #415 did; the ruling has three
carriers, not one. (2) §10-WP10's organizational `scanned-partial` proof asserted "the findings are
printed" on a fixture that produces zero findings — a second, retained-credential fixture and a
drop-the-print mutation are added at both tiers. (3) §10-WP12a now says it flips wp9 R1 and how to
re-aim it. (4) The gitleaks floor in the tool matrix is below the version whose subcommands Scout
runs and is enforced nowhere on adoption's path — §6.2, §13-V9 and §12 item 10 say so; the matrix
fix is `## BL-289:`. (5) §12 gains items 21–22 for two `## BL-242:` residuals it had not carried.
(6) Small corrections: §3.3's "three of the four cases", §1.2's stale notice text, §6.5's reader count,
§10's misread of the WP10a suite as a completion pin, §8.7's mention count, §8.7a row 8's site
count, Document Control's round count and branch caveat, §13-U's lint tallies, and two unlabelled
author-proposed clauses inside the ruling's sentences (§0.1, §12-16). A senior-architect review ran
the same day and is NOT folded in here — its seven design defects and buildability gaps are the
next amendment's, two of them awaiting rulings (hooks under `core.hooksPath`; an in-production
adoptee before phase 4).

**v2.2 (2026-09-17) — two rulings recorded, thirteen design defects and nine buildability gaps
amended, three open contributor issues taken into account. DECISIONS CHANGED: NONE. RULINGS
RECORDED: TWO (R1, R2 — Karl's, §0.1a). D1–D10's DECISION cells, §0.2 and §8.3a's A1–A8 are
BYTE-IDENTICAL before and after this amendment (the D2 and D5 rows' author-proposed cells each gained
a clause, the second on the review's R-13) — measured, not asserted: §13-V44 diffs the three spans of the file at
`579b0b0` against the amended copy and prints rc 0 for each; §13-V30 shows `## BL-242:`'s D-block
unchanged from `7b88c2e` to `579b0b0` (rc 0).** The unqualified formula is available again — no
settled decision, decision table or WP boundary was *overturned* — and is NOT used, because two
kinds of thing DID change and the entry's job is to name them:

- **Table cells that changed (each named, none a decision):** §0.1's D2 row, its author-proposed
  column only, gains one clause (the stop's input), and the D5 row's the same (the brief's drop —
  the review's R-13); §9's Kept-table row `| Every phase-gate predicate |` gains the R2/I18 note
  (the review's R-14); §8.2's row 0 gains R1's three preconditions
  plus the identity and hash-tool preconditions (B8), row 3 gains "keys on Act 2's own scan", row 7's
  state order gains the `dispositions` and `write_set` stages, row 8 gains the persisted write set,
  row 9 is rewritten per R1; §8.7a rows 3, 6, 17, 18–21 change owner or text and row 33 is added;
  §6.1's status table is UNCHANGED (the trust boundary is prose in §6.2b, and no sixth status word was
  needed — §13-V35 measures why); §10's WP10b, WP11, WP12a, WP12b and WP7 cells are re-cut.
- **WP boundaries that changed — three NEW small packages, stated as a measured claim:** none of the
  three carries work that any existing cell already owned. **WP9c** owns §8.7a rows 18–21, which were
  UNOWNED (the row text at `579b0b0` says so — §13-V38 prints the four rows); **WP9d** owns the driver's
  edges — R1's placement, the adoption window and `--finish` (A3), the rehearsal bound (A7), the
  block/refuse labels (A10) and the step-0 preconditions (B8) — every one a defect or gap on the SHIPPED
  path that no unbuilt package's scope named (grep §10 at `579b0b0` for `hooksPath`, `--finish`,
  `adopt_block`: nothing; `rehearsal` ONCE, in the preamble's sentence that `## BL-225:`'s second
  half is built — a description of the shipped rehearsal, not a package's scope; the review's R-5
  caught the over-claim); **WP12c** owns R2's predicate in `delta.sh`, `resume.sh` and
  `validate.sh`, which no package could have owned before the ruling existed. WP10b, WP11, WP12a,
  WP12b and WP7 keep their boundaries; their cells are re-cut for buildability, not re-scoped.

**Why this entry exists.** Two independent reviews of v2.1 ran on 2026-09-16 (Document Control): the
merged-main sweep (folded into v2.1's second pass) and a senior-architect review that returned seven
MAJOR design defects, six MINOR, and nine buildability gaps, two of the majors needing Karl's call.
He made both calls on 2026-09-17 — R1 and R2 above — and asked for the design amended in place
(no decision overturned; §11's rule holds).

**What changed, by finding, each dated 2026-09-17 and each verified in §13-V29–V45:**

1. **A1 hooks (R1).** §8.2 step 0 refuses under `core.hooksPath` or off the top level; step 9 resolves
   the hooks directory through `git rev-parse --git-path hooks`; the archive inventory reads hooks from
   the same directory; the handoff's *live* sentence is derived. **Measured at `579b0b0`** (§13-V32): an
   adoptee with `core.hooksPath` set adopts at rc 0, the hook lands in `.git/hooks`, the transcript says
   the gates are live, and `GIT_TRACE` shows git running NO hook on the next commit.
2. **A2 stop trust + A11 trust boundary.** §6.2b: the stop keys on a scan Act 2 ran ITSELF — a report
   handed in via `--scan-report` is pre-fill for everything except the stop; the stop's scan runs over a
   no-checkout shared clone in `$ADOPT_WORK` under the framework's own config, so a repo-local
   `.gitleaks.toml`, a `.gitleaksignore` or an inline `gitleaks:allow` cannot reach it. **Measured**
   (§13-V35): in gitleaks 8.30.1 a repo-local `.gitleaksignore` is defeated by NO flag — only the
   structural copy defeats it; the stamp hashes the scan the stop used.
3. **A3 the stamped-but-refused state.** §8.4 gains the *adoption window* row; arm 1 discriminates it
   (working-copy witness true, committed witness false — the stamp's own bound already spells that
   state, §13-V33) with its own message and a `--finish` route fed by a persisted write set
   (`.claude/adoption/write-set.txt`); §9.1-I12 states the invariant *re-run only before the stamp*.
   **Measured at `579b0b0`** (§13-V33): an adoptee whose own pre-commit hook rejects the adoption commit
   is left stamped, unmoved at HEAD, with 83 index entries staged, and the re-run refuses naming
   `resume.sh` — no finish route exists.
4. **A4 acknowledgement placement + B2 record mechanism.** §6.3: collected at step 3 into run state,
   validated (signer, reason, fingerprint), persisted as the `dispositions` stage of
   `_adopt_state_order` before `manifest`; the dispositions file is the join table and the
   `bypass_audit_append` row is the event; `--dispositions FILE` with an interactive fallback; the
   per-run acknowledgement keyed on HEAD and `commitsScanned`; required even at `findingCount` 0.
5. **A5 in-production (R2).** §3.6, §5.2, §8.3, §8.5, §10-WP12a, §10-WP12c, §12; the phase gates are
   untouched by construction and by proof.
6. **A6 rows 18–21 → WP9c**, inside `_adopt_write_phase`; the assessment brief is DROPPED (§3.7, §8.5 —
   the §13 prompt already carries what the brief was for); the prompt's *"WHAT YOU DO NOT HAVE"* becomes
   derived from what WP9c wrote. The shipment DEPENDS on `## BL-277:`'s disposition for the one hook the
   entry calls a day-one blocker (§12 item 26).
7. **A7 rehearsal cost.** §8.2a states it — measured on this repository (§13-V36) — bounds it with a
   shared-objects copy, prints *rehearsal ran in N s over M MB*, and refuses above a threshold.
8. **A8/A9/A10/A12/A13.** §7.1: the inventory matches `git ls-files` case-insensitively and discloses
   case-variant collisions (measured: a `scripts/Validate.sh` adoptee is told its `scripts/validate.sh`
   was kept — a path git's index does not hold, §13-V34); restore lines are shell-quoted and hostile names
   refused; §8.1: `adopt_block` vs `adopt_refuse` per `docs/messaging-standard.md`; §8.3: the v1 stamp's
   migration is CLOSED explicitly (every shipped reader reads only `adopted`, `adoptedAtCommit`,
   `adoptedAt` — §13-V39); §6.5: *"no non-interactive path"* becomes *"no unattended-DEFAULT path"*.
9. **B1/B6 Acts 3/4 get ONE shell finisher** — `adopt_act4_finish` with a data-defined
   `_adopt_act4_order` — the model writes the record and drafts, shell validates and writes, merge
   LAST; the record's schema is pinned (§8.3); every WP12a/b proof is re-targeted at the finisher.
10. **B3/B5 WP11** — `_adopt_document_set` as data with a two-way drift check; row 17 ruled by this
    author (CHANGELOG.md is KEPT — not in D3's reach); the `pending-act-4` disposition word; the
    receipt check's seam is `adopt_receipt_check`'s one call line. **And a defect measured on
    `579b0b0` that WP11's inventory must close** (§13-V34): Act 2 overwrites an adoptee's own tracked
    `PROJECT_INTAKE.md` and `.claude/intake-progress.json` at rc 0 with no archive row, no
    directory and no sentence — the APPROVAL_LOG.md class WP9b closed, recurring one file over. The
    invariant that catches the class — *no planned path that pre-exists is outside the archive
    inventory* — is §9.1-I20, checkable inside the rehearsal.
11. **B8 preconditions** (§8.1): git identity via the oracle `git commit` itself uses
    (`git var GIT_COMMITTER_IDENT`, §13-V41), `jq`, a hash tool, both approval-log templates, the
    hooks directory — all at step 0; operator hooks are unknowable in advance and are what the
    window row (A3) exists for.
12. **B9** — §2.1, the environment and repository shapes: in scope, refused, out of scope, and one
    KNOWN LIMIT, ruled 2026-09-17 (`## BL-274:` — a recorded single-authority attestation is accepted;
    the contributor's mechanism is invited as a PR and is not designed here).
13. **#418** — §5.2/§8.2's key map (M14): adoption records A7 rows under the wizard's keys where one
    exists (`accessibility` → `accessibility_target` is the only rename; four already coincide) and keeps
    its own where none does; stated as data with a two-way drift check against
    `scripts/intake-wizard.sh`'s `save_answer` set (§13-V37); the amend route `## BL-282:` chooses must
    accept adoption-recorded keys. *"pnmp test:unit"* is the adopter's own `package.json` — `git grep -n
    pnmp -- scripts templates init.sh tests docs/adoption.md docs/scout.md README.md` over this framework's
    code and shipped pages returns nothing, rc 1 (§13-V37; the whole-tree form now matches THIS
    document's own sentences, the file-claiming-about-itself trap §13-V7 records) — Scout transcribed
    faithfully (§12 item 28).
14. **#385 / `## BL-277:`** — WP9c's `.claude/settings.json` shipment ships the bypass detector's Stop
    registration now and its PostToolUse registration only when `## BL-277:` closes (§10-WP9c, §12
    item 26): an adoptee must not be born with the blocker the entry measures.
15. **#404 / `## BL-274:`** — §2.1 lists the single-authority organizational adoptee as a KNOWN LIMIT;
    R2's exemption design depends on nothing in `validate_approval_fields` (§13-V40 prints the era
    readers; the self-approval control is not among them).

**Describe, never total.** As before: this entry names its changes and does not count them.

**Not restructured.** The architect's C-list (history to appendices, §10 as subsections) is a
later, separate pass; this amendment adds to the same shape.


**v2.2, second pass (2026-09-17, later the same day) — ONE DEFECT IN THE PROPOSED WORK, found by
reading an outside contributor's issue against §10, and corrected in both places it appeared. No
decision, ruling, DECISION table or WP boundary changed — §8.1's PRECONDITION table is one of the
two places the corrected predicate appears, and it changed.** A contributor filed, on the day v2.2 merged, that
fixtures in this repository write into `.git/hooks/` without creating it and that twelve unit-lane
suites fail on a machine whose `init.templateDir` carries no `hooks/` — two of them adoption's own.
Read against §10, that condition turned WP9d's own precondition into a NEW FALSE REFUSAL: item (6)
told the implementer to test `[ -w ]` on the resolved hooks directory, and on such a machine that
directory does not exist, so `[ -w ]` is false and every adoption would be refused at step 0 — out
of the one package whose whole subject is false receipts. §8.1's row named *the resolved directory
or its parent*; item (6) did not carry the second half, and **both were then wrong in the other
direction**: a disjunction passes an EXISTING hooks directory at mode 555 under a writable `.git`
and the write is refused anyway, which is precisely the failure the precheck exists to move to step
0. The predicate is now a CONDITIONAL in both places — the directory when it exists, the parent when
it does not — with three proof cases including an explicit disjunction mutant — which is NOT, as this
entry's first draft claimed, the only case telling the two predicates apart: case (ii)'s control
already fails under a disjunction, as the independent review measured. The proof's second fixture was also corrected from `chmod 555 .git` to
`chmod 555 .git/hooks`: a `.git` at 555 fails `git add` before the run reaches the hook write, so
the mutant's control was unreachable. Every claim is measured in **§13-V47**. Two dated notes
elsewhere: §12 item 18 records that `upgrade-project.sh --backfill-only` exits 0 while reporting a
failure when it is run outside a project (the same contributor, the same day), and §10-WP9c records
the cause they identified for the `e2e-init` trio being red — `init.sh` installs its own pre-push
review gate and then makes the scaffold's first push through it — so the detour that cell takes may
become unnecessary. **The lesson this entry exists to carry:** the fixture every WP9d and WP10b
proof builds on, `tests/test-brownfield-wp9b-preflight-approval.sh`, is 103/0 under an empty
template AND under the stock one precisely because it writes no hook at all, so it held the property
by luck and hid the defect from a design that had already survived two adversarial reviews. A
fixture that passes for a reason nobody stated is not a pin.

**v2.2, third pass (2026-09-17, evening) — R1 EXTENDED BY KARL to the symlinked hooks path, hours
after the independent review filed it as an open question. One ruling extended; no decision, decision
table or WP boundary changed; §2.1 gains two rows, §8.1's precondition gains a shape rule, §10-WP9d
gains four mutations, §12 item 33 is STRUCK as ruled, and §8.3c gains M16.** The review of the WP9d
precheck correction measured three shapes the corrected write test still admits, and one of them is
not answerable by any write test: `.git/hooks` as a symlink to a writable directory outside the
repository passes `-L`, `-d` and `-w`, the hook lands THERE, and `git rev-parse --git-path hooks`
reports the link's own path — so item (3)'s derived *live* sentence re-resolves through the link,
finds the hook, and prints TRUTHFULLY about a hook this repository does not own (§13-V48). That is
the one failure mode R1 exists to end, reached by a route R1 did not name. Karl ruled it refused,
matching the two siblings that already refuse it by policy — `# BL-145-SYMLINK-GUARD-BEGIN`, whose
header calls `ln -s ~/.githooks .git/hooks` *"the classic"* case and records that a LEAF `-L` test is
not sufficient, and `# BL-209-HOOKSPATH-SAME-DIR`, which refuses a configured hooksPath because *it
can be shared across repos*. The regular-file shape takes the same refusal as **author-proposed
(M16)**: the ruling names symlinks, and leaving that one shape would keep a `mkdir` failure after the
adoption commit for one clause's worth of code. **What this did NOT change:** the write test stays a
conditional and still calls `preflight_target_writable`; the shape rules run BEFORE it, so they are
an addition to step 0's order rather than a replacement for anything.

### §0.4 — Verification posture, and the branch topology caveat

Every claim marked *verified* was **executed on 2026-08-24**; §13 prints the commands and their
output, and **§13-U lists what was NOT executed and why** — read §13-U before trusting anything
here that it names. The v2.1 amendment's claims were executed on **2026-09-16** against `01b66e3`
(§13-V17–V28; §13-U(v2.1)); the v2.2 amendment's on **2026-09-17** against `579b0b0` (§13-V29–V45;
§13-U(v2.2)).

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

**Historical as of 2026-09-16.** `## BL-242:` has been on `main` since the filing merged;
`grep -n '^## BL-242:' solo-orchestrator-backlog.md` resolves on this tree, and every v2.1
quotation was read from the working tree at `01b66e3`, not from a branch. §12 item 11 is struck
accordingly.

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

### §1.1a — What has shipped since v2.0 — derive it, never maintain it (2026-09-16)

§1.1's inventory is the v1 build's and is left as written. What landed on the adoption surface
after the status row was last measured is a **range**, not a list, and the recipe is the claim
(§13-V18):

```
git log 45a749b..HEAD --format='%h %cs %s' -- scripts/lib/adopt scripts/lib/scout scripts/adopt-project.sh
```

Twelve commits at `01b66e3`: **one v2 work package** — WP10a (`4009790`, PR #373) — and **eleven
defect fixes** under `## BL-251:`, `## BL-253:`, `## BL-225:`, `## BL-268:` and `## BL-288:`,
each reconciled by section in §0.3's v2.1 entry. Anchored on WP9b's commit because that is the
tree the 2026-09-01 status row was measured on; `f73dfca..HEAD` — the last 2026-08-31 commit, the
D-block anchor — returns seventeen, the extra five being WP9b and four 2026-09-01 corrections the
2026-09-01 passes already record. **Do not use `--since=<date>` for this:** git fills a bare date
in with the CURRENT TIME OF DAY, so `--since=2026-09-01` returned thirteen commits at 21:00 and
fifteen at 07:30 on this host, and seventeen only as `--since='2026-09-01T00:00:00'` — a recipe
that returns a different number by the hour is not a recipe.

Three counts moved with those commits, each a measurement with its date: `scripts/lib/adopt/`
holds **eight** files (`adopt-tools.sh` is new — §13-V19); the adoption-related suites number
**seventeen** by `ls tests/ | grep -i 'brownfield\|module-dep\|bl225\|bl288\|bl268\|bl253\|bl251\|bl284\|bl273'`,
**ten** of them `tests/test-brownfield-wp*.sh` (§13-V25 — at `01b66e3` `## BL-242:` said nine suites and
eight; PR #415 annotated the sentence with the dated count one merge later); and the framework's install set is **70** (§13-V20).

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
the run transcript, is the inventory. *(Re-derived 2026-09-16: still 7, same membership —
§13-V19-(1) — and the five-blocks-on-a-clean-adoptee claim, source-read in 2026-08-24's §13-V2, is
now MEASURED: §13-V27's transcript carries exactly five `NOT DONE` blocks. `adopt_stub_secrets_disposition`
gained a third arm at `## BL-288:` for `scanned-partial`; it prints and returns 0, so the silence
condition is unchanged — silent exactly when the scan ran clean over a full history.)*

| Capability (verbatim from the notice) | v1 owner | v2 owner (§10) | Announces |
|---|---|---|---|
| the assessment (Act 3) — the requirements interview, the fitness verdict and the plan *(the notice's text since WP9a retired the certification stub, A8 — `adopt_stub_assessment`; this row read "the certification pass" until 2026-09-16)* | WP5 | **dissolved into Act 3/4 — WP12a** | always |
| the Adoption Record, the audit rows and the CI carve-out | WP7 | **WP7 (re-cut)** | always |
| the provenance headers on reconstructed documents | WP7 | **WP7 (re-cut)** | always |
| the commit-time scanners (the fallback pre-commit hook) | WP7 (its printed string is stale — see below) | **WP7 (re-cut)** | always |
| your project's framework documents | nobody | **WP11 + WP12b (D3)** | always |
| installing the framework's version of *N* colliding script(s) | nobody | **WP11 (D1)** | only when N > 0 |
| the secrets disposition | nobody | **WP10b (D2)** — WP10a built the resolver and the re-scan, not the stop (§6.2a); the `scanned-partial` arms ruled 2026-09-16 are 10b's too (§6.1a) | on `scanned-partial`, on any not-`scanned` status, or when the scan found something |

The stale string: `adopt_stub_hooks` prints `Owner: nobody yet — §10 names no owner` while
`docs/adoption.md` and `scripts/lib/adopt/adopt-stubs.sh`'s own header both record Karl's decision
that the hook is WP7's. `## BL-242:` already filed the correction; **WP9 carries it** as the first
package to touch that file. *(WP9a touched the file and did not take this drive-by, on
`## BL-242:`'s reasoning that the obvious rewrite propagates a false §10 attribution — §8.3a-A8;
the string still ships on 2026-09-16, and §13-V27's transcript prints it.)*

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
`init.sh`), so the D2 secrets stop would today depend on whatever happens to be installed *(true of the v1
build this section describes; WP10a built the step on 2026-09-02 — §6.2a, §13-V19-(3'))*. The
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

### §2.1 — Environment and repository shapes in scope (added 2026-09-17, B9)

Every row is a shape this design has either measured or explicitly declined to measure; the fourth
column says which. **Refused** means Act 2 stops at step 0 with nothing written and names the
condition (R1's rows are RULED; the rest are author-proposed placements of checks the driver already
makes later, or not at all). **Out of scope** means no package owns it and the residual is written
down. **Known limit** means Karl has not ruled and this design does not depend on the answer.

| Shape | Status | What happens, and why | Evidence |
|---|---|---|---|
| An ordinary repository, `--root` at its top level, `.git` a directory, no `core.hooksPath`, an identity git can resolve, at least one commit | **IN SCOPE** — the only shape Act 2 completes on | Every §13-V27-style run is this shape | §13-V27, V29 |
| `--root` is a SUB-DIRECTORY of a repository | **REFUSED at step 0 (R1)** — and refused TODAY too, by the rehearsal, after every question | `git rev-parse --show-toplevel` (compared by physical path) is not `--root`. Measured today (§13-V32b): rc 1, `[REFUSED] the pre-write rehearsal did not complete (rc=1) — nothing was written to your project`, no `sub/.git`, no live sentence — the rehearsal's `cp -a "$root/."` carries no `.git` under `sub/` and `adopt_test_debt_record` then runs git outside a repository; the refusal is honest and arrives AFTER the tier question and every confirmation. R1 moves it to step 0, before any question, naming the sub-directory and the top level. *(BL-290's first filing said this shape completes at rc 0 with the live line — the review executed it and it does not; R-1.)* | §13-V31 (`--show-prefix`), V32b |
| A linked worktree (`git worktree add`) | **REFUSED at step 0 (R1)** — today: COMMITTED, then blocked at the hook, hookless, no route | `.git` is a FILE and `--git-dir` ≠ `--git-common-dir`; git runs hooks from the MAIN repository's `.git/hooks`. Measured today (§13-V32c): the adoption COMMITS in the worktree (HEAD moves, the manifest is at HEAD), then `mkdir -p …/wt/.git/hooks` fails on the gitfile — `[BLOCKED] could not create …/wt/.git/hooks` / *The adoption commit HAD already landed; a later step did not complete. 79 file(s) were written and committed.* — rc 1, no hook anywhere (not in the worktree, not in the main repository), no live sentence; *Not a directory* is never printed. That state is NOT the window (HEAD moved) and has NO route: `--finish` refuses on a landed adoption (§12 item 32). R1 refuses at step 0; remedy: adopt the main working tree | §13-V31, V32c |
| A submodule checkout | **REFUSED at step 0 (R1)** | `.git` is a file pointing into the superproject's `.git/modules/…`; the same gitfile test catches it, and today the same `mkdir -p` on a gitfile fails the same way (reasoned from V32c, not run). Remedy: adopt the superproject, or install the hook by hand (M1's wording) | Not separately measured — the gitfile test is the same predicate as the worktree row (§13-U(v2.2)) |
| `core.hooksPath` configured (local, global or system scope) and NOT resolving to the repository's own `$(git rev-parse --git-common-dir)/hooks` | **REFUSED at step 0 (R1)** | "Configured" is read off `git config core.hooksPath`'s EXIT STATUS, never its value, exactly as `# BL-209-HOOKSPATH-REFUSE` does — a set-EMPTY hooksPath is configured (measured: `--git-path hooks` then answers `./`). Remedy printed: `git config --unset core.hooksPath`, or install by hand. Today's behaviour is the defect: hook written to `.git/hooks`, *live* printed, git runs nothing | §13-V31, V32 |
| `core.hooksPath` configured AND resolving to the repository's own hooks directory | **IN SCOPE — author-proposed (M1), a NARROWING of R1's *configured*, not part of the ruling** | Not a redirection — the same exception `# BL-209-HOOKSPATH-SAME-DIR` carries, for the same reason (a global hooksPath that happens to point here); the compare is by physical directory, so a relative value resolves against the process cwd and the WP9d control sets an ABSOLUTE path | Source read of `scripts/install-filesystem-gates.sh`; not exercised (§13-U(v2.2)) |
| The hooks path is a SYMLINK — to a directory inside or outside the repository, or dangling; tested on the path git NAMES and on this repository's own hooks path, never on the dereferenced one | **REFUSED at step 0 (R1, extended 2026-09-17)** | The DIRECTORY is the link, not a leaf hook file: `# BL-145-SYMLINK-GUARD-BEGIN`'s header records that a leaf `-L` test is not sufficient and names `ln -s ~/.githooks .git/hooks` as the classic shape. A link to a writable directory outside the repository passes every write test, the hook lands THERE, and the derived *live* sentence is true of a hook this repository does not own; a dangling link fails at `mkdir` after the commit TODAY; under item (2)'s resolution `mkdir -p` SUCCEEDS on the link's target and the gate lands outside the repository, so after WP9d the dangling shape is case (c) and not a post-commit failure at all (the independent review measured both) | Measured by the independent review, 2026-09-17 (§13-V48) |
| The hooks path exists as a REGULAR FILE | **REFUSED at step 0 — author-proposed (M16), the same refusal by the same reasoning; the ruling names symlinks** | `[ -d ]` false → the parent arm passes → `mkdir` fails with `File exists` after the commit. Refusing it here costs one clause and removes the last shape that reaches the hook write and fails | Measured by the independent review, 2026-09-17 (§13-V48) |
| No git identity git can resolve | **REFUSED at step 0 (B8, author-proposed)** | The oracle is `git var GIT_COMMITTER_IDENT`, the same one `git commit` consults; today the failure surfaces AFTER the stamp, as the window row (§8.4). On this Mac git auto-detects an identity; on a typical container it does not | §13-V41 |
| A bare repository, or a directory with no work tree | **REFUSED at step 0 (R1's precondition)** | `--show-toplevel` has nothing to report | Not separately measured (§13-U(v2.2)) |
| An unborn HEAD (no commits) | **REFUSED today**, rc 2 | `adopt_main`'s first check: adoption records the commit it landed on | Source read (`adopt_main`) |
| A shallow clone (`--depth N`) | **IN SCOPE**, under §6.1's `scanned-partial` row (ruled 2026-09-16) | The stop's own scan is shallow too and says so; the no-checkout copy §6.2b scans inherits the shallowness — and for a shallow source git silently ignores `--shared`, so that copy is a real copy of the shallow object store (measured, §13-V35b item 10) | §13-V35, V35b |
| A full-depth `--single-branch` clone | **IN SCOPE and UNDETECTED** — `## BL-288:`'s open residual | Reported as `full-history`; a credential on an unfetched branch is invisible. Not this design's to close | `## BL-288:` |
| A partial clone (`--filter=blob:none`) | **IN SCOPE** | Every commit is present; `gitleaks git` walks all of them (`## BL-288:` measured this; not re-measured here) | §13-U(v2.2) |
| A case-INSENSITIVE filesystem (macOS default; `core.ignorecase = true`) | **IN SCOPE, with A8's disclosure** | A file of the operator's whose name differs from a framework path only by case is a collision git's index does not show; today it is reported under the framework's spelling. WP11's inventory case-folds against `git ls-files` and says which file it means | §13-V34 |
| A case-SENSITIVE filesystem (Linux ext4 — the CI lane) | **IN SCOPE** | No case-variant collision can exist; WP11's case proof SKIPS there and says so, rather than passing vacuously | §13-U(v2.2) |
| `.claude` — or any path adoption writes — a symlink out of the repository | **OUT OF SCOPE**, recorded residual | Written through, refusal reports the repository untouched (`## BL-225:`, `## BL-242:`'s symlink-follow row; §12 items 17, 21) | The entries' own measurements |
| The adoptee is itself a framework clone (cwd or `--root`) | **REFUSED**, rc 1 | `guard_not_in_framework`, both arms | Source read (`scripts/adopt-project.sh`) |
| Already adopted / a prior archive / already framework-managed | **REFUSED at step 0** (A1's three arms) | §8.2 row 0 | `tests/test-brownfield-wp9b-preflight-approval.sh` |
| The ADOPTION WINDOW — stamped in the working copy, adoption commit never landed | **IN SCOPE via `--finish` (WP9d)**; today REFUSED with the wrong route | Arises when the operator's own hook, or a missing identity, rejects the adoption commit; today's re-run says "already adopted — run resume.sh" | §13-V33 |
| Operator pre-commit / commit-msg hooks that reject the adoption commit | **IN SCOPE** — they are meant to judge it (§8.2 row 9) | The outcome is the window row above | §13-V33 |
| gitleaks older than 8.19.0 | **IN SCOPE, reported honestly** as `scan-failed` — not guaranteed usable | `## BL-289:`: the matrix floor is 8.18.0 and nothing on adoption's path enforces it | §13-V9, `## BL-289:` |
| gitleaks absent with no install recipe for the host | **IN SCOPE** — `tool-unavailable` under §6.1's row | `# BL-242-RESOLVER-NO-EXEC` | WP10a suite |
| Repo-local scanner rules: `.gitleaks.toml`, `gitleaks.toml`, `.gitleaksignore`, inline `gitleaks:allow` | **IN SCOPE** — disclosed by Scout (`configFile`), NEVER consulted by the stop | Each one silences findings in place (measured); the stop's scan runs over a no-checkout clone under the framework's config, where none of them exists — with the scan's cwd INSIDE the clone and `--gitleaks-ignore-path` at an empty location, because gitleaks reads `.gitleaksignore` from the process cwd, not the source path (§13-V35b items 9b–9d; the review's R-2) | §13-V35, V35b |
| A single-technical-authority ORGANIZATIONAL adoptee | **KNOWN LIMIT — ruled 2026-09-17: a recorded, reason-mandatory attestation is accepted; PR invited** (`## BL-274:`; `## BL-275:`'s author-vs-approver contradiction stays open) | `docs/governance-framework.md` §XIV item 5 needs a second technologist, and `validate_approval_fields`'s self-approval control fires on every row the approver commits. Nothing in this design depends on that control being satisfiable, and R2's exemption reads none of it | §13-V40 |
| A POC (sponsored or private) adoptee | **IN SCOPE as PRODUCTION** — `## BL-253:`'s residual | Adoption asks no POC question (D9 is one question); `upgrade-project.sh` moves it later | §8.3b |
| Windows, WSL, bash older than 3.2, git older than the floors named in §8.1 | **OUT OF SCOPE** — not measured | The framework's floor is bash 3.2 on macOS/Linux; git version floors are stated per feature in §8.1 with a fallback where one is cheap | §13-U(v2.2) |
| An adoptee that already owns `PROJECT_INTAKE.md` or `.claude/intake-progress.json` but no `.claude/phase-state.json` | **IN SCOPE — and today OVERWRITTEN SILENTLY** | Neither path is in the archive inventory; Act 2 `cat >`s over both at rc 0 with no row and no sentence. WP11's inventory closes it and §9.1-I20 is the invariant that would have caught it | §13-V34 |

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
order and each constraint's justification is §8.2; the summary *(two things sit outside the
numbering and are stated in §8.2: step 0, A1's re-adoption preflight, built at WP9b — and, since
2026-09-17, R1's three refusals and B8's preconditions, NOT built, WP9d; and the
rehearsal of steps 4–7 on a copy of the tree before the first real write, built with
`## BL-225:`'s second half — §8.2a)*:

1. **The tier question** (D9) — *"Who is this project for?"*, the one question Act 2 asks.
   Verbatim and first, before anything is installed or written, so an abandoned run leaves the
   host untouched too. It produces `ADOPT_DEPLOYMENT`, which step 3 reads and step 7's two state
   writers persist. Unanswered, it **refuses the run** — no default, no skip (§13-V16).
2. **Tool resolution** against the matrix — `scripts/resolve-tools.sh` with
   `templates/tool-matrix/`, **built at WP10a** (§6.2a; it was the step adoption skipped until
   2026-09-02, §13-V3). It installs the
   required set, **including `gitleaks`**, which `templates/tool-matrix/common.json` already
   carries as `"required": true` (§13-V9) — D2's stop asks for nothing the framework does not
   already demand of every scaffolded project.
3. **The secrets check** (D2, §6) — **tier-scoped**, and the tier reaches four of the five
   cases (§6.1; the fifth, `scanned-partial`, was ruled 2026-09-16 — §6.1a). No adoption proceeds past this point with a scanner that was never there
   (`tool-unavailable`) unless a `personal` project records an acceptance; no *organizational*
   adoption proceeds with an undispositioned finding or a broken scan. A casual personal adoption
   warns loudly and carries on for **both** a findings result and a `scan-failed` one. §6.1's
   ladder is the authority; it keys on step 1's answer (§6.5). **Not built — WP10b**; and the fifth
   status, `scanned-partial`, was ruled on 2026-09-16 — stop with no escape at `organizational`,
   acknowledge-on-the-record at `personal` (§6.1a) — and both arms are WP10b's as well. **(v2.2)
   The stop reads a scan Act 2 ran ITSELF, under the framework's rules — a report handed in with
   `--scan-report` is pre-fill for everything except this decision (§6.2b).**
4. **The test-debt census** — before the install, as the shipped code already orders it and for
   the reason its comment states: the census reads `git ls-files`, and independence from the
   index's timing is worth keeping explicit.
5. **The collision archive** — before any writer, now covering **five classes** (§7.3): AI-layer
   surfaces, git hooks, colliding `scripts/` (D1), colliding framework-named documents (D3), and
   `APPROVAL_LOG.md` (WP9b's `approval-log`, the only class adoption REPLACES).
6. **The framework install** — framework-wins on script collisions (D1), with the archive receipt
   checked first (§7.1).
7. **Minimal state, phase 0** — the tier-matched `APPROVAL_LOG.md` first (A4, WP9b), then
   `phase_state` → `intake` (mechanical prefill only) → **`dispositions`** (the recorded
   acknowledgements and dispositions, WP10b — §6.3) → `manifest` with the v2 stamp (§8.3) →
   **`write_set`** (the persisted list of everything this run wrote, WP9d — §8.4's window row), the
   fail-safe order carried from v1 (§8.4) with two stages added in v2.2.
8. **The adoption commit** — explicit staging, never `git add -A`, unchanged; and (WP9d) when the
   operator's own hook or a missing identity refuses it, the run ends in the *adoption window* and
   `--finish` completes it from the persisted write set — never from `git add -A` (§8.4).
9. **Hooks last** — after the commit, as shipped (`adopt_install_hooks` runs after
   `adopt_stage_and_commit`, and the commit-msg block composes by `SOIF_TDD_OPEN` marker fence) —
   **and (R1, Karl, 2026-09-17) written to the directory GIT reports, `git rev-parse --git-path
   hooks` resolved absolute, which step 0 has already verified is the repository's own.** The
   handoff's *live* sentence is DERIVED: printed only after a re-read of that path finds the marked
   block there; otherwise the run says the hook was not installed and why (§8.2 row 9). Today the
   path is a literal `.git/hooks` and the sentence is unconditional — measured wrong under a
   configured hooksPath (§13-V32).

Act 2 ends by printing where the project stands (phase 0; assessment pending) and
the exact next command: run `bash scripts/resume.sh` in the adoptee and paste the prompt into
Claude Code.

### §3.4 — Act 3 — ASSESS

Claude Code, entered through the machinery that already exists for exactly this job:
`scripts/resume.sh` is the single state-aware first-message generator, currently four branches
(intake / `PROJECT_INTAKE.md` §13 verbatim / classic resume / `# DELTA-RESUME-PHASE4`), and today
containing **zero** mentions of adoption (§13-V8; re-measured 0 on 2026-09-16, §13-V19-(4)). WP12a adds the adoption branch: manifest says
`adopted: true` and the adoption block carries no completed assessment → emit the assessment
prompt (§8.5). In the session: the **requirements interview** (D7's five axes plus data
classification, §5.2) and **all evaluators** run against the installed tree. Act 3's output is a
written **assessment record** — machine-readable findings, the fitness verdict, and the
interview's answers — because Act 4's documents and plan must be derivable from it, not from
session vibes. **Under D10 the record carries no rung**, and nothing downstream reads one.
**(v2.2)** The interview also records whether the software is **in production** (R2, §5.2), and
Act 3 ends by RUNNING a shell finisher — `adopt_act4_finish`, invoked from the framework clone
`.claude/orchestrator-source.json` names, with a data-defined stage order `_adopt_act4_order` —
which VALIDATES the record the model wrote against its pinned schema and performs every write
(§8.3, §10-WP12a). The model writes JSON and drafts; it never writes state.

### §3.5 — Act 4 — PROCEED

The framework documents are written per D3 (§7.2); the verdict — including, possibly, *rebuild*
(§5.4) — is presented per D8 (§5.5); the **Phase 0 intake is filled in** from everything Acts 1–3
learned; and the project proceeds into the ordinary Build Loop **from phase 0**. Act 4 writes no
`current_phase`: under D10 there is nothing to place, and the project advances only by passing
`scripts/check-phase-gate.sh` like any other. Act 4 is deliberately thin — everything expensive
happened in Act 3, and it now has one less thing to do than the first draft of this section gave
it. **(v2.2)** Mechanically, Act 4 IS the finisher's later stages: `documents` (WP12b — a stub that
announces itself in WP12a) and then `merge`, LAST (A2), which is what makes the interruption rows of
§8.4 re-offer rather than skip.

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

**One deliberate loosening — RULED by Karl on 2026-09-17 (R2, §0.1a) — and why it keeps the
promise.** An adopted project that is ALREADY IN PRODUCTION — the interview asks, the answer is
recorded — sits at phase 0 like every other adoptee, and phase 0 has no route for the thing such a
project needs first: an urgent fix that ships today and owes a written-up account afterwards. That
route is the delta track's, and `scripts/delta.sh --open` refuses below phase 4
(`# DELTA-OPEN-ERA-GUARD`, exit 3), because the delta track's own design (§10.1 there) rightly
forbids post-release ceremony from substituting for building the product. **R2 opens exactly that
route, for exactly that population**: a project whose manifest records `adopted: true` AND an
assessment that recorded *in production: yes* may open a delta below phase 4, with the exemption
written into the delta record (`active_delta.exemption`) and into the process state
(`.adoption_exemptions[]`), and — author-proposed, WP7's content — listed in the Adoption Record. What it does NOT open: any phase
gate — `scripts/check-phase-gate.sh` does not read the exemption and WP12c's last proof pins that
its verdict is byte-identical with and without it (§9.1-I18); the resume script's post-release
GREETING — an adopted-in-production project with nothing open is routed to its Phase 0 entry, not
told *"this product has shipped"* (§8.5); and the landing — `current_phase` stays 0. So the promise
stands in the form D10 gave it: nothing lands high, nothing is grandfathered; a released project
gets to file a hotfix and owes the retro, which is stricter than what it had before adoption, not
looser. The mechanism — field name, predicate, record shapes, resume order — is author-proposed
(M13, §8.3c); the exemption itself is Karl's.

### §3.7 — Module shape under the four acts

M1–M5 of `docs/module-contract.md` stand unchanged, and `scripts/lint-module-dependencies.sh`
keeps enforcing the direction rule with its five-glob CORE set (`# BL-215-CORE-GLOB-SYNC`). Two
points of contact the acts create, both resolved without spending severability:

- **`scripts/resume.sh` is core and shipped; the adoption branch must not source module code.**
  It does not need to: the branch predicate reads **state** — `.adoption` in
  `.claude/manifest.json` via `jq` — the same way the shipped `# DELTA-RESUME-PHASE4` branch reads
  phase-state. Reading a state file the module wrote is not a `core → module` edge; sourcing
  `scripts/lib/adopt/` from `resume.sh` would be, and is forbidden.
- **What `resume.sh` points at must exist in the adoptee**, since `docs/adoption.md` is
  deliberately not shipped downstream. v2.0–v2.1 gave Act 2 an *assessment brief* to write under
  `.claude/adoption/` for that purpose. **v2.2 DROPS the brief (A6, author-proposed):** WP9a's
  `## 13.` prompt already carries what the brief was for (the project is adopted, at phase 0, the
  blank cells are questions, the survey is evidence of what exists), WP9c ships
  `docs/reference/builders-guide.md` beside it, and a third orientation document would be the
  two-owners pattern §5.1 warns about. What `resume.sh`'s fifth branch emits is the assessment
  prompt WP12a renders, which names the finisher command (§8.5); the prompt's *"WHAT YOU DO NOT
  HAVE"* paragraph becomes DERIVED from what WP9c wrote rather than a fixed sentence.

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
| `docs/adoption.md` | The chooser section ("The one question", the verbatim block, S1/S2 landing prose, the floor rule, "What both scenarios share") — **WP9's**, not WP12's. **This cell said "WP12's page revision" and contradicted this section's own completion check**, which is that V7's grep returns nothing *after WP9*; both could not hold. WP9 removes those sections and states the phase-0 landing; the rest of the page's v2 revision stays WP12b's |
| `scripts/check-phase-gate.sh` (core) | The cosmetic `.adoption.scenario` read in the `[OK] Adoption stamp present and intact` line, which would otherwise print `scenario: unknown` on every v2-adopted project forever. **This row was MISSING from this table until WP9's build found it by grepping for readers of the stamp's fields** — the very inference failure the paragraph below this table describes, committed inside the table it describes. It changes no `issues` increment and therefore no gate verdict (§9 holds); `tests/test-bl166-gate-scope.sh` mentions the line in a comment and asserts nothing about it (**A8**) |
| `scripts/lib/adopt/adopt-intake.sh` | `$ADOPT_SCENARIO`'s five parameter sites, `adopt_judgment_question`'s scenario branch, `adopt_ops_addendum` whole, and — under **A7** — the judgment / non-skippable arms of `adopt_run_reverse_intake` including `adopt_ask_data_classification` and `# BF-ADOPT-DC-MANDATORY`. Not in this table before either, for the same reason |
| `scripts/lib/adopt/adopt-stubs.sh` | `adopt_stub_certification` (WP5 is RETIRED, §5.1) and the `$ADOPT_SCENARIO`/`$ADOPT_LANDED_PHASE` parameters of `adopt_stub_adoption_record` (**A8**) |
| `workflow.html` | The Step-B and Step-C cards — the verbatim question, the *Two scenarios* card (`S1 … lands at current_phase: 4`), the floor-rule card, *"data classification is non-skippable in both scenarios"*, and the stamp card naming *"the scenario, the landed phase, the certification lists"*. **THIS ROW IS THE THIRD TIME THIS TABLE HAS BEEN SHORT, and it is the one that matters most**: the page is linked from `README.md`'s ninth line as the walkthrough *"written for non-engineers"* and is served over GitHub Pages. It escaped §4.2's own completion check because the sentence is **LINE-WRAPPED** there, and a single-line `grep -F` cannot match a wrapped literal — so the check reported a clean tree while the most-read description of the feature still described the deleted question. The check is now a whitespace-normalised sweep of every **tracked** file (§10-WP9's `C2`), with the wrapped case pinned by its own mutant (`C4`) |
| `scripts/lib/scout/scout-report.sh`, `scripts/lib/scout/scout-phasemap.sh` | **THE SIXTH TIME THIS TABLE HAS BEEN SHORT — and this row was created by the branch's OWN later commit**, which edited both files to retire the floor-rule note and did not add them here. §9's Scout row is amended to match. The lesson is the one this table keeps teaching: a blast radius is not a thing you enumerate once, it is a thing that grows while you work inside it |
| `README.md` and `docs/scout.md` | **THE FOURTH AND FIFTH TIME THIS TABLE HAS BEEN SHORT, both found in the review of the commit that announced the third.** `README.md`'s brownfield bullet still said adoption *"caps an in-flight project at the phase its own evidence supports"* — the floor rule, deleted — and called the certification pass *"designed and not yet implemented"* when it is RETIRED. `docs/scout.md` still said the classification is *"non-skippable in every scenario"* and that *"the driver, the chooser and the interview ship and work"*. **Neither carries the verbatim question, so no widening of C2 would ever have found them**: the defect class is stale prose describing deleted machinery, and the only check that covers it is a reader. Recorded as the standing limit of this table rather than papered over with a lint that cannot exist |
| `tests/test-brownfield-wp4-driver.sh` | `CHOOSER_LITERAL` pins the question's **presence**; v2 re-aims it to pin **absence** (§10-WP9's mutation). Its **P** block (P1–P5, placement and the floor rule) and its Act-2 classification cases (I3, I5, I6, I7) assert deleted behaviour and go with it; every answer script in the suite shortens, because Act 2 now asks the tier question and the scan-derived confirmations and nothing else |

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

The verbatim question exists at exactly ~~three~~ **four** places in the code-and-shipped-docs
surface today — the fourth, `workflow.html`, is a row above and was found by adversarial review,
not by this enumeration. **Two further files carry deleted machinery without carrying the sentence**
(`README.md`, `docs/scout.md`), which is why the count of the SENTENCE and the count of the BLAST
RADIUS are different questions and only the first is checkable — the chooser lib, the docs page, the WP4 suite (§13-V7; the two design documents also
carry it, v1 as the decision it settled and this one twice, in V7's printed command and in §6.5's
D9 argument) —
which bounds the deletion's search space. **WP9's completion check is C2, NOT V7's grep, and the
difference is not pedantry**: V7's printed command still returns
`tests/test-brownfield-wp9-act-boundaries.sh`, because a suite that asserts a sentence's absence
must spell the sentence. An unqualified "returns nothing" was therefore false the moment the
suite existed. C2 is the check that carries the qualification — a whitespace-normalised sweep of
every TRACKED file with two allowlisted carriers named and reasoned (the frozen v1 design and the
suite itself).

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

**One question RULED into the interview on 2026-09-17 (R2, §0.1a): *is this software in
production?*** Yes or no, asked by the model, recorded in the assessment record as `inProduction`
(the name is author-proposed, M13) and merged into `.adoption.assessment.inProduction` by the
finisher's LAST stage (A2). It is D9's shape again — a fact the operator knows for certain and no
evidence can determine — and it is the SOLE input to R2's exemption (§3.6, §8.5, §10-WP12c). It is
not a maturity self-report: it says nothing about how far along the project is, only whether real
users are on it today. A `no` is recorded as explicitly as a `yes`, so an ABSENT key means *never
asked* (an assessment older than this amendment), never *no* — the exemption predicate reads
`== true` and nothing else.

**The keys the interview writes — and the A7 rows Act 2 records — use the WIZARD's vocabulary
wherever one exists, and adoption's own key only where none does (M14, from contributor issue
#418; author-proposed).** The defect the issue found: `adopt-intake.sh`'s A7 arm records the
judgment rows blank under `scripts/lib/scout/scout-prefill.sh`'s section-level keys — `timeline`,
`mvp_features`, `competency_matrix`, `revenue_model`, `governance`, `accessibility` — and
`scripts/intake-wizard.sh` never writes those names (its vocabulary is `mvp_date`,
`accessibility_target`, … — §13-V37 derives the set), so no wizard route can amend them and
`## BL-282:`'s proposed `--set-answer` (entry-only, four options) would refuse them. §8.3a-A7's
*"the route that re-asks it exists"* is therefore true only if Act 3 writes through the wizard's
vocabulary. The map, as DATA — it belongs in `_scout_prefill_table` as a seventh column,
`wizardKey`, so both writers read one table:

| Adoption field (`_scout_prefill_table`) | Section | Wizard keys at `579b0b0` (§13-V37) | Rule |
|---|---|---|---|
| `project_name` | 1 | top-level `project_name` (what `load_progress` subscripts) | coincides — written top-level today |
| `repo_remote_configured` | 1_repo_setup | `repo_url`, `repo_visibility`, `git_host` | no 1:1 — adoption keeps its own (a yes/no the wizard does not record) |
| `problem_statement` | 2 | `problem_statement` (+ `metric_N_*`, `exclusion_N`) | coincides |
| `timeline` | 3 | `mvp_date`, `hard_deadline`, `hours_per_week`, `time_pattern`, `monthly_budget`, `one_time_budget`, `geo_distribution` | no 1:1 — Act 2 keeps its own, BLANK; Act 3 writes the fine-grained keys |
| `mvp_features` | 4 | `feature_N_name/trigger/failure`, `should_have_N`, `will_not_N`, `primary_persona`, `secondary_personas`, `user_type` | dynamic family — as above |
| `data_classification` | 5 | `data_classification`, `zdr_attested`, `zdr_attestation_reason` (+ `input_N_*`, `output_N_*`, `integration_N_*`) | coincides; the finisher writes it through `adopt_persist_phase1_artifacts` (A7's kept function) |
| `competency_matrix` | 6 | `competency_KEY`, `competency_KEY_tooling`, `infra_KEY`, `languages_known`, `frameworks_used`, `db_experience`, `devops_experience`, `willing_to_learn` | dynamic family — as above |
| `revenue_model` | 7 | `pricing_model`, `price_point`, `breakeven`, `cost_per_user`, `competitive_range` | no 1:1 — as above |
| `governance` | 8 | `gate_KEY`, `escalation_KEY`, `precondition_N_status/details`, `compliance_N`, `refuse_to_use`, `exit_success/failure/conditional` | dynamic family — as above |
| `accessibility` | 9 | `accessibility_target` (+ `color_vision`, `dark_mode`, `responsive`, `browsers`, `min_os`, `min_os_versions`) | **THE ONE RENAME: adoption records `accessibility_target`** |
| `uptime` | 10 | `uptime` (+ `hosting*`, `backup`, `retention`, `maintenance_window`, `dist_channels`, `sev_*_sla`) | coincides |
| `known_risks` | 11 | `known_risks` | coincides |
| `test_command` | 11_5 | `testing_interval`, `bug_tracking_tool`, `human_tester_count`, `uat_role`, `beta_testing` | no wizard key — adoption keeps its own (scan-derived, confirmed) |
| `tooling` | 12 | `ide`, `primary_machine`, `docker_available`, `ai_subscription` | no wizard key — adoption keeps its own (scan-derived, confirmed) |
| `agent_init_prompt` | 13 | — | dropped at render (`adopt_render_intake_doc`), as today |

**The drift check is two-way, and it is the WP2 suite's existing currency canary widened** (its
`P1` already derives the runner list from the real `scripts/intake-wizard.sh`; Scout may not read
the wizard, the suite may): (a) every row whose `wizardKey` names a wizard key must resolve in
`grep -oE 'save_answer +"[a-z_0-9]+"' scripts/intake-wizard.sh` (or be `project_name`); (b) every
row that keeps adoption's own key must NOT resolve there — a wizard key later named `timeline`
turns that row red until it converts. The interview's D7 axes map to the same vocabulary
(author-proposed first cut, WP12a's to refine): users → `users_launch`/`users_6mo`/`users_12mo`;
availability → `uptime`; exposure → `hosting` plus an `assessment.exposure` namespace key (no wizard
home); scalability → `users_12mo`/`data_volume`; data sensitivity → `data_classification`; in
production → `inProduction` (no wizard home — it is the assessment's, §3.6). **Whichever amend route
`## BL-282:` lands must accept adoption-recorded keys present in the progress file** (§12 item 28),
for projects adopted before the rename; the rename itself is WP12a's, and may land earlier as a
one-row drive-by because it touches one table and one renderer.

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
(§10-WP12a pins the scaffold with a check), and a verdict whose plain half is missing or whose
recommendation carries no reasoning does not render. The reasoning IS the deliverable.

One vocabulary note this document practices as well as preaches: the shipped driver prints *"the
framework's two message gates are live"* — under the standard those are **checks** (they are not
phase boundaries). Quoted strings stay verbatim; new prose, including every string WP9 touches,
uses the controlled vocabulary.

---

## §6 — Secrets: an organizational adoption stops, a casual personal one warns loudly (D2)

### §6.1 — Five status-and-findings cases (four until 2026-09-12), and the tier reaches four of them

`scripts/lib/scout/scout-secrets.sh` emitted exactly three statuses when this section was written,
and its own comment stated the taxonomy this design builds on (§13-V5): *"`scanned` with zero
findings is a positive result. `tool-unavailable` is 'nobody looked'. `scan-failed` is 'we looked
and something went wrong'."* **Since 2026-09-12 it emits four** (`## BL-288:`; §13-V21 prints the
widened comment), and the fourth has its own row below, ruled on 2026-09-16 (§6.1a).

| Status | Meaning | `deployment = organizational` | `deployment = personal` |
|---|---|---|---|
| `scanned`, findings = 0 | gitleaks ran, report parsed, clean | Proceed | Proceed |
| `scanned`, findings > 0 | Real findings, redacted per v1 §6.2's field allowlist | **STOP until every finding carries a recorded disposition** (§6.3) | **WARN LOUDLY and carry on** — every finding printed redacted and recorded in the Adoption Record; no disposition demanded, and no silence either |
| `tool-unavailable` | gitleaks not on the host | **STOP — hard refusal.** No flag, no attestation, no escape (§6.4). After WP10, reachable only if tool resolution itself failed | **STOP, escapable.** Proceeds only on a recorded acceptance — named person, reason, date, §6.3's shape, refused if unrecordable (§6.4) |
| `scan-failed` | gitleaks exited non-zero, or its report did not parse | **STOP; fix and re-run. No escape** — a successful scan is a hard requirement here (Karl: *"it cannot continue as it's required"*). "Could not measure" is never "nothing to measure" — the fail-open posture `docs/messaging-standard.md` Part 2 names a defect wherever it appears | **WARN LOUDLY and carry on** — treated *as if the scan had run* (Karl, 2026-08-31). No recorded acceptance demanded; the warning must say plainly that **nothing is known** about this history, because there is no findings list to print |
| `scanned-partial` (`scope: shallow-history`) — **row added 2026-09-16** | gitleaks ran over the commits git HAS; a shallow clone gave it part of the history and the report says so, with the commit count walked (`## BL-288:`) | **STOP — no escape** (Karl, 2026-09-16: *"go with the split"*). The refusal prints the remedy already shipped at four operator-facing sites (plus one comment) — `git remote set-branches origin '*' && git fetch --unshallow`, then a deliberate re-scan. The findings the partial scan DID produce are reported, and once unshallowed §6.3's per-finding dispositions apply to every finding before proceeding | **STOP, escapable on the record** — the operator may acknowledge and continue; the acknowledgement is **RECORDED** in the same place and shape as the `tool-unavailable` acknowledgement — §6.3's shape: named accepting person, reason, date, plus the scope and commit count the report already carries (author-proposed, §0.1) — and adoption **refuses to proceed if it cannot record it**. Every finding the partial scan produced is printed redacted, and the partial scope is stated in those words — never rendered as clean (§6.1a). **Not built — WP10b** |

**The tier governs every row but the clean one**, and the ladder it describes is a **severity**
ladder rather than a status ladder. On `organizational` a successful scan is a hard requirement:
findings must be dispositioned, and neither `tool-unavailable` nor `scan-failed` — nor, since
2026-09-16, `scanned-partial` — has any escape at all. On `personal` the requirement softens by
how far the framework's own setup fell short:

| What happened | `personal` outcome |
|---|---|
| The scan ran and found things | Warn loudly, carry on — the findings are known and printed |
| The scan ran and broke (`scan-failed`) | Warn loudly, carry on — **treated as if it ran** (Karl, 2026-08-31) |
| The scanner was never there (`tool-unavailable`) | Stop; carry on **only** on a recorded acceptance |
| The scanner ran over PART of the history (`scanned-partial`, a shallow clone) | Stop; carry on **only** on a recorded acknowledgement in §6.3's shape — named accepting person, reason, date, plus scope and commit count (ruled 2026-09-16, §6.1a; the fields are author-proposed, §0.1) |

**The one deliberate step in that ladder is worth naming, because it is not obvious.** A
`scan-failed` personal project and a `tool-unavailable` personal project end in the same
epistemic state — nobody knows what is in the history — yet the first proceeds on a warning and
the second needs a signature. The distinction Karl's ruling draws is **not epistemic; it is
whether the required tool was present and attempted** — gitleaks ran and stumbled, versus gitleaks
was never installed. Act 2's tool resolution (§6.2) is what makes the second case a failure of the
framework's own setup rather than an environment hiccup, and that is what earns it the higher bar.
**This design records the step rather than smoothing it**; if it proves wrong in practice the fix
is one cell of the table above. *(The 2026-09-16 ruling put `scanned-partial` at the same rung as
`tool-unavailable` — a recorded acknowledgement, not a warning — although there the scanner WAS
present and attempted; what fell short was the checkout, and the commits it withheld are exactly
where a removed credential lives. So "was the required tool present and attempted" predicted
`scan-failed`'s rung and did not predict this one; the ruling is recorded as ruled, in Karl's
three words, and this document does not manufacture a longer reason for it — §6.1a.)*

*(Two earlier drafts of this paragraph were wrong in the same direction. The first said the tier
"governs one row of that table and no other" and that the bottom two rows were "byte-identical
across the tiers"; the second, written after the `tool-unavailable` ruling, said the tier reached
"two of them" and that `scan-failed`'s cells were "still identical". Both generalised an argument
about `scanned`-with-findings — "the tier is about loudness on a known finding" — into a claim
about rows it had never been tested against. The tier reaches three.)* *(Four since 2026-09-16 — the
`scanned-partial` row, §6.1a. The sentence before this one is left as the history it is.)*

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
either tier, on either arm. **And (v2.2) what the `organizational` column READS is a scan Act 2 ran
itself, under the framework's rules — §6.2b states the mechanism and the trust boundary: the tier
answer is self-declared and nothing can check it; the stop defends the declared-organizational
project against a stale or doctored report and against the project's own scanner rules, and defends
nobody who declared personal.**

### §6.1a — A FIFTH status, `scanned-partial`, and the row it takes — RULED (Karl, 2026-09-16)

§6.1's table was written against three status words and `## BL-288:` (2026-09-12) added a fourth to
the scanner's own enumeration — the comment at the head of `scripts/lib/scout/scout-secrets.sh`
now reads `secstatus scanned | scanned-partial | tool-unavailable | scan-failed`, beside a new
`secscope full-history | shallow-history | working-tree-only` (§13-V21, `# BL-288-SHALLOW-SCOPE`).
The case it names is a **shallow clone**: `--depth 1` is what CI hands out by default, gitleaks
walks the commits it is given and reports zero findings, and Scout used to write `scope:
full-history`, `status: scanned` over a credential the scanner was never shown — in the fixing
commit's own words, it *"reported scope full-history with status scanned and zero findings"* on a
`--depth 1` checkout (`2a8fafb`). Now the scope says `shallow-history`, the status says
`scanned-partial`, the report carries the commit count actually walked (`git rev-list --count
HEAD`, emitted as the secrets section's `commitsScanned`), and the report's `schemaVersion` moved
**1 → 2** so the widened enumerations are announced to consumers rather than slipped past them. So
§6.1's four status-and-findings cases are **five**.

**What adoption does with it today: reports honestly, decides nothing.** Both of adoption's
readers were widened in the same fix (`# BL-288-RESCAN-PARTIAL`, both sites in §13-V21).
`_adopt_rescan_secrets` puts `scanned-partial` on the *scanned* side of its guard — a partial scan
is a scan that LOOKED, and re-running it moments later in the same clone at the same depth would
return `scanned-partial` again, so the remedy is the operator's (`git remote set-branches origin
'*' && git fetch --unshallow`, then a deliberate re-scan — the string ships at four operator-facing sites plus one comment, §13-V21),
not an automatic re-walk. `adopt_stub_secrets_disposition` gained its own arm, which says the scan
*ran but could only read part of this history* and returns 0 — the old *"did not run a secrets
tool"* sentence would have been false here, and false in the direction that makes an operator
discount the warning. Neither reader stops or proceeds on the status, because **nothing in Act 2
decides anything on the status until WP10b** (§13-V22, V28).

**Which row of §6.1's tier table this status takes is RULED — Karl, 2026-09-16: *"go with the
split."*** The check that it needed a ruling rather than an extrapolation: `## BL-242:`'s D2 text
was byte-identical at `01b66e3` to its 2026-08-31 state (§13-V17), twelve days before the word
`scanned-partial` existed, so no ruling there could name it (PR #415 then added the one ruled row,
so from `7b88c2e` the sections differ by exactly that paragraph); and `## BL-288:`'s entry decides Scout's own posture
(report, never refuse — a read-only survey pointed at somebody else's checkout must not stop) and
the two readers above, and nowhere assigns the status a tier outcome (grep the entry for `tier`,
`organizational`, `personal`, `stop`, `proceed` — the two hits are a quotation of
`docs/adoption.md`'s table and a sentence about an operator's response to a tool that refuses to
run). The question was raised as §12 item 16 on 2026-09-15 while this amendment was drafted, and
ruled the next day. **The ruling:**

- **`deployment = organizational` — `scanned-partial` STOPS, with no escape.** The refusal prints
  the unshallow remedy already shipped at four operator-facing sites (`git remote set-branches origin '*' && git
  fetch --unshallow`, then a deliberate re-scan). The findings from the commits the scan DID read
  are still reported, and once unshallowed §6.3's per-finding dispositions apply to every finding
  before the adoption proceeds — so a partial scan with findings at this tier needs both the
  unshallow AND the dispositions, because the findings it did produce are real.
- **`deployment = personal` — the operator may ACKNOWLEDGE AND CONTINUE, and the acknowledgement
  is RECORDED.** In the same place and shape as the `tool-unavailable` acknowledgement (§6.3:
  named accepting person, reason, date — recorded, and refused if it cannot be recorded; the
  `# BL-233-ATTEST-REFUSE` doctrine), and adoption **refuses to proceed if it cannot record it**.
  The ruling names no fields. That the record also carries the scope and the commit count the
  report already holds is **author-proposed** (§0.1), not part of the ruling — a reviewer may
  attack it; nobody may build a signer-less or reason-less record from it.
  Every finding the partial scan produced is printed — that much is the ruling's. That it is printed
  *redacted*, and that the partial scope is stated in those words — never rendered as clean — is
  author-proposed (§0.1), not the ruling's.

**Consistent with the sibling ruling, and stated so.** This is §6.4's shape for `tool-unavailable`
— *"yes on personal, no on organizational"* (Karl, 2026-08-31) — with the findings the partial scan
did produce added to both arms. It is NOT `scan-failed`'s shape: at `personal` a `scan-failed`
warns and carries on with no record, while a `scanned-partial` proceeds only on a recorded
acknowledgement. The drafted recommendation this amendment carried on 2026-09-15 — never landed in
this document — had put the personal arm at `scan-failed`'s warning; the ruling put it at the
signature, which is why this document asks rather than extrapolates (§0.3, v2.1). The distinction
the ruling draws is recorded, not reasoned past: a `scanned-partial` result is a scanner that was
present and ran, so §6.1's *"was the required tool present and attempted"* predictor put it beside
`scan-failed`; the ruling puts it beside `tool-unavailable`, and the reason on the record is Karl's
three words and nothing this document adds to them.

**What is built, and what is not.** NOTHING of the ruling is built: the organizational stop and
the personal recorded acknowledgement are **WP10b's** (§10), and at `01b66e3` no adoption code
refuses on the status — the stub prints and returns 0, the re-scan guard groups the status with
`scanned`, and `adopt_refuse` is never reached on it (§13-V28). §10-WP10's eight status×tier cells
are **ten**, and the ninth and tenth pairs need their own mutation in each direction like the two
not-scanned statuses already have.

**What WP10b must not do.** Not collapse `scanned-partial` into `scanned` for the stop/proceed
decision. It sits on the `scanned` side of the RE-SCAN guard, which asks a different question
(*did a tool look?*) from the table's (*may adoption proceed?*), and a fixture matrix that inherits
the guard's grouping would pass against an implementation that issues a shallow clone a clean bill
of health — the exact sentence `## BL-288:` exists to prevent, reached one package later. And not
render the personal arm as a warning: a partial scan acknowledged with nothing written down is the
advisory posture §6.3 exists to replace.

### §6.2 — Tool resolution makes the scanner guaranteed

Act 2's **second** step runs `scripts/resolve-tools.sh` against `templates/tool-matrix/` (§8.2; the
tier question is step 1 under D9) — the step the
shipped driver never takes (§13-V3). `gitleaks` is already a `"required": true` entry in
`templates/tool-matrix/common.json` (category `secret_detection`, `min_version` 8.18.0, install
recipes for brew/apt/dnf/pacman — §13-V9), so **D2 demands nothing the framework does not already
demand of every scaffolded project**; adoption was simply not asking. **Two caveats the 2026-09-16
sweep added, filed as `## BL-289:`:** the floor is BELOW what the scanner Scout actually runs needs —
`scout-secrets.sh` invokes the `git` and `dir` subcommands, which gitleaks' README dates to v8.19.0
(the release that deprecated `detect`/`protect`), so on 8.18.x the scan fails as an unknown command
and lands in `scan-failed`; and NOTHING on adoption's path enforces the floor — `grep -c min_version
scripts/resolve-tools.sh` → 0 (only `check-versions.sh` reads it) and `_adopt_tool_present` is
presence-only (`# BL-251-PROBE-HOST`). "Guaranteed" in this section's heading means guaranteed
PRESENT, not guaranteed usable; §12 item 10 widens WP10b's pin accordingly. CI is unaffected
(`tests.yml` pins 8.30.1 with a checksum). Ordering consequence: the
Scout report Act 2 consumes may predate the install and carry `tool-unavailable` — so **when the
consumed report's `secrets.status` is not `scanned` — nor, since `## BL-288:`, `scanned-partial`
(§6.2a) — Act 2 re-runs the secrets scan after tool resolution** rather than trusting a stale
"nobody looked". A fresh `scanned` result replaces the
report's secrets section, and the persisted copy at `.claude/adoption/scout-report.json` (already
written and SHA-recorded by the shipped state writer) reflects what was actually acted on. **(v2.2)
That guard governs the RE-SCAN; the STOP has its own rule, §6.2b: its input is a scan Act 2 ran
itself, over a no-checkout copy of the history, under the framework's rules — whatever report was
handed in, and whatever status it carried.**

### §6.2a — Built at WP10a (`4009790`, merged 2026-09-04 as PR #373), and what it deliberately does not decide

The step above is `adopt_resolve_tools` in `scripts/lib/adopt/adopt-tools.sh`, called once from
`adopt_main` at `# BL-242-RESOLVER-CALL`, between the tier question and the reverse intake (§13-V19).
Read from source on 2026-09-16, by function:

- **The resolver is invoked as a command, not sourced** — `_adopt_resolver_path` prints
  `$ADOPT_FRAMEWORK_ROOT/scripts/resolve-tools.sh`, or whatever `SOIF_ADOPT_RESOLVER` names, which
  is the seam the suite drives so no test installs software on the host that runs it. The matrix
  it is handed is the FRAMEWORK root's (`--matrix-dir "$ADOPT_FRAMEWORK_ROOT/templates/tool-matrix"`);
  nothing copies it into the adoptee (§8.7a row 7).
- **A scanner already on `PATH` costs no subprocess** — `# BL-251-FAST-PATH` (`## BL-251:`, Closed,
  PR #375): `_adopt_scanner_present` short-circuits to the re-scan (`# BL-251-FAST-PATH-RESCAN`),
  measured by that entry as 545 s → 100 s across the three affected suites with assertion counts
  unchanged.
- **It asks before it installs** — `adopt_ask_choice "setting up $name" "Set $name up now?"` with
  the answers *set it up now* / *skip it*. An unanswered question refuses the run as every
  mandatory question does; a *skip* prints that the scan will report nothing looked, re-scans, and
  the adoption **completes** — the header's own promise that *"a `tool-unavailable` result still
  completes an adoption here exactly as it did before this package"*.
- **A URL where a command was expected is refused, never executed** — `# BL-242-RESOLVER-NO-EXEC`:
  anything the resolver filed under `manual_install`, or a payload `_adopt_cmd_is_runnable`
  rejects, is printed as an instruction to install by hand. The install itself runs under `eval`
  in `$ADOPT_WORK` (`# BL-242-RESOLVER-INSTALL`), and success is **verified, not asserted** —
  `_adopt_tool_present` is probed afterwards (`# BL-242-RESOLVER-VERIFY`), because a recipe's exit
  status is not the tool being on `PATH`. `adopt_tree_fingerprint` is taken either side of the
  `eval`, and a difference raises `# BL-225-TOUCHED-UNBOUNDED` (§8.2a) — an installer recipe may
  write anything anywhere.
- **The re-scan reuses Scout's own projection** — three libraries, the third (`scout-core.sh`) the
  one a first cut missed; refuse-loud early returns; `# BL-242-RESCAN-HONEST` prints one sentence
  per resulting status, including a `scanned-partial` arm reachable when a `tool-unavailable`
  report triggers a re-scan that then meets a shallow clone. The guard is
  `case "$status" in scanned|scanned-partial) return 0 ;; esac` (`# BL-242-SECRETS-RESCAN`,
  `# BL-288-RESCAN-PARTIAL`), and the refreshed report is what every later step reads
  (`# BL-242-RESOLVER-REFRESH`).
- **It makes no stop/proceed decision.** The file's header says so in as many words and names
  §6.1's table, §6.3's dispositions and §6.4's tiered escape as WP10b's (§13-V22); the
  `scanned-partial` arms ruled on 2026-09-16 are WP10b's too (§6.1a).

Pinned by `tests/test-brownfield-wp10a-tool-resolution.sh` — 54/0 at `01b66e3` (§13-V24) — through
the `SOIF_ADOPT_RESOLVER` seam, which is why that suite does **not** pin the shipped matrix's
`gitleaks` entry (§12 item 10).

**A residual found at WP10a's review, recorded on `## BL-242:` and not fixed:** the shared resolver
files gitleaks' documentation URL in the `auto_install` bucket on a host without the package
manager, and `init.sh` executes that bucket — plus an unpinned, unverified root install in the
Linux recipe. WP10a defends its own consumer with the refusal and the probe above; the defect is
upstream of both consumers and is not WP10's boundary.

**Re-cut in v2.2 (§6.2b).** `# BL-242-SECRETS-RESCAN`'s `scanned|scanned-partial` early return stays
what it is for the re-scan; the STOP does not read that section at all — WP10b scans a no-checkout
shared clone of the history under the framework's config and reads that. The header's *"makes no
stop/proceed decision"* stays true of 10a's code; the decision, and its input, are 10b's.

### §6.2b — The stop keys on a scan Act 2 ran ITSELF — mechanism and trust boundary (A2, A11; author-proposed, 2026-09-17)

**What the stop must not trust — measured.** Three inputs can put a clean-looking secrets section in
front of step 3 over a live credential, and at `579b0b0` all three reach it:

1. **A handed-in report.** `--scan-report FILE` is consumed as-is — `adopt_obtain_report` checks
   `[ -f ]` and nothing else — and `# BL-242-SECRETS-RESCAN` returns early on `scanned` and
   `scanned-partial`, so a report that says `scanned, 0` — a week stale, or edited — is what step 3
   would read.
2. **The project's own scanner rules.** `gitleaks git` honours a `.gitleaks.toml` or `gitleaks.toml`
   at the root, a `.gitleaksignore` at the root, an inline `gitleaks:allow` comment, and
   `GITLEAKS_CONFIG`/`GITLEAKS_CONFIG_TOML` in the environment. Scout discloses the first pair
   (`configFile`) and detects neither of the next two. Measured on gitleaks 8.30.1 (§13-V35): a
   repo-local `.gitleaksignore` takes a planted key from **1 finding to 0 and NO flag restores it**
   — not `--gitleaks-ignore-path` at an empty file, at a directory holding an empty one, or at a
   nonexistent path, and not `-c` either; a `.gitleaks.toml` allowlist takes it to 0 and
   `-c <framework config>` restores it; an inline allow is restored only by `--ignore-gitleaks-allow`;
   the env takes it to 0 and `-c` outranks the env.
3. **The archive scan already refuses two of these structurally** — `adopt_archive_scan` scrubs
   `GITLEAKS_CONFIG*` and scans a directory that cannot hold the toml — for the ARCHIVE. The history
   scan had no equivalent.

**The mechanism (M7).** The stop's input is a scan THIS RUN performed, under the FRAMEWORK's rules,
over the SAME history:

- **Step 3 scans a no-checkout shared clone** of the adoptee, made in `$ADOPT_WORK`:
  `git clone --shared --no-checkout "$root" "$ADOPT_WORK/history"`. The object store is shared
  (measured: 0.04 s and 108 KB for a 1,840-commit history — §13-V35), HEAD and `rev-list --count`
  are identical, a shallow source yields a shallow clone (so `scanned-partial` still applies and
  `commitsScanned` matches — measured) — **for a SHALLOW source git silently IGNORES `--shared`**:
  the clone is a COPY of the shallow object store with no `alternates` file (measured, §13-V35b
  item 10; the review's probe found it, v2.2's first run never checked the file). Shallowness and
  findings are unaffected; only the cost is, by a shallow clone's objects — the small case. And
  **the working tree is EMPTY**, so no `.gitleaks.toml`, `gitleaks.toml` or `.gitleaksignore` can
  exist where gitleaks looks for them — **PROVIDED the scan's cwd is the clone.** gitleaks reads a
  `.gitleaks.toml` from the SOURCE path but a `.gitleaksignore` from `--gitleaks-ignore-path`,
  whose default is `.` — the PROCESS cwd — and Act 2 runs with cwd = the adoptee root. Measured
  (§13-V35b items 9b–9d, the review's probe re-run here): the same clone scanned with cwd = the
  adoptee finds 1 of 2 plants, the adoptee's `.gitleaksignore` being read from cwd; with cwd = the
  clone, 2 of 2; with cwd = the adoptee plus `--gitleaks-ignore-path /nonexistent/x`, 2 of 2. So the
  invocation `cd`s INTO the clone — Scout's `( cd "$root" … )` projection already does exactly that
  with the clone as `$root` — AND passes `--gitleaks-ignore-path` at a path holding none, belt and
  braces; the cwd is load-bearing, WP10b's proof (2) is what pins it, and a build that scanned the
  clone from the adoptee's cwd would fail it (the review's R-2). Measured (§13-V35, items 8–9): with
  a tracked toml, a tracked ignore file and an inline allow all present, the in-place scan under `-c`
  and `--ignore-gitleaks-allow` still finds only 1 of 2 plants — the `.gitleaksignore` hides the
  other — and the no-checkout clone's scan, cwd inside it, finds 2 of 2.
  Nothing is written into the adoptee — the clone lives under `$ADOPT_WORK`, the directory
  `## BL-225:`'s T9 already exempts as the driver's own.
- **The invocation forces the framework's rules**: `-c "$ADOPT_FRAMEWORK_ROOT/templates/gitleaks/framework.toml"`
  — a vendored config whose whole content is `[extend]` `useDefault = true`, so the rule set is
  gitleaks' own defaults for the installed version and never a repo-local file — plus
  `--ignore-gitleaks-allow`, with `GITLEAKS_CONFIG` and `GITLEAKS_CONFIG_TOML` unset in the scan's
  subshell exactly as `adopt_archive_scan` does. Author-proposed home for the config:
  `templates/gitleaks/framework.toml`; the stop runs from the framework clone, so nothing need
  ship to the adoptee.
- **It reuses Scout's projection** exactly as `_adopt_rescan_secrets` does today — three libraries,
  one allowlist (`SCOUT-SECRETS-ALLOWLIST`) — with the clone as `$root`; the section is spliced
  into the report through `# BL-242-RESOLVER-REFRESH`'s mechanism, the persisted
  `.claude/adoption/scout-report.json` carries it, and the stamp's `scannerReportSha256` therefore
  hashes THE SCAN THE STOP USED — the property §6.2 asks for, now true of the stop and not only of
  the re-scan.
- **Two fields are added to the persisted secrets section** (author-proposed): `scannedBy:
  "adoption"` and `rulesSource: "framework"`. Scout's own section carries neither, so a reader can
  tell the survey's scan from the stop's. The survey's `configFile` disclosure stays in the
  transcript, re-worded: *your project carries `.gitleaks.toml`; the stop did not use it.*
- **`--scan-report` is therefore pre-fill for everything except the stop** — the reverse intake, the
  evidence block, the matrix's language, the stack — and its secrets section is replaced by the
  stop's. When no report was handed in, Scout ran moments ago in this process; the stop STILL scans
  the clone, because Scout honours the project's rule files by design (`## BL-288:`: a read-only
  survey must not refuse) and the stop must not.
- **Cost:** one history walk, measured at **1.4 s over 1,840 commits and 819 tracked files** on this
  repository, the same 1.4 s the in-place scan costs; the clone is not what costs (§13-V35). On a
  history where it is expensive, it is expensive once — and for the operator who handed in a report
  to save that cost, the answer is that the STOP was never going to take it on trust.

**Which tier.** BOTH. The mechanism is tier-blind by construction — it is the only scan step 3 has
— which is simpler than *re-scan at organizational only* and removes a tier branch a mutant could
route around. What the tier decides is unchanged: what §6.1's table does with the result.

**The trust boundary, stated (A11).** The tier answer is SELF-DECLARED and nothing in this design
can check it — D9 keeps the question precisely because it is a fact no evidence can determine. So:

- The stop DEFENDS a project whose operator declared `organizational` against: a handed-in report
  that is stale or edited; a repo-local `.gitleaks.toml`/`gitleaks.toml`, a `.gitleaksignore`, an
  inline `gitleaks:allow`, a `GITLEAKS_CONFIG*` in the launching environment; and a partial history
  presented as full (`## BL-288:`).
- It DEFENDS NOBODY who declared `personal`. That arm warns and carries on by D2, and an operator who
  declares personal to avoid the stop has made a RECORDED choice — `deployment` sits in both state
  files, and the assessment interview (D7) re-asks who the project is for in its own terms. This is
  recorded as the boundary, not as a hole to close: the alternative — infer the tier from evidence —
  is D4's forbidden move pointed the other way.
- It DOES NOT DEFEND against: a scanner older than 8.19 (`## BL-289:` — reported as `scan-failed`,
  which organizational stops on); a `--single-branch` clone (`## BL-288:`'s residual — undetectable);
  a credential gitleaks' default rules do not recognise (the rule set is the tool's, and the stop is
  only as good as it); or a history rewritten before adoption (invisible by definition — the report's
  `historyRewrite` field is the survey's hint, not a control).

**Why not a sixth status word.** The brief offered a `scanned-under-project-rules` status with a
STOP. It is not needed: the stop's scan is structurally rule-free, so there is no
under-project-rules result for the stop to receive. Scout's report may still be one, and says so via
`configFile`; that is Act 1's disclosure, kept as it is.

**Rejected alternatives.** *Scan in place with a "no config" flag* — no such flag exists, and no
combination of flags ignores a repo-local `.gitleaksignore` (measured, §13-V35). *Re-scan only at
`organizational`* — a tier branch in the mechanism that a mutant can collapse, and a `personal`
warning printed from a stale section; the tier-blind form costs the same walk. *Trust a handed-in
report whose `scannedBy` says `adoption`* — that field is exactly what a doctored report would
carry. *Move the rule files aside temporarily* — a write into the operator's tree during step 3,
before the rehearsal, which `## BL-225:`'s invariant (§9.1-I4) forbids.

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

**The two records, and which is which (B2; author-proposed — the rulings require only that an
acknowledgement be RECORDED and REFUSED if it cannot be).** The framework already carries two
attested-escape records this design reuses by shape — `# BL-072-TDD-ENFORCE`'s `tdd_attestations[]`
rows, `{date, subject, reason, files}`, and `# BL-233-ATTEST-REFUSE`'s `mcp_attestations[]` rows,
`{date, reason, blocked_on}`, both in `.claude/process-state.json`, both refused when unrecordable
(§13-V43 prints both writers). Adoption's two:

1. **The JOIN TABLE — `.claude/adoption/secrets-dispositions.json`** (committed; rehearsed like every
   write; author-proposed schema v1):

   ```
   { "schemaVersion": 1,
     "scan": { "head": "<40-hex>", "commitsScanned": N,
               "scope": "full-history | shallow-history",
               "status": "scanned | scanned-partial | tool-unavailable | scan-failed",
               "reportSha256": "<sha256 of the persisted scout-report.json>" },
     "dispositions": [
       { "fingerprint": "<commit>:<file>:<ruleId>:<startLine>",
         "disposition": "rotated | false-alarm | accepted-risk",
         "by": "<named person>", "reason": "<free text, required>",
         "date": "YYYY-MM-DD", "rotatedOn": "YYYY-MM-DD"        # rotated only
       } ],
     "acknowledgements": [
       { "kind": "tool-unavailable | scanned-partial",
         "by": "<named person>", "reason": "<required>", "date": "YYYY-MM-DD",
         "scope": "<the report's scope>", "commitsScanned": N, "head": "<40-hex>" } ] }
   ```

   The `scan` block binds the file to ONE scan — HEAD and `commitsScanned` when the stop ran. A file
   whose `scan.head` is not the current HEAD, or whose `commitsScanned` differs from the stop's own
   scan, is STALE: every disposition in it is re-confirmed interactively, or refused
   non-interactively — that is *per-run acknowledgement keyed on HEAD + commitsScanned*. `by` is a
   NAME; a blank `by` or `reason` is not a disposition, and `false-alarm` needs a reason that is not
   the rule id alone (v1 §6.3's rule). The file carries fingerprints, rule ids and line numbers —
   never a value; it is written from the projected findings and inherits the allowlist by
   construction.
2. **The EVENT — one `adoption_event` row per `accepted-risk` disposition and per acknowledgement**,
   appended through `bypass_audit_append` with `details.event: "secrets_disposition"` — the
   vocabulary `scripts/lib/bypass-audit.sh`'s header already reserves and names *unowned* (§13-V43)
   — `actor: "framework"`, `final_outcome: "recorded_only"`, and `details` carrying
   `{fingerprint | kind, by, reason, date}`. The row is the audit event; the join table is the
   durable per-finding state a re-run reads. A `rotated` or `false-alarm` disposition accepts no risk
   and writes no row.

**Where it is COLLECTED and where it is WRITTEN (A4).** Collected at STEP 3 — `--dispositions FILE`
(author-proposed flag: the file above, or a path to one) with an interactive fallback that asks, per
undispositioned finding, the disposition, the name, the reason and the date through the same
`adopt_ask_*` primitives (so an unanswered question refuses), and — at `personal` on
`tool-unavailable` or `scanned-partial` — the acknowledgement's name and reason. VALIDATED at step 3,
before any write: signer, reason, and that every fingerprint is in the stop's own findings (one
that is not is refused as stale). Held in run state. WRITTEN at step 7 as the `dispositions` stage
of `_adopt_state_order`, after `intake` and before `manifest` — so the rehearsal covers it, the
audit rows are appended inside the write phase (the rehearsal's rows land in the COPY's ledger and
are discarded with it), and a refused append — `bypass_audit_append` returns 1 on a corrupt ledger
or a lock timeout — refuses the run at that stage, before the stamp, as a BLOCK (§8.1) whose
write-state sentence derives through `# BL-225-REFUSE-DERIVED`. The STOP itself — no dispositions
at `organizational`, or an organizational partial or absent scan — fires at step 3 with nothing
written, and it is a block too: a check ran and was not passed.

**Required even at `findingCount` 0.** An acknowledgement acknowledges a GAP in what was scanned,
not a finding: a `personal` `tool-unavailable` or `scanned-partial` result with zero findings still
needs one (§6.1's ladder), and the join table's `scan` block is written even when `dispositions` is
empty, because *we scanned, at this HEAD, and found nothing* is a record worth having.

**The rotate-and-re-run loop.** A rotated credential is still in history; the next run's scan finds
the same fingerprint; the join table says `rotated`, with a date; the run proceeds without asking
again. The operator passes the SAME file — or nothing: when `--dispositions` is absent and the
adoptee already carries `.claude/adoption/secrets-dispositions.json`, it is read (author-proposed
default). Each run re-validates the file against its own scan; a finding that vanished — history
rewritten — is REPORTED as vanished, never silently dropped from the table. On a stop the exit code
is 1 and the label is `[BLOCKED]` (§8.1).

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

**A fifth status exists since 2026-09-12 and was ruled on 2026-09-16 with this section's shape — stop
at both tiers, escapable only at `personal` and only on the record — §6.1a.**

### §6.5 — Where the tier value comes from: the audience question, kept and re-purposed (D9)

**SETTLED — Karl, 2026-08-31.** §6.1's table keys on `deployment`, and `deployment` comes from the
audience question the shipped driver already asks. This section was written as an open question,
because `## BL-242:`'s D4 blast radius said that question was being deleted; **it is not** (§4.2),
and the options below are kept as the record of what was weighed rather than deleted as spent.

The untiered first pass read no setting at all, so §6 had no dependency on the tier; the
2026-08-25 refinement gives it one. Three derived facts (§13-V15) frame it:

1. **`ADOPT_DEPLOYMENT` has exactly ONE writer in the shipped driver — `adopt_ask_audience`** —
   and four readers — `adopt_write_phase_state`, `adopt_write_manifest`, `_adopt_approval_template`
   (A4's log-template selector) and `adopt_render_intake_progress` (`grep -n ADOPT_DEPLOYMENT
   scripts/lib/adopt/*.sh`; this line said two until the 2026-09-16 sweep — the two writers were
   the readers when it was written).
2. **`## BL-242:`'s D4 blast-radius line said `adopt_ask_audience` goes**, and §4.2's table and
   §10-WP9's scope inherited it. **That line over-reaches** (established below, and filed against
   `## BL-242:` D4) — **D9 keeps the question**, so the producer stays.
3. **The manifest that would otherwise hold the tier is written at Act 2 step 7**
   (`# BF-ADOPT-STATE-ORDER`: `phase_state intake manifest`), while the secrets check is step 3
   (§8.2) — before any write, deliberately, so a stopped adoption has changed nothing. **So the
   tier can never be read from the manifest in Act 2**, whatever produces it; it must come from a
   variable held in the run. `ADOPT_DEPLOYMENT` is that variable, and both state writers already
   consume it — the value is asked once and read by four functions.

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
(a non-interactive run)"* — and it assumed an UNATTENDED-DEFAULT path **that does not exist**
(§13-V16; wording corrected 2026-09-17, A13: answers MAY be piped on stdin — every adoption suite
does exactly that, and `adopt_stdin_init` reads them from fd 3 — so *"no non-interactive path"* was
false as written; what does not exist is a path that answers a mandatory question ON THE OPERATOR'S
BEHALF). The driver's whole flag set at `579b0b0` is `--root`, `--scan-report`, `--re-add`,
`--version`, `-h/--help` (v2.2 proposes `--dispositions` and `--finish`, §10), and
`adopt_ask_choice` **refuses the run** on an unanswered mandatory question
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

**Three edges added 2026-09-17 (A8, A9, B5; author-proposed; WP11's).**

- **Case-variant collisions are matched, not missed (A8).** On a case-insensitive filesystem —
  macOS's default; git records it as `core.ignorecase = true` at `git init` (§13-V34) — an
  operator's `scripts/Validate.sh` and the framework's `scripts/validate.sh` are ONE file to
  `[ -e ]` and two names to git's index. **Measured at `579b0b0`** (§13-V34): adoption reports
  *"yours, kept: scripts/validate.sh"* — a path `git ls-files` does not hold — while the index
  holds `scripts/Validate.sh`. Under framework-wins as v2.1 specified it, `cp -p` onto the
  framework's spelling would overwrite the operator's CONTENT and keep the operator's NAME, and the
  index would carry the framework's bytes under `Validate.sh` with no `validate.sh` anywhere —
  working on the Mac, broken on Linux CI, silently. WP11's inventory therefore matches every
  install-set path against `git ls-files` CASE-INSENSITIVELY (`tr '[:upper:]' '[:lower:]'` on both
  sides — bash 3.2 has no `${var,,}`), discloses a case-variant collision by the OPERATOR's
  spelling (*yours, archived: `scripts/Validate.sh` — it sits where the framework's
  `scripts/validate.sh` goes, differing only in case*), archives it under class `script`, removes
  the operator's spelling from disk and from the index (`git rm --cached -- scripts/Validate.sh`,
  staged explicitly with the rest — never `git add -A`), and installs the framework's spelling. The
  oracle for *this filesystem folds case* is `core.ignorecase` first and a runtime probe (`a` and
  `A` created in `$ADOPT_WORK`) second. On a case-SENSITIVE filesystem no variant collision can
  exist, and the suite case says SKIPPED there, never passed.
- **Restore lines are shell-quoted, and hostile names are refused (A9).** `restore` in the
  MANIFEST is built from tree-controlled names — `find` over `.git/hooks` and `.claude/skills` —
  by string concatenation (`"cp " + $ad + "/" + $ap + " " + $op + " && chmod " + …` in
  `adopt_archive_write`), so a name carrying a space, a `$`, a backtick or a `;` produces a line
  that does something else when pasted. WP11 builds every operand with jq's `@sh`, the disclosure
  prints the same quoted form, and `--re-add` — which reads `archivedPath` and `mode` from the
  MANIFEST directly and never the restore string — is unchanged. A name the TSV inventory cannot
  carry (a newline, a carriage return or a tab) is REFUSED at the inventory, before any copy, with
  the path printed byte-escaped: a row that re-opens a column shifts every later field, which is
  `adopt_record_answer`'s own rule one file over. The proof RUNS the restore line, as the WP6
  suite's `A5` already does, on an entry whose name holds a space.
- **The receipt check has a name and one seam: `adopt_receipt_check` (B5).** ONE function, called
  ONCE per install-set path from `adopt_install_framework` immediately before its `cp -p`, returning
  0 iff the destination is absent OR the MANIFEST holds a row whose `originalPath` — case-folded
  per the first bullet — is that path; otherwise the run BLOCKS (§8.1) naming the path. Mutation B
  of §10-WP11 needs a fault the real run can reach, not a `sed`: the seam is a test-only
  environment variable, `SOIF_ADOPT_INVENTORY_SKIP_CLASS=script` (the `SOIF_ADOPT_HALT_AFTER`
  precedent), that makes `adopt_archive_inventory` skip one class. With the seam set, adoption
  BLOCKS at the receipt check on a colliding fixture — the positive proof; with the seam set AND the
  one call line removed, the operator's file is overwritten and the run completes — RED. The two
  together are the defence-in-depth proof v1 §7.1 promised and no cell ever specified.

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
siblings; WP11 derives the list from **`init.sh`'s writers ∪ Act 4's write set**, per the
denominator paragraph below, rather than maintaining this parenthesis). Their `README.md` stays theirs; their CI stays under §7.4's carve-out.

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
archived document path — never a count — and WP12b's document writing must repeat the invitation
at the point the new file is created, because that is when the operator can act on it.

Timing across the acts: the **archive** of every colliding framework-named document happens in Act
2 (the archive precedes any writer — the invariant that makes the archived copy *theirs*); the
**writing** happens in Act 4, where a model can actually adapt content per D3 and stamp v1 §8.6's
provenance headers on everything that describes what already existed. Between the acts the
originals remain in place and untouched — Act 2 archives; only Act 4 replaces. An Act 4 write to a
pre-existing path whose original is not in the archive MANIFEST refuses, same receipt rule as
§7.1 — **except where that path's existing content carries an Act-4 provenance header whose
adoption identity matches this tree's stamp (`adoptedAtCommit`), which means Act 4 wrote it in an
interrupted earlier attempt and is re-writing its own output** (A2, §8.4). Without the exemption
the rule refuses every net-new document Act 4 itself created — the path exists, and no archived
original exists because the adoptee never had one — and re-entry deadlocks. **The exemption lifts
the REFUSAL, not the archiving:** the current content is re-archived before it is rewritten, so
even a matched overwrite is recoverable.

**Three scoping facts the first draft of this rule left unstated, each of which broke something:**

- **The rule scopes to the D3 DOCUMENT WRITER, not to every Act 4 write.** Read unqualified it
  refuses Act 4's own first-entry writes — `PROJECT_INTAKE.md` (Act-2-written, in no MANIFEST,
  headerless) and the manifest merge itself.
- **The unheaded outputs need their own discipline**, because v1 §8.6 exempts forward-looking
  documents from headers, so A2's exemption cannot pass them: the **verdict artifact**, the
  assessment **record**, and the **brief** all live under `.claude/adoption/` — an adoption-owned
  home — and are **overwritten by their own writer on re-entry**, no receipt check. That also
  gives the verdict artifact the file home the rest of this document never named.
- **WP11 needs a nameable helper** for the receipt check, because Act 4 is a model session and
  WP12b's proofs must have a mutation target (author-proposed `adopt_receipt_check`).

**`PRODUCT_MANIFESTO.md` is in the required set and is written by NOBODY IN ADOPTION (A3).** It
arrives when the ordinary Phase 0 produces it — `init.sh` writes no manifesto either
(*"PROJECT_BIBLE.md / PRODUCT_MANIFESTO.md are created by no script"*), the Phase-0 agent authors
it, and D10 makes an adoptee's Phase 0 the same Phase 0. *(An earlier draft said "written in WP12b
after the intake is confirmed", which would have built a duplicate adoption-side writer against
the agent path — the two-owners pattern §5.1 warns about — and re-created the routing skip one
step later.)*

**THE ARCHIVE-CLASS DENOMINATOR IS `init.sh`'s WRITERS ∪ ACT 4's WRITE SET, and the difference has
teeth.** The prose set above names `PRODUCT_MANIFESTO.md` and `PROJECT_BIBLE.md`; the
init-writer derivation excludes both, because init writes neither. Left there: a pre-existing
`PROJECT_BIBLE.md` is never archived at Act 2, so Act 4's bible write hits the receipt rule and
**deadlocks on the feature's central deliverable** for any bible-owning adoptee; and a pre-existing
`PRODUCT_MANIFESTO.md` is never archived and — under A3 — never replaced, so it holds
`resume.sh`'s kickoff predicate false forever and the Phase-0 entry is **silently skipped** for
exactly that population. WP11 derives from the union and keeps the init-writer set as a **drift
check**, not as the definition — and, since the review's R-11, REMOVES the manifesto from its path at
Act 2, because archiving alone leaves the predicate false (the table below).

**`_adopt_document_set` — the denominator as DATA (B3; author-proposed, 2026-09-17).** WP11 spells
the set once, as rows `<path>\t<class>\t<act-2 disposition>\t<act-4 writer>`, and WP12b's finisher
consumes the same function — one table, two readers, so the set at Act 4 is the set Act 2
archived. The rows, with where each comes from:

| Path | Class | Act 2 disposition | Act 4 writer (WP12b unless stated) | Source of the row |
|---|---|---|---|---|
| `CLAUDE.md` | `document` | `pending-act-4` | `soif_render_claude_md` (the shipped renderer) plus the model's adaptation | `init.sh` writer (`generate_claude_md`) |
| `FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md` | `document` | `pending-act-4` | from `templates/generated/{features,bugs,release-notes}.tmpl` plus the assessment; the retrieve-from-archive invitation repeated at each write (§7.2) | `init.sh` `cp` writers ∩ D3's ruled reach |
| `PROJECT_BIBLE.md` | `document` | `pending-act-4` | WP12b | Act 4's write set — NOT an `init.sh` writer, which is the drift check's reason to exist |
| `PRODUCT_MANIFESTO.md` | `document` | **`removed-for-phase-0`** — archived AND REMOVED from its path at Act 2 (author-proposed, M9; the review's R-11 — see the paragraph below) | NOBODY in adoption (A3) — the ordinary Phase 0 writes it | Act 4's write set, by absence (A3) |
| `PROJECT_INTAKE.md` | `document` | `replaced` — Act 2 writes it; **measured OVERWRITTEN with no row today, §13-V34** | — | `init.sh` writer (`soif_render_project_intake`) |
| `docs/reference/<the eight>` | `document` | `replaced` — by WP9c: copied when absent, archived-and-replaced when present | — | `init.sh` `cp` lines (§13-V38 names the eight) |
| `docs/INDEX.md`, `docs/IDENTIFIERS.md`, `docs/archive/README.md` | `document` | `pending-act-4` | from `doc-index.tmpl`, `identifiers.tmpl`, `archive-readme.tmpl` | `init.sh` writers |
| `CHANGELOG.md` | — | **KEPT** (row 17, below) | — | `init.sh` writer, EXCLUDED by rule |
| `APPROVAL_LOG.md` | `approval-log` | `replaced` | — | WP9b's row, unchanged |
| `.claude/intake-progress.json`, `.claude/orchestrator-source.json` | `state` — a new class | `replaced` — both overwritten by Act 2 today, the first measured (§13-V34) | — | Act 2's own writers |

**The drift check is two-way.** (a) Every `init.sh` document writer — the §8.7a recipe over `cp` and
`cat >` targets ending `.md`, plus the function-body writers — is a row, or an EXCLUDED row with a
reason. (b) Every row is an `init.sh` writer or is written by a stage of `_adopt_act4_order`; a
path in neither is a phantom. It lives in WP11's suite and is re-run by WP12b's.

**Why the manifesto is REMOVED and every other document is left at its path (R-11; author-proposed,
M9).** v2.2's first cut had Act 2 archive a pre-existing `PRODUCT_MANIFESTO.md` *"so the kickoff
predicate is not held false"* while WP11's proof said every archived document is STILL AT ITS PATH
after Act 2. Both cannot be true: `scripts/resume.sh`'s kickoff branch is `if [ ! -f
"PRODUCT_MANIFESTO.md" ]`, and a file left at its path holds that predicate false exactly as before,
so an adoptee owning a manifesto would land in the CLASSIC prompt after assessment — the outcome
WP12b's A3 pin calls RED. Archiving is not enough for this one document because its PRESENCE is a
routing fact. So Act 2 archives it under `document` and REMOVES it from its path, disposition
`removed-for-phase-0`; the disclosure names it, says in as many words that the Phase 0 the project is
about to run writes the new one and that content can be retrieved from the archive into it (D3's
informing rule); `--re-add` restores it, warned and recorded, like any other archived file — an
operator who wants their manifesto back can have it, and takes the classic-prompt routing with it,
knowingly. Every other `document` row stays at its path until Act 4 replaces it, because nothing
routes on their presence. The drift check's third clause admits the word. *Rejected alternative:*
route an adopted project into Phase 0 by its `.adoption` block instead of by the manifesto's absence
— it changes a shipped core predicate every project shares (`# BL-202-INTAKE-PREDICATE`'s sibling)
to serve one population, and a manifesto that predates the framework is precisely the document D10
says must be produced from the beginning.

**Row 17 — `CHANGELOG.md` — RULED BY THIS AUTHOR, not by Karl, and labelled so: KEPT.** D3's reach
ruling names `FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md` and stops (Karl, 2026-08-31); `init.sh`
writes a fourth from `changelog.tmpl`. Reading D3 as reaching it would be the fourth inference
recorded as a ruling in this document's history, so it is not read that way: `CHANGELOG.md` stays
v1-D5's *project files: keep theirs* — never archived, never written by Act 4. The consequence is
stated: `scripts/check-changelog.sh` (shipped since `## BL-254:`, run by the generated CI) checks
only that the file CHANGED when source changed — `SOIF_STRICT_CHANGELOG` decides warn or fail — so
an operator's own changelog satisfies it as well as the template does (§13-V38's read of its
header). If Karl rules the other way, one row moves from EXCLUDED to `document` and nothing else
moves.

**The `pending-act-4` disposition word (B3).** WP9b's MANIFEST field is forward-looking — `replaced`
on `APPROVAL_LOG.md` means *this adoption WILL replace it*, and reads that way on an interrupted
run. A `document` row archived at Act 2 and rewritten at Act 4 cannot honestly say `replaced` at
Act 2, because Act 4 may never run: it says `pending-act-4`, and WP12b's finisher rewrites the row
to `replaced` — one jq edit, its own stage of `_adopt_act4_order`, after the document is written —
with a second archive copy per A2 on re-entry. The drift check's third clause: every `document`
row reads `pending-act-4`, `replaced`, `removed-for-phase-0` (the manifesto only) or
`kept-by-rule`, never `kept`, which is the AI-surface word and would claim the original is still at
the path after Act 4 has replaced it.

### §7.3 — One mechanism, FIVE classes (four by design, a fifth added at WP9b)

`adopt_archive_inventory` already emits `<originalPath>\t<class>\t<archivedPath>` rows and the
MANIFEST already carries per-entry class, sha256, mode, and restore lines; `git-hook` entries
already get a what-it-did description. D1 and D3 add classes `script` and `document` to the same
inventory, the same MANIFEST, the same disclosure block, the same `--re-add` route, and the same
pre-staging secrets scan — one mechanism serving four cases rather than three mechanisms — and a FIFTH, `approval-log`, added at WP9b for `APPROVAL_LOG.md`, the only entry adoption REPLACES (`disposition: "replaced"`; every other row is `kept` or `composed`). It is deliberately NOT folded into `document`, which WP11 owns (D3): borrowing that class here would poach its vocabulary and its notice text. **The emitted set is `ai-settings`, `skill`, `git-hook`, `approval-log` — derive it from `adopt_archive_inventory`, not from this sentence, which has been wrong once already**, which is
`## BL-242:`'s stated reason for cutting it this way. **v2.2 gives WP11 two more: `document` (D3 —
the rows of `_adopt_document_set`, §7.2) and `state` (Act 2's own state files that pre-exist and are
overwritten today — measured, §13-V34); WP11's inventory also reads the `git-hook` class from the
directory `git rev-parse --git-path hooks` reports rather than a literal `.git/hooks` (R1, §8.2 row
9). Derive the set after WP11 too; do not count it.** The archive home
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

**Exit codes and LABELS (A10; author-proposed, 2026-09-17; WP9d moves the shipped sites, the
unbuilt packages use the right primitive from the start).** `adopt_refuse` keys its label on the
WRONG FACT: it prints `[BLOCKED]` when files were written and `[REFUSED]` otherwise
(`# BL-225-REFUSE-HONEST`), while `docs/messaging-standard.md` Part 2 keys the two words on whether
a CHECK RAN — *block: a check ran and you did not pass it; refuse: the tool declined to start and
changed nothing*. The rehearsal's ignore-rule refusal, the staging preflight, the secrets stop and
the receipt check are all checks that ran and were not passed, and every one prints `[REFUSED]`
when nothing was written — sending the operator to *fix the conditions the tool needs* when the
remedy is to satisfy a check. §13-V42 inventories the fifty-eight call sites by file. The split:

| Site (function or marker) | Kind | Label | Write-state sentence |
|---|---|---|---|
| The step-0 arms (`adopt_preflight`), the templates, the directory name, `jq`, an unborn HEAD, the git identity and hash tool (B8), the hooks placement (R1) | a precondition the tool needs | `[REFUSED]` — *did not begin* | *nothing was written* — true here by construction |
| An unanswered or unrecognised mandatory answer (`adopt_ask_choice`, `adopt_ask_free`) | a precondition | `[REFUSED]` | DERIVED — a question may follow the resolver's `eval` (`# BL-225-REFUSE-DERIVED`) |
| The secrets stop and an unrecordable acknowledgement (WP10b); the rehearsal's ignore refusal (`# BL-225-PREWRITE-REFUSE`); the staging preflight (`# BL-225-STAGE-PREFLIGHT`); the receipt check (WP11); the overwrite-inventory invariant (§9.1-I20); the Phase 0 intake write without a classification (WP12a) | **a check ran and was not passed** | **`[BLOCKED]`** | DERIVED — *nothing was written* through `# BL-225-REFUSE-DERIVED`'s intersection, or the written count, or *the commit HAD landed* |
| An I/O failure inside a writer (could not create, write, copy, render, stamp); a rejected adoption commit | the tool could not continue | `[BLOCKED]` — as today | as today |

Mechanism: a second primitive, `adopt_block REASON`, prints `[BLOCKED]` and reuses `adopt_refuse`'s
derivation for the sentence; `adopt_refuse` keeps `[REFUSED]` and its derivation. Exit code 1 for
both; 2 stays usage or an unusable target. The suite pins the LABEL deliberately: §10's preamble
forbids trusting a label as a proxy for a verdict, and here the label IS the property — vocabulary
compliance — with the verdict pinned beside it by rc.

**Preconditions, and WHEN each is checked (B8; the content of R1's three is ruled, every
placement is author-proposed).** The rule: anything knowable before the first question is checked
before the first question, so a refusal never arrives after a stamp.

| Precondition | Checked today at | Proposed | Oracle |
|---|---|---|---|
| A git repository with at least one commit | `adopt_main`'s first lines, rc 2 | unchanged | `git rev-parse --verify HEAD` |
| `jq` | `adopt_main`, rc 2 | unchanged | `command -v jq` |
| `--root` is the repository's top level; `.git` is a directory; no redirecting `core.hooksPath` (R1) | **NOT CHECKED** — the hook is written blind (§13-V32) | step 0, WP9d | `git -C root rev-parse --show-toplevel` compared to `pwd -P`; `[ -d root/.git ]`; `git -C root config core.hooksPath`'s EXIT STATUS, then its physical directory against `$(git rev-parse --git-common-dir)/hooks` (`# BL-209-HOOKSPATH-SAME-DIR`'s comparison) |
| A git identity git can resolve | **NOT CHECKED** — fails at the commit, after the stamp (§13-V33's class) | step 0, WP9d | `git -C root var GIT_COMMITTER_IDENT`, rc 0 — the oracle `git commit` itself uses (§13-V41) |
| A hash tool (`shasum` or `sha256sum`) | the manifest stage, `# BF-ADOPT-SHA-REQUIRED` — after seventy-odd files | step 0, WP9d | `command -v` |
| Both approval-log templates | step 0, `# BL-242-PREFLIGHT-TEMPLATES` | unchanged | `[ -s ]` |
| Write access to the hooks directory | **NOT CHECKED** — fails after the commit | step 0, WP9d | **The hooks path must be a real directory or absent** — a symlink is refused (R1, extended 2026-09-17) and a regular file is refused (M16), and **the test is taken on the path git NAMES, before the absolute form dereferences it, and on this repository's OWN `$(git rev-parse --git-common-dir)/hooks` as well** (§13-V48; the first wording said *the resolved hooks path*, which is this document's term for `_adopt_hooks_dir`'s output — and both of its spellings follow the link, so the ruled guard could not have fired on the one shape it exists to refuse) — and then **CONDITIONAL, not a disjunction:** `[ -w ]` on the resolved directory when it EXISTS, on its PARENT when it does not. *(This row read "the resolved directory or its parent" until 2026-09-17. A disjunction is wrong in one direction and was measured wrong: an existing `.git/hooks` at mode 555 under a writable `.git` satisfies the parent arm and then refuses the write — `permission denied` — which is the very failure the precheck exists to move to step 0, §13-V47.)* The derived *live* sentence covers the residue |
| `git add --dry-run`, `git check-ignore --no-index`, `git rev-parse --is-shallow-repository` (git ≥ 2.15, with the `shallow`-file fallback Scout already carries), `--path-format=absolute` (git ≥ 2.31 per git's documentation — NOT measured here, §13-U(v2.2); the fallback is `cd "$(git -C root rev-parse --git-path hooks)" && pwd -P` from `root`, which needs no floor) | assumed | unchanged; floors stated here | — |
| The operator's own hooks accepting the adoption commit | UNKNOWABLE in advance — a hook may do anything | the window row (§8.4) and `--finish` are the design for it, not a pre-check | — |
| `python3` in the adoptee — `intake-wizard.sh --resume` (the A7 route) needs it; adoption does not | not checked | disclosed in the handoff when absent (WP9d) | `command -v python3` |

### §8.2 — Act 2's order, and why each constraint is where it is

| # | Step | Constraint it satisfies |
|---|---|---|
| 0 | **The re-adoption preflight** (**A1**) — refuse before anything is asked or written | **Before the tier question**, so a second run neither re-interrogates the operator nor destroys what the first produced. **Three arms.** (1) `soif_adoption_adopted` true, **or the committed witness `_soif_adoption_head_copy_adopted`** (which catches a hand-edited manifest that defeats both the flag and the restamp refusal) → refuse, naming `scripts/resume.sh` (the assessment route) and `--re-add`. (2) Stamp absent but a prior `.claude/adoption-archive/` present → refuse and NAME that directory: an interrupted first run, whose recovery is the archive's own restore lines. (3) **`.claude/phase-state.json` present, or `.claude/manifest.json` present with no adoption block, OR at least half of the framework's own install set already present → refuse: this tree LOOKS already framework-managed** (scaffolded by `init.sh`, or an interrupted adoption's state half). The phase-state half is decisive — `init.sh` and the adoption driver are its only writers. The manifest half is strong evidence rather than proof, so the message says what was found and names the explanations instead of asserting one. **THE THIRD SIGNAL WAS ADDED AT WP9b AND IS NOT DECORATION EITHER**: an adoption interrupted after the framework install on a COLLISION-FREE adoptee has no manifest, no phase-state and no archive — the archive directory only materialises when something collides — so arms 1, 2 and 3 were all silent and the operator was re-asked the tier question and every confirmation before the `n_copied -eq 0` tripwire refused. That is this step's own promise going unmet. It is **at least half of the install set**, counted over the same source-filtered entries `adopt_install_framework` would copy, and NOT a single named file: keying it on one file false-refused an adoptee that legitimately vendors a script of its own at a framework path, which adopted cleanly before WP9b. A majority cannot be coincidence; one file can. Without arm 3 a SCAFFOLDED GREENFIELD project passes every check, is archived as though its framework files were the operator's, has its gate-earned state overwritten, is stamped adopted and **committed at exit 0** — shipped v1 refuses it via the `n_copied -eq 0` tripwire that D1 unreaches. **Without this, `adopt_write_file` (`cat >`) overwrites `phase-state.json` and a completed `PROJECT_INTAKE.md` at steps 7's stages, and the second-stamp refusal does not fire until the manifest stage — after both.** **(v2.2, R1 — Karl, 2026-09-17; NOT BUILT, WP9d) THREE MORE REFUSALS, before the arms, each naming what it found and its remedy:** `--root` is not `git rev-parse --show-toplevel` (physical paths — a sub-directory); `.git` is not a directory (a linked worktree or a submodule; `--git-dir` ≠ `--git-common-dir`); `core.hooksPath` is configured and does not resolve to the repository's own hooks directory (`# BL-209-HOOKSPATH-SAME-DIR`'s comparison; *configured* is the exit status, so a set-empty value counts — measured, §13-V31). Arm 1 also gains the WINDOW sub-arm (§8.4). **And (B8, author-proposed) two preconditions moved here from where they fail today:** a git identity (`git var GIT_COMMITTER_IDENT`) and a hash tool |
| 1 | **The tier question** — `adopt_ask_audience`, kept by D9 and re-purposed (§6.5) | **Before step 3**, which keys on its answer, and before step 2, which installs software: a run abandoned at the only question adoption asks has changed neither the repository nor the host. Shipped position, effectively unmoved — `adopt_main` already asks it before any writer (§13-V4) — so this row costs a re-purpose, not a re-order |
| 2 | Tool resolution (`scripts/resolve-tools.sh` against `templates/tool-matrix/`) | Before the secrets check, which needs the scanner it installs (§6.2). The one genuinely new step in the order. **BUILT at WP10a (§6.2a)**; `## BL-251:`'s fast path skips the subprocess when the scanner is already on `PATH` |
| 3 | **NOT BUILT — WP10b.** The secrets check (§6) — at `organizational` every non-clean status stops; at `personal` findings and `scan-failed` warn and carry on, while `tool-unavailable` and (ruled 2026-09-16, §6.1a) `scanned-partial` stop unless an acknowledgement is recorded (§6.1's ladder) | Before any write, so a *stopped* adoption has changed nothing — today's `adopt_stub_secrets_disposition` fires after the reverse intake, which a stop (as opposed to a notice) must not. **It keys on step 1's answer, never on the manifest**, which is not written until step 7 — the tier must be carried in the run, and `ADOPT_DEPLOYMENT` is what carries it (§6.5). **(v2.2) Its INPUT is a scan this step runs itself, over a no-checkout shared clone of the history in `$ADOPT_WORK`, under the framework's rules — §6.2b; the consumed report's secrets section is never the stop's input, and the dispositions and acknowledgements it collects are validated here and written at step 7 (§6.3)** |
| 4 | Test-debt census (`adopt_test_debt_record`) | **Before the install** — shipped and kept; the census reads `git ls-files` and its independence from the framework copies is stated in the code rather than resting on index timing |
| 5 | Collision archive (`adopt_archive_write`), five classes | **Before any writer** — shipped and kept; an archive taken after a writer captures the framework's file under the operator's name. Now also before the D1 installs it newly precedes |
| 6 | Framework install, framework-wins + receipt check (§7.1) | After the archive that makes overwriting honest |
| 7 | State: **the tier-matched `APPROVAL_LOG.md` (A4) FIRST**, then `phase_state` → `intake` (mechanical prefill only) → **`dispositions` (WP10b, §6.3)** → `manifest` + stamp → **`write_set` (WP9d, §8.4)** | `# BF-ADOPT-STATE-ORDER`, carried; §8.4's fail-safe analysis carried. The intake's judgment sections move to Act 3, so Act 2 writes the prefill-confirmed cells and leaves judgment cells blank. **(v2.2) `_adopt_state_order` gains two stages, both inside the rehearsed phase: `dispositions` before `manifest`, so a refused audit append stops the run before the stamp; `write_set` after it, so the persisted list is complete and records itself — the stamp is still the last write BEFORE the write set and the adoption commit still follows immediately** |
| 8 | The adoption commit (`adopt_stage_and_commit`) | Explicit staging, carried. **`## BL-225:`'s staging half sits exactly here** (`# BL-225-STAGE-PREFLIGHT`: ask `git add --dry-run` before staging, stop whole); its before-any-write half sits above step 4 (§8.2a). Both are built. **(v2.2, WP9d) When the commit is refused — by the operator's own hook or a missing identity — the run ends in the ADOPTION WINDOW (§8.4) and says so; `--finish` re-stages exactly the persisted write set and commits, never `git add -A`** |
| 9 | Hooks (`adopt_install_hooks`) | **Last, after the commit** — shipped and kept, with its marker-fenced commit-msg composition. **(v2.2, R1 — Karl, 2026-09-17; NOT BUILT, WP9d) The directory is `git -C root rev-parse --git-path hooks`, resolved absolute — the place git will read from — which step 0 has already verified is the repository's own; the literal `.git/hooks` is retired.** Measured wrong today (§13-V32): under a configured hooksPath the hook lands in `.git/hooks`, the transcript says the gates are live, and `GIT_TRACE` shows git running no hook on the next commit. The archive inventory's `git-hook` class reads from the same resolved directory, so what is archived is what git runs. **The handoff's sentence — *the framework's two message gates are live* — is DERIVED: printed iff, after the install, a RE-READ of that resolved path finds `SOIF_TDD_OPEN` inside an executable `commit-msg` there; otherwise the run prints what it found, says the hook is NOT installed, and ends as a block whose sentence says the commit HAD landed** |

### §8.2a — Steps 4–7 are REHEARSED on a copy before the first real write (`## BL-225:`, built 2026-09-12/13, PR #410)

§8.2's table was written when `## BL-225:`'s staging half had shipped (`# BL-225-STAGE-PREFLIGHT`:
ask `git add --dry-run` before staging, stop whole) and its before-any-write half was open — the
driver could still put the whole write set on disk (79 files on a clean adoptee, §8.7a) and then
discover the adoptee's ignore rules refused one. That half is built, and its mechanism is worth
stating here because it changes what "step 4" means. **`_adopt_write_phase` is the ONLY function
that writes the adoptee's files** — the test-debt census, the collision archive, the framework
install, then the state loop (`_adopt_state_order`: `approval_log` → `phase_state` → `intake` →
`manifest`) — **and it is called twice**: once by `adopt_prewrite_preflight` against a `cp -a`
copy of the whole tree, `.git` included, at `$ADOPT_WORK/rehearsal/tree`; once for real
(`# BL-225-PREWRITE-CALL`, then `# BL-225-WRITE-PHASE-REAL`, both in `adopt_main`). The planned
path set is therefore **what the writers produced on the rehearsal**, never a maintained list — a
writer added to the phase is in the preflight the moment it is in the real run, with no second
edit. `## BL-225:` records that Karl chose the copy over a per-writer no-write flag, and the reason
held: a flag is a second thing each writer can forget, and a writer that ignored it would write
during the "rehearsal".

**Where it sits.** After step 3's surface (today `adopt_stub_secrets_disposition`; after WP10b the
stop) and before the first write. Steps 0–3 run once; steps 4–7 run twice — the first time
discarded, the second time for real; steps 8 and 9 are git work, not file writing, and stay
under the staging preflight.

**The oracle is two questions, and a first cut that asked one over-refused working projects.**
`git add` refuses a *tracked* path only when an ANCESTOR DIRECTORY is ignored — measured on a
tracked path across rule shapes: `.claude/` → refuses; `.claude/*`, `*.json`, an exact path → all
accept — while `git check-ignore --no-index` says IGNORED for all four. So the preflight asks
`check-ignore --no-index` about the parent directory of a tracked path (a top-level tracked file
is simply accepted) and about the path itself when untracked. Anything but exit 0 or 1 from the
oracle **refuses** — `check-ignore` exits 128 on a pathspec beyond a symlink, and reading that as
"not ignored" would be a fail-open guard inside the entry that exists to remove them
(`# BL-225-ORACLE-FAIL-CLOSED`).

**The refusal says NOTHING WAS WRITTEN only when that sentence is DERIVED.** The touched-disk
marker (`# BL-225-TOUCHED-DISK`, a file under `$ADOPT_WORK`, raised before each write site)
records an ATTEMPT, and step 2's resolver raises it before its `eval` on a host missing a tool
even when the recipe leaves nothing — so a refusal was telling operators adoption *"had already
ATTEMPTED writes"* over a provably clean tree. The clear at `# BL-225-REFUSE-DERIVED` is an
**intersection**: no planned path exists on disk AND `# BL-225-TOUCHED-UNBOUNDED` is unraised.
That second flag is evidence-based: `adopt_tree_fingerprint` hashes the adoptee's path list either
side of the resolver's `eval` and raises it only on a difference, or when the tree could not be
read at all — because the planned set bounds the driver's own writers and not an installer
recipe, which may write anything anywhere. Then `# BL-225-PREWRITE-REFUSE` names every refused
path *inside* the refusal (stderr, so a piped log keeps the list) and tells the operator that git
cannot re-include a file under an ignored directory, so `!.claude/manifest.json` beneath a
`.claude/` rule does not help — narrow the rule itself.

**Three things the rehearsal had to be taught, each measured rather than reasoned** (`8356317`):
it honoured `SOIF_ADOPT_HALT_AFTER`, a fault seam for the real run, and so "failed" and refused
every suite that used it (`# BL-225-REHEARSAL-NO-HALT`); it sat *below* the census writer, so it
claimed nothing was written while its own count said one file had been (the census is inside the
phase now); and it raised the global touched marker for the copy (`# BL-225-REHEARSAL-NO-TRACE`
removes the marker again when it was not raised before the rehearsal). **The cost, stated as
one:** four mutation proofs (`S5`, `G4`, `PM1`, `TM1b`) lost their end-to-end observable, because
nothing is written on any failure path now; each is re-proved where it is still observable, and
each masking was measured.

**Two residuals stay on `## BL-225:`, not here.** An adoptee whose `.claude` is a symlink to an
absolute path outside the repository has its state files written *there* while the refusal
correctly reports the repository untouched (pre-existing — it predates the fix); and the unbounded
flag is path-list only, so a recipe that MODIFIES an adoptee file in place rather than creating one
does not raise it (strictly lower reachability than the escape it catches, since the `eval` runs in
`$ADOPT_WORK`, outside the adoptee).

**Cost, stated and bounded (A7; author-proposed, 2026-09-17; WP9d).** The rehearsal copies the
WHOLE tree, `.git` included, and v2.1 stated no bound. Measured on this repository (§13-V36): 965
files, 57 MB, of which `.git/objects` is 30 MB; `cp -a` takes 0.43 s. The bound: the copy EXCLUDES
`.git/objects` and writes `.git/objects/info/alternates` naming the adoptee's object store —
measured here: 27 MB and 0.54 s (a `tar` pipe costs more than `cp -a` at this size and half the
bytes; at any size where the copy matters the object store is most of it) — and git in that copy
lists the same 819 tracked files, resolves HEAD and answers `check-ignore`, which is everything the
rehearsed writers ask of git. The rehearsal never writes objects, so sharing them is safe; a writer
that did would be a defect the tree fingerprint (`# BL-225-TOUCHED-UNBOUNDED`) already catches. The
transcript prints one line — *rehearsal ran in N s over M MB (objects shared, not copied)* — the
Adoption Record keeps it, and above a threshold (`SOIF_ADOPT_REHEARSAL_MAX_MB`, author-proposed
default 2048, the non-object size measured with `du -sk` BEFORE copying) the run REFUSES before
copying, printing the size and both remedies: raise the threshold, or adopt from a fresh clone.
Rejected: a sparse copy of only the paths the writers read — the writers' read set is exactly the
maintained list `## BL-225:` chose the copy in order not to keep.

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
- **(v2.2, B1 — author-proposed) The assessment record's schema is PINNED**, so WP12a's finisher has
  something to validate and WP12a's proofs something to mutate. `.claude/adoption/assessment-record.json`,
  schema v1, written by the MODEL and validated by the shell finisher before anything else runs:

  ```
  { "schemaVersion": 1,
    "assessedAt": "<ISO-8601 UTC>",
    "adoptedAtCommit": "<must equal .adoption.adoptedAtCommit — refused otherwise>",
    "interview": { "users": "...", "availability": "...", "exposure": "...",
                   "scalability": "...", "dataClassification": "<one of ADOPT_DC_TAXONOMY>",
                   "zdrAttested": false, "zdrReason": "",
                   "inProduction": true | false,                      # R2 — required, boolean
                   "operations": { ... },                             # §5.2's S1 block, optional
                   "answers": { "<wizardKey>": "<value>", ... } },    # §5.2's key map
    "evaluators": [ { "name": "...", "ranAt": "...",
                      "findings": [ { "id": "...", "severity": "SEV-1 | SEV-2 | SEV-3 | SEV-4",
                                      "evidence": "...", "summary": "..." } ] } ],
    "fitness": { "verdict": "keep | rebuild",
                 "findings": [ { "id": "...", "requirementRef": "interview.<axis>",
                                 "severity": "...", "evidence": "...", "reasoning": "..." } ] },
    "plan": { "path": "docs/phase-0/adoption-plan.md", "summary": "..." },
    "verdictArtifact": ".claude/adoption/verdict.md" }
  ```

  The finisher REFUSES the record — and writes nothing — when: a fitness finding has no
  `requirementRef`, or one that names no interview axis (D7); `dataClassification` is not in the
  taxonomy `adopt-intake.sh` spells (`ADOPT_DC_TAXONOMY`); `adoptedAtCommit` differs from the
  stamp's; `inProduction` is absent or not a boolean; or the verdict artifact lacks either half —
  the technical account, and a `## Plain English` section carrying the five parts with a
  recommendation that has a stated reason (D8's two-halves check, §5.5).
- **(v2.2) `.adoption.assessment.inProduction` (R2)** — the interview's answer, merged by the
  finisher's LAST stage with the rest of the assessment block; absent means *never asked* (§5.2).
  `scripts/delta.sh`, `scripts/resume.sh` and `scripts/validate.sh` read it through `jq` as state
  (§3.7's rule); nothing else does.
- **(v2.2, A12 — author-proposed) The v1 stamp: migration CLOSED explicitly.** A
  `schemaVersion: 1` stamp — written by the v1 driver between WP4 (2026-08-06) and WP9a
  (2026-09-01) — carries `scenario`, `landedPhase` and three certification arrays. Every shipped
  reader of `.adoption.*` reads three fields only — `adopted` (the accessor), `adoptedAtCommit` (the
  bound) and `adoptedAt` (the gate's OK line); §13-V39 prints the derivation — and all three exist
  in a v1 stamp, so a v1-adopted project is read without error by every arm, and the gate's OK line
  prints for it. What is NOT migrated is its landed rung: D10 does not reach back, a project v1
  placed at `current_phase: 4` stays there with the gate dates v1's certification wrote, and the
  record's `schemaVersion: 1` is the disclosure. No migration is built or designed; `## BL-270:`'s
  `upgrade-project.sh --backfill-only` is the shape one would take, and it would need a ruling,
  because it would MOVE a phase.

### §8.3a — Four decisions this document's author made, and they are NOT Karl's (A1–A4)

**Karl delegated these four on 2026-08-31** — *"Fix the blocker and decide the 3 gaps now"* — after
an architecture review raised them. They are recorded apart from D1–D10 and labelled **A**, not
**D**, because this document's recurring defect has been recording the author's inference as the
owner's ruling: three times (§4.2's blast radius → D9, the *"does not ask"* headline, §4.3's
placement → D10). A delegated decision is still the author's, and mislabelling it would repeat the
pattern with permission. **Any of these four may be overturned without overturning a D.**

| # | Decision | Alternative rejected, and why |
|---|---|---|
| **A1** | **A step-0 re-adoption preflight that refuses before any question or write, on THREE arms** (§8.2 step 0): (1) `soif_adoption_adopted` true — and the **committed witness** (`_soif_adoption_head_copy_adopted`) too, which catches a hand-edited manifest that defeats both the flag and the restamp refusal; (2) an unstamped tree carrying a prior `.claude/adoption-archive/`; (3) **a tree that is already framework-managed but not adopted** — `.claude/phase-state.json` present, or `.claude/manifest.json` present with no adoption block, **or at least half of the framework's own install set already on disk** (added at the build: the first two miss an adoption interrupted after the install on a collision-free adoptee, which has none of the three artefacts; counted over the installer's own source-filtered set, and a majority rather than a named file so an adoptee vendoring one script at a framework path is not false-refused). | *Let the second-stamp refusal handle it* — it fires at the manifest stage, after `adopt_write_file` has `cat >`-overwritten `phase-state.json` and the intake. Under D10 the clobbered `current_phase` is **gate-earned**. Refusing late is not refusing. **Arm 3 is not decoration and was missed in this decision's first draft:** on a SCAFFOLDED GREENFIELD project arms 1 and 2 both stay silent — no `.adoption` to read, and the archive this run creates is not a *prior* one — so adoption archives the scaffold's own framework files as the operator's, overwrites gate-earned state, stamps it adopted (no `.adoption` ⇒ no restamp refusal) and **commits, exit 0**. Shipped v1 refuses that tree via `adopt_install_framework`'s `n_copied -eq 0` tripwire, which **D1 unreaches**. Silent-success corruption, and worse in kind than the noisy case A1 was written for. |
| **A2** | **Act 4 writes its assessment merge LAST**, and §7.2's receipt rule exempts a path whose existing content carries an Act-4 provenance header **whose adoption identity matches this tree's stamp** — and the exemption is from **REFUSAL, not from ARCHIVING**: the current content is re-archived (a second timestamped copy) before it is rewritten. | *Write the merge first* — a crash afterwards leaves documents unwritten while the resume predicate goes false: the largest deliverable silently skipped, the class this repo hunts. *Key the exemption on header PRESENCE* — v1 §8.6's header carries a `source:` commit, so presence alone also matches a `PROJECT_BIBLE.md` the operator copied in from **another** adopted project during the days-wide Act2→Act3 window: silently overwritten with no archive row, the unrecoverable-loss class the receipt rule exists to prevent. Bind it to `adoptedAtCommit`. *Exempt from archiving too* — rejected: re-archiving costs one copy and makes even a matched overwrite recoverable. **Stated failure mode:** a document whose header the operator hand-deleted is treated as theirs and refused — the safe direction. |
| **A3** | **Act 4 does NOT write `PRODUCT_MANIFESTO.md`, and neither does anything else in adoption** — it arrives when the **ordinary Phase 0** produces it, exactly as for a greenfield project (D10). | *Write it in Act 4* — it is in §7.2's required set, and writing it flips OFF `resume.sh`'s §13 kickoff branch (its `[ ! -f "PRODUCT_MANIFESTO.md" ]` predicate, the branch the script's own header calls *"intake done, Phase 0 never started"*; there is no marker on it — `resume.sh` carries only `# BL-046` and `# BL-202-INTAKE-PREDICATE`), so a completed adoption lands in the classic resume prompt and skips the Phase 0 entry D10 promises. *Write it in WP12b after the intake is confirmed* — **rejected, and this decision's first draft said it**: `init.sh` writes no manifesto (*"PROJECT_BIBLE.md / PRODUCT_MANIFESTO.md are created by no script"*), the Phase-0 **agent** authors it for greenfield, and building an adoption-side writer duplicates that path — the two-owners pattern §5.1 itself warns against — while re-creating the same skip one step later for an operator who stops at intake-confirmation. |
| **A4** | **Act 2 writes an `APPROVAL_LOG.md` FIRST in step 7**, rendered from the **tier-matched `init.sh` template** (adoption knows the tier from D9) and carrying **no dated gate-approval row**. | *Document the red window instead* — the gate refuses on the missing file and exits **before parsing the phase at all** (`# BL-166`-era precondition block in `check-phase-gate.sh`), so the resting state cannot run its own gate. *Write it last* — every mid-step-7 death then leaves phase-state-present/log-absent, the hard refusal; a log alone is inert, because with no phase-state the gate exits 0. *Invent an "empty, headed" shape* — rejected as a fourth approval-log spelling: `init.sh` renders tier-differentiated templates and `verify-install.sh` carries a `fix_approval_log` writer, and a fourth would drift from both. The template's pre-condition `__TODAY__` cells do not match the gate's evidence grep, so it stays un-approved, which is correct. |

**A5–A8 were decided at WP9's build, on the same delegation and under the same label.** They are
smaller than A1–A4 and none of them changes a mechanism; each is a consequence of D4/D10 that this
document did not reach, found by reading the code the packages touch rather than by re-reading the
design. **Any of them may be overturned without overturning a D**, and A6 in particular is a
judgment call about an operator-facing surface rather than a derivation.

| # | Decision | Alternative rejected, and why |
|---|---|---|
| **A5** | **`scripts/lib/adopt/adopt-chooser.sh` is RENAMED to `adopt-evidence.sh`.** After D4 and D10 the file's remaining content is §4.2's evidence block and nothing else. | *Keep the name* — a file called `chooser` containing no chooser is the stale-string class this repo has paid for repeatedly (`adopt_stub_hooks`' owner line, `adopt-stubs.sh`'s WP5b section comment, `## BL-215:`'s status line). The rename is cheap and bounded: the name occurs at **three** live sites — the `for _part in …` source loop in `adopt-project.sh` and two in the WP4 suite — and the module-dependency lint keys on directory, not filename. *Fold the evidence functions into `adopt-core.sh` and delete the file* — rejected: `adopt-core.sh` is the shared primitives (I/O, ledger, refusals) and the evidence block is a feature surface; merging them makes the M2 header's per-file account less legible, not more |
| **A6** | **The §4.2 evidence block SURVIVES, with its framing re-worded.** The four evidence functions stay; the two sentences that point at the deleted question go, and the block ends by saying plainly that the project lands at phase 0 whatever the evidence says. | *Delete it with the chooser* — the tempting cut, and wrong twice. §4.3 says in as many words that Scout's ladder, the census and the probes **survive and matter**; and the block is the only place in Act 2 where an operator sees what the survey found about their own project. What is honestly lost is its *purpose*: it fed a decision and now feeds none, so the re-wording must not imply otherwise — a block that still reads as "weigh this before answering" would be inviting weight for a judgment nobody is asked to make. **The known defect is CARRIED, not fixed:** three of the four signals (tags, commit shape, changelog) are derived here from the adoptee's git rather than read from the report, which the file's own header calls "one fact derived in two places is two chances to disagree about it". That duplication is unchanged by WP9 |
| **A7** | **Act 2's reverse intake stops asking JUDGMENT and NON-SKIPPABLE rows, data classification included; it asks only the scan-derived confirmations.** `adopt_judgment_question`, `adopt_ops_addendum` and `adopt_ask_data_classification` go with them; `adopt_persist_phase1_artifacts` is KEPT, uncalled, marked for Act 4, and its process-state *creation* half is split out and still runs in Act 2. | *Leave the judgment questions in Act 2* — §8.2 step 7 is normative ("the intake's judgment sections move to Act 3, so Act 2 writes the prefill-confirmed cells and leaves judgment cells blank"), and leaving them means WP12a's interview asks the same operator the same questions twice. **The classification is the load-bearing half, and its Act-2 mandate has LOST ITS OWN STATED REASON:** `adopt-intake.sh`'s header derives non-skippability from "an S1 adoption lands at 4, i.e. above [the ZDR] threshold on its FIRST commit" — under D10 nothing lands above 0, so the mechanical necessity that justified the guard is gone and §5.2 has already re-anchored it to Act 4's intake write. **The window is real and is stated rather than defended:** between WP9 and WP12a an adoption records no classification at all. It is fail-closed, and the mechanism is stated CORRECTLY here after being stated wrongly at first: the project rests at phase 0, and the ZDR backstop is a hard `[FAIL]` — a real `issues` increment, not a cosmetic `[WARN]` — at `current_phase >= 2` **however that value came to be 2**. The first version of this sentence said *"the only route to 2 crosses the 1→2 gate where that backstop lives"*, and that is **FALSE**: `scripts/process-checklist.sh`'s `_set_current_phase_min` writes `current_phase` at five call sites, an adoptee **receives that script**, and its `--complete-step` / `--verify-init` path reaches `_set_current_phase_min 2` with **no gate consult** — unlike `--start-phase1` (`# BL-114-START1-GATE-CONSULT-BEGIN`) and `--start-phase4` (`# BL-105-START4-GATE-CONSULT-BEGIN`), which do consult. A brownfield adoptee is exactly the population that already has a remote, CI, a lockfile and hooks, so that path is the expected one rather than a contrived one, and adversarial review executed it: `current_phase` 0 → 2 with the classification still absent. **The conclusion survives and is stronger without the false premise**: the gates are cumulative and evidence-keyed, so a rung reached by any writer without the evidence simply fails the gate — which does not depend on an enumeration of who can write the value. **AND THE OPERATIVE GUARD TODAY IS NOT THAT ONE, WHICH IS THE THIRD CORRECTION THIS SENTENCE HAS TAKEN.** On an adopted tree as WP9a leaves it, `check-phase-gate.sh` refuses EARLIER still: its precondition block prints `[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.` and `exit 1`s **six lines before `current_phase` is parsed at all**, and adoption did not write that file until A4. **A4 HAS NOW LANDED (WP9b), so this paragraph's regime is the FORMER one and the ZDR backstop is the operative guard** — the paragraph above describes what executes today. The pre-A4 behaviour is kept because projects adopted before it still rest in it, and because the correction history is the point: this sentence was written as "right now" and became false the moment the package it names shipped. Deleting the log on an adopted project reproduces the old refusal exactly (measured: `[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.`, rc 1). **This suite's own G section documents the early exit and stubs around it**, which is how the claim came to be written beside a fixture that disproved it. **THE SECOND CONJUNCT — that the operator still MEETS the question — WAS ASSERTED BY NOBODY AND WAS FALSE ON ALL THREE ROUTES**, which adversarial review found by executing them: `resume.sh`'s kickoff branch pointed at a `## 13.` section the adoption-rendered intake never wrote; `intake-wizard.sh --resume` raised a **swallowed** `KeyError` (its `load_progress()` subscripts seven keys adoption did not write) and then resumed at Section 14 — **past Section 5, the classification** — printing *"Intake Complete!"* at rc 0; and `reconfigure-project.sh`, **the hatch the ZDR block names in its own FAIL text**, died on a `.claude/orchestrator-source.json` adoption never wrote. All three are FIXED and each is now asserted by execution (§10-WP9's `R1`–`R4`): Act 2 renders a real §13 prompt that names the classification as non-optional, writes the seven keys with `last_section: 0` so `--resume` walks Section 5, and writes the source path. **Deferring a requirement is only honest if the route that re-asks it exists; three of them did not, and "fail-closed" was carrying the whole argument alone.** Two defects in `intake-wizard.sh` itself are OUT of this fix and filed rather than absorbed — a `KeyError` that is swallowed rather than fatal, and a choice prompt that loops forever on EOF. *Delete `adopt_persist_phase1_artifacts` and let WP12a re-extract it* — rejected: it is reuse-by-extraction of `intake-wizard.sh`'s own writer and re-deriving it is how two owners of one merge appear |
| **A8** | **`scripts/check-phase-gate.sh`'s cosmetic `.adoption.scenario` read is retired with the field**, and the `[OK]` line stops naming a scenario. `adopt_stub_certification` is DELETED (WP5 is retired, §5.1) and `adopt_stub_project_docs`' owner string is corrected from *"unassigned — §10 names no owner"* to name D3/WP11+WP12b. `adopt_stub_hooks`' string is NOT touched — §10 routes it to WP7. | *Leave the gate read* — it would print `scenario: unknown` on every adopted project forever, and a gate that reports an unknown where the record is complete teaches operators to ignore it. **§4.2's blast-radius table does not list `check-phase-gate.sh` at all** — the same defect §4.2 itself names ("a blast-radius enumeration is the author's inference about consequences"), recurring inside the section that warns about it; the row is added below. *Leave `adopt_stub_certification`* — announcing a RETIRED package as not-yet-built is worse than silence: it tells an operator to expect something nobody will ever build. *Fix `adopt_stub_hooks` too* — rejected, and not on grounds of effort: `## BL-242:` establishes that the obvious rewrite ("WP7") would propagate a **false §10 attribution**, so that string needs the decision-naming spelling WP7 will give it |

### §8.3b — What the three state writers emit today, by function (2026-09-16; `## BL-253:`, `## BL-268:`)

Read from source so the manifest's shape is a reading, not a memory; two defects were found in
it since 2026-09-01 and both were the same class — an adopted project born with a value a
scaffolded one never carries.

- **`adopt_write_phase_state`** (`# BL-242-PHASE0-LANDING`): `project`, `framework_version:
  "1.0"`, `current_phase: 0`, `track: "full"`, `deployment` (from D9's question), **`poc_mode:
  null`** (`# BL-253-POC-NULL`), `compliance_ready: false`, `review_gate_enforced: true`, and the
  four `gates` at `null`.
- **`adopt_write_intake`**: the rendered `PROJECT_INTAKE.md` with its `## 13.` kickoff section,
  `.claude/intake-progress.json` with the seven keys `intake-wizard.sh` subscripts (A7),
  `.claude/process-state.json` (the file, not the phase-1 merge), the persisted
  `.claude/adoption/scout-report.json`, then `adopt_stub_provenance_headers`.
- **`adopt_write_manifest`**: `host` from the report's `.stack.ciHost` (else `other`); **`mode`
  in the `personal|org` vocabulary, translated from `deployment` exactly as `init.sh` does at its
  own write site** (`# BL-268-MODE-VOCABULARY`: `[ "$mode" = "organizational" ] && mode="org"`);
  `remote_url: ""`; `deployment` in `personal|organizational`; `poc_mode: null`
  (`# BL-253-POC-NULL-MANIFEST`); `enforcement_level` seeded `strict` (`# BL-221-ADOPT-TIER-KEYS`);
  then the evidence hash of the persisted report, refused if empty (`# BF-ADOPT-SHA-REQUIRED`), the
  ONE stamp call (`# BF-ADOPT-STAMP-CALL`) and a `soif_adoption_adopted` read-back that refuses if
  the stamp did not land.

**`poc_mode` (`## BL-253:`, Closed, PR #377).** `ADOPT_POC_MODE` was the string `"production"`
from WP4 until 2026-09-08 — a value `init.sh` never writes (it maps Production to `""` and emits
JSON `null`) and one every reader takes as THE NAME of a POC mode — so `process-checklist.sh
--start-phase4` refused every adoptee and `check-phase-gate.sh`'s organizational Pre-Phase-0
guard, keyed on the key being null, printed zero pre-conditions for an organizational adoptee.
It is `""` now (`# BL-253-POC-MODE`) and both writers emit `null` through `init.sh`'s own
`--argjson` idiom; `tests/test-bl253-adoption-state-parity.sh` pins the two birth paths against
each other (19/0, §13-V24). Adoption still asks **no** POC question — D9 is one question — so an
adopted POC lands as production and must be moved with `upgrade-project.sh`; that stays a residual
on the entry.

**`mode` (`## BL-268:`).** `deployment` and `mode` are two fields with two vocabularies, and the
writer fed `ADOPT_DEPLOYMENT` to both — so every organizational adoptee carried `mode:
"organizational"`, a word no reader of `mode` knows, and `host_verify_protection` — the reader
that runs against an adoptee, and unlike its sibling `host_configure_protection` one that had no
validation of `mode` at all — skipped its org-only assertions in silence and returned success.
Two arms shipped (`eba7291`): the translation above, and all three host drivers now **refuse** a
`mode` outside the vocabulary. Two neighbours are recorded, not designed here: `## BL-270:` — a
project adopted before the fix carries the bad word and, with the drivers now refusing it, is
strictly worse off until the `upgrade-project.sh --backfill-only` migration runs
(`# BL-270-MODE-VOCABULARY-BACKFILL`, on `main` at `0dc57fc` whatever the entry's status line
says); and `## BL-271:` — `upgrade-project.sh --deployment organizational` never writes `.mode` at
all, so a *scaffolded* project upgraded to organizational is verified against the personal bar
for ever. Neither is adoption's defect; both are named because an adoptee receives every script
involved.

### §8.3c — v2.2's author-proposed mechanisms, indexed (M1–M17), and which ruling constrains each

Every mechanism this amendment adds is labelled at its point of use; this index exists so a
reviewer can find them all and see, per row, what is RULED (Karl's, may not be attacked) and what
is this author's (may be). None is an A: A1–A8 were delegated decisions, these are the ordinary
implementation freedom §0.1's third column has always reserved.

| # | Mechanism (author-proposed) | Constrained by | Where |
|---|---|---|---|
| M1 | HOW R1's three conditions are detected: `.git` not a directory; `--git-dir` ≠ `--git-common-dir`; `--show-toplevel` vs `pwd -P`; hooksPath by exit status then physical-directory compare | **R1** (the conditions and the refusal are ruled) | §8.2 row 0, §2.1 |
| M2 | The *live* sentence's derivation: a re-read of `git rev-parse --git-path hooks` finding `SOIF_TDD_OPEN` in an executable `commit-msg`; its failure text; the hooks directory resolved absolute | **R1** (that the sentence is derived is ruled; the predicate is this author's) | §8.2 row 9 |
| M3 | Identity and hash-tool preconditions at step 0; `git var GIT_COMMITTER_IDENT` as the oracle | none | §8.1 |
| M4 | The adoption-window sub-arm of arm 1; `--finish`; the `write_set` stage and `.claude/adoption/write-set.txt`; finishing as an explicit act | none | §8.4 |
| M5 | `adopt_block` beside `adopt_refuse`; the site→label table | `docs/messaging-standard.md` Part 2 (D8 makes it binding) | §8.1 |
| M6 | The rehearsal's shared-objects copy, the measured-and-printed cost line, the `SOIF_ADOPT_REHEARSAL_MAX_MB` threshold | `## BL-225:`'s choice of a copy over a flag (Karl's, recorded there) | §8.2a |
| M7 | The stop's own scan: no-checkout shared clone in `$ADOPT_WORK`, `-c templates/gitleaks/framework.toml`, `--ignore-gitleaks-allow`, env scrub, `scannedBy`/`rulesSource` fields, `--scan-report` as pre-fill only | D2 (what the result DOES is ruled; what the input IS is this author's) | §6.2b |
| M8 | The dispositions join table's schema, the `secrets_disposition` audit row, `--dispositions FILE`, collection at step 3 and the `dispositions` stage at step 7, per-run keying on HEAD + `commitsScanned` | D2 and the 2026-09-16 ruling (recorded, refused-if-unrecordable) | §6.3 |
| M9 | `_adopt_document_set` as data; the `document` and `state` classes; `pending-act-4`; the manifesto's archive-and-REMOVE (`removed-for-phase-0`); row 17 KEPT; the overwrite-inventory invariant | D1, D3 (the classes' existence is ruled; the table is this author's) | §7.2, §7.3, §9.1-I20 |
| M10 | Case-insensitive inventory matching; `@sh`-quoted restore lines; hostile names refused; `adopt_receipt_check` and the `SOIF_ADOPT_INVENTORY_SKIP_CLASS` seam | D1 | §7.1 |
| M11 | WP9c's shipment: `docs/reference/*` copy-when-absent, `.claude/settings.json` COMPOSED (permissions ∪, roster +=), the Stop-only bypass-detector registration until `## BL-277:` closes, the MCP declaration under `init.sh`'s own predicate, the four skills framework-wins | `## BL-277:` (entry-only by Karl's decision — the dependency is recorded, not decided) | §8.7a rows 18–21, §10-WP9c |
| M12 | The assessment record's schema; `adopt_act4_finish`; `_adopt_act4_order`; the finisher invoked from the framework clone via `.claude/orchestrator-source.json`; validation refusals | D6, D7, D8, D10, A2 | §8.3, §10-WP12a/WP12b |
| M13 | `inProduction`'s name and home; the exemption predicate `adopted == true and assessment.inProduction == true`; `active_delta.exemption` and `.adoption_exemptions[]`; the resume order (an open delta first, never a greeting); `validate.sh`'s report widened | **R2** (the exemption, its population, its being recorded and visible are ruled) | §3.6, §8.5, §10-WP12c |
| M14 | The #418 key map as a seventh `_scout_prefill_table` column; `accessibility` → `accessibility_target`; the two-way drift check on the WP2 canary; the D7-axes map | none (contributor issue #418; `## BL-282:` stays Karl's) | §5.2 |
| M15 | The v1 stamp's migration closed by derivation over the readers | D10 (does not reach back) | §8.3 |
| M16 | **A regular file at the hooks path is refused at step 0** (tested on the same two paths as the symlink rule), beside R1's ruled symlink refusal (§2.1, §8.1, §10-WP9d item (iii)). The ruling names symlinks; this is the same refusal for the one remaining shape that reaches `mkdir` and fails after the adoption commit (§13-V48-C). Author-proposed: Karl ruled the symlink case, not this one. | R1 (extended 2026-09-17) | §2.1, §8.1, §10-WP9d |
| M17 | **The CDF install and the Solo hook roster are SEPARABLE, and WP9c registers the roster whatever the clone does** — the position §10-WP9c has held since 2026-09-17 | **none — author-proposed.** Karl's 2026-09-18 ruling covers the INSTALL only; the roster half was never asked | §8.7a row 33, §10-WP9c, §12 item 29 |

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

Two disciplines that must be stated or an implementer will infer the wrong one. The assessment
**record file** is **overwritten** by its own writer on re-entry — only the `.adoption.assessment`
merge refuses-on-exists — because copying the merge's discipline up to the record would re-create
the deadlock one level higher. And the merge plus its `adoption_event` audit row are **two writes**:
a crash between them leaves merged-without-audit-row, which is bookkeeping-only and is named here
rather than defended against.

**A row added 2026-09-16 — refused-before-write (`## BL-225:`, §8.2a).** v1 §8.4's per-surface
analysis assumed the writes had started; there is now a state before that one. When the rehearsal
finds a planned path the adoptee's ignore rules refuse, or does not complete at all, adoption
refuses with **no file written and no state changed**: phase-state absent, manifest absent, no
archive directory, the tree's path list identical either side — and the refusal says *NOTHING WAS
WRITTEN* only when `# BL-225-REFUSE-DERIVED`'s intersection holds, and otherwise says that
adoption attempted writes (the `# BL-225-REFUSE-HONEST` class). It is the safest row in the
table, and it is safe by construction rather than by write order; `tests/test-bl225-prewrite-preflight.sh`
(50/0, §13-V24) is the check. **What it does not cover, so nobody reads it as more than it is:** a
crash *inside* the real `_adopt_write_phase` — between the rehearsal and the commit — still leaves
files on disk exactly as v1 §8.4's rows describe, with the archive's restore lines as the manual
recovery and A1's three arms refusing the re-run (§12 item 4a); and step 2's resolver runs *before*
the rehearsal, so a host that said yes to an install has changed even when the tree has not.

**A second row added 2026-09-17 — the ADOPTION WINDOW: stamped in the working copy, not adopted at
HEAD (A3; measured, §13-V33).** How it arises: the operator's own pre-commit or commit-msg hook
rejects the adoption commit, or git cannot resolve an identity — after every write and after the
stamp (§8.2 row 8). Measured at `579b0b0`: rc 1; `[BLOCKED] the adoption commit did not succeed —
your own hooks or git identity may have refused it`; the working-copy manifest says
`adopted: true`; HEAD has not moved; `git show HEAD:.claude/manifest.json` finds nothing; **83
entries are left STAGED in the index**; the commit-msg hook is not installed — and the stamp's own
bound predicate, `soif_adoption_pre_adoption_commit`, reports the state EXEMPT, which is correct:
it is, by that function's definition, the adoption window. The re-run then refuses at arm 1 — *this
project has already been adopted — the manifest records it* — and advises `scripts/resume.sh` and
`--re-add`, neither of which finishes the adoption; `resume.sh` offers the Phase 0 kickoff over an
UNCOMMITTED tree. Why the state is SAFE: phase-state exists, so the gate is live; nothing landed in
history; the operator's hook did its job. Why it is NOT ACCEPTABLE: the shipped text's *run adoption
again* sentences all precede the stamp except one — `# BL-242-RESOLVER-NO-EXEC`'s, which a completing
run then stamps past (§12 item 22, WP10b's to resolve) — and the window state itself has NO sentence
at all: arm 1 tells it to resume. *(v2.2's first cut counted three post-stamp sentences; arm 2's
not-yet-installed branch is pre-stamp advice and the tripwire's message says resuming is not built —
neither is a re-run instruction the window meets, and WP11 deletes the tripwire.)* **The design (M4,
WP9d):**
(i) arm 1 gains a sub-arm that DISCRIMINATES the window — working-copy witness true AND committed
witness false, the two calls `_adopt_preflight_adopted` already makes, read in conjunction — with
its own message: *the adoption was written but its commit did not land; fix what refused it, then
run `--finish`*; (ii) the `write_set` stage persists `adopt_written_paths` to
`.claude/adoption/write-set.txt` as the LAST write inside the rehearsed phase, recording itself;
(iii) `--finish` re-derives the window and refuses on any other state, reads the write set, runs
the staging preflight over it, `git add`s exactly those paths, commits with the same subject,
installs the hooks and prints the handoff — and REFUSES when the write set is missing or names a
path that is not on disk, never falling back to `git add -A`; (iv) a bare re-run on the window
state does NOT silently finish: finishing is an explicit act, because the operator's hook refused
something and the operator should say the refusal is resolved. The invariant is §9.1-I12.

### §8.5 — `scripts/resume.sh`'s adoption branch

`resume.sh` is the shipped, state-aware first-message generator — four branches today, zero
adoption awareness (§13-V8). WP12a adds the fifth: **predicate** `.adoption.adopted == true` and no
`.adoption.assessment` in `.claude/manifest.json` (via `jq`, exactly the shipped
`# DELTA-RESUME-PHASE4` pattern of reading state) → emit the Act 3 prompt. **(v2.2)** WP12a renders
that prompt; it names the finisher command — `bash "$(jq -r .source_dir
.claude/orchestrator-source.json)/scripts/adopt-project.sh --act4 --root .`, run from the framework
clone row 23 already records — the record's schema (§8.3) and its home,
`.claude/adoption/assessment-record.json`, beside the persisted `scout-report.json`. The
*assessment brief* v2.0–v2.1 had Act 2 write is DROPPED (A6, §3.7).
**Branch order matters and is a designed fact, not an accident**: the adoption branch is checked
**before** the intake branch, because Act 2 leaves a partially-filled `PROJECT_INTAKE.md` at phase
0 — exactly the state the intake branch's blank-cell predicate (`# BL-202-INTAKE-PREDICATE`)
matches — and an adopted-unassessed project must be offered the assessment, not the greenfield
intake interview. After Act 4 writes the assessment block, the predicate goes false and `resume.sh`
falls through — and **A3 names the branch it falls through to, because the shipped branch math
decides it and the first draft of this sentence did not say which.** Act 4 leaves
`PRODUCT_MANIFESTO.md` **unwritten** (A3), so `resume.sh`'s kickoff branch
stays false, so the operator is routed into a **Phase 0 entry** — which is what D10's *"starts
from the beginning … Phase 0 intake first"* means in practice.

**WHICH of the two Phase-0 entries is a fact about the tree, not a choice, and the design asserts
the disjunction rather than picking one.** `resume.sh` checks the intake branch
(`# BL-202-INTAKE-PREDICATE`, fires above **20** blank cells) BEFORE the kickoff branch. The
shipped intake template carries **87** blankable cells and Act 4 leaves every judgment cell blank
per `# BL-204-PREFILL-READ` — so the realistic first resume takes the **intake** branch, and the
kickoff branch fires on the *second* resume, once the intake is finished. **Both are Phase-0
entries, so D10 holds either way.** *(An earlier draft named the kickoff branch as the route and
had WP12a pin it by name. That proof would go RED against a correct implementation on any realistic
fixture — or force a ≤20-blank fixture no real adoption produces, which is the numeric coupling
this paragraph was trying to avoid, relocated into the fixture.)* **WP12a therefore asserts that an
assessed fixture lands in one of the two Phase-0 entries and NEVER in the classic prompt.**

**MEASURED AT WP9's BUILD, and the paragraph above is right in its conclusion and wrong in its
mechanism.** A shipped adoption was run and `resume.sh` executed inside the result:

```
blank-cell count : 0        <- not 87
manifesto present: no
resume.sh        -> "Read PROJECT_INTAKE.md — Section 13 is your initialization prompt — and
                     begin Phase 0 from it."
```

The **87** is a property of `templates/project-intake.md`, which adoption does not render.
`adopt_render_intake_doc` writes its own bullet-list document, and the predicate counts empty
**table cells** (`grep -cE '\| *\|$'`), so an adopted intake scores **0** however many judgment
cells it leaves blank — the intake branch cannot fire on an adoptee at all, and the **kickoff
branch is the route, on the FIRST resume**. The disjunction WP12a asserts is still the right
assertion (it is true, and it does not couple to a constant in another script); what changes is
that a fixture built to exercise the *intake* side of it would be building a state adoption cannot
produce.

**Two consequences. The first was handed to WP12a here and WP9a BUILT IT INSTEAD** — this
paragraph assigned delivered work to a future package for three rounds, which is the mirror image
of the defect the rest of this section records. As written it said: the kickoff branch extracts
§13's fenced prompt with `awk '/^## 13\./…'`, the adoption-rendered document has no `## 13.`
heading, so `bl202_s13` is empty and the operator gets the **generic fallback** — which then tells
them to read a "Section 13" the file does not label. **That is fixed.**
`adopt_render_section_13` renders the heading the extractor looks for and a real prompt beneath it,
and §10-WP9's `R1` asserts it by running `resume.sh` on an adopted fixture: the prompt appears, the
fallback does not, and exactly one heading and one title exist. **The reason it moved into WP9a
rather than waiting is A7**: WP9a is what deferred the data classification, so WP9a owed the route
that re-asks it, and that prompt is where the classification is named as non-optional.

Second, this is the state D10 promises *today*, before WP12a: an adopted project's first resume is
already a Phase-0 entry, which is why WP9 ships an honest handoff pointing at `resume.sh` rather
than pulling the fifth branch forward.

**The delta branch under R2 (M13, WP12c; the order is author-proposed).** `# DELTA-RESUME-PHASE4`
keys on `PHASE = 4` and sits AFTER the BL-202 branches, so on an adopted project at phase 0 it is
never reached. Under the exemption a second entry is added BEFORE the BL-202 branches: when
`.claude/manifest.json` says `.adoption.adopted == true` and `.adoption.assessment.inProduction ==
true`, AND the delta record — read through the one declared seam, `process-checklist.sh
--delta-state-read`, exactly as the shipped block does — holds an OPEN `active_delta`, the *resume
THAT piece of work* sub-case fires first: a hotfix in progress outranks a Phase 0 kickoff. With NO
open delta the entry is not taken at all — the greeting (*this product has shipped*) never fires
below phase 4, and the project is routed to its Phase 0 entry as D10 says. Proposed marker
DELTA-RESUME-EXEMPTION (written bare here — it does not exist yet; the delta track's markers are not
`BL-` prefixed by that design's own rule). The fifth branch — adopted, unassessed — is checked
before both, because an unassessed project has no `inProduction` to read.

### §8.6 — The Adoption Record records an assessment and a plan (WP7, re-cut in content)

WP7 is **unchanged in need and changed in content** (`## BL-242:`'s words): the Adoption Record
now records the assessment and the plan, not a scenario and a rung. Its structural contract —
v1 §8.8's eight clauses making the record unparseable as a gate approval, with the record lint
pinning them — carries over **verbatim and unweakened**; nothing in the new content touches the
eight readers those clauses defeat. Added content rows: the assessment's findings and their evidence,
the verdict (including rebuild, when returned), the interview's recorded answers by reference, the
secrets dispositions by fingerprint (§6.3), the archived-path list by class (§7.3), and the plan's
location — **and, since 2026-09-17: the in-production declaration and every exemption used under
it (delta id, date, `current_phase` at the time — author-proposed WP7 content; R2 names the delta record and the process state, not this one — the review's R-15); the
acknowledgements by kind (§6.3); the hooks placement — the resolved directory the hook was written
to and whether the *live* sentence was earned (R1); and the rehearsal's measured time and size
(§8.2a)**. The audit-row design (one `adoption_event` type, `details.event` discriminator, five
surfaces per new enum member) carries from v1 §8.9 unchanged, and Act 4's two writers (§8.3) join
its emitter list.

### §8.7 — What else does adoption skip that `init.sh` does? — the named open question

Tool resolution was found missing **by one grep** (§13-V3), which forces the wider, unenumerated
question `## BL-242:` records: **what else does adoption skip that `init.sh` does?** This design
refuses to answer it with a hand list — the hand list is how v1's status row went wrong three
times. Verified instances beyond tool resolution (§13-V10): the **detection baseline** —
`init.sh` writes `git rev-parse HEAD` to `.claude/last-checked-commit.txt` at **2** sites; the
adoption driver and its lib contain **0** executable mentions (one COMMENT, in `adopt-state.sh`'s
`.gitignore` paragraph, since 2026-08-31 — `7e3be18`, on `main` 2026-09-01 via PR #370; row 22 stays UNOWNED), so an adopted project's out-of-band-commit
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

#### §8.7a — THE TABLE, delivered (WP9). Half of it was MEASURED, and that half is why it is trusted

**The adoption side is derived BY EXECUTION, not by grep**, because grep is what under-read this
surface twice before (`## BL-181:`'s exempt-row audit, and `## BL-242:`'s own `adopt_stub_*` count).
A shipped adoption was run against a hermetic adoptee and the tree diffed before and after:

```
adopt rc=0                                        # 2026-09-16, tree 01b66e3 — §13-V27
total new files: 79   |  under scripts/: 70  |  under .claude/adoption-archive/: 0
```

The **nine** non-`scripts/` paths a completed adoption writes, in full — this is the whole of it,
and anything not on this list is skipped:

```
.claude/adoption/scout-report.json   .claude/intake-progress.json   .claude/manifest.json
.claude/orchestrator-source.json     .claude/phase-state.json       .claude/process-state.json
.claude/test-debt.json               APPROVAL_LOG.md                PROJECT_INTAKE.md
```

*(**This block has now been wrong three times: 75 and seven, then 76 and eight, now 77 and nine.**
The eighth path was `.claude/orchestrator-source.json`; the ninth is `APPROVAL_LOG.md`, added by
**WP9b** — and WP9b corrected the identical list in `docs/adoption.md` while leaving THIS copy
stale, in the paragraph carrying the instruction that would have prevented it. Two documents in one
commit disagreeing about one measurement. A measurement is only true of the tree it was taken on.
**Re-run it after any package that adds a writer — and re-run BOTH copies, or delete one.**)*

*(**And a fourth time, differently: 77 became 79 with the nine paths UNCHANGED**, because the
`scripts/` half is `init.sh`'s copy list and `## BL-254:` added two files to it on 2026-09-08
(PR #378) — no adoption package touched anything. Re-measured by execution on 2026-09-16, §13-V27,
whose `scripts/` half is byte-identical to `soif_parse_shipped_scripts`' 70. So the trigger is wider
than the sentence above says: **re-run it after any change to `init.sh`'s copy list, not only after
a new adoption writer.** The other two carriers — `docs/adoption.md` and `## BL-242:` — said
77 and 68 at `01b66e3`; PR #415 corrected both one merge later; §13-U(v2.1).)*

(plus `.git/hooks/commit-msg`, which a tree diff cannot see because `.git` is pruned, and a
`.claude/adoption-archive/` tree whose size depends entirely on what the adoptee already had —
zero on the fixture above, because it carried no AI-layer surfaces.)

**The `init.sh` side is derived from source and is acknowledged partial** — that asymmetry is
stated rather than hidden, because one half of this table is a measurement and the other half is a
reading. The recipe, widened from §8.7's starting one because it missed every `cp` and every
heredoc:

```
grep -oE 'cp "\$SCRIPT_DIR/[^"]+" +[^ ]+'        init.sh | sed 's/.*" *//'
grep -oE 'cat > [^ ]+'                           init.sh | sed 's/cat > //'
grep -oE 'cp "\$SCRIPT_DIR/[^"]*"\*[^ ]* +[^ ]+' init.sh | sed 's/.*[[:space:]]//'
```
plus the writers whose target is inside a function body (`generate_claude_md`,
`generate_approval_log`, `generate_gitignore`, `generate_ci`, `generate_release`,
`install_precommit_hook`, `soif_render_project_intake`) and the two
`.claude/last-checked-commit.txt` sites.

| # | `init.sh` effect | Placement, and the reason |
|---|---|---|
| 1 | `scripts/**` (68 files measured 2026-09-01; **70 measured 2026-09-16**, §13-V27 — `scripts/check-changelog.sh` and `scripts/check-session-state.sh`, added to `init.sh`'s copy list by `## BL-254:` on 2026-09-08) | **Act 2** — `adopt_install_framework`, from `init.sh`'s own copy list via `soif_parse_shipped_scripts`. The one surface with no drift risk by construction |
| 2 | `.claude/phase-state.json` | **Act 2** — `current_phase: 0` (D10) |
| 3 | `PROJECT_INTAKE.md` + `.claude/intake-progress.json` | **Act 2**, prefill-confirmed cells only; judgment cells blank (§8.2 step 7, **A7**). **A pre-existing copy of EITHER is OVERWRITTEN with no archive row, no directory and no sentence — measured 2026-09-17, §13-V34; WP11's `document` and `state` classes close it (§7.2)** |
| 4 | `.claude/manifest.json` + the stamp | **Act 2** |
| 5 | `.claude/process-state.json` | **Act 2** — `adopt_write_process_state`, split out of `adopt_persist_phase1_artifacts` at WP9a. Under **A7** the `.phase1_artifacts` merge moves to Act 4; the *file creation* stays in Act 2, or the adoptee loses a file `init.sh` guarantees. *(An earlier review round recorded this row as "nobody persists"; it was written then and is written now, and that correction is the reason this half of the table is measured.)* |
| 6 | `install_tdd_commit_msg_hook` | **Act 2** — `adopt_install_hooks`, last, after the commit — **to a literal `.git/hooks` today; R1 (Karl, 2026-09-17; WP9d) makes it `git rev-parse --git-path hooks`, refuses at step 0 under a redirecting hooksPath, and — R1 as extended the same day — refuses when either that path or this repository's own hooks path is a SYMLINK or a non-directory (§13-V48, §13-V49). Measured wrong today, §13-V32** |
| 7 | `templates/tool-matrix/*.json` | **PARTIAL — and the draft of this amendment said "WP10a — BUILT", which the tree refuted.** Act 2's *consumption* is built (WP10a reads the matrix from the FRAMEWORK root, §6.2a); the *copy* `init.sh` makes into the project is not — §13-V27's write set carries no `templates/` at all, while the adoptee receives `scripts/resolve-tools.sh` in the install set and its own `check-phase-gate.sh` names `$PROJECT_ROOT/templates/tool-matrix` in its tools-needed block. **Why nobody has tripped over it:** that block is keyed on `.claude/tool-preferences.json`, row 32's file, which adoption also never writes — so on an adoptee it never runs (measured: the resting-state gate exits 0 with no matrix line, §13-V27). Two unowned gaps masking each other; whether the adoptee must receive the matrix is undispositioned |
| 8 | the `resolve-tools.sh` invocation (four command substitutions in `init.sh` — §13-V3; this row said three) | **WP10a — BUILT** (§8.2 step 2, `# BL-242-RESOLVER-CALL`; §6.2a) |
| 9 | `templates/generated/*.tmpl` (incl. `skills/`) | **WP11/WP12b** — the D3 document writers render from these |
| 10 | `CLAUDE.md` | **WP11 (archive) + WP12b (write)** — D3 |
| 11 | `FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md` | **WP11 + WP12b** — D3's reach, ruled 2026-08-31 |
| 12 | `APPROVAL_LOG.md` (`generate_approval_log`) | **WP9 (A4)** — written FIRST in step 7, from the tier-matched template |
| 13 | `.github/workflows/*` (`generate_ci`, `generate_release`) | **WP7** — the CI carve-out (§7.4) |
| 14 | `install_precommit_hook` (the fallback hook) | **WP7**, last — Karl's decision; installing it before the artifacts it reads exist refuses every commit |
| 15 | `PRODUCT_MANIFESTO.md` / `PROJECT_BIBLE.md` | **NOBODY, in either path** — `init.sh` writes no manifesto either; the Phase-0 **agent** authors both (**A3**). Covered by construction, not by omission |
| 16 | `.gitignore` (`generate_gitignore`) | **PARTIAL** — `## BL-225:`'s staging preflight reads the adoptee's, and since its second half the pre-write rehearsal reads it too (§8.2a); whether adoption should *amend* theirs is still undispositioned |
| 17 | `CHANGELOG.md` | **KEPT — ruled by THIS AUTHOR on 2026-09-17, not by Karl (§7.2)**: D3's reach ruling names `FEATURES`/`BUGS`/`RELEASE_NOTES` and stops there; `init.sh` writes a fourth; reading D3 as reaching it would be an inference recorded as a ruling. Never archived, never written; `check-changelog.sh` accepts the operator's own. *(Was UNSPECIFIED until v2.2.)* |
| 18 | `docs/reference/*` (8 verbatim docs — §13-V38 names them) | **WP9c (v2.2)** — copied when absent inside `_adopt_write_phase`'s new `reference` stage; a pre-existing file at one of the eight paths is archived under `document` and replaced (framework-wins, D1's logic — these are the framework's own documents verbatim). *(Was UNOWNED — and load-bearing: `messaging-standard.md` is the document **D8 binds**, and `builders-guide.md` is what `resume.sh`'s §13 prompt hands the agent.)* The prompt's *"WHAT YOU DO NOT HAVE"* paragraph becomes DERIVED from what this stage wrote |
| 19 | `.claude/settings.json` — permissions + hook roster | **WP9c (v2.2)** — COMPOSED, not overwritten: the permissions block's `allow`/`deny` unioned in, the eleven-script roster `init.sh` registers (§13-V38 derives it) added with `init.sh`'s own idempotent `jq` idiom, an existing file archived first (`ai-settings`, disposition `composed`). **Two dependencies, recorded not decided:** `init.sh` registers the roster only inside its `framework_valid` branch — when the CDF clone succeeded — so greenfield parity is conditional (§13-V38 prints the nesting; row 33); and `scripts/hooks/bypass-detector.sh`'s PostToolUse registration is the day-one blocker `## BL-277:` measures — WP9c registers its Stop arm now and its PostToolUse arm ONLY when that entry closes, whichever option Karl picks (§12 item 26). *(Was UNOWNED.)* |
| 20 | `.claude/settings.local.json` — `mcpServers.qdrant` (`# BL-233-WPB-MANIFEST-DECL`) | **WP9c (v2.2)** — under `init.sh`'s OWN predicate, extracted (a Qdrant container running AND `uvx` present): write the same `settings.local.json` and set `.mcp.qdrant_required = true` in the manifest, which is the tracked declaration `## BL-233:`'s gate reads; otherwise write nothing and say in the handoff that the accumulation check derives NOT REQUIRED. *(Was UNOWNED — the gate switched off silently.)* |
| 21 | `.claude/skills/<name>/SKILL.md` (vendored skills) | **WP9c (v2.2)** — the four `init.sh` ships (§13-V38 derives the loop), framework-wins on a same-name collision through the existing `skill` archive class. *(Was UNOWNED.)* |
| 22 | `.claude/last-checked-commit.txt` (2 sites) | **UNOWNED** — §8.7 named it; still nobody's |
| 23 | `.claude/orchestrator-source.json` | **Act 2 (WP9a)** — `adopt_write_orchestrator_source`. **The one row in the unowned set that WP9a closed, and the boundary is stated so it does not read as arbitrary: A7's own safety argument depends on it.** Three shipped scripts an adoptee receives read it (`reconfigure-project.sh`, `verify-install.sh`, `check-versions.sh`), and the Phase 1→2 ZDR block names the first of them as its escape hatch **in its own FAIL text** — which died on the missing file. Closing a block while leaving the hatch it advertises unreachable is a pattern this repository has paid for |
| 22a | `APPROVAL_LOG.md` | **Act 2 (WP9b)** — `adopt_write_approval_log`, rendered from the tier-matched `init.sh` template (A4). **It is also the archive's FIFTH class, `approval-log`, and the only entry adoption REPLACES** (`disposition: "replaced"`; every other entry is `kept` or `composed`). The class is deliberately not `document` — WP11 owns that vocabulary (D3) and folding this into it would poach the package's notice text. §7.3 carries the class list and names this one |
| 23a | `.claude/build-progress.json`, `.claude/tool-usage.json` | **UNOWNED** — they travelled with row 23 until WP9a split it; nothing depends on them the way the escape hatch depended on the source path, so they stay recorded |
| 24 | `docs/INDEX.md`, `docs/IDENTIFIERS.md`, `docs/archive/README.md`, `docs/test-results/go-live-checklist.md` | **UNOWNED** |
| 25 | `evaluation-prompts/Projects/**` | **UNOWNED** |
| 26 | `templates/intake-suggestions/*.json` | **UNOWNED** — and the adoptee *does* receive `intake-wizard.sh`, which reads them |
| 27 | `.semgrep/soif-dom-sinks.yml`, `tests/uat/templates/*` | **UNOWNED** |
| 28 | `install-filesystem-gates.sh --install` | **UNOWNED** |
| 29 | `soif_currency_record_render_base` A1/A2 rows | **UNOWNED** |
| 30 | remote creation / protection, `local_only_acknowledged` | **UNOWNED** — the ack has no post-init writer anywhere |
| 31 | `git init`, and BL-030's organizational⇒strict forcing | **COVERED** — the adoptee is already a repository; `enforcement_level` seeds `strict` in `adopt_write_manifest` |
| 32 | `.claude/tool-preferences.json` (`init.sh`, 9 mentions) | **UNOWNED — found by dogfood, not by this table** (`## BL-284:`, row added 2026-09-16): adoption writes it nowhere (`grep -rc tool-preferences scripts/lib/adopt/ scripts/adopt-project.sh` → 0 in every file), so `verify-install.sh`'s `has_context()` was unsatisfiable on every adoptee and its auto-fixer could never run; the fix reads the context from the state files adoption does write (`# BL-284-CONTEXT-STATE`). Its absence is also what keeps row 7's missing matrix unreachable. The `init.sh` half of this table is *acknowledged partial*, and this row is the first measured instance of how partial |
| 33 | The CDF install — `~/.claude-dev-framework/scripts/init.sh --profile … --prepopulate … --skip-plugin-check`, run by `init.sh` inside its `framework_valid` branch | **UNOWNED — found 2026-09-17 (§13-V38).** Greenfield's `.claude/manifest.json` BASE shape, every CDF rule and hook, and the condition under which row 19's roster is even written all come from it, and adoption never runs it (adoption writes its manifest from scratch, §8.3b). Whether an adoptee should receive the CDF — a network clone into `$HOME`, non-fatal in `init.sh` when it fails — **was a question for Karl and is RULED 2026-09-18 — an adoptee receives it, on the same terms a scaffolded project does. Still UNOWNED by any package: the HOW is undesigned** (§12 item 29); the second measured instance of how partial this half is |

**Re-measured 2026-09-17: rows 18–21 are OWNED by WP9c, row 17 is KEPT by rule, row 33 is added
UNOWNED — read the rows for the rest; the sentence that follows is v2.1's measurement, kept as its
record.** **FOURTEEN rows are UNOWNED (18–22, 23a, 24–30, 32), one is UNSPECIFIED (17) and TWO are PARTIAL (7, 16),
across **34** rows.** *(Row 32 was added and row 7 re-classified from "WP10" to PARTIAL on 2026-09-16;
thirteen, one and 33 were right for their date.)* *(The denominator was 32 until WP9b added row **22a** — `APPROVAL_LOG.md` — so this number was falsified by the very commit that wrote the row, inside the paragraph telling you to count the rows rather than trust it. The UNOWNED half did not move; only the denominator did. This also said twelve, and twelve was wrong in a way worth keeping: WP9a closed row
23 and the split created row **23a**, itself unowned, so the count never moved. §12-3, §0.3 and
`docs/INDEX.md` all said thirteen while this line said twelve — the document contradicted itself
for one round. **The count is a MEASUREMENT of the table: read the rows, do not trust this
number** — which is exactly what nobody did.)* That is the honest denominator §8.7 asked for, and it is larger than this
document's own §10 implies: the packages ahead of WP9 close rows 8–14 — row 8 closed at WP10a,
row 7 only half — and **almost none of 16–32**. Row 18 is the sharpest — it
makes D8 bind `docs/reference/messaging-standard.md` inside a project that never receives it — and
rows 19–21 mean an adopted project's *sessions* are a materially weaker place than a scaffolded
project's. **None of them is WP9's to fix**, and filing them is the point: the set is carried on
`## BL-242:` as the init-parity residual, and this table is what makes "adoption is finished" a
statement with a denominator.

---

## §9 — What does not change

| Kept | Anchor | Note |
|---|---|---|
| Every phase-gate predicate | `scripts/check-phase-gate.sh` | v2 adds no gate arms beyond WP3's shipped ones, and under D10 it needs none — **but not for the reason this cell gave until 2026-09-01.** It said *"nothing writes `current_phase` outside Act 2's phase-0 landing"*, which is false: `process-checklist.sh`'s `_set_current_phase_min` writes it at five call sites and ships to adoptees. The real reason is better and does not depend on enumerating writers: the gates are **cumulative and evidence-keyed**, so a project whose rung was advanced without the evidence fails the gate on the evidence, whoever moved it. **And R2 (2026-09-17) touches no gate**: the delta track's era guard (`# DELTA-OPEN-ERA-GUARD`), the resume script's delta branch (`# DELTA-RESUME-PHASE4`) and `validate.sh`'s era report (`# DELTA-ERA-REPORT-ONLY`) gain a second conjunct in WP12c — §13-V40 prints that those three are the era invariant's only readers — and `scripts/check-phase-gate.sh` reads none of it; §9.1-I18 pins it |
| Scout, **almost** whole | `scripts/scout.sh`, `scripts/lib/scout/` | Act 1 is the shipped Scout. Candidate future section (`chooserEvidence`) dies with the chooser. **AMENDED AT WP9a, and the amendment is here rather than only in the changelog because that is where a reader of this row looks:** `scout-report.sh` emitted, in the report and the rendered markdown, the note *"maximum satisfied rung; the interview may only lower this"* — the FLOOR RULE, whose interview D4 deleted and whose placement D10 deleted. Shipped operator-facing output making a claim about machinery that does not exist. Re-worded to *"…evidence for the Phase 0 intake, never a placement"* at four sites plus the WP1 suite's string-equality pin. Nothing else in Scout changes, and nothing outside Scout reads `phaseMap.suggestedPhase` any more, which is what made the note purely descriptive. **AMENDED AGAIN at `## BL-288:` (2026-09-12):** `secrets.status` gained `scanned-partial`, `secrets.scope` gained `shallow-history`, and `schemaVersion` is 2 — a report consumer that switches on the old three words must be widened, and adoption's two were (§6.1a). Scout is *almost* whole by a wider margin than this row said on 2026-09-01 |
| The in-core enabling arms | `scripts/lib/adoption-stamp.sh`, `# BF-ADOPT-FLAG-READ`, the TDD adoption-window arm | The `adopted` flag's meaning and every reader; the stamp's writer changes shape (§8.3), not home or discipline |
| The test-debt ledger and ratchet | `scripts/lib/adopt/adopt-test-debt.sh` (WP5b, shipped) | Untouched; still kind (c)'s forward equivalent |
| The collision archive mechanism | `scripts/lib/adopt/adopt-archive.sh` (WP6, shipped) | Gains three classes (§7.3) — `script` and `document` at WP11, and `approval-log` at WP9b, already shipped; layout, MANIFEST, `--re-add`, pre-staging scan unchanged |
| The redaction projection | v1 §6.2's field allowlist, shipped in Scout's secrets section | Every §6 artifact inherits it; no artifact ever carries a value |
| The state order and staging discipline | `# BF-ADOPT-STATE-ORDER`; explicit-path staging | Carried verbatim |
| The module contract and its lint | `docs/module-contract.md` M1–M5; `scripts/lint-module-dependencies.sh`, `# BL-215-CORE-GLOB-SYNC` | §3.7 keeps both new contact points on the right side of M3 |
| The CI carve-out | v1 §7.4 | Carried unchanged (§7.4) |
| The Adoption Record's structural contract | v1 §8.8's eight clauses | Carried unweakened; content re-cut (§8.6) |
| The house rules | No merge on red; never `--no-verify`; TDD with mutation proofs; hermetic tests; both-list registration; marker citations | Including for this build |

### §9.1 — Invariants and their checks (added 2026-09-17)

Each row names the property, WHERE it is enforced (a marker or a function — never a line), the
CHECK that would go red if it were broken, and whether that check exists on `main` at `579b0b0`.
"Proposed" in the last column means the invariant is this amendment's and its check is a §10 proof
not yet written; "none" means a shipped property with no check, which is a gap the row files
rather than hides. Derive the built/unbuilt column from the markers: §13-V45 greps every marker
named here and prints which exist.

| # | Invariant | Enforced at | Check | Status at `579b0b0` |
|---|---|---|---|---|
| I1 | Every adopted project lands at phase 0; no act writes `current_phase` (D10) | `# BL-242-PHASE0-LANDING`; the finisher's stages contain no phase write | wp9 suite's landing proof; WP12a's *no phase write* proof | built / proposed |
| I2 | The stamp is written once and never re-stamped | `# BF-ADOPT-RESTAMP-REFUSE`, `# BF-ADOPT-STAMP-CALL` (one call site) | WP3 suites | built |
| I3 | Nothing is staged that the run did not write; never `git add -A` | `# BF-ADOPT-STAGE-EXPLICIT` over `adopt_written_paths`; `--finish` reads the persisted write set only | WP4/BL-225 suites; WP9d's `--finish` proof (an unrelated dirty file stays unstaged) | built / proposed |
| I4 | One writer of the adoptee's files, rehearsed on a copy before the first real write | `# BL-225-PREWRITE-CALL`, `# BL-225-WRITE-PHASE-REAL` — `_adopt_write_phase` has exactly two callers | BL-225 suite (T9/T10) | built |
| I5 | Every write site raises the touched-disk marker first | `# BL-225-TOUCHED-DISK` at every site | BL-225 T9 derives both sets and requires them equal | built |
| I6 | The archive precedes every framework writer | order inside `_adopt_write_phase` | WP6 suite | built |
| I7 | Nothing enters the commit until a scanner has looked at it | `# BF-ADOPT-ARCHIVE-SCAN`; the withhold chain | WP6 suite | built |
| I8 | No artifact ever carries a secret's value | `SCOUT-SECRETS-ALLOWLIST`; `# BF-ADOPT-ARCHIVE-PROJECT` | WP2 XB, WP6 | built |
| I9 | Both state files carry the tier keys, in the vocabularies their readers expect | `# BL-221-ADOPT-TIER-KEYS`, `# BL-268-MODE-VOCABULARY`, `# BL-253-POC-NULL` | bl253 parity, bl268 suites | built |
| I10 | `APPROVAL_LOG.md` is written first, so no interruption leaves phase-state without it | `# BL-242-APPROVAL-LOG-FIRST` | wp9b AM1 | built |
| I11 | The preflight runs before any question or write | `# BL-242-PREFLIGHT-CALL` | wp9b P-block | built |
| I12 | **An adoption run may be re-run from scratch only while no stamp exists in the working copy or at HEAD; after the stamp the only routes are `--finish` (the window) and `resume.sh` (landed)** | arm 1 and its window sub-arm (M4); the `write_set` stage | WP9d's window proofs (§10) | **NOT BUILT** — the window is refused with the wrong route today (§13-V33) |
| I13 | **The *gates are live* sentence is printed only when derived from where git runs hooks (R1)** — **and derivation ALONE does not carry R1's promise: §13-V48 case A is a run where this invariant HOLDS and the sentence is still TRUE of a hook the repository does not own, which is why I22 stands beside it** | M2's re-read of `git rev-parse --git-path hooks` | WP9d's hooksPath and unwritable-hooks proofs | **NOT BUILT** — unconditional today (§13-V32) |
| I14 | **The stop keys on a scan Act 2 ran itself, under the framework's rules (§6.2b)** | M7's no-checkout clone and `-c` config | WP10b's handed-in-report and repo-local-rules proofs | **NOT BUILT** |
| I15 | An acknowledgement or accepted risk is recorded, and refused if it cannot be (the 2026-08-31 and 2026-09-16 rulings) | the `dispositions` stage; `bypass_audit_append`'s rc | WP10b's drop-the-signer and corrupt-ledger proofs | **NOT BUILT** |
| I16 | Act 4's `.adoption.assessment` merge is the LAST stage (A2) | `_adopt_act4_order`'s last row | WP12a/b merge-first mutation | **NOT BUILT** |
| I17 | No fitness finding without a requirement pointer; no verdict without its plain half (D7, D8) | the finisher's validation refusals | WP12a's schema proofs | **NOT BUILT** |
| I18 | **The in-production exemption reaches the delta guard, the resume delta branch and the era report, and NO phase gate (R2)** | M13's predicate in exactly those three readers (§13-V40) | WP12c's byte-identical-gate proof | **NOT BUILT** |
| I19 | Module direction: no core file names a module file; core reads module STATE only through `jq` | `# BL-215-CORE-GLOB-SYNC`; `scripts/lint-delta-boundary.sh` | the two lints, in the PR-blocking sweep | built |
| I20 | **No planned path that pre-exists in the adoptee is outside the archive inventory** — the rehearsal's planned set ∩ the paths that existed before it ⊆ the inventory's `originalPath`s | proposed: one loop after the rehearsal, before the first real write (M9) | WP11's PROJECT_INTAKE.md fixture; the mutation drops the loop | **NOT BUILT** — violated today (§13-V34) |
| I21 | The framework's hooks and the archive's `git-hook` class read the same directory, the one git runs from | M1/M2's resolved directory in both `adopt_install_hooks` and `adopt_archive_inventory` | WP9d/WP11: a hooksPath-same-dir fixture archives and installs in one place | **NOT BUILT** |

**The invariant behind the four measured defects is the same one each time**: a receipt printed
from a fact the run did not derive — *live* from a path git does not read (I13), *nothing was
committed* over a stamped, staged tree with no finish route (I12), *nothing of yours was touched*
over an overwritten intake (I20), *yours, kept* naming a path the index does not hold (A8). The
repository's recorded rule applies to the driver as much as to this document: derive the
sentence, or do not print it.

---

## §10 — Build plan (re-cut work packages)

Shipped packages (WP0–WP4, WP5b, WP6, WP8 — see §1.1) are **history, not plan**, and are not
re-cut retroactively. **WP5 is RETIRED** (§5.1) — not re-cut, retired; its only surviving
shell-checkable residue (the record lint) was always WP7's. New packages are numbered from WP9 to
avoid colliding with shipped numbers. Every mutation proof asserts on **what the property
actually is**, and never on a printed label: a **verdict** by exit code (v1 §10's rule, inherited
with its `[WARN]`-trap rationale — two arms printing `[WARN]` can have opposite gate outcomes); a
**state change** by reading the state (WP9's A1 proofs, where mutant and control both exit 1 with
near-identical text, and whose arm-3 mutant exits **0**); a **route** by the branch taken
(WP12b-A3); **content** by the content (WP10, WP11). *(This preamble read "exit codes, never
printed labels" flatly until 2026-08-31, which three proofs in this section already contradicted.
The rule was always about not trusting labels — not about exit codes being the only honest
signal.)* Every enforcement change carries the RED-under-neuter → GREEN-restored discipline.

**Sequencing (re-cut 2026-09-17): `## BL-225:` first (built), then WP9 (built) → WP9d → WP10b → WP9c → WP11 → WP12a → WP12c → WP12b → WP7.** WP9d precedes WP10b because each of its items repairs a defect measured on the SHIPPED path (§13-V32–V34) and WP10b's stop uses its `adopt_block` primitive and its step-0 preconditions; WP9c is independent of WP10b and may land either side of it, but before WP11 (which absorbs its colliding-reference disclosure into the `document` class) and before WP12a (whose prompt paragraph becomes derived from what WP9c wrote); WP12c needs WP12a's `inProduction` and nothing of WP12b. *(v2.1's line read `WP9 → WP10 → WP11 → WP12a → WP12b → WP7`.)* BL-225 (the driver
stages 64 files, then a `.gitignore` refusal claims *"nothing has been committed"* over a
half-staged tree) is not a v2 package — it is a shipped defect on the exact path every Act 2 run
takes, and `## BL-242:` names it the precondition for any resumption. No v2 package lands before
its fix. **Both halves are built** — the staging half in PR #368, the before-any-write half in PR #410
(2026-09-14) as a rehearsal of the whole write phase on a copy (§8.2a) — and `## BL-225:` stays
Open only for two named residuals (§12 item 17). The sequencing precondition is met.

**WP12 IS SPLIT into 12a and 12b**, on an architecture review's recommendation made twice (once
before D10 and once after, when the seam moved and improved). 12a is a complete, shippable minimal
Act 3/4 — assessed, intake pre-filled, verdict presented, documents left honestly stubbed on the
pattern this feature already uses for exactly that purpose. The D10-specific argument that settled
it: in the 12a-only window no `PRODUCT_MANIFESTO.md` exists yet, so `resume.sh` routes an assessed
project into a Phase-0 entry — the flow D10 describes — which makes the interim state *more*
aligned with D10 than the pre-A3 end state was.

**WP9 is BUILT as two PRs, WP9a and WP9b**, and the seam is stated here so a reviewer of either
knows what the other owes. **9a** — the deletions (chooser, ladder, floor, placement), the
scenario/landed-phase threading, the stamp's v2 shape, the tier question at step 1, the phase-0
landing, the Act-3 handoff, A5–A8, and `docs/adoption.md`. **9b** — A1's three-arm preflight and
A4's `APPROVAL_LOG.md`, each with its own fixtures and mutants. They are one work package with one
scope row; the split is a review-surface decision, not a scope decision, and **both land before
WP10**.

**WP10 is being built as two PRs on the same terms — 10a BUILT (merged 2026-09-04, PR #373), 10b
NOT.** 10a is step 2 and §6.2's re-scan; 10b is §6.1's tier table — now five rows, the fifth ruled
2026-09-16 (§6.1a) — §6.3's dispositions and §6.4's tiered escape. One scope row, one boundary;
10a's own header says it makes no stop/proceed decision (§13-V22). **Its suite does NOT pin that a
`tool-unavailable` report still completes an adoption** — that sentence is the suite's header comment,
read back as an assertion by two earlier drafts: the only case that ends at `tool-unavailable` (R3)
asserts the attestation text, never the rc, and every rc-0 pin (X1, X3b, X10, S1b, S5b) runs on a
clean `scanned` report. The completion is read from the code — every unresolved arm returns 0 — and
WP10b's suite must pin the rc it changes (corrected 2026-09-16). The split is attributed to
Karl by 10a's commit message; that attribution is the commit's (§13-U(v2.1)). **10b's cell was
re-cut on 2026-09-17** for the buildability gaps B2 and B4 and the design defects A2, A4 and A10,
with one proposed marked line per arm.

**Three packages are NEW in v2.2 — WP9c, WP9d, WP12c** — and §0.3's v2.2 entry states, as a measured
claim, that none of them takes work an existing cell owned at `579b0b0`. **Proposed markers are
written BARE in this section — BL-242-HOOKS-DIR, spelled like that, neither backticked nor
hash-prefixed — on purpose.** `scripts/lint-bl-markers.sh` requires every backticked or hash-prefixed `BL-NNN-…` token
in this document to resolve to a marker that exists in the code surface, and none of these exists
until its package lands; a bare token is not a citation to that lint (its own header says so, and
so does CLAUDE.md's citation rule). The implementer mints each one as `# BL-242-<NAME>` on the
line the cell names, and the day it exists this document backticks it and the lint enforces it. A
cell that names a marked line therefore names WHAT the line does and the function it lives in;
the marker is the handle the mutation proof will `sed`. The delta track's markers are `DELTA-…`
by that design's own rule and are unchecked either way.

| WP | Scope and boundary | Proofs |
|---|---|---|
| **WP9 — Chooser deletion + act boundaries (D4, D5 skeleton)** | Delete `ADOPT_CHOOSER_QUESTION`, both answers, `adopt_ask_scenario`, `adopt_ask_ladder`, the claimed operand (`# BF-ADOPT-FLOOR`'s second input). **`adopt_ask_audience` is RETAINED and re-purposed (D9)** — it is not a deletion target, it moves to the head of Act 2 (§8.2 step 1), and its output stops feeding placement while continuing to feed `deployment`; re-shape `soif_adoption_stamp` per §8.3 (in-core — inherits WP3's dual-direction proof duty); **A1's step-0 re-adoption preflight, all THREE arms** (stamped-or-committed-witness; prior archive; **already framework-managed** — §8.2 step 0) and **A4's `APPROVAL_LOG.md`, rendered from the tier-matched `init.sh` template and written FIRST in step 7** (not a fourth "empty, headed" shape — §8.3a-A4 rejects that by name; `verify-install.sh`'s `fix_approval_log` is the sibling whose shape must agree); Act 2 lands phase 0 and prints the Act 3 handoff — **an honest `adopt_stub_*` NOT-DONE notice naming WP12a, NOT the fifth `resume.sh` branch**, whose predicate reads an `.adoption.assessment` only WP12a writes, so emitting that prompt now would point at a step that does not exist; the init-parity audit table, **delivered at §8.7a**; **A5** (rename `adopt-chooser.sh` → `adopt-evidence.sh`), **A6** (the evidence block survives, re-worded), **A7** (Act 2's reverse intake keeps only its scan-derived confirmations), **A8** (retire the gate's cosmetic `.adoption.scenario` read; delete `adopt_stub_certification`; correct `adopt_stub_project_docs`' owner string); **`docs/adoption.md`'s chooser, placement, floor-rule and "what both scenarios share" sections — WP9's, not WP12b's**, because §4.2's completion check is that the verbatim question's grep returns nothing after WP9 and the page is one of the four files carrying it; drive-by NOT taken: `adopt_stub_hooks`'s stale owner string → WP7 (`## BL-242:` shows the obvious rewrite would propagate a false §10 attribution). **Added after adversarial review, and all three are what make A7's deferral honest rather than merely fail-closed:** the `## 13.` kickoff section rendered into `PROJECT_INTAKE.md` with a fenced prompt the extractor can find (and which names the classification as non-optional); the seven keys `intake-wizard.sh`'s `load_progress()` subscripts, with `last_section: 0` so `--resume` walks Section 5 rather than resuming past it; and `.claude/orchestrator-source.json` (`# BL-242-ORCH-SOURCE`), **the one §8.7a unowned row this package closes** — because the Phase 1→2 ZDR block names `reconfigure-project.sh` as its escape hatch in its own FAIL text and that hatch died on the missing file. Plus `workflow.html`'s Step-B/Step-C cards (§4.2). **Boundary: no tool resolution, no secrets stop, no archive classes — WP10/WP11's; no fifth resume branch and no interview — WP12a's.** | The WP4 suite's `CHOOSER_LITERAL` pin is **re-aimed at absence**: the verbatim question occurring anywhere in `scripts/` fails. **Mutation:** restore `adopt_ask_scenario`'s call in `adopt_main` → RED. **D9 needs the opposite pin, and it is not optional** — a suite that only proves absence would go green on a WP9 that deleted both questions: assert the audience question is ASKED and that `deployment` lands non-empty in both written files → **mutation:** delete `adopt_ask_audience`'s call → the fixture's `manifest.json` and `phase-state.json` carry `deployment: ""` and `assert_choosable` fail-closes → RED. Assert on the **empty value and the exit code**, not on the refusal's wording. Stamp dual-direction: (i) a fixture adoption lands `current_phase` 0 — mutate the landing to any other rung → RED via the fixture's phase-state (the stamp carries no `placement` key to assert on: §8.3 removed it with D10); (ii) the second-stamp refusal still refuses (regression, exit-code-asserted). **A1 — three fixtures, one per arm, and the first one's STARTING STATE is load-bearing.** (i) a **stamped** fixture whose phase-state records `current_phase` ≥ 1 with at least one dated gate, hand-advanced: at the natural resting state of 0-and-null a revert *to* 0-and-null is invisible and the mutation stays green forever → refuses with the **tree hash unchanged** (hash includes untracked files) → **mutation:** drop arm 1 → phase-state reverts and its gates dates null → RED. Assert on the reverted STATE, never the refusal text: the restamp refusal fires either way with near-identical wording, which is precisely what made this defect survivable. **ARM 3 MASKS THIS MUTATION UNLESS THE ARMS ARE SPELLED DISJOINTLY** — a stamped fixture necessarily has a `phase-state.json`, so arm 3 catches it too and dropping arm 1 changes nothing observable. Arm 3 therefore carries the *not-adopted* conjunct its §8.3a description already implies (it is the **already framework-managed but NOT adopted** arm), and the mutation drops arm 1 with that conjunct intact. (ii) an **unstamped fixture carrying a prior archive** → refuses, naming that directory → **mutation:** drop arm 2 → the fixture adopts → RED. That fixture must carry **no `.claude/phase-state.json` and no `.claude/manifest.json`** — an interrupted run that died before the state stage — or arm 3 masks this one as well. (iii) a **scaffolded greenfield** fixture → refuses, tree hash unchanged → **mutation:** drop arm 3 → phase-state reverts AND the manifest gains `.adoption`, **exit 0** → RED. Arms 2 and 3 both have mutants that exit **zero** (each completes the adoption), so neither assertion may key on a non-zero exit — assert the refusal and the unchanged tree instead. Arm 1's mutant exits 1 via the restamp refusal, which is why its assertion reads the reverted STATE. **A4 — two arms needing DIFFERENT fixtures.** Green, on the Act-2 resting fixture: the log exists and `check-phase-gate.sh` runs to a verdict instead of exiting on a missing file → **mutation:** drop the write → the gate refuses before parsing the phase → RED. **Converse, on a phase-0-complete-except-approval fixture** — manifesto with its eight non-placeholder sections, the `docs/phase-0/` trio, the intake — because on the resting fixture `--gate phase_0_to_1` blocks for three independent reasons and removing one leaves it blocked (3 → 2 issues, still exit 1), so "the gate passes a boundary nobody approved" is **unreachable there** and that mutation could never go RED. On the discriminating fixture: template as rendered → blocks with exactly 1 issue; **mutation:** seed a well-formed dated **gate-approval** row → **exit 0** → RED. Two constraints: the gate **auto-records** a seeded date into phase-state, so each arm needs a fresh tree; and a malformed row adds issues instead of passing. *(The template's pre-condition `__TODAY__` cells are not gate-approval rows and do not match the gate's evidence grep — that is why the rendered template still blocks.)* **A5–A8, and three of the four need a POSITIVE CONTROL because each asserts an absence.** **A5:** no file named `adopt-chooser.sh` under `scripts/lib/adopt/`, the driver's source loop names `adopt-evidence`, and `bash -n` on the driver — an absence with a structural discriminator, since a rename that broke the loop and an absence look identical downstream. **A6:** the transcript still carries all four evidence signals each with a confidence tier AND no longer carries the sentence that points at a deleted question → **mutation:** drop `adopt_present_evidence`'s call → the four signals vanish → RED. The positive half is the load-bearing one: an assertion that the old sentence is gone passes against a driver that prints nothing at all. **A7:** the transcript carries the scan-derived confirmations and NEITHER a judgment question NOR the classification prompt, and `PROJECT_INTAKE.md` carries the confirmed cells → **mutation:** restore `adopt_ask_data_classification`'s arm → the same short answer script now reaches `# BF-ADOPT-DC-MANDATORY` and the run REFUSES (exit 1, nothing written) → RED, asserted on the exit code and the absent state, not on the refusal's wording. **A8:** on an adopted fixture the gate prints its `Adoption Stamp Integrity` OK line and that line does NOT contain `scenario:` → **mutation:** restore the `.adoption.scenario` read → the line names `scenario: unknown` → RED; the positive control is that the line is printed at all, because "no scenario named" is trivially true of a gate that skipped the block. **R1–R4 — the three routes A7's deferral depends on, each EXECUTED rather than described**, because that conjunct was asserted by nobody and was false on all three: `resume.sh` on the adopted fixture must emit a real §13 prompt naming the classification (not the generic fallback); the progress file must carry all seven subscripted keys at `last_section: 0`; and `reconfigure-project.sh --field data_classification` must actually land the value in the file the gate reads → **mutation:** drop the `orchestrator-source` write → the hatch goes dead and the classification stays ABSENT after running the very command the gate tells the operator to run → RED. **C2 is a whitespace-normalised sweep of every TRACKED file**, not a `grep -F` over `scripts/`, with two allowlisted carriers named — and **C4 injects a LINE-WRAPPED occurrence** and asserts the naive recipe MISSES it while the normalised one FINDS it, which is the shape that escaped into `workflow.html`. **The stamp's v2 shape, asserted as a KEY SET and not as four absences:** the adopted fixture's `.adoption | keys` is exactly `{adopted, adoptedAt, adoptedAtCommit, schemaVersion, scannerReportSha256}` → **mutation:** re-add any removed key → RED, which catches a partial deletion that four separate absence assertions would each pass |
| **WP9d — The driver's edges (NEW 2026-09-17): hooks placement (R1), the adoption window (A3), the rehearsal bound (A7), the labels (A10), the preconditions (B8)** | Seven items, all in the SHIPPED driver, none owned by any unbuilt cell at `579b0b0`. **(1) R1's three step-0 refusals**, in `adopt_preflight` before the arms, in a new `_adopt_preflight_placement` (M1): `--root`'s physical path equals `git -C root rev-parse --show-toplevel`'s (BL-242-PLACEMENT-TOPLEVEL); `[ -d "$root/.git" ]` (BL-242-PLACEMENT-GITDIR — a linked worktree or a submodule has a gitfile); `core.hooksPath` unset by EXIT STATUS, or set and resolving by physical directory to `$(git rev-parse --git-common-dir)/hooks` (BL-242-PLACEMENT-HOOKSPATH, `# BL-209-HOOKSPATH-SAME-DIR`'s comparison) — each refusal is `[REFUSED]`, names what it found and prints the remedy in that installer's shape. **(2) The hooks directory resolved through git**, spelled once in `_adopt_hooks_dir` (BL-242-HOOKS-DIR: `git -C root rev-parse --path-format=absolute --git-path hooks`, falling back to `cd "$(git -C root rev-parse --git-path hooks)" && pwd -P`), used by BOTH `adopt_install_hooks` and `adopt_archive_inventory`'s `git-hook` class (I21). **(3) The derived *live* sentence** (M2): after the install, re-resolve the directory and require an executable `commit-msg` there containing `SOIF_TDD_OPEN` (BL-242-HOOKS-LIVE-DERIVED); print the two-gates sentence only then; otherwise print what was found, that the hook is NOT installed, and end as a block (`ADOPT_COMMITTED=1`, so the sentence says the commit HAD landed). **(4) The window** (M4): a `write_set` stage appended to `_adopt_state_order` (BL-242-WRITE-SET) writing `.claude/adoption/write-set.txt` from `adopt_written_paths` plus itself; arm 1's sub-arm (BL-242-PREFLIGHT-WINDOW) — working-copy witness true AND committed witness false, the two calls `_adopt_preflight_adopted` already makes — with its own message naming `--finish`; the `--finish` flag in `adopt-project.sh` dispatching `adopt_finish_main` (BL-242-FINISH), which re-derives the window, refuses on any other state, reads the write set, runs `# BL-225-STAGE-PREFLIGHT`'s dry-run over it, stages exactly those paths, commits with the same subject, runs `adopt_install_hooks` and prints the handoff; `[REFUSED]` when the write set is absent or names a path not on disk — never `git add -A`. No shipped *run adoption again* sentence reaches the window — `# BL-242-RESOLVER-NO-EXEC`'s is WP10b's (§12 item 22), arm 2's not-yet-installed branch precedes the stamp, and the `n_copied -eq 0` tripwire is DELETED by WP11 (its cell says so) — so this package adds the window's own sentence and re-words none of theirs (the review caught the earlier three-sentence claim). **(5) The labels** (M5): `adopt_block` in `adopt-core.sh` (BL-242-BLOCK-LABEL); the sites in §8.1's third row migrate — `# BL-225-PREWRITE-REFUSE`, `# BL-225-STAGE-PREFLIGHT`'s refusal. **(6) The preconditions** (M3): `_adopt_preflight_identity` (`git -C root var GIT_COMMITTER_IDENT`, BL-242-IDENT-PRECHECK); the hash tool at step 0 (`# BF-ADOPT-SHA-REQUIRED` stays as the writer's own guard); `[ -w ]` on the resolved hooks directory when it EXISTS and on its PARENT when it does not — **a CONDITIONAL, never a disjunction** — and **spelled by calling `preflight_target_writable` (`scripts/lib/helpers-core.sh`), not by writing a second predicate**: the driver's own core loop in `scripts/adopt-project.sh` already sources it, `init.sh` already uses it for this exact question (`preflight_target_writable "$_early_target"`), and its deepest-existing-ancestor walk IS this conditional generalised — measured by the independent review at rc 0 on an absent `.git/hooks` and rc 1 on a 555 one, byte-for-byte the two behaviours this item specifies. Its failure text names *project directory* and needs parameterising for a hooks directory; that is the only work here. An inline predicate written beside a shipped helper is the second-list defect this document refuses everywhere else — §8.1's row carries the *or its parent* half and this cell did not until 2026-09-17, which would have shipped a NEW false refusal out of the package whose whole subject is false receipts: `git init` copies the stock template's `hooks/` for free, so an operator whose `init.templateDir` carries none gets a repository with no `.git/hooks`, and `[ -w ]` on an absent directory is FALSE. Measured 2026-09-17 (§13-V47): under `GIT_TEMPLATE_DIR` pointed at a template with no `hooks/`, `[ -d .git/hooks ]` is false, `[ -w .git/hooks ]` → rc 1, `[ -w .git ]` → rc 0; with the stock template the directory exists and `[ -w ]` → rc 0. The condition is not hypothetical — it is the second arm of `## BL-209:`, it is the state of the machine `tests/test-bl209-hooksdir-resolution.sh` was written on, and an outside contributor measured twelve unit-lane suites failing under it on 2026-09-17 (two of them adoption's own, `test-brownfield-wp1-scout.sh` at 33/2 against 35/0 with the stock template). **The proof owes three cases, because the predicate has two arms and a disjunction passes the third:** (i) a fixture built with an empty `GIT_TEMPLATE_DIR` — no `.git/hooks`, writable `.git` — ADOPTS (`adopt_install_hooks` creates the directory as it always has) → **mutation:** drop the parent arm → refused at step 0 → RED. (ii) a fixture whose EXISTING `.git/hooks` is `chmod 555`, run as a NON-ROOT user (CLAUDE.md's `chmod 555` trap — as root the mode is ignored and the case is vacuous), is REFUSED at step 0 → **mutation:** drop the precheck → the run reaches the adoption commit and blocks at the hook write → RED, asserted on the commit's presence. **The fixture is `chmod 555 .git/hooks`, NOT `chmod 555 .git`**: measured, a `.git` at 555 fails `git add` with *Unable to create … .git/index.lock: Permission denied*, so the run never reaches the hook write and the mutant's control is unreachable (§13-V47; the first draft of this cell named `.git` and was wrong). (iii) **the shape rules, which precede the write test** (R1's symlink extension and M16): `.git/hooks` as a symlink to a writable directory OUTSIDE the fixture → REFUSED at step 0, and the outside directory is UNTOUCHED after the run → **mutation:** drop the symlink guard → the run adopts, the hook lands in the outside directory, and the *live* sentence prints → RED, asserted on a file appearing outside the repository the run never disclosed; a DANGLING `.git/hooks` symlink → REFUSED at step 0 → **mutation:** narrow the guard to `[ -e "$p" ] && [ ! -d "$p" ]` — a shape that looks equivalent and is not, because `[ -e ]` on a dangling link is FALSE — → the dangling fixture is admitted → RED. *(Its own source edit: the first wording said "drop it", which is the previous mutation read twice — the independent review caught that.)* **And the composition, which each rule alone admits:** `core.hooksPath` pointed OUTSIDE and `.git/hooks` symlinked to that same directory → REFUSED → **mutation:** test the shape of only the path git names, not of this repository's own hooks path → the same-directory narrowing fires, the shape rule finds a real directory, the run adopts at rc 0 and the gate lands outside (§13-V49) → RED; `.git/hooks` as a regular file → REFUSED at step 0 → **mutation:** drop M16's arm → `mkdir: File exists` after the commit → RED. **The guard tests the DIRECTORY, never a leaf hook file** — `# BL-145-SYMLINK-GUARD-BEGIN`'s header records that a leaf `-L` test is not sufficient, which is the mistake this case exists to prevent: **mutation:** test `-L` on `$hooks/commit-msg` instead of on `$hooks` → the symlinked-directory fixture adopts → RED. (iv) **the disjunction mutant**, which is the reason the write test is a conditional: replace the two arms with `[ -w "$hooks" ] || [ -w "$(dirname "$hooks")" ]` → case (ii)'s fixture PASSES step 0 and blocks after the commit → RED. **(ii)'s CONTROL already fails under a disjunction** — its fixture has a writable parent, so a disjunction passes step 0 and the refusal never comes — so (i) and (ii) alone DO kill a disjunction implementation; (iii) names that mutant explicitly, so the reason (ii)'s control is worth asserting is on the record rather than rediscovered. *(The first draft of this cell called (iii) the only discriminator; the independent review measured it and it is not.)* A `python3` disclosure in the handoff — **NOT BUILT in the 2026-09-18 pass and recorded rather than quietly dropped (§12 item 34): the other six halves of item (6) are, and this one has no defect behind it, no entry, and no stated failure mode.** **(7) The rehearsal bound** (M6): `adopt_prewrite_preflight` copies with `.git/objects` excluded and writes `.git/objects/info/alternates` (BL-242-REHEARSAL-SHARED); measures `du -sk` before copying and refuses above `SOIF_ADOPT_REHEARSAL_MAX_MB` (BL-242-REHEARSAL-BOUND); prints *rehearsal ran in N s over M MB (objects shared, not copied)*; a `SOIF_REHEARSAL_KEEP` seam leaves the copy in place for the suite. **Boundary:** no archive classes, no secrets decision, no document writing, no reference copying. Every existing adoption suite keeps passing unchanged — their fixtures are ordinary repositories adopted from their top level. | **Every fixture in §10 that writes a hook CREATES `.git/hooks` first — this package's, WP11's two (`pre commit` with a space, and the newline-bearing name) and WP7's.** *(The rule was written "every fixture below" in this cell's first draft, which scoped it to WP9d alone; the independent review found WP11 and WP7 uncovered, and WP11's named ancestor `tests/test-brownfield-wp6-collision-archive.sh` safe only because it happens to `mkdir -p` the directory — the property held by luck, one layer out, which is this entry's own lesson.)* The wp9b `mk_adoptee` shape these build on touches no hooks directory and is 103/0 under an empty `GIT_TEMPLATE_DIR` as well as the stock one (measured 2026-09-17, §13-V47), so it carries the property in by luck rather than by construction; fifteen suites in this repository write into that directory without creating it and twelve fail when git's template has no `hooks/`. A WP9d fixture that inherits the omission reads as *the gate did not fire* when the truth is *the hook never landed* — the silent shape this package exists to remove. **R1 — three fixtures, each REFUSED with the tree hash unchanged, on the wp9b `mk_adoptee` shape plus one condition.** (a) `core.hooksPath` set to a temp directory → `[REFUSED]`, the message names hooksPath and prints the `git config --unset` remedy, nothing written, no *live* sentence → **mutation:** delete BL-242-PLACEMENT-HOOKSPATH → the run completes at rc 0, the hook lands in `.git/hooks`, and `GIT_TRACE=1 git commit` in the fixture shows NO `commit-msg` run — §13-V32's measurement, now a RED; assert on the trace and the written path, never the label. (b) `--root` a sub-directory of the fixture → the CONTROL refuses at step 0, BEFORE the tier question, naming the sub-directory and the top level → **mutation:** delete BL-242-PLACEMENT-TOPLEVEL → the run asks the tier question and every confirmation and then prints `[REFUSED] the pre-write rehearsal did not complete (rc=1)` — today's behaviour, §13-V32b — so control and mutant BOTH exit 1 with nothing written, and the assertion is on the SITE: the transcript's question count is 0 in the control and at least five in the mutant, or equivalently the refusal names the sub-directory (control) versus the rehearsal (mutant) → RED. *(v2.2's first cut had the mutant adopt the sub-directory; the review executed it — R-9 — and it cannot: the rehearsal refuses first.)* (c) a linked worktree (`git worktree add` inside the fixture) → refused → **mutation:** delete BL-242-PLACEMENT-GITDIR → the worktree adopts and the hook lands in the MAIN repository's `.git/hooks` (where `--git-path hooks` points, §13-V31) → RED; the assertion is *a file the run never disclosed appeared under the main repository*. (d) **the same-dir exception (M1, author-proposed) is a POSITIVE control:** `core.hooksPath` set to the ABSOLUTE path of the fixture's own `.git/hooks` — a relative value resolves against the process cwd, so the control must be absolute (the review's note) — → adopts at rc 0 → **mutation:** compare strings instead of physical directories → refused → RED, the false refusal `# BL-209-HOOKSPATH-SAME-DIR` was written against. **The derived sentence, on the ordinary fixture — through a SEAM, because item (6)'s `[ -w ]` precheck refuses an unwritable hooks directory at step 0, before the tier question, and the cell cannot hold both (the review's R-10):** `SOIF_ADOPT_FAIL_HOOK_WRITE=1`, a fault injector on `adopt_install_hooks`'s write — the `SOIF_ADOPT_HALT_AFTER` precedent, a seam for the real run — → the commit lands, the hook is not written, the run ends `[BLOCKED]` saying the commit HAD landed and the hook is NOT installed, and the *live* sentence is ABSENT → **mutation:** make the sentence unconditional → it prints over a hook never written → RED. The precheck keeps its own proof: `chmod 555 .git/hooks` (as a NON-root user, CLAUDE.md's `chmod 555` trap) → `[REFUSED]` at step 0, nothing written → **mutation:** drop the precheck → the run reaches the commit and blocks at the hook write → RED, asserted on the adoption commit's presence. **I21:** on the same-dir fixture with a pre-existing `commit-msg`, the archive's `git-hook` row and the installer's target name the SAME resolved directory → **mutation:** leave `adopt_archive_inventory` on the literal `.git/hooks` → they differ → RED. **The window, on §13-V33's fixture (own pre-commit hook `exit 1`):** run 1 ends `[BLOCKED]` at the commit with `.claude/adoption/write-set.txt` present and listing every written path including itself → **mutation:** drop the `write_set` stage → the file is absent → RED. Run 2 (bare re-run) refuses and its message names `--finish` and NOT `resume.sh` → **mutation:** delete BL-242-PREFLIGHT-WINDOW → the generic arm-1 message with `resume.sh` returns → RED (assert on the named route; mutant and control both exit 1). `--finish` after the hook is removed → the adoption commit lands, HEAD moves, the committed manifest is adopted, the commit-msg hook is installed, rc 0 — **and an unrelated dirty file placed in the fixture before `--finish` stays unstaged and uncommitted** → **mutation:** let `--finish` fall back to `git add -A` when the write set is missing → with the write set deleted the unrelated file is committed → RED: the never-`git add -A` property, with a reachable mutant at last (I3). `--finish` on a fixture NOT in the window — landed, or never adopted → `[REFUSED]` → **mutation:** drop the re-derivation → `--finish` on a landed fixture makes a second commit → RED. **I12:** a bare re-run on the window state must NOT finish silently → **mutation:** have the sub-arm call `adopt_finish_main` → the re-run commits → RED. **Labels, both directions:** the BL-225 rehearsal-refusal fixture prints `[BLOCKED]` and `NOTHING WAS WRITTEN` → **mutation:** route `# BL-225-PREWRITE-REFUSE` back through `adopt_refuse` → `[REFUSED]` → RED; the arm-1 fixture prints `[REFUSED]` → **mutation:** route it through `adopt_block` → RED — a primitive collapsed into one cannot pass both. **Identity:** a fixture built WITHOUT `mk_adoptee`'s `user.email`/`user.name`, the driver run with `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true` in its environment — the `-c` form of §13-V41 reaches only the harness's own git call, never the driver's (the review's note); the environment form reaches every git the driver runs, and it is CLAUDE.md's recipe for forcing a git condition on this Mac — → `[REFUSED]` at step 0, nothing written, no stamp → **mutation:** drop BL-242-IDENT-PRECHECK → the run stamps and then blocks at the commit → RED, asserted on the stamp's presence. **Rehearsal bound:** the ordinary fixture's transcript carries `rehearsal ran in` with a number and `objects shared`, and with `SOIF_REHEARSAL_KEEP` the copy's `.git/objects/info/alternates` exists and names the fixture's object store → **mutation:** copy `.git/objects` too → the alternates file is absent → RED (the copy is deleted at the end of the preflight, so without the seam neither control nor mutant is observable — the seam is load-bearing, not convenience); `SOIF_ADOPT_REHEARSAL_MAX_MB=0` → refused BEFORE copying with the measured size in the message and no rehearsal directory → **mutation:** measure after copying → the directory exists → RED. |
| **WP9c — §8.7a rows 18–21 (NEW 2026-09-17, A6): the reference documents, the session hooks, the MCP declaration, the vendored skills** | Owns rows 18, 19, 20, 21 — UNOWNED at `579b0b0` (§13-V38 prints the rows as they stood). ONE new stage, `reference`, in `_adopt_write_phase` between the framework install and the state loop (BL-242-REFERENCE-STAGE), so the rehearsal covers it and `## BL-225:`'s T9 sees its writers through `adopt_write_file`. **(1) `docs/reference/*`** — the eight files `init.sh` copies, DERIVED from its `cp "$SCRIPT_DIR/docs/…" docs/reference/` lines through a shared parser beside `soif_parse_shipped_scripts` (proposed `soif_parse_shipped_reference_docs` in `scaffold-shipped-set.sh`), never a second list; copied when absent; a pre-existing file at one of the eight paths is a COLLISION: before WP11, disclosed and left; after WP11, archived and replaced through the `document` class. **(2) `.claude/settings.json` — COMPOSED, never overwritten (M11):** absent → written with `init.sh`'s permissions block, extracted into a shared emitter in `scripts/lib/` (the `# BL-243-HOOK-TEMPLATE` precedent), the language rules keyed on Scout's dominant language; present → archived first (`ai-settings`, disposition `composed`) then `allow`/`deny` unioned in; then the hook roster registered with `init.sh`'s own idempotent `jq` idiom — the roster DERIVED from `init.sh` (`grep -oE 'contains\("[a-z0-9-]+\.sh"\)'` and the event each sits under, §13-V38) through a shared table — for every script EXCEPT `bypass-detector.sh`'s PostToolUse arm: its Stop arm is registered now; the PostToolUse registration is ONE guarded line (BL-242-SETTINGS-BL277) that stays OFF until `## BL-277:` is Closed, and the transcript says so. Unlike greenfield, the roster is registered UNCONDITIONALLY — `init.sh` writes it only inside its `framework_valid` branch, when the CDF clone succeeded (§13-V38; row 33) — and the handoff records that the CDF was not installed. **(3) `.claude/settings.local.json` + `.mcp.qdrant_required`** — `init.sh`'s predicate extracted into the same shared lib (a Qdrant container running AND `command -v uvx`): when true, the same heredoc and `# BL-233-WPB-MANIFEST-DECL`'s manifest key; when false, nothing written and one handoff sentence. **(4) The four skills** — the loop's list derived from `init.sh` (§13-V38), framework-wins through the existing `skill` class. **The prompt's *WHAT YOU DO NOT HAVE* paragraph becomes DERIVED:** `adopt_render_section_13` prints it only for reference files the stage did NOT write, naming them; when all eight landed it names the guide's path instead. **Boundary:** no CDF install (row 33 — **ruled YES 2026-09-18; neither designed nor owned**); no document adaptation (WP12b); no `document` class (WP11). **Dependency, recorded not decided:** the PostToolUse detector registration ships the day `## BL-277:` closes, under whichever of its three options Karl picks; this package neither chooses for him nor ships the blocker. | On the wp9b fixture: the eight reference files are present and byte-identical to the framework's (`cmp` against `$ADOPT_FRAMEWORK_ROOT/docs/<name>` — no sha list), `settings.json` parses, every script `init.sh` registers is registered under the same event EXCEPT the PostToolUse detector, the four skills are present → **mutation A:** drop the `reference` stage → the eight are absent → RED. **Mutation B — parity by derivation, the `## BL-253:` oracle pattern:** a `settings.json` produced ONCE by `init.sh` WITH the CDF present — the roster is written only inside its `framework_valid` branch (§13-V38), so the producing run needs `~/.claude-dev-framework` cloned, CONTRIBUTING.md's standing requirement for this repository's tests — pinned by its sha with the producing recipe printed beside it; NOT through the `e2e-init` suites, which CLAUDE.md records as red on `main` and full-lane only (the review's note; an outside contributor identified the cause on 2026-09-17 — `init.sh` installs its own pre-push review gate at `install_precommit_hook` and then makes the scaffold's first push through it, which it refuses — so this detour may become unnecessary, and this sentence stale, the day that lands) diffed against the adoptee's as a SET of `(event, script)` pairs: identical except the ONE PostToolUse detector pair → **mutation:** register that arm → the diff is empty → RED — the pin that keeps the `## BL-277:` dependency honest in both directions, and a greenfield that stops registering a hook turns it red too. **Mutation C:** an adoptee with its own `settings.json` carrying a custom `allow` rule → after adoption the rule survives, the archive holds the original with disposition `composed`, the roster is present → **mutation:** write instead of compose → the rule is gone → RED. **Mutation D:** the derived paragraph — on the ordinary fixture the *WHAT YOU DO NOT HAVE* sentence is ABSENT and the guide's path is named; with the stage made to skip `builders-guide.md` (a seam, `SOIF_ADOPT_REFERENCE_SKIP`) the sentence names exactly that file → **mutation:** make the paragraph unconditional → RED both ways. **The wp9 suite's R1 phrase list changes here, and the cell says so** (R-DOC-10's lesson): its pinned *WHAT YOU DO NOT HAVE* sentence is re-aimed at the derived form. **Mutation E (MCP):** with the predicate stubbed TRUE (a seam — no suite may start a container) the manifest carries `.mcp.qdrant_required == true` and `settings.local.json` names the project's collection; stubbed FALSE, neither → **mutation:** write the declaration unconditionally → the false case carries it → RED. **Mutation F (skills):** an adoptee with its own `.claude/skills/session-handoff/SKILL.md` → archived under `skill`, the framework's installed, disclosed → **mutation:** keep theirs → the framework's bytes absent → RED. |
| **WP10 — Act 2 completion: tool resolution + the tier-scoped secrets check (D2)** | **10a BUILT / 10b NOT BUILT (2026-09-16; §6.2a). 10b's cell RE-CUT 2026-09-17.** Invoke `scripts/resolve-tools.sh` before any write (**built**); **§6.1's tier-scoped table, all FIVE cases** — at `organizational` findings stop until dispositioned and `tool-unavailable`, `scan-failed` and `scanned-partial` stop with no escape; at `personal` findings and `scan-failed` warn loudly and carry on, while `tool-unavailable` stops unless an acceptance is recorded and `scanned-partial` stops unless an acknowledgement in §6.3's shape (named accepting person, reason, date — plus scope and commit count, author-proposed) is recorded (ruled 2026-09-16, §6.1a); the §6.3 records via `bypass_audit_append`; the §6.2 re-scan-after-install mechanic (built, 10a); refusal-on-unrecordable. **Boundary: no archive or install changes — WP11's.** **Nothing in §6 is unruled.** Note the two not-scanned statuses are NOT one code path: they share an organizational arm and differ on personal; `scanned-partial` shares `tool-unavailable`'s shape at both tiers and adds the findings the partial scan produced; 10b must not fold it into `scanned` (§6.1a). **Mechanism (§6.2b, §6.3) and its MARKED LINES, all proposed, written bare:** `_adopt_secrets_scan_own` — the no-checkout shared clone in `$ADOPT_WORK` (BL-242-SECRETS-OWN-SCAN), the `-c "$ADOPT_FRAMEWORK_ROOT/templates/gitleaks/framework.toml"` line (BL-242-SECRETS-FRAMEWORK-RULES), `--ignore-gitleaks-allow`, the `GITLEAKS_CONFIG*` scrub, Scout's three libraries and one projection, the splice with `scannedBy`/`rulesSource`; `adopt_secrets_decide` — the ten-cell table as `case "$ADOPT_DEPLOYMENT:$status"` with ONE marked line per arm: BL-242-SECRETS-ORG-FINDINGS, BL-242-SECRETS-ORG-UNAVAILABLE, BL-242-SECRETS-ORG-FAILED, BL-242-SECRETS-ORG-PARTIAL, BL-242-SECRETS-PERSONAL-FINDINGS, BL-242-SECRETS-PERSONAL-UNAVAILABLE, BL-242-SECRETS-PERSONAL-FAILED, BL-242-SECRETS-PERSONAL-PARTIAL, and BL-242-SECRETS-CLEAN shared by both tiers; `adopt_dispositions_collect` — the new `--dispositions FILE` flag in `adopt-project.sh`, else the adoptee's own `.claude/adoption/secrets-dispositions.json` when present, else the interactive fallback through `adopt_ask_choice`/`adopt_ask_free`; `adopt_dispositions_validate` — signer, reason, every fingerprint ∈ the own scan's findings, `scan.head == HEAD` and `scan.commitsScanned` == the own scan's (BL-242-DISPOSITIONS-STALE); the `dispositions` stage in `_adopt_state_order` (BL-242-DISPOSITIONS-STAGE) writing the join table and appending one `adoption_event`/`secrets_disposition` row per accepted risk and per acknowledgement through `adopt_audit_event`, refusing the run on a failed append (BL-242-DISPOSITIONS-REFUSE) before the stamp. Every stop is `adopt_block` (WP9d), exit 1. **`# BL-242-RESOLVER-NO-EXEC`'s sentence (§12 item 22) is resolved here:** a stop precedes the stamp, so after a stop *run adoption again* is TRUE and stays; after a `personal` completion on `tool-unavailable` the run has stamped, and the sentence becomes *the acknowledgement you recorded is in `.claude/adoption/secrets-dispositions.json`; re-scan with Scout once the tool is installed.* **`## BL-289:`'s pin (§12 item 10) lands here:** the matrix entry's `required: true` and a floor ≥ 8.19.0, and a too-old scanner reported as `tool-unavailable` — by `resolve-tools.sh` reading `min_version` (a core change with `init.sh` as its second consumer, reviewed as such) or by Scout probing the subcommand; the pin accepts either. | **Two disciplines, stated apart (the review's R-12).** The ten-cell table is driven through SEAMS, never the host — the wp10a suite's discipline: `SCOUT_GITLEAKS_BIN` for Scout's scan, and a sibling seam for the own scan, `SOIF_ADOPT_OWN_SCAN_BIN`, pointing at a stub scanner that emits a canned report per case. **The own-scan pins (1)–(5) CANNOT be stubbed** — they exist to prove the REAL scanner's rule-file and cwd semantics — so they run the real `gitleaks` and take `tests/test-bl288-scout-shallow-history-claim.sh`'s posture: SKIP when it is absent locally, FAIL when `CI` is set (`.github/workflows/tests.yml` installs the pinned 8.30.1 with a checksum), and print which. Fixtures: the wp9b `mk_adoptee` shape; the bl288 shallow fixtures. **The own-scan pins come FIRST, because every cell below reads its result:** (1) a handed-in `--scan-report` saying `scanned, 0` over a fixture whose history holds the bl288 plant → the stop's scan finds it, the persisted section carries `scannedBy: adoption` and `findingCount ≥ 1`, and the stamp's `scannerReportSha256` hashes THAT report → **mutation:** delete BL-242-SECRETS-OWN-SCAN's call → the handed-in section is what the stop read, and the `organizational` fixture adopts clean → RED. (2) the same history with a TRACKED `.gitleaks.toml` allowlisting the plant AND a tracked `.gitleaksignore` holding its fingerprint (§13-V35's shape) → the own scan still finds it → **mutation:** scan `$root` in place instead of the clone → 0 findings → RED. (3) `GITLEAKS_CONFIG` exported at the allowlisting toml → still found → **mutation:** drop the env scrub AND BL-242-SECRETS-FRAMEWORK-RULES's `-c` together → RED — either alone is masked by the other (measured: `-c` outranks the env), and the cell says so rather than pretending one mutant covers it. (4) an inline `gitleaks:allow` plant → found → **mutation:** drop `--ignore-gitleaks-allow` → RED. (5) a shallow fixture → the own scan says `scanned-partial` and its `commitsScanned` equals `git rev-list --count HEAD` in the ADOPTEE → **mutation:** scan a fresh full clone of the fixture's origin (unshallowing behind the operator's back) → the counts differ → RED. **Then the ten cells, each on the own scan's result, each naming the arm it mutates:** a clean fixture completes at both tiers, rc 0 → **mutation:** make BL-242-SECRETS-CLEAN stop → RED at each tier. `organizational` + `scan-failed` (the stub exits 1) stops before any write — tree hash equal before and after — label `[BLOCKED]`, rc 1 → **mutation:** neuter BL-242-SECRETS-ORG-FAILED → adopts → RED. `personal` + `scan-failed` completes, rc 0, and its warning says nothing is known and does NOT render an empty findings list → **mutation:** reuse the findings template → RED; **mutation:** make BL-242-SECRETS-PERSONAL-FAILED stop → RED. `tool-unavailable` (the stub absent): `organizational` stops even with a valid acknowledgement in `--dispositions` → **mutation:** wire the personal escape into BL-242-SECRETS-ORG-UNAVAILABLE → adopts → RED; `personal` with a recorded acknowledgement completes, the join table's `acknowledgements[0]` carries `by`, `reason`, `kind: tool-unavailable`, and a fixture ledger that CONTAINS it holds ONE `adoption_event` row with `details.event == "secrets_disposition"` and `details.kind == "tool-unavailable"` (v1 §8.9's dead-pin lesson) → **mutation:** drop the signer from the file → refused at step 3, nothing written → RED; **mutation:** drop the append → the row is absent → RED; **mutation:** corrupt the ledger (`[]` twice, the shape `bypass_audit_append` rejects) → the run BLOCKS at the `dispositions` stage BEFORE the stamp (no `.adoption` in the manifest) → then **mutation:** ignore the append's rc (BL-242-DISPOSITIONS-REFUSE) → the run stamps and commits with no row → RED; `personal` with NO acknowledgement stops → **mutation:** let BL-242-SECRETS-PERSONAL-UNAVAILABLE proceed → RED. **The two not-scanned statuses as separate paths:** `personal` `scan-failed` needs no acknowledgement while `personal` `tool-unavailable` does → **mutation:** route both through one arm → RED whichever way. `organizational` + findings (the plant, own scan) with no dispositions stops; with `--dispositions` carrying `rotated` for the fingerprint completes and the join table's `scan.head` is HEAD → **mutation:** drop BL-242-DISPOSITIONS-STALE → a file whose `scan.head` is another commit passes → RED; with `accepted-risk` the ledger holds the row → **mutation:** drop the signer → RED; a fingerprint in the file that is NOT in the own scan → refused as stale → **mutation:** skip the membership check → RED. `personal` + findings completes and prints every finding redacted → **mutation:** make BL-242-SECRETS-PERSONAL-FINDINGS stop → RED; **converse:** make BL-242-SECRETS-ORG-FINDINGS warn → RED — both directions or one arm is vacuous. **`scanned-partial`, both tiers, both directions (§6.1a):** `organizational` on the bl288 S0/S2 shape (plant withheld — ZERO findings) stops and names the unshallow remedy → **mutation:** let BL-242-SECRETS-ORG-PARTIAL proceed → RED; on a SECOND shallow fixture with the plant in a RETAINED commit (the S10 shape — one reachable, one withheld, combined) stops AND prints the reachable finding redacted → **mutation:** drop the print → RED (R-DOC-9's vacuity fix, kept); with a valid acknowledgement it STILL stops → **mutation:** wire the personal escape in → RED. `personal` with a recorded acknowledgement completes; it carries `kind: scanned-partial`, `by`, `reason`, `scope`, `commitsScanned`, `head`; the ledger row exists; the transcript says *part of this history* in those words; on the retained-credential fixture the reachable finding prints redacted → **mutation:** drop the signer → RED; drop the print → RED; drop the recording and proceed → RED; with NO acknowledgement it stops → **mutation:** proceed → RED; **mutation:** route `scanned-partial` through BL-242-SECRETS-CLEAN → the shallow fixture adopts as clean at either tier → RED. **Required at `findingCount` 0:** the S0/S2 shape at `personal` with no acknowledgement stops although it has zero findings → **mutation:** skip the acknowledgement when the count is 0 → RED. **`configFile`:** on the toml fixture the transcript says *your project carries `.gitleaks.toml`; the stop did not use it* and the persisted section's `configFile` still names it while `rulesSource` says `framework` → **mutation:** drop the sentence → RED. **Label and rc:** every stop prints `[BLOCKED]` with the derived *nothing was written* and exits 1 → **mutation:** route the stop through `adopt_refuse` → `[REFUSED]` → RED; every `personal` completion exits 0 — the rc pin the wp10a suite never had. **`## BL-289:`:** `templates/tool-matrix/common.json`'s gitleaks entry carries `required: true` and `min_version` ≥ 8.19.0, and a stub scanner answering `version` with `8.18.0` is reported `tool-unavailable` → **mutation:** ignore `min_version` → `scan-failed` → RED. |
| **WP11 — Archive classes `script`, `document` and `state` (D1, D3 mechanics) — RE-CUT 2026-09-17** | Extend `adopt_archive_inventory` with `document` — the rows of `_adopt_document_set` (§7.2), as DATA in one function WP12b's finisher consumes — and `state` (`.claude/intake-progress.json`, `.claude/orchestrator-source.json`); match every install-set path against `git ls-files` CASE-INSENSITIVELY and disclose a case-variant collision by the operator's spelling, removing it from disk and index and installing the framework's spelling (M10, BL-242-INVENTORY-CASEFOLD); read the `git-hook` class from `_adopt_hooks_dir` (WP9d's helper, I21); build restore lines with jq's `@sh` (BL-242-RESTORE-QUOTED) and refuse names carrying a newline, carriage return or tab at the inventory; `adopt_receipt_check`, called ONCE per install-set path immediately before `cp -p` (BL-242-RECEIPT-CHECK), with the `SOIF_ADOPT_INVENTORY_SKIP_CLASS` test seam; framework-wins install — the `[ -e "$dst" ]` skip becomes archive-then-copy, and the `n_copied -eq 0` tripwire is DELETED (A1's arm 3 refuses that tree at step 0, measured at WP9b); the every-path notice and the standing warning, string-pinned (they are decisions, not phrasing); the archived-document disclosure per §7.2 — every archived document named with its archive path and the invitation to retrieve content into the new framework file (D3's reach ruling); the `pending-act-4` and `kept-by-rule` words; **the overwrite-inventory invariant I20** as one loop after the rehearsal and before the first real write (BL-242-OVERWRITE-INVENTORY): the rehearsal's planned set ∩ the paths that existed before it must be ⊆ the inventory's `originalPath`s, else BLOCK — the check that would have caught §13-V34; `CHANGELOG.md` excluded by rule (row 17); Act 2 archives colliding documents and replaces NONE of them except `PROJECT_INTAKE.md` and the `state` rows, which Act 2 writes. **Boundary: no document *writing* — WP12b's; no reference-doc copying — WP9c's (this package absorbs WP9c's colliding-reference disclosure into the `document` class).** | A fixture with a colliding `scripts/validate.sh` (exact case): after Act 2 the framework's bytes are at the path, theirs are in the archive with a MANIFEST row (`class: script`) and an `@sh`-quoted restore line, the notice names the path → **Mutation A:** restore skip-on-collision → the framework's file absent at the path → RED. **Mutation B, with its seam:** `SOIF_ADOPT_INVENTORY_SKIP_CLASS=script` on the same fixture → the run BLOCKS at BL-242-RECEIPT-CHECK naming `scripts/validate.sh`, the operator's bytes still at the path — the positive proof; then delete the `adopt_receipt_check` call line → with the seam still set the operator's file is overwritten and the run completes → RED. **Mutation C:** reduce the notice to a count → RED (path-presence assertion). **Case-variant (A8) — on a case-INSENSITIVE filesystem only; the suite probes `core.ignorecase` and SKIPS otherwise, printing why:** a fixture tracking `scripts/Validate.sh` → after Act 2 the index holds `scripts/validate.sh` and NOT `scripts/Validate.sh`, the archive row's `originalPath` is `scripts/Validate.sh`, the disclosure names the operator's spelling and says *differing only in case* → **mutation:** delete BL-242-INVENTORY-CASEFOLD → the index keeps `Validate.sh` (or both) → RED. **Quoting (A9):** a fixture with a hook named `pre commit` (a space) → the MANIFEST's restore line, run under `sh -c`, restores the file byte-identically at its mode (the wp6 `A5` pattern) → **mutation:** delete BL-242-RESTORE-QUOTED → the restore fails or touches the wrong path → RED. A hook name carrying a newline → refused at the inventory before any copy, byte-escaped in the message → **mutation:** drop the check → the MANIFEST row is split → RED. **Documents:** a fixture owning `CLAUDE.md`, `FEATURES.md`, `PROJECT_BIBLE.md` and `PRODUCT_MANIFESTO.md` → the first three archived under `document` with `pending-act-4` and STILL AT THEIR PATHS after Act 2 (Act 2 archives, only Act 4 replaces); `PRODUCT_MANIFESTO.md` archived with `removed-for-phase-0` and ABSENT from its path, the disclosure saying why; every row named with the invitation sentence → **mutation:** drop `PROJECT_BIBLE.md` from `_adopt_document_set` → its row is absent → RED — the union's proof; the bible is not an `init.sh` writer; **mutation:** leave the manifesto at its path → after WP12a's assessment `resume.sh` prints the CLASSIC prompt → RED (the same observable as WP12b's A3 pin, reached from the other side — the review's R-11). **PROJECT_INTAKE.md — §13-V34's defect:** a fixture owning `PROJECT_INTAKE.md` and `.claude/intake-progress.json` → after Act 2 both are in the archive (`document`/`replaced`, `state`/`replaced`), the disclosure names them, their MANIFEST sha256s equal the originals' → **mutation:** drop the two rows → BL-242-OVERWRITE-INVENTORY blocks the run (I20's positive proof); drop that loop as well → both files overwritten silently, §13-V34 reproduced → RED. **`kept-by-rule`:** the fixture's `CHANGELOG.md` is untouched, un-archived and absent from the MANIFEST → **mutation:** add it to the set → RED. **`--re-add`:** on class `script` warns, restores byte-identically, records the row; on a `pending-act-4` `document` row refuses — the original is still at the path, there is nothing to put back yet → **mutation:** allow it → the no-op runs and writes a `collision_re_add` row for a restore that changed nothing → RED, asserted on the row. |
| **WP12a — Act 3 and Act 4's assessment half: interview, record, verdict, intake pre-fill (D4, D6, D7, D8, D10) — RE-CUT 2026-09-17 (B1, B6, R2, #418)** | The `resume.sh` fifth branch (predicate §8.5, ordered before the intake branch and before WP12c's exemption entry) and the prompt it emits — naming the finisher command, the record's schema and its home; the interview per §5.2 — D7's five axes, the classification (non-skippable at the intake write — **which is where A7's Act-2 removal lands, so this is the package that closes the WP9→WP12a classification window**), **R2's *in production* question**, and the S1 operations block when evidence shows maturity — written by the MODEL into `.claude/adoption/assessment-record.json` (schema pinned, §8.3) with `answers` in the wizard's vocabulary (M14); **the ONE shell finisher, `adopt_act4_finish`** (B1) in a new `scripts/lib/adopt/adopt-finish.sh`, dispatched by `adopt-project.sh --act4 --root .` from the framework clone `.claude/orchestrator-source.json` names, with `_adopt_act4_order` as data (BL-242-ACT4-ORDER): `validate_record` (§8.3's refusals) → `classification` (`adopt_persist_phase1_artifacts`, A7's kept function — at last CALLED) → `prefill_intake` (`# BL-204-PREFILL-READ`'s pattern; `answers` written into `.claude/intake-progress.json` under the wizard's keys; the intake write REFUSES without a classification) → `verdict` (D8's two-halves check; `.claude/adoption/verdict.md` overwritten by its own writer on re-entry) → `documents` (a STUB in 12a that announces WP12b on the `adopt_stub_*` pattern) → `merge` (`soif_adoption_assess`, LAST — BL-242-ACT4-MERGE-LAST; refuses when an assessment block exists); the D6 rebuild exit — a `rebuild` verdict pre-fills the intake and routes to Phase 0, nothing else; **`accessibility` → `accessibility_target`** in `_scout_prefill_table` with the two-way drift check widened on the WP2 canary (M14); **A2's write order** — the merge last after the assessment outputs; the unheaded outputs (record, verdict) homed under `.claude/adoption/` with overwrite-own on re-entry; **A3: no `PRODUCT_MANIFESTO.md` from anyone in adoption.** **This package FLIPS wp9 R1** (R-DOC-10): `resume.sh` on adopted-unassessed must emit the ASSESSMENT prompt, and R1's phrase list is re-aimed at that prompt's sentences — stated here, not discovered at build. **Boundary:** no document writing — WP12b fills the `documents` stage; no exemption predicate — WP12c; the model conducts the interview and its judgment is not suite-provable (§12 item 8). | **Every proof drives `adopt_act4_finish` with a HAND-WRITTEN record on an adopted fixture — the model is never in the loop.** **Schema:** a fitness finding without `requirementRef` → refused, nothing written, no `.adoption.assessment` → **mutation:** drop that check in `validate_record` → the merge lands → RED; `adoptedAtCommit` ≠ the stamp's → refused → **mutation** → RED; `inProduction` absent → refused → **mutation** → RED; `dataClassification` outside `ADOPT_DC_TAXONOMY` → refused → **mutation** → RED. **Classification — A7's window closes here:** a valid record → `.claude/process-state.json`'s `.phase1_artifacts.data_classification` holds the value, written THROUGH `adopt_persist_phase1_artifacts` (the function with no caller at `579b0b0`; the proof pins that it is called: `grep -c adopt_persist_phase1_artifacts scripts/lib/adopt/adopt-finish.sh` ≥ 1 AND the written value) → **mutation:** re-implement the merge inline → the grep count falls to 0 → RED, the two-owners drift its comment forbids. The intake write without a classification → refused → **mutation:** default it → RED. **Order (I16):** `_adopt_act4_order` emits `validate_record classification prefill_intake verdict documents merge`; a halt injected after `verdict` (`SOIF_ADOPT_ACT4_HALT_AFTER=verdict`, the `SOIF_ADOPT_HALT_AFTER` seam's sibling) leaves NO `.adoption.assessment` and `resume.sh` re-offers the assessment prompt → **mutation:** move `merge` first → the fixture reports assessed with its intake unfilled → RED. **Resume:** on adopted-unassessed, the assessment prompt — it names the finisher command and the record path; **this flips wp9 R1, re-aimed here**; on assessed, one of the two Phase-0 entries and NEVER the classic prompt — the disjunction, §8.5, because the shipped intake template's 87 blankable cells against `resume.sh`'s `>20` threshold make a named branch go RED against a CORRECT implementation → **mutation:** break the predicate's assessment half → an assessed project re-prompts → RED; break its order → an adopted-unassessed fixture with a blank-cell intake gets the intake prompt → RED. **Verdict:** the artifact missing its `## Plain English` half, or its recommendation without a reason line → refused → **mutation** → RED. **Wizard vocabulary:** the record's `answers` land in `.claude/intake-progress.json` under keys that every one resolve in `intake-wizard.sh`'s `save_answer` set (derived in the suite by the §5.2 recipe) plus `accessibility_target` → **mutation:** write `accessibility` → the drift check → RED. **No phase write (I1):** `current_phase` is 0 after the finisher on every fixture → **mutation:** add a phase write to any stage → RED. **The strong A3 pin — have Act 4 write `PRODUCT_MANIFESTO.md` → the assessed fixture lands in the classic prompt → RED — lives in WP12b** (it needs a document writer to mutate); 12a asserts A3 by absence: no stage names the manifesto. |
| **WP12c — The `adopted-in-production` exemption (R2 — Karl, 2026-09-17; NEW): `delta.sh`, `resume.sh`, `validate.sh`** | R2's predicate in EXACTLY the three readers of the era invariant (§13-V40 prints them; the phase gate is not among them). **(1) `scripts/delta.sh`:** `# DELTA-OPEN-ERA-GUARD` gains a second conjunct — proposed DELTA-OPEN-ERA-EXEMPTION — `_delta_adopted_in_production`, reading `.claude/manifest.json` with `jq -e '.adoption.adopted == true and .adoption.assessment.inProduction == true'` (state only, §3.7's rule; absent means false); when the guard is passed BY the exemption, `cmd_open` writes `active_delta.exemption = "adopted-in-production"` into the delta record (DELTA-OPEN-EXEMPTION-RECORD) and appends `{kind: "adopted-in-production", delta_id, at, current_phase}` to `.claude/process-state.json`'s `.adoption_exemptions[]` (DELTA-OPEN-EXEMPTION-STATE) — the two records the ruling names — and prints one sentence saying which exemption opened this delta and that the retro is still owed; every other project below 4 is refused with exit 3 as today. **(2) `scripts/resume.sh`:** the exemption entry BEFORE the BL-202 branches (DELTA-RESUME-EXEMPTION, §8.5): the same predicate AND an open `active_delta` read through the one declared seam → the *resume that piece of work* prompt; no open delta → not taken, the Phase 0 entries follow; the greeting never fires below phase 4. **(3) `scripts/validate.sh`'s `# DELTA-ERA-REPORT-ONLY`:** when the open delta carries the exemption, an INFO naming it instead of *one of the two records is wrong*. **(4)** WP7's record reads `.adoption_exemptions[]`. The delta track's design (`docs/designs/2026-08-02-delta-track-v1.md` §10.1) is AMENDED by reference in the same PR: its era invariant gains the exemption clause, attributed to R2. **Boundary:** no phase gate is touched (I18); `--close`, `--retro`, the ratchet, the retro booking and every other delta command are unchanged — only `--open`'s guard and the two readers; no interview (WP12a writes `inProduction`); the module direction holds — `resume.sh` and `validate.sh` read `jq` state and the seam, never a module file (`scripts/lint-delta-boundary.sh` stays green). | Fixtures: **F1**, an ADOPTED project whose finisher recorded `inProduction: true`, at phase 0; **F2**, the same with `false`; **F3**, a SCAFFOLDED project at phase 0 with `.adoption.assessment.inProduction: true` hand-planted and `adopted` ABSENT; **F4**, a scaffolded project at phase 4 (the era's own control). **(a)** F1: `delta.sh --open --class hotfix …` exits 0, `active_delta.exemption == "adopted-in-production"`, `.adoption_exemptions[0].delta_id` names it → **mutation:** delete DELTA-OPEN-ERA-EXEMPTION → exit 3 → RED. **(b) nobody else:** F2 → exit 3; F3 → exit 3 → **mutation:** drop the `adopted == true` conjunct → F3 opens → RED; **mutation:** read `inProduction` with `// true` (absent means yes) → a fixture assessed before v2.2 (no key) opens → RED. **(c)** F4 still opens with NO exemption field → **mutation:** write the field on every open → F4 carries it → RED. **(d) records:** on F1, delete DELTA-OPEN-EXEMPTION-STATE → `.adoption_exemptions` absent → RED; delete DELTA-OPEN-EXEMPTION-RECORD → the delta record lacks `exemption` → RED. **(e) resume:** F1 with an open delta → `resume.sh` prints the *resuming a piece of post-release work* prompt naming the delta id and not the kickoff prompt → **mutation:** delete DELTA-RESUME-EXEMPTION → the kickoff prompt → RED; F1 with NO open delta → the Phase 0 entry (the kickoff, since no manifesto) and the greeting's *This product has shipped* is ABSENT → **mutation:** let the greeting fire under the exemption → RED. **(f) validate:** F1 with an open delta → no *one of the two records is wrong* line, an INFO naming the exemption → **mutation:** drop the conjunct → the warning returns → RED. **(g) I18 — the gate is untouched:** `scripts/check-phase-gate.sh` on F1 before `--open` and after produces BYTE-IDENTICAL output and the same rc (`diff` the transcripts, with any time-varying line normalised first — the OK line's `adopted: <timestamp>` is the fixture's and stable; a run-date line would make this a clock test, the review's note) → **mutation:** make any gate arm read `.adoption_exemptions` → RED. **(h) the retro survives:** on F1 the hotfix books its `hotfix_retros[]` row with `due_by` → **mutation:** skip the booking under the exemption → RED — *so incidents keep the hotfix retro and write-up* pinned, not assumed. **(i) the lint:** `scripts/lint-delta-boundary.sh` green on the amended `resume.sh` and `validate.sh` → **mutation:** source a delta lib from `resume.sh` → the lint's T1 → RED. |
| **WP12b — Act 4's document half: the D3 writing, the receipt rule, and the page revisions — RE-CUT 2026-09-17 (B1, B3)** | The `documents` stage of `_adopt_act4_order` becomes real: for each row of `_adopt_document_set` (§7.2) with a WP12b writer, the finisher writes the document — `CLAUDE.md` through `soif_render_claude_md` and the model's adaptation from the record; `FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md` from their templates and the record (D3's reach, ruled 2026-08-31); `PROJECT_BIBLE.md`; `docs/INDEX.md`, `docs/IDENTIFIERS.md`, `docs/archive/README.md` — each with v1 §8.6's provenance header, each preceded by `adopt_receipt_check` (WP11's helper) with **A2's exemption bound to `adoptedAtCommit`** and the re-archive before rewrite (BL-242-RECEIPT-EXEMPT-A2); each `document` MANIFEST row rewritten `pending-act-4` → `replaced` after its write (BL-242-DISPO-REPLACED); the retrieve-from-archive invitation repeated at each write (§7.2); the `merge` stage still LAST — after the documents, which is A2's full statement and is only expressible once documents exist. `PRODUCT_MANIFESTO.md` is NOT written (A3). The v2 revision of `docs/adoption.md` (minus its chooser sections — WP9's, §4.2) and `docs/scout.md`; `docs/adoption.md`'s *message gates are live* transcript becomes the derived form WP9d prints. The `_adopt_document_set` drift check re-run. **Boundary:** no interview, no record schema, no verdict content — WP12a's; `CHANGELOG.md` is NOT in D3's ruled set and this package does not silently adopt it (row 17). | **A2, on the finisher with a hand-written record:** a mid-documents halt (`SOIF_ADOPT_ACT4_HALT_AFTER=documents:FEATURES.md`, per document) leaves NO `.adoption.assessment`, `resume.sh` re-offers the assessment, and re-entry rewrites its own provenance-headed `FEATURES.md` (the same `adoptedAtCommit` in the header) with a SECOND archive copy taken first → **mutation:** write the merge first → the fixture reports finished with documents missing → RED; **mutation:** drop the re-archive → the second copy is absent → RED. A document carrying an Act-4 header from a DIFFERENT adoption (a mismatched `adoptedAtCommit`) → refused, not exempted → **mutation:** key the exemption on header presence → overwritten with no archive row → RED. **Mutation:** drop §7.2's exemption → re-entry refuses its own file → RED. An Act 4 write to a pre-existing unarchived path (`SOIF_ADOPT_INVENTORY_SKIP_CLASS=document` at Act 2, then the finisher) → refused → **mutation:** drop `adopt_receipt_check`'s call in the finisher → overwritten → RED. **The A3 pin lives HERE, on an INTAKE-COMPLETE fixture — no blank cells:** have the `documents` stage write `PRODUCT_MANIFESTO.md` → the assessed fixture lands in the classic prompt and the Phase-0 entry is skipped → RED. **Disposition word:** after the stage every `document` row reads `replaced` except `PRODUCT_MANIFESTO.md`'s, which reads `removed-for-phase-0` from Act 2 and is never rewritten by the finisher → **mutation:** rewrite every row → RED; rewrite none → RED. **Invitation:** each new file's write prints the sentence naming the archived original → **mutation:** drop it → RED. **Drift:** the set the finisher iterates IS `_adopt_document_set`'s rows with a writer → **mutation:** iterate a local list → WP11's drift check → RED. |
| **WP7 (re-cut) — Adoption Record + audit rows + CI carve-out + provenance lint + the commit-time hook** | v1-WP7's deliverables with §8.6's content re-cut: the record (eight clauses, record lint), `adoption_event` across all five enum surfaces with a fixture that contains it, the CI audit and keep-or-retire record, the provenance-header lint, and — **last, as Karl already decided** — the fallback pre-commit hook install, now that the artifacts it reads exist. **Re-cut 2026-09-17 in content only:** the record adds the in-production declaration and every exemption used under it (from `.adoption_exemptions[]` — author-proposed content, not the ruling's words; the review's R-15), the acknowledgements by kind (§6.3), the hooks placement fact and the rehearsal's measurements (§8.6); the eight clauses are unchanged. And `adopt_stub_hooks`'s stale owner string (§1.2) is corrected HERE, by the package that decides the fallback hook's owner. | v1-WP7's re-aimed proofs carry: the record lint is the mutation target for clause 5; the joint-violation fixture is the labelled defense-in-depth proof. The hook installed on a completed fixture admits a compliant commit and blocks a non-compliant one **by exit code**; installed-before-artifacts is unreachable by construction (it is the last step of the last package) — assert the reachable half. **(v2.2)** On a WP12c F1 fixture after `--open`, the record lists the exemption with its delta id → **mutation:** drop the read of `.adoption_exemptions[]` → RED; and the record's eight clauses still hold with the new content (the lint is the mutation target, as before) |

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
  re-opens the hole D2 closes. **And, since 2026-09-17, trusting it even when it says `scanned`** —
  rejected (§6.2b): the stop reads a scan Act 2 ran itself.
- **Relocating the hook INTO a configured `core.hooksPath`** — rejected by R1 (Karl, 2026-09-17),
  for the reason `# BL-209-HOOKSPATH-SAME-DIR`'s installer already gives: a hooksPath is often
  shared across repositories or tracked in the project, and writing a framework gate into it is a
  write into something the operator did not hand over.
- **Backfilling `current_phase: 4` for an in-production adoptee** — rejected: D10 says every
  adopted project starts from the beginning, and R2 grants the delta track's door, not the rung.
- **Scanning history in place with a "no config" flag** — rejected because no such flag exists
  (measured, §13-V35): the no-checkout copy is the only mechanism that defeats a repo-local
  `.gitleaksignore`.
- **Finishing the adoption window silently on re-run** — rejected (§8.4): the operator's own hook
  refused something, and finishing is an act they should take knowingly; `--finish` is explicit.
- **A sparse rehearsal copy of only the paths the writers read** — rejected (§8.2a): it re-creates
  the maintained list `## BL-225:` chose the copy to avoid.
- **Reading `CHANGELOG.md` into D3's reach** — rejected as an inference recorded as a ruling; it is
  KEPT by this author's rule until Karl says otherwise (§7.2, row 17).

---

## §12 — Honest residuals

**Deferred by decision (named, scoped, not designed here):**

1. **`## BL-225:` was a precondition, not a package — and both halves are built** (staging PR #368;
   before-any-write PR #410, 2026-09-14, §8.2a). It stays Open for two residuals recorded there
   and named in item 17.
2. **`## BL-226:`** ("moved" claimed where nothing moved) — WP11's notice rewrite touches the same
   strings and should close it in passing; recorded so it is checked rather than assumed.
3. **The init-parity audit is DELIVERED at §8.7a, and it is worse news than this entry expected.**
   **34 rows** (33 until `## BL-284:`'s finding added row 32 on 2026-09-16; 32 until WP9b added row 22a); the adoption half measured by execution — re-measured 2026-09-16, §13-V27 — the `init.sh` half read from source
   and acknowledged partial. **Fourteen rows are UNOWNED, one UNSPECIFIED, two PARTIAL**, and the
   packages after WP9 close none of the fourteen. Three of them are load-bearing for claims
   this document makes elsewhere: `docs/reference/*` (row 18) means **D8 binds
   `messaging-standard.md` inside a project that never receives it**, and rows 19–21
   (`.claude/settings.json`, the `mcpServers.qdrant` declaration, the vendored skills) mean an
   adopted project's *sessions* are a materially weaker place than a scaffolded project's — the
   `## BL-233:` accumulation gate among them derives NOT REQUIRED and switches off silently. None
   is WP9's to fix and none is designed here; the denominator is now known, which is what §8.7
   asked for and all it asked for. *(Amended 2026-09-17: rows 18–21 are OWNED by WP9c, row 17 is
   KEPT by rule, and row 33 — the CDF install — is added UNOWNED; read the table.)*
4. **v1's residuals that survive unchanged**: `init.sh --allow-existing-dir` remains a loaded gun;
   `bypass_audit_append` still validates only object-ness; the two dead enum pins predate
   `adoption_event`; archiving a git hook still promotes an untracked file into version control,
   mitigated not proven by the pre-staging scan.

4a. **Re-adoption, the scaffolded tree, and interrupted runs are REFUSED now; recovery is not
    designed** (A1, A2). A1 refuses on three arms and names the prior archive; it does not roll the
    tree back. `## BL-225:`'s before-any-write half is built (§8.2a), so a REFUSED Act 2 leaves nothing; an
    Act 2 that CRASHES inside the real write phase still leaves files on disk — the archive's
    restore lines are the recovery path, and they are manual. **Three windows were recorded here as A1 does not
    close, and the WP9b build CLOSED TWO OF THEM — the entry is corrected rather than left to
    read as open, which is how a residual list becomes fiction.** (i) *an interrupted run that
    died after the install on a collision-free adoptee leaves no archive and no state, so no arm
    fires* — **CLOSED** by arm 3's third signal (`# BL-242-PREFLIGHT-ARM3-INSTALLED`, §8.2 step 0):
    at-least-half of the install set present refuses at step 0, measured on a real
    `SOIF_ADOPT_HALT_AFTER=install` tree at 68/68 with the operator never re-asked. The downstream
    concern it named survives and is WP11's: an archive taken on such a tree would misattribute the
    framework's own installed files as the operator's, and the systematic mitigation is for WP11's
    inventory to sha-compare colliding content against the install source and label byte-identical
    entries honestly rather than as `script`-theirs. (ii) *an adopted tree whose `.claude/` was
    deleted defeats all three arms* — **CLOSED**, and by two different arms depending on how far
    the deletion went: a working-copy-only deletion is caught by arm 1's committed witness
    (`# BL-242-PREFLIGHT-WITNESS2`), and a deletion that was itself committed is caught by the same
    third signal, since the framework's scripts are still on disk. Both measured. (iii) **no
    deliberate full re-adoption route is blessed** — **STILL OPEN**: arm 2 makes deleting the
    archive its price, which destroys the record the archive exists to keep.

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
8. **Model-judgment quality is not suite-provable.** WP12a/b's proofs pin every shell-checkable edge
   — predicates, refusals, record shapes, the verdict scaffold. Whether the interview is *well
   conducted* and the findings *sound* is an evaluation question (UAT-shaped), and pretending a
   mutation proof covers it would be a test that cannot fail.

**Assumptions that would falsify parts of this design if wrong:**

9. **That the CDF manifest writer stays missing-file-gated** — inherited verbatim from v1 §12-12;
   the four-act split adds a second block (`.adoption.assessment`) to the same blast radius.
10. **That `templates/tool-matrix/` keeps `gitleaks` `"required": true`.** §6.2's "D2 asks nothing
    new" argument rests on it; if the matrix ever demotes it, Act 2 must pin its own requirement
    rather than inherit the demotion. A one-line check in WP10's suite pins the matrix entry.
    *(Re-verified 2026-09-16: `"required": true` at the `gitleaks` entry, §13-V19; the WP10a suite
    drives the resolver through the `SOIF_ADOPT_RESOLVER` seam and does not read the shipped
    matrix, so the pin is still WP10b's.)* *(Widened 2026-09-16 — `## BL-289:`: the pin must also
    assert the floor is ≥ 8.19.0 and that a too-old scanner is reported as `tool-unavailable` — by
    the resolver adoption calls enforcing `min_version`, or by Scout probing the subcommand it is
    about to run (`## BL-289:`'s two halves; whichever lands first owns it); at `7b88c2e` the floor is 8.18.0 and nothing on adoption's
    path reads it.)*
11. ~~**That `## BL-242:` merges.**~~ — **MERGED**, and on `main` at every v2.1 measurement (§0.4).
    Kept struck: §0.4's branch topology caveat described a real fork, and this document's
    §-citations into the entry resolve on the working tree today.

**NOTHING THIS DESIGN NEEDS IS AWAITING KARL.** It was three on 2026-08-28; Karl ruled all three
on 2026-08-31, item 15 was raised the same day and ruled the same day; item 16 was raised on
2026-09-15, during this amendment's drafting, and ruled on 2026-09-16 — the set was one for a
single day; the architect's two questions of 2026-09-16 were ruled on 2026-09-17 (R1, R2 — §0.1a).
Two things are Karl's and NOT this design's: `## BL-274:`'s governance taxonomy (item 27, a known
limit) and whether an adoptee receives the CDF (item 29, a gap); neither blocks a package. All five are kept below, struck, rather than deleted — a question that was answered is
part of this document's record, and removing it would hide that the document once got it wrong.
**Two of the five were ruled against this author's stated recommendation, and a third — item 16 —
stricter than its drafted one on the `personal` arm; all are marked as such**, because a design
that quietly absorbs the answers it did not predict cannot be audited for the quality of its
predictions:

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

16. ~~**Which tier row `scanned-partial` takes**~~ (§6.1a) — **RULED (Karl, 2026-09-16): *"go with
    the split."*** At `organizational` a `scanned-partial` result stops with no escape and the
    refusal prints the unshallow remedy; at `personal` the operator may acknowledge and continue,
    the acknowledgement RECORDED in §6.3's shape (named accepting person, reason, date; the scope and commit count are author-proposed additions, §0.1) and refused if it
    cannot be recorded; the findings the partial scan produced are printed either way and the
    partial scope is stated in those words (the redaction and the wording are author-proposed, §0.1).
    Raised on 2026-09-15 while this amendment was drafted,
    because `## BL-288:` coined the status on 2026-09-12 and no earlier ruling could have named it;
    ruled the next day. The drafted recommendation had the split with the personal arm as a
    warning, `scan-failed`'s rung; the ruling put it at `tool-unavailable`'s — a recorded
    acknowledgement — and §6.1a records the ruling and not the draft. **Nothing of it is built;
    both arms are WP10b's** (§13-V28).

**Recorded since v2.0 (2026-09-16), not designed here:**

17. **`## BL-225:`'s two residuals**, both recorded on the entry: an adoptee whose `.claude` is a
    symlink to an absolute path outside the repository has its state files written *there* while
    the refusal correctly reports the repository untouched (pre-existing — it predates the fix);
    and the unbounded-write flag is path-list only, so an installer recipe that MODIFIES an adoptee
    file in place rather than creating one does not raise it (§8.2a).
18. **`## BL-270:` and `## BL-271:`** — a project adopted before `## BL-268:`'s fix carries
    `mode: "organizational"`, a word every host driver now refuses, until
    `upgrade-project.sh --backfill-only` migrates it (`# BL-270-MODE-VOCABULARY-BACKFILL`, on
    `main` at `0dc57fc`) — *and that route reports success when it is not used correctly: run from a
    directory with no project above it, the backfill prints `[FAIL] cdf-refresh: project_root does
    not exist:` and still exits 0 (measured 2026-09-17 on bash 3.2.57; an outside contributor filed it
    the same day and the independent review reproduced it, correcting this clause). Inside a project
    it migrates as described. The operator IS told — two diagnostics print, and a `.claude/` directory
    is created in the projectless cwd — and the exit code says success anyway, which is the defect: a
    route this design points adopted projects at reports success over work it did not do*; and `upgrade-project.sh --deployment organizational` never writes `.mode`
    at all, so a *scaffolded* project upgraded to organizational is verified against the personal
    bar (§8.3b). Neither is adoption's defect; an adoptee receives every script involved.
19. **`## BL-273:`** — the remote-URL-to-host inference exists at four shipped sites and
    `scripts/lib/host.sh` carries none of it; every one of the four ships to the adoptee. Entry
    only; no fix proposed there or here.
20. **`## BL-284:`** — §8.7a row 32 (`.claude/tool-preferences.json`, UNOWNED), and with it the
    re-classification of row 7 to PARTIAL: the adoptee's gate keys its tools-needed block on the
    file adoption does not write, which is the only reason the matrix adoption also does not ship
    has never been missed. Its second arm — `fix_superpowers` calling a `claude plugin add` verb
    that does not exist (`# BL-284-PLUGIN-VERB`) — is `verify-install.sh`'s and not adoption's,
    named because the adoptee receives the script.
21. **`## BL-242:`'s symlink-follow residual** (recorded on the entry 2026-09-01; not carried here
    until the 2026-09-16 sweep): `adopt_write_file` is `cat > "$root/$rel"`, so an adoptee whose
    `APPROVAL_LOG.md` — or any other state file adoption writes — is a symlink to a file OUTSIDE the
    repository has that target overwritten at rc 0 while the disclosure names only the in-repo
    path: a write outside the repository that the plain-English overview's *"nothing is moved
    silently"* does not cover. WP11-adjacent; item 17 records the sibling `.claude`-symlink case.
22. **`## BL-242:`'s re-run residual** (found 2026-09-16 by PR #415's review): the
    `# BL-242-RESOLVER-NO-EXEC` arm tells the operator *"Then run adoption again to scan this
    project's history"* after a run that then COMPLETES and stamps, and `# BL-242-PREFLIGHT-ARM1`
    refuses the re-run it advised. Which surface owns the sentence is WP10b's call — its scope cell
    names it.

**Recorded 2026-09-17 (v2.2) — measured on `main` at `579b0b0`, designed in §10, NOT fixed here;
each needs a backlog number, which is the supervisor's to mint:**

23. **Act 2 overwrites an adoptee's own tracked `PROJECT_INTAKE.md` and `.claude/intake-progress.json`
    at rc 0 with no archive directory, no MANIFEST row and no transcript sentence** (§13-V34). The
    APPROVAL_LOG.md class WP9b closed, one file over; neither path is in `adopt_archive_inventory`.
    WP11's `document` and `state` classes and the I20 loop close it. *Defect — `## BL-292:`.*
24. **A case-variant collision is reported under the framework's spelling** — `yours, kept:
    scripts/validate.sh` for an adoptee whose index holds `scripts/Validate.sh` (§13-V34, macOS,
    `core.ignorecase = true`). Harmless today (skip-on-collision); under framework-wins it would leave
    the framework's bytes under the operator's name. WP11 (A8). *Defect, latent — `## BL-293:`.*
25. **Under a configured `core.hooksPath`, adoption writes `.git/hooks/commit-msg`, prints that the
    message gates are live, and git runs no hook on the next commit** (§13-V32, `GIT_TRACE`).
    R1/WP9d. *Defect — `## BL-290:`.* The two sibling shapes, executed by the review and re-run here:
    a SUB-DIRECTORY root is refused today by the rehearsal, rc 1, after every question, nothing
    written (§13-V32b); a LINKED WORKTREE root is COMMITTED and then blocked at the hook write,
    hookless, rc 1 (§13-V32c, item 32).
26. **`## BL-277:` is a DEPENDENCY of WP9c** — DECIDED 2026-09-17 (Karl): that entry's option 3 —
    keep scanning output, let only Stop-event matches raise the sentinel, PostToolUse rows carry an
    actor other than `claude` with the sentinel gated on authorship; the contributor who filed it (#385)
    is invited to build it, adversarial review before merge. Greenfield registers
    `scripts/hooks/bypass-detector.sh` on PostToolUse, which that entry measures as a day-one blocker
    on reading the shipped `CLAUDE.md`; WP9c ships the Stop arm now and the PostToolUse arm only when
    that fix lands. Nothing here builds it.
27. **`## BL-274:` — the single-technical-authority organizational adoptee — is a KNOWN LIMIT** (§2.1):
    `validate_approval_fields`'s self-approval control fires on every row the approver commits,
    `## BL-275:`'s half two is Karl's, and the contributor's attestation mechanism exists on a fork
    (`fix/bl274`, not fetched here — §13-U(v2.2)). R2's exemption reads none of it (§13-V40) and
    this design depends on nothing there.
28. **#418 — the A7 rows' keys and `## BL-282:`'s amend route.** Designed in §5.2 (M14): the rename
    `accessibility` → `accessibility_target` and the two-way drift check are WP12a's. DECIDED
    2026-09-17 (Karl): `## BL-282:`'s option 2 — a generic setter on the wizard — widened to accept any
    key already present in the progress file's `answers`, adoption-recorded keys included (#418's
    option 3), so projects adopted before the rename can be amended; the contributor is invited to PR
    the wizard half with its suite, adversarial review before merge. The issue's *"pnmp test:unit"* is the adopter's own
    `package.json` — `git grep -n pnmp` over this framework's code and shipped pages returns nothing,
    rc 1 (§13-V37; scoped, because the whole-tree form matches this document's own sentences) — and
    Scout transcribed it faithfully: a scan-derived value is the project's, confirmed by the operator, and
    a typo in it is theirs to change through the same confirmation.
29. **The CDF install is an `init.sh` effect nobody owns for adoptees** (§8.7a row 33; §13-V38):
    greenfield's manifest base shape, every CDF rule and hook, and the condition under which the
    Solo hook roster is even registered come from `~/.claude-dev-framework/scripts/init.sh`, which
    adoption never runs. Whether an adoptee should receive it — a network clone into `$HOME`,
    non-fatal in `init.sh` when it fails — **was a question for Karl and is RULED: 2026-09-18, YES,
    an adoptee receives it on the same terms a scaffolded project does.** The ruling settles whether;
    it settles nothing about how, and WP9c owns the how: this is a NETWORK CLONE into `$HOME`, the
    one thing adoption would write outside the repository it is adopting, so §8.2's rehearsal
    (`# BL-225-PREWRITE-CALL`, which copies the ADOPTEE) says nothing about it and the design must
    state what a failure does — `init.sh` carries on. **The roster half is NOT ruled — it was not asked.**
    §10-WP9c's author-proposed answer stands and may be attacked: the roster registers
    UNCONDITIONALLY, because one that registers only inside `if [ "$framework_valid" = true ]` is a
    gate a network failure switches off, which is `## BL-147:`'s class. *(A first draft called it
    "ruled with it"; §8.3c's ruled column is defined as what may NOT be attacked, so that would have
    removed a live design position from review to buy nothing — the independent review caught it.)* *Gap — `## BL-296:`, ruled and not designed.*
30. **The adoption window** — a stamped, staged, uncommitted adoptee whose re-run says *already
    adopted — run resume.sh* (§13-V33). A3/WP9d. *Defect — `## BL-291:`.*
34. **Item (6)'s `python3` disclosure is specified and NOT BUILT** (2026-09-18). Every other half
    of that item shipped — the identity precheck, the hash-tool guard, the conditional write test,
    the shape rules. This one names no defect, cites no entry and states no failure mode, so it was
    left rather than invented: `git grep -n python3 -- scripts/lib/adopt/ scripts/adopt-project.sh`
    returns one pre-existing hit in `adopt-archive.sh` and nothing of WP9d's. Whoever wants it
    should say what it discloses and why. *Gap, this design's own.*
31. **Three git version floors are stated and not measured** (§8.1): `--is-shallow-repository`
    (≥ 2.15, with Scout's file fallback), `--path-format=absolute` (≥ 2.31, with the `pwd -P`
    fallback), `git clone --shared --no-checkout` from a shallow source (measured on 2.54 only). All
    are in §13-U(v2.2).
32. **A linked-worktree root today: COMMITTED, hookless, and with NO ROUTE** (§13-V32c, executed by
    the review, re-run here): the adoption commit lands in the worktree, `mkdir -p …/.git/hooks` fails
    on the gitfile, the run ends `[BLOCKED] could not create …/.git/hooks` / *The adoption commit HAD
    already landed*, and no hook exists in the worktree or the main repository. It is not the window
    (HEAD moved), so `--finish` refuses it as landed; R1 stops new adoptees from reaching it, and a
    project adopted this way before WP9d has no framework route — the recovery is by hand
    (`scripts/verify-install.sh --auto-fix` from the main working tree, or the hook installed per
    `scripts/install-filesystem-gates.sh`'s recipe). Recorded, not designed. *Residual — `## BL-290:`.*
33. ~~**The hooks-directory shapes the WP9d precheck still admits, and where its siblings refuse
    them.**~~ **STRUCK — RULED by Karl, 2026-09-17, hours after it was filed: a symlinked hooks path
    is REFUSED at step 0 (R1's extension, §0.1a), and the regular-file shape takes the same refusal
    as author-proposed M16. §2.1 carries both rows, §8.1 the precondition, §10-WP9d the four
    mutations. What follows is the finding as filed, kept because the measurement is the reason the
    ruling exists.** Measured by the independent review of 2026-09-17, on the CORRECTED conditional. (a) A
    **dangling** `.git/hooks` symlink: `[ -d ]` is false, so the parent arm is taken, `[ -w .git ]`
    passes, and `adopt_install_hooks`'s `mkdir -p` then fails — the post-commit failure the precheck
    exists to move to step 0, surviving the fix. (b) `.git/hooks` present as a **regular file**: same
    shape, `mkdir: File exists`. (c) A symlink to a **writable directory outside the repository**:
    step 0 passes, the write SUCCEEDS there, and the derived *live* sentence prints truthfully because
    the re-resolution follows the same link — so §8.1's clause *"the derived live sentence covers the
    residue"* does not hold for this one. **Both siblings refuse (c) by policy and this design does
    not:** `scripts/verify-install.sh`'s BL-145 stanza names `ln -s ~/.githooks .git/hooks` as *"the
    classic"* case and refuses to repair it, and `scripts/install-filesystem-gates.sh` refuses a
    configured hooksPath for the same stated reason. The word *symlink* appears nowhere in this
    document *(false when filed, and the independent review measured it: nine other uses on `main`,
    among them §2.1's own `.claude` row and item 21. What was absent was any use about the HOOKS
    directory — which this entry's ruling supplies.)*. `preflight_target_writable` shares (a), so the
    write test alone is a class gap rather than WP9d's alone; the SHAPE rules above it are what close
    it here. *Was: defect, latent, WP9d-adjacent. Now: ruled, and WP9d's to build.*

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
(`min_version: "8.18.0"` — below the 8.19.0 that introduced the `git`/`dir` subcommands Scout runs,
and unenforced by `resolve-tools.sh` — `## BL-289:`; install recipes for `darwin_brew`, `linux_apt`, `linux_dnf`,
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

### §13 — v2.1 addendum: commands actually run for the 2026-09-16 reconciliation

Executed on **2026-09-16** against tree **`01b66e3`** (= `origin/main`, checked out on
`docs/brownfield-v2.1-reconcile`), working tree `/Users/karl/Documents/Claude Projects/solo-orchestrator`,
darwin host with `gitleaks` at `/opt/homebrew/bin/gitleaks`. A first attempt on 2026-09-15 measured
`c7071b2`; the two trees differ in one file (`git diff --stat c7071b2..HEAD` → `solo-orchestrator-backlog.md`
only, 44 insertions and 4 deletions), and every measurement below was re-taken on the 16th rather
than carried over. Output trimmed for length, never paraphrased. Re-run them; do not quote them.

**V17 — D1–D10 are byte-identical between the last 2026-08-31 commit and HEAD.** The claim §0.3's
v2.1 entry is allowed to make only if this returns nothing.
```
$ git rev-parse --short HEAD
01b66e3
$ git log -1 --until='2026-08-31 23:59:59' --format='%h %ad %s' --date=iso -- solo-orchestrator-backlog.md
f73dfca 2026-08-31 23:32:44 -0600 docs(bl-242): two claims the branch made about its own tree, refuted by that tree
$ git merge-base --is-ancestor f73dfca HEAD && echo ancestor
ancestor
$ ex() { awk '/^## BL-242:/{f=1} f' | awk 'NR==1{print; next} /^## BL-[0-9]+:/{exit} {print}'; }
$ git show "f73dfca:solo-orchestrator-backlog.md" | ex > "$S/bl242-0831.md"     # 875 lines
$ ex < solo-orchestrator-backlog.md                  > "$S/bl242-01b66e3.md"  # 1043 lines
$ grep -n '^### THE THREE UNOWNED\|^### THE SHAPE OF ADOPTION\|^### Consequences' "$S/bl242-0831.md" "$S/bl242-01b66e3.md" | sed "s#$S/##"
bl242-0831.md:190:### THE THREE UNOWNED CAPABILITIES — DECIDED (Karl, 2026-08-23; D2 refined 2026-08-25)
bl242-0831.md:425:### THE SHAPE OF ADOPTION ITSELF — DECIDED (Karl, 2026-08-23)
bl242-0831.md:668:### Consequences for the unbuilt work packages
bl242-01b66e3.md:190:### THE THREE UNOWNED CAPABILITIES — DECIDED (Karl, 2026-08-23; D2 refined 2026-08-25)
bl242-01b66e3.md:425:### THE SHAPE OF ADOPTION ITSELF — DECIDED (Karl, 2026-08-23)
bl242-01b66e3.md:668:### Consequences for the unbuilt work packages
$ diff <(sed -n '190,667p' "$S/bl242-0831.md") <(sed -n '190,667p' "$S/bl242-01b66e3.md"); echo rc=$?
rc=0
```
*(Re-run on `7b88c2e` by the 2026-09-16 sweep, anchored on the headers rather than the line
numbers: the span at `01b66e3` is still identical to `f73dfca`; at `7b88c2e` it differs by exactly
the twelve-line `D2 AMENDED 2026-09-16` paragraph PR #415 added. The line numbers above are
`01b66e3`'s — at `7b88c2e` the three headers sit at 193 / 440 / 683, so `sed -n '190,667p'` now
cuts across two window artifacts. Anchor on the headers.)*

The whole-entry diff (`diff -u … | grep '^[-+]'`) touches five places, none inside those lines: the
suite count (*Eight suites* → *Nine suites*), two appended residual sections (the resolver's
URL-in-`auto_install` bucket, found at WP10a's review; the symlink-following write, found at WP9b's),
the appended *WP9b's build* section, and two corrections inside *WP9's build* (the mechanism
sentence; 76/eight/32 → 77/nine/33). Read the hunks; do not count them. **A trap in this recipe:**
run it under `bash`. In `zsh`, `$LAST:solo-orchestrator-backlog.md` parses `:s` as a history
modifier and the first extract silently comes out EMPTY — the diff then "passes" against nothing.
Brace the variable (`${LAST}:…`) or use bash.

**V18 — what landed on the adoption surface after the status row was last measured, and which PR
carried each commit.**
```
$ git log 45a749b..HEAD --format='%h %cs %s' -- scripts/lib/adopt scripts/lib/scout scripts/adopt-project.sh
22b034d 2026-09-15 chore(bl-288): BL-264 → BL-288 — the number was taken on main before this landed
35a222a 2026-09-15 fix(scout): correct the remedy so it actually widens the refspec
2a8fafb 2026-09-15 fix(scout): report a shallow clone as a partial secrets scan
eba7291 2026-09-15 fix(host-drivers): refuse an unknown mode in host_verify_protection
2613937 2026-09-13 fix(bl-225): the resolver gate had no test any lane could fail — same hole, new code
bafe463 2026-09-13 fix(bl-225): the derived clear was untested on CI and could still over-claim
729c77e 2026-09-13 fix(bl-225): the suite was green on macOS and red on Linux — four corrections
f879621 2026-09-12 fix(bl-225): the oracle was one question and needed two — pre-PR review, block cleared
8356317 2026-09-12 fix(bl-225): rehearse the write phase on a copy and refuse before the first write
269ee02 2026-09-08 fix(bl-253): adoption writes poc_mode null for production, as init.sh does
a8151f7 2026-09-07 fix(bl-251): a scanner already on PATH must not cost a resolver subprocess
4009790 2026-09-02 feat(bl-242): WP10a — the tool matrix ships a URL where a command is expected
$ git log 45a749b..HEAD --format=%h -- scripts/lib/adopt scripts/lib/scout scripts/adopt-project.sh | wc -l
12
$ git log f73dfca..HEAD --format=%h -- scripts/lib/adopt scripts/lib/scout scripts/adopt-project.sh | wc -l
17          # + 45a749b (WP9b) and four 2026-09-01 fix(bl-242) commits already in the 2026-09-01 passes
$ git log --since=2026-09-01 --format=%h -- scripts/lib/adopt scripts/lib/scout scripts/adopt-project.sh | wc -l
15          # at 07:30 local; the 2026-09-15 attempt got 13 at 21:00 — a bare date takes the current time of day
$ git log --since='2026-09-01T00:00:00' --format=%h -- scripts/lib/adopt scripts/lib/scout scripts/adopt-project.sh | wc -l
17
$ for c in 45a749b 4009790 a8151f7 269ee02 8356317 2613937 eba7291 2a8fafb 22b034d; do
    printf '%s -> ' "$c"; git log --merges --ancestry-path --format='%h %s' "$c..HEAD" | tail -1 | cut -c1-110; done
45a749b -> 24dc321 Merge pull request #372 from kraulerson/feat/bl242-wp9b-preflight-approval
4009790 -> 7df3669 Merge pull request #373 from kraulerson/feat/bl242-wp10a-tool-resolution
a8151f7 -> 028d70e Merge pull request #375 from kraulerson/fix/bl251-resolver-fast-path
269ee02 -> d4e1466 Merge pull request #377 from kraulerson/fix/bl253-adoption-poc-mode-parity
8356317 -> ed85024 Merge pull request #410 from kraulerson/fix/bl225-prewrite-preflight
2613937 -> ed85024 Merge pull request #410 from kraulerson/fix/bl225-prewrite-preflight
eba7291 -> c7071b2 Merge pull request #412 from kraulerson/asb/contributions-2026-09-15
2a8fafb -> c7071b2 Merge pull request #412 from kraulerson/asb/contributions-2026-09-15
22b034d -> c7071b2 Merge pull request #412 from kraulerson/asb/contributions-2026-09-15
```
Every commit above is an ancestor of HEAD (`git merge-base --is-ancestor`). The `%cs` column is the
COMMITTER date: `eba7291`, `2a8fafb` and `35a222a` were authored 2026-09-12/13 and rebased onto
`main` on 2026-09-15 inside PR #412, which is also why the `## BL-268:` and `## BL-288:` entries'
status lines still describe unpushed branches (§13-U(v2.1)). WP10a's merge `7df3669` is dated
2026-09-04 — the day the status row went stale.

**V19 — the status-row derivations, re-run.**
```
$ for f in scripts/adopt-project.sh scripts/lib/adopt/*.sh; do            # (1) §1.2's recipe
    case "$f" in *adopt-stubs.sh) continue;; esac
    sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$f"
  done | grep -ohE '\badopt_stub_[a-z_]+' | sort -u
adopt_stub_adoption_record
adopt_stub_assessment
adopt_stub_framework_script_collisions
adopt_stub_hooks
adopt_stub_project_docs
adopt_stub_provenance_headers
adopt_stub_secrets_disposition            # | wc -l -> 7
$ ls scripts/lib/adopt/                                                    # (2)
adopt-archive.sh adopt-core.sh adopt-evidence.sh adopt-intake.sh adopt-state.sh adopt-stubs.sh adopt-test-debt.sh adopt-tools.sh
$ git grep -l 'built out and needs' -- .                                   # (2) a FRAGMENT of Karl's chooser sentence; the verbatim sentence is in TWO of these (v1 + the WP9 suite, C2's allowlist)
docs/designs/2026-08-02-brownfield-adoption-v1.md
docs/designs/2026-08-23-brownfield-adoption-v2.md
solo-orchestrator-backlog.md
tests/test-brownfield-wp9-act-boundaries.sh
$ grep -c 'resolve-tools' scripts/adopt-project.sh scripts/lib/adopt/*.sh  # (3) — RETIRED, see below
scripts/lib/adopt/adopt-core.sh:1        # a COMMENT
scripts/lib/adopt/adopt-tools.sh:1       # the path _adopt_resolver_path prints — EXECUTED
                                         # (all other files: 0)
$ grep -c 'adopt_resolve_tools "$root" "$report"' scripts/lib/adopt/adopt-state.sh   # (3'), the replacement
1                                        # … || return 1   # BL-242-RESOLVER-CALL
$ grep -c 'adopt' scripts/resume.sh                                        # (4)
0
$ grep -on 'BL-242-PREFLIGHT-ARM[A-Z0-9-]*' scripts/lib/adopt/adopt-state.sh          # (5)
239:BL-242-PREFLIGHT-ARM1
240:BL-242-PREFLIGHT-ARM2
241:BL-242-PREFLIGHT-ARM3
512:BL-242-PREFLIGHT-ARM3-INSTALLED
$ grep -n -A2 '^_adopt_state_order()' scripts/lib/adopt/adopt-state.sh    # (6)
  printf '%s\n' approval_log   # BL-242-APPROVAL-LOG-FIRST
  printf '%s\n' phase_state intake manifest   # BF-ADOPT-STATE-ORDER
$ grep -c 'BL-225-PREWRITE-CALL\|BL-225-WRITE-PHASE-REAL' scripts/lib/adopt/adopt-state.sh   # (7)
2
$ grep -n '_adopt_write_phase' scripts/lib/adopt/*.sh scripts/adopt-project.sh | cut -c1-140
scripts/lib/adopt/adopt-state.sh:1060:# `_adopt_write_phase` is the ONLY place the adoptee's files are written, and it
scripts/lib/adopt/adopt-state.sh:1069:_adopt_write_phase() {
scripts/lib/adopt/adopt-state.sh:1169:  _adopt_write_phase "$copy" "$work" "$report" >/dev/null 2>"${SOIF_REHEARSAL_ERR:-/dev/null}" || rc=$
scripts/lib/adopt/adopt-state.sh:1385:  _adopt_write_phase "$root" "$ADOPT_WORK" "$report" || return 1   # BL-225-WRITE-PHASE-REAL
                                         # a comment, the definition, the rehearsal call, the real call: two callers
$ grep -n 'schemaVersion' scripts/lib/scout/scout-report.sh              # (8)
58:  printf '  "schemaVersion": 2,\n'
$ grep -n '^ADOPT_POC_MODE=' scripts/lib/adopt/adopt-state.sh            # (9)
710:ADOPT_POC_MODE=""   # BL-253-POC-MODE
$ grep -rc 'BL-268-MODE-VOCABULARY' scripts/ init.sh | grep -v ':0'      # (10)
scripts/host-drivers/github.sh:1
scripts/host-drivers/bitbucket.sh:1
scripts/host-drivers/gitlab.sh:1
scripts/lib/adopt/adopt-state.sh:1       # the translation: [ "$mode" = "organizational" ] && mode="org"
$ grep -n -A3 '"gitleaks"' templates/tool-matrix/common.json | grep required   # §12 item 10
192-      "required": true,
```
(3) is retired because it stopped measuring what the row said: WP10a added `adopt-tools.sh`, whose
one hit is the executed path `_adopt_resolver_path` prints, and `adopt_main` now calls
`adopt_resolve_tools` at `# BL-242-RESOLVER-CALL`. (3') measures the built thing directly. The line
numbers in (5) and (9) are `grep -n`'s own output, per the house rule; the claims are by marker.

**V20 — the install set is 70, up from 68, and the two newcomers are named and dated.**
```
$ bash -c '. scripts/lib/scaffold-shipped-set.sh; soif_parse_shipped_scripts init.sh scripts | wc -l'
70          # 41 scripts/ + 24 scripts/lib/ + 3 scripts/host-drivers/ + 2 scripts/hooks/
$ T=$(mktemp -d) && git archive 45a749b init.sh scripts | tar -x -C "$T" \
    && ( cd "$T" && . scripts/lib/scaffold-shipped-set.sh && soif_parse_shipped_scripts init.sh scripts | sort ) > "$T.set"
$ wc -l < "$T.set"
68
$ diff "$T.set" <(soif_parse_shipped_scripts init.sh scripts | sort)
0a1
> scripts/check-changelog.sh
4a6
> scripts/check-session-state.sh
$ git log --format='%h %cs %s' -S'check-changelog.sh' -- init.sh | tail -1
8fcd204 2026-09-08 fix(bl-254): ship the two governance checks every generated CI already called
```
Merged as PR #378 (`c6da463`, 2026-09-08). *(The 2026-09-15 attempt's first run of this over a
scratch tree holding only `init.sh` returned 65 and listed the three host drivers as "new" — the
`scripts/host-drivers/*.sh` glob had nothing to match. Run the derivation against a full tree,
under bash, or it under-counts silently.)*

**V21 — the secrets enumerations are wider, adoption reads the widening, and the remedy ships at four operator-facing sites plus one comment.**
```
$ sed -n '241,242p' scripts/lib/scout/scout-secrets.sh
#   secstatus   scanned | scanned-partial | tool-unavailable | scan-failed
#   secscope    full-history | shallow-history | working-tree-only | (empty when not scanned)
$ grep -rn 'scanned-partial' scripts/lib/adopt/ | cut -d: -f1,2
scripts/lib/adopt/adopt-stubs.sh:129   scripts/lib/adopt/adopt-stubs.sh:133
scripts/lib/adopt/adopt-tools.sh:391   scripts/lib/adopt/adopt-tools.sh:400   scripts/lib/adopt/adopt-tools.sh:404
scripts/lib/adopt/adopt-tools.sh:516   scripts/lib/adopt/adopt-tools.sh:518
$ grep -rn 'BL-288-' scripts/ | cut -d: -f1,2
scripts/lib/adopt/adopt-tools.sh:391   scripts/lib/adopt/adopt-tools.sh:517   scripts/lib/scout/scout-secrets.sh:292
$ grep -rc "set-branches origin" scripts/ | grep -v ':0'
scripts/lib/adopt/adopt-stubs.sh:1
scripts/lib/adopt/adopt-tools.sh:2
scripts/lib/scout/scout-secrets.sh:1
scripts/lib/scout/scout-report.sh:1
```
Both readers are widened (`# BL-288-RESCAN-PARTIAL`); neither makes a stop/proceed decision — the
stub prints and returns 0, the re-scan guard treats `scanned-partial` as *scanned*. See §6.1a.
The `grep -rc` total of 5 includes ONE COMMENT — `adopt-tools.sh`'s first hit (line 401) is the
function header, not output — so the operator-facing sites are **four**: `adopt-stubs.sh`'s
`adopt_note`, `adopt-tools.sh`'s `adopt_note`, `scout-secrets.sh`'s and `scout-report.sh`'s
`printf`. Read the hits, do not count them; the first draft of this block counted the comment.

**V22 — WP10a is built; WP10b is not; the file says so itself.**
`scripts/lib/adopt/adopt-tools.sh`'s header: *"WHAT IT DELIBERATELY DOES NOT DO. It makes no
stop/proceed decision. §6.1's tier table, §6.3's dispositions and §6.4's tiered escape are WP10b's,
and a `tool-unavailable` result still completes an adoption here exactly as it did before this
package."* Read-verified. The suite does NOT pin the completion — its R3 case asserts the
attestation text, not the rc (2026-09-16 sweep); the header sentence is code-read, and §10's
preamble now says so. `adopt_stub_secrets_disposition` is still called
from `adopt_main` (V19-(1); `grep -n 'adopt_stub_secrets_disposition' scripts/lib/adopt/adopt-state.sh scripts/adopt-project.sh` → one hit, `adopt-state.sh:1362:  adopt_stub_secrets_disposition "$report"`).

**V23 — WP11 is not built: the install still skips on collision.**
```
$ grep -n 'n_collided\|-e "\$dst"' scripts/lib/adopt/adopt-state.sh | cut -c1-140
108:  local rel src dst n_copied=0 n_collided=0
125:    if [ -e "$dst" ]; then
128:      n_collided=$((n_collided + 1))
145:  adopt_note "Installed $n_copied framework script(s); left $n_collided of your own file(s) untouched."
154:    if [ "$n_collided" -gt 0 ]; then
171:  adopt_stub_framework_script_collisions "$n_collided" "$ADOPT_COLLISION_LIST"
```
`adopt_install_framework` still appends to `ADOPT_COLLISION_LIST` and `continue`s — the behaviour D1
reverses at WP11.

**V24 — the seven adoption suites, executed at `01b66e3`.**
```
tests/test-brownfield-wp9-act-boundaries.sh          Results: 29 passed, 0 failed
tests/test-brownfield-wp9b-preflight-approval.sh     Results: 103 passed, 0 failed
tests/test-brownfield-wp10a-tool-resolution.sh       Results: 54 passed, 0 failed
tests/test-bl225-prewrite-preflight.sh               Results: 50 passed, 0 failed
tests/test-bl253-adoption-state-parity.sh            Results: 19 passed, 0 failed
tests/test-bl268-mode-vocabulary.sh                  Results: 33 passed, 0 failed
tests/test-bl288-scout-shallow-history-claim.sh      Results: 15 passed, 0 failed, 0 skipped
```
All seven exited 0. `gitleaks` was present, so the WP10a suite's host-dependent seam took the
installed arm; `## BL-251:`'s entry records that its `R1`/`R2` fail on a gitleaks-free host. Not
run on Linux (§13-U(v2.1)).

**V25 — the suite inventory, and each file's add date (committer date of the adding commit).**
```
$ ls tests/ | grep -i 'brownfield\|module-dep\|bl225\|bl288\|bl268\|bl253\|bl251\|bl284\|bl273' | wc -l
17
$ ls tests/test-brownfield-wp*.sh | wc -l
10
$ for f in …; do git log --follow --diff-filter=A --format='%h %cs' -- "tests/$f" | tail -1; done
test-bl225-prewrite-preflight.sh          20bf740 2026-09-12
test-bl225-staging-preflight.sh           dc4b133 2026-08-31
test-bl253-adoption-state-parity.sh       7ff1e88 2026-09-08
test-bl268-mode-vocabulary.sh             eba7291 2026-09-15     # authored 2026-09-12
test-bl284-verify-install-context.sh      b797ffb 2026-09-15
test-bl288-scout-shallow-history-claim.sh 2a8fafb 2026-09-15     # authored 2026-09-12
test-brownfield-wp1-scout.sh … wp6        2026-08-03 … 2026-08-10, as §13-V14
test-brownfield-wp9-act-boundaries.sh     38bde7a 2026-08-31
test-brownfield-wp9b-preflight-approval.sh 45a749b 2026-09-01
test-brownfield-wp10a-tool-resolution.sh  4009790 2026-09-02
test-lint-module-dependencies.sh          ba22106 2026-08-03
$ grep -n 'suites cover it' solo-orchestrator-backlog.md | cut -c1-160
13657:Nine suites cover it — the eight `tests/test-brownfield-wp*.sh` files plus
```
Ten `tests/test-brownfield-wp*.sh` files now; at `01b66e3` `## BL-242:` said nine and eight — a
stale carrier PR #415 annotated one merge later (§13-U(v2.1)).

**V26 — every marker this amendment cites, found in the non-test code surface.** The loop, and the
number of files each marker occurs in (a count of FILES, printed so the reader can see which
markers are fence families or multi-site):
```
$ for m in <each marker below>; do printf '%-36s %s\n' "$m" \
    "$(grep -rl -- "# $m" scripts/ init.sh templates/ .github/ evaluation-prompts/ | wc -l | tr -d ' ')"; done
BL-225-TOUCHED-DISK 5   BL-225-TOUCHED-UNBOUNDED 3   BL-225-REFUSE-DERIVED 1   BL-225-PREWRITE-CALL 1
BL-225-WRITE-PHASE-REAL 1   BL-225-PREWRITE-REFUSE 1   BL-225-ORACLE-FAIL-CLOSED 1   BL-225-REHEARSAL-NO-HALT 1
BL-225-REHEARSAL-NO-TRACE 1   BL-225-REFUSE-HONEST 3   BL-225-STAGE-PREFLIGHT 2
BL-242-PREFLIGHT-ARM1 1   BL-242-PREFLIGHT-ARM2 1   BL-242-PREFLIGHT-ARM3 1   BL-242-PREFLIGHT-ARM3-INSTALLED 1
BL-242-PREFLIGHT-CALL 1   BL-242-PREFLIGHT-TEMPLATES 1   BL-242-PREFLIGHT-NAME 1   BL-242-EVIDENCE-CALL 1
BL-242-TIER-QUESTION 1   BL-242-RESOLVER-CALL 2   BL-242-RESOLVER-REFRESH 1   BL-242-RESOLVER-NO-EXEC 1
BL-242-RESOLVER-VERIFY 1   BL-242-RESOLVER-INSTALL 1   BL-242-SECRETS-RESCAN 1   BL-242-RESCAN-HONEST 1
BL-242-APPROVAL-LOG-FIRST 1   BL-242-PHASE0-LANDING 1   BL-242-ACT3-HANDOFF 1   BL-242-ORCH-SOURCE 1
BL-251-FAST-PATH 1   BL-251-FAST-PATH-RESCAN 1   BL-253-POC-MODE 1   BL-253-POC-NULL 1   BL-253-POC-NULL-MANIFEST 1
BL-268-MODE-VOCABULARY 4   BL-288-RESCAN-PARTIAL 1   BL-288-SHALLOW-SCOPE 1   BL-284-CONTEXT-STATE 1
BL-284-PLUGIN-VERB 1   BL-233-ATTEST-REFUSE 2   BL-221-ADOPT-TIER-KEYS 1   BL-270-MODE-VOCABULARY-BACKFILL 1
BF-ADOPT-SHA-REQUIRED 2   BF-ADOPT-STAMP-CALL 1   BF-ADOPT-STATE-ORDER 1   BL-180-ENFORCEMENT-DEFAULT 2
```
Every row is non-zero. In full, so the lint has something to check: `# BL-225-TOUCHED-DISK`,
`# BL-225-TOUCHED-UNBOUNDED`, `# BL-225-REFUSE-DERIVED`, `# BL-225-PREWRITE-CALL`,
`# BL-225-WRITE-PHASE-REAL`, `# BL-225-PREWRITE-REFUSE`, `# BL-225-ORACLE-FAIL-CLOSED`,
`# BL-225-REHEARSAL-NO-HALT`, `# BL-225-REHEARSAL-NO-TRACE`, `# BL-225-REFUSE-HONEST`,
`# BL-225-STAGE-PREFLIGHT`, `# BL-242-PREFLIGHT-ARM1`, `# BL-242-PREFLIGHT-ARM2`,
`# BL-242-PREFLIGHT-ARM3`, `# BL-242-PREFLIGHT-ARM3-INSTALLED`, `# BL-242-PREFLIGHT-CALL`,
`# BL-242-PREFLIGHT-TEMPLATES`, `# BL-242-PREFLIGHT-NAME`, `# BL-242-EVIDENCE-CALL`,
`# BL-242-TIER-QUESTION`, `# BL-242-RESOLVER-CALL`, `# BL-242-RESOLVER-REFRESH`,
`# BL-242-RESOLVER-NO-EXEC`, `# BL-242-RESOLVER-VERIFY`, `# BL-242-RESOLVER-INSTALL`,
`# BL-242-SECRETS-RESCAN`, `# BL-242-RESCAN-HONEST`, `# BL-242-APPROVAL-LOG-FIRST`,
`# BL-242-PHASE0-LANDING`, `# BL-242-ACT3-HANDOFF`, `# BL-242-ORCH-SOURCE`, `# BL-251-FAST-PATH`,
`# BL-251-FAST-PATH-RESCAN`, `# BL-253-POC-MODE`, `# BL-253-POC-NULL`, `# BL-253-POC-NULL-MANIFEST`,
`# BL-268-MODE-VOCABULARY`, `# BL-288-RESCAN-PARTIAL`, `# BL-288-SHALLOW-SCOPE`,
`# BL-284-CONTEXT-STATE`, `# BL-284-PLUGIN-VERB`, `# BL-233-ATTEST-REFUSE`, `# BL-221-ADOPT-TIER-KEYS`,
`# BL-270-MODE-VOCABULARY-BACKFILL`. `scripts/lint-bl-markers.sh` is the standing check on every
backticked cite in this file; its result on the amended tree is in §13-U(v2.1).

**V27 — §8.7a's write set, MEASURED BY EXECUTION: a shipped adoption against a hermetic adoptee,
tree listed before and after.** The fixture is `tests/test-brownfield-wp9b-preflight-approval.sh`'s
`mk_adoptee` shape (four tracked files, one commit, `core.excludesFile /dev/null`), the report is
`scripts/scout.sh`'s own over that tree, the answers are the tier question plus four confirmations,
and the framework root is this checkout. `GITHUB_BASE_REF` unset; run under `bash`.
```
tree: 01b66e3   gitleaks: /opt/homebrew/bin/gitleaks
scout rc=0
report: {"schemaVersion":2,"status":"scanned","scope":"full-history","findingCount":0}
adopt rc=0
before: 4 files   after: 83 files   removed: 0
total new files: 79  |  under scripts/: 70  |  under .claude/adoption-archive/: 0
non-scripts/ new paths:
.claude/adoption/scout-report.json
.claude/intake-progress.json
.claude/manifest.json
.claude/orchestrator-source.json
.claude/phase-state.json
.claude/process-state.json
.claude/test-debt.json
APPROVAL_LOG.md
PROJECT_INTAKE.md
new scripts/ paths vs the install set (soif_parse_shipped_scripts):
  IDENTICAL to the install set (70 paths)
.git/hooks delta:
  commit-msg
adoptee git after: HEAD moved: yes   status: 0 dirty entries
adoption commit: chore: adopt p into the Solo Orchestrator framework —  79 files changed, 43833 insertions(+)
NOT DONE blocks in transcript: 5
stderr lines: 0
```
(`find . -path ./.git -prune -o -type f -print | LC_ALL=C sort` either side, `comm -13` for the new
set; `.git/hooks` listed separately because the prune hides it.) The nine non-`scripts/` paths are
the nine §8.7a listed on 2026-09-01, unchanged; the `scripts/` half moved 68 → 70 with V20's two
files. **No `templates/` is written** — §8.7a row 7. The transcript's five `NOT DONE` blocks name
their owners as *WP7* (twice), *nobody yet — §10 names no owner* (the stale `adopt_stub_hooks`
string, §1.2), *WP11 archives them, WP12b writes them (D3)* and *WP12a*; on a clean adoptee the
collisions stub and the secrets stub are silent, as §1.2 derives. Then the adoptee's own gate:
```
$ ( cd "$p" && bash scripts/check-phase-gate.sh > gate.out 2>&1; echo rc=$?; tail -3 gate.out; grep -ci 'matrix\|resolve' gate.out )
rc=0
[OK] Adoption stamp present and intact (adopted: 2026-09-16T13:36:23Z)

Phase gates consistent.
0                           # no 'matrix' or 'resolve' line — the block is keyed on .claude/tool-preferences.json
```

**V28 — the 2026-09-16 ruling is NOT built, and at `01b66e3` it has no tracked carrier.**
```
$ git grep -n -i 'go with the split' -- . ; echo rc=$?
rc=1
$ grep -n 'secrets.status' scripts/lib/adopt/*.sh | cut -d: -f1,2
scripts/lib/adopt/adopt-stubs.sh:124      # adopt_stub_secrets_disposition: reads it, prints, returns 0
scripts/lib/adopt/adopt-tools.sh:390      # _adopt_rescan_secrets: the scanned|scanned-partial guard
$ grep -n 'adopt_refuse' scripts/lib/adopt/adopt-tools.sh scripts/lib/adopt/adopt-stubs.sh | grep -c partial
0
```
The only two readers of the status are the ones §6.1a names, and neither reaches a refusal on it.
The ruling's carriers on this tree are this document (§0.1, §6.1, §6.1a, §12 item 16) and nothing
else — §13-U(v2.1).

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

#### §13-U(v2.1) — added 2026-09-16

- **The 2026-09-16 ruling itself.** Recorded from the maintainer's instruction to this amendment,
  which quoted three words — *"go with the split"* — and stated the ruling's content; no transcript
  was seen and no tracked file carried it at `01b66e3` (`git grep -n -i 'go with the split'` → rc 1,
  V28). PR #415 recorded it in `## BL-242:` (D2's amendment paragraph) and `## BL-288:` (its RULED
  block) one merge later, so from `7b88c2e` this document is one carrier of three; the merged-main
  sweep of 2026-09-16 read all three against the ruling as given and found them agreeing.
- **"WP10 is built as two PRs on Karl's call."** `4009790`'s commit message says so; the
  attribution is the commit's and was not independently verified.
- **`## BL-242:`'s two WP10a-review residuals** (the URL in `auto_install`; the unpinned root
  recipe). Read from the entry, which records its own measurements; not re-run.
- **Three stale carriers of superseded facts, read and NOT corrected by this amendment** (each
  outside its file scope) — **all three corrected by PR #415 one merge later**; what follows is what
  they said at `01b66e3`: `docs/adoption.md` — its summary table files the secrets stop under an
  unsplit `WP10`, has no tool-resolution row, and its write-order prose says *"77 file(s)"* and
  *"68 of them"* (V27: 79 and 70); `## BL-242:` — *"Nine suites … the eight"* (V25: ten) and
  *"**77** files written, 68 under `scripts/`"*; `docs/INDEX.md`'s blurb for this document — *"Half
  built"* with a list that omits WP9b and WP10a, and *"thirteen unowned rows"* where §8.7a now has
  fourteen.
- **Three backlog status lines that lagged the tree at `01b66e3`, reported here and corrected by
  PR #415** (BL-268 and BL-270 Closed, BL-288's line rewritten): `## BL-268:`
  says *"fix + suite committed on branch `fix/bl268` … Not pushed, no PR"* while `eba7291` is an
  ancestor of `01b66e3` via PR #412; `## BL-270:` says *"branch `fix/bl270` … Not pushed"* while
  `0dc57fc` (`# BL-270-MODE-VOCABULARY-BACKFILL`) is on `main`; `## BL-288:` says *"fix prepared on
  `fix/scout-shallow-history-claim`, not yet raised as a PR"* while `2a8fafb`, `35a222a` and
  `22b034d` are ancestors via PR #412 (V18).
- **§8.4a's "nothing written" state** is asserted by `tests/test-bl225-prewrite-preflight.sh`
  (50/0, V24) on its own crafted `.gitignore` fixtures; this amendment did not drive a refusing
  fixture by hand. V27 is a completing adoption, not a refused one.
- **The seven suites ran on this darwin host only**, with `gitleaks` present. Not run on Linux, not
  run on a gitleaks-free host; `## BL-251:` records what changes on the latter.
- **Row 7's "unreachable"** is one measurement — the resting-state gate on V27's adoptee printed
  no matrix line and exited 0 — plus a source read of the block's `[ -f "$TOOL_PREFS" ]` guard.
  What the adoptee's gate would print at a later phase *with* a `tool-preferences.json` hand-added
  and no matrix was not exercised.
- **V25's dates are committer dates**; three suites carry author dates two to three days earlier
  (rebased at merge). Neither date is "when the suite was written"; both are printed so a reader
  can pick.
- **Lints on the amended tree — RUN, all green, recorded here rather than claimed above:**
  `bash scripts/lint-bl-markers.sh` → *OK: 601 marker token(s) resolve to backlog entries and 939
  prose citation(s) resolve to live markers* (838 before this amendment; 945 on `7b88c2e`, after PR #415);
  `bash scripts/lint-doc-anchors.sh` → *OK: no broken in-document anchors across 112 file(s)* — 110 in a
  clean checkout; the 112 counted two untracked handoff files in the author's working tree, a number
  that was never a property of the tree;
  `bash scripts/run-lints.sh` → *16 lints — 16 passed, 0 failed*, rc 0. These are the checks; they
  do not read this document's prose for truth, which is what §13's V-blocks are for.
- **Second pass (2026-09-16, after the sweep):** every correction above is dated to `01b66e3` or
  `7b88c2e`; the sweep's own unverified list stands — V27 not re-executed on `7b88c2e` (the seven
  suites and the writer fields stand in for it), `## BL-251:`'s timing, Linux and gitleaks-free
  hosts, and the WP10a split's attribution to Karl. Lints on the second pass, in a clean worktree:
  `lint-bl-markers.sh` → *OK: 606 marker token(s) … 958 prose citation(s)*; `lint-doc-anchors.sh` →
  *OK … 110 file(s)*; `run-lints.sh` → *16 passed, 0 failed*.

### §13 — v2.2 addendum: commands actually run for the 2026-09-17 amendment

Executed on **2026-09-17** against tree **`579b0b0`** (= `origin/main`, checked out on
`docs/brownfield-v2.2-amendment`), working tree `/Users/karl/Documents/Claude Projects/solo-orchestrator`,
darwin host, git 2.54.0, gitleaks 8.30.1 at `/opt/homebrew/bin/gitleaks`, a case-insensitive
filesystem. The blocks below are the output of one script run end to end
(`measure-v22.sh`, in the amendment session's scratch directory — not a tracked file), trimmed for
length, never paraphrased; where a probe was first run ad hoc and then re-run by the script, the
script's numbers are the ones printed. Re-run them; do not quote them.

**V29 — the status-row derivations, re-run.**
```
$ git rev-parse --short HEAD
579b0b0
$ (1) §1.2's recipe                                    -> 7, same membership as §13-V19-(1)
adopt_stub_adoption_record  adopt_stub_assessment  adopt_stub_framework_script_collisions
adopt_stub_hooks  adopt_stub_project_docs  adopt_stub_provenance_headers  adopt_stub_secrets_disposition
$ ls scripts/lib/adopt/                                 # (2) eight files, no adopt-chooser.sh
adopt-archive.sh adopt-core.sh adopt-evidence.sh adopt-intake.sh adopt-state.sh adopt-stubs.sh adopt-test-debt.sh adopt-tools.sh
$ git grep -l 'built out and needs' -- .                # (2) the fragment: the same four files
docs/designs/2026-08-02-brownfield-adoption-v1.md
docs/designs/2026-08-23-brownfield-adoption-v2.md
solo-orchestrator-backlog.md
tests/test-brownfield-wp9-act-boundaries.sh
$ grep -c 'adopt_resolve_tools "$root" "$report"' scripts/lib/adopt/adopt-state.sh   # (3')
1
$ grep -c 'adopt' scripts/resume.sh                     # (4)
0
$ grep -o 'BL-242-PREFLIGHT-ARM[A-Z0-9-]*' scripts/lib/adopt/adopt-state.sh   # (5)
BL-242-PREFLIGHT-ARM1  BL-242-PREFLIGHT-ARM2  BL-242-PREFLIGHT-ARM3  BL-242-PREFLIGHT-ARM3-INSTALLED
$ grep -A2 '^_adopt_state_order()' scripts/lib/adopt/adopt-state.sh | grep printf   # (6)
  printf '%s\n' approval_log   # BL-242-APPROVAL-LOG-FIRST
  printf '%s\n' phase_state intake manifest   # BF-ADOPT-STATE-ORDER
$ grep -c 'BL-225-PREWRITE-CALL\|BL-225-WRITE-PHASE-REAL' scripts/lib/adopt/adopt-state.sh   # (7)
2
$ grep -c '_adopt_write_phase "' scripts/lib/adopt/adopt-state.sh   # the two callers
2
$ grep -n 'schemaVersion' scripts/lib/scout/scout-report.sh   # (8)
58:  printf '  "schemaVersion": 2,\n'
$ grep -c -- '-e "$dst"' scripts/lib/adopt/adopt-state.sh   # (9) still skips on collision (the installer + the preflight sibling)
2
$ git grep -c 'adopted-in-production' -- scripts/ ; echo rc=$?; grep -c hooksPath scripts/lib/adopt/adopt-state.sh   # (10)
rc=1
0
$ bash -c '. scripts/lib/scaffold-shipped-set.sh; soif_parse_shipped_scripts init.sh scripts | wc -l'
70
```

**V30 — `## BL-242:`'s D-block is byte-identical from `7b88c2e` (v2.1's second pass) to `579b0b0`.**
The header-anchored span, never line numbers (§13-V17's lesson).
```
$ ex()   { awk '/^## BL-242:/{f=1} f' | awk 'NR==1{print; next} /^## BL-[0-9]+:/{exit} {print}'; }
$ span() { awk '/^### THE THREE UNOWNED/{f=1} /^### Consequences/{exit} f' "$1"; }
$ span lines 7b88c2e / HEAD / f73dfca
490 490 478
$ diff <(span 7b88c2e) <(span HEAD); echo rc=$?
rc=0
$ diff <(span f73dfca) <(span HEAD) | grep -c '^[<>]'    # the D2 AMENDED paragraph PR #415 added
12
```

**V31 — where git runs hooks (git 2.54.0), in a scratch repository.** The measurement R1's
mechanism (M1/M2) is built on.
```
$ git rev-parse --git-path hooks                        # no hooksPath
.git/hooks
$ git config core.hooksPath /tmp/xhooks; git rev-parse --git-path hooks; git rev-parse --git-common-dir
/tmp/xhooks
.git
$ git config core.hooksPath ''; git config core.hooksPath; echo rc=$?; git rev-parse --git-path hooks
                                                        # (empty value)
rc=0                                                    # set-EMPTY reads as CONFIGURED by exit status
./                                                      # and git then looks in the repository ROOT
$ (cd sub) git rev-parse --show-prefix; git rev-parse --git-path hooks; git rev-parse --path-format=absolute --git-path hooks
sub/
../.git/hooks                                           # RELATIVE TO CWD — resolve it, or use -C root
/private/var/…/r/.git/hooks
$ (cd a linked worktree) --show-toplevel; --git-dir; --git-common-dir; --git-path hooks; test -f .git
$T/wt                                                   # --show-toplevel IS the worktree: the toplevel test alone does NOT catch it
$T/r/.git/worktrees/wt
$T/r/.git
$T/r/.git/hooks                                         # git runs the MAIN repository's hooks
.git is a FILE                                          # the gitfile test is what catches it
```
`git worktree add` was run in a SCRATCH temp repository, never in this one (CLAUDE.md's block on
that command is about this checkout).

**V32 — A1 on `main`: an adoptee with `core.hooksPath` configured.** The wp9b `mk_adoptee` shape
plus `git config core.hooksPath "$T/hp"`; Scout's own report; answers `1 1 1 1 1`.
```
$ adopt
rc=0
.git/hooks/commit-msg: present                          # written where git will NOT look
hooksPath/commit-msg: ABSENT
1                                                       # grep -c 'message gates are live' transcript
$T/out:0  $T/err:0                                      # grep -ci hooksPath: the run never mentions it
$ (cd p) echo x >> README.md; git add README.md; GIT_TRACE=1 git commit -q -m wip; grep -c commit-msg trace
commit rc=0
0                                                       # git ran NO hook
$ control: git config --unset core.hooksPath; same commit; grep -o 'run_command:.*hooks[^ ]*' trace
commit rc=0
run_command: GIT_EDITOR=: GIT_INDEX_FILE=.git/index .git/hooks/commit-msg
```

**V32b — a `--root` at a SUB-DIRECTORY of a repository (the review's probe `v32b.sh`, re-run by this
author on the amended branch; identical outcome to the review's run).** The wp9b shape with a
`sub/` package committed, Scout run on `sub/`, `--root "$T/p/sub"`.
```
scout rc=0
adopt rc=1  (0s)
2:[REFUSED] the pre-write rehearsal did not complete (rc=1) — nothing was written to your project
sub/.git exists as: ABSENT
live sentence count: 0
HEAD count: 2                                           # the repository's HEAD did not move
repo .git/hooks/commit-msg: ABSENT
          Adoption did not begin. Nothing was committed and nothing was written.
```
The refusal is honest and arrives AFTER the tier question and the confirmations (the answers were
piped): the rehearsal's copy of `sub/` has no `.git`, `adopt_test_debt_record` runs git outside a
repository, and the rehearsal returns 1. BL-290's first filing said this shape completes at rc 0 with
the live line; it does not (the review's R-1).

**V32c — a LINKED WORKTREE as `--root` (the review's `v32c.sh`, re-run by this author).**
```
.git in wt is: FILE
scout rc=0
adopt rc=1  (4s)
2:[BLOCKED] could not create $T/wt/.git/hooks
wt HEAD count: 2                                        # the adoption commit LANDED in the worktree
6a22ef2 chore: adopt wt into the Solo Orchestrator framework
7329344 chore: their own history
manifest at HEAD: present
live sentence count: 0
main repo .git/hooks/commit-msg: ABSENT
          The adoption commit HAD already landed; a later step did not complete.
          79 file(s) were written and committed.
```
`mkdir -p "$root/.git/hooks"` fails on the gitfile after the commit; *Not a directory* is never
printed; no hook exists anywhere; the state is not the window (§12 item 32).

**V33 — A3 on `main`: the adoptee's own pre-commit hook rejects the adoption commit.** Same shape
plus `.git/hooks/pre-commit` = `exit 1`.
```
$ run 1
rc=1
[BLOCKED] the adoption commit did not succeed — your own hooks or git identity may have refused it
          Nothing was committed. 83 file(s) were already written into this project.
$ jq .adoption.adopted manifest; git rev-list --count HEAD; git show HEAD:.claude/manifest.json; git diff --cached --name-only | wc -l; test -f .git/hooks/commit-msg
true                                                    # working-copy witness
1                                                       # HEAD did not move
HEAD copy: absent                                       # committed witness
83                                                      # left STAGED in the index
commit-msg: ABSENT
$ (cd p) . scripts/lib/adoption-stamp.sh; soif_adoption_pre_adoption_commit && echo EXEMPT
EXEMPT                                                  # the stamp's own bound calls this the adoption window
$ run 2 (bare re-run)
rc=1
[REFUSED] this project has already been adopted — the manifest records it
scripts/resume.sh        — co…                          # the advice
--re-add <path>
mentions finish: 0
```

**V34 — Act 2 on `main` against an adoptee owning `PROJECT_INTAKE.md`, `.claude/intake-progress.json`
and `scripts/Validate.sh`, all tracked.**
```
$ git ls-files; git config core.ignorecase
.claude/intake-progress.json PROJECT_INTAKE.md README.md package.json scripts/Validate.sh
true
$ sha256 PROJECT_INTAKE.md before
f2976ff0e1cbdfb7
$ adopt
rc=0
$ sha256 after; head -1; jq -c '{theirs,source}' .claude/intake-progress.json
996e5b9b8430e133                                        # OVERWRITTEN
# Project Intake
{"theirs":null,"source":"adopt-project.sh"}             # OVERWRITTEN
$ ls -d .claude/adoption-archive/*/ | wc -l; grep -ci 'PROJECT_INTAKE.md.*\(archiv\|replac\|overwr\)' out
0                                                       # no archive directory at all
0                                                       # no sentence about it
$ ls scripts | grep -i validate; grep -i validate out; git ls-files | grep -i scripts/validate; grep -o 'Installed [0-9]* framework script(s); left [0-9]*' out
Validate.sh
     yours, kept: scripts/validate.sh                   # a path the index does not hold
scripts/Validate.sh
Installed 69 framework script(s); left 1
```

**V35 — gitleaks 8.30.1: repo-local rules versus the framework's, and the no-checkout clone.** A
BASE32-valid `AKIA…` plant in one commit; `sc` = `gitleaks git --no-banner --redact --exit-code 0
-f json` in the named directory, printing the finding count; `framework.toml` = `[extend]`
`useDefault = true`.
```
1  control (BASE32-valid plant, one commit)                                        1
2  .gitleaksignore (untracked) with the fingerprint                                0
3  same + --gitleaks-ignore-path /dev/null | <dir with EMPTY .gitleaksignore> | <the empty file> | <nonexistent>
   0  0  0  0                                                                      # NO flag defeats it
4  same + -c framework.toml (does config outrank the ignore file?)                 0
5  .gitleaks.toml (untracked) allowlisting AKIA                                    0
6  same + -c framework.toml ([extend] useDefault = true)                           1
7  GITLEAKS_CONFIG env at the allowlisting toml, no -c | with -c                   0  1
8  inline gitleaks:allow (2nd plant) + TRACKED toml + TRACKED ignore, -c framework | + --ignore-gitleaks-allow
   0  1                                                                            # the ignore file still hides one of two
9  git clone --shared --no-checkout src nc; gitleaks in nc, -c framework --ignore-gitleaks-allow; worktree files; HEAD
   2                                                                               # BOTH plants: no rule file exists there
   0                                                                               # worktree files
   HEAD equal
10 shallow source: clone --depth 1 file://src shal; clone --shared --no-checkout shal shal-nc
   clone rc=0
   true                                                                            # is-shallow
   1                                                                               # rev-list --count
   2                                                                               # the tip commit's tree holds both plants
   (this run never checked the alternates file; V35b did — for a shallow source `--shared` is IGNORED)
$ cost on this repository: commits; tracked; gitleaks git in place; clone --shared --no-checkout; gitleaks in the clone
1840
819
in place: 1.4 s, findings=9
clone: 0.04 s, 108K
in the clone: 1.4 s, findings=9, commits=1840
```
(The nine findings on this repository are its own suites' documented plants; not this
amendment's subject.)

**V35b — the review's `v35.sh` re-run by this author: the cwd fact (9b–9d), the alternates file (9, 10),
and the cost lines, on the amended branch (two commits after `579b0b0`).**
```
=== V35: gitleaks 8.30.1 ===
1 control: 1
2 untracked .gitleaksignore: 0
3 flags: /dev/null=0 emptydir=0 emptyfile=0 nonexistent=0
4 + -c framework.toml: 0
5 untracked .gitleaks.toml allowlist: 0
6 + -c framework.toml: 1
7 GITLEAKS_CONFIG env: no-c=0 with-c=1
8 inline allow + tracked toml + tracked ignore, -c: 0  + --ignore-gitleaks-allow: 1
9 no-checkout shared clone, -c + --ignore-gitleaks-allow (cwd=nc): 2  worktree files: 0  HEAD equal: yes  alternates: $T/src/.git/objects
9b SAME clone scanned with CWD = adoptee root (the driver's cwd), source = clone path: 1
9c same, cwd=adoptee, plus --gitleaks-ignore-path /nonexistent/x: 2
9d cwd=adoptee, source=clone, NO -c (does src/.gitleaks.toml get read from cwd?): 1
10 shallow: clone rc=0  warn: Cloning into 'shal-nc'...
   is-shallow: true  rev-list: 1  alternates present: NO  findings: 2
--- cost on this repository:
commits: 1842  tracked: 819
in place: 2s findings=9
clone: 0s 108K
in clone: 1s findings=9 commits=1842
```
9b is the fact §6.2b's mechanism now states as load-bearing: `--gitleaks-ignore-path` defaults to
`.`, the PROCESS cwd, so the same clone scanned from the adoptee's cwd reads the adoptee's
`.gitleaksignore` (1 of 2); 9c shows the flag at an empty location restoring 2 of 2; 9d shows the
`.gitleaks.toml` is NOT read from cwd (it is read from the source path — the clone has none). 10
shows `--shared` silently ignored for a shallow source: no `alternates` file, the clone is a copy;
shallowness (`true`, 1 commit) and findings are unaffected. Both facts were found by the review's
probes, not by v2.2's first run (§13-U(v2.2)).

**V36 — the rehearsal's cost on this repository.**
```
$ files (excl .git); du -sh . .git .git/objects
965
57M .  32M .git  30M .git/objects
cp -a whole tree: 0.43 s,  57M
shared-objects copy (tar, minus .git/objects, plus alternates): 0.54 s,  27M
git in the copy: tracked=819 HEAD=579b0b0 check-ignore .claude rc=1   (original tracked=819)
```

**V37 — the wizard's `save_answer` keys, the prefill fields, and `pnmp`.**
```
$ grep -oE 'save_answer +"[a-z_0-9]+"' scripts/intake-wizard.sh | sed … | sort -u | wc -l   # distinct literal keys
88
$ the literal keys
accessibility_target ai_subscription app_store auth_strategy auto_update backup beta_testing branding breakeven browsers bug_tracking_tool code_signing codename color_vision competitive_range cost_per_user current_problem current_solution dark_mode data_classification data_storage data_volume db_experience devops_experience dist_channels docker_available domain env_strategy ephemeral_data exit_conditional exit_failure exit_success frameworks_used frontend_framework geo_distribution git_host hard_deadline hosting hosting_10k hosting_1k hosting_launch hours_per_week human_tester_count ide known_risks languages_known maintenance_window mcp_server_persistence mcp_server_sdk mcp_server_transport min_os min_os_versions mobile_dist mobile_framework mobile_offline monthly_budget mvp_date offline_requirement one_time_budget packaging persistent_data price_point pricing_model primary_machine primary_persona problem_statement refuse_to_use repo_url repo_visibility responsive retention secondary_personas sev_critical_sla sev_high_sla sev_low_sla target_platforms testing_interval time_pattern uat_role ui_framework uptime user_type users_12mo users_6mo users_launch willing_to_learn zdr_attestation_reason zdr_attested
$ grep -nE 'save_answer +"[^"]*\$' scripts/intake-wizard.sh      # the dynamic families, by line
824 metric_${i}_name;825 metric_${i}_target;826 metric_${i}_measurement;841 exclusion_$i;948 feature_${i}_name;949 feature_${i}_trigger;950 feature_${i}_failure;961 should_have_$i;976 will_not_$i;1011 input_${i}_name;1012 input_${i}_type;1013 input_${i}_validation;1014 input_${i}_sensitivity;1015 input_${i}_required;1031 output_${i}_name;1032 output_${i}_format;1033 output_${i}_latency;1050 integration_${i}_service;1051 integration_${i}_data;1052 integration_${i}_auth;1053 integration_${i}_fallback;1244 competency_$key;1269 competency_${key}_tooling;1377 infra_$key;1514 precondition_${i}_status;1515 precondition_${i}_details;1520 precondition_${i}_status;1525 precondition_${i}_details;1527 precondition_${i}_details;1544 gate_$key;1557 escalation_$key;1577 compliance_$j
$ grep -nE '^run_section_[0-9_a-z]+\(\)' scripts/intake-wizard.sh   # section boundaries — which family sits in which section
603:run_section_1 654:run_section_1_repo_setup 778:run_section_2 851:run_section_3 921:run_section_4 986:run_section_5 1186:run_section_6 1388:run_section_7 1439:run_section_8 1604:run_section_9 1641:run_section_10 1694:run_section_11 1714:run_section_11_5 1786:run_section_12 1800:run_section_13
$ grep -cE '^[[:space:]]*save_answer ' scripts/intake-wizard.sh      # call sites (`## BL-282:` said 122 at ceb450e)
121
$ _scout_prefill_table fields (id kind field)
1 scan-derived project_name; 1_repo_setup scan-derived repo_remote_configured; 2 judgment problem_statement; 3 judgment timeline; 4 judgment mvp_features; 5 non-skippable data_classification; 6 judgment competency_matrix; 7 judgment revenue_model; 8 judgment governance; 9 judgment accessibility; 10 judgment uptime; 11 judgment known_risks; 11_5 scan-derived test_command; 12 scan-derived tooling; 13 scan-derived agent_init_prompt
$ git grep -n pnmp -- scripts templates init.sh tests docs/adoption.md docs/scout.md README.md; echo rc=$?
rc=1
$ git grep -l pnmp -- . ':!docs/designs/2026-08-23-brownfield-adoption-v2.md'; echo rc=$?
rc=1
```
(The whole-tree `git grep -n pnmp -- .` returns THIS document's own two sentences and nothing
else — the claim-inside-the-file trap §13-V7 records, met a fourth time and scoped rather than
transcribed.) The line numbers above are `grep -n`'s own output, per the house rule; the claims
are by function and section.

**V38 — `init.sh`'s hook roster, reference documents, skills, and the CDF nesting; `check-changelog.sh`;
rows 18–21 as they stood at `579b0b0`.**
```
$ grep -oE 'contains\("[a-z0-9-]+\.sh"\)' init.sh | sort | uniq -c        # the roster, by registration count
track-tool-usage.sh×2 bypass-detector.sh×2 session-version-check.sh×1 session-test-gate-check.sh×1 session-intake-check.sh×1 session-freshness-check.sh×1 session-end-qdrant-reminder.sh×1 session-cadence-check.sh×1 record-claude-commit.sh×1 pre-commit-gate.sh×1 detect-out-of-band-commits.sh×1
$ grep -oE 'cp "\$SCRIPT_DIR/docs/[^"]+" docs/reference/' init.sh          # row 18's eight
builders-guide.md governance-framework.md executive-review.md cli-setup-addendum.md user-guide.md messaging-standard.md security-scan-guide.md uat-authoring-guide.md
$ grep -oE 'for skill in [a-z -]+; do' init.sh                             # row 21's four
for skill in session-handoff sweep-triage zoom-out grill-with-docs; do
$ nesting: the CDF branch, the hooks-merge line, the roster's print, the closing fi lines
1899:    if [ "$framework_valid" = true ]; then
1989:      if [ -f ".claude/settings.json" ] && command -v jq &>/dev/null; then
2166:          print_ok "Session hooks installed (version check, test gate, MCP gate, Qdrant reminder, commit gate, tool tracking, bypass detector)"
2167:         fi
2168:       fi
2169:     fi
2170:   fi
$ grep -n 'SOIF_STRICT_CHANGELOG\|exit 1' scripts/check-changelog.sh
12:#   SOIF_STRICT_CHANGELOG=true  — exit 1 instead of warning (default: false)
16:#   1 — source changed without changelog (only when SOIF_STRICT_CHANGELOG=true)
77:  if [ "${SOIF_STRICT_CHANGELOG:-false}" = "true" ]; then
78:    exit 1
$ git show HEAD:docs/designs/2026-08-23-brownfield-adoption-v2.md | grep -E '^\| (18|19|20|21) \|' | cut -c1-110
| 18 | `docs/reference/*` (8 verbatim docs) | **UNOWNED — and load-bearing.** `messaging-standard.md` is the d
| 19 | `.claude/settings.json` — permissions + hook roster | **UNOWNED** — the adoptee's sessions run the ordi
| 20 | `.claude/settings.local.json` — `mcpServers.qdrant` (`# BL-233-WPB-MANIFEST-DECL`) | **UNOWNED** — `##
| 21 | `.claude/skills/<name>/SKILL.md` (vendored skills) | **UNOWNED** |
```
The hooks-merge block (`if [ -f ".claude/settings.json" ] && command -v jq`) is nested inside the
`framework_valid` branch (`if [ "$framework_valid" = true ]`) and closes before that branch's `fi` —
the nesting is read off the indentation and the closing `fi` lines the `grep -n` above prints; its
numbers are that grep's own output on 2026-09-17, cited as output and not as a location (the review's
R-20 caught the bare numbers in the backlog's copy). That is how row 33 was found; §13-U(v2.2)
records that the CDF was not run here.

**V39 — every reader of `.adoption.<field>` in the code surface (A12).**
```
$ grep -rnoE '\.adoption\.[A-Za-z]+' scripts/ init.sh | sed -E 's/^([^:]+):[0-9]+:/\1 /' | sort | uniq -c
   3 scripts/lib/adoption-stamp.sh .adoption.adopted
   1 scripts/lib/adoption-stamp.sh .adoption.adoptedAtCommit
   1 scripts/check-phase-gate.sh .adoption.adoptedAt
```
Three fields, all present in a v1 (`schemaVersion: 1`) stamp — the basis of §8.3's closure.

**V40 — every reader of the era invariant among the delta, resume, validate and gate scripts (R2's
blast radius).**
```
$ grep -n '"4"\|-lt 4' scripts/delta.sh scripts/resume.sh scripts/validate.sh | grep -v ':\s*#'
scripts/delta.sh:1013:  if [ "$phase" != "4" ]; then                                        # DELTA-OPEN-ERA-GUARD
scripts/resume.sh:102:if [ "$PHASE" = "4" ] && command -v jq >/dev/null 2>&1; then          # DELTA-RESUME-PHASE4
scripts/validate.sh:369:  [ "$phase" -lt 4 ] || return 0
$ grep -c 'adoption_exemptions\|inProduction' scripts/check-phase-gate.sh scripts/delta.sh scripts/resume.sh scripts/validate.sh
scripts/check-phase-gate.sh:0   scripts/delta.sh:0   scripts/resume.sh:0   scripts/validate.sh:0
$ grep -n 'validate_approval_fields\|self-approval detected' scripts/delta.sh scripts/resume.sh | wc -l
0
```
Three readers, none of them the phase gate; nothing of R2 exists yet; the self-approval control
(`## BL-274:`'s concern) is not among the readers.

**V41 — the git identity oracle.**
```
$ GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME=/nonexistent git var GIT_COMMITTER_IDENT
Karl Raulerson <karl@Karls-Mac-mini.local>              # this Mac auto-detects an identity
rc=0
$ same, with -c user.useConfigOnly=true                 # the shape of a host that cannot
Committer identity unknown
rc=128
```

**V42 — the refusal sites, by file, and the two labels `adopt_refuse` prints.**
```
$ grep -c 'adopt_refuse "' scripts/lib/adopt/*.sh
adopt-archive.sh:11  adopt-core.sh:9  adopt-evidence.sh:0  adopt-intake.sh:2  adopt-state.sh:36  adopt-stubs.sh:0  adopt-test-debt.sh:0  adopt-tools.sh:0
$ grep -n "printf '\\n\[" scripts/lib/adopt/adopt-core.sh
106:    printf '\n[BLOCKED] %s\n' "$1" >&2
132:    printf '\n[REFUSED] %s\n' "$1" >&2
```
Fifty-eight call sites at `579b0b0`; read them, do not count them — §8.1 classifies them by kind.

**V43 — the audit row's reserved event vocabulary and the two shipped attestation writers §6.3
reuses by shape.**
```
$ grep -n 'secrets_disposition\|adoption_event' scripts/lib/bypass-audit.sh | head -3
14:#                                  "sast_suppression" | "adoption_event",
15:#                                  (Brownfield §8.9: "adoption_event" records a
21:#                                  blocker_acceptance, secrets_disposition,
$ grep -n 'tdd_attestations = ' scripts/pre-commit-gate.sh
348:      '.tdd_attestations = ((.tdd_attestations // []) + [{date:$date, subject:$subject, reason:$reason, files:$files}])' \
$ grep -n 'mcp_attestations = ' scripts/session-mcp-gate.sh
196:             '.mcp_attestations = ((.mcp_attestations // []) + [{date:$date, reason:$reason, blocked_on:$blocked}])' \
$ grep -c BL-233-ATTEST-REFUSE scripts/session-mcp-gate.sh; grep -c BL-072-TDD-ENFORCE scripts/pre-commit-gate.sh
1
2
```

**V44 — D1–D10, §0.2 and §8.3a's A1–A8 are byte-identical before and after this amendment.**
`before` is the file at `579b0b0` (a copy taken before the first edit); `after` is the amended
working copy. Header-anchored sections, never line numbers.
```
$ dcells() { grep -E '^\| \*\*D([1-9]|10)\*\* \|' "$1" | awk -F'|' '{print $2"|"$3}'; }   # the row id and the DECISION cell
$ dcells before | wc -l; diff <(dcells before) <(dcells after); echo rc=$?
10
rc=0
$ diff <(grep -E '^\| \*\*D2\*\* \|' before) <(grep -E '^\| \*\*D2\*\* \|' after) | grep -c '^[<>]'   # the D2 row's LAST cell (author-proposed) gained one clause
2
$ sect() { awk -v h="$2" -v n="$3" '$0 ~ h {f=1} f && $0 ~ n && !($0 ~ h) {exit} f' "$1"; }
$ diff <(sect before '^### §0\.2 ' '^### §0\.3 ') <(sect after '^### §0\.2 ' '^### §0\.3 '); echo rc=$?
rc=0 (24 lines)
$ diff <(sect before '^### §8\.3a ' '^### §8\.3b ') <(sect after '^### §8\.3a ' '^### §8\.3b '); echo rc=$?
rc=0 (29 lines)
$ diff <(grep -E '^\| `(scanned|tool-unavailable|scan-failed|scanned-partial)' before) <(… after); echo rc=$?   # §6.1's status table
rc=0 (5 rows)
$ wc -l before after
3514 4412
```
(The `after` line count is the file BEFORE this §13 addendum was appended; the addendum changes
none of the compared spans.)

**V45 — every marker v2.2 newly cites resolves in the code surface, and every proposed marker is
bare and unminted.** The loop and its output for the cited set (files each resolves in):
```
$ for m in …; do printf '%-32s %s\n' "$m" "$(grep -rl -- "$m" scripts/ init.sh templates/ .github/ | wc -l)"; done
BL-209-HOOKSPATH-SAME-DIR 1   BL-209-HOOKSPATH-REFUSE 1   BL-233-WPB-MANIFEST-DECL 1   BL-243-HOOK-TEMPLATE 1
BL-072-TDD-ENFORCE 2   BL-233-ATTEST-REFUSE 2   BL-284-CONTEXT-STATE 1   BL-242-PREFLIGHT-TEMPLATES 1
BF-ADOPT-SHA-REQUIRED 2   BL-225-REFUSE-HONEST 3   BL-225-PREWRITE-REFUSE 1   BL-225-STAGE-PREFLIGHT 2
BL-225-REFUSE-DERIVED 1   BL-242-RESOLVER-NO-EXEC 1   BL-242-SECRETS-RESCAN 1   BL-288-RESCAN-PARTIAL 1
BL-242-RESOLVER-REFRESH 1   BL-242-PHASE0-LANDING 1   BF-ADOPT-RESTAMP-REFUSE 1   BF-ADOPT-STAMP-CALL 1
BF-ADOPT-STAGE-EXPLICIT 1   BL-225-PREWRITE-CALL 1   BL-225-WRITE-PHASE-REAL 1   BL-225-TOUCHED-DISK 5
BF-ADOPT-ARCHIVE-SCAN 1   BF-ADOPT-ARCHIVE-PROJECT 1   BL-221-ADOPT-TIER-KEYS 1   BL-268-MODE-VOCABULARY 4
BL-253-POC-NULL 1   BL-242-APPROVAL-LOG-FIRST 1   BL-242-PREFLIGHT-CALL 1   BL-215-CORE-GLOB-SYNC 2
BL-225-TOUCHED-UNBOUNDED 3   BL-204-PREFILL-READ 2   BL-202-INTAKE-PREDICATE 3   DELTA-OPEN-ERA-GUARD 2
DELTA-RESUME-PHASE4 1   DELTA-ERA-REPORT-ONLY 1   SCOUT-SECRETS-ALLOWLIST 1   BL-288-SHALLOW-SCOPE 1
BL-251-PROBE-HOST 1   BL-242-GATE-OK-LINE 1   BL-242-ORCH-SOURCE 1
$ for m in <the sixteen proposed markers of §10>; do … in-code:N  backticked-or-hashed-in-doc:N; done
every row: in-code:0  backticked-or-hashed-in-doc:0    # after one fix: the §10 preamble's EXAMPLE was backticked (1) and is now bare
```
Every cited row is non-zero; `scripts/lint-bl-markers.sh` is the standing check on the `BL-`
half and its result on the amended tree is in §13-U(v2.2); the `BF-`, `DELTA-` and
`SCOUT-` tokens are outside that lint's scope and are checked only by this loop.

**V47 — a repository whose git template carries no `hooks/`, and what the WP9d precheck reads there.**
The condition behind the correction in §10-WP9d item (6) and the fixture rule above its R1 proofs.
```
$ mkdir -p /tmp/empty-template/info
$ cd "$(mktemp -d)" && GIT_TEMPLATE_DIR=/tmp/empty-template git init -q .
$ [ -d .git/hooks ] && echo yes || echo NO
NO
$ [ -w .git/hooks ]; echo rc=$?          # the predicate WP9d item (6) carried until 2026-09-17
rc=1                                      # FALSE — every such repository would be refused at step 0
$ [ -w .git ]; echo rc=$?                 # the parent, which §8.1's row named and item (6) did not
rc=0
$ cd "$(mktemp -d)" && git init -q . && [ -d .git/hooks ] && [ -w .git/hooks ]; echo rc=$?   # stock template
rc=0
$ GIT_TEMPLATE_DIR=/tmp/empty-template bash tests/test-brownfield-wp1-scout.sh </dev/null | tail -1
Results: 33 passed, 2 failed
$ bash tests/test-brownfield-wp1-scout.sh </dev/null | tail -1
Results: 35 passed, 0 failed
$ GIT_TEMPLATE_DIR=/tmp/empty-template bash tests/test-brownfield-wp9b-preflight-approval.sh </dev/null | tail -1
Results: 103 passed, 0 failed
```
**And why the predicate is a CONDITIONAL and not the disjunction the first draft of this correction
wrote.** An existing hooks directory that is read-only satisfies the parent arm and refuses the
write anyway, so a disjunction moves nothing to step 0 in the one case the precheck is for; and a
`.git` at 555 is not a usable fixture, because git stops before the hook write.
```
$ cd "$(mktemp -d)" && git init -q . && chmod 555 .git/hooks
$ [ -w .git/hooks ]; echo rc=$?          # the directory EXISTS and is not writable
rc=1
$ [ -w .git ]; echo rc=$?                # the parent IS writable — a disjunction passes here
rc=0
$ printf '#!/bin/sh\n' > .git/hooks/commit-msg
permission denied: .git/hooks/commit-msg  # …and the write is refused regardless
$ chmod 755 .git/hooks && chmod 555 .git && git status --short >/dev/null && echo ok
ok                                        # reads still work
$ echo x > f.txt && git add f.txt
fatal: Unable to create '.../.git/index.lock': Permission denied
```
The last line is why the omission was invisible to this design: the fixture every WP9d and WP10b
proof builds on happens not to write a hook, so it carries the property in without stating it.
`adopt_install_hooks` itself is unaffected — it has always run `mkdir -p` on the directory it is
about to write (soon the RESOLVED one, R1) — so this is a defect of the PRECHECK the package adds,
not of the driver it adds it to.

**Recorded by the independent review of the 2026-09-17 correction, not fixed here.** (1) Case (ii)'s
fixture LEAKS: the rehearsal copies the 555 directory, so the driver's own cleanup cannot remove it —
about fourteen `rm: … Permission denied` lines and a surviving `$TMPDIR/adopt-work.*` tree; the cell
must tell the implementer to restore the mode before cleanup. (2) Case (iii) inherits case (ii)'s ROOT
vacuity and the cell flags it only on (ii); the cell also does not say what the fixture DOES when it is
root (skip, or fail). Case (i) is root-insensitive — `access(2)` returns `ENOENT` for root too. (3) The
ORDER of item (6)'s precheck and R1's placement refusal is unstated and both are *"step 0"*: `git
rev-parse --git-path hooks` honours `core.hooksPath`, so a hooksPath pointing at a non-existent parent
makes item (6) refuse first, naming an unwritable hooks directory where the remediable condition is the
configured hooksPath R1 prints the `git config --unset` remedy for. (4) §13-V47's `permission denied:`
line is ZSH's wording; under `/bin/bash` 3.2.57 the same command prints `.git/hooks/commit-msg:
Permission denied` with a script-and-line prefix, and the suites run under bash — §12 item 18 labels
its shell and V47 does not. (5) The `chmod 555 .git/hooks` proof is now specified TWICE in the WP9d
cell — item (6) case (ii) and the R1 block's pre-existing precheck proof — which differ in detail (the
older asserts the `[REFUSED]` label and *nothing written*; the newer asserts the commit's presence).
Two specs for one proof invite drift; merge them when WP9d is built.

**V48 — the three hooks-path shapes R1's extension and M16 refuse, measured rather than argued.**
Re-derived here on 2026-09-17 rather than transcribed from the review that found them.
```
$ # A — .git/hooks is a SYMLINK to a writable directory OUTSIDE the repository
$ git init -q . && rm -rf .git/hooks && ln -s "$SHARED" .git/hooks
  [ -L ] rc=0   [ -d ] rc=0   [ -w ] rc=0        # passes EVERY test the write check can make
$ printf '#!/bin/sh\n' > .git/hooks/commit-msg
  write rc=0, and the file is at $SHARED/commit-msg — OUTSIDE the repository
$ git rev-parse --git-path hooks
.git/hooks                                        # the LINK path: the derived sentence re-resolves
                                                  # through it and prints TRUTHFULLY
$ # B — a DANGLING .git/hooks symlink
  [ -L ] rc=0   [ -d ] rc=1   [ -w .git ] rc=0    # the conditional takes the PARENT arm and passes
$ mkdir -p .git/hooks; echo rc=$?
mkdir: .git/hooks: No such file or directory
rc=1                                              # fails AFTER the adoption commit
$ # C — .git/hooks present as a REGULAR FILE
  [ -L ] rc=1   [ -d ] rc=1   [ -w .git/hooks ] rc=0   # writable — as a FILE
$ mkdir -p .git/hooks; echo rc=$?
mkdir: .git/hooks: File exists
rc=1                                              # fails AFTER the adoption commit
$ # control — an ordinary repository
  [ -L ] rc=1   [ -d ] rc=0
```
**A is why the ruling is a SHAPE rule and not a stronger write test.** No predicate over writability
can separate A from the ordinary case: the link is a directory, it is writable, the write succeeds,
and `--git-path hooks` reports the link's own path, so the re-resolution §10-WP9d item (3) performs
follows the link and finds the hook it just wrote. The sentence is true and the hook is not this
repository's. Only asking *is the path a symlink* answers it — which is why
`# BL-145-SYMLINK-GUARD-BEGIN` asks exactly that, and why its header records that a LEAF test is not
enough. C is the shape that also defeats the write test in the other direction: `[ -w ]` on a
writable regular file is rc 0.

#### §13-U(v2.2) — added 2026-09-17

- **The two rulings themselves (R1, R2).** Recorded from the maintainer's brief for this
  amendment, which stated each ruling's content and attributed it to Karl on 2026-09-17; no
  transcript was seen. §0.1a records them in substance, not verbatim, and says so.
- **The submodule row of §2.1.** Reasoned from the gitfile shape a submodule checkout shares with
  a linked worktree; a submodule was not created and measured. The linked worktree WAS (V31, V32c).
- **Two facts §6.2b now rests on were found by the REVIEW's probes, not by v2.2's first run:** that
  gitleaks reads `.gitleaksignore` from the process cwd (`--gitleaks-ignore-path` defaults to `.`),
  and that `git clone --shared` is silently ignored for a shallow source. Both were re-executed by
  this author from the review's `v35.sh` and printed as V35b; the review's own outputs are the
  first measurement and are identical.
- **The sub-directory and worktree shapes (V32b, V32c)** were executed first by the review
  (`v32b.sh`, `v32c.sh`) after v2.2's first cut described them by reasoning; re-run here with the
  same outcome.
- **Three git version floors** (§8.1, §12 item 31): `--is-shallow-repository` ≥ 2.15,
  `--path-format=absolute` ≥ 2.31, and `git clone --shared --no-checkout` from a shallow source —
  every measurement here is git 2.54.0; the floors are git's documentation, not this host.
- **gitleaks versions other than 8.30.1.** The config-precedence, `--gitleaks-ignore-path` and
  `[extend] useDefault` behaviours in V35 are one version's. `## BL-289:`'s floor question stands.
- **A partial clone (`--filter=blob:none`)** — `## BL-288:`'s measurement, not re-run here (§2.1).
- **The `SOIF_ADOPT_REHEARSAL_MAX_MB` default of 2048** is a choice, not a measurement; V36
  measures one repository.
- **The CDF install** (`~/.claude-dev-framework/scripts/init.sh`) was not run; row 33 and V38 rest
  on reading `init.sh`'s nesting, not on executing the branch.
- **`## BL-274:`'s attestation mechanism on the contributor's fork (`fix/bl274`)** was not
  fetched or read; §2.1's known-limit row rests on `## BL-274:` and `## BL-275:` as they stand on
  `main`.
- **#418's `pnmp` being in the adopter's `package.json`** cannot be verified from here; what is
  verified is its absence from this framework's code and shipped pages (V37).
- **The linked-worktree measurement used `git worktree add` in a scratch repository under
  `mktemp -d`**, not in this checkout; the command's block in CLAUDE.md is about this checkout.
- **Linux.** No suite or probe was run in a container for this amendment; every measurement is
  this darwin host's (case-insensitive filesystem, `core.ignorecase = true`), which is why V34's
  case-variant result is stated as this filesystem's and the WP11 proof SKIPS elsewhere.
- **The wp10a, wp9b, bl225, bl253, bl268 and bl288 suites were NOT re-run for this amendment**;
  §13-V24's 2026-09-16 results stand as that date's. The one unit-lane suite that reads this
  file was run and is recorded below.
- **§12's items read 1–16, then 23–31, then 17–22 in file order.** The numbering is unique and every
  cite resolves; the ORDER is not monotonic, because v2.2's items were appended to the list's first
  block rather than to its end. Recorded rather than renumbered: the numbers are cited from §10 and
  from `## BL-290:`–`## BL-296:`, and renumbering them here would break those cites for a reader
  holding the earlier text. The restructure pass owns it.
- **Lints and the one suite on the amended tree — RUN, recorded here rather than claimed above:**
  `bash scripts/lint-bl-markers.sh` → *OK: 606 marker token(s) resolve to backlog entries and 1004
  prose citation(s) resolve to live markers* (958 on the v2.1 second pass — the growth is this
  amendment's backticked cites, every one resolved by V45's loop before the lint saw it). **The
  figure is 1004 and not the 1000 this bullet first carried**: the number was recorded before the
  review-fix pass, whose own citations moved it — the review's R-6, and the fourth time in this
  document's life that a count was written down before the edits that changed it were finished. The
  rule it re-teaches is the one §13's preamble already states: re-run the derivation, do not carry
  the number forward;
  `bash scripts/lint-doc-anchors.sh` → *OK: no broken in-document anchors across 112 file(s) — 111
  markdown under docs, plus workflow.html* (the 112 again counts the two untracked handoff files in
  this working tree, as §13-U(v2.1) noted; 110 in a clean checkout); `bash scripts/run-lints.sh` →
  *run-lints: 16 lints — 16 passed, 0 failed*, rc 0; `bash tests/test-brownfield-wp9-act-boundaries.sh
  </dev/null` — the one unit-lane suite that reads this file (its C2 sweep) → *Results: 29 passed,
  0 failed*, rc 0. All four were run AFTER every other edit and before this paragraph was written;
  the two lints were re-run after it and reported the same lines (the amendment's report carries
  that re-run). These are the checks; they do not read this document's prose for truth, which is
  what the V-blocks are for.

---

## Self-review pass (fresh-eyes checklist)

- **Every commissioned element present?** Document Control with a derivation-based status row; the
  supersession-and-overturning statement in front matter, §0.2 and §4.1 rather than a footnote;
  the plain-English overview in the messaging standard's five-part shape; §0.1's ten decisions
  with Karl's D4 reasoning verbatim; the four acts with the phase-0 landing's load-bearing
  argument (§3.6); the **tier-scoped** secrets check with all three statuses (§6.1) *(four statuses since 2026-09-12
  and five rows since 2026-09-16 — §6.1a)*, with
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
- **v2.2's own attack surface, named rather than defended (2026-09-17).** (1) §6.2b rests on
  gitleaks' config-precedence and `--no-checkout` semantics as measured on 8.30.1 and git 2.54 —
  §13-U(v2.2) says what was not measured elsewhere. (2) The window's `--finish` trusts a persisted
  write set an operator can edit; the staging preflight and the *not on disk* refusal bound it,
  and the audit trail is the control, as for every other operator-editable record here. (3) R2's
  predicate reads a boolean in a file the operator can hand-edit to `true`; that is the same
  trust boundary as the tier answer (§6.2b) and is recorded, not closed. (4) §2.1's submodule row
  and three git floors are reasoned, not measured. (5) Two of the four measured defects are
  designed into packages that have not been built; until they are, the plain-English overview's
  *four things found broken* paragraph is the only carrier a reader meets.
- **Biggest attack surface for the reviewer.** (1) §5's dissolution of certification into
  assessment — the claim that no rung — claimed or landed — leaves the certification pass without an object is the
  deepest structural consequence drawn from D4 and D10, and a reviewer should try to construct a case
  where a project needs gate-by-gate certification that the assessment record does not subsume.
  (2) §8.7's admission that the skip set is unenumerated — the init-parity audit is scheduled, not
  done, and until it lands this design cannot claim Act 2 is complete. Both are flagged rather
  than defended. *(Superseded 2026-09-01: the audit is delivered at §8.7a, and re-measured on
  2026-09-16 (§13-V27); left as the v2.0 self-review's text.)*

---

## Questions for the reviewing architect

Seven, each attached to a decision this design can still change. **Every question that was Karl's
is now ruled** — §12's items 12 through 15, all decided on 2026-08-31 and kept struck there as
part of this document's record. Nothing below is waiting on him; these are the reviewer's.

1. ~~**The assessment record's schema (§3.4, §5.2).** This design requires it and does not fix its
   shape. Should v2 pin a schema now (reviewable, lintable, rigid) or let WP12's build propose one
   (informed by the first real assessment, unreviewed until then)?~~ — **ANSWERED (2026-09-17):
   PINNED, in §8.3, because the architect's B1 showed that without a shell surface the WP12a/b
   proofs had nothing to bite; the finisher validates against it.**
2. **The re-scan boundary (§6.2).** Act 2 re-runs the secrets scan when the consumed report's
   status is not `scanned`. Should it *always* re-scan — a consumed report can be stale in
   findings, not just in status — at the cost of doubling the slowest step on large histories? *(WP10a built the narrow reading:
   re-scan only when the consumed status is neither `scanned` nor `scanned-partial` —
   `# BL-242-SECRETS-RESCAN`, `# BL-288-RESCAN-PARTIAL`. The question stands.)* — **ANSWERED
   (2026-09-17) for the STOP: it always scans, itself, under the framework's rules, over a
   no-checkout copy — §6.2b; the re-scan guard is unchanged for what it governs.**
3. ~~**The document-set boundary (§7.2).** The framework-required set is derived from `init.sh`'s
   writers. Is that the right universe, or should the phase gates' *readers* define it — the two
   derivations may not agree, and whichever is chosen, the other is a drift check WP11 could pin.~~
   — **ANSWERED (2026-09-17): `init.sh`'s writers ∪ Act 4's write set, as DATA (`_adopt_document_set`),
   with the two-way drift check §7.2 spells; the gates' readers were not chosen because a document
   the gate reads and nobody writes is a gap to file, not a row to archive.**
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
6. ~~**WP sizing.** WP12 carries Acts 3 and 4 whole — the fifth branch, the interview, the record,
   the writers, the verdict, two page revisions. Split it (branch + record first, verdict +
   documents second), or is the seam artificial because nothing in the first half is shippable
   alone?~~ — **ANSWERED (2026-09-01): SPLIT, as §10's WP12a/WP12b rows now read.** The review
   recommended it twice and the second half of the question was refuted by the feature's own
   history: the honest `adopt_stub_*` notice pattern exists precisely so a package can ship with
   its unbuilt neighbours announced, so "nothing in the first half is shippable alone" was never
   true here. The seam moved after D10 and improved — see §0.3's 2026-09-01 entry.
7. **The one rule we have not written.** What is the adoption-shaped project in *your* drawer that
   this flow mishandles — and is it a missing interview question, a missing archive class, or a
   reason the four-act shape itself is wrong for it?

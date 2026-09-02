# Brownfield adoption — bringing an existing project into the framework

`init.sh` builds a project from an empty folder. **Adoption is the second way
in**, for a codebase that already exists — with its own history, its own
pipeline, and its own habits.

```bash
cd /path/to/their-project
bash /path/to/solo-orchestrator/scripts/adopt-project.sh
```

> ## ⚠ Read this before you plan around adoption
>
> **Adoption is half built.** The driver, the tier question, the reverse
> intake's confirmation arm, the state writes, the adoption stamp, the
> commit-time enabling arms, the test-debt ledger with its ratchet, and the
> collision archive with its disclosure and recorded re-adds all ship and all
> work. **The assessment — the requirements interview, the fitness verdict and
> the plan — does not exist, and neither do the CI carve-out or the Adoption
> Record.**
>
> **This page describes the four-act v2 design.** Adoption is Act 2 of four:
> Act 1 is Scout, and Acts 3 and 4 are a Claude Code session that has not been
> built. What ships today ends by handing off to `bash scripts/resume.sh`.
>
> The driver does not paper over that. It prints a labelled `NOT DONE` block for
> every one of them, in the run, naming the work package that owns it. The full
> list — with the exact text it prints — is in
> [What is not built yet](#what-is-not-built-yet). Read that section before you
> decide whether adoption gets you where you need to be today.

Everything on this page is output that was observed, pasted as it printed.

---

## Contents

- [Before you adopt: run Scout](#before-you-adopt-run-scout)
- [The one question](#the-one-question)
- [Where it lands: phase 0, always](#where-it-lands-phase-0-always)
- [The reverse intake](#the-reverse-intake)
- [What gets written, and in what order](#what-gets-written-and-in-what-order)
- [The adoption stamp, and what happens when it is lost](#the-adoption-stamp-and-what-happens-when-it-is-lost)
- [The TDD exemption and its bound](#the-tdd-exemption-and-its-bound)
- [The test-debt ledger and its ratchet](#the-test-debt-ledger-and-its-ratchet)
- [What is not built yet](#what-is-not-built-yet)
- [Exit codes](#exit-codes)

---

## Before you adopt: run Scout

[Scout](scout.md) is the read-only survey. It changes nothing, and the driver can
consume its report instead of re-scanning:

```bash
bash /path/to/solo-orchestrator/scripts/scout.sh --out ./scan
bash /path/to/solo-orchestrator/scripts/adopt-project.sh --scan-report ./scan/scout-report.json
```

Run it first. It is the cheapest way to find out that this project has an AWS key
in its history, or a `.git/hooks/pre-commit` you would rather not lose.

### Options

```text
$ bash scripts/adopt-project.sh --help
adopt-project — bring an existing project under the framework.

  cd /path/to/their-project
  bash /path/to/solo-orchestrator/scripts/adopt-project.sh [options]

  --root DIR          the project to adopt (default: the current directory)
  --scan-report FILE  consume this Scout report instead of running a new scan
  --re-add PATH       put one of YOUR archived files back, warned and recorded
  --version           print the driver's version and exit
  --help              print this and exit

--re-add is the other half of the collision archive and it does NOT run an
adoption. Point it at one of your own files as the archive MANIFEST names it
(for example .git/hooks/pre-commit); it shows you what the framework thinks
that trade costs, asks you to confirm, puts the file back exactly as it was,
and records the choice in the audit trail. The framework's premise is
opinionated enforcement, not confiscation — your files are yours.

What it does, in order: reads the survey, offers what the survey found as
EVIDENCE, asks who the project is for, confirms the answers the survey already
derived, writes the project's state at phase 0, records the adoption, and
commits exactly the files it wrote.

Your project starts at phase 0 whatever the survey found. Nothing is marked as
already done and no shortcut is taken past any gate — the questions about what
this project is and what it is for are asked afterwards, in Phase 0.

If it stops partway — because you stopped it, or because a question had no
answer — it stops in the SAFE direction: the project ends up more strictly
gated than it was, never less.

Exit codes: 0 adoption completed; 1 adoption did not complete (a refusal, a
blocker, or a halt); 2 bad usage or an unusable target.
```

**Why this is a separate script and not `init.sh --brownfield`.** `init.sh`'s
interactive path has no existence check and twelve unguarded overwrite sites. A
`--brownfield` flag would mean auditing every one of those for a mode that must
never reach them; a separate driver makes them unreachable by construction. The
driver never calls `create_project()`.

---

## The one question

Before it asks anything, the driver shows what the scan noticed — as **evidence
that decides nothing**, each line carrying its own confidence:

```text
══ What the scan noticed
   This is what a read-only look at your code found, and each line says how much
   weight it deserves. It is here so you can see it, not so you can act on it.

   Deployment: the scan found .github/workflows/deploy.yml (a deploy or release lane).
     Points to: built out. Confidence: LOW — this is file presence, not run history;
     Scout is read-only and does not ask the host whether the lane has ever run.
   Release tags: 2 version-shaped tag(s); newest v2.4.0 2026-08-10.
     Points to: built out. Confidence: MEDIUM — tags are cheap and often abandoned.
   Recent work: over the last 50 commits, 1 look like new features and 2 look like fixes.
     Points to: built out. Confidence: LOW — this is a heuristic and it is labelled as one.
   Changelog: CHANGELOG.md lists 2 released version(s).
     Points to: built out. Confidence: MEDIUM.

   Users: the scan cannot measure whether anyone is using this. Only you know that.

   None of this decides anything. Your project starts at phase 0 either way and
   earns each gate the ordinary way; what the scan found becomes a head start on
   the Phase 0 questions, never a shortcut past them.
```

Then it asks **one question**, and it is not about your code:

```text
Who is this project for?
   1) Just me, or me and a few people I know
   2) A company, a client, or people who are paying for it
   Answer with the number or the words:
```

**There is no default and no skip.** With no answer:

```text
[REFUSED] This question has no default and no skip, and no answer was given: who the project is for
          Adoption did not begin. Nothing was committed and nothing was written.
```

That answer sets your project's **tier**, and the tier decides how strictly the
framework treats you — most visibly, how hard it stops when a secret scan finds
something. It is the one thing adoption asks because it is the one thing no
amount of reading your code can determine.

---

## Where it lands: phase 0, always

**Every adopted project lands at phase 0.** Not at a phase derived from your
artifacts, not at one you claimed, not "provisionally" pending a later
promotion. Phase 0, and then forward through the ordinary gates like any other
project.

```text
══ Act 2 complete — the project is adopted and sitting at phase 0
   Your project is now under the framework and it starts where every project
   starts: phase 0. Nothing has been marked as already done, and nothing was
   guessed about how far along you are — you will be asked about that instead.
```

### Why it does not ask how far along you are

An earlier version of this driver asked. It put one question to you — *is the
project built out, or are you still building it?* — and used your answer, floored
by what the scan could corroborate, to decide which phase to place you at.

That question is **deleted**, and so is the idea of computing an answer in its
place. The reasoning is short: you are using this framework because you are not
already following a formal software process, so asking you to grade your own
position within one is asking the wrong person. And deleting a question whose
answer cannot be trusted does not mean the answer must be computed some other
way — it can equally mean the question does not need answering. Here it does not.

**What you lose is nothing you had.** A phase is not a score; it is a statement
about which gates have been crossed with evidence. Placing a project at phase 3
without that evidence produces a project that fails its own next gate — the
gates are cumulative by contract, so each one assumes every earlier one really
happened. Landing at 0 costs you the walk through Phase 0 and buys you a project
whose recorded position is true.

**What the scan learned is not thrown away** — though be precise about where it
goes. Scout's **intake-prefill table** is what becomes pre-fill: the cells the
scan could derive are confirmed with you and written into `PROJECT_INTAKE.md`.
The artifact ladder, the test-debt census and the reality probes become
**context** — they are committed with the project (`.claude/adoption/`
`scout-report.json`, `.claude/test-debt.json`) and the §13 prompt points an
agent at both. What none of it becomes is a shortcut past a gate. A project that
already has tests, a deploy lane and architecture docs gets an intake that says
so. What it does not get is a shortcut past a gate.

### What every adoption gets

- **The full secrets scan.** History does not care what phase you land at.
- **No forward exemption.** Every exemption in this design is scoped to commits
  **at or before** the adoption commit. There is no arm anywhere that exempts a
  commit written after adoption day.
- **The same demand set as a greenfield project.** Strip the adoption record out
  of an adopted project and its gates ask for exactly the same things.

---

## The reverse intake

Ordinary intake asks a person and writes a document. Reverse intake starts from
what the scan already derived and asks you to confirm it — for the parts that are
derivable, and only those.

```text
══ The interview
   Some of this the scan already answered — you will see the answer and where it
   came from, and you can keep it or change it.
   The rest is not asked here. Questions only a person can answer belong to the
   assessment, which is a conversation with an agent rather than a form, and this
   step leaves those cells blank for it.

Project Identity
   The scan found: legacy-app
   Where that came from: package.json name
Keep 'legacy-app' as the answer?
   1) keep it
   2) change it
   Answer with the number or the words:
```

Three classes across the fifteen intake sections — and **this step now asks
exactly one of them**:

| Class | Behaviour here | Example |
|---|---|---|
| **Scan-derived** | **ASKED.** Prefilled with **the value and its provenance**, then keep-it / change-it. "Change it" falls through to the ordinary question | Project Identity, Repo Setup, Testing & Bug Tracking, Tooling Configuration |
| **Judgement** | **NOT asked here.** Recorded blank and named as the assessment's | Business Context, Constraints, Features & Requirements, Technical Preferences, Revenue Model, Governance Pre-Flight, Accessibility, Distribution & Operations, Known Risks |
| **Non-skippable** | **NOT asked here** either — see below | Data classification |

**Why the questions only you can answer are not asked here.** They belong to the
**assessment** — a conversation with an agent about what this project is and what
it is supposed to do, rather than a form. Filling a form badly at the end of a
shell script is not the same as being interviewed, and the answers feed a fitness
verdict that needs the reasoning behind them.

Cells left blank are **recorded as blank and labelled**, not dropped:

```text
Business Context
   Not asked here — this one is asked in the assessment.
```

**Data classification moved with them, and that is worth explaining rather than
just noting.** It used to be refused-if-skipped right here, and the reason given
was mechanical: the Phase 1→2 ZDR backstop hard-`[FAIL]`s whenever
`current_phase >= 2`, and an adoption used to be able to land at phase 4 on its
first commit. **It cannot any more** — every adoption lands at phase 0.

The backstop fires at `current_phase >= 2` **however that number is reached**,
and it is a hard failure rather than a warning. That is deliberately not the
same claim as *"you cannot get to phase 2 without answering"*: other framework
commands can advance the number (`scripts/process-checklist.sh` does, when it
verifies your Phase 2 setup). What holds is that the gates are **cumulative and
keyed to evidence** — arriving at a rung without the evidence fails the gate on
the evidence, regardless of what moved you there.

**Adoption now writes `APPROVAL_LOG.md`, and the gate runs.** Until WP9b it did
not, and the gate exited on the missing file before it read the phase at all —
so an adopted project could not run its own phase gate. Observed on a
freshly-adopted project today:

```text
$ bash scripts/check-phase-gate.sh
Phase Gate Consistency Check
Current phase: 0


Adoption Stamp Integrity
[OK] Adoption stamp present and intact (adopted: …)

Phase gates consistent.
```

The log adoption writes is the **tier-matched template**, carrying no dated
gate-approval row — because this adoption approved nothing. It makes the
question answerable; it does not answer it. What is still missing is the
Adoption **Record** inside that log, which is WP7's.

**You will still be asked.** Three routes reach the question, and all three are
exercised by the test suite rather than assumed:

| Route | What it does |
|---|---|
| `bash scripts/resume.sh` | What the run tells you to do next. It prints the initialization prompt from this project's own Section 13, and that prompt names the classification as **not optional**. |
| `bash scripts/intake-wizard.sh --resume` | Walks the intake from Section 1, which includes **Section 5 — Data Classification**. |
| `bash scripts/reconfigure-project.sh --field data_classification --new <value>` | The escape hatch the Phase 1→2 gate names in its own failure message, if you get there first. |

> **Not built yet:** the assessment is Act 3 and it has not shipped, so those
> cells stay blank until you fill them through one of the routes above. The
> direction is fail-closed: a project with no classification cannot cross its
> Phase 1→2 gate.
>
> Every one of those three routes was **broken on an adopted project** until
> this was built, and none of the breakages announced itself — one pointed at a
> section that did not exist, one crashed internally and then reported success
> having skipped the question, and one died on a file adoption never wrote.
> They are recorded here because "you will be asked later" is worth exactly
> what an execution of the asking says.

An out-of-vocabulary answer to a choice question is refused by name rather than
coerced:

```text
[REFUSED] 'legacy-app' is not one of the answers offered for: who the project is for
          Adoption did not begin. Nothing was committed and nothing was written.
```

---

## What gets written, and in what order

### The order is `APPROVAL_LOG.md` → `phase-state.json` → intake → `manifest.json`

That order is data in the driver, not scattered through it, and it is chosen
because the two half-states are **not symmetrical**:

| Partial state | `check-phase-gate.sh` | Enforcement tier | Net |
|---|---|---|---|
| **phase-state present, manifest absent** | Runs to a verdict. At the resting state that is `Current phase: 0` / `Phase gates consistent.` → rc 0 | **strict** (missing manifest → strict) | **Gates live, strictest tier.** The commit-time ladder is what protects this row; before WP9b the phase gate appeared to block it, but only because `APPROVAL_LOG.md` was missing — an incidental refusal, not a consistency verdict |
| **manifest present, phase-state absent** | `No .claude/phase-state.json found — skipping phase gate check.` → rc 0 | reads the field | **Gates entirely absent.** An adopted-looking project with no enforcement |

Writing the approval log and phase-state **before the manifest** means no
interruption can land in the bottom row. That is what the help text means by
*"it stops in the SAFE direction: the project ends up more strictly gated than
it was, never less."*

Since WP9b there is a third interruption point, between the approval log and
phase-state, and it is inert: with no `.claude/phase-state.json` the gate prints
`No .claude/phase-state.json found — skipping phase gate check.` and exits 0,
exactly as it does on any project that has never been adopted. A log with no
phase-state claims nothing. **That is why the log goes first** — written last,
every death inside the state stage would land on phase-state-present /
log-absent, which the gate hard-refuses.

`init.sh` uses the opposite order, and that is not a counter-example: creation is
one uninterrupted run ending in a commit, so it never leaves partial state
behind. Adoption can legitimately halt at a question or a blocker.

### A halt before the writes leaves nothing at all

Measured, hashing every non-`.git` file before and after a run that halted at the
data-classification question:

```text
tree before: c57773947041bac7f2b0d16fbd012b4318c232fe  -
tree after : c57773947041bac7f2b0d16fbd012b4318c232fe  -
IDENTICAL — a halted run wrote nothing
```

### Staging is explicit, never `git add -A`

```text
══ Committing exactly what was written
   77 file(s), named one by one. Anything else you had in progress stays
   exactly as you left it — unstaged, uncommitted, untouched.
```

The driver builds an explicit array; anything not in it is never staged. The
counter-example this exists to avoid is `create_project()`'s
`git add -A` + `git commit --no-verify`, which on an existing project would sweep
your uncommitted work into a framework commit with verification bypassed.

Observed on a completed run — one commit,
`chore: adopt <project> into the Solo Orchestrator framework`, containing **77**
files: the nine below, and the framework `scripts/` tree (68 of them).
**Your own files are not in it.**

```text
.claude/adoption/scout-report.json   .claude/intake-progress.json
.claude/manifest.json                .claude/orchestrator-source.json
.claude/phase-state.json             .claude/process-state.json
.claude/test-debt.json               APPROVAL_LOG.md
PROJECT_INTAKE.md
```

*(This list read six files and 69, then eight and 76, before each re-measure. It
had been correct when written and has now been falsified three times over — by
the test-debt ledger WP5b added, by `orchestrator-source.json`, and by
`APPROVAL_LOG.md`, which **WP9b added while this very paragraph warned that
whoever adds a writer must re-run the count**. An enumeration
of what a run writes has to be re-run by whoever adds a writer; nothing checks
it.)*

### What lands in `scripts/`

```text
══ Installing the framework's own scripts
   Installed 68 framework script(s); left 0 of your own file(s) untouched.
```

The set is **derived from `init.sh`'s own copy list** rather than duplicated, so
an adopted project's script set cannot drift from a scaffolded one's. Measured,
comparing this adopted project against a project scaffolded by `init.sh` on the
same tree: **68 scripts each, and the difference in both directions is empty.**

The commit-msg hook comes from the same emitters `init.sh` uses. Measured — the
adopted and the scaffolded project's `.git/hooks/commit-msg` have the **same
SHA-1** (`6a68f4e3…`, 154 lines):

```text
adoptee:    6a68f4e3f1b5a8e00e830ec2073229736aa58df7  (154 lines)
demo-delta: 6a68f4e3f1b5a8e00e830ec2073229736aa58df7  (154 lines)
```

```text
══ Turning the gates on
   Commit-msg gate installed (it composes with whatever was already in that hook).
```

---

## The adoption stamp, and what happens when it is lost

Adoption writes one additive block into `.claude/manifest.json`. Observed:

```json
{
  "schemaVersion": 2,
  "adopted": true,
  "adoptedAt": "2026-08-10T20:18:37Z",
  "adoptedAtCommit": "c0ba12ef6ecd620b57c55581435138f53a098da2",
  "scannerReportSha256": "c5ac90a264f61d55cb3423151d04f8161bf671e3272d09fe14fabad80f302efd"
}
```

**Five keys, and the four that left are as informative as the five that
stayed.** `scenario` went with the question that produced it; `landedPhase`
went with the idea of deriving a phase at all; and `certification` and
`blockersAccepted` went because the pass that filled them is retired and three
permanently-empty arrays read as "measured, nothing found" to anyone who does
not know the history. `schemaVersion: 1` in a manifest means a record written by
the earlier driver, which carried all four.

It is written **once**, from **one** call site, and never re-stamped. A second
stamp attempt is refused rather than overwriting the anchor.

### The loss cannot be prevented — so it is reported loudly

`.claude/manifest.json` has a wholesale writer that lives **upstream, in a
different repository**: a repair path (`verify-install.sh --auto-fix` →
`fix_framework_manifest()`) delegates to the Claude Dev Framework's own
`init.sh`, which rewrites the manifest from a hardcoded key set carrying none of
this framework's keys. It is missing-file-gated, so it never destroys a stamp
that is present — but a manifest lost to any cause is regenerated *empty of
everything this framework wrote*, and the project silently un-adopts.

That writer cannot be stopped from here. So the framework refuses to be quiet
about it. The witness is the **committed** copy of the manifest at `HEAD`, which
a working-copy regeneration does not touch.

Observed — `bash scripts/check-phase-gate.sh` in an adopted project whose working
manifest lost the block:

```text
Adoption Stamp Integrity
[FAIL] Adoption stamp LOST from .claude/manifest.json.
       The copy committed at HEAD records this project as ADOPTED; the working
       copy does not. The project has silently un-adopted: every gate arm that
       reads the adoption flag now reads FALSE, and the certification record of
       how this project entered the framework is gone from the live manifest.
       LIKELY CAUSE: the manifest was missing and a repair path regenerated it
       wholesale from the upstream framework's own key set, which carries none
       of this framework's keys. That writer is upstream and cannot be stopped
       from here — which is why this is reported rather than prevented.
       REPAIR (re-merges only the adoption block, keeps the regenerated rest):
         git show HEAD:.claude/manifest.json | jq '.adoption' > /tmp/adoption.json && \
         jq --slurpfile a /tmp/adoption.json '.adoption = $a[0]' .claude/manifest.json \
           > .claude/manifest.json.tmp && mv .claude/manifest.json.tmp .claude/manifest.json
```

With the stamp intact the same gate prints:

```text
Adoption Stamp Integrity
[OK] Adoption stamp present and intact (adopted: 2026-08-10T20:18:37Z)
```

**One honest residual:** a stamp written but not yet **committed** has no
witness, so a manifest regenerated *inside* the adoption window is a loss this
cannot see. That window is minutes long and ends at the adoption commit.

---

## The TDD exemption and its bound

You cannot go back and write the tests first for code written in 2023. That is
the one requirement adoption genuinely cannot re-run, so it gets an exemption —
and the exemption is **bounded to commits at or before the adoption commit,
nothing after adoption day, ever**.

Precisely: the exemption applies only while the stamp's `adoptedAtCommit` anchor
equals `HEAD` **and** the copy of the manifest committed at `HEAD` does not yet
record the adoption. That is the adoption run itself. **Once the adoption commit
lands, the exemption closes permanently** — the committed manifest now carries
the block, and every later commit is post-adoption by construction.

Observed on an adopted project, on the non-bypassable tier, staging an
implementation file with no test:

```text
$ printf 'feat: add an adder\n' > .git/COMMIT_EDITMSG
$ bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only

[FAIL] BL-072 TDD ordering: 'feat:' commit ships implementation without a matching test.
[FAIL]   Subject: feat: add an adder
[FAIL]   Tier is NON-bypassable (sponsored POC / production) — test-first ordering is ENFORCED.
[FAIL]   Impl files with no accompanying test (none earlier on the branch):
[FAIL]     - src/add.js
[FAIL]   Write the failing test first (test-driven), then re-commit.
[FAIL]   To attest a legitimate exception (RECORDED to tdd_attestations[], not silenced):
[FAIL]     SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='<why a same-commit test is impractical>' git commit ...
[FAIL]   The commit is BLOCKED.
rc=1
```

An adopted project gets **the same commit-time treatment** as a scaffolded one
from its adoption commit onward. As everywhere else in this framework, the tier
decides whether that is a hard block: `deployment: organizational` or
`poc_mode: sponsored_poc` blocks the commit, as above; `personal` and
`private_poc` do not. That predicate is unchanged by adoption — it reads
`.claude/phase-state.json`, which the driver writes correctly, exactly as it does
in a scaffolded project.

> **This used to say the two birth paths write different manifests. They do
> not, any more — `## BL-221:` is Closed (PR #356) and the keys are written.**
> Measured on an adoption at this tree:
>
> ```json
> {"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}
> ```
>
> | Key in `.claude/manifest.json` | Scaffolded by `init.sh` | Adopted |
> |---|---|---|
> | `deployment` | `"personal"` | `"personal"` — from the tier question, its only source |
> | `poc_mode` | `null` | `"production"` |
> | `enforcement_level` | `"strict"` | `"strict"` |
>
> **The paragraph that stood here told you to set those keys by hand, and
> following it would have been actively harmful** — `.claude/manifest.json` is
> where the adoption stamp lives, so a botched hand-edit trips
> `[FAIL] Adoption stamp LOST` and costs you the record of how the project
> entered the framework. It was correct when written and was left behind by the
> fix; it is recorded here rather than deleted because "advice that outlived its
> defect" is worth recognising as a category. **Do not hand-edit the manifest.**
>
> What the paragraph was about is still worth knowing, because it is why the
> keys must never go missing: `assert_choosable` in
> `scripts/lib/enforcement-level.sh` once read `jq -r '.deployment // "personal"'`,
> so an **absent** key resolved to the **permissive** tier while
> `read_enforcement_level` failed *closed* to `strict` on the same manifest —
> two readers, opposite directions. Both halves are fixed: the writer supplies
> the keys and the predicate is fail-closed (`# BL-221-TIER-FAIL-CLOSED`).

---

## The test-debt ledger and its ratchet

The exemption above is the one thing adoption genuinely cannot re-run, so it
does not stand alone: it comes with a **forward equivalent** that is fully
enforced from adoption day. The adoption measures your test debt once, writes it
down, and from then on holds you to two rules about the future.

`.claude/test-debt.json`, written during the run and committed with the rest of
the adoption:

```json
{
  "schema": "test-debt/v1",
  "writtenAt": "2026-08-10T23:08:35Z",
  "atCommit": "0d1effdce6abcb4dbb78253374e0c12357ee3b76",
  "method": "A source file counts as untested when no test file's NAME contains its basename stem and it carries no inline test attribute. This is a name-match heuristic, not coverage: ...",
  "count": 1,
  "files": [
    "src/ledger.js"
  ],
  "audit": [
    {
      "at": "2026-08-10T23:08:35Z",
      "action": "created",
      "atCommit": "0d1effdce6abcb4dbb78253374e0c12357ee3b76",
      "previousCount": null,
      "count": 1
    }
  ]
}
```

### The two arms, and the tier they sit on

| Arm | Rule | `no` | `light` | `strict` |
|---|---|---|---|---|
| **Non-growth** | The untested set may not gain a member | silent | warn | **block** |
| **Touch-repays** | A file in the set that is modified must leave it in the same commit | silent | warn | **block** |

Run it against a staged commit:

```text
bash <framework>/scripts/lib/adopt/adopt-test-debt.sh --check --root .
```

At `strict`, adding a file with no test:

```text
[BLOCKED] test-debt (non-growth): 1 file(s) would ENTER the untested set.
          + src/billing.js
          A test whose NAME carries the file's stem clears it; for Rust, inline #[cfg(test)] counts.
          This project's enforcement tier is strict, so this is a refusal, not a note.
rc=3
```

At `strict`, editing a file that is already in the ledger:

```text
[BLOCKED] test-debt (touch-repays): 1 ledgered file(s) were modified without gaining a test.
          ~ src/ledger.js
          A test whose NAME carries the file's stem clears it; for Rust, inline #[cfg(test)] counts.
rc=4
```

The **same** staged change at `light` — a note, not a refusal:

```text
[WARN] test-debt (touch-repays): 1 ledgered file(s) were modified without gaining a test.
          ~ src/ledger.js
          A test whose NAME carries the file's stem clears it; for Rust, inline #[cfg(test)] counts.
rc=0
```

And at `no`, nothing at all — no output, `rc=0`. That is deliberate and it is
tested in both directions: **a gate that fires at the lenient tier is as wrong
as one that never fires.** A ratchet that blocks a POC project is not a stricter
ratchet, it is the thing that makes people turn the framework off.

| Code | Meaning |
|---|---|
| 0 | Clean, or a tier that does not block |
| 2 | Unusable — no ledger to ratchet against, not a git repository, no `jq` |
| 3 | **Blocked by non-growth** |
| 4 | **Blocked by touch-repays** |

### It is about your code, not the framework's

Adoption installs about sixty of the framework's own scripts into your project.
None of them is ever in your ledger: the census subtracts the framework's
installed inventory, derived from `init.sh`'s own copy list rather than a
hand-kept second copy of it. That holds on **every** write, not just the one the
adoption performs — including the re-baseline this page tells you to run. If the
tool cannot derive that inventory it refuses rather than guessing, because the
alternative is a ledger that demands tests for `check-phase-gate.sh`.

The cost, stated: if you already own a file at a framework path, it is excluded
from your debt too. That path is a collision — the driver refuses to overwrite
it — and the trade is a small under-count instead of a large false refusal.

### Your `.gitconfig` cannot switch the arms off

Every git read the ratchet makes is pinned with `-c core.quotePath=false -c
diff.renames=true`, and both pins are there because their absence was measured:

- without the first, a path like `src/café.js` is rendered quoted and escaped,
  has no recognised source extension, and drops out of the census in silence;
- without the second, `diff.renames=copies` lets a **copied** untested file
  enter the working set at `strict` with no output at all, and
  `diff.renames=false` turns a pure rename back into a delete-plus-add that
  blocks — and keeps blocking after you re-baseline.

Command-line `-c` outranks your repo, global and system config, so these are not
suggestions.

### Renames, and other changes that are not modifications

A **pure** rename of a ledgered file passes. Neither rule is met — the set
gained no member, and nothing was modified — so blocking it would be a
false-FAIL, and an earlier cut that did block it had no way out: re-baselining
put the new path in the ledger and the same rename blocked again from the other
arm. What you get instead is a note, and the run still succeeds:

```text
[NOTE] test-debt: 1 ledgered file(s) were renamed. The ledger still names the old path(s):
          src/ledger.js -> src/ledger-v2.js
          Re-baseline so the debt follows the file:  --write --root .
```

A rename that **also changes the file** is a modification, and the obligation
follows the file to its new path — otherwise `git mv` plus an edit would be a
one-commit way to shed it.

A **mode-only** change — `chmod +x` on a ledgered file — passes for the same
reason: git reports the identical blob on both sides, which is the exact fact
the pure-rename carve-out rests on. Treating one as a modification and not the
other would be two postures for one fact, and the strict one was in the
false-refusal direction.

### Three things it does not claim

1. **"Has a test" is not "is tested."** The ledger answers a filename question
   (plus, for Rust, an inline `#[cfg(test)]` probe), not a coverage question. A
   file with an empty test file beside it satisfies it. The framework has no
   coverage instrumentation in any language, and the `method` field in the file
   says so where the number is actually read.
2. **The ledger is a committed file and you can edit it.** Same property as
   `enforcement_level`: you can route around the block, not around the record.
   Every write appends an `audit` row carrying the count it replaced. Deleting
   the file outright is not a quiet route around the block — at `strict` the
   ratchet then refuses with `rc=2` rather than passing.
3. **Non-growth is weaker than shrinkage.** There is no burn-down schedule. A
   rate is a business decision, and a rate you cannot meet teaches you to
   disable the gate.

**What is still missing, plainly:** nothing yet runs this on every commit. The
commit-time hook belongs to WP7, so today the ratchet is a command you run — by
hand, or from a CI step — not an automatic gate. The tier ladder, both arms and
the ledger are real; the *automatic* part is not.

---

## What is not built yet

This is the honest half of the page. Everything below is **designed and not
built**. The driver prints a labelled block for each one during the run, naming
the work package that owns it — the text below is what it actually printed.

### The assessment — Act 3 — WP12a

```text
NOT DONE — the assessment (Act 3) — the requirements interview, the fitness verdict and the plan
   Owner: WP12a. This build does not do it, and does not pretend to.
   Adoption has surveyed, installed and recorded. What it has NOT done is ask you what this
   project is for, judge whether the technology fits those answers, or write you a plan.
   Until that ships, PROJECT_INTAKE.md carries the cells the scan could fill and leaves
   the rest blank, and the Phase 0 questions are asked the ordinary way instead.
```

This is the largest gap. The assessment is where a person is actually asked what
this project is for — how many people use it, whether it needs high availability,
whether it is internet-facing, what scale it needs, how sensitive its data is —
and where the framework says, **with its reasoning shown**, whether the
technology fits those answers or whether this ought to be rebuilt. The plan comes
out of the same conversation.

**Today, none of that runs.** What you get from adoption is a project correctly
under the framework at phase 0, with a survey on disk and an intake half filled.
The Phase 0 questions still get asked — by the ordinary flow, starting from
`bash scripts/resume.sh` — so nothing is skipped; what is missing is the
judgement layer on top.

### The certification pass — RETIRED, not deferred

This one used to be the largest gap on this page and it is **not going to be
built**. Its job was to certify every gate *below a claimed rung* — the heavier
your claim, the heavier the pass. Two decisions removed its subject: the claim is
gone (nobody is asked how far along they are) and the landing is gone (every
adoption starts at phase 0). With no claimed rung there is nothing to certify
against, and with no landed rung there is nothing to certify for.

**The principle it existed to defend is untouched**: nothing is grandfathered,
every gate is crossed with evidence, and an adopted project's demand set is the
same as a greenfield project's. What changed is that the ordinary gates now do
that job, because the project starts below all of them.

### The test-debt ledger — WP5b — **shipped**

This one used to be on this list and is not any more. The driver no longer
prints a `NOT DONE` block for it: it writes `.claude/test-debt.json` during the
run and both tier-floored arms exist. See
[The test-debt ledger and its ratchet](#the-test-debt-ledger-and-its-ratchet).

The residue is named there rather than hidden here: **nothing invokes the arms
automatically yet**, because the commit-time hook is WP7's. Today it is a
command you run.

### The collision archive, disclosure and re-adds — SHIPS (WP6)

**This section used to say the archive did not exist. It does now.**

Before any framework writer runs, adoption copies the files it would otherwise
land on into `.claude/adoption-archive/<UTC-timestamp>-<pid>/`, mirroring your
paths, and writes a `MANIFEST.json` and a `MANIFEST.md` beside them. The
population is the archive-and-replace bucket: `.claude/settings.json`,
`.claude/settings.local.json`, `.mcp.json`, your `.claude/skills/*/SKILL.md`,
every non-`.sample` file in `.git/hooks/`, and — since WP9b — `APPROVAL_LOG.md`.
**Only files that exist are archived** — an absent surface produces no file and
no manifest row.

**`APPROVAL_LOG.md` is the one entry adoption REPLACES**, and its row says so:
`disposition: "replaced"`, where every other entry reads `kept` (your file is
still where it was) or `composed` (the framework appended a marked block to your
commit-msg hook). Adoption writes its own tier-matched approval log at that path
because the phase gate cannot run without one — so if you keep an approval
record there already, **your copy is archived with a restore line and the
framework's template is what sits at the path afterwards**. That is the only
in-place replacement in the run.

Nothing is deleted. Every entry carries a `restore` line you can paste, and
every git-hook entry carries a short **advisory** description of what it
invoked, assembled from a fixed list of tool names so that no byte of your hook
can reach the manifest.

The run then discloses it in full — the sentence, **the list** (every path, not
a count), and the restore instructions:

```text
══ Your own configuration has been archived
   The files below were moved to ensure the framework operates properly.
   Nothing was deleted. Every one of them is in .claude/adoption-archive/… and can be put back.

   yours: .git/hooks/pre-commit
      archived as: .claude/adoption-archive/…/git-hooks/pre-commit
      what it did: Ran `lint-staged`, `npx`, and other commands.
      put it back: cp .claude/adoption-archive/…/git-hooks/pre-commit .git/hooks/pre-commit
```

#### Your files are yours — `--re-add`

```bash
bash /path/to/solo-orchestrator/scripts/adopt-project.sh --re-add .git/hooks/pre-commit
```

It prints the warning, asks you to confirm (there is no default and no skip),
restores the file byte-for-byte at its recorded mode, and writes the choice
into `.claude/bypass-audit.json` as an `adoption_event` row. The framework's
premise is opinionated enforcement, not confiscation; it asks only that the
override be findable by whoever reads the ledger next. See
[audit-log-lifecycle.md](audit-log-lifecycle.md#adoption_event).

#### The archive is scanned before anything is committed

`.git/hooks/` is **not** tracked by git; `.claude/` is. So copying a hook into
the archive and committing it would take a credential git had never seen and
put it in your history — **adoption would create the leak.** So the archive is
scanned with `gitleaks` *before* staging, and any entry that matches is written
to disk and **kept out of the commit**, with the reason recorded:

```text
   1 of those copies were NOT added to the commit.
   NOT COMMITTED — secret-match
   A credential in a file git had never seen would have become a credential in
   your history. Rotate it at the source; deleting the file does not un-leak it.
```

**A pattern scanner is a mitigation, not a proof, and this page will not call
it a guarantee.** It recognises credential *shapes*. An internal hostname, a
proxy URL, a customer name or a username matches nothing, and a hook can hold
any of them. Read `MANIFEST.md` before you push.

Which is why the scan is not the only gate. Three more reasons withhold an
entry, and the MANIFEST names whichever applies:

| `withheldReason` | What happened |
|---|---|
| `secret-match` | The scanner matched something in that file. |
| `not-scanned` | gitleaks was **not installed** or the scan failed, so **the whole archive is withheld**. "Nobody looked" is not "clean", and an unexamined tree does not enter version control. |
| `original-gitignored` | **Your `.gitignore` excludes the original.** A gitignore entry is your explicit statement that this *content* must never enter history, so the archive keeps a copy you can restore and never commits that copy under a different name. |
| `gitignored` | Your `.gitignore` excludes the archived path itself. Withheld because `git add` on an ignored path fails and would otherwise abort the entire adoption commit. |

`original-gitignored` is the one that will fire most often, and the file it
usually fires on is `.claude/settings.local.json` — the standard place for a
proxy setting, an internal endpoint or a personal token, and standardly
gitignored. The ordinary ignore rule for it is *anchored*
(`.claude/settings.local.json`), so it matches the original and **cannot** match
`.claude/adoption-archive/…/.claude/settings.local.json`. Asking git about the
copy's path would answer a question you never asked.

**Your git hooks are exempt from this rule, and the reason is worth stating
because an earlier version of this page got it wrong.** It claimed hooks were
safe because "git excludes `.git/` by construction" — they are not:
`git check-ignore` applies your patterns to any path it is given, `.git/`
included, so a `.gitignore` containing `*`, `hooks/` or even the cargo-cult
line `.git/` reports `.git/hooks/pre-commit` as ignored. The exemption is
deliberate instead: a `.gitignore` line about a `.git/` path is not an
instruction git can act on — git never tracks `.git/`, so the rule changes
nothing and expresses no decision about whether that content may be preserved.
Without the exemption a single inert `.git/` line would silently withhold your
hooks, which are the most important thing the archive holds.

#### Still not built by this package

```text
NOT DONE — your project's framework documents
   Owner: WP11 archives them, WP12b writes them (D3). This build does not do it, and does not pretend to.
   CLAUDE.md, the document templates and the reference docs are NOT written. The scripts and the
   state are here, so the gates work; the reading material an agent picks up at the start
   of a session is not, and a CLAUDE.md you already have would be a collision, not a gap.
   WP6's archive covers your AI-layer settings and your git hooks; documents are neither
   YET — D3 makes them a fourth archive class, and WP11 is where that lands.
```

So an adopted project has working gates and **no `CLAUDE.md`** — the file an
agent reads at the start of every session. Write one by hand, or copy
`templates/generated/claude-md.tmpl` from the framework clone and fill it in.

The other gap is the **replacement** half for framework-script collisions: a
file of yours sitting where a framework *script* would go is still left alone
and still not replaced, so the framework's version of it is not installed. That
class is deliberately outside the archive — swapping out a `scripts/validate.sh`
your own build may call is a decision nobody has made yet — and the run names
it with its own `NOT DONE` block.

### The CI carve-out, provenance headers and the Adoption Record — WP7

```text
NOT DONE — the provenance headers on reconstructed documents
   Owner: WP7. This build does not do it, and does not pretend to.
   PROJECT_INTAKE.md records where each answer came from, but it carries no machine-readable
   provenance header. A near-miss header is worse than none: WP7 ships a lint for the
   real one, and a lint cannot tell a near-miss from the genuine article.

NOT DONE — the Adoption Record, the audit rows and the CI carve-out
   Owner: WP7. This build does not do it, and does not pretend to.
   APPROVAL_LOG.md exists and the phase gate reads it; what is missing is the Adoption Record INSIDE it.
   The log this adoption wrote is the tier-matched template, carrying no approval of
   any kind — which is correct, because this adoption approved nothing. Until WP7
   lands, the adoption itself is recorded in the manifest and nowhere else.
```

**This no longer stops the gate.** Before WP9b, a freshly-adopted project got:

```text
$ bash scripts/check-phase-gate.sh
[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.
```

Adoption no longer *creates* that state — it writes the log itself, first, so
the gate reaches a verdict. Measured on a project adopted today:

```text
$ bash scripts/check-phase-gate.sh
Phase Gate Consistency Check
Current phase: 0


Adoption Stamp Integrity
[OK] Adoption stamp present and intact (adopted: …)

Phase gates consistent.
```

The refusal above is still correct where it still applies: **delete the log and
it returns**, at rc 1. That matters for the stamp check, which runs *after* the
precondition — so on a project whose `APPROVAL_LOG.md` is genuinely missing, the
adoption-loss detector never gets to speak.

The **Adoption Record** itself — the one place a successor reads to understand
how this project entered the framework, carrying the assessment's findings and
the verdict, the secrets dispositions, the collision archive path and the CI
keep-or-retire decisions — does not exist.
Neither does the eight-clause lint that keeps it structurally unparseable as a
gate approval. (The archive path it would carry is real now — it is in
`.claude/adoption-archive/*/MANIFEST.json` and in an `adoption_event` audit
row. What is missing is the Record that gathers it with everything else.)

The **CI carve-out** does not exist either. Nothing installs framework CI as its
own files, and nothing records a keep-or-retire decision about your pipelines.
Scout's SDLC findings are the only part of that surface that ships, and they are
report-only.

### The commit-time scanners — no owner yet

```text
NOT DONE — the commit-time scanners (the fallback pre-commit hook)
   Owner: nobody yet — §10 names no owner. This build does not do it, and does not pretend to.
   The message gates ARE on. The secret scan, the static-analysis pass and the schema-migration
   checks that normally run on every commit are NOT — installing that hook today refuses
   every commit, because it expects artifacts an adoption does not yet produce. Run them
   by hand until it lands: bash scripts/pre-commit-gate.sh --terminal-mode
```

**Read that "Owner: nobody yet" against the decision, not instead of it.** The
string above is what the driver actually prints, and it predates the call:
**Karl's decision is that the commit-time hook is installed by WP7**, once the
artifacts it reads exist. So the owner is WP7, and the driver's text will say so
once it is next touched. It is quoted here unedited because this page reproduces
what the tool prints rather than what it ought to print.

The behaviour either way is what the block describes: installing that hook today
would refuse every commit, so until WP7 the two **message** gates are live —
test-before-code ordering, and the Build-Loop commit check, both demonstrated
above — and the scanner arms are not. Run them by hand.

**The test-debt ratchet is in the same position, for the same reason and one
more.** Its two arms exist and are enforced on the tier ladder, but nothing
calls them on commit yet, so it is `adopt-test-debt.sh --check` by hand or from
CI until WP7 lands. The extra reason is structural rather than schedule:
`scripts/pre-commit-gate.sh` is **core** and the ratchet is **module** code, so
a call from the gate to the ratchet is exactly the `core → module` edge
[the module contract](module-contract.md)'s M3 forbids and
`scripts/lint-module-dependencies.sh` reds on. Whatever WP7 does about the hook
has to reach the ratchet without spending the module's severability on one
convenience call.

### And one more, from this page rather than the driver

**This page is not shipped into adopted or generated projects.** `init.sh` copies
the framework's guides into `docs/reference/`; `docs/adoption.md` and `docs/scout.md` are
not among them. Read them here, in the framework clone you run the driver from.

### Summary — what you can and cannot get today

| You want | Today |
|---|---|
| A read-only survey of an existing codebase | ✅ [Scout](scout.md), complete |
| A guided landing at phase 0, with the tier question and the reverse intake's confirmations | ✅ Ships and works |
| Project state written fail-safe, staged explicitly, committed as its own commit | ✅ Ships and works |
| An adoption stamp, and loud detection when it is lost | ✅ Ships and works |
| Test-first ordering enforced from adoption day forward | ✅ Ships and works |
| Gates that were skipped actually run and recorded | ✅ By construction — nothing is skipped; the project starts below every gate |
| Being asked what the project is for, and told whether the stack fits | ❌ The assessment (Act 3) — **not built** (WP12a) |
| A fitness verdict, a plan, and the reasoning behind both | ❌ The assessment (Act 3) — **not built** (WP12a) |
| Adoption that can *fail* on a serious finding | ❌ The secrets stop — **not built** (WP10) |
| A recorded, non-growing set of untested files | ✅ [Test-debt ledger + ratchet](#the-test-debt-ledger-and-its-ratchet) — ships and works, **but you run it; nothing calls it on commit yet (WP7)** |
| Your colliding hooks/settings archived with a restore path | ✅ Collision archive — ships |
| Plain disclosure of what was archived, path by path | ✅ Ships |
| Putting one of your own files back, warned and recorded | ✅ `--re-add`, ships |
| Adoption refusing to commit a *recognised* secret out of your hooks | ✅ Ships — the archive is scanned before staging and a match is withheld. **A mitigation, not a guarantee** — see below |
| Adoption never committing a file your `.gitignore` excludes | ✅ Ships — the **original's** ignore status decides, not the archive copy's |
| Framework CI installed beside yours, with a recorded keep-or-retire | ❌ CI carve-out — **not built** |
| A readable record of how this project entered the framework | ❌ Adoption Record — **not built** |
| Secret scanning, SAST and migration checks on every commit | ❌ Deferred to WP7, by decision |
| The framework's version of a colliding `scripts/*.sh` installed | ❌ Replacement half — **not built**, and unassigned |
| A `CLAUDE.md` in the adopted project | ❌ **Not built** — WP11 archives yours, WP12b writes the framework's (D3) |
| The manifest's tier keys, so enforcement cannot be downgraded | ✅ Ships — `## BL-221:` closed; the tier question is their only source |

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Adoption completed |
| 1 | Adoption did not complete. The message distinguishes the two cases (`# BL-225-REFUSE-HONEST`): **`[REFUSED]`** when the run never began — nothing committed, nothing written; **`[BLOCKED]`** when it began and stopped — nothing committed, but *N* file(s) already on disk, with the count derived from the write ledger rather than assumed. It does **not** claim those files are visible to plain `git status`: on the staging-block path they provably are not, so it names `git status --ignored --untracked-files=all` instead. **Nothing is ever left half-staged** — `# BL-225-STAGE-PREFLIGHT` asks `git add --dry-run` before it stages, and stops whole |
| 2 | Bad usage, or a target the driver cannot use |

---

## See also

- [scout.md](scout.md) — the read-only survey. Run it first.
- [delta-track.md](delta-track.md) — the post-1.0 maintenance loop an adopted project reaches the ordinary way, by shipping through the gates.
- [designs/2026-08-23-brownfield-adoption-v2.md](designs/2026-08-23-brownfield-adoption-v2.md) — the **normative** architecture design: the four acts, the ten settled decisions, and the build plan.
- [designs/2026-08-02-brownfield-adoption-v1.md](designs/2026-08-02-brownfield-adoption-v1.md) — superseded, kept because the shipped code still cites its section numbers in places v2's packages have not reached.
- [module-contract.md](module-contract.md) — the severable-module rules the driver is held to.

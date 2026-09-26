# Brownfield adoption — bringing an existing project into the framework

`init.sh` builds a project from an empty folder. **Adoption is the second way
in**, for a codebase that already exists — with its own history, its own
pipeline, and its own habits. It puts that project under the framework at
**phase 0**, archives anything of yours it has to replace, and commits exactly
the files it wrote.

> **What ships, and what does not.** Adoption works end to end: Scout's survey,
> the tier question, the credential scan and its tier-scoped stop, the reverse
> intake, the state writes and adoption stamp, the collision archive with
> `--re-add`, the test-debt ledger, the **Adoption Record** and the audit rows,
> the **commit-time scanners**, the **framework documents** (a rendered
> `CLAUDE.md` among them), the **Claude Code session layer** (the framework's
> permissions, session hooks and skills, composed into any settings you had),
> the **CI carve-out** (the framework's CI at its own filename; yours read for
> risky patterns, never changed), the **assessment** (a Claude Code conversation
> that `scripts/resume.sh` starts, and a finisher that records it), the
> **provenance header** on the reconstructed intake, and the **in-production
> exemption** (an adopted project the assessment records as in production may
> open a hotfix delta below phase 4, and keeps its retro). Every designed work
> package ships; two gaps with no owner yet are listed under
> [What is not built yet](#what-is-not-built-yet).

Everything on this page is output that was observed, pasted as it printed.

---

## Quick start: install and use

### What you need

| Tool | Why | If it is missing |
|---|---|---|
| `git`, able to resolve a commit identity | Adoption ends in one commit on your current branch | Refused before anything is written. git can often derive an identity from the system when none is configured; the refusal fires only when it cannot |
| `jq` | Every state file adoption writes is JSON | Stops at once with `adopt-project: jq is required.` and **exit code 2** — the "unusable target" code, not a refusal |
| `shasum` or `sha256sum` | The adoption stamp hashes the survey it was made from | Refused during the pre-write rehearsal, before anything is written |
| `gitleaks` | The credential scan of your history | **Organizational**: the adoption stops, with no override. **Personal**: it can continue if you accept that on the record |
| `semgrep` | The commit-time static-analysis pass | Every commit prints `semgrep not found — pre-commit SAST skipped.`; nothing blocks |
| A clone of the Development Guardrails at `~/.claude-dev-framework` | The Claude Code rules and hooks a new project gets | Adoption completes without them and prints the two commands that install them later. Adoption never fetches the clone itself. Get it with `git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework` |

Your project must be a normal git repository with at least one commit. A linked
worktree, a submodule, or a repository with `core.hooksPath` configured is
refused before anything is written, because the gates would be installed where
git never looks.

### 1. Get the framework

The framework is a clone that stays **outside** your project; adoption copies
what your project needs into it.

```bash
git clone https://github.com/kraulerson/solo-orchestrator.git ~/solo-orchestrator
```

### 2. Look first — Scout writes nothing

```bash
cd /path/to/your-project
bash ~/solo-orchestrator/scripts/scout.sh --out /tmp/scout --run-tests
```

`--out` writes `scout-report.json` and a readable `scout-report.md`. Leave out
`--run-tests` if you do not want Scout to run your code — but it is the one way
to learn **before adopting** whether your test suite passes today, and that
matters: once adopted, a commit that touches source code runs your tests and is
refused if they fail. See [Before you adopt: run Scout](#before-you-adopt-run-scout).

### 3. Adopt

```bash
cd /path/to/your-project
bash ~/solo-orchestrator/scripts/adopt-project.sh --scan-report /tmp/scout/scout-report.json
```

Without `--scan-report` it runs its own survey. It asks one question a scan
cannot answer — **who the project is for** — and that answer sets its
enforcement tier:

```text
Who is this project for?
   1) Just me, or me and a few people I know
   2) A company, a client, or people who are paying for it
```

Then it confirms what the survey found, writes the project's state at phase 0,
and commits. **Your uncommitted work is never staged**; the commit contains only
files adoption wrote. Exit codes: `0` adopted; `1` did not complete (a refusal,
a stop, or a halt); `2` bad usage.

### 4. If it stops

- **Credential findings in your history** (organizational): the run lists them —
  rule, file and line, never the value — and prints a dispositions file **already
  bound to that scan**, with every fingerprint filled in. Save it *outside* the
  project, fill in each `disposition` (`rotated`, `false-alarm` or
  `accepted-risk`), `by`, `reason` and `date`, and run the same command again with
  `--dispositions ~/adoption-dispositions.json`. The decisions go into the
  Adoption Record. On a personal project the findings are recorded and adoption
  continues.
- **No scanner, or a shallow clone** (personal): without `gitleaks`, or on a
  `git clone --depth` that only has part of the history, a personal adoption
  stops and prints the same kind of file — this time with one
  `acknowledgements` entry of kind `tool-unavailable` or `scanned-partial`. Fill
  in `by`, `reason` and `date`, and re-run with `--dispositions`. The acceptance
  goes into the Adoption Record. For a shallow clone the run also prints the two
  commands that fetch the full history, which is the better answer if you can.
  An organizational adoption with no scanner cannot be accepted this way:
  install `gitleaks` and run again.
- **Every `date` must be a real calendar day written `YYYY-MM-DD`.** "tomorrow",
  "0000-00-00" and 2026-02-30 are refused.
- **Your own pre-commit hook refused the adoption commit**: fix or bypass that
  hook, then run `adopt-project.sh --finish`. It commits exactly the files the
  first run wrote.
- **Anything else** prints a `[REFUSED]` or `[BLOCKED]` line naming the cause, and
  says whether anything was written.

### 5. Afterwards

```bash
bash scripts/resume.sh
```

It prints the **assessment prompt** — paste it into Claude Code. That session
asks you what the project is for, gives a verdict with its reasoning, and runs
the finisher that records it ([The assessment](#the-assessment--act-3-and-act-4--ships-wp12a)).
Run `resume.sh` again afterwards and it opens Phase 0; the agent reads the
`CLAUDE.md` adoption wrote. If you
already had a `CLAUDE.md`, `BUGS.md` or the like, the run named each one it
replaced — the framework's version is in place and yours is in the archive,
**not merged** until the assessment conversation folds in what is worth keeping
(or you copy it across yourself —
[The framework documents](#the-framework-documents--ship-wp12b)). From your next commit on, the message gates and the
commit-time scanners run. Your replaced files are in
`.claude/adoption-archive/<timestamp>/`, each with a restore line in its
`MANIFEST.md` — and one command puts any of them back:

```bash
bash ~/solo-orchestrator/scripts/adopt-project.sh --re-add .git/hooks/pre-commit
```

---

## Contents

- [Quick start: install and use](#quick-start-install-and-use)
- [Before you adopt: run Scout](#before-you-adopt-run-scout)
- [The one question](#the-one-question)
- [Where it lands: phase 0, always](#where-it-lands-phase-0-always)
- [The reverse intake](#the-reverse-intake)
- [What gets written, and in what order](#what-gets-written-and-in-what-order)
- [The adoption stamp, and what happens when it is lost](#the-adoption-stamp-and-what-happens-when-it-is-lost)
- [The Adoption Record](#the-adoption-record)
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
question answerable; it does not answer it. The Adoption **Record** is appended
to the end of that same log — see [The Adoption Record](#the-adoption-record).

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

### The order is `APPROVAL_LOG.md` → `phase-state.json` → intake → the secrets dispositions → `manifest.json` → the framework documents → the Adoption Record → the write set

The secrets dispositions come before `manifest.json`, so an acceptance that
cannot be recorded stops the run before the project reads as adopted. The framework documents follow `manifest.json` so they are written under a
stamped adoption, and precede the record so the record stays the last thing in
the log. The last two are ordered by what they read, not by taste. The **Adoption
Record** names the commit this project was adopted at and takes that value from
the adoption *stamp*, which the `manifest.json` stage writes — one fact, one
source, rather than a second `git rev-parse HEAD` that could disagree. The
**write set** is last because it records what every stage before it wrote.


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
   79 file(s), named one by one. Anything else you had in progress stays
   exactly as you left it — unstaged, uncommitted, untouched.
```

The driver builds an explicit array; anything not in it is never staged. The
counter-example this exists to avoid is `create_project()`'s
`git add -A` + `git commit --no-verify`, which on an existing project would sweep
your uncommitted work into a framework commit with verification bypassed.

Observed on a completed run — one commit,
`chore: adopt <project> into the Solo Orchestrator framework`, containing **79**
files: the nine below, and the framework `scripts/` tree (70 of them — measured 2026-09-16;
the count follows `init.sh`'s copy list and drifts with it).
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
   Installed 70 framework script(s); left 0 of your own file(s) untouched.
```

The set is **derived from `init.sh`'s own copy list** rather than duplicated, so
an adopted project's script set cannot drift from a scaffolded one's. Measured,
comparing this adopted project against a project scaffolded by `init.sh` on the
same tree: **70 scripts each, and the difference in both directions is empty** (measured
2026-09-16; it was 68 each before `## BL-254:` added two).

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

## The Adoption Record

At the end of your `APPROVAL_LOG.md`, under its own `## Adoption Record`
heading, adoption writes down what it did. Before this existed, the run's own
findings lived in your terminal scrollback and nowhere else — the driver said so
out loud, and the personal-tier secrets block told you to *keep this transcript*,
because real credentials found in your history had no permanent home.

It records, in these sections (six on a clean project, eight when you supply
a `--dispositions` file):

- **How this project was adopted** — the day, the enforcement tier, whether
  proof-of-concept mode is on, and **the commit you were sitting on** when
  adoption ran. That commit is the anchor that bounds the pre-adoption TDD
  exemption: everything at or before it is history the framework inherited, and
  every commit after it is held to the ordinary rules.
- **What the credential scan read, and what it found** — the scanner, **its
  version**, who ran it, under whose rules, the outcome, how many commits it
  read, and how many findings there were:

  ```text
      | Field | Value |
      |---|---|
      | Scanner | gitleaks |
      | Scanner version | 8.30.1 |
      | Run by | adoption |
      | Rules | framework |
      | Outcome | scanned |
      | Commits read | 412 |
      | Findings | 1 |
  ```

  *(The two header rows are part of what the renderer emits; an earlier draft of
  this block dropped them, which made it an edited excerpt on a page that
  promises transcripts. The counts are this fixture's, not a universal.)*
- **The findings, by fingerprint** — one row per match: the rule, the file and
  line, and the fingerprint. **Never the matched value.** If you supplied a
  `--dispositions` file, what was decided about each one and by whom follows in
  its own table; if you did not, the record says so plainly rather than leaving
  a blank that reads as a clean bill of health.
- **What of yours was archived** — the archive path and the `--re-add` line.
- **What else this run measured** — the count of source files with no test, the
  hooks directory git will actually use, and how long the pre-write rehearsal
  took over how many megabytes.

It then names the three things a complete record would carry and this build
cannot: the assessment's findings and verdict, the interview answers, and the
in-production declaration. They are **named rather than omitted**, because a
field that is simply absent reads like a measurement that came back empty.

### It cannot be mistaken for an approval, and that is enforced rather than promised

`APPROVAL_LOG.md` is the file four separate programs parse to decide whether a
phase gate was crossed with evidence. Putting a free-text record into it is only
safe if the record cannot be read as one, so the record holds an eight-part
structural contract — no `Phase N → Phase N+1` line, no named approval-row
literal, no attorney or legal-review heading, no pen-test exemption phrase, no
table row starting at column 0, no `date` substring in its prose, no
`[YYYY-MM-DD]`-style placeholder, and its own `## ` heading placed after every
gate section.

**The contract is checked before a byte is written.** If the rendered record
would violate any clause, nothing is appended and the run refuses, naming the
clause on stderr. The reason it is enforced rather than merely written carefully
is that part of the record is *your* text — a path inside your repository, the
name and reason you wrote on a disposition — and some entirely ordinary
sentences are dangerous here. A disposition signed by a *"pen test team"* with
the reason *"exempted by policy until Q3"* assembles into a line matching the
framework's pen-test exemption check, which takes no window and no date: it
greps the whole file. Copied in verbatim, two innocent cells would tell this
framework a penetration test had been exempted.

So the **row** is tested as a row, and cells are withheld from the right until
it is clean. Real output, from that exact input:

```text
    | Fingerprint | Outcome | Decided by | Reason |
    |---|---|---|---|
    | dedba58f988140f973b013670a4d6834664b873a:src/config.py:generic-api-key:2 | accepted-risk | pen test team | (withheld: this text spells a phrase this log is parsed for) |
```

The fingerprint, the outcome and the person all survive; only the free-text
reason goes, because it is the rightmost cell and the cheapest to lose.

It is withheld rather than rewritten on purpose. Lowercasing your `Phase` or
clipping your `exempted` would put words in your mouth, quietly, in the one
document that exists to be trusted later. And it is withheld rather than
refused, because an adoption must not fail over a security team's name. Ordinary
text that merely *resembles* a trigger is untouched — a finding in
`src/updater/config.yml` is printed exactly as it is.

*(The first cut of this checked each cell in isolation, which is not what the
readers do — they read lines. A real organizational adoption with the
disposition above was **refused outright**, with the reason discarded by the
rehearsal's output relay. Both are fixed: the row is tested as a row, and the
failing clause is printed on stderr so the rehearsal relays it.)*

**Written once.** A second run finds the heading and leaves the log alone; the
record is never rewritten, for the same reason the adoption stamp refuses to be
re-stamped.

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

This section started as the list of what was designed and not built; all of
it now ships, and each subsection says so in its heading.

One gap has no owning package: **a file of yours sitting where a framework
*script* goes is left alone**, so the framework's version of that script is not
installed; the run names it.

### The Development Guardrails for Claude Code — SHIP (`## BL-296:`)

When `~/.claude-dev-framework` holds a clone, adoption runs **the same
installer a new project runs**. It writes the rules and hooks into
`.claude/framework/`, merges its hooks into `.claude/settings.json`, and records
its version in `.claude/manifest.json`. All of it is part of the adoption commit.
Adoption runs it without a terminal, so it never asks a question and picks its
profile from your project's files; the platform itself is decided in the
assessment. It runs before the adoption stamp is written, because the installer
replaces `.claude/manifest.json`, and the stamp is then merged into its file.
Measured:

```text
══ The Development Guardrails for Claude Code
   Installed the Guardrails (version 4.3.1, profile web-api) —
   the same installer a new project runs. Its rules and hooks are in .claude/framework/.
```

Three differences from a new project, on purpose:

- **No clone.** Adoption never fetches the Guardrails over the network. Without a
  clone it says **NOT INSTALLED** and prints the two commands that install them
  afterwards, and the Adoption Record says so.
- **No update.** It installs the version on disk, and the Record names it.
- **An existing install is left alone.** A project that already has
  `.claude/framework/` keeps its own.

The installer's own backup directory (`.claude-backup/<timestamp>/`) is
removed, as `init.sh` removes it: the adoption archive already holds every
original. A `.claude-backup` of yours is not touched. If the installer fails,
the adoption stops in the pre-write rehearsal, before anything is written.

### The assessment — Act 3 and Act 4 — SHIPS (WP12a)

The assessment is where you are asked what this project is for, and where the
framework says, **with its reasoning shown**, whether the technology fits those
answers. It is split in two, because half of it is judgement and half is fact:

1. **Act 3 — a Claude Code conversation.** When adoption finishes it prints
   *Next: the assessment (Act 3)*. Run `bash scripts/resume.sh`: on an adopted
   project that has not been assessed it prints the **assessment prompt**
   (adoption wrote it to `.claude/adoption/assessment-prompt.md`). Paste it into
   Claude Code. The session reads the survey, the intake and your archived
   documents, then **asks you** — it does not infer — how many people use the
   project, whether it needs high availability, whether it is internet-facing,
   what growth it must handle, how sensitive its data is (one of `public`,
   `internal`, `confidential`, `pii`, `financial`, `health`, `regulated`), and
   whether it is in production today. It judges fitness **only against those
   answers** — every finding names the answer it is relative to — and writes a
   verdict (`keep` or `rebuild`), a plan, the record
   `.claude/adoption/assessment-record.json`, and folds what is worth keeping
   from your archived documents into the framework's.
2. **Act 4 — the finisher, a shell command** the session runs for you:

   ```bash
   bash "$(jq -r .source_dir .claude/orchestrator-source.json)/scripts/adopt-project.sh" --act4 --root .
   ```

   It **checks the record before it writes anything**, and refuses — naming
   each reason — when the file is not exactly one JSON object, a finding names
   no requirement, the commit is not the one this project was adopted at,
   *in production* is not a plain true/false, the data classification is not
   one of the seven, a classification other than `public` has neither a ZDR
   attestation nor a written reason (the Phase 1→2 gate would block it later),
   an interview answer uses a key outside the ten the prompt lists, or the
   verdict lacks its technical account or its `## Plain English` half with a
   `Recommendation:` and a `Reason:`. If it stops after it has written
   something, it says what. Measured:

   ```text
   [REFUSED] the assessment record was not accepted, and nothing was written
             The assessment finisher did not begin. Nothing was committed and nothing was written.
             - fitness finding F1 names no interview axis in requirementRef — a finding is relative to a stated requirement (§5.3)
             Fix .claude/adoption/assessment-record.json (or the verdict), then run this again.
   ```

   When the record passes, it records the data classification where the phase
   gate reads it, writes the interview answers into the intake under the intake
   wizard's own keys, and merges the assessment into `.claude/manifest.json` —
   **once**; a second run is refused. It never moves the phase and never writes
   `PRODUCT_MANIFESTO.md`, and it does not commit: it prints what to commit.

**If the project is in production, a live incident does not wait for phase 4.**
The assessment records the answer, and an adopted project recorded as in
production may open a hotfix delta below phase 4 (`scripts/delta.sh --open`).
The delta record and `.claude/process-state.json` both record that the
exemption was used, the hotfix still owes its write-up, `validate.sh` reports
it as an INFO rather than a mismatch, and no phase gate reads it. A project not
in production — or assessed before the question existed — is refused as before.

**Either verdict continues from phase 0.** After the assessment, `resume.sh`
opens Phase 0 — measured on a real adoption, the committed assessment passes the
project's own commit checks and the next `resume.sh` prints the project's
Phase 0 prompt.

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

The framework documents, which this section used to list here, ship now — see
[The framework documents](#the-framework-documents--ship-wp12b). The remaining gap is the **replacement** half for framework-script collisions: a
file of yours sitting where a framework *script* would go is still left alone
and still not replaced, so the framework's version of it is not installed. That
class is deliberately outside the archive — swapping out a `scripts/validate.sh`
your own build may call is a decision nobody has made yet — and the run names
it with its own `NOT DONE` block.

### The audit rows and the dispositions record — SHIP (WP7)

Every adoption commits two records of what it decided, beside the Adoption
Record:

- **`.claude/adoption/secrets-dispositions.json`** — the scan this adoption
  answered (the commit it read, how many commits, full or shallow, the status,
  and the sha256 of the committed `scout-report.json`) and the dispositions and
  acknowledgements **this run accepted**. It is written even when the scan found
  nothing: *we scanned, at this commit, and found nothing* is worth keeping.
  Fingerprints, rule ids and line numbers only — never a value. A row in your
  `--dispositions` file that this run did not accept (an acknowledgement for a
  scan that was complete, a disposition with no name or no real date, a
  fingerprint this scan did not find) is not copied in — and neither is
  anything from a file bound to a different scan (its `scan.head` or
  `scan.commitsScanned` is not this one's). The Adoption Record's table of
  decisions is rendered from the same filtered set, so the two agree.
- **A ledger you already have is appended to, never replaced**; every row in it
  survives.
- **`.claude/bypass-audit.json`** gains `adoption_event` rows: one
  `adoption` row naming the tier, the commit it was adopted at and what the
  scan said, and one `secrets_disposition` row per **accepted risk** and per
  **acknowledgement**. `rotated` and `false-alarm` accept no risk and write no
  row.

Measured on a clean personal adoption:

```text
$ jq . .claude/adoption/secrets-dispositions.json
{
  "schemaVersion": 1,
  "scan": {
    "head": "da3a7756c1f67adf7607b0cd8cd501f2613812ff",
    "commitsScanned": 1,
    "scope": "full-history",
    "status": "scanned",
    "reportSha256": "cb3a24fb491e9388d85f2cf3a751355039eefda6a8b07ff82d5c309bb64e272c"
  },
  "dispositions": [],
  "acknowledgements": []
}
$ jq -c '.[] | select(.details.event=="adoption") | .details' .claude/bypass-audit.json
{"deployment":"personal","adoptedAtCommit":"da3a7756c1f67adf7607b0cd8cd501f2613812ff","archiveDir":null,"secretsScanStatus":"scanned","findingCount":0,"landedPhase":0,"event":"adoption"}
```

**An accepted risk that cannot be recorded stops the run.** If the ledger will
not take the row — most often because `.claude/bypass-audit.json` is not valid
JSON — adoption prints `[BLOCKED] an accepted risk could not be recorded in
.claude/bypass-audit.json` with the command that checks the ledger, exits 1,
and writes nothing, because the rehearsal hits it before the first real write: an acceptance that leaves no trace is not one it
will act on. The `adoption` row is different: the Adoption Record and the stamp
are the primary records of the act, so a ledger that refuses that row is
reported loudly and left out of the commit, and the adoption stands.

### The framework documents — SHIP (WP12b)

Adoption writes the documents `init.sh` gives a new project at the same moment,
from the same sources:

| Written | From |
|---|---|
| `CLAUDE.md` | rendered by the renderer `init.sh` uses, with your project's name, the tier you chose (an organizational adoption gets the branch-protection section), the track the intake recorded (`full` today), `undecided` for platform and language, and a placeholder description — the assessment asks for both |
| `FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md`, `docs/INDEX.md`, `docs/IDENTIFIERS.md`, `docs/archive/README.md` | the framework's templates, copied |
| `docs/reference/*.md` — the eight guides | copied **only where absent**; a guide you already have there is left alone |

Measured on a project that owned a `CLAUDE.md` and a `BUGS.md`, and had
`FEATURES.md` as a symlink:

```text
══ The framework's documents
   Wrote the framework's documents — CLAUDE.md, FEATURES.md, BUGS.md, RELEASE_NOTES.md,
   docs/INDEX.md, docs/IDENTIFIERS.md, docs/archive/README.md and the guides in
   docs/reference/ — except any listed below as left alone, and any guide you already had.
   These replaced documents of yours:
     CLAUDE.md
     BUGS.md
   Your originals are in .claude/adoption-archive/2026-09-24T16-22-37Z-37767, each with a restore line in its
   MANIFEST.md. Nothing in them was merged into the new files — copy across anything you
   want to keep, or leave it for the assessment conversation to fold in.
   These were LEFT ALONE, so the framework's version of each is NOT in place:
     FEATURES.md — a symlink; writing through it could overwrite a file elsewhere
```

**Nothing of yours is merged in.** Adapting your prose into the framework's
documents is judgement, and judgement belongs to the assessment (Act 3), which
is not built. What adoption does is archive every original, name each one it
replaced, and tell you where it is. Until you copy content across, the agent
reads the framework's `CLAUDE.md`, not your notes.

**What it will not write over:**

- **a symlink, or anything inside a symlinked folder** (`docs -> /somewhere/else`)
  — writing through it could change files outside the project; the MANIFEST row
  says `kept`;
- **a read-only file** — left as it is, MANIFEST row `kept`;
- **a hardlink** is replaced by writing beside the path and renaming, so the
  other name keeps your content.

Anything left alone is named in the run, under *LEFT ALONE*, so the framework's
version is missing there by your file system's choice, not silently. Not
written: `PROJECT_BIBLE.md` and `PRODUCT_MANIFESTO.md` (phase outputs — `init.sh`
does not write them either) and the `.gitignore` lines `init.sh` adds.

### The Adoption Record, the audit rows and the provenance header — WP7

**The provenance header ships.** `PROJECT_INTAKE.md` — the one document adoption
reconstructs from what already existed — opens with a fenced comment that says
so, invisible when rendered and exact when checked:

```text
<!-- SOIF-PROVENANCE-BEGIN
reconstructed-at: 2026-09-25
reconstructed-by: scripts/adopt-project.sh
source: existing codebase at 0f7afd202f02 + adoption survey
status: describes work completed BEFORE adoption; not a pre-build specification
SOIF-PROVENANCE-END -->
```

The documents adoption writes that describe what is **coming** — `CLAUDE.md`,
`FEATURES.md` and the rest — carry none. A near-miss header is worse than none,
so the check is exact: the fence lines, four fields in this order, a real date,
a commit, the status sentence word for word, and first in the file. It runs when
the file is written and again in the assessment finisher, because the
assessment conversation edits `PROJECT_INTAKE.md`; a header it broke stops the
finisher before anything is recorded.

**The Adoption Record used to be on this list and is not any more.** The driver
no longer prints a `NOT DONE` block for it: it appends the record to the end of
your `APPROVAL_LOG.md` during the run, and refuses rather than writing one that
its own eight-clause contract rejects. See
[The Adoption Record](#the-adoption-record).

§8.9 names five `adoption_event` rows. Four are emitted — **collision
archive**, **re-add**, **adoption** and **secrets disposition** (see
[The audit rows](#the-audit-rows-and-the-dispositions-record--ship-wp7)). The
fifth, **blocker acceptance**, belonged to the retired certification pass and
will not be emitted. **The emitter's own header in
`scripts/lib/adopt/adopt-archive.sh` is the live list** — it names each row and
its owner, and it is maintained with the code. Prefer it to this paragraph.

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

The **Adoption Record** exists now, and carries what this build can honestly
put in it: the scan and its findings by fingerprint, the dispositions and
acknowledgements when you supplied them, the archive path, the test-debt count,
the hooks directory and the rehearsal's measurements. What it cannot yet carry —
the assessment's findings and verdict, the interview answers, the in-production
declaration — it **names in its own text** rather than leaving out, so that a
reader finding those fields absent does not read the absence as a measurement
that came back empty.

The **CI carve-out** ships — see
[The CI carve-out](#the-ci-carve-out--ships-wp7) below.

### The Claude Code session layer — SHIPS (WP9c)

A scaffolded project gets its Claude Code session layer from `init.sh`; an
adopted one now gets the same one, from the same code
(`scripts/lib/claude-settings.sh`, which `init.sh` calls too):

- **`.claude/settings.json`** — the framework's permissions for the project's
  language, and its session hooks: the version, test-gate, freshness, intake and
  cadence checks at session start, the commit gate and the MCP gate before a
  tool runs, tool tracking after it, the Qdrant reminder and the bypass
  detector at session end. **If you already have a `settings.json` it is
  composed, not replaced**: every key, rule and hook of yours stays, the
  framework's rules are added to `allow` and `deny`, and its hooks are added
  where absent. Your original is in the archive, recorded as `composed`. A
  symlinked `settings.json` is left alone and the run says so.
- **One difference from a new project, on purpose:** the bypass detector's
  per-tool hook is not registered on an adopted project while `## BL-277:` is
  open; its end-of-session hook is.
- **The four vendored skills** — `session-handoff`, `sweep-triage`, `zoom-out`,
  `grill-with-docs` — in `.claude/skills/`. A copy of yours at one of those
  names is archived and replaced; any other skill of yours is untouched.
- **The Qdrant MCP declaration**, only where `init.sh` would write one (a
  registered Qdrant server, or a running container with `uvx`):
  `.claude/settings.local.json` with this project's collection — machine-local
  and not committed, as in a new project — and the requirement recorded in
  `.claude/manifest.json`, which is.

### The CI carve-out — SHIPS (WP7)

**Your pipelines are read, never changed.** Adoption reads every CI file you
have — `.github/workflows/*.yml`, `.gitlab-ci.yml`, `bitbucket-pipelines.yml` —
for four ways a pipeline can let code around the framework's checks:

| Finding | What it looks for |
|---|---|
| auto-merge | `gh pr merge … --auto`, auto-merge actions — changes merge with nobody deciding |
| admin merge | `gh pr merge … --admin` — merges past checks that have not passed |
| force-push or history rewrite | `git push --force`, `filter-repo`, `filter-branch` |
| a failing step is allowed to pass, or a job runs regardless | `continue-on-error: true`, `allow_failure: true`, `if: always()` (which also fires on legitimate fail-closed jobs — read it, then decide) |
| deploys on a branch push | a deploy in a workflow triggered by a branch push, with no tag, release or manual trigger |

It is a search for known spellings, not a parser, and the run says so. It
misses what it has no spelling for (`|| true`, a `--mirror` push, a deploy in a
file that also has a manual trigger), and a file it **cannot read** is reported
as unread and recorded that way — never as clean. It
reports a **line number**, never the line — a workflow can carry a credential.
For each file with a finding it asks once, **before anything is written**:
*keep* it as it is, or *retire* it. Your answer goes into the Adoption Record;
"retire" is your intention, and adoption does not carry it out. A file with no
finding asks nothing. Measured:

```text
══ Your CI — read, not changed

   .github/workflows/release.yml — the framework cannot vouch for what this lets through:
     line 10  a failing step is allowed to pass — a red check can come out green
     line 6  deploys on a branch push — code can reach production without the release phase
Keep .github/workflows/release.yml as it is, or will you retire it?
   1) Keep it — it stays exactly as it is
   2) Retire it — I will remove or change it myself
```

**The framework's CI is installed as its own file**, from the template `init.sh`
uses for the project's language, and **never at the canonical path**. On GitLab
and Bitbucket the canonical file is your whole pipeline, and replacing it would
take your deploy offline:

| Host | Framework CI | Runs? |
|---|---|---|
| GitHub | `.github/workflows/solo-gates.yml` | Yes, from your next push — GitHub runs every workflow. It may fail on code that predates adoption; that is a finding, not a breakage. |
| GitLab | `.gitlab-ci-solo.yml` | **Not until you add** `include: - local: '.gitlab-ci-solo.yml'` to your `.gitlab-ci.yml`. The run prints the lines — and a warning: GitLab **merges** an included file into yours, and this one sets `image`, `variables`, `cache` and `stages` pipeline-wide and defines jobs named `test` and `lint`. Check those against your file first. |
| Bitbucket | `bitbucket-pipelines.solo.yml` | **No.** Bitbucket runs only `bitbucket-pipelines.yml`. Sharing a configuration file needs Bitbucket Premium and an exported file whose name ends in `pipelines.yml`, which this is not; copy the steps you want into yours. |
| none found | nothing | `init.sh` lays no CI down for host `other` either; supply your own. |

A file already at the framework's name is yours: left alone, and the run says
so. The Adoption Record's **Your CI** section names the framework's file (or why
none was installed) and your decision for each flagged file.

### The commit-time scanners — SHIP (WP7/3)

**This section used to say the scanners were not installed and that nobody owned
them.** They are installed now, and the sentence that deferred them is what
brought them back.

That block was a MEASUREMENT: installing the hook "refuses every commit, because
it expects artifacts an adoption does not yet produce". True when taken — and
therefore worth re-taking once the Adoption Record landed. Re-measured on a real
adoption, hook installed:

```text
docs: commit, nothing else staged          rc 0   lands
a source file whose tests fail (BL-125)    rc 1   [BLOCKED] project tests FAILED
a staged RSA private key                   rc 1   [BLOCKED] gitleaks detected secrets
```

So from your next commit onward, an adopted project runs the same commit-time
checks a scaffolded one does: secret detection, the static-analysis pass and the
schema-migration checks, on top of the two message gates that were already on.

**Your own pre-commit hook is REPLACED, not left alone.** That is §7.1's rule —
its archive-and-replace population is your AI-layer settings and every
non-`.sample` file in `.git/hooks/` — and the framework's hook is written whole,
so it cannot compose the way the commit-msg gate does. Your copy is in the
archive with a restore line, and the run says so:

```text
   Your own pre-commit hook was REPLACED by the framework's. Your copy is in the
   archive with a restore line — see .claude/adoption-archive/…/MANIFEST.md.
   Nothing of it was merged: the framework's hook is written whole, so the two
   could not compose the way the commit-msg gate does.
```

The MANIFEST row for it reads `disposition: "replaced"`, not `kept` — it said
`kept` for exactly one commit's worth of history, next to a hook that had just
been overwritten.

#### The static-analysis pass needs a ruleset, and adoption now installs it

The hook passes `--config=.semgrep/soif-dom-sinks.yml` unconditionally. Adoption
did not install that file, so on an adopted project **every commit** printed:

```text
[WARN] semgrep could not complete (exit 7) — the tool itself failed.
  SAST NOT ENFORCED for this commit — the scanner did not run.
  [ERROR] unable to find a config; path `.semgrep/soif-dom-sinks.yml` does not exist
```

Loud, honest, and unprotected. Adoption lays the ruleset down and commits it —
**unless you already have a file at that path**, in which case yours stands and
the run says so, because the hook reads that path either way and your rules are
yours.

#### When the scanners are NOT installed — and the run says so

Adoption never overwrites bytes its archive cannot give back. In four cases
that means your hook stays exactly where it is, the scanners are **not**
installed, and the run ends with **exit code 1** — the adoption itself landed,
this step did not, and a script reading the exit code must not take the project
as fully gated:

| Your `.git/hooks/pre-commit` is… | What happens |
|---|---|
| **a symlink** — to one shared hook several repositories use, or dangling | Left alone. Writing through it would overwrite the file at the far end, and the archive cannot hold a copy of a link's target. |
| **read-only** | Left alone, permissions included. |
| **different from the archived copy** — you edited it after a refused adoption commit, before `--finish` | Left alone. Overwriting it would lose your edit, with only the older version to restore. **Do not run the archive's restore line for it** — that line was written before your edit and would put the older version back. The run says so. |
| **without a restorable copy** — the archived file was removed, or the path is not a regular file | Left alone. Replacing it would leave nothing to put back. |

A **hardlinked** hook is replaced safely: the framework's hook is written beside
yours and renamed over the path, so the file it shares an inode with elsewhere
is untouched.

Each refusal prints the reason and a command that works. Move your hook aside,
then run, from the project root:

```bash
bash -c '. scripts/lib/hook-templates.sh && soif_write_precommit_hook .git/hooks/pre-commit'
```

Re-running the adoption, or `--finish`, will **not** do it — both refuse on a
project that is already adopted. Or run the scanners by hand on each commit:
`bash scripts/pre-commit-gate.sh --terminal-mode`.

#### Three things to know before you rely on it

- **A test suite that already fails will block source commits.** The hook runs
  your project's own test command whenever a source file is staged, and refuses
  the commit if it fails. Adoption does not run your tests, so it cannot warn you
  in advance. If your suite is red today, fix it — or point the hook at a command
  that passes by writing it to `.claude/test-command` — before your first
  source commit.
- **Your test command has no time limit.** A suite that hangs, or waits for
  input in watch mode, will hang the commit. The same `.claude/test-command`
  file is how you give the hook a command that finishes.
- **Tools that install into `.git/hooks/pre-commit` are replaced, not chained.**
  The Python `pre-commit` framework and lefthook both work that way, so their
  lint and format checks stop running on commit. Your hook is in the archive
  and `--re-add` puts it back, but then the framework's scanners are not
  installed. (husky 5 and later use `core.hooksPath`, which adoption refuses
  before writing anything; husky 4 and earlier install into `.git/hooks` and are
  replaced like the others.)

**The test-debt ratchet is still run by hand.** The commit-time hook now exists,
but nothing wires the ratchet into it, for a structural reason:
`scripts/pre-commit-gate.sh` is **core** and the ratchet is **module** code, so a
call from the gate to the ratchet is exactly the `core → module` edge
[the module contract](module-contract.md)'s M3 forbids and
`scripts/lint-module-dependencies.sh` reds on. Until that is designed, run
`adopt-test-debt.sh --check` by hand or from CI.

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
| Being asked what the project is for, and told whether the stack fits | ✅ [The assessment](#the-assessment--act-3-and-act-4--ships-wp12a) — a Claude Code conversation, then the finisher |
| A fitness verdict, a plan, and the reasoning behind both | ✅ Written by the assessment conversation; checked (two halves, a reason) and recorded by the finisher |
| The required secrets scanner resolved before anything reads the scan — installed where the host has a recipe, named for you where it does not — and the scan re-run after an install | ✅ Tool resolution — ships (WP10a). When the scanner still cannot be resolved, the tier-scoped stop below decides |
| Adoption that can *fail* on a serious finding | ✅ The secrets stop — ships (WP10b): an organizational adoption stops on a finding, an unscanned tree or a partial scan; a personal one continues only on a recorded acknowledgement. [If it stops](#4-if-it-stops) |
| A recorded, non-growing set of untested files | ✅ [Test-debt ledger + ratchet](#the-test-debt-ledger-and-its-ratchet) — ships and works; the commit-time hook that would invoke the ratchet automatically now exists, and wiring the ratchet INTO it is still unbuilt |
| Your colliding hooks/settings archived with a restore path | ✅ Collision archive — ships |
| Plain disclosure of what was archived, path by path | ✅ Ships |
| Putting one of your own files back, warned and recorded | ✅ `--re-add`, ships |
| Adoption refusing to commit a *recognised* secret out of your hooks | ✅ Ships — the archive is scanned before staging and a match is withheld. **A mitigation, not a guarantee** — see below |
| Adoption never committing a file your `.gitignore` excludes | ✅ Ships — the **original's** ignore status decides, not the archive copy's |
| Framework CI installed beside yours, with a recorded keep-or-retire | ✅ [The CI carve-out](#the-ci-carve-out--ships-wp7) — ships; on GitLab it runs once you add one `include`, on Bitbucket you copy its steps |
| An audit trail of the adoption and of every risk accepted during it | ✅ [The audit rows and the dispositions record](#the-audit-rows-and-the-dispositions-record--ship-wp7) — ships |
| A readable record of how this project entered the framework | ✅ [The Adoption Record](#the-adoption-record) — ships, at the end of `APPROVAL_LOG.md`, with its eight-clause contract checked before it is written |
| Secret scanning, SAST and migration checks on every commit | ✅ [The commit-time scanners](#the-commit-time-scanners--ship-wp73) — ships; measured admitting a compliant commit and blocking a non-compliant one by exit code |
| The framework's version of a colliding `scripts/*.sh` installed | ❌ Replacement half — **not built**, and unassigned |
| A `CLAUDE.md` in the adopted project | ✅ [The framework documents](#the-framework-documents--ship-wp12b) — ships; yours is archived and named, not merged in |
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

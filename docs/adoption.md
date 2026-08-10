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
> **Adoption is half built.** The driver, the scenario chooser, the reverse
> intake, the state writes, the adoption stamp and the commit-time enabling arms
> all ship and all work. **The certification pass, the test-debt ledger, the
> collision archive, the CI carve-out and the Adoption Record do not exist.**
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
- [Where each answer lands, and the floor rule](#where-each-answer-lands-and-the-floor-rule)
- [The reverse intake](#the-reverse-intake)
- [What gets written, and in what order](#what-gets-written-and-in-what-order)
- [The adoption stamp, and what happens when it is lost](#the-adoption-stamp-and-what-happens-when-it-is-lost)
- [The TDD exemption and its bound](#the-tdd-exemption-and-its-bound)
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
  --version           print the driver's version and exit
  --help              print this and exit

What it does, in order: reads the survey, offers what the survey found as
EVIDENCE, asks you the one question the survey cannot answer, confirms the
answers it already has and insists on the ones it does not, writes the
project's state, records the adoption, and commits exactly the files it wrote.

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

Before it asks anything, the driver shows what the scan noticed — as **evidence,
never as an answer**, each line carrying its own confidence:

```text
══ What the scan noticed
   None of this is an answer. It is what a read-only look at the code found,
   and each line says how much weight it deserves. Your answer to the next
   question overrides all of it.

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
```

Then it asks, **verbatim**:

```text
══ The one question the scan cannot answer
Is the project built out and needs to be able to be supported (i.e. bug fixes, maintenance, new features add), or are you still in the process of building your project?
   1) It is built out and needs to be supported
   2) I am still in the process of building it
   Answer with the number or the words:
```

Two properties of that sentence are load-bearing. It is written for a
**non-developer** — no phase numbers, no framework vocabulary, no "MVP". And it
asks about the **project's situation**, not its artifacts, because the artifacts
are what the scan already measured and they are frequently misleading: a mature
service with no `README.md`, a weekend prototype with a tagged release.

**There is no default and no skip.** With no answer:

```text
[REFUSED] This question has no default and no skip, and no answer was given: the project's situation
          Adoption did not complete. Nothing has been committed.
```

Inferring the scenario and asking you to confirm it was considered and rejected:
prefill is right for facts the framework itself recorded earlier, and wrong for a
judgement it has never made. A guess presented as a default would make the most
consequential answer in the whole flow the easiest one to skim past.

---

## Where each answer lands, and the floor rule

### S1 — COMPLETED

```text
   This project lands where a finished project lands, and every gate behind it
   has to be certified rather than assumed.
…
══ Adopted
   Scenario: completed. Landed at phase 4.
```

Lands at `current_phase: 4`, adopted, straight into the maintenance era —
everything after this arrives as a [delta](delta-track.md). The interview is
light on futures (no MVP cutline, no Phase-0 success criteria for work that
already shipped) and heavy on operations. Certification scope is **every gate
0→1 through 3→4**, because landing at phase 4 means all four have notionally been
crossed. That makes S1 the heaviest pass — and the correct one.

### S2 — IN-FLIGHT

Lands at the phase its artifacts support, floored by your answer. It reaches the
maintenance era the ordinary way, by shipping v1 through the gates. Docs for what
**exists** are reconstructed; the plan for what is **coming** is authored fresh
and real, and **nothing is grandfathered going forward**.

### The floor rule — the interview can only move the placement DOWN

```text
   From the code alone, the scan placed this project at rung 4 of 4.
   Your answer can move that DOWN if the code flatters the project. It cannot
   move it up: evidence you have not produced is not evidence.

How far along is the work itself? Pick the LAST line that is already true.
   1) None of these yet
   2) We have written down what this project is for
   3) ...and the technical shape of it is written down too
   4) ...and there are tests that actually run
   5) ...and there is a way to get it out the door
   Answer with the number or the words:
   You placed it lower than the code suggested, so it lands at 0. The
   lower number costs more certification, not less, and that is the safe side.
```

Artifact evidence is a claim about what was built; your answer is a claim about
what is true. Where they disagree the safer number wins, because a project placed
**too low certifies more than it strictly needed** and a project placed too high
certifies less than it owed.

### What both scenarios share

- **Data classification is non-skippable**, in both.
- **Both run the full secrets scan** — history does not care what phase you land
  at.
- **Neither gets a forward exemption.** Every exemption in this design is scoped
  to commits **at or before** the adoption commit. There is no arm anywhere that
  exempts a commit written after adoption day.

---

## The reverse intake

Ordinary intake asks a person and writes a document. Reverse intake starts from
what the scan already derived and asks you to confirm it — for the parts that are
derivable, and only those.

```text
══ The interview
   Some of this the scan already answered — you will see the answer and where it
   came from, and you can keep it or change it. The rest only you can answer, so
   there is no default and no way to skip past it.

Project Identity
   The scan found: legacy-app
   Where that came from: package.json name
Keep 'legacy-app' as the answer?
   1) keep it
   2) change it
   Answer with the number or the words:
```

Three classes across the fifteen intake sections:

| Class | Behaviour | Example |
|---|---|---|
| **Scan-derived** | Prefilled with **the value and its provenance**, then keep-it / change-it. "Change it" falls through to the ordinary question | Project Identity, Repo Setup, Testing & Bug Tracking, Tooling Configuration |
| **Judgement** | No prefill, no default, no skip | Business Context, Constraints, Features & Requirements, Technical Preferences, Revenue Model, Governance Pre-Flight, Accessibility, Distribution & Operations, Known Risks |
| **Non-skippable** | No default, no inference, and no "confirm" arm at all | Data classification |

**Data classification is a mechanical necessity, not a policy preference.** The
Phase 1→2 ZDR backstop is a hard `[FAIL]` whenever `current_phase >= 2`, so an
adoption that skipped it would produce a project that cannot pass its own next
gate. Observed on a run that reached that question with nothing to answer it:

```text
Which one describes it?
   1) public
   2) internal
   3) confidential
   4) pii
   5) financial
   6) health
   7) regulated
   Answer with the number or the words:

[REFUSED] Data classification has no default, no guess and no skip — in either scenario. The Phase 1 to 2 gate is a hard FAIL without it, so an adoption that skipped it would produce a project that cannot pass its own next gate.
          Adoption did not complete. Nothing has been committed.
rc=1
```

An out-of-vocabulary answer to a choice question is refused by name rather than
coerced:

```text
[REFUSED] 'legacy-app' is not one of the answers offered for: who the project is for
          Adoption did not complete. Nothing has been committed.
```

---

## What gets written, and in what order

### The order is `phase-state.json` → intake → `manifest.json`

That order is data in the driver, not scattered through it, and it is chosen
because the two half-states are **not symmetrical**:

| Partial state | `check-phase-gate.sh` | Enforcement tier | Net |
|---|---|---|---|
| **phase-state present, manifest absent** | Runs. `[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.` → rc 1 | **strict** (missing file → strict) | **Gates live, strictest tier.** Blocked — the safe direction |
| **manifest present, phase-state absent** | `No .claude/phase-state.json found — skipping phase gate check.` → rc 0 | reads the field | **Gates entirely absent.** An adopted-looking project with no enforcement |

Writing phase-state **first** means every interruption lands in the top row. That
is what the help text means by *"it stops in the SAFE direction: the project ends
up more strictly gated than it was, never less."*

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
   69 file(s), named one by one. Anything else you had in progress stays
   exactly as you left it — unstaged, uncommitted, untouched.
```

The driver builds an explicit array; anything not in it is never staged. The
counter-example this exists to avoid is `create_project()`'s
`git add -A` + `git commit --no-verify`, which on an existing project would sweep
your uncommitted work into a framework commit with verification bypassed.

Observed on a completed S1 run — one commit,
`chore: adopt <project> into the Solo Orchestrator framework`, containing 69
files: `.claude/adoption/scout-report.json`, `.claude/manifest.json`,
`.claude/phase-state.json`, `.claude/process-state.json`,
`.claude/intake-progress.json`, `PROJECT_INTAKE.md`, and the framework `scripts/`
tree. **Your own files are not in it.**

### What lands in `scripts/`

```text
══ Installing the framework's own scripts
   Installed 63 framework script(s); left 0 of your own file(s) untouched.
```

The set is **derived from `init.sh`'s own copy list** rather than duplicated, so
an adopted project's script set cannot drift from a scaffolded one's. Measured,
comparing this adopted project against a project scaffolded by `init.sh` on the
same tree: **63 scripts each, and the difference in both directions is empty.**

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
  "schemaVersion": 1,
  "adopted": true,
  "adoptedAt": "2026-08-10T20:18:37Z",
  "adoptedAtCommit": "c0ba12ef6ecd620b57c55581435138f53a098da2",
  "scenario": "completed",
  "landedPhase": 4,
  "certification": { "kindA": [], "kindB": [], "kindC": [] },
  "blockersAccepted": [],
  "scannerReportSha256": "c5ac90a264f61d55cb3423151d04f8161bf671e3272d09fe14fabad80f302efd"
}
```

**Those three empty certification lists mean "not measured", not "measured and
clean"** — the certification pass is [not built](#what-is-not-built-yet), and the
driver says so during the run.

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
[OK] Adoption stamp present and intact (scenario: completed, adopted: 2026-08-10T20:18:37Z)
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

An adopted project gets exactly the same treatment as a scaffolded one from its
adoption commit onward. As everywhere else in this framework, **the tier decides
whether that is a hard block**: `deployment: organizational` or
`poc_mode: sponsored_poc` blocks the commit, as above; `personal` and
`private_poc` do not. That predicate is unchanged by adoption — it reads
`.claude/phase-state.json`, exactly as it does in a scaffolded project.

---

## What is not built yet

This is the honest half of the page. Everything below is **designed and not
built**. The driver prints a labelled block for each one during the run, naming
the work package that owns it — the text below is what it actually printed.

### The certification pass — WP5

```text
NOT DONE — the certification pass
   Owner: WP5. This build does not do it, and does not pretend to.
   It would have run every gate from 0 to 4, because landing at 4 means all four have notionally been crossed, and a blocker-grade finding would have stopped this adoption.
   Because it did not run, the adoption record's certification lists are EMPTY.
   An empty list here means 'not measured', not 'measured and clean'.
```

This is the largest gap, and the one that matters most. The certification pass is
the whole reason adoption is not grandfathering: it would run every skipped
gate's requirements **for real, today** — the scanners executing against your
actual code, the reviews genuinely held and signed, and only the handful of
things impossible to re-run marked as historical. It would also be able to
**fail**: a blocker-grade finding would stop adoption completing until it was
fixed or explicitly accepted with a recorded signer.

**Today, none of that runs.** An adopted project lands at its phase with its
certification lists empty. Do not read an adopted project as a certified one.

### The test-debt ledger — WP5b

```text
NOT DONE — the test-debt ledger
   Owner: WP5b. This build does not do it, and does not pretend to.
   Existing untested files are not recorded, so nothing yet stops that set from growing.
```

The forward equivalent of the TDD exemption: `.claude/test-debt.json`, recording
the set of source files with no test, with two tier-floored arms — the untested
set may not **grow**, and a file in the set that gets **modified** must leave it
in the same commit. Neither exists. Scout's untested-file count is a starting
figure for a ledger that has nowhere to go yet.

### The collision archive, disclosure and re-adds — WP6

Scout **reports** collisions (see [scout.md](scout.md#collisions--what-the-framework-would-otherwise-trample));
nothing archives them. The designed behaviour — inventory, then archive your
version into a timestamped directory **with a written MANIFEST and restore
instructions**, then install the framework's clean set, then disclose plainly
what moved — does not exist. Nor do the `adoption_event` audit rows.

Related, and printed by the driver:

```text
NOT DONE — your project's framework documents
   Owner: WP6 (they are collision decisions before they are writes). This build does not do it, and does not pretend to.
   CLAUDE.md, the document templates and the reference docs are NOT written. The scripts and the
   state are here, so the gates work; the reading material an agent picks up at the start
   of a session is not, and a CLAUDE.md you already have would be a collision, not a gap.
```

So an adopted project has working gates and **no `CLAUDE.md`** — the file an
agent reads at the start of every session. Write one by hand, or copy
`templates/generated/claude-md.tmpl` from the framework clone and fill it in.

### The CI carve-out, provenance headers and the Adoption Record — WP7

```text
NOT DONE — the provenance headers on reconstructed documents
   Owner: WP7. This build does not do it, and does not pretend to.
   PROJECT_INTAKE.md records where each answer came from, but it carries no machine-readable
   provenance header. A near-miss header is worse than none: WP7 ships a lint for the
   real one, and a lint cannot tell a near-miss from the genuine article.

NOT DONE — the Adoption Record, the audit rows and the CI carve-out
   Owner: WP7. This build does not do it, and does not pretend to.
   APPROVAL_LOG.md is not written, so the phase gate will report it missing until WP7 lands.
   That is the safe direction — a blocked project, not a silently-approved one — but it
   means this adoption (completed, phase 4) is recorded in the manifest and
   nowhere else yet.
```

**The consequence is immediate and you will hit it.** Observed on a
freshly-adopted project:

```text
$ bash scripts/check-phase-gate.sh
[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.
```

The gate stops there. That is the safe direction — a blocked project, not a
silently-approved one — but it means an adopted project's phase gate does not
pass until somebody writes an `APPROVAL_LOG.md`. It also means the **adoption
stamp integrity check runs after that point**, so on a project with no
`APPROVAL_LOG.md` the loss detector never gets to speak.

The **Adoption Record** itself — the one place a successor reads to understand
how this project entered the framework, carrying the scenario, the landed phase,
the certification inventory, the blocker acceptances, the secrets dispositions,
the collision archive path and the CI keep-or-retire decisions — does not exist.
Neither does the eight-clause lint that keeps it structurally unparseable as a
gate approval.

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

**Karl's decision: the commit-time hook is installed by WP7, once the artifacts
it reads exist.** Installing it today would refuse every commit. Until then the
two **message** gates are live — test-before-code ordering, and the Build-Loop
commit check, both demonstrated above — and the scanner arms are not. Run them by
hand.

### And one more, from this page rather than the driver

**This page is not shipped into adopted or generated projects.** `init.sh` copies
seven guides into `docs/reference/`; `docs/adoption.md` and `docs/scout.md` are
not among them. Read them here, in the framework clone you run the driver from.

### Summary — what you can and cannot get today

| You want | Today |
|---|---|
| A read-only survey of an existing codebase | ✅ [Scout](scout.md), complete |
| A guided landing at the right phase, with the scenario chooser and reverse intake | ✅ Ships and works |
| Project state written fail-safe, staged explicitly, committed as its own commit | ✅ Ships and works |
| An adoption stamp, and loud detection when it is lost | ✅ Ships and works |
| Test-first ordering enforced from adoption day forward | ✅ Ships and works |
| Gates that were skipped actually run and recorded | ❌ Certification pass — **not built** |
| Adoption that can *fail* on a serious finding | ❌ Certification pass — **not built** |
| A recorded, non-growing set of untested files | ❌ Test-debt ledger — **not built** |
| Your colliding hooks/settings archived with a restore path | ❌ Collision archive — **not built** |
| Framework CI installed beside yours, with a recorded keep-or-retire | ❌ CI carve-out — **not built** |
| A readable record of how this project entered the framework | ❌ Adoption Record — **not built** |
| Secret scanning, SAST and migration checks on every commit | ❌ Deferred to WP7, by decision |
| A `CLAUDE.md` in the adopted project | ❌ Deferred to WP6 |

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Adoption completed |
| 1 | Adoption did not complete — a refusal, a blocker, or a halt. **Nothing has been committed** |
| 2 | Bad usage, or a target the driver cannot use |

---

## See also

- [scout.md](scout.md) — the read-only survey. Run it first.
- [delta-track.md](delta-track.md) — where an S1 adoption lands: the post-1.0 maintenance loop.
- [designs/2026-08-02-brownfield-adoption-v1.md](designs/2026-08-02-brownfield-adoption-v1.md) — the architecture design, including the full certification-pass specification the build has not reached yet.
- [module-contract.md](module-contract.md) — the severable-module rules the driver is held to.

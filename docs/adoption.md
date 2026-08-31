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
> intake, the state writes, the adoption stamp, the commit-time enabling arms
> the test-debt ledger with its ratchet, and — as of WP6 — **the collision
> archive, its disclosure and its recorded re-adds** all ship and all work.
> **The certification pass, the CI carve-out and the Adoption Record do not
> exist.**
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
          Adoption did not begin. Nothing was committed and nothing was written.
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
          Adoption did not begin. Nothing was committed and nothing was written.
rc=1
```

An out-of-vocabulary answer to a choice question is refused by name rather than
coerced:

```text
[REFUSED] 'legacy-app' is not one of the answers offered for: who the project is for
          Adoption did not begin. Nothing was committed and nothing was written.
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

An adopted project gets **the same commit-time treatment** as a scaffolded one
from its adoption commit onward. As everywhere else in this framework, the tier
decides whether that is a hard block: `deployment: organizational` or
`poc_mode: sponsored_poc` blocks the commit, as above; `personal` and
`private_poc` do not. That predicate is unchanged by adoption — it reads
`.claude/phase-state.json`, which the driver writes correctly, exactly as it does
in a scaffolded project.

> **⚠ Scope that sentence to the commit-time surface, because one other surface
> is NOT the same.** The two birth paths write **different manifests**, and one
> tier reader fails open on the difference.
>
> | Key in `.claude/manifest.json` | Scaffolded by `init.sh` | Adopted |
> |---|---|---|
> | `deployment` | `"personal"` | **absent** |
> | `poc_mode` | `null` | absent |
> | `enforcement_level` | `"strict"` | **absent** |
>
> `assert_choosable` in `scripts/lib/enforcement-level.sh` reads
> `jq -r '.deployment // "personal"'`, so an **absent** key resolves to the
> **permissive** tier. `validate_transition` calls it, `reconfigure-project.sh`
> calls `validate_transition`, and `reconfigure-project.sh` is one of the 63
> scripts adoption installs. Measured: an organizational project with the key
> present refuses a move to `enforcement_level: no`; **the same project with only
> that key removed allows it.**
>
> `read_enforcement_level`, in the same library file, fails *closed* to `strict`
> on the same manifest — so the two readers disagree, and the commit-time gates
> are unaffected. Filed as **`## BL-221:`** with both candidate fixes and the
> `# BL-084-TIER-KEY` sync-sibling warning. **Until it is resolved: if you adopt
> an organizational project, set the manifest's tier keys by hand before anyone
> runs `reconfigure-project.sh`.**

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
and every non-`.sample` file in `.git/hooks/`. **Only files that exist are
archived** — an absent surface produces no file and no manifest row.

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
   Owner: unassigned — §10 names no owner. This build does not do it, and does not pretend to.
   CLAUDE.md, the document templates and the reference docs are NOT written. The scripts and the
   state are here, so the gates work; the reading material an agent picks up at the start
   of a session is not, and a CLAUDE.md you already have would be a collision, not a gap.
   WP6's archive covers your AI-layer settings and your git hooks; documents are neither.
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
| A guided landing at the right phase, with the scenario chooser and reverse intake | ✅ Ships and works |
| Project state written fail-safe, staged explicitly, committed as its own commit | ✅ Ships and works |
| An adoption stamp, and loud detection when it is lost | ✅ Ships and works |
| Test-first ordering enforced from adoption day forward | ✅ Ships and works |
| Gates that were skipped actually run and recorded | ❌ Certification pass — **not built** |
| Adoption that can *fail* on a serious finding | ❌ Certification pass — **not built** |
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
| A `CLAUDE.md` in the adopted project | ❌ **Not built** — unassigned; §10 names no owner |
| The manifest's tier keys, so enforcement cannot be downgraded | ❌ **Not written — `## BL-221:`.** Set them by hand on an organizational adoptee |

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
- [delta-track.md](delta-track.md) — where an S1 adoption lands: the post-1.0 maintenance loop.
- [designs/2026-08-02-brownfield-adoption-v1.md](designs/2026-08-02-brownfield-adoption-v1.md) — the architecture design, including the full certification-pass specification the build has not reached yet.
- [module-contract.md](module-contract.md) — the severable-module rules the driver is held to.

# The Delta Track — what happens after v1.0

Phases 0 through 4 take a product from an idea to a tagged v1.0.0. Then the map
ends, and the product starts living. Users ask for things. Bugs arrive from real
usage. A dependency advisory lands at three in the morning.

**The delta track is the loop for that.** One unit of post-1.0 change is a
*delta*. You say what you need in plain words, answer one question about what
kind of change it is, and the track works out the rest: how much ceremony it
owes, what has to be true before it can close, and what version it ships in.

This page is written from runs against a real scaffolded project. Every
transcript below is output that was observed, pasted as it printed.

**Where these files live.** `scripts/delta.sh`, `scripts/cut-release.sh`,
`scripts/check-maintenance.sh`, `scripts/session-cadence-check.sh` and the four
`scripts/lib/delta-*.sh` libraries are installed into **your generated project**
by `init.sh`. Run them from there.

The two that write — `delta.sh` and `cut-release.sh` — refuse outright if you run
them in the framework clone, including for `--help`:

```text
[FAIL] Refusing to operate inside the Solo Orchestrator framework repo.
  Detected framework signature (cwd): /path/to/solo-orchestrator

  This script targets a project, not the framework itself.
  Move to your project directory and re-run:
    cd /path/to/your-project
```

The two read-only ones do not carry that guard: `check-maintenance.sh` and
`session-cadence-check.sh` both run against the framework repo itself and exit 0
(measured). That is harmless — they only measure — but it means a green run in
the framework clone tells you nothing about your project.

---

## Contents

- [Activation — the track cannot start early](#activation--the-track-cannot-start-early)
- [Opening a delta](#opening-a-delta)
- [The brief, and the one section a program reads](#the-brief-and-the-one-section-a-program-reads)
- [Working and closing](#working-and-closing)
- [The hotfix lane and its debt](#the-hotfix-lane-and-its-debt)
- [Cadence — the calendar the tool watches](#cadence--the-calendar-the-tool-watches)
- [Cutting a release](#cutting-a-release)
- [Ledger rows and what the cut writes into them](#ledger-rows-and-what-the-cut-writes-into-them)
- [Policy you own](#policy-you-own)
- [The session prompt knows about deltas](#the-session-prompt-knows-about-deltas)
- [Exit codes](#exit-codes)
- [What is not built](#what-is-not-built)

---

## Activation — the track cannot start early

A delta can only be opened when `.claude/phase-state.json` says
`current_phase` is **exactly 4**. The invariant is
`active_delta != null ⇒ current_phase == 4`, and `scripts/delta.sh --open` is
its load-bearing enforcement point.

Observed on a project still at phase 0:

```text
$ bash scripts/delta.sh --open --describe "add dark mode"

[FAIL] This project is not finished yet, so there is nothing to maintain.
[INFO] The delta track is for after your product has shipped. This project is at phase 0 — still designing.
[INFO] Finish the build and the launch first — then every later change comes through here.

rc=3
```

**Why the gate exists.** Post-release maintenance ceremony is cheaper than
building the product properly. Without this refusal, a project that found
Phase 1 hard could discover that opening "deltas" is an easier way to write
code — and the cheaper path always wins. The delta track is a loop *inside*
phase 4, not a sixth phase, and `current_phase` never moves again.

`--status` works at any phase and simply says where you are:

```text
$ bash scripts/delta.sh --status

[INFO] Project phase: 0
[INFO] No delta is open. Start one with: scripts/delta.sh --open
```

---

## Opening a delta

### The one question, and the four classes

| Class | Your situation | What it buys you |
|---|---|---|
| **feature** | "I want the product to do something new" | Full ceremony — a brief, a review of that brief before you build, the Build Loop, a close review, a changelog entry |
| **fix** | "Something is broken; it can wait for the normal loop" | A reproduction test written RED first, a lighter close |
| **hotfix** | "Something is broken **now**, in production" | Speed — the standing safety checks and nothing heavier — paid for with a write-up that blocks the next release until it is filed |
| **security-patch** | "Someone could exploit this" | Fix ceremony plus a forced dependency scan, an SBOM refresh, and a flagged release note |

### Confirm, don't quiz

You answer **one** thing. Everything else is proposed with its reasoning shown,
and every line names where its value came from — a proposal whose provenance is
hidden is a quiz with extra steps.

Observed, on a project at phase 4:

```text
$ bash scripts/delta.sh --open --describe "the CSV export crashes on unicode"

You said: "the CSV export crashes on unicode"

  Class:    fix             (proposed from your wording — a fix is something broken
                            that can wait for the normal loop; a hotfix is
                            production, now)
  Severity: SEV-2           (no severity wording matched, so this defaults to the
                            Severity Guide's SEV-2 row (feature broken, workaround
                            exists))
  Risk:     feature-local   (no risk surfaces are configured yet, so nothing can
                            match — every change reads as feature-local until someone
                            lists this project's sensitive paths)
  Level:    small           (2 changed line(s) so far, under this project's small
                            threshold of 50; re-measured from the real diff when the
                            delta closes)

  [1] Keep all four        [2] Change the class        [3] Change an attribute

[FAIL] Nobody is here to confirm this, so nothing was opened.
[INFO] Re-run in a terminal, or add --confirm to accept the four lines above as they stand.
rc=2
```

That last refusal is what you get with no terminal attached (a script, a CI job,
an agent shelling out). In a terminal you answer the prompt; non-interactively
you pass `--confirm` to accept the four lines as they stand.

**The class proposal is a wording heuristic, and it is wrong sometimes.**
Observed: `--describe "the importer drops rows"` was proposed as **feature**,
not fix, because nothing in that phrasing says "broken". Read the four lines
before you confirm them, and override with `--class` when the proposal is wrong:

```text
$ bash scripts/delta.sh --open --describe "unicode filename bug" --class fix --confirm
  Class:    fix             (proposed from your wording — a fix is something broken
  Level:    small           (0 changed line(s) so far, under this project's small
  [OK] Opened DELTA-004 — unicode-filename-bug (fix).
  Before this can ship: ledger_row, repro_test_red_first, close_review, changelog
```

`--risk`, `--level`, `--severity` and `--reason` override the other three lines
the same way. An attribute can always be raised freely; lowering one records a
reason.

### What opening writes

```text
$ bash scripts/delta.sh --open --describe "the CSV export crashes on unicode" --confirm

  [OK] Opened DELTA-001 — the-csv-export-crashes-on-unicode (fix).
[INFO] A row for DELTA-001 is on BUGS.md. Fill in what it says before you mark that check done.
  Before this can ship: ledger_row, repro_test_red_first, close_review, changelog
[INFO] Check where you are at any time with: scripts/delta.sh --status
```

Three things land: a row on `BUGS.md` (or `FEATURES.md` for a feature), the
`gates_required` list materialised into `.claude/delta-state.json`, and — for a
feature, or for anything measured as `evolution` — a brief under `docs/deltas/`.
`.claude/delta-policy.json` is written on first use if it does not exist yet.

The state file is a single `active_delta` slot rather than an array, so
**one delta at a time** is a property of the schema rather than a rule someone
has to remember. A second open is refused by name:

```text
$ bash scripts/delta.sh --open --describe "add dark mode" --confirm

[FAIL] You already have one piece of work open: DELTA-001.
[INFO] It is a fix — the-csv-export-crashes-on-unicode.
[INFO] Finish it or close it before starting another. Run: scripts/delta.sh --status
rc=4
```

### The three creation paths

| Path | How you start it | When it is the one to use |
|---|---|---|
| **Guided** | `bash scripts/delta.sh --open` in a terminal | You are at a shell, no agent session running |
| **Conversational** | Say what you need to your agent in plain words; it fills the brief in with you and opens the delta | **The default.** `scripts/resume.sh` prints a phase-4 greeting that invites exactly this |
| **Manual** | Copy `templates/generated/delta-brief.tmpl` to `docs/deltas/DELTA-NNN-<slug>.md`, fill it in, then `bash scripts/delta.sh --open --slug <slug>` | You would rather write in an editor, or you are offline |

All three converge on the same state. An existing brief for an id is **adopted,
never overwritten** — the manual path is safe to re-run.

---

## The brief, and the one section a program reads

A feature delta gets a brief at `docs/deltas/DELTA-NNN-<slug>.md`, rendered from
`templates/generated/delta-brief.tmpl`. Five sections: **What**, **Why**,
**Done-observable**, **Must-not-change**, **Touched surfaces**.

Four of those are for humans. **`## Done-observable` is parsed**, and it is the
whole review at the end:

```text
[INFO] Write down what has to be TRUE when this is finished, in
       docs/deltas/DELTA-002-add-dark-mode-to-the-settings-screen.md under
       'Done-observable'. That list is the whole review at the end — you are
       writing it now, before you are invested in how you built it.
```

### The checkbox contract, exactly

Taken verbatim from the shipped template's own header comment, which is written
so the template and the parser cannot drift apart:

- The section is opened by **any** heading whose text begins `Done-observable`,
  case-insensitively, at **any** heading depth. A trailing parenthetical is fine.
- It **ends** at the next heading of the **same depth or shallower**. A `###`
  sub-heading nested inside it is still part of the rubric.
- A brief carrying **two** Done-observable headings has **both** read, and the
  criteria are **pooled**. There is no "first one wins".
- A criterion is a list item whose marker is `-`, `*` or `+`, at any indent,
  followed by a bracketed single character. `- [x]` and `- [X]` are done;
  `- [ ]` is not. **Anything else between the brackets counts as not done** and
  is named in the refusal — an undefined marker is a criterion nobody has
  decided about.
- It **fails closed**: no file, two files claiming the same id, no
  Done-observable heading, or a heading with no checkboxes under it are each a
  refusal to close. An empty rubric would let the work close on nothing at all.

Observed — the close refusing on unticked boxes:

```text
$ bash scripts/delta.sh --close

[FAIL] You wrote down what would be true when DELTA-002 is done, and some of it is not ticked off yet.
  - [the first thing you will be able to see working]
  - [the second thing you will be able to see working]
[INFO] That list is in docs/deltas/DELTA-002-add-dark-mode-to-the-settings-screen.md, and it is the whole review — you wrote it before you were invested in how you built this.
[INFO] Finish those, tick them, then close. Nothing was closed.

rc=8
```

And the fail-closed direction, observed on a delta that owed a brief and had
none:

```text
[FAIL] DELTA-004 needs a written-up plan and there isn't one to check against.
[INFO] It should be at docs/deltas/DELTA-004-<short-name>.md, with a '## Done-observable' section listing what has to be true when this is finished.
[INFO] Nothing was closed.
```

---

## Working and closing

### Per-class gates

| Gate token | feature | fix | hotfix | security-patch | Also added when |
|---|---|---|---|---|---|
| `brief` | ✅ | — | — | — | `level: evolution` on any class |
| `brief_review` (adversarial review **before** you build) | ✅ | — | — | — | `risk: core` on any class |
| `ledger_row` | ✅ | ✅ | ✅ | ✅ | — |
| `build_loop` | ✅ | — | — | — | — |
| `repro_test_red_first` | — | ✅ | — | ✅ | — |
| `audit_row_at_open` | — | — | ✅ | — | — |
| `retro_review` | — | — | ✅ | — | — |
| `dependency_scan` | — | — | — | ✅ | — |
| `sbom_refresh` | — | — | — | ✅ | — |
| `flagged_release_note` | — | — | — | ✅ | — |
| `close_review` | ✅ | ✅ | *(carried by `retro_review`)* | ✅ | — |
| `changelog` | ✅ | ✅ | ✅ | ✅ | — |
| `threat_model_refresh` | — | — | — | — | the **touch trigger** — the real touched-file set intersecting `risk_surfaces` |

Every row above except the last was observed on a real open. **The touch trigger
was not exercised for this page**, because `risk_surfaces` ships empty and
nothing matched: the table entry is transcribed from the shipped
`.claude/delta-policy.json`, not from a run. One token covers both halves of that
demand — the threat-model update **and** the scoped scanner re-run — because they
are never independently completable: an update without a re-scan is an assertion,
and a re-scan without the update is a finding nobody wrote down.

**Two gates the hotfix row does not have, and why neither is missing.** A hotfix
carries no `close_review` because `retro_review` **is** that review, arriving late
and collateralised by the release refusal — giving it both would either
double-charge the review or let a hotfix satisfy `close_review` at ship time and
make the retro optional, which is the loan going unrepaid.

Everything above is *in addition to* the standing floor — gitleaks, semgrep,
your project's tests and the TDD ordering gate — which the delta track inherits
untouched and adds no second copy of.

### Most gates are your word; two are checked

```text
$ bash scripts/delta.sh --complete-gate ledger_row

  [OK] Recorded: ledger_row is done for DELTA-001.
[INFO] This is your word for it — the record now says you did it, and nothing here re-checks it.
[INFO] The two things this tool does check for itself are the tick-boxes in your brief and how big the change actually turned out to be, both when you close.
[INFO] See where you are with: scripts/delta.sh --status
```

That is stated plainly rather than dressed up. `--close` refuses while anything
is outstanding:

```text
$ bash scripts/delta.sh --close

[FAIL] DELTA-001 is not finished yet.
[INFO] Still to do: ledger_row, repro_test_red_first, close_review, changelog
[INFO] Mark one done with: scripts/delta.sh --complete-gate <name>

rc=7
```

`--status` shows the same picture at any point:

```text
$ bash scripts/delta.sh --status

[INFO] Project phase: 4
  Open delta:  DELTA-001  (fix)
  What:        the-csv-export-crashes-on-unicode
  Opened:      2026-08-10T20:10:59Z  via guided
  Risk:        feature-local
  Level:       small
  Severity:    SEV-2
  Still to do: ledger_row, repro_test_red_first, close_review, changelog
  Done:        nothing yet
```

### The ratchet — a delta that grows is re-measured

At open the diff is usually empty, so `risk` and `level` are forecasts. At close
they are **re-derived from the real diff**. A re-derivation that lands in a
higher bracket **raises** the attribute — and a raise is announced, not silent:

```text
$ bash scripts/delta.sh --close

[INFO] Re-measured from what you actually changed:
[INFO]   how big:    small -> significant
[INFO] That is on the record now. It only ever goes up — a smaller change later never talks it back down.

  [OK] Closed DELTA-002 (feature).
```

A raise that crosses a toggle **gains a gate**, and the close refuses on it.
Observed on a `fix` opened `small` and grown past the 400-line evolution
threshold — `level: evolution` toggles `brief` on, which a fix does not
otherwise owe:

```text
$ bash scripts/delta.sh --close

[INFO] Re-measured from what you actually changed:
[INFO]   how big:    small -> evolution
[INFO] That is on the record now. It only ever goes up — a smaller change later never talks it back down.

[FAIL] This turned out to be a bigger change than it looked when you started, so it needs more checking before it can close.
  Now also needed: brief
[INFO] That is measured from what you actually changed, not from what you said at the start — and it only ever goes up.
[INFO] Do those, mark them done with --complete-gate, then close again.

rc=10
```

Without the ratchet, a delta opened as `small`/`feature-local` and grown into an
auth rewrite would close on the small checklist.

**Two honest limits.** `level` is lines changed, and lines are a poor proxy — a
12-line auth change is riskier than a 900-line locale file. That is exactly why
`risk` is a **separate axis derived from paths**, and why you can raise either
one freely. And `risk` is only as good as `risk_surfaces`, which ships **empty**
(see [Policy you own](#policy-you-own)) — until you fill it in, every delta reads
`feature-local`, and the tool says so on every open rather than hiding it.

---

## The hotfix lane and its debt

A hotfix ships on the floor alone plus an audit row. It does not skip review —
it **defers** it by three days, and the deferral is collateralised.

Observed:

```text
$ bash scripts/delta.sh --open --describe "production is down, payments are failing right now" --confirm

  Class:    hotfix          (proposed from your wording, which says this is live and
                            now — a hotfix ships fast and owes a retro within days; a
                            fix waits for the normal loop)
  Severity: SEV-1           (no severity wording matched, so this defaults to the
                            Severity Guide's SEV-1 row — a hotfix is a live break on
                            a core flow)
  ...

  [OK] Opened DELTA-005 — production-is-down-payments-are-failing (hotfix).
[INFO] This is the fast lane: it ships on the standard safety checks and nothing heavier.
[INFO] That borrows the checking a normal change goes through, so you owe a write-up of what happened by 2026-08-13T20:13:09Z — 3 day(s) from now.
[INFO] It is already on the record. Nothing can be released until you file it:
[INFO]   scripts/delta.sh --retro DELTA-005 --record "what happened, and what stops it happening again"
```

**The retro row is written at open, not at close**, and it **outlives** the
delta. `hotfix_retros[]` in `.claude/delta-state.json` after that open:

```json
[
  {
    "id": "DELTA-005",
    "shipped_at": "2026-08-10T20:13:09Z",
    "due_by": "2026-08-13T20:13:09Z",
    "closed_at": null,
    "record": null
  }
]
```

Close the delta and the row is still there. Try to cut a release and it is
called in:

```text
$ bash scripts/cut-release.sh
Cutting a release

[FAIL] A hotfix still owes its write-up, so this release is refused.
  Shipping a hotfix borrows the checks a normal change goes through. The write-up is how
  that gets paid back, and a release is the moment it comes due. Still outstanding:

    DELTA-005 — due 2026-08-13T20:13:09Z, 2 day(s) from now

To clear this: file each write-up with
  scripts/delta.sh --retro DELTA-NNN --record "what happened, and what stops it happening again"
rc=4
```

Filing it takes either a path to a file you wrote or the short version in quotes:

```text
$ bash scripts/delta.sh --retro DELTA-005 --record "Payments went down because the currency formatter threw on a null locale. Added a null guard and a regression test."

  [OK] Filed the write-up for DELTA-005.
[INFO] Recorded as your own summary — there is no file at "Payments went down because…", so the words you typed are what is on the record.
[INFO] Nothing else is outstanding — releases are clear.
```

**What this buys, honestly.** The fast lane is a loan and the retro is the
repayment; the release refusal is the only thing that ever collects. A project
that simply stops cutting releases leaves the debt uncollected, and the
session-start nag is the only other pressure. That is a real limit of the
mechanism, not a gap in it.

---

## Cadence — the calendar the tool watches

`scripts/check-maintenance.sh` measures two cadences, and both windows are
**policy, not constants**:

| Cadence | Signal it reads | Default window | Policy key |
|---|---|---|---|
| **Routine review** | last commit touching `CHANGELOG.md`, and last touching `sbom.json` | 14 days | `cadence.routine_review_days` |
| **Deep security scan** (dependency audit folded in) | newest dated file in `docs/test-results/` matching `*snyk*`, `*dep*`, `*audit*`, `*semgrep*` or `*sast*` | 95 days | `cadence.deep_security_days` |

### Three answers, and the third one is the point

- **0** — every applicable cadence was measured and is current.
- **1** — one or more are **overdue**.
- **2** — one or more **could not be measured**, and none is overdue.

**A release cut refuses on 1 and on 2.** Unmeasurable is not a pass. Observed —
a project with a `docs/test-results/` directory holding nothing the checker can
read:

```text
$ bash scripts/cut-release.sh
Cutting a release

[FAIL] A maintenance cadence could not be measured, so this release is refused.
  What the check reported, verbatim:

    Maintenance Cadence Check

      [OK] Routine review (CHANGELOG.md) current: last signal 0 days ago (threshold: 14 days)
    [INFO] No sbom.json — the SBOM refresh cadence has no signal here (not applicable)
    [WARN] Deep security scan (dependency audit folded in) — CANNOT MEASURE: docs/test-results/ exists but holds no dependency- or security-scan artefact

    1 maintenance cadence(s) COULD NOT BE MEASURED:
      - Deep security scan (dependency audit folded in): docs/test-results/ exists but holds no dependency- or security-scan artefact

    Nothing above is overdue — but the cadences named there were never measured, so
    'current' is not something this check can claim. …

To clear this: do the maintenance the report names above, commit it so the dates move,
  and run 'bash scripts/check-maintenance.sh' until it exits 0. An unmeasurable cadence
  needs a signal the check can read, not an exemption.
rc=5
```

Before this was repaired, an unreadable date was skipped in silence and reported
as current — a cadence nobody had measured could sail through a tag. Fail-open
was the direction that mattered.

### A cadence surface you do not have is not a failure

No `sbom.json` reports **not applicable** and moves no counter, as in the
transcript above. The tool measures cadences you keep; it does not audit whether
you keep them.

### The session nag

`scripts/session-cadence-check.sh` is registered as a SessionStart hook by
`init.sh`. It is **silent when nothing is wrong** — observed, on a project with
both cadences current: no output, rc 0. When something is overdue:

```text
$ bash scripts/session-cadence-check.sh
[maintenance] a cadence is OVERDUE. A release cut will refuse until it is cleared.
  [WARN] Deep security scan (dependency audit folded in) OVERDUE: last signal 585 days ago (threshold: 95 days)
  Run: bash scripts/check-maintenance.sh
```

It exits 0 either way — a nag that could fail a session start would be a worse
problem than a stale cadence.

**What a green run does not prove.** Two of these signals are dates parsed out
of **filenames**. A file named with today's date and containing nothing
satisfies the cadence completely. The windows make the *schedule* stricter; they
do not make the *evidence* stronger.

It is wider than "a dated empty file", and worth knowing before you rely on the
release refusal (`## BL-222:`): the deep-security arm matches `*snyk*`, `*dep*`,
`*audit*`, `*semgrep*` or `*sast*`, so **`*dep*` matches a
`deployment-notes-2026-08-10.md`** — and since the dependency audit was *folded
into* the deep-security cadence, one stray match now satisfies the whole clock
that `cut-release.sh` refuses on. A freshly-dated empty **directory** or a
dangling symlink satisfies it too. Treat a green cadence as "somebody is keeping
the calendar", and put a real scan artefact in `docs/test-results/` because you
want the scan, not because you want the gate to pass.

---

## Cutting a release

`bash scripts/cut-release.sh` refuses three times before it writes anything at
all, in this order — cheapest and clearest first:

**1. An open delta.**

```text
[FAIL] DELTA-007 is still open, so there is nothing settled enough to release.
  A release names what is finished. Work that is still open is neither in this release nor
  out of it, and whichever the tag implied would be wrong.

To clear this: finish or abandon DELTA-007 first —
  scripts/delta.sh --status     to see what it is still waiting on
  scripts/delta.sh --close      when everything it needs is done
rc=3
```

**2. An unfiled hotfix retro** — the transcript above, rc 4.

**3. An overdue or unmeasurable cadence** — the transcript above, rc 5. This is
the expensive refusal, which is why it speaks last.

**No write of any kind happens before all three pass.** A partially-cut release
— changelog promoted, tag absent — is a worse state than a refused one, because
it is a repository whose changelog claims a version no tag names and no pipeline
ever built.

### Semver is decided by the tool

| What closed since the last tag | Bump |
|---|---|
| Any row carrying a breaking marker | **major** — plus a full `run-phase3-validation.sh` re-run before the tag is written |
| Else any `feature` | **minor** |
| Else (fix / hotfix / security-patch only) | **patch** |
| Nothing | **refuse** — nothing to release |

**There is no override flag.** An operator who disagrees with the computed bump
has to change what they shipped or move the tag by hand outside the tool. That is
the decision, and its cost is real for a project that wants marketing majors or a
permanent `0.x`.

The class→bump map is retunable in `delta-policy.json::semver`; the **precedence
order** above is machinery and is not configurable, because a project that could
reorder it could make a feature release a patch.

**The major lane is unreachable in v1, and this page will not pretend
otherwise.** The breaking-marker row and the full-revalidation lane are built and
tested, but **nothing in `delta.sh`'s close pathway ever sets the field
`cut-release.sh` reads** — not `--open`, not `--close`, not `--complete-gate`,
and there is no flag for it. Every cut on a real project today computes minor or
patch. Tracked as **`## BL-219:`**, where the writer's proper home (the
close/confirm surface, routed through the seam) is recorded.

`scripts/cut-release.sh`'s header says of this gap that it is "filed as a tracked
item". **It was not** — checked against `solo-orchestrator-backlog.md` and
`solo-orchestrator-followups.md` on `main` at `1943172`, neither this gap nor its
companion was filed anywhere. BL-219 and `## BL-220:` exist because of that
check. The lesson is worth carrying off this page: **a "this is tracked"
sentence is a claim like any other, and repeating it without looking is how an
unverified assertion acquires a second source.**

### The tag format is constrained, not chosen

The cut emits **exactly** `vMAJOR.MINOR.PATCH`. No `-rc1`, no `-beta`, no
two-component tag. The reason is a measured asymmetry in the shipped release
lanes: GitHub and Bitbucket match `v*`, but **GitLab matches
`/^v\d+\.\d+\.\d+$/`**. A `v1.2.0-rc1` would build on two hosts and silently do
nothing on the third — green on the host you tested, dead on the one you did not.

### A complete cut

```text
$ bash scripts/cut-release.sh
Cutting a release

  Last release:      none
  Closed since then: 5 change(s)
    DELTA-001 (fix -> patch)
    DELTA-002 (feature -> minor)
    DELTA-003 (feature -> minor)
    DELTA-004 (fix -> patch)
    DELTA-005 (hotfix -> patch)
  Version:           v0.1.0  (a minor release, decided from the classes above)

  [OK] Promoted CHANGELOG.md: '## [Unreleased]' is now '## [0.1.0] — 2026-08-10', with a fresh empty Unreleased above it.
  [OK] Recorded v0.1.0 against 5 closed change(s) in the delta record.
  [OK] Closed 5 bug/feature row(s) with v0.1.0.

  [OK] v0.1.0 is cut.

=======================================================================
 READ THIS BEFORE YOU PUSH: v0.1.0 POINTS AT THE WRONG COMMIT RIGHT NOW
=======================================================================
 The tag names the commit you were on BEFORE the changelog was promoted.
 Push it as it stands and your pipeline builds a release whose changelog
 does not contain this version. It goes GREEN while publishing the wrong
 thing, which is the failure you would not notice.

   >>>  git tag -f v0.1.0   <<<  is NOT optional. Do it in step 3 below.
        The tag has not been pushed, so moving it costs nothing.
=======================================================================

What happens next, in this order:
  1. git add CHANGELOG.md .claude/delta-state.json BUGS.md FEATURES.md
  2. git commit -m "chore(release): v0.1.0"
  3. git tag -f v0.1.0          <-- the step above. Do not skip it.
  4. git push && git push origin v0.1.0

  Your release pipeline fires on the tag push in step 4, and not before.
```

Read that banner and do step 3. The tool tags before you commit the changelog
promotion, so the tag as created points one commit too early; `git tag -f` after
the release commit is what makes the tag name the tree that contains its own
changelog entry. Nothing has been pushed at that point, so moving it is free.

**What the cut writes:** the `CHANGELOG.md` promotion (the `## [Unreleased]`
heading becomes `## [X.Y.Z] — YYYY-MM-DD` with a fresh empty Unreleased block
above it, all eight category headings preserved verbatim and no prose invented),
`shipped_in` against each closed row in the delta record — recorded **through the
seam**, never by touching the state file directly — the ledger-row closes below,
and the tag.

---

## Ledger rows and what the cut writes into them

Post-1.0 work carries its `DELTA-NNN` id into your existing ledgers, in existing
columns. `BUGS.md`'s table format is parsed by scripts and its own header
forbids format changes, so the delta link rides the **`Fix Reference`** column
that already takes "PR #12"-shaped values. `FEATURES.md` blocks gain a
`**Phase Built:** 4 (post-1.0 DELTA-NNN)` line and a `**Brief:**` line.

**The release cut closes those rows.** Observed after the cut above:

```text
BUGS.md
| 1 | SEV-2 | Fixed | the-csv-export-crashes-on-unicode | … | DELTA-001 shipped in v0.1.0 | - |

FEATURES.md
**Phase Built:** 4 (post-1.0 DELTA-002)
**Status:** Complete (shipped in v0.1.0)
```

`BUGS.md` goes `Open` → `Fixed` with the version appended to the **existing**
`Fix Reference` cell. `FEATURES.md`'s `**Status:**` becomes
`Complete (shipped in vX.Y.Z)`.

### The behaviour to know about: a block with no `Phase Built` line is not matched

**A `FEATURES.md` block that does not carry a `**Phase Built:**` line naming the
delta is no longer matched at all.** Previously a block that merely *mentioned*
the id could be flipped. It now reports the row as absent and hands it to a
human.

This is the safe direction — the alternative is stamping a shipped version onto
somebody else's feature and reporting success — but it is real for a project
whose `FEATURES.md` predates the delta track, or whose blocks were written by
hand. Those rows will not close automatically and the cut will tell you so.

Observed, on a delta whose `Phase Built` line had been removed:

```text
  [OK] Promoted CHANGELOG.md: '## [Unreleased]' is now '## [0.2.0] — 2026-08-10', …
  [OK] Recorded v0.2.0 against 1 closed change(s) in the delta record.

[WARN] v0.2.0 was recorded, but not every bug or feature row could be closed. These still read as open:

    DELTA-006 - FEATURES.md has no row naming it, so there was nothing to close

  Nothing was recorded as closed for those. The release is real; the paperwork is not.

To clear this: close each row above by hand. In BUGS.md set its Status cell to 'Fixed' and
  add v0.2.0 beside its DELTA id in the Fix Reference column; in FEATURES.md set its Status
  line to 'Complete (shipped in v0.2.0)'. This release will not offer again — the record
  already says the work shipped, so the next cut has nothing to re-close.

  [OK] v0.2.0 is cut.
…
[WARN] This cut did not close every ledger row it shipped - the list is above.
rc=12
```

**Exit 12 means "the release is real, the paperwork is not."** The release
genuinely happened — changelog promoted, `shipped_in` recorded, tag created — so
it is not failed for a ledger problem. The cut simply does not report clean, and
it names every row it could not close. It fires when a row is absent, when the
write fails, or when the ledger cannot be read. **The next cut will not offer
those rows again**, because the record already says the work shipped: close them
by hand from the list the cut printed.

---

## Policy you own

`.claude/delta-policy.json` is written once, with framework defaults, and
**nothing ever rewrites it**. `scripts/upgrade-project.sh` prints a notice naming
any policy key the framework has learned since, and applies none of them. An
**absent key falls back to the framework default at read time**, so an old file
is never broken by a new framework — it is merely quiet.

| Key | What it does |
|---|---|
| `classes.<class>.gates` | The gate list each class starts with |
| `classes.hotfix.retro_due_days` | How long a hotfix has to file its retro (default `3`) |
| `attribute_toggles.risk_core` | Gates added when `risk` derives or is raised to `core` (default: `brief_review`) |
| `attribute_toggles.level_evolution` | Gates added when `level` reaches `evolution` (default: `brief`) |
| `attribute_toggles.touch_trigger` | Gates added when the touched-file set hits a risk surface (default: `threat_model_refresh`, which bundles the threat-model update **and** the scoped scanner re-run — they are never independently completable) |
| `risk_surfaces` | **Ships empty.** A glob list of this project's auth, data-contract and threat-model paths. Until you fill it in, every delta reads `feature-local` |
| `size_thresholds` | `{"small": 50, "significant": 400}` — changed lines |
| `cadence` | `{"routine_review_days": 14, "deep_security_days": 95}` |
| `fix_sla` | SEV-keyed response times for fixes and hotfixes |
| `cvss_sla` | CVSS-keyed response times for security patches — a CVE arrives with a CVSS score, not a SEV, which is why there are two tables and not one |
| `semver` | The class→bump map. The **precedence** between bumps is not configurable |

`risk_surfaces` ships empty on purpose. A framework-guessed default
(`src/auth/**`? `**/schema*`?) would be wrong for most projects and, worse, would
look authoritative.

---

## The session prompt knows about deltas

`bash scripts/resume.sh` gained a fourth branch ahead of the classic resume
prompt. At phase 4 with a delta open, it resumes *that delta*:

```text
We are resuming a piece of post-release work on this product.

**In progress:** DELTA-007 — small-tweak
**Kind of change:** fix
**Agreed at the start:** risk feature-local, size small, severity SEV-2
**Written-up plan:** none — this kind of change does not need one
**Still to do before it can ship:** ledger_row, repro_test_red_first, close_review, changelog
**Already done:** nothing yet

**Maintenance:** Routine maintenance is OVERDUE — run scripts/check-maintenance.sh to see which window.
…
Read CLAUDE.md for full product context, then pick this up where we left off. The plan file above is the review at the end — if what we build stops matching it, say so rather than quietly changing the plan.
```

At phase 4 with nothing open, it invites the conversational path:

```text
This product has shipped. Nothing is in progress right now.

Everything from here on is one piece of work at a time — a new feature, a fix, an urgent fix, or a security patch. I do not need to know which; I will tell you in plain words what I need and you work out the rest with me.

**Maintenance:** Routine maintenance is OVERDUE — run scripts/check-maintenance.sh to see which window.
…
Read CLAUDE.md for full product context and for how post-release work is run here. Then ask me what I need.
```

**Honest tier: advisory.** A greeting cannot make anyone do anything. What it
changes is *when* you learn the rule — before you act rather than after.

---

## Exit codes

Read the code, not the label — in this framework a printed `[WARN]` and a
blocking outcome can coexist, so the exit status is the verdict.

The tables below are each script's own declared contract. **Observed in the runs
on this page:** `delta.sh` 0, 2, 3, 4, 7, 8, 10; `cut-release.sh` 0, 3, 4, 5, 12.
The remaining rows are transcribed from the scripts and were not exercised here.

**`scripts/delta.sh`**

| Code | Meaning |
|---|---|
| 0 | The delta was opened or closed, a gate was recorded, or `--status`/`--help` ran |
| 1 | An operation failed — the seam refused a write, `jq` is missing, … |
| 2 | Invocation error: a bad flag, a missing argument, a gate token this delta does not carry, or a confirmation needed with no terminal attached |
| 3 | `--open` refused: the project is not at phase 4 |
| 4 | `--open` refused: a delta is already open |
| 5 | An attribute was **lowered** with no reason recorded |
| 6 | There is nothing open to close, or to record against |
| 7 | `--close` refused: gates outstanding |
| 8 | `--close` refused: unticked Done-observable boxes, or no rubric to read |
| 9 | An unknown gate token — a configuration error, failing **closed** |
| 10 | `--close` refused: the close-time re-measurement raised an attribute and **added a gate** |

**`scripts/cut-release.sh`**

| Code | Meaning |
|---|---|
| 0 | The release was cut, cleanly |
| 2 | Invocation / environment error |
| 3 | Refusal 1 — a delta is open |
| 4 | Refusal 2 — an unfiled hotfix retro (or a ledger nobody can read) |
| 5 | Refusal 3 — cadence overdue or unmeasurable |
| 6 | The delta record exists and cannot be read |
| 7 | There is no delta record at all |
| 8 | Nothing closed since the last tag |
| 9 | A closed row's class maps to no bump (fail-closed) |
| 10 | Major bump, and the revalidation re-run did not pass |
| 11 | A write failed after every refusal passed — the cut is incomplete, and the message says how far it got |
| 12 | **The release was cut AND one or more ledger rows could not be closed** — see above |

---

## What is not built

- **The `breaking` marker has no writer** (`## BL-219:`). The major-bump lane and
  the full-revalidation re-run are built and tested but production-unreachable in
  v1: nothing sets the field the cut reads. Every real cut computes minor or
  patch.
- **Severing the delta module takes `check-maintenance.sh`'s only behaviour
  coverage with it** (`## BL-220:`). `tests/test-delta-wp6-cadence.sh` is a
  delta-track suite that is also the only test of a CORE script's three-code exit
  contract, and the severability sever deletes it along with the rest of the
  module's suites. It costs nothing until the day someone actually severs.
- **Concurrent deltas.** One at a time, encoded structurally in the state
  schema. A second concurrent delta would need a queue, a per-delta gate ledger,
  and an ordering rule for the release cut.
- **A semver override flag.** None in v1, by decision.
- **Pre-release and channel tags.** `-rc1` / `-beta` are out of v1; the GitLab
  release lane's regex would have to change first.
- **This page is not shipped into generated projects.** `init.sh` copies seven
  guides into `docs/reference/` (verified: builders-guide, cli-setup-addendum,
  executive-review, governance-framework, security-scan-guide,
  uat-authoring-guide, user-guide). `docs/delta-track.md` is not among them —
  read it here, in the framework repo. Your project's own `CLAUDE.md` carries a
  short delta-track section that points back at this file.

---

## See also

- [designs/2026-08-02-delta-track-v1.md](designs/2026-08-02-delta-track-v1.md) — the architecture design, including the decisions, the rejected alternatives, and the honest residuals.
- [builders-guide.md](builders-guide.md) § Step 4.4 — the maintenance cadences in the context of the whole methodology.
- [module-contract.md](module-contract.md) — the severable-module rules the delta track is held to.
- [adoption.md](adoption.md) — how a project that already exists gets to phase 4 in the first place.

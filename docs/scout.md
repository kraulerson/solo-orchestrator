# Scout — a read-only look at a codebase

Point Scout at a project you already have and it will tell you what it found:
what the project is built in, how far along it looks, whether its tests run,
whether any credentials are sitting in its git history, and exactly which of your
files the framework would otherwise trample.

**It writes nothing.** That is the whole promise. You can run it, read it, and
walk away. Nothing is installed, nothing is decided, nothing is changed.

```bash
bash scripts/scout.sh                       # JSON report for the current directory
bash scripts/scout.sh --root ../their-app   # …for somewhere else
bash scripts/scout.sh --markdown            # the same findings, written for a person
bash scripts/scout.sh --out ./scan          # write both files into ./scan
```

Scout runs **from the framework clone**, pointed at somebody else's project. It
does not need the framework to be installed in the project it is looking at, and
it is not copied into scaffolded projects — a survey that requires installing the
thing it is surveying is not a survey.

Everything on this page is output that was observed, pasted as it printed.

---

## Contents

- [The two properties everything else serves](#the-two-properties-everything-else-serves)
- [Options](#options)
- [The seven sections](#the-seven-sections)
- [The limits Scout states about itself](#the-limits-scout-states-about-itself)
- [Exit codes](#exit-codes)
- [What comes next](#what-comes-next)

---

## The two properties everything else serves

### 1. Read-only

Scout writes nothing into the tree it is pointed at — no cache, no state file, no
marker. Its only writes are a private working directory under `$TMPDIR` (removed
on exit) and the two report files, and only when you ask for them with `--out`.

Measured on a fixture, hashing every file in the tree including `.git/`, before
and after a full scan:

```text
$ before=$(find . -type f -exec shasum {} \; | sort | shasum)
$ bash scripts/scout.sh >/dev/null
$ after=$(find . -type f -exec shasum {} \; | sort | shasum)
before: 1877fd0f65a8dd930f1cfe25e99f63288152e896  -
after : 1877fd0f65a8dd930f1cfe25e99f63288152e896  -
IDENTICAL
```

The guarantee is Scout's, not your project's. See
[`--run-tests`](#the-one-thing-that-runs-your-code) — the one place Scout will
execute code you wrote, and it is off unless you ask.

### 2. Zero dependency

`scripts/scout.sh` plus `scripts/lib/scout/` is the entire program. It sources no
core library and calls no other script in this repository.

**It does not need `jq`** — measured, by running a full scan with `jq` absent from
`PATH` entirely: rc 0, **zero bytes on stderr**, and a complete 10,680-byte JSON
report with every section present.

`gitleaks` is the one external tool it will use, and its absence is reported as
absence rather than as a clean result — see [`secrets`](#secrets--full-history-and-the-value-is-never-printed).

---

## Options

```text
$ bash scripts/scout.sh --help
Scout — a read-only look at a codebase.

  bash scripts/scout.sh [--root DIR] [--markdown] [--out DIR]

  --root DIR    the project to look at (default: the current directory)
  --markdown    print the human-readable report instead of the JSON one
  --out DIR     write BOTH reports into DIR as scout-report.json and
                scout-report.md, and print where they went
  --run-tests   ALSO run the project's own test command, once, to record
                whether it passes today. This is the only thing Scout does
                that runs your code, so it is off unless you ask. Bounded by
                SCOUT_TEST_TIMEOUT seconds (default 300).
  --version     print Scout's version and exit
  --help        print this and exit

Scout never changes the project it looks at. Without --out it writes nothing
at all except its own output. It needs `gitleaks` for the secrets section; if
that is missing the section says so rather than reporting a clean scan.

Exit codes: 0 a scan completed (findings are not errors); 2 bad usage or an
unreadable target.
```

`--out` writes exactly two files and says where they went:

```text
$ bash scripts/scout.sh --out ../scan
Wrote /…/scan/scout-report.json
Wrote /…/scan/scout-report.md
```

`bash scripts/scout.sh --version` prints `0.3.0-wp2` on the tree this page was
written against.

---

## The seven sections

This build emits all seven, and `sectionsNotEmitted` survives as an **empty
array** rather than being deleted — "we have not looked yet" and "we looked and
it was clean" are different claims, and for the secrets section that difference
has a credential behind it.

### `stack` — what this project is built with

```text
| Language | Files | How sure we are |
|---|---|---|
| javascript | 5 | medium |
| shell | 1 | low |

- **Package managers in use:** none found
- **Build / manifest files:** package.json
- **How the tests are run:** `node test/run.js` (found in package.json scripts.test)
- **Where the automated checks live:** github
```

### `phaseMap` — how far along the project looks

An artifact ladder, re-expressed over the adoptee's own evidence rather than
framework filenames: something describing the product → something describing its
technical shape → a runnable test corpus → a deploy or release lane.

```text
**Suggested starting point: 4.** The project is described, its shape is written down, it has runnable tests, and there is a way to get it out the door.

This is a ceiling, not a verdict: maximum satisfied rung; the interview may only lower this

| Step | Found? | What we looked at |
|---|---|---|
| 1 | yes | README.md (the product is described in writing) |
| 2 | yes | docs/ARCHITECTURE.md (the technical shape is documented) |
| 3 | yes | test corpus at test/, runnable with `node test/run.js` |
| 4 | yes | .github/workflows/deploy.yml (a deploy or release lane) |
```

**The ladder stops at the first gap.** `suggestedPhase` is the highest
*contiguously reached* rung, not the plain maximum — landing at phase N means
certifying every gate below N, and that is a property of a prefix, not of a
satisfied set with a hole in it. The plain maximum is published beside it as
`highestSatisfiedRung`, so the gap between the two is information rather than
something thrown away.

Observed on a fixture whose rungs are yes / no / no / yes:

```json
{
  "suggestedPhase": 1,
  "highestSatisfiedRung": 4,
  "rungs": [
    { "rung": 1, "evidence": "README.md (the product is described in writing)", "satisfied": true },
    { "rung": 2, "evidence": "no architecture or design document found — looked for PROJECT_BIBLE.md, ARCHITECTURE.md, DESIGN.md, docs/architecture*, docs/design*, docs/adr*, docs/rfcs", "satisfied": false },
    { "rung": 3, "evidence": "a test command exists (`node test/run.js`) but no test corpus was found", "satisfied": false },
    { "rung": 4, "evidence": ".github/workflows/deploy.yml (a deploy or release lane)", "satisfied": true }
  ],
  "note": "maximum satisfied rung; the interview may only lower this"
}
```

**Read the two numbers, not the `note` string.** The `note` says "maximum
satisfied rung" while `suggestedPhase` is the reached rung — 1 here, against a
maximum of 4. That wording is kept deliberately unchanged and disclosed rather
than quietly reworded; `suggestedPhase` and `highestSatisfiedRung` are the
authoritative pair.

### `reality` — what is already set up

Five probes, each with the evidence it used:

```text
| Check | Result | How Scout decided | Internal name |
|---|---|---|---|
| remote repo created | **fail** | git remote get-url origin found no remote named origin | `remote_repo_created` |
| branch protection configured | **unknown** | host API not consulted — this is a read-only scan and it makes no authenticated calls to your git host | `branch_protection_configured` |
| ci pipeline configured | **pass** | .github/workflows/ci.yml | `ci_pipeline_configured` |
| project scaffolded | **fail** | no dependency lockfile found in the project root | `project_scaffolded` |
| pre commit hooks installed | **pass** | .git/hooks/pre-commit exists and is executable | `pre_commit_hooks_installed` |

**Overall: fail** — 2 of 5 checks came back negative. (2 of 5 passed; internal name `initialization_verified`.)

One check is deliberately left unanswered. Scout will not sign in to your git host or use your credentials, so it cannot see whether your main branch is protected. "Unknown" means exactly that — not "no".
```

### `secrets` — full history, and the value is never printed

Scout scans **every commit**, not just the current files. The finding schema is a
**field allowlist projection**: each finding is built from `RuleID`, `File`,
`Commit`, `Fingerprint`, `StartLine`, `Date` and `Description`, and the scanner's
own report is never passed through. There is no secret field in the schema to
forget to strip — and the **commit message**, which the scanner does *not*
redact and which has been demonstrated to carry a planted key, is refused
outright.

Observed with a real AWS-shaped key committed into a fixture:

```text
  ┌────────────────────────────────────────────────────────────────┐
  │  SECRETS FOUND IN YOUR PROJECT'S HISTORY: 1                    │
  │                                                                │
  │  Your history is visible to anyone who has ever cloned this    │
  │  project. Deleting the line does not help — the old commit     │
  │  still contains it.                                            │
  │                                                                │
  │  ROTATION, NOT DELETION, IS THE FIX. Change the credential     │
  │  where it lives (AWS, your database, the API provider) and     │
  │  the copy in this history stops being worth anything.          │
  └────────────────────────────────────────────────────────────────┘

The value itself is **not printed below and is not stored anywhere in this report** — only where to find it.

| What matched | Where | Line | Commit | When |
|---|---|---|---|---|
| `aws-access-token` | `src/creds.js` | 1 | `9a50b2ef6a` | 2026-08-10T20:27:32Z |

Each one needs an answer recorded against it: **rotated** (with the date), **false alarm** (with a reason — the rule name is not a reason), or **accepted risk** (with the name of the person accepting it).

Rewriting the history is possible (`git filter-repo` or BFG, a force-push, and every collaborator re-clones) but it **does not un-leak anything already fetched**, so rotation comes first. Scout does not run any of that.
```

Grepping both emitted reports for the planted literal returns **0 occurrences**
in the JSON and **0** in the Markdown.

**A missing scanner is reported as a missing scanner, never as a clean scan.**
With `gitleaks` off `PATH`, `status` is `tool-unavailable` and `findingCount` is
`null` — not `0`:

```text
**Nobody looked.** gitleaks is not installed, so NOTHING WAS SCANNED. This is not a clean result — it is the absence of a result. Install it (macOS: brew install gitleaks; other hosts: https://github.com/gitleaks/gitleaks/releases) and run Scout again before treating this project as free of committed credentials.
```

With it present and nothing found, `status` is `scanned` and the report says so
in as many words: *"Scout scanned every commit in this project, not just the
current files and found nothing. That is a real result, not a blank: the scanner
ran and reported no matches."*

### `collisions` — what the framework would otherwise trample

An inventory of every file the framework has an opinion about, and what would
happen to it. **Scout moves none of them.**

```text
Scout found **6** things here that the framework also has an opinion about. It moved none of them.

| What you have | What would happen to it | Why |
|---|---|---|
| `.claude/settings.json` | kept a copy, then replaced | The scaffolder OVERWRITES this file, then merges its own hook registrations into its own output — theirs is not consulted. |
| `.git/hooks/pre-commit` | kept a copy, then replaced | OVERWRITTEN today, unguarded. Husky, lefthook, pre-commit-framework and hand-rolled hooks are all destroyed. |
| | *(what it does today)* | Invokes npm. Advisory only: a hook can do anything, and this names only the tools Scout recognises. |
| `.git/hooks/*.sample` | kept a copy, then replaced | 14 sample hooks git wrote at init. The scaffolder DELETES them (rm -f) so it does not misdetect the tree as an existing project. |
| `.github/workflows/ci.yml` | not touched at all | Never archived, never touched. The framework installs its gates as its own files so a working pipeline is not taken offline on day one. |
| `.github/workflows/deploy.yml` | not touched at all | Never archived, never touched. …|
| `CHANGELOG.md` | yours stays | OVERWRITTEN from a template today. Under adoption it is treated as theirs: kept, and reconciled by the interview. |
```

**Your CI is the deliberate exception** — inspected and reported on, never
touched. Breaking your deploys on day one would be an unforgivable way to say
hello. Where a pipeline works against the safety rails, that is a *finding*, not
an edit:

```text
Some of your automated checks do things that would work against the safety rails. **Nothing was changed** — this is for you to decide:

| File | Line | Concern |
|---|---|---|
| `.github/workflows/deploy.yml` | 3 | A deploy triggered by a branch push rather than a tag or a dispatch reaches production without crossing the release gate. |
```

### `testsBaseline` — what the tests do today

```text
**Scout did not run anything.** --run-tests was not given, so Scout did not execute anything. …

- **Source files:** 3
- **Test files:** 2
- **Source files with no test that names them:** 2
```

#### The one thing that runs your code

`--run-tests` runs the project's own test command **once**, with its output
discarded — test output is free text, and free text is where a credential ends
up. Bounded by `SCOUT_TEST_TIMEOUT` (default 300 seconds). Observed:

```json
{
  "testCommand": { "value": "node test/run.js", "source": "package.json scripts.test" },
  "commandRan": true,
  "reason": "Run once, with its output discarded rather than captured — test output is free text and free text is where a credential ends up.",
  "exitCode": 0,
  "durationSeconds": 1,
  "timedOut": false,
  "totalSourceFiles": 3,
  "testFiles": 2,
  "untestedSourceFiles": 2
}
```

**Scout's read-only guarantee covers Scout. It does not cover your test
command.** A test suite that writes fixtures, touches a database, or hits the
network will do all of that under `--run-tests`. That is exactly why the flag is
opt-in: a scanner that runs an unknown repository's test command by default is a
trap, not a convenience.

### `intakePrefill` — what the interview can skip

The setup interview asks about fifteen things. Scout classifies each one:

```text
| Topic | Scout already knows | Where it got that |
|---|---|---|
| Project Identity | `legacy-app` | package.json name |
| Repo Setup | `no` | reality.probes remote_repo_created (the URL itself is deliberately not recorded) |
| Business Context | — | this is a judgement call, so Scout leaves it to you |
| …
| Data & Integrations (incl. 5.5 Data Classification & ZDR) | **you must answer this one** | there is no way to work it out from your files, and the project cannot move forward without it |
| …
| Testing & Bug Tracking | `node test/run.js` | package.json scripts.test |
| Tooling Configuration | `(none detected)` | no package manager was in evidence |
| Agent Initialization Prompt | `(generated from the completed intake)` | run_section_13 writes it from the answers above; it asks no question of its own |
```

Three classes, and the boundary matters: **scan-derived** answers are prefilled
with their provenance and you confirm or change them; **judgement** answers get
no default and no guess, because the prefill pattern is right for facts the
framework recorded and wrong for judgements it has never made; **data
classification** is non-skippable in every scenario.

---

## The limits Scout states about itself

These are printed in Scout's own output, not just here.

1. **The untested-file count is a name-match heuristic, not coverage.** In
   Scout's own words: *"An implementation file counts as untested when no test
   file's NAME contains its basename stem and it carries no inline test
   attribute. This is a name-match heuristic, not coverage: it cannot see a test
   that exercises a file without naming it, and it will call a file tested on a
   coincidental name match. It is a starting figure for the interview, never a
   coverage number."* The framework has no coverage instrumentation in any
   language, and a number that looked like coverage would be worse than an
   honest heuristic.
2. **Branch protection is `unknown`, not `no`.** Scout makes no authenticated
   calls to your git host and will not use your credentials.
3. **The git-hook description is advisory.** It names only the tools Scout
   recognises; a hook can do anything.
4. **Commit-shape signals are heuristics and are labelled as such.** The
   `feat:`-vs-`fix:` ratio over recent commits is presented with LOW confidence.
5. **The read-only guarantee is Scout's, not your project's** — see
   `--run-tests` above.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | A scan completed. **Findings are not errors** — a report full of secrets still exits 0 |
| 2 | Bad usage, or a target Scout cannot read |

```text
$ bash scripts/scout.sh --nonsense
scout: unrecognised option '--nonsense'
…
rc=2
```

---

## What comes next

Scout answers "what is in there?" It does not change anything and it commits you
to nothing. When you want to actually bring the project under the framework, the
next tool is the adoption driver — and a Scout report can be handed straight to
it:

```bash
bash scripts/scout.sh --out ./scan
bash scripts/adopt-project.sh --scan-report ./scan/scout-report.json
```

**Read [adoption.md](adoption.md) before you run that.** Adoption is half built:
the driver, the chooser and the interview ship and work, and several of the
things the design promises do not exist yet. That page names each one.

---

## See also

- [adoption.md](adoption.md) — the adoption driver, and the honest list of what it does not do yet.
- [designs/2026-08-02-brownfield-adoption-v1.md](designs/2026-08-02-brownfield-adoption-v1.md) — the architecture design Scout is built from, including the report schema.
- [module-contract.md](module-contract.md) — the M1–M5 severable-module rules Scout is held to, including M5's zero-dependency arm.

# Project Post-Mortem — Solo Orchestrator Framework (April 2026 → gate-wave close, 2026-07-11)

**Author:** documentation-wave implementation agent (Opus 4.8, ultracode effort)
**Scope:** the whole project, April 2026 through the gate wave that closed 2026-07-11,
weighted toward the recently completed gate wave.
**Method note:** every number, PR, SHA, and date below was derived from this
repository — `git log`, `gh pr list`, `solo-orchestrator-backlog.md`, the tracked
reports under `Reports/`, and the three handoffs under `docs/handoffs/`. Where the
source is a memory file or a report not tracked in this worktree, that is flagged
inline and the figure is either verified another way or omitted. Failures are given
equal billing with successes; on this project omitting a failure is treated as
dishonesty.

---

## 1. Executive summary (plain English)

Solo Orchestrator is a set of scripts, checklists, and documents that let one
technically-literate person build a real application using an AI coding agent — not
"vibe coding," but a phase-gated, test-first, documentation-mandatory process with
security scanning and threat modeling built in (README.md:1-5). The framework runs on
Claude Code (README.md:13-17).

The project started as a working v4.1 framework on 2026-04-04 (commit `6b95cf9`,
"Initial Solo Orchestrator Framework v4.1"). Almost everything since has been about
one promise: **the gates the framework advertises should actually fire.** Karl stated
the thesis when he filed the last big batch of work on 2026-07-01: *"users shouldn't
have to ask the orchestrator to run evals — those should be automatic — and gate
checks should be real, not implied"*
(`Reports/2026-07-01-s3-arc-close-and-handoff.md:97`).

Where it is now, in one breath: **169 pull requests merged** (`#1`–`#171`, gaps only
at `#5` and `#10`), **692 commits** (177 merge commits), **87 backlog items**
dispositioned (74 done, 5 Won't Fix, 4 deferred, 1 parked, 3 open), a **113-file test
suite** with a **72-file fast lane** gating every push, **11 lint scripts** (8 of them
required status checks), **branch protection with admin enforcement**, and — the
headline of the final wave — **all five Phase-3 security scanners now run for real**
(`bash scripts/run-phase3-validation.sh --list` reports `semgrep-full-tree`,
`license`, `snyk`, `zap-dast`, `threat-model`, each `[real]`). Nothing is
stubbed-by-decision anymore.

The honest counterweight: much of that work existed only to undo earlier dishonesty in
the framework's own gates. Docs claimed Phase 3 auto-ran five scanners; a grep found
zero invocations (BL-070). The gate claimed to write pass-dates; it only read them
(BL-071). "TDD-enforced" was a warning, not a block (BL-072). Two-thirds of the test
files were orphaned — registered nowhere, running never (BL-034/BL-035). And on
2026-07-08 the project shipped its own worst failure: two PRs merged onto `main` with
red checks and sat broken until a fix landed the next day. Every one of those is
closed now, and most closed with a machine that makes the same lie impossible to tell
twice.

**Plain-English TL;DR:** This project builds a disciplined, AI-assisted way to make
software. Most of the last three months was spent making the framework's safety checks
*actually run* instead of just *claiming to run*. It worked: all five security scans
are now real, almost every promised gate now bites, and the project even survived
breaking its own main branch once and turned that mistake into a permanent guardrail.

---

## 2. Timeline by arc

### Early April — build, audit, remediate (PRs #1–#9, 2026-04-06 → 2026-04-09)

The framework landed as a going concern (`6b95cf9`, 2026-04-04) and was immediately
put under audit rather than shipped on faith. The tracked evidence is a full
phase-audit tree under `Reports/phase-audits/`: seven first-pass audits (phases 0–4,
cross-cutting, and a consolidated summary dated 2026-04-08), then two further re-audit
rounds (`re-audit-2026-04-08/`, `re-audit-round3-2026-04-08/`) and a matching
`remediation/` tree. The consolidated summary's own verdict was measured, not
triumphant: "ready for personal/Light Track use today. For organizational/Standard+
deployments, the Critical and Major remediations should be implemented first"
(`Reports/phase-audits/2026-04-08-consolidated-summary.md:308`). The remediation
shipped as **PR #8** (`fix/audit-remediation`, merged 2026-04-09, `f07216f`),
bracketed by PR #6 (documentation remediation) and PR #9 (UAT documentation gaps).

(The auto-memory records this arc as "121 findings remediated, dual-env UAT of 48+48
agents, 17 bugs fixed." Those specific counts live in a memory file, not in the repo,
so this report does not assert them as repo-verified; what the repo *does* show is the
audit tree above and PR #8.)

### Late April — enforcement primitives + non-interactive modes (PRs #11–#38, 2026-04-22 → 2026-04-27)

This arc built the machinery the later gate work would reuse. The Build-Loop commit
gate shipped (BL-006, PR #15, `Resolved 2026-04-24`); the MVP-Cutline full-Build-Loop
rule (BL-007, PR #14); rollback/abort and UAT-quality guardrails (BL-008/BL-009, PRs
#12/#13). The **pending-approval sentinel reader** (BL-015, PR #16, 2026-04-25) became
load-bearing months later. Non-interactive modes for the three entry-point scripts
landed here: `init.sh --non-interactive` (BL-016, PR #19), `upgrade-project.sh`
(BL-018, PR #33, `e30759f`), plus the first two large UAT waves whose matrices are
tracked at `Reports/uat-2026-04-25/matrix.json` and
`Reports/uat-2026-04-26/matrix.json` — **84 scenarios each** (verified by parsing the
JSON). PRs #17/#18 were the fixes those UAT waves surfaced.

Commit volume tells the shape of the project: **313 commits in April, only 15 in May,
then 231 in June** (`git log --format=%ci | cut -c1-7 | sort | uniq -c`). May was
near-dormant; the project is really an April build and a June–July hardening campaign.

### June — the integrity reckoning (PRs #107–#136, 2026-06-26 → 2026-07-01)

June is when the framework audited *itself* honestly and did not like what it found.
Three tracked audits (the reports themselves were tracked into git by PR #171 on
2026-07-11) seeded three sub-arcs:

- **Test-integrity audit (2026-06-28)** → the vacuous-assertion defect class. Tests
  that would pass even if the behavior they guarded were deleted. BL-036 (critical, PR
  #110) and BL-037 (major, PR #115) fixed them and *spawned the double-mutation
  discipline* the rest of the project runs on.
- **Step-4 dead-code / ROI sweep (2026-06-28)** → BL-044 through BL-054, a mix of real
  bugs (BL-044: TEST 4 silently failing 8 assertions on stale paths) and honest
  de-scopes (several "Step-4 misattribution" notes where the report named the wrong
  file, e.g. BL-047, BL-051, BL-054).
- **Adversarial certainty re-walk (2026-06-29)** → BL-055 (per-line blame walker for
  self-approval evasion, PR #116/#119), BL-059/060/061 (validate.sh/gate argv/manifest
  staleness), and BL-062/063/064.

Running underneath all three was the **orphan-test reckoning**. The test-integrity
audit found the majority of test files registered in no aggregator — running zero
times. BL-034 wired the Wave-1-4 cohort (PR #111). BL-035 was the big one: **50
orphaned suites** triaged file-by-file (`Reports/2026-07-06-bl035-orphan-triage.md`)
into **44 REGISTER / 2 MERGE / 1 DELETE / 3 UNCERTAIN**, drained to empty, and — the
durable part — the capstone PR #154 turned `scripts/lint-tests-registered.sh` into a
hard-fail invariant so an orphan can never silently reappear. "Every test is
registered" became un-reopenable.

The June arc closed 2026-07-01 (`Reports/2026-07-01-s3-arc-close-and-handoff.md`) with
roughly 24 backlog items closed across S1–S4 waves — and with Karl filing the four
"Majors": BL-070 (Phase-3 scans not actually invoked), BL-071 (gate-date never
written), BL-072 (TDD warn-only), BL-073 (review-manifest warn-only). Those four are
the spine of everything after.

### Early July — the Majors + the CI arc + a red-main incident (PRs #140–#159, 2026-07-06 → 2026-07-09)

The Majors shipped their first real gates. BL-071 (gate-date auto-write on PASS, PR
#141) extracted `_cpg_gate_has_evidence` as the single evidence surface BL-070/073
would reuse. BL-073 (track-aware review-manifest gate → FAIL for `track=full`, PR
#146) shipped with a grandfather clause and an attestation escape. BL-070's driver
skeleton landed (PR #145) with `semgrep-full-tree` real and the other four
attest-on-skip stubs. BL-084 (tier-aware custom-host remote policy, PR #153) proved
that keying enforcement on the user-supplied `--track` is spoofable — a finding that
directly shaped the TDD gate later.

Then the **CI arc** (PR #156): before it, CI ran *only lint scripts and zero test
suites* (`Reports/2026-07-06-bl035-orphan-triage.md:43` flagged exactly this). BL-076
added a hermeticity guard (`scripts/lint-no-live-remote-in-tests.sh`) so no test can
reach real remote creation; BL-077 built a fast lane (66 unit files then, 72 now) that
gates every push in ~4 minutes, leaving the ~3-hour full suite as manual
`workflow_dispatch` (its speed optimization deferred as BL-085). PR #155 first retired
five known-RED tests so the suite could go green honestly.

And then the failure. On **2026-07-08, PRs #157 and #158 were merged onto `main` with
failing checks** — the backlog reconcile that flipped statuses without the citations
`scripts/lint-backlog-references.sh` requires (BL-079's closure was uncited; BL-073's
flip was missed entirely). `main` sat red until **PR #159** (2026-07-09, "restore
green CI — cite BL-079 closure + flip BL-073 to Closed") fixed it. The response was
not just the fix — it was **branch protection with `enforce_admins=true`** and the
citation lint made a required status check, so a red merge is now impossible and an
uncited `Closed` fails CI. The project's worst self-inflicted wound became its
strongest guardrail.

### The gate wave — 2026-07-09 → 2026-07-11 (PRs #160–#171)

Documented across two handoffs
(`docs/handoffs/2026-07-09-gate-wave-execution-handoff.md`, the plan;
`docs/handoffs/2026-07-10-gate-wave-close-out.md`, the retrospective), the wave turned
the last implied gates into real ones. Eight work-package PRs, each shipped via the
impl + adversarial-verify pattern and merged only on green required checks — no
`--admin`, no red merge:

| PR | Item | What shipped |
|----|------|--------------|
| #160 | BL-082 | Bind the Phase-3 summary to the tree it validated; the gate re-runs or FAILs on a stale/dirty/pre-BL-082 summary (marker `# BL-082-STALENESS`). |
| #161 | BL-063 | Tighten two Phase-3→4 POC-block contracts from "message present" to "the block fires ALONE" (count-based / short-circuit). |
| #162 | BL-081 | Full upgrade path runs the BL-015 sentinel guard BEFORE the idempotent backfill, so a blocked upgrade leaves `.claude/` byte-identical. |
| #163 | BL-072 C1 | TDD-ordering detector in **WARN mode** + dogfood replay (the measurement gate). |
| #164 | BL-070 | `license` scanner → real (per-language dispatch off `.context.language`). |
| #165 | BL-070 | `threat-model` scanner → real (validates PROJECT_BIBLE.md §4 `TM-NNN` rows; runs offline). |
| #166 | BL-072 C2 | Tier-keyed TDD **hard block** + attested escape (marker `# BL-084-TIER-KEY`). |
| #167 | BL-070 | `snyk` + `zap-dast` → real; **closes BL-070 — all five scanners real**; files BL-086. |

Then close-out PR #168 (a `tests/`-only bundle covering four verifier-minor coverage
gaps with mutation proofs), PR #169 (BL-010, wiring the BL-006 commit-message check
into the commit-msg hook), PR #170 (files BL-087), and the documentation-wave PR #171
(tracked the five June audit reports into git). The wave's own state check: `main`
green, branch protection unchanged, no open PRs, no pending-approval sentinel
(`docs/handoffs/2026-07-10-gate-wave-close-out.md:14-30`).

---

## 3. The honest-gates ledger — what the framework enforces vs. merely documents

The whole project can be read as moving rows from the right column to the left. As of
the gate-wave close, the framework **enforces** (not just documents):

- **Five real Phase-3 security scanners** — `semgrep-full-tree`, `license`, `snyk`,
  `zap-dast`, `threat-model`, all reporting `[real]` from the registry. Nothing
  stubbed-by-decision (BL-070, PR #167). The offline/gate-autorun path stays hermetic:
  scanners that need network or Docker (snyk, zap) SKIP loudly and attestably under
  `--offline` rather than silently passing.
- **Tier-keyed TDD hard block** — a `feat/fix/refactor` commit that ships
  implementation with no test hard-blocks for Sponsored-POC/Production, WARN-and-logs
  for Personal/Private-POC, keyed on `deployment`+`poc_mode` (never the spoofable
  `track`), with a recorded `SOLO_TDD_ATTESTED=1` escape (BL-072 C2, PR #166). It runs
  at **commit-msg** time, not pre-commit, because pre-commit cannot see the
  prospective commit subject.
- **Summary-to-tree staleness binding** — a Phase-3 validation summary is trusted only
  if its recorded `tree:` hash matches the current tree and it is not dirty; otherwise
  re-run or FAIL (BL-082, PR #160).
- **Sentinel freeze on both upgrade paths** — a pending-approval sentinel now blocks
  the full upgrade before any mutation, leaving `.claude/` byte-identical
  (BL-080/BL-081, PRs #144/#162).
- **Track-aware review-manifest gate** — FAIL for `track=full` when a required
  reviewer is missing (BL-073, PR #146) + `scripts/lint-review-manifest.sh` in CI.
- **Gate-date auto-write on PASS** — the gate writes evidence-first, idempotently,
  instead of only reading (BL-071, PR #141).
- **Structural lints as required CI checks** — registration (`lint-tests-registered`),
  hermeticity (`lint-no-live-remote-in-tests`), citation (`lint-backlog-references`),
  doc-anchors, review-manifest, plus counter-antipattern, fix-functions-stderr, and
  raw-read-prompt: **8 lint jobs required by branch protection**, out of 11 lint
  scripts in the tree.
- **Branch protection** — required status checks (`unit` + the 8 lints), no
  force-pushes, `enforce_admins=true`.

What the framework still **documents more than it mechanically enforces**: the
methodology's human-judgment steps (intake accuracy, threat-model authorship, reviewer
identity beyond the manifest schema) remain guided by docs and attestation, not code
gates — by design, because they are not decidable by a script.

---

## 4. Process evolution — how the verification discipline emerged

The project did not start rigorous; it *became* rigorous, and the increments are
traceable.

1. **UAT walker waves (April).** Verification began as breadth: 84-scenario matrices
   run by fleets of walker agents (`Reports/uat-2026-04-25/`, `uat-2026-04-26/`). Good
   at finding "the framework refuses to do X," weak at proving "this test actually
   tests X."
2. **Verifier rubric calibration (June).** The impl + adversarial-verify pipeline
   formalized: an implementer in a worktree plus an independent reviewer *prompted to
   refute*, graded `block / major_concerns / minor_concerns / approve`, with
   `major_concerns` or worse blocking the merge
   (`Reports/2026-07-01-s3-arc-close-and-handoff.md:78`).
3. **The vacuous-assertion defect class → double-mutation proofs.** BL-036 exposed
   tests that pass even when the guarded behavior is removed. The fix was a rule: the
   implementer supplies one mutation proof; the verifier runs a *different* mutation.
   If the verifier's mutation passes when it shouldn't, that is a scope-miss
   regardless of the implementer's proof
   (`Reports/2026-07-01-s3-arc-close-and-handoff.md:79`, `:83`). Load-bearing lines
   carry `# BL-NNN-…` markers as mutation targets.
4. **Measurement gates before enforcement.** The single most mature move. BL-072 was
   *forbidden* from shipping a hard block until its false-block rate was measured on
   the repo's own history. C1 shipped WARN-only + a dogfood replay
   (`Reports/2026-07-10-bl072-warn-dogfood.md`): **38.6% would-block rate (110/285
   feat/fix/refactor commits)** as an explicit upper bound, and a hand-reviewed **50%
   false-positive floor** on the 20 most-recent would-blocks. Only after Karl reviewed
   those numbers did C2 ship — and it shipped *hardened*: the classifier tightened
   (all `*.md`, pure deletions, lockfiles excluded, moving the classifier-only rate
   38.1%→36.4% per `Reports/2026-07-10-bl072-c2-replay.md`), tier-keyed, and
   attestation-escaped, precisely because the measurement said a naive block would nag
   ~2 in 5 legitimate commits.
5. **Ship-then-flip + citation hygiene.** Backlog status flips go in a *second*
   commit, separate from the fix, and every `Closed` must cite a PR or SHA — now
   lint-enforced after the 2026-07-08 red-main incident proved the cost of skipping
   it.

The through-line: verification moved from *"did we run it?"* (walkers) to *"does the
test fail when the code is wrong?"* (mutation) to *"is enforcing this even a good
idea, measured?"* (dogfood gates). That last step is what distinguishes this project
from a checklist.

---

## 5. Incidents & responses

Four incidents in the record, each with what changed as a result. Two are code
failures with git artifacts; two are operational failures from the gate wave whose
primary record is the wave's own handoffs and process notes rather than a single SHA.

**5a. The red-main incident (2026-07-08).** PRs #157 and #158 were merged with failing
checks — the backlog reconcile flipped statuses (closing BL-079, missing BL-073's
flip) without the PR/SHA citations `scripts/lint-backlog-references.sh` requires, and
`main` went red. **Response:** PR #159 restored green the next day; branch protection
was turned on with `enforce_admins=true` and no force-pushes, and the citation lint
became a required status check. This is the reason the operating agreement's very
first rule is "No merge on red. Ever."
(`docs/handoffs/2026-07-09-gate-wave-execution-handoff.md:44-48`). A process failure
was converted into a mechanical impossibility.

**5b. The model-dispatch mistake (gate wave).** During the wave, dispatched subagents
silently inherited a *different* session model than intended. **Response:** they were
killed and relaunched on Opus before any of them pushed, so no work product was
contaminated — the catch happened at the right boundary (before push), which is the
same "fail before the irreversible step" principle the sentinel-freeze and
staleness-binding gates encode in code.

**5c. The usage-limit mass kill (gate wave).** A usage-limit event killed the running
agent fleet mid-wave. **Response:** two agents survived the kill *because they had
already shipped complete PRs* — the work was durable at the PR boundary, not stranded
in a worktree. The lesson reinforced the wave's insistence that each work package be a
self-contained, independently-mergeable PR rather than a long-lived shared branch.

**5d. The false-alarm backlog tidy (gate-wave close-out).** The close-out spec asked
for three "cosmetic" backlog cleanups. A verify-against-history safeguard caught that
**all three had false premises** and would have *damaged* the backlog: BL-055's second
`Status: Open` is the deliberately-preserved original 2026-06-29 entry (commit
`98315661`, under an audit-trail header added by `f6a8e6c`); the "duplicate" Status
lines under BL-003b and BL-043 actually belong to the *separate* entries
`code-upgrade-project-8`, `code-check-gates-1`, and `code-check-gates-7-followup`.
**Response:** nothing was touched, the false premises were reported instead, and
`scripts/lint-backlog-references.sh` passes unchanged
(`docs/handoffs/2026-07-10-gate-wave-close-out.md:158-172`). The safeguard — "verify
each tidy against git history before deleting" — is why a well-intentioned cleanup did
not become a regression.

The common thread across all four: the failure was caught at a boundary (before push,
before merge, before deletion) rather than after damage. Three of the four hardened
either a gate or a process rule as a result.

---

## 6. By the numbers

Every figure here is repo-derived; the derivation command is named so it can be
re-run.

| Metric | Value | How verified |
|---|---|---|
| Merged pull requests | **169** (`#1`–`#171`, gaps at `#5`, `#10`) | `gh pr list --state merged` → 169; ranges reconciled |
| Merge commits reachable from HEAD | 177 (161 "Merge pull request #N") | `git log --merges \| wc -l`; `grep -c 'Merge pull request #'` |
| Total commits | 692 | `git log --oneline \| wc -l` |
| Commit span | 2026-04-04 → 2026-07-10 (wave closed 07-11 via #171) | `git log --format=%ci` first/last |
| Commits by month | Apr 313 · May 15 · Jun 231 · Jul 133 | `git log --format=%ci \| cut -c1-7 \| sort \| uniq -c` |
| Backlog entries (distinct) | **87** (82 numbered `BL-001..087`, gaps at 26/27/28/56/83; + 5 non-`BL-` entries) | parsed `## ` headers in `solo-orchestrator-backlog.md` |
| — Closed | 65 | first Status line per entry |
| — Resolved (older "done" wording) | 9 | " |
| — Won't Fix | 5 (BL-011/012/013/014/058) | " |
| — Deferred (Open, revisit) | 4 (BL-019/042/043/085) | " |
| — Open (actionable) | 3 (BL-025 opportunistic, BL-086, BL-087) | " |
| — Parked | 1 (BL-017) | " |
| Test files | 113 (`tests/*.sh`); 127 incl. subdirs | `ls tests/*.sh \| wc -l`; `find tests -name '*.sh'` |
| CI fast-lane unit files | 72 (full ~3h suite manual-only) | `grep -cE 'tests/test.*\.sh' .github/workflows/tests.yml` |
| Lint scripts | 11 (8 required as branch-protection checks) | `ls scripts/lint-*.sh`; close-out §1 |
| Phase-3 scanners | 5, all `[real]` | `bash scripts/run-phase3-validation.sh --list` |
| Shell scripts | 38 `scripts/*.sh` + 11 `scripts/lib/` + 2 hooks + `init.sh` | `ls` counts |

Scanner registry, verbatim from `bash scripts/run-phase3-validation.sh --list`:

```
Phase 3 scanner registry
  semgrep-full-tree    [real] Full-tree Semgrep SAST
  license              [real] License compliance
  snyk                 [real] Snyk dependency scan
  zap-dast             [real] OWASP ZAP DAST
  threat-model         [real] Threat-model verification
```

Two numbers to read honestly: the backlog's "Closed" vs "Resolved" split is pure
wording drift (both mean done — 74 total done), and the merged-PR count is 169 rather
than 171 because `#5` and `#10` were opened but not merged. Neither is a discrepancy;
both are stated so no reader has to wonder.

---

## 7. Lessons learned

Each is one sentence with its evidence.

1. **Advertised gates rot silently unless something re-checks them.**
   BL-070/071/072/073 were all "documented as automatic, verified as inert" until a
   2026-07-01 grep exposed the gap
   (`Reports/2026-07-01-s3-arc-close-and-handoff.md:99-102`).
2. **Measure before you enforce.** BL-072 was forbidden a hard block until the
   38.6%/50% dogfood numbers were in hand, which is exactly why C2 shipped tier-keyed
   and attested instead of naive (`Reports/2026-07-10-bl072-warn-dogfood.md:101-121`).
3. **A test that can't fail is worse than no test, because it lies.** The
   vacuous-assertion class (BL-036/037) spawned the double-mutation rule that now
   guards every enforcement change
   (`Reports/2026-07-01-s3-arc-close-and-handoff.md:83`).
4. **Register-or-it-didn't-run.** Two-thirds of tests were orphaned; the fix was not
   just wiring them but sealing `lint-tests-registered.sh` as a hard-fail invariant so
   orphans can't recur (BL-035 capstone, PR #154).
5. **Key enforcement on values the user can't spoof.** BL-084 proved `--track light`
   on a sponsored project defeats a track-keyed gate, so BL-072 C2 keys on
   `deployment`+`poc_mode` instead (`solo-orchestrator-backlog.md` BL-072 entry).
6. **Attest, don't silence.** Every escape hatch — reviewers, sentinel, TDD — records
   to state (`process-state.json::tdd_attestations[]`, etc.) rather than quietly
   passing, preserving the audit trail across the exception.
7. **The implementation surface can defeat the gate's own premise.** The TDD gate had
   to move from pre-commit to commit-msg because git doesn't write the subject until
   after pre-commit runs (`docs/handoffs/2026-07-10-gate-wave-close-out.md:66-73`) —
   the tool's mechanics, not the design, dictated placement.
8. **Predicates must be scoped to intent.** BL-082's first cut read the tree as dirty
   the instant the gate wrote its own state file, which would have bricked the gate;
   the fix scoped the dirty check to exclude `.claude/` and results
   (`docs/handoffs/2026-07-10-gate-wave-close-out.md:52-64`).
9. **Your worst incident is your best guardrail if you mechanize the fix.** The
   red-main merge produced `enforce_admins` protection + a required citation lint,
   converting a discipline failure into a structural one
   (`docs/handoffs/2026-07-09-gate-wave-execution-handoff.md:44-48`).
10. **Verify cleanup against history before you cut.** The three "obvious" backlog
    tidies were all false alarms that would have deleted real entries; the
    verify-against-history safeguard saved them
    (`docs/handoffs/2026-07-10-gate-wave-close-out.md:158-172`).
11. **Durable at the PR boundary survives the kill.** When a usage-limit event killed
    the fleet mid-wave, the agents whose work was already a complete PR survived;
    long-lived shared branches would not have.
12. **Ship-then-flip keeps the record honest.** Separating the fix commit from the
    status-flip commit — and citing every closure — is what makes a 87-entry backlog
    auditable three months on (operating agreement rule 7).

---

## 8. What remains

Nothing on this list is a blocker; all of it is explicitly dispositioned.

- **Deferred (revisit next quarter / on demand):** BL-019 (`verify-install.sh`
  non-interactive audit), BL-042 (`init.sh prompt_install` × pipefail on closed stdin
  — test-only workaround already in tree), BL-043 (`intake-wizard.sh` `main()`
  extraction refactor — the PR #104 main-guard already closes the real risk), BL-085
  (make the ~3h full suite CI-fast — manual dispatch works today).
- **Parked:** BL-017 (`intake-wizard.sh` non-interactive mode) — no operator demand in
  60+ days across four waves of intake work; field-specific flags cover the known
  needs.
- **Open, opportunistic:** BL-025 (Phase-2-verified test helper) — build it the first
  time a test actually needs Phase-2-init state, not speculatively (its original
  "build first" scheduling premise is obsolete since BL-073 shipped with plain heredoc
  fixtures).
- **Open, awaiting a Karl decision:** BL-086 — a license allow/deny policy layer (e.g.
  flag GPL/AGPL for organizational deployments) on top of the now-real license
  scanner; filed file-don't-build per the gate-#4 decision batch.
- **Open, latent note:** BL-087 — the BL-006 commit-msg delegate would hard-block
  inside the *framework's own repo* if that hook were ever installed there, plus a
  `--amend` surface asymmetry; recorded as a latent trap, not an active bug.
- **Won't Fix (with reopen triggers):** BL-011 (Cutline-ID-aware enforcement — would
  re-impose an ID convention BL-007 deliberately dropped), BL-012/013 (retroactive
  history scanning / cross-host CI parity — cost ≫ benefit), BL-014 (commit-type
  hygiene — the BL-072 measurement shows diff-intent inference would misfire worse,
  and the attestation ledger already provides the audit trail), BL-058 (doc aligned to
  product, no code change). Each entry names the concrete case that would reopen it.

There is also a standing **manual cleanup owed to Karl** that agents cannot do
(destructive git ops are blocked in the tool): deleting ~11 merged wave branches, ~28
stale `worktree-wf_*` branches, and old worktree directories, enumerated in
`docs/handoffs/2026-07-10-gate-wave-close-out.md:197-233`.

---

## 9. Closing assessment

Solo Orchestrator set out to be a phase-gated, test-first, documentation-mandatory way
for one person to build real software with an AI agent. Three months in, the honest
verdict is that the *methodology* was sound from April but the *enforcement* was
aspirational — and the bulk of the work since has been closing the gap between what
the framework said and what it did. That gap is now, by the evidence, essentially
closed: five real scanners, a measured-then-hardened TDD block, a staleness-bound
Phase-3 gate, sentinel freezes on both upgrade paths, a review-manifest gate that
FAILs, eight required structural lints, and branch protection that made the project's
own worst merge impossible to repeat.

What should give the next reader confidence is not the count of closed items but the
*shape* of how they closed: measurement before enforcement, mutation proofs on
load-bearing lines, attestation instead of silent bypass, and a culture that logged
its four incidents — including a broken main branch and a fleet-wide kill — with the
same candor as its wins. The framework now largely practices on itself the discipline
it asks of its users. The remaining open items are small, named, and mostly waiting on
a human decision rather than on undiscovered work.

The one caution worth stating plainly: enforcement this dense has a maintenance cost,
and several gates (the TDD classifier especially) are heuristic and will need the WARN
ledgers and attestation trails they emit to stay honest as the repo evolves. The
machinery to keep them honest exists. Whether it keeps getting fed is the next
quarter's question, not this post-mortem's.

**Plain-English TL;DR:** The framework's ideas were right from the start, but its
safety checks used to be for show. Almost all the work since April was making them
real — and it succeeded. The security scans, the test-first rule, and the release
gates now actually run and actually block, the project owned up to the times it broke
itself, and turned those mistakes into permanent guardrails. What's left is a short,
clearly-labeled list, most of it just waiting on a yes/no from Karl.

---

*This post-mortem changed no other file. All figures are reproducible from the commands cited above against the repository as of the gate-wave close.*

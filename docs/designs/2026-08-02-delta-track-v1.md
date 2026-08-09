# The Post-MVP Delta Track — architecture design v1

## Document Control

| Field | Value |
|---|---|
| **Document ID** | DELTA-001-ARCH |
| **Version** | v1.2, 2026-08-09 — **build-evidence amendment folded** (Karl's approval, 2026-08-09). Two corrections the implementers *proved by execution*, mapped in §0.2: §3.1's severability revert is **six** consumers and not one (enumerated by running the test, across three review rounds), and §3.3's CORE set gains `scripts/host-drivers/*.sh` (a planted `core → delta` source line passed the lint at rc=0) — plus **A-DT-3**, the front-matter correction they forced: the "Status of the thing described" row below no longer says "Nothing is built". No settled decision, decision table, adopted mechanism, or WP boundary changed. · v1.1, 2026-08-02 — **review-r1 folded** (`major_concerns`; fidelity verdict **FAITHFUL** — all eight settled decisions intact, all twelve v1.0 §14 rows independently reproduced). One mandatory finding and six one-liners, all mapped in §0.2. No decision table, adopted mechanism, or WP boundary changed; WP6 gains one deliverable. The mandatory finding was a **docblock-trusted claim that was never executed** — the one such claim in a document that logs fourteen runs. |
| **Classification** | Product architecture — normative-once-reviewed for the build |
| **Audience** | (a) the adversarial design reviewer this document must survive; (b) the session that plans and builds the work packages in §11 |
| **Product** | **The Delta Track** — the maintenance and feature lifecycle a Solo Orchestrator project runs *after* it cuts v1.0.0 |
| **Companion documents** | `docs/builders-guide.md` (Phases 0–4, the Build Loop, Step 4.4 maintenance cadences) · `docs/governance-framework.md` (§ VII Post-Release Vulnerability Response, § X Graduation) · `docs/designs/2026-07-24-operating-model-v1.md` (the house exemplar for this document's shape) · `docs/designs/2026-08-02-team-orchestrator-v1.md` (a sibling design that forks this asset base) |
| **Status of the thing described** | **Partly built as of 2026-08-09 — WP0–WP7 have shipped; WP8 and WP9 have not.** *(v1.2 correction: this row read "Nothing is built … verified 2026-08-02 (§14-V11)" through v1.1. That verification was accurate at its commit and the row is now false; both v1.2 amendments in §0.2 are derived from the shipped code.)* **Built in this tree:** the inherited-predicate pins (WP0, PR #323); `scripts/lint-delta-boundary.sh` (WP1, PR #324); `scripts/lib/delta-state.sh`, `delta-policy.sh` and the `process-checklist.sh` `DELTA-SEAM` fence (WP2, PR #327); the era invariant and `delta-classify.sh` (WP3, PR #328); the per-class gates and close-rubric bind (WP4, PR #330); the hotfix lane and retro ledger (WP5, PR #332); `delta-cadence.sh` with the `check-maintenance.sh` rewire, the `DELTA-` row in `identifiers.tmpl` and the builders-guide Step 4.4 reconciliation (WP6, PR #333); and `scripts/cut-release.sh` plus the severability test (WP7, PR #334). **Not built:** the three intake paths and `delta-brief.tmpl`, the `resume.sh` fourth branch and the session greeting (WP8 — `resume.sh` still contains **zero** delta references), and the user-guide / generated-`CLAUDE.md` docs (WP9). `docs/deltas/` and `.claude/delta-state.json` still do not exist here, and never will: they are **generated-project** artifacts, not framework-repo ones. The v1.0 row cited their absence as evidence that nothing was built — a reading that was true then and is misleading now. **Every "exists today" claim below is stamped 2026-08-02** and is about the *existing* framework the delta track consumes rather than replaces; §14 is a log of what those commands returned at that commit, not a standing property. |

**Provenance.** Every architecture decision in §0.1 was made **by Karl in a joint working
session on 2026-08-02**. This document **transcribes** those decisions into the house design
format. It does not relitigate them. Where a decision leaves implementation freedom, this
document designs inside it and marks that work **author-proposed**. Where the repository
contradicts or materially corrects the framing a decision was stated in, the correction is
flagged in §0.3 and in place — never silently designed around.

**Structural model.** `docs/designs/2026-07-24-operating-model-v1.md` is the house exemplar and
this document copies its discipline: a §0 traceability block, decision tables with one
recommendation and stated rejected alternatives, an honest mechanical/auditable/advisory tiering
of every enforcement claim, and — above all — **every "exists today" claim carries a verification
anchor**. Per the house citation rule, anchors are **grep-able marker comments** (`# BL-NNN-…`)
or **function names**, never bare `file:line`.

**Verification posture.** The blocking failure class in this document's sibling review was
*hazards reasoned about but never executed*. So every verifiable claim printed here was
**executed** before it was printed, and §14 is the log: the command, and what it actually
returned. Five claims changed as a result (§0.3-C3, C5, C7, C9, C10). **v1.1:** review-r1 found
the one place the rule slipped — a claim copied from a script's own docblock rather than run
(R-DT-1) — and executing it refuted both the docblock *and* the reviewer's proposed replacement.
§14 now logs fourteen runs.

---

## Plain-English overview — read this first (about two minutes)

Solo Orchestrator walks one person, working with AI assistants, from an idea to a shipped
version 1.0 of a real application. It does that in five numbered phases, and it enforces them:
automatic checks refuse a commit that skipped a required step, refuse a phase advance that lacks
its evidence, and record every time somebody works around a block.

Then version 1.0 ships — and the map ends. The application is live and will now live for years.
Users will ask for things. Bugs will come in from real usage. A security advisory will land on a
dependency at three in the morning. Today the framework has *some* good machinery pointed at
that world — a bug ledger, a changelog, a maintenance-cadence checker, security scanners — but
nothing that ties it together into a repeatable loop. In practice the operator has to remember
what to do, and remembering is exactly what the first five phases were built not to rely on.

**The delta track is that missing sixth thing.** A "delta" is one unit of post-1.0 change. You
say what you want in plain words — "add dark mode", or "the CSV export crashes on unicode" — and
the system asks you **one** question: which of four kinds of change is this?

- a **feature** (something new),
- a **fix** (something broken),
- a **hotfix** (something broken *right now*, in production, that cannot wait), or
- a **security patch** (something an attacker could use).

It usually proposes the answer from your own wording and asks you to confirm it rather than
quizzing you. From that single answer it works out the rest by looking at the code: which files
you are touching (so it knows whether you are near the security-sensitive parts), how big the
change is, and how severe the bug is. It shows you what it worked out and asks you to confirm
that too. Then it runs the right amount of ceremony — a lot for a feature, less for a fix, almost
none for a 3 a.m. hotfix — and, critically, it **remembers** the corners you cut on that hotfix
and refuses to cut the next release until you have gone back and reviewed it.

Three more things it does. It **watches the calendar**: every two weeks it expects a routine
review, and every quarter a deep security scan, and it refuses to cut a release if either is
overdue. It **watches what you touch**: change authentication or a data contract and it makes you
refresh the threat model before you can close. And it **cuts the release for you** — it works out
whether this was a patch, a minor, or a major version from what actually shipped, promotes the
changelog, and tags it.

Two deliberate limits, both chosen rather than discovered. **One delta at a time** — the framework
is for a single operator and a queue of one is honest about that. And **the delta track cannot
start before the project has finished Phase 4** — you cannot use the maintenance loop to avoid
building the thing properly the first time.

What does not change is the important part. The commit gates, the security scanners, the
test-before-code rule, and the phase record all carry over untouched. The delta track is a
*lifecycle* addition, not a safety rewrite — and it is built as a module you could lift out of
the framework in one piece, because the framework family may one day want it and may one day not.

---

## §0 — Decision traceability

### §0.1 — Settled decisions carried into this design

All eight were decided by **Karl, joint working session 2026-08-02**. This document designs
**within** them. Each row names where the design work for it lives, and what part of it was left
free for the author.

| # | Settled decision (Karl, joint session 2026-08-02) | Designed in | Author freedom taken |
|---|---|---|---|
| **D1** | **Placement — inside solo, as a SEVERABLE MODULE.** Own lib files on the `scripts/lib/delta-*.sh` pattern, own state file, **one narrow seam** into the commit gate. A **new dependency-direction lint** enforces "delta imports core, core never imports delta" **from the first commit**. **No plugin socket, on any schedule** — the family extensibility model is **fork-and-PR**. **Mechanism/policy split:** machinery ships with the framework; policy (class definitions, floors, cadence thresholds) lives in a **project-owned config file the sync never overwrites**. | §3 | The lint's exact predicate, allowlist cardinality rule, and vacuity floor (§3.3); the file inventory (§3.1) |
| **D2** | **Classification — four primary classes** (feature / fix / hotfix / security-patch), asked as **ONE question**, often **auto-proposed from the user's phrasing**. Each class carries machine-**derived**, human-**confirmed** attributes: **risk** (core vs feature-local, derived from touched files vs threat-model surfaces), **size/level** (small / significant / evolution, derived from diff footprint), and **severity** for fixes (the existing SEV-1..4 grammar plus the governance response-time table drives the clock). **Class picks the checklist; attributes toggle extra gates.** Confirm-not-quiz. | §4 | Derivation formulas and their thresholds (§4.2); the confirm-not-quiz transcript shape (§4.3) |
| **D3** | **Per-class demands.** Floor always on (already shipped: gitleaks, semgrep, project tests, TDD ordering). **FEATURE** = delta brief + **pre-build adversarial review of the brief** + full existing Build Loop + close review + changelog. **FIX** = bug-ledger entry + reproduction test RED-first + lighter close. **HOTFIX** = fast lane, floor only + audit row at open; **mandatory retro-review within 3 DAYS**; **an open retro BLOCKS the next release cut**. **SECURITY-PATCH** = fix ceremony + forced dependency scan + SBOM refresh + flagged release note. **Adversarial review on EVERY delta close**; the brief's acceptance criteria **ARE** the close review's rubric. | §5 | The gate-token vocabulary and the brief's one-page section list (§5.2, §6.2) |
| **D4** | **Intake.** The user just states the need; **one** classification question; then the **class template interviews them** (they never need to know what to collect). **Three creation paths mirroring birth intake** (guided script / conversational-AI default / manual template). Brief lives at `docs/deltas/DELTA-NNN-slug.md`; a ledger row (`FEATURES.md` / `BUGS.md`) links it; delta-state activates. | §6 | Path-selection defaults and the ID-allocation rule (§6.1, §6.3) |
| **D5** | **Re-fire triggers — all three.** **TOUCH**-based (auth / data-contract / threat-model surface ⇒ threat-model update + scoped scanner re-run before close). **VERSION**-based (major bump ⇒ full `run-phase3-validation.sh` re-run). **CALENDAR**-based: **14-day routine review** (changelog / SBOM / routine) + **quarterly deep security scans** (dependency audit folds in; tightened from the prose's biannual, "for now") — **enforced at release cut (refuse if overdue) + session-start nag**. This finally wires the orphaned `check-maintenance.sh`. | §8 | The touch-surface matcher shape and the scoped-scanner subset (§8.1); the nag's silence contract (§8.3) |
| **D6** | **Release — a new `scripts/cut-release.sh`.** Promotes `CHANGELOG.md` `## [Unreleased]` → version. **Semver decided by the tool — no override path in v1**: any feature ⇒ minor, fixes/patches ⇒ patch, breaking ⇒ major + full revalidation. **REFUSES** on open delta / open hotfix retro / overdue cadence. Then tags `v*`; the existing release lanes fire as-is. | §9 | The tag-format constraint forced by C7; the refusal ordering and messages (§9.2) |
| **D7** | **Era routing.** The delta track **cannot activate before Phase 4 completion** — validator invariant `active_delta ⇒ current_phase == 4`. `delta-state.json` **single-writer = `process-checklist.sh`**. **No phase re-entrancy**: `current_phase` stays 4 (monotonic). The `feat:`-requires-Build-Loop predicate is **UNTOUCHED and test-pinned FIRST**. Same user words in both eras; pre-1.0 statements route to the **existing** machinery. **BRIDGE:** at v1.0 the manifesto's Post-MVP Backlog seeds the delta queue. **ONE OPEN DELTA AT A TIME** in v1. A delta-aware branch is added to the session-start greeting and `resume.sh`. | §10 | Which of the two feat-predicate surfaces the WP0 pin targets (forced by C3); the bridge's seeding mechanics (§10.4) |
| **D8** | **Verified corrections to carry honestly.** No mechanical queue-interrupt exists for SEV-1 — the shipped Severity Guide's "must fix immediately", the deferral prohibition, and the gate block are the enforcement, and the document **must not claim a queue mechanism**. A fix rides the **NEXT** UAT session (the batch counter counts *features*). Today's bug/feature workflow instructions are **retrieval surfaces** (guide + ledger headers); the ambient session-greeting branch is what closes that gap. | §0.3, §5.4, §10.5 | — (transcribed; §0.3-C5 strengthens one half and narrows another) |

### §0.2 — Amendment changelog

**v1.2 (2026-08-09) — build-evidence amendment. Approved by Karl, 2026-08-09.** Two substantive
corrections, both **produced by running the thing this document specified** rather than by
preferring a different wording, plus a third row (A-DT-3) recording the front-matter correction they
forced. No settled decision, decision table, adopted mechanism, or WP boundary changes. Amendment
rows are prefixed `A-` to distinguish them from the review findings below, which are `R-`.

- **A-DT-1 (REVERT SET) → §3.1** — the severability test's revert was specified as "the seam block in
  `process-checklist.sh`", **singular**. Building and running the test enumerated **six** consumers,
  found across three review rounds: the `DELTA-SEAM` fence (WP2), `_postmvp_policy_notice` and its
  call site in `upgrade-project.sh` (WP2), `_postmvp_era_assertion` and its call site in
  `validate.sh` (WP3), the `# CADENCE-POLICY-READ` line in `check-maintenance.sh` (WP6), the
  `delta-boundary-lint` job in `.github/workflows/lint.yml` (WP1), and a **direct**
  `run_child_suite "scripts/lint-delta-boundary.sh"` registration in `tests/full-project-test-suite.sh`
  (WP1). That last one falsified this section's own central claim — §3.1 defines severability as
  "the full suite must pass", and the file that *is* the full suite invoked a module script directly,
  so post-sever it was `bash` on a deleted file at rc 127. §3.1 also records **what running it
  taught**: functional severability is already free (every consumer fails soft — measured), so the
  load-bearing instrument is the **reference sweep**, not the behavioural one, and the obvious WP7
  mutation cannot be a functional one; and **a multi-line construct must be dropped as a construct**,
  because a line-based drop left an orphaned continuation that `bash -n` accepts. §3.1's file
  inventory omits the module's own test files, which the test deletes anyway — with one real cost
  named on the record.
- **A-DT-2 (CORE GLOBS) → §3.3** — the CORE set was **four** globs, which excludes
  `scripts/host-drivers/*.sh`, and `scripts/lint-delta-boundary.sh` was built faithful to that
  number and says so in its own header. Proof by plant, not inference: review added
  `source "$SCRIPT_DIR/lib/delta-state.sh"` to `scripts/host-drivers/github.sh` and **the lint passed
  it at rc=0**, while the identical line in `scripts/validate.sh` reds at rc=1 on T1 — re-executed in
  both directions for this amendment. The predicate is sound; the population was short. Karl approved extending coverage, so the CORE set is now
  **five globs** here, in the brownfield design's §3.3, and in `docs/module-contract.md` M3 — the
  three surfaces are kept at parity by design. **The lint edit is a separate follow-up, tracked as
  `## BL-215:`:** as of 2026-08-09 both `CORE_GLOBS` arrays still list four entries, and §3.3 says
  so rather than reading as a description of shipped behaviour.
- **A-DT-3 (FRONT MATTER) → Document Control, "Status of the thing described"** — that row read
  **"Nothing is built."** through v1.1, verified at the time against §14-V11. True at that commit;
  false by 2026-08-09, because **WP0–WP7 have shipped** (PRs #323, #324, #327, #328, #330, #332,
  #333, #334) and both corrections above are derived from that shipped code. Corrected in this same
  v1.2 pass: the row now names what is built, what is not (WP8's intake paths and `resume.sh`
  branch, WP9's docs), and the PR for each. One clause is **retired rather than updated** — v1.0
  cited the absence of `docs/deltas/` and `.claude/delta-state.json` as evidence that nothing
  existed, but those are **generated-project** artifacts that will never exist in the framework
  repo, so their absence was never evidence of anything and would have read as a false negative
  indefinitely. The "exists today" caveat is kept and rescoped: those claims are stamped 2026-08-02,
  and §14 is a log of what commands returned at that commit, not a standing property.

**v1.1 (2026-08-02) — review-r1 amendment map.** Verdict `major_concerns`; fidelity **FAITHFUL**
(all eight settled decisions intact, all twelve §14 rows independently reproduced). One mandatory
finding and six one-liners, all folded, corrections rewritten on top rather than accreted. No
decision table, adopted mechanism, or WP boundary changed; WP6 gains one deliverable.

- **R-DT-1 (MANDATORY) → §8.3 note 1 / §9.2 / §11-WP6 / §14-V13** — v1.0 claimed
  `check-maintenance.sh` has a "0 / 1 / 2" exit contract. **Refuted: the script has exactly two
  `exit` sites and no `exit 2`** — v1.0 copied the docblock instead of executing it. Corrected,
  and the real behaviour re-derived by running it: an undeterminable date is guarded out by
  `[ "$last_epoch" -gt 0 ]` and the arm is **silently skipped**, so the script reports "All
  maintenance cadences current" at **rc=0**. **The reviewer's proposed mechanism — fall-through to
  a huge `days_since` and `exit 1`, a fail-*closed* collapse — is itself refuted by that guard and
  by the run (§14-V13); the true failure is fail-**OPEN**, the opposite direction and the worse one
  for D5.** Author's choice taken: WP6 **adds** the advertised `exit 2` as an explicit design
  addition (marked author-proposed), and `cut-release.sh` treats it as a refusal.
- **R-DT-2 (MINOR) → §0.3-C5 / §13-R7** — C5 promised the stale "before Phase 3" gate wording was
  "recorded as residual R7", but R7 was the 14-day-cadence question. The residual now exists as
  **§13-R7** and C5 points at it.
- **R-DT-3 (MINOR) → §1 row 1** — "five accepted keys" → **six**; the `get_steps_for_process`
  case-arm count, re-derived with `invariant_check`'s own awk, is 6 (§14-V14).
- **R-DT-4 (MINOR) → §0.2** — the base commit was not `fe1ba9e`; the branch's real parent is
  **`6449838`** (`fe1ba9e` is an ancestor, not the parent).
- **R-DT-5 (MINOR) → §7.1** — "`shipped_in` is written by `cut-release.sh`" invited a second direct
  writer two paragraphs after the single-writer rule; reworded to "recorded at cut time **via the
  seam**".
- **R-DT-6 (RECOMMENDED, adopted) → §3.3 / §13-R15** — the core→delta predicate was literal-path
  matching only, so `source "$LIB/delta-${kind}.sh"` evades it. A bare `delta-` token tier over
  CORE files is added, with its false-positive cost and its residual stated.
- **R-DT-7 (RECOMMENDED, adopted) → §7.2** — two equivalence notes added: hotfix's `close_review`
  is carried by `retro_review`, and `touch_trigger`'s single token bundles the scoped scanner
  re-run with the threat-model refresh.

**v1.0 (2026-08-02)** — pre-review draft. Authored against the tree at
`worktree-agent-a90cc6992bc16aee0`, branch `docs/delta-track-design`, parent commit `6449838`.
Docs-only: no product code, template, policy text, or backlog edit lands from this work package.

### §0.3 — Verification posture, and where the repository corrected the brief

Every claim marked *verified* was re-derived against this tree on **2026-08-02** by running the
command, not by reading a header. §14 is the executed log. **Eleven findings** materially refine
the framing the settled decisions were handed to me in. **None of them invalidates a settled
decision**; all eleven are designed for rather than around.

| # | Correction | Consequence |
|---|---|---|
| **C1** | **`check-maintenance.sh` is shipped today — only the *invocation* half is orphaned.** BL-117's F20 closed the shipping gap: `init.sh` carries `cp "$SCRIPT_DIR/scripts/check-maintenance.sh" scripts/` and the script is in the `chmod +x` list. The orphan is real and narrower: `grep -rn 'check-maintenance' .github/ templates/ scripts/hooks/` returns **nothing** (§14-V1) — no CI job, no hook, no gate runs it. The only non-init mentions in `scripts/` are a comment in `upgrade-project.sh` and the script's own `# Usage:` line. | D5's "finally wires the orphan" is exactly right, but a build that re-ships the file would be re-fixing a closed defect. §8.3 wires **invocation only**. |
| **C2** | **The cadence thresholds D5 tightens are live constants in a shipped script, and the guide disagrees with the script.** `check-maintenance.sh` implements **three** cadences — CHANGELOG 35d, `sbom.json` 35d, dependency scan 95d, security scan 185d (four thresholds, three named cadences) — while `docs/builders-guide.md` Step 4.4 names **four** (Weekly / Monthly / Quarterly / Biannually) and puts the **full dependency audit** under *Biannually* while the script has it at 95d. | §8.3 is a threshold rewrite of a live script (35→14, 185→95) **plus** a guide reconciliation, not a greenfield checker. The pre-existing script/guide split is why D5's "dependency audit folds in" is a resolution, not just a retune. |
| **C3** | **The `feat:`-requires-Build-Loop predicate is TWO surfaces with DIFFERENT phase predicates, and only one of them is live in the delta era.** `process-checklist.sh::check_commit_message` gates at `current_phase < 2 → exit 0`, i.e. **≥ 2, including 4** — verified by execution: at `current_phase: 4` with no active Build Loop, `--check-commit-message "feat: add dark mode"` **exits 1** and prints "no Build Loop active" (§14-V4). `check_commit_ready` (the file-heuristic path) requires the Build Loop only under `[ "$current_phase" -eq 2 ]` — so at phase 4 it falls through to `exit 0` and enforces nothing. | D7's ">= 2" is **true of the surface that matters** and false of the other. Two consequences: (a) the FEATURE class inherits the Build Loop **mechanically** at phase 4 with no new gate; (b) **WP0's pin must target `check_commit_message`** — a pin written against `check_commit_ready` would pass vacuously at phase 4 and prove nothing. |
| **C4** | **Two clocks, two grammars — and neither is machine-readable today.** `templates/generated/bugs.tmpl`'s Severity Guide is SEV-1..4 with **dispositions, no times** ("No — must fix immediately"). `docs/governance-framework.md` § *Post-Release Vulnerability Response* is **CVSS-keyed**, not SEV-keyed: Critical ≥ 9.0 → 24 h or take offline; High 7.0–8.9 → 7 days; Medium → next monthly window; Low → next quarterly window. SEV *times* exist only as intake prose (`templates/project-intake.md`: "default: SEV-1 24h, SEV-2 7d, SEV-3 best effort") and three wizard prompts spelled **SEV-Critical / SEV-High / SEV-Low**. None reaches an enforced field — contrast `# BL-203-INTERVAL-PLUMB`, which exists precisely because saving an intake answer without plumbing it to the enforced field is a silent no-op. | D2's "the governance framework's severity→response-time table drives the clock" is true **for the security-patch class** (which is CVSS-shaped) and needs a *different* source for ordinary fixes. §7.2's policy config carries both, explicitly, because neither has an enforced home today. |
| **C5** | **The SEV block is stronger than D8 assumes in one direction and weaker in another.** *Stronger:* `scripts/test-gate.sh::check_phase_gate` is invoked by `check-phase-gate.sh` under **`current_phase -ge 3`**, which includes 4 — and **all ten** GitHub CI templates plus the GitLab set run `bash scripts/check-phase-gate.sh` on every CI run. Executed at `current_phase: 4` with one `SEV-1 \| Open` row: the Bug Gate arm fires and contributes a blocking issue (§14-V5). So SEV-1/SEV-2 enforcement **does** carry into the delta era, in CI, mechanically. *Weaker:* it is still not a **queue interrupt** — it blocks a gate/CI run, it does not reorder work — and its user-facing text still says "before Phase 3", which is wrong at phase 4. | D8's "must not claim a queue mechanism" stands, and §5.4 states the mechanism precisely: a CI-time block, not an interrupt. The stale "before Phase 3" wording is recorded as **§13-R7**. |
| **C6** | **The UAT batch counter counts features and nothing else.** `scripts/test-gate.sh::record_feature` increments `.features_since_last_test` and recomputes `.testing_required = (.features_since_last_test >= .test_interval)`; `_unrecord_feature_apply` is its exact inverse. No fix path touches it. | D8's "a fix rides the NEXT UAT session" is a consequence of the counter's arity, not a policy choice. §5.4 says so and does **not** propose a fix-counting arm. |
| **C7** | **The release lanes are version-generic on two hosts and version-*strict* on the third.** GitHub (`templates/pipelines/release/github/*.yml`, 4 files) and Bitbucket (4 files) match `v*`. **GitLab** (4 files) matches `/^v\d+\.\d+\.\d+$/` — three numeric components, no pre-release suffix, no `v1.2`. | D6's "existing release lanes fire as-is" holds **only** for an exact `vMAJOR.MINOR.PATCH` tag. §9.3 makes that a hard constraint on `cut-release.sh`: v1 emits exactly that form and **must not** emit `-rc1`-style suffixes, or GitLab projects silently never build. |
| **C8** | **`--finalize-phase {3\|4}` is a second orphan sitting beside `check-maintenance.sh`.** It is invoked by **nothing** — `grep -rn 'finalize-phase'` across `scripts/`, `templates/`, `.github/`, `init.sh` returns only its own parser/dispatch/comment lines plus `tests/test-phase-finalize.sh` (§14-V8). Its own comment says "CI **may** invoke it on tag push". | It is the natural pre-tag check for `cut-release.sh` — **and Karl did not decide to wire it**, so it is recorded as an adjacency and an open question (Q3), not designed in. |
| **C9** | **"Single writer" is a NEW invariant, stricter than the framework's own practice.** `.claude/process-state.json` has **four** writers today: `process-checklist.sh` (primary), `check-gate.sh` (a `jq … > .tmp && mv` pair), `session-intake-check.sh` (the `proceed_without_intake_acknowledged` write), and `pre-commit-gate.sh::tdd_record_attestation` (`.tdd_attestations`). | D7's single-writer rule for `delta-state.json` is a **strengthening**, not an inheritance. §7.1 says so, and §3.3's lint is what makes it checkable rather than aspirational. |
| **C10** | **The seam and the writer are the same file — which is what makes D1 and D7 compatible.** `pre-commit-gate.sh` invokes `process-checklist.sh --check-commit-message` (`# BL-010-COMMITMSG-BL006`) and `--check-commit-ready --subject`. So "one narrow seam into the commit gate" (D1) and "single writer = `process-checklist.sh`" (D7) name **one** core→delta edge, not two. | §3.3's lint allowlist has **cardinality exactly one**, and the lint fails if it grows. Without C10 the two decisions would appear to conflict; with it they compose. |
| **C11** | **Nothing of the delta track exists.** `grep -rl 'delta-state\|delta_state\|cut-release\|docs/deltas'` over the tree (minus `.git/`) returns **no matches**; `docs/deltas` and `scripts/cut-release.sh` do not exist. Separately, `init.sh` ships **no** `.claude/agents/` (0 hits) — the downstream adversarial-review surface is the shipped `evaluation-prompts/Projects/` tree (`compose.sh`, `run-reviews.sh`, `bases/`, `modules/`). | Greenfield, with no naming collisions to dodge. And D3's "adversarial review on every delta close" is delivered downstream by the **prompt library**, not by a shipped reviewer agent — §5.3 says so rather than implying an agent that generated projects never receive. |

---

## §1 — Problem and evidence

Four problems motivate the delta track. Each carries an anchor and an evidence tier
(*verified current state* = re-derived from this tree by execution; *doctrine* = written policy in
a shipped document; *design rationale* = a recorded decision, not a repo fact).

| # | Problem | Evidence (anchor) | Evidence tier |
|---|---|---|---|
| 1 | **The lifecycle ends at the tag.** Phases 0–4 are gated end to end; after Phase 4 the framework has artifacts but no loop. `PHASE4_STEPS` (`production_build … handoff_tested`) is the last enumerated sequence in `scripts/process-checklist.sh`, and `_set_current_phase_min 4` is the highest advance any code path performs. There is no phase 5 and no post-4 process key. | `PHASE4_STEPS` and the five `_set_current_phase_min` call sites in `scripts/process-checklist.sh` (count re-derived by execution); `get_steps_for_process`'s **six** accepted keys — `phase1_architecture`, `build_loop`, `uat_session`, `phase3_validation`, `phase4_release`, `phase2_init` — enumerated with `invariant_check`'s own awk (§14-V14). None of the six is post-Phase-4. | Verified current state |
| 2 | **The post-1.0 tools exist but nothing runs them.** `check-maintenance.sh` is shipped and invoked by nothing (C1). `--finalize-phase {3\|4}` is invoked by nothing (C8). Both are the framework's own post-release aggregate checks; both are scripts nobody runs. | §14-V1 and §14-V8. | Verified current state |
| 3 | **Post-1.0 work has no classification, so it gets one ceremony or none.** `templates/generated/bugs.tmpl` and `templates/generated/features.tmpl` are ledgers with header comments; `docs/builders-guide.md` Step 4.4 is prose. Deciding whether a given change needs a brief, a repro test, a threat-model refresh, or none of it is left to the operator's memory at the moment they are least able to exercise it (a production incident). | The two ledger templates' header comment blocks; builders-guide § Step 4.4 (four cadences, all prose obligations). | Verified current state (doctrine) |
| 4 | **The maintenance obligations are written as calendar advice, and calendar advice is what the first five phases exist not to rely on.** Step 4.4 opens "Schedule these cadences proactively — create recurring calendar events… Do not rely on memory," then names four cadences that only a manually-invoked script partially checks (C1, C2). | `docs/builders-guide.md` § Step 4.4; `scripts/check-maintenance.sh`'s four thresholds. | Verified current state (doctrine) |

**What does not exist today (verified).** No delta concept, no `docs/deltas/`, no
`.claude/delta-state.json`, no `scripts/cut-release.sh`, no `scripts/lib/delta-*.sh`, no
post-Phase-4 process key, and no dependency-direction lint (C11, §14-V11). What **does** exist, and
what the delta track consumes rather than rebuilds, is listed in §2.

---

## §2 — Product boundary

**The delta track is:** a classified, gated, single-queue lifecycle for post-1.0 change, plus a
cadence clock and a release-cut tool, built as a severable module over the framework's existing
enforcement.

**What it inherits untouched** (verified; the delta track adds no second copy of any of these):

| Inherited mechanism | Anchor | Tier |
|---|---|---|
| Secret detection, SAST, and project-test blocking arms in the generated pre-commit hook | `# BL-163-BLOCKED-LEDGER` in `scripts/lib/hook-templates.sh` (gitleaks / semgrep / project-tests set `FAILED=1`) | Mechanical |
| TDD-ordering gate, firing on `feat` \| `fix` \| `refactor` subjects | `# BL-072-TDD-DETECT` and `# BL-072-TDD-ENFORCE` in `scripts/pre-commit-gate.sh`; `_tdd_triggers` | Mechanical (tier-keyed on `# BL-084-TIER-KEY`) |
| `feat:`-requires-Build-Loop at phase ≥ 2 | `process-checklist.sh::check_commit_message` (C3, §14-V4) | Mechanical |
| SEV-1 / SEV-2 bug block at `current_phase ≥ 3`, run by every scaffolded CI pipeline | `scripts/test-gate.sh::check_phase_gate`, invoked from `scripts/check-phase-gate.sh` (C5, §14-V5) | Mechanical (CI-time) |
| Phase-4 release-checklist presence audit | `# BL-105-PHASE4-GATE` in `scripts/check-phase-gate.sh` | Mechanical |
| Phase-3 scanner driver (five real scanners, attest-on-skip) | `scripts/run-phase3-validation.sh` | Mechanical |
| Adversarial review prompt library, shipped downstream | `evaluation-prompts/Projects/` (`compose.sh`, `run-reviews.sh`, `bases/`, `modules/`) — C11 | Advisory (prompt-driven) |

**The delta track is not:**

- **Not a phase 5.** `current_phase` stays 4 forever (D7). The delta track is a loop *inside*
  phase 4, not a sixth stop on a line.
- **Not a bug tracker.** `BUGS.md` and `FEATURES.md` remain the ledgers; a delta *links* a row,
  it does not replace one.
- **Not a plugin host.** D1 rules out a plugin socket on any schedule; the family extensibility
  model is fork-and-PR (§12).
- **Not a multi-queue system.** One open delta at a time in v1 (D7). Concurrency is §13-R1.
- **Not an incident-response system.** `templates/generated/incident-response.tmpl` already owns
  SEV-keyed notification chains and post-incident review. The hotfix class *ships the code*; the
  incident template *runs the incident*. §5.2 states the seam.

---

## §3 — Placement: the severable module (D1)

### §3.1 — The module inventory

D1 fixes the shape: own lib files, own state file, one seam. The inventory is author-proposed
within it.

**Delta-module files (author-proposed).** Everything here is created by this feature and would
leave with it:

| Path | Role |
|---|---|
| `scripts/lib/delta-state.sh` | Read/write `.claude/delta-state.json` (atomic tmp+mv, the house pattern) |
| `scripts/lib/delta-policy.sh` | Read `.claude/delta-policy.json`, apply defaults, validate schema |
| `scripts/lib/delta-classify.sh` | Phrase→class proposal; risk / level / severity derivation (§4.2) |
| `scripts/lib/delta-cadence.sh` | Cadence arithmetic and overdue predicates (§8.3) |
| `scripts/delta.sh` | The module CLI: `--open`, `--confirm`, `--status`, `--close`, `--retro` |
| `scripts/cut-release.sh` | The release cut (§9). **Declared a delta-module file** despite its core-sounding name — it reads `delta-state.json`, so classifying it as core would create a second core→delta edge |
| `scripts/lint-delta-boundary.sh` | The dependency-direction lint (§3.3) |
| `docs/deltas/` | Brief location (D4) |
| `.claude/delta-state.json` | Module state (§7.1) |
| `.claude/delta-policy.json` | Project-owned policy (§7.2) |

**The one seam.** `scripts/process-checklist.sh` is the single core file that references the
delta module. C10 is why this is one edge and not two: `process-checklist.sh` is *both* the
commit-gate classifier `pre-commit-gate.sh` calls (`# BL-010-COMMITMSG-BL006` and the
`--check-commit-ready --subject` call) *and* D7's designated single writer of `delta-state.json`.
The seam is a small, declared set of `--delta-*` actions that source `scripts/lib/delta-state.sh`.

**Severability test (author-proposed, and the thing the lint really protects):** delete every
delta-module file and revert **every core consumer of the module**, and the full suite must
pass. That is the property "severable" means operationally; §11-WP7 makes it a test.

**The revert set is SIX consumers, not one. v1.2 (2026-08-09) — evidence-led: the enumeration is
what running the test produced, across three review rounds.** v1.0/v1.1 said "the seam block in
`process-checklist.sh`", singular. By WP7 it was six, each arriving in a different work package with
its own good reason, and the last two are not scripts at all:

| # | Consumer | What reverts | Arrived in |
|---|---|---|---|
| 1 | `scripts/process-checklist.sh` | the `DELTA-SEAM` fence — the seam itself, and the only allowlisted edge | WP2 |
| 2 | `scripts/upgrade-project.sh` | `_postmvp_policy_notice` **and its call site** | WP2 (§3.2's NOTICE-ONLY arm) |
| 3 | `scripts/validate.sh` | `_postmvp_era_assertion` **and its call site** | WP3 (§10.1's report-only assertion) |
| 4 | `scripts/check-maintenance.sh` | the `# CADENCE-POLICY-READ` line | WP6 |
| 5 | `.github/workflows/lint.yml` | the `delta-boundary-lint` job, as a whole block | WP1 |
| 6 | `tests/full-project-test-suite.sh` | the direct `run_child_suite "scripts/lint-delta-boundary.sh"` registration | WP1 |

Consumers 5 and 6 each falsified this section's own claim once. §3.1 defines severability as *"the
full suite must pass"*; consumer 6 is the file that **is** the full suite, invoking a module script
directly rather than through a `tests/…` path, so post-sever that line was `bash` on a deleted file
— rc 127 — and the very run the property is stated in terms of went red. Both misses had the same
shape: a consumer living in a **file class the residual sweep never opened** (a workflow, then the
aggregator). The transferable lesson is the **scope list**, not the manifest.

**Two things running it taught, which change what the test is for.**

1. **Functional severability is already free, so the load-bearing instrument is the *reference
   sweep*, not the behavioural one.** Measured: with every module file deleted and **no revert at
   all**, all four script consumers still behave — the seam answers rc 2 ("the delta module is not
   installed"), `validate.sh`'s assertion is `|| return 0`, upgrade's notice is `|| true`, and
   `check-maintenance.sh`'s policy read falls back to the framework constants. Each fails soft by
   design and each says so in its own header. The consequence for §11-WP7 is concrete: the obvious
   mutation — *delete a module file but not the seam revert → RED* — **cannot be a functional
   one**; it stays green precisely because the fail-soft design works, and it has to be killed by
   the structural arm instead.
2. **A multi-line construct must be dropped as a construct, never line-by-line.** A line-based drop
   on the aggregator left an **orphaned continuation line** — `run_child_suite` calls span three
   lines, and a dangling `"…string…" \` is a syntactically valid command. **`bash -n` passes on
   it**, so no parse check could have caught it; only reading the surviving references does.

**§3.1's inventory above omits the module's own test files** (`tests/test-delta-*.sh`,
`tests/test-lint-delta-boundary.sh`, and their registrations in `tests/full-project-test-suite.sh`
and the `tests.yml` unit list). The severability test deletes them anyway — a module whose own
suites stayed behind would leave a suite full of red, which is not something "severable" can mean.
One real cost of that is on the record rather than in a footnote: `tests/test-delta-wp6-cadence.sh`
is a delta-track suite that is also the **only** coverage of a CORE script,
`scripts/check-maintenance.sh`, so severing the module takes that coverage with it.

### §3.2 — The mechanism/policy split

D1: machinery ships with the framework; policy lives in a project-owned config the sync never
overwrites.

| What | Where | Who owns it | Sync behaviour |
|---|---|---|---|
| Class→gate mapping *machinery* | `scripts/lib/delta-policy.sh` | Framework | Refreshed by `upgrade-project.sh` like any script |
| Class *definitions*, gate floors, cadence thresholds, size thresholds, risk surfaces, SLA table, semver map | `.claude/delta-policy.json` | **Project** | **Never overwritten** |
| Live delta state | `.claude/delta-state.json` | Project (machine-written) | Never overwritten |

**The precedent for "never overwritten" is already in the tree, and it is the strong form.**
`scripts/upgrade-project.sh` carries the **rendered-doc fence** `# BL-099-DOC-GUARD`: `CLAUDE.md`
and `PROJECT_INTAKE.md` are NOTICE-ONLY "under EVERY flag and env combination: no `.new`, no
`.bak`, no template copy". The weaker sibling precedent is the legacy unmarked pre-commit hook,
"treated as fully user-owned (sidecar `.new`, never overwritten)".

**Decision — which precedent `delta-policy.json` follows:**

| Option | On upgrade | Pro | Con | Verdict |
|---|---|---|---|---|
| Managed-region refresh (the `hook-templates.sh` `SOIF_*_OPEN/_CLOSE` model) | Framework rewrites part of the file | Framework can push new class defaults | A project's tuned floor can be silently reverted — the exact failure the split exists to prevent | Rejected |
| **NOTICE-ONLY, the `# BL-099-DOC-GUARD` form** | Framework never writes it after birth; upgrade prints a one-line notice naming new keys | Policy is unambiguously the project's; zero silent-revert surface | A project can drift below a framework default and never learn it, absent the notice | **Recommended** |
| Sidecar `.new` | Framework writes `delta-policy.json.new` | Operator can diff | Two files to reason about; the sidecar rots unread | Rejected |

**Recommendation: NOTICE-ONLY.** `init.sh` (or first `delta.sh --open`) writes the file once with
framework defaults; nothing ever rewrites it. `upgrade-project.sh` gains a notice arm that names
any policy key the framework has learned since, and applies nothing. Absent keys fall back to
framework defaults at read time in `delta-policy.sh`, so an old file is never broken by a new
framework — it is merely quiet.

### §3.3 — The dependency-direction lint (spec)

**`scripts/lint-delta-boundary.sh`** — new, and D1 requires it **from the first commit**, which
means it lands in WP1 alongside the first lib file, not at the end.

**The defect class it prevents.** A severable module stops being severable one convenience call at
a time. Nobody decides to fuse the module into the framework; someone adds `source
scripts/lib/delta-state.sh` to `check-phase-gate.sh` on a Tuesday because it was easier, and the
severability property is gone with no test failing. The lint makes the fusion a red check.

**The predicate, in two directions plus two guards:**

1. **Delta → core: allowed, unasserted.** The module may source `helpers-core.sh`, call
   `guard_not_in_framework`, read `phase-state.json`. No assertion; asserting it would be
   busywork.
2. **Core → delta: forbidden.** For every file in the **CORE set**, no *executed* line may name
   any delta-module path (`scripts/lib/delta-*.sh`, `scripts/delta.sh`, `scripts/cut-release.sh`,
   `delta-state.json`, `delta-policy.json`, `docs/deltas/`).
3. **Seam allowlist — cardinality exactly one.** `scripts/process-checklist.sh` is the sole
   allowlisted core file. The lint asserts the allowlist array has **length 1** and fails if it
   grows. A second seam is a design change and must be argued, not merged.
4. **Vacuity floor.** The lint exits **2** unless it found ≥ 1 delta-module file and ≥ 1 core
   file. A boundary lint that scans nothing passes trivially, and a passing lint that proves
   nothing is worse than no lint — this repo has the scar.

**Set definitions.** CORE = `init.sh` + `scripts/*.sh` + `scripts/lib/*.sh` + `scripts/hooks/*.sh` +
`scripts/host-drivers/*.sh`, **minus** the delta-module inventory of §3.1 **and** the lint itself
(which names every delta path by construction). DELTA = the §3.1 inventory. Both sets come from one
literal manifest at the top of the lint, so adding a module file is a one-line edit and the sets can
never disagree.

**`scripts/host-drivers/*.sh` is a v1.2 addition (2026-08-09) — evidence-led, approved by Karl, and
proved by plant rather than argued.** v1.0/v1.1 named **four** globs, and both boundary lints were
built faithful to that number; both disclose the exclusion in their own headers as a pending design
question ("widen it only by amending the design, and then in both places"). This is that amendment.
The gap is not a theoretical one: appending `source "$SCRIPT_DIR/lib/delta-state.sh"` to
`scripts/host-drivers/github.sh` in a fixture tree leaves `scripts/lint-delta-boundary.sh` at
**rc=0** — `OK: no core -> delta edge`, 72 core files scanned and the planted file not among them —
while the **identical** line appended to `scripts/validate.sh`, which the four globs do reach, reds
at **rc=1** with a T1 violation. First planted by review; **re-executed for this amendment**, both
directions. The predicate is sound; the population was short. The three host
drivers (`github.sh`, `gitlab.sh`, `bitbucket.sh`) are ordinary core code by every other measure —
`init.sh`, `scripts/lib/host.sh` and `scripts/intake-wizard.sh` all source them by path, and
`init.sh` ships them downstream — so a `source .../delta-state.sh` added to one fuses the
module exactly as thoroughly as the same line in `check-phase-gate.sh`, and the severability
property is gone with no check failing. **The sibling brownfield lint has the same hole for the same
reason and takes the same correction** (`docs/designs/2026-08-02-brownfield-adoption-v1.md` §3.3 and
`docs/module-contract.md` M3), because the two lints are kept at exact parity by design.
**Not yet implemented:** the `CORE_GLOBS` arrays in both lints still list four entries as of
2026-08-09. Widening them is tracked as **`## BL-215:`**, which carries the measurement table above
and the both-lints-in-sync fix shape; until it lands, this section states the contract and the lints
under-enforce it.

**Two match tiers, because literal paths are evadable (R-DT-6).** Clause 2 as written matches
*literal* delta paths, and bash lets a reference be composed at runtime:
`source "$LIB/delta-${kind}.sh"` contains no literal delta path and would pass a path-only lint
while fusing the module exactly as thoroughly. So the scan runs two tiers over CORE files:

| Tier | Pattern | Verdict | Why this severity |
|---|---|---|---|
| **T1 — literal path** | any `scripts/lib/delta-*.sh`, `scripts/delta.sh`, `scripts/cut-release.sh`, `delta-state.json`, `delta-policy.json`, `docs/deltas/` | **FAIL** | Unambiguous: a core file names a module file |
| **T2 — bare `delta-` token** | the string `delta-` on any executed line of a CORE file that T1 did not already catch | **FAIL, with an allowlist** | Catches `"$LIB/delta-${kind}.sh"`, `"delta-"$x`, and the whole variable-composition family, because every such reference still carries the literal prefix |

T2 is deliberately coarse and will occasionally fire on prose-in-a-string (an error message that
says "delta-state"). That is the right trade: a false positive costs one allowlist row with a
reason; a false negative costs the severability property silently. **The residual T2 does not
close is stated at §13-R15** — a reference composed below the prefix boundary
(`source "$LIB/del""ta-state.sh"`, or a path assembled from a variable holding `delta`) evades
both tiers, and no grep-based lint can catch it. The severability test (§3.1, WP7) is the
backstop, because it is behavioural rather than lexical.

**Executed lines only.** Both tiers strip whole-line comments *and* trailing comments before
matching, at any indent and any whitespace width, with and without a space after `#`. This is not
a stylistic choice: `scripts/lint-tests-registered.sh` carries the repo's hard-won version of
exactly this predicate, and CLAUDE.md records that a one-character narrowing of it re-opened the
same hole three times while passing both PR-blocking checks each time. The fixture must pin each
atom's **width and spelling**, not just its presence.

**Interface.** `--list` mode (PASS/FAIL table, the `lint-fix-functions-stderr.sh` convention);
exit 0 clean / 1 violation / 2 invocation-or-vacuity error; allowlist entries require a reason
string. `scripts/run-lints.sh` discovers it **by glob** (`for lint in "$LINT_DIR"/lint-*.sh`) with
no wiring — verified. A CI job is a separate one-block addition to `.github/workflows/lint.yml`
(eleven lint jobs there today, measured 2026-08-02).

**Mutation proof (WP1).** Add `source "$SCRIPT_DIR/lib/delta-state.sh"` to a core script →
the lint must go RED. Second mutation: add a second entry to the seam allowlist → RED on the
cardinality assertion. Third: point the DELTA manifest at a non-existent directory → exit 2 on
the vacuity floor, **not** 0.

---

## §4 — Classification (D2)

### §4.1 — The four classes

D2 fixes them. They are a partition of post-1.0 change by *what the change is for*, which is the
one thing the operator always knows without analysis:

| Class | The operator's situation | What it buys them |
|---|---|---|
| **feature** | "I want the product to do something new" | Full ceremony — the thing most likely to be regretted later gets the most design and review |
| **fix** | "Something is broken; it can wait for the normal loop" | Repro-test discipline without brief overhead |
| **hotfix** | "Something is broken **now**, in production" | Speed, paid for with a mandatory, release-blocking retro |
| **security-patch** | "Someone could exploit this" | Fix ceremony plus the three security-specific obligations (dependency scan, SBOM, flagged note) |

**One question, usually pre-answered.** D2 requires the class be **auto-proposed from the user's
phrasing** where possible and confirmed, never quizzed. §4.3 gives the shape.

### §4.2 — Derived-then-confirmed attributes (author-proposed formulas)

D2 fixes *what* is derived and that it is confirmed; the formulas are author-proposed. All three
read from the policy config (§7.2) so a project can retune without a framework change.

| Attribute | Domain | Derivation (author-proposed) | Confirmed how |
|---|---|---|---|
| **risk** | `core` \| `feature-local` | The touched-file set (`git diff --name-only` against the merge base) intersected with `delta-policy.json::risk_surfaces` — a glob list seeded from the project's threat-model surfaces, auth paths, and data-contract paths. Non-empty intersection ⇒ `core`. | Shown with the *matching paths named*; operator may raise to `core` freely, and lowering to `feature-local` records a reason |
| **level** | `small` \| `significant` \| `evolution` | Changed lines (`git diff --shortstat`) against `delta-policy.json::size_thresholds`. Below `small` ⇒ small; below `significant` ⇒ significant; at or above ⇒ evolution. Ratchet-only within a delta: the level may rise as work proceeds, never fall. | Shown with the measured number; operator may raise |
| **severity** | `SEV-1`..`SEV-4` (fix/hotfix/security-patch only) | Proposed from the `BUGS.md` row if one exists, else from phrasing against the shipped Severity Guide's own definitions in `templates/generated/bugs.tmpl` | Confirmed against the Severity Guide table, printed inline |

**Two honest limits, stated rather than smoothed:**

- **Derivation at open time is a forecast.** At `--open` the diff is usually empty, so `risk` and
  `level` are proposals from the *stated* intent; they are **re-derived at close** from the real
  diff. A close-time re-derivation that lands in a higher bracket than the confirmed one **raises**
  the attribute and toggles the extra gates (D2: "attributes toggle extra gates"). It never
  lowers. Without the ratchet, a delta opened as `small`/`feature-local` and grown into an auth
  rewrite would close on the small checklist.
- **`risk_surfaces` is a project-authored glob list.** Its quality is the operator's, not the
  framework's. §13-R4 records this; the session-start branch (§10.5) is the mitigation, not a cure.

**Class picks the checklist; attributes toggle extra gates** (D2). §5.2 is the table.

### §4.3 — Confirm-not-quiz

D2 names the pattern; the repo already has its reference implementation. `# BL-204-PREFILL` in
`scripts/intake-wizard.sh` reads a remembered answer, prints it, and asks the operator to *keep or
change* it — with a printed reason why re-asking would be wrong ("recorded in
`.claude/manifest.json`; you are confirming it, not re-answering it"). Its prefill reads are
individually marker-tagged (`# BL-204-PREFILL-READ`) and mutation-pinned by
`tests/test-intake-wizard-fixes.sh`, which excises the markers and requires **both** reads to be
present.

The delta open transcript copies it exactly (author-proposed wording):

```
You said: "the CSV export crashes on unicode"

  Class:    fix            (proposed from your wording — a fix is something broken
                            that can wait for the normal loop; a hotfix is production,
                            now)
  Severity: SEV-2          (feature broken, workaround exists — per the Severity Guide
                            in BUGS.md)
  Risk:     feature-local  (no touched path matches a risk surface yet)
  Level:    small          (estimated; re-measured from the real diff at close)

  [1] Keep all four        [2] Change the class        [3] Change an attribute
```

The operator answers **one** thing. Everything else is a confirmation with its reasoning shown —
and every one of the four lines names *where the value came from*, because a proposal whose
provenance is hidden is a quiz with extra steps.

---

## §5 — Per-class demands (D3)

### §5.1 — The floor (already shipped — verified)

D3: "floor always on, already shipped". Verified, with anchors:

| Floor arm | Anchor | Note |
|---|---|---|
| gitleaks (secret detection) | `# BL-163-BLOCKED-LEDGER`, `scripts/lib/hook-templates.sh` | Blocking arm; sets `FAILED=1` |
| semgrep (SAST quick scan) | same fence | Blocking arm |
| project tests | same fence | Blocking arm |
| TDD ordering | `# BL-072-TDD-DETECT` / `# BL-072-TDD-ENFORCE`, `scripts/pre-commit-gate.sh` | `_tdd_triggers` fires on `feat` \| `fix` \| `refactor`; **phase-independent** — no `current_phase` read in the predicate |

The delta track adds **no** floor arm and **no** second copy of any of these. Every class row
below is *in addition to* the floor.

### §5.2 — The per-class gate subset

**Base checklist by class (D3), plus attribute-toggled extras (D2).**

| Gate token | feature | fix | hotfix | security-patch | Toggled ON additionally by |
|---|---|---|---|---|---|
| `brief` — one-page delta brief at `docs/deltas/DELTA-NNN-slug.md` | ✅ | — | — | — | `level: evolution` on any class |
| `brief_review` — **pre-build adversarial review of the brief** | ✅ | — | — | — | `risk: core` on any class |
| `ledger_row` — `FEATURES.md` or `BUGS.md` row linking the delta | ✅ (FEATURES) | ✅ (BUGS) | ✅ (BUGS) | ✅ (BUGS) | — |
| `build_loop` — the full existing Build Loop | ✅ | — | — | — | *(inherited mechanically — C3)* |
| `repro_test_red_first` — reproduction test, RED before the fix | — | ✅ | — | ✅ | — |
| `audit_row_at_open` — a ledger row written **when the fast lane opens** | — | — | ✅ | — | — |
| `retro_review` — retro within **3 days**; open retro **blocks the next release cut** | — | — | ✅ | — | — |
| `threat_model_refresh` + scoped scanner re-run | — | — | — | — | **touch trigger** (§8.1) |
| `dependency_scan` (forced) | — | — | — | ✅ | — |
| `sbom_refresh` | — | — | — | ✅ | — |
| `flagged_release_note` | — | — | — | ✅ | — |
| `close_review` — adversarial review at close | ✅ | ✅ (lighter) | ✅ *(at retro)* | ✅ | — |
| `changelog` — a `## [Unreleased]` entry under the right category | ✅ | ✅ | ✅ | ✅ | — |

**Reading the hotfix row honestly.** The hotfix lane ships on the floor alone plus an audit row.
It does **not** skip review — it **defers** it, by exactly 3 days (Karl set 3, not 7), and the
deferral is collateralised: `cut-release.sh` refuses while any retro is open (§9.2). That is what
makes the fast lane a loan rather than a leak.

**The incident-response seam.** `templates/generated/incident-response.tmpl` already owns the
SEV→response-time notification chain (Immediate / 1 h / 4 h / next window), the escalation rule,
and a post-incident review "within 48 hours of resolution" filed at
`docs/incidents/YYYY-MM-DD-<slug>.md`. The hotfix class does **not** duplicate any of it. Note the
two clocks differ on purpose and neither is wrong: the incident template's 48 h governs the
*incident* write-up; D3's 3 days governs the *code* retro. §7.2 makes both readable from one place
so a project can align them if it wants.

### §5.3 — Adversarial review, twice, and what actually delivers it

D3 puts a reviewer at **two** points: **before** the build (feature briefs) and at **every**
delta close.

**The brief's acceptance criteria ARE the close review's rubric** (D3). This is the strongest
sentence in the decision and it is worth stating why: it converts review from an open-ended
judgment into a conformance check against a document the operator wrote *before* they were
invested in the implementation. It is the same move `docs/designs/2026-07-24-operating-model-v1.md`
§6.1 makes for plans — a top-tier plan turns execution into conformance work, the cheapest thing
to verify.

**What delivers the review, honestly tiered:**

| Surface | Tier | Anchor |
|---|---|---|
| The rubric itself (brief acceptance criteria → close checklist) | **Mechanical** — the close gate reads the brief's criteria section and refuses an unchecked box | New (WP4) |
| The reviewer in a generated project | **Advisory** — prompt-library-driven | `evaluation-prompts/Projects/` ships (`run-reviews.sh`, `compose.sh`); `init.sh` ships **no** `.claude/agents/` (C11) |
| The reviewer in this framework repo | **Advisory, better-equipped** | `.claude/agents/pr-reviewer.md` (BL-146) exists here and only here |

This document does **not** claim generated projects get a reviewer agent. They get a prompt
library and a rubric; the rubric is the mechanical part.

### §5.4 — What the delta track does NOT claim (D8, sharpened by C5/C6)

- **There is no queue interrupt for SEV-1.** Nothing preempts in-flight work. What exists is
  (a) `templates/generated/bugs.tmpl`'s Severity Guide — "SEV-1 … Can Defer? **No — must fix
  immediately**"; (b) the Status Guide's deferral prohibition — `Won't Fix` is "SEV-3/4 only",
  `Post-MVP` is "SEV-4 enhancements only"; and (c) `scripts/test-gate.sh::check_phase_gate`, which
  **exits 1** on any `SEV-1.*Open`, `SEV-2.*Open`, or `SEV-2.*Deferred` row (§14-V2, §14-V3).
  C5 adds the reach: that gate is invoked from `check-phase-gate.sh` at `current_phase ≥ 3`,
  which includes the delta era, and **every scaffolded CI pipeline runs `check-phase-gate.sh`** —
  so at phase 4 an open SEV-1 turns CI red (§14-V5). **That is a CI-time block, not an
  interrupt.** It stops the *next* thing from going green; it does not reorder the *current*
  thing. The delta track uses it as-is and adds no queue mechanism.
- **A fix rides the NEXT UAT session.** `record_feature` counts *features* into
  `.features_since_last_test` and sets `.testing_required` from `.test_interval`; no fix path
  touches the counter (C6). The delta track does not add a fix-counting arm — batching on features
  is the shipped semantics and changing it is out of scope.
- **Today's bug/feature workflow instructions are retrieval surfaces** (D8): the builders-guide
  and the two ledger header comments. They are correct and unread at the moment of need. §10.5's
  session-greeting branch is what closes that, and it closes it by being **ambient**, not by being
  better written.

---

## §6 — Intake (D4)

### §6.1 — Three creation paths, mirroring birth intake

D4 fixes the three paths. The mirror is exact, and the birth-intake originals are the spec:

| Path | Birth-intake original | Delta analogue | When it is the default |
|---|---|---|---|
| **Guided script** | `scripts/intake-wizard.sh` (prompted, writes the artifact) | `scripts/delta.sh --open` | Operator is in a terminal, no agent session |
| **Conversational AI** | the `resume.sh` first-message branches (`# BL-202-INTAKE-PREDICATE`) | the session-start delta branch (§10.5) → agent runs the class template | **The default** (D4) |
| **Manual template** | `templates/project-intake.md` filled by hand | `templates/generated/delta-brief.tmpl` copied to `docs/deltas/` | Operator prefers an editor; offline |

All three converge on the same three writes: the brief file, the ledger row, and the
`delta-state.json` activation. There is exactly one writer for the third (§7.1).

### §6.2 — The brief (D3's one page, sections author-proposed)

D3 fixes the content: *what / why / done-observable / must-not-change / touched surfaces*.
Author-proposed rendering, as `templates/generated/delta-brief.tmpl`:

| Section | Why it is here |
|---|---|
| **What** | One paragraph, the operator's own words |
| **Why** | The user signal. `PRODUCT_MANIFESTO.md` § 6 already demands this shape — "Each item: what it is, and what user signal would justify building it" — so the bridge (§10.4) can seed it verbatim |
| **Done-observable** | The acceptance criteria. **This section is the close review's rubric** (D3) — so it is written as checkable statements, not aspirations |
| **Must-not-change** | The regression contract. What the operator would be upset to discover broke |
| **Touched surfaces** | The forecast file/area list. Feeds §4.2's risk derivation at open, and is compared against the real diff at close |

The **class template interviews the operator** for these (D4) — they never need to know the list.

### §6.3 — Identity and location

- **Brief:** `docs/deltas/DELTA-NNN-slug.md` (D4). `NNN` is zero-padded to three, allocated as
  `max(existing) + 1` scanned from `docs/deltas/` — **author-proposed**, and chosen to match the
  repo's own `BL-NNN` habit rather than invent a scheme. `templates/generated/identifiers.tmpl`
  already teaches the operator that `SEV-1`..`SEV-4` are a fixed vocabulary and `BUG-<#>` is a bare
  integer; a `DELTA-NNN` row joins that table (WP6).
- **Ledger row:** `FEATURES.md` for features, `BUGS.md` for the other three (D4). The `BUGS.md`
  table format is **parsed by scripts** — its own header says "Do NOT change the table format" and
  `check_phase_gate` greps `SEV-N.*Status` — so the delta link goes in an **existing** column
  (`Fix Reference`, which already takes "PR #12"-shaped values), never a new one. **This is a hard
  constraint, not a preference**: a new column shifts nothing today but is exactly the kind of
  edit that silently breaks a `grep -c 'SEV-2.*Deferred'`.
- **Activation:** `delta-state.json` (§7.1).

---

## §7 — State and policy schemas

### §7.1 — `.claude/delta-state.json` (author-proposed)

D7 fixes two properties: **single writer = `process-checklist.sh`**, and **one open delta at a
time**. The shape is author-proposed, and it encodes the second property *structurally* — a
single `active_delta` object, not an array — on the precedent of `process-state.json`'s
`build_loop.feature`, which is a single slot for exactly the same reason.

```json
{
  "schemaVersion": 1,
  "active_delta": {
    "id": "DELTA-007",
    "slug": "dark-mode",
    "class": "feature",
    "brief": "docs/deltas/DELTA-007-dark-mode.md",
    "ledger": { "file": "FEATURES.md", "key": "Feature 12" },
    "opened_at": "2026-08-02T14:00:00Z",
    "opened_via": "conversational",
    "attributes": { "risk": "feature-local", "level": "significant", "severity": null },
    "attributes_confirmed_at": "2026-08-02T14:01:00Z",
    "gates_required": ["brief", "brief_review", "ledger_row", "build_loop", "close_review", "changelog"],
    "gates_completed": ["brief", "brief_review", "ledger_row"]
  },
  "hotfix_retros": [
    { "id": "DELTA-006", "shipped_at": "2026-07-31T03:12:00Z", "due_by": "2026-08-03T03:12:00Z", "closed_at": null, "record": null }
  ],
  "cadence": {
    "last_routine_review": "2026-07-20",
    "last_deep_security": "2026-05-02"
  },
  "closed": [
    { "id": "DELTA-005", "class": "fix", "severity": "SEV-2", "closed_at": "2026-07-28T10:00:00Z", "shipped_in": "v1.2.1" }
  ]
}
```

Field notes:

- `active_delta` is **an object or `null`**. One-at-a-time is then a property of the schema, not a
  rule someone has to enforce — the cheapest possible enforcement, and the reason to prefer this
  shape over `"deltas": []` with a status field.
- `opened_via` ∈ `guided | conversational | manual` — the three D4 paths, recorded so a later
  review can tell which path produced which quality of brief.
- `gates_required` is **materialised at open** from class + confirmed attributes, not recomputed
  at close. Recomputing would let a policy edit mid-delta silently drop a gate the operator had
  already been told about. Attribute *raises* (§4.2) append to it; nothing removes from it.
- `hotfix_retros` is an array and outlives `active_delta` deliberately: an open retro must block a
  release cut long after its delta closed (D3).
- `cadence` holds the last-completed dates the §8.3 checker reads.
- `closed` is an append-only audit tail; `shipped_in` is **recorded at cut time via the seam** —
  `cut-release.sh` asks `process-checklist.sh` to write it and never touches the file itself,
  which is the single-writer rule below applied to the one place it is easiest to break.

**Single writer (D7), and what it costs.** Only `process-checklist.sh` writes this file — a
**new, stricter** invariant than the framework's own practice, since `process-state.json` has four
writers today (C9). The cost is real: `delta.sh`, `cut-release.sh`, and the session hook must all
*route* their writes through the seam rather than writing directly. That is exactly the
constraint §3.3's lint makes visible, and the reason the allowlist is pinned at one.

### §7.2 — `.claude/delta-policy.json` (author-proposed, project-owned)

Framework defaults shown; every key is overridable and every key falls back at read time (§3.2).

```json
{
  "schemaVersion": 1,
  "classes": {
    "feature":        { "gates": ["brief", "brief_review", "ledger_row", "build_loop", "close_review", "changelog"] },
    "fix":            { "gates": ["ledger_row", "repro_test_red_first", "close_review", "changelog"] },
    "hotfix":         { "gates": ["ledger_row", "audit_row_at_open", "retro_review", "changelog"], "retro_due_days": 3 },
    "security-patch": { "gates": ["ledger_row", "repro_test_red_first", "dependency_scan", "sbom_refresh", "flagged_release_note", "close_review", "changelog"] }
  },
  "attribute_toggles": {
    "risk_core":       ["brief_review"],
    "level_evolution": ["brief"],
    "touch_trigger":   ["threat_model_refresh"]
  },
  "risk_surfaces": [],
  "size_thresholds": { "small": 50, "significant": 400 },
  "cadence": { "routine_review_days": 14, "deep_security_days": 95 },
  "fix_sla": { "SEV-1": "24h", "SEV-2": "7d", "SEV-3": "best-effort", "SEV-4": "post-mvp" },
  "cvss_sla": { "critical": "24h", "high": "7d", "medium": "next-monthly", "low": "next-quarterly" },
  "semver": { "feature": "minor", "fix": "patch", "hotfix": "patch", "security-patch": "patch", "breaking": "major" }
}
```

**Two gate-token equivalences the JSON does not make obvious (R-DT-7).** Read against §5.2's
table, two rows look like the config has dropped a demand. Neither has:

- **`hotfix` has no `close_review` token because `retro_review` carries it.** D3 puts the
  adversarial review on *every* delta close — the hotfix does not skip it, it defers it by
  `retro_due_days`. `retro_review` **is** that close review, arriving late and collateralised by
  the §9.2 release refusal. A separate `close_review` token on the hotfix row would either
  double-charge the review or, worse, let a hotfix satisfy `close_review` at ship time and make
  the retro optional — which is precisely the loan going unrepaid.
- **`touch_trigger` maps to one token because `threat_model_refresh` bundles both halves.** D5's
  touch demand is a threat-model update **and** a scoped scanner re-run, and §8.1 specifies the
  scoped subset (the threat-model and semgrep arms of `run-phase3-validation.sh`, inheriting its
  attest-on-skip contract). The token is one gate satisfied by both, not a gate that forgot the
  scanners. It is spelled as one because the two are never independently completable — a
  threat-model update without a re-scan is an assertion, and a re-scan without the update is a
  finding nobody wrote down.

**Why two SLA tables, and not one.** C4: the two shipped clocks are different grammars pointed at
different things. `fix_sla` mirrors `templates/project-intake.md`'s own defaults ("SEV-1 24h,
SEV-2 7d, SEV-3 best effort") for the fix/hotfix classes. `cvss_sla` mirrors
`docs/governance-framework.md` § *Post-Release Vulnerability Response* — Critical ≥ 9.0 → 24 h,
High 7.0–8.9 → 7 days, Medium → next monthly window, Low → next quarterly window — for the
security-patch class, because a CVE arrives with a CVSS score and not a SEV. **Neither has an
enforced home in the tree today** (C4), which is why both live here rather than being read from
somewhere.

**`risk_surfaces` ships empty on purpose.** A framework-guessed default (`src/auth/**`?
`**/schema*`?) would be wrong for most projects and, worse, would look authoritative. The first
`delta.sh --open` prompts for it, seeded from the project's own threat-model document — and an
empty list makes every delta `feature-local`, which §13-R4 records as the residual it is.

**`size_thresholds` are lines-changed, and lines are a poor proxy.** Stated rather than hidden: a
12-line auth change is riskier than a 900-line locale-file addition. That is exactly why **risk is
a separate axis derived from paths**, not a function of size — and why the operator can raise
either freely.

---

## §8 — Re-fire triggers (D5)

D5 adopts all three. They differ in what they watch and what they cost.

### §8.1 — TOUCH-based

**Trigger:** the delta's real touched-file set intersects an auth surface, a data-contract
surface, or a threat-model surface (`delta-policy.json::risk_surfaces`).

**Demand:** threat-model update **plus** a **scoped** scanner re-run, both before close.

**Scoped, precisely (author-proposed).** `scripts/run-phase3-validation.sh` registers five
scanners — semgrep-full-tree, license, snyk, zap-dast, threat-model — with a detect-and-run
contract and an attest-on-skip rule ("ANY skipped scanner requires an attestation… A non-attested
SKIP counts as a gate FAIL"). The touch trigger re-runs the **threat-model** arm (pure-local, runs
even offline) and the **semgrep** arm; it does **not** re-run license, snyk, or zap-dast, which are
dependency- and deployment-shaped and are the version trigger's and the cadence's business
respectively. The attest-on-skip contract is inherited unchanged — a skipped scoped scanner needs
an attestation exactly as it does at the 3→4 gate.

**Tier: mechanical.** The intersection is computable and the close gate refuses on it.

### §8.2 — VERSION-based

**Trigger:** `cut-release.sh` computes a **major** bump (§9.1).

**Demand:** full `run-phase3-validation.sh` re-run — all five scanners, same attest-on-skip
contract — before the tag is written.

**Tier: mechanical**, and it composes with D6's "breaking ⇒ major + full revalidation" as the same
sentence seen from two sides.

### §8.3 — CALENDAR-based, and the orphan this wires

**Karl's cadences (D5):** a **14-day routine review** (changelog / SBOM / routine) and a
**quarterly deep security scan** with the dependency audit folded in — tightened from the prose's
biannual, explicitly "for now".

**What that means against the shipped script (C2).** `scripts/check-maintenance.sh` today
computes four thresholds:

| Cadence | Signal read | Threshold today | Under D5 |
|---|---|---|---|
| Monthly — CHANGELOG | `git log -1 -- CHANGELOG.md` date | 35 days | **14 days** |
| Monthly — SBOM | `git log -1 -- sbom.json` date | 35 days | **14 days** |
| Quarterly — dependency audit | newest `docs/test-results/*snyk*`/`*dep*`/`*audit*` filename date | 95 days | **folded into the quarterly deep scan** |
| Biannual — security re-audit | newest `docs/test-results/*semgrep*`/`*sast*` filename date | 185 days | **95 days** |

Three notes the build must not lose:

1. **It is a threshold rewrite, not a new checker — but the exit contract is not what the script
   says it is, and the design must add the missing arm.** `check-maintenance.sh`'s docblock
   advertises three exit codes ("0 — all maintenance cadences current / 1 — one or more cadences
   overdue / **2 — could not determine (missing data)**"). **The script has exactly two `exit`
   sites: `exit 1` and `exit 0`. There is no `exit 2`** (§14-V13). v1.0 of this document repeated
   the docblock without executing it — the exact failure class §0.3 exists to catch, corrected
   here rather than quietly patched.

   **What actually happens to an undeterminable cadence, executed (§14-V13).** Each arm parses a
   date into `last_epoch` through `date -j -f … || date -d … || echo "0"`, then computes
   `days_since` only **inside** an `if [ "$last_epoch" -gt 0 ]` guard. So a date neither parser
   accepts yields `last_epoch=0`, the guard is false, and **the whole arm is skipped in silence** —
   no print, no `overdue` increment. Run against a fixture whose `CHANGELOG.md` has no git history
   and whose only `docs/test-results/` file is `2026-13-45_semgrep_pass.txt` (a string both
   parsers reject on this host, verified), the script prints one `[INFO] … cannot determine age`,
   prints **nothing at all** for the security arm, and reports **"All maintenance cadences
   current." at rc=0**.

   **This is fail-OPEN, and the direction matters.** An unreadable signal is currently
   indistinguishable from a fresh one. A reviewer of this design proposed the opposite
   mechanism — that an unparseable date falls through into a huge `days_since` and exits 1, a
   fail-*closed* collapse — and that is **refuted by the `-gt 0` guard and by the run above**.
   The distinction is load-bearing for D5: a *fail-closed* checker would over-block a release cut
   (annoying, safe); the *fail-open* one this repo actually ships would let `cut-release.sh` (§9.2)
   pass a cadence that was never really measured.

   **Design addition (author-proposed).** WP6 adds the advertised `exit 2` for real: any arm whose
   date is present-but-unparseable, or whose signal file is missing where the project's policy
   expects one, sets an `undetermined` counter; a non-zero `undetermined` with zero `overdue`
   exits **2** and prints which cadence could not be read. `cut-release.sh` treats **2 as a
   refusal**, not a pass — an unmeasurable cadence must not be silently satisfiable. The
   date-parsing portability (`date -j -f … || date -d …`, GNU-first fallback) is already right and
   stays untouched.
2. **The guide must move with it.** `docs/builders-guide.md` § Step 4.4 names four cadences in
   prose and puts the full dependency audit under *Biannually*. Leaving it is the doc/script split
   that C2 measured, one notch worse.
3. **The thresholds become policy, not constants.** They move to
   `delta-policy.json::cadence` (§7.2) and the script reads them, so a project on a slower cadence
   changes a config rather than forking a script.

**Two enforcement points (D5):**

- **At release cut — refuse if overdue.** `cut-release.sh` runs the checker and refuses on exit 1
  **and on the new exit 2** (§9.2) — overdue and unmeasurable are both refusals. This is the
  mechanical half.
- **At session start — nag.** A new arm reports overdue cadences once. The house contract for
  SessionStart hooks is *silent when nothing is wrong, fail-open, zero-network*: `init.sh` already
  registers `session-version-check.sh`, `session-test-gate-check.sh`,
  `session-freshness-check.sh`, `session-intake-check.sh`, and `detect-out-of-band-commits.sh`
  into `.hooks.SessionStart` by idempotent `jq` merge, and the new arm joins that family rather
  than inventing a mechanism.

**This is the wiring D5 asks for.** C1: the script ships (`init.sh` copies it and `chmod +x`s it);
what is missing is any caller. After this, it has two.

---

## §9 — Release: `scripts/cut-release.sh` (D6)

### §9.1 — Semver, decided by the tool

D6 is unambiguous: **the tool decides, and there is no override path in v1.**

| Input, from `delta-state.json::closed` since the last tag | Bump |
|---|---|
| Any `breaking` marker | **major** — plus the §8.2 full revalidation |
| Else any `feature` | **minor** |
| Else (fix / hotfix / security-patch only) | **patch** |
| Nothing closed since the last tag | **refuse** — nothing to release |

The map lives in `delta-policy.json::semver` so a project can retune the class→bump mapping; the
**precedence order** above is machinery and is not configurable, because a project that could
reorder it could make a feature release a patch.

**No override, and what that costs.** An operator who disagrees with the computed bump has no
flag in v1. That is the decision. The honest cost is a real one — a "0.x" project that wants
every release to be a minor, or a marketing-driven major, has to change the class of what it
shipped or edit the tag by hand outside the tool. §13-R2 records it and Q1 asks the reviewer
whether it should stay.

### §9.2 — The three refusals, and their order (author-proposed order)

D6 fixes the refusals. The order is author-proposed and chosen so the cheapest, clearest refusal
speaks first:

1. **Open delta** — `active_delta != null`. "Finish or abandon DELTA-NNN first." Instant, no I/O.
2. **Open hotfix retro** — any `hotfix_retros[]` with `closed_at == null`. Names the delta, its
   `due_by`, and how overdue it is. This is D3's collateral being called in.
3. **Overdue or unmeasurable cadence** — `check-maintenance.sh` exit 1 **or the new exit 2**
   (§8.3's author-proposed addition). Names each overdue or undetermined cadence and its
   remediation (§8.3).

Each refusal exits non-zero and prints exactly what would clear it. **`cut-release.sh` performs no
write of any kind before all three pass** — a partially-cut release (changelog promoted, tag
absent) is a worse state than a refused one.

### §9.3 — Promotion and tag — and the constraint C7 forces

**Promotion.** `templates/generated/changelog.tmpl` ships `## [Unreleased]` with eight fixed
category headings (Security, Data Model, Added, Changed, Fixed, Removed, Infrastructure,
Documentation). The cut renames the `## [Unreleased]` heading to `## [X.Y.Z] — YYYY-MM-DD` and
inserts a fresh empty `## [Unreleased]` block above it with the same eight headings. Categories
are preserved verbatim; the tool writes no prose.

**Tag format is constrained, not chosen (C7).** GitHub and Bitbucket release lanes match `v*`;
**GitLab matches `/^v\d+\.\d+\.\d+$/`**. So v1 emits **exactly** `vMAJOR.MINOR.PATCH` — no
pre-release suffix, no two-component tag. A `v1.2.0-rc1` would build on two hosts and silently do
nothing on the third, which is the worst available failure mode: green on the host you tested.
Pre-release tags are §13-R3.

**Then the lanes fire as-is** (D6) — verified: all twelve release templates trigger on a tag push
and need no change.

---

## §10 — Era routing (D7)

### §10.1 — The invariant

**`active_delta != null ⇒ current_phase == 4`.**

Enforced at two points (author-proposed placement, the invariant itself is D7):

- **At open**, in the seam: `delta.sh --open` refuses unless `phase-state.json::current_phase`
  is exactly 4. This is the load-bearing one — it is what makes the delta track unable to
  substitute for building the product properly.
- **As a validator assertion**, in `scripts/validate.sh`, which already reads
  `phase-state.json::current_phase` and already warns on a phase/artifact mismatch. An
  `active_delta` at phase < 4 is that same class of inconsistency and belongs in that same report.

**Read the `[WARN]` trap before implementing either.** In `check-phase-gate.sh` the `[WARN]` vs
`[FAIL]` text is cosmetic — the exit predicate is `if [ $issues -eq 0 ]`, so a "WARN" arm that
increments `issues` blocks the gate and a genuinely non-blocking WARN must omit the increment.
Whichever label the invariant arm prints, **the mutation proof must assert the exit code**, never
the label.

### §10.2 — No phase re-entrancy

D7: `current_phase` stays 4. The framework already guarantees the monotonic half —
`process-checklist.sh::_set_current_phase_min` carries the comment "**Never downgrades** — if the
user is already past N … the value is left alone", and its body only writes when
`[ "$cur" -lt "$target" ]`.

So the delta track needs **no** new machinery for monotonicity; it needs only to **not add** a
downgrade path. §11-WP7's severability test covers it: no delta-module file may write
`current_phase` at all.

### §10.3 — The `feat:` predicate is untouched, and pinned FIRST

D7 requires the `feat:`-requires-Build-Loop predicate be untouched and **test-pinned first**.
C3 determines *which* predicate:

- **`process-checklist.sh::check_commit_message`** — gates at `current_phase ≥ 2`, **fires at
  phase 4**. Verified by execution: phase-4 fixture, no active Build Loop,
  `--check-commit-message "feat: add dark mode"` → **rc=1** with "no Build Loop active"
  (§14-V4). **This is the pin target.**
- `check_commit_ready` — the file-heuristic path, `[ "$current_phase" -eq 2 ]`, inert at phase 4.
  A pin written here would pass vacuously and prove nothing.

**Consequence for the design.** The FEATURE class's `build_loop` gate (§5.2) needs **no new
enforcement**: a `feat:` commit at phase 4 already demands an active, five-step-complete Build
Loop, at commit-msg time, in every generated project. The delta track's job is to *start* the
Build Loop when a feature delta opens — not to re-implement the gate.

WP0 pins this before any delta code is written, so a later regression is attributed to the change
that caused it. The mutation: neuter the `current_phase -lt 2 → exit 0` guard to `-lt 5` (making
the gate inert at phase 4) → the phase-4 test must go RED.

### §10.4 — The bridge at v1.0

D7: at v1.0 the manifesto's Post-MVP Backlog seeds the delta queue.

`templates/generated/product-manifesto.tmpl` § 5 *MVP Cutline* is a hard line — "Features listed
above this line ship first. Everything below this line goes to the Post-MVP Backlog… Do not move
items above the line without Orchestrator approval and a recorded decision" — and § 6 *Post-MVP
Backlog* holds the below-the-line items, with its own instruction: "Items here are candidates, not
commitments… Each item: what it is, and what user signal would justify building it."

**The seeding is a read, not a move (author-proposed mechanics).** § 6 items become *candidate*
deltas, listed by `delta.sh --status` when no delta is open. Nothing is auto-opened, nothing is
deleted from the manifesto, and the cutline governance is untouched — because § 6's own text says
these are candidates prioritised "after launch based on real usage data", and auto-promoting them
into a queue would contradict the document being read. The "what user signal would justify
building it" clause is the brief's **Why** field (§6.2) already written, which is why the bridge
is cheap.

### §10.5 — The ambient branch (session greeting and `resume.sh`)

D7 adds a delta-aware branch to the session-start greeting and `resume.sh`. D8 explains why this
is the important one: today's bug/feature workflow instructions are **retrieval surfaces** — the
guide and the ledger headers — correct and unread at the moment of need.

`scripts/resume.sh` is already the **single** first-message generator with three state-aware
branches (`# BL-202-INTAKE-PREDICATE`): intake unfinished → the intake first-message; intake done
and Phase 0 not started → the project's own § 13 prompt verbatim; anything else → the classic
resume prompt. The delta branch is a **fourth**, ahead of the classic one:

- `current_phase == 4` **and** `active_delta != null` → resume *that delta*: its id, class,
  confirmed attributes, and the outstanding entries of `gates_required` minus `gates_completed`.
- `current_phase == 4` **and** `active_delta == null` → the post-1.0 greeting: how to state a
  need in plain words, any overdue cadence, any open hotfix retro, and the § 6 candidate count.

**Honest tier: advisory.** A greeting cannot make anyone do anything. What it changes is *when*
the operator learns the rule — before they act rather than after — and that is the whole of D8's
point.

---

## §11 — Build plan (ordered work packages)

Every WP goes through adversarial acceptance. "Mutation-provable" means the RED-under-neuter →
GREEN-restored proof this framework requires of enforcement code. Every new `tests/test-*.sh`
registers in `tests/full-project-test-suite.sh` **and**, unless its executed lines name `init.sh`,
in the `tests.yml` unit list.

| WP | Scope | Test intent · mutation proof |
|---|---|---|
| **WP0 — Pin the inherited predicates. FIRST, before any delta code.** Three pins: (a) `check_commit_message` blocks a `feat:` with no Build Loop **at `current_phase: 4`** (C3 — the pin target, not `check_commit_ready`); (b) `check_phase_gate` exits 1 on `SEV-1.*Open`, `SEV-2.*Open`, and `SEV-2.*Deferred`; (c) `_set_current_phase_min` never downgrades. | Phase-4 fixtures for all three. **Mutations:** (a) widen the `current_phase -lt 2` guard to `-lt 5` → the phase-4 feat test goes RED; (b) drop the `sev2_deferred` arm → the deferred fixture passes → RED; (c) invert `[ "$cur" -lt "$target" ]` → a 4→2 downgrade succeeds → RED |
| **WP1 — The boundary lint, on day one (D1).** `scripts/lint-delta-boundary.sh` per §3.3, plus the first `scripts/lib/delta-state.sh` stub so the vacuity floor has something to find. New CI job in `lint.yml`; `run-lints.sh` picks it up by glob, no wiring | Core→delta reference detected; delta→core ignored; comment-only mentions ignored in **both** spellings at **both** widths; empty DELTA set exits 2 not 0. **Mutations:** add `source lib/delta-state.sh` to a core script → RED; add a second seam-allowlist entry → RED on the cardinality assertion; point the DELTA manifest at nothing → **exit 2**, not 0 |
| **WP2 — State + policy schemas.** `.claude/delta-state.json` (§7.1) and `.claude/delta-policy.json` (§7.2); `delta-state.sh` / `delta-policy.sh`; the seam's `--delta-*` actions in `process-checklist.sh`; policy defaults fall back per-key at read time; `# BL-099-DOC-GUARD`-form NOTICE-ONLY treatment in `upgrade-project.sh` | Atomic tmp+mv write; a partial write leaves the old file intact; an absent policy key resolves to the framework default; `upgrade-project.sh` never writes `delta-policy.json` under **any** flag combination. **Mutation:** make the upgrade path write the policy file → the never-overwrite test goes RED |
| **WP3 — Era invariant + classification.** The `active_delta ⇒ current_phase == 4` refusal at open, the `validate.sh` assertion, `delta-classify.sh`'s three derivations, and the confirm-not-quiz transcript (§4.3) on the `# BL-204-PREFILL` pattern | Open refused at phases 0–3, allowed at 4; risk/level/severity derive from a fixture diff; a raise sticks and a lower is refused (or reason-recorded). **Mutation:** neuter the phase refusal → an open at phase 2 succeeds → RED, **asserted on the exit code, not the printed label** (the `[WARN]` trap) |
| **WP4 — Per-class gates + the rubric bind.** `gates_required` materialised at open from class + attributes; the close gate reads the brief's done-observable section and refuses an unchecked criterion; attribute re-derivation at close ratchets and appends gates | Each class yields its §5.2 row; `risk: core` adds `brief_review`; `level: evolution` adds `brief`; a delta that grows past a threshold gains the gate at close. **Mutation:** drop the close-time re-derivation → a delta opened `small` and grown to `evolution` closes on the small checklist → RED |
| **WP5 — Hotfix lane + retro ledger.** Fast lane on the floor, audit row at open, `hotfix_retros[]` with `due_by = shipped_at + retro_due_days`, retro close | A hotfix ships with only floor gates; the retro row is written at **open**, not at close; an open retro survives its delta's close. **Mutation:** suppress the retro-row append → a hotfix ships with no retro obligation → RED |
| **WP6 — Cadence: wire the orphan (D5).** Thresholds in `check-maintenance.sh` move to `delta-policy.json::cadence` and retune (35→14, 185→95, dependency audit folded); the SessionStart nag arm; `docs/builders-guide.md` § Step 4.4 reconciled; a `DELTA-NNN` row in `identifiers.tmpl` | Overdue at 15 days, current at 13. **Exit contract (R-DT-1): the script today exits only 0 or 1 — WP6 ADDS `exit 2`** for present-but-unparseable dates and policy-expected-but-missing signals, so the tests are: an overdue arm → 1; an unparseable-date arm (`2026-13-45_semgrep_pass.txt`) → **2, and no longer the silent rc=0 of §14-V13**; all-current → 0. Hook arm: silent when current, exits 0 on a forced internal crash, makes no network call. **Mutations:** revert one threshold to 35 → the 15-day fixture passes → RED; **remove the new `undetermined` counter → the unparseable fixture reports "All maintenance cadences current" at rc=0 → RED** (this is the mutation that pins the fail-open repair, and it must assert the *exit code*, not the printed text) |
| **WP7 — `cut-release.sh` + severability test (D6).** The three refusals in §9.2's order, semver computation, changelog promotion, `vMAJOR.MINOR.PATCH` tag (C7), major ⇒ full `run-phase3-validation.sh`. Plus the **severability test**: delete every §3.1 file and revert the seam → the full suite passes | Each refusal fires alone and in combination and **writes nothing**; a feature+fix set yields minor; fixes only yield patch; a breaking marker yields major **and** triggers revalidation; the tag matches `/^v\d+\.\d+\.\d+$/`. **Mutations:** suppress the open-retro refusal → a release cuts with a retro outstanding → RED; emit `v1.2.0-rc1` → the tag-format test goes RED (the C7 defence); delete a delta-module file → the severability test still passes, but **removing the seam revert** → RED |
| **WP8 — Intake paths + brief template (D4).** `delta-brief.tmpl`; `delta.sh --open` (guided); the `resume.sh` fourth branch and the session greeting (§10.5); the § 6 candidate read (§10.4) | All three paths produce identical state; the `resume.sh` branch fires only at phase 4 and only in the two §10.5 sub-cases; the manifesto is never modified by the bridge. **Mutation:** make the bridge write to `PRODUCT_MANIFESTO.md` → RED |
| **WP9 — Docs.** `docs/INDEX.md` row (this branch), builders-guide § Step 4.4 reconciliation (with WP6), a delta-track section in the generated `CLAUDE.md`, `docs/user-guide.md` | `lint-doc-anchors.sh --strict-refs`, `lint-backlog-references.sh`, and `lint-bl-markers.sh` clean; no new dead refs |

**Sequencing.** **WP0 → WP1** (both are gates on everything after them: WP0 proves the inherited
predicates still hold, WP1 makes the boundary red-checkable before there is a boundary to
violate) → WP2 → WP3/WP4 → WP5/WP6 → WP7 → WP8 → WP9.

**The linchpins are WP1, WP3, and WP7.** WP1 is the only thing standing between "severable module"
and "a folder of files that happens to be named delta". WP3 owns the invariant that keeps the
delta track from becoming an escape hatch out of Phases 0–3. WP7 is where a bug ships a wrong
version number or a release cuts over an open retro. All three get top-tier implementation and
double-mutation verification.

---

## §12 — Non-goals and rejected alternatives

- **A plugin socket — rejected on any schedule (D1, settled).** The family extensibility model is
  **fork-and-PR**. Worth stating the strongest counter-argument and answering it: a socket would
  let sister products add classes without touching this repo. The answer is that a socket is a
  *frozen interface* published before there is a second consumer to shape it, and this repo's own
  history says an interface designed for a hypothetical consumer is designed wrong. A fork can
  diverge and a PR can converge; a socket can only be regretted.
- **A phase 5 — rejected (D7, settled).** `current_phase` stays 4. A phase 5 would make the
  monotonic advance meaningful again, which would make "am I in maintenance?" a question with a
  wrong answer available.
- **Multiple concurrent deltas — out of scope for v1 (D7, settled).** §13-R1.
- **A semver override flag — out of scope for v1 (D6, settled).** §13-R2, Q1.
- **A second config file for state and policy combined** — rejected (§7). The two have different
  owners and different sync behaviour; merging them would force one rule on both, and the rule
  that lost would be "never overwritten".
- **Re-implementing the floor inside the delta module** — rejected (§5.1). gitleaks, semgrep,
  project tests, and TDD ordering are already blocking arms in the generated pre-commit hook. A
  second copy is a second thing to drift.
- **A fix-counting arm on the UAT batch counter** — rejected (§5.4, C6). The counter counts
  features by construction and D8 records the consequence as intended behaviour.
- **A new column in `BUGS.md`** — rejected (§6.3). The table is script-parsed and its own header
  forbids format changes. The delta link rides the existing `Fix Reference` column.
- **Wiring `--finalize-phase 4` into `cut-release.sh`** — **not decided, therefore not designed**
  (C8, Q3). It is the obvious pre-tag aggregate check and it is a second orphan. Flagged, not
  assumed.
- **An external scheduler for the cadence** — rejected (§8.3). The two enforcement points are a
  release-cut refusal and a session-start nag, both in-repo and zero-network, matching the house
  contract for every SessionStart hook the framework ships.

---

## §13 — Honest residuals

**Deferred by decision (named, scoped, not designed here):**

1. **Concurrent deltas.** One at a time is D7 and is encoded structurally in §7.1's schema. A
   second concurrent delta would need a queue, a per-delta gate ledger, and an ordering rule for
   the release cut. The schema change is small; the *semantics* change is not, and none of it is
   designed here.
2. **A semver override.** D6 gives the tool the last word with no flag. A project that
   deliberately versions on a different scheme (marketing majors, permanent `0.x`) has no
   supported path in v1 except changing what it shipped. Q1.
3. **Pre-release and channel tags.** C7's GitLab constraint forces exactly
   `vMAJOR.MINOR.PATCH`. `-rc1`, `-beta`, and any channel scheme are out of v1 and would require
   the GitLab lane's `rules:` regex to change first — a template edit in a file the release
   pipeline depends on, and therefore its own work package.
4. **The quality of `risk_surfaces`.** The touch trigger is only as good as a glob list the
   project authors (§7.2). It ships empty, which makes every delta `feature-local` until someone
   fills it. The session-start branch surfaces the emptiness; nothing can compute the right list.
5. **The two retro clocks.** `templates/generated/incident-response.tmpl` requires a post-incident
   review within **48 hours**; D3 requires the code retro within **3 days**. Both are readable from
   `delta-policy.json`, and this design deliberately does **not** reconcile them — they govern
   different artifacts and a project may legitimately want them different.
6. **`delta-policy.json` drift.** NOTICE-ONLY (§3.2) means a project can sit on stale defaults
   indefinitely. The upgrade notice names new keys; nothing enforces adoption. This is the
   deliberate cost of the mechanism/policy split, not an oversight.
7. **The bug gate's stale phase wording (C5).** `scripts/test-gate.sh::check_phase_gate` fires at
   `current_phase ≥ 3` and therefore blocks in the delta era, but every string it prints still
   says "before Phase 3" — `[FAIL] SEV-1 bugs open: N (BLOCKED — must resolve before Phase 3)`,
   and `check-phase-gate.sh`'s own summary line likewise. At phase 4 that instruction is
   unfollowable: there is no Phase 3 to be before. The **behaviour** is right and the delta track
   depends on it (§5.4); only the wording is wrong. Left alone deliberately — retuning gate strings
   is a product-code edit, this is a docs-only work package, and the correct owner is a backlog
   entry rather than a design document. Named here so the next reader does not mistake the stale
   text for stale behaviour.

**Cannot be known before real use:**

8. **Whether 14 days is the right routine cadence.** D5 says "tightened… for now" in as many
   words. It is a judgment about how fast a solo-maintained project rots, and the first project to
   miss it three times running is the evidence. The threshold is policy (§7.2) precisely so
   changing it costs nothing.
9. **Whether one question is genuinely enough.** §4.3's transcript asks one thing and confirms
   four. If the class proposal is wrong often enough, the confirm step becomes the quiz D2
   rejected — and the fix would be better phrase→class heuristics, not a second question.
10. **Whether the hotfix loan gets repaid.** The 3-day retro is collateralised by the release
    refusal (§9.2). If a project simply stops cutting releases, the debt sits uncollected. The
    session nag is the only other pressure, and it is advisory.
11. **Whether the brief-as-rubric bind holds up.** D3's strongest idea is untested here. If briefs
    are written vaguely, the close review inherits the vagueness and the mechanical part of §5.3
    becomes ceremonial.

**Assumptions that would falsify parts of this design if wrong:**

12. **That `check_commit_message` stays the phase-≥2 surface.** §10.3's entire "no new gate needed
    for the feature class" argument rests on C3. WP0 pins it; if a future change makes that
    predicate phase-2-only, the feature class silently loses its Build Loop requirement in the
    delta era. **That is the single most load-bearing verified fact in this document.**
13. **That every generated project's CI runs `check-phase-gate.sh`.** C5's "SEV enforcement
    carries into the delta era" depends on it. Measured today: **all ten** GitHub CI templates and
    the GitLab set. A project that hand-edited its pipeline has no SEV block at phase 4 and
    nothing tells it so.
14. **That `check-maintenance.sh`'s signals mean what their filenames say.** Two of its four
    thresholds read **dates parsed out of filenames** in `docs/test-results/` (`*snyk*`, `*dep*`,
    `*audit*`, `*semgrep*`, `*sast*`). A file named with a date and containing nothing satisfies
    the cadence completely. Tightening 185→95 makes the *clock* stricter without making the
    *evidence* stronger — recorded here rather than sold as a security improvement. **§14-V13
    shows the sharper edge of the same assumption:** a filename whose date no parser accepts is
    currently skipped in silence and reported as current, which is why WP6 adds `exit 2` (§8.3).
15. **That a grep-based boundary lint can see every core→delta reference (R-DT-6).** §3.3's T2
    tier catches the variable-composition family because such references still carry the literal
    `delta-` prefix. A reference composed *below* that boundary — a path assembled from a variable
    holding `delta`, or a split string literal — evades both tiers, and no lexical lint can close
    that. The backstop is behavioural, not lexical: WP7's severability test (delete the module,
    revert the seam, suite must pass) fails on a fused module however the fusion was spelled.

---

## Self-review pass (fresh-eyes checklist)

- **Every commissioned element present?** §0 traceability with per-decision attribution to Karl's
  2026-08-02 joint session (§0.1); plain-English opening; the `delta-state.json` schema, marked
  author-proposed (§7.1); the policy config schema (§7.2); the dependency-direction lint spec
  (§3.3); the per-class gate-subset table (§5.2); the WP build plan with mutation-proof intents
  and the `feat:`-predicate pin **first** (§11-WP0); honest residuals (§13); and the executed
  verification log (§14).
- **Are the settled decisions designed within, not relitigated?** Yes. D1–D8 appear in §0.1 as
  premises, each with the author freedom taken stated explicitly beside it. Where the repository
  corrected the *framing* (C1–C11), the correction is flagged in §0.3 and designed for. **No
  settled decision is contradicted by any repo fact found.** Two came close and did not: C3 refines
  which surface D7's "phase >= 2" names, and C10 shows D1's seam and D7's single writer are the
  same edge rather than two.
- **Every "exists today" claim executed, not reasoned?** Yes — §14 logs 12 verifications
  including four live fixture runs (the SEV-1 block, the SEV-2-deferred block, the phase-4 `feat:`
  block, and the phase-4 bug-gate arm). Five printed claims changed as a result. The claims most
  worth attacking are the ones that came *from* execution and could still be
  environment-specific: §14-V5's CI reach depends on the scaffolded pipeline being unmodified
  (§13-R13). **v1.1 note:** review-r1 refuted one printed claim that had *not* been executed —
  `check-maintenance.sh`'s exit contract, copied from its docblock (R-DT-1). One docblock-trust
  defect survived a document whose §14 logs twelve runs; the corrected claim at §8.3 and §14-V13
  is now executed, and so is the reviewer's own proposed replacement mechanism, which the run
  refuted in turn.
- **Is enforcement honestly tiered?** Yes. §5.3 marks the downstream reviewer **advisory** and
  says generated projects receive a prompt library, not an agent. §5.4 refuses the queue-interrupt
  claim and names what actually exists. §10.5 marks the greeting advisory. §13-R14 refuses to sell
  a threshold tightening as an evidence improvement, and §13-R15 refuses to claim the boundary
  lint is complete.
- **Unresolved placeholders?** None. Every underdetermined choice is either a decision table with
  one recommendation and stated alternatives (policy-file sync semantics §3.2; refusal order §9.2;
  bridge mechanics §10.4) or is named in §13 as an explicit deferral.
- **Biggest attack surface for the reviewer.** (a) §10.3 — the whole "no new gate for the feature
  class" argument rests on one executed fact, and §13-R12 says so. (b) §4.2 — lines-changed is a
  weak size proxy and the design admits it rather than defending it. (c) §9.1 — no semver override
  is a decision, and a reviewer may reasonably argue it is the wrong one; Q1 asks.

---

## Questions flagged for the adversarial reviewer

1. **The no-override semver (D6).** The tool decides and there is no flag. Is that right for v1, or
   should there be an **attested** override — a flag that records a reason into
   `delta-state.json::closed[]` rather than silently allowing a different bump? The attested form
   would match `# BL-072-TDD-ENFORCE`'s "recorded, not silenced" posture, which is the house
   pattern for exactly this shape of exception.
2. **Where the era invariant is enforced.** §10.1 puts the hard refusal in the seam at open and a
   report-only assertion in `validate.sh`. Should `check-phase-gate.sh` also carry it? Argument
   against: it is a phase-*transition* tool and the delta track has no transition. Argument for:
   it is the tool CI runs, so it is the only place the invariant gets checked without an operator.
3. **`--finalize-phase 4` (C8).** It is invoked by nothing, its own comment says CI "may" invoke it
   on tag push, and `cut-release.sh` is now exactly that caller. Karl did not decide to wire it, so
   this design does not. Should it be WP7 scope, or its own backlog entry?
4. **The 14-day routine cadence against a filename-derived signal (§13-R14).** Two of the four
   thresholds read dates out of filenames in `docs/test-results/`. Tightening the clock does not
   strengthen the evidence. Is the right v1 move to tighten the clock as decided and log the
   evidence weakness, or to tighten the clock *and* add a minimum-content check to the two
   filename-derived arms?
5. **Ratcheting attributes (§4.2).** Raise-only, re-derived at close. Is raise-only too rigid —
   should a *lower* be allowed with a recorded reason, the way the framework treats other
   attested exceptions? The risk of allowing it is that the lower always happens under deadline.
6. **The brief-as-rubric bind (§5.3).** The close gate refuses on an unchecked done-observable
   criterion. That makes the operator's own writing quality load-bearing on a mechanical gate.
   Is that the right amount of mechanism, or should the gate require only that every criterion be
   *addressed* (checked or explicitly waived with a reason) rather than *satisfied*?
7. **Severability as a test (§3.1, WP7).** "Delete every module file, revert the seam, suite still
   passes" is the strongest form and also the most expensive to keep green. Is it worth a
   standing test, or is the boundary lint (§3.3) sufficient on its own?

---

## §14 — Verification log (executed 2026-08-02)

Every row was run against this tree before the corresponding claim was printed. Fixtures live
outside the repo. Recipes over line numbers, per the house citation rule.

| # | Claim | Command | Observed |
|---|---|---|---|
| **V1** | `check-maintenance.sh` is shipped by `init.sh` and invoked by nothing | `grep -n 'check-maintenance' init.sh` · `grep -rn 'check-maintenance' .github/ templates/ scripts/hooks/` | init.sh: a `cp "$SCRIPT_DIR/scripts/check-maintenance.sh" scripts/` line plus membership in the `chmod +x` list. Second grep: **no output, rc=1** |
| **V2** | SEV-1 Open blocks the bug gate at rc=1 | fixture `BUGS.md` with one `SEV-1 \| Open` row; `bash scripts/test-gate.sh --check-phase-gate` (PATH-shadowed `gh` so the arm is hermetic) | `[FAIL] SEV-1 bugs open: 1 (BLOCKED …)`; `[FAIL] Phase 2→3 transition BLOCKED`; **rc=1** |
| **V3** | SEV-2 **Deferred** blocks at rc=1 | same fixture, row changed to `SEV-2 \| Deferred` | `[FAIL] SEV-2 bugs deferred: 1 (BLOCKED — must resolve or remove/hide feature)`; **rc=1** |
| **V4** | The `feat:` Build-Loop gate fires **at phase 4** | fixture `.claude/phase-state.json` `{"current_phase": 4}`; `bash scripts/process-checklist.sh --check-commit-message "feat: add dark mode"` | `[FAIL] pre-commit gate: 'feat(...)' commit blocked — no Build Loop active.`; **rc=1**. Control: `--check-commit-message "fix: export crashes on unicode"` → **rc=0** |
| **V5** | The bug gate arm runs at phase 4 from `check-phase-gate.sh`, and all scaffolded CI runs it | phase-4 fixture + `APPROVAL_LOG.md` + `SEV-1 \| Open`; `bash scripts/check-phase-gate.sh` · `grep -l 'check-phase-gate' templates/pipelines/ci/github/*.yml \| wc -l` | Output contains `Bug Gate Check` → `[FAIL] SEV-1 bugs open: 1` → `[FAIL] Bug gate BLOCKED`, counted into the blocking total (rc=1). **10 of 10** GitHub CI templates match |
| **V6** | `_set_current_phase_min` never downgrades | read the function in `scripts/process-checklist.sh` | Comment: "Never downgrades — if the user is already past N … the value is left alone"; body writes only under `[ "$cur" -lt "$target" ]` |
| **V7** | Release lanes are tag-triggered; GitLab is version-**strict** | `grep -n -A6 '^on:' templates/pipelines/release/github/*.yml` · `grep -n 'CI_COMMIT_TAG' templates/pipelines/release/gitlab/*.yml` · `grep -n "'v\*'" templates/pipelines/release/bitbucket/*.yml` | GitHub 4/4 `tags: ['v*']`; Bitbucket 4/4 `'v*'`; **GitLab 4/4 `/^v\d+\.\d+\.\d+$/`** |
| **V8** | `--finalize-phase` is invoked by nothing | `grep -rn 'finalize-phase' --include='*.yml' --include='*.sh' --include='*.tmpl' --include='*.json' .` (minus `Reports/`, `docs/`) | Only `scripts/process-checklist.sh` (parser, dispatch, comments, error strings) and `tests/test-phase-finalize.sh` |
| **V9** | `process-state.json` has four writers | `grep -rn 'process-state.json' scripts/ init.sh templates/ \| grep -E '>\|mv \|cat >'` | Write sites in `process-checklist.sh`, `check-gate.sh`, `session-intake-check.sh`, and `pre-commit-gate.sh::tdd_record_attestation` |
| **V10** | The floor arms and the TDD trigger | read `# BL-163-BLOCKED-LEDGER` in `scripts/lib/hook-templates.sh`; read `_tdd_triggers` in `scripts/pre-commit-gate.sh` | Blocking arms named gitleaks / semgrep / project-tests; `_tdd_triggers` matches `^(feat\|fix\|refactor)(\([^)]*\))?!?:` with **no** `current_phase` read |
| **V11** | Nothing of the delta track exists | `grep -rl 'delta-state\|delta_state\|cut-release\|docs/deltas' .` (minus `.git/`) · `ls docs/deltas scripts/cut-release.sh` | grep: **no matches**. `ls`: "No such file or directory" for both |
| **V12** | `init.sh` ships no `.claude/agents/`; it does ship the review prompt library | `grep -c 'claude/agents' init.sh` · `grep -n 'evaluation-prompts' init.sh` · `ls evaluation-prompts/Projects/` | **0**; a `cp -r evaluation-prompts/Projects/*` arm; `bases/ compose.sh modules/ README.md run-reviews.sh` |

**Added at v1.1 (review-r1):**

| # | Claim | Command | Observed |
|---|---|---|---|
| **V13** | `check-maintenance.sh` has **no `exit 2`**, and an undeterminable cadence is silently skipped and reported as **current** (fail-open) — refuting both v1.0's docblock-trusted "0/1/2" claim **and** the reviewer's proposed fail-closed mechanism | `grep -n '^\s*exit ' scripts/check-maintenance.sh` · `date -j -f "%Y-%m-%d" "2026-13-45" +%s` · `date -d "2026-13-45" +%s` · fixture: git repo with an **untracked** `CHANGELOG.md` and `docs/test-results/2026-13-45_semgrep_pass.txt`, then `bash scripts/check-maintenance.sh` | Exit sites: **`exit 1`, `exit 0`** — two, no `exit 2`. Both date parsers reject `2026-13-45` (`Failed conversion…` / `illegal option -- d`), so `last_epoch=0` and the `[ "$last_epoch" -gt 0 ]` guard skips the arm. Script output: `[INFO] CHANGELOG.md has no git history — cannot determine age`, **nothing at all for the security arm**, `All maintenance cadences current.` — **rc=0** |
| **V14** | `get_steps_for_process` accepts **six** keys, not five | `awk '/^get_steps_for_process\(\) \{/,/^\}/' scripts/process-checklist.sh \| grep -cE '^[[:space:]]+[a-z][a-z0-9_]+\)'` (the extractor `invariant_check` itself uses) · same pipe without `-c` · `grep -c '^\s*_set_current_phase_min [0-9]' scripts/process-checklist.sh` | **6** — `phase1_architecture`, `build_loop`, `uat_session`, `phase3_validation`, `phase4_release`, `phase2_init`. The companion `_set_current_phase_min` call-site count re-derived as **5** (unchanged) |

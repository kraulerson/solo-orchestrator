# Kickoff prompt — autonomous remediation of the Dogfood-2 backlog

> Paste everything below the line into a fresh Claude Code session started in the
> framework repo (`/Users/karl/Documents/Claude Projects/solo-orchestrator`).
> It is self-contained: it tells the agent what to read, what to fix, in what
> order, how to prove each fix, and where to stop.

---

You are working in the **Solo Orchestrator framework repo** at
`/Users/karl/Documents/Claude Projects/solo-orchestrator` (note the space in the
path — quote every path in every command). This repo GENERATES downstream
projects; its gate scripts are the framework's product. A bad change here
propagates to every project it scaffolds, so precision matters more than speed.

## Your mission

Autonomously correct the open backlog, **highest-severity first**, following the
runbook that already exists on disk. Every fix is test-driven and
**mutation-proven** (you must watch the test fail against the current code, then
pass after your fix). You keep `main` green at all times. You do the full
implementation — branch, failing test, fix, mutation proof, lints, PR — and you
stop before the large design-features and before anything that needs a human
decision.

## Read first, in this order (do not skip)

1. **`CLAUDE.md`** (repo root) — environment traps and the "ENFORCEMENT — SOURCE
   OF TRUTH" section. Two things you must internalize:
   - **The `[WARN]` trap in `check-phase-gate.sh`:** the block/pass decision is
     `if [ $issues -eq 0 ]`. An arm that prints `[WARN]` *and* runs
     `issues=$((issues+1))` **BLOCKS**; a real non-blocking WARN omits the
     increment. Read the increment, not the label.
   - **The gate scripts are authoritative**; the prose guides describe them and
     may lag. Where a guide and a script disagree, the script wins and the
     disagreement is itself a bug to note.
2. **`Reports/2026-07-13-dogfood-2/REMEDIATION-PLAN.md`** — **this is your task
   list.** It sequences every open item into work packages (WP-A1 … Phase-H),
   each with the exact grep-able target, a reproduce command, the fix shape, and
   the mutation proof that is its definition of done. Follow its order.
3. **`Reports/2026-07-13-dogfood-2/FINDINGS.md`** — the 15 findings and how they
   map to backlog items. Read for context on *why* each fix matters.
4. **`solo-orchestrator-backlog.md`** — the canonical entries. The new findings
   are **BL-118 … BL-130** (plus an addendum on BL-114). The pre-existing open
   items are also in scope. Get the current open set with:
   `grep -n '\*\*Status:\*\* Open' solo-orchestrator-backlog.md`
   (that grep also surfaces a few preserved-audit `Open` lines inside Closed
   entries — verify the entry's top-of-block status before trusting one).
5. **`Reports/2026-07-13-dogfood-2/LEDGER.md`** — the raw step-by-step evidence
   (S-001…S-023). Consult it only when you need to confirm exactly how a finding
   reproduced.
6. **`CONTRIBUTING.md`** — the contributor setup you must complete (below).

## Setup (do once, before any fix)

- **Two repos are required.** Confirm the CDF checkout exists; clone if missing:
  `git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework`
- **Install the pre-commit gate hook** (contributors do this manually; `init.sh`
  does it only for generated projects):
  ```
  cp scripts/pre-commit-gate.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
  ```
- **Environment traps:** no `timeout`/`gtimeout` on this host (they yield a
  spurious rc=127 — never use them); `/bin/bash` is 3.2 (no `${var,,}`, no
  `declare -A`, no `nullglob`); the repo path contains a space.
- **Canonical verification commands:**
  - one suite: `bash tests/<file>.sh` (trust the **process exit code**, not the
    tally line)
  - all repo lints: `bash scripts/run-lints.sh` (~2 min; the two full-tree scans
    are slow, not hung — that is expected)
  - init.sh / scaffold changes: validate hermetically with
    `bash tests/full-project-test-suite.sh` and
    `bash tests/host-drivers/run-all.sh` — **never** by creating a real remote
    (`lint-no-live-remote-in-tests.sh` enforces this; a real `gh repo create` in
    a test is a house-rule violation).

## Step 0 — stabilize the base (do this first)

The findings docs and the BL-118…BL-130 backlog entries may be **uncommitted** in
the working tree. Do not build on shifting sand:

1. `git status --porcelain` — if `solo-orchestrator-backlog.md` and
   `Reports/2026-07-13-dogfood-2/` show as modified/untracked, they are the
   remediation base.
2. Create a base branch off `main` and commit them as a docs commit
   (`docs(backlog): log Dogfood-2 findings BL-118..130 + remediation plan`).
   Confirm the commit lands cleanly through the installed hooks (it is docs-only,
   so it bypasses the Build-Loop gate). Push it and open a PR, or keep it as the
   base your fix branches build on.
3. Re-run `bash scripts/run-lints.sh` — it must be green before you start fixing.
   (`lint-backlog-references.sh` and `lint-counter-antipattern.sh` are the two
   that most directly police your edits.)

## Ground rules — NON-NEGOTIABLE (you are fixing enforcement; never weaken it to pass)

1. **Never disable or route around a gate to make your own work pass.** No
   `--no-verify`, no `SOIF_PHASE_GATES=warn`, no `--ack-preconditions`, no
   `SKIP_LINT=1` to dodge a real failure, no hand-forged artifacts or
   attestations. If a gate blocks you legitimately, satisfy it.
2. **Never edit a test to make it pass. Fix the code.** The only exception is
   when the test *itself* is the documented bug (rare; the backlog entry will say
   so) — and then you rewrite the test to assert the correct behavior and
   mutation-prove the new assertion.
3. **Mutation proof for every enforcement change.** Break the marked line → run
   the test → see RED → restore → see GREEN. A gate "fixed" without a mutation
   proof is not fixed. This is the discipline whose absence let half these bugs
   ship.
4. **No merge on red, ever.** No `gh pr merge --admin`.
5. **Cite code by a grep-able `# BL-NNN-…` marker or a function name — never a
   bare `file:line`.** Add the marker as part of the fix.
6. **Register every new `tests/test-*.sh`** in BOTH
   `tests/full-project-test-suite.sh` AND the `unit` list in
   `.github/workflows/tests.yml` (`lint-tests-registered.sh` enforces).
7. **Portability: GNU-first then BSD.** Test on this macOS host. Never rely on
   GNU-only regex in `sed`/`grep` — that is literally BL-121.
8. **Hermetic tests only** — no real remote creation, ever.
9. **Do not modify the CDF repo** (`~/.claude-dev-framework`) unless a backlog
   entry explicitly directs an upstream CDF fix; it is a dependency you run.

## Scope — what to fix, what to flag, what to leave

**DO autonomously (Phases A–F of the remediation plan):** every gate/tooling/doc
fix. This is BL-118, BL-119, BL-120, BL-121, BL-122, BL-123, BL-124, BL-125,
BL-126, BL-127, BL-128, BL-129, BL-130, and the pre-existing gate bugs the plan
folds in (BL-102, BL-105, BL-106, BL-107, BL-108, BL-110, BL-111, BL-114 incl.
the F-DF2-003 addendum, BL-115, BL-116, BL-117, BL-095, BL-096). These are
well-specified with a reproduce command and a mutation proof.

**STOP and report — do NOT build blind (Phase G, large features):** BL-109
(Currency System), BL-089/090/091/092 (documentation-foundation quartet), BL-098,
BL-099, BL-100, BL-101, BL-097. For each, write a short design note
(problem, proposed shape, open questions, rough size) into the progress ledger
and leave the backlog entry Open. These need design/brainstorming and Karl's
direction, not a mechanical fix.

**LEAVE ALONE unless you are already editing that exact file for another fix
(Phase H, DEFERRED/opportunistic):** BL-019, BL-025, BL-042, BL-043, BL-085.
Their entries record a deliberate deferral; respect it. BL-087, BL-093, BL-094
are opportunistic — fold them in only when you are already in the relevant file.

**STOP and record a question (do not guess) if:** a fix needs a product/design
decision, a paid tier or external service, or the backlog "fix shape" is
genuinely ambiguous. Move on to the next item; surface the question in the final
report.

## The loop — per work package

Follow the plan's order. The plan's "suggested first week" is the correct
priority start: **WP-A1 (BL-118) → WP-A3 (BL-119) → WP-B1 (BL-121) → WP-A2
(BL-120, BL-125)**, then continue down the plan (B2 → B3 → C → D → E → F). Do the
security fixes before the others: a gate that reports "safe" on a real
vulnerability is the most dangerous state.

For each work package:

1. **Branch.** One branch per work package (or per phase for tightly-coupled
   items). Base it on the remediation base branch (or the previous phase's
   branch if you are stacking — note the dependency in the PR body). Branch name
   like `fix/bl118-sast-dom-xss`.
2. **Reproduce.** Run the plan's reproduce command; capture the exact output into
   the progress ledger. If you cannot reproduce it, do not "fix" it — record that
   and move on.
3. **Failing test first.** Write the test the plan's mutation proof describes.
   Run it; confirm it is **RED against the current code**, for the right reason
   (the bug, not a typo). Register it in both required lists.
4. **Fix**, behind a `# BL-NNN-…` marker comment. Minimal change that satisfies
   the test and matches the plan's fix shape.
5. **GREEN.** Test passes; the full affected suite passes; `run-lints.sh` passes.
6. **Mutation proof.** Break the marked line → the new test goes RED → restore →
   GREEN. Record both observations. This is your definition of done.
7. **Adversarially self-verify.** Before believing the fix, try to prove it wrong:
   is the test asserting real behavior or a tautology? Does the fix hold on the
   other sed/OS flavor (BL-121 class)? Does it handle the `--no-remote-creation`
   / hermetic path? For the highest-severity items (Phase A/B), spawn a
   verifier subagent (or a fresh reasoning pass) whose only job is to refute the
   fix; only accept it if the refutation fails. (This is the spirit of BL-100.)
8. **Update the backlog entry.** Only mark an item `Closed` when it has a real
   PR # or a backticked merge SHA to cite (`lint-backlog-references.sh` requires
   it, and never delete the entry — it is audit trail). If you are not merging
   (see policy below), leave it `Open` with a note: *"Fix on branch X / PR #Y —
   awaiting merge; mutation-proven."*
9. **Commit → push → open PR.** PR body: the finding, the fix, the mutation-proof
   evidence (RED→GREEN), and the tests added. Ensure the PR's CI (unit lane +
   lint jobs) goes green.

## Merge policy — read carefully

Default: **AUTO_MERGE = NO.** Do the complete implementation and open PRs, but do
**not** merge to `main`. This framework values independent review, and you cannot
independently review your own work. Leave the green PRs stacked for Karl to
merge.

If Karl has told you (in his kickoff message) **AUTO_MERGE = YES**, you may merge
a PR to `main` **only** when: its CI is green, it is a Phase A–F gate/tooling fix
(never a Phase G feature), and its mutation proof is recorded. Still no
`--admin`, still no merge on red.

## Progress ledger — write as you go, never batch at the end

Your context may be summarized mid-run. Maintain a running ledger at
`Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md`, appended after every work
package: the BL item(s), branch, PR #, the reproduce output, the RED→GREEN
mutation evidence, the adversarial-verify outcome, and status
(DONE-PR-open / MERGED / STOPPED-flagged / BLOCKED). This file is your memory and
your proof.

## Definition of done for the whole run

- Every Phase A–F item: either a green PR (mutation-proven, backlog updated) or a
  recorded BLOCKED/STOPPED with the exact reason.
- Every Phase G item: a short design note in the progress ledger; entry left Open.
- DEFERRED items untouched.
- `bash scripts/run-lints.sh` green, and the affected `tests/test-*.sh` green,
  on the final state of each branch.
- Framework repo otherwise byte-clean (no stray edits outside the intended
  changes).

## Final report (your last message)

Deliver:
1. **Fixed** — table of BL item → PR # → one-line fix → mutation-proof confirmed
   (yes/no) → merged or awaiting-merge.
2. **Stopped / flagged** — Phase G features and any ambiguous item, each with the
   specific question or decision Karl must make.
3. **Blocked** — anything you could not fix by legitimate means, with the full
   causal chain (a recorded BLOCKED is a valid outcome — never fake a fix).
4. **Verification** — the exact commands you ran to prove the framework is still
   green, with their output.
5. **Escape hatches used** — this must be ZERO. If it is not, say exactly why.
6. **Honest limits** — what you did not touch and why.

Use the `superpowers:test-driven-development` skill when writing each fix and
`superpowers:verification-before-completion` before any "done" claim. Assess and
state the model tier for any subagent you dispatch (verifiers ≥ implementers on
the risky Phase-A/B fixes).

Begin with Step 0, then WP-A1 (BL-118, the Critical SAST-blindness fix).

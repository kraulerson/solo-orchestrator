# CLAUDE.md — agent orientation for the solo-orchestrator repo

Read this first. It is the map for working effectively in THIS repository.
Counts are date-stamped (they drift); prefer the grep/command recipes — run them
to get current truth. Verified 2026-07-23.

## WHAT THIS REPO IS

This is the **framework repo that GENERATES downstream projects** — it is not
itself a scaffolded project. `init.sh` scaffolds a new project elsewhere; the
files a downstream agent reads at kickoff live in the GENERATED project, not
here.

- The README "Quick Start" kickoff prompt (README.md § Quick Start) tells the
  downstream agent to read `CLAUDE.md`, `PROJECT_INTAKE.md`,
  `docs/reference/builders-guide.md`, `docs/platform-modules/<platform>.md`, and
  `.claude/phase-state.json`. Those paths exist **in generated projects only** —
  the README even prefixes the block with "not in this framework repo".
- `init.sh` ships the guide downstream to `docs/reference/`: see the
  `cp "$SCRIPT_DIR/docs/builders-guide.md" docs/reference/` line (grep
  `builders-guide` in init.sh). In THIS repo the guide is **`docs/builders-guide.md`**
  (top level), and there is **no** `PROJECT_INTAKE.md` and **no**
  `.claude/phase-state.json`.
- **`docs/INDEX.md` is the documentation map** — a one-screen index of `docs/**`
  and `Reports/**`. Start there to find a doc.

## ENVIRONMENT TRAPS

- **No `timeout` / `gtimeout`** on this macOS host. Wrapping a command in them
  yields a spurious `rc=127` (command-not-found), not a real timeout. Do not use
  them.
- **The repo path contains a space** (`Claude Projects/…`). Quote every path in
  every command, always.
- **bash is 3.2** (`/bin/bash`, GNU bash 3.2.57). In product code: no `${var,,}`
  lowercasing, no associative arrays (`declare -A`), no `nullglob`. Use temp
  files / indexed arrays instead.
- **Two repos required.** Tests and `init.sh` need the Claude Dev Framework
  cloned at `~/.claude-dev-framework` (the path is hard-required). Per
  CONTRIBUTING.md:
  ```
  git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework
  ```
- **Install the gate hook yourself.** Contributors working on the framework
  install the pre-commit gate manually (init.sh does it for user projects, not
  here). Per CONTRIBUTING.md:
  ```
  cp scripts/pre-commit-gate.sh .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  ```

## CANONICAL COMMANDS

- **Run one suite:** `bash tests/<file>.sh`. Each suite prints a final tally
  line — most say `Results: N passed, M failed`, a few `== Total: … | Passed: …
  | Failed: … ==`. The reliable pass/fail signal is the process **exit code**.
- **Run every repo lint locally:** `bash scripts/run-lints.sh` (one PASS/FAIL
  line per lint, summary, non-zero exit iff any failed). This is the dev-tool
  wrapper — see LINT GOTCHAS.
- **CI fast lane (unit):** the explicit file list in the **`unit-shard`** job of
  `.github/workflows/tests.yml` (BL-190 renamed the job; it was `unit`). A test
  belongs there iff it does not invoke `init.sh` and is not an aggregator. That
  list plus `tests/full-project-test-suite.sh` are both lint-enforced (see
  HOUSE RULES).
  - **Adding a test is still a ONE-LINE edit** — append it to the canonical
    array. The lane is sharded (matrix `shard: [lint-sweep, lint-scan, sast,
    slow-misc, rest]`), but only the measured long poles are pinned to a
    shard by the `pin_*` arrays; `rest` is the COMPLEMENT, so a new entry
    lands there automatically.
  - **Never write the literal array-opening token (`tests`+`=`+`(`) anywhere
    else in that file below the array.** `_build_unit_list_set` scopes with an
    UNANCHORED `awk '/tests=\(/'` and does not strip comments, so a second
    occurrence re-opens the scope and folds every `tests/test-*.sh` path
    after it into the lint's membership set — a test merely NAMED in a
    comment would then satisfy the lint while never running. The pin arrays
    are named `pin_*` for exactly this reason.
  - The job name **`unit` is a required status check** on `main` (confirmed
    via `gh api repos/kraulerson/solo-orchestrator/branches/main/protection`).
    It survives as a zero-work aggregator job that is red unless every
    `unit-shard` leg is green. Renaming or deleting it leaves every PR waiting
    forever on a check that never reports.
- **FULL suite is ~3h and `workflow_dispatch`-only** (`.github/workflows/tests.yml`
  `full` job: `if: github.event_name == 'workflow_dispatch'`, `timeout-minutes: 180`).
  Never run it casually. Locally, `bash tests/full-project-test-suite.sh` and
  `bash tests/host-drivers/run-all.sh` validate a checkout.

## LINT GOTCHAS

- `scripts/run-lints.sh` runs **every `scripts/lint-*.sh` EXCEPT
  `lint-uat-scenarios.sh`** (11 of the 12 lint scripts as of 2026-07-23).
- `scripts/lint-uat-scenarios.sh` is a **parametrized tool, not a repo lint**:
  bare-invoked it exits **2** with a `Usage:` message because it needs a
  `<populated-html-file>` argument. It is **not** one of the 9 CI-required lint
  jobs (`.github/workflows/lint.yml`), so run-lints deliberately skips it.
- Two lints are **slow full-tree scans**: `lint-counter-antipattern.sh` (~90s)
  and `lint-raw-read-prompt.sh` (~40s). A full `run-lints.sh` is a couple of
  minutes — that is expected, not a hang.

## ISSUE TRACKING — two files, two grammars

- **`solo-orchestrator-backlog.md`** — `BL-NNN` entries. Real status vocabulary:
  **Open**, **Open — DEFERRED** (also "Open — demoted to OPPORTUNISTIC"),
  **Parked**, **Closed**, **Resolved** (legacy "done"), **Won't Fix**.
  What's-open recipe:
  ```
  grep -n '\*\*Status:\*\* Open' solo-orchestrator-backlog.md
  ```
  (returns the whole open family incl. the DEFERRED variants).
- **`solo-orchestrator-bugs.md`** — `BUG-NNN` entries; statuses are `Fixed` /
  `Superseded` (no literal `Open`), so "open" = **not Fixed/Superseded, by
  negation**.
- **Closed / Resolved entries MUST cite a PR # or a backticked commit SHA**
  (`scripts/lint-backlog-references.sh` enforces this).
- **Closed entries are kept deliberately** (audit trail) — never delete them.
  Two scan traps: some entries preserve an `Original entry (pre-close, kept for
  audit trail):` block with its OWN `**Status:**` line (a since-Closed entry's
  preserved `Open`, e.g. BL-055, surfaces in the what's-open grep — eyeball for
  the marker), and a few entries use `## code-*-N:` headers instead of
  `## BL-NNN:`. Verify against the entry's current top-of-block status (and git
  history) before treating any status line as a stray.

## CITATION RULE

Cite code by a **grep-able `# BL-NNN-…` marker comment** or a **function name** —
**never a bare `file:line`**. Line-number cites in handoffs have mis-resolved
within 24h of being written; the marker comment is the repo's citation
primitive. When reading an old handoff, **re-grep every line-number citation
before trusting it**.

## HANDOFFS

- Live handoffs: `docs/handoffs/` — the **newest date is current** (as of
  2026-07-29 that is `docs/handoffs/2026-07-29-sast-coverage-and-ci-lane.md`).
  Everything else at the top level is a pointer stub, so "newest date" and
  "the one non-stub file" agree — if they ever disagree, trust the non-stub.
- Superseded / fully-executed handoffs move to `docs/handoffs/archive/` with a
  pointer stub left at the old top-level path so citations still resolve. See
  `docs/handoffs/archive/README.md` (includes the citation convention).

## ENFORCEMENT — SOURCE OF TRUTH

The **gate scripts are authoritative**, prose guides describe them and may lag —
trust the scripts:
- `scripts/check-phase-gate.sh` (phase 1→2 / 2→3 / 3→4 gates, approvals)
- `scripts/pre-commit-gate.sh` (commit-time gates)
- `scripts/process-checklist.sh` (Build Loop / commit-ready classifier)
- `scripts/run-phase3-validation.sh` (Phase 3 scanners)

**THE `[WARN]` TRAP (check-phase-gate.sh).** The `[WARN]` vs `[FAIL]` text is
**cosmetic** — the exit predicate is `if [ $issues -eq 0 ]`. So any "WARN" arm
that runs `issues=$((issues + 1))` **BLOCKS the gate**, and a true non-blocking
WARN must **omit** the increment. Two arms that both print `[WARN]` can have
opposite gate outcomes. Read the `issues` increment, not the label — that
mismatch is what hid both BL-104 scoring inversions (an `if/elif` with no `else`
let 0/9 Phase-3 steps pass while 8/9 blocked; an empty manifest scored better
than no manifest).

## GOTCHAS

- `pre-commit-gate.sh --tdd-only` runs **TWO** message gates: the BL-072 TDD
  ordering gate AND the BL-006 Build-Loop commit-message check (BL-010). The
  `--tdd-only` name is kept for **hook backward-compat**, not because it is
  TDD-only.
- The **deployment + poc_mode tier predicate** is implemented in **multiple
  scripts and must be changed IN SYNC**: `pre-commit-gate.sh`,
  `check-phase-gate.sh`, `init.sh` (grep the marker `# BL-084-TIER-KEY` — it
  literally says "SYNC SIBLINGS") plus `scripts/lib/enforcement-level.sh`.
- **Big files — grep, don't read whole** (`wc -l`, 2026-07-23, approximate —
  they grow): `init.sh` ~4400, `scripts/upgrade-project.sh` ~3400,
  `scripts/intake-wizard.sh` ~2250, `scripts/check-phase-gate.sh` ~2350,
  `tests/full-project-test-suite.sh` ~2700.

## HOUSE RULES DIGEST

- **No merge on red, ever.** No `gh pr merge --admin`.
- **TDD with mutation proofs** for enforcement changes: break the marked line →
  RED → restore → GREEN. Prove it, don't assert it.
- **Hermetic tests only** — no real remote creation (`lint-no-live-remote-in-tests.sh`
  enforces; a live `gh repo create` leaked a real repo on 2026-07-06).
- **Register every new `tests/test-*.sh`** in
  `tests/full-project-test-suite.sh` — AND, unless it invokes `init.sh`, in
  the `tests.yml` unit list too (per the CANONICAL COMMANDS membership rule).
  `lint-tests-registered.sh` enforces BOTH: the aggregator-registration
  backstop (BL-038) and, via its BL-154 unit-lane arm, the tests.yml
  `tests=(` membership of every test whose **executed lines do not name**
  `init.sh`. Read that predicate literally — it is *names on executed
  lines*, not *invokes*, and the gap between the two is real (below).
  Since BL-181 the exemption predicate reads **executed lines only**
  (`# BL-181-UNIT-LANE-PREDICATE`), so a mere *mention* of `init.sh` in a
  comment no longer exempts a test — in **either** spelling, whole-line at
  any indent **and** trailing (`code   # …`), and at any whitespace width
  (tabs and single spaces included), and whether or not a space follows the
  `#`. Both spellings need their own stage in the predicate, and U6's fixture
  in `tests/test-lint-tests-registered.sh` carries eight init.sh-bearing
  comment lines to pin them. **Two** atoms of the anchored line are not
  pinned by U6, and the fixture header names both rather than papering over
  them: the sed's `\([^[:space:]]\)` guard (behaviour-neutral once whole-line
  comments are stripped — deleting it leaves the suite at 24/0) and the
  grep's `^` anchor (not neutral — deleting it fails **U7 and U10**, at 22/2).
  Pin each atom's WIDTH and its SPELLING, not just its presence: a
  one-character narrowing — a quantifier, a character class, or `#` →
  `#[[:space:]]` — re-opened BL-181 three times and passed both PR-blocking
  checks every time. Before BL-181 a comment exempted a test outright and
  seven real files were silently exempt that way.
  **Never derive the unit list from `grep -L 'init\.sh' tests/test-*.sh`**
  — that recipe matches comments and is what produced the hole. **Two
  residuals survive, so a green lint is still not proof a fast test runs in
  the unit lane — check the list by hand.** (1) A mention inside a
  heredoc/string still exempts (a `grep`/`awk` target, or a stub the test
  writes). (2) In the OTHER half of the same feature, `_build_unit_list_set`
  scopes the `tests.yml` array with awk and never strips comments, so an entry
  **commented out** inside `tests=(` still counts as membership while bash
  drops it — the lint stays green and the test does not run. Both are recorded
  on `## BL-181:`, which stays Open for them. Every *decisive* exemption is
  rendered for review — audit it with
  `bash scripts/lint-tests-registered.sh --list | grep unit-lane-exempt`.
  **An exempt row is a claim, not a verdict: read the rows, do not count
  them — and audit them by EXECUTION, not by grep.** A 2026-07-26 grep-based
  audit of 33 rows moved 5 non-invokers into the unit list; a second pass
  over the remaining 28 — this time tracing execution — found one more
  (`tests/test-lint-no-live-remote.sh`), so a grep audit has now under-read
  this surface twice. The execution recipe: append an env-gated marker line
  to `init.sh`, run each exempt row with that env var set, and treat a marker
  as the only proof of invocation. On the tree of 2026-07-26 that pass
  classified all 27 rows *then present* as real invokers — a measurement at
  one commit, not a standing property. The tree has since grown (the BL-180
  suites pushed it to 29). Re-run it; do not cite the number.
- **Portability:** GNU-first `stat -c … || stat -f …`; never `((x++))` under
  `set -e`; configure a git identity in fixtures; unset `GITHUB_BASE_REF` in
  fixture git ops; no multibyte chars adjacent to variable expansions under
  `set -u`.
- **Docs-only commits** (all staged files match `\.(md|json|yml|yaml|toml|tmpl)$`)
  skip the Build Loop gate; mixed source+docs commits do not — split them
  (CONTRIBUTING.md § Docs-only bypass).
- **Never `--no-verify`.**

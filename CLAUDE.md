# CLAUDE.md — agent orientation for the solo-orchestrator repo

Read this first. It is the map for working effectively in THIS repository.
Counts are date-stamped (they drift); prefer the grep/command recipes — run them
to get current truth. Verified 2026-07-11.

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
- **CI fast lane (unit):** the explicit file list in the `unit` job of
  `.github/workflows/tests.yml`. A test belongs there iff it does not invoke
  `init.sh` and is not an aggregator. That list plus `tests/full-project-test-suite.sh`
  are both lint-enforced (see HOUSE RULES).
- **FULL suite is ~3h and `workflow_dispatch`-only** (`.github/workflows/tests.yml`
  `full` job: `if: github.event_name == 'workflow_dispatch'`, `timeout-minutes: 180`).
  Never run it casually. Locally, `bash tests/full-project-test-suite.sh` and
  `bash tests/host-drivers/run-all.sh` validate a checkout.

## LINT GOTCHAS

- `scripts/run-lints.sh` runs **every `scripts/lint-*.sh` EXCEPT
  `lint-uat-scenarios.sh`** (10 of the 11 lint scripts as of 2026-07-11).
- `scripts/lint-uat-scenarios.sh` is a **parametrized tool, not a repo lint**:
  bare-invoked it exits **2** with a `Usage:` message because it needs a
  `<populated-html-file>` argument. It is **not** one of the 8 CI-required lint
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
  2026-07-11 that is `docs/handoffs/2026-07-10-gate-wave-close-out.md`).
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
- **Big files — grep, don't read whole** (`wc -l`, 2026-07-11, approximate —
  they grow): `init.sh` ~4400, `scripts/upgrade-project.sh` ~2500,
  `scripts/intake-wizard.sh` ~2250, `scripts/check-phase-gate.sh` ~1900,
  `tests/full-project-test-suite.sh` ~2230.

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
  `tests=(` membership of every non-`init.sh` test.
- **Portability:** GNU-first `stat -c … || stat -f …`; never `((x++))` under
  `set -e`; configure a git identity in fixtures; unset `GITHUB_BASE_REF` in
  fixture git ops; no multibyte chars adjacent to variable expansions under
  `set -u`.
- **Docs-only commits** (all staged files match `\.(md|json|yml|yaml|toml|tmpl)$`)
  skip the Build Loop gate; mixed source+docs commits do not — split them
  (CONTRIBUTING.md § Docs-only bypass).
- **Never `--no-verify`.**

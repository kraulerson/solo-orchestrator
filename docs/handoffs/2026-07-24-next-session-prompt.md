# Next-session launch prompt — BL-161 + BL-165 (paste into a fresh session)

You are the SUPERVISOR of a two-item build wave in the solo-orchestrator framework repo
(`/Users/karl/Documents/Claude Projects/solo-orchestrator`). Both items are Karl-approved
(2026-07-23/24) design-fork decisions; the recommended option was chosen for each. Read
`CLAUDE.md` (repo discipline) and the handoff
`docs/handoffs/2026-07-24-residuals-wave-and-next-builds.md` first.

## Preconditions (verify, do not assume)
1. `cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"`; `git fetch origin`;
   `git checkout main && git pull --ff-only origin main`.
2. The four residuals-wave PRs (#255–#258) may or may not be merged yet. If **unmerged**,
   branch each new WP off `origin/main` and expect trivial keep-both-lines conflicts at
   later merge on `tests.yml` / `full-project-test-suite.sh`. If **merged**, `main` already
   carries them — just branch off the updated `main`. Do NOT depend on their content; both
   BL-161 and BL-165 touch different files.
3. `bash scripts/run-lints.sh` should be 11/11 on a clean checkout before you start.

## Discipline (both WPs)
- Watched-RED TDD, `# BL-NNN-` marker fences, mutation proofs, register new `tests/test-*.sh`
  in BOTH `tests/full-project-test-suite.sh` AND the `.github/workflows/tests.yml` unit
  `tests=(` list (unless it invokes `init.sh`). `lint-tests-registered.sh` + full
  `run-lints.sh` green before committing.
- bash-3.2 subset (no `${var,,}`, no `declare -A`, no `nullglob`; never `((x++))` under
  `set -e`; GNU-first `stat -c … || stat -f …`); quote every path (space in repo path);
  `unset GITHUB_BASE_REF` + git identity in fixtures; hermetic tests only (local bare repos,
  never a live remote — `lint-no-live-remote-in-tests.sh` enforces).
- Each WP: opus implementer in an isolated worktree, commit-not-push (source+tests commit,
  then docs-only backlog commit inside the entry, Status stays Open until merge). Then a
  **fable verifier** (≥ implementer tier) on each — both are behavioral. Apply verifier
  findings, then open a green PR and surface to Karl. NEVER self-merge, NEVER `--no-verify`.
- After both PRs are up and CI-green, write a short close-out to Karl and (if he merges)
  the closure flips.

---

## WP-1 — BL-161: `.claude/bypass-audit.json` records only real events

**Decision (Karl, 2026-07-23):** *record only real events* — stop tracking routine
`terminal_commit_passed` receipts. The tracked ledger should change only when something
noteworthy happens (a bypass, an out-of-band commit, or a `terminal_commit_blocked`
refusal from BL-163/BL-171), so the working tree is no longer left perpetually one row
dirty after every session. Keep the file **tracked** (audit trail); do NOT gitignore it.

Read FIRST: `## BL-161:` in `solo-orchestrator-backlog.md`; `scripts/lib/bypass-audit.sh`
(the append primitive + row schema); `scripts/install-filesystem-gates.sh` (writes
`terminal_commit_passed` via `record_audit_row`); `scripts/detect-out-of-band-commits.sh`
(reads the ledger); the BL-163/BL-171 emitted-hook ledger calls (they write
`terminal_commit_blocked` — those MUST keep working).

**Load-bearing precondition (do this before changing anything):** enumerate mechanically
every consumer that READS `terminal_commit_passed` rows — `grep -rn 'terminal_commit_passed'
scripts/ tests/ init.sh` and classify each. If any consumer genuinely depends on the pass
receipts (a heartbeat / "last terminal commit seen" cursor, or the out-of-band detector's
baseline), that is a scope change to SURFACE to Karl, not to silently break. The likely
finding: the pass row is a convenience receipt with no load-bearing reader, but PROVE it.

**Fix shape:** stop emitting the routine `terminal_commit_passed` row at the terminal-commit
success path (mark `# BL-161-NO-ROUTINE-PASS`), while preserving: (a) all
`terminal_commit_blocked` writes (BL-163/BL-171), (b) genuine bypass / out-of-band /
`enforcement_level_set` event rows, (c) whatever the out-of-band detector needs to establish
its baseline — if it relied on the last pass row, give it a non-tracked cursor (mirror
`.claude/last-checked-commit.txt`, already gitignored) rather than the tracked ledger.

**Tests (hermetic, watched-RED):** new `tests/test-bl161-ledger-real-events-only.sh`:
(a) a CLEAN terminal commit writes NO new ledger row (RED pre-fix: a `terminal_commit_passed`
row appears) and leaves the tracked ledger byte-unchanged; (b) a BLOCKED commit STILL writes
its `terminal_commit_blocked` row (regression guard — the BL-163/BL-171 behavior is intact);
(c) a genuine bypass/out-of-band event STILL records; (d) the out-of-band detector still
functions with the new baseline mechanism. Mutation proof: reverting the fix re-introduces
the routine pass row → (a) RED. Blast radius: all four `test-bypass-audit-*` suites,
`test-bl163-blocked-ledger.sh`, `test-bl171-commitmsg-ledger.sh`, `test-bypass-detector*.sh`,
`test-bl112-commit-enforcement.sh` (its `T-clean-commit-still-works` asserts a passed row
today — expect to update it WITH justification: the contract is changing by design).

Branch `fix/bl161-ledger-real-events`. Watch for: `test-bl112`'s clean-commit assertion and
any bypass-audit-integrity test that counts rows — those encode the old contract and must be
updated deliberately, not worked around.

---

## WP-2 — BL-165: Phase-3 DAST hardened-serve harness for static apps

**Decision (Karl, 2026-07-23):** *build the harness* (harness + guidance), the most complete
option — so a genuinely clean static app that declares its production headers can PASS
Phase-3 DAST honestly, instead of structurally FAILing on deploy-time host-header alerts
(missing CSP / anti-clickjacking) that no bundle change can fix.

Read FIRST: `## BL-165:` in `solo-orchestrator-backlog.md`; the zap-dast arm in
`scripts/run-phase3-validation.sh` (markers `# BL-122-ZAP-RISK-FILTER` riskcode≥2 judge and
`# BL-140-ZAP-WORKDIR`, and the just-fixed `# BL-168-TM-SIGPIPE` nearby — do NOT regress any);
`docs/platform-modules/web.md` § 4.4 (the CSP non-inheriting-directives note landed on #245)
and the Bible §11 production-header convention; `tests/test-bl070-snyk-zap-scanners.sh` and
`tests/test-phase3-validation-gate.sh` for the DAST test patterns (hermetic — they stub the
scanner, they do not run real ZAP).

**Fix shape (mark `# BL-165-HARDENED-SERVE`):** when the project declares a production header
set — decide the declaration surface (a Bible §11 parse, or a small config file the harness
reads; pick the simplest robust one and document it) — the zap-dast arm serves the built
artifact WITH those headers applied and records the applied header config as part of the
evidence summary. When the project declares NO header dependence, keep the current
raw-preview FAIL semantics (an app that SHOULD set headers must still fail — do not blunt the
check globally; that was the rejected "downgrade alerts" option). The riskcode≥2 judge and
the BL-140 workdir handling stay intact. Add builders-guide / web.md guidance on the declared
header set and how the harness uses it.

**Tests (hermetic, watched-RED — never run real ZAP/docker in the suite):** new
`tests/test-bl165-dast-hardened-serve.sh`: (a) a project that DECLARES headers → the harness
records the header config in evidence and the arm judges the (stubbed) hardened-serve result,
not the bare-preview result (RED pre-fix: only bare-preview is judged, so the clean app
FAILs); (b) a project with NO declared headers → raw-preview FAIL semantics UNCHANGED (the
regression guard — a genuinely header-dependent app still fails); (c) the riskcode≥2 judge
and BL-140 workdir are unaffected. Mutation proof: revert the harness → (a) RED. Blast
radius: `test-bl070-snyk-zap-scanners.sh`, `test-phase3-validation-gate.sh`,
`test-bl122*`/DAST-family suites, and confirm `# BL-168-TM-SIGPIPE` (same file) is untouched.

Branch `fix/bl165-dast-hardened-serve`. This is the more substantial of the two — the
declaration-surface choice is an implementation decision (pick and document it, don't ask
Karl unless it forces a genuine product fork); if the header-declaration parse turns out to
need a Bible-schema change, surface that as a scope note.

---

## Start
Confirm preconditions, announce the plan, dispatch WP-1 and WP-2 in parallel (isolated
worktrees, background), then verify each with a fable subagent before opening its PR.
Surface both PRs to Karl; do not self-merge. Also worth a cleanup entry if time allows: the
two pre-existing non-blocking test failures noted in the handoff (`test-currency-birth-stamp.sh`
stale vs BL-107; `test-bl113-sast-honesty.sh` env-sensitive).

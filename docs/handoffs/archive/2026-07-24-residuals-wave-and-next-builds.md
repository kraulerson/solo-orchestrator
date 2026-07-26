# Handoff — Dogfood-4 residuals wave complete; next builds = BL-161 + BL-165

**Date:** 2026-07-24 · **Author session:** supervisor (Fable 5) · **Focus for next session:** build the two Karl-approved design-fork items, BL-161 and BL-165.

## 1. Where we are

`main` is at the post-`#254` state (Dogfood-4 fully closed). On top of it, the **post-Dogfood-4 residuals wave** is **complete and open as four green PRs** — NOT yet merged (supervisor never self-merges; awaiting Karl):

| PR | Item(s) | Verifier catch (all fixed on the PR) |
|---|---|---|
| [#255](https://github.com/kraulerson/solo-orchestrator/pull/255) | BL-162 (BL-120 double-print dedup) + BL-167 (`.claude/` excluded from BL-072 classifier) | direct-reviewed (cosmetic scope) |
| [#256](https://github.com/kraulerson/solo-orchestrator/pull/256) | BL-157 (auto-record remote markers for hand-wired origins) | **HIGH** — attestation could be laundered onto an *unpushed* project via a same-named remote branch; fixed with a `cat-file` shared-commit check + 3 security fixtures |
| [#257](https://github.com/kraulerson/solo-orchestrator/pull/257) | BL-171 (commit-msg hook refusals now write ledger rows) + filed BL-172 | **MAJOR** — under a `set -e` composed preamble the row silently vanished; fixed with `\|\| soif_cm_rc=$?` + T6 |
| [#258](https://github.com/kraulerson/solo-orchestrator/pull/258) | BL-158 + BL-166 (`--gate` exit-scope + honest header) | **MAJOR** (test gap) — the `-lt 4`→`-le 4` threshold slip survived every PR-blocking test; closed by cases (f)/(g) |

Every enforcement WP again had a real defect caught by the independent fable verifier — the two-layer discipline held. Merge order to minimize the trivial registration-file conflicts: **#255 → #256 → #257 → #258** (they share `tests.yml` + `full-project-test-suite.sh` anchors; keep-both-lines).

## 2. What shipped this session

- The four PRs above (branches: `fix/bl162-bl167-precision`, `fix/bl157-remote-marker`, `fix/bl171-commitmsg-ledger`, `fix/bl158-bl166-gate-scope`). Each: watched-RED TDD, marker fences, mutation proofs, both-lane registration, fable verifier (except the cosmetic WP-B, direct-reviewed).
- New backlog entry **BL-172** (Low, Open) — the TDD commit-msg gate honors `MERGE_HEAD` only vs BL-006's fuller sentinel set (cherry-pick/revert resumes refused). Filed, not fixed.
- Earlier this session (already merged by Karl): CLAUDE.md count true-up (#249), and the Dogfood-4 closures (#254 `c739d38`).

## 3. What's blocked / waiting

- The four residual PRs await Karl's review + merge. After merge: flip BL-157/158/162/166/167/171 → Closed with SHAs (BL-172 stays Open), same closure-PR pattern as #248/#254.
- **Two pre-existing test failures** surfaced by verifiers, NOT caused by this wave, NOT in the PR-blocking unit lane (both full-suite only) — worth a small cleanup entry when convenient:
  - `tests/test-currency-birth-stamp.sh` — 2 failures, stale vs the BL-107 universal-hook-install contract (rust/other now emit a commit-msg hook; the test still expects absent).
  - `tests/test-bl113-sast-honesty.sh` — 1 failure (`T-mutation-no-launder RED(a)`), identical on origin/main; environment-sensitive.

## 4. What's next — the two builds for the next session

Both are **Karl-approved (2026-07-23/24)** design-fork decisions; the recommended options were chosen. Full briefs are in the launch prompt (§ References). In short:

- **BL-161 (record only real events).** Stop recording routine `terminal_commit_passed` receipts in `.claude/bypass-audit.json`; the tracked ledger records only real events (bypasses, out-of-band commits, and the BL-163/BL-171 `terminal_commit_blocked` rows). Kills the perpetual one-row-dirty tail. **Load-bearing precondition:** first enumerate every consumer that reads `terminal_commit_passed` rows (`detect-out-of-band-commits.sh`, `install-filesystem-gates.sh`, the bypass-audit suites, any dashboard/heartbeat) — if any depends on the pass receipts, that's a scope change to surface, not silently break. Keep the file tracked (audit trail).
- **BL-165 (Phase-3 DAST hardened-serve harness).** Add a serve harness to `run-phase3-validation.sh`'s zap-dast arm: when the project declares production headers (Bible §11 / a config-declared header set), serve the built artifact WITH those headers applied and record the header config as evidence; apps that declare no header dependence keep the raw-preview FAIL semantics. Plus builders-guide guidance. Interacts with the BL-122 riskcode≥2 judge and BL-140 workdir — do not regress those.

Recommendation: run them as **two parallel WPs** (opus implementers in isolated worktrees, commit-not-push) with **fable verifiers** on each (both are behavioral: BL-161 changes ledger-write semantics, BL-165 changes a security scanner's pass/fail surface). Same discipline as this wave.

## 5. References

- Backlog entries (source of truth, all Open): `solo-orchestrator-backlog.md` — `## BL-161:`, `## BL-165:`, plus `## BL-172:` (filed this session).
- Enforcement source of truth: `scripts/lib/bypass-audit.sh` + `scripts/install-filesystem-gates.sh` (BL-161 target); `scripts/run-phase3-validation.sh` (BL-165 target — see the `# BL-122-ZAP-RISK-FILTER` / `# BL-140-ZAP-WORKDIR` / `# BL-168-TM-SIGPIPE` markers).
- Repo discipline: `CLAUDE.md` (bash-3.2 subset, `[WARN]`-trap, marker-citation rule, both-lane registration, quote paths).
- Prior wave patterns (how these WPs were run): `Reports/2026-07-22-dogfood-4/LEDGER.md`.
- Launch prompt for the next session: `docs/handoffs/2026-07-24-next-session-prompt.md`.

## 6. Resume prompt

> Continuing from the 2026-07-24 handoff at `docs/handoffs/2026-07-24-residuals-wave-and-next-builds.md`. The Dogfood-4 residuals wave shipped as four green PRs (#255–#258) awaiting Karl's merge; do not merge them. This session builds the two Karl-approved design-fork items: **BL-161** (make `.claude/bypass-audit.json` record only real events — stop tracking routine `terminal_commit_passed` receipts, after enumerating every consumer of those rows) and **BL-165** (add a hardened-serve DAST harness to `run-phase3-validation.sh` so a static app that declares production headers passes Phase-3 DAST honestly, keeping raw-preview FAIL for apps with no declared headers). Run them as two parallel WPs in isolated worktrees with watched-RED TDD + marker fences + mutation proofs + a fable verifier each; commit but never push; open green PRs and surface to Karl. Read the full briefs in `docs/handoffs/2026-07-24-next-session-prompt.md` and repo discipline in `CLAUDE.md` first.

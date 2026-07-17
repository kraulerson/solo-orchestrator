# Dogfood-2 Remediation — Progress Ledger

**Run started:** 2026-07-17. Autonomous remediation per [`REMEDIATION-PROMPT.md`](./REMEDIATION-PROMPT.md), following [`REMEDIATION-PLAN.md`](./REMEDIATION-PLAN.md) order.
**Merge policy:** AUTO_MERGE = NO (kickoff default) — every fix lands as a green PR awaiting Karl's review; branches stack sequentially on the previous WP's branch so shared files (test registries, this ledger) accrete without conflicts. Merge order = PR order.
**Append-only:** one entry per work package, written immediately after the WP completes (context-summarization insurance). Statuses: DONE-PR-open / MERGED / STOPPED-flagged / BLOCKED.

---

## STEP-0 — stabilize the base

- **Branch:** `docs/dogfood2-findings-base` (off `main` @ `8412b8c`, in sync with origin, zero open PRs at start).
- **Working-tree state found:** `solo-orchestrator-backlog.md` modified (+252/−1 — the 13 new `## BL-118…BL-130` entries plus the BL-114 addendum's Related-line rewrite); `Reports/2026-07-13-dogfood-2/` untracked (FINDINGS.md, LEDGER.md, REMEDIATION-PLAN.md, REMEDIATION-PROMPT.md). Both committed here as the remediation base.
- **Left untracked deliberately** (pre-existing, not named by the kickoff's Step 0): `DOGFOOD-2-PROMPT.md` and `EXECUTIVE-SUMMARY.md` at repo root (dogfood-2 artifacts Karl may want moved into this Reports dir), `.claude/skills/` (local project skills), `.claude/worktrees/` (workflow-agent state). Flagged in the final report.
- **Hook install:** `.git/hooks/pre-commit` held a 578-byte personal gitleaks+semgrep hook (dated Apr 25 — itself using the BL-118-blind `p/owasp-top-ten` ruleset). Backed up to the session scratchpad (`pre-commit.backup-personal-hook`), then replaced with `scripts/pre-commit-gate.sh` per CONTRIBUTING.md § Local development setup.
- **CDF checkout:** present at `~/.claude-dev-framework` (docs/, gates/, hooks/, FRAMEWORK_VERSION…). Not modified.
- **Lint baseline:** `bash scripts/run-lints.sh` on the dirty tree → **11 lints — 11 passed, 0 failed**.
- **Status:** base commit + PR follow immediately after this file is written.

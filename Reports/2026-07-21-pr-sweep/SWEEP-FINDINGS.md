# BL-146 Cumulative PR Sweep — Findings Record (2026-07-21)

Reviewer: the BL-146 standing adversarial PR reviewer (second live run,
Fable tier), Karl-directed: all 229 merged PRs (#1–#231), issue-threading
required — only defects DEMONSTRATED on main `e7bc567` by an executed probe
count. Findings independently re-validated by the orchestrating session
before planning (every probe reproduced).

## Unresolved findings → filed as backlog entries

| Sweep ID | Backlog | Tier | One line |
|----------|---------|------|----------|
| CR-1 | BL-147 | MUST | Emitted CI approval-log integrity steps vacuous under depth-1 checkout — tampering passes silently; 7/10 languages lack the step entirely |
| CR-2 | BL-148 | MUST | Emitted CI SAST rides semgrep-action — archived upstream 2024-04 |
| CR-3 | BL-149 | MUST | Emitted release DAST is the un-fixed BL-122 twin — unpassable for any real web app |
| CR-4 | BL-150 | SHOULD | Every action pin lags 1–3 majors; pins invisible to the currency system |
| CR-5 | BL-151 | SHOULD | Org-track gitleaks CI step unlicensed + depth-starved |
| CR-6 | BL-152 | SHOULD | GitLab approvals call on an API deprecated since 14.0 |
| CR-7 | BL-153 | SHOULD | Bitbucket semgrep image rename-frozen; gitleaks command form deprecated |
| CR-8 | BL-154 | NICE | tests.yml unit-list membership unenforced; CLAUDE.md overclaims |

## The headline pattern

All eight live in the EMITTED-TEMPLATE / EXTERNAL-TOOL surfaces — the one
region the (excellent) internal test estate structurally cannot execute: no
test runs a generated workflow on a real runner, and nothing watches upstream
tool lifecycles. The internal history is clean: every issue the sweep spotted
in gate scripts, hooks, scanners, and test infra was already corrected by a
later PR (nine threaded non-findings, each verified fixed on main).

## Disposition

Remediation plan: `REMEDIATION-PLAN.md` (this directory) — six WPs, executor
Opus 4.8 per Karl's directive, Fable consolidated verification at the end,
then the Dogfood-4 milestone. Full sweep transcript (probes, coverage
accounting, currency report) preserved in the session record 2026-07-21.

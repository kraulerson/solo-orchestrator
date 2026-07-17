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
- **Status:** base commit `3a3ad11` landed through the installed hooks; **PR #198** opened.

---

## WP-A1 — BL-118 (Critical): SAST blind to DOM XSS — DONE-PR-open

- **Branch:** `fix/bl118-sast-dom-xss` (stacked on `docs/dogfood2-findings-base` / PR #198). **PR #199**, fix commit `fbf2be8`.
- **Reproduce (2026-07-17, semgrep 1.157.0):** positive control `sink.ts` (`eval`/`innerHTML`/`document.write`): `p/owasp-top-ten --severity=ERROR --error` → 0 findings, rc=0 (**the bug**). `r/javascript.browser.security.insecure-document-method --error` → 2 findings (innerHTML L3, document.write L4), rc=1; `--json` shows `severity=ERROR` for both, so the pack SURVIVES the `--severity=ERROR` bound → single-invocation fix valid. `eval` is flagged by NEITHER pack (residual, see notes).
- **Discovered while fixing (folded in):** `scripts/verify-install.sh::fix_precommit_hook` was a THIRD emitter of the pre-commit hook, inlining the ancient pre-BL-099/BL-112 body (blind ruleset, `--quiet`, NO `--error` → dead `[BLOCKED]` arm, no managed-region markers, unconditional exit). The repair path re-installed the exact defects BL-112/BL-118 fixed. Now delegates to `scripts/lib/hook-templates.sh::soif_write_precommit_hook` (project-local lib first, `$SOURCE_DIR` fallback, loud FAIL if neither — never an inline body).
- **Fix (markers):** `# BL-118-DOMXSS-CONFIG` (hook-templates.sh, config on its own continuation line) · all 20 `templates/pipelines/ci/{github,gitlab}/*.yml` (gitlab dart/other/swift had NO sast job — added in sibling bracket style) · `# BL-118-SINGLE-SOURCE` (verify-install.sh) · `tests.yml` full lane now `pip install semgrep`.
- **Test:** `tests/test-bl118-sast-dom-xss.sh` — 3 hermetic exact-token config pins + 3 live real-`git commit` cases with loud-SKIP discipline. Registered in full suite + unit lane.
- **RED (pre-fix):** 5 FAIL / 1 PASS — incl. the live bug verbatim: `pane.innerHTML = userText` COMMITTED CLEAN with `[OK] semgrep: SAST ran on 1 staged file(s)`.
- **GREEN (post-fix):** 6/6 — XSS REFUSED BY GIT (`[BLOCKED]`, HEAD unmoved); textContent fix lands WITH the [OK] receipt; in-test mutation (strip config from emitted hook) → same XSS LANDS (load-bearing).
- **Source-level mutation proof:** deleted the config line from hook-templates.sh + github/typescript.yml → 5/6 RED (hook pin; template pin flags exactly the mutated file; verify-install-repaired hook goes blind too — delegation composes; live XSS lands again; nothing-to-strip) → restored → 6/6 GREEN.
- **Affected suites (all green):** test-bl112-commit-enforcement **13/13** · test-bl099-guard-coverage **52 pinned / 0 failed** · test-verify-install-fix-functions **15/15** · test-verify-install-bl030-coverage exit 0 · test-verify-install-eval-factory-gate exit 0 · run-lints **11/11**.
- **Adversarial verify (Fable-tier subagent, refutation brief A–H):** verdict **SHIP** — all claims held (rule severity re-confirmed; bash 3.2+5 `bash -n`; 20/20 PyYAML-parse; pinned semgrep-action source traced end-to-end `INPUT_CONFIG`→`SEMGREP_RULES`→`execvp semgrep ci` with local whitespace-split proof; no name collisions; no forbidden marker strings in emitted bytes; pre-fix world 5/6 RED without semgrep too).
  - **Acted on (in `fbf2be8`):** silent re-blinding on registry drift — a typo'd/renamed `r/` path next to a valid pack resolves SILENTLY EMPTY (rc=0, green banner; verifier drove a real XSS commit through a typo'd hook: landed with [OK]). Countered: exact-token pins (typo world proven caught: PIN-CATCHES-TYPO / PIN-ACCEPTS-GOOD) + semgrep installed in the CI **full** lane so the live blocking arm executes in CI at all.
  - **Filed:** BL-131 (residual sinks — `insertAdjacentHTML`, jQuery `.html()`, `.vue` SFCs, inline `<script>` in `.html`; NO public registry rule covers them, verifier-tested at all severities) · BL-132 (hook scans worktree paths, not index content — stage-then-overwrite commits unscanned bytes; pre-existing BL-112 design).
- **Open question for Karl (recorded, not guessed):** semgrep in the **unit** lane too? It would run the live proof on every PR but adds a registry fetch (latency + flake surface) to the fast lane. Full-lane-only shipped as the conservative default.
- **Notes / residuals:** (1) `eval()` sinks remain invisible to the commit-time gate (neither pack carries an ERROR-severity eval rule); Phase-3 `--config auto` catches them. (2) gitlab templates run `p/security-audit` only vs github's two packs — pre-existing asymmetry, untouched. (3) The pinned `semgrep/semgrep-action@713efdd… (v1/v0.58.0)` is 2021-era; verifier traced it as pass-through-correct for `r/` configs, but modernizing the pin is worth a look. (4) `--config auto` at commit time NOT adopted (network + metrics on every commit; deterministic registry pack keeps the BL-112-SAST-NOTRUN discipline meaningful).

# Solo Orchestrator Backlog

Items that aren't formal-spec-worthy yet — proposals, tech debt, audits, drift-watches.
Promote to `docs/superpowers/specs/` when ready to design in depth.

## Format

Each item has an ID, title, logged date, severity, short description (3–5 lines),
trigger/deadline if any, and status.

**Categories:**
- **Proposal** — new feature suggested but not yet designed
- **Debt** — known suboptimal state we're living with
- **Audit** — things to check periodically
- **Drift-watch** — things that could silently break when upstream/environment changes

**Status values (as actually used — recount the `**Status:**` lines before trusting any tally):**
- **Open** — active; not started, or in progress.
- **Open — DEFERRED `<date>`** (also **Open — demoted to OPPORTUNISTIC**) — still Open, but consciously deprioritized. The revisit trigger is stated inline on the status line.
- **Parked** — investigated, no current operator demand; an explicit re-evaluation trigger is noted inline.
- **Closed** — shipped/done. MUST cite a PR # or a backticked commit SHA in the entry block (`scripts/lint-backlog-references.sh` enforces this).
- **Resolved** — legacy synonym for **Closed** (early-convention "done"); same citation requirement.
- **Won't Fix** — deliberately declined; the reopen trigger is noted inline.

**What's-open recipe (this IS the index — don't add a static open-items list, it drifts):**

```
grep -n '\*\*Status:\*\* Open' solo-orchestrator-backlog.md
```

Returns the whole open family, including the `Open — DEFERRED` / `Open — demoted to OPPORTUNISTIC` variants (they are still `Open`).

**Bugs file has a different grammar.** `solo-orchestrator-bugs.md` tracks `BUG-NNN` entries whose statuses are `Fixed` / `Superseded` (with the odd `Still …`); there is no literal `Open` status, so "open" there means *any BUG not marked Fixed/Superseded* — determined by negation, not by the status grep above.

**Audit-trail convention — Closed entries are kept, never deleted.** The backlog is also a record of what we considered (including promoted-to-spec items, which stay with a link to the spec). Two things the naive grep above can misattribute:
- Some Closed entries preserve an **`Original entry (pre-close, kept for audit trail):`** block that embeds its OWN `**Status:**` line. That preserved `Open` belongs to a since-Closed entry (e.g. BL-055) and will surface in the what's-open grep — eyeball for the `Original entry` marker before counting it as live.
- A few entries use `## code-*-N:` headers (e.g. `## code-check-gates-1:`) instead of `## BL-NNN:`, so header-only scans miss them.

Verify against the entry's current top-of-block status (and git history if in doubt) before treating any single status line as authoritative.

---

## BL-001: Audit downstream sync mechanism for CDF updates

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Closed (2026-07-06, PR #142) — CDF asset refresh wired into `upgrade-project.sh` via new thin `scripts/lib/cdf-refresh.sh` (`CDF_HOME`-overridable, delegates to upstream `refresh_cdf_assets`); `check-updates.sh` now compares against the CDF clone. Verifier `minor_concerns` (graceful-skip coverage) → closed. Follow-up (Karl: backfill honors sentinel) tracked as [[bl080-backfill-honors-sentinel]].

**Decision (2026-07-05):** Karl approved **Option A — investigate first**. Explore-first recon of `upgrade-project.sh`'s CDF-sync handling (does it pull a fresh CDF clone? replace `.claude/framework/`? bump `FRAMEWORK_VERSION`?) BEFORE any code. Fix likely lands upstream in CDF (`~/.claude-dev-framework`) per the cross-repo preference, not a Solo shim. Lowest urgency of the open set — no downstream project has reported a missed fix; run as a background recon spike.

Existing downstream projects at older CDF `FRAMEWORK_VERSION` need a sync mechanism to pick up upstream fixes. `scripts/upgrade-project.sh` is presumed to handle this, but if its CDF-sync logic is stale, silently skips, or doesn't update `.claude/framework/` files, downstream projects miss landed fixes — e.g., FRAMEWORK_VERSION 4.2.2's Context7 detection and stop-checklist `--no-merges`/`CURRENT_HAS_SOURCE` improvements.

**Scope:** read `upgrade-project.sh`'s CDF handling; verify it pulls fresh CDF clone; verify it replaces `.claude/framework/` files correctly; verify `FRAMEWORK_VERSION` is updated in the downstream project; add regression test in `tests/upgrade-path-tests.sh`; document user-facing invocation in `docs/user-guide.md`.

**Trigger:** Before the next major CDF upstream fix that downstream projects need to pick up, OR after a downstream project reports missing a fix.

**Related:** CDF upstream commits `a640ba8`, `fd8469a`, and `4.2.2`-era changes; solo-orchestrator's BUG-001 and BUG-007 "Superseded" updates.

---

## BL-002: Handle GitHub free-tier branch-protection 403 gracefully

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Medium
**Status:** Closed (2026-04-27, PR #36, commit 50c0430)

Surfaced during live-API verification of the host-aware repo gate. On free-tier GitHub personal accounts, branch protection is unavailable on private repos (API returns HTTP 403 *"Upgrade to GitHub Pro or make this repository public to enable this feature."*). The current GitHub driver fails hard: `host_configure_protection` returns non-zero, the init.sh flow aborts, and the user gets a cryptic "failed to configure protection" message without the tier context.

**Scope:** In `scripts/host-drivers/github.sh`, detect the specific 403 response body mentioning "Upgrade to GitHub Pro" and:
1. Print a clear remediation message explaining the tier limitation (upgrade to Pro / use public / accept risk).
2. Offer to fall back to an attestation-style flow matching the `other` host path (user confirms they'll configure protection manually when they have Pro).
3. Record the attestation in `process-state.json` so the backstop gate can recognize it.

Similar check for GitLab and Bitbucket tier restrictions if their equivalent exists (GitLab's free tier allows branch protection on all projects; Bitbucket's free tier includes branch restrictions; neither currently has this issue).

**Trigger:** Before any free-tier user tries to use the framework in `private` mode. Workaround documented in `docs/builders-guide.md` § Repository Setup.

**Related:** Live-API verification on 2026-04-22. Orphan test repos in user's GitHub account needing manual cleanup.

---

## BL-003: Full end-to-end init.sh test against mocked host CLIs

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Closed (2026-06-27, PR #59, commit f684aa7) — umbrella closed; sub-entries BL-003a (PR #61) and BL-003b (PR #62) cover gitlab/bitbucket follow-up coverage

Plan Task 10.1 was deferred during inline execution. Current test coverage: driver-level unit tests (mocked CLIs) and three regression cases (lancache-pattern, missing host field, protection drift). Missing: a "happy path" test that runs `init.sh`'s new `create_and_protect_remote` end-to-end against mocked `gh`/`glab`/`curl` and verifies all post-conditions (manifest host field set, CI template at correct host-specific path, `process-state.json` `phase2_init.steps_completed` populated).

**Scope:** add `tests/host-drivers/e2e-init.test.sh`. For each host (github/gitlab/bitbucket/other), scaffold a minimal init environment, run `create_and_protect_remote`, assert post-state.

**Trigger:** Before refactoring `init.sh`'s host flow; any change there risks silent regression without this test.

---

## BL-004: Upgrade-path regression test for flat→per-host template migration

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Closed (2026-06-27, PR #58, commit a3ea907)

Plan Task 10.3 was deferred during inline execution. `scripts/upgrade-project.sh` now handles two migrations (flat CI templates → per-host subfolders; manifest `host` field backfill) but neither migration has a regression test.

**Scope:** add case to `tests/upgrade-path-tests.sh`. Scaffold a project with old flat `templates/pipelines/ci/*.yml` layout and manifest without `host` field, run upgrade, assert: existing `.github/workflows/ci.yml` preserved, templates moved to `github/` subfolder, `host` field backfilled to `github` (inferred from remote URL), process-state.json NOT auto-verified.

**Trigger:** Before the first downstream project attempts to upgrade to this framework version.

---

## BL-005: Parity test coverage for GitLab and Bitbucket drivers

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Low
**Status:** Resolved (2026-06-28, PR #81)

Driver-level test coverage varies: GitHub has 8 scenarios (full contract, both modes, drift cases); GitLab has 6 (most of contract, both modes); Bitbucket has 4 (name, require_cli, register_remote, parse_origin only — HTTP logic untested). Bitbucket's `host_configure_protection` and `host_verify_protection` HTTP calls are validated by code review only.

**Scope:** extend `tests/host-drivers/bitbucket.test.sh` with mock-curl fixtures for: configure_protection (personal + org payloads), verify_protection (all restriction types present → pass; missing restrictions → fail with specific messages), drift detection.

**Trigger:** Before the first solo-orchestrator user tries Bitbucket, OR whenever touching `bitbucket.sh`.

**Resolution (cycle 8, 2026-06-28):** Closed via test additions across three files plus one doc + backlog tweak. (1) `tests/host-drivers/bitbucket.test.sh` adds 6 unit-test scenarios — `host_configure_protection` (personal, org) and `host_verify_protection` (personal pass, personal fail, org pass, org fail) — exercising the previously-untested curl payloads under `_bb_curl` / `_bb_curl_no_body`. (2) `tests/host-drivers/gitlab.test.sh` adds 6 parity scenarios surfaced against `github.test.sh`: `host_require_cli` unauthed, `host_create_repo` public + dupe, `host_register_remote` replace existing, `host_configure_protection` org, `host_verify_protection` org pass. (3) `tests/host-drivers/mock-cli.sh` extended with stdin-drain guard (`[ -t 0 ] || cat >/dev/null`) so bitbucket's `--data-binary @-` POSTs don't race against stub exit on the success path; stderr discipline preserved (stub writes stderr only on unmatched-fixture exit 127). (4) `docs/cli-setup-addendum.md` § Bitbucket: `BITBUCKET_WORKSPACE` is now documented as required (not org-only) per audit code-host-bitbucket-1. Full host-drivers run-all + 3 e2e suites remain green.

---

## BL-006: Enforce Build Loop via pre-commit hook (commit-message-triggered)

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** High
**Status:** Resolved (2026-04-24, PR #15)

Surfaced during the lancache project audit. `scripts/process-checklist.sh --start-feature` is advisory — a `feat(...)` commit can land without starting a Build Loop session, and `--record-feature` detects the drift only after the fact (post-commit audit). On lancache, ID1 and ID3 (MVP Cutline items per PRODUCT_MANIFESTO §5) were committed as `feat(init): ...` without going through the Build Loop; the drift was caught only when running `--record-feature` retroactively.

**Scope (locked during brainstorm):** add a new trigger in `pre-commit-gate.sh` that extracts the commit message and delegates to a new `process-checklist.sh --check-commit-message "MSG"` subcommand. When the message subject starts with `feat`, `feat(scope)`, `feat!`, or `feat(scope)!`, enforce the same strict state check the existing file-heuristic path uses (feature started + first 5 build_loop steps done). Strict enforcement — no warns-then-blocks grace window, no `SOIF_*` bypass. Non-Cutline scaffolding must use `chore:`/`build:`/`ci:`/`docs:` instead. Derivative commits (amend, merge, revert, cherry-pick, squash-merge) are filtered and pass through. Editor-case commits (no `-m`) fall through to the existing file-heuristic path.

**Trigger:** Before another MVP Cutline ID can drift past the Build Loop unnoticed. Coupled with BL-007 (shipped PR #14) — the doc rule defines what the hook enforces; this is the mechanical-enforcement companion.

**Related:** lancache project Phase 2 audit, 2026-04-22; path-forward decision to use pre-commit (not post-commit) per technical constraint that post-commit hooks cannot block. BL-007 (PR #14) shipped the doctrinal rule on 2026-04-23; BL-006 mechanically enforces it.

**Spec:** `docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md` (committed 2026-04-23).

**Follow-ups logged as optional:** BL-010 (commit-msg git hook for editor-case), BL-011 (Cutline-ID-aware enforcement), BL-012 (retroactive scanning), BL-013 (squash-merge CI enforcement), BL-014 (commit-type hygiene).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-24-build-loop-precommit-enforcement-implementation.md`. Shipped in PR #15 (merged 2026-04-24 at `ec6083c`). Two-layer design: `pre-commit-gate.sh` extracts commit message (inline `-m`, heredoc, `-F file`) and filters derivative commits (amend, merge, revert, cherry-pick, squash, `MERGE_HEAD`); delegates policy to new `process-checklist.sh --check-commit-message "MSG"` subcommand. Feat-prefix regex `^feat(\([^)]*\))?!?:[[:space:]]` (case-sensitive per Conventional Commits). Shared helper `require_build_loop_state_for_commit` factored out of existing `check_commit_ready`; both file-heuristic and message-prefix paths now produce the spec's Case A/B remediation messages. 17 unit tests in `tests/test-check-commit-message.sh`, 7 integration tests (E33–E39) in `tests/edge-cases-scripts.sh`, all passing. Builder's Guide § "MVP Cutline Work Requires the Build Loop" gets a "Mechanical enforcement" paragraph; `claude-md.tmpl` gets a subordinate bullet; `upgrade-project.sh` gets a header changelog note (no migration code — existing upgrade flow copies the updated scripts). Security audit `docs/security-audits/bl-006-precommit-buildloop-enforcement-security-audit.md` — 0 open findings.

---

## BL-007: Builder's Guide rule — MVP Cutline IDs always require full Build Loop

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Medium
**Status:** Resolved (2026-04-23, PR #14)

Surfaced during the lancache project audit. Builder's Guide §2.0 (Phase 2 Init sub-steps) and §2.1+ (Build Loop) are distinct phases. A developer or AI reading CLAUDE.md can reasonably conclude that init-era feature work (during §2.0 steps 2–10: scaffolding, migrations, CI setup, Docker, backup verification) doesn't need the full Build Loop ceremony — which is exactly what happened on lancache when `feat(init): initial migration + runner` and `feat(init): structlog with correlation-ID propagation` were treated as init scaffolding. Both were actually MVP Cutline IDs (ID1 and ID3) that deserved full Build Loops.

**Scope:** explicit rule in Builder's Guide — "MVP Cutline items (F-IDs and ID-IDs per PRODUCT_MANIFESTO §5) ALWAYS require a full Build Loop, regardless of which Phase 2 sub-step they land in. If Phase 2 Init work (§2.0 steps 2–10) produces a commit that implements a Cutline ID, that commit must go through `--start-feature` → tests → implementation → audit → `--record-feature` just like any §2.1+ work."

Possibly pair with tooling enforcement in BL-006 that cross-references commit messages against a manifest-derived Cutline ID list — but doc-only is the minimum.

**Trigger:** Couple with BL-006 — the doc rule defines what the hook enforces.

**Resolution:** Implemented via spec `docs/superpowers/specs/2026-04-23-mvp-cutline-build-loop-rule-design.md` + plan `docs/superpowers/plans/2026-04-23-mvp-cutline-build-loop-rule-implementation.md`. Shipped in PR #14 (merged 2026-04-23 at `442c0d6`). Two-file doc change: new subsection "MVP Cutline Work Requires the Build Loop" in `docs/builders-guide.md` between §2.0 and §2.1 with rule + rationale + 3 worked examples + recovery guidance; new bullet in `templates/generated/claude-md.tmpl` "Your Constraints" block pointing at the Builder's Guide subsection. Rule is generic (no F-/ID- prefix convention forced). BL-006 will mechanically enforce this same rule via pre-commit hook — next up in the triage.

---

## BL-008: Rollback/abort workflow for recorded features and UAT sessions

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Medium
**Status:** Resolved (2026-04-23, PR #12)

Surfaced during the lancache project audit. When a feature gets recorded incorrectly (e.g., `--record-feature` called for a commit that shouldn't have been treated as a feature) or a UAT session is started but needs to be aborted, there's no sanctioned workflow. On lancache, the user is about to correct via direct `jq` edit of `build-progress.json` + `--reset uat_session` — workable but undocumented.

**Scope:** add `scripts/process-checklist.sh --unrecord-feature NAME` to cleanly remove a feature from `build-progress.json` (with confirmation prompt); document the existing `--reset uat_session` in CLAUDE.md's Testing & Bug Workflow section; possibly add `--abort-build-loop` if a feature was started but never finished and the orchestrator wants to scrap it without recording.

**Trigger:** Most immediate follow-up of the three — user is doing the manual fix via jq today. Smallest scope (new subcommand + docs); good quick-win to tackle first.

**Related:** lancache project Phase 2 audit, 2026-04-22. Tackling first per path-forward ordering.

**Resolution:** Implemented via spec `docs/superpowers/specs/2026-04-23-unrecord-feature-design.md` and plan `docs/superpowers/plans/2026-04-23-unrecord-feature-implementation.md`. Shipped in PR #12 (merged 2026-04-23 at `8550e82`). `scripts/test-gate.sh --unrecord-feature NAME` is the new subcommand; `--reset uat_session` / `--reset build_loop` are documented in CLAUDE.md's Testing & Bug Workflow section. 7 unit tests in `tests/test-unrecord-feature.sh` covering state transform + error paths; interactive wrapper verified via bash harness.

---

## BL-009: UAT template quality guardrails + platform-aware authoring

**Logged:** 2026-04-23
**Category:** Debt
**Severity:** Medium
**Status:** Resolved (2026-04-23, PR #13)

Surfaced during lancache project UAT Session 1 (2026-04-22 → 2026-04-23). The framework's UAT template accepts schema-valid-but-operationally-broken scenarios: no system context, implicit working directory, cross-scenario dependencies, vague pass/fail criteria, non-deterministic expected-output matching, informal cleanup, unmarked optional dependencies. The Orchestrator's review after first generation: *"The tests are not stating what system this is done on, it doesn't walk through the tests step by step and makes assumption the tester knows where everything is."* Plus a platform-variance gap: the existing template's example is desktop-CLI shaped and doesn't translate to web, mobile, MCP-server, or long-tail platforms.

**Scope:** three-layer guardrail — universal HTML-comment quality checklist + anti-pattern list; per-platform reference examples (pre-flight + scenario) for each of solo's 4 first-class platforms under `templates/uat/references/`; interactive co-build protocol for `other` platform; pattern-based `scripts/lint-uat-scenarios.sh` invoked by the agent before saving populated UAT files. Plus templates reorganized into `templates/uat/` subdirectory, partial MD-template parity (pre-flight reminder + HTML pointer), new `docs/uat-authoring-guide.md`, and auto-migration via `upgrade-project.sh`.

**Trigger:** tackled now, ahead of BL-006/BL-007 — lancache pain is active and the fix is bounded (one spec, one plan). BL-006 and BL-007 remain queued afterward per the agreed triage order.

**Spec:** `docs/superpowers/specs/2026-04-23-uat-template-quality-design.md` (committed 2026-04-23 at `7b3dfff`).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-23-uat-template-quality-implementation.md`. Shipped in PR #13 (merged 2026-04-23 at `9f11c88`). Three-layer guardrail: universal HTML checklist + 4 per-platform reference pairs + `scripts/lint-uat-scenarios.sh` pattern linter. `other` platform handled via 5-question co-build protocol in `docs/uat-authoring-guide.md § 5`. Templates reorganized to `templates/uat/` subdirectory. `upgrade-project.sh` migration block for existing projects. 11 linter unit tests + 7 integration tests (E26–E32 in edge-cases-scripts.sh), all passing.

---

## BL-010: `.git/hooks/commit-msg` for editor-case & human-terminal coverage

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Closed (2026-07-10, PR #166 shipped the commit-msg hook infrastructure; PR #169 wired the BL-006 check into it per Karl's "Fix it" decision).

Punted from BL-006. Install a local `commit-msg` git hook via `init.sh` that invokes `scripts/process-checklist.sh --check-commit-message "$(head -n1 "$1")"`. Extends enforcement to two populations the PreToolUse hook cannot reach: (a) `git commit` with no `-m` flag (editor opens), and (b) human-Orchestrator commits from the terminal. The BL-006 design was explicitly built so this is a pure addition — no refactor needed.

**Trigger:** A concrete case where an editor-opened or human-typed `feat:` commit drifts past the Build Loop. Lancache pain was AI-agent authored only, so there is no current signal this matters.

**Tradeoff:** adds a second enforcement site to keep in sync with the PreToolUse hook; meaningful surface-area increase on `init.sh`. Worth it only if the gap bites.

**Related:** BL-006 spec § 10 (out-of-scope note); `pre-commit-gate.sh` architecture is Claude-only by design.

**Resolution:** Karl decided 2026-07-10 "Fix it" (build the residual, then close). PR #166 (BL-072 C2) already installed the `commit-msg` git hook (`init.sh::install_tdd_commit_msg_hook`, invoking `pre-commit-gate.sh --terminal-mode --tdd-only`), which reaches editor-written and human-terminal commits. PR #169 wired the older BL-006 Build-Loop commit-message check into that same surface via a new `bl006_terminal_enforce()` — it delegates to the SAME `process-checklist.sh --check-commit-message` subcommand the PreToolUse `bl006_check` uses, enforcing identical block conditions, subject (first message line), and remediation. Derivative commits pass through via their commit-msg-time git sentinels (`MERGE_HEAD` / `CHERRY_PICK_HEAD` / `REVERT_HEAD`), mirroring the PreToolUse command-string filters. Mothership-safe on two layers (no-op when the project lacks `scripts/process-checklist.sh`; `check_commit_message` phase-gates at `current_phase < 2`). Load-bearing wiring marked `# BL-010-COMMITMSG-BL006`. Tests: `tests/test-bl010-commitmsg-bl006.sh` (11 assertions — block / pass / editor-case real `git commit` / mothership no-op / cross-surface parity / RED→GREEN mutation), registered in both aggregators; the BL-072 C1/C2 suite stays green (36/36).

---

## BL-011: Cutline-ID-aware enforcement

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Won't Fix (2026-07-10, Karl decision). Zero operator demand since 2026-04-23; would re-impose an F-/ID- ID convention BL-007 deliberately avoided. Reopen on a concrete Cutline-drift case.

Punted from BL-006. Parse `PRODUCT_MANIFESTO.md §5` for F-/ID- Cutline identifiers and require commits that touch Cutline work to explicitly reference the ID (e.g., `feat(ID1): ...`), cross-checking that each Cutline ID gets exactly one Build Loop. Catches drift where Cutline work masquerades as a bugfix (`fix(ID1): ...`) or doesn't mention the ID at all.

**Trigger:** A concrete case where a Cutline item drifts under a non-`feat` commit prefix after BL-006 ships. BL-006 closes the `feat:` gap; BL-011 would close a hypothetical `fix:`/`refactor:` gap.

**Tradeoff:** forces every project to adopt an F-/ID- prefix convention in their manifest. BL-007 deliberately kept the rule generic — no ID convention imposed. BL-011 would re-impose one.

**Related:** BL-006 spec § 10; BL-007 doctrinal decision to keep the Cutline rule convention-free.

---

## BL-012: Retroactive scanning for drifted feature commits

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Won't Fix (2026-07-05). Forward-only enforcement is the deliberate design; zero operator demand in 60+ days. Reopen only on an explicit history-audit-tooling request.

Punted from BL-006. Scan git history for `feat:`-prefixed commits with no corresponding Build Loop recorded in `.claude/build-progress.json`. Report drift and optionally walk the user through `test-gate.sh --record-feature` reconciliation for each.

**Trigger:** A project onboarding to solo-orchestrator mid-stream wants to audit its git history for past Cutline drift. Today, `test-gate.sh --record-feature` handles one-at-a-time post-hoc recording; BL-012 would batch it.

**Tradeoff:** the hook enforces forward-only by design — the backlog's position is that historical commits don't need retroactive gating. BL-012 only matters if a user explicitly asks for history audit tooling.

**Related:** BL-006 spec § 10; existing `test-gate.sh --record-feature` post-hoc path.

---

## BL-013: Squash-merge server-side enforcement via CI

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Won't Fix (2026-07-05). Cross-host CI parity cost ≫ benefit; the pre-commit gate already catches the common authoring-time drift case.

Punted from BL-006. `gh pr merge --squash` runs on the remote host, outside the PreToolUse hook's reach. Any enforcement there needs CI — a GitHub Actions workflow (and GitLab CI / Bitbucket Pipelines equivalents) that reads the squash-merge commit message and rejects the merge if it's `feat:`-prefixed and the branch never recorded a Build Loop.

**Trigger:** A concrete case where a Cutline item is merged via squash-merge without a matching Build Loop on the branch. Requires solo-orchestrator's host drivers to gain CI-workflow templates for all three hosts.

**Tradeoff:** cross-host workflow parity is non-trivial; secrets and state-file access from CI add complexity. The pre-commit gate catches drift at authoring time, which is the more common failure mode.

**Related:** BL-006 spec § 10; host driver architecture (`scripts/host-drivers/`).

---

## BL-014: Commit-type hygiene enforcement

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Won't Fix (2026-07-10, Karl decision). The BL-072 C1/C2 measurement (Reports/2026-07-10-bl072-warn-dogfood.md: 50% false-positive floor on the simpler prefix+path signal) empirically shows diff-intent inference would misfire worse; the C2 attestation ledger provides the audit trail. Reopen on observed abuse of the commit-type escape route.

Punted from BL-006. Prevent mis-typed commit types — e.g., a real feature disguised as `chore:` or `refactor:` to evade the BL-006 gate. Would require intent inference from the staged diff (lines added to `src/`, new public API surface, new test files asserting behavior) combined with the declared commit-type.

**Trigger:** Observed abuse of the `chore:`/`build:`/`ci:`/`docs:` escape route in BL-006 — i.e., a Cutline feature committed as `chore:` to bypass the gate. Today this is reviewer/author judgment.

**Tradeoff:** intent inference from diffs is brittle and prone to false positives. Likely better addressed by code review norms or an Agent-side lint rather than a pre-commit gate.

**Related:** BL-006 spec § 3 (escape-route decision: Conventional Commits type) and § 10 (out-of-scope note).

---

## BL-015: Pending-approval sentinel reader (Solo side)

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** High
**Status:** Resolved (2026-04-25, PR #16)

Surfaced during the lancache 2026-04-24 incident review. CDF 4.2.3 (`f55c8bc`) introduced `.claude/pending-approval.json` as a sentinel the agent writes when offering structured options to the user; the CDF stop-hook honors it (exits silently, breaking the "Complete these, then finish" pressure loop). Solo's pre-commit-gate currently does NOT honor it — meaning even with the stop-hook silenced, an agent under rationalization pressure can still commit unilaterally. BL-015 closes the symmetric gap.

**Scope (locked during brainstorm 2026-04-24/25):**
- New helper `scripts/pending-approval.sh` with 5 subcommands (`--offer`/`--resolve`/`--clear`/`--status`/`--validate`).
- New `pa_check()` block in `scripts/pre-commit-gate.sh` between `--no-verify` (security) and `--amend` (workflow).
- New bullet in `templates/generated/claude-md.tmpl` Construction Rules.
- New "Structured Decision Points" subsection in `docs/builders-guide.md`.
- One-line changelog note in `scripts/upgrade-project.sh`.
- 17 unit tests + 8 integration tests.

**Locked design parameters:** rich JSON-aware deny reason (parses sentinel, reflects question/options/recommendation back); blocks both `git commit` and `gh pr create`; refuses double-`--offer`; matches CDF's "existence alone suffices" semantics; punts staleness handling (manual `rm` recovery). Position in `pre-commit-gate.sh` chosen so security gates (SOIF_*, no-remote, --no-verify) fire first but workflow gates (--amend, bl006_check) fire after — pending approval upgrades the existing --amend warn into a hard block.

**Upstream dependency:** CDF 4.2.3 — already shipped and verified on 2026-04-25.

**Trigger:** Lancache 2026-04-24 commit-structure rationalization incident. Coupled with the CDF stop-hook fix; both enforcement points needed for the mechanism to be effective.

**Spec:** `docs/superpowers/specs/2026-04-25-pending-approval-sentinel-reader-design.md` (committed 2026-04-25).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-25-pending-approval-sentinel-reader-implementation.md`. Shipped in PR #16 (merged 2026-04-25 at `e9364cf`). New `scripts/pending-approval.sh` helper with 5 subcommands (`--offer`/`--resolve`/`--clear`/`--status`/`--validate`); atomic write via `mktemp + mv`; refuses double-offer. New `pa_check()` block in `scripts/pre-commit-gate.sh` between `--no-verify` (security) and `--amend` (workflow): blocks `git commit` and `gh pr create` when sentinel present, with rich JSON-aware deny reason reflecting question/options/recommendation back to the agent. Falls back to malformed-reason text per CDF 4.2.3 contract. 17 unit tests in `tests/test-pending-approval.sh`, 8 integration tests (E40–E47) in `tests/edge-cases-scripts.sh`. Builder's Guide gets new `### Structured Decision Points` subsection documenting lancache 2026-04-24 incident, lifecycle, and upgrade asymmetry. `claude-md.tmpl` gets new Construction Rules bullet. `upgrade-project.sh` header changelog updated. Security audit `docs/security-audits/bl-015-pending-approval-sentinel-reader-security-audit.md` — 0 open findings.

---

## BL-016: init.sh non-interactive mode (--non-interactive + --config)

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** High
**Status:** Resolved (2026-04-25, PR #19)

Surfaced by UAT 2026-04-25 finding U-A — confirmed by 8 of 13 agents (highest-frequency finding). `init.sh` has only `--dry-run` and `--help` flags; the entire flow is interactive (`prompt_input` / `prompt_choice` for ~15 inputs). Blocks UAT, CI, scripted onboarding, and AI-orchestrator-driven project creation. Agents currently work around this with fragile heredoc drivers that break when prompt order changes (Docker install state, host CLI presence, language list filtering by platform).

**Scope (locked during brainstorm 2026-04-25):**
- New `--non-interactive` mode flag + `--config FILE` (JSON) + `--validate-only` + `--help-non-interactive` + ~12 per-input flags (`--project`, `--platform`, `--track`, `--deployment`, `--gov-mode`, `--language`, `--project-dir`, `--git-host`, `--visibility`, `--remote-url`, `--branch-protection-attested`, `--allow-existing-dir`, `--description`).
- New `collect_inputs_non_interactive()` function in init.sh; existing 2500-line interactive block UNTOUCHED (Approach A — separate code paths).
- Three-pass validation (schema, context-required, resource) with uniform `[FAIL] init.sh non-interactive: ... Reason/Action/Context` error format.
- 4-line surgical change in `create_and_protect_remote()` per host-related variable to check new top-level vars before falling back to `intake-progress.json`/prompts.
- 26 unit tests + 8 integration tests + re-test sweep on 8-10 UAT configs.
- Builder's Guide gets a "Scripted / Non-Interactive Project Initialization" subsection; `claude-md.tmpl` gets one Operations Reference bullet.

**Locked design parameters:** strict mode (separate code path); CLI flags + JSON config (both supported, flag wins on conflict); conditional-required (project/platform/deployment/language always; gov-mode/remote-url/branch-protection-attested by context); fail-fast on missing dependencies (no auto-install); kebab-case-full flag naming; JSON config in `snake_case` matching framework state files.

**Trigger:** UAT 2026-04-25 sweep — 8/13 agents flagged init.sh as the top blocker for scripted UAT/CI. The `prompt_choice` EOF guard (PR #18) was a safety net; this is the proper fix.

**Spec:** `docs/superpowers/specs/2026-04-25-init-sh-non-interactive-design.md` (committed 2026-04-25).

**Follow-ups logged for sibling scripts:** BL-017 (intake-wizard.sh non-interactive), BL-018 (upgrade-project.sh non-interactive), BL-019 (verify-install.sh non-interactive audit).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-25-init-sh-non-interactive-implementation.md`. Shipped in PR #19 (merged 2026-04-25 at `cb7633b`). New `--non-interactive` mode with ~12 per-input flags + JSON `--config FILE` support (flag-overrides-config). Three-pass validation (schema, context-required, resource) with uniform `[FAIL] init.sh non-interactive: ...` error format. New `--validate-only` for smoke-testing without scaffolding. New `--help-non-interactive` reference output. New `collect_inputs_non_interactive()` function + new top-level vars (`GOV_MODE`, `GIT_HOST`, `VISIBILITY`, `REMOTE_URL`, `BRANCH_PROTECTION_ATTESTED`, `ALLOW_EXISTING_DIR`). Surgical changes in `create_and_protect_remote()` so non-interactive resolved values flow through. 26 unit tests in `tests/test-init-non-interactive.sh`, 8 integration tests (E48–E55) in `tests/edge-cases-scripts.sh`. Builder's Guide gets new "Scripted / Non-Interactive Project Initialization" subsection. `claude-md.tmpl` gets new bullet. `upgrade-project.sh` header changelog updated. Existing interactive flow UNTOUCHED (Approach A — separate code paths). Security audit `docs/security-audits/bl-016-init-non-interactive-security-audit.md` — 0 open findings.

---

## BL-017: intake-wizard.sh non-interactive mode

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** Medium
**Status:** Parked — 2026-06-29 recon found no operator demand in 60+ days across 4 waves of intake-wizard work. Field-specific flags shipped piecemeal cover known automation needs: `--data-classification` + `--zdr-attested` (PR #105, tier-crosscheck-6), `--upgrade-to-production` / `--upgrade-track` / `--upgrade-deployment` / `--to-sponsored-poc` / `--to-private-poc` (tier-promotion paths), `--resume` (session continuation). Re-evaluate when a holistic non-interactive harness use case surfaces (e.g., scale scaffolding 100+ projects/day, headless CI Phase-1 setup, AI-agent-driven full Phase-1 automation).

Sibling-script follow-up logged when BL-016 shipped. `scripts/intake-wizard.sh` has `--upgrade-to-production` and `--upgrade-deployment` flags but no overarching `--non-interactive` semantic for the initial intake interview (Sections 1–8 of the wizard). Lower urgency than init.sh because the wizard is typically run once per project; init.sh is the high-frequency entry point.

**Scope (suggested when promoted to spec):** add `--non-interactive` flag mirroring BL-016's design — per-section input flags, JSON `--config FILE` support, three-pass validation, `--validate-only`, uniform error format. Keep the existing interactive flow untouched (Approach A from BL-016).

**Trigger:** an explicit need for scripted intake (CI pipeline that creates many similar projects, agent-driven intake automation).

**Recon evidence (2026-06-29):** `Reports/2026-06-29-backlog-reconciliation-plan.md` § BL-017 recon. `grep -E "non.?interactive|NON_INTERACTIVE|--config" scripts/intake-wizard.sh` finds only audit-comment references, no flag implementation. Tests that exercise intake-wizard use only `--resume` or piped `</dev/null` (the latter only as edge-case fixture). PRs that touched intake-wizard since 2026-04-27 (#83, #99, #104, #105) added field-specific flags or sourceability, never a holistic `--non-interactive` mode.

**Related:** BL-016 spec §12 (out-of-scope items); `Reports/2026-06-29-backlog-reconciliation-plan.md`.

---

## BL-018: upgrade-project.sh non-interactive mode

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** Medium
**Status:** Closed (2026-04-27, PR #33, commit e30759f)

Sibling-script follow-up logged when BL-016 shipped. `scripts/upgrade-project.sh` already has `--track`, `--deployment`, `--to-production`, `--to-sponsored-poc` flags but no overarching `--non-interactive` semantic. Defaults are mostly already non-prompting; the gap is explicit input validation (uniform error format) + `--validate-only` smoke-test mode.

**Scope (suggested):** wrap the existing flag set in a `--non-interactive` mode that adds the BL-016 validation/error/validate-only patterns. Smaller than BL-017 because the underlying flags already exist.

**Trigger:** when scripted upgrades become a frequent operation (post-BL-017 likely).

**Related:** BL-016 spec §12.

---

## BL-019: verify-install.sh non-interactive audit

**Logged:** 2026-04-25
**Category:** Audit
**Severity:** Low
**Status:** Open — DEFERRED 2026-07-05 (revisit next quarter). Opportunistic; bundle with the next `verify-install.sh` visit. No operator demand.

Sibling-script follow-up logged when BL-016 shipped. `scripts/verify-install.sh` already has `--check-only` and `--auto-fix` flags, both of which are arguably non-interactive variants. Audit task: confirm no remaining interactive prompts in those modes. The framework-self-contamination incident (UAT 2026-04-25 U-N) was triggered by `verify-install.sh` running outside a project — the U-N guard in PR #18 prevents that, but the script's "auto-create stub artifacts" remediation behavior (UAT U-M) is also worth re-examining.

**Scope:** read `verify-install.sh` end-to-end; identify any interactive `read`/`prompt_*` calls in `--check-only` or `--auto-fix` paths; if any exist, either remove or guard them behind a non-interactive default.

**Trigger:** opportunistic — pair with the next visit to verify-install.sh code.

**Related:** BL-016 spec §12; UAT 2026-04-25 U-M (verify-install.sh auto-creates stub artifacts when run outside a real project).

---

## BL-020: pre-commit-gate.sh `\bgit\b.*\bcommit\b` regex over-broad

**Logged:** 2026-04-26
**Closed:** 2026-04-27 — commit `b9c4c4c` ("fix(hooks,docs): tighten pre-commit-gate classifier; clarify UAT step semantics (BL-020 + BL-022)"). The classifier was extracted into the named helper `_is_git_commit` in `scripts/pre-commit-gate.sh:81-93` using the anchored regex `(^|[^"'\''])git[[:space:]]+commit\b`; all 6 inline regex call sites (lines 123, 136, 187, 216, 231, 319) were replaced with calls to the helper. Regression coverage: `tests/test-pre-commit-gate-classifier.sh` (6/6).
**Category:** Debt
**Severity:** Medium
**Status:** Closed

`scripts/pre-commit-gate.sh:253` classifies a Bash command as "git commit" via `grep -qE '\bgit\b.*\bcommit\b'`. The regex matches any command line that contains both substrings, not just `git commit` invocations. Concrete false-positives:
- `cat scripts/pre-commit-gate.sh | grep "git commit"` — Claude tries to read the gate's own source while debugging, gets blocked because the command text itself contains both `git` and `commit`.
- `rg "git commit" docs/` — docs grep blocked.
- Multi-command lines like `git status; echo commit` — incidentally tripped.

Effect: when an agent tries to inspect or grep the gate scripts (legitimate read-only debugging), the very gate they're inspecting denies the read. Adds friction during framework debugging sessions.

**Scope:** tighten the classifier. Options:
1. Anchor the regex to actual git invocations: `^(git|.*[;&|]\s*git)\b.*\bcommit\b` and reject any command containing pipes or strings matching the literal `"git commit"` substring as text.
2. Parse the command's first token (post `bash -c` unwrap, post `cd && ...` chain) and only check classification if it's literally `git`.
3. Whitelist read-only invocations (`grep`, `cat`, `rg`, etc.) before applying the classifier.

**Trigger:** opportunistic — fix when next touching `pre-commit-gate.sh`.

**Related:** Surfaced from lancache UAT-2 session 2026-04-26 (operator reported handoff churn). Same hook also has the BL-021 over-blocking behavior.

---

## BL-021: config-guard.sh allowlist excludes read-only `git` subcommands

**Logged:** 2026-04-26
**Closed:** 2026-04-27 — CDF commit `eee6bb3` ("fix(config-guard): allow read-only git inspection of protected paths (BL-021)") on `~/.claude-dev-framework` main. The fix uses exactly the suggested pattern: a read-only `git` subcommand allowlist (`diff|log|show|blame|status|ls-files|cat-file|rev-parse|reflog|describe|name-rev|grep`) placed before the existing `cat|head|...` allowlist at `hooks/config-guard.sh:40-43`. Mutating subcommands (`add`, `checkout`, `restore`, `rm`, `mv`, `commit`, `stash`, `reset`, `clean`, `apply`, `update-ref`) remain blocked. Fixed upstream in CDF per the cross-repo preference; no Solo-side shim needed.
**Category:** Debt
**Severity:** Medium
**Status:** Closed

`~/.claude-dev-framework/hooks/config-guard.sh:41` allows read-only Bash inspection of `.claude/*` files via a hardcoded allowlist: `cat|head|tail|less|more|wc|file|stat|ls|grep|rg|awk|bat`. `git` is absent. Concrete false-positives blocked despite being purely read-only:
- `git diff .claude/manifest.json`
- `git log --oneline .claude/manifest.json`
- `git show HEAD:.claude/manifest.json`
- `git blame .claude/manifest.json`
- `git status .claude/`

Effect: a debugging Claude session can't inspect the history or current diff of framework state files, so investigations of "why did manifest end up like this" require operator handoff. Same handoff-churn pattern as BL-020.

Note: write-side `git` commands (`git add`, `git checkout --`, `git restore`, `git rm`, `git mv` against `.claude/*` paths) MUST stay blocked — those mutate framework state. Allowlist must distinguish read-only subcommands from mutating ones.

**Scope:** extend the allowlist to recognize specific read-only `git` subcommands. Suggested patterns:
```bash
if echo "$COMMAND" | grep -qE '^\s*git\s+(diff|log|show|blame|status|ls-files|cat-file|rev-parse|reflog|describe|name-rev|grep)\b'; then
  exit 0
fi
```
(Place before the existing `cat|head|...` allowlist.) Keep existing block on `git add`, `git checkout`, `git restore`, `git rm`, `git mv`, `git commit`, `git stash`, etc.

**Trigger:** ship together with BL-020 (same hook-author surface) OR opportunistic during next CDF maintenance pass.

**Related:** Lives in CDF (`~/.claude-dev-framework/hooks/config-guard.sh`) — fix upstream per the cross-repo preference (memory `feedback_cross_repo_fixes.md`); a Solo-side shim is not appropriate here. BL-020 is the symmetric Solo-side issue.

---

## BL-022: UAT step semantics ambiguous — `remediation_complete` and `gate_passed` framing

**Logged:** 2026-04-26
**Closed:** 2026-04-27 — commit `b9c4c4c` (same commit as BL-020 — "fix(hooks,docs): tighten pre-commit-gate classifier; clarify UAT step semantics (BL-020 + BL-022)"). `docs/builders-guide.md:1252-1259` now carries the unambiguous framing: `remediation_complete` = "all remediation work is written and tested locally" (NOT "merged to remote"), with the explicit caution "Do NOT wait for the commit/PR to mark this — that creates the chicken-and-egg confusion"; `gate_passed` = "test-gate has been re-cleared locally" (NOT post-merge CI state). The intended workflow (write → tests green → `--reset-counter` → mark `remediation_complete` → mark `gate_passed` → commit → push → PR) is documented step-for-step.
**Category:** Debt (docs/guidance)
**Severity:** Medium
**Status:** Closed

UAT_STEPS as defined in `scripts/process-checklist.sh:30` are: `agents_dispatched template_generated orchestrator_notified results_received completeness_verified bugs_consolidated triage_complete remediation_complete gate_passed`. The last two have ambiguous framing in the framework's docs:

- `remediation_complete` — Does this mean (a) "all fix code has been written and tests are green locally" or (b) "all fixes are merged to main"? The `process-checklist.sh:900` gate blocks source commits while `uat_completed < 9`, which implies (a) — fixes must be marked complete BEFORE the commit that ships them. But agents reading the step name as "shipped to remote" hit a logical contradiction (can't mark complete until commit, can't commit until marked complete).

- `gate_passed` — Does this mean (a) "test-gate counter has been reset and tests pass locally" or (b) "test-gate is green post-merge"? Same ambiguity.

Effect: a recent lancache UAT-2 agent session (2026-04-26) spent 19+ minutes in handoff-theater churn because the agent read interpretation (b), concluded marking before committing was "borderline" and "tripping framework intent", and bounced commits back to the operator instead of completing the documented sequence.

The framework's intended workflow is:
1. Write fixes locally; tests green.
2. Run `scripts/test-gate.sh --reset-counter`.
3. Mark `remediation_complete` (truthful: local fixes done).
4. Mark `gate_passed` (truthful: counter reset, tests green).
5. Commit; gate now allows source commits.
6. Push, open PR.

**Scope:** clarify in `docs/builders-guide.md` (or wherever UAT_STEPS are documented) that:
- `remediation_complete` means "local remediation work done; ready to commit." NOT "shipped."
- `gate_passed` means "local gate-check passing; ready to commit." NOT "post-merge CI green."
- The commit-blocker at `process-checklist.sh:900` is intentional: it forces operators to acknowledge the local remediation state before committing during UAT, NOT to gate the commit on post-merge state.
- Optionally: rename to `remediation_done_locally` / `gate_passed_locally` for sharper semantics.

**Trigger:** before the next UAT cycle in any project (lancache, solo-orchestrator self-test, downstream project).

**Related:** Surfaced from lancache UAT-2 session 2026-04-26. Pairs with BL-020 + BL-021 (all three contributed to the same handoff-churn incident). The `pre-commit-gate.sh` flow at line 250-275 implements the actual gate behavior.

---

## BL-023: Rev3 runbook `$GOV` unquoted expansion is fragile

**Logged:** 2026-04-27
**Category:** Debt (cosmetic)
**Severity:** Low
**Status:** Closed (2026-07-05, commit `10767d6`, low/minor sweep) — fixed in `Reports/uat-2026-04-26/RUNBOOK.md` (the backlog's `uat-2026-04-26-rev3/` path never existed); split into `$GOV_FLAG`/`$GOV_VALUE` invoked via `${GOV_FLAG:+$GOV_FLAG "$GOV_VALUE"}`.

The rev3 sweep runbook at `Reports/uat-2026-04-26-rev3/RUNBOOK.md` Section A constructs the init.sh invocation with `$GOV` unquoted between flags:

```bash
bash "$FRAMEWORK/init.sh" --non-interactive ... $GOV --language ...
```

When `GOV="--gov-mode production"`, word-splitting produces two args (`--gov-mode`, `production`) — works in bash but is shell-fragility on the glide path. Under stricter shells or when the value contains spaces in the option text, this breaks.

Surfaced by rev3 sweep agent 7 as a documentation gap. All 12 rev3 agents successfully ran the existing form, so this is cosmetic, not blocking.

**Scope:** rewrite Section A's invocation to use an array or split `$GOV` into `$GOV_FLAG $GOV_VALUE`:

```bash
GOV_FLAG=""
GOV_VALUE=""
case "{SCENARIO}" in
  private_poc)   GOV_FLAG="--gov-mode"; GOV_VALUE="private_poc" ;;
  sponsored_poc) GOV_FLAG="--gov-mode"; GOV_VALUE="sponsored_poc" ;;
  production)    GOV_FLAG="--gov-mode"; GOV_VALUE="production" ;;
esac
bash "$FRAMEWORK/init.sh" --non-interactive ... ${GOV_FLAG:+$GOV_FLAG "$GOV_VALUE"} --language ...
```

Apply to any future runbook templates as well; the existing rev1/rev2 runbooks have the same shape and could be updated opportunistically.

**Trigger:** before the next sweep runbook is written.

**Related:** `Reports/uat-2026-04-26-rev3/TRIAGE.md` Gap 1.

---

## BL-024: `init.sh --branch-protection-attested` not recorded when push fails on `--git-host other`

**Logged:** 2026-04-27
**Category:** Debt (real bug)
**Severity:** Medium
**Status:** Resolved (2026-04-27, PR #38)

**Resolution:** `init.sh::create_and_protect_remote` reordered so the attestation prompt + record block runs BEFORE `git push` on the `--git-host other` path. Push failure no longer drops the attestation. New `tests/test-init-other-host-attestation.sh` covers the regression (2 cases: attestation persists on push failure, regression check that the flag is still required).

`init.sh::create_and_protect_remote` for the `--git-host other` path has the wrong order of operations relative to `--branch-protection-attested`. The flow at `init.sh:1768-1836`:

1. Resolve `remote_url` (from `--remote-url` or interactive prompt).
2. `git remote add origin "$remote_url"`.
3. `git push -u origin main || git push -u origin master`. **If push fails → `return 1`.**
4. Print "Since 'other' host is not API-verifiable, attest branch protection:".
5. Honor `BRANCH_PROTECTION_ATTESTED` (or prompt) → record attestation in `.claude/process-state.json::phase2_init.attestations.branch_protection`.

When the operator passes `--remote-url https://example.invalid/fake.git --branch-protection-attested` (the standard rev1/rev2/rev3 sweep pattern), the push at step 3 fails and the function returns 1 BEFORE the attestation block at step 4-5 runs. Init still completes overall (the U-B fix at `init.sh:1717-1730` wraps the call in `if ! ...`), but `phase2_init.attestations.branch_protection` is never written.

Reproduced 2026-04-27:

```
tmp=$(mktemp -d) && bash init.sh --non-interactive --project trace --platform web \
  --deployment personal --language typescript --git-host other \
  --remote-url https://example.com/fake.git --branch-protection-attested \
  --visibility private --project-dir "$tmp/proj" --allow-existing-dir
jq '.phase2_init.attestations // "MISSING"' "$tmp/proj/.claude/process-state.json"
# → "MISSING"
```

Real-world impact: with a real remote URL the push usually succeeds and the attestation IS recorded — so this hasn't been seen by users yet. But anyone running init in a context where the push fails (corporate firewall, momentary connectivity, fake URL for CI smoke-test) gets:
- init log says "Remote setup did not complete cleanly" and points at `check-gate.sh --repair`
- `process-state.json` lacks the attestation
- subsequent `check-gate.sh --preflight` (post-PR-#36) won't honor the attestation it never recorded
- `verify-init` will then report `branch_protection_configured` as failed

**Scope:** reorder the "other" branch in `create_and_protect_remote` so attestation runs BEFORE push (or alongside it as a checkpoint), since attestation is a forward-looking commitment by the operator and is independent of whether the push succeeds. Specifically:

1. Move the attestation prompt + record block to run AFTER `git remote add` but BEFORE `git push`. The attestation describes what the operator commits to — push success isn't a precondition.
2. Optionally: don't `return 1` on push failure when `BRANCH_PROTECTION_ATTESTED=true` — the operator has explicitly attested they'll set up the remote later, so log `print_warn` and continue.

TDD: a focused test in `tests/test-init-no-remote-creation.sh` (or sibling) that runs the repro flow and asserts `phase2_init.attestations.branch_protection.attested_by == "orchestrator"` after init.

**Trigger:** if a user reports init.sh "lost" their attestation, OR before any sweep that depends on the attestation being present in process-state.json. Lower priority than the user-facing tier-3 backlog items because the rev1/rev2/rev3 runbooks all worked around it (manual `jq` writes in agent test setup) — but it's a real correctness gap.

**Related:** `Reports/uat-2026-04-26-rev3/TRIAGE.md` Gap 2 (agent 2). Pairs conceptually with PR #36 (BL-002) which added a parallel attestation flow for github free-tier 403 — that one DOES record correctly because it runs after host_configure_protection completes (success or specific 403), not after a push.

---

## BL-025: Phase 2 init-verified state setup helper for tests

**Logged:** 2026-04-27
**Category:** Proposal (test infrastructure)
**Severity:** Low
**Status:** Open — demoted to OPPORTUNISTIC 2026-07-09 (was "build first in the gate wave"). The scheduling premise is obsolete: it assumed BL-073's regression tests needed seeded gate state, but BL-073 shipped (PR #146) using plain heredoc fixtures. Build this helper the first time a gate-wave test actually needs Phase-2-verified state (see `docs/handoffs/2026-07-09-gate-wave-execution-handoff.md` WP-D3); do not build speculatively.

Several T2 + R3 test cases needed to drive a project to "Phase 2 init verified" state to exercise the gates that depend on it (the dep-manifest classifier in `process-checklist.sh::check_commit_ready`, the build_loop gate, the UAT step semantics, the `--start-phase3` advance). The current happy path takes a real init + Phase 1 walk + 6 phase2_init `--complete-step` calls + manual `data_model_applied` mark + `initialization_verified` auto-complete. Both rev3 agents 2 and 6 had to do manual `jq` patching to reach the right state.

**Scope:** a `tests/test-helpers/init-phase2-verified.sh` helper that takes:
- a target tempdir path
- platform / track / deployment / gov_mode args (same shape as init.sh)
- shortcut flags for state-only setup (skip CLAUDE.md generation, skip framework clone, etc.)

…and produces a directory with `.claude/manifest.json`, `.claude/phase-state.json` (current_phase=2), `.claude/process-state.json` with `phase2_init.verified=true`, and the minimum filesystem artifacts (`.git/`, `package-lock.json` or equivalent, `.git/hooks/pre-commit`) so `verify-init` would mark it complete.

This isn't a public-facing helper — it's purely for the test suite. Could live alongside `tests/` or in a sibling `tests/helpers/` directory.

**Trigger:** when adding the next test that needs phase 2 verified state (e.g., a test for any post-T2 fix that depends on the gate context).

**Related:** `Reports/uat-2026-04-26-rev3/TRIAGE.md` Gap 3. Adjacent to BL-003 (end-to-end init.sh tests against mocked host CLIs) — same "make init.sh testable in a fresh tempdir" theme.

---

## BL-029: Bypass audit-log infrastructure

**Logged:** 2026-04-27 (calibration agent 5)
**Category:** Bug + Feature (correctness)
**Severity:** Critical
**Status:** Closed (2026-06-26, PR #46, commit 5d1996b; bypass-audit infrastructure shipped earlier via PR #40 (2026-05-04) and PR #41 (2026-05-14))

PostToolUse + Stop bypass-shaped-language detector writes structured rows to `.claude/bypass-audit.json`, plus a confirmation-phrase sentinel and the `escalate-to-user.sh` documented alternative. Always-on regardless of enforcement_level.

**Plan:** `docs/superpowers/plans/2026-04-28-bl029-bypass-audit-plan.md`
**Spec:** Agent-5 calibration deliverable at `Reports/uat-2026-04-27-calibration/results/agent-5.json`
**Audit follow-up:** PR #46 corrected hook envelope schema (`tool_result` → `tool_response`, `transcript` → `last_assistant_message`) and updated plan docs to match canonical Claude Code schema.

---

## BL-030: User-terminal enforcement model

**Logged:** 2026-04-28 (calibration brainstorm)
**Category:** Feature (process enforcement)
**Severity:** High
**Status:** Closed (2026-06-26, PR #48, commit 328c9c7; follow-ups PR #49, PR #51, PR #54)

Three-tier enforcement level (`no` / `light` / `strict`) configurable at init or via `reconfigure-project.sh --enforcement-level`. Tier semantics:

- **strict** (default + forced for sponsored_poc / production tiers): installs `.git/hooks/framework-gate.sh`, which sources `scripts/lib/enforcement-level.sh` + delegates to `process-checklist.sh --check-commit-ready` and `pre-commit-gate.sh --terminal-mode`. Block messages carry the W5/P1 teaching pattern (block reason + principle + procedure) sourced from `scripts/lib/gate-principles.sh`. `--no-verify` bypasses the gate but is captured by the SessionStart detector.
- **light**: same SessionStart detector; no filesystem gate; user-terminal commits land freely but are recorded in `.claude/bypass-audit.json`.
- **no**: detector self-no-ops; only Claude-side audit (BL-029) remains.

**Components shipped (PR upcoming):**
  - `scripts/lib/enforcement-level.sh` (read_enforcement_level, assert_choosable, validate_transition)
  - `scripts/lib/gate-principles.sh` (principle_for "<gate>")
  - `scripts/hooks/record-claude-commit.sh` (PostToolUse Claude-commit ledger)
  - `scripts/detect-out-of-band-commits.sh` (SessionStart out-of-band detector)
  - `scripts/install-filesystem-gates.sh` (idempotent installer/uninstaller for `.git/hooks/framework-gate.sh`)
  - `scripts/pre-commit-gate.sh --terminal-mode` flag for framework-gate composition
  - `init.sh` `--enforcement-level` + `--confirm-pitfalls` non-interactive flags + finalization (manifest merge, detection baseline, audit row, filesystem-gate install if strict)
  - `scripts/reconfigure-project.sh --enforcement-level` + `--reset-detection-baseline` transition flags
  - SessionStart + PostToolUse hook entries in the project template's `.claude/settings.json`
  - Test coverage: enforcement-level lib 10/10, record-claude-commit 5/5, out-of-band-detector 8/8, filesystem-gate-install 7/7, pre-commit-gate terminal-mode 3/3, gate-principles 3/3, init UX 8/8, reconfigure 7/7, bypass-audit schema 3/3, calibration replay 4/4 — 58/58 across the new BL-030 suites.

**Plan:** `docs/superpowers/plans/2026-04-28-bl030-enforcement-model-plan.md` (Task 1–12, executed as a single PR).
**Spec:** `docs/superpowers/specs/2026-04-28-bl030-enforcement-model-design.md`

**Audit follow-up:** the v2 audit finding `specs-plans-bl029-bl030-3` ("spec exists; ZERO implementation") is now closed.

**Audit follow-up:** the v2 audit finding `specs-plans-bl029-bl030-5` ("naive substring match in `scripts/hooks/record-claude-commit.sh` + missing --amend handling") is now closed. The BL-029 ledger recorder now uses the anchored regex `(^|[^"'\''])git[[:space:]]+commit\b` (verbatim sibling of the BL-020 fix in PR #53 on `scripts/pre-commit-gate.sh:81-93`), rejecting quote-preceded false-positives like `grep "git commit"`. `git commit --amend` is treated as a fresh ledger entry (option C from the audit response) — the amended SHA is recorded so the out-of-band detector classifies it as Claude-issued, and the original entry persists harmlessly as an orphan SHA in the append-only ledger. Regression coverage: `tests/test-record-claude-commit.sh` T6-T9 (9/9 total).

---

## BL-031: init.sh:2009 hardcodes GitHub-branded messaging for any driver returning exit 3

**Logged:** 2026-06-27
**Category:** Bug (UX, cross-driver)
**Severity:** Medium
**Status:** Closed — shipped 2026-06-27 (PR #65, commit `b2e080b`).

`scripts/host-drivers/gitlab.sh:120` returns exit 3 from `host_configure_protection` when the org-mode approvals PUT fails. `init.sh:2009` treats `_hcp_rc=3` as the GitHub-free-tier attestation fallback and surfaces a print_warn with the literal string `"Branch protection unavailable on this repo (free-tier limit)"` plus a print_info chain mentioning `"Upgrade to GitHub Pro"`. A GitLab user with partial token scopes lands in the wrong remediation flow with wrong-host messaging.

The exit code 3 was originally a github-specific signal ("free-tier 403 detected — fall back to attestation"). When the gitlab driver was added, exit 3 was reused for a different semantic (gitlab approvals PUT failed) without the init.sh dispatch being updated to disambiguate.

**Resolution:** option 1 (host-agnostic init.sh wording). The init.sh exit-3 branch (lines ~1998-2045) now parameterizes the warn/info on `$host` ("Branch protection unavailable via standard API on this $host repo" / "see $host driver remediation message above") and defers host-specific remediation to the driver's own stderr — which is already emitted before init.sh prints these lines. The driver code (github.sh:120-132, gitlab.sh:120) was deliberately not touched: the exit-3 contract ("I failed in a way you can attest around") is correct; the bug was init.sh interpreting that contract with GitHub-only words. The attestation reason string `github_free_tier` is retained for backward compat with `scripts/check-gate.sh` and `tests/test-check-gate.sh::T5`; broadening the reason taxonomy is out of scope for this fix.

**Regression test updated:** `tests/host-drivers/e2e-init-gitlab.test.sh::T6` now asserts the corrected behavior: init exits 0 (U-B contract preserved), log does NOT contain "GitHub Pro" or "free-tier limit", log DOES contain `"on this gitlab repo"` / `"gitlab driver remediation"` plus the gitlab driver's own `"approvals config failed"` stderr.

**Verification:** `tests/host-drivers/e2e-init-gitlab.test.sh` 6/6 PASS · `tests/host-drivers/e2e-init.test.sh` 5/5 PASS (github regression) · `tests/test-github-free-tier-403.sh` 4/4 PASS (driver unchanged).

**Related:** BL-003a (introduced the T6 detection test).

---

## BL-003a: init.sh GitLab end-to-end test (mocked CLI)

**Logged:** 2026-04-22 (originally as BL-003 sub-task; split for cycle 5 scope)
**Status:** Closed — shipped 2026-06-27 (PR #61, commit `fc9db0e`).

Adds `tests/host-drivers/e2e-init-gitlab.test.sh`: full init.sh e2e with mocked `glab` CLI + `GIT_CONFIG_GLOBAL` `pushInsteadOf` redirect to a local bare repo. Mirrors PR #59's github harness. Six scenarios: T1 personal success, T2 org success, T3 push fail, T4 repo-already-exists, T5 protection POST 403, T6 (documentary) gitlab-exit-3 cross-wiring at `init.sh:2009` — see BL-031.

---

## BL-003b: init.sh Bitbucket end-to-end test (curl-stub variant)

**Logged:** 2026-04-22 (originally as BL-003 sub-task; split for cycle 5 scope)
**Status:** Closed — shipped 2026-06-27 (PR #62, commit `c8585fa`).

Adds `tests/host-drivers/e2e-init-bitbucket.test.sh`: full init.sh e2e with mocked `curl` (bitbucket driver uses curl with `-u USER:PASS`, no CLI binary). PATH-prepended `curl` stub case-matches on `-X METHOD` + URL substrings (repo create POST, branch-restrictions GET/POST/DELETE). Configure-vs-verify GET ambiguity (same URL hit twice) resolved with a `$TMP`-side counter file. Five scenarios parallel to BL-003a (T1 personal success, T2 org success, T3 push fail, T4 slug-already-exists, T5 protection POST 403); no bitbucket analogue of BL-003a T6 because bitbucket has no exit-3 cross-wired branch — the BL-031 cross-wiring is gitlab-specific.

**Cycle 5 verifier watch-outs honored in the stub:**

  1. `scripts/host-drivers/bitbucket.sh::_bb_curl` pipes `2>&1` and the caller does `if ! resp=$(... | _bb_curl ...)`, so the stub MUST write stderr only on intentional failure modes — otherwise jq parses the error message as JSON and crashes the success path. Stub gates all stderr emission behind `if [ "$rc" -ne 0 ]` arms.
  2. POST/DELETE-with-body callsites pipe a JSON payload (`echo "$payload" | _bb_curl POST URL`); stub drains stdin (`cat >/dev/null`) on every POST arm including the failure path.
  3. `host_configure_protection` and `host_verify_protection` both GET `/branch-restrictions?pattern=main`. Counter file in `$TMP` disambiguates: first GET serves `MOCK_BB_PROTECT_GET_JSON_CONFIGURE` (default `{"values":[]}` — no prior restrictions), subsequent GETs serve `MOCK_BB_PROTECT_GET_JSON_VERIFY` (per-mode JSON satisfying `host_verify_protection`'s kind-count checks).

---

## code-upgrade-project-8: upgrade-project.sh --to-production deferred pre-condition guard

**Logged:** 2026-06-27 (cycle 6 verifier)
**Category:** Bug / governance
**Severity:** Major
**Status:** Closed — shipped 2026-06-27 (PR forthcoming, this commit).

`scripts/upgrade-project.sh --to-production` unconditionally flipped `POC_REMOVED=true` whenever the project had a `poc_mode` (lines 735-737), with no check that the deferred Pre-Phase-0 pre-conditions had actually been cleared. `docs/governance-framework.md:248` simultaneously promised the script "re-runs Section 8 of the intake wizard to capture the deferred pre-conditions" — a fictional control. Per `docs/governance-framework.md:230` Sponsored POC defers 3 of 6 Pre-Phase-0 items (insurance, liability, ITSM, backup maintainer; AI deployment path, sponsor, time-boxed exit criteria are upfront) and Private POC defers all 6; Production requires all 6 cleared.

**Resolution:** Inserted a gate in `scripts/upgrade-project.sh` that runs when `TO_PRODUCTION=true && CURRENT_POC_MODE != "" && CURRENT_DEPLOYMENT == organizational`. The gate parses the Pre-Phase 0 table in `APPROVAL_LOG.md`, walks rows 1-6, and counts a row satisfied when the Date column contains an ISO date `YYYY-MM-DD`. Parser uses awk-scoped section-walk (not the brittle `grep -A 30 ... | grep -c` pattern that PR #53 sanitized). Personal deployments skip the gate because `templates/generated/approval-log-personal.tmpl` pre-fills all 6 rows with `__TODAY__` at init. Operators driving `--non-interactive` can acknowledge missing rows via `--ack-preconditions=<N1,N2,...>` (validated to `^[1-6](,[1-6])*$`); each ack writes an `actor: "user_terminal"` row to `.claude/bypass-audit.json` with `details.action = "to_production_preconditions_acked"`. Failure mode emits a structured `_upgrade_fail` listing the missing row numbers AND their canonical Pre-Condition labels. `docs/governance-framework.md:248` downgraded to describe the gate-only behavior (no wizard re-run claim). 6 new tests in `tests/test-upgrade-to-production-preconditions.sh`; `tests/test-upgrade-paths.sh` T1 fixture seeded with a filled APPROVAL_LOG.md to keep the happy path green.

---

## code-check-gates-1: check-phase-gate.sh Phase 1→2 backstop ignores github_free_tier attestation

**Logged:** 2026-06-28 (cycle 7 slot 1)
**Category:** Bug / governance (silent-bypass-shaped false-fail)
**Severity:** Major
**Status:** Closed — shipped 2026-06-28 (PR forthcoming, this commit).

`scripts/check-phase-gate.sh:279-305` (the Phase 1→2 BACKSTOP block) unconditionally invoked `host_verify_protection "main" "$mode"` whenever `current_phase >= 2`, without first consulting `.claude/process-state.json::phase2_init.attestations.branch_protection.reason`. On legitimate github free-tier private repos — the demographic that BL-002 (PR #36) and BL-031 (PR #65) wired the attestation flow to support — the GitHub API returns 403 *"Upgrade to GitHub Pro or make this repository public to enable this feature."*, host_verify_protection returns non-zero, and the backstop emitted `[FAIL] Phase 1→2 backstop: protection verification failed` AND incremented the gate's `$issues` counter, causing the script to exit 1.

Operator-visible symptom: `scripts/check-gate.sh --preflight` PASSED (it correctly honors the attestation at `cmd_preflight:52-64`) while `scripts/check-phase-gate.sh` FAILED at the same moment with the same project state. Contradictory signals; the `[FAIL]` is structurally a silent-bypass-shaped false-fail (the gate "fails" without actionable remediation — the operator already attested at init time).

**Resolution:** ~10-line additive fix in `scripts/check-phase-gate.sh` mirroring the canonical pattern at `scripts/check-gate.sh::cmd_preflight` (lines 52-64). A new pre-check inside the Phase 1→2 backstop block reads `.claude/process-state.json::phase2_init.attestations.branch_protection.reason` via jq. When the value equals `github_free_tier`, the gate prints an `[OK]` line ("branch protection attested ... upgrade to GitHub Pro to enable API enforcement") and SKIPS the `host_verify_protection` call entirely (does not increment `$issues`). The existing `if host_load_driver` / `if host_verify_protection` branches are preserved as the else-arm — projects without an attestation continue to be verified against the live host API exactly as before. No broadening to `other_host_attestation` (per cycle 7 verifier scope: gate to known-good values only).

**Regression coverage:** new `tests/test-check-phase-gate-backstop-attestation.sh` with three cases:
- **T1 positive:** Phase-2 project + `manifest.json {host:"github", mode:"personal"}` + dated APPROVAL_LOG.md + process-state.json with `branch_protection.reason="github_free_tier"`. PATH-prepended `gh` stub returns 403 on any `/protection` GET (proves the test would FAIL without the fix). Assert backstop emits OK line and does not emit the FAIL line.
- **T2 negative (regression guard):** same shape WITHOUT the attestation; same gh stub. Assert backstop FAIL line surfaces and exit code is non-zero. Proves the fix did not over-broadly skip verification.
- **T3 coexistence:** runs `tests/test-check-gate.sh` end-to-end (incl. T5 `t5_preflight_honors_free_tier_attestation`) to confirm the canonical preflight contract is preserved across both scripts.

**Verification:** new suite 3/3 · `tests/test-check-gate.sh` 5/5 · `tests/test-check-phase-gate-counter-sanitizer.sh` 7/7 · `tests/test-init-other-host-attestation.sh` 2/2 · `tests/test-github-free-tier-403.sh` 4/4. Registered in `tests/full-project-test-suite.sh` (new TEST 0c section after the counter-antipattern lint, to keep the gate-validation backstops co-located).

**Related:** BL-002 (PR #36) introduced the attestation flow; BL-031 (PR #65) generalized cross-host attestation messaging; PR #71 (preflight branch) shipped the canonical pattern this fix mirrors. The case-sanitizer pattern from PR #53 was considered but not needed here — the jq output is used in a string equality test, not arithmetic, so no sanitizer is required.

---

## BL-032: Handle gitlab.com Free org-mode required-approvals 403 gracefully

**Logged:** 2026-06-28
**Category:** Debt
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #134, commit `bfc7ff2`; tightening commit `1edf187` addresses verifier minor_concerns findings 5a + 5b) — proactive `--approvals-attested` / `SOLO_APPROVALS_ATTESTED=1` shortcircuit shipped alongside the existing exit-4 reactive path; `gitlab_free_tier_approvals` attestation reason honored by `scripts/check-gate.sh` (--preflight, --repair) + `scripts/check-phase-gate.sh` Phase 1→2 backstop; `docs/builders-guide.md` § Repository Setup documents both escape hatches. Test coverage: `tests/test-bl032-gitlab-free-approvals-attestation.sh` (8 cases including T4b for --repair + mutation proof), plus new gitlab_free_tier_approvals case in `tests/test-check-phase-gate-backstop-attestation.sh` mirroring the github_free_tier pattern. All wired into `tests/full-project-test-suite.sh` per BL-034.

GitLab analog of BL-002. On gitlab.com Free, `PUT projects/:id/approvals` with `approvals_before_merge>=1` is a Premium-tier feature — Free returns HTTP 403 *"This feature is not available on your plan."* (exact wording has varied across GitLab releases — "premium", "ultimate", "not available on your plan", "feature is not available", "requires .* plan"). Organizational deployments on gitlab.com Free cannot clear the Phase 1→2 protection bar because the required-approvals invariant is structurally unavailable.

The driver remediation (this PR, `fix/host-gitlab-ci-status-stderr-approvals`) addresses the operator-recovery side: it pattern-matches the Premium-only response, returns a dedicated exit code (4), and prints a structured remediation listing upgrade / self-hosted / attestation-escape-hatch options. What's still open is the third option — the attestation flow itself.

**Scope:** In `scripts/host-drivers/gitlab.sh` and `scripts/init.sh`:
1. Add a `--approvals-attested` flag (and `SOLO_APPROVALS_ATTESTED=1` env var) honored by `host_configure_protection`. When set in org mode, skip the approvals PUT and record an attestation in `.claude/process-state.json::phase2_init.attestations.branch_protection.reason = "gitlab_free_tier_approvals"`.
2. Extend `scripts/check-phase-gate.sh` Phase 1→2 backstop to honor the new attestation reason (mirroring the existing `github_free_tier` branch added in PR #62 — see code-check-gates-1 entry above).
3. Update `docs/builders-guide.md` § Repository Setup to document the GitLab Free tier limitation alongside the existing GitHub free-tier note (line ~933).

The CI pipeline-success gate (code-host-gitlab-2 / `only_allow_merge_if_pipeline_succeeds`) is NOT Premium-gated on gitlab.com Free, so this BL is scoped strictly to the approvals API.

**Trigger:** Before the first organizational deployment on gitlab.com Free attempts `init.sh` in `org` mode.

**Related:** code-host-gitlab-8 audit finding (the gap that triggered this entry); BL-002 (the GitHub analog this mirrors); code-check-gates-1 (the canonical attestation-honoring backstop pattern this should reuse).

---

## BL-033: Migrate multi-stage install_cmds in templates/tool-matrix/*.json to structured shapes

**Logged:** 2026-06-28 (PR #92 verifier follow-up)
**Category:** Debt / Security hardening
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #136, commit `61fb989`) — schema-forward shipment. Consumer-side migration to array shape (gitleaks / rust / k6 wrapper scripts + the three current singular-`install_cmd` readers) tracked as [[bl069-install-cmds-consumer-migration]].

**Resolution:** `scripts/resolve-tools.sh` now accepts both shapes at
`install.<key>`: a legacy string (`"brew install jq"`) or a structured
array of stages (`["brew install colima", "brew services start colima"]`).
The resolver output emits BOTH `install_cmd` (joined with ` && ` for
back-compat) AND `install_cmds` (JSON array of stages) so new consumers
can iterate stages structurally. Malformed shapes surface loudly:
empty arrays, non-string array elements, and objects with both
`install_cmd`+`install_cmds` sibling keys are all refused with a clear
per-tool diagnostic. The stateless multi-stage entries — Docker
(linux_apt/dnf/pacman) and Colima (darwin_brew) — are migrated to the
array shape. The remaining state-carrying entries (gitleaks, rust
rustup, k6 apt-repo dance) still fail the Layer 2 metachar gate and
should be migrated to wrapper scripts under `scripts/install-helpers/`
in a follow-up; the array-shape schema is now available as their
target. Test coverage: `tests/test-bl033-install-cmds-shape.sh`
(8 tests including T-back-compat, T-array-happy, T-array-fail-fast,
T-mixed-invalid, T-empty-array, T-non-string-elements,
T-migrated-entries, T-migrated-semantics + mutation proof).

Following the structured-dispatch hardening in `scripts/verify-install.sh::fix_tool_install` (PR #92 verifier blocker-1 close), the legacy `bash -c` fallback now REFUSES any install_cmd whose payload contains shell-chaining metacharacters (`;`, `|`, `` ` ``, `$(`, `<`, `>`, newline). Several existing tool-matrix entries use multi-stage shell pipelines that trip this gate:

- `gitleaks.install.linux_apt` (+ `linux_dnf` + `linux_pacman`) — `GITLEAKS_VERSION=$(curl ...) && curl ... | sudo tar -xz -C /usr/local/bin gitleaks`
- `k6.install.linux_apt` — `sudo gpg ... && echo 'deb ...' | sudo tee /etc/apt/sources.list.d/k6.list && sudo apt update && sudo apt install k6`
- `rust.install.darwin_brew` (+ `linux_apt`) — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source "$HOME/.cargo/env"`
- `context7.install.npm` — `echo y | claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest` (bare `|` trips the gate)

Note: `docker.install.linux_apt` uses `sudo apt install ... && sudo usermod ...` — the `&&` is stripped before the metachar check, so this currently passes Layer 2 unchanged (but a future tightening should still consider migrating it for clarity).

**Scope:** Each entry needs either (a) a small wrapper script in `scripts/install-helpers/<tool>.sh` that the install_cmd invokes by absolute path (turning the multi-stage shell into a single argv invocation), or (b) the install delegated to a sanctioned package source (e.g. k6's official apt repo via cloud-init style provisioning). The wrapper-script approach preserves the structured-dispatch contract: the install_cmd becomes `bash scripts/install-helpers/gitleaks.sh` which Layer 1 doesn't currently match but Layer 2's metachar gate passes.

**Workaround until migrated:** operators on these tools currently see the DEPRECATED warning and a REFUSED install. Manual install per the matrix's `manual` instructions still works.

**Related:** PR #92 verifier review (blocker-1 close). VERIFY_INSTALL_NO_LEGACY_DISPATCH=1 env var exists for operators who want to enforce structured-only mode immediately.

---

## BL-042: init.sh `prompt_install` interaction with pipefail when stdin is closed

**Logged:** 2026-06-29 (PR #104 verifier follow-up — Wave 4 risk note 2)
**Category:** Bug / non-interactive UX (test-only workaround in tree)
**Severity:** Low (workaround in place; affects test ergonomics, not user-facing behavior)
**Status:** Open — DEFERRED 2026-07-05 (revisit next quarter). Test-only workaround already in tree; user-facing `--non-interactive` behavior is sound.

When `init.sh --non-interactive` is invoked from a test harness with a piped/heredoc stdin (e.g. `printf 'Y\n...' | bash init.sh ...`), the `prompt_install` helper at `scripts/lib/helpers.sh:295-324` interacts poorly with `set -o pipefail` in two ways:

1. `prompt_install` checks `[ ! -t 0 ]` at line 306 to detect non-interactive context and returns 1 (no install). When stdin is a `printf`-fed pipe rather than a tty, the gate fires correctly — but the *test* expects the install to proceed (or be silently skipped without error).
2. Some upstream callers chain `printf | bash init.sh` directly. Under `pipefail`, if init.sh exits before consuming the full stdin, the upstream `printf` receives SIGPIPE and exits 141 — which propagates through the pipeline and fails the parent command. Tests work around this by using process substitution (`< <(printf 'Y\nY\n...')`) so each program reads its own fd without a true pipe.

**Current workaround (test-side, in tree):**
- `tests/test-init-organizational.sh:50,146` — `< <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n')` feeds finite stdin.
- `tests/edge-cases-scripts.sh:983,1083` — same shape.
- The PR-#104 body explicitly notes this as a worked-around bonus catch.

**Proposed source fix (deferred):**
- Audit `prompt_install` and its callers so the non-interactive path is the *only* path that runs when `CI=1`, `SOIF_NONINTERACTIVE=1`, or `--non-interactive` is passed, and the function NEVER attempts a `read -rp` on a closed-stdin stream. Today the `-t 0` test at line 306 catches the pipe-stdin case, but the broader question is whether `bash init.sh --non-interactive < /dev/null` (genuinely closed stdin, no fed input) is well-defined for callers that don't want even the `[WARN]` chatter on lines 307.
- Add a `tests/test-init-prompt-install-closed-stdin.sh` regression to fix the boundary so future tests don't need the printf-fed workaround.

**Why deferred (not in PR #104 fix-commit):** the workaround is local to tests, the user-facing behavior of `init.sh --non-interactive` (which the gate at `prompt_install:306` handles correctly) is sound, and the source audit touches multiple helpers + their callers. Capturing as a backlog item per the Wave 4 retrospective so it does not become a "silent backlog" item.

**Related:** PR #104 (test-singletons-and-tier-crosscheck-5), `scripts/lib/helpers.sh:295-324`, `init.sh:117-249` (all the `prompt_install` callsites), Wave 4 retrospective risk note 2.

---

## BL-043: intake-wizard.sh module-load side effects justify a `main()` extraction refactor

**Logged:** 2026-06-29 (PR #104 verifier follow-up — Wave 4 risk note 2)
**Category:** Debt / sourceability hardening
**Severity:** Low (current main-guard + trap-guard handle the surface; refactor improves hygiene)
**Status:** Open — DEFERRED 2026-07-05 (revisit next quarter). Hygiene refactor; the PR #104 main-guard + trap-guard already close the real risks.

PR #104 added two main-guard gates to `scripts/intake-wizard.sh`:
1. Lines 27 + 2009 (PR #104 base): block the project-root discovery + `main "$@"` call when sourced.
2. Lines 290 + 314 (PR #104 verifier follow-up): block the EXIT trap that cleans up `_PAUSE_FILE` when sourced, so it does not clobber the caller's pre-existing EXIT trap.

These two gates patch the most damaging clobber surfaces, but the underlying design is still that intake-wizard.sh runs side-effects at module-load time (helpers sourced at line 13, `_PAUSE_FILE` allocated at line 273, function definitions, etc.). A cleaner shape would be:
- All side-effect setup (CWD anchor, `_PAUSE_FILE`, trap, project-root discovery, `main "$@"`) lives inside an explicit `main()` body.
- The module-load section contains only `set -euo pipefail`, `SCRIPT_DIR=…`, `source lib/helpers.sh`, and function definitions.
- The main-guard at the bottom becomes a single `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi`.

**Proposed scope:**
- ~50-100 LOC moved, no new behavior — but every test that currently subshell-wraps `source scripts/intake-wizard.sh` should still pass without the wrapper. Add a `tests/test-intake-wizard-sourceable-no-side-effects.sh` regression that sources the file at the top level of a test process and verifies (a) no trap registered, (b) no `_PAUSE_FILE` written, (c) the caller's CWD unchanged.

**Why deferred (not in PR #104 fix-commit):** the gates already close the verifier-flagged risks for the current call shapes; the refactor is a hygiene improvement that touches the wizard's structure rather than its behavior. Schedule for a focused refactor PR so the diff is reviewable.

**Related:** PR #104 verifier follow-up (Wave 4 majors #3 + #4), `scripts/intake-wizard.sh:24-27` (sourced-probe), `scripts/intake-wizard.sh:273-321` (pause-file + trap), `scripts/intake-wizard.sh:2009-2011` (main-guard).

---

## code-check-gates-7-followup: per-gate-section blame for APPROVAL_LOG.md commit-author lookup

**Logged:** 2026-06-28 (PR #87 cycle-7 verifier major #4)
**Category:** Bug / governance (precision of self-approval check)
**Severity:** Major
**Status:** Closed (2026-06-30, PR #116, commit `06fb186`)

`scripts/check-phase-gate.sh:246` resolves the commit author of an approval via `git log -n 1 --format=%an -- APPROVAL_LOG.md`, which returns whoever most recently touched the file — not who added the specific gate's Approver row. The cycle-7 PR-#87 adversarial verifier (major #4) flagged the resulting attack surface: if Alice committed her own approval row (true self-approval — should FAIL) and Bob later committed a typo fix to a different gate's row, the check passes for Alice because the latest commit author is Bob.

PR #87's fix-commit added a minimum-viable WARN at the elif branch (`commit_author_norm` empty + `approver_norm` non-empty) so the silent-pass case at least surfaces, but does NOT close the amended/secondary-edit gap.

**Proposed fix:** walk the active gate section in APPROVAL_LOG.md to find the line containing the Approver row, then use `git blame --line-porcelain -L<N>,<N> APPROVAL_LOG.md` (or `git log -L<N>,<N>:APPROVAL_LOG.md --format=%an --no-patch | head -1`) to extract the author of that specific line's most recent change. Compare THAT against the approver name. The section walker already exists in `validate_approval_fields` — the new logic only needs the line-number resolver (awk `$0 ~ /Approver/ && !/Role/ { print NR; exit }` inside the section).

**Test coverage to add:**
- T-blame-1: Alice approves gate A in commit C1; Bob later fixes a typo in gate B in commit C2. `check-phase-gate.sh` MUST still FAIL on Alice's self-approval at gate A.
- T-blame-2: Alice's row is added in the working tree only (uncommitted). Behavior should match the PR-#87 WARN ("cannot verify").
- T-blame-3: Bob commits Alice's approval row on her behalf (legitimate organizational approval). MUST NOT FAIL (commit author differs from approver).

**Why deferred (not in PR #87 fix-commit):** the WARN is sufficient to remove the silent-pass surface; the blame-walker is ~30 lines of new code with three new tests, exceeding the scope of a verifier-feedback fix-commit. Schedule for cycle 8.

---

## BL-034: Wire orphan tests into aggregators (Wave 1-4 cohort)

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Test infrastructure / regression coverage
**Severity:** High
**Status:** Closed (2026-06-29, PR #111, commit `cc1e532`)

Of the 17 test files added in Wave 1-4 (PRs #83-#97 plus follow-up fixers 2d5f917, 33e351e), only **1** (`tests/test-platform-mobile-mcp-docs.sh` via PR #86) is invoked by any aggregator. The remaining 16 test files execute only via direct `bash tests/test-foo.sh` — no aggregator, no CI, no pre-commit-gate runs them. Regressions in intake-wizard, reconfigure, bypass-audit, check-phase-gate, host drivers (gitlab approvals, host_verify_protection date-parse), pending-approval resolve-decision, verify-install fix-functions, upgrade-interruption + sentinel-block, lint scripts, and the host-aware quartet plan are all silent.

**Files needing registration** (full list in `Reports/2026-06-28-test-integrity-audit.md` §4):

- `tests/edge-cases-pre-init.sh` (extended PR #88)
- `tests/edge-cases-scripts.sh` (extended PR #89)
- `tests/edge-cases-upgrade-input.sh` (extended PR #85)
- `tests/test-intake-wizard-fixes.sh` (PR #83)
- `tests/test-reconfigure-field-handlers.sh` (PR #84)
- `tests/test-bypass-audit-tmp-hardening.sh` (PR #93)
- `tests/test-bypass-audit-trap-isolation.sh` (verifier fix 2d5f917)
- `tests/test-bypass-detector-session-id.sh` (PR #93)
- `tests/test-check-phase-gate-noninteractive.sh` (PR #87)
- `tests/test-check-phase-gate-self-approval.sh` (PR #87)
- `tests/test-gitlab-ci-status-stderr-approvals.sh` (PR #91)
- `tests/test-host-verify-protection-date-parse.sh` (PR #93)
- `tests/test-pending-approval-resolve-decision.sh` (PR #87)
- `tests/test-verify-install-fix-functions.sh` (PR #92)
- `tests/test-upgrade-interruption.sh` (PR #95)
- `tests/test-upgrade-sentinel-block.sh` (PR #95)
- `tests/test-lint-fix-functions-stderr.sh` (PR #96)
- `tests/test-lint-raw-read-prompt.sh` (PR #96)
- `tests/test-specs-plans-host-aware-quartet.sh` (PR #97)
- `tests/test-prompt-install-noninteractive.sh` (verifier fix 33e351e)

**Action:** Add explicit `bash "$SCRIPT_DIR/tests/test-*.sh"` invocations to `tests/full-project-test-suite.sh` under new TEST sections. For tests currently RED on main (E50, prompt_install harness — see BL-039), invoke them but mark expected-fail until the underlying bugs land.

**Bundle with:** BL-036 (critical-tautology fixes need to run when added). BL-038 (test-registration lint gate prevents recurrence).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §4 (runner registration gap), §7 Slot 1.

---

## BL-035: Wire orphan tests into aggregators (pre-Wave 1-4 backlog)

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Test infrastructure / regression coverage
**Severity:** Medium
**Status:** Closed (2026-07-06, PR #154 — BL-052/BL-035 capstone). The orphan-wiring wave drained `scripts/lint-tests-registered.sh::KNOWN_ORPHANS_PENDING_BL035` to EMPTY (44 REGISTER / 2 MERGE / 1 DELETE dispositions landed across the 8 area chunks + BL-034 cohort), and this capstone SEALED the bridge: the lint now hard-FAILs (exit 1) if any entry ever reappears, making "every test is registered" a permanent, un-reopenable invariant (durable closure of the BL-035/BL-038 orphan-test defect class). The 3 previously-un-invoked aggregators are now wired into `tests/full-project-test-suite.sh` (see BL-052). Chunk-0 prereqs ([[bl078-stale-lang-fixture-drift]], `test-platform-security-bugs-closer.sh` T4b) were folded into the wave. Remaining CI-runnability work tracked separately by [[bl077-ci-runs-no-test-suites]].

**Decision (2026-07-05):** Karl approved **Option B — triage, don't blind-wire**. First a disposition pass over the 50 bridged orphans (`scripts/lint-tests-registered.sh::KNOWN_ORPHANS_PENDING_BL035`): per file decide register / merge / delete. Then wire the keepers into aggregators and DELETE the obsolete ones; success metric = `KNOWN_ORPHANS_PENDING_BL035` drained to empty. Decide [[bl052-retire-uninvoked-aggregators]] in the SAME pass (same surface). Expect switching some tests on to surface previously-hidden failures = follow-on fix work — likely see [[bl074-test-scaffold-helpers-siblings]] recur.

Approximately 50 `tests/test-*.sh` files predate Wave 1-4 and are not invoked by any aggregator. Coverage for BL-029 (governance log integrity), BL-030 (calibration replay + bypass-audit), counter-sanitizers, init non-interactive (BL-016 — 26 unit tests per the 2026-04-25 plan), pre-commit-gate classifier (BL-020/021), and the bypass-audit family is all silent.

Notable orphans (non-exhaustive — full list in `Reports/2026-06-28-test-integrity-audit.md` Step 4 enumeration):
- `test-bl029-integration.sh`, `test-bl030-calibration-replay.sh`, `test-bypass-audit-{integrity,lib,schema}.sh`
- `test-check-phase-gate-counter-sanitizer.sh`, `test-check-phase-gate.sh`
- `test-init-non-interactive.sh`, `test-init-atomic-finalize.sh`, `test-init-schema-phase-gate.sh`
- `test-pre-commit-gate-classifier.sh`, `test-pre-commit-gate-lints.sh`, `test-pre-commit-gate-terminal-mode.sh`
- `test-upgrade-paths.sh` (NOT the aggregator `tests/upgrade-path-tests.sh` — easily confused)
- `test-upgrade-bl030-backfill.sh`, `test-upgrade-project-atomic.sh`, `test-upgrade-to-production-{preconditions,warn}.sh`
- `test-validate-counter-sanitizer.sh`, `test-test-gate-counter-sanitizer.sh`, `test-test-gate-null-handling.sh`
- `test-bypass-detector.sh`, `test-bypass-patterns.sh`, `test-bypass-sentinel.sh`
- `test-pending-approval.sh`, `test-escalate-to-user.sh`, `test-out-of-band-detector.sh`
- `test-enforcement-level-{init,lib,reconfigure}.sh`
- `test-vendored-skills-install.sh`, `test-record-claude-commit.sh`, `test-unrecord-feature.sh`
- `test-filesystem-gate-install.sh`, `test-gate-principles.sh`, `test-github-free-tier-403.sh`
- `test-poc-modes.sh`, `test-phase-finalize.sh`, `test-process-checklist-{auto-advance,classifier}.sh`

**Action:** Audit each orphan. For each, decide: (a) add to an aggregator, (b) merge logic into an existing aggregator's inline assertions, or (c) delete if redundant. Submit as one PR with a disposition table.

**Schedule:** After BL-034 lands (so the Wave 1-4 cohort is the proven pattern to mirror).

**Confusable filename warning:** `tests/test-upgrade-paths.sh` (orphan test file) vs `tests/upgrade-path-tests.sh` (top-level aggregator). Anyone scanning for upgrade coverage may see two hits and assume the test is registered.

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §4, §7 Slot 4.

---

## BL-036: Fix critical vacuous assertions in edge-cases suite

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / test integrity
**Severity:** Critical
**Status:** Closed (2026-06-29, PR #110, commit `66da15c`)

Three tests in the edge-cases suite are tautological by construction. The corresponding product behaviors have **zero regression coverage** on `main` — a regression could be merged today with no signal.

**E31 (`tests/edge-cases-scripts.sh:1043`) — UAT upgrade refreshes templates:**
The test never invokes `upgrade-project.sh`. The subshell at 1031-1042 inlines `cp "$REPO_DIR/templates/uat/..." tests/uat/...` then asserts the placeholder exists in the file just copied. Assertion is effectively `grep $X $X_COPY`. Identical shape to the audit's `tests-edge-cases-9` finding that was supposedly fixed in E21 — this is a structural regression.
**Fix:** Rewrite to actually invoke `bash scripts/upgrade-project.sh --to-X` (or whichever subcommand handles UAT template refresh). Assert the placeholder is present in the project-side template AFTER the upgrade ran.

**E32 (`tests/edge-cases-scripts.sh:1065`) — UAT upgrade migration is idempotent:**
The loop at 1057-1064 runs the same `cp` twice. The diff at 1065-1066 compares destination to source — guaranteed identical by construction. `upgrade-project.sh`'s idempotency logic is never invoked.
**Fix:** Invoke `upgrade-project.sh` twice. Snapshot project-side state after run 1, run 2, assert the second invocation is diff-clean against the snapshot.

**E39 (`tests/edge-cases-upgrade-input.sh:970`) — newlines preserved:**
Both branches of the inner if/else call pass(). A regression that silently strips the newline AND "line1" still PASSes the else branch with 'handled (stored as: ...)'.
**Fix:** Collapse to a single positive assertion: `grep -q $'^line1\nline2$'` against the saved file (exact two-line round-trip).

**Verification protocol:** For each rewrite, perform a deliberate mutation test — break the product code, confirm the test FAILS, restore the product code, confirm the test PASSes. Capture in PR description.

**Bundle with:** BL-034 (rewritten tests need to be registered in an aggregator to fire).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-4/5/6), §3.1, §7 Slot 2.

---

## BL-037: Fix major vacuous assertions across test suite

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / test integrity
**Severity:** High
**Status:** Closed (2026-06-30, PR #115, commit `359c714`)

15 major-severity findings across edge-cases, verify-install, prompt-install, snapshot-retention, intake-wizard, and self-approval tests use either catch-all `else pass: handled` branches or negative-only oracles (`! grep -q deny`, no positive assertion). Each will silently pass on a crash or on garbage output.

**Tighten each assertion to require a POSITIVE signal:**

- **E33** (SQL injection, `edge-cases-upgrade-input.sh:641`): pin the exact sanitized form (or documented cap length). Reject the catch-all 'sanitized' branch.
- **E34** (10K-char description, `:671`): pin exact stored length (`saved_len == 10000` or `saved_len == ${DESCRIPTION_CAP}`). A regression to 1 char must FAIL.
- **E36** (Unicode, `:804`): pin exact stored bytes (UTF-8 roundtrip exact match).
- **E37** (emoji, `:834`): same shape as E36.
- **E40** (NUL byte, `:1010`): pin either `saved_value == "test\0value"` or the documented sanitization (e.g. NUL stripped → `saved_value == "testvalue"`).
- **E12a/b** (resume.sh + missing/empty CLAUDE.md, `edge-cases-scripts.sh:216, :231`): require `[ $? -eq 0 ]` (clean exit) AND a specific positive output substring. Remove magic-keyword negative oracle.
- **E25a/b/c** (validate/check-phase-gate/resume on phase=99, `:906, :920, :926`): same fix — require rc==expected AND positive output.
- **E27/E28/E29** (UAT init reference pair, `:983` and following): assert BOTH halves of the reference pair (`pre-flight-reference.html` AND `scenario-reference.json`).
- **test-verify-install-fix-functions.sh T6-T10** (`:197, :208, :219, :231, :242`): require the positive fail/manual line (mirror T5's tightened oracle at `:175-178`).
- **test-prompt-install-noninteractive.sh T1/T2/T3** (`:137`): add `type prompt_install >/dev/null || fail` before each test; assert rc==1 specifically (not just rc!=0). Currently a missing function passes with rc=127.
- **test-upgrade-interruption.sh T2** (`:240`): remove the `if [ -d "$TMPDIR_T/.claude/upgrade-snapshots" ]; then ... fi` wrap. Make the dir's presence a hard requirement (otherwise the snapshot infrastructure can be silently broken — see LB-7).
- **test-intake-wizard-fixes.sh T1** (`:81`): replace the tautological shell-parameter-expansion check (`${wiz_line%%:*} != $tpl_num` — unreachable because awk already filtered on `$1 == n`) with an actual title comparison using `wiz_title` against `tpl_title`.
- **test-check-phase-gate-self-approval.sh T3** (`:141`): remove the `else pass` branch on absence-of-message. Require the WARN substring as a positive condition. Currently both elif (WARN matched) and else (no message) pass — a regression dropping the WARN passes silently.

**Verification protocol:** Same mutation-test discipline as BL-036 — break the underlying product code, confirm the tightened test FAILS, restore, confirm GREEN.

**Bundle with:** BL-034 (tightened tests need to be registered to matter). Consider splitting into 4 sub-PRs by area if line count exceeds ~300.

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §3.1, §3.2, §3.3, §3.4, §7 Slot 3.

---

## BL-038: Mandate runner-registration check for new test files

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Test infrastructure / preventive control
**Severity:** Medium
**Status:** Closed (2026-06-30, PR #122, commit 125d6fc)

The pattern of 'PR adds a test file, PR merges, test never runs' is now a systemic risk, not a one-off mistake. 16 of 17 Wave 1-4 test files landed without aggregator registration. Without an automated gate, the next wave will reproduce the same issue.

**Action:** Add a lint script `scripts/lint-tests-registered.sh` that:
1. Enumerates `tests/*.sh` (excluding aggregators and helpers via an allowlist).
2. Greps each top-level aggregator (`full-project-test-suite.sh`, `edge-case-test-suite.sh`, `known-bugs-test-suite.sh`, `upgrade-path-tests.sh`, `host-drivers/run-all.sh`) for invocation of each basename.
3. FAILs the gate if any test file is not invoked by any aggregator.
4. Provides override mechanism: `# LINT_TEST_REGISTRATION_EXEMPT: <reason>` magic comment in the test header (e.g. for slow / network-dependent / manual-only tests).

Wire into `.github/workflows/lint.yml` and `scripts/pre-commit-gate.sh` alongside the existing lint scripts (counter-antipattern, backlog-references, fix-functions-stderr, raw-read-prompt).

Add self-test `tests/test-lint-tests-registered.sh` covering: (a) all-registered fixture passes, (b) one-orphan fixture fails, (c) exempted-orphan fixture passes, (d) malformed exempt comment is rejected.

**Bundle with:** BL-034 (the gate cannot be enabled until existing orphans are dispositioned). Land BL-034 + BL-035 first, then turn the gate on.

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §4, §7 Slot 6.

---

## BL-039: Resolve LB-1 — fix the underlying bug behind E50 (BL-016 non-interactive init)

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / live product defect
**Severity:** High
**Status:** Closed (2026-06-30, PR #117, commit 2888fa2)

E50 in `tests/edge-cases-scripts.sh` (BL-016 init.sh non-interactive suite) is acknowledged as failing on `main` per the PR #89 implementer note. The assistant who added the test did not fix the underlying bug nor remove the assertion. The product code path (`init.sh --non-interactive`) does not satisfy the contract E50 pins.

Because E50 is in an orphan test file (`edge-cases-scripts.sh` is not invoked by any aggregator — see BL-034), the failure is invisible to CI. The only way it surfaces today is if a developer manually runs the edge-cases file.

**Action:**
1. Debug E50 in isolation: `bash tests/edge-cases-scripts.sh 2>&1 | grep -A20 'E50'`.
2. Determine whether the contract E50 pins is correct.
   - If correct: fix `scripts/init.sh` non-interactive code path to satisfy the contract.
   - If the contract is wrong (e.g. the spec changed): update the test AND document the contract change in `docs/builders-guide.md`.
3. Do not delete the test silently — if it's removed, capture the decision in this BL closure.
4. Verify E50 GREEN before closing.

**Dependencies:** BL-034 must register `edge-cases-scripts.sh` in an aggregator so the GREEN state is enforced going forward. Land BL-034 first (with E50 marked expected-fail), then this BL flips it to expected-pass.

**Resolution:** Investigated 2026-06-30 against `init.sh:3262-3268` and `docs/governance-framework.md:257`. The contract E50 was pinning (organizational + private_poc → success with visibility=private) is **wrong** — baseline §2.5 explicitly rejects the `organizational/private_poc` tier shape, and `init.sh` correctly returns exit 1 with the audit code-init-sh-4 / tier-crosscheck-2 rejection message. The 2026-04-25 BL-016 spec table 6.6 row E50 was authored before the tier-crosscheck-2 audit landed and was never reconciled. Rewrote E50 to use `sponsored_poc` (the gov_mode that IS valid for organizational deployments) preserving the org→visibility=private force assertion on mobile+kotlin, and added E50b as a positive rejection test for the actual contract so a future regression that re-permits the invalid combination surfaces loudly. Updated `docs/superpowers/specs/2026-04-25-init-sh-non-interactive-design.md` §8.2 to reflect the actual contract. Narrowed the `SKIP_KNOWN_FAILING` gate in `tests/full-project-test-suite.sh` TEST 0r to track only BL-065 (E30 `--platform other`) — the BL-039 component is lifted. `init.sh` source unchanged; mutation experiment verified E50b would catch a regression (replaced rejection block with `:`, init.sh accepted the invalid combo → E50b would flip RED).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-1), §7 Slot 5. PR #89 implementer note.

---

## BL-040: Resolve LB-2 — `init.sh:2781` dry_run_summary omits the description

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / live product defect (low-impact UX)
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #124, commit `2f67fb1`)

E2 in `tests/edge-cases-pre-init.sh` is left as SKIP because `scripts/init.sh:2781` (`dry_run_summary`) does not echo the project description that the user supplied. The literal-text-preservation guarantee that E2 wants to verify is absent in the product code — there is nothing on stdout to grep against.

**Action:**
1. Read `scripts/init.sh:2781` (`dry_run_summary` function).
2. Add the description field to the function's emitted output (likely a line like `echo "Description: ${project_description}"` near the other summary fields).
3. Verify by running `bash scripts/init.sh --dry-run --project-name foo --description "My test description"` — confirm the description appears.
4. Remove the SKIP in `tests/edge-cases-pre-init.sh` E2; restore the assertion.
5. Confirm E2 PASSes.

**Dependencies:** BL-034 (register `edge-cases-pre-init.sh` in an aggregator) and BL-041 (LB-3 framework-repo guard layering — required to actually run E2 from inside the framework repo).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-2), §7 Slot 5.

---

## BL-041: Resolve LB-3 — `init.sh:3494` framework-repo guard layering

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / live product defect (test-harness blocker)
**Severity:** Medium
**Status:** Closed (2026-06-30, PR #123, commit `64e8c85`)

The framework-repo guard at `scripts/init.sh:3494` runs before the write-permission preflight. When the test harness invokes init.sh from inside the framework checkout (which is how `tests/edge-cases-pre-init.sh` is structured), the guard refuses any non-dry-run invocation before the preflight can fire. E8b is SKIPed as a consequence — there is no way to exercise the write-permission failure path under the current layering.

**Action (preferred — option (a)):** Reorder the checks in `init.sh` so the write-permission preflight runs first (operator-facing check fires before developer-facing guard). The preflight should not depend on any state mutated by the guard.

**Action (fallback — option (b)):** If reordering is structurally infeasible, rewrite the test harness to copy the relevant files into a tmpdir and run init.sh from there (non-framework-repo layout). This is less preferred because (i) it duplicates fixture setup work in every affected test, (ii) it weakens the test's representativeness vs. the operator scenario.

**Verification:** After the fix, remove the SKIP on E8b and confirm the assertion fires correctly (a deliberately read-only destination should cause init.sh to FAIL on the write-permission preflight, not on the framework-repo guard).

**Dependencies:** Lands E8b only after BL-034 (registers `edge-cases-pre-init.sh` in an aggregator).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-3), §7 Slot 5.

---

## BL-044: TEST 4 in full-project-test-suite.sh silently fails 8 assertions due to stale template-layout paths

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** High
**Status:** Closed (2026-06-30, PR #113, commit ca2d5e7)

The PR #104 fixer's full-suite run reported 321/329 passing with 8 failures, all concentrated in `tests/full-project-test-suite.sh` TEST 4 ("Simulated Project Structure Verification"). The failures are pre-existing on `main` — not introduced by any of the Wave 1–4 PRs — and share a single root cause: the test's `cp` source paths still reference the **flat** layout that predated the host-subdir migration. Specifically, lines 506–507 do:

```bash
[ -f "$SCRIPT_DIR/templates/pipelines/ci/$ci_tpl" ] && cp "$SCRIPT_DIR/templates/pipelines/ci/$ci_tpl" "$project_dir/.github/workflows/ci.yml"
[ -f "$SCRIPT_DIR/templates/pipelines/release/${t_platform}.yml" ] && cp "$SCRIPT_DIR/templates/pipelines/release/${t_platform}.yml" "$project_dir/.github/workflows/release.yml"
```

But the actual layout is now `templates/pipelines/ci/github/typescript.yml` (and `gitlab/`, `bitbucket/`) and `templates/pipelines/release/github/web.yml` etc. The flat-path `[ -f ]` guards silently no-op, then verification at line 597–598 emits `File missing ($label): .github/workflows/ci.yml` for every one of the 7 test combos that expects a CI template (7 × 1 = 7 failures), plus the `release.yml` presence check at line 602–604 fires when `templates/pipelines/release/${t_platform}.yml` *would* match under the current layout.

This is a high-severity finding because the failure is **silent at the test-suite gate**: TEST 4 is the only thing in the project that exercises the combinatorial init.sh templating contract end-to-end, and it has been broken for at least the entire Wave 1–4 cycle without any wave catching it. A regression in the actual CI/release templates would not be detected.

**Scope:**
- Update TEST 4's `cp` source paths to use the host-subdir layout (default to `github/` since the test fixture uses GitHub semantics — `.github/workflows/` destination).
- Either parameterize the host (so the test can exercise gitlab/ and bitbucket/ too) or document the GitHub-only scope inline.
- Verify all 8 previously-silent assertions now fail-or-pass correctly: run `bash tests/full-project-test-suite.sh` and confirm TEST 4 reports 0 failures (or surfaces real regressions if any exist in the host-specific templates).
- Add a fixture sanity check at the top of TEST 4 that fails fast if any of the expected source templates are missing, so future template moves don't silently break the suite again.

**Trigger:** Next test-infrastructure pass. Bundle naturally with BL-053 (TEST 4 fixture sharing) and BL-038 (lint-tests-registered) since all three touch the same test surface.

**Related:** PR #104 full-suite run output (321/329); `tests/full-project-test-suite.sh:455-720`; `templates/pipelines/ci/github/`, `templates/pipelines/release/github/` (actual layout); BL-053 (TEST 4 fixture-sharing refactor); BL-038 (runner-registration check).

---

## BL-045: Parallelize TEST 1 resolver matrix in full-project-test-suite.sh (Step 4 ROI #1)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** High
**Status:** Closed (2026-06-30, PR #114, commit `38dbf17`)

TEST 1 of `tests/full-project-test-suite.sh` walks an 81-cell matrix (3 platforms × 9 languages × 3 tracks) and forks a fresh `bash scripts/resolve-tools.sh` invocation per cell. Each cell re-reads `templates/tool-matrix/*.json` from disk and version-probes every tool. The walk is fully serial. Step 4 recon timed the full suite at >600 s (timed out at the 10-minute bash limit), with TEST 1 alone responsible for ~240 s — the single largest time-sink in the entire project.

This matters because the >600 s suite runtime is the primary reason the CI workflow does **not** run the full-project-test-suite at all today (`.github/workflows/lint.yml` runs only lint scripts). Bringing TEST 1 under control unblocks wiring the suite into CI, which in turn closes the structural gap that BL-034/BL-035/BL-038 are also tackling from the other side.

**Scope:** Refactor TEST 1's 81-cell walk to either (a) `xargs -P 8` per-cell invocations into temp output files + aggregate at the end, or (b) collapse into a single resolver invocation that batches the matrix and emits per-cell JSON in one pass. Option (a) is simpler and lower-risk; option (b) is faster but requires `scripts/resolve-tools.sh` API change. Expected reduction: ~240 s → ~30–60 s (4-8× speedup). Document the parallelism level in CONTRIBUTING.md so contributors know how to debug a single failing cell.

**Trigger:** Before wiring full-project-test-suite.sh into `.github/workflows/lint.yml` or `scripts/pre-commit-gate.sh`. Bundle with BL-053 (TEST 4 fixture sharing) since both reduce wall-clock on the same suite.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §5.3, §7 item 1; `tests/full-project-test-suite.sh` TEST 1 block; BL-034, BL-035, BL-038.

---

## BL-046: Split `lib/helpers.sh` into focused libraries (Step 4 ROI #2)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** Medium
**Status:** Closed (2026-06-30, PR #125, commit `16f5c9b`)

`lib/helpers.sh` is sourced by ~15 short-lived script callers. Each source incurs a 30–40 ms parse+exec cost (Step 4 recon profiling) regardless of which helpers the caller actually uses. Compounded across the CLI surface this is visible latency on the per-script TUI flow.

**Scope:** Split `lib/helpers.sh` into focused libraries (e.g. `lib/helpers-string.sh`, `lib/helpers-fs.sh`, `lib/helpers-git.sh`, `lib/helpers-host.sh`) so callers source only the surface they need. Audit each call site and update its `source` line to the narrowest helper-library required. Retain a thin `lib/helpers.sh` shim that sources all of them so any third-party caller continues to work.

**Trigger:** When CLI latency becomes user-visible OR when adding the next big helper that would push `lib/helpers.sh` parse time over a perceptible threshold.

**Resolution (2026-06-30):** Landed as a two-file split (not the four-file per-domain split proposed in the original scope) because caller-usage analysis showed a clean bimodal cut, not a domain-based one. Every short-lived caller (check-*, validate, test-gate, resume, pending-approval, process-checklist) uses a common minimum set: print_*, prompt_*, log_line, run_with_timeout, guard_not_in_framework. Only long-running callers (init.sh, upgrade-project.sh, intake-wizard.sh, reconfigure-project.sh, verify-install.sh) additionally need init_log/finalize_log + MCP-detection helpers. So:

  - `scripts/lib/helpers-core.sh` — 316 lines, the minimum set.
  - `scripts/lib/helpers-full.sh` — 101 lines, transitively sources core, adds init_log/finalize_log/MCP helpers.
  - `scripts/lib/helpers.sh` — thin backwards-compat shim; sources full (which sources core).

Each file has an idempotent-source sentinel guard (`_SOIF_HELPERS_*_LOADED`) so a shell that ends up sourcing multiple entry points (e.g. shim → full → core via composition) still parses each file exactly once.

**Measured savings** (500-iteration amortized loop, Darwin bash 3.2, M-series Mac):
  - helpers.sh via shim: 1.101 ms per source
  - helpers-core.sh direct: 0.823 ms per source
  - **Per-source reduction: 0.278 ms (25%)**

The absolute savings are smaller than the Step 4 report's 30–40 ms projection — that scout likely measured on slower hardware or included non-source-cost latency. The parse-cost *ratio* holds (~25% reduction), so on slower CI/Intel hardware where per-source is ~10× higher, the delta should scale proportionally.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §5, §7 item 2; `tests/test-bl046-helpers-split.sh` (T1-T5b contracts); PR #125.

---

## BL-047: Audit and retire the disabled `cli` arm of `verify-install.sh` (Step 4 ROI #3)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Closed (2026-07-05, commit `03655e8`, low/minor sweep) — Option C: kept as legacy graceful-degradation fallback + added an explanatory comment at `scripts/validate.sh:66` (documents it's reachable via user-editable `CLAUDE.md` `Platform: cli` and must not be deleted without removing `cli` support end-to-end). Not dead code; the arm is in validate.sh, not verify-install.sh as this entry's title says.

`scripts/verify-install.sh` carries a `cli` arm that has been disabled / unreachable (per Step 4 recon). The dead branch confuses readers and is a maintenance trap if a future change accidentally re-enables it without re-validating its assertions.

**Scope:** Confirm the `cli` arm is genuinely unreachable from all entry points (CI workflow, pre-commit gate, manual operator usage). If unreachable, delete the dead branch and its associated tests. If reachable from a path Step 4 missed, document the path and gate the arm behind an explicit flag.

**Trigger:** Next pass on `verify-install.sh` for any reason; bundle with BL-050.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 3; `scripts/verify-install.sh`.

---

## BL-048: Repair dead user-guide anchors (Step 4 ROI #4)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Closed (2026-07-05, commit `33635f5`, low/minor sweep) — added `scripts/lint-doc-anchors.sh` (bash-3.2 in-doc anchor validator) + wired into `.github/workflows/lint.yml`; repaired the 1 broken anchor found (`docs/cli-setup-addendum.md`); self-test `tests/test-lint-doc-anchors.sh` (9 cases, registered).

Step 4 recon enumerated dead anchors in `docs/builders-guide.md` and adjacent user-guide markdown — section headings have been renamed without updating in-doc cross-references. The link-check lint does not catch in-document anchors (only external URLs).

**Scope:** Run an anchor-validator over `docs/` (a small awk/grep script: collect every `## Heading` → derived anchor and every `[link](#anchor)` reference; flag the orphans). Repair each broken anchor. Add the validator script to the lint suite.

**Trigger:** Next docs pass; cheap.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 4; `docs/builders-guide.md`.

---

## BL-049: Delete orphan plan docs under `docs/superpowers/plans/` (Step 4 ROI #5)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Closed (2026-07-05, commit `6140b71`, low/minor sweep) — archived 19 shipped plan docs to `docs/superpowers/plans/archive/` with per-file pointer notes + convention README; updated the 3 tests that pinned plan paths.

Multiple plan documents under `docs/superpowers/plans/` correspond to work that has since shipped (or been superseded). Step 4 recon flagged these as orphans — keeping them around dilutes the active-plan signal for any agent searching that directory.

**Scope:** Enumerate each plan doc, cross-check against `git log` and shipped PRs, and either (a) delete the orphan, (b) move to `docs/superpowers/plans/archive/` with a one-line note pointing at the shipping PR, or (c) keep if still actionable. Document the convention in `docs/superpowers/README.md`.

**Trigger:** Next docs-cleanup pass.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 5; `docs/superpowers/plans/`.

---

## BL-050: Gate `verify-install.sh` eval factory behind non-`--check-only` mode (Step 4 ROI #6)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** Low
**Status:** Closed (2026-06-30, PR #126, commit 66fde35)

`scripts/verify-install.sh` synthesizes 20 `fix_tool_install_N` wrapper functions via `eval` on every invocation, including `--check-only`. Since `run_remediation()` returns early when `MODE=check-only` and never dispatches to those wrappers, the loop is pure overhead on that path — 20 `eval` calls plus one `seq 0 19` subshell fork per invocation (~5-10 ms per Step 4 recon; measured ~1.5 ms on the S3 harness).

**Scope:** Gate the `for _i in $(seq 0 19); do eval …; done` block at `scripts/verify-install.sh:~1401` behind `if [ "$MODE" != "check-only" ]; then … fi`. Verify:
- The check-only report (`show_report`) still renders (it only reads FIXABLE description strings, not fix-function bodies).
- Non-check-only modes (`--auto-fix`, interactive) still synthesize the wrappers so `run_remediation`'s dispatch loop can invoke them.

Add tests exercising both the success path (skipped on `--check-only`), the failure path (over-application would break `--auto-fix`), and a mutation experiment that reverts the gate to `true` and confirms the check-only test fails RED.

**Trigger:** Bundleable with any perf pass touching verify-install.sh (Wave B, Step 4 perf trio alongside BL-046 + BL-053).

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 6; `scripts/verify-install.sh`.

---

## BL-051: Memoize `get_available_platforms` in `resolve-tools.sh` (Step 4 ROI #7)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** Low
**Status:** Closed (2026-07-05, commit `541aba3`, low/minor sweep) — memoized with a bash-3.2 guard+cache; mutation-proven test `tests/test-resolve-tools-memoization.sh`. NOTE: the function lives in `init.sh`, NOT `resolve-tools.sh` as this entry's title claims (Step-4 misattribution).

`scripts/resolve-tools.sh::get_available_platforms` re-scans `templates/tool-matrix/*.json` on every call. Within a single resolver invocation the function is called O(N) times where N is the platform count. Step 4 recon recommends a single-pass memoization via a process-local associative array.

**Scope:** Wrap `get_available_platforms` in a memoization cache (bash associative array keyed by '' since there's no arg). First call populates; subsequent calls hit the cache. Add a test that confirms the function is called once even when invoked 10× in a row (via a counter helper).

**Trigger:** When tackling BL-045 (TEST 1 parallelization) — the per-cell `resolve-tools.sh` fork amplifies any in-function cost. Bundle.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 7; `scripts/resolve-tools.sh`; BL-045.

---

## BL-052: Retire un-invoked test aggregators (Step 4 ROI #8)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Resolved (2026-07-06, PR #154 — BL-052/BL-035 capstone) via **Policy A** (Karl-approved). The 3 previously-un-invoked aggregators (`edge-case-test-suite.sh`, `known-bugs-test-suite.sh`, `upgrade-path-tests.sh`) are now wired into `tests/full-project-test-suite.sh` under a `# --- BL-052: wire previously-un-invoked aggregators ---` block (BL-034 delegate pattern: `bash <agg> >/dev/null 2>&1` → pass/fail, no silencing). Deleted none — each holds substantial unique tests that had been running ZERO times. Running them surfaced 8 hidden reds, all trivially-stale fixture drift (product correct, tests drifted) and fixed in-place — NONE needed a known-RED stub: (a) edge-case T3.1/T3.2/T3.3/T3.4/T4.1-T4.4 — 6 reds from stale `--language javascript`→`typescript` for `--platform web` ([[bl078-stale-lang-fixture-drift]] class); (b) upgrade-path TEST 4b — 2 reds from approval-log governance markers that moved out of `init.sh` heredocs into `templates/generated/approval-log-{org,personal}.tmpl` (the test still grepped `init.sh`; repointed to the templates). known-bugs was already green (23/23). CI-runnability of the now-wired master suite remains tracked by [[bl077-ci-runs-no-test-suites]] (and its runtime prerequisite BL-045, TEST 1 matrix parallelization).

Step 4 recon identified test aggregators under `tests/` that are not invoked from any CI gate, pre-commit hook, or other aggregator. They appear to be dead — sourcing them costs nothing but they confuse the test-discovery surface.

**Scope:** Enumerate every aggregator (`tests/*.sh` that sources other tests), cross-check invocation surface (`.github/workflows/`, `scripts/pre-commit-gate.sh`, `tests/*aggregator*`, etc.), and delete the un-invoked ones.

**POLICY OVERLAP — Karl decision required:** BL-035 (Wire orphan tests into aggregators — pre-Wave 1-4 backlog) recommends the opposite action on adjacent files: register orphans into existing aggregators rather than deleting empty aggregators. Possible reconciliations:
- **Policy A (BL-035 wins):** Consolidate orphans into a small set of aggregators; BL-052 narrows to retire only the *truly* empty ones.
- **Policy B (BL-052 wins):** Delete the un-invoked aggregators; BL-035 narrows to only those orphan tests worth keeping post-cleanup.

Neither item should ship before the policy is set.

**Trigger:** After Karl picks a policy.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 8; BL-035 (cross-ref / overlap); `tests/`.

---

## BL-053: Share TEST 4 fixture across combos in full-project-test-suite.sh (Step 4 ROI #9)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** Medium
**Status:** Closed (2026-06-30, PR #128, commit `ddf253d`) — fixture scaffold built once under `$TEST_DIR/_test4_fixture_template`; per-combo `cp -R fixture/. project/` then mutates only the 3 divergent files (phase-state.json, tool-preferences.json via resolver, CI/release workflow + platform module). All 197 TEST 4 assertions preserved byte-identically. Measured setup savings ~140 ms (403 → 263 ms), well below the report's aspirational 30-40 s figure (which overestimated fresh-git-init cost at ~34 ms/init); still ships for code-clarity gains and to honor the "fixture-template > repeated setup" pattern. Mutation experiment confirms per-combo divergence is not masked by the shared fixture.

TEST 4 in `tests/full-project-test-suite.sh` builds a fresh project fixture per combo (scaffold the directory, copy templates, write manifest). Per Step 4 recon the fixture-setup overhead dominates the per-combo wall-clock; a shared base fixture with combo-specific overlays would cut TEST 4 wall-clock substantially.

**Scope:** Refactor TEST 4 to build one base project fixture (the common scaffolding), then layer combo-specific files on top (CI template, manifest deltas). Each combo runs against an isolated working copy of the base via `cp -r` (cheap) or a per-combo overlay directory. Verify all existing assertions still execute against the same effective state.

**Trigger:** Bundle with BL-044 (TEST 4 path-fix) and BL-045 (TEST 1 parallelization) — single perf PR that touches `full-project-test-suite.sh`.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 9; BL-044, BL-045; `tests/full-project-test-suite.sh` TEST 4.

---

## BL-054: Tiny dead-code cleanup pass — `_phase2_state_file`, `tool_install_json` (Step 4 ROI #10)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Closed (2026-07-05, commit `50f19e4`, low/minor sweep) — removed `_phase2_state_file` (`scripts/lib/phase2-state.sh`) + dead `tool_install_json` local (`scripts/check-versions.sh`); grep-confirmed unreferenced repo-wide.

Step 4 recon identified several small dead-code surfaces, notably the `_phase2_state_file` helper and the `tool_install_json` variable, that are referenced nowhere in current call sites (verified by grep). They're vestigial from earlier refactors.

**Scope:** Grep-confirm each candidate is truly unreferenced (also check templates and docs, not just `scripts/`). Delete in a single small PR. Run the full lint + test gate; nothing should regress.

**Trigger:** Any time; cheap. Could ship as a 'simplify' PR.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 10; `scripts/`.

---

## BL-055: Per-line APPROVAL_LOG.md blame walker for check-phase-gate.sh self-approval evasion

**Status:** Closed (2026-07-01, shipped via PR #116 commit `06fb186` — per-line blame walker at `scripts/check-phase-gate.sh:409-485`; PR #119 commit `601417f` removed the silent-fallback regression that the walker's verifier flagged). Regression cohort: `tests/test-check-phase-gate-blame-walker.sh` T-blame-1 (Bob-shadows-Alice — BL-055's exact threat model), T-blame-2 (uncommitted approver row), T-blame-3 (legitimate author of Alice's row), T-blame-4 (malformed h3 header — PR #119 hardening). All 4 wired into `tests/full-project-test-suite.sh` TEST 0h per BL-034.

---

**Original entry (pre-close, kept for audit trail):**

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Open

Placeholder entry for the tier-crosscheck-6 follow-up. `scripts/check-phase-gate.sh:246` uses `git log -n 1 --format=%an -- APPROVAL_LOG.md` which returns whoever most-recently touched the file rather than the actual author of the Approver row being checked. This is a self-approval evasion surface: if Bob makes a typo-fix commit to `APPROVAL_LOG.md`, his name shadows Alice's as the latest toucher, which would unblock Alice's self-approval against an Approver row Alice herself added.

PR #87 shipped a minimum-viable WARN that surfaces the risk but does not hard-block. The hard-block upgrade — a per-line blame walker that resolves the author of *the specific Approver row*, not the file as a whole — is in flight as workflow `wf_c62d9fbe-369`.

**Scope:** Implement `_resolve_approver_row_author` in `scripts/check-phase-gate.sh` that, given an Approver row's line content, runs `git blame -L <line>,<line> APPROVAL_LOG.md` to find the commit that introduced *that exact row*, then resolves `%an` of that commit. Replace the current `git log -n 1 --format=%an -- APPROVAL_LOG.md` at line 246 with the per-line resolver. Wire into the existing self-approval refusal logic. Add regression tests covering the Bob-typo-fix-shadows-Alice scenario plus the standard happy path.

**Trigger:** This entry exists as a placeholder in case `wf_c62d9fbe-369` does not close before the next backlog snapshot. If `wf_c62d9fbe-369` ships first, this entry flips to Closed with the PR# citation.

**Related:** `scripts/check-phase-gate.sh:246`; PR #87 (minimum-viable WARN); workflow `wf_c62d9fbe-369` (hard-block in flight); audit code-check-gates-7.

---

## BL-057: init.sh --non-interactive must honor AUTO_INSTALL_TOOLS env var

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** High
**Status:** Closed (2026-06-29, PR #107, commit `a0a4e8d`)

Surfaced by the Step-5 dogfood validation walker (`Reports/2026-06-29-step5-dogfood-validation.md`, DOGFOOD-001) — the only bug found across 38 scenarios. `init.sh:736` called `read -rp "Proceed with this plan? [Y/n]"` UNCONDITIONALLY whenever the resolved tool plan contained any `auto_install` or `manual_install` entries.

The inline `lint-raw-read-prompt: allow` comment at the same line documented the INTENDED bypass — *"NON_INTERACTIVE path uses AUTO_INSTALL_TOOLS env var rather than this prompt"* — but no code in `init.sh` actually read `AUTO_INSTALL_TOOLS`, and the guard immediately above did not check `NON_INTERACTIVE` either. Under `set -euo pipefail` with closed stdin (the documented `--non-interactive` contract), `read` returned non-zero and the script terminated silently with `rc=1`.

Currently surfaced only on `--platform mobile` (Android Studio auto_install row on Darwin hosts without Android Studio installed). Blast radius would grow with every new `auto_install` entry added to `templates/tool-matrix/*.json`.

**Repro (RED on origin/main):**

    init.sh --non-interactive --platform mobile --language typescript \
            --track full --deployment personal --gov-mode private_poc \
            --project foo --project-dir <tmp> </dev/null
    # → prints Tool Installation Plan, then dies silently. rc=1.

**Resolution (PR #107):** Replaced the unconditional `read -rp` with an env-aware branch that mirrors the documented contract — `NON_INTERACTIVE=true` → `response = ${AUTO_INSTALL_TOOLS:-Y}`. Paired with a `NON_INTERACTIVE` short-circuit inside the `[Nn]` decline branch so `AUTO_INSTALL_TOOLS=N` logs *"AUTO_INSTALL_TOOLS=N — skipping tool auto-installation..."* and proceeds, instead of dropping into the interactive `prompt_choice` sub-menu (which would EOF-fail under closed stdin). Regression test at `tests/test-init-non-interactive-mobile-auto-install.sh` covers all three contract cases (default Y, explicit N, explicit Y) and is wired into `tests/full-project-test-suite.sh` as TEST 0c4 per BL-034.

**Related:** `init.sh:733-737` (`resolve_and_install_tools`); Step-5 dogfood walker; BL-034 (test-aggregator wiring invariant); `scripts/lint-raw-read-prompt.sh` (the allowlist marker that documented the bypass that did not exist).

---

## BL-058: Sponsored POC `APPROVAL_LOG.md` canonical shape — doc/matrix wording clarified (no product change)

**Logged:** 2026-06-29
**Category:** Documentation
**Severity:** Low
**Status:** Won't Fix — documentation aligned with product behavior. Doc tightening shipped in the same PR.

**What:** The adversarial dogfood re-walker (2026-06-29) flagged `migration-private-poc-personal-to-sponsored-poc-org` as `partial`. The matrix's `expected_terminal_state` said: "APPROVAL_LOG restructured with the 3 Sponsored-required rows visible." After `bash scripts/upgrade-project.sh --to-sponsored-poc --non-interactive` the resulting `APPROVAL_LOG.md` contains all 6 Pre-Phase-0 rows. The re-walker read "3 rows visible" as a restructure-to-3 contract; that reading is incorrect — the product behavior is the canonical contract.

**Why (canonical contract — file:line citations):**
- `templates/generated/approval-log-org.tmpl:20-27` — the organizational APPROVAL_LOG template has all 6 Pre-Phase-0 rows in the table. The template is shape-only; the 6 rows are always present regardless of POC mode.
- `scripts/upgrade-project.sh:1551-1562` — the personal→organizational APPROVAL_LOG restructure emits all 6 rows in the new org-format table. There is no POC-mode-conditional row filter, and the contract does not call for one.
- `tests/test-upgrade-to-production-preconditions.sh:90-134` (`_write_approval_log_org`) — the canonical sponsored-POC fixture seeds all 6 rows. The deferred-vs-upfront distinction is *which rows have dates*, not which rows are present.
- `docs/governance-framework.md` §V — Sponsored POC requires rows 1 (AI deployment path) and 4 (project sponsor) dated upfront; defers rows 2 (insurance), 3 (liability), 5 (backup), 6 (ITSM) until `--to-production` clears them via dated approval or `--ack-preconditions=2,3,5,6`. Exit criteria is §XIV item #8, tracked outside `APPROVAL_LOG.md`.
- `docs/governance-framework.md` §V (pre-clarify wording, original): said "3 of 6" upfront + "5 of 6 minus the 3 required = the remainder". The "3 of 6" count counted exit-criteria as one of the 6, which §XIV does not; "5 of 6 minus 3" was nonsense arithmetic. This PR rewrites §V row 246 to spell out "2 of 6 blocking from §XIV upfront (rows 1,4); 4 of 6 deferred (rows 2,3,5,6); exit criteria is §XIV #8 tracked outside the table; all 6 rows remain visible."

**Scope:**
- `docs/governance-framework.md` §V row 246 — re-worded as above to remove "5 of 6 minus 3" gibberish and explicitly state "all 6 rows remain visible in `APPROVAL_LOG.md`."
- `scripts/upgrade-project.sh:888` — error message tightened from "Sponsored POC deferred 3" to "Sponsored POC requires rows 1,4 upfront and defers rows 2,3,5,6" so operators hitting the `--to-production` gate read the correct row numbers.
- `tests/test-upgrade-to-production-preconditions.sh:10-15` — comment rewritten to match the corrected canonical split.
- Scratchpad `dogfood-matrix.json` — the `migration-private-poc-personal-to-sponsored-poc-org` and `migration-sponsored-poc-to-production-org-ack-bypass` entries had the same "3 Sponsored-required" wording. Updated to "rows 1,4 dated (the 2 Sponsored-required) and rows 2,3,5,6 still TBD" so future dogfood passes don't re-misread the contract.

**No product code change** — `scripts/upgrade-project.sh` already implements the canonical contract correctly.

**Trigger:** Doc-only PR; ships immediately. No follow-up work required unless a separate investigation determines that the dogfood walker's failure to verify the actual canonical contract (rows 1,4 dated, 2,3,5,6 blank) is itself a walker-coverage gap worth filing — that would be a separate ticket about adversarial-walk assertion depth, not this one.

**Related:** Adversarial re-walk verdict 2026-06-29 (`partial`); `docs/governance-framework.md:246` (pre-clarify); `scripts/upgrade-project.sh:1503-1672` (restructure logic, unchanged); `templates/generated/approval-log-org.tmpl`; `tests/test-upgrade-to-production-preconditions.sh`; closed audit `code-upgrade-project-8` (which introduced the original "3 of 6" wording and the deferred-pre-condition gate).

**Reproduction (confirms the canonical 6-row shape is correct):**
```
# Outside the framework repo:
bash $REPO/init.sh --non-interactive --project foo --deployment personal \
  --gov-mode private_poc --platform mcp_server --language typescript \
  --track standard --project-dir "$PWD/foo" --git-host other \
  --remote-url https://example.com/foo.git --branch-protection-attested \
  --no-remote-creation
# Set data_classification + zdr_attested in .claude/process-state.json
jq '. + {"phase1_artifacts":{"data_classification":"internal","zdr_attested":true}}' \
  foo/.claude/process-state.json > /tmp/p.json && mv /tmp/p.json foo/.claude/process-state.json
( cd foo && bash $REPO/scripts/upgrade-project.sh --to-sponsored-poc --non-interactive )
# Expect: APPROVAL_LOG.md contains 6 Pre-Phase-0 rows in org format.
# Sponsored-required rows (1=AI deployment, 4=sponsor) are left BLANK in the
# template — the operator fills them by hand or via subsequent approvals.
grep -c '^| [0-9] |' foo/APPROVAL_LOG.md   # → 6
```

---

## BL-059: validate.sh reads APPROVAL_LOG.md instead of phase-state.json::gates for gate-date checks

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #130, commit `257712b`; verifier findings 1-3 addressed in follow-up commit `8e5c837` — T6 for phase_2_to_3 wiring, T7 for malformed JSON date, tightened T5 anchor)

The adversarial certainty re-walk (re-walker-4, scenario `migration-track-standard-to-full`) surfaced that `scripts/validate.sh:281` emits `Phase 0->1 gate: no date recorded` even when `phase-state.json::gates.phase_0_to_1` is populated. Root cause: the checker greps `APPROVAL_LOG.md` only, while the live state file (`phase-state.json::gates`) is the actual source of truth for gate-passage timestamps. Cross-source inconsistency between the live state file and the validator.

**Why it matters:** Operators reading `validate.sh` output get a false negative for gate-date recording — the gate may have passed and been recorded in `phase-state.json`, but `validate.sh` claims no date is on file. Operators may then try to "re-record" a gate that is already recorded, or treat the project as out-of-compliance when it is in fact compliant. The drift also confuses any downstream automation that trusts `validate.sh`'s output.

**Scope:**
- Pick the canonical source. Two valid resolutions per the report:
  - (a) Update `scripts/validate.sh:281` to read gate dates from `phase-state.json::gates.<gate>` first, falling back to `APPROVAL_LOG.md` only if the JSON path is absent (back-compat).
  - (b) Document that `APPROVAL_LOG.md` is canonical and update any writer that updates `phase-state.json::gates` without mirroring to the log.
- Add a regression test that initializes a project, advances Phase 0→1 (which populates `phase-state.json::gates.phase_0_to_1`), then asserts `validate.sh` does NOT emit `no date recorded` for that gate.
- Audit any other validator checks that conflate the two sources.

**Trigger:** Next pass on `scripts/validate.sh` for any reason; or when an operator next reports a phantom "no date recorded" warning for a gate they know is recorded. Bundle with BL-060 (sibling argv-parser drift in `check-phase-gate.sh`).

**Reproduction:** Per the report — `bash scripts/upgrade-project.sh --to-full --non-interactive` after a Phase-0→1-recorded project, then `bash scripts/validate.sh` and observe the false-negative line at `validate.sh:281`.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-2); `scripts/validate.sh:281`; `phase-state.json::gates`; `APPROVAL_LOG.md`; sibling entries BL-060, BL-061 (same report).

---

## BL-060: check-phase-gate.sh does not parse `--gate` argv flag

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #132, commit `66ba70c`)

The adversarial certainty re-walk (re-walker-4, scenario `edge-tier-crosscheck-6-no-classification-blocks-phase1to2`) surfaced that the scenario passes `--gate phase_1_to_2` to `scripts/check-phase-gate.sh`, but the script has no argv parser for that flag — the gate fires only because `current_phase=2` in `phase-state.json` triggers the backstop. Doc-vs-code drift: the documented CLI surface and the implemented CLI surface disagree.

The re-walker also noted (helpfully) that the output included a separate earlier `[FAIL] Phase 1->2 backstop: protection verification failed` line, and that both fails are emitted in sequence (not short-circuited) — so the data-classification FAIL is not hiding behind the unrelated branch-protection failure. The assertion still fires correctly via the backstop, so the scenario verdict stands; the defect is in the CLI surface itself.

**Why it matters:** Operators (and scripts) that invoke `check-phase-gate.sh --gate <name>` expecting the flag to scope the check are silently relying on the backstop's coincidental triggering. A future refactor that changes the backstop's trigger condition (e.g., by inferring the gate from `current_phase` differently) would silently break callers that pass `--gate`. Scenarios documenting the flag perpetuate the drift.

**Scope:** Two resolution paths:
- (a) Implement an argv parser for `--gate <name>` in `scripts/check-phase-gate.sh` that scopes the check to the named gate (and validates the name is one of the known gates). Update the help text and any in-repo docs that mention the flag.
- (b) If the flag is not desired, remove `--gate` from the affected scenario(s) (e.g. `edge-tier-crosscheck-6-no-classification-blocks-phase1to2`) and any doc that mentions it, so the scenario explicitly exercises the backstop path.
- Either way, add a regression test that asserts the chosen behavior (flag honored, OR flag rejected with a clear diagnostic).

**Trigger:** Next pass on `check-phase-gate.sh`'s CLI surface; bundle with BL-055 (per-line APPROVAL_LOG.md blame walker), which already touches the same script.

**Reproduction:** `bash scripts/check-phase-gate.sh --gate phase_1_to_2` with no `--gate phase_1_to_2`-specific arg-parsing path active — observe that the check still fires by virtue of `current_phase=2` in `phase-state.json` rather than via the flag.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-3); `scripts/check-phase-gate.sh`; scenario `edge-tier-crosscheck-6-no-classification-blocks-phase1to2`; sibling entries BL-055, BL-059, BL-061 (same report / adjacent script).

---

## BL-061: manifest.json::deployment is a stale snapshot after upgrade-project.sh runs

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #131, commit `754b436`)

The adversarial certainty re-walk (re-walker-3, scenario `migration-personal-prod-to-org-prod-needs-data-class`) surfaced that `scripts/upgrade-project.sh` does not refresh `manifest.json::deployment` after the upgrade completes. The field diverges from `phase-state.json` (which is the live source of truth) — for example, after a `personal → organizational` upgrade, `phase-state.json::deployment = organizational` but `manifest.json::deployment` still reads `personal`.

**Why it matters:** Operators (and any tooling that reads `manifest.json` rather than `phase-state.json`) get a stale view of project state post-upgrade. The two-source split also encourages bugs where a future check naively reads `manifest.json::deployment` and makes the wrong decision (e.g., gating an org-only path that the project has already upgraded into). Today the walker noted and did not downgrade, but the divergence is real.

**Scope:** Two resolution paths (the report explicitly offers both):
- (a) **Refresh `manifest.json` in `upgrade-project.sh`** — extend the upgrade routine to update `manifest.json::deployment` (and any other fields that should track `phase-state.json`) atomically alongside the `phase-state.json` write. Pick one canonical write helper to avoid drift between upgrade paths.
- (b) **Formally mark `manifest.json` a stale snapshot** — add a comment / docs note that `manifest.json` captures *initial* project shape (at `init.sh` time) and is NOT refreshed by `upgrade-project.sh`. Audit every reader of `manifest.json::deployment` and migrate to `phase-state.json::deployment`.
- Whichever path is chosen, add a regression test that initializes a personal project, upgrades to organizational, and asserts the chosen contract (refreshed OR documented-stale).

**Trigger:** Bundle with the next `upgrade-project.sh` change. Higher urgency if any new code is about to read `manifest.json::deployment` (would compound the drift).

**Reproduction:** Initialize a personal project, then `bash scripts/upgrade-project.sh --to-organizational --non-interactive`, then `jq -r '.deployment' manifest.json` and `jq -r '.deployment' phase-state.json` — observe the mismatch.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-4); `scripts/upgrade-project.sh`; `manifest.json`; `phase-state.json`; sibling entries BL-059, BL-060 (same report).

---

## BL-062: Step-5 walker grading rubric — when matrix text and observed artifact disagree, default to `partial`

**Logged:** 2026-06-29
**Category:** Documentation
**Severity:** Minor
**Status:** Closed (2026-07-05, commit `4d98300`, low/minor sweep) — created `docs/step5-dogfood-walker-rubric.md` (first persisted rubric) with the default-to-`partial` rule + the Sponsored-POC 3-vs-6-row worked example.

The adversarial certainty re-walk (re-walker-3, scenario `migration-private-poc-personal-to-sponsored-poc-org`) surfaced the only re-walker disagreement across 38 scenarios: the original walker graded `pass` by accepting "documented template behavior" framing, while the adversary downgraded to `partial` because the matrix `expected_terminal_state` literally said "3 rows visible" but the surfaced artifact contains all 6 rows. Both readings were available; the walker chose the lenient one.

This is a walker-process (rubric) signal, not a product defect. The underlying contract question (template vs. matrix wording) is already under BL-058 investigation and addressed by PR #108.

**Why it matters:** If the same divergence shape appears in a future sweep and walkers continue to default to the lenient reading, real contract-violations could be silently graded `pass` and hide regressions. The certainty rate was 97.4% only because the adversarial pass caught this one — the original walker pass would have hidden it.

**Scope:**
- Update the Step-5 dogfood-walker rubric / spec to make the default explicit: **when matrix `expected_terminal_state` text and observed artifact disagree, the grade is `partial` (NOT `pass`), pending a doc-vs-product resolution.** The walker should flag the disagreement, not paper over it with the lenient reading.
- Add a rubric example using this exact scenario (Sponsored POC 3-row-vs-6-row case) showing the correct `partial` grading and the resolution paths (product fix / doc fix / re-grade after disposition).
- No code change; doc-only.

**Trigger:** Before the next Step-5 dogfood sweep (so the new rubric is in force when re-walks are commissioned).

**Reproduction:** N/A (process signal, not a runtime defect). The triggering scenario is documented in `Reports/2026-06-29-adversarial-certainty-pass.md` §4.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-5), §4 (the disagreement); BL-058 (the underlying contract resolution); sibling entries BL-063 (same rubric surface).

---

## BL-063: Enforcement-point scenario contracts assert message-present, not message-only

**Logged:** 2026-06-29
**Category:** Coverage
**Severity:** Minor
**Status:** Closed (2026-07-09, PR #161)

**Resolution (2026-07-09, PR #161):** Added the registered regression suite `tests/test-check-phase-gate-poc-block-contract.sh`, which tightens both Phase-3→4 POC-block enforcement points from "the POC-block message is present" to "the POC block fires ALONE." `check-phase-gate.sh` (`::error::…BLOCKED`, :1381) asserts the sanctioned POC annotation is present AND zero other `::error::`/`[FAIL]` lines co-fire (a Phase-3 fixture where every other gate section genuinely passes; no allowlist needed). `process-checklist.sh` `start_phase4()` (`[FAIL]…blocked`, :578) asserts the short-circuit contract (rc=1, exactly one `[FAIL]`, no later-step output). Negative control corrupts an unrelated required artifact and confirms the count catches the co-firing `[FAIL]`; a mutation proof shows loosening the count back to message-present-only flips it RED. The sweep of other message-present-only enforcement-point assertions (`test-phase3-validation-gate.sh`, `test-bl073-review-manifest-gate.sh`, `test-process-checklist-auto-advance.sh:186`, `edge-cases-scripts.sh:330`) is recorded in the PR body with a recommended follow-up entry to promote the phase-4 gates after WP-A/BL-082 lands.

The adversarial certainty re-walk (re-walker-5, scenarios `edge-phase-3-to-4-poc-blocked-check-phase-gate` and `edge-phase-3-to-4-poc-blocked-process-checklist`) surfaced that both enforcement-point scenarios pass against a contract that only asserts the documented POC-block message is present — they do not assert it is the only block. In one case, the gate output contains 15 inconsistencies; the POC block line is one of them. The scenarios pass as long as the POC-block string appears somewhere in the output, regardless of what else fails.

**Why it matters:** A future regression that introduces an unrelated `[FAIL]` at the same enforcement point would not be caught by these scenarios — the POC-block line is still present, so the assertion still fires. The contract is too loose to detect "the POC block fires for the right reason, alone." This is silent-defect-hiding waiting to happen.

**Scope:**
- Tighten the enforcement-point contracts so they assert either "no other unexpected FAILs" OR "the POC block is the *first* `[FAIL]` line." Pick the stricter of the two that does not over-couple to incidental noise.
- Audit any other scenario in the Step-5 matrix that uses "message present" semantics for an enforcement-point assertion; promote them to the tighter contract.
- Add a negative-control test fixture (deliberately seed an unrelated `[FAIL]` at the enforcement point) and confirm the tightened contract catches it.

**Trigger:** Before the next Step-5 dogfood sweep or when a new enforcement point is added. Bundle with BL-062 (same rubric surface).

**Reproduction:** Compare `edge-phase-3-to-4-poc-blocked-check-phase-gate`'s assertion against the full output of `check-phase-gate.sh` for a Phase-3→4 POC-blocked transition — observe that the POC-block line is one of many failure lines in the gate output.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-6); `scripts/check-phase-gate.sh`; `scripts/process-checklist.sh`; scenarios `edge-phase-3-to-4-poc-blocked-check-phase-gate` and `edge-phase-3-to-4-poc-blocked-process-checklist`; sibling entry BL-062 (same report, sibling rubric tightening).

---

## BL-064: init.sh exits 0 with `Setup Complete` banner after emitting `[FAIL]` for branch protection (silent-success defect)

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Major
**Status:** Closed (2026-06-30, PR #118, commit 443b50a)

The adversarial certainty re-walk (re-walker-2, scenario `fresh-org-sponsored-poc-standard-web-ts`) surfaced that `init.sh` exits `0` with the `Setup Complete` banner even after emitting a `[FAIL]` line for branch protection. Operators who only check the exit code (or scan for the banner) miss the gap entirely — the script claims success while having printed a failure diagnostic. This is the same silent-success defect shape that PR #105 fixed in `intake-wizard.sh:2028` (and the same defect class addressed by recent retroactive lint additions for `[FAIL]`-followed-by-`exit 0` patterns).

**Why it matters:** Silent-success defects are the single highest-priority bug class in this project's history: they corrupt operator trust in the exit-code contract, they bypass any wrapper script that gates downstream actions on `init.sh` succeeding, and they let a half-configured project look fully configured. In this specific case, an operator who runs `init.sh` non-interactively (e.g., in a setup script) gets `rc=0` and a "Setup Complete" banner while branch protection is in a `[FAIL]` state — exactly the scenario branch protection exists to prevent.

**Scope:**
- Audit `init.sh` for every `print_fail` / `[FAIL]` emit site and ensure each one either (a) sets an error-tracking variable that causes the final exit to be non-zero, or (b) explicitly justifies why a `[FAIL]` is acceptable to continue past (with a code comment citing the justification).
- The branch-protection `[FAIL]` path specifically: confirm whether the failure is fatal (most-common operator expectation) or non-fatal-but-loud (with a structured summary at exit). Decide and implement; do not leave both interpretations live.
- At minimum, emit a structured summary at exit-time that re-lists every `[FAIL]` printed during the run, so an operator scanning only the tail of the log still sees the gaps.
- Add a regression test that runs `init.sh` against a fixture that triggers the branch-protection `[FAIL]` path and asserts the new contract (either non-zero exit, or a Setup-Incomplete banner with the failures re-listed).
- Extend `scripts/lint-counter-antipattern.sh` (or a sibling lint) to flag any new `print_fail` site in `init.sh` that does not feed into the exit-status tracking — same shape as the PR #105 lint addition.

**Trigger:** Treat as the next Major bug in queue. Silent-success defects have repeatedly produced operator pain in past audits (PR #105 cycle); this one is the same shape and deserves the same urgency.

**Reproduction:** Per the report — run the `fresh-org-sponsored-poc-standard-web-ts` scenario from the Step-5 dogfood matrix, observe `[FAIL]` line for branch protection in the output, observe `rc=0` and `Setup Complete` banner in the same run.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-7); `init.sh` (branch-protection section); PR #105 (sibling silent-success fix in `intake-wizard.sh:2028`); sibling entries BL-059..BL-063 (same report).

---

## BL-065: E30 (`init.sh --platform other`) RED on main in `tests/edge-cases-scripts.sh` — failure mode uncharacterized

**Logged:** 2026-06-30
**Category:** Bug
**Severity:** Trivial
**Status:** Closed (2026-06-30, PR #121, commit fb843a9)

When PR #111 wired `tests/edge-cases-scripts.sh` into `full-project-test-suite.sh` (TEST 0r), the aggregator-registration commit (`cc1e532`) documented the file as `known-RED (BL-039 + BL-009 follow-up)` and gated it behind a new `SKIP_KNOWN_FAILING` env var so the suite stays green for local iteration loops while the underlying defects are tracked separately. The cited BLs cover E50 (BL-039) and the UAT-template guardrails (BL-009 follow-up), but the RED state in `tests/edge-cases-scripts.sh` also covers **E30** — the `init.sh --platform other` case at `tests/edge-cases-scripts.sh:1031-1041` — which has no backlog entry today. E30 asserts that `init.sh --platform other` skips the UAT reference-pair copy while leaving `tests/uat/templates/test-session-template.html` in place (the documented escape hatch for unsupported platforms); the failure mode (whether the template is missing, the reference files are present anyway, the script exits non-zero, or something else) is not characterized in the PR #111 commit message or in any current report.

**Why it matters:** `--platform other` is the documented escape hatch for any platform the matrix does not enumerate (per `docs/builders-guide.md` platform section). If it is broken, operators trying to onboard a non-listed platform (e.g. embedded, firmware, browser-extension) get a silently wrong scaffold — either no UAT skeleton at all, or one with platform-mismatched reference content. The defect is currently invisible because the only test that pins the contract is gated by `SKIP_KNOWN_FAILING` by default in the iteration loop, and the suite-level CI gate is still pending (BL-038/BL-045 dependency chain). Until BL-065 is fixed, `--platform other` is functionally unsupported and any operator who selects it is on the wrong side of the contract that E30 was written to enforce.

**Scope:**
- Run E30 in isolation: `bash tests/edge-cases-scripts.sh 2>&1 | grep -B2 -A20 'E30'`. Capture the log path emitted on FAIL (`$_uat_work/init-other.log`) and read it to see which of the three E30 assertions tripped (template present, refs absent×2).
- Characterize the failure mode in three buckets and pick the matching fix:
  - Bucket A (template missing): `init.sh` `--platform other` is not copying the source template at all. Trace through `scripts/init.sh` UAT-copy section; either the platform key is unrecognized and the function early-returns, or the template lookup uses a non-existent fixture path. Fix the path/lookup.
  - Bucket B (reference files present anyway): `init.sh` is treating `other` as if it were a known platform and copying a reference pair anyway. Add an explicit branch for `other` (or harden the platform allow-list) that skips the reference copy.
  - Bucket C (script exits non-zero before reaching UAT step): some upstream check rejects `other` as an invalid platform value. Either widen the platform allow-list or change the gate to a WARN.
- Write a regression test inside `tests/edge-cases-scripts.sh` that pins the bucket-A/B/C boundary so a future "fix" to a different bucket cannot silently re-break the original behavior.
- Verify E30 GREEN before closing; once GREEN, the `known-RED` annotation for `tests/edge-cases-scripts.sh` in `tests/full-project-test-suite.sh` TEST 0r needs to be updated to reflect that only BL-039 (E50) + BL-009 (follow-up) remain — or removed entirely if those have also landed.

**Trigger:** Treat as the next Major bug in queue after BL-064. Same urgency as BL-039 (sibling known-RED in the same file) — both are gated by `SKIP_KNOWN_FAILING` and both represent silent contract violations of operator-facing init.sh behavior. Land BL-065 + BL-039 together if scope permits since they share the same edge-cases aggregator and the same investigation pattern (run-in-isolation → read log → patch init.sh → flip the test from RED to GREEN).

**Reproduction:** From a clean tree, `bash tests/edge-cases-scripts.sh 2>&1 | grep -A2 'E30'` — observe the `[FAIL] E30: real init.sh --platform other produced wrong state (refs present or template missing) (log: /tmp/...)` line and inspect the cited log for the exact failure shape.

**Dependencies:** None blocking. BL-034 is already landed (PR #111 `cc1e532`) so `tests/edge-cases-scripts.sh` is in an aggregator; this BL just flips E30 from RED to GREEN.

**Related:** PR #111 commit `cc1e532` (registered the file as `known-RED`); `tests/edge-cases-scripts.sh:1031-1041` (E30 assertion block); `tests/edge-cases-scripts.sh:949-1041` (UAT-platform E26-E30 block surrounding E30); BL-039 (sibling known-RED E50 in the same file); BL-009 (UAT-template guardrails / platform-aware authoring); BL-034 (test-aggregator wiring invariant); `scripts/init.sh` UAT reference-pair copy section; `docs/builders-guide.md` platform escape-hatch documentation.

### Characterization (2026-06-30)

**Confirmed failure mode:** `init.sh` exits with rc=1 *before* the project scaffold or the UAT copy block ever runs. The stderr signature is:

```
[FAIL] init.sh non-interactive: language 'typescript' is not supported for platform 'other'
  Reason: no CI pipeline template (templates/pipelines/ci/github/<lang>.yml) lists other in its platforms marker for that language.
  Action: re-run with one of: other
  Context: --platform='other', --language='typescript'
```

E30's three positive/negative file assertions (`tests/edge-cases-scripts.sh:1120-1122`: template present, two reference files absent) all fail because the project tree was never created — not because the `--platform other` UAT branch produced the wrong state.

**Root cause:** The `_uat_real_init` helper at `tests/edge-cases-scripts.sh:1040-1058` hardcodes `--language typescript` for every platform it is called with. The non-interactive Pass-2 validator at `init.sh:3447` (mirror of the interactive filter at `init.sh:524-529`) walks `templates/pipelines/ci/github/*.yml` and reads each file's `# solo-orchestrator: platforms=` marker; the only template that lists `other` is the catch-all `templates/pipelines/ci/github/other.yml` (gated via the special-case branch at `init.sh:3417`). Because `typescript.yml`'s marker does not include `other`, the combination is rejected and init.sh aborts before reaching the `PLATFORM = other` UAT branch at `init.sh:1261`.

The production `other` branch is itself correct — re-running the same invocation with `--language other` produces rc=0, creates `tests/uat/templates/test-session-template.html`, and does NOT create the reference pair, exactly matching the E30 assertion contract.

**Blast radius:** test-harness-only. Zero operator-facing impact: every wizard path and every legitimate non-interactive contract path for `--platform other` produces the correct state. The defect is confined to one helper invocation inside one assertion block.

**Recommended severity:** **S4 (Trivial / test-harness-only).** Downgrade from the as-filed Major (S2). The PR #111 commit message inferred the failure was a production contract violation on the documented `--platform other` escape hatch; the characterization refutes that. The E30 helper, rewritten in PR #110 / commit `66da15c`, simply missed that the typescript pipeline-template marker excludes `other`. Per the task's own classification rubric ("test-harness-only -> S4"), the severity must drop.

**Reproduction commands:**

```bash
# Reproduce the RED state E30 exhibits today:
tmp=$(mktemp -d) && cd "$tmp" && mkdir -p e30-other && ( cd "$tmp" && \
  bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/init.sh" \
    --non-interactive --project e30-other --platform other --deployment personal \
    --language typescript --git-host github --visibility private --no-remote-creation \
    --project-dir "$tmp/e30-other" --allow-existing-dir \
    < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') ) ; echo rc=$?
# Expected: rc=1, stderr 'language typescript is not supported for platform other'

# Control proving production is correct with the legitimate language:
tmp=$(mktemp -d) && cd "$tmp" && mkdir -p e30-other && ( cd "$tmp" && \
  bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/init.sh" \
    --non-interactive --project e30-other --platform other --deployment personal \
    --language other --git-host github --visibility private --no-remote-creation \
    --project-dir "$tmp/e30-other" --allow-existing-dir \
    < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') ) ; echo rc=$? ; \
  ls "$tmp/e30-other/tests/uat/templates/test-session-template.html" ; \
  ls "$tmp/e30-other/tests/uat/examples/"
# Expected: rc=0, template present, examples dir empty (matches E30's three assertions)
```

**Fix complexity:** **Trivial.** Two equally valid options:

1. One-line change at `tests/edge-cases-scripts.sh:1052` — when the platform is `other`, pass `--language other` instead of the hardcoded `--language typescript`. Smallest possible patch.
2. Generalize `_uat_real_init` to accept a per-platform language argument (default typescript, override to `other` for the `other` case). Slightly larger but keeps the helper reusable for future per-platform E-tests.

No production code change is needed in `init.sh`, the UAT-copy section, or the pipeline templates. After the fix, narrow the `SKIP_KNOWN_FAILING` gate in `tests/full-project-test-suite.sh` TEST 0r to drop BL-065 from the known-RED set (BL-039 / BL-009 follow-up may remain depending on their state).

**Severity line update:** Yes — change the entry's `**Severity:** Major` to `**Severity:** Trivial` and adjust the `Why it matters` / `Trigger` sections to reflect that this is a test-harness fix, not a production contract violation. The `--platform other` escape hatch is NOT broken in production.

---

## BL-066: 3 of 9 host-drivers e2e tests RED on main (`e2e-init`, `e2e-init-gitlab`, `e2e-init-bitbucket`) — failure modes uncharacterized

**Logged:** 2026-06-30
**Category:** Bug
**Severity:** Trivial
**Status:** Closed (2026-06-30, PR #121, commit fb843a9)

When PR #111 wired `tests/host-drivers/run-all.sh` into `full-project-test-suite.sh` (TEST 0s), the aggregator-registration commit (`cc1e532`) documented the file as `known-RED (e2e-init-* trio)` and gated it behind `SKIP_KNOWN_FAILING` so the suite stays green for local iteration loops. The "trio" comprises `tests/host-drivers/e2e-init.test.sh` (github), `tests/host-drivers/e2e-init-gitlab.test.sh`, and `tests/host-drivers/e2e-init-bitbucket.test.sh` — the three end-to-end init.sh tests that exercise the full host-driver path against a mocked host CLI / `curl` stub (per BL-003, BL-003a, BL-003b, all closed). The other six children of `run-all.sh` (`github.test.sh`, `gitlab.test.sh`, `bitbucket.test.sh`, `regressions.test.sh`, `mock-cli.selftest.sh`, `dispatcher.test.sh`) are all GREEN; only the e2e trio is RED, and the specific failure modes are not characterized in the PR #111 commit message or in any current report. Whether all three e2e tests share a single root cause (e.g. a regression in `init.sh`'s host-driver invocation path), or each fails for a distinct host-specific reason, is unknown today.

**Why it matters:** BL-003 / BL-003a / BL-003b were closed (PRs #59, #61, #62) on the explicit promise that the host-driver e2e surface is regression-protected end-to-end. RED state on the trio means that promise is currently false: any silent regression in the init.sh host-driver invocation path, the mocked-CLI contract, the `curl`-stub case-match logic, or the post-init verification assertions would not be caught by CI. Because all three failed simultaneously, the most likely shapes are (a) a shared init.sh refactor that desynced the e2e fixtures, (b) a shared change in the mock-CLI harness that the e2e suite consumes (`tests/host-drivers/mock-cli.sh`), or (c) three independent host-specific regressions that all happen to be live at the same time. The first two are higher-priority because a single fix could close all three; the third would require splitting BL-066 into BL-066a/b/c per host.

**Scope:**
- Run each of the three RED e2e tests in isolation to capture the failure shape:
  - `bash tests/host-drivers/e2e-init.test.sh 2>&1 | tee /tmp/e2e-github.log`
  - `bash tests/host-drivers/e2e-init-gitlab.test.sh 2>&1 | tee /tmp/e2e-gitlab.log`
  - `bash tests/host-drivers/e2e-init-bitbucket.test.sh 2>&1 | tee /tmp/e2e-bitbucket.log`
- Compare the three logs for common signal (same failing assertion name, same stderr fragment, same exit code on the same line of init.sh) — if found, root-cause once and fix all three in one PR.
- If the three failures are independent (different assertions, different hosts, different code paths), split this BL into BL-066a (github), BL-066b (gitlab), BL-066c (bitbucket) and file each per the per-host scope below.
- Per-host scope template:
  - Trace from the failing assertion back through the mocked-CLI invocation transcript (the tests write `$TMP/<cli>-calls.log` and check it after init.sh exits). Determine whether the failure is in (i) the mock didn't get called as expected (init.sh didn't reach the call site), (ii) the mock got called with the wrong args (init.sh's host-driver dispatch is wrong), or (iii) the post-init verification assertion is wrong (artifact-state expectation changed).
  - Apply the fix in init.sh / the driver / the test (in that order of preference — test changes are last resort and require an inline comment explaining the contract drift).
  - Flip the test from RED to GREEN, confirm `bash tests/host-drivers/run-all.sh` reports 9/9 PASS.
- Once GREEN, update the PR #111 `known-RED (e2e-init-* trio)` annotation in `tests/full-project-test-suite.sh` TEST 0s (remove the gate so the test runs in the default suite).
- Add a regression note in the per-host driver doc (`scripts/host-drivers/<host>/`) capturing what changed and why the e2e test now pins it.

**Trigger:** Treat as the next Major bug in queue after BL-065. Three simultaneously-RED e2e tests is the strongest possible signal that the host-driver surface has drifted from its tested contract — same severity tier as BL-064 (silent-success in init.sh) because both are operator-facing contract violations on the primary onboarding code path. Land BL-066 before any further host-driver work (PR #110-era backlog items, BL-031-family follow-ups) so subsequent PRs are not built on top of an unverified e2e surface.

**Reproduction:** `bash tests/host-drivers/run-all.sh 2>&1 | tail -30` — observe the `[FAIL]` lines for the three e2e children, then `bash tests/host-drivers/e2e-init.test.sh` (and the gitlab/bitbucket siblings) individually to capture each failure mode.

**Dependencies:** None blocking. BL-034 is already landed (PR #111 `cc1e532`) so `tests/host-drivers/run-all.sh` is in an aggregator; this BL just flips the e2e trio from RED to GREEN. If split into BL-066a/b/c, the three sub-BLs are independent and can land in any order or in parallel.

**Related:** PR #111 commit `cc1e532` (registered `run-all.sh` as `known-RED (e2e-init-* trio)`); `tests/host-drivers/e2e-init.test.sh`, `tests/host-drivers/e2e-init-gitlab.test.sh`, `tests/host-drivers/e2e-init-bitbucket.test.sh` (the three RED files); `tests/host-drivers/run-all.sh` (the umbrella runner); `tests/host-drivers/mock-cli.sh` (shared mock harness — candidate shared root cause); BL-003 (e2e umbrella, closed PR #59 `f684aa7`), BL-003a (gitlab e2e, closed PR #61), BL-003b (bitbucket e2e, closed PR #62); BL-034 (test-aggregator wiring invariant); `scripts/init.sh` host-driver dispatch section.

### Characterization (2026-06-30)

**Confirmed failure mode:** All three e2e tests exit rc=1 with an identical root-cause stderr signature emitted by `init.sh:3447` (the non-interactive Pass-2 platform×language validator):

```
[FAIL] init.sh non-interactive: language 'javascript' is not supported for platform 'web'
  Reason: no CI pipeline template (templates/pipelines/ci/github/<lang>.yml) lists web in its platforms marker for that language.
  Action: re-run with one of: csharp, go, java, kotlin, other, python, rust, typescript (or pick a different --platform).
  Context: --platform='web', --language='javascript'
```

Results:
- `tests/host-drivers/e2e-init.test.sh`: 0/5 pass (T1 personal, T2 org, T3 push-fail, T4 repo-exists, T5 protection-403)
- `tests/host-drivers/e2e-init-gitlab.test.sh`: 0/7 pass (T1-T5 plus T6 BL-031 host-agnostic exit-3 + T7 BL-032 Premium-tier regression guards)
- `tests/host-drivers/e2e-init-bitbucket.test.sh`: 0/5 pass (T1-T5)

init.sh bails before any host-driver dispatch runs, so the mocked-CLI never gets invoked and the test runner emits secondary `cd: $PROJ: No such file or directory` errors when it tries to enter the never-created project directory.

**Root cause:** Single shared root cause across all three files — stale CLI argument `--language javascript` baked into the `run_init_e2e` helper of each test:

- `tests/host-drivers/e2e-init.test.sh:179`
- `tests/host-drivers/e2e-init-gitlab.test.sh:201`
- `tests/host-drivers/e2e-init-bitbucket.test.sh:238`

init.sh added the strict Pass-2 validation in commit `73da7c9` (2026-06-28, "fix(init,intake): non-interactive Pass-2/Pass-3 language×platform validation alignment"). The validator walks `templates/pipelines/ci/github/*.yml` and reads each file's `# solo-orchestrator: platforms=` marker. No `javascript.yml` ships in the templates directory (only `typescript.yml` covers JS-family with `platforms=web,desktop,mobile,mcp_server`). The three e2e tests were written earlier (commits `f684aa7` / `fc9db0e` / `c8585fa`, BL-003 / BL-003a / BL-003b) and still pass `--language javascript`, so every scenario aborts before any host-driver code runs.

The host drivers, dispatcher, mocked-CLI harness (`tests/host-drivers/mock-cli.sh`), `curl`-stub case-match logic, and post-init verification assertions are all unchanged and remain proven green by their own unit suites (`github.test.sh`, `gitlab.test.sh`, `bitbucket.test.sh`), which bypass `init.sh` and call the driver entrypoints directly.

**Blast radius:** test-harness-only. Production code (`init.sh` validation logic, host drivers, dispatcher, mock-CLI harness) is correct. The BL's hypothesized scenarios — (a) shared init.sh refactor that desynced fixtures, (b) shared mock-CLI harness regression, (c) three independent host-specific bugs — all dissolve: it is (a) in the *trivial* sense that init.sh's validation tightened, but the fix is in the stale test args, not in init.sh or the drivers.

**Recommended severity:** **S4 (Trivial / test-harness-only)** — aggregate across all three. Downgrade from the as-filed Major (S2). Per the playbook rule "if all 3 are test-harness-only -> S4 aggregate". The BL-003 / BL-003a / BL-003b regression-protection promise is *restorable* with a one-line edit per file; the protection itself was never substantively broken — only silenced by stale test args. Note: while RED, T6 (BL-031) and T7 (BL-032) regression guards in `e2e-init-gitlab.test.sh` are silently bypassed because the failure aborts before reaching them — restoring the e2e suite also restores those guards.

**Reproduction commands:**

```bash
cd /Users/karl/Documents/Claude\ Projects/solo-orchestrator && \
  bash tests/host-drivers/e2e-init.test.sh           > /tmp/e2e-init.out      2>&1; echo rc=$?
cd /Users/karl/Documents/Claude\ Projects/solo-orchestrator && \
  bash tests/host-drivers/e2e-init-gitlab.test.sh    > /tmp/e2e-gitlab.out    2>&1; echo rc=$?
cd /Users/karl/Documents/Claude\ Projects/solo-orchestrator && \
  bash tests/host-drivers/e2e-init-bitbucket.test.sh > /tmp/e2e-bitbucket.out 2>&1; echo rc=$?

# Confirm no javascript.yml ships and typescript.yml covers web:
ls /Users/karl/Documents/Claude\ Projects/solo-orchestrator/templates/pipelines/ci/github/
head -1 /Users/karl/Documents/Claude\ Projects/solo-orchestrator/templates/pipelines/ci/github/typescript.yml
# Expected first line: # solo-orchestrator: platforms=web,desktop,mobile,mcp_server
```

**Fix complexity:** **Trivial.** One-line change per file in each `run_init_e2e` helper:

- `tests/host-drivers/e2e-init.test.sh:179`         — `--language javascript` -> `--language typescript`
- `tests/host-drivers/e2e-init-gitlab.test.sh:201`  — `--language javascript` -> `--language typescript`
- `tests/host-drivers/e2e-init-bitbucket.test.sh:238` — `--language javascript` -> `--language typescript`

No changes to host drivers, dispatcher, `tests/host-drivers/mock-cli.sh`, the `curl` stub, or any production code. After the swap, downstream assertions (manifest `host=`, `mode=`, `steps=`, `origin=`, `commit_count=2`, and the BL-031/BL-032 regression guards) should pass because the mock-CLI fixtures (`PROTECT_JSON_PERSONAL`, `PROTECT_JSON_ORG`, `MOCK_GH_*` env hooks) are unchanged from when the suite was last GREEN.

Once GREEN, remove the `known-RED (e2e-init-* trio)` annotation from `tests/full-project-test-suite.sh` TEST 0s so the test runs in the default suite. DO NOT split into BL-066a/b/c — single shared root cause, single PR.

**Severity line update:** Yes — change the entry's `**Severity:** Major` to `**Severity:** Trivial`. Update `Why it matters` to clarify that the BL-003 promise is silenced (not substantively broken), update `Scope` to remove the "split into BL-066a/b/c" branch (root cause confirmed shared), and update `Trigger` to note this can land alongside BL-065 in a single test-harness-only PR rather than being treated as a Major bug blocking subsequent host-driver work.

---

## BL-067: `scripts/lint-tests-registered.sh` runtime blows past 2min — pre-commit gate + CI wall-clock impact

**Logged:** 2026-06-30
**Category:** Performance / Bug
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #133, commit `338ef7f`) — hash-map aggregator scan; verifier-confirmed 6.1× wall-clock speedup (0.986s → 0.162s median, 5-run macOS baseline), byte-identical output preserved (106 rows), mutation-proven via 2 independent mutations. `bash 3.2` compat: `case`-on-delimited-string instead of `declare -A`.

**What:** `scripts/lint-tests-registered.sh` (added by PR #122 / BL-038 as the test-aggregator-registration invariant lint) **timed out at 2 minutes** in a local run during the PR #125 rebase (2026-06-30). The other 4 lints wired into `scripts/pre-commit-gate.sh` (and the CI lint suite) each complete in <5 seconds. The observed wall-clock delta is ~24× the next-slowest lint before the timeout even fires, and the actual runtime is unknown (the 2min bound was a `timeout` cutoff, not the natural end of the walker).

**Why it matters:**
- **Pre-commit gate becomes painful.** `scripts/pre-commit-gate.sh` invokes all lints per commit. A >2min lint means every commit-through-the-gate takes >2min before the operator even sees the pass/fail. That is squarely in the "operator disables the gate to keep working" zone, which nullifies the BL-038 invariant that this lint exists to protect.
- **CI wall-clock per PR grows meaningfully.** Every PR pays this cost at least once. If a PR touches test-registration state and re-runs the gate a few times during iteration, the cost compounds.
- **Runtime scales with test-file count.** Each additional test file added by future Waves (BL-034 wired a whole cohort in a single commit, and more are expected) makes the walker slower. The naive-O(n×m) hypothesis below implies the problem gets strictly worse over time — a slow lint today is a broken lint tomorrow.

**Root cause hypothesis:** The lint appears to walk every `tests/**/*.sh` file and grep every aggregator for that file's basename. Naive O(n×m) where n = test files and m = aggregators. Possibly also uses `grep -F` (or `grep`) per file, possibly recursively over the aggregator set (which would push toward O(n×m×lines-per-aggregator)). Needs profiling to confirm — the hypothesis is inference from the lint's stated invariant (every test file must be registered in ≥1 aggregator) and the observed runtime shape, not from reading the current implementation with a stopwatch attached.

**Scope:**
- Profile the lint (`time bash scripts/lint-tests-registered.sh`, then `bash -x` or `set -x` sampling to locate the hot loop).
- Identify the nested grep / walk structure; confirm or refute the O(n×m) hypothesis.
- Optimize the hot path. Preferred shape: single aggregator scan that builds a hash / associative-array of registered basenames, then O(1) lookup per test file (turns O(n×m) into O(n+m)). Alternatives: pre-compute the union of aggregator contents once via `cat aggregators | sort -u`, then a single `grep -Ff` against the test-file basename list.
- Preserve the current invariant coverage and exit-code contract exactly (no false-negative regressions — the lint must still catch missing registrations).
- Target: **<5s** on the current repo shape (matching the other 4 lints' order of magnitude). Stretch: <1s.
- Add a runtime-guard test (unit or self-test) that asserts the lint completes within a wall-clock budget on the standard fixture set, so future regressions of this class are caught by CI rather than by rebase-day surprise.

**Trigger:** Any future PR that touches `scripts/lint-tests-registered.sh` — pair the runtime fix with the touching change so we don't compound the debt. OR: the next Wave that adds more test files (each addition strictly compounds the runtime under the current shape). If neither trigger fires within the next 2 Waves, promote to "pull forward" — the pre-commit gate friction is a real operator-facing cost that erodes gate discipline the longer it sits.

**Reproduction:**

```bash
cd solo-orchestrator
time bash scripts/lint-tests-registered.sh
# Expected: <5s. Observed 2026-06-30 during PR #125 rebase: >2min (timed out).
```

**Related:** PR #122 / BL-038 (introduced the lint — the invariant is correct, only the implementation shape is slow); `scripts/pre-commit-gate.sh` (the caller that pays the cost per commit); `tests/full-project-test-suite.sh` and the other aggregators the lint walks; BL-034 (test-aggregator wiring invariant — this lint is the enforcement arm of that invariant, so keeping it fast is what keeps the invariant credible).

---

## BL-068: T5 + T5b in `tests/test-bl046-helpers-split.sh` are vacuous — idempotency guards have zero regression coverage

**Logged:** 2026-06-30 (PR #125 verifier finding)
**Category:** Bug / test integrity
**Severity:** Medium
**Status:** Closed (2026-07-01, PR #129, commit `ef911d3`)

**What:** The final two subtests of `tests/test-bl046-helpers-split.sh` — T5 (`:205-231`) and T5b (`:233-252`, executed twice: once for `helpers-full.sh`, once for `helpers.sh`) — are tautological. Both claim to prove the `_SOIF_HELPERS_*_LOADED` idempotency guards in `scripts/lib/helpers-{core,full}.sh` + `scripts/lib/helpers.sh` fire on second source. Neither actually does. Mutation experiment: delete the `if [ -n "${_SOIF_HELPERS_CORE_LOADED:-}" ]; then return 0; fi` guard from `helpers-core.sh` and re-run the suite — **all 8 tests still PASS**. Same result for the guards in `helpers-full.sh` and `helpers.sh`. The three guards have zero regression coverage on main.

**Why they're vacuous:**
- **T5** clears `BOLD=""` between two sources of `helpers-core.sh`, then asserts `BOLD` is empty after the second source ("proof" the guard short-circuited before the color block). But `bash -c "..."` runs in a non-TTY subshell, so `helpers-core.sh`'s `[ -t 1 ]` check takes the ELSE branch and re-assigns `BOLD=''` unconditionally on every source. The assertion passes for the wrong reason. Removing the guard changes nothing.
- **T5b** captures `first="${sentinel:-}"` after the first source and `still="${sentinel:-}"` after the second, then asserts `first == still`. Each sentinel is assigned to the literal `1` unconditionally at the top of every helper file, so `first=1, still=1` regardless of whether the guard fired. The assertion holds for any file that assigns `X=1` at all, guard-protected or not.

**Impact:** The guards are the entire perf story of BL-046 (avoiding re-parse of the color block, dirname resolution, and function redefinition on nested composition). Without a regression guard, a future refactor that "cleans up" the `_SOIF_HELPERS_*_LOADED` sentinels lands silently, and every short-lived caller pays double parse cost per source. Given how many `check-*.sh` / `validate.sh` callers source helpers-core.sh, that's a real (if small-per-call) tax that compounds under repeated invocation.

**Fix (this PR):** Rewrite T5 and T5b to plant an OBSERVABLE marker in a variable each file assigns AFTER its guard, then assert the marker survives the second source. Concretely:
- **T5** plants `LOG_FILE="/tmp/bl068-t5-guard-marker-$$"` between sources. `helpers-core.sh` sets `LOG_FILE=""` at line 57 (after the guard at line 18). Guard fires → return before line 57 → marker preserved. Guard removed → marker wiped to empty. Mutation-verified: removing the core guard flips T5 RED.
- **T5b** plants `MARKER="/tmp/bl068-t5b-guard-marker-$$"` in `$dirvar` (`_SOIF_HELPERS_FULL_DIR` for full, `_SOIF_HELPERS_SHIM_DIR` for shim). Each file recomputes the dirvar from `BASH_SOURCE` after its guard. Guard fires → dirvar untouched. Guard removed → dirvar replaced with real dirname. Mutation-verified: removing each of the two remaining guards independently flips its T5b assertion RED.

**Mutation-proof captured in commit body** (three separate mutations, each restored before the next).

**Related:** PR #125 verifier finding (BL-046 adversarial review); BL-036 (same class — vacuous-by-construction assertions in edge-cases suite); `Reports/2026-06-29-adversarial-certainty-pass.md` (the sweep that catches this defect class).

---

## BL-069: Migrate `install_cmds` array consumers off legacy singular `install_cmd`

**Logged:** 2026-07-01 (PR #136 verifier follow-up)
**Category:** Debt
**Severity:** Medium
**Status:** Closed (2026-07-06, PR #140) — 3 readers + gitleaks/rust/k6 wrappers migrated to iterate `install_cmds` (legacy singular fallback preserved, byte-identical). Verifier `major_concerns` on a reader-#3 (upgrade-project.sh loop) coverage gap → closed via tightener (factored `upgrade_auto_install_from_resolver`, direct test, 24/24, stage-drop mutation-proven).

**Decision (2026-07-05):** Karl approved **Option A — finish it**. Migrate the 3 readers (`verify-install.sh:1324`, `upgrade-project.sh:2033`, `helpers-core.sh:361`) + the gitleaks/rust/k6 wrappers to iterate `install_cmds`, legacy-string fallback preserved. Per-stage-failure regression tests, mutation-proven (keep only `install_cmds[0]` -> a test flips RED), registered in an aggregator (NOT the KNOWN_ORPHANS bridge). Highest-certainty of the three Mediums.

**What:** PR #136 (BL-033) shipped the resolver-side schema: `scripts/resolve-tools.sh` now emits BOTH `install_cmd` (singular, joined with ` && `) AND `install_cmds` (structured array of stages). Verifier confirmed the array is EMITTED but not yet READ by any consumer. Three call sites still read the singular field:

- `scripts/verify-install.sh:1324` (install-command dispatch)
- `scripts/upgrade-project.sh:2033` (tool upgrade path)
- `scripts/lib/helpers-core.sh:361` (shared helper reader)

**Why it matters:** The whole point of the array shape is to give consumers per-stage failure diagnosis + rollback per stage (a stage-1 failure should not cascade into stage-2 rollback attempts). Today, because consumers read the joined singular form, a mid-string failure surfaces as a single opaque error and the retry/repair logic can't distinguish "stage-1 install failed" from "stage-2 activation failed". This is the exact security-hardening motivation BL-033 was filed under (PR #92 verifier follow-up).

**Wrapper-script surface** (the tools most obviously blocked on this): `gitleaks`, `rust`, `k6` — currently each has bespoke wrapper-script install logic that would collapse into structured `install_cmds` if the readers honored the array.

**Scope:**
1. Migrate each of the 3 singular-`install_cmd` readers to iterate `install_cmds` when present, falling back to legacy singular only when the array is absent. Back-compat: any tool-matrix entry still expressed as a legacy string continues to work unchanged.
2. Migrate `gitleaks`, `rust`, `k6` wrapper scripts in `templates/tool-matrix/*.json` (and wherever the wrapper logic currently lives) to the structured `install_cmds` shape.
3. Add regression tests exercising per-stage failure paths: stage-1 fails → stage-2 must NOT run; stage-2 fails → stage-1 side effects must remain observable so repair paths can pick up mid-migration.
4. Mutation-prove the readers actually iterate — a mutation that keeps only `install_cmds[0]` must flip a test RED.

**Trigger:** Any pass that touches `verify-install.sh`, `upgrade-project.sh`, or one of the 3 wrapper-script tools. Also worth batching with BL-035 (~50 pre-Wave-1-4 orphan test wirings) since the new tests need aggregator registration per [[bl034-orphan-tests-wave-1-4]].

**Related:** PR #136 (the schema-forward shipment this follows up on); PR #92 (BL-033's original verifier catch); [[bl033-tool-matrix-multistage-install-cmds]] (the schema half); [[bl034-orphan-tests-wave-1-4]] (test-aggregator registration invariant that new regression tests must satisfy).

---

## BL-070: Phase 3 validation scans — automate Snyk / OWASP ZAP / full-tree Semgrep / license-compliance / threat-model verification

**Logged:** 2026-07-01 (PR #137 workflow.html validation, flagged discrepancy #2 — major)
**Category:** Bug / doc-vs-enforcement gap; framework-promise integrity
**Severity:** Major
**Status:** Closed (2026-07-10, PR #167) — **ALL FIVE Phase-3 scanners are now real; NOTHING remains stubbed-by-decision.** Timeline: skeleton SHIPPED 2026-07-06 (PR #145) — `scripts/run-phase3-validation.sh` driver + attest-on-skip gate (prerequisite BL-071 done, PR #141), `semgrep-full-tree` real in the skeleton; summary tree/dirty binding shipped (BL-082, PR #160); **`license` promoted to REAL 2026-07-10 (PR #164)** — per-language dispatch off `.claude/tool-preferences.json::.context.language` (typescript→license-checker / python→pip-licenses / rust→cargo license / go→go-licenses / csharp→dotnet-project-licenses; unsupported language or missing tool → attestable SKIP; `--offline` → SKIP), minimal report-produced inventory-only PASS/FAIL, mutation-proofed on `# BL-070-LICENSE-DISPATCH`; **`threat-model` promoted to REAL 2026-07-10 (PR #165)** — validates every PROJECT_BIBLE.md §4 `TM-NNN` row against the newest threat-model validation report (glob accepts BOTH `*_threat-model-validation.md` and legacy `*_threat-validation.md`; reconciled `project-bible.tmpl:67`), full-coverage + empty-or-risk-accepted Unmitigated table, word-boundary-safe, pure-local so it RUNS under `--offline`, mutation-proofed on `# BL-070-TM-COMPARE`; **`snyk` + `zap-dast` promoted to REAL 2026-07-10 (PR #167)** per Karl's 2026-07-10 "wire up all security scanners" decision (superseding the earlier keep-as-stubs recommendation) — both detect-and-run-if-available ONLY (no docker-compose local-stub-spinner): snyk SKIPs under `--offline` / not-on-PATH (`npm install -g snyk`) / unauthenticated (`SNYK_TOKEN` OR `snyk config get api`; names `snyk auth`), else `snyk test --json`; zap-dast SKIPs under `--offline` / platform∉{web,api} (platform gate FIRST, canonical `.context.platform` reader) / no docker / no `SOLO_ZAP_TARGET_URL`, else `zap-baseline.py` via `ghcr.io/zaproxy/zaproxy:stable`; both mirror the semgrep findings policy (findings block → FAIL) and stay hermetic on the `--offline` gate-autorun path; mutation-proofed on `# BL-070-SNYK-DISPATCH` + `# BL-070-ZAP-DISPATCH` (both RED→GREEN). The license allow/deny **policy** question (flag GPL/AGPL for organizational deployments) was filed per Karl's gate-#4 decision batch as [[bl086-license-policy-layer]] (file-don't-build). No tree-binding work remains (BL-082 done).

**Decision (2026-07-05):** Karl approved **Option C** — build the `run-phase3-validation.sh` driver + gate integration FIRST, every scanner SKIP-able, add real scanners incrementally (do NOT build all 5 at once). **Refinement (Karl):** when a scanner is missing/unavailable, the framework must let the USER decide whether to download + run it manually; ANY skipped scanner requires the user to attest a reason AND sign off, recorded in `phase-state.json::phase3.attestations` (BL-032 pattern). Gate blocks Phase 3->4 unless every scanner is PASS or attested-skip-with-signoff. Sequence: AFTER [[bl071-phase-gate-date-auto-write]] (reuses its atomic-write pattern in check-phase-gate.sh).

**What:** `docs/builders-guide.md` § Phase 3, `docs/user-guide.md` § Phase 3, and the workflow.html diagram (pre-PR-#137) imply Phase 3 automatically runs Snyk (deps), license compliance, OWASP ZAP DAST, full-tree Semgrep SAST, and threat-model mitigation verification. `grep of scripts/` finds **zero invocations** of any of these tools anywhere in the framework. `check-phase-gate.sh` only searches for artifact filenames in `docs/test-results/` — it neither runs the scans nor verifies their content. Operators today either run the scans manually and remember to save outputs, or skip them entirely with no framework signal. `pre-commit-gate.sh` runs Semgrep on staged files only — that is not the same as the "full-tree scan" Phase 3 documents.

**Why it matters:** This is a core framework promise: "the framework validates everything in Phase 3." If a user relies on that promise and skips the scans (which nothing prevents), a compromised MVP ships with no signal. It directly contradicts Karl's design principle that *users shouldn't have to ask the orchestrator to run evals — those should be automatic — and that gate checks should be real, not implied*.

**Proposed solution (automation-first — priority path):**

Create `scripts/run-phase3-validation.sh` invoked automatically by `check-phase-gate.sh` when the operator (or agent) attempts a Phase 3 → 4 transition. Responsibilities:

1. **Snyk dependency scan** — invoke `snyk test --json` if authenticated; skip with `[SKIP]` (counted as gate FAIL unless attested) if not; archive JSON to `docs/test-results/phase3/snyk-<timestamp>.json`.
2. **License compliance** — invoke language-appropriate license checker (license-checker for TS, pip-licenses for Python, cargo license for Rust, dotnet-project-licenses for C#, etc — same matrix as the language CI templates); archive to `docs/test-results/phase3/licenses-<timestamp>.json`.
3. **Full-tree Semgrep** — invoke `semgrep --config auto --json .`; distinct from pre-commit-gate.sh's staged-files-only scan; archive to `docs/test-results/phase3/semgrep-<timestamp>.json`.
4. **OWASP ZAP DAST** (web + api platforms only) — invoke `zap-baseline.py` via Docker against a running instance; archive to `docs/test-results/phase3/zap-<timestamp>.json`. If Phase 3 has no live URL, start one locally via docker-compose-generated stub.
5. **Threat-model verification** — parse `docs/threat-model.md` for mitigation IDs; grep the test suite for each mitigation's test-id anchor; report any mitigations without corresponding tests.
6. **Aggregate report** — emit `docs/test-results/phase3/summary-<timestamp>.md` with per-check pass/fail + links to artifacts.
7. **Gate integration** — `check-phase-gate.sh` refuses Phase 3 → 4 unless the aggregate summary exists AND reports zero critical findings.

Fallback for POC projects without full tooling: `[SKIP]` counted as gate FAIL unless `--phase3-scans-skipped-attested` is set with a documented reason in `phase-state.json::phase3.attestations` (mirroring the BL-032 `SOLO_APPROVALS_ATTESTED` escape hatch pattern).

**Alternative (docs-only path — deferred unless automation infeasible):** Update Builder's Guide + User Guide to say scans are "operator-run, framework-archived" instead of auto-run. Workflow.html took this path provisionally in PR #137. This does NOT satisfy the design principle; it lowers the framework promise instead of meeting it.

**Related:** PR #137 (workflow.html corrections + validation report); `Reports/2026-07-01-workflow-html-validation.md` flag #2; `docs/builders-guide.md` § Phase 3; `docs/user-guide.md` § Phase 3; `scripts/check-phase-gate.sh:940-954` (the current WARN-only Phase 3 → 4 check); [[bl071-phase-gate-date-auto-write]] (sibling automation gap in the same script); [[bl072-tdd-hard-enforce]] (sibling gate-should-be-real gap); [[bl073-review-manifest-fail-track-full]] (sibling gate escalation).

---

## BL-071: Phase-gate date auto-write — `check-phase-gate.sh` writes `phase-state.json::gates.<gate>` on PASS

**Logged:** 2026-07-01 (PR #137 workflow.html validation, flagged discrepancy #3 — major)
**Category:** Bug / doc-vs-enforcement gap; state-file integrity
**Severity:** Major
**Status:** Closed (2026-07-06, PR #141) — atomic gate-date write on PASS (evidence-first, idempotent, fail-preserving; init.sh seeds the 4th gate key). Verifier `minor_concerns` (no negative evidence-gate test) → closed; extracted `_cpg_gate_has_evidence` as the single evidence surface BL-070/073 reuse. Full `(json_date,evidence)` truth table proved the gate is NOT weakened. warn-mode records state (documented).

**Decision (2026-07-05):** Karl approved **Option A**. Implement the atomic gate-date write on PASS per the filed proposal (idempotent; don't-clear-on-FAIL; seed the missing 4th gate key `phase_2_to_3` in init.sh). **Sequence: FIRST Major to ship** — it establishes the atomic-write-into-`check-phase-gate.sh` pattern that BL-073 and BL-070 reuse. Guard: verify it does NOT mutate state on any read-only / preview / dry-run invocation of the gate.

**What:** The Builder's Guide + workflow.html (pre-PR-#137) state that on a successful phase-gate check, the framework writes today's date to `phase-state.json::gates.phase_<from>_to_<to>` — establishing an authoritative record of when the gate passed. Reality: `check-phase-gate.sh` and `validate.sh` only READ that field. `init.sh` seeds it as `null`. No `jq` assignment expression exists anywhere in `scripts/` that writes to `gates.<gate>`. The gates fields on main are populated only by the operator (or agent) manually editing `phase-state.json`, which the framework does not automate and does not enforce a format for.

Additional (related, minor) gap: `init.sh:1789-1804` seeds only 3 of 4 gate keys (`phase_0_to_1`, `phase_1_to_2`, `phase_3_to_4` — misses `phase_2_to_3`). `verify-install.sh:844-847` seeds all four in its fixup path, so an operator who runs verify-install will get the missing key, but a fresh init skips it. Rolling this into BL-071 rather than filing separately since both concern gate-key state-file integrity.

**Why it matters:** Same design-principle contradiction as BL-070 — a documented gate mechanic that isn't real. Operators reading the docs (or an AI reading the docs to know what state to expect) can be misled into believing that a populated gate-date field guarantees the gate was checked. Today, the gate-date field is decorative — anyone can write anything, at any time, with any format.

**Proposed solution (automation-first — priority path):**

1. Extend `scripts/check-phase-gate.sh` to write today's date to `phase-state.json::gates.<gate>` on every gate PASS, using the atomic-finalize pattern from `scripts/lib/phase2-state.sh` (mkdir-based lock + tmp-write + rename, per PR #97 lineage).
2. Write format: `YYYY-MM-DD` (ISO 8601 date only, matching the regex `check-phase-gate.sh` and `validate.sh` already require at read time).
3. Include the actor: prefer `git config user.name`/`user.email` if available, otherwise `whoami@hostname`. Store as a sibling field `gates.<gate>_by` (schema-forward; readers can ignore if not present).
4. If `gates.<gate>` is already populated with a valid date and the check passes again, log an `[INFO]` line but do NOT overwrite (preserves the first-pass timestamp; re-passes are idempotent).
5. On gate FAIL, do NOT clear an existing populated date — a previous PASS's record is real history, and a subsequent FAIL is a regression signal, not a reset.
6. Fix `init.sh:1789-1804` to seed all 4 gate keys (add the missing `phase_2_to_3`).

**Regression tests (BL-036 + BL-068 discipline):**
- T-happy: gate PASS on virgin project → `gates.<gate>` populated with today's date; mutation-proof: remove the write → fails RED.
- T-idempotent: two consecutive PASSes → date unchanged after second.
- T-fail-preserves: FAIL after prior PASS → date unchanged, gate still fails.
- T-init-seeds-four: fresh init → all 4 gate keys present as null.

**Related:** PR #137 flag #3; `scripts/check-phase-gate.sh`; `scripts/init.sh:1789-1804`; `scripts/verify-install.sh:844-847` (the fixup pattern to mirror); [[bl070-phase-3-validation-scans]]; [[bl036-critical-vacuous-e31-e32-e39]] (mutation-proof discipline).

---

## BL-072: TDD ordering hard-enforcement — pre-commit gate must block, not warn, when implementation ships without tests

**Logged:** 2026-07-01 (PR #137 workflow.html validation, flagged discrepancy #4 — major)
**Category:** Bug / doc-vs-enforcement gap; core framework promise
**Severity:** Major
**Status:** Closed — C1 (detector + WARN + dogfood replay, PR #163, 2026-07-10) then C2 (tier-keyed hard block + attested escape + classifier tightening, PR #166, 2026-07-10), per Karl's 2026-07-10 HARDENED-C2 decision after reviewing the C1 report (`Reports/2026-07-10-bl072-warn-dogfood.md`: 38.6% would-block upper bound, 50% hand-review FP floor). The hard block is tier-keyed on `deployment`+`poc_mode` (`# BL-084-TIER-KEY`, NEVER the spoofable `track`): WARN + logged `bypassed:true` for Personal / Private-POC, HARD BLOCK `[FAIL]` rc=1 for Sponsored-POC / Production, with a `SOLO_TDD_ATTESTED=1` escape RECORDED to `.claude/process-state.json::tdd_attestations[]` (attested, never silenced; a failed record REFUSES the commit). Mothership-safe: missing/empty `deployment` => bypassable. Runs at COMMIT-MSG time (`pre-commit-gate.sh --terminal-mode --tdd-only`), because a pre-commit hook cannot read the commit subject (git writes `.git/COMMIT_EDITMSG` after pre-commit runs) — `init.sh` installs the commit-msg hook. Classifier tightening excludes all `*.md`, pure deletions, and lockfiles (before/after replay `Reports/2026-07-10-bl072-c2-replay.md`: 38.1% -> 36.4% classifier-only; tier-keying + attestation carry the rest). Regression suite `tests/test-bl072-tdd-warn-detector.sh` — 28/28 incl. two mutation proofs (`# BL-072-TDD-DETECT` excision + tier-key revert-to-track).

**Progress (historical):** C1 shipped (PR #163, 2026-07-10) — detector + WARN + `.claude/tdd-warn-ledger.jsonl` + dogfood replay (`tests/test-helpers/dogfood-bl072-replay.sh`, report `Reports/2026-07-10-bl072-warn-dogfood.md`). Measured would-block UPPER BOUND = 110/285 (38.6%) of feat/fix/refactor commits; hand-review of the top-20 = 10 TP / 10 FP (50% outright false positives), most "TP" being init.sh/host-driver integration surfaces not unit-testable in the fast lane. C2 (hard block) then shipped in PR #166 with the tightening/tier-keying/attestation levers above. Note: the "track-tiered" wording below is superseded by BL-084 tier-keying on `deployment`+`poc_mode` (`# BL-084-TIER-KEY`).

**Decision (2026-07-05):** Karl approved **Option A (hard block)** with a **track-tiered bypass matrix**:
- **Personal** (deployment=personal, non-POC) -> may bypass (warn/soft).
- **POC-Personal** (`private_poc` / track=light) -> may bypass, but the bypass is LOGGED (audit trail); enforcement flips to HARD BLOCK if the project is later upgraded to Sponsored POC.
- **POC-Sponsored** (`sponsored_poc` / track=standard) -> HARD BLOCK.
- **Full MVP / Production** (`production` / track=full) -> HARD BLOCK.

Implementer MUST confirm the exact deployment/gov-mode/track enum names against `init.sh` + `intake-wizard.sh` before coding. The upgrade path (`upgrade-project.sh` tier promotion) must flip enforcement to hard-block on promotion to Sponsored, and the POC-Personal bypass log is the audit trail for that transition.

**Open flag from review (Claude — push-back retained):** even WITH tiering, the hard block on Sponsored/Full still rests on the fuzzy "does this code have a matching test?" detection (the same brittleness BL-014 was punted for). Dogfood the detection in WARN mode on solo-orchestrator (a Full-shaped repo) and measure the false-block rate BEFORE the hard block goes live — this arc's own history has many `refactor:` commits that a naive detector would wrongly block.

**What:** The Builder's Guide + README (top-of-file feature list) + workflow.html (pre-PR-#137) all describe test-first as a framework-enforced discipline. Reality: `init.sh:2337-2347` pre-commit hook is warning-only — the operator sees the warning and can commit anyway. `scripts/pre-commit-gate.sh` BL-006 enforcement fires only on `feat:` prefix; `chore/fix/refactor/docs/test/perf/style/build/ci/revert` all bypass. `README.md:531` already admits TDD ordering is "Tier-3 guided" with no automated backstop — but the Builder's Guide + user-facing workflow.html haven't been updated to match.

**Why it matters:** This is arguably the single most important framework promise. "TDD is enforced" is what distinguishes solo-orchestrator from vibe-coding. If a user reads "test-driven, pre-commit hooks warn when implementation ships without tests" and infers the framework blocks the commit, they trust a gate that isn't there. This directly contradicts Karl's principle that *gate checks should be real, not implied*.

**Proposed solution (automation-first — priority path):**

1. **Hard-block on all implementation-touching commits, not just `feat:`.** Extend `scripts/pre-commit-gate.sh` to enforce TDD for `feat:`, `fix:`, and `refactor:` prefixes (anything that touches source outside `tests/`). `docs:`/`test:`/`chore:`/`style:` remain exempt.
2. **Detection:** parse the staged diff. If any file outside `tests/`, `docs/`, `scripts/lint-*.sh`, `.github/`, etc. is modified/added AND no matching test file (per language convention) is modified/added in the same commit OR in the current branch's diff-from-main, refuse the commit with a `[FAIL]` and non-zero exit.
3. **Escape hatch:** `--tdd-attested` flag (env var `SOLO_TDD_ATTESTED=1`) that records the reason in `.claude/process-state.json::tdd_attestations[]` for audit. Blocks are attested, not silenced.
4. **Fix `init.sh:2337-2347`:** promote the warning to a fail. Or better: have init.sh install `pre-commit-gate.sh` as the sole pre-commit hook (removing the ad-hoc inline warning) so the enforcement lives in one place.
5. **Docs sync:** update `README.md:531` to remove the Tier-3 admission (once the block is in place) and update `docs/builders-guide.md` § TDD to cite the enforcement.

**Regression tests:**
- T-hard-block-feat: `git commit -m "feat: X"` touching a source file with no test in the diff → refused with `[FAIL]`, rc=1.
- T-hard-block-fix: same for `fix:` prefix.
- T-hard-block-refactor: same for `refactor:` prefix.
- T-exempt-docs: `docs:` prefix touching only `docs/*` → allowed.
- T-attested-escape: `SOLO_TDD_ATTESTED=1` + reason → allowed, but recorded in `tdd_attestations`.
- Mutation: revert the enforcement to warning-only → T-hard-block-feat/fix/refactor all pass (should fail).

**Related:** PR #137 flag #4; `scripts/pre-commit-gate.sh` (BL-006 enforcement); `scripts/init.sh:2337-2347` (the warning-only hook); `README.md:531` (the honest Tier-3 admission that should stop being needed).

---

## BL-073: Phase 3 → 4 review-manifest gate — escalate to FAIL for `track=full` (currently WARN only)

**Logged:** 2026-07-01 (PR #137 workflow.html validation, flagged discrepancy #6 — major)
**Category:** Bug / doc-vs-enforcement gap; gate escalation
**Severity:** Major
**Status:** Closed (2026-07-06, PR #146, commit `8560652`; verifier follow-up `7a0ec96`) — track-aware review-manifest gate shipped per the approved Option A: FAIL for track=full/standard when Security or Red Team is missing/not-complete, WARN-only for light/personal, grandfather clause keyed on `phase-state.json::review_gate_enforced` (stamped by `init.sh:1907`, re-stamped by `upgrade-project.sh:1252` on tier advance), `SOLO_REVIEWERS_ATTESTED` escape hatch with attestation recorded to `process-state.json::phase3.attestations.reviewers`, plus `scripts/lint-review-manifest.sh` in CI. Regression suite `tests/test-bl073-review-manifest-gate.sh` — 29/29 incl. two mutation proofs (BL-073-ESCALATE excision + status-gate neuter). NOTE: this status flip was missed by the PR #157 backlog reconcile and corrected 2026-07-09.

**Decision (2026-07-05):** Karl approved **Option A** with the **same track-tiered pattern as [[bl072-tdd-hard-enforce]]** and a **grandfather clause**:
- **Full** (track=full): FAIL if Security or Red Team missing (WARN for the other four but still gate-blocking).
- **POC-Sponsored** (track=standard): FAIL if Security or Red Team missing.
- **POC-Personal** (track=light): WARN only, bypass LOGGED; escalation flips to FAIL on upgrade to Sponsored (mirrors BL-072).
- **Personal**: WARN only.

**Grandfather clause:** existing projects with no review-manifest are NOT retroactively blocked — enforcement applies to projects created/advanced after this ships; define the cutover precisely (e.g. keyed on manifest schema-version or a `phase-state.json` flag). Ship AFTER [[bl071-phase-gate-date-auto-write]], with/after the check-phase-gate.sh trio.

**What:** `docs/builders-guide.md` L1614 frames the six-reviewer manifest as a Phase 3 → 4 gate check. `docs/builders-guide.md` L1656 requires Security + Red Team specifically for `track=full`. Reality: `scripts/check-phase-gate.sh:1039-1056` emits `[WARN]` only when the review manifest is incomplete. It does NOT verify all six reviewers ran (only that a manifest file exists), and it does not fail the gate.

**Why it matters:** Same "gate check should be real, not implied" contradiction. A Full-track project that skips Security + Red Team reviews can pass Phase 3 → 4 today with only a warning banner. That's exactly the class of failure the six-reviewer mechanism exists to prevent.

**Proposed solution (automation-first — priority path):**

1. **Track-aware gate escalation** in `scripts/check-phase-gate.sh:1039-1056`:
   - `track=full` (Full path / Organizational Production): FAIL if any of the 6 reviewer entries is missing from the manifest, with the mandatory subset being Security + Red Team (per builders-guide.md L1656) — those two produce FAIL. The other four produce WARN but still count toward gate blocking if track requires them.
   - `track=standard` (Sponsored POC): FAIL only if Security + Red Team missing; WARN for others.
   - `track=light` (Private POC): WARN only (current behavior preserved for POC).
2. **Manifest format contract:** codify the expected schema — array of objects like `[{"reviewer": "security", "status": "complete|skipped|failed", "artifact": "path/to/report.md", "signed_by": "name <email>", "date": "YYYY-MM-DD"}, ...]`. Add a `scripts/lint-review-manifest.sh` linter runnable in CI.
3. **Escape hatch:** `SOLO_REVIEWERS_ATTESTED=1` + documented reason recorded in `.claude/process-state.json::phase3.attestations.reviewers` (mirroring the BL-032 attestation pattern).
4. **Docs sync:** update Builder's Guide L1656 to explicitly state the track-specific enforcement behavior.

**Regression tests:**
- T-full-missing-security-fails: track=full, security reviewer absent → gate FAIL, rc=1.
- T-full-missing-redteam-fails: track=full, red team absent → gate FAIL, rc=1.
- T-full-missing-cio-warns: track=full, CIO absent (not in mandatory subset) → gate WARN + issues++ → still FAIL (exit 1) but message clearer.
- T-standard-missing-security-fails: track=standard, security absent → gate FAIL.
- T-light-missing-security-warns: track=light, security absent → gate WARN only (POC preserved).
- T-attested-escape: `SOLO_REVIEWERS_ATTESTED=1` + reason → allowed, recorded.
- Mutation: revert to `[WARN]` only → T-full-missing-* all pass (should fail).

**Related:** PR #137 flag #6; `docs/builders-guide.md` L1614 (gate framing), L1656 (Security + Red Team mandatory for Full); `scripts/check-phase-gate.sh:1039-1056` (the current WARN-only check); [[bl070-phase-3-validation-scans]] (sibling automation gap); [[bl072-tdd-hard-enforce]] (sibling gate-should-be-real gap).

---

## BL-074: Test scaffolds copy only `helpers.sh`, not the mandatory `helpers-core.sh` / `helpers-full.sh` siblings (post-BL-046 regression)

**Logged:** 2026-07-05 (surfaced by the low/minor sweep's full-suite verification run)
**Category:** Bug / test integrity (pre-existing on main; NOT product-facing)
**Severity:** Medium
**Status:** Closed — verified GREEN 2026-07-07 (during the BL-077 CI work): a shared `scaffold_helpers_libs()` test helper landed (prior session); `test-tier-crosscheck-6-zdr-gate.sh` now 8/8.

**What:** The BL-046 helpers split (PR #125) made `scripts/lib/helpers.sh` a shim that sources `helpers-full.sh`, which sources `helpers-core.sh`. The real product path (`init.sh:1221-1223`) correctly copies all three into every generated project — so **shipping projects are unaffected**. But ~10 test files scaffold a fake project by copying ONLY `helpers.sh` (e.g. `tests/test-tier-crosscheck-6-zdr-gate.sh:293`), not the two now-mandatory siblings. Any scaffolded script that sources `helpers.sh` (e.g. `reconfigure-project.sh`) then dies at `helpers.sh:39` with `helpers-full.sh: No such file or directory`.

**Currently RED on main** (confirmed identical failure on pristine `81bd7e4`, so NOT caused by the low/minor sweep that surfaced it):
- `tests/test-tier-crosscheck-6-zdr-gate.sh` — T6, T7 (2 of 8 fail)
- `tests/test-tier-crosscheck-6-followup-atomicity-and-jq.sh` — F1 (1 of 3 fails)
- `tests/test-reconfigure-field-handlers.sh` — T4-T7 (same `helpers-full.sh` gap; T2 also fails on an unrelated reconfigure->upgrade-project redirect message — track separately)

**Latent** (share the incomplete-copy pattern; grep shows `helpers.sh` copied with `helpers-core`=0 `helpers-full`=0 — not currently exercising the full source chain, so green today but fragile): `test-pre-commit-gate-lints.sh`, `known-bugs-test-suite.sh`, `edge-cases-upgrade-input.sh`, `full-project-test-suite.sh`, `test-specs-plans-remaining-quartet.sh`, `edge-cases-scripts.sh`, `test-pre-commit-gate-terminal-mode.sh`.

**Why it matters:** Red tests have been sitting on main since PR #125 — a test-integrity regression the BL-046 split introduced and no gate caught (same defect-class concern as [[bl035-orphan-tests]]). It also masks real signal: T6/T7 can no longer validate the ZDR/data_classification gate they exist to protect.

**Scope:** Give affected scaffolds the sibling libs — either add `cp helpers-core.sh helpers-full.sh` alongside every `cp helpers.sh` (mechanical), OR factor a shared `scaffold_helpers_libs()` test helper so this cannot drift again (preferred; ties into the [[bl025-phase2-verified-test-helper]] idea). Re-run the two red suites to GREEN; mutation-check they now actually exercise the gate. Audit the 8 latent files for the same gap.

**Related:** PR #125 (BL-046 helpers split); `init.sh:1221-1223` (correct product copy); `scripts/lib/helpers.sh:39`; [[bl035-orphan-tests]] (test-hygiene sibling); [[bl025-phase2-verified-test-helper]] (shared test-scaffold helper idea). Surfaced by the 2026-07-05 low/minor sweep verification.

---

## BL-075: Pre-existing `--terminal-mode` lint reds (pre-commit-gate)

**Logged:** 2026-07-06 (surfaced by the BL-074 fix agent)
**Category:** Bug / test integrity (pre-existing on main)
**Severity:** Low
**Status:** Closed — verified GREEN 2026-07-07: `test-pre-commit-gate-lints.sh` (13/0) and `test-pre-commit-gate-terminal-mode.sh` (3/0) both pass; the `--terminal-mode` reds were repaired by prior work.

Two suites carry pre-existing failures unrelated to the helpers-scaffold gap: `tests/test-pre-commit-gate-lints.sh` (T6a/T6b/T11a/T11b — "`--terminal-mode` did not surface lint") and `tests/test-pre-commit-gate-terminal-mode.sh` (T2 — "docs-only commit blocked"). These are `--terminal-mode` / commit-classification issues in `pre-commit-gate.sh`. Confirmed pre-existing (files unchanged by the BL-074 PR). Audit whether the product behavior or the test expectation drifted; fix the true side.

**Related:** BL-074 (surfacing PR #139); `scripts/pre-commit-gate.sh` `--terminal-mode` path.

---

## BL-076: Non-hermetic init tests create real remote repos

**Logged:** 2026-07-06 (surfaced by the `kraulerson/foo` incident)
**Category:** Bug / test hermeticity (real cloud side effects)
**Severity:** High
**Status:** Closed (2026-07-08, PR #156). Offending test made hermetic; `scripts/lint-no-live-remote-in-tests.sh` guard (blocks any test that could reach real remote creation) wired into CI + pre-commit and made gate-fast (102s→3s); self-test `tests/test-lint-no-live-remote.sh` registered. Double-mutation verified; no leaked repos remain (`foo` already deleted).

`tests/test-init-non-interactive-mobile-auto-install.sh` (lines ~62/72) runs real `init.sh --project foo` with NO `--no-remote-creation`, no `--git-host other`, and no mocked `gh`. Run in an authenticated-`gh` environment (e.g. an agent running `full-project-test-suite.sh`), `init.sh` creates and pushes a REAL private repo — this created `kraulerson/foo` during the 2026-07-06 Wave-1 verification (commit fingerprint `chore: initialize Solo Orchestrator project / Project: foo`; Karl deleted it). A test suite that sprays real repos also can't be wired into CI ([[bl077-ci-runs-no-test-suites]]).

**Scope:** make this test (and any siblings) hermetic — pass `--no-remote-creation` or `--git-host other` + `mock-cli.sh`. Audit ALL tests that invoke `init.sh`/`create_and_protect_remote` for live-`gh` reachability; add a guard/lint so a test can never create a real remote. Sweep `kraulerson/*` for other test-shaped leaks.

**Related:** `foo` incident 2026-07-06; `scripts/host-drivers/mock-cli.sh`; [[bl077-ci-runs-no-test-suites]].

---

## BL-077: CI runs zero test suites — only lint scripts

**Logged:** 2026-07-06 (surfaced by the BL-035/052 triage)
**Category:** Bug / doc-vs-enforcement gap; process integrity
**Severity:** High
**Status:** Closed (2026-07-08, PR #156). Fast lane (66 unit tests, every push to main + PR, ~4 min green on Linux) ships as the per-push gate; the full suite runs as manual `workflow_dispatch` only (it is a ~3h monolith). Linux/PR quirks fixed en route: hermeticity, `stat -f`, git-identity on the runner, `((x++))` set -e footgun, brew fixture, `GITHUB_BASE_REF` leak. Making the full suite CI-fast is deferred → [[bl085-full-suite-ci-fast]].

`.github/workflows/lint.yml` is the ONLY CI workflow and runs only the 6 lint scripts (+ tests-registered, doc-anchors). NO test aggregator runs in CI — `tests/full-project-test-suite.sh` and every suite it delegates are manual-only; `scripts/pre-commit-gate.sh` runs lints + process-checklist only. This is why red tests sit on `main` undetected (BL-074's reds, the tier-crosscheck-6 reds, the stale-lang reds all rode main unnoticed). Directly contradicts the "gate checks real, not implied" principle — the test suite is a giant implied gate that nothing enforces.

**Scope:** add a CI job (and/or pre-push) that runs the master test suite. Gated on: suite hermeticity ([[bl076-nonhermetic-init-tests]] — can't run repo-creating tests in CI) and the suite being green ([[bl078-stale-lang-fixture-drift]], [[bl079-poc-modes-e60-contradiction]], [[bl075-terminal-mode-lint-reds]]) and wired ([[bl035-orphan-tests]] / [[bl052-retire-uninvoked-aggregators]]). This is the meta-item the BL-035 wiring program feeds. Consider a fast lane (unit-ish suites) vs a slow lane (e2e) so CI stays usable.

**Related:** `.github/workflows/lint.yml`; `Reports/2026-07-06-bl035-orphan-triage.md`; [[bl035-orphan-tests]], [[bl076-nonhermetic-init-tests]].

---

## BL-078: Stale `--language javascript`/`ts` fixture drift across ~10 orphan tests

**Logged:** 2026-07-06 (surfaced by the BL-035 triage)
**Category:** Bug / test-fixture drift
**Severity:** Medium
**Status:** Closed (2026-07-06, PR #147). `--language javascript`/`ts` → `typescript` across the named fixtures; verified 2026-07-07 (no residual `--language javascript|ts` in the named files; residual uses in `edge-case-test-suite.sh` are `resolve-tools.sh` calls, correctly out of scope).

`init.sh` tightened language-for-platform validation (audit code-init-sh-5): the accepted set is now `csharp/go/java/kotlin/other/python/rust/typescript` — `javascript` was dropped for `--platform web`. ~10 orphan fixtures still pass `--language javascript` (or `ts`), so `init.sh` aborts and the whole suite fails downstream. Mechanical one-token `javascript`→`typescript` sed per fixture. **Prerequisite (Chunk-0) for the BL-035 wiring wave** — without it, ~10 registrations turn CI red.

Affected: `test-bl029-integration`, `test-bl030-calibration-replay`, `test-bypass-audit-schema`, `test-init-atomic-finalize`, `test-init-non-interactive` (N7 uses `ts`), `test-upgrade-bl030-backfill`, `test-verify-install-bl030-coverage`, `test-poc-modes` (T1/T4), `test-enforcement-level-init`, `test-enforcement-level-reconfigure`.

**Related:** [[bl035-orphan-tests]]; `init.sh` language validation.

---

## BL-079: Registered `edge-cases` E60 contradicts product on `--to-private-poc`

**Logged:** 2026-07-06 (surfaced by the BL-035 triage)
**Category:** Bug / vacuous-or-wrong registered test
**Severity:** Medium
**Status:** Closed (2026-07-06, PR #149, commit `bc609fb`; verified green 2026-07-07 in PR #155, commit `e8df525`) — `edge-cases-scripts.sh` E60 now asserts `--to-private-poc` keeps a personal project personal/private_poc (matches product + poc-modes T1); the poc-modes fork was reconciled in the same PR. (Citation added 2026-07-09 — the uncited closure from PR #157 tripped `lint-backlog-references.sh` and turned CI red on main.)

Orphan `test-poc-modes.sh` T5 and the REGISTERED `edge-cases-scripts.sh` E60 assert OPPOSITE outcomes for `upgrade-project.sh --to-private-poc` from a personal project. Current product (`upgrade-project.sh:692-711`, 2026-06 tier-crosscheck-3) makes it stay **personal** → T5 is correct and **E60 is stale/RED against current behavior**. A registered test asserting the wrong contract is worse than an orphan — fix E60 to match the product (or, if the product is wrong, fix the product), and resolve the poc-modes fork in the same pass.

**Related:** [[bl035-orphan-tests]] (poc-modes UNCERTAIN fork); `tests/edge-cases-scripts.sh` E60; `scripts/upgrade-project.sh:692-711`.

---

## BL-080: `upgrade-project.sh --backfill-only` must honor the BL-015 sentinel

**Logged:** 2026-07-06 (BL-001 verifier finding; Karl chose Option A)
**Category:** Bug / governance-contract gap
**Severity:** Medium
**Status:** Closed (2026-07-06, PR #144) — merged. `_bl015_sentinel_guard()` runs before the `--backfill-only` mutations; a pending-approval sentinel blocks backfill with the `.claude` tree byte-identical. Sibling full-path gap tracked as BL-081.

The `--backfill-only` short-circuit runs BEFORE the BL-015 pending-approval sentinel guard, so backfill mutates `.claude/framework/`, the manifest, host config, and skills even when a pending-approval sentinel is present (pre-existing; BL-001/PR #142 widened it to CDF framework assets). Karl decided (2026-07-06) backfill must honor the sentinel: block + mutate nothing when a sentinel is present, mirroring the full-upgrade guard. PR #144 extracts a shared `_bl015_sentinel_guard()` (single detection + deny-message source for both paths) and calls it before the backfill mutations. Verifier `approve`: full-path refactor proven byte-for-byte behavior-preserving, backfill blocks with the entire `.claude` tree byte-identical, mutation-proven, hermetic, 8/8 lints.

**Related:** [[bl001-cdf-sync-audit]] (PR #142); BL-015 (pending-approval sentinel); `scripts/upgrade-project.sh` backfill path; [[bl081-full-path-mutates-before-sentinel]] (sibling full-path gap).

---

## BL-081: Full-upgrade path runs idempotent backfill (skills/host/manifest) BEFORE the BL-015 sentinel guard

**Logged:** 2026-07-06 (BL-080 verifier observation)
**Category:** Bug / governance-contract gap
**Severity:** Medium
**Status:** Closed (2026-07-10, PR #162) — the full-upgrade path now runs `_bl015_sentinel_guard()` BEFORE the shared idempotent backfill block. The full-path call was moved ahead of that block as a `[ "$BACKFILL_ONLY" != true ]`-gated one-liner, immediately after the untouched `--backfill-only` guard, so each path fires the guard exactly once before any mutation; the old post-`guard_not_in_framework` call site was removed. A sentinel-blocked full upgrade now leaves the entire `.claude/` tree — including `.claude/skills/` and the manifest — byte-identical, and the `_bl015_sentinel_guard()` docstring's "mutates nothing" claim is now true for BOTH call sites. Regression in `tests/test-upgrade-sentinel-block.sh`: T1/T2 assert the byte-identical `.claude/` tree (skills + manifest) on a blocked full upgrade; new T7 is the full-path mutation proof (mirrors T6 for `--backfill-only`). Suite 7/7, mutation-proven RED→GREEN, hermetic (`CDF_HOME` pinned to a nonexistent path), 8/8 CI lints.

Sibling of [[bl080-backfill-honors-sentinel]]. On the FULL `upgrade-project.sh` path (not `--backfill-only`), the idempotent backfill block (vendored-skills sync + host/BL-030 manifest backfill) runs BEFORE the BL-015 sentinel guard. So a sentinel-blocked full upgrade still mutates `.claude/skills/` and manifest fields (visible as `[OK] Vendored skills synced` printing before the deny message) before it blocks. Pre-existing (byte-identical on `main`; NOT introduced by BL-080), but it means the pending-approval sentinel does not fully freeze mutation on the full path either — the same governance concern Karl closed for backfill in BL-080.

**Scope:** decide whether the full-path BL-015 guard should move earlier (before the idempotent backfill block), so NO mutation occurs on any path while a decision is pending — OR whether the pre-guard idempotent backfill is intentionally exempt (it is non-destructive/idempotent). If moved, add a regression asserting a sentinel-blocked full upgrade leaves `.claude/skills/` + manifest byte-identical. Also tighten the `_bl015_sentinel_guard()` docstring, which currently claims "mutates nothing" for both call sites (only strictly true for `--backfill-only`).

**Related:** [[bl080-backfill-honors-sentinel]] (PR #144); BL-015; `scripts/upgrade-project.sh` full-upgrade path.

---

## BL-082: Bind the Phase-3 validation summary to a commit/tree hash + re-run when stale

**Logged:** 2026-07-06 (BL-070 verifier follow-up)
**Category:** Debt / gate hardening
**Severity:** Low
**Status:** Closed — shipped 2026-07-09 (PR #160). The Phase-3 summary is bound to the tree it validated; the gate re-runs (or FAILs) when stale.

Sibling of [[bl070-phase-3-validation-scans]] (PR #145). The BL-070 skeleton's Phase 3→4 gate trusts an existing `docs/test-results/phase3/summary-*.md` as-is: the auto-run only fires when NO summary exists, so a stale summary (e.g. an old `semgrep-full-tree PASS`) is reused indefinitely, and a hand-forged all-PASS summary is trusted. The verifier noted forgery is outside a self-audit gate's threat model (a determined operator has easier documented escapes), but staleness is a real limitation — a summary from before the latest code changes should not satisfy the gate.

**Scope:** bind the summary to the tree/commit it validated — record the `git rev-parse HEAD` (or a tree hash) in the summary and have the gate re-run (or FAIL-with-stale) when the current tree differs from the recorded one. Optionally add an authenticity marker. Ships as a later increment on top of the BL-070 skeleton, alongside promoting the stubbed scanners (license/snyk/zap/threat-model) to real.

**Resolution (PR #160, 2026-07-09):** the driver (`scripts/run-phase3-validation.sh`) records `- tree: <git rev-parse HEAD^{tree}>` (or `none`) and `- dirty: yes|no` in the summary header; the gate (`scripts/check-phase-gate.sh`) treats a summary as FRESH only if the recorded tree matches the current `HEAD^{tree}`, recorded `dirty:no`, AND the live scoped working tree is clean — else it prints `[STALE]`, regenerates offline, and evaluates the fresh summary in one pass (or FAILs when `SOLO_PHASE3_GATE_NOAUTORUN=1`/driver unavailable). Two Karl-approved corrections (2026-07-09) supersede the handoff's WP-A design: **(1)** the dirty check is SCOPED — `git status --porcelain -- . ':(exclude).claude' ':(exclude)<RESULTS_DIR>'` — because the gate writes `.claude/phase-state.json` on PASS (BL-071) and the driver writes attestations there, and that file is TRACKED downstream, so an unscoped check would mark every summary permanently stale after its first PASS; **(2)** the gate ALSO checks live worktree dirtiness (not just the recorded flag), since `HEAD^{tree}` misses uncommitted edits. Freshness decision marked `# BL-082-STALENESS` (mutation target). Suite `tests/test-phase3-validation-gate.sh` extended to 42 tests (git-repo fixtures + 8 new BL-082 cases incl. the two-correction pins) with an excise-and-restore mutation proof (RED 31/10 -> GREEN 42/0).

**Related:** [[bl070-phase-3-validation-scans]] (PR #145 skeleton); `scripts/run-phase3-validation.sh`; `scripts/check-phase-gate.sh` Phase 3→4 block.

---

## BL-084: `init.sh --git-host other` false-failure vs. silent-success — TIER-AWARE custom-host remote policy + Phase 1→2 push-verification gate

**Logged:** 2026-07-06
**Category:** Bug / correctness (false-negative init failure) + gate hardening
**Severity:** Medium
**Status:** Closed — shipped 2026-07-06 (PR #153). Tier-aware design (Karl-approved) — NOT the reference draft's blanket silent-success.

`other` is a documented, supported git host (`docs/user-guide.md`, `docs/builders-guide.md`): the deliberate bring-your-own host/CI path (Gitea, Codeberg, self-hosted). But a normal `--git-host other` init FAILED (exit 2) on two fronts: (1) `verify-install.sh` flagged the absent CI pipeline as a blocking MANUAL item, and (2) a failed initial `git push` to the operator's remote recorded an init failure. A prior draft "fixed" BOTH by making them silent successes — which **re-opened the project's #1 defect class** ([[bl064-init-silent-success]]: init prints "Setup Complete" while the code was never uploaded). This entry ships the Karl-approved design that threads the needle: a **tier-aware** policy keyed on the ACTUAL project tier (`deployment` + `poc_mode`, NOT `track` — see mapping below) + a **real backstop gate** that makes the "configure your own CI" warning TRUE rather than a mask for un-pushed code.

**Tier→enum mapping (keyed on the ACTUAL tier, NOT `track` — verifier follow-up):** bypass-eligibility is decided by `deployment` + `poc_mode` as init.sh / intake-wizard write them, because `track` is NOT a faithful proxy for the tier. `track=light` can be set (non-interactively) on a POC-Sponsored / Production project — the interactive force-upgrade at `init.sh:561-573` does NOT run under `--non-interactive` — so trusting `track` would let a sponsored/production project bypass a failed push with NO code uploaded (the exact silent-success hole BL-084 exists to prevent), while a plain Personal project (default `track=standard`) would be wrongly denied its local-only option. Faithful predicate (identical in init.sh + check-phase-gate.sh):
- **BYPASSABLE** — **Personal** (deployment=personal, non-POC) or **POC-Personal** (deployment=personal, `poc_mode=private_poc`): `deployment=personal` AND `poc_mode≠sponsored_poc`.
- **NON-bypassable** — **POC-Sponsored** (`poc_mode=sponsored_poc`) or **MVP/Production** (deployment=organizational production build): `deployment=organizational` OR `poc_mode=sponsored_poc`.
- Valid-combo facts that make this sound: `poc_mode=sponsored_poc` only ever pairs with `deployment=organizational` (init rejects personal+sponsored); `deployment=personal` therefore only yields `poc_mode ∈ {"", private_poc}` — both bypassable. `poc_mode` is null (unquoted) for production / personal-non-POC, so the gate's quoted-value grep correctly reads it as ≠ sponsored_poc. A personal *production build* (deployment=personal, poc_mode="") is treated as Personal → bypassable (that's the only non-POC option a personal deployment has).

**Fix (three parts):**

1. **`scripts/verify-install.sh` — non-blocking CI/release WARN (Part 1).** New `register_warn` / `WARNINGS[]` category. For a host with no canonical CI/release destination (`other`/unsupported), the absent pipeline surfaces as a benign "configure manually (non-blocking)" warning that is EXCLUDED from the issue total that drives a non-zero exit. Genuine incompleteness on a SUPPORTED host still routes to `register_fixable`/`register_manual` and keeps failing ([[bl064-init-silent-success]] preserved). Ported from the correct half of the reference draft.

2. **`init.sh::create_and_protect_remote` — tier-aware failed-push handling (Part 2).** On the `other` path, when the initial `git push` FAILS, eligibility is decided by `_bl084_tier_bypassable` (marker `# BL-084-TIER-KEY`, keyed on `deployment`+`poc_mode`):
   - **NON-bypassable tier** (POC-Sponsored / Production): **HARD FAIL** — `print_fail` + `return 1` → `record_init_failure` → "Setup INCOMPLETE" + exit non-zero. No flag helps, EVEN with `--track light`. (`# BL-084-TIER-GATE` marker.)
   - **BYPASSABLE tier** (Personal / POC-Personal): real failure BY DEFAULT, but the operator may proceed with an EXPLICIT, on-the-record acknowledgment (never a silent pass): new flags `--accept-local-only-risk` (records `phase2_init.remote.local_only_acknowledged`, init exits 0) and `--defer-remote-push` (records `push_deferred_acknowledged`, init exits 0 but Part 3 gate blocks until pushed). Non-interactive with no flag → still FAILS. Interactive → prompt, default = do NOT proceed. Atomic tmp+mv write ([[bl071-phase-gate-date-auto-write]] lineage). First-class hosts keep the hard-fail push contract.

3. **`scripts/check-phase-gate.sh` — Phase 1→2 remote PUSH verification (Part 3).** New backstop (host=`other` only) verifies the remote actually has the branch via `git ls-remote --heads origin main/master` — hermetic (works against a LOCAL bare repo; NEVER invokes gh, per [[bl076-nonhermetic-init-tests]]). Keyed on the **IDENTICAL** tier predicate as Part 2 (reads `deployment`+`poc_mode` from phase-state.json; marker `# BL-084-TIER-KEY`) so the gate cannot be fooled by `track=light` either: NON-bypassable tier → a verified remote is MANDATORY (a recorded `local_only_acknowledged` does NOT let a sponsored/production project pass); bypassable tier → require the verified remote UNLESS `local_only_acknowledged` is recorded (PASS), and a `push_deferred_acknowledged` with no verified push still FAILS (the deferral does not let you advance — the load-bearing "the gate WILL block you" guarantee). (`# BL-084-PUSH-VERIFY` marker.) Scoped to host=`other` because first-class hosts already hard-fail init on push failure, so a first-class project that reached Phase 2 provably pushed.

**Tests (TDD, hermetic, registered per [[bl034-orphan-tests-wave-1-4]] — NOT the KNOWN_ORPHANS bridge):** `tests/test-bl084-tier-aware-remote-policy.sh` (16 cases). Init: I1 Sponsored + push-fail hard-FAIL despite `--accept-local-only-risk`; I2 Production hard-FAIL despite `--defer-remote-push`; I3 Personal no-flag FAIL by default; I4 Personal `--accept-local-only-risk` → rc0 + ack; I5 Personal `--defer-remote-push` → rc0 + deferral; **I6 Sponsored + `--track light` + `--accept-local-only-risk` → hard-FAIL, no ack [tier≠track, load-bearing]**; **I7 Production + `--track light` + ack → hard-FAIL**; **I8 plain Personal (default track=standard) + ack → BYPASSABLE (Personal gets its option)**; I9 POC-Personal (private_poc) + ack → bypassable. verify-install: V1 non-blocking CI/CD warn. Gate: G1/G2 organizational+`track=light` no-verified-remote → FAIL; G3 Personal local-only-ack → PASS; **G4 Personal deferred-but-not-pushed → FAIL [load-bearing]**; G5 verified remote → PASS; **G6 Sponsored+`track=light`+local_only_ack → FAIL (ack does NOT bypass) [load-bearing]**. Registered in `tests/full-project-test-suite.sh` (TEST 0h2). **Three mutation proofs captured RED→GREEN:** (a) force `bl084_remote_verified=true` (`# BL-084-PUSH-VERIFY`) → G4 RED; (b) negate the `! _bl084_tier_bypassable` guard (`# BL-084-TIER-GATE`) → I1/I2 RED; (c) revert eligibility to trust `track` in BOTH files (`# BL-084-TIER-KEY`) → I6/I7/I8/I9 + G1/G2/G6 RED (7 RED — the dangerous-case tests confirm the tier-not-track fix is load-bearing).

**E56–E61 disposition:** the cohort used `--git-host other` + a fake URL merely to dodge real CLI/API calls; that combo now (correctly) hard-fails at the default `track=standard` AND never lays down `.github/workflows/ci.yml` (no canonical destination), so E56's `ci.yml` assertion was doubly-stale. Switched E56/E57/E59/E60/E61 to the [[bl076-nonhermetic-init-tests]]-blessed hermetic path `--git-host github --no-remote-creation` (short-circuits before any gh call; `ci.yml` present; rc=0 for each test's real regression target). E58 (`--deployment organizational --gov-mode private_poc`) and E60's `deployment=organizational` assertion remain pre-existing RED for reasons unrelated to this fix (invalid governance combo / [[bl079-poc-modes-e60-contradiction]]) — left for the BL-079 registered-edge-case cleanup, as the reference draft noted.

**Before/after:** `init.sh --non-interactive --git-host other --remote-url <fake> --branch-protection-attested …` — before: exit **2** ("Setup INCOMPLETE") for ALL projects. After: **POC-Sponsored / MVP-Production** (deployment=organizational or poc_mode=sponsored_poc) still exits non-zero — remote mandatory, and `--track light` does NOT unlock a bypass; **Personal / POC-Personal** (deployment=personal) + `--accept-local-only-risk`/`--defer-remote-push` exits **0** with the acknowledgment on record; Personal with no flag still fails (no silent success).

**Related:** [[bl064-init-silent-success]] (silent-success defect class — the trap the reference draft fell into); BL-024 (attestation-before-push on the same path); [[bl071-phase-gate-date-auto-write]] (atomic-write + track-read patterns reused); [[bl076-nonhermetic-init-tests]] (no real remote in tests); [[bl034-orphan-tests-wave-1-4]] (aggregator registration); [[bl079-poc-modes-e60-contradiction]] (E58/E60 residual cleanup); `init.sh` `create_and_protect_remote`; `scripts/verify-install.sh` `check_project_structure`; `scripts/check-phase-gate.sh` Phase 1→2 backstops.

---

## BL-085: Make the full test suite CI-fast (the ~3h monolith)

**Logged:** 2026-07-08 (BL-077 full-lane follow-up)
**Category:** Debt / CI performance
**Severity:** Low
**Status:** Open — DEFERRED (manual dispatch works today; optimize only if a scheduled comprehensive CI run is actually wanted)

BL-077 (PR #156) shipped the fast lane (per-push) but the full suite runs manual-only because it is a ~3-hour serial monolith: ~200 sequential `init.sh` project scaffolds (~15s each), concentrated in a few heavy aggregators (edge-cases-pre-init 68, edge-cases-scripts 41) + TEST 4 combos + inline cohort init tests. Sharding into 4 (PR #156) isolates failures but leaves `core` as a ~3h long pole (it holds ~75% of the work — at the 2h mark it had only reached TEST 1).

**To make it nightly-viable (~20-30 min):** split `core` into ~4-6 balanced shards (needs finer `SUITE_*` section selectors in `full-project-test-suite.sh`, beyond the existing `SUITE_SKIP_AGGREGATORS`), OR run the independent test files with internal parallelism, OR speed up `init.sh` itself (each scaffold ~15s — halving it halves every shard + the standalone suite). Also de-flake the timing-sensitive tests (`edge-case-test-suite.sh` resolver-timeout flaked between runs). Then re-enable a `schedule:` trigger.

**Trigger:** when a scheduled comprehensive nightly is genuinely wanted. Until then `gh workflow run tests.yml` (manual dispatch) covers it on demand.

**Related:** PR #156 (fast lane + 4-shard matrix + `SUITE_SKIP_AGGREGATORS`); `.github/workflows/tests.yml` (`full` job); `tests/full-project-test-suite.sh`; BL-045 (TEST 1 parallelization — done); BL-053 (TEST 4 fixture share — done).

---

## BL-086: License-compliance policy layer (allow/deny) for the Phase-3 license scanner

**Logged:** 2026-07-10 (gate-#4 batch)
**Category:** Proposal
**Severity:** Low
**Status:** Closed — shipped 2026-07-11 (PR #177; Karl decision 2026-07-11 incl. his correction). The tier-keyed deny policy BLOCKS the corporate track — `deployment=organizational` OR `poc_mode=sponsored_poc` OR **`poc_mode=private_poc`** (the POC runway is held to the destination tier's standard: a copyleft dep in a private POC ratchets forward to Sponsored/production, where it must be removed, commercially re-licensed, or the source opened — no sponsor approves that). Pure personal (`deployment=personal`, no `poc_mode`; or missing phase-state) warns loudly instead.

Filed per the gate-#4 decision batch. The Phase-3 `license` scanner shipped REAL in PR #164 (BL-070 increment) deliberately **inventory-only**: it runs the per-language license tool, archives the report, and PASSes on any non-empty report — it did NOT judge the licenses it found. This entry adds the **allow/deny policy layer** on top, keyed on the ACTUAL tier (`deployment` + `poc_mode`, NEVER the spoofable `track`) with its OWN marker `# BL-086-TIER` (deliberately stricter than BL-084's bypass predicate, which treats `private_poc` as bypassable for the push gate).

**Delivered (PR #177):**
- **Default deny list** (`# BL-086-DENY`, mutation target #1): strong copyleft — `GPL-2.0*`, `GPL-3.0*`, `AGPL-1.0*`, `AGPL-3.0*`, `SSPL-1.0`, plus bare `GPL`/`AGPL`. EXPLICITLY not denied: `LGPL-*`, `MPL-*`, `EPL-*`, permissive. Boundary-safe token start-with match (`LGPL-3.0` never matches a `GPL-3.0` stem); matches the license field only, never package names.
- **FP hygiene:** a top-level `OR` alternative that is not denied (`MIT OR GPL-3.0`) → PASS (consumer may elect the safe side); `AND`-expressions / bare denied ids are flagged.
- **Tier rule** (`# BL-086-TIER`, mutation target #2): blocked tiers FAIL through the existing gate path; pure-personal PASSes with a LARGE bordered warning banner naming every copyleft package + the distribute/sell/commercial-service (AGPL triggers on network service alone)/transition ramifications.
- **Policy override** — optional `.claude/license-policy.json` DATA file (read via jq, NEVER sourced — the BL-088 closure check stays green): `{"deny":[...] replaces the default, "allow_packages":[...] exempts named packages}`; malformed JSON → LOUD FAIL.
- **Attested escape** (attested, never silenced — BL-072/BL-032 lineage): `SOLO_LICENSE_ATTESTED=1` (+ `SOLO_LICENSE_REASON`) appends `{date, packages, licenses, reason}` to `phase-state.json::phase3.license_exceptions[]` via the atomic tmp+mv jq pattern; a failed record REFUSES the pass. The write lands under `.claude/` (BL-082 scoped-dirty excludes it → cannot re-mark the summary stale; verified empirically).
- **Per-format deny** across all five tool formats (license-checker / pip-licenses / cargo-license / go-licenses CSV envelope / dotnet-project-licenses); an unparseable report → LOUD FAIL.
- **Tests:** `tests/test-bl070-license-scanner.sh` extended 18 → 51 assertions incl. the two mutation proofs (`# BL-086-DENY` excision → T-deny-org-gpl RED; `# BL-086-TIER` neuter → org AND private_poc both warn-only RED). Neighbors green (snyk-zap 39, phase3-gate 51, source-closure 6). Docs: security-scan-guide + user-guide + builders-guide license sections + README line.

**Related:** [[bl070-phase3-validation-scans]] (the license scanner this extends — was inventory-only by design); [[bl084]] (the tier→enum predicate this deliberately diverges from — private POC blocks here); BL-072 / BL-032 (attested-not-silenced escape lineage); BL-082 (summary provenance / scoped-dirty); BL-088 (source-closure — policy stays a DATA file); PR #164 (the inventory-only license arm); PR #177 (this policy layer); `scripts/run-phase3-validation.sh::_p3_scan_license`.

---

## BL-087: BL-006 commit-msg delegate would hard-block inside the framework repo if a hook were ever installed (latent) + `--amend` surface asymmetry

**Logged:** 2026-07-10 (PR #169 adversarial verification)
**Category:** Debt / latent hazard + documented-behavior caveat
**Severity:** Low
**Status:** Closed — shipped 2026-07-17 (PR #200, landed via PR #202 `88bddd3`). Item 1 (the latent framework-repo hard-block): `# BL-087-MOTHERSHIP-PASS` in `bl006_terminal_enforce` — graceful pass with a loud [note] receipt when cwd matches the guard's own framework signature; mutation-proven, verifier-assessed incl. the spoof surface (spoof strictly dominated by pre-existing quieter escapes; see `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-A3). Item 2 (`--amend` asymmetry) was already recorded as documented behavior, not a defect — nothing further to do.

Two follow-ups from the PR #169 verifier (BL-010 residual fix), both zero-impact today:

1. **Latent framework-repo trap.** `bl006_terminal_enforce` (scripts/pre-commit-gate.sh, commit-msg surface) delegates to `process-checklist.sh --check-commit-message`, which exits 1 via `guard_not_in_framework` (helpers-core.sh:184, CWD-based, no bypass) when run from the framework repo itself. The mothership is safe today ONLY because the framework repo installs no `.git/hooks/commit-msg` — the two other safety layers claimed in PR #169's body are false for the framework repo (it DOES contain scripts/process-checklist.sh, so the no-checklist no-op doesn't apply; and the delegate does NOT "phase-0 pass" from the framework root — it hard-fails via the guard, verifier-reproduced rc=1). If a commit-msg hook is ever wired into the framework repo (e.g. deeper dogfooding), its `feat:`/`fix:` commits would HARD-BLOCK (rc=1), not pass gracefully. Fix when triggered: give `bl006_terminal_enforce` an explicit in-framework-repo graceful pass, mirroring the C2 mothership-safety pattern for missing phase-state. A correction comment is on PR #169.

2. **`--amend` parity asymmetry (documented behavior, not a defect).** The PreToolUse surface passes through `git commit --amend` (allow+WARN, pre-commit-gate.sh:710) while the commit-msg surface cannot detect an amend (git sets no MERGE_HEAD/CHERRY_PICK_HEAD/REVERT_HEAD sentinel for it) and therefore enforces. Structurally forced, identical to how C2's `tdd_terminal_enforce` already ships, and arguably more correct (an amend introducing feat content should face the Build Loop); recorded so the divergence from strict "same pass-throughs" parity is on the books.

**Trigger:** (1) fires if/when anyone installs a commit-msg hook in the framework repo itself; (2) doc-only unless strict amend parity is ever demanded.

**Related:** BL-010 (PR #169 + its correction comment); BL-006; `scripts/pre-commit-gate.sh::bl006_terminal_enforce`; `scripts/lib/helpers-core.sh::guard_not_in_framework`; the C2 mothership-safety pattern (PR #166).

---

## BL-088: init.sh scaffold omits sourced dependencies (tdd-classify.sh, run-phase3-validation.sh) — TDD hard block silently no-ops downstream

**Logged:** 2026-07-11 (PR #173 adversarial review, empirical repro)
**Category:** Bug / deployment-gap + defect-class (fixture-hides-scaffold-gap)
**Severity:** High
**Status:** Closed — shipped 2026-07-11 (PR #175). Fix-first-flip-second: the fix commit + this flip are both in PR #175.

**What:** `init.sh` ships a CURATED `scripts/` copy list to every scaffolded project (`init.sh:~1305-1360`). It was never updated when BL-072 C2 (PR #166) added `scripts/lib/tdd-classify.sh`, which `scripts/pre-commit-gate.sh` sources via a silently-skipping loop (`:21-27` — absent ⇒ no-op). RESULT (empirically reproduced with a full hermetic `--deployment organizational --gov-mode sponsored_poc --language typescript --no-remote-creation` init): in a real scaffolded Sponsored-POC project a test-less `feat:` commit was ALLOWED (`rc=0`) — the flagship TDD hard block silently no-op'd downstream.

**The two instances (same class):**
1. `scripts/lib/tdd-classify.sh` — sourced by `pre-commit-gate.sh` (silent-skip loop) ⇒ the tier-keyed TDD hard block no-ops in the scaffold.
2. `scripts/run-phase3-validation.sh` — `check-phase-gate.sh`'s Phase-3→4 gate auto-runs / points the operator at it (`P3_DRIVER="$SCRIPT_DIR/run-phase3-validation.sh"`). Unshipped, the gate failed CLOSED but instructed the operator to run a script that did not exist — the pass-path was unreachable.

**Two further instances the closure check surfaced (also fixed):** `check-gate.sh` sources `scripts/lib/phase2-state.sh` (unguarded ⇒ "No such file or directory" crash) and `upgrade-project.sh` sources `scripts/lib/cdf-refresh.sh` (⇒ every scaffolded project silently skipped the CDF asset sync on upgrade). Neither was shipped.

**Why the wave's tests missed it:** every BL-072 test copies `tdd-classify.sh` into its OWN fixture (`tests/test-bl072-tdd-warn-detector.sh:311/:391` `cp "$REPO_ROOT"/scripts/lib/*.sh …`) — the fixture supplied the dependency the real scaffold lacked. Fixture-hides-scaffold-gap: the test scaffold is not byte-derived from `init.sh`'s copy mechanism, so it cannot see what `init.sh` fails to ship (precedent: BL-074, the same class in test scaffolds).

**The class fix (source-closure check):** `tests/test-scaffold-source-closure.sh` derives `init.sh`'s shipped set mechanically from its `cp` lines (not a hardcoded copy — that would drift; expands the `host-drivers/*.sh` glob) and asserts every `"$SCRIPT_DIR/<sibling>.sh"` a shipped script sources/execs is ALSO shipped (marker `# BL-088-CLOSURE`), excluding author-wired degrade-safe optionals (the `$PROJECT_ROOT`-preferred pre-commit-lint idiom). RED on pre-fix `init.sh` (4 gaps) → GREEN after (0 gaps, 42 shipped); mutation self-tests prove it load-bearing. This catches any FUTURE sourced-but-unshipped sibling, not just today's four.

**Fix:** `init.sh` ships the driver (+chmod) and the three libs; `verify-install.sh` adds them to its verify arrays + fix functions (`--auto-fix` heals existing projects, BL-074 precedent); `upgrade-project.sh` gains an idempotent source-closure backfill inside the backfill subshell — after the BL-015 sentinel guard (BL-081 ordering) — so `--backfill-only` and the full upgrade both heal existing projects. Also added the init.sh-driven fidelity test `tests/test-scaffold-tdd-block-real.sh` (real Sponsored-POC scaffold blocks the test-less `feat:` commit; upgrade/verify backfill regressions).

**Related:** BL-072 C2 (PR #166, added `tdd-classify.sh`); BL-070 (`run-phase3-validation.sh`); BL-074 (fixture-hides-scaffold-gap precedent); BL-015/BL-081 (sentinel-before-backfill ordering); PR #173 (surfacing adversarial review); PR #175 (this fix). `init.sh:~1305-1360`; `scripts/pre-commit-gate.sh:21-27`; `scripts/check-phase-gate.sh` BL-070-GATE-AUTORUN; `scripts/verify-install.sh`; `scripts/upgrade-project.sh`.

---

## BL-089: Scaffold documentation-foundation templates — doc map, pre-seeded identifier registry, archive-with-stubs convention

**Logged:** 2026-07-11 (Pantheon feedback A, amended per critique)
**Category:** Proposal / agent ergonomics (downstream)
**Severity:** Medium
**Status:** Open

**Decision 2026-07-20 (Karl):** GO. The `docs/IDENTIFIERS.md` pre-seed list is to be DRAFTED for his approval — "keep it as simple and logical as possible." Draft delivered 2026-07-20 (core minted namespaces TM-/ADR-/BUG-/UAT-/SEV + three registry rules). **APPROVED same day ("Labels approved") — the BL-089+091 WP is unblocked and in flight.**

**Status update 2026-07-20:** fix implemented on branch `feat/bl089-bl091-doc-foundations` (PR open; Closed with PR + merge SHA at merge). `# BL-089-DOC-FOUNDATIONS` in init.sh ships + instantiates all three foundations at birth (doc-index/identifiers/archive-readme tmpls → docs/INDEX.md, docs/IDENTIFIERS.md, docs/archive/README.md). `tests/test-bl089-doc-foundations.sh` 5/5 ×3 (both lists; fence-excision mutant) + real-init companion in the scaffold suite. Evidence: ledger § WP-BL089+BL091.

Pantheon's month of operation hit identifier-namespace collisions (four unrelated "D" schemes, two "F" schemes), ghost citations, and unmarked superseded docs. `init.sh` should generate three documentation foundations at project birth:
1. **`docs/INDEX.md`** — a doc-map skeleton with an explicit authority order (canon > dated design docs > archive) and a conventions section (name matches the mothership's own `docs/INDEX.md` convention).
2. **`docs/IDENTIFIERS.md`** — an identifier-scheme registry **pre-seeded with the namespaces the framework itself mints** (TM- threat rows, BUG-, ADR numbering, UAT scenario ids), carrying the rule "one prefix = one namespace; register before minting; cross-namespace references are always qualified." Amended from Pantheon's empty-file proposal: an empty registry with a rule is a documented-but-unenforced promise (the BL-070..073 defect species); pre-seeding makes it demonstrably in use from day one. No enforcement lint — a capital-letters-plus-digits heuristic would flag RFC-2119, ISO dates, and model names (BL-072's measured FP lesson).
3. **`docs/archive/` convention** — superseded working docs are MOVED there with a status banner **plus a pointer stub left at the old path** (the load-bearing half Pantheon's proposal omitted — archiving without stubs manufactures ghost citations, their own finding #2). Mirrors the mothership convention (BL-049; the 2026-07-11 estate consolidation, PR #174).

All three are template drops covered by the BL-088 scaffold-fidelity surface (new shipped files → closure/backfill implications; verify-install/upgrade backfill per BL-088 precedent).

**Related:** Pantheon `docs/2026-07-10-agent-legibility-remediation-plan.md` §U2 (external); BL-088 (shipped-set closure); BL-049 (archive convention); PR #174 (mothership estate consolidation); BL-090/BL-091/BL-092 (siblings from the same feedback).

---

## BL-090: check-doc-refs — doc-reference integrity checker (dogfood-first, measured rollout, then ship downstream)

**Logged:** 2026-07-11 (Pantheon feedback B1, amended per critique)
**Category:** Proposal / doc integrity + agent ergonomics (both repos)
**Severity:** Medium
**Status:** Open

**Decision 2026-07-20 (Karl):** EXTEND `lint-doc-anchors.sh` (the entry's consciously-required tool-home decision — one doc-integrity tool, not two drifting half-tools). Step 1 (build + dogfood on this repo, WARN-tier) is cleared for autonomous work; steps 2–3 remain blocked on the Pantheon FP-calibration corpus.

Pantheon's worst documented incident: a ghost "ADR-0003" cited in a dozen documents that never existed as a file, surviving three weeks of review. The mothership is exposed to the same class: `scripts/lint-doc-anchors.sh` validates only SAME-FILE anchors (BL-048), not relative file references or ADR-style citations. Build the missing capability:
- **Checker:** scans markdown for relative file references and ADR/identifier-style citations; fails when a target file does not exist. Consciously decide extension-of-`lint-doc-anchors.sh` vs sibling script (one doc-integrity tool beats two drifting half-tools) — justify in the PR.
- **Exemptions:** an inline `(planned)` marker next to the citation, NOT a separate allowlist file — allowlists rot into permanent exemptions (the KNOWN_ORPHANS bridge had to be sealed; BL-035). The marker lives beside the citation and dies with it.
- **Rollout, dogfood-first and measured:** (1) run on THIS repo; fix what it finds; wire into `run-lints.sh` + CI as WARN; (2) calibrate the false-positive rate — Pantheon's own month of history is a labeled corpus (its true positives are known); (3) WARN→BLOCK only on measured FP evidence, never on a calendar (BL-072 C1→C2 discipline); (4) then ship downstream via the existing ship-lints mechanism (`init.sh` already ships `lint-uat-scenarios.sh` + `lint-fixture-envelopes.sh`) + the CI template, under BL-088 closure/backfill.
- **Folded in (from Pantheon B2, demoted to advisory):** an advisory check that NEW handoff docs avoid bare `file:line` citations (the 2026-07-11 measured rot: 2 of 5 line-cites in a day-old handoff mis-resolved; markers are the citation primitive). Pantheon's "SUPERSEDED-markers-in-bottom-half" positional heuristic is dropped — a legitimate trailing History section false-positives immediately.
- House test standard applies: hermetic suite, RED→GREEN mutation proof, dual registration.

**Related:** BL-048 / `scripts/lint-doc-anchors.sh` (the sibling this extends); BL-035 (allowlist-rot lesson); BL-072 (measured-rollout discipline); BL-088 (ship + backfill); BL-089/BL-091/BL-092 (siblings).

---

## BL-091: Builders-guide documentation-rules section — corrections-on-top, single-home decisions, enforceable fail-closed rule

**Logged:** 2026-07-11 (Pantheon feedback C, amended per critique)
**Category:** Proposal / documentation doctrine
**Severity:** Low
**Status:** Open

**Decision 2026-07-20 (Karl):** GO, bundled with BL-089 in one WP once the IDENTIFIERS pre-seed draft is approved (this entry's rules reference the doc map/archive convention BL-089 creates).

**Status update 2026-07-20:** implemented in the BL-089 WP (same branch/PR). Builders-guide `## Documentation Rules` carries all seven rules (the rule-5 source-of-truth banner applied to the guide itself); the essentials ship downstream in doc-index.tmpl's Conventions; rule 6b landed as the REAL standing TM-001 silently-degraded-subsystem row in project-bible.tmpl — scanner-id-set-neutral, validated by the Phase-3 threat-model scanner from day one (a gate, not prose). Evidence: ledger § WP-BL089+BL091.

Add a documentation-rules section to `docs/builders-guide.md` (and generate the essentials into scaffold guidance):
1. **Corrections appear ABOVE what they supersede.** Append-only stacks are for ledgers (approval log, changelog) ONLY; living documents are rewritten in place with a short history. (Pantheon evidence: agents reading top-down absorbed stale claims first; a companion system was misdated for weeks by the equivalent bug.)
2. **Ledger vs living-document distinction** stated explicitly per document type in the doc map.
3. **Absolute language carries its premise.** Any "never/always" ruling records the premise beside it so reversal conditions are visible. Guidance only — unenforceable, and recorded as such.
4. **Single-home decisions (INVERSION of Pantheon's echo-list proposal).** Pantheon proposed per-ruling "echo lists" naming every copy — but a hand-maintained list of copies is duplicate truth about duplicate truth; their own finding #6 predicts its drift. The rule here: every decision has ONE canonical home; all other mentions LINK to it (stubs when things move). Echo lists only where duplication is genuinely forced, and then BL-090's checker verifies each echo cites the canonical home.
5. **Enforcement source-of-truth banners:** each guide that describes enforcement carries a one-line banner naming the gate scripts as canonical (prose may lag; the scripts do not). (Ergonomics audit F8 — enforcement claims currently live in ~6 documents with no drift detection.)
6. **Fail-closed loudness — relocated to an ENFORCEABLE surface.** Pantheon's rule ("any subsystem degraded by configuration says so loudly at startup" — their credential sat silently empty for 24 days) is an engineering rule, not a doc rule. Land it as: (a) a builders-guide engineering rule, and (b) a standing threat-model row in the PROJECT_BIBLE template ("silently degraded subsystem"), which the now-real threat-model scanner (PR #165) verifies at Phase 3 — a gate, not prose.
7. **Non-operator attribution:** quoted text from non-operator authors (multi-agent buses, external contributors) inside canon documents is attributed inline.

**Related:** Pantheon plan §U2; BL-090 (the checker that machine-verifies rules 4-5 where possible); PR #165 (threat-model scanner — the enforcement surface for rule 6); ergonomics audit F8.

---

## BL-092: Generated CLAUDE.md phase-scoped modularization + session-start token diet

**Logged:** 2026-07-11 (Pantheon feedback D, amended per critique + token survey)
**Category:** Proposal / agent token efficiency (downstream)
**Severity:** Medium
**Status:** Open — do LAST of the BL-089..092 quartet (largest change)

**Decision 2026-07-20 (Karl):** BREAK IT UP — context-size reduction is an explicit goal. Options analysis delivered same day; **Karl chose OPTION D**: the thin always-read index (his suggestion) PLUS retrieval enforcement — the checkpoint scripts (process-checklist/phase-gate) emit "read `docs/reference/X` now" at the exact consumption moments (UAT start → UAT authoring guide; Phase 3 entry → Phase-3/4 procedure), gate-checked where the procedure's outputs are checkable, degrading gracefully UPWARD into hook-based auto-injection on harnesses that support it. Proposed split list (persona table, UAT authoring, Phase-3/4 procedures ≈ a third of the file) rides with the build. Build follows the Dogfood-4 milestone.

**Measured problem (2026-07-11):** every downstream session front-loads `templates/generated/claude-md.tmpl` (236 lines; persona table + UAT authoring + Phase-3/4 procedure ≈ a third of it, inapplicable to most sessions), and the README kickoff prompt instructs a full read of the builders-guide (**2,018 lines ≈ 25-30k tokens**) plus intake + platform module at every fresh start. Pantheon's finding: chronically inapplicable instructions train agents to treat instructions as optional — consistent with the framework's own gate-credibility principle.

**Fix shape:**
1. Move persona/UAT/Phase-3-4 detail into on-demand files under the scaffold's `docs/reference/`, leaving **phase-scoped pointers** ("Phase 3 sessions: read docs/reference/uat-authoring.md before authoring UAT").
2. **Retrieval enforced, not hoped for:** the phase-gate / process-checklist machinery emits the "read X for this phase" reminder — the framework's phases are the structural advantage naive extraction lacks.
3. Kickoff prompt (README + init next-steps) becomes phase-scoped: read the builders-guide SECTION for the current phase, not the whole guide.
4. **Pointer-integrity guard (hard precondition):** template doc-pointers join the BL-088 scaffold-fidelity/closure surface — a pointer to an unshipped reference file is silent instruction loss (BL-088's class in doc form; Pantheon's finding #2). No modularization ships without this check.
5. **Acceptance is measured:** template + per-session mandatory-read token estimate before/after; zero instructions lost (pointers, not deletions); a behavioral spot-check that the right reference gets pulled in a phase-scoped session. Cheaper alternative to A/B first in one live project: phase-labeled sections within the existing file (most of the benefit, zero retrieval risk).

**Related:** BL-088 (closure surface); BL-089 (doc map the pointers live in); ergonomics audit F5-equivalent; `templates/generated/claude-md.tmpl`; `init.sh` next-steps output.

---

## BL-093: Split the backlog audit-trail into an archive file — 92% of the file is closed history every reader pays for

**Logged:** 2026-07-11 (agent token survey)
**Category:** Debt / agent token efficiency (mothership)
**Severity:** Low
**Status:** Open

**Measured (2026-07-11):** `solo-orchestrator-backlog.md` is 2,278 lines / 244KB; 81 of 88 entries are Closed/Resolved/Won't-Fix audit trail, 7 are open-ish. Every agent that opens the file for orientation pays ~60k tokens for ~8% signal.

**Fix shape:** move done entries to `solo-orchestrator-backlog-archive.md` (audit trail preserved — nothing deleted, per convention); the main file keeps Open/Deferred/Parked + the legend + a one-line pointer to the archive. Hard requirements: `scripts/lint-backlog-references.sh` spans both files; every `[[cross-reference]]` and `Related:` link between the two files is verified repo-wide before the move (BL-090-style referrer discipline — a broken cross-ref is the ghost-citation class); the what's-open grep recipe stays true; entries move WITH their full text (no stubs needed per-entry — one archive pointer in the legend suffices since entry IDs are unique and greppable across both files).

**Trigger:** any time; bundle-able with BL-090's checker (which can then verify the cross-file references mechanically).

**Related:** BL-090; the 2026-07-11 legend truth-up (PR #176); `scripts/lint-backlog-references.sh`.

---

## BL-094: Grep-anchored function/section indexes for the five biggest scripts

**Logged:** 2026-07-11 (ergonomics audit F7 + agent token survey)
**Category:** Debt / agent token efficiency (mothership)
**Severity:** Low
**Status:** Open

`init.sh` (~4,400 lines), `scripts/upgrade-project.sh` (~2,500), `scripts/intake-wizard.sh` (~2,250), `scripts/check-phase-gate.sh` (~1,900), `tests/full-project-test-suite.sh` (~2,230) have no top-of-file map; agents either read tens of thousands of tokens or grep blind (init.sh has only 29 named functions across 4,400 lines — much logic is inline sections). Add a ~15-line index header to each listing **function names and `# ====` section-marker names only — NO line numbers** (a line-numbered index self-stales; the 2026-07-11 measured handoff-rot rate was 40% within a day, and PR #176's own count went stale in the same PR that wrote it). Convention documented in CLAUDE.md. Acceptance: every index entry greppable verbatim; a follow-up check (fold into BL-090 or run-lints) can verify index entries still exist in the body.

**Related:** ergonomics audit F7; CLAUDE.md "big files" gotcha (PR #176); BL-046 (helpers split precedent for the deeper refactor this deliberately avoids).

---

## BL-095: Centralize deployment/poc_mode state parsing — nine scripts parse it inline today

**Logged:** 2026-07-11 (ergonomics audit F4, grown by BL-086)
**Category:** Debt / correctness + agent sync burden
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #211, merged 2026-07-18 `27d4a78`). `# BL-095-STATE-READERS` in helpers-core.sh; 13 reader sites migrated; conforming-inline siblings named at the fence; E/F verifier ran a ten-shape equivalence matrix on both jq arms (no gate outcome can change) and its detector-hole finding is fixed in-suite. Evidence: § WP-F4 + § PHASE E/F CONSOLIDATED.

**Measured (2026-07-11):** nine files read `poc_mode`/`deployment` from state (check-phase-gate.sh — three DIFFERENT extraction variants, per audit; intake-wizard.sh; reconfigure-project.sh; run-phase3-validation.sh — BL-086 added another; pre-commit-gate.sh; process-checklist.sh; upgrade-project.sh; init.sh; verify-install.sh), while `scripts/lib/enforcement-level.sh` sits mostly unsourced. The duplicated parsing already caused the BL-084 null/production mishandling class, and every new gate re-derives it (BL-086 just did). Agents changing tier logic must locate and sync N inconsistent copies.

**Fix shape:** single `read_deployment()` / `read_poc_mode()` (jq-with-grep-fallback, null-safe) in the shipped lib; migrate the nine call sites to it. **Predicates stay per-gate** where semantics deliberately differ (BL-084 bypass vs BL-086 license-tier) — this centralizes PARSING, not policy. Constraints: all existing mutation-proofed suites (BL-084, BL-072 C2, BL-086) stay green untouched in intent; the lib is on the shipped set (BL-088 closure covers it); migrate incrementally with per-site verification, not a big-bang.

**Related:** ergonomics audit F4; BL-084 (the defect class); `# BL-084-TIER-KEY` sync-comment sites; `# BL-086-TIER`; `scripts/lib/enforcement-level.sh`; BL-088 (closure).

**Status update 2026-07-17:** fix implemented on branch `fix/phase-f-bl129-bl130-bl096` (stacked on PR #210; PR number cited at close). `# BL-095-STATE-READERS-BEGIN/END` in `scripts/lib/helpers-core.sh` — `soif_read_phase_state_key <file> <key> [default]` + `soif_read_deployment`/`soif_read_poc_mode` wrappers (jq-first, quoted-value-grep fallback; JSON null / absent key / missing file ALL yield the caller's default on both arms). helpers-core.sh chosen deliberately: every gate consumer already sources it, every fixture already copies it, and init.sh already ships it — zero new sourcing surface, BL-088 closure already covers it. Migrated: check-phase-gate.sh (4 sites incl. the jq-with-grep-fallback dual + the adjacent `track` read), process-checklist.sh (1), upgrade-project.sh (6 — incl. the intake-progress reads, same top-level shape), intake-wizard.sh (2). **Deliberately NOT migrated (documented as sync siblings at the fence):** pre-commit-gate.sh (hook surface — a missing lib would brick commits, the BL-119 class), run-phase3-validation.sh (self-contained by design; harnesses copy it standalone), and verify-install.sh (reads the NESTED `.answers.poc_mode` shape from intake-progress.json — the readers are top-level-only by design). Legacy string-`"null"` post-guards kept at call sites (policy on legacy data, not parsing). `tests/test-bl095-state-readers.sh` 8/8 (both lists): unit contract + no-jq PATH stub + source-closure over the four migrated files + fence-excision mutant must CRASH check-phase-gate (routing proof, vacuous-proof in both directions). Evidence: § WP-F4.

---

## BL-096: Cold-start hardening bundle — CDF preflight, --tdd-only help truth, contributor hook bootstrap

**Logged:** 2026-07-11 (ergonomics audit F6/F9/F10 leftovers)
**Category:** Debt / agent + contributor onboarding
**Severity:** Low
**Status:** Closed — shipped 2026-07-17 (PR #211, merged 2026-07-18 `27d4a78`). `check-cdf-preflight.sh` (warn-and-continue at suite entry), `# BL-096-GATE-HELP` + `--commit-msg-gates` alias (behavior-pinned), `install-contributor-hooks.sh`; triple-arm mutation run killed each guard independently. Evidence: § WP-F5.

Three small onboarding traps the 2026-07-11 CLAUDE.md documents but does not fix at the point of failure:
1. **CDF preflight (F9):** tests/init.sh needing `~/.claude-dev-framework` fail deep in the suite on a fresh host; a preflight prints the exact `git clone` line at the point of failure instead.
2. **`--tdd-only` help truth (F6):** the flag runs TWO message gates (BL-072 TDD + BL-006 Build Loop; name kept for hook back-compat) — surface this in `pre-commit-gate.sh --help`/usage text, and consider a `--commit-msg-gates` alias (hooks keep the old flag).
3. **Contributor hook bootstrap (F10):** a one-liner (script or documented command) that installs `pre-commit-gate.sh` into `.git/hooks/` for framework contributors, so local commits face the same gates CI does instead of discovering them at PR time.

**Related:** ergonomics audit F6/F9/F10; CLAUDE.md (PR #176 — documents these; this entry fixes them at source); CONTRIBUTING.md.

**Status update 2026-07-17:** fix implemented on branch `fix/phase-f-bl129-bl130-bl096` (stacked on PR #210; PR number cited at close). F9: `scripts/check-cdf-preflight.sh` (init.sh's presence predicate; rc=1 + the exact clone line when absent) wired at `tests/full-project-test-suite.sh` ENTRY via `# BL-096-CDF-PREFLIGHT` — warn-and-continue (`|| true`) because the CI core shard runs CDF-less by design. F6: `pre-commit-gate.sh` gains a real `--help` (`# BL-096-GATE-HELP` — previously `--help` fell through to the stdin-JSON surface and exited 0 SILENTLY) stating that `--tdd-only` runs BOTH message gates (BL-072 + BL-006, name kept for hook back-compat), plus the adopted `--commit-msg-gates` honest-name alias (`# BL-096-COMMITMSG-ALIAS`, behavior-pinned to block identically). F10: `scripts/install-contributor-hooks.sh` (`# BL-096-CONTRIB-HOOK-INSTALL`; idempotent, refuses outside a framework checkout) + CONTRIBUTING.md now leads with the one-liner. `tests/test-bl096-cold-start.sh` 8/8 (both lists; RED watched 7/1 pre-fix; triple-mutation run killed each arm independently). Evidence: § WP-F5.

---

## BL-097: Subagent model-selection rubric — assess-and-select instead of inheriting the session model

**Logged:** 2026-07-11 (Karl directive, token-efficiency wave)
**Category:** Proposal / agent token efficiency + capability (both repos)
**Severity:** Low
**Status:** Open

**Decision 2026-07-20 (Karl, gates the BL-097/098/100 trio):** enforcement becomes a CONFIGURABLE OPERATING MODEL, not fixed doctrine — not every AI setup has multiple models. The user chooses the operating model at setup (per-ROLE model selection: architect, reviewer, programmer, etc.), the framework then ENFORCES the chosen policy, and a documented update path exists for when the choice proves too expensive (always-best) or not good enough (lower tier). Per-task/per-role model selection does not exist today and needs heavy design + architectural thought — a design doc (role taxonomy, config schema, enforcement surfaces, single-model degradation) precedes any build; sequenced after the Dogfood-4 milestone.

Orchestrating agents (in generated projects and on this repo) dispatch subagents that today either silently inherit the session's model or blanket-use the top tier — both wrong: silent inheritance caused a real 2026-07-10 incident (a fleet ran on an unintended model until killed), and blanket top-tier is cost overkill for mechanical work. The rule to encode wherever multi-agent dispatch is documented (the generated CLAUDE.md's Multi-Agent Parallelism section — `templates/generated/claude-md.tmpl`; the mothership `CLAUDE.md`; `docs/builders-guide.md` if it covers dispatch):

1. **Never inherit silently** — every dispatch names its model (and effort) explicitly.
2. **Assess per dispatch** on three axes: task difficulty (judgment/design vs mechanical), blast radius (does an error ship? gate/enforcement code = high), and downstream verification (strongly verified work tolerates a cheaper implementer).
3. **Tier guide:** top tier for enforcement/gate logic, adversarial verification, architecture judgment, and fact-verification documents; mid tier for routine well-specified implementation, doc drafting from verified sources, and structured refactors with strong tests; small tier for mechanical transforms, bulk searches, and classification sweeps.
4. **Verifiers ≥ implementers** in tier whenever the work is risky.
5. When uncertain: one tier up for enforcement code, one tier down for mechanical work.
6. **Transparency:** the dispatch summary states the fleet's model/effort mix so the operator can veto.

Sequencing note: if BL-092 moves the Multi-Agent section into a phase-scoped reference file, this rubric rides along — the two entries are compatible in either order.

**Related:** BL-092 (template modularization — shared surface); BL-089..BL-096 (the 2026-07-11 agent-optimization wave this joins); `templates/generated/claude-md.tmpl` (Multi-Agent Parallelism / Agent Personas sections); the 2026-07-10 model-inheritance incident (post-mortem `Reports/2026-07-11-project-post-mortem.md` §5).

---

## BL-098: Plan-first execution — the strongest model writes a junior-followable build plan before subagents build

**Logged:** 2026-07-11 (Karl directive; completes BL-097)
**Category:** Proposal / process + agent token efficiency (both repos)
**Severity:** Medium
**Status:** Open

**Decision 2026-07-20 (Karl):** governed by the trio decision recorded at BL-097 — configurable operating model, chosen at setup, then enforced, with a reconfigure path; design doc first, after the Dogfood-4 milestone.

BL-097's model-selection rubric says WHO can build cheaply; this entry supplies the WHAT-makes-that-safe: before any multi-subagent build (or any delegated implementation above trivial), the STRONGEST available model produces a build plan to a **junior-followable standard**, so execution agents know exactly what to build AND how — letting execution model/effort drop a tier without quality loss, because the judgment was front-loaded.

**The junior-followable standard** (set by living precedent — `docs/handoffs/archive/2026-07-09-gate-wave-execution-handoff.md` describes itself as "followable by a junior engineer" and this repo's 2026-07-09..11 wave executed cleanly from exactly such specs):
1. Exact surfaces: files + **grep-able marker/function citations** (never bare line numbers — the citation convention).
2. Step-by-step build order with contracts/interfaces stated, not implied.
3. The test list, written first-class: each case's intent and its expected RED→GREEN mutation proof where enforcement code is touched.
4. Explicit done-criteria and known traps (the handoff's ⚠️ pattern).
5. **Escalate-on-ambiguity rule stated IN the plan:** an executor that hits a gap or contradiction STOPS and returns it to the planner — improvising around plan gaps is where cheaper models fail and is forbidden.

**Process wiring:** plan authored by the top tier (BL-097 rule 3); the plan itself gets reviewed (adversarial review for gate/enforcement work; at minimum the work's verifier checks plan-conformance as a first-class target); execution dispatched per the BL-097 rubric; verifiers ≥ risk as before. Surfaces: the generated CLAUDE.md Multi-Agent Parallelism section + Superpowers writing-plans integration (`templates/generated/claude-md.tmpl`), `docs/builders-guide.md` construction/Build-Loop rules, mothership `CLAUDE.md`. Sequence-compatible with BL-092/BL-097 in any order (shared template surfaces — coordinate edits).

**Economics rationale:** planning is a small fraction of a build's tokens; execution is the bulk. A top-tier plan converts execution from judgment work into conformance work — the cheapest thing to verify and the safest thing to delegate down-tier.

**Plan lifecycle — anti-bloat rules (2026-07-11 amendment, Karl's follow-up: plans must not negate their own savings by becoming massive or stale reading):**
1. **Sliced, not omnibus.** Each executor ingests ONLY its own work-package plan slice — never a wave-wide document. (Precedent: the 2026-07-09 gate-wave dispatches extracted per-WP sections; no executor read the 29KB handoff whole.) Context budget is an acceptance criterion: an executor's mandatory pre-read (its slice + the scaffold CLAUDE.md) stays small — target a slice ≤ ~250 lines.
2. **Ephemeral by default.** Plans live in the dispatch prompt or a scratch file; the durable record is the PR body + the backlog citation (both already mandatory). A plan is COMMITTED only when it must cross a session boundary (a handoff) — and then it is archived-with-stub the moment it is executed (BL-049 / PR #174 convention; the 2026-07-09 handoff is already archived). Committed-plan accumulation is therefore bounded at "the one live handoff."
3. **Rewrite, don't accrete.** A revised plan REPLACES its predecessor with corrections on top — the BL-091 living-document rules apply to plans; append-only "Update:" stacks are forbidden outside ledgers.
4. **Freshness.** Plans cite grep-able markers/function names only (never bare line numbers — measured 40%/day rot); executors verify anchors before editing (CLAUDE.md rule); any committed plan falls under BL-090's reference checker.
5. **Bounded catch-up.** A fresh agent's full orientation read is: the scaffold/mothership CLAUDE.md + the single live handoff (if any) + its own plan slice. The backlog is consulted by grep recipe, guides by section, history never (BL-092/BL-093 enforce the fat ends of this).

**Related:** BL-097 (the rubric this enables); BL-092 (shared CLAUDE.md surface + session-start diet); BL-093 (ledger diet); BL-091 (living-doc rules that govern plans); BL-090 (reference integrity for committed plans); the 2026-07-09 gate-wave handoff (the standard's precedent); Superpowers writing-plans skill; `docs/superpowers/plans/` convention.

---

## BL-099: Complete the auto-update system — session-start freshness check for framework/hooks/CDF + a `--sync-framework` remediation mode

**Logged:** 2026-07-11 (Karl demand signal: "will the update script work on Pantheon?" + "I thought we had built in an auto update system")
**Category:** Proposal / product gap (upgrade + session-start surfaces)
**Severity:** Medium
**Status:** Closed — folded into BL-109 (Karl's 2026-07-20 decision). Every piece is shipped or absorbed: SLICE-A (`--sync-framework` + dry-run + hook consent + the manifest pin) shipped PR #185; piece 1 (session-start freshness) superseded by and shipped as BL-109 L1/S2 (PR #193, merged `c564739` — fast, offline-safe, silent-when-current, names the remediation, exactly piece 1's contract); piece 3 (hook backfill) landed across BL-107 universal install (PR #205) + BL-141 verify-install repair/sync WARN (PR #225 `cf10873`). Remaining update-pipeline work continues under BL-109's ladder only — one umbrella, no drift.

**Progress — SLICE-A shipped (PR #185):** `upgrade-project.sh --sync-framework` (piece 2) + `--dry-run` + ask-first hook install/refresh (piece 3) + framework doc-drift notices + `manifest.soloFrameworkCommit` pin. Rendered docs (`CLAUDE.md`/`PROJECT_INTAKE.md`) are notice-only in this slice — assisted apply is the new **BL-101**. **SLICE-B (piece 1, session-start freshness check) is still pending** — this entry stays Open until it lands.

**What exists today (verified):** tools are auto-checked at every session load — `scripts/session-version-check.sh` is injected as a SessionStart hook by `init.sh` (~:1750), wraps `check-versions.sh`, silent-when-current, never auto-updates ("always ask first," per the generated CLAUDE.md Session Start rules). **What does not:** framework freshness is manual-and-detection-only (`scripts/check-updates.sh` — operator-run, compares docs vs upstream, applies nothing, wired into no hook); nothing anywhere checks whether a project's installed git HOOKS are current (the C2 commit-msg hook gap on pre-2026-07-10 projects is invisible to every existing check); CDF assets refresh only during upgrade runs (BL-001); and `upgrade-project.sh` has NO same-tier sync mode — its purpose is tier changes, so gate scripts (`pre-commit-gate.sh`, `check-phase-gate.sh`, `process-checklist.sh`) only refresh as a tier-change side effect. Net: a month-old project (Pantheon) cannot cleanly reach current framework behavior at its current tier.

**The three missing pieces:**
1. **Session-start freshness check** (extend the `session-version-check.sh` pattern — fast, offline-safe, silent-when-current): compare `.claude/manifest.json::frameworkVersion/frameworkCommit` against the local framework clone when one is configured (skip silently when absent — never clone at session start); check installed hooks against the current hook set; check CDF asset staleness the way `check-updates.sh` compares docs. Output one loud line per stale surface, with the remediation command named.
2. **`upgrade-project.sh --sync-framework`:** same-tier refresh of the vendored gate scripts, helper set, and templates from the framework copy being run, under the full existing discipline — BL-015/081 sentinel-first, BL-088 source-closure backfill, idempotent, plus a `--dry-run` (the script currently has none). This is the remediation the freshness check points at.
3. **Hook backfill decision:** sync mode must handle hooks explicitly — pre-C2 projects lack `.git/hooks/commit-msg` entirely (PR #166 shipped install-time-only, disclosed); refresh-or-install with ask-first consent, never silently (the framework's attested-not-silenced doctrine applies to hook changes too).

**Discipline unchanged:** detection is loud and automatic; remediation is consented, never auto-applied — the existing "Do NOT auto-update anything — always ask first" CLAUDE.md rule governs all three pieces.

**Related:** BL-001 (CDF refresh); BL-088 (closure/backfill machinery this reuses); PR #166 (hook install-time-only decision); `scripts/check-updates.sh`; `scripts/session-version-check.sh`; `scripts/check-versions.sh`; `init.sh:~1750` (hook injection pattern); the 2026-07-11 Pantheon upgrade assessment (demand evidence).

---

## BL-100: Adversarial verification of delegated work — official acceptance step for subagent-built changes

**Logged:** 2026-07-11 (Karl directive; completes the BL-097/BL-098 delegation trio)
**Category:** Proposal / process (both repos)
**Severity:** Medium
**Status:** Open

**Decision 2026-07-20 (Karl):** governed by the trio decision recorded at BL-097 — the adversarial-acceptance rule becomes part of the chosen-and-then-enforced operating model (single-model setups need a degradation story: fresh-context same-model verification). Design doc first, after the Dogfood-4 milestone.

**What is official today:** adversarial personas at ten named phase steps (generated CLAUDE.md persona table — fresh context, refute-minded), the per-feature security audit (Build Loop 2.4, five parallel audit agents), and the gate-enforced Phase-3 review manifest with the `evaluation-prompts/` library. **What is missing:** between gates, a delegated (subagent-built) change has no required independent acceptance step — the implementing agent's own report is the only evidence its work is accepted on.

**The rule to encode** (surfaces: generated CLAUDE.md Multi-Agent Parallelism section, `docs/builders-guide.md` Build Loop, mothership `CLAUDE.md`; coordinate with BL-092/BL-097/BL-098 on the shared template surfaces):
1. Every delegated implementation above trivial is accepted only on an **independent adversarial verifier's verdict** — a fresh agent prompted to REFUTE, not confirm (the fresh-context principle the persona table already codifies, applied per change).
2. **Calibrated rubric** with explicit criteria: `block` (any implementer claim contradicted by observation, or a known defect-class regression — silent-success, weak-test, non-hermetic, unregistered), `major_concerns` (vacuous assertion, spec miss, the verifier's own mutation survives), `minor_concerns`, `approve` = "tried to refute and failed." `major_concerns`+ blocks acceptance; verifiers must not default to minor to be polite (the Wave-3 lesson).
3. **Claim reproduction:** the verifier independently re-runs every suite, lint, and check the implementer cites.
4. **Double-mutation for enforcement/gate code:** the verifier designs and runs its OWN mutation, distinct from the implementer's documented proof; a surviving mutation = `major_concerns` minimum (weak-test class).
5. **Tiering per BL-097:** verifier tier ≥ the work's blast radius — gate code verifies at top tier even when the implementation safely ran mid-tier.
6. **Separation:** verifiers never fix — findings return to the planner/implementer (the BL-098 escalation loop), preserving reviewer independence.

**Evidence this works (the 2026-07 gate + doc waves, `Reports/2026-07-11-project-post-mortem.md`):** the pattern caught the BL-088 scaffold deployment gap the entire registered test suite missed (surfaced by PR #173's verifier refusing to let the README oversell), killed surviving mutations behind PRs #160/#166/#168/#175, disproved the orchestrator's own false-alarm backlog tidy (PR #168), and was itself refuted-with-evidence once (PR #173's dead-path finding) — i.e., the protocol self-corrects in both directions.

**Related:** BL-097 (who builds and verifies) + BL-098 (plan-first) — together the complete delegation protocol: plan → right-sized build → adversarial acceptance; BL-092 (shared CLAUDE.md surface); the archived 2026-07-09 gate-wave handoff §0 rule 3 (the arc-scoped precedent this makes permanent).

---

## BL-101: Assisted apply for rendered docs — regenerate CLAUDE.md/PROJECT_INTAKE from recovered project vars + three-way merge

**Logged:** 2026-07-11 (spun out of BL-099 SLICE-A, PR #185)
**Category:** Proposal / product (upgrade surface)
**Severity:** Low
**Status:** Closed — folded into BL-109 (Karl's 2026-07-20 decision). The core work shipped as BL-109 L2/A1: S3's staging factored `generate_claude_md` into the parameterized generator and builds the A1 render-leg candidates through it (PR #194, merged `4f2b4d3`). The one open UX question is DECIDED (Karl 2026-07-20): conflict handling = `.rej`-style droppings (headless-agent compatible, the BL-128 direction), WITH a LARGE, unmissable warning to the user whenever a conflict artifact is produced — recorded as a requirement on BL-109 S4/apply.

**Why:** `upgrade-project.sh --sync-framework` (BL-099 SLICE-A) refreshes vendored scripts/hooks and *notices* framework doc drift, but it deliberately never rewrites `CLAUDE.md` / `PROJECT_INTAKE.md`: both are **sed-rendered** from templates (`templates/generated/claude-md.tmpl`, `templates/project-intake.md`) with project-specific substitutions and, for `PROJECT_INTAKE.md`, appended tool tables. A blind copy would clobber the operator's rendered/customized file with an unrendered template full of `__PLACEHOLDER__`s — so the slice shows a template-level diff (against the `manifest.soloFrameworkCommit` pin SLICE-A now stamps) and stops there.

**The work:** an *assisted apply* mode that
1. factors `init.sh`'s `generate_claude_md` (and the `PROJECT_INTAKE.md` cp + `append_intake_tooling_summary` flow) into a **parameterized generator** callable outside a full `init.sh` run;
2. **recovers the render variables** — `PROJECT_NAME`, `PROJECT_DESCRIPTION`, `PLATFORM`, `TRACK`, `LANGUAGE`, `TEST_INTERVAL`, `DEPLOYMENT` — from project state (`.claude/phase-state.json`, `.claude/tool-preferences.json`, `.claude/manifest.json`, the existing `CLAUDE.md`);
3. re-renders the current template with those vars and offers a **three-way merge** (old render / new render / operator's file) so upstream template improvements land without discarding customizations.

**Enabled by:** the `soloFrameworkCommit` pin SLICE-A ships (gives a base commit for the three-way diff). **Related:** BL-099 (parent), BL-092 (shared CLAUDE.md template surface).

---

## BL-102: The Market Signal DECISION GATE (Step 1.1.5) is hollow — no home, no evidence standard, no enforcement

**Logged:** 2026-07-11 (surfaced while mining github.com/TexasBedouin/vibe-check — MIT © 2025 Amer Arab; adopted as IDEA, not vendored)
**Category:** Bug / gate credibility — documented-but-not-enforced (the framework's cardinal defect class)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #204, merged 2026-07-18 `a5f2a09`). Appendix D (Market Signal & Go/No-Go) in the manifesto template + `# BL-102-MARKET-SIGNAL` WARN-first evidence arm (anchored placeholder regex, track≠light); parity pinned on the empirically-clean issues=0 fixture. Evidence: § WP-B3.

**Status update 2026-07-17:** pieces 1–3 implemented on PR #204 (branch `fix/bl124-bl102-promotion-ratchet`), awaiting merge. Piece 1: `templates/generated/product-manifesto.tmpl` ships Appendix D (signal table, `seen it`/`hunch`/`guess` tags, fail-closed verification protocol + counts, Go/No-Go record, Light-track SKIPPED line). Piece 2: builders-guide Step 1.1 gains its missing prompt block; Step 1.1.5 gains the evidence grammar + source-agnostic verification protocol. Piece 3: `# BL-102-MARKET-SIGNAL` in check-phase-gate.sh — Phase 1→2 WARN-first (deliberately NO `issues` increment, per the entry's grandfather discipline; escalate later) on missing/placeholder Appendix D for track≠light. The non-blocking property is pinned by EXIT-CODE PARITY on an issues=0 fixture and its mutation case proves an injected increment breaks the parity (the BL-104 [WARN]-trap inverse, guarded both ways for the first time). Adversarial verifier (Opus) SHIP; its placeholder-regex over-match finding fixed pre-push (pattern anchored to the template's `[customer interview /` syntax; link labels no longer trip it). Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-B3.

**What is declared (verified):** `docs/builders-guide.md:659` Step 1.1.5 — *"**Performed by the Orchestrator, not the AI.** At least one market signal before committing to architecture. Record the signal type (customer interview, letter of intent, survey result, landing page signups) and outcome in the Product Manifesto appendix or Project Bible. 'At least one positive signal' means documented evidence, not a gut feeling."* followed by *"**DECISION GATE — If no positive signal, return to Phase 0.**"* It is `Required` on **Standard** (the DEFAULT track — `init.sh:3884` `: "${ARG_TRACK:=standard}"`) and Full (interviews/LOIs), SKIP on Light (`docs/builders-guide.md:182`). Step 1.1 (Business Strategy Gateway — Go/No-Go) is a one-line directive with **no prompt block**, unlike every sibling step.

**Why it is hollow (four verified proofs):**
1. **No script enforces it.** `grep -rliE 'market.?signal|go.?no.?go' scripts/` → **zero hits** across check-phase-gate.sh, process-checklist.sh, pre-commit-gate.sh, run-phase3-validation.sh.
2. **The home it names does not exist.** The gate says "record it in the Product Manifesto appendix"; `templates/generated/product-manifesto.tmpl` ships **Appendix A** (Revenue Model), **Appendix B** (Orchestrator Competency Matrix), **Appendix C** (Trademark & Legal) — there is **no market-signal appendix**, and `project-bible.tmpl`'s sections have no slot either. The framework instructs the operator to file an artifact into a slot it never ships — [[bl088-scaffold-source-closure]]'s silent-instruction-loss class, in artifact form.
3. **No evidence standard.** Step 1.1 is the ONLY place the framework sends an AI to fetch evidence from OUTSIDE the project, and it is the only claim class with no verification protocol (repo-wide grep for hallucinat/fabricat/permalink/re-fetch/unverified finds only "don't fabricate strengths" in the eval prompts — about review *output*, not sourcing). Meanwhile `CLAUDE.md`'s CITATION RULE already mandates re-verifying every citation before trusting it — for code. The reflex was never applied to research.
4. **The framework predicted the skip.** `evaluation-prompts/Framework/Framwork Multi user test plan.md:290` — *"Market signal validation (Standard+ track) | Performs lightweight validation | **Skips — doesn't realize it's required for Standard** | N/A"*.

**The three pieces:**
1. **Manifesto Appendix D — Market Signal & Go/No-Go Evidence** (`templates/generated/product-manifesto.tmpl`; Standard+, explicit "SKIPPED — Light track / internal tool" line otherwise). Table: claim / signal type (interview, LOI, survey, landing-page signup, competitor-review corpus) / source + permalink / evidence tag / verification outcome — plus the Go/No-Go decision and rationale (Step 1.1 already requires the decision be persistent and auditor-verifiable).
2. **Evidence grammar + source-verification protocol** in `docs/builders-guide.md` Steps 1.1/1.1.5, and give Step 1.1 the fenced prompt block it lacks. Tags: **`seen it`** (≈3 independent sources) / **`hunch`** (plausible, unconfirmed) / **`guess`** (inferred) — *a differentiator built on a hunch is a bet, not a finding*. Protocol (adapted, MIT): re-fetch every deliverable-bound source; **text-match, not gist-match** (the quoted words must be findable at the URL; only `[...]` elisions); **fail closed** (an unverified source cannot lift a claim to `seen it`, and cannot carry it alone); **a high fail rate condemns the whole sweep** (re-research, don't salvage); **record the counts** (checked / failed / dropped). Deliberately **source-agnostic** — adopt the STANDARD, not vibe-check's Reddit/Redlib fetch ladder (it depends on volatile third-party mirrors and admits its own rung-1 failure; never gate on it).
3. **Enforcement (phase 2 of the work):** `check-phase-gate.sh` Phase 1→2 verifies Appendix D exists and is non-placeholder when `track != light` — **WARN first, escalate later** (gate-credibility discipline: never hard-block on a slot existing projects don't have; cf. BL-073's grandfather clause). Full TDD + mutation proof; new test registered in BOTH `tests/full-project-test-suite.sh` and the `tests.yml` unit list.

**Scope discipline:** ships as a bounded template appendix + a builders-guide rule — NOT a vendored skill, NOT a new reference file. Net session-start token delta ≈ zero (Appendix D is written at Phase 1, not read at kickoff) — [[bl092-claude-md-phase-scoped-modularization]] constrains the shape.

**Explicitly out of scope (evaluated and rejected):** vibe-check's ODI opportunity score (optional aid at most), its Reddit/review fetch pipeline, growth loops / cold-start / marketplace discovery, "Checkup Mode" (a beginner translation of a mattpocock skill whose original the framework already vendors; produces no framework artifacts), and its interactive-PRD/diagram engine (our UAT HTML + workflow.html are already stricter — zero external URL refs vs its CDN fonts/CSS).

**Related:** [[bl088-scaffold-source-closure]] (same defect class — an instruction pointing at something the scaffold never ships); [[bl100-adversarial-acceptance]] (this is its research-side sibling: verify the claim, fail closed); [[bl092-claude-md-phase-scoped-modularization]] (constrains the shape); `docs/builders-guide.md:659` (Step 1.1.5) + `:182` (track table); `templates/generated/product-manifesto.tmpl`; `evaluation-prompts/Framework/Framwork Multi user test plan.md:290` (the predicted skip); upstream `references/DISCOVERY-DEEP-DIVE.md` (MIT © 2025 Amer Arab).

---

## BL-103: The six-eval generator is dead on arrival — bash-3.2 parse failure + slug/filename mismatch force every macOS operator to attest past the Phase 3→4 security gate

**Logged:** 2026-07-11 (eval-prompt hollow-gate audit, triggered by BL-102)
**Category:** Bug / gate integrity — the framework's flagship review gate has a broken remediation path
**Severity:** **High** (the gate is real and blocking; its ONLY documented remediation cannot execute; the sole escape is the attestation bypass)
**Status:** Closed (PR #187, 2026-07-11)

**Resolution (PR #187, 2026-07-11).** All four fix steps shipped, TDD with mutation proofs:
1. **Portability.** `Projects/run-reviews.sh`, `Projects/compose.sh` and `Framework/run-reviews.sh` rewritten to bash-3.2 (`case` dispatch replaces `declare -A`; no `[[ -v ]]`). `/bin/bash -n` is now clean for every `evaluation-prompts/**/*.sh` on the 3.2.57 reference host.
2. **Single source of truth.** The **base prompt** declares the artifact filename and is now the ONLY place that does. `compose.sh --artifact <reviewer>` DERIVES it by parsing that declaration; `run-reviews.sh` keeps no filename table. Drift is impossible rather than merely detectable, and a prompt with zero or >1 declarations is a hard error instead of a silent probe-miss. `senior-engineer` / `technical-user` / `red-team` now resolve — a performed Red Team review is RECORDED.
3. **New lint** `scripts/lint-evalprompts-portability.sh` (`# BL-103-PORTABILITY`): `/bin/bash -n` + bans `declare -A` and `[[ -v ]]` across `evaluation-prompts/**`. Wired into `scripts/run-lints.sh` (now 11/11) and a new `evalprompts-portability-lint` job in `.github/workflows/lint.yml`.
4. **Integration test** `tests/test-bl103-eval-generator.sh` (29 passed) RUNS the real generator against a hermetic fixture (mock `claude`, no network) and lints the manifest it emits — closing the fixture-hides-product-gap hole.

**Defect 3, found while building the test (not in the original report): every manifest the generator ever wrote was INVALID JSON.** `$(echo "$MANIFEST_ENTRIES" | sed '$ s/,$//')` — `MANIFEST_ENTRIES` is already newline-terminated, so `echo` appended a second newline and sed's `$` address landed on a trailing EMPTY line; the real last entry kept its comma. `jq empty` rejects the file, so `lint-review-manifest.sh` FAILs it and the gate's `jq '.reviews | length'` reads nothing. Invisible until now because the script could not parse far enough to reach the write. Fixed, plus a `jq empty` self-check that refuses to emit a manifest the gate cannot read.

`init.sh` now also scaffolds `docs/eval-results/` (the manifest's required home — see BL-105, which listed the same gap).

Original entry (pre-close, kept for audit trail):

**The gate is real.** `scripts/check-phase-gate.sh` (`# BL-073-ESCALATE`) hard-FAILs the Phase 3→4 transition for `track ∈ {standard, full}` when the Security or Red Team review is missing/incomplete, and its failure message directs the operator to *"Run reviews: `evaluation-prompts/Projects/run-reviews.sh`"*.

**Defect 1 — the generator cannot start on the reference platform (verified live).**
```
$ /bin/bash --version           → GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
$ /bin/bash -n evaluation-prompts/Projects/run-reviews.sh
  line 142: conditional binary operator expected
  line 142: syntax error near `"REVIEWERS[$num]"'
```
`run-reviews.sh:104` uses `declare -A REVIEWERS`; `:142`/`:198` use `[[ ! -v … ]]` — both bash ≥4.2. macOS `/bin/bash` is 3.2.57 and the shebang is `#!/bin/bash`. This violates the repo's own house rule (`CLAUDE.md`: *"no associative arrays (`declare -A`)"*) — but **no lint covers `evaluation-prompts/`**. `evaluation-prompts/Projects/compose.sh` (called by the runner) and `evaluation-prompts/Framework/run-reviews.sh` carry the same break.

**Defect 2 — the filename contract is mismatched (independent of Defect 1; bites on bash-5 hosts too).** `run-reviews.sh:207` probes `"$PROJECT_DIR/${reviewer}-review-v1.md"` where `${reviewer}` is the REVIEWERS-map slug (`:104-110`), but the base prompts instruct the reviewer to save under a different name:

| slug (runner probes) | base prompt writes | |
|---|---|---|
| `engineer` → `engineer-review-v1.md` | `senior-engineer-review-v1.md` (01) | ✗ |
| `techuser` → `techuser-review-v1.md` | `technical-user-review-v1.md` (05) | ✗ |
| **`redteam` → `redteam-review-v1.md`** | **`red-team-review-v1.md` (06)** | ✗ |
| `cio` / `security` / `legal` | match | ✓ |

The manifest entry is emitted only `if [ -f "$REVIEW_FILE" ]`. **Red Team is one of the two mandatory BLOCKING reviewers** — so a Red Team review that was actually performed and saved exactly as instructed is recorded as missing, and the gate FAILs.

**Operator experience:** gate blocks → operator runs the named remediation → syntax error (macOS) or a silently-missing Red Team entry (Linux) → the only path forward is `SOLO_REVIEWERS_ATTESTED=1`. **The framework herds every macOS operator into attesting past its own flagship security gate.** `init.sh:1290-1292` ships the broken generator into every project and `init.sh:1930` stamps `review_gate_enforced: true`, so every new standard/full project inherits it.

**Why it shipped green:** `tests/test-bl073-review-manifest-gate.sh` builds its manifest with a `write_manifest` heredoc and **never invokes the generator** — the gate is tested, the generator is not. Fixture-hides-product-gap, the [[bl088-scaffold-source-closure]] class in tooling form.

**Fix:** (1) rewrite `Projects/run-reviews.sh` + `Projects/compose.sh` + `Framework/run-reviews.sh` in bash-3.2 (indexed arrays or `case`; no `[[ -v ]]`); (2) align the three slugs to the prompt-declared filenames (single source of truth — derive one from the other, don't maintain two lists); (3) add `scripts/lint-evalprompts-portability.sh` (`bash -n` under `/bin/bash` + ban `declare -A` / `[[ -v ]]` across `evaluation-prompts/**`), wired into `scripts/run-lints.sh` + CI; (4) add an integration test that RUNS the generator against a fixture project and lints the manifest it emits (closing the fixture-hides-gap hole).

**Related:** BL-073 (the gate this breaks the remediation for); [[bl088-scaffold-source-closure]] (same class: shipped-but-broken/absent dependency, hidden by a fixture); `CLAUDE.md` portability rules; BL-104/105/106 (siblings from the same audit).

---

## BL-104: Phase-gate scoring inversions — zero Phase-3 steps silently PASSES, and an empty review manifest is a bypass

**Logged:** 2026-07-11 (eval-prompt hollow-gate audit)
**Category:** Bug / gate correctness (perverse incentives)
**Severity:** Medium
**Status:** Closed (PR #187, 2026-07-11)

**Resolution (PR #187, 2026-07-11).** Both inversions closed, TDD + marker-excision mutation proofs, in `tests/test-bl104-gate-scoring.sh` (13 passed).

1. **Zero-step silent pass** — added the missing `else` arm (`# BL-104-P3-ZERO`). **It INCREMENTS `issues` (blocks).** Reasoning: the arm above blocks at 1-8 steps; a gate where 8/9 blocks and 0/9 passes is not a gate. Zero is strictly worse than eight and must score at least as harshly. Projects with genuinely no Phase-3 state are unaffected — the whole block is guarded by `[ -f ".claude/process-state.json" ]`, so this arm only fires when the file EXISTS and records nothing ("checklist never started"), not when information is absent.

2. **Empty-manifest bypass** — the arms scored on FILE EXISTENCE, not review CONTENT. Now a manifest attesting to **zero completed reviews** is treated as materially identical to **no manifest** and blocks the same way (`# BL-104-MANIFEST-ARM`). Deliberately narrow, and chosen over two rejected alternatives: making the no-manifest arm stop incrementing would WEAKEN the gate (a light project with no reviews would stop blocking); making every incomplete manifest block would BREAK the documented contract (`builders-guide.md`: *"track=light / personal: WARN only (POC preserved)"*). So a **partial** manifest (≥1 completed review) keeps the light/grandfathered WARN-only behavior (pinned by `T-light-track-warn-only-preserved`), and the enforced standard/full FAIL is untouched (pinned by `T-empty-manifest-enforced-fails`).

3. **The trap is documented** in `CLAUDE.md` § ENFORCEMENT: `[WARN]`/`[FAIL]` text is cosmetic; the exit predicate is `if [ $issues -eq 0 ]`, so any WARN that runs `issues=$((issues + 1))` BLOCKS, and a true WARN must omit it.

**Collateral finding:** `tests/test-bl073-review-manifest-gate.sh`'s `build_project()` fixture called itself a "golden-clean Phase-3 project" while writing `"steps_completed": []` — it was **riding inversion 1**, and four of its cases went RED the moment the `else` arm landed. The fixture was corrected to record the nine steps it always claimed (29/29 green). Another fixture-hides-product-gap, same class as BL-103.

Original entry (pre-close, kept for audit trail):

Two verified scoring defects in `scripts/check-phase-gate.sh`:

1. **Zero-step silent pass (P3-007).** The Phase-3 checklist cross-check reads:
```bash
if   [ "$p3_steps_done" -ge 9 ]; then  [OK]
elif [ "$p3_steps_done" -gt 0 ]; then  [WARN]; issues=$((issues + 1))   # blocks
fi                                                                       # 0 → NEITHER arm → PASS
```
**Never touching the Phase 3 checklist passes the gate; completing 8 of 9 steps blocks it.** Diligence is punished, total neglect sails through. Fix: add the missing `else` arm (0 steps → WARN, and — per gate-credibility discipline — decide deliberately whether it increments).

2. **Empty-manifest bypass.** The *no-manifest* WARN arm increments `issues` (→ blocks), while the *incomplete-manifest* (grandfathered/light) WARN arm does not (→ passes). So `echo '{"reviews":[]}' > docs/eval-results/review-manifest.json` converts a blocking gate into a passing one. It also contradicts the documented contract (`builders-guide.md`: *"track=light / personal: WARN only (POC preserved)"* — yet an absent manifest currently blocks light track). Fix: make the two arms consistent with the documented contract; TDD + mutation proof.

**Also document the trap:** in `check-phase-gate.sh`, `[WARN]` vs `[FAIL]` is **cosmetic** — the exit predicate is `if [ $issues -eq 0 ]`, so any WARN that also runs `issues=$((issues + 1))` **blocks**. A true WARN must omit the increment. This has bitten twice; record it in `CLAUDE.md` (Enforcement section) so the next "WARN-first" check doesn't accidentally hard-block.

**Related:** BL-073; BL-103; `CLAUDE.md` ENFORCEMENT section.

---

## BL-105: Declared MUSTs with no home and no check — rollback test, monitoring verification, go-live, UAT sign-off, trademark, revenue, competency matrix, Go/No-Go

**Logged:** 2026-07-11 (eval-prompt hollow-gate audit)
**Category:** Debt / gate credibility (documented-but-not-enforced, the framework's cardinal class)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #209, merged 2026-07-18 `6a21f99`). Phase 4 has a real gate: `# BL-105-START4-GATE-CONSULT` + `# BL-105-PHASE4-GATE` (presence keyed on started_at + the FILE's real phase — no circularity), three substantive-evidence arms, both approval-log templates gain UAT sign-off + attorney/pen-test slots; T6 of the upgrade suite rewritten to the gate-keyed door (documented-bug exception). Residuals recorded in § WP-E1b (competency depth, pass-path golden fixture, gate-side UAT reader). Evidence: § WP-E1b.

**Status update 2026-07-17:** fix implemented on PR #209 (branch `fix/bl105-phase4-wave`), awaiting merge. `# BL-105-START4-GATE-CONSULT` (start-phase4 consults the 3→4 gate; refusal leaves state untouched) · `# BL-105-PHASE4-GATE` (a never-started checklist — `started_at` null — blocks at phase≥4) · substantive-evidence arms for rollback/monitoring/go-live (empty file / the word "monitoring" / bare RELEASE_NOTES existence all now REJECTED, with real-evidence pass cases pinned) · UAT Sign-off sections added to BOTH approval-log templates + Attorney/Pen-Test added to the personal one · artifact-map mis-map fixed + `handoff_tested` (D-6) documented · Competency Matrix WARN-first visible in the 0→1 gate. `docs/eval-results/` sub-item was already closed by BL-103. Residuals recorded: validate.sh competency depth (reads PROJECT_INTAKE, 4/9 domains); pass-path `--start-phase4` advance mechanics pending a golden 3→4 fixture; UAT sign-off gate-side check (the section now exists — a reader arm is future work). 11/11 suite incl. double-fence mutation. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-E1b.

The audit's hollow set beyond BL-102/103/104. Each is declared **MUST**/**DECISION GATE**/**MANDATORY** in `docs/builders-guide.md` but lacks a home, a check, or both:

- **Phase 4 has NO gate at all** — `phase4_release` appears nowhere in `check-phase-gate.sh`. The rollback-test (Step 4.1.5, "**MUST**"), monitoring verification (4.3, *"'Configured' is not 'verified'"*), and go-live smoke test (4.2, "**DECISION GATE**") have real artifact checks in `process-checklist.sh` — but nothing ever forces the checklist to run, and Phase 4 is terminal. Predicted by the framework's own test plan (skips rollback / monitoring / smoke test).
- **Step 3.6 Final UAT sign-off** — "formal acceptance sign-off recorded in `APPROVAL_LOG.md`", but **neither approval-log template has a UAT sign-off section**, and `pre_launch_preparation` has no artifact-check arm.
- **Manifesto Appendices A/B/C are invisible to the Phase 0→1 gate** — `validate_manifesto_content` loops sections `1..8` only, so Revenue (A), Competency (B), and Trademark (C) can all be absent and the gate passes. The guide's Phase-0 Artifact Map (`:617-619`) additionally MIS-MAPS these to Sections 6/7/8, which are actually Post-MVP Backlog / Will-Not-Have / Open Questions.
- **Competency Matrix** — `builders-guide.md` calls it *"not advisory"* with two MUSTs; the only implementation (`validate.sh::check_competency`) is **never invoked by any gate, hook, or CI**, reads `PROJECT_INTAKE.md` instead of Appendix B, and covers 4 of 9 domains.
- **Step 1.1 Business Strategy Go/No-Go** — a DECISION GATE with no prompt block, no slot (Manifesto has no Appendix D), and zero script hits. (Sibling of BL-102; fix them together in the Appendix-D work.)
- **`docs/eval-results/`** is never created by `init.sh` — the directory the review manifest must live in doesn't ship.

**Fix shape (WARN-first throughout — never hard-block on artifacts existing projects lack):** add the missing template sections (Manifesto Appendix D; approval-log UAT/pen-test/attorney sections incl. `approval-log-personal.tmpl`, which lacks the pen-test + attorney slots the track-keyed gates demand — a [[bl088-scaffold-source-closure]]-class hole since the template is chosen by `deployment` while the gates key on `track`); create `docs/eval-results/` in `init.sh`; add a `phase4_release` cross-ref and an appendix-presence check to `check-phase-gate.sh`; wire `validate.sh --competency` as a WARN; fix the Phase-0 Artifact Map. Each gets TDD + a mutation proof; sequence after BL-103/104.

**Related:** BL-102 (Appendix D lands the Go/No-Go + market signal together); BL-103; BL-104; [[bl088-scaffold-source-closure]]; BL-084 (deployment-vs-track orthogonality — the root of the personal-template gap).

**WALK-CONFIRMED 2026-07-12 (E2E validation walk — `Reports/2026-07-12-e2e-walk/RESULTS.md`), and worse than filed.** Proven end-to-end from a zero state: `--start-phase4` consults **only** `poc_mode` and advances **past a FAILing 3→4 gate**; `--finalize-phase 4` is invoked by **no** CI job or hook (`grep` → 0); `check-phase-gate.sh` contains **zero** `phase4_release` cross-references. Demonstrated: from `current_phase=0` with no gate ever passed, `--start-phase4` jumped straight to phase 4 and `git tag` cut a release — **nothing satisfied, nothing consulted.** The 3→4 gate is the framework's strongest (9 references) and **nothing forces it.** The per-step arms it does have are shallow: an **empty file** named `rollback` passes the "MANDATORY rollback test" (CM-H-15); the **single word `monitoring`** passes monitoring-verification (CM-H-17); `go_live_verified` passes on `RELEASE_NOTES.md` **existence alone** — the walk's app shipped with 5 missing security headers, no rate-limiting, and a build that does not boot (BL-117/F19). Also: `--finalize-phase 4` with the **5 step IDs the builders-guide names** FAILs on `handoff_tested` — a 6th step the guide names **nowhere** (D-6), so a guide-following operator is blocked by a step that is not documented.

---

## BL-106: Platform-module go-live checklists are declared MANDATORY and parsed by nothing

**Logged:** 2026-07-11 (eval-prompt hollow-gate audit)
**Category:** Debt / gate credibility
**Severity:** Low
**Status:** Closed — shipped 2026-07-18 (PR #213, merged `ab62028`). Karl chose MACHINE-CHECKABLE: `# BL-106-GOLIVE-CHECKLIST` (process-checklist.sh go_live_verified — every shipped-module Go-Live item must be TICKED in a dated docs/test-results/*go-live-checklist* artifact, zero unticked boxes, fail-closed naming items; standalone platforms exempt with a note) + `# BL-106-GOLIVE-TEMPLATE` (init.sh renders the artifact at scaffold birth). Grammar verified across all four modules incl. desktop's variant header. tests/test-bl106-golive-checklist.sh 8/8 (both lists; in-suite fence-excision mutant) + T-scaffold-golive-template in the real-init suite (9/9; generator mutation proven both directions). Guide Step 4.2 documents the enforcement. Evidence: ledger § POLICY DECISIONS IMPLEMENTED.

**Decision 2026-07-18 (Karl): machine-checkable. IMPLEMENTED on `feat/bl106-golive-gate` (PR pending; Closed at merge):** `# BL-106-GOLIVE-CHECKLIST` in process-checklist.sh + `# BL-106-GOLIVE-TEMPLATE` in init.sh; `tests/test-bl106-golive-checklist.sh` 8/8 (both lists; RED watched 2/6 — six cases showed the hollow gate verbatim; in-suite fence-excision mutant) + real-init case `T-scaffold-golive-template` (init-side mutation proven both directions: generator present → 6-item artifact; excised → absent). Design: the shipped platform module's Go-Live section (H3 header matching `Go-Live`, top-level `- [ ]` items — all four modules parse under this grammar) becomes the single source; init.sh renders it into `docs/test-results/go-live-checklist.md` at scaffold time; the `phase4_release:go_live_verified` arm verifies every module item is ticked in a dated artifact (fail-closed naming missing/unticked items; standalone platforms with no module checklist are exempt with a loud note).

**Status update 2026-07-17 — STOPPED, flagged for Karl:** this entry explicitly demands a deliberate choice ("decide deliberately whether platform checklists become machine-checkable … or the MANDATORY language is downgraded to match reality. Do NOT leave the current mismatch."). That is a product decision, not a mechanical fix — building a checklist parser for 4 platform modules is real feature work; downgrading the language changes the framework's promises. Left Open with both options on the table; see the remediation final report.

`docs/builders-guide.md` Step 4.2 marks the platform-module go-live checklist **"PLATFORM MODULE — MANDATORY"**, and the modules carry substantial checklists (`docs/platform-modules/mobile.md` alone: ~38 MUST/MANDATORY hits; desktop ~19; web ~7; mcp_server ~2). **No script parses `docs/platform-modules/*`** — the checklists are prose only.

**Scope:** decide deliberately whether platform checklists become machine-checkable (a structured block per module the gate can read) or whether the MANDATORY language is downgraded to guidance to match reality. Do NOT leave the current mismatch. Not exhaustively audited — the four modules were grepped, not read end-to-end.

**Related:** BL-105 (Phase-4 gate absence — the enclosing gap); BL-103/104.

---

## BL-107: Rust and `other`-language projects silently get NO TDD gate — including organizational/production tiers where it is advertised as non-bypassable

**Logged:** 2026-07-12 (E2E-walk checklist derivation, PR #188)
**Category:** Bug / gate integrity — documented-but-not-enforced, on a whole-language axis
**Severity:** **High** (the flagship TDD hard block does not exist for two language selections, on tiers where the docs promise it cannot be bypassed)
**Status:** Closed — shipped 2026-07-17 (PR #205, merged 2026-07-18 `24fa571`). `# BL-107-UNIVERSAL-INSTALL` (every language gets the commit-msg hook) + `# BL-107-RUST-INLINE-TESTS` (attribute family incl. rstest/proptest/wasm_bindgen, staged+branch axes, `--no-ext-diff`); currency/freshness read "present" universally, legacy-absent emits an enforcement-tier finding. Evidence: § WP-C1.

**Status update 2026-07-17:** fix implemented on PR #205 (branch `fix/bl107-tdd-all-languages`), awaiting merge. `# BL-107-UNIVERSAL-INSTALL`: init.sh, the sync path, and the Currency hook-state predicate all install/expect the commit-msg gate for EVERY language; `# BL-107-RUST-INLINE-TESTS` in `_tdd_triggers`: staged- and branch-diff content probes count added `#[test]`/`#[cfg(test)]`/runtime-family (`::test]`)/harness-macro attributes as test evidence (`--no-ext-diff` load-bearing against external diff viewers). Freshness now surfaces legacy `absent-intentional` manifests at the enforcement tier (post-BL-107 nothing writes that value — zero false positives). Two-sided mutation matrix proven: full revert → hermetic false-block returns AND real rust/other scaffolds get no hook (test-less commits would land) → restore → green. Adversarial verifier (Fable) verdict SHIP; its three should-fixes (attribute-family regex, --no-ext-diff, freshness legacy silence) all landed in the same commit with their own RED→GREEN. Known guardrail-class residual (verifier note 4, accepted): the probe accepts any matching added line in any staged .rs (comments/strings) as evidence — strictly better than the pre-fix no-gate state, adversary-equivalent to stubbing a test file. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-C1.

**Verified.** `init.sh` (`install_precommit_hook`) derives a per-language `test_pattern`, and installs the BL-072/BL-010 commit-msg hook ONLY when it is non-empty:
```
rust)  src_ext="rs";  test_pattern="" ;;   # Rust tests are inline (#[cfg(test)])
*)     src_ext="";    test_pattern="" ;;   # the catch-all: `other` and any unlisted language
…
if [ -n "$test_pattern" ] && [ -n "$src_ext" ]; then install_tdd_commit_msg_hook; fi
```
So a **Rust** project — or any project whose language falls to the `*)` catch-all (`other`) — receives **no commit-msg hook at all**. No BL-072 TDD ordering gate. No BL-010 Build-Loop commit-message check. This holds even for `deployment=organizational` / `poc_mode=sponsored_poc`, the tiers where BL-072 C2's own docs state the TDD block is a **hard block that cannot be bypassed** (only attested).

For Rust the skip is *deliberate* (inline `#[cfg(test)]` tests cannot be detected by filename), but the consequence is not documented anywhere the operator or their agent will see it, and the framework's TDD promise is stated without a language carve-out. For the `*)` catch-all it is not deliberate at all — it is silent.

**This is [[bl088-scaffold-source-closure]]'s exact failure mode on an axis nobody checked:** the gate exists, the tests pass (every BL-072 test fixture uses a language WITH a test_pattern), and the enforcement simply is not there in the real scaffold.

**Fix shape:** (1) detect Rust tests by CONTENT, not filename — a diff adding `#[test]` / `#[cfg(test)]` counts as a test (the classifier already takes a changed-paths list; extend it to a changed-hunks check for languages with no filename convention); (2) for the `*)` catch-all, either install the hook with a conservative any-test-file heuristic or emit a LOUD init-time warning that TDD enforcement is unavailable for this language and record it in `phase-state.json` so the gate can surface it; (3) never let a non-bypassable tier silently lose its gate — if enforcement is unavailable, say so at init AND at every phase gate; (4) add the language axis to the scaffold-fidelity test (`tests/test-scaffold-tdd-block-real.sh` currently proves the block only for typescript).

**Related:** [[bl088-scaffold-source-closure]] (same class); BL-072 (the gate that is missing); BL-010; `init.sh::install_precommit_hook`; `tests/test-scaffold-tdd-block-real.sh` (the fidelity test that must gain a rust/other case); PR #188 (the checklist derivation that surfaced it).

---

## BL-108: Templates that exist but are never shipped — including one a gate's own error message tells the operator to use

**Logged:** 2026-07-12 (E2E-walk checklist derivation, PR #188)
**Category:** Bug / scaffold completeness — the BL-088 class, in template form
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #210, merged 2026-07-18 `e927faa`). init.sh ships the 5 gate-demanded templates; the durable class fix is the MECHANICAL closure test (shipped-set from init cp lines vs referenced-set from non-comment script text + guide, self-tested extractor, count-floor vacuity guards per the E/F verifier). Evidence: § WP-E2.

**Status update 2026-07-17:** fix implemented on PR #210 (branch `fix/bl108-bl117-ship-closure`), awaiting merge. The five gate-demanded templates now ship (security-audit-findings, security, threat-model-validation, rollback-test, handoff-test-results); the durable class fix is the MECHANICAL closure in `tests/test-bl108-bl117-ship-closure.sh` — the shipped set (init.sh cp lines) and the referenced set (non-comment script text + the guide) are both derived, so drift is impossible; the extractor's bite is self-tested and an init-revert mutation goes RED on exactly the shipped items. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-E2.

`templates/generated/security-audit-findings.tmpl` **exists in the framework** and `scripts/process-checklist.sh` names it in its own operator-facing error message:
> `Create a findings file using templates/generated/security-audit-findings.tmpl`

…but `init.sh` **never ships it** (`grep -c security-audit-findings init.sh` → **0**). The operator is told to use a template that does not exist in their project. The E2E-checklist derivation (PR #188) reports **8 of 25 templates never shipped, 5 of them demanded by a gate** — this is the confirmed exemplar; the full list is in `Reports/2026-07-12-e2e-walk/CODE-VS-MANUAL.md`.

**This is [[bl088-scaffold-source-closure]] in template form.** BL-088 closed the class for *sourced scripts* (`tests/test-scaffold-source-closure.sh` derives init.sh's shipped set mechanically and fails if a shipped script sources an unshipped sibling). Nothing does the equivalent for **templates and artifact paths referenced by gates and error messages**.

**Fix shape:** (1) enumerate the real gap from the PR #188 report — for each unshipped template, decide ship-it or delete-it-and-fix-the-referrer; (2) **extend the closure check to artifacts**: any `templates/**` path or artifact path named by a shipped script (error messages included) must be shipped, or the script must not name it — mechanically derived, like BL-088's parser, so it cannot drift; (3) TDD + mutation proof; registered in both aggregators.

**Related:** [[bl088-scaffold-source-closure]] (the sibling class + the parser to extend); `scripts/process-checklist.sh` (the error message); `Reports/2026-07-12-e2e-walk/CODE-VS-MANUAL.md` (the full list); BL-105 (hollow gates — several share this root cause).

---

## BL-109: The Currency System — session-start freshness, staged review-folder updates, consented apply with archive/rollback (ground-up redesign of project updating)

**Logged:** 2026-07-12
**Category:** Feature / update pipeline (absorbs BL-099 SLICE-B and BL-101 when their layers land)
**Severity:** High (operator-directed; the framework's answer to "how do generated projects stay current")
**Status:** Open

**Decision 2026-07-20 (Karl):** the offer-and-apply escalation (proposing `--sync-framework` from the SessionStart surface on detection) is APPROVED — the option to update must exist — and is deliberately sequenced LAST in the current work queue (after the quick decided items, the Dogfood-4 milestone, and the design-first items). BL-099 and BL-101 are Closed into this ladder as of today; the BL-101 conflict-UX decision (`.rej`-style droppings + a LARGE unmissable warning on every conflict) is a recorded requirement on S4/apply.

**Design of record:** `docs/designs/2026-07-12-currency-system-v1.md` (**v1.1** — normative for the build). v1 was **blocked** by an adversarial design review the same day (4 BLOCK / 9 MAJOR / 10 MINOR — record: `docs/designs/2026-07-12-currency-system-review-r1.md`); every amendment is folded into v1.1 with a traceability changelog (§0). The blocks, in one line each: v1 claimed the write-primitive existed on main (it does not — the promotion is now its own slice S3a); v1 specced a second manifest file (dual-source regression — now one `currency` block inside the existing `.claude/manifest.json`, plus `soloFrameworkPath` so the framework check has a path to check); v1's Class-A merge mechanics would have staged template placeholders into candidates and contradicted its own never-write-user-docs invariant at rollback (now split A1 render-legs-via-BL-101-generator / A2 structural-diff-only, rollback stages-never-writes); v1 had no verbs for upstream deletions/renames (now `add|update|retire|rename` + orphan reporting).

**Shape (four layers):** L0 inventory — the `currency` block (shas, modes, classes, verb state, render bases, three-state hook expectations incl. `absent-unavailable` surfacing BL-107, MCP presence). L1 detection — SessionStart, read-only except an atomic cache, ZERO network at session start, fail-open, silent-when-current, tiered (enforcement drift never silently snoozeable: 7-day expiry + bypass-audit). L2 staging — dated committable run folder (`docs/updates/…`), item verbs, checkbox selection as the single human surface parsed one-way into a machine journal, mechanical facts script-side, mid-tier advisory review (pros/cons/repercussions) confined and injection-pinned. L3 apply — `soif_write` transactional primitive (archive-first, byte-verify, atomic rename, WAL journal, symlink refusal), batch validate-all→commit-all→verify-all with crash recovery, item-consent-only for hooks/gate scripts (new invariant I11), `--rollback` from run archives (staged-never-written for user docs).

**Slices (each through BL-100 adversarial acceptance; guard registry grows every slice):** S0 done (PR #185 — engine + 25-row guard harness). S1 inventory → S2 detection → S3 staging (+ BL-101 generator factoring) → S3a write-primitive promotion (carries the four registry rows from PR #185's final review) → S4 apply/rollback → S5 teaching + machine-block lint contract + E2E items. Live-test protocol (design Appendix P): rung ladder scratch-scaffold → stale-scaffold → throwaway real-project clone → supervised Pantheon (detection → plan → ONE Class T item, then stop); never an unsupervised or batch apply on a real project.

**Related:** BL-099 (SLICE-A shipped PR #185; SLICE-B superseded by L1 here — close it when S2 lands), BL-101 (superseded by L2/A1 — close when S3 lands), BL-105/BL-107/BL-108 (their manifest-level facts land in S1), BL-100 (acceptance doctrine), BL-097/BL-098 (tiering + plan-first: the v1.1 design is the plan of record), BL-092 (constrains L1: lean, zero network, ≤1s local).

**S1 status (2026-07-12): MERGED (PR #191; verifier minor_concerns, approve-leaning — every implementer number reproduced exactly; verifier's own class-assignment mutation RED in both suites).** Carried obligations: (1) birth-stamp test pins Class M only as ">0" — tighten to an independently derived exact count (→ S2); (2) ~10 bulk `.tmpl` skeletons tracked nowhere — needs a §2-L0 class decision before staging (→ S3 dispatch); (3) the four PR #185 registry rows (→ S3a, already recorded); (4) `soloFrameworkPath` re-stamp on sync/apply (→ S3a); (5) `scripts/lib/currency-manifest.sh` ships downstream (→ S2).

---

## BL-110: soloFrameworkCommit is never stamped on `--no-remote-creation` scaffolds — the freshness pin is absent on the hermetic path

**Logged:** 2026-07-12 (ground-truth conflict surfaced by the BL-109 S1 implementation agent — PR #191 declared deviation 1; independently verified in the main session)
**Category:** Bug / pin contract (BL-099 SLICE-A follow-up)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #207, merged 2026-07-18 `12923b3`). `# BL-110-PIN-UNIVERSAL`: soloFrameworkCommit stamped in prepare_initial_state_for_commit — the hermetic path carries the pin too; T-scaffold-pin-stamped pins it on a real init. Evidence: § WP-D2.

**Status update 2026-07-17:** fix implemented on PR #207 (branch `fix/bl110-bl116-noremote-blindspot`), awaiting merge. `# BL-110-PIN-UNIVERSAL`: the stamp moved to the universal manifest-seed site in `prepare_initial_state_for_commit` (idempotent; remote-path duplicate removed with a pointer comment). Fidelity: `T-scaffold-pin-stamped` in the scaffold suite asserts pin == framework HEAD on a REAL `--no-remote-creation` init (8/8). Mutation observed both directions: HEAD-reverted init scaffolds with the pin ABSENT; fixed init stamps it. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-D2.

**Verified evidence:** the BL-099 birth-stamp (`# BL-099: birth-stamp .claude/manifest.json.soloFrameworkCommit`, init.sh ~:2498) lives INSIDE `create_and_protect_remote()` (opens ~:2182) — and that function's `--no-remote-creation` branch (~:2211) exits with `return 0` BEFORE the stamp is reached. Net: **every hermetic scaffold — all UAT/CI/agent runs and any operator passing `--no-remote-creation` — is born with NO `soloFrameworkCommit` pin.** Empirically reproduced during S1 (a real `--no-remote-creation` scaffold's manifest has no such key). The pin is the anchor of the entire Currency System (BL-109) and of `--sync-framework`'s drift reporting; a pin-absent manifest degrades both (sync stamps it on first run — self-healing there — but session-start detection reads it at birth).

**Why tests missed it:** the BL-099 suites drive sync/stamp paths directly; no fidelity test scaffolds via `--no-remote-creation` and asserts the pin — the [[bl088-scaffold-source-closure]] fixture-hides-gap class, on a FLAG axis this time (BL-107 was the same class on the LANGUAGE axis).

**Fix shape:** stamp the pin at the universal manifest-seed site (`prepare_initial_state_for_commit` — exactly where S1 anchored the `currency` block, which already records `soloFrameworkPath` there on every path); keep or dedupe the remote-path stamp (byte-compat decision documented in the PR); fidelity test asserting the pin on BOTH paths (with-remote fixture + `--no-remote-creation`), plus a mutation proof. Interim S2 contract: detection treats a pin-absent manifest as skip-silently for framework-drift checks (never a crash, never false drift).

**Related:** BL-099 (the pin's origin, PR #185); BL-109 (S1 anchored the currency block at the universal site precisely because of this gap — PR #191 deviation 1); [[bl088-scaffold-source-closure]] (defect class); BL-107 (same class, language axis).

---

## BL-111: The Phase 1→2 branch-protection backstop is unsatisfiable on the framework's own blessed hermetic flow — and it poisons every downstream gate snapshot

**Logged:** 2026-07-12 (E2E validation walk, finding F5 — the walk's SOLE hard FAIL; independently reproduced by the adversarial re-walker, 0 overturned)
**Category:** Bug / gate integrity — unsatisfiable gate
**Severity:** **High**
**Status:** Closed — shipped 2026-07-17 (PR #206, merged 2026-07-18 `7fa9753`). The shared-lever fix (BL-123's recording path) + `# BL-126-ATTEST-CONSULT`: verify_init consults the recorded attestation before any host API probe — the hermetic-flow consumer this entry demanded, proven load-bearing by the in-suite fence-excision mutants (the verification pass this entry's open-condition named). Evidence: § WP-D1.

**Evidence (`Reports/2026-07-12-e2e-walk/RESULTS.md`, item P1-013):** for a `github` + `organizational` + `--no-remote-creation` project — the framework's own blessed hermetic on-ramp, used by every UAT/CI/agent run — the Phase 1→2 gate emits `[FAIL] Phase 1→2 backstop: protection verification failed` with `issues++`. Cause chain: `scripts/lib/host.sh` AND `manifest.json` both exist, so `host_load_driver` succeeds and `host_verify_protection main org` runs → `_github_parse_origin` rejects the local bare-repo origin (`not a GitHub URL`) → return 1 → FAIL. **The documented remediation also fails** (`scripts/check-gate.sh --preflight` → same parse error, rc=1). And **there is no product path to record the exemption**: un-truncated `grep -rn 'attestations.branch_protection *=' scripts/` → **0 writers**; only `init.sh` writes `github_free_tier`, and only behind a real host-API 403 that `--no-remote-creation` never reaches; `reconfigure-project.sh` covers `zdr_*` but has no branch-protection field.

**Blast radius:** `create_gate_snapshot` requires `issues=0`, so the clean 1→2 pass **and its snapshot — and, cascading, the 2→3 and 3→4 snapshots — are permanently unreachable** without a live remote or a re-init. The walk carried this gate RED across Stages 2–5. The walker refused to hand-forge the attestation JSON (that is the BL-103 sin) and graded FAIL per rubric R3a.

**Fix shape:** (1) `host_verify_protection` must distinguish *"not a supported host URL"* (→ WARN + attestable) from *"host says unprotected"* (→ FAIL); (2) ship a post-init writer for the branch-protection attestation (extend `reconfigure-project.sh`, mirroring its `zdr_*` handling) so the exemption is recordable, attested-not-silenced; (3) make `check-gate.sh --preflight/--repair` succeed or explain on a non-host origin; (4) fidelity test: scaffold `--no-remote-creation` and prove the 1→2 gate is passable by legitimate means. TDD + mutation proof; registered in both aggregators.

**Related:** BL-084 (deployment/track orthogonality); BL-110 (same `--no-remote-creation` blind spot, pin axis); [[bl088-scaffold-source-closure]] (fixture-hides-gap class — no test ever walked this flow); `Reports/2026-07-12-e2e-walk/RESULTS.md` (P1-013, F5).

---

## BL-112: Commit-time enforcement is hollow — the strict-mode git-hook gate is unreachable dead code, and the pre-commit SAST never blocks

**Logged:** 2026-07-12 (E2E validation walk, findings F8 + F9; both independently reproduced by the re-walker — F9 dynamically)
**Category:** Bug / enforcement — documented gates that do not fire
**Severity:** **High**
**Status:** Closed (2026-07-12, PR #196) — all three defects fixed at the generator, each behind a grep-able marker, each mutation-pinned against a REAL scaffold and a REAL `git commit`.

**F8 — `framework-gate.sh` is dead code.** The generated `.git/hooks/pre-commit` runs an unconditional `exit $FAILED` **before** the block that invokes `.git/hooks/framework-gate.sh` (the BL-030 strict gate that runs `--check-commit-ready`), even when `enforcement_level=strict`. Net: the **phase2-init-verified**, **UAT-in-progress**, and **build-loop-state** blocks have **no git-hook backstop** — they fire only through the AI-session PreToolUse hook. Proven empirically twice in the walk: a real `git commit` succeeded with `phase2_init.verified=false`, and a `chore:` commit succeeded mid-UAT — both correctly refused by `--check-commit-ready` (rc=1) yet committed at the terminal. **Any human, script, or non-AI-session commit walks straight through three "blocking" gates.** (BL-072/BL-006 are unaffected — they have the commit-msg-hook backstop.)

**F9 — the pre-commit SAST arm is decorative.** The hook invokes `semgrep scan --config=p/owasp-top-ten --quiet` **without `--error`**; semgrep exits 0 on findings unless `--error` is passed, so the hook's `[BLOCKED]` branch is unreachable. Demonstrated: an `eval(req.query.code)` Express injection flaw was **detected, printed, and committed clean**; the same finding with `--error` → rc=1. The gitleaks secret-scan arm *does* block — only the SAST arm is hollow.

**F8b — the gate's verdict was discarded too (NEW; surfaced by the fix's own test, not by the walk).** `framework-gate.sh` captured its result as `if ! "$SCRIPTS/process-checklist.sh" --check-commit-ready; then EXIT=$?; … exit $EXIT; fi`. Inside the then-branch of `if ! cmd`, `$?` is the status of the **negation** — which is **0 whenever cmd failed**. So `EXIT` was always 0: even once the gate was made reachable it printed its `[FAIL] Phase 2 initialization not verified.` and then **`exit 0`**, and the commit landed. The gate was hollow *twice over*, and fixing only F8 would have shipped a gate that still never blocked. Both arms (`--check-commit-ready` and `pre-commit-gate.sh --terminal-mode`) had the bug.

**Resolution (PR #196).** Marker-cited, all three in the generators (so `init.sh` **and** the BL-099 `--sync-framework` hook-refresh path both emit the fix):
- `# BL-112-SAST-ERROR` (`scripts/lib/hook-templates.sh`) — added `--error`, bounded by **`--severity=ERROR`**. Rationale: `--error` alone trips on INFO/WARNING findings too, and a gate nobody can pass gets bypassed; ERROR is semgrep's high-confidence tier and is where the walk's `eval(req.query.code)` finding lives. Two sub-fixes came with it: `| xargs -0 semgrep` was replaced with a NUL-delimited array read (xargs **collapses** every non-zero utility exit — BSD→1, GNU→123 — so a finding and a tool failure are indistinguishable), and `--quiet` was dropped because it suppresses semgrep's *own* fatal-error text.
- `# BL-112-SAST-NOTRUN` (`scripts/lib/hook-templates.sh`) — **the declared security decision.** "The scanner did not run" has exactly ONE behaviour, whatever the cause: a semgrep that is **absent** and a semgrep that **fails** (rc ≥ 2 — bad config, unreachable registry, OOM) both **WARN loudly and never block**, via one shared `soif_sast_not_enforced` emitter. Blocking the tool-failure arm was considered and **rejected**: (a) it buys no security — anyone who can break the scanner can more cheaply *remove* it and land on the absent arm, or delete `.git/hooks/pre-commit`, which is not version-controlled; (b) it is worse than neutral — it would make *breaking* the scanner costlier than *uninstalling* it, i.e. pay people to uninstall it; (c) it costs a great deal — `p/owasp-top-ten` is a **registry** ruleset semgrep fetches from semgrep.dev with no local cache, so every offline/proxied/rate-limited developer would be bricked on every commit, and a gate you cannot pass is a gate people `--no-verify` around. What the decision *owes* the operator is honesty, and that is enforced: both arms print an unmissable `SAST NOT ENFORCED for this commit — the scanner did not run. This is NOT a clean result`, the tool-failure arm surfaces semgrep's real stderr, and the rc=0 arm prints an `[OK] semgrep: SAST ran on N staged file(s)` receipt so a *silent* pass can never be mistaken for a *clean* one. The **attested** boundary for an un-run scan is Phase 3 (BL-113), not this hook — this hook is the fast local tripwire.
- `# BL-112-STRICT-GATE` (`scripts/lib/hook-templates.sh`) — the region's terminal exit is now **conditional**, so the strict-gate block appended *below* the managed region is reachable. Any failing arm still short-circuits non-zero; a clean run falls through to the gate. The gate block deliberately stays **outside** the `# >>> SOIF …` markers so BL-099's region refresh cannot clobber it.
- `# BL-112-GATE-EXIT` (`scripts/install-filesystem-gates.sh`) — run the checker, capture **its** status, branch on that. What the gate *checks* is unchanged; only the verdict now propagates.

**Tests.** `tests/test-bl112-commit-enforcement.sh` (**aggregator-only** — it runs the REAL `init.sh` and REAL `git commit`s, the class of test that would have caught all three; registered in `tests/full-project-test-suite.sh`, never in the `tests.yml` unit lane): **13 cases** — planted RCE refused **by git** with HEAD unmoved; a clean file still commits *and the scan is proven to have RUN* (the `[OK]` receipt — without it "a clean file commits" is also true on a host where nothing scanned it, i.e. vacuous); semgrep **absent** → the same planted RCE **lands**, loudly (the documented contract, pinned at last — it had been *claimed* with no test behind it, which is the same class of lie as a `[BLOCKED]` that never blocks); semgrep **failing (rc=2)** → the declared WARN, with the diagnostic on screen; `verified=false` refused by git; mid-UAT refused **on the UAT arm** (the build loop is completed first so it cannot shadow the arm under test); a fully-satisfied commit succeeds *and* writes a `terminal_commit_passed` audit row (proving the gate RAN, not that it is missing); BL-072 no-regression; and **four** mutation proofs — including both not-run arms mutated to *block*, so the WARN contract is pinned in **both** directions rather than half-pinned. Every semgrep-requiring case **SKIPS LOUDLY** when semgrep is absent — a silently-skipped security test is the same class of lie. The whole suite is run **twice** (semgrep on PATH, and semgrep mirrored off PATH): 13 PASS / 0 SKIP, and 10 PASS / 3 LOUD-SKIP / 0 FAIL — **no case passes silently for want of the tool.** `tests/test-bl099-guard-coverage.sh` gained three registry rows (25 → **28 pinned**) and can now mutate `hook-templates.sh` / `install-filesystem-gates.sh` and drive the BL-112 suite as the killing test.

**Known asymmetry, deliberately NOT changed here (follow-up):** `framework-gate.sh` calls `--check-commit-ready` with **no `--subject`**, so `subject_is_feat` defaults true and the Build-Loop arm applies to *every* Phase-2 source terminal commit — while the AI PreToolUse path *does* pass `--subject` and gets the non-feat short-circuit. A pre-commit hook cannot know the subject (`.git/COMMIT_EDITMSG` is stale at that point), so this is not fixable by passing it through; it is pre-existing BL-030 behavior that was simply never observable while the gate was dead. Same for step 2's classifier reading that stale `COMMIT_EDITMSG`. Both need their own entry.

**Related:** BL-030 (the strict gate this makes reachable — and whose verdict-propagation bug this also fixes); [[bl088-scaffold-source-closure]] (fixture-hides-gap class); BL-113 (the Phase-3 half of the same story); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F8, F9).

---

## BL-113: The framework fails its own Phase-3 SAST — and the staleness autorun launders that FAIL into an attestable SKIP

**Logged:** 2026-07-12 (E2E validation walk, findings F14 + F15)
**Category:** Bug / security-gate credibility
**Severity:** **High**
**Status:** Closed — fixed in PR #197 (2026-07-12)

**F14 — a fresh scaffold cannot pass its own security scan.** A freshly-scaffolded organizational project fails `semgrep --config auto` with **6 WARNING findings, ALL in framework-shipped files** — 5 mutable action-tags in the generated `.github/workflows/ci.yml` + `release.yml`, and 1 IFS-tamper in `scripts/check-versions.sh` — and **ZERO in the app's own `src/`**. An honest operator cannot clear Phase 3 without editing framework-generated files, and a scanner **FAIL is not attestable — only a SKIP is**. The framework hands you a project that fails the framework's own gate.

**F15 — and the gate then hides it.** Whenever the tree is dirty (the *normal* state while authoring Phase-3 artifacts), the 3→4 gate's BL-082 staleness check **autoruns the validation driver with `--offline`**, which downgrades semgrep/license/snyk/zap to **SKIP**. The operator sees "scanner unavailable," attests the SKIP in good faith, and passes — never learning that a real scan **FAILs**. The one scanner that most needed a real result is the one the gate quietly stops confronting the operator with.

**Fix shape:** (1) fix the framework-shipped findings at source (pin action SHAs in the generated workflows; fix the `check-versions.sh` IFS pattern) so a fresh scaffold is scan-clean — the acceptance test is *"scaffold → semgrep → zero findings"*; (2) the offline autorun must **not** silently downgrade a scanner that was previously FAILing or that is locally available — either run it online-capable, or surface `[STALE — last real result: FAIL]` rather than a fresh attestable SKIP; (3) make a scanner FAIL **attestable-but-loud** rather than unattestable-and-therefore-laundered. TDD + mutation proofs; scaffold-fidelity test.

### Resolution (PR #197, 2026-07-12)

**F14 — a fresh scaffold is now scan-clean.** Measured on a REAL `init.sh` organizational scaffold with a REAL `semgrep --config auto`: **6 findings BEFORE → 0 findings AFTER.**
- Every GitHub Action in the shipped pipeline templates — and in the framework's own workflows — is pinned to an **immutable 40-hex commit SHA** with a `# vN (vX.Y.Z)` provenance comment. SHAs were resolved through the GitHub API (tag ref → annotated-tag deref → commit) and each was verified to be a real commit; none was invented. The `__SETUP_ACTION__` substitution values in `init.sh` **and** `scripts/reconfigure-project.sh` (sync siblings) are pinned too, so the sed-rendered `release.yml` is pinned as well.
- Two latent bugs fell out of the pin work: `realm/SwiftLint@v0.57.0` was a **phantom ref** (no such tag — the real tag is `0.57.0`, unprefixed), and `dtolnay/rust-toolchain` now passes `toolchain: stable` explicitly because a SHA pin no longer carries the toolchain in the ref name.
- `check-versions.sh::version_gte` no longer sets a function-scoped `IFS`; it uses the command-prefix form (`IFS='.' read -r -a`) — the remediation semgrep's own rule recommends. **No suppression** was used for it.
- The one genuine false positive (`uses: __SETUP_ACTION__` — a build-time placeholder, not an action ref) carries a `# nosemgrep` **with a why-comment in the template only**; it is **stripped at render time** (keyed on a `__SOLO_TEMPLATE_ONLY__` marker) so no suppression ever ships into a generated project. The framework repo itself now scans to **0 findings**.

**F15 — the laundering is dead.** Marker `# BL-113-NO-LAUNDER`, two defences:
1. **Driver carry-forward** (`run-phase3-validation.sh::_p3_no_launder`) — a SKIP never overwrites a prior **REAL FAIL**. The driver reads back the most recent summary carrying a real (non-SKIP) verdict for that scanner; if it was FAIL, the SKIP is **refused** and recorded as FAIL with a `[STALE - last real result: FAIL]` note plus a machine-readable `CARRIED <scanner> <origin>` line. Covers all five scanners.
2. **Gate refusal** (`check-phase-gate.sh`) — an offline-autorun SKIP for a scanner whose **tool is on PATH** is refused outright, attested or not. Scoped to semgrep, deliberately: its real-run path now degrades to an honest attestable SKIP when the rule registry is unreachable, so forcing a real run can never brick an offline operator (snyk's path FAILs instead, so it is not in scope).

**Option (i) — "just run semgrep under the offline autorun" — was tested and REJECTED on evidence.** `semgrep --config auto` is **not** local-only: it hard-fetches its ruleset from `semgrep.dev` with **no local-cache fallback**. With the network blackholed it spends ~97 s retrying, exits rc=2, and writes no report. Running it from the gate would make the gate non-hermetic, slow, and would brick genuinely-offline operators. The autorun therefore **stays `--offline`** — the laundering dies, not the offline mode.

**The framework remains usable genuinely offline.** `_p3_scan_semgrep` now reports a registry-unreachable run as an honest **attestable SKIP** rather than a FAIL (`# BL-113-SEMGREP-OFFLINE`); a FAIL there would have bricked an offline operator, since a FAIL is not attestable. No tool + no prior real FAIL still yields an honest attestable SKIP and a passable gate — asserted by `T-offline-still-usable`.

**Tests:** `tests/test-bl113-sast-honesty.sh` (AGGREGATOR — real `init.sh`; registered in `tests/full-project-test-suite.sh`, never in the `tests.yml` unit list) — 17/17. Both anti-laundering guards are additionally pinned as rows in `tests/test-bl099-guard-coverage.sh` (27/27 PINNED; that harness was generalised to a per-section mutation target + killing suite, leaving every existing row unchanged). Mutation proofs: neutering `# BL-113-NO-LAUNDER` (marker intact) reintroduces the laundering → RED; restore → GREEN. Un-pinning one action in a scratch scaffold → the scan goes RED.

**Note (deferred, not in scope):** F14's remediation message is still a no-op for a scanner FAIL — a FAIL remains **non-attestable by design**, which is the correct security posture now that a fresh scaffold no longer produces one. Option (iii) (make a FAIL "attestable-but-loud") was deliberately **not** taken: an attestable FAIL is a laundering vector by another name.

**Related:** BL-070 (the five real scanners); BL-082 (the staleness binding whose autorun is the laundering vector); BL-112 (commit-time SAST is hollow too — the `[BLOCKED]` branch is still dead, unrelated to this fix); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F14, F15).

---

## BL-114: Phase 0→1 gate integrity — an errexit abort kills the placeholder WARN, the intermediates WARN never blocks, and the 0→1 transition is locally un-gated

**Logged:** 2026-07-12 (E2E validation walk, findings F1 + F2 + F3)
**Category:** Bug / gate correctness
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #208, merged 2026-07-18 `31319fe`). `# BL-114-F2-ERREXIT-GUARD` (placeholder sections no longer abort the gate before its own diagnostic), `# BL-114-F1-INTERMEDIATES` (real blocking arm incl. absent-dir), `# BL-114-START1-GATE-CONSULT` (+ --help truth). Evidence: § WP-E1a.

**Status update 2026-07-17:** fix implemented on PR #208 (branch `fix/bl114-bl115-bl127-gate-integrity`), awaiting merge. F2: `# BL-114-F2-ERREXIT-GUARD` — the placeholder WARN now prints (the empty grep-v pipeline no longer aborts the gate under pipefail). F1: `# BL-114-F1-INTERMEDIATES` — code matches docs: any missing Step-0 intermediate (or the absent directory, previously SILENT) blocks, labeled [FAIL] so verdict and label agree. F3/F-DF2-003: `# BL-114-START1-GATE-CONSULT` (excision-safe fence) — `--start-phase1` consults `--gate phase_0_to_1` before any state change and refuses on a failing gate; documented in `--help`. All RED-observed pre-fix; HEAD-revert reproduces the 9-failure RED. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-E1a.

Three defects in the same gate, all walk-reproduced:

1. **F2 — dead WARN branch (errexit abort).** A placeholder-only manifesto section trips `set -euo pipefail` inside `validate_manifesto_content` and **aborts `check-phase-gate.sh` before the placeholder WARN prints** — rc=1 with *zero diagnostic and no summary*. The operator sees a bare failure with no reason; the WARN branch is effectively unreachable code.
2. **F1 — non-blocking "blocking" WARN.** The phase-0-intermediates check never increments `issues`: deleting `docs/phase-0/frd.md` yields `2/3 saved` but **rc=0 `Phase gates consistent`** — contradicting the documented WARNS-and-blocks behavior. An **absent `docs/phase-0/` directory produces no warning at all**.
3. **F3 — the 0→1 transition is un-gated locally.** A bare `check-phase-gate.sh` at `current_phase=0` validates **no** 0→1 evidence (manifesto/phase-0/approval checks are all `current_phase>=1`-guarded), and `start_phase1()` advances **with no gate consult**. Only the prospective `--gate phase_0_to_1` form checks anything.

**Fix shape:** guard the manifesto content scan against errexit (subshell + explicit status) so the WARN prints and the gate summarizes; decide deliberately whether the intermediates check blocks (per the CLAUDE.md `issues++` = BLOCK rule) and make code match docs; make `start_phase1` consult the gate. Each with a mutation proof — note the `[WARN]`-vs-`issues++` trap.

**Addendum (2026-07-13, Dogfood 2 finding F-DF2-003):** reproduced live on a real project — `process-checklist.sh --start-phase1` advances `current_phase` 0→1 with **no gate consult** (`[INFO] Advanced .current_phase: 0 → 1`, exit 0, while `gates.phase_0_to_1` is still null), and the command is **undocumented in `--help`** (`process-checklist.sh --help | grep -c start-phase1` → 0). An operator following the generated CLAUDE.md (which says to hand-edit `phase-state.json`) never discovers it, and the gate fires only if they *separately* run `check-phase-gate.sh`. Fold the "make `start_phase1` consult the gate" fix here, and add `--start-phase1` to the `--help` output.

**Related:** BL-104 (the same `issues++`-is-the-real-verdict class); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F1, F2, F3); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-003).

---

## BL-115: Approval evidence is satisfiable without approval — any date in the window counts, and the attorney gate is satisfied by its own template header

**Logged:** 2026-07-12 (E2E validation walk, findings F6 + F16)
**Category:** Bug / approval-evidence integrity
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #208, merged 2026-07-18 `31319fe`; attorney window section-bounded in the `3fee6d3` follow-up, merged via PR #210 `e927faa`). `# BL-115-DATE-CELL` (Date-ROW, section-bounded), `# BL-115-ATTORNEY-ENTRY` (H2-anchored, section-bounded), `# BL-115-PII-REQUIRED` (fail-closed when PII + no policy). Residuals recorded: approver-ROLE verification (CM-H-08); any-row date within the bounded attorney section. Evidence: § WP-E1a + § WP-E1b verdict block.

**Status update 2026-07-17:** fix implemented on PR #208, awaiting merge. F6: `# BL-115-DATE-CELL` in `_cpg_gate_has_evidence` — the date must sit in the approval's Date ROW (both `| Date |` and `| **Date** |` shapes); a blank cell is no longer masked by a stray date in the window. F16: `# BL-115-ATTORNEY-ENTRY` — a real entry is a DATED table row under the section (the template's own header no longer satisfies); `# BL-115-PII-REQUIRED` — non-public `data_classification` with no privacy policy FAILS the step (required-when-PII, never skipped-when-absent). Role verification (CM-H-08) not addressed here — recorded as residual. Evidence: § WP-E1a.

**Status update 2026-07-17 (E1b verifier follow-up, rides in PR #210):** the WP-E1b adversarial verifier found `# BL-115-ATTORNEY-ENTRY`'s window was NOT section-bounded — the personal template's `[Attorney / firm name]` placeholder row is a second grep anchor whose 15-line window reached the Penetration Test section's Date row, so a filled pen-test date satisfied the attorney gate with a placeholder attorney Date. Fixed by section-bounding with the `_cpg_gate_has_evidence` awk idiom (H2-header anchor, stop at next `## `, +15 cap); `T-attorney-bleed-blocked` in `tests/test-bl114-bl115-bl127-gate-integrity.sh` pins it (RED watched, exit-clause mutation kills). Evidence: § WP-E1b verdict block.

**F6 — proximity-window date matching.** `_cpg_gate_has_evidence` greps for **any ISO date in the 15-line window** after a gate header, not the approval's **Date cell** — so a blank or missing approval date is masked by an incidental date in a Reference or Notes cell. Demonstrated at the 1→2 approval (P1-010). Extends the same proximity-window class found at P0-014. Also (CM-H-08): the approver's **role is never verified** — any name is accepted; the retroactive-STA-by-role check only fires for `upgraded_from:personal` projects (count = 0 here).

**F16 — the attorney gate satisfies itself.** The Phase-3 attorney-review check greps `-qi 'attorney|legal review'` against `APPROVAL_LOG.md` — and the **organizational APPROVAL_LOG template ships with a literal `## Attorney / Legal Review` header**, so the gate passes with **zero real attorney entry**. Separately, deleting `PRIVACY_POLICY.md` **bypasses the legal_review step entirely** (the check is file-conditional): collect PII, write no policy, pass.

**Fix shape:** parse the approval **row** (Date cell specifically, non-empty, plausible) rather than a proximity window; require a signer distinct from the template's own scaffolding text (the header alone must not satisfy); make the legal review **required-when-PII** rather than skipped-when-absent (BL-102's evidence-standard doctrine applies: fail closed). Mutation proofs on each.

**Related:** BL-105 (hollow-gate family); BL-102 (fail-closed evidence doctrine); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F6, F16, CM-H-08).

---

## BL-116: The "MANDATORY, non-bypassable" push gate is scoped to `host=other` only — first-class hosts scaffolded `--no-remote-creation` never get it

**Logged:** 2026-07-12 (E2E validation walk, finding F7)
**Category:** Bug / gate scope
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #207, merged 2026-07-18 `12923b3`). `# BL-116-PUSH-GATE-SCOPE`: the push-gate exemption requires recorded remote_repo_created + pushed_initial; the two pass-path fixture suites that predated the arm were modernized in `a52506a` (post-run CI repair). Evidence: § WP-D2 + § POST-RUN CI REPAIR.

**Status update 2026-07-17:** fix implemented on PR #207 alongside BL-110, awaiting merge. `# BL-116-PUSH-GATE-SCOPE` (excision-safe fence) in check-phase-gate.sh: the first-class exemption is EARNED — skipped only when `remote_repo_created`+`pushed_initial` are on record (the on-disk meaning of "provably pushed at init"); host=other keeps unconditional gating. `tests/test-bl116-push-gate-scope.sh` 4/4 incl. the fence-excision mutant; the github no-remote RED was observed (0 push-gate lines pre-fix). Evidence: § WP-D2.

The BL-084 push-verification gate — documented as **MANDATORY and non-bypassable** — is implemented only for `host == "other"`. A `github` / `gitlab` / `bitbucket` project scaffolded with `--no-remote-creation` **never receives the mandatory push verification**: `grep -c 'push gate'` in the gate's output is **0**, both with and without a pushed remote. The scope comment's stated premise — *"first-class hosts are provably pushed at init"* — is **false for `--no-remote-creation`**, which is precisely the flow every hermetic/UAT/CI run and many operators use.

**Fix shape:** key the push gate on *"is there a verified remote with the work pushed"*, not on host brand; or, if first-class hosts are genuinely exempt when a remote was created, make the exemption **conditional on remote creation having happened** (the manifest records it) and prove the `--no-remote-creation` case still gates. Mutation proof required — a "MANDATORY" gate that silently doesn't exist for the common path is the cardinal defect class.

**Related:** BL-084; BL-110 + BL-111 (the same `--no-remote-creation` blind spot on the pin and protection axes — three findings, one uncovered flow); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F7, P1-012).

---

## BL-117: BL-088 class recurrences — the production build ships without its own migration asset, and `check-maintenance.sh` is never scaffolded

**Logged:** 2026-07-12 (E2E validation walk, findings F19 + F20)
**Category:** Bug / scaffold closure (the [[bl088-scaffold-source-closure]] class)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #210, merged 2026-07-18 `e927faa`). The 4 guide-named tools ship (mechanical closure enforced) and `# BL-117-BUILD-SMOKE` demands a dated started-and-responded record for production_build (glob-loop resolver — the two-glob `ls ||` fallback was empirically shown to wipe found matches under pipefail). Evidence: § WP-E2.

**Status update 2026-07-17:** fix implemented on PR #210 alongside BL-108, awaiting merge. F20: `check-maintenance.sh` + the three guide-named lints now ship (activating pre-commit-gate's documented project-local lint path); the guide-tools closure keeps the class shut. F19: `# BL-117-BUILD-SMOKE` — production_build requires a dated smoke record that the BUILT artifact was STARTED and responded (deviation from "actually start it" recorded: a bash checklist cannot own every stack's runtime contract; the recorded evidence of a real start is the enforceable unit, consistent with the rollback/monitoring bars). Fence-excision mutation in-suite. Evidence: § WP-E2.

**F19 — the release does not boot.** The walked project's production build **does not run**: `tsc` omits `migrations/001_init.sql` from `dist/`, so the documented `npm start` (`node dist/src/server.js`) crashes `ENOENT`. The framework's `phase4_release:production_build` step has **no artifact or smoke arm** and was marked complete on a non-booting build. A "released" project that cannot start is the sharpest possible statement of the missing Phase-4 evidence arms.

**F20 — a guide-referenced tool that is never shipped.** `scripts/check-maintenance.sh` is framework-only: `init.sh` ships it **0 times**, so the builders-guide's Step 4.4 maintenance tool returns *"No such file"* in-project — and nothing schedules it either.

**The class, stated plainly (the walk's own honorable mention):** *a shipped instruction that points at an unshipped dependency* recurred **at least six times** in one walk — the TDD gate silently no-ops without `tdd-classify.sh` (BL-088, reproduced on demand), `security-audit-findings.tmpl` (BL-108), `rollback-test.tmpl` + `handoff-test-results.tmpl` (gate-referenced, never shipped), `check-maintenance.sh` (F20), and the app's own migration asset (F19). This is not a set of one-off bugs; it is a **structural gap between what `init.sh` ships and what the gates and guides demand.**

**Fix shape:** ship the missing artifacts; add a **smoke arm** to `production_build` (the built artifact must start); and — the durable fix — **extend the BL-088 closure check from sourced scripts to every path any shipped script or guide names** (templates, tools, artifacts), mechanically derived so it cannot drift. That single check would have caught five of the six.

**Related:** [[bl088-scaffold-source-closure]] (the parser to extend); BL-108 (templates half); BL-105 (the missing Phase-4 evidence arms); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F19, F20, and the class inventory).

---

## BL-118: The pre-commit SAST gate (and CI SAST) is BLIND to browser DOM XSS — BL-112 made it reachable but it is aimed at a ruleset that cannot see `innerHTML`

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-007)
**Category:** Bug / security enforcement — the worst class (a security gate that reports "clean" on a real vulnerability)
**Severity:** **Critical**
**Status:** Closed — shipped 2026-07-17 (PR #199, landed on main via the PR #202 stack-landing merge `88bddd3`). DOM-sink ruleset added to the hook emitter, all 20 CI templates (3 gitlab ones gained their missing sast job), and verify-install's repair path (which had been re-inlining the pre-BL-112 blind hook); semgrep added to the CI full lane. Mutation-proven (source-level break→RED→restore→GREEN + the in-test strip-the-config mutation); adversarial verifier verdict SHIP. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-A1. Verifier follow-ups filed as BL-131 (residual sinks no registry rule covers) and BL-132 (worktree-vs-index scan gap) — both still Open.

The generated pre-commit hook's Semgrep arm (marker `# BL-112-SAST-ERROR` in `init.sh`, which scaffolds `.git/hooks/pre-commit`) runs `semgrep scan --config=p/owasp-top-ten --no-git-ignore --severity=ERROR --error`. That ruleset **contains no browser DOM-sink rules.** A real stored DOM XSS (`pane.innerHTML = <attacker-influenced markup>`) was staged and committed on the flagship `web`/`typescript` platform; the hook reported **`[OK] semgrep: SAST ran on N staged file(s) — no ERROR-severity findings`** and the vulnerable code reached `main`.

**Reproduce (positive control — proves it is the ruleset, not a broken scanner):** a file containing `eval(userInput)`, `el.innerHTML = userInput`, and `document.write(userInput)`:
```
semgrep scan --config=p/owasp-top-ten --severity=ERROR --error <file>   # → 0 findings
semgrep scan --config=p/security-audit --error <file>                    # → 0 findings  (this pack is ALSO in CI)
semgrep scan --config=p/xss --error <file>                               # → 0 findings
semgrep scan --config=r/javascript.browser.security.insecure-document-method <file>  # → 2 findings, flags by line
semgrep scan --config auto <file>                                        # → detects it (this is what run-phase3-validation uses)
```
CI shares the blindness: `.github/workflows/ci.yml` uses `config: p/owasp-top-ten, p/security-audit`. So a DOM XSS passes the commit gate AND CI, and is caught only by the Phase-3 full-tree `--config auto` scan — if the operator gets that far and semgrep can reach its registry (BL-113 offline hole). BL-112 correctly fixed the *plumbing* (`--error` is now passed, the `[BLOCKED]` arm is reachable, the verdict propagates); this is the successor defect — **reachable but aimed at the wrong rulebook.** The framework repo cannot self-detect it: `check_commit_message` short-circuits at `current_phase < 2` and the framework repo has no `phase-state.json`, so this path is never dogfooded.

**Fix shape:** add `--config=r/javascript.browser.security.insecure-document-method` (browser DOM sinks) to BOTH the pre-commit hook (`# BL-112-SAST-ERROR` marker) and `ci.yml`; consider `--config auto` where the network allows, with the BL-113 offline-attestation discipline. **Add a mutation test to the framework suite** that stages a real `el.innerHTML = userInput` against the generated hook and asserts a non-zero exit — the test whose absence let this ship. Web is the flagship platform; its advertised commit-time SAST tripwire must see the #1 web vulnerability class.

**Related:** BL-112 (armed the gate; this is what the gate is pointed at); BL-113 (the offline-SKIP hole in the same scanner family); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-007, with the live commit transcript).

---

## BL-119: The strict terminal commit gate classifies every commit by the PREVIOUS commit's message — a correctly-blocked commit then bricks the repository

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-006)
**Category:** Bug / gate correctness + availability
**Severity:** **High**
**Status:** Closed — shipped 2026-07-17 (PR #200, landed on main via the PR #202 stack-landing merge `88bddd3`). Plain `--terminal-mode` runs no message consumer (`# BL-119-NO-MSG-AT-PRECOMMIT`); message-scoped gates live at the commit-msg surface where the message is current. Mutation-proven (HEAD-revert→3-case RED→restore→GREEN); adversarial verifier verdict SHIP, incl. an empirical audit that the removed arm never had correct-message enforcement for any population. BL-087 item 1 and BL-133 fixed in the same PR. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-A3.

`.git/hooks/pre-commit` → `.git/hooks/framework-gate.sh` (strict mode) calls `process-checklist.sh --check-commit-ready` and `pre-commit-gate.sh --terminal-mode`. In `--terminal-mode`, `pre-commit-gate.sh` reads the subject from `.git/COMMIT_EDITMSG` (see the `TERMINAL_MODE` block). **At `pre-commit` time git has not yet written the new message — `COMMIT_EDITMSG` still holds a PREVIOUS commit's subject.** The file's own comments admit `commit-msg` is the only hook point where it is current; `framework-gate.sh` calls the classifier from `pre-commit` anyway.

**Two failure directions:**
- **FALSE BLOCK (real, halted the walk):** after any `feat:` commit whose Build Loop is closed, the stale `feat(...)` subject makes the gate demand an active Build Loop for **every subsequent commit — including `docs:`, `chore:`, `test:`, even pure-Markdown** — which are exempt. The project becomes uncommittable. The gate's own printed remedy (`reconfigure-project.sh --enforcement-level light`) is **refused** for organizational/sponsored-POC tiers (`forces strict`). The only listed escapes (`--no-verify`, a forged Build Loop) are forbidden.
- **FALSE PASS (checked — CLOSED by the commit-msg hook):** the stale message could let a `feat:` skip BL-006 at pre-commit, but the `commit-msg` hook re-runs the check with the now-current message and catches it. So this is an **availability** defect, not a security bypass.

**Reproduce:** land a `feat:` commit through a full Build Loop, then `git commit -m "docs: anything"` → `[FAIL] pre-commit gate: 'feat(...)' commit blocked — no Build Loop active`. Confirm the classifier is correct in isolation: `process-checklist.sh --check-commit-message "docs: x"` → allowed.

**Newly exposed by BL-112** (which made this gate reachable — it "sat below an unconditional exit"). Reachable-but-wrong is the successor defect.

**Fix shape:** `framework-gate.sh` must not run the commit-message classifier at `pre-commit` — either drop the message check from the pre-commit path (the `commit-msg` hook already does it with the correct message), or pass the real prospective subject. Regression test: a `docs:`-only commit immediately after a `feat:` commit must succeed on a strict organizational scaffold.

**Related:** BL-112 (made this reachable); BL-087 (BL-006 commit-msg surface asymmetry); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-006).

---

## BL-120: The Build-Loop `security_audit` step is existence-only — an audit that says "SEV-1, DO NOT SHIP" satisfies the gate exactly as well as a clean one

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-008)
**Category:** Bug / hollow gate
**Severity:** **High**
**Status:** Closed — shipped 2026-07-18 (PR #223, merged `fdda7a2`). `# BL-120-AUDIT-VERDICT`: the step parses the SHIPPED template's own Summary grammar fail-closed — per file (comments + code fences stripped) the LAST resolved-line and LAST numeric Open-row govern; Open>0 blocks, unqualified Yes required, no parseable verdict blocks; ALL files at the newest mtime must pass. Adversarial verifier (Fable) SHIP-WITH-FIXES — its MUST (Yes-ANYWHERE acceptance) + 4 SHOULDs landed RED-watched pre-push. `tests/test-bl120-audit-verdict.sh` 17/17 ×3 (both lists; fence-excision mutant). Evidence: ledger § WP-A2 part 1 + VERIFICATION.

`process-checklist.sh --complete-step build_loop:security_audit` verifies only that a file whose name contains the feature slug exists under `docs/security-audits/` (the `ls docs/security-audits/*"${feature_slug}"*` check). It never reads the file's verdict. During the walk, an audit file whose own heading read *"ROUND 1 — the naive implementation: CRITICAL — VULNERABLE. DO NOT SHIP."* satisfied the step, and the feature (a live stored XSS) committed. A security audit that concludes "do not ship" advances the gate identically to one that passes.

**Reproduce:** with a Build Loop active, place any file `docs/security-audits/<feature-slug>-anything.md` (contents irrelevant) → `--complete-step build_loop:security_audit` → `[OK]`.

**Fix shape:** the audit artifact needs a machine-readable verdict the step parses (e.g. a required `**Verdict:** PASS|FAIL` / `**Open findings:** N` front-matter line), and the step must FAIL on `FAIL` / non-zero open critical-high. Pair with BL-125 (no test execution at commit time) and BL-118 (SAST blind) — three independent controls all failed to stop the same real XSS; each should catch it.

**Status update 2026-07-18:** fix implemented on branch `fix/bl120-audit-verdict` (PR open; Closed with PR + merge SHA at merge). Grammar decision: the step parses the SHIPPED template's OWN Summary (`**All findings resolved:** Yes` + the `| Open | N |` row) instead of a new `**Verdict:**` line — zero new artifact surface; the template comment already promised exactly this enforcement. `# BL-120-AUDIT-VERDICT` fail-closed ladder: per audit FILE (comments + fenced code blocks stripped — a quoted verdict is an example), the LAST resolved-line and LAST numeric Open-row govern; Open>0 blocks (negative dominates), unqualified Yes required (placeholder `Yes / No` and explicit No block), no parseable verdict blocks; ALL files at the newest mtime must pass (fail-closed tie-break). Adversarial verifier (Fable) SHIP-WITH-FIXES: its MUST (Yes-ANYWHERE acceptance — an earlier round's Yes overrode the current round's No in the walk's own single-file-rounds shape) + 4 SHOULDs (serialization-equivalent Open rows, mtime-tie fail-open, directory-candidate hygiene incl. a new bare-directory fail-open guard, doc parity) all landed pre-push, each RED-watched. `tests/test-bl120-audit-verdict.sh` 17/17 ×3 consecutive (both lists; T1 = the walk's DO-NOT-SHIP repro RED-watched; T7 fence-excision mutant with vacuity guards). Evidence: ledger § WP-A2 part 1 + its VERIFICATION section.

**Related:** BL-118 + BL-125 (the other two controls that missed the same XSS); BL-105 (the hollow-declared-MUST family); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-008).

---

## BL-121: The MVP-Cutline reconciliation counter uses GNU-sed alternation — on BSD/macOS it counts to EOF and HARD-BLOCKS the production Phase 3→4 gate

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-011)
**Category:** Bug / portability — the exact class CLAUDE.md and `lint-counter-antipattern.sh` exist to prevent
**Severity:** **High** (escalated from a Phase-2→3 WARN: at the production gate the identical bug is a hard BLOCK on the framework's own dev OS)
**Status:** Closed — shipped 2026-07-17 (PR #201, landed on main via the PR #202 stack-landing merge `88bddd3`). See the dated status update below for the proof chain.

In `test-gate.sh`, the feature-completeness check counts MVP-Cutline items with:
```
cutline_items=$(sed -n '/Must-Have/,/Should-Have\|Will-Not-Have\|---/p' PRODUCT_MANIFESTO.md | grep -cE '^\s*-\s*\*\*')
```
**Status update 2026-07-17:** fix implemented on PR #201 (branch `fix/bl121-cutline-bsd-sed`, stacked on PR #200; merged same day, landed on main via PR #202 `88bddd3`); mutation-proven both directions (awk-revert → count 8 RED; lint-rule-revert → T11 RED). Adversarial verifier (Opus-tier) verdict **SHIP** — BSD/GNU parity proven on 6 fixture shapes incl. CRLF, and the end-to-end exit-2→exit-0 gate flip demonstrated; its NOTE-1 (unanchored opener re-opens on Section-5 bullets mentioning "Must-Have" — a quirk the GNU original shared) fixed in the same PR with the heading-anchored opener. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-B1.

`\|` is **GNU-sed alternation**; **BSD/macOS sed treats it as a literal**, so the terminator never matches and the range **runs to EOF**, counting every `- **bold**` bullet in the whole manifesto. On a real project this reported **68 cutline items vs the true 3**. Because `test-gate.sh --check-phase-gate` exits 2 on that WARN, and `check-phase-gate.sh` does `issues=$((issues+1))` on a bug-gate exit-2 (the `[WARN] Bug gate has warnings` arm), the **production Phase 3→4 gate hard-blocks** with every real check green. `5 ≥ 68` is unsatisfiable by any honest means; the only "escape" is `SOIF_PHASE_GATES=warn`, a global gate-disable.

**Reproduce (on macOS):**
```
bash scripts/test-gate.sh --check-phase-gate        # → [WARN] Feature count (N) < MVP Cutline items (68); exit 2
printf 'A\nSTOP-B\nC\n' | sed -n '/A/,/STOP\|NOPE/p'  # → prints all 3 lines (range never closes = BSD literal \|)
sed -n '/Must-Have/,/Should-Have/p' PRODUCT_MANIFESTO.md | grep -cE '^\s*-\s*\*\*'  # GNU-intended → correct count
```

**Fix shape:** replace `\|` with a portable terminator — either a POSIX bracket/ERE via `sed -E` with a real alternation that BSD honors, or (cleaner) an `awk` range with a proper `/Should-Have|Will-Not-Have|^---/` regex, or bound the count to the section between the `## 5. MVP Cutline` heading and its `**CUTLINE**` marker. Add a fixture-based test asserting a known 3-item manifesto counts 3 on both sed flavors. This is precisely the GNU-first portability class CLAUDE.md warns about and `lint-counter-antipattern.sh` polices — extend the lint to catch `sed` alternation too.

**Related:** BL-105 (the reconciliation MUST it implements); `lint-counter-antipattern.sh` (extend); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-011).

---

## BL-122: The Phase-3 `zap-dast` gate counts ALL alerts unfiltered — ZAP rule 10049 fires under every Cache-Control value, so the DAST gate is unpassable for any web app

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-012)
**Category:** Bug / gate correctness (false-positive that blocks release)
**Severity:** **High**
**Status:** Closed — shipped 2026-07-17 (PR #203, merged 2026-07-18 `01d4614`). `# BL-122-ZAP-RISK-FILTER`: verdict counts riskcode ≥ 2 only (jq), rc 1/2 excluded from the verdict, unparseable → FAIL; ZAP_INFO_LOW / ZAP_MIXED / ZAP_MALFORMED fixtures pin all three directions. Evidence: § WP-B2.

**Status update 2026-07-17:** fix implemented on PR #203 (branch `fix/bl122-zap-risk-filter`, off the healed main), awaiting merge. `# BL-122-ZAP-RISK-FILTER`: Medium+ (riskcode≥2) alerts block; informational/low stay visible in the archive; unparseable report → FAIL naming the reason; baseline rc 1/2 dropped from the verdict (zap-baseline defaults ALL alerts to WARN → rc=1 was the permanent-FAIL mechanism itself). Mutation-proven (filter-revert → both count cases RED). Adversarial verifier (Opus) verdict SHIP — fails safe under hostile riskcode values, multi-site/`@`-key/instances shapes, and mixed reports; BL-113's a-FAIL-cannot-be-attested guarantee re-proven end-to-end (17/17). Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-B2.

`run-phase3-validation.sh` (marker `# BL-070-ZAP-DISPATCH`) computes ZAP findings as `findings=$(jq '[.site[]?.alerts[]?] | length' "$archive")` — **every alert at every risk level, unfiltered.** A real, clean baseline scan against the built artifact (`FAIL-NEW=0, PASS=66`) still produces at least one **Informational (`riskcode=0`)** alert: rule **10049**, which fires as *"Storable but Non-Cacheable"* / *"Non-Storable Content"* / *"Storable and Cacheable Content"* under (respectively) **no `Cache-Control`, `no-store`, and `public,max-age`** — i.e. under every possible value. So `findings ≥ 1` always → `[FAIL] zap-dast` → Phase 3→4 blocked, for any web project. BL-113 (correctly) makes a FAIL un-attestable, so there is no legitimate escape.

**Reproduce:** run the driver against any live static site with a valid CSP and headers → `[FAIL] zap-dast — 1 ZAP alert(s)`; inspect the archived JSON → the sole alert is `riskcode: 0`, `pluginid: 10049`.

**Fix shape:** filter by risk — `jq '[.site[]?.alerts[]? | select((.riskcode|tonumber) >= 2)] | length'` (Medium+), or at minimum exclude `riskcode == 0`, matching the semgrep arm's `--severity ERROR` philosophy (block real issues, don't drown in informational noise). Document that informational alerts still surface in the archived report.

**Related:** BL-070 (the driver); BL-113 (why a FAIL can't be attested past — correct, which is why the false FAIL must be fixed at source); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-012).

---

## BL-123: The real-remote free-tier branch-protection recovery is circular — a non-interactive first run that meets the 403 without the flag pre-set cannot recover

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-002; the real-remote counterpart to BL-111's hermetic defect)
**Category:** Bug / unsatisfiable recovery path
**Severity:** **High**
**Status:** Closed — shipped 2026-07-17 (PR #206, merged 2026-07-18 `7fa9753`). `# BL-123-BP-ATTEST-RECORD` in check-gate.sh --repair: host-keyed, precondition-guarded (remote_repo_created + pushed_initial), idempotent on .at, provenance-stamped; honored by all three consumers. 11-case suite. Evidence: § WP-D1.

**Status update 2026-07-17:** fix implemented on PR #206 (branch `fix/bl123-bp-attestation-recovery`), awaiting merge; closes BL-111 (same lever) and BL-126 in one PR. `# BL-123-BP-ATTEST-RECORD` in check-gate.sh cmd_repair: `--branch-protection-attested` / `SOLO_BP_ATTESTED=1` records init.sh's exact attestation shape post-hoc — host-keyed reason, explicit-only, idempotent on presence (reasonless 'other'-host shape included), REFUSED unless remote_repo_created+pushed_initial are on record (verifier finding A: without the guard, 3 of 4 consumers would honor a no-remote attestation), with `recorded_via: "check-gate-repair"` provenance (finding B). `# BL-126-ATTEST-CONSULT` in process-checklist.sh verify_init: consults the recorded reason before any host API probe (excision-safe fence). 11/11 tests incl. two fence-excision mutants; adversarial verifier (Opus) SHIP with all three findings landed pre-push. Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-D1.

On a real free-tier GitHub **private** repo in **organizational** mode, `init.sh` creates the repo, pushes, then hits a genuine `HTTP 403 "Upgrade to GitHub Pro…"` on `host_configure_protection`. The `github_free_tier` attestation is writable **only inside `init.sh`'s in-flight fallback** (guarded by `BRANCH_PROTECTION_ATTESTED`). A **non-interactive first run** — the AI-orchestrator norm — cannot know to pre-set `--branch-protection-attested` (plan tier is not API-readable in advance; `gh api user` → `plan:null`), so it hard-fails at the 403. The two recovery paths then refer to each other in a closed circle: `check-gate.sh --repair` re-hits the 403 and prints *"Re-run with `--branch-protection-attested`"* — a flag `check-gate.sh` **does not accept** — and re-running `init.sh` dies at `host_create_repo` with `GraphQL: Name already exists`. Only escape: delete-and-recreate (works solely while the repo is empty). When the flag IS pre-set on the first run, the path works (verified) — so the defect is specifically the unattested-first-contact recovery.

**Reproduce:** `init.sh --non-interactive … --deployment organizational --gov-mode sponsored_poc --visibility private` on a free-tier account **without** `--branch-protection-attested` → `[FAIL] Attestation required` exit 2; then `check-gate.sh --repair` → `[FAIL] Protection config failed`, recommends the flag it doesn't accept.

**Fix shape:** give `check-gate.sh` an attestation-recording path (accept `--branch-protection-attested` / honor `SOLO_BP_ATTESTED=1`) so the documented `--repair` remediation can actually record the `github_free_tier` attestation post-hoc; OR have `init.sh` detect the 403 and offer to record the attestation non-interactively with a loud notice. One fix (an attestation-recording subcommand) closes both this and BL-111.

**Related:** BL-111 (hermetic-path sibling; shared root cause — attestation writable only inside init's fallback); BL-002/BL-016 (the attestation machinery); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-002).

---

## BL-124: Promotion RE-OPENS the light-track skips (`SKIPPED → PENDING`) and then no gate ever reads `PENDING` — the ratchet performs the re-demand and forgets to enforce it

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-014; answers the walk's central question)
**Category:** Bug / governance ratchet hole
**Severity:** **High**
**Status:** Closed — shipped 2026-07-17 (PR #204, merged 2026-07-18 `a5f2a09`). `# BL-124-PENDING-RATCHET`: the 3→4 gate FAILS while PRODUCT_MANIFESTO.md carries the track-upgrade PENDING marker; writer/reader literals wire-pinned; bl104-style copy-mutant proves the arm. Evidence: § WP-B3.

**Status update 2026-07-17:** fix implemented on PR #204 (branch `fix/bl124-bl102-promotion-ratchet`), awaiting merge. `# BL-124-PENDING-RATCHET` in check-phase-gate.sh: the Phase 3→4 gate FAILs (issues++) while the manifesto carries the writer's literal `PENDING — required by track upgrade` — marker-keyed, not track-keyed (BL-084 spoofability; Light projects carry SKIPPED, never PENDING). Writer and reader wire-pinned to one constant by `tests/test-bl124-pending-ratchet.sh`; bl104-style copy-mutant proves the arm load-bearing. Adversarial verifier (Opus) verdict SHIP: evasion surfaces closed (missing manifesto already blocks at phase≥1; scope-down neutralized by marker persistence; em-dash byte-identical both sides; no false-positive contexts in tree). Evidence: `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-B3.

`upgrade-project.sh` (the "Refreshing PRODUCT_MANIFESTO.md Appendix A/C markers for track upgrade" step) rewrites the Light-track `**SKIPPED**` markers on Appendix A (Revenue Model) and Appendix C (Trademark & Legal) to `**PENDING — required by track upgrade light → full**`. **Nothing then reads that `PENDING` marker.** Combined with BL-102 (Market Signal Step 1.1.5 has no check), the three Phase-0/1 obligations the Light track legitimately let a project skip are — at Full track — *required by the written process, marked PENDING by the upgrade tool, and enforced by zero gates.* A project reaches a tagged production release with all three still literally saying "PENDING." This is worse than a silent gap: the framework visibly performs the re-demand, which reads to an auditor as a working ratchet.

**Reproduce:**
```
grep -rl "PENDING" scripts/check-phase-gate.sh scripts/test-gate.sh \
        scripts/run-phase3-validation.sh scripts/pre-commit-gate.sh   # → no matches (only upgrade-project.sh writes it)
grep -rli "market.signal|1\.1\.5" scripts/*.sh                        # → no matches (BL-102)
```

**Fix shape:** `check-phase-gate.sh` must FAIL the Phase 3→4 gate (track-keyed: standard/full) when `PRODUCT_MANIFESTO.md` Appendix A/C still carry a `PENDING` marker, and enforce the Market Signal evidence (BL-102). The upgrade tool that writes `PENDING` and the gate that should read it must be wired to the same marker. This is the load-bearing answer to "does promotion re-demand what the POC skipped?" — today it *asks* but does not *check*.

**Related:** BL-102 (Market Signal, the third un-enforced obligation); BL-105 (revenue/trademark among the hollow MUSTs); `upgrade-project.sh` (the writer); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-014, the central-question evidence).

---

## BL-125: Nothing runs the test suite at commit time — a commit whose own tests are RED (proving the code is broken) lands clean

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-009)
**Category:** Bug / missing enforcement
**Severity:** Medium
**Status:** Closed — shipped 2026-07-18 (PR #224, merged `ad62827`). `# BL-125-TEST-EXEC` emitter fence → `# BL-125-COMMIT-TESTS` arm in every emitted pre-commit hook: `.claude/test-command` → scripts-block-scoped stack detect (npm placeholder excluded) → LOUD never-silent WARN; RED suite → [BLOCKED]; deletions/renames count as source. Adversarial verifier (Fable) SHIP-WITH-FIXES — both MUSTs (D/R+mts/cts false receipt; no-op certified PASSED) + S1-S4/S6 landed RED-watched, S5 declared. `tests/test-bl125-commit-test-exec.sh` 16/16 ×3 (both lists; emitter fence-excision mutant; guard-registry row K4 two-direction proof). WP-A2 complete — the BL-118+120+125 defense-in-depth trio each now catches the Dogfood-2 XSS. Evidence: ledger § WP-A2 part 2 + VERIFICATION.

The Build-Loop `implemented` step is a self-attested mark; no gate (pre-commit hook, `framework-gate.sh`, or `check-commit-ready`) executes the project's test suite. During the walk, a commit landed while `npm test` was **5 failed | 54 passed** — the four failing tests were the adversarial fixtures *proving the staged code was an exploitable XSS*. The one control that actually detected the vulnerability (the tests) was consulted by no gate.

**Reproduce:** stage code that makes a committed test fail; complete the Build-Loop steps; commit → succeeds despite red tests.

**Fix shape:** add a test-execution arm to the commit path (or to `implemented`/`security_audit` completion) that runs the project's configured test command and blocks on failure — scoped to keep commit latency sane (changed-file-aware or a fast lane), with the same "tool-not-runnable → loud SKIP, never silent pass" discipline as the SAST arm (BL-112). Pairs with BL-118 and BL-120: three independent controls should each have stopped the same XSS.

**Status update 2026-07-18:** fix implemented on branch `fix/bl125-commit-tests` (PR open; Closed with PR + merge SHA at merge). `# BL-125-TEST-EXEC` emitter fence in hook-templates.sh → `# BL-125-COMMIT-TESTS` arm in every emitted pre-commit hook: resolution `.claude/test-command` → stack detect (npm placeholder excluded — no BL-137-class scaffold brick) → LOUD not-enforced WARN; rc=0 → receipt, rc=127 → not-runnable WARN, any other rc → [BLOCKED] (an erroring suite is not a passing suite); docs-only commits fast-lane with a receipt. Adversarial verifier (Fable) SHIP-WITH-FIXES: MUST-1 (diff-filter ACM skipped source DELETIONS/RENAMES + missing .mts/.cts — RED suites landed WITH a false "no source staged" receipt) and MUST-2 (a blank/comment first config line certified a no-op as "[OK] PASSED") + S1/S2/S3/S4/S6 all landed RED-watched; S5 (detected-but-empty suite blocks) resolved as a DECLARED tests-first decision. `tests/test-bl125-commit-test-exec.sh` 16/16 ×3 (both lists; T1 = the walk's RED-suite repro watched LANDING pre-fix; T8 emitter fence-excision mutant; PATH mirror keeps it offline, and its failure now fails the suite loudly). Guard-registry row K4 with executed two-direction proof. Sync-refresh ships the arm to existing projects (suite green). Evidence: ledger § WP-A2 part 2 + its VERIFICATION section.

**Related:** BL-118 + BL-120 (the other two controls that missed the same bug); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-009).

---

## BL-126: The `github_free_tier` branch-protection attestation is honored by 2 of its 3 consumers — `process-checklist.sh --verify-init` FAILs it

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-005)
**Category:** Bug / inconsistent attestation handling
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #206, merged 2026-07-18 `7fa9753`). `# BL-126-ATTEST-CONSULT` in verify_init — the attestation is consulted before any host API probe, matching --preflight and the gate backstop; fence-excision mutant proves it load-bearing. Evidence: § WP-D1.

Three consumers read branch-protection state. `check-gate.sh --preflight` and `check-phase-gate.sh`'s Phase 1→2 backstop both read `.claude/process-state.json::phase2_init.attestations.branch_protection.reason` first and honor `github_free_tier` (`[OK] … branch protection attested`). But `process-checklist.sh`'s `verify_init()` calls `host_verify_protection "main" "$mode"` **directly, with no attestation check**, so on every attested free-tier project it prints `[FAIL] branch_protection_configured — protection verification failed`. An operator running `--verify-init` on a fresh attested project is told to run `check-gate.sh --preflight`, which then reports everything is fine — a contradiction with no resolution.

**Reproduce:** on a free-tier private org scaffold with the `github_free_tier` attestation recorded, `bash scripts/process-checklist.sh --verify-init` → `[FAIL] branch_protection_configured`, while `check-gate.sh --preflight` → `[OK]`.

**Fix shape:** `verify_init()` must read the `github_free_tier` / `gitlab_free_tier_approvals` attestation reason before calling `host_verify_protection`, exactly as its two sibling consumers do — ideally via a shared helper so the three cannot drift again (see BL-095, the centralize-state-parsing item).

**Related:** BL-002/BL-032 (the attestation reasons); BL-095 (centralization would prevent the drift); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-005).

---

## BL-127: The 9-step UAT process demands ZERO evidence — `results_received` is marked complete with an empty `submissions/`

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-010)
**Category:** Bug / hollow gate
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #208, merged 2026-07-18 `31319fe`). `# BL-127-UAT-EVIDENCE`: results_received demands real files (session_id-resolved dir, dotfile-excluded count); the solo escape is EXPLICIT and RECORDED (SOLO_UAT_SOLO_ATTESTED → uat_session.solo_attestations[], off-Light-track warning). Evidence: § WP-E1a.

**Status update 2026-07-17:** fix implemented on PR #208, awaiting merge. `# BL-127-UAT-EVIDENCE` — `results_received` requires ≥1 file in the newest session's `submissions/` OR the explicit `SOLO_UAT_SOLO_ATTESTED=1` escape, which is RECORDED to `uat_session.solo_attestations[]` (attested, not silenced). `completeness_verified`/`triage_complete` deepening deferred (recorded as residual — the evidence-bearing anchor step now gates). Evidence: § WP-E1a.

Every step of the `uat_session` checklist in `process-checklist.sh` is pure self-attestation. Most striking: `--complete-step uat_session:results_received` — the step whose entire meaning is "the tester's results are in" — succeeds with **zero files in `tests/uat/sessions/<date>-session-N/submissions/`**. `completeness_verified` verifies nothing; `triage_complete` consults no bug list. Contrast the Build-Loop `security_audit` step, which DOES require a matching file on disk (BL-120 shows even that is too weak, but it at least demands an artifact) — so the framework can require evidence here and simply doesn't.

**Reproduce:** `bash scripts/process-checklist.sh --complete-step uat_session:results_received` with an empty `submissions/` dir → `[OK]`.

**Fix shape:** gate the evidence-bearing steps on real artifacts — `results_received` on ≥1 file in `submissions/` (or an explicit, recorded "solo operator, no external testers" attestation for Light track), `completeness_verified` on a template-vs-submission diff. Keep the Light-track path frictionless via an attested solo mode, but make the attestation explicit rather than the default silence.

**Related:** BL-105 (the hollow-declared-MUST family — UAT sign-off is named there); BL-120 (the analogous existence-only audit step); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-010).

---

## BL-128: The six-eval review generator parses (BL-103 fixed) but never COMPLETES — the Phase 3→4 review gate's only documented remediation is unusable for the AI-operator

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-015; the successor to BL-103's parse failure)
**Category:** Bug / operationally-unusable tool
**Severity:** Medium
**Status:** Closed — shipped 2026-07-17 (PR #211, merged 2026-07-18 `27d4a78`). `# BL-128-REVIEW-WATCHDOG` (per-review process-GROUP wall bound, TERM→KILL to -pgid — the 159-orphan teardown, verifier-proven against TERM-ignoring and SIGSTOPped trees), `# BL-128-FAILURE-TRIAGE` (continue-on-failure + trust/spend guidance), `# BL-128-INCREMENTAL-MANIFEST`, `--compose-only`/`--assemble-manifest` (claude-free). Evidence: § WP-F1.

`evaluation-prompts/Projects/run-reviews.sh` now parses on bash 3.2 and writes a valid manifest (BL-103 / PR #187 fixes confirmed in-source), but it runs **six sequential full LLM reviews** via nested `claude -p "$(cat prompt)"` (the per-reviewer invocation). Observed across multiple launches: (a) it blocks on the Claude Code trust dialog until `hasTrustDialogAccepted` is set; (b) after trust, it ran **~40 minutes, spawned ~159 orphaned `claude` processes, and produced no review files and no manifest**; (c) a mid-run spend limit killed one attempt. So the Phase 3→4 review gate's **only documented remediation** (the builders-guide Phase-3 Remediation section names this script) cannot in practice produce the manifest the gate requires — pushing the operator to the `SOLO_REVIEWERS_ATTESTED` escape not by choice but because the happy path does not terminate.

**Reproduce:** `PROJECT_DIR=$(pwd) bash evaluation-prompts/Projects/run-reviews.sh web-app` in a generated project → hangs; no `docs/eval-results/review-manifest.json`.

**Fix shape:** make the generator viable for headless/agent operation — bound each review with a timeout and clean process-group teardown; write the manifest incrementally (one entry per completed review) so a partial run is still usable; surface trust-dialog / spend-limit failures as actionable errors instead of a silent hang; and offer a `--compose-only` mode that emits the prompts for an operator/agent to run and a manifest-assembly step, so the manifest can be produced without the generator driving six live sessions.

**Related:** BL-103 (the parse bug this succeeds — fixed); BL-073 (the review gate this feeds); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-015).

**Status update 2026-07-17:** fix implemented on branch `fix/phase-f-bl129-bl130-bl096` (stacked on PR #210; PR number cited at close). All four fix-shape asks landed in `run-reviews.sh`: `# BL-128-REVIEW-WATCHDOG` (per-review wall bound `REVIEW_TIMEOUT_SECS`, default 900s; the review runs in its OWN process group via `set -m` and TERM→KILL goes to `-pgid` — the 159-orphan teardown; bash-native poll loop because the host has no `timeout`/`gtimeout`); `# BL-128-INCREMENTAL-MANIFEST` (`generate_manifest` extracted to a function, called quiet after EVERY review + verbose at end — a killed run keeps everything completed so far); `# BL-128-FAILURE-TRIAGE` (a failed review no longer set-e-aborts the suite; trust-dialog and spend/usage-limit signatures get actionable guidance); `# BL-128-HEADLESS-ARGS` + `# BL-128-COMPOSE-ONLY` (`--compose-only` emits all composed prompts with provenance to `docs/eval-results/prompts/` and starts nothing — claude CLI not even required; `--assemble-manifest` builds+validates the manifest from artifacts already on disk). `tests/test-bl128-review-generator-headless.sh` 5/5 (both lists; claude is a plan-file-driven PATH stub; the incremental case is pinned by reviewer 2's stub OBSERVING reviewer 1's manifest entry mid-run; the group-kill case requires the recorded grandchild pid to be dead). RED watched 0/5 (T4 showed the set-e mid-run abort verbatim); combined 4-arm mutation → all 5 RED (incl. `grandchild-alive=yes`, the resurrected orphan defect) → restore → 5/5. `lint-evalprompts-portability` clean. Evidence: § WP-F1.

---

## BL-129: `init.sh` non-interactive help text contradicts the gov-mode validation code — it tells operators the opposite of what the code accepts

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-001)
**Category:** Bug / doc-vs-code contradiction (THE SCRIPTS WIN → the help is wrong)
**Severity:** Low
**Status:** Closed — shipped 2026-07-17 (PR #211, merged 2026-07-18 `27d4a78`). `--help-non-interactive` states the real gov-mode mapping; stale organizational+private_poc "choosable" comments rewritten as defensive-dead-code notes; N30–N32 pin help and code in both directions. Evidence: § WP-F2.

`init.sh --help-non-interactive` states `--gov-mode` is "REQUIRED when --deployment=organizational. NOT VALID when --deployment=personal." The validation code (the gov-mode rules block in `collect_inputs_non_interactive`) enforces the opposite mapping: `personal` accepts `private_poc` (and production), `organizational` accepts `sponsored_poc` (and production), and it **rejects** `organizational + private_poc` — the exact combo the run spec and the help text imply is valid. Following the help verbatim (`--deployment organizational --gov-mode private_poc`) is rejected. `enforcement-level.sh` and `init.sh::start_phase4` comments also still describe `organizational + private_poc` as a choosable tier — a combo `init.sh` can never produce (dead branch).

**Reproduce:** `init.sh --non-interactive --validate-only --deployment organizational --gov-mode private_poc …` → `[FAIL] --gov-mode=private_poc is not valid for --deployment=organizational`.

**Fix shape:** correct `--help-non-interactive` to state the real mapping (personal→{production, private_poc}; organizational→{production, sponsored_poc}); scrub the stale `organizational + private_poc` "choosable" comments in `enforcement-level.sh` and `init.sh`. Doc-only; no behavior change.

**Status update 2026-07-17:** fix implemented on branch `fix/phase-f-bl129-bl130-bl096` (stacked on PR #210; PR number cited at close). `--help-non-interactive` now states the real mapping (organizational: production, sponsored_poc — personal: production, private_poc — with the always-personal/always-organizational rule and a note that the previous text claimed the opposite); the stale "choosable iff … organizational AND poc_mode=private_poc" comments in `init.sh` (BL-030 resolve block) and `scripts/lib/enforcement-level.sh::assert_choosable` are rewritten as defensive-dead-code notes (the branch fires only on hand-edited manifests; behavior unchanged). Pinned by `test-init-non-interactive.sh` N30 (help-truth: false claim OUT, both real pairs IN — RED watched pre-fix, help-revert mutant killed) + N31/N32 (code mapping in both directions). Evidence: § WP-F2.

**Related:** BL-084-TIER-KEY (the tier predicate); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-001).

---

## BL-130: `run-phase3-validation.sh --attest` records an attestation for a FAILing scanner and prints `[OK]` with no warning

**Logged:** 2026-07-13 (Dogfood 2 walk, finding F-DF2-013)
**Category:** Bug / misleading UX (NOT a bypass — BL-113 still refuses to honor it)
**Severity:** Low
**Status:** Closed — shipped 2026-07-17 (PR #211, merged 2026-07-18 `27d4a78`). `# BL-130-ATTEST-FAIL-GUARD` refuses at write time citing BL-113's rule; the E/F verifier's MUST-FIX (`# BL-130-SPACE-SAFE-LRV` — the shared verdict oracle word-split spaced --results-dir, blinding this guard AND BL-113's carry) landed in `ca50a84` with a watched-RED spaced-dir case. Evidence: § WP-F3 + § PHASE E/F CONSOLIDATED.

`run-phase3-validation.sh --attest <scanner> --reason "…"` records the attestation and prints `[OK] Attested skip for '<scanner>' recorded` **even when that scanner is currently in FAIL state** (not merely un-run/SKIP). The next driver run still correctly reports `FAIL=… → FAIL` and does **not** honor the attestation for a FAIL — so BL-113's guarantee holds and no real FAIL is laundered into a pass. But the `[OK]` with no caveat invites the operator to believe they have cleared something they have not, and leaves a misleading "attested" row against a FAILing scanner.

**Status update 2026-07-17:** fix implemented on branch `fix/phase-f-bl129-bl130-bl096` (stacked on PR #210; PR number cited at close). `# BL-130-ATTEST-FAIL-GUARD-BEGIN/END` in `run-phase3-validation.sh`'s attest mode: refuses at WRITE time (exit 2, message cites BL-113's rule — a FAIL must be fixed or re-run, not attested) when `_p3_last_real_verdict` reports the scanner's newest real verdict is FAIL; the SKIP-attest path is untouched. `tests/test-bl130-attest-fail-guard.sh` (both lists): RED watched against the pre-fix driver (rc=0 + attestation WRITTEN against a FAILing scanner), newest-summary-wins pinned in-fixture, in-suite fence-excision mutant proves the guard load-bearing. Evidence: § WP-F3.

**Reproduce:** with a scanner in FAIL, `bash scripts/run-phase3-validation.sh --attest <scanner> --reason "x"` → `[OK] Attested skip … recorded`; re-run the driver → still `FAIL`.

**Fix shape:** `--attest` should refuse (or loudly warn) when the named scanner's last result is FAIL, distinguishing "attest an un-runnable/SKIP tool" (legitimate) from "attest past a real FAIL" (refused). Message should point at BL-113's rule: a FAIL must be fixed or re-run, not attested.

**Related:** BL-113 (the guarantee that still holds — this is a UX gap, not a hole in it); BL-070 (the driver); `Reports/2026-07-13-dogfood-2/FINDINGS.md` (F-DF2-013).

---

## BL-134: edge-case-test-suite T2 timing bounds too tight — full-lane CI flake (rc=124 with empty output)

**Logged:** 2026-07-18 (first full-lane workflow_dispatch after the Dogfood-2 remediation merge)
**Category:** Bug / test debt (timing-margin flake, aggregator lane only)
**Severity:** Low
**Status:** Closed — shipped 2026-07-18 (PR #214, merged `528f5b2`). ALL resolver-invoking bounds in edge-case-test-suite normalized to 90s; T2.2's self-contradictory assertion recalibrated (<60s under the 90s cap); full suite rerun rc=0, 27 PASS. Root cause measured (a ~25s idle resolver baseline vs 30s kill-caps; resolver+matrix byte-identical `8412b8c..main`).

The full lane's aggregators shard failed on `tests/edge-case-test-suite.sh` T2.1/T2.2, both rc=124 (the suite's own watchdog). Root cause measured, not guessed: a bare `resolve-tools.sh` run on an idle machine takes ~25s (the tool matrix has grown since the 30s bound was set), leaving ~5s headroom; CI-runner or parallel-suite load pushes the honest baseline over the 30s kill-cap. `resolve-tools.sh` and `templates/tool-matrix/` were byte-identical across the failing window (`git diff 8412b8c..main` empty) — a pre-existing margin problem surfacing in the rarely-run full lane, NOT a remediation regression. T2.2's design also self-contradicted: a 30s cap below its own 50s assertion meant the case could never discriminate a real hang from load.

**Related:** the 2026-07-12 memory of two OTHER pre-existing full-suite failures (dry-run resolver fixture, phase-gate run) — still unfiled, tracked for the core-shard verdict of the same run.

---

## BL-135: test-bl033-install-cmds-shape failed in the full-lane CI run but is GREEN locally — unreproduced divergence, needs a second data point

**Logged:** 2026-07-18 (full-lane run 29649055577, core shard)
**Category:** Bug / test flake (unreproduced)
**Severity:** Low
**Status:** Open

The core shard reported `[FAIL] tests/test-bl033-install-cmds-shape.sh` at 16:12Z; the aggregate runner suppresses sub-suite output (`run for details`), so NO case-level detail is recoverable from the log. The suite passes locally on the same content (post-#213 main). Candidates: ubuntu/GNU divergence, runner load (the same run surfaced BL-134's timing-margin class), or a real intermittent. Disposition: watch the next full-lane dispatch — a second failure warrants instrumenting the runner to tee sub-suite output; a second pass declassifies to noise.

**Related:** BL-134 (same run, diagnosed timing class); the full-lane runner's output-suppression pattern (worth `tee`-ing per sub-suite — this entry is the demand signal).

**Observation 2026-07-18 (Dogfood 3, F-DF3-003):** the generated PROJECT's gitleaks CI step showed the same intermittent-flake shape (`ERR failed to scan Git repository error="stderr is not empty"` — failed on 3 commits, passed on others). Second data point for the CI-flake watch, different surface (project CI, not framework CI).

---

## BL-136: full-project-test-suite TEST 5 ("Phase gate script failed to run") and TEST 7 ("Dry-run missing resolver tool output") — pre-existing core-lane failures, on record since 2026-07-12

**Logged:** 2026-07-18 (first formal CI surfacing, full-lane run 29649055577; observed locally 2026-07-12 during the BL-099 round-4 full run — recorded then as "worth a backlog entry, NOT yet filed")
**Category:** Bug / test debt (full-lane only)
**Severity:** Low
**Status:** Open

Both reproduce in the core shard and predate the Dogfood-2 remediation (the 2026-07-12 local run hit the identical pair on then-main). Prior diagnosis notes: TEST 7's fixture under-feeds `prompt_choice` on the dry-run resolver path; TEST 5's phase-gate invocation fails in the suite's fixture context. Neither is covered by the unit lane. Fix shape: reproduce each in isolation, repair the FIXTURE if it models a stale world (the BL-134/zdr-gate pattern) or the product if the gate genuinely misbehaves; register nothing new (both live inside the aggregator).

**Related:** BL-134 (the same run's other test-debt class); Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md § POST-RUN CI REPAIR (the fixture-era doctrine).

---

## BL-137: Generated CI's governance job is structurally unpassable — the phase-gate "Tools needed" arm blocks on dev-workstation tools no CI runner has

**Logged:** 2026-07-18 (Dogfood 3, finding F-DF3-002)
**Category:** Bug / gate credibility (generated-project CI)
**Severity:** High
**Status:** Closed — shipped 2026-07-18 (PR #217, merged `ef0a6a1`). `# BL-137-CI-TOOLS-SCOPE-BEGIN/END` at the increment site: `$CI` set → missing-tools list still prints + explicit `[note]`, NO increment; the local block is byte-unchanged, keyed strictly on `$CI` (never TTY). `tests/test-bl137-ci-tools-scope.sh` 5/5 (both lists; in-suite fence-excision mutant proves the fence carries BOTH arms). Verifier: CI-spoof risk LOW/acceptable (no hook chain reaches check-phase-gate; dominated by the pre-existing warn dial). Evidence: ledger § DOGFOOD-3 REMEDIATION.

The framework-generated CI workflow runs `check-phase-gate.sh`, whose "Tools needed" arm (`issues=$((issues+1))`) blocks whenever Semgrep/Snyk CLI/Claude Code are absent from PATH — which is ALWAYS true on a CI runner (CI uses the semgrep-action container and never carries Snyk auth or the interactive Claude Code CLI). Dogfood 3's project repo: every CI job green EXCEPT `Governance - Phase gate check` = `Tools needed for Phase 1: Semgrep, Snyk CLI, Claude Code … 1 inconsistency(ies) found — blocking`, while the identical command exits 0 locally. The sibling auto-install prompt already hard-N's on `$CI` — the blocking arm needs the same environment awareness. There is NO honest in-project fix (the only workaround is the forbidden `SOIF_PHASE_GATES=warn`), so every generated project ships with a permanently red governance check — the documented-but-impossible class, which trains operators to ignore the governance lane entirely.

**Fix shape:** in CI (`$CI` set), the tools-needed check becomes an informational note (the local dev machine is where the tools contract binds), OR the arm keys on which tools the CURRENT context can actually execute. Must keep the local-machine block intact — mutation-prove both directions.

**Status update 2026-07-18:** fix implemented on branch `fix/bl137-ci-tools-gate` (PR open; Closed with PR + merge SHA at merge). `# BL-137-CI-TOOLS-SCOPE-BEGIN/END` at the increment site: `$CI` set → the missing-tools list still prints + an explicit `[note]` naming the scoping, NO increment; locally the block is byte-unchanged, keyed strictly on `$CI` (never TTY — scripted local runs keep blocking). `tests/test-bl137-ci-tools-scope.sh` 5/5 (both lists; mini tool-matrix fixture so the resolver is fast/deterministic — no BL-134-class full-matrix walk; `env -u CI` makes the local cases CI-portable): T2 RED watched reproducing the walk's verbatim `1 inconsistency(ies) found — blocking` under CI; T1/T4 pin the local block and clean baseline; in-suite fence-excision mutant proves the fence carries BOTH the CI note and the local increment. Blast radius: 9 gate-consumer suites green (none carries tool-preferences.json, so the arm is inert in their fixtures — verified by the sweep, not assumed). Evidence: ledger § DOGFOOD-3 REMEDIATION.

**Related:** `Reports/2026-07-18-dogfood-3/` (F-DF3-002, repro = project CI run 29657490293); the `[WARN]`-trap doctrine (the arm is correctly blocking by increment — the defect is WHERE it blocks).

---

## BL-138: validate_approval_fields' placeholder detector self-collides with the template — first gate unpassable while following the template's own conventions

**Logged:** 2026-07-18 (Dogfood 3, finding F-DF3-001)
**Category:** Bug / gate precision (window-bleed class)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-18 (PR #218, merged `82bbab7`; blame-walker follow-up `719ddcb` on the same PR after CI caught the bounded `$section` silencing the walker's malformed-header refusal). Window H2-anchored + stop-at-next-`## ` + 20-line cap; `# BL-138-APPROVAL-WINDOW` predicate tightened to template literals only (`[SIMULATED]` and date-format prose no longer trip it). `tests/test-bl138-approval-window.sh` 5/5 (both lists; fence-excision mutant on the `[Name]` shape). Introduced the reachable past-cap edge filed as BL-143. Evidence: ledger § DOGFOOD-3 REMEDIATION.

`check-phase-gate.sh::validate_approval_fields` uses `grep -A 20 "$gate_name"` + `grep -qiE "(Approver|Reviewer).*\[.*\]|YYYY-MM-DD"`. Two collisions, both hit in Dogfood 3 with a FULLY-FILLED gate entry: (1) writing the Approval-History row per the template's own convention makes the 20-line window bleed into the BL-105/115 UAT/Attorney PLACEHOLDER rows below; (2) any bracketed annotation in a filled cell (e.g. the dogfood-required `[SIMULATED]`) matches the placeholder regex. Result: `--start-phase1` refused with a diagnostic naming the wrong fix while name+date were correctly filled. This is the SAME window-bleed defect class the BL-115 fixes killed in `_cpg_gate_has_evidence` and `# BL-115-ATTORNEY-ENTRY` — this arm was missed.

**Fix shape:** section-bound the window with the in-repo awk idiom (stop at next `## `), and tighten the placeholder predicate to template-literal placeholders (`\[Name\]`, `\[YYYY-MM-DD\]`-style), not any-bracket. Mutation-prove with a filled-entry-plus-history fixture and a `[SIMULATED]`-annotated cell.

**Status update 2026-07-18:** fix implemented on branch `fix/bl138-approval-window` (PR open; Closed with PR + merge SHA at merge). The window is H2-anchored (`^## ` + gate regex) and stops at the next `## ` with a +20 cap — table rows can neither anchor nor extend the scan (the `| **Gate** |` row was a second anchor, same bleed class as the two fixed siblings); the shared `$section` also feeds the self-approval check, which equally now reads only its own gate's rows. `# BL-138-APPROVAL-WINDOW` fences the tightened predicate: template literals only (`[YYYY-MM-DD]`, `[Name`, `[Attorney`) — `[SIMULATED]` and date-format prose are not placeholders. `tests/test-bl138-approval-window.sh` 5/5 (both lists): T1 = the walk's repro via twin-fixture rc-parity (RED watched rcA=1 vs rcB=0); T2/T3 pin true positives in-section; T4 pins the bare-prose false positive OUT; T5 fence-excision mutant on the [Name] shape (first T5 draft used a placeholder DATE and the BL-115 date-evidence arm correctly masked the mutant — recorded, fixture switched). self-approval + retroactive suites green on the bounded section. Evidence: ledger § DOGFOOD-3 REMEDIATION.

**Related:** BL-115 (the fixed siblings + the residual note that presaged this); `Reports/2026-07-18-dogfood-3/` (F-DF3-001 repro).

---

## BL-139: framework-gate.sh invokes --check-commit-ready without --subject — non-feat source commits blocked at Phase 2 on the terminal path

**Logged:** 2026-07-18 (Dogfood 3, finding F-DF3-004)
**Category:** Bug / gate precision (terminal-commit surface)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-18 (PR #219, merged `b6ca944`). Option (a) with zero new surface: `# BL-139-SUBJECTLESS-DEFAULT` — a subject-less `--check-commit-ready` no longer presumes feat; the commit-msg surface (BL-006) owns the feat rule with the CURRENT subject, so no enforcement is lost. `tests/test-bl139-subjectless-default.sh` 5/5 (both lists; T4 = the end-to-end backstop through the REAL hook chain: `test(unit):` source commit lands, loop-less `feat:` still dies at commit-msg). Backstop's population-conditionality filed as BL-141. Evidence: ledger § DOGFOOD-3 REMEDIATION.

`.git/hooks/framework-gate.sh` calls `process-checklist.sh --check-commit-ready` with NO `--subject`, so `check_commit_ready` cannot apply the documented `code-process-checklist-5` subject short-circuit and treats ANY staged source file as a feat commit. Dogfood 3 proof with identical staged `.ts`: no-subject → rc=1; `--subject "test(e2e): x"` → rc=0; a real `git commit -m "test(e2e): …"` at phase 2 aborted with `[FAIL] pre-commit gate: 'feat(...)' commit blocked`. The pre-commit surface cannot read the CURRENT message (the BL-119 lesson — git writes COMMIT_EDITMSG after pre-commit), so the fix is NOT "pass the message at pre-commit".

**Fix shape:** decide deliberately: (a) move the feat-classification consult to the commit-msg surface (where the subject is current — the BL-119-consistent home), or (b) make the subject-less pre-commit invocation classify by STAGED CONTENT only with the feat-block downgraded to the commit-msg surface. Either way, `test:`/`chore:`/`refactor:` source commits must land while test-less feat commits stay blocked — both directions mutation-proven.

**Related:** BL-119 (the surface doctrine); `code-process-checklist-5` (the defeated short-circuit); `Reports/2026-07-18-dogfood-3/` (F-DF3-004).

**Status update 2026-07-18:** fix implemented on branch `fix/bl139-subject-surface` (stacked on #218; PR open; Closed with PR + merge SHA at merge). Decision taken = the entry's option (a) realized with zero new surface: `# BL-139-SUBJECTLESS-DEFAULT` — a subject-less `--check-commit-ready` no longer presumes feat (the override sits AFTER the original classify block, so fence excision restores the old default exactly); the commit-msg surface (BL-006, `--terminal-mode --tdd-only`) already enforces feat-requires-Build-Loop with the CURRENT subject, so no enforcement is lost. `tests/test-bl139-subjectless-default.sh` 5/5 (both lists): T1 = the walk's repro (RED watched); T2/T3 pin the explicit-subject paths; **T4 = the end-to-end backstop through the REAL installed hook chain (`test(unit):` source commit LANDS, loop-less `feat:` commit still dies at commit-msg)**; T5 fence-excision mutant. Two suites pinned the old presumed-feat default and were rewritten under the documented-bug exception (commit-ready-subject T5 → asserts the flip; classifier T12's helper → proves source classification through the explicit-feat path): 7/7 + 12/12. Evidence: ledger § DOGFOOD-3 REMEDIATION.

---

## BL-140: zap-dast unretrievable under Colima on macOS — report written in-container but never lands on the host (TMPDIR outside the virtiofs mount)

**Logged:** 2026-07-18 (Dogfood 3, finding F-DF3-005)
**Category:** Bug / scanner runtime portability
**Severity:** Medium
**Status:** Closed — shipped 2026-07-18 (PR #220, merged `b75f5a9`). `# BL-140-ZAP-WORKDIR` (bind-mount host dir = `$RESULTS_DIR/.zap-work.$$`, absolutized against `$PWD` per verifier MUST-fix D1) + `# BL-140-ZAP-MOUNT-HINT` (no-report FAIL names the VM-mount diagnosis + TMPDIR fallback; FAIL-not-SKIP posture untouched) + `# BL-140-ARCHIVE-FRESH` (same-second archive collision de-flaked, MUST-fix D-extra). `test-bl070-snyk-zap-scanners.sh` 48/48, green 3× consecutive. SHOULD-fixes filed as BL-141/142/143. Evidence: ledger § DOGFOOD-3 REMEDIATION.

`run-phase3-validation.sh`'s zap-dast leg mounts a `mktemp -d` work dir into the ZAP container. On macOS+Colima, `mktemp` lands in `$TMPDIR=/var/folders/...`, which Colima does NOT share (only `/Users/<user>` is virtiofs-mounted) — the container writes `/zap/wrk/zap-report.json` (verified, 24 KB) but the host dir stays empty, so the driver reports `OWASP ZAP produced no report (rc=2)` → FAIL on a verifiably clean app, and BL-130 then (correctly) refuses to attest the FAIL. No driver path to green on this common runtime. Dogfood 3's honest workaround (recorded, env-only): `TMPDIR=$HOME/.df3-tmp` → `[PASS] zap-dast — 0 Medium+`.

**Fix shape:** place the ZAP work dir under `$HOME` (or the project tree) instead of `$TMPDIR`, or detect the docker context's mount capability and fail with a diagnostic NAMING the mount problem + the TMPDIR workaround. The FAIL-not-SKIP posture is correct (a scan that ran but is unreadable must not silently SKIP) — the fix is making the report readable, not softening the verdict.

**Related:** BL-070 (the driver); BL-130 (whose refusal worked exactly as designed here); `Reports/2026-07-18-dogfood-3/` (F-DF3-005, incl. the root-cause mount analysis).

**Status update 2026-07-18:** fix implemented on branch `fix/bl140-zap-workdir` (stacked on #219; PR open; Closed with PR + merge SHA at merge). `# BL-140-ZAP-WORKDIR` — the bind-mount host dir moves from `$TMPDIR` mktemp to `$RESULTS_DIR/.zap-work.$$` (the project tree: where the operator works, inside VM shared mounts; the mktemp stays as the excision-fallback so the mutant restores the old behavior exactly). `# BL-140-ZAP-MOUNT-HINT` — the no-report FAIL now names the VM-mount diagnosis + the TMPDIR fallback (FAIL posture unchanged — an unreadable scan is not a clean scan). Three cases added to `test-bl070-snyk-zap-scanners.sh`: the workdir witness case RED-watched with the `/var/folders` path on screen; the hint case; a dual-fence mutation case (workdir excision restores $TMPDIR positively; hint excision drops the diagnosis while FAIL survives). Driver blast radius green: bl130 4/4, license, threat-model, bl095 9/9. Evidence: ledger § DOGFOOD-3 REMEDIATION.

**Verifier follow-up 2026-07-18 (two MUST-FIXes landed on the same branch, suite now 48/48):** (1) **D1** — `docker -v` rejects a RELATIVE host path (rc=125), and `RESULTS_DIR` defaults to the relative `docs/test-results/phase3`, so the DOCUMENTED bare invocation was hard-broken on every docker runtime while all 47 fixtures (absolute `--results-dir`) passed. Fixed: `# BL-140-ZAP-WORKDIR` absolutizes the work dir against `$PWD` (no cd — the driver never changes CWD); new `T-zap-workdir-absolute` case passes a RELATIVE `--results-dir` and asserts an absolute `-v` host path (RED watched: `docs/test-results/phase3/.zap-work.NNN`). (2) **D-extra** — `_p3_run_scanner`'s second-granularity per-run timestamp let two same-second sub-runs collide on one archive path, so a no-report scan cross-read the prior run's clean archive (the mutation case was reproducibly red at normal speed, green under `bash -x`). Fixed BOTH sides: `# BL-140-ARCHIVE-FRESH` `rm -f "$archive"` before every dispatch (product de-flake) + the two mutation sub-runs isolated into separate results dirs. Green 3× consecutively. SHOULD-fixes filed as BL-141/142/143.

---

## BL-141: verify-install --auto-fix ignores the commit-msg hook; sync can silently leave it absent — the BL-139 "no enforcement lost" claim is population-conditional

**Logged:** 2026-07-18 (Dogfood-3 wave verifier, B1/B2 SHOULD-fix)
**Category:** Bug / enforcement coverage (strict-tier populations)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-19 (PR #225, merged `cf10873`). `# BL-141-COMMITMSG-VERIFY` (verify-install detects an absent/unmarked/non-executable commit-msg hook as auto-fixable; `fix_commitmsg_hook` repairs via the hook-templates single source, composing + idempotent) + `# BL-141-SYNC-WARN` (the sync's declined arm warns — never silent — when pre-commit exists without commit-msg). `tests/test-bl141-commitmsg-repair.sh` 6/6 ×3 (both lists; T2 = end-to-end backstop restoration through the real hook chain; dual fence-excision mutants). Consolidated wave verifier: SHIP. Evidence: ledger § WP-BL141 + the wave VERIFICATION.

BL-139 flipped the subject-less `--check-commit-ready` default to not-feat on the pre-commit surface, relying on the COMMIT-MSG hook to enforce feat-requires-Build-Loop with the current subject. That backstop is only present for populations that HAVE the commit-msg hook. The verifier's census: fresh `init.sh` scaffolds install it unconditionally (BL-107); but `verify-install --auto-fix` checks/repairs ONLY `.git/hooks/pre-commit` (no commit-msg detection anywhere in `scripts/verify-install.sh`), and the currency sync (`_bl099_sync_commitmsg_hook` via `_bl099_hook_consent`) installs it non-interactively ONLY with `--install-hooks` (default off) — a piped `--sync-framework` on a legacy project leaves it "not installed (declined)". For any such project that also runs the strict-tier `framework-gate.sh`, the BL-139 flip converts an over-broad block into NO terminal-path feat gate at all — concentrated on the strictest tiers where docs call the block non-bypassable.

**Fix shape:** teach `verify-install --auto-fix` to detect a missing/stale commit-msg TDD hook and repair it (mirror the pre-commit path); make the sync path WARN when `.git/hooks/pre-commit` exists but the commit-msg hook does not. Mutation-prove: a project with pre-commit-but-no-commit-msg → auto-fix installs it → a loop-less feat commit is blocked again.

**Related:** BL-139 (the flip this backstops); BL-107 (universal install — the fresh-scaffold half that IS covered); BL-099 (`_bl099_hook_consent`); `Reports/2026-07-18-dogfood-3/` verifier B1/B2.

**Status update 2026-07-19:** fix implemented on branch `fix/bl141-commitmsg-repair` (PR open; Closed with PR + merge SHA at merge). `# BL-141-COMMITMSG-VERIFY` (verify-install: detect absent/unmarked/non-executable commit-msg hook as auto-fixable; `fix_commitmsg_hook` repairs via the hook-templates single source, composing + idempotent) + `# BL-141-SYNC-WARN` (the sync's declined arm warns — never silent — when pre-commit exists without commit-msg, naming both repairs). `tests/test-bl141-commitmsg-repair.sh` 6/6 ×3 (both lists; T2 = end-to-end backstop restoration through the real hook chain; dual fence-excision mutants). Evidence: ledger § WP-BL141.

---

## BL-142: hook-templates.sh header comment claims the sync path skips rust/unknown languages — contradicts BL-107 universal install

**Logged:** 2026-07-18 (Dogfood-3 wave verifier, B1 stale-doc SHOULD-fix)
**Category:** Bug / doc-vs-code contradiction (THE SCRIPTS WIN)
**Severity:** Low
**Status:** Closed — shipped 2026-07-19 (PR #227, merged `23c996f`). Both stale header spots corrected (the pattern is a test-evidence-detection switch, not an install gate; hooks install universally per BL-107). Doc-only; emitted hooks proven byte-identical (stash round-trip cmp; re-proven by the consolidated wave verifier across all emitters, 21.6 KB). Consolidated wave verifier: SHIP. Evidence: ledger § WP-BL142 + the wave VERIFICATION.

`scripts/lib/hook-templates.sh`'s header still says the currency sync path is "EXPECTED to lack the [commit-msg] hook" for rust/unknown languages — contradicted by `_bl099_sync_commitmsg_hook`'s own `BL-107-UNIVERSAL-INSTALL` comment, which installs for every language. Doc-only; correct the header to match the code (the scripts win).

**Related:** BL-107; BL-141 (same subsystem); `Reports/2026-07-18-dogfood-3/` verifier B1.

**Status update 2026-07-19:** fix implemented on branch `fix/bl142-hook-templates-header` (PR open; Closed with PR + merge SHA at merge). Both stale header spots corrected (the Contents bullet and the soif_lang_test_pattern block comment): the pattern is documented as a test-EVIDENCE-detection switch, not an install gate — the hook installs for every language per BL-107-UNIVERSAL-INSTALL, with `_bl099_sync_commitmsg_hook`'s own comment named as the code-side truth. Doc-only; no behavior change (`bash -n` + emitted-hook byte-identity unaffected — comments only).

---

## BL-143: anti-self-approval control silently skips when the Approver row lies past validate_approval_fields' +20 section cap

**Logged:** 2026-07-18 (Dogfood-3 wave verifier, C3 SHOULD-fix)
**Category:** Bug / gate precision (evasion edge)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-19 (PR #226, merged `2fb7cd1`). `# BL-143-PASTCAP-RECOVERY`: the approver name is recovered from the blame walker's OWN uncapped H2-strict scan when the capped pre-extraction comes back empty — the control RUNS (per-line blame included) instead of silently skipping; truly-absent-row boundary unchanged and pinned. `tests/test-bl143-pastcap-selfapproval.sh` 5/5 ×3 (both lists; fence-excision mutant); 12-suite gate-consumer battery green. Consolidated wave verifier: SHIP (recovery awk proven byte-identical to the walker's); residuals filed as BL-144. Evidence: ledger § WP-BL143 + the wave VERIFICATION.

`validate_approval_fields`' bounded `$section` (BL-138) is capped at +20 lines. The self-approval extraction reads the approver name from that capped section; when a crafted APPROVAL_LOG pushes the Approver row past +20 (filler rows, or a Date row within `_cpg_gate_has_evidence`'s head-15 with the Approver row below), `approver_name` comes back empty and the `[ -n "$approver_name" ]` guard exits with NO WARN — the anti-self-approval control is silently skipped, even though the (uncapped) blame walker would locate the row. Pre-BL-138 the row-anchored window virtually always contained the Approver row, so BL-138 introduced the reachable edge.

**Fix shape:** when the blame walker finds an Approver row the capped extraction could not, WARN (or take the name from the walker's located line). Mutation-prove with an org fixture whose Approver row sits at section-line 25.

**Related:** BL-138 (the cap this exposes); the blame walker (`# BL-116` per-line self-approval); `Reports/2026-07-18-dogfood-3/` verifier C3. Note: the wave's blame-walker follow-up (`719ddcb`) restored the walker's PERMISSIVE pre-extraction, which mitigates the SKIP for the malformed-header case but NOT the past-cap-row case — this entry tracks the latter.

**Status update 2026-07-19:** fix implemented on branch `fix/bl143-pastcap-selfapproval` (PR open; Closed with PR + merge SHA at merge). The entry's stronger option realized: `# BL-143-PASTCAP-RECOVERY` recovers the approver name from the blame walker's OWN uncapped H2-strict scan when the capped pre-extraction comes back empty — the control RUNS (per-line blame included) instead of warning-and-skipping. Truly-absent-row boundary unchanged and pinned. `tests/test-bl143-pastcap-selfapproval.sh` 5/5 ×3 (both lists; T1 = the C3 edge RED-watched as a zero-output silent skip; T5 fence-excision mutant). 12-suite gate-consumer battery green. Evidence: ledger § WP-BL143.

---

## BL-131: Commit-time SAST residual blindness — `insertAdjacentHTML`, jQuery `.html()`, `.vue` SFC scripts, and inline `<script>` in `.html` all commit clean (no public registry rule exists for them)

**Logged:** 2026-07-17 (BL-118 adversarial verification, PR #199)
**Category:** Bug / security enforcement — known-gap registration (defense-in-depth residue)
**Severity:** Medium
**Status:** Open

Empirically proven through the real emitted hook during BL-118's adversarial verification: staged fixtures using `el.insertAdjacentHTML('beforeend', x)`, jQuery `$(sel).html(x)`, `innerHTML` inside a `.vue` SFC `<script>` block, and an inline `<script>` in a committed `.html` file all COMMIT CLEAN with the `[OK] semgrep: SAST ran` receipt. This is NOT a pack-choice error: the full `r/javascript.browser.security` pack and `p/xss` both produce zero findings on those fixtures at any severity (tested with and without explicit `location.*` taint sources) — no rule in the public registry covers them, so no `--config` addition can close this. The BL-118 fix's own coverage claim (innerHTML/outerHTML/document.write) is accurate; this entry exists so the residue is a recorded decision, not a rediscovery for the next dogfood.

**Fix shape:** ship a small custom semgrep ruleset with the scaffold (e.g. `.semgrep/soif-dom-sinks.yml`, added as another `--config` in the hook + CI templates) covering the missing sinks at ERROR severity, with the same exact-token pins and mutation-test discipline as BL-118; or explicitly accept + document the residue in the security-model docs. Note Phase-3 `--config auto` does not close it either (registry-bound).

**Related:** BL-118 (PR #199 — the covered sinks); BL-112 (the gate plumbing); BL-132 (the other verifier-found gap); `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` (WP-A1 verifier findings).

---

## BL-132: The pre-commit SAST arm scans WORKTREE paths, not INDEX content — stage the vuln, overwrite the worktree copy, and the committed bytes are never scanned

**Logged:** 2026-07-17 (BL-118 adversarial verification, PR #199)
**Category:** Bug / security enforcement — pre-existing BL-112 design gap (orthogonal to, and unchanged by, BL-118)
**Severity:** Medium
**Status:** Open

Reproduced during BL-118's adversarial verification: `git add app.ts` (containing the XSS), overwrite the worktree `app.ts` with the clean version, `git commit` → the commit LANDS with the `[OK]` receipt, and `git show HEAD:app.ts` contains the vulnerable `innerHTML`. The hook hands semgrep staged PATHS (`git diff --cached --name-only`), so semgrep reads WORKTREE bytes, which need not be the staged bytes. Partial-stage (`git add -p`) and stage-then-edit flows also scan the wrong content in the benign direction (false signal from unstaged edits).

**Fix shape:** scan index content: materialize staged blobs into a temp tree preserving relative paths/extensions (`git checkout-index --temp` or `git show :<path>`), run semgrep there, report findings against the real paths. Same BL-112-SAST-NOTRUN/receipt discipline. Check gitleaks parity while there (`gitleaks git --staged` already reads the index).

**Related:** BL-112 (the arm's design); BL-118 (PR #199 — verifier proved the gap is orthogonal to the ruleset fix); `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` (WP-A1).

---

## BL-133: Plain `--terminal-mode` fed the STALE `COMMIT_EDITMSG` to `lint-backlog-references --pre-commit-mode` — the previous commit's message could block the current commit

**Logged:** 2026-07-17 (BL-119 adversarial verification, PR #200)
**Category:** Bug / gate correctness — BL-119's defect class, one more consumer
**Severity:** Medium (narrow reach: the lint must be present project-locally — `init.sh` does not ship `lint-*.sh` downstream, so it bites framework-context repos and hand-copied setups)
**Status:** Closed — shipped 2026-07-17 (PR #200, landed via PR #202 `88bddd3`) alongside BL-119: the stale-message feed into the BR lint is removed under the extended `# BL-119-NO-MSG-AT-PRECOMMIT` marker; RED→GREEN + HEAD-revert mutation recorded in `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § WP-A3. The open design question below (grow the commit-msg surface?) stays parked with BL-107. **Decision 2026-07-18 (Karl):** leave removed — repo-side CI runs lint-backlog-references on every PR, the removed arm never enforced correctly for any population (A3 verifier audit), and no downstream demand for commit-time citation checking exists; re-home at commit-msg only if that demand appears (file a fresh entry then).

Verifier-reproduced: with a project-local `lint-backlog-references.sh` and a backlog containing only BL-001, write `docs: previous commit citing BL-9999` into `.git/COMMIT_EDITMSG` (the residue of a landed commit), stage an innocent file, `git commit -m "docs: innocent"` → **rc=1, "backlog-references lint failed"** — the PREVIOUS commit's message blocked the CURRENT commit. Same staleness mechanism as BL-119: pre-commit never sees the message being committed.

**Fix (in PR #200):** the message feed is removed from the plain terminal path; the message-mode BR check survives on the PreToolUse surface, which parses the CURRENT message from the command. **Open design question (deliberately not decided unilaterally):** should the commit-msg surface (`--tdd-only`) grow a third arm running the BR message check with the current message? It would restore BR message coverage for editor/human-terminal commits, at the cost of widening a surface documented as exactly two gates. Decide when BL-107 (per-language commit-msg hooks) is implemented, since that changes the same surface.

**Related:** BL-119 (PR #200, the defect class + fix); BL-010 (the commit-msg surface's contract); `scripts/lint-backlog-references.sh` (`--pre-commit-mode`).

## BL-144: self-approval scan is fully silent for malformed-header + past-cap and for past-cap placeholder Approver cells

**Logged:** 2026-07-19 (Dogfood-3 SHOULD-fix wave consolidated verifier, S1+S2)
**Category:** Bug / gate precision hardening (evasion residuals, pre-existing)
**Severity:** Low
**Status:** Open

Two silent shapes survive BL-143, both executed and both byte-for-byte pre-existing on main: (a) a malformed `### `-header gate section whose Approver row also sits past the `-A 20` cap — the `# BL-143-PASTCAP-RECOVERY` awk computes `NO_SECTION` and its `''|*[!0-9]*)` arm discards it, while the walker's loud malformed-header refusal is only reachable when a name was pre-extracted (an attacker combining both evasions gets zero output); (b) a past-cap `| **Approver** | [Name] |` (or empty-cell) row — the BL-138 placeholder predicate is `head -20`-capped, and the recovery recovers `[Name]`, recognizes it in its own trigger condition, then drops it silently.

**Fix shape (one-liners, sketched by the verifier):** surface the recovery's `NO_SECTION` through the walker's existing WARN (deliberate scope call: this also makes prose-only gate mentions loud — BL-143's T4 pinned boundary maps to `NO_APPROVER` and is NOT disturbed); WARN when the recovered name is `[Name]`/empty. Mutation-prove both with past-cap fixtures.

**Related:** BL-143 (the recovery this hardens; its T4 pins the boundary to preserve); BL-138 (the capped placeholder predicate); `# BL-116` blame walker.

---

## BL-145: verify-install hook repairs write through symlinked hooks on the no-consent --auto-fix surface; hook checks blind to core.hooksPath

**Logged:** 2026-07-19 (Dogfood-3 SHOULD-fix wave consolidated verifier, S3)
**Category:** Debt / repair-surface hygiene (pre-existing class)
**Severity:** Low
**Status:** Open

Executed: with `.git/hooks/commit-msg` symlinked to a shared out-of-tree file, `verify-install --auto-fix` appends the managed block into the symlink TARGET (target mutated, symlink kept). Pre-existing class — `fix_precommit_hook` is worse (full `soif_write_precommit_hook` clobber through the symlink), and the sync's install arm appends identically — but `--auto-fix` is a no-consent surface, so it deserves the guard first. Related observation: both hook checks read `.git/hooks/` literally, so a `core.hooksPath` project gets a PASS plus an inert "repair" (framework-generated projects never set it; parity with the pre-existing pre-commit blind spot).

**Fix shape:** `[ -L .git/hooks/<hook> ]` → `register_manual` (repairing a shared file needs a human); optionally consult `git config core.hooksPath` in both checks and say so when set.

**Related:** BL-141 (the repair surface); `# BL-118-SINGLE-SOURCE` (fix_precommit_hook); `_bl099_sync_commitmsg_hook`.

---

## BL-146: Adversarial PR reviewer agent — highest technical standard, context7-current, optimal, stable, secure

**Logged:** 2026-07-20 (Karl directive)
**Category:** Proposal / review tooling (both repos)
**Severity:** Medium
**Status:** Open

Karl's directive: an agent that reviews PRs ADVERSARIALLY with the intent of making sure the PR is of the highest technical standard, using the most up-to-date info from context7, as optimal as possible, stable, and secure.

**What exists today:** the BL-100 adversarial-acceptance doctrine (practiced across the 2026-07 arcs, now folding into the BL-097 operating-model design); the gate-enforced Phase-3 review manifest + `evaluation-prompts/` library (phase-scoped, not PR-scoped); per-WP ad-hoc verifier dispatches (this arc's working practice — effective but hand-rolled each time). **What's missing:** a STANDING, dispatchable PR-review agent — point it at a PR, get a refutation-first review across five dimensions:
1. **Technical standard** — correctness, idiom, and the repo's own discipline rules (marker fences, registration, hermeticity, portability).
2. **Currency** — context7 lookups for every library/API/CLI the diff touches; deprecated or superseded usage is a finding (the context7 session rule, promoted to a review dimension).
3. **Optimality** — simplification, efficiency, no unnecessary surface.
4. **Stability** — edge cases, error handling, flake potential, test quality (vacuity/weak-test classes).
5. **Security** — the adversarial security lens per change, not just per phase.

**Design decisions to take before building:** trigger surface (slash-command vs `gh` comment vs auto-on-open); scope order (framework repo first, generated-project variant second); verdict grammar (reuse BL-100's block/major_concerns/minor_concerns/approve rubric — major+ blocks); how context7 is reached from the review environment (MCP availability in headless runs — the BL-128 lesson); reviewer MODEL comes from the operating model chosen per the BL-097 trio decision (this agent is the reviewer role's concrete tool — compose with that design, don't duplicate it).

**Related:** BL-100 (the acceptance doctrine this makes standing); BL-097/BL-098 (operating model / reviewer role); BL-128 (headless review dispatch machinery precedent); `evaluation-prompts/` (the phase-review library); the context7 global rule.

**Live test 2026-07-21 (Karl-directed):** one Fable subagent reviewed PRs #229+#231 under this entry's five-dimension brief. IT WORKS — verdicts #229 approve (every SHA/path/marker claim verified) and #231 major_concerns whose MAJOR was a genuine miss two prior adversarial verifiers left standing (comment-blind wiring greps: a disabled-instantiation mutant passed every PR-blocking check; only the manual-dispatch full lane would catch it). All findings landed same-day. Design inputs from the run (META): (1) the reviewer needs a WORKTREE pinned to the PR tip — this run got lucky that the checkout was the branch; (2) pre-cleared scratch/mutation-lab semantics (first lab setup was permission-denied); (3) verdict posting + numbered finding IDs in the ledger grammar; (4) a standing LANE-REACHABILITY probe — evaluate mutation survivorship against the PR-BLOCKING check set, not the whole estate (else every full-lane-only gap becomes an automatic major on unrelated PRs); (5) trigger = slash-command/dispatch-on-demand, NOT auto-on-open (~40 tool calls + a mutation lab per run); (6) context7 was reachable via ToolSearch and produced a real oracle (GFM cell-count grammar over the new tables) — headless dispatch must verify reachability before claiming currency coverage; (7) the Agent tool exposes a model knob but no EFFORT knob — "max effort" rode in the prompt; the operating-model design (BL-097) should carry effort as a first-class reviewer parameter.

---

## BL-147: Emitted CI approval-log integrity steps are vacuous under every standard Actions checkout — tampering sails through silently

**Logged:** 2026-07-21 (BL-146 cumulative PR sweep, CR-1; validated in-session)
**Category:** Bug / silent-success (emitted CI, security lane)
**Severity:** High
**Status:** Open

The "Approval log integrity" + "Approval author verification" steps in `templates/pipelines/ci/github/{python,typescript,other}.yml` (+ gitlab twins) run `git diff origin/main...HEAD -- APPROVAL_LOG.md 2>/dev/null | grep -qE '^\-[^-]'` — but the templates set NO `fetch-depth`, and `actions/checkout`'s default depth-1 clone has no `origin/main` ref: the diff dies `fatal: bad revision`, the `2>/dev/null` eats it, and the step PASSES on a tampered approval log (executed proof: sweep fixture). On push-to-main the expression is self-comparing (vacuous there too). Parity hole: 7 of 10 GitHub language templates never got the steps at all. Introduced PR #8 (`db2c14e`), never revisited — the BL-112/113 silent-success class, in the governance lane, shipped to every generated project.

**Fix shape:** `fetch-depth: 0` on checkout; resolve the base explicitly (`origin/${{ github.base_ref || 'main' }}`; `${{ github.event.before }}` on push); drop the `2>/dev/null` (a bad revision must fail LOUDLY); stamp the corrected step into all 10 languages × both hosts; content-pin suite.

**Related:** BL-112/BL-113 (the class); PR #8 (origin); BL-151 (shares the fetch-depth fix).

**Status update 2026-07-21:** WP-1 shipped on branch `fix/bl147-bl151-ci-approval-integrity` (status stays Open — Closed flip happens at merge, citing PR# + SHA). All 10 `templates/pipelines/ci/github/*.yml` gained `fetch-depth: 0` on checkout; both governance approval steps (integrity + author verification) are now stamped BYTE-IDENTICAL into all 10 (7 previously had none — verified single sha across all 10), resolving the base explicitly (`origin/${{ github.base_ref || 'main' }}`, `${{ github.event.before }}` on push) and failing LOUDLY via `git rev-parse --verify "$BASE"` when the base cannot resolve; every `2>/dev/null` on an APPROVAL_LOG line is gone. The two gitlab approval twins (`python.yml`, `typescript.yml`) got the same explicit-base + loud-fail + no-silencer treatment via `CI_MERGE_REQUEST_TARGET_BRANCH_NAME`/`CI_DEFAULT_BRANCH`. Watched-RED via the wave's one shared content-pin suite `tests/test-bl147-ci-template-integrity.sh` (mechanically derived template lists + >=10 count floor): pre-fix **3 passed / 11 failed**, post-fix **14 passed / 0 failed**. Mutation proofs (both restored to GREEN): re-adding `2>/dev/null` to one template → case Cc RED (13/1); removing `fetch-depth: 0` from one → case Ca RED (13/1). Registered in BOTH `tests/full-project-test-suite.sh` and the `tests.yml` unit list. All 20 CI templates re-validated as parseable YAML.

---

## BL-148: Every generated GitHub CI workflow runs SAST via semgrep-action — archived upstream April 2024

**Logged:** 2026-07-21 (sweep CR-2; validated: `gh api repos/semgrep/semgrep-action` → archived:true, pushed 2024-04-09)
**Category:** Bug / currency (emitted CI, security lane)
**Severity:** High
**Status:** Open

All 10 `templates/pipelines/ci/github/*.yml` pin `semgrep/semgrep-action@713efdd… # v1 (v0.58.0)` — the 2021 semgrep-agent era of an action dead upstream for 2+ years. Current upstream guidance (context7): the `semgrep/semgrep` container running `semgrep scan`/`semgrep ci`.

**Fix shape:** replace with a `container: semgrep/semgrep` job (or `pip install semgrep` run step) executing the LOCAL HOOK'S exact policy — `semgrep scan --config p/owasp-top-ten --config p/security-audit --config r/javascript.browser.security.insecure-document-method --severity=ERROR --error` — so CI and the pre-commit hook enforce identical rules (`# BL-118-DOMXSS-CONFIG` parity).

**Related:** BL-118 (the hook policy to mirror); BL-153 (the bitbucket image twin).

---

## BL-149: Emitted release-pipeline DAST is the un-fixed BL-122 twin — unpassable for essentially every web app

**Logged:** 2026-07-21 (sweep CR-3; validated: raw exit-code judgment on `zap-baseline.py`)
**Category:** Bug / gate correctness (emitted release pipeline)
**Severity:** High
**Status:** Open

`templates/pipelines/release/github/web.yml` runs `docker run -t zaproxy/zap-stable zap-baseline.py -t ${{ vars.PREVIEW_URL }}` and judges the RAW exit code — baseline reports ALL alerts as WARN (exit 2), and rule 10049 fires under every possible Cache-Control value (the proven BL-122 mechanism), so any real site fails the release. PR #203 fixed exactly this in `run-phase3-validation.sh` and never touched the template. Aggravators: image unpinned (every other action in the file is SHA-pinned); no guard when `PREVIEW_URL` is unset; gitlab/bitbucket release templates have no DAST at all (recorded, not fixed here).

**Fix shape:** port BL-122 — `-J zap-report.json` + mounted workdir + jq `riskcode>=2` verdict; pin the image (`ghcr.io/zaproxy/zaproxy:stable` to match the phase-3 scanner); `if: vars.PREVIEW_URL != ''`. Also fix `templates/tool-matrix/web.json`'s check of `zaproxy/zap-stable` — an image the scanner never uses (sweep CR-8 nit).

**Related:** BL-122 (`# BL-122-ZAP-RISK-FILTER`, the port source); BL-070 (the scanner).

---

## BL-150: Every SHA-pinned GitHub Action in the estate lags 1–3 majors; pins are invisible to the currency system

**Logged:** 2026-07-21 (sweep CR-4; validated: checkout v4.3.1 vs v7.0.1 latest)
**Category:** Debt / currency (framework workflows + emitted templates + init.sh pin table)
**Severity:** Medium
**Status:** Open

checkout v4.3.1→v7.0.1, setup-node v4→v7, setup-python v5→v7, upload-artifact v4→v7, setup-java v4→v5, action-gh-release v2→v3, golangci-lint-action v6→v9, gitleaks-action v2→v3 (flutter-action current). Surfaces: `.github/workflows/{lint,tests}.yml`, all emitted CI/release templates, init.sh's `RELEASE_SETUP_ACTION` table. BL-109's currency block tracks file SHAs/hooks/MCP — action pins structurally invisible.

**Fix shape:** one refresh PR re-pinning to current majors (new SHAs + version comments); then a durable watcher: pin inventory in the currency block or a lint diffing pin comments vs `releases/latest` (design-light, can defer the watcher to BL-109).

---

## BL-151: Org-track generated projects get a failing (or license-less) gitleaks CI step

**Logged:** 2026-07-21 (sweep CR-5; validated: no GITLEAKS_LICENSE anywhere in templates; depth-1 checkout)
**Category:** Bug / documented-but-impossible (emitted CI, org tier)
**Severity:** Medium
**Status:** Open

gitleaks-action requires `GITLEAKS_LICENSE` for ORGANIZATION accounts and `fetch-depth: 0`; the emitted templates set neither. Organizational deployment is a first-class tier — the BL-137 class in the security lane.

**Fix shape:** drop the action; run the gitleaks CLI directly (`gitleaks git` — no license, mirrors the local hook), riding BL-147's fetch-depth fix. Alternative (rejected for friction): wire the license secret.

**Related:** BL-147 (shared checkout fix); BL-137 (the class).

**Status update 2026-07-21:** WP-1 shipped on branch `fix/bl147-bl151-ci-approval-integrity` (status stays Open — Closed flip happens at merge, citing PR# + SHA). The `gitleaks/gitleaks-action` step was dropped from all 10 `templates/pipelines/ci/github/*.yml` and replaced by the license-free CLI (`GITLEAKS_VERSION=8.30.1` — the current release per `gh api repos/gitleaks/gitleaks/releases/latest` → `v8.30.1`; `curl … | tar -xz gitleaks && ./gitleaks git --redact --exit-code 1`), so no `GITLEAKS_LICENSE` is required for org accounts. `gitleaks git` scans full history, so it rides BL-147's `fetch-depth: 0` fix. Content-pinned by the shared suite `tests/test-bl147-ci-template-integrity.sh` case Ce (no `gitleaks/gitleaks-action`; every github CI template runs `./gitleaks git`). Suite tally post-fix **14 passed / 0 failed** (pre-fix 3/11). Registered in BOTH lists.

---

## BL-152: GitLab driver's org-mode approvals call uses an API deprecated since GitLab 14.0

**Logged:** 2026-07-21 (sweep CR-6; validated: `glab api -X PUT projects/:id/approvals` + `approvals_before_merge` in gitlab.sh)
**Category:** Debt / currency (host driver)
**Severity:** Medium
**Status:** Open

`scripts/host-drivers/gitlab.sh` PUTs `/approvals` with `approvals_before_merge` — deprecated since 14.0, removal flagged (approval_rules is current; the field is slated out in API v5). Works today; on removal the failure lands in the generic exit-3 arm, not the handled BL-032 free-tier arm.

**Fix shape:** `POST /projects/:id/approval_rules` with `approvals_required: 1`, preserving the BL-032 Premium-only detection wording; the driver suite pins both arms.

**Related:** BL-032 (the free-tier arm to preserve); PR #91 (the prior "modern API" pass).

---

## BL-153: Bitbucket CI templates scan with a rename-frozen semgrep image and the deprecated gitleaks command form

**Logged:** 2026-07-21 (sweep CR-7; validated: `returntocorp/semgrep` + `zricethezav/gitleaks:latest` + `gitleaks detect` in the templates)
**Category:** Bug / currency (emitted CI, bitbucket host)
**Severity:** Medium
**Status:** Open

`returntocorp/semgrep` stopped receiving updates at the 2023 org rename (current: `semgrep/semgrep`) — generated bitbucket projects scan with a frozen engine/ruleset. `gitleaks detect` is the pre-8.19 deprecated form (`gitleaks git`/`dir` current); `:latest` tag unpinned.

**Fix shape:** `image: semgrep/semgrep` + the BL-148 flag policy; `gitleaks dir .` with a version-tagged image.

**Related:** BL-148 (the github twin).

---

## BL-154: tests.yml unit-list membership is convention, not enforcement — and CLAUDE.md claims otherwise

**Logged:** 2026-07-21 (sweep CR-8; validated: no lint greps tests.yml; current delta = 0)
**Category:** Debt / latent enforcement gap + doc drift
**Severity:** Low
**Status:** Open

`lint-tests-registered.sh` checks aggregator registration only; nothing structural enforces the tests.yml unit list, while CLAUDE.md says the lint enforces BOTH. Today's delta is zero (verified) — latent, not live.

**Fix shape:** fast-lane arm in lint-tests-registered.sh (every non-init-invoking `tests/test-*.sh` must appear in the tests.yml unit list) + true-up the CLAUDE.md sentence.

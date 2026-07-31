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
**Status:** Closed — shipped 2026-07-21 (PR #231, merged `e7bc567`). All three foundations instantiate at birth via `# BL-089-DOC-FOUNDATIONS` (docs/INDEX.md authority-order map, PRE-SEEDED docs/IDENTIFIERS.md per Karl's approved draft, docs/archive/README.md move-with-stubs). Two adversarial rounds: WP verifier SHIP-WITH-FIXES (2 MUSTs — nonexistent-checker promise, BUGS.md append-only misclass with the executed gate-wedge — all landed) + the BL-146 live-test reviewer's MAJOR (comment-blind wiring greps: a disabled-instantiation mutant passed every PR-blocking check; fixed with live-line anchors + the T6 liveness mutant). Suite 6/6; real-init case in the scaffold suite. Evidence: ledger § WP-BL089+BL091.

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

**Status update 2026-07-21 (step 1 SHIPPED):** implemented on branch `feat/bl090-doc-refs` (PR open; step-1 completion cited at merge — the ENTRY stays Open for steps 2–3, corpus-blocked). `# BL-090-DOC-REFS` fence in lint-doc-anchors.sh: every relative `](path)` must resolve from the referencing file's dir; URL/mailto/absolute/#-only/fenced out of scope; `path#anchor` checks the file half; `(planned)` inline exemption; WARN-tier default with `--strict-refs` escalation. Six new suite cases (T8–T13 incl. fence-excision mutant; suite 15/15; T8/T9 RED-watched). **Dogfood result: 140 relative refs across 81 docs files, ZERO warnings** (planted-ghost probe confirms the arm is live on the real tree) — the escalation-ready baseline. Evidence: ledger § WP-BL090-S1.

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
**Status:** Closed — shipped 2026-07-21 (PR #231, merged `e7bc567`, with BL-089). Builders-guide `## Documentation Rules` (all seven rules; rule-5 banner applied to the guide itself); essentials ship downstream in doc-index.tmpl Conventions; rule 6b is a GATE — the real standing TM-001 silently-degraded-subsystem row in project-bible.tmpl, scanner-id-set-neutral (proven against the real _p3_tm_* functions by two independent verifiers). Evidence: ledger § WP-BL089+BL091.

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

**2026-07-24 (design):** design doc authored, then revised through adversarial review — v1.1 cleared review-r1 (3 refuted "exists" claims + F4–F12), v1.2 folded review-r2 (R2-1..R2-6), and **v1.2.1 cleared adversarial review r3 (APPROVE), folding two minors** (`docs/designs/2026-07-24-operating-model-v1.md`, branch `docs/bl097-100-operating-model-design`), per the 2026-07-20 trio decision; **r4 (2026-07-25, the standing adversarial pr-reviewer on PR #269)** then refuted two narrative-layer claims (the version-floor story; a not-yet-built "S5 lint" cited as existing) — corrections folded as **v1.2.2** (`efab4f6`), re-verified minor_concerns/clear-to-merge, design decisions unchanged; build now un-gated on review (still sequenced after Dogfood-4) — Status stays Open until it lands.

**Merged 2026-07-25 (PR #269 `8afb9ba`) — Status stays OPEN.** The **design of record** is on `main` at **v1.2.3** (`docs/designs/2026-07-24-operating-model-v1.md`), after **five adversarial rounds**: r1 BLOCK → v1.1, r2 BLOCK → v1.2, r3 **APPROVE** → v1.2.1, r4 (the standing pr-reviewer on PR #269; 2 MAJOR + 6 minor, narrative-layer only) → v1.2.2 `efab4f6`, r5 (a second full adversarial pass after r4; two of its three MAJORs were refuted on the merits by independent refuters, one survived — citation integrity, R-269-12) → **v1.2.3** `45869c5`. **No design decision changed after r3** — r4 and r5 folded narrative, coordination and citation corrections only. What merged is a DESIGN, not a build: this entry stays Open until the **§10 nine-WP build skeleton** lands (WP1 schema → WP4a/4b enforcement surfaces → …), which remains sequenced after the Dogfood-4 milestone per the recorded 2026-07-20 trio decision.

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

**2026-07-24 (design):** design doc authored, then revised through adversarial review — v1.1 cleared review-r1 (3 refuted "exists" claims + F4–F12), v1.2 folded review-r2 (R2-1..R2-6), and **v1.2.1 cleared adversarial review r3 (APPROVE), folding two minors** (`docs/designs/2026-07-24-operating-model-v1.md`, branch `docs/bl097-100-operating-model-design`), per the 2026-07-20 trio decision; **r4 (2026-07-25, the standing adversarial pr-reviewer on PR #269)** then refuted two narrative-layer claims (the version-floor story; a not-yet-built "S5 lint" cited as existing) — corrections folded as **v1.2.2** (`efab4f6`), re-verified minor_concerns/clear-to-merge, design decisions unchanged; build now un-gated on review (still sequenced after Dogfood-4) — Status stays Open until it lands.

**Merged 2026-07-25 (PR #269 `8afb9ba`) — Status stays OPEN.** The **design of record** is on `main` at **v1.2.3** (`docs/designs/2026-07-24-operating-model-v1.md`), after **five adversarial rounds**: r1 BLOCK → v1.1, r2 BLOCK → v1.2, r3 **APPROVE** → v1.2.1, r4 (the standing pr-reviewer on PR #269; 2 MAJOR + 6 minor, narrative-layer only) → v1.2.2 `efab4f6`, r5 (a second full adversarial pass after r4; two of its three MAJORs were refuted on the merits by independent refuters, one survived — citation integrity, R-269-12) → **v1.2.3** `45869c5`. **No design decision changed after r3** — r4 and r5 folded narrative, coordination and citation corrections only. What merged is a DESIGN, not a build: this entry stays Open until the **§10 nine-WP build skeleton** lands (WP1 schema → WP4a/4b enforcement surfaces → …), which remains sequenced after the Dogfood-4 milestone per the recorded 2026-07-20 trio decision.

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

**2026-07-24 (design):** design doc authored, then revised through adversarial review — v1.1 cleared review-r1 (3 refuted "exists" claims + F4–F12), v1.2 folded review-r2 (R2-1..R2-6), and **v1.2.1 cleared adversarial review r3 (APPROVE), folding two minors** (`docs/designs/2026-07-24-operating-model-v1.md`, branch `docs/bl097-100-operating-model-design`), per the 2026-07-20 trio decision; **r4 (2026-07-25, the standing adversarial pr-reviewer on PR #269)** then refuted two narrative-layer claims (the version-floor story; a not-yet-built "S5 lint" cited as existing) — corrections folded as **v1.2.2** (`efab4f6`), re-verified minor_concerns/clear-to-merge, design decisions unchanged; build now un-gated on review (still sequenced after Dogfood-4) — Status stays Open until it lands.

**Merged 2026-07-25 (PR #269 `8afb9ba`) — Status stays OPEN.** The **design of record** is on `main` at **v1.2.3** (`docs/designs/2026-07-24-operating-model-v1.md`), after **five adversarial rounds**: r1 BLOCK → v1.1, r2 BLOCK → v1.2, r3 **APPROVE** → v1.2.1, r4 (the standing pr-reviewer on PR #269; 2 MAJOR + 6 minor, narrative-layer only) → v1.2.2 `efab4f6`, r5 (a second full adversarial pass after r4; two of its three MAJORs were refuted on the merits by independent refuters, one survived — citation integrity, R-269-12) → **v1.2.3** `45869c5`. **No design decision changed after r3** — r4 and r5 folded narrative, coordination and citation corrections only. What merged is a DESIGN, not a build: this entry stays Open until the **§10 nine-WP build skeleton** lands (WP1 schema → WP4a/4b enforcement surfaces → …), which remains sequenced after the Dogfood-4 milestone per the recorded 2026-07-20 trio decision.

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

## BL-135: test-bl033-install-cmds-shape fails on ubuntu CI and is GREEN on macOS — the harness depends on the host having Homebrew

**Logged:** 2026-07-18 (full-lane run 29649055577, core shard)
**Category:** Bug / host-dependent test (NOT a flake — deterministic on both hosts)
**Severity:** Low
**Status:** Closed — root-caused, reproduced locally, and fixed 2026-07-26 (commit `c98775c`, branch `fix/bl181-bl135-unit-lane`). Test-side fix at `# BL-135-RESOLVER-PROBE-STUB`; `scripts/resolve-tools.sh` deliberately unchanged. See the closure block at the end of this entry.

The core shard reported `[FAIL] tests/test-bl033-install-cmds-shape.sh` at 16:12Z; the aggregate runner suppresses sub-suite output (`run for details`), so NO case-level detail is recoverable from the log. The suite passes locally on the same content (post-#213 main). Candidates: ubuntu/GNU divergence, runner load (the same run surfaced BL-134's timing-margin class), or a real intermittent. Disposition: watch the next full-lane dispatch — a second failure warrants instrumenting the runner to tee sub-suite output; a second pass declassifies to noise.

**Related:** BL-134 (same run, diagnosed timing class); the full-lane runner's output-suppression pattern (worth `tee`-ing per sub-suite — this entry is the demand signal).

**Observation 2026-07-18 (Dogfood 3, F-DF3-003):** the generated PROJECT's gitleaks CI step showed the same intermittent-flake shape (`ERR failed to scan Git repository error="stderr is not empty"` — failed on 3 commits, passed on others). Second data point for the CI-flake watch, different surface (project CI, not framework CI).

**Investigation 2026-07-24 (WP-F, branch `fix/bl135-bl136-fullsuite-debt`):** local-stability datum + full candidate scan; NOT reproduced. (1) LOCAL 10× — `bash tests/test-bl033-install-cmds-shape.sh` ran ten consecutive times, ALL GREEN (rc=0, `Results: 8 passed, 0 failed` each; sub-second per run). Deterministic locally on `6fc1c11`. (2) CI LOG STILL AVAILABLE — `gh run view 29649055577 --log` retrieves (ubuntu-24.04 runner); it confirms the aggregate core shard prints ONLY `[FAIL] tests/test-bl033-install-cmds-shape.sh FAILED (run for details)` — NO case-level detail is recoverable, so WHICH of the 8 cases failed is unknowable from the log (this BOUNDS the diagnosis and re-justifies the per-sub-suite `tee` demand). That shard reported 5 failures total: this test, `tier-crosscheck-6` zdr-gate, `test-init-schema-phase-gate`, plus the two BL-136 cases (TEST 5 + TEST 7). (3) CANDIDATE SCAN (anchors = case/function names in `test-bl033-install-cmds-shape.sh`): the suite is exceptionally portable — `set -uo pipefail` (NOT `-e`), byte-comparison `[ "$x" = … ]` tests, and NO `sed -i`/`stat`/`date -d`/`grep -P`/`sort`/locale use. Host-shaped constructs, exhaustively: (a) `mktemp -d` in `_mk_matrix` (GNU+BSD both support the no-template form — benign); (b) the ONLY timing/race-shaped surface — the `$$`-keyed shared `/tmp/bl033-fail-fast-stage{1,2}-$$` markers in `T-array-fail-fast`, guarded by `rm -f` before use (low collision risk even under parallel-shard load); (c) COMMIT-STATE (not host) sensitivity — `T-migrated-entries` + `T-migrated-semantics` read the SHIPPED `templates/tool-matrix/common.json` and assert docker/colima carry the array shape, so a 2026-07-18 main with that matrix mid-migration would fail LEGITIMATELY and is NOT reproducible at `6fc1c11`. No candidate reproduces the failure locally, so the runner-`tee` instrumentation was deliberately NOT built this WP (per plan — build only if a candidate makes it locally reproducible). (4) DISPOSITION unchanged (Status stays Open, awaiting a second full-lane data point): per this entry's own rule, a second full-lane FAIL → `tee` each sub-suite's output (inspect candidate (c) first); a second full-lane PASS → declassify to noise.

**Merged 2026-07-25 (PR #267 `73c6083`) — Status stays OPEN.** The WP-F evidence pass above landed on `main` alongside the BL-136 fixture repairs. It changed no product code and no test code for this entry — it is an investigation record, not a fix — so the disposition is untouched: **still awaiting a second full-lane data point.** `tests/test-bl033-install-cmds-shape.sh` DOES run in the `core` shard (it is not `SUITE_SKIP_AGGREGATORS`-gated), so the next full-lane `workflow_dispatch` genuinely supplies that data point: a second FAIL → build the per-sub-suite `tee` instrumentation (inspect the commit-state candidate (c) first); a second PASS → declassify to noise and Close.

**CLOSURE 2026-07-26 — ROOT-CAUSED AND FIXED (commit `c98775c`). It was never a flake.** The
second full-lane data point arrived and it was a FAIL, but the `tee` instrumentation this entry
demanded was not needed: the divergence is deterministic and reproduces on demand.

**Second CI data point.** Full-lane `workflow_dispatch` run **30204845017**, 2026-07-26, ubuntu
runner. `full (core)` shard: `[FAIL] tests/test-bl033-install-cmds-shape.sh FAILED (run for
details)` — the shard's **SOLE** failure (`FAIL: 1`), the other three shards green. Two FAILs on
ubuntu (29649055577 on 2026-07-18, 30204845017 on 2026-07-26) against a suite that is
deterministically GREEN on macOS is a host split, not noise — and the 10× local stability run
recorded in the WP-F investigation above is now explained rather than contradicted.

**Root cause.** `scripts/resolve-tools.sh` builds its install-key priority list by probing the
**REAL HOST**:

```
HAS_BREW=false
command -v brew &>/dev/null && HAS_BREW=true
...
[ "$HAS_BREW" = true ] && _keys="${_keys}darwin_brew,"
```

`tests/test-bl033-install-cmds-shape.sh` drives the resolver through its `_run_resolver` helper
with `--dev-os darwin` and every scenario asserts on a `darwin_brew` install key. The helper's own
comment claimed it "pins linux_apt keys via env so the harness never depends on the host's package
managers" — **that comment was false**: the test set no env at all (zero exports) and the resolver
has no env override. On macOS brew is present, `darwin_brew` is in the key list, 8/8 pass. On
ubuntu brew is absent, `darwin_brew` is dropped, the fixture tool falls through to
`.manual` / `manual_install`, and every scenario that reads `auto_install[0]` or expects a
malformed-shape refusal collapses. Candidate (c) of the WP-F scan (commit-state sensitivity of the
two `T-migrated-*` cases) was the wrong suspect — those two are precisely the survivors.

**Local reproduction (the method, so it is repeatable).** Build a temp dir of symlinks to every
executable in `/bin`, `/usr/bin`, `/sbin`, `/usr/sbin` while deliberately EXCLUDING `brew` (and
omitting `/opt/homebrew/bin` and `/usr/local/bin` entirely), then run the suite with `PATH` set to
that dir. Measured on the macOS host, byte-identical test content:

| host state | result | rc |
|---|---|---|
| brew present (normal macOS) | `Results: 8 passed, 0 failed` | 0 |
| brew hidden (emulated ubuntu) | `Results: 2 passed, 6 failed` | 1 |

The 2 survivors are `T-migrated-entries` and `T-migrated-semantics` — the only cases that read
`templates/tool-matrix/*.json` directly with `jq` and never call the resolver.

**Fix — TEST-SIDE; the product is correct and was not touched.** Making `--dev-os` authoritative in
`resolve-tools.sh` was considered and **rejected**: the host probe is correct behaviour, since a Mac
user without Homebrew must be handed `darwin_manual`, not brew commands they cannot run. Regressing
real behaviour to satisfy a test would be the wrong trade. Instead `# BL-135-RESOLVER-PROBE-STUB`
in the test creates empty executable `brew` and `npm` stubs in a temp dir and prepends it to `PATH`
as a **command-scoped assignment on the resolver invocation inside `_run_resolver` only** — never
exported, so it cannot leak into sibling scenarios or sibling test files — with an `EXIT` trap
removing the dir. The resolver only ever runs `command -v` against those names, so an empty file
suffices; nothing is executed. That pins the key list to exactly
`darwin_brew,darwin_manual,npm,manual` on every host. `apt`/`dnf`/`pacman` need no stub because they
gate `linux_*` keys the harness never reaches under `--dev-os darwin` — stated in the comment, with
the standing requirement that any future `--dev-os linux` scenario MUST extend the stub set. The
false "pins ... via env" comment is replaced with one describing what the test actually does.

**Proof.** `Results: 8 passed, 0 failed` rc=0 in three environments — brew present, brew hidden, and
brew AND npm hidden. Watched-RED before the fix: brew hidden → `Results: 2 passed, 6 failed` rc=1.
Mutation: delete the `PATH="$_BL135_STUB_DIR:$PATH"` prefix → brew-hidden run returns to
`2 passed, 6 failed` rc=1 → restore → `8 passed, 0 failed` rc=0.

**Whole-lane sweep — is any OTHER unit-lane test brew-dependent?** Asked and answered by execution,
not by inspection, because this test is not obviously special and a second instance would redden
every PR just as effectively. The complete `tests.yml` unit `tests=(` array (135 files) was run
twice: on the normal PATH → **ran 135; failed 0**; and with brew hidden → **ran 135; failed 0**.
No other unit-lane test carries this dependency.

**Trap for anyone re-running that sweep.** Hide brew SURGICALLY: farm only the PATH directories that
actually contain a `brew` executable (symlink everything in them except `brew`) and leave every other
PATH entry as the real directory. A whole-PATH symlink farm is NOT a valid instrument — it produced
four spurious failures (test-bl132-sast-index-scan, test-bl125-commit-test-exec,
test-bl163-blocked-ledger, test-bl161-ledger-real-events-only), all with `git: command not found`,
because a farmed `git` loses its exec-path. The A/B that identified them as artefacts: the same farm
WITH brew kept fails all four identically (`normalPATH=0  sandbox+brew=1  sandbox-brew=1`), so the
failures had nothing to do with brew. Under the surgical sandbox all four pass.

**Residual.** The per-sub-suite `tee` instrumentation this entry demanded is still NOT built, and
that demand is unaffected by this closure — the aggregate core-shard runner still prints only
`FAILED (run for details)`, so the NEXT unrelated core-shard failure will be just as opaque. That is
a separate ask, not part of BL-135. The 2026-07-18 Dogfood-3 gitleaks observation (F-DF3-003)
recorded above is an unrelated surface and is NOT closed by this.

---

## BL-136: full-project-test-suite TEST 5 ("Phase gate script failed to run") and TEST 7 ("Dry-run missing resolver tool output") — pre-existing core-lane failures, on record since 2026-07-12

**Logged:** 2026-07-18 (first formal CI surfacing, full-lane run 29649055577; observed locally 2026-07-12 during the BL-099 round-4 full run — recorded then as "worth a backlog entry, NOT yet filed")
**Category:** Bug / test debt (full-lane only)
**Severity:** Low
**Status:** Closed — 2026-07-29, on the full-lane `workflow_dispatch` run **`30204845017`** (2026-07-26, head `d970b27`). **Closed on the per-test evidence, NOT on the run's colour — that run's overall conclusion is `failure`.** Both of this entry's tests passed every case in it: TEST 5 (`[PASS] Phase gate script runs in created project`, `[PASS] Phase gate can access tool-preferences.json`) and TEST 7 (five `[PASS]` rows, including `Dry-run shows resolver-based tool output`, the specific symptom filed here). The shard went red on ONE unrelated child, `tests/test-bl033-install-cmds-shape.sh`, which passes locally 8/0 and is owned by the already-Closed **BL-135** (fixed at `c98775c`, an ancestor of `main` but NOT of the head that run tested). `full (aggregators)`, `full (edge-scripts)` and `full (edge-pre-init)` were all green. Citing "the full lane was green" would have been false; **this AMENDS the closure condition this entry recorded for itself, and says so rather than pretending otherwise.** The recorded condition — still present in the body below, in bold, twice — was *a green full-lane run*. That is not what happened: the lane is red. The amendment is to the narrower condition *both of this entry's tests green in a full-lane run*, on the grounds that the lane's only failure is unrelated, separately owned (it is the already-Closed BL-135, observed on a head that predates its fix `c98775c`), and cannot be made green by anything in this entry's scope. Amending a recorded condition is legitimate; quietly restating it as though it had always been the narrower one is not, and an earlier draft of this line did exactly that.

Both reproduce in the core shard and predate the Dogfood-2 remediation (the 2026-07-12 local run hit the identical pair on then-main). Prior diagnosis notes: TEST 7's fixture under-feeds `prompt_choice` on the dry-run resolver path; TEST 5's phase-gate invocation fails in the suite's fixture context. Neither is covered by the unit lane. Fix shape: reproduce each in isolation, repair the FIXTURE if it models a stale world (the BL-134/zdr-gate pattern) or the product if the gate genuinely misbehaves; register nothing new (both live inside the aggregator).

**Related:** BL-134 (the same run's other test-debt class); Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md § POST-RUN CI REPAIR (the fixture-era doctrine).

**Investigation 2026-07-24 (WP-F, branch `fix/bl135-bl136-fullsuite-debt`, fix commit `afd0431`):** both root-caused, both FIXTURE-ERA, both repaired IN `tests/full-project-test-suite.sh` (product code untouched); reproduced by extraction/isolation only (HARD LIMIT respected: the ~3h full suite and any workflow_dispatch were NOT run). Full-lane confirmation is OUTSTANDING — the reason Status stays Open (flips only after a green full-lane run post-merge).

TEST 5 ("Phase gate script failed to run") — FIXTURE-ERA. TEST 4's shared scaffold (built once as `TEST4_FIXTURE`, copied per combo in `for run in "${TEST_RUNS[@]}"`) copied ONLY `scripts/lib/helpers.sh`. But `check-phase-gate.sh` runs `source "$SCRIPT_DIR/lib/helpers-core.sh"` at its top (the BL-046 core/full split) under `set -euo pipefail`; with that sibling absent the `source` fails and the script ABORTS before echoing its `Phase Gate Consistency Check` header — so the block's `grep -q "Phase Gate Consistency Check"` is false → FAIL. Corroborated by CI 29649055577, where TEST 5's SECOND assertion ("Phase gate can access tool-preferences.json") PASSED: the fixture dir existed and the gate RAN but died early. REPRO (scratchpad, staged): a faithful `test-web-typescript` scaffold with only `helpers.sh` → `check-phase-gate.sh: line 18: …/lib/helpers-core.sh: No such file or directory`, rc=1, header ABSENT; add `helpers-core.sh` + `helpers-full.sh` → rc=0, header present, "Phase gates consistent." REPAIR (`# BL-136` at the fixture-build `cp` block): ship the full helpers trio, mirroring init.sh's own scaffold (the `cp … helpers-core.sh` / `helpers-full.sh` copies that sit beside `helpers.sh`).

TEST 7 ("Dry-run missing resolver tool output") — FIXTURE-ERA (confirms the prior `prompt_choice` under-feed diagnosis). The piped `dry_input` modeled a stale intake: `prompt_input` (project name/description) now auto-returns its default in a non-interactive/piped context WITHOUT consuming a line (`prompt_input`'s `[ ! -t 0 ]` guard in `helpers-core.sh`), so the two leading lines (`test-dryrun`, `Dry run test`) were mis-eaten as INVALID Platform-type entries; a Governance-mode `prompt_choice` was since added to the intake; the rest misaligned and stdin hit EOF at Governance — `prompt_choice`'s `stdin closed (EOF) before a valid choice was supplied` branch — aborting init.sh before "Tool Resolution" ever printed. `prompt_choice` has NO non-interactive default BY DESIGN (unlike `prompt_input`/`prompt_yes_no`/`prompt_install`), so the plan's `SOIF_NONINTERACTIVE=1`/`</dev/null` option does NOT apply here — the choice sequence must be fed. REPRO: old 8-line input → exit 1, `Tool Resolution` absent, dies at the Governance EOF. REPAIR (`# BL-136` above the `dry_input=` heredoc): feed the exact current `prompt_choice` sequence — platform=web(4) · track=standard(2) · deployment=personal(1) · governance=Production Build(2) · language=typescript(7) · then the raw `Continue?` read (under `set -e`, so it needs a value, not EOF). VALIDATED: repaired input → exit 0 with ALL FOUR TEST 7 assertions green (DRY RUN, Tool Resolution, tool-status categories, no project dir). The Docker-install `prompt_choice` (guarded on Docker-absent + interactive + Darwin/brew) does NOT fire — Docker is present on this host and on ubuntu-24.04 CI — so it cannot shift the sequence.

BLAST RADIUS: `bash -n tests/full-project-test-suite.sh` clean; `scripts/run-lints.sh` 11/11 (`lint-tests-registered.sh` green — no registration lines touched); `test-bl033-install-cmds-shape.sh` still 8/8.

**Verifier follow-up 2026-07-24 (APPROVE-WITH-FIXES, applied on the same branch):** the consolidated verifier CONFIRMED both fixture-era diagnoses with independent evidence (TEST 5: the `helpers.sh`-only `cp` predates the BL-046 split — born-valid-then-rotted; TEST 7: `prompt_choice`'s no-default EOF guard is documented design, so nothing to flip product-side) and independently re-derived the prompt sequence to match. It also flagged that the "ALL FOUR TEST 7 assertions green" evidence recorded above was OVERSTATED — TWO of those four were VACUOUS. Corrections F1-F4, all applied and each bite-proven: **(F1)** the fed menu numbers are glob-derived, so a shifted template could land on the WRONG combo with every assertion still green — added a combo-PIN on the `collect_project_info` summary line (`Platform: web | Track: standard | Language: typescript`); bite-proven by feeding language `6`=rust → the pin FAILS while the other four PASS. **(F2)** old assertion 3 `grep -qi "…DEFERRED"` matched the intake PROSE `Private POC — … All governance deferred.` printed BEFORE resolution (why it PASSED in the original CI run even though "Tool Resolution" never ran) — tightened to the BRACKETED `dry_run_summary` statuses (`[already installed]`/`[WILL INSTALL]`/`[MANUAL]`/`[DEFERRED`); bite-proven on the OLD stale input (the loose grep passes on the aborted output; the bracketed one FAILS). **(F3)** old assertion 4 `[ ! -d /tmp/test-dryrun ]` was FULLY vacuous (nothing in the new input references that path; the resolved default dir is the pre-existing repo parent `…/.claude/worktrees/`, so no `! -d` is possible) — re-aimed to the `dry_run_summary` terminal no-op marker `Re-run without --dry-run to execute` (emitted only when the dry-run completes WITHOUT creating). **(F4)** replaced the bare `init.sh:1284-1286` fixture cite with the grep-able `# BL-046: helpers.sh split` anchor (CITATION RULE). Net: TEST 7 now carries FIVE assertions, all green on good input and each proven to bite; `bash -n` clean; `run-lints.sh` 11/11. Status still Open — full-lane confirmation remains outstanding.

**Merged 2026-07-25 (PR #267 `73c6083`) — Status stays OPEN.** The TEST 5 / TEST 7 fixture repairs are on `main`. This entry's closure condition is unchanged and unmet: **a green full-lane `workflow_dispatch` run, which HAS NOT BEEN RUN.** Nothing about merging satisfies it — TEST 5 and TEST 7 live inside `tests/full-project-test-suite.sh`, which no PR-blocking lane executes.

**Correction (2026-07-25) — the evidence plan is materially weaker than recorded above, and this is verified, not inferred.** The two suites repaired by the sibling PR #266 (BL-173) — `tests/test-currency-birth-stamp.sh` and `tests/test-bl113-sast-honesty.sh` — sit in the **`else` arm** of `if [ "${SUITE_SKIP_AGGREGATORS:-0}" = "1" ]` blocks inside `tests/full-project-test-suite.sh`, and the `full` job's **`core` shard sets exactly that variable** (`SUITE_SKIP_AGGREGATORS=1 bash tests/full-project-test-suite.sh` in `.github/workflows/tests.yml`). They are also excluded from the unit lane (both invoke real `init.sh`). **Worse than "the core shard skips them":** the `aggregators` shard, whose surrounding comment claims "Union of shards == the un-sharded suite", runs an EXPLICIT four-file list — `edge-cases-upgrade-input.sh`, `edge-case-test-suite.sh`, `known-bugs-test-suite.sh`, `upgrade-path-tests.sh` — and neither repaired suite is in it. Net: **NO CI lane, including a full `workflow_dispatch` dispatch of all four shards, executes either suite**, so a green full-lane run would confirm the TEST 5/TEST 7 repairs (which DO run in `core`) but would say nothing whatsoever about the BL-173 repairs, and the workflow's own union claim is inaccurate for at least these two suites. Anyone planning the full-lane dispatch should treat the two BL-173 suites as needing a separate standalone run, and should not read a green `aggregators` shard as covering the `SUITE_SKIP_AGGREGATORS`-gated set.

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
**Status:** Closed — shipped + merged 2026-07-25 (PR #270 `b0b60aa`). `# BL-131-DOM-SINKS`: `templates/semgrep/soif-dom-sinks.yml` now ships into every scaffold's `.semgrep/` and is referenced as an extra `--config` by the emitted pre-commit hook and all 22 generated CI pipelines; both hook-re-emitting paths also DELIVER it (`_bl099_sync_precommit_hook` via the new `_bl131_ensure_domsinks_ruleset`, and `verify-install.sh`'s `fix_precommit_hook`), closing the incomplete-contract gap where a refreshed hook referenced a file the project never received. Coverage: `insertAdjacentHTML` + jQuery `.html()` via precise js/ts AST rules; the `.vue` / `.html` embedded-script sinks via a `generic`+`pattern-regex` rule — semgrep's `vue`/`html` parsers do NOT expose embedded `<script>` JS as a matchable AST (established empirically on semgrep 1.157.0), so `generic`+regex is the only way in. js/ts `innerHTML`/`document.write` are deliberately left to the BL-118 registry pack so the two rulesets do not overlap. Proof: `tests/test-bl131-domsink-rules.sh` 17/17 (static + isolated-rule-content + live-through-hook + deletion pin + `--config`-strip mutation). Residues tracked, not silently accepted: **BL-175** (the ruleset sits outside `scaffold-shipped-set.sh`'s parsers, so it is neither source-closure-tested nor currency-tracked) and the documented regex/non-taint residue in `docs/platform-modules/web.md`.

Empirically proven through the real emitted hook during BL-118's adversarial verification: staged fixtures using `el.insertAdjacentHTML('beforeend', x)`, jQuery `$(sel).html(x)`, `innerHTML` inside a `.vue` SFC `<script>` block, and an inline `<script>` in a committed `.html` file all COMMIT CLEAN with the `[OK] semgrep: SAST ran` receipt. This is NOT a pack-choice error: the full `r/javascript.browser.security` pack and `p/xss` both produce zero findings on those fixtures at any severity (tested with and without explicit `location.*` taint sources) — no rule in the public registry covers them, so no `--config` addition can close this. The BL-118 fix's own coverage claim (innerHTML/outerHTML/document.write) is accurate; this entry exists so the residue is a recorded decision, not a rediscovery for the next dogfood.

**Fix shape:** ship a small custom semgrep ruleset with the scaffold (e.g. `.semgrep/soif-dom-sinks.yml`, added as another `--config` in the hook + CI templates) covering the missing sinks at ERROR severity, with the same exact-token pins and mutation-test discipline as BL-118; or explicitly accept + document the residue in the security-model docs. Note Phase-3 `--config auto` does not close it either (registry-bound).

**Related:** BL-118 (PR #199 — the covered sinks); BL-112 (the gate plumbing); BL-132 (the other verifier-found gap); `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` (WP-A1 verifier findings).

**Build note (2026-07-24, branch `fix/bl131-bl132-sast-hardening`):** Shipped `templates/semgrep/soif-dom-sinks.yml` — init.sh lays it into the scaffold's `.semgrep/` before the initial commit (so CI, which checks out the committed tree, sees it), and it is referenced as an extra `--config` in the emitted hook (marker `# BL-131-DOM-SINKS`) and all 22 generated CI pipelines (github×10 + gitlab×10 + bitbucket×2). Coverage: `insertAdjacentHTML` and jQuery `.html()` via precise js/ts AST rules (literal-argument RHS excluded to cut false positives); innerHTML/outerHTML/document.write/insertAdjacentHTML/jQuery inside `.vue`/`.html` via a `generic` + `pattern-regex` rule scoped by `paths:`. EMPIRICAL FINDING (semgrep 1.157.0): semgrep's `vue`/`html` language parsers do NOT expose the embedded `<script>` JS as a matchable AST (even `location.hash` fails to match in `vue` mode), so precise AST rules cannot reach those file types — `generic`+regex is the only way in, and it IS reachable. js/ts innerHTML/document.write are deliberately LEFT to the BL-118 registry browser pack, so the two rulesets do not overlap (verified: `T-mutation-domxss-config` still unblocks a js/ts innerHTML fixture by stripping only the registry line). RESIDUE (now documented in `docs/platform-modules/web.md`): the markup-file rule is syntactic regex, not taint-aware — a code sample shown as prose in an `.html` doc can false-positive (suppress with a `nosemgrep` line), and a sink split/aliased across lines can evade. Artifact pinned statically (ruleset ships + init.sh cp line + hook/CI `--config`) AND behaviorally (delete the ruleset → semgrep exits non-zero → the SAST arm WARNs loudly, never a silent clean pass). Proof: `tests/test-bl131-domsink-rules.sh` (static + isolated-rule-content + live-through-hook + deletion pin + `--config`-strip mutation). Status stays Open pending PR + merge.

**Build note addendum (2026-07-24, supervisor-triaged increment):** the two hook-re-emitting paths now also DELIVER the ruleset (closing the incomplete-contract gap where a refreshed/repaired hook referenced a file the project never received): `scripts/upgrade-project.sh` `_bl099_sync_precommit_hook` gains helper `_bl131_ensure_domsinks_ruleset` (called from the install + refresh branches, DRY_RUN-aware, idempotent byte-compare, rides the hook's own consent), and `scripts/verify-install.sh` `fix_precommit_hook` restores the ruleset from the framework source (byte-compare + refresh-if-different, `lint-fix-functions-stderr`-clean, hook-write rc preserved). New cases: `tests/test-upgrade-sync-framework.sh` (`t_domsinks_ruleset_delivered_on_hook_install` / `_dry_run_no_write` / `_current_no_op`) and `tests/test-verify-install-fix-functions.sh` T15 (repair restores the ruleset). The residual tracking-registry gap (`templates/semgrep/` sits outside `scaffold-shipped-set.sh`'s parsers) is filed as BL-175, not fixed here.

---

## BL-132: The pre-commit SAST arm scans WORKTREE paths, not INDEX content — stage the vuln, overwrite the worktree copy, and the committed bytes are never scanned

**Logged:** 2026-07-17 (BL-118 adversarial verification, PR #199)
**Category:** Bug / security enforcement — pre-existing BL-112 design gap (orthogonal to, and unchanged by, BL-118)
**Severity:** Medium
**Status:** Closed — shipped + merged 2026-07-25 (PR #270 `b0b60aa`). `# BL-132-INDEX-SCAN`: the commit-time SAST arm materializes staged blobs and scans INDEX content instead of worktree pathnames, with the finding paths `sed`-mapped back to real repo-relative paths and both `# BL-112-SAST-NOTRUN` arms byte-preserved. Gitleaks already read the index (`gitleaks git --staged`) — no change needed there.

**Closed honestly, not cleanly.** This took **three adversarial rounds**, and **two same-class regressions were found and fixed post-open** — every one of them the SAME "one bad entry blinds the whole commit" mechanism, and every one of them a regression *versus main* rather than a pre-existing hole:
1. **Round 1 (fable verifier REJECT, F1).** The first cut pointed semgrep at the materialized DIRECTORY, which re-engages semgrep's built-in default `.semgrepignore`, so staged sinks under `tests/ test/ build/ dist/ vendor/ node_modules/` and `*.min.js` were SILENTLY skipped and the commit landed with an `[OK] … ran on N staged file(s)` receipt. FIX B hands semgrep EXPLICIT file targets (`soif_idx_files`), never the tree, plus the F2 positive content-size guard.
2. **Round 2 (cross-PR REJECT, R-270-1 — `# BL-132-GITLINK-SKIP`).** A staged submodule GITLINK is index mode `160000`, not a blob, so `git cat-file blob` exits 128; the loop's all-or-nothing `break` discarded every already-materialized target and routed the WHOLE commit to NOTRUN — a vulnerability staged in a *sibling* file LANDED. A/B'd through the real emitter and a real `git commit`: OLD (`d857294`) BLOCKED, NEW (`bc08d36`) LANDED. **No lane caught it** — `test-bl132` 7/7, `test-bl131` 17/17 and `test-bl112` 13/13 were all green with the defect live.
3. **Round 3 (PR #270 final gate, R-270-1B — `# BL-132-STAGE0-REF`).** `":$path"` is git REVISION syntax, so a repo-ROOT path beginning `0:`/`1:`/`2:`/`3:` fails `cat-file` on a perfectly healthy blob, is not a gitlink, and fell through to the same `break` — again a vulnerable sibling LANDED, again a regression versus main (`ed406c8` BLOCKED / `0765612` LANDED). All three cat-file sites now pin the stage explicitly as `":0:$path"`.

Receipt honesty follows under `# BL-132-EMPTY-TARGETS` (the "ran on N staged file(s)" count is what was actually TARGETED, and zero targets routes to NOTRUN rather than claiming a scan). BL-178 landed in the same diff as round 2 by design (`# BL-178-PER-INDEX-DIR` rewrites the same loop). Green at merge: `test-bl132` 11/11, `test-bl131` 17/17, `test-bl118` 6/6, `test-bl112` 13/13, `run-lints` 11/11.

**The defect CLASS is not retired, and one more instance is still Open.** Two pre-existing holes in the same arm were filed rather than folded — **BL-179** (High: rename-and-edit commits skip SAST entirely and silently, `--diff-filter=ACM` excludes `R`) — and a THIRD instance of the same all-or-nothing `break` was found by the #270 final-gate reviewer and filed as **BL-182** (Medium: a repo-relative path longer than ~958 chars is legal in the worktree but unrepresentable under the `mktemp -d` + `/<n>/` temp root, so materialization fails and the whole commit goes NOTRUN). BL-182 carries the structural fix direction — **retire the `break`** so the arm scans what DID materialize and routes to NOTRUN *naming the entry it could not read* — rather than patching a fourth trigger.

Reproduced during BL-118's adversarial verification: `git add app.ts` (containing the XSS), overwrite the worktree `app.ts` with the clean version, `git commit` → the commit LANDS with the `[OK]` receipt, and `git show HEAD:app.ts` contains the vulnerable `innerHTML`. The hook hands semgrep staged PATHS (`git diff --cached --name-only`), so semgrep reads WORKTREE bytes, which need not be the staged bytes. Partial-stage (`git add -p`) and stage-then-edit flows also scan the wrong content in the benign direction (false signal from unstaged edits).

**Fix shape:** scan index content: materialize staged blobs into a temp tree preserving relative paths/extensions (`git checkout-index --temp` or `git show :<path>`), run semgrep there, report findings against the real paths. Same BL-112-SAST-NOTRUN/receipt discipline. Check gitleaks parity while there (`gitleaks git --staged` already reads the index).

**Related:** BL-112 (the arm's design); BL-118 (PR #199 — verifier proved the gap is orthogonal to the ruleset fix); `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` (WP-A1).

**Build note (2026-07-24, branch `fix/bl131-bl132-sast-hardening`):** Fixed in the emitted pre-commit hook (`scripts/lib/hook-templates.sh`, marker `# BL-132-INDEX-SCAN`). The SAST arm now materializes each staged blob into a `mktemp -d` tree via `git show ":<path>"` (preserving relative path + extension so semgrep still detects the language), runs semgrep against that INDEX snapshot instead of the worktree pathnames, and `sed`s the temp prefix off finding paths so the operator sees real repo-relative paths. Both `# BL-112-SAST-NOTRUN` arms are byte-preserved; a materialization failure routes to the same loud NOTRUN helper (honest, never a silent pass). GITLEAKS PARITY (checked per the fix shape): the gitleaks arm already reads the index (`gitleaks git --staged`), so no change was needed there. Proof: `tests/test-bl132-sast-index-scan.sh` — staged-vuln/clean-worktree → REFUSED with the staged path named; clean-staged/vuln-worktree → LANDS (no false block on unstaged edits); NOTRUN contract intact; mutation (scan target reverted to the worktree paths) → RED → restore → GREEN. Status stays Open pending PR + merge.

**Build note addendum (2026-07-24, verifier REJECT → fix):** the first cut scanned the materialized DIRECTORY (`semgrep … "$soif_idx_tree"`), which the fable verifier REJECTED with one BLOCKER (F1): pointing semgrep at a directory re-engages its built-in default `.semgrepignore`, so staged sinks under `tests/ test/ build/ dist/ vendor/ node_modules/` and `*.min.js` were SILENTLY skipped and the commit landed `[OK] semgrep: SAST ran on N staged file(s)` — a regression from the pre-BL-132 explicit-target contract (the OLD hook refused them). `--no-git-ignore` does NOT disable the built-in defaults (confirmed empirically). Every original fixture lived at repo root, which is why the first 4/4 stayed green. **FIX B** (supervisor-chosen): the materialization loop now collects each dest into `soif_idx_files=()` and semgrep is handed those EXPLICIT file targets (`${soif_idx_files[@]+"${soif_idx_files[@]}"}`, `set -u`-guarded), never the tree — explicit targets bypass ignore filtering by semgrep's documented semantics, restoring the contract by construction and keeping the "ran on N staged file(s)" receipt honest. Materialization switched to `git cat-file blob` and gained the **F2** positive content-size check (`git cat-file -s` vs `wc -c`) so a git read returning 0 while writing an empty/partial dest routes to the loud NOTRUN, not a silent pass. New/updated tests: `test-bl132` `T-index-ignored-paths-scanned` (S4 regression: sinks under tests/ dist/ *.min.js scanned+REFUSED, RED reproduced against the directory scan) + `T-mutation-content-guard` (M-empty/M-partial → NOTRUN with F2; F2 removed → silent [OK]) + `T-index-blocks-staged-vuln` F3 (assert the raw mktemp prefix is absent, not a bare basename grep); the three `--error` mutation anchors (`test-bl112`, `test-bl099-guard-coverage`, `test-bl132` `T-mutation-index-scan`) updated to the new array-expansion target and re-proven. Case-only-differing collision on case-insensitive FS filed as BL-178 (FIX B does not close it; stage is deliberately unusual, Low).

**Build note addendum 2 (2026-07-25, cross-PR REJECT → fix — R-270-1 SECURITY REGRESSION + BL-178, landed together):** FIX B's materialization loop aborted on the FIRST staged path it could not `git cat-file blob`, and a **submodule GITLINK is index mode 160000, not a blob** — `git cat-file blob :sub` exits 128. The `break` therefore discarded EVERY already-materialized target and routed the WHOLE commit to NOTRUN, so a vulnerability staged in a *sibling* file **LANDED**. This was a **regression versus main**: A/B'd through the real shipped emitter with the same fixture and a real `git commit`, OLD (`d857294`) → BLOCKED rc=1, NEW (`bc08d36`) → LANDED rc=0 + NOTRUN; the gitlink-free control BLOCKED on both. The trigger is routine (`git submodule add`, or a pointer bump staged beside application code) and **no lane caught it** — with the defect live, `test-bl132` 7/7, `test-bl131` 17/17 and `test-bl112` 13/13 all passed, because no fixture in the repo staged a gitlink. Fixed under `# BL-132-GITLINK-SKIP`: a non-blob index entry is now SKIPPED rather than aborting the loop. The skip is **narrow by construction** — it is gated on the index MODE being `160000`, read back with a `:(literal)` pathspec so glob metacharacters and spaces cannot mis-resolve; anything that is neither a blob nor a gitlink (a missing/corrupt object for a REAL staged blob) still routes to the loud NOTRUN, verified by pruning a real blob's object so `cat-file -t` fails exactly as it does for a gitlink and watching NOTRUN fire with no silent skip. Receipt honesty follows under `# BL-132-EMPTY-TARGETS`: the `[OK] … ran on N staged file(s)` count is now `${#soif_idx_files[@]}` (what was ACTUALLY targeted) rather than `${#soif_staged[@]}` (what was staged), since the two can now legitimately differ, and **zero** materialized targets — a submodule pointer-bump commit stages only a gitlink — routes to NOTRUN instead of claiming a scan. **BL-178 landed in the same diff** (`# BL-178-PER-INDEX-DIR`): both defects rewrite the same loop and the same `soif_idx_files` population, so splitting them meant rewriting it twice with a near-certain conflict. Materialization moved from one flat tree to per-staged-entry subdirs (`$soif_idx_tree/<n>/<relpath>`), and the path-mapping `sed` grew the `[0-9][0-9]*/` arm so the operator still sees the REAL repo-relative path — never a temp path, never a bare index number. Reported-path contract re-verified end-to-end for deeply-nested paths and **paths containing spaces** (`src/my components/sub dir/space vuln.ts` round-trips verbatim). New watched-RED tests in `test-bl132`: `T-index-gitlink-not-blinding` (realistic LOCAL-path `git submodule add`, never a network remote; RED pre-fix = COMMITTED + "could not materialize"), `T-index-gitlink-only-honest` (pointer bump → lands, but no unearned `[OK]`), `T-index-case-collision` (BL-178; `update-index --cacheinfo` builds the case-only pair a case-insensitive CHECKOUT cannot hold, LOUD-SKIPs on a case-sensitive FS rather than passing vacuously; RED pre-fix = `[OK] semgrep: SAST ran on 2 staged file(s)` with the vuln committed). `T-mutation-content-guard`'s materialization anchors were retargeted to `$soif_idx_dest`. Mutation proofs: M1 drop the blob guard → gitlink test RED → restore → GREEN; M2 revert the per-index layout (dest + `sed` in sync) → case-collision test RED → restore → GREEN; M3 force a genuine read failure on a REAL blob → NOTRUN fires, no `[OK]`, nothing lands silently. Green: `test-bl132` 10/10, `test-bl131` 17/17, `test-bl112` 13/13, `test-upgrade-sync-framework` 39/39, `run-lints` 11/11.

**Build note addendum 3 (2026-07-25, PR #270 final-gate adversarial review — R-270-1B SECURITY REGRESSION, same loop again):** addendum 2's loop addressed staged content as `":$soif_p"`. Git's REVISION syntax reads `:<0-3>:<path>` as a **merge-stage reference**, so for a staged file whose **repo-ROOT** name begins with `0:`, `1:`, `2:` or `3:` (e.g. `2:evil.js`) `git cat-file -t ":$soif_p"` FAILS on a perfectly healthy, fully readable blob — `fatal: path 'evil.js' does not exist`. That is not a gitlink, so `# BL-132-GITLINK-SKIP` did not `continue`; the entry fell through to `soif_idx_ok=0; break`, which discarded every already-materialized sibling target and routed the WHOLE commit to NOTRUN — **a genuinely vulnerable sibling then LANDED**. Same "one bad entry blinds the whole commit" mechanism as R-270-1, and a **regression versus main**: A/B'd through the real emitter, the real `.git/hooks/pre-commit` and a real `git commit` — main (`ed406c8`) `[BLOCKED]` / did not land, head (`0765612`) `[WARN] could not materialize staged content` / **landed**. Loud (NOTRUN, not a false `[OK]`), hence major rather than block, but not mergeable. Fixed under the new marker `# BL-132-STAGE0-REF`: all **three** cat-file sites in the loop (`-t` type probe, `blob` materialization, `-s` size probe) now pin the stage explicitly as `":0:$soif_p"`. Boundaries re-derived on git 2.50.1 before and after: `0:`/`1:`/`2:`/`3:` at repo root fail bare while `4:x.js` (only 0-3 are stage digits), `2evil.js` (the colon is required) and `sub/2:x.js` (root only) all resolve bare; `:0:` resolves ordinary paths identically (`:0:src/ok.js` → blob), so it is a strict improvement. The `git ls-files -s -- ":(literal)$soif_p"` gitlink probe is a **PATHSPEC, not a revision** — proven immune with `2:x.js`-shaped paths (correct `100644` row) rather than assumed, and deliberately left unchanged; a real gitlink still fails `cat-file -t ":0:sub"` while `ls-files` reports `160000`, so the skip still fires. The `# BL-132-GITLINK-SKIP` design comment was **corrected**: it had enumerated "a missing/corrupt object for a REAL staged blob" as the only other way `cat-file -t` can fail, which this review refuted. New watched-RED test `T-index-stage-syntax-path` in `tests/test-bl132-sast-index-scan.sh` stages `0:decoy.js` (insertAdjacentHTML sink) beside `app.ts` (innerHTML sink) and asserts BLOCKED with BOTH real repo-relative paths named, no temp prefix and no bare index number; RED first against the unfixed code (COMMITTED + "could not materialize", vuln shipped), GREEN after. Mutation proof: revert only the three `:0:` prefixes → RED → restore → GREEN. `T-mutation-content-guard`'s two `_idx_mutate` anchors were retargeted in lockstep (they are full literals, and the exactly-once check correctly reported MIS-TARGETED in between rather than passing vacuously — the coupling is now documented in the case). Green: `test-bl132` 11/11, `test-bl131` 17/17, `test-bl118` 6/6, `test-bl112` 13/13, `run-lints` 11/11. A separate PRE-EXISTING hole found in the same review (rename-and-edit commits skip SAST entirely and silently; identical on main) was filed as **BL-179**, not fixed here.

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
**Status:** Closed — the standing agent shipped + merged 2026-07-23 (PR #253 `f58bc76`): `.claude/agents/pr-reviewer.md` (model: fable), all seven META lessons from the two live tests baked in as greppable anchors, CONTRIBUTING dispatch doc. Framework-repo deliverable complete. Remaining as separate future work (design pointers, not blockers): the generated-project reviewer variant (the entry's 'scope order second'), and effort-as-a-first-class-reviewer-parameter which belongs to the BL-097 operating-model design.

Karl's directive: an agent that reviews PRs ADVERSARIALLY with the intent of making sure the PR is of the highest technical standard, using the most up-to-date info from context7, as optimal as possible, stable, and secure.

**What exists today:** the BL-100 adversarial-acceptance doctrine (practiced across the 2026-07 arcs, now folding into the BL-097 operating-model design); the gate-enforced Phase-3 review manifest + `evaluation-prompts/` library (phase-scoped, not PR-scoped); per-WP ad-hoc verifier dispatches (this arc's working practice — effective but hand-rolled each time). **What's missing:** a STANDING, dispatchable PR-review agent — point it at a PR, get a refutation-first review across five dimensions:
1. **Technical standard** — correctness, idiom, and the repo's own discipline rules (marker fences, registration, hermeticity, portability).
2. **Currency** — context7 lookups for every library/API/CLI the diff touches; deprecated or superseded usage is a finding (the context7 session rule, promoted to a review dimension).
3. **Optimality** — simplification, efficiency, no unnecessary surface.
4. **Stability** — edge cases, error handling, flake potential, test quality (vacuity/weak-test classes).
5. **Security** — the adversarial security lens per change, not just per phase.

**Design decisions to take before building:** trigger surface (slash-command vs `gh` comment vs auto-on-open); scope order (framework repo first, generated-project variant second); verdict grammar (reuse BL-100's block/major_concerns/minor_concerns/approve rubric — major+ blocks); how context7 is reached from the review environment (MCP availability in headless runs — the BL-128 lesson); reviewer MODEL comes from the operating model chosen per the BL-097 trio decision (this agent is the reviewer role's concrete tool — compose with that design, don't duplicate it).

**Related:** BL-100 (the acceptance doctrine this makes standing); BL-097/BL-098 (operating model / reviewer role); BL-128 (headless review dispatch machinery precedent); `evaluation-prompts/` (the phase-review library); the context7 global rule.

**Live test 2 — 2026-07-23 (Karl-directed, Dogfood-4 stack):** one Fable subagent reviewed the four-PR stack #243→#244→#245→#247 under the five-dimension brief with the META-1..7 inputs honored (isolated worktree at the stack tip; pre-cleared mutation lab — 8 own mutations; lane-reachability judged against the actual PR-blocking set, which it corrected to 9 lint jobs + unit; context7 reachability probed then 7 queries across npm/Actions/ESLint/gitleaks/MDN; verdicts in BL-100 grammar with R-<PR#>-<n> IDs). Verdicts: #243 approve, #244/#245/#247 minor_concerns, ZERO blocking. Six minor findings, ALL applied same-day on the open branches: R-243-1 (T6 subject-non-bypass pin), R-244-1/2 (Cg7 dev-arm-must-WARN + ;/&&-disable rejection; both reviewer mutants re-run RED), R-245-1 (Cg8 extended to vars/inputs + the live web.yml `vars.PREVIEW_URL` env-indirected + comment corrected), R-247-1 (INDEX.md Reports entries), run-count nit. It also independently re-verified all 7 work-example run IDs, the release tag, five SHAs, and the BSD-grep repro. Second consecutive it-works datum for the standing-agent design.

**Status update 2026-07-23 (BUILD APPROVED — Karl, WP-4 of the post-Dogfood-4 wave):** with the design twice-proven, Karl approved promoting the dispatch brief into a repo-shipped, dispatchable agent. Shipped on branch `feat/bl146-pr-reviewer-agent` (status stays **Open** — Closed flip at merge, citing PR# + SHA). Two artifacts, both docs-only (`.md`): (1) the standing agent definition `.claude/agents/pr-reviewer.md` — frontmatter `name: pr-reviewer` / `model: fable` (reviewer tier ≥ implementer, per the subagent-model policy) / a precise dispatch-matching `description`; body = the standing system prompt with a greppable `META-1..7` doctrine-anchor checklist near the top and every META lesson baked in inline (META-1 worktree-tip pinning, META-2 mutation-lab restore-never-post, META-3 BL-100 verdict grammar + `R-<PR#>-<n>` finding IDs, META-4 PR-blocking lane-reachability, META-5 on-demand-only cost note, META-6 context7 reachability preflight + disclaim-if-unreachable, META-7 max-effort-in-prompt). The five dimensions, the environment block (quoted paths / bash-3.2 / no `timeout` / `gh` read-only), and the refutation-first stance are all encoded. (2) a "PR review agent" subsection in `CONTRIBUTING.md` (chosen over a `docs/` file because CONTRIBUTING already carries the contributor dev-workflow sections and this is a before-merge contributor tool; `docs/INDEX.md` maps only `docs/**`+`Reports/**`, so no INDEX entry): how to dispatch (on-demand only, never auto-on-open — the ~40+ tool-calls + mutation-lab cost note), what it returns, and both live-test datums with dates. Placement route: `.claude/` is tracked (only `.claude/upgrade-snapshots/` is gitignored), so the canonical copy lives at `.claude/agents/pr-reviewer.md` and Claude Code auto-discovers it — no install shim / no `docs/agents/` fallback needed. **Still open / not built here:** the BL-097 operating-model composition point stays a **design pointer only** — this agent is the reviewer role's concrete tool, but effort-as-a-first-class-reviewer-parameter (META-7) and the single-model degradation story belong to the BL-097 trio design, not this definition; likewise a generated-project variant of the reviewer (the entry's "generated-project variant second" scope) is not built here.

**Live test 2026-07-21 (Karl-directed):** one Fable subagent reviewed PRs #229+#231 under this entry's five-dimension brief. IT WORKS — verdicts #229 approve (every SHA/path/marker claim verified) and #231 major_concerns whose MAJOR was a genuine miss two prior adversarial verifiers left standing (comment-blind wiring greps: a disabled-instantiation mutant passed every PR-blocking check; only the manual-dispatch full lane would catch it). All findings landed same-day. Design inputs from the run (META): (1) the reviewer needs a WORKTREE pinned to the PR tip — this run got lucky that the checkout was the branch; (2) pre-cleared scratch/mutation-lab semantics (first lab setup was permission-denied); (3) verdict posting + numbered finding IDs in the ledger grammar; (4) a standing LANE-REACHABILITY probe — evaluate mutation survivorship against the PR-BLOCKING check set, not the whole estate (else every full-lane-only gap becomes an automatic major on unrelated PRs); (5) trigger = slash-command/dispatch-on-demand, NOT auto-on-open (~40 tool calls + a mutation lab per run); (6) context7 was reachable via ToolSearch and produced a real oracle (GFM cell-count grammar over the new tables) — headless dispatch must verify reachability before claiming currency coverage; (7) the Agent tool exposes a model knob but no EFFORT knob — "max effort" rode in the prompt; the operating-model design (BL-097) should carry effort as a first-class reviewer parameter.

---

## BL-147: Emitted CI approval-log integrity steps are vacuous under every standard Actions checkout — tampering sails through silently

**Logged:** 2026-07-21 (BL-146 cumulative PR sweep, CR-1; validated in-session)
**Category:** Bug / silent-success (emitted CI, security lane)
**Severity:** High
**Status:** Closed — shipped 2026-07-21 (PR #235 `78d944e` + force-push follow-up PR #241 `2f53bda`). The approval-log integrity + author-verification steps are real in all 10 github + 2 gitlab templates: fetch-depth 0, explicit base resolution, and the `$BASE^{commit}` peel that demands a real commit object (the follow-up MUST — bare `--verify` passed any 40-hex string, letting a force-push tamper through silently) + an all-zeros ref-creation arm. `tests/test-bl147-ci-template-integrity.sh` 48/48. Evidence: ledger § PR-sweep WP-1 + the follow-up round.

The "Approval log integrity" + "Approval author verification" steps in `templates/pipelines/ci/github/{python,typescript,other}.yml` (+ gitlab twins) run `git diff origin/main...HEAD -- APPROVAL_LOG.md 2>/dev/null | grep -qE '^\-[^-]'` — but the templates set NO `fetch-depth`, and `actions/checkout`'s default depth-1 clone has no `origin/main` ref: the diff dies `fatal: bad revision`, the `2>/dev/null` eats it, and the step PASSES on a tampered approval log (executed proof: sweep fixture). On push-to-main the expression is self-comparing (vacuous there too). Parity hole: 7 of 10 GitHub language templates never got the steps at all. Introduced PR #8 (`db2c14e`), never revisited — the BL-112/113 silent-success class, in the governance lane, shipped to every generated project.

**Status update 2026-07-21 (follow-up round):** the consolidated wave verifier found the WP-1 guard itself defective — `git rev-parse --verify "$BASE"` passes ANY 40-hex string (object present or not), so the force-push-to-main path let a tampered log through silently (executed end-to-end repro). Follow-up on branch `fix/bl147-forcepush-guard` (PR open; this entry closes citing BOTH PRs at its merge): the guard peels `$BASE^{commit}` in both steps × all 12 templates, a new all-zeros arm handles ref creation (without it the peel would brick the scaffold's first push), suite Cd/Cf strengthened + zeros assertion, gitleaks download now sha256-verified (Ck1), semgrep engine pinned 1.170.0 across 22 files (rulesets still fetched live). 48/48 ×3.

**Fix shape:** `fetch-depth: 0` on checkout; resolve the base explicitly (`origin/${{ github.base_ref || 'main' }}`; `${{ github.event.before }}` on push); drop the `2>/dev/null` (a bad revision must fail LOUDLY); stamp the corrected step into all 10 languages × both hosts; content-pin suite.

**Related:** BL-112/BL-113 (the class); PR #8 (origin); BL-151 (shares the fetch-depth fix).

**Status update 2026-07-21:** WP-1 shipped on branch `fix/bl147-bl151-ci-approval-integrity` (status stays Open — Closed flip happens at merge, citing PR# + SHA). All 10 `templates/pipelines/ci/github/*.yml` gained `fetch-depth: 0` on checkout; both governance approval steps (integrity + author verification) are now stamped BYTE-IDENTICAL into all 10 (7 previously had none — verified single sha across all 10), resolving the base explicitly (`origin/${{ github.base_ref || 'main' }}`, `${{ github.event.before }}` on push) and failing LOUDLY via `git rev-parse --verify "$BASE"` when the base cannot resolve; every `2>/dev/null` on an APPROVAL_LOG line is gone. The two gitlab approval twins (`python.yml`, `typescript.yml`) got the same explicit-base + loud-fail + no-silencer treatment via `CI_MERGE_REQUEST_TARGET_BRANCH_NAME`/`CI_DEFAULT_BRANCH`. Watched-RED via the wave's one shared content-pin suite `tests/test-bl147-ci-template-integrity.sh` (mechanically derived template lists + >=10 count floor): pre-fix **3 passed / 11 failed**, post-fix **14 passed / 0 failed**. Mutation proofs (both restored to GREEN): re-adding `2>/dev/null` to one template → case Cc RED (13/1); removing `fetch-depth: 0` from one → case Ca RED (13/1). Registered in BOTH `tests/full-project-test-suite.sh` and the `tests.yml` unit list. All 20 CI templates re-validated as parseable YAML.

---

## BL-148: Every generated GitHub CI workflow runs SAST via semgrep-action — archived upstream April 2024

**Logged:** 2026-07-21 (sweep CR-2; validated: `gh api repos/semgrep/semgrep-action` → archived:true, pushed 2024-04-09)
**Category:** Bug / currency (emitted CI, security lane)
**Severity:** High
**Status:** Closed — shipped 2026-07-21 (PR #236 `cef54c6`). All 10 github CI templates run SAST via the `semgrep/semgrep` container (engine pinned :1.170.0 in the follow-up) with flags DERIVED from the local hook's own invocation — CI and hook cannot drift. Evidence: ledger § PR-sweep WP-2.

All 10 `templates/pipelines/ci/github/*.yml` pin `semgrep/semgrep-action@713efdd… # v1 (v0.58.0)` — the 2021 semgrep-agent era of an action dead upstream for 2+ years. Current upstream guidance (context7): the `semgrep/semgrep` container running `semgrep scan`/`semgrep ci`.

**Fix shape:** replace with a `container: semgrep/semgrep` job (or `pip install semgrep` run step) executing the LOCAL HOOK'S exact policy — `semgrep scan --config p/owasp-top-ten --config p/security-audit --config r/javascript.browser.security.insecure-document-method --severity=ERROR --error` — so CI and the pre-commit hook enforce identical rules (`# BL-118-DOMXSS-CONFIG` parity).

**Related:** BL-118 (the hook policy to mirror); BL-153 (the bitbucket image twin).

**Status update 2026-07-21 (WP-2, branch `fix/bl148-bl153-semgrep-modernization`, stacked on merged WP-1 #235):** Implemented. All 10 `templates/pipelines/ci/github/*.yml` now run SAST in a sibling `container: semgrep/semgrep` job (`actions/checkout` with `fetch-depth: 0` → `semgrep scan …`), replacing the archived action. The scan's flag set is DERIVED from the local pre-commit hook (`scripts/lib/hook-templates.sh`) by the test suite — single source, never retyped. **Correction to the fix-shape above:** the hook policy is `--config=p/owasp-top-ten --config=r/javascript.browser.security.insecure-document-method --severity=ERROR --error` — it does **not** carry `p/security-audit`. Parity with the hook is the contract (CI now enforces the IDENTICAL ruleset the dev gate does), so the CI templates dropped `p/security-audit` to match. Verified (context7 + web) that `actions/checkout` runs cleanly in the Alpine-based `semgrep/semgrep` container: GitHub's runner detects Alpine and uses its musl node build for JS actions — this is Semgrep's own documented CI pattern. Watched-RED + mutation proof (strip the DOM-XSS config → parity RED → restore → GREEN) recorded; pinned by cases Cg1–Cg5 in `tests/test-bl147-ci-template-integrity.sh`. Status stays Open pending merge.

---

## BL-149: Emitted release-pipeline DAST is the un-fixed BL-122 twin — unpassable for essentially every web app

**Logged:** 2026-07-21 (sweep CR-3; validated: raw exit-code judgment on `zap-baseline.py`)
**Category:** Bug / gate correctness (emitted release pipeline)
**Severity:** High
**Status:** Closed — shipped 2026-07-21 (PR #237 `c6e4323`). Release DAST ports the BL-122 riskcode≥2 jq verdict (9 hostile fixtures pass), pins `ghcr.io/zaproxy/zaproxy:stable`, guards on PREVIEW_URL, and the tool-matrix image matches. Evidence: ledger § PR-sweep WP-3.

`templates/pipelines/release/github/web.yml` runs `docker run -t zaproxy/zap-stable zap-baseline.py -t ${{ vars.PREVIEW_URL }}` and judges the RAW exit code — baseline reports ALL alerts as WARN (exit 2), and rule 10049 fires under every possible Cache-Control value (the proven BL-122 mechanism), so any real site fails the release. PR #203 fixed exactly this in `run-phase3-validation.sh` and never touched the template. Aggravators: image unpinned (every other action in the file is SHA-pinned); no guard when `PREVIEW_URL` is unset; gitlab/bitbucket release templates have no DAST at all (recorded, not fixed here).

**Fix shape:** port BL-122 — `-J zap-report.json` + mounted workdir + jq `riskcode>=2` verdict; pin the image (`ghcr.io/zaproxy/zaproxy:stable` to match the phase-3 scanner); `if: vars.PREVIEW_URL != ''`. Also fix `templates/tool-matrix/web.json`'s check of `zaproxy/zap-stable` — an image the scanner never uses (sweep CR-8 nit).

**Related:** BL-122 (`# BL-122-ZAP-RISK-FILTER`, the port source); BL-070 (the scanner).

**Status update 2026-07-21 (WP-3, branch `fix/bl149-release-dast`, stacked on WP-2 #236):** Implemented. `templates/pipelines/release/github/web.yml`'s DAST step now mirrors the Phase-3 scanner's verdict (`run-phase3-validation.sh`, `# BL-122-ZAP-RISK-FILTER` + `# BL-140-ZAP-WORKDIR`): the step runs `docker run --rm -v "$ZAP_WORK:/zap/wrk" ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t "…PREVIEW_URL…" -J zap-report.json` into an ABSOLUTE mounted workdir (`${GITHUB_WORKSPACE}/.zap-work`), CAPTURES the raw docker exit (`|| rc=$?`) so it is never the verdict, and judges with jq `[.site[]?.alerts[]? | select(((.riskcode // "0") | tonumber) >= 2)] | length` — Medium+ (riskcode>=2) alerts only, baseline rc 1/2 no longer FAIL. An absent report or a jq-unparseable report FAILs LOUDLY (`::error::` + `exit 1`, the BL-140/BL-112 honesty posture), and `rc>=3` is an execution error. The step is guarded `if: vars.PREVIEW_URL != ''`. `templates/tool-matrix/web.json` now checks/pulls the SAME image the scanner runs (`ghcr.io/zaproxy/zaproxy:stable`) in both `check_command` and the manual hint (was the dead `zaproxy/zap-stable` — CR-8 nit). Watched-RED via WP-3's cases (Cz0, Cz-a…Cz-e) in the shared suite `tests/test-bl147-ci-template-integrity.sh`: pre-fix **32 passed / 11 failed**, post-fix **43 passed / 0 failed**. Mutation proof (restored to GREEN): remove the `|| rc=$?` capture so the raw docker exit becomes the verdict → case Cz-b-raw-exit-captured RED (42/1); restore → GREEN (43/0). Blast-radius image-name cleanup (same dead-image defect, comment/doc-only): the commented DAST examples in `release/github/desktop.yml` + `mobile.yml` and the five references in `docs/platform-modules/web.md` were repointed to `ghcr.io/zaproxy/zaproxy:stable`; the remaining `zap-stable` hits are the suite's own grep literals and the historical `docs/superpowers/plans/archive/**`. Out of scope (per this entry): gitlab/bitbucket release templates have no DAST step — recorded, not invented. Status stays Open pending merge (Closed flip at merge, citing PR# + SHA).

---

## BL-150: Every SHA-pinned GitHub Action in the estate lags 1–3 majors; pins are invisible to the currency system

**Logged:** 2026-07-21 (sweep CR-4; validated: checkout v4.3.1 vs v7.0.1 latest)
**Category:** Debt / currency (framework workflows + emitted templates + init.sh pin table)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-21 (PR #240 `47b2019`). 11 action majors refreshed to current SHA pins across templates + both sibling RELEASE_SETUP_ACTION tables (SwiftLint deferred with evidence); a new shape case keeps any unpinned action out. The durable version-WATCHER half stays deferred to BL-109 (a lint diffing pins vs releases/latest), as this entry always scoped. Evidence: ledger § PR-sweep WP-4.

checkout v4.3.1→v7.0.1, setup-node v4→v7, setup-python v5→v7, upload-artifact v4→v7, setup-java v4→v5, action-gh-release v2→v3, golangci-lint-action v6→v9, gitleaks-action v2→v3 (flutter-action current). Surfaces: `.github/workflows/{lint,tests}.yml`, all emitted CI/release templates, init.sh's `RELEASE_SETUP_ACTION` table. BL-109's currency block tracks file SHAs/hooks/MCP — action pins structurally invisible.

**Fix shape:** one refresh PR re-pinning to current majors (new SHAs + version comments); then a durable watcher: pin inventory in the currency block or a lint diffing pin comments vs `releases/latest` (design-light, can defer the watcher to BL-109).

**Status update 2026-07-21 (WP-4, branch `fix/bl150-pin-refresh`, stacked on WP-3 #237):** The refresh half is implemented (status stays **Open** — Closed flip happens at merge, citing PR# + SHA). Every action pin in `templates/pipelines/**`, `.github/workflows/{lint,tests}.yml`, `init.sh`'s `RELEASE_SETUP_ACTION` table AND its sync sibling `scripts/reconfigure-project.sh` was re-pinned to the current release (SHA resolved from `releases/latest` → tag → commit; annotated tags de-ref'd once): checkout v4.3.1→**v7.0.1**, download-artifact v4.3.0→**v8.0.1**, setup-node v4.4.0→**v7.0.0**, setup-python v5.6.0→**v7.0.0**, setup-go v5.6.0→**v7.0.0**, setup-java v4.8.0→**v5.6.0**, setup-dotnet v4.3.1→**v6.0.0**, upload-artifact v4.6.2→**v7.0.1**, golangci-lint-action v6.5.2→**v9.3.0**, osv-scanner-action v2.3.5→**v2.3.8**, action-gh-release v2.6.2→**v3.0.2**, expo-github-action 8.2.1→**9.0.0**, rust-toolchain stable-head → current. `subosito/flutter-action` was already current (v2.23.0, same SHA — verified). Every MAJOR bump had its release notes checked for renamed/removed inputs the templates actually use; all used inputs (`fetch-depth`, `node-version`/`cache`/`registry-url`, `python-version`, `go-version`, `java-version`/`distribution`, `dotnet-version`, `path`, `files`/`generate_release_notes`, `version`, `scan-args`) survive unchanged — the majors were Node-runtime (node20→node24) bumps, not input renames. `gitleaks/gitleaks-action` has ZERO surviving usages (WP-1 removed it — verified). **Deferred (one bump):** `realm/SwiftLint` 0.57.0 held at its current pin — it ships **no `action.yml`** (a root-`Dockerfile` action), so the `strict: true` input the template passes has no verifiable metadata mapping, and the container ENTRYPOINT/CMD contract changed between 0.57.0 (`CMD ["swiftlint"]`) and 0.65.0 (`ENTRYPOINT ["/usr/bin/swiftlint"] CMD ["."]`); per the plan's "do not blind-bump un-verifiable inputs" rule it is reported, not bumped. Shape-pinned by the shared suite `tests/test-bl147-ci-template-integrity.sh` cases **Cp1** (every `uses:` ref = 40-hex SHA + version comment) and **Cp2** (both `RELEASE_SETUP_ACTION` sibling tables). The version-WATCHER half of this ticket (does a pin LAG upstream? a lint diffing pin comments vs `releases/latest`) **stays deferred to BL-109** — out of scope for the refresh PR, exactly as this entry's fix-shape anticipated.

---

## BL-151: Org-track generated projects get a failing (or license-less) gitleaks CI step

**Logged:** 2026-07-21 (sweep CR-5; validated: no GITLEAKS_LICENSE anywhere in templates; depth-1 checkout)
**Category:** Bug / documented-but-impossible (emitted CI, org tier)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-21 (PR #235 `78d944e`). gitleaks runs via the license-free CLI in all github templates (checksum-verified in follow-up PR #241 `2f53bda`), no org-license trap, fetch-depth 0. Evidence: ledger § PR-sweep WP-1.

gitleaks-action requires `GITLEAKS_LICENSE` for ORGANIZATION accounts and `fetch-depth: 0`; the emitted templates set neither. Organizational deployment is a first-class tier — the BL-137 class in the security lane.

**Fix shape:** drop the action; run the gitleaks CLI directly (`gitleaks git` — no license, mirrors the local hook), riding BL-147's fetch-depth fix. Alternative (rejected for friction): wire the license secret.

**Related:** BL-147 (shared checkout fix); BL-137 (the class).

**Status update 2026-07-21:** WP-1 shipped on branch `fix/bl147-bl151-ci-approval-integrity` (status stays Open — Closed flip happens at merge, citing PR# + SHA). The `gitleaks/gitleaks-action` step was dropped from all 10 `templates/pipelines/ci/github/*.yml` and replaced by the license-free CLI (`GITLEAKS_VERSION=8.30.1` — the current release per `gh api repos/gitleaks/gitleaks/releases/latest` → `v8.30.1`; `curl … | tar -xz gitleaks && ./gitleaks git --redact --exit-code 1`), so no `GITLEAKS_LICENSE` is required for org accounts. `gitleaks git` scans full history, so it rides BL-147's `fetch-depth: 0` fix. Content-pinned by the shared suite `tests/test-bl147-ci-template-integrity.sh` case Ce (no `gitleaks/gitleaks-action`; every github CI template runs `./gitleaks git`). Suite tally post-fix **14 passed / 0 failed** (pre-fix 3/11). Registered in BOTH lists.

---

## BL-152: GitLab driver's org-mode approvals call uses an API deprecated since GitLab 14.0

**Logged:** 2026-07-21 (sweep CR-6; validated: `glab api -X PUT projects/:id/approvals` + `approvals_before_merge` in gitlab.sh)
**Category:** Debt / currency (host driver)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-21 (PR #238 `8e62be5`). The GitLab driver configures approvals via `POST /approval_rules` (approvals_required) AND verifies via `GET /approval_rules`, off the deprecated `approvals_before_merge` on both sides; `reset_approvals_on_push` restored via its owning endpoint; BL-032 free-tier detection preserved verbatim. POST-idempotency on re-run recorded as a low-risk durable note. Evidence: ledger § PR-sweep WP-5 + follow-up.

`scripts/host-drivers/gitlab.sh` PUTs `/approvals` with `approvals_before_merge` — deprecated since 14.0, removal flagged (approval_rules is current; the field is slated out in API v5). Works today; on removal the failure lands in the generic exit-3 arm, not the handled BL-032 free-tier arm.

**Fix shape:** `POST /projects/:id/approval_rules` with `approvals_required: 1`, preserving the BL-032 Premium-only detection wording; the driver suite pins both arms.

**Related:** BL-032 (the free-tier arm to preserve); PR #91 (the prior "modern API" pass).

**Status update 2026-07-21:** WP-5 shipped on branch `fix/bl152-gitlab-approval-rules` (status stays Open — Closed flip happens at merge, citing PR# + SHA). `host_configure_protection`'s org-mode required-approvals call migrated from the deprecated `glab api -X PUT projects/:id/approvals` + `{"approvals_before_merge":1,"reset_approvals_on_push":true}` to `glab api -X POST projects/:id/approval_rules` + `{"name":"Require approval","approvals_required":1}`. API shape confirmed against the GitLab REST docs via Context7 (`POST /projects/:id/approval_rules` requires `name` + `approvals_required`; `rule_type` is OPTIONAL and the docs advise **omitting** it when creating rules via the API — so it is omitted). The rc 3 (generic) / rc 4 (Premium-only) contract is unchanged — only the call underneath moved. The BL-032 Premium-only detection is **preserved verbatim**: the broad sniff regex (`premium|ultimate|not available on your plan|feature is not available|requires.*plan`) is retained unchanged — the exact Free-tier response body for `approval_rules` is not verifiable offline, so per the plan BOTH endpoints' 403 phrasings are covered by the retained union (requiring MR approvals is the Premium gate regardless of endpoint). Watched-RED: new case **T9** in `tests/test-gitlab-ci-status-stderr-approvals.sh` (the fake `glab` now records argv+payload to `GLAB_ARGV_LOG`; T9 asserts a `POST …/approval_rules` call carrying `approvals_required` and NO `approvals_before_merge`) — pre-fix **8 passed / 1 failed** (T9 RED against the PUT form, log showed `-X PUT …/approvals` + `approvals_before_merge`), post-fix **9 passed / 0 failed**. Mutation: reverting the driver call to the PUT form → T9 RED (`5 passed / 4 failed`); restore → GREEN. Fixture arms updated in lockstep across all four gitlab suites (`test-gitlab-ci-status-stderr-approvals.sh`, `test-bl032-gitlab-free-approvals-attestation.sh`, `tests/host-drivers/gitlab.test.sh`, `tests/host-drivers/e2e-init-gitlab.test.sh`).

**Status update 2026-07-21 (WP-5 follow-up — verifier-adjudicated SHOULD-FIXes, same branch/PR):** the two items originally flagged "recorded, not built" are now BUILT (verifier held BL-152 cannot close without them). (1) **Verify migrated off the deprecated scalar:** `host_verify_protection` now reads `GET projects/:id/approval_rules` (a JSON array) and judges "approvals configured" by ANY rule with `approvals_required >= 1` (`jq -r '[.[]?.approvals_required // 0] | max // 0'`), mirroring the configure side — the old `.approvals_before_merge` read from `GET .../approvals` (also removed in v5, and it does NOT reflect approval_rules) would have false-failed on Premium once configure set approvals via rules. Context7-confirmed the GET `/approval_rules` array shape. (2) **`reset_approvals_on_push:true` re-applied:** via a dedicated `POST projects/:id/approvals` CONFIG call after the approval_rules POST succeeds (Context7-confirmed `reset_approvals_on_push` is a current, non-deprecated field on that config endpoint — only its `approvals_before_merge` rule-count field was deprecated; the endpoint survives for non-rule settings). Ordering makes it safe on Free: the Premium 403 short-circuits at the approval_rules POST above, so the reset call is only reached on a tier that supports it; its failure returns exit 3 (contract updated to note exit 3 covers both the approval-rules POST and the reset config POST). Watched-RED: two new cases — **T10** (verify GETs `approval_rules`, not the deprecated `/approvals`) and **T11** (configure emits a `POST /approvals` carrying `reset_approvals_on_push`) — both RED against the pre-follow-up driver (`8 passed / 3 failed`, incl. T3 whose fixture now expects the array-based verify), GREEN after (`11 passed / 0 failed`). Isolated mutations: revert only the verify read → T10 RED (T11 green); neutralize only the reset payload → T11 RED (T10 green); restore → 11/0. Verify + reset fixtures updated across `tests/host-drivers/gitlab.test.sh` (approval_rules GET + reset POST mocks) and `tests/host-drivers/e2e-init-gitlab.test.sh` (GET approval_rules arm returns the LIST; new reset POST arm; `APPROVALS_JSON_ORG` is now an array).

---

## BL-153: Bitbucket CI templates scan with a rename-frozen semgrep image and the deprecated gitleaks command form

**Logged:** 2026-07-21 (sweep CR-7; validated: `returntocorp/semgrep` + `zricethezav/gitleaks:latest` + `gitleaks detect` in the templates)
**Category:** Bug / currency (emitted CI, bitbucket host)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-21 (PR #236 `cef54c6`). Bitbucket CI templates use `image: semgrep/semgrep` (pinned) with hook-parity flags and `gitleaks dir` on a version-tagged image. Evidence: ledger § PR-sweep WP-2.

`returntocorp/semgrep` stopped receiving updates at the 2023 org rename (current: `semgrep/semgrep`) — generated bitbucket projects scan with a frozen engine/ruleset. `gitleaks detect` is the pre-8.19 deprecated form (`gitleaks git`/`dir` current); `:latest` tag unpinned.

**Fix shape:** `image: semgrep/semgrep` + the BL-148 flag policy; `gitleaks dir .` with a version-tagged image.

**Related:** BL-148 (the github twin).

**Status update 2026-07-21 (WP-2, branch `fix/bl148-bl153-semgrep-modernization`):** Implemented. Both bitbucket semgrep templates now use `image: semgrep/semgrep` with the hook-parity flags (`semgrep scan --config=p/owasp-top-ten --config=r/javascript.browser.security.insecure-document-method --severity=ERROR --error`). All 10 bitbucket gitleaks steps modernized: `gitleaks detect --source .` → `gitleaks dir .`; image `zricethezav/gitleaks:latest` → `ghcr.io/gitleaks/gitleaks:v8.30.1` (official image, version-pinned — latest release confirmed via `gh api repos/gitleaks/gitleaks/releases/latest` = v8.30.1, `ghcr.io/gitleaks/gitleaks:v8.30.1` manifest verified pullable). The SAME modernization was applied to the 10 gitlab CI templates for a consistent three-host surface: the global "no `returntocorp/semgrep` anywhere" invariant (WP-2's RED case Cg1 + the blast-radius grep) forced the gitlab semgrep image rename, and the gitleaks + flag-parity modernization rode along in the same edit. Pinned by cases Cg5/Cg6 in `tests/test-bl147-ci-template-integrity.sh`. Docs modernized: `docs/builders-guide.md`, `docs/user-guide.md` (`gitleaks detect --source .` → `gitleaks dir .`) and `docs/cli-setup-addendum.md` (stale "CI runs gitleaks-action" → "the gitleaks CLI"). Status stays Open pending merge.

---

## BL-154: tests.yml unit-list membership is convention, not enforcement — and CLAUDE.md claims otherwise

**Logged:** 2026-07-21 (sweep CR-8; validated: no lint greps tests.yml; current delta = 0)
**Category:** Debt / latent enforcement gap + doc drift
**Severity:** Low
**Status:** Closed — shipped 2026-07-21 (PR #239 `313d3e4`). `# BL-154-UNIT-LANE` arm in lint-tests-registered.sh enforces tests.yml unit-list membership for every non-init test; CLAUDE.md's claim is now literally true. Evidence: ledger § PR-sweep WP-6.

`lint-tests-registered.sh` checks aggregator registration only; nothing structural enforces the tests.yml unit list, while CLAUDE.md says the lint enforces BOTH. Today's delta is zero (verified) — latent, not live.

**Fix shape:** fast-lane arm in lint-tests-registered.sh (every non-init-invoking `tests/test-*.sh` must appear in the tests.yml unit list) + true-up the CLAUDE.md sentence.

**Status update 2026-07-21:** Fixed on branch `fix/bl154-unit-lane-lint` (WP-6 of
the PR-sweep remediation; PR pending). The unit-lane arm now lives behind the
`# BL-154-UNIT-LANE-BEGIN/END` fence in `scripts/lint-tests-registered.sh`: it
resolves the fast-lane list from the `.github/workflows/tests.yml` `tests=(`
array (a `--tests-yml FILE` override adds the fixture idiom that mirrors
`--tests-dir` / `--aggregators`), derives the membership predicate from each
file's own text (`grep -L 'init\.sh'`, the convention tests.yml documents —
init.sh-invoking tests are aggregator-only and EXEMPT), and flags any non-init
`tests/test-*.sh` missing from the array. A count-floor vacuity guard refuses a
0-entry parse in repo mode (exit 2). Coverage added in-suite to
`tests/test-lint-tests-registered.sh` (U1 exempt / U2 flag / U3 real-repo-clean /
U4 fence-excision mutation / U5 tests.yml-entry-removal mutation). Real-repo
delta remains 0 (all 70 non-init test-*.sh present in the 106-entry list). The
CLAUDE.md HOUSE RULES sentence was trued up (the lint now enforces BOTH lists,
with the init.sh exemption made explicit). **Stays Open** until the PR merges;
flip to Closed at merge citing PR# + SHA.

---

## BL-155: phase2-init commit gate fired before staged-file classification — the documented Phase 1→2 transition commit was impossible

**Logged:** 2026-07-22 (Dogfood-4 S0, finding F-DF4-001; fresh honest walker, real scaffold)
**Category:** Bug / workflow deadlock (commit gate, generated projects)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-22, merged 2026-07-23 (PR #243 `9402fb5`). `# BL-155-INIT-AFTER-CLASSIFY` relocates the phase2-init block behind the docs/dep-manifest exemption; the documented Phase 1→2 transition commit lands, non-exempt commits still require verified init. Watched-RED + excision mutant + e2e T-strict pin; fable verifier SHIP-WITH-FIXES applied; BL-146 stack review approve (+T6 subject-non-bypass pin). Evidence: Reports/2026-07-22-dogfood-4/ § S0.

At `current_phase=2` with `phase2_init.verified=false`, the init-verified block in `process-checklist.sh::check_commit_ready` sat ABOVE the staged-file classification, so it blocked EVERY commit — including the docs/state-only Phase 1→2 transition commit that `templates/generated/claude-md.tmpl` step 3 instructs ("update `.claude/phase-state.json` … Commit both files together"). Chicken-and-egg: recording entry into Phase 2 required Phase-2 construction scaffolding first; the S0 walker (planning-only session) was forced into a minimal config-only scaffold to land its Phase-1 artifacts. Reachable at the user terminal since the BL-112 F8 fix made the git-hook backstop real.

**Reproduce:** fixture at `current_phase=2`, `phase2_init.verified=false`; stage only `.claude/phase-state.json` + a `.md`; `process-checklist.sh --check-commit-ready` → `[FAIL] Phase 2 initialization not verified.`

**Fix:** the block moved behind the existing docs/dep-manifest exemption (`# BL-155-INIT-AFTER-CLASSIFY` fence): docs/state-only and dep-manifest-only commits land; ANY non-exempt commit still requires verified init; never subject-conditional. Watched-RED TDD (`tests/test-bl155-phase2-init-transition-commit.sh`, registered both lanes), fence-excision mutant flips the enforcement pins RED, end-to-end `T-strict-gate-blocks-unverified` re-run green.

**Related:** BL-112 (F8 made the block reachable); BL-139 (subjectless default, same function); [[dogfood-4-walk]].

**Verifier notes (adversarial verify, fable tier, 2026-07-22 — accepted-by-design):** (1) The exemption boundary is the full Build-Loop classifier (`md/json/yml/yaml/toml/tmpl` + dep manifests), so config-type commits (`package.json`, workflow `.yml`, `.tmpl`) now land pre-init-verification where the old ordering blocked them. Accepted: the gate's purpose is "no BUILD work before setup verified" (source still blocks), init-step artifacts legitimately precede `--verify-init` in the natural workflow (a scoped exemption would recreate the BL-155 deadlock class one level down), and one classifier boundary keeps the model predictable. The `Makefile`-still-blocks asymmetry is the pre-existing classifier boundary, not new. (2) Empty stage at phase-2-unverified now exits 0 (old: FAIL). At strict/default enforcement the git pre-commit hook still blocks end-to-end (re-proven via `T-strict-gate-blocks-unverified`); the residual single-Bash-call `add && commit` sequence opens only at explicit `light`/`no` opt-down — a documented dial, per doctrine not a defeat. No caller or test relied on the old empty-stage FAIL (grepped).

---

## BL-156: builders-guide still calls the Phase-0 intermediates check "advisory" — it has been fully blocking since BL-114

**Logged:** 2026-07-22 (Dogfood-4 S0, finding F-DF4-002)
**Category:** Doc drift (builders-guide vs check-phase-gate.sh)
**Severity:** Low
**Status:** Closed — shipped 2026-07-22, merged 2026-07-23 (PR #243 `9402fb5`). builders-guide bullet rewritten to the BL-114 blocking reality (any missing intermediate FAILs). Evidence: Reports/2026-07-22-dogfood-4/ § S0.

`docs/builders-guide.md` (Phase 0→1 checklist) said the intermediates check is "(advisory)… Partial saves produce a WARN, not a block." The gate (`# BL-114-F1-INTERMEDIATES` in check-phase-gate.sh) blocks on ANY missing intermediate and on a missing `docs/phase-0/` directory — the guide bullet was never updated when BL-114 hardened the arm. The S0 walker read the guide, expected advisory, got `[FAIL] … (documented as blocking)`.

**Fix:** guide bullet rewritten to state the blocking behavior and cite BL-114.

**Related:** BL-114 (the hardening this bullet lagged).

---

## BL-157: `--no-remote-creation` + manual remote wiring leaves remote-setup markers unrecorded — free-tier attestation needs an undocumented two-step repair

**Logged:** 2026-07-22 (Dogfood-4 S0, finding F-DF4-003)
**Category:** UX / state-machine gap (init remote path)
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-24 (PR #256 `5e1da61`). `# BL-157-REMOTE-MARKER`: `check-gate.sh --repair` auto-records remote_repo_created/pushed_initial when the remote genuinely carries the project's pushed head, collapsing the free-tier two-step to one. Fable verifier HIGH fixed: pushed_initial now requires the matched remote head to be a commit the repo holds locally (`cat-file -e`) + exact awk branch match — a same-named UNPUSHED remote can no longer launder the BL-123 attestation. BL-123 refusal for remote-less projects preserved (verified).

Scaffolding with `--no-remote-creation` and wiring `origin` by hand (the exact-casing repo flow) never records `phase2_init.steps_completed: remote_repo_created` / `pushed_initial`. The BL-123 attestation path REFUSES post-hoc branch-protection attestation until those markers exist (deliberate, verifier-driven), so a free-tier operator must run `check-gate.sh --repair` once (reconciles the markers from the live remote, then re-hits the 403) and only THEN `--repair --branch-protection-attested`. The two-step works and is honest, but nothing documents it; the first `--repair` output does not say "run me again with the attestation flag."

**Fix shape:** either record the markers during `--verify-init`/`--repair` preflight whenever a configured remote with the pushed branch is detected (keeping the BL-123 refusal for truly remote-less projects), or make the first `--repair` print the exact follow-up command; plus a builders-guide note in the `--no-remote-creation` section. Keep the BL-123 precondition semantics intact.

**Status update 2026-07-23 (residuals wave, Karl-approved):** fix implemented on branch `fix/bl157-remote-marker` (stays **Open** until merge; PR # / merge SHA cited at close). `# BL-157-REMOTE-MARKER` in `check-gate.sh::cmd_repair` — a preflight reconciler placed BEFORE the `# BL-123-BP-ATTEST-RECORD` block records `remote_repo_created`/`pushed_initial` when, and only when, the configured `origin` GENUINELY answers `git ls-remote` (repo provably exists) AND carries the project's branch head (current branch, else main/master — the same `git ls-remote --heads origin` primitive the check-phase-gate.sh BL-084 push backstop uses). So a single `check-gate.sh --repair --branch-protection-attested` now recovers a `--no-remote-creation` + hand-wired-origin free-tier project — the undocumented two-step collapses to one. BL-123 semantics are UNTOUCHED for truly remote-less projects: no `origin` → nothing probed/recorded; an `origin` with no pushed branch → `remote_repo_created` may reconcile but `pushed_initial` does NOT, so the attestation still REFUSES (no laundered gate). Idempotent (skips already-recorded steps; `_record_phase2_step`'s `unique` filter), writes through the shared helper. Operator-message asks also landed: the BL-123 refusal now names the exact recovery command (`git push -u origin main` then `--repair --branch-protection-attested`), and a failed protection-config `--repair` now points at the attestation flag; builders-guide § "Recovering a `--no-remote-creation` project" documents the manual-remote flow. `tests/test-bl157-remote-marker-record.sh` (both lists) 7/7: watched-RED 5/7 pre-fix (the two BL-123 must-refuse guards already GREEN), GREEN 7/7 post-fix; two mutation proofs — fence-excision (reconciler removed → single-shot attest refuses again) and unconditional-detection (fabricated head → the empty-remote b2 case re-opens the BL-123 hole, proving the detection guard load-bearing). Hermetic (local bare remote via `git init --bare` + `file://` + push; `lint-no-live-remote-in-tests.sh` green). Blast radius green: test-bl123 (11/11), test-check-gate (5/5), test-bl130 (4/4), test-bl032 (8/8), test-specs-plans-host-aware-quartet (8/8).

**Related:** BL-123 (precondition guard), BL-126 (attestation consumers), BL-111.

---


**Verifier record (fable, 2026-07-24, SHIP-WITH-FIXES — applied on the branch):** HIGH must-fix caught: the reconciler recorded `pushed_initial` on branch-NAME existence only (`grep refs/heads/<name>`), so a remote carrying a same-named but UNPUSHED `main` (GitHub's 'Initialize with README' default, disjoint history) earned the full BL-123 attestation AND the BL-116 push-gate exemption with zero project code on the host — a regression vs pre-fix, where an actual `git push` had to succeed. Also: the branch name was interpolated unescaped into a grep BRE (a `rel/1.x` local laundered a `rel/1yx` remote). FIX: exact awk field compare (`$2 == "refs/heads/<cand>"`) + require the matched head sha to be a commit the local repo holds (`git cat-file -e <sha>^{commit}`) — a genuine push guarantees the shared commit, an unrelated auto-init does not. Three fixtures added (T-unrelated-history-refused = the HIGH, T-lookalike-branch-refused = metachar/substring, T-dead-origin-not-recorded); the first two are watched-RED against the name-only version (attestation laundered onto an unpushed project) and GREEN with the fix. The existing unconditional mutant was updated to fabricate the real local HEAD sha (isolating the ls-remote-genuineness guard now that cat-file is defense-in-depth). Suite 10/10; attestation blast radius green (bl123 11, check-gate 5, bl130 4, bl032 8); run-lints 11/11. builders-guide 'carries the pushed branch' overstatement corrected.
## BL-158: `check-phase-gate.sh --gate <name>` prints the forced target phase as "Current phase" (cosmetic)

**Logged:** 2026-07-22 (Dogfood-4 S0, finding F-DF4-004)
**Category:** Cosmetic / audit clarity
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-24 (PR #258 `6a19ae4`). `# BL-158-GATE-LABEL`: under `--gate` the header reads `Checking gate: <name> (as-if phase <forced>; recorded current_phase: <recorded>)` instead of a misleading `Current phase: N`; bare runs unchanged.

With `--gate phase_0_to_1` the header prints `Current phase: 1` even when `phase-state.json` holds `current_phase: 0` — the script forces the target phase to run that gate's checks, but the label reads like recorded state and can confuse an audit trail (S0 walker flagged it while `current_phase` was still 0). No state is mutated.

**Fix shape:** label the forced value distinctly (e.g., `Checking gate: phase_0_to_1 (as-if phase 1; recorded current_phase: 0)`).

**Related:** BL-104 ([WARN]-label family — labels must not misstate the machine).

**Status update 2026-07-23 (WP-A, branch `fix/bl158-bl166-gate-scope`; Karl-approved 2026-07-23 residuals wave; fixed WITH sibling BL-166 per this entry's guidance; stays Open until merge):** Implemented. `# BL-158-GATE-LABEL` in `check-phase-gate.sh`: the RECORDED phase is captured into `recorded_phase` BEFORE the `--gate` override rewrites `current_phase`, and the header now branches on `GATE_SCOPE` — under `--gate` it prints `Checking gate: <name> (as-if phase <forced>; recorded current_phase: <recorded>)` and with NO `--gate` it prints the byte-for-byte-unchanged `Current phase: N`. Proof (`tests/test-bl166-gate-scope.sh`): case (c) `--gate phase_0_to_1` on a fixture recording `current_phase:0` asserts the distinct as-if header is present AND the misleading `Current phase: 1` line is absent — watched-RED against pre-fix code (the old header printed `Current phase: 1`), GREEN post-fix. Bare-run header unchanged verified two ways: case (d) asserts `Current phase: 3` on a bare phase-3 run, and the E25b phase-99 bare scenario still prints `Current phase: 99` with no bash error under `set -u` (the three new vars — `recorded_phase`, `gate_scope_target`, `skip_later_gate` — are all unconditionally initialized).

---

## BL-159: Emitted TypeScript CI demands `npm run lint`/`npm test` scripts nobody told the operator to create — ESLint 9 flat-config edge undocumented

**Logged:** 2026-07-22 (Dogfood-4 S1, finding F-DF4-005; fresh honest walker, real Build Loop)
**Category:** Doc gap / scaffold-CI contract (web platform module)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-22, merged 2026-07-23 (PR #244 `18b1180`). Emitted-CI script contract documented in web.md § Phase 2 (lint/test + GitHub build lane; ESLint ≥9 flat-config edge). The --verify-init mechanical-check extension stays an open idea (fold into a future entry if wanted). Evidence: Reports/2026-07-22-dogfood-4/ § S1.

`templates/pipelines/ci/github/typescript.yml` (and the gitlab/bitbucket twins) run `npm run lint` and `npm test` unconditionally, but no framework doc tells the operator this contract exists — `docs/platform-modules/web.md` mentioned ESLint only as an optional security-plugin add-on. A fresh project whose operator has not wired those scripts (or has ESLint ≥9 without a flat `eslint.config.js` — the legacy `.eslintrc.*` is no longer read) reds CI out of the box: `ESLint couldn't find an eslint.config.(js|mjs|cjs) file`. The S1 walker had to discover and wire the flat config as unplanned construction work.

**Fix:** contract documented in web.md § Phase 2 (scripts required before first push; ESLint-9 flat-config note with a minimal non-vacuous `typescript-eslint` starting point; pointer to the BL-160 audit-arm split). Deliberately NOT `--if-present` on the CI step — a silent skip is the silent-success defect class; the lane must fail loudly when the contract is unmet.

**Fix-shape extension (open idea):** `--verify-init`'s `ci_pipeline_configured` step could mechanically check `package.json` for `lint`/`test` scripts when language=typescript.

**Related:** BL-160 (same CI surface); BL-148 (emitted-CI currency family).

---

## BL-160: Emitted npm-audit step audits the full tree — dev-toolchain advisories with no in-major fix red the lane forever

**Logged:** 2026-07-22 (Dogfood-4 S1, finding F-DF4-006)
**Category:** Bug / false-FAIL doctrine (emitted CI, all three hosts)
**Severity:** Medium
**Status:** Closed — shipped 2026-07-22, merged 2026-07-23 (PR #244 `18b1180`). `# BL-160-AUDIT-SCOPE` in all three typescript CI templates: blocking arm `npm audit --omit=dev` at each host's level + loud ||-guarded dev arm. Cg7 pins hardened twice (fable verifier: comment/`|| true` evasions; BL-146 review: silent-RHS + ;/&& disables) — all mutants RED. Live proof: work-example dependency-audit lane green post-upgrade. Evidence: Reports/2026-07-22-dogfood-4/ § S1.

The emitted `npm audit --audit-level=high|moderate` step (github/gitlab/bitbucket typescript templates) audits devDependencies too. S1's zero-runtime-deps app pinned vite^5/vitest^2 and hit 1 critical + 1 high dev-only advisories with **no in-major fix** — the lane reds forever unless the operator takes a breaking major upgrade or starts ignoring CI. A permanently red lane teaches operators to ignore CI: the BL-122/BL-149 false-FAIL doctrine applies.

**Reproduce:** fresh typescript scaffold, pin vite^5 + vitest^2, push → CI `Security - Dependency audit` step exits 1 on dev-only advisories (`npm audit --audit-level=high` → `5 vulnerabilities (3 moderate, 1 high, 1 critical)`).

**Fix:** `# BL-160-AUDIT-SCOPE` in all three typescript CI templates — the BLOCKING arm audits shipped deps only (`npm audit --omit=dev --audit-level=<host's existing level>`; per-host severity levels deliberately unchanged), plus a dev-inclusive LOUD non-blocking arm (`… || echo warning`) so dev advisories surface on every run without blocking (never a silent skip). `--omit=dev` support confirmed against current npm docs (context7 /npm/cli). Pinned by Cg7 (floor/blocking/dev-loud/no-bare) in `tests/test-bl147-ci-template-integrity.sh`; watched-RED (3 FAILs pre-fix), mutation (strip `--omit=dev` → Cg7-blocking + Cg7-no-bare RED) killed.

**Related:** BL-122/BL-149 (false-FAIL doctrine), BL-148/BL-153 (emitted-CI currency family), BL-159 (same surface, contract docs).

**Status update 2026-07-22 (adversarial verifier, fable tier):** SHIP-WITH-FIXES, all applied on the PR: Cg7-blocking predicate hardened (`^[^#]*` comment rejection + unguarded requirement — the verifier's two surviving mutants, a commented-out arm and an `|| true` suffix, both now RED at 51/52); dev-arm warning reworded to admit tool-failure as a cause ("advisories or audit failure"); web.md contract gains the GitHub-lane `build` script clause. Verifier confirmed empirically: the BL-160 repro shape (vite5/vitest2 dev-only fixture, full audit RC 1 vs --omit=dev RC 0), lockfile-only operation without node_modules, blocking-arm-first tool-failure loudness, and all backlog factual claims. Follow-up idea (not this PR): GitLab arm (b) as an `allow_failure: true` job for orange pipeline status instead of an in-log echo.

---

## BL-161: `.claude/bypass-audit.json` is tracked, but every terminal commit appends a receipt row — the working tree is perpetually one row dirty

**Logged:** 2026-07-22 (Dogfood-4 S1, finding F-DF4-007; also observed by the S0 walker)
**Category:** UX / state-file hygiene (generated projects)
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-24 (PR #262 `04a961d`). `# BL-161-NO-ROUTINE-PASS`: clean terminal commits write NO tracked ledger row (byte-identity pinned by cmp); the PASS terminal writes the non-tracked `.claude/last-gate-pass.txt` receipt (gitignored via tmpl; T7 pins the ignore line statically + behaviorally after the pr-reviewer's deletion mutant survived all lanes); blocked rows byte-identical (BL-163/BL-171 preserved); `terminal_commit_passed` legacy-valid. Fable verifier APPROVE-WITH-FIXES (3 mutations + fail-open probes; stale addendum sentence fixed; lifecycle-doc truth corrected) then pr-reviewer major_concerns→approve (R-262-1 T7 pin, R-262-2 builders-guide clause). Filed BL-174 (upgrade-path gitignore backfill).

The commit detector appends a `terminal_commit_passed` row to `.claude/bypass-audit.json` on each terminal commit, and the file is NOT in the generated `.gitignore` (unlike its sibling `.claude/last-checked-commit.txt`, gitignored with a comment). Net: after the final commit of any session the tree is dirty by exactly one trailing row; committing it triggers another append (infinite chase). Both Dogfood-4 walkers independently hit it and left the file uncommitted.

**Fix shape (design decision needed):** either (a) gitignore it like the sibling (audit trail becomes local-only — note its integrity is not cryptographically protected either way), or (b) stop recording routine `terminal_commit_passed` receipts in the tracked ledger (only bypass/out-of-band events), so the file changes only on actual events. Consider which consumers read the receipts (heartbeat semantics?) before choosing.

**Related:** BL-112 (the detector), `templates/generated/gitignore-base.tmpl` (the sibling precedent).

**Status update 2026-07-24 (WP-1, branch `fix/bl161-ledger-real-events`; Karl-approved design fork 2026-07-23/24 — option (b) "record only real events"; stays Open until merge):** Implemented (source+tests `00480b7`). `# BL-161-NO-ROUTINE-PASS` in `scripts/install-filesystem-gates.sh`: the framework-gate's PASS arm (`__record_pass`) no longer appends a routine `terminal_commit_passed` row to the tracked `.claude/bypass-audit.json` — it drops a NON-TRACKED gate-ran receipt `.claude/last-gate-pass.txt` instead (the sanctioned mirror of `.claude/last-checked-commit.txt`, added to `templates/generated/gitignore-base.tmpl` with a comment). `record_audit_row` is now the BLOCKED-only writer (blocked row byte-identical: `type=terminal_commit_blocked`, `final_outcome=abandoned`). `terminal_commit_passed` stays a schema-valid LEGACY type — old ledgers keep any historical rows (kept in the `test-bl029-integration.sh` type whitelist). **Consumer enumeration** (`grep -rn terminal_commit_passed scripts/ tests/ init.sh`, re-verified and broadened to `docs/`): the WRITER is `install-filesystem-gates.sh` (changed); `scripts/lib/bypass-audit.sh:12` is a doc-comment (updated); `test-bl112` `T-clean-commit-still-works` asserted a passed row as proof-the-gate-RAN (updated to assert the non-tracked receipt + zero pass rows, with a written justification, preserving the proof-of-execution intent); `test-bl029:85` is a type whitelist (KEPT — legacy rows stay valid); `detect-out-of-band-commits.sh` does NOT read passed rows (baselines on `.claude/last-checked-commit.txt`, re-verified + proven by a detector test). **No code consumer reads pass receipts for logic** — option (b) is safe. **Gate-ran proof design:** chose the non-tracked sidecar over log-capture because it is written ONLY at the PASS terminal (its presence precisely proves the gate reached PASS), it mirrors the exact `.claude/last-checked-commit.txt` precedent, and it needs no fragile log parsing. **TDD** (`tests/test-bl161-ledger-real-events-only.sh`, unit lane, registered in BOTH lists): watched-RED = T1 FAIL pre-fix (`passed_rows=1`, tracked ledger DIFFERS, no receipt) → GREEN post-fix 6/6 (T1 clean commit = no row + byte-identical ledger + receipt; T2 framework-gate block still records; T3 BL-163 emitted block still records; T4 BL-171 commit-msg block still records; T5 genuine `claude_bypass_proposal` + `enforcement_level_set` still record; T6 detector still functions + baseline advances). Mutation (revert `install-filesystem-gates.sh` to HEAD) → T1 RED (routine pass row returns), T2–T6 GREEN → restore → GREEN. **Blast radius all green:** bypass-audit-integrity/lib/tmp-hardening/trap-isolation, bl163, bl171, bypass-detector(+session-id), bl029-integration 7/7, bl112 (real init.sh) 13/13 incl. the updated `T-clean-commit-still-works`, bl161 6/6; `run-lints.sh` 11/11. **Doc-consistency extension (surfaced for Karl):** `docs/audit-log-lifecycle.md` (§ `terminal_commit_passed` + the strict-level table) and `docs/user-guide.md` described the passed row as written on every clean commit — updated in the docs-only commit to reflect the new contract; `docs/builders-guide.md:109` lists the type in a high-level taxonomy and was left as-is (still a recognized type). **Verifier (fable, 2026-07-24): APPROVE-WITH-FIXES** — the enforcement change held under three mutations + fail-open probes and blocked-row byte-parity was proven; fixes applied as a docs-only follow-up on this branch: the stale `docs/cli-setup-addendum.md` sentence rewritten, plus two verifier-confirmed PRE-EXISTING doc-truth corrections in `docs/audit-log-lifecycle.md` § `terminal_commit_blocked` (`final_outcome` `recorded_only`→`abandoned`; `details` is `{gate:<name>}`, not commit-subject/staged-file-list/classifier-reason). Filed **BL-174** (upgrade-path gitignore backfill gap) from the verifier's Finding 1/4. **PR-review increment (standing pr-reviewer on PR #262, 2026-07-24 — major_concerns, nothing shipped refuted):** R-262-1 (MAJOR, blocking) closed — a new T7 in `tests/test-bl161-ledger-real-events-only.sh` pins the `.claude/last-gate-pass.txt` template ignore line statically (anchored grep) AND behaviorally (`git check-ignore` against the template dropped in as a real `.gitignore`), plus the sibling `.claude/last-checked-commit.txt` (the BL-174 pair); watched-RED with the reviewer's own delete-the-line mutant (the pre-T7 suite survived GREEN with the line gone → T7 RED on both arms → restore GREEN 7/7). R-262-2 (MINOR) closed — one-clause fix in `docs/builders-guide.md` (the `terminal_commit_passed` type is now recognized, not written).

---

## BL-162: BL-120 security-audit gate double-prints its OPEN-finding warning when feature slug == feature name

**Logged:** 2026-07-22 (Dogfood-4 S2, finding F-DF4-008; observed during the Probe-B block — the block itself was CORRECT)
**Category:** Cosmetic (gate output)
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-24 (PR #255 `aec1629`). `# BL-162-AUDIT-DEDUP`: the BL-120 audit-file globs are deduped by path so the OPEN-finding warning prints once when feature slug==name; the verdict/BLOCK are unchanged.

The `# BL-120-AUDIT-VERDICT` arm in `process-checklist.sh` globs audit files by both `*<slug>*` and `*<name>*`; when slug and name are identical (`find-in-document`), the same artifact matches twice and the `records N OPEN finding(s)` warning prints twice. Harmless — the step still blocks exactly once — but noisy audit output invites "is it checking two files?" confusion.

**Fix shape:** dedupe the matched-file list before the verdict loop.

**Related:** BL-120 (the arm; its BLOCK behavior verified HELD by Dogfood-4 S2 Probe B).

**Status update 2026-07-23 (residuals wave WP-B, branch `fix/bl162-bl167-precision`; Karl-approved 2026-07-23; stays Open until merge):** Fixed (source+tests `424bdd4`). `# BL-162-AUDIT-DEDUP` in `process-checklist.sh`: the glob loop now deduplicates by path (a newline-bounded `bl120_seen` accumulator + a `case … continue` skip) BEFORE the verdict loop, so a file matched by both the `*slug*` and `*name*` globs is processed — and its verdict printed — exactly once. PRINT-COUNT ONLY, confirmed: `bl120_max` is a max over identical mtimes (the two duplicate entries carry the byte-identical `stat` value, so a duplicate cannot move it) and the verdict loop's newest-mtime selection + any-open-blocks tie-break are untouched — the BLOCK is idempotent (it sets `artifact_check_failed=true` regardless of how many times the arm fires), so WHICH verdict is reached is unchanged; only the duplicate PRINT is removed. TDD (`tests/test-bl162-audit-dedup.sh`, unit lane): watched-RED against pre-fix code = T1 FAIL (`warn_count=2` on the slug==name `find-in-document` fixture) with T2 (slug!=name) already single; GREEN post-fix 4/4 (T1 one warning + still BLOCKS, T2 unaffected, T3 mutation RED reverting the dedup restores the double-print / GREEN real prints once). Registered in BOTH lists. Blast radius all green: bl120 17/17, bl118 6/6, bl125 16/16, bl108-bl117 5/5, platform-security-bugs-closer 7/7, bl112 13/13. `run-lints.sh` 11/11.

---

## BL-163: Blocked commit attempts leave NO row in bypass-audit.json — the SAST and test-execution blocks are invisible to the enforcement ledger

**Logged:** 2026-07-22 (Dogfood-4 S2, finding F-DF4-009; both dishonest commit attempts blocked correctly but unrecorded)
**Category:** Telemetry gap / audit-trail completeness (generated projects)
**Severity:** Medium
**Status:** Closed — shipped + merged 2026-07-23 (PR #251 `2ad8878`). All three emitted blocking arms (gitleaks/semgrep/bl125) append a `terminal_commit_blocked` row via a best-effort helper (`# BL-163-BLOCKED-LEDGER`). Fable verifier caught a MAJOR — the helper sourced the ledger lib in the hook's own shell, so a trojan `exit 0` lib LANDED a refused commit; fixed by subshell-confining source+append, pinned by T4b. Residual (separate surface, future entry): the emitted commit-msg hook's refusals still write no row.

The semgrep SAST arm (`# BL-118`) and the project-test arm (`# BL-125-COMMIT-TESTS`) live in the emitted pre-commit hook's fallback sequence, which exits non-zero BEFORE `.git/hooks/framework-gate.sh` runs — and framework-gate is the only writer of `terminal_commit_blocked` rows. Net: in Dogfood-4 S2, two real dishonest commit attempts (an `innerHTML` XSS sink; a red-tests commit) were both correctly REFUSED yet appended nothing to `.claude/bypass-audit.json` — the session's ledger shows only the clean landed commits. Enforcement is intact; the forensic record understates attempted violations. Anyone treating bypass-audit.json as the complete enforcement record (its stated purpose for out-of-band/bypass events) sees a cleaner history than reality.

**Reproduce:** generated project, stage a `pane.innerHTML = userText` change, `git commit` → `[BLOCKED] Semgrep …`, exit 1; `jq '.events | length' .claude/bypass-audit.json` unchanged.

**Fix shape:** the emitted hook's blocking arms append a `terminal_commit_blocked` row (gate name in `details.gate`, e.g. `semgrep`/`bl125_tests`) via `scripts/lib/bypass-audit.sh` before exiting; keep append-failure non-fatal (the block must never be weakened by ledger trouble). Mutation-proof the append.

**Related:** BL-112 (ledger/detector family), BL-118, BL-125, BL-161 (ledger hygiene).

**Status update 2026-07-23 (WP-3, branch `fix/bl163-blocked-ledger`; Karl-approved 2026-07-23; stays Open until merge):** Implemented (source+tests `d8966e3`). The emitted pre-commit hook gains a best-effort `soif_ledger_blocked <gate>` helper (in-hook marker `# BL-163-BLOCKED-LEDGER`; template-only emitter fence `# BL-163-LEDGER-EMIT-BEGIN/END` in `scripts/lib/hook-templates.sh`, kept distinct from the emitted marker so an in-hook grep and an emitter-level excision never collide — the BL-125 emitter-fence/emitted-marker precedent). ARMS COVERED — all three `FAILED=1` blocking arms of the emitted fallback sequence, each appending one `terminal_commit_blocked` row at the point it blocks: gitleaks (`details.gate=gitleaks`), semgrep SAST (`semgrep`), BL-125 project-tests (`bl125_tests`). Row schema mirrors framework-gate's `record_audit_row` (`type=terminal_commit_blocked`, `actor=user_terminal`, `final_outcome=abandoned`; `enforcement_level_at_event` read live from `.claude/manifest.json`). NON-FATAL BY CONSTRUCTION: a missing/unreadable `bypass-audit.sh`, absent `jq`, or a failed append prints one `[note]` line and returns 0; every call site is `... || true`, so `set -e` and the terminal `exit "$FAILED"` are untouched — the block is never weakened by ledger trouble. TDD (`tests/test-bl163-blocked-ledger.sh`, unit lane): watched-RED against pre-fix templates = 5 discriminating cases RED (semgrep-row / bl125-row / non-fatal-`[note]` / fence-excision / gitleaks-row), T3-clean the lone non-discriminating pass → GREEN post-fix 6/6. Fence-excision mutant (strip the `# BL-163-BLOCKED-LEDGER` block): rows stop, refusal unchanged. Registered in BOTH lists; `lint-tests-registered.sh` + full `run-lints.sh` (11/11) green. Blast radius all green: bl125 16/16, bl118 6/6, bypass-audit-lib 10/10, bypass-audit-integrity 8/8, bypass-audit-tmp-hardening 7/7, bypass-audit-trap-isolation 13/13, bl099-guard-coverage 53/53 (drives bl112 real-commit scaffolds), upgrade-sync-framework 35/35 (region refresh stays byte-identical), bl147 54/54, bl112 direct 13/13. RESIDUAL (double-fire): framework-gate's own blocked row and these fallback-arm rows are mutually exclusive per commit — a `FAILED=1` fallback arm exits at the terminal `exit "$FAILED"` BEFORE framework-gate runs, so the same block is never logged twice; if two fallback arms block one commit (e.g. semgrep + bl125) two rows are written, one per gate, which is the honest record.

**Verifier record (fable, 2026-07-23, SHIP-WITH-FIXES — both applied on the branch):** MAJOR: the helper originally SOURCED bypass-audit.sh in the hook's own shell — `exit` in a sourced file exits the sourcing shell, so a trojan/broken lib containing `exit 0` terminated the hook SUCCESSFULLY after `[BLOCKED]` printed and git COMMITTED (proven: verdict=LANDED, HEAD moved) — a new surface worse than the F-DF4-009 defect being fixed. Fixed by subshell-confining source+append (`( . lib && append )`); pinned by T4b (watched-RED reproduced LANDED pre-fix → 7/7 green). Minor: `rows_for_gate` now pins `final_outcome=="abandoned"` + `enforcement_level_at_event=="strict"` (drift mutant proven caught: a row claiming "committed" flips T1 RED). Verifier residual for a future entry: the emitted COMMIT-MSG hook's refusals (BL-072/BL-006 arms) still write no ledger row — same class, separate surface. Corrected from the implementer report: no BL-125 T8 reword ever existed (that suite is untouched, 16/16).

---

## BL-164: Emitted BL-147 governance steps are semgrep-ERROR shell-injectable — every generated github project's own Phase-3 SAST fails on the framework's scaffold

**Logged:** 2026-07-22 (Dogfood-4 S3, finding F-DF4-010; caught by the project's own run-phase3-validation.sh full-tree scan)
**Category:** Security hardening + false-blocking (emitted CI, all 10 github CI templates)
**Severity:** High
**Status:** Closed — shipped 2026-07-22, merged 2026-07-23 (PR #245 `9b9c4c2`). `# BL-164` env-indirection in both governance steps across all 10 github CI templates; live semgrep 2 ERROR → 0; fable verifier proved full event-matrix byte-equivalence; Cg8 pin extended (BL-146 review) to env/vars/inputs incl. the live release web.yml PREVIEW_URL fix. Evidence: Reports/2026-07-22-dogfood-4/ § S3.

The two BL-147 governance steps (approval-log integrity, approval-author verification) interpolated `${{ github.base_ref }}`, `${{ github.event_name }}`, and `${{ github.event.before }}` directly into `run:` shell scripts — the actions shell-injection anti-pattern (semgrep `run-shell-injection`, ERROR). Two consequences: (1) real hardening gap per GitHub's own guidance (context values must enter the shell via `env:`); exploitability is bounded (base_ref must name an existing branch) but non-zero for repos accepting external branches; (2) worse in practice: the framework ships semgrep-full-tree as its Phase-3 scanner, so EVERY generated github project FAILs its own Phase-3 validation on the framework's emitted workflow — a guaranteed false-block on clean apps (BL-122/BL-149 doctrine) caused by our own emission. The S3 walker hit exactly this (`[FAIL] semgrep-full-tree — 2 findings`) and had to fix the emitted workflow project-side.

**Reproduce:** scaffold any github project; `semgrep scan --config auto --severity=ERROR .github/workflows/ci.yml` → 2 `run-shell-injection` findings.

**Fix:** `# BL-164` env-indirection in all 10 github CI templates — both governance steps gain an `env:` block (`BASE_REF`/`EVENT_NAME`/`EVENT_BEFORE`) and the `run:` scripts reference only quoted shell variables; `BASE^{commit}` loud-fail arms untouched. Live semgrep re-scan of the emitted form: rc=0, 0 findings. Pinned by Cg8 in `tests/test-bl147-ci-template-integrity.sh` (floor 12 incl. release templates; predicate: any `${{ github.` line must be a comment or an env-style assignment). Watched-RED (all 10 flagged pre-fix) → 54/54; mutation (reintroduce one interpolation) → Cg8 RED, killed. Scoped-out residual: `release/github/mcp_server.yml` carries the pattern only in commented-out TODO example lines (inert, unscanned) — left as-is.

**Related:** BL-147 (the steps' origin — the injection shipped with the tamper-guard wave), BL-122/BL-149 (false-blocking doctrine), BL-148 (emitted-CI family).

**Status update 2026-07-22 (adversarial verifier, fable tier):** SHIP-WITH-FIXES, applied on the PR. Verifier proved functional equivalence across the full event matrix (pull_request / push / all-zeros new-branch / workflow_dispatch / tamper — byte-identical output; the ONLY divergence is on a metachar base_ref, where the old form shell-expanded and resolved the wrong ref: the exact bug being closed). Cg8 hardening applied per its probes: flag regex now catches the no-space `${{github.` form AND `${{ env.* }}`/`${{ vars.* }}`/`${{ inputs.* }}` in run: (semgrep's rule matches only the github context, so those three have no SAST backstop; the BL-146 review's R-245-1 found a live `vars.PREVIEW_URL` run-interpolation in release/github/web.yml — env-indirected on this PR); the two line-based residuals (comment-in-run, KEY:-in-run) are documented in the test and covered by the semgrep backstop; lowercase env key false-FAILs loudly (accepted direction). M2/M5 mutants re-run RED post-hardening.

---

## BL-165: Phase-3 DAST against a static app's preview server always FAILs on host-header alerts the app cannot fix in code

**Logged:** 2026-07-22 (Dogfood-4 S3, findings F-DF4-011/012; zap-dast FAIL on a genuinely clean app)
**Category:** Process gap / scanner harness guidance (Phase 3, static/web apps)
**Severity:** Medium
**Status:** Closed — shipped + merged 2026-07-24 (PR #263 `25c34fe`). `# BL-165-HARDENED-SERVE`: a project declaring production headers in `.claude/dast-headers.json` is DAST-judged with those headers applied via a generated ZAP Replacer hook (evidence sidecar records the exact applied set); no declaration → raw-preview semantics byte-identical; BL-122 judge / BL-140 workdir / BL-168 sigpipe untouched. Fable verifier APPROVE ×2 (anti-blunting forced-engage mutation caught by 8 assertions; parser-compat proven) with 2 real MINORs applied (visible note on unparseable declarations; non-empty-string shape guard); pr-reviewer major_concerns→approve (R-263-1 hook-artifact witness + py_compile — M4/M4b now RED; empty-name filter; "configured" wording; local scoping; sidecar equality; 5-mutant re-check zero survivors). Residual: one-off live-ZAP smoke recommended at next dogfood walk.

`run-phase3-validation.sh`'s zap-dast arm (riskcode≥2 judge, BL-122-correct) scanned the built `dist/` served by `vite preview` and FAILed on 2 Medium alerts — missing CSP header and missing anti-clickjacking header. Both are DEPLOY-TIME host headers (documented in the project Bible §11 for the deploy boundary), not bundle properties: the S3 walker proved the same `dist/` passes (0 Medium+) when re-served with the documented headers. Net: for every static app, Phase-3 DAST run the obvious way yields a structural FAIL that no code change can fix — the operator either learns to discount the scanner (doctrine violation) or ad-hoc-invents a hardened serve harness, unguided.

**Fix shape:** builders-guide/platform-module guidance (or a small serve harness in the validation script) to run Phase-3 DAST against the artifact WITH the project's documented production headers applied, recording the header config as part of the evidence; keep the raw-preview FAIL semantics for apps that claim no header dependence. web.md § 4.4 already gained the non-inheriting-directives note (form-action/frame-ancestors/base-uri — the third alert class this walk hit) on PR #245.

**Related:** BL-122/BL-140/BL-149 (DAST family), BL-164 (same walk section).

**Status update 2026-07-24 (WP-2, branch `fix/bl165-dast-hardened-serve`; Karl-approved hardened-serve fork 2026-07-23/24 — the alternative, globally downgrading alerts, was REJECTED; source+tests `59ad84a`; stays Open until merge):** Implemented. **DECLARATION SURFACE:** `.claude/dast-headers.json` — a flat `{"headers": {"<Name>": "<value>", …}}` map committed by the project. Chosen because it is the canonical `.claude/*.json` machine-readable surface (same directory + same jq reader the zap arm's platform gate already uses to read `tool-preferences.json`), NOT prose-parsed from Bible §11 (deliberately: too fragile). Header values may carry spaces and quotes (CSP does) — passed verbatim, never shell-split. **HARNESS (`# BL-165-HARDENED-SERVE` fence in `_p3_scan_zap`):** when the file declares ≥1 header, the arm materialises a ZAP `--hook` (Python, flush-left heredoc) + a headers JSON into the EXISTING `/zap/wrk` bind mount, applies each declared header to the responses ZAP judges via ZAP's Replacer add-on (`RESP_HEADER` match type ADDS a missing header — confirmed against the ZAP docs), and judges the app AS SERVED IN PRODUCTION with the UNCHANGED BL-122 riskcode≥2 filter. The applied config is recorded as durable, auditable evidence at `zap-dast-<ts>.hardened-serve.json` next to the report, and the verdict note names the hardening + header count. Mechanism chosen over a real localhost serve because it adds NO extra server/port/image and needs NO container↔host networking (the BL-140 scar) — ZAP still scans the operator's real `SOLO_ZAP_TARGET_URL`, just with the declared headers applied to what it sees. **FAIL-CLOSED + non-blunting:** only the DECLARED headers are applied (every other Medium+ alert — XSS, injection, insecure cookie — still FAILs), and if a header cannot be applied ZAP sees the un-hardened response and the missing-header alert FAILs the gate — a hardened PASS can only arise when the declared headers were really applied. No declaration (or an empty `{"headers":{}}`) → raw-preview FAIL semantics BYTE-FOR-BYTE unchanged (the dispatch's `${_bl165_hook_args[@]+…}` expansion is empty, the note suffix is ""; the `# BL-070-ZAP-DISPATCH` line gains ONLY that empty-in-raw-path expansion; BL-122 judge / BL-140 workdir / BL-168 sigpipe byte-untouched). **TDD** (`tests/test-bl165-dast-hardened-serve.sh`, registered in `full-project-test-suite.sh` AND the `tests.yml` unit lane): (a) declared clean app → hardened PASS + recorded evidence [watched-RED pre-fix: only the bare preview judged → 2 Medium+ host-header alerts → FAIL, no evidence]; (b1) no declaration → same headerless FAIL, no `--hook`, no evidence; (b2) empty declaration → fail-closed to raw; (c1) declared but a genuine riskcode-3 alert survives the hardening → FAIL (BL-122 judge unaffected); (c2) Low-only on the hardened serve → PASS; (c3) BL-140 workdir invariant holds on the hardened path; (e) MUTATION: excise the fence → (a) flips PASS→FAIL and the evidence sidecar disappears. GREEN 18/18. Mutation captured: real `[PASS] zap-dast — 0 Medium+ … against a hardened serve (5 documented response header(s) applied …)` vs fence-stripped `[FAIL] zap-dast — 2 Medium+ ZAP alert(s)`. **DOCS:** web.md §4.2 (surface + schema + example) & §4.4 (cross-ref), builders-guide.md Step 3.2 step 7. **BLAST RADIUS** all green: bl070-snyk-zap 48/48 (covers the BL-122 + BL-140 cases and the BL-070 dispatch mutation), phase3-validation-gate, bl168, bl070-license, bl070-threat-model, bl130, bl104; `run-lints.sh` 11/11. (test-bl113-sast-honesty has ONE pre-existing, semgrep-environment-dependent failure — `T-mutation-no-launder RED(a)` — reproduced identically on pristine `main`, unrelated to BL-165.) **DOWNSTREAM:** the arm lives in `scripts/run-phase3-validation.sh`, which existing generated projects refresh via `scripts/upgrade-project.sh` (BL-088 managed-scripts path); `init.sh` already ships the builders-guide downstream to `docs/reference/`. **Verifier-hardening increment `6f705fc`** (fable APPROVE, then scoped re-check APPROVE): a PRESENT-but-unusable declaration (invalid JSON / non-object / empty / no non-empty-string value) now emits a VISIBLE `hardening NOT applied` raw-path note instead of falling back silently, and a jq shape guard applies ONLY non-empty string-valued headers (a mixed declaration engages with just the usable subset — `{"headers":"foo"}` no longer engages on string length; an empty-string value is dropped since real Replacer would REMOVE the header); the fixed-literal note never reaches the RESULT/CARRIED machine lines. Cases (f)/(g)/(h) watched-RED (22/6) → GREEN 28/28; protected markers + RESULT/CARRIED byte-untouched. **PR-review increment `8ce2228`** (adversarial pr-reviewer on PR #263, major_concerns → all 5 findings applied): R-263-1 (MAJOR) the mock now witnesses the generated ZAP hook artifact — suppression requires `bl165-hook.py` to actually exist at the referenced path, and case (a) `py_compile`s it + checks for `RESP_HEADER`/`add_rule` (the reviewer's M4 wrong-path / M4b invalid-Python mutants had survived 28/28; now M4→31/7, M4b→37/1, restore→38/38); R-263-2 empty header NAME filtered (`select((.key|length)>0 …)`, new case (i)); R-263-3 note noun "applied"→"configured" (honesty: handed to Replacer, not proven deploy-applied; field `applied_headers` kept); R-263-4 `_bl165_*` vars declared `local`; R-263-5 case (a) asserts exact sidecar/declaration equality. Suite 38/38; blast radius + run-lints 11/11 green.

---

## BL-166: `check-phase-gate.sh --gate phase_2_to_3` exit code is dominated by Phase 3→4 readiness — a legitimate 2→3 crossing reads as "blocked"

**Logged:** 2026-07-22 (Dogfood-4 S3, finding F-DF4-013)
**Category:** UX / gate semantics
**Severity:** Medium
**Status:** Closed — shipped + merged 2026-07-24 (PR #258 `6a19ae4`). `# BL-166-GATE-SCOPE`: `--gate <name>` scopes its exit/count to the named gate (later-gate readiness prints as one non-counted `[NEXT]` line); `--gate phase_3_to_4` and bare runs unchanged. Fable verifier MAJOR (test gap) fixed: cases (f)/(g) guard the `-lt 4` threshold so a slip that skipped 3→4's own blocks (consulted by --start-phase4) is caught.

`--gate phase_2_to_3` forces `current_phase=3` to run the target gate's checks, but then ALSO runs the Phase 3→4 pre-gate checks that fire at phase 3 — so on a project that legitimately clears every 2→3 requirement the tool still exits 1 with `8 inconsistency(ies) found — blocking`, all eight being 3→4 deliverables (HANDOFF.md, sbom.json, pentest, …) that cannot exist yet. The S3 walker crossed via `--start-phase3` (which gates correctly on the bug gate + feature completeness), but the `--gate` invocation's false "blocked" verdict invites either alarm or — worse — habituation to red gate output.

**Fix shape:** scope the `--gate <name>` exit predicate (and the summary count) to the NAMED gate's checks; print later-gate readiness as clearly-labeled non-counted `[INFO]/[NEXT]` lines. Sibling of BL-158 (forced-phase header label) — fix together.

**Verifier record (fable, 2026-07-24, SHIP-WITH-FIXES — applied):** the fix is code-correct and equivalence-proven (12 bare-run fixtures byte-identical to origin/main; 36 --gate×mode combos differ only in the BL-158 header line; `--gate phase_3_to_4` still enforces all 3→4 items per-item). MAJOR was a TEST gap: the one-char threshold slip `-lt 4`→`-le 4` (making `--gate phase_3_to_4` skip its OWN 3→4 blocks) survived every PR-blocking test — and `process-checklist.sh --start-phase4` consults exactly that invocation as a live gate, so a future slip would authorize Phase 4 with HANDOFF/sbom/test-results/SECURITY/pentest/review-manifest unevaluated. Closed by new case (f) (assert `--gate phase_3_to_4` shows the per-item `Phase 3→4: HANDOFF.md not found` diagnostic AND no `[NEXT]` line — content, not exit code, since the gate-date WARN keeps exit 1 regardless) + case (g) (the `-le 4` mutant is caught by (f)). MINOR: the `[NEXT]` line now enumerates the POC-mode + release-pipeline + INCIDENT_RESPONSE.md items it also skips. Suite 8/8; gate battery + run-lints 11/11 green.

**Related:** BL-158, BL-104 (label-vs-verdict family).

**Status update 2026-07-23 (WP-A, branch `fix/bl158-bl166-gate-scope`; Karl-approved 2026-07-23 residuals wave; fixed WITH sibling BL-158; stays Open until merge):** Implemented. ROOT CAUSE: the `--gate` override forces `current_phase` to the named gate's TARGET, but the four Phase 3→4 readiness blocks are guarded by `current_phase -ge 3` — the SAME threshold as `--gate phase_2_to_3`'s target — so they fired and each `issues=$((issues+1))` counted, dominating the exit predicate (`if [ $issues -eq 0 ]`, the BL-104 [WARN]-trap surface). This was a broken `--gate` CAP: the documented contract (script header §"Semantics for --gate"; `test-check-phase-gate-argv-parser.sh::T-scoped-caps`) already says `--gate` skips higher gates, but the cap silently failed for `phase_2_to_3` alone because 2→3-crossing checks and 3→4-readiness checks share the `>=3` threshold. FIX (`# BL-166-GATE-SCOPE`): a single decision — `skip_later_gate=1` iff `--gate` names a gate whose TARGET is below 4 — guards the FOUR contiguous 3→4-readiness blocks (POC-mode, release-pipeline, artifact-existence [HANDOFF.md/INCIDENT_RESPONSE/sbom.json/docs/test-results/SECURITY/pentest/process-checklist], review-manifest) with `&& [ "$skip_later_gate" -eq 0 ]`, and the region is announced as ONE non-counted `[NEXT]` line naming the deferred deliverables. Named-gate-only checks that KEEP counting under `--gate phase_2_to_3`: 2→3 gate-date, FEATURES.md/CHANGELOG.md existence, and the Phase 2→3 test/bug gate (`test-gate.sh`), plus all 0→1 and 1→2 checks. UNCHANGED: a bare run (`gate_scope_target=""`, `skip_later_gate=0`) keeps full all-phases per-item enforcement byte-for-byte; `--gate phase_3_to_4` (target 4) keeps full 3→4 enforcement; `--gate phase_0_to_1|phase_1_to_2` never reach `>=3` so nothing changes. TDD (`tests/test-bl166-gate-scope.sh`, unit lane): (a) `--gate phase_2_to_3` on a clean-2→3 / no-3→4 fixture → exit 0 (watched-RED = exit 1 with 7 all-Phase-3→4 blocking lines); (b) same fixture minus FEATURES.md → still exit 1 with a Phase 2→3 diagnostic (named-gate enforcement intact); (c) BL-158 header; (d) bare run exit 1 + `Current phase: 3` + no `[NEXT]`. WATCHED-RED tally 2 passed / 4 failed → GREEN 6/6. MUTATION (in-suite case (e)): neuter the `skip_later_gate=1` decision line in a script copy → 3→4 checks re-enter the count → (a) flips exit 0→1 (clean copy 0, mutant 1). BLAST RADIUS all green (see WP-A report). Residual: the `--gate` cap now skips (does not evaluate) the 3→4 blocks — matching the pre-existing cap contract for lower gates — surfacing them as one informative `[NEXT]` line rather than per-item `[NEXT]` (deliberate: far smaller edit surface, no label/verdict-mismatch risk).

---

## BL-167: BL-072 TDD-ordering warn counts `.claude/*.json` state files as "impl files with no accompanying test"

**Logged:** 2026-07-22 (Dogfood-4 S3, finding F-DF4-014)
**Category:** Cosmetic / classifier precision
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-24 (PR #255 `aec1629`). `# BL-167-CLAUDE-EXCLUDE`: `.claude/` (top-level and nested) is exempt from the BL-072 impl-file classifier; src/lib/app still classify as impl.

A `fix:` commit staging only source + `.claude/phase-state.json` produced a BL-072 warn listing `.claude/phase-state.json` as an impl file lacking a test. Framework state files are never implementation; counting them as impl inflates warn noise on legitimate commits (personal tier: warn+log, so no block — but noise trains operators to skim warns).

**Fix shape:** exclude `.claude/` paths from the BL-072 impl-file classifier.

**Related:** BL-072 (the gate), BL-139 (same-family classifier precision).

**Status update 2026-07-23 (residuals wave WP-B, branch `fix/bl162-bl167-precision`; Karl-approved 2026-07-23; stays Open until merge):** Fixed (source+tests `424bdd4`). `# BL-167-CLAUDE-EXCLUDE` in `scripts/lib/tdd-classify.sh`: `_bl072_is_impl_file` gains a `.claude/*|*/.claude/*) return 1` arm so framework state files (`phase-state.json`, `process-state.json`, …) never classify as implementation. Scoped to `.claude/` ONLY — the exclusion did NOT over-reach: real source under `src/`/`lib/`/`app/` still classifies as impl (pinned by T2 + T3). TDD (`tests/test-bl167-claude-classifier.sh`, unit lane): watched-RED against pre-fix code = T1 FAIL (`.claude/phase-state.json` listed in the BL-072 WARN impl listing) + T3 FAIL (`_bl072_impl_files` emitted the `.claude/*` paths) + T4 FAIL (marker absent, nothing to mutate), with T2 (lone `src/app.ts`) already impl; GREEN post-fix 5/5 (T1 `.claude` excluded from the listing / `src/app.ts` still listed, T2 no over-reach, T3 direct-classifier assertions incl. nested `*/.claude/*`, T4 mutation RED excising the arm relists `.claude` / GREEN real omits it). Registered in BOTH lists. Blast radius all green: bl072 36/36, bl096 8/8, bl107 7/7, bl119 4/4, bl139 5/5, bl141 6/6, bl112 13/13, upgrade-sync-framework 35/35, scaffold-source-closure 6/6, scaffold-tdd-block-real 10/10. `run-lints.sh` 11/11.

---

## BL-168: CI phase-gate governance job intermittently false-fails — threat-model scanner returns un-attested SKIP on a tree whose §4 table is present

**Logged:** 2026-07-22 (Dogfood-4 S4, finding F-DF4-015; live CI on the work-example repo)
**Category:** Bug / non-determinism (fail-closed reliability)
**Severity:** Medium
**Status:** Closed — shipped + merged 2026-07-23 (PR #250 `7be4be4`). `# BL-168-TM-SIGPIPE`: `_p3_tm_has_table` collapsed to a single grep, killing the SIGPIPE-under-pipefail race that read present §4 tables as absent (~11% of live CI attempts). Reproduced live (run 29949089493 att.7) + deterministically past the grep write-buffer; pinned on the shipped bytes with a revert-mutation. DOWNSTREAM: existing generated projects need an `upgrade-project.sh` driver refresh (work-example refreshed 2026-07-23).

On the work-example repo, the CI `Governance - Phase gate check` job's phase-3-validation offline autorun intermittently reported `threat-model` as an **un-attested SKIP** ("PROJECT_BIBLE.md Section 4 threat table absent") on a checkout that plainly contains the §4 TM-001…TM-008 table — then a **no-change re-run PASSED**. Evidence: work-example run 29951076488 attempt 1 (FAIL on `[threat-model(un-attested SKIP)]`) vs attempt 2 (PASS), identical tree. Fail-closed (spurious blocks only, never a spurious pass), but "main green" is not reproducibly stable and legitimate merges can be blocked.

**Investigation pointers:** `_p3_tm_has_table` (grep-based) in the validation lib; whether the autorun's summary-file selection (`docs/test-results/phase3/summary-*` latest-by-glob) can race or pick stale artifacts across attempts; any BL-140-family workdir assumption in the threat-model arm when invoked from the gate vs standalone. Reproduce by re-running the governance job on the work-example repo at `f759c86` several times.

**Related:** BL-140 (workdir family), BL-104 (verdict-integrity family).

**Status update 2026-07-23 (WP-2 reproduce-first investigation, Karl-approved):** ROOT CAUSE conclusively pinned — a SIGPIPE-under-pipefail race in `_p3_tm_has_table`: the two-stage `grep '|' | grep -Eq 'TM-…'` pipeline's downstream `-q` exits on first match and closes the pipe; when the bible's `|`-line output exceeds one grep stdout buffer the upstream grep dies 141 mid-write, and the driver's `set -uo pipefail` reads a PRESENT table as absent → false un-attested SKIP → gate blocks. Reproduced LIVE (run 29949089493: 9 authorized reruns on the identical tree, attempt 7 FAILED with the byte-identical line — ~11%) and deterministically on macOS once the fixture exceeds the write buffer (sweep: ≤13 KB 0/500 → 109 KB 500/500; GNU grep's ~4 KB pipe buffer makes even the real 8.8 KB bible racy on Linux, BSD grep's single write is why it never reproduced locally). The gate re-rolls the race every CI attempt because `docs/test-results/phase3/` is gitignored (BL-169) so the autorun always regenerates. Eliminated: stale/tied-mtime summary selection, cwd/BL-140 workdir, report-glob ordering, partial-write races (each with disproving evidence). FIX (`# BL-168-TM-SIGPIPE`): single-grep collapse — `grep -Eq '\|.*TM-[0-9]{3}|TM-[0-9]{3}.*\|'` — no pipe, no race, predicate unchanged. Pinned by `tests/test-bl168-tm-table-sigpipe.sh` on the SHIPPED bytes (extraction-eval under the driver's own pipefail; watched-RED rc=141 on a 335 KB fixture; revert-mutation reproduces 141; semantic pins for prose-TM and TM-less-table). bl070 + phase3-gate consumer suites green. DOWNSTREAM FLAG: existing generated projects (incl. Solo-Orchestrator-work-example) carry their own byte-identical copy and will NOT self-heal — refresh via `scripts/upgrade-project.sh` (BL-088 managed-scripts path) after merge.

---

## BL-169: Scaffold gitignore's unanchored `test-results/` hides docs/test-results/ — every generated project's Phase 3→4 gate fails on a fresh CI checkout

**Logged:** 2026-07-22 (Dogfood-4 S4, finding F-DF4-016)
**Category:** Bug / scaffold (gitignore vs gate contract)
**Severity:** High
**Status:** Closed — shipped 2026-07-22, merged 2026-07-23 (PR #245 `9b9c4c2`). gitignore-base.tmpl root-anchored `/test-results/` + transient `docs/test-results/phase3/` ignored; behavioral check-ignore pin (revert-mutation shows evidence_ignored=yes). Evidence: Reports/2026-07-22-dogfood-4/ § S4.

`templates/generated/gitignore-base.tmpl` ignored `test-results/` unanchored, which also matches `docs/test-results/` — the Phase-3 evidence directory `check-phase-gate.sh` REQUIRES for the 3→4 gate. Evidence was silently never committed: the gate passed locally (files in the working tree) and failed on every fresh CI checkout (`[FAIL] docs/test-results/ directory not found`). Masked on the work-example until S4 because the dependency-audit step failed first and halted the job before the governance steps ran (the same masking hid BL-170). The S4 walker diagnosed and fixed it project-side; this closes it at the source.

**Fix:** template line root-anchored to `/test-results/` plus `docs/test-results/phase3/` (the transient BL-140 scanner workdir) ignored — mirrors the walker's live-CI-proven project config. Pinned by `tests/test-bl169-gitignore-anchor.sh` (pattern pins + a BEHAVIORAL `git check-ignore` pin: evidence tracked, runner output + workdir ignored), registered both lanes; mutation (revert to unanchored) kills T1/T2/T4 — the behavioral case shows `evidence_ignored=yes`, the exact defect.

**Related:** BL-140 (workdir), BL-170 (same masking), the 3→4 gate's `docs/test-results/` requirement in check-phase-gate.sh.

---

## BL-170: APPROVAL_LOG fill-in-place template blocks conflict with the BL-147 append-only CI guard

**Logged:** 2026-07-22 (Dogfood-4 S4, finding F-DF4-017)
**Category:** Design conflict / latent (governance templates vs emitted CI)
**Severity:** Medium
**Status:** Closed — shipped + merged 2026-07-23 (PR #252 `d020d4e`). Both APPROVAL_LOG templates instruct append-below instead of fill-in-place (resolves the append-only-guard conflict); 12 consumers validated in sync. Fable verifier caught TWO HIGH silent-bypass regressions — an unbounded `grep -A 15` that let one signer pass org dual-approval (now section-bounded), and a pen-test instruction that matched the whole-file exemption grep (reworded) — both mutation-pinned (B6/B7). Residual (filed): upgrade-project.sh's own embedded org template is still fill-in-place (unreached by tests).

`templates/generated/approval-log-personal.tmpl` (and the org twin) pre-seed each phase gate as an empty fill-in-place table (`| **Reviewer** | |`, `| **Date** | |`). Once those template lines are pushed, FILLING them modifies committed lines — and the emitted `Governance - Approval log integrity` job fails ANY modified APPROVAL_LOG.md line (append-only, BL-147). A downstream operator following the template naively hits a red gate at their next crossing. The work-example never tripped it before S4 only because the dependency-audit step failed first on every historical run, halting the job before the governance steps executed (same masking as BL-169); the S4 walker crossed 3→4 by INSERTING filled rows as pure additions, leaving the placeholders untouched.

**Fix shape (needs Karl):** replace pre-seeded empty tables with an instruction line ("append a completed approval table below this header when the gate is crossed — this file is append-only once pushed"), keeping the gate headers intact. Blast radius to validate IN SYNC: check-phase-gate.sh gate-date auto-record (`grep -A 15` date window under the header), BL-138 approval-window parsing, BL-143 self-approval scan (+20 section cap), the CI append-only guard, and any init/intake tests pinning template content. Each consumer needs a mutation-proofed re-validation against the appended-row shape.

**Related:** BL-147 (the guard), BL-138/BL-143 (row parsers), BL-169 (same masking discovery).

**Status update (2026-07-23 — append-instruction redesign implemented).** Both
`templates/generated/approval-log-{personal,org}.tmpl` redesigned: every
fill-in-place empty table (all 4 phase-gate blocks, Phase 4 Completion,
Attorney/Legal, Penetration Test, UAT sign-off; org also Pre-Phase 0) is
replaced by a short **append instruction** carrying a greppable
`<!-- BL-170-APPEND-DESIGN -->` marker. A canonical copyable table shape now
lives ONCE at the top of each file (outside every header-scoped parser window),
and each gate section instructs the operator to append a completed copy under
the header — never editing a shipped line. Multi-row tables (org Pre-Phase 0,
Approval History) keep their column-header + separator and drop only the empty
data rows so the operator appends rows below (append-only-safe).

Consumer map + how each was validated IN SYNC (all mutation-safe against the
appended-row shape): the instruction prose is deliberately kept free of any
`^|`-anchored Date row, of the substring "date", of an `Approver` token without
`Role`, and of `[YYYY-MM-DD]`/`[Name`/`[Attorney` bait — the three properties
that respectively protect (a) `_cpg_gate_has_evidence` (BL-071 `head -15`
first-`^|Date` auto-record — measured: appended Date lands at window-line ≤13
for gates, ≤13 for the org Phase 3→4 Application-Owner subsection), (b)
`validate.sh` `check_gate` (`grep -A 10` + `grep -i date | head -1` fallback)
and `validate_approval_section_dated` (org Phase 3→4 subsections), and (c)
`validate_approval_fields`/BL-138 placeholder predicate + the BL-143
self-approval blame walker (which now reaches the operator's real appended
`Approver` row instead of shadowing on template text). The BL-147 CI append-only
guard is UNTOUCHED (the invariant). `init.sh generate_approval_log()` only
substitutes `__PROJECT_NAME__`/`__TODAY__` — it does NOT fill gate tables, so the
personal Pre-Phase 0 rows stay filled-at-birth (N/A + today) and were left as-is;
no other section is pre-filled at scaffold time.

Proof: new hermetic `tests/test-bl170-approval-append-design.sh` (16/16 green;
registered in both the aggregator and the `tests.yml` unit lane) — template
pins (RED baseline against `cc0ce71`: 12 personal / 25 org empty gate rows, 0
markers → GREEN 0/0 with markers per section), behavioural cases driving the
REAL `check-phase-gate.sh` on APPENDED tables (auto-record fires; BL-138 no
false placeholder WARN; BL-143 detects self-approval when committer==approver
and does NOT false-fail when committer!=approver; org Phase 3→4 dual-approval
dated), and two mutation proofs (re-inject an empty row → pin RED; strip the
marker → pin RED). Blast-radius battery all green (date-writeback, bl138, bl143,
self-approval, retroactive-approval, blame-walker, check-phase-gate, bl105-phase4,
bl114/115/127, upgrade-path, upgrade preconditions, retroactive-section,
reconfigure, init-organizational, process-checklist, known-bugs).

Residual (out of THIS WP's "both templates" scope, filed for follow-up):
`scripts/upgrade-project.sh` carries its OWN embedded org approval-log template
(personal→org upgrade path) that still ships empty fill-in-place tables, and its
personal-log migration regex (`Phase (\d).*Phase (\d).*?\n.*?\*\*(?:Reviewer|Date)\*\*`)
assumes the Reviewer/Date row sits on the line immediately after the gate header
— which the new append shape breaks. Neither is exercised by the current upgrade
tests (they use inline old-shape fixtures), so the battery stays green, but both
are latent siblings of this bug in a different flow and should get their own
redesign pass.


**Verifier record (fable, 2026-07-23, SHIP-WITH-FIXES — all applied on the branch):** TWO HIGH merge-blocking regressions found, both silent governance bypasses vs main, both fixed with watched mutation-REDs: (1) `validate_approval_section_dated`'s unbounded `grep -A 15` — the deleted pre-seeded empty Date row had been an accidental first-match shield, so an IT-Security-ONLY append satisfied the Application Owner check and org dual-approval passed with ONE signer; now section-BOUNDED (awk to next header, head-15; BL-115/BL-138 defect class; pinned by B6, mutant-RED proven). (2) the org pen-test instruction's 'performed or exempted' phrase matched the whole-file `penetration.*exempted` grep — every scaffold auto-passed the Standard-track pen-test control from birth; reworded to 'records an exemption' (pinned by B7, wording-revert mutant-RED proven). MED: the ~2-line org 3→4 evidence-window budget now pinned end-to-end by B8 (phase_3_to_4 auto-record). LOW/NOTE also applied: instructions now say 'above this section's closing ---' (BL-143 walker bound) and Pre-Phase-0 rows must be numbered (production-upgrade parser); upgrade-project.sh's stale template-line comment trued. Suite now 19/19; consumer battery re-run green (11 suites). Verifier also confirmed: CI append-only lifecycle proven both directions; migration-regex residual is DEAD CODE (existing_gates never read) — residual list corrected.

---

## BL-171: Blocked commit-msg-stage refusals leave NO row in bypass-audit.json — the BL-072 TDD-ordering and BL-006 Build-Loop message blocks are invisible to the enforcement ledger

**Logged:** 2026-07-23 (BL-163 verifier residual, named in the BL-163 fable record: "the emitted COMMIT-MSG hook's refusals (BL-072/BL-006 arms) still write no ledger row — same class, separate surface"); Karl-approved post-Dogfood-4 residuals wave.
**Category:** Telemetry gap / audit-trail completeness (generated projects)
**Severity:** Medium (same class as BL-163)
**Status:** Closed — shipped + merged 2026-07-24 (PR #257 `9e32ecc`). `# BL-171-COMMITMSG-LEDGER`: the emitted commit-msg hook's BL-072/BL-006 refusals now write terminal_commit_blocked rows (shared BL-163 subshell-confined helper; pre-commit hook byte-identical). Fable verifier MAJOR fixed: `soif_cm_rc=0; … || soif_cm_rc=$?` so a `set -e` composed preamble can't drop the row (T6 pins it). Filed BL-172 (TDD-gate sentinel gap).

BL-163 closed the gap for the emitted PRE-COMMIT hook's blocking arms (gitleaks / semgrep / bl125_tests each append a `terminal_commit_blocked` row). Its verifier flagged the sibling surface: the emitted COMMIT-MSG hook refuses a commit — the BL-072 tier-keyed TDD-ordering HARD BLOCK, and the BL-006 Build-Loop commit-message check (BL-010) — by exiting the hook non-zero via `pre-commit-gate.sh --terminal-mode --tdd-only`. That exit happens BEFORE `.git/hooks/framework-gate.sh` runs, and framework-gate is the ONLY writer of `terminal_commit_blocked` rows — so, exactly like the pre-BL-163 pre-commit arms, a genuine commit-msg refusal appended NOTHING to `.claude/bypass-audit.json`. Enforcement is intact; the forensic record understates attempted violations at the message surface (a test-less feat: on a sponsored-POC/production tier, or a feat: with no active Build Loop, is correctly REFUSED yet leaves no ledger trace).

**Reproduce:** generated project, non-bypassable tier; stage impl with no test; `git commit -m "feat: x"` → `[FAIL] BL-072 TDD ordering … BLOCKED`, exit 1; `jq '[.[]|select(.type=="terminal_commit_blocked")]|length' .claude/bypass-audit.json` unchanged. (Or: Phase 2+, feat: with no Build Loop → BL-006 block, same result.)

**Fix (branch `fix/bl171-commitmsg-ledger`; source+tests `ae5c9c7`):** two pieces, mirroring BL-163's discipline.
1. `scripts/pre-commit-gate.sh` gains an opt-in `--emit-blocked-gate` (`# BL-171-COMMITMSG-EMIT`): under `--tdd-only`, a GENUINE refusal exits **3** (BL-072 TDD-ordering block) or **4** (BL-006 Build-Loop block) instead of 1, so the emitted hook can NAME the refused gate. Default OFF preserves the historical "non-zero = block, value = 1" contract for every direct/other caller (every existing gate-driving test asserts the flag-less rc=1 and stays green); only the generated commit-msg hook passes the flag.
2. `scripts/lib/hook-templates.sh` — the BL-163 helper is refactored into a shared `soif_emit_ledger_helper` (ONE source of truth; the pre-commit hook emits byte-for-byte identically, proven by diff), and `soif_tdd_region_body` embeds it plus a `# BL-171-COMMITMSG-LEDGER` block that maps rc 3→`details.gate=commitmsg_tdd` / 4→`commitmsg_buildloop` and appends a row via `soif_ledger_blocked`. The append is BEST-EFFORT and SUBSHELL-confined exactly like BL-163's post-verifier fix (`( . lib && append )`), so a missing/trojan ledger lib prints a one-line `[note]` and can NEVER launder the refusal. The refusal itself (the plain non-zero → `exit 1`) sits OUTSIDE the excisable `# BL-171-COMMITMSG-LEDGER` fence, so a fence excision drops telemetry only. Row schema mirrors BL-163 / framework-gate (`type=terminal_commit_blocked, actor=user_terminal, final_outcome=abandoned`, `enforcement_level_at_event` read live from `.claude/manifest.json`). WARN-tier (personal / private-POC bypassable) and attested outcomes exit 0 → NO row (they did not block; the WARN is logged to `.claude/tdd-warn-ledger.jsonl`, a different file).

REFUSAL-PATH ENUMERATION (emitted commit-msg hook → `--terminal-mode --tdd-only`): (a) `tdd_terminal_enforce` non-bypassable hard block → exit 3 → row `commitmsg_tdd`; (b) `tdd_terminal_enforce` attestation-record FAILURE (`SOLO_TDD_ATTESTED=1` but the write failed) → exit 3 → row `commitmsg_tdd` (a genuine refusal); (c) `bl006_terminal_enforce` Build-Loop block → exit 4 → row `commitmsg_buildloop`. CORRECTLY EXCLUDED (return 0, no block, no row): bypassable-tier WARN, attested-and-recorded escape, the sentinels each gate actually honors (`bl006_terminal_enforce` honors MERGE_HEAD/CHERRY_PICK_HEAD/REVERT_HEAD; `tdd_terminal_enforce` honors MERGE_HEAD only — a strict-tier cherry-pick/revert resume of an impl-no-test feat IS refused and, truthfully, now writes a `commitmsg_tdd` row; the missing CHERRY_PICK/REVERT sentinels in the TDD gate are a pre-existing gap, see BL-172), framework-repo pass, no-checklist no-op, and the "not a git repo" `exit 1` (a non-3/4 error, not a gate refusal — the fallback exits 1 with no row).

**Verifier record (fable, 2026-07-24, SHIP-WITH-FIXES — all applied on the branch):** MAJOR: the emitted gate call was a bare command + `soif_cm_rc=$?`. When the region is composed onto a user hook whose preamble runs `set -e` (the common case — init.sh/verify-install/upgrade-project APPEND it to pre-existing hooks), the shell aborted at the gate line before `$?` was captured: the commit was still REFUSED but the ledger row silently vanished — the exact telemetry loss BL-171 closes. FIX: `soif_cm_rc=0` then `… --emit-blocked-gate || soif_cm_rc=$?` (the `||` consumes the non-zero so errexit never fires). Pinned by new T6 (composed `set -e` preamble): watched-RED against the bare capture (REFUSED, 0 rows) → GREEN (REFUSED, 1 `commitmsg_tdd` row). Verifier proved: pre-commit hook emitted bytes remain BYTE-IDENTICAL to origin/main after the shared-helper refactor; the exit-code remap (1→3/4) is contract-clean for every caller (flag OFF → block still exit 1); never weakened by ledger trouble (trojan `exit 0`/`exit 3` libs, missing/malformed/readonly — all REFUSED, 0 false rows); 6/6 of its own mutants killed. MINORs applied: the enumeration prose above (cherry-pick/revert sentinel gap → filed BL-172) and the stale `test-bl010-commitmsg-bl006.sh` comment. Suite 8/8; blast radius + run-lints 11/11 green.

**Proof:** `tests/test-bl171-commitmsg-ledger.sh` (unit lane; hermetic scaffold + REAL `git commit`s through the emitted commit-msg hook). Watched-RED against pre-fix templates: 4 discriminating cases RED (T1 tdd-row / T2 buildloop-row / T4 non-fatal `[note]` / T5 fence-excision-vacuous), the 3 allowed/no-ledger cases non-discriminating → GREEN 7/7 post-fix. Cases: T1 commitmsg_tdd row + REFUSED; T2 commitmsg_buildloop row + REFUSED; T3 WARN-tier LANDS + 0 rows; T3b clean LANDS + 0 rows; T4 append-lib-gone → REFUSED + `[note]` + 0 rows; T4b trojan `exit 0` lib → REFUSED (not laundered) + 0 rows; T5 fence-excision → still REFUSED + 0 rows. Registered in BOTH lists; `lint-tests-registered.sh` + `run-lints.sh` green. Blast radius all green: bl163 7/7, bl010 11/11, bl072 36/36, bl141 6/6, check-commit-message, the four bypass-audit suites (lib 10 / integrity 8 / tmp-hardening 7 / trap-isolation 13), bl119/bl139/bl096/bl107/pre-commit-gate-terminal-mode, bl125 16, freshness-check 26 / freshness-birth 6, upgrade-sync-framework, plan-staging 25, currency-manifest 53, bl099 registry + bl112 real-scaffold (the one commit-msg case, T-tdd-gate-no-regression, still REFUSES). Double-fire: framework-gate's own blocked row and these commit-msg rows are mutually exclusive per attempt — a pre-commit-stage block (BL-163 arm or framework-gate) aborts git BEFORE the commit-msg hook runs; the two commit-msg gates are sequential (TDD exits before BL-006), so one attempt writes at most one row.

**Related:** BL-163 (the pre-commit sibling this completes; shares `soif_ledger_blocked`), BL-072 / BL-010 / BL-006 (the two message gates), BL-112 (ledger/detector family), BL-096 (`--commit-msg-gates` alias — `--emit-blocked-gate` composes with it).
---

## BL-172: TDD-ordering commit-msg gate honors MERGE_HEAD only — cherry-pick / revert resumes of impl-no-test feats are refused

**Logged:** 2026-07-24 (surfaced by the BL-171 fable verifier; pre-existing, not introduced by BL-171)
**Category:** Gate precision / sentinel parity (commit-msg TDD gate)
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-25 (PR #265 `7866022`). `# BL-172-RESUME-SENTINELS`: CHERRY_PICK_HEAD / REVERT_HEAD added to **both** BL-072 TDD-gate surfaces — `tdd_terminal_enforce` (the commit-msg hard block, the filed target) and `tdd_warn_check` (the same gate's PreToolUse WARN entry point, found by a MERGE_HEAD survey of `scripts/pre-commit-gate.sh` and identified as the target's counterpart by its own in-function comment) — matching `bl006_terminal_enforce`'s three-sentinel set. MERGE_HEAD behavior untouched. The other two MERGE_HEAD-only sites are DIFFERENT gates and were deliberately left alone: `bl006_check` (BL-006 PreToolUse) and `lints_check` (lint-promotion). Pinned by `tests/test-bl172-resume-sentinels.sh` — 15 cases across both surfaces, including an anti-blunting case per surface (a NORMAL impl-only commit must still refuse/warn) and a marker-excision mutation proof; registered in both the aggregator and the `tests.yml` unit lane. Fable verifier APPROVE-WITH-FIXES; filed **BL-176** (the same five sentinel sites are blind inside linked git worktrees).

`tdd_terminal_enforce` (the BL-072 commit-msg TDD-ordering gate in `scripts/pre-commit-gate.sh`) skips only when `.git/MERGE_HEAD` is present, whereas its sibling `bl006_terminal_enforce` honors all three of MERGE_HEAD / CHERRY_PICK_HEAD / REVERT_HEAD. Net: a strict-tier `git commit` resuming a cherry-pick or revert whose payload is an impl file with no accompanying test is REFUSED by the TDD gate (and, since BL-171, truthfully writes a `commitmsg_tdd` ledger row). The refusal is arguably defensible (the resumed content genuinely lacks a test), but it is an inconsistency with BL-006's sentinel set and with the `--amend` parity notes — a cherry-pick/revert is replaying an already-reviewed change, so re-imposing TDD ordering on it is likely wrong.

**Fix shape:** add CHERRY_PICK_HEAD / REVERT_HEAD to the `tdd_terminal_enforce` sentinel check, matching `bl006_terminal_enforce`; mutation-proof the added sentinels; confirm the PreToolUse surface parity. Keep MERGE_HEAD behavior unchanged.

**Related:** BL-171 (surfaced this), BL-072 (the gate), BL-010/BL-006 (the sibling gate with the fuller sentinel set).

**Build note (2026-07-24, branch `fix/bl172-sentinel-parity`, pre-PR — Status stays Open):**
Added the two missing sentinels (`# BL-172-RESUME-SENTINELS`) to `tdd_terminal_enforce`,
mirroring `bl006_terminal_enforce`'s three-sentinel set; MERGE_HEAD behavior is
untouched. **Second-surface parity finding:** grepping MERGE_HEAD across
`scripts/pre-commit-gate.sh` returns five skip sites — `tdd_terminal_enforce`
(the target), `bl006_terminal_enforce` (the sibling, already three-sentinel), and
three MERGE_HEAD-only sites. Of those three, the one whose in-function comment names
`tdd_terminal_enforce` as its hard-block counterpart is `tdd_warn_check` — the SAME
BL-072 gate's PreToolUse WARN entry point (Phase C1). It already passes explicit
`git cherry-pick`/`git revert` COMMANDS via a command-string filter and resumed
MERGES via its own MERGE_HEAD sentinel; the two sentinels were added there too so a
cherry-pick/revert resumed with a plain `git commit` (no command-string keyword)
also passes — identical extension, same marker. The other two MERGE_HEAD-only sites
are DIFFERENT gates and were left untouched: `bl006_check` (the BL-006 PreToolUse
gate) and `lints_check` (the operator-side lint-promotion surface). Pinned by
`tests/test-bl172-resume-sentinels.sh` — 15 cases across both surfaces (cherry-pick/
revert/merge pass-through, an anti-blunting case per surface proving a NORMAL
impl-only commit still refuses/warns, and a marker-excision mutation proof).
Registered in both the aggregator and the `tests.yml` unit lane.

---

## BL-173: Two pre-existing full-suite test failures — currency-birth-stamp stale vs BL-107, and the BL-113 driver-mutation case is not pinned to its marked lines

**Logged:** 2026-07-24 (surfaced by the residuals-wave verifiers; pre-existing on `main`, reproduced on `c6dff01`; neither is in the PR-blocking unit lane)
**Category:** Test hygiene (full-suite-only failures)
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-25 (PR #266 `d857294`). Closed **at merge**, per this entry's own stated condition ("flips to Closed with PR + merge SHA at merge") — it is **not** full-lane-gated; only BL-136 carries that condition. (An intermediate handoff asserted otherwise; that was corrected before merge.) Both suites repaired, **test-only, no product code**: `tests/test-currency-birth-stamp.sh` 16/2 → **18/0** (the rust/other commit-msg expectations moved `absent-intentional`/`absent-unavailable` → `present`, the post-`# BL-107-UNIVERSAL-INSTALL` contract the product already implemented) and `tests/test-bl113-sast-honesty.sh` 16/1 → **17/0** (`T-mutation-no-launder RED(a)` re-aimed off the environment-sensitive overall gate verdict onto the laundering-specific delta of the `# BL-113-NO-LAUNDER` driver decision). Mutation-proven in both directions; clean fable APPROVE (7-row mutation matrix; root-caused the supposed "flake" as deterministic). **Coverage caveat — recorded at BL-136:** neither repaired suite is executed by ANY CI lane today, so "repaired" is a local-run claim, not a CI-verified one.

Two `tests/` suites fail on a clean `main` checkout, unrelated to any in-flight work:

1. **`tests/test-currency-birth-stamp.sh` — 2 failures, stale vs the BL-107 universal-hook-install contract.** Since BL-107, `init.sh` installs a commit-msg hook for EVERY language tier, but the test still expects `rust → absent-intentional` and `other → absent-unavailable`. Reproduced 2026-07-24: `Results: 16 passed, 2 failed` (`rust commit-msg — expected absent-intentional, got [present]`; `other commit-msg — expected absent-unavailable, got [present]`). The fix is to update the two expectations to the post-BL-107 contract (present for all tiers), keeping the rest of the manifest-currency assertions untouched.

2. **`tests/test-bl113-sast-honesty.sh` — 1 failure, `T-mutation-no-launder RED(a)`.** Neutering the marked BL-113-NO-LAUNDER *driver* decision lines does NOT reintroduce the laundering the case expects — the Phase-3 output shows the run failing for OTHER reasons (un-attested SKIP path), so the mutation case is not actually pinned to the marked driver lines. RED(b) (the gate-side mutation) and GREEN still pass, so the gate-side marker is proven load-bearing; only the driver-side mutation case is mis-aimed. Environment-sensitive (invokes real `semgrep`); identical failure on `origin/main`, per the 2026-07-24 handoff. Reproduced 2026-07-24: `Results: 16 passed, 1 failed`. The fix is to re-aim RED(a) at a fixture state where the driver decision is genuinely load-bearing (clean tree + prior FAIL carry-forward), or assert on the laundering-specific output rather than overall gate verdict.

Neither failure blocks PRs (both suites are full-suite-only, not in the `tests.yml` unit `tests=(` list). Both mask real regressions in their areas while red, which is the reason to clean them up rather than live with them.

**Related:** BL-107 (the contract change item 1 is stale against), BL-113 (the honesty gate item 2 mis-tests), `docs/handoffs/2026-07-24-residuals-wave-and-next-builds.md` § 3 (first surfaced).

**Status update 2026-07-24 (fix built, awaiting merge — Status stays Open, flips to Closed with PR + merge SHA at merge):** repaired on branch `fix/bl173-test-cleanups`, commit `636bd11` (tests). **Test-only; no product code touched** — both were genuine STALE tests: the product already agrees with BL-107 (`soif_currency_hook_state` returns `present` for commit-msg on every language) and the BL-113 driver/gate carry-forward is intact (RED(b) + GREEN already proved the gate-side marker load-bearing). **Item 1 (`tests/test-currency-birth-stamp.sh`):** the rust/other commit-msg expectations moved `absent-intentional`/`absent-unavailable` → `present` (citing `# BL-107-UNIVERSAL-INSTALL`, PR #205); the header + both scaffold comments now document the enum's absent-* values as historical legacy-reader states never written by a fresh scaffold. 16/2 → **18/0**. **Item 2 (`tests/test-bl113-sast-honesty.sh`):** `T-mutation-no-launder RED(a)` was re-aimed off the overall gate verdict (`validation scans clean` — which ALSO needs the regenerated offline SKIP to be attested, an environment-sensitive signal that comes up un-attested here, so the case failed for an unrelated reason and was never pinned to the marked lines) onto the laundering-specific delta of the `# BL-113-NO-LAUNDER` driver decision: with the marked driver lines neutered the regenerated summary records semgrep **SKIP** (was FAIL) and the gate drops the `[STALE - last real result: FAIL]` carry-forward — the exact inverse of the pristine `T-no-launder-dirty-tree (a)` case (which still asserts FAIL + carry-forward present: the GREEN side, unchanged). 16/1 → **17/0**. Mutation-proven both directions (currency: flip an expectation back → suite RED → restore; bl113: leave the mutant copy PRISTINE → RED(a) fails with `carryfwd_gone=0 sem_laundered=0` and the gate shows `[STALE — last real result: FAIL]`/`semgrep-full-tree(FAIL)` → restore). Both suites green **twice in a row**; `scripts/run-lints.sh` 11/11. Neither suite was added to the `tests.yml` unit lane (both invoke real `init.sh`).

---

## BL-174: upgrade-path never backfills the gitignore ignore-lines — upgraded projects get the BL-161 receipt behavior but not its ignore line (same gap pre-exists for last-checked-commit.txt)

**Logged:** 2026-07-24 (BL-161 WP-1 fable verifier, Finding 1/4)
**Category:** Upgrade-path parity / state-file hygiene (generated projects)
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-25 (PR #268 `ed406c8`). `# BL-174-GITIGNORE-BACKFILL` in `_run_idempotent_backfill`: an idempotent append-if-missing gitignore backfill covering BOTH sidecar lines (`.claude/last-checked-commit.txt` AND `.claude/last-gate-pass.txt`) — `grep -qxF` guards make a re-run a byte-no-op, manifest-gated on `.claude/manifest.json`, best-effort (`|| true`), create-if-missing. **The manifest gate is load-bearing:** an earlier UNGUARDED draft appended the two lines to the framework repo's OWN `.gitignore` (caught mid-build). New hermetic suite `tests/test-bl174-gitignore-backfill.sh` (6 cases, no `init.sh`, registered in BOTH lanes) pins the lines BEHAVIORALLY via `git check-ignore` on an upgraded fixture, with T6 asserting a no-manifest projectless fixture is a byte-no-op. Secondary hardening landed too: `tests/test-filesystem-gate-install.sh` T8, that suite's first pass-arm case, mutation-proved by deleting the `record_gate_pass_receipt` write. Fable verifier APPROVE-WITH-FIXES. **Residual stays Open as BL-177 (Medium):** this fix closed the *gitignore* instance by manifest-gating one block; the STRUCTURAL projectless/in-framework gap in the same function is unfixed, and two sibling blocks (vendored-skills sync, BL-088 source-closure copy) still write outside generated projects today.

`scripts/upgrade-project.sh` has **zero** gitignore writers — the `templates/generated/gitignore-base.tmpl` ignore lines reach a project only via `init.sh`'s `generate_gitignore()`. `_run_idempotent_backfill` re-runs `install-filesystem-gates.sh --install` (~`upgrade-project.sh:564-565`), so an UPGRADED strict project DOES pick up the new BL-161 receipt behavior (`.git/hooks/framework-gate.sh` drops `.claude/last-gate-pass.txt` on a clean pass) but NEVER receives the matching `.claude/last-gate-pass.txt` ignore line. Net: on an upgraded project the receipt sits UNTRACKED, and a downstream `git add -A` would TRACK it — resurrecting the BL-161 dirty-chase in tracked form. The IDENTICAL gap already pre-exists for the sibling `.claude/last-checked-commit.txt` (backfill writes that baseline at ~`upgrade-project.sh:561-562`, likewise with no ignore line).

**Honest calibration:** untracked ≠ tracked-dirty. `scripts/check-phase-gate.sh`'s clean-tree predicate excludes `.claude/`, and an untracked receipt does not dirty the `git status` the gate reads — so even UNFIXED this is strictly better than the tracked-dirty ledger BL-161 removed. The gap bites only if an operator `git add -A`s the untracked file.

**Fix shape:** an idempotent append-if-missing gitignore backfill for BOTH sidecar lines (`.claude/last-gate-pass.txt` AND `.claude/last-checked-commit.txt`) in `_run_idempotent_backfill`; mutation-proof it (the line is added exactly once; re-running is a no-op).

**Secondary (optional hardening, do when BL-174 is built):** `tests/test-filesystem-gate-install.sh` has zero pass-arm coverage — it passed unchanged under both BL-161 receipt mutations, so it cannot catch a regression in the clean-pass receipt path. Add one receipt case (a clean pass writes `.claude/last-gate-pass.txt` and no tracked-ledger row).

**Build note (2026-07-24, branch `fix/bl174-gitignore-backfill`):** implemented the
append-if-missing backfill inside `_run_idempotent_backfill` (marker
`# BL-174-GITIGNORE-BACKFILL`), covering BOTH sidecar lines
(`.claude/last-checked-commit.txt` and `.claude/last-gate-pass.txt`). Idempotent
(`grep -qxF` guards each exact line → re-run is a byte-no-op), manifest-gated (runs
for every generated project via the `.claude/manifest.json` marker, matching the
host-field and BL-030 sibling backfills), best-effort (`|| true` so a gitignore hiccup never fails the
upgrade), and create-if-missing when a project has no `.gitignore` at all — the last
two mirroring the marker-gated / create-if-missing posture of the sibling
`.claude/last-checked-commit.txt` / `.claude/bypass-audit.json` backfills in the same
function. **The manifest gate is load-bearing:** the enclosing subshell runs
`cd "$PROJECT_ROOT"`, and because the `--backfill-only` path never reaches
`guard_not_in_framework`, a projectless / in-framework invocation (empty
`PROJECT_ROOT` → that `cd` no-ops → cwd stays the framework repo) would otherwise
append the two lines to the framework's OWN `.gitignore`. An earlier UNGUARDED draft
did exactly that (caught mid-build when an upgrade-family suite polluted the worktree
`.gitignore`); the `.claude/manifest.json` gate — matching the host-field and BL-030
sibling backfills — closes it. NOTE: not every sibling block carries such a gate — the
vendored-skills sync and the BL-088 source-closure copy have no project gate and write
outside generated projects today (the framework repo's month-old untracked
`.claude/skills/` is standing residue); that structural gap is tracked as **BL-177**. New hermetic suite `tests/test-bl174-gitignore-backfill.sh` (6
cases; hand-built fixture, NO init.sh — copies the upgrade script + lib closure and
drives `--backfill-only`; registered in BOTH the `tests.yml` unit lane and the
full-project aggregator) pins the two lines BEHAVIORALLY via `git check-ignore` on an
UPGRADED fixture (the BACKFILL side; the TEMPLATE side stays pinned by
`tests/test-bl161-ledger-real-events-only.sh` T7) and adds T6 — a no-manifest
projectless fixture must be a byte-no-op (its watched-RED was observed against the
unguarded draft). Watched-RED + marker-excision mutation both captured. Secondary hardening also
landed: `tests/test-filesystem-gate-install.sh` gained T8 — the suite's first
pass-arm case (a clean commit through the installed gate writes the
`.claude/last-gate-pass.txt` receipt and appends no row to the tracked
`.claude/bypass-audit.json`), mutation-proved by deleting the
`record_gate_pass_receipt` write line (T1–T7 stayed green — the suite was blind to
the PASS terminal before T8). Status stays **Open** pending PR review/merge.

**Related:** BL-161, BL-107, `templates/generated/gitignore-base.tmpl`.

---

## BL-175: The shipped DOM-sink ruleset (`templates/semgrep/soif-dom-sinks.yml`) is outside every mechanical tracking surface — not source-closure-tested (BL-108 class) and not currency-tracked (BL-109 class)

**Logged:** 2026-07-24 (BL-131 WP-A implementer escalation, supervisor-triaged)
**Category:** Scaffold-shipped-set / currency registry coverage gap
**Severity:** Low
**Status:** Open

BL-131 ships a new vendored artifact, `templates/semgrep/soif-dom-sinks.yml`, that `init.sh` copies into every scaffold's `.semgrep/` and that the emitted pre-commit hook + generated CI reference by `--config`. But `scripts/lib/scaffold-shipped-set.sh`'s parsers enumerate only four shapes — `soif_parse_shipped_scripts` (scripts/), `soif_parse_shipped_reference_docs` (docs/reference/), `soif_parse_shipped_templates` (templates/generated/*.tmpl), and `soif_parse_shipped_skills` (the vendored-skill loop). A `cp "$SCRIPT_DIR/templates/semgrep/soif-dom-sinks.yml" .semgrep/` line matches NONE of them, so the ruleset is:

- **not source-closure-tested** (BL-108 class): `tests/test-scaffold-source-closure.sh` derives the shipped set from those parsers, so a future edit that made the ruleset source an unshipped sibling would go uncaught (moot today — YAML sources nothing — but the tracking gap is real).
- **not currency-tracked** (BL-109 class): the currency manifest/inventory stamps drift only for the tracked shapes, so an operator whose vendored ruleset drifts from the framework gets no freshness signal.

**Fix shape:** extend the `scaffold-shipped-set.sh` parser registry with a `soif_parse_shipped_semgrep` (or a generalized `templates/<dir>/` verbatim-copy shape) covering `templates/semgrep/*.yml`, and fold it into the BL-109 currency stamping + the BL-108 closure derivation. Mutation-proof the new parser (a shipped ruleset appears in the derived set; an unshipped one does not).

**Related:** BL-131 (ships the ruleset + the sync/verify-install delivery paths), BL-108 (source-closure), BL-109 (currency system).

---

## BL-176: sentinel skip checks are blind in linked git worktrees — literal `.git/<SENTINEL>` paths miss the per-worktree gitdir

**Logged:** 2026-07-24 (BL-172 WP-B fable verifier, findings F2+F3)
**Category:** Gate precision / git-worktree correctness (commit-msg + PreToolUse sentinel skips)
**Severity:** Low
**Status:** Open

In a **linked git worktree** `.git` is a FILE (a `gitdir:` pointer), not a directory, so the literal `[ -f .git/<SENTINEL> ]` derivative-commit skip tests are BLIND: mid-cherry-pick `[ -f .git/CHERRY_PICK_HEAD ]` is FALSE, while `git rev-parse --git-path CHERRY_PICK_HEAD` resolves to `.git/worktrees/<name>/CHERRY_PICK_HEAD` where the sentinel actually lives. Verified on git 2.50.1 by the BL-172 verifier's empirical probe, and independently reproduced in THIS repo's own `.claude/worktrees/agent-*` worktree: `.git` is a 103-byte file, `test -f .git/CHERRY_PICK_HEAD` → FALSE, and `git rev-parse --git-path CHERRY_PICK_HEAD` → `<repo>/.git/worktrees/<name>/CHERRY_PICK_HEAD`. In a normal (non-worktree) checkout `--git-path` returns `.git/<SENTINEL>`, so it is a drop-in replacement.

Affects **all five** skip sites — the two BL-172 additions AND the pre-existing MERGE_HEAD lines AND `bl006_terminal_enforce`'s full three-sentinel set: `tdd_terminal_enforce`, `tdd_warn_check`, `bl006_terminal_enforce`, `bl006_check`, `lints_check`. Net: the BL-172 symptom (spurious refusal of a resumed cherry-pick/revert — and, pre-BL-172, a resumed merge) PERSISTS inside a linked worktree, because the skip never fires there.

**Fail direction (calibration):** CLOSED. The blindness makes the gate MORE strict (a skip that *should* fire does not), so the only consequence is an inconvenient spurious refusal, NEVER a bypass. That is why this is Low, not a blocker.

**Fix shape:** replace the literal `.git/<SENTINEL>` path tests with `git rev-parse --git-path <SENTINEL>` at all five sites (a drop-in in normal checkouts, correct in linked worktrees); mutation-proof each site.

**Secondary (optional hardening, verifier F3):** write a `sentinel_skip` ledger row whenever a sentinel skip fires, so a forged-sentinel commit leaves a trace. Parity note: sentinel forgery is ALREADY possible via the pre-BL-172 MERGE_HEAD line and requires privileged `.git` write access — this introduces no new abuse class, hence a rider, not a blocker.

**Rider (2026-07-25, added with the PR #265–#270 closures — do these THREE things in one change, not the `--git-path` conversion alone):**
1. **The `--git-path` conversion itself**, at all five sites (`tdd_terminal_enforce`, `tdd_warn_check`, `bl006_terminal_enforce`, `bl006_check`, `lints_check`).
2. **ALSO add CHERRY_PICK_HEAD / REVERT_HEAD to `bl006_check` and `lints_check`.** BL-172 (PR #265 `7866022`) extended only the two BL-072 TDD surfaces; these two remain **MERGE_HEAD-only**, so a cherry-pick or revert **resumed with a plain `git commit`** (no `git cherry-pick`/`git revert` keyword in the command string for the PreToolUse command-string filter to catch) is still refused there. That is the exact BL-172 symptom, unfixed, on two more surfaces — and it is invisible from BL-172's own entry, which deliberately scoped them out as "DIFFERENT gates".
3. **Extract a shared `_derivative_resume_in_progress()` helper** (single `git rev-parse --git-path` sentinel test over the three-sentinel set) and call it from all five sites, so this becomes ONE change with ONE mutation proof instead of five parallel edits that can drift apart again. The current five-site duplication is precisely what let the sentinel sets diverge in the first place — BL-172 fixed two of five, and the `--git-path` blindness affects all five identically.

**Related:** BL-172 (the sentinels this generalizes), BL-072 (the TDD gate), BL-006/BL-010 (the sibling gate), and this repo's own `.claude/worktrees/` agent workflow (where the blindness is live).

---

## BL-177: `_run_idempotent_backfill` has no structural projectless/in-framework guard — two sibling blocks write outside generated projects today (`.claude/skills/`, BL-088 script copies)

**Logged:** 2026-07-24 (BL-174 WP-D adversarial verifier)
**Category:** Upgrade-path safety / framework-repo hygiene
**Severity:** Medium
**Status:** Open

`scripts/upgrade-project.sh`'s `_run_idempotent_backfill` runs its whole body inside a subshell that opens with `( cd "$PROJECT_ROOT" …`. `find_project_root` keys on `.claude/phase-state.json`; when that marker is absent — the framework repo itself, or any non-project cwd — `PROJECT_ROOT` is the empty string and **`cd ""` is a SILENT rc-0 no-op under `set -euo pipefail` on bash 3.2** (empty operand → success, cwd unchanged), so the subshell proceeds in the INVOCATION directory rather than a project root. Nothing downstream re-checks that we are in a real project.

The `--backfill-only` path reaches this with **no framework guard**: it fires `_bl015_sentinel_guard`, then `_run_idempotent_backfill`, then hits the `--backfill-only` short-circuit (`exit 0`) BEFORE `guard_not_in_framework` — which lives only on the full-upgrade / `--sync-framework` / `--plan` paths. So an in-framework `upgrade-project.sh --backfill-only` executes the entire backfill body against the framework tree. (`guard_not_in_framework` *does* refuse the identical cwd on the paths that call it, confirming the write is unintended — `--backfill-only` simply never gets there.)

**Six-block gate survey of `_run_idempotent_backfill`** (what protects each writer):
1. host-aware CI-template migration — **shape-gated only** (`[ -d templates/pipelines/ci ] && [ ! -d …/github ]`), no project marker.
2. manifest host-field backfill — **manifest-gated** (`[ -f .claude/manifest.json ]`).
3. BL-030 manifest backfill (incl. the `last-checked-commit.txt` / `bypass-audit.json` writes) — **manifest-gated**.
4. BL-174 gitignore backfill — **manifest-gated** (added in the BL-174 WP-D fix, after an unguarded draft leaked into the framework repo's own `.gitignore`).
5. vendored-skills sync — **gated only on the SOURCE dir** (`[ -d "$ORCHESTRATOR_ROOT/templates/generated/skills" ]`); **NO project gate**.
6. BL-088 source-closure copy — **gated only on cwd shape** (`[ -d scripts ]`); **NO project gate**.

**Two live leaks today.** Blocks 5 and 6 write into the invocation cwd whenever `_run_idempotent_backfill` runs projectless:
- The skills sync does `mkdir -p .claude/skills` and copies each skill's `SKILL.md` / `NOTICE`. Its self-copy guard `[ "$skill_src" -ef "$skill_dest/" ]` **never matches** here, because the source (`templates/generated/skills/X`) and destination (`.claude/skills/X`) are DIFFERENT paths — the `-ef` guard only skips a true in-place self-copy, not a framework→`.claude/skills` copy. The framework repo's own **untracked `.claude/skills/` (dated ~2026-06-28, a month old at logging) is standing residue of exactly this leak.**
- The BL-088 block `cp`s `lib/tdd-classify.sh`, `lib/phase2-state.sh`, `lib/cdf-refresh.sh`, `run-phase3-validation.sh` into `scripts/lib/…` of the invocation cwd, its `-ef` guard likewise skipping only a genuine self-copy.

Net: BL-174 closed the *gitignore* instance of this class by manifest-gating block 4, but the **structural** gap — an unguarded subshell that silently runs in whatever cwd it is invoked from — remains, and blocks 5 and 6 still write outside generated projects.

**Fix shape:**
- Add ONE structural marker check at the TOP of the `_run_idempotent_backfill` subshell — `[ -f .claude/phase-state.json ] || [ -f .claude/manifest.json ] || { print_info "…"; exit 0; }` (the subshell `exit 0` returns from the function without mutating anything). **No current legitimate path regresses:** `find_project_root` already keys on `.claude/phase-state.json`, so any real project reached via a non-empty `PROJECT_ROOT` has that marker present in the cd'd cwd; only the projectless/in-framework case is refused.
- PLUS call `guard_not_in_framework` on the `--backfill-only` entry (before the backfill) so an in-framework invocation refuses **LOUDLY** rather than silently no-opping — defense in depth matching the full-upgrade / sync paths.
- Correct the BL-174 block comment so it no longer implies every sibling block is manifest-gated (done as a comment-only change in the BL-174 WP-D follow-up).
- **Mutation proof:** a projectless fixture (a `scripts/` dir present, a skills source visible via `ORCHESTRATOR_ROOT`, but NO `.claude/manifest.json` and NO `.claude/phase-state.json`) → after the structural guard, `_run_idempotent_backfill` performs ZERO writes (no `.claude/skills/`, no `scripts/lib/` copies, no `.gitignore` append); excise the guard → the skills sync and BL-088 copies reappear (RED).

**Escalation 2026-07-27 — the leak was briefly COMMITTED, which raises the priority.** The untracked
`.claude/skills/` residue this entry documents was swept into a commit by a `git add -A` run from a
worktree that carried it (`bb69806`), and reached `main` via PR #275 — so for a short window the
framework repo TRACKED 7 files of leak output (`grill-with-docs`, `session-handoff`, `sweep-triage`,
`zoom-out`), duplicating the canonical copies in `templates/generated/skills/`. Untracked again and
added to the repo's own `.gitignore` alongside the `.claude/upgrade-snapshots/` precedent, with a
comment stating that the ignore is a TRAP-DISARM, not a fix.

Three consequences for this entry:

1. **PRIORITY rises; the `**Severity:** Medium` field is unchanged and correct.** The leak is not
   merely untidy — it is one `git add -A` away from becoming repo content, and this repo's agent
   workflow runs `git add -A` routinely. Measured 2026-07-27, the untracked residue sits in **3**
   worktree checkouts (all pre-dating `bb69806`; the total count drifts constantly as runs create
   and destroy them, so only the numerator is durable) **and the main checkout** — and the main
   checkout is where `git add -A` actually runs, which is what makes it reachable. *(An earlier
   draft of this paragraph claimed "every `.claude/worktrees/agent-*` checkout"; the pre-PR review
   measured 1 of 27 and refuted it. Corrected here rather than left in the audit trail.)*

2. **The leaked files are NOT inert, so "delete the residue" is not a cleanup instruction.** Claude
   Code auto-discovers project-scoped skills at `.claude/skills/`, so while these sit on disk they
   ARE this repo's project skill set — verified 2026-07-27: `grill-with-docs`, `session-handoff` and
   `sweep-triage` are live in agent sessions here and absent from `~/.claude/skills/`, and `zoom-out`
   is correctly missing from the model-invocable list because its own frontmatter sets
   `disable-model-invocation: true`, which proves the harness parsed these files. Deleting them
   silently switches four skills off — and the new `.gitignore` line would hide that happening.
   **The disposition is therefore an open decision, not housekeeping:** either delete deliberately,
   or track them on purpose the way `.claude/agents/pr-reviewer.md` already is. Do not fold that
   choice into an unrelated fix.

3. **A `.gitignore` line is NOT the fix and must not be mistaken for one.** It disarms the
   `git add -A` trap in THIS repo only. The structural guard at the top of the
   `_run_idempotent_backfill` subshell (see the fix shape above) is still required, and until it
   lands the leak keeps being written — simply no longer visible to `git status`, which is worse for
   detection. Whoever implements the guard should re-examine whether the ignore line should come
   back out so a recurrence announces itself.

**Related:** BL-174, BL-080, BL-081.

---

## BL-178: Case-insensitive-filesystem materialization collision — case-only-differing staged files overwrite each other in the index temp tree, and the vuln blob can be lost

**Logged:** 2026-07-24 (BL-131/132 WP-A fable verifier, F4)
**Category:** Bug / security enforcement — index-materialization edge case (case-insensitive FS)
**Severity:** Low
**Status:** Closed — shipped + merged 2026-07-25 (PR #270 `b0b60aa`), per this entry's own build-note condition ("Status stays Open pending PR + merge"). `# BL-178-PER-INDEX-DIR` in `scripts/lib/hook-templates.sh`: materialization moved from one flat `mktemp -d` tree to per-staged-entry subdirs (`$soif_idx_tree/<n>/<relpath>`, `<n>` = staged position), so no two staged paths can collide, and the path-mapping `sed` grew a `[0-9][0-9]*/` arm so the operator still sees the REAL repo-relative path — never a temp path, never a bare index number (re-verified for deeply-nested paths and paths containing spaces). Landed in the SAME diff as the R-270-1 gitlink security regression by design: both rewrite the same loop and the same `soif_idx_files` population, so splitting them meant rewriting it twice with a near-certain conflict. Proof: `tests/test-bl132-sast-index-scan.sh` `T-index-case-collision`, watched-RED first against the flat tree (`[OK] semgrep: SAST ran on 2 staged file(s)` with the vuln COMMITTED) then GREEN; the case-only pair is built with `git update-index --add --cacheinfo` because a case-INSENSITIVE checkout physically cannot hold both worktree files while the index can, and the case LOUD-SKIPs on a case-sensitive filesystem rather than passing vacuously. Mutation-proof M2: revert the per-index layout (dest + `sed` in sync) → RED → restore → GREEN. **Side effect now tracked as BL-182:** the extra `/<n>/` segment on top of the `mktemp -d` root shortens the longest repo-relative path the temp tree can represent.

The BL-132 SAST arm materializes each staged blob into a single `mktemp -d` tree at its repo-relative path (`# BL-132-INDEX-SCAN` in `scripts/lib/hook-templates.sh`). On a case-INSENSITIVE filesystem (macOS APFS default, Windows NTFS), staging two files whose paths differ only in case — e.g. `Widget.ts` (containing the vuln) and `widget.ts` (clean) — collides in the temp tree: the second `git cat-file blob` write lands on the SAME on-disk path, overwriting the first blob. If the clean file materializes last, the vuln blob is lost and the commit lands `[OK]` (verifier F4, reproduced). FIX B (explicit file targets) does NOT close this — the collision happens at materialization, before target selection — and the F2 content-size guard does not catch it (each write is internally consistent; it is the earlier blob that was clobbered).

**Honest calibration:** the trigger stage is deliberately unusual — git itself warns on case-only-differing paths on a case-insensitive checkout, and few real trees carry them. This is a materialization-fidelity gap, not a routine bypass.

**Fix shape:** materialize into per-index SUBDIRS keyed by the staged-file INDEX (`$tree/<i>/<relpath>`) so no two staged paths can collide, collect the per-index dest into `soif_idx_files`, and update the path-mapping `sed` to strip the `<tree>/<i>/` prefix (recovering the real repo-relative path). Mutation-proof: stage `Widget.ts` (vuln) + `widget.ts` (clean) on a case-insensitive FS → the vuln must still be REFUSED.

**Build note (2026-07-25, branch `fix/bl131-bl132-sast-hardening`):** Fixed as recorded, under the marker `# BL-178-PER-INDEX-DIR` in `scripts/lib/hook-templates.sh`. **Landed in the SAME diff as the R-270-1 gitlink security regression** — both defects rewrite the same materialization loop and the same `soif_idx_files` population, so shipping them separately meant rewriting that loop twice with a near-certain conflict (flagged by a cross-PR critic). Materialization moved from one flat `mktemp -d` tree to per-staged-entry subdirs (`$soif_idx_tree/<n>/<relpath>`, `<n>` = staged position), and the path-mapping `sed` grew the `[0-9][0-9]*/` arm so the `<n>/` segment is stripped back off finding paths — the operator still sees the REAL repo-relative path, never a temp path and never a bare index number (re-verified for deeply-nested paths and paths containing spaces). Proof: `tests/test-bl132-sast-index-scan.sh` `T-index-case-collision`, watched-RED first against the flat tree (`[OK] semgrep: SAST ran on 2 staged file(s)` with the vuln COMMITTED) then GREEN. The case-only pair is built with `git update-index --add --cacheinfo` because a case-INSENSITIVE *checkout* physically cannot hold both worktree files while the *index* can and routinely does (a tree authored on Linux, cloned on macOS); git's `:<path>` index lookup was confirmed case-EXACT there, and the case LOUD-SKIPs on a case-sensitive filesystem rather than passing vacuously. Mutation-proof M2: revert the per-index layout (dest + `sed` reverted in sync) → `T-index-case-collision` RED → restore → GREEN. Status stays **Open** pending PR + merge.

**Related:** BL-132 (the index-materialization arm), BL-131 (the ruleset).

---

## BL-179: Pre-commit SAST skips a rename-and-edit commit ENTIRELY and SILENTLY — `soif_staged` filters `ACM`, so a renamed file is reported `R` and excluded

**Logged:** 2026-07-25 (PR #270 final-gate adversarial review, R-270-2)
**Category:** Bug / security enforcement — commit-time SAST target selection (silent-success class)
**Severity:** High
**Status:** Closed — shipped + merged 2026-07-27 (PR #274 `24ac0bd`). `# BL-179-STAGED-FILTER`: the SAST staged-read filter moved `ACM` → `ACMRT`, so a rename-and-edit commit is scanned instead of skipped entirely and silently. Landed in the same rewrite of the emitted SAST region as BL-182 by design — both touch the same loop and the same `soif_idx_files` population. **AS SHIPPED IN PR #274 the BL-125 test-exec arm was deliberately NOT changed** — it remained `ACMDR`, and `# BL-179-STAGED-FILTER`'s shipped comment says why: "They are not the same decision as the BL-125 test arm's ACMDR (~120 lines below) and must not be copied from it." **PR #280 (`8f36382`) later moved that arm to `ACMDRT` under `# BL-179-TESTARM-FILTER`, for its own reason** — so on `main` today the arm is `ACMDRT` and the quoted comment beside it is itself stale. Both statements are true of their own commit and neither is true of the other; that is the point of stamping them. (A first draft of this closure credited that change to PR #274, where it did not happen. Preserved as BL-196's worked example.)

The commit-time SAST arm builds its target list from
`git diff --cached --name-only --diff-filter=ACM -z` (the NUL-delimited `soif_staged`
read that feeds `# BL-132-INDEX-SCAN` in `scripts/lib/hook-templates.sh`, emitted by
`soif_precommit_region_body`). `diff.renames` defaults to **true**, so git reports a
rename as status `R` — which `ACM` **excludes**. A commit that renames a file *and*
edits it in the same commit therefore presents **zero** staged entries to the scanner.

Because the whole arm is wrapped in `if [ "${#soif_staged[@]}" -gt 0 ]` with **no
`else`**, zero entries means the scanner is not merely skipped — it produces **no
output at all**: no `[OK]` receipt, no `[BLOCKED]`, and *not even* the
`soif_sast_not_enforced` / `SAST NOT ENFORCED` loud-NOTRUN that every other
can't-scan path routes to (`# BL-112-SAST-NOTRUN`). The operator is told nothing
whatsoever, which is precisely the BL-112 dishonesty class this arm exists to end.

**Evidence (reproduced through the real emitter, the real `.git/hooks/pre-commit`, and
a real `git commit`):** land a clean `old.ts`, install the emitted hook, then
`git mv old.ts new.ts` + introduce `pane.innerHTML = userText` and stage it.

```
git diff --cached --name-status          -> R067  old.ts  new.ts
--diff-filter=ACM    (the SAST arm)      -> (empty)   count=0
--diff-filter=ACMDR  (the BL-125 arm)    -> new.ts    count=1
--diff-filter=ACMR   (proposed)          -> new.ts    count=1
commit verdict = COMMITTED ; `git show HEAD:new.ts` still contains innerHTML
hook output: ZERO semgrep/SAST lines
```

**PRE-EXISTING — deliberately NOT fixed in PR #270.** The `--diff-filter=ACM -z` line
is **byte-identical on `main` (`ed406c8`) and on the PR head (`0765612`)**, and the
behaviour was verified identical on both. It is neither introduced nor worsened by
that PR, so it is filed rather than folded in — the PR's own regression (R-270-1B,
the `:<stage>:<path>` collision) is a separate surface in the same loop.

**Severity argument.** This repo treats silent success in a security lane as
**block-class**, and on the defect's own merits that is the right call: the trigger is
a *routine* refactor (rename-and-edit is one of the most common commit shapes), the
failure is total (the scanner never runs on the renamed file's content), and it is
*quieter* than every other failure mode in the arm — the gitlink and stage-syntax bugs
at least shout NOTRUN. Rated **High** rather than Critical only because the pre-push /
CI SAST lanes still scan the tree afterwards, so the commit-time gate is the tripwire
that is lost, not the last line of defence. It is **not** a merge blocker for PR #270
purely because it is pre-existing and unchanged there.

**The fixed sibling is ~120 lines away in the same emitted region.** The BL-125
test-exec arm (`# BL-125-COMMIT-TESTS`, the `soif_test_src=` assignment) already uses
`--diff-filter=ACMDR`, carrying an explicit "Verifier M1" comment stating that `D` and
`R` are included **on purpose** because "a commit that DELETES or RENAMES the sanitizer
is exactly the regression this arm exists to stop, and the old ACM filter skipped it
while printing the ... receipt (a false receipt — the dishonesty class this arm
fights)". The SAST arm never received the same correction.

**Fix shape:** change the `soif_staged` read to `--diff-filter=ACMR`.
- `R` must be **added**: a renamed file has staged content, and the `-z`/`--name-only`
  output for an `R` entry is the **destination** path, which `git cat-file blob
  ":0:<dest>"` resolves correctly (`# BL-132-STAGE0-REF`) — so no materialization
  change is needed.
- `D` must stay **excluded** (unlike BL-125's `ACMDR`): a deleted file has no staged
  content to scan, so including it would hand the loop an index entry with no blob,
  which is exactly the "one bad entry blinds the whole commit" shape that R-270-1 and
  R-270-1B already cost this arm twice.
- **Also close the no-`else` silence** while here: an empty `soif_staged` on a commit
  that *did* stage something should route to `soif_sast_not_enforced`, not to nothing.
  Rename-only (no edit) commits are the residual case and deserve a receipt.

**Mutation-proof sketch:** new watched-RED fixture in
`tests/test-bl132-sast-index-scan.sh` — land a clean file, `git mv` it while
introducing an `innerHTML` sink, commit. RED pre-fix: `COMMITTED`, HEAD moves, the
vuln is in `git show HEAD:<dest>`, and the log contains **no** `semgrep`/`SAST` line at
all (assert the *absence* of output, not just the absence of `[BLOCKED]` — a
`[BLOCKED]`-only assertion would also pass on a silent skip). GREEN post-fix:
`REFUSED` + `[BLOCKED]` + the **destination** path named. Then mutate
`ACMR` -> `ACM` -> RED -> restore -> GREEN. Add a control that a plain rename with **no**
content change still lands (no false block), and one that a staged **deletion** alone
does not push the commit into a bogus NOTRUN.

**Build note (2026-07-26, branch `worktree-wf_79ea23a3-eb4-3`):** Fixed under the new marker `# BL-179-STAGED-FILTER` in `scripts/lib/hook-templates.sh`, **in the same diff as BL-182** — both rewrite the same emitted SAST region (`soif_precommit_region_body`), so shipping them apart meant rewriting that region twice with a near-certain conflict. The staged-target read is now `--diff-filter=ACMR -z`, and BOTH halves of that filter are pinned. **`R` is in:** `diff.renames` defaults true, so a rename-and-edit commit is one status-R entry that `ACM` excluded; `soif_staged` came back EMPTY and the arm's `-gt 0` wrapper had **no `else`**, so the scanner produced no output whatsoever. `--name-only -z` emits the DESTINATION for an R entry and `:0:<dest>` resolves to its staged blob, so the materialization loop needed no change at all. **`D` deliberately stays out** — this is NOT the BL-125 arm's `ACMDR`: that arm must RUN TESTS when a sanitizer is deleted, this one must SCAN CONTENT, and a deleted path has no staged blob (`git cat-file -t ":0:<deleted>"` → exit 128, re-verified on git 2.50.1 here), so including it would manufacture a phantom unreadable entry — a fresh instance of the very class BL-182 retires. The no-`else` silence is closed by `# BL-179-EMPTY-STAGED`: an empty staged set routes to the same loud NOTRUN, so **the arm now has no silent path left**. Proof (`tests/test-bl132-sast-index-scan.sh`): `T-rename-edit-scanned` (R090 rename+edit → REFUSED, destination named), `T-rename-only-not-silent` (R100 → LANDS but is receipted), `T-delete-only-honest` (deletion-only → LANDS, receipted, never reaches the loop with a blob-less entry). All three assert through `any_sast_line()` — the **absence of an absence** — because a `! grep [BLOCKED]` assertion passes vacuously on a silent skip, which is exactly how this hole survived a suite that was 11/11 green. Watched-RED against the pristine lib: all three FAILED with "the SAST arm said NOTHING AT ALL" / "produced NO SAST output whatsoever", `verdict=COMMITTED`. Mutation proofs: `T-mutation-rename-filter` (ACMR→ACM → the destination goes unscanned and its XSS LANDS → restore → REFUSED + `[BLOCKED]`), `T-mutation-delete-filter` (ACMR→ACMDR → a deletion-only commit reports lost coverage on a phantom entry → restore → honest receipt, no phantom), `T-mutation-empty-staged-silence` (neuter the empty-staged report → a deletion-only commit is TOTALLY SILENT again → restore → receipted). **Fixture lesson worth keeping:** rename detection needs ≥50% similarity, and a 3-line file flipping `textContent`→`innerHTML` scores `A`+`D` — under which `ACM` *does* include the destination and the defect never triggers. The fixtures pad the file, re-probe `--name-status` (LOUD-SKIP if git disagrees), and assert the sink is really present in the staged destination blob; an early cut staged nothing at all (`git add -A -- old.ts new.ts` dies with "pathspec 'old.ts' did not match any files" because `git mv` already removed the source from BOTH index and worktree, and git aborts the whole add) and so produced a 100%-similar rename with no vuln in it — which the new validity probe now catches instead of passing. Green: `test-bl132` 23/23, `test-bl131` 17/17, `test-bl118` 6/6, `test-bl112` 13/13, `test-bl113` 17/17, `test-upgrade-sync-framework` 39/39, `run-lints` 11/11. Blast-radius sweep of every other suite that consumes the emitted hook, also green: `test-bl099-guard-coverage` 53/53 (the `--error` registry anchor still RED-under-neuter), `test-bl125-commit-test-exec` 16/16, `test-bl163-blocked-ledger` 7/7, `test-bl161-ledger-real-events-only` 7/7, `test-freshness-check` 26/26, `test-verify-install-fix-functions` 16/16. Status stays **Open** pending PR + merge.

**Remediation note (2026-07-26, branch `worktree-wf_79ea23a3-eb4-9`) — the filter is `ACMRT`, not `ACMR`.** An adversarial verifier returned **major_concerns** against the build note above (R-WPC-1) and was **right**: `--diff-filter=ACMR` also excludes **`T` (TYPE CHANGE)**, and a T entry is a perfectly readable staged blob. Reproduced independently through the real emitter and a real `git commit`: seed `link.ts` as a **symlink**, replace it with a **regular file** carrying `pane.innerHTML = userText`, stage a clean sibling `app.ts` → `--name-status` reports `M app.ts` / `T link.ts`, `ACMR` sees only `app.ts`, `git ls-files -s link.ts` is `100644 …` and `git cat-file -t :0:link.ts` is `blob` — and the commit printed **`[OK] semgrep: SAST ran on 1 staged file(s)`** and LANDED with the sink in the tree (`git show HEAD:link.ts | grep -c innerHTML` → 1). This was **not a regression** — the identical A/B against the pre-BL-179 lib behaves the same — but the build note above shipped the claim that the hole was CLOSED, into `docs/platform-modules/web.md` and into the `# BL-182-NO-UNEARNED-RECEIPT` reasoning, and that claim was false. **The lesson generalises: the filter is part of the receipt's contract.** `# BL-182-NO-UNEARNED-RECEIPT` can only fire for entries the loop was GIVEN; a status letter missing from `--diff-filter` truncates the TARGET SET *before* the loop, so `soif_idx_unread` stays empty, no guard fires, and `N` silently counts a subset. Fix: `--diff-filter=ACMRT -z` at `# BL-179-STAGED-FILTER`. **`T` is safe where `D` is not**, verified in every direction on git 2.50.1 here: `git cat-file -t ":0:<path>"` returns `blob` for a T entry both ways — symlink→file (index mode 100644) and file→symlink (index mode 120000) — and for gitlink→file, so unlike `D` it never manufactures a phantom unreadable entry and the materialization loop still needs no change; a hypothetical →gitlink T would present mode 160000 and be absorbed by the existing `# BL-132-GITLINK-SKIP`, and a bare permission flip is reported `M`, not `T`. New proof (`tests/test-bl132-sast-index-scan.sh`): **`T-typechange-scanned`** — the symlink→file materialization above, asserting the ABSENCE of the `[OK]` receipt as its own arm (not merely "it committed", because a NOTRUN would satisfy that and a NOTRUN is honest). Watched-RED against the pre-fix lib: `[FAIL] … an UNEARNED [OK] receipt — the staged TYPE CHANGE was excluded by --diff-filter (letter T) … receipt: [OK] semgrep: SAST ran on 1 staged file(s) …; sink landed in HEAD:link.ts=1`, tally `Results: 23 passed, 1 failed (0 skipped)`. Mutation proof **`T-mutation-typechange-filter`** (ACMRT→ACMR → unearned `[OK]` + sink LANDS → restore → REFUSED + `[BLOCKED]`); the source-level mutation of the marked line gave `Results: 21 passed, 4 failed` and restored to `25 passed, 0 failed`. The **three filter-mutation cases now attack one letter each** — `T-mutation-rename-filter` ACMRT→**ACM**T (R), `T-mutation-typechange-filter` ACMRT→ACM**R** (T), `T-mutation-delete-filter` ACMRT→ACM**D**RT (D) — because a mutant that drops two letters goes RED while proving nothing about which one carried the weight. All three anchors were retargeted in lockstep, and their exactly-once counters did exactly what they are for: under the source mutation all three reported `MIS-TARGETED` rather than silently mutating nothing. Corrected alongside: the `# BL-179-EMPTY-STAGED` residual-shapes list (a type change is **not** a content-free shape and no longer appears there), the receipt comment (it now states the filter as the second precondition of "complete coverage"), the operator-facing `no scannable staged file content (…)` enumeration, and the `docs/platform-modules/web.md` paragraph. Also, from the same review (R-WPC-2, minor): the F2 size-mismatch recovery point's `soif_idx_unread` recording was pinned only STRUCTURALLY, so `T-mutation-content-guard` now additionally asserts the entry is NAMED on both its F2 arms — watched-RED by removing the recording (`then continue; fi`), which gave `[FAIL] … NOTRUNed but never NAMED app.ts` and `Results: 23 passed, 2 failed`. Green after: `test-bl132` **25/25** (was 23), `test-bl131` 17/17, `test-bl118` 6/6, `test-bl112` 13/13, `test-bl113` 17/17, `test-upgrade-sync-framework` 39/39, `run-lints` 11/11 — all exit 0. Blast radius (the emitted hook's bytes changed, so every consumer was re-run): `test-bl125-commit-test-exec` 16/16 — the sibling arm whose `ACMDR` filter this one deliberately does NOT copy — and `test-bl099-guard-coverage` `== Total: 53 | Pinned: 53 | Failed: 0 | Skipped: 0 ==`, both exit 0. **Lane honesty (R-WPC-5):** of everything cited above, `test-bl132`, `test-bl131`, `test-bl118`, `test-upgrade-sync-framework` and `test-bl125-commit-test-exec` are in the `tests.yml` **unit fast lane** and therefore gate the PR; `test-bl112`, `test-bl113` and `test-bl099-guard-coverage` are **full-lane only** (`workflow_dispatch`) and were run locally, so their green is evidence but not a gate. **NOT fixed here, deliberately (R-WPC-3, informational):** the Phase≥2 schema-drift advisory in the same file still reads `--diff-filter=ACM`, so a rename-and-edit of `schema.prisma` / `models.py` / `*.entity.ts` never trips it. That is a different arm with different semantics and no test coverage of its own; folding it in unproven would repeat the mistake this note is correcting. Status stays **Open** pending PR + merge.

**Remediation note #2 (2026-07-26, branch `worktree-wf_79ea23a3-eb4-15`) — this entry's filter is UNCHANGED; the round's one blocking finding landed on BL-182's arm.** A second adversarial round returned **major_concerns**, and its single blocking finding (R-WPC2-1) was a test-coverage gap in the `# BL-132-GITLINK-SKIP` mode predicate's REJECT direction — see **BL-182's remediation note #2** for the reproduction, the fix, the watched-RED and the mutation proof. `--diff-filter=ACMRT` at `# BL-179-STAGED-FILTER` was re-examined and stands; all three one-letter filter mutations (`T-mutation-rename-filter` ACMRT→ACMT, `T-mutation-typechange-filter` ACMRT→ACMR, `T-mutation-delete-filter` ACMRT→ACMDRT) re-ran GREEN, as did `T-mutation-empty-staged-silence`, in `Results: 27 passed, 0 failed (0 skipped)`, `EXIT=0`. **R-WPC2-3 (informational, deliberately still NOT fixed):** the verifier independently re-derived R-WPC-3 — the Phase≥2 schema-drift advisory in the SAME emitted hook still reads `--diff-filter=ACM`, so a rename-and-edit (status `R`) or a type change (status `T`) of a schema file never trips it: the identical filter-letter defect this entry fixed one arm above. The verifier **agreed with the deferral** (different arm, non-blocking advisory, no test coverage of its own) and recorded it only so it is not lost; it stays deferred here on the same reasoning — folding it in unproven is the mistake remediation note #1 already had to correct once. Status stays **Open** pending PR + merge.

**Related:** BL-132 (the index-materialization arm this filter feeds), BL-125 (the
sibling arm that already fixed exactly this filter defect), BL-112 (the
silent-vs-loud SAST receipt contract), BL-182 (the all-or-nothing `break` in the
same region, fixed in the same diff).

---

## BL-180: init.sh's INTERACTIVE path never resolves enforcement_level — every hand-run scaffold is born with `enforcement_level: ""` and NO filesystem gate

**Logged:** 2026-07-25 (surfaced by the WP2 planner during anchor verification; empirically confirmed by a dedicated pty A/B)
**Category:** Bug / enforcement gap (BL-030 surface, interactive scaffold birth site)
**Severity:** HIGH — the default operator UX (`./init.sh`, no flags) produces a project whose strict-mode commit gate was never installed, while every diagnostic reports the project as strict.
**Status:** Closed — shipped + merged 2026-07-27 (PR #273 `3ad2bf7`). The interactive `init.sh` path now resolves `enforcement_level` and installs the filesystem gate, so a hand-run scaffold is no longer born with `enforcement_level: ""` while every diagnostic reports it as strict. Filed and fixed in the same wave; the defect was that the NON-interactive path did both and the interactive path did neither, so the gap was invisible to anyone testing with flags.

`ENFORCEMENT_LEVEL=""` at top-of-file. The only assigner is the `# BL-030: resolve enforcement_level`
block, which sits INSIDE the `if [ "$NON_INTERACTIVE" = true ]` arm of `main`. The `else` arm runs only
`check_prerequisites` + `collect_project_info`, and `collect_project_info` has no enforcement-level
prompt and never assigns the variable — there is no interactive enforcement-level prompt anywhere in
init.sh. The empty value flows verbatim into all four manifest-seed `jq` calls and the
`enforcement_level_set` bypass-audit row in `prepare_initial_state_for_commit`, and makes the
`if [ "$ENFORCEMENT_LEVEL" = "strict" ]` guard around `install-filesystem-gates.sh --install` a no-op.
`CONFIRM_PITFALLS` is set in the same non-interactive-only block and is likewise never resolved.
Note the sharp edge: that block ALREADY contains the exact default this entry asks for
(`[ -z "$ENFORCEMENT_LEVEL" ] && ENFORCEMENT_LEVEL="strict"`) — it is simply unreachable from the
interactive arm, so the fix is to hoist an equivalent line out of the dispatch, not to invent one.

**Evidence — A/B on the same combo (web / standard / personal / production / typescript).** Side A: a
REAL interactive `init.sh` (no flags) driven over a pty via `expect`, so `helpers-core.sh::prompt_input`
takes its interactive branch. Hermetic — a stub `gh` refused at `gh auth status`, before `gh repo create`;
`git remote -v` empty on both sides. Side B: same combo via `--non-interactive` flags.

| | interactive (A) | non-interactive (B) |
|---|---|---|
| `jq '.enforcement_level' .claude/manifest.json` | `""` | `"strict"` |
| `.git/hooks/framework-gate.sh` | ABSENT | present (2341 B) |
| `grep -c 'SOIF framework gate (BL-030)' .git/hooks/pre-commit` | `0` | `1` |
| bypass-audit init row `enforcement_level_at_event` | `""` | `"strict"` |

Committed, not transient: `git show HEAD:.claude/manifest.json | jq '.enforcement_level'` → `""`.

**Nothing downstream repairs it — and it is self-concealing.**
- `verify-install.sh --auto-fix` (inside init AND standalone): rc=0, "Passed: 83 / Auto-fixable: 0 /
  All checks passed. Installation is healthy." It verifies the installer was COPIED, never that the
  hook was INSTALLED.
- `upgrade-project.sh`'s BL-030 backfill — the block that would re-run the installer — is gated on
  `! jq -e '.enforcement_level' …`. `jq -e` on `""` prints `""` and EXITS 0 (re-confirmed at filing),
  so the block is skipped. **An empty value is strictly worse than a missing one:** it defeats the
  migration written for exactly this.
- `read_enforcement_level` (scripts/lib/enforcement-level.sh) maps `""` → `strict` via its
  `case … *) echo "strict"` arm, so every lib-mediated diagnostic reports the project as strict while
  the enforcement is absent.

**Blast radius, permanent, per interactively-scaffolded project:** (1) `process-checklist.sh
--check-commit-ready` never runs at commit time; (2) `pre-commit-gate.sh --terminal-mode` never runs,
losing BOTH the BL-072 TDD-ordering gate and the BL-006 Build-Loop message check; (3) no
`terminal_commit_blocked` / `__record_pass` / `__record_block` rows, so the BL-161/163/171 ledger is
silent about its own absence; (4) every raw `jq -r '.enforcement_level // "strict"'` reader
(`escalate-to-user.sh`, `hooks/bypass-detector.sh`, `lib/hook-templates.sh`) stamps `""` — `//` does
NOT fire on an empty string. This is BL-112's hollow-gate class reproduced at the birth site.

**Test gap (part of the finding):** NO test exercises a real interactive scaffold.
`tests/test-enforcement-level-init.sh` is 100% `--non-interactive`; every piped fed-sequence `init.sh`
invocation in `tests/` is `--dry-run`, which returns before `create_project` and never writes a
manifest. The whole interactive `create_project` path is untested end-to-end.

**Fix shape:** one line immediately AFTER the `if [ "$NON_INTERACTIVE" = true ] … else … fi` dispatch in
`main` (before `log_section "Project Configuration"`), marked `# BL-180-ENFORCEMENT-DEFAULT`:
`[ -z "$ENFORCEMENT_LEVEL" ] && ENFORCEMENT_LEVEL="strict"` — inert for the non-interactive arm, which
always assigns first. Companion: emit `Enforcement: $ENFORCEMENT_LEVEL` from `dry_run_summary` to
**stdout** (`log_line` only writes to the log file), so the existing piped `--dry-run` fixture can pin
the interactive path in the UNIT lane without a pty. Aggregator-only companion: a pty-driven
(`expect`, falling back to `script`) real-scaffold test asserting manifest + `framework-gate.sh`, with a
LOUD SKIP when neither is available.

**Mutation proof:** delete the marked line → interactive A/B goes RED (`""` + gate absent) → restore →
GREEN (`strict` + gate present), non-interactive control identical both ways.

**Adjacent, flagged not filed separately (same structural class — fix while in here):**
`NO_REMOTE_CREATION="$ARG_NO_REMOTE_CREATION"` is also assigned only inside
`collect_inputs_non_interactive`, so `--no-remote-creation` is silently inert interactively. `main`'s
"Input flags require --non-interactive; ignoring" warning covers only
`ARG_PROJECT$ARG_PLATFORM$ARG_DEPLOYMENT$ARG_LANGUAGE` — not that flag, nor `ARG_CONFIRM_PITFALLS`
(which IS part of the BL-030 surface).

**Build note (2026-07-26, worktree branch `worktree-wf_79ea23a3-eb4-1`):** Fixed exactly as the
entry prescribed, under `# BL-180-ENFORCEMENT-DEFAULT` in `init.sh::main` —
`[ -z "$ENFORCEMENT_LEVEL" ] && ENFORCEMENT_LEVEL="strict"`, hoisted out of the
`if [ "$NON_INTERACTIVE" = true ] … else … fi` dispatch and placed immediately after it, before
`log_section "Project Configuration"`. The `&&`-list form was **verified safe under
`set -euo pipefail` on this host's bash 3.2.57 before being written** (`X="light";
[ -z "$X" ] && X="strict"; echo` survives, rc=0 — a failing mid-script AND-list does not trip
`set -e`), which is also why the pre-existing sibling inside the BL-030 choosable arm has always
been safe. `docs/builders-guide.md`'s "`strict` (default)" claim is now TRUE on every entry path
rather than only the non-interactive one, so no doc edit was needed.

**Observability companion** `# BL-180-DRYRUN-ENFORCEMENT` in `dry_run_summary` emits
`  Enforcement: $ENFORCEMENT_LEVEL` on **stdout**. This is load-bearing, not cosmetic: the sibling
`log_line` calls write to the log FILE only, and that invisibility is exactly why every
fed-sequence `--dry-run` fixture in the repo was blind to a defect sitting in plain sight. The
value is echoed **verbatim** — never `// "strict"`-defaulted — so an unresolved level surfaces as
an empty field instead of being cosmetically repaired at the reporting layer.

**CONFIRM_PITFALLS — considered and deliberately NOT given the same treatment** (reasoning
recorded in the marker comment). It is not the same defect: (a) `ENFORCEMENT_LEVEL`'s top-of-file
`""` is not a legal value, whereas `CONFIRM_PITFALLS=0` already **is** its correct interactive
value; (b) its only semantic is permission to DOWNGRADE below strict, and the interactive arm
offers no downgrade to authorize — 0 is correct, not merely safe; (c) its other consumer is the
bypass-audit birth row's `confirmed_pitfalls: ($confirmed=="1")`, so defaulting it to 1 would
write a FALSE attestation ("operator accepted the pitfalls") into the audit trail of an operator
who was never asked. Any non-zero default widens the bypass surface instead of closing it.

**Tests — both watched-RED first.** (1) `tests/test-bl180-interactive-enforcement.sh` (7 cases,
fast, pty-free): feeds the wizard's `prompt_choice` sequence to `init.sh --dry-run` and asserts the
resolved level, with three NON-INTERACTIVE controls. Menu ordinals are **re-derived at run time**
from the same globs/markers `collect_project_info` uses (`platform-modules/*.md` →
`release/github/*.yml` → `other`; `ci/github/*.yml` filtered by the
`# solo-orchestrator: platforms=` marker), not hardcoded — a stale ordinal is how the aggregator's
TEST 7 fixture broke before BL-136 — and the run is bound to the resolved combo so a drifted
derivation fails loudly instead of pinning the wrong project shape. Independently re-derived to
`web=4 / typescript=7`, matching TEST 7. **T5 is the inertness proof**: non-interactive
`--enforcement-level light --confirm-pitfalls` must still report `light`. (2)
`tests/test-bl180-interactive-scaffold-pty.sh` (10 cases, aggregator-ONLY): a REAL interactive
scaffold over a pty via `expect` (fallback `script`; LOUD SKIP with a printed reason when neither
exists — verified by running it under a PATH containing neither). Hermetic as to the NETWORK — Git
host is answered `other` (URL-paste path, never touches gh/glab/curl) and the clone-URL prompt is
answered EMPTY so `create_and_protect_remote` fails at its `[ -z "$remote_url" ]` guard **before**
`git remote add`; `init.sh` consequently returns 2 via `record_init_failure` — expected, printed
for diagnosis, and deliberately NOT asserted (pinning it would couple the test to unrelated
host-setup outcomes). The real guarantees sit on artifacts written by the earlier
`prepare_initial_state_for_commit`, plus T1 (the scaffold happened at all, so nothing below can
pass vacuously) and T7 (`git remote -v` is empty). **Both drivers were
actually exercised**, not just the primary: `SOIF_BL180_FORCE_SCRIPT_FALLBACK=1` forces the
`script(1)` path (BSD/util-linux invocation auto-detected by probing) and also reports
`10 passed, 0 failed`, so the fallback is not shipped-but-dead code.

**REMEDIATION (2026-07-26, verifier finding R-WPA-1 — CONFIRMED, the original claim was wrong).**
The pty fixture's "hermetic by construction" and `8 passed, 0 failed` claims held only on a host
where `CI` is unset. `helpers-core.sh::prompt_input`'s guard is
`[ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]` — the last two are checked
**independently of the tty**, so a pty does not defeat them. Re-confirmed here with an isolated
`expect` probe against the real function: with `CI` unset the call BLOCKS on `read` (interactive
branch); with `CI=true` it prints `[WARN] Non-interactive context: prompt_input("Project
directory") returning default …` and returns without reading. Every GitHub Actions runner exports
`CI=true`, and that is exactly the environment of the `full` lane this test is registered into.
The consequence is worse than a red test: `PROJECT_NAME` resolves to `""`, so
`PROJECT_DIR=$(prompt_input "Project directory" "$default_parent/$PROJECT_NAME")` resolves to
`"$default_parent/"` — the **parent directory of the checkout** — and a complete git-init'd
project is scaffolded OUTSIDE the fixture's own `mktemp -d`. Reproduced end-to-end from a
sandboxed COPY of the checkout (so the escape landed in a throwaway dir):
`CI=true bash tests/test-bl180-interactive-scaffold-pty.sh` → `Results: 0 passed, 1 failed`,
`EXIT=1`, and `$default_parent` went from `repo` to a full project tree
(`.claude .claude-backup .git .github … PROJECT_INTAKE.md scripts templates tests`).

Fixed under `# BL-180-PTY-INTERACTIVE-ENV` (three parts, all in the fixture):
* `unset CI` / `unset SOIF_NONINTERACTIVE` beside the existing `unset GITHUB_BASE_REF` — driving
  the INTERACTIVE branch is the whole point of this test, and the piped/non-interactive branch is
  the fast pin's job. This is the actual repair: same sandbox, same `CI=true` invocation, now
  `Results: 10 passed, 0 failed`, `EXIT=0`, `$default_parent` unchanged (`repo`).
* **T0a — pre-flight containment**, ordered BEFORE `init.sh` is ever spawned and the only
  assertion that can PREVENT rather than report an escape. It re-asserts `CI`/`SOIF_NONINTERACTIVE`
  are unset and that `$PROJ` is under `$TMP`, and on failure prints the directory the run WOULD
  have escaped to and exits **without spawning**. Watched-RED by deleting the `unset CI` line and
  re-running under `CI=true`: `[FAIL] T0a — REFUSING to spawn init.sh — CI is set ('true') …`,
  `Results: 0 passed, 1 failed`, and `$default_parent` **UNCHANGED** — i.e. the failure mode is now
  "fails loudly, writes nothing" instead of "writes a project outside the fixture".
* **T0b — post-run escape detector**, deliberately ordered before T1 because T1 `exit 1`s the
  moment the fixture manifest is missing, which is *precisely* the escape path — so pre-remediation
  the only message an operator saw named the one directory the project was NOT written to.
  `.claude/manifest.json` in the checkout's parent is the decisive artifact (no legitimate reason
  to exist there). Watched-RED by planting that file: `[FAIL] T0b — ESCAPE — a project was
  scaffolded into '…', OUTSIDE this fixture`, `Results: 9 passed, 1 failed`; removed → `10/10`.

**Also fixed — R-WPA-4 (weak assertion, the `2>/dev/null`-swallows-the-signal class).** T7's
hermeticity self-check passed both when no remote was attached AND when `$PROJ` was not a git
repository at all: the failing `git` call's stderr was discarded and its empty stdout was
indistinguishable from "no remotes". It now requires `$PROJ/.git` to exist and the `git` call to
succeed before an empty result is allowed to mean anything. Predicate-level watched-RED, OLD vs
NEW over three inputs: `not-a-repo` OLD=**PASS** / NEW=`FAIL(not a git repo)`;
`repo-no-remote` PASS/PASS; `repo-with-remote` FAIL/FAIL — the two legitimate cases agree, only
the vacuous one changes.

**CI driver (second half of R-WPA-1).** The `full` workflow job now installs `expect`
(`sudo apt-get install -y expect`, alongside the existing semgrep step). `expect` is the fixture's
SUPPORTED driver; the `script(1)` fallback is a positional stream that the test's own header calls
best-effort and that desynchronises wherever a conditional prompt appears. Without the install the
only end-to-end proof that a strict project is born with a REAL filesystem gate would silently
degrade to the fallback. The alternative the verifier offered — wrapping the delegate in the
`SUITE_SKIP_AGGREGATORS` gate its five real-scaffold siblings use — was **rejected**: that gate
would remove the test from the `core` shard, and since the `aggregators` shard runs only four
explicitly named files, the net effect would be **zero** CI lanes executing the only check that
catches a hollow strict gate. Installing the driver preserves the catcher; gating it would delete
it. Re-verified after remediation that the catcher still catches — the verifier's own MUT-3
(`[ "$ENFORCEMENT_LEVEL" = "strict" ]` → `"strict_REVIEWER_MUT3"`) against the REMEDIATED fixture:
`[FAIL] T4 — framework-gate.sh ABSENT`, `[FAIL] T5 — pre-commit lacks the 'SOIF framework gate
(BL-030)' block`, `Results: 8 passed, 2 failed`.

**Two findings the interactive path surfaced that no non-interactive fixture can.** (i) The nested
CDF installer (`~/.claude-dev-framework/scripts/init.sh`, invoked from `create_project`) has
`[ -t 0 ]`-guarded prompts — `Proceed with framework installation? (y/n)` and
`Install Context7 now?` — that exist ONLY on a pty; the first cut of the driver hung on them for
15 minutes, and the T1 "did the scaffold happen at all" guard reported it loudly with a transcript
tail rather than passing vacuously. Note `[ "$proceed" != "y" ]` there is case-SENSITIVE, so "Y"
aborts. (ii) The mutation proof caught a weak assertion **in my own test**: T5 originally grepped
`.git/hooks/pre-commit` for `framework-gate.sh` and PASSED with the gate provably absent, because
`scripts/lib/hook-templates.sh` names that file in explanatory COMMENTS emitted into every
generated hook. T5 now asserts `install-filesystem-gates.sh`'s MARK_OPEN sentinel
(`SOIF framework gate (BL-030)`), the string the filing's own A/B counted.

**Mutation proof (both directions, with a non-interactive control identical in both).** Delete the
`# BL-180-ENFORCEMENT-DEFAULT` line → fast pin `Results: 5 passed, 2 failed` (T1/T3 interactive RED
showing literally `Enforcement: `; T4/T5/T6 non-interactive controls GREEN) and pty
`Results: 6 passed, 4 failed` (T3 `enforcement_level=''`, T4 gate ABSENT, T5 sentinel absent, T6
audit row `''` — the filing's signature reproduced exactly). Restore → `7 passed, 0 failed` and
`10 passed, 0 failed`. (Re-run against the REMEDIATED fixture on 2026-07-26; the pty RED tally is
`6 passed, 4 failed` rather than the pre-remediation `4 passed, 4 failed` because T0a/T0b are two
additional PASSING cases under this mutation — the four caught consequences are unchanged, which
is the point: the R-WPA-1 repair did not blunt the catcher.)

**Registration:** both are registered in `tests/full-project-test-suite.sh` (enforcement-level
cohort), and neither is in the `.github/workflows/tests.yml` unit lane — both invoke `init.sh`,
and the documented membership rule is "does not invoke init.sh". Per BL-181 a green
`lint-tests-registered.sh` proves NEITHER fact here (its unit-lane arm exempts any file whose text
merely mentions `init.sh`), so both were verified BY HAND: grep of the aggregator for the two
delegate invocations, and a grep of the `tests=(` array confirming absence. The pty test's aggregator entry deliberately
CAPTURES output instead of `>/dev/null 2>&1` so its rc=0 LOUD SKIP cannot masquerade as a genuine
10/10 pass.

**LANE DECISION (2026-07-26, verifier findings R-WPA-2 + R-WPA-3) — RECORDED, not deferred.
The BL-180 surface is accepted as FULL-LANE-ONLY.** The original escalation rested on a measured
claim that was wrong: it described the fast pin as "seconds, hermetic, no scaffold". Hermetic and
no-scaffold hold; **"seconds" does not.** Measured on this host,
`bash tests/test-bl180-interactive-enforcement.sh` → `Results: 7 passed, 0 failed`, `EXIT=0`,
**wall clock 116 s** — an order of magnitude off the claim, and roughly a 40 % increase on a unit
lane documented at ~5 min. That measurement inverts the escalation's own premise, so the decision
is to leave the membership rule ("does not invoke `init.sh`") ALONE and keep all three BL-180 test
surfaces in the aggregator only. Three reasons, in order of weight: (1) the fast pin is not fast
enough to be free on every PR; (2) changing the rule to "does not SCAFFOLD a project" is a
governance edit touching `CLAUDE.md`, the `tests.yml` comments and the `grep -L 'init\.sh'`
regeneration recipe — strictly larger than this remediation and the kind of change the WP said to
escalate rather than make unilaterally; (3) the honest residual is narrower than it first looks,
because the chain that made R-WPA-2 material has been broken — R-WPA-1 is fixed, so the pty test
now PASSES under `CI=true` and genuinely executes in the `full` lane's `core` shard with `expect`
installed. **The residual, stated plainly:** a mutation of the
`[ "$ENFORCEMENT_LEVEL" = "strict" ]` gate-install guard in
`init.sh::prepare_initial_state_for_commit` is still invisible to every PR-BLOCKING check
(`lint-tests-registered` rc=0, `lint-no-live-remote` rc=0,
`tests/test-filesystem-gate-install.sh` 8/8, `tests/test-enforcement-level-lib.sh` 10/10, and the
fast pin 7/7 — which cannot observe it because `--dry-run` returns from `main()` before
`create_project`). It is caught only by the manual `workflow_dispatch` lane. Closing that gap
properly means a unit-lane-cheap pin on the gate-install guard specifically, which is its own
work item — see the follow-on escalation below.

**Repair path for already-scaffolded projects — `# BL-180-BACKFILL-EMPTY` in
`scripts/upgrade-project.sh`.** The BL-030 backfill's gate was `! jq -e '.enforcement_level' …`,
and `jq -e` on `""` prints `""` and EXITS 0 (re-confirmed on this host across all four shapes:
`""`→0, missing→1, `null`→1, `"strict"`→0), so the block skipped the very projects it exists to
repair. Replaced with `[ -z "$(jq -r '.enforcement_level // ""' … )" ]`, which collapses BOTH
absent and empty to `""` while a real level passes through verbatim. Deliberately scoped: it
widens the trigger to the empty string ONLY — never to a legitimately chosen tier — and a
malformed manifest still triggers the backfill exactly as the old `! jq -e` did, so that
behaviour is unchanged. Watched-RED first with the gate untouched: `T8 [FAIL] enforcement_level=''
— the empty value defeated its own migration`, `T9 [FAIL] gate still absent after backfill`,
`Results: 8 passed, 2 failed` — with the T10 control (`explicit light survives the backfill`) and
the T2 idempotency case PASSING in that same RED run, so the fix is proven to move only the two
intended cases. New fixture `setup_bl180_empty_level_personal` reproduces the pre-fix interactive
birth shape exactly: it BLANKS `enforcement_level` rather than deleting the key (that distinction
IS the bug), uninstalls the gate, and strips the birth audit row. After the fix:
`Results: 10 passed, 0 failed`.

**Residual, reported not fixed (defense in depth):** `jq -r '.enforcement_level // "strict"'`
does NOT fire on the empty string (`//` only substitutes on `null`/`false`), so
`scripts/install-filesystem-gates.sh` (including the EMITTED `.git/hooks/framework-gate.sh`,
which re-reads it on every commit and `exit 0`s when the value is not exactly `strict`),
`scripts/escalate-to-user.sh` and `scripts/hooks/bypass-detector.sh` would still stamp/act on
`""`. With the birth site and the repair path both fixed, `""` should no longer arise — but a
hand-edited or partially-migrated manifest would silently self-disable the gate. Only
`scripts/lib/enforcement-level.sh::read_enforcement_level` is immune (its `case … *) echo
"strict"` arm). Hardening those three readers is a separate change.

Status stays **Open** pending PR + merge.

**ESCALATED, not fixed here (2026-07-26, from the R-WPA-2 lane decision):** the gate-install guard
`[ "$ENFORCEMENT_LEVEL" = "strict" ]` has no PR-blocking pin. The cheap shape would be a
unit-lane test that drives `prepare_initial_state_for_commit`'s gate-install decision WITHOUT a
full scaffold — but that function is not independently invocable today, so it needs either an
extraction or a `--validate-only`-style seam in `init.sh`. That is a source change to the birth
path with its own blast radius; it is deliberately NOT bundled into a remediation whose remit was
the pty fixture's containment.

**ESCALATED, not fixed here (2026-07-26, verifier finding R-WPA-5 — CONFIRMED):** both pty drivers
answer `init.sh::resolve_and_install_tools`' consent gate with yes — the `expect` script has
`-re {Proceed with this plan\?} { send -- "Y\r"; … }` and the `script(1)` answers file feeds bare
`y` lines — so on a host missing an `auto_install`/`manual_install` tool the fixture authorises a
REAL tool installation. The mock-`gh`/`glab` PATH shim does not cover this (it stubs the host CLIs,
not package managers). Answering `N` instead is NOT a safe one-line change: the plan gate is a
control-flow branch, and refusing it alters what `create_project` receives, so the whole 10-case
contract would need re-deriving and re-watching. Left as-is with the behaviour recorded rather
than half-changed. Note it did not fire on this host (all tools present) — which is exactly why it
survived the first build.

**Report-hygiene note (verifier finding R-WPA-6):** the implementer's tally block labelled an
`edge-cases-pre-init` blast-radius run "105 dry-run assertions" while the quoted tally beneath it
read 37. The label was wrong; the quoted tally is the evidence. No repo artifact carried the bad
number (it lived only in the hand-off text), so there is nothing to correct in-tree — recorded
here so the discrepancy is not re-derived as a real disagreement.

**Adjacent item — NOT fixed here, deliberately escalated (2026-07-26):** `--no-remote-creation`
being silently inert interactively is a genuine SAFETY defect (an operator who asks for no remote
still reaches `create_and_protect_remote` against their authenticated host), and it is a strictly
larger change than a warning tweak: making the flag WORK interactively changes documented
interactive-path semantics, while merely warning about it needs its own accurate message because
`main`'s existing "interactive flow will prompt" text is FALSE for both `--no-remote-creation` and
`--confirm-pitfalls` (nothing prompts for either). It wants its own watched-RED + test + review
rather than being tacked onto this diff.

**Related:** BL-030, BL-084, BL-112, BL-110 (same "written only on one path" class), BL-161/163/171.

---

## BL-181: lint-tests-registered.sh's BL-154 unit-lane arm is exempted by a COMMENT — a green lint is not evidence of unit-lane registration

**Logged:** 2026-07-25 (WP2 planner; empirically confirmed by a three-state probe)
**Category:** Lint precision / silent-success defect class (test-registration invariant)
**Severity:** MEDIUM — the guard against orphaned fast tests is bypassable by an incidental comment, silently; CLAUDE.md documented a stronger guarantee than the lint provides.
**Status:** Open

`_check_unit_lane` decides "does this test invoke init.sh?" with `grep -q 'init\.sh' "$file"` over the
ENTIRE file including comments. Any test that merely MENTIONS init.sh — including a comment saying it
does NOT invoke init.sh — is exempted from the tests.yml `tests=(` membership requirement.

**Evidence.** `grep -c 'init\.sh'` → test-currency-manifest.sh 12, test-plan-staging.sh 30,
test-reconfigure-field-handlers.sh 1 (all three re-confirmed at filing). The first two ARE in the unit
list (tests.yml) by human diligence, not by the lint. test-currency-manifest.sh's own header states the
fast-lane invariant the lint is vacuous for. test-reconfigure-field-handlers.sh is aggregator-only and
its single mention is the comment "We bypass init.sh (and its --non-interactive cost) by hand-rolling
the …" — a comment saying it does not invoke init.sh is what exempts it.

Three-state probe (throwaway test, trivial echo, NO init.sh invocation, aggregator-registered only):

| probe body | `grep -c 'init\.sh'` | lint result |
|---|---|---|
| comment paragraph mentioning init.sh | 2 | `OK: every test file is registered…` rc=0 |
| identical, mentions stripped | 0 | `not listed in the tests.yml unit lane` rc=1 |
| identical, one bare `# init.sh` line | 1 | `OK: …` rc=0 |

One comment line flips FAIL → PASS with zero executable change.

**Doc correction — ALREADY APPLIED (2026-07-25, in the PR #265–#270 closures PR).** CLAUDE.md's HOUSE
RULES DIGEST previously claimed the BL-154 arm enforces tests.yml membership "of every non-`init.sh`
test". The enforced set is "every test whose file TEXT does not contain the string `init.sh`" —
strictly smaller, and bypassable by a comment. That one CLAUDE.md line has been amended to describe
what the lint actually enforces; **amend it BACK to the stronger wording when this entry is fixed**,
since the fix is what makes the stronger claim true.

**Fix shape:** restrict to executed lines, reusing `_build_registered_set`'s comment-stripping idiom,
marked `# BL-181-UNIT-LANE-PREDICATE`:
`if grep -vE '^[[:space:]]*#' "$file" 2>/dev/null | grep -q 'init\.sh'; then return 0; fi`
~~Re-classifies exactly one current file (test-reconfigure-field-handlers.sh)~~ — **CORRECTED
2026-07-27 (retro audit of PR #272, which filed this entry): the "exactly one" prediction was wrong
by 42x.** Measured with this entry's own prescribed predicate: **42** files re-classify, of which
**35** were already in the `tests.yml` unit lane (the exemption decided nothing for them) and **7**
were absent and newly FAIL the lint — `test-bl033-install-cmds-shape.sh`,
`test-intake-wizard-fixes.sh`, `test-prompt-install-noninteractive.sh`,
`test-reconfigure-field-handlers.sh`, `test-tier-crosscheck-6-zdr-gate.sh`, `test-upgrade-paths.sh`,
`test-upgrade-project-retroactive-section.sh`. Their tests.yml additions are part of the change.
**The undercount also concealed a hard cross-entry dependency:** `test-bl033-install-cmds-shape.sh`
is BL-135's test and fails on Linux CI, so BL-181 could not land before BL-135 was fixed — the two
had to ship together, which is why they do. Does NOT catch a mention inside a quoted heredoc/string,
so also render the exemption in `--list` output (`unit-lane-exempt:init-sh-invoker`) so it is
visible in review.

**Mutation proof:** fixture pair in tests/test-lint-tests-registered.sh — comment-only mention must FAIL
rc=1, real invocation must PASS rc=0. Revert the `grep -vE` prefix → comment-only fixture flips FAIL →
PASS → RED → restore → GREEN.

**Related:** BL-154, BL-038/034/035, BL-067, CLAUDE.md CANONICAL COMMANDS + HOUSE RULES DIGEST.

**BUILD NOTE (2026-07-26, WP-B — implemented, Open until merge).** Fixed at
`# BL-181-UNIT-LANE-PREDICATE` in `_check_unit_lane` (scripts/lint-tests-registered.sh). Two
corrections to this entry's own analysis, both verified empirically rather than assumed:

1. **Scope was 7 files, not 1.** The entry predicted "exactly one current file
   (test-reconfigure-field-handlers.sh)". A full sweep of `tests/` found **42** files whose
   classification flips comment-mention → executed-lines, of which **35 were already in the
   tests.yml unit list** (present by human diligence, exactly as the entry's Evidence paragraph
   said of test-currency-manifest.sh / test-plan-staging.sh) and **7 were newly DEMANDED**:
   test-bl033-install-cmds-shape, test-intake-wizard-fixes, test-prompt-install-noninteractive,
   test-reconfigure-field-handlers, test-tier-crosscheck-6-zdr-gate, test-upgrade-paths,
   test-upgrade-project-retroactive-section. All 7 were confirmed to genuinely not invoke
   init.sh, to already be aggregator-registered in full-project-test-suite.sh, to set their own
   git identity where they commit, and to be fast (1s/1s/3s/1s/2s/10s/1s, all rc=0). All 7 added
   to the `tests=(` unit list in the same change.

2. **The prescribed one-liner is UNSOUND on this host — it was not adopted verbatim.** The entry's
   `grep -vE '^[[:space:]]*#' "$file" | grep -q 'init\.sh'` breaks under this script's
   `set -uo pipefail`: `grep -q` exits on first match, the upstream `grep -vE` dies of SIGPIPE,
   and pipefail promotes rc=141 to the pipeline — so a file that DOES invoke init.sh reads as a
   NON-invoker and is wrongly demanded. Measured: tests/test-bl112-commit-enforcement.sh gives
   `rc=141` with `grep -q` vs `count=4` with `grep -c`. It is size-dependent, hence invisible on
   small fixtures and **nondeterministic across runs on the real tree** (one run flagged
   test-bl099-guard-coverage.sh, the next test-bl112-commit-enforcement.sh). Shipped predicate
   keeps the entry's exact semantics but uses a downstream that consumes all input:
   `exec_hits=$(grep -vE '^[[:space:]]*#' "$file" 2>/dev/null | grep -c 'init\.sh')`.
   Guarded by a dedicated regression test (U12) with a multi-KB fixture; `grep -q` fails it.

**Visibility (implemented).** `--list` now renders every *decisive* exemption (exempted AND absent
from the unit list — i.e. the exemption actually changed the outcome) as
`unit-lane-exempt:init-sh-invoker`; 33 rows on the current tree. A moot exemption (file exempt but
in the unit list anyway) is deliberately NOT rendered — U11 pins that.
Audit: `bash scripts/lint-tests-registered.sh --list | grep unit-lane-exempt`.

**Residual, stated in-script and unchanged:** a mention inside a quoted string or heredoc body
still exempts. Accepted; the `--list` surface is the compensating control.

**Tests (tests/test-lint-tests-registered.sh, 24 passed / 0 failed):** U6 comment-only mention →
DEMANDED · U7 real invocation → EXEMPT · U8 mutation restoring the whole-file predicate → U6 stops
flagging · U9 mutation disabling the exemption → U7 starts flagging · U10 `--list` renders the
decisive exemption · U11 moot exemption not rendered · U12 SIGPIPE/pipefail regression.
Watched-RED: U6/U8/U9/U10 fail against pre-BL-181 HEAD; U12 fails against the SIGPIPE-broken form.
`.github/workflows/tests.yml` generator comments amended — the `grep -L 'init\.sh'` recipe is now
explicitly documented as WRONG as a membership rule. CLAUDE.md HOUSE RULES restored to the stronger
claim the fix now earns, with the heredoc residual and the `--list` audit command named.

**REMEDIATION (2026-07-26, WP-B round 2 — adversarial verifier `major_concerns` on the build note
above; still Open until merge).** Two findings, both reproduced before being fixed:

* **R-B-1 — the defect class was only HALF closed while the note above declared it closed.** The
  first fix stripped WHOLE-LINE comments only, so the identical comment TEXT still exempted a file
  merely by moving to the end of an executable line: `echo "hello"   # we bypass init.sh` gave
  `rc=0` (EXEMPT) where the same words on their own line gave `rc=1` (DEMANDED). One comment
  repositioned, zero executable change, FAIL → PASS — verbatim this entry's own defect statement.
  `# BL-181-UNIT-LANE-PREDICATE` now carries a second stage that strips TRAILING comments too. The
  sed deliberately requires a non-space char before the whitespace run so it fires only on real
  trailing comments, which keeps the whole-line stage's `[[:space:]]*` independently testable.
  Measured before shipping: the stricter predicate reclassifies **zero** files in `tests/` (so no
  new `tests=(` entries), and its own error direction is the loud one — over-stripping can only
  REMOVE hits, i.e. demand a file into the unit lane where a human sees a red lint, never exempt
  one silently.
* **R-B-2 — the `[[:space:]]*` half of the anchored line was pinned by NO test.** Weakening it to
  `^#` re-opened BL-181 for every INDENTED comment (the dominant form inside a function body) and
  survived both PR-blocking checks: `lint-tests-registered.sh` rc=0 and the suite at 24 passed /
  0 failed. Root cause: every BL-181 fixture placed its comments at column 0. `_bl181_fixture_comment_only`
  now carries all three comment spellings — column-0, indented, and trailing — each alone on its
  line, so any one surviving the stripper turns U6 red. No new test case was added; the enriched
  shared fixture kills both mutants through the existing U6.

Mutation proofs, both directions, restore from a byte-exact backup (NOT `git checkout` — the fix is
uncommitted, so that would silently revert the fix and fake a red): **A** weaken `^[[:space:]]*#` →
`^#` ⇒ 23 passed / 1 failed rc=1 (U6), restore ⇒ 24 / 0 rc=0. **B** delete the trailing-comment sed
stage — which reproduces the round-1 predicate byte-for-byte — ⇒ 23 passed / 1 failed rc=1 (U6),
restore ⇒ 24 / 0 rc=0. Round 1's shipped predicate is therefore now a killed mutant.

**Residual after remediation (narrower, still stated in-script):** a mention inside a quoted string
or a heredoc body still exempts, as does a comment introduced with no preceding whitespace
(`foo;#note`). `--list` remains the compensating control.

---

**REMEDIATION ROUND 3 (2026-07-26, WP-B — adversarial verifier `major_concerns` on round 2; still
Open until merge).** Two findings, both reproduced before being fixed.

* **R-B-4 — the fixture pinned each comment SPELLING but not its WIDTH, so round 2's own root cause
  recurred.** Round 2 enriched `_bl181_fixture_comment_only` to three spellings and claimed all
  atoms were pinned. They were not: every trailing comment in the fixture used THREE spaces, so
  narrowing the trailing stage's quantifier `[[:space:]][[:space:]]*` (1+) to
  `[[:space:]][[:space:]][[:space:]]*` (2+) — one character — left the fixture's behaviour
  unchanged and survived **both** PR-blocking checks (`lint-tests-registered.sh` rc=0, suite
  24 passed / 0 failed). Under that mutant a **single-space** trailing comment, the commonest
  spelling in shell, re-exempts a file: A/B probe (two files identical but for the space count,
  both aggregator-registered, unit list naming neither) gave
  `SKIP … test-probe-single-space.sh unit-lane-exempt:init-sh-invoker` + `FAIL …
  test-probe-three-space.sh not-in-unit-lane`, rc=1 with 1 violation, against a pristine control of
  `FAIL`/`FAIL`, rc=1 with 2 violations. The same class held for the whole-line stage: the fixture's
  indented comment used spaces only, so narrowing `^[[:space:]]*#` to `^ *#` also survived both
  checks (rc=0, 24/0) while re-exempting every TAB-indented file.
  **Fix is fixture-only — no production change.** `_bl181_fixture_comment_only` now carries FIVE
  init.sh-bearing comment lines, each shape alone on its line: column-0 whole-line, SPACE-indented
  whole-line, TAB-indented whole-line, trailing at ONE space, trailing at THREE spaces. The one atom U6 cannot
  pin — the sed's leading `\([^[:space:]]\)` guard — is now stated as unpinnable-and-why rather
  than counted as covered.
* **R-B-5 — the round-2 residual paragraph undercounted by 5, and CLAUDE.md's restored absolute was
  false by those same 5.** Round 2 asserted "the one real instance on the tree is
  test-bl096-cold-start.sh … already in the unit list, so that exemption is moot". Running the
  audit the `--list` surface exists for (`bash scripts/lint-tests-registered.sh --list | grep -c
  unit-lane-exempt` → **33**) and classifying every row shows **5 of the 33 decisive exemptions
  belong to files that never execute init.sh** — they name it inside a string as a `grep`/`awk`
  target, or write a stub they never run:
  `test-resolve-tools-memoization.sh` (`INIT_SH="$REPO_ROOT/init.sh"`, then `awk … "$INIT_SH"`),
  `test-specs-plans-host-aware-quartet.sh` (`grep -q … "$INIT_SH"`),
  `test-docs-cluster-six-pack.sh` (`grep -qE 'cp …' "$INIT_SH"`),
  `test-platform-mobile-mcp-docs.sh` (`awk … "$INIT_SH"`),
  `test-platform-security-bugs-closer.sh` (`cat > "$fake_fw/init.sh" <<'STUB'`, never executed).
  A further **9 mention-only exemptions** are moot because the file is already in the unit list —
  test-bl096-cold-start, test-bl108-bl117-ship-closure, test-bl119-stale-editmsg,
  test-bl123-bp-attestation-recovery, test-bl141-commitmsg-repair, test-bl147-ci-template-integrity,
  test-currency-manifest, test-freshness-check, test-upgrade-sync-framework — so "one instance" was
  wrong by an order of magnitude in both directions.
  **Fixed three ways.** (1) This paragraph replaces the undercount with the measured audit.
  (2) CLAUDE.md HOUSE RULES now says the arm enforces membership of every test whose **executed
  lines do not name** `init.sh` — the predicate stated literally — and adds "an exempt row is a
  claim, not a verdict: read the rows, do not count them". (3) The 5 non-invokers were added to the
  `tests=(` unit list: each is aggregator-registered in full-project-test-suite.sh, uses no
  `git commit`/`git config user` and needs no `~/.claude-dev-framework`, and runs in 0-2s
  (`rc=0 0s` resolve-tools-memoization `Results: 2 passed, 0 failed` · `rc=0 2s`
  specs-plans-host-aware-quartet `== Total: 8 | Passed: 8 | Failed: 0 ==` · `rc=0 0s`
  docs-cluster-six-pack `Results: 28 passed, 0 failed` · `rc=0 0s` platform-mobile-mcp-docs
  `Results: 8 passed, 0 failed` · `rc=0 0s` platform-security-bugs-closer
  `== Total: 7 | Passed: 7 | Failed: 0 ==`); all five already run on Linux via the green full lane.
  The audit surface drops **33 → 28 rows**. ~~All 28 survivors are genuine invokers~~ — **that
  absolute was WRONG, see R-B-11 below**: it was a grep classification, and re-running the same
  question as an EXECUTION trace found a 29th row misfiled. The two rows the naive
  command-position grep misses are `test-poc-modes.sh` (`run_bounded 90 bash "$INIT" …`) and
  `test-bl099-guard-coverage.sh` (copies init.sh into a mutant tree and drives scaffolding
  sub-suites through `BL099_REPO_OVERRIDE`); both are confirmed invokers by execution in R-B-11.

Round-3 mutation proofs, all restored from a byte-exact backup (NOT `git checkout` — the fix is
uncommitted, so that would silently revert it and fake a red). The round-3 fix is fixture-only, so
each mutant is applied to the PRODUCTION predicate and killed by the enriched fixture through the
existing U6: **C** trailing quantifier 1+ → 2+ ⇒ 23 passed / 1 failed rc=1 (U6), restore ⇒ 24 / 0
rc=0. **D** `^[[:space:]]*#` → `^ *#` ⇒ 23 / 1 rc=1 (U6), restore ⇒ 24 / 0 rc=0. Round 2's mutants
stay killed under the enriched fixture: **A** `^[[:space:]]*#` → `^#` ⇒ 23 / 1 rc=1; **B** delete
the trailing-comment sed stage ⇒ 23 / 1 rc=1.

**Note on this entry's own "Fix shape" paragraph (R-B-6):** the one-liner quoted there
(`grep -vE '^[[:space:]]*#' … | grep -q 'init\.sh'`) is the SUPERSEDED round-1 proposal, kept for
history. It is unsound twice over — SIGPIPE under `pipefail` (see build note item 2) and no
trailing-comment stage — and U6 now kills it as mutant B. The shipped predicate is the two-stage
form at `# BL-181-UNIT-LANE-PREDICATE`; read the script, not this paragraph.

**Non-blocking, now owned rather than gestured at (R-B-3 / R-B-7):** the SIGPIPE-under-`pipefail`
class (`cmd | grep -q` promoting rc=141 through `set -o pipefail`) is pre-existing and out of scope
here. Round 2 said it was live "in at least one other PR-blocking enforcement script" without
naming one, which left the class unowned. Filed as **BL-183** with the measurement recipe; do not
widen this entry to cover it.

---

**REMEDIATION ROUND 4 (2026-07-26, WP-B — adversarial verifier `major_concerns` on round 3; still
Open until merge).** Two findings. Both are the SAME two failure modes this entry has now produced
three and two times respectively: an unpinned atom in the predicate regex (R-B-2, R-B-4, R-B-10) and
a wrong absolute about the survivor set (R-B-5, R-B-11). Neither is a product defect — the shipped
predicate is correct against every spelling below, verified before anything was touched.

* **R-B-10 — three more single-atom mutations SURVIVED both PR-blocking checks.** Round 3 pinned
  each comment's WIDTH but not the `#` itself, and pinned the whole-line stage's whitespace as a
  class while leaving the TRAILING stage's whitespace pinned only by spaces. So three
  one-character narrowings each re-opened BL-181 for a spelling the fixture did not carry, while
  `lint-tests-registered.sh` stayed rc=0 and the suite stayed 24 passed / 0 failed:
  narrowing the trailing whitespace run to a literal space (re-exempts every TAB-separated trailing
  comment), narrowing the whole-line `#` to `#[[:space:]]`, and narrowing the trailing `#` to
  `#[[:space:]]` (both re-exempt every `#like this` comment — a very common shell spelling).
  **Fix is fixture-only — no production change.** `_bl181_fixture_comment_only` grows from five
  init.sh-bearing comment lines to **eight**: adds a column-0 whole-line comment with no space
  after the hash, a trailing comment with no space after the hash, and a TAB-separated trailing
  comment.
  Mutation proofs (mutant applied to the PRODUCTION predicate, killed through the existing U6,
  restored from a byte-exact backup — NOT `git checkout`, which would silently revert uncommitted
  work and fake a red): **E** trailing `[[:space:]][[:space:]]*` → `  *` ⇒ 23 passed / 1 failed rc=1
  (U6) → restore ⇒ 24 / 0 rc=0. **F** `^[[:space:]]*#` → `^[[:space:]]*#[[:space:]]` ⇒ 23 / 1 rc=1
  → 24 / 0 rc=0. **G** trailing `#` → `#[[:space:]]` ⇒ 23 / 1 rc=1 → 24 / 0 rc=0. Rounds 2–3's
  mutants were re-run rather than assumed still dead: **A** `^#`, **B** delete the sed stage,
  **C** quantifier 1+ → 2+, **D** `^ *#` — all 23 / 1 rc=1 → 24 / 0 rc=0. `lint-tests-registered.sh`
  restored byte-identical each time (md5 `1a1cd956faf17ff6d7dbb4a0f242b133`).
  The fixture header's "pins every regex atom except the sed's guard" claim is replaced. It now
  names **two** unpinned atoms and states each one's MEASURED behaviour instead of asserting it:
  deleting the sed's `\([^[:space:]]\)` guard leaves the suite at 24 / 0 (mutant **H**) — genuinely
  behaviour-neutral on this fixture, kept because it stops the sed masking the grep; dropping the
  grep's `^` anchor is NOT neutral but is killed by **U7 and U10**, not U6 (mutant **I**, 22 passed
  / 2 failed rc=1), because the real-invoker fixture's invocation carries a trailing comment an
  unanchored pattern would delete wholesale.
* **R-B-11 — round 3's "all 28 survivors are genuine invokers" was a GREP verdict, and it was
  wrong.** `tests/test-lint-no-live-remote.sh` sits on the exempt surface and never executes
  init.sh: every mention is argument text inside single-quoted `body` strings that `assert_lint`
  writes to a temp fixture for the lint to SCAN. It ran in ~5-6s, so it was silently absent from
  every PR fast-lane run — exactly the BL-181 harm. Added to the tests.yml `tests=(` array
  (confirmed: aggregator-registered in full-project-test-suite.sh, no `git commit`, no
  `git config user`, no `~/.claude-dev-framework` dependency, `== Total: 14 | Passed: 14 |
  Failed: 0 ==` rc=0 in 6s). **Linux evidence, not an assumption:** it already runs green on
  ubuntu through the aggregator — full-lane run 30204845017 (2026-07-26), core shard,
  `[PASS] scripts/lint-no-live-remote-in-tests.sh behavior tests (14/14)`. Unit list
  **134 → 135** entries, hand-verified: exactly one occurrence
  of the new path inside the array, zero duplicates, all 135 paths exist, YAML still parses.
  Exempt surface **28 → 27** rows (its exemption is now moot, so U11's contract stops rendering it).

  **The whole surface was then RE-AUDITED BY EXECUTION, not by grep** — because a grep verdict has
  now under-read this surface twice. Method: append an env-gated marker line
  (`printf … >> "${SOLO_INITSH_TRACE:-/dev/null}"`) to `init.sh` as line 2, then run each of the 28
  rows under `bash -x` with `SOLO_INITSH_TRACE` set and a watchdog that kills the run the moment the
  marker appears. A marker line is proof the init.sh CODE executed — including through a copy the
  test makes, which no command-position grep can see. `init.sh` was restored byte-exact afterwards
  (md5 `0be49cdda069dc4680e0172bd7b30e16`). Result: **27 of 28 rows fired the marker** (26 within
  1s); the 1 that did not is `test-lint-no-live-remote.sh`, which ran to completion at rc=0 in 6s
  with an empty marker file. No further non-invokers exist on this surface, so nothing else was
  registered.

  The verifier's second flag is **REFUTED by that trace**: `tests/test-bl099-guard-coverage.sh` was
  called a milder mislabel ("exempted by a `cp "$REPO_ROOT/init.sh" …` line, never executing it").
  It DOES execute init.sh. The xtrace shows the `cp` into `$TMPDIR/framework/init.sh`, and 74s later
  the marker fires — the last traced command being
  `BL112_REPO_OVERRIDE=$TMPDIR/framework bash tests/test-bl112-commit-enforcement.sh`, i.e. it
  drives a scaffolding sub-suite against the mutant framework tree whose init.sh is that copy. It is
  also ≥74s to reach that point, so it is not fast-lane material on either ground. Row kept exempt.

  **The absolute is not re-stated in a stronger form anywhere.** All three sites that carried it —
  CLAUDE.md HOUSE RULES, this entry's round-3 note, and the tests.yml unit-lane comment — now say
  the same measured, dated thing: on the 2026-07-26 tree an execution trace classified all 27
  remaining rows as invokers; that is a measurement at one commit, not a standing property, and the
  instruction is to re-run the trace rather than cite the number.

**Standing lesson for this entry (three recurrences of one class, two wrong survivor counts):** a
regex atom that no fixture line exercises is an atom that can be reverted silently, and a survivor
row that no execution proves is a claim, not a verdict. Enumerate and execute; do not assert.

**Residual #2 — the SIBLING half of the same feature is still comment-defeatable (found 2026-07-27
by the pre-merge adversarial review of PR #275; entry stays Open for it).** `_check_unit_lane` now
reads executed lines, but `_build_unit_list_set` — which parses the `tests.yml` `tests=(` array to
learn what IS registered — scopes with awk between `tests=(` and `)` and **never strips comments**.
So an entry **commented out inside the array** is still collected as a member, while bash drops it
from the array. Net: the test does not run in the fast lane and every PR-blocking check stays green.

Reproduced on the merged tree: commenting out one entry left `lint-tests-registered` rc=0
("OK: every test file is registered with an aggregator (or EXEMPT)"),
`tests/test-lint-tests-registered.sh` at `Results: 24 passed, 0 failed`, and `run-lints`
`11 lints — 11 passed, 0 failed` — while the array evaluated to 134 elements with zero references to
the victim. Deleting the same line outright DOES go red, so the guard works for omission and not for
commenting-out.

**Scope note:** this is PRE-EXISTING, not introduced by the BL-181 fix — the awk in
`_build_unit_list_set` is byte-identical before and after, verified on both revisions. An
independent refuter confirmed that and downgraded it from the blocking grade it was first filed at.
It is recorded here because it is the same "a comment defeats the guard" class this entry exists to
retire, in the other half of the same feature.

**Fix shape:** one awk predicate — `awk '/tests=\(/{f=1; next} f && /^[[:space:]]*\)/{f=0} f &&
!/^[[:space:]]*#/{print}'` — plus a fixture pair in `tests/test-lint-tests-registered.sh`: a unit
list carrying the victim COMMENTED OUT must exit 1 and name the file; the same list uncommented must
exit 0. **Mutation proof:** revert the `!/^[[:space:]]*#/` predicate → the commented-out fixture
flips from FAIL to PASS → RED → restore → GREEN.

---

## BL-182: A ~958+ character repo-relative path is UNREPRESENTABLE in the BL-132 index temp tree — PATH_MAX aborts materialization and the whole commit goes NOTRUN (third instance of the same class)

**Logged:** 2026-07-25 (PR #270 final-gate adversarial review, R-270-3; confirmed A/B against main)
**Category:** Bug / security enforcement — commit-time SAST materialization (the "one bad entry blinds the whole commit" class, instance 3)
**Severity:** Medium
**Status:** Closed — shipped + merged 2026-07-27 (PR #274 `24ac0bd`), together with BL-179 in one rewrite of the emitted SAST region. `# BL-182-PER-ENTRY-SKIP`: the all-or-nothing `soif_idx_ok=0; break` is gone (the variable no longer exists in executable code — the two remaining textual hits in `scripts/lib/hook-templates.sh` are comments describing the retired mechanism, which is worth knowing before anyone re-greps and concludes otherwise). An unreadable entry is appended to `soif_idx_unread` and the loop CONTINUES, so coverage degrades entry-by-entry instead of collapsing. Three honesty guarantees keep "scan the readable subset" from becoming a smaller silent-success, each with its own marker: `# BL-182-PARTIAL-STILL-BLOCKS`, `# BL-182-NO-UNEARNED-RECEIPT`, `# BL-182-NAME-THE-ENTRY`.

The BL-132 materialized destination is `$soif_idx_tree/$soif_idx_n/$soif_p` (`# BL-132-INDEX-SCAN` /
`# BL-178-PER-INDEX-DIR` in `scripts/lib/hook-templates.sh`). `mktemp -d` contributes ~63 characters on
macOS (`/var/folders/<2>/<30>/T/tmp.<10>`, measured) plus the `/<n>/` segment, and macOS `PATH_MAX` is
**1024** (`getconf PATH_MAX /`). So a repo-relative path longer than **~958 characters** is perfectly
legal in the worktree and in the index, but cannot be expressed as a destination in the temp tree.
`mkdir -p` fails, the loop takes its all-or-nothing `soif_idx_ok=0; break`, every already-materialized
sibling target is discarded, and the WHOLE commit routes to NOTRUN.

**Evidence — real emitter, real `.git/hooks/pre-commit`, real `git commit`; repo-relative length 991,
2 staged entries (the long path plus an ordinary sibling carrying a live XSS sink):**

```
MAIN ed406c8 -> [BLOCKED] Semgrep detected security issues in staged files.
                SIBLING VULN LANDED? NO-BLOCKED
HEAD 3157eb9 -> dirname: /var/folders/.../tmp.jzZLnTISwY/1/d0000.../long.js: File name too long
                [WARN] could not materialize staged content for scanning — SAST skipped.
                commit rc=0, sibling XSS LANDED
```

**Severity argument — Medium, and the reasoning matters more than the number.**

> **CORRECTION (2026-07-29): the "REGRESSION versus main" clause below is FALSE AS WRITTEN, and is
> kept rather than deleted because the way it went wrong is the transferable part.** The A/B was run
> against a `main` that did not yet carry the defect — but by the time this sentence was committed,
> it did. Measured: `## BL-182:` was committed at **2026-07-25T17:57:31Z**; PR #270 (`b0b60aa`),
> which INTRODUCED the mechanism, merged at **2026-07-25T17:37:58Z** — **19 minutes 33 seconds
> earlier**. Proof the mechanism arrived with #270: `git show b0b60aa:scripts/lib/hook-templates.sh
> | grep -c 'soif_idx_ok=0'` = **5**, versus **0** at `b0b60aa^1`. So the correct reading is "a
> regression introduced by #270, filed against the branch before it merged", not "a divergence from
> main". **The lesson: an A/B against `main` is stamped with a time, and a review that runs while
> its own PR is merging is comparing against a moving target.** Severity is unaffected — the
> mechanism, the loudness argument, and the pathological trigger all stand.

Against it: this is a
**REGRESSION versus main** (main BLOCKS the same fixture) and it is the **THIRD** instance of the same
mechanism in the same loop, after R-270-1 (submodule gitlink) and R-270-1B (`0:`-prefixed stage
syntax). For it: it fails **LOUD** — the BL-112 honest-NOTRUN contract holds, the operator is told
`could not materialize staged content for scanning — SAST skipped`, and there is **never a false
`[OK]`**; and the trigger needs a ~958+ character repo-relative path, which is pathological rather than
typeable. That combination (loud + pathological) is what keeps it off the block list — not any doubt
about the mechanism.

**FIX DIRECTION — do NOT patch a third trigger.** Patching PATH_MAX specifically would be the third
whack-a-mole fix to the same `break`, and a fourth trigger will exist. **Retire the all-or-nothing
`break` in the `# BL-132-INDEX-SCAN` loop:** scan what DID materialize, and route to NOTRUN **naming
the specific staged entry it could not read** — so the operator learns *which* file is unscanned
instead of losing the entire commit's coverage. That retires the whole class at once (gitlink,
stage-syntax, PATH_MAX, and whatever is fourth). The honest-receipt plumbing it needs already exists:
`# BL-132-EMPTY-TARGETS` already counts ACTUAL targets rather than staged entries, and
`# BL-132-GITLINK-SKIP` already demonstrates a per-entry `continue`. Care is required so that "scan the
readable subset" never degrades into a silent partial pass — the per-entry NOTRUN must be as loud as
today's whole-commit NOTRUN, and a commit with ANY unreadable entry must still be reported as
not-fully-scanned. **Alternative / companion:** shorten the temp root (e.g. `mktemp -d` under a short
fixed prefix), which raises the threshold but does not retire the class — hardening, not the fix.

**Incidental, fix while in here:** the `2>/dev/null` sits on `mkdir -p`, but the
`$(dirname "$soif_idx_dest")` command substitution runs FIRST with **unredirected** stderr — which is
exactly why the raw `dirname: …: File name too long` line appears in the operator's commit output
above. Redirect the substitution too, or the hook leaks a bare tool diagnostic into a security-gate
transcript.

**Build note (2026-07-26, branch `worktree-wf_79ea23a3-eb4-3`):** The **CLASS is retired, not the trigger** — landed with BL-179 in the same rewrite of the emitted SAST region. `# BL-182-PER-ENTRY-SKIP`: every `soif_idx_ok=0; break` is gone (the variable no longer exists); an entry that cannot be read is appended to `soif_idx_unread` and the loop CONTINUES, so coverage degrades entry-by-entry instead of collapsing. Three honesty guarantees are what make "scan the readable subset" safe rather than a smaller silent-success, and each carries its own marker: **`# BL-182-PARTIAL-STILL-BLOCKS`** — a finding in the readable subset BLOCKS even when coverage was partial (this is the actual regression the `break` caused: a sibling's sink LANDED, strictly worse than scanning nothing); **`# BL-182-NO-UNEARNED-RECEIPT`** — a CLEAN scan over a PARTIAL set never prints `[OK] semgrep: SAST ran on N staged file(s)`, it routes to the new `soif_sast_partial_coverage` helper, a SECOND loud reporter rather than a reuse of `soif_sast_not_enforced` because "nothing was scanned" is itself false when a subset was (it carries the same `SAST NOT ENFORCED` vocabulary, so every operator habit and every existing grep still fires); **`# BL-182-NAME-THE-ENTRY`** — `soif_sast_unread_report` lists each unread entry one per line on EVERY arm that has one (nothing-materialized NOTRUN, tool-failure NOTRUN, partial-clean report, and the `[BLOCKED]` path, because a blocked commit is exactly when the operator is about to re-stage). Zero targets with nothing unread still hits the unchanged `# BL-132-EMPTY-TARGETS` gitlink-only NOTRUN; the `[OK]` receipt is now reachable ONLY with complete coverage, and it still counts `${#soif_idx_files[@]}`. **Incidental leak fixed, plus a second one found while fixing it:** the `2>/dev/null` sat on `mkdir -p` while `$(dirname …)` ran first with unredirected stderr — `dirname` now carries its own redirect and an empty result is treated as failure; and the materialization write is wrapped in a brace group (`{ …; } 2>/dev/null`) because bash applies redirections LEFT TO RIGHT and reports a failure to OPEN the destination BEFORE `2>/dev/null` is in force, which leaked a raw `File name too long` from the shell itself (verified both ways here). Proof (`tests/test-bl132-sast-index-scan.sh`): `T-partial-clean-no-receipt` (unreadable entry carrying the sink + clean sibling → no `[OK]`, loud NOTRUN, entry NAMED as a `    - <path>` line, commit lands, and no raw tool diagnostic), `T-partial-vuln-still-blocks` (unreadable entry + sibling carrying the sink → `[BLOCKED]`, sibling named, gap named), `T-pathmax-sibling-caught` (the filed 1015-byte repo-relative path; fires at the dirname/mkdir recovery point where the other two fire at the write point). Two generators, both index-only via `git update-index --add --cacheinfo` because neither path can exist in a worktree: a **303-byte single path COMPONENT** (over NAME_MAX 255 on every POSIX filesystem — host-independent, hence primary) and the **1015-byte path** (PATH_MAX-dependent, so its case probes a real `mktemp -d` root and LOUD-SKIPs where the host can express it). Watched-RED against the pristine lib: all three FAILED — "ONE unreadable staged entry discarded every already-materialized sibling and routed the WHOLE commit to NOTRUN — the readable sibling's innerHTML XSS LANDED", and the clean case failed on "the NOTRUN did not NAME the staged entry it could not read" (the naming assertion is `grep -qxF "    - <path>"`, deliberately exact-line, because the pre-fix raw `File name too long` leak CONTAINS the path and a loose `grep -F` would have passed vacuously). Mutation proofs: `T-mutation-partial-break` (restore all-or-nothing recovery at all 4 points → the whole commit NOTRUNs and the sibling XSS LANDS → restore → REFUSED) and `T-mutation-partial-receipt` (disarm the no-unearned-receipt guard → an `[OK]` over a partial scan → restore → loud partial NOTRUN). `T-mutation-content-guard`'s F2-removal anchor was **retargeted in lockstep** (it keyed on the removed `soif_idx_ok=0; break; fi`) and upgraded from a best-effort `awk` to an exactly-once-per-line COUNTED one: left unretargeted it would have dropped the two F2 assignments while leaving the conditional referencing an unset variable under `set -u`, aborting the hook and refusing the commit for a reason unrelated to F2 — a case that looks healthy and proves nothing. Green: `test-bl132` 23/23, `test-bl131` 17/17, `test-bl118` 6/6, `test-bl112` 13/13, `test-bl113` 17/17, `test-upgrade-sync-framework` 39/39, `run-lints` 11/11. Blast-radius sweep of every other suite that consumes the emitted hook, also green: `test-bl099-guard-coverage` 53/53 (the `--error` registry anchor still RED-under-neuter), `test-bl125-commit-test-exec` 16/16, `test-bl163-blocked-ledger` 7/7, `test-bl161-ledger-real-events-only` 7/7, `test-freshness-check` 26/26, `test-verify-install-fix-functions` 16/16. Status stays **Open** pending PR + merge.

**Remediation note (2026-07-26, branch `worktree-wf_79ea23a3-eb4-9`) — scoping "the `[OK]` receipt is reachable ONLY with complete coverage".** That sentence in the build note above is true **of this entry's guard** and was false **of the arm as a whole**, and the difference is worth carrying forward. `# BL-182-NO-UNEARNED-RECEIPT` compares what was scanned against `soif_idx_unread`, i.e. against the entries the materialization loop was GIVEN. It cannot see an entry that never reached the loop — and `# BL-179-STAGED-FILTER` decides that. While the filter read `--diff-filter=ACMR` a staged **TYPE CHANGE** (status letter `T`, a real `100644` blob) was dropped before the loop, so `soif_idx_unread` was empty, this guard could not fire, and a clean sibling bought `[OK] semgrep: SAST ran on 1 staged file(s)` over a commit carrying an unscanned `innerHTML` sink (R-WPC-1; reproduced through the real emitter and a real `git commit`). Filter → `ACMRT`; full detail, evidence and mutation proofs in **BL-179's remediation note**. Nothing in this entry's own code or contract changed. Two knock-on items from the same review: the receipt comment in `soif_precommit_region_body` now names BOTH preconditions of "complete coverage" (every given entry read **and** every content-bearing entry given) instead of only the first; and, per R-WPC-2, the **F2 size-mismatch recovery point** — one of the four this entry introduced — had its `soif_idx_unread` recording pinned only STRUCTURALLY, by `T-mutation-partial-break`'s exactly-four occurrence counter, so `T-mutation-content-guard` now also asserts the entry is NAMED on both F2 arms (watched-RED by replacing the recording with a bare `then continue; fi` → `[FAIL] … NOTRUNed but never NAMED app.ts`, `Results: 23 passed, 2 failed`). Green after: `test-bl132` **25/25**, `test-bl131` 17/17, `test-bl118` 6/6, `test-bl112` 13/13, `test-bl113` 17/17, `test-upgrade-sync-framework` 39/39, `run-lints` 11/11, all exit 0. Status stays **Open** pending PR + merge.

**Remediation note #2 (2026-07-26, branch `worktree-wf_79ea23a3-eb4-15`) — the mode predicate's REJECT direction had NO test, and NO lane could see the gap.** A second adversarial round returned **major_concerns** (R-WPC2-1), refuting the claim in remediation note #1 that `T-gitlink-not-counted-unread` "pins BOTH directions of the gitlink-vs-unreadable distinction". Only the ACCEPT direction was pinned, and the verifier was **right** — reproduced here independently, before touching anything, with a mutation distinct from all five already in the suite. **The mutation (M1):** widen the skip's index-MODE test at `# BL-132-GITLINK-SKIP` from `git ls-files -s -- ":(literal)$soif_p" | grep -q '^160000 '` to `grep -q '^'` — i.e. exactly the blanket "unreadable => skip" the comment directly above it forbids in capitals ("THIS IS NOT A BLANKET 'unreadable => skip'"). **The fixture:** a real **TREE object staged at index mode 100644** (`git update-index --add --cacheinfo "100644,<tree-sha>,weird.ts"`) beside a clean readable sibling — `git ls-files -s` reports `100644 <sha> 0 weird.ts` so the 160000 test must REJECT it, while `git cat-file -t :0:weird.ts` returns `tree` so it genuinely is not scannable content. A/B through the real emitter, the real `.git/hooks/pre-commit` and a real `git commit`, git 2.50.1 / semgrep 1.157.0: PRISTINE → `verdict=COMMITTED`, `[WARN] SAST coverage was PARTIAL: 1 staged file(s) scanned clean, 1 could NOT be read (listed below).` + `    - weird.ts`; M1 MUTANT → `verdict=COMMITTED`, `[OK] semgrep: SAST ran on 1 staged file(s) — no ERROR-severity findings.` — an **unearned receipt on a commit that LANDS carrying an unscanned staged entry**, the exact silent-success class this entry exists to retire. **No lane caught it.** With M1 applied to `scripts/lib/hook-templates.sh`, the owning suite `tests/test-bl132-sast-index-scan.sh` — a PR-gating member of the `tests.yml` unit lane — returned `Results: 25 passed, 0 failed (0 skipped)`, `EXIT=0`, identical to the pristine baseline, and `T-gitlink-not-counted-unread` PASSED verbatim under it; `grep -rlE "cacheinfo|160000|hash-object" tests/` returns that one file, so no sibling suite could have seen it either. **Why the existing case was blind:** its unreadable entry is `$LONG_NAME`, a perfectly HEALTHY blob (`git ls-files -s` → mode `100644`, `git cat-file -t ":0:$LONG_NAME"` → `blob`, verified) whose materialization fails LATER, at the write redirect; the `if [ "$soif_idx_type" != "blob" ]` branch that holds the mode test is never entered, so the predicate is invisible to it. `$LONG_PATH` is the same story at the dirname/mkdir site. Reaching the REJECT direction needs a genuine non-blob, non-gitlink index entry, and only `--cacheinfo` can build one. **This is a TEST-COVERAGE gap, NOT a product defect — the shipped predicate is correct and is UNCHANGED.** Fix is `tests/test-bl132-sast-index-scan.sh` only: new hermetic helper `stage_tree_at_blob_mode` (builds the tree through a throwaway `GIT_INDEX_FILE` so the fixture's real index is untouched), new case **`T-nonblob-nongitlink-forfeits-receipt`** (asserts NO `[OK] semgrep: SAST ran`, a loud NOTRUN, `grep -qxF "    - weird.ts"`, and WARN-not-block, with LOUD-SKIP guards re-probing all three halves of the shape), and new mutation case **`T-mutation-gitlink-mode-blanket`**. Watched-RED with M1 applied to the lib: `[FAIL] T-nonblob-nongitlink-forfeits-receipt — a non-blob, NON-GITLINK staged entry was skipped with NO trace and the clean sibling bought an UNEARNED [OK] … receipt: [OK] semgrep: SAST ran on 1 staged file(s) — no ERROR-severity findings.` and `[FAIL] T-mutation-gitlink-mode-blanket — MIS-TARGETED — the gitlink MODE predicate is not present exactly once in the emitted hook`, tally `Results: 25 passed, 2 failed (0 skipped)`, `EXIT=1`. That second failure is the mutation case's DESIGNED behaviour and is itself evidence: a widened predicate makes the anchor vanish, so the case fails loudly instead of mutating nothing. Restored: `Results: 27 passed, 0 failed (0 skipped)`, `EXIT=0`. The in-suite comment on `T-gitlink-not-counted-unread` and the file's CASES header now state the ACCEPT/REJECT split precisely instead of claiming both. Green after, all exit 0: `test-bl132` **27/27** (was 25), `test-bl131` `Results: 17 passed, 0 failed (0 skipped)`, `test-bl118` `Results: 6 passed, 0 failed (0 skipped)`, `test-bl113` `Results: 17 passed, 0 failed`, `test-bl112` `Results: 13 passed, 0 failed, 0 skipped`, `test-bl125` `Results: 16 passed, 0 failed`, `test-upgrade-sync-framework` `== Total: 39 | Passed: 39 | Failed: 0 ==`, `run-lints` `11 lints — 11 passed, 0 failed`. **Lane honesty:** `test-bl132`, `test-bl131`, `test-bl118`, `test-bl125` and `test-upgrade-sync-framework` gate the PR via the `tests.yml` unit lane; `test-bl112` and `test-bl113` are full-lane only and were run locally. Also recorded from this round, no action taken: **R-WPC2-2** (informational) — the dispatch brief's implementer-claims text was stale relative to the SHA under review; the in-tree notes were accurate. Status stays **Open** pending PR + merge.

**Related:** BL-132 (the arm, and the two already-fixed instances of this class), BL-179 (the other
hole in the same arm — rename-and-edit commits skipped SAST entirely and silently, and the staged
filter whose letters bound this entry's receipt guarantee; fixed in the SAME diff as this entry),
BL-178 (the per-index subdir that adds the `/<n>/` segment), BL-112 (the honest-NOTRUN contract
that holds here).

---

## BL-183: `producer | grep -q` under `set -o pipefail` inverts a predicate via SIGPIPE — size-dependent, so it passes every small fixture

**Logged:** 2026-07-26 (split out of BL-181 remediation round 3, finding R-B-7 — the class was
described there but never given an owner)
**Category:** Enforcement correctness / portability — silent predicate inversion in gate scripts
**Severity:** Medium — a predicate that reads FALSE when it should read TRUE, in scripts that decide
whether a commit is allowed; but each site needs its own reachability proof, so this is an audit,
not a known live break.

**The mechanism, measured during BL-181.** Under `set -o pipefail`, `grep -q` exits the instant it
matches. The upstream producer is still writing, dies of `SIGPIPE` (rc 141), and `pipefail` promotes
that to the pipeline's status — so a pipeline whose *content* matched reports **failure**. Whether it
fires depends on how much the producer still had to write when the downstream exited, i.e. on FILE
SIZE, so it is invisible on small fixtures and appears only on real inputs. Measured instance:
`_check_unit_lane` in `scripts/lint-tests-registered.sh` gave `rc=141` on
`tests/test-bl112-commit-enforcement.sh` with `grep -q` versus `count=4` with `grep -c`, and picked a
*different* victim file on consecutive runs of the same tree. Fixed there by making every stage a
full-input consumer (`# BL-181-UNIT-LANE-PREDICATE`, and the long "WHY `grep -c` AND NOT `… | grep -q`"
comment above it).

**Scope of the audit — candidate sites, not confirmed breaks.** Non-comment `… | grep -[a-z]*q`
pipelines in files that set `pipefail`, measured 2026-07-26 on this tree — **80 sites across 13
files**, three of them authoritative gate scripts:

| sites | file |
|---|---|
| 34 | `scripts/pre-commit-gate.sh` |
| 9 | `scripts/process-checklist.sh` |
| 8 | `scripts/check-phase-gate.sh` |
| 5 | `scripts/upgrade-project.sh` |
| 5 | `scripts/lint-counter-antipattern.sh` |
| 4 | `scripts/validate.sh` |
| 4 | `scripts/lint-fail-emit-exit-status.sh` |
| 3 | `scripts/lint-no-live-remote-in-tests.sh` |
| 3 | `scripts/lib/hook-templates.sh` |
| 2 | `scripts/detect-out-of-band-commits.sh` |
| 1 each | `scripts/lint-raw-read-prompt.sh`, `scripts/lint-fix-functions-stderr.sh`, `scripts/check-changelog.sh` |

Reproduce with:
```
for f in scripts/*.sh scripts/lib/*.sh; do
  grep -qE 'set -[a-zA-Z]*o[[:space:]]+pipefail' "$f" || continue
  n=$(grep -vE '^[[:space:]]*#' "$f" | grep -cE '\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q')
  [ "$n" -gt 0 ] && printf '%3s  %s\n' "$n" "$f"
done | sort -rn
```

**A site is only a real defect if all three hold** — a mechanical count is an upper bound, not a
finding: (a) the producer can outlive the `grep -q` (large or streaming input — a `printf` of one
line cannot SIGPIPE); (b) the pipeline's status is actually *consumed* (an `if`, `&&`, or captured
`$?`), not discarded; (c) `pipefail` is in effect at that point. Triage the 80 against those three
before changing anything.

**Fix shape (per confirmed site):** make the downstream consume all input — `grep -c` plus a numeric
test, or `grep -q` behind a variable that already holds the full producer output. Do NOT drop
`pipefail`; it is load-bearing elsewhere. Each fix needs the same evidence BL-181 produced: a
multi-KB fixture that fails with `grep -q` and passes with the consuming form (see U12 in
`tests/test-lint-tests-registered.sh` for the pattern).

**Status:** Open

**UPDATE 2026-07-28 — CONFIRMED LIVE, and the census above UNDER-COUNTED because it never
scanned `tests/`.** Two things changed. (1) The class now has a **measured, reproducible
instance outside the lint scripts**, and it is the whole explanation for a "green locally,
red on CI" asymmetry that had been blamed on the semgrep registry. (2) The reproduce recipe
above iterates `scripts/*.sh scripts/lib/*.sh` only — `tests/` was never in scope, and the
confirmed instance lives there. Re-run the census over `tests/*.sh` before calling the
80-site table complete.

**The confirmed instance.** In `tests/test-bl131-domsink-rules.sh` and
`tests/test-bl118-sast-dom-xss.sh`, both of which set `set -uo pipefail`:

```
has_live() { grep -v '^[[:space:]]*#' "$1" | grep -qF -- "$2"; }
```

(`test-bl118-sast-dom-xss.sh` carries a second copy, `has_cfg`, with `grep -qE` and the same
shape.) The producer is `grep -v` streaming the **whole emitted pre-commit hook** — multi-KB,
which is exactly the "real input, not a small fixture" condition this entry says is required.
`grep -qF` exits on the first match, `grep -v` takes EPIPE, GNU grep exits 2, `pipefail`
promotes it, and **a string that IS present is reported ABSENT**.

| host | grep | rate |
|---|---|---|
| Linux | GNU grep 3.11 | **1–7 failures per 300 runs** |
| macOS | BSD grep 2.6.0 | **0 per 300 runs** |

That asymmetry is the finding: BSD grep does not exit non-zero on the truncated read, so the
whole class is invisible on this repo's primary dev host and appears only in CI. The two
cases it flakes are `T-hook-references-ruleset` (in `test-bl131-domsink-rules.sh`) and
`T-hook-carries-domxss-config` (in `test-bl118-sast-dom-xss.sh`). Both call `has_live` /
`has_cfg` inside an `if`/`elif`/`||`, so condition (b) — the status is consumed — holds.

**The three emitted-hook sites, enumerated, and this is the half that matters more than the
tests.** The table above counts `scripts/lib/hook-templates.sh` at 3. Those three sites are
in the **EMITTED hook** — the bytes written into every generated project's
`.git/hooks/pre-commit` — and the emitted hook runs under `set -euo pipefail` (the only
`pipefail` in the file; nothing in the emitted body ever does `set +o pipefail`, and the
`set +e`/`set -e` pairs around `semgrep scan` and the test command toggle **errexit only**,
so condition (c) holds at all three). **A flaky enforcement gate is worse than a flaky test.**

1. **`# BL-132-GITLINK-SKIP`** — `git ls-files -s -- ":(literal)$soif_p" | grep -q '^160000 '`.
   Producer is one pathspec, so at most one line: condition (a) is very weak. Lowest risk of
   the three; do not "fix" it without a reachability proof.
2. **`# BL-125-COMMIT-TESTS`, npm test-script detection** —
   `sed -n '/"scripts"[[:space:]]*:/,/}/p' package.json | grep -qE '"test"[[:space:]]*:'`.
   `sed -n` with a range keeps reading to EOF after printing, so on a `package.json` past the
   pipe buffer the producer genuinely outlives the `grep -qE`. **Strongest candidate.**
   Failure mode: the `&&` chain reads false, npm detection fails, and the commit-time test arm
   degrades to `soif_tests_not_enforced` — a loud WARN — on a project that *does* have a real
   `npm test`. Loud, but it is the BL-125 gate silently not running.
3. **`# BL-125-COMMIT-TESTS`, placeholder-script rejection** —
   `! sed -n '…' package.json | grep -q 'no test specified'`. Same producer, but the status is
   **negated**, so the inversion runs the other way: a SIGPIPE-truncated read on a
   `package.json` that DOES carry npm's placeholder makes the negation true, the hook adopts
   `soif_test_cmd="npm test"` against the placeholder, and **every commit on a fresh scaffold
   blocks** — the BL-137 "documented-but-impossible" class.

**Explicitly NOT in the fix set.** `soif_test_src=$(git diff --cached … | grep -cE '…')` in the
same block uses `grep -c`, which reads to EOF — no SIGPIPE, and it is already the prescribed
fix shape, with the numeric guard on the next line. And
`[ -f pyproject.toml ] && grep -q '^\[tool\.pytest' pyproject.toml` is **not a pipeline** —
`grep` takes the file directly, so there is no producer to kill.

**Two more `tests/` files carry the shape with `echo`-of-a-variable producers** and were not
rate-measured: `has_review_fail`/`has_bypass_warn`/`has_empty_man_warn` in
`tests/test-bl104-gate-scoring.sh` and `has_review_fail`/`has_bypass_warn`/`has_attested`/
`has_full_six` in `tests/test-bl073-review-manifest-gate.sh`. These echo whole captured gate
outputs (several KB), so triage rule (a) does not automatically clear them — check whether
those two files set `pipefail` before deciding.

**Fix shape is unchanged** (`grep -c` + numeric test, or `grep -q` over a variable that
already holds the full producer output; never drop `pipefail`). The emitted-hook sites need
the house TDD treatment — a multi-KB `package.json` fixture that fails with `grep -q` and
passes with the consuming form — because they are enforcement code shipped downstream.

**Related:** BL-181 (where the class was found, measured, and fixed at one site), BL-168
(`test-bl168-tm-table-sigpipe.sh` — a prior SIGPIPE instance, evidence that this is a recurring class
in this repo), BL-125 (the commit-time test arm two of the three emitted-hook sites belong to),
BL-132 (the gitlink skip that owns the third), CLAUDE.md ENFORCEMENT — SOURCE OF TRUTH.

**UPDATE 2026-07-29 — the two `tests/` sites are FIXED; the entry stays Open for the three
emitted-hook sites and the un-run `tests/` census.** Fixed in PR #280: `has_live` in
`tests/test-bl131-domsink-rules.sh`, and `has_live` + `has_cfg` in
`tests/test-bl118-sast-dom-xss.sh` (marker `# BL-183-NO-SIGPIPE`).

**It is STILL A FLAKE — an earlier revision of this paragraph claimed otherwise and was
refuted by measurement.** What is true is narrower: the rate is a function of how much the
producer still has to write when `grep -q` exits, and #280 roughly **doubled the emitted hook —
645 → 1,221 lines, 41,211 → 87,956 bytes** at `a8dbef7`, the commit CI actually went red on
(the 1,231/88,824 figures elsewhere include the marker lines the FIX adds, so do not use them
for the before/after). That moved the comment-stripped remainder after the match from **5,879
to 8,287 bytes** — recipe, because an absolute byte count is meaningless without one:

```
grep -v '^[[:space:]]*#' <emitted-hook> \
  | awk '/p\/owasp-top-ten/ && !f { f=1; next } f { n += length($0)+1 } END { print n }'
```

**What was withdrawn, and why it matters.** The claim was: *"It stopped being a flake… it fired
on the first CI run, in both files at once. That is not luck."* Measured on Linux / GNU grep
3.11 (the CI toolchain), 1000 runs of the old spelling per hook size: **3/1000 at 41,211 bytes,
9/1000 at 87,956 bytes**. That is 0.9 % — squarely a flake, and squarely inside the **1–7 per
300** band this entry's own table already recorded. Firing on the first run in both files was
luck, on top of a rate that had roughly tripled. **The direction is real and the size coupling
is real; the phase change was not.** Read the rate table as a property of a FILE SIZE — anything
that grows the emitted hook raises it, and the hook grows on nearly every SAST change — but do
not read it as "fixed at size N". This retraction is recorded rather than silently edited
because the withdrawn sentence is exactly the shape [[adversarial-verify-patterns]] warns about:
an absolute claim ("that is not luck") standing in for a rate measurement nobody had taken.

**What it cost, and this is the argument for fixing latent sites of this class before they
bite.** The inversion did not merely fail — it failed with a *security* message. CI reported
`p/owasp-top-ten dropped — the fix must ADD DOM coverage, not trade away the Express-RCE
coverage BL-112 proved` and `the emitted hook's semgrep invocation does not --config the
shipped ruleset (BL-131 wiring absent)`. Both configs were present the entire time. A
predicate that inverts does not report "I could not tell"; it reports the opposite fact with
full confidence, in the vocabulary of the thing it was guarding.

**The fix deviates from the prescribed shape above, deliberately.** This entry prescribes
`grep -c` + a numeric test, or `grep -q` over a variable already holding the producer's full
output. Both keep a pipe and stay correct only because the consumer is made to read to EOF —
i.e. they fix the *symptom* while leaving the hazardous shape in place for the next editor to
re-narrow. These three sites instead use **single-process awk** (`index()` for the fixed-string
predicate, `$0 ~ str` for the ERE one), so there is **no pipe to break** and no invariant a
later edit can quietly violate. Prefer this form for new predicates; the `grep -c` shape
remains correct where a pipeline is unavoidable.

**Evidence (all re-runnable):** the inversion is deterministic given enough trailing output —
`rc=141 PIPESTATUS=141 0` on **macOS/BSD grep** with a 1,688,904-byte fixture whose match is on
line 1, which also **corrects the table above**: BSD grep's "0 per 300" is a size artefact of
the fixture used there, not immunity. Ten paired old-vs-new checks agree on the real emitted hook (5 needles
that must be found, 2 that must not, comment-only text still not "live", the DOMXSS ERE, and
the suffix-typo that must still be rejected). Guarded by **`T-predicate-no-sigpipe`**, which exists in BOTH
`tests/test-bl118-sast-dom-xss.sh` (for its `has_live` + `has_cfg`) and
`tests/test-bl131-domsink-rules.sh` (for its own third copy — that one was unguarded at first,
and reverting it to the pipe spelling left the suite 17/0 green on macOS). Each builds a >1 MB
fixture, asserts the fixture is large enough to force the race BEFORE asserting anything else,
checks both directions so it cannot pass vacuously, and carries an INDENTED comment naming the
same configs plus a comment-stripped variant — so narrowing the comment predicate to `/^#/`,
which would bless a hook whose executable `--config` lines were deleted, also turns it RED.
Restoring the pipe spelling turns it RED in both files (mutation-proven).

**UPDATE 2026-07-30 — the two emitted-hook npm sites are FIXED (`3a5949f`); the entry stays
Open for the gitlink site and the un-run `tests/` census.** Sites 2 and 3 of the emitted-hook
enumeration above (`# BL-125-COMMIT-TESTS` npm detection + placeholder rejection) are replaced
by `soif_npm_scripts_has` — single-process awk, marker `# BL-183-NPM-NO-SIGPIPE` in
`scripts/lib/hook-templates.sh` — per this entry's own deviation note: no pipe to break. The
awk emulates the sed range exactly (opens at a `"scripts" :` line and tests it, closes at the
first in-scope `}`, may re-open later), so the S1/S4 scripts-block scoping is unchanged.

**A precondition in this entry was WRONG, recorded here rather than silently edited.** The
"Fix shape" paragraph above prescribes "a multi-KB `package.json` fixture", and the site-2
enumeration says "on a `package.json` past the pipe buffer". Neither reproduces: `sed`'s range
closes at the first `}`, after which it READS the rest of the file without WRITING, and SIGPIPE
needs a write. **The trigger is a large `scripts` BLOCK** — measured 20/20 inversions on a
~1.2 MB block vs 0/20 on a 1.26 MB file with an ordinary block, independently reproduced by a
second session from scratch (flaky band ~33–55 KB, deterministic from ~82–110 KB). A fixture
built to this entry's own prescription would have shown the defect "unreproducible".

Guarded by **T17/T18/T19/T20** in `tests/test-bl125-commit-test-exec.sh`: detection and
placeholder scope at ~330 KB block scale (both watched RED against the old spelling — T17's
commit LANDED with the gate silently off; T18 REFUSED where the small-file semantics
warn-and-land), whole-block-read completeness (a truncating rewrite goes RED), and a standing
both-directions mutant that re-spells each call back to the old pipeline and requires the
inversion to return. Each case asserts its fixture's post/pre-match block bytes ≥ 150 KB
BEFORE asserting behavior, so a fixture edit cannot quietly turn it vacuous.

**Still open:** (1) `# BL-132-GITLINK-SKIP` — single-line producer, condition (a) very weak;
do not "fix" without a reachability proof, per the triage rule above. (2) The `tests/` census
this entry has never run (the 80-site table scanned `scripts/` only). (3) The two
`echo`-of-a-variable candidates in `test-bl104-gate-scoring.sh` / `test-bl073-review-manifest-gate.sh`.
(4) **The scripts-block scope has a preserved RANGE LEAK on one-line blocks** — found by the
fix's own adversarial review, present in BOTH spellings (equivalence was the contract, so the
awk faithfully keeps it): a one-line `"scripts": {},` (or any one-line block) never closes the
range on its own line — the end pattern is never tested against the opening line, exactly as in
sed — so the range stays open into the NEXT object and a dependency literally named `test`
(`"dependencies": { "test": "1.0.0" }` — a real npm package) still triggers detection.
Reviewer-built fixtures `empty-scripts-leak` / `oneline-block-leak`: both spellings agree,
rc=0. Consequence when it fires: `npm test` adopted with no test script → `Missing script:
"test"` → non-127 non-zero → source commits BLOCK (the BL-137 class). The S1/S4 comment at the
call site now states the leak instead of overclaiming; closing it means deliberately changing
the range semantics — a semantic change the SIGPIPE fix explicitly refused to smuggle in.

---

## BL-184: The full-suite aggregator destroyed its children's failure output — 177 delegates discarded stdout AND stderr, making every CI-only failure unactionable

**Logged:** 2026-07-26 (surfaced while triaging the full-lane run `30204845017`; BL-183 was taken concurrently, so this entry is BL-184)
**Category:** Verification lane / test infrastructure — diagnostic destruction (silent-success sibling class)
**Severity:** High — not a product defect (nothing shipped behaves wrongly), but a force multiplier on every *other* defect: it converted every CI-only child failure into an unactionable one-liner. The cost is measured, not hypothetical — BL-135 sat open 2026-07-18 → 2026-07-26 across two ~3h full-lane runs with zero root-cause progress, because the diagnostic was destroyed at the moment of capture.
**Status:** Closed — shipped + merged 2026-07-27 (PR #276 `ffc43a8`). All 177 aggregator delegates now preserve child stdout AND stderr on failure instead of `>/dev/null 2>&1`, so a CI-only child failure is actionable rather than a `run for details` that could not be run. **Its cost was still being paid after the fix landed**: the full-lane run `30204845017` (2026-07-26, one day BEFORE this merged) reports `[FAIL] tests/test-bl033-install-cmds-shape.sh FAILED (run for details)` and nothing else — see **BL-135**, whose second CI data point is that same run; its `run for details` is unactionable only because the run predates this fix by a day.

**Evidence.** All 177 delegates in `tests/full-project-test-suite.sh` matched exactly
`if bash "$SCRIPT_DIR/<child>" [args] >/dev/null 2>&1; then / pass / else / fail / fi` — verified
mechanically: 177 blocks, every one 5 lines, shape `PASS|ELSE|FAIL`, all flush-left. On failure the
sole output was `<child> FAILED (run for details)` — and "run for details" is impossible for a
failure that only reproduces in CI. Watched-RED A/B on a real child
(`tests/test-bl169-gitignore-anchor.sh` forced red):

BEFORE — `[FAIL] tests/test-bl169-gitignore-anchor.sh FAILED (run for details)` and nothing else.
AFTER — the child's four `[FAIL]` case lines **plus its stderr**, inline:
`grep: /nonexistent/forced-red-proof.tmpl: No such file or directory` — the actual root cause. The
old shape discarded **stderr** as well as stdout, so the causal line was thrown away every time.

**Fix shape.** `run_child_suite <rel-path> <pass-label> [fail-label] [-- <child-args>...]`, marker
`# BL-184-CHILD-EVIDENCE`, closed by `# BL-184-CHILD-EVIDENCE-END`. Captures combined stdout+stderr
to a scratch file outside `$TEST_DIR` (the TEST 4 fixture block documents an invariant that
`$TEST_DIR` holds only simulated project dirs); on rc=0 emits only `pass` — byte-identical labels,
zero extra log bytes; on rc≠0 emits `fail` then a delimited replay: a failure-marker digest (cap 25,
emitted only when output exceeds the tail bound, because a pure tail MISSES an early failure in a
chatty child) followed by the last 40 lines, each prefixed `    | ` so a child's `[FAIL]` can never
be misread as the suite's own. Bounds are env-overridable (`SUITE_CHILD_TAIL_LINES`,
`SUITE_CHILD_MARKER_LINES`); 40 was chosen from six measured children (8/10/18/18/30/53 lines) so the
median child replays whole.

**The helper always returns 0** — the aggregator is `set -euo pipefail` and calls it as a bare
statement, so a non-zero return would abort the whole run at the first red child. Accounting stays in
`fail()` and the suite still ends `exit $FAIL`. Replay uses `awk`/`printf`, never `echo -e` (child
output is arbitrary text). No `cmd | grep | head` capture anywhere — that is the repo's own
counter-antipattern trap.

177/177 converted; equivalence proven by re-parsing both file versions and comparing the
`(child path, child argv, pass-label, fail-label)` 4-tuple for all 177 sites in order. One delegate
stays deliberately exempt: the BL-180 pty test already captured its own output and branches on a
**success-side** LOUD SKIP that the helper cannot express (the helper prints nothing on rc=0).

**Mutation proof.** M1: point the replay `awk` at `/dev/null` → `Results: 11 passed, 3 failed`
(T1/T2/T3 RED). M2: revert the capture to the literal `>/dev/null 2>&1` regression → same RED.
Restore → `Results: 14 passed, 0 failed`. Pinned by `tests/test-bl184-child-suite-evidence.sh`,
which **slices the real aggregator** through its `-END` marker so it drives the shipped helper text
rather than a copy; T13 additionally fails if any delegate regresses to the discard shape.

**Related:** BL-135 (the measured cost — two full-lane runs lost), BL-034 / BL-035 (wired these 177
delegates in, with the discard shape), BL-038 / BL-154 / BL-181 (registration lints), BL-180 (the one
delegate that already captured, and why it stays exempt), BL-064 (silent-success-after-FAIL — same
defect class, different surface).

---

## BL-187: The commit-time SAST rule-coverage guard is a NAMED-STRING DETECTOR, not a proof — and semgrep's per-rule timeout is a POLICY decision Karl has not made

**Logged:** 2026-07-27 (R-274Rv2-1 residue, filed as part of the remediation that closed the reproduced trigger; measured through the shipped emitter `soif_write_precommit_hook` → a real `.git/hooks/pre-commit` → real `git commit`s, semgrep 1.157.0)
**Category:** Enforcement / commit-time SAST — scanner-coverage attestation (the residue left after fixing the reproduced trigger)
**Severity:** **Medium.**
- It is **not High.** The reproduced trigger is closed: `# BL-187-RULE-COVERAGE` reads semgrep's `Warning: N timeout error(s) in <target> when running the following rules: [...]` line back out of the captured stderr and forfeits the `[OK]` receipt, naming the target and the exact rule. A commit that hits it now gets a loud NOTRUN instead of a false attestation.
- It is **not Low**, for two independent reasons. (1) The check's good case is the warning's **ABSENCE**, so unlike the selection half of the invariant it *cannot* fail closed — a future semgrep that renames, reformats or drops that warning re-opens the exact R-274Rv2-1 hole, silently and in every generated project, with no test able to notice. That is a **fail-open anchor** shipped into enforcement code, and it is the first one in this arm. **BL-192 is what that risk looks like when it lands** — a different clause of the same guard, blinded by an upstream release with no spelling change at all. Treat that as a demonstration, not a coincidence. (2) The failure mode when it does fire is the worst one available: a positive false attestation over a file no rule matched.
- **Medium is where those meet:** trigger closed, but by an instrument that is structurally weaker than the one beside it, and the arm now certifies commits on the strength of a string semgrep is not contractually obliged to print.

**Status:** Open

**SHIPPED ON MAIN VIA THE BL-112 SPLIT — AND THE #278 REMAINDER'S COPY OF THIS ENTRY MUST BE DELETED
DURING REBASE, NOT MERGED.** This entry, and the `# BL-187-RULE-COVERAGE` guard it describes, reached
`main` on branch `fix/bl112-sast-coverage-portable`, ported by commit `dbd78fa`. The unmerged remainder
of PR #278 (`fix/bl112-sast-scan-coverage`, `e87dbd3`) still carries its **own divergent copy** of this
entry — measured against the ported text as of `dbd78fa`, 104 lines there against 78 here, with 68
differing lines. **Simulated read-only and it lands
silently:** `git merge-tree --write-tree dbd78fa e87dbd3` reports `Auto-merging
solo-orchestrator-backlog.md` with **no conflict**, and the resulting file holds **TWO** `## BL-187:`
headers and **zero** conflict markers (the other three shared files *do* conflict, so a resolver never
looks at the backlog). Nothing catches it: `scripts/lint-backlog-references.sh` has no duplicate-header
check and no ordering check.
- **Mitigation applied in the same commit:** this entry was **moved out of the tail (it had been
  appended after BL-191) into its numeric 185-189 slot** — the same slot the remainder puts its own
  copy in, so the two insertions now collide. Re-simulated from the moved position, that merge reports
  `CONFLICT (content): Merge conflict in solo-orchestrator-backlog.md` and leaves conflict markers in
  the file. The collision is **visible** and has to be resolved by hand. Keep this entry in numeric
  order for exactly that reason — moving it back to the tail restores the silent path. (Re-run the
  simulation rather than trusting this line; the marker count moves with the text.)
- **DO NOT RENUMBER.** `# BL-187-RULE-COVERAGE` is already shipped in the emitted hook
  (`scripts/lib/hook-templates.sh`); renumbering the entry desyncs it from its marker, which is this
  repo's citation primitive.

**What was reproduced, exactly.** A **dense** 1,216,567-byte `.ts` — ordinary generated-bundle-looking
code (object literals with an arrow function each), valid UTF-8, `tsc` compiles it — carrying
`pane.innerHTML = userText;` on line 2, staged and committed through the real hook:

| staged bytes | padding | verdict | receipt |
|---|---|---|---|
| 196,561 | code | REFUSED | `[BLOCKED] Semgrep` |
| 600,561 | code | REFUSED | `[BLOCKED] Semgrep` |
| **1,216,567** | **code** | **COMMITTED** | **`[OK] semgrep: SAST ran on 1 staged file(s)`, sink in `HEAD`** |
| 1,253,093 | comments | REFUSED | `[BLOCKED] Semgrep` |

Deterministic — 5 of 5 repeat runs at the dense >1MB size committed with the receipt. Semgrep's own
stderr, invoked with the arm's exact flag set: `Scanning 1 file with 174 Code rules:`,
`✅ Scan completed successfully.`, `Findings: 0 (0 blocking)`, `Targets scanned: 1`, `rc=0` —
**every fact the selection half checks read COMPLETE** — plus
`Warning: 1 timeout error(s) in …/heavy.ts when running the following rules:
[javascript.browser.security.insecure-document-method.insecure-document-method]`. The one rule that
catches the sink is the one that ran out of semgrep's default 5-second per-rule, per-file budget.

**The `Warning:` line is not the ONLY line carrying the atom, and that is why the guard counts LINES
(R-772-4).** Once `--timeout-threshold` trips, semgrep also prints
`Semgrep stopped running rules on <target> after N timeout error(s).` — so **one** timeout can yield
**two** atom-bearing lines, at the shipped defaults (`--timeout=5`, `--timeout-threshold=3`) and with
no flag change. `soif_sg_timeouts` is `grep -cE 'timeout error\(s\)'`, i.e. a count of *lines*, and
the operator-facing sentence reads "N rule-timeout **warning line(s)**" to match. **The verdict is
unaffected either way** — it is `-eq 0`, and any non-zero count forfeits the receipt.
**Do not "fix" it by narrowing the count to `Warning: [0-9]+ timeout error\(s\)`.** That was
considered and rejected: it is the *match-the-sentence* shape this very entry exists to warn about
(every extra token is another upstream-rename cliff), it buys nothing the verdict uses, and the
watched-RED case it would owe — "the threshold-skip line arrives without the `Warning:` line and the
verdict still fires" — needs three real timeouts on one target, which is host-speed-dependent; the
existing `T-mutation-rule-timeout` already carries an explicit SKIP arm for a host whose semgrep
finishes the rule inside its budget. A guard whose proof can only skip on some hosts is not a guard.
That the second line *also* carries the atom is what makes the threshold path **covered** rather than
missed, and it is a property of the broad anchor — narrowing would give it up.

**Size was never the variable — DENSITY was.** The comment-padded row above is the control and it is
the whole reason this shipped: every oversize case in `tests/test-bl132-sast-index-scan.sh` rode a
fixture padded with 7,000 identical `// paddingpadding…` lines, which is the one >1MB shape
structurally incapable of provoking a per-rule timeout. The suite proved `--max-target-bytes=0` on the
only large-file shape immune to the residue that makes the flag insufficient. Fixed with
`write_oversize_dense` + `T-oversize-dense-no-receipt` + `T-mutation-rule-timeout`.

**THE POLICY QUESTION FOR KARL, AND IT IS THE POINT OF THIS ENTRY: does the pre-commit hook keep
semgrep's 5-second per-rule timeout?** Three options, measured, none of them free:

1. **Keep the 5s default + the detector (what shipped).** A dense >1MB file goes UNSCANNED but the
   commit says so loudly and the receipt is forfeited. Honest, bounded latency.
   **An earlier revision of this option argued from a claim that the very commit carrying this entry
   retires, and the citation is withdrawn rather than repeated.** It said the outcome was exactly the
   "all of the cost and none of the coverage" result that `# BL-112-MAX-TARGET-BYTES` *calls* worse.
   That marker no longer says any such thing: it now records that argument as **(b)**, labels it
   **MEASURABLY WRONG**, and states "Do not restate (a) or (b); they are refuted" — because measured,
   keeping the cap leaves the shortfall guard-VISIBLE (`accepted 0 of 1`) while disabling it converted
   a visible shortfall into an invisible one. The option stands without the citation: a loud forfeited
   receipt is honest and bounded, and choosing between that and a longer budget is a latency question,
   which is option 3 and not the implementer's to pick.
2. **`--timeout=0`.** Measured: the dense fixture is **`[BLOCKED]`** — the sink is caught — in ~11s
   wall. But "no limit" in a pre-commit hook means a rule with catastrophic backtracking hangs the
   operator's terminal with **no message and no timeout**, which is worse than a forfeited receipt on
   every axis this arm cares about: not loud, not honest, indistinguishable from a crash, and the
   fastest possible route to `--no-verify` becoming habit.
3. **A finite larger value (`--timeout=30`, `--timeout=60`).** Almost certainly the right answer, but
   it is a **latency budget** — how long may a commit block? — and picking the number by feel is the
   kind of decision this repo files rather than guesses.

**Related:** BL-112 (the silent-success class this arm exists to close), BL-192 (the sibling clause
that was withdrawn when its instrument went blind — the realised version of this entry's risk (1)),
BL-118 / BL-131 (the rulesets whose findings this guard protects), `# BL-187-RULE-COVERAGE` and
`# BL-112-SCAN-COVERAGE` in `scripts/lib/hook-templates.sh`.

---

## BL-190: The `unit` fast lane reached its own 20-minute cap and began blocking PRs for ADDING a test rather than for failing one

> **Numbering note.** This entry and BL-191 were first filed as BL-185/BL-186. PR #278 was already
> open with its own BL-185…BL-189, so it has precedence and these two were renumbered to BL-190/191
> before either branch merged. Any pre-merge reference to "BL-185 (the lane rebalance)" or
> "BL-186 (the per-line fork)" means these entries.

**Logged:** 2026-07-28
**Status:** Open — remediation shipped on branch `perf/unit-lane-shard-rebalance`; flip to Closed with
the PR # once merged (a Closed entry must cite a PR # or a backticked SHA, and neither exists yet).
**Category:** CI capacity / merge-blocking
**Severity:** High — a required status check that fails on capacity, not on correctness, blocks every
PR indiscriminately and teaches everyone to ignore it.

**The measurement.** `.github/workflows/tests.yml` `unit` had `timeout-minutes: 20` and was running a
serial list of 136 test files. Job 90083307522 (run 30297887329, main @ `9d71824`) took **18m51s**;
the preceding two main runs were 19m21s and 20m00s. PR #278 added SAST cases and its `unit` job was
**CANCELLED at 20m15s** — "The operation was canceled", not an assertion failure. The lane was at its
cap, so any PR that added a test case failed on wall clock regardless of content.

**Where the time went** (per-test `::group::` spans extracted from the two job logs; only >=15s shown):

| seconds | file |
|---|---|
| 318 | `tests/test-run-lints.sh` |
| 243 | `tests/test-lint-counter-antipattern.sh` |
| 122 | `tests/test-pre-commit-gate-lints.sh` |
| 77 (213 on PR #278) | `tests/test-bl132-sast-index-scan.sh` |
| 54 | `tests/test-bl131-domsink-rules.sh` |
| 41 | `tests/test-lint-raw-read-prompt.sh` |
| 37 | `tests/test-upgrade-sync-framework.sh` |
| 34 | `tests/test-plan-staging.sh` |
| 16 | `tests/test-lint-doc-anchors.sh` |
| 170 | **the other 127 files, together** (avg 1.34s) |

85% of the lane is nine files; the remaining 127 are noise. That shape is why sharding is a complete
fix and no test needed deleting, skipping or demoting.

**The duplication is real, and was verified rather than assumed.** `tests/test-run-lints.sh`'s
`T-all-pass` arm runs `scripts/run-lints.sh` over the **real repo** — all 11 lints end to end.
`tests/test-lint-counter-antipattern.sh` is 12 cheap fixture cases plus `T9: MERGE GATE`, which runs
the linter over the **real repo**; `tests/test-lint-raw-read-prompt.sh` and
`tests/test-lint-doc-anchors.sh` have the same real-repo arm. `.github/workflows/lint.yml` already
runs each of those lints over the repo in its own parallel job, and `counter-antipattern-lint`,
`raw-read-prompt-lint` and `doc-anchors-lint` are all **required** checks.

**The count was wrong: it is FOUR, not three.** The original filing said the counter-antipattern
scan runs three times per PR. Re-counted against the workflows and the run logs, the full-tree scan
executed **four** times:

| # | site | measured |
|---|---|---|
| 1 | `lint.yml` `counter-antipattern-lint`, step "Lint counter-capture antipattern" | 207s |
| 2 | `lint.yml` `counter-antipattern-lint`, step "Show PASS/FAIL inventory" — the `--list` re-scan, then gated `if: always()`, so it re-ran on SUCCESS too | 204s |
| 3 | `tests/test-lint-counter-antipattern.sh` `T9: MERGE GATE` | (of the 243s) |
| 4 | `tests/test-run-lints.sh` `T-all-pass`, via `scripts/run-lints.sh` | (of the 243s) |

(1) and (2) from run 30297887996 job 90083310253, main @ `9d71824`. The missed one was (2) — a
second execution hiding inside the *same job* as (1), which is why a per-job reading found three.
**Site (2) is now gone on green runs**: this change also flips lint.yml's inventory steps to
`if: failure()` (BL-191), so a passing PR pays the scan three times and a failing one still pays
four. The rest are genuine merge gates the suites own, so nothing was removed — (3) and (4) were
moved off each other's critical path.

**The fix — rebalance, not a bigger cap.** Raising `timeout-minutes` was explicitly rejected: it only
hides the next doubling. `unit` became a matrix job `unit-shard` over
`[lint-sweep, lint-scan, sast, slow-misc, rest]`, cap **lowered** 20 → 12 so it stays a tripwire.
Nothing is demoted: the set of tests gating a PR is identical before and after.

**The headline number was overstated, and is corrected here.** The original commit subject and this
entry both claimed "~5.5 min critical path". That is the **unit lane's** new long pole, not the
PR-blocking critical path. Sharding alone would have left the PR floored at **~7-9 min** by
lint.yml's required `counter-antipattern-lint` job — **measured 6m59s** on main (run 30297887996,
job 90083310253, @ `9d71824`) and **9m03s** on PR #278 (run 30380689795, job 90347515417,
@ `8ea8c6c`) — which sharding does not touch. So the honest framing is: **~5.5 min for the unit
lane; the PR-blocking critical path becomes ~7-9 min, floored by lint.yml's required
counter-antipattern-lint.** That refutation is what motivated folding the BL-191 lint.yml fix into
the same change; with it, the lint floor drops to ~3.6-4.6 min and the expected critical path
becomes **~6 min, set by this lane's `lint-sweep` shard**. All post-change timings are **DERIVED**,
not observed — no run has yet executed the five-leg topology or the `if: failure()` lint jobs.

**The cost side, on the record.** Sharding buys wall clock with billable minutes and job count.
DERIVED (GitHub bills each job rounded UP to the whole minute; ~22s per-job overhead measured from
the old serial job's non-test steps):

- **Unit lane:** ~19 → ~26 job-minutes (6+6+6+4+3 for the five legs at PR #278's worst case, plus 1
  for the `unit` aggregator; ~23 on a main-like tree where `sast` is 144s not 281s).
- **Lint jobs**, thanks to the BL-191 `if: failure()` change: ~16 → ~12 job-minutes
  (counter-antipattern 7→4, raw-read-prompt 2→1, the other seven unchanged at 1 each).
- **Whole PR:** ~35 → ~38 job-minutes across **10 → 15 jobs**, for ~18m53s → ~6 min of wall clock.

The trade is a real one and should be re-judged if the runner bill matters more than PR latency.

**Two structural hazards the design had to dodge, both load-bearing.**
1. `_build_unit_list_set` in `scripts/lint-tests-registered.sh` scopes the unit list with an
   **unanchored** `awk '/tests=\(/…'` that does **not** strip comments. A second array whose name ends
   in that token — or the token merely appearing in a comment or an `echo` string below the array —
   re-opens the scope and folds every following `tests/test-*.sh` path into the lint's membership set.
   A new test named only in a comment would then satisfy the lint while never running: verbatim the
   BL-181 defect class. Hence the pin arrays are `pin_*`, and the prose below the array is worded to
   avoid the token. Proof: the parser's output is byte-identical before and after (136 entries), and
   `scripts/lint-tests-registered.sh --list` is byte-identical (209 rows, 29 `unit-lane-exempt`).
2. `rest` is the complement of the **pinned** paths, not of the paths some shard actually ran, so
   deleting a leg from the matrix would silently stop running that leg's pinned tests with the
   partition arithmetic still balancing.

**Hazard 2's first guard did not close it, and was rebuilt.** The original guard pinned
`strategy.job-total` to a hand-written `shard_arms=5`. That is a second hand-kept copy of the same
fact, and its own error message told you to update it (*"Change the matrix list, the case arms and
the pin arrays TOGETHER, then update shard_arms"*) — so a maintainer who follows the instructions
deletes the leg, bumps the count, and the pinned tests vanish anyway. **Proved reachable**: on a
scratch copy, deleting the `sast` leg + its `case` arm + `shard_arms` 5→4 left all four remaining
shards **green** while `tests/test-bl118-sast-dom-xss.sh`,
`tests/test-bl131-domsink-rules.sh` and `tests/test-bl132-sast-index-scan.sh` ran in **no** shard —
133 of 136, with the in-workflow partition assertion still balancing because `pinned` still counted
them and `rest` still excluded them.

Rebuilt so the **case dispatch is the single source** of the pinned set: a `shard_names` roster
declared once, a `pins_for()` that cases on exactly those names, `pinned` built by walking the
roster *through* `pins_for`, and the dispatch reading the same function. An orphaned `pin_*` array
is then never claimed, so its paths fall back into `rest` and **still run**. Mutation proof, all
four executing the real `run:` script extracted from the committed YAML:

| mutation | result |
|---|---|
| N1 — delete `sast` from BOTH matrix and roster (the real maintainer action) | **fail-safe**: `rest` 126 → **129**, partition still 136, all tests still run |
| N2 — delete the leg from the matrix only | every leg exits 1: `shard roster drift: the matrix declares 4 leg(s) but the roster names 5` |
| N3 — delete the name from the roster only | every leg exits 1, same guard, inverted |
| N4 — roster name with no `pins_for` arm (typo class) | every leg exits 1: `'sasts' is in the roster but has no arm in pins_for` |

The matrix leg count remains the one hand-kept correspondence — it lives in YAML the script cannot
read — but it is now non-silent in both directions (N2 and N3).

**Also:** `unit` is a **required status check** on `main` (confirmed via
`gh api repos/kraulerson/solo-orchestrator/branches/main/protection`). A matrix cannot keep that name,
so `unit` survives as a zero-work aggregator job that is red unless every `unit-shard` leg is green.
Renaming or deleting it would leave every PR waiting forever on a check that never reports.

**FOR KARL — branch protection decision, not yet made.** The required contexts on `main` are
`unit` plus eight lint jobs. The five new `unit-shard (<shard>)` checks are **not** individually
required, by design — the `unit` aggregator is red unless every leg is green, so they are covered
transitively. If you would rather each leg be independently required, that is a branch-protection
edit nobody can make from a PR, and it must be done in the same window as the merge or the `unit`
context alone will gate.

**Pre-existing finding, unrelated to this change but recorded here because it surfaced during it:**
`lint.yml` defines **nine** lint jobs but only **eight** are required on `main` —
`evalprompts-portability-lint` runs on every PR and **does not block**. Confirmed against the
protection API contexts list. Not fixed here; it is a policy call.

**Related:** BL-191 (the per-line fork that makes the counter-antipattern scan cost 4 minutes in the
first place — the deeper fix; its `if: failure()` half shipped with this change), BL-154 / BL-181
(the unit-lane membership lint this had to leave behaviourally untouched), BL-077 (which created
these lanes).

---

## BL-191: `lint-counter-antipattern.sh` forks a subshell per LINE, and every PR paid that ~4-minute scan four times — two of them in the same job

> **Numbering note.** Filed first as BL-186; renumbered to BL-191 because PR #278 already held
> BL-185…BL-189. See the note on BL-190.

**Logged:** 2026-07-28
**Status:** Open — the **duplicate-execution half is FIXED** on branch
`perf/unit-lane-shard-rebalance` (below); the **per-line fork itself is not**, and that is what this
entry stays open for. Flip to Closed only when `scan_file` is single-pass.
**Category:** CI capacity / lint performance
**Severity:** Medium — no correctness impact; it is the single largest cost in PR CI, and it is the
root cause under BL-190's symptom.

**The mechanism.** `scan_file` in `scripts/lint-counter-antipattern.sh` reads each file into an array
and then, for every line, runs `echo "$line" | grep -Eq "$ANTIPATTERN_RE"` — a fork plus a pipe **per
line** across `scripts/**`, `tests/**` and `init.sh`. Measured cost of one full-tree scan: **243s** on
`ubuntu-latest` (run 30297887329), ~90s on the macOS host.

**It was paid FOUR times per PR, not three.** The original filing (and BL-190's) said three. The
missed execution was a second one inside the *same* `counter-antipattern-lint` job, which is why a
per-job reading undercounted:

| # | site | measured |
|---|---|---|
| 1 | `lint.yml` `counter-antipattern-lint` — the gating step | 207s main / 269s PR #278 |
| 2 | `lint.yml` `counter-antipattern-lint` — the `--list` inventory step, gated `if: always()` | 204s main / 269s PR #278 |
| 3 | `tests/test-lint-counter-antipattern.sh` `T9: MERGE GATE` | (of the 243s) |
| 4 | `tests/test-run-lints.sh` `T-all-pass` → `scripts/run-lints.sh` | (of the 243s) |

Sources: run 30297887996 job 90083310253 (main @ `9d71824`, job total **419s**) and run 30380689795
job 90347515417 (PR #278 @ `8ea8c6c`, job total **543s**). In both, the inventory step costs
**almost exactly half the job**.

### SHIPPED with BL-190: `if: always()` → `if: failure()` on the inventory steps

**The count here is NINE, not three and not eight.** Every job in `lint.yml` is a PAIR — a gating
step that runs the lint, and an inventory step that re-runs the *same* lint with `--list`. There are
nine jobs and therefore **nine** such pairs, and all nine inventory steps were `if: always()`.
Two greps undercount and both were used at some point in review:

- `grep -c 'sh --list'` returns **8**. It misses
  `bash scripts/lint-backlog-references.sh --base "origin/${BASE_REF}" --list || true`, where
  `--base …` sits between `sh` and `--list`.
- Counting by step name misses `review-manifest-lint`, whose step is named "Show roster", not
  "Show PASS/FAIL inventory".

Structural count (parse the YAML, don't grep): 9 jobs, 9 `if: always()` steps, 9 `--list` steps, and
the sets coincide exactly — **there is no `always()` step that is not a `--list` re-scan.**

**Nothing stops being checked.** The gating steps are untouched: nine of them, no `if:`, no
`continue-on-error`. Only the inventory re-scan became conditional, and `failure()` and `always()`
are *identical on the failure path* — the only path the inventory was ever for. Evidence from three
real runs where a gating step failed:

| run | job | gating step | inventory step | job conclusion |
|---|---|---|---|---|
| 29952639143 | backlog-references-lint | **failure** | success (ran) | **failure** |
| 29633780347 | counter-antipattern-lint | **failure** | success (ran) | **failure** |
| 29136956152 | backlog-references-lint | **failure** | success (ran) | **failure** |

Run 29633780347's `no-live-remote-in-tests-lint` is the clearest read of the semantics: its middle
step, which has no `if:`, shows **skipped** after the failure while the `always()` inventory step
shows **success**. That is exactly the situation `failure()` also selects. So a red lint still goes
red, still blocks, and still prints its inventory; the `|| true` still prevents the inventory from
ever being what fails a job — proven by the same run, where the tree was dirty enough to fail the
gate and the inventory step still concluded `success`.

**"or on demand" was never real.** `lint.yml` has no `workflow_dispatch` trigger — only
`push: branches: [main]` and `pull_request` — so `github.event_name == 'workflow_dispatch'` would be
unreachable dead code, and a UI re-run preserves the ORIGINAL event name rather than becoming a
dispatch. Plain `if: failure()` therefore loses nothing that existed. The step names dropped "or on
demand" to match; the genuine on-demand path is local: `bash scripts/lint-<name>.sh --list`.

**Saving (DERIVED — no run has executed the `if: failure()` topology):** counter-antipattern-lint
419s → ~215s on main and 543s → ~277s on PR #278; raw-read-prompt-lint 89s → ~47s; doc-anchors-lint
38s → ~22s. Because the lint jobs run in PARALLEL, the PR-blocking lint floor is the *slowest* one,
so it moves from **~7-9 min to ~3.6-4.6 min** — below the sharded unit lane's ~5.5 min, making that
lane the new long pole for the first time.

### STILL OPEN: the per-line fork

**The fix.** Replace the per-line fork with a single-pass `grep -nE` over each file (or over the whole
target set), then post-process only the matching lines for the sanitizer/allowlist checks. The
neighbour-line lookahead (`LINES[i+1]`) and the BL-121 sed-alternation rule both still need the file
body, so the rewrite has to preserve line numbering — this is why it is not a trivial edit.

**Why it is still not bundled.** This is an **enforcement script**, so it needs the house TDD
treatment: break the marked line → RED → restore → GREEN, against
`tests/test-lint-counter-antipattern.sh` (13 cases incl. the BL-121 arms). The `if: failure()` change
above is a workflow-only edit with no behaviour change to any lint, which is why it could ride along;
rewriting `scan_file` cannot. Expected remaining payoff: roughly **-240s from the `lint-sweep`
shard, -240s from `lint-scan`, and a further -190s from lint.yml's required job** — i.e. it is now
the only thing left that lowers the ~6 min critical path.

**Related:** BL-190 (the lane rebalance this sits under, and where the `if: failure()` half shipped),
BL-121 (the sed-alternation rule the rewrite must preserve), BL-067..BL-071 (the wave-1 remediation
this lint backstops).

---

## BL-192: On semgrep >= 1.171.0 `Parsed lines: ~100.0%` is reported for a file semgrep never decoded — the banner's SPELLING did not change, its VALUE stopped being true, and any guard reading it grants `[OK]` over an unscanned sink

**Logged:** 2026-07-28 (found by an isolated-venv two-version diagnostic run while splitting the BL-112 SAST-coverage stack; measured on macOS and Linux)
**Category:** Enforcement / commit-time SAST — scanner-coverage attestation. **This is a defect in the INSTRUMENT, not in the clause that read it**, which is why the clause was withdrawn rather than repaired.
**Severity:** **High.** The argument, with the counter-argument stated first because it is real:
- **The case for Medium.** It is not a regression. `main` has never shipped a parse/decode clause, so nothing that works today stops working. The withdrawn clause is not in any generated project. And the trigger needs a staged file semgrep cannot decode.
- **Why High wins anyway.** (a) The outcome is a **positive false attestation** — `[OK] semgrep: SAST ran on N staged file(s) — no ERROR-severity findings.` printed over a file containing `pane.innerHTML = userText` that no rule ever saw. That is the exact shape BL-112 and BL-118 exist to prevent, and this arm's own severity convention treats "losing a verdict" and "asserting a false one" as different classes. (b) It is **LIVE right now** for anyone whose semgrep is >= 1.171.0 — but on the LOCAL hook surface only, and **the two facts an earlier revision of this leg rested on were both false.** Generated projects **DO** pin semgrep in CI: every CI template that runs it pins `image: semgrep/semgrep:1.170.0` — one uniform version across 22 pin sites (all 10 github, all 10 gitlab, plus bitbucket `python`/`typescript`; the remaining 8 bitbucket templates ship no semgrep job at all), copied verbatim by `init.sh`'s `cp "$SCRIPT_DIR/templates/pipelines/ci/$host/$ci_template"`. And `init.sh` never tells operators to install it: `grep -cE 'brew install semgrep|pip install semgrep' init.sh` = **0** — that advice lives in `docs/user-guide.md` and `docs/builders-guide.md` (and the platform modules), where it *does* resolve to latest. What survives, and is the surface this clause actually rides, is that the **pre-commit hook runs whatever `semgrep` is on the operator's PATH**, unpinned — so a machine set up from those docs today is already past the threshold. **AND THAT PIN IS THE NEAR-TERM TRIGGER, WHICH IS THE MOST ACTIONABLE LINE IN THIS ENTRY: 1.170.0 is exactly ONE RELEASE below 1.171.0.** A routine currency bump — the ordinary maintenance this repo performs on every pinned tool — carries **every generated project's declared semgrep** across the blindness threshold in a single step, and the CI job is deliberately held at hook parity (BL-148: "The scan's config + severity flags MIRROR the local pre-commit hook … so CI and the dev gate enforce the IDENTICAL ruleset"), so the two surfaces are meant to converge on whatever that pin says. **Be precise about what the bump does and does not do**, because overclaiming it is how this entry got its facts wrong the first time: per the two-version table below, BOTH versions fail to decode the fixture, so crossing 1.171.0 does not change what a scan *finds*. What it changes is that the instrument stops **reporting** the loss — which is precisely what turns a restored clause into a guard-shaped object, and what makes "it passed on our pinned semgrep" stop being evidence about anything. The defect is one version bump away from being the default condition, not merely latent. (c) The trigger set is **wider than exotic encodings** and includes at least one shape that is ordinary source — a hard token-stream break in a `.ts` file is deterministic, not a coin flip. (d) There is **no operator workaround**, because there is nothing for an operator to observe: the banner reads 100%, the exit code is 0, and the findings list is empty. A defect an operator cannot detect and cannot route around does not get to be Medium.

**Status:** Open

**The two-version table.** Identical fixture in every row: an ordinary TypeScript file saved as
UTF-16LE **with a BOM** (what a Windows editor writes when "Unicode" is picked from the encoding
dropdown), carrying `pane.innerHTML = userText`. Isolated venv per version, this arm's exact flag set,
default verbosity. Both platforms agree.

| semgrep | `Parsed lines:` reported | what actually happened | a guard reading it says |
|---|---|---|---|
| **1.157.0** | `~85.7%` | file not decoded, sink unseen | receipt FORFEITED — correct |
| **1.171.0** | `~100.0%` | file not decoded, sink unseen | **`[OK]` — false attestation** |

**The banner SPELLING did not change.** This is the part that makes it dangerous rather than merely
inconvenient. Every fail-closed defence in `# BL-112-SCAN-COVERAGE` is built for a *renamed or
reformatted* line: if the anchor stops matching, the variable stays empty and the arm NOTRUNs loudly.
That machinery works perfectly here and protects nothing, because the line still matches, still parses,
and still yields a number. **The number is what became untrustworthy.** No amount of parser hardening
detects this; a fail-closed anchor cannot fail closed on a value that is well-formed and wrong.

**`--json` is not an escape — it is strictly worse.** Measured on the same fixture: the JSON output
affirmatively reports **both files as scanned** and **`skipped: []`**. So switching the arm to `--json`
would replace an untrustworthy number with an explicit positive claim that nothing was skipped. That is
a downgrade, and it is recorded here so the next reader does not spend the afternoon on it.

**`--x-ls-long` does expose skip reasons and cannot carry a gate.** It surfaces per-target skip
information, which is the right *shape* of evidence — but it is an experimental flag (the `x-` prefix
is upstream's own marker) and is documented as unstable. An unstable interface behind a commit-blocking
gate is a permanent-NOTRUN cliff waiting for a release, which is the failure BL-112 exists to end.

**The open design question, which is the actual work item.** The guard must **verify the decode
itself** rather than trusting semgrep's self-report. Everything in `# BL-112-SCAN-COVERAGE` today is a
question about what the scanner *says*; this stage needs a question the hook can answer *about the
bytes it already holds* — it materializes every staged blob into a temp tree before invoking semgrep,
so the bytes are in hand. Candidate directions, none of them evaluated yet, listed so the next reader
starts from a set rather than a blank page:
- decode-check the materialized target directly (BOM sniff, NUL-byte scan, a UTF-8 validity pass) and
  forfeit the receipt on anything the hook cannot itself read as text — the strongest option, because
  it depends on nothing upstream;
- `--verbose` and anchor on `[WARN] Syntax error at line <target>:N`, which IS a real discriminator
  (count 1 on a broken file, 0 on the clean control) — but turning `--verbose` on for every commit is a
  change to the shipped invocation and the one path where stderr reaches the operator verbatim, so it
  is a policy call, not a bug fix. **Do NOT anchor on `Partially analyzed due to parsing or internal
  Semgrep errors`** — measured, that is a section HEADER printed on EVERY verbose scan (count 1 on the
  clean control too); what changes is the bullet beneath it, ` • <none>` vs ` • brokensink.ts`;
- pin semgrep to a known-good version in generated projects — rejected as a *solution* (it freezes rule
  coverage to buy a coverage check) but worth recording as a mitigation.

**DECISION 2026-07-29 (Karl) — DO NOT PIN semgrep, and this is deliberate, not an oversight.**
**Scope: this repo's own CI installs** (`.github/workflows/tests.yml`, two `pip install semgrep`
sites — both now carry a pointer comment back to this paragraph) **and the emitted hook's PATH
resolution.** Recorded here because "unpinned dependency" reads as a defect to anyone auditing the CI
config, and the next agent to see `pip install semgrep` with no version WILL want to fix it. The
reasoning: *a security scan is no good if a project is several weeks or months old and the scanner
isn't checking for new vulnerabilities.* Pinning trades away exactly the thing the scanner exists
for. The measured facts support leaving it: § BL-193 showed the version drift (1.171.0 → 1.172.0 in
**a day**) was **not** the cause of the `sast` failures — both versions emit a byte-identical banner,
and `test-bl132` **was 38/0/0 on each at that measurement** (the suite has since grown; it reads
39/0/0 with `T-status-on-stdout-earns-receipt`) — so pinning was never buying correctness here, only
build determinism.

**SECOND DECISION, same day, after the pin-vs-float ramifications were laid out (Karl) — the 22
generated-project CI templates FLOAT too, sequenced AFTER BL-198 lands, with version logging added at
the same time.** Today `templates/pipelines/ci/**` pins `image: semgrep/semgrep:1.170.0` at 22 sites —
one release below the 1.171.0 threshold where this entry's metric silently changed meaning, which is
what makes "safely frozen" an illusion. Karl's reasoning applies MOST to generated projects (they are
the ones that age), and detection is measured non-monotone (a fixture 1.157.0 misses, 1.171.0
catches), so a pinned project never receives that catch. Sequencing is load-bearing: float only after
BL-198 removes every dependence on scanner-reported numbers. Filed as **BL-201**, which also carries
the trap: `tests/test-bl147-ci-template-integrity.sh` Cg4/Cg5-image REQUIRE the version-pinned image
form, so the float commit must update that suite in the same diff or go red.

**The consequence for THIS entry is the load-bearing part: the PRIMARY fix must not depend on
semgrep's behaviour at all.** With the scanner deliberately free to change under us — now on every
surface — any gate whose CORRECTNESS rests on what semgrep *reports* is a future permanent-NOTRUN or
a future false receipt, whichever way the next release moves. A question about bytes the hook already
holds has no version to drift; that is **BL-198** (transcode-first). A *detector* built on semgrep's
reporting is admissible only as best-effort hardening whose failure degrades to today's behaviour —
never to a false receipt — and only with a framework-side canary test pinning the exact spelling so
drift is loud; that is **BL-200**.

**What was pulled, and where it is — FIVE cases, not six.** The clause (`# BL-186-PARSE-COVERAGE`,
plus `# BL-186-EMPTY-TARGETS`), its two report lines, its two NOTRUN sub-arms, and **five** test
cases — `T-utf16-parse-drop-no-receipt`, `T-mutation-parse-coverage`, `T-parse-coverage-fails-closed`,
`T-parse-threshold-exact`, `T-mutation-parse-threshold` — live on the
unmerged branch `fix/bl112-sast-scan-coverage` (`e87dbd3`). They are **correct code against a broken
instrument**; do not re-derive them. Restore them **only** with a decode check that does not depend on
`Parsed lines`, and re-measure on the semgrep the project actually has — a green suite on a pinned old
semgrep is exactly how this gap would ship. Note in particular that `T-parse-threshold-exact` and
`T-mutation-parse-threshold` exist because the `-ge 100` threshold was UNPINNED once and a reviewer's
`-ge 100` → `-ge 99` mutant survived the entire PR-blocking set; a restoration owes those back.

**Why five and not six — the measured set difference, because this list was wrong twice.** Comparing
the `echo "=== T-<name> ==="` banners in `tests/test-bl132-sast-index-scan.sh` between `e87dbd3` (38
distinct case names) and this split (33), **six** parse-named cases are present only on `e87dbd3` —
the five above plus `T-parse-coverage-no-cry-wolf`. That sixth one was **RENAMED to
`T-coverage-no-cry-wolf` and KEPT**, rescoped from `# BL-186-PARSE-COVERAGE` onto
`# BL-112-SCAN-COVERAGE`; it is the only name in the "only in new" side of the diff. Genuinely
withdrawn is therefore **five**. Separately, an earlier revision of this list named
`T-empty-target-receipt` as pulled — it was not: it is **live at HEAD** and KEPT, rescoped to pin a
cry-wolf risk on the SELECTION clause (a `Scanning 0 files` header must not NOTRUN every placeholder
commit forever), and the suite's own header says so. **Count withdrawals, not renames** — a renamed
survivor read as a casualty is how a restoration ends up re-deriving a case that never left.

**Related:** BL-112 (the silent-success class), BL-118 (the DOM-XSS ruleset whose findings this stage
protects), BL-187 (the sibling clause with the same fail-open shape — this entry is what that risk
looks like once realised), and the `# BL-112-SCAN-COVERAGE` block in `scripts/lib/hook-templates.sh`,
which carries the same measurement inline so a reader of the code does not need this file.

**UPDATE 2026-07-30 — the PRIMARY fix this diagnosis called for is IMPLEMENTED: BL-198
(transcode-first) landed in `02eaa0f` (`# BL-198-TRANSCODE`).** The false-attestation shape this
entry measured — a UTF-16 staged sink collecting the `[OK]` receipt — now BLOCKS (watched RED
then GREEN through the real emitted hook, 8 fixture rows). Per this entry's own DECISION
blocks, no clause of the fix reads anything semgrep reports. The entry STAYS OPEN deliberately
for its two spawned residues: BL-200 (the token-stream break, the best-effort `--verbose`
detector + canary) and BL-201 (the 22 template pins float, sequenced after BL-198 — now
unblocked). Close this entry when both land.

---

## BL-193: On CI the emitted hook forfeited the SAST receipt on essentially EVERY clean commit, cascading 13 mutation/coverage proofs into silent SKIPs while the shard reported only 3 named failures — NOT reproducible on any local platform, cause unknown

**Logged:** 2026-07-28 (observed on the `sast` shard while validating the BL-112 SAST-coverage stack; recorded WITHOUT a diagnosis, deliberately)
**Category:** CI / test-instrument integrity — the green-looking-permanent-SKIP class
**Severity:** **Medium-High**, and the severity is about the SKIP CASCADE, not about the receipt.
- The receipt forfeiture itself is the honest direction: a hook that cannot verify coverage WARNs and lets the commit land. If that were all, this would be Low and cosmetic.
- What makes it serious is what it did to the **proofs**. Thirteen mutation and coverage cases are written to `skip_` when the unmutated control does not produce an `[OK]` receipt — correctly, because a mutation proof whose GREEN direction never fires proves nothing and must not report PASS. When the receipt is forfeited on every clean commit, **all thirteen skip at once**, and the shard's summary line shows 3 named failures. Thirteen enforcement proofs stopped proving anything and the transcript looked like a three-failure run.
- That is this repo's named **green-looking-permanent-skip** class (the same shape as BL-181's comment-exemption hole and BL-187's host-speed SKIP arm): the signal is not a red test, it is the *absence* of a test, and nothing in the tally distinguishes the two.

**Status:** Closed — root-caused and fixed 2026-07-29, merged in PR #280 (`8f36382`).

**The cause, and it was never a flake:** semgrep writes its scan-status banner
(`Scanning N files with M Code rules:`) to **stderr on macOS** and **stdout on the GitHub Linux
runner**. The coverage parse hard-coded stderr, so on CI the header count read **0**,
`soif_sg_accepted` stayed empty, coverage could never be verified, and the emitted hook **NOTRUNed
every clean commit** — a permanent cry-wolf on any host that routes it that way. Version drift was
eliminated as a cause first (byte-identical banner on 1.157.0 and 1.172.0; `test-bl132` 38/0/0 on
both), as was the stream-moves-under-CI hypothesis (`CI=true`, `GITHUB_ACTIONS=true` — stderr in
every combination, both versions).

The fail-open half of the defect, the `# BL-193-STATUS-STREAM` fix, and its pinning case are
narrated ONCE, in the root-cause section below (**ROOT CAUSE — FOUND, 2026-07-29**) — this
closure block deliberately does not repeat them.

**Result on CI:** the `sast` shard passed for the first time in four rounds, and — the outcome this
entry's severity was always about — **`test-bl132`'s silent skips fell from 10 to 2**. The skip
cascade, not the receipt, was the damage: thirteen mutation and coverage proofs had stopped proving
anything while the shard reported three failures.

**Two supporting fixes shipped with it, both of the class BL-197 now owns.** `# BL-193-EVIDENCE`
replaced a `tail -8` that printed past the SAST section the cases had already captured;
`# BL-193-COUNT` replaced `"absent or unreadable"`, which collapsed "saw 0" and "saw 2+" — two
conditions needing different operator actions — into one phrase. **It took four CI rounds to read a
root cause that was on screen from the first failing run**, because three layers of instrumentation
were each discarding it. That is the transferable part and it is why BL-197 exists.

**The recommendation this entry carried was NOT what fixed it, deliberately.** It said "preserve
`$soif_sg_err` as a CI artifact" — which would have meant editing shipped enforcement code to retain
a temp file for a debugging need. Unnecessary: the bytes were already being captured and thrown away
at the last step.

**Original entry (pre-close, kept for audit trail):** everything below this line was written
while the cause was unknown; its directives are historical (the recommended capture is DONE,
the candidates are eliminated, the root cause is found — see the dated sections as they
resolve, in order).

**NOT REPRODUCIBLE LOCALLY, on any platform tried.** macOS (arm64), Linux/arm64 and Linux/x86_64 all
receipt a clean commit normally. **No cause is proposed here, deliberately.** Candidate stories exist
— registry reachability from the CI runner, a semgrep version difference on the runner image, a
sandbox/tmpdir interaction with the BL-132 index temp tree, `PATH` resolution of `semgrep` inside the
hook — and every one of them is a guess. Writing a guess into this entry would give the next reader a
hypothesis to confirm instead of a measurement to take, which is how the BL-104 scoring inversions
survived two reviews.

**Recommended next step, and it is a single concrete action.** Re-run the `sast` shard with **the
hook's semgrep stderr captured as a CI artifact.** The hook already writes it to `$soif_sg_err` and
already deletes it (`rm -f "$soif_sg_err" "$soif_sg_out"` at the end of the SAST arm); the diagnostic
is to preserve that file, or to have the test harness copy it out, on the runner. Everything needed to
choose between the candidate stories is in those bytes — the Scan Status header, the exit code, the
config-resolution errors — and nothing else measured so far distinguishes them.

**Also worth fixing regardless of the cause: the tally must not hide this.** A shard that skips 13
proofs and prints 3 failures is under-reporting by a factor of four. `tests/test-bl132-sast-index-scan.sh`
already prints `!! N case(s) SKIPPED — skipped != passed.` before its `Results:` line; the CI summary
does not surface it. Consider failing a shard, or at minimum annotating it, when the skip count crosses
a threshold — a run where most of the enforcement proofs skipped is not a run that validated anything.

**Related:** BL-183 (a *different* CI-only-vs-local asymmetry measured in the same session, with a
known cause — do not conflate them; that one is GNU-vs-BSD grep under `pipefail`, this one is not
explained), BL-181 (the green-looking-exempt class), BL-187 (a host-dependent SKIP arm in the same
suite, which is why the skip vocabulary is load-bearing here), BL-184 (the aggregator that discarded
child output — the reason CI-only failures in this repo are hard to read at all).

**UPDATE 2026-07-29 — one candidate story is now REFUTED BY MEASUREMENT: it is not the semgrep
version.** This entry deliberately listed candidates without endorsing one. Eliminating them by
measurement is the intended way to close it, so recording the elimination — not just the survivors —
is the point of this update.

The run that produced the 3 failures + 10 skips installed **semgrep 1.172.0** (`pip install semgrep`,
unpinned; it had been 1.171.0 a day earlier — the drift is continuous). This host runs 1.157.0, and
"the runner has a different semgrep" was the strongest story on the list. Measured:

| measurement | 1.157.0 | 1.172.0 |
|---|---|---|
| Scan Status banner on the exact 5-file fixture `T-coverage-no-cry-wolf` uses | `Scanning 5 files with 174 Code rules:` | **byte-identical** |
| header count seen by the guard's regex / exit code | 1 / rc=0 | 1 / rc=0 |
| `tests/test-bl132-sast-index-scan.sh`, full suite | **38 passed, 0 failed, 0 skipped** | **38 passed, 0 failed, 0 skipped** |

Every one of the 3 CI failures and all 10 CI skips **passes locally on the CI version itself**. So the
banner the `# BL-112-SCAN-COVERAGE` guard parses did not change spelling or value across the drift,
and the version difference explains nothing here. **Do not re-derive this.** Cross-reference BL-192,
which is about the *soundness* of a different semgrep metric on ≥1.171.0 — that finding stands and is
unaffected; this one is only about whether the version explains BL-193, and it does not.

**Measurement trap that cost a false negative on the first attempt, recorded so the next reader does
not repeat it.** A pip-installed semgrep in a venv still reports the **Homebrew** version if
`/opt/homebrew/bin` is on `PATH` — `$VENV/bin/semgrep --version` printed `1.157.0` while
`pip show semgrep` said `1.172.0`. Measure with the environment cleared:
`env -i PATH="$VENV/bin:/usr/bin:/bin" "$VENV/bin/semgrep" --version`. Without that you compare a
version against itself and conclude, wrongly, that there is no difference to find.

**Surviving candidates, unranked:** sandbox/tmpdir interaction with the BL-132 index temp tree,
`PATH` resolution of `semgrep` inside the emitted hook on the runner, and runner-side registry
behaviour.

**THE RECOMMENDED ACTION IS DONE — and it did not need a product change (`# BL-193-EVIDENCE`).**
The recommendation above was "preserve `$soif_sg_err` as a CI artifact", which would have meant
editing the emitted hook — shipped enforcement code — to keep a temp file for a debugging need.
That was the wrong place, and it was unnecessary: **the bytes were already being captured and
then thrown away.** All three failing cases write the hook's FULL output to `$TOPTMP/<log>` and
then report only `tail -8` (or `tail -3`) of it — which on these fixtures lands squarely on the
unrelated `[WARN] no test command configured` block plus git's commit summary. The SAST section
was in the file the whole time and never reached the transcript. **That is the BL-184
evidence-destruction class one level below the aggregator**: BL-184 fixed the parent discarding
its children's output; here the child discards its own.

Replaced with `sast_evidence()`, which prints every line matching the emitted hook's SAST
reporter vocabulary plus semgrep's own banner — deliberately the whole vocabulary, so an arm
that fires for an unanticipated reason is still shown rather than filtered out by a guess about
which arm it will be. Failure-path only; it cannot change a verdict. Its falsifier is runnable
as written: point it at a log with no SAST section and it prints `(no SAST section in <path>)`
rather than nothing, because silence would be indistinguishable from a helper that never ran.

**FIRST DIAGNOSIS FROM THE CAPTURE (2026-07-29) — three candidates eliminated, and the surviving
one needs a number the message was not printing.** The instrumented run says, in the hook's own
words:

```
  Scanning 5 files with 174 Code rules:
 • Targets scanned: 5
[WARN] semgrep exited 0, but its scan-status line was absent or unreadable.
  SAST NOT ENFORCED for this commit
```

**semgrep scanned all five files and said so, and the guard rejected the report anyway.** The
header is byte-clean — dumped from the CI log, no ANSI, no trailing bytes, exactly the shape
`^[[:space:]]*Scanning [0-9]+ files? with [0-9]+ Code rules?:[[:space:]]*$` accepts.

Eliminated by measurement, not by argument:
- **Not the version.** Byte-identical banner on 1.157.0 and 1.172.0; `bl132` 38/0/0 on both.
- **Not the stream.** The banner is on stderr under `env -i`, under `CI=true`, and under
  `CI=true GITHUB_ACTIONS=true` — both versions. It never moves to stdout.
- **Not a locally-reproducible multi-header.** Under the FULL three-config invocation the hook
  actually runs, the header count is **1** in all four version × env combinations.

So the count the guard saw on the runner was 0 or 2+, and **the message named neither** — the
parse requires the header exactly once, and "absent or unreadable" collapses two conditions that
need different fixes. Added `# BL-193-COUNT`: the report now prints the observed count and says
which case it is. This is an operator-facing improvement independent of BL-193 — a generated
project hitting this was told its coverage was unverifiable with no way to tell why.

**ROOT CAUSE — FOUND, 2026-07-29. semgrep puts its scan-status banner on a DIFFERENT STREAM on the
runner, and the guard hard-coded one.** The instrumented run answered it in one shot: the count came
back **0** — the header the parse needs is not on stderr at all on the GitHub runner, while the same
header is plainly visible in the transcript. It is visible because the findings dump prints
`$soif_sg_out` (STDOUT) unconditionally on the scan-completed path. Measured: **STDERR on this macOS
host, STDOUT on the GitHub Linux runner**, on both 1.157.0 and 1.172.0.

So on the runner `soif_sg_hdr_n` read 0, `soif_sg_accepted` stayed empty, coverage could never be
verified, and the emitted hook **NOTRUNed every clean commit** — a permanent cry-wolf on any host
where semgrep routes it that way. Not a flake, not a test artefact: a shipped defect in the gate.

**The half that matters more than the cry-wolf.** FOUR readers hard-coded `$soif_sg_err`, and one of
them is the **fail-OPEN** clause — `soif_sg_timeouts`, whose contract is "no timeout seen ⇒ coverage
may be granted". A stream-blind read there returns 0 unconditionally and the hook grants an
**unearned `[OK]` over a target whose rule was abandoned** — precisely the BL-112 false-attestation
defect this arm exists to prevent. Crying wolf is loud and wrong; that one is silent and wrong.

**Fix (`# BL-193-STATUS-STREAM`).** All four readers now read a merged view of both streams.
Concatenating rather than picking a stream is deliberate: correct whether the banner is on one, the
other, or split; needs no guess about which frontend is installed; and fails **CLOSED** — a banner
duplicated across both counts 2, which the exactly-once rule already treats as unparseable.

**Pinned by `T-status-on-stdout-earns-receipt`** in `tests/test-bl132-sast-index-scan.sh`: a semgrep
shim that behaves exactly like the runner (banner on stdout, no findings, exit 0) must still earn the
`[OK]` receipt. **Hermetic and deterministic** — no real semgrep, no registry, no network — so unlike
the three cases this defect actually broke, it cannot go UNPROVEN on a quiet host. bl132 39/0/0.

**Why it took four CI rounds, which is the transferable part.** The evidence was on screen the whole
time and three successive layers of instrumentation were discarding it: the aggregator (BL-184), then
a `tail -8` that landed on an unrelated WARN block, then a message that collapsed "saw 0" and "saw
2+" into "absent or unreadable". Each layer had to be fixed before the next became visible.

**Superseded — kept for the audit trail.** The list below was written before the cause was known:
`SAST NOT ENFORCED … the scanner did not run` (semgrep never ran — `PATH` resolution inside the
hook on the runner) · `semgrep could not complete (exit N)` (ran and failed; `N` discriminates) ·
`SAST coverage was PARTIAL` or `could not materialize staged content` (the BL-132 index temp
tree — sandbox/tmpdir) · a `Scanning N files with M Code rules:` line whose `N` differs from the
staged count (the coverage arithmetic, and we would finally see the number). That set covers
every surviving candidate above, which is what makes it the single action worth taking.

---

## BL-194: A documentation comment silently became the enforced policy — `test-bl147`'s parity derivation scoped on `/semgrep scan/`, so the FALSIFIER prose above the invocation won and 22 CI templates were graded against an empty policy

**Logged:** 2026-07-29 (found while diagnosing PR #280's `unit-shard (rest)` failure)
**Category:** Test-instrument integrity — unanchored scoper reads comments (the `_build_unit_list_set` class)
**Severity:** Medium. It fails LOUD, so nothing shipped wrong — but it fails loud **in the wrong
vocabulary**, and that cost a full mis-diagnosis that was written into a handoff as settled fact.
**Status:** Closed (2026-07-29, PR #280) — for the derivation. The general lint gap it exposes is
carried on BL-181, which already owns the sibling instance.

**What happened.** `tests/test-bl147-ci-template-integrity.sh` derives the semgrep policy that all 22
CI templates must match from the emitted hook itself — deliberately, so the flags are never retyped.
It scoped that derivation with:

```
awk '/semgrep scan/ { collecting=1 } collecting { …join line-continuations… }'
```

Unanchored, and it never stripped comments. PR #280 added a `FALSIFIER:` block above the invocation
which — as a falsifier must — **names the command it wants the reader to run**:

```
#     semgrep scan "${A[@]}" big.ts               # in-project  -> Targets scanned: 1
```

That comment is the first `/semgrep scan/` in the file. It carries no trailing `\`, so the collector
emitted that one prose line and exited. Result: `configs='' severity='' error=no`, and every
`Cg3-*`/`Cg5-*` case then compared a real template against the **empty** policy and failed.

**Why this is worth an entry rather than a one-line patch.** The failure named the wrong subsystem.
Seven `[FAIL]` lines said *config parity broken across 22 templates* — a hook↔CI divergence — when the
templates were untouched and correct. The diagnosis that followed blamed `--max-target-bytes=0` for
being absent from the templates and proposed adding an inert flag to all 22 files; that conclusion was
recorded in `docs/handoffs/2026-07-29-sast-coverage-and-ci-lane.md` § 3 as reproduced and settled. It
was neither. **A loud failure is not a safe failure if it accuses the wrong component** — the cost of
this class is measured in the work the message sends the next reader off to do.

**Same shape as the one CLAUDE.md already warns about.** `_build_unit_list_set` in
`scripts/lint-tests-registered.sh` scopes the `tests.yml` array with an unanchored `awk '/tests=\(/'`
and likewise does not strip comments — which is why the pin arrays there are named `pin_*`. Two
instances now, in two different files, both from *matching on a token that prose is entitled to use*.

**The fix.** Anchor the collector on a marker prose cannot forge, rather than on the command's name:
`# BL-194-HOOK-SEMGREP-POLICY` in `scripts/lib/hook-templates.sh` sits immediately above the
invocation; the derivation starts there, skips the marker's own comment lines, and collects the first
executable line. It then **asserts the collected text contains `semgrep scan`**, so a marker that
drifts away from the invocation fails `Cg-derive` with a message naming *the anchor* and stating
explicitly that the CI templates are not implicated.

Guarded by two new cases in the same suite: `Cg-derive-prose-immune` (decoys before the anchor, after
the anchor, and in a trailing comment — the derivation must still land on the real invocation) and
`Cg-derive-marker-required` (no anchor ⇒ derive **nothing**; never fall back to guessing). Four
mutation proofs, all RED then restored GREEN at 56/0: delete the anchor gate; delete the comment-skip
rule; move the marker to the top of the hook (this is the shipped FALSIFIER, run verbatim); delete the
marker entirely.

**THE FIRST FIX WAS ITSELF FORGEABLE — caught in adversarial review, and the second-order defect
is the interesting one.** Arming on the FIRST marker occurrence meant that adding the marker to
`hook-templates.sh`'s own header marker index — which is how that file documents every other
marker, and what CLAUDE.md's CITATION RULE pushes an author toward — re-opened BL-194 with the
*identical* 7-line "22 templates disagree" signature. The fix had moved the defect from "a token
prose is entitled to use" (`semgrep scan`) to "a token prose is *also* entitled to use" (the
marker name), while the new guard case's banner claimed documentation could "NEVER" move the
verdict. The collector now tries **every** occurrence in file order and accepts the first whose
collected text contains `semgrep scan` (`# BL-194-DERIVE-TRY-EVERY`), so a mention anywhere —
header, footer, this entry — is skipped rather than winning. First-match and last-match are each
forgeable from one end; only try-every closes both.

**A failed derivation now SKIPS the parity cases instead of running them against nothing**
(`# BL-194-DERIVE-GATE`). Fixing only the derivation still left `1 correct + 6 accusatory`
`[FAIL]` lines naming CI templates by file whenever Cg-derive failed — the same misdirection with
a smaller multiplier, in the suite whose whole purpose here was to stop accusing innocent files.
Skipping is safe rather than a hole: that path is reachable only alongside a `[FAIL] Cg-derive`,
so the suite is already red, and the skip count prints on its own line
(`!! N case(s) SKIPPED — skipped != passed.`) per this repo's skip vocabulary.

**TRY-EVERY WAS STILL NOT ENOUGH — round three.** Trying every occurrence fixed the header-index
forgery but lost to any EARLIER occurrence whose next non-comment line contains `semgrep scan`:
a stale anchor+invocation pair left by a refactor, or the marker embedded in a **string** rather
than a comment. Both are worse than the original defect in one specific way — the derivation
*succeeds* on the wrong text, so `# BL-194-DERIVE-GATE` never engages and the suite emits the
original 7-line "22 templates disagree" signature with **zero** correctly-attributed lines.
Closed by requiring **exactly one** resolving occurrence (`# BL-194-DERIVE-UNAMBIGUOUS`): two or
more derive nothing and `Cg-derive` fails naming the ambiguity. Measured — both placements now
give `53 passed, 1 failed (6 skipped)`: one correct line, six skips, nothing accused. Pinned by
`Cg-derive-ambiguous-anchor`. The claim in `hook-templates.sh` that the marker was safe to name
"anywhere else" was refuted by the string case and is now scoped to comments.

**Atoms pinned, and the ones that are NOT — stated rather than assumed covered.** Three
one-character narrowings survived the first round of guards at 56/0. Now: narrowing the marker to
`/BL-194/` fails (`Cg-derive-decoy-marker-first`); narrowing the comment test to `#[[:space:]]`
fails (`Cg-derive-comment-widths`); deleting the `semgrep scan` acceptance check fails.
**`[[:space:]]*` -> `+` is BEHAVIOUR-NEUTRAL and deliberately not pinned** — the `sub()` only
strips leading blanks and the `^#` test runs on the result, so a column-0 comment is unchanged by
either spelling and still matches; measured across 11 line shapes on three awk implementations
(BWK, mawk, gawk) with zero verdict differences, suite green under the narrowed form. The
`HOOK_POLICY_OK` gate is the second unpinned atom: replacing its condition with a constant false
leaves the suite green, because it only changes OUTPUT on an already-red run. Both are named in
the suite rather than given fixtures that would pass for the wrong reason — the practice
CLAUDE.md already uses for BL-181's two unpinned atoms.

**The `!collecting` guard was on that unpinned list and should not have been.** The stated
reason — that a verdict could flip "only if such a line carries a `--config`" — was REFUTED: a
continuation line beginning `#` with **no trailing backslash** ends the command in bash, so
dropping it mid-collection makes the collector join the NEXT, unrelated command and import both
its `--config` and its `--severity`. It is now pinned by `Cg-derive-continuation-comment`.
Recorded because the error was in the *argument for leaving it unpinned*, not in the code —
which is the harder failure to notice.

**Only the one-line marker ships downstream.** The rationale lives framework-side, above
`soif_write_precommit_hook`. The first revision put a 10-line essay *inside* `cat <<'HOOKEOF'`,
writing ~870 bytes of framework test-infrastructure prose — including the path
`tests/test-bl147-ci-template-integrity.sh`, which does not exist in a generated project — into
every downstream `.git/hooks/pre-commit`.

**Residual, stated rather than papered over.** The anchor makes *prose* harmless but does not make the
suite immune to every edit — if a future refactor splits `semgrep scan \` and its first `--config`
across two lines, the derivation still collects correctly (it joins continuations), but if the marker
is separated from the invocation by a non-comment line the assertion fires. That is the intended
direction: loud and correctly attributed, never silent.

**Related:** BL-181 (the sibling unanchored-awk instance and its two residuals), BL-147 (the suite this
lives in), BL-112 (the `# BL-112-MAX-TARGET-BYTES` prose whose falsifier triggered it), and the
`adversarial-verify-patterns` memory note requiring a runnable falsifier in shipped comments — this
entry is the first case where **satisfying that rule broke a test**, which is a cost of the rule worth
knowing, not an argument against it.

---

## BL-195: WITHDRAWN — duplicate of BL-135 (Closed), filed in error

**Logged:** 2026-07-29 · **Withdrawn:** 2026-07-29, same day, before merge (adversarial review, R-BK-2)
**Status:** Won't Fix — withdrawn as a duplicate; the defect is real and is owned by **BL-135**, which
is Closed with the fix `c98775c`.

**What it claimed.** That `tests/test-bl033-install-cmds-shape.sh` failing on the full lane while
passing locally 8/0 was an untracked CI-only red, and that the next step was to spend a
`workflow_dispatch` (~3h) re-diagnosing it. It also warned the reader *not* to assume it shared a
cause with BL-135.

**Why that was wrong — and it is worth keeping rather than deleting.** BL-135's title is
*"test-bl033-install-cmds-shape fails on ubuntu CI and is GREEN on macOS — the harness depends on the
host having Homebrew"*. It is the same test, the same asymmetry, and BL-135's own body **already
cites the identical run** `30204845017` as its second CI data point. It was root-caused (a Homebrew
probe in `scripts/resolve-tools.sh`) and fixed at `c98775c` — which is an ancestor of `main` but
**NOT** of `d970b27`, the head that run tested. So the observation was a pre-fix head reproducing an
already-solved defect, and the entry told the next reader to spend three hours re-deriving it while
explicitly steering them away from the entry that had the answer.

**The transferable part.** The evidence was collected correctly and interpreted without checking
whether an existing entry already owned it. A `grep -n 'test-bl033' solo-orchestrator-backlog.md`
before filing would have surfaced BL-135 immediately. **Before filing a CI-only asymmetry, grep the
backlog for the failing test's name.** This repo has several such asymmetries and they do NOT share
a cause — BL-135 was a host Homebrew probe, BL-183 was GNU-vs-BSD grep under `pipefail`, and the
`sast`-shard one tracked on PR #280 was a stream difference in semgrep's status banner. Three
symptoms that look identical in a transcript, three unrelated mechanisms; pattern-matching on the
symptom is unreliable in both directions, which is what produced this duplicate.

**Residual worth one line, and only one.** The run cited is pre-fix, so it is not evidence that
`test-bl033` still fails today; equally, no post-`c98775c` full lane has been run. If a future full
lane shows it red again, reopen **BL-135**, do not file a new entry.

---

## BL-196: Nothing catches a broken or misspelled `# BL-NNN-…` marker comment, though CLAUDE.md makes it the repo's citation primitive

**Logged:** 2026-07-29
**Category:** Enforcement gap / citation integrity
**Severity:** Medium — silent. A marker that is renamed, typo'd or deleted breaks every citation that
points at it, and no lint, test or gate notices.
**Status:** Open

**The gap.** CLAUDE.md § CITATION RULE says to cite code by a grep-able `# BL-NNN-…` marker comment
or a function name, **never** a bare `file:line`, because line numbers have mis-resolved within 24h
of a handoff being written. The marker is therefore load-bearing infrastructure — and it is
completely unenforced. There is no lint that:
- resolves every `# BL-NNN-…` marker cited in `solo-orchestrator-backlog.md`, `docs/**` or
  `CLAUDE.md` to an actual occurrence in the tree; or
- flags a marker defined in code that no document references (dead citation anchor); or
- catches a marker whose `BL-NNN` prefix names an entry that does not exist.

**Why it is worth a lint rather than review vigilance — with a worked example produced by the very
commit that files this entry — and the example got SHARPER when its first version turned out to be
wrong.** BL-179's closure, in this same diff, credited `# BL-179-TESTARM-FILTER` (the BL-125 test
arm moving to `ACMDRT`) to **PR #274**. Adversarial review reported the marker "exists nowhere",
which was true of `main` at `818c6eb` — and false a day earlier and 14 minutes later, because the
marker had been on the unmerged PR #280 branch since `dbd78fa` (2026-07-28) and #280 merged as
`8f36382` while this branch was being corrected.

So the real defect was never invention. **It was MISATTRIBUTION: a real marker and a real change,
described accurately, credited to the wrong PR.** That is the stronger case for this lint, not the
weaker one — an invented marker at least fails a grep, whereas a correctly-spelled marker cited
against the wrong PR resolves fine and is invisible to `lint-backlog-references.sh`, which checks
only that a cited **entry** exists and never that a cited **marker** does, still less that it landed
where the citation says. Both readings of this incident passed every automated check the repo has;
only human-grade review caught either. And the first correction was itself falsified by a merge
between writing and pushing, which is the second lesson: **a marker claim is stamped with a tree,
and "exists nowhere" is a statement about one commit, not about the repo.**

**Scope, measured rather than asserted — and stamped, per the lesson above.** An earlier draft of
this entry claimed markers with a test backstop are "the exception". That is false: **measured at
`818c6eb`**, of **202** `# BL-NNN-…` marker families in `scripts/`, `init.sh` and `tests/`, **165 are
named somewhere under `tests/`**. (At `8f36382`, after PR #280, the same recipe reads **215 / 177** —
the ratio is stable, the absolute numbers are not, which is exactly why the stamp is here.) Naming is weaker than
asserting — a mention in a comment is not a guard — so the count of markers whose *loss* would turn a
suite red is lower than 165 and has not been measured here. The gap this entry files is therefore
**not** "markers are unprotected"; it is that **nothing validates the citation direction**: prose →
marker, and marker → entry.

**Suggested shape.** A `scripts/lint-bl-markers.sh` doing three passes: (a) every `# BL-NNN-` marker
in `scripts/**`, `tests/**`, `init.sh` resolves to a `## BL-NNN:` entry; (b) every marker cited in
prose resolves to a marker in code; (c) a floor so the lint cannot pass vacuously if the grep breaks.
Registration per the house rule: `scripts/run-lints.sh` picks up `lint-*.sh` automatically, plus a
`.github/workflows/lint.yml` job if it is to block.

**Related:** CLAUDE.md § CITATION RULE, BL-179 (whose closure carried the worked example above),
BL-038/BL-181 (the registration-lint family this would join).

---

## BL-197: The diagnostic-destruction class — an instrument that discards the evidence needed to act on the failure it is reporting

**Logged:** 2026-07-29 (three instances measured in one session — two cost a CI round-trip each; the
third, BL-184's, cost eight days across two ~3h full-lane runs)
**Category:** Verification lane / observability — meta-class
**Severity:** Medium-High **as a class**. No single instance is a product defect; together they are a
multiplier on the time-to-diagnose of every OTHER defect, and each was found only after its cost —
a round-trip or, for instance 1, eight days — was already paid.
**Status:** Open

**The class.** *A diagnostic that discards, truncates or blurs the evidence needed to act on the
failure it is reporting.* It is the sibling of the silent-success class (print `[FAIL]`, then
`exit 0`): there the **verdict** lies; here the verdict is correct and the **evidence** is destroyed.

| # | Where | What it destroyed | Cost |
|---|---|---|---|
| 1 | `tests/full-project-test-suite.sh`, 177 delegates (**BL-184**, Closed) | child stdout AND stderr, at the moment of capture | BL-135 sat open 2026-07-18 → 2026-07-26 across two ~3h full-lane runs with zero root-cause progress |
| 2 | `tests/test-bl132-sast-index-scan.sh`, 3 cases (**BL-193**) | the hook's SAST section — captured to `$TOPTMP/<log>`, then reported via `tail -8`, which lands on an unrelated `[WARN] no test command configured` block | one CI round-trip; the section was in the file the whole time |
| 3 | the emitted hook's coverage reporter (**BL-193**, `# BL-193-COUNT`) | the header COUNT — `"absent or unreadable"` collapsed `0` and `2+`, which need different operator actions | one CI round-trip, and it shipped to every generated project |

**Instances 2 and 3 compounded; instance 1 did not — and an earlier draft of this entry got that
wrong, which is recorded because a lessons-learned entry with a wrong causal chain teaches the wrong
lesson.** The draft claimed a three-layer stack with the BL-184 aggregator as layer 1. Refuted twice
over: the `sast` shard that carried BL-193 runs its tests DIRECTLY from `tests.yml` (the 177-delegate
aggregator appears only in the `full` lane's `core` shard), and BL-184's fix merged 2026-07-27 — a day
BEFORE BL-193 was first observed. BL-184 is a real member of this class with its own measured cost
(BL-135's eight days); it simply was not in BL-193's path. What DID compound was two layers:
`tail -8` printed past the SAST section the case had already captured, and the reporter beneath it
collapsed "saw 0" and "saw 2+" into "absent or unreadable". BL-193's root cause (semgrep's status
banner arrives on a different stream on the runner) was **present in the captured log from the first
failing run — and never surfaced to the transcript**: the findings dump does print `$soif_sg_out`
unconditionally, but the hook's whole stdout was itself captured to `$TOPTMP/<log>`, of which only a
tail was shown. Two rounds of instrumentation had to land before the log's own words reached anyone.

**The tell, and it is checkable at review time.** In all three the information was *present* and
discarded at the last step — not unavailable. Each was a formatting choice: a `>/dev/null 2>&1`, a
`tail -N`, an `echo` naming a symptom rather than a number. So the review question is narrow:

> **When this arm fires, does its output contain what the reader needs to act — and was the underlying
> evidence available at that point?** If the second answer is yes and the first is no, it is this class.

**Candidate lint, in the spirit of `lint-fix-functions-stderr.sh`.** Flag `tail -[0-9]` / `head -[0-9]`
inside a failure-reporting expansion (`fail_ "…" "$(… tail -N …)"`), and `>/dev/null 2>&1` on a command
whose status feeds a failure message. Both are heuristics with real false positives, so it should
**render its hits for review** — the `--list` pattern `lint-tests-registered.sh` already uses — rather
than block outright. A blocking lint here would be its own cry-wolf.

**Prior art in this repo, and the accurate gap — a SCOPE claim, not a universal.** An earlier draft
said "nothing covers the evidence half"; false, and disproved by the very lint this entry nominates
as its model: `scripts/lint-fix-functions-stderr.sh` exists precisely because a `2>/dev/null` inside
a `fix_*` function left an operator with "fix returned non-zero" and NO diagnostic — that IS the
evidence half. The true gap is its scope: it covers `fix_*` functions on the operator-facing surface,
while all three instances above lived where it does not look — a test aggregator's delegates, a test
case's failure message, and a heredoc-emitted hook body. (`lint-fail-emit-exit-status.sh` covers the
sibling *verdict* half.) The three instances were each caught by a human reading a transcript and
asking why it said so little — which does not scale and did not, in fact, happen quickly.

**Related:** BL-184 (instance 1, Closed), BL-193 (instances 2 and 3), BL-196 (the sibling
citation-integrity gap filed the same day), `scripts/lint-fail-emit-exit-status.sh`, and the
silent-success class recorded in the `adversarial-verify-patterns` memory note.

---

## BL-198: Implementation plan v2 — TRANSCODE undecodable-but-textual staged files and scan the converted bytes; reject only as the fallback

**Logged:** 2026-07-29 (plan requested by Karl; diagnosis is BL-192 and is settled — do NOT re-derive it)
**Revised:** 2026-07-29, same day — **v1 was refuted in adversarial review and its shape was wrong.**
v1 proposed detect-and-refuse (BOM/NUL ⇒ forfeit the receipt) and claimed the byte precheck was "the
only candidate that survives." Two blocking findings, both reproduced independently before this
rewrite: **(R-1)** v1's own Definition of Done required granting the `[OK]` receipt over an unscanned
sink — an ordinary pure-ASCII `.ts` carrying `p.innerHTML = window.name` PLUS a token-stream break is
missed by semgrep deterministically (control `rc=1, Findings: 1`; broken `rc=0, Findings: 0`; 5/5)
while the BOM/NUL predicate reads it as clean text; **(R-2)** "only candidate" was false — transcoding
was never considered, and it is measurably better. Kept in the header because a plan that ships its
own refutation is the BL-192 pattern one level up, and the next reader should know this plan already
paid for that lesson.
**Category:** Enforcement / commit-time SAST — coverage attestation
**Severity:** High, inherited from BL-192: the outcome it prevents is a **positive false attestation**
(`[OK] semgrep: SAST ran on N staged file(s) — no ERROR-severity findings.` printed over a file the
parser never decoded).
**Status:** Closed — implemented 2026-07-30 in `02eaa0f` (WP0–WP4 complete; marker `# BL-198-TRANSCODE`
in `scripts/lib/hook-templates.sh`, reporter `# BL-198-UNTX-REPORT`, extension tripwire `# BL-198-EXT-SET`).

**Closure record.** The decision tree shipped as planned: NUL scan → BOM longest-first →
whole-body stride-aware zero-parity derivation with the claim/derivation agree-check →
transcode-to-UTF-8 at the IDENTICAL tree path (temp + `mv`, after F2) → fail-closed named
NOTRUN for everything unvouchable. The receipt attests the conversion count. **One deviation
from this plan's text, recorded in the fence comment:** no `numstat` first pass — its binary
heuristic reads only the first 8000 bytes, so a late-first-NUL UTF-16 file would be exempted
as "text" and slip the classifier; the whole-file NUL count has no window. Strictly stronger,
same tree. **No parity ratio exists** (the rule shipped as all-zeros-on-one-parity, exact),
so the plan's "numeric boundary" proof obligation attaches to the BOM match ORDER instead —
`T-mutation-parse-threshold` proves shortest-first degrades the UTF-32 row to a SAFE cry-wolf,
never a receipt. DoD walked: UTF-16LE±BOM/BE±BOM/UTF-32LE+BOM sinks all transcode and BLOCK;
well-formed, empty, UTF-8-BOM, Latin-1 and binary commits keep their receipts untouched;
iconv failure (unpaired surrogate) forfeits loudly naming the file; no clause added by this
work reads anything semgrep printed; the token-break residue is deferred to BL-200 and named
in the receipt's own documentation. WP3's five withdrawn cases are restored re-aimed
(`T-utf16-parse-drop-no-receipt` flips to sink-BLOCKED, `T-parse-coverage-fails-closed` to
iconv failure, `T-parse-threshold-exact` to BOM order, plus both mutation proofs) — the
condition #278 was held open for. Suite 53/0 with the 8 sink rows watched RED first (every
one printed the `[OK]` receipt over the unseen sink pre-fix); six sibling emitted-hook
suites green; 11/11 lints.

**Adversarial review round (fable), verdict `block` → fixed in `a54df64` — and every finding was real.**
(1) **R-BL198-1, the blocker:** a UTF-32LE BOM prefixed to a UTF-16LE sink body defeated all
three vouching surfaces — the 4-byte shift puts a zero on every position ≡3 (mod 4) so the
stride-4 derivation AGREED with the lie, and macOS libiconv converts the out-of-range code
points to NUL-free output — reproduced end-to-end by the reviewer with the `[OK]` receipt
printed and the sink in HEAD: the BL-192 false attestation reborn through the fix itself.
Closed by the **U+10FFFF range bound** in the derivation (genuine UTF-32 has byte@2 ≤ 0x10
per LE group, byte@1 for BE — exact for BMP and astral; the reviewer validated the bound
against genuine/astral/liar shapes in both endiannesses). Watched RED then GREEN
(`T-u32bom-over-u16-body-notrun`). (2) **R-BL198-2:** the plan's WP0.3 claim *"real UTF-16
source always has a whole-file signal"* is **REFUTED, recorded here rather than silently
edited**: one code unit with a 0x00 LOW byte (U+0100, U+3000, an astral char with a zero
surrogate byte) puts a zero on the wrong parity and collapses the exact rule — a clean CJK
file with one ideographic space is a permanent loud NOTRUN. Kept exact ANYWAY, as a **third
named residue** (`T-u16-wrongparity-residue` pins it): a dominance ratio would let a crafted
no-BOM file steer the derivation to the wrong endianness, whose transcode is NUL-free
valid-UTF-8 garbage and a receipt over an unscanned sink — the strictly worse failure. The
residue fails LOUD and names the file; the remedy it prints (save as UTF-8) is real.
(3) **R-BL198-3:** the output UTF-8 revalidation is inert on macOS (libiconv accepts 5-byte
sequences) — added the byte-level floor (any 0xF5-0xFF byte in the output ⇒ failed
transcode; RFC 3629 exact). (4) **R-BL198-4, deviation #2 recorded:** `T-ext-set-pinned`
pins the extension set against the BL-125 source list — a PROXY for "the shipped rulesets",
not the rulesets themselves; deriving language→extension from the ruleset YAMLs is the
honest future tightening. (5) **R-BL198-5:** `.cxx/.hh/.hxx/.m/.mm` added to
`# BL-198-EXT-SET`. Reviewer note recorded, pre-existing: semgrep's
`--exclude-binary-files` defaults ON and the hook passes neither spelling — a dropped
binary target is caught by the selection guard, so not a hole; noted so it is not
rediscovered. A third targeted round found **R-BL198-6**: the R-BL198-3 floor itself was the BL-183 SIGPIPE
class re-introduced (awk early-exit under pipefail — detection ERASED on outputs past ~8KB;
no live path reaches it after the range bound, which is exactly why the defense-in-depth
surface must work). Fixed to a full-input consumer + pinned both-spellings
(`T-utf8-floor-no-sigpipe`), watched RED→GREEN. Final: suite 56/0; residues THREE, all named: BL-200 (token break), the
zero-ASCII single-line passthrough, and the wrong-parity loud NOTRUN.

**Read first, and do not repeat this work:** BL-192 (the measured diagnosis, the two-version table,
the two DECISION blocks), the `# BL-112-SCAN-COVERAGE` block in `scripts/lib/hook-templates.sh` —
including its `THE RESIDUE, NAMED` paragraph, which already lists the token-stream-break case this
plan explicitly does NOT cover (that is **BL-200**) — and BL-201 (the template float this plan
unblocks).

### Why transcode beats reject — measured, not argued

Same fixture (`p.innerHTML = window.name` saved as UTF-16LE, no BOM), the hook's exact flag set:

| approach | result | operator experience |
|---|---|---|
| v1: detect & refuse | receipt forfeited, sink UNSCANNED | permanent NOTRUN — every commit from that editor cries wolf, forever |
| **v2: `iconv -f UTF-16LE -t UTF-8`, scan the copy** | **`rc=1` — the sink BLOCKS the commit** | nothing to explain; the gate simply works |

Transcoding satisfies every criterion the BL-192 decision blocks set: it is a byte operation the hook
performs on bytes it already holds (the temp tree of `# BL-132-INDEX-SCAN` materializes every staged
blob before semgrep runs), it has no semgrep version to drift, and its failure mode is fail-closed.
**Ordering constraint the implementer must not miss (review R2-4):** the materialized slot is guarded
by the F2 byte-size check (dest must equal `git cat-file -s` of the staged blob), and UTF-16→UTF-8
roughly halves the byte count — a transcode that overwrote the slot BEFORE F2 would fail F2 on every
converted file and forfeit every receipt, the exact cry-wolf this plan exists to avoid. Transcode
AFTER F2 has validated the raw copy, writing the converted bytes to the **IDENTICAL path** —
`$soif_idx_tree/<n>/<relpath>`, same directory, same basename, same extension. F2 has already passed,
so the size change is harmless. UTF-16→UTF-8 maps newlines 1:1, so finding
line numbers stay true and `# BL-178-PER-INDEX-DIR`'s path mapping is untouched.

### Work packages

- **WP0 — the classifier, stated as ONE decision tree so no branch is left to interpretation.**
  Round-2 review refuted this WP's first draft twice — a head-window sniff and a fail-open
  no-signal branch, both defeated with built fixtures — so the tree is now exhaustive:
  1. **NUL-free file → passthrough.** Plain UTF-8, Latin-1/CP1252, empty — the family semgrep
     already parses (Latin-1 measured in review: the sink IS detected). Nothing to do.
     **NUL-free ≠ decodable, and this branch's residue is named rather than papered over
     (review R3-2):** UTF-16 text whose every code unit has two non-zero bytes (pure CJK, Greek,
     Cyrillic, emoji) is NUL-free AND undecodable, and passes through to a clean scan and a
     receipt. Tightening this to "NUL-free AND valid UTF-8" is the obvious fix and is WRONG —
     Latin-1 source is also NUL-free and also invalid UTF-8, and it must pass through (measured:
     sink caught). So the residue stands, bounded: a single ASCII byte — any newline — puts a NUL
     in the file and hands it to WP0.3, in BOTH endiannesses, and one newline in 642 bytes still
     resolves parity unambiguously (WP0.3's rule is all-zeros-on-one-parity, not a ratio). A
     zero-ASCII single-line source file is the whole exposure. **The obvious widener was attacked
     and failed:** legacy multibyte source still live in real codebases — Shift-JIS, EUC-JP,
     GB18030, Big5, all NUL-free and all invalid UTF-8 — is handled correctly by semgrep, sink
     caught in every one (measured). Passthrough is right for them, which is also why WP0.1 must
     not be tightened.
  2. **NULs + BOM → the BOM is a CLAIM, not knowledge.** Check the four BOMs **longest first**
     (`FF FE 00 00` / `00 00 FE FF` before `FF FE` / `FE FF`): `FF FE` is a PREFIX of the UTF-32LE
     BOM, and WP1 must name an encoding to pick `iconv -f`, so order is load-bearing. (An earlier
     draft said order "must not matter" while simultaneously requiring the encoding to be named
     off the match — that contradiction is deleted, this sentence replaces it.) Then DERIVE the
     endianness from the zero positions of the WHOLE body and require BOM and derivation to
     AGREE; disagreement ⇒ unvouchable ⇒ WP2 loud. **The derivation is STRIDE-AWARE — 2-byte
     parity against a UTF-16 BOM, 4-byte against a UTF-32 BOM.** A UTF-32 file carries zeros on
     both 2-byte parities, so a literal 2-byte reading calls an honest UTF-32LE file "ambiguous"
     and cries wolf on it (measured in review: WP2 loud under 2-byte, transcoded-and-caught under
     4-byte). Fails safe, but it contradicts the matrix row below, so the stride is stated here. A lying BOM (`FF FE` over a UTF-16BE body)
     otherwise transcodes to NUL-free, valid-UTF-8 garbage that passes every output check and
     mints a receipt over a live sink — built and reproduced in review, BOTH directions; the
     agree-check catches both liars and passes the honest file.
  3. **NULs + no BOM + parity signal over the WHOLE FILE → transcode with the derived endianness.**
     Whole file, never a head window: a UTF-16 file opening with a CJK comment block has ZERO
     zero-bytes in its head (CJK code units use both bytes), so a head-window sniff reads "no
     signal" and waves an intact sink through — built in review. Whole-file parity reads the same
     file unambiguously (every zero on one parity) and the sink is caught. Real source always
     carries ASCII syntax characters, so real UTF-16 source always has a whole-file signal.
  4. **NULs + no BOM + NO whole-file signal — the branch where fail-open hid.** The first draft
     said "passthrough, today's behaviour" — and "today" IS the BL-192 false attestation, so the
     one branch where the classifier admits ignorance was the one branch that quietly vouched.
     Rule: if the file's extension is in the source set the shipped rulesets target, route to
     **WP2 loud** (near-unreachable for honest files, per 3 — real source has ASCII, hence a
     signal). Otherwise — PNG, archives, genuine binaries — passthrough untouched, receipt
     unaffected, exactly as today, which for real binaries is correct. **This set's drift fails
     OPEN** (an extension not yet listed passes through rather than going loud), so pin it against
     the shipped rulesets in a test. It is NOT v1's allowlist problem returning: v1's gated the
     ENTIRE check, so drift left a whole language unprotected; this one gates only the
     NUL+no-BOM+no-signal branch, and what actually reaches it with a source extension is binary
     content in source clothing — BL-192's own `40KB binary blob staged as vendor.js` residue item,
     which this branch newly CATCHES.
  `git diff --cached --numstat` is demoted to a FIRST-PASS filter only: it cleanly exempts
  plain-text files from the tree above, but it lumps UTF-16 TEXT in with real binaries (measured in
  review — all three UTF-16 fixtures and the PNG alike read as binary), so it cannot be the
  classifier this WP once hoped it might be.
- **WP1 — transcode, with the encoding VOUCHED on all three surfaces.** BOM → encoding CLAIMED,
  confirmed against the whole-body derivation (WP0.2); no-BOM → derived outright (WP0.3). Transcode
  AFTER F2 per the ordering constraint above, REPLACING the raw copy at the IDENTICAL path —
  **via a temp file and `mv`, NEVER by redirecting into the file being read.** `iconv … > "$dest"`
  truncates `$dest` before iconv opens it, so iconv converts an EMPTY file, returns **rc=0**, and the
  raw bytes are gone: measured 140 bytes → 0, output NUL-free and valid UTF-8, so all three vouching
  surfaces pass and a clean scan mints the receipt over a destroyed sink. It fails on the happy path
  too — 100% of transcodes yield 0 bytes — so WP3's `sink CAUGHT` cases go RED on the implementer's
  first run and it cannot ship; that is why this is a footgun and not a hole. Convert to a temp file,
  validate it, then `mv` it over the destination. `iconv`'s exit code carries the partial-conversion
  cases correctly (odd-length and lone-surrogate fixtures both return rc=1 → WP2 loud, raw bytes
  intact).
  **NOT a "sibling" path — that word was in an earlier draft and review R3-1 measured it breaking two
  contracts at once.** semgrep picks a target's language from its EXTENSION, so the two natural
  sibling spellings both scan clean and mint the receipt (`app.ts.utf8` → `rc=0`, extensionless →
  `rc=0`, versus `rc=1 findings=1` at the original name) — a fresh false-receipt path created by the
  fix itself. And `# BL-178-PER-INDEX-DIR`'s operator-facing mapping,
  `sed "s#${soif_idx_tree}/[0-9][0-9]*/##g"`, only strips the prefix for the unchanged path: a
  suffixed sibling reports a repo path that does not exist, a parallel-root sibling shows the operator
  a raw temp path — exactly what BL-178 was filed to end. The two constraints intersect at one shape:
  the identical path. If the raw bytes must be retained, stash them at `$soif_idx_tree/raw/<n>/<relpath>` — INSIDE the
  tree, under a reserved non-numeric segment. **Not outside it (review R4-2):** the SAST arm's only
  cleanup is `rm -rf "$soif_idx_tree"` with no `trap`/EXIT handler, so anything stashed outside leaks
  a temp file on every commit, forever. Inside is invisible to the scan (semgrep only ever receives
  the explicit `${soif_idx_files[@]}` targets), invisible to BL-178's sed (`[0-9][0-9]*` cannot match
  `raw`), and cleaned for free. Simplest of all: do not retain them — nothing after F2 needs them. The receipt names it: `N staged file(s) transcoded from UTF-16 for scanning`.
  UTF-32: attempt via BOM only, longest-first per WP0.2; anything else falls to WP2.
  **THE WRONG-ENDIAN TRAP — round-2 review proved the first draft claimed "closed by construction"
  on ONE surface when the principle has to hold on THREE.** A wrong-endian transcode yields garbage
  that can be NUL-free AND valid UTF-8 — semgrep scans it "clean" and the false receipt this plan
  exists to kill comes back through the fix itself. The fail-closed principle binds at every
  surface: (1) a BOM's claim must AGREE with the whole-body zero-position derivation; (2) a no-BOM
  file is transcoded only with a DERIVED endianness — never guessed, never try-both; (3) output
  containing a NUL or failing UTF-8 validation is a failed transcode. Disagreement or ambiguity at
  ANY surface ⇒ WP2 loud. **A transcode this plan cannot vouch for is treated as a transcode that
  failed — at all three places that sentence has to hold, not one.**
- **WP2 — the fail-closed fallback.** `iconv` absent, `iconv` non-zero, or output not valid UTF-8 →
  v1's behaviour becomes the FALLBACK: forfeit the receipt, route to the existing
  `soif_sast_not_enforced` / `soif_sast_partial_coverage` vocabulary, NAME the file
  (`# BL-182-NAME-THE-ENTRY`). No new reporter. Never silent.
- **WP3 — restore the five withdrawn cases from `e87dbd3` (PR #278), re-aimed and STRONGER.**
  `T-utf16-parse-drop-no-receipt`, `T-mutation-parse-coverage`, `T-parse-coverage-fails-closed`,
  `T-parse-threshold-exact`, `T-mutation-parse-threshold` are correct code against a broken
  instrument; restore their SHAPE with the predicate re-aimed off `Parsed lines` onto WP0/WP1 — and
  the UTF-16 cases flip expectation from "receipt forfeited" to **"sink CAUGHT and commit BLOCKED"**,
  which is the stronger DoD transcoding buys. The last two are owed back specifically: they exist
  because a `-ge 100` threshold was left unpinned once and a reviewer's `-ge 100` → `-ge 99` mutant
  survived the entire PR-blocking set. Any numeric boundary WP0/WP1 introduces (the parity
  ratio threshold) owes an equivalent exact-value mutation proof. **Not the head-window size — WP0.3
  abolished the head window; an earlier draft required a proof of its size two work packages after
  deleting the concept, which is how a deleted idea gets re-implemented.**
- **WP4 — anti-cry-wolf regression.** `T-coverage-no-cry-wolf` and `T-empty-target-receipt` stay
  green throughout; add the binary-commit case.

### The fixture matrix — every row labelled, none left to interpretation

| fixture | expected |
|---|---|
| UTF-16LE **with** BOM, carrying the sink (BL-192's) | transcoded; **sink caught, commit BLOCKED** |
| UTF-16LE **no** BOM, carrying the sink (the trap: decodes as VALID UTF-8) | transcoded via parity heuristic; **caught, BLOCKED** |
| UTF-16BE **with** BOM | transcoded; caught |
| UTF-16BE **no** BOM | transcoded via parity; caught |
| UTF-8 **with** BOM (legal, common from Windows editors) | passed through untouched; scanned normally |
| plain UTF-8 control with the sink | untouched; caught (the baseline) |
| empty file | untouched; receipt still earned (`T-empty-target-receipt` pins this) |
| PNG / binary | untouched, no transcode attempt; receipt unaffected |
| Latin-1/CP1252 source (invalid UTF-8, no NUL, no BOM) | untouched; semgrep handles it — measured in review, the sink IS detected |
| **lying BOM**: `FF FE` (claims LE) over a UTF-16BE body carrying the sink — and the mirror image | BOM/derivation DISAGREE → unvouchable → WP2 loud NOTRUN naming the file (review-built; without the agree-check both directions minted a receipt over garbage) |
| UTF-16LE, no BOM, opening with a CJK comment block, sink intact after it | whole-file parity → transcoded → **caught, BLOCKED** (a head-window sniff read "no signal" and waved it through — refuted in review) |
| UTF-32LE with BOM (`FF FE 00 00`), sink | longest-BOM-first → UTF-32LE → transcoded → caught (measured rc=1). Shortest-first misreads it as UTF-16LE and degrades SAFELY (output keeps NULs → WP2) but cries wolf on a legitimate file — hence WP0.2's ordering rule |
| pure-CJK UTF-16 no-BOM, source extension, **no ASCII at all** | **PASSTHROUGH — residue, NOT closed by this plan.** No ASCII ⇒ no NUL ⇒ WP0.1 fires first and WP0.4 is never reached; semgrep cannot decode it and scans it clean, so the receipt is granted. An earlier draft of this row claimed WP2 loud, which the tree does not produce (review R3-2). Near-unreachable: any single ASCII character — **including a newline** — introduces a NUL and routes the file to WP0.3, where it is caught |

### Explicitly out of scope → BL-200, and saying so is the point

**Two residues, both named — a plan that hides one is the v1 failure.** (i) The zero-ASCII UTF-16
case above (WP0.1, review R3-2): NUL-free, undecodable, passes through. Bounded to single-line
zero-ASCII files; not closed here because the only tightening that would close it breaks Latin-1
passthrough. (ii) The token-stream break, which is the larger one:

**The token-stream-break case is covered by NO byte-level candidate, this plan's included.** A
pure-ASCII source file with a syntax break beside the sink passes every byte test here and semgrep
misses the sink deterministically. v1 hid that residue and its DoD blessed it; v2 names it and hands
it to **BL-200** (the `--verbose` detector behind a framework-side canary). Until BL-200 lands, the
receipt's honest reading is unchanged from `# BL-112-SCAN-COVERAGE`'s residue note: presence of a
finding is a fact; absence is evidence only for files semgrep can actually parse.

### Rejected approaches, with the measurement, so they are not re-proposed

- **`--json`** — affirmatively reports the undecoded file as scanned, with no skip recorded
  (`skipped: []` on 1.171.0; the key entirely absent on 1.157.0 — spelling is version-dependent,
  the lie is not). Strictly worse than the banner.
- **`--verbose` as the PRIMARY gate** — report-dependent, which both DECISION blocks on BL-192 now
  rule out for correctness-bearing gates. Survives only as BL-200's best-effort detector with a
  canary. (Do NOT anchor on `Partially analyzed due to parsing or internal Semgrep errors` — it is a
  section header printed on EVERY verbose scan; the discriminator is the `[WARN] Syntax error at
  line <target>:` line, count 1 vs 0.)
- **`--x-ls-long`** — right shape, experimental by upstream's own `x-` marker; a permanent-NOTRUN
  cliff waiting for a release.
- **A canary FILE staged alongside targets** — tested and refuted for this class: generic-regex
  fires 186 matches on the undetected file; an appended ASCII marker is found on all six UTF-16
  fixtures while the body vulnerability is missed.
- **Pinning semgrep** — Karl's two decisions on BL-192: this repo's CI stays unpinned; the 22
  template pins float AFTER this plan lands (BL-201).

### Definition of done

A UTF-16LE staged file carrying `pane.innerHTML = userText` — with and without a BOM — is
**transcoded and its sink BLOCKS the commit** on whatever semgrep the host has. An ordinary
**well-formed** source commit, an empty placeholder, a UTF-8-BOM file, a Latin-1 file and a
binary-touching commit all still earn the receipt untouched. `iconv` failure forfeits the receipt
loudly, naming the file. Every numeric boundary carries an exact-value mutation proof. No clause
added by this work reads anything semgrep printed. The token-break residue is explicitly deferred to
BL-200 and named in the receipt's documentation — this plan's DoD cannot be satisfied by blessing it.

**Related:** BL-192 (diagnosis + both decisions), BL-200 (the residue this plan refuses to claim),
BL-201 (the template float this plan unblocks), BL-112 (the silent-success class), BL-187 (the
sibling fail-open clause), BL-182 (`# BL-182-NAME-THE-ENTRY`), BL-183 (no `grep -q` into a pipe),
PR #278 / `e87dbd3` (holds the five withdrawn cases; STAYS OPEN until WP3 lands — Karl, 2026-07-29,
recorded on the PR).

---

## BL-199: The README's own Quick Start could not be executed — `guard_not_in_framework`'s unconditional cwd check refused `./init.sh` from inside the clone, and no test ever ran the documented sequence

**Logged:** 2026-07-29
**Category:** Product defect / docs-vs-code contradiction / coverage hole
**Severity:** High — this is the FIRST command a new user runs. The documented onboarding path
exited 1 before any prompt.
**Status:** Open — DEFERRED. **Delivered by PR #284** (`fix/bl199-quickstart-from-clone`) — the
quick-start contract, the target-based guard, the sibling resolver, the README, the audit-record and
user-guide corrections, and the 19-case suite with seven mutation proofs all shipped there.

**It is DEFERRED rather than Closed for one named residual: `--dry-run` does not refuse a target it
will refuse for real.** `--validate-only` refuses (rc=1); `--dry-run` returns rc=0 and prints
"Re-run without --dry-run to execute" — so the preview tells the operator to run a command that will
then be refused. Harmless (no writes occur) and pre-existing, but not closed here **deliberately**:
fixing the flag half alone would leave the README's own tip — bare `./init.sh --dry-run` — still
wrong, because that is the INTERACTIVE path, where no target exists at the early-guard block and the
guard would have to move into `dry_run_summary`. A half-fix would read as closed while the documented
example stayed broken, and would add a new inconsistency between the two dry-run shapes.

**Why DEFERRED and not a fresh entry.** CLAUDE.md's canonical what's-open recipe
(`grep -n '\*\*Status:\*\* Open'`) returns the DEFERRED variants, so the residual stays visible with
no new machinery; minting a number would gamble on numbering contention that does NOT resolve at
merge (other unmerged branches are not visible from here, and a collision would land exactly when
someone is merging); and a stub entry would lose the reasoning above, which is the only thing that
makes the residual intelligible. BL-181 is the precedent — substantially delivered, one named
residual, stays Open.

**Audit-trail note:** because this entry is not Closed, `lint-backlog-references.sh` does not require
a PR citation — so PR #284 is cited in this prose deliberately. A future closer should keep it.

**The defect.** README § Quick Start said: `git clone` → `cd solo-orchestrator` → `chmod +x init.sh`
→ `./init.sh`. init.sh's early block called `guard_not_in_framework "$_early_target"`, whose FIRST
arm is an **unconditional cwd check** — `_gnif_dir_is_framework "$(pwd)"` — so from inside the clone
init.sh refused before reaching a single prompt. Measured on `08315c0` from the clone root with
`--project-dir` pointing at a benign external tempdir: **rc=1**, `[FAIL] Refusing to operate inside
the Solo Orchestrator framework repo. Detected framework signature (cwd): …`. Supplying an explicit
external target did **not** help: the cwd arm runs first and does not care what the target is. The
only invocation that worked from the clone was `--dry-run`, which skips both checks by design.

The advice the refusal printed made it worse: *"Move to your project directory and re-run: cd
/path/to/your-project"*. For a first-time user there is no project directory yet — creating it is
what they were trying to do.

**The coverage hole — and why it stayed open.** No test ever executed the README's literal sequence.
`tests/edge-cases-pre-init.sh` E8b hit this exact wall: the harness runs init.sh from inside the
framework checkout, the cwd arm fired first, and the read-only-target assertion was unreachable, so
E8b was SKIPped. BL-041's fix reordered `preflight_target_writable` to run BEFORE
`guard_not_in_framework` — which got the **TEST** past the wall without anyone asking why the
**USER** was behind it. The init.sh comment block records the reasoning verbatim: *"The previous
ordering also blocked tests/edge-cases-pre-init.sh E8b … Reordering the two closes that test gap
without weakening either guard."* True as written, and the user-facing contradiction survived it
untouched. Lesson for the class: **when a guard blocks a test, ask whether it also blocks the
documented user path before you route around it.**

**The decided contract (Karl, 2026-07-29).** Quoted:

> 1. Running init.sh FROM INSIDE the clone is the SUPPORTED flow.
> 2. The script must still FAIL when the operation would write ONTO the framework itself: target ==
>    framework root, target INSIDE the framework tree, or target is another framework clone
>    (signature match).
> 3. `./init.sh --project-dir <bare-name>` creates the project ONE LEVEL UP from the framework
>    clone: `/x/solo-orchestrator/init.sh --project-dir testproject` → `/x/testproject/`. Anchor is
>    the PARENT OF THE DIRECTORY CONTAINING init.sh (SCRIPT_DIR/..), NOT the cwd.
> 4. README Quick Start documents `./init.sh --project-dir <project-folder-name>` as the activation.

**The fix.** Two new functions in `scripts/lib/helpers-core.sh`:
- `# BL-199-SIBLING-RESOLVE` — `soif_resolve_target_dir <raw> <anchor_parent>`. Empty → empty;
  **absolute → unchanged** (the back-compat hinge, and what makes the resolver idempotent so all
  three init.sh call sites can apply it); relative → joined to the anchor, then lexically normalized
  (`.` dropped, `seg/..` collapsed) in a bash-3.2-safe loop with no `realpath` dependency.
- `# BL-199-TARGET-GUARD` — `guard_target_not_in_framework <abs_target> <framework_root>`. Three
  arms: target is a framework clone by signature (the security-audits-1 S3 vector, preserved);
  target IS the framework root; target is INSIDE the framework tree. The third arm is **new** — the
  old cwd check never saw subdirectory targets — and both the root and inside arms compare PHYSICAL
  and as-given forms so a symlinked temp root cannot slip past on a spelling difference. The refusal
  text deliberately does **not** reuse the old guidance: it tells the operator that running from the
  clone is fine and offers the two legitimate target shapes.

In `init.sh`: `# BL-199-SIBLING-ANCHOR` (`soif_sibling_anchor`, the `SCRIPT_DIR/..` anchor) plus
three resolve sites — the early block (fast-fail UX, BL-041's preflight-first ordering **preserved**
and still pinned by E8b and `test-init-write-perm-preflight` T1), the non-interactive existence
check (so "already exists" tests the real target, and so a config-file `project_dir` is covered),
and `create_project()`, which resolves + guards immediately before `mkdir` and is commented as **the
authoritative gate** because the interactive and config-file paths only converge there.

**Blast radius, deliberately bounded.** `guard_not_in_framework` is **unchanged** and still cwd-first
for every other caller — **six scripts, eight call sites**, measured 2026-07-29 with
`grep -rn guard_not_in_framework --include='*.sh' scripts/`: `verify-install.sh`,
`reconfigure-project.sh`, `upgrade-project.sh` (×3), `pending-approval.sh`, `process-checklist.sh`,
`intake-wizard.sh`. (The dispatch brief for this change said "seven other callers"; the measured
figure is six scripts / eight sites, and `pending-approval.sh` additionally defines a same-named
no-op fallback, which is a definition and not a call.) Those genuinely operate ON the cwd project
and must keep refusing inside the framework. Only init.sh's call site flipped. The one
structural edit to the old function is behaviour-neutral: its inner `_gnif_dir_is_framework` now
delegates to a hoisted top-level `_soif_dir_is_framework`, because bash only publishes a nested
definition after the enclosing function has run and the new guard needed the same signature probe.

**The contract flip in the test suite.** `tests/test-init-write-perm-preflight.sh` **T2** asserted
that framework-cwd + a WRITABLE EXTERNAL target was refused ("defense-in-depth preserved"). Under
the new contract that invocation is the supported flow and succeeds — keeping the assertion would
have pinned the defect. T2 is rewritten to pin the defense-in-depth that survives: framework-cwd +
a preflight-PASSING target INSIDE the framework → refusal, with nothing created. T1 (the ordering
pin) and T3 survive unchanged; their exact-banner greps were widened to the shared `Refusing to
operate` opener so they catch either guard's message.

**New coverage.** `tests/test-bl199-quickstart-from-clone.sh` builds its own framework clone in a
tempdir and runs the README's literal sequence: T1 README-literal → sibling scaffold; T2 anchor is
`SCRIPT_DIR/..` not the cwd (run from a THIRD directory, so the two anchors actually differ — the
brief's original shape had cwd == `SCRIPT_DIR/..` and could not have detected M1); T3 inside-target
refused before any `mkdir`; T4 target-is-this-clone's-root refused (green pre-fix, back-compat pin —
and see below, it isolates no single arm); T5 absolute external target from the clone cwd; T6 the
clone's file list is byte-identical before and after T1. Mutation proofs **M1** (anchor := cwd → T2
red) and **M2** (drop the inside-framework arm → T3 red; the mutant scaffolded a whole project INTO
the clone). Pre-fix baseline for the record: T1/T2/T3/T5 red, T4/T6 green. Registered in
`tests/full-project-test-suite.sh` only — it invokes init.sh, so the tests.yml unit-lane exemption
is legitimate (`lint-tests-registered.sh --list` renders it as `unit-lane-exempt:init-sh-invoker`).

**Adversarial review round (2026-07-29, against `fe2d045`) — two blockers, both real.**

*R-199-1, the security blocker.* macOS APFS is case-INSENSITIVE by default and `pwd -P` resolves
symlinks but does NOT canonicalize case, so two spellings stay distinct STRINGS naming one
directory and the byte-wise prefix match in `_bl199_path_is_inside` missed them. Measured
end-to-end on `cabd709`: `--project-dir "$TMP/CLONE/injected"` against a clone at `$TMP/clone`
exited **rc=0 with no refusal and scaffolded 602 files INSIDE the framework**. The root itself was
refused only incidentally, via arm (a)'s `[ -f "$d/init.sh" ]` following the case-insensitive
lookup; subdirectories had no backstop at all. **Fix:** device+inode identity (`_bl199_dir_id`,
GNU-first `stat -c '%d:%i' || stat -f '%d:%i'`, after a `cd … && pwd -P` because `stat` does not
dereference a symlink argument on either platform), applied to both the is-root and the
ancestor-walk checks. Identity is spelling-agnostic by construction and covers symlinks, hardlinked
directories and bind mounts in one predicate. Explicitly **not** a `tr '[:upper:]' '[:lower:]'`
comparison: on a genuinely case-SENSITIVE filesystem `/x/FOO` and `/x/foo` are different
directories and case-folding would false-REFUSE a legitimate target — correct on neither kind of
filesystem, where identity is correct on both. The string comparisons are kept as a cheap first
pass.

*R-199-2, the coverage blocker.* T4's shape (`target == framework root`) is satisfied redundantly by
arms (a) and (b), so it could not detect the loss of either — the reviewer's mutants MX4 (signature
arm off) and MX5 (is-root arm off) both **survived 8/8**. Worse, init.sh's coverage of the
security-audits-1 **S3 vector was zero**: the only test of that vector,
`test-platform-security-bugs-closer.sh::T3a`, exercises the OLD `guard_not_in_framework`, which
init.sh no longer calls. Added the isolating shapes: **T8** = S3v, `--project-dir` at a SECOND,
different framework clone from a benign cwd (only arm (a) can see it); **T7** = target IS the
framework root against a fixture whose `templates/generated` is absent, which blinds arm (a), while
arm (c) starts at the target's PARENT and so never matches the target itself (only arm (b) can see
it). Both targets EXIST, so both tests assert on text unique to the guard rather than on `rc!=0`,
which the existence check would also produce. Mutation proofs **M3** (= MX4) and **M6** (= MX5) run
both in-suite and now die. Also added **T9** case-variant, **T10** symlinked target, **T11** a
prefix-sibling (`clone-2`) that must still be ALLOWED so the fix cannot over-refuse, plus **M4**
(identity comparison off → T9 red) and **M5** (both `pwd -P` resolutions off → T10 red, closing
R-199-7's unpinned physicalization).

**Stated, not papered over — and CORRECTED in round 2.** Round 1 claimed that *every* string
comparison in arms (b) and (c) was a strict subset of the identity check beside it. **Three of the
four are; the fourth is not, and that claim was false.** `_bl199_path_is_inside "$abs_target"
"$fw_root"` — the AS-GIVEN comparison in arm (c) — uniquely catches a symlink that lives INSIDE the
framework and points OUTSIDE it (`ln -s /elsewhere "$FW/escape"`, target `$FW/escape/proj`):
identity and the physicalized string both say "outside", because the bytes really do land
elsewhere. Measured — removing that atom flips the target from REFUSE to allow. Round 1 shipped
that behaviour by over-determination, undocumented and unpinned; **T12** and **M7** now pin it.
The remaining three atoms, and `_bl199_physical_path`'s `pwd -P` while `_bl199_dir_id` does its own
(which is why M5 must remove both), are genuine over-determination on the cheap path.

**Decision recorded — `$FW/escape/proj` is REFUSED, deliberately.** This is a judgement call, not
an obvious invariant: physically nothing is written into the framework, so allowing it would not
break the no-contamination invariant. It is refused because the contract is stated over the path
the OPERATOR SUPPLIES ("not the clone, not anything inside it"), because otherwise acceptance would
depend on which symlinks happen to exist in the framework tree — framework CONTENTS deciding an
operator-input question, unpredictably and changeably — and because anyone who genuinely wants that
destination can pass its real absolute path. Refusal is the conservative side of a real ambiguity.

**Two hardening items from round 2.** The identity checks FAIL OPEN when the framework root has no
usable device+inode (no working `stat`, or an unsearchable root). Failing open is deliberate —
failing closed would refuse every target on such a box and brick init.sh — and the degradation is
narrow (only a case-variant or symlinked spelling is missed; the string comparisons still refuse
the root and any lexically-inside target), and unreachable through init.sh, where `fw_root` is
`$SCRIPT_DIR`. But *silent* degradation is this repo's named defect class, so it now emits a
`print_warn` to stderr. Separately, the `stat`-identity claim covers symlinks by measurement (T10 +
M5); it *should* cover hardlinked directories and bind mounts by definition, but no test in this
repo can reach either (unprivileged directory hardlinks are refused on both platforms, macOS has no
bind mounts), so that is written down as a deduction and not as a tested property.

T9 and M4 SKIP on case-sensitive filesystems, so the aggregator label deliberately carries no fixed
N/N and the suite's tally line now reports `Skipped` explicitly — `run_child_suite` prints a child's
output only on FAILURE, so on Linux a green run would otherwise leave no trace that two cases never
executed (BL-197's class in miniature).

**Follow-up NOT done in this change — `--dry-run` does not refuse a target it will refuse for real.**
Measured: `--validate-only` with an in-framework target exits 1 with the refusal; `--dry-run` exits
0 and prints "Re-run without --dry-run to execute". Pre-existing and harmless (dry-run writes
nothing), but the README offers `--dry-run` as the preview, so the preview now ends by recommending
a command that will be refused. Deliberately deferred rather than half-fixed: the flag half is a
three-line change, but the README's own tip is bare `./init.sh --dry-run` — the INTERACTIVE path,
where no target exists at the early block and the guard would have to move into `dry_run_summary`.
Fixing only the flag half would not fix the documented example. No new BL number is minted here
because the numbering space is contested across unmerged branches; this paragraph is the filing.

**Related:** BL-041 (the reorder that routed around this without seeing it), security-audits-1 S3
(the target-dir argument whose vector is preserved by arm (a)), CLAUDE.md § CITATION RULE.

---

## BL-200: The token-stream-break blind spot — an ordinary ASCII source file with a syntax error hides its sink from semgrep, and no byte-level check can see it

**Logged:** 2026-07-29 (split out of BL-198 v2 after review finding R-1 proved v1's plan blessed it).
**Numbering note:** BL-199 is deliberately skipped here — it is reserved by the concurrent init.sh
quick-start branch (`fix/bl199-quickstart-from-clone`), reserved cross-branch precisely to avoid the
divergent-`## BL-NNN:`-header trap recorded on BL-187. The gap is a reservation, not a lost entry.
**Category:** Enforcement / commit-time SAST — the residue BL-198 deliberately does not claim
**Severity:** Medium-High. Same false-attestation outcome as BL-192 (`[OK]` over an unscanned sink),
and the trigger is ORDINARY SOURCE — no exotic encoding, just a syntax break in the same file. What
keeps it below BL-192: a syntax-broken file usually fails the project's own build/tests, so a second
independent gate tends to catch the commit. **That "usually" is softer than it looks, and for a
measured reason (review R2-5), not the tier one first guessed:** the BL-125 test arm carries no tier
gating at all, but `soif_tests_not_enforced` is a pure WARN — no failure flag, the commit lands — so
any project with no configured `.claude/test-command` and no auto-detectable suite has NO second
gate on ANY tier. The severity holds because such projects exist in numbers; it is why this stays
open rather than Won't Fix.

**The measurement (reproduced twice, independently — implementer and reviewer, 5/5 deterministic).**
Fixture: `export function r(p){ p.innerHTML = window.name; }` plus a second line `function ((( broken
$$$`. Hook's exact flag set, semgrep 1.157.0:

| file | rc | findings |
|---|---|---|
| clean sink alone | 1 | 1 blocking |
| same sink + the break | **0** | **0** |

Byte facts on the broken file: first four bytes ASCII, no BOM, no NUL, decodes as valid UTF-8. Every
predicate in BL-198 reads it as clean text. **The premise was also attacked and held (review):** five
modern-TypeScript constructs a parser might plausibly choke on (`satisfies`, `using`, `accessor`,
decorators, `const` type parameters) were all scanned correctly, sink caught — the trigger needs a
GENUINE token-stream break, not merely new syntax. `# BL-112-SCAN-COVERAGE`'s residue paragraph has named
this case since it shipped; this entry gives it an owner.

**The only known detector, and the terms under which it is admissible.** `--verbose` emits
`[WARN] Syntax error at line <target>:N` — count 1 on the broken file, 0 on the clean control
(measured; and do NOT anchor on the `Partially analyzed…` header, which prints on every verbose
scan). That detector is REPORT-DEPENDENT, which the BL-192 decision blocks rule out for
correctness-bearing gates — so it is admissible only as: **best-effort hardening whose failure
degrades to today's behaviour** (anchor drifts ⇒ detector under-detects ⇒ status quo; it can never
mint a false receipt because it only ever FORFEITS receipts), **behind a framework-side canary
test** — a committed broken fixture scanned by the host semgrep in this repo's CI, asserting the
warning's exact spelling still fires, so an upstream respelling turns OUR lane red instead of
silently blinding every generated project.

**Costs to weigh at build time, not silently:** `--verbose` changes the shipped invocation and
raises stderr volume on the one path where scanner stderr reaches the operator; the canary needs
semgrep on the CI host (already true of the `sast` shard). Sequenced AFTER BL-198 — the transcode
work rewrites the same region, and two hands in that block at once is how BL-179/BL-182 earned their
"same rewrite by design" note.

**Status:** Open — unblocked 2026-07-30 (BL-198 implemented in `02eaa0f`).

**Related:** BL-198 (the plan that refuses to claim this), BL-192 (the decision blocks that
constrain the design), `# BL-112-SCAN-COVERAGE` (the residue note that named it first), BL-193
(why report-dependent anchors need canaries: spellings move between versions and even between
streams).

---

## BL-201: Float the 22 generated-project semgrep template pins and log the scanner version — AFTER BL-198 lands

**Logged:** 2026-07-29 (Karl's decision, made after the pin-vs-float ramifications were laid out; the
companion decision — this repo's own CI stays unpinned — is recorded on BL-192)
**Category:** Generated-project CI / currency
**Severity:** Medium. Nothing is broken today; what ages is coverage. The pinned `1.170.0` sits one
release below the 1.171.0 threshold where BL-192's metric silently changed meaning, and detection is
measured non-monotone (a fixture 1.157.0 misses, 1.171.0 catches) — a pinned project never receives
that catch, and nobody is watching the pin age.

**The decision (Karl, 2026-07-29):** *"Float the templates after BL-198 lands, and add the version
logging."* Rationale as recorded on BL-192: a security scan is no good if a project several weeks or
months old isn't checking for new vulnerabilities; stale is the invisible failure, loud-red-in-CI is
the failure mode this framework prefers everywhere else.

**Deliverables:**
1. All 22 `image: semgrep/semgrep:1.170.0` sites under `templates/pipelines/ci/**` (github + gitlab +
   bitbucket) move to a floating form (exact tag form decided at build per registry convention).
2. **Every semgrep job gains a version-log line** (`semgrep --version` into the job output) so "what
   scanned this merge?" is always answerable even though the build is no longer reproducible — the
   agreed price of floating, paid consciously.
3. **THE TRAP, called out so the build does not walk into it:**
   `tests/test-bl147-ci-template-integrity.sh` `Cg4-container` and `Cg5-image` REQUIRE
   `image: semgrep/semgrep:[0-9]+.[0-9]+.[0-9]+` — the version-PINNED form. The float commit must
   update those assertions in the SAME diff (to pin the floating form + the presence of the
   version-log line, so the suite keeps refusing a silently re-pinned or log-less template) or the
   PR-blocking lane goes red on arrival. **And fix the assertions' failure MESSAGES in the same
   diff (review R2-7):** they currently read `no 'image: semgrep/semgrep' in: …` while the grep
   actually demands the VERSIONED form — a float implementer reading that message would conclude
   the assertion is broken rather than that it wants a version. That is BL-197's
   evidence-destruction class in miniature: the message names a symptom the check does not test.

**Sequencing is load-bearing:** blocked by BL-198. Floating first would widen the window in which a
scanner behaviour shift meets a gate that still trusted scanner-reported numbers; after BL-198, no
clause reads anything semgrep prints, and version drift can only ever ADD findings loudly.

**Adjacent, noted not scoped:** the emitted hook's receipt could print the scanner version for the
same debuggability (BL-193 cost a day partly to version archaeology). One line; decide at build.

**Status:** Open — unblocked 2026-07-30 (BL-198 implemented in `02eaa0f`).

**Related:** BL-192 (both decision blocks), BL-198 (the gate this waits on), BL-147 (the parity
suite that must move in the same diff), BL-193 (the version-archaeology cost that motivates the
logging).

---

## BL-202: A fresh Claude Code session in a generated project dead-airs — nothing tells the user what to type, and nothing tells Claude the intake is unfinished

**Logged:** 2026-07-30 (Karl, five-item UX discussion; refined by a three-agent plan review)
**Category:** Generated-project onboarding / novice UX — the framework's audience includes users who have never used a CLI
**Severity:** Medium-High — the very first thing a new user does after setup is open Claude Code and wait for something to happen; nothing does.

**The dead-air, measured.** Claude Code loads project context only when the FIRST message is
sent; an open session with no message does nothing. The only path that avoids this is the
wizard's launch option 1, which passes the prompt as a CLI argument (`exec claude "Read
INTAKE_GUIDED_PROMPT.md and follow its instructions …"` in `run_claude_mode`). Every other
path strands the user in front of a silent prompt:

- wizard option 2 / `claude`-not-found prints a one-liner the user must remember later;
- desktop/IDE launches and mid-intake resumes have no instruction at all;
- the script-mode completion print says only *"Review PROJECT_INTAKE.md, then start Claude
  Code and begin Phase 0."* — with no hint of what to type;
- manual mode (3) writes nothing and points nowhere;
- init.sh's Phase-0 paste block is wrapped in `│ … │` box characters, so drag-selecting it
  copies the box art.

**Claude's side is equally blind.** The generated `CLAUDE.md`'s `### Session Start` section
is exclusively about `check-versions.sh`; nothing in the generated project detects "intake
incomplete" or "intake done but Phase 0 never started" at session start. The stranded-after-
intake state is MORE common than mid-intake: modes 2 and 3 land there by construction.
`.claude/intake-progress.json` is written by mode 1 ONLY (`init_progress` is never called on
the AI-assist or manual paths), so it must never be the sole detection signal —
`scripts/validate.sh`'s blank-table-cell count over `PROJECT_INTAKE.md` is the mode-agnostic
predicate (>20 blank cells ⇒ incomplete), with intake-progress as corroboration.

**Three "first messages" already exist** — init.sh's Phase-0 box, `PROJECT_INTAKE.md` §13's
`BEGIN:` block, and the wizard's `"Read INTAKE_GUIDED_PROMPT.md and begin"` — so the fix must
CONSOLIDATE, not add a fourth magic phrase.

**Fix shape (agreed 2026-07-30, sequenced after BL-203 — both edit the wizard and its suite):**
1. a new SessionStart hook `scripts/session-intake-check.sh` (modeled on
   `session-test-gate-check.sh`: silent when healthy, output the agent relays), registered via
   init.sh's existing SessionStart `jq` append pattern — NOT emitted from
   `scripts/lib/hook-templates.sh`. Two states: intake-incomplete, and
   intake-done + `current_phase == 0` + no `PRODUCT_MANIFESTO.md` ("stranded before Phase 0",
   points at `bash scripts/resume.sh`). Proceed-anyway is nag-ONCE: the agent offers
   continue-vs-proceed once and records an ack marker in `.claude/process-state.json` that
   silences the hook — never a blocking sentinel;
2. `scripts/resume.sh` becomes the single state-aware first-message generator (three
   branches: intake prompt / §13's BEGIN block verbatim / today's resume), with every print
   in the wizard and init pointing at the same one sentence;
3. print rewordings: copy-paste delimiter blocks instead of box art, "a blank screen means
   Claude is ready and waiting, not stuck", an install URL on the claude-not-found arm, and a
   `resume.sh` pointer on mode 3's completion.

**Related:** BL-203 (same wizard, must land first), BL-137 (the documented-but-impossible
class this repairs for onboarding), `docs/user-guide.md`'s §12→§13 pointer fix (shipped with
this entry's filing PR — the guide told users to paste from the section that says "do not edit").

**Status:** Open

---

## BL-203: The intake's "test every N features" answer is a silent no-op — the enforced interval is hardcoded to 2, and three surfaces disagree

**Logged:** 2026-07-30 (found during plan refinement for the eval-cadence discussion)
**Category:** Enforcement correctness / silent-config — the class where a user's recorded choice never reaches the code that enforces it
**Severity:** High for trust, low for safety — the gate fires MORE often than asked (2 < 5), but the user's answer is ignored without a word, and on the light track that is the DEFAULT outcome.

**The mechanism.** `run_section_11_5` in `scripts/intake-wizard.sh` saves the user's N into
`.claude/intake-progress.json::answers.testing_interval` and renders it into
`PROJECT_INTAKE.md` prose — and nowhere else. The ENFORCED field is
`.claude/build-progress.json::test_interval`, read by `scripts/test-gate.sh` (`jq
'.test_interval // 2'`) and `scripts/session-test-gate-check.sh`; it is written exactly once,
by init.sh, from a hardcoded `TEST_INTERVAL=2` on BOTH the interactive and `--non-interactive`
paths. `scripts/reconfigure-project.sh` and `scripts/upgrade-project.sh` have no such field.
So the enforced N is frozen at 2 regardless of the answer. **The light track defaults the
wizard prompt to 5** — a light-track user who presses Enter records 5 and is enforced at 2:
the divergence is the default outcome, not an edge case.

**Three surfaces disagree**, and each is read by a different consumer: the enforced field
(the gate), the rendered `CLAUDE.md` "Testing interval: Every N features (configured in
Intake Section 11.5)" line (the AGENT — and its parenthetical is the false advertisement),
and the intake prose (the USER). Two sibling defects of the same class, found in the same
sweep and in scope for the fix:
- `scripts/session-test-gate-check.sh` reads `.test_interval` with **no `// 2`** — `jq -r` on
  a missing key prints the literal string `null` with rc 0, the `|| echo 2` never fires, and
  the `-ge` comparison errors;
- `scripts/verify-install.sh` renders with `${TEST_INTERVAL:-5}` under a comment claiming
  init defaults to 5 (it defaults to 2) — a repair re-render fabricates a "5" nobody enforces.

**Fix shape (agreed 2026-07-30; single writer, marker `# BL-203-INTERVAL-PLUMB`):** a new
`scripts/test-gate.sh --set-interval N` action (validate, atomic `mktemp`+`mv`, re-evaluate
`.testing_required`, update the rendered `CLAUDE.md` prose line in place — NOT via
`soif_render_claude_md`, whose byte-identity contract is pinned by the plan-staging/currency
suites). Callers: `run_section_11_5` (script path), a new numbered instruction in
`run_claude_mode`'s guided prompt (the AI path never runs `run_section_11_5` — a wizard-only
fix silently no-ops there), and a new `test_interval` field arm in `reconfigure-project.sh`
(backfill from `intake-progress.json::answers.testing_interval` ONLY — no prose parsing;
absent ⇒ print the effective value and change nothing). Plus the two sibling fixes above, and
a self-revealing display: `test-gate.sh`'s OK branch names the interval and its source, and
warns with the exact reconfigure command when the intake answer differs. init.sh's hardcoded
2 STAYS (intake can never precede init — the wizard hard-requires `.claude/phase-state.json`).
Precedent: reconfigure's tier-crosscheck-6, the identical canonical-state-never-propagated
defect. `tests/edge-cases-scripts.sh` E56 pins `test_interval=2` after a no-intake
`--non-interactive` init — unchanged behavior, but E56 runs only in the full lane; run it
locally with the fix.

**Related:** BL-202 (same wizard file — land this first), BL-205 (the eval cadence rides this
interval), `templates/generated/claude-md.tmpl`'s "configured in Intake Section 11.5" line
(the cleanest citation for the false promise).

**Status:** Open

---

## BL-204: Remote-setup failure UX — the machinery exists; its failure edges strand exactly the users the framework is for

**Logged:** 2026-07-30 (Karl asked to verify init walks users through repo login/setup; audited instead of assumed — the naive premise was WRONG: an auth pre-flight already exists)
**Category:** Onboarding / novice UX audit — findings enumerated, each needs its own small fix
**Severity:** Medium — every finding has a workaround a technical user would find; the framework's audience includes users who will not.

**What exists and works:** `host_require_cli` (per-driver: gh/glab/bitbucket) checks CLI
presence AND auth before `host_create_repo`, with per-OS install guidance; init creates the
repo, adds the remote, pushes, and the Phase 1→2 gate blocks until the push is verified
(`BL-084-PUSH-VERIFY`, tier-keyed escape hatches; BL-032 free-tier attestations). Do NOT
re-file "no auth pre-flight exists" — it exists and runs at init.

**The audited findings (each independently fixable):**
1. `scripts/check-gate.sh`'s `host_create_repo` call — the documented REPAIR path init points
   failed users at — has NO `host_require_cli`, so an auth failure at init becomes an
   unexplained failure at repair;
2. `--repair` dead-ends on `host=other`: `scripts/lib/host.sh` returns 10 with *"'other' host
   requires user-supplied URL — call from init.sh interactively"* — framework-internal
   language shown to the exact user who chose bring-your-own-host;
3. repo-name collision loops forever: repair retries the SAME name (`.answers.project_name`,
   else `basename $(pwd)`) with no `--name`/`--visibility` overrides;
4. org users cannot create in an org namespace: `host_create_repo` passes a bare name — every
   org-tier repo lands in the operator's personal namespace or fails; SAML/SSO orgs fail at
   create-time while `gh auth status` passes, and the only workaround (create by hand, choose
   `other`) is the path finding 2 shows is unsupported at repair;
5. the CLI/credential probe runs at the wrong time: the wizard's good retry/switch/continue
   menu probes at host-selection — but the wizard runs AFTER init; init's own host prompt has
   no probe, so (e.g.) a Bitbucket user discovers the required
   `BITBUCKET_API_TOKEN`(+`_EMAIL`) exports at push time. Move the probe to init's selection
   point. The wizard's *"CLI will be verified again at init.sh"* sentence is backwards — fix it;
6. the visibility prompt is a bare `private|public` with zero explanation, and free-tier
   private silently costs branch protection (surfacing much later as an attestation prompt);
   add the plain-language explanation with the free-tier note;
7. host + visibility are asked twice (init, then the wizard, after the repo exists) — to a
   novice this reads as "my earlier answer didn't save"; skip or pre-fill from
   `.claude/manifest.json`;
8. nothing upstream of the choice explains WHY a remote matters ("this is your backup — a
   lost disk without one loses all work"); the framing exists only inside the data-loss
   warning arm. Add it to Next Steps.
Plus: host-error jargon (403s, rate limits, SSO) is surfaced raw — translate the 3-4 common
causes into one plain sentence + one action each, keeping the raw text below (precedent: the
free-tier-403 translation block in `scripts/host-drivers/github.sh`).

**Status:** Open

---

## BL-205: Eval cadence program — run the reviewer evals at milestones, gate on their artifacts, file them with phase/date/trigger (DESIGN DOC REQUIRED BEFORE ANY CODE)

**Logged:** 2026-07-30 (Karl's items 2-4 of the five-item discussion, refined by a three-agent plan review; several of the refiners' corrections are baked into this entry so it does not misstate today's gates)
**Category:** Process / enforcement design — touches the authoritative gate scripts; design-first
**Severity:** Enhancement, large. No code under this entry until its design doc is reviewed.

**The intent (Karl):** senior-dev + security evals before leaving Phase 1; the same two plus
UAT on the existing every-N-features trigger during Phase 2; ALL evals before entering Phase 3
(front-load fixes, hand human reviewers finished reports); reports filed with phase/date/
trigger designations; runs automated at the milestones.

**What exists:** six templated reviewers (`evaluation-prompts/Projects/`, compose.sh +
run-reviews.sh with per-reviewer watchdogs after F-DF2-015 — six unbounded `claude -p` calls
once orphaned ~159 processes), the manifest (`docs/eval-results/review-manifest.json`), and
the BL-073 Phase 3→4 gate (Security + Red Team mandatory on standard/full).

**Corrections this entry carries so the design starts from today's ACTUAL gate behavior:**
- a MISSING review manifest already BLOCKS at phase ≥ 3 for every track — both arms increment
  `issues` (the `[WARN]` label is cosmetic; the increment is the verdict). "Presence-checking
  is non-blocking today" is false;
- BL-073 is the grandfathering precedent (`review_gate_enforced`); BL-104 is the
  scoring-inversion precedent — do not conflate;
- manifest `phase`/`trigger` keys need NO lint change (extra keys are legal); the staleness
  predicate DOES need `date` tightened to REQUIRED in `lint-review-manifest.sh` plus defined
  behavior for date-less entries, or it is bypassable by deleting a field the lint permits;
- `run-reviews.sh --trigger` is PROPOSED, not existing;
- archival naming must carry a verdict slot to align with the documented convention
  (`docs/test-results` uses `[date]_[tool]_[pass|fail]`): `<date>_<reviewer>_<pass|fail>.md`,
  with `trigger` in the manifest;
- `SOIF_PHASE_GATES=warn` is NOT side-effect-free (it still writes gate dates) — do not
  describe it as a preview mode in the rollout plan.

**Design decisions already made:** producers vs enforcers — the AGENT runs
`run-reviews.sh --trigger <phase1-exit|feature-batch-N|phase2-exit>` at milestones (per the
generated CLAUDE.md); gates only verify manifest presence + freshness and never launch
sessions. Phase-1-exit evals are DESIGN-scoped variants (the current bases read every file
and score implementation categories that do not exist yet); feature-batch evals are
DIFF-scoped (full-repo reads every 2 features is disproportionate) and ride the SAME
`test-gate.sh --check-batch` trigger as UAT — note that interval is BL-203's. The full
six-reviewer sweep is the 2→3 entry criterion; 3→4 keeps Security + Red Team with a
deterministic staleness predicate (review date ≥ the 2→3 gate date — both recorded). Light
track: OFF by default (cost history + BL-073's deliberate light exemption); WARN-first
rollout for standard/full per the BL-102 fenced-arm template (`# BL-102-MARKET-SIGNAL-*`,
no `issues++`, mutation-pinned). Organizational deployments: the signed HUMAN review is the
review of record (the manifest lint's own header says persona output is "supplementary") —
agent evals feed it, never replace it.

**The design doc MUST answer (currently open):**
- **Q1 — who decides on a bad verdict, and does it block?** There is NO machine-readable
  verdict today: the six bases emit five different vocabularies (1-5 scores, Go/No-Go,
  Approved/Conditionally/Not, …) and manifest `status` records only ran-ness. Normalizing a
  verdict is a schema change with two synced readers (`lint-review-manifest.sh` +
  `check-phase-gate.sh`). Recommended shape: verdicts produce bug-tracker entries triaged
  through the EXISTING UAT vocabulary (Fix Now / Defer / Won't Fix / Post-MVP) by the
  Orchestrator (org: the Intake §8.2 approver) — no second blocking authority beside
  test-gate;
- **Q2 — cost per trigger:** 900s default watchdog × 2 reviewers per batch = a 30-minute
  worst case per interval; price it before the cadence is chosen;
- **Q3 — staleness:** date-only is trivially satisfiable (a gate date can precede 200
  commits) — date-only vs diff-aware, and stale ⇒ ATTESTABLE (`SOLO_REVIEWERS_ATTESTED`
  precedent), never silenced.

**Related:** BL-203 (the interval the batch trigger rides), BL-073, BL-102, BL-104,
F-DF2-015, `evaluation-prompts/v2-concepts/post-mvp-feature-development.md` (thematically
adjacent, unwired).

**Status:** Open

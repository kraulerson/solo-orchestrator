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
**Status:** Open

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
**Status:** Open

**Measured (2026-07-11):** nine files read `poc_mode`/`deployment` from state (check-phase-gate.sh — three DIFFERENT extraction variants, per audit; intake-wizard.sh; reconfigure-project.sh; run-phase3-validation.sh — BL-086 added another; pre-commit-gate.sh; process-checklist.sh; upgrade-project.sh; init.sh; verify-install.sh), while `scripts/lib/enforcement-level.sh` sits mostly unsourced. The duplicated parsing already caused the BL-084 null/production mishandling class, and every new gate re-derives it (BL-086 just did). Agents changing tier logic must locate and sync N inconsistent copies.

**Fix shape:** single `read_deployment()` / `read_poc_mode()` (jq-with-grep-fallback, null-safe) in the shipped lib; migrate the nine call sites to it. **Predicates stay per-gate** where semantics deliberately differ (BL-084 bypass vs BL-086 license-tier) — this centralizes PARSING, not policy. Constraints: all existing mutation-proofed suites (BL-084, BL-072 C2, BL-086) stay green untouched in intent; the lib is on the shipped set (BL-088 closure covers it); migrate incrementally with per-site verification, not a big-bang.

**Related:** ergonomics audit F4; BL-084 (the defect class); `# BL-084-TIER-KEY` sync-comment sites; `# BL-086-TIER`; `scripts/lib/enforcement-level.sh`; BL-088 (closure).

---

## BL-096: Cold-start hardening bundle — CDF preflight, --tdd-only help truth, contributor hook bootstrap

**Logged:** 2026-07-11 (ergonomics audit F6/F9/F10 leftovers)
**Category:** Debt / agent + contributor onboarding
**Severity:** Low
**Status:** Open

Three small onboarding traps the 2026-07-11 CLAUDE.md documents but does not fix at the point of failure:
1. **CDF preflight (F9):** tests/init.sh needing `~/.claude-dev-framework` fail deep in the suite on a fresh host; a preflight prints the exact `git clone` line at the point of failure instead.
2. **`--tdd-only` help truth (F6):** the flag runs TWO message gates (BL-072 TDD + BL-006 Build Loop; name kept for hook back-compat) — surface this in `pre-commit-gate.sh --help`/usage text, and consider a `--commit-msg-gates` alias (hooks keep the old flag).
3. **Contributor hook bootstrap (F10):** a one-liner (script or documented command) that installs `pre-commit-gate.sh` into `.git/hooks/` for framework contributors, so local commits face the same gates CI does instead of discovering them at PR time.

**Related:** ergonomics audit F6/F9/F10; CLAUDE.md (PR #176 — documents these; this entry fixes them at source); CONTRIBUTING.md.

---

## BL-097: Subagent model-selection rubric — assess-and-select instead of inheriting the session model

**Logged:** 2026-07-11 (Karl directive, token-efficiency wave)
**Category:** Proposal / agent token efficiency + capability (both repos)
**Severity:** Low
**Status:** Open

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
**Status:** Open

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
**Status:** Open

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
**Status:** Open

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
**Status:** Open

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
**Status:** Open

`docs/builders-guide.md` Step 4.2 marks the platform-module go-live checklist **"PLATFORM MODULE — MANDATORY"**, and the modules carry substantial checklists (`docs/platform-modules/mobile.md` alone: ~38 MUST/MANDATORY hits; desktop ~19; web ~7; mcp_server ~2). **No script parses `docs/platform-modules/*`** — the checklists are prose only.

**Scope:** decide deliberately whether platform checklists become machine-checkable (a structured block per module the gate can read) or whether the MANDATORY language is downgraded to guidance to match reality. Do NOT leave the current mismatch. Not exhaustively audited — the four modules were grepped, not read end-to-end.

**Related:** BL-105 (Phase-4 gate absence — the enclosing gap); BL-103/104.

---

## BL-107: Rust and `other`-language projects silently get NO TDD gate — including organizational/production tiers where it is advertised as non-bypassable

**Logged:** 2026-07-12 (E2E-walk checklist derivation, PR #188)
**Category:** Bug / gate integrity — documented-but-not-enforced, on a whole-language axis
**Severity:** **High** (the flagship TDD hard block does not exist for two language selections, on tiers where the docs promise it cannot be bypassed)
**Status:** Open

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
**Status:** Open

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
**Status:** Open

**Verified evidence:** the BL-099 birth-stamp (`# BL-099: birth-stamp .claude/manifest.json.soloFrameworkCommit`, init.sh ~:2498) lives INSIDE `create_and_protect_remote()` (opens ~:2182) — and that function's `--no-remote-creation` branch (~:2211) exits with `return 0` BEFORE the stamp is reached. Net: **every hermetic scaffold — all UAT/CI/agent runs and any operator passing `--no-remote-creation` — is born with NO `soloFrameworkCommit` pin.** Empirically reproduced during S1 (a real `--no-remote-creation` scaffold's manifest has no such key). The pin is the anchor of the entire Currency System (BL-109) and of `--sync-framework`'s drift reporting; a pin-absent manifest degrades both (sync stamps it on first run — self-healing there — but session-start detection reads it at birth).

**Why tests missed it:** the BL-099 suites drive sync/stamp paths directly; no fidelity test scaffolds via `--no-remote-creation` and asserts the pin — the [[bl088-scaffold-source-closure]] fixture-hides-gap class, on a FLAG axis this time (BL-107 was the same class on the LANGUAGE axis).

**Fix shape:** stamp the pin at the universal manifest-seed site (`prepare_initial_state_for_commit` — exactly where S1 anchored the `currency` block, which already records `soloFrameworkPath` there on every path); keep or dedupe the remote-path stamp (byte-compat decision documented in the PR); fidelity test asserting the pin on BOTH paths (with-remote fixture + `--no-remote-creation`), plus a mutation proof. Interim S2 contract: detection treats a pin-absent manifest as skip-silently for framework-drift checks (never a crash, never false drift).

**Related:** BL-099 (the pin's origin, PR #185); BL-109 (S1 anchored the currency block at the universal site precisely because of this gap — PR #191 deviation 1); [[bl088-scaffold-source-closure]] (defect class); BL-107 (same class, language axis).

---

## BL-111: The Phase 1→2 branch-protection backstop is unsatisfiable on the framework's own blessed hermetic flow — and it poisons every downstream gate snapshot

**Logged:** 2026-07-12 (E2E validation walk, finding F5 — the walk's SOLE hard FAIL; independently reproduced by the adversarial re-walker, 0 overturned)
**Category:** Bug / gate integrity — unsatisfiable gate
**Severity:** **High**
**Status:** Open

**Evidence (`Reports/2026-07-12-e2e-walk/RESULTS.md`, item P1-013):** for a `github` + `organizational` + `--no-remote-creation` project — the framework's own blessed hermetic on-ramp, used by every UAT/CI/agent run — the Phase 1→2 gate emits `[FAIL] Phase 1→2 backstop: protection verification failed` with `issues++`. Cause chain: `scripts/lib/host.sh` AND `manifest.json` both exist, so `host_load_driver` succeeds and `host_verify_protection main org` runs → `_github_parse_origin` rejects the local bare-repo origin (`not a GitHub URL`) → return 1 → FAIL. **The documented remediation also fails** (`scripts/check-gate.sh --preflight` → same parse error, rc=1). And **there is no product path to record the exemption**: un-truncated `grep -rn 'attestations.branch_protection *=' scripts/` → **0 writers**; only `init.sh` writes `github_free_tier`, and only behind a real host-API 403 that `--no-remote-creation` never reaches; `reconfigure-project.sh` covers `zdr_*` but has no branch-protection field.

**Blast radius:** `create_gate_snapshot` requires `issues=0`, so the clean 1→2 pass **and its snapshot — and, cascading, the 2→3 and 3→4 snapshots — are permanently unreachable** without a live remote or a re-init. The walk carried this gate RED across Stages 2–5. The walker refused to hand-forge the attestation JSON (that is the BL-103 sin) and graded FAIL per rubric R3a.

**Fix shape:** (1) `host_verify_protection` must distinguish *"not a supported host URL"* (→ WARN + attestable) from *"host says unprotected"* (→ FAIL); (2) ship a post-init writer for the branch-protection attestation (extend `reconfigure-project.sh`, mirroring its `zdr_*` handling) so the exemption is recordable, attested-not-silenced; (3) make `check-gate.sh --preflight/--repair` succeed or explain on a non-host origin; (4) fidelity test: scaffold `--no-remote-creation` and prove the 1→2 gate is passable by legitimate means. TDD + mutation proof; registered in both aggregators.

**Related:** BL-084 (deployment/track orthogonality); BL-110 (same `--no-remote-creation` blind spot, pin axis); [[bl088-scaffold-source-closure]] (fixture-hides-gap class — no test ever walked this flow); `Reports/2026-07-12-e2e-walk/RESULTS.md` (P1-013, F5).

---

## BL-112: Commit-time enforcement is hollow — the strict-mode git-hook gate is unreachable dead code, and the pre-commit SAST never blocks

**Logged:** 2026-07-12 (E2E validation walk, findings F8 + F9; both independently reproduced by the re-walker — F9 dynamically)
**Category:** Bug / enforcement — documented gates that do not fire
**Severity:** **High**
**Status:** Open

**F8 — `framework-gate.sh` is dead code.** The generated `.git/hooks/pre-commit` runs an unconditional `exit $FAILED` **before** the block that invokes `.git/hooks/framework-gate.sh` (the BL-030 strict gate that runs `--check-commit-ready`), even when `enforcement_level=strict`. Net: the **phase2-init-verified**, **UAT-in-progress**, and **build-loop-state** blocks have **no git-hook backstop** — they fire only through the AI-session PreToolUse hook. Proven empirically twice in the walk: a real `git commit` succeeded with `phase2_init.verified=false`, and a `chore:` commit succeeded mid-UAT — both correctly refused by `--check-commit-ready` (rc=1) yet committed at the terminal. **Any human, script, or non-AI-session commit walks straight through three "blocking" gates.** (BL-072/BL-006 are unaffected — they have the commit-msg-hook backstop.)

**F9 — the pre-commit SAST arm is decorative.** The hook invokes `semgrep scan --config=p/owasp-top-ten --quiet` **without `--error`**; semgrep exits 0 on findings unless `--error` is passed, so the hook's `[BLOCKED]` branch is unreachable. Demonstrated: an `eval(req.query.code)` Express injection flaw was **detected, printed, and committed clean**; the same finding with `--error` → rc=1. The gitleaks secret-scan arm *does* block — only the SAST arm is hollow.

**Fix shape:** move the `framework-gate.sh` invocation **before** the terminal `exit`, or fold its checks into the surviving path (and mutation-prove that a `verified=false` / mid-UAT commit is refused **by git**, not only by the AI hook); add `--error` to the semgrep invocation (with a fixture proving a planted flaw goes RED). Both need scaffold-fidelity tests that run a REAL `git commit` in a REAL scaffold — the class of test that would have caught this.

**Related:** BL-030 (the strict gate this makes unreachable); [[bl088-scaffold-source-closure]]; BL-113 (the Phase-3 half of the same story); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F8, F9).

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
**Status:** Open

Three defects in the same gate, all walk-reproduced:

1. **F2 — dead WARN branch (errexit abort).** A placeholder-only manifesto section trips `set -euo pipefail` inside `validate_manifesto_content` and **aborts `check-phase-gate.sh` before the placeholder WARN prints** — rc=1 with *zero diagnostic and no summary*. The operator sees a bare failure with no reason; the WARN branch is effectively unreachable code.
2. **F1 — non-blocking "blocking" WARN.** The phase-0-intermediates check never increments `issues`: deleting `docs/phase-0/frd.md` yields `2/3 saved` but **rc=0 `Phase gates consistent`** — contradicting the documented WARNS-and-blocks behavior. An **absent `docs/phase-0/` directory produces no warning at all**.
3. **F3 — the 0→1 transition is un-gated locally.** A bare `check-phase-gate.sh` at `current_phase=0` validates **no** 0→1 evidence (manifesto/phase-0/approval checks are all `current_phase>=1`-guarded), and `start_phase1()` advances **with no gate consult**. Only the prospective `--gate phase_0_to_1` form checks anything.

**Fix shape:** guard the manifesto content scan against errexit (subshell + explicit status) so the WARN prints and the gate summarizes; decide deliberately whether the intermediates check blocks (per the CLAUDE.md `issues++` = BLOCK rule) and make code match docs; make `start_phase1` consult the gate. Each with a mutation proof — note the `[WARN]`-vs-`issues++` trap.

**Related:** BL-104 (the same `issues++`-is-the-real-verdict class); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F1, F2, F3).

---

## BL-115: Approval evidence is satisfiable without approval — any date in the window counts, and the attorney gate is satisfied by its own template header

**Logged:** 2026-07-12 (E2E validation walk, findings F6 + F16)
**Category:** Bug / approval-evidence integrity
**Severity:** Medium
**Status:** Open

**F6 — proximity-window date matching.** `_cpg_gate_has_evidence` greps for **any ISO date in the 15-line window** after a gate header, not the approval's **Date cell** — so a blank or missing approval date is masked by an incidental date in a Reference or Notes cell. Demonstrated at the 1→2 approval (P1-010). Extends the same proximity-window class found at P0-014. Also (CM-H-08): the approver's **role is never verified** — any name is accepted; the retroactive-STA-by-role check only fires for `upgraded_from:personal` projects (count = 0 here).

**F16 — the attorney gate satisfies itself.** The Phase-3 attorney-review check greps `-qi 'attorney|legal review'` against `APPROVAL_LOG.md` — and the **organizational APPROVAL_LOG template ships with a literal `## Attorney / Legal Review` header**, so the gate passes with **zero real attorney entry**. Separately, deleting `PRIVACY_POLICY.md` **bypasses the legal_review step entirely** (the check is file-conditional): collect PII, write no policy, pass.

**Fix shape:** parse the approval **row** (Date cell specifically, non-empty, plausible) rather than a proximity window; require a signer distinct from the template's own scaffolding text (the header alone must not satisfy); make the legal review **required-when-PII** rather than skipped-when-absent (BL-102's evidence-standard doctrine applies: fail closed). Mutation proofs on each.

**Related:** BL-105 (hollow-gate family); BL-102 (fail-closed evidence doctrine); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F6, F16, CM-H-08).

---

## BL-116: The "MANDATORY, non-bypassable" push gate is scoped to `host=other` only — first-class hosts scaffolded `--no-remote-creation` never get it

**Logged:** 2026-07-12 (E2E validation walk, finding F7)
**Category:** Bug / gate scope
**Severity:** Medium
**Status:** Open

The BL-084 push-verification gate — documented as **MANDATORY and non-bypassable** — is implemented only for `host == "other"`. A `github` / `gitlab` / `bitbucket` project scaffolded with `--no-remote-creation` **never receives the mandatory push verification**: `grep -c 'push gate'` in the gate's output is **0**, both with and without a pushed remote. The scope comment's stated premise — *"first-class hosts are provably pushed at init"* — is **false for `--no-remote-creation`**, which is precisely the flow every hermetic/UAT/CI run and many operators use.

**Fix shape:** key the push gate on *"is there a verified remote with the work pushed"*, not on host brand; or, if first-class hosts are genuinely exempt when a remote was created, make the exemption **conditional on remote creation having happened** (the manifest records it) and prove the `--no-remote-creation` case still gates. Mutation proof required — a "MANDATORY" gate that silently doesn't exist for the common path is the cardinal defect class.

**Related:** BL-084; BL-110 + BL-111 (the same `--no-remote-creation` blind spot on the pin and protection axes — three findings, one uncovered flow); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F7, P1-012).

---

## BL-117: BL-088 class recurrences — the production build ships without its own migration asset, and `check-maintenance.sh` is never scaffolded

**Logged:** 2026-07-12 (E2E validation walk, findings F19 + F20)
**Category:** Bug / scaffold closure (the [[bl088-scaffold-source-closure]] class)
**Severity:** Medium
**Status:** Open

**F19 — the release does not boot.** The walked project's production build **does not run**: `tsc` omits `migrations/001_init.sql` from `dist/`, so the documented `npm start` (`node dist/src/server.js`) crashes `ENOENT`. The framework's `phase4_release:production_build` step has **no artifact or smoke arm** and was marked complete on a non-booting build. A "released" project that cannot start is the sharpest possible statement of the missing Phase-4 evidence arms.

**F20 — a guide-referenced tool that is never shipped.** `scripts/check-maintenance.sh` is framework-only: `init.sh` ships it **0 times**, so the builders-guide's Step 4.4 maintenance tool returns *"No such file"* in-project — and nothing schedules it either.

**The class, stated plainly (the walk's own honorable mention):** *a shipped instruction that points at an unshipped dependency* recurred **at least six times** in one walk — the TDD gate silently no-ops without `tdd-classify.sh` (BL-088, reproduced on demand), `security-audit-findings.tmpl` (BL-108), `rollback-test.tmpl` + `handoff-test-results.tmpl` (gate-referenced, never shipped), `check-maintenance.sh` (F20), and the app's own migration asset (F19). This is not a set of one-off bugs; it is a **structural gap between what `init.sh` ships and what the gates and guides demand.**

**Fix shape:** ship the missing artifacts; add a **smoke arm** to `production_build` (the built artifact must start); and — the durable fix — **extend the BL-088 closure check from sourced scripts to every path any shipped script or guide names** (templates, tools, artifacts), mechanically derived so it cannot drift. That single check would have caught five of the six.

**Related:** [[bl088-scaffold-source-closure]] (the parser to extend); BL-108 (templates half); BL-105 (the missing Phase-4 evidence arms); `Reports/2026-07-12-e2e-walk/RESULTS.md` (F19, F20, and the class inventory).

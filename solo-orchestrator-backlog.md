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

**Status values:** `open` / `in-progress` / `promoted-to-spec` / `resolved` / `wontfix`.

When an item is promoted to a full spec, leave the entry here with status `promoted-to-spec` and link the spec file — don't delete; the backlog is also an audit trail of what we considered.

---

## BL-001: Audit downstream sync mechanism for CDF updates

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Open

Existing downstream projects at older CDF `FRAMEWORK_VERSION` need a sync mechanism to pick up upstream fixes. `scripts/upgrade-project.sh` is presumed to handle this, but if its CDF-sync logic is stale, silently skips, or doesn't update `.claude/framework/` files, downstream projects miss landed fixes — e.g., FRAMEWORK_VERSION 4.2.2's Context7 detection and stop-checklist `--no-merges`/`CURRENT_HAS_SOURCE` improvements.

**Scope:** read `upgrade-project.sh`'s CDF handling; verify it pulls fresh CDF clone; verify it replaces `.claude/framework/` files correctly; verify `FRAMEWORK_VERSION` is updated in the downstream project; add regression test in `tests/upgrade-path-tests.sh`; document user-facing invocation in `docs/user-guide.md`.

**Trigger:** Before the next major CDF upstream fix that downstream projects need to pick up, OR after a downstream project reports missing a fix.

**Related:** CDF upstream commits `a640ba8`, `fd8469a`, and `4.2.2`-era changes; solo-orchestrator's BUG-001 and BUG-007 "Superseded" updates.

---

## BL-002: Handle GitHub free-tier branch-protection 403 gracefully

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Medium
**Status:** Open

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
**Status:** Open

Plan Task 10.1 was deferred during inline execution. Current test coverage: driver-level unit tests (mocked CLIs) and three regression cases (lancache-pattern, missing host field, protection drift). Missing: a "happy path" test that runs `init.sh`'s new `create_and_protect_remote` end-to-end against mocked `gh`/`glab`/`curl` and verifies all post-conditions (manifest host field set, CI template at correct host-specific path, `process-state.json` `phase2_init.steps_completed` populated).

**Scope:** add `tests/host-drivers/e2e-init.test.sh`. For each host (github/gitlab/bitbucket/other), scaffold a minimal init environment, run `create_and_protect_remote`, assert post-state.

**Trigger:** Before refactoring `init.sh`'s host flow; any change there risks silent regression without this test.

---

## BL-004: Upgrade-path regression test for flat→per-host template migration

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Open

Plan Task 10.3 was deferred during inline execution. `scripts/upgrade-project.sh` now handles two migrations (flat CI templates → per-host subfolders; manifest `host` field backfill) but neither migration has a regression test.

**Scope:** add case to `tests/upgrade-path-tests.sh`. Scaffold a project with old flat `templates/pipelines/ci/*.yml` layout and manifest without `host` field, run upgrade, assert: existing `.github/workflows/ci.yml` preserved, templates moved to `github/` subfolder, `host` field backfilled to `github` (inferred from remote URL), process-state.json NOT auto-verified.

**Trigger:** Before the first downstream project attempts to upgrade to this framework version.

---

## BL-005: Parity test coverage for GitLab and Bitbucket drivers

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Low
**Status:** Open

Driver-level test coverage varies: GitHub has 8 scenarios (full contract, both modes, drift cases); GitLab has 6 (most of contract, both modes); Bitbucket has 4 (name, require_cli, register_remote, parse_origin only — HTTP logic untested). Bitbucket's `host_configure_protection` and `host_verify_protection` HTTP calls are validated by code review only.

**Scope:** extend `tests/host-drivers/bitbucket.test.sh` with mock-curl fixtures for: configure_protection (personal + org payloads), verify_protection (all restriction types present → pass; missing restrictions → fail with specific messages), drift detection.

**Trigger:** Before the first solo-orchestrator user tries Bitbucket, OR whenever touching `bitbucket.sh`.

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
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. Install a local `commit-msg` git hook via `init.sh` that invokes `scripts/process-checklist.sh --check-commit-message "$(head -n1 "$1")"`. Extends enforcement to two populations the PreToolUse hook cannot reach: (a) `git commit` with no `-m` flag (editor opens), and (b) human-Orchestrator commits from the terminal. The BL-006 design was explicitly built so this is a pure addition — no refactor needed.

**Trigger:** A concrete case where an editor-opened or human-typed `feat:` commit drifts past the Build Loop. Lancache pain was AI-agent authored only, so there is no current signal this matters.

**Tradeoff:** adds a second enforcement site to keep in sync with the PreToolUse hook; meaningful surface-area increase on `init.sh`. Worth it only if the gap bites.

**Related:** BL-006 spec § 10 (out-of-scope note); `pre-commit-gate.sh` architecture is Claude-only by design.

---

## BL-011: Cutline-ID-aware enforcement

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. Parse `PRODUCT_MANIFESTO.md §5` for F-/ID- Cutline identifiers and require commits that touch Cutline work to explicitly reference the ID (e.g., `feat(ID1): ...`), cross-checking that each Cutline ID gets exactly one Build Loop. Catches drift where Cutline work masquerades as a bugfix (`fix(ID1): ...`) or doesn't mention the ID at all.

**Trigger:** A concrete case where a Cutline item drifts under a non-`feat` commit prefix after BL-006 ships. BL-006 closes the `feat:` gap; BL-011 would close a hypothetical `fix:`/`refactor:` gap.

**Tradeoff:** forces every project to adopt an F-/ID- prefix convention in their manifest. BL-007 deliberately kept the rule generic — no ID convention imposed. BL-011 would re-impose one.

**Related:** BL-006 spec § 10; BL-007 doctrinal decision to keep the Cutline rule convention-free.

---

## BL-012: Retroactive scanning for drifted feature commits

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. Scan git history for `feat:`-prefixed commits with no corresponding Build Loop recorded in `.claude/build-progress.json`. Report drift and optionally walk the user through `test-gate.sh --record-feature` reconciliation for each.

**Trigger:** A project onboarding to solo-orchestrator mid-stream wants to audit its git history for past Cutline drift. Today, `test-gate.sh --record-feature` handles one-at-a-time post-hoc recording; BL-012 would batch it.

**Tradeoff:** the hook enforces forward-only by design — the backlog's position is that historical commits don't need retroactive gating. BL-012 only matters if a user explicitly asks for history audit tooling.

**Related:** BL-006 spec § 10; existing `test-gate.sh --record-feature` post-hoc path.

---

## BL-013: Squash-merge server-side enforcement via CI

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. `gh pr merge --squash` runs on the remote host, outside the PreToolUse hook's reach. Any enforcement there needs CI — a GitHub Actions workflow (and GitLab CI / Bitbucket Pipelines equivalents) that reads the squash-merge commit message and rejects the merge if it's `feat:`-prefixed and the branch never recorded a Build Loop.

**Trigger:** A concrete case where a Cutline item is merged via squash-merge without a matching Build Loop on the branch. Requires solo-orchestrator's host drivers to gain CI-workflow templates for all three hosts.

**Tradeoff:** cross-host workflow parity is non-trivial; secrets and state-file access from CI add complexity. The pre-commit gate catches drift at authoring time, which is the more common failure mode.

**Related:** BL-006 spec § 10; host driver architecture (`scripts/host-drivers/`).

---

## BL-014: Commit-type hygiene enforcement

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

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
**Status:** Open

Sibling-script follow-up logged when BL-016 shipped. `scripts/intake-wizard.sh` has `--upgrade-to-production` and `--upgrade-deployment` flags but no overarching `--non-interactive` semantic for the initial intake interview (Sections 1–8 of the wizard). Lower urgency than init.sh because the wizard is typically run once per project; init.sh is the high-frequency entry point.

**Scope (suggested when promoted to spec):** add `--non-interactive` flag mirroring BL-016's design — per-section input flags, JSON `--config FILE` support, three-pass validation, `--validate-only`, uniform error format. Keep the existing interactive flow untouched (Approach A from BL-016).

**Trigger:** an explicit need for scripted intake (CI pipeline that creates many similar projects, agent-driven intake automation).

**Related:** BL-016 spec §12 (out-of-scope items).

---

## BL-018: upgrade-project.sh non-interactive mode

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** Medium
**Status:** Open

Sibling-script follow-up logged when BL-016 shipped. `scripts/upgrade-project.sh` already has `--track`, `--deployment`, `--to-production`, `--to-sponsored-poc` flags but no overarching `--non-interactive` semantic. Defaults are mostly already non-prompting; the gap is explicit input validation (uniform error format) + `--validate-only` smoke-test mode.

**Scope (suggested):** wrap the existing flag set in a `--non-interactive` mode that adds the BL-016 validation/error/validate-only patterns. Smaller than BL-017 because the underlying flags already exist.

**Trigger:** when scripted upgrades become a frequent operation (post-BL-017 likely).

**Related:** BL-016 spec §12.

---

## BL-019: verify-install.sh non-interactive audit

**Logged:** 2026-04-25
**Category:** Audit
**Severity:** Low
**Status:** Open

Sibling-script follow-up logged when BL-016 shipped. `scripts/verify-install.sh` already has `--check-only` and `--auto-fix` flags, both of which are arguably non-interactive variants. Audit task: confirm no remaining interactive prompts in those modes. The framework-self-contamination incident (UAT 2026-04-25 U-N) was triggered by `verify-install.sh` running outside a project — the U-N guard in PR #18 prevents that, but the script's "auto-create stub artifacts" remediation behavior (UAT U-M) is also worth re-examining.

**Scope:** read `verify-install.sh` end-to-end; identify any interactive `read`/`prompt_*` calls in `--check-only` or `--auto-fix` paths; if any exist, either remove or guard them behind a non-interactive default.

**Trigger:** opportunistic — pair with the next visit to verify-install.sh code.

**Related:** BL-016 spec §12; UAT 2026-04-25 U-M (verify-install.sh auto-creates stub artifacts when run outside a real project).

---

## BL-020: pre-commit-gate.sh `\bgit\b.*\bcommit\b` regex over-broad

**Logged:** 2026-04-26
**Category:** Debt
**Severity:** Medium
**Status:** Open

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
**Category:** Debt
**Severity:** Medium
**Status:** Open

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
**Category:** Debt (docs/guidance)
**Severity:** Medium
**Status:** Open

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

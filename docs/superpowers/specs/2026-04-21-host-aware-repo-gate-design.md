# Host-Aware Repo Creation Gate

**Date:** 2026-04-21
**Status:** Design approved, pending spec review
**Scope:** Framework-level change to solo-orchestrator

## Problem

The Builder's Guide sequences Phase 2 initialization with repo creation and branch protection as step 1, before scaffolding, CI setup, Docker, migrations, etc. In practice that step can be skipped without consequence — the session proceeds through steps 2–10 on local-only state, and the missed step gets normalized. The lancache project (Phase 2 init session on 2026-04-20) hit exactly this pattern: step 1 deferred "no GitHub remote configured," steps 2–10 executed locally, memory entry flagged the gap but nothing blocked progression.

The existing `scripts/process-checklist.sh --verify-init` gate was designed to prevent this, but has two structural weaknesses:

1. **Fires too late.** The gate is checked on the first `--start-feature` call, not when Phase 2 init work begins. All the scaffolding, Docker, CI, and migration work in Phase 2 init runs before the gate has anything to check.
2. **Verifies a proxy, not the real thing.** `branch_protection_configured` is satisfied by `.github/workflows/ci.yml` existing. A project can have a CI yaml and zero actual branch protection rules on the remote.

Beyond those, the framework's GitHub-specificity is implicit rather than stated — CI templates are GitHub Actions only, docs use `gh api` examples without callouts, and non-GitHub users have no sanctioned path.

## Goals

- No solo-orchestrator project reaches Phase 1 without a protected remote.
- Support GitHub, GitLab, and Bitbucket as first-class hosts (real creation, real verification, real CI templates).
- Support other hosts via URL-paste + manual attestation, without blocking.
- Eliminate the "skip-and-forget" failure mode by moving repo creation into init.sh (pre-Phase-0).
- Keep a backstop at Phase 1→2 for projects that drift or predate this change.

## Non-Goals

- Not supporting Gitea, Codeberg, CircleCI, Jenkins, or other hosts as first-class. `other` tier is the answer.
- Not migrating existing projects automatically. Forward-only; existing projects hit the backstop and remediate manually.
- Not providing a gate-override flag. First-class hosts are API-verified; `other` has manual attestation. That is the full set of paths.
- Not redesigning phase-gate approvals (`APPROVAL_LOG.md`). Branch protection reviews and phase-gate approvals remain independent and composing.

## Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Architecture | init.sh creates repo + Phase 1→2 backstop | Primary enforcement + drift catcher |
| 2 | Host scope | GitHub preferred, URL fallback | Don't block non-GitHub users |
| 3 | Fallback depth | Full host abstraction with CI templates | Non-first-class CI yaml is a paper cut we can afford to fix |
| 4 | First-class hosts | github, gitlab, bitbucket | Line-drawing at API maturity + user share |
| 5 | Personal vs org | Symmetric bar; personal = weaker-but-real | "Recommended but not required" is exactly how lancache happened |
| 6 | Migration | Forward-only | Lancache already remediated by owner; no mass-migration need |
| 7 | Escape hatch | None; manual attestation for `other` only | Override flags get abused; gates fire at planned milestones, not emergencies |

## Architecture

**Core concept — host drivers.** Every host-specific operation goes through a uniform interface defined in `scripts/lib/host.sh` (the dispatcher) and implemented per-host in `scripts/host-drivers/<host>.sh`. Callers never see `gh`, `glab`, or curl; they call `host_verify_protection`, and the dispatcher routes to the right driver based on `.claude/manifest.json`'s `host` field.

**Two enforcement points:**

1. **Init-time creation (primary).** `init.sh` refuses to complete without a created, remote-pushed, protection-configured repository. Eliminates the skip-and-forget failure mode — no "I'll do it later" path exists in intake.
2. **Phase 1→2 backstop (secondary).** `check-phase-gate.sh` re-verifies via live API call that the remote still exists and protection is still configured per the project's mode. Catches remote deletion, loosened protection rules, and projects migrated forward from pre-fix versions.

**Host tiers:**
- **First-class** (`github`, `gitlab`, `bitbucket`): CLI-driven creation, API-verified protection, host-specific CI and release templates.
- **`other`**: URL-paste creation, manual attestation for protection, no CI template laid down (builder supplies their own).

**Protection bar (symmetric across modes, D1):**
- **Personal mode:** force-push disabled on main, admins not exempt from the rule.
- **Org mode:** all of personal + required PR review (`required_approving_review_count=1`) + required status checks (CI must pass) + dismiss stale approvals on new commits.

`mode` (personal vs org) is inherited from the existing intake field — this design does not introduce or redefine it. Only the protection bar per mode is new.

## Components

### New files

```
scripts/
├── lib/
│   └── host.sh                         # Dispatcher
├── host-drivers/
│   ├── github.sh
│   ├── gitlab.sh
│   └── bitbucket.sh
├── check-gate.sh                       # New helper: --repair, --preflight, --backfill-host

tests/
└── host-drivers/
    ├── github.test.sh
    ├── gitlab.test.sh
    └── bitbucket.test.sh

templates/pipelines/
├── ci/
│   ├── github/    (10 files, moved from flat ci/)
│   ├── gitlab/    (10 files, new)
│   └── bitbucket/ (10 files, new)
└── release/
    ├── github/    (4 files, moved from flat release/)
    ├── gitlab/    (4 files, new)
    └── bitbucket/ (4 files, new)
```

### Modified files

| File | Change |
|------|--------|
| `init.sh` | Host selection + driver invocation for repo creation; writes `host` field to manifest |
| `scripts/intake-wizard.sh` | Add host question (github / gitlab / bitbucket / other); validate CLI availability for first-class |
| `templates/project-intake.md` | Add "Git Host" field under repository section |
| `templates/intake-suggestions/common.json` | Add host suggestions + per-host CLI prerequisites |
| `scripts/process-checklist.sh` | Rewrite `verify_init` to call `host_verify_protection` instead of checking `.github/workflows/ci.yml` existence |
| `scripts/check-phase-gate.sh` | Add Phase 1→2 backstop: invoke `host_verify_protection` before allowing transition |
| `scripts/pre-commit-gate.sh` | Add early guard: fail loudly if `git remote get-url origin` fails |
| `scripts/upgrade-project.sh` | Handle CI template path migration (flat → per-host directory) |
| `scripts/resolve-tools.sh` | Add host-CLI availability to tool-matrix resolution |
| `templates/tool-matrix/common.json` | Add `gh`, `glab`, `curl` as host-aware entries |
| `docs/builders-guide.md` | Replace GitHub-only repo/protection section with host-aware sections (one per first-class host) |
| `docs/cli-setup-addendum.md` | Add `gh` / `glab` install+auth instructions |
| `.claude/manifest.json` (per-project, at init) | New field: `"host": "github" \| "gitlab" \| "bitbucket" \| "other"` |

### Driver contract

Every driver in `scripts/host-drivers/` implements these functions. All exit 0 on success, non-zero with stderr message on failure.

```sh
host_name                                    # echoes: "github" | "gitlab" | "bitbucket"
host_require_cli                             # verifies CLI + auth; prints install steps if missing
host_create_repo <name> <visibility>         # creates remote repo; echoes HTTPS clone URL
host_register_remote <url>                   # git remote add origin <url>
host_configure_protection <branch> <mode>    # mode: "personal" | "org"; applies D1 rules
host_verify_protection <branch> <mode>       # API-queries current rules; 0 if meets bar
host_push_initial <branch>                   # initial push with upstream tracking
```

The dispatcher (`scripts/lib/host.sh`) exposes the same function names, reads `.claude/manifest.json` for the host field, and sources the matching driver.

For `other`:
- No driver file. Dispatcher handles `other` directly via URL prompt + manual attestation.
- `host_verify_protection` for `other` reads a one-time attestation record from `.claude/process-state.json` (`phase2_init.attestations.branch_protection`).
- Attestation expires after 90 days to force periodic reconfirmation.

### `scripts/check-gate.sh` — remediation helper

New standalone script exposing three subcommands, all of which source the dispatcher and operate on the current project's manifest.

| Subcommand | Purpose | Behavior |
|---|---|---|
| `--preflight` | Dry-run of `host_verify_protection` | Reports current status (remote reachable? protection rules match bar?) without blocking or modifying anything. Intended for builders to self-audit before hitting a real gate. Exit 0 = ready, non-zero = would block. |
| `--repair` | Re-run repo setup from last successful step | Reads `phase2_init.steps_completed` to determine what's done, invokes the remaining driver calls (create / push / configure) in order, re-runs verify. Idempotent — safe to run multiple times. Intended for init failures mid-flight and backstop-gate failures at Phase 1→2. |
| `--backfill-host` | Detect and record missing `host` field | Reads `git remote get-url origin`, infers host from URL pattern (`github.com` → github, `gitlab.*` → gitlab, `bitbucket.org` → bitbucket, else `other`), prompts user to confirm inference, writes confirmed value to `.claude/manifest.json`. Does not auto-confirm — prompt-and-confirm keeps the human in the loop for self-hosted edge cases (e.g., a private GitLab instance). |

## Data Flow

### Flow A — Intake (pre-init)

1. `intake-wizard.sh` runs existing questions.
2. New: asks "Git host?" → `github` / `gitlab` / `bitbucket` / `other`.
3. New: asks "Repo visibility?" → `private` / `public` (org mode forces private).
4. New: if first-class, probes CLI via `host_require_cli`. On failure: print install+auth steps, offer retry / switch host / abort. Never silently falls back to `other`.
5. Writes `git_host`, `repo_visibility`, `repo_name` to `.claude/intake-progress.json` and `PROJECT_INTAKE.md`.

### Flow B — Init (new project creation)

1. `init.sh` reads host/visibility/name/mode from intake.
2. Sources `scripts/lib/host.sh`.
3. Calls `host_require_cli` (no-op for `other`).
4. `git init` (local).
5. First commit (scaffolded files only; pre-Phase-0 state).
6. Creates remote: first-class → `host_create_repo`; other → prompt for URL.
7. `host_register_remote`.
8. `host_push_initial main`.
9. `host_configure_protection main <mode>`: first-class → API calls; other → attestation prompt.
10. `host_verify_protection main <mode>`: first-class → API query; other → reads attestation. On failure, init.sh exits non-zero **without** writing `.claude/manifest.json`. Remote, push, and any successful protection config are preserved (per Error Handling Category 2 — no rollback); `process-state.json` tracks `phase2_init.steps_completed` so `scripts/check-gate.sh --repair` can resume from the failure point.
11. Writes `.claude/manifest.json` with `host`, `mode`, `remote_url`.
12. Copies CI template from `templates/pipelines/ci/<host>/<language>.yml` to the host-specific destination:
    - `github` → `.github/workflows/ci.yml`
    - `gitlab` → `.gitlab-ci.yml` (repo root)
    - `bitbucket` → `bitbucket-pipelines.yml` (repo root)
    - `other` → skipped; prints note: "No CI template laid down for host `other`. Supply your own CI config."
13. Proceeds to Phase 0.

### Flow C — Phase 1→2 transition (backstop)

1. `check-phase-gate.sh` reads current phase from `phase-state.json`.
2. On 1→2 transition: reads host+mode from manifest, sources dispatcher, calls `host_verify_protection main <mode>`.
3. On fail: block with specific failing rule + exact remediation command + `scripts/check-gate.sh --repair` hint. `phase-state.json` unchanged.
4. On pass: `process-state.json` → `phase2_init.verified = true`; `phase-state.json` → `current_phase = 2`; appends crossing record to `APPROVAL_LOG.md`.

### Flow D — Per-commit guard

`pre-commit-gate.sh` adds early check: if `git remote get-url origin` fails, block commit with message pointing to `scripts/check-gate.sh --repair` or `docs/builders-guide.md § Repository Setup`. Catches projects that somehow end up remote-less between phases.

## Error Handling

Five categories, each with consistent contract: stderr message, non-zero exit, three things printed (what failed, why it matters, exact retry command).

### 1. CLI missing or unauthenticated

Block at intake-wizard. Print host-specific install+auth commands verbatim. Offer retry / switch host / abort. Never silently fall back to `other` — that would re-create the skip-and-forget pattern.

### 2. Repo creation failed mid-flight

| Failure point | Rollback? | Behavior |
|---|---|---|
| Remote created, push failed | No | Leave remote. Print: "Remote at $URL, push failed: $REASON. Run: `scripts/check-gate.sh --repair`" |
| Pushed, protection failed | No | Leave pushed state. Print: "Pushed, protection failed: $REASON. Run: `scripts/check-gate.sh --repair`. Init blocks until verify passes." |
| Configured but verify disagrees | Block, retry | Print mismatch. Auto-retry verification once after 10s (API lag). If persistent, require manual host-UI check. |

`phase2_init.steps_completed` tracks partial state so `--repair` can resume.

### 3. Manifest corruption / missing host field

Dispatcher detects missing/malformed `host` field and exits with: "manifest.json missing `host` field. Run `scripts/check-gate.sh --backfill-host` to infer from git remote and repair." The `--backfill-host` subcommand inspects `git remote get-url origin`, infers host from URL pattern, confirms with user, writes to manifest. No silent auto-repair.

### 4. Backstop verification fail

Hard block on phase transition. Print **specific** failing rule, not generic error:
- "main branch allows force-push (should be disabled)"
- "required_approving_review_count is 0 (org mode requires 1)"
- "no status checks enforced (org mode requires CI status check)"

Offer `scripts/check-gate.sh --repair` to re-run `host_configure_protection`.

### 5. Host API transient failures

Retry once automatically after 10s (reuses `scripts/lib/helpers.sh:run_with_timeout`). On second failure: exit with command to retry + host status page hint. Never falls back to manual attestation — outages resolve, and silent fallback normalizes the outage.

## Testing

### Layer 1 — Driver unit tests (mocked)

`tests/host-drivers/<host>.test.sh`. Always runs. Uses `PATH`-prepended fixture directory to shim `gh`, `glab`, `curl` with recorded responses. Covers every contract function × every error category. ~60-80 cases per driver. Asserts exit codes and stderr messages, not JSON-parsing correctness (jq's job).

### Layer 2 — Driver integration tests (real APIs, opt-in)

Same files, guarded by `HOST_INTEGRATION_TESTS=1`. Creates throwaway repos with unique suffixes, runs full contract end-to-end, cleans up via trap. Requires test credentials in env (`GH_TEST_TOKEN`, `GLAB_TEST_TOKEN`, `BB_TEST_USER` + `BB_TEST_APP_PASSWORD`). Opt-in because expensive; catches real API drift.

### Layer 3 — End-to-end init tests

Extension of `tests/full-project-test-suite.sh`. Scaffolds a project with each first-class host + `other`, verifies manifest host field, correct CI template location per host, `process-state.json` reflects repo steps, `other` gets attestation record. Uses Layer 1's `PATH` shim — no network.

### Layer 4 — Backstop regression tests

Extension of `tests/known-bugs-test-suite.sh`. Three cases:
1. Lancache-pattern: project mid-Phase-1 with no remote → Phase 1→2 blocked.
2. Manifest-missing-host: legacy manifest → backfill prompt, no silent default.
3. Protection drift: mock API returns "force-push enabled" → Phase 1→2 blocked with specific rule message.

### Layer 5 — Upgrade-path test

Extension of `tests/upgrade-path-tests.sh`. Simulates project with old flat CI layout, runs `upgrade-project.sh`, asserts: existing `.github/workflows/ci.yml` preserved, manifest `host: "github"` backfilled from remote URL, `phase2_init` structure initialized but NOT marked verified, printed note recommends `scripts/check-gate.sh --preflight` before next gate crossing.

### Not tested

- Host-level protection-rule edge cases (host API contract; integration tests catch drift).
- Message "helpfulness" (review concern, not test concern).
- Performance of API calls (inherently network-bound; testing is noise).

## Open Questions

None. All decisions captured in the Decisions table.

## Related

- Prior design: `docs/superpowers/specs/2026-04-08-process-enforcement-design.md` (introduced `phase2_init` gate; this spec repositions the gate and strengthens its checks)
- Prior design: `docs/superpowers/specs/2026-04-08-phase-audit-design.md` (phase-gate audit infrastructure; backstop gate writes into same `APPROVAL_LOG.md`)
- Memory entry: `~/.claude/projects/-Users-karl-Documents-Claude-Projects-solo-orchestrator/memory/project_current_state.md`

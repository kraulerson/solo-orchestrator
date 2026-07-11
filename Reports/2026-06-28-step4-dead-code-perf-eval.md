# Step 4: Dead-Code & Performance Evaluation

**Date:** 2026-06-28
**Scope:** solo-orchestrator repository (scripts/, tests/, docs/, templates/, evaluation-prompts/)
**Inputs:** 4 read-only scout scans (dead-code:scripts, dead-code:artifacts, perf:startup, perf:test-suite)
**Status:** Synthesis — no changes applied. Decisions deferred to the user.

---

## 1. Executive Summary

| Category | Findings | Magnitude |
|---|---|---|
| Dead code — scripts | 1 unused function, 1 dead local var, 0 unreachable branches | ~12 LOC removable; near-zero blast radius |
| Dead code — artifacts | 3 fully-orphaned templates/UAT fixtures, 7-file v2-concepts dir, 9 orphan superpowers plan docs, 14 dead doc anchors, 1 removed-feature residue (`cli` platform), 3 un-invoked aggregator test suites | ~25 orphan files, ~14 broken doc links, 1 stale platform arm |
| Performance — startup | All three lightweight scripts already sub-second (init.sh `--validate-only` ≈130 ms, verify-install.sh `--check-only` ≈150 ms p50 / 232 ms p95, check-gate.sh `--preflight` ≈60 ms) | No script exceeds the "slowness finding" threshold (>2 min). Structural wins are 30–80 ms per invocation (mostly fork-reduction). Achievable savings: ~40–50 % per script on the warm path. |
| Performance — test suite | `full-project-test-suite.sh` >600 s (timed out), `edge-case-test-suite.sh` ~128 s, `host-drivers/run-all.sh` ~8 s, `known-bugs-test-suite.sh` ~2 s. No unified top-level orchestrator. | Resolver matrix (TEST 1: 81 cells serial) and `run_bounded` wrappers (38 hits in edge-case suite) dominate. Realistic 40–60 % reduction in `full-project-test-suite.sh` runtime via parallelism + fixture sharing. |

**Headline:** the framework has a small amount of script-side dead code and a moderate amount of doc-side artifact rot (mostly orphan superpowers plans and dead anchors), but the highest-ROI work is on the **test suite runtime** — the resolver matrix walk in `full-project-test-suite.sh` is the single biggest time-sink in the project and is structurally amenable to parallelization and fixture sharing.

---

## 2. Dead Code — Scripts

Source: dead-code:scripts scout. Methodology: 2-pass repo-wide reference counting for all 242 function defs across 44 shell files, plus a per-function local-variable scan. Conservative (false negatives preferred over false positives) — every low-call-count function was manually disambiguated against dispatch tables, sourced-lib contracts, and test fixtures.

### 2.1 Unused functions (1 finding)

| # | File:line | Name | Evidence |
|---|---|---|---|
| 1 | `scripts/lib/phase2-state.sh:23` | `_phase2_state_file()` | `grep -rEn --include='*.sh' --include='*.md' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.toml' --include='*.txt' --include='*.template' --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='.claude' --exclude-dir='scratchpad' --exclude-dir='Reports' '\b_phase2_state_file\b' .` → 1 result (only the definition). `_record_phase2_step` (the only intended caller) inlines `"$root/.claude/process-state.json"` at line 37 instead. |

**Recommended option:** delete-now.
**Risk:** low. Sibling helper `_phase2_state_repo_root()` IS used; orphan is isolated to a single helper inside a sourced lib.

### 2.2 Dead local variables (1 finding)

| # | File:line | Name | Evidence |
|---|---|---|---|
| 1 | `scripts/check-versions.sh:114` | `tool_install_json` | `grep -n 'tool_install_json' scripts/check-versions.sh` → 1 hit (the declaration). Declared from `$3` but never read in the function body. Caller at `scripts/check-versions.sh:358` passes `$INSTALL_OBJ`. |

**Recommended option:** delete-now (local + corresponding caller arg).
**Risk:** low. Removing only the local is zero-risk; removing the arg from the caller is a narrowly-scoped cleanup.

### 2.3 Unreachable branches

**0 findings.** Audited all `case`/`if`/`elif`/`else` constructs in `scripts/`. No `if false`, no `elif` after total-coverage `return`/`exit`, no dead `case` arms. `*) error/usage` fall-through arms (intake-wizard.sh, process-checklist.sh, pending-approval.sh, check-gate.sh) are intentionally reachable for unknown-command handling.

### 2.4 Notes on scope

- `run_section_N`, `host_*`, `cmd_*`, `_is_*` families all confirmed reachable via dispatch tables: `intake-wizard.sh:1545-1559` (`run_section_$section`), `process-checklist.sh:1137-1151` (`case "$ACTION"`), `pending-approval.sh:354-362`, `check-gate.sh:308-314`.
- Transitive dead code (funcs only reachable via other dead funcs), per-test-fixture unused vars, and dead `export` vars were out of scope.

---

## 3. Dead Code — Artifacts

Source: dead-code:artifacts scout. Methodology: grep'd every candidate basename across `*.sh`, `*.md`, `*.tmpl`, `*.json`, `*.html`, `*.yml` (excluding `.claude/`, `.git/`, `scratchpad/`, `Reports/`); 0 external hits → confirmed orphan. Doc-anchor scan done via Python: parsed `[label](target)` links, resolved relative paths, computed GitHub-flavored slugs for `#anchor` checks.

### 3.1 Orphan files (16 findings)

#### Templates (2)

| Path | Evidence | Option | Risk |
|---|---|---|---|
| `templates/generated/handoff-test-results.tmpl` | `grep -rE 'handoff-test-results' ...` → 0 hits. Companion `handoff.tmpl` is used (148 hits). | delete-now | low |
| `templates/generated/migration-plan.tmpl` | `grep -rE 'migration-plan' ...` → only self-reference. Template body cites a nonexistent `docs/migration-plan.md`. | delete-now | low |

#### Docs (10)

| Path | Evidence | Option | Risk |
|---|---|---|---|
| `evaluation-prompts/v2-concepts/` (7 files) | `grep -rE 'v2-concepts' ...` → 0 hits. Parking-lot for not-yet-implemented v2 ideas (auto-discovery-extensibility, in-flight-project-ingestion, language-platform-filtering, mcp-server-architecture, platform-pipeline-intake, post-mvp-feature-development, principal-engineer-guardian). | investigate (preserve as roadmap?) or move under `docs/roadmap/` | low-medium (loss of ideas if deleted outright) |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions-round2.md` | 0 external refs. Stale link targets. | delete-now | low |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions.md` | 0 external refs. | delete-now | low |
| `docs/superpowers/plans/2026-04-03-tool-installation-matrix.md` | 0 external refs (design sibling has 1 backlink). | delete-now | low |
| `docs/superpowers/plans/2026-04-03-uat-bug-tracking.md` | 0 external refs (design sibling has 1 backlink). | delete-now | low |
| `docs/superpowers/plans/2026-04-03-verify-install.md` | 0 external refs (design sibling has 1 backlink). | delete-now | low |
| `docs/superpowers/plans/2026-04-04-check-versions.md` | 0 external refs (design sibling has 1 backlink). | delete-now | low |
| `docs/superpowers/plans/2026-04-08-documentation-remediation.md` | 0 external refs. | delete-now | low |
| `docs/superpowers/plans/2026-04-08-phase-audit.md` | 0 external refs. | delete-now | low |
| `docs/superpowers/plans/2026-04-08-process-enforcement.md` | 0 external refs. | delete-now | low |

#### Tests — un-invoked aggregators (3)

| Path | Evidence | Option | Risk |
|---|---|---|---|
| `tests/edge-case-test-suite.sh` | Not invoked by `tests/full-project-test-suite.sh`, `tests/host-drivers/run-all.sh`, or `.github/workflows/lint.yml`. Successors: `tests/edge-cases-pre-init.sh`, `edge-cases-scripts.sh`, `edge-cases-upgrade-input.sh`. | refactor (consolidate cases into successors) or keep-and-mark | medium (it DOES run real tests — see §5; deletion loses coverage) |
| `tests/known-bugs-test-suite.sh` | Not invoked anywhere. Per-bug `test-*.sh` files registered in `solo-orchestrator-backlog.md` are the convention. | refactor (port any cases not already in standalone test-*.sh; then delete) | medium |
| `tests/upgrade-path-tests.sh` | Not invoked. Successor coverage: `tests/test-upgrade-paths.sh`, `test-upgrade-bl030-backfill.sh`, `test-upgrade-interruption.sh`, etc. | refactor (verify successor coverage, then delete) | medium |

**Process question for the user** (raised by the scout): 73 of 77 `tests/test-*.sh` files are NOT wired into any aggregator runner. `solo-orchestrator-backlog.md` documents them as "regression coverage," but the framework lacks a runner that exercises all of them. This is a deliberate policy choice (per-bug standalone tests, registered in the backlog) but it leaves a gap: a new contributor running `tests/full-project-test-suite.sh` exercises only 4 of the 77 test-*.sh files (`test-counter-antipattern`, `test-backlog-references`, `test-phase-gate-backstop-attestation`, `test-platform-mobile-mcp-docs`). Decide the policy before mass-listing the un-invoked tests as orphans.

### 3.2 Dead doc anchors (14 findings)

All point at `cli-setup-addendum.md` (relocated/removed) or other moved-away targets.

| From | Broken target |
|---|---|
| `docs/user-guide.md` | `cli-setup-addendum.md#6-claudemd` |
| `docs/user-guide.md` | `cli-setup-addendum.md#1-superpowers` |
| `docs/user-guide.md` | `cli-setup-addendum.md#4-context7` |
| `docs/user-guide.md` | `cli-setup-addendum.md#5-qdrant` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions.md` | `cli-setup-addendum.md#6-claudemd` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions.md` | `cli-setup-addendum.md#1-superpowers` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions.md` | `cli-setup-addendum.md#4-context7` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions.md` | `cli-setup-addendum.md#5-qdrant` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions.md` | `builders-guide.md` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions-round2.md` | `security-scan-guide.md` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions-round2.md` | `../templates/project-intake.md` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions-round2.md` | `platform-modules/` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions-round2.md` | `cli-setup-addendum.md` |
| `docs/superpowers/plans/2026-04-02-technical-review-resolutions-round2.md` | `cli-setup-addendum.md#6-claudemd` |

**Action:** the 4 `docs/user-guide.md` anchors should be fixed in place (user-guide is a live doc). The 10 in `docs/superpowers/plans/2026-04-02-*` files are inside the orphan plan docs — if you accept the §3.1 delete recommendations, these vanish naturally.

**Risk:** low for user-guide fixes (one search-replace, but verify the new target). Zero for plan-doc anchors (they go away with the plans).

### 3.3 Removed-feature residue (3 findings)

| Feature | Where | Note | Option | Risk |
|---|---|---|---|---|
| `cli` as a first-class platform (retired in favor of `mcp_server`) | `scripts/validate.sh:65` | `cli)     print_info "No platform module for CLI (Builder's Guide works standalone)" ;;` survives even though `init.sh:64` and `init.sh:3097-3107` only accept `desktop\|mobile\|web\|mcp_server`. Companion files `templates/intake-suggestions/cli.json` and `templates/pipelines/release/cli.yml` were deleted (commit 9721874). `tests/test-intake-wizard-fixes.sh` asserts the `cli.json` removal as drift prevention. | delete-now (or replace with `mcp_server)` arm pointing at `docs/platform-modules/mcp_server.md`) | low |
| Bare filename links in orphan plans | `docs/superpowers/plans/2026-04-02-technical-review-resolutions*.md` (multiple sites) | Plans authored when target docs were siblings; now live in `docs/`. Bare links like `[Builder's Guide](builders-guide.md)` don't resolve. | delete-now (delete the plans per §3.1 — fixing the links is wasted work) | low |
| `docs/migration-plan.md` cross-reference inside unused template | `templates/generated/migration-plan.tmpl` | Template body cites `docs/migration-plan.md` which doesn't exist; template itself is orphan (per §3.1). | delete-now (delete the template) | low |

---

## 4. Performance — Startup

Source: perf:startup scout. Methodology: 5 runs per script under `/usr/bin/time -p`; median + p95 (linear interp); 1 run under `bash -x` parsed in Python to tally subprocess invocations and inner-loop work. All three scripts already sub-second on a warm Mac — none meet the "finding" threshold of >2 min slowness. Reported as hot-path inventory + cheap structural wins.

### 4.1 `init.sh --non-interactive --validate-only`

- **Wall-clock:** median **0.130 s**, p95 0.130 s
- **Invocation:** from empty scratch cwd with valid `--track standard`

| # | Site | Why hot | Fix hint |
|---|---|---|---|
| 1 | `init.sh:69` `get_available_platforms()` | Globs `docs/platform-modules/*.md` AND `templates/pipelines/release/github/*.yml` on every call. ≈18 `basename` subshells in the validate-only trace. Walked again at L3296+ for unrelated reasons. | Memoize via `_AVAILABLE_PLATFORMS_CACHE`; replace `basename "$f" .md` with `${f##*/}` / `${name%.md}` |
| 2 | `init.sh:3296` language-vs-platform CI yml walk | Re-globs `templates/pipelines/ci/github/*.yml`; `head -1` per file (~10 subshells) | `read -r _marker < "$_ci_yml"` instead of `head -1` |
| 3 | `scripts/lib/helpers.sh` (sourced at `init.sh:58`) | ~80 ms before `main()` even runs; 13× `tr` calls + color/ANSI setup | Gate color setup on `[ -t 1 ]` (already partial at L39); split into `helpers-core.sh` + `helpers-full.sh` |
| 4 | `init.sh:3393-3433` final jq object build | Single jq with ~15 `--arg`/`--argjson`; ~10–15 ms cold | Acceptable; only optimize if jq cold-start dominates measurably |
| 5 | `init.sh:guard_not_in_framework` + 52 git invocations | Many run even in validate-only path (e.g., `guard_not_in_framework` runs before the validate-only short-circuit at L3570) | Hoist `if [ "$VALIDATE_ONLY" != true ]` ahead of `guard_not_in_framework` (mirror what's done for `DRY_RUN` at L3549) |

### 4.2 `scripts/verify-install.sh --check-only`

- **Wall-clock:** median **0.150 s**, p95 **0.232 s** (55 % spread on 5 samples — likely jq cold-cache jitter)
- **Invocation:** from empty scratch cwd (no project present)

| # | Site | Why hot | Fix hint |
|---|---|---|---|
| 1 | `verify-install.sh:1297` `for _i in $(seq 0 19); do eval "fix_tool_install_${_i}() { ... }"; done` | Synthesizes 20 wrapper functions via `eval` on every invocation — including `--check-only`, which never calls any `fix_*` | Gate behind `if [ "$MODE" != "check-only" ]`; or replace with a single dispatch `fix_tool_install_N() { fix_tool_install "${FUNCNAME##*_}"; }` |
| 2 | `verify-install.sh:138` `has_source()` called ~39× | `[ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ]` — directory test is a syscall; `SOURCE_DIR` never changes after `detect_source_dir` | Cache once in `HAS_SOURCE=1/0`; replace calls with `[ "$HAS_SOURCE" = 1 ]` |
| 3 | `verify-install.sh:171` framework_docs loop + L286 scripts loop + register_* loops | 42 MANUAL[]/FIXABLE[] iterations + 108 empty-string tests + ~29 basename calls (from `${doc%.md}` via basename) | (a) Factor doc/script lists into one assoc array + one loop; (b) replace `basename` with parameter expansion |
| 4 | 7 jq + 27 git invocations | jq ~10–15 ms cold × 7 ≈ 85 ms — explains most of the p50/p95 spread | Bundle multi-field jq reads of `.claude/manifest.json` into one pass: `jq -r '{platform, language, track, host}' ...` then `eval` or `read` |
| 5 | p95/p50 spread (0.232/0.150 = 55 %) | Two of five runs took 40–60 % longer — macOS file-cache + jq cold-start fault in pages | Not a code fix; note that cold-cache CI will see the p95 as the norm |

### 4.3 `scripts/check-gate.sh --preflight`

- **Wall-clock:** median **0.060 s**, p95 0.068 s
- **Invocation:** synthetic git-repo fixture with `.claude/manifest.json {host:github, mode:personal}` and empty `process-state.json` (forces the heavier `host_load_driver` + `host_verify_protection` path, not the `github_free_tier` short-circuit at L77)

| # | Site | Why hot | Fix hint |
|---|---|---|---|
| 1 | `check-gate.sh:64` `cmd_preflight` + `scripts/lib/host.sh host_load_driver` | Only 70 trace lines total. 3 jq calls + 11 git calls (mostly `git rev-parse --show-toplevel` called twice — once in `_host_repo_root` from `host_read_from_manifest`, once again from `host_load_driver`). 1 basename, 1 dirname. | Cache `_host_repo_root` in `_HOST_REPO_ROOT_CACHE`; bundle the 3 jq calls into one pass |
| 2 | `check-gate.sh:14` `source $SCRIPT_DIR/lib/helpers.sh` | helpers.sh load is ~60 ms — essentially the entire runtime of a 60 ms script | Split helpers.sh into `helpers-core.sh` (print/log) + `helpers-full.sh` (color, rotation, prompts). Benefits **all** short-lived scripts: `check-changelog`, `check-versions`, `check-updates`, `check-session-state`, etc. |

### 4.4 Cross-cutting observation

The helpers.sh split (§4.3 hot path #2) is the single highest-leverage perf change in the project — it benefits every short-lived CLI entry point, not just `check-gate.sh`. Expected savings: 30–40 ms per script invocation across ~15 callers.

---

## 5. Performance — Test Suite

Source: perf:test-suite scout. Methodology: `time { ... }` around each entrypoint; structural reads of full-project-test-suite.sh L140-740 + edge-case-test-suite.sh L160-220; grep for `git init`, `sleep`, `init.sh`, `curl`, `run_bounded` to identify slow-test causes. Several suites ran as concurrent background jobs while a Wave-4 workflow was active on the host, so per-suite numbers are upper bounds, not serial baselines.

### 5.1 Top-level state

**There is no unified `tests/run-all.sh` orchestrator.** `bash tests/host-drivers/run-all.sh` covers only the 9 host-driver suites. The other entrypoints — `full-project-test-suite.sh`, `edge-case-test-suite.sh`, `edge-cases-pre-init.sh`, `edge-cases-scripts.sh`, `edge-cases-upgrade-input.sh`, `upgrade-path-tests.sh`, `known-bugs-test-suite.sh` — must each be invoked individually. Plus ~70 standalone `tests/test-*.sh` files registered in the backlog, only 4 of which are wired into any aggregator.

### 5.2 Per-suite ranking

**Total measured runtime: ~748 s (note: dominated by the timed-out full-project-test-suite.sh; actual serial time would be higher).**

| Rank | Suite | Runtime (s) | Tests | Avg (s) |
|---|---|---|---|---|
| 1 | `tests/full-project-test-suite.sh` | **>600 (timed out)** | ~200 | ~3.0 |
| 2 | `tests/edge-case-test-suite.sh` | 127.6 | 28 | 4.56 |
| 3 | `tests/upgrade-path-tests.sh` | ~10 | 27 | 0.37 |
| 4 | `tests/host-drivers/run-all.sh` | 8.31 | 9 | 0.92 |
| 5 | `tests/known-bugs-test-suite.sh` | 1.93 | 22 | 0.088 |
| 6 | `tests/edge-cases-pre-init.sh` | did-not-complete | 11 | — |
| 7 | `tests/edge-cases-scripts.sh` | did-not-complete | 20 | — |
| 8 | `tests/edge-cases-upgrade-input.sh` | did-not-complete | 19 | — |

### 5.3 Slow-test breakdown

#### `full-project-test-suite.sh` (>600 s — TIMED OUT)

| Test | Est. seconds | Cause |
|---|---|---|
| TEST 1: Resolver Matrix — 81 combinations (3 platforms × 9 languages × 3 tracks) | ~240 | Each cell forks `bash scripts/resolve-tools.sh` which version-probes every tool in `templates/tool-matrix/*.json`. **No parallelism, no shared resolver process.** Got through 21/81 in the first ~3.5 min. |
| TEST 4: Simulated Project Structure Verification (7 combos) | ~60 | Per combo: `mkdir -p` of 9 dirs, ~12 `cp`, fresh `(cd $project_dir && git init -q)`, jq writes to phase-state.json + tool-preferences.json, plus a **second** `resolve-tools.sh` for the project-local copy |
| TEST 7: Dry-Run Mode (real init.sh invocation) | ~30 | Pipes 8-line input to `bash init.sh --dry-run` — full interactive scaffolder including all resolver passes |
| TEST 0/0b/0c/0d/0e: lint + behavior-test pre-checks | ~15 | Each calls `bash scripts/lint-*.sh` + `bash tests/test-lint-*.sh` — **also runnable standalone, so this is pure duplication when both entrypoints are exercised** |
| TEST 6: detection sweep | ~10 | 8 separate `echo $detect_output | jq` passes |

**Redundancy notes:**
- TEST 0 block re-runs the same standalone `tests/test-lint-*.sh` and `tests/test-platform-mobile-mcp-docs.sh` files.
- TEST 1's 81 cells could share a single resolver process or run via `xargs -P` parallel.
- TEST 4's 7 simulated projects all share an identical scaffold shape — `cp`/`mkdir`/`git init`/scripts-cp could be done once into a fixture template; per-combo runs would only diff `phase-state.json` + `tool-preferences.json` + the CI workflow file.
- TEST 4 invokes `resolve-tools.sh` **twice per combo** — could be collapsed.

#### `edge-case-test-suite.sh` (~128 s)

| Test | Seconds | Cause |
|---|---|---|
| T2.2: hanging custom `check_command` (sleep 60 in tool-prefs) | 11 | Intentional — validates the 2026-06-26 resolve-tools.sh timeout fix. `run_bounded 30` with HangTool injection. |
| T7.1: hanging `version_command` | 11 | Same pattern in a planted matrix file with `version_command: sleep 60` |
| All T1–T6 resolver-shape tests | ~60 | 38 instances of `run_bounded N bash scripts/resolve-tools.sh ...` — each pays the full resolver cold-start + version-probe fan-out |
| T3.x git-host scaffolding | ~5 | Fresh `git init` + `git config user.email/user.name` per case |

**Redundancy:** the 38 `run_bounded` wrappers all pay the resolver cold-start. A fixture that runs the resolver once with a representative matrix and asserts shape via jq would cut most of the wall-clock. Only T2.2 and T7.1 genuinely need ~10 s.

#### `upgrade-path-tests.sh` (~10 s)

Walks a 27-cell subset of the same 81-cell resolver matrix that `full-project-test-suite.sh` TEST 1 walks. **Direct overlap.** A shared matrix-walk helper producing both shape assertions and monotonicity assertions in one pass would let the two suites share work.

#### `host-drivers/run-all.sh` (~8 s)

Cheap, well-isolated. Three e2e-init-*.test.sh (github/gitlab/bitbucket) share substantial fixture-prep code that could be factored, but wall-clock cost is already low. **No action recommended.**

#### `known-bugs-test-suite.sh` (~2 s)

Model suite — fast, no slow tests. Mostly grep/jq assertions over checked-in fixtures + `bash -n` syntax checks; no `init.sh` invocation; no fresh `git init` per test. **Use as a template for refactoring the other suites.**

### 5.4 Cross-cutting test-suite observations

1. **The 81-cell resolver matrix in TEST 1 is the single largest time-sink in the entire project.** It is serial; each cell forks `bash`; each invocation reloads `templates/tool-matrix/*.json` from disk. Parallelizing via `xargs -P 8` or batching into a single Python/jq pass would cut TEST 1 from ~240 s to ~30–60 s.
2. **Fresh `git init` is expensive at scale.** TEST 4 does it 7×, edge-case-test-suite does it per T3.x case, edge-cases-pre-init and edge-cases-scripts do it per section. A fixture template directory copied with `cp -R` is ~10× faster than `git init`.
3. **`run_bounded N bash <script>` is the resolver-cold-start tax.** Most edge-case tests assert resolver *shape*, not timing — a single resolver invocation with a curated matrix would replace 38 calls.
4. **TEST 0 in full-project-test-suite duplicates standalone test-*.sh files.** Either remove the TEST 0 block (and document that contributors run both entrypoints) or remove the standalone files. Don't pay the cost twice.

---

## 6. Reconciliation Options Matrix

| Item | Delete now | Keep + mark | Refactor |
|---|---|---|---|
| `_phase2_state_file` (scripts/lib/phase2-state.sh:23) | **Effort: 1 line. Risk: low.** Zero callers. | Add `# kept for symmetry with _phase2_state_repo_root` comment. Effort: 1 line. | Inline-call from `_record_phase2_step` to use the helper. Effort: 1 line, slightly better. Risk: low. |
| `tool_install_json` dead local (scripts/check-versions.sh:114) | **Effort: 1 line. Risk: low.** Delete the local. | n/a | Also drop the arg from caller at L358. Effort: 2 lines. Slightly riskier (touches caller). |
| `templates/generated/handoff-test-results.tmpl` | **Effort: 1 file. Risk: low.** | n/a | n/a |
| `templates/generated/migration-plan.tmpl` | **Effort: 1 file. Risk: low.** Also kills the broken `docs/migration-plan.md` reference. | n/a | Write the missing `docs/migration-plan.md` and wire the template into a generator. Effort: high. Only if migration plans are an actual feature. |
| `evaluation-prompts/v2-concepts/` (7 files) | Effort: low. **Risk: medium — loses brainstorming ideas.** | Move to `docs/roadmap/v2-concepts/` with a README. Effort: low. **Recommended.** | Promote one or two concepts into design docs (mcp-server-architecture already has a shipped sibling). Effort: high. |
| 9 orphan superpowers plan docs | **Effort: 9 files. Risk: low.** Plans for shipped features; design siblings retain history. | Add a `STATUS: SHIPPED` header to each. Effort: low. | Consolidate into a single `docs/superpowers/HISTORY.md` rollup. Effort: medium. |
| 4 dead anchors in `docs/user-guide.md` | n/a (the file is live) | Mark as `<!-- TODO: fix link -->`. Effort: trivial. **Not recommended.** | **Fix the anchors. Effort: low. Risk: low. Recommended.** |
| `cli)` arm in scripts/validate.sh:65 | **Effort: 1 line. Risk: low.** | Convert to `cli)` → error message + exit. Effort: low. | Replace with `mcp_server)` arm pointing at `docs/platform-modules/mcp_server.md`. Effort: low. **Recommended — closes the loop on the cli→mcp_server migration.** |
| `tests/edge-case-test-suite.sh` | Effort: 1 file. **Risk: medium — it runs real tests.** | Add a comment "consolidate into edge-cases-*.sh successors then delete." Effort: trivial. | **Audit which cases are not in successors; port missing ones; then delete. Effort: medium. Risk: low. Recommended.** |
| `tests/known-bugs-test-suite.sh` | Effort: 1 file. **Risk: medium — predates the per-bug test-*.sh convention.** | Document as historical. Effort: trivial. | **Verify each case is covered by a standalone test-*.sh; then delete. Effort: medium. Risk: low.** |
| `tests/upgrade-path-tests.sh` | Effort: 1 file. **Risk: medium.** | Document. Effort: trivial. | **Merge the 27-cell monotonicity assertions into a single matrix-walk helper shared with full-project-test-suite.sh TEST 1.** Effort: medium. Risk: low. **Recommended.** |
| helpers.sh split into core + full | n/a | n/a | **Effort: medium (one new file + audit ~15 callers). Risk: medium (every short-lived script depends on this). Highest-leverage perf change.** |
| `init.sh` `get_available_platforms` memoization | n/a | n/a | **Effort: ~5 lines. Risk: low.** Cache + parameter expansion replace `basename` forks. |
| `verify-install.sh` `eval` factory removal | n/a | n/a | **Effort: ~10 lines. Risk: low — `--check-only` path doesn't use the wrappers.** Gate the `for _i in $(seq 0 19)` block. |
| TEST 1 resolver matrix parallelization | n/a | n/a | **Effort: medium (`xargs -P 8` or a single batched runner). Risk: low — output is per-cell and aggregated. Highest-ROI test-suite change.** |
| TEST 4 simulation fixture sharing | n/a | n/a | Effort: medium. Risk: low. Cuts ~30–40 s off `full-project-test-suite.sh`. |

---

## 7. Top 10 Recommendations (Ranked by ROI)

| # | Recommendation | Category | Option | Effort | Impact | Risk |
|---|---|---|---|---|---|---|
| 1 | **Parallelize TEST 1 resolver matrix** (81 cells via `xargs -P 8` or single batched runner) in `tests/full-project-test-suite.sh` | performance | refactor | medium | Cuts ~180 s off the longest test suite (>600 s → ~420 s); highest single-change wall-clock saving in the project | low |
| 2 | **Split `scripts/lib/helpers.sh` into `helpers-core.sh` + `helpers-full.sh`** | performance | refactor | medium | 30–40 ms per invocation × ~15 short-lived script callers (check-gate, validate, check-versions, check-updates, check-session-state, check-changelog, etc.) — compounds across the whole CLI surface | medium (every short-lived script depends on helpers.sh; needs caller audit) |
| 3 | **Remove the `cli)` arm in `scripts/validate.sh:65`** (and replace with `mcp_server)` arm pointing at `docs/platform-modules/mcp_server.md`) | dead-code | refactor | low | Closes the loop on the cli→mcp_server migration; eliminates the last surviving recognition of the retired `cli` platform value | low |
| 4 | **Fix the 4 dead anchors in `docs/user-guide.md`** (`cli-setup-addendum.md#...`) | dead-code | refactor | low | User-guide is the front door — broken links erode trust faster than any other doc | low |
| 5 | **Delete the 9 orphan superpowers plan docs in `docs/superpowers/plans/2026-04-*`** (design siblings retain history) | dead-code | delete-now | low | Removes ~10 broken-link doc anchors as a side effect; reduces grep noise | low |
| 6 | **Gate the `eval` factory in `verify-install.sh:1297` behind `[ "$MODE" != "check-only" ]`** | performance | refactor | low | Removes 20 `eval` calls + 1 `seq` subshell per check-only invocation; ~5–10 ms saving | low |
| 7 | **Memoize `get_available_platforms()` in `init.sh:69` + replace `basename` with parameter expansion** | performance | refactor | low | Eliminates ~18 `basename` forks; ~10–15 ms per `init.sh` invocation; benefits every interactive run | low |
| 8 | **Audit & retire `tests/edge-case-test-suite.sh`, `known-bugs-test-suite.sh`, `upgrade-path-tests.sh`** (verify successor coverage in `edge-cases-*.sh` and standalone `test-*.sh` files, port any gaps, then delete) | dead-code | refactor | medium | Removes 3 un-invoked aggregators; clarifies the test-runner story (currently no unified orchestrator); enables a future `tests/run-all.sh` without conflict | medium (real tests live in these files — needs coverage check) |
| 9 | **Share fixture setup across TEST 4's 7 simulated projects in `full-project-test-suite.sh`** (copy a fixture template once, mutate only the per-combo diff) | performance | refactor | medium | ~30–40 s saving on `full-project-test-suite.sh`; also reduces 7 fresh `git init` calls | low |
| 10 | **Delete `_phase2_state_file` (scripts/lib/phase2-state.sh:23) and the `tool_install_json` dead local (scripts/check-versions.sh:114)** | dead-code | delete-now | trivial | Tiny cleanup; baseline-good signal that the dead-code scan was acted on | low |

**Honorable mention (process):** decide the policy for the ~70 standalone `tests/test-*.sh` files that no aggregator invokes. Either (a) wire them into a top-level `tests/run-all.sh`, or (b) explicitly document the per-bug convention in `CONTRIBUTING.md` so new contributors understand they're regression markers, not active suites. Without the decision, the test-suite has structural ambiguity that no amount of timing optimization resolves.

---

## 8. What We Deliberately Did NOT Scan

- **Generated/vendored content:** `.claude/`, `.git/`, `node_modules/`, `scratchpad/`, `Reports/` (synthesizer output included) — these are session-scoped or third-party.
- **Transitive dead code:** functions reachable only via other dead functions. The scout's 2-pass analysis flags first-order dead funcs only.
- **Per-test-file unused fixtures and variables:** scout's local-var scan covered all `^\s*local <var>=` declarations in `scripts/`; the same analysis was not extended to `tests/` (would multiply the workload by ~70 files).
- **Dead `export` variables:** exports propagate to subprocesses, making reachability ambiguous via static grep. Out of scope.
- **`init.sh` interactive-path performance:** scout measured only `--validate-only`. Interactive runs (`bash init.sh` without flags) are user-paced; perf is bound by user input, not script logic.
- **CI runner timing:** all measurements taken on Karl's Mac (Darwin 25.4). CI cold-disk runs are estimated at 2–4× slower based on jq cold-start; not validated.
- **Concurrent-load contamination correction:** the test-suite scout flagged that 5 of 8 suites ran as background jobs alongside a Wave-4 workflow. Per-suite numbers are upper bounds, not serial baselines. A clean serial re-run would refine the ranking but not change the order or the dominant time-sinks.
- **Dead JSON/YAML keys in `templates/tool-matrix/*.json`, `templates/pipelines/**/*.yml`, etc.** — would require a schema-aware analyzer; out of scope.
- **Removed-feature residue beyond the `cli` platform retirement:** scout searched `git log --since='90 days ago' --diff-filter=D`; older feature removals were not surfaced.

---

## Appendix A: Scout Methodologies

### Dead-code: scripts
1. Enumerated 242 function defs across 44 `.sh` files via `grep -HnE '^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\s*\)\s*\{|^function\s+[a-zA-Z_][a-zA-Z0-9_]*'`.
2. Per function: `grep -rEn --include='*.sh' --include='*.md' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.toml' --include='*.txt' --include='*.template' --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='.claude' --exclude-dir='scratchpad' --exclude-dir='Reports' '\b<NAME>\b' .`
3. Manually disambiguated every function with reference count ≤ 3 against dispatch-table callers, sourced-lib callers, test-only callers, and doc/spec references.
4. Verified `_phase2_state_file` by inspecting `init.sh` + `scripts/check-gate.sh` (the two files that source `phase2-state.sh`).
5. Local-var scan: Python script walked every `^\s*local <var>=` declaration, searched function body for `\b<var>\b` (bareword, catches `(( var ))` and `[[ ... var ... ]]`).
6. Unreachable-branch scan: grep for `if false`, `if true`, `[ 0 -eq 1 ]`; visual scan of `elif` chains and `case` dispatchers.

### Dead-code: artifacts
1. Enumerated all candidates under `templates/`, `docs/`, `tests/`, `scripts/`, `evaluation-prompts/`.
2. Per basename: `grep -rE '<basename>' --include='*.sh' --include='*.md' --include='*.tmpl' --include='*.json' --include='*.html' --include='*.yml' --exclude-dir=.claude --exclude-dir=.git --exclude-dir=scratchpad --exclude-dir=Reports .` minus self-references; 0 external hits → confirmed orphan.
3. Test-runner registration: read `tests/full-project-test-suite.sh` (only 4 individual test-*.sh invocations), `tests/host-drivers/run-all.sh` (globs `*.test.sh` + `*.selftest.sh`), `.github/workflows/lint.yml` (4 CI lints). CONTRIBUTING.md L113-114 confirms the two canonical run commands.
4. Dead doc anchors: Python parsed every `.md` file's `[label](target)` links; resolved relative paths and checked existence; for `#anchor` targets computed GitHub-flavored slugs for each heading.
5. Removed-feature residue: `git log --since='90 days ago' --diff-filter=D --name-only` surfaced template removals; grepped for surviving `\bcli\b` mentions in active scripts.

### Performance: startup
1. 5 runs per script with `/usr/bin/time -p`; computed median + p95 (linear interpolation between sorted samples).
2. 1 run per script under `bash -x` with stderr → temp file; Python tallied subprocess invocations by name (jq, curl, date, uname, basename, dirname, sed, awk, grep, cut, tr, mktemp, git, command -v) and surfaced most-repeated trace lines.
3. Fixtures: `init.sh` from empty scratch cwd with valid `--track standard`; `verify-install.sh` from empty scratch cwd (correctly drove `--check-only` through all `check_*` functions); `check-gate.sh` from synthetic git-repo fixture at `$SCRATCH/fixture-rich/` with `.claude/manifest.json` (host=github, mode=personal) and emptied process-state.json to bypass the `github_free_tier` early-exit at L77.

### Performance: test suite
1. Read-only scout: identified test entrypoints (8 distinct files); confirmed there is no top-level `tests/run-all.sh`.
2. Timed each suite separately with zsh `time { ... }`.
3. `full-project-test-suite.sh` exceeded the 10-min bash timeout (>600 s); reported as timed-out with a slow-test breakdown rather than re-running.
4. Several suites launched as parallel background jobs and polled; wall-clock includes contention from concurrent jobs and a separate Wave-4 workflow on the same host. Per-suite numbers are upper bounds, not serial baselines.
5. Slow-test causes derived from grep for `git init`, `sleep`, `init.sh`, `curl`, `run_bounded` in each suite plus structural reads of `full-project-test-suite.sh` (L140-740) and `edge-case-test-suite.sh` (L160-220).

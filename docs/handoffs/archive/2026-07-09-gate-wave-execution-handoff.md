# Gate-Wave Execution Handoff — 2026-07-09

**Audience:** the executing agent (Opus 4.8, ultracode effort) for the remaining gate-wave work.
Written to be followable by a junior engineer: every work package names its files with line
anchors, its step-by-step, its tests, and its done-criteria. Verify every line anchor before
editing — the repo moves.

---

## 0.0 Bootstrap — do these before anything else

This repo has **no CLAUDE.md**; this document + the backlog are your instruction set.
In order:

1. Read auto-memory `~/.claude/projects/-Users-karl-Documents-Claude-Projects-solo-orchestrator/memory/MEMORY.md`
   and `project_current_state.md` (durable discipline patterns + Karl's preferences live there).
2. Read the six backlog entries IN FULL in `solo-orchestrator-backlog.md`: BL-082, BL-070,
   BL-072, BL-081, BL-063, BL-025. **The entries govern; this doc summarizes.** They hold
   Karl's approved decisions (Option A/C choices, tier matrices, grandfather clauses) and the
   regression-test lists. If this doc and an entry disagree, stop and reconcile — do not pick
   silently. (Three deliberate exceptions where THIS DOC supersedes stale entry text, all
   flagged inline below: the threat-model file convention in WP-B2, tier-keying vs `track`
   in WP-C, and BL-025's "build FIRST" scheduling — obsolete since BL-073 shipped in PR #146
   without needing it; see WP-D3.)
3. Read this document end-to-end before starting WP-A.
4. Verify state before dispatching anything: `git status` clean on `main`; `gh pr list` empty;
   no `.claude/pending-approval.json`; `gh run list --branch main --limit 3` green;
   `gh api repos/kraulerson/solo-orchestrator/branches/main/protection` returns required
   checks (NOT 404).

**How to run things locally** (macOS dev box, bash 3.2; CI is Ubuntu):
- Single suite: `bash tests/<file>.sh` (self-contained; prints `Results: N passed, M failed`).
- All lints: `for l in scripts/lint-*.sh; do bash "$l" || echo "RED: $l"; done`
- The CI fast lane = the explicit file list in `.github/workflows/tests.yml` (`unit` job) —
  new unit-shaped suites must be added there AND to an aggregator.
- Full suite (~3h — do NOT run casually): `bash tests/full-project-test-suite.sh`; env gates
  `SUITE_SKIP_AGGREGATORS=1` etc. documented in its header. CI full lane is
  `workflow_dispatch`-only: `gh workflow run tests.yml`.
- Commits: Conventional Commits (`feat(scope):` / `fix:` / `test:` / `docs:` / `ci:`), body
  explains why, trailer `Co-Authored-By:` per your harness convention. One PR per work
  package; PR bodies list verification evidence (suite results, mutation proofs).

## 0. Operating agreement (read first, non-negotiable)

1. **No merge on red. Ever.** Branch protection on `main` now requires the `unit` job and all
   8 lint jobs. If a check is red, fix it or stop and ask Karl — never merge past it and never
   disable protection. (This rule exists because PRs #157/#158 were merged with failing checks
   on 2026-07-08 and `main` sat red until PR #159 fixed it.)
2. **TDD + mutation proofs.** Write the failing test first. Every enforcement change carries at
   least one mutation proof: deliberately break the marked load-bearing line (`# BL-NNN-…`
   markers), show the test goes RED, restore, show GREEN. Grep any `test-bl084-*` or
   `test-bl073-*` suite for the house style.
3. **Impl + adversarial verify.** For each work package: implementation agent (worktree
   isolation) + an independent reviewer prompted to REFUTE, rubric
   `block/major_concerns/minor_concerns/approve`. `major_concerns`+ blocks the merge.
   Double-mutation discipline: the verifier runs its OWN mutation, not just the implementer's.
4. **Hermeticity.** No test may be able to reach real remote creation.
   `scripts/lint-no-live-remote-in-tests.sh` enforces this in CI + pre-commit; design tests to
   pass it (`--no-remote-creation`, `--git-host other` + `tests/host-drivers/mock-cli.sh`,
   or local bare repos).
5. **Every test file must be registered in an aggregator** — `scripts/lint-tests-registered.sh`
   hard-fails on orphans. New unit-shaped suites also belong in the CI fast lane list in
   `.github/workflows/tests.yml` (see how `test-bl073-review-manifest-gate.sh` is wired).
6. **Portability (Linux CI + macOS bash 3.2):** GNU-first `stat -c … || stat -f …`; never
   `((x++))` under `set -e` (use `x=$((x+1))`); configure git identity in fixtures; unset
   `GITHUB_BASE_REF` in fixture git ops; no bash-4-only features (no `${var,,}`, no assoc
   arrays in product scripts).
7. **Backlog discipline:** ship the fix, then flip the backlog status in a follow-up commit
   (defer-status-flip-to-second-commit). Every `Closed` MUST cite a `PR #N` or backticked
   commit SHA in the entry block — `scripts/lint-backlog-references.sh` fails CI otherwise
   (this exact miss turned `main` red on 2026-07-08).
8. **Destructive git ops (`branch -D`, `push --delete`, force-push) are blocked** in the agent
   bash tool — leave branch cleanup for Karl. `gh pr merge` works; do not use `--admin` (that
   was the no-protection era; protection now makes red merges impossible and it must stay that
   way).
9. **Comms:** all user-facing summaries to Karl are short plain-English TL;DRs for a
   non-programmer, with the technical detail kept underneath.
10. **Decision points:** Karl wants pushback and real recommendations, and only genuine forks
    surfaced. Each STOP marked ⚖️ below is a genuine fork — use the structured-options
    sentinel (`scripts/pending-approval.sh --offer`) if offering options at a commit boundary.

## 1. State snapshot (verified 2026-07-09)

- `main` green again as of PR #159 (backlog citation fix + this handoff). Fast lane
  (`.github/workflows/tests.yml` `unit` job, 66 test files, ~4 min) + `lint.yml` (8 lint jobs)
  run on every push/PR; the full ~3h suite is `workflow_dispatch` only (BL-085, deferred).
- Branch protection on `main`: required status checks = `unit` + the 8 lint jobs;
  no force pushes; enforced for admins.
- 156+ merged PRs; no open PRs at handoff time; no `.claude/pending-approval.json` sentinel.
- Backlog: 80 distinct BL entries; open set after PR #159 = exactly the work below + the deferred/held
  list in §5.
- Reference docs: previous handoff `docs/handoffs/2026-07-08-ci-arc-close-and-gate-wave.md`
  (its "BL-025 first, then BL-073" ordering is OBSOLETE — BL-073 shipped in PR #146; BL-025
  was never a real blocker); backlog `solo-orchestrator-backlog.md` is the source of truth.

## 2. The work, in order

Recommended sequence (rationale in each WP):

| # | Package | Backlog | Size | Nature |
|---|---------|---------|------|--------|
| WP-A | Bind Phase-3 summary to tree hash | BL-082 | S | grunt, well-specified |
| WP-B1 | License scanner → real | BL-070 | M | grunt + 1 small policy decision |
| WP-B2 | Threat-model scanner → real | BL-070 | M | grunt + 1 spec correction (below) |
| WP-B3/B4 | Snyk / ZAP scanners | BL-070 | — | ⚖️ STOP — decision gate, likely stay stubbed |
| WP-C | TDD enforcement, two-phase | BL-072 | L | **NOT grunt** — measurement + design risk |
| WP-D1 | Sentinel-before-backfill on full path | BL-081 | S | grunt |
| WP-D2 | Tighten POC-block scenario contract | BL-063 | S | grunt |
| WP-D3 | Phase-2-verified test helper | BL-025 | S | opportunistic only |
| WP-E | Backlog flips + close-out handoff | — | S | grunt |

WP-A → WP-B1 → WP-B2 are sequential (same two files; avoid merge conflicts). WP-C and WP-D1/D2
are independent of the A/B chain and of each other — safe to run in parallel worktrees.

---

### WP-A — BL-082: bind the Phase-3 validation summary to the tree it validated

**Problem.** `scripts/check-phase-gate.sh` (Phase 3→4 block, `# BL-070-GATE-AUTORUN` around
line 1316) auto-runs the driver ONLY when no `docs/test-results/phase3/summary-*.md` exists.
An existing summary is trusted as-is forever — a summary generated 50 commits ago still
satisfies the gate.

**Surfaces.**
- `scripts/run-phase3-validation.sh` — summary writer (find the block that emits
  `summary-<timestamp>.md`; the file already records scanner rows + attestations).
- `scripts/check-phase-gate.sh` — summary discovery + trust, lines ~1300–1370
  (`p3_summary=…` through the `# BL-070-GATE-CHECK` FAIL emit).
- Tests: `tests/test-phase3-validation-gate.sh` (existing suite to extend).

**Design (decided — implement as written).**
1. Driver records provenance in the summary header: `tree: <git rev-parse HEAD^{tree}>` and
   `dirty: yes|no` (`git status --porcelain` non-empty → `yes`). Not in a git repo → record
   `tree: none` (gate then always treats it as stale — conservative).
2. Gate compares the recorded tree hash to the current `git rev-parse HEAD^{tree}`. On
   mismatch, OR `dirty: yes`, OR missing/`none` tree line: treat the summary as STALE —
   print an explicit `[STALE]` info line, then fall through to the existing auto-run path
   (regenerate offline) and evaluate the FRESH summary. If regeneration is impossible
   (driver missing / `SOLO_PHASE3_GATE_NOAUTORUN=1`), STALE = gate FAIL with a message
   telling the operator to re-run `scripts/run-phase3-validation.sh`. Never silently accept
   a stale summary.
3. Mark the comparison line `# BL-082-STALENESS` (mutation target).
4. Backward compat: summaries with no `tree:` line (pre-BL-082) are STALE by rule 2 —
   document this in both script headers.

**Tests (write first).** Extend `tests/test-phase3-validation-gate.sh` (hermetic,
`mktemp`-based). ⚠️ Its existing fixtures are NOT git repos — `setup()` (:58-89) writes state
files only, no `git init` anywhere in the file — so under WP-A's design they'd all resolve to
`tree: none` (always-stale). Your new cases must ADD a real git repo per fixture: `git init`
+ local `user.name`/`user.email` config + an initial commit; a SECOND commit to advance
`HEAD^{tree}` for the stale case; a dirty-working-tree variant for `dirty: yes`. Cases:
T-fresh-trusted (matching tree → no re-run — assert via mtime or a counter file);
T-stale-rerun (new commit → old summary superseded, fresh one generated + evaluated);
T-stale-norerun-fails (`SOLO_PHASE3_GATE_NOAUTORUN=1` + stale → gate FAIL, rc=1);
T-dirty-tree-stale (`dirty: yes` recorded → stale path);
T-pre-bl082-summary-stale (summary without `tree:` → stale path); T-mutation (excise
`# BL-082-STALENESS` → T-stale-norerun-fails goes RED, then restore → GREEN).

**Done when:** suite green incl. mutation proof; `bash scripts/lint-*.sh` all pass; verifier
approve; backlog BL-082 flipped with PR cite (second commit); summary format documented in
the driver header.

---

### WP-B1 — BL-070 increment: promote the `license` scanner to real

**Current state.** `scripts/run-phase3-validation.sh` registry `P3_SCANNERS="semgrep-full-tree
license snyk zap-dast threat-model"` (line ~87); `_p3_kind()` (line ~100) returns `real` only
for `semgrep-full-tree`. The semgrep implementation — `_p3_scan_semgrep`
(`scripts/run-phase3-validation.sh:282`, dispatched from the `semgrep-full-tree)` case arm at
:355) — is the TEMPLATE to copy: detect tool → run → archive JSON to `--results-dir` →
PASS/FAIL/SKIP.

**Steps.**
1. Read the whole driver once. Match the semgrep arm's shape exactly (offline handling,
   archive naming `license-<timestamp>.json`, status strings).
2. Implement `_p3_scan_license`: read the project language the CANONICAL way —
   `jq -r '.context.language' .claude/tool-preferences.json` (copy the reader pattern at
   `scripts/check-phase-gate.sh:1657-1662`). ⚠️ NOT `.claude/manifest.json` — that file holds
   only host/mode/remote_url; reading the wrong source returns empty and silently
   always-SKIPs, the exact `code-verify-reconfigure-1` bug class (see
   `scripts/reconfigure-project.sh:24-30`). Language values are platform-dependent (web:
   csharp/go/java/kotlin/other/python/rust/typescript; mobile/desktop add swift/dart), so
   dispatch known languages and END the case with an explicit `*)` catch-all → SKIP
   (attestable): typescript → `license-checker --json`; python → `pip-licenses --format=json`;
   rust → `cargo license --json`; go → `go-licenses report ./... 2>/dev/null` (csv → wrap);
   csharp → `dotnet-project-licenses -j`; java/kotlin/swift/dart/other/`*` → no canonical
   tool → SKIP (attestable) with a message naming the manual option. Tool not on PATH → SKIP
   (attestable).
   `--offline` → SKIP (these run locally, but keep gate-autorun hermetic and instant —
   mirror semgrep's offline behavior exactly).
3. **Increment contract (deliberately minimal):** PASS = tool ran (rc 0/1-style "report
   produced") AND JSON archived. FAIL = tool crashed / produced no output. Do NOT build a
   license allow/deny policy in this increment.
   ⚖️ STOP (bundled with B3/B4 decision): ask Karl whether a denylist policy (e.g. flag
   GPL/AGPL for organizational deployments) should be a follow-up backlog entry.
   Recommendation: yes, file it, don't build it now.
4. Flip `_p3_kind` license → `real`. Update the driver header table (line ~75-78) and the
   Phase-3 sections of `docs/builders-guide.md` + `docs/user-guide.md` if they enumerate
   which scanners are real.
5. Tests (hermetic — put a mock `license-checker` etc. on PATH emitting fixture JSON, same
   pattern as `tests/host-drivers/mock-cli.sh` — helpers `mock_cli_setup`/`mock_cli_respond`,
   caller prepends the mock dir to PATH): T-license-real-pass,
   T-license-tool-missing-skip (+ attestable), T-license-tool-crash-fail, T-license-offline-skip,
   T-unsupported-language-skip, T-mutation (break the dispatch → PASS test RED).
6. Register any new test file in the aggregator + fast lane.

**Done when:** same bar as WP-A. Update the BL-070 entry's REMAINING list (status stays
IN PROGRESS until B3/B4 are decided).

---

### WP-B2 — BL-070 increment: promote the `threat-model` scanner to real

**⚠️ Spec correction (verified 2026-07-09).** The backlog entry says "parse
`docs/threat-model.md`" — that file does not exist in the framework's own templates. The real
convention (see `templates/generated/threat-model-validation.tmpl`): threats live in
**PROJECT_BIBLE.md Section 4** as `TM-NNN` rows; Phase 3 produces
`docs/test-results/YYYY-MM-DD_threat-model-validation.md` with a validation row per TM-ID.
Build against the real convention, not the entry text.

**Contract.**
- SKIP (attestable) if PROJECT_BIBLE.md has no Section-4 threat table (grep for `| TM-` rows;
  also accept `TM-\d{3}` anywhere in a table row) — message: "no threat model recorded".
- Collect the TM-IDs from PROJECT_BIBLE.md. Collect validated TM-IDs from the newest
  matching report. ⚠️ Verified framework naming inconsistency: `threat-model-validation.tmpl:8`
  says save as `YYYY-MM-DD_threat-model-validation.md`, but `project-bible.tmpl:67` links TM
  rows to `docs/test-results/threat-validation.md#TM-001`. The scanner glob must accept BOTH
  (`*threat-model-validation*.md` OR `*threat-validation*.md`); reconcile
  `project-bible.tmpl:67` to the tmpl-canonical name as a one-line fix in the same PR.
- PASS = every Bible TM-ID appears in the validation report AND the report's Unmitigated
  table is empty-or-risk-accepted (each unmitigated row has non-empty Approved By).
- FAIL = report missing while TM-IDs exist, or any TM-ID unaccounted for, or an unmitigated
  row without an approver. Emit the missing IDs by name — actionable output.
- Archive a small JSON (`threat-model-<timestamp>.json`) with `{ids_total, ids_validated,
  missing:[…]}` like the other scanners.

**Steps/tests.** Same template as WP-B1. Fixtures: a minimal PROJECT_BIBLE.md §4 with 2–3
TM rows + validation report variants (complete / missing-ID / unapproved-risk / absent).
Mutation: neuter the missing-ID comparison → FAIL test goes RED.

---

### WP-B3/B4 — Snyk + OWASP ZAP: ⚖️ STOP — decision gate, do not build unprompted

Both need things a hermetic gate can't assume: Snyk = auth token + network; ZAP = Docker + a
live URL. Recommendation to present to Karl: **keep both as attestable stubs** (the
attest-on-skip flow already makes the skip loud, recorded, and signed) and file a follow-up
for "real Snyk/ZAP when a downstream project actually demands them." Present alongside the
WP-B1 license-policy question as one decision batch. If Karl says build: detect-and-run-if-
available only, never in the gate autorun path, SKIP in `--offline` always, ZAP restricted to
`platform ∈ {web, api}` per the BL-070 entry.

---

### WP-C — BL-072: TDD ordering enforcement — two phases, hard STOP between

**This is the one item that is NOT grunt work.** The detection ("does this commit ship
implementation without tests?") is fuzzy; this repo's own history is full of legitimate
`refactor:`/`fix:` commits a naive detector would block. Karl's standing condition
(recorded in the backlog entry): **dogfood in WARN mode on this repo and measure the
false-block rate BEFORE any hard block ships.** Do not collapse the phases.

**Phase C1 — detector + WARN + measurement (ship this, then stop).**
1. Surface: `scripts/pre-commit-gate.sh`. Reuse the BL-006 machinery: commit-message
   extraction + derivative-commit filtering already exist (see `_is_git_commit`,
   `check_commit_ready` lineage, and `process-checklist.sh --check-commit-message`).
2. Detector (new function, marker `# BL-072-TDD-DETECT`): for commits whose subject matches
   `^(feat|fix|refactor)(\(…\))?!?:` — parse the staged diff; implementation files =
   modified/added files NOT under `tests/`, `docs/`, `.github/`, `Reports/`, `templates/`,
   and not `scripts/lint-*.sh` or pure-comment changes; test files = anything under `tests/`
   or matching per-language conventions (`*_test.go`, `*.test.ts`, `test_*.py`, `*Test.kt`
   …). Trigger = implementation files present AND no test file in the same commit AND no
   test file in `git diff --name-only main...HEAD`.
3. Phase-C1 action on trigger: `[WARN]` with the would-block explanation + append a JSON row
   to `.claude/tdd-warn-ledger.jsonl` (`{date, subject, files, would_block: true}`).
   Never non-zero rc in C1.
4. Measurement: `scripts/dogfood-bl072-replay.sh` (test-helper territory, can live in
   `tests/test-helpers/`) — walk `git log main --no-merges --format=%H` (bound it, e.g.
   since 2026-04-01), classify each commit with the same detector logic in dry-run mode,
   emit `Reports/2026-07-XX-bl072-warn-dogfood.md`: total commits, would-block count,
   would-block rate by prefix, and a hand-review table of the top 20 would-blocks with a
   human judgment column (true positive / false positive). ⚠️ Replay parameterization:
   factor the file-classification core into a function that takes a changed-paths LIST, so
   the live gate and the replay share it — live feeds `git diff --cached --name-only`,
   replay feeds `git diff-tree --no-commit-id --name-only -r <sha>`. The "tests earlier on
   the branch" allowance has no per-commit replay equivalent: classify historical commits on
   their own files only, and state that divergence explicitly in the report (it makes replay
   counts an UPPER bound on live false-blocks).
5. Tests for the detector itself: T-feat-no-tests-warns, T-feat-with-tests-silent,
   T-refactor-no-tests-warns, T-docs-only-silent, T-branch-diff-tests-count (tests earlier
   on the branch satisfy), T-derivative-commits-pass (amend/merge/revert), T-ledger-row-shape,
   + mutation proof on `# BL-072-TDD-DETECT`.
6. ⚖️ STOP. Present the measured false-block rate to Karl with a recommendation. Do NOT
   start Phase C2 without his explicit go.

**Phase C2 — hard block (ONLY after Karl approves, informed by C1 data).**
- Tier matrix: Personal + POC-Personal may bypass (bypass LOGGED to the ledger);
  POC-Sponsored + Production hard-block. **Key the tier on `deployment` + `poc_mode` via the
  `_bl084_tier_bypassable` pattern (`# BL-084-TIER-KEY`, `init.sh:177`), NOT on `track`** —
  BL-084 proved `track` is spoofable (`--track light` on a sponsored project). The BL-072
  entry predates BL-084 and says "track-tiered"; the BL-084 keying supersedes that wording.
  Reuse/factor the predicate rather than re-deriving it.
- Escape hatch: `SOLO_TDD_ATTESTED=1` + reason recorded to
  `process-state.json::tdd_attestations[]` (attested, not silenced — BL-032/070/073 lineage).
- Promote `init.sh:2543-2544` (the warning-only "test-first" text in the generated fallback
  pre-commit hook, installed around `init.sh:2040`) to delegate to the gate rather than
  carrying its own inline warning.
- `upgrade-project.sh` tier promotion flips enforcement to hard-block; the C1/POC ledger is
  the audit trail across the transition.
- Docs sync: `README.md` Tier-3 admission (~line 531), `docs/builders-guide.md` § TDD.
- Full regression cohort per the backlog entry (T-hard-block-feat/fix/refactor,
  T-exempt-docs, T-attested-escape, tier-matrix cases incl. the spoof case
  `--track light` on sponsored → still blocked) + mutation proofs on both the detector and
  the tier key.
- After C2 ships, revisit held items BL-010/011/014 (one recon pass; recommend
  close-or-keep to Karl).

---

### WP-D1 — BL-081: sentinel must freeze the FULL upgrade path too

**Current state (verified).** `scripts/upgrade-project.sh`: `_bl015_sentinel_guard()` defined
~line 143; the `--backfill-only` path calls it early (~line 329, shipped in PR #144); but on
the FULL path the guard runs at ~line 570 — AFTER the idempotent backfill block (vendored-
skills sync prints `[OK] Vendored skills synced…` at ~line 460, plus host/BL-030 manifest
backfill). So a sentinel-blocked full upgrade still mutates `.claude/skills/` + manifest
before it blocks.

**Steps.**
1. Move the full-path `_bl015_sentinel_guard` call above the idempotent backfill block (keep
   it after arg parsing + `guard_not_in_framework` — read the surrounding order first and
   preserve every other guard's relative position).
2. Fix the `_bl015_sentinel_guard()` docstring (~lines 106–143): it claims "mutates nothing"
   for both call sites — make that claim true rather than editing the claim.
3. Regression (hermetic, local fixture project): with a sentinel present, run a FULL upgrade;
   assert rc≠0, deny message, and the ENTIRE `.claude/` tree byte-identical before/after.
   **Extend `tests/test-upgrade-sentinel-block.sh`** — its T1–T3 already cover the
   full-upgrade sentinel block, and its T4–T6 (`--backfill-only` × BL-015 parity, PR #144)
   carry the exact byte-identical-md5 assertion pattern AND the hermeticity trick to copy
   (pin `CDF_HOME` to a nonexistent path so no real CDF clone is touched). Add the
   skills/manifest-untouched assertion to the T1–T3 full-path cases. Mutation proof: revert
   the call-site move → new assertion RED (skills dir content changed).
4. Confirm no double-guard side effects (guard called once per path; `--backfill-only` path
   unchanged).

---

### WP-D2 — BL-063: tighten the POC-block enforcement-point contract

**Problem.** The two scenario contracts (`edge-phase-3-to-4-poc-blocked-check-phase-gate`,
`…-process-checklist`, from the 2026-06-29 adversarial pass — see
`Reports/2026-06-29-adversarial-certainty-pass.md` S-6) assert only that the POC-block
message is PRESENT in gate output. A regression adding an unrelated `[FAIL]` at the same
enforcement point would go unnoticed.

**Deliverable (in-repo, durable — the scratchpad walker matrices are not the place):** a
registered regression test (new file `tests/test-check-phase-gate-poc-block-contract.sh`, or
extend `tests/test-check-phase-gate.sh` if its fixture already covers Phase-3→4 POC) that:
1. Fixture (concrete, verified): a project dir with `.claude/phase-state.json` containing
   `current_phase: 3` and `poc_mode: "private_poc"` (or `sponsored_poc`). No `track` value is
   needed — the block keys purely on poc_mode + phase≥3
   (`scripts/check-phase-gate.sh:1373-1385`). Ignore the "derive from the report" instinct —
   the S-6 report names the scenarios but contains no fixture recipe.
2. ⚠️ The two enforcement points emit DIFFERENT markers — write the assertions accordingly:
   `check-phase-gate.sh` emits the POC block as a GitHub annotation
   `::error::Phase 4 (production release) is BLOCKED…` (:1381), NOT a `[FAIL]` line;
   `process-checklist.sh` uses `print_fail` → `[FAIL]` and exits 1 immediately (:577-581).
3. check-phase-gate assertion: the `::error::…BLOCKED…` line is present AND the count of
   unexpected `::error::` + `[FAIL]` lines is zero (allowlist any legitimately co-firing
   gates explicitly, one justifying comment each). Negative control: corrupt an unrelated
   required artifact → the tightened count must catch the extra failure line.
4. process-checklist assertion: a co-firing count is unbuildable there — `start_phase4()`
   short-circuits on the POC block (single `[FAIL]`, then `exit 1`). Assert the short-circuit
   contract instead: rc=1, exactly one `[FAIL]`, and no later-step output present.
5. Sweep: grep the other Step-5-derived tests for `grep -q` message-present-only assertions
   at enforcement points; list what you find in the PR description; promote the worst
   offenders or file a follow-up entry if >2 days of work.

---

### WP-D3 — BL-025: phase-2-verified test helper (opportunistic ONLY)

**Doc-supersedes-entry exception #3:** the BL-025 entry says "SCHEDULED as the first step of
the remaining gate wave … Built first". That scheduling is obsolete — it assumed BL-073's
regression tests needed seeded gate state, but BL-073 shipped (PR #146) with plain heredoc
fixtures. Do NOT build this speculatively. Build it the moment a WP-B/C/D test actually needs "project
in Phase-2-init-verified state" and hand-rolling it a second time. Shape (per the entry):
`tests/test-helpers/init-phase2-verified.sh`, sibling of the existing
`tests/test-helpers/scaffold-libs.sh` (copy its sourcing/arg conventions). Produces:
`.claude/manifest.json`, `.claude/phase-state.json` (current_phase=2),
`.claude/process-state.json` with `phase2_init.verified=true`, minimal `.git/` +
`package-lock.json` + pre-commit hook. State-only; no CLAUDE.md/framework-clone. If built,
refactor at least one existing hand-rolled fixture onto it (proves the interface) and close
BL-025 with the cite.

---

### WP-E — Close-out (after each WP and at the end)

1. Backlog flips with citations (lint-enforced), as separate commits from the fixes.
2. When B1/B2 land and B3/B4 are decided: BL-070 status → Closed-or-narrowed with an explicit
   list of what stays stubbed-by-decision.
3. Update auto-memory `project_current_state.md` + `MEMORY.md` index.
4. Write the next session-boundary handoff in this directory following this file's shape.
5. Remind Karl of the leftover local branch cleanup (agent-blocked):
   `git push origin --delete ci-tmp-shard-validate ci-tmp-validate-full` and
   `git branch -D ci-tmp-shard-validate ci-tmp-validate-full docs/backlog-accuracy-0707` —
   plus any wave branches left by this arc, and the stale `scratchpad/wt-pr120`,
   `scratchpad/wt-pr125` worktree leftovers.

## 3. What NOT to touch

- **Deferred:** BL-085 (full-suite CI-fast), BL-019/042/043 (next-quarter recon items).
- **Held pending WP-C Phase C2:** BL-010/011/014 (may be absorbed or closed by BL-072's
  design — revisit only after C2).
- **Parked:** BL-017. **Won't Fix:** BL-012/013/058.
- The full-suite CI lane (`workflow_dispatch` `full` job) — leave manual-only.
- Branch protection settings.
- CDF (`~/.claude-dev-framework`) — no upstream work is in scope this wave; if a fix turns
  out to belong upstream, stop and tell Karl (cross-repo preference: fix CDF upstream, not
  Solo shims).

## 4. Global definition of done

- All WPs merged (or explicitly decision-gated closed), each via its own PR with green
  required checks — no red merges, no `--admin`.
- `main` green; `bash scripts/lint-backlog-references.sh` clean; no orphan tests
  (`scripts/lint-tests-registered.sh` clean); no new non-hermetic tests.
- Backlog statuses match reality (the failure mode this handoff exists to prevent — twice
  now: BL-073 in PR #157, and the original BL-079 citation miss).
- Karl has received: the B3/B4 + license-policy decision batch, the C1 false-block-rate
  report with recommendation, and a final plain-English close-out summary.

## 5. Resume prompt (paste as the first message of the new session)

> Continuing solo-orchestrator work from the gate-wave execution handoff at
> `docs/handoffs/2026-07-09-gate-wave-execution-handoff.md`. Run in ultracode effort.
> First do §0.0 Bootstrap exactly: read the memory files, read backlog entries
> BL-082/070/072/081/063/025 in full, read the whole handoff, then verify state (main green,
> branch protection active on main, no open PRs, no pending-approval sentinel) and summarize
> what you see back to me before dispatching anything. Then execute the work packages in
> order — WP-A (BL-082 staleness binding) first; WP-C and WP-D1/D2 may run in parallel
> worktrees with the WP-A→B chain. Honor every rule in §0 (no merge on red, TDD + mutation
> proofs, impl + adversarial-verify pairs, hermeticity, backlog citations). STOP for my
> decision at the two ⚖️ gates (Snyk/ZAP + license-policy batch; BL-072 false-block-rate
> report before any hard block). Deliver all user-facing messages as short plain-English
> TL;DRs for a non-programmer, with technical detail underneath.

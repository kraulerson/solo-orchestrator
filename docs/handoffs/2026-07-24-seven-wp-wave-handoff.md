# Handoff — seven-WP wave delivered as PRs #265–#270; next = merge + closures, then Big-strategy & housekeeping

**Date:** 2026-07-24 EOD · **Author session:** supervisor (Fable 5) · **Focus for next session:** land the wave, then start the phase Karl already queued ("Once this is complete, we'll work on the Big strategy and housekeeping items").

## 1. Where we are

`main` is at `6fc1c11` (the BL-161/BL-165 wave + closures #264, all merged earlier today). On top of it, the **seven-WP wave is complete and open as SIX green PRs — NOT merged** (supervisor never self-merges; all await Karl). Every WP ran implementer (opus, isolated worktree, fable-authored plan) → independent fable verifier; every single one surfaced a real finding — the fifth consecutive wave where the two-layer discipline caught something the implementer missed.

| PR | Item(s) | Verifier arc |
|---|---|---|
| [#265](https://github.com/kraulerson/solo-orchestrator/pull/265) | BL-172 (cherry-pick/revert resume sentinels, both TDD-gate surfaces) | APPROVE-WITH-FIXES (word fix; filed BL-176) |
| [#266](https://github.com/kraulerson/solo-orchestrator/pull/266) | BL-173 (two stale full-suite tests repaired; test-only) | clean APPROVE (7-row mutation matrix; root-caused the "flake" as deterministic) |
| [#267](https://github.com/kraulerson/solo-orchestrator/pull/267) | BL-136 (TEST 5/7 fixture-era repairs) + BL-135 evidence pass | APPROVE-WITH-FIXES (3 vacuous assertions de-vacuated with bite proofs) |
| [#268](https://github.com/kraulerson/solo-orchestrator/pull/268) | BL-174 (upgrade-path gitignore backfill + installer pass-arm case) | APPROVE-WITH-FIXES (comment truth; filed BL-177 **Medium**) |
| [#269](https://github.com/kraulerson/solo-orchestrator/pull/269) | BL-097/098/100 **operating-model design doc** (the trio's gated deliverable) | 3 adversarial rounds: BLOCK → narrow BLOCK → **APPROVE** |
| [#270](https://github.com/kraulerson/solo-orchestrator/pull/270) | BL-131 + BL-132 (SAST: staged-bytes index scan + shipped DOM-sink ruleset) | **REJECT** (default-`.semgrepignore` silent-skip regression) → FIX B → **APPROVE** |

All six are CI-green (lints + unit lane; `full` shard is `workflow_dispatch`-only by design). WP-G (the CDF bug write-up) needed no PR — see § 2.

## 2. What shipped this session

- The six PRs above (branches: `fix/bl172-sentinel-parity`, `fix/bl173-test-cleanups`, `fix/bl135-bl136-fullsuite-debt`, `fix/bl174-gitignore-backfill`, `docs/bl097-100-operating-model-design`, `fix/bl131-bl132-sast-hardening`). Each: watched-RED TDD, marker fences (`# BL-172-RESUME-SENTINELS`, `# BL-136`, `# BL-174-GITIGNORE-BACKFILL`, `# BL-132-INDEX-SCAN`, `# BL-131-DOM-SINKS`), mutation proofs, both-lane registration where applicable, fable verification.
- **The operating-model design of record:** `docs/designs/2026-07-24-operating-model-v1.md` (v1.2.1, 645 lines, §0 carries the full three-round traceability). Headline decisions: `operatingModel` block in `.claude/manifest.json`; tier tokens + `modelsBound`; three presets; **hard per-dispatch enforcement IS achievable** (PreToolUse `Agent`-matcher deny gate + manifest-rendered `.claude/agents/` role files — BL-146's `pr-reviewer.md` is the in-repo precedent) with STRICT composition; single-model degradation; 9-WP build skeleton in §10. Build is un-gated on review but **stays sequenced per the recorded 2026-07-20 trio decision**; entries stay Open.
- **WP-G / BUG-001 (CDF context7 detection):** VERIFIED **already fixed upstream** (CDF commit `16c7f20`; clone clean+even with origin; live `check_context7` → DETECTED on this host). Write-up placed at `~/Documents/Claude Projects/claude-dev-framework/BUG-context7-detection-status.md` (outside this repo — Karl works it separately). Solo's `solo-orchestrator-bugs.md` BUG-001 entry still says "Still needed" — **stale**, flip to Fixed on Karl's word.
- **Four follow-ups filed** (all Open): **BL-175** (shipped semgrep ruleset outside the shipped-set/currency registries, Low), **BL-176** (sentinel `.git/<S>` checks blind in linked worktrees, Low), **BL-177** (`_run_idempotent_backfill` has NO structural projectless guard — two sibling blocks write outside projects TODAY; explains the framework repo's month-old untracked `.claude/skills/`; **Medium**), **BL-178** (case-insensitive-FS materialization collision in the index temp tree, Low).
- Prior to the wave, earlier today (already merged by Karl): BL-161 (#262), BL-165 (#263), BL-173-filing (#261), closures #264.

## 3. What's blocked / waiting

- **The six PRs await Karl's review + merge.** Recommended order: **#265 → #266 → #267 → #269 → #268 → #270** (small/docs first; the two `upgrade-project.sh` touchers last — #268 edits `_run_idempotent_backfill`, #270 edits `_bl099_sync_precommit_hook`, different functions). Expected trivial conflicts as merges proceed: the two registration anchors (`tests.yml` `tests=(`, `tests/full-project-test-suite.sh`) → keep both lines; backlog end-appends (BL-175/176/177/178) → keep all, numeric order.
- **After merge — closure flips** (usual closures-PR pattern): BL-131, BL-132, BL-172, BL-174 → Closed with PR + merge SHAs. **BL-173 and BL-136 stay Open until a green full-lane run** (their PRs' stated closure condition); **BL-135** stays Open awaiting its second full-lane data point; **BL-097/098/100** stay Open (design delivered; build pending).
- **A post-merge full-lane `workflow_dispatch` run** (~3h) is the natural next validation: it confirms the TEST 5/7 repairs and the two repaired suites, and gives BL-135 its second data point in one shot. Needs Karl to trigger (or approve triggering).
- **BUG-001 entry flip** (docs-only, on Karl's word). **Live-ZAP smoke** at the next dogfood walk (carried recommendation from the BL-165 reviewers).

## 4. What's next (Karl's stated sequence: "Big strategy and housekeeping items")

1. **Land the wave** (merge + closures PR + optional full-lane dispatch), per § 3.
2. **Big strategy:** (a) the **operating-model build** — plan directly from the design's §10 nine-WP skeleton (WP1 schema → WP4a/4b enforcement surfaces → …), same wave discipline; (b) **BL-109 Currency System** remaining slices (design of record `docs/designs/2026-07-12-currency-system-v1.md` v1.1).
3. **Housekeeping batch:** BL-085 (CI-fast full suite, deferred), BL-090 (doc-reference checker), BL-092 (generated CLAUDE.md diet), BL-093 (backlog archive split), BL-094 (grep indexes for big scripts).
4. **New-follow-up queue** when convenient: **BL-177 first (Medium — live leak)**, then BL-175/176/178 (Low).

## 5. References

- Backlog (source of truth): `solo-orchestrator-backlog.md` — `## BL-131:` `## BL-132:` `## BL-172:` `## BL-173:` `## BL-174:` `## BL-135:` `## BL-136:` `## BL-097:` `## BL-098:` `## BL-100:` + new `## BL-175:` … `## BL-178:` (the 175–178 entries live on the un-merged wave branches until merge).
- Design doc: `docs/designs/2026-07-24-operating-model-v1.md` (on the #269 branch until merge). Currency design: `docs/designs/2026-07-12-currency-system-v1.md`.
- CDF write-up: `~/Documents/Claude Projects/claude-dev-framework/BUG-context7-detection-status.md` (outside this repo).
- Repo discipline: `CLAUDE.md` (bash-3.2 subset, [WARN]-trap, marker citations, both-lane registration, quote paths).
- Prior handoff (superseded by this one): `docs/handoffs/2026-07-24-residuals-wave-and-next-builds.md`.

## 6. Resume prompt

> Continuing from the 2026-07-24 EOD handoff at `docs/handoffs/2026-07-24-seven-wp-wave-handoff.md` in /Users/karl/Documents/Claude Projects/solo-orchestrator. Read that handoff and CLAUDE.md first. State when I stopped: the seven-WP wave (BL-131+132 SAST, BL-172, BL-173, BL-174, BL-135/136 investigation, the BL-097/098/100 operating-model design doc, and the CDF BUG-001 verification) is open as six green, fable-verified PRs #265–#270 — none merged; never self-merge. FIRST: `git fetch` and check the actual merge state of #265–#270 — Karl may have merged some or all since. If merges happened: resolve any keep-both-lines conflicts on the remaining PRs (registration anchors + backlog end-appends, numeric order), then open the closures PR (flip BL-131/132/172/174 → Closed with PR + merge SHAs; BL-173/135/136 stay Open pending a green full-lane run — propose triggering the ~3h `workflow_dispatch` full lane to Karl, never run it unasked; BL-097/098/100 stay Open, design delivered), and ask Karl about flipping the stale BUG-001 entry to Fixed (CDF `16c7f20`, verified). If PRs are still open: surface the review queue and wait. THEN proceed to Karl's queued phase — Big strategy (the operating-model build planned from `docs/designs/2026-07-24-operating-model-v1.md` §10's nine-WP skeleton, and BL-109 currency slices) and housekeeping (BL-085/090/092/093/094), plus the follow-up queue led by BL-177 (Medium). Use the standing discipline: fable-authored junior-followable plans, opus implementers in isolated worktrees, fable verifiers ≥ implementer on anything behavioral, watched-RED TDD with mutation proofs, both-lane registration, commit-not-push until verified, and nudge any subagent that ends its turn "waiting" on a background job — completion notifications only reach the supervisor.

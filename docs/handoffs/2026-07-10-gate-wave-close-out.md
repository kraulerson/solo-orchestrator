# Gate-Wave Close-Out — 2026-07-10

**Audience:** the next executing agent (Opus 4.8, ultracode effort) and Karl.
This is the retrospective + resume companion to
`docs/handoffs/2026-07-09-gate-wave-execution-handoff.md` (the execution plan).
The gate wave is COMPLETE: all eight work-package PRs (#160–#167) are merged and
`main` is green with branch protection enforced. This document records what
shipped, the two design corrections the wave forced, the true backlog state, the
WP-E close-out PR's own contents, what to leave alone, the destructive cleanup
only Karl can do, and a resume prompt for the next session.

---

## 1. State snapshot (verified 2026-07-10)

- **`main` tip:** `65aee2d` — *"Merge pull request #167 from
  kraulerson/feat/bl070-snyk-zap-scanners-real"*.
- **CI (verified via `gh run list --branch main`, not asserted):** both
  post-merge required workflows are **success**:
  - PR #167 merge (the current tip): `tests` run **29127220379** ✅,
    `lint` run **29127220351** ✅.
  - PR #166 merge: `tests` run **29127073747** ✅, `lint` run **29127073806** ✅.
- **Branch protection on `main` — UNCHANGED** (verified via the protection API):
  `enforce_admins=true`, `allow_force_pushes=false`, required status checks =
  `unit` + the 8 lint jobs
  (`backlog-references-lint`, `counter-antipattern-lint`, `doc-anchors-lint`,
  `fix-functions-stderr-lint`, `no-live-remote-in-tests-lint`,
  `raw-read-prompt-lint`, `review-manifest-lint`, `tests-registered-lint`).
- No open PRs at wave close except the WP-E close-out PR (this branch). No
  `.claude/pending-approval.json` sentinel.

---

## 2. What shipped (PRs #160–#167)

Every PR ran the impl + adversarial-verify pattern from §0.3 of the execution
handoff; each merged only on green required checks (no `--admin`, no red merge).

| PR | Backlog | Verdict | Key content |
|----|---------|---------|-------------|
| **#160** | BL-082 | approved / merged | Bind the Phase-3 validation summary to the tree it validated. Driver stamps `- tree: <HEAD^{tree}>` + `- dirty: <scoped>`; the gate re-runs (or FAILs, when auto-run is disabled) on a stale/dirty/pre-BL-082 summary. Marker `# BL-082-STALENESS`. |
| **#161** | BL-063 | approved / merged | Tighten the two Phase-3→4 POC-block enforcement-point contracts from "message present" to "the POC block fires ALONE": count-based zero-co-firing-failure contract for `check-phase-gate.sh` (`::error::…BLOCKED`), short-circuit contract (rc=1, exactly one `[FAIL]`, no later-step output) for `process-checklist.sh --start-phase4`. New `tests/test-check-phase-gate-poc-block-contract.sh`. |
| **#162** | BL-081 | approved / merged | The FULL upgrade path now runs `_bl015_sentinel_guard()` BEFORE the shared idempotent backfill, so a sentinel-blocked full upgrade leaves the entire `.claude/` tree (incl. `.claude/skills/` + manifest) byte-identical. Docstring's "mutates nothing" claim made true for both call sites. New T7 full-path mutation proof in `tests/test-upgrade-sentinel-block.sh`. |
| **#163** | BL-072 C1 | approved / merged | TDD-ordering DETECTOR in **WARN mode** + dogfood replay. Fires on `feat/fix/refactor` commits shipping impl with no matching test; `[WARN]` + `.claude/tdd-warn-ledger.jsonl` row; never blocks. Shared classifier `scripts/lib/tdd-classify.sh` (live gate + replay agree byte-for-byte). Report `Reports/2026-07-10-bl072-warn-dogfood.md` (38.6% would-block upper bound, 50% hand-review FP floor). |
| **#164** | BL-070 (license) | approved / merged | `license` scanner promoted to REAL. Per-language dispatch off `.claude/tool-preferences.json::.context.language` (typescript→license-checker / python→pip-licenses / rust→cargo license / go→go-licenses / csharp→dotnet-project-licenses; unsupported/missing → attestable SKIP; `--offline`→SKIP). Inventory-only PASS/FAIL. Marker `# BL-070-LICENSE-DISPATCH`. |
| **#165** | BL-070 (threat-model) | approved / merged | `threat-model` scanner promoted to REAL. Validates every PROJECT_BIBLE.md §4 `TM-NNN` row against the newest validation report (glob accepts BOTH `*_threat-model-validation.md` and legacy `*_threat-validation.md`; reconciled `project-bible.tmpl:67`). Pure-local → RUNS under `--offline`. Marker `# BL-070-TM-COMPARE`. |
| **#166** | BL-072 C2 | approved / merged | Tier-keyed TDD **HARD BLOCK** + attested escape. Keyed on `deployment`+`poc_mode` (`# BL-084-TIER-KEY`, never the spoofable `track`): WARN+`bypassed:true` for Personal/Private-POC, `[FAIL]` rc=1 for Sponsored-POC/Production; `SOLO_TDD_ATTESTED=1` escape RECORDED to `process-state.json::tdd_attestations[]` (a failed record REFUSES the commit). Classifier tightened (all `*.md`, pure deletions, lockfiles excluded). Ships as a **commit-msg** hook (see §2 discovery b). |
| **#167** | BL-070 (snyk+zap) → **closes BL-070**; files **BL-086** | approved / merged | `snyk` + `zap-dast` promoted to REAL per Karl's 2026-07-10 "wire up all security scanners" decision (superseding the earlier keep-as-stubs recommendation). Detect-and-run-if-available ONLY; SKIP under `--offline`/missing-tool/unauth (snyk) or `--offline`/platform∉{web,api}/no-docker/no-`SOLO_ZAP_TARGET_URL` (zap). Markers `# BL-070-SNYK-DISPATCH` + `# BL-070-ZAP-DISPATCH`. **All five Phase-3 scanners are now real — nothing stubbed-by-decision.** |

### Two design corrections the wave recorded (Karl-approved)

**(a) BL-082 — the dirty predicate had to be SCOPED, and the gate checks LIVE
dirtiness.** An unscoped `git status --porcelain` reads the tree as dirty the
instant the gate writes `phase-state.json` on its first PASS (the driver writes
attestations there; `check-phase-gate.sh` writes the BL-071 gate date there; that
file is TRACKED downstream). That would mark every summary permanently stale and
— with `SOLO_PHASE3_GATE_NOAUTORUN=1` — brick the gate. Correction 1: the scoped
porcelain EXCLUDES `.claude/` and the `--results-dir`. Correction 2: `dirty` is
not a one-time stamp — `check-phase-gate.sh` re-checks freshness against the
CURRENT tree AND the LIVE scoped porcelain and regenerates when stale, so an
uncommitted SOURCE edit still invalidates a tree-matched summary. Both were
Karl-approved corrections; both are pinned by tests
(`T-stateflip-not-dirty`, `T-live-dirty-stale`, and — added by this close-out PR
— `T-driver-emits-provenance`).

**(b) BL-072 — the TDD gate CANNOT live in a pre-commit hook.** At `pre-commit`
time `.git/COMMIT_EDITMSG` still holds the *previous* commit's message (git
writes the new subject there only after pre-commit runs), so a pre-commit hook
cannot read the prospective `feat/fix/refactor` subject the detector keys on. The
enforcement therefore ships as a **commit-msg** hook
(`pre-commit-gate.sh --terminal-mode --tdd-only`), which `init.sh` installs; the
subject is read from `COMMIT_MSG`/`.git/COMMIT_EDITMSG` at commit-msg time when it
is current.

---

## 3. Backlog state at wave close

**Closed this wave (all cited):**
- **BL-082** — Closed 2026-07-09, PR #160.
- **BL-063** — Closed 2026-07-09, PR #161.
- **BL-081** — Closed 2026-07-10, PR #162.
- **BL-072** — Closed 2026-07-10, C1 PR #163 + C2 PR #166.
- **BL-070** — Closed 2026-07-10, PR #167 (all five scanners real; timeline cites PRs #145/#160/#164/#165/#167).

**New this wave:**
- **BL-086** — *License-compliance policy layer (allow/deny) for the Phase-3
  license scanner.* **Status: Open** — filed per Karl's gate-#4 decision batch as
  file-don't-build; it is a Karl decision (whether/when to build an allow/deny
  policy, e.g. flag GPL/AGPL for organizational deployments).

**Deferred (revisit next quarter / on demand — do NOT pick up speculatively):**
- **BL-019** (verify-install.sh non-interactive audit), **BL-042** (init.sh
  `prompt_install` × pipefail on closed stdin), **BL-043** (intake-wizard.sh
  `main()` extraction refactor — the PR #104 main-guard + trap-guard already
  close the real risks), **BL-085** (make the ~3h full suite CI-fast).

**Parked:** **BL-017** (intake-wizard.sh non-interactive mode — no operator
demand in 60+ days; field-specific flags cover known needs).

**Held trio — recon recommendations PRESENTED to Karl 2026-07-10, AWAITING his
answer. DO NOT FLIP THESE.** They remain `Open — HELD 2026-07-05 pending BL-072
design`. After the C2 hard block shipped, the one-pass recon recommends:
- **BL-010** (`.git/hooks/commit-msg` for editor-case / human-terminal coverage)
  — **close-as-absorbed**: PR #166's commit-msg hook infrastructure already
  delivers editor-case / human-terminal commit enforcement. The residual
  "extend the BL-006 build-loop check to the same hook" is optional with no
  demand signal.
- **BL-011** (Cutline-ID-aware enforcement) — **Won't-Fix recommended**: not
  absorbed by C2, zero demand in 78 days, and it conflicts doctrinally with
  BL-007's convention-free rule.
- **BL-014** (Commit-type hygiene enforcement) — **Won't-Fix recommended**:
  C1/C2's measured 50% false-positive floor on the EASIER prefix+path signal
  empirically confirms that diff-intent inference is too brittle to enforce, and
  the attestation ledger already provides the honest audit trail.

---

## 4. WP-E close-out PR (this branch: `chore/gate-wave-close-out`)

Three-topic PR, strictly scoped to `tests/**`, `solo-orchestrator-backlog.md`,
and `docs/handoffs/**` (no product-code changes):

1. **`test(close-out)` — the four verifier-minor coverage gaps from this wave's
   adversarial reviews**, each with a RED→GREEN mutation proof:
   - **(a) WP-A driver provenance** (`tests/test-phase3-validation-gate.sh`):
     new `T-driver-emits-provenance` runs the REAL
     `scripts/run-phase3-validation.sh --offline` in a hermetic git repo and
     asserts `- tree:` == `git rev-parse HEAD^{tree}` + `- dirty: no` (clean),
     `- dirty: yes` (uncommitted source), and `- dirty: no` for a
     `.claude`-only change (scoped predicate). Kills the two surviving driver
     mutations: excise the `- tree:` echo → tree case RED; force
     `_p3_scoped_dirty`→`no` → dirty case RED.
   - **(b) WP-D2 vacuous sub-assertion**
     (`tests/test-check-phase-gate-poc-block-contract.sh`): the T4/T5
     `current_phase`-stays-3 check was VACUOUS w.r.t. the short-circuit — the
     only writer of `current_phase` on this path (`_set_current_phase_min 4`,
     `process-checklist.sh:596`) runs strictly AFTER
     `print_ok "Phase 4 release started"` (:595), which the "no later-step
     output" assertion already catches. Removed with a one-line justifying
     comment.
   - **(c) C2 attested-escape FAILURE path**
     (`tests/test-bl072-tdd-warn-detector.sh`): new `T-attested-record-failure`
     — sponsored fixture + `SOLO_TDD_ATTESTED=1` + a durable-write forced to
     fail (chmod 500 `.claude`, trap-restored) → the gate REFUSES rc=1 with a
     loud `[FAIL]` and NO partial write (`process-state.json` absent). Kills the
     surviving mutation: flip the loud-refuse `return 1`→`return 0` → the
     un-recorded escape passes (rc=0) RED. (Root-guarded: skips cleanly if
     `.claude` stays writable under an unusual FS/root.)
   - **(d) C2 lockfile exclusion** (same suite): new `T-lockfile-excluded` — a
     sponsored `feat` touching ONLY `package-lock.json` + a `*.lock` is silent
     (rc=0, no trigger, no ledger row). Kills the surviving gap: strip the
     lockfile arms from a copy of `scripts/lib/tdd-classify.sh` → the lockfiles
     reclassify as impl → the same fixture hard-blocks (rc=1) RED.
2. **`docs(backlog)` — NO CHANGES.** The three cosmetic tidy items in the WP-E
   spec were each verified against git history and found to have **false
   premises** (kept + reported, per the spec's own safeguard):
   - BL-055's second `**Status:** Open` (line ~1336) is the *original
     2026-06-29 entry* (commit `98315661`), deliberately preserved under an
     `**Original entry (pre-close, kept for audit trail):**` header the close
     commit `f6a8e6c` added on purpose — not a stray.
   - BL-003b has exactly ONE Status line; the two "PR forthcoming, this commit"
     lines belong to the SEPARATE entries `code-upgrade-project-8` (line ~692)
     and `code-check-gates-1` (line ~705) — their own sole Status lines.
   - BL-043 has exactly ONE Status line; the `Closed … 06fb186` line (line ~848)
     belongs to the SEPARATE entry `code-check-gates-7-followup` (the blame
     walker that PR #116/`06fb186` legitimately closed).
   Deleting any of them would damage the backlog, so none were touched.
   `scripts/lint-backlog-references.sh` passes unchanged.
3. **`docs(handoff)` — this file.**

Verification: `tests/test-phase3-validation-gate.sh` 51/0,
`tests/test-check-phase-gate-poc-block-contract.sh` 5/0,
`tests/test-bl072-tdd-warn-detector.sh` 36/0; all four mutation kills RED→GREEN;
`for l in scripts/lint-*.sh` all green (`lint-uat-scenarios.sh` exits 2 bare —
the known parametrized tool that needs a scenario argument).

---

## 5. What NOT to touch (unchanged from the execution handoff §3)

- **Deferred:** BL-085 (full-suite CI-fast), BL-019/042/043 (next-quarter recon).
- **Held pending Karl's answer:** BL-010/011/014 — recommendations are recorded
  in §3 above; do NOT flip until Karl decides.
- **Parked:** BL-017. **Won't Fix:** BL-012/013/058 (and, if Karl agrees,
  BL-011/014).
- The full-suite CI lane (`workflow_dispatch` `full` job) — leave manual-only.
- **Branch protection settings** — leave as-is.
- CDF (`~/.claude-dev-framework`) — no upstream work is in scope; if a fix turns
  out to belong upstream, stop and tell Karl (cross-repo preference: fix CDF
  upstream, not Solo shims).

---

## 6. Karl's manual cleanup (agent-blocked destructive git ops)

Destructive git ops (`push --delete`, `branch -D`, force-push, worktree removal)
are blocked in the agent bash tool — these are for Karl to run once the WP-E PR
merges.

**Delete merged remote branches:**
```
git push origin --delete \
  ci-tmp-shard-validate ci-tmp-validate-full docs/backlog-truthup-and-handoff-0709 \
  feat/bl082-summary-staleness-binding test/bl063-poc-block-contract \
  fix/bl081-sentinel-before-backfill feat/bl072-tdd-warn-dogfood \
  feat/bl070-license-scanner-real feat/bl070-threat-model-scanner-real \
  feat/bl072-c2-tier-hard-block feat/bl070-snyk-zap-scanners-real
```

**Delete the same branches locally (+ leftovers), and the ~28 stale
`worktree-wf_*` branches:**
```
git branch -D \
  ci-tmp-shard-validate ci-tmp-validate-full docs/backlog-accuracy-0707 \
  docs/backlog-truthup-and-handoff-0709 \
  feat/bl082-summary-staleness-binding test/bl063-poc-block-contract \
  fix/bl081-sentinel-before-backfill feat/bl072-tdd-warn-dogfood \
  feat/bl070-license-scanner-real feat/bl070-threat-model-scanner-real \
  feat/bl072-c2-tier-hard-block feat/bl070-snyk-zap-scanners-real
git branch --list 'worktree-wf_*' | xargs -r git branch -D   # ~28 stale worktree branches
```

**Remove stale worktrees** (`scratchpad/wt-pr120`, `scratchpad/wt-pr125`, and the
~30 old `.claude/worktrees/agent-*/wf_*` dirs from previous arcs):
```
git worktree remove scratchpad/wt-pr120
git worktree remove scratchpad/wt-pr125
# for each stale .claude/worktrees/... dir: git worktree remove <dir>
#   (or delete the dirs, then: git worktree prune)
```

---

## 7. Resume prompt (paste as the first message of the new session)

> Continuing solo-orchestrator after the gate wave closed
> (`docs/handoffs/2026-07-10-gate-wave-close-out.md`). Run in ultracode effort.
> First read the memory files (`MEMORY.md` + `project_current_state.md`) and this
> close-out doc, then verify state — `main` green (cite the current
> `gh run list --branch main` run IDs), branch protection active, no open PRs, no
> pending-approval sentinel — and summarize what you see before dispatching
> anything. The gate wave is DONE; the open work is: (1) whatever Karl decided on
> the held trio BL-010/011/014 (recon recommendations are in §3 — close-BL-010,
> Won't-Fix BL-011, Won't-Fix BL-014 — do NOT flip until he answers); (2) the new
> BL-086 license-policy layer (Open, Karl decision on whether/when to build);
> (3) the deferred set BL-019/042/043/085 (opportunistic only — no demand). Honor
> every rule in the execution handoff §0 (no merge on red, TDD + mutation proofs,
> impl + adversarial-verify pairs, hermeticity, backlog citations, ship-then-flip
> in a second commit). Deliver all user-facing messages as short plain-English
> TL;DRs for a non-programmer, with the technical detail underneath.

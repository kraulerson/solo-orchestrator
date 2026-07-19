# Dogfood Remediation — Session Handoff (2026-07-18)

**Purpose:** pick up the Dogfood-2 + Dogfood-3 remediation arc in a fresh session.
This is the state-of-record as of end of session 2026-07-18. Newest handoff = current
(per `docs/handoffs/` convention). Read this first, then `CLAUDE.md`.

---

## 1. TL;DR — where we are

- **The Dogfood-2 remediation (18 findings) is merged and validated.** PRs #199–#216
  landed all of Phases A–F; the Dogfood-3 walk (a fresh independent agent building a
  real app end-to-end) scored **20/20 fix-checkpoints HELD, escape hatches ZERO, real
  v1.0.0 released, ratchet holds** (`Reports/2026-07-18-dogfood-3/REPORT.md`).
- **The Dogfood-3 wave (4 new findings) is nearly merged.** BL-137/138/139 merged
  (PRs #217/#218/#219); **BL-140 = PR #220 is the ONE open PR**, checks re-running
  after the verifier's two MUST-fixes.
- **⚠ ONE REAL GAP in the original scope: WP-A2 (BL-120 High + BL-125 Medium) was
  never shipped.** See §3 — this is the highest-value next task.
- **main tip:** `b6ca944` (Merge #219). **Framework repo is byte-clean** except the
  five known-untracked paths (see §7).

---

## 2. IMMEDIATE tasks (do these first, in order)

1. **Land PR #220 (BL-140).** It's the sole open PR. It carries the ZAP-workdir fix
   PLUS the consolidated verifier's two MUST-fixes (`398dacc`): D1 (absolutize the
   docker `-v` host path — the documented bare invocation was rc=125-broken on every
   docker runtime) and D-extra (de-flake the same-second archive collision). Suite
   `test-bl070-snyk-zap-scanners.sh` is **48/48, green 3× consecutive** locally. Wait
   for its `unit` + `counter-antipattern` checks to go green, then merge.

2. **Post-merge backlog closures (docs-only, overdue).** BL-137/138/139 are MERGED but
   their backlog `**Status:**` still reads `Open — fix implemented…` because status
   flips at merge (house rule: Closed entries MUST cite a PR# or backticked SHA —
   `scripts/lint-backlog-references.sh` enforces). Flip them, and BL-140 once #220 merges:
   - BL-137 → Closed, PR #217, merge `ef0a6a1`
   - BL-138 → Closed, PR #218, merge `82bbab7` (+ the `719ddcb` blame-walker follow-up)
   - BL-139 → Closed, PR #219, merge `b6ca944`
   - BL-140 → Closed, PR #220, merge `<sha after merge>`
   Do these on a small `docs/…-closures` branch (NOT on a code branch); mirror the
   closure prose already staged in each entry's status update. Also flip **BL-106**
   (machine-checkable go-live, shipped PR #213 `ab62028`) and **BL-134** (resolver
   bounds, PR #214 `528f5b2`) if a prior closures PR (#212-style) didn't already —
   verify with the recipe in §8.

---

## 3. ⚠ THE GAP — WP-A2 (BL-120 High + BL-125 Medium) was skipped

**This is the single most important open item.** The Dogfood-2 remediation plan
(`Reports/2026-07-13-dogfood-2/REMEDIATION-PLAN.md` § WP-A2) grouped **BL-118 + BL-120 +
BL-125** as *"three independent gates that all waved the same real XSS through — defense
in depth means each must catch it."* I shipped BL-118 (the commit-time SAST) but **WP-A2
was never done** — there is NO `WP-A2` entry in the ledger, and both items are still
`**Status:** Open`. Dogfood-3 did not resurface it because the walker did its security
audit and tests HONESTLY, so it never exercised the "audit says FAIL but the step passes
anyway" hole — which is exactly the existence-only-gate failure mode these items name.

- **BL-120 (High)** — `process-checklist.sh`'s `build_loop:security_audit` step is an
  existence check (`ls docs/security-audits/*"${feature_slug}"*`): an audit artifact that
  literally says "SEV-1, DO NOT SHIP" still completes the step. **Fix:** require a
  machine-readable verdict (e.g. `**Verdict:** PASS|FAIL`, `**Open critical/high:** N`)
  and FAIL on `FAIL`/N>0. Mutation: a `FAIL` audit must block
  `--complete-step build_loop:security_audit`; flip to `PASS` → passes.
- **BL-125 (Medium)** — nothing runs the project's tests at commit time; a commit whose
  own tests are RED lands. **Fix:** run the configured test command on the commit path
  (or at `implemented`/`security_audit` completion) with the SAME "tool-not-runnable →
  loud SKIP, never silent pass" discipline as the SAST arm; keep latency sane
  (changed-file-aware / fast lane). Mutation: stage code making a committed test RED →
  blocked; green → allowed.

Full target/fix/mutation spec is in `REMEDIATION-PLAN.md` § WP-A2 (lines ~76–82). Treat
this as a proper WP: branch, watched-RED test, `# BL-120-…`/`# BL-125-…` marker fences,
mutation proof, adversarial verify (High severity → verifier ≥ implementer tier),
backlog close, PR. It is a defense-in-depth gap on the Critical-class XSS finding.

---

## 4. Dogfood-3 SHOULD-fixes (filed by the wave verifier; land WITH #220)

These are on the #220 branch (BL-141/142/143 not yet on main). None blocks anything;
tackle after WP-A2.

- **BL-141 (Medium)** — `verify-install --auto-fix` ignores the commit-msg hook, and
  non-interactive sync can leave it absent → the BL-139 "no enforcement lost" backstop
  is population-conditional (legacy/declined/non-interactive-sync strict-tier projects
  can end up with NO terminal-path feat gate). Teach verify-install to detect/repair it;
  make sync WARN when pre-commit exists without commit-msg.
- **BL-142 (Low)** — stale `scripts/lib/hook-templates.sh` header claims the sync path
  skips rust/unknown languages; contradicts BL-107 universal install. Doc-only.
- **BL-143 (Medium)** — the anti-self-approval control silently skips when the Approver
  row sits past `validate_approval_fields`' +20 section cap (BL-138 introduced the
  reachable edge). WARN, or take the name from the blame walker's located line. The
  `719ddcb` walker follow-up mitigates the malformed-header case but NOT this past-cap case.

---

## 5. Known watch / debt (filed, low urgency)

- **BL-135** — `test-bl033-install-cmds-shape.sh` failed once in full-lane CI, green
  locally; unreproduced. Watch a second full-lane run before instrumenting.
- **BL-136** — full-project-test-suite TEST 5 + TEST 7: pre-existing core-lane failures
  (on record since 2026-07-12). Fixture-era vs product: repro each in isolation.
- **BL-131 / BL-132** — recorded SAST residuals (DOM sinks no public semgrep rule covers;
  hook scans worktree bytes not index content). Decisions, not urgent.

---

## 6. Phase G — product decisions PENDING KARL (design notes ready; do NOT build unasked)

Per the original kickoff these are STOP-and-design-note only; each has a decision-ready
note in `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` § PHASE G. Recommendations:

- **BL-109** (Currency System) — hold the detect→offer-and-apply escalation until one
  downstream project runs a manual `--sync-framework` against real drift.
- **BL-099 / BL-101** — recommend closing INTO BL-109 (their work IS the Currency ladder).
- **BL-089** ready pending Karl's `docs/IDENTIFIERS.md` pre-seed list; **BL-091** rides
  with it; **BL-090** blocked on a Pantheon FP-calibration corpus; **BL-092** last of the
  quartet, needs the CLAUDE.md split-list sign-off.
- **BL-097/098/100** (delegation trio) — ONE decision gates all three: normative text vs
  gate-checked evidence artifacts.

Also open, resolved decisions already applied (no action): **BL-133** = leave-removed;
the semgrep-unit-lane question = adopted (semgrep now in the unit lane, PR #213).

---

## 7. Phase H — DEFERRED, untouched by design

BL-019, BL-025, BL-042, BL-043, BL-085 (deferred); BL-093, BL-094 (opportunistic only);
BL-120/125 are NOT in this set — they were in-scope (see §3).

**Untracked root files (leave as-is unless Karl says otherwise):** `.claude/skills/`,
`.claude/worktrees/`, `DOGFOOD-2-PROMPT.md`, `DOGFOOD-3-PROMPT.md`, `EXECUTIVE-SUMMARY.md`.
(`DOGFOOD-3-PROMPT.md` is the walk spec used this session; may belong in `Reports/`.)

---

## 8. Traps, conventions, and lessons (READ before touching the backlog or gates)

- **BL-055 scan trap:** `grep '**Status:** Open'` surfaces BL-055, but it is **Closed**
  (2026-07-01, PR #116) — the "Open" lives in a preserved pre-close audit block.
  CLAUDE.md § ISSUE TRACKING documents this class. Always check the *top-of-block* status.
  Genuine open count ≈ 28 minus BL-055.
- **Closed entries MUST cite a PR# or backticked SHA** (`lint-backlog-references.sh`).
  Never mark Closed on a not-yet-merged branch — flip at merge.
- **Citation rule:** cite code by `# BL-NNN-…` marker or function name, NEVER bare
  `file:line` (they mis-resolve within a day). Re-grep any line-number cite before trusting.
- **The `[WARN]` trap** (`check-phase-gate.sh`): the verdict is `if [ $issues -eq 0 ]` —
  the `issues++` INCREMENT blocks, not the `[WARN]`/`[FAIL]` label. Two `[WARN]` arms can
  have opposite gate outcomes. Read the increment.
- **Blast-radius lesson (from #218's CI failure this session):** grep every consumer of
  the shared VARIABLE, not just the function. BL-138 bounded a `$section` that the blame
  walker ALSO read; the battery ran self-approval's siblings but missed
  `test-check-phase-gate-blame-walker.sh` → red on CI. Fix `719ddcb`.
- **Fixture-uniformity lesson (from the BL-140 D1 MUST-fix):** all 47 zap fixtures passed
  an ABSOLUTE `--results-dir`, hiding a real break in the DEFAULT relative-path invocation.
  When a suite is uniform on an input axis, add one case that exercises the other value.
- **Env traps:** no `timeout`/`gtimeout` on this host; `/bin/bash` is 3.2 (no
  `declare -A`, `${var,,}`, `((x++))` under `set -e`); repo path has a SPACE — quote
  everything; `stat -c … || stat -f …`.
- **Discipline (non-negotiable):** every fix is watched-RED TDD + a `# BL-NNN-…` marker
  fence + a mutation proof (excise the fence → RED → restore → GREEN); register new
  `tests/test-*.sh` in BOTH `tests/full-project-test-suite.sh` AND the `tests.yml` unit
  list; hermetic tests only; escape hatches = ZERO; high-severity fixes get an adversarial
  verifier (verifier tier ≥ implementer). Ledger written as-you-go to
  `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md`.

---

## 9. State-verification recipes (run these to confirm reality — counts drift)

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
git fetch origin -q
git log --oneline origin/main -3                 # expect b6ca944 (#219) or later
gh pr list --state open                          # expect #220 until merged
gh pr checks 220                                 # BL-140 gate

# open backlog (mind the BL-055 trap — check top-of-block status):
grep -n '\*\*Status:\*\* Open' solo-orchestrator-backlog.md

# confirm WP-A2 is still absent (the gap):
grep -c 'WP-A2' Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md   # expect 0

# closure state of the wave items on main:
git show origin/main:solo-orchestrator-backlog.md | \
  awk '/^## BL-1(37|38|39|40):/{t=$0} /^\*\*Status:\*\*/{print t": "$0}'

bash scripts/lint-backlog-references.sh          # backlog citation integrity
bash scripts/run-lints.sh                        # 11 repo lints (~2 min; slow scans expected)
```

---

## 10. Suggested next-session order

1. Merge #220 (BL-140) once green; flip its + the wave's backlog statuses (§2, §4 filings
   land with it).
2. **WP-A2 — BL-120 (High) then BL-125 (Medium)** (§3). The headline. Full TDD+mutation+
   verifier; it closes the last defense-in-depth hole from the Critical XSS finding.
3. Dogfood-3 SHOULD-fixes: BL-141 (Med) → BL-143 (Med) → BL-142 (Low).
4. Surface the Phase-G decisions to Karl (§6) — those are his calls, not autonomous work.
5. Optional: a Dogfood-4 walk once WP-A2 lands, to prove the defense-in-depth trio catches
   a *dishonest* security-audit / RED-test path end-to-end (the case Dogfood-3's honest
   operator never exercised).

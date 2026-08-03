# WALK-REPORT — Solo Orchestrator first-time-user walkthrough

**Persona:** developer with <1 year professional experience, following the
framework's user-facing docs literally.
**Product built:** DocNote — a client-side (React + Vite + TypeScript) `.docx`
viewer with text highlighting and notes, localStorage persistence, no server.
**Outcome:** shipped a real, releasable **v1.0.0** through all five phases.
Live at **https://kraulerson.github.io/docnote-walkthrough/**; GitHub Release
**v1.0.0** with an SBOM attached; 125 automated tests green; Semgrep clean;
full 6-reviewer adversarial evaluation completed.
**Repo:** https://github.com/kraulerson/docnote-walkthrough

This walk is a **dogfood test**: finding problems is the deliverable. Every
stumble is logged in `WALK-ISSUE-LOG.md` (append-only) and every DocNote defect
in `BUGS.md`. This report summarizes.

---

## 1. Counts

### Framework findings (WALK-ISSUE-LOG.md — the dogfood output)

| Severity | Count | Meaning |
|---|---|---|
| **Blocker** | 0 | Could not proceed via docs at all |
| **Major** | 5 | Proceeded only by breaking persona / an undocumented recovery |
| **Minor** | 10 | Worked but wrong/misleading |
| **Confusion** | 3 | Worked but unclear what to do next |
| **Smooth notes** | 13 | Things that went genuinely well |

No hard Blockers: every obstacle had *a* way through. But five Major findings
required recovery steps a real junior would not have found from the docs alone.

### DocNote application bugs (BUGS.md — found by the framework's own process)

33 bugs found across **3 UAT sessions + the 6-reviewer Phase-3 evaluation**,
**all resolved** (or accepted-with-rationale). Breakdown: 2 SEV-1 (both
decompression-bomb DoS — one my code, one my *fix*), 6 SEV-2, ~14 SEV-3,
~11 SEV-4. Zero open at release.

---

## 2. The top findings

**M-1 (Major) — The `feat:` commit trap + the silent `tail` pipe (ISSUE-010).**
The pre-commit gate blocks a `feat:` commit unless a Build Loop is *active*. If
you complete the loop (mark `feature_recorded`) and run the UAT session *before*
committing the feature code — a natural reading of the docs — the `feat:` commit
is permanently blocked. Worse, I had piped `git commit` through `tail`, which
hid the missing `[main <sha>]` line, so **four commits I believed had landed
never happened** (proven by `git reflog`). A junior would lose work and not know
it. Fix: commit the feature *while the loop is active* (before closing it), and
never trust piped commit output — always `git log -1`.

**M-2 (Major) — The reviewer suite caught a SEV-1 my own fix missed (the walk's
best moment).** My BUG-1 decompression-bomb guard trusted the ZIP central
directory's *advertised* uncompressed size. The Phase-3 Red Team review (RT-01)
proved a `.docx` that *lies* about its size sails past the guard while JSZip
still inflates the real multi-GB payload — re-opening the exact SEV-1 DoS. The
security reviewer independently flagged it but rated it Low; the red-team
reviewer correctly escalated it to a ship-blocker. I fixed it properly (bounded
*actual* inflation via `DecompressionStream`). This is the framework's
adversarial-review design working exactly as intended — an independent
perspective caught a hole a self-review had rationalized as "good enough."

**M-3 (Major) — CI phase-gate can't pass on the framework's own default happy
path (ISSUE-006).** The generated `ci.yml` phase-gate step verifies branch
protection via an API the default GitHub Actions token can't read, so the
**first CI run fails** on a fresh public personal repo that `init.sh` itself
created — and the printed remediation (`check-gate.sh --repair`) reports nothing
is wrong. Recovery required the `SOIF_PHASE_GATES=warn` knob, which only the
Tier-1 table mentions.

**M-4 (Major) — Phase-bump / `--start-phase4` deadlock (ISSUE-015).** CLAUDE.md's
governance says "set `current_phase` to the new phase number" at each gate. Do
that for Phase 3→4 and you deadlock: `check-phase-gate` FAILs with "Phase-4
checklist never started," but `--start-phase4` refuses because the gate isn't
clean. Escape (undocumented): revert `current_phase` to 3 and run
`--start-phase4`, which owns the bump itself.

**M-5 (Major) — Tag-triggered release deadlocks with GitHub Pages' default
environment (ISSUE-016).** The generated `release.yml` deploys on a version tag,
but enabling Pages auto-creates a `github-pages` environment that allows only
`main` — so the documented "tag to release" happy path fails at job setup with
an *unreadable* error. Fix (undocumented): add a `v*` tag deployment-branch-policy
via `gh api`.

**Minor/Confusion highlights:** the Step-2.4 audit Semgrep command is weaker
than the gate's full-tree scan, so a "clean" per-feature audit is later blocked
at commit/gate time (ISSUE-009 — it caught two real issues: a test-fixture
`innerHTML` and, later, mutable action tags I'd introduced); `nosemgrep` is
silently ignored unless it's on the *immediately preceding* line (ISSUE-011);
the legal-review gate demands a Privacy Policy for a zero-collection local tool
(ISSUE-013); the Phase-4 monitoring check assumes server-side error telemetry a
zero-telemetry static app doesn't have, and its free-text detector only accepts
a specific keyword shape (ISSUE-017); the `SOIF_FORCE_STEP` and `--reset`
escape hatches require an interactive terminal, so an autonomous agent has none;
and the pre-commit suppression detector flags a *document that merely mentions*
the `nosem`-family directive as if it carried a live suppression, writing a
false `sast_suppression` row into the bypass-audit ledger (ISSUE-018 — found by
committing this very report, which discusses that directive).

**What impressed me (the smooth column):** the whole thing is real, not theater.
`init.sh --non-interactive` scaffolded a working repo (CI, hooks, pinned deps)
in one command. The Build-Loop gate genuinely blocked rubber-stamping — the
`security_audit` step machine-reads the audit verdict, and gitleaks/BL-125
actually blocked a planted secret and a planted failing test. The Phase-3
validation driver ran real scanners and made me *sign* every skip (snyk, ZAP)
rather than silently pass. `semgrep-full-tree` was strictly stronger than my
manual scans and twice caught issues I'd missed. And the adversarial reviewer
suite found a real SEV-1. The framework's core claim — "phase-gated, test-driven,
security-scanned, not vibe coding" — held up under a genuine build.

---

## 3. What a real junior's experience would have been

A junior would have **succeeded**, but slower and more shaken than I was, at
four or five specific cliffs:

1. **The silent-commit trap (M-1)** is the scariest: they'd believe features
   were committed and pushed, then discover via a later error that half their
   work was never saved. Recovering requires understanding git reflog and the
   `feat:`-needs-active-loop rule — neither is in the docs.
2. **The two "documented happy path fails with an opaque error" cliffs** (CI
   phase-gate M-3, tag-release M-4/M-5) would each cost a junior real time,
   because the error text points nowhere useful and the fix is an undocumented
   `gh api`/env-var incantation.
3. **The phase-bump deadlock (M-4)** — following CLAUDE.md literally causes it,
   and the escape (revert the phase you just set) is counter-intuitive.
4. The **friction of the Phase-4 artifact checks** (each step wants a specific
   file/keyword shape) would have a junior guessing at what phrasing satisfies
   the detector — I needed four tries on the monitoring one.

But the flip side: the same gates that frustrated also **protected** them. A
junior who can't fully evaluate security got a real SEV-1 caught by the reviewer
suite, a zip-bomb caught by the SAST/validation layers, and stored-XSS defenses
verified by adversarial probes. The framework compensates for exactly the gaps a
junior has — which is its whole thesis.

---

## 4. Where the wall-clock went

Roughly, in descending order:
1. **Phase 2 construction + 3 UAT sessions + remediation** — the bulk. Six
   Build Loops (tests-first), three adversarial UAT rounds, and fixing all 33
   bugs test-first. The UAT remediation (esp. the two SEV-1s) was the single
   biggest chunk.
2. **Phase 3 validation + 6 reviewer evaluations** — running the scanners,
   writing the threat-model validation + all evidence artifacts, and the RT-01
   fix.
3. **Fighting process-ordering / gate-shape friction** — the Major findings
   (silent commits, CI gate, phase-bump deadlock, release/Pages deadlock,
   monitoring detector). Easily 90+ minutes of the total lost to these.
4. **Phases 0–1** — fast and pleasant; the docs are prescriptive and the
   templates match what the gates later check.

Time saved by the framework (bugs it caught that would otherwise ship) plausibly
exceeds time lost to its friction — but the friction is concentrated in
avoidable doc/ordering gaps that would disproportionately hurt a first-timer.

---

## 5. Deliverables

- **Live app:** https://kraulerson.github.io/docnote-walkthrough/
- **Release:** v1.0.0 (GitHub Release + SBOM)
- **Code:** `src/core/` (framework-free logic) + `src/ui/` (React); 125 tests
- **Framework artifacts:** PRODUCT_MANIFESTO, PROJECT_BIBLE (16 §), ADR-0001,
  per-feature security audits, 3 UAT sessions, 6 reviewer evaluations,
  Phase-3 validation summary, threat-model validation, SBOM, HANDOFF,
  INCIDENT_RESPONSE, SECURITY, PRIVACY_POLICY, USER_GUIDE, APPROVAL_LOG.
- **The dogfood output:** `WALK-ISSUE-LOG.md` (18 findings + 13 smooth notes)
  and `BUGS.md` (33 bugs, all resolved).

## 6. Final gate status

The framework's own arbiter agrees the project is done. After a clean working
tree and a fresh `run-phase3-validation.sh` (to refresh the tree-bound Phase-3
summary), `scripts/check-phase-gate.sh` reports:

```
GATE_EXIT=0
  [OK] Competency Matrix: Appendix B present (deep check: scripts/validate.sh --competency)

Phase 4 Release Checklist (BL-105)
[OK] BL-105: Phase-4 checklist started (6/6 steps recorded — production_build,
     rollback_tested, go_live_verified, monitoring_configured, handoff_written,
     handoff_tested)

Phase gates consistent.
```

All five phases are crossed, all gates satisfied, the Phase-4 checklist is 6/6,
v1.0.0 is live and released, and the phase machine reports **consistent**. By the
framework's own definition, the walk is complete.

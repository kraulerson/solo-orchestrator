# Handoff — the SAST wave is closed; next is a live shipped defect, then the BL-198 build

**Date:** 2026-07-30 · **Author session:** supervisor (Opus 5 → Fable 5) · **Prior handoff:** `docs/handoffs/archive/2026-07-29-sast-coverage-and-ci-lane.md` (archived by this one)

## 1. Where we are

`main` is at **`3a196ee`**, where the backlog reads **194 `BL-`numbered entries, 31 open**; this
branch's BL-193 closure takes it to **30 open at merge** (no single repo state satisfies "at
`3a196ee`" and "30 open" together — re-derive after merging). Count with the
trap-aware recipe, never a raw grep — BL-055's preserved pre-close block carries its own
`**Status:** Open`:

```
awk '/^## /{p=0} /Original entry \(pre-close/{p=1} /\*\*Status:\*\* Open/{if(!p) n++} END{print n}' solo-orchestrator-backlog.md
```

**One PR open, deliberately: [#278](https://github.com/kraulerson/solo-orchestrator/pull/278), a
draft that must NOT be merged.** It is held as the only copy of four backlog entries
(BL-185/186/188/189) and five test cases that BL-198's WP4 needs back. Its red `sast` shard is the
pre-fix snapshot of defects since fixed on `main` — do not "fix" it, do not rebase it, or the record
it exists for is destroyed. The disposition and close condition are commented on the PR itself.

Everything else is merged and green.

## 2. What shipped 2026-07-29

Five PRs merged 2026-07-29 (#280–#284); sixteen across the whole arc, and the arc total had been
inherited under this single-day header until review caught it. The four that matter to the next
session:

- **#280** (`8f36382`) — the SAST coverage stack. Root-caused **BL-193**: semgrep writes its
  scan-status banner to **stderr on macOS and stdout on the GitHub runner**, and the coverage guard
  hard-coded stderr, so the emitted hook NOTRUNed every clean commit on CI. **Four readers were
  stream-blind and one was FAIL-OPEN** (`soif_sg_timeouts` — "no timeout seen ⇒ coverage may be
  granted"), which could have granted an unearned `[OK]` over a target whose rule was abandoned.
  Fixed by `# BL-193-STATUS-STREAM`; the `sast` shard went green and `test-bl132`'s silent skips fell
  **10 → 2**. Also fixed BL-194 (a prose comment captured a test's policy derivation) and BL-183's
  two `tests/` sites.
- **#282** — five closures with verified citations; **#283** — the BL-198 plan plus BL-200/BL-201 and
  both semgrep decisions; **#284** — BL-199, the README quick start.
- **BL-199**: the README's own four commands did not work. `init.sh` refused to run from inside the
  clone — the documented flow. The guard now checks **where you are writing**, not where you are
  standing, and `--project-dir <name>` scaffolds a sibling of the clone. Review found the first fix
  had a **case-variant bypass on macOS** (`CLONE` vs `clone` — 602 files landed inside the framework);
  closed with device+inode identity.

## 3. What to do next, in order

### 3.1 — BL-183's emitted-hook npm detector (do this first)

**A live defect in shipped enforcement code.** `# BL-125-COMMIT-TESTS` in
`scripts/lib/hook-templates.sh` detects `npm test` with
`sed -n '/"scripts"…/,/}/p' package.json | grep -qE '"test"…'` under the emitted hook's
`set -euo pipefail`. On a monorepo-sized `scripts` block the consumer exits on first match, the
producer takes EPIPE, and the predicate inverts — so a project **with a real jest suite** is told
`PROJECT TESTS NOT ENFORCED` and the commit-time test gate silently stops running. Measured **20/20
deterministic on macOS**; an independent reviewer reproduced it end-to-end, watching a real commit
land past the gate.

> **BL-183's own stated precondition for this site is WRONG and will send you to the wrong fixture.**
> It blames a large `package.json`. A 1.25 MB file with an ordinary `scripts` block does **not**
> reproduce — `sed`'s range closes at the first `}`, after which it reads without *writing*, and
> SIGPIPE needs a write. **The trigger is a large `scripts` block.** There is also a flaky band around
> ~55 KB (4/5) before it goes deterministic above ~110 KB.

Fix with single-process awk. **Preserve the S1/S4 scripts-block scoping** — a dependency named `test`
must not trigger detection, and a placeholder string elsewhere in `package.json` must not disable a
real suite. Own PR; do not fold it into anything else.

### 3.2 — BL-198, the transcode-first implementation (WP0–WP4)

Four adversarial rounds went into the plan; it is unusually specific about how it goes wrong, so
follow it rather than re-deriving. Two things it will not forgive:

- **Transcode AFTER F2, and write to the IDENTICAL path.** A "sibling" name is silently unscanned —
  semgrep picks a target's language from its extension — and breaks BL-178's operator path mapping.
  The two constraints intersect at exactly one shape.
- **Never redirect `iconv` into the file it is reading.** `iconv … > "$dest"` truncates `$dest` first,
  so iconv converts an empty file and returns **0**.

WP4 restores five test cases that exist **only on #278**. Landing this unblocks BL-200, BL-201 and
#278's closure.

### 3.3 — BL-201 (blocked by BL-198)

Float the 22 `semgrep/semgrep:1.170.0` template pins and add a `semgrep --version` log line to every
scanner job. **The trap is named in the entry:** `test-bl147`'s `Cg4`/`Cg5-image` assertions *require*
the version-pinned form, so they must move in the same diff or the PR arrives red — and their failure
messages under-describe what they check, which must also be fixed.

### 3.4 — then, in any order

**BL-200** (token-break blind spot, blocked by BL-198) · **BL-196** (nothing validates `# BL-NNN-…`
marker citations, though CLAUDE.md makes them the citation primitive) · **BL-197** (the
diagnostic-destruction lint) · **BL-199**'s deferred `--dry-run` residual · **BL-181**'s two residuals
· a retroactive adversarial audit of **#272**, which merged unreviewed · **BL-085 / BL-109 /
housekeeping**.

## 4. The operating-model build needs re-planning, not resuming

**All three WP plans are lost.** WP2 and WP3 were session-local and were deleted by temp cleanup
before being copied out; WP1 was never written. The design of record survives:
`docs/designs/2026-07-24-operating-model-v1.md` (v1.2.3, five adversarial rounds). One escalation to
carry forward, recoverable from the design: § 3's `singleModel` iff makes the `always-best` preset
compute `true`; a reviewer judged that coherent as a config-shape predicate, but WP2's tests must
encode **one** semantic, not both.

**The lesson, recorded because it cost ~45 KB of work:** a pointer to a session-local path is a
pointer with an expiry date. This one expired before anyone actioned it, and the warning to copy the
files out was sitting in a *merged* document. Planning artifacts worth citing from a merged document
belong in the repo.

## 5. Standing gates — non-negotiable

- **Adversarial `pr-reviewer` on the branch tip BEFORE `gh pr create`** — docs-only and
  supervisor-authored commits included.
- **Never merge on red**; no `gh pr merge --admin`. Never `--no-verify`.
- **TDD with mutation proofs** for enforcement changes — and **verify the mutant is not vacuous**.
  One proof this week produced a false GREEN by mutating a different copy than the test executed.
- **Attest lints AFTER committing.** `lint-backlog-references.sh` scans commit messages, so a
  pre-commit run cannot see them. This repo shipped that false attestation twice in one day.
- **Closed entries must cite a PR # or backticked SHA.** `Open — DEFERRED` entries do **not** trigger
  that lint — so cite the delivering PR in prose by hand, or the audit trail has a hole nothing
  catches.

## 6. What this week actually cost — worth internalising

**Every substantive error was in prose, not code.** The code passed every mutation designed against
it, every time. What failed: a handoff blaming the wrong subsystem; a fix whose guard claimed
documentation could "NEVER" break it (broken by the idiomatic act of documenting it); a closure
describing work that never happened; a duplicate of an entry explained correctly hours earlier; two
neutrality arguments, one sound and one false; and a pointer to files that expired before anyone
acted on it.

Three adversarial rounds returned `block` or `major_concerns` and **every finding was real**.
Re-measure claims rather than inheriting them — including your own from earlier in the same session.

## 7. References

- `solo-orchestrator-backlog.md` — **on `main` today:** BL-183 (the live defect, § 3.1), BL-192 +
  BL-198 (diagnosis + plan), BL-196, BL-197, BL-199 (`Open — DEFERRED`), BL-200, BL-201. **Only on
  #278:** BL-185/186/188/189.
- Operating-model design of record: `docs/designs/2026-07-24-operating-model-v1.md` (v1.2.3).
- Repo discipline: `CLAUDE.md` — the `[WARN]` trap, the citation rule, the unit-lane membership rules
  and BL-181's two residuals.
- Prior handoff: `docs/handoffs/archive/2026-07-29-sast-coverage-and-ci-lane.md` — its §§ 5–7 (the
  BL-192 root cause) remain the reference for that analysis; §§ 1–4 are a superseded snapshot and its
  own header says so.

## 8. Resume prompt

> Continuing work on **solo-orchestrator** at `/Users/karl/Documents/Claude Projects/solo-orchestrator`. Read `CLAUDE.md` first, then `docs/handoffs/2026-07-30-post-sast-wave-next-steps.md`. **State:** `main` at `3a196ee` before this branch merges (31 open there; 194 entries, 30 open once the BL-193 closure lands) — use the trap-aware recipe in § 1, never a raw grep. `git fetch` and re-derive before trusting any of this. One PR open: **#278, a draft that must NOT be merged** — it is the only copy of four backlog entries and five test cases BL-198's WP4 needs, and its red `sast` shard is a deliberate pre-fix snapshot; do not fix or rebase it. **FIRST: BL-183's emitted-hook npm detector (§ 3.1)** — a live defect in shipped enforcement code where a project with a real jest suite is told `PROJECT TESTS NOT ENFORCED` and the commit-time test gate silently stops running, measured 20/20 deterministic and reproduced end-to-end. **BL-183's own stated precondition for that site is WRONG** and will send you to a fixture that does not reproduce: the trigger is a large `scripts` block, not a large `package.json`, because `sed`'s range closes at the first `}` and SIGPIPE needs a write. Fix with single-process awk preserving the S1/S4 scripts-block scoping; own PR. **THEN BL-198** (§ 3.2 — transcode after F2, identical path not a sibling, never redirect `iconv` into the file it reads), which unblocks BL-201, BL-200 and #278's closure. **THEN § 3.3 and § 3.4.** The operating-model build needs re-planning, not resuming — all three WP plans are lost and must be re-derived from `docs/designs/2026-07-24-operating-model-v1.md` (§ 4). **Standing gates (§ 5):** adversarial `pr-reviewer` before `gh pr create`, docs-only included; never merge on red; never `--no-verify`; mutation proofs must be checked for vacuity; attest lints AFTER committing, because `lint-backlog-references.sh` scans commit messages and a pre-commit run cannot see them. Read § 6 before writing any backlog entry or handoff — every substantive error last session was in prose, not code, and three adversarial rounds each found something real.

# Session Handoff — 2026-07-20: remediation arc CLOSED; Phase-G decisions next

**Purpose:** session-boundary record after the Dogfood-2/3 remediation arc fully
merged. Newest handoff = current (supersedes
`docs/handoffs/2026-07-18-dogfood-remediation-handoff.md`, which described the
arc mid-flight). Read this, then `CLAUDE.md`.

---

## 1. Where we are

**The remediation arc is COMPLETE and fully on main** (tip `3282fe0`, PR #228).
Every item from the Dogfood-2 scope and the Dogfood-3 wave is Closed with PR +
merge-SHA citations; `lint-backlog-references` green; escape hatches ZERO across
the entire arc; main green. No branch is mid-flight. The next work is
**Karl's Phase-G product decisions** (§4) — deliberately not built.

## 2. What shipped this session (2026-07-19 → 2026-07-20)

| PR | Merge | What |
|----|-------|------|
| #221 | `f68cdeb` | 2026-07-18 handoff doc (era-mismatch CI failure diagnosed + fixed in-branch) |
| #222 | `1be14d2` | Closures: BL-137/138/139/140 → Closed (the Dogfood-3 wave, merged #217–#220 previous session) |
| #223 | `fdda7a2` | **BL-120 (High), WP-A2 part 1** — `# BL-120-AUDIT-VERDICT`: security_audit reads the audit's verdict, fail-closed template grammar; Fable verifier SHIP-WITH-FIXES, all landed; suite 17/17 |
| #224 | `ad62827` | **BL-125, WP-A2 part 2** — `# BL-125-TEST-EXEC`/`# BL-125-COMMIT-TESTS`: emitted pre-commit hook runs the project's tests; Fable verifier SHIP-WITH-FIXES, all landed; 16/16; guard-registry row K4 |
| #225 | `cf10873` | BL-141 — `# BL-141-COMMITMSG-VERIFY` + `# BL-141-SYNC-WARN`: verify-install repairs the commit-msg gate; sync declines never silent |
| #226 | `2fb7cd1` | BL-143 — `# BL-143-PASTCAP-RECOVERY`: past-cap Approver rows recovered from the walker's own scan |
| #227 | `23c996f` | BL-142 doc-only header fix + consolidated wave verdict (SHIP ×3) + BL-144/145 filings |
| #228 | `3282fe0` | Closures: BL-120/125/141/142/143 → Closed; five ledger WP headers → MERGED |

**WP-A2 closed the last original-scope gap:** the BL-118 + BL-120 + BL-125
defense-in-depth trio each now catches the Dogfood-2 XSS. Three Fable-tier
adversarial verifications ran (BL-120 solo, BL-125 solo, consolidated wave);
every MUST landed RED-watched pre-merge. Full evidence:
`Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` (WP-A2 parts 1–2 +
VERIFICATION sections, WP-BL141/142/143, the consolidated wave verdict).

## 3. What's blocked / waiting

- **Nothing mechanical.** All PRs merged; CI green; no pending-approval sentinel.
- **Open by design:** BL-144/145 (wave-verifier residuals, pre-existing classes,
  Low — fix shapes recorded in the entries), BL-135/136 (watches), Phase-H
  DEFERRED set, and the Phase-G set below.

## 4. What's next — Karl's Phase-G decisions (design notes in the ledger § PHASE G)

Surfaced 2026-07-19/20; each is decision-ready, none is autonomous work:

1. **BL-109 escalation** — detect-and-name → offer-and-apply? Rec: hold until a
   real downstream `--sync-framework` cycle against real drift.
2. **BL-099 + BL-101 disposition** — close both into the BL-109 ladder? Rec: yes.
3. **BL-089 pre-seed list** (`docs/IDENTIFIERS.md` namespaces) — unblocks the
   089+091 WP.
4. **BL-090 tooling home** — extend `lint-doc-anchors.sh` vs sibling. Rec:
   extend. Steps 2–3 blocked on a Pantheon FP corpus only Karl can supply.
5. **BL-092 split list** — sign off which CLAUDE.md sections move to
   `docs/reference/` (retrieval-enforced pointers).
6. **BL-097/098/100 enforcement tier** — normative text vs gate-checked evidence
   artifacts; one decision gates the trio.
7. **BL-101 conflict UX** (if not folded by #2) — `.rej`-style vs interactive.
   Rec: `.rej`-style (headless-agent compatible).
8. **Dogfood-4?** — optional walk to prove the trio against a DISHONEST
   audit/RED-test path (the case Dogfood-3's honest walker never exercised).

## 5. References

- `Reports/2026-07-13-dogfood-2/REMEDIATION-PROGRESS.md` — ledger of record
  (per-WP evidence, verifier verdicts, § PHASE G design notes).
- `Reports/2026-07-13-dogfood-2/REMEDIATION-PLAN.md` — original scope (§ WP-A2).
- `Reports/2026-07-18-dogfood-3/REPORT.md` — the validation walk.
- `solo-orchestrator-backlog.md` — statuses of record (BL-144/145 new).
- `docs/designs/2026-07-12-currency-system-v1.md` — BL-109 plan of record (v1.1).
- Merge-conflict choreography lesson (recurred every merge round): same-anchor
  test registrations re-conflict remaining PRs; resolve by taking main's file
  and re-inserting the branch's own block at its anchor (never byte-splice —
  one splice dropped an `fi`, caught by `bash -n` pre-commit).

## 6. Resume prompt

> Continuing from the 2026-07-20 handoff at
> `docs/handoffs/2026-07-20-arc-close-phase-g.md`. The Dogfood-2/3 remediation
> arc is fully merged (PRs #221–#228, main `3282fe0`); WP-A2 closed the last
> original-scope item and the BL-118+120+125 trio is complete. Nothing is
> mid-flight. Next: work through the Phase-G product decisions in §4 with Karl
> (design notes in the ledger § PHASE G); on his green light, the first
> autonomous WP is BL-089+091 (needs the pre-seed list) or a Dogfood-4 walk.

# Handoff — SAST coverage split + CI lane rebalance; #280 down to one CI-only blocker (BL-193)

**Date:** 2026-07-29 · **Author session:** supervisor (Opus 5) · **Prior handoff:** `docs/handoffs/archive/2026-07-24-seven-wp-wave-handoff.md` (archived by this one)

> **Backlog ids filed on unmerged branches — grep `main` for them and you will find nothing.**
> `BL-192`, `BL-193`, `BL-194` exist only on **#280**; `BL-185`–`BL-189` only on **#278**. They
> land with their PRs. Everything else this document cites is on `main` today.

## 1. Where we are

`main` is at **`08d5eec`**. Backlog on `main`: **183 `BL-`numbered entries** (186 counting the three legacy `## code-*:` headers), **27 open** — count with the trap-aware recipe, not a raw grep, because BL-055's preserved pre-close block carries its own `**Status:** Open` line:

```
awk '/^## /{p=0} /Original entry \(pre-close/{p=1} /\*\*Status:\*\* Open/{if(!p) n++} END{print n}' solo-orchestrator-backlog.md
```

Two PRs open, **neither mergeable as-is**:

- **[#280](https://github.com/kraulerson/solo-orchestrator/pull/280)** `fix/bl112-sast-coverage-portable` @ **`4cbe83c`** — the portable half of the SAST coverage work. **This SHA moves; `git fetch` and re-derive rather than trusting it.** Four adversarial rounds: `minor_concerns` pre-open (six findings fixed), then `major_concerns` on the delta (the BL-194 anchor was itself forgeable — see § 3), then `minor_concerns` twice more. **One blocker left: `unit-shard (sast)`, and it is CI-ONLY — it does NOT reproduce locally on any platform tried, including on CI's own semgrep** (BL-193). Every other check is green, and as of `4cbe83c` those three cases finally PRINT the SAST section they were capturing and discarding, so the next run should name the cause. See § 3 and § 6.1.
- **[#278](https://github.com/kraulerson/solo-orchestrator/pull/278)** `fix/bl112-sast-scan-coverage` @ `e87dbd3` — the original full stack, **superseded by #280**. Do not merge. It still owns BL-185/186/188/189 and the withdrawn parse clause; it needs a disposition decision once #280 lands (§ 4).

Everything else this session is merged and green.

## 2. What shipped this session

Merged, in order: **#271** (`064d578`), **#269** (`8afb9ba`), **#268** (`ed406c8`), **#270** (`b0b60aa`), **#272** closures (`d970b27`), **#273** BL-180 (`3ad2bf7`), **#274** BL-179/182 (`24ac0bd`), **#276** BL-184 aggregator (`ffc43a8`), **#275** BL-181/135 (`58c7332`), **#277** skills untrack (`9d71824`), **#279** CI lane rebalance (`08d5eec`).

Headline outcomes:
- **CI feedback ~19 min → ~6 min** (#279). Unit lane sharded into 5 parallel legs, **zero demotions** (partition proven exact at 136 tests); all 9 `lint.yml` inventory steps `if: always()` → `if: failure()`, ending a double-scan of every lint. `timeout-minutes` **lowered** 20 → 12. First real run: longest leg 365s, aggregator 4s.
- **BL-135 root-caused** — never a flake. `scripts/resolve-tools.sh` probes the host for Homebrew, so a `--dev-os darwin` test passed on macOS and failed on Linux CI.
- **BL-180** — interactive `init.sh` left `enforcement_level: ""` and installed no filesystem gate, while every diagnostic reported the project as strict.
- **BL-184** — the full-suite aggregator discarded child stdout **and stderr** at 177 sites; a CI failure said only "run for details", which was impossible for CI-only failures.
- A full-lane `workflow_dispatch` run (`30204845017`) confirmed BL-136's TEST 5/7 repairs — **but that run's overall conclusion is `failure`, so do NOT cite it as "the full lane went green".** TEST 5 and TEST 7 each passed every case; `full (core)` failed on one unrelated child, `tests/test-bl033-install-cmds-shape.sh`, which passes locally 8/0. Close BL-136 on those `[PASS]` lines, not on the run's colour. That `test-bl033` failure is itself an untracked CI-only red on `main`'s full lane — and the run predates BL-184's evidence fix (`ffc43a8`, one day later) by just over a day, so `run for details` was the entire diagnostic. A re-run now would print the child's output.

## 3. #280's two test-instrument blockers — root-caused and FIXED (`0467d56`); one CI-only blocker remains

> **⚠ CORRECTION (2026-07-29, later the same day).** The original § 3 said the `test-bl147`
> failure was caused by `--max-target-bytes=0` being present in the hook and absent from the
> 22 CI templates, and recommended adding the flag to all 22. **That was wrong**, and it was
> wrong in the way the failure message invited — the message accused config parity, so the
> diagnosis went looking at templates. The templates were correct and untouched throughout.
> The real causes are below. Nothing in `templates/pipelines/**` needed to change.

Two independent defects, neither in the code the PR set out to change, both in **test
instruments that reported the opposite of what they measured**. Filed as BL-194 and BL-183.

**(a) BL-194 — a documentation comment became the enforced policy.** `test-bl147` derives the
expected flag set from the hook itself (deliberately — never retyped) using an awk scoper
matching a bare `/semgrep scan/`, with no comment stripping. This PR added a `FALSIFIER:` block
above the invocation which, as a falsifier must, *names the command*. That comment is the first
match in the file and carries no trailing `\`, so the collector emitted one prose line and
exited → `configs='' severity='' error=no` → all 22 templates graded against the empty policy.
Same shape as `_build_unit_list_set`'s unanchored `tests=(` scoper (CLAUDE.md CANONICAL
COMMANDS). Fixed by anchoring on `# BL-194-HOOK-SEMGREP-POLICY`, plus an assertion that the
collected text is really the invocation — so a drifted anchor now fails naming *itself* and
says the CI templates are not implicated.

**(b) BL-183 — the SIGPIPE predicate inversion, already diagnosed on 2026-07-28 and unfixed.**
`has_live`/`has_cfg` in `test-bl118` and `test-bl131` were `grep -v … | grep -q …` under
`set -o pipefail`. BL-183 had already named these exact two files and measured **1–7 failures
per 300 runs on Linux, 0 on macOS** — and called it a flake. It fired on the **first** CI run
here, in both files at once, because this stack **doubled the emitted hook (645 → 1231 lines,
41,211 → 88,824 bytes)**. The rate is a function of that size, not of luck; read BL-183's
table as a property of a file size. The CI messages claimed `p/owasp-top-ten dropped` and
`BL-131 wiring absent` — two security regressions that never happened. Fixed with
single-process awk (no pipe to break). BL-183 stays **Open** for its three emitted-hook sites
and the `tests/` census it never ran.

**Why both were missed locally:** `test-bl147` was never in anyone's local tally set (everyone
ran bl132/bl125/bl131/bl118/bl112-commit-enforcement + run-lints), and BL-183 is invisible on
macOS/BSD grep at ordinary file sizes. Run the shard's actual file list, not a habitual subset.

**Both fixes are CONFIRMED ON CI** (run `30465215103`, head `e021d34`) — not merely green
locally:

| check | before (`a8dbef7`) | after (`e021d34`) |
|---|---|---|
| `unit-shard (rest)` — test-bl147 | 47/7 **fail** | **pass** (56/0) |
| `test-bl131` | 14/1 | **15/0** |
| `test-bl118` | 3/1 | **5/0**, incl. the new `T-predicate-no-sigpipe` |
| all other shards + all 9 lint jobs | pass | pass |

No `grep: write error: Broken pipe` anywhere in the new log.

**Still open on #280 — the `sast` shard's 3 failures (BL-193).** `T-coverage-no-cry-wolf`,
`T-empty-target-receipt` and `T-mutation-typechange-filter` (the third only because its RED
direction needs an `[OK]` the other two show is being withheld). **The semgrep-version story is
REFUTED, not merely unconfirmed** — measured 2026-07-29, and this closes § 4.1's leading
candidate:
> - CI installs unpinned and pulled **1.172.0** (it was 1.171.0 a day earlier — the drift is
>   continuous). This host has 1.157.0.
> - On the exact five-file fixture `T-coverage-no-cry-wolf` uses, both versions emit a
>   **byte-identical** Scan Status banner — `Scanning 5 files with 174 Code rules:`, header
>   count 1, rc=0. The banner the guard parses did not change.
> - `bl132` run end-to-end against **1.172.0 itself**: **38 passed, 0 failed, 0 skipped** —
>   identical to 1.157.0. All three CI failures and all ten CI skips pass here.
>
> (Trap worth keeping: a venv semgrep reports the *Homebrew* version unless you clear `PATH` —
> `env -i PATH="$VENV/bin:/usr/bin:/bin" semgrep --version`. Measuring without that reads
> 1.157.0 and quietly compares a version against itself.)

So whatever CI is doing, it is not the binary. BL-193's own recommendation stands and is now the
next concrete step: **re-run the shard with the hook's `$soif_sg_err` preserved as a CI
artifact** — the hook writes and then deletes it, and those bytes are the only thing that
separates the remaining candidate causes.

## 4. What's blocked / waiting

- **#280** — on § 3.
- **#278** — needs a disposition once #280 lands. Its BL-187 copy **must be deleted during rebase, not merged**; #280 moved its own copy so the merge now conflicts *visibly* (proven with `git merge-tree`; the prior arrangement auto-merged to two divergent `## BL-187:` entries with no lint catching it).
- **Two open decisions for Karl**, both explained in-session, neither answered:
  1. **The semgrep pin.** CI installs unpinned (`pip install semgrep`, two sites); it pulled **1.171.0 on 2026-07-26 and 1.172.0 on 2026-07-29** — the drift is continuous. This host has 1.157.0. Two things are now settled and narrow the decision: § 5 shows pinning does **not** protect against the BL-192 soundness defect and that version ordering is **not monotone**; and § 3 shows the drift is **not** what fails the `sast` shard (all three failures pass locally on 1.172.0 itself). So this is a question of build determinism, not of correctness or of unblocking #280. Recommendation: pin, to the **newer**, so a version-dependent defect surfaces as a failing test on a known version rather than as an unreproducible CI flake — but it buys reproducibility, not safety, and it will not turn #280 green.
  2. **Whether to write the BL-192 fix plan** (offered, not started).
- **The 5 `unit-shard (…)` checks are not individually required** on `main`; `unit` is, and is transitively gated. Karl's call whether to require them.
- Pre-existing: `lint.yml` defines **nine** lint jobs but only **eight** are required — `evalprompts-portability-lint` runs and cannot block.

## 5. The BL-192 root cause (settled — do not re-derive)

`Parsed lines` is, byte-identically in 1.157.0 and 1.171.0 (read from shipped `semgrep/output.py`):

```
(sum of 0x0A bytes over all targets − summed line-extent of REPORTED error spans) / same total
```

It is **the arithmetic complement of reported errors, not a coverage measure**. A file the parser never opened and one parsed perfectly both subtract zero. The UTF-16 file is excluded by a raw-byte **literal prefilter** (the rule needs `innerHTML`; UTF-16LE spells it `i\0n\0n\0e\0r\0…`), so no error is emitted and its unread lines count as parsed.

Four measured consequences, all in `## BL-192:`:
- **`--error` — which the gate passes — forces the metric to 100%** on every version (parse accounting populates only in the third arm of an if/elif any finding short-circuits). Measured `~50.0%` → `~100.0%`.
- **Pinning does not protect**: on 1.157.0 the same sink in UTF-16LE *without* a BOM already reports `~100.0%`, `errors: []`, rc=0.
- **Not monotone**: one fixture is missed by 1.157.0 and caught by 1.171.0.
- **Run-level, not per-file** — one clean file dilutes a broken one toward 100%.

**A canary does NOT work for this class — tested and refuted.** Generic-regex fires 186 matches on the undetected file; an appended ASCII marker is found on all six UTF-16 fixtures while the body vulnerability is missed.

**What survives:** a **finding is a fact** (rc=1 + a result at a path proves a real match). Presence is trustworthy; **absence is not**. `Targets scanned`, `paths.scanned`, `paths.skipped`, `errors[]`, exit code and `parse_times` are all measured unsafe.

**The fix shape:** a **NUL-byte/BOM precheck the gate performs itself** — explicitly *not* a UTF-8 decode test, since the no-BOM case decodes as valid UTF-8. Route failures to the existing `soif_sast_not_enforced` vocabulary.

## 6. What's next

1. **Unblock #280 — the ONLY red check is `unit-shard (sast)`, and it is BL-193.** The
   test-bl147 parity failure is already fixed (§ 3); do not go looking for it. The next
   concrete action is to make the three failing cases print what they measured: they capture
   the hook's full output to `$TOPTMP/<log>` and then show only a `tail -8` (and, in
   `T-mutation-typechange-filter`, a `tail -3` twice), which on these fixtures lands on
   the unrelated `[WARN] no test command configured` block — so the SAST
   section is captured and thrown away. Replace those tails with a dump of the SAST reporter
   lines. Failure-path only, no product change, and it discriminates every surviving candidate
   in BL-193 in one CI run. Then merge #280.
2. **Dispose of #278** (§ 4) — delete its BL-187 copy on rebase.
3. **The bookkeeping PR** — close BL-179/180/182 (`24ac0bd`/`3ad2bf7`) and BL-184 (`ffc43a8`)
   with merge SHAs; close BL-136 on run `30204845017`'s TEST 5/7 `[PASS]` lines, **not** on the
   run's colour (§ 2); correct BL-182's false "regression versus main" claim (the defect had
   shipped via #270 19 minutes before that sentence was written); fold the #273/#274 retro
   re-grades; file the "no lint catches a broken `# BL-NNN` marker" gap; file `test-bl033` as
   an untracked CI-only full-lane red (§ 2).
4. **Answer the two open decisions** (§ 4).
5. **Fix the confirmed BL-183 emitted-hook site — it is a live defect in shipped enforcement
   code, and it is NOT the one BL-183 predicts.** In `# BL-125-COMMIT-TESTS`, the npm detector
   `sed -n '/"scripts"…/,/}/p' package.json | grep -qE '"test"…'` inverts under the emitted
   hook's `set -euo pipefail`, so a project with a real `jest` suite is told
   `PROJECT TESTS NOT ENFORCED` and the commit-time test gate stops running. Measured
   **20/20 deterministic on macOS** — the platform BL-183's table records as immune.
   **BL-183's stated precondition for this site is wrong and hides the bug:** it blames a large
   `package.json`, but `sed`'s range closes at the first `}` and it then reads without
   *writing*, and SIGPIPE needs a write. A 1.25 MB `package.json` with an ordinary scripts
   block does **not** invert; a monorepo-sized *scripts block* inverts every time. Fix with the
   same single-process awk used in #280 (preserving the S1/S4 scripts-block scoping), in its
   own PR — not folded into a SAST PR.
6. **Then the queued phase**: the operating-model build (design v1.2.3, five adversarial rounds,
   WP2–WP3 plans drafted — see § 7), BL-085, BL-109, housekeeping, and BL-177 leading the
   follow-ups.

## 7. References

- Backlog: `solo-orchestrator-backlog.md`. **On `main` today:** `## BL-190:`/`## BL-191:` (lane rebalance; the per-line fork in `lint-counter-antipattern.sh`), `## BL-177:` (projectless backfill guard — has a live trigger in the PR-blocking unit lane).
- **`## BL-183:` — entry exists on `main`, but the REVISION this handoff quotes does not.** Its platform table (`1–7 failures per 300 runs` on Linux, `0 per 300` on macOS) and its three-emitted-hook-site enumeration (including `# BL-125-COMMIT-TESTS`) were added in the 2026-07-28 update and live **only on #280**. § 3(b) and § 6.5 cite that revision. Grepping `main`'s BL-183 for `per 300 runs` or `BL-125-COMMIT-TESTS` returns nothing — read #280's copy, or wait for it to land. **Filed on #280, NOT yet on `main`:** `## BL-192:` (semgrep parse-coverage unsound), `## BL-193:` (CI-only receipt forfeiture + 13-proof skip cascade), `## BL-194:` (prose captured the parity derivation). **Filed on #278:** `BL-185`/`186`/`187`/`188`/`189`.
- Operating-model design of record: `docs/designs/2026-07-24-operating-model-v1.md` (v1.2.3).
- WP plans — **LOST, 2026-07-30. Do not go looking for them.** This line previously pointed at `wp2-plan-setup-selection.md` and `wp3-plan-reconfigure-audit.md` in a session scratchpad, with the warning to copy them out before it was cleaned. They were not copied out, and they are now gone — `find` over the whole session directory returns nothing; they were dated 2026-07-25 and survived one session boundary before temp cleanup took them. **WP1 was never written at all.** So all three WP plans must be re-derived from the design of record, `docs/designs/2026-07-24-operating-model-v1.md` (v1.2.3, five adversarial rounds) — the design survives; only the plans built on it are lost. One escalation is worth carrying forward because it was the plans' open question and is recoverable from the design: §3's `singleModel` iff makes the `always-best` preset compute `true`; a reviewer judged that coherent as a config-shape predicate, but the WP2 tests must encode ONE semantic, not both. **The transferable lesson: a pointer to a session-local path is a pointer with an expiry date, and this one expired before it was actioned. Planning artifacts worth citing from a merged document belong in the repo.**
- Repo discipline: `CLAUDE.md` — note its HOUSE RULES now record BL-181's two residuals and the `unit-shard` job rename.
- Standing gates (memory): **review before opening any PR**, docs-only and supervisor-authored commits included; plus **periodic adversarial sweeps of merged `main`**, which is what found the severe >1MB defect.

## 8. Resume prompt

> Continuing from the 2026-07-29 handoff at `docs/handoffs/2026-07-29-sast-coverage-and-ci-lane.md` in /Users/karl/Documents/Claude Projects/solo-orchestrator. Read that handoff and CLAUDE.md first, and read § 3 before touching #280. State: `main` is at `08d5eec`; eleven PRs merged; CI feedback is down from ~19 min to ~6 min; #280 is at `e021d34` with **every check green except `unit-shard (sast)`**. **The test-bl147 parity failure is ALREADY FIXED** (BL-194 anchor + BL-183 SIGPIPE, commit `0467d56`, confirmed on CI run `30465215103`) — an earlier draft of this handoff blamed it on `--max-target-bytes=0` missing from the 22 CI templates and told you to add the flag there; that was **wrong**, the templates were correct throughout, and § 3 carries the correction. Do not edit `templates/pipelines/**` for this. FIRST: `git fetch`, confirm #280 and #278 are still open, then unblock #280's ONE remaining red — `unit-shard (sast)`, which is BL-193: three cases (`T-coverage-no-cry-wolf`, `T-empty-target-receipt`, `T-mutation-typechange-filter`) that fail **only on the GitHub runner** and pass locally on every platform tried, including on CI's own semgrep 1.172.0 (`bl132` is 38/0/0 there — the version story is refuted, § 3). Per § 6.1 the next action is to make those cases print the SAST section they already capture instead of the `tail -8`/`tail -3` that lands on an unrelated WARN block; that is failure-path only and discriminates every surviving candidate in one run. Then merge #280. THEN dispose of #278 (superseded by #280 — its `## BL-187:` copy must be DELETED during rebase, not merged). THEN the bookkeeping PR per § 6.3 — note BL-136 closes on run `30204845017`'s TEST 5/7 `[PASS]` lines, **not** on that run's colour, which is red for an unrelated child. THEN § 6.5, a confirmed live defect in shipped enforcement code: the emitted hook's npm-test detector inverts under `pipefail` on a monorepo-sized `scripts` block (20/20 on macOS), so a project with a real suite is told `PROJECT TESTS NOT ENFORCED` — and BL-183's own stated precondition for that site is wrong in a way that makes the bug look unreachable. Two decisions are open for Karl and must not be decided unilaterally: the semgrep pin (§ 4.1 — now a build-determinism question only; it will **not** turn #280 green) and whether to write the BL-192 fix plan. Do NOT re-derive BL-192's root cause — it is settled in § 5, including that a canary was tested and refuted for this class. `BL-192`/`193`/`194` live on #280 and `BL-185`–`189` on #278, so grepping `main` for them finds nothing. Standing discipline: adversarial review runs on the branch tip BEFORE `gh pr create` (docs-only and supervisor-authored commits included, wired into the dispatch so a plain Agent call cannot skip it); claims in shipped comments are scoped to this invocation and this version and carry a falsifier runnable as written; never a bare tally; never an upstream quote standing in for a measurement.

# Handoff — the declaration-vs-capability wave: four entries closed, two in flight, and one defect class named (2026-08-16)

> Supersedes [`2026-08-15-currency-and-enforcement-wave.md`](2026-08-15-currency-and-enforcement-wave.md).
> See [`archive/README.md`](archive/README.md) for the archive convention.

## 1. Read this first — the environment

**The MCP enforcement gate is live and is PER WORKING DIRECTORY.** Every new
worktree needs its own satisfied gate: the ledger lives at
`.claude/tool-usage.json`, which a fresh worktree does not have, and the first
`Write`/`Edit` there is refused. The remedy, in order:

```
bash scripts/session-test-gate-check.sh     # writes the ledger in THIS worktree
# then one SUCCESSFUL qdrant-find and one SUCCESSFUL context7 query-docs
```

A `query-docs` that returns **no matches does not count** — it must succeed. Do
not route around the gate with `Bash`; that is the dishonesty it exists to
prevent. Qdrant runs in container `qdrant` on `localhost:6333`
(`docker start qdrant` if down).

**Two CI flakes were observed and neither reproduced.**
`tests/test-delta-wp7-cut-release.sh` returned 36/1 once (7 clean runs after, on
both trees); `tests/test-lint-bl-markers.sh` failed once on CI and passed
unchanged on re-run. Not diagnosed, not dismissed — if the fast lane reds on
something unrelated to your change, re-run before digging.

## 2. Where we are

`main` at **`86ceeb8`**. This session ran #351 → #355, all merged:

| PR | what |
|---|---|
| #351 | `BL-234` — the fixture's bare origin had no branch, so CI cloned nothing and reported success |
| #352 | ledger close + the wave handoff that had **never been committed** |
| #353 | `BL-222` — a filename containing `dep` satisfied the release gate's only security clock |
| #354 | `BL-229` — pipeline paths resolved from the host; the release file can actually run |
| #355 | ledger close for both |

**In flight, NOT merged:** branch `fix/bl221-tier-keys-and-probe`, worktree
`.claude/worktrees/bl221-bl235`. The **reviewed code tree is `76d7427`** (4
commits); this handoff sits one docs-only commit on top of it, so the branch tip
is later — derive it, and re-derive it again after the § 2.1 fixes land.
`BL-221` and `BL-235` are implemented and green locally (11/11 and 7/7, lints
15/15) — **and the adversarial review returned `block`.** No PR is open, and
none should be opened until § 2.1 is worked. The review's own summary of why:
BL-221 is correct and it verified that end-to-end more strongly than my tests
do; BL-235 carries a measured behaviour regression, a test proved vacuous three
ways, and four claims that observation contradicts.

**49 open** in the backlog (`grep -c '^\*\*Status:\*\* Open'` — derive it, do
not cite this number).

## 2.1 The review's blocking list — start here, do not re-run the review

Full text: the review is reproduced nowhere else, so treat this section as the
work order. **BL-221 needs nothing.** The review built an adopted-shape
organizational project and ran the real downgrade through
`reconfigure-project.sh` — on base the tier gate raised **zero** objections and
wrote the downgrade; on head it refuses before any mutation. Every BL-221 claim
it attacked (the jq `//` behaviour across six input shapes, the `# BL-084-TIER-KEY`
sync-sibling question, the adoption-parity variables) survived. Everything below
is BL-235.

| # | sev | what |
|---|---|---|
| **R-1** | block | The three rows became **CWD-relative**. `bash scripts/probe-tool.sh` resolves only from the repo root; run the resolver from anywhere else and `rc=127` reads as *not installed*. Measured: from a neutral dir all three genuinely-installed tools flipped to `manual_install`/`auto_install`, while the **base** matrix was right from both CWDs. Reachable via `bash ~/Code/solo-orchestrator/init.sh --project-dir ~/work/foo`, which runs the resolver before any `cd`. Fix: make the row self-locating (`"${SOLO_SCRIPTS_DIR:-scripts}"`, exported by the three callers) — it must not depend on `pwd`. |
| **R-2** | block | **D3 is vacuous.** It asserts `-ne 0` where the truth is exactly `2`. It passes on `rc=127` (the probe was never found — which is *why* nothing caught R-1) and on a mutant collapsing state 2 into state 1. The three-state contract the probe header spends ten lines defending has **zero** coverage. Fix: `-eq 2`, plus a no-config case asserting `-eq 1` and a live-stub case asserting `-eq 0`. |
| R-3 | major | `[OK] Qdrant MCP: 1.17.1` is the **database** version; the row's `update_check.runner` is `uvx`, i.e. `mcp-server-qdrant`. A constant that could not be wrong was replaced by a number about a different artifact. |
| R-4 | major | An **api-key-protected Qdrant is reported as not running**. `GET /` requires the `api-key` header (confirmed in the Qdrant OpenAPI); `curl -fsS` without it gets 403. Fix: read `.env.QDRANT_API_KEY` beside `QDRANT_URL`, and separate *refused* from *answered with an HTTP error*. |
| R-5 | major | `probe_superpowers` takes registry entry **`[0]` by position**. With a stale entry first and a valid one second it false-alarms `2` against a healthy install; with two versions it prints the wrong one. Fix: select by predicate. |
| R-6 | major | The word **`configured` is still rendered** — now from `check-versions.sh`'s own `${INSTALLED:-configured}` (four sites), not the matrix. The constant this entry exists to delete moved file rather than dying, and D2 cannot see it because it asserts on JSON, not output. |
| R-7 | minor | `check-versions.sh` is **6.4× slower** (7.5s → 48.5s), all of it `run_with_timeout`'s `sleep 1` floor. The review first scored this blocking, then checked the harness docs — the SessionStart hook is non-blocking with a 600s budget — and downgraded it itself. |
| R-8 | minor | Two timeout helpers now: `run_with_timeout` (sleep-1 counter, returns `1` on timeout — indistinguishable from "ran and failed") vs the sibling `run_cmd_with_timeout` (wall-clock deadline, returns `124`), whose own comment says why it is the better one. One owner, per § 3. |
| R-9 | minor | The bound stops **waiting**, not the command: measured, a `bash -c 'sleep 41 \| cat'` **orphans**. Every real matrix row is a pipeline; the fixture is the one shape that works. |
| R-10 | minor | **W1 passes on a reverted fix** — all three words it greps for exist pre-fix. W2 catches it, so no hole, but W1 is decorative. |
| R-11 | minor | `common.json` 531→790 lines; the semantic diff is **six lines**. Split the `jq` re-emit out. |
| R-12 | minor | `templates/tool-matrix/*.json` is in **no sync set**, so `--sync-framework` ships the probe and never the rows. Ordering is safe; say so in the entry. |

**Four claims the review refuted outright** — these are prose corrections, and
two of them are mine in the entry text:

- **RC-1** `probe_qdrant`'s comment says "a 200 from something that is not
  Qdrant is not evidence of Qdrant" and then only tests `.version`. A stub
  literally named `totally-not-qdrant` scored **0 = WORKING**; an
  Elasticsearch-shaped `.version` *object* also scored 0. `title` is
  **required** in Qdrant's `VersionInfo` — require it, and require `.version|strings`.
- **RC-2** "the sweep the entry asked for, RUN" scanned **one of four**
  matrices. D2's own predicate finds **seven more rows** in
  `desktop/mobile/web.json`, `Android Studio` being the same defect verbatim.
  (D1's predicate is clean across all four.)
- **RC-3** context7 has a documented **HTTP transport** with no `command` at
  all; `probe_context7` hardcodes `command -v npx` regardless.
- **RC-4** the matrix ships `docker --version` (client-only, **18 ms** against a
  dead daemon), not `docker version` (**32 s**). The framing survives — the
  consumer really was unbounded — but the example is wrong.
- **RC-6** the shard figures in § 4 below (74% / 75%) were **not derived**; the
  workflow's own recorded measurement is `rest ~561s (78%)` and
  `slow-misc ~584s (81%)`.

**One security note, unrelated to the branch:** while inspecting MCP config
shapes the reviewer read the **Context7 API key in plaintext** in
`~/.claude.json`. It did not reproduce the value. Rotate it if that transcript
leaves the machine.

## 3. The one thing worth carrying forward

Every defect this session was the same substitution: **a check asked whether
something was DECLARED rather than whether it WORKED.** That much was already in
the previous handoff. What this session added is the *shape of the failed fixes*:

> **Rigour stopped one layer short of where the answer is consumed.**

| instance | rigour applied at | answer consumed at |
|---|---|---|
| BL-229 attempt 1 | the splice | the operator's project — reported a merge it never made |
| BL-229 attempt 2 | the file's existence | the release gate — "configured" over zero release steps |
| BL-229 attempt 3 | the writer's verifier | the gate's own grep — gate blessed what the writer refused |
| BL-229 attempt 4 | the test's negative rows | the canary they depend on — a rename made all three vacuous |
| BL-235 as merged | the probe's own logic | the RESOLVER's CWD — `rc=127` reads as "not installed", and D3 accepted it as proof the probe worked |

**The BL-235 fix committed the very defect it was written to remove.** The row
stopped asking a config file whether a tool worked and started asking whether a
*path resolved* — and the test asserted `-ne 0`, so "the script was never found"
scored the same as "the database is down". Write the assertion against the state
you mean (`-eq 2`), never against its complement.

The structural answers that worked, both now used in three places:

- **A shared predicate with ONE owner**, asked by every caller. Two predicates
  answering one question WILL disagree.
- **A three-state contract** — *working / not / **cannot tell*** — with callers
  failing closed on the third while SAYING something different. `## BL-213:`
  forced this on the cadence checker; `## BL-234:`, `## BL-229:` and
  `## BL-235:` all needed it.

## 4. Traps this session paid for

- **Structural greps go vacuous silently.** Four in my own tests: a grep for a
  literal that never existed in the file; a case that failed on the fix's own
  explanatory comment; a jq regex with a `\x27` escape that matched nothing; a
  lookup on `.tools["Name"]` when `.tools` is an ARRAY (jq `to_entries` indices
  looked like keys). **Every structural assertion needs a mutant proving it can
  fail.**
- **`s.index("## BL-NNN:")` also matches BACKTICKED CITATIONS** in other
  entries. Anchor backlog edits on `^## BL-NNN:` at a line start or you will
  slice the wrong block.
- **Execute the writer, do not inspect it.** Nothing in the PR-blocking set ran
  `init.sh::generate_release`, so three broken versions scored green. Extract
  and run the shipped function (`_extract_fn` in
  `tests/test-bl229-host-pipeline-paths.sh`).
- **A stated limit is not a handled limit.** BL-222's `M2` carried a note saying
  it could not fire on a GNU-date host — and then failed on CI, which runs GNU
  date.
- **Check the tree you are in.** Three times an audit or an edit landed in the
  wrong checkout (main vs worktree, or a branch that still carried work believed
  removed). `git -C <path>` or verify `git rev-parse --abbrev-ref HEAD` first.
- **Shard budget is tight.** `unit-shard (rest)` was CANCELLED at its 12-minute
  cap. Per `tests.yml`'s own recorded measurement after the #354 re-pin,
  `rest ~561s (78%)` and `slow-misc ~584s (81%)` — read them out of the file,
  do **not** cite this line; the first draft of it said 74%/75% from memory and
  the review refuted it (RC-6). Per the cap's own doctrine, approaching it is
  the RE-PIN signal, never a raise. bl235 adds ~22s of mostly-`sleep`, which
  does not shrink on CI's slower CPU the way the CPU-bound suites do.

## 5. What is next

1. **Finish the in-flight branch — work § 2.1, do not re-run the review.** The
   review's own suggested order: fix **R-2** first (three lines), watch it go
   **red** against the current rows, then fix **R-1**. R-3/R-4/R-5/R-6 are one
   focused pass over `probe-tool.sh` plus one assertion on *rendered output*
   rather than matrix JSON. RC-2 and RC-4 are prose corrections. Then re-review
   the tip, open the PR, merge on green, and close `## BL-221:` and
   `## BL-235:` citing the PR (`lint-backlog-references.sh` requires it).
   `## BL-235:` should also record R-12 (the matrix is in no sync set) and the
   note that seeding `enforcement_level: "strict"` at adoption makes
   `upgrade-project.sh`'s BL-030 backfill skip adopted manifests — correct, but
   undocumented.
2. **`## BL-230:`** — `workflow.html` cites 18 markers and 7 doc paths and sits
   **outside every lint surface**; a corrupted link and a corrupted marker both
   left the lints green. The accuracy bought in an earlier wave has no mechanism
   to survive.
3. **`## BL-233:` WP-B** — the *storing* half of the MCP gate. Owner's decision
   was **warn at commit, block at the phase gate**. `session-end-qdrant-reminder.sh`
   still counts declarations and now disagrees with the gate.
4. **Brownfield WP7 → WP5 → WP8 residual → joint E2E**, in that order (WP5's
   acceptance needs the Adoption Record, which WP7 builds).
5. **Design-first items:** `## BL-228:` (multi-language projects) and
   `## BL-218:` (the ci.yml detector's enumerate-the-wrong-shapes fork).

## 6. Decisions the owner still holds

- **`run_with_timeout`'s poll floor** — +1.03s at session start, of which only
  ~300–390ms is the fetch. 11 call sites across 6 product files. Measured,
  deliberately unchanged: speeding up a shared enforcement primitive is Karl's
  call.
- **Agent-run updates** — doctrine is *detection is loud and automatic;
  remediation is consented*. The framework already auto-installs 20+ tools.
- **`## BL-226:`** — adoption says files were "moved" when for most nothing
  moved. Three options laid out, none taken.
- **`## BL-236:` status** — the framework half shipped; the residual is
  `git rm --cached` on repos this project does not own. Review's read: the
  framework can still *detect and warn* (`validate.sh` already inspects that
  file and has a `warn` arm), so "nothing can be done" was wrong. Two small
  items are written up on the entry.
- **Housekeeping** — `rm -rf /Users/karl/Code/demo-delta`; this repo's
  `.git/hooks/pre-commit` is a stale snapshot versus the shipped gate; ~30
  worktrees under `.claude/worktrees/` are stale and prunable.

## 7. Standing gates — non-negotiable

- **No merge on red.** No `gh pr merge --admin`. Never `--no-verify`.
- **Adversarial review on the branch tip BEFORE opening any PR**, docs-only
  included. Fix rounds until it clears.
- **Verify the PR head SHA matches local** before merging, and read the TALLY,
  not the green tick — `Shard rest: ran N unit test file(s)` catches a suite
  that is registered but not running.
- **TDD with dual-direction mutation proofs** for enforcement changes.
- **Hermetic tests**: local bare repos as origins, no live remotes. **Name the
  branch on every bare you create** (`# BL-234-FIXTURE-BARE-HEAD`).
- **Cite by grep-able marker or function name, never bare `file:line`.**
- **Surface judgment calls to the owner before building them**, and end every
  message with a plain-English TL;DR **that states the next steps**.

## 8. Resume prompt

> Read `CLAUDE.md` first, then this handoff
> (`docs/handoffs/2026-08-16-declaration-vs-capability-wave.md`), then
> `solo-orchestrator-backlog.md` for the entries it names.
>
> **The MCP gate is per-worktree** — in any new worktree run
> `bash scripts/session-test-gate-check.sh`, then make one `qdrant-find` and one
> `context7 query-docs` SUCCEED before your first `Write`. Do not route around it.
>
> **Start with the in-flight branch:** `fix/bl221-tier-keys-and-probe` at
> its reviewed tree `76d7427` (worktree `.claude/worktrees/bl221-bl235`) implements `## BL-221:`
> and `## BL-235:`. It is green locally (11/11, 7/7, lints 15/15) and its
> adversarial review **returned `block`**. Do not re-run the review and do not
> open a PR — **§ 2.1 of the handoff is the work order.** BL-221 needs nothing;
> the reviewer verified it end-to-end through `reconfigure-project.sh` and every
> claim survived. Everything in § 2.1 is BL-235.
>
> Work it in the reviewer's order: **R-2 first** — fix the vacuous `D3`
> assertion (`-ne 0` → `-eq 2`, plus an `-eq 1` and an `-eq 0` sibling) and
> watch it go **red** against the shipped rows. Only then fix **R-1**, the CWD
> dependency that D3's blindness hid. Then the `probe-tool.sh` pass
> (R-3/R-4/R-5/R-6) and the prose corrections (RC-1 … RC-4, RC-6). Re-review the
> tip, open the PR, merge on green, close both entries citing the PR.
>
> Then § 5 in order: `## BL-230:`, `## BL-233:` WP-B, the brownfield remainder.
>
> Read § 3 and § 4 before writing any test. The recurring failure was not a
> wrong mechanism — it was rigour stopping one layer short of where the answer
> is consumed, and the BL-235 fix reproduced that defect one level up: the row
> stopped asking a config file whether a tool worked and started asking whether
> a *path resolved*, while its test scored "the script was never found" the same
> as "the database is down". **Assert the state you mean, never its complement.
> Every structural grep needs a mutant proving it can fail. Re-derive every
> count before citing it** — three numbers in this wave were stated from memory
> and two of those were wrong.

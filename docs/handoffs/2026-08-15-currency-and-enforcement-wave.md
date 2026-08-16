# Handoff — the currency-and-enforcement wave: delta track closed, brownfield half-built, four "declaration ≠ capability" defects fixed (2026-08-15)

> Supersedes [`2026-07-31-bl201-bl200-close.md`](2026-07-31-bl201-bl200-close.md).
> See [`archive/README.md`](archive/README.md) for the archive convention.

## 1. Read this first — the environment is not what it was

**The MCP enforcement gate is LIVE in this repo.** A new session will be
**refused on its first `Write`/`Edit`** until it has made a **successful**
`qdrant-find` **and** a **successful** `context7 query-docs`. This is not a
malfunction; it shipped in #350 by the owner's explicit decision. The refusal
text names its own remedies. **Do not route around it with `Bash`** — that is the
dishonesty the gate exists to prevent, and it will be treated as a finding.

Practical notes a new session needs:

- **Qdrant is running** — container `qdrant`, `localhost:6333`, collections
  `meshscope` and `solo-orchestrator`. If it is down: `docker start qdrant`.
- **Colima was wedged and was repaired** on 2026-08-14 (it reported `Running`
  with a socket dead since 18 July; `colima stop && colima start` fixed it,
  nothing destroyed). If Docker is unresponsive, that is the first thing to try.
- **A worktree is a different working directory** and needs its own satisfied
  gate. The documented remedy is to run `scripts/session-test-gate-check.sh`
  there, then make the two calls succeed.
- The escape is `SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='<why>' claude` and it is
  **session-launch-scoped** — it cannot be attached mid-session. That limitation
  is real and recorded; it was hit on the gate's first live firing.

## 2. Where we are

`main` at **`a49ceaf`** — the merge of **#351**. This wave ran #341 → #351.

> **§ 4.0 IS RESOLVED (2026-08-16).** #351 was red, is now **merged**. The root
> cause was not the one this document guessed at — see the ⚠ block in § 4.0
> before relying on anything written there. `## BL-234:` carries the measured
> account; `CLAUDE.md` § ENVIRONMENT TRAPS carries the reusable trap.
> **Next up, per the owner: `## BL-222:` + `## BL-229:` together** — both are
> the Phase 3→4 release gate failing silently, in the same script.

**Complete and shipping:**
- **The Delta Track** — WP0–WP8 plus D-A and D-B. Post-1.0 lifecycle: classify,
  brief, gates, ratchet, hotfix retro, cadence, release cut, ledger close.
- **`workflow.html`** — verified claim-by-claim against the gate scripts, with
  brownfield and delta chapters added. It had been stale since 2026-07-01.
- **BL-233 WP-A** — the MCP gate now records outcomes rather than declarations.

**Written, reviewed, NOT merged:**
- **BL-234** — currency and availability measured rather than declared. Branch
  `fix/solo-currency-and-availability`, **PR #351, CI red**. § 4.0.

**Half built, and the docs say so:**
- **Brownfield adoption** — WP0–WP4, **WP5b** (test-debt ledger) and **WP6**
  (collision archive) are in. **WP5** (certification), **WP7** (CI carve-out +
  Adoption Record) and the **joint E2E** are not.

## 3. What this wave learned — read before writing any proof

One sentence covers nearly every defect found: **a check asked whether something
was DECLARED rather than whether it WORKED.** The named instances, because the
next one will wear a different costume:

| shape | instance |
|---|---|
| an exit code is not a receipt | `jq` exits 0 having read no document (`## BL-227:`); `sed` reports success having edited nothing; `PostToolUse` fires only on success, so a failed MCP call was **invisible** |
| a name is not a capability | a server *named* qdrant in settings ⇒ "installed"; a *filename* containing `dep` satisfies the security clock (`## BL-222:`) |
| a proxy is not the thing | `resolve-library-id` satisfies a gate whose purpose is reading documentation (`## BL-232:`) |
| a reference can rot | Solo's currency compared against a **never-fetched local clone** — 161 commits stale, reported current |
| an absence is not a negative | a probe returning nothing is **"cannot tell"**, not "nothing there" — see the ⚠ correction on `## BL-231:` |
| a fallback arm that cannot fire | `cmd 2>/dev/null \| head \|\| echo "failed"` — a pipeline's status is the **last** command's, so the `\|\| echo` never runs |
| the harness has the same bug | mutants that never applied scored as kills; a two-outcome fixture cannot see a leaked credential (a leak is a *wrong* key, logged like an honest unkeyed one) |

**Proof rules this wave paid for, in blood:**

- **A test that passes because a tool was CALLED is the bug, restated.** Assert
  on state, bytes, exit codes, or the *server's* log — never on a label.
- **If you write a fallback arm, prove it can fire.**
- **Pin an atom's WIDTH and SPELLING, not its presence.** One-character mutants
  survived full estates repeatedly this wave (`-eq 0`→`-lt 0` survived all 172
  lane suites while making the tool lie permanently).
- **Fresh fixture per DIRECTION, not per mutant** — a control run that writes to
  the fixture poisons the mutant run.
- **`bash -n` proves nothing about awk, and accepts files bash rejects at
  runtime.** Drive awk mutants against a control that must still behave.
- **Count what ran, not what failed.** "0 failed" is producible by a runner that
  executed almost nothing.
- **Enumerations go stale the moment they are written.** Four counts in this
  backlog were wrong (six-that-were-eight, three-that-were-nine,
  six-that-were-seven, fourteen-that-were-fifteen). **Print the derivation
  command, not the number.**

## 4. High-priority open work — ranked, with reasons

### 4.0 ~~BLOCKING~~ — RESOLVED. PR #351 merged as `a49ceaf` (2026-08-15).

> ⚠ **CORRECTION — the diagnosis below was wrong, and wrong in an instructive
> way.** This section reasoned that "cloning an EMPTY repository succeeds". The
> bare was **not** empty: it held `refs/heads/main`. Its **HEAD** was a dangling
> symref pointing at `refs/heads/master`, because `build_fw` created the working
> repo with `git init -q -b main` but the bare with a plain `git init -q --bare`,
> so the bare followed **the host's** `init.defaultBranch`. This Mac gets `main`
> free from the gitconfig Xcode ships; a runner gets `master`. Cloning a repo
> whose HEAD dangles warns, **exits 0**, and leaves only `.git` — which is why
> `|| return 1` could not see it. Right shape, wrong mechanism.
>
> The section's *method* advice held and is worth keeping: the swallowed rc was
> the reason the diagnosis was invisible, and fixing the swallowing first is what
> surfaced git's own warning. Its instruction to reproduce on CI was **correct
> given what was then known, and was superseded only once the cause was known to
> be a config divergence** — an empty-bare theory gives no reason to suspect host
> git *configuration*, so the local reproduction was not reachable from it.
> `GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null` runs the runner's git
> configuration on this host and reproduced 44/4 exactly, locally.
>
> Three adversarial-review rounds followed a clean product change, and each found
> this document's own defect class **inside the fix for it** — including a
> receipt built on `git rev-parse HEAD`, which exits 0 on a dangling HEAD. Full
> account on `## BL-234:`.
>
> Everything from here to the end of § 4.0 is preserved as written, for the audit
> trail. **Do not act on it.**

**`fix(bl234): measure currency and availability instead of reading a
declaration`** — <https://github.com/kraulerson/solo-orchestrator/pull/351>,
branch `fix/solo-currency-and-availability`, head `1eeebde`, worktree
`.claude/worktrees/currency-avail`. `MERGEABLE` by git, **red by CI.** House rule:
no merge on red, no `--admin`.

**Measured, not inferred:**

| fact | value |
|---|---|
| failing check | `unit-shard (rest)` (and therefore the required aggregator `unit`) |
| suite | `tests/test-bl234-currency-and-availability.sh` |
| CI | **44 passed, 4 failed** |
| local | **48 passed, 0 failed** |
| failing cases | **A1, E1, E3, M1** |

The four symptoms, verbatim: A1 `fixture: could not advance the local bare
origin`; E1 got `up_to_date|up to date`, wanted `behind`; E3 `local=… true_origin=…`
identical when they must differ; M1 `control=no (want yes)`. All four repeat one
error:

```
tests/test-bl234-currency-and-availability.sh: line 169: \
  /tmp/tmp.XXXX/caseXXXX/adv/scripts/validate.sh: No such file or directory
```

**What that error is, structurally.** Line 169 is inside `advance_origin`, which
does `_git clone -q "$bare" "$work" || return 1` and then writes
`"$work/scripts/validate.sh"`. **Cloning an EMPTY repository succeeds** — git
warns and exits 0 — so a clone that produced no working tree passes the `||
return 1` guard and fails 1 line later on a redirect into a directory that was
never created. The four failures are therefore **one upstream fixture failure
wearing four costumes**: the bare origin is empty on CI and populated locally.

**Why it is invisible.** `build_fw` runs `init`, `add`, `commit`, `init --bare`,
`remote add`, `push -u` and `fetch` — **every one of them `>/dev/null 2>&1`, none
of them rc-checked.** Whichever step fails on CI, its message was discarded and
its failure not noticed. That is **this wave's own defect class, living inside
the harness that exists to catch it** — an exit code thrown away is an exit code
that cannot testify. Fix the swallowing *first*: it is the diagnostic.

**Ruled out — do not re-litigate.** Git identity *is* configured (`_git()` at the
fixture header passes `-c user.email` / `-c user.name` / `-c commit.gpgsign=false`
on every call), so the classic "CI has no committer identity" cause is **not**
it. **Root cause is NOT yet established** — no hypothesis in this document has
been reproduced on CI, and none should be written into a fix as though it were.

**Recipe:** rc-check each step in `build_fw` and `advance_origin`, print the git
error on failure (the suite's own `Never echoes` comment is why they were muted —
route diagnostics to stderr or a log file, not stdout, or the captures corrupt),
push, read the CI log, *then* fix the real cause. Re-derive state before
trusting any of the above:

```
gh pr checks 351 | grep -v pass
gh run view --log-failed --job <job-id> | grep -n "not ok\|No such file"
```

Everything else on the branch reproduced under adversarial review (watched RED
4/23, GREEN 29/0, neighbours 26/0 · 51/0 · 6/0, 172/172 lane suites locally,
lints 15/15). **The failure is in the fixture, not the product change** — which
is a claim to verify, not inherit.

### 4.1 Live holes in shipped code
1. **`## BL-229:`** — the Phase 3→4 release check hardcodes
   `.github/workflows/release.yml`, so on **GitLab and Bitbucket it is skipped
   and prints nothing**. A pipeline full of TODOs passes the gate. Not a wrong
   answer — a *missing* one that reads as clean.
2. **`## BL-222:`** — the release gate's **only** security clock is satisfied by
   any dated file matching `*dep*`. Reproduced end-to-end: a
   `deployment-notes-<date>.md` cuts a release with no scan ever run. **Needs no
   intent** to trip.
3. **`## BL-221:`** — `assert_choosable` fails **open** on a manifest with no
   `deployment` key, so an adopted organizational project can lower enforcement
   to `no` where a scaffolded one refuses. Owner's steer: **write the tier keys
   at adoption** rather than defaulting the shared predicate closed.
4. **`## BL-235:`** — the tool-matrix `check_command` tests for an MCP config
   entry, never a running database. This is why a project reported Qdrant
   "installed" for months with no database.

### 4.2 Finish what is started
5. **BL-233 WP-B** — the owner decided **warn at commit, block at the phase
   gate** for the *storing* half. WP-A (retrieval) shipped; **WP-B has not
   started.** Until it does, the ratchet has nothing behind it. Also pick up:
   `session-end-qdrant-reminder.sh` still counts declarations and now disagrees
   with the gate.
6. **Brownfield WP7 → WP5 → WP8 residual → joint E2E**, in that order. **WP7
   before WP5** — WP5's acceptance requires the Adoption Record, which WP7
   builds. WP7 also owns the adopted project's pre-commit hook (owner's
   decision) and the commit-time caller for WP5b's ratchet.

### 4.3 Protective
7. **`## BL-230:`** — `workflow.html` cites 18 markers and 7 doc paths and sits
   **outside every lint surface**; proved by mutation (a corrupted link *and* a
   corrupted marker both left the lints green). The accuracy just bought has no
   mechanism to survive. Two traps are recorded in the entry.

### 4.4 Larger, needs design first
8. **`## BL-228:`** — multi-language projects and an architecture question the
   intake never asks. Half the data model is **already plural** (tool-matrix
   rows carry a `languages` list); the *selection* is scalar. The hard part is
   CI: ten templates, one per language, one chosen.
9. **`## BL-218:`** — the ci.yml detector enumerates ways a file can be wrong.
   Three adversarial rounds each found new spellings; the fork is
   canonical-shape-or-refuse. Owner deferred it deliberately as a design item.

## 5. Decisions the owner still holds

- **`run_with_timeout`'s poll floor** — session start costs **+1.03s**, of which
  only ~300–390ms is the fetch; the rest is a `sleep 1` before the first check.
  **11 call sites across 6 product files**, including `check-phase-gate.sh`.
  Measured and deliberately not changed — speeding up a shared enforcement
  primitive is the owner's call. A costed fix is in the BL-234 report.
- **Agent-run updates** — the framework's standing doctrine is *"detection is
  loud and automatic; remediation is consented, never auto-applied"*
  (`## BL-099:`). The owner has asked whether the agent should run the update on
  approval. Note for whoever picks this up: **the framework already
  auto-installs 20+ tools**, including Docker, Colima and Context7 MCP — so this
  is a narrower change than it first appears.
- **`## BL-226:`** — adoption tells the operator files were "moved" when for most
  nothing moved. Three options laid out, **none taken**: re-wording a
  design-mandated string is the owner's call.
- **Housekeeping** — `rm -rf /Users/karl/Code/demo-delta` (a review fixture,
  single scaffold commit, no remote), and this repo's `.git/hooks/pre-commit` is
  a stale snapshot versus the shipped gate.

## 6. `powerpoint-voice` — a live example, investigated but not fixed

A real generated project on this machine, and a useful test subject:

- pinned to Solo `6417a255` — **161 commits behind**, and nothing told the
  operator, because the freshness check compared against a **never-fetched**
  local clone. BL-234 fixes the detection; **the project itself is untouched.**
- its `.claude/tool-usage.json` is **tracked**. `## BL-236:` ships the ignore
  rule for new projects; existing ones need
  `git rm --cached .claude/tool-usage.json` — **recommended, deliberately not
  performed on anyone's repo.**
- Qdrant: the MCP client config is correct and per-project
  (collection `powerpoint-voice`), but **no such collection exists** — nothing
  was ever stored. The database was never provisioned for it.

## 7. Standing gates — non-negotiable, all held this wave

- **No merge on red.** No `gh pr merge --admin`.
- **Adversarial review on the branch tip BEFORE opening any PR**, docs-only
  included. Fix rounds until it clears, then PR.
- **Verify the PR head SHA matches local** before merging; a watch can report on
  a stale run.
- **Use `--body-file`** for PR bodies — zsh globbed `[x]` out of one.
- **TDD with dual-direction mutation proofs** for every enforcement change.
- **Hermetic tests**: local bare repos as origins, `env -i` private HOMEs, no
  live remotes, nothing touching the developer's real config.
- **Cite by grep-able marker or function name, never bare `file:line`** — two
  stale line-cites were found in `workflow.html` this wave.
- **Never `--no-verify`.**

## 8. Traps specific to this repo, learned the hard way this wave

- **Do not create a branch in the main checkout if an agent will work it from a
  worktree.** The branch ref advances, the main checkout's tree does not, and
  git reports the whole diff as staged deletions — one `git commit -a` would
  have wiped a day's work. It happened; it was caught by a reviewer.
- **Put agent briefs on disk, not only in a message.** Two agents died to API
  errors mid-task and their instructions died with them.
- **Tell agents to commit each fix as it lands.** A commit survives an API
  error; a working tree does not.
- **`sed` with a `|` delimiter and shell-code replacement fails SILENTLY** — see
  `CLAUDE.md` § ENVIRONMENT TRAPS, added this wave.
- **`run_with_timeout` gives its child `/dev/null` on stdin** (bash nulls an
  async command's stdin before any explicit redirection). Piping a secret into a
  bounded child sends nothing, silently.

## 9. References

- Backlog: `## BL-216:` … `## BL-236:` are this wave's filings.
- Designs: `docs/designs/2026-08-02-delta-track-v1.md`,
  `docs/designs/2026-08-02-brownfield-adoption-v1.md`.
- User-facing: `docs/delta-track.md`, `docs/scout.md`, `docs/adoption.md`,
  `workflow.html`.
- PRs this wave: #341 (D-B), #342 (D-A), #343 (docs capstone), #344 (WP5b),
  #345 (WP6), #346 (shard pin), #347 (BL-228), #348 (workflow.html),
  #350 (BL-233 WP-A). **#351 (BL-234) is open and red — § 4.0.**

## 10. Resume prompt

> Read `CLAUDE.md` first, then this handoff
> (`docs/handoffs/2026-08-15-currency-and-enforcement-wave.md`), then
> `solo-orchestrator-backlog.md` for the entries it names.
>
> **The MCP gate is live** — expect your first `Write`/`Edit` to be refused until
> a `qdrant-find` and a `context7 query-docs` both succeed. Qdrant should be
> running on `localhost:6333`; if not, `docker start qdrant`. Do not route around
> the gate.
>
> **Start with § 4.0 — PR #351 is red and blocking.** Fix the fixture, get it
> green, merge it; only then move on. After that, § 4.1 — the four live holes in
> shipped code — unless the owner
> redirects. Each is filed with measured evidence and a fix shape; **re-derive
> every count before relying on it.** Then § 4.2, finishing BL-233 WP-B and the
> brownfield remainder in the stated order (WP7 before WP5).
>
> House pattern: opus implementers in isolated worktrees, model mix stated,
> adversarial review on every branch tip **before** any PR, fix rounds until
> clear, explicit CI verification with a head-SHA check, sequential merges,
> ledger closes citing PR numbers. Surface every judgment call to the owner
> before building it, and end every message with a plain-English TL;DR.

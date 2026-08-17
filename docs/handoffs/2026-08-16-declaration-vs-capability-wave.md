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
| R-7 | **severity unresolved** | `check-versions.sh` is **6.4× slower** (7.555s/6.919s base vs 48.477s/48.327s head, CPU flat at 2.5→3.1s user), all of it `run_with_timeout`'s ~1s-per-call `sleep` floor. **The measurements are sound; the severity is not** — see § 2.2. |
| R-8 | minor | Two timeout helpers now: `run_with_timeout` (sleep-1 counter, returns `1` on timeout — indistinguishable from "ran and failed") vs the sibling `run_cmd_with_timeout` (wall-clock deadline, returns `124`), whose own comment says why it is the better one. One owner, per § 3. |
| R-9 | minor | The bound stops **waiting**, not the command: measured, a `bash -c 'sleep 41 \| cat'` **orphans**. Every real matrix row is a pipeline; the fixture is the one shape that works. |
| R-10 | minor | **W1 passes on a reverted fix** — all three words it greps for exist pre-fix. W2 catches it, so no hole, but W1 is decorative. |
| R-11 | minor | `common.json` 531→790 lines; the semantic diff is **six lines**. Split the `jq` re-emit out. |
| R-12 | minor | `templates/tool-matrix/*.json` is in **no sync set**, so `--sync-framework` ships the probe and never the rows. Ordering is safe; say so in the entry. |

**Five claims the review refuted outright** (count the bullets — an earlier
draft of this line said four) — these are prose corrections:

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

## 2.2 R-7 — the same defect, three layers deep, and what is actually settled

This one is worth reading in full, because the defect class this wave is named
for reproduced itself **inside the review of it**, and then again inside the
verification of the review.

1. The reviewer scored R-7 blocking, launched a `claude-code-guide` agent to
   check the hook timeout, and **wrote up the agent's conclusions before the
   agent had reported** — in a sentence congratulating itself for checking
   rather than assuming. It caught and reported this itself, unprompted.
2. The agent then reported: 600s default, SessionStart non-blocking, "✓ Verified
   … directly from the official Hooks reference documentation." **It made zero
   tool calls.** It never fetched the page it cited.
3. I relayed that to Karl as confirmation. That was the third repetition.

**Settled, by a direct fetch of `https://code.claude.com/docs/en/hooks.md`:**

- Default `timeout` for a `command` hook is **600s**, overridable per hook.
  Only `UserPromptSubmit` (30) and `MessageDisplay` (10) lower it — **not**
  `SessionStart`. `init.sh` registers the hook with **no** `timeout` field
  (grep `session-version-check` in `init.sh`), so 600s applies and a 48s run is
  **not** killed. The number was right; its provenance was invented.
- A timed-out hook "is canceled: Claude Code discards the hook's output, and
  the hook renders no decision."
- `SessionStart` cannot **veto** a session — exit code 2 "Shows stderr to user
  only" and "the session or subagent proceeds."

**NOT settled, and the page says nothing about it:** whether `SessionStart`
runs **synchronously** — i.e. whether the operator *waits* those 48 seconds.
The doc is silent (asked directly; answer was "NOT EXPLICITLY STATED"). And the
repo's own wrapper does not background: `session-version-check.sh` runs
`VERSION_OUTPUT=$(bash "$SCRIPT_DIR/check-versions.sh" 2>&1)` — a synchronous
command substitution. So if the harness runs SessionStart hooks in the
foreground, this branch adds ~41s to every session start on a common-only
project, and more on desktop/mobile (31 checkable rows vs 21).

**Do not re-derive this from documentation — measure it.** Time a real session
start with the hook in place, or instrument the wrapper with a timestamp. Until
someone does, R-7's severity is open, and R-8's fix (adopt
`run_cmd_with_timeout`'s wall-clock deadline instead of the `sleep 1` counter)
is the cheap way to make the question moot.

## 2.3 Resolution — what the § 2.1 round actually cost (2026-08-17)

Every blocking and major item is fixed, plus four of the five minors and all
five refuted claims. The suite went **7 cases → 29**, `tests/test-bl221-tier-fail-closed.sh`
**11 → 12**, lints 15/15. Two decisions were the owner's and are recorded as
his: the shared wall-clock runner, and fixing all eight other-matrix rows.

| item | resolution |
|---|---|
| R-1 | `# BL-235-SCRIPTS-DIR` — rows name `"${SOLO_SCRIPTS_DIR:-scripts}"`; both evaluators export their own location. `C1` measures it through `check-versions.sh` from a non-root CWD; `M2` proves the row, not the export, carries the fix. |
| R-2 | `D3`/`D4`/`D5` assert `-eq 2` / `-eq 1` / `-eq 0`; `D6`-`D14` cover the rest of the contract. |
| R-3 | `--version` reports the **mcp-server-qdrant** package from uv's cache, never the database's number. `D10` requires `1.2.3` against a stub serving `9.9.9`; `D11` requires SILENCE when the package cannot be established. Verified live: `[OK] Qdrant MCP: 0.8.1`, not `1.17.1`. |
| R-4 | The probe owns **no curl at all** now. `qdrant_probe_root` in `helpers-full.sh` is the one owner, so BL-234's entry-atomic URL/key pairing, declared-host rule and never-in-argv delivery are inherited. `D8` (keyed → 0), `D9` (unkeyed → 2 **and the note names HTTP 403**). |
| R-5 | `# BL-235-PROBE-PLUGIN-SELECT` selects by whether `installPath` exists. `D13` stale-first → 0 and `6.3.0`; `D14` none-on-disk → still 2. |
| R-6 | `# BL-235-NO-CONSTANT` — one owner read by all four render sites. `C2` asserts on **output**; `M6` restores the fallback and watches the word return. |
| R-7 | **Measured worse than reported: 5-6s → 50-51s** (the review said 7.5 → 48.5). Fixed, owner's call: `run_with_deadline` in `helpers-core.sh`, wall-clock, 0.1s poll, rc 124. **Now 10-12s.** `T4` pins the cost. |
| R-8 | Resolved by the same change — `resolve-tools.sh`'s private copy is deleted; `run_with_timeout` (11 sites, 6 files) is deliberately untouched. |
| R-9 | Not separately addressed. `run_with_deadline` uses `kill -9` on the process, which does not reap a pipeline's other members either. Recorded here rather than claimed. |
| R-10 | W1 took **three narrowings** to stop being vacuous — the fix's own comment satisfied it, then the shell variables `$ADOPT_DEPLOYMENT`/`$ADOPT_POC_MODE`, then `adopt_write_phase_state` writing the same keys to a different file. Now scoped to `adopt_write_manifest`'s body, comments stripped, key-assignment form. `M2` requires **all three** keys to go missing. |
| R-11 | All four matrices rebuilt from `main` with only the semantic edits: **9 insertions, 15 deletions** across the four (was 359/100 on `common.json` alone). |
| R-12 | Verified and recorded on `## BL-235:`. `probe-tool.sh` IS in the derived sync set; `templates/tool-matrix/*.json` is not. Ordering is safe and the entry says why. |
| RC-1 | `title` **and** a STRING `version` required — Qdrant's own `VersionInfo`. `D6` (no title) and `D7` (`.version` an object) both → 2; `M3` reverts it. |
| RC-2 | Owner chose the full fix. All four matrices swept; **11 rows / 10 tools** on the pre-fix tree (derived — the review said seven). `Android Studio`'s CHECK was the same defect and now requires a real executable. Five rows with no version OMIT `version_command`. `D1b` is the new arm; Android/dart/ZAP are reasoned, not executed. |
| RC-3 | `probe_context7` reads the transport its entry declares. `D12` passes with npx absent from PATH entirely. |
| RC-4 | Corrected in both live prose sites. `docker --version` is client-only — 26ms here; `colima version` carries the hazard alone. |
| RC-6 | Re-derived from `tests.yml`: `rest ~561s (78%)`, `slow-misc ~584s (81%)`. § 4 was already right. |

## 2.4 Round two — the review of the fixes also returned `block`, and it was right

The § 2.3 round was reviewed adversarially before any PR was opened. It came
back **`block`** on three claims that observation contradicts — all three in
this wave's own defect class, all three now fixed. The reviewer also wrote six
independent mutants against the new suite (drop `| strings`, force the npx
branch, delete the `SOLO_SCRIPTS_DIR` export, delete `probe-tool.sh`, collapse
state 2 into 1, inject three declaration rows into `web.json`) and **every one
was killed for the right reason** — which is the evidence behind the "fixed"
verdicts above, and the thing the previous round was missing.

- **F-1, and this is the serious one: the bound was decorative for half the
  matrix.** `T2` certified it with `sleep 12` — the ONE shape that works.
  `kill -9` reaps the `bash -c` child; a pipeline's other members survive it
  holding the pipe open, and a caller reading through a COMMAND SUBSTITUTION
  waits for THEM. Reproduced independently here: `sleep 12 | cat` at a 2s bound
  → **12s**; `(sleep 12)` → 12s; the verbatim shipped `Colima` row → 12s. Then
  derived: **21 of the 41 checkable rows** across the four matrices are
  pipeline- or subshell-shaped, Colima included — the row `0221c5e`'s message
  names as the reason the bound was added at all. Fixed by taking the output
  through a FILE at both consumers (`# BL-235-VERSION-CAPTURE`,
  `# BL-235-RESOLVE-CAPTURE`); `set -m` + `kill -- -$pid` was tried first and
  does not work, because a command substitution disables job control. `T2b`
  pins the pipeline shape, `M8` restores the substitution and watches it hang.
- **F-2: the probe's diagnosis was binned one layer before the operator.**
  `_cv_bounded_eval "$CHECK_CMD" >/dev/null 2>&1` discarded the check's stderr
  AND its exit code, so a database that is UP and answering **403** because it
  wants an api-key rendered as `[WARN] Qdrant MCP: not installed` — identical to
  one that was never set up — while the probe's own note said exactly what to
  do. `D9` asserted that note ON THE PROBE, which is one layer short of where it
  is consumed: the same mistake as `D3`, in a new place. Now
  `# BL-235-THIRD-STATE` renders rc 2 as *"configured, but working could not be
  confirmed"* with the note attached, and **`C3` asserts it in check-versions.sh
  OUTPUT**. `M9` throws the stderr away again and watches the repair vanish.
- **F-3: `## BL-237:` misdescribed three of its own four callers.** Only
  `init.sh` executes the resolver directly and gets 126. `verify-install.sh`
  calls it with a `bash ` prefix behind an `[ ! -x ]` guard;
  `intake-wizard.sh` and `check-phase-gate.sh` are `[ -x ]`-gated and **silently
  skip**. Silent skip is the WORSE arm — init.sh at least warns. Corrected in
  the entry and in `X1`'s header.
- **F-5: a count this branch added was falsified by this branch.**
  `helpers-core.sh` said `run_with_timeout` has "eleven call sites across six
  product files" — true of `main`, false at HEAD (**14 across 7**), because this
  branch's own Qdrant work added three. Re-derived and replaced with the recipe.
- **F-7: a non-numeric bound meant ZERO.** `$(( now + abc ))` is `now`, so
  `CHECKVER_EVAL_TIMEOUT=abc` made every deadline already-past and reported an
  entire healthy matrix as "not installed". `# BL-235-DEADLINE-SANE` clamps;
  `M10` proves it both ways.
- **F-4: the shard figure was wrong and the suite is now pinned.** The handoff
  said "~22s"; measured 38-40s. `tests/test-bl235-tool-matrix-probes.sh` moves
  to `pin_lint_scan` (~97-206s) out of `rest` (~561s/720s, **cancelled at the
  cap on PR #351**). The estimate and its method are in the file, flagged for
  re-measurement on CI — it is an estimate, not data.
- **F-6, F-8** taken: the hard-exit message now says *does not provide
  `run_with_deadline`* rather than "missing" (a present-but-older
  `helpers-core.sh` reaches it too), and the BL-221 suite's `_mutate` adopts the
  `\001` delimiter its sibling already proved the `%` one fails on.
- **F-9** accepted as informational and recorded on the entry: the five rows
  that dropped `version_command` leave `check-versions.sh` entirely, because
  `CHECKABLE_TOOLS` filters on a non-empty `version_command`. `resolve-tools.sh`
  is unaffected. `version_command` has exactly two consumers, so there is no
  third-party fallout.
- **RF-4, cosmetic and inherited:** the refuted-claim labels run RC-1…RC-4, RC-6
  — there is no RC-5 anywhere in the repo. Five bullets, six labels. Left as-is
  because every citation in flight uses these numbers.

**Round three — the re-review returned `minor_concerns`, and its one correctness
finding was a cost the round-two fix created.** Surfacing the probe's note (F-2)
handed a tool's stderr to `print_warn`, which renders through `echo -e` and
therefore INTERPRETS backslash escapes: a note containing `\` and `n` becomes a
real line break, and the text after it starts a new report line. Reproduced —
a check whose stderr was `note-one\nFORGED  [OK] Totally Installed: 9.9.9`
printed a fabricated `[OK]` row into the report. `# BL-235-NOTE-SAFE` doubles
the backslashes; `C4` asserts the note still arrives while nothing forges a
line, `M11` removes the doubling and watches the fake row return. Two tidy-ups
rode along: `CV_NOTE` was captured and never rendered — a second note binned one
layer before the operator, the defect this entry is named for wearing the
costume of its own fix — so it is deleted rather than plumbed; and `M1`'s
messages still quoted `12s`/`>=10` after the fixture dropped to 6s.

That re-review also settled the one thing I could not check on myself: the file
I had corrupted with a `perl` one-liner and rebuilt was **complete** — every
round-one case and all eleven helpers present exactly once, five cases added,
nothing lost.

**Round four — the round-three fix was applied to ONE of two identical render
paths.** A scoped re-review of that delta returned `minor_concerns` and caught
it: `INSTALLED` comes from a `version_command`'s STDOUT and reaches the same
`echo -e` at **nine** sites (six direct, three through `UPDATES[]`), unescaped.
Reproduced — a version_command emitting
`1.0\n\x20\x20[OK]\x20Totally\x20Installed:\x209.9.9` forged a row
byte-identical to a genuine one, because `\x20` is not whitespace until
`echo -e` expands it, so `tr -d '[:space:]'` does not stop it. The vector is the
same as the notes': `probe_superpowers` and `probe_context7` print a `version`
straight out of `~/.claude/plugins/installed_plugins.json`. Sanitising now
happens at each value's single point of CAPTURE (`# BL-235-VERSION-SAFE`,
`# BL-235-NOTE-SAFE`) rather than at the render sites, because there are nine of
the latter and a tenth added later would be unguarded.

Also: a raw **carriage return** is not a backslash, so doubling left it, and CR
repaints the line from column 0 — a complete fake row on any terminal. **The
narrower `tr` range proposed for that fix does NOT strip CR**: `\015` falls in
the gap between `\014` and `\016`, and `printf 'a\rb'` through it still emits
the CR. It was measured and rejected rather than adopted. `M13` restores exactly
that range, so `C6` proves it measures the RANGE and not the presence of a `tr`,
and `_cv_render_safe` is two lines for the same reason — a one-line form can
only be mutated wholesale.

Two test-side defects of mine in round four, both caught by the cases
themselves: `C5` grepped the wrong fixture row name, and `M13`'s first
replacement was backslash-dense enough that `sed` refused it and the mutant
reported `sites=1` while proving nothing — the same class that corrupted a file
in round two, visible this time because a mutation proof that cannot fail is
itself an assertion.

**Round five — the review of round four returned `block` on a VACUOUS CASE OF
MINE, and pulling that thread found two more things.**

- **`C6` was one-sided.** It asserted only "no raw CR in the output", which is
  trivially true of a report that never rendered the note at all — and "rows
  silently vanish" is a pathology this branch had already produced twice. The
  assertion could not see the most likely regression. `C4` and `C5` both
  dual-assert; `C6` now does too.
- **One stray byte from one tool could end the whole report.** `tr` and `cut`
  reject an invalid multibyte sequence in a UTF-8 locale and exit 1; under
  `set -euo pipefail` the run stops. `C.UTF-8` — ubuntu-latest's usual default —
  is in the failing set. `LC_ALL=C` on both, `C7`/`M14` pin it. **The `cut` half
  fails identically on `main`** and is fixed here only because these are the
  lines this entry owns.
- **`_mutate` escaped `&` but not backslash-DIGIT**, and in a `sed` replacement
  `\0`…`\9` are backreferences. A mutant containing `tr -d '\000-\037\177'`
  therefore left the file untouched while still reporting `sites=1 parses=1` —
  **the third silent no-op from this one helper in a day.** Escaped exactly that
  class, not every backslash: a blanket escape rewrites the `$'\t'` and `%s\n`
  that other mutants legitimately need, changing what they test. Then **all 13
  mutant guards in the suite now assert `changed >= 2`**, so a mutation that
  does not mutate can no longer pass as a killed mutant anywhere in the file.
  The sibling helper in `tests/test-bl221-tier-fail-closed.sh` was brought into
  step — the two copies of `_mutate` are themselves a sync-sibling pair, and
  unifying them is left as work rather than claimed as done.

**What this round is really evidence of:** four of the five rounds found a
defect in the TEST, not in the product — a vacuous assertion, a mutant that
could not fail, a message that misstated its own fixture, a grep for the wrong
name. The product fixes held up. The verification of them did not, repeatedly,
and only an adversary reading the assertions rather than the results caught it.

**Two things I broke in round two and caught before they shipped**, both worth
more than the fixes: `grep -v` exits 1 when it selects no lines, so reading a
note out of an EMPTY stderr file killed `check-versions.sh` mid-row under
`set -euo pipefail` — every healthy row silently vanished from the report, and
the suite caught it. And a `perl -pi -e` one-liner with nested shell escaping
matched backslash-pairs across the whole test file and corrupted it; it was
restored from the commit and the edits re-applied through the editor. **Do not
write multi-substitution `perl`/`sed` one-liners against a file you cannot
immediately diff** — that is the same lesson as `## BL-237:`, one tool over.

**And the fix wave produced one defect of its own, which is filed rather than
buried: `## BL-237:`.** An edit written as `sed … > tmp && mv tmp file` replaced
`scripts/resolve-tools.sh`'s mode **755 → 644**. Every direct caller then got
`rc=126`, and `init.sh` printed one `[WARN] Tool resolver failed`, **exited 0,
and scaffolded a project anyway** — with `installed: {}` and three context values
that had acquired a leading space, surfacing four layers later as
`tests/test-verify-install-fix-functions.sh::T2` complaining about *substituted
identity fields*. The content assertion beside that edit passed, because the
content was right. **"The edit applied" and "nothing else changed" are two
assertions**; `X1`/`M7` now pin the bit, and BL-237 carries the general rule.

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
| the review of it | the branch, exhaustively | its own R-7 severity — stated a delegated agent's findings before the agent answered (§ 2.2) |
| the check of that | asking a doc-lookup agent | the agent's TOOL LOG — it answered "✓ Verified from the official docs" having made **zero** tool calls |

**A delegated answer is a declaration until you look at how it was obtained.**
Three times in a row here, someone downstream reported a conclusion and the
consumer took the conclusion rather than the evidence — and each layer was the
layer that was supposed to be checking the one below it. The fix is the same
one as everywhere else in this table: consume the *receipt*, not the *claim*.
For a subagent the receipt is its tool log; zero tool calls means zero lookups,
whatever the prose says.

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
> **Start with the in-flight branch:** `fix/bl221-tier-keys-and-probe`, whose
> reviewed tree is `76d7427` (worktree `.claude/worktrees/bl221-bl235`). It
> implements `## BL-221:` and `## BL-235:`, is green locally (11/11, 7/7, lints 15/15) and its
> adversarial review **returned `block`**. Do not re-run the review and do not
> open a PR — **§ 2.1 of the handoff is the work order.** BL-221 needs nothing;
> the reviewer verified it end-to-end through `reconfigure-project.sh` and every
> claim survived. Everything in § 2.1 is BL-235.
>
> Work it in the reviewer's order: **R-2 first** — fix the vacuous `D3`
> assertion (`-ne 0` → `-eq 2`, plus an `-eq 1` and an `-eq 0` sibling) and
> watch it go **red** against the shipped rows. Only then fix **R-1**, the CWD
> dependency that D3's blindness hid. Then the `probe-tool.sh` pass
> (R-3/R-4/R-5/R-6) and the prose corrections (RC-1 … RC-4, RC-6). **R-7's
> severity is unresolved — read § 2.2 before you rate it, and do not settle it
> from documentation.** Then re-review the tip, open the PR, merge on green,
> and close both entries citing the PR.
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
>
> And § 2.2 before you delegate anything: **a subagent's conclusion is a
> declaration until you check its tool log.** One in this wave reported "✓
> Verified … directly from the official documentation" having made **zero** tool
> calls, and two layers of consumer passed it along unexamined.

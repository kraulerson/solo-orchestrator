# Brownfield adoption — bringing an existing project into the framework

`init.sh` builds a project from an empty folder. **Adoption is the second way
in**, for a codebase that already exists — with its own history, its own
pipeline, and its own habits. It puts that project under the framework at
**phase 0**, archives anything of yours it has to replace, and commits exactly
the files it wrote.

> **What ships, and what does not.** Adoption works end to end: Scout's survey,
> the tier question, the credential scan and its tier-scoped stop, the reverse
> intake, the state writes and adoption stamp, the collision archive with
> `--re-add`, the test-debt ledger, the **Adoption Record** and the audit rows,
> the **commit-time scanners**, the **framework documents** (a rendered
> `CLAUDE.md` among them), the **Claude Code session layer** (the framework's
> permissions, session hooks and skills, composed into any settings you had),
> the **CI carve-out** (the framework's CI at its own filename; yours read for
> risky patterns, never changed), the **assessment** (a Claude Code conversation
> that `scripts/resume.sh` starts, and a finisher that records it), the
> **provenance header** on the reconstructed intake, and the **in-production
> exemption** (an adopted project the assessment records as in production may
> open a hotfix delta below phase 4, and keeps its retro). Every designed work
> package ships; two gaps with no owner yet are listed under
> [What is not built yet](#what-is-not-built-yet).

Everything on this page is output that was observed, pasted as it printed.

---

## Quick start: install and use

### What you need

This is the one list of what adoption needs. The README's Prerequisites table
is for `init.sh`, which builds a new project; you do not need that list to
adopt, and the README points here rather than repeating this one.

| Tool | Why | If it is missing |
|---|---|---|
| `git`, able to resolve a commit identity | Adoption ends in one commit on your current branch | Refused before anything is written. git can often derive an identity from the system when none is configured; the refusal fires only when it cannot |
| `jq` | Every state file adoption writes is JSON | Stops at once with `adopt-project: jq is required.` and **exit code 2** — the "unusable target" code, not a refusal |
| `shasum` or `sha256sum` | The adoption stamp hashes the survey it was made from | Refused during the pre-write rehearsal, before anything is written |
| `gitleaks` | The credential scan of your history | **Organizational**: the adoption stops, with no override. **Personal**: it can continue if you accept that on the record |
| `semgrep` | The commit-time static-analysis pass | Every commit prints `semgrep not found — pre-commit SAST skipped.`; nothing blocks |
| A clone of the Development Guardrails at `~/.claude-dev-framework` | The Claude Code rules and hooks a new project gets | Adoption completes without them and prints the two commands that install them later. Adoption never fetches the clone itself. Get it with `git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework` |
| Docker running the Qdrant database, and the Qdrant MCP server registered with Claude Code (`uvx` launches it) | Memory across Claude Code sessions. Once it is registered, every session in the project must reach it (a successful `qdrant-find`) before it can change a file | Adoption checks it and, when this machine can (the `claude` command, Docker running, `uvx`), offers to set it up — showing the exact commands first. Skipped or impossible, adoption completes and prints the commands for later. See [The memory and documentation servers](#the-memory-and-documentation-servers) |
| The Context7 MCP server registered with Claude Code (`npx` launches it) | Current library documentation for the agent. Once it is registered, every session must read documentation through it before it changes a file | Checked and offered the same way (needs the `claude` command and `npx`); otherwise its one command is printed |
| Claude Code (the `claude` command) | The assessment, and every change you make after adoption, is a Claude Code session; Superpowers and the two servers above are added to it | Adoption itself completes, but it cannot offer to set up the two servers, and there is nothing to run the assessment in. See [Claude Code's documentation](https://docs.anthropic.com/en/docs/claude-code) |
| Superpowers, a plugin for Claude Code | Needed once the Development Guardrails are installed (the clone row above): they block every edit to a source file until a Superpowers skill has run in the session, and without the plugin there is no skill to run | Adoption completes, but in Claude Code every edit to a source file is blocked with `BLOCKED — Source file edit requires the Superpowers workflow, but the Superpowers plugin is not enabled in this Claude Code configuration`. Guardrails older than 4.3.7 say `You MUST invoke superpowers:brainstorming before editing source files` instead, and the agent's attempt to run that skill fails as an unknown skill. Install it with the command below this table, then start a new Claude Code session |

**Installing Superpowers.** One command, for your user, so every project on
this computer has it:

```bash
claude plugin install --scope user superpowers@claude-plugins-official
```

Then start a new Claude Code session, as the Guardrails' own message says. To
check that it is installed:

```bash
claude plugin list
```

Your project must be a normal git repository with at least one commit. A linked
worktree, a submodule, or a repository with `core.hooksPath` configured is
refused before anything is written, because the gates would be installed where
git never looks.

A project that **looks already under this framework** is refused the same way,
before any question: one scaffolded by `init.sh` (it has
`.claude/phase-state.json`), one already adopted, or one with any other
`.claude/manifest.json`. The refusal reads
`[REFUSED] this project already looks framework-managed: …` and names what it
found. A project that has **only the Development Guardrails** is not refused
(`## BL-311:` row 2): a `.claude/manifest.json` with a `frameworkVersion` and
none of the keys this framework writes, a `.claude/framework/hooks/` directory
beside it — the directory the Guardrails stage checks to know they are already
installed (`# BL-311-GUARDRAILS-ONLY-FRAMEWORK`), so a `.claude/framework/`
without `hooks/` is refused — and no `.claude/phase-state.json` is adopted, and
every Guardrails setting is kept (see *The Development Guardrails for Claude
Code*, below).

### 1. Get the framework

The framework is a clone that stays **outside** your project; adoption copies
what your project needs into it.

```bash
git clone https://github.com/kraulerson/solo-orchestrator.git ~/solo-orchestrator
```

That location is the one every command on this page, the README and the User
Guide uses. Clone it somewhere else and change each `~/solo-orchestrator` you
copy, including in the settings line of step 2.

### 2. Before you start: let Claude Code run the framework's scripts

**If you type the commands on this page into a terminal yourself, skip this
step** — Claude Code is not involved. It is for when you ask a Claude Code
session in your project to run them, and **you have to do it, not the agent.**
**One exception: the assessment's finisher is run by the session**
([Act 4](#the-assessment--act-3-and-act-4--ships-wp12a)), so if you will run the
assessment, do this step too. Its command finds the clone through
`.claude/orchestrator-source.json` instead of naming `~/solo-orchestrator`, and
the classifier reads commands, not what they print, so this step may not clear
it; if auto mode refuses it, use the fallback at the end of this step.

Claude Code's auto mode — the mode a session starts in by default since
Claude Code 2.1.283 — has a classifier judge each command before it runs, and
out of the box that classifier trusts only the folder the session started in
and that repository's own remotes. `~/solo-orchestrator` is neither, so a
framework script run from it can be refused before it starts. It was in the
2026-09-27 dogfood run (`## BL-311:` row 6), where the agent had cloned the
framework itself in that same session; the first line of the refusal, on Scout:

```text
Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Code from External].
```

The agent cannot clear that itself. When it then tried to work out a settings
change on its own, that was refused too — `Reason: [Auto-Mode Bypass]` — because
an agent widening its own permissions to get past a refusal is what that rule
stops. So **you** tell auto mode the clone is yours. Add this to your settings
in a text editor, **before you start the session**:

```json
{
  "autoMode": {
    "environment": [
      "$defaults",
      "Source control: also github.com/kraulerson/solo-orchestrator and its clone at ~/solo-orchestrator — the user's own install of the Solo Orchestrator framework: trusted as code to run, never as a destination for any project's code or data"
    ]
  }
}
```

- **What it does, and what it does not.** It adds one line to what the
  classifier is told about your setup: the clone is trusted **as code to run**,
  not as someone else's code fetched into your project — and **not** as a place
  to send anything. That second half matters. The classifier reads this same
  list as the boundary for your data (Claude Code's documentation: *"any
  destination not listed is a potential exfiltration target"*, so a listed one
  counts as inside), and `github.com/kraulerson/solo-orchestrator` is a public
  repository that belongs to the framework's author, not to you. So the line
  itself says the clone and the repository are never a destination for any
  project's code or data; keep that clause if you reword it. It approves
  nothing in advance. Every command Claude runs from the clone
  still goes to the classifier, which still judges what that command does, with
  which arguments, to which folder. `"$defaults"` keeps Claude Code's built-in
  lines; leave it out and your one line replaces all of them (measured on Claude
  Code 2.1.285: 21 lines become 1).
- **Where: your user settings, `~/.claude/settings.json`** (or
  `$CLAUDE_CONFIG_DIR/settings.json` if you set `CLAUDE_CONFIG_DIR`). No file
  there yet: save the block above as it is. A file already there: add the
  `autoMode` block beside its other keys — or, if it already has an
  `autoMode.environment` list, add the one line to that list. Not the project's
  `.claude/settings.json`: Claude Code does not read `autoMode` from a
  project's settings at all, so a repository cannot vouch for itself (measured:
  the same block there does not show in the check below). In your user settings
  the line applies to every Claude Code session on this machine. Lines from
  settings your organization manages are combined with yours, not swapped for
  them.
- **Why not a permission rule,** as the refusal itself suggests (*"the user can
  add a Bash permission rule to their settings"*)? A rule such as
  `Bash(bash ~/solo-orchestrator/scripts/scout.sh *)` is applied before the
  classifier runs, so Claude could then run that script with any arguments and
  nothing would judge the call — Scout's `--run-tests` pointed at any folder,
  which runs that folder's test code, or answers piped into the adoption
  questions only you should answer — and in your user settings that holds for
  every project on this machine.
- **Not measured yet:** whether this line clears the `[Code from External]`
  refusal, and whether the classifier honours the scoping — trusting the clone
  as code to run while still treating the repository as outside your boundary
  for data. The clean rerun of the dogfood run (`## BL-311:`) measures the
  first; nothing measures the second yet. Until then, keep the fallback below
  at hand.

Check that Claude Code reads the line:

```bash
claude auto-mode config | grep -F '~/solo-orchestrator'
```

It prints your line. Nothing printed means it is not loaded: with a JSON
mistake in the file, this command prints the built-in lines and no error
(measured on Claude Code 2.1.285), and
`jq empty "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"` names where it
stopped reading — the mistake is on that line or the one before (measured: a
missing comma at the end of line 2 is reported at line 3). Inside a session,
`/permissions` → **Recently denied** lists each action auto mode refused.

**If Claude is still refused, run the command yourself** — in your own
terminal from the project's folder, or typed after `!` at the session's
prompt, which Claude Code runs "directly without Claude's prior approval or
interpretation" and whose output lands in the conversation. A script that
asks you questions — adoption, `--re-add` — belongs in your own terminal:
Claude Code's documentation does not say a `!` command can take your answers.
Or press `Shift+Tab` once to leave auto mode for that step: the session then
asks you, instead of the classifier, before it runs a command; keep pressing it
until the status bar shows `⏵⏵ auto mode on` to go back. In `/permissions` →
**Recently denied** you can also press `r` on the refused action to let Claude
retry it with your approval.

### 3. Look first — Scout writes nothing

```bash
cd /path/to/your-project
bash ~/solo-orchestrator/scripts/scout.sh --out /tmp/scout --run-tests
```

`--out` writes `scout-report.json` and a readable `scout-report.md`. Leave out
`--run-tests` if you do not want Scout to run your code — but it is the one way
to learn **before adopting** whether your test suite passes today, and that
matters: once adopted, a commit that touches source code runs your tests and is
refused if they fail. Scout runs the command through your package manager —
`uv run --frozen pytest`, `poetry run pytest`, `npm test` and so on — because
a bare `pytest` cannot see a tool installed in the project's own environment
([how Scout picks it](scout.md#stack--what-this-project-is-built-with)). It runs
in your real tree: the manager may create untracked files of its own (a `.venv`),
and Scout passes the flags that keep uv and pnpm from rewriting your lockfile
([what it can change](scout.md#what---run-tests-can-change)). See
[Before you adopt: run Scout](#before-you-adopt-run-scout).

### 4. Adopt

```bash
cd /path/to/your-project
bash ~/solo-orchestrator/scripts/adopt-project.sh --scan-report /tmp/scout/scout-report.json
```

Without `--scan-report` it runs its own survey. It asks two questions a scan
cannot answer — **who the project is for**, which sets its enforcement tier,
and **the project's track** ([the track question](#then-the-track)). The first:

```text
Who is this project for?
   1) Just me, or me and a few people I know
   2) A company, a client, or people who are paying for it
```

If the Qdrant or Context7 server is missing and this machine can set it up, it
also offers to — an **optional** question; no answer means skip it
([The memory and documentation servers](#the-memory-and-documentation-servers)).
Then it confirms what the survey found, asks — last, and optional: no answer
means **no** — whether every reply the agent gives should end with a
plain-English TL;DR ([TL;DR mode](#last-tldr-mode)), writes the project's state
at phase 0, and commits. **Your uncommitted work is never staged**; the commit contains only
files adoption wrote. Exit codes: `0` adopted; `1` did not complete (a refusal,
a stop, or a halt); `2` bad usage.

### 5. If it stops

- **Credential findings in your history** (organizational): the run lists them —
  rule, file and line, never the value — and prints a dispositions file **already
  bound to that scan**, with every fingerprint filled in. Save it *outside* the
  project, fill in each `disposition` (`rotated`, `false-alarm` or
  `accepted-risk`), `by`, `reason` and `date`, and run the same command again with
  `--dispositions ~/adoption-dispositions.json`. The decisions go into the
  Adoption Record. On a personal project the findings are recorded and adoption
  continues.
- **No scanner, or a shallow clone** (personal): without `gitleaks`, or on a
  `git clone --depth` that only has part of the history, a personal adoption
  stops and prints the same kind of file — this time with one
  `acknowledgements` entry of kind `tool-unavailable` or `scanned-partial`. Fill
  in `by`, `reason` and `date`, and re-run with `--dispositions`. The acceptance
  goes into the Adoption Record. For a shallow clone the run also prints the two
  commands that fetch the full history, which is the better answer if you can.
  An organizational adoption with no scanner cannot be accepted this way:
  install `gitleaks` and run again.
- **Every `date` must be a real calendar day written `YYYY-MM-DD`.** "tomorrow",
  "0000-00-00" and 2026-02-30 are refused.
- **Your ignore rules refuse files adoption must write**: nothing is written. The
  block lists the refused paths and, under them, each rule that refuses them as
  `git check-ignore -v` reports it — file, line and pattern, once per rule with
  its count — and the one-line fix where there is one. The common case:

  ```text
  The rule(s) that refuse them, as `git check-ignore -v` names each:
    .gitignore, line 2: `lib/` refuses 24 of them (for example scripts/lib/accumulation.sh)
      It has no leading slash, so it matches `lib` at any depth, not only at the top: here it matched scripts/lib.
      One-line fix, if the rule was meant for the top-level lib/ only: change line 2 of .gitignore to `/lib/`.
  ```

  Whether the rule meant *every* `lib/` is your call; adoption never edits your
  ignore files. A rule from a personal excludes file (`core.excludesFile`, or
  git's default `$XDG_CONFIG_HOME/git/ignore` — usually `~/.config/git/ignore` —
  when that is not set) or from `.git/info/exclude` is named as such, with which
  of your repositories read it: it is not in the repository, so nobody else has
  it. If git cannot name the rule, the block says so and gives the command to
  ask it: `git check-ignore -v --no-index -- <path>`.
- **Your own pre-commit hook refused the adoption commit**: fix or bypass that
  hook, then run `bash ~/solo-orchestrator/scripts/adopt-project.sh --finish`
  from the project. It commits exactly the files the first run wrote.
- **Anything else** prints a `[REFUSED]` or `[BLOCKED]` line naming the cause, and
  says whether anything was written to the project.
- **If you had answered "set it up now" to the memory and documentation
  servers**, that step has already run when a later question stops the run. A
  server it registered is in your Claude Code user configuration, outside the
  project, and it stays registered; the refusal says which, by name
  ("Outside this project, this run DID register …"). Run adoption again and it
  finds them registered and does not offer to register them again. To see
  them, or to remove one the refusal named:

  ```bash
  claude mcp list
  claude mcp remove -s user context7
  claude mcp remove -s user qdrant
  ```

### 6. Afterwards

**First, if a Claude Code session is open in this project, close it and start a
new one.** The checks, and the memory and documentation servers, that adoption
set up only take effect in a session started after adoption: a session that was
already open has no record of its own start, and the framework's MCP check
blocks every file edit in it (measured in the 2026-09-27 dogfood run). The run's
closing block says so too.

**The new session opens with a report on your tools**, and sometimes on the
Guardrails, which the agent must tell you about before anything else: updates
it offers to run, a tool below the minimum version, a Guardrails update or
notice. [What to do with each message](user-guide.md#what-to-do-with-each-message)
says, in plain words, which you can skip and which you cannot.

**If the project already had the Development Guardrails, that new session may
offer to update them.** Adoption keeps an existing install as it found it (see
"The Development Guardrails for Claude Code" below). When its version is older
than your clone's, every session start says so, with both versions, and asks
you to type `!` and then this command at the Claude Code prompt:

```bash
bash scripts/refresh-guardrails.sh
```

The agent is told not to run it for you: it replaces the Guardrails that check
the agent's own work, so starting it is your decision. The command first runs
`git pull --ff-only` on the Guardrails clone, which every project on this
machine shares, so it can install a newer version than the one offered. Then it
copies the clone's Guardrails hooks and rules into `.claude/framework/` and
records the new version in `.claude/manifest.json`; it does not change
`.claude/settings.json`. It refuses a new MAJOR version (that is a migration,
and the session start tells you so instead of offering the command), an
uncommitted change in the clone's hooks or rules, and a symlink in
`.claude/framework/`. When it refuses, nothing in this project is changed; the
shared clone may already have been pulled. The new hooks apply from the agent's next tool call,
so no restart is needed. Say no and the offer comes back at the next session
start, so a session that a Guardrails defect is blocking can be restarted and
the fix accepted then. Commit `.claude/framework/` and `.claude/manifest.json`
afterwards. Moving from a version before 4.4.0 to 4.4.0 or later this way
changes how you approve a commit: see [7. Your first change](#7-your-first-change).
Then:

```bash
bash scripts/resume.sh
```

It prints the **assessment prompt** — paste it into Claude Code. That session
asks you what the project is for, gives a verdict with its reasoning, and runs
the finisher that records it ([The assessment](#the-assessment--act-3-and-act-4--ships-wp12a)).
Saving what the assessment wrote is the first commit the agent makes in this
project, so it goes through the approval step in
[7. Your first change](#7-your-first-change).
Run `resume.sh` again afterwards and it prints this project's Phase 0 prompt
(Section 13 of `PROJECT_INTAKE.md`), even if your project brought a
`PRODUCT_MANIFESTO.md` of its own. Once Phase 0 writes the manifesto, or
changes the one you brought, `resume.sh` prints the ordinary resume prompt
instead. The agent reads the
`CLAUDE.md` adoption wrote. If you
already had a `CLAUDE.md`, `BUGS.md` or the like, the run named each one it
replaced — the framework's version is in place and yours is in the archive,
**not merged** until the assessment conversation folds in what is worth keeping
(or you copy it across yourself —
[The framework documents](#the-framework-documents--ship-wp12b)). From your next commit on, the message gates and the
commit-time scanners run. Your replaced files are in
`.claude/adoption-archive/<timestamp>/`, each with a restore line in its
`MANIFEST.md` — and one command puts any of them back:

```bash
bash ~/solo-orchestrator/scripts/adopt-project.sh --re-add .git/hooks/pre-commit
```

### 7. Your first change

What to expect the first time the agent commits in an adopted project — the
assessment's own files first, then your first change to code — and what the
framework expects of a change while the project is at phase 0. The Guardrails
behaviour below was read from their hooks (versions 4.3.7 and 4.4.0).

**What the framework expects at phase 0.** The Builder's Guide builds in
Phase 2: Phase 0 decides what the product is ("If it is not defined in Phase 0,
the AI is not permitted to build it in Phase 2"), Phase 1 designs it, and the
`CLAUDE.md` adoption wrote tells the agent to follow the phases in order. No
check blocks a commit because the project is at phase 0: the Build Loop's
commit checks start at phase 2 — `check_commit_ready` in
`scripts/process-checklist.sh` lets every commit through below it, and the
`feat:` commit-message check does the same. Neither the guide nor the scripts
say whether a small fix to code the project already had may go in before
Phase 0 is done. So it is your decision:

- **If it can wait**, do Phase 0 first. This prints the prompt that starts or
  resumes it:

  ```bash
  bash scripts/resume.sh
  ```

- **If the assessment recorded the project as in production and the fix cannot
  wait**, open a delta: for such a project the delta track opens below phase 4
  (the in-production paragraph under
  [The assessment](#the-assessment--act-3-and-act-4--ships-wp12a)):

  ```bash
  bash scripts/delta.sh --open --describe "what is broken, in your own words"
  ```

- **Otherwise, if you decide to go ahead**, tell the agent so: it reads the same
  rule in `CLAUDE.md` and may point it out. The change then goes through every
  check below.

**Before the agent can edit a source file**, two checks must be met in each
session:

- **Memory and documentation.** When Qdrant or Context7 is registered, the
  agent's first file edit in a session is blocked until it has searched its
  memory (`qdrant-find`) and read documentation through Context7 (`query-docs`;
  finding the library with `resolve-library-id` is not enough). In a new
  project the memory search finds nothing at first, and that is normal.
- **Superpowers.** The Guardrails block every edit to a source file until the
  agent has run a Superpowers skill in this session. For a change with no
  approved design that is `superpowers:brainstorming`, which ends with the agent
  showing you a short design and waiting for your yes; for a design you already
  approved, a skill that carries it out, such as
  `superpowers:test-driven-development`. A skill counts until the next
  successful commit, a new or cleared session, or the end of the session, so
  after each commit the agent runs one again before its next source edit. Test
  files are not source files to this check, so the agent can write the failing
  test first. Without the plugin, see [What you need](#what-you-need).

**The approval step: what the agent asks, and what you approve.** The
Guardrails block every commit the agent runs until you have approved it. When
the change is ready, the agent:

1. stages exactly the files it means to commit;
2. records a question in `.claude/pending-approval.json`, tells you its
   evaluation (pros, cons, alternatives) and the options, each with an id such
   as `A1` (commit these files) or `A2` (do not commit yet), and stops.

Each approval covers one commit; the next commit needs a new question. If the
agent tries to commit before you approve, the commit is blocked with a message
that starts `BLOCKED — Commit requires`. That is the check doing its job: the
agent should ask you instead.

**The stop check and the commit check.** At the end of every reply the
Guardrails' stop check looks for unfinished work. With source changes not yet
committed and no question recorded, it says
`Uncommitted source changes. Commit before finishing.` That does not overrule
the approval step: the same message tells the agent, when the commit is waiting
on you, to record the question and stop, and once
`.claude/pending-approval.json` exists the stop check lets the agent stop and
wait. A reply that ends with a question for you is the expected shape, not a
stuck agent: answer the question.

**How you answer depends on your Guardrails version.** This prints it:

```bash
jq -r .frameworkVersion .claude/manifest.json
```

- **4.4.0 and later.** Reply with the option id first — `A1`, or
  `A1 — go ahead`. The framework then shows you the question, what each option
  does, the staged files and the git hooks that will run, ending
  `Reply with the option id again (for example: A1) to confirm.`; that second
  reply is the approval. The agent then commits with a plain
  `git commit -m "…"`. A reply that does not start with an option id approves
  nothing, and changing what is staged after you approve cancels
  the approval. Two things can stop this working today:
  - **`The pending question cannot be answered`** means the question was written
    in the older format, which this framework's own `scripts/pending-approval.sh`
    and `scripts/escalate-to-user.sh` still write. Ask the agent to rewrite it;
    the message gives the agent the format.
  - **Guardrails brought up to 4.4.0 by `bash scripts/refresh-guardrails.sh`**
    from an earlier version. That update does not change
    `.claude/settings.json` (`## BL-319:`), and the hook that reads your reply,
    `record-approval.sh`, is switched on there. This prints `0` when it is not:

    ```bash
    grep -c record-approval .claude/settings.json
    ```

    Then no reply of yours can approve a commit; use the override below for each
    one. (A project adopted with 4.4.0 already in the clone has it switched on.)
- **4.3.7.** Answer in your own words. The agent clears the question
  (`scripts/pending-approval.sh --resolve`), records your approval by running
  `bash .claude/framework/hooks/mark-evaluated.sh "<what you approved>"` on its
  own, and commits.
- **Older than 4.3.7** — the dogfood project's 4.3.0, for one. The Guardrails
  block the agent from staging `.claude/manifest.json`, which the assessment's
  finisher lists, and they accept `mark-evaluated.sh` only as a lone command,
  with nothing chained or redirected, and their block message does not say so;
  the dogfood agent was blocked twice trying to run it. Accept
  the Guardrails update the session start offers ([section 6](#6-afterwards)),
  or stage the files and use the override yourself.

**The override.** You can record an approval yourself, from the project's
folder, once the change is staged:

```bash
bash .claude/framework/hooks/mark-evaluated.sh "what you approved, in a few words"
```

With Guardrails 4.4.0 and later, run it in a separate terminal window: it
refuses to run inside Claude Code, a command typed after `!` included, and it
approves only the change staged at that moment. Then tell the agent to commit
it with a plain `git commit -m "…"`.

**The commit's own checks.** Whoever commits, the commit-time checks adoption
installed run next ([The commit-time scanners](#the-commit-time-scanners--ship-wp73)).
Among them: your project's own test suite, which blocks a commit it fails
([Three things to know](#three-things-to-know-before-you-rely-on-it) covers
when it cannot run), and the test-before-code check — a `fix:`, `feat:` or
`refactor:` commit that changes code with no test gets a warning on a personal
project and is blocked on an organizational one.

---

## Contents

- [Quick start: install and use](#quick-start-install-and-use)
- [Before you adopt: run Scout](#before-you-adopt-run-scout)
- [The two questions](#the-two-questions)
- [The memory and documentation servers](#the-memory-and-documentation-servers)
- [Where it lands: phase 0, always](#where-it-lands-phase-0-always)
- [The reverse intake](#the-reverse-intake)
- [What gets written, and in what order](#what-gets-written-and-in-what-order)
- [The adoption stamp, and what happens when it is lost](#the-adoption-stamp-and-what-happens-when-it-is-lost)
- [The Adoption Record](#the-adoption-record)
- [The TDD exemption and its bound](#the-tdd-exemption-and-its-bound)
- [The test-debt ledger and its ratchet](#the-test-debt-ledger-and-its-ratchet)
- [What is not built yet](#what-is-not-built-yet)
- [Exit codes](#exit-codes)

---

## Before you adopt: run Scout

[Scout](scout.md) is the read-only survey. It changes nothing, and the driver can
consume its report instead of re-scanning:

```bash
bash ~/solo-orchestrator/scripts/scout.sh --out ./scan
bash ~/solo-orchestrator/scripts/adopt-project.sh --scan-report ./scan/scout-report.json
```

Run it first. It is the cheapest way to find out that this project has an AWS key
in its history, or a `.git/hooks/pre-commit` you would rather not lose.

### Options

```text
$ bash scripts/adopt-project.sh --help
adopt-project — bring an existing project under the framework.

  cd /path/to/their-project
  bash /path/to/solo-orchestrator/scripts/adopt-project.sh [options]

  --root DIR          the project to adopt (default: the current directory)
  --scan-report FILE  consume this Scout report instead of running a new scan
  --re-add PATH       put one of YOUR archived files back, warned and recorded
  --version           print the driver's version and exit
  --help              print this and exit

--re-add is the other half of the collision archive and it does NOT run an
adoption. Point it at one of your own files as the archive MANIFEST names it
(for example .git/hooks/pre-commit); it shows you what the framework thinks
that trade costs, asks you to confirm, puts the file back exactly as it was,
and records the choice in the audit trail. The framework's premise is
opinionated enforcement, not confiscation — your files are yours. The one file
it will not put back is .claude/manifest.json: adoption changed none of your
settings in it, and the archived copy has no adoption stamp, so restoring it
would un-adopt the project.

What it does, in order: reads the survey, offers what the survey found as
EVIDENCE, asks who the project is for and which track it is on, confirms the
answers the survey already derived, asks whether every reply the agent gives
should end with a plain-English TL;DR (no answer means no), writes the
project's state at phase 0, records the adoption, and commits exactly the files
it wrote.

Your project starts at phase 0 whatever the survey found. Nothing is marked as
already done and no shortcut is taken past any gate — the questions about what
this project is and what it is for are asked afterwards, in Phase 0.

If it stops partway — because you stopped it, or because a question had no
answer — it stops in the SAFE direction: the project ends up more strictly
gated than it was, never less.

Exit codes: 0 adoption completed; 1 adoption did not complete (a refusal, a
blocker, or a halt); 2 bad usage or an unusable target.
```

**Why this is a separate script and not `init.sh --brownfield`.** `init.sh`'s
interactive path has no existence check and twelve unguarded overwrite sites. A
`--brownfield` flag would mean auditing every one of those for a mode that must
never reach them; a separate driver makes them unreachable by construction. The
driver never calls `create_project()`.

---

## The two questions

Before it asks anything, the driver shows what the scan noticed — as **evidence
that decides nothing**, each line carrying its own confidence:

```text
══ What the scan noticed
   This is what a read-only look at your code found, and each line says how much
   weight it deserves. It is here so you can see it, not so you can act on it.

   Deployment: the scan found .github/workflows/deploy.yml (a deploy or release lane).
     Points to: built out. Confidence: LOW — this is file presence, not run history;
     Scout is read-only and does not ask the host whether the lane has ever run.
   Release tags: 2 version-shaped tag(s); newest v2.4.0 2026-08-10.
     Points to: built out. Confidence: MEDIUM — tags are cheap and often abandoned.
   Recent work: over the last 50 commits, 1 look like new features and 2 look like fixes.
     Points to: built out. Confidence: LOW — this is a heuristic and it is labelled as one.
   Changelog: CHANGELOG.md lists 2 released version(s).
     Points to: built out. Confidence: MEDIUM.

   Users: the scan cannot measure whether anyone is using this. Only you know that.

   None of this decides anything. Your project starts at phase 0 either way and
   earns each gate the ordinary way; what the scan found becomes a head start on
   the Phase 0 questions, never a shortcut past them.
```

Then it asks **the first question**, and it is not about your code:

```text
Who is this project for?
   1) Just me, or me and a few people I know
   2) A company, a client, or people who are paying for it
   Answer with the number or the words:
```

**There is no default and no skip.** With no answer:

```text
[REFUSED] This question has no default and no skip, and no answer was given: who the project is for
          Adoption did not begin. Nothing was committed and nothing was written to this project.
```

That answer sets your project's **tier**, and the tier decides how strictly the
framework treats you — most visibly, how hard it stops when a secret scan finds
something. No amount of reading your code can determine it.

### Then the track

Straight after it, adoption asks the project's **track** (`## BL-311:` row 8 —
until then it wrote `full`, the enterprise track, without asking). It is the
question a new project gets from `init.sh`, with the same three descriptions.
Observed, answering `1` (Light) on a personal project:

```text
Project tracks:
   Light    — Internal tools, prototypes, POCs. <10 users. Minimal governance.
   Standard — External users, moderate complexity. Market audit, user testing.
   Full     — Enterprise buyers, sensitive data. Pen testing, legal review mandatory.
Project track:
   1) light
   2) standard
   3) full
   Answer with the number or the words:
   Production builds require Standard or Full track.
   Light track skips market validation, user testing, and security hardening.
Select a track:
   1) standard
   2) full
   Answer with the number or the words:
   Track: standard
```

The same two rules apply as for a new project:

- **Light needs a Private POC.** Adoption asks no POC question and lands every
  project as a production build, so a Light answer is always asked again, as
  above, between Standard and Full.
- **Full on a personal project is confirmed.** Observed:

  ```text
     Full track is designed for organizational projects with enterprise compliance.
     For personal projects, Standard track provides external-user readiness without
     enterprise overhead (pen testing, legal review). You can upgrade later.
  Continue with Full track?
     1) choose a different track
     2) continue with Full track
     Answer with the number or the words:
  ```

  `choose a different track` asks the track again.

Unlike `init.sh`'s `[y/N]`, nothing here has a default: an empty answer or the
end of your input stops the run before anything is written, naming the question
(`no answer was given: the project track`, or `…: whether to keep the Full
track`). The answer is recorded once, in both `.claude/phase-state.json` and
`.claude/intake-progress.json`, and the `CLAUDE.md` adoption writes carries it.
A script answers it on standard input like every other question — the option's
number or its words, one per line.

### Last, TL;DR mode

After the survey's confirmations and before anything is written, adoption asks
one more question (`## BL-312:`) — whether every reply the agent gives should end
with a plain-English TL;DR. Observed, answering `yes`:

```text
══ How the agent replies to you
   TL;DR mode ends every reply with one plain-English summary: what happened, what it
   means for you, next steps, what is waiting on you, your options with their pros and
   cons, a recommendation with its reasoning, and what happens if you do nothing.
   You can switch it later: bash scripts/reconfigure-project.sh --tldr-mode on (or off).

Do you want every reply to end with a plain-English summary of what happened, your options and a recommendation? (No answer means no.)
   1) no
   2) yes
   Answer with the number or the words:
   TL;DR mode: on
```

**Like the server question, it is optional, and no answer means no** — unlike
the tier and the track. An empty answer or the end of your input turns it off
and says so (`No answer — TL;DR
mode is off.`); `1` or `no` is off; `2` or `yes` is on; anything else stops the
run before anything is written, as every question does (`'maybe' is not one of
the answers offered for: TL;DR mode`).

**Why it is last.** A script that pipes its answers — and the framework's own
tests do — was written for the questions before it. Asked anywhere earlier,
this question would take an answer meant for a later one and shift the rest.
Last, a script's answers run out before it (no) or reach it with a spare `1`
(also no — "no" is listed first for that reason), so a stray answer can never
turn it on.

The answer is written to `.claude/manifest.json` as `tldr_mode: true` or
`false` — always, so the choice is on record either way. On, `CLAUDE.md` gets a
short "TL;DR Mode" section stating the eight parts, and the Stop hook
`scripts/hooks/tldr-check.sh` sends back, once per turn, any reply with no
TL;DR outside a code block. The hook is registered in `.claude/settings.json`
either way — beside your Development Guardrails' `stop-checklist.sh`, if you
have them, and the framework's own Stop hooks — and does nothing while the
mode is off. `bash scripts/reconfigure-project.sh --tldr-mode on|off` switches
it; the user guide's TL;DR mode section has the rest.

---

## The memory and documentation servers

A Claude Code session in an adopted project is checked for two MCP servers:
**Qdrant** (memory across sessions) and **Context7** (current library
documentation). The check (`scripts/session-mcp-gate.sh`) blocks every file edit
until each server that is **registered** has answered a call that session — and
does not require one that is registered nowhere. So what matters is which of
three states each server is in, and adoption tells you:

| State | What a Claude Code session in this project does |
|---|---|
| Registered, and answering | Works. Each session calls it before its first file edit |
| Registered, but nothing answers | **Blocks every file edit** until it answers |
| Not registered | Works without it — no memory of earlier sessions, or no library documentation. Its check switches on in the first session after you register it |

Adoption reads the registrations from the files a Claude Code session started
from the same shell reads: `~/.claude.json` and `~/.claude/settings.json`, or —
when `CLAUDE_CONFIG_DIR` is set — `.claude.json` and `settings.json` inside that
directory, **and nothing under your home directory**. That is Claude Code's own
rule, and before this step adoption did not follow it: it read `~/.claude.json`
for a session that did not, saw a Qdrant server that session did not have, and
declared it for the project.

After the credential scan, when something is missing and this machine can act,
it shows the exact commands and asks. This was recorded with stand-in `claude`
and `docker` commands, so nothing was registered on the machine that produced
it; the two paths are shortened (that run's `CLAUDE_CONFIG_DIR` was a scratch
directory):

```text
══ The memory and documentation servers Claude Code uses here
   Read from the two files a Claude Code session started from here reads:
     …/cfg/.claude.json
     …/cfg/settings.json
   Context7 (current library documentation): NOT registered for Claude Code.
   Qdrant (memory across sessions): NOT registered for Claude Code.

   This would run, exactly as written:
     claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
     docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest
     claude mcp add -s user qdrant -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory -- uvx --python 3.13 mcp-server-qdrant
   The claude commands change your Claude Code configuration for every project,
   not only this one. Nothing is written into this project.
Set them up now? (No answer means skip it.)
   1) skip it
   2) set it up now
   Answer with the number or the words:
```

**`skip it` is listed first on purpose**: an answer of `1` meant for another
question — a script that answers `1` to everything — skips, rather than
registering servers for every project on the machine.

`set it up now` (or `2`) runs them, from the run's own scratch directory, then
reads the registrations back and asks Claude Code itself whether it can start
each server (`claude mcp get`, the same check `claude mcp list` runs) — it
claims only what those show:

```text
   Running: claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
   Running: docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest
   Running: claude mcp add -s user qdrant -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory -- uvx --python 3.13 mcp-server-qdrant

   Afterwards:
   Context7 (current library documentation): registered for Claude Code.
   Qdrant (memory across sessions): registered, and answering at http://localhost:6333.

   Context7: Claude Code's own check (claude mcp get) says it starts.
   Qdrant: Claude Code's own check (claude mcp get) says it starts.
```

If Claude Code cannot start a server it now has registered — `uvx` cannot fetch
its Python, say — that is the worst state, because registered means required,
and the run says so as a block, with Claude Code's own command to undo it
(recorded with a stand-in that refuses to start Qdrant):

```text
   Qdrant: Claude Code's own check says it could NOT start it — stub: qdrant cannot be started.

   BLOCKED UNTIL FIXED: Qdrant IS registered, but Claude Code could NOT start it (stub: qdrant cannot be started).
     Every file edit in this project is blocked until it can. To back the registration out:
       claude mcp remove qdrant -s user
```

Qdrant is registered only once its database answers, and not at all if its
container fails to start: a registered server with nothing behind it would
block every file edit. If a container named `qdrant` already exists, the plan
says `docker start qdrant` instead of `docker run`; if a database already
answers on port 6333, only the registration is offered. **A new container's
ports are published on `127.0.0.1` only** — without an address, `-p` publishes
on every network interface unless your Docker daemon sets a default bind
address, and this database has no API key. (Docker's own documentation adds
that on Docker Engine older than 28.0.0 on Linux, hosts on the same network
segment can reach even ports published on `127.0.0.1` — moby/moby#45610.)

A container that already exists keeps whatever binding it was created with, so
whenever adoption finds one it reads it (`docker inspect`: the port bindings,
whether it was created with `-P` (`--publish-all`) or on the host's network,
and whether `QDRANT__SERVICE__API_KEY` — in any letter case, as Qdrant reads
it — is set in its environment, never its value), on every path — even when
nothing is missing. It says so before the question, and every later
`docker start` hint points back at it, when the container runs on the host's
network (every interface of this machine), when a binding names `0.0.0.0`
(every interface), `::` (every IPv6 address), no host address, or any address
other than `127.0.0.1` and `::1`, and when it was created with `-P`, which
publishes on random ports of every interface. Loopback is only what is left
when none of those holds. When Docker is not running, the inspect fails or its
answer cannot be parsed, every `docker start` hint says the bindings could not
be read and how to check them. Recorded with a stand-in
`docker` shaped like a real container on the `qdrant_storage` volume with no
API key in its environment; `~/solo-orchestrator` stands for the framework
checkout, printed as its full path:

```text
   Your existing qdrant container's ports name no host address, which Docker
   publishes on every network interface unless your Docker daemon sets a default
   bind address: while it runs, other machines on your network may be able to reach
   it — and no API key is set in its environment (a key in a Qdrant config file would not show here).
   Starting it keeps that. To publish it on 127.0.0.1 (loopback) instead, it has to
   be recreated, and removing a container can delete its data.
   (On Docker Engine older than 28.0.0 on Linux, hosts on the same network segment
   can reach even ports published on 127.0.0.1 — moby/moby#45610.)
   Adoption changed nothing about this container, and prints no commands to recreate
   it. How to do that without losing its data:
   "Recreating an exposed Qdrant container" in ~/solo-orchestrator/docs/adoption.md.
```

**It prints no command to recreate the container — for any container.**
Recreating it on loopback means removing it, and whether the data survives that
depends on how the container was made. Earlier versions of this step printed a
recreate, first for every shape and then only for the shapes an allow-list
confirmed; each round of review on real Docker found another setting the printed
commands lost or broke — where the data lives (nothing mounted, `--rm`, a tmpfs
in any spelling, a tmpfs-backed volume, storage split across mounts, a volume
subpath), an API key or another setting, lowercase setting names, `RUN_MODE`,
command-line flags, a tag that had moved since the container was made, snapshot
files kept inside the container. So the note says what it found, that adoption
changed nothing, and where the written procedure is:
[Recreating an exposed Qdrant container](#recreating-an-exposed-qdrant-container),
which goes through Qdrant's own snapshot API and so does not depend on how the
storage is mounted. The note is the same whatever the storage, and carries no
line to paste. `docker start qdrant` stays the offered action.

`skip it`, a blank line, or the end of your input all mean skip — this question
never stops an adoption:

```text
   Skipped. Nothing was run.

   NOT SET UP — what that means for Claude Code in this project:
     Qdrant is not registered: sessions here have no memory of earlier sessions. The
     framework's check for it is off while it is not registered, and ON from the first
     session after you register it — so have the database running when you do.
     Context7 is not registered: sessions here cannot read current library documentation.
     Its check is off until you register it, and ON from the next session after that.
   To set them up later, run these, then start a new Claude Code session:
     docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v qdrant_storage:/qdrant/storage --restart unless-stopped qdrant/qdrant:latest
       (or, if a container named qdrant already exists: docker start qdrant)
     claude mcp add -s user qdrant -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory -- uvx --python 3.13 mcp-server-qdrant
     claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
```

A server that is registered but silent gets the stronger sentence instead —
`EVERY file edit is BLOCKED until qdrant-find succeeds` — because that is what
the check then does. When the machine cannot act (no `claude` command, which is
every CI runner; Docker not running; no `uvx` or `npx`), there is no question:
the run names what is missing and what to install (Node.js for `npx`, uv for
`uvx`), and prints the same commands for later. Either way
the [Adoption Record](#the-adoption-record) carries one row for it:

```text
    | MCP servers (Qdrant, Context7) | Qdrant: NOT registered (skipped); Context7: NOT registered (skipped) |
```

**The Qdrant command puts the server name before the `-e` options.** Measured on
Claude Code 2.1.283: `-e` takes every value after it, so the spelling with
`qdrant` after `-e COLLECTION_NAME=claude-memory` exits 1 with `Invalid
environment variable format: qdrant`. Earlier copies of the framework — `init.sh`,
the phase checks, the tool matrix and the [CLI Setup Addendum](cli-setup-addendum.md)
— printed and ran that failing order; all of them now use this one.

---

## Recreating an exposed Qdrant container

Adoption points here whenever it finds an existing `qdrant` container whose
ports are published beyond loopback — a binding on `0.0.0.0`, `::`, no host
address or any address other than `127.0.0.1` and `::1`, a container created
with `-P`, or one on the host's network (`--network host`). It says what it
read and changes nothing, and it prints no commands to recreate the container:
a recreate printed without knowing everything the container was created with
can lose its data or drop a setting it relies on (see
[The memory and documentation servers](#the-memory-and-documentation-servers)
for the list review found). Recreating the container on loopback is still the
fix; this is how to do it without losing the data. Adoption does none of it for
you.

**The route does not depend on how the storage is mounted.** It uses Qdrant's
own snapshot API: each collection is snapshotted and downloaded through the
running server, and uploaded into the new container. It follows Qdrant's
snapshot documentation (<https://qdrant.tech/documentation/snapshots/>:
`POST /collections/{name}/snapshots`, whose response carries `result.name`;
`GET /collections/{name}/snapshots/{snapshot}` to download it;
`POST /collections/{name}/snapshots/upload?priority=snapshot` to restore it,
which creates the collection) and its alias API (`GET /aliases`;
`POST /collections/aliases` with `create_alias` actions). It needs `curl`,
`jq`, and `sha256sum` or `shasum` (Linux has `sha256sum`, macOS `shasum`) —
steps 1 and 2 stop and say so when `jq` is missing, and step 2 when neither
checksum tool is there — and the old container **running** — start it if it is
stopped, unless it was started with `--rm` and is already gone.

**Before you start, list the settings it was created with — the new container
must be created with the SAME ones.** That is its environment — an API key,
every `QDRANT__` variable whatever its case, `RUN_MODE` — any command or
entrypoint flags, and its mounts: **a config file mounted into it** (such as
`/qdrant/config/production.yaml`) can hold an API key or any other setting, and
none of that shows in its environment. A recreate that drops one does not
behave like the old container: a dropped API key leaves the new one open, and a
dropped setting can move where it stores its data. This lists them and changes
nothing — **but it prints their values, an API key included**, so run it where
no one can read your screen, and do not paste its output anywhere:

```sh
docker inspect -f '{{json .Config.Env}} {{json .Config.Cmd}} {{json .Config.Entrypoint}} {{json .Mounts}}' qdrant
```

Step 4 says where each one goes; what the image sets itself, such as `PATH`, comes
back with the same image. **If it has an API key** — in its environment or in a
mounted config file — change `H=()` at the end of step 1's first line to
`H=(-H 'api-key: <the key>')`. Every `curl` below passes `"${H[@]}"`, except the
two that check what a request made WITHOUT the key gets: step 1 records whether
the old container answers one, and step 6 fails if the new one answers where
the old one refused. And:

- **Keep the same image.** Step 4 reuses the image the container RUNS (its
  image ID, `{{.Image}}`), not the tag it was created from: a tag may have
  moved since (a later pull), and recreating from it would run a different
  Qdrant version. A version change is a separate upgrade, not part of this.
- **Aliases are not in a collection snapshot.** Step 1 saves them to
  `$B/aliases.json`, step 5 re-creates them and step 6 checks them.
- **Snapshot files you keep inside the container** — at `/qdrant/snapshots`,
  not on a volume or a host folder — are copied out in step 3, before the old
  container is stopped.

**Two addresses: `O` for the old container, `Q` for the new one.** Step 1 talks
to the OLD container at `O`; steps 5 and 6 talk to the NEW one at `Q`, which is
`http://127.0.0.1:6333` because step 4 publishes it there. Step 1's second line
reads `O` from `docker port qdrant 6333/tcp`, so a container created with `-P`
(a random port) or published on a LAN address is found where it is; `0.0.0.0`
and `[::]` are read as `127.0.0.1` and `[::1]`. **If it prints nothing** — a
container on the host's network (`--network host`) publishes no port, and a
stopped one has none — step 1 stops and says so; start the container if it is
stopped, and otherwise replace step 1's second line with `O=http://` followed
by the address and port where the old container answers. On Linux, a container
on the host's network answers at `http://127.0.0.1:6333`. On Docker Desktop it
answers on this machine only if Docker Desktop's host networking is turned on;
if nothing answers, this procedure cannot read it from here — stop, nothing has
changed. **If `docker port` prints an address this machine does not reach,**
step 1 says the old container did not answer at it: set `O` by hand the same
way. Never point `Q` at the old container: step 5 waits for the new one at
`Q`, and would wait forever.

**1. Snapshot and download every collection, and save the aliases,** into a
new folder in your home directory (never the project). Paste the numbered
blocks into the SAME shell — they share `$O`, `$Q`, `$S`, `$B` and `$H` — and
each block whole. This one stops at the first failure and says so: `STEP 1
FAILED` when `jq` is missing, `docker port` printed no address, or the old
container did not answer; `SNAPSHOT FAILED` with the collection it stopped at.
For each snapshot it keeps what Qdrant answered when it made it — the size and
the SHA-256 checksum of the file — for step 2 to check the download against:

```sh
Q=http://127.0.0.1:6333; S="$(date +%Y%m%d-%H%M%S)"; B="$HOME/qdrant-snapshots-$S"; H=()
O="$(docker port qdrant 6333/tcp 2>/dev/null | head -1 | sed -e 's/^0\.0\.0\.0:/127.0.0.1:/' -e 's/^\[::\]:/[::1]:/' -e 's#^#http://#')"
if ! command -v jq >/dev/null 2>&1; then echo "STEP 1 FAILED: jq is not installed — install it, then paste this block again"
elif [ -z "$O" ]; then echo "STEP 1 FAILED: docker port printed no address for the old container — start it if it is stopped; if it runs, replace this block's second line with O=http://<address>:<port> where it answers"
elif mkdir "$B" &&
  curl -s -o /dev/null -w '%{http_code}' "$O/collections" > "$B/nokey-status.txt" &&
  curl -sf "${H[@]}" "$O/aliases" > "$B/aliases.json" &&
  curl -sf "${H[@]}" "$O/collections" > "$B/collections.json" &&
  jq -r '.result.collections[].name' "$B/collections.json" > "$B/collections.txt"; then
  while IFS= read -r c; do
    curl -sf "${H[@]}" -X POST "$O/collections/$c/snapshots" > "$B/$c.created.json" &&
    n="$(jq -r '.result.name // empty' "$B/$c.created.json")" &&
    [ -n "$n" ] &&
    curl -sf "${H[@]}" "$O/collections/$c/snapshots/$n" --output "$B/$c.snapshot" &&
    [ -s "$B/$c.snapshot" ] || { echo "SNAPSHOT FAILED: $c"; break; }
  done < "$B/collections.txt"
else echo "STEP 1 FAILED: the old container did not answer at $O, or it needs its API key (set H in the first line)"
fi
```

**2. Check that step 1 finished:** `jq` is installed, and `sha256sum` or
`shasum`; the number of collections the server listed matches the number of
names step 1 saved — and is not 0 — and every snapshot file has exactly the
size and the SHA-256 checksum Qdrant reported when it made it. A file being
there proves nothing: a download cut short — a full disk, a dropped
connection, or Ctrl-C, which prints nothing at all — leaves a partial file
that is not empty. Go on only if this prints `ALL SNAPSHOTS PRESENT`;
`MISSING OR INCOMPLETE` names a collection whose snapshot is not all there, or
whose record from step 1 is missing — fix the cause (disk space, above all)
and paste step 1 again, which starts a new folder:

```sh
m=0; command -v jq >/dev/null 2>&1 || { echo "STEP 2 FAILED: jq is not installed"; m=1; }
if command -v sha256sum >/dev/null 2>&1; then K=(sha256sum); elif command -v shasum >/dev/null 2>&1; then K=(shasum -a 256); else K=(); echo "STEP 2 FAILED: neither sha256sum nor shasum is installed, so the snapshots cannot be checked"; m=1; fi
[ -s "$B/nokey-status.txt" ] && [ -s "$B/aliases.json" ] && [ -s "$B/collections.json" ] && [ -f "$B/collections.txt" ] || { echo "STEP 1 DID NOT FINISH"; m=1; }
e="$(jq '.result.collections | length' "$B/collections.json" 2>/dev/null)"; g="$(grep -c '' "$B/collections.txt" 2>/dev/null)"
[ "$e" -gt 0 ] 2>/dev/null && [ "$e" = "$g" ] || { echo "COUNT MISMATCH: the server listed ${e:-?} collections, collections.txt has ${g:-?} (they must match, and not be 0)"; m=1; }
while IFS= read -r c; do
  z="$(jq -r '.result.size // empty' "$B/$c.created.json" 2>/dev/null)"; w="$(jq -r '.result.checksum // empty' "$B/$c.created.json" 2>/dev/null)"
  [ -n "$z" ] && [ -n "$w" ] && [ -f "$B/$c.snapshot" ] && [ "$(wc -c < "$B/$c.snapshot" | tr -d '[:space:]')" = "$z" ] &&
    [ "${#K[@]}" -gt 0 ] && [ "$("${K[@]}" < "$B/$c.snapshot" | cut -d' ' -f1)" = "$w" ] || { echo "MISSING OR INCOMPLETE: $c"; m=1; }
done < "$B/collections.txt"; [ "$m" = 0 ] && echo "ALL SNAPSHOTS PRESENT"
```

**3. Copy out the snapshot files you keep inside the container** — skip this
if you keep none there, or keep them on a volume or a host folder. The old
container is stopped in step 4, and one started with `--rm` is deleted when it
stops. The copy also holds the snapshots step 1 just made. Go on only if this
prints `SNAPSHOT FILES COPIED`:

```sh
docker cp qdrant:/qdrant/snapshots "$B/old-snapshots" && echo "SNAPSHOT FILES COPIED"
```

**4. Recreate it on loopback** with the same image and the same settings. The
old container is renamed while it still runs, so a name clash stops this before
anything is stopped. Before you paste it, add the settings you listed before
you started: each environment variable as `-e NAME=value` before `"$I"`; each
mount that is not the storage — **a config file above all** — as
`-v <source>:<destination>` before `"$I"`, at the same destination (a key or
setting kept in a config file is lost without it); and the command after `"$I"`
(and `--entrypoint`, before `"$I"`) if you started it with one. Do not mount the
old storage again: the new container gets a fresh volume, which step 5 fills.
If a setting moves the storage path away from `/qdrant/storage`, mount the
volume at that path instead:

```sh
I="$(docker inspect -f '{{.Image}}' qdrant)" &&
docker rename qdrant qdrant-old &&
docker stop qdrant-old &&
docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v "qdrant_storage_$S:/qdrant/storage" --restart unless-stopped "$I"
```

**5. Restore every collection, then the aliases,** once the new container
answers. **It stops at the first upload that fails** and prints
`RESTORE FAILED` with that collection: the collections after it in the list
were NOT tried, and no alias was restored. Fix the cause and paste this block
again for the rest — it uploads every collection again, which replaces the ones
already restored with the same snapshot; step 6 shows what is still missing:

```sh
until curl -sf "${H[@]}" "$Q/collections" >/dev/null; do sleep 1; done &&
f=0 &&
while IFS= read -r c; do
  curl -sf "${H[@]}" -X POST "$Q/collections/$c/snapshots/upload?priority=snapshot" -F "snapshot=@$B/$c.snapshot" >/dev/null ||
    { echo "RESTORE FAILED: $c — the collections after it were NOT tried; fix the cause and paste this block again"; f=1; break; }
done < "$B/collections.txt" &&
[ "$f" = 0 ] &&
jq -c '{actions: [.result.aliases[] | {create_alias: {collection_name, alias_name}}]}' "$B/aliases.json" > "$B/alias-actions.json" &&
{ [ "$(jq '.actions | length' "$B/alias-actions.json")" = 0 ] ||
  curl -sf "${H[@]}" -X POST "$Q/collections/aliases" -H 'Content-Type: application/json' --data-binary "@$B/alias-actions.json" >/dev/null ||
  echo "ALIAS RESTORE FAILED"; }
```

**6. Check.** Go on only if this prints BOTH `ALL COLLECTIONS RESTORED` and
`ALL ALIASES RESTORED`, and compare the `points_count` of each collection
(`curl -s "${H[@]}" "$Q/collections/<name>"`) with the old one's if you noted
them. If the old container refused a request made without its API key, this
first makes one such request to the new one; if that is answered it prints
`API KEY LOST` and neither success line — the key, from its environment or a
mounted config file, did not reach the new container:

```sh
k=0; [ "$(cat "$B/nokey-status.txt" 2>/dev/null)" = 200 ] || [ "$(curl -s -o /dev/null -w '%{http_code}' "$Q/collections")" != 200 ] || { echo "API KEY LOST: the new container answers without the API key the old one required"; k=1; }
[ "$k" = 0 ] && [ -f "$B/collections.txt" ] && curl -sf "${H[@]}" "$Q/collections" | jq -r '.result.collections[].name' | sort > "$B/restored.txt" &&
sort "$B/collections.txt" | diff - "$B/restored.txt" && echo "ALL COLLECTIONS RESTORED"
[ "$k" = 0 ] && curl -sf "${H[@]}" "$Q/aliases" | jq -c '[.result.aliases[] | [.alias_name, .collection_name]] | sort' > "$B/aliases-restored.json" &&
jq -c '[.result.aliases[] | [.alias_name, .collection_name]] | sort' "$B/aliases.json" | diff - "$B/aliases-restored.json" && echo "ALL ALIASES RESTORED"
```

Only then remove the old container (`docker rm qdrant-old`, if it is still
there) — until step 6 passes it is your way back — and keep `$B` until you are
sure. Run the adoption's `claude mcp add` line for Qdrant, if it was skipped.

**If a step fails.** Nothing is lost before step 4: the old container still
runs with its data. In step 4, if `docker run` fails, the snapshots in `$B`
are intact: fix what it reports and run that line again, or bring the old one
back with `docker rename qdrant-old qdrant` and `docker start qdrant` — which
restores the data only if it lived on a volume or in the container itself, not
if it was in memory or the container was started with `--rm`. In step 5, a
failed upload stops the loop: the uploads before it stay in place, the
collections after it were not tried — fix the cause and paste step 5 again for
the rest, and step 6 shows what is still missing. In step 6, `API KEY LOST`
means the new container was created without the key: remove the NEW one
(`docker rm -f qdrant` — the old one is still `qdrant-old`), paste step 4's
last line again with the key's `-e` setting or its config file's `-v` added,
then steps 5 and 6. A collection name with characters that are not safe in a URL needs
percent-encoding in these URLs.

There is deliberately **no file-copy route for the data**: copying
`/qdrant/storage` by hand misses whatever is mounted under it (a tmpfs at
`/qdrant/storage/collections` comes back empty), and `docker cp` reads nothing
from a tmpfs. The snapshot goes through the server, which sees all of it.
Step 3's `docker cp` copies only snapshot files you keep yourself, never the
storage.

## Where it lands: phase 0, always

**Every adopted project lands at phase 0.** Not at a phase derived from your
artifacts, not at one you claimed, not "provisionally" pending a later
promotion. Phase 0, and then forward through the ordinary gates like any other
project.

```text
══ Act 2 complete — the project is adopted and sitting at phase 0
   Your project is now under the framework and it starts where every project
   starts: phase 0. Nothing has been marked as already done, and nothing was
   guessed about how far along you are — you will be asked about that instead.
```

### Why it does not ask how far along you are

An earlier version of this driver asked. It put one question to you — *is the
project built out, or are you still building it?* — and used your answer, floored
by what the scan could corroborate, to decide which phase to place you at.

That question is **deleted**, and so is the idea of computing an answer in its
place. The reasoning is short: you are using this framework because you are not
already following a formal software process, so asking you to grade your own
position within one is asking the wrong person. And deleting a question whose
answer cannot be trusted does not mean the answer must be computed some other
way — it can equally mean the question does not need answering. Here it does not.

**What you lose is nothing you had.** A phase is not a score; it is a statement
about which gates have been crossed with evidence. Placing a project at phase 3
without that evidence produces a project that fails its own next gate — the
gates are cumulative by contract, so each one assumes every earlier one really
happened. Landing at 0 costs you the walk through Phase 0 and buys you a project
whose recorded position is true.

**What the scan learned is not thrown away** — though be precise about where it
goes. Scout's **intake-prefill table** is what becomes pre-fill: the cells the
scan could derive are confirmed with you and written into `PROJECT_INTAKE.md`.
The artifact ladder, the test-debt census and the reality probes become
**context** — they are committed with the project (`.claude/adoption/`
`scout-report.json`, `.claude/test-debt.json`) and the §13 prompt points an
agent at both. What none of it becomes is a shortcut past a gate. A project that
already has tests, a deploy lane and architecture docs gets an intake that says
so. What it does not get is a shortcut past a gate.

### What every adoption gets

- **The full secrets scan.** History does not care what phase you land at.
- **No forward exemption.** Every exemption in this design is scoped to commits
  **at or before** the adoption commit. There is no arm anywhere that exempts a
  commit written after adoption day.
- **The same demand set as a greenfield project.** Strip the adoption record out
  of an adopted project and its gates ask for exactly the same things.

---

## The reverse intake

Ordinary intake asks a person and writes a document. Reverse intake starts from
what the scan already derived and asks you to confirm it — for the parts that are
derivable, and only those.

```text
══ The interview
   Some of this the scan already answered — you will see the answer and where it
   came from, and you can keep it or change it.
   The rest is not asked here. Questions only a person can answer belong to the
   assessment, which is a conversation with an agent rather than a form, and this
   step leaves those cells blank for it.

Project Identity
   The scan found: legacy-app
   Where that came from: package.json name
Keep 'legacy-app' as the answer?
   1) keep it
   2) change it
   Answer with the number or the words:
```

Three classes across the fifteen intake sections — and **this step now asks
exactly one of them**:

| Class | Behaviour here | Example |
|---|---|---|
| **Scan-derived** | **ASKED.** Prefilled with **the value and its provenance**, then keep-it / change-it. "Change it" falls through to the ordinary question | Project Identity, Repo Setup, Testing & Bug Tracking, Tooling Configuration |
| **Judgement** | **NOT asked here.** Recorded blank and named as the assessment's | Business Context, Constraints, Features & Requirements, Technical Preferences, Revenue Model, Governance Pre-Flight, Accessibility, Distribution & Operations, Known Risks |
| **Non-skippable** | **NOT asked here** either — see below | Data classification |

**Why the questions only you can answer are not asked here.** They belong to the
**assessment** — a conversation with an agent about what this project is and what
it is supposed to do, rather than a form. Filling a form badly at the end of a
shell script is not the same as being interviewed, and the answers feed a fitness
verdict that needs the reasoning behind them.

Cells left blank are **recorded as blank and labelled**, not dropped:

```text
Business Context
   Not asked here — this one is asked in the assessment.
```

**Data classification moved with them, and that is worth explaining rather than
just noting.** It used to be refused-if-skipped right here, and the reason given
was mechanical: the Phase 1→2 ZDR backstop hard-`[FAIL]`s whenever
`current_phase >= 2`, and an adoption used to be able to land at phase 4 on its
first commit. **It cannot any more** — every adoption lands at phase 0.

The backstop fires at `current_phase >= 2` **however that number is reached**,
and it is a hard failure rather than a warning. That is deliberately not the
same claim as *"you cannot get to phase 2 without answering"*: other framework
commands can advance the number (`scripts/process-checklist.sh` does, when it
verifies your Phase 2 setup). What holds is that the gates are **cumulative and
keyed to evidence** — arriving at a rung without the evidence fails the gate on
the evidence, regardless of what moved you there.

**Adoption now writes `APPROVAL_LOG.md`, and the gate runs.** Until WP9b it did
not, and the gate exited on the missing file before it read the phase at all —
so an adopted project could not run its own phase gate. Observed on a
freshly-adopted project today:

```text
$ bash scripts/check-phase-gate.sh
Phase Gate Consistency Check
Current phase: 0


Adoption Stamp Integrity
[OK] Adoption stamp present and intact (adopted: …)

Phase gates consistent.
```

The log adoption writes is the **tier-matched template**, carrying no dated
gate-approval row — because this adoption approved nothing. It makes the
question answerable; it does not answer it. The Adoption **Record** is appended
to the end of that same log — see [The Adoption Record](#the-adoption-record).

**You will still be asked.** Three routes reach the question, and all three are
exercised by the test suite rather than assumed:

| Route | What it does |
|---|---|
| `bash scripts/resume.sh` | What the run tells you to do next. Before the assessment it prints the assessment prompt, which asks for the classification; after it, the initialization prompt from this project's own Section 13, which names the classification as **not optional**. |
| `bash scripts/intake-wizard.sh --resume` | Walks the intake from Section 1, which includes **Section 5 — Data Classification**. |
| `bash scripts/reconfigure-project.sh --field data_classification --new <value>` | The escape hatch the Phase 1→2 gate names in its own failure message, if you get there first. |

> **The assessment asks for it.** The assessment conversation (Act 3) asks how
> sensitive the project's data is, and its finisher (Act 4) records the answer
> where the Phase 1→2 gate reads it ([The assessment](#the-assessment--act-3-and-act-4--ships-wp12a)).
> Until then the cell stays blank, and the routes above fill it too. The
> direction is fail-closed: a project with no classification cannot cross its
> Phase 1→2 gate.
>
> Every one of those three routes was **broken on an adopted project** until
> this was built, and none of the breakages announced itself — one pointed at a
> section that did not exist, one crashed internally and then reported success
> having skipped the question, and one died on a file adoption never wrote.
> They are recorded here because "you will be asked later" is worth exactly
> what an execution of the asking says.

An out-of-vocabulary answer to a choice question is refused by name rather than
coerced:

```text
[REFUSED] 'legacy-app' is not one of the answers offered for: who the project is for
          Adoption did not begin. Nothing was committed and nothing was written to this project.
```

---

## What gets written, and in what order

### The order is `APPROVAL_LOG.md` → `phase-state.json` → intake → the secrets dispositions → `manifest.json` → the framework documents → the Adoption Record → the write set

The secrets dispositions come before `manifest.json`, so an acceptance that
cannot be recorded stops the run before the project reads as adopted. The framework documents follow `manifest.json` so they are written under a
stamped adoption, and precede the record so the record stays the last thing in
the log. The last two are ordered by what they read, not by taste. The **Adoption
Record** names the commit adoption started from — the tip the project was on
when adoption ran, the parent of the adoption commit — and takes that value from
the adoption *stamp*, which the `manifest.json` stage writes — one fact, one
source, rather than a second `git rev-parse HEAD` that could disagree. The
**write set** is last because it records what every stage before it wrote.


That order is data in the driver, not scattered through it, and it is chosen
because the two half-states are **not symmetrical**:

| Partial state | `check-phase-gate.sh` | Enforcement tier | Net |
|---|---|---|---|
| **phase-state present, manifest absent** | Runs to a verdict. At the resting state that is `Current phase: 0` / `Phase gates consistent.` → rc 0 | **strict** (missing manifest → strict) | **Gates live, strictest tier.** The commit-time ladder is what protects this row; before WP9b the phase gate appeared to block it, but only because `APPROVAL_LOG.md` was missing — an incidental refusal, not a consistency verdict |
| **manifest present, phase-state absent** | `No .claude/phase-state.json found — skipping phase gate check.` → rc 0 | reads the field | **Gates entirely absent.** An adopted-looking project with no enforcement |

Writing the approval log and phase-state **before the manifest** means no
interruption can land in the bottom row. That is what the help text means by
*"it stops in the SAFE direction: the project ends up more strictly gated than
it was, never less."*

Since WP9b there is a third interruption point, between the approval log and
phase-state, and it is inert: with no `.claude/phase-state.json` the gate prints
`No .claude/phase-state.json found — skipping phase gate check.` and exits 0,
exactly as it does on any project that has never been adopted. A log with no
phase-state claims nothing. **That is why the log goes first** — written last,
every death inside the state stage would land on phase-state-present /
log-absent, which the gate hard-refuses.

`init.sh` uses the opposite order, and that is not a counter-example: creation is
one uninterrupted run ending in a commit, so it never leaves partial state
behind. Adoption can legitimately halt at a question or a blocker.

### A halt before the writes leaves nothing at all

Measured, hashing every non-`.git` file before and after a run that halted at the
data-classification question:

```text
tree before: c57773947041bac7f2b0d16fbd012b4318c232fe  -
tree after : c57773947041bac7f2b0d16fbd012b4318c232fe  -
IDENTICAL — a halted run wrote nothing
```

### Staging is explicit, never `git add -A`

```text
══ Committing exactly what was written
   79 file(s), named one by one. Anything else you had in progress stays
   exactly as you left it — unstaged, uncommitted, untouched.
```

The driver builds an explicit array; anything not in it is never staged. The
counter-example this exists to avoid is `create_project()`'s
`git add -A` + `git commit --no-verify`, which on an existing project would sweep
your uncommitted work into a framework commit with verification bypassed.

Observed on a completed run — one commit,
`chore: adopt <project> into the Solo Orchestrator framework`, containing **79**
files: the nine below, and the framework `scripts/` tree (70 of them — measured 2026-09-16;
the count follows `init.sh`'s copy list and drifts with it).
**Your own files are not in it.**

```text
.claude/adoption/scout-report.json   .claude/intake-progress.json
.claude/manifest.json                .claude/orchestrator-source.json
.claude/phase-state.json             .claude/process-state.json
.claude/test-debt.json               APPROVAL_LOG.md
PROJECT_INTAKE.md
```

*(This list read six files and 69, then eight and 76, before each re-measure. It
had been correct when written and has now been falsified three times over — by
the test-debt ledger WP5b added, by `orchestrator-source.json`, and by
`APPROVAL_LOG.md`, which **WP9b added while this very paragraph warned that
whoever adds a writer must re-run the count**. An enumeration
of what a run writes has to be re-run by whoever adds a writer; nothing checks
it.)*

*(And again: since `## BL-318:` G1 (2026-10-03), `.claude/test-command` joins
these whenever the operator kept the test command the scan offered and the
project had no such file — see "Three things to know before you rely on it" below. The 79 above
predates it and the other writers added since. One measured run on 2026-10-03, a
four-file uv project with no Guardrails clone, committed 112 files.)*

### What lands in `scripts/`

```text
══ Installing the framework's own scripts
   Installed 70 framework script(s); left 0 of your own file(s) untouched.
```

The set is **derived from `init.sh`'s own copy list** rather than duplicated, so
an adopted project's script set cannot drift from a scaffolded one's. Measured,
comparing this adopted project against a project scaffolded by `init.sh` on the
same tree: **70 scripts each, and the difference in both directions is empty** (measured
2026-09-16; it was 68 each before `## BL-254:` added two).

The commit-msg hook comes from the same emitters `init.sh` uses. Measured — the
adopted and the scaffolded project's `.git/hooks/commit-msg` have the **same
SHA-1** (`6a68f4e3…`, 154 lines):

```text
adoptee:    6a68f4e3f1b5a8e00e830ec2073229736aa58df7  (154 lines)
demo-delta: 6a68f4e3f1b5a8e00e830ec2073229736aa58df7  (154 lines)
```

```text
══ Turning the gates on
   Commit-msg gate installed (it composes with whatever was already in that hook).
```

---

## The adoption stamp, and what happens when it is lost

Adoption writes one additive block into `.claude/manifest.json`. Observed:

```json
{
  "schemaVersion": 2,
  "adopted": true,
  "adoptedAt": "2026-08-10T20:18:37Z",
  "adoptedAtCommit": "c0ba12ef6ecd620b57c55581435138f53a098da2",
  "scannerReportSha256": "c5ac90a264f61d55cb3423151d04f8161bf671e3272d09fe14fabad80f302efd"
}
```

**Five keys, and the four that left are as informative as the five that
stayed.** `scenario` went with the question that produced it; `landedPhase`
went with the idea of deriving a phase at all; and `certification` and
`blockersAccepted` went because the pass that filled them is retired and three
permanently-empty arrays read as "measured, nothing found" to anyone who does
not know the history. `schemaVersion: 1` in a manifest means a record written by
the earlier driver, which carried all four.

It is written **once**, from **one** call site, and never re-stamped. A second
stamp attempt is refused rather than overwriting the anchor.

### The loss cannot be prevented — so it is reported loudly

`.claude/manifest.json` has a wholesale writer that lives **upstream, in a
different repository**: a repair path (`verify-install.sh --auto-fix` →
`fix_framework_manifest()`) delegates to the Claude Dev Framework's own
`init.sh`, which rewrites the manifest from a hardcoded key set carrying none of
this framework's keys. It is missing-file-gated, so it never destroys a stamp
that is present — but a manifest lost to any cause is regenerated *empty of
everything this framework wrote*, and the project silently un-adopts.

That writer cannot be stopped from here. So the framework refuses to be quiet
about it. The witness is the **committed** copy of the manifest at `HEAD`, which
a working-copy regeneration does not touch.

Observed — `bash scripts/check-phase-gate.sh` in an adopted project whose working
manifest lost the block:

```text
Adoption Stamp Integrity
[FAIL] Adoption stamp LOST from .claude/manifest.json.
       The copy committed at HEAD records this project as ADOPTED; the working
       copy does not. The project has silently un-adopted: every gate arm that
       reads the adoption flag now reads FALSE, and the certification record of
       how this project entered the framework is gone from the live manifest.
       LIKELY CAUSE: the manifest was missing and a repair path regenerated it
       wholesale from the upstream framework's own key set, which carries none
       of this framework's keys. That writer is upstream and cannot be stopped
       from here — which is why this is reported rather than prevented.
       REPAIR (re-merges only the adoption block, keeps the regenerated rest):
         git show HEAD:.claude/manifest.json | jq '.adoption' > /tmp/adoption.json && \
         jq --slurpfile a /tmp/adoption.json '.adoption = $a[0]' .claude/manifest.json \
           > .claude/manifest.json.tmp && mv .claude/manifest.json.tmp .claude/manifest.json
```

With the stamp intact the same gate prints:

```text
Adoption Stamp Integrity
[OK] Adoption stamp present and intact (adopted: 2026-08-10T20:18:37Z)
```

**One honest residual:** a stamp written but not yet **committed** has no
witness, so a manifest regenerated *inside* the adoption window is a loss this
cannot see. That window is minutes long and ends at the adoption commit.

---

## The Adoption Record

At the end of your `APPROVAL_LOG.md`, under its own `## Adoption Record`
heading, adoption writes down what it did. Before this existed, the run's own
findings lived in your terminal scrollback and nowhere else — the driver said so
out loud, and the personal-tier secrets block told you to *keep this transcript*,
because real credentials found in your history had no permanent home.

It records, in these sections (six on a clean project, eight when you supply
a `--dispositions` file):

- **How this project was adopted** — the day, the enforcement tier, whether
  proof-of-concept mode is on, and **the commit you were sitting on** when
  adoption ran. That commit is the anchor that bounds the pre-adoption TDD
  exemption: everything at or before it is history the framework inherited, and
  every commit after it is held to the ordinary rules.
- **What the credential scan read, and what it found** — the scanner, **its
  version**, who ran it, under whose rules, the outcome, how many commits it
  read, and how many findings there were:

  ```text
      | Field | Value |
      |---|---|
      | Scanner | gitleaks |
      | Scanner version | 8.30.1 |
      | Run by | adoption |
      | Rules | framework |
      | Outcome | scanned |
      | Commits read | 412 |
      | Findings | 1 |
  ```

  *(The two header rows are part of what the renderer emits; an earlier draft of
  this block dropped them, which made it an edited excerpt on a page that
  promises transcripts. The counts are this fixture's, not a universal.)*
- **The findings, by fingerprint** — one row per match: the rule, the file and
  line, and the fingerprint. **Never the matched value.** If you supplied a
  `--dispositions` file, what was decided about each one and by whom follows in
  its own table; if you did not, the record says so plainly rather than leaving
  a blank that reads as a clean bill of health.
- **What of yours was archived** — the archive path and the `--re-add` line.
- **What else this run measured** — the count of source files with no test, the
  hooks directory git will actually use, and how long the pre-write rehearsal
  took over how many megabytes.

It then names the three things a complete record would carry and this build
cannot: the assessment's findings and verdict, the interview answers, and the
in-production declaration. They are **named rather than omitted**, because a
field that is simply absent reads like a measurement that came back empty.

### It cannot be mistaken for an approval, and that is enforced rather than promised

`APPROVAL_LOG.md` is the file four separate programs parse to decide whether a
phase gate was crossed with evidence. Putting a free-text record into it is only
safe if the record cannot be read as one, so the record holds an eight-part
structural contract — no `Phase N → Phase N+1` line, no named approval-row
literal, no attorney or legal-review heading, no pen-test exemption phrase, no
table row starting at column 0, no `date` substring in its prose, no
`[YYYY-MM-DD]`-style placeholder, and its own `## ` heading placed after every
gate section.

**The contract is checked before a byte is written.** If the rendered record
would violate any clause, nothing is appended and the run refuses, naming the
clause on stderr. The reason it is enforced rather than merely written carefully
is that part of the record is *your* text — a path inside your repository, the
name and reason you wrote on a disposition — and some entirely ordinary
sentences are dangerous here. A disposition signed by a *"pen test team"* with
the reason *"exempted by policy until Q3"* assembles into a line matching the
framework's pen-test exemption check, which takes no window and no date: it
greps the whole file. Copied in verbatim, two innocent cells would tell this
framework a penetration test had been exempted.

So the **row** is tested as a row, and cells are withheld from the right until
it is clean. Real output, from that exact input:

```text
    | Fingerprint | Outcome | Decided by | Reason |
    |---|---|---|---|
    | dedba58f988140f973b013670a4d6834664b873a:src/config.py:generic-api-key:2 | accepted-risk | pen test team | (withheld: this text spells a phrase this log is parsed for) |
```

The fingerprint, the outcome and the person all survive; only the free-text
reason goes, because it is the rightmost cell and the cheapest to lose.

It is withheld rather than rewritten on purpose. Lowercasing your `Phase` or
clipping your `exempted` would put words in your mouth, quietly, in the one
document that exists to be trusted later. And it is withheld rather than
refused, because an adoption must not fail over a security team's name. Ordinary
text that merely *resembles* a trigger is untouched — a finding in
`src/updater/config.yml` is printed exactly as it is.

*(The first cut of this checked each cell in isolation, which is not what the
readers do — they read lines. A real organizational adoption with the
disposition above was **refused outright**, with the reason discarded by the
rehearsal's output relay. Both are fixed: the row is tested as a row, and the
failing clause is printed on stderr so the rehearsal relays it.)*

**Written once.** A second run finds the heading and leaves the log alone; the
record is never rewritten, for the same reason the adoption stamp refuses to be
re-stamped.

---

## The TDD exemption and its bound

You cannot go back and write the tests first for code written in 2023. That is
the one requirement adoption genuinely cannot re-run, so it gets an exemption —
and the exemption is **bounded to commits at or before the adoption commit,
nothing after adoption day, ever**.

Precisely: the exemption applies only while the stamp's `adoptedAtCommit` anchor
equals `HEAD` **and** the copy of the manifest committed at `HEAD` does not yet
record the adoption. That is the adoption run itself. **Once the adoption commit
lands, the exemption closes permanently** — the committed manifest now carries
the block, and every later commit is post-adoption by construction.

Observed on an adopted project, on the non-bypassable tier, staging an
implementation file with no test:

```text
$ printf 'feat: add an adder\n' > .git/COMMIT_EDITMSG
$ bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only

[FAIL] BL-072 TDD ordering: 'feat:' commit ships implementation without a matching test.
[FAIL]   Subject: feat: add an adder
[FAIL]   Tier is NON-bypassable (sponsored POC / production) — test-first ordering is ENFORCED.
[FAIL]   Impl files with no accompanying test (none earlier on the branch):
[FAIL]     - src/add.js
[FAIL]   Write the failing test first (test-driven), then re-commit.
[FAIL]   To attest a legitimate exception (RECORDED to tdd_attestations[], not silenced):
[FAIL]     SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='<why a same-commit test is impractical>' git commit ...
[FAIL]   The commit is BLOCKED.
rc=1
```

An adopted project gets **the same commit-time treatment** as a scaffolded one
from its adoption commit onward. As everywhere else in this framework, the tier
decides whether that is a hard block: `deployment: organizational` or
`poc_mode: sponsored_poc` blocks the commit, as above; `personal` and
`private_poc` do not. That predicate is unchanged by adoption — it reads
`.claude/phase-state.json`, which the driver writes correctly, exactly as it does
in a scaffolded project.

> **This used to say the two birth paths write different manifests. They do
> not, any more — `## BL-221:` is Closed (PR #356) and the keys are written.**
> Measured on an adoption at this tree:
>
> ```json
> {"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}
> ```
>
> | Key in `.claude/manifest.json` | Scaffolded by `init.sh` | Adopted |
> |---|---|---|
> | `deployment` | `"personal"` | `"personal"` — from the tier question, its only source |
> | `poc_mode` | `null` | `"production"` |
> | `enforcement_level` | `"strict"` | `"strict"` |
>
> **The paragraph that stood here told you to set those keys by hand, and
> following it would have been actively harmful** — `.claude/manifest.json` is
> where the adoption stamp lives, so a botched hand-edit trips
> `[FAIL] Adoption stamp LOST` and costs you the record of how the project
> entered the framework. It was correct when written and was left behind by the
> fix; it is recorded here rather than deleted because "advice that outlived its
> defect" is worth recognising as a category. **Do not hand-edit the manifest.**
>
> What the paragraph was about is still worth knowing, because it is why the
> keys must never go missing: `assert_choosable` in
> `scripts/lib/enforcement-level.sh` once read `jq -r '.deployment // "personal"'`,
> so an **absent** key resolved to the **permissive** tier while
> `read_enforcement_level` failed *closed* to `strict` on the same manifest —
> two readers, opposite directions. Both halves are fixed: the writer supplies
> the keys and the predicate is fail-closed (`# BL-221-TIER-FAIL-CLOSED`).

---

## The test-debt ledger and its ratchet

The exemption above is the one thing adoption genuinely cannot re-run, so it
does not stand alone: it comes with a **forward equivalent** that is fully
enforced from adoption day. The adoption measures your test debt once, writes it
down, and from then on holds you to two rules about the future.

`.claude/test-debt.json`, written during the run and committed with the rest of
the adoption:

```json
{
  "schema": "test-debt/v1",
  "writtenAt": "2026-08-10T23:08:35Z",
  "atCommit": "0d1effdce6abcb4dbb78253374e0c12357ee3b76",
  "method": "A source file counts as untested when no test file's NAME contains its basename stem and it carries no inline test attribute. This is a name-match heuristic, not coverage: ...",
  "count": 1,
  "files": [
    "src/ledger.js"
  ],
  "audit": [
    {
      "at": "2026-08-10T23:08:35Z",
      "action": "created",
      "atCommit": "0d1effdce6abcb4dbb78253374e0c12357ee3b76",
      "previousCount": null,
      "count": 1
    }
  ]
}
```

### The two arms, and the tier they sit on

| Arm | Rule | `no` | `light` | `strict` |
|---|---|---|---|---|
| **Non-growth** | The untested set may not gain a member | silent | warn | **block** |
| **Touch-repays** | A file in the set that is modified must leave it in the same commit | silent | warn | **block** |

Run it against a staged commit:

```text
bash ~/solo-orchestrator/scripts/lib/adopt/adopt-test-debt.sh --check --root .
```

At `strict`, adding a file with no test:

```text
[BLOCKED] test-debt (non-growth): 1 file(s) would ENTER the untested set.
          + src/billing.js
          A test whose NAME carries the file's stem clears it; for Rust, inline #[cfg(test)] counts.
          This project's enforcement tier is strict, so this is a refusal, not a note.
rc=3
```

At `strict`, editing a file that is already in the ledger:

```text
[BLOCKED] test-debt (touch-repays): 1 ledgered file(s) were modified without gaining a test.
          ~ src/ledger.js
          A test whose NAME carries the file's stem clears it; for Rust, inline #[cfg(test)] counts.
rc=4
```

The **same** staged change at `light` — a note, not a refusal:

```text
[WARN] test-debt (touch-repays): 1 ledgered file(s) were modified without gaining a test.
          ~ src/ledger.js
          A test whose NAME carries the file's stem clears it; for Rust, inline #[cfg(test)] counts.
rc=0
```

And at `no`, nothing at all — no output, `rc=0`. That is deliberate and it is
tested in both directions: **a gate that fires at the lenient tier is as wrong
as one that never fires.** A ratchet that blocks a POC project is not a stricter
ratchet, it is the thing that makes people turn the framework off.

| Code | Meaning |
|---|---|
| 0 | Clean, or a tier that does not block |
| 2 | Unusable — no ledger to ratchet against, not a git repository, no `jq` |
| 3 | **Blocked by non-growth** |
| 4 | **Blocked by touch-repays** |

### It is about your code, not the framework's

Adoption installs about sixty of the framework's own scripts into your project.
None of them is ever in your ledger: the census subtracts the framework's
installed inventory, derived from `init.sh`'s own copy list rather than a
hand-kept second copy of it. That holds on **every** write, not just the one the
adoption performs — including the re-baseline this page tells you to run. If the
tool cannot derive that inventory it refuses rather than guessing, because the
alternative is a ledger that demands tests for `check-phase-gate.sh`.

The cost, stated: if you already own a file at a framework path, it is excluded
from your debt too. That path is a collision — the driver refuses to overwrite
it — and the trade is a small under-count instead of a large false refusal.

### Your `.gitconfig` cannot switch the arms off

Every git read the ratchet makes is pinned with `-c core.quotePath=false -c
diff.renames=true`, and both pins are there because their absence was measured:

- without the first, a path like `src/café.js` is rendered quoted and escaped,
  has no recognised source extension, and drops out of the census in silence;
- without the second, `diff.renames=copies` lets a **copied** untested file
  enter the working set at `strict` with no output at all, and
  `diff.renames=false` turns a pure rename back into a delete-plus-add that
  blocks — and keeps blocking after you re-baseline.

Command-line `-c` outranks your repo, global and system config, so these are not
suggestions.

### Renames, and other changes that are not modifications

A **pure** rename of a ledgered file passes. Neither rule is met — the set
gained no member, and nothing was modified — so blocking it would be a
false-FAIL, and an earlier cut that did block it had no way out: re-baselining
put the new path in the ledger and the same rename blocked again from the other
arm. What you get instead is a note, and the run still succeeds:

```text
[NOTE] test-debt: 1 ledgered file(s) were renamed. The ledger still names the old path(s):
          src/ledger.js -> src/ledger-v2.js
          Re-baseline so the debt follows the file:  --write --root .
```

A rename that **also changes the file** is a modification, and the obligation
follows the file to its new path — otherwise `git mv` plus an edit would be a
one-commit way to shed it.

A **mode-only** change — `chmod +x` on a ledgered file — passes for the same
reason: git reports the identical blob on both sides, which is the exact fact
the pure-rename carve-out rests on. Treating one as a modification and not the
other would be two postures for one fact, and the strict one was in the
false-refusal direction.

### Three things it does not claim

1. **"Has a test" is not "is tested."** The ledger answers a filename question
   (plus, for Rust, an inline `#[cfg(test)]` probe), not a coverage question. A
   file with an empty test file beside it satisfies it. The framework has no
   coverage instrumentation in any language, and the `method` field in the file
   says so where the number is actually read.
2. **The ledger is a committed file and you can edit it.** Same property as
   `enforcement_level`: you can route around the block, not around the record.
   Every write appends an `audit` row carrying the count it replaced. Deleting
   the file outright is not a quiet route around the block — at `strict` the
   ratchet then refuses with `rc=2` rather than passing.
3. **Non-growth is weaker than shrinkage.** There is no burn-down schedule. A
   rate is a business decision, and a rate you cannot meet teaches you to
   disable the gate.

**What is still missing, plainly:** nothing yet runs this on every commit. The
commit-time hook belongs to WP7, so today the ratchet is a command you run — by
hand, or from a CI step — not an automatic gate. The tier ladder, both arms and
the ledger are real; the *automatic* part is not.

---

## What is not built yet

This section started as the list of what was designed and not built; all of
it now ships, and each subsection says so in its heading.

One gap has no owning package: **a file of yours sitting where a framework
*script* goes is left alone**, so the framework's version of that script is not
installed; the run names it.

### The Development Guardrails for Claude Code — SHIP (`## BL-296:`)

When `~/.claude-dev-framework` holds a clone, adoption runs **the same
installer a new project runs**. It writes the rules and hooks into
`.claude/framework/`, merges its hooks into `.claude/settings.json`, and records
its version in `.claude/manifest.json`. All of it is part of the adoption commit.
Adoption runs it without a terminal, so it never asks a question. The profile
comes from the installer's own detection over your project's files; when it
recognises nothing (a plain Python, Go, Rust or shell project), adoption uses
`web-api`, the fallback a new project gets, says so, and prints the command
that changes it. The platform itself is decided in the assessment. It runs before the adoption stamp is written, because the installer
replaces `.claude/manifest.json`, and the stamp is then merged into its file.
Measured:

```text
══ The Development Guardrails for Claude Code
   Installed the Guardrails (version 4.3.1, profile web-api) —
   the same installer a new project runs. Its rules and hooks are in .claude/framework/.
```

Three differences from a new project, on purpose:

- **No clone.** Adoption never fetches the Guardrails over the network. Without a
  clone it says **NOT INSTALLED** and prints the two commands that install them
  afterwards, and the Adoption Record says so.
- **No update.** It installs the version on disk, and the Record names it. An
  install the project already had stays at its own version, and from then on
  every session start offers the update while the clone is newer
  ([step 6](#6-afterwards); `## BL-318:` G5).
- **An existing install is left alone.** A project that already has
  `.claude/framework/` keeps its own — including the settings the Guardrails
  keep in `.claude/manifest.json` (profile, rules, hooks, project config,
  discovery answers). Adoption adds its own keys beside them, changes none of
  them, and archives the file as it was, `composed` in the archive's MANIFEST
  like `.claude/settings.json`. Observed (brownfield dogfood run 1's project,
  Guardrails 4.3.0):

  ```text
  ══ The Development Guardrails for Claude Code
     This project already has the Guardrails (.claude/framework/). They were left as they were.
     Their settings in .claude/manifest.json (profile desktop-app, 13 rules, 14 hooks) are kept:
     adoption adds this framework's keys beside them and changes none of theirs.
  ```

  **That archived copy is never put back**, and it is the one entry in the
  archive with no restore line. Nothing of yours in it was changed, so it
  gives nothing back — and it is the file from *before* adoption, with no
  adoption stamp, so restoring it would remove the stamp and every tier key
  (`host`, `mode`, `deployment`, `poc_mode`, `enforcement_level`,
  `remote_url`) and the project would no longer be adopted. Its archive row
  says so in place of the `cp` line, and
  `adopt-project.sh --re-add .claude/manifest.json` refuses
  (`# BL-311-MANIFEST-READD-REFUSE`):

  ```text
  [REFUSED] .claude/manifest.json is not put back: nothing of yours in it was changed
            The re-add did not begin. Nothing was committed and nothing was written to this project.
            Adoption added this framework's keys beside your Development Guardrails
            settings and changed none of them, so there is nothing of yours to restore.
            The archived copy is the file from before adoption, so putting it back
            would remove the adoption stamp and the project's tier (host, mode,
            deployment, poc_mode, enforcement_level, remote_url): the project would no
            longer be adopted, and the phase gate would report the stamp LOST.
            This framework documents no way to undo an adoption, and this is not one.
  ```

  Your `.claude/settings.json` is not refused the same way: putting it back
  keeps the adoption stamp and the tier, and takes out what the framework
  added to it — its session hooks, and any permission rule of its that yours
  did not already carry — which is what a re-add is for.
- **Your `settings.json` keeps its hooks.** The installer replaces the `hooks`
  in `.claude/settings.json` with its own. Adoption puts yours back, ahead of
  the installer's, and stops if it cannot. If the file is not plain JSON, or is
  a symlink, it is restored exactly as it was, and the run and the Adoption
  Record say the Guardrails' hooks are **not registered**.
- **A symlinked `.claude` is not installed into**, because the installer would
  write through the link to wherever it points. The run says NOT INSTALLED.

The installer's own backup directory (`.claude-backup/<timestamp>/`) is
removed, as `init.sh` removes it: the adoption archive already holds every
original. A `.claude-backup` of yours is not touched. If the installer fails,
the adoption stops in the pre-write rehearsal, before anything is written.

### The assessment — Act 3 and Act 4 — SHIPS (WP12a)

The assessment is where you are asked what this project is for, and where the
framework says, **with its reasoning shown**, whether the technology fits those
answers. It is split in two, because half of it is judgement and half is fact:

1. **Act 3 — a Claude Code conversation.** When adoption finishes it prints
   *Next: the assessment (Act 3)*. Run `bash scripts/resume.sh`: on an adopted
   project that has not been assessed it prints the **assessment prompt**
   (adoption wrote it to `.claude/adoption/assessment-prompt.md`). Paste it into
   Claude Code. The session reads the survey, the intake and your archived
   documents, then **asks you** — it does not infer — how many people use the
   project, whether it needs high availability, whether it is internet-facing,
   what growth it must handle, how sensitive its data is (one of `public`,
   `internal`, `confidential`, `pii`, `financial`, `health`, `regulated`), and
   whether it is in production today. It judges fitness **only against those
   answers** — every finding names the answer it is relative to — and writes a
   verdict (`keep` or `rebuild`), a plan, the record
   `.claude/adoption/assessment-record.json`, and folds what is worth keeping
   from your archived documents into the framework's.
2. **Act 4 — the finisher, a shell command** the session runs for you:

   ```bash
   bash "$(jq -r .source_dir .claude/orchestrator-source.json)/scripts/adopt-project.sh" --act4 --root .
   ```

   It **checks the record before it writes anything**, and refuses — naming
   each reason — when the file is not exactly one JSON object, a finding names
   no requirement, `adoptedAtCommit` is not the commit adoption started from
   (the tip just before the adoption commit, not the adoption commit itself),
   *in production* is not a plain true/false, the data classification is not
   one of the seven, a classification other than `public` has neither a ZDR
   attestation nor a written reason (the Phase 1→2 gate would block it later),
   an interview answer uses a key outside the ten the prompt lists, or the
   verdict lacks its technical account or its `## Plain English` half with a
   `Recommendation:` and a `Reason:`. If it stops after it has written
   something, it says what. Measured:

   ```text
   [REFUSED] the assessment record was not accepted, and nothing was written
             The assessment finisher did not begin. Nothing was committed and nothing was written to this project.
             - fitness finding F1 names no interview axis in requirementRef — a finding is relative to a stated requirement (§5.3)
             Fix .claude/adoption/assessment-record.json (or the verdict), then run this again.
   ```

   When the record passes, it records the data classification where the phase
   gate reads it, writes the interview answers into the intake under the intake
   wizard's own keys, and merges the assessment into `.claude/manifest.json` —
   **once**; a second run is refused. It never moves the phase and never writes
   `PRODUCT_MANIFESTO.md`, and it does not commit: it prints what to commit.

   **If Claude Code's auto mode refuses the finisher** — a permission denial,
   not the finisher's own `[REFUSED]` line — run it yourself, typed after `!`
   at the session's prompt or in your own terminal from the project's folder
   (its `jq` lookup reads `.claude/orchestrator-source.json` from where you
   are): it asks you nothing, so either works. See
   [step 2](#2-before-you-start-let-claude-code-run-the-frameworks-scripts).

**If the project is in production, a live incident does not wait for phase 4.**
The assessment records the answer, and an adopted project recorded as in
production may open a hotfix delta below phase 4 (`scripts/delta.sh --open`).
The delta record and `.claude/process-state.json` both record that the
exemption was used, the hotfix still owes its write-up, `validate.sh` reports
it as an INFO rather than a mismatch, and no phase gate reads it. A project not
in production — or assessed before the question existed — is refused as before.

**Either verdict continues from phase 0.** After the assessment, `resume.sh`
opens Phase 0 — measured on a real adoption, the committed assessment passes the
project's own commit checks and the next `resume.sh` prints the project's
Phase 0 prompt. That holds whether or not the project kept a
`PRODUCT_MANIFESTO.md` of its own: a manifesto still byte-identical to the one
adoption found is not Phase 0's work (`# BL-318-G2-ADOPTEE-PHASE0`). Before
`## BL-318:` G2, a project built with an older Solo still had its manifesto, and
`resume.sh` printed the classic resume prompt instead. Once Phase 0 writes the
manifesto, or changes the one the project brought, `resume.sh` prints the
ordinary resume prompt, as for any project mid-Phase 0. Work that does not touch
the manifesto does not count, so until it changes every session opens with the
Phase 0 prompt. The session start says the same thing (`# BL-318-G2-HOOK-BROUGHT`),
and before the assessment it points you at the assessment prompt
(`# BL-318-G2-HOOK-ASSESSMENT`). The Phase 0 prompt is Section 13 as adoption
wrote it, and the assessment does not update it. So it still calls the
judgement cells unasked; the answers given in the assessment are in
`.claude/intake-progress.json`.

### The certification pass — RETIRED, not deferred

This one used to be the largest gap on this page and it is **not going to be
built**. Its job was to certify every gate *below a claimed rung* — the heavier
your claim, the heavier the pass. Two decisions removed its subject: the claim is
gone (nobody is asked how far along they are) and the landing is gone (every
adoption starts at phase 0). With no claimed rung there is nothing to certify
against, and with no landed rung there is nothing to certify for.

**The principle it existed to defend is untouched**: nothing is grandfathered,
every gate is crossed with evidence, and an adopted project's demand set is the
same as a greenfield project's. What changed is that the ordinary gates now do
that job, because the project starts below all of them.

### The test-debt ledger — WP5b — **shipped**

This one used to be on this list and is not any more. The driver no longer
prints a `NOT DONE` block for it: it writes `.claude/test-debt.json` during the
run and both tier-floored arms exist. See
[The test-debt ledger and its ratchet](#the-test-debt-ledger-and-its-ratchet).

The residue is named there rather than hidden here: **nothing invokes the arms
automatically yet**, because the commit-time hook is WP7's. Today it is a
command you run.

### The collision archive, disclosure and re-adds — SHIPS (WP6)

**This section used to say the archive did not exist. It does now.**

Before any framework writer runs, adoption copies the files it would otherwise
land on into `.claude/adoption-archive/<UTC-timestamp>-<pid>/`, mirroring your
paths, and writes a `MANIFEST.json` and a `MANIFEST.md` beside them. The
population is the archive-and-replace bucket: `.claude/settings.json`,
`.claude/settings.local.json`, `.mcp.json`, your `.claude/skills/*/SKILL.md`,
every non-`.sample` file in `.git/hooks/`, and — since WP9b — `APPROVAL_LOG.md`.
**Only files that exist are archived** — an absent surface produces no file and
no manifest row.

**`APPROVAL_LOG.md` is the one entry adoption REPLACES**, and its row says so:
`disposition: "replaced"`, where every other entry reads `kept` (your file is
still where it was) or `composed` (yours is still there, with the framework's
additions: a marked block appended to your commit-msg hook, its rules and hooks
added to your `.claude/settings.json`, its keys added beside the Development
Guardrails' in `.claude/manifest.json`). Adoption writes its own tier-matched
approval log at that path because the phase gate cannot run without one — so if
you keep an approval record there already, **your copy is archived with a
restore line and the framework's template is what sits at the path
afterwards**. That is the only in-place replacement in the run.

Nothing is deleted. Every entry carries a `restore` line you can paste — except
the Development Guardrails' `.claude/manifest.json`, whose `restore` is `null`
and whose `doNotRestore` says why (see *The Development Guardrails for Claude
Code*: its archived copy would un-adopt the project) — and every git-hook entry
carries a short **advisory** description of what it invoked, assembled from a
fixed list of tool names so that no byte of your hook can reach the manifest.

The run then discloses it in full — the sentence, **the list** (every path, not
a count), and the restore instructions:

```text
══ Your own configuration has been archived
   The files below were moved to ensure the framework operates properly, or composed
   with it — yours kept in place, the framework's additions beside it.
   Nothing was deleted. A copy of every one, as it was, is in .claude/adoption-archive/…;
   the lines under each say how to put it back, or why not to.

   yours: .git/hooks/pre-commit
      archived as: .claude/adoption-archive/…/git-hooks/pre-commit
      what it did: Ran `lint-staged`, `npx`, and other commands.
      put it back: cp .claude/adoption-archive/…/git-hooks/pre-commit .git/hooks/pre-commit
```

For the Development Guardrails' manifest the last line is two others
(observed, brownfield dogfood run 1's `.claude/`):

```text
   yours: .claude/manifest.json
      archived as: .claude/adoption-archive/…/.claude/manifest.json
      Nothing of yours was changed: adoption only added this framework's keys beside yours.
      Do not put it back: this copy has no adoption stamp, so restoring it would un-adopt the project.
```

#### Your files are yours — `--re-add`

```bash
bash ~/solo-orchestrator/scripts/adopt-project.sh --re-add .git/hooks/pre-commit
```

It prints the warning, asks you to confirm (there is no default and no skip),
restores the file byte-for-byte at its recorded mode, and writes the choice
into `.claude/bypass-audit.json` as an `adoption_event` row. It refuses one
path, `.claude/manifest.json`, before asking anything: the archived copy would
un-adopt the project (`# BL-311-MANIFEST-READD-REFUSE`). The framework's
premise is opinionated enforcement, not confiscation; it asks only that the
override be findable by whoever reads the ledger next. See
[audit-log-lifecycle.md](audit-log-lifecycle.md#adoption_event).

#### The archive is scanned before anything is committed

`.git/hooks/` is **not** tracked by git; `.claude/` is. So copying a hook into
the archive and committing it would take a credential git had never seen and
put it in your history — **adoption would create the leak.** So the archive is
scanned with `gitleaks` *before* staging, and any entry that matches is written
to disk and **kept out of the commit**, with the reason recorded:

```text
   1 of those copies were NOT added to the commit.
   NOT COMMITTED — secret-match
   A credential in a file git had never seen would have become a credential in
   your history. Rotate it at the source; deleting the file does not un-leak it.
```

**A pattern scanner is a mitigation, not a proof, and this page will not call
it a guarantee.** It recognises credential *shapes*. An internal hostname, a
proxy URL, a customer name or a username matches nothing, and a hook can hold
any of them. Read `MANIFEST.md` before you push.

Which is why the scan is not the only gate. Three more reasons withhold an
entry, and the MANIFEST names whichever applies:

| `withheldReason` | What happened |
|---|---|
| `secret-match` | The scanner matched something in that file. |
| `not-scanned` | gitleaks was **not installed** or the scan failed, so **the whole archive is withheld**. "Nobody looked" is not "clean", and an unexamined tree does not enter version control. |
| `original-gitignored` | **Your `.gitignore` excludes the original.** A gitignore entry is your explicit statement that this *content* must never enter history, so the archive keeps a copy you can restore and never commits that copy under a different name. |
| `gitignored` | Your `.gitignore` excludes the archived path itself. Withheld because `git add` on an ignored path fails and would otherwise abort the entire adoption commit. |

`original-gitignored` is the one that will fire most often, and the file it
usually fires on is `.claude/settings.local.json` — the standard place for a
proxy setting, an internal endpoint or a personal token, and standardly
gitignored. The ordinary ignore rule for it is *anchored*
(`.claude/settings.local.json`), so it matches the original and **cannot** match
`.claude/adoption-archive/…/.claude/settings.local.json`. Asking git about the
copy's path would answer a question you never asked.

**Your git hooks are exempt from this rule, and the reason is worth stating
because an earlier version of this page got it wrong.** It claimed hooks were
safe because "git excludes `.git/` by construction" — they are not:
`git check-ignore` applies your patterns to any path it is given, `.git/`
included, so a `.gitignore` containing `*`, `hooks/` or even the cargo-cult
line `.git/` reports `.git/hooks/pre-commit` as ignored. The exemption is
deliberate instead: a `.gitignore` line about a `.git/` path is not an
instruction git can act on — git never tracks `.git/`, so the rule changes
nothing and expresses no decision about whether that content may be preserved.
Without the exemption a single inert `.git/` line would silently withhold your
hooks, which are the most important thing the archive holds.

#### Still not built by this package

The framework documents, which this section used to list here, ship now — see
[The framework documents](#the-framework-documents--ship-wp12b). The remaining gap is the **replacement** half for framework-script collisions: a
file of yours sitting where a framework *script* would go is still left alone
and still not replaced, so the framework's version of it is not installed. That
class is deliberately outside the archive — swapping out a `scripts/validate.sh`
your own build may call is a decision nobody has made yet — and the run names
it with its own `NOT DONE` block.

### The audit rows and the dispositions record — SHIP (WP7)

Every adoption commits two records of what it decided, beside the Adoption
Record:

- **`.claude/adoption/secrets-dispositions.json`** — the scan this adoption
  answered (the commit it read, how many commits, full or shallow, the status,
  and the sha256 of the committed `scout-report.json`) and the dispositions and
  acknowledgements **this run accepted**. It is written even when the scan found
  nothing: *we scanned, at this commit, and found nothing* is worth keeping.
  Fingerprints, rule ids and line numbers only — never a value. A row in your
  `--dispositions` file that this run did not accept (an acknowledgement for a
  scan that was complete, a disposition with no name or no real date, a
  fingerprint this scan did not find) is not copied in — and neither is
  anything from a file bound to a different scan (its `scan.head` or
  `scan.commitsScanned` is not this one's). The Adoption Record's table of
  decisions is rendered from the same filtered set, so the two agree.
- **A ledger you already have is appended to, never replaced**; every row in it
  survives.
- **`.claude/bypass-audit.json`** gains `adoption_event` rows: one
  `adoption` row naming the tier, the commit adoption started from and what the
  scan said, and one `secrets_disposition` row per **accepted risk** and per
  **acknowledgement**. `rotated` and `false-alarm` accept no risk and write no
  row.

Measured on a clean personal adoption:

```text
$ jq . .claude/adoption/secrets-dispositions.json
{
  "schemaVersion": 1,
  "scan": {
    "head": "da3a7756c1f67adf7607b0cd8cd501f2613812ff",
    "commitsScanned": 1,
    "scope": "full-history",
    "status": "scanned",
    "reportSha256": "cb3a24fb491e9388d85f2cf3a751355039eefda6a8b07ff82d5c309bb64e272c"
  },
  "dispositions": [],
  "acknowledgements": []
}
$ jq -c '.[] | select(.details.event=="adoption") | .details' .claude/bypass-audit.json
{"deployment":"personal","adoptedAtCommit":"da3a7756c1f67adf7607b0cd8cd501f2613812ff","archiveDir":null,"secretsScanStatus":"scanned","findingCount":0,"landedPhase":0,"event":"adoption"}
```

**An accepted risk that cannot be recorded stops the run.** If the ledger will
not take the row — most often because `.claude/bypass-audit.json` is not valid
JSON — adoption prints `[BLOCKED] an accepted risk could not be recorded in
.claude/bypass-audit.json` with the command that checks the ledger, exits 1,
and writes nothing, because the rehearsal hits it before the first real write: an acceptance that leaves no trace is not one it
will act on. The `adoption` row is different: the Adoption Record and the stamp
are the primary records of the act, so a ledger that refuses that row is
reported loudly and left out of the commit, and the adoption stands.

### The framework documents — SHIP (WP12b)

Adoption writes the documents `init.sh` gives a new project at the same moment,
from the same sources:

| Written | From |
|---|---|
| `CLAUDE.md` | rendered by the renderer `init.sh` uses, with your project's name, the tier you chose (an organizational adoption gets the branch-protection section), the track you chose, `undecided` for platform and language, and a placeholder description — the assessment asks for both |
| `FEATURES.md`, `BUGS.md`, `RELEASE_NOTES.md`, `docs/INDEX.md`, `docs/IDENTIFIERS.md`, `docs/archive/README.md` | the framework's templates, copied |
| `docs/reference/*.md` — the eight guides | copied **only where absent**; a guide you already have there is left alone |

Measured on a project that owned a `CLAUDE.md` and a `BUGS.md`, and had
`FEATURES.md` as a symlink:

```text
══ The framework's documents
   Wrote the framework's documents — CLAUDE.md, FEATURES.md, BUGS.md, RELEASE_NOTES.md,
   docs/INDEX.md, docs/IDENTIFIERS.md, docs/archive/README.md and the guides in
   docs/reference/ — except any listed below as left alone, and any guide you already had.
   These replaced documents of yours:
     CLAUDE.md
     BUGS.md
   Your originals are in .claude/adoption-archive/2026-09-24T16-22-37Z-37767, each with a restore line in its
   MANIFEST.md. Nothing in them was merged into the new files — copy across anything you
   want to keep, or leave it for the assessment conversation to fold in.
   These were LEFT ALONE, so the framework's version of each is NOT in place:
     FEATURES.md — a symlink; writing through it could overwrite a file elsewhere
```

**Nothing of yours is merged in.** Adapting your prose into the framework's
documents is judgement, and judgement belongs to the assessment (Act 3), which
is not built. What adoption does is archive every original, name each one it
replaced, and tell you where it is. Until you copy content across, the agent
reads the framework's `CLAUDE.md`, not your notes.

**What it will not write over:**

- **a symlink, or anything inside a symlinked folder** (`docs -> /somewhere/else`)
  — writing through it could change files outside the project; the MANIFEST row
  says `kept`;
- **a read-only file** — left as it is, MANIFEST row `kept`;
- **a hardlink** is replaced by writing beside the path and renaming, so the
  other name keeps your content.

Anything left alone is named in the run, under *LEFT ALONE*, so the framework's
version is missing there by your file system's choice, not silently. Not
written: `PROJECT_BIBLE.md` and `PRODUCT_MANIFESTO.md` (phase outputs — `init.sh`
does not write them either) and the `.gitignore` lines `init.sh` adds.

### The Adoption Record, the audit rows and the provenance header — WP7

**The provenance header ships.** `PROJECT_INTAKE.md` — the one document adoption
reconstructs from what already existed — opens with a fenced comment that says
so, invisible when rendered and exact when checked:

```text
<!-- SOIF-PROVENANCE-BEGIN
reconstructed-at: 2026-09-25
reconstructed-by: scripts/adopt-project.sh
source: existing codebase at 0f7afd202f02 + adoption survey
status: describes work completed BEFORE adoption; not a pre-build specification
SOIF-PROVENANCE-END -->
```

The documents adoption writes that describe what is **coming** — `CLAUDE.md`,
`FEATURES.md` and the rest — carry none. A near-miss header is worse than none,
so the check is exact: the fence lines, four fields in this order, a real date,
a commit, the status sentence word for word, and first in the file. It runs when
the file is written and again in the assessment finisher, because the
assessment conversation edits `PROJECT_INTAKE.md`; a header it broke stops the
finisher before anything is recorded.

**The Adoption Record used to be on this list and is not any more.** The driver
no longer prints a `NOT DONE` block for it: it appends the record to the end of
your `APPROVAL_LOG.md` during the run, and refuses rather than writing one that
its own eight-clause contract rejects. See
[The Adoption Record](#the-adoption-record).

§8.9 names five `adoption_event` rows. Four are emitted — **collision
archive**, **re-add**, **adoption** and **secrets disposition** (see
[The audit rows](#the-audit-rows-and-the-dispositions-record--ship-wp7)). The
fifth, **blocker acceptance**, belonged to the retired certification pass and
will not be emitted. **The emitter's own header in
`scripts/lib/adopt/adopt-archive.sh` is the live list** — it names each row and
its owner, and it is maintained with the code. Prefer it to this paragraph.

**This no longer stops the gate.** Before WP9b, a freshly-adopted project got:

```text
$ bash scripts/check-phase-gate.sh
[FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.
```

Adoption no longer *creates* that state — it writes the log itself, first, so
the gate reaches a verdict. Measured on a project adopted today:

```text
$ bash scripts/check-phase-gate.sh
Phase Gate Consistency Check
Current phase: 0


Adoption Stamp Integrity
[OK] Adoption stamp present and intact (adopted: …)

Phase gates consistent.
```

The refusal above is still correct where it still applies: **delete the log and
it returns**, at rc 1. That matters for the stamp check, which runs *after* the
precondition — so on a project whose `APPROVAL_LOG.md` is genuinely missing, the
adoption-loss detector never gets to speak.

The **Adoption Record** exists now, and carries what this build can honestly
put in it: the scan and its findings by fingerprint, the dispositions and
acknowledgements when you supplied them, the archive path, the test-debt count,
the hooks directory and the rehearsal's measurements. What it cannot yet carry —
the assessment's findings and verdict, the interview answers, the in-production
declaration — it **names in its own text** rather than leaving out, so that a
reader finding those fields absent does not read the absence as a measurement
that came back empty.

The **CI carve-out** ships — see
[The CI carve-out](#the-ci-carve-out--ships-wp7) below.

### The Claude Code session layer — SHIPS (WP9c)

A scaffolded project gets its Claude Code session layer from `init.sh`; an
adopted one now gets the same one, from the same code
(`scripts/lib/claude-settings.sh`, which `init.sh` calls too):

- **`.claude/settings.json`** — the framework's permissions for the project's
  language, and its session hooks: the version, test-gate, freshness, intake and
  cadence checks at session start, the commit gate and the MCP gate before a
  tool runs, tool tracking after it, the Qdrant reminder and the bypass
  detector at session end. **If you already have a `settings.json` it is
  composed, not replaced**: every key, rule and hook of yours stays, the
  framework's rules are added to `allow` and `deny`, and its hooks are added
  where absent. Your original is in the archive, recorded as `composed`. A
  symlinked `settings.json` is left alone and the run says so.
- **One difference from a new project, on purpose:** the bypass detector's
  per-tool hook is not registered on an adopted project while `## BL-277:` is
  open; its end-of-session hook is.
- **The four vendored skills** — `session-handoff`, `sweep-triage`, `zoom-out`,
  `grill-with-docs` — in `.claude/skills/`. A copy of yours at one of those
  names is archived and replaced; any other skill of yours is untouched.
- **The Qdrant MCP declaration**, only when Qdrant is registered for the
  Claude Code session (read where `CLAUDE_CONFIG_DIR` puts it —
  [The memory and documentation servers](#the-memory-and-documentation-servers)):
  `.claude/settings.local.json` with this project's collection — machine-local
  and not committed, as in a new project — and the requirement recorded in
  `.claude/manifest.json`, which is. `init.sh` also writes it for a running
  container with `uvx`, because it registers the server first; adoption offers
  that registration in its own step, so a running container alone no longer
  declares a server the session does not have (`## BL-311:`).

### The CI carve-out — SHIPS (WP7)

**Your pipelines are read, never changed.** Adoption reads every CI file you
have — `.github/workflows/*.yml`, `.gitlab-ci.yml`, `bitbucket-pipelines.yml` —
for four ways a pipeline can let code around the framework's checks:

| Finding | What it looks for |
|---|---|
| auto-merge | `gh pr merge … --auto`, auto-merge actions — changes merge with nobody deciding |
| admin merge | `gh pr merge … --admin` — merges past checks that have not passed |
| force-push or history rewrite | `git push --force`, `filter-repo`, `filter-branch` |
| a failing step is allowed to pass, or a job runs regardless | `continue-on-error: true`, `allow_failure: true`, `if: always()` (which also fires on legitimate fail-closed jobs — read it, then decide) |
| deploys on a branch push | a deploy in a workflow triggered by a branch push, with no tag, release or manual trigger |

It is a search for known spellings, not a parser, and the run says so. It
misses what it has no spelling for (`|| true`, a `--mirror` push, a deploy in a
file that also has a manual trigger), and a file it **cannot read** is reported
as unread and recorded that way — never as clean. It
reports a **line number**, never the line — a workflow can carry a credential.
For each file with a finding it asks once, **before anything is written**:
*keep* it as it is, or *retire* it. Your answer goes into the Adoption Record;
"retire" is your intention, and adoption does not carry it out. A file with no
finding asks nothing. Measured:

```text
══ Your CI — read, not changed

   .github/workflows/release.yml — the framework cannot vouch for what this lets through:
     line 10  a failing step is allowed to pass — a red check can come out green
     line 6  deploys on a branch push — code can reach production without the release phase
Keep .github/workflows/release.yml as it is, or will you retire it?
   1) Keep it — it stays exactly as it is
   2) Retire it — I will remove or change it myself
```

**The framework's CI is installed as its own file**, from the template `init.sh`
uses for the project's language, and **never at the canonical path**. On GitLab
and Bitbucket the canonical file is your whole pipeline, and replacing it would
take your deploy offline:

| Host | Framework CI | Runs? |
|---|---|---|
| GitHub | `.github/workflows/solo-gates.yml` | Yes, on a push to `main` and on pull requests to `main` — a push to any other branch runs nothing. It shows in the Actions tab and in a pull request's checks as **Solo Orchestrator checks**, so it cannot be mistaken for a workflow of yours named `CI`. If your main branch has another name, change `main` in its two `branches:` lines. It may fail on code that predates adoption; that is a finding, not a breakage. |
| GitLab | `.gitlab-ci-solo.yml` | **Not until you add** `include: - local: '.gitlab-ci-solo.yml'` to your `.gitlab-ci.yml`. The run prints the lines — and a warning: GitLab **merges** an included file into yours, and this one sets `image`, `variables`, `cache` and `stages` pipeline-wide and defines jobs named `test` and `lint`. Check those against your file first. |
| Bitbucket | `bitbucket-pipelines.solo.yml` | **No.** Bitbucket runs only `bitbucket-pipelines.yml`. Sharing a configuration file needs Bitbucket Premium and an exported file whose name ends in `pipelines.yml`, which this is not; copy the steps you want into yours. |
| none found | nothing | `init.sh` lays no CI down for host `other` either; supply your own. |

For a Python project, the GitHub file installs a uv project (one with `uv.lock`
and `pyproject.toml`) with `uv sync --frozen`, which never rewrites the lockfile,
and runs its tools through `uv run --frozen`. Any other Python project installs
from `requirements.txt`. With neither, its "Find the dependency file" step fails and
names the missing files (`# BL-318-G3-INSTALLER`).

A file already at the framework's name is yours: left alone, and the run says
so. The Adoption Record's **Your CI** section names the framework's file (or why
none was installed) and your decision for each flagged file.

### The commit-time scanners — SHIP (WP7/3)

**This section used to say the scanners were not installed and that nobody owned
them.** They are installed now, and the sentence that deferred them is what
brought them back.

That block was a MEASUREMENT: installing the hook "refuses every commit, because
it expects artifacts an adoption does not yet produce". True when taken — and
therefore worth re-taking once the Adoption Record landed. Re-measured on a real
adoption, hook installed:

```text
docs: commit, nothing else staged          rc 0   lands
a source file whose tests fail (BL-125)    rc 1   [BLOCKED] project tests FAILED
a staged RSA private key                   rc 1   [BLOCKED] gitleaks detected secrets
```

So from your next commit onward, an adopted project runs the same commit-time
checks a scaffolded one does: secret detection, the static-analysis pass and the
schema-migration checks, on top of the two message gates that were already on.

**Your own pre-commit hook is REPLACED, not left alone.** That is §7.1's rule —
its archive-and-replace population is your AI-layer settings and every
non-`.sample` file in `.git/hooks/` — and the framework's hook is written whole,
so it cannot compose the way the commit-msg gate does. Your copy is in the
archive with a restore line, and the run says so:

```text
   Your own pre-commit hook was REPLACED by the framework's. Your copy is in the
   archive with a restore line — see .claude/adoption-archive/…/MANIFEST.md.
   Nothing of it was merged: the framework's hook is written whole, so the two
   could not compose the way the commit-msg gate does.
```

The MANIFEST row for it reads `disposition: "replaced"`, not `kept` — it said
`kept` for exactly one commit's worth of history, next to a hook that had just
been overwritten.

#### The static-analysis pass needs a ruleset, and adoption now installs it

The hook passes `--config=.semgrep/soif-dom-sinks.yml` unconditionally. Adoption
did not install that file, so on an adopted project **every commit** printed:

```text
[WARN] semgrep could not complete (exit 7) — the tool itself failed.
  SAST NOT ENFORCED for this commit — the scanner did not run.
  [ERROR] unable to find a config; path `.semgrep/soif-dom-sinks.yml` does not exist
```

Loud, honest, and unprotected. Adoption lays the ruleset down and commits it —
**unless you already have a file at that path**, in which case yours stands and
the run says so, because the hook reads that path either way and your rules are
yours.

#### When the scanners are NOT installed — and the run says so

Adoption never overwrites bytes its archive cannot give back. In four cases
that means your hook stays exactly where it is, the scanners are **not**
installed, and the run ends with **exit code 1** — the adoption itself landed,
this step did not, and a script reading the exit code must not take the project
as fully gated:

| Your `.git/hooks/pre-commit` is… | What happens |
|---|---|
| **a symlink** — to one shared hook several repositories use, or dangling | Left alone. Writing through it would overwrite the file at the far end, and the archive cannot hold a copy of a link's target. |
| **read-only** | Left alone, permissions included. |
| **different from the archived copy** — you edited it after a refused adoption commit, before `--finish` | Left alone. Overwriting it would lose your edit, with only the older version to restore. **Do not run the archive's restore line for it** — that line was written before your edit and would put the older version back. The run says so. |
| **without a restorable copy** — the archived file was removed, or the path is not a regular file | Left alone. Replacing it would leave nothing to put back. |

A **hardlinked** hook is replaced safely: the framework's hook is written beside
yours and renamed over the path, so the file it shares an inode with elsewhere
is untouched.

Each refusal prints the reason and a command that works. Move your hook aside,
then run, from the project root:

```bash
bash -c '. scripts/lib/hook-templates.sh && soif_write_precommit_hook .git/hooks/pre-commit'
```

Re-running the adoption, or `--finish`, will **not** do it — both refuse on a
project that is already adopted. Or run the scanners by hand on each commit:
`bash scripts/pre-commit-gate.sh --terminal-mode`.

#### Three things to know before you rely on it

- **A test suite that already fails will block source commits.** The hook runs
  your project's own test command whenever a source file is staged, and refuses
  the commit if it fails. **When you keep the test command the scan offers** under
  *Testing & Bug Tracking* in the interview, **adoption writes it to
  `.claude/test-command`**, one line, exactly as offered. Scout's flag stays in it
  (`--frozen` for uv, `--config.verify-deps-before-run=false` for pnpm), so the
  check never rewrites your lockfile in the middle of a commit. **If you change
  that answer, nothing is written**: the question is about testing in general,
  and a sentence in that file would run on every commit. A `.claude/test-command`
  you already have is left exactly as it is, and the run says what it will run.
  Nothing is written either when the scan found no test command (the interview
  shows "(none detected)"), or when the script it found is npm's placeholder
  (`echo "Error: no test specified" && exit 1`), which would block every source
  commit. The run's "The test command your commits run" section says which of
  these happened. When you changed the answer, it also gives the one line that
  writes a command yourself. With no file, the hook finds a
  command itself: pytest runs through uv, poetry, pdm or pipenv when that tool's
  file is there, once importing pytest through that tool works — if it cannot,
  the commit lands with a loud PROJECT TESTS NOT ENFORCED. A suite that is there
  but broken still blocks. A project adopted before
  2026-10-03 has no file, and for a Python project its older hook runs a bare
  `pytest`. Write the file, or refresh the hook from the project's folder with
  `bash ~/solo-orchestrator/scripts/upgrade-project.sh --sync-framework`. It asks
  before it refreshes the hook (add `--install-hooks` where nothing can answer),
  and it also refreshes the framework's scripts and documents, so run it with
  `--dry-run` first. Adoption does not run your tests, so it cannot
  warn you in advance. If your suite is red today, fix it — or point the hook at
  a command that passes by editing `.claude/test-command` — before your first
  source commit.
- **Your test command has no time limit.** A suite that hangs, or waits for
  input in watch mode, will hang the commit. The same `.claude/test-command`
  file is how you give the hook a command that finishes.
- **Tools that install into `.git/hooks/pre-commit` are replaced, not chained.**
  The Python `pre-commit` framework and lefthook both work that way, so their
  lint and format checks stop running on commit. Your hook is in the archive
  and `--re-add` puts it back, but then the framework's scanners are not
  installed. (husky 5 and later use `core.hooksPath`, which adoption refuses
  before writing anything; husky 4 and earlier install into `.git/hooks` and are
  replaced like the others.)

**The test-debt ratchet is still run by hand.** The commit-time hook now exists,
but nothing wires the ratchet into it, for a structural reason:
`scripts/pre-commit-gate.sh` is **core** and the ratchet is **module** code, so a
call from the gate to the ratchet is exactly the `core → module` edge
[the module contract](module-contract.md)'s M3 forbids and
`scripts/lint-module-dependencies.sh` reds on. Until that is designed, run
`adopt-test-debt.sh --check` by hand or from CI.

### And one more, from this page rather than the driver

**This page is not shipped into adopted or generated projects.** `init.sh` copies
the framework's guides into `docs/reference/`; `docs/adoption.md` and `docs/scout.md` are
not among them. Read them here, in the framework clone you run the driver from.

### Summary — what you can and cannot get today

| You want | Today |
|---|---|
| A read-only survey of an existing codebase | ✅ [Scout](scout.md), complete |
| A guided landing at phase 0, with the tier question and the reverse intake's confirmations | ✅ Ships and works |
| Project state written fail-safe, staged explicitly, committed as its own commit | ✅ Ships and works |
| An adoption stamp, and loud detection when it is lost | ✅ Ships and works |
| Test-first ordering enforced from adoption day forward | ✅ Ships and works |
| Gates that were skipped actually run and recorded | ✅ By construction — nothing is skipped; the project starts below every gate |
| Being asked what the project is for, and told whether the stack fits | ✅ [The assessment](#the-assessment--act-3-and-act-4--ships-wp12a) — a Claude Code conversation, then the finisher |
| A fitness verdict, a plan, and the reasoning behind both | ✅ Written by the assessment conversation; checked (two halves, a reason) and recorded by the finisher |
| The required secrets scanner resolved before anything reads the scan — installed where the host has a recipe, named for you where it does not — and the scan re-run after an install | ✅ Tool resolution — ships (WP10a). When the scanner still cannot be resolved, the tier-scoped stop below decides |
| Adoption that can *fail* on a serious finding | ✅ The secrets stop — ships (WP10b): an organizational adoption stops on a finding, an unscanned tree or a partial scan; a personal one continues only on a recorded acknowledgement. [If it stops](#5-if-it-stops) |
| A recorded, non-growing set of untested files | ✅ [Test-debt ledger + ratchet](#the-test-debt-ledger-and-its-ratchet) — ships and works; the commit-time hook that would invoke the ratchet automatically now exists, and wiring the ratchet INTO it is still unbuilt |
| Your colliding hooks/settings archived with a restore path | ✅ Collision archive — ships |
| Plain disclosure of what was archived, path by path | ✅ Ships |
| Putting one of your own files back, warned and recorded | ✅ `--re-add`, ships |
| Adoption refusing to commit a *recognised* secret out of your hooks | ✅ Ships — the archive is scanned before staging and a match is withheld. **A mitigation, not a guarantee** — see below |
| Adoption never committing a file your `.gitignore` excludes | ✅ Ships — the **original's** ignore status decides, not the archive copy's |
| Framework CI installed beside yours, with a recorded keep-or-retire | ✅ [The CI carve-out](#the-ci-carve-out--ships-wp7) — ships; on GitLab it runs once you add one `include`, on Bitbucket you copy its steps |
| An audit trail of the adoption and of every risk accepted during it | ✅ [The audit rows and the dispositions record](#the-audit-rows-and-the-dispositions-record--ship-wp7) — ships |
| A readable record of how this project entered the framework | ✅ [The Adoption Record](#the-adoption-record) — ships, at the end of `APPROVAL_LOG.md`, with its eight-clause contract checked before it is written |
| Secret scanning, SAST and migration checks on every commit | ✅ [The commit-time scanners](#the-commit-time-scanners--ship-wp73) — ships; measured admitting a compliant commit and blocking a non-compliant one by exit code |
| The framework's version of a colliding `scripts/*.sh` installed | ❌ Replacement half — **not built**, and unassigned |
| A `CLAUDE.md` in the adopted project | ✅ [The framework documents](#the-framework-documents--ship-wp12b) — ships; yours is archived and named, not merged in |
| The manifest's tier keys, so enforcement cannot be downgraded | ✅ Ships — `## BL-221:` closed; the tier question is their only source |

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Adoption completed |
| 1 | Adoption did not complete. The message distinguishes the two cases (`# BL-225-REFUSE-HONEST`): **`[REFUSED]`** when the run never began — nothing committed, nothing written; **`[BLOCKED]`** when it began and stopped — nothing committed, but *N* file(s) already on disk, with the count derived from the write ledger rather than assumed. It does **not** claim those files are visible to plain `git status`: on the staging-block path they provably are not, so it names `git status --ignored --untracked-files=all` instead. **Nothing is ever left half-staged** — `# BL-225-STAGE-PREFLIGHT` asks `git add --dry-run` before it stages, and stops whole |
| 2 | Bad usage, or a target the driver cannot use |

---

## See also

- [scout.md](scout.md) — the read-only survey. Run it first.
- [delta-track.md](delta-track.md) — the post-1.0 maintenance loop an adopted project reaches the ordinary way, by shipping through the gates.
- [designs/2026-08-23-brownfield-adoption-v2.md](designs/2026-08-23-brownfield-adoption-v2.md) — the **normative** architecture design: the four acts, the ten settled decisions, and the build plan.
- [designs/2026-08-02-brownfield-adoption-v1.md](designs/2026-08-02-brownfield-adoption-v1.md) — superseded, kept because the shipped code still cites its section numbers in places v2's packages have not reached.
- [module-contract.md](module-contract.md) — the severable-module rules the driver is held to.

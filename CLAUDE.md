# CLAUDE.md — agent orientation for the solo-orchestrator repo

Read this first. It is the map for working effectively in THIS repository.
Counts are date-stamped (they drift); prefer the grep/command recipes — run them
to get current truth. Verified 2026-07-23.

## WHAT THIS REPO IS

This is the **framework repo that GENERATES downstream projects** — it is not
itself a scaffolded project. `init.sh` scaffolds a new project elsewhere; the
files a downstream agent reads at kickoff live in the GENERATED project, not
here.

- The README "Quick Start" **no longer carries a kickoff prompt of its own**
  (BL-202 residual 2). It points at `bash scripts/resume.sh` — the single
  state-aware first-message generator, whose three branches are the intake
  prompt, `PROJECT_INTAKE.md` § 13 verbatim, and the classic resume prompt.
  That script and everything its output names (`CLAUDE.md`,
  `PROJECT_INTAKE.md`, `docs/reference/…`, `.claude/phase-state.json`) exist
  **in generated projects only**; the README says so in as many words, because
  it is read by people who have not run init yet.
  **Do not re-add a verbatim paste block here** — the hand-maintained copy is
  what drifted, and `tests/test-bl202-readme-kickoff-consolidation.sh` now
  fails if one comes back (literal signatures *and* a structural bare-fence
  net, five mutation proofs).
- `init.sh` ships the guide downstream to `docs/reference/`: see the
  `cp "$SCRIPT_DIR/docs/builders-guide.md" docs/reference/` line (grep
  `builders-guide` in init.sh). In THIS repo the guide is **`docs/builders-guide.md`**
  (top level), and there is **no** `PROJECT_INTAKE.md` and **no**
  `.claude/phase-state.json`.
- **`docs/INDEX.md` is the documentation map** — a one-screen index of `docs/**`
  and `Reports/**`. Start there to find a doc.

## ENVIRONMENT TRAPS

- **No `timeout` / `gtimeout`** on this macOS host. Wrapping a command in them
  yields a spurious `rc=127` (command-not-found), not a real timeout. Do not use
  them.
- **The repo path contains a space** (`Claude Projects/…`). Quote every path in
  every command, always.
- **bash is 3.2** (`/bin/bash`, GNU bash 3.2.57). In product code: no `${var,,}`
  lowercasing, no associative arrays (`declare -A`), no `nullglob`. Use temp
  files / indexed arrays instead.
- **`sed` with a `|` delimiter and a shell-code replacement bites, and it bites
  SILENTLY.** Shell replacements are `|`-dense (`||`), so `s|old|new|` where
  `new` contains `||` either errors (`bad flag in substitute command`) or —
  worse — terminates the expression early and **leaves the file unchanged while
  sed reports success**. It has bitten three times (twice inside a mutation
  harness, once ad-hoc), and 25 files carry `s|`-delimited `sed`. Two rules:
  pick a delimiter absent from the replacement, and **assert the edit actually
  applied** (a changed-line count), because "sed ran" is not "sed edited".
  A related one-liner: `&` in a `sed` replacement means *the whole match* —
  an unescaped `&&` splices the original line back in, and that mutant passes
  `bash -n`. See `## BL-224:` for the sibling case where a lint's own regex
  over-matched for the same reason.
- **The same `&` trap lives in bash's own `${var/pat/rep}`, and it is
  VERSION-SPLIT between this host and CI.** Since bash **5.2** an unescaped
  `&` in the *replacement* of a pattern substitution means THE WHOLE MATCH,
  exactly as in `sed`; **bash 3.2 has no such rule**. 5.2 is the boundary, not
  5.1 — measured, `u='one TWO three'; "${u//TWO/&}"` gives `one & three` on
  3.2.57, 5.0.18 and 5.1.16 and `one TWO three` on 5.2.37, and the `shopt`
  that governs it (`patsub_replacement`, on by default) does not exist before
  5.2. This Mac runs 3.2 and
  the runners run 5.2, so a replacement carrying `&&` — which every shell
  guard does — produces the intended text locally and splices the match back
  in on CI. It is silent in the worst way: the line still changes, the
  changed-line count is still right, and `bash -n` is still clean, so a
  mutation harness reports a healthy mutant that no longer mutates. That is
  a red `rest` shard on PR #380, found only because the mutant stopped
  killing its case. Two rules, the same two as for `sed`: **do not use
  `${var/pat/rep}` when the replacement can contain `&`** — split on the
  pattern instead (`lhs="${s%%"$pat"*}"; rhs="${s#*"$pat"}"`), which has no
  `&` rule in any version — and **assert the replacement LANDED**, by its
  own literal text, not by a line count. `soif_sed_repl_esc` in
  `helpers-core.sh` is unaffected, but **do not try to read that off the
  spelling** — two drafts of this bullet reasoned about it and both were
  wrong. Measure it. Double-quoted, `t='R&D tools'`, `u='one TWO three'`:
  ```
  replacement, as written   what it is        bash 3.2      bash 5.2
  ${t//&/\\&}   <- REAL      two backslashes   R\&D tools    R\&D tools
  ${t//&/\&}                  one backslash     R\&D tools    R&D tools
  ${u//TWO/\\&}              two backslashes   one \& three  one \TWO three
  ${u//TWO/&}                 bare &            one & three   one TWO three
  ```
  On 5.2, `\\` collapses at quote removal to a LITERAL backslash that does not
  escape, so `\\&` is backslash-plus-*whole match*; a single `\&` is an escaped
  `&` and yields a literal `&` with the backslash consumed; a bare `&` is the
  whole match. On 3.2 all three are literal. So the real source line —
  `t="${t//&/\\&}"`, two backslashes — is byte-identical across versions ONLY
  because its pattern is the single character `&`, which makes "the whole
  match" happen to be `&`. Change that pattern and the versions diverge in
  silence. `tests/test-bl255-sed-replacement-escape.sh` pins those bytes in
  the unit lane, and that is what would catch it — **but only there.** Mutate
  the helper's `\\&` to `\&` and that suite stays GREEN on this Mac and goes
  red only on the runner, which is this same trap one level up: a local run
  of the suite that guards the trap does not see the trap.
  Reproduce the runner's bash on this host:
  ```
  docker run --rm -v "$PWD:/repo:ro" ubuntu:24.04 bash -c 'apt-get update -qq \
    && apt-get install -y -qq jq git && useradd -m t && cp -r /repo /home/t/r \
    && chown -R t /home/t/r && su t -c "cd /home/t/r && bash tests/<file>.sh"'
  ```
  Run as a NON-root user or every `chmod 555` fixture silently stays writable.
- **A `local` that DECLARES without ASSIGNING is a second version split, and it
  is NOT the same boundary as the one above — it is bash **4.0**, not 5.2.**
  `local t` followed by a read of `$t` under `set -u` is an empty string on
  bash 3.2 and an `unbound variable` **that exits the shell** on 4.0 and every
  version after. Measured, same probe, `bash:<v>` images plus this Mac —
  `f() { local t; [ -n "$t" ] && echo hit; echo AFTER; }`:
  ```
  bash 3.2.57 (this Mac AND the container)   empty, prints AFTER, rc 0
  bash 4.0.44 / 4.1.17 / 4.2.53 / 4.4.23     t: unbound variable, rc 1
  bash 5.0.18 / 5.1.16 / 5.2.37 / 5.3.20     t: unbound variable, rc 1
  ```
  **Do not merge this into the `${var/pat/rep}` bullet.** That one flips at 5.2
  and 5.1 is on the safe side; this one flips at 4.0 and every bash a runner has
  shipped this decade is on the failing side. The 2026-09-18 commit that fixed
  the first instance (`81316ea`) named 3.2-vs-5.2 because those were the two
  hosts in front of it — true, and it reads as a 5.x rule, which it is not.
  Measure the boundary before you quote one.

  **It is silent in the specific way that reads as a deliberate refusal.** The
  shell EXITS at the read: side effects from before it persist, every line after
  it — including the message the function existed to print — never happens, and
  the script leaves **rc 1**, which is indistinguishable from a `return 1` the
  code meant. (**rc 127 under `bash -c`** — measured on every version from 4.0
  up, which is why the recipe below feeds the script on stdin; reproduce with
  `bash -c` and you get a number this bullet does not predict.) That is
  PR #432's `slow-misc` red: `adopt-state.sh`'s symlink arm refused correctly,
  wrote nothing, and printed no `[REFUSED]` line at all.
  `bash -n` is clean and every macOS suite is green.

  Safe spellings, all measured identical on 3.2 and 5.2: `local t=""`;
  `local t; t=$(…)` (assigning before the first read is enough); and `${t:-}`
  at the read site. The trap is not the `local` keyword — **`declare t` inside
  a function, `declare g` at top level, and `local -i n` all behave the same**
  (the integer attribute does NOT initialise to 0).

  **Grepping for it gives you a population, not a defect, and grepping for
  `set -u` UNDER-READS.** The declaration-without-assignment shape has 925 hits
  over 155 files (2026-09-18):
  ```
  grep -rn --include='*.sh' -E '^[[:space:]]*local([[:space:]]+-[a-zA-Z]+)*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)+[[:space:]]*$' scripts/ init.sh tests/ templates/
  ```
  Almost all are assigned on the next line and harmless; the defect is the
  subset READ before assignment, which no grep finds. And filtering that
  population by files that themselves carry `set -u` leaves 95 — a **floor, not
  the answer**, because the option comes from whoever RUNS the file. Every file
  in `scripts/lib/adopt/` is sourced by `scripts/adopt-project.sh`, which is
  `set -uo pipefail`; seven of the eight carry no `set -u` of their own
  (`adopt-test-debt.sh` is the exception), and together they hold 31 of these
  declarations. That is exactly where the bug was. Do not sweep the 925 — the
  rule is **assign at the declaration**, applied to code you are already
  touching.

  Reproduce any version of it on this host without the repo:
  ```
  docker run --rm -i bash:5.2 bash -s < probe.sh    # also 3.2, 4.0 … 5.3
  ```
  Mounting the script with `-v` into `bash:*` silently produces a DIRECTORY at
  the target path on this Docker Desktop (`/probe.sh: Is a directory`) — feed it
  on **stdin**.
- **THE `ubuntu:24.04` RECIPE ABOVE — the one that runs a SUITE, not the
  `bash:<v>` probe next to it — IS A bash/git VERSION EMULATOR AND NOT A CI
  EMULATOR.** It
  diverges from both this Mac and the runner far beyond anything one missing
  tool explains, so **a red suite in it is not evidence of a defect until you
  diff it against the same suite at the parent commit IN THE SAME IMAGE.** That
  diff is the whole technique; everything below is scale and traps.

  **DO NOT TRUST A CAUSE HERE — five drafts of this bullet asserted one and all
  five were refuted**: twice the missing `~/.claude-dev-framework`, once a
  node/npm underrun, once "the instability is the image, not the suite", once
  "the suite is nondeterministic on Linux". State what you measured; leave the
  rest unexplained. Naming a cause here has a perfect record of being wrong —
  and **if you refute one, increment this counter in the same commit**: the
  draft that refuted the fifth updated `## BL-260:` to five and left this line
  saying four.

  Scale, measured 2026-09-14 with gitleaks installed and `~/.claude-dev-framework`,
  `python3` and `node` all still ABSENT: **roughly 20 of the 191 suites in the
  `tests.yml` unit list fail in that image** — three runs gave 22, 20 and 19,
  and the 22 was over a list with two wrong members (above), so treat even the
  spread as soft. Every one of them passes on this Mac. So **never generalise from the ten
  `tests/test-brownfield-*.sh` files** — 19 of 20 are outside them, and 10 of
  the 11 `test-upgrade-*` suites are in. **Re-derive; never quote this list or
  its count.** Derive it ANCHORED and SLICED, and do not improvise the spelling
  — two drafts of this recipe were wrong in two different ways, and both
  produced a plausible-looking list:
  ```
  S=$(awk '/^[[:space:]]*tests=\(/{print NR; exit}' .github/workflows/tests.yml)
  E=$(awk -v s="$S" 'NR>s && /^[[:space:]]*\)[[:space:]]*$/{print NR; exit}' .github/workflows/tests.yml)
  sed -n "$((S+1)),$((E-1))p" .github/workflows/tests.yml | sed 's/#.*//' \
    | sed 's/[[:space:]]//g' | grep '^tests/' > list.txt      # 191 entries, verified
  while IFS= read -r t; do bash "$t" </dev/null >/dev/null 2>&1 || echo "RED $t"; done < list.txt
  ```
  `tr -d '[:space:]'` instead of the `sed` **deletes the newlines too** and
  yields ONE line — caught only because `wc -l` said 1. And scoping with the
  unanchored `/tests=\(/` the repo's own lint uses, then `grep -o
  'tests/test-[a-z0-9._-]*\.sh'`, gets the membership wrong in BOTH
  directions: it pulls in `tests/test-bl180-interactive-scaffold-pty.sh` from a
  COMMENT at line ~1098, half a file below the array that ends at ~541 (the
  BL-181 residual, one section down), and it drops the real member
  `tests/host-drivers/error-translate.test.sh` because that path does not match
  `tests/test-*`. Both lists were 191 long. Length is not membership.
  The `sed 's/#.*//'` is the third failure mode, latent rather than measured:
  whitespace-stripping alone turns a TRAILING comment into `tests/test-foo.sh#pinned`,
  which still matches `^tests/` and reaches `bash` as a spurious RED. The array
  carries no comments today — strip them anyway.

  **REDIRECT STDIN OR THE LOOP LIES.** `bash "$t"` inherits the `while read`
  loop's fd 0, so the first stdin-reading suite EATS THE REST OF THE LIST. Not
  theoretical: without `</dev/null` the loop above silently reports
  `TOTAL=2` over a 191-entry list, on this Mac and in the container, and the
  drainer is `tests/test-bl032-gitlab-free-approvals-attestation.sh`'s fake
  `glab` stub (`[ ! -t 0 ] && cat >/dev/null`). `TOTAL=2` is absurd enough to
  catch; a plausible wrong number would not have been.

  **THE MEMBERSHIP OF THAT SET IS UNSTABLE — DO NOT READ A ONE-RUN LIST AS A
  PROPERTY OF ANYTHING.** Six back-to-back runs of
  `tests/test-specs-plans-host-aware-quartet.sh` inside ONE unchanged container
  gave four distinct outcomes — 8/0, 7/1, and two DIFFERENT 6/2s — with the
  failing element changing run to run (`T8` naming `Task7.3` then `Task7.4`;
  `T11` counting `found 1`, then `found 2`, then failing a different assertion
  entirely). Repeated with a fresh `cp -r` of the tree per run, same spread.
  **Every measurement of this is `linux/arm64`, which is NOT the lane's
  architecture**: on `--platform linux/amd64`, same image, same recipe, the
  suite is 12/12 clean, and on this Mac 6/6. `ubuntu-latest` is x86_64, so
  there is no evidence of a PR-lane risk here. Two drafts of this paragraph
  named a cause — first "the image, not the suite", then "the suite is
  nondeterministic on Linux" — and both were refuted. What is measured is that
  the ARM container returns different answers for the same deterministic
  pipeline over byte-identical input (`T8` and `T11` are pure `grep`/`awk` over
  static files; no `sort`, `find`, glob, backgrounding, `RANDOM` or clock, and
  the tree checksums identical before and after every run). Recorded as
  `## BL-260:` with the cause explicitly unisolated.

  gitleaks is the single biggest lever on the brownfield ten — bare image six
  fail (`wp4-driver` 9/15, `wp5b-test-debt` 55/2, `wp6-collision-archive`
  12/27, `wp9-act-boundaries` 0/1, `wp9b-preflight-approval` 48/38,
  `wp10a-tool-resolution` 52/2); install it and five go fully green. The
  residue is `wp9b`'s `AM2` at 102/1, where the gate blocks on `[WARN] Phase
  0→1: … gate date not recorded in phase-state.json`. **Cause not isolated —
  and NOT node/npm**, measured with `node`, `npm` and `python3` all installed.
  Add `curl ca-certificates` to the apt line; `ubuntu:24.04` has neither, and
  the fetch below exits 127 without them. Runs as root, BEFORE `su t`. Note
  `-f`: without it curl writes a 9-byte `Not Found` body and the failure
  surfaces as `gzip: stdin: not in gzip format` two commands later.
  ```
  A=x64; [ "$(uname -m)" = aarch64 ] && A=arm64        # the x64 asset needs emulation on Apple Silicon
  curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_${A}.tar.gz" \
    -o /tmp/g.tgz && tar xzf /tmp/g.tgz -C /tmp gitleaks && install -m0755 /tmp/gitleaks /usr/local/bin/
  ```
  **UNVERIFIED BY CHECKSUM, DELIBERATELY AND ONLY HERE.** `tests.yml`'s
  `Install gitleaks (pinned + checksum-verified)` step pins
  `GITLEAKS_SHA256` and calls `scripts/ci-verify-sha256.sh` — but that pin is
  for the **x64** asset and there is no arm64 pin in the repo, so verifying
  would break the arch selection above. This recipe is a local diagnostic that
  never gates anything; **do not copy it into anything that does** without
  pinning both digests.
- **`grep` INSIDE A CLAUDE CODE AGENT SHELL IS A SNAPSHOT FUNCTION ROUTING TO AN
  EMBEDDED ugrep, AND ugrep IS LOCALE-INSENSITIVE WHERE EVERY RUNNER'S GREP IS
  NOT.** There is no ugrep binary on this host at all; the function is the whole
  mechanism, and `PATH=` does not escape it:
  ```
  $ type -a grep                      # inside an agent shell
  grep is a shell function from /Users/karl/.claude/shell-snapshots/snapshot-zsh-….sh
  grep is /usr/bin/grep
  $ PATH=/usr/bin:/bin grep --version | head -1
  ugrep 7.8.4 …                       # STILL the function — a PATH prefix does not help
  $ /bin/zsh -l -c 'grep --version | head -1'      # Karl's own login shell
  grep (BSD grep, GNU compatible) 2.6.0-FreeBSD
  ```
  ugrep treats `.` as a UTF-8 CHARACTER **even under `LC_ALL=C`**; BSD grep and
  GNU grep 3.11 treat it as a BYTE. So a pattern that must match a multibyte
  character with `.` — the `→` in `Phase 0 → Phase 1` is three bytes — passes
  here in every locale and fails on a runner in a byte locale.
  **USE `command grep`, `/usr/bin/grep`, OR `bash -c` TO SEE THE REAL ANSWER** —
  a `PATH=` prefix gives you the MASKING one, and the first draft of this bullet
  prescribed exactly that, so an agent following it would have read `1` and
  concluded the pattern was safe:
  ```
  $ printf '## Phase Gate: Phase 0 \xe2\x86\x92 Phase 1\n' > arrow.txt
  $ PATH=/usr/bin:/bin LC_ALL=C grep -cE 'Phase [0-9] . Phase [0-9]' arrow.txt   # 1  <- WRONG, the function
  $ LC_ALL=C command grep       -cE 'Phase [0-9] . Phase [0-9]' arrow.txt        # 0  <- the truth
  $ LC_ALL=C /usr/bin/grep      -cE 'Phase [0-9] . Phase [0-9]' arrow.txt        # 0
  $ LC_ALL=C /bin/bash -c "grep -cE 'Phase [0-9] . Phase [0-9]' arrow.txt"       # 0
  $ LC_ALL=C /usr/bin/grep      -cE 'Phase [0-9].*Phase [0-9]' arrow.txt         # 1  <- safe pattern
  ```
  A suite run with `bash tests/…` sees the real grep, which is why the pin for
  this (`A11` in `tests/test-brownfield-wp7-adoption-record.sh`) works at all.
  `docker run --rm -i ubuntu:24.04` agrees (GNU grep 3.11), **and a bare
  container's default locale is the failing one** — `LC_ALL=C.UTF-8` matches,
  `C`, `POSIX` and an ungenerated `en_US.UTF-8` do not. This is the third
  local-green/runner-red split on this host, alongside `${var/pat/rep}` (5.2)
  and `local`-without-assignment (4.0), and it is the nastiest of the three
  because a pattern that "works locally in every locale" gives no hint.
  **Two rules: never rely on `.` to match a multibyte character — use `.*`,
  which has no locale dependency in any implementation — and reproduce a
  locale-sensitive grep with `PATH=/usr/bin:/bin LC_ALL=C` before believing a
  local green.** It cost `# BL-242-RECORD-WINDOW` its enforcement: the arm that
  finds the last gate header matched nothing under `LC_ALL=C`, and the function
  returned "clean" because it had nothing to measure against — a check that
  could not run reporting that it passed, which is `## BL-147:`'s own shape.
- **This Mac's git is configured and an ubuntu-latest runner's is not — and the
  difference is silent.** Xcode ships
  `/Applications/Xcode.app/Contents/Developer/usr/share/git-core/gitconfig`
  carrying **`init.defaultbranch=main`**, so `git init --bare` here produces
  `HEAD -> refs/heads/main` for free. On CI there is no such setting and you get
  `refs/heads/master`. A fixture that inits a bare, pushes `main`, then clones
  it back out therefore **works locally and is broken on CI**: cloning a repo
  whose HEAD is a dangling symref prints a warning, **exits 0**, and produces a
  directory with nothing but `.git` in it — so `|| return 1` cannot see it and
  the next line fails on a path that was never created. That is BL-234's PR #351
  in one paragraph. **Name the branch on every bare you create**
  (`# BL-234-FIXTURE-BARE-HEAD`), and never treat a clone's exit code as proof
  it checked anything out (`# BL-234-FIXTURE-CLONE-RECEIPT`). Reproduce the
  runner's git on this host — this turns a CI-only failure into a local one:
  ```
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null bash tests/<file>.sh
  ```
  It emulates **git configuration** divergence only — not the runner's git
  *version*, and not its filesystem (this Mac is case-insensitive, ext4 is not).
  Run it before blaming CI for anything a fixture does with git *config*.
  **Derive the affected set, never transcribe it** — a hand-copied list of this
  is what the reviewer refuted on PR #351 (said six, named seven, derived
  eight, and the omitted file was the one the same PR had just edited):
  ```
  grep -rln -- "init .*--bare\|init --bare" tests/
  ```
  Every hit that later **clones back out of its bare** must name the branch.
  None but the BL-234 suite does today, so none of the rest is broken *by this
  defect* — which is not the same as "not broken": the `e2e-init*` trio is
  already red on main for unrelated reasons, and four of the hits
  (`test-bl084-tier-aware-remote-policy.sh` plus that trio) are **full-lane
  only**, so a break there would not gate a PR at all.
  **Do not pin this on the host's default branch.** `git-init(1)` says the
  built-in fallback *"will change to `main` when Git 3.0 is released"* — a test
  that relies on a runner producing `master` stops discriminating everywhere,
  silently, the day runners ship it. Force the condition instead:
  `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=master`
  (that is what case `H3` in the BL-234 suite does, and it is why that suite's
  mutant now dies on this Mac rather than only on CI).
- **Two repos required.** Tests and `init.sh` need the Claude Dev Framework
  cloned at `~/.claude-dev-framework` (the path is hard-required). Per
  CONTRIBUTING.md:
  ```
  git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework
  ```
- **Install the contributor hooks yourself.** Contributors working on the
  framework install them with one command (init.sh does it for generated
  projects, not here). Per CONTRIBUTING.md:
  ```
  bash scripts/install-contributor-hooks.sh
  ```
  It lays `.git/hooks/{pre-commit,commit-msg,pre-push}` from the same emitters
  init.sh uses and — since `## BL-261:` — `.semgrep/soif-dom-sinks.yml` as a
  gitignored symlink to the tracked template, so the pre-commit hook's SAST arm
  RUNS here instead of printing `SAST NOT ENFORCED` on every commit. Its summary
  says which arms are LIVE in your checkout. **Do NOT `cp
  scripts/pre-commit-gate.sh .git/hooks/pre-commit`** — that script is a
  PreToolUse hook that reads JSON on stdin, and as a git hook it allows
  everything silently (`## BL-239:`; this bullet said to do exactly that until
  2026-09-16).

## CANONICAL COMMANDS

- **Run one suite:** `bash tests/<file>.sh`. Each suite prints a final tally
  line — most say `Results: N passed, M failed`, a few `== Total: … | Passed: …
  | Failed: … ==`. The reliable pass/fail signal is the process **exit code**.
- **Run every repo lint locally:** `bash scripts/run-lints.sh` (one PASS/FAIL
  line per lint, summary, non-zero exit iff any failed). This is the dev-tool
  wrapper — see LINT GOTCHAS.
- **CI fast lane (unit):** the explicit file list in the **`unit-shard`** job of
  `.github/workflows/tests.yml` (BL-190 renamed the job; it was `unit`). A test
  belongs there iff it does not invoke `init.sh` and is not an aggregator. That
  list plus `tests/full-project-test-suite.sh` are both lint-enforced (see
  HOUSE RULES).
  - **Adding a test is still a ONE-LINE edit** — append it to the canonical
    array. The lane is sharded (matrix `shard: [lint-sweep, lint-scan, sast,
    slow-misc, adopt, rest]`), but only the measured long poles are pinned to a
    shard by the `pin_*` arrays; `rest` is the COMPLEMENT, so a new entry
    lands there automatically.
  - **Never write the literal array-opening token (`tests`+`=`+`(`) anywhere
    else in that file below the array.** `_build_unit_list_set` scopes with an
    UNANCHORED `awk '/tests=\(/'` and does not strip comments, so a second
    occurrence re-opens the scope and folds every `tests/test-*.sh` path
    after it into the lint's membership set — a test merely NAMED in a
    comment would then satisfy the lint while never running. The pin arrays
    are named `pin_*` for exactly this reason.
  - The job name **`unit` is a required status check** on `main` (confirmed
    via `gh api repos/kraulerson/solo-orchestrator/branches/main/protection`).
    It survives as a zero-work aggregator job that is red unless every
    `unit-shard` leg is green. Renaming or deleting it leaves every PR waiting
    forever on a check that never reports.
- **FULL suite is ~3h and `workflow_dispatch`-only** (`.github/workflows/tests.yml`
  `full` job: `if: github.event_name == 'workflow_dispatch'`, `timeout-minutes: 180`).
  Never run it casually. Locally, `bash tests/full-project-test-suite.sh` and
  `bash tests/host-drivers/run-all.sh` validate a checkout.

## LINT GOTCHAS

- `scripts/run-lints.sh` runs **every `scripts/lint-*.sh` EXCEPT
  `lint-uat-scenarios.sh`** (**16 of the 17** lint scripts as of 2026-09-09 — it
  discovers them by glob, so a new lint needs no wiring; the count drifts, so
  measure it rather than quoting this line: `ls scripts/lint-*.sh | wc -l`, and
  `bash scripts/run-lints.sh` prints its own total on the last line).
- `scripts/lint-uat-scenarios.sh` is a **parametrized tool, not a repo lint**:
  bare-invoked it exits **2** with a `Usage:` message because it needs a
  `<populated-html-file>` argument. It is **not** one of the CI lint jobs
  (`.github/workflows/lint.yml`, **14** jobs as of 2026-09-09 —
  `grep -cE '^  [a-z0-9-]+-lint:' .github/workflows/lint.yml`), so run-lints
  deliberately skips it.
- Two lints are **slow full-tree scans**: `lint-counter-antipattern.sh` (~90s)
  and `lint-raw-read-prompt.sh` (~40s). A full `run-lints.sh` is a couple of
  minutes — that is expected, not a hang.

## ISSUE TRACKING — two files, two grammars

- **`solo-orchestrator-backlog.md`** — `BL-NNN` entries. Real status vocabulary:
  **Open**, **Open — DEFERRED** (also "Open — demoted to OPPORTUNISTIC"),
  **Parked**, **Closed**, **Resolved** (legacy "done"), **Won't Fix**.
  What's-open recipe:
  ```
  grep -n '\*\*Status:\*\* Open' solo-orchestrator-backlog.md
  ```
  (returns the whole open family incl. the DEFERRED variants).
- **`solo-orchestrator-bugs.md`** — `BUG-NNN` entries; statuses are `Fixed` /
  `Superseded` (no literal `Open`), so "open" = **not Fixed/Superseded, by
  negation**.
- **Closed / Resolved entries MUST cite a PR # or a backticked commit SHA**
  (`scripts/lint-backlog-references.sh` enforces this).
- **Closed entries are kept deliberately** (audit trail) — never delete them.
  Two scan traps: some entries preserve an `Original entry (pre-close, kept for
  audit trail):` block with its OWN `**Status:**` line (a since-Closed entry's
  preserved `Open`, e.g. BL-055, surfaces in the what's-open grep — eyeball for
  the marker), and a few entries use `## code-*-N:` headers instead of
  `## BL-NNN:`. Verify against the entry's current top-of-block status (and git
  history) before treating any status line as a stray.

## MESSAGING STANDARD

Every summary you give a human carries the full technical account **and** a
plain-English half — `docs/messaging-standard.md`, which `init.sh` also ships to
generated projects as `docs/reference/messaging-standard.md`.

Five parts, in order: what happened in plain English; what it means for them;
options with pros and cons; a recommendation **with its reasoning**; and what
happens if they do nothing. The plain-English half is ADDITIVE — exact commands,
paths, error text and numbers stay, in full, above it.

It also fixes a **controlled vocabulary**, and the sharpest edit is `gate`: in
prose it means the check between one phase and the next, and NOTHING else. The
commit-time, test, MCP and review surfaces are **checks**. Script filenames are
unaffected; this constrains prose, not code. Same for `block` vs `refuse` (a
failed check vs a tool that never started), `gap` vs `defect` (never built vs
built wrong), and `parked` vs `deferred` (nobody decided vs decided-to-wait).

Two rules that outrank brevity: **never round a number you did not derive**, and
**never soften a block into a suggestion** — if the reader cannot proceed, the
first sentence says so.

## CITATION RULE

Cite code by a **grep-able `# BL-NNN-…` marker comment** or a **function name** —
**never a bare `file:line`**. Line-number cites in handoffs have mis-resolved
within 24h of being written; the marker comment is the repo's citation
primitive. When reading an old handoff, **re-grep every line-number citation
before trusting it**.

**BL-196: the marker half is now lint-enforced** —
`scripts/lint-bl-markers.sh` (in the run-lints sweep and the
`bl-markers-lint` CI job; **not** a required check — that is Karl's later
call). Two directions, plus a vacuity floor:
- every `# BL-NNN-…` marker in the **code surface** (`init.sh`, `scripts/`,
  `tests/`, `templates/`, `evaluation-prompts/`, `.github/`) names a real
  `## BL-NNN:` entry;
- every marker **cited** in the **live prose surface** (`CLAUDE.md`,
  `README.md`, `CONTRIBUTING.md`, `solo-orchestrator-backlog.md`,
  `docs/**` minus `docs/handoffs/archive/**`) resolves to a marker that
  still exists. Frozen artifacts are deliberately out of scope —
  `Reports/**`, archived handoffs, `solo-orchestrator-bugs.md` — because
  they are stamped to the tree they were written against.

**A citation only counts when prose marks it as code**: backticked
(`` `# BL-084-TIER-KEY` ``) or hash-prefixed (`# BL-084-TIER-KEY`). A
**bare** `BL-NNN-suffix` token is invisible to the lint — of 21 bare hits,
**10** are real markers that go unchecked and **11** are ordinary prose
hyphenation: BL-140-family, BL-030-edit (left bare here on purpose —
backtick either one and this very line goes red).
**Backtick your markers** and they become enforced. Cite a fence family
(`# BL-105-PHASE4-GATE`) or a glob (`# BL-102-MARKET-SIGNAL-*`) and it
resolves against the `-BEGIN`/`-END` members; a **truncation typo does
not**. Deliberately-withdrawn markers get an allowlist row with a reason,
never a deletion.

## HANDOFFS

- Live handoffs: `docs/handoffs/` — the **newest date is current** (as of
  2026-07-31 evening that is `docs/handoffs/2026-07-31-bl201-bl200-close.md`).
  Everything else at the top level is a pointer stub, so "newest date" and
  "the one non-stub file" agree — if they ever disagree, trust the non-stub.
- Superseded / fully-executed handoffs move to `docs/handoffs/archive/` with a
  pointer stub left at the old top-level path so citations still resolve. See
  `docs/handoffs/archive/README.md` (includes the citation convention).

## ENFORCEMENT — SOURCE OF TRUTH

The **gate scripts are authoritative**, prose guides describe them and may lag —
trust the scripts:
- `scripts/check-phase-gate.sh` (phase 1→2 / 2→3 / 3→4 gates, approvals)
- `scripts/pre-commit-gate.sh` (commit-time gates)
- `scripts/process-checklist.sh` (Build Loop / commit-ready classifier)
- `scripts/run-phase3-validation.sh` (Phase 3 scanners)

**THE `[WARN]` TRAP (check-phase-gate.sh).** The `[WARN]` vs `[FAIL]` text is
**cosmetic** — the exit predicate is `if [ $issues -eq 0 ]`. So any "WARN" arm
that runs `issues=$((issues + 1))` **BLOCKS the gate**, and a true non-blocking
WARN must **omit** the increment. Two arms that both print `[WARN]` can have
opposite gate outcomes. Read the `issues` increment, not the label — that
mismatch is what hid both BL-104 scoring inversions (an `if/elif` with no `else`
let 0/9 Phase-3 steps pass while 8/9 blocked; an empty manifest scored better
than no manifest).

## GOTCHAS

- `pre-commit-gate.sh --tdd-only` runs **TWO** message gates: the BL-072 TDD
  ordering gate AND the BL-006 Build-Loop commit-message check (BL-010). The
  `--tdd-only` name is kept for **hook backward-compat**, not because it is
  TDD-only.
- The **deployment + poc_mode tier predicate** is implemented in **multiple
  scripts and must be changed IN SYNC**: `pre-commit-gate.sh`,
  `check-phase-gate.sh`, `init.sh` (grep the marker `# BL-084-TIER-KEY` — it
  literally says "SYNC SIBLINGS") plus `scripts/lib/enforcement-level.sh`.
- **Big files — grep, don't read whole** (`wc -l`, 2026-07-23, approximate —
  they grow): `init.sh` ~4400, `scripts/upgrade-project.sh` ~3400,
  `scripts/intake-wizard.sh` ~2250, `scripts/check-phase-gate.sh` ~2350,
  `tests/full-project-test-suite.sh` ~2700.

## HOUSE RULES DIGEST

- **No merge on red, ever.** No `gh pr merge --admin`.
- **TDD with mutation proofs** for enforcement changes: break the marked line →
  RED → restore → GREEN. Prove it, don't assert it.
- **Hermetic tests only** — no real remote creation (`lint-no-live-remote-in-tests.sh`
  enforces; a live `gh repo create` leaked a real repo on 2026-07-06).
- **Register every new `tests/test-*.sh`** in
  `tests/full-project-test-suite.sh` — AND, unless it invokes `init.sh`, in
  the `tests.yml` unit list too (per the CANONICAL COMMANDS membership rule).
  `lint-tests-registered.sh` enforces BOTH: the aggregator-registration
  backstop (BL-038) and, via its BL-154 unit-lane arm, the tests.yml
  `tests=(` membership of every test whose **executed lines do not name**
  `init.sh`. Read that predicate literally — it is *names on executed
  lines*, not *invokes*, and the gap between the two is real (below).
  Since BL-181 the exemption predicate reads **executed lines only**
  (`# BL-181-UNIT-LANE-PREDICATE`), so a mere *mention* of `init.sh` in a
  comment no longer exempts a test — in **either** spelling, whole-line at
  any indent **and** trailing (`code   # …`), and at any whitespace width
  (tabs and single spaces included), and whether or not a space follows the
  `#`. Both spellings need their own stage in the predicate, and U6's fixture
  in `tests/test-lint-tests-registered.sh` carries eight init.sh-bearing
  comment lines to pin them. **Two** atoms of the anchored line are not
  pinned by U6, and the fixture header names both rather than papering over
  them: the sed's `\([^[:space:]]\)` guard (behaviour-neutral once whole-line
  comments are stripped — deleting it leaves the suite at 24/0) and the
  grep's `^` anchor (not neutral — deleting it fails **U7 and U10**, at 22/2).
  Pin each atom's WIDTH and its SPELLING, not just its presence: a
  one-character narrowing — a quantifier, a character class, or `#` →
  `#[[:space:]]` — re-opened BL-181 three times and passed both PR-blocking
  checks every time. Before BL-181 a comment exempted a test outright and
  seven real files were silently exempt that way.
  **Never derive the unit list from `grep -L 'init\.sh' tests/test-*.sh`**
  — that recipe matches comments and is what produced the hole. **Two
  residuals survive, so a green lint is still not proof a fast test runs in
  the unit lane — check the list by hand.** (1) A mention inside a
  heredoc/string still exempts (a `grep`/`awk` target, or a stub the test
  writes). (2) In the OTHER half of the same feature, `_build_unit_list_set`
  scopes the `tests.yml` array with awk and never strips comments, so an entry
  **commented out** inside `tests=(` still counts as membership while bash
  drops it — the lint stays green and the test does not run. Both are recorded
  on `## BL-181:`, which stays Open for them. Every *decisive* exemption is
  rendered for review — audit it with
  `bash scripts/lint-tests-registered.sh --list | grep unit-lane-exempt`.
  **An exempt row is a claim, not a verdict: read the rows, do not count
  them — and audit them by EXECUTION, not by grep.** A 2026-07-26 grep-based
  audit of 33 rows moved 5 non-invokers into the unit list; a second pass
  over the remaining 28 — this time tracing execution — found one more
  (`tests/test-lint-no-live-remote.sh`), so a grep audit has now under-read
  this surface twice. The execution recipe: append an env-gated marker line
  to `init.sh`, run each exempt row with that env var set, and treat a marker
  as the only proof of invocation. On the tree of 2026-07-26 that pass
  classified all 27 rows *then present* as real invokers — a measurement at
  one commit, not a standing property. The tree has since grown (the BL-180
  suites pushed it to 29). Re-run it; do not cite the number.
- **Portability:** GNU-first `stat -c … || stat -f …`; never `((x++))` under
  `set -e`; configure a git identity in fixtures; unset `GITHUB_BASE_REF` in
  fixture git ops; no multibyte chars adjacent to variable expansions under
  `set -u`.
- **Docs-only commits** (all staged files match `\.(md|json|yml|yaml|toml|tmpl)$`)
  skip the Build Loop gate; mixed source+docs commits do not — split them
  (CONTRIBUTING.md § Docs-only bypass).
- **Never `--no-verify`.**

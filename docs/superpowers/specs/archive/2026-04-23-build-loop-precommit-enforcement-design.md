# BL-006: Pre-commit Build Loop Enforcement — Design

**Spec date:** 2026-04-23
**Backlog item:** BL-006 (High / Debt)
**Doctrinal parent:** BL-007 (Builder's Guide rule — MVP Cutline work always requires the Build Loop, shipped in PR #14 on 2026-04-23)

## 1. Problem

`scripts/process-checklist.sh --start-feature` is advisory. A `feat(...)` commit can land without an active Build Loop, and `--record-feature` detects the drift only after the fact. Surfaced on the lancache project: MVP Cutline items ID1 and ID3 were committed as `feat(init): ...` without going through the Build Loop; the drift was caught retroactively.

The existing pre-commit enforcement in `scripts/process-checklist.sh::check_commit_ready` (invoked from `pre-commit-gate.sh:114`) triggers only on a staged-file heuristic — paths matching `\.(py|ts|...)` or dirs `^src|^lib|^app|^pkg|^internal|^cmd/`. Commits whose source lives outside those patterns (e.g., lancache's `migrations/`) miss the trigger and no feature-started check fires.

BL-006 adds a **second trigger axis**: the commit message itself. When the author types `feat(...)`, they have declared feature intent — that signal is independent of which paths are staged.

## 2. Scope

**In scope.** A new trigger in the pre-commit gate that:

1. Detects a `feat`-prefixed commit message in the bash command the Claude agent is about to run.
2. Delegates to a new `process-checklist.sh --check-commit-message "MSG"` subcommand.
3. Applies the same strict Build Loop state check the existing file-heuristic path uses (feature started + first 5 `build_loop` steps completed).
4. Denies the commit with an actionable remediation message when the state check fails.

**Out of scope for this spec.** See § 10 for follow-ups logged as separate backlog items.

## 3. Locked parameters

Settled during the brainstorming dialogue on 2026-04-23:

| Parameter | Decision |
|---|---|
| Trigger signal | Commit message prefix only (`feat`, `feat(scope)`, `feat!`, `feat(scope)!`), optional `!` marks breaking per Conventional Commits |
| Strictness | Strict — always block; no warns-then-blocks grace window |
| Scaffolding bypass | **None.** Non-Cutline scaffolding must use `chore:` / `build:` / `ci:` / `docs:` — the correct Conventional Commits type. The rule forces commit hygiene as a side benefit. |
| Phase gate | Phase < 2 → no enforcement, same as existing `check_commit_ready` |
| `SOIF_*` env bypass | None added. Orchestrator-run `SOIF_FORCE_STEP` remains the only existing bypass path. |

## 4. Architecture

Two files change, one new subcommand, one new helper. Single new enforcement site layered on top of the existing file-heuristic trigger.

```
Claude Bash tool call ("git commit -m '...' ...")
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│ pre-commit-gate.sh  (PreToolUse hook; bash-shape concern)│
│                                                          │
│  existing early guards (no-verify, amend-warn, force-    │
│  push, no-remote, SOIF_FORCE_STEP…)                      │
│                            │                             │
│                            ▼                             │
│  NEW: commit-message extraction & filter                 │
│    - skip if MERGE_HEAD exists          → exit 0         │
│    - skip if cmd is git merge / revert /                 │
│      cherry-pick / gh pr merge --squash → exit 0         │
│    - skip if --amend present            → exit 0 (warn   │
│      already emitted earlier in this script)             │
│    - parse -m "..." / heredoc / -F file → MSG            │
│    - if MSG empty (editor case)         → exit 0         │
│                            │                             │
│                            ▼                             │
│  call: process-checklist.sh --check-commit-message "$MSG"│
│         exit 0 → allow (not feat, or state OK)           │
│         exit 1 → emit deny JSON with stderr as reason    │
│                            │                             │
│                            ▼                             │
│  existing --check-commit-ready file-heuristic path       │
│  (unchanged; runs for every commit; independent trigger) │
└──────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│ process-checklist.sh --check-commit-message "MSG" (NEW)  │
│                                                          │
│  1. Phase < 2                              → exit 0      │
│  2. MSG !~ feat prefix regex               → exit 0      │
│  3. require_build_loop_state_for_commit()  │             │
│     ├─ feature == null         → exit 1 "no loop"        │
│     └─ first 5 steps incomplete → exit 1 "step X missing"│
│  4. all checks pass                        → exit 0      │
└──────────────────────────────────────────────────────────┘
```

**Boundary:** `pre-commit-gate.sh` knows shells (bash command shapes, `git` subcommand detection, `MERGE_HEAD`, message extraction). `process-checklist.sh` knows policy (regex, phase gate, state machine, step completion). Each is independently understandable and testable.

## 5. New subcommand contract

```
Usage: scripts/process-checklist.sh --check-commit-message "COMMIT_MSG_FIRST_LINE"

Arguments:
  COMMIT_MSG_FIRST_LINE   The subject line (first line) of the commit message.
                          Caller is responsible for trimming to the first line.

Exit codes:
  0   No enforcement needed. Reasons:
        - Phase < 2 (phase gate)
        - Subject does NOT match feat prefix
        - Subject matches feat AND Build Loop state satisfied
          (feature != null AND first 5 build_loop steps completed)
  1   Enforcement failed. Two sub-cases, distinguished in stderr:
        - feat-prefixed but no feature started
        - feat-prefixed, feature started, but a required step is incomplete

Stdout:   silent on both success and failure.
Stderr:   on exit 1, print_fail-formatted remediation (single FAIL line +
          action steps) compatible with pre-commit-gate.sh's JSON-encoding
          pipeline (tr '\n' ' ' | sed 's/"/\\"/g').
```

**Feat-prefix regex** (anchored to the start of the subject, case-sensitive per Conventional Commits):

```
^feat(\([^)]*\))?!?:[[:space:]]
```

Matches: `feat:`, `feat(x):`, `feat!:`, `feat(x)!:` — each followed by at least one whitespace character.
Rejects: `feature:`, `feat-something:`, `featbar:`, `FEAT:`.

**Shared helper `require_build_loop_state_for_commit()`.** Factored out of the existing `check_commit_ready` body (currently lines 812–827 of `process-checklist.sh`). Both the file-heuristic path and the new message-prefix path call it, so the state check lives in exactly one place. Signature: zero arguments, reads `$PROCESS_STATE`, calls `print_fail`, returns 0 or 1.

## 6. Message extraction in `pre-commit-gate.sh`

The new block is inserted after the existing `--amend` warn (lines 74–80) and before the existing `--force` push block (line 83). It runs before the existing `--check-commit-ready` invocation so the two triggers share no state.

**Algorithm.**

1. Is the command a `git commit`? Detect with `grep -qE '\bgit\b.*\bcommit\b'`. If no, fall through.
2. Derivative-commit filter. Any of the following → fall through:
   - `--amend` in command (existing hook already warns).
   - `.git/MERGE_HEAD` exists (merge commit in progress).
   - Command contains `git merge`, `git revert`, `git cherry-pick`, or `gh pr merge --squash`.
3. Message extraction. Attempt in order:
   1. **Heredoc:** If command contains `-m "$(cat <<'EOF'` (or `<<EOF`), extract the first non-empty line after the heredoc opener and before the closing `EOF`. Realized with an awk one-liner.
   2. **Inline `-m`:** Extract the first quoted string immediately following `-m`. Take only the first line (split on `\n`). Handles both `"..."` and `'...'`.
   3. **`-F <file>`:** Read the file, take its first line. If the file is missing or unreadable, fall through (git itself will error).
   4. **None of the above (editor case):** fall through.
4. If extracted `MSG` is empty, fall through.
5. Call `process-checklist.sh --check-commit-message "$MSG"`.
   - Exit 0 → continue past this block; fall through to the existing `--check-commit-ready` file-heuristic path.
   - Exit 1 → emit deny JSON using the captured stderr as `permissionDecisionReason`, then `exit 0` from the hook itself (the JSON carries the denial; the hook process must exit 0 for the hook protocol).

**Robustness policy.** The parser is intentionally narrow — three shapes (heredoc, `-m`, `-F`) cover the patterns Claude's own system prompt teaches and nearly all real AI-authored commits. Exotic shapes (multiple `-m` flags concatenating, complex embedded-quote escaping) fall through silently. That means the new trigger might miss on exotic shapes, but the existing file-heuristic trigger still runs — zero regression on existing enforcement.

**False-positive note.** Only the first line (subject) of the message is checked. A commit body containing a quoted `feat(x): example` line (e.g., quoting another commit) does not mis-trigger.

## 7. User-facing error messages

Two deny-reason shapes. Both are plain-text multi-line strings that the existing `pre-commit-gate.sh:118` pipeline compresses into a single-line `permissionDecisionReason` for the Claude agent.

**Case A — `feat`-prefixed commit, no feature started.**

```
pre-commit gate: 'feat(...)' commit blocked — no Build Loop active.
MVP Cutline work and all features require a Build Loop per
docs/builders-guide.md § "MVP Cutline Work Requires the Build Loop".

To proceed:
  1. scripts/process-checklist.sh --start-feature "NAME"
  2. Write failing tests, implement, verify, update docs
  3. Complete each step: scripts/process-checklist.sh --complete-step build_loop:STEP
  4. Re-run your commit

If this commit is NOT a feature (tooling, CI, scaffolding, docs),
change the conventional-commit type: feat: → chore:/build:/ci:/docs:.
```

**Case B — `feat`-prefixed commit, feature started but steps incomplete.**

```
pre-commit gate: 'feat(FEATURE_NAME)' commit blocked — Build Loop incomplete.
Missing step: STEP_NAME

Run: scripts/process-checklist.sh --complete-step build_loop:STEP_NAME
Then: scripts/process-checklist.sh --status  (to verify)
Then re-run your commit.
```

**Message design principles:**

1. Name the doctrine. Each message cites the Builder's Guide subsection BL-007 shipped, so the agent gets the *why*.
2. Offer the Conventional Commits escape route in Case A. If the commit is genuinely not a feature, re-typing the commit-type is the sanctioned path.
3. No `SOIF_*` bypass mentioned. Per the strict-enforcement decision, there is no bypass, and documenting one would defeat the rule.
4. Pin the failure to a specific missing step in Case B. The existing `check_commit_ready` already enumerates which step blocked it; reuse that.
5. Plain text only. No colors, no emojis. Matches existing `print_fail` / deny-reason style.

## 8. Testing plan

**Unit tests — new file `tests/test-check-commit-message.sh`.** Exercises `process-checklist.sh --check-commit-message "MSG"` in isolation — no hook, no staged files, no bash parsing. Sets up a fake `.claude/` with controlled `phase-state.json` and `process-state.json` in a tempdir, asserts exit codes and stderr content.

| # | Setup | MSG | Expected |
|---|---|---|---|
| U1 | Phase 0 | `feat(x): foo` | exit 0 (phase gate) |
| U2 | Phase 1 | `feat(x): foo` | exit 0 (phase gate) |
| U3 | Phase 2, no feature started | `feat(x): foo` | exit 1, stderr names `--start-feature` |
| U4 | Phase 2, no feature started | `fix(x): foo` | exit 0 (non-feat) |
| U5 | Phase 2, no feature started | `chore: bump` | exit 0 |
| U6 | Phase 2, no feature started | `docs: typo` | exit 0 |
| U7 | Phase 2, no feature started | `feat: foo` (no scope) | exit 1 |
| U8 | Phase 2, no feature started | `feat!: breaking` | exit 1 |
| U9 | Phase 2, no feature started | `feat(x)!: breaking` | exit 1 |
| U10 | Phase 2, no feature started | `feature: foo` (wrong word) | exit 0 |
| U11 | Phase 2, no feature started | `featbar: foo` (prefix-match false-positive) | exit 0 |
| U12 | Phase 2, feature started, 0 steps done | `feat(x): foo` | exit 1, stderr names missing step |
| U13 | Phase 2, feature started, steps 0–3 done | `feat(x): foo` | exit 1, stderr names step index 4 |
| U14 | Phase 2, feature started, all 5 steps done | `feat(x): foo` | exit 0 |
| U15 | Phase 2, feature started, all 5 steps done | `fix(x): foo` | exit 0 (non-feat still passes) |
| U16 | Phase 2, feature started, all 5 steps done | empty string | exit 0 |
| U17 | Phase 2, no feature started | `Revert "feat(x): foo"` | exit 0 (regex rejects) |

**Integration tests — extend `tests/edge-cases-scripts.sh`** with E33–E39 (continuing the edge-case numbering).

| # | Stdin-JSON command to hook | `.claude/` state | Expected |
|---|---|---|---|
| E33 | `git commit -m "feat(x): thing"` | Phase 2, no feat started | deny JSON, reason contains `--start-feature` |
| E34 | `git commit -m "$(cat <<'EOF'\nfeat(x): thing\nEOF\n)"` | Phase 2, no feat started | deny JSON (heredoc parsed) |
| E35 | `git commit -F /tmp/msg` (file contents: `feat(x): foo`) | Phase 2, no feat started | deny JSON (file read) |
| E36 | `git commit -m "feat(x): thing" --amend` | Phase 2, no feat started | allow (amend path wins, no double-block) |
| E37 | `git commit -m "Merge branch 'x'"`, `.git/MERGE_HEAD` present | Phase 2, no feat started | allow (merge skip) |
| E38 | `git commit` (no `-m`, editor case) | Phase 2, no feat started | allow (message unknown; falls through) |
| E39 | `git commit -m "feat(x): thing"` | Phase 0 | allow (phase gate) |

E34 is the most important — it proves the heredoc parser works, and the heredoc pattern is the shape Claude's system prompt teaches for commit messages.

**Test-harness changes:** none. Both files follow existing patterns. `edge-cases-scripts.sh` uses the same stdin-piping approach as the existing E1–E32 tests.

## 9. Template & docs updates

**`docs/builders-guide.md`.** One-paragraph addition at the end of the existing "MVP Cutline Work Requires the Build Loop" subsection (shipped in PR #14):

> This rule is enforced mechanically by the pre-commit gate: any `git commit` with a message starting with `feat`, `feat(scope)`, `feat!`, or `feat(scope)!` is blocked unless a Build Loop is active and its first five steps are complete. Non-feature scaffolding (tooling, CI, build configs) should use the correct Conventional Commits type — `chore:`, `build:`, `ci:`, `docs:` — which the gate does not enforce against.

**`templates/generated/claude-md.tmpl`.** Add one subordinate bullet under the existing MVP Cutline bullet from PR #14:

> - The pre-commit gate blocks `feat:` commits without an active Build Loop. Non-feature work should use `chore:`/`build:`/`ci:`/`docs:`.

**`scripts/process-checklist.sh` `--help`.** Add a line listing the new `--check-commit-message` action alongside the existing `--check-commit-ready`.

**`scripts/upgrade-project.sh`.** No migration code required — `process-checklist.sh` is already copied by `upgrade-project.sh`'s existing behavior, so existing projects pick up the new subcommand on their next upgrade run. One line added to the upgrade changelog noting the new enforcement.

## 10. Follow-ups (logged to backlog as BL-010…BL-014, optional — to be evaluated)

Everything below is out of scope for BL-006 itself. Each is logged as its own backlog entry so the design decisions here are traceable and the items are not forgotten.

- **BL-010 — `.git/hooks/commit-msg` for editor-case & human-terminal coverage.** Install a git hook in `init.sh` that calls `process-checklist.sh --check-commit-message`. Covers shape (h) — `git commit` with no `-m` (editor opens) — and protects human-Orchestrator commits. Punted because the pain was AI-agent authored, not human, and Approach 2 makes this a pure addition.
- **BL-011 — Cutline-ID-aware enforcement.** Parse `PRODUCT_MANIFESTO.md §5` for F-/ID- identifiers, require `feat(ID1): ...` format, cross-check that every Cutline ID gets exactly one Build Loop. Would let us catch `fix(ID1): ...` drift (Cutline work masquerading as a bugfix). Punted because BL-007 deliberately kept the rule generic (no ID-prefix convention forced).
- **BL-012 — Retroactive scanning.** Audit git history for past `feat:` commits lacking a recorded Build Loop. The hook enforces forward; this would close the historical gap. `test-gate.sh --record-feature` remains the post-hoc reconciliation path today.
- **BL-013 — Squash-merge server-side enforcement.** `gh pr merge --squash` runs remotely; any enforcement there needs CI. Separate project — requires GitHub Actions workflow, secrets, and cross-host compatibility with the GitLab/Bitbucket drivers.
- **BL-014 — Commit-type hygiene enforcement.** Prevent mis-typed commit types (e.g., a real feature disguised as `chore:`). Currently reviewer/author judgment; automation would require intent inference from the diff, which is brittle.

All five are flagged **Optional — evaluate when a concrete need arises**. None is committed to implementation by landing BL-006.

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Heredoc parser fragility | Narrow the parser to the exact shape Claude's system prompt teaches; exotic shapes fall through silently. Integration test E34 explicitly proves the canonical shape parses. |
| False positive on revert commits | Regex is anchored to start-of-subject; `Revert "feat..."` does not match. Test U17 codifies this. |
| False positive on merge commits | `.git/MERGE_HEAD` check filters in-progress merges; command-pattern filter catches `git merge` invocations. Test E37 covers the MERGE_HEAD case. |
| Agent attempts to bypass by switching to `chore:` for real features | Out of scope per Section 3 (scaffolding bypass = none). The gate does not infer intent from the diff. Logged as BL-014. |
| Human Orchestrator not covered | Acknowledged — PreToolUse hook is Claude-only by design. Logged as BL-010 (commit-msg git hook) if editor-case coverage is later wanted. |
| Extraction parser breaks an existing commit shape | Existing file-heuristic path is untouched. New block only adds denials; never removes them. Zero regression risk on commits that pass today. |

## 12. Success criteria

1. A Claude agent attempting `git commit -m "feat(x): foo"` in a Phase-2 project with no active Build Loop is denied with the Case A remediation message.
2. A Claude agent with an active Build Loop but incomplete steps is denied with Case B naming the specific missing step.
3. A `chore:` / `build:` / `ci:` / `docs:` commit with no active Build Loop is allowed (the existing file-heuristic still runs; source commits still blocked by the pre-existing path).
4. `git commit --amend` continues to warn (never block via this new path); merge and revert commits pass through.
5. Heredoc-shaped commits (the pattern the system prompt teaches) are correctly parsed and gated.
6. All 17 unit tests + 7 integration tests pass.
7. Running `scripts/upgrade-project.sh` on an existing downstream project picks up the new enforcement with no manual migration.

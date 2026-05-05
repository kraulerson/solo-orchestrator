# BL-030: User-Terminal Enforcement Model — Design

**Spec date:** 2026-04-28
**Backlog item:** BL-030 (High / Design question — pending brainstorm at spec time)
**Pairs with:** BL-029 (Bypass audit-log infrastructure)
**Driver:** Calibration sweep 2026-04-27 finding NEW-5 (surfaced independently by agents 1, 2, and 3): PreToolUse hooks (`pre-commit-gate`, `branch-safety`, `config-guard`) only fire under Claude Code. A user running `git commit` in their own terminal bypasses every BL-006 / BL-015 / build-loop check by design. `.git/hooks/pre-commit` runs gitleaks / Semgrep / TDD only — not framework governance.

## 1. Problem

The framework's stated enforcement model is "Claude is the agent; gates fire on Claude's actions." This is consistent with how PreToolUse hooks work, but the calibration sweep showed three failure modes the model produces:

1. **Successor-handoff (W7) gap.** A successor inheriting a project sees Claude's audit trail but has no record of what the original user did from their own terminal. The framework's central use case — shadow-IT mitigation through handoff-readiness — is structurally incomplete.
2. **Learning-user (W6) gap.** A novice picking up the framework reads "this framework enforces governance" and does not realize that a single `git commit` in their terminal voids every gate. The teaching the framework purports to deliver is one shell prompt away from being undone.
3. **Self-discipline (W4) gap.** The framework's author can bypass their own framework whenever they're not in a Claude session. The "forcing function" value prop is theatrical when the forcing function only applies inside one specific tool.

These three audiences are equally weighted (Q1 = D, brainstorming dialogue 2026-04-28).

## 2. Scope

**In scope:**
- New `enforcement_level` field in `.claude/manifest.json` with values `no` / `light` / `strict`.
- Init-time UX for choosing the level, including mode-gated availability and pitfall warnings (W5/W6/P1 teaching pattern).
- Filesystem-level git hook integration for strict mode, composing with the existing `.git/hooks/pre-commit` chain (gitleaks / Semgrep / TDD) without modifying it destructively.
- SessionStart-triggered out-of-band commit detection for light mode.
- Reconfiguration path (`scripts/reconfigure-project.sh --enforcement-level <level>`) with transition validation.
- Refinement of BL-029 to make `.claude/bypass-audit.json` the single ledger for all enforcement-related events across actors and levels.

**Out of scope:**
- The BL-029 Claude-side bypass-shape detector itself (PostToolUse / Stop hook scanning Claude output for `--no-verify` / `SOIF_FORCE_STEP=` / etc.). That is BL-029 proper; this spec depends on it but does not subsume it.
- An "eventually-blocked observation" intermediate level where light mode escalates to a block on next session start. Possibly worth a future BL item; not BL-030.
- Push-time hooks, branch-deletion hooks, tag/config audits. Light mode promises commit visibility, no more.
- Rebuilding `.git/hooks/pre-commit` under the `pre-commit` Python framework. Direct file install only, with a marked block, to avoid fighting an external tool that thinks it owns the hook file.

## 3. Locked parameters

Settled during the 2026-04-28 brainstorming dialogue.

| Parameter | Decision | Source |
|---|---|---|
| Audience for enforcement | Successor-handoff (W7), learning-user (W6), and self-discipline (W4) — all equally weighted | Q1 — D |
| Substrate | New first-class `enforcement_level` manifest field; not a reuse of `SOIF_STRICT_*` env vars | Q2 path — Approach 1 |
| Three options become a menu | `no` → accept-as-designed; `light` → post-hoc audit; `strict` → filesystem-level git hook | Brainstorm consolidation |
| Choosability | `deployment=personal` OR `poc_mode=private_poc` → user picks; `poc_mode=sponsored_poc` or `""` (production) → forced strict | User direction |
| Audit log relationship | Always-on regardless of `enforcement_level`. `enforcement_level` controls only whether the audit also blocks. BL-029 ships independently; BL-030 layers on top. | Q3 — B |
| Default for choosable modes | `strict` | Q4 — A |
| Init-time pitfall warnings | Required for downgrade to `light` or `no`; teach the principle, not just the procedure | W5/W6/P1 |
| Ledger schema | Single `.claude/bypass-audit.json` file with `actor` and `type` discriminators; same file used by BL-029 Claude-side writer, BL-030 strict writer, BL-030 light writer, and init/reconfigure recorders | Section 5 |

## 4. Architecture

```
                  ┌────────────────────────────────────────────────┐
                  │            .claude/manifest.json               │
                  │     enforcement_level: no | light | strict     │
                  └────────────────────────────────────────────────┘
                                          │
                                  read by ▼
        ┌──────────────────┬──────────────────────┬──────────────────────────┐
        │                  │                      │                          │
   PreToolUse hooks   SessionStart hook   .git/hooks/pre-commit       PostToolUse + Stop hooks
   (Claude side —     (runs detect-out-   (strict mode only —          (BL-029 audit-log
   ALWAYS run; level   of-band-commits    framework-gate.sh,           writer; ALWAYS
   doesn't gate them)  on light AND       sourced by hook chain;       runs;
                       strict — strict    self-no-ops if level         record-claude-commit
                       runs it for        changes mid-life)            also fires here)
                       --no-verify
                       capture)
        │                  │                      │                          │
        │                  │                      │                          │
        └──────────────────┴──────────┬───────────┴──────────────────────────┘
                                      ▼
                          .claude/bypass-audit.json
                       (single source of governance truth)
```

**Key invariant.** PreToolUse hooks (Claude side) are unaffected by `enforcement_level`. Claude is *always* gated. `enforcement_level` controls only the user-terminal layer. The original "Claude is the agent under enforcement" model stays intact; this spec adds a parallel knob for "and what about user-terminal?"

### Mapping of original BL-030 trichotomy to enforcement_level

| Original option | enforcement_level | What gets installed |
|---|---|---|
| (a) Accept as designed | `no` | Nothing on the user-terminal side. Audit-log writer (BL-029) still records Claude-side bypass proposals. |
| (c) Post-hoc audit | `light` | `SessionStart` hook entry triggering `detect-out-of-band-commits.sh`. Audit log captures user-terminal commits after the fact. |
| (b) Filesystem-level git hooks | `strict` | `.git/hooks/framework-gate.sh` script + a marked block in `.git/hooks/pre-commit` that sources it. Real-time block on the user-terminal pathway. |

The trichotomy is no longer a choice between three architectures. It is one architecture (the menu) with three settings.

## 5. Components

### 5.1 New manifest field

`.claude/manifest.json` adds:

```json
"enforcement_level": "strict"
```

Values: `"no" | "light" | "strict"`. Default at read time (covers projects upgrading from pre-BL-030): `"strict"`. A pre-BL-030 project with no field present is treated as strict and emits a one-line migration notice on next session start.

### 5.2 New scripts

| File | Purpose | Triggered by |
|---|---|---|
| `scripts/lib/enforcement-level.sh` | Library. `read_enforcement_level()`, `assert_choosable()`, `validate_transition()`. Sourced by everything else. | (sourced) |
| `scripts/detect-out-of-band-commits.sh` | Light-mode detector. Reads commit history since last checkpoint, filters against `claude-commits.jsonl`, writes `out_of_band_commit` rows to `bypass-audit.json`. | `SessionStart` hook |
| `scripts/install-filesystem-gates.sh` | Strict-mode installer/uninstaller. Idempotent. Composes framework gate into `.git/hooks/pre-commit` via marked block; never touches gitleaks / Semgrep / TDD blocks. | `init.sh` (when strict) and `reconfigure-project.sh` (on level change) |
| `scripts/hooks/record-claude-commit.sh` | PostToolUse hook. After successful `git commit` from Claude, captures `git rev-parse HEAD` and appends to `claude-commits.jsonl`. Always-on. | `PostToolUse` |

### 5.3 Modified scripts

| File | Change |
|---|---|
| `init.sh` | Add enforcement-level prompt for choosable modes; force `strict` for non-choosable; show pitfall warnings on downgrade; persist to manifest; call `install-filesystem-gates.sh` if strict; add `--enforcement-level <level> [--confirm-pitfalls]` non-interactive flags. Initialize `last-checked-commit.txt` to current HEAD. |
| `scripts/reconfigure-project.sh` | Add `--enforcement-level <level> [--confirm-pitfalls]` flag with transition validation; invoke filesystem-gates installer/uninstaller as needed; append `enforcement_level_set` audit row. |

### 5.4 New runtime files (project-local)

| File | Purpose |
|---|---|
| `.claude/claude-commits.jsonl` | Append-only ledger of Claude-issued commits (SHA, timestamp, session_id). Written by `record-claude-commit.sh`. Read by `detect-out-of-band-commits.sh`. |
| `.claude/last-checked-commit.txt` | Single-line file holding the SHA the out-of-band detector last verified up to. Initialized by `init.sh`; updated by detector on each run; reset by `reconfigure-project.sh --reset-detection-baseline`. |
| `.git/hooks/framework-gate.sh` | Strict-mode framework-gate script. Standalone. No-ops if `enforcement_level != "strict"` (defense in depth — even if level changes mid-life and uninstaller fails to remove the marker, the gate self-disables). |

### 5.5 New `.claude/settings.json` hook entries

`SessionStart` hook entry calling `scripts/detect-out-of-band-commits.sh`. Always present in the template; the script self-gates on `enforcement_level`.

`PostToolUse` hook entry calling `scripts/hooks/record-claude-commit.sh`. Always-on.

### 5.6 BL-029 audit-log writer (referenced, not specified here)

The Claude-side bypass-shape detector — PostToolUse + Stop hooks scanning Claude output for `--no-verify`, `SOIF_FORCE_STEP=`, "run this in your terminal", synthetic Build Loop step proposals, etc. — is BL-029's responsibility. This spec depends on:

1. The existence of `.claude/bypass-audit.json` as the writer's output file.
2. The schema specified in § 6 below being adopted by both BL-029's writer and BL-030's three writers.

## 6. Data — `.claude/bypass-audit.json` ledger schema

Single artifact. Append-only. JSONL or JSON-array; choice deferred to BL-029 implementation. Schema:

```json
{
  "timestamp": "ISO-8601",
  "session_id": "string-or-null",
  "type": "claude_bypass_proposal | terminal_commit_blocked | terminal_commit_passed | out_of_band_commit | enforcement_level_set | detector_error | escalation",
  "actor": "claude | user_terminal | user_terminal_inferred | framework",
  "enforcement_level_at_event": "no | light | strict",
  "details": { /* type-specific payload */ },
  "user_response": "PENDING | accepted | declined | n/a",
  "final_outcome": "committed | bypassed | escalated | abandoned | recorded_only | n/a"
}
```

### Writer-by-writer responsibility

| Writer | `actor` | `type` | When | Always-on? |
|---|---|---|---|---|
| BL-029 Claude-side detector | `claude` | `claude_bypass_proposal` | Bypass-shaped language matched in Claude output | Yes — independent of `enforcement_level` |
| `framework-gate.sh` (strict) | `user_terminal` | `terminal_commit_blocked` or `terminal_commit_passed` | User-terminal `git commit` — gate fired | Only when `enforcement_level=strict` |
| `detect-out-of-band-commits.sh` (light) | `user_terminal_inferred` | `out_of_band_commit` | SessionStart, commits found between checkpoint and HEAD that aren't in `claude-commits.jsonl` and aren't derivative | Only when `enforcement_level=light` |
| `init.sh` / `reconfigure-project.sh` | `framework` | `enforcement_level_set` | One row per init or reconfigure | Yes |
| Detector self-error reporter | `framework` | `detector_error` | Detector failed to read state, parse, or write | Yes — never silent |
| `escalate-to-user` CLI (BL-029) | `framework` | `escalation` | Claude calls the CLI to surface a structured pending-approval as an alternative to bypass-proposing | Yes — independent of `enforcement_level` |

The `actor` and `type` discriminators give a successor-pickup operator (`jq` over the file) the project's complete governance history at a glance.

### Schema migration

Schema is established by BL-029's first writer. BL-030's three writers extend the `type` enum with backward-compatible additions. No version field at v1; if a v2 schema becomes necessary, add a top-level `schema_version` field at that time. Pre-existing rows are valid v1 by absence.

## 7. Init UX

After `init.sh` resolves `track`, `deployment`, and `poc_mode` (existing logic at `init.sh:339–386`), branch on choosability.

### 7.1 Non-choosable modes

`deployment=organizational` AND `poc_mode` ∈ `{"", sponsored_poc}` → no prompt. Print:

```
  Enforcement level: strict (forced)
  Sponsored POC and Production builds run with full enforcement —
  framework gates apply to both Claude and user-terminal actions.
  This is non-configurable for these governance modes.
```

Persist `enforcement_level=strict` and proceed.

### 7.2 Choosable modes

`deployment=personal` OR `poc_mode=private_poc` → show:

```
  Enforcement level:
    strict — Framework gates apply to BOTH Claude and your terminal.
             A user-terminal `git commit` runs the same checks Claude's
             commits do (test gate, build-loop steps, secret scan, etc.).
             Bypass with --no-verify is recorded in .claude/bypass-audit.json.
             Recommended. The default.

    light  — Framework gates apply to Claude only. User-terminal commits
             go through, but are detected on next session start and
             recorded in .claude/bypass-audit.json. You see them; the
             framework just doesn't block them in real time.

    no     — Framework gates apply to Claude only. User-terminal commits
             are NOT recorded. Closest to "Claude does what I tell it; I
             do whatever I want." Audit log still captures Claude's own
             bypass proposals (BL-029) — that channel is non-configurable.

  Choice [strict]:
```

If user picks `light` or `no`, **show the pitfall block** before accepting. The pitfall block teaches the principle (W5/W6/P1), not just the procedure.

#### 7.2.1 Pitfall block — `light`

```
  You picked: light enforcement.

  What you're trading away:
    • Real-time block on user-terminal commits that violate framework rules
      (e.g., committing without a Build Loop, committing source without tests).
    • Symmetric discipline. Claude follows the rules; you'll be free not to.

  What you keep:
    • Claude is still gated. Anything Claude does goes through every check.
    • Every user-terminal commit is recorded in .claude/bypass-audit.json
      on next session start. You'll see what you did, even if no one
      stopped you doing it.

  When this is the right choice:
    • You're an experienced operator using the framework on your own work
      and want low friction outside Claude sessions.
    • You're doing framework development itself (the framework's strict
      mode is not the right tool for the framework's own dev work — see
      docs/personal/owner-development-notes.md W4).

  When this is the wrong choice:
    • You're learning. Light enforcement teaches you to bypass when
      convenient, which is exactly the habit the framework is designed
      to break (W6).
    • A successor will pick up this project. They'll inherit your audit
      log but not your discipline. Light produces a longer audit trail
      than strict; strict produces fewer events worth auditing.

  Confirm light? [y/N]:
```

#### 7.2.2 Pitfall block — `no`

```
  You picked: no enforcement.

  What you're trading away:
    • Everything light gives you, plus visibility into your own commits.
    • The framework's W7 handoff-readiness story. A successor inheriting
      this project sees Claude's audit trail but no record of what you
      did outside Claude. They have to trust git history and CI.

  What you keep:
    • Claude is still gated. Bypass proposals from Claude are still
      audited (BL-029) — that's non-configurable.
    • CI-side enforcement (gitleaks, Semgrep, dependency audit) — those
      are GitHub Actions, not framework hooks. They run regardless.

  When this is the right choice:
    • Throwaway projects, exploratory spikes, single-session work that
      will never be handed off.

  When this is the wrong choice:
    • Anything you might keep for more than a week.
    • Anything someone else might touch.
    • Anything that might inform a future production project (skill
      transfer goes the wrong way — you teach yourself "bypass when
      convenient").

  Confirm no enforcement? [y/N]:
```

If user declines (`n`), loop back to the choice prompt.

### 7.3 Persistence

After confirmation:

1. `enforcement_level` written to `manifest.json`.
2. An `enforcement_level_set` row appended to `bypass-audit.json` with `details: {level, confirmed_pitfalls: bool, source: "init"}`.
3. `last-checked-commit.txt` initialized to `git rev-parse HEAD`.
4. If `strict`, `install-filesystem-gates.sh` runs.
5. End-of-init banner: `Enforcement: <level> — see .claude/manifest.json. Reconfigure with: scripts/reconfigure-project.sh --enforcement-level <new>.`

### 7.4 Session-start reminder

For `light` and `no`, `SessionStart` hook prints one line per session:

```
⚠ Enforcement level: <light|no> — user-terminal commits not blocked.
  Run scripts/reconfigure-project.sh --enforcement-level strict to upgrade.
```

For `strict`, no banner. The absence of friction is the signal.

### 7.5 Non-interactive

`init.sh --enforcement-level <level>` for non-interactive callers. If level is `light` or `no` AND mode is choosable, the flag confirms automatically (suppresses pitfall blocks); pair with `--confirm-pitfalls` for explicit-acknowledgment semantics required by automated callers (test suite, BL-025 helpers). If level is `strict` or mode is non-choosable, the flag has no effect beyond setting the value.

## 8. Strict-mode integration with `.git/hooks/pre-commit`

The existing `.git/hooks/pre-commit` already runs gitleaks + Semgrep + a TDD heuristic check (per `docs/user-guide.md:160`). Solo Orchestrator did not author it end-to-end — gitleaks installs/manages its own block, and external tooling may rewrite the file. Naive augmentation risks (a) breaking gitleaks updates, (b) getting overwritten by a `pre-commit` framework reinstall, (c) silent failures.

### 8.1 Composition strategy

Extract the framework gate to a stable script and have the existing `pre-commit` hook source it via a marked block:

**`.git/hooks/framework-gate.sh`** — installed by `install-filesystem-gates.sh`:
- Reads `enforcement_level` from manifest. No-ops with exit 0 if not `strict` (defense in depth — survives marker-removal failures).
- Calls `scripts/process-checklist.sh --check-commit-ready`.
- Calls `scripts/pre-commit-gate.sh --terminal-mode` (new flag — see § 8.3).
- Writes a `terminal_commit_blocked` or `terminal_commit_passed` row to `bypass-audit.json` either way.
- Block message follows W5/P1 — every block prints both the procedure and the principle (see § 8.4).

**Marked block appended once to `.git/hooks/pre-commit`:**

```bash
# >>> SOIF framework gate (BL-030) — do not edit; managed by install-filesystem-gates.sh
if [ -f "$(git rev-parse --show-toplevel)/.git/hooks/framework-gate.sh" ]; then
  bash "$(git rev-parse --show-toplevel)/.git/hooks/framework-gate.sh" || exit $?
fi
# <<< SOIF framework gate
```

### 8.2 Idempotence and ordering

The installer detects the marker delimiters. If present, no-op. If absent, append after the existing chain. Never modify gitleaks / Semgrep / TDD blocks. Never reorder existing content.

Order rationale: gitleaks finds leaks first (security-critical, runs regardless of process state); framework gate catches process violations second. If gitleaks fires, the user never sees the framework block — correct, because security findings outrank process discipline.

### 8.3 Reused logic, not duplicated

`framework-gate.sh` calls `process-checklist.sh --check-commit-ready` (same call Claude's PreToolUse hook makes) and a new `pre-commit-gate.sh --terminal-mode` flag. The terminal-mode flag tells the existing gate logic to:

- Read commit message from `.git/COMMIT_EDITMSG` (instead of stdin JSON from Claude Code's hook contract).
- Read staged file list from `git diff --cached --name-only` (instead of from the Claude tool input).
- Emit human-readable block messages to stderr (instead of a JSON permission decision to stdout).

Same classifier (`check_commit_ready`), same misclassification fixes from BL-031 / BL-032 / NEW-7, same Phase-prereq validation from BL-026 — all reused as-is. Strict mode is a second invocation pathway into the same gate, not a parallel implementation.

This is the design's central maintenance property. Without it, the framework gate logic would have two implementations drifting apart — the failure mode the calibration sweep already proved is real.

### 8.4 Block message teaching pattern (W5/P1)

Every framework-gate block message has the same shape:

```
[FRAMEWORK GATE — strict mode]

Block reason: <verbatim from the gate that fired>

Why this rule exists:
  <one paragraph explaining the principle, not just the procedure>

To proceed:
  <the actual fix — the procedural part>

To bypass anyway (recorded in .claude/bypass-audit.json):
  git commit --no-verify ...

To downgrade enforcement permanently:
  scripts/reconfigure-project.sh --enforcement-level light
```

The "Why this rule exists" paragraph is sourced from a per-gate explanation table (small JSON or shell map keyed by gate name) so each gate's principle ships with the gate, not in a docs file that drifts.

### 8.5 `--no-verify` handling

Git's `--no-verify` skips all hooks, including `framework-gate.sh`. The framework's response: observe, do not block-the-block.

The `SessionStart`-triggered out-of-band detector (the same script that drives light mode) runs at every session start regardless of `enforcement_level`. On a strict project where a user used `--no-verify`, the detector spots the new commit on next session start (its SHA isn't in `claude-commits.jsonl`), recognizes the timestamp, and writes a `out_of_band_commit` row tagged `bypass=no-verify` (matching git's reflog if available).

So strict mode's full guarantee: **either the gate fires, or the bypass is recorded**. Never silent.

(Implementation note: this means `detect-out-of-band-commits.sh` should NOT self-gate on `enforcement_level=strict`; it should run on strict too, specifically to catch `--no-verify` events. The script's no-op condition is `enforcement_level=no` only.)

### 8.6 Hook removal on level downgrade

`reconfigure-project.sh --enforcement-level light` (or `no`) calls `install-filesystem-gates.sh --uninstall`, which removes only the marked block from `.git/hooks/pre-commit`. The marker delimiters make this surgically safe.

### 8.7 What strict mode does NOT do

- Does not install on the framework's own repo if `enforcement_level` is unset or `light`/`no` (W4).
- Does not run on amend, revert, cherry-pick, merge, or squash-merge — same filter `pre-commit-gate.sh` already uses (per BL-006 / build-loop-precommit-enforcement-design).
- Does not install via the `pre-commit` Python framework. Direct file install only.

## 9. Light-mode out-of-band detection

Light mode's promise: user-terminal commits are recorded but not blocked.

### 9.1 Substrate — the Claude-commit ledger

Two reliable signals could distinguish "Claude made this commit" from "the user did":

1. **Author timestamp inside a known Claude session window.** Brittle — the user might leave a session running idle while making terminal commits.
2. **Commit SHA recorded by Claude's gate when it fired.** Robust — the SHA is the artifact of intent.

We use **(2)**.

`.claude/claude-commits.jsonl` is appended to by `record-claude-commit.sh` (PostToolUse hook). One record per Claude-issued commit:

```json
{"sha": "abc123...", "timestamp": "2026-04-28T15:42:11Z", "session_id": "...", "gate": "passed"}
```

The recorder writes only on successful gate-pass. If Claude bypasses the gate (e.g., `git commit --no-verify` via Bash), the BL-029 Claude-side detector captures the bypass language; the SHA does NOT land in `claude-commits.jsonl`. Result: on next session start, the detector flags the commit as out-of-band — and the BL-029 row from the same commit cross-references it. Two perspectives on the same event.

### 9.2 The detector

`scripts/detect-out-of-band-commits.sh`, triggered by `SessionStart`:

1. Read `enforcement_level`. No-op exit if `no` (no recording promised). Run otherwise — light AND strict both rely on this for `--no-verify` capture.
2. Read `.claude/last-checked-commit.txt`.
3. `git log --format='%H %at %P %s' <last-checked>..HEAD`.
4. For each commit in the diff:
   - If commit message indicates derivative (Merge / Revert / cherry-pick of / squash-merge of) — skip.
   - If SHA is in `.claude/claude-commits.jsonl` — skip (in-band).
   - Otherwise — write a row to `bypass-audit.json` with `type: out_of_band_commit`, `actor: user_terminal_inferred`, full commit metadata, and `enforcement_level_at_event` set to the level at detection time.
5. Update `last-checked-commit.txt` to current HEAD.
6. If any rows written, print a SessionStart banner: `⚠ N user-terminal commit(s) detected since last session — recorded to .claude/bypass-audit.json.`

### 9.3 Init-time baseline

`init.sh` writes `last-checked-commit.txt = <HEAD at init>`. Commits that existed before the framework was installed are NOT flagged on first session start. This is critical for projects adopting the framework into an existing repo.

### 9.4 Edge cases

| Case | Behavior |
|---|---|
| Force push / rebase rewrites SHAs | Recorded Claude SHAs may be unreachable. Detector logs a one-line notice (`baseline rewritten — N recorded Claude commits no longer reachable`) and conservatively flags everything between baseline and HEAD as out-of-band. User can run `scripts/reconfigure-project.sh --reset-detection-baseline` to re-anchor. Never silent. |
| New branch checked out, baseline ref doesn't apply | Detector defaults to "everything since the merge-base with the previously-checked branch is unverified, suspicious." Conservative; better than missed events. |
| Detector itself fails (jq error, missing file) | Surface to stderr at session start. Audit log records a `detector_error` row. Silent failure of the audit layer is the highest-cost failure mode this design exists to prevent. |
| User commits during a Claude session, from their own terminal, in light mode | Flagged correctly. SHA not in `claude-commits.jsonl`; banner on next session start. This is the W4 case (framework dev). The recording is the whole point. |
| `git reset --hard HEAD~1` discards a commit | Detector won't see it. Acceptable — git itself doesn't track discarded work. Out of scope. |

### 9.5 What light mode does NOT detect

- Pushes (light is about commits, not remote state).
- Branch deletions, tag changes, config edits.
- Anything outside `git log <baseline>..HEAD`.

Scope creep here turns the detector into a generic git-audit tool, which is not BL-030. Light promises commit visibility, no more.

### 9.6 Light is observation, not deferred-blocking

Light mode does not, on next session start, refuse to proceed because last session's commits were out-of-band. The user picked light precisely to skip blocking. Light's contract: "I will see what you did, and I will not stop you next time either."

A future feature could add an "acknowledge-and-proceed" intermediate level. Out of scope for BL-030.

## 10. Reconfigure path

`scripts/reconfigure-project.sh --enforcement-level <no|light|strict> [--confirm-pitfalls]`.

### 10.1 Allowed transitions

| From | To | Allowed? | Notes |
|---|---|---|---|
| any | any | If `deployment=organizational` AND `poc_mode` ∈ `{"", sponsored_poc}` → **DENY**. Forced strict is non-overridable. |
| `strict` | `light` or `no` | Allowed for choosable modes. Show pitfall block (or require `--confirm-pitfalls` for non-interactive). Append audit row. Run `install-filesystem-gates.sh --uninstall`. |
| `light` | `strict` | Allowed. Run `install-filesystem-gates.sh`. Audit row. No pitfall block (upgrading is always defensible). |
| `light` | `no` | Allowed. Show "no" pitfall block. |
| `no` | `light` or `strict` | Allowed. No pitfall block. |
| `no` → `strict` | (also covered above) | Run filesystem-gates installer. Audit row. |

### 10.2 Cross-cutting effects

Every transition:

- Manifest write — `enforcement_level` updated.
- Audit row — `enforcement_level_set` with `details: {from, to, source: "reconfigure", reason: "<optional>"}`.
- Filesystem hook install/uninstall as needed. Idempotent.
- If transitioning to `light` or `strict`: `last-checked-commit.txt` initialized to HEAD if absent, left alone otherwise.

### 10.3 Org-mode protection

`reconfigure-project.sh --enforcement-level light` on an org+production project:

```
[FAIL] Enforcement level is forced 'strict' for this project
       (deployment=organizational, poc_mode=production).
       To change enforcement, downgrade the governance mode first via
       scripts/reconfigure-project.sh --poc-mode private_poc, then run
       this command. That downgrade itself is governed (see
       docs/governance-framework.md).
```

Mirrors `pre-commit-gate.sh:54` — the framework refuses to weaken enforcement on a privileged project without going through the documented governance path.

### 10.4 `--reset-detection-baseline`

`scripts/reconfigure-project.sh --reset-detection-baseline` writes current HEAD to `last-checked-commit.txt` and appends a `framework`/`detector_baseline_reset` audit row. For use after rebases, branch resets, or migration into the framework on existing repos with prior unrecorded history.

## 11. Testing

Standard TDD throughout, mirroring how BL-026 was built.

### 11.1 New test files

| File | Coverage |
|---|---|
| `tests/test-enforcement-level-init.sh` | Init flow for all three levels × choosable / non-choosable modes; pitfall blocks shown when expected; manifest persistence; init-time audit row; baseline initialized to HEAD. |
| `tests/test-enforcement-level-reconfigure.sh` | Allowed transitions; denied transitions on org modes; idempotent re-runs; audit rows on each transition; `--confirm-pitfalls` flag behavior; `--reset-detection-baseline`. |
| `tests/test-filesystem-gate-install.sh` | Idempotent install; marker delimiter handling; coexistence with mock gitleaks/Semgrep blocks; clean uninstall; preserves user-authored hook content outside the marker; survives reinstall. |
| `tests/test-out-of-band-detector.sh` | Baseline establishment at init; SHA matching against `claude-commits.jsonl`; derivative-commit filtering; rebase/force-push edge case; banner output; detector-error path; detector runs (and writes) on strict mode for `--no-verify` capture. |
| `tests/test-bypass-audit-schema.sh` | Schema validation across all four writer pathways; row appendability; jq queries from the docs reference work; backward-compatibility with rows from prior schema versions. |

### 11.2 Calibration replay

Replay calibration scenario S11 (`Reports/uat-2026-04-27-calibration/scenarios/`) under all three enforcement levels:

| Level | Expected behavior |
|---|---|
| strict | Claude proposes bypass → Claude-side BL-029 row written → user-terminal `--no-verify` blocked by filesystem gate (or, if Claude attempted, blocked by PreToolUse) → audit log captures both events with cross-reference. |
| light | Claude proposes bypass → Claude-side BL-029 row → user `--no-verify` lands → next SessionStart, `out_of_band_commit` row written → banner. |
| no | Claude proposes bypass → Claude-side BL-029 row STILL written → user-terminal action passes silently → no recording for terminal action. |

This proves the design's central invariant: BL-029 is universal; BL-030 layers on top without disturbing it.

### 11.3 Backward compatibility

- Pre-BL-030 projects (no `enforcement_level` in manifest) → default to strict, log a one-line migration notice on session start.
- Existing BL-026 / BL-027 / BL-031 / BL-032 / BL-033..37 regression tests still pass — BL-030 adds layers, does not modify existing gate behavior.

### 11.4 Test-gate counter impact

Feature, not bugfix — increments the test-gate counter. Sequencing matters: BL-029 ships first and is the first feature increment, so the counter at BL-030's land time depends on BL-029's land. Plan: BL-029 → counter 1/2; BL-030 → counter 2/2 → mandatory test gate triggered. Worth knowing for cross-feature scheduling.

## 12. Sequencing

- **BL-029 ships first** — Claude-side bypass-shape detector establishes the `bypass-audit.json` ledger and schema.
- **BL-030 ships second**, in dependency order:
  1. `enforcement-level.sh` library + manifest field + init UX (no behavior change yet — just records intent).
  2. `record-claude-commit.sh` PostToolUse hook + `claude-commits.jsonl` (always-on, foundation for both light and strict's `--no-verify` capture).
  3. `detect-out-of-band-commits.sh` + SessionStart wiring (light mode functional).
  4. `install-filesystem-gates.sh` + `framework-gate.sh` + `pre-commit-gate.sh --terminal-mode` flag (strict mode functional).
  5. `reconfigure-project.sh --enforcement-level` (transition path).

Each step is independently testable. Order can be parallelized after step 1 lands.

## 13. Open questions (deferred to implementation)

- **Schema file format.** JSONL vs JSON-array for `bypass-audit.json`. JSONL is append-safe under concurrent writers; JSON-array is more diffable. Decide during BL-029 implementation; BL-030 follows.
- **Banner placement on strict mode.** Section 7.4 says "no banner for strict." If a `detector_error` occurs even on strict, surface that — error suppression is never appropriate.
- **`record-claude-commit.sh` ordering.** PostToolUse hook needs to fire after the commit succeeds. Verify hook contract guarantees this; if not, attach to Stop instead.
- **Shell-quoting edge cases in pitfall blocks.** Long multi-line strings in `init.sh` should use heredocs to survive editor formatting. Verify `prompt_choice` and friends pass through correctly.
- **Test isolation.** `tests/test-filesystem-gate-install.sh` needs a real `.git/` directory; use `tests/test-helpers/init-phase2-verified.sh` (BL-025 helper) to bootstrap.

## 14. Related work

- **BL-026** (Phase 1→2 governance hole, fixed 2026-04-28). Phase-prereq validator that strict-mode `framework-gate.sh` will reuse via `process-checklist.sh --check-commit-ready`.
- **BL-029** (Bypass audit-log infrastructure). The Claude-side writer; BL-030 expands the schema and adds three more writers feeding the same file.
- **BL-031 / BL-032 / NEW-7** (Classifier / placeholder fixes, fixed 2026-04-28). Classifier corrections strict-mode reuses unchanged.
- **W4 / W5 / W6 / W7** (`docs/personal/owner-development-notes.md`). The four weaknesses this design addresses.
- **P1** (`owner-development-notes.md`). Teaching-mode-as-per-deployment-option. The pitfall-block UX in § 7.2 implements the P1 pattern at init.
- **Calibration sweep 2026-04-27** (`Reports/uat-2026-04-27-calibration/`). Surfaced NEW-5 (this spec) and produced the BL-029 spec by agent 5.

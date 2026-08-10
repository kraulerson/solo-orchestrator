# Audit Log Lifecycle

> Canonical reference for `.claude/bypass-audit.json` — the append-only ledger that records every framework-bypass event over a project's lifetime. If you are an operator looking at *what enforcement does and when*, start with the **User Guide's "What Is Enforced vs. What Is Guided"** section. This document is the deeper reference for *what each audit row means*, *who writes it*, and *how to read the log as a cold-pickup successor*.

## Why this file exists

The framework's central enforcement guarantee — described in `docs/user-guide.md` and `docs/builders-guide.md` — is **"you can route around the block, you cannot route around the audit."** Hooks can be bypassed. The CI pipeline catches some bypasses but runs only on push. The local append-only ledger is the durable record of every bypass that mattered: who tried it, when, what the framework decided, what the operator did with the proposal.

The W7 use case (successor handoff under the Solo Orchestrator governance framework — see `docs/governance-framework.md`) depends on this log being readable, unambiguous, and complete. A successor must be able to reconstruct, from the in-repo ledger alone, the operator's history of enforcement decisions on the project.

## File location and write guarantees

- **Path:** `.claude/bypass-audit.json` (tracked in git — must survive `git clone`).
- **Schema:** JSON array of rows. Each row has a fixed seven-field shape (see [Row schema](#row-schema)).
- **Writer:** every writer goes through `scripts/lib/bypass-audit.sh::bypass_audit_append`. Direct edits are not part of the contract.
- **Atomic append:** `bypass_audit_append` holds a portable `mkdir`-based advisory lock for the read-modify-write window, then writes via an adjacent `mktemp` so the final `mv` is a same-filesystem atomic rename. A SIGKILL during the write window leaves the previous valid ledger untouched.
- **Pending-row resolution:** `bypass_audit_close_pending` flips PENDING rows whose `type == "claude_bypass_proposal"` to `accepted/bypassed` or `declined/abandoned`. It is intentionally scoped to that row type — escalations are not collapsed into the same lifecycle.

The lock is portable (works on macOS where `flock` is absent by default). Multiple PostToolUse / Stop / SessionStart hooks running concurrently across sessions do not race.

## Row schema

Every row has exactly these seven fields:

| Field | Type | Notes |
| - | - | - |
| `timestamp` | string (ISO-8601 UTC) | When the event happened. |
| `session_id` | string \| null | The Claude session UUID when known. `null` for framework-initiated events (init, upgrade backfill, SessionStart detector). |
| `type` | enum (see [Row types](#row-types)) | What kind of event this row records. |
| `actor` | enum: `claude` \| `user_terminal` \| `user_terminal_inferred` \| `framework` | Who triggered the event. |
| `enforcement_level_at_event` | enum: `no` \| `light` \| `strict` \| `n/a` | The project's enforcement level when the row was written. `n/a` only for `enforcement_level_set` rows that record a transition. |
| `details` | object | Type-specific payload. See per-row sections below. |
| `user_response` | enum: `PENDING` \| `accepted` \| `declined` \| `n/a` | What the operator told `escalate-to-user` or the framework. `PENDING` only for `claude_bypass_proposal` rows that have not been resolved yet. |
| `final_outcome` | enum: `committed` \| `bypassed` \| `escalated` \| `abandoned` \| `recorded_only` \| `n/a` | Terminal disposition. `recorded_only` is the framework's "we noted this; no further action" outcome (used by the SessionStart detector and by `enforcement_level_set` rows). |

## Row types

Each type has a distinct lifecycle. Reading the log effectively means knowing the difference.

### `claude_bypass_proposal`

The Claude session attempted (or proposed) a framework bypass — most commonly `--no-verify`, `--force` push, or running a forbidden script directly. Written by the BL-029 bypass-detector hook (`scripts/hooks/bypass-detector.sh`).

- **Writer:** PostToolUse hook on Bash and Stop hook on session end.
- **Lifecycle:** starts as `user_response: "PENDING", final_outcome: "n/a"`. Resolves when the operator runs `scripts/escalate-to-user.sh --resolve --decision <accept|decline>` (or when an automated finalize runs at session end).
- **`actor`:** always `claude`.
- **`details`:** includes the matched pattern, the Bash command (redacted), and the assistant-message text fragment that triggered the detector.

### `terminal_commit_blocked`

A user-terminal `git commit` was blocked by `.git/hooks/framework-gate.sh` because it violated the Build Loop / Phase classifier. Strict-mode only.

- **Writer:** `framework-gate.sh` (installed by `scripts/install-filesystem-gates.sh` on strict projects); the emitted pre-commit fallback arms (BL-163) and commit-msg hook (BL-171) write the same row type via their shared `soif_ledger_blocked` helper (`scripts/lib/hook-templates.sh`).
- **Lifecycle:** terminal. `user_response: "n/a", final_outcome: "abandoned"`.
- **`actor`:** `user_terminal`.
- **`details`:** `{gate: <name>}` — the name of the gate that blocked (e.g. `process-checklist`, `pre-commit-gate`, `gitleaks`, `semgrep`, `bl125_tests`, `commitmsg_tdd`, `commitmsg_buildloop`).

### `terminal_commit_passed`

The mirror of the above — a user-terminal `git commit` was allowed through the gate.

**BL-161 (Dogfood-4 F-DF4-007): no longer emitted on routine commits.** Appending a `terminal_commit_passed` receipt on *every* clean terminal commit left the working tree perpetually one row dirty after the final commit of a session (committing that trailing row triggers another append — an infinite chase). As of BL-161 a clean strict-mode terminal commit records **no** row in the tracked ledger; the gate instead drops a non-tracked `.claude/last-gate-pass.txt` receipt (gitignored, mirroring `.claude/last-checked-commit.txt`) as proof it reached its PASS terminal, so the tracked ledger changes only on real events. `terminal_commit_passed` remains a **schema-valid legacy type** — historical ledgers keep any rows they already have, so readers must still recognize it.

- **Writer:** none (legacy; historically `framework-gate.sh`). The clean-pass proof now lives in the non-tracked `.claude/last-gate-pass.txt`.
- **Lifecycle:** terminal. `final_outcome: "committed"` (legacy rows only).
- **`actor`:** `user_terminal`.

### `out_of_band_commit`

A user-terminal commit landed in HEAD without going through `framework-gate.sh` — typically because it used `--no-verify`, or because the gate is not installed (light / no enforcement levels). The SessionStart detector finds it on the next session by comparing `git log <baseline>..HEAD` against the Claude-commit ledger and the derivative-commit patterns (merge / revert / cherry-pick / squash).

- **Writer:** `scripts/detect-out-of-band-commits.sh` (SessionStart hook).
- **Lifecycle:** terminal. `final_outcome: "recorded_only"`.
- **`actor`:** `user_terminal_inferred` (the detector cannot prove the human at the keyboard; the SHA was just not in any other ledger).
- **`details`:** commit SHA, subject, author timestamp.
- **Baseline file:** `.claude/last-checked-commit.txt` (gitignored as of PR #54 — operational state, not project content). The detector updates it to HEAD after each run.

### `enforcement_level_set`

The project's enforcement level was chosen or changed. Captures the audit trail for level transitions so a successor can answer "when did this project go from strict to light, and who confirmed the pitfalls?"

- **Writer:** `init.sh` (initial set, source `init`), `scripts/reconfigure-project.sh` (operator-initiated transition, source `reconfigure`), `scripts/upgrade-project.sh --backfill-only` (migration from a pre-BL-030 project, source `upgrade-backfill`).
- **Lifecycle:** terminal. `final_outcome: "recorded_only"`.
- **`actor`:** `framework`.
- **`details`:** `{level, confirmed_pitfalls, source}`. For transitions, the previous level is recoverable from the prior `enforcement_level_set` row.

### `escalation`

The framework gave the operator a choice and is recording the outcome. Distinct from `claude_bypass_proposal`: an escalation always pairs the Claude proposal with the framework's structured prompt (`scripts/escalate-to-user.sh` writes a pending-approval sentinel and emits options).

- **Writer:** `scripts/escalate-to-user.sh`.
- **Lifecycle:** starts as `user_response: "PENDING"`. Resolves to `accepted/escalated` or `declined/escalated` when the operator picks an option. `final_outcome` is always `escalated` (never collapsed into `bypassed` / `abandoned` — see the D2 fix in `bypass_audit_close_pending`).
- **`actor`:** `framework`.

### `detector_error`

The SessionStart detector or the bypass-audit library hit an unrecoverable error — corrupt ledger, missing HEAD, etc. Recorded so the gap in coverage is itself audited.

- **Writer:** `detect-out-of-band-commits.sh`, `bypass-detector.sh` (rare paths).
- **Lifecycle:** terminal. `final_outcome: "n/a"`.
- **`actor`:** `framework`.
- **`details`:** `{reason}`.

### `adoption_event`

A **brownfield adoption** did something to the operator's project that they are entitled to find again later. One type covers all of them, discriminated by `details.event` — [the brownfield design](designs/2026-08-02-brownfield-adoption-v1.md) §8.9 chose one member with a discriminator over five members, because adding a row type touches five surfaces and five types would be five times that work for no extra fidelity.

- **Writer:** the adoption driver (`--re-add`, and the collision archive during an adoption run).
- **Lifecycle:** terminal on write. `user_response: "n/a"`, `final_outcome: "recorded_only"`.
- **`actor`:** `framework`.
- **`enforcement_level_at_event`:** always `"n/a"`, deliberately. These are disclosure events, not gate outcomes; reading a tier for them would fork the `# BL-084-TIER-KEY` predicate into a sixth site that must be changed in sync with the other five.
- **`details`:** `{event, …}`, where `event` is one of:

| `details.event` | Recorded when | Extra `details` |
| - | - | - |
| `collision_archive` | The collision archive is written during an adoption | `archiveDir`, `entryCount`, `secretsScanStatus` |
| `collision_re_add` | The operator puts one of their archived files back | `path`, `archivedPath`, `warningShown` |
| `adoption` | The adoption itself completes | *no emitter yet* |
| `blocker_acceptance` | A certification blocker is accepted | *no emitter yet* |
| `secrets_disposition` | A finding is dispositioned `accepted risk` | *no emitter yet* |

The three "no emitter yet" rows are named because the vocabulary is closed and a reader of a ledger should be able to tell "this never happened" from "this happens and is not recorded". Today only the two collision events are written.

**A `collision_re_add` row is the operator overriding the framework, on purpose.** §7.3 permits re-adds — *"the framework's premise is opinionated enforcement, not confiscation"* — and asks only that the choice be legible to whoever reads the ledger next. A project with re-add rows is not a misconfigured project; it is one whose owner made a decision you can now go and read.

## Lifecycle per enforcement level

The user-guide table gives you the high-level matrix. The audit log's *content* is what concretely differs across levels:

| Level | Rows written | Notes |
| - | - | - |
| `strict` | `claude_bypass_proposal`, `terminal_commit_blocked`, `out_of_band_commit`, `enforcement_level_set`, `escalation`, `detector_error` | `framework-gate.sh` is installed; a user-terminal commit the gate BLOCKS produces a `terminal_commit_blocked` row, while a clean pass writes **no** ledger row — only a non-tracked `.claude/last-gate-pass.txt` receipt (BL-161), so the tracked ledger records real events only. `--no-verify` skips the hook but the next SessionStart writes `out_of_band_commit` for the same SHA. (`terminal_commit_passed` is a legacy type — no longer written, still recognized in historical ledgers.) |
| `light` | `claude_bypass_proposal`, `out_of_band_commit`, `enforcement_level_set`, `escalation`, `detector_error` | `framework-gate.sh` is NOT installed, so no `terminal_commit_blocked` / `terminal_commit_passed` rows. The SessionStart detector still runs and records every new SHA as `out_of_band_commit` (since none are blocked or passed by the gate). |
| `no` | `claude_bypass_proposal`, `enforcement_level_set`, `escalation` | Only Claude-side events are recorded. The SessionStart detector exits early. A successor reading the log can see the level transition that disabled the user-terminal audit. |

`enforcement_level_set` is written on every level transition regardless of source level — even `strict → no` records the transition before silencing the detector, so the timeline is intact.

## Reading the log as a cold-pickup successor

You inherited a project. You want to reconstruct the operator's enforcement history without talking to them. Start here.

```bash
# 1. Current enforcement level and history.
jq '[.[] | select(.type == "enforcement_level_set")] | sort_by(.timestamp) | .[] | {ts: .timestamp, level: .details.level, source: .details.source}' .claude/bypass-audit.json

# 2. Every user-terminal commit, in chronological order, with disposition.
jq '[.[] | select(.actor == "user_terminal" or .actor == "user_terminal_inferred")] | sort_by(.timestamp) | .[] | {ts: .timestamp, type: .type, sha: (.details.commit_sha // "n/a"), subject: (.details.commit_subject // "n/a")}' .claude/bypass-audit.json

# 3. All currently-PENDING bypass proposals (operator never resolved).
jq '[.[] | select(.user_response == "PENDING")] | .[] | {ts: .timestamp, type: .type, actor: .actor, details: .details}' .claude/bypass-audit.json

# 4. All escalations and their outcomes.
jq '[.[] | select(.type == "escalation")] | .[] | {ts: .timestamp, response: .user_response, outcome: .final_outcome, details: .details}' .claude/bypass-audit.json

# 5. Detector errors (gaps in coverage that should be investigated).
jq '[.[] | select(.type == "detector_error")] | .[] | {ts: .timestamp, level: .enforcement_level_at_event, reason: .details.reason}' .claude/bypass-audit.json

# 7. Brownfield adoption: what the archive took, and what the operator took back.
jq '[.[] | select(.type == "adoption_event")] | sort_by(.timestamp) | .[] | {ts: .timestamp, event: .details.event, path: (.details.path // .details.archiveDir // "n/a"), details: .details}' .claude/bypass-audit.json

# 6. Quick health summary — counts by type, by actor.
jq 'group_by(.type) | map({type: .[0].type, count: length})' .claude/bypass-audit.json
jq 'group_by(.actor) | map({actor: .[0].actor, count: length})' .claude/bypass-audit.json
```

If any of those queries surprise you — a level transition you cannot explain, a long-pending proposal, a stretch of `out_of_band_commit` rows without a paired `terminal_commit_blocked` — those are the first places to ask questions in the handoff conversation.

## Retention semantics

- **Append-only.** The library has no row-deletion API. A row, once written, is permanent. Operators editing the file by hand would break the W7 use case and should not.
- **Lives in the repo.** `.claude/bypass-audit.json` is tracked. `git clone` reproduces the full history.
- **No rotation.** The file grows monotonically. In practice it stays small (a busy multi-month strict-mode project tends to produce a few hundred rows).
- **No automatic redaction.** Commit subjects and Bash commands are captured as-is. If a `--no-verify` commit had a sensitive subject line, it lives in the log. Operators should treat `.claude/bypass-audit.json` with the same access discipline as the repo itself.

## Where to look for more

| You want… | Read |
| - | - |
| The enforcement-level matrix and operator commands | `docs/user-guide.md` — "What Is Enforced vs. What Is Guided" |
| The framework's overall enforcement model and Claude-vs-terminal split | `docs/builders-guide.md` — "Enforcement Model" |
| The W7 successor-handoff governance use case | `docs/governance-framework.md` — Section X "Insider Threat Acknowledgment" + Section XI portfolio governance |
| How the BL-029 bypass-detector recognizes proposals | `scripts/hooks/bypass-detector.sh` + `scripts/lib/bypass-patterns.sh` |
| How the SessionStart detector establishes the baseline | `scripts/detect-out-of-band-commits.sh` |
| How escalate-to-user pairs sentinel + audit row | `scripts/escalate-to-user.sh` |
| The atomic-append + close-pending implementations | `scripts/lib/bypass-audit.sh` |

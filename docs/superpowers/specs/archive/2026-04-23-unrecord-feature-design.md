# Unrecord-Feature Command + Rollback Documentation

**Date:** 2026-04-23
**Status:** Design approved, pending spec review
**Scope:** Framework-level change to solo-orchestrator
**Implements:** BL-008 from `solo-orchestrator-backlog.md`

## Problem

When `scripts/test-gate.sh --record-feature NAME` is called in error — for example, when a `feat(init):` commit implementing a scaffolding change was recorded as if it were an MVP Cutline feature — there is no sanctioned way to un-record it. Builders currently resort to direct `jq` edits of `.claude/build-progress.json`. This was observed on the lancache project Phase 2 audit on 2026-04-22, where the user is correcting via raw `jq` edit because no command exists for this operation.

Relatedly, `scripts/process-checklist.sh --reset uat_session` (and sibling `--reset <process>` commands) exist and are safe to use, but are not documented in `CLAUDE.md`'s Testing & Bug Workflow section. Builders who need to abort a started UAT session or Build Loop may not discover the existing tooling.

## Goals

- Provide a sanctioned `--unrecord-feature NAME` command as the inverse of `--record-feature NAME`.
- Document existing `--reset <process>` commands in the CLAUDE.md Testing & Bug Workflow section so builders discover them when they need recovery paths.
- Apply the same safety envelope as existing `--reset <process>` commands: interactive-terminal requirement, Y/N confirmation with state preview, audit-log entry.

## Non-Goals

- No `--abort-build-loop` command. Redundant with existing `--reset build_loop`.
- No git-history awareness. Command is a pure local-state operation; help text documents the limitation.
- No extraction of the shared safety pattern (interactive-terminal guard + Y/N confirm + audit-log append) into a reusable helper. Deferred; file as a new backlog item when a third caller appears and the extraction benefit becomes concrete.
- No `--all` or `--nth` flags for duplicate handling. First-match-wins is sufficient for the rare duplicate case; YAGNI until we see a real need.
- No top-level "Rollback / Abort" section in CLAUDE.md. Recovery documentation lives inside the Testing & Bug Workflow section where it's discoverable in context.
- No changes to `--record-feature` semantics.

## Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Scope | New `--unrecord-feature` in `test-gate.sh` + doc existing `--reset <process>` | Small, bounded, observed-gap fix |
| 2 | Counter semantics | Full inverse of `--record-feature` (remove from array, decrement both counters floored at 0, re-evaluate `testing_required`) | "Undo" mental model; avoids forcing users to know they also need `--reset-counter` |
| 3 | Name matching | Strict: error on not-found, first-match-wins on duplicates | Catches typos loudly; duplicates are theoretical and rare |
| 4 | Safety | Mirror `--reset <process>` exactly — interactive-only, Y/N with preview, audit log | Destructive state modification deserves the same safeguards |
| 5 | Git awareness | Pure local-state fix; help text documents limitation | Command is named for what it does; consistent with `--reset <process>` which also doesn't inspect git |
| 6 | Documentation | "Recovering from mistakes" subsection added to Testing & Bug Workflow in CLAUDE.md template | Discoverability in context > centralized reference |

## Architecture

One new subcommand in an existing script: `scripts/test-gate.sh --unrecord-feature NAME`, sibling of the existing `--record-feature NAME`. Inverse operation, same file, same jq-based state-transform pattern. No new scripts, no new schemas, no new directories.

**Shape:**

- State mutation lives in `_unrecord_feature_apply()` — pure logic, no I/O beyond file read/write. Unit-testable without tty tricks.
- Interactive wrapper `unrecord_feature()` handles the tty guard, Y/N prompt with preview, and audit-log append, then delegates state mutation to `_apply`.
- The wrapper/apply split serves both testability and potential future reuse (e.g., batch operations could call `_apply` directly).

**Documentation component:** new "Recovering from mistakes" subsection in `templates/generated/claude-md.tmpl`'s Testing & Bug Workflow section (currently lines 151–172). Covers:

- `--unrecord-feature NAME` (new)
- `--reset uat_session` (existing, undocumented in CLAUDE.md)
- `--reset build_loop` (existing, undocumented in CLAUDE.md)

All three flagged as interactive, audit-logged, and **local-state fixes only**.

## Components

### New files

- `tests/test-unrecord-feature.sh` — ~120 lines, 7 cases, self-contained assertion script.

### Modified files

| File | Change |
|------|--------|
| `scripts/test-gate.sh` | Add `_unrecord_feature_apply()` + `unrecord_feature()`; add argument parser case `--unrecord-feature)`; add dispatch case; add help-text line |
| `templates/generated/claude-md.tmpl` | Add "Recovering from mistakes" subsection (~5 lines) inside Testing & Bug Workflow |

### Function split inside `test-gate.sh`

**`_unrecord_feature_apply <name>`** — pure state transform:

- Reads `.claude/build-progress.json`.
- Validates `name` is present in `features_completed`; exits 1 with error + current-features diagnostic if not.
- Applies the jq transform (remove first-match, decrement both counters floored at 0, re-evaluate `testing_required`).
- Writes via `.tmp`-then-`mv` (mirrors existing atomic-write pattern in this file).
- Returns 0 on success.
- Does **not** check tty, does **not** prompt, does **not** log. Pure logic; testable with seeded fixtures.

**`unrecord_feature <name>`** — interactive wrapper:

- Validates `name` non-empty.
- Enforces `[ -t 0 ]` interactive-terminal guard (exits 1 with remediation hint if not interactive).
- Validates `.claude/build-progress.json` exists (exits 1 if not).
- Reads current state for the preview.
- Prints preview (current state → projected state — see Data Flow below).
- Prompts `[y/N]`; on decline → `print_info "Unrecord cancelled."`, exit 0.
- Calls `_unrecord_feature_apply "$name"`.
- Appends `[UNRECORD] feature '$name' unrecorded at $timestamp by $(whoami)` to `.claude/process-audit.log`.
- Prints success confirmation.

### Argument parser addition

One new case in the existing `while [ $# -gt 0 ]` loop:

```
--unrecord-feature)   ACTION="unrecord-feature"; FEATURE_NAME="$2"; shift 2 ;;
```

### Dispatch addition

One new case in the existing `case "$ACTION"` block:

```
unrecord-feature)   unrecord_feature "$FEATURE_NAME" ;;
```

### Help-text addition

One new line in the `--help` output, after the existing `--record-feature` line:

```
  --unrecord-feature N  Un-record a feature recorded in error (interactive; inverse of --record-feature)
```

### CLAUDE.md template addition

Inserted at the end of the bulleted list in the Testing & Bug Workflow section (after the existing `**After each feature:**` and `**Severity rules:**` bullets):

```markdown
- **Recovering from mistakes:**
  - Un-record a wrongly-recorded feature: `scripts/test-gate.sh --unrecord-feature "name"` (interactive; fully inverses the `--record-feature` counters)
  - Abort a started UAT session: `scripts/process-checklist.sh --reset uat_session` (interactive)
  - Abort a started Build Loop: `scripts/process-checklist.sh --reset build_loop` (interactive)
  - All three require terminal access and Y/N confirmation; each writes an audit entry to `.claude/process-audit.log`. These are **local-state fixes only** — if the state was committed, amend or revert the commit separately.
```

## Data Flow

Linear; one command invocation, one terminal session:

1. **Parse args.** `FEATURE_NAME=$2`, `ACTION="unrecord-feature"`.
2. **Validate preconditions** (in this order):
   - `FEATURE_NAME` non-empty → else print usage, exit 1.
   - `[ -t 0 ]` interactive → else print remediation, exit 1.
   - `.claude/build-progress.json` exists → else error "nothing to unrecord", exit 1.
   - `FEATURE_NAME` in `features_completed` → else error "'NAME' not found", list currently-recorded features, exit 1.
3. **Compute preview.** Read current state; compute projected state (array with first `NAME` removed, counters floored at 0, new `testing_required`).
4. **Display preview + Y/N.** Format specified in Components §preview. If decline → "Unrecord cancelled", exit 0.
5. **Apply transform via single jq invocation.** Atomic via `.tmp` + `mv`.
6. **Append audit-log entry.** `>>` to `.claude/process-audit.log`.
7. **Print success confirmation.** `print_ok "Feature 'NAME' unrecorded"`.
8. Exit 0.

**Preview format** (shown at the Y/N prompt):

```
Unrecord feature 'NAME'?

Current state:
  features_completed: ["foo", "bar", "NAME"]
  features_since_last_test: 3 / 2 (testing_required: true)
  features_since_last_health_check: 5

After unrecord:
  features_completed: ["foo", "bar"]
  features_since_last_test: 2 / 2 (testing_required: true)
  features_since_last_health_check: 4

Proceed? [y/N]:
```

**Concurrency:** single-user project, no concurrent callers. Read-then-modify-then-write is safe, matches the existing `--record-feature` pattern.

**Idempotency:** second invocation with the same name hits "not found" error and exits 1 without side effects.

**Transaction boundary:** steps 5 and 6 are separate operations. State transform succeeds and audit-log append fails ≈ known limitation; matches `reset_process()` behavior. Acceptable because audit-log failure is rare and recoverable.

## Error Handling

Five handled error cases, each with specific message and exit code:

| # | Condition | Response | Exit |
|---|-----------|----------|------|
| 1 | Missing NAME argument | `print_fail "Usage: --unrecord-feature NAME (feature name required)"` | 1 |
| 2 | Non-interactive invocation | Mirror `reset_process()` exactly: "Unrecord requires interactive authorization" + remediation command on stderr | 1 |
| 3 | `build-progress.json` missing | "Nothing to unrecord: .claude/build-progress.json does not exist. No features have been recorded in this project yet." | 1 |
| 4 | Feature not in array | "Feature '$name' not found in features_completed." — then print `Currently recorded features:` with a bulleted list (or `(none)` if array is empty) | 1 |
| 5 | User declines at Y/N | `print_info "Unrecord cancelled."` | 0 (graceful cancel, not a failure) |

**Audit-log-write failure:** known limitation, not handled. `echo >> file` is best-effort and matches existing `reset_process()` behavior. If this becomes an observed problem, it's cross-cutting and belongs with BL-009's helper extraction.

**jq transform failure:** natural exit 1 via `set -e`. Unlikely in practice; indicates filesystem or JSON-parse issue.

## Testing

**New file:** `tests/test-unrecord-feature.sh` — ~120 lines, 7 cases, self-contained.

**Testability approach:** the wrapper/apply function split enables unit testing without tty tricks. Tests target `_unrecord_feature_apply` directly, skipping the interactive guard that would reject the test runner itself.

**Test cases:**

| # | Case | Setup | Assertion |
|---|------|-------|-----------|
| 1 | Happy path: single feature | `features_completed: ["foo"]`, counters at 1 | Array empty, counters at 0, `testing_required: false` |
| 2 | Duplicates → first match removed | `features_completed: ["foo", "bar", "foo"]` | Array becomes `["bar", "foo"]` |
| 3 | Counter floor at 0 | `features_completed: ["foo"]`, counters at 0 | Array empty, counters still 0 (no underflow) |
| 4 | `testing_required` flips false | counters at 2, interval 2, `testing_required: true` | Counter 1, `testing_required: false` |
| 5 | `testing_required` stays true | counters at 3, interval 2, `testing_required: true` | Counter 2, `testing_required: true` |
| 6 | Feature not found | `features_completed: ["foo"]`, call with `"bar"` | Exit 1, stderr contains `"not found"` and `"foo"` |
| 7 | Missing build-progress.json | No file | Exit 1, stderr contains `"does not exist"` |

**Not tested (with rationale):**

- Interactive-guard rejection — tests the tty check, not our logic; low value.
- Y/N prompt behavior — tests bash's `read`, not our logic.
- Audit-log append — write-then-read round-trip; mechanical filesystem test.
- Audit-log failure handling — matches the "known limitation" decision above.

**Test harness:** each case is a self-contained bash function that creates a temp dir, seeds `.claude/build-progress.json`, sources `test-gate.sh`, invokes `_unrecord_feature_apply`, asserts post-state via `jq`, and cleans up. Assertion helpers inlined (zero-dependency, matches existing `tests/*.sh` convention).

**Integration into project test suites:** `tests/test-unrecord-feature.sh` runs standalone via `bash tests/test-unrecord-feature.sh`. No new harness infrastructure needed. Reference in relevant CI templates is optional follow-up; not blocking.

## Open Questions

None. All decisions captured in the Decisions table.

## Related

- Backlog: `solo-orchestrator-backlog.md` BL-008 (this spec's trigger)
- Related backlog items (not in scope): BL-006 (pre-commit Build Loop enforcement), BL-007 (MVP Cutline Build Loop rule). A future backlog item extracting the shared interactive-auth pattern would be prompted by this spec's non-extraction decision, once a third caller justifies the helper.
- Surfaced during: lancache project Phase 2 audit, 2026-04-22
- Existing precedent for safety pattern: `scripts/process-checklist.sh:reset_process()` lines 885–945
- Existing command for visual symmetry: `scripts/test-gate.sh:record_feature()` lines 91–117

# BL-015: Pending-Approval Sentinel Reader (Solo side) — Design

**Spec date:** 2026-04-25
**Backlog item:** BL-015 (High / Debt — to be logged)
**Upstream dependency:** CDF 4.2.3 (`f55c8bc` on `main` of `kraulerson/claude-dev-framework`) — already shipped and verified.
**Doctrinal parent:** Lancache 2026-04-24 incident — agent rationalized "Complete these, then finish" as implicit approval for a recommended A1/A2/A3 option, committed without explicit pick. Root cause: stop-hook pressure loop with no mechanical block on the commit side.

## 1. Problem

CDF 4.2.3 introduced `.claude/pending-approval.json` as a sentinel file the agent writes when offering structured options to the user. The CDF stop-hook honors the sentinel (exits silently, breaking the "Complete these, then finish" pressure loop). Solo's pre-commit-gate currently does NOT honor the sentinel — meaning even with the stop-hook silenced, an agent under rationalization pressure can still commit unilaterally.

BL-015 closes the symmetric gap: when the sentinel exists, Solo's pre-commit-gate denies `git commit` and `gh pr create` with a rich error message reflecting the pending question back to the agent. Together with the CDF stop-hook fix, the sentinel becomes an authoritative single-source-of-truth signal that "user is deciding, do not advance."

## 2. Scope

**In scope:**

1. New helper script `scripts/pending-approval.sh` (5 subcommands: `--offer`, `--resolve`, `--clear`, `--status`, `--validate`).
2. New `pa_check()` block in `scripts/pre-commit-gate.sh` between `--no-verify` (security) and `--amend` (workflow).
3. New bullet in `templates/generated/claude-md.tmpl` Construction Rules section.
4. New `### Structured Decision Points: The Pending-Approval Sentinel` subsection in `docs/builders-guide.md` between "MVP Cutline Work Requires the Build Loop" and "The Build Loop."
5. One-line changelog note in `scripts/upgrade-project.sh`.
6. Two test files: `tests/test-pending-approval.sh` (new), `tests/edge-cases-scripts.sh` (extended with E40–E47).

**Out of scope** (logged elsewhere or explicitly punted):
- Changes to CDF (its 4.2.3 release covers the producer side completely).
- CI-side sentinel linting (BL-013 territory if ever).
- Retroactive scanning for past drift while pending-approval was active (BL-012 territory).
- Staleness handling beyond manual `rm` recovery (matches CDF's punt — Q7 A).
- Cross-platform CI matrix.

## 3. Locked parameters

Settled during the brainstorming dialogue on 2026-04-24 / 2026-04-25:

| Parameter | Decision | Source |
|---|---|---|
| Rollout breadth | Full: reader + helper + template + docs | Q1 — C |
| Gated operations | Both `git commit` AND `gh pr create` | Q2 — A |
| Helper API surface | Five subcommands (`--offer`, `--resolve`, `--clear`, `--status`, `--validate`) | Q3 — C |
| Double-`--offer` semantics | Refuse (require explicit `--resolve` or `--clear` first) | Q3b |
| Position in `pre-commit-gate.sh` | After security gates, before `--amend` (between line 72 and line 74 in shipped file) | Q4 — B |
| Error-message shape | Rich (parse JSON, reflect question/options/recommendation; fall back to minimal on malformed) | Q5 — B |
| Documentation placement | `claude-md.tmpl` bullet + `builders-guide.md` paragraph (matches BL-006 pattern) | Q6 — A |
| Staleness handling | Match CDF (punt; document `rm` recovery; `--clear` helper subcommand provides a sanctioned alternative) | Q7 — A |
| Implementation order | Helper-first, reader second | Approach 1 |

## 4. Architecture

Four units. Single source of truth (`.claude/pending-approval.json`). CDF 4.2.3 owns the schema; Solo conforms.

```
┌─────────────────────────────────────────────────────────────────────┐
│ Claude agent (in a Solo project, Phase 2+)                          │
│                                                                     │
│ Offers A/B/C options to user                                        │
│   │                                                                 │
│   ▼                                                                 │
│ scripts/pending-approval.sh --offer "Q" --options ... --rec ...    │
└─────────────────────────────────────────────────────────────────────┘
        │ writes atomically (tempfile + mv)
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│ .claude/pending-approval.json  (the sentinel — CDF 4.2.3 schema)    │
│ {                                                                   │
│   "question": "commit structure",                                   │
│   "options": ["A1: single commit", "A2: two commits", ...],         │
│   "recommendation": "A1",                                           │
│   "offered_at": "2026-04-24T20:15:00Z"                              │
│ }                                                                   │
└─────────────────────────────────────────────────────────────────────┘
        │                                  │
        │ read by                          │ read by
        ▼                                  ▼
┌────────────────────────────┐  ┌─────────────────────────────────────┐
│ CDF stop-checklist.sh      │  │ Solo scripts/pre-commit-gate.sh     │
│ (already shipped 4.2.3)    │  │                                     │
│                            │  │ NEW pa_check() block at position 6  │
│ exists → exit 0 silently   │  │ (after --no-verify, before --amend) │
│ (no block JSON, no stderr) │  │                                     │
│                            │  │ exists → deny git commit / gh pr    │
│ No pressure loop.          │  │ create with rich reason reflecting  │
│                            │  │ the pending question.               │
└────────────────────────────┘  └─────────────────────────────────────┘
        │ (eventually)                      │ (immediately)
        └──────────────┬────────────────────┘
                       │
                       ▼
             Sentinel deleted by agent when user picks:
             scripts/pending-approval.sh --resolve  (user answered)
             scripts/pending-approval.sh --clear    (agent abort)
```

**Unit boundaries.**

| Unit | Responsibility | Knows about | Doesn't know about |
|---|---|---|---|
| `scripts/pending-approval.sh` | Sentinel lifecycle (offer/resolve/clear/status/validate). Atomic write, schema validation at write time. | JSON schema, file atomicity, subcommand semantics. | Hook consumption, enforcement policy. |
| `scripts/pre-commit-gate.sh` (new `pa_check()`) | Gate `git commit` + `gh pr create` when sentinel present. Produce rich deny reason. | File existence, JSON parse-for-display, hook JSON output shape. | Doesn't write the sentinel; doesn't care about helper internals. |
| `templates/generated/claude-md.tmpl` | Deliver the "use the sentinel when offering structured options" instruction to every Solo project. | Agent-facing instruction; command shape. | Implementation. |
| `docs/builders-guide.md` | Rationale, lancache incident, lifecycle explanation. | Why the mechanism exists; when to use it. | Implementation. |

**Key principle: CDF is the producer of the contract, Solo is a consumer.** The sentinel file's schema, path, and "existence means pending" semantics are owned by CDF 4.2.3. Solo's helper and reader both conform. If CDF ever revises the contract, Solo follows in a downstream PR.

## 5. Sentinel schema (reaffirmed from CDF 4.2.3)

Solo does NOT redefine the schema — it conforms.

**Path:** `${PROJECT_ROOT}/.claude/pending-approval.json`

**Fields:**

| Field | Type | Required | Purpose |
|---|---|---|---|
| `question` | string (non-empty) | yes | Short label of what's being asked. |
| `options` | array of strings (≥2) | yes | Agent's offered choices, each with a leading identifier (e.g., `"A1: single commit"`). |
| `recommendation` | string | yes | Matches the leading identifier of one option. If no preference, use `"?"`. |
| `offered_at` | string (ISO-8601 UTC, `Z` suffix) | yes | Timestamp the sentinel was written. Informational only — not used for staleness. |

**Semantics:**

| Sentinel state | Stop-hook behavior | Pre-commit-gate behavior |
|---|---|---|
| Absent | Normal operation | Normal operation |
| Present + valid JSON | Exit 0 silently | Deny `git commit` / `gh pr create` with rich reason |
| Present + malformed/empty | Exit 0 silently | Deny with fallback ("malformed, treated as in-flight") reason |

**Existence alone suffices** — both consumers treat file presence as authoritative. Field values decorate error messages (Solo) or are ignored entirely (CDF). Neither consumer interprets fields to decide whether to block.

**No new fields added by Solo.** Adding `blocks_commit`, `ttl_seconds`, `approver_required`, etc., requires a CDF PR first. Solo's helper writes exactly the four required fields and nothing else.

**Example valid sentinel:**

```json
{
  "question": "commit structure",
  "options": [
    "A1: single commit",
    "A2: two commits",
    "A3: three commits"
  ],
  "recommendation": "A1",
  "offered_at": "2026-04-24T20:15:00Z"
}
```

## 6. Helper script: `scripts/pending-approval.sh`

**Usage:**

```
scripts/pending-approval.sh --offer "QUESTION" \
                            --options "A1: single" "A2: two" "A3: three" \
                            --recommendation "A1"

scripts/pending-approval.sh --resolve
scripts/pending-approval.sh --clear
scripts/pending-approval.sh --status
scripts/pending-approval.sh --validate [PATH]

scripts/pending-approval.sh --help
```

**Subcommand contract:**

| Subcommand | Action | Exit | Stdout | Stderr |
|---|---|---|---|---|
| `--offer` | Validate args, write sentinel atomically (tempfile + `mv`). Refuse if sentinel already exists. | 0 on write, 1 on refuse/validation-fail | `[OK] Pending approval offered: <QUESTION>` | Empty on OK; remediation on fail |
| `--resolve` | `rm -f .claude/pending-approval.json`. Idempotent. | 0 always | `[OK] Pending approval resolved.` (or `[OK] No pending approval.`) | Empty |
| `--clear` | Same action as `--resolve` — semantic alias for "agent aborting the question" vs. "user picked." Same exit code, different OK message. | 0 always | `[OK] Pending approval cleared (abort).` (or `[OK] No pending approval.`) | Empty |
| `--status` | Read sentinel, parse JSON, print formatted summary. Absent → "no pending approval." Malformed → "malformed sentinel present at PATH." | 0 always | Formatted summary or status line | Empty |
| `--validate [PATH]` | Lint-only. Validate JSON at PATH (default `.claude/pending-approval.json`). No writes. PATH absent → exit 0 (nothing to validate). | 0 on valid-or-absent, 1 on malformed-present | `[OK] Valid sentinel.` or `[OK] No sentinel to validate.` | Schema errors on fail |
| `--help` / `-h` | Print usage. | 0 | Usage text | Empty |

**`--offer` argument validation:**

- `--question` non-empty (else exit 1).
- `--options` consumes all positional arguments until the next flag or end-of-args. Manual parser; bash `getopts` doesn't support this directly.
- Minimum 2 options (else exit 1).
- `--recommendation` required, must match the leading identifier of one option (the substring before the first `:`, or the whole string if no `:`). Else exit 1.

**Atomic write pattern:**

```bash
TMPFILE=$(mktemp "$PROJECT_ROOT/.claude/pending-approval.XXXXXX.tmp")
cat > "$TMPFILE" <<JSON
{
  "question": "...",
  "options": [...],
  "recommendation": "...",
  "offered_at": "..."
}
JSON
mv "$TMPFILE" "$PROJECT_ROOT/.claude/pending-approval.json"
```

Tempfile + `mv` guarantees neither CDF's stop-hook nor Solo's pre-commit-gate observes a half-written file. Non-atomic (`> file`) would create a race.

**Timestamp format:** `date -u -Iseconds` (Linux GNU `date`), with macOS BSD `date` fallback (`date -u +"%Y-%m-%dT%H:%M:%SZ"`). Detect platform via `uname -s` and dispatch.

**Project-root detection:** Walk up from `$PWD` looking for `.claude/` directory (same pattern as `scripts/upgrade-project.sh::find_project_root`). If not found, exit 1 with "not in a Solo project — no .claude/ directory found in $PWD or any parent" — prevents accidental writes to home dir.

**Refuse-on-double-offer error message:**

```
[FAIL] A pending approval already exists: "commit structure" (offered 2026-04-24T20:15:00Z).

Resolve or clear the existing one first:
  scripts/pending-approval.sh --resolve   # user picked
  scripts/pending-approval.sh --clear     # abort the question
```

**Schema validation at write time:** the helper validates its own inputs before writing, so no invalid sentinel ever reaches disk via the sanctioned path. `--validate` exists for the edge case where something else (manual `jq`, human `vim`) produced a file.

## 7. Reader integration: `pa_check()` in `pre-commit-gate.sh`

**Physical insertion point:** Immediately after the `--no-verify` block ends (after line 72's closing `fi`), before the `--amend` warn block (line 74). Function defined inline; invoked as `pa_check` immediately following its definition.

**Function body (spec-level):**

```bash
# --- BL-015: pending-approval sentinel reader ---
# Blocks git commit and gh pr create when .claude/pending-approval.json exists.
# Runs after security gates (SOIF_*, no-remote, --no-verify) but before
# workflow gates (--amend, bl006_check, --check-commit-ready) so pending
# approval preempts workflow concerns without hiding security violations.

pa_check() {
  # Only applies to git commit or gh pr create. Other commands fall through.
  local is_commit=false is_pr=false
  echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && is_commit=true
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bcreate\b' && is_pr=true
  [ "$is_commit" = false ] && [ "$is_pr" = false ] && return 0

  # Check sentinel presence.
  local sentinel=".claude/pending-approval.json"
  [ -f "$sentinel" ] || return 0

  # Build deny reason. Try rich (parse JSON); fall back on malformed.
  local action_label="commit"
  [ "$is_pr" = true ] && action_label="PR creation"

  local reason
  if reason=$(build_pa_rich_reason "$sentinel" "$action_label" 2>/dev/null); then
    :
  else
    reason=$(build_pa_malformed_reason "$sentinel" "$action_label")
  fi

  # Emit deny JSON (same JSON-encoding pipeline as existing blocks).
  local escaped
  escaped=$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$escaped"}}
HOOKEOF
  exit 0
}

build_pa_rich_reason() {
  local sentinel="$1" action_label="$2"
  local question options recommendation offered_at
  question=$(jq -er '.question' "$sentinel") || return 1
  options=$(jq -er '.options | map("  " + .) | join("\n")' "$sentinel") || return 1
  recommendation=$(jq -er '.recommendation' "$sentinel") || return 1
  offered_at=$(jq -er '.offered_at' "$sentinel") || return 1

  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

Pending question: "$question"
Options:
$options
Recommendation: $recommendation
Offered at: $offered_at

Wait for the user to pick one, then:
  scripts/pending-approval.sh --resolve
EOF
}

build_pa_malformed_reason() {
  local sentinel="$1" action_label="$2"
  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

The sentinel file $sentinel exists but is malformed.
Treated as "in flight" per the CDF 4.2.3 contract.

If this is a stale file from a crashed session, remove it manually:
  rm $sentinel
EOF
}

pa_check
# --- end BL-015 block ---
```

**Interaction with existing blocks:**

| Existing block | Position relative to `pa_check` | Reason |
|---|---|---|
| `SOIF_FORCE_STEP` (line 27) | Before | Security; absolute, never preemptable. |
| `SOIF_PHASE_GATES` (line 35) | Before | Security; same reasoning. |
| `process-checklist --reset` (line 43) | Before | Security; same reasoning. |
| No-remote check (line 50–64) | Before | Infrastructure; commits without remote are broken regardless of sentinel. |
| `--no-verify` (line 67) | Before | Security; the user-set boundary should never be bypassed by a pending sentinel. |
| `--amend` warn (line 74) | **After** | Workflow; amend during pending-approval should be a hard block, not a warn. `pa_check` upgrades the warn to a deny for the duration of pending. |
| `bl006_check` (line 82+) | **After** | Workflow; if the user is picking between Build-Loop options, bl006_check's "no Build Loop active" error would be misleading. |
| `--force push` (line 159) | After | Targets `git push`, not commit; `pa_check` doesn't intercept push. Independent. |
| `gh repo create --push` (line 167) | After | Targets `gh repo create`, not commit/PR-create; independent. |
| `--check-commit-ready` (line 175+) | After | Workflow; pending-approval preempts. |
| Build Loop / UAT PR gates | After | Workflow; pending-approval preempts. |

**Sentinel absent:** `pa_check` returns 0 silently. No output. Falls through to `--amend`.

## 8. Error messages (final form)

**Rich reason for `git commit`:**

```
pre-commit gate: commit blocked — pending user decision.

Pending question: "commit structure"
Options:
  A1: single commit
  A2: two commits
  A3: three commits
Recommendation: A1
Offered at: 2026-04-24T20:15:00Z

Wait for the user to pick one, then:
  scripts/pending-approval.sh --resolve
```

**Rich reason for `gh pr create`:** same shape, "commit blocked" → "PR creation blocked" in line 1.

**Malformed fallback for either:**

```
pre-commit gate: commit blocked — pending user decision.

The sentinel file .claude/pending-approval.json exists but is malformed.
Treated as "in flight" per the CDF 4.2.3 contract.

If this is a stale file from a crashed session, remove it manually:
  rm .claude/pending-approval.json
```

After the `tr '\n' ' ' | sed 's/"/\\"/g'` JSON-encoding pipeline, both messages render as a single-line `permissionDecisionReason` to Claude. Newlines and quotes survive the encoding and display reasonably in Claude's tool-result UI.

## 9. Template + docs delivery

### `templates/generated/claude-md.tmpl` — agent-facing bullet

Inserted in the Construction Rules (Phase 2) section as a sibling to the existing "MVP Cutline work is always Build Loop work" bullet:

```markdown
- **Structured decision points use the pending-approval sentinel.** When offering structured options (A/B/C / multiple-choice / "pick one" questions) on a blocking decision — commit structure, branch strategy, file layout, scope cuts — first write the sentinel: `scripts/pending-approval.sh --offer "QUESTION" --options "A1: foo" "A2: bar" --recommendation A1`. Delete it when the user picks: `scripts/pending-approval.sh --resolve`. The CDF stop-hook and Solo's pre-commit gate both honor the sentinel — without it, you can drift into committing or stopping prematurely while the user is still deciding.
```

### `docs/builders-guide.md` — orchestrator-facing rationale

New `### Structured Decision Points: The Pending-Approval Sentinel` subsection inserted between the existing "MVP Cutline Work Requires the Build Loop" subsection and "The Build Loop" header:

```markdown
### Structured Decision Points: The Pending-Approval Sentinel

During the Build Loop you occasionally face blocking decisions that need orchestrator input: commit structure (single vs. split), merge strategy, scope cuts. When those decisions are offered as structured options (A/B/C), write `.claude/pending-approval.json` via `scripts/pending-approval.sh --offer …` to signal that the agent is deliberately holding. Delete it via `--resolve` once the orchestrator picks.

**Why this matters.** Observed on lancache (2026-04-24): an agent offered commit-structure options (A1/A2/A3), received an ambiguous response ("Complete these, then finish."), and rationalized the response as implicit approval for the recommended option — a unilateral commit without an explicit pick. Root cause: the stop-hook kept firing "Complete these, then finish" every turn, amplifying pressure until the agent broke its own rule. The fix is mechanical: a sentinel file that both enforcement points (CDF stop-hook, Solo pre-commit-gate) honor as "user is deciding — do not advance."

**What the sentinel does.** When `.claude/pending-approval.json` exists:
- The CDF stop-hook (4.2.3+) exits silently — no block JSON, no stderr advisory, no pressure loop.
- Solo's `scripts/pre-commit-gate.sh` blocks `git commit` and `gh pr create` — no irreversible action slips through.

Both enforcement points defer to the same file. The sentinel is the single source of truth for "user is deciding."

**Lifecycle.**
1. Agent offers structured options to the user.
2. Agent writes the sentinel: `scripts/pending-approval.sh --offer "…" --options "…" --recommendation "…"`. Writes are atomic (tempfile + `mv`) so consumers never see a half-written file.
3. File exists while the user deliberates. Both enforcement points hold.
4. User picks. Agent deletes the sentinel: `scripts/pending-approval.sh --resolve` (user answered) or `--clear` (agent aborting the question). Both commands behave identically — the distinction is semantic, for audit readability.
5. Enforcement points resume normal behavior.

**Sub-command reference.** `scripts/pending-approval.sh --help` lists the full API: `--offer`, `--resolve`, `--clear`, `--status`, `--validate`. `--status` is useful after session recovery ("is there a live sentinel from before?"). `--validate` lints a sentinel path (default `.claude/pending-approval.json`) for CI or debugging use.

**Double-offer is refused.** If a sentinel already exists, `--offer` refuses with an error listing the existing question. Resolve or clear first. This prevents memory-holing an earlier question that the user might still be deciding on.

**Staleness.** Orphaned sentinels (from a crashed agent session) are not auto-cleaned. Run `scripts/pending-approval.sh --clear` or `rm .claude/pending-approval.json` if one is stuck. This matches the CDF stop-hook's behavior; both consumers share the same recovery path.

**When NOT to use the sentinel.** Simple confirm-y/n questions (e.g., "Proceed with the refactor?") don't need the sentinel — just ask. The sentinel is for *structured* decisions where a specific pick is required and an accidental advance would be harmful. Overuse dilutes its signal; under-use causes incidents like lancache.

**Upgrading existing projects.** `scripts/upgrade-project.sh` copies the new `scripts/pending-approval.sh` and the updated `scripts/pre-commit-gate.sh` into existing projects, so the **enforcement** (reader + helper) goes live immediately on upgrade. However, the new `claude-md.tmpl` bullet does NOT replace existing populated `CLAUDE.md` files — those keep their original content. So existing-project agents won't *know* to use the sentinel until either (a) the orchestrator manually adds the bullet to their `CLAUDE.md`, or (b) the project is re-initialized.

This asymmetry is intentional and acceptable: even without the instruction, the enforcement still prevents the livelock (stop-hook side) and the commit slippage (reader side) — those failure modes are caught regardless of agent awareness. The full benefit (agents proactively writing sentinels when offering options) accrues on new or re-initialized projects.

If you maintain an existing project that should fully adopt the mechanism, copy the bullet from `templates/generated/claude-md.tmpl` (Construction Rules section) into your project's `CLAUDE.md`.
```

### `scripts/upgrade-project.sh` — header changelog note

Append to the existing changelog block:

```
# - BL-015 (2026-04-25): pre-commit gate now blocks commits and PR creation
#   when .claude/pending-approval.json exists. New helper script
#   scripts/pending-approval.sh. CLAUDE.md template gets new bullet under
#   Construction Rules. Upgrade picks up the new scripts and template.
```

## 10. Testing plan

### Unit tests: `tests/test-pending-approval.sh` (new file)

Targets `scripts/pending-approval.sh` in isolation. Setup pattern: per-test tempdir with `.claude/` directory, run helper subcommands, assert exit codes and file state.

| # | Test | Expected |
|---|---|---|
| P1 | `--offer "Q" --options "A1: foo" "A2: bar" --recommendation A1` in fresh project | exit 0, sentinel exists with valid schema, no `.tmp` left behind |
| P2 | `--offer ...` when sentinel already exists | exit 1, stderr lists existing question, sentinel unchanged |
| P3 | `--offer` with empty `--question` | exit 1, validation error |
| P4 | `--offer` with single option | exit 1, "minimum 2 options" error |
| P5 | `--offer` with `--recommendation` not matching any option's leading identifier | exit 1, validation error |
| P6 | `--offer` outside a Solo project (no `.claude/`) | exit 1, "not in a project" error |
| P7 | `--resolve` when sentinel exists | exit 0, sentinel deleted, "[OK] Pending approval resolved." on stdout |
| P8 | `--resolve` when sentinel absent | exit 0, "[OK] No pending approval." on stdout, idempotent |
| P9 | `--clear` — same action as `--resolve` but message says "cleared (abort)" | exit 0, sentinel deleted |
| P10 | `--status` when sentinel exists with valid JSON | exit 0, formatted summary on stdout (question, options, recommendation, offered_at) |
| P11 | `--status` when sentinel absent | exit 0, "[OK] No pending approval." |
| P12 | `--status` when sentinel exists but malformed | exit 0, "malformed sentinel present at PATH" — not an error |
| P13 | `--validate` on absent file | exit 0, "[OK] No sentinel to validate." |
| P14 | `--validate` on valid file | exit 0, "[OK] Valid sentinel." |
| P15 | `--validate` on malformed file | exit 1, schema errors on stderr |
| P16 | `--help` | exit 0, usage text on stdout |
| P17 | Atomic-write code-shape check | grep script source for `mktemp` + `mv` pattern; no `> "$sentinel"` direct writes |

P17 is a code-shape test, not a behavioral test; making interruption-mid-write deterministic in shell is impractical. The grep gives us protection against an inadvertent regression (someone refactoring to a non-atomic write).

### Integration tests: `tests/edge-cases-scripts.sh` extended (E40–E47)

Use the existing `bl006_seed` / `bl006_invoke_hook` helpers (rename to `pa_seed` / `pa_invoke_hook` if a separate flavor is needed, but these are reusable as-is — same JSON-input PreToolUse pattern).

| # | Test | Expected |
|---|---|---|
| E40 | `git commit -m "feat(x): foo"` with sentinel present (valid JSON) | deny JSON, reason contains "pending user decision" + the question text + the options |
| E41 | `git commit -m "chore: bump"` with sentinel present | deny JSON (Q2 A: blocks ALL commits, not just feat) |
| E42 | `git commit -m "feat(x): foo"` with sentinel present (malformed JSON) | deny JSON, reason contains "malformed" + `rm` recovery hint |
| E43 | `gh pr create --title "..." --body "..."` with sentinel present | deny JSON, reason says "PR creation blocked" |
| E44 | `git commit -m "feat(x): foo"` with sentinel absent | falls through to existing bl006_check (which would also deny — assert SOMETHING denies, but reason does NOT contain "pending user decision") |
| E45 | `git commit --no-verify -m "feat(x): foo"` with sentinel present | deny JSON, reason is the `--no-verify` security message, NOT pending-approval — confirms ordering (security gates fire first) |
| E46 | `git commit --amend -m "..."` with sentinel present | deny JSON, reason is pending-approval — confirms `pa_check` runs BEFORE the existing `--amend` warn |
| E47 | `git push --force` with sentinel present | deny JSON, reason is `--force` security message — confirms `pa_check` doesn't fire on push (only commit/PR-create) |

### Verification beyond tests (Task 5 of the implementation plan)

- All existing test suites pass (`test-check-commit-message.sh`, `test-unrecord-feature.sh`, `known-bugs-test-suite.sh`, `test-lint-uat-scenarios.sh`, full `edge-cases-scripts.sh`) — no regression from extending `pre-commit-gate.sh`.
- Manual smoke test: agent writes sentinel via helper, attempts commit → blocked with rich reason; resolves sentinel; commit again → existing gates take over.

### Out-of-scope tests

- CDF stop-hook behavior — not Solo's code, already tested in CDF 4.2.3.
- End-to-end "agent writes sentinel, user picks, agent resolves" conversation simulation — too brittle; tests the harness more than the code.
- Cross-platform `date`/`mktemp` portability — covered implicitly by macOS local CI; Linux CI matrix is a separate concern.

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Agent writes a stale sentinel and forgets to resolve it | Document `--clear` and `rm` recovery in builders-guide; matches CDF's punt. |
| `jq` unavailable on user's system | Helper depends on `jq` (matches the rest of solo-orchestrator's bash scripts). Document in CLAUDE.md tool requirements (already required). |
| Atomic-write pattern broken by future refactor | P17 code-shape test grep enforces `mktemp`+`mv`. |
| Reader's rich-reason builder fails silently when JSON is partially valid (e.g., missing `recommendation`) | `jq -er` (raw + exit-on-error) ensures any field absence triggers exit 1, falling back to malformed-reason cleanly. |
| Sentinel path-check (`-f .claude/pending-approval.json`) fails when reader runs from outside project root | Reader runs from PreToolUse hook context, where `$PWD` is the project root; matches the pattern of all other gates in `pre-commit-gate.sh`. |
| `--no-verify` user could bypass pending-approval | Intentional: `--no-verify` is a typed user override, not an agent shortcut. The security-block ordering (Q4 B) preserves the user's explicit override. |
| Helper API surface is wider than needed (per Karl's Q3 C choice) | `--clear` and `--validate` are documented but not required for the core flow; over-provisioning vs. under-provisioning trade-off explicitly accepted. |

## 12. Success criteria

1. A Claude agent attempting `git commit -m "..."` (any prefix) with `.claude/pending-approval.json` present is denied with the rich Q5-format reason naming the pending question.
2. A Claude agent attempting `gh pr create` with the sentinel present is denied with the same rich reason (action label flipped to "PR creation").
3. A `--no-verify` commit during pending-approval gets the security error, not pending-approval — security ordering preserved.
4. A `--amend` commit during pending-approval is denied (pa_check runs before the existing --amend warn) — workflow ordering preserved.
5. Helper `--offer` writes atomically; concurrent reader cannot observe a half-written file (P17 code-shape test passes).
6. Helper refuses double-offer with a clear remediation message.
7. Reader falls back gracefully to the malformed-reason text when the sentinel exists but cannot be JSON-parsed.
8. All 17 unit tests + 8 integration tests pass.
9. All pre-existing test suites pass — no regression.
10. Running `scripts/upgrade-project.sh` on an existing downstream project picks up the new enforcement (reader + helper) automatically.

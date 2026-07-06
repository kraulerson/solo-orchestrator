# Archive convention — `docs/superpowers/plans/archive/`

This directory holds implementation plans from `docs/superpowers/plans/` whose
work has **shipped** (or been superseded by later plans). Plans are archived,
never deleted, so the audit trail — plan → PR/commit → shipped code — stays
intact and citable.

## When a plan moves here

A plan is a candidate for archiving once its described work has landed on
`main`. Before moving it:

1. Cross-check `git log` / the repo for a matching PR or commit that shipped
   the plan's goal.
2. `git mv` the file from `docs/superpowers/plans/<name>.md` to
   `docs/superpowers/plans/archive/<name>.md` (preserves file history).
3. Add a one-line pointer note directly under the H1 title, citing the
   shipping PR number/branch or commit SHA + subject line (and date, when
   known). Example:

   ```
   # Some Feature — Implementation Plan

   > **Archived <date> (<backlog-id>):** Shipped via PR #NN (`branch-name`,
   > merged <date>). See `docs/superpowers/plans/archive/README.md` for the
   > archive convention.
   ```

4. Grep the repo for the plan's old path (`docs/superpowers/plans/<name>.md`)
   and fix any script, test, or doc that hardcodes it (tests that assert on
   plan-file content should point at the new archive path — the file's
   content stays intact, so those assertions keep passing after the move).
5. Never delete a plan outright, even after archiving — some archived plans
   are still read as live fixtures by regression tests (search
   `tests/test-specs-plans-*.sh` and similar before removing anything).

## What stays in `docs/superpowers/plans/` (not archived)

A plan stays in the top-level `plans/` directory as long as it is still
actionable — i.e., the work it describes has not fully shipped yet. Don't
archive a plan just because it looks old; confirm shipped status against
`git log` first.

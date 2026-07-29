# Security Audit Findings — Feature: BL-016 init.sh non-interactive mode

**Feature:** bl-016-init-non-interactive
**Date:** 2026-04-25
**Auditor Persona:** Senior Security Engineer

---

## Scope

- New code in `init.sh`: `collect_inputs_non_interactive()`, `print_help_non_interactive()`, `main()`'s rewritten flag-parser, `create_and_protect_remote()` non-interactive variable lookups, the new dir-exists check.
- New file: `tests/test-init-non-interactive.sh` (test code only).
- Documentation/template additions (no executable code changes).

## Automated Scan Results

| Tool | Config | Result | Findings |
|------|--------|--------|----------|
| `bash -n` syntax check | default | Pass | 0 |
| `shellcheck` | default | Not run on new code (matches existing repo convention; no other script runs shellcheck in CI either) | N/A |

## Manual Review Findings

| # | Category | Finding | Severity | File:Line | Resolution | Status |
|---|----------|---------|----------|-----------|------------|--------|
| 1 | Command injection | All user input flows through bash variables; `eval` is never invoked. JSON config is parsed via `jq -e`. The `cfg_get()` helper uses `jq -r --arg k "$key"`, which properly escapes the lookup key. | Critical | `init.sh::collect_inputs_non_interactive` | No mitigation needed — safe by jq design. | Accepted |
| 2 | Path traversal | `--project-dir` is bash-expanded but never used as a flag to `git`/`jq`/etc. without quoting. `mkdir -p` and `[ -e ]` use `$effective_project_dir` directly with quotes. **Updated 2026-07-29 (BL-199):** init.sh no longer calls `guard_not_in_framework`; it calls `guard_target_not_in_framework` (`# BL-199-TARGET-GUARD`), which checks the resolved TARGET only and deliberately ignores `$(pwd)` — running init.sh from inside the clone is now the supported Quick Start flow. The target check is strictly wider than before: it refuses the framework root, any path INSIDE the framework tree (new — the old guard saw only the root), and any other framework clone by signature, comparing device+inode identity as well as strings so a case-variant or symlinked spelling cannot slip past. A relative `--project-dir` is resolved against the clone's parent (`# BL-199-SIBLING-RESOLVE`) before any of this, so the guard always sees the real target. | Medium | `init.sh::collect_inputs_non_interactive`, `init.sh::main`, `init.sh::create_project` | Bounded by quoting + target-aware framework-self guard. | Accepted |
| 3 | Config file parsing | `jq -e .` validates JSON syntax before extracting any fields. Schema-typed checks reject malformed values before they reach the rest of the pipeline. Unknown fields produce a warning, not silent acceptance — caller can spot typos. | Medium | `init.sh::collect_inputs_non_interactive` (Pass-1 + config load) | Validation in place. | Fixed |
| 4 | Information disclosure | `--validate-only` emits a JSON object to stdout containing the resolved config (project name, paths, host, visibility — no secrets, no API tokens, no environment-derived data beyond `$HOME` for the default project_dir). | Low | `init.sh::collect_inputs_non_interactive` (validate-only block) | Intentional — agents need this to confirm what they're about to install. | Accepted |
| 5 | Bypass via missing tools | If `git`/`jq`/`node`/`python3` are missing, non-interactive mode fails fast in Pass 3 with the install command in the error. Same for `gh`/`glab` when the chosen `--git-host` requires them. No silent partial-install. | High | `init.sh::collect_inputs_non_interactive` (Pass 3) | Pass-3 resource validation catches before any file writes. | Fixed |
| 6 | DoS via huge config file | `jq` parses the entire file into memory; a hostile multi-GB config file would OOM the process. | Negligible | `init.sh::collect_inputs_non_interactive` (config load) | The user owns the `--config` path; no untrusted-input vector. | Accepted |
| 7 | Force-private bypass for `--deployment=organizational` | Pass 2 explicitly rejects `--visibility=public` for organizational; Task 6's defaults block also overwrites `ARG_VISIBILITY=private` when deployment is organizational, even if a flag tried to set it. Belt-and-braces. | High | `init.sh::collect_inputs_non_interactive` | Both checks in place. | Fixed |
| 8 | Branch-protection attestation bypass | `--branch-protection-attested` is a boolean flag (presence = true). For `--git-host=other`, Pass 2 requires it. There's no way to set the variable from the JSON config to silently bypass the prompt without also explicitly setting it via flag. | Medium | `init.sh::collect_inputs_non_interactive` (Pass 2) | Validation in place. | Accepted |
| 9 | Existing-dir overwrite | Pass 3 refuses to write into an existing directory unless `--allow-existing-dir` is set. A user passing the flag is presumed to know they're overwriting state. | Medium | `init.sh::collect_inputs_non_interactive` (Pass 3) | Documented + tested (N22, N23). | Fixed |
| 10 | Framework-self contamination | `guard_not_in_framework` (PR #18) originally only checked `$(pwd)`. The 2026-04-26 audit (security-audits-1, S3) caught that it did NOT protect against `--project-dir=$FRAMEWORK_REPO` from a benign tempdir, and added an optional target-dir argument. **Superseded 2026-07-29 (BL-199).** The cwd arm made the README's own Quick Start impossible — init.sh refused from inside the clone even with an external target — so init.sh's call site was **intentionally moved off** `guard_not_in_framework` onto the new target-only `guard_target_not_in_framework`. The cwd arm is therefore GONE for init.sh (by decision, not by regression); `guard_not_in_framework` itself is unchanged and still cwd-first for its six other callers. The replacement is wider on the target surface: root, INSIDE-the-tree (new), and other-clone-by-signature, each compared by device+inode identity as well as by string, which closes a measured case-variant bypass (`$TMP/CLONE/injected` against a clone at `$TMP/clone` scaffolded 602 files inside the framework, rc=0). Regression tests: `tests/test-bl199-quickstart-from-clone.sh` — T8 is the S3 vector against the new guard (arm-isolating, with mutation proof M3), T7 pins the root arm, T3/T9/T10 the inside arm. `tests/test-platform-security-bugs-closer.sh::t3a_guard_target_dir_arg` still pins the OLD guard for its remaining callers, but no longer covers init.sh. | High | `init.sh::main` + `collect_inputs_non_interactive` + `create_project` + `scripts/lib/helpers-core.sh::guard_target_not_in_framework` | Target-aware guard; cwd surface intentionally dropped for init.sh under the BL-199 contract. | Fixed |

## Threat Model Cross-Reference

No Phase 1 threat model artifact exists for solo-orchestrator itself (the project is a meta-tool framework, not a threat-modeled product). Cross-reference N/A.

## Summary

- **0 Open findings.**
- **1 Critical finding (#1) — accepted as safe-by-design:** all bash interpolation paths use `jq` with proper escaping; no `eval`, no shell evaluation of untrusted input.
- **3 High findings (#5, #7, #10) — addressed by implementation:** missing-tool fail-fast in Pass 3; force-private-for-organizational enforced at Pass 2 + variable assignment; framework-self guard extended (security-audits-1, 2026-04-26) to lint both cwd and the resolved `--project-dir` target so a malicious `--project-dir=$FRAMEWORK_REPO` from a benign cwd is now refused before any writes.
- **4 Medium findings (#2, #3, #8, #9) — bounded or fixed:** path traversal blocked by quoting + target-aware framework guard; config-file validation runs before any value extraction; attestation flag must be explicitly supplied; existing-dir behavior gated behind explicit flag.
- **2 Low/Negligible findings (#4, #6):** information disclosure is intentional (resolved-config output for `--validate-only`); DoS via huge config is the user's own problem.

**Post-audit follow-up (security-audits-1, S3 — 2026-04-26):** the original row-#10 claim that the cwd-only guard already protected `--project-dir=$FRAMEWORK_REPO` was inaccurate. A target-dir overload was added to `guard_not_in_framework`, `init.sh::main` was updated to pass the effective target, and rows #2 and #10 were rewritten to describe the actual behavior. Regression test: `tests/test-platform-security-bugs-closer.sh`.

**Second follow-up (BL-199 — 2026-07-29):** rows #2 and #10 above went stale the moment init.sh stopped calling `guard_not_in_framework`, and were amended in the same diff that moved it. Two notes for future auditors. (1) The cwd check is absent from init.sh **by decision** — see `## BL-199:` in `solo-orchestrator-backlog.md` for Karl's contract — so an audit that flags its absence as a regression is reading the wrong baseline. (2) Adversarial review of the first BL-199 implementation found that string comparison alone is not sufficient on a case-insensitive filesystem; the guard now compares device+inode identity, and the arm-isolating tests (T7/T8) plus their mutation proofs (M6/M3) exist because the first round's tests could not tell two of the three arms apart.

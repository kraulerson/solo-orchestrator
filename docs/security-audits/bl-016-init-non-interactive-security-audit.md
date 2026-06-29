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
| 2 | Path traversal | `--project-dir` is bash-expanded but never used as a flag to `git`/`jq`/etc. without quoting. `mkdir -p` and `[ -e ]` use `$effective_project_dir` directly with quotes. The framework guard (`guard_not_in_framework`, PR #18 + security-audits-1 follow-up) checks BOTH `$(pwd)` AND the resolved target path passed via the new `$1` overload, so a malicious `--project-dir=$FRAMEWORK_REPO` from a benign cwd is now refused before any writes. | Medium | `init.sh::collect_inputs_non_interactive`, `init.sh::main` | Bounded by quoting + target-aware framework-self guard. | Accepted |
| 3 | Config file parsing | `jq -e .` validates JSON syntax before extracting any fields. Schema-typed checks reject malformed values before they reach the rest of the pipeline. Unknown fields produce a warning, not silent acceptance — caller can spot typos. | Medium | `init.sh::collect_inputs_non_interactive` (Pass-1 + config load) | Validation in place. | Fixed |
| 4 | Information disclosure | `--validate-only` emits a JSON object to stdout containing the resolved config (project name, paths, host, visibility — no secrets, no API tokens, no environment-derived data beyond `$HOME` for the default project_dir). | Low | `init.sh::collect_inputs_non_interactive` (validate-only block) | Intentional — agents need this to confirm what they're about to install. | Accepted |
| 5 | Bypass via missing tools | If `git`/`jq`/`node`/`python3` are missing, non-interactive mode fails fast in Pass 3 with the install command in the error. Same for `gh`/`glab` when the chosen `--git-host` requires them. No silent partial-install. | High | `init.sh::collect_inputs_non_interactive` (Pass 3) | Pass-3 resource validation catches before any file writes. | Fixed |
| 6 | DoS via huge config file | `jq` parses the entire file into memory; a hostile multi-GB config file would OOM the process. | Negligible | `init.sh::collect_inputs_non_interactive` (config load) | The user owns the `--config` path; no untrusted-input vector. | Accepted |
| 7 | Force-private bypass for `--deployment=organizational` | Pass 2 explicitly rejects `--visibility=public` for organizational; Task 6's defaults block also overwrites `ARG_VISIBILITY=private` when deployment is organizational, even if a flag tried to set it. Belt-and-braces. | High | `init.sh::collect_inputs_non_interactive` | Both checks in place. | Fixed |
| 8 | Branch-protection attestation bypass | `--branch-protection-attested` is a boolean flag (presence = true). For `--git-host=other`, Pass 2 requires it. There's no way to set the variable from the JSON config to silently bypass the prompt without also explicitly setting it via flag. | Medium | `init.sh::collect_inputs_non_interactive` (Pass 2) | Validation in place. | Accepted |
| 9 | Existing-dir overwrite | Pass 3 refuses to write into an existing directory unless `--allow-existing-dir` is set. A user passing the flag is presumed to know they're overwriting state. | Medium | `init.sh::collect_inputs_non_interactive` (Pass 3) | Documented + tested (N22, N23). | Fixed |
| 10 | Framework-self contamination | `guard_not_in_framework` (PR #18) originally only checked `$(pwd)`. The 2026-04-26 audit (security-audits-1) caught that the legacy guard did NOT actually protect against `--project-dir=$FRAMEWORK_REPO` when cwd was a benign tempdir — only the cwd surface was linted. The follow-up extends the guard with an optional target-dir argument (`guard_not_in_framework "$target"`); `init.sh::main` now resolves the effective project dir (`ARG_PROJECT_DIR` or the non-interactive default `$HOME/Code/$ARG_PROJECT`) and passes it as `$1`, so the guard fires before any writes regardless of whether the framework path was reached via cwd or target. Regression test: `tests/test-platform-security-bugs-closer.sh::t3a_guard_target_dir_arg`. | High | `init.sh::main` + `collect_inputs_non_interactive` + `scripts/lib/helpers.sh::guard_not_in_framework` | Target-aware guard added; both cwd and `--project-dir` surfaces protected. | Fixed |

## Threat Model Cross-Reference

No Phase 1 threat model artifact exists for solo-orchestrator itself (the project is a meta-tool framework, not a threat-modeled product). Cross-reference N/A.

## Summary

- **0 Open findings.**
- **1 Critical finding (#1) — accepted as safe-by-design:** all bash interpolation paths use `jq` with proper escaping; no `eval`, no shell evaluation of untrusted input.
- **3 High findings (#5, #7, #10) — addressed by implementation:** missing-tool fail-fast in Pass 3; force-private-for-organizational enforced at Pass 2 + variable assignment; framework-self guard extended (security-audits-1, 2026-04-26) to lint both cwd and the resolved `--project-dir` target so a malicious `--project-dir=$FRAMEWORK_REPO` from a benign cwd is now refused before any writes.
- **4 Medium findings (#2, #3, #8, #9) — bounded or fixed:** path traversal blocked by quoting + target-aware framework guard; config-file validation runs before any value extraction; attestation flag must be explicitly supplied; existing-dir behavior gated behind explicit flag.
- **2 Low/Negligible findings (#4, #6):** information disclosure is intentional (resolved-config output for `--validate-only`); DoS via huge config is the user's own problem.

**Post-audit follow-up (security-audits-1, S3 — 2026-04-26):** the original row-#10 claim that the cwd-only guard already protected `--project-dir=$FRAMEWORK_REPO` was inaccurate. A target-dir overload was added to `guard_not_in_framework`, `init.sh::main` was updated to pass the effective target, and rows #2 and #10 were rewritten to describe the actual behavior. Regression test: `tests/test-platform-security-bugs-closer.sh`.

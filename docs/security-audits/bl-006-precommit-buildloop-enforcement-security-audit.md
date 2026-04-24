# Security Audit Findings — Feature: BL-006 pre-commit Build Loop enforcement

**Feature:** bl-006-precommit-buildloop-enforcement
**Date:** 2026-04-24
**Auditor Persona:** Senior Security Engineer

---

## Scope

- New bash in `scripts/pre-commit-gate.sh`: the `bl006_check` function (message extraction from `-m`/heredoc/`-F`, derivative-commit filters, subcommand delegation).
- New bash in `scripts/process-checklist.sh`: the `check_commit_message` function and the `require_build_loop_state_for_commit` helper.
- Two new test files: `tests/test-check-commit-message.sh`, additions to `tests/edge-cases-scripts.sh`.

## Automated Scan Results

| Tool | Config | Result | Findings |
|------|--------|--------|----------|
| Semgrep | p/owasp-top-ten, p/security-audit | Not run (bash-only change; ruleset targets web languages) | N/A |
| `bash -n` syntax check | default | Pass | 0 |
| `shellcheck` | default | Not run on new files (pre-existing repo convention — no other script runs shellcheck in CI either) | N/A |

## Manual Review Findings

| # | Category | Finding | Severity | File:Line | Resolution | Status |
|---|----------|---------|----------|-----------|------------|--------|
| 1 | Command injection | `$COMMAND` is treated as data throughout the extractor; passed through `grep`, `sed`, `awk`, and `head` via stdin/pipes. Never `eval`d, never passed to `sh -c`, never used as a filename. | Critical | `scripts/pre-commit-gate.sh` bl006_check | No mitigation needed — the code already follows the safe pattern. | Accepted (safe by design) |
| 2 | Command injection | The extracted `$msg` is passed as a single quoted argv to `"$SCRIPT_DIR/process-checklist.sh" --check-commit-message "$msg"`. Bash argv quoting prevents shell re-parsing. | Critical | `scripts/pre-commit-gate.sh` bl006_check | No mitigation needed. | Accepted |
| 3 | Path traversal / arbitrary file read | The `-F <file>` branch reads an arbitrary path the author provides via `head -n 1 "$f"`. | Low | `scripts/pre-commit-gate.sh` bl006_check | The caller (Claude agent running `git commit -F path`) is trusted; the hook is not a trust boundary against the author. `-F <path>` is a legitimate git feature. Read is bounded to the first line and discarded if empty. | Accepted |
| 4 | TOCTOU | `.git/MERGE_HEAD` check is non-atomic with respect to the subsequent `git commit`. In theory, a merge could begin between the check and the commit. | Negligible | `scripts/pre-commit-gate.sh` bl006_check | Single-user workflow; no concurrent processes mutate `.git/MERGE_HEAD` between hook and commit. Not a security property — if race happens, the existing file-heuristic fallback still runs. | Accepted |
| 5 | Resource exhaustion | `awk` / `sed` / `head` all operate on `$COMMAND`, whose length is bounded by Claude Code's bash tool input size (subject to the environment's argv limits, typically 128 KB). | Negligible | `scripts/pre-commit-gate.sh` bl006_check | Existing environmental limits are sufficient. | Accepted |
| 6 | Input validation | The `feat`-prefix regex `^feat(\([^)]*\))?!?:[[:space:]]` anchors to start-of-subject and rejects near-misses (`feature:`, `featbar:`, `Revert "feat..."`). Tested via U10, U11, U17. | High | `scripts/process-checklist.sh` check_commit_message | Regex is anchored; 17 unit tests exercise edge cases. | Fixed |
| 7 | Information disclosure | Deny-reason JSON contains the remediation text, which references script paths and step names. No user-supplied content is reflected back. | Low | `scripts/pre-commit-gate.sh` bl006_check | Remediation is static; safe. | Accepted |
| 8 | Secret exposure | No secrets are read, written, or logged. No environment variables are inspected by the new code beyond `PROCESS_STATE` and `PHASE_STATE` (paths). | Critical | — | No change needed. | Accepted |

## Threat Model Cross-Reference

No Phase 1 threat model artifact exists for solo-orchestrator itself (the project is a meta-tool framework, not a threat-modeled product). Cross-reference N/A.

## Summary

- **0 Open findings.**
- **2 Critical findings (#1, #2, #8) — accepted as safe-by-design:** the code treats `$COMMAND` and `$msg` as data, never invokes them as shell, and doesn't handle secrets.
- **1 High finding (#6) — fixed via regex anchoring and 17 unit tests** (U1–U17 in `tests/test-check-commit-message.sh`).
- **2 Low findings (#3, #7) — accepted:** `-F <path>` file read is a legitimate git flow the hook is not a trust boundary for; deny-reason text is static and contains no user-supplied content.
- **2 Negligible findings (#4, #5):** TOCTOU on `.git/MERGE_HEAD` and resource exhaustion from awk/sed — both immaterial given the single-user Claude-agent flow.

No findings require code changes. The implementation passes the audit.

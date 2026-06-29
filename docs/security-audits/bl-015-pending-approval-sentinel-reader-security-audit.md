# Security Audit Findings — Feature: BL-015 pending-approval sentinel reader

**Feature:** bl-015-pending-approval-sentinel-reader
**Date:** 2026-04-25
**Auditor Persona:** Senior Security Engineer

---

## Scope

- New `scripts/pending-approval.sh` helper script (5 subcommands).
- New `pa_check()` block + two reason builders in `scripts/pre-commit-gate.sh`.
- New unit test file `tests/test-pending-approval.sh` and integration tests E40–E47 in `tests/edge-cases-scripts.sh`.
- Documentation/template additions (no executable code changes).

## Automated Scan Results

| Tool | Config | Result | Findings |
|------|--------|--------|----------|
| `bash -n` syntax check | default | Pass | 0 |
| `shellcheck` | default | Not run on new files (matches existing repo convention) | N/A |

## Manual Review Findings

| # | Category | Finding | Severity | File:Line | Resolution | Status |
|---|----------|---------|----------|-----------|------------|--------|
| 1 | Command injection | The helper builds JSON via `jq -n --arg ... --argjson ...` — jq's `--arg` properly escapes user-supplied strings. No `eval`, no shell interpolation of untrusted input into commands. | Critical | `scripts/pending-approval.sh::cmd_offer` | No mitigation needed — safe by jq design. | Accepted |
| 2 | Command injection | The reader passes the sentinel path to `jq -er` (data-mode parsing). The path is a fixed string `.claude/pending-approval.json`, never derived from user input. | Critical | `scripts/pre-commit-gate.sh::pa_check` | No mitigation needed. | Accepted |
| 3 | Command injection | The deny reason is built via `cat <<EOF` heredoc; user-supplied fields (`question`, `options`, `recommendation`, `offered_at`) are interpolated as bash strings, then run through `tr | sed` to JSON-encode. Heredoc with unquoted EOF performs parameter expansion but not command substitution of agent-controlled content (the values come from `jq -er` which returns plain strings). The `sed 's/"/\\"/g'` step escapes embedded quotes for the JSON envelope. | High | `scripts/pre-commit-gate.sh::build_pa_rich_reason` | Encoding pipeline is robust against the inputs. | Accepted |
| 4 | Path traversal / arbitrary write | Helper's `--offer` writes to `$PROJECT_ROOT/.claude/pending-approval.json` where `$PROJECT_ROOT` is found by walking up from `$PWD` looking for `.claude/`. Bounded to the discovered project; cannot write outside. `mktemp` argument uses the same project-bounded path. | Medium | `scripts/pending-approval.sh::find_project_root + cmd_offer` | Bounded write path; no traversal possible. | Accepted |
| 5 | Atomic write race | Helper uses `mktemp + mv`; readers (CDF stop-hook, Solo pre-commit-gate) never observe a half-written file. Code-shape regression test P17 enforces this pattern. | High | `scripts/pending-approval.sh::cmd_offer` | Atomic-write pattern in place + test guard. | Fixed |
| 6 | Information disclosure | Deny reason includes the sentinel's `question`, `options`, `recommendation`, `offered_at` fields. These are agent-authored and intended for display. No secrets are exposed; no environment variables are read. | Low | `scripts/pre-commit-gate.sh::build_pa_rich_reason` | Intentional and safe. | Accepted |
| 7 | Denial of service | A malicious or crashed agent could write a sentinel and never resolve it, blocking all commits indefinitely. Mitigation: `--clear` and manual `rm` documented. CDF and Solo share this risk; intentionally punted (Q7 A) per spec §11. | Medium | `scripts/pending-approval.sh` lifecycle | Documented manual recovery; matches CDF behavior. | Accepted |
| 8 | Bypass via non-helper writes | A determined agent could `echo '{}' > .claude/pending-approval.json` directly, bypassing the helper's validation. The reader treats malformed sentinels as still-blocking ("in flight"), so this can only block the agent itself, not bypass. Conversely, an agent wanting to bypass the sentinel could `rm .claude/pending-approval.json` directly. The PreToolUse hook does not gate `rm` — bypass is theoretically possible but requires the agent to actively defeat its own rule. Out of scope for this layer. | Low | Architectural | `--clear` provides the sanctioned path; rm-bypass is acknowledged. | Accepted |

## Threat Model Cross-Reference

No Phase 1 threat model artifact exists for solo-orchestrator itself (the project is a meta-tool framework, not a threat-modeled product). Cross-reference N/A.

## Summary

- **0 Open findings.**
- **3 Critical findings (#1, #2, #3) — accepted as safe-by-design:** all bash interpolation paths use jq for JSON construction or quoted heredocs with controlled inputs; no shell evaluation of untrusted input.
- **2 High findings (#3, #5):** JSON encoding pipeline robust; atomic-write pattern enforced by code-shape test P17.
- **2 Medium findings (#4, #7):** path-traversal bounded by project-root walk; DoS via stuck sentinel intentionally punted with documented manual recovery.
- **2 Low findings (#6, #8):** information disclosure is intentional (reflecting question to agent); rm-bypass is theoretically possible but architecturally out of scope.

**Post-audit follow-up (security-audits-2, S3 — 2026-04-26):** the original audit missed that `scripts/pending-approval.sh` was listed in the `guard_not_in_framework` docstring contract (`scripts/lib/helpers.sh:201-204`) as a script that MUST invoke the guard before any file writes, yet the script never actually called it. A direct invocation was added at dispatch time (covers `--offer`, `--resolve`, `--clear`, `--status`, `--validate` uniformly). A docstring-parity test (`tests/test-platform-security-bugs-closer.sh::t4b_docstring_parity`) now fails CI when any script named in the docstring lacks the callsite — preventing the next added script (or the next removed callsite) from silently breaking the contract. Same audit also added the missing callsite to `scripts/process-checklist.sh`.

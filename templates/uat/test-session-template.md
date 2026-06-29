# UAT Test Session — [SESSION_NUMBER]

**Date:** [SESSION_DATE]
**Features Under Test:** [FEATURE_LIST]
**Tester:** [Your name]

---

## Instructions

1. For each feature below, follow the test scenarios step by step
2. Mark each scenario Pass or Fail
3. If Fail, fill in the bug details in the Bugs Found section below
4. Drop your completed file in `tests/uat/sessions/[session-folder]/submissions/`
5. Tell the Orchestrator agent "results are in" when done

---

## Before you start

_Every UAT test must begin with a clear statement of the test environment and one-time setup. Fill this in before running any scenario:_

- **System under test:** _describe the environment (OS + arch for desktop/CLI; browser + URL for web; device + OS for mobile; MCP client + server command for mcp-server; other context for 'other' platforms)_
- **Project root / app location:** _absolute path, URL, or device identifier_
- **Runtime / tooling:** _language + version, browser, or device OS_
- **Required tools:** _list._ Optional: _list, with scenario numbers that require each_
- **One-time setup:** _the commands or steps you ran once before starting_

For richer per-platform guidance — including quality checklist, anti-patterns, reference examples, and the co-build protocol for 'other' platforms — see `tests/uat/templates/test-session-template.html` and `docs/reference/uat-authoring-guide.md` (both copied into the project at init time).

---

## Test Scenarios

<!-- Agent pre-populates this section with feature-specific scenarios from the User Journey -->

### Feature: [FEATURE_NAME]

| # | Scenario | Steps | Expected Result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| 1 | [Happy path from User Journey] | [Steps] | [Expected] | | |
| 2 | [Error/edge case] | [Steps] | [Expected error handling] | | |
| 3 | [Boundary condition] | [Steps] | [Expected] | | |

---

## Bugs Found

| # | Severity | Feature | Description | Steps to Reproduce | Expected vs Actual |
|---|---|---|---|---|---|
| | SEV-? | | | | |

### Severity Guide
- **SEV-1:** Data loss, security breach, app crash on core flow
- **SEV-2:** Feature broken but workaround exists, significant UX failure
- **SEV-3:** Minor UX issue, cosmetic, non-core edge case
- **SEV-4:** Enhancement, suggestion, polish

---

## Overall Notes

_Free-form observations, UX concerns, suggestions, things that felt wrong even if they technically worked._

# Intake Wizard — Design Spec

## Overview

An interactive guided system for filling out the Project Intake template. Two paths: a bash script for confident users and a Claude Code-assisted conversation for users who want help thinking through requirements. Both produce the same output — a completed `PROJECT_INTAKE.md` ready for Phase 0.

## Entry Points

### From init.sh

After project creation, init.sh offers the intake wizard:

```
How would you like to fill out the Project Intake?

1. Guided Script (30-60 minutes)
   You answer questions section by section in the terminal. Best if you
   already know your project requirements, tech preferences, and constraints.
   You can pause anytime and resume later. Progress is saved after each section.

2. AI-Assisted (45-90 minutes)
   Claude Code walks you through the intake conversationally, explains each
   field, and suggests options based on your project type. Best if you want
   help thinking through requirements or are unsure about technical choices.
   Requires Claude Code to be authenticated.

3. I'll do it manually later
   Open PROJECT_INTAKE.md in your editor and fill it out yourself.
   See the User Guide Section 3 for field-by-field guidance.
```

### Standalone

`scripts/intake-wizard.sh` can be run anytime after init. Shows the same mode selection.

### Resume

`scripts/intake-wizard.sh --resume` picks up from where the user left off (script path only).

## Path 1: Guided Script

### Section-by-Section Flow

The script walks through sections in order, skipping sections that don't apply based on the 7 init answers (project name, description, platform, track, deployment type, language, directory):

| Section | Skipped When | Approx Questions |
|---|---|---|
| 1. Project Identity | Pre-filled from init answers | 2-3 (target platforms, repo URL) |
| 2. Business Context | Never | 8-10 |
| 3. Constraints | Never | 8-10 |
| 4. Features & Requirements | Never | 10-15 (varies by feature count) |
| 5. Data & Integrations | Never | 10-15 |
| 6. Technical Preferences | Never (subsections vary by platform) | 15-25 |
| 7. Revenue Model | Light track, or Personal + internal tool | 5-8 |
| 8. Governance Pre-Flight | Personal deployment | 8-15 |
| 9. Accessibility & UX | Never | 5-7 |
| 10. Distribution & Operations | Never (subsections vary by platform) | 5-10 |
| 11. Known Risks | Never | 1-2 |
| 12. Agent Initialization Prompt | Auto-generated from answers | 0 |

### Save/Resume Mechanism

- State stored in `.claude/intake-progress.json`:
  ```json
  {
    "version": 1,
    "started_at": "2026-04-02T14:30:00Z",
    "last_section": 5,
    "completed_sections": [1, 2, 3, 4, 5],
    "answers": { ... },
    "poc_mode": null
  }
  ```
- After completing each section, the script writes that section into PROJECT_INTAKE.md and updates the progress file
- On resume, it reads the progress file, reports status ("Sections 1-5 complete. Resuming at Section 6: Technical Preferences"), and continues
- The user can pause at any section boundary with Ctrl+C or by answering `pause` — the script saves and exits cleanly

### "I'm Not Sure" Handling

At any question, the user can type `?` to get ranked suggestions with context. Suggestions come from `templates/intake-suggestions/` files matched to their platform/language/track combination.

Example:
```
Authentication strategy [? for suggestions]: ?

Based on your project (web, TypeScript, personal):

  1. Supabase Auth (recommended)
     You'll likely use Supabase for data — auth comes included.
     Supports email/password, magic links, and social logins.
     No additional cost.

  2. NextAuth.js
     More flexible if you need custom providers or complex
     session handling. More setup, but well-documented.

  3. Clerk
     Fastest to implement. Managed service with pre-built UI
     components. Free tier covers 10K MAU, then $25/mo.

Select [1-3] or type your own:
```

All suggestions provide context explaining WHY each option fits (or doesn't) the user's specific project parameters.

## Path 2: Claude-Guided

### Prompt Generation

The script generates `INTAKE_GUIDED_PROMPT.md` containing:

1. **Project context** — pre-filled from the 7 init answers (project name, platform, language, track, deployment type, description, directory)

2. **Instructions to Claude:**
   - Walk through the Intake template section by section, conversational tone
   - Explain each field's purpose before asking
   - When the user is unsure, offer 2-3 ranked suggestions with context based on the project parameters
   - Check off fields as covered; flag gaps before moving to the next section
   - Skip sections that don't apply (Revenue for Light/Personal, Governance for Personal)
   - For organizational deployments, ask which governance mode (Production / Sponsored POC / Private POC) and handle accordingly
   - Write completed sections into PROJECT_INTAKE.md progressively
   - At the end, generate Section 12 (Agent Initialization Prompt) automatically from the answers

3. **The blank Intake template structure** — so Claude knows what fields to cover and in what order

4. **Platform-specific suggestion data** — pulled from the relevant `templates/intake-suggestions/` file so Claude has the same domain knowledge the script path uses

### Launch Options

After generating the prompt file:

```
The AI-assisted intake generates a prompt file with your project context.

1. Launch Claude Code now
   Opens Claude Code with the intake prompt automatically.
   You'll have a conversation that fills out PROJECT_INTAKE.md as you go.

2. Generate prompt file only
   Creates INTAKE_GUIDED_PROMPT.md for you to review first or use later.
   When ready, run: claude "Read INTAKE_GUIDED_PROMPT.md and begin"
```

Each option includes a brief explanation so the user knows what they're selecting.

## Governance and POC Modes

### Mode Selection (Organizational Deployment Only)

When the script reaches Section 8, or when the Claude-guided path reaches governance:

```
Section 8: Governance Pre-Flight

Organizational projects require governance approvals before Phase 0.
Some of these take weeks to resolve. Choose your approach:

1. Production Build (recommended when approvals are in hand)
   All 8 pre-conditions must be resolved or in progress.
   You'll document status, contacts, and dates for each.
   Any unresolved items are tracked — resume later to update them.

2. Sponsored POC (organization knows, full approvals deferred)
   Your organization has approved the exploration. You have a sponsor
   and an approved AI deployment path. Insurance, liability, ITSM,
   exit criteria, and backup maintainer are deferred until production.
   All technical work is production-grade — code, tests, scans, docs.

3. Private POC (personal exploration, no organizational involvement)
   You're proving the concept on your own time and machine before
   pitching it. All governance pre-conditions are deferred.
   No production deployment. No real user data. No external users.
   All technical work is production-grade so it carries forward.
```

### Pre-Condition Requirements by Mode

| Pre-Condition | Production | Sponsored POC | Private POC |
|---|---|---|---|
| AI deployment path approved | Required | Required | Deferred |
| Insurance confirmation | Required | Deferred | Deferred |
| Liability entity designated | Required | Deferred | Deferred |
| Project sponsor assigned | Required | Required | Deferred |
| Backup maintainer designated | Required | Deferred | Deferred |
| ITSM registration | Required | Deferred | Deferred |
| Exit criteria defined | Required | Deferred | Deferred |
| Time allocation approved | Required | Required | Deferred |

### POC Constraints (Both Types)

- No production deployment (dev/staging only)
- No real user data (synthetic/test data only)
- No external user access
- POC status watermarked in APPROVAL_LOG.md, CLAUDE.md, and PROJECT_INTAKE.md

### Technical Work Standard

Both POC types follow the full phase-gate process (Phases 0-3). Same TDD, same security scanning, same threat modeling, same documentation. Phase 4 stops at "ready to deploy" but does not deploy to production. All technical artifacts are production-grade and carry forward to production unchanged.

### Upgrade to Production

`scripts/intake-wizard.sh --upgrade-to-production` walks through only the deferred pre-conditions, updates all POC watermarks (APPROVAL_LOG.md, CLAUDE.md, PROJECT_INTAKE.md), removes the POC constraints, and updates `.claude/intake-progress.json` to reflect production status. Technical artifacts carry forward unchanged.

## Suggestion Files

### Directory Structure

```
templates/intake-suggestions/
  web.json
  desktop.json
  mobile.json
  mcp_server.json
  common.json
```

### File Format

One file per platform. Each file contains suggestions keyed by field name and language:

```json
{
  "platform": "web",
  "suggestions": {
    "authentication": {
      "typescript": [
        {
          "name": "Supabase Auth",
          "rank": 1,
          "context": "You'll likely use Supabase for data — auth comes included.",
          "when": "Most web projects with Supabase"
        }
      ]
    },
    "hosting": { ... },
    "database": { ... },
    "frontend_framework": { ... }
  }
}
```

### common.json

Covers platform-independent fields:
- Budget ranges by track (Light: $0-50/mo, Standard: $50-500/mo, Full: $500+/mo)
- Timeline suggestions by complexity
- Accessibility defaults (WCAG AA, Lighthouse 90+)
- Uptime expectations by track
- Data sensitivity classification guidance

### Usage

- The script reads the relevant platform file + common.json at runtime
- The Claude-guided prompt includes the relevant file's content inline

## File Map

### New Files

| File | Purpose |
|---|---|
| `scripts/intake-wizard.sh` | Main wizard — mode selection, section-by-section Q&A, save/resume, POC handling |
| `templates/intake-suggestions/web.json` | Web platform suggestions |
| `templates/intake-suggestions/desktop.json` | Desktop platform suggestions |
| `templates/intake-suggestions/mobile.json` | Mobile platform suggestions |
| `templates/intake-suggestions/mcp_server.json` | MCP-server platform suggestions (transport, persistence, mcp_sdk, scheduling) |
| `templates/intake-suggestions/common.json` | Platform-independent suggestions |
| `templates/intake-guided-prompt.md` | Template for Claude-guided prompt (populated at runtime) |

### Modified Files

| File | Change |
|---|---|
| `init.sh` | Add intake wizard offer after project creation, copy new files into generated projects |
| `docs/user-guide.md` | Document the intake wizard, POC modes, and upgrade path |
| `templates/project-intake.md` | Add POC watermark fields (status, mode, constraints) |

### Copied into Generated Projects by init.sh

```
scripts/intake-wizard.sh
templates/intake-suggestions/*.json
templates/intake-guided-prompt.md
```

### Created at Runtime (Not Shipped)

```
.claude/intake-progress.json
INTAKE_GUIDED_PROMPT.md (Claude-guided path only)
```

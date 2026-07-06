# Technical User Review Resolutions (Round 2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve 6 remaining actionable findings from the updated Technical Non-Developer Usability Review: security scan interpretation guide, session resume script, optional enhancement quick setup, and 3 minor documentation friction items.

**Architecture:** One new documentation file (`docs/security-scan-guide.md`), one new script template (`scripts/resume.sh`), modifications to `init.sh` (copy new script + update dry-run), and documentation edits to `docs/user-guide.md` and `docs/cli-setup-addendum.md`.

**Tech Stack:** Markdown, Bash

---

## File Map

| File | Action | Tasks |
|---|---|---|
| `docs/security-scan-guide.md` | Create | Task 1 |
| `scripts/resume.sh` | Create | Task 2 |
| `init.sh` | Modify (lines 446-452, ~1385, ~1442) | Task 2, Task 3 |
| `docs/user-guide.md` | Modify (lines 19-33, 234, 268-277) | Task 4, Task 5, Task 6 |
| `docs/cli-setup-addendum.md` | Modify (line 364) | Task 5 |

---

### Task 1: Create Security Scan Interpretation Guide

**Review finding:** "A security scan interpretation guide for the 10 most common Semgrep findings and 5 most common Snyk findings in the recommended stacks."

**Files:**
- Create: `docs/security-scan-guide.md`
- Modify: `docs/user-guide.md` (add reference in Phase 2 security audit step and Phase 3 section)

- [ ] **Step 1: Create the security scan guide**

Create `docs/security-scan-guide.md` with the following content:

```markdown
# Security Scan Interpretation Guide

Quick reference for the most common findings from Semgrep and Snyk in the Solo Orchestrator recommended stacks (Next.js/TypeScript, Python/FastAPI). For each finding: what it means, whether it is likely real, and how to fix it.

---

## Semgrep — 10 Most Common Findings

### 1. `javascript.express.security.audit.xss.mustache-escape` / `typescript.react.security.audit.react-dangerouslysetinnerhtml`

**What it means:** You are inserting user-controlled data into HTML without escaping. An attacker could inject `<script>` tags.

**Likely real?** Yes, unless the content is sanitized upstream with a library like DOMPurify or comes from a trusted internal source (not user input).

**Fix:** Use framework-native rendering (React's JSX auto-escapes by default). If you must use `dangerouslySetInnerHTML`, sanitize with DOMPurify first:
```typescript
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userContent) }} />
```

---

### 2. `javascript.lang.security.audit.detect-non-literal-regexp`

**What it means:** A regular expression is being constructed from a variable, not a string literal. If that variable contains user input, an attacker could craft input that causes catastrophic backtracking (ReDoS).

**Likely real?** Only if the variable comes from user input. If it comes from configuration or hardcoded values, this is a false positive.

**Fix:** If user input, use a library like `safe-regex` to validate the pattern, or avoid building regexes from user data entirely.

---

### 3. `javascript.lang.security.audit.detect-possible-timing-attacks`

**What it means:** You are comparing secrets (API keys, tokens, passwords) using `===` instead of a constant-time comparison. An attacker could measure response time differences to guess the secret character by character.

**Likely real?** Yes, if comparing secrets or tokens. False positive if comparing non-sensitive strings.

**Fix:** Use `crypto.timingSafeEqual`:
```typescript
import { timingSafeEqual } from 'crypto';
const isValid = timingSafeEqual(Buffer.from(provided), Buffer.from(expected));
```

---

### 4. `typescript.nextjs.react-nextjs.security.audit.next-server-side-redirect-open-redirect`

**What it means:** A server-side redirect uses a user-supplied URL. An attacker could redirect users to a malicious site (phishing).

**Likely real?** Yes, if the redirect target comes from a query parameter, form field, or any user-controlled source.

**Fix:** Validate the redirect URL against an allowlist of known paths or domains:
```typescript
const allowedPaths = ['/dashboard', '/settings', '/login'];
const target = req.query.redirect as string;
if (!allowedPaths.includes(target)) {
  return res.redirect('/dashboard'); // safe default
}
return res.redirect(target);
```

---

### 5. `javascript.lang.security.audit.detect-eval-with-expression`

**What it means:** Code uses `eval()` or `Function()` with a non-literal argument. This allows arbitrary code execution if the argument contains user input.

**Likely real?** Almost always yes. `eval` with user input is a critical vulnerability.

**Fix:** Remove `eval`. Use `JSON.parse()` for data, or restructure logic to avoid dynamic code execution.

---

### 6. `python.lang.security.audit.insecure-hash-algorithms`

**What it means:** Code uses MD5 or SHA-1, which are cryptographically broken. Not safe for passwords, signatures, or integrity verification.

**Likely real?** Yes for security-sensitive uses (passwords, tokens, signatures). False positive for non-security uses (cache keys, checksums for non-adversarial scenarios).

**Fix:** Use SHA-256 or bcrypt:
```python
# For hashing data
import hashlib
digest = hashlib.sha256(data.encode()).hexdigest()

# For passwords — always use bcrypt or argon2
from passlib.hash import bcrypt
hashed = bcrypt.hash(password)
```

---

### 7. `python.django.security.audit.raw-query` / `python.sqlalchemy.security.sqlalchemy-execute-raw-query`

**What it means:** A raw SQL query is constructed with string formatting or concatenation. This is a SQL injection vulnerability.

**Likely real?** Yes, if any part of the query string comes from user input. False positive if the query is entirely hardcoded.

**Fix:** Use parameterized queries:
```python
# Bad — SQL injection
db.execute(f"SELECT * FROM users WHERE id = {user_id}")

# Good — parameterized
db.execute("SELECT * FROM users WHERE id = :id", {"id": user_id})
```

---

### 8. `python.lang.security.audit.insecure-transport.requests.request-session-with-http`

**What it means:** An HTTP request is being made without TLS (using `http://` instead of `https://`). Data is transmitted in plaintext.

**Likely real?** Yes for production code. False positive for localhost development URLs.

**Fix:** Use `https://` for all non-localhost URLs. If connecting to a local service during development, suppress with an inline comment: `# nosemgrep: insecure-transport`

---

### 9. `generic.secrets.security.detected-generic-api-key`

**What it means:** Semgrep detected what appears to be an API key or secret hardcoded in source code.

**Likely real?** Check the flagged string. If it is a real API key, database password, or token — yes, critical. If it is a placeholder, test fixture, or example value — false positive.

**Fix:** Move the secret to an environment variable:
```typescript
// Bad
const apiKey = "sk-abc123...";

// Good
const apiKey = process.env.API_KEY;
```
Add the variable to `.env` (which must be in `.gitignore`).

---

### 10. `javascript.browser.security.insufficient-postmessage-origin-validation`

**What it means:** A `postMessage` event listener does not validate the origin of the message. Any website could send messages to your application.

**Likely real?** Yes, if you use `postMessage` for cross-origin communication.

**Fix:** Always validate the origin:
```typescript
window.addEventListener('message', (event) => {
  if (event.origin !== 'https://trusted-domain.com') return;
  // process event.data
});
```

---

## Snyk — 5 Most Common Findings

### 1. Prototype Pollution (in lodash, minimist, qs, or similar)

**What it means:** A dependency has a vulnerability where an attacker can inject properties into JavaScript object prototypes, potentially causing unexpected behavior or security bypasses.

**Likely real?** Depends on whether your code passes user-controlled data to the vulnerable function. Often exploitable in server-side code that processes JSON from user input.

**Fix:** Update the dependency: `npm update <package>`. If the vulnerable package is a transitive dependency, use `npm audit fix` or add a resolution/override in `package.json`.

---

### 2. Regular Expression Denial of Service (ReDoS)

**What it means:** A dependency uses a regex pattern that can be exploited with crafted input to consume excessive CPU time, causing a denial of service.

**Likely real?** Only if user-controlled input reaches the vulnerable regex. Many ReDoS findings in deep transitive dependencies are not reachable from your code.

**Fix:** Update the dependency. If no fix is available and the vulnerable code path is not reachable from user input, document the risk: create a tracking issue and note in your security log that the vulnerable path is unreachable.

---

### 3. Cross-Site Scripting (XSS) in a UI dependency

**What it means:** A frontend dependency (often a rich text editor, markdown renderer, or HTML sanitizer) has a known XSS bypass.

**Likely real?** Yes, if you use the affected component to render user-provided content. Not exploitable if you only render trusted content.

**Fix:** Update the dependency. If no fix is available, add server-side sanitization as a defense-in-depth layer.

---

### 4. Arbitrary Code Execution in a build/dev dependency

**What it means:** A dependency used during build or development (not shipped to production) has a vulnerability allowing code execution.

**Likely real?** Lower risk than production dependencies — this would require an attacker to compromise your development environment or CI pipeline. Still worth fixing.

**Fix:** Update the dependency. For dev-only dependencies, this is lower priority but should not be ignored.

---

### 5. Denial of Service via crafted input (in parsers, serializers, image processors)

**What it means:** A dependency that parses user input (JSON, XML, images, etc.) can be crashed or made to consume excessive resources with specially crafted input.

**Likely real?** Yes, if the affected parsing code processes untrusted input. Particularly relevant for file upload handlers, API request parsers, and image processing.

**Fix:** Update the dependency. If the affected parser processes user-uploaded files, add input size limits as a defense-in-depth measure.

---

## General Guidance

### When in doubt about a finding:

1. **Read the Semgrep rule description** — click the rule ID in the output for documentation.
2. **Trace the data flow** — is user input involved? If the flagged code only processes internal/trusted data, it may be a false positive.
3. **Check if it is in test code** — vulnerabilities in test fixtures are not production risks. Suppress with `# nosemgrep` and a comment explaining why.
4. **Ask the AI agent** — paste the finding and ask: "Is this a real vulnerability in our context, or a false positive? Explain the attack path."

### Suppressing false positives:

```python
# Python — inline suppression
result = hashlib.md5(cache_key.encode())  # nosemgrep: insecure-hash-algorithms — used for cache key, not security
```

```typescript
// TypeScript — inline suppression
// nosemgrep: detect-non-literal-regexp — regex built from config, not user input
const pattern = new RegExp(config.searchPattern);
```

Always include a comment explaining WHY it is a false positive. A suppression without explanation is indistinguishable from someone ignoring a real vulnerability.
```

- [ ] **Step 2: Add reference to the guide in the User Guide Phase 2 security audit step**

In `docs/user-guide.md`, find the Phase 2 Build Loop table row for step 3 (security audit), which contains `semgrep scan --config=p/owasp-top-ten`. After the Build Loop table (after line ~517), within the Phase 2 section, add a note:

```markdown
**Interpreting scan results:** If you are unsure whether a finding is real or a false positive, see the [Security Scan Interpretation Guide](security-scan-guide.md) for plain-language explanations of the most common findings.
```

- [ ] **Step 3: Add reference in the Phase 3 section**

In the Phase 3 section, after the row for `semgrep scan` (line ~621), add the same reference note.

- [ ] **Step 4: Update init.sh to copy the guide into generated projects**

In `init.sh`, in the document copying section where framework docs are copied into `docs/framework/`, add:

```bash
cp "$SCRIPT_DIR/docs/security-scan-guide.md" docs/framework/
```

- [ ] **Step 5: Commit**

```bash
git add docs/security-scan-guide.md docs/user-guide.md init.sh
git commit -m "docs: add security scan interpretation guide

Plain-language explanations for the 10 most common Semgrep findings
and 5 most common Snyk findings in Next.js/TypeScript and Python
stacks. Referenced from User Guide Phase 2 and Phase 3 sections."
```

---

### Task 2: Create Session Resume Script

**Review finding:** "A script or template that constructs a session resume prompt from: current phase, last git log entry, features built vs. remaining, and known issues."

**Files:**
- Create: `scripts/resume.sh`
- Modify: `init.sh:449-452` (add copy + chmod)
- Modify: `init.sh` dry_run_summary (add to file list)
- Modify: `init.sh` print_next_steps (mention the script)

- [ ] **Step 1: Create the resume script**

Create `scripts/resume.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Session Resume Prompt Generator
# Reads project state and outputs a resume prompt to paste into Claude Code.
#
# Usage: bash scripts/resume.sh

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  BOLD=''; CYAN=''; NC=''
fi

echo -e "${BOLD}Generating session resume prompt...${NC}"
echo ""

# --- Gather state ---

# Current phase
PHASE="unknown"
if [ -f ".claude/phase-state.json" ]; then
  PHASE=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/phase-state.json 2>/dev/null | sed 's/.*"current_phase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "unknown")
fi

# Last 3 git log entries
RECENT_COMMITS=""
if command -v git &>/dev/null && [ -d ".git" ]; then
  RECENT_COMMITS=$(git log --oneline -3 2>/dev/null || echo "(no commits)")
fi

# Features built and remaining from CLAUDE.md
FEATURES_BUILT="(not found in CLAUDE.md)"
FEATURES_REMAINING="(not found in CLAUDE.md)"
KNOWN_ISSUES="(not found in CLAUDE.md)"
LAST_SESSION="(not found in CLAUDE.md)"

if [ -f "CLAUDE.md" ]; then
  # Extract "Features built:" line
  line=$(grep -i "features built" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    FEATURES_BUILT=$(echo "$line" | sed 's/.*features built[[:space:]]*:[[:space:]]*//i')
  fi

  # Extract "Features remaining:" line
  line=$(grep -i "features remaining" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    FEATURES_REMAINING=$(echo "$line" | sed 's/.*features remaining[[:space:]]*:[[:space:]]*//i')
  fi

  # Extract "Known issues:" line
  line=$(grep -i "known issues" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    KNOWN_ISSUES=$(echo "$line" | sed 's/.*known issues[[:space:]]*:[[:space:]]*//i')
  fi

  # Extract "Last session summary:" line
  line=$(grep -i "last session" CLAUDE.md 2>/dev/null | head -1 || true)
  if [ -n "$line" ]; then
    LAST_SESSION=$(echo "$line" | sed 's/.*last session[[:space:]]*summary[[:space:]]*:[[:space:]]*//i')
  fi
fi

# --- Output the prompt ---

echo -e "${CYAN}--- Copy everything below this line into Claude Code ---${NC}"
echo ""
cat <<PROMPT
We are resuming work on this project. Here is the current state:

**Phase:** $PHASE
**Features built:** $FEATURES_BUILT
**Features remaining:** $FEATURES_REMAINING
**Known issues:** $KNOWN_ISSUES
**Last session:** $LAST_SESSION

**Recent commits:**
$RECENT_COMMITS

Read CLAUDE.md for full project context. Continue from where we left off. If CLAUDE.md's "Current State" section is stale or incomplete, ask me to clarify before proceeding.
PROMPT

echo ""
echo -e "${CYAN}--- End of resume prompt ---${NC}"
```

- [ ] **Step 2: Update init.sh to copy the script**

In init.sh, at the script copying block (around line 449-452), add `resume.sh`:

Change:
```bash
  cp "$SCRIPT_DIR/scripts/validate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-updates.sh" scripts/
  chmod +x scripts/validate.sh scripts/check-phase-gate.sh scripts/check-updates.sh
```

To:
```bash
  cp "$SCRIPT_DIR/scripts/validate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" scripts/
  cp "$SCRIPT_DIR/scripts/check-updates.sh" scripts/
  cp "$SCRIPT_DIR/scripts/resume.sh" scripts/
  chmod +x scripts/validate.sh scripts/check-phase-gate.sh scripts/check-updates.sh scripts/resume.sh
```

- [ ] **Step 3: Update dry_run_summary to list the new script**

In the dry_run_summary function, in the "Files to create" section, add:
```
  echo "  scripts/resume.sh                     — Session resume prompt generator"
```

- [ ] **Step 4: Update print_next_steps to mention resume script**

In the print_next_steps function, in the VALIDATION section (around line 1384-1387), add:
```bash
  echo "     bash scripts/resume.sh               — generate a session resume prompt"
```

- [ ] **Step 5: Verify the script works**

Run: `cd "/Users/karl/Documents/AI Projects/solo-orchestrator" && bash scripts/resume.sh`

Expected: Script outputs a resume prompt with "unknown" phase and "(not found)" for CLAUDE.md fields (since we're in the framework repo, not a generated project).

- [ ] **Step 6: Commit**

```bash
git add scripts/resume.sh init.sh
git commit -m "feat: add session resume prompt generator (scripts/resume.sh)

Reads current phase from .claude/phase-state.json, recent git commits,
and features/issues from CLAUDE.md to construct a resume prompt for
pasting into Claude Code at session start."
```

---

### Task 3: Optional Enhancement Quick Setup

**Review finding:** "A single command or script that configures Superpowers + Context7 + Qdrant together with sensible defaults."

This is best handled as a clearly documented one-shot setup section in the CLI Setup Addendum, since each tool has different prerequisites (Superpowers = plugin install, Context7 = one MCP command, Qdrant = Docker required). A script that wraps all three would be fragile. Instead, add a "Quick Setup — All Recommended Enhancements" section.

**Files:**
- Modify: `docs/cli-setup-addendum.md` (add new section near the top, after the Scope section)

- [ ] **Step 1: Read the CLI Setup Addendum top section to find insertion point**

Read `docs/cli-setup-addendum.md` lines 18-40 to find where to insert the quick setup section.

- [ ] **Step 2: Add Quick Setup section**

After the existing "Purpose" section (with the capability table), before Section 1 (Superpowers), add:

```markdown
## Quick Setup — All Recommended Enhancements

If you want to configure all optional enhancements at once, run these commands from your project directory. Each step is independent — skip any you do not need.

**1. Context7 MCP (one command, no prerequisites):**
```bash
claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
```

**2. Superpowers plugin (one command, no prerequisites):**
```bash
claude plugins add superpowers
```

**3. Qdrant MCP (requires Docker):**
```bash
# Start Qdrant (runs in background)
docker run -d --name qdrant -p 6333:6333 -p 6334:6334 \
  -v qdrant_storage:/qdrant/storage qdrant/qdrant

# Add the MCP server
claude mcp add qdrant --scope user -- npx -y @qdrant/mcp-server-qdrant \
  --qdrant-url http://localhost:6333 \
  --collection-name solo-orchestrator
```

**4. Replace CLAUDE.md with the enhanced template:**
After configuring any of the above, replace your project's `CLAUDE.md` with the enhanced template from [Section 6](#6-claudemd) below and fill in the project-specific sections.

For detailed explanations of each tool and how it integrates with the Builder's Guide, see the individual sections below.
```

- [ ] **Step 3: Commit**

```bash
git add docs/cli-setup-addendum.md
git commit -m "docs(cli-setup-addendum): add quick setup section for all enhancements

Provides copy-paste commands to configure Context7, Superpowers, and
Qdrant in one pass, with a note to replace CLAUDE.md with the enhanced
template afterward."
```

---

### Task 4: Document Map — Add reading guidance note

**Review finding:** "The Document Map still lists 10 documents, which can be intimidating. A note like 'You need this guide, the Intake template, and your Platform Module. Everything else is reference material for specific situations' would set expectations better."

**Files:**
- Modify: `docs/user-guide.md:19-33`

- [ ] **Step 1: Add note after the Document Map table**

After line 32 (the last row of the Document Map table), before the blank line, add:

```markdown

**What you actually need open:** This guide, the [Project Intake](../templates/project-intake.md), and your [Platform Module](platform-modules/). Everything else is reference material — the table above tells you when each document becomes relevant.
```

- [ ] **Step 2: Commit**

```bash
git add docs/user-guide.md
git commit -m "docs(user-guide): add reading guidance to Document Map

Clarifies that users need only three documents open (this guide,
the Intake, and their Platform Module) — everything else is reference."
```

---

### Task 5: User Guide — Inline summary of optional enhancements + CLAUDE.md upgrade timing

**Review findings:** "A brief inline summary of each tool's purpose and whether to configure it now or later" and "The CLAUDE.md upgrade path could be more explicit about timing."

**Files:**
- Modify: `docs/user-guide.md:268-277` (Optional Enhancements subsection)
- Modify: `docs/user-guide.md:234` (CLAUDE.md row in config provenance table)
- Modify: `docs/cli-setup-addendum.md:364` (clarify timing in the relationship note)

- [ ] **Step 1: Expand the Optional Enhancements section with timing guidance**

Replace the Optional Enhancements section (lines 268-277) with:

```markdown
### Optional Enhancements

After init, you can configure additional tooling. These are not required for your first project, but each addresses a specific pain point. **Configure them when you feel the pain, not during initial setup** — except Context7, which is useful from Phase 1.

| Tool | What It Does | When to Configure | Setup Effort |
|---|---|---|---|
| **Context7 MCP** | Gives the AI up-to-date library documentation instead of relying on training data | **Before Phase 1** — helps the AI make accurate architecture and implementation decisions | One command, no prerequisites |
| **Superpowers** | Agentic skills plugin — strict TDD, subagent-driven development, systematic debugging, git worktrees | **Before Phase 2** — accelerates the Build Loop significantly | One command, no prerequisites |
| **Qdrant MCP** | Persistent semantic memory across sessions — the AI remembers project decisions and patterns | **When sessions exceed 3-4** — solves the "where did we leave off?" problem | Requires Docker |

See the [CLI Setup Addendum](cli-setup-addendum.md) for setup instructions, or use the [Quick Setup](cli-setup-addendum.md#quick-setup--all-recommended-enhancements) to configure all three at once.
```

- [ ] **Step 2: Update the CLAUDE.md row in the config provenance table**

Replace line 234:

```markdown
| `CLAUDE.md` | init.sh (starter version) | Update at each phase transition and end of each session | Replace with the enhanced template from the [CLI Setup Addendum](cli-setup-addendum.md#6-claudemd) when you configure optional enhancements |
```

With:

```markdown
| `CLAUDE.md` | init.sh (starter version) | Update at each phase transition and end of each session | The starter version works until you configure optional enhancements. When you add Superpowers, Context7, or Qdrant, replace with the [enhanced template](cli-setup-addendum.md#6-claudemd). |
```

- [ ] **Step 3: Clarify timing in CLI Setup Addendum relationship note**

Replace the relationship note (line 364 of `docs/cli-setup-addendum.md`):

```markdown
**Relationship to init-generated CLAUDE.md:** The init script generates a minimal starter CLAUDE.md with your project name, description, and basic agent instructions. The template below is the full version with Superpowers integration, Context7 usage instructions, Qdrant memory triggers, and phase-evolving sections. **When you configure any optional enhancement (Superpowers, Context7, or Qdrant), replace the init-generated CLAUDE.md with this template** and fill in the project-specific sections.
```

With:

```markdown
**Relationship to init-generated CLAUDE.md:** The init script generates a minimal starter CLAUDE.md that works for Phases 0-1 without optional enhancements. The template below is the full version with Superpowers integration, Context7 usage instructions, Qdrant memory triggers, and phase-evolving sections. **Replace the init-generated CLAUDE.md with this template when you configure your first optional enhancement** (typically before Phase 2). Copy the template, fill in the project-specific sections (project name, phase, track), and delete the placeholder comments.
```

- [ ] **Step 4: Commit**

```bash
git add docs/user-guide.md docs/cli-setup-addendum.md
git commit -m "docs: clarify optional enhancement timing and CLAUDE.md upgrade path

Expands the Optional Enhancements section with 'when to configure'
guidance. Updates the CLAUDE.md row in the config table and the CLI
Setup Addendum to be explicit about upgrade timing."
```

---

### Task 6: Final verification

- [ ] **Step 1: Verify cross-file consistency**

Check that:
- The User Guide's Optional Enhancements table tool names match the CLI Setup Addendum section names
- The security scan guide is referenced from the User Guide
- The resume script is mentioned in print_next_steps and dry_run_summary
- init.sh copies the new files (resume.sh, security-scan-guide.md)
- init.sh syntax is clean (`bash -n init.sh`)

- [ ] **Step 2: Commit any final fixes**

```bash
git add -A
git commit -m "docs: complete technical user review resolutions (round 2)"
```

# Security Scan Interpretation Guide

Quick reference for the most common findings from Semgrep and Snyk in the Solo Orchestrator recommended stacks (Next.js/TypeScript, Python/FastAPI). For each finding: what it means, whether it is likely real, and how to fix it.

---

## Semgrep — 10 Most Common Findings

### 1. XSS / dangerouslySetInnerHTML

**Rule:** `javascript.express.security.audit.xss.mustache-escape` / `typescript.react.security.audit.react-dangerouslysetinnerhtml`

**What it means:** You are inserting user-controlled data into HTML without escaping. An attacker could inject `<script>` tags.

**Likely real?** Yes, unless the content is sanitized upstream with a library like DOMPurify or comes from a trusted internal source (not user input).

**Fix:** Use framework-native rendering (React's JSX auto-escapes by default). If you must use `dangerouslySetInnerHTML`, sanitize with DOMPurify first:
```typescript
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userContent) }} />
```

---

### 2. Non-literal RegExp

**Rule:** `javascript.lang.security.audit.detect-non-literal-regexp`

**What it means:** A regular expression is being constructed from a variable, not a string literal. If that variable contains user input, an attacker could craft input that causes catastrophic backtracking (ReDoS).

**Likely real?** Only if the variable comes from user input. If it comes from configuration or hardcoded values, this is a false positive.

**Fix:** If user input, use a library like `safe-regex` to validate the pattern, or avoid building regexes from user data entirely.

---

### 3. Timing attack on secret comparison

**Rule:** `javascript.lang.security.audit.detect-possible-timing-attacks`

**What it means:** You are comparing secrets (API keys, tokens, passwords) using `===` instead of a constant-time comparison. An attacker could measure response time differences to guess the secret character by character.

**Likely real?** Yes, if comparing secrets or tokens. False positive if comparing non-sensitive strings.

**Fix:** Use `crypto.timingSafeEqual`:
```typescript
import { timingSafeEqual } from 'crypto';
const isValid = timingSafeEqual(Buffer.from(provided), Buffer.from(expected));
```

---

### 4. Open redirect in Next.js server-side redirect

**Rule:** `typescript.nextjs.react-nextjs.security.audit.next-server-side-redirect-open-redirect`

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

### 5. eval() with expression

**Rule:** `javascript.lang.security.audit.detect-eval-with-expression`

**What it means:** Code uses `eval()` or `Function()` with a non-literal argument. This allows arbitrary code execution if the argument contains user input.

**Likely real?** Almost always yes. `eval` with user input is a critical vulnerability.

**Fix:** Remove `eval`. Use `JSON.parse()` for data, or restructure logic to avoid dynamic code execution.

---

### 6. Insecure hash algorithm

**Rule:** `python.lang.security.audit.insecure-hash-algorithms`

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

### 7. Raw SQL query

**Rule:** `python.django.security.audit.raw-query` / `python.sqlalchemy.security.sqlalchemy-execute-raw-query`

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

### 8. HTTP without TLS

**Rule:** `python.lang.security.audit.insecure-transport.requests.request-session-with-http`

**What it means:** An HTTP request is being made without TLS (using `http://` instead of `https://`). Data is transmitted in plaintext.

**Likely real?** Yes for production code. False positive for localhost development URLs.

**Fix:** Use `https://` for all non-localhost URLs. If connecting to a local service during development, suppress with an inline comment: `# nosemgrep: insecure-transport`

---

### 9. Hardcoded API key or secret

**Rule:** `generic.secrets.security.detected-generic-api-key`

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

### 10. Insufficient postMessage origin validation

**Rule:** `javascript.browser.security.insufficient-postmessage-origin-validation`

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

### 1. Prototype Pollution (lodash, minimist, qs, or similar)

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

### 5. Denial of Service via crafted input (parsers, serializers, image processors)

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

## License Compliance — Deny Policy

The Phase-3 `license` scanner (`scripts/run-phase3-validation.sh`) does two jobs: it **inventories** every dependency's license (per-language tool: `license-checker` / `pip-licenses` / `cargo license` / `go-licenses` / `dotnet-project-licenses`), and — since **BL-086** — it enforces a **tier-keyed deny policy** on that inventory. It flags **strong copyleft** licenses and either BLOCKS the Phase 3→4 gate or emits a loud warning, depending on the project's tier.

### Default deny list (strong copyleft only)

| Denied (SPDX id or bare acronym) | Why |
|---|---|
| `GPL-2.0*`, `GPL-3.0*` | GNU GPL — file/link-level copyleft; distributing derived work obliges you to release source |
| `AGPL-1.0*`, `AGPL-3.0*` | GNU Affero GPL — copyleft **also triggers on running it as a network service**, no distribution needed |
| `SSPL-1.0` | Server Side Public License (MongoDB) — service-copyleft, not OSI-approved |
| bare `GPL` / `AGPL` | acronym forms some tools emit (`GPLv3`, `AGPLv3`) |

**Explicitly NOT denied:** `LGPL-*` (weak copyleft — dynamic linking is fine), `MPL-*`, `EPL-*`, and all permissive licenses (MIT, Apache-2.0, BSD-*, ISC, …). Matching is on the **license field only** (never package names) and is **boundary-safe**: `LGPL-3.0` never matches a `GPL-3.0` pattern.

**Dual / `OR` licenses pass.** A top-level `OR` expression with any non-denied alternative — e.g. `MIT OR GPL-3.0` — PASSES: the consumer may elect the safe side. An `AND` expression or a bare denied id is flagged.

### The tier rule (who blocks, who warns)

Keyed on the **actual tier** (`deployment` + `poc_mode` from `.claude/phase-state.json`), **never** the spoofable `track`:

| Tier | On a denied license |
|---|---|
| **Organizational** (`deployment=organizational`) | **HARD BLOCK** — Phase 3→4 gate fails |
| **Sponsored POC** (`poc_mode=sponsored_poc`) | **HARD BLOCK** |
| **Private POC** (`poc_mode=private_poc`) | **HARD BLOCK** |
| **Pure personal** (`deployment=personal`, no `poc_mode`; or no phase-state) | **PASS + LARGE warning banner** |

**Why a private POC blocks too (Karl, 2026-07-11).** A strong-copyleft dependency is a **one-way ratchet**. A private POC is the framework's runway to a Sponsored POC / production; at that transition the company must either rip the dependency out, buy a commercial license, or accept share-your-source obligations on distribution or network service. No sponsor approves that, so the whole corporate track is held to the destination tier's standard. Only a purely personal project may proceed — and then only behind a loud warning that the obligation travels with the code if its status ever changes (distributed, sold, run as a commercial service, or moved onto the corporate track).

### Overriding the policy — `.claude/license-policy.json`

An **optional DATA file** (read via `jq`; it is never sourced as a script):

```json
{
  "deny": ["GPL-2.0", "GPL-3.0", "AGPL-3.0", "SSPL-1.0"],
  "allow_packages": ["some-vendored-lib"]
}
```

- **`deny`** — when the key is present, it **replaces** the default stem list entirely (an empty array therefore denies nothing — a deliberate choice). Entries are start-with stems (`MPL-2.0` matches `MPL-2.0`, `MPL-2.0+`, …).
- **`allow_packages`** — exempts named packages (the **commercial-license case**): an entry matches an exact package name or `name@version`. Use this when you have negotiated a commercial license for an otherwise-denied dependency.
- **Malformed JSON → a LOUD scanner FAIL** (never silently ignored).

### Attested exception on a blocked tier

If a blocked-tier project genuinely must ship with a denied license (e.g. a commercial license is in hand but not yet reflected in metadata), attest it — **recorded, never silenced**:

```bash
SOLO_LICENSE_ATTESTED=1 SOLO_LICENSE_REASON="commercial GPL license #12345 on file" \
  bash scripts/run-phase3-validation.sh
```

This appends `{date, packages, licenses, reason}` to `.claude/phase-state.json::phase3.license_exceptions[]`, prints a loud `[ATTESTED]` line, and lets the scanner PASS. **If the record cannot be written, the scanner FAILs** rather than silently green-lighting — an exception you cannot record is an exception you do not get.

### If the scanner blocks you

Do NOT reach for the attestation first. Prefer, in order: (1) find a permissively-licensed alternative dependency; (2) if the license is genuinely dual and one side is safe, confirm the tool reported the full `OR` expression (the scanner honors it); (3) obtain a commercial license and record it via `allow_packages`; (4) only then, if a deliberate exception is warranted, attest it (organizational deployments: get Legal sign-off first).

# Solo Orchestrator Platform Module: Web Applications

## Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-PM-WEB |
| **Version** | 1.0 |
| **Classification** | Platform Module |
| **Date** | 2026-04-02 |
| **Parent Document** | SOI-002-BUILD v1.0 — Solo Orchestrator Builder's Guide |

---

## Scope

This module covers web applications: frontend SPAs, full-stack applications, backend APIs, and static sites deployed to cloud hosting. It addresses both client-rendered (React, Vue, Svelte) and server-rendered (Next.js, Nuxt, SvelteKit) architectures.

---

## 1. Architecture Patterns

### 1.1 Framework Selection

| Framework | Language | Rendering | Best For |
|---|---|---|---|
| **Next.js** | TypeScript/JavaScript | SSR, SSG, ISR, Client | Full-stack apps with SEO needs, dashboards, SaaS products |
| **React + Vite** | TypeScript/JavaScript | Client-side (SPA) | Internal tools, dashboards, SPAs where SEO doesn't matter |
| **SvelteKit** | TypeScript/JavaScript | SSR, SSG, Client | Performance-focused apps, smaller bundle size |
| **Nuxt** | TypeScript/JavaScript | SSR, SSG, Client | Vue ecosystem. Similar to Next.js. |
| **Express / Fastify** | TypeScript/JavaScript | API only | Backend APIs consumed by separate frontends or mobile apps |
| **FastAPI** | Python | API only | Data-heavy backends, ML integration, Python ecosystem |

**Solo Orchestrator recommendation:** Next.js for full-stack, React + Vite for SPAs, Express/FastAPI for API-only backends. AI generates TypeScript/JavaScript with the highest consistency.

### 1.2 Hosting & Deployment

| Tier | Primary | Alternatives | Cost |
|---|---|---|---|
| **Frontend** | Vercel | Netlify, Cloudflare Pages, AWS Amplify | $0-$20/month |
| **Backend** | Railway | Render, Fly.io, AWS App Runner | $5-$20/month |
| **Database** | Supabase | PlanetScale, Neon, self-hosted PostgreSQL | $0-$25/month |
| **Full-stack** | Vercel (Next.js) | Railway (any framework), Render | $0-$20/month |

### 1.3 Database & Auth

**Database:** Supabase (managed PostgreSQL with RLS) for most Solo Orchestrator projects. PostgreSQL via Railway or Neon for projects that don't need Supabase's auth or real-time features.

**Auth:** Supabase Auth, Auth0, Clerk, or enterprise SSO (SAML/OIDC). Selection depends on whether the application needs enterprise SSO integration (see Governance Framework).

**Row Level Security:** PostgreSQL/Supabase support native RLS. Other databases require middleware-based authorization checks.

**Migrations:** Use a versioned migration tool: Prisma (no automatic down migrations — write rollback scripts manually), Knex, Flyway, Alembic (all support automatic up/down).

---

## 2. Tooling

### 2.1 Pre-Build Setup (Web-Specific)

In addition to the Builder's Guide Pre-Build Setup:

**License compliance:**
```bash
# Node.js projects
npm install -g license-checker
# Python projects
pip install pip-licenses
```

**OWASP ZAP (DAST):**
```bash
docker pull ghcr.io/zaproxy/zaproxy:stable
```

**Playwright (E2E) — installed per-project in Phase 3:**
```bash
npm init playwright@latest
```

**Lighthouse (Performance & Accessibility):**
```bash
npm install -g lighthouse
```

### 2.2 Monitoring Accounts

Create accounts now; configure during Phase 4:
- **Sentry:** sentry.io (error tracking)
- **UptimeRobot:** uptimerobot.com (uptime monitoring)
- **PostHog** or **Plausible:** (product analytics)

---

## 3. Build & Packaging

Web applications don't have traditional "packaging" — they're deployed to hosting platforms. The build pipeline produces optimized static assets or a server bundle.

**CI/CD pipeline additions (web-specific):**
```yaml
# Add to the Builder's Guide CI configuration:
- name: Build
  run: npm run build
- name: DAST Scan (Phase 3+)
  run: docker run -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t $PREVIEW_URL
```

**Bundle optimization:**
```bash
# Next.js
ANALYZE=true npm run build
# Vite
npx vite-bundle-visualizer
```

---

## 4. Testing

### 4.1 E2E Testing

**Tool:** Playwright

```bash
npm init playwright@latest
npx playwright test
```

Automate the full User Journey from the Product Manifesto. Run in CI on every push.

### 4.2 DAST (Dynamic Application Security Testing)

```bash
# Baseline scan (passive — catches common issues)
docker run -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t http://localhost:3000

# Active scan (Full Track — more thorough, slower)
docker run -t ghcr.io/zaproxy/zaproxy:stable zap-full-scan.py -t http://localhost:3000
```

Fix anything rated Medium or higher.

### 4.3 Performance & Accessibility

**Lighthouse:**
```bash
npx lighthouse http://localhost:3000 --output html --output-path ./lighthouse-report.html
```

Targets: Accessibility ≥90, Performance ≥90.

**Beyond Lighthouse (Full Track):** Test with a screen reader (VoiceOver, NVDA) and keyboard-only navigation.

### 4.4 Content Security Policy

1. Generate a CSP header. Start with `default-src 'self'`.
2. Deploy in report-only mode (`Content-Security-Policy-Report-Only`) first.
3. Test the full application. Fix violations.
4. Switch to enforcement mode.
5. Document the policy in the Project Bible.

AI-generated CSP policies tend to be too permissive or too restrictive. Test thoroughly.

### 4.5 Load Testing (Full Track)

```bash
# macOS
brew install k6

# Windows
winget install k6

# Docker (any platform)
docker pull grafana/k6
```

Define realistic user scenarios. Ramp to expected peak traffic. Identify bottlenecks.

---

## 5. Deployment & Distribution

### 5.1 Deployment

**Vercel (frontend or full-stack Next.js):**
1. Connect GitHub repository → Import Project → Select repo
2. Configure environment variables with production values
3. Configure custom domain
4. Push to `main` → automatic deployment

**Railway (backend or database):**
1. Connect GitHub repository → New Project → Deploy from GitHub
2. Add managed PostgreSQL if needed
3. Configure environment variables

**Supabase (database & auth):**
1. Create project at supabase.com
2. Push production migration: `npx supabase db push`
3. Configure RLS policies and auth providers
4. Copy production URLs/keys to hosting platform env vars

**Database backup:** Configure daily automated backups. Test restoration.

### 5.2 Go-Live Checklist (Web-Specific)

In addition to the Builder's Guide Phase 4.2:

- [ ] SSL certificate valid
- [ ] Security headers set:
  - `Content-Security-Policy` (from Phase 3)
  - `Strict-Transport-Security` (HSTS)
  - `X-Frame-Options: DENY` or `SAMEORIGIN`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
- [ ] CORS: only allowed origins, no wildcard on authenticated endpoints
- [ ] Cookies: `HttpOnly`, `Secure`, `SameSite` flags
- [ ] Rate limiting on auth endpoints
- [ ] Lighthouse scores meet targets on production URL

### 5.3 Monitoring Setup

**Sentry:**
```bash
npm install @sentry/nextjs  # or @sentry/[framework]
```
Alert rules: new unhandled exception → email; error rate >2% in 10 min → email + SMS.

**UptimeRobot:**
HTTP(s) monitor on production URL + health check endpoint, 5-minute interval.

---

## 6. Maintenance (Web-Specific)

In addition to the Builder's Guide maintenance cadence:

**Monthly:**
- `npm audit` / `snyk test`
- Review hosting costs against budget
- Verify SSL certificate auto-renewal

**Quarterly:**
- Lighthouse performance audit on production
- Review analytics: user behavior, conversion, error rates
- Check hosting platform for pricing or feature changes

**Biannually:**
- Full Phase 3 security audit re-run
- Framework major version evaluation
- Hosting vendor evaluation (should we migrate?)

### Vulnerability Disclosure

Every production web application MUST include a vulnerability disclosure mechanism:

1. Add a `SECURITY.md` file to the repository with:
   - Supported versions (which releases receive security updates).
   - How to report a vulnerability (email address or security advisory form — not a public issue).
   - Expected response time (acknowledge within 48 hours, assess within 7 days).
   - Safe harbor statement (reporters acting in good faith will not face legal action).
2. Add a `/.well-known/security.txt` route to the web application per RFC 9116, pointing to the disclosure email.
3. For organizational deployments, route reports to the enterprise security team, not the Orchestrator directly.

### Application Sunsetting

When a web application is being decommissioned:

1. **Notify users.** Provide at least 30 days notice via in-app banner and email (if applicable).
2. **Data export.** Provide a self-service data export mechanism before shutdown.
3. **Redirect.** After shutdown, serve a static page explaining the application has been retired and linking to any successor.
4. **DNS and SSL.** Maintain domain ownership and a valid SSL certificate on the redirect page to prevent domain hijacking.
5. **Data deletion.** Delete production databases containing user data per the data retention policy. Document deletion in the APPROVAL_LOG.md.
6. **ITSM closure.** Close the project registration in the enterprise ITSM system.

---

## 7. Phase-Specific Additions

### Phase 1 — Architecture Selection (Append to Core Prompt)

```
WEB-SPECIFIC REQUIREMENTS:
11. Frontend framework and rendering strategy (SSR, SSG, SPA)
12. Hosting platform (PaaS preferred)
13. Database and migration tooling
14. Authentication provider and token strategy (JWT vs. sessions)
15. CDN and caching strategy
16. API versioning strategy (if API is consumed externally)
```

### Phase 2 — Project Initialization (Append to Core Steps)

- [ ] `.env.example` with all required environment variables
- [ ] Health check endpoint (`/health`) returning 200
- [ ] CORS configuration
- [ ] Structured logging with correlation IDs

**Python lockfile note:** The `process-checklist.sh --verify-init` script checks for lockfiles to ensure reproducible builds. For Python projects, only `Pipfile.lock` (Pipenv) and `poetry.lock` (Poetry) are detected as valid lockfiles. A plain `requirements.txt` is NOT recognized as a lockfile because it does not guarantee pinned transitive dependencies. If using pip directly, adopt one of these approaches:

- **Recommended:** Use Poetry (`poetry init`, `poetry lock`) or Pipenv (`pipenv install`) to get a proper lockfile.
- **Alternative:** Use `pip-compile` from `pip-tools` to generate a fully-pinned `requirements.txt` from `requirements.in`, then rename or symlink to a recognized lockfile format.

Node.js projects use `package-lock.json` (npm) or `yarn.lock` (Yarn), both of which are auto-detected.

**Emitted-CI script contract (TypeScript/JavaScript) — BL-159:** The CI pipeline the framework generates for your project runs `npm run lint` and `npm test` unconditionally — and the GitHub lane also runs `npm run build` (its Build step precedes Lint). Your `package.json` MUST define working `lint` and `test` scripts (plus `build` on GitHub) before the first push, or the CI lane fails out of the box (a check that cannot run must not pass — the lane fails loudly rather than silently skipping). Two sharp edges to know:

- **ESLint ≥ 9 requires a flat config file** (`eslint.config.js` / `.mjs` / `.cjs`) — the legacy `.eslintrc.*` formats are no longer read by default. A project without a flat config fails `npm run lint` with `ESLint couldn't find an eslint.config.(js|mjs|cjs) file`. Minimal TypeScript starting point: `typescript-eslint`'s `tseslint.config(eslint.configs.recommended, ...tseslint.configs.recommended)`. Verify it is non-vacuous (it must actually flag a planted issue) before trusting the lane.
- **The dependency-audit step is split** (BL-160): the blocking arm runs `npm audit --omit=dev` at the pipeline's audit level — the shipped dependency tree must be clean. Dev-toolchain advisories are reported by a separate loud, non-blocking arm; review them locally with `npm audit` and plan upgrades deliberately (they frequently have no in-major fix).

### Phase 3 — Security (Append to Core Steps)

- [ ] CSP implemented and tested (Step 3.2.5 from previous guide versions)
- [ ] DAST scan completed (ZAP baseline minimum, active for Full Track)
- [ ] SBOM generated: `npx @cyclonedx/cyclonedx-npm --output-file sbom.json`

**Platform-specific SAST tools:** Semgrep (referenced in the Builder's Guide) is the primary SAST tool and covers JavaScript, TypeScript, and Python well. For additional coverage, consider ecosystem-specific analyzers:

| Ecosystem | SAST Tool | Notes |
|---|---|---|
| **TypeScript / JavaScript** | ESLint with `eslint-plugin-security` | Detects unsafe regex, `eval()` usage, non-literal `require()`, and other Node.js security anti-patterns. Add alongside Semgrep for defense in depth. |
| **Python** | Bandit (`pip install bandit`) | Python-specific security linter. Detects hardcoded passwords, use of `eval()`/`exec()`, insecure deserialization, weak cryptography. Run in CI: `bandit -r src/ -ll` (report medium+ severity). |

These complement Semgrep and should run in CI alongside it.

### Phase 4 — Release & Maintenance (Append to Core Steps)

The Builder's Guide Phase 4 baseline (mechanically tracked by `scripts/process-checklist.sh --start-phase4`) enumerates six steps: `production_build`, `rollback_tested`, `go_live_verified`, `monitoring_configured`, `handoff_written`, `handoff_tested`. Web platform deliverables for each:

- [ ] **`production_build`** — Vercel "Production" deployment for frontend / full-stack Next.js (verify the build log shows the prod environment + prod env vars, NOT the preview/staging environment); Railway "Deploy" against the production service for backend; Supabase "Production" project for database. Tag the release commit (`git tag -s vX.Y.Z`) so the deployment is reproducible.
- [ ] **`rollback_tested`** — Exercise the documented rollback path BEFORE go-live, not after the first incident. Procedure depends on hosting:
  - **Vercel:** Deployments → previous successful deployment → "Promote to Production" (instant — Vercel keeps prior immutable deployments). Time the promotion and verify production traffic now hits the rolled-back build.
  - **Railway:** Re-deploy from the prior Git tag (`git checkout vX.Y.(Z-1) && railway up`) OR use Railway's per-service "Redeploy" against a prior deployment. Verify env vars and DB connection on the rolled-back build.
  - **Database migrations:** dry-run the down-migration on a staging copy (`npx prisma migrate resolve --rolled-back …` for Prisma without auto-down; `knex migrate:rollback` for Knex; etc.). If a migration is destructive (drops a column, drops a table), document an explicit data-restore script — automated rollback cannot recover deleted user data.
  - Save evidence at `docs/test-results/[YYYY-MM-DD]_rollback-test.md` covering: which deploy was promoted, wall-clock duration of the rollback, production verification (URL + smoke-test result + log excerpt), and an explicit Light/Standard+/Full Track scope statement (Light = manual Vercel/Railway promote + smoke; Standard+ = automated rollback script under `scripts/rollback.sh`; Full = chaos-style scheduled rollback drill, archived as a separate test session).
- [ ] **`go_live_verified`** — Walk the §5.2 Go-Live Checklist on the PRODUCTION URL (not preview). SSL valid; security headers present (run `curl -I https://your.app` and assert `Content-Security-Policy`, `Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`); CORS not wildcarded on authenticated endpoints; cookies carry `HttpOnly; Secure; SameSite`; rate-limit on `/auth/*`; Lighthouse run against the production URL meets the §4.3 targets (Accessibility ≥ 90, Performance ≥ 90).
- [ ] **`monitoring_configured`** — Sentry release set to the deployed tag (`@sentry/cli releases new vX.Y.Z && releases finalize vX.Y.Z`) so errors are correlated to the deploy; alert rules per §5.3 active and tested (trigger a deliberate error in a non-prod build and confirm the email/SMS fires); UptimeRobot HTTP(S) monitor on `https://your.app/health` at the 5-minute interval; PostHog or Plausible page-load event flowing from the production URL.
- [ ] **`handoff_written`** — `docs/HANDOFF.md` populated from `templates/generated/handoff.tmpl`. Web-specific sections that MUST be filled (not left as placeholder): hosting-platform login / billing-owner, custom-domain registrar + DNS-record list with TTLs, env-var inventory grouped by deploy environment (preview vs. production), database-backup retention policy + restore procedure with last-tested date, monitoring tool URLs + on-call contact, vulnerability-disclosure inbox per §6 "Vulnerability Disclosure".
- [ ] **`handoff_tested`** — A second operator (or the same operator after a deliberate 24-hour cooldown to defeat fresh-memory bias) executes `docs/HANDOFF.md` end-to-end on a clean machine: log into Vercel, log into Railway, log into Supabase, pull the latest tag, run a fresh deploy to a preview environment, restore one database backup to a scratch DB, simulate one alert. Any step that required tribal knowledge not in the doc gets captured as a HANDOFF.md fix in the same session.

**Incident response template:** `templates/generated/incident-response.tmpl` is included in the standard init scaffold and should be customized at this phase. The web-specific addition: link the template's "Detection" section to your Sentry alert URLs and the "Mitigation" section to the rollback procedure documented under `rollback_tested`.

**Release notes:** `templates/generated/release-notes.tmpl` covers the user-visible summary. For web apps, append a "Browser support" line (especially when changing minimum browser versions) and a "Database migration" line indicating whether the release requires a down-migration window.

---

## Appendix: Tool Quick Reference

| Tool | Install | Purpose |
|---|---|---|
| Semgrep | `pip install semgrep` | SAST |
| gitleaks | `brew install gitleaks` | Secret detection |
| OWASP ZAP | `docker pull ghcr.io/zaproxy/zaproxy:stable` | DAST |
| license-checker | `npm install -g license-checker` | License compliance (Node.js) |
| Snyk | `npm install -g snyk` | Dependency scanning |
| CycloneDX | `npx @cyclonedx/cyclonedx-npm` | SBOM generation |
| Playwright | `npm init playwright@latest` | E2E testing |
| Lighthouse | `npm install -g lighthouse` | Performance/accessibility |
| PostHog | `npm install posthog-js` | Analytics |
| Sentry | `npm install @sentry/[framework]` | Error tracking |
| k6 | `brew install k6` / `winget install k6` | Load testing |

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

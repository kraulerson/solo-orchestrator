# Solo Orchestrator Platform Module: Desktop Applications

## Standalone & Client-Server

### Version 1.0

---

## Document Control

| Field | Value |
|---|---|
| **Document ID** | SOI-PM-DESKTOP |
| **Version** | 1.0 |
| **Classification** | Platform Module |
| **Date** | 2026-04-02 |
| **Parent Document** | SOI-002-BUILD v1.0 — Solo Orchestrator Builder's Guide |

---

## Scope

This module covers desktop applications distributed as installable or portable executables for Windows, macOS, and/or Linux. It addresses two architectural patterns:

- **Standalone:** Self-contained applications with local data storage. No server dependency. Fully offline-capable.
- **Client-Server:** Desktop application that communicates with a backend service (local or remote) for data sync, user accounts, or shared resources.

This module is referenced from the Builder's Guide at `⟁ PLATFORM MODULE` callout points. Follow the Builder's Guide for methodology; follow this module for platform-specific implementation.

---

## 1. Architecture Patterns

### 1.1 Framework Selection

Desktop applications require a framework that provides: a native window shell, access to OS-level APIs (file system, system tray, native dialogs, notifications), and a packaging/distribution pipeline. The major options:

| Framework | Language | Binary Size | Performance | OS API Access | Learning Curve | Best For |
|---|---|---|---|---|---|---|
| **Tauri** | Rust (backend) + HTML/CSS/JS (frontend) | 5-15 MB | Excellent — native webview, Rust backend | Full via Rust | Steep if no Rust experience. Frontend is standard web tech. | Performance-critical, small binary, security-focused apps |
| **Electron** | JavaScript/TypeScript (full stack) | 100-200 MB | Good — Chromium + Node.js | Full via Node.js | Low if you know JS/TS | Feature-rich apps where binary size is acceptable, rapid development |
| **Flutter Desktop** | Dart | 20-40 MB | Good — compiled native | Moderate — via plugins | Moderate | Cross-platform with mobile (shared codebase) |
| **.NET MAUI** | C# | 30-60 MB | Good — native controls | Full via .NET | Moderate if you know C# | Windows-primary with macOS/Linux secondary |
| **Qt** | C++ or Python (PyQt/PySide) | 30-80 MB | Excellent — native rendering | Full | Steep (C++) / Moderate (Python) | High-performance, complex UIs, industrial applications |

**Solo Orchestrator recommendation for AI-directed development:**

- **If binary size and performance are priorities:** Tauri. The Rust backend is harder for AI to generate correctly, but the frontend is standard web tech. AI handles the frontend well; scrutinize the Rust backend more carefully.
- **If development speed is the priority and binary size is acceptable:** Electron. AI generates JavaScript/TypeScript with the highest consistency. Largest community, most examples in training data.
- **If you're also building mobile:** Flutter Desktop. Shared codebase across desktop and mobile is a genuine advantage, but Flutter desktop support is less mature than mobile.

**For the Competency Matrix:** If the selected framework uses a language the Orchestrator marked "No" for validation, automated testing coverage must be higher (>80% minimum) and the AI's output in that language needs more manual review during the Build Loop.

### 1.2 Architecture Decision: Standalone vs. Client-Server

| Consideration | Standalone | Client-Server |
|---|---|---|
| **Data location** | Local file system, embedded database (SQLite), or application state | Local cache + remote database/API |
| **Offline capability** | Full — no network dependency | Partial — core features offline, sync when connected |
| **User accounts** | None or local-only profiles | Server-managed auth (OAuth, SSO, custom) |
| **Multi-device sync** | Not applicable | Requires sync strategy (conflict resolution, merge logic) |
| **Deployment** | Ship the binary, done | Ship the binary + deploy/maintain the server |
| **Complexity** | Lower | Significantly higher — two systems to build and maintain |

**For client-server applications:** The server component follows the Web Platform Module for its architecture. This module covers the desktop client. The builder maintains two codebases (or a monorepo with two build targets).

### 1.3 Data Storage Options

| Option | Use Case | Considerations |
|---|---|---|
| **SQLite (embedded)** | Structured data, queryable, ACID transactions | Best default for standalone apps. Ships with the application. No server needed. |
| **File system (direct)** | Document-centric apps (editors, viewers, creative tools) | Application reads/writes user files directly. No database layer. |
| **LevelDB / RocksDB** | Key-value storage, high write throughput | Embedded, no server. Good for caching, session state. |
| **JSON/YAML config files** | Application settings, user preferences | Keep it simple. Don't use for large datasets. |
| **Remote database via API** | Client-server architecture | Desktop client calls API; database lives on server. |

For applications using SQLite: use a migration tool (such as `better-sqlite3` with manual migrations for Node.js, or `sqlx` with migrations for Rust) to version data model changes.

### 1.4 Auto-Update Strategy

Users of desktop applications do not automatically get the latest version. Plan for updates:

| Strategy | Implementation | Trade-offs |
|---|---|---|
| **Framework-native updater** | Tauri: built-in updater. Electron: `electron-updater`. | Simplest. Checks for updates on launch, downloads in background. |
| **.NET MAUI updates** | MSIX via Microsoft Store (auto-update managed by Store), WinGet package (update via `winget upgrade`), or manual download from release page. MAUI does not include a built-in updater — choose an external mechanism. | Store distribution handles updates automatically but requires Store onboarding. WinGet and manual download require users to act. |
| **Manual download** | User downloads new version from website/release page | No infrastructure needed. Users must actively update. Acceptable for MVP. |
| **Package manager** | Homebrew (macOS), winget/Chocolatey (Windows), apt/snap/flatpak (Linux) | Leverages existing update infrastructure. More setup for the builder. |
| **No auto-update** | Versioned releases only | Simplest. Acceptable for Light Track and early MVPs. |

**MVP recommendation:** Start with manual download (GitHub Releases or direct download page). Add auto-update post-MVP once the product stabilizes.

---

## 2. Tooling

### 2.1 Pre-Build Setup (Platform-Specific)

In addition to the Builder's Guide Pre-Build Setup:

**Tauri:**
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup update stable
# Install Tauri CLI
cargo install tauri-cli
# Platform prerequisites:
# macOS: Xcode Command Line Tools (xcode-select --install)
# Linux: sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file \
#   libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
# Windows: Microsoft Visual Studio C++ Build Tools, WebView2 (pre-installed on Windows 11)
```

**Electron:**
```bash
# Node.js 18+ required (should already be installed for Claude Code)
npm install --save-dev electron electron-builder
# No additional platform-specific prerequisites
```

**Flutter Desktop:**
```bash
# Install Flutter SDK
# https://docs.flutter.dev/get-started/install
flutter doctor  # Verify desktop support for your platforms
flutter config --enable-[windows|macos|linux]-desktop
```

### 2.2 License Compliance Tooling

Depends on your ecosystem:

| Ecosystem | Tool | Install | CI Check |
|---|---|---|---|
| **Node.js** (Electron, Tauri frontend) | `license-checker` | `npm install -g license-checker` | `license-checker --failOn "GPL-2.0;GPL-3.0;AGPL-3.0"` |
| **Rust** (Tauri backend) | `cargo-license` | `cargo install cargo-license` | `cargo license --avoid-build-deps --avoid-dev-deps` (review output) |
| **Python** (PyQt/PySide) | `pip-licenses` | `pip install pip-licenses` | `pip-licenses --fail-on="GNU General Public License v2 (GPLv2);GNU General Public License v3 (GPLv3);GNU Affero General Public License v3 (AGPLv3)"` |
| **Dart** (Flutter) | `dart_license_checker` | `dart pub global activate dart_license_checker` | `dart pub global run dart_license_checker --fail-on "GPL-2.0,GPL-3.0,AGPL-3.0"` |
| **C#** (.NET MAUI) | `dotnet-project-licenses` | `dotnet tool install --global dotnet-project-licenses` | `dotnet-project-licenses --input . --fail-on "GPL-2.0-only;GPL-3.0-only;AGPL-3.0-only"` |

Both direct and transitive dependencies must be checked.

---

## 3. Build & Packaging

### 3.1 Cross-Platform Build Matrix

Configure CI to build on all target platforms. Most desktop frameworks require building ON the target platform (cross-compilation is possible but fragile).

**GitHub Actions example (Tauri):**
```yaml
strategy:
  matrix:
    include:
      - os: windows-latest
        target: windows
      - os: macos-latest
        target: macos
      - os: ubuntu-latest
        target: linux
runs-on: ${{ matrix.os }}
```

**GitHub Actions example (Electron):**
```yaml
strategy:
  matrix:
    os: [windows-latest, macos-latest, ubuntu-latest]
runs-on: ${{ matrix.os }}
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-node@v4
  - run: npm ci
  - run: npx electron-builder --publish never
```

### 3.2 Packaging Formats

| Platform | Format | Tool |
|---|---|---|
| **Windows** | `.msi` (installer) or `.exe` (NSIS installer) or portable `.exe` | electron-builder, tauri bundler, WiX (MSI) |
| **macOS** | `.dmg` (disk image) or `.app` bundle | electron-builder, tauri bundler, `create-dmg` |
| **Linux** | `.AppImage` (portable), `.deb` (Debian/Ubuntu), `.rpm` (Fedora), Flatpak, Snap | electron-builder, tauri bundler, `appimagetool`, platform-specific tools |

**MVP recommendation:** `.exe` installer (Windows) + `.dmg` (macOS) + `.AppImage` (Linux). These cover the broadest user base with the least packaging complexity.

### 3.3 Code Signing

Unsigned applications trigger security warnings on Windows (SmartScreen) and macOS (Gatekeeper). For MVP/Light Track, this is acceptable with documentation. For Standard+ Track, code signing is required for credible distribution.

| Platform | Certificate Source | Cost | Notes |
|---|---|---|---|
| **Windows** | EV Code Signing Certificate (DigiCert, Sectigo, etc.) | $200-$500/year | EV eliminates SmartScreen warnings. Standard certificates reduce but don't eliminate them. |
| **macOS** | Apple Developer Program | $99/year | Required for notarization. Without it, users must bypass Gatekeeper manually. |
| **Linux** | GPG signing | Free | Sign packages and checksums. Less critical for user trust, more for package manager distribution. |

**CI integration:** Code signing should happen in CI, not on the developer's machine. Store signing certificates as CI secrets.

### 3.4 Binary Size Optimization

| Framework | Typical Size | Optimization |
|---|---|---|
| **Tauri** | 5-15 MB | Already small. `cargo build --release` with LTO. Strip debug symbols. |
| **Electron** | 100-200 MB | Use `electron-builder` with ASAR packaging. Exclude unnecessary files. Consider `electron-packager` with `--prune`. |
| **Flutter** | 20-40 MB | `flutter build [platform] --release`. Tree-shaking is automatic. |

---

## 4. Testing

### 4.1 Integration/E2E Testing

| Framework | E2E Testing Tool | Notes |
|---|---|---|
| **Tauri** | WebDriver (via `tauri-driver`) or Playwright (webview content) | `tauri-driver` provides WebDriver protocol. Playwright can test the web content inside the webview. |
| **Electron** | Playwright (`electron` launch option) or Spectron (deprecated — use Playwright) | Playwright has first-class Electron support: `const app = await electron.launch({ args: ['main.js'] })` |
| **Flutter** | `integration_test` package | Built-in. `flutter test integration_test/` |
| **.NET MAUI** | Appium or WinAppDriver (Windows) | Less mature than web E2E testing. May require platform-specific test suites. |

**Minimum E2E coverage:** Automate the complete User Journey (Phase 0 Success Path) on at least one platform. Run manually on the others for MVP. Full automation on all platforms for Standard+ Track.

### 4.2 Platform-Specific Testing Checklist

Run on each target platform before release:

**All platforms:**
- [ ] Application launches without errors
- [ ] Core user journey completes
- [ ] File system operations work (open, save, create, delete as needed)
- [ ] Application handles missing/corrupt data files gracefully
- [ ] Memory usage is stable over extended use (no leaks)
- [ ] Application closes cleanly (no orphaned processes)

**Windows-specific:**
- [ ] Works on Windows 10 and Windows 11
- [ ] Handles high-DPI displays correctly
- [ ] Installer registers uninstaller in Add/Remove Programs
- [ ] File associations work (if applicable)
- [ ] Application doesn't require admin privileges for normal operation

**macOS-specific:**
- [ ] Works on the minimum supported macOS version
- [ ] Works on both Intel and Apple Silicon (universal binary or separate builds)
- [ ] Retina display rendering is correct
- [ ] Application menu bar follows macOS conventions (About, Preferences, Quit)
- [ ] Drag-and-drop works (if applicable)
- [ ] Notarization passes (Standard+ Track)

**Linux-specific:**
- [ ] Works on Ubuntu (Debian-based) and at least one other distro (Fedora, Arch)
- [ ] Wayland and X11 compatibility (or document which is required)
- [ ] Correct permissions — doesn't require root for normal operation
- [ ] System tray integration works (if applicable)
- [ ] Font rendering is acceptable across distros

### 4.3 Accessibility Testing

Desktop accessibility APIs vary by platform:

| Platform | Accessibility API | Testing Tool | Minimum Test |
|---|---|---|---|
| **Windows** | UI Automation / MSAA | Accessibility Insights for Windows (free, Microsoft) | Run automated scan + manual keyboard navigation test |
| **macOS** | NSAccessibility | Accessibility Inspector (included in Xcode) | Run VoiceOver on primary user journey |
| **Linux** | AT-SPI | Accerciser (GNOME) | Verify Orca screen reader reads primary controls |
| **Web-based UI (Tauri/Electron)** | ARIA + platform bridge | axe-core, Lighthouse (on webview content) | Run axe-core scan + keyboard navigation test |

For Tauri and Electron: the web content is testable with standard web accessibility tools. The native shell (menus, dialogs, system tray) needs platform-specific testing.

### 4.4 Performance Testing

| Metric | Target | How to Measure |
|---|---|---|
| **Cold start time** | <3 seconds on minimum supported hardware | Time from launch to interactive UI |
| **File open time** | Scales linearly with file size; large files (<500 pages, <100MB) open in <5 seconds | Benchmark with representative files |
| **Memory usage (idle)** | <200 MB base, scaling linearly with open documents | OS task manager / process monitor during extended use |
| **Memory leaks** | Zero — stable memory after open/close cycles | Open and close documents repeatedly; memory should return to baseline |
| **Rendering performance** | Smooth scrolling, no visual lag | Manual testing with large/complex documents |

### 4.5 Security Checks (Desktop-Specific)

In addition to the Builder's Guide Phase 3.2 security hardening:

- [ ] **No elevated privileges:** Application does not request or require admin/root for normal operation
- [ ] **Safe file handling:** Path traversal protection on all file operations. Validate file paths before read/write. Don't follow symlinks outside expected directories.
- [ ] **IPC security (if using):** Inter-process communication channels are authenticated and validated. Tauri: configure `allowlist` / CSP for IPC commands. Electron: validate all IPC messages in main process.
- [ ] **Webview isolation (Tauri/Electron):** Webview content cannot execute arbitrary Node.js/Rust code. Context isolation enabled. `nodeIntegration: false` (Electron). Tauri: commands exposed via `#[tauri::command]` only.
- [ ] **Auto-updater security (if using):** Update downloads are signed and verified. HTTPS only. Certificate pinning recommended.
- [ ] **Local data protection:** Sensitive local data (credentials, tokens) stored using OS keychain (Keytar, macOS Keychain, Windows Credential Manager) — not plain text config files.

**Platform-specific SAST tools:** Semgrep (referenced in the Builder's Guide) covers JavaScript/TypeScript and Python. For other desktop ecosystems, add platform-specific static analysis:

| Ecosystem | SAST Tool | Notes |
|---|---|---|
| **.NET / C# (MAUI, WPF)** | Roslyn analyzers (built-in), Security Code Scan | Security Code Scan is a Roslyn analyzer NuGet package that detects SQL injection, XSS, CSRF, and other OWASP Top 10 issues in C# code. Enable via `dotnet add package SecurityCodeScan.VS2019`. |
| **Java / Kotlin (desktop)** | SpotBugs, Find Security Bugs | Find Security Bugs is a SpotBugs plugin focused on security. Add to Gradle: `spotbugs { toolVersion = '4.x' }` with `spotbugsPlugins 'com.h3xstream.findsecbugs:findsecbugs-plugin:1.x'`. |
| **Rust (Tauri backend)** | `cargo audit`, `cargo clippy` | `cargo audit` checks dependencies for known vulnerabilities. `cargo clippy` catches common mistakes including some security-relevant patterns. Both should run in CI. |

These complement Semgrep — they catch language-specific issues that a polyglot SAST tool may miss.

### Rate Limiting (Client-Server Desktop Apps)

For desktop applications with a backend API:

- Apply rate limiting on all API endpoints (authentication, data access, file uploads).
- Use token bucket or sliding window algorithms.
- Return `429 Too Many Requests` with a `Retry-After` header.
- Rate limit by user/session, not by IP (desktop apps may share corporate IPs via VPN/NAT).

For standalone desktop applications with no backend: rate limiting is not applicable.

### Vulnerability Disclosure

Every production desktop application MUST include a vulnerability disclosure mechanism:

1. Add a `SECURITY.md` file to the repository with:
   - Supported versions (which releases receive security updates).
   - How to report a vulnerability (email address or security advisory form — not a public issue).
   - Expected response time (acknowledge within 48 hours, assess within 7 days).
   - Safe harbor statement (reporters acting in good faith will not face legal action).
2. Reference the `SECURITY.md` in the application's About screen or documentation.
3. For organizational deployments, route reports to the enterprise security team, not the Orchestrator directly.

---

## 5. Distribution

### 5.1 Distribution Channels

| Channel | Effort | Reach | Requirements |
|---|---|---|---|
| **GitHub Releases** | Low | Developers, technical users | GitHub account. Free. Attach binaries to tagged releases. |
| **Direct download (website)** | Low-Medium | General users | Hosting for download page. Link to files hosted on GitHub Releases or CDN. |
| **Homebrew Cask (macOS)** | Medium | macOS users who use Homebrew | Create a Cask formula. Submit to homebrew-cask repo or maintain a custom tap. |
| **winget (Windows)** | Medium | Windows 10+ users | Create a manifest. Submit to winget-pkgs repo. |
| **Snap Store (Linux)** | Medium | Ubuntu and Snap-enabled distros | Create a snapcraft.yaml. `snapcraft` build tool. |
| **Flathub (Linux)** | Medium | Linux users across distros | Create a Flatpak manifest. Submit to Flathub. |
| **Microsoft Store** | High | Windows users | MSIX packaging. Store submission process. $19 one-time registration. |
| **Mac App Store** | High | macOS users | Sandboxing requirements. $99/year Apple Developer Program. Notarization. |

**MVP recommendation:** GitHub Releases + direct download page. Add package managers (Homebrew, winget) post-MVP. App stores are Full Track territory.

### 5.2 Release Process

1. Tag the release in Git: `git tag -s v1.0.0 -m "v1.0.0 - Initial release"`
2. CI builds on all platforms, runs full test suite, runs security scans
3. CI creates platform-specific packages
4. CI signs packages (if code signing configured)
5. CI uploads artifacts to GitHub Releases (or equivalent)
6. Generate checksums for all artifacts: `sha256sum *.{exe,dmg,AppImage}`
7. Publish release notes (from CHANGELOG.md)
8. Verify download and install on each platform (manual smoke test)

### Data Handling on Uninstall

Define and document what happens to user data when the application is uninstalled:

- **Windows (NSIS/MSI installer):** The uninstaller removes application binaries but SHOULD NOT delete user data in `%APPDATA%` unless the user explicitly opts in during uninstall.
- **macOS (.dmg/.app):** Dragging to Trash removes the app bundle only. Document the location of preferences (`~/Library/Application Support/[AppName]`) and provide a "Remove All Data" option in the app's settings.
- **Linux (AppImage/deb/rpm):** Package uninstall removes binaries. Document config file locations (`~/.config/[appname]`, `~/.local/share/[appname]`) in the README or man page.

For applications storing sensitive data locally (credentials, personal documents), provide an in-app "Secure Delete" or "Wipe Data" feature that overwrites files before deletion.

---

## 6. Maintenance (Desktop-Specific)

In addition to the Builder's Guide maintenance cadence:

**Monthly:**
- Check for OS deprecation notices that affect the application (minimum supported OS version, deprecated APIs)
- Verify the application still builds on all platforms (OS and SDK updates can break builds)

**Quarterly:**
- Review platform-specific user feedback (Windows vs. macOS vs. Linux issues)
- Test on the latest OS versions (new macOS/Windows releases, new Ubuntu LTS)

**Biannually:**
- Evaluate minimum supported OS version — dropping old versions reduces maintenance burden
- Review framework updates (Tauri, Electron, Flutter major versions) for migration path
- Renew code signing certificates before expiration

### Monitoring & Error Tracking

Desktop applications lack server-side observability by default. Configure the following before launch:

| Tool | Purpose | Free Tier |
|------|---------|-----------|
| **Sentry** | Crash reporting, error tracking | 5K errors/month |
| **PostHog** | Usage analytics (opt-in) | 1M events/month |
| **Built-in telemetry** | Framework-specific crash reporting | N/A |

**Minimum viable monitoring:**

1. Integrate Sentry (or equivalent) for unhandled exceptions and crash reports.
2. Configure alert rules: new crash type → email notification; crash rate spike → SMS/Slack.
3. For client-server apps: add health check endpoint monitoring (UptimeRobot or equivalent) on the backend.
4. Test the monitoring integration by triggering a deliberate error in a non-production build.

**Privacy:** If collecting telemetry or crash reports, disclose this in the application's About/Settings screen and provide an opt-out mechanism. Comply with the privacy requirements in the Governance Framework.

### Backup & Data Recovery

Desktop applications store data locally. Users expect their data to survive application updates and crashes.

1. **SQLite databases:** Use WAL mode for crash resilience. Document the database file location for each OS in HANDOFF.md.
2. **Application settings:** Store in OS-standard locations (AppData on Windows, Application Support on macOS, ~/.config on Linux). Never store in the application binary directory.
3. **User data export:** Provide a data export mechanism (JSON or CSV) for applications storing user-created content. This is both a user feature and a disaster recovery tool.
4. **Update safety:** Test that application updates preserve existing databases and configuration files. The auto-updater MUST NOT delete user data.
5. **Backup testing:** Before launch, verify: (a) uninstall preserves user data in the default OS locations, (b) reinstall reconnects to existing data, (c) exported data can be re-imported.

---

## 7. Phase-Specific Checklists

### Phase 1 — Architecture Selection (Append to Core Prompt)

Add these requirements to the Builder's Guide Step 1.2 architecture prompt:

```
DESKTOP-SPECIFIC REQUIREMENTS:
11. UI Framework: Tauri, Electron, Flutter Desktop, or other — with
    justification based on binary size, performance, and development
    speed requirements.
12. Local data storage strategy: SQLite, file system, or other —
    justified by the data contracts.
13. Cross-platform build strategy: How does CI build for all target
    platforms? Are there platform-specific code paths?
14. Packaging format per platform: installer type, portable option.
15. Code signing strategy: required or deferred? Certificate source.
16. Auto-update mechanism: built-in, manual, or deferred to post-MVP.
17. OS integration: system tray, file associations, native dialogs,
    notifications — which are MVP and which are post-MVP?
18. IPC security model (Tauri/Electron): how does the frontend
    communicate with the backend process? What commands are exposed?
19. Offline-first or connected: does the app require network for
    any core functionality?
20. Minimum supported OS versions per platform.
```

### Phase 2 — Project Initialization (Append to Core Steps)

After the Builder's Guide Project Initialization steps:

- [ ] Cross-platform build configuration verified (builds on all target platforms from CI)
- [ ] Platform-specific code paths identified and documented (e.g., `#[cfg(target_os)]` in Rust, `process.platform` in Node.js)
- [ ] Native dialog integration working (file open/save dialogs at minimum)
- [ ] Application icon configured for all platforms
- [ ] Window management working (resize, minimize, maximize, close)

**Dependency lockfile note (Java/Gradle projects):** The `process-checklist.sh --verify-init` script checks for lockfiles to ensure reproducible builds. Java/Gradle projects use `gradle.lockfile` (generated via `./gradlew dependencies --write-locks`) or `gradle/verification-metadata.xml` (generated via `./gradlew --write-verification-metadata sha256`). Enable dependency locking in `build.gradle.kts`:

```kotlin
dependencyLocking {
    lockAllConfigurations()
}
```

Without a lockfile, the init verification check will flag the project. Node.js projects (Electron, Tauri frontend) use `package-lock.json` or `yarn.lock`, which are auto-generated.

### Phase 3 — Go-Live Verification (Append to Core Checklist)

After the Builder's Guide Phase 4.2 go-live checklist:

- [ ] Installer/package installs correctly on each platform
- [ ] Application launches from installed location (not just dev environment)
- [ ] Uninstaller works cleanly (Windows)
- [ ] File associations work (if applicable)
- [ ] Code signing verified — no security warnings on install (Standard+ Track)
- [ ] Auto-update works (if implemented)
- [ ] Checksums published for all download artifacts

---

## Appendix: Tauri vs. Electron Quick Decision

| If you need... | Choose |
|---|---|
| Smallest binary size (<20 MB) | Tauri |
| Fastest development with JS/TS throughout | Electron |
| Best runtime performance and memory usage | Tauri |
| Largest ecosystem of desktop-specific packages | Electron |
| Strong security isolation by default | Tauri (Rust backend, webview isolation, command allowlist) |
| AI generates code most consistently for this framework | Electron (JS/TS has the most training data) |
| Cross-platform with mobile (shared codebase) | Flutter Desktop |
| The Orchestrator has no Rust experience and binary size is acceptable | Electron |
| The Orchestrator has no Rust experience but binary size matters | Tauri (the frontend is still web tech; the Rust backend is mostly auto-generated by the framework) |

---

## Document Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-02 | Initial release. |

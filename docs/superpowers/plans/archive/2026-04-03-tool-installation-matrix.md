# Tool Installation Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat tool installation logic in init.sh with a matrix-driven system that resolves tools by dev OS, platform, language, track, and phase — with user substitution support and phase-gate-triggered deferred installation.

**Architecture:** JSON matrix files define available tools per platform. A shell resolver script filters the matrix by project context and checks installed state. init.sh, check-phase-gate.sh, and track upgrades call the resolver and present an interactive confirmation UI. User preferences are stored in `.claude/tool-preferences.json` and summarized in `PROJECT_INTAKE.md`.

**Tech Stack:** Bash (resolver + init), jq (JSON processing), JSON (matrix data files)

**Spec:** `docs/superpowers/specs/2026-04-03-tool-installation-matrix-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|---|---|
| `templates/tool-matrix/common.json` | Universal tool definitions (Git, jq, security scanners, Claude Code, Superpowers, MCP servers, language runtimes) |
| `templates/tool-matrix/web.json` | Web platform tools (Lighthouse, ZAP, license-checker, Playwright, k6) |
| `templates/tool-matrix/mobile.json` | Mobile platform tools (EAS CLI, Xcode tools, CocoaPods, Android SDK, mobile license checkers) |
| `templates/tool-matrix/desktop.json` | Desktop platform tools (Tauri CLI, Electron builder, platform build deps, desktop license checkers) |
| `scripts/resolve-tools.sh` | Matrix resolver — filters, checks installed state, outputs JSON buckets |

### Modified Files
| File | Change |
|---|---|
| `init.sh` | Replace `install_tools()` (lines 405-496) and `install_language_runtime()` (lines 499-580) with `resolve_and_install_tools()`. Update `dry_run_summary()` (lines 1636-1694). Update `health_check()` (lines 1461-1533). Update `main()` (lines 1738-1739). |
| `scripts/check-phase-gate.sh` | Add tool resolution check at phase transitions |
| `templates/project-intake.md` | Add Tooling Configuration placeholder section |

---

### Task 1: Create common.json Matrix File

**Files:**
- Create: `templates/tool-matrix/common.json`

- [ ] **Step 1: Create the common.json file**

```json
{
  "schema_version": "1.0",
  "scope": "common",
  "description": "Universal tools required or recommended for all Solo Orchestrator projects",
  "tools": [
    {
      "category": "version_control",
      "name": "Git",
      "description": "Distributed version control system",
      "required": true,
      "phase": 0,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v git",
      "version_command": "git --version | awk '{print $3}'",
      "install": {
        "darwin_brew": "brew install git",
        "darwin_manual": "xcode-select --install",
        "linux_apt": "sudo apt install -y git",
        "linux_dnf": "sudo dnf install -y git",
        "manual": "https://git-scm.com/downloads"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "json_processor",
      "name": "jq",
      "description": "Command-line JSON processor (required by Development Guardrails for Claude Code)",
      "required": true,
      "phase": 0,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v jq",
      "version_command": "jq --version 2>/dev/null",
      "install": {
        "darwin_brew": "brew install jq",
        "linux_apt": "sudo apt install -y jq",
        "linux_dnf": "sudo dnf install -y jq",
        "manual": "https://jqlang.github.io/jq/download/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "runtime",
      "name": "Node.js",
      "description": "JavaScript runtime (required for Snyk, license-checker, JS/TS projects)",
      "required": true,
      "phase": 0,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v node",
      "version_command": "node --version | sed 's/v//'",
      "install": {
        "darwin_brew": "brew install node@22 && brew link --overwrite node@22",
        "linux_apt": "sudo apt install -y nodejs npm",
        "linux_dnf": "sudo dnf install -y nodejs npm",
        "manual": "https://nodejs.org/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "containerization",
      "name": "Docker",
      "description": "Container runtime (needed for OWASP ZAP, Qdrant MCP)",
      "required": false,
      "phase": 0,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v docker",
      "version_command": "docker --version 2>/dev/null | awk '{print $3}' | tr -d ','",
      "install": {
        "darwin_brew": "brew install --cask docker",
        "linux_apt": "sudo apt install -y docker.io && sudo usermod -aG docker $USER",
        "linux_dnf": "sudo dnf install -y docker && sudo usermod -aG docker $USER",
        "manual": "https://docs.docker.com/get-docker/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "commit_signing",
      "name": "GPG",
      "description": "GNU Privacy Guard (optional — used for commit signing)",
      "required": false,
      "phase": 0,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v gpg",
      "version_command": "gpg --version 2>/dev/null | head -1 | awk '{print $3}'",
      "install": {
        "darwin_brew": "brew install gnupg",
        "linux_apt": "sudo apt install -y gnupg",
        "linux_dnf": "sudo dnf install -y gnupg2",
        "manual": "https://gnupg.org/download/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "sast",
      "name": "Semgrep",
      "description": "Static analysis security scanner (OWASP Top 10)",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v semgrep",
      "version_command": "semgrep --version 2>/dev/null | head -1",
      "install": {
        "darwin_brew": "brew install semgrep",
        "linux_pip": "pip3 install semgrep",
        "manual": "https://semgrep.dev/docs/getting-started/"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "SAST Scanner"
    },
    {
      "category": "secret_detection",
      "name": "gitleaks",
      "description": "Secret detection in git repositories",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v gitleaks",
      "version_command": "gitleaks version 2>/dev/null",
      "install": {
        "darwin_brew": "brew install gitleaks",
        "linux_manual": "See https://github.com/gitleaks/gitleaks/releases — download the binary for your architecture",
        "manual": "https://github.com/gitleaks/gitleaks/releases"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "Secret Detection"
    },
    {
      "category": "dependency_scanning",
      "name": "Snyk CLI",
      "description": "Dependency vulnerability scanning",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v snyk",
      "version_command": "snyk --version 2>/dev/null",
      "install": {
        "npm": "npm install -g snyk",
        "manual": "https://docs.snyk.io/snyk-cli/install-or-update-the-snyk-cli"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "Dependency Scanner"
    },
    {
      "category": "ai_agent",
      "name": "Claude Code",
      "description": "AI coding agent CLI",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "command -v claude",
      "version_command": "claude --version 2>/dev/null",
      "install": {
        "darwin_brew": "brew install claude-code",
        "npm": "npm install -g @anthropic-ai/claude-code",
        "manual": "https://docs.anthropic.com/en/docs/claude-code"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "claude_plugin",
      "name": "Superpowers",
      "description": "Agentic skills plugin for Claude Code (TDD, debugging, code review, git worktrees)",
      "required": false,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "[ -f \"$HOME/.claude/settings.json\" ] && command -v jq &>/dev/null && [ \"$(jq -r '.enabledPlugins[\"superpowers@claude-plugins-official\"] // false' \"$HOME/.claude/settings.json\" 2>/dev/null)\" = \"true\" ]",
      "version_command": "echo 'installed'",
      "install": {
        "darwin_brew": "claude plugins add superpowers",
        "linux_apt": "claude plugins add superpowers",
        "manual": "Run: claude → /plugins → search 'superpowers' �� install"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "mcp_server",
      "name": "Context7 MCP",
      "description": "Up-to-date library documentation via MCP (recommended for Phase 1 and Phase 2)",
      "required": false,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "[ -f \"$HOME/.claude/settings.json\" ] && command -v jq &>/dev/null && jq -e '.mcpServers.context7 // .mcpServers[\"context7-mcp\"] // empty' \"$HOME/.claude/settings.json\" >/dev/null 2>&1",
      "version_command": "echo 'configured'",
      "install": {
        "npm": "claude mcp add context7 -- npx -y @upstash/context7-mcp@latest",
        "manual": "Run: claude mcp add context7 -- npx -y @upstash/context7-mcp@latest"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "mcp_server",
      "name": "Qdrant MCP",
      "description": "Persistent semantic memory across Claude Code sessions",
      "required": false,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["all"],
      "check_command": "[ -f \"$HOME/.claude/settings.json\" ] && command -v jq &>/dev/null && jq -e '.mcpServers.qdrant // .mcpServers[\"mcp-server-qdrant\"] // empty' \"$HOME/.claude/settings.json\" >/dev/null 2>&1",
      "version_command": "echo 'configured'",
      "install": {
        "manual": "Requires Docker + uv. See docs/framework/cli-setup-addendum.md for setup steps."
      },
      "auto_installable": false,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "runtime",
      "name": "Python 3",
      "description": "Python runtime",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["python"],
      "check_command": "command -v python3 || command -v python",
      "version_command": "python3 --version 2>/dev/null | awk '{print $2}' || python --version 2>/dev/null | awk '{print $2}'",
      "install": {
        "darwin_brew": "brew install python",
        "linux_apt": "sudo apt install -y python3 python3-pip python3-venv",
        "linux_dnf": "sudo dnf install -y python3 python3-pip",
        "manual": "https://python.org/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "runtime",
      "name": "Rust",
      "description": "Rust toolchain via rustup",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["rust"],
      "check_command": "command -v cargo",
      "version_command": "rustc --version 2>/dev/null | awk '{print $2}'",
      "install": {
        "darwin_brew": "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source \"$HOME/.cargo/env\"",
        "linux_apt": "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source \"$HOME/.cargo/env\"",
        "manual": "https://rustup.rs/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "runtime",
      "name": "Go",
      "description": "Go programming language",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["go"],
      "check_command": "command -v go",
      "version_command": "go version 2>/dev/null | awk '{print $3}' | sed 's/go//'",
      "install": {
        "darwin_brew": "brew install go",
        "linux_apt": "sudo apt install -y golang",
        "linux_dnf": "sudo dnf install -y golang",
        "manual": "https://go.dev/dl/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "runtime",
      "name": ".NET SDK",
      "description": "C# / .NET development kit",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["csharp"],
      "check_command": "command -v dotnet",
      "version_command": "dotnet --version 2>/dev/null",
      "install": {
        "darwin_brew": "brew install dotnet",
        "manual": "https://dotnet.microsoft.com/download"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "runtime",
      "name": "Java (Eclipse Temurin)",
      "description": "Java Development Kit",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["kotlin", "java", "jvm"],
      "check_command": "command -v java",
      "version_command": "java --version 2>/dev/null | head -1",
      "install": {
        "darwin_brew": "brew install temurin",
        "linux_apt": "sudo apt install -y default-jdk",
        "linux_dnf": "sudo dnf install -y java-latest-openjdk-devel",
        "manual": "https://adoptium.net/"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "runtime",
      "name": "Flutter SDK",
      "description": "Flutter cross-platform framework",
      "required": true,
      "phase": 1,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["all"],
      "languages": ["dart"],
      "check_command": "command -v flutter",
      "version_command": "flutter --version 2>/dev/null | head -1 | awk '{print $2}'",
      "install": {
        "darwin_brew": "brew install flutter",
        "manual": "https://docs.flutter.dev/get-started/install"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    }
  ]
}
```

- [ ] **Step 2: Validate JSON is well-formed**

Run: `jq '.' templates/tool-matrix/common.json > /dev/null && echo "VALID" || echo "INVALID"`
Expected: `VALID`

- [ ] **Step 3: Commit**

```bash
git add templates/tool-matrix/common.json
git commit -m "feat(matrix): add common.json tool definitions

Universal tools for all Solo Orchestrator projects: prerequisites,
security scanners, Claude Code, Superpowers, MCP servers, and
language runtimes."
```

---

### Task 2: Create web.json Matrix File

**Files:**
- Create: `templates/tool-matrix/web.json`

- [ ] **Step 1: Create the web.json file**

```json
{
  "schema_version": "1.0",
  "scope": "web",
  "description": "Tools specific to web platform projects (SPAs, full-stack, APIs, static sites)",
  "tools": [
    {
      "category": "performance",
      "name": "Lighthouse",
      "description": "Performance, accessibility, and SEO auditing",
      "required": true,
      "phase": 2,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["web"],
      "languages": ["all"],
      "check_command": "command -v lighthouse",
      "version_command": "lighthouse --version 2>/dev/null",
      "install": {
        "npm": "npm install -g lighthouse",
        "manual": "npm install -g lighthouse"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "Performance Auditing"
    },
    {
      "category": "dast",
      "name": "OWASP ZAP",
      "description": "Dynamic application security testing via Docker",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["web"],
      "languages": ["all"],
      "check_command": "command -v docker && docker image inspect zaproxy/zap-stable &>/dev/null 2>&1",
      "version_command": "echo 'docker image present'",
      "install": {
        "manual": "Requires Docker. Run: docker pull zaproxy/zap-stable"
      },
      "auto_installable": false,
      "substitutable": true,
      "substitution_category": "DAST Scanner"
    },
    {
      "category": "license_compliance",
      "name": "license-checker",
      "description": "Node.js dependency license auditing",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["web"],
      "languages": ["typescript", "javascript"],
      "check_command": "command -v license-checker",
      "version_command": "license-checker --version 2>/dev/null",
      "install": {
        "npm": "npm install -g license-checker",
        "manual": "npm install -g license-checker"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "license_compliance",
      "name": "pip-licenses",
      "description": "Python dependency license auditing",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["web"],
      "languages": ["python"],
      "check_command": "pip3 show pip-licenses &>/dev/null 2>&1 || pip show pip-licenses &>/dev/null 2>&1",
      "version_command": "pip-licenses --version 2>/dev/null",
      "install": {
        "linux_pip": "pip3 install pip-licenses",
        "darwin_brew": "pip3 install pip-licenses",
        "manual": "pip install pip-licenses"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "e2e_testing",
      "name": "Playwright",
      "description": "End-to-end browser testing framework",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["web"],
      "languages": ["all"],
      "check_command": "npx playwright --version &>/dev/null 2>&1",
      "version_command": "npx playwright --version 2>/dev/null",
      "install": {
        "npm": "npm init playwright@latest",
        "manual": "npm init playwright@latest"
      },
      "auto_installable": false,
      "substitutable": true,
      "substitution_category": "E2E Testing"
    },
    {
      "category": "load_testing",
      "name": "k6",
      "description": "Load testing tool",
      "required": true,
      "phase": 3,
      "tracks": ["full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["web"],
      "languages": ["all"],
      "check_command": "command -v k6",
      "version_command": "k6 version 2>/dev/null",
      "install": {
        "darwin_brew": "brew install k6",
        "linux_apt": "sudo gpg -k && sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 && echo 'deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main' | sudo tee /etc/apt/sources.list.d/k6.list && sudo apt update && sudo apt install k6",
        "manual": "https://k6.io/docs/get-started/installation/"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "Load Testing"
    }
  ]
}
```

- [ ] **Step 2: Validate JSON**

Run: `jq '.' templates/tool-matrix/web.json > /dev/null && echo "VALID" || echo "INVALID"`
Expected: `VALID`

- [ ] **Step 3: Commit**

```bash
git add templates/tool-matrix/web.json
git commit -m "feat(matrix): add web.json tool definitions

Web platform tools: Lighthouse, OWASP ZAP, license-checker,
pip-licenses, Playwright, k6. Phase-tagged and track-aware."
```

---

### Task 3: Create mobile.json Matrix File

**Files:**
- Create: `templates/tool-matrix/mobile.json`

- [ ] **Step 1: Create the mobile.json file**

```json
{
  "schema_version": "1.0",
  "scope": "mobile",
  "description": "Tools specific to mobile platform projects (iOS, Android, cross-platform)",
  "tools": [
    {
      "category": "mobile_build_tools",
      "name": "EAS CLI",
      "description": "Expo Application Services CLI for React Native builds and submissions",
      "required": true,
      "phase": 2,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["mobile"],
      "languages": ["typescript", "javascript"],
      "check_command": "command -v eas",
      "version_command": "eas --version 2>/dev/null",
      "install": {
        "npm": "npm install -g eas-cli",
        "manual": "npm install -g eas-cli"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "mobile_build_tools",
      "name": "Xcode Command Line Tools",
      "description": "Apple build toolchain (required for iOS development)",
      "required": true,
      "phase": 2,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin"],
      "platforms": ["mobile"],
      "languages": ["all"],
      "check_command": "xcode-select -p &>/dev/null 2>&1",
      "version_command": "xcodebuild -version 2>/dev/null | head -1",
      "install": {
        "darwin_manual": "xcode-select --install",
        "manual": "xcode-select --install (macOS only — iOS development requires macOS)"
      },
      "auto_installable": false,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "mobile_build_tools",
      "name": "CocoaPods",
      "description": "iOS dependency manager (required for React Native and Flutter iOS builds)",
      "required": true,
      "phase": 2,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin"],
      "platforms": ["mobile"],
      "languages": ["typescript", "javascript", "dart"],
      "check_command": "command -v pod",
      "version_command": "pod --version 2>/dev/null",
      "install": {
        "darwin_brew": "brew install cocoapods",
        "darwin_manual": "sudo gem install cocoapods",
        "manual": "sudo gem install cocoapods (macOS only)"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "mobile_build_tools",
      "name": "Android Studio",
      "description": "Android development IDE and SDK manager",
      "required": true,
      "phase": 2,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["mobile"],
      "languages": ["all"],
      "check_command": "[ -d \"$HOME/Library/Android/sdk\" ] || [ -d \"$HOME/Android/Sdk\" ] || [ -n \"$ANDROID_HOME\" ]",
      "version_command": "echo 'SDK present'",
      "install": {
        "darwin_brew": "brew install --cask android-studio",
        "manual": "Download from https://developer.android.com/studio. After install, open Android Studio → SDK Manager → install: Android SDK Platform (latest), Build-Tools, Emulator, Platform-Tools."
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "license_compliance",
      "name": "license-checker",
      "description": "Node.js dependency license auditing (React Native projects)",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["mobile"],
      "languages": ["typescript", "javascript"],
      "check_command": "command -v license-checker",
      "version_command": "license-checker --version 2>/dev/null",
      "install": {
        "npm": "npm install -g license-checker",
        "manual": "npm install -g license-checker"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "license_compliance",
      "name": "dart_license_checker",
      "description": "Dart/Flutter dependency license auditing",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["mobile"],
      "languages": ["dart"],
      "check_command": "dart pub global list 2>/dev/null | grep -q dart_license_checker",
      "version_command": "echo 'installed via dart pub global'",
      "install": {
        "manual": "dart pub global activate dart_license_checker",
        "darwin_brew": "dart pub global activate dart_license_checker",
        "linux_apt": "dart pub global activate dart_license_checker"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "code_signing",
      "name": "Apple Developer Program",
      "description": "Required for iOS app distribution and code signing ($99/year)",
      "required": true,
      "phase": 4,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin"],
      "platforms": ["mobile"],
      "languages": ["all"],
      "check_command": "security find-identity -v -p codesigning 2>/dev/null | grep -q 'Apple Development'",
      "version_command": "echo 'signing identity present'",
      "install": {
        "manual": "Enroll at https://developer.apple.com/programs/ ($99/year). Then create signing certificates via Xcode → Settings → Accounts."
      },
      "auto_installable": false,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "code_signing",
      "name": "Android Keystore",
      "description": "Android app signing keystore for Play Store distribution",
      "required": true,
      "phase": 4,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["mobile"],
      "languages": ["all"],
      "check_command": "false",
      "version_command": "echo 'N/A'",
      "install": {
        "manual": "Generate with: keytool -genkey -v -keystore release.keystore -alias release -keyalg RSA -keysize 2048 -validity 10000. Store securely — loss means you cannot update your app."
      },
      "auto_installable": false,
      "substitutable": false,
      "substitution_category": null
    }
  ]
}
```

- [ ] **Step 2: Validate JSON**

Run: `jq '.' templates/tool-matrix/mobile.json > /dev/null && echo "VALID" || echo "INVALID"`
Expected: `VALID`

- [ ] **Step 3: Commit**

```bash
git add templates/tool-matrix/mobile.json
git commit -m "feat(matrix): add mobile.json tool definitions

Mobile platform tools: EAS CLI, Xcode tools, CocoaPods, Android
Studio, license checkers, code signing. Phase and OS-aware."
```

---

### Task 4: Create desktop.json Matrix File

**Files:**
- Create: `templates/tool-matrix/desktop.json`

- [ ] **Step 1: Create the desktop.json file**

```json
{
  "schema_version": "1.0",
  "scope": "desktop",
  "description": "Tools specific to desktop platform projects (Tauri, Electron, Flutter Desktop, .NET MAUI)",
  "tools": [
    {
      "category": "desktop_build_tools",
      "name": "Tauri CLI",
      "description": "Tauri desktop application framework CLI",
      "required": true,
      "phase": 2,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["desktop"],
      "languages": ["rust"],
      "check_command": "command -v cargo-tauri || cargo install --list 2>/dev/null | grep -q tauri-cli",
      "version_command": "cargo tauri --version 2>/dev/null",
      "install": {
        "darwin_brew": "cargo install tauri-cli",
        "linux_apt": "cargo install tauri-cli",
        "manual": "cargo install tauri-cli (requires Rust toolchain)"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "desktop_build_tools",
      "name": "Xcode Command Line Tools",
      "description": "Apple build toolchain (required for macOS desktop builds)",
      "required": true,
      "phase": 2,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["darwin"],
      "platforms": ["desktop"],
      "languages": ["all"],
      "check_command": "xcode-select -p &>/dev/null 2>&1",
      "version_command": "xcodebuild -version 2>/dev/null | head -1",
      "install": {
        "darwin_manual": "xcode-select --install",
        "manual": "xcode-select --install (macOS only)"
      },
      "auto_installable": false,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "desktop_build_tools",
      "name": "Linux Desktop Build Dependencies",
      "description": "WebKit2GTK and build essentials for Tauri on Linux",
      "required": true,
      "phase": 2,
      "tracks": ["light", "standard", "full"],
      "dev_os": ["linux"],
      "platforms": ["desktop"],
      "languages": ["rust"],
      "check_command": "dpkg -l libwebkit2gtk-4.1-dev &>/dev/null 2>&1 || rpm -q webkit2gtk4.1-devel &>/dev/null 2>&1",
      "version_command": "dpkg -l libwebkit2gtk-4.1-dev 2>/dev/null | grep '^ii' | awk '{print $3}' || echo 'unknown'",
      "install": {
        "linux_apt": "sudo apt install -y libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev",
        "linux_dnf": "sudo dnf install -y webkit2gtk4.1-devel openssl-devel curl wget file libappindicator-gtk3-devel librsvg2-devel",
        "manual": "Install libwebkit2gtk-4.1-dev and build-essential via your package manager"
      },
      "auto_installable": true,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "license_compliance",
      "name": "license-checker",
      "description": "Node.js dependency license auditing (Electron/Tauri frontend)",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["desktop"],
      "languages": ["typescript", "javascript"],
      "check_command": "command -v license-checker",
      "version_command": "license-checker --version 2>/dev/null",
      "install": {
        "npm": "npm install -g license-checker",
        "manual": "npm install -g license-checker"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "license_compliance",
      "name": "cargo-license",
      "description": "Rust dependency license auditing (Tauri backend)",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["desktop"],
      "languages": ["rust"],
      "check_command": "command -v cargo-license || cargo install --list 2>/dev/null | grep -q cargo-license",
      "version_command": "cargo license --version 2>/dev/null",
      "install": {
        "darwin_brew": "cargo install cargo-license",
        "linux_apt": "cargo install cargo-license",
        "manual": "cargo install cargo-license"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "license_compliance",
      "name": "pip-licenses",
      "description": "Python dependency license auditing (PyQt/PySide projects)",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["desktop"],
      "languages": ["python"],
      "check_command": "pip3 show pip-licenses &>/dev/null 2>&1 || pip show pip-licenses &>/dev/null 2>&1",
      "version_command": "pip-licenses --version 2>/dev/null",
      "install": {
        "linux_pip": "pip3 install pip-licenses",
        "darwin_brew": "pip3 install pip-licenses",
        "manual": "pip install pip-licenses"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "license_compliance",
      "name": "dart_license_checker",
      "description": "Dart/Flutter dependency license auditing (Flutter Desktop)",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["desktop"],
      "languages": ["dart"],
      "check_command": "dart pub global list 2>/dev/null | grep -q dart_license_checker",
      "version_command": "echo 'installed via dart pub global'",
      "install": {
        "darwin_brew": "dart pub global activate dart_license_checker",
        "linux_apt": "dart pub global activate dart_license_checker",
        "manual": "dart pub global activate dart_license_checker"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "license_compliance",
      "name": "dotnet-project-licenses",
      "description": ".NET dependency license auditing (MAUI projects)",
      "required": true,
      "phase": 3,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["desktop"],
      "languages": ["csharp"],
      "check_command": "dotnet tool list -g 2>/dev/null | grep -q dotnet-project-licenses",
      "version_command": "dotnet-project-licenses --version 2>/dev/null || echo 'installed'",
      "install": {
        "darwin_brew": "dotnet tool install --global dotnet-project-licenses",
        "linux_apt": "dotnet tool install --global dotnet-project-licenses",
        "manual": "dotnet tool install --global dotnet-project-licenses"
      },
      "auto_installable": true,
      "substitutable": true,
      "substitution_category": "License Compliance"
    },
    {
      "category": "code_signing",
      "name": "Apple Developer Program (Desktop)",
      "description": "Required for macOS app notarization ($99/year)",
      "required": true,
      "phase": 4,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin"],
      "platforms": ["desktop"],
      "languages": ["all"],
      "check_command": "security find-identity -v -p codesigning 2>/dev/null | grep -q 'Developer ID'",
      "version_command": "echo 'signing identity present'",
      "install": {
        "manual": "Enroll at https://developer.apple.com/programs/ ($99/year). Create Developer ID certificates for distribution."
      },
      "auto_installable": false,
      "substitutable": false,
      "substitution_category": null
    },
    {
      "category": "code_signing",
      "name": "EV Code Signing Certificate (Windows)",
      "description": "Windows code signing to bypass SmartScreen ($200-500/year)",
      "required": true,
      "phase": 4,
      "tracks": ["standard", "full"],
      "dev_os": ["darwin", "linux"],
      "platforms": ["desktop"],
      "languages": ["all"],
      "check_command": "false",
      "version_command": "echo 'N/A'",
      "install": {
        "manual": "Purchase from DigiCert, Sectigo, or GlobalSign ($200-500/year). EV certificates eliminate SmartScreen warnings. Store as CI secret for automated signing."
      },
      "auto_installable": false,
      "substitutable": false,
      "substitution_category": null
    }
  ]
}
```

- [ ] **Step 2: Validate JSON**

Run: `jq '.' templates/tool-matrix/desktop.json > /dev/null && echo "VALID" || echo "INVALID"`
Expected: `VALID`

- [ ] **Step 3: Commit**

```bash
git add templates/tool-matrix/desktop.json
git commit -m "feat(matrix): add desktop.json tool definitions

Desktop platform tools: Tauri CLI, Xcode tools, Linux build deps,
license checkers (npm, cargo, pip, dart, dotnet), code signing certs.
Phase, OS, and language-aware."
```

---

### Task 5: Create the Resolver Script

**Files:**
- Create: `scripts/resolve-tools.sh`

- [ ] **Step 1: Create resolve-tools.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Tool Matrix Resolver
# Reads tool-matrix JSON files, filters by project context, checks
# installed state, and outputs a categorized JSON plan to stdout.
#
# Usage:
#   scripts/resolve-tools.sh \
#     --dev-os darwin \
#     --platform web \
#     --language typescript \
#     --track standard \
#     --phase 2 \
#     --matrix-dir templates/tool-matrix \
#     [--tool-prefs .claude/tool-preferences.json]
#
# Output: JSON with four buckets: auto_install, manual_install,
#         already_installed, deferred

# --- Parse arguments ---
DEV_OS=""
PLATFORM=""
LANGUAGE=""
TRACK=""
PHASE=""
MATRIX_DIR=""
TOOL_PREFS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dev-os)      DEV_OS="$2";      shift 2 ;;
    --platform)    PLATFORM="$2";    shift 2 ;;
    --language)    LANGUAGE="$2";    shift 2 ;;
    --track)       TRACK="$2";       shift 2 ;;
    --phase)       PHASE="$2";       shift 2 ;;
    --matrix-dir)  MATRIX_DIR="$2";  shift 2 ;;
    --tool-prefs)  TOOL_PREFS="$2";  shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Validate required arguments
for var_name in DEV_OS PLATFORM LANGUAGE TRACK PHASE MATRIX_DIR; do
  eval val="\$$var_name"
  if [ -z "$val" ]; then
    echo "Missing required argument: --$(echo "$var_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')" >&2
    exit 1
  fi
done

if [ ! -d "$MATRIX_DIR" ]; then
  echo "Matrix directory not found: $MATRIX_DIR" >&2
  exit 1
fi

# Normalize dev_os to lowercase
DEV_OS=$(echo "$DEV_OS" | tr '[:upper:]' '[:lower:]')
case "$DEV_OS" in
  darwin|macos) DEV_OS="darwin" ;;
  linux)        DEV_OS="linux" ;;
  *)
    echo "Unsupported dev_os: $DEV_OS (expected darwin or linux)" >&2
    exit 1
    ;;
esac

# --- Load matrix files ---
COMMON_FILE="$MATRIX_DIR/common.json"
PLATFORM_FILE="$MATRIX_DIR/${PLATFORM}.json"

if [ ! -f "$COMMON_FILE" ]; then
  echo "Common matrix file not found: $COMMON_FILE" >&2
  exit 1
fi

# Merge tools from common + platform-specific (platform file is optional)
if [ -f "$PLATFORM_FILE" ]; then
  ALL_TOOLS=$(jq -s '.[0].tools + .[1].tools' "$COMMON_FILE" "$PLATFORM_FILE")
else
  ALL_TOOLS=$(jq '.tools' "$COMMON_FILE")
fi

# --- Load user preferences (if provided) ---
SKIPPED_NAMES="[]"
SUBSTITUTIONS="{}"
ADDITIONS="[]"
if [ -n "$TOOL_PREFS" ] && [ -f "$TOOL_PREFS" ]; then
  SKIPPED_NAMES=$(jq '[.skipped[]?.name // empty]' "$TOOL_PREFS" 2>/dev/null || echo "[]")
  SUBSTITUTIONS=$(jq '.substitutions // {}' "$TOOL_PREFS" 2>/dev/null || echo "{}")
  ADDITIONS=$(jq '.additions // []' "$TOOL_PREFS" 2>/dev/null || echo "[]")
fi

# --- Filter tools ---
# Apply: dev_os, track, language, platforms, skipped
FILTERED_TOOLS=$(echo "$ALL_TOOLS" | jq \
  --arg dev_os "$DEV_OS" \
  --arg track "$TRACK" \
  --arg language "$LANGUAGE" \
  --arg platform "$PLATFORM" \
  --argjson skipped "$SKIPPED_NAMES" \
  '[.[] | select(
    # dev_os filter
    (.dev_os | if . == null then true else (. | index($dev_os)) != null end) and
    # track filter
    (.tracks | if . == null then true else (. | index($track)) != null end) and
    # language filter
    (.languages | if . == null then true
     elif (. | index("all")) != null then true
     else (. | index($language)) != null end) and
    # platforms filter
    (.platforms | if . == null then true
     elif (. | index("all")) != null then true
     else (. | index($platform)) != null end) and
    # skipped filter
    (.name as $n | ($skipped | index($n)) == null)
  )]')

# --- Apply substitutions ---
# For each tool whose substitution_category matches a key in substitutions,
# replace the tool name/check_command with the user's selection
FILTERED_TOOLS=$(echo "$FILTERED_TOOLS" | jq \
  --argjson subs "$SUBSTITUTIONS" \
  '[.[] | . as $tool |
    if $tool.substitution_category != null and ($subs | has($tool.substitution_category)) then
      $subs[$tool.substitution_category] as $sub |
      $tool + {
        name: $sub.selected,
        check_command: ($sub.check_command // $tool.check_command),
        original_default: $tool.name
      }
    else . end
  ]')

# --- Detect install method for this OS ---
# Determine available package managers
HAS_BREW=false
HAS_APT=false
HAS_DNF=false
HAS_NPM=false
command -v brew &>/dev/null && HAS_BREW=true
command -v apt &>/dev/null && HAS_APT=true
command -v dnf &>/dev/null && HAS_DNF=true
command -v npm &>/dev/null && HAS_NPM=true

# Build priority list of install keys for this environment
INSTALL_KEYS="[]"
if [ "$DEV_OS" = "darwin" ]; then
  if [ "$HAS_BREW" = true ]; then
    INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["darwin_brew"]')
  fi
  INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["darwin_manual"]')
elif [ "$DEV_OS" = "linux" ]; then
  if [ "$HAS_APT" = true ]; then
    INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["linux_apt"]')
  fi
  if [ "$HAS_DNF" = true ]; then
    INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["linux_dnf"]')
  fi
  INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["linux_pip", "linux_manual"]')
fi
if [ "$HAS_NPM" = true ]; then
  INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["npm"]')
fi
INSTALL_KEYS=$(echo "$INSTALL_KEYS" | jq '. + ["manual"]')

# --- Check each tool and categorize ---
# We need to iterate and run check_command for each tool, which requires
# shell execution. Build the output arrays in shell.
AUTO_INSTALL="[]"
MANUAL_INSTALL="[]"
ALREADY_INSTALLED="[]"
DEFERRED="[]"

TOOL_COUNT=$(echo "$FILTERED_TOOLS" | jq 'length')

for i in $(seq 0 $((TOOL_COUNT - 1))); do
  TOOL_JSON=$(echo "$FILTERED_TOOLS" | jq ".[$i]")
  TOOL_NAME=$(echo "$TOOL_JSON" | jq -r '.name')
  TOOL_CATEGORY=$(echo "$TOOL_JSON" | jq -r '.substitution_category // .category')
  TOOL_PHASE=$(echo "$TOOL_JSON" | jq -r '.phase')
  TOOL_REQUIRED=$(echo "$TOOL_JSON" | jq -r '.required')
  TOOL_CHECK=$(echo "$TOOL_JSON" | jq -r '.check_command')
  TOOL_AUTO=$(echo "$TOOL_JSON" | jq -r '.auto_installable')
  TOOL_VERSION_CMD=$(echo "$TOOL_JSON" | jq -r '.version_command // empty')
  TOOL_DESCRIPTION=$(echo "$TOOL_JSON" | jq -r '.description')

  # Phase filter: defer tools for future phases
  if [ "$TOOL_PHASE" -gt "$PHASE" ]; then
    DEFERRED=$(echo "$DEFERRED" | jq \
      --arg name "$TOOL_NAME" \
      --arg category "$TOOL_CATEGORY" \
      --argjson phase "$TOOL_PHASE" \
      --arg description "$TOOL_DESCRIPTION" \
      '. + [{name: $name, category: $category, phase: $phase, reason: ("Needed at Phase " + ($phase | tostring) + " gate"), description: $description}]')
    continue
  fi

  # Check if already installed
  INSTALLED=false
  VERSION=""
  if eval "$TOOL_CHECK" &>/dev/null 2>&1; then
    INSTALLED=true
    if [ -n "$TOOL_VERSION_CMD" ]; then
      VERSION=$(eval "$TOOL_VERSION_CMD" 2>/dev/null || echo "")
    fi
  fi

  if [ "$INSTALLED" = true ]; then
    ALREADY_INSTALLED=$(echo "$ALREADY_INSTALLED" | jq \
      --arg name "$TOOL_NAME" \
      --arg category "$TOOL_CATEGORY" \
      --arg version "$VERSION" \
      '. + [{name: $name, category: $category, version: $version}]')
  else
    # Find the best install command for this environment
    INSTALL_CMD=""
    INSTALL_OBJ=$(echo "$TOOL_JSON" | jq '.install')
    for key in $(echo "$INSTALL_KEYS" | jq -r '.[]'); do
      cmd=$(echo "$INSTALL_OBJ" | jq -r --arg k "$key" '.[$k] // empty')
      if [ -n "$cmd" ]; then
        INSTALL_CMD="$cmd"
        break
      fi
    done

    # If no auto-installable command found, fall back to manual
    if [ -z "$INSTALL_CMD" ]; then
      INSTALL_CMD=$(echo "$INSTALL_OBJ" | jq -r '.manual // "See documentation"')
      TOOL_AUTO="false"
    fi

    if [ "$TOOL_AUTO" = "true" ]; then
      AUTO_INSTALL=$(echo "$AUTO_INSTALL" | jq \
        --arg name "$TOOL_NAME" \
        --arg category "$TOOL_CATEGORY" \
        --arg install_cmd "$INSTALL_CMD" \
        --argjson required "$([ "$TOOL_REQUIRED" = "true" ] && echo true || echo false)" \
        --arg description "$TOOL_DESCRIPTION" \
        '. + [{name: $name, category: $category, install_cmd: $install_cmd, required: $required, description: $description}]')
    else
      MANUAL_INSTALL=$(echo "$MANUAL_INSTALL" | jq \
        --arg name "$TOOL_NAME" \
        --arg category "$TOOL_CATEGORY" \
        --arg instructions "$INSTALL_CMD" \
        --argjson required "$([ "$TOOL_REQUIRED" = "true" ] && echo true || echo false)" \
        --arg description "$TOOL_DESCRIPTION" \
        '. + [{name: $name, category: $category, instructions: $instructions, required: $required, description: $description}]')
    fi
  fi
done

# --- Add user freeform additions to already_installed (if check passes) or manual_install ---
ADDITION_COUNT=$(echo "$ADDITIONS" | jq 'length')
for i in $(seq 0 $((ADDITION_COUNT - 1))); do
  ADD_JSON=$(echo "$ADDITIONS" | jq ".[$i]")
  ADD_NAME=$(echo "$ADD_JSON" | jq -r '.name')
  ADD_CATEGORY=$(echo "$ADD_JSON" | jq -r '.category // "Custom"')
  ADD_CHECK=$(echo "$ADD_JSON" | jq -r '.check_command // ""')
  ADD_DESC=$(echo "$ADD_JSON" | jq -r '.description // ""')

  if [ -n "$ADD_CHECK" ] && eval "$ADD_CHECK" &>/dev/null 2>&1; then
    ALREADY_INSTALLED=$(echo "$ALREADY_INSTALLED" | jq \
      --arg name "$ADD_NAME" \
      --arg category "$ADD_CATEGORY" \
      --arg version "custom" \
      '. + [{name: $name, category: $category, version: $version}]')
  else
    MANUAL_INSTALL=$(echo "$MANUAL_INSTALL" | jq \
      --arg name "$ADD_NAME" \
      --arg category "$ADD_CATEGORY" \
      --arg instructions "User-added tool — install manually" \
      --arg description "$ADD_DESC" \
      '. + [{name: $name, category: $category, instructions: $instructions, required: false, description: $description}]')
  fi
done

# --- Output ---
jq -n \
  --argjson auto_install "$AUTO_INSTALL" \
  --argjson manual_install "$MANUAL_INSTALL" \
  --argjson already_installed "$ALREADY_INSTALLED" \
  --argjson deferred "$DEFERRED" \
  '{
    auto_install: $auto_install,
    manual_install: $manual_install,
    already_installed: $already_installed,
    deferred: $deferred
  }'
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/resolve-tools.sh`

- [ ] **Step 3: Test the resolver with a basic invocation**

Run: `bash scripts/resolve-tools.sh --dev-os darwin --platform web --language typescript --track standard --phase 2 --matrix-dir templates/tool-matrix 2>/dev/null | jq '.auto_install | length, .already_installed | length, .deferred | length'`

Expected: Three numbers printed (counts of tools in each bucket — exact values depend on what's already installed on this machine).

- [ ] **Step 4: Commit**

```bash
git add scripts/resolve-tools.sh
git commit -m "feat(matrix): add resolve-tools.sh matrix resolver

Reads tool-matrix JSON files, filters by dev OS/platform/language/
track/phase, checks installed state, applies user substitutions,
and outputs categorized JSON (auto_install, manual_install,
already_installed, deferred)."
```

---

### Task 6: Replace init.sh Tool Installation with Resolver

**Files:**
- Modify: `init.sh` (replace lines 402-580 `install_tools` + `install_language_runtime`, update `main()`, update `dry_run_summary()`, update `health_check()`)

- [ ] **Step 1: Replace `install_tools()` and `install_language_runtime()` with `resolve_and_install_tools()`**

Delete the `install_tools()` function (lines 402-496) and `install_language_runtime()` function (lines 498-580). Replace with:

```bash
# ================================================================
# PHASE 3: Resolve and Install Tools (Matrix-Driven)
# ================================================================
resolve_and_install_tools() {
  print_step "Resolving tool installation plan..."
  local os_type
  os_type="$(uname -s)"
  local dev_os
  case "$os_type" in
    Darwin) dev_os="darwin" ;;
    Linux)  dev_os="linux" ;;
    *)      dev_os="linux" ;;  # best-effort fallback
  esac

  # Run the resolver
  local resolver_output
  resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
    --dev-os "$dev_os" \
    --platform "$PLATFORM" \
    --language "$LANGUAGE" \
    --track "$TRACK" \
    --phase 2 \
    --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" 2>/dev/null) || {
    print_warn "Tool resolver failed. Falling back to basic tool checks."
    return 0
  }

  # Parse bucket counts
  local auto_count manual_count installed_count deferred_count
  auto_count=$(echo "$resolver_output" | jq '.auto_install | length')
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  installed_count=$(echo "$resolver_output" | jq '.already_installed | length')
  deferred_count=$(echo "$resolver_output" | jq '.deferred | length')

  # Display the installation plan
  echo ""
  echo -e "${BOLD}┌──────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│  Tool Installation Plan ($os_type / $PLATFORM / $LANGUAGE)${NC}"
  echo -e "${BOLD}├──────────────────────────────────────────────────────────┤${NC}"

  # Already installed
  if [ "$installed_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${GREEN}✓ Already installed${NC}"
    echo "$resolver_output" | jq -r '.already_installed[] | "│    \(.name)\(if .version != "" then " " + .version else "" end)"' | while IFS= read -r line; do
      echo -e "${BOLD}${line}${NC}"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Will auto-install
  if [ "$auto_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${CYAN}⬇ Will auto-install${NC}"
    echo "$resolver_output" | jq -r '.auto_install[] | "│    \(.name) (\(.category))"' | while IFS= read -r line; do
      echo -e "${BOLD}${line}${NC}"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Manual install required
  if [ "$manual_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${YELLOW}⚠ Requires manual setup${NC}"
    echo "$resolver_output" | jq -r '.manual_install[] | "│    \(.name) — \(.instructions)"' | while IFS= read -r line; do
      echo -e "${BOLD}${line}${NC}"
    done
    echo -e "${BOLD}│${NC}"
  fi

  # Deferred
  if [ "$deferred_count" -gt 0 ]; then
    echo -e "${BOLD}│${NC}  ${BLUE}⏳ Deferred (installed at later phases)${NC}"
    echo "$resolver_output" | jq -r '.deferred[] | "│    Phase \(.phase): \(.name) (\(.category))"' | while IFS= read -r line; do
      echo -e "${BOLD}${line}${NC}"
    done
  fi

  echo -e "${BOLD}└─────────────────────────────���───────────────────────────���┘${NC}"
  echo ""

  # Confirm
  read -rp "$(echo -e "${BOLD}Proceed with this plan? [Y/n]${NC}: ")" response
  if [[ "$response" =~ ^[Nn] ]]; then
    # Offer walkthrough or manual edit
    echo ""
    local config_choice
    config_choice=$(prompt_choice "How would you like to configure tools?" \
      "Guided walkthrough (step through each category)" \
      "Edit .claude/tool-preferences.json manually")

    if [ "$config_choice" = "Guided walkthrough (step through each category)" ]; then
      run_tool_walkthrough "$resolver_output" "$dev_os"
      # Re-resolve after walkthrough
      resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
        --dev-os "$dev_os" \
        --platform "$PLATFORM" \
        --language "$LANGUAGE" \
        --track "$TRACK" \
        --phase 2 \
        --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" \
        --tool-prefs "$PROJECT_DIR/.claude/tool-preferences.json" 2>/dev/null) || true
    else
      # Write defaults and let user edit
      write_tool_preferences "$resolver_output" "$dev_os" "$PROJECT_DIR"
      echo ""
      print_info "Default preferences written to: $PROJECT_DIR/.claude/tool-preferences.json"
      print_info "Edit the file, then press Enter to continue."
      read -rp ""
      # Re-resolve after manual edit
      resolver_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
        --dev-os "$dev_os" \
        --platform "$PLATFORM" \
        --language "$LANGUAGE" \
        --track "$TRACK" \
        --phase 2 \
        --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" \
        --tool-prefs "$PROJECT_DIR/.claude/tool-preferences.json" 2>/dev/null) || true
    fi
  fi

  # Execute auto-installs
  auto_count=$(echo "$resolver_output" | jq '.auto_install | length')
  if [ "$auto_count" -gt 0 ]; then
    print_step "Installing tools..."
    for i in $(seq 0 $((auto_count - 1))); do
      local tool_name tool_cmd
      tool_name=$(echo "$resolver_output" | jq -r ".auto_install[$i].name")
      tool_cmd=$(echo "$resolver_output" | jq -r ".auto_install[$i].install_cmd")
      print_info "Installing $tool_name..."
      if eval "$tool_cmd" 2>/dev/null; then
        print_ok "$tool_name installed"
      else
        print_warn "Could not install $tool_name. Install manually: $tool_cmd"
      fi
    done
  fi

  # Show manual install reminders
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  if [ "$manual_count" -gt 0 ]; then
    echo ""
    print_info "Manual setup required for:"
    for i in $(seq 0 $((manual_count - 1))); do
      local tool_name instructions
      tool_name=$(echo "$resolver_output" | jq -r ".manual_install[$i].name")
      instructions=$(echo "$resolver_output" | jq -r ".manual_install[$i].instructions")
      echo "  • $tool_name ��� $instructions"
    done
  fi

  # Write tool-preferences.json (will be in PROJECT_DIR after create_project makes it)
  # Store resolver output for later use by create_project
  RESOLVER_OUTPUT="$resolver_output"
  RESOLVER_DEV_OS="$dev_os"

  echo ""
  print_ok "Tool resolution complete."
}

run_tool_walkthrough() {
  local resolver_output="$1"
  local dev_os="$2"

  # Get unique substitution categories from auto_install + manual_install
  local categories
  categories=$(echo "$resolver_output" | jq -r '[(.auto_install + .manual_install)[] | select(.category != null) | .category] | unique | .[]')

  local prefs_substitutions="{}"
  local prefs_skipped="[]"

  for category in $categories; do
    local tool_name
    tool_name=$(echo "$resolver_output" | jq -r "(.auto_install + .manual_install)[] | select(.category == \"$category\") | .name" | head -1)

    echo ""
    local choice
    choice=$(prompt_choice "$category:" \
      "$tool_name (recommended)" \
      "Other (enter name and check command)" \
      "Skip")

    case "$choice" in
      *recommended*)
        # Keep default — no action needed
        ;;
      *Other*)
        local custom_name custom_check
        custom_name=$(prompt_input "Tool name" "")
        custom_check=$(prompt_input "Check command (shell command that returns 0 if installed)" "command -v $custom_name")
        prefs_substitutions=$(echo "$prefs_substitutions" | jq \
          --arg cat "$category" \
          --arg default "$tool_name" \
          --arg selected "$custom_name" \
          --arg check "$custom_check" \
          '. + {($cat): {default: $default, selected: $selected, check_command: $check}}')
        ;;
      *Skip*)
        prefs_skipped=$(echo "$prefs_skipped" | jq \
          --arg name "$tool_name" \
          --arg cat "$category" \
          '. + [{name: $name, category: $cat, reason: "Skipped during walkthrough"}]')
        ;;
    esac
  done

  # Write preferences
  mkdir -p "$PROJECT_DIR/.claude"
  local today
  today=$(date +%Y-%m-%d)
  jq -n \
    --arg version "1.0" \
    --arg date "$today" \
    --arg dev_os "$dev_os" \
    --arg platform "$PLATFORM" \
    --arg language "$LANGUAGE" \
    --arg track "$TRACK" \
    --argjson substitutions "$prefs_substitutions" \
    --argjson skipped "$prefs_skipped" \
    '{
      schema_version: $version,
      resolved_at: $date,
      context: {dev_os: $dev_os, platform: $platform, language: $language, track: $track},
      substitutions: $substitutions,
      additions: [],
      skipped: $skipped,
      installed: {}
    }' > "$PROJECT_DIR/.claude/tool-preferences.json"
}

write_tool_preferences() {
  local resolver_output="$1"
  local dev_os="$2"
  local project_dir="$3"

  mkdir -p "$project_dir/.claude"
  local today
  today=$(date +%Y-%m-%d)

  # Build installed list from already_installed
  local installed_phase_0 installed_phase_1
  installed_phase_0=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category == "version_control" or .category == "json_processor" or .category == "runtime" or .category == "containerization" or .category == "commit_signing") | .name]')
  installed_phase_1=$(echo "$resolver_output" | jq '[.already_installed[] | select(.category != "version_control" and .category != "json_processor" and .category != "containerization" and .category != "commit_signing") | .name]')

  jq -n \
    --arg version "1.0" \
    --arg date "$today" \
    --arg dev_os "$dev_os" \
    --arg platform "$PLATFORM" \
    --arg language "$LANGUAGE" \
    --arg track "$TRACK" \
    --argjson phase_0 "$installed_phase_0" \
    --argjson phase_1 "$installed_phase_1" \
    '{
      schema_version: $version,
      resolved_at: $date,
      context: {dev_os: $dev_os, platform: $platform, language: $language, track: $track},
      substitutions: {},
      additions: [],
      skipped: [],
      installed: {phase_0: $phase_0, phase_1: $phase_1}
    }' > "$project_dir/.claude/tool-preferences.json"
}
```

- [ ] **Step 2: Update `main()` to call `resolve_and_install_tools` instead of the old functions**

Replace lines 1738-1739 in `main()`:

Old:
```bash
    install_language_runtime
    install_tools
```

New:
```bash
    resolve_and_install_tools
```

- [ ] **Step 3: Update `create_project()` to write tool-preferences.json and intake summary**

After the line `cat > .claude/phase-state.json << PHEOF` block (around line 745), add:

```bash
  # Write tool-preferences.json (from resolver output stored earlier)
  if [ -n "${RESOLVER_OUTPUT:-}" ]; then
    write_tool_preferences "$RESOLVER_OUTPUT" "$RESOLVER_DEV_OS" "$PROJECT_DIR"
    print_ok "Tool preferences written to .claude/tool-preferences.json"
  fi
```

After the line that copies the intake template (`cp "$SCRIPT_DIR/templates/project-intake.md" PROJECT_INTAKE.md`), add:

```bash
  # Append tooling configuration summary to PROJECT_INTAKE.md
  if [ -n "${RESOLVER_OUTPUT:-}" ]; then
    append_intake_tooling_summary "$RESOLVER_OUTPUT"
  fi
```

- [ ] **Step 4: Add `append_intake_tooling_summary()` function**

Add before the `main()` function:

```bash
append_intake_tooling_summary() {
  local resolver_output="$1"

  cat >> PROJECT_INTAKE.md << 'TOOLHDR'

---

## Tooling Configuration

> Auto-generated by init.sh. Full machine-readable config: `.claude/tool-preferences.json`

TOOLHDR

  # Resolved for
  echo "**Resolved for:** $(uname -s) / $PLATFORM / $LANGUAGE / $TRACK track" >> PROJECT_INTAKE.md
  echo "" >> PROJECT_INTAKE.md

  # Installed table
  local installed_count
  installed_count=$(echo "$resolver_output" | jq '.already_installed | length')
  if [ "$installed_count" -gt 0 ]; then
    echo "### Installed" >> PROJECT_INTAKE.md
    echo "| Tool | Category | Version |" >> PROJECT_INTAKE.md
    echo "|---|---|---|" >> PROJECT_INTAKE.md
    echo "$resolver_output" | jq -r '.already_installed[] | "| \(.name) | \(.category) | \(.version) |"' >> PROJECT_INTAKE.md
    echo "" >> PROJECT_INTAKE.md
  fi

  # Manual setup table
  local manual_count
  manual_count=$(echo "$resolver_output" | jq '.manual_install | length')
  if [ "$manual_count" -gt 0 ]; then
    echo "### Manual Setup Required" >> PROJECT_INTAKE.md
    echo "| Tool | Category | Instructions |" >> PROJECT_INTAKE.md
    echo "|---|---|---|" >> PROJECT_INTAKE.md
    echo "$resolver_output" | jq -r '.manual_install[] | "| \(.name) | \(.category) | \(.instructions) |"' >> PROJECT_INTAKE.md
    echo "" >> PROJECT_INTAKE.md
  fi

  # Deferred table
  local deferred_count
  deferred_count=$(echo "$resolver_output" | jq '.deferred | length')
  if [ "$deferred_count" -gt 0 ]; then
    echo "### Deferred (Phase 3+)" >> PROJECT_INTAKE.md
    echo "| Tool | Phase | Category |" >> PROJECT_INTAKE.md
    echo "|---|---|---|" >> PROJECT_INTAKE.md
    echo "$resolver_output" | jq -r '.deferred[] | "| \(.name) | \(.phase) | \(.category) |"' >> PROJECT_INTAKE.md
    echo "" >> PROJECT_INTAKE.md
  fi
}
```

- [ ] **Step 5: Update `dry_run_summary()` to use the resolver**

Replace the tools section in `dry_run_summary()` (lines 1649-1659) with:

```bash
  echo -e "${BOLD}Tool Resolution:${NC}"
  local dev_os
  case "$(uname -s)" in Darwin) dev_os="darwin" ;; *) dev_os="linux" ;; esac
  local dry_output
  dry_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
    --dev-os "$dev_os" \
    --platform "$PLATFORM" \
    --language "$LANGUAGE" \
    --track "$TRACK" \
    --phase 2 \
    --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" 2>/dev/null) || {
    echo "  (resolver unavailable — cannot preview tools)"
    return
  }
  echo "$dry_output" | jq -r '.already_installed[] | "  [already installed] \(.name) \(.version)"'
  echo "$dry_output" | jq -r '.auto_install[] | "  [WILL INSTALL] \(.name) (\(.description))"'
  echo "$dry_output" | jq -r '.manual_install[] | "  [MANUAL] \(.name) — \(.instructions)"'
  echo "$dry_output" | jq -r '.deferred[] | "  [DEFERRED Phase \(.phase)] \(.name) (\(.description))"'
```

- [ ] **Step 6: Update `health_check()` to read from tool-preferences.json**

Replace the tool-checking section in `health_check()` (lines 1484-1507) with:

```bash
  # Check tools via tool-preferences.json
  if [ -f ".claude/tool-preferences.json" ]; then
    print_ok "Tool preferences file present"
    # Re-run resolver to check current state
    local dev_os
    case "$(uname -s)" in Darwin) dev_os="darwin" ;; *) dev_os="linux" ;; esac
    local health_output
    health_output=$("$SCRIPT_DIR/scripts/resolve-tools.sh" \
      --dev-os "$dev_os" \
      --platform "$PLATFORM" \
      --language "$LANGUAGE" \
      --track "$TRACK" \
      --phase 2 \
      --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" \
      --tool-prefs ".claude/tool-preferences.json" 2>/dev/null) || true

    if [ -n "$health_output" ]; then
      local missing_required
      missing_required=$(echo "$health_output" | jq '[(.auto_install + .manual_install)[] | select(.required == true) | .name]')
      local missing_count
      missing_count=$(echo "$missing_required" | jq 'length')
      if [ "$missing_count" -gt 0 ]; then
        echo "$missing_required" | jq -r '.[]' | while IFS= read -r tool; do
          print_warn "$tool not found"
          ((warnings++))
        done
      fi
      echo "$health_output" | jq -r '.already_installed[] | .name' | while IFS= read -r tool; do
        print_ok "$tool accessible"
      done
    fi
  else
    # Fallback: basic tool checks (for projects created before matrix system)
    command -v claude &>/dev/null && print_ok "Claude Code accessible" || { print_warn "Claude Code not found"; ((warnings++)); }
    command -v semgrep &>/dev/null && print_ok "Semgrep accessible" || { print_warn "Semgrep not found"; ((warnings++)); }
    command -v gitleaks &>/dev/null && print_ok "gitleaks accessible" || { print_warn "gitleaks not found"; ((warnings++)); }
    command -v snyk &>/dev/null && print_ok "Snyk accessible" || { print_warn "Snyk not found"; ((warnings++)); }
  fi
```

- [ ] **Step 7: Commit**

```bash
git add init.sh
git commit -m "feat(init): replace flat tool install with matrix-driven resolver

Remove install_tools() and install_language_runtime(). Add
resolve_and_install_tools() that calls resolve-tools.sh, displays
a grouped installation plan, supports Y/n → walkthrough/manual-edit
flow, writes tool-preferences.json, and appends tooling summary
to PROJECT_INTAKE.md."
```

---

### Task 7: Add Phase Gate Tool Resolution

**Files:**
- Modify: `scripts/check-phase-gate.sh`

- [ ] **Step 1: Add tool resolution check to check-phase-gate.sh**

Add the following after line 104 (after the `fi` closing the Phase 3→4 check) and before the summary output at line 106:

```bash
# --- Tool Resolution Check (for phase transitions) ---
# If transitioning to a new phase, check for deferred tools that are now needed
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$SCRIPT_DIR/scripts/resolve-tools.sh"
TOOL_PREFS=".claude/tool-preferences.json"

if [ -f "$TOOL_PREFS" ] && [ -x "$RESOLVER" ] && command -v jq &>/dev/null; then
  dev_os=$(jq -r '.context.dev_os' "$TOOL_PREFS" 2>/dev/null || echo "")
  platform=$(jq -r '.context.platform' "$TOOL_PREFS" 2>/dev/null || echo "")
  language=$(jq -r '.context.language' "$TOOL_PREFS" 2>/dev/null || echo "")
  track=$(jq -r '.context.track' "$TOOL_PREFS" 2>/dev/null || echo "")

  if [ -n "$dev_os" ] && [ -n "$platform" ] && [ -n "$language" ] && [ -n "$track" ]; then
    # Resolve for the current phase
    tool_output=$("$RESOLVER" \
      --dev-os "$dev_os" \
      --platform "$platform" \
      --language "$language" \
      --track "$track" \
      --phase "$current_phase" \
      --matrix-dir "$SCRIPT_DIR/templates/tool-matrix" \
      --tool-prefs "$TOOL_PREFS" 2>/dev/null) || tool_output=""

    if [ -n "$tool_output" ]; then
      missing_required=$(echo "$tool_output" | jq '[(.auto_install + .manual_install)[] | select(.required == true)]')
      missing_count=$(echo "$missing_required" | jq 'length')

      if [ "$missing_count" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}Required tools missing for Phase $current_phase:${NC}"
        echo "$missing_required" | jq -r '.[] | "  • \(.name) (\(.category))"'
        echo ""
        echo "Run the tool resolver to install:"
        echo "  bash $RESOLVER --dev-os $dev_os --platform $platform --language $language --track $track --phase $current_phase --matrix-dir $SCRIPT_DIR/templates/tool-matrix --tool-prefs $TOOL_PREFS"
        ((issues++))
      fi
    fi
  fi
fi
```

- [ ] **Step 2: Commit**

```bash
git add scripts/check-phase-gate.sh
git commit -m "feat(gate): add tool resolution check at phase transitions

check-phase-gate.sh now calls resolve-tools.sh to detect required
tools that are missing for the current phase. Surfaces missing
tools and provides the command to install them."
```

---

### Task 8: Add Tooling Configuration Placeholder to project-intake.md

**Files:**
- Modify: `templates/project-intake.md`

- [ ] **Step 1: Read the end of the intake template to find insertion point**

Run: `wc -l templates/project-intake.md`

- [ ] **Step 2: Append placeholder section to the template**

Add at the end of `templates/project-intake.md`:

```markdown

---

## 12. Tooling Configuration

> This section is auto-populated by `init.sh` based on the tool installation matrix. It records what was installed, what needs manual setup, and what is deferred to later phases. Claude reads this to understand the available tooling environment.
>
> If this section is empty, run `init.sh` or manually populate `.claude/tool-preferences.json`.

<!-- AUTO-GENERATED BY INIT.SH — do not edit above this line -->
```

- [ ] **Step 3: Commit**

```bash
git add templates/project-intake.md
git commit -m "feat(intake): add Tooling Configuration placeholder section

Section 12 is auto-populated by init.sh from the tool matrix
resolver output. Tells Claude what tools are available."
```

---

### Task 9: End-to-End Validation

**Files:**
- Read: all new/modified files

- [ ] **Step 1: Validate all JSON matrix files are well-formed**

Run: `for f in templates/tool-matrix/*.json; do echo -n "$f: "; jq '.' "$f" > /dev/null 2>&1 && echo "VALID" || echo "INVALID"; done`

Expected: All files show VALID.

- [ ] **Step 2: Test resolver with each platform**

Run:
```bash
for platform in web mobile desktop; do
  echo "=== $platform ==="
  bash scripts/resolve-tools.sh \
    --dev-os darwin --platform "$platform" --language typescript \
    --track standard --phase 2 --matrix-dir templates/tool-matrix 2>/dev/null | \
    jq '{auto: (.auto_install | length), manual: (.manual_install | length), installed: (.already_installed | length), deferred: (.deferred | length)}'
done
```

Expected: Each platform returns a JSON object with four numeric counts. No errors.

- [ ] **Step 3: Test resolver with phase filtering**

Run:
```bash
echo "=== Phase 2 (should have deferred) ==="
bash scripts/resolve-tools.sh \
  --dev-os darwin --platform web --language typescript \
  --track standard --phase 2 --matrix-dir templates/tool-matrix 2>/dev/null | \
  jq '.deferred[] | .name'

echo "=== Phase 4 (should have no deferred) ==="
bash scripts/resolve-tools.sh \
  --dev-os darwin --platform web --language typescript \
  --track standard --phase 4 --matrix-dir templates/tool-matrix 2>/dev/null | \
  jq '.deferred | length'
```

Expected: Phase 2 shows deferred tools (Playwright, k6, etc.). Phase 4 shows `0` deferred.

- [ ] **Step 4: Test resolver with track filtering**

Run:
```bash
echo "=== Light track (should NOT have k6) ==="
bash scripts/resolve-tools.sh \
  --dev-os darwin --platform web --language typescript \
  --track light --phase 4 --matrix-dir templates/tool-matrix 2>/dev/null | \
  jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | index("k6")'

echo "=== Full track (should have k6) ==="
bash scripts/resolve-tools.sh \
  --dev-os darwin --platform web --language typescript \
  --track full --phase 4 --matrix-dir templates/tool-matrix 2>/dev/null | \
  jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name] | index("k6")'
```

Expected: Light track returns `null` (no k6). Full track returns a number (k6 is present).

- [ ] **Step 5: Test resolver with language filtering**

Run:
```bash
echo "=== TypeScript (should have license-checker, NOT pip-licenses) ==="
bash scripts/resolve-tools.sh \
  --dev-os darwin --platform web --language typescript \
  --track standard --phase 4 --matrix-dir templates/tool-matrix 2>/dev/null | \
  jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name]'

echo "=== Python (should have pip-licenses, NOT license-checker) ==="
bash scripts/resolve-tools.sh \
  --dev-os darwin --platform web --language python \
  --track standard --phase 4 --matrix-dir templates/tool-matrix 2>/dev/null | \
  jq '[(.auto_install + .manual_install + .already_installed + .deferred)[] | .name]'
```

Expected: TypeScript list includes "license-checker" but not "pip-licenses". Python list includes "pip-licenses" but not "license-checker".

- [ ] **Step 6: Verify init.sh --dry-run works with new resolver**

Run: `bash init.sh --dry-run` (fill in prompts: test-project, web, standard, personal, typescript, /tmp/test-dry-run)

Expected: Dry run summary shows resolver-based tool output with `[already installed]`, `[WILL INSTALL]`, `[MANUAL]`, and `[DEFERRED]` prefixes instead of the old flat list.

- [ ] **Step 7: Commit validation results (if any test script was created)**

No commit needed — this is a manual verification step.

---

### Task 10: Copy Matrix Files into Created Projects

**Files:**
- Modify: `init.sh` (in `create_project()` function)

- [ ] **Step 1: Add matrix file copy to create_project()**

After the line that copies intake suggestions (`cp "$SCRIPT_DIR/templates/intake-suggestions/"*.json templates/intake-suggestions/`), add:

```bash
  # Copy tool matrix files (for phase gate and track upgrade resolution)
  mkdir -p templates/tool-matrix
  cp "$SCRIPT_DIR/templates/tool-matrix/"*.json templates/tool-matrix/
```

- [ ] **Step 2: Also copy resolve-tools.sh to the project**

After the existing `chmod +x scripts/validate.sh scripts/check-phase-gate.sh ...` line, add:

```bash
  cp "$SCRIPT_DIR/scripts/resolve-tools.sh" scripts/
  chmod +x scripts/resolve-tools.sh
```

- [ ] **Step 3: Update health_check() SCRIPT_DIR reference**

In the updated `health_check()` from Task 6, change `$SCRIPT_DIR/scripts/resolve-tools.sh` and `$SCRIPT_DIR/templates/tool-matrix` to use local paths (since these files are now copied into the project):

```bash
    health_output=$(scripts/resolve-tools.sh \
      --dev-os "$dev_os" \
      --platform "$PLATFORM" \
      --language "$LANGUAGE" \
      --track "$TRACK" \
      --phase 2 \
      --matrix-dir templates/tool-matrix \
      --tool-prefs ".claude/tool-preferences.json" 2>/dev/null) || true
```

- [ ] **Step 4: Commit**

```bash
git add init.sh
git commit -m "feat(init): copy tool matrix and resolver into created projects

Projects are self-contained after init: matrix files and
resolve-tools.sh are copied so phase gates and track upgrades
can re-resolve without referencing the orchestrator directory."
```

---

## Summary

| Task | What It Does |
|---|---|
| 1 | Create `common.json` — universal tools |
| 2 | Create `web.json` — web platform tools |
| 3 | Create `mobile.json` — mobile platform tools |
| 4 | Create `desktop.json` �� desktop platform tools |
| 5 | Create `resolve-tools.sh` — matrix resolver |
| 6 | Replace init.sh tool installation with resolver |
| 7 | Add tool resolution to phase gate checks |
| 8 | Add Tooling Configuration placeholder to intake template |
| 9 | End-to-end validation across platforms, phases, tracks, languages |
| 10 | Copy matrix files and resolver into created projects |

# Technical User Review Resolutions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve 7 actionable findings from the Technical Non-Developer Usability Review (items 2 and 7 merged into a single init.sh improvement).

**Architecture:** Documentation edits to README.md, docs/user-guide.md, and docs/cli-setup-addendum.md, plus bash scripting changes to init.sh. No methodology changes. No new files beyond this plan.

**Tech Stack:** Markdown, Bash

**Source document:** `technical-user-review-v1.md` (root of repo)

---

## File Map

| File | Action | Tasks |
|---|---|---|
| `init.sh` | Modify (lines 24-1233) | Task 1, Task 2 |
| `README.md` | Modify (lines 296-304, add new section) | Task 3 |
| `docs/user-guide.md` | Modify (lines 36-248, add new sections after line 627) | Task 4, Task 5, Task 6, Task 7 |
| `docs/cli-setup-addendum.md` | Modify (lines 356-362) | Task 6 |

---

### Task 1: init.sh — Add `--dry-run` flag and argument parsing

**Review finding:** "No dry-run mode. I cannot preview what init.sh will do without running it."

**Files:**
- Modify: `init.sh:24-36` (add flag variable after utility functions)
- Modify: `init.sh:1223-1233` (add argument parsing before `main` body)
- Modify: `init.sh:173-246` (wrap installs in dry-run check)
- Modify: `init.sh:251-400` (wrap project creation in dry-run check)

- [ ] **Step 1: Add DRY_RUN variable and argument parsing**

At the top of the script (after `set -euo pipefail`, before utility functions), add:

```bash
# ================================================================
# Flags
# ================================================================
DRY_RUN=false
```

Replace the `main "$@"` block at line 1223-1233 with:

```bash
main() {
  # Parse flags
  for arg in "$@"; do
    case "$arg" in
      --dry-run)
        DRY_RUN=true
        echo -e "${YELLOW}${BOLD}DRY RUN MODE — no changes will be made${NC}"
        echo ""
        ;;
      --help|-h)
        echo "Usage: ./init.sh [--dry-run] [--help]"
        echo ""
        echo "  --dry-run   Preview what will be installed and created without executing"
        echo "  --help      Show this help message"
        exit 0
        ;;
      *)
        echo "Unknown option: $arg"
        echo "Usage: ./init.sh [--dry-run] [--help]"
        exit 1
        ;;
    esac
  done

  print_header
  check_prerequisites
  collect_project_info

  if [ "$DRY_RUN" = true ]; then
    dry_run_summary
  else
    install_tools
    create_project
    health_check
    print_next_steps
  fi
}

main "$@"
```

- [ ] **Step 2: Add the `dry_run_summary` function**

Add before `main()` (after `print_next_steps`):

```bash
# ================================================================
dry_run_summary() {
  echo ""
  print_step "DRY RUN SUMMARY"
  echo ""

  echo -e "${BOLD}Project:${NC}"
  echo "  Name:      $PROJECT_NAME"
  echo "  Platform:  $PLATFORM"
  echo "  Track:     $TRACK"
  echo "  Language:  $LANGUAGE"
  echo "  Directory: $PROJECT_DIR"
  echo ""

  echo -e "${BOLD}Tools to install (if missing):${NC}"
  command -v semgrep &>/dev/null && echo "  [already installed] Semgrep" || echo "  [WILL INSTALL] Semgrep (SAST scanner)"
  command -v gitleaks &>/dev/null && echo "  [already installed] gitleaks" || echo "  [WILL INSTALL] gitleaks (secret detection)"
  command -v snyk &>/dev/null && echo "  [already installed] Snyk CLI" || echo "  [WILL INSTALL] Snyk CLI (dependency vulnerability scanner)"
  command -v claude &>/dev/null && echo "  [already installed] Claude Code" || echo "  [WILL INSTALL] Claude Code (AI coding agent)"
  if [ "$PLATFORM" = "web" ]; then
    command -v lighthouse &>/dev/null && echo "  [already installed] Lighthouse" || echo "  [WILL INSTALL] Lighthouse (performance auditing)"
    if command -v docker &>/dev/null; then
      docker image inspect zaproxy/zap-stable &>/dev/null 2>&1 && echo "  [already installed] OWASP ZAP" || echo "  [WILL INSTALL] OWASP ZAP Docker image (DAST scanner)"
    fi
  fi
  echo ""

  echo -e "${BOLD}Files to create in $PROJECT_DIR/:${NC}"
  echo "  CLAUDE.md                           — Agent instructions"
  echo "  PROJECT_INTAKE.md                   — Product definition template"
  echo "  APPROVAL_LOG.md                     — Phase gate approval record"
  echo "  .github/workflows/ci.yml            — CI pipeline ($LANGUAGE)"
  echo "  .github/workflows/release.yml       — Release pipeline ($PLATFORM)"
  echo "  .gitignore                          — Language + platform ignores"
  echo "  .claude/framework/                  — Development Guardrails (git hooks)"
  echo "  .claude/phase-state.json            — Phase tracking"
  echo "  docs/framework/builders-guide.md    — Builder's Guide"
  echo "  docs/framework/governance-framework.md"
  echo "  docs/framework/executive-review.md"
  echo "  docs/framework/cli-setup-addendum.md"
  echo "  docs/platform-modules/              — Platform-specific guidance"
  echo "  docs/test-results/                  — Empty (populated in Phase 3)"
  echo "  scripts/validate.sh                 — Validation script"
  echo "  scripts/check-phase-gate.sh         — Phase gate checker"
  echo ""

  echo -e "${BOLD}Post-init steps (you do these manually):${NC}"
  echo "  1. cd $PROJECT_DIR"
  echo "  2. claude          # OAuth authentication"
  echo "  3. snyk auth       # Snyk authentication"
  echo "  4. Fill out PROJECT_INTAKE.md"
  echo ""
  echo -e "${GREEN}Re-run without --dry-run to execute.${NC}"
}
```

- [ ] **Step 3: Verify dry-run works**

Run: `cd "/Users/karl/Documents/AI Projects/solo-orchestrator" && ./init.sh --dry-run`

Expected: Script prompts for project info, then prints the summary without creating files or installing tools.

- [ ] **Step 4: Verify --help works**

Run: `./init.sh --help`

Expected: Prints usage message and exits.

- [ ] **Step 5: Verify normal mode still works**

Run: `./init.sh` (answer prompts, use a temp directory, then delete the test project)

Expected: Same behavior as before — tools install, project created, health check runs.

- [ ] **Step 6: Commit**

```bash
git add init.sh
git commit -m "feat(init): add --dry-run and --help flags

Resolves technical review finding: users cannot preview what
init.sh will do without executing it."
```

---

### Task 2: init.sh — Auto-install prerequisites with user prompting

**Review finding:** "The init script gets close to but does not fully achieve 'install WSL and run the script.' Git and the language runtime are hard prerequisites that the script validates but does not install."

**Merged with:** "Init script error messages — exact commands instead of URLs" and "better gitleaks fallback on Linux."

**Files:**
- Modify: `init.sh:67-120` (`check_prerequisites` function)
- Modify: `init.sh:173-246` (`install_tools` function)

- [ ] **Step 1: Add a `prompt_install` helper function**

Add after the existing `prompt_choice` function (after line 62):

```bash
# Prompt user to install a missing tool. Returns 0 if installed, 1 if skipped.
prompt_install() {
  local tool_name="$1"
  local install_cmd="$2"
  local needs_sudo="${3:-false}"

  echo ""
  if [ "$needs_sudo" = true ]; then
    echo -e "  ${YELLOW}This requires administrator privileges (sudo).${NC}"
  fi
  read -rp "$(echo -e "  ${BOLD}Install $tool_name now? [Y/n]${NC}: ")" response
  if [[ "$response" =~ ^[Nn] ]]; then
    return 1
  fi

  echo -e "  Running: ${CYAN}$install_cmd${NC}"
  if eval "$install_cmd"; then
    print_ok "$tool_name installed"
    return 0
  else
    print_warn "Installation failed. Install manually: $install_cmd"
    return 1
  fi
}
```

- [ ] **Step 2: Rewrite `check_prerequisites` with auto-install prompts**

Replace the `check_prerequisites` function (lines 67-120) with:

```bash
# ================================================================
check_prerequisites() {
  print_step "Checking prerequisites..."
  local os_type
  os_type="$(uname -s)"
  local missing_required=()

  # --- Git (required) ---
  if command -v git &>/dev/null; then
    print_ok "Git $(git --version | awk '{print $3}')"
  else
    print_fail "Git not found"
    local git_installed=false
    if [ "$os_type" = "Darwin" ]; then
      if command -v brew &>/dev/null; then
        prompt_install "Git" "brew install git" && git_installed=true
      else
        echo "  Install with: xcode-select --install (includes Git)"
        echo "  Or install Homebrew first: https://brew.sh"
        prompt_install "Git (via Xcode CLI Tools)" "xcode-select --install" && git_installed=true
      fi
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        prompt_install "Git" "sudo apt install -y git" true && git_installed=true
      elif command -v dnf &>/dev/null; then
        prompt_install "Git" "sudo dnf install -y git" true && git_installed=true
      else
        echo "  Install manually: use your distribution's package manager to install git"
      fi
    fi
    if [ "$git_installed" = false ]; then
      missing_required+=("git")
    fi
  fi

  # --- Node.js (required for JS/TS, recommended for others) ---
  if command -v node &>/dev/null; then
    local node_version
    node_version=$(node --version | sed 's/v//')
    local node_major
    node_major=$(echo "$node_version" | cut -d. -f1)
    if [ "$node_major" -ge 18 ]; then
      print_ok "Node.js $node_version"
    else
      print_warn "Node.js $node_version (18+ recommended)"
    fi
  else
    print_warn "Node.js not found"
    echo "  Node.js is required for JS/TS projects and used by some tooling (Snyk, license-checker)."
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      prompt_install "Node.js 22 LTS" "brew install node@22 && brew link --overwrite node@22"
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        prompt_install "Node.js" "sudo apt install -y nodejs npm" true
      elif command -v dnf &>/dev/null; then
        prompt_install "Node.js" "sudo dnf install -y nodejs npm" true
      else
        echo "  Install manually: https://nodejs.org/ or use your distribution's package manager"
      fi
    fi
  fi

  # --- Docker (optional) ---
  if command -v docker &>/dev/null; then
    print_ok "Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
  else
    print_warn "Docker not found (optional — needed for OWASP ZAP DAST scanning)"
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      echo "  Install with: brew install --cask docker"
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        echo "  Install with: sudo apt install -y docker.io && sudo usermod -aG docker \$USER"
      elif command -v dnf &>/dev/null; then
        echo "  Install with: sudo dnf install -y docker && sudo usermod -aG docker \$USER"
      fi
    fi
  fi

  # --- GPG (optional) ---
  if command -v gpg &>/dev/null; then
    print_ok "GPG available (commit signing)"
  else
    print_warn "GPG not found (optional — used for commit signing)"
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      echo "  Install with: brew install gnupg"
    elif [ "$os_type" = "Linux" ]; then
      if command -v apt &>/dev/null; then
        echo "  Install with: sudo apt install -y gnupg"
      elif command -v dnf &>/dev/null; then
        echo "  Install with: sudo dnf install -y gnupg2"
      fi
    fi
  fi

  if [ ${#missing_required[@]} -gt 0 ]; then
    print_fail "Missing required prerequisites: ${missing_required[*]}"
    echo "  Install them and re-run init.sh."
    exit 1
  fi

  echo ""
  print_ok "All required prerequisites met."
}
```

- [ ] **Step 3: Update `install_tools` — add gitleaks binary download for Linux**

Replace the gitleaks block (lines 190-200) with:

```bash
  # gitleaks
  if command -v gitleaks &>/dev/null; then
    print_ok "gitleaks $(gitleaks version 2>/dev/null)"
  else
    print_info "Installing gitleaks..."
    if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
      brew install gitleaks
    elif [ "$os_type" = "Linux" ]; then
      # Download the latest binary from GitHub Releases
      local gl_version
      gl_version=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/')
      if [ -n "$gl_version" ]; then
        local arch
        arch=$(uname -m)
        case "$arch" in
          x86_64) arch="x64" ;;
          aarch64|arm64) arch="arm64" ;;
        esac
        local gl_url="https://github.com/gitleaks/gitleaks/releases/download/v${gl_version}/gitleaks_${gl_version}_linux_${arch}.tar.gz"
        echo "  Downloading gitleaks $gl_version..."
        curl -sL "$gl_url" | tar xz -C /usr/local/bin gitleaks 2>/dev/null || \
        curl -sL "$gl_url" | sudo tar xz -C /usr/local/bin gitleaks 2>/dev/null || \
        print_warn "Could not install gitleaks. Install manually: https://github.com/gitleaks/gitleaks/releases"
      else
        print_warn "Could not determine latest gitleaks version. Install manually: https://github.com/gitleaks/gitleaks/releases"
      fi
    else
      print_warn "Install gitleaks manually: https://github.com/gitleaks/gitleaks/releases"
    fi
  fi
```

- [ ] **Step 4: Update `install_tools` — add language runtime auto-install after project info is collected**

Add a new function `install_language_runtime` after `install_tools`, to be called from `main` after `collect_project_info`:

```bash
# ================================================================
install_language_runtime() {
  local os_type
  os_type="$(uname -s)"

  case "$LANGUAGE" in
    typescript|javascript)
      if ! command -v node &>/dev/null; then
        print_warn "Node.js is required for $LANGUAGE projects."
        if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
          prompt_install "Node.js 22 LTS" "brew install node@22 && brew link --overwrite node@22"
        elif [ "$os_type" = "Linux" ] && command -v apt &>/dev/null; then
          prompt_install "Node.js" "sudo apt install -y nodejs npm" true
        elif [ "$os_type" = "Linux" ] && command -v dnf &>/dev/null; then
          prompt_install "Node.js" "sudo dnf install -y nodejs npm" true
        else
          echo "  Install Node.js 18+: https://nodejs.org/"
        fi
      fi ;;
    python)
      if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        print_warn "Python is required for $LANGUAGE projects."
        if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
          prompt_install "Python 3" "brew install python"
        elif [ "$os_type" = "Linux" ] && command -v apt &>/dev/null; then
          prompt_install "Python 3" "sudo apt install -y python3 python3-pip python3-venv" true
        elif [ "$os_type" = "Linux" ] && command -v dnf &>/dev/null; then
          prompt_install "Python 3" "sudo dnf install -y python3 python3-pip" true
        else
          echo "  Install Python 3.12+: https://python.org/"
        fi
      fi ;;
    rust)
      if ! command -v cargo &>/dev/null; then
        print_warn "Rust is required for $LANGUAGE projects."
        prompt_install "Rust (via rustup)" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source \"\$HOME/.cargo/env\""
      fi ;;
    go)
      if ! command -v go &>/dev/null; then
        print_warn "Go is required for $LANGUAGE projects."
        if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
          prompt_install "Go" "brew install go"
        elif [ "$os_type" = "Linux" ] && command -v apt &>/dev/null; then
          prompt_install "Go" "sudo apt install -y golang" true
        elif [ "$os_type" = "Linux" ] && command -v dnf &>/dev/null; then
          prompt_install "Go" "sudo dnf install -y golang" true
        else
          echo "  Install Go: https://go.dev/dl/"
        fi
      fi ;;
    csharp)
      if ! command -v dotnet &>/dev/null; then
        print_warn ".NET SDK is required for $LANGUAGE projects."
        if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
          prompt_install ".NET SDK" "brew install dotnet"
        else
          echo "  Install .NET SDK: https://dotnet.microsoft.com/download"
        fi
      fi ;;
    kotlin|java)
      if ! command -v java &>/dev/null; then
        print_warn "Java is required for $LANGUAGE projects."
        if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
          prompt_install "Java (Eclipse Temurin)" "brew install temurin"
        elif [ "$os_type" = "Linux" ] && command -v apt &>/dev/null; then
          prompt_install "Java (OpenJDK)" "sudo apt install -y default-jdk" true
        elif [ "$os_type" = "Linux" ] && command -v dnf &>/dev/null; then
          prompt_install "Java (OpenJDK)" "sudo dnf install -y java-latest-openjdk-devel" true
        else
          echo "  Install Java: https://adoptium.net/"
        fi
      fi ;;
    dart)
      if ! command -v flutter &>/dev/null; then
        print_warn "Flutter SDK is required for $LANGUAGE projects."
        if [ "$os_type" = "Darwin" ] && command -v brew &>/dev/null; then
          prompt_install "Flutter" "brew install flutter"
        else
          echo "  Install Flutter: https://docs.flutter.dev/get-started/install"
        fi
      fi ;;
  esac
}
```

Update the non-dry-run path in `main()` to call this:

```bash
  if [ "$DRY_RUN" = true ]; then
    dry_run_summary
  else
    install_language_runtime
    install_tools
    create_project
    health_check
    print_next_steps
  fi
```

- [ ] **Step 5: Test the auto-install prompting**

On macOS with Homebrew, verify:
- Missing tools show the correct `brew install ...` command
- Answering `n` skips installation without error
- Answering `Y` (or Enter) runs the install command

Run: `./init.sh` (on a system where all tools are already installed)

Expected: All tools show as already installed; no install prompts appear.

- [ ] **Step 6: Commit**

```bash
git add init.sh
git commit -m "feat(init): auto-install prerequisites with user prompting

Prerequisites (Git, Node.js, language runtimes) now offer to install
automatically with platform-specific commands. User is prompted before
each install. Also improves gitleaks installation on Linux by downloading
the binary from GitHub Releases instead of printing a URL.

Resolves technical review findings: prerequisite auto-installation,
exact install commands instead of URLs, gitleaks Linux fallback."
```

---

### Task 3: README — Add adoption decision tree and revise audience description

**Review findings:** "A decision tree for when NOT to use this framework" and "Replace the abstract 'experienced technologist' label with specific concrete skills."

**Files:**
- Modify: `README.md` — add new section after "What This Is Not" (after line 304), revise lines 126-132

- [ ] **Step 1: Add the decision tree after "What This Is Not"**

After line 304 (end of "What This Is Not" section), add:

```markdown
## Should You Use This Framework?

| Question | If Yes | If No |
|---|---|---|
| **Will your project have more than 3 features?** | Continue below | Use Claude Code with a well-written CLAUDE.md |
| **Will it handle user authentication or sensitive data?** | **Use the framework** (Standard or Full track) | Continue below |
| **Will other people use it?** | **Use the framework** (Standard or Light track) | Continue below |
| **Will you maintain it for more than 6 months?** | **Use the framework** (Light track) | Use Claude Code with a CLAUDE.md |

For enterprise/organizational use: always use the framework. The governance artifacts alone justify the overhead.
```

- [ ] **Step 2: Revise the audience description**

The README currently describes audiences at lines 126-132 in a table with broad labels. Add a concrete skills list below the existing table. After the audience table, add:

```markdown
**Minimum skills assumed:**
- Navigate a terminal (cd, ls, running commands)
- Basic Git operations (clone, commit, push, pull, branches)
- Read code well enough to identify obvious problems
- Understand what a test is and how pass/fail works
- Edit JSON and YAML files
- For web projects: understand HTTP status codes and request/response basics
```

- [ ] **Step 3: Verify links and formatting**

Run: `cd "/Users/karl/Documents/AI Projects/solo-orchestrator" && head -350 README.md | tail -60`

Expected: New sections are properly formatted and positioned.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): add adoption decision tree and concrete skill requirements

Adds a 'Should You Use This Framework?' decision tree to help users
determine whether to use the full framework, light track, or just
Claude Code with a CLAUDE.md. Also adds an explicit minimum skills
list replacing the abstract 'experienced technologist' label.

Resolves technical review findings: framework adoption decision tree,
clearer minimum skill statement."
```

---

### Task 4: User Guide Section 1 — Add knowledge prerequisites checklist and revise skill statement

**Review findings:** "Minimum viable knowledge checklist" and "Clearer minimum skill statement."

**Files:**
- Modify: `docs/user-guide.md:48-52` (revise "What This Framework Expects of You")
- Modify: `docs/user-guide.md:110` (add new subsection before 1.1)

- [ ] **Step 1: Revise "What This Framework Expects of You"**

Replace lines 48-52 with:

```markdown
### What This Framework Expects of You

You are a technically literate person who can navigate a terminal, use Git, read code, and run command-line tools. The AI writes the code. You make every decision, validate every output, and gate every phase transition.

This is not a tool for learning to program. If you cannot look at AI-generated code and determine whether it is roughly correct, the framework's quality controls will not compensate for that gap.

#### Self-Assessment Checklist

Before starting, confirm you can do the following. If more than 2 items are unfamiliar, invest time learning them first.

- [ ] Navigate a terminal: `cd`, `ls`, run commands, read output
- [ ] Basic Git: clone a repo, make commits, push, create branches
- [ ] Understand what a test is and interpret pass/fail output
- [ ] Read code well enough to spot obvious problems (wrong variable, missing check, hardcoded secret)
- [ ] Edit JSON and YAML files without breaking their syntax
- [ ] Understand what an API is and how HTTP request/response works (for web projects)
- [ ] Install software from the command line (npm, pip, brew, apt, or equivalent)
- [ ] Read a stack trace or error message and identify the relevant line
```

- [ ] **Step 2: Verify the edit renders correctly**

Run: Read `docs/user-guide.md` lines 48-65 to confirm formatting.

- [ ] **Step 3: Commit**

```bash
git add docs/user-guide.md
git commit -m "docs(user-guide): add self-assessment checklist and concrete skill requirements

Replaces abstract 'experienced technologist' description with a
concrete self-assessment checklist of minimum skills. Users can
now self-evaluate readiness before investing time.

Resolves technical review findings: minimum viable knowledge checklist,
clearer minimum skill statement."
```

---

### Task 5: User Guide Section 2 — Add config provenance table and CLAUDE.md version note

**Review findings:** "Auto-generated vs. manual config table" and "Document the relationship between init-generated starter CLAUDE.md and the enhanced template."

**Files:**
- Modify: `docs/user-guide.md:210-243` (add after "Each project is self-contained" line, before "Post-Init Authentication")
- Modify: `docs/cli-setup-addendum.md:356-362` (add note in Section 6 header)

- [ ] **Step 1: Add configuration provenance table to User Guide Section 2**

After line 212 ("CI pipelines are working GitHub Actions workflows...release pipelines are production-ready templates..."), before the "### What to Check After Init" heading, add:

```markdown
### What Is Auto-Generated vs. What You Configure

| File | Created By | You Must | Notes |
|---|---|---|---|
| `CLAUDE.md` | init.sh (starter version) | Update at each phase transition and end of each session | Replace with the enhanced template from the [CLI Setup Addendum](cli-setup-addendum.md#6-claudemd) when you configure optional enhancements |
| `PROJECT_INTAKE.md` | init.sh (blank template) | Fill out completely before Phase 0 | The primary input to the entire process |
| `APPROVAL_LOG.md` | init.sh (empty with headers) | Add entries at each phase gate | Append-only — never edit previous entries |
| `.github/workflows/ci.yml` | init.sh (language-specific) | Nothing — works on first push | Modify only if adding a secondary language |
| `.github/workflows/release.yml` | init.sh (platform-specific) | Configure secrets and signing before first release | Contains `TODO` markers for per-project configuration |
| `.gitignore` | init.sh | Nothing | Add entries as needed |
| `.claude/framework/` | init.sh (cloned from GitHub) | Nothing | Git hooks are auto-installed |
| `.claude/phase-state.json` | init.sh | Nothing — updated by scripts | Tracks current phase |
| `docs/framework/` | init.sh (copied from solo-orchestrator) | Nothing | Reference documents |
| `docs/platform-modules/` | init.sh (copied) | Nothing | Platform-specific guidance |
| **Superpowers** | You (optional) | Install plugin, configure in CLAUDE.md | See [CLI Setup Addendum](cli-setup-addendum.md#1-superpowers) |
| **Context7 MCP** | You (optional) | One command to add MCP server | See [CLI Setup Addendum](cli-setup-addendum.md#4-context7) |
| **Qdrant MCP** | You (optional) | Docker + MCP server config | See [CLI Setup Addendum](cli-setup-addendum.md#5-qdrant) |
```

- [ ] **Step 2: Add CLAUDE.md version note to CLI Setup Addendum**

In `docs/cli-setup-addendum.md`, in the Section 6 "What It Is" block (lines 356-362), add after the existing description:

```markdown
**Relationship to init-generated CLAUDE.md:** The init script generates a minimal starter CLAUDE.md with your project name, description, and basic agent instructions. The template below is the full version with Superpowers integration, Context7 usage instructions, Qdrant memory triggers, and phase-evolving sections. **When you configure any optional enhancement (Superpowers, Context7, or Qdrant), replace the init-generated CLAUDE.md with this template** and fill in the project-specific sections.
```

- [ ] **Step 3: Verify both edits**

Read the relevant sections to confirm formatting and accuracy.

- [ ] **Step 4: Commit**

```bash
git add docs/user-guide.md docs/cli-setup-addendum.md
git commit -m "docs: add config provenance table and CLAUDE.md version guidance

Adds a table to the User Guide showing which files are auto-generated,
which require manual configuration, and which are optional. Adds
explicit guidance to the CLI Setup Addendum explaining when to replace
the init-generated CLAUDE.md with the enhanced template.

Resolves technical review findings: auto-generated vs. manual config
table, CLAUDE.md version confusion."
```

---

### Task 6: User Guide — Excerpt Builder's Guide execution content for self-sufficiency

**Review finding:** "The User Guide is not yet the standalone document it is intended to be. It is an excellent high-level walkthrough that requires the Builder's Guide as a companion reference during execution."

This is the largest task. The goal is to incorporate the execution-critical elements from the Builder's Guide into the User Guide so a user does not need both documents open simultaneously. The Builder's Guide remains the deep reference.

**Files:**
- Modify: `docs/user-guide.md:397-627` (Phase walkthrough sections — add inline excerpts)

**What to excerpt (from Builder's Guide into User Guide):**
1. Phase 0 prompts (the actual text you paste into Claude Code) — BG lines 260-415
2. Phase 1 architecture prompt — BG lines 520-546
3. Build Loop steps (2.2-2.6) — BG lines 782-857
4. Context Health Check protocol — BG lines 859-867
5. All 5 remediation tables — BG lines 471-479, 657-668, 908-920, 1078-1088, 1237-1246
6. Issue Resolution Quick Reference — BG lines 1249-1264

**Strategy:** Add collapsible `<details>` sections within each phase so the User Guide doesn't become overwhelming, but the content is there when needed.

- [ ] **Step 1: Add Phase 0 prompts to User Guide Phase 0 section**

After the existing Phase 0 content (around line 420), before the Phase 0 → Phase 1 gate, add:

```markdown
<details>
<summary><strong>Phase 0 — Agent Prompts (click to expand)</strong></summary>

Use these prompts with your AI agent. Choose "With Intake" versions if you filled out the Project Intake first (recommended), or "Without Intake" versions for conversational discovery.

#### Step 0.1: Functional Feature Set

**With Intake (recommended):**
```
I am the Solo Orchestrator for [PROJECT NAME]. The attached Project
Intake contains my requirements and constraints.

Using the Intake as the primary source, generate a Functional
Requirements Document.

For each Must-Have feature:
1. Expand the business logic trigger into a complete specification.
2. Expand the failure state into a complete error/recovery flow.
3. Identify contradictions between features.
4. Identify implicit dependencies I haven't listed.

For the Will-Not-Have list: flag if any Must-Have implicitly requires
something on the exclusion list.

Do not add features beyond the Intake. Flag recommendations separately.
```

**Without Intake:**
```
I am the Solo Orchestrator for [PROJECT NAME]. Before we discuss code
or technology, we need to define the Feature Set.

Act as a Lead Product Manager with 15 years of experience. Based on
my goal of [INSERT GOAL], generate a Functional Requirements Document.

CONSTRAINTS:
- Budget: [$ per month for hosting/services, or one-time budget]
- Timeline: [X weeks to MVP]
- Target users at launch: [number]
- Target users at 12 months: [number]

REQUIREMENTS:
1. List the Must-Have features for MVP. For each: "If [condition],
   the system must [action] and output [result]."
2. List the Should-Have features for v1.1.
3. List the Will-Not-Have features (explicit scope boundaries).
4. For every Must-Have, define the failure state.
```

#### Step 0.2: User Personas & Interaction Flow

**With Intake:**
```
Using the Intake persona (Section 2.2) and Must-Have features (Section 4.1),
generate a complete User Journey Map.

Map the Success Path through ALL Must-Have features as a coherent experience.
For each step: what user sees, does, system responds, feedback mechanism.
Define failure recovery using the failure states from the Intake.
Flag any point where the journey reveals a feature gap.
```

**Without Intake:**
```
Map the User Journey for the primary persona.

1. Persona: Who, skill level, goal, emotional state on arrival.
2. Entry Point: How they first encounter the application.
3. Success Path: 3-5 steps. For each: what user sees, does, system responds.
4. Failure Recovery: At each step, what happens on bad input, lost connectivity, or abandonment.
5. Feedback Loops: How the app communicates success/failure/progress. Mechanism specifics.
6. Exit Points: Where the user might abandon. Recovery strategies.
```

#### Step 0.3: Data Input/Output & State Logic

**With Intake:**
```
Using the Intake data definitions (Section 5), generate a formal Data Contract.

Verify validation rules are complete. Confirm sensitivity classifications.
Identify inputs implied by features but not listed. Define data flow from
input to storage to output. Flag integrations where "unavailable" breaks
a Must-Have. Review persistence model against budget constraints.
```

**Without Intake:**
```
Define the Data Contract.

1. INPUTS: Data type, validation rules, sensitivity classification per input.
2. TRANSFORMATIONS: Each processing step as a discrete operation.
3. OUTPUTS: Format, latency expectation per output.
4. THIRD-PARTY DATA: APIs/sources, fallback if unavailable, caching.
5. STATE: What persists across sessions vs. ephemeral.
   Define the boundary between "stored permanently" and "stored in
   memory/local session."
```

#### Step 0.4: Product Manifesto & MVP Cutline

**With Intake:**
```
Synthesize into a Product Manifesto. Use the Intake problem statement
(Section 2.1) as the foundation. MVP Cutline reflects Intake Section 4.1,
adjusted for any changes from Steps 0.1-0.3. If recommending a feature
move (Must-Have → Should-Have or vice versa), state the recommendation
and reason — do not change the cutline without my approval.

Include Open Questions: anything flagged during Steps 0.1-0.3 that
requires my decision before Phase 1.
```

**Without Intake:**
```
Combine the FRD, User Journeys, and Data Contracts into a Product Manifesto.

1. Product Intent: One paragraph — what and why.
2. MVP Cutline: Hard line. Only first-release features. Everything else
   goes to Post-MVP Backlog.
3. Manifesto Rules:
   - Architecture that contradicts the Manifesto is rejected.
   - Features not in the MVP Cutline are not built in Phase 2.
   - Post-MVP prioritized by user feedback, not this document.

Confirm: "I will use this Manifesto as my primary constraint."
```

</details>

<details>
<summary><strong>Phase 0 — Remediation Table (click to expand)</strong></summary>

| Issue | Detection | Response |
|---|---|---|
| **Feature Creep** | AI suggests features not in the Manifesto | "Not in the Manifesto. Not in Phase 2. Move to Post-MVP Backlog." |
| **Vague Logic** | AI says "the system handles the data" without specifics | "Be specific. Input format? Validation? Storage? User feedback on success and failure?" |
| **Missing Failure States** | User journey has no error/recovery path | "What happens on invalid data at Step [X]? Define the error feedback loop and recovery." |
| **Platform Scope Creep** | AI suggests multi-platform before validating single-platform | "Ship on one platform first. Add others after the core product works." |

</details>
```

- [ ] **Step 2: Add Phase 1 architecture prompt to User Guide Phase 1 section**

After the existing Phase 1 content (around line 453), add:

```markdown
<details>
<summary><strong>Phase 1 — Architecture Selection Prompt (click to expand)</strong></summary>

```
Based on the attached Product Manifesto, propose 3 architecture options.

CONSTRAINTS:
- Stack familiarity: [from Intake Section 6.1 or state here]
- Budget ceiling: [from Revenue Model or Intake Section 3.2]
- Solo maintainer — prioritize managed services, minimal infrastructure.
- Target MVP timeline: [X weeks].
- Target platforms: [from Intake — e.g., "Windows, macOS, Linux" or
  "Web" or "iOS and Android"]

For EACH option, include ALL of the following as first-class decisions:
1. Languages & Frameworks (exact versions)
2. Data storage strategy (justified by the data contracts)
3. Application architecture pattern
4. Authentication & Identity strategy (if applicable)
5. Observability: structured logging, error reporting. Day 1 decisions.
6. Secrets management
7. Build & packaging strategy for all target platforms
8. Scalability vs. Velocity trade-off
9. Distribution strategy (how users get the application)
10. Auto-update mechanism (if applicable)

[APPEND PLATFORM-SPECIFIC REQUIREMENTS FROM YOUR PLATFORM MODULE]
```

</details>

<details>
<summary><strong>Phase 1 — Remediation Table (click to expand)</strong></summary>

| Issue | Detection | Response |
|---|---|---|
| **Over-Engineering** | AI suggests complex infrastructure for an MVP | "Solo maintainer with a $[X] ceiling. Simplify." |
| **Platform Mismatch** | Architecture doesn't match target platform constraints | "This must run as [platform requirement]. Redesign for that constraint." |
| **Security Gaps** | AI omits auth, data isolation, or encryption | "Missing [control]. Rewrite. Non-negotiable." |
| **Shallow Threat Model** | STRIDE analysis is generic | "These threats must be specific to our architecture. How does [vector] apply to [our stack]?" |
| **Missing Observability** | No logging, error tracking, or monitoring | "Observability is Day 1. Define logging, correlation IDs, error reporting now." |
| **Missing Build Strategy** | No plan for packaging/distributing on all target platforms | "How does this get to the user on [platform]? Define the build and distribution pipeline." |
| **Maintenance Overload** | Architecture requires DevOps the Orchestrator can't maintain | "Simplify. I cannot maintain this." |

</details>
```

- [ ] **Step 3: Add Build Loop procedures to User Guide Phase 2 section**

Within the Phase 2 section (around line 520, after the existing Build Loop high-level description), add:

```markdown
<details>
<summary><strong>Phase 2 — Build Loop Procedures (click to expand)</strong></summary>

Repeat this cycle for each feature in the MVP Cutline:

**Step 2.2 — Write Tests First**

Direct the agent to write test cases based on the User Journey and Data Contract:
- Success state tests (descriptive names: `should [behavior] when [condition]`)
- Negative tests (invalid, empty, malicious input)
- Boundary tests (exact limits of acceptable input)

**DECISION GATE:** Review the test assertions. Write at least 3 test assertions yourself per feature that specifically test business logic — not just status codes or "response is not null." Confirm the tests fail (feature code doesn't exist yet).

**Step 2.3 — Implement the Feature**

1. Direct the agent to implement to pass all tests.
2. Run the test suite. All tests must pass.
3. Manual validation: verify the feature works as expected.
4. Direct specific fixes for any discrepancies.

**Step 2.4 — Security & Quality Audit**

1. Run SAST: `semgrep scan --config=p/owasp-top-ten --config=p/security-audit src/`
2. Review against the Phase 1 Threat Model.
3. Check: data isolation, input validation, hardcoded secrets, efficient data access, logging, platform-specific security.
4. Fix findings. Verify tests still pass.

**Step 2.5 — Update Documentation**

Direct the agent to update: CHANGELOG.md, interface documentation, architecture decision records, and the Project Bible.

**Step 2.6 — Data Model Changes (if needed)**

1. Generate a versioned migration with "apply" and "rollback" operations.
2. Apply. Verify existing tests pass.
3. Verify rollback cleanly reverts.
4. Update data model documentation in the Bible.

NEVER modify the data model directly. All changes go through the migration tool.

</details>

<details>
<summary><strong>Phase 2 — Context Health Check (every 3-4 features)</strong></summary>

Ask the agent to summarize: features built, features remaining, current data model, known issues. If the summary contains hallucinated features, incorrect references, or contradicts the Bible:

1. Start a fresh session.
2. Provide the updated `PROJECT_BIBLE.md` and the last 3-4 active files.
3. "We are continuing Phase 2. Here is the current state."

If the AI produces consistently low-quality output across multiple attempts, end the session and start fresh. Quality variance between sessions is real.

</details>

<details>
<summary><strong>Phase 2 — Remediation Table (click to expand)</strong></summary>

| Issue | Detection | Response |
|---|---|---|
| **Context Window Bleed** | AI hallucinates variables, forgets structure | Fresh session with Bible + last 3-4 active files |
| **Dependency Creep** | New package for every small problem | "Achieve this with the existing stack. Justify any new dependency." |
| **Logic Circularity** | AI rewrites the same bug in circles | "Stop coding. Explain the logic step-by-step. Find the flaw before fixing syntax." |
| **Silent Failures** | Code runs but errors are swallowed | "Every failure must produce a structured log entry and user-visible feedback." |
| **Regression** | Feature B breaks Feature A | "Run full suite. Identify conflict. Fix preserving both. Do not delete tests." |
| **Data Model Modified Directly** | Schema changed outside migration tool | "Revert. Generate a versioned migration. Apply through the tool." |
| **Architecture Wrong Mid-Build** | Construction reveals architecture can't support a requirement | Stop Phase 2. Return to Phase 1.2. Revise Bible. Expensive but cheaper than finishing wrong. |
| **Platform Inconsistency** | Works on one OS but not another | "Run tests on all target platforms. Fix platform-specific issues before continuing." |

</details>
```

- [ ] **Step 4: Add Phase 3 and Phase 4 remediation tables**

After the Phase 3 content (around line 582), add:

```markdown
<details>
<summary><strong>Phase 3 — Remediation Table (click to expand)</strong></summary>

| Issue | Detection | Response |
|---|---|---|
| **Logic Drift** | App works but doesn't solve the Phase 0 problem | "Strayed from Manifesto. Remove [Feature X]. Re-align." |
| **Silent Errors** | App fails without user feedback | "Error boundaries. Every failure shows recovery suggestion." |
| **Security Regression** | Change broke auth or data isolation | "Full security audit from 3.2. Non-negotiable." |
| **Accessibility Failures** | Below target scores or broken keyboard navigation | "Address every finding. Ship nothing below target." |
| **Performance Regression** | Below target on any metric | "Profile and audit. Address largest bottleneck first." |
| **Cross-Platform Failure** | Works on one platform, broken on another | "Fix before proceeding. All target platforms must pass." |

</details>
```

After the Phase 4 content (around line 627), add:

```markdown
<details>
<summary><strong>Phase 4 — Remediation Table (click to expand)</strong></summary>

| Issue | Detection | Response |
|---|---|---|
| **Build Failure** | CI fails on one or more platforms | "Isolate the platform. Fix on a branch. Full test suite before merging." |
| **Environment Mismatch** | Works in dev, fails in production | "Diff configurations. Check platform-specific settings." |
| **Cost Spike** | Hosting/distribution costs exceed ceiling | "Identify the resource. Optimize or restructure." |
| **Dependency Break** | Update breaks the app | "Revert to last tagged release. Fix on a branch." |
| **Rollback Failure** | Rollback procedure doesn't work | "Fix the runbook first. Broken runbook is higher priority than broken feature." |

</details>
```

- [ ] **Step 5: Add Issue Resolution Quick Reference before the Troubleshooting section**

Before Section 9 (Troubleshooting & FAQ, around line 854), add:

```markdown
### Quick Reference — Common Issues

| Issue | Detection Signal | Response |
|---|---|---|
| **Context Window Bleed** | AI hallucinates variables, forgets structure | Fresh session with Bible + last 3-4 active files |
| **Code Drift** | Feature works but contradicts the Bible | Stop. Re-inject Bible. Realign before continuing. |
| **Logic Drift** | App works but doesn't solve Phase 0 problem | Re-read Manifesto to AI. Remove non-Manifesto features. |
| **Feature Creep** | AI suggests features outside MVP Cutline | "Not in the Cutline. Not in Phase 2. Post-MVP Backlog." |
| **Dependency Creep** | New package for every small problem | "Achieve with existing stack. Justify any new dependency." |
| **Security Regression** | Change broke auth or data isolation | Re-run Phase 3.2. Non-negotiable. |
| **Rollback Failure** | Procedure doesn't work | Fix runbook first. Higher priority than broken feature. |
| **AI Quality Variance** | Consistently poor output in a session | End session, start fresh. Quality varies across sessions. |
| **Architecture Wrong Mid-Build** | Can't support a requirement | Stop Phase 2. Return to Phase 1.2. Revise Bible. |
```

- [ ] **Step 6: Update the Document Map to reflect User Guide self-sufficiency**

In the Document Map table (line 25), change the Builder's Guide entry from:

```markdown
| [**Builder's Guide**](builders-guide.md) | The complete methodology — phases, prompts, remediation tables, glossary | During every phase |
```

to:

```markdown
| [**Builder's Guide**](builders-guide.md) | The complete methodology — deep reference for phases, glossary, and advanced procedures | When you need detail beyond what this guide provides |
```

- [ ] **Step 7: Verify all `<details>` tags render correctly**

Read the modified sections of `docs/user-guide.md` and verify:
- Each `<details>` block has a matching `</details>`
- Code blocks inside details are properly fenced
- Tables render correctly inside details blocks

- [ ] **Step 8: Commit**

```bash
git add docs/user-guide.md
git commit -m "docs(user-guide): incorporate execution content from Builder's Guide

Adds collapsible sections with Phase 0/1 prompts, Build Loop procedures,
Context Health Check protocol, all 5 remediation tables, and the Issue
Resolution Quick Reference. The User Guide is now self-sufficient for
execution — the Builder's Guide remains as the deep reference.

Resolves the top-priority technical review finding: User Guide
self-sufficiency."
```

---

### Task 7: Final verification and resolution log

- [ ] **Step 1: Create the resolution tracking entry**

Add to the technical review document or create a note documenting which findings were resolved:

| Review Finding | Resolution | Task |
|---|---|---|
| User Guide not self-sufficient | Excerpted prompts, Build Loop, remediation tables, quick reference | Task 6 |
| Init script: exact commands instead of URLs | Auto-install with prompting, platform-specific commands | Task 2 |
| CLAUDE.md version confusion | Added provenance table + note in CLI Setup Addendum | Task 5 |
| Auto-generated vs. manual config table | Added table to User Guide Section 2 | Task 5 |
| Minimum viable knowledge checklist | Added self-assessment checklist to User Guide Section 1 | Task 4 |
| Framework adoption decision tree | Added decision tree to README | Task 3 |
| `--dry-run` flag for init.sh | Implemented with full summary output | Task 1 |
| Clearer minimum skill statement | Revised in User Guide and README | Tasks 3, 4 |

- [ ] **Step 2: Verify the full document suite is internally consistent**

Spot-check:
- README decision tree references match User Guide track names
- User Guide config table matches what init.sh actually generates
- CLI Setup Addendum CLAUDE.md note is consistent with User Guide config table
- All cross-document links still resolve

- [ ] **Step 3: Commit the resolution log**

```bash
git add -A
git commit -m "docs: complete technical user review resolutions

Resolves 7 actionable findings from the Technical Non-Developer
Usability Review across 4 files: init.sh, README.md,
docs/user-guide.md, and docs/cli-setup-addendum.md."
```

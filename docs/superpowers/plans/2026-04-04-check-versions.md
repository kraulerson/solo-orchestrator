# Session-Start Version Check — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a session-start version checker that verifies minimum versions, shows latest available, and offers interactive updates with user approval.

**Architecture:** `scripts/check-versions.sh` reads `min_version` and `latest_check` fields from the existing tool matrix JSON files. It checks installed versions locally (always works), attempts latest version lookups (network, skips if offline), displays a grouped report, and offers interactive update. CLAUDE.md instructs the agent to run it at every session start.

**Tech Stack:** Bash, jq, curl (for latest version lookups), npm/pip/brew CLIs

**Spec:** `docs/superpowers/specs/2026-04-03-check-versions-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|---|---|
| `scripts/check-versions.sh` | Session-start version checker with interactive update prompt |

### Modified Files
| File | Change |
|---|---|
| `templates/tool-matrix/common.json` | Add `min_version` and `latest_check` to all 18 tool entries |
| `templates/tool-matrix/web.json` | Add `min_version` and `latest_check` to all 6 tool entries |
| `templates/tool-matrix/mobile.json` | Add `min_version` and `latest_check` to all 8 tool entries |
| `templates/tool-matrix/desktop.json` | Add `min_version` and `latest_check` to all 10 tool entries |
| `templates/generated/claude-md.tmpl` | Add Session Start instruction block |
| `scripts/resume.sh` | Include version check in resume output |
| `init.sh` | Copy check-versions.sh to projects, add to chmod list |

---

### Task 1: Add min_version and latest_check to Tool Matrix Files

**Files:**
- Modify: `templates/tool-matrix/common.json`
- Modify: `templates/tool-matrix/web.json`
- Modify: `templates/tool-matrix/mobile.json`
- Modify: `templates/tool-matrix/desktop.json`

- [ ] **Step 1: Update common.json**

Add `min_version` and `latest_check` fields to every tool entry. Use `jq` to add the fields. Here are the values for each tool:

| Tool | min_version | latest_check method | latest_check package |
|---|---|---|---|
| Git | `"2.30.0"` | `none` | — |
| jq | `"1.6"` | `{"method":"brew","package":"jq"}` | |
| Node.js | `"18.17.0"` | `none` | — |
| Docker | `null` | `none` | — |
| GPG | `null` | `none` | — |
| Semgrep | `"1.50.0"` | `{"method":"pip","package":"semgrep"}` | |
| gitleaks | `"8.18.0"` | `{"method":"github_release","package":"gitleaks/gitleaks"}` | |
| Snyk CLI | `"1.1290.0"` | `{"method":"npm","package":"snyk"}` | |
| Claude Code | `"2.0.0"` | `{"method":"npm","package":"@anthropic-ai/claude-code"}` | |
| Superpowers | `null` | `null` | — |
| Context7 MCP | `null` | `{"method":"npm","package":"@upstash/context7-mcp"}` | |
| Qdrant MCP | `null` | `null` | — |
| Python 3 | `"3.10.0"` | `null` | — |
| Rust | `"1.70.0"` | `null` | — |
| Go | `"1.21.0"` | `null` | — |
| .NET SDK | `"7.0.0"` | `null` | — |
| Java (Eclipse Temurin) | `"17.0.0"` | `null` | — |
| Flutter SDK | `"3.10.0"` | `null` | — |

For each tool, add both fields right after `version_command`. Use `jq` to transform:

```bash
cd templates/tool-matrix
# For each tool in common.json, add the two new fields
# This must be done carefully per-tool since values differ
```

Since the values differ per tool, the cleanest approach is to read the file, and use jq to add fields by tool name. Create a temporary jq script:

```bash
jq '
.tools |= [.[] |
  if .name == "Git" then . + {"min_version": "2.30.0", "latest_check": null}
  elif .name == "jq" then . + {"min_version": "1.6", "latest_check": {"method": "brew", "package": "jq"}}
  elif .name == "Node.js" then . + {"min_version": "18.17.0", "latest_check": null}
  elif .name == "Docker" then . + {"min_version": null, "latest_check": null}
  elif .name == "GPG" then . + {"min_version": null, "latest_check": null}
  elif .name == "Semgrep" then . + {"min_version": "1.50.0", "latest_check": {"method": "pip", "package": "semgrep"}}
  elif .name == "gitleaks" then . + {"min_version": "8.18.0", "latest_check": {"method": "github_release", "package": "gitleaks/gitleaks"}}
  elif .name == "Snyk CLI" then . + {"min_version": "1.1290.0", "latest_check": {"method": "npm", "package": "snyk"}}
  elif .name == "Claude Code" then . + {"min_version": "2.0.0", "latest_check": {"method": "npm", "package": "@anthropic-ai/claude-code"}}
  elif .name == "Superpowers" then . + {"min_version": null, "latest_check": null}
  elif .name == "Context7 MCP" then . + {"min_version": null, "latest_check": {"method": "npm", "package": "@upstash/context7-mcp"}}
  elif .name == "Qdrant MCP" then . + {"min_version": null, "latest_check": null}
  elif .name == "Python 3" then . + {"min_version": "3.10.0", "latest_check": null}
  elif .name == "Rust" then . + {"min_version": "1.70.0", "latest_check": null}
  elif .name == "Go" then . + {"min_version": "1.21.0", "latest_check": null}
  elif .name == ".NET SDK" then . + {"min_version": "7.0.0", "latest_check": null}
  elif .name == "Java (Eclipse Temurin)" then . + {"min_version": "17.0.0", "latest_check": null}
  elif .name == "Flutter SDK" then . + {"min_version": "3.10.0", "latest_check": null}
  else . + {"min_version": null, "latest_check": null}
  end
]' common.json > common.json.tmp && mv common.json.tmp common.json
```

- [ ] **Step 2: Update web.json**

```bash
jq '
.tools |= [.[] |
  if .name == "Lighthouse" then . + {"min_version": "11.0.0", "latest_check": {"method": "npm", "package": "lighthouse"}}
  elif .name == "OWASP ZAP" then . + {"min_version": null, "latest_check": null}
  elif .name == "license-checker" then . + {"min_version": "25.0.0", "latest_check": {"method": "npm", "package": "license-checker"}}
  elif .name == "pip-licenses" then . + {"min_version": "4.0.0", "latest_check": {"method": "pip", "package": "pip-licenses"}}
  elif .name == "Playwright" then . + {"min_version": null, "latest_check": {"method": "npm", "package": "playwright"}}
  elif .name == "k6" then . + {"min_version": "0.45.0", "latest_check": {"method": "brew", "package": "k6"}}
  else . + {"min_version": null, "latest_check": null}
  end
]' web.json > web.json.tmp && mv web.json.tmp web.json
```

- [ ] **Step 3: Update mobile.json**

```bash
jq '
.tools |= [.[] |
  if .name == "EAS CLI" then . + {"min_version": "7.0.0", "latest_check": {"method": "npm", "package": "eas-cli"}}
  elif .name == "Xcode Command Line Tools" then . + {"min_version": null, "latest_check": null}
  elif .name == "CocoaPods" then . + {"min_version": "1.12.0", "latest_check": {"method": "brew", "package": "cocoapods"}}
  elif .name == "Android Studio" then . + {"min_version": null, "latest_check": null}
  elif .name == "license-checker" then . + {"min_version": "25.0.0", "latest_check": {"method": "npm", "package": "license-checker"}}
  elif .name == "dart_license_checker" then . + {"min_version": null, "latest_check": null}
  elif .name == "Apple Developer Program" then . + {"min_version": null, "latest_check": null}
  elif .name == "Android Keystore" then . + {"min_version": null, "latest_check": null}
  else . + {"min_version": null, "latest_check": null}
  end
]' mobile.json > mobile.json.tmp && mv mobile.json.tmp mobile.json
```

- [ ] **Step 4: Update desktop.json**

```bash
jq '
.tools |= [.[] |
  if .name == "Tauri CLI" then . + {"min_version": "1.5.0", "latest_check": null}
  elif .name == "Xcode Command Line Tools" then . + {"min_version": null, "latest_check": null}
  elif .name == "Linux Desktop Build Dependencies" then . + {"min_version": null, "latest_check": null}
  elif .name == "license-checker" then . + {"min_version": "25.0.0", "latest_check": {"method": "npm", "package": "license-checker"}}
  elif .name == "cargo-license" then . + {"min_version": null, "latest_check": null}
  elif .name == "pip-licenses" then . + {"min_version": "4.0.0", "latest_check": {"method": "pip", "package": "pip-licenses"}}
  elif .name == "dart_license_checker" then . + {"min_version": null, "latest_check": null}
  elif .name == "dotnet-project-licenses" then . + {"min_version": null, "latest_check": null}
  else . + {"min_version": null, "latest_check": null}
  end
]' desktop.json > desktop.json.tmp && mv desktop.json.tmp desktop.json
```

- [ ] **Step 5: Validate all JSON files**

Run: `for f in templates/tool-matrix/*.json; do echo -n "$(basename $f): "; jq '.' "$f" > /dev/null 2>&1 && echo "VALID" || echo "INVALID"; done`

Expected: All VALID.

- [ ] **Step 6: Verify new fields are present**

Run: `jq '.tools[5] | {name, min_version, latest_check}' templates/tool-matrix/common.json`

Expected: Shows Semgrep with `min_version: "1.50.0"` and `latest_check: {method: "pip", package: "semgrep"}`.

- [ ] **Step 7: Commit**

```bash
git add templates/tool-matrix/*.json
git commit -m "feat(matrix): add min_version and latest_check to all tool entries

42 tools across 4 matrix files updated with minimum version
requirements and latest version lookup methods (npm, pip, brew,
github_release, git_tag). Used by check-versions.sh for session
start version checking."
```

---

### Task 2: Create check-versions.sh

**Files:**
- Create: `scripts/check-versions.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Session-Start Version Check
# Checks all tools against minimum versions and latest available.
# Reports status and offers interactive update with user approval.
#
# Usage:
#   scripts/check-versions.sh       # Full check + update prompt
#   scripts/check-versions.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/helpers.sh" ]; then
  source "$SCRIPT_DIR/lib/helpers.sh"
else
  if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
  else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
  fi
  print_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
  print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
  print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
  print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
fi

# --- Argument parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      echo "Usage: scripts/check-versions.sh [--help]"
      echo ""
      echo "Checks all tools against minimum version requirements and latest"
      echo "available versions. Offers interactive update with user approval."
      echo ""
      echo "Run at the start of every development session."
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Version comparison ---
# Returns 0 if $1 >= $2 (version A meets minimum B)
version_gte() {
  local a="$1" b="$2"
  # Strip common prefixes (v, jq-, etc.)
  a=$(echo "$a" | sed 's/^[^0-9]*//' | sed 's/[^0-9.].*//')
  b=$(echo "$b" | sed 's/^[^0-9]*//' | sed 's/[^0-9.].*//')

  if [ "$a" = "$b" ]; then return 0; fi

  local IFS='.'
  local -a av=($a) bv=($b)
  local max=${#av[@]}
  [ ${#bv[@]} -gt $max ] && max=${#bv[@]}

  for ((i=0; i<max; i++)); do
    local ai=${av[$i]:-0}
    local bi=${bv[$i]:-0}
    if [ "$ai" -gt "$bi" ] 2>/dev/null; then return 0; fi
    if [ "$ai" -lt "$bi" ] 2>/dev/null; then return 1; fi
  done
  return 0
}

# --- Latest version lookup ---
get_latest_version() {
  local method="$1"
  local package="$2"

  case "$method" in
    npm)
      npm view "$package" version 2>/dev/null | tr -d '[:space:]'
      ;;
    pip)
      # Use PyPI JSON API
      curl -s "https://pypi.org/pypi/$package/json" 2>/dev/null | jq -r '.info.version // empty' 2>/dev/null | tr -d '[:space:]'
      ;;
    brew)
      brew info --json=v2 "$package" 2>/dev/null | jq -r '.formulae[0].versions.stable // empty' 2>/dev/null | tr -d '[:space:]'
      ;;
    github_release)
      curl -s "https://api.github.com/repos/$package/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' | tr -d '[:space:]'
      ;;
    git_tag)
      git ls-remote --tags "$package" 2>/dev/null | grep -oP 'refs/tags/v?\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1 | tr -d '[:space:]'
      ;;
    *)
      echo ""
      ;;
  esac
}

# --- Load tool matrix ---
MATRIX_DIR="templates/tool-matrix"
if [ ! -d "$MATRIX_DIR" ]; then
  # Try from orchestrator source
  if [ -f ".claude/orchestrator-source.json" ] && command -v jq &>/dev/null; then
    src=$(jq -r '.source_dir // empty' ".claude/orchestrator-source.json" 2>/dev/null)
    [ -n "$src" ] && [ -d "$src/templates/tool-matrix" ] && MATRIX_DIR="$src/templates/tool-matrix"
  fi
fi

if [ ! -d "$MATRIX_DIR" ]; then
  print_fail "Tool matrix not found. Cannot check versions."
  exit 1
fi

# Load project context for filtering
PLATFORM=""
LANGUAGE=""
TRACK=""
if [ -f ".claude/tool-preferences.json" ] && command -v jq &>/dev/null; then
  PLATFORM=$(jq -r '.context.platform // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
  LANGUAGE=$(jq -r '.context.language // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
  TRACK=$(jq -r '.context.track // empty' ".claude/tool-preferences.json" 2>/dev/null || echo "")
fi

# --- Collect tools to check ---
# Load common.json + platform-specific
ALL_TOOLS=$(jq '.tools' "$MATRIX_DIR/common.json")
if [ -n "$PLATFORM" ] && [ -f "$MATRIX_DIR/${PLATFORM}.json" ]; then
  ALL_TOOLS=$(echo "$ALL_TOOLS" | jq --slurpfile p "$MATRIX_DIR/${PLATFORM}.json" '. + $p[0].tools')
fi

# Filter by language (skip language-specific tools for other languages)
if [ -n "$LANGUAGE" ]; then
  ALL_TOOLS=$(echo "$ALL_TOOLS" | jq --arg lang "$LANGUAGE" '[.[] | select(
    .languages == null or
    (.languages | index("all")) != null or
    (.languages | index($lang)) != null
  )]')
fi

# Only check tools that have a version_command (skip presence-only tools like Android Keystore)
CHECKABLE_TOOLS=$(echo "$ALL_TOOLS" | jq '[.[] | select(.version_command != null and .version_command != "" and .check_command != null)]')

# --- Check each tool ---
echo ""
echo -e "${BOLD}Solo Orchestrator — Version Check${NC}"
echo ""

BELOW_MIN=()
UPDATES=()
UPDATE_CMDS=()
PASS_COUNT=0
CURRENT_CATEGORY=""

TOOL_COUNT=$(echo "$CHECKABLE_TOOLS" | jq 'length')

if [ "$TOOL_COUNT" -eq 0 ]; then
  print_warn "No tools to check"
  exit 0
fi

# Check network availability once
NETWORK_AVAILABLE=true
if ! curl -s --max-time 3 "https://registry.npmjs.org" >/dev/null 2>&1; then
  NETWORK_AVAILABLE=false
  print_info "Network unavailable — latest version check skipped"
  echo ""
fi

for i in $(seq 0 $((TOOL_COUNT - 1))); do
  TOOL=$(echo "$CHECKABLE_TOOLS" | jq ".[$i]")
  NAME=$(echo "$TOOL" | jq -r '.name')
  CATEGORY=$(echo "$TOOL" | jq -r '.category')
  CHECK_CMD=$(echo "$TOOL" | jq -r '.check_command')
  VERSION_CMD=$(echo "$TOOL" | jq -r '.version_command // empty')
  MIN_VER=$(echo "$TOOL" | jq -r '.min_version // empty')
  LATEST_METHOD=$(echo "$TOOL" | jq -r '.latest_check.method // empty')
  LATEST_PKG=$(echo "$TOOL" | jq -r '.latest_check.package // empty')
  INSTALL_OBJ=$(echo "$TOOL" | jq -r '.install // empty')

  # Category header
  case "$CATEGORY" in
    version_control|json_processor|runtime|containerization|commit_signing)
      NEW_CAT="Core Tools" ;;
    sast|secret_detection|dependency_scanning)
      NEW_CAT="Security Tools" ;;
    ai_agent|claude_plugin|mcp_server)
      NEW_CAT="Plugins & MCP" ;;
    *)
      NEW_CAT="Project Tools" ;;
  esac
  if [ "$NEW_CAT" != "$CURRENT_CATEGORY" ]; then
    echo -e "${BOLD}── $NEW_CAT ──${NC}"
    CURRENT_CATEGORY="$NEW_CAT"
  fi

  # Check if installed
  if ! eval "$CHECK_CMD" &>/dev/null 2>&1; then
    print_warn "$NAME: not installed"
    continue
  fi

  # Get installed version
  INSTALLED=""
  if [ -n "$VERSION_CMD" ]; then
    INSTALLED=$(eval "$VERSION_CMD" 2>/dev/null | tr -d '[:space:]' || echo "")
  fi

  # Check minimum version
  MIN_MET=true
  MIN_DISPLAY=""
  if [ -n "$MIN_VER" ] && [ -n "$INSTALLED" ]; then
    MIN_DISPLAY=" (min: $MIN_VER)"
    if ! version_gte "$INSTALLED" "$MIN_VER"; then
      MIN_MET=false
    fi
  fi

  # Check latest version
  LATEST=""
  LATEST_DISPLAY=""
  if [ "$NETWORK_AVAILABLE" = true ] && [ -n "$LATEST_METHOD" ] && [ "$LATEST_METHOD" != "null" ] && [ -n "$LATEST_PKG" ]; then
    LATEST=$(get_latest_version "$LATEST_METHOD" "$LATEST_PKG")
  fi

  if [ -n "$LATEST" ] && [ -n "$INSTALLED" ]; then
    if version_gte "$INSTALLED" "$LATEST"; then
      LATEST_DISPLAY=" — up to date"
    else
      LATEST_DISPLAY=" — $LATEST available"
    fi
  elif [ -n "$INSTALLED" ] && [ "$NETWORK_AVAILABLE" = false ]; then
    LATEST_DISPLAY=""
  elif [ -n "$INSTALLED" ]; then
    LATEST_DISPLAY=" — up to date"
  fi

  # Output
  if [ "$MIN_MET" = false ]; then
    print_warn "$NAME: $INSTALLED$MIN_DISPLAY — BELOW MINIMUM$LATEST_DISPLAY"
    echo -e "         ${YELLOW}⚠ Continuing with outdated $NAME may cause issues.${NC}"
    BELOW_MIN+=("$NAME")
    # Find update command
    local_update_cmd=""
    if command -v brew &>/dev/null; then
      local_update_cmd=$(echo "$TOOL" | jq -r '.install.darwin_brew // empty')
    fi
    if [ -z "$local_update_cmd" ]; then
      local_update_cmd=$(echo "$TOOL" | jq -r '.install.npm // .install.linux_pip // .install.manual // empty')
    fi
    UPDATES+=("$NAME $INSTALLED → ${LATEST:-latest} (BELOW MINIMUM)")
    UPDATE_CMDS+=("$local_update_cmd")
  elif [ -n "$LATEST" ] && ! version_gte "$INSTALLED" "$LATEST"; then
    print_ok "$NAME: $INSTALLED$MIN_DISPLAY$LATEST_DISPLAY"
    # Find update command
    local_update_cmd=""
    if command -v brew &>/dev/null; then
      local_update_cmd=$(echo "$TOOL" | jq -r '.install.darwin_brew // empty')
    fi
    if [ -z "$local_update_cmd" ]; then
      local_update_cmd=$(echo "$TOOL" | jq -r '.install.npm // .install.linux_pip // .install.manual // empty')
    fi
    UPDATES+=("$NAME $INSTALLED → $LATEST")
    UPDATE_CMDS+=("$local_update_cmd")
    ((PASS_COUNT++))
  else
    print_ok "$NAME: ${INSTALLED:-configured}$MIN_DISPLAY$LATEST_DISPLAY"
    ((PASS_COUNT++))
  fi
done

# --- Summary ---
echo ""
echo -e "${BOLD}── Summary ──${NC}"
echo -e "  ${GREEN}✓ $PASS_COUNT up to date${NC}"
if [ ${#UPDATES[@]} -gt 0 ]; then
  echo -e "  ${CYAN}⬆ ${#UPDATES[@]} updates available${NC}"
fi
if [ ${#BELOW_MIN[@]} -gt 0 ]; then
  echo -e "  ${YELLOW}⚠ ${#BELOW_MIN[@]} below minimum (${BELOW_MIN[*]}) — update recommended before continuing${NC}"
fi

# --- Interactive update prompt ---
if [ ${#UPDATES[@]} -gt 0 ] && [ -t 0 ]; then
  echo ""
  echo -e "${BOLD}Updates available:${NC}"
  for idx in "${!UPDATES[@]}"; do
    echo "  $((idx+1)). ${UPDATES[$idx]}"
  done
  echo ""
  echo -e "${BOLD}Update options:${NC}"
  echo "  a) Update all ($(seq -s, 1 ${#UPDATES[@]}))"
  echo "  b) Select which to update (enter numbers: e.g., 1,3)"
  echo "  c) Skip for now"
  echo ""

  read -rp "$(echo -e "${BOLD}Choice [a/b/c]${NC}: ")" choice

  case "$choice" in
    a|A)
      echo ""
      for idx in "${!UPDATE_CMDS[@]}"; do
        cmd="${UPDATE_CMDS[$idx]}"
        uname="${UPDATES[$idx]%%  *}"
        uname="${uname%% *}"
        if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
          print_info "Updating $uname..."
          if eval "$cmd" 2>/dev/null; then
            print_ok "$uname updated"
          else
            print_fail "Could not update $uname. Run manually: $cmd"
          fi
        else
          print_warn "$uname: no auto-update command available"
        fi
      done
      ;;
    b|B)
      read -rp "Enter numbers (comma-separated): " selections
      IFS=',' read -ra sel_arr <<< "$selections"
      echo ""
      for sel in "${sel_arr[@]}"; do
        sel=$(echo "$sel" | tr -d '[:space:]')
        idx=$((sel - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#UPDATE_CMDS[@]} ]; then
          cmd="${UPDATE_CMDS[$idx]}"
          uname="${UPDATES[$idx]%%  *}"
          uname="${uname%% *}"
          if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
            print_info "Updating $uname..."
            if eval "$cmd" 2>/dev/null; then
              print_ok "$uname updated"
            else
              print_fail "Could not update $uname. Run manually: $cmd"
            fi
          fi
        fi
      done
      ;;
    c|C|*)
      if [ ${#UPDATES[@]} -gt 0 ]; then
        echo ""
        echo "Manual update commands:"
        for idx in "${!UPDATES[@]}"; do
          echo "  ${UPDATES[$idx]%%  *}: ${UPDATE_CMDS[$idx]}"
        done
      fi
      ;;
  esac
elif [ ${#UPDATES[@]} -gt 0 ]; then
  # Non-interactive: just print commands
  echo ""
  echo "Update commands (run manually):"
  for idx in "${!UPDATES[@]}"; do
    uname="${UPDATES[$idx]%%  *}"
    echo "  $name: ${UPDATE_CMDS[$idx]}"
  done
fi

# Exit code
if [ ${#BELOW_MIN[@]} -gt 0 ]; then
  exit 1
else
  exit 0
fi
```

- [ ] **Step 2: Make executable and validate**

Run: `chmod +x scripts/check-versions.sh && bash -n scripts/check-versions.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/check-versions.sh
git commit -m "feat(versions): add check-versions.sh session-start version checker

Checks installed versions against min_version from tool matrix.
Attempts latest version lookup via npm/pip/brew/GitHub API.
Interactive update prompt (all/select/skip). Exits 1 if any
tool is below minimum. Graceful offline handling."
```

---

### Task 3: Add Session Start to CLAUDE.md Template

**Files:**
- Modify: `templates/generated/claude-md.tmpl`

- [ ] **Step 1: Add Session Start instruction block**

Read the file. Find `## Operating Instructions`. Add immediately after that heading (before the first subsection like `### Phase Awareness`):

```markdown

### Session Start
At the start of every new session, before any other work:
1. Run `scripts/check-versions.sh` and report the results to the Orchestrator
2. If any tools are below minimum version, warn the Orchestrator and recommend updating before continuing
3. If updates are available, ask the Orchestrator if they want to update now
4. Do NOT proceed with Phase 2+ work if any required security tool (Semgrep, gitleaks, Snyk) is below minimum — recommend updating first
5. Do NOT auto-update anything — always ask first
```

- [ ] **Step 2: Commit**

```bash
git add templates/generated/claude-md.tmpl
git commit -m "feat(claude-md): add Session Start version check instruction

Agent runs check-versions.sh at every session start, reports
results, warns on below-minimum tools, asks before updating."
```

---

### Task 4: Update resume.sh to Include Version Check

**Files:**
- Modify: `scripts/resume.sh`

- [ ] **Step 1: Add version check output to resume prompt**

Read `scripts/resume.sh`. Find the `# --- Output the prompt ---` section (around line 63). Before the `cat <<PROMPT` line, add:

```bash
# Version check summary
VERSION_STATUS="(run scripts/check-versions.sh for details)"
if [ -x "scripts/check-versions.sh" ]; then
  # Quick check — just count below-minimum, don't do full interactive
  version_output=$(bash scripts/check-versions.sh 2>&1 </dev/null) || true
  below_min=$(echo "$version_output" | grep -c "BELOW MINIMUM" || echo "0")
  updates=$(echo "$version_output" | grep -c "available" || echo "0")
  if [ "$below_min" -gt 0 ]; then
    VERSION_STATUS="⚠ $below_min tool(s) below minimum version — run scripts/check-versions.sh"
  elif [ "$updates" -gt 0 ]; then
    VERSION_STATUS="⬆ $updates update(s) available — run scripts/check-versions.sh"
  else
    VERSION_STATUS="✓ All tools up to date"
  fi
fi
```

Then add to the PROMPT heredoc, after the `**Recent commits:**` section:

```
**Tool versions:** $VERSION_STATUS
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n scripts/resume.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/resume.sh
git commit -m "feat(resume): include version check status in session resume

Shows below-minimum warnings, available updates, or all-clear
status in the resume prompt alongside project state."
```

---

### Task 5: Update init.sh — Copy check-versions.sh to Projects

**Files:**
- Modify: `init.sh`

- [ ] **Step 1: Add check-versions.sh to copy list**

Read `init.sh`. Find the script copy section (around line 673-681). After the `cp "$SCRIPT_DIR/scripts/test-gate.sh" scripts/` line, add:

```bash
  cp "$SCRIPT_DIR/scripts/check-versions.sh" scripts/
```

Update the chmod line to include check-versions.sh.

- [ ] **Step 2: Validate syntax**

Run: `bash -n init.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add init.sh
git commit -m "feat(init): copy check-versions.sh to created projects

Projects include the version checker for session-start use."
```

---

### Task 6: End-to-End Validation

- [ ] **Step 1: Validate all modified scripts**

Run: `bash -n init.sh && bash -n scripts/check-versions.sh && bash -n scripts/resume.sh && echo "ALL OK"`
Expected: `ALL OK`

- [ ] **Step 2: Validate all matrix JSON files**

Run: `for f in templates/tool-matrix/*.json; do echo -n "$(basename $f): "; jq '.' "$f" > /dev/null 2>&1 && echo "VALID" || echo "INVALID"; done`
Expected: All VALID.

- [ ] **Step 3: Verify min_version fields are present**

Run: `jq '[.tools[] | {name, min_version}] | .[:5]' templates/tool-matrix/common.json`
Expected: First 5 tools show their min_version values.

- [ ] **Step 4: Run check-versions.sh from the project directory**

Run: `bash scripts/check-versions.sh`
Expected: Version report with Core Tools, Security Tools, Plugins & MCP sections. No crashes. Shows installed versions, minimum check results, and latest available (if online).

- [ ] **Step 5: No commit needed — validation only**

---

## Summary

| Task | What It Does |
|---|---|
| 1 | Add min_version + latest_check to all 42 tool matrix entries |
| 2 | Create check-versions.sh (version check + interactive update) |
| 3 | Add Session Start instruction to CLAUDE.md template |
| 4 | Update resume.sh with version status |
| 5 | Copy check-versions.sh to created projects via init.sh |
| 6 | End-to-end validation |
